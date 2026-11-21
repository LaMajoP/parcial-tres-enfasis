# Resultados de verificación reales

Fecha de auditoría/corrección: 2026-11-20 (America/Bogota). Baseline: `e7bb393` en `main`.

## Corrección de `CONNECTOR_NOT_FOUND`

La tabla `aegisvolt-reservations-dev` conservaba solo `connector-01`, `connector-03` y `connector-04`; faltaba `CONNECTOR#connector-02`. Las SAGAs persistidas con el error usaban efectivamente `connector-02`, aunque la descripción inicial mencionaba `connector-01`. Una SAGA previa de `connector-02` había llegado a `COMPLETED`, lo cual confirma que la fila existió antes.

La causa estructural fue doble:

- `expiresAt` es la TTL de DynamoDB para una reserva pendiente. La transición a `CHARGING` no la eliminaba, de modo que DynamoDB Local podía borrar por TTL el ítem completo de un conector ya activado.
- `kind:down` elimina solo el clúster; el volumen `aegisvolt_dynamodb-data` permanece. `kind:up` creaba tablas, pero no reejecutaba de forma explícita una semilla que completara entidades faltantes. Por ello el estado incompleto sobrevivía al siguiente clúster.

La semilla es ahora condicional e idempotente, se ejecuta explícitamente en cada arranque de Kind y no sobrescribe conectores ocupados ni saldos. La activación elimina `expiresAt`; los reintentos idempotentes también lo reparan si el ítem antiguo aún existe.

| Comando / acción | Resultado real | Estado |
|---|---|---|
| `npm run lint` | ESLint sin warnings. | OK |
| `npm run build` | TypeScript y build Vite correctos en todos los workspaces. | OK |
| `npm run test:graphql-schema` | `Schema GraphQL del gateway válido y con los contratos obligatorios.` | OK |
| `npm test` | 3 pruebas unitarias aprobadas. | OK |
| `npm run test:integration` | 6/6 aprobadas contra Compose y DynamoDB Local: éxito, saldo insuficiente, conector anunciado `AVAILABLE`, duplicado idempotente, falla física/reembolso y timeout. | OK |
| `npm run test:resilience` | 1/1 aprobada: dos flotas no adquieren el mismo conector. | OK |
| `npm run validate:kubernetes` | 37 documentos válidos; Rollout sin placeholders desplegables. | OK |
| `python3 scripts/validate_workflows.py` | Workflows YAML y reglas estáticas válidas. | OK |
| `docker compose up --build -d` | Servicios de dominio y gateway sanos; healthcheck web corregido a IPv4. | OK |
| `npm run kind:down` | Eliminó el clúster `aegisvolt`; no eliminó el volumen DynamoDB. | OK |
| `npm run kind:up` + comprobación posterior con `kubectl` | 12 pods `Running/Ready`; 4 réplicas del Rollout disponibles; condiciones `Healthy` y `Available` satisfechas. El plugin `kubectl argo` no está instalado y ya no es una dependencia del script. | OK |
| DynamoDB Local tras el arranque Kind | Cuatro ítems de conector con claves `CONNECTOR#connector-01` a `CONNECTOR#connector-04`; billetera `fleet-demo` presente. | OK |
| Mutación real por `kubectl port-forward svc/web …` | `station-bogota-01` + `connector-01`: reserva, débito, activación y SAGA `COMPLETED`; movimiento y sesión persistidos con la misma SAGA/correlación. | OK |
| Consulta tras activar | Conector `CHARGING` y `reservationExpiresAt: null`; tras `closeCharging`, `AVAILABLE`. | OK |
| Rechazos reales en Kind | Inexistente, fuera de servicio y par estación/conector inválido: `COMPENSATED`, `SAGA_TERMINATED`, sin reconciliación. Una reserva válida posterior completó, confirmando que esos 4xx no abren el circuit breaker. | OK |

## Limitaciones no verificadas en esta ejecución

- No se ejecutó `npm run test:e2e` con Playwright.
- No se inyectó una pérdida de conectividad de DynamoDB: no hay un mecanismo de fallo seguro implementado para hacerlo sin interrumpir servicios reales. Los errores técnicos reintentables permanecen en `PENDING` para reconciliación.
- No se ejecutaron Terraform, AWS, GitHub Actions, CloudWatch ni Prefect contra cuentas externas; no se hizo `terraform apply`.
