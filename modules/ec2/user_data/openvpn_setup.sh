#!/bin/bash
set -euo pipefail

# EC2 user-data for provisioning the OpenVPN (community) host.
#
# High-level steps
# 1) Install prerequisites (docker, compose plugin, awscli, nfs-common)
# 2) Mount EFS for persistent OpenVPN state (/etc/openvpn)
# 3) Build the OpenVPN Community container image on-host
# 4) Run the container with NET_ADMIN and TUN device
# 5) Persist the selected variant and server name/port hints

# Inputs from templatefile (populated by Terraform)
AWS_REGION=${aws_region}
ENVIRONMENT=${environment}
PROJECT_NAME=${project_name}
VPN_PORT=${vpn_port}
VPN_SERVERNAME=${vpn_servername}
EFS_FS_ID=${efs_file_system_id}
EFS_MOUNT=${efs_mount_path}

export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y curl wget gnupg2 ca-certificates awscli jq nfs-common

# Install Docker
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
fi

# Install docker compose plugin (compose v2)
if ! docker compose version >/dev/null 2>&1; then
    mkdir -p /usr/lib/docker/cli-plugins
    curl -L "https://github.com/docker/compose/releases/download/v2.39.1/docker-compose-linux-arm64" -o /usr/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/lib/docker/cli-plugins/docker-compose
fi

systemctl enable docker
systemctl start docker

## Mount EFS for persistence
mkdir -p "$${EFS_MOUNT}"
if ! grep -q "$${EFS_MOUNT}" /etc/fstab; then
    echo "$${EFS_FS_ID}.efs.$${AWS_REGION}.amazonaws.com:/ $${EFS_MOUNT} nfs4 defaults,_netdev 0 0" >> /etc/fstab
fi
mount -a || true

# Ensure the default admin user has docker group access for troubleshooting
groupadd -f docker || true
usermod -aG docker admin || true


mkdir -p /opt/openvpn
cd /opt/openvpn

# Build a Debian Trixie based OpenVPN community image on the instance
mkdir -p /opt/openvpn/community
# Write build context from template variables
cat > /opt/openvpn/community/Dockerfile <<'DOCKER'
${community_dockerfile}
DOCKER
cat > /opt/openvpn/community/entrypoint.sh <<'ENTRY'
${community_entrypoint}
ENTRY
cat > /opt/openvpn/community/genclient.sh <<'GEN'
${community_genclient}
GEN
chmod +x /opt/openvpn/community/entrypoint.sh /opt/openvpn/community/genclient.sh

docker build -t openvpn-community:latest /opt/openvpn/community

docker run -d \
    --name openvpn-community \
    --cap-add=NET_ADMIN \
    --device /dev/net/tun:/dev/net/tun \
    -p $${VPN_PORT}:1194/udp \
    -v $${EFS_MOUNT}/openvpn:/etc/openvpn \
    --restart unless-stopped \
    openvpn-community:latest

echo "community" > /opt/openvpn/variant

echo "$${VPN_SERVERNAME}" > /opt/openvpn/servername
echo "$${VPN_PORT}" > /opt/openvpn/port

exit 0
