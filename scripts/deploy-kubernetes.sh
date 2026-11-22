#!/usr/bin/env bash
# Renderiza una copia temporal del overlay con digests inmutables y espera el
# Rollout real. Nunca altera los YAML versionados ni acepta tags mutables.
set -euo pipefail

environment="${1:?Uso: scripts/deploy-kubernetes.sh <dev|test|prod>}"
case "$environment" in dev|test|prod) ;; *) echo "Ambiente inválido" >&2; exit 64 ;; esac
for command in kubectl kustomize kustomize jq; do command -v "$command" >/dev/null || { echo "Falta $command" >&2; exit 69; }; done

images_json="${PROMOTED_IMAGES_JSON:?PROMOTED_IMAGES_JSON es obligatorio}"
required='["graphql-gateway","station-reservation","billing-wallet","energy-dispatch","web"]'
jq -e --argjson required "$required" '
  . as $images | type == "object" and
  all($required[]; . as $name | ($images | has($name)) and ($images[$name] | type == "string" and test("@sha256:[0-9a-f]{64}$")))
' <<<"$images_json" >/dev/null || {
  echo "PROMOTED_IMAGES_JSON debe contener los cinco componentes como referencias @sha256 inmutables." >&2
  exit 64
}

# Fluent Bit no forma parte del artefacto de aplicación que se promociona entre
# ambientes. Su digest viene de un espejo privado, generado una vez por
# `mirror-platform-images.sh`, para que el clúster sin NAT nunca descargue una
# imagen pública durante el despliegue.
platform_images_json="${PLATFORM_IMAGES_JSON:?PLATFORM_IMAGES_JSON es obligatorio}"
jq -e '
  type == "object" and
  (.["aws-for-fluent-bit"] | type == "string" and test("@sha256:[0-9a-f]{64}$"))
' <<<"$platform_images_json" >/dev/null || {
  echo "PLATFORM_IMAGES_JSON debe incluir aws-for-fluent-bit como referencia @sha256 inmutable." >&2
  exit 64
}

render_root="$(mktemp -d)"
cleanup() { rm -rf "$render_root"; }
trap cleanup EXIT
cp -R infra/kubernetes "$render_root/kubernetes"
overlay="$render_root/kubernetes/overlays/$environment"

# kustomize edit trabaja solo sobre la copia temporal; así el manifiesto aplicado
# lleva cada digest aprobado desde el primer objeto enviado a Kubernetes.
while IFS=$'\t' read -r component image; do
  (cd "$overlay" && kustomize edit set image "aegisvolt/$component=$image")
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$images_json")

fluent_bit_image="$(jq -r '.["aws-for-fluent-bit"]' <<<"$platform_images_json")"
(cd "$overlay" && kustomize edit set image "aegisvolt/aws-for-fluent-bit=$fluent_bit_image")

kubectl apply -k "$overlay"
namespace="aegisvolt-$environment"
kubectl -n "$namespace" rollout status deployment/station-reservation --timeout=5m
kubectl -n "$namespace" rollout status deployment/billing-wallet --timeout=5m
kubectl -n "$namespace" rollout status deployment/energy-dispatch --timeout=5m
kubectl -n "$namespace" rollout status deployment/web --timeout=5m

# Es un Argo Rollout, no un Deployment. El CRD publica condiciones que
# `kubectl` estándar puede esperar; el runner no depende del plugin cliente.
kubectl -n "$namespace" wait --for=condition=Healthy rollout/graphql-gateway --timeout=12m
kubectl -n "$namespace" wait --for=condition=Available rollout/graphql-gateway --timeout=12m
