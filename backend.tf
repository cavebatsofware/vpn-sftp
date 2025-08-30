# Backend is configured at init time via -backend-config or disabled for local state
terraform {
  backend "s3" {}
}
