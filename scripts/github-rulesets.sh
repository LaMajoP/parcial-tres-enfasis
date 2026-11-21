#!/usr/bin/env bash
# Inspecciona y prepara rulesets sin requerir GitHub CLI. No modifica GitHub
# salvo con --apply, token explícito y rulesets ausentes; nunca sobrescribe uno.
set -euo pipefail

apply=false
if [[ "${1:-}" == "--apply" ]]; then
  apply=true
  shift
fi
repository="${1:-${GITHUB_REPOSITORY:-}}"
[[ -n "$repository" ]] || { echo "Uso: scripts/github-rulesets.sh [--apply] owner/repo" >&2; exit 64; }
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Repositorio inválido: $repository" >&2; exit 64; }
command -v curl >/dev/null || { echo "curl es obligatorio." >&2; exit 69; }
command -v python3 >/dev/null || { echo "python3 es obligatorio." >&2; exit 69; }

api="https://api.github.com/repos/$repository/rulesets"
headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then headers+=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi

work_dir="$(mktemp -d)"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

curl --fail-with-body --silent --show-error "${headers[@]}" "$api" > "$work_dir/current.json"

checks='["promotion-policy","lockfile","lint-build","unit-tests","integration-tests","resilience-tests","e2e-tests","image-build","terraform-offline","terraform-plan"]'
for branch in dev test prod; do
  payload="$work_dir/$branch.json"
  python3 - "$branch" "$checks" > "$payload" <<'PY'
import json
import sys

branch = sys.argv[1]
checks = json.loads(sys.argv[2])
payload = {
    "name": f"aegisvolt-{branch}",
    "target": "branch",
    "enforcement": "active",
    "conditions": {"ref_name": {"include": [f"refs/heads/{branch}"], "exclude": []}},
    "rules": [
        {"type": "deletion"},
        {"type": "non_fast_forward"},
        {
            "type": "pull_request",
            "parameters": {
                "required_approving_review_count": 1,
                "dismiss_stale_reviews_on_push": True,
                "require_code_owner_review": False,
                "require_last_push_approval": True,
                "required_review_thread_resolution": True,
            },
        },
        {
            "type": "required_status_checks",
            "parameters": {
                "strict_required_status_checks_policy": True,
                "required_status_checks": [{"context": check} for check in checks],
            },
        },
    ],
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY

  python3 - "$work_dir/current.json" "$payload" "$branch" <<'PY'
import json
import sys

current = json.load(open(sys.argv[1], encoding="utf-8"))
payload = json.load(open(sys.argv[2], encoding="utf-8"))
branch = sys.argv[3]
name = payload["name"]
existing = next((item for item in current if item.get("name") == name), None)
print(f"\n=== {branch} ===")
if existing:
    print(f"Ruleset remoto existente: id={existing.get('id')} enforcement={existing.get('enforcement')}")
    print("No se reemplazará automáticamente.")
else:
    print("No existe ruleset remoto con este nombre.")
print("Payload propuesto:")
print(json.dumps(payload, indent=2, sort_keys=True))
PY

  if [[ "$apply" == true ]]; then
    [[ -n "${GITHUB_TOKEN:-}" ]] || { echo "GITHUB_TOKEN con permiso Administration: write es obligatorio para --apply." >&2; exit 77; }
    exists="$(python3 - "$work_dir/current.json" "aegisvolt-$branch" <<'PY'
import json
import sys
print("true" if any(item.get("name") == sys.argv[2] for item in json.load(open(sys.argv[1], encoding="utf-8"))) else "false")
PY
)"
    [[ "$exists" == false ]] || { echo "Existe aegisvolt-$branch; se rechaza sobrescribirlo automáticamente." >&2; exit 65; }
    curl --fail-with-body --silent --show-error --request POST "${headers[@]}" -H "Content-Type: application/json" --data-binary "@$payload" "$api"
    echo
  fi
done

if [[ "$apply" == false ]]; then
  cat <<'EOF'

Modo de solo lectura: no se modificó GitHub.
Tras revisar los payloads, cree únicamente los rulesets ausentes con:
  GITHUB_TOKEN=... bash scripts/github-rulesets.sh --apply owner/repo
El token debe ser de corta duración y tener Administration: write; no lo guarde en el repositorio.
EOF
fi
