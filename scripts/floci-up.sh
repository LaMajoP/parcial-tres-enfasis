#!/usr/bin/env bash
# Inicia únicamente el emulador local. Nunca usa AWS ni elimina, detiene o
# renombra contenedores/volúmenes ajenos.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose=(docker compose -f "$repo_root/compose.floci.yaml")

if docker inspect aegisvolt-floci >/dev/null 2>&1; then
  mode="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' aegisvolt-floci | sed -n 's/^FLOCI_STORAGE_MODE=//p' | head -n1)"
  if [[ "$mode" != "persistent" ]]; then
    cat >&2 <<'EOF'
Existe aegisvolt-floci sin FLOCI_STORAGE_MODE=persistent. Para preservar sus
datos este script no lo modifica. Respáldelo y renómbrelo manualmente antes de
crear el contenedor persistente con compose.floci.yaml.
EOF
    exit 78
  fi
fi

"${compose[@]}" up -d --no-recreate
for attempt in $(seq 1 30); do
  if curl --silent --show-error --fail http://127.0.0.1:4567/_localstack/health >/dev/null; then
    "$repo_root/scripts/floci-verify.sh" --minimal
    exit 0
  fi
  sleep 1
done

echo "Floci no alcanzó estado listo en 30 segundos." >&2
"${compose[@]}" logs --tail 120 floci >&2
exit 1
