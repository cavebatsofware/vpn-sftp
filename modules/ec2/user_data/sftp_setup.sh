#!/bin/bash
set -euo pipefail

# EC2 user-data for provisioning the SFTP host (SFTPGo + companions).
#
# High-level steps
# 1) Install docker + compose plugin and dependencies
# 2) Mount EFS for persistence and prepare sftpgo data directory
# 3) Fetch/generate SFTPGo admin password and write to a local secret file
# 4) Render docker-compose.yml from a template, overriding the data volume to EFS
# 5) Start the stack with docker compose up -d

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
mkdir -p "$${EFS_MOUNT}"
if ! grep -q "$${EFS_MOUNT}" /etc/fstab; then
  echo "$${EFS_FS_ID}.efs.$${AWS_REGION}.amazonaws.com:/ $${EFS_MOUNT} nfs4 defaults,_netdev 0 0" >> /etc/fstab
fi
mount -a || true

# Mount S3 bucket via s3fs at /mnt/s3 (read/write)
# Credential precedence:
# 1) /etc/passwd-s3fs (AK:SK[:ST])
# 2) Instance profile (iam_role=auto)
mkdir -p /mnt/s3
S3FS_OPTS="_netdev,allow_other,uid=1000,gid=1000,umask=027,endpoint=$${AWS_REGION}"
if [[ -f "/etc/passwd-s3fs" ]]; then
  chmod 600 /etc/passwd-s3fs || true
  S3FS_OPTS="$S3FS_OPTS,passwd_file=/etc/passwd-s3fs"
else
  # Fall back to instance role credentials
  S3FS_OPTS="$S3FS_OPTS,iam_role=auto"
fi
if ! grep -q "/mnt/s3" /etc/fstab; then
  echo "$${S3_BUCKET} /mnt/s3 fuse.s3fs $S3FS_OPTS 0 0" >> /etc/fstab
fi
mount -a || true

# Ensure the EFS mount is available and prepare SFTPGo data dir with proper ownership
if mountpoint -q "$${EFS_MOUNT}"; then
  mkdir -p "$${EFS_MOUNT}/sftpgo"
  # SFTPGo container runs as uid/gid 1000 by default; grant it ownership
  chown -R 1000:1000 "$${EFS_MOUNT}/sftpgo" || true
  chmod 750 "$${EFS_MOUNT}/sftpgo" || true
else
  echo "WARNING: EFS mount $${EFS_MOUNT} is not mounted; SFTPGo may fail to start" >&2
fi

# SFTPGo admin password
# Prefer retrieving an existing admin password from SSM; otherwise generate one.
if aws ssm get-parameter --name "/$PROJECT_NAME/$ENVIRONMENT/sftpgo/admin-password" --with-decryption --query 'Parameter.Value' --output text --region $AWS_REGION >/dev/null 2>&1; then
  aws ssm get-parameter --name "/$PROJECT_NAME/$ENVIRONMENT/sftpgo/admin-password" --with-decryption --query 'Parameter.Value' --output text --region $AWS_REGION > /opt/docker-app/secrets/sftpgo_admin_password || true
else
  openssl rand -base64 24 > /opt/docker-app/secrets/sftpgo_admin_password
fi

chmod 600 /opt/docker-app/secrets/* || true

# Replace the local named volume with an absolute EFS bind-mount path for SFTPGo data.
# The S3 mount path is already rendered inside DOCKER_COMPOSE_YML.
echo "$DOCKER_COMPOSE_YML" | sed "s|sftpgo-data:/var/lib/sftpgo|$${EFS_MOUNT}/sftpgo:/var/lib/sftpgo|" > docker-compose.yml

docker compose up -d

exit 0