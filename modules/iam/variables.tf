variable "project_name" { type = string }
variable "environment" { type = string }
variable "s3_bucket_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "parameter_store_kms_key_arn" {
  type    = string
  default = null
}
