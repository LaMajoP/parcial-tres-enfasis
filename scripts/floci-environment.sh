#!/usr/bin/env bash
set -euo pipefail
usage() { echo "Uso: $0 pr <base_ref>|push <ref_name>" >&2; exit 64; }
[[ $# == 2 ]] || usage
event="$1" branch="$2"
case "$event:$branch" in
  pr:dev|push:dev|pr:test|push:test|pr:prod|push:prod) printf '%s\n' "$branch" ;;
  *) echo "Destino/ambiente Floci no permitido: $event:$branch" >&2; exit 64 ;;
esac
