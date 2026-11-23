#!/usr/bin/env bash
# Comprueba una SAGA real y sus logs en el ambiente Floci indicado.
set -euo pipefail

environment="${1:-}"
[[ "$environment" =~ ^(dev|test|prod)$ ]] || { echo "Uso: $0 <dev|test|prod>" >&2; exit 64; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cluster="floci-aws-eks-aegisvolt-${environment}"
namespace="aegisvolt-${environment}"

for command in docker python3 aws; do
  command -v "$command" >/dev/null || { echo "Falta $command" >&2; exit 69; }
done

docker exec "$cluster" kubectl -n "$namespace" wait --for=condition=Available \
  rollout/graphql-gateway --timeout=3m
docker exec "$cluster" kubectl -n "$namespace" rollout status \
  daemonset/aws-for-fluent-bit --timeout=3m
gateway_pod="$(docker exec "$cluster" kubectl -n "$namespace" get pods \
  -l app=graphql-gateway -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$gateway_pod" ]] || { echo "Sin pod GraphQL en $namespace" >&2; exit 1; }

result="$(docker exec "$cluster" kubectl -n "$namespace" exec "pod/$gateway_pod" -- env \
  GRAPHQL_URL=http://127.0.0.1:4000/graphql \
  BILLING_SERVICE_URL=http://billing-wallet:3002 \
  node scripts/demo.mjs success)"
correlation_id="$(python3 -c '
import json, sys
text = sys.stdin.read()
payload, _ = json.JSONDecoder().raw_decode(text)
result = payload["reserveAndStartCharging"]
assert result["saga"]["state"] == "COMPLETED"
assert result["error"] is None
print(result["correlationId"])
' <<<"$result")"

for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if bash "$repo_root/scripts/verify-floci-logs.sh" "$environment" "$correlation_id"; then
    echo "Floci ${environment}: SAGA, cierre de sesión y logs aprobados."
    exit 0
  fi
  sleep 2
done
echo "Floci ${environment}: la SAGA completó, pero faltan logs correlacionados." >&2
exit 1
