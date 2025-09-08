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
  source             = "./modules/security-groups"
  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  allowed_ssh_cidrs  = var.allowed_ssh_cidrs
  admin_access_cidrs = var.admin_access_cidrs
  sftp_port          = var.sftp_port
  wireguard_port     = var.wireguard_port
}

# IAM
module "iam" {
  source        = "./modules/iam"
  project_name  = var.project_name
  environment   = var.environment
  s3_bucket_arn = module.s3.bucket_arn
  kms_key_arn   = module.s3.kms_key_arn
  # Provide a Parameter Store KMS key ARN if you encrypt SSM parameters
  parameter_store_kms_key_arn = null
}

# S3 backend
module "s3" {
  source       = "./modules/s3"
  project_name = var.project_name
  environment  = var.environment
}

# EFS for persistent state (SFTPGo DB, VPN state)
module "efs" {
  source        = "./modules/efs"
  project_name  = var.project_name
  environment   = var.environment
  aws_region    = var.aws_region
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.public_subnet_ids
  client_sg_ids = [module.security_groups.sftp_sg_id, module.security_groups.vpn_sg_id]
  kms_key_arn   = module.s3.kms_key_arn
}

locals {
  docker_compose_template_stack = "${path.root}/docker-compose/templates/docker-compose.stack.yml.tpl"
  # AWS VPC DNS resolver is network address + 2
  vpc_dns_ip = cidrhost(var.vpc_cidr, 2)

  docker_compose_yml_stack = templatefile(local.docker_compose_template_stack, {
    s3_bucket_name  = module.s3.bucket_name
    aws_region      = var.aws_region
    sftp_port       = var.sftp_port
    wireguard_port  = var.wireguard_port
    vpn_servername  = (var.domain_name != "" ? "${var.vpn_subdomain}.${var.domain_name}" : "${var.project_name}.${var.environment}")
    s3_mount_path   = "/mnt/s3"
    efs_mount_path  = "/mnt/efs"
    wireguard_peers = var.wireguard_peers == "" ? 0 : var.wireguard_peers
    dns_servers     = var.dns_servers
  })
}

# EC2
module "ec2" {
  source                 = "./modules/ec2"
  project_name           = var.project_name
  environment            = var.environment
  aws_region             = var.aws_region
  public_subnet_id       = module.vpc.public_subnet_ids[0]
  sftp_security_group_id = module.security_groups.sftp_sg_id
  vpn_security_group_id  = module.security_groups.vpn_sg_id
  instance_profile_name  = module.iam.instance_profile_name
  arm64_ami_id           = var.arm64_ami_id_override != "" ? var.arm64_ami_id_override : data.aws_ami.al2023_arm64.id
  s3_bucket_name         = module.s3.bucket_name
  public_key             = var.public_key
  docker_compose_yml     = local.docker_compose_yml_stack
  wireguard_port         = var.wireguard_port
  vpn_servername         = (var.domain_name != "" ? "${var.vpn_subdomain}.${var.domain_name}" : "${var.project_name}.${var.environment}")
  efs_file_system_id     = module.efs.file_system_id
  efs_mount_path         = "/mnt/efs"
  aws_profile            = var.aws_profile
  vpc_dns_ip             = local.vpc_dns_ip
  dns_servers            = var.dns_servers
  domain_name            = var.domain_name
}
# DNS (optional)
module "dns" {
  count              = var.domain_name == "" ? 0 : 1
  source             = "./modules/dns"
  domain_name        = var.domain_name
  create_hosted_zone = var.create_hosted_zone
  zone_id            = var.route53_zone_id
  sftp_subdomain     = var.sftp_subdomain
  vpn_subdomain      = var.vpn_subdomain
  sftp_ip            = module.ec2.sftp_effective_ip
  vpn_ip             = module.ec2.vpn_effective_ip
}

# Private hosted zone for internal SFTPGo UI name -> private IP
module "dns_private" {
  count           = var.domain_name == "" ? 0 : 1
  source          = "./modules/dns-private"
  domain_name     = var.domain_name
  vpc_id          = module.vpc.vpc_id
  sftp_private_ip = module.ec2.sftp_private_ip
  vpn_private_ip  = module.ec2.vpn_private_ip
  sftp_subdomain  = var.sftp_subdomain
  vpn_subdomain   = var.vpn_subdomain
}

# Monitoring
module "monitoring" {
  source             = "./modules/monitoring"
  project_name       = var.project_name
  environment        = var.environment
  log_retention_days = var.log_retention_days
  alert_email        = var.alert_email
  sftp_instance_id   = module.ec2.sftp_instance_id
  vpn_instance_id    = module.ec2.vpn_instance_id
}
