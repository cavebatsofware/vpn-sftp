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
  ingress {
    description = "SFTPGo Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
  # Only allow from the OpenVPN instance (packets from VPN clients are SNATed to this ENI)
  security_groups = [aws_security_group.openvpn.id]
  }
  ingress {
    description = "SFTPGo WebDAV"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
  security_groups = [aws_security_group.openvpn.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-${var.environment}-sftp-sg", Service = "sftp" }
}

resource "aws_security_group" "openvpn" {
  name        = "${var.project_name}-${var.environment}-openvpn"
  description = "Security group for OpenVPN server"
  vpc_id      = var.vpc_id

  ingress {
    description = "OpenVPN UDP"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "OpenVPN TCP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "OpenVPN Admin"
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = var.admin_access_cidrs
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
  tags = { Name = "${var.project_name}-${var.environment}-openvpn-sg", Service = "openvpn" }
}

output "sftp_sg_id" { value = aws_security_group.sftp.id }
output "openvpn_sg_id" { value = aws_security_group.openvpn.id }
