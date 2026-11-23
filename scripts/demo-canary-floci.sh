#!/usr/bin/env bash
# Prueba reversible de un canary en el k3s que Floci crea para EKS. Comprueba
# que Argo Rollouts cambia de revisión, detecta un gateway que responde 500 y
# siempre restituye la imagen inicial antes de salir.
#
# Floci no provee AWS Load Balancer Controller ni métricas CloudWatch reales;
# por eso el overlay local no pretende medir distribución 20/80 ni AnalysisRun.
set -euo pipefail

namespace="${1:-aegisvolt-dev}"
cluster_container="${FLOCI_EKS_CONTAINER:-floci-aws-eks-aegisvolt-dev}"
rollout="graphql-gateway"

for command in docker; do
  command -v "$command" >/dev/null || { echo "Falta $command." >&2; exit 69; }
done
docker inspect "$cluster_container" >/dev/null 2>&1 || {
  echo "No existe el k3s local $cluster_container." >&2
  exit 69
}

k() { docker exec "$cluster_container" kubectl "$@"; }

original_image="$(k -n "$namespace" get rollout "$rollout" -o jsonpath='{.spec.template.spec.containers[0].image}')"
changed=false
restore() {
  if [[ "$changed" != true ]]; then return; fi
  echo "Restaurando $rollout a $original_image..."
  k -n "$namespace" patch rollout "$rollout" --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"${original_image}\"}]" >/dev/null
  k -n "$namespace" wait --for=condition=Healthy "rollout/$rollout" --timeout=5m >/dev/null
  k -n "$namespace" wait --for=condition=Available "rollout/$rollout" --timeout=5m >/dev/null
}
trap restore EXIT

if ! docker image inspect aegisvolt/graphql-gateway-defective:0.0.0 >/dev/null 2>&1; then
  docker build --quiet --target gateway-defective -t aegisvolt/graphql-gateway-defective:0.0.0 .
fi
docker save aegisvolt/graphql-gateway-defective:0.0.0 | docker exec -i "$cluster_container" ctr -n k8s.io images import -

k -n "$namespace" patch rollout "$rollout" --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"aegisvolt/graphql-gateway-defective:0.0.0"}]'
changed=true
# En el perfil local Argo puede permanecer Progressing mientras aplica el
# setWeight sin un controlador ALB. Basta con comprobar un Pod Ready de la
# revisión canary; esperar Healthy aquí ocultaría precisamente la regresión.
canary_pod=""
for attempt in $(seq 1 60); do
  canary_pod="$(k -n "$namespace" get pods -l app=graphql-gateway \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{" "}{.status.phase}{"\n"}{end}' \
    | awk '$2 == "aegisvolt/graphql-gateway-defective:0.0.0" && $3 == "Running" { print $1; exit }')"
  [[ -n "$canary_pod" ]] && break
  sleep 2
done
[[ -n "$canary_pod" ]] || { echo "No se encontró un Pod Running de la revisión Canary." >&2; exit 1; }

k -n "$namespace" exec "$canary_pod" -- node -e '
  fetch("http://127.0.0.1:4000/graphql", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query: "{ environment }" })
  }).then(async (response) => {
    console.log(`Canary Floci: HTTP ${response.status} ${await response.text()}`);
    process.exit(response.status === 500 ? 0 : 1);
  });
'
echo "Defecto detectado; el trap restaura y verifica la revisión estable."
