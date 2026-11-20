# Preguntas de defensa

Las preguntas se responden contra la rúbrica transcrita; el PDF adjunto no pudo extraerse en el sandbox y no se inventa una cita literal de su apartado 6.

## ¿Cómo se aíslan Terraform y los ambientes?

`workspace_key_prefix="env"` y workspaces `dev/test/prod` separan state como `env:/<env>/aegisvolt.tfstate`; `terraform.workspace` se usa para CIDR, recursos y tablas, no dentro del backend. `infra/terraform/environments/versions.tf` y `main.tf` lo prueban. Error frecuente: interpolar workspace en bloque backend o usar namespace como si fuera VPC.

## ¿Cómo recupera una versión de state S3?

Se lista versión con `aws s3api list-object-versions`, se descarga a `/tmp` para inspección y se revisa un plan antes de cualquier recuperación aprobada. Versionamiento y bloqueo se definen en `bootstrap-state`. Error: editar tfstate JSON o destruir el bucket primero.

## ¿Cuál es el recorrido de red?

Cliente con conectividad privada → Interface Endpoint `execute-api` → REST API privada validada con `aws:SourceVpce` → VPC Link → NLB interno → Service → pod Gateway. `docs/diagrams/despliegue-red.md` y módulo API. Error: afirmar que el Interface Endpoint conecta API Gateway con pods.

## ¿Qué reglas Git impiden saltar promoción?

`feature/*` nace de `dev`; PR dev, luego PR dev→test y test→prod. `github-rulesets.sh` solicita PR, no force-push y checks obligatorios. `deploy.yml` deriva ambiente de `github.ref_name`; CI deriva plan de `github.base_ref`. Error: usar un valor de ambiente fijo en YAML.

## ¿Cómo evita que test aplique prod?

Cada Environment de GitHub inyecta solo su `AWS_ROLE_ARN` y bucket; CD selecciona `github.ref_name`, tiene concurrency por workspace y Terraform valida workspace. Demostrable en `deploy.yml`. Error: reutilizar rol o state bucket/prefijo de prod para test.

## ¿Qué mide el canary y qué pasa sin muestras?

`AnalysisTemplate` consulta CloudWatch: error rate <2 %, p95 <1000 ms y expresión que falla si hay ≤20 peticiones. No hay métricas = no éxito. Argo mantiene 20/80 hasta AnalysisRun y promueve o aborta. Error: llamar canary a un rolling update o al 20 % de réplicas.

## ¿Qué ocurre si falla el hardware en el paso 3?

El Gateway persiste `COMPENSATING`, ejecuta `REFUND` idempotente y solo después `RELEASE`; termina `COMPENSATED` o `COMPENSATION_FAILED` reconciliable. Ver `SAGA_ESTADOS_Y_FALLOS.md`, `executeSaga` y test de integración. Error: liberar primero o cobrar dos veces al reintentar.

## ¿Cómo previene doble compensación y doble cobro?

Movimientos usan clave durable `idempotencyKey:debit/refund`, Dispatch `ACTIVATION#idempotencyKey` y Reservation condiciona por `sagaId`. SAGA guarda `compensationCompleted`. Error: depender de memoria del proceso o de un retry sin idempotencia.

## ¿Cómo trabajan Prefect y CloudWatch juntos?

CloudWatch centraliza stdout JSON y alarmas/métricas; Prefect agenda health y scan read-only de tabla SAGA, reportando huérfanas o compensaciones fallidas. Ver `observability/prefect/flows.py` y `logs-insights.queries.md`. Error: reportar métricas hardcodeadas como auditoría.

## ¿Por qué un flag dev no modifica prod?

Cada ambiente tiene `aegisvolt-flags-<env>` y Terraform crea tablas distintas. El Gateway cachea cinco segundos e invalida al escribir; prod exige `platform-admin`. Error: misma tabla con columna environment sin policy/partición efectiva.

## ¿Qué trade-off tiene la orquestación?

Hace visible orden, estado y compensación, a costa de un coordinador crítico. La persistencia antes/después, reconciliación y circuit breaker reducen el riesgo. Se documenta en ADR-0001. Error: afirmar transacción ACID distribuida.

## ¿Qué no fue comprobado aún?

La evidencia local/AWS/GitHub depende de red npm, socket Docker y cuentas no disponibles en este sandbox; el estado honesto está en `RESULTADOS_VERIFICACION.md`. Error: presentar manifiestos como despliegue ocurrido.
