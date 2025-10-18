# vpn-sftp (WireGuard)

Terraform configuration for deploying SFTP (SFTPGo), personal site, and WireGuard VPN on AWS.

## Features
- Multi-environment (dev/staging/prod) via workspaces and per-env tfvars
- SFTPGo with EFS-backed state and S3-backed data via Mountpoint for Amazon S3
- Personal site with PostgreSQL database, admin panel, and S3 storage
- WireGuard VPN on Amazon Linux 2023 ARM64 (t4g.*)
- ALB + ACM for HTTPS; Route 53 DNS integration
- CloudWatch metrics/alerts
- Docker Compose-based service orchestration

## Prerequisites
- Terraform >= 1.6
- AWS CLI v2 authenticated to an AWS account with permissions for VPC, EC2, EFS, IAM, S3, Route53, ACM, SSM
- A public SSH key to access the instances (set `public_key` in tfvars)
- Optional: Docker locally to validate the rendered compose file (`docker compose config`)

Links
- Terraform: https://developer.hashicorp.com/terraform
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html
- SFTPGo: https://github.com/drakkan/sftpgo
- WireGuard: https://www.wireguard.com/

## Project structure
- Root Terraform and common variables: `*.tf`
- Environments: `environments/{dev,staging,prod}` with `backend.tfvars` and `terraform.tfvars`
- Modules: `modules/*` (vpc, security-groups, iam, s3, efs, ec2, dns, monitoring, alb)
- User-data (instance bootstraps): `modules/ec2/user_data/*`
- Docker Compose template (stack): `docker-compose/templates/docker-compose.stack.yml.tpl`
- Operational scripts: `scripts/`

## Setup
1) Copy example environment configs (optional)
   - Use `environments.examples/*` as a reference
2) Edit `environments/<env>/terraform.tfvars`
   - Required: `aws_region`, `project_name`, `environment`, VPC CIDRs, `allowed_ssh_cidrs`, `admin_access_cidrs`, `public_key`
   - Required for personal site: `postgres_password`, `personal_site_storage_bucket`, `aws_ses_from_email`
   - DNS: `domain_name`, `route53_zone_id` or `create_hosted_zone`
   - HTTPS: `acm_certificate_arn`, `personal_site_subdomain`
3) Initialize Terraform
   - make init ENV=dev
4) Plan and apply
   - make plan ENV=dev
   - make apply ENV=dev

## Infrastructure
- VPC, subnets, route tables, security groups
- S3 buckets (SFTP data, personal site storage) + KMS encryption
- EFS file system (SFTPGo state, WireGuard config, PostgreSQL data)
- IAM roles with policies for S3, SES, ECR access
- EC2 instance (Amazon Linux 2023 ARM64) running:
  - SFTPGo (SFTP/WebDAV server)
  - WireGuard (VPN)
  - PostgreSQL (personal site database)
  - Personal site application
- ALB + Route53 for personal site HTTPS access
- CloudWatch logs and metrics

## S3 access via Mountpoint for Amazon S3
Mountpoint mounts your S3 bucket at `/mnt/s3`, which is bind-mounted as `/data` into the SFTPGo container. New users default to local FS under `/data/[username]`.

Credentials
- Uses the instance profile by default; no local credential files are required.

On boot, user-data will:
- Install Mountpoint (`mount-s3`) on Amazon Linux 2023
- Create a systemd unit that mounts `<bucket> -> /mnt/s3` with uid/gid 1000

Note: `scripts/seed-s3fs-passwd.sh` is no longer required when using Mountpoint.

## Using the Makefile
- make init ENV=dev       # terraform init + workspace select/create
- make plan ENV=dev       # validate + checkov + plan -> plans/dev.tfplan
- make apply ENV=dev      # apply plan
- make clean              # clean .terraform and plans
- make security-scan      # run checkov (best effort)

Backend note: `make init` uses `environments/<env>/backend.tfvars` to configure state.

## Operational scripts
- `scripts/wireguard-client.sh`
  - Connects to the VPN instance, creates a WireGuard peer, and prints the client config.
  - Requires SSH access to the VPN host.
- `scripts/sftpgo-create-user.sh`
  - Authenticates to SFTPGo’s REST API using Basic auth to obtain a token, then creates a user.
  - Reads Terraform outputs for IP/region/bucket; fetches admin password from SSM path `/<project>/<env>/sftpgo/admin-password`.
  - Flags: `-e <env> -u <username> -p <password>`; supports OTP via `-O`.
- `scripts/seed-s3fs-passwd.sh`
  - Prints `ACCESS:SECRET[:SESSION]` from a local AWS profile or writes it to SSM for use as `s3fs_ssm_parameter_name`.
- `scripts/health-check.sh`
  - Basic checks; customize endpoints as needed.

## Service Configuration

### Personal Site
- PostgreSQL 16 database on EFS at `/mnt/efs/postgres`
- Database migrations run automatically on container start when `MIGRATE_DB=true`
- Required environment variables:
  - `DATABASE_URL`: PostgreSQL connection string
  - `SITE_DOMAIN`: Base domain for the site
  - `SITE_URL`: Full URL for the site
  - `AWS_SES_FROM_EMAIL`: Email address for sending verification emails
  - `S3_BUCKET_NAME`: S3 bucket for file storage
- Access via ALB at configured subdomain
- Deploy updates: `./scripts/deploy-personal-site.sh <stack_ip>`

### SFTPGo
- Data provider: SQLite at `/var/lib/sftpgo/sftpgo.db` (on EFS)
- User storage: local filesystem under `/data` (Mountpoint S3)
- Admin password: `/opt/docker-app/secrets/sftpgo_admin_password` (from SSM)
- UI and REST API on port 8080

### WireGuard
- UDP port (default: 51820)
- Client generation: `./scripts/wireguard-client.sh <stack_ip>`

## DNS and HTTPS
- Set `domain_name` and either `route53_zone_id` or `create_hosted_zone = true`
- Set `acm_certificate_arn` for HTTPS
- Configure `personal_site_subdomain` for site access
- Route 53 records created automatically for configured services

## Security notes
- Do not commit secrets. Use SSM/KMS.
- Restrict admin UI access to VPN or trusted CIDRs.
- Keep your AMIs and Docker images up-to-date.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for workflow and best practices.

## License
Choose MIT or GPLv3 for your fork/use.
- Include `LICENSE-MIT` or `LICENSE-GPLv3` in your published repo (or rename your choice to `LICENSE`).

## AWS pricing resources
- EC2 On‑Demand pricing: https://aws.amazon.com/ec2/pricing/on-demand/
- EC2 Graviton (t4g.*) pricing: https://aws.amazon.com/ec2/graviton/pricing/
- S3 pricing: https://aws.amazon.com/s3/pricing/
- S3 requests and data transfer: https://aws.amazon.com/s3/pricing/#Request_and_data_transfer_pricing
- EFS pricing: https://aws.amazon.com/efs/pricing/
- Data transfer pricing: https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer

Notes
- The ~$15/month estimate assumes two t4g.micro instances in a low‑cost region and excludes S3/EFS storage and egress.
- S3 costs include storage per GB‑month, requests (PUT/GET), and data transfer.
- EFS costs include storage per GB‑month; provisioned throughput (if enabled) is extra. This is a very low volume cost for this service as the space and access requirements are very low for these files.
- CloudWatch logging/metrics and Elastic IPs can add small additional charges.

## Why run your own VPN?
- Privacy and control: traffic terminates on infrastructure you manage—not a third-party provider.
- Security: tight security groups, audited IAM, and known images; no shared multi-tenant VPN surface.
- Cost and scale: about $15 USD/month at time of writing for two t4g.micro instances (region-dependent), excluding S3 storage and transfer. Connections are effectively unlimited until the instance tops out.
- Flexibility: full control over authentication, routing, and service composition (SFTPGo, WireGuard, monitoring).
