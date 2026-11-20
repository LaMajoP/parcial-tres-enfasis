#!/usr/bin/env bash
set -euo pipefail
command -v kind >/dev/null || { echo "Instale Kind para esta verificación local." >&2; exit 69; }
kind create cluster --name aegisvolt --wait 60s
kubectl apply -k infra/kubernetes/overlays/dev
kubectl -n aegisvolt-dev get pods,services
