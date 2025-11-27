resource "aws_security_group" "sftp" {
  name        = "${var.project_name}-${var.environment}-sftp"
  description = "Security group for SFTP server"
  vpc_id      = var.vpc_id

  ingress {
    description = "SFTP"
    from_port   = var.sftp_port
    to_port     = var.sftp_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_access_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-${var.environment}-sftp-sg", Service = "sftp" }
}

resource "aws_security_group" "vpn" {
  name        = "${var.project_name}-${var.environment}-vpn"
  description = "Security group for VPN (WireGuard) server"
  vpc_id      = var.vpc_id

  # WireGuard UDP
  ingress {
    description = "WireGuard UDP"
    from_port   = var.wireguard_port
    to_port     = var.wireguard_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_access_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-${var.environment}-vpn-sg", Service = "vpn" }
}

output "sftp_sg_id" { value = aws_security_group.sftp.id }
output "vpn_sg_id" { value = aws_security_group.vpn.id }
