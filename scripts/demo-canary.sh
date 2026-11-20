#!/usr/bin/env bash
set -euo pipefail
namespace="${1:-aegisvolt-test}"
command -v kubectl >/dev/null || { echo "NO VERIFICADO: kubectl no está instalado." >&2; exit 69; }
if [[ -n "${CANARY_DEFECTIVE_IMAGE:-}" ]]; then
  [[ "$CANARY_DEFECTIVE_IMAGE" =~ @sha256:[0-9a-f]{64}$ ]] || { echo "CANARY_DEFECTIVE_IMAGE debe ser un digest @sha256." >&2; exit 64; }
  kubectl -n "$namespace" argo rollouts set image rollout/graphql-gateway "app=$CANARY_DEFECTIVE_IMAGE"
fi
kubectl -n "$namespace" get rollout/graphql-gateway
kubectl -n "$namespace" argo rollouts get rollout graphql-gateway --watch
echo "Use CANARY_DEFECTIVE_IMAGE=<ECR@sha256> npm run demo:canary para iniciar la demo defectuosa. Observe AnalysisRun y ejecute: kubectl -n $namespace argo rollouts abort graphql-gateway"
