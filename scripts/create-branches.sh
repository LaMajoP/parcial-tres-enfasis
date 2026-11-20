#!/usr/bin/env bash
set -euo pipefail
git show-ref --verify --quiet refs/heads/dev || git branch dev
git show-ref --verify --quiet refs/heads/test || git branch test dev
git show-ref --verify --quiet refs/heads/prod || git branch prod test
echo "Ramas locales listas. Publique únicamente tras revisar el remoto: git push -u origin dev test prod"
