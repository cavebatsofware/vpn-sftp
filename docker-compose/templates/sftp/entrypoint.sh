#!/bin/sh
set -e

# Create user if not exists
if ! id sftp-sync-user >/dev/null 2>&1; then
    adduser -D -u 1000 -h /home/sftp-sync-user -s /sbin/nologin sftp-sync-user
fi

# Set up authorized keys directory and file
mkdir -p /etc/ssh/authorized_keys
echo "$SFTP_PUBLIC_KEY" > /etc/ssh/authorized_keys/sftp-sync-user
chmod 644 /etc/ssh/authorized_keys/sftp-sync-user

# Chroot requires root ownership of /data, user writes to subdirectory
chown root:root /data
chmod 755 /data

# Create upload directory owned by user
mkdir -p /data/files
chown sftp-sync-user:sftp-sync-user /data/files
chmod 750 /data/files

# Start sshd in foreground
exec /usr/sbin/sshd -D -e
