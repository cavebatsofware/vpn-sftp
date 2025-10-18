resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-${var.environment}-ec2-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = { Name = "${var.project_name}-${var.environment}-ec2-role" }
}

resource "aws_iam_role_policy" "s3_access" {
  name = "s3-access-policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads"
        ],
        Resource = var.s3_bucket_arn
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:CreateMultipartUpload",
          "s3:UploadPart",
          "s3:CompleteMultipartUpload",
          "s3:AbortMultipartUpload",
          "s3:CopyObject",
          "s3:PutObjectAcl"
        ],
        Resource = "${var.s3_bucket_arn}/*"
      },
      { Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"], Resource = var.kms_key_arn }
    ]
  })
}

resource "aws_iam_role_policy" "ssm_get_parameters" {
  name = "ssm-get-parameters"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ssm_kms_decrypt" {
  count = var.parameter_store_kms_key_arn == null ? 0 : 1
  name  = "ssm-kms-decrypt"
  role  = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["kms:Decrypt"],
        Resource = var.parameter_store_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "route53_read" {
  name = "route53-read"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecr_access" {
  name = "ecr-access"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ],
        Resource = var.ecr_repository_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "ses_send_email" {
  name = "ses-send-email"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_personal_site_storage" {
  name = "s3-personal-site-storage"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::personal-site-access",
          "arn:aws:s3:::personal-site-access/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

output "instance_profile_name" { value = aws_iam_instance_profile.ec2_profile.name }
output "ec2_role_arn" { value = aws_iam_role.ec2_role.arn }
output "parameter_store_kms_key_arn" { value = var.parameter_store_kms_key_arn }
