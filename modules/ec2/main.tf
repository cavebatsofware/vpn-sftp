resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-${var.environment}-keypair"
  public_key = var.public_key
}

resource "aws_instance" "stack_server" {
  ami                         = var.arm64_ami_id
  instance_type               = "t4g.micro"
  key_name                    = aws_key_pair.main.key_name
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.sftp_security_group_id, var.vpn_security_group_id]
  iam_instance_profile        = var.instance_profile_name
  ebs_optimized               = true
  user_data_replace_on_change = true
  credit_specification {
    cpu_credits = "unlimited"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 16
    encrypted             = true
    delete_on_termination = true
  }
  user_data = templatefile("${path.module}/user_data/stack_setup.sh", {
    s3_bucket_name     = var.s3_bucket_name,
    aws_region         = var.aws_region,
    environment        = var.environment,
    project_name       = var.project_name,
    docker_compose_yml = var.docker_compose_yml,
    efs_file_system_id = var.efs_file_system_id,
    efs_mount_path     = var.efs_mount_path,
    s3fs_passwd        = var.s3fs_passwd,
    s3fs_ssm_parameter = var.s3fs_ssm_parameter_name,
    aws_profile        = var.aws_profile
  })
  tags = { Name = "${var.project_name}-${var.environment}-stack", Service = "sftp+vpn", Architecture = "arm64" }
}

output "sftp_instance_id" { value = aws_instance.stack_server.id }
output "vpn_instance_id" { value = aws_instance.stack_server.id }
output "sftp_public_ip" { value = aws_instance.stack_server.public_ip }
output "vpn_public_ip" { value = aws_instance.stack_server.public_ip }
output "sftp_private_ip" { value = aws_instance.stack_server.private_ip }
output "vpn_private_ip" { value = aws_instance.stack_server.private_ip }

resource "aws_eip" "stack" {
  count    = var.allocate_elastic_ip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.stack_server.id
}

output "sftp_effective_ip" {
  value = var.allocate_elastic_ip && length(aws_eip.stack) > 0 ? aws_eip.stack[0].public_ip : aws_instance.stack_server.public_ip
}

output "vpn_effective_ip" {
  value = var.allocate_elastic_ip && length(aws_eip.stack) > 0 ? aws_eip.stack[0].public_ip : aws_instance.stack_server.public_ip
}

output "efs_mount_path" { value = var.efs_mount_path }
