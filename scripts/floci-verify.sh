#!/usr/bin/env bash
# Verificaciones no destructivas contra el endpoint estrictamente local.
set -euo pipefail

endpoint="http://127.0.0.1:4567"
minimal="${1:-}"
for command in curl aws docker; do
  command -v "$command" >/dev/null || { echo "Falta $command" >&2; exit 69; }
done

health="$(curl --silent --show-error --fail "$endpoint/_localstack/health")"
printf 'Floci health: %s\n' "$health"

storage="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' aegisvolt-floci | sed -n 's/^FLOCI_STORAGE_MODE=//p' | head -n1)"
[[ "$storage" == "persistent" ]] || { echo "Floci no está configurado con FLOCI_STORAGE_MODE=persistent (valor: ${storage:-ausente})." >&2; exit 1; }

aws_local=(env AWS_ACCESS_KEY_ID=floci AWS_SECRET_ACCESS_KEY=floci AWS_DEFAULT_REGION=us-east-2 aws --endpoint-url "$endpoint")
"${aws_local[@]}" sts get-caller-identity --output json
"${aws_local[@]}" dynamodb list-tables --output json
"${aws_local[@]}" s3api list-buckets --output json

if [[ "$minimal" != "--minimal" ]]; then
  "${aws_local[@]}" ec2 describe-vpcs --output json
  "${aws_local[@]}" logs describe-log-groups --output json
  "${aws_local[@]}" eks list-clusters --output json
fi
