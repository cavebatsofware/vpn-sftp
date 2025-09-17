networks:
  app-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

volumes:
  sftpgo-data:
    driver: local

services:
  coredns:
    image: "coredns/coredns:arm64-1.12.4"
    container_name: coredns
    command: ["-conf", "/etc/coredns/Corefile"]
    volumes:
      - /opt/docker-app/config/coredns:/etc/coredns:ro
    networks:
      app-network:
        ipv4_address: 172.20.0.53
    restart: unless-stopped

  sftpgo:
    image: "drakkan/sftpgo:latest"
    container_name: sftpgo
    user: "1000:1000"
    ports:
      - "${sftp_port}:2022"   # SFTP
      - "8080:8080"           # Web admin/UI
      - "8081:8081"           # WebDAV (optional)
    environment:
      - SFTPGO_DEFAULT_ADMIN_USERNAME=admin
      - SFTPGO_DEFAULT_ADMIN_PASSWORD_FILE=/run/secrets/sftpgo_admin_password
      - SFTPGO_DATA_PROVIDER__DRIVER=sqlite
      - SFTPGO_DATA_PROVIDER__NAME=/var/lib/sftpgo/sftpgo.db
      - SFTPGO_LOG__LEVEL=info
      # Explicitly enable REST API and Web Admin and set bindings
      - SFTPGO_HTTPD__ENABLE_REST_API=true
      - SFTPGO_HTTPD__ENABLE_WEB_ADMIN=true
      - SFTPGO_HTTPD__BINDINGS__0__ADDRESS=0.0.0.0
      - SFTPGO_HTTPD__BINDINGS__0__PORT=8080
      # Expose WebDAV on 8081
      - SFTPGO_WEBDAVD__BINDINGS__0__ADDRESS=0.0.0.0
      - SFTPGO_WEBDAVD__BINDINGS__0__PORT=8081
      - AWS_DEFAULT_REGION=${aws_region}
      # Default users to local storage under /data (s3fs bind mount)
      - SFTPGO_DEFAULTS__USER__FS_PROVIDER=0
      - SFTPGO_DEFAULTS__USER__HOME_DIR=/data
    volumes:
      - ${efs_mount_path}/sftpgo:/var/lib/sftpgo
      - ${s3_mount_path}:/data
      - /opt/docker-app/secrets/sftpgo_admin_password:/run/secrets/sftpgo_admin_password:ro
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "nc -z localhost 2022"]
      interval: 60s
      timeout: 10s
      retries: 5
      start_period: 30s

  wireguard:
    image: lscr.io/linuxserver/wireguard:latest
    container_name: wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    depends_on:
      - coredns
    dns:
      - 172.20.0.53
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - SERVERURL=${vpn_servername}
      - SERVERPORT=${wireguard_port}
      - PEERS=${wireguard_peers}
      - PEERDNS=172.20.0.53
      - ALLOWEDIPS=0.0.0.0/0
      - MTU=1400
      - POSTUP=sysctl -w net.ipv4.ip_forward=1; iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -j MASQUERADE
      - POSTDOWN=iptables -D FORWARD -i %i -j ACCEPT || true; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true; iptables -t nat -D POSTROUTING -j MASQUERADE || true
    volumes:
      - ${efs_mount_path}/wireguard:/config
    ports:
      - "${wireguard_port}:${wireguard_port}/udp"
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    networks:
      - app-network
    restart: unless-stopped

  personal-site:
    image: "${personal_site_image_url}"
    container_name: personal-site
    environment:
      - PORT=3000
      - RESUME_CODES=${resume_codes}
    ports:
      - "3000:3000"
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
