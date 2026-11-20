#!/usr/bin/env bash
set -euo pipefail
bucket="${1:?Uso: scripts/terraform-init.sh <bucket-state> <region>}"
region="${2:?Uso: scripts/terraform-init.sh <bucket-state> <region>}"
terraform -chdir=infra/terraform/environments init -reconfigure -backend-config="bucket=${bucket}" -backend-config="region=${region}"
for env in dev test prod; do terraform -chdir=infra/terraform/environments workspace select "$env" 2>/dev/null || terraform -chdir=infra/terraform/environments workspace new "$env"; done
terraform -chdir=infra/terraform/environments workspace select dev
