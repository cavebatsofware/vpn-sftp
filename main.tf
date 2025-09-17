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
  ecr_repository_arn          = module.ecr.repository_arn
}

# S3 backend
module "s3" {
  source       = "./modules/s3"
  project_name = var.project_name
  environment  = var.environment
}

# ECR for personal-site container
module "ecr" {
  source       = "./modules/ecr"
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
    s3_bucket_name          = module.s3.bucket_name
    aws_region              = var.aws_region
    sftp_port               = var.sftp_port
    wireguard_port          = var.wireguard_port
    vpn_servername          = (var.domain_name != "" ? "${var.vpn_subdomain}.${var.domain_name}" : "${var.project_name}.${var.environment}")
    s3_mount_path           = "/mnt/s3"
    efs_mount_path          = "/mnt/efs"
    wireguard_peers         = var.wireguard_peers == "" ? 0 : var.wireguard_peers
    dns_servers             = var.dns_servers
    resume_codes            = var.resume_codes
    personal_site_image_url = "${module.ecr.repository_url}:latest"
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
  route53_zone_id        = var.domain_name != "" ? module.dns_private[0].zone_id : ""
  dns_tls_servername     = var.dns_tls_servername
  instance_type          = var.instance_type
  ecr_registry_url       = split("/", module.ecr.repository_url)[0]
}
# DNS (optional)
module "dns" {
  count                      = var.domain_name == "" ? 0 : 1
  source                     = "./modules/dns"
  domain_name                = var.domain_name
  create_hosted_zone         = var.create_hosted_zone
  zone_id                    = var.route53_zone_id
  sftp_subdomain             = var.sftp_subdomain
  vpn_subdomain              = var.vpn_subdomain
  sftp_ip                    = module.ec2.sftp_effective_ip
  vpn_ip                     = module.ec2.vpn_effective_ip
  personal_site_subdomain    = var.personal_site_subdomain
  personal_site_alb_dns_name = var.acm_certificate_arn != "" ? try(aws_lb.personal_site[0].dns_name, "") : ""
  personal_site_alb_zone_id  = var.acm_certificate_arn != "" ? try(aws_lb.personal_site[0].zone_id, "") : ""
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

# Personal Site ALB (conditional)
resource "aws_security_group" "personal_site_alb" {
  count       = var.acm_certificate_arn != "" && var.domain_name != "" ? 1 : 0
  name        = "${var.project_name}-${var.environment}-personal-site-alb"
  description = "Security group for Personal Site ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name    = "${var.project_name}-${var.environment}-personal-site-alb"
    Service = "personal-site"
  }
}

resource "aws_lb" "personal_site" {
  count              = var.acm_certificate_arn != "" && var.domain_name != "" ? 1 : 0
  name               = "${var.project_name}-${var.environment}-personal"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.personal_site_alb[0].id]
  subnets            = module.vpc.public_subnet_ids
}

resource "aws_lb_target_group" "personal_site" {
  count    = var.acm_certificate_arn != "" && var.domain_name != "" ? 1 : 0
  name     = "${var.project_name}-${var.environment}-personal"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  health_check {
    enabled             = true
    interval            = 30
    path                = "/health"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "personal_site_https" {
  count             = var.acm_certificate_arn != "" && var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.personal_site[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.personal_site[0].arn
  }
}

resource "aws_lb_listener" "personal_site_http" {
  count             = var.acm_certificate_arn != "" && var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.personal_site[0].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_target_group_attachment" "personal_site" {
  count            = var.acm_certificate_arn != "" && var.domain_name != "" ? 1 : 0
  target_group_arn = aws_lb_target_group.personal_site[0].arn
  target_id        = module.ec2.sftp_instance_id
  port             = 3000
}

# Allow ALB to access personal-site on port 3000
resource "aws_security_group_rule" "personal_site_alb_to_ec2" {
  count                    = var.acm_certificate_arn != "" && var.domain_name != "" ? 1 : 0
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.personal_site_alb[0].id
  security_group_id        = module.security_groups.sftp_sg_id
  description              = "Personal Site from ALB"
}
