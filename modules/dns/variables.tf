variable "domain_name" { type = string }
variable "create_hosted_zone" {
  type    = bool
  default = false
}
variable "zone_id" {
  type    = string
  default = ""
}
variable "sftp_subdomain" {
  type    = string
  default = "sftp"
}
variable "vpn_subdomain" {
  type    = string
  default = "vpn"
}
variable "sftp_ip" {
  type = string
}
variable "vpn_ip" {
  type = string
}
variable "ttl" {
  type    = number
  default = 900
}
variable "personal_site_subdomain" {
  type    = string
  default = "resume"
}
variable "personal_site_alb_dns_name" {
  type    = string
  default = ""
}
variable "personal_site_alb_zone_id" {
  type    = string
  default = ""
}