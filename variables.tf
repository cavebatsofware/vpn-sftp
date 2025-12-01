variable "aws_region" { type = string }
variable "environment" { type = string }
variable "project_name" { type = string }
variable "cost_center" {
  type    = string
  default = ""
}
variable "owner" {
  type    = string
  default = ""
}
# Network
variable "vpc_cidr" { type = string }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }

# Security
variable "allowed_ssh_cidrs" { type = list(string) }
variable "admin_access_cidrs" { type = list(string) }

# EC2 / SSH
variable "public_key" { type = string }

# Monitoring
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "alert_email" { type = string }

# Flags
variable "enable_encryption" {
  type    = bool
  default = true
}

# Outputs feeding modules
variable "instance_type" {
  type    = string
  default = "t4g.micro"
}

# Optional: override the default ARM64 AMI (e.g., specific AL2023 AMI ID)
variable "arm64_ami_id_override" {
  type        = string
  default     = ""
  description = "If set, use this AMI ID for the EC2 instance instead of the data-sourced AL2023 AMI. AMI IDs are region-specific."
}

# Compose template inputs
variable "sftp_port" {
  type    = number
  default = 2222
}

# WireGuard aggressive cutover
variable "wireguard_port" {
  type    = number
  default = 51820
}

# Comma-separated list of initial WireGuard peers (names)
# Example: "alice,bob,carol". Set to empty to create none.
variable "wireguard_peers" {
  type        = string
  default     = ""
  description = "Comma-separated list of WireGuard peer names to generate at first run; leave empty for none"
}

# DNS servers to use for the Wireguard VPN configuration
variable "dns_servers" {
  description = "Space-separated list of DNS servers to use"
  type        = string
  default     = "tls://8.8.8.8 tls://8.8.4.4"
}

variable "dns_tls_servername" {
  description = "TLS Server Name (SNI) for DNS over TLS upstream; leave empty to skip tls_servername directive"
  type        = string
  default     = "dns.google"
}

# Fits into a forwarding rule in CoreDNS like this: forward . 10.0.0.10:53 10.0.0.11:1053 [2003::1]:53
# where this value is everything after "forward . "
variable "aws_profile" {
  description = "AWS CLI profile to use when reading ~/.aws/credentials on the instance"
  type        = string
  default     = "default"
}

# DNS
variable "domain_name" {
  type    = string
  default = ""
}
variable "route53_zone_id" {
  type    = string
  default = ""
}
variable "create_hosted_zone" {
  type    = bool
  default = false
}
variable "sftp_subdomain" {
  type    = string
  default = "sftp"
}
variable "vpn_subdomain" {
  type    = string
  default = "vpn"
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

# Private DNS (Route 53 private hosted zone) for internal-only UI name
# The module will create a private zone for `domain_name` and map
# `<sftp_ui_subdomain>.<domain_name>` to the SFTP instance private IP.
# It is created automatically when domain_name is set.

# Personal site configuration
variable "access_codes" {
  type        = string
  default     = ""
  description = "Comma-separated list of valid resume access codes"
}

variable "personal_site_subdomain" {
  type        = string
  default     = "resume"
  description = "Subdomain for the personal site"
}

# PostgreSQL Database configuration
variable "postgres_db" {
  type        = string
  default     = "personal_site"
  description = "PostgreSQL database name"
}

variable "postgres_user" {
  type        = string
  default     = "personal_site_user"
  description = "PostgreSQL database user"
}

variable "postgres_password" {
  type        = string
  sensitive   = true
  description = "PostgreSQL database password (sensitive)"
}

variable "totp_encryption_key" {
  type        = string
  sensitive   = true
  description = "64-character hex string (32 bytes) for TOTP secret encryption"
}

variable "migrate_db" {
  type        = string
  default     = "true"
  description = "Enable database migrations on startup"
}

# Rate limiting and access logging
variable "rate_limit_per_minute" {
  type        = number
  default     = 50
  description = "Max requests per minute before blocking IP"
}

variable "block_duration_minutes" {
  type        = number
  default     = 15
  description = "Duration to block IPs exceeding rate limit"
}

variable "enable_access_logging" {
  type        = string
  default     = "true"
  description = "Enable/disable access logging to database"
}

variable "log_successful_attempts" {
  type        = string
  default     = "true"
  description = "Log successful access attempts"
}

variable "access_log_retention_days" {
  type        = number
  default     = 30
  description = "Days to retain access logs before cleanup"
}

# AWS SES configuration for email sending
variable "aws_ses_from_email" {
  type        = string
  default     = ""
  description = "AWS SES from email address for sending emails (e.g., noreply@domain.com)"
}

# S3 bucket for personal-site storage
variable "personal_site_storage_bucket" {
  type        = string
  description = "S3 bucket name for personal-site storage"
}
