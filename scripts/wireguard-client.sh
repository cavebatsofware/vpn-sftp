#!/usr/bin/env bash
set -euo pipefail

# WireGuard client helper
# - Shows QR or prints config using linuxserver/wireguard built-ins
# - Optionally copies the client config locally

usage(){ echo "Usage: $0 [-e env] [-n name] [-H host] [-u ssh_user] [-q|--qr] [-P|--print] [-o path|--copy=path]"; }

ENVIRONMENT="${ENVIRONMENT:-}"
CLIENT_NAME="${NAME:-${CLIENT:-}}"
HOST_OVERRIDE="${HOST:-}"
SSH_USER="${SSH_USER:-ec2-user}"
QR=false
PRINT=false
COPY_PATH=""

while getopts ":e:n:H:u:qPo:h-:" opt; do
  case $opt in
    e) ENVIRONMENT="$OPTARG";;
    n) CLIENT_NAME="$OPTARG";;
    H) HOST_OVERRIDE="$OPTARG";;
    u) SSH_USER="$OPTARG";;
    q) QR=true;;
    P) PRINT=true;;
    o) COPY_PATH="$OPTARG";;
    -)
      case "$OPTARG" in
        qr) QR=true ;;
        print) PRINT=true ;;
        copy=*) COPY_PATH="${OPTARG#copy=}" ;;
        *) echo "Unknown option --$OPTARG" >&2; usage; exit 2 ;;
      esac
      ;;
    h) usage; exit 0;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage; exit 2;;
    \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2;;
  esac
done

if [[ -z "$ENVIRONMENT" ]]; then read -rp "Environment (dev|staging|prod): " ENVIRONMENT; fi
if [[ -z "$CLIENT_NAME" ]]; then read -rp "Client name: " CLIENT_NAME; fi

# Resolve host from terraform outputs if not provided explicitly.
tf_out() { terraform output -raw "$1" 2>/dev/null || true; }
if [[ -z "$HOST_OVERRIDE" ]]; then
  export TF_WORKSPACE="$ENVIRONMENT" || true
  HOST_OVERRIDE=$(tf_out vpn_effective_ip)
fi
if [[ -z "$HOST_OVERRIDE" ]]; then
  echo "VPN host not found. Provide -H or export HOST." >&2
  exit 1
fi

# Determine remote EFS mount
EFS_MOUNT_REMOTE=${EFS_MOUNT_REMOTE:-}
if [[ -z "$EFS_MOUNT_REMOTE" ]]; then
  export TF_WORKSPACE="$ENVIRONMENT" || true
  EFS_MOUNT_REMOTE=$(tf_out efs_mount_path)
fi
if [[ -z "$EFS_MOUNT_REMOTE" ]]; then
  EFS_MOUNT_REMOTE="/mnt/efs"
fi
WG_DIR_REMOTE="$EFS_MOUNT_REMOTE/wireguard"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null)

# Resolve remote config path (named and numeric peers)
resolve_remote_conf_path() {
  local name="$1"; local wgdir="$2"
  local p1="$wgdir/peer_${name}/peer_${name}.conf"
  local p2="$wgdir/peer${name}/peer${name}.conf"
  local cmd="if [ -f '$p1' ]; then echo '$p1'; elif [ -f '$p2' ]; then echo '$p2'; fi"
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$HOST_OVERRIDE" "$cmd"
}

REMOTE_CONF_PATH=$(resolve_remote_conf_path "$CLIENT_NAME" "$WG_DIR_REMOTE")
if [[ -z "$REMOTE_CONF_PATH" ]]; then
  echo "Config not found for peer '$CLIENT_NAME' under $WG_DIR_REMOTE" >&2
  exit 2
fi

# Print to stdout
if $PRINT; then
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$HOST_OVERRIDE" "cat '$REMOTE_CONF_PATH'"
fi

# Copy to local path when requested
if [[ -n "$COPY_PATH" ]]; then
  scp "${SSH_OPTS[@]}" "$SSH_USER@$HOST_OVERRIDE:$REMOTE_CONF_PATH" "$COPY_PATH"
  echo "Saved config to $COPY_PATH"
fi

# Copy QR PNG next to the conf (or pwd if not copying conf)
if $QR; then
  REMOTE_PNG_PATH="${REMOTE_CONF_PATH%.conf}.png"
  PNG_OUT="${COPY_PATH:-peer_${CLIENT_NAME}.conf}"
  PNG_OUT="${PNG_OUT%.conf}.png"
  scp "${SSH_OPTS[@]}" "$SSH_USER@$HOST_OVERRIDE:$REMOTE_PNG_PATH" "$PNG_OUT" || {
    echo "QR PNG not found for '$CLIENT_NAME' under $WG_DIR_REMOTE" >&2
    exit 2
  }
  echo "Saved QR PNG to $PNG_OUT"
fi
