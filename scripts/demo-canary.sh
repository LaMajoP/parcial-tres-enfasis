#!/usr/bin/env bash
set -euo pipefail
namespace="${1:-aegisvolt-test}"
command -v kubectl >/dev/null || { echo "NO VERIFICADO: kubectl no está instalado." >&2; exit 69; }
kubectl -n "$namespace" get rollout/graphql-gateway-canary
kubectl -n "$namespace" argo rollouts get rollout graphql-gateway-canary --watch
echo "Para la demostración defectuosa aplique el patch con un digest previamente construido que falle readiness; observe AnalysisRun y ejecute: kubectl -n $namespace argo rollouts abort graphql-gateway-canary"
