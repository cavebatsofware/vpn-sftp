.PHONY: help init validate plan apply clean security-scan
.DEFAULT_GOAL := help

ENV ?= dev
REGION ?= us-east-1
TF_VAR_FILE = environments/$(ENV)/terraform.tfvars
PLAN_FILE = plans/$(ENV).tfplan
BACKEND ?= true

help:
	@echo "Targets: init plan apply destroy drift-check security-scan clean"

init:
	@echo "Initializing Terraform for $(ENV)..."
	@mkdir -p plans
	@if [ "$(BACKEND)" = "true" ]; then terraform init -backend-config=environments/$(ENV)/backend.tfvars; else terraform init -backend=false; fi
	@terraform workspace select $(ENV) || terraform workspace new $(ENV)

validate: init
	terraform validate
	terraform fmt -check=true

security-scan:
	@command -v checkov >/dev/null 2>&1 || pip3 install --user checkov >/dev/null 2>&1 || true
	checkov -d . --framework terraform || true

plan: validate security-scan
	@mkdir -p plans
	terraform plan -var-file=$(TF_VAR_FILE) -out=$(PLAN_FILE)

apply:
	terraform apply $(PLAN_FILE)

clean:
	rm -rf .terraform/ plans/ .terraform.lock.hcl
