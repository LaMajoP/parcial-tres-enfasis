#!/usr/bin/env bash
# Opera la raíz Terraform aislada de Floci. Los estados se separan por
# workspace local y el modo recover sólo copia el state legado después de que
# scripts/floci-state-backup.sh haya preservado el original.
set -euo pipefail

usage() {
  echo "Uso: $0 <init|plan|apply|recover-dev-state|outputs> [dev|test|prod]" >&2
  exit 64
}

action="${1:-}"
environment="${2:-}"
case "$action" in init|plan|apply|recover-dev-state|outputs) ;; *) usage ;; esac
if [[ "$action" == init ]]; then
  [[ -z "$environment" ]] || usage
else
  case "$environment" in dev|test|prod) ;; *) usage ;; esac
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$repo_root/infra/terraform/local-floci"
tf=(terraform -chdir="$root")
plan_file="$root/plan-${environment}.tfplan"

create_non_destructive_plan() {
  "${tf[@]}" plan -input=false -lock-timeout=5m -var-file=floci.tfvars -out="$plan_file"
  "${tf[@]}" show -json "$plan_file" | node -e '
    let text = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => { text += chunk; });
    process.stdin.on("end", () => {
      const plan = JSON.parse(text);
      const deleting = (plan.resource_changes ?? []).filter((change) =>
        change.change.actions.includes("delete")
      ).map((change) => change.address);
      if (deleting.length) {
        console.error(`Plan rechazado: contiene acciones delete: ${deleting.join(", ")}`);
        process.exit(2);
      }
    });
  '
}

if [[ "$action" == init ]]; then
  "${tf[@]}" init -input=false
  exit 0
fi

# Evita consultar el registry en cada operación cuando la inicialización y el
# lockfile ya se verificaron. Use `init` explícitamente para actualizar módulos
# o proveedores.
if [[ ! -d "$root/.terraform/providers" ]]; then
  "${tf[@]}" init -input=false
fi
"${tf[@]}" workspace select "$environment" >/dev/null 2>&1 || "${tf[@]}" workspace new "$environment" >/dev/null

case "$action" in
  recover-dev-state)
    [[ "$environment" == dev ]] || { echo "Sólo existe state completo legado para dev." >&2; exit 64; }
    "$repo_root/scripts/floci-state-backup.sh"
    source_state="/tmp/aegisvolt-floci-full/environments/terraform.tfstate.d/dev/terraform.tfstate"
    [[ -f "$source_state" ]] || { echo "No existe $source_state" >&2; exit 66; }
    # No se usa -force: Terraform rechaza una colisión de lineage en vez de
    # sobrescribir un estado que el operador pudiera haber creado después.
    "${tf[@]}" state push "$source_state"
    ;;
  plan)
    "${tf[@]}" plan -input=false -lock-timeout=5m -var-file=floci.tfvars -out="$plan_file"
    ;;
  apply)
    "$repo_root/scripts/floci-state-backup.sh"
    create_non_destructive_plan
    "${tf[@]}" apply -input=false -lock-timeout=5m "$plan_file"
    ;;
  outputs)
    "${tf[@]}" output
    ;;
  *)
    echo "Acción no permitida: ${action:-<vacía>}" >&2
    exit 64
    ;;
esac
