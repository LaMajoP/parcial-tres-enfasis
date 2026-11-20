#!/usr/bin/env bash
# Se ejecuta una vez desde una red con acceso al registro npm. No instala ni
# arranca la plataforma: deja el lockfile para revisión y posterior npm ci.
set -euo pipefail
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
test -f package-lock.json
echo "package-lock.json generado. Revise el diff y ejecute npm ci antes de versionarlo."
