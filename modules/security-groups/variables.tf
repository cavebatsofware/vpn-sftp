variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "allowed_ssh_cidrs" { type = list(string) }
variable "admin_access_cidrs" { type = list(string) }
variable "sftp_port" { type = number }
