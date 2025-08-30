#!/bin/bash
set -e
ENVIRONMENT=${1:-staging}
TARGET_ENV=${2:-}
SFTP_IP=${SFTP_IP:-$(terraform output -raw sftp_effective_ip 2>/dev/null || terraform output -raw sftp_public_ip 2>/dev/null || echo "")}
OPENVPN_IP=${OPENVPN_IP:-$(terraform output -raw openvpn_effective_ip 2>/dev/null || terraform output -raw openvpn_public_ip 2>/dev/null || echo "")}
ALB_DNS=${ALB_DNS:-$(terraform output -raw alb_dns_name 2>/dev/null || echo "")}

if [ -n "$SFTP_IP" ]; then
  echo "Checking SFTP $SFTP_IP:2022"
  timeout 10 bash -c "</dev/tcp/$SFTP_IP/2022" && echo "SFTP OK" || { echo "SFTP FAILED"; exit 1; }
  # Optional: Web UI
  code=$(curl -s -o /dev/null -w "%{http_code}" http://$SFTP_IP:8080/health 2>/dev/null || true)
  [ "$code" = "200" ] && echo "SFTPGo UI health OK" || echo "SFTPGo UI HTTP $code"
fi

if [ -n "$OPENVPN_IP" ]; then
  echo "Checking OpenVPN $OPENVPN_IP:1194"
  # Best-effort UDP check
  (echo >/dev/udp/$OPENVPN_IP/1194) >/dev/null 2>&1 && echo "OpenVPN UDP OK" || echo "OpenVPN UDP check inconclusive"
fi

if [ -n "$ALB_DNS" ]; then
  code=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/health || true)
  [ "$code" = "200" ] && echo "ALB health OK" || echo "ALB health HTTP $code"
fi
