#!/usr/bin/env bash
# Copia estados externos a una evidencia local ignorada por Git. No modifica
# los originales ni ejecuta Terraform.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
destination="$repo_root/artifacts/local-floci-state-backups/$stamp"
mkdir -p "$destination"

sources=(
  # Estados activos de la raíz local versionada. Se añaden primero para que un
  # respaldo siga siendo útil aunque los directorios efímeros de /tmp ya hayan
  # sido eliminados por el sistema.
  "$repo_root/infra/terraform/local-floci/terraform.tfstate"
  "$repo_root/infra/terraform/local-floci/terraform.tfstate.d/dev/terraform.tfstate"
  "$repo_root/infra/terraform/local-floci/terraform.tfstate.d/dev/terraform.tfstate.backup"
  "$repo_root/infra/terraform/local-floci/terraform.tfstate.d/test/terraform.tfstate"
  "$repo_root/infra/terraform/local-floci/terraform.tfstate.d/test/terraform.tfstate.backup"
  "$repo_root/infra/terraform/local-floci/terraform.tfstate.d/prod/terraform.tfstate"
  "$repo_root/infra/terraform/local-floci/terraform.tfstate.d/prod/terraform.tfstate.backup"
  "$repo_root/infra/terraform/local-floci-bootstrap/terraform.tfstate"
  "$repo_root/infra/terraform/local-floci-bootstrap/terraform.tfstate.backup"
  "/tmp/aegisvolt-floci-full/environments/terraform.tfstate.d/dev/terraform.tfstate"
  "/tmp/aegisvolt-floci-full/environments/terraform.tfstate.d/dev/terraform.tfstate.backup"
  "/tmp/aegisvolt-floci-terraform/terraform.tfstate"
  "/tmp/aegisvolt-floci-terraform/terraform.tfstate.d/dev/terraform.tfstate"
  "/tmp/aegisvolt-floci-terraform/terraform.tfstate.d/test/terraform.tfstate"
  "/tmp/aegisvolt-floci-terraform/terraform.tfstate.d/prod/terraform.tfstate"
)

copied=0
for source in "${sources[@]}"; do
  if [[ -f "$source" ]]; then
    if [[ "$source" == "$repo_root/"* ]]; then
      relative="repository/${source#"$repo_root/"}"
    else
      relative="${source#/tmp/}"
    fi
    target="$destination/$relative"
    mkdir -p "$(dirname "$target")"
    cp --preserve=mode,timestamps "$source" "$target"
    copied=$((copied + 1))
  fi
done

(( copied > 0 )) || { echo "No se encontraron estados fuente en /tmp." >&2; exit 66; }
(cd "$destination" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$destination/SHA256SUMS"
printf 'Respaldo inmutable creado: %s (%s archivos)\n' "$destination" "$copied"
