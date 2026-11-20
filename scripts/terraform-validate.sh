#!/usr/bin/env bash
set -euo pipefail
mapfile -t directories < <(find infra/terraform -type f -name '*.tf' -printf '%h\n' | sort -u)
for directory in "${directories[@]}"; do
  terraform -chdir="$directory" fmt -check -recursive
done
terraform -chdir=infra/terraform/environments init -backend=false
terraform -chdir=infra/terraform/environments validate
