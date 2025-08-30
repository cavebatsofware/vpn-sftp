# Contributing

Thanks for your interest in contributing!

- Use feature branches and open pull requests early for feedback.
- Keep PRs small and focused; one logical change per PR.
- Run `make plan` and ensure `terraform validate` passes.
- Include updates to `environments.examples/` when adding variables.
- Do not commit secrets. Use SSM/KMS and `.gitignore`.
- Explain user-visible changes in the PR description.
- Prefer module-local refactors; avoid breaking module inputs/outputs.

## Development tips
- Use environment-specific workspaces (dev/staging/prod).
- Validate Docker Compose rendering with `docker compose config` when debugging.
- For s3fs, prefer SSM SecureString to pass credentials rather than inline.

## Reporting Issues
Please include:
- Environment (dev/staging/prod), Terraform version, AWS region
- Steps to reproduce
- Relevant plan/apply output and logs
- Expected vs actual behavior
