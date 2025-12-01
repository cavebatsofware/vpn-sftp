aws_region   = "us-east-2"
environment  = "prod"
project_name = "sftp-vpn"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

allowed_ssh_cidrs  = ["YOUR_ADMIN_CIDR/32"]
admin_access_cidrs = ["YOUR_ADMIN_CIDR/32"]

public_key = "ssh-ed25519 AAAA... user@host"

log_retention_days = 30
alert_email        = "alerts@example.com"

# DNS
# Set your public domain and whether to create the hosted zone or use an existing one.
# If you already created the public hosted zone in Route 53, set route53_zone_id instead of create_hosted_zone.
domain_name        = "example.com"
create_hosted_zone = false
# route53_zone_id  = "ZXXXXXXXXXXXX"

# Hostname labels
vpn_subdomain  = "vpn"
sftp_subdomain = "sftp"
personal_site_subdomain = "resume"

# Service ports and WireGuard peers
sftp_port       = 2222
wireguard_port  = 51820
wireguard_peers = ""

# Personal Site Configuration
# PostgreSQL database password (required, sensitive)
postgres_password = "CHANGE_ME_SECURE_PASSWORD"

# TOTP encryption key - 64-character hex string (32 bytes)
# Generate with: openssl rand -hex 32
totp_encryption_key = "CHANGE_ME_64_CHAR_HEX_STRING_USE_OPENSSL_RAND_HEX_32"

# AWS SES and S3 configuration
aws_ses_from_email           = "noreply@example.com"
personal_site_storage_bucket = "your-site-storage-bucket"

# SSL Certificate for HTTPS (optional)
# acm_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/abcd-1234"
