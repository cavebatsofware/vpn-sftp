output "repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.personal_site.repository_url
}

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.personal_site.name
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.personal_site.arn
}