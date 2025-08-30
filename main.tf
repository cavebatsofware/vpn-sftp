locals {
  name = "${var.project_name}-${var.environment}"
}

# VPC
module "vpc" {
  source               = "./modules/vpc"
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Security groups
module "security_groups" {
  source              = "./modules/security-groups"
  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  allowed_ssh_cidrs   = var.allowed_ssh_cidrs
  admin_access_cidrs  = var.admin_access_cidrs
  sftp_port           = var.sftp_port
}

# IAM
module "iam" {
  source                     = "./modules/iam"
  project_name               = var.project_name
  environment                = var.environment
  s3_bucket_arn              = module.s3.bucket_arn
  kms_key_arn                = module.s3.kms_key_arn
  # Provide a Parameter Store KMS key ARN if you encrypt SSM parameters; null by default
  parameter_store_kms_key_arn = null
}

# S3 backend
module "s3" {
  source       = "./modules/s3"
  project_name = var.project_name
  environment  = var.environment
}

# EFS for persistent state (SFTPGo DB, OpenVPN PKI)
module "efs" {
  source        = "./modules/efs"
  project_name  = var.project_name
  environment   = var.environment
  aws_region    = var.aws_region
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.public_subnet_ids
  client_sg_ids = [module.security_groups.sftp_sg_id, module.security_groups.openvpn_sg_id]
  kms_key_arn   = module.s3.kms_key_arn
}

locals {
  docker_compose_template_sftp = "${path.root}/docker-compose/templates/docker-compose.sftp.yml.tpl"

  docker_compose_yml_sftp = templatefile(local.docker_compose_template_sftp, {
    s3_bucket_name   = module.s3.bucket_name
    aws_region       = var.aws_region
    sftp_port        = var.sftp_port
    aws_iam_role_arn = module.iam.ec2_role_arn
    s3_mount_path    = "/mnt/s3"
    efs_mount_path   = module.ec2.efs_mount_path
  })
}

# EC2
module "ec2" {
  source                    = "./modules/ec2"
  project_name              = var.project_name
  environment               = var.environment
  aws_region                = var.aws_region
  public_subnet_id          = module.vpc.public_subnet_ids[0]
  sftp_security_group_id    = module.security_groups.sftp_sg_id
  openvpn_security_group_id = module.security_groups.openvpn_sg_id
  instance_profile_name     = module.iam.instance_profile_name
  arm64_ami_id              = data.aws_ami.debian_arm64.id
  s3_bucket_name            = module.s3.bucket_name
  public_key                = var.public_key
  docker_compose_yml        = local.docker_compose_yml_sftp
  vpn_port                  = var.vpn_port
  vpn_servername            = (var.domain_name != "" ? "${var.openvpn_subdomain}.${var.domain_name}" : "${var.project_name}.${var.environment}")
  efs_file_system_id        = module.efs.file_system_id
  efs_mount_path            = "/mnt/efs"
  s3fs_passwd               = var.s3fs_passwd
  s3fs_ssm_parameter_name   = var.s3fs_ssm_parameter_name
  aws_profile               = var.aws_profile
}
# DNS (optional)
module "dns" {
  count               = var.domain_name == "" ? 0 : 1
  source              = "./modules/dns"
  domain_name         = var.domain_name
  create_hosted_zone  = var.create_hosted_zone
  zone_id             = var.route53_zone_id
  sftp_subdomain      = var.sftp_subdomain
  openvpn_subdomain   = var.openvpn_subdomain
  sftp_ip             = module.ec2.sftp_effective_ip
  openvpn_ip          = module.ec2.openvpn_effective_ip
}

# Monitoring
module "monitoring" {
  source              = "./modules/monitoring"
  project_name        = var.project_name
  environment         = var.environment
  log_retention_days  = var.log_retention_days
  alert_email         = var.alert_email
  sftp_instance_id    = module.ec2.sftp_instance_id
  openvpn_instance_id = module.ec2.openvpn_instance_id
}

# Optional ALB for SFTPGo UI with ACM
module "sftp_ui_alb" {
  count             = var.enable_sftp_ui_alb && var.acm_certificate_arn != "" ? 1 : 0
  source            = "./modules/alb"
  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = var.acm_certificate_arn
  target_instance_id = module.ec2.sftp_instance_id
  target_port       = 8080
}

# Allow ALB SG -> SFTP instance on 8080 when ALB is enabled
resource "aws_security_group_rule" "alb_to_sftp_ui" {
  count                    = var.enable_sftp_ui_alb && length(module.sftp_ui_alb) > 0 ? 1 : 0
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.security_groups.sftp_sg_id
  source_security_group_id = module.sftp_ui_alb[0].alb_sg_id
}

# DNS record for SFTP UI if DNS and ALB are enabled
resource "aws_route53_record" "sftp_ui" {
  count   = var.domain_name != "" && var.enable_sftp_ui_alb && length(module.sftp_ui_alb) > 0 ? 1 : 0
  zone_id = module.dns[0].zone_id
  name    = "${var.sftp_ui_subdomain}.${var.domain_name}"
  type    = "A"
  alias {
    name                   = module.sftp_ui_alb[0].lb_dns_name
    zone_id                = module.sftp_ui_alb[0].lb_zone_id
    evaluate_target_health = true
  }
}
