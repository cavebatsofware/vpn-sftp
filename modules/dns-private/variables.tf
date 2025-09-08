variable "domain_name" { type = string }
variable "vpc_id" { type = string }
variable "sftp_private_ip" { type = string }
variable "sftp_subdomain" { type = string }
variable "vpn_subdomain" { type = string }
variable "vpn_private_ip" { type = string }
variable "ttl" {
  type    = number
  default = 900
}
