#!/usr/bin/env bash
# Consulta de solo lectura para demostrar la entrega de una misma SAGA en los
# tres grupos preexistentes de CloudWatch Logs emulado por Floci.
set -euo pipefail

environment="${1:-}"
correlation_id="${2:-}"
[[ "$environment" =~ ^(dev|test|prod)$ ]] || {
  echo "Uso: $0 <dev|test|prod> <correlation_id>" >&2
  exit 64
}
[[ "$correlation_id" =~ ^[A-Za-z0-9._:-]{1,128}$ ]] || {
  echo "correlation_id contiene caracteres no permitidos" >&2
  exit 64
}
command -v aws >/dev/null || { echo "Falta aws CLI" >&2; exit 69; }
command -v jq >/dev/null || { echo "Falta jq" >&2; exit 69; }

export AWS_ACCESS_KEY_ID=floci
export AWS_SECRET_ACCESS_KEY=floci
export AWS_DEFAULT_REGION=us-east-2
groups=(station-reservation billing-wallet energy-dispatch)
for service in "${groups[@]}"; do
  group="/aegisvolt/${environment}/${service}"
  events="$(aws --endpoint-url http://127.0.0.1:4567 logs filter-log-events \
    --log-group-name "$group" --filter-pattern "$correlation_id" --output json)"
  count="$(jq --arg cid "$correlation_id" --arg env "$environment" --arg service "$service" \
    '[.events[]?.message | fromjson? | select(.correlation_id == $cid and .environment == $env and .service_group == $service and .timestamp and .level and .event)] | length' \
    <<<"$events")"
  [[ "$count" -gt 0 ]] || {
    echo "No hay evento con correlation_id=${correlation_id} en ${group}" >&2
    exit 1
  }
  jq -r --arg cid "$correlation_id" --arg group "$group" \
    '.events[]?.message | fromjson? | select(.correlation_id == $cid) | [$group, .timestamp, .level, .service, .event, .correlation_id] | @tsv' \
    <<<"$events"
done
echo "SAGA visible en reserva, facturación y dispatch para ${correlation_id} (${environment})."
