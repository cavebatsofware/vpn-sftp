networks:
  app-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

services:
  coredns:
    image: "coredns/coredns:1.13.1"
    container_name: coredns
    command: ["-conf", "/etc/coredns/Corefile"]
    volumes:
      - /opt/docker-app/config/coredns:/etc/coredns:ro
    networks:
      app-network:
        ipv4_address: 172.20.0.53
    restart: unless-stopped

  sftp:
    build:
      context: /opt/docker-app/sftp
      dockerfile: Dockerfile
    container_name: sftp
    depends_on:
      - coredns
    dns:
      - 172.20.0.53
    ports:
      - "${sftp_port}:22"
    environment:
      - SFTP_PUBLIC_KEY=${public_key}
    volumes:
      - ${efs_mount_path}/sftp:/data
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "nc -z localhost 22"]
      interval: 60s
      timeout: 10s
      retries: 5
      start_period: 10s

  wireguard:
    image: lscr.io/linuxserver/wireguard:1.0.20250521-r0-ls91
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

  postgres:
    image: postgres:17.2-alpine
    container_name: personal-site-db
    depends_on:
      - coredns
    dns:
      - 172.20.0.53
    restart: unless-stopped
    environment:
      - POSTGRES_DB=${postgres_db}
      - POSTGRES_USER=${postgres_user}
      - POSTGRES_PASSWORD=${postgres_password}
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=en_US.UTF-8
    volumes:
      - ${efs_mount_path}/postgres:/var/lib/postgresql/data
    networks:
      - app-network
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${postgres_user} -d ${postgres_db}"]
      interval: 10s
      timeout: 15s
      retries: 5
      start_period: 15s

  personal-site:
    image: "${personal_site_image_url}"
    container_name: personal-site
    depends_on:
      coredns:
        condition: service_started
      postgres:
        condition: service_healthy
    dns:
      - 172.20.0.53
    environment:
      - PORT=3000
      - ACCESS_CODES=${access_codes}
      - DATABASE_URL=postgresql://${postgres_user}:${postgres_password}@postgres:5432/${postgres_db}
      - POSTGRES_DB=${postgres_db}
      - POSTGRES_USER=${postgres_user}
      - POSTGRES_PASSWORD=${postgres_password}
      - POSTGRES_PORT=5432
      - MIGRATE_DB=true
      - RATE_LIMIT_PER_MINUTE=${rate_limit_per_minute}
      - BLOCK_DURATION_MINUTES=${block_duration_minutes}
      - ENABLE_ACCESS_LOGGING=${enable_access_logging}
      - LOG_SUCCESSFUL_ATTEMPTS=${log_successful_attempts}
      - ACCESS_LOG_RETENTION_DAYS=${access_log_retention_days}
      - SITE_DOMAIN=${site_domain}
      - SITE_URL=${site_url}
      - AWS_SES_FROM_EMAIL=${aws_ses_from_email}
      - S3_BUCKET_NAME=${personal_site_storage_bucket}
      - AWS_REGION=${aws_region}
      - AWS_DEFAULT_REGION=${aws_region}
    volumes:
      - ${efs_mount_path}/wireguard:/wireguard-config
    ports:
      - "3000:3000"
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
      interval: 30s
      timeout: 20s
      retries: 5
      start_period: 30s
