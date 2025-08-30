#!/bin/bash
set -euo pipefail

# Container entrypoint for the OpenVPN Community server.
#
# Responsibilities
# - Enable IP forwarding inside the container for NAT
# - Initialize Easy-RSA PKI on first run and generate server keys
# - Write a secure OpenVPN server.conf if missing
# - Ensure NAT (MASQUERADE) for VPN subnet to the host's default interface
# - Start openvpn in the foreground

OVPN_DIR=/etc/openvpn
PKI_DIR=${OVPN_DIR}/pki
SERVER_CONF=${OVPN_DIR}/server.conf

sysctl -w net.ipv4.ip_forward=1 || true

# First-run PKI bootstrap
if [[ ! -f "${PKI_DIR}/ca.crt" ]]; then
  mkdir -p ${PKI_DIR}
  make-cadir ${PKI_DIR}/easyrsa >/dev/null 2>&1 || true
  if [[ ! -d "${PKI_DIR}/easyrsa" ]]; then
    mkdir -p ${PKI_DIR}/easyrsa
    cp -r /usr/share/easy-rsa/* ${PKI_DIR}/easyrsa/
  fi
  cd ${PKI_DIR}/easyrsa
  export EASYRSA_BATCH=1
  ./easyrsa init-pki
  ./easyrsa build-ca nopass
  ./easyrsa gen-dh
  ./easyrsa build-server-full server nopass
  openvpn --genkey secret ${PKI_DIR}/ta.key
  cp pki/ca.crt ${PKI_DIR}/ca.crt || true
  cp pki/issued/server.crt ${PKI_DIR}/server.crt || true
  cp pki/private/server.key ${PKI_DIR}/server.key || true
  cp pki/dh.pem ${PKI_DIR}/dh.pem || true
fi

# Opinionated server configuration enforcing AES-256-GCM
if [[ ! -f "${SERVER_CONF}" ]]; then
  cat > ${SERVER_CONF} <<CFG
port 1194
proto udp
dev tun
topology subnet
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup
verb 3
data-ciphers AES-256-GCM
auth SHA256
key-direction 0
tls-auth ${PKI_DIR}/ta.key 0
ca ${PKI_DIR}/ca.crt
cert ${PKI_DIR}/server.crt
key ${PKI_DIR}/server.key
dh ${PKI_DIR}/dh.pem
status ${OVPN_DIR}/openvpn-status.log
log-append ${OVPN_DIR}/openvpn.log
CFG
fi

# NAT: allow VPN clients to reach the internet via the host's eth0
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE || true

exec openvpn --config ${SERVER_CONF}
