#!/usr/bin/env bash
set -euo pipefail
for directory in infra/terraform/bootstrap-state infra/terraform/environments; do
  terraform -chdir="$directory" fmt -check -recursive
  terraform -chdir="$directory" init -backend=false -input=false
  terraform -chdir="$directory" validate
done
python3 scripts/validate_terraform_layout.py
