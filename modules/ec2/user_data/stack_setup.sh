#!/bin/bash
set -euo pipefail

# EC2 user-data to provision a single host running both SFTPGo and WireGuard via Docker Compose.
# - Installs Docker and compose plugin
# - Mounts EFS at ${efs_mount_path} and S3 bucket via Mountpoint for Amazon S3 (mount-s3) at /mnt/s3
# - Creates SFTPGo admin password secret (from SSM if available, else random)
# - Renders docker-compose.yml from provided template and starts the stack

AWS_REGION=${aws_region}
ENVIRONMENT=${environment}
PROJECT_NAME=${project_name}
EFS_FS_ID=${efs_file_system_id}
EFS_MOUNT=${efs_mount_path}
S3_BUCKET=${s3_bucket_name}
DOCKER_COMPOSE_YML=$(cat <<'YAML'
${docker_compose_yml}
YAML
)

export DNF_YUM=1
dnf -y update || true
dnf -y install docker || true
dnf -y swap gnupg2-minimal gnupg2-full || true


# Ensure any old/incorrect compose plugin path is not shadowing
rm -f /usr/lib/docker/cli-plugins/docker-compose || true

# Start Docker using systemctl (preferred), with fallbacks
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable docker || true
  systemctl start docker || true
  if ! systemctl is-active --quiet docker; then
    service docker start || true
  fi
else
  service docker start || true
fi

# Wait for Docker daemon readiness
for i in {1..20}; do
  docker info >/dev/null 2>&1 && break || sleep 3
done

groupadd -f docker || true
id "ec2-user" >/dev/null 2>&1 && usermod -aG docker "ec2-user" || true

mkdir -p /opt/docker-app/{config,secrets,logs}
cd /opt/docker-app

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

# Mount S3 bucket at /mnt/s3 using Mountpoint for Amazon S3 via /etc/fstab
mkdir -p /mnt/s3

# Ensure FUSE allows 'allow_other' (create if missing)
if [ -f /etc/fuse.conf ]; then
  sed -i 's/^#\?user_allow_other/user_allow_other/' /etc/fuse.conf || true
else
  echo user_allow_other > /etc/fuse.conf
  chmod 644 /etc/fuse.conf || true
fi

# Install mount-s3 (Mountpoint for Amazon S3) if missing
if ! command -v mount-s3 >/dev/null 2>&1; then
  RPM_URL="https://s3.amazonaws.com/mountpoint-s3-release/latest/arm64/mount-s3.rpm"
  SIG_URL="https://s3.amazonaws.com/mountpoint-s3-release/latest/arm64/mount-s3.rpm.sig"
  TMP_DIR="/tmp/mountpoint-s3"
  mkdir -p "$TMP_DIR"
  (
    set -e
    cd "$TMP_DIR"
    wget -q -O KEYS https://s3.amazonaws.com/mountpoint-s3-release/public_keys/KEYS || true
    if [ -s KEYS ]; then
      gpg --import KEYS || true
      EXPECTED_FPR="673FE4061506BB469A0EF857BE397A52B086DA5A"
      ACTUAL_FPR=$(gpg --fingerprint mountpoint-s3@amazon.com 2>/dev/null | sed -n 's/ *Key fingerprint = //p' | tr -d ' ' | head -n1)
      if [ -n "$ACTUAL_FPR" ] && [ "$ACTUAL_FPR" != "$EXPECTED_FPR" ]; then
        echo "WARNING: mountpoint-s3 GPG fingerprint mismatch: $ACTUAL_FPR" >&2
      fi
    fi
    wget -q -O mount-s3.rpm "$RPM_URL"
    wget -q -O mount-s3.rpm.sig "$SIG_URL"
    if [ ! -s KEYS ] || [ ! -s mount-s3.rpm.sig ]; then
      echo "ERROR: GPG KEYS or signature file missing; cannot verify mount-s3.rpm" >&2
      exit 1
    fi
    if ! gpg --verify mount-s3.rpm.sig mount-s3.rpm >/dev/null 2>&1; then
      echo "ERROR: GPG signature verification failed for mount-s3.rpm; skipping install" >&2
      exit 3
    fi
    # Install the RPM (dnf handles dependencies like fuse3-lib, if any)
    dnf -y install ./mount-s3.rpm || rpm -Uvh --force ./mount-s3.rpm || true
  ) || echo "WARNING: Failed to install mount-s3; S3 mount will be skipped" >&2
fi

# Configure fstab entry and mount if mount-s3 is available
if command -v mount-s3 >/dev/null 2>&1; then
  if ! grep -qE "^s3://\s*$${S3_BUCKET}\b" /etc/fstab; then
    echo "s3://$${S3_BUCKET} /mnt/s3 mount-s3 _netdev,nosuid,nodev,nofail,rw,allow-other,uid=1000,gid=1000,dir_mode=0750,file_mode=0640 0 0" >> /etc/fstab
  fi
  mount -a || true
else
  echo "WARNING: mount-s3 not installed; skipping S3 mount" >&2
fi

# Tighten secret permissions only if files exist
if compgen -G "/opt/docker-app/secrets/*" > /dev/null; then
  chmod 600 /opt/docker-app/secrets/* || true
fi

# Enable IPv4 forwarding on host (defense in depth for WireGuard NAT)
sysctl -w net.ipv4.ip_forward=1 || true
if ! grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi

# Write docker-compose.yml from injected template
echo "$DOCKER_COMPOSE_YML" > docker-compose.yml

# Ensure Docker Compose v2 plugin is available (install to /usr/libexec if needed)
if ! docker compose version >/dev/null 2>&1; then
  mkdir -p /usr/libexec/docker/cli-plugins
  ARCH=$(uname -m)
  case "$ARCH" in
    aarch64)
      COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.39.1/docker-compose-linux-aarch64" ;;
    *)
      COMPOSE_URL="" ;;
  esac
  if [ -n "$COMPOSE_URL" ]; then
    curl -fsSL -o /usr/libexec/docker/cli-plugins/docker-compose "$COMPOSE_URL" || \
    wget -q -O /usr/libexec/docker/cli-plugins/docker-compose "$COMPOSE_URL" || true
    chmod +x /usr/libexec/docker/cli-plugins/docker-compose || true
  fi
fi

# Start the stack (only if compose plugin is available)
if docker compose version >/dev/null 2>&1; then
  docker compose up -d
else
  echo "WARNING: docker compose plugin not available; skipping stack start" >&2
fi

exit 0
