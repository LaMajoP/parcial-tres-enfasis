# Arquitectura

## Límites y propiedad de datos

| Bounded context | Servicio | Tabla propietaria | Responsabilidad |
|---|---|---|---|
| StationReservation | `station-reservation-service` | `aegisvolt-reservations-<env>` | Conectores, bloqueo, caducidad y liberación. |
| BillingWallet | `billing-wallet-service` | `aegisvolt-billing-<env>` | Saldo, débito y reembolso enteros e idempotentes. |
| EnergyDispatch | `energy-dispatch-service` | `aegisvolt-dispatch-<env>` | Activación simulada, sesión y telemetría. |
| SagaCoordination | `graphql-gateway` | `aegisvolt-saga-<env>`, `aegisvolt-flags-<env>` | Orquestación durable, lectura GraphQL y flags. |

El gateway solo integra por HTTP interno; no contiene credenciales ni accede a tablas de los tres contextos de dominio.

## Datos y consistencia

Cada tabla usa PK/SK. La tabla SAGA tiene `GSI1` por `IDEMPOTENCY#<key>` para que una solicitud duplicada recupere la misma transacción. Billetera ejecuta débito/movimiento en una transacción DynamoDB; reserva actualiza con `ConditionExpression`; dispatch mantiene un registro de activación por `idempotencyKey`.

DynamoDB TTL (`expiresAt`) elimina registros eventualmente y **no** libera de inmediato un conector. `POST /reconcile-expired` realiza la recuperación condicional, sin tocar una reserva que otra SAGA haya adquirido después.

## Red AWS

La topología prevista es privada: navegador autorizado → VPN/Client VPN o túnel/host corporativo → Interface VPCE `execute-api` → API Gateway REST privada (resource policy `aws:SourceVpce`) → VPC Link → NLB interno creado por el Service GraphQL → pods privados de EKS. Un Interface Endpoint `execute-api` solo permite al cliente dentro de VPC llegar a una API privada; no sustituye el VPC Link. El VPC Link es la conexión de API Gateway hacia el NLB/backend privado.

Para un navegador público opcional, la alternativa es un entrypoint autenticado independiente, con WAF/OIDC, que enruta al backend privado mediante VPC Link. No se promete que una API privada sea navegable desde Internet. Los pods no tienen IP pública.

Sin NAT, los Gateway Endpoints S3/DynamoDB y los Interface Endpoints Logs, `execute-api`, ECR API/DKR y STS cubren tráfico necesario de workloads. La comprobación AWS real está documentada en `ACCIONES_MANUALES.md`.

## Observabilidad

Cada llamada crítica emite JSON con `timestamp`, `level`, `service`, `environment`, `correlation_id`, `saga_id`, `operation`, `status`, `duration_ms` y `error_code` cuando existe. El sanitizador elimina campos con `token`, `secret`, `authorization`, `password` o `balance`. El correlativo se propaga al HTTP interno. Prefect consulta `/health/ready` y escanea solo la tabla SAGA autorizada.

## Actualización de UI

No se declara WebSocket: la UI consulta GraphQL cada tres segundos. Es casi tiempo real con el límite explícito de una ventana de hasta tres segundos, elegido para mantener el entorno privado simple y verificable.
