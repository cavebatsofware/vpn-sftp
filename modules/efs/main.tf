resource "aws_security_group" "efs" {
  name        = "${var.project_name}-${var.environment}-efs"
  description = "SG for EFS"
  vpc_id      = var.vpc_id

  # Allow NFS from provided client SGs
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.client_sg_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "this" {
  creation_token = "${var.project_name}-${var.environment}"
  encrypted      = true
  kms_key_id     = var.kms_key_arn
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name        = "${var.project_name}-${var.environment}-efs"
    Environment = var.environment
  }
}

resource "aws_efs_mount_target" "mt" {
  # Use stable, index-based keys so for_each keys are known at plan time
  for_each        = { for idx, sid in var.subnet_ids : tostring(idx) => sid }
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

output "file_system_id" { value = aws_efs_file_system.this.id }
output "security_group_id" { value = aws_security_group.efs.id }