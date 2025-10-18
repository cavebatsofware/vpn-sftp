aws_region   = "us-east-2"
environment  = "dev"
project_name = "sftp-vpn"

vpc_cidr             = "10.10.0.0/16"
public_subnet_cidrs  = ["10.10.1.0/24"]
private_subnet_cidrs = ["10.10.10.0/24"]

allowed_ssh_cidrs  = ["YOUR_ADMIN_CIDR/32"]
admin_access_cidrs = ["YOUR_ADMIN_CIDR/32"]

public_key = "ssh-ed25519 AAAA... user@host"

log_retention_days = 30
alert_email        = "alerts@example.com"

# DNS
domain_name        = "example.com"
create_hosted_zone = false
# route53_zone_id  = "ZXXXXXXXXXXXX"

vpn_subdomain  = "vpn"
sftp_subdomain = "sftp"
personal_site_subdomain = "resume"

# Service ports and WireGuard peers
sftp_port       = 2222
wireguard_port  = 51820
wireguard_peers = ""

# Personal Site Configuration
postgres_password            = "dev_password_change_me"
aws_ses_from_email           = "noreply@example.com"
personal_site_storage_bucket = "dev-site-storage-bucket"
