# CloudWatch Logs Insights — consultas reproducibles

Seleccionar los grupos `/aegisvolt/<ambiente>/*`.

```sql
fields @timestamp, timestamp, level, event, environment, service, correlation_id, saga_id, operation, status, error_code, duration_ms
| filter ispresent(correlation_id)
| sort @timestamp asc
| limit 200
```

```sql
fields @timestamp, environment, service, correlation_id, saga_id, event, operation, status, error_code
| filter event like /refund|release|compensat/ or status = "FAILED"
| sort @timestamp asc
```

No incluir tokens, cabeceras de autorización ni saldos: el logger los sanea antes de emitir JSON.

Para seguir un flujo SAGA concreto, sustituir el marcador por el
`correlation_id` mostrado por `npm run demo:fail-charger`:

```sql
fields @timestamp, environment, service, level, event, operation, correlation_id, saga_id, status, error_code
| filter correlation_id = "<correlation-id-de-la-demo>"
| sort @timestamp asc
| limit 100
```

Usar en la consola Logs Insights solo después de comprobar que Fluent Bit
entregó los eventos al grupo emulado; la consulta guardada no es evidencia de
ingesta por sí misma.
