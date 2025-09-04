output "region" { value = var.aws_region }
output "project_name" { value = var.project_name }

output "sftp_public_ip" {
  value       = module.ec2.sftp_public_ip
  description = "Public IP of SFTP instance"
}

output "vpn_public_ip" {
  value       = module.ec2.vpn_public_ip
  description = "Public IP of VPN instance"
}
output "sftp_private_ip" {
  value       = module.ec2.sftp_private_ip
  description = "Private IP of SFTP instance"
}
output "vpn_private_ip" {
  value       = module.ec2.vpn_private_ip
  description = "Private IP of VPN instance"
}

output "s3_bucket_name" {
  value       = module.s3.bucket_name
  description = "Name of S3 bucket used for SFTP backend"
}

output "sftp_effective_ip" {
  value       = try(module.ec2.sftp_effective_ip, module.ec2.sftp_public_ip)
  description = "Effective public IP (Elastic IP if allocated) for SFTP"
}

output "vpn_effective_ip" {
  value       = try(module.ec2.vpn_effective_ip, module.ec2.vpn_public_ip)
  description = "Effective public IP (Elastic IP if allocated) for VPN"
}

output "wireguard_port" {
  value       = var.wireguard_port
  description = "WireGuard UDP port"
}

output "s3_role_arn" {
  value       = module.iam.ec2_role_arn
  description = "Role ARN used for S3 access"
}