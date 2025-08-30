FROM debian:trixie-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends openvpn easy-rsa iptables iproute2 bash systemctl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY genclient.sh /usr/local/bin/genclient.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/genclient.sh
VOLUME ["/etc/openvpn"]
EXPOSE 1194/udp
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
