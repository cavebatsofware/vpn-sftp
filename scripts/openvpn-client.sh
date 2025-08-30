#!/usr/bin/env bash
set -euo pipefail

# Unified OpenVPN client exporter for the Community edition.
#
# What this does
# - Resolves the OpenVPN server host/IP (via -H or terraform outputs)
# - SSHes to the instance running the openvpn-community container
# - Runs genclient.sh inside the container to produce a single .ovpn
# - Streams the .ovpn back to your local machine and writes it to a file
#
# Why this approach
# - Keeps the PKI on the server (no private keys leave the host)
# - Produces deterministic client configs by passing OVPN_REMOTE and OVPN_PORT
# - Avoids multi-hop scp steps; output is clean and ready to use
#
# Requirements
# - You can SSH to the OpenVPN EC2 instance as the specified user
# - terraform outputs are available locally if you don’t pass -H
#
# Usage: ./scripts/openvpn-client.sh [-e env] [-n name] [-p passphrase] [-H host] [-u ssh_user] [-P port] [-o output]

usage() {
  cat <<USAGE
Usage: $0 [-e env] [-n name] [-p passphrase] [-H host] [-u ssh_user] [-P port] [-o output]
If flags are omitted, you'll be prompted interactively.
USAGE
}

# Inputs from env/flags with sensible defaults. CLI flags override env vars.
ENVIRONMENT="${ENVIRONMENT:-}"
CLIENT_NAME="${NAME:-${CLIENT:-}}"
PASSPHRASE="${PASSPHRASE:-}"  # optional key passphrase
HOST_OVERRIDE="${HOST:-${OPENVPN_IP:-}}"
SSH_USER="${SSH_USER:-admin}"
PORT="${OPENVPN_PORT:-1194}"
OUTPUT=""

while getopts ":e:n:p:H:u:P:o:h" opt; do
  case $opt in
    e) ENVIRONMENT="$OPTARG";;
    n) CLIENT_NAME="$OPTARG";;
    p) PASSPHRASE="$OPTARG";;
    H) HOST_OVERRIDE="$OPTARG";;
    u) SSH_USER="$OPTARG";;
    P) PORT="$OPTARG";;
    o) OUTPUT="$OPTARG";;
    h) usage; exit 0;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage; exit 2;;
    \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2;;
  esac
done

if [[ -z "$ENVIRONMENT" ]]; then read -rp "Environment (dev|staging|prod): " ENVIRONMENT; fi
if [[ -z "$CLIENT_NAME" ]]; then read -rp "Client name: " CLIENT_NAME; fi
# Optional: if set, the client private key in the resulting .ovpn will be encrypted
if [[ -z "$PASSPHRASE" ]]; then read -rp "Key passphrase (optional): " PASSPHRASE; fi

# Resolve host from terraform outputs if not provided explicitly.
tf_out() { terraform output -raw "$1" 2>/dev/null || true; }
if [[ -z "$HOST_OVERRIDE" ]]; then
  export TF_WORKSPACE="$ENVIRONMENT" || true
  HOST_OVERRIDE=$(tf_out openvpn_effective_ip)
fi
if [[ -z "$HOST_OVERRIDE" ]]; then
  echo "OpenVPN host not found. Provide -H or set OPENVPN_IP." >&2
  exit 1
fi

OUT_FILE="${OUTPUT:-${CLIENT_NAME}.ovpn}"

# SSH options and the remote script to run on the server.
# - StrictHostKeyChecking=accept-new: first connect auto-accepts host key, later connects verify it
# - UserKnownHostsFile=/dev/null: don’t persist host keys locally for ephemeral hosts
SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
)

# The remote script runs on the EC2 instance. It:
# 1) Locates the openvpn-community container
# 2) Sets environment overrides (remote host/port/passphrase)
# 3) Executes genclient.sh inside the container and prints the .ovpn to stdout
REMOTE_SCRIPT=$(cat <<'BASH'
set -euo pipefail

CLIENT="$1"
PORT="$2"
REMOTE_HOST="$3"
PASSPHRASE="${4:-}"

# Find the running OpenVPN container by its canonical name
CONTAINER=$(docker ps --format '{{.Names}}' | awk '$0=="openvpn-community"{print; exit}')
if [[ -z "$CONTAINER" ]]; then
  echo "openvpn-community container not running" >&2
  exit 1
fi

ARGS=( -e "OVPN_REMOTE=${REMOTE_HOST}" -e "OVPN_PORT=${PORT}" )
if [[ -n "${PASSPHRASE}" ]]; then
  ARGS+=( -e "OVPN_PASSPHRASE=${PASSPHRASE}" )
fi

# Execute the client generator. All output is the final .ovpn content.
exec docker exec "${ARGS[@]}" -i "${CONTAINER}" /usr/local/bin/genclient.sh "${CLIENT}"
BASH
)

# Stream the generated config directly to the output file on the local machine
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST_OVERRIDE}" \
  bash -s -- "${CLIENT_NAME}" "${PORT}" "${HOST_OVERRIDE}" "${PASSPHRASE:-}" \
  >"${OUT_FILE}" <<<"${REMOTE_SCRIPT}"

echo "Wrote ${OUT_FILE}"
