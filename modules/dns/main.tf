locals {
  use_existing = var.create_hosted_zone ? false : true
}

resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0
  name  = var.domain_name
  comment       = "Public hosted zone for ${var.domain_name}"
}

data "aws_route53_zone" "this" {
  count        = local.use_existing && var.zone_id == "" ? 1 : 0
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
  name    = "${var.sftp_subdomain}.${var.domain_name}."
  type    = "A"
  ttl     = var.ttl
  records = [var.sftp_ip]
}

resource "aws_route53_record" "vpn" {
  zone_id = local.zone_id
  name    = "${var.vpn_subdomain}.${var.domain_name}."
  type    = "A"
  ttl     = var.ttl
  records = [var.vpn_ip]
}

resource "aws_route53_record" "personal_site" {
  count   = 1
  zone_id = local.zone_id
  name    = "${var.personal_site_subdomain}.${var.domain_name}."
  type    = "A"

  alias {
    name                   = var.personal_site_alb_dns_name
    zone_id                = var.personal_site_alb_zone_id
    evaluate_target_health = true
  }
}

output "zone_id" {
  value = local.zone_id
}