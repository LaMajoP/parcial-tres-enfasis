# CloudWatch Logs Insights — consultas reproducibles

Seleccionar los grupos `/aegisvolt/<ambiente>/*`.

```sql
fields @timestamp, service, correlation_id, saga_id, operation, status, error_code, duration_ms
| filter ispresent(correlation_id)
| sort @timestamp asc
| limit 200
```

```sql
fields @timestamp, saga_id, operation, status, error_code
| filter operation like /compensat/ or status = "FAILED"
| sort @timestamp asc
```

No incluir tokens, cabeceras de autorización ni saldos: el logger los sanea antes de emitir JSON.
