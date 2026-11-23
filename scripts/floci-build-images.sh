#!/usr/bin/env bash
# Construye las imágenes que consume el k3s de Floci sin crear un clúster Kind
# ni publicar en un registry. floci-eks-deploy.sh las importa a containerd.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for component in graphql-gateway station-reservation billing-wallet energy-dispatch; do
  docker build --target runtime -t "aegisvolt/${component}:0.0.0" .
done
docker build --target web-runtime -t aegisvolt/web:0.0.0 .
