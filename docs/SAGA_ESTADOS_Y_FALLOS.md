# Estados y fallos de la SAGA

| Paso durable | Estado antes/después | Efecto HTTP | Idempotencia | Falla y compensación | Evidencia |
|---|---|---|---|---|---|
| Crear | `PENDING` | Persistir `SAGA_CREATED` y GSI de llave | `idempotencyKey` recupera la misma SAGA | Se puede reanudar desde `PENDING` | `createSaga` en gateway |
| Reservar | `PENDING → RESERVED` | Reserva condicional `AVAILABLE → RESERVED` y validación del par estación/conector | mismo `sagaId` devuelve reserva existente | Rechazo definitivo antes de efectos (`CONNECTOR_NOT_FOUND`, fuera de servicio o estación inválida): `PENDING → COMPENSATED` con `SAGA_TERMINATED`; error técnico reintentable queda `PENDING` para reconciliación | integración éxito/concurrencia/rechazos |
| Cobrar | `RESERVED → CHARGED` | `TransactWriteItems`: saldo + movimiento | movimiento `idempotencyKey:debit` | `INSUFFICIENT_FUNDS`: `RELEASE` | integración saldo insuficiente |
| Activar | `CHARGED → ACTIVATING → COMPLETED` | Activación de cargador y enlazar `CHARGING` | registro `ACTIVATION#idempotencyKey` | falla hardware/timeout: `REFUND` **antes** de `RELEASE` | integración fallo hardware |
| Compensar | `COMPENSATING → COMPENSATED` | Cada acción se persiste antes y después | `:refund` y `:release` son idempotentes | fallo queda `COMPENSATION_FAILED` y reconciliable | `reconcileSagas` + Prefect |

Transiciones permitidas están en `packages/contracts/src/index.ts` y se validan antes de cada `record`. La orquestación persistida se eligió sobre Outbox: este flujo usa comandos HTTP síncronos con estado durable y reconciliación; no se afirma que exista relay Outbox.

Reintentos están limitados a tres, timeout de 2 s, backoff exponencial con jitter y solo se ejecutan con comandos idempotentes. Cada dependencia tiene bulkhead de ocho operaciones y circuit breaker que abre tras tres fallos técnicos/reintentables por cinco segundos; rechazos de dominio 4xx no cuentan para abrirlo.
