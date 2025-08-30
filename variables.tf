variable "aws_region" { type = string }
variable "environment" { type = string }
variable "project_name" { type = string }
variable "cost_center" { 
    type = string
    default = ""
}
variable "owner" {
    type = string
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
    type = number
    default = 30
}
variable "alert_email" { type = string }

# Flags
variable "enable_encryption" {
    type = bool
    default = true
}

# Outputs feeding modules
variable "instance_type" {
    type = string
    default = "t4g.micro"
}

# Compose template inputs
variable "sftp_port" {
    type = number
    default = 2222
}
variable "vpn_port" {
    type = number
    default = 1194
}

# s3fs credentials seeding (optional)
variable "s3fs_passwd" {
    description = "Content for ~/.passwd-s3fs in the form ACCESS_KEY_ID:SECRET_ACCESS_KEY[:SESSION_TOKEN]"
    type        = string
    default     = ""
    sensitive   = true
}
variable "s3fs_ssm_parameter_name" {
    description = "Name of SSM (SecureString) parameter containing ACCESS_KEY_ID:SECRET_ACCESS_KEY[:SESSION_TOKEN] for s3fs"
    type        = string
    default     = ""
}
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
variable "openvpn_subdomain" {
    type    = string
    default = "vpn"
}

# Optional SFTPGo UI over HTTPS via ALB
variable "enable_sftp_ui_alb" {
    type    = bool
    default = false
}
variable "acm_certificate_arn" {
    type    = string
    default = ""
}
variable "sftp_ui_subdomain" {
    type    = string
    default = "sftp-ui"
}

