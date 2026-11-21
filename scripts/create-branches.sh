#!/usr/bin/env bash
set -euo pipefail

git remote get-url origin >/dev/null || { echo "Falta remote origin; no se puede comprobar seguridad." >&2; exit 69; }
git show-ref --verify --quiet refs/heads/main || { echo "Falta la rama local main." >&2; exit 69; }

for mapping in 'dev:main' 'test:dev' 'prod:test'; do
  branch="${mapping%%:*}"
  base="${mapping##*:}"
  remote_ref="$(git ls-remote --heads origin "refs/heads/$branch")"
  if [[ -n "$remote_ref" ]]; then
    echo "$branch ya existe en origin; no se crea ni sobrescribe localmente. Revise su historial antes de continuar."
    continue
  fi
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "$branch ya existe localmente; no se modifica."
    continue
  fi
  git show-ref --verify --quiet "refs/heads/$base" || { echo "Falta rama base local $base para crear $branch." >&2; exit 69; }
  git branch "$branch" "$base"
  echo "Creada rama local $branch desde $base. No se publicó en origin."
done

cat <<'EOF'
Revise `git log --oneline main..dev`, `dev..test` y `test..prod` antes de publicar.
No publique dev/test/prod hasta que CD_ENABLED siga ausente o sea distinto de true,
y los rulesets/Environments hayan sido revisados por un administrador.
EOF
