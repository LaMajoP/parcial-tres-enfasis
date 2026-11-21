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
