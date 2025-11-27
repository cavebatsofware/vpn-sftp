FROM alpine:3.22

RUN apk add --no-cache openssh-server && \
    mkdir -p /var/run/sshd /data && \
    ssh-keygen -A

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
