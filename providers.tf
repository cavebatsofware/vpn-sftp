provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment  = var.environment
      Project      = var.project_name
      ManagedBy    = "terraform"
      Architecture = "arm64"
      CostCenter   = var.cost_center
      Owner        = var.owner
    }
  }
}
