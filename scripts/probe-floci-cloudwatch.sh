#!/usr/bin/env bash
# Probe funcional CloudWatch Logs contra un grupo existente de Floci.
# Escribe un stream y un único evento marcador; nunca llama AWS.
set -euo pipefail
environment="${1:-}"
case "$environment" in dev|test|prod) ;; *) echo "Uso: $0 dev|test|prod [service]" >&2; exit 64;; esac
service="${2:-graphql-gateway}"
case "$service" in graphql-gateway|station-reservation|billing-wallet|energy-dispatch|web) ;; *) echo "Servicio inválido." >&2; exit 64;; esac

for command in aws jq curl; do command -v "$command" >/dev/null || { echo "Falta $command" >&2; exit 69; }; done
endpoint="http://127.0.0.1:4567"
region="us-east-2"
group="/aegisvolt/$environment/$service"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
stream="api-probe-$stamp-$$"
correlation="probe-$environment-$stamp-$$"
event="$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg env "$environment" --arg svc "$service" --arg corr "$correlation" '{timestamp:$ts,level:"INFO",event:"cloudwatch_api_probe",service:$svc,environment:$env,correlation_id:$corr}')"
aws_local=(env AWS_ACCESS_KEY_ID=floci AWS_SECRET_ACCESS_KEY=floci AWS_DEFAULT_REGION="$region" aws --endpoint-url "$endpoint" logs)

curl --silent --show-error --fail "$endpoint/_localstack/health" >/dev/null
"${aws_local[@]}" describe-log-groups --log-group-name-prefix "$group" --query "logGroups[?logGroupName=='$group'].logGroupName | [0]" --output text | grep -Fx "$group" >/dev/null || {
  echo "El grupo existente no está disponible: $group. No se crea automáticamente." >&2; exit 1;
}
"${aws_local[@]}" create-log-stream --log-group-name "$group" --log-stream-name "$stream" >/dev/null
"${aws_local[@]}" put-log-events --log-group-name "$group" --log-stream-name "$stream" \
  --log-events "[$(jq -cn --arg message "$event" --argjson timestamp "$(date +%s%3N)" '{timestamp:$timestamp,message:$message}')]" >/dev/null

"${aws_local[@]}" describe-log-streams --log-group-name "$group" --log-stream-name-prefix "$stream" \
  | jq -e --arg stream "$stream" '.logStreams[] | select(.logStreamName == $stream)' >/dev/null
got="$("${aws_local[@]}" get-log-events --log-group-name "$group" --log-stream-name "$stream" --start-from-head \
  | jq -r --arg corr "$correlation" '.events[] | .message | fromjson | select(.correlation_id == $corr) | .correlation_id')"
[[ "$got" == "$correlation" ]] || { echo "GetLogEvents no devolvió el evento marcador." >&2; exit 1; }
filtered="$("${aws_local[@]}" filter-log-events --log-group-name "$group" --log-stream-names "$stream" --filter-pattern "$correlation" \
  | jq -r --arg corr "$correlation" '.events[] | .message | fromjson | select(.correlation_id == $corr) | .correlation_id')"
[[ "$filtered" == "$correlation" ]] || { echo "FilterLogEvents no encontró el evento marcador." >&2; exit 1; }
printf 'CloudWatch Logs API OK: DescribeLogStreams, CreateLogStream, PutLogEvents, GetLogEvents, FilterLogEvents\n'
printf 'GROUP=%s\nSTREAM=%s\nCORRELATION_ID=%s\nEVENT=%s\n' "$group" "$stream" "$correlation" "$event"
printf 'El stream/evento marcador permanece en Floci para evidencia; no se elimina.\n'
