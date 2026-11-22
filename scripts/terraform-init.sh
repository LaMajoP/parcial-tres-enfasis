#!/usr/bin/env bash
set -euo pipefail
bucket="${1:?Uso: scripts/terraform-init.sh <bucket-state> <region>}"
region="${2:?Uso: scripts/terraform-init.sh <bucket-state> <region>}"
[[ "$bucket" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo "Nombre de bucket S3 inválido." >&2; exit 64; }
[[ "$region" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || { echo "Región AWS inválida." >&2; exit 64; }
terraform -chdir=infra/terraform/environments init -reconfigure -input=false -backend-config="bucket=${bucket}" -backend-config="region=${region}"
for env in dev test prod; do terraform -chdir=infra/terraform/environments workspace select "$env" 2>/dev/null || terraform -chdir=infra/terraform/environments workspace new "$env" -no-color; done
terraform -chdir=infra/terraform/environments workspace select dev
