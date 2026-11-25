#!/usr/bin/env bash
# Terraform local CI para PR plan-only y push apply; nunca conecta a AWS real.
set -euo pipefail

action="${1:-}" environment="${2:-}"
[[ "$action" == plan || "$action" == apply ]] || { echo "Uso: $0 <plan|apply> <dev|test|prod>" >&2; exit 64; }
resolved="$(bash "$(dirname "$0")/floci-environment.sh" "$([[ "$action" == plan ]] && echo pr || echo push)" "$environment")"
[[ "$resolved" == "$environment" ]] || exit 64

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$repo_root/infra/terraform/local-floci"
backend_example="$root/backend.s3.tf.example"
backend_active="$root/backend.floci.s3.tf"

for cmd in terraform python3; do command -v "$cmd" >/dev/null || { echo "Falta herramienta: $cmd" >&2; exit 69; }; done
grep -Fq 's3 = "http://127.0.0.1:4567"' "$backend_example" || { echo "Backend no está anclado al endpoint local Floci." >&2; exit 78; }
grep -Fq 'access_key = "floci"' "$backend_example"
grep -Fq 'secret_key = "floci"' "$backend_example"
for credential_var in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE \
  AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN AWS_CONTAINER_CREDENTIALS_RELATIVE_URI \
  AWS_CONTAINER_CREDENTIALS_FULL_URI AWS_CONTAINER_AUTHORIZATION_TOKEN; do
  value="${!credential_var:-}"
  [[ -z "$value" ]] && continue
  if [[ "$credential_var" == AWS_ACCESS_KEY_ID && "$value" == floci ]] ||
     [[ "$credential_var" == AWS_SECRET_ACCESS_KEY && "$value" == floci ]]; then
    continue
  fi
  echo "Se detectó $credential_var; Floci CI se niega a continuar." >&2; exit 78
done
if [[ -e "$backend_active" ]]; then
  cmp -s "$backend_example" "$backend_active" || { echo "Backend activo difiere del backend Floci fijado." >&2; exit 78; }
else
  cp "$backend_example" "$backend_active"
fi

data_dir="$(mktemp -d "${TMPDIR:-/tmp}/aegisvolt-tfdata-${environment}.XXXXXX")"
plan_file="$data_dir/plan.tfplan"
summary_file="$data_dir/plan.md"
cleanup() { rm -rf "$data_dir"; }
trap cleanup EXIT
export TF_DATA_DIR="$data_dir/terraform-data"
tf=(terraform -chdir="$root")

"${tf[@]}" init -input=false
"${tf[@]}" workspace select "$environment" >/dev/null || {
  echo "Workspace remoto $environment no existe; no se crea automáticamente." >&2; exit 1;
}
"${tf[@]}" plan -input=false -lock-timeout=60s -var-file=floci.tfvars -out="$plan_file"
"${tf[@]}" show -json "$plan_file" | python3 -c '
import json,sys
p=json.load(sys.stdin)
changes=p.get("resource_changes",[])
destroy=[x["address"] for x in changes if "delete" in x.get("change",{}).get("actions",[])]
if destroy:
 print("Plan rechazado: contiene destrucción: " + ", ".join(destroy), file=sys.stderr)
 raise SystemExit(2)
counts={k:sum(1 for x in changes if k in x.get("change",{}).get("actions",[])) for k in ("create","update","delete")}
print("PLAN SUMMARY: " + json.dumps({"workspace":sys.argv[1],"changes":counts,"resource_changes":len(changes)},sort_keys=True))
' "$environment" > "$summary_file" || exit $?

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  { echo "## Terraform Floci · $environment"; echo; cat "$summary_file"; } >> "$GITHUB_STEP_SUMMARY"
fi
if [[ "$action" == apply ]]; then
  "${tf[@]}" apply -input=false -lock-timeout=60s "$plan_file"
fi
