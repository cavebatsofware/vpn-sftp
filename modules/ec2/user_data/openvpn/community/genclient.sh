#!/bin/bash
set -euo pipefail

# Generate a single-file OpenVPN client configuration (.ovpn) and print to stdout.
#
# Inputs
# - $1: client name (CN)
# - OVPN_REMOTE: remote host/IP for clients to connect to (required)
# - OVPN_PORT: UDP port (default 1194)
# - OVPN_PASSPHRASE: optional passphrase to encrypt the client private key
#
# Behavior
# - Uses the server-side Easy-RSA PKI under /etc/openvpn/pki
# - Builds a client cert/key (encrypted if passphrase provided)
# - Emits a deterministic, opinionated client config enforcing AES-256-GCM

NAME=${1:?client name required}
OVPN_DIR=/etc/openvpn
PKI_DIR=${OVPN_DIR}/pki
cd ${PKI_DIR}/easyrsa
export EASYRSA_BATCH=1

# Build client cert/key quietly so stdout remains a clean .ovpn
if [[ -n "${OVPN_PASSPHRASE:-}" ]]; then
	# Create an encrypted key without prompts
	./easyrsa --sbatch --passout="pass:${OVPN_PASSPHRASE}" build-client-full "$NAME" >/dev/null 2>&1
else
	./easyrsa --sbatch build-client-full "$NAME" nopass >/dev/null 2>&1
fi

# Remote host/port come from env; keep this deterministic and fail if missing
REMOTE_HOST=${OVPN_REMOTE:-}
REMOTE_PORT=${OVPN_PORT:-1194}
if [[ -z "${REMOTE_HOST}" ]]; then
	echo "[genclient] OVPN_REMOTE not set; please set to a resolvable hostname or IP (e.g., vpn.example.com). Aborting." >&2
	exit 2
fi

# Collect materials for embedding into the unified client profile
CA=$(cat ${PKI_DIR}/ca.crt)
CRT=$(cat pki/issued/${NAME}.crt)
KEY=$(cat pki/private/${NAME}.key)
TA=$(cat ${PKI_DIR}/ta.key)

# Output the inline .ovpn profile
cat <<EOF
client
dev tun
proto udp
remote ${REMOTE_HOST} ${REMOTE_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verb 3
data-ciphers AES-256-GCM
auth SHA256
key-direction 1
<ca>
${CA}
</ca>
<cert>
${CRT}
</cert>
<key>
${KEY}
</key>
<tls-auth>
${TA}
</tls-auth>
EOF
