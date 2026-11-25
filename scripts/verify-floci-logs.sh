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
command -v python3 >/dev/null || { echo "Falta python3" >&2; exit 69; }

export AWS_ACCESS_KEY_ID=floci
export AWS_SECRET_ACCESS_KEY=floci
export AWS_DEFAULT_REGION=us-east-2
groups=(station-reservation billing-wallet energy-dispatch)
for service in "${groups[@]}"; do
  group="/aegisvolt/${environment}/${service}"
  # Floci 2.5.0 returns no events for a UUID filter-pattern even when the
  # event exists. Read the group and match the JSON field locally instead.
  events="$(aws --endpoint-url http://127.0.0.1:4567 logs filter-log-events \
    --log-group-name "$group" --output json)"
  matches="$(python3 -c '
import json, sys
payload = json.load(sys.stdin)
cid, environment, service, group = sys.argv[1:]
for item in payload.get("events", []):
    try:
        event = json.loads(item["message"])
    except (KeyError, TypeError, ValueError):
        continue
    if (event.get("correlation_id") == cid and event.get("environment") == environment
            and event.get("service_group") == service
            and all(event.get(key) for key in ("timestamp", "level", "event"))):
        print("\t".join(str(value) for value in
              (group, event["timestamp"], event["level"], event.get("service", ""), event["event"], cid)))
' "$correlation_id" "$environment" "$service" "$group" <<<"$events")"
  [[ -n "$matches" ]] || {
    echo "No hay evento con correlation_id=${correlation_id} en ${group}" >&2
    exit 1
  }
  printf '%s\n' "$matches"
done
echo "SAGA visible en reserva, facturación y dispatch para ${correlation_id} (${environment})."
