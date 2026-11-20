#!/usr/bin/env bash
set -euo pipefail
repository="${1:-${GITHUB_REPOSITORY:-}}"
[[ -n "$repository" ]] || { echo "Uso: scripts/github-rulesets.sh owner/repo" >&2; exit 64; }
command -v gh >/dev/null || { echo "Instale GitHub CLI y ejecute gh auth login." >&2; exit 69; }
command -v jq >/dev/null || { echo "jq es obligatorio." >&2; exit 69; }
for branch in dev test prod; do
  payload="$(jq -n --arg branch "$branch" '{name:("aegisvolt-"+$branch),target:"branch",enforcement:"active",conditions:{ref_name:{include:[$branch],exclude:[]}},rules:[{type:"deletion"},{type:"non_fast_forward"},{type:"pull_request",parameters:{required_approving_review_count:1,require_code_owner_review:false,require_last_push_approval:true,required_review_thread_resolution:true}},{type:"required_status_checks",parameters:{strict_required_status_checks_policy:true,required_status_checks:[{context:"lint-build"},{context:"unit-tests"},{context:"integration-tests"},{context:"e2e-tests"},{context:"terraform-plan"}]}}]}')"
  gh api --method POST "repos/$repository/rulesets" --input - <<<"$payload"
done
echo "Rulesets solicitados. Confirme en Settings > Rules > Rulesets y pruebe el rechazo remoto antes de declararlos activos."
