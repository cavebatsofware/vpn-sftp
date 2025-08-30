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
      # Default new users to local storage under /data (s3fs bind mount)
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
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  monitoring:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - app-network
    restart: unless-stopped
