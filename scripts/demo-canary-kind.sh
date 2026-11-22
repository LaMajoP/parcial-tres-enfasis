#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-aegisvolt-dev}"
for command in docker kind kubectl; do
  command -v "$command" >/dev/null || { echo "Falta $command para la demo Canary local." >&2; exit 69; }
done

rollout="graphql-gateway"
original_image="$(kubectl -n "$namespace" get rollout "$rollout" -o jsonpath='{.spec.template.spec.containers[0].image}')"
changed=false

restore() {
  if [[ "$changed" != true ]]; then return; fi
  echo "Restaurando $rollout a $original_image..."
  kubectl -n "$namespace" patch rollout "$rollout" --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"${original_image}\"}]" >/dev/null
  kubectl -n "$namespace" wait --for=condition=Healthy "rollout/$rollout" --timeout=5m >/dev/null
  kubectl -n "$namespace" wait --for=condition=Available "rollout/$rollout" --timeout=5m >/dev/null
}
trap restore EXIT

docker build --quiet --target gateway-defective -t aegisvolt/graphql-gateway-defective:0.0.0 .
kind load docker-image aegisvolt/graphql-gateway-defective:0.0.0 --name aegisvolt
kubectl -n "$namespace" patch rollout "$rollout" --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"aegisvolt/graphql-gateway-defective:0.0.0"}]'
changed=true
kubectl -n "$namespace" wait --for=condition=Healthy "rollout/$rollout" --timeout=5m

current_hash="$(kubectl -n "$namespace" get rollout "$rollout" -o jsonpath='{.status.currentPodHash}')"
canary_pod="$(kubectl -n "$namespace" get pods -l "app=graphql-gateway,rollouts-pod-template-hash=${current_hash}" -o jsonpath='{.items[0].metadata.name}')"
test -n "$canary_pod" || { echo "No se encontró el pod de la revisión Canary." >&2; exit 1; }

kubectl -n "$namespace" exec "$canary_pod" -- node -e '
fetch("http://127.0.0.1:4000/graphql", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ query: "{ environment }" }) })
  .then(async (response) => { const body = await response.text(); console.log(`Canary local: HTTP ${response.status} ${body}`); process.exit(response.status === 500 ? 0 : 1); });
'
echo "Defecto detectado en el pod Canary; se ejecutará rollback manual local."
