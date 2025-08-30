variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "client_sg_ids" { type = list(string) }
variable "kms_key_arn" {
	type    = string
	default = null
}
