locals {
  use_existing = var.create_hosted_zone ? false : true
}

resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0
  name  = var.domain_name
}

data "aws_route53_zone" "this" {
  count = local.use_existing && var.zone_id == "" ? 1 : 0
  name         = "${var.domain_name}."
  private_zone = false
}

locals {
  zone_id = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : (
    var.zone_id != "" ? var.zone_id : data.aws_route53_zone.this[0].zone_id
  )
}

resource "aws_route53_record" "sftp" {
  zone_id = local.zone_id
  name    = "${var.sftp_subdomain}.${var.domain_name}"
  type    = "A"
  ttl     = var.ttl
  records = [var.sftp_ip]
}

resource "aws_route53_record" "openvpn" {
  zone_id = local.zone_id
  name    = "${var.openvpn_subdomain}.${var.domain_name}"
  type    = "A"
  ttl     = var.ttl
  records = [var.openvpn_ip]
}

output "zone_id" {
  value = local.zone_id
}