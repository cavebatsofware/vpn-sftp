resource "aws_route53_zone" "private" {
  name = var.domain_name
  vpc {
    vpc_id = var.vpc_id
  }
  comment      = "Private hosted zone for ${var.domain_name}"
  force_destroy = true
}

resource "aws_route53_record" "sftp_ui_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "${var.sftp_ui_subdomain}.${var.domain_name}."
  type    = "A"
  ttl     = var.ttl
  records = [var.sftp_private_ip]
}

output "zone_id" { value = aws_route53_zone.private.zone_id }
