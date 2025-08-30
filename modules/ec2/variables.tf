variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "public_subnet_id" { type = string }
variable "sftp_security_group_id" { type = string }
variable "openvpn_security_group_id" { type = string }
variable "instance_profile_name" { type = string }
variable "arm64_ami_id" { type = string }
variable "s3_bucket_name" { type = string }
variable "public_key" { type = string }
variable "docker_compose_yml" { type = string }
variable "allocate_elastic_ip" {
    type = bool
    default = true
}
variable "vpn_port" { type = number }
variable "vpn_servername" { type = string }
variable "efs_file_system_id" { type = string }
variable "efs_mount_path" {
    type    = string
    default = "/mnt/efs"
}

# Optional: seed s3fs credentials
variable "s3fs_passwd" {
    description = "Content for ~/.passwd-s3fs in the form ACCESS_KEY_ID:SECRET_ACCESS_KEY[:SESSION_TOKEN]"
    type        = string
    default     = ""
    sensitive   = true
}
variable "s3fs_ssm_parameter_name" {
    description = "If set, fetch this SSM SecureString parameter for s3fs (format ACCESS_KEY_ID:SECRET_ACCESS_KEY[:SESSION_TOKEN])"
    type        = string
    default     = ""
}
variable "aws_profile" {
    description = "AWS CLI profile name to use when relying on ~/.aws/credentials"
    type        = string
    default     = "default"
}
