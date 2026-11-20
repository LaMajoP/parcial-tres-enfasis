#!/usr/bin/env bash
set -euo pipefail
environment="${1:?Uso: scripts/terraform-plan.sh dev|test|prod}"
case "$environment" in dev|test|prod) ;; *) echo "Ambiente inválido" >&2; exit 64;; esac
current="$(terraform -chdir=infra/terraform/environments workspace show)"
if [[ "$current" == "default" || "$current" != "$environment" ]]; then
  terraform -chdir=infra/terraform/environments workspace select "$environment"
fi
terraform -chdir=infra/terraform/environments plan -var-file="terraform.tfvars" -out="plan-${environment}.tfplan"
