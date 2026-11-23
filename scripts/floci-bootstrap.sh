#!/usr/bin/env bash
# Bootstrap S3/ECR exclusivamente contra Floci. No toca providers, backends ni
# estados de producción; el state de esta raíz es local e independiente.
set -euo pipefail

action="${1:-}"
case "$action" in init|plan|apply|outputs) ;; *)
  echo "Uso: $0 <init|plan|apply|outputs>" >&2
  exit 64
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$repo_root/infra/terraform/local-floci-bootstrap"
tf=(terraform -chdir="$root")
plan_file="/tmp/aegisvolt-floci-bootstrap.tfplan"

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

if [[ "$action" == "init" ]]; then
  "${tf[@]}" init -input=false
  exit 0
fi

if [[ ! -d "$root/.terraform/providers" ]]; then
  "${tf[@]}" init -input=false
fi

case "$action" in
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
