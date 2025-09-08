variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "public_subnet_id" { type = string }
variable "sftp_security_group_id" { type = string }
variable "vpn_security_group_id" { type = string }
variable "instance_profile_name" { type = string }
variable "arm64_ami_id" { type = string }
variable "s3_bucket_name" { type = string }
variable "public_key" { type = string }
variable "docker_compose_yml" { type = string }
variable "allocate_elastic_ip" {
  type    = bool
  default = true
}
variable "vpn_servername" { type = string }
variable "wireguard_port" {
  type    = number
  default = 51820
}
variable "efs_file_system_id" { type = string }
variable "efs_mount_path" {
  type    = string
  default = "/mnt/efs"
}

# VPC resolver IP Deprecated, remove
variable "vpc_dns_ip" {
  type = string
}

# Comma-separated upstream public DNS servers used by CoreDNS default forwarder
variable "dns_servers" {
  type = string
}

# Optional domain to forward internally to VPC resolver (for private hosted zone)
variable "domain_name" {
  type    = string
  default = ""
}

variable "route53_zone_id" {
  type    = string
  default = ""
}

variable "dns_tls_servername" {
  type    = string
  default = ""
}

variable "aws_profile" {
  description = "AWS CLI profile name to use when relying on ~/.aws/credentials"
  type        = string
  default     = "default"
}
