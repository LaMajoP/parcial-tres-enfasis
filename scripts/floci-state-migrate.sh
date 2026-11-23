#!/usr/bin/env bash
# Preflight y migración deliberada de la raíz local-floci a S3 Floci.
# No configura ni usa AWS real y nunca opera sobre local-floci-bootstrap.
set -euo pipefail

mode="${1:-preflight}"
case "$mode" in preflight|migrate) ;; *) echo "Uso: $0 [preflight|migrate]" >&2; exit 64;; esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$repo_root/infra/terraform/local-floci"
backend_example="$root/backend.s3.tf.example"
backend_active="$root/backend.floci.s3.tf"
bucket="aegisvolt-floci-terraform-state"
endpoint="http://127.0.0.1:4567"
region="us-east-2"
workspaces=(dev test prod)
state_dir="$root/terraform.tfstate.d"

for cmd in terraform aws curl python3 sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Falta herramienta: $cmd" >&2; exit 69; }
done
[[ -f "$backend_example" ]] || { echo "Falta configuración $backend_example" >&2; exit 66; }

aws_local=(env AWS_ACCESS_KEY_ID=floci AWS_SECRET_ACCESS_KEY=floci AWS_DEFAULT_REGION="$region" aws --endpoint-url "$endpoint")

check_locals() {
  local env state lineage
  local -A seen_lineages=()
  for env in "${workspaces[@]}"; do
    state="$state_dir/$env/terraform.tfstate"
    [[ -s "$state" ]] || { echo "No existe state local legible para $env: $state" >&2; return 1; }
    lineage="$(python3 - "$state" "$env" <<'PY'
import json, sys
from pathlib import Path
s = json.loads(Path(sys.argv[1]).read_text())
env = sys.argv[2]
if s.get("version") != 4 or not s.get("lineage") or not isinstance(s.get("serial"), int):
    raise SystemExit(f"State inválido/incompleto para {env}")
if not isinstance(s.get("resources"), list):
    raise SystemExit(f"Campo resources inválido para {env}")
print(s["lineage"])
print(f"LOCAL {env}: lineage={s['lineage']} serial={s['serial']} resources={len(s['resources'])}", file=sys.stderr)
PY
    )"
    [[ -z "${seen_lineages[$lineage]:-}" ]] || { echo "Lineage duplicado en $env y ${seen_lineages[$lineage]}" >&2; return 1; }
    seen_lineages[$lineage]="$env"
  done
}

remote_key_exists() {
  local key="$1" response
  response="$("${aws_local[@]}" s3api list-object-versions --bucket "$bucket" --prefix "$key" --output json)" || {
    echo "No se pudo listar versiones para $key; error de endpoint/autenticación." >&2
    return 1
  }
  python3 -c 'import json,sys; k=sys.argv[1]; d=json.load(sys.stdin); found=[x.get("Key") for g in ("Versions","DeleteMarkers") for x in d.get(g,[]) if x.get("Key")==k]; found and sys.exit("Destino remoto/versiones ya existen: "+k)' "$key" <<<"$response"
}

check_s3_readonly() {
  curl --silent --show-error --fail "$endpoint/_localstack/health" >/dev/null || { echo "Floci no responde en $endpoint" >&2; return 1; }
  "${aws_local[@]}" s3api head-bucket --bucket "$bucket" >/dev/null || { echo "No se pudo confirmar el bucket (autenticación/endpoint/bucket)." >&2; return 1; }
  local versioning
  versioning="$("${aws_local[@]}" s3api get-bucket-versioning --bucket "$bucket" --query Status --output text)" || { echo "No se pudo leer versionado del bucket." >&2; return 1; }
  [[ "$versioning" == Enabled ]] || { echo "Versionado S3 no está Enabled: ${versioning:-ausente}" >&2; return 1; }
  echo "S3 VERSIONING: $bucket = $versioning"
}

check_destinations_empty() {
  local env key lock
  for env in "${workspaces[@]}"; do
    key="env/$env/terraform.tfstate"
    lock="$key.tflock"
    remote_key_exists "$key"
    remote_key_exists "$lock"
    echo "DESTINO VACÍO: s3://$bucket/$key (+ .tflock)"
  done
}

check_locals
check_s3_readonly

if [[ "$mode" == preflight ]]; then
  check_destinations_empty
  if [[ -e "$backend_active" ]]; then
    echo "Backend activo detectado. El preflight no modifica nada; inspección manual necesaria antes de migrar." >&2
    exit 1
  fi
  printf '\nPREFLIGHT OK. Solo se leyeron estados, salud y S3; no se inicializó Terraform ni se escribieron objetos.\n'
  exit 0
fi

[[ "${CONFIRM_FLOCI_STATE_MIGRATION:-}" == "I_UNDERSTAND" ]] || {
  echo "Migración bloqueada. Se requiere CONFIRM_FLOCI_STATE_MIGRATION=I_UNDERSTAND y autorización explícita." >&2
  exit 77
}
[[ ! -e "$backend_active" ]] || {
  echo "Backend activo encontrado. No se reconfigura ni reintenta automáticamente: inspeccione los tres objetos remotos y recupere manualmente antes de continuar." >&2
  exit 65
}
[[ ! -e "$root/backend.tf" ]] || { echo "Hay otra configuración backend activa; inspección manual requerida." >&2; exit 65; }
check_destinations_empty

backup_output="$("$repo_root/scripts/floci-state-backup.sh")"
backup_dir="${backup_output#Respaldo inmutable creado: }"
backup_dir="${backup_dir% (*}"
[[ -d "$backup_dir" && -s "$backup_dir/SHA256SUMS" ]] || { echo "No se pudo localizar el backup; cancelado." >&2; exit 1; }
(cd "$backup_dir" && sha256sum -c SHA256SUMS) || { echo "Hashes del backup inválidos; cancelado." >&2; exit 1; }

declare -A original_hashes=()
for env in "${workspaces[@]}"; do
  cmp -s "$state_dir/$env/terraform.tfstate" "$backup_dir/repository/infra/terraform/local-floci/terraform.tfstate.d/$env/terraform.tfstate" || {
    echo "El state $env difiere del backup recién creado; cancelado." >&2; exit 1;
  }
  original_hashes[$env]="$(sha256sum "$backup_dir/repository/infra/terraform/local-floci/terraform.tfstate.d/$env/terraform.tfstate" | cut -d ' ' -f1)"
done

cp "$backend_example" "$backend_active"
echo "Backend staged. Ejecutando init -migrate-state una vez para el backend local completo."
echo "No asumir migración completa: si Terraform falla, backend activo y backup se conservan; la siguiente ejecución abortará para recuperación manual."
if ! terraform -chdir="$root" init -migrate-state; then
  echo "init -migrate-state falló. No reintente ni use -reconfigure. Inspeccione todos los destinos env/{dev,test,prod}, preserve archivos locales y recupere con el backup verificado." >&2
  exit 1
fi

for env in "${workspaces[@]}"; do
  backup_state="$backup_dir/repository/infra/terraform/local-floci/terraform.tfstate.d/$env/terraform.tfstate"
  current_hash="$(sha256sum "$backup_state" | cut -d ' ' -f1)"
  [[ "$current_hash" == "${original_hashes[$env]}" ]] || {
    echo "Backup original cambió durante init para $env. Deténgase y recupere manualmente." >&2
    exit 1
  }
done

# Terraform's init migration is intended to migrate the backend state set, but
# we independently require each workspace to exist remotely and match source.
for env in "${workspaces[@]}"; do
  terraform -chdir="$root" workspace select "$env" >/dev/null || {
    echo "Workspace remoto $env ausente; migración parcial. No reintente automáticamente." >&2; exit 1;
  }
  pulled_file="$(mktemp)"
  if ! terraform -chdir="$root" state pull > "$pulled_file"; then
    rm -f "$pulled_file"
    echo "state pull falló para $env (endpoint/auth/state remoto); migración parcial o no verificable." >&2
    exit 1
  fi
  python3 - "$pulled_file" "$backup_dir/repository/infra/terraform/local-floci/terraform.tfstate.d/$env/terraform.tfstate" "$env" <<'PY'
import json, sys
from pathlib import Path
remote_path, local_path, env = sys.argv[1:]
remote = json.loads(Path(remote_path).read_text())
local = json.loads(Path(local_path).read_text())
if not remote.get("lineage") or not isinstance(remote.get("serial"), int):
    raise SystemExit(f"State remoto vacío/inválido para {env}")
if remote["lineage"] != local["lineage"]:
    raise SystemExit(f"Lineage distinto en {env}: {remote['lineage']} != {local['lineage']}")
if remote["serial"] not in (local["serial"], local["serial"] + 1):
    raise SystemExit(f"Serial remoto fuera del rango esperado para migración en {env}: local={local['serial']} remoto={remote['serial']}")
if remote.get("resources") != local.get("resources"):
    raise SystemExit(f"Recursos distintos en {env}")
print(f"VERIFIED {env}: lineage={remote['lineage']} serial={remote['serial']} local_serial={local['serial']} resources={len(remote['resources'])}")
PY
  rm -f "$pulled_file"
  plan_rc=0
  terraform -chdir="$root" plan -input=false -lock-timeout=30s -var-file=floci.tfvars -detailed-exitcode || plan_rc=$?
  [[ "$plan_rc" == 0 ]] || {
    echo "Plan de $env no terminó en No changes (código $plan_rc). La migración queda sin validar; preserve backend, backup y states locales." >&2
    exit 1
  }
done

echo "Migración verificada para dev/test/prod. Backup y states locales originales conservados."
