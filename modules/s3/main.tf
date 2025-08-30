resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "sftp_data" {
  bucket = "${var.project_name}-${var.environment}-sftp-data-${random_string.bucket_suffix.result}"
  tags = { Name = "${var.project_name}-${var.environment}-sftp-data", Purpose = "sftp-backend-storage", Environment = var.environment }
}

resource "aws_s3_bucket_versioning" "sftp_data" {
  bucket = aws_s3_bucket.sftp_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "s3_encryption" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "s3_encryption" {
  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3_encryption.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sftp_data" {
  bucket = aws_s3_bucket.sftp_data.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "sftp_data" {
  bucket = aws_s3_bucket.sftp_data.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

output "bucket_name" { value = aws_s3_bucket.sftp_data.bucket }
output "bucket_arn" { value = aws_s3_bucket.sftp_data.arn }
output "kms_key_arn" { value = aws_kms_key.s3_encryption.arn }
