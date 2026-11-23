#!/usr/bin/env bash
# Detiene el control-plane sin borrar ni el contenedor, ni el volumen, ni los
# k3s hijos persistentes que Floci pueda haber creado.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker compose -f "$repo_root/compose.floci.yaml" stop floci
