#!/usr/bin/env bash
# Despliega la aplicación sobre el k3s EKS real de Floci, sin depender de
# localhost dentro de Pods. Verifica la IP fija declarada en compose.floci.yaml,
# inyecta ese endpoint runtime y lo permite sólo por NetworkPolicy al emulador.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cluster_name="${1:-aegisvolt-dev}"
case "$cluster_name" in
  aegisvolt-dev|aegisvolt-test|aegisvolt-prod) ;;
  *) echo "Uso: $0 [aegisvolt-dev|aegisvolt-test|aegisvolt-prod]" >&2; exit 64 ;;
esac
environment="${cluster_name#aegisvolt-}"
namespace="aegisvolt-${environment}"
network="aegisvolt-floci-net"
expected_floci_ip="172.27.0.2"

for command in docker kubectl; do
  command -v "$command" >/dev/null || { echo "Falta $command" >&2; exit 69; }
done

cluster_container="$(docker ps --filter "name=^/floci-aws-eks-${cluster_name}$" --format '{{.Names}}')"
[[ -n "$cluster_container" ]] || { echo "No hay k3s activo para ${cluster_name}. Aplique Terraform primero." >&2; exit 69; }
floci_ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${network}\").IPAddress}}" aegisvolt-floci)"
[[ "$floci_ip" == "$expected_floci_ip" ]] || {
  echo "La IP de Floci debe ser ${expected_floci_ip} según compose.floci.yaml; obtenida: ${floci_ip:-vacía}" >&2
  exit 1
}

# k3s usa containerd y no ve el almacén de imágenes del daemon Docker. La
# importación por stdin no crea archivos temporales ni registra imágenes remotas.
images=(
  aegisvolt/graphql-gateway:0.0.0
  aegisvolt/station-reservation:0.0.0
  aegisvolt/billing-wallet:0.0.0
  aegisvolt/energy-dispatch:0.0.0
  aegisvolt/web:0.0.0
)
for image in "${images[@]}"; do
  docker image inspect "$image" >/dev/null || { echo "Falta imagen local $image; ejecute npm run kind:up o construya la imagen." >&2; exit 69; }
done
docker save "${images[@]}" | docker exec -i "$cluster_container" ctr -n k8s.io images import -

# Argo Rollouts sí se ejecuta; se descarga desde su publicación oficial para
# conservar el CRD/controlador real, no una simulación local.
docker exec "$cluster_container" kubectl create namespace argo-rollouts --dry-run=client -o yaml | docker exec -i "$cluster_container" kubectl apply -f -
if ! docker exec "$cluster_container" kubectl -n argo-rollouts get deployment argo-rollouts >/dev/null 2>&1; then
  curl --silent --show-error --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    https://github.com/argoproj/argo-rollouts/releases/download/v1.8.3/install.yaml \
    | docker exec -i "$cluster_container" kubectl -n argo-rollouts apply -f -
fi
docker exec "$cluster_container" kubectl -n argo-rollouts rollout status deployment/argo-rollouts --timeout=4m

# El overlay Floci parte de dev para reutilizar los parches locales de Kind.
# Para test/prod se cambia únicamente el nombre de Namespace y, abajo, se
# inyectan explícitamente environment/tablas en el ConfigMap runtime. Así no
# se altera ningún overlay AWS ni se duplican manifiestos locales.
if [[ "$environment" == dev ]]; then
  kubectl kustomize "$repo_root/infra/kubernetes/overlays/floci"
else
  kubectl kustomize "$repo_root/infra/kubernetes/overlays/floci" \
    | sed "s/aegisvolt-dev/aegisvolt-${environment}/g"
fi | docker exec -i "$cluster_container" kubectl apply -f -

# EXCEPCIÓN LOCAL (Sonar security hotspot): Floci 2.5.0 expone su API emulada
# sin TLS exclusivamente en la red Docker privada. `floci_ip` se obtiene del
# network aislado, no de entrada de usuario; el endpoint nunca se publica fuera
# de loopback y la NetworkPolicy siguiente permite sólo IP/puerto exactos.
# No sustituir por HTTPS: el emulador no ofrece TLS en 4566.
floci_dynamodb_endpoint="http://${floci_ip}:4566"
docker exec "$cluster_container" kubectl -n "$namespace" patch configmap aegisvolt-runtime --type=merge \
  -p "{\"data\":{\"AEGISVOLT_ENV\":\"${environment}\",\"TABLE_RESERVATIONS\":\"aegisvolt-reservations-${environment}\",\"TABLE_BILLING\":\"aegisvolt-billing-${environment}\",\"TABLE_DISPATCH\":\"aegisvolt-dispatch-${environment}\",\"TABLE_SAGA\":\"aegisvolt-saga-${environment}\",\"TABLE_FLAGS\":\"aegisvolt-flags-${environment}\",\"DYNAMODB_ENDPOINT\":\"${floci_dynamodb_endpoint}\",\"AWS_ACCESS_KEY_ID\":\"floci\",\"AWS_SECRET_ACCESS_KEY\":\"floci\"}}"
for policy in domain-service-ingress-egress gateway-ingress-egress; do
  policy_json="$(docker exec "$cluster_container" kubectl -n "$namespace" get networkpolicy "$policy" -o json)"
  if ! grep -Fq "\"cidr\":\"${floci_ip}/32\"" <<<"$policy_json"; then
    docker exec "$cluster_container" kubectl -n "$namespace" patch networkpolicy "$policy" --type=json \
      -p "[{\"op\":\"add\",\"path\":\"/spec/egress/-\",\"value\":{\"to\":[{\"ipBlock\":{\"cidr\":\"${floci_ip}/32\"}}],\"ports\":[{\"protocol\":\"TCP\",\"port\":4566}]}}]"
  fi
done

docker exec "$cluster_container" kubectl -n "$namespace" rollout restart deployment/station-reservation deployment/billing-wallet deployment/energy-dispatch deployment/web
restart_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
docker exec "$cluster_container" kubectl -n "$namespace" patch rollout graphql-gateway --type=merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"aegisvolt.io/restarted-at\":\"${restart_at}\"}}}}}"

for deployment in station-reservation billing-wallet energy-dispatch web; do
  docker exec "$cluster_container" kubectl -n "$namespace" rollout status "deployment/${deployment}" --timeout=5m
done
docker exec "$cluster_container" kubectl -n "$namespace" wait --for=condition=Healthy rollout/graphql-gateway --timeout=6m
docker exec "$cluster_container" kubectl -n "$namespace" wait --for=condition=Available rollout/graphql-gateway --timeout=6m
docker exec "$cluster_container" kubectl -n "$namespace" get pods,services,rollouts
printf 'AegisVolt desplegado en %s usando DynamoDB Floci en %s\n' "$cluster_name" "$floci_dynamodb_endpoint"
