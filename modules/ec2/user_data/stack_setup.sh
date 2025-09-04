#!/bin/bash
set -euo pipefail

# EC2 user-data to provision a single host running both SFTPGo and WireGuard via Docker Compose.
# - Installs Docker and compose plugin
# - Mounts EFS at ${efs_mount_path} and S3 bucket via s3fs at /mnt/s3
# - Creates SFTPGo admin password secret (from SSM if available, else random)
# - Renders docker-compose.yml from provided template and starts the stack

AWS_REGION=${aws_region}
ENVIRONMENT=${environment}
PROJECT_NAME=${project_name}
EFS_FS_ID=${efs_file_system_id}
EFS_MOUNT=${efs_mount_path}
S3_BUCKET=${s3_bucket_name}
S3FS_PASSWD_CONTENT=${s3fs_passwd}
S3FS_SSM_PARAM=${s3fs_ssm_parameter}
DOCKER_COMPOSE_YML=$(cat <<'YAML'
${docker_compose_yml}
YAML
)

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl wget gnupg2 ca-certificates awscli jq nfs-common
apt-get install -y s3fs
sed -i 's/^#\?user_allow_other/user_allow_other/' /etc/fuse.conf || echo user_allow_other >> /etc/fuse.conf

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
fi

if ! docker compose version >/dev/null 2>&1; then
  mkdir -p /usr/lib/docker/cli-plugins
  curl -L "https://github.com/docker/compose/releases/download/v2.39.1/docker-compose-linux-arm64" -o /usr/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/lib/docker/cli-plugins/docker-compose
fi

systemctl enable docker
systemctl start docker

groupadd -f docker || true
for U in admin ubuntu debian ec2-user; do
  id "$U" >/dev/null 2>&1 && usermod -aG docker "$U" || true
done

mkdir -p /opt/docker-app/{config,secrets,logs}
cd /opt/docker-app

# Optional: seed /etc/passwd-s3fs from SSM or inline var
if [[ -n "$S3FS_SSM_PARAM" ]]; then
  if VAL=$(aws ssm get-parameter --name "$S3FS_SSM_PARAM" --with-decryption --query 'Parameter.Value' --output text --region "$AWS_REGION" 2>/dev/null); then
    echo "$VAL" > /etc/passwd-s3fs
    chmod 600 /etc/passwd-s3fs
    chown root:root /etc/passwd-s3fs || true
  fi
elif [[ -n "$S3FS_PASSWD_CONTENT" ]]; then
  echo "$S3FS_PASSWD_CONTENT" > /etc/passwd-s3fs
  chmod 600 /etc/passwd-s3fs
  chown root:root /etc/passwd-s3fs || true
fi

# Mount EFS for persistence
mkdir -p "$EFS_MOUNT"
if ! grep -q "$EFS_MOUNT" /etc/fstab; then
  echo "$EFS_FS_ID.efs.$AWS_REGION.amazonaws.com:/ $EFS_MOUNT nfs4 defaults,_netdev 0 0" >> /etc/fstab
fi
mount -a || true

# Prepare EFS subdirs and permissions
mkdir -p "$EFS_MOUNT/sftpgo" "$EFS_MOUNT/wireguard"
chown -R 1000:1000 "$EFS_MOUNT/sftpgo" "$EFS_MOUNT/wireguard" || true
chmod 750 "$EFS_MOUNT/sftpgo" "$EFS_MOUNT/wireguard" || true

# Mount S3 bucket via s3fs at /mnt/s3 (read/write)
mkdir -p /mnt/s3
S3FS_OPTS="_netdev,allow_other,uid=1000,gid=1000,umask=027,endpoint=$AWS_REGION"
if [[ -f "/etc/passwd-s3fs" ]]; then
  chmod 600 /etc/passwd-s3fs || true
  S3FS_OPTS="$S3FS_OPTS,passwd_file=/etc/passwd-s3fs"
else
  S3FS_OPTS="$S3FS_OPTS,iam_role=auto"
fi
if ! grep -q "/mnt/s3" /etc/fstab; then
  echo "$S3_BUCKET /mnt/s3 fuse.s3fs $S3FS_OPTS 0 0" >> /etc/fstab
fi
mount -a || true

# SFTPGo admin password: get from SSM if exists; else generate one
if aws ssm get-parameter --name "/$PROJECT_NAME/$ENVIRONMENT/sftpgo/admin-password" --with-decryption --query 'Parameter.Value' --output text --region $AWS_REGION >/dev/null 2>&1; then
  aws ssm get-parameter --name "/$PROJECT_NAME/$ENVIRONMENT/sftpgo/admin-password" --with-decryption --query 'Parameter.Value' --output text --region $AWS_REGION > /opt/docker-app/secrets/sftpgo_admin_password || true
else
  openssl rand -base64 24 > /opt/docker-app/secrets/sftpgo_admin_password
fi
chmod 600 /opt/docker-app/secrets/* || true

# Enable IPv4 forwarding on host (defense in depth for WireGuard NAT)
sysctl -w net.ipv4.ip_forward=1 || true
if ! grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi

# Write docker-compose.yml from injected template
echo "$DOCKER_COMPOSE_YML" > docker-compose.yml

# Start the stack
docker compose up -d

exit 0
