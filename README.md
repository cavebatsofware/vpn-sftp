# vpn-sftp (WireGuard)

Production-ready Terraform to deploy an SFTP service (SFTPGo) behind a WireGuard VPN on AWS with hardened networking, logging, and persistent storage.

Highlights
- Multi-environment (dev/staging/prod) via workspaces and per-env tfvars
- SFTPGo with EFS-backed state and S3-backed data via Mountpoint for Amazon S3; access over VPN (HTTP/WEBDAV) or SSH/SFTP
- WireGuard VPN on Amazon Linux 2023 ARM64 Gravitron (t4g.*), simple client export
- Optional ALB + ACM for SFTPGo Web UI; Route 53 DNS wiring (wip, coming)
- CloudWatch metrics/alerts; node exporter
- Clean, idempotent bootstraps using Docker Compose in user-data

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
   - Optional DNS: `domain_name`, `route53_zone_id` or `create_hosted_zone` (this isn't implemented at time of writing)
   - Optional ALB for SFTP UI: `enable_sftp_ui_alb=true`, `acm_certificate_arn`, `sftp_ui_subdomain` (coming soon)
   - Optional s3fs credentials (see next section)
3) Initialize Terraform
   - make init ENV=dev
4) Plan and apply
   - make plan ENV=dev
   - make apply ENV=dev

What gets created
- VPC, subnets, route tables
- Security groups (SSH, SFTP, UI, VPN)
- S3 bucket + KMS key (SSE-KMS)
- EFS file system (for SFTPGo state and WireGuard config)
- IAM role/policies and instance profile
- EC2: single host (Amazon Linux 2023 ARM64) running both SFTPGo and WireGuard via Docker Compose
- Optional: ALB + Route53 for SFTPGo UI (WIP)

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

## SFTPGo and VPN specifics
- SFTPGo
  - Data provider: SQLite at `/var/lib/sftpgo/sftpgo.db` (on EFS)
  - Defaults: new users on local filesystem under `/data` (s3fs mount)
  - Admin password: `/opt/docker-app/secrets/sftpgo_admin_password` (seeded from SSM if present)
  - UI and REST API listen on 8080 (restrict via SG or place behind ALB)
- WireGuard
  - UDP ${wireguard_port} (default 51820)
  - Easy client generation via `scripts/wireguard-client.sh`

## DNS and HTTPS (optional)
- Set `domain_name` and either `route53_zone_id` or `create_hosted_zone = true`
- Enable ALB with `enable_sftp_ui_alb = true` and set `acm_certificate_arn`
- Terraform will publish records for SFTP UI and VPN based on subdomains

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
