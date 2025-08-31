variable "domain_name" { type = string }
variable "create_hosted_zone" {
    type = bool
    default = false
}
variable "zone_id" {
    type = string
    default = ""
}
variable "sftp_subdomain" {
    type = string
    default = "sftp"
}
variable "openvpn_subdomain" {
    type = string
    default = "vpn"
}
variable "sftp_ip" {
    type = string
}
variable "openvpn_ip" {
    type = string
}
variable "ttl" {
    type = number
    default = 900
}