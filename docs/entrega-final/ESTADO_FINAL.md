# AegisVolt — entrega local con Floci

## Observabilidad: estado comprobado — 2026-11-23

El código de logging SAGA está implementado: JSON incluye timestamp, level,
event, servicio, ambiente y correlation ID; el gateway propaga el mismo ID a
reserva, facturación y dispatch. Se añadieron 3 pruebas unitarias de formato,
saneamiento y propagación, que pasaron junto a las 3 pruebas unitarias de
dominio (6/6).

Prefect ahora expone conteos de SAGAs compensadas, fallidas y huérfanas en el
resumen del flow. Su test actualizado no se pudo ejecutar desde el host porque
no tiene `pytest`; tampoco se verificó un run funcional en la UI de Prefect en
esta revisión.

CloudWatch Logs real/emulado por Floci sigue pendiente de verificación. El
overlay Floci se preparó en el repositorio para programar Fluent Bit en modo
non-root, sin token ni RBAC, con `/var/log` read-only y egress exclusivamente
a `172.27.0.2:4566`. Esa IP se observó en modo lectura en
`aegisvolt-floci-net` (`172.27.0.0/16`, gateway `.1`), con los tres
contenedores k3s conectados; Compose declara ahora la misma IP fija para
futuras creaciones. El despliegue no se ejecutó y no se afirma ingesta.

La configuración filtra logs con `correlation_id` de gateway, reserva,
facturación y dispatch; las métricas sin correlación no se envían. Usa solo
grupos CloudWatch ya existentes y no permite
crearlos automáticamente. El filtro Kubernetes se eliminó, por lo que no se
necesitan permisos del API ni se monta token. Se añadió una variante de
Kustomize de observabilidad que afecta únicamente Fluent Bit y su NetworkPolicy,
más un overlay de rollback. `scripts/verify-floci-logs.sh <env> <correlation_id>`
consulta, sin escribir, la misma SAGA en reserva, billing y dispatch. Aún no se
ejecutó; tampoco se ejecutó `scripts/probe-floci-cloudwatch.sh`, que crea un
stream y un evento persistentes.

La preparación de manifests y logger pasó 8 pruebas estáticas de Fluent Bit,
la validación Kubernetes general, 6 unitarias del logger, build TypeScript,
sintaxis shell, configuración Compose y `git diff --check`; el detalle y los
comandos preparados están en `docs/RESULTADOS_VERIFICACION.md`. Siguen
pendientes la disponibilidad de la imagen `aegisvolt/aws-for-fluent-bit:2.32.4`
en containerd de cada cluster, el despliegue (no autorizado en esta tarea) a
los tres k3s y la consulta real de las APIs de CloudWatch Logs. No se comprobaron en esta tarea
CreateLogStream/PutLogEvents/DescribeLogStreams/GetLogEvents/FilterLogEvents
desde Fluent Bit, ni un run funcional de Prefect.

## Terraform State remoto en Floci — 2026-11-23

La migración real a S3 de Floci fue confirmada por el operador: bucket
`aegisvolt-floci-terraform-state`, versionado habilitado, sin uso de AWS real.
El bootstrap conserva su backend local independiente y los states/backups
originales se preservaron. `terraform init -migrate-state` incrementó el
serial una unidad; los lineages y recursos se conservaron y los planes
posteriores dieron `No changes`:

| Workspace | Lineage | Serial | Recursos | Plan |
|---|---|---:|---:|---|
| dev | `866b3622-720a-51f3-52f9-fbe6ca390181` | 143 | 37 | `No changes` |
| test | `38bd6a3b-1ced-a795-8abf-09732c74281a` | 71 | 36 | `No changes` |
| prod | `457bf529-74b4-9772-080c-c5c694f3f96e` | 68 | 36 | `No changes` |

Esta sección registra evidencia informada desde la terminal del operador; no
se repitió la migración ni se accedió al backend durante esta actualización.
Las limitaciones de CloudWatch real, Fluent Bit/IRSA, ALB/NLB, API Gateway
privado y Canary ALB 20/80 permanecen sin cambios.

## Evidencia funcional reciente — 2026-11-22

Las pruebas funcionales siguientes se ejecutaron en Docker Compose con
DynamoDB Local: `npm run test:graphql-schema` (aprobado),
`npm run test:integration` (6/6), `npm run test:resilience` (1/1) y
`npm run test:e2e` (1/1). El gateway GraphQL, los tres microservicios y el
frontend estuvieron saludables. La prueba Prefect ejecutada dentro de su
contenedor fue `python -m pytest /opt/aegisvolt/prefect/tests/test_flows.py
-q -p no:cacheprovider` con `PYTHONPATH=/opt/aegisvolt/prefect`: 1/1 aprobada,
con seis advertencias no bloqueantes.

Por separado, `./scripts/floci-verify.sh` confirmó respuesta de la API
emulada Floci, 15 tablas DynamoDB y tres clústeres EKS registrados. Estas
pruebas funcionales recientes no se ejecutaron dentro de pods EKS. Conservan
su alcance local y no demuestran servicios AWS reales.

El generador de rulesets en `scripts/github-rulesets.sh` exige los checks de
CI presentes en el workflow y omite `terraform-plan`, porque GitHub omite ese
job cuando `TF_PLAN_ENABLED` está desactivado. Cuando se activa, el workflow
continúa exigiendo la configuración real y ejecuta el plan AWS; no hay
evidencia aquí de un plan ni despliegue AWS.

## Resultado comprobado

El laboratorio se ejecutó únicamente contra Floci `2.5.0` en
`http://127.0.0.1:4567`, región `us-east-2`; no se usaron credenciales ni
recursos de AWS reales.

Floci quedó con `FLOCI_STORAGE_MODE=persistent` y
`FLOCI_STORAGE_PERSISTENT_PATH=/app/data`, volumen nombrado
`aegisvolt-floci-data`, red privada `aegisvolt-floci-net` y el puerto limitado
a `127.0.0.1:4567`. Después de reiniciar el control-plane se volvieron a
consultar correctamente 15 tablas DynamoDB, los tres clústeres EKS y los 33
VPC endpoints. Los k3s hijos continuaron disponibles mediante
`FLOCI_SERVICES_EKS_KEEP_RUNNING_ON_SHUTDOWN=true`.

El volumen histórico
`d0ee3eb390b14ef7fed2d1d0bc414e22d339aefeaf3ecb1fffacdeeefae3c1a4` y el
respaldo `~/aegisvolt-backups/floci-data-backup` se preservaron. Solo contienen
archivos pequeños de Resource Explorer; los directorios
`/tmp/aegisvolt-floci-full` y `/tmp/aegisvolt-floci-terraform` ya no existían,
por lo que no había state ni recursos anteriores recuperables desde ellos. No
se borraron estados, contenedores, volúmenes ni respaldos.

## Terraform y recursos emulados

Las raíces `infra/terraform/local-floci` y
`infra/terraform/local-floci-bootstrap` son exclusivas del laboratorio: usan
endpoint loopback, credenciales ficticias y backend local. No cambian los
providers, backends ni CI/CD de AWS de producción.

| Ámbito | State Terraform | Recursos verificados por API Floci |
| --- | ---: | --- |
| bootstrap compartido | 21 | bucket S3 con versionado/endurecimiento y 8 repositorios ECR |
| dev | 71 | VPC `10.40.0.0/16`, 5 tablas, 11 VPCE, EKS `aegisvolt-dev`, logs/dashboard/alarma |
| test | 70 | VPC `10.41.0.0/16`, 5 tablas, 11 VPCE, EKS `aegisvolt-test`, logs/dashboard/alarma |
| prod | 70 | VPC `10.42.0.0/16`, 5 tablas, 11 VPCE, EKS `aegisvolt-prod`, logs/dashboard/alarma |

Conteos de la API emulada tras el despliegue: 15 tablas, 3 VPC de AegisVolt
más la VPC `default` creada por Floci, 33 VPC endpoints, 22 log groups,
3 dashboards, 3 alarmas, 1 bucket y 8 repositorios ECR. Los planes finales de
`dev`, `test` y `prod` devolvieron `No changes`.

Durante la reconciliación inicial de `dev`, Floci normalizó cuatro ARNs de
políticas IAM y Terraform recreó las cuatro relaciones
`aws_iam_role_policy_attachment` correspondientes. No se ejecutó
`terraform destroy` ni se eliminó state, contenedor, volumen, backup, rol o
política. El guard de los scripts locales quedó después de ese incidente y
rechaza planes que incluyan `delete`.

El módulo API Gateway queda incluido pero deshabilitado en la variante local:
Floci no entregó un NLB interno/AWS Load Balancer Controller verificable para
el VPC Link. ECR se verificó como API/recurso emulado; las imágenes locales se
importan directamente a containerd de k3s, no se afirma un pull real desde un
registry ECR.

## Kubernetes y aplicación

Floci sí creó k3s real para EKS, por lo que no fue necesario sustituirlo por
Kind. Se desplegó AegisVolt completo en `aegisvolt-dev`,
`aegisvolt-test` y `aegisvolt-prod`:

- `station-reservation`, `billing-wallet`, `energy-dispatch` y `web`: 2/2
  réplicas disponibles cada uno, por ambiente.
- `graphql-gateway`: Argo Rollout `Healthy`, 4/4 disponibles, por ambiente.
- Argo Rollouts opera como controlador real en cada k3s.
- Desde los pods gateway se comprobó DNS de servicios y
  `DYNAMODB_ENDPOINT=http://172.27.0.2:4566`; ningún pod usa `localhost` para
  Floci. La NetworkPolicy permite únicamente esa IP/puerto para el emulador.
  Las consultas GraphQL reportaron `environment=test`/`prod` y sus tablas
  `aegisvolt-*-test`/`aegisvolt-*-prod` correctas.

Se ejecutaron los flujos GraphQL dentro de ese clúster:

- reserva/cobro/activación: `COMPLETED` con sesión;
- saldo insuficiente: `COMPENSATED` y `RELEASE_SUCCEEDED`;
- fallo de cargador: `COMPENSATED`, con `REFUND_SUCCEEDED` antes de
  `RELEASE_SUCCEEDED`;
- feature flag de fallo activado/restaurado por la prueba.

`scripts/demo-canary-floci.sh` importó una imagen gateway defectuosa, confirmó
HTTP 500 en el pod canary y restauró automáticamente la imagen original. El
Rollout acabó nuevamente `Healthy` con 4 réplicas. Es una prueba real de
revisión/rollback de Argo, no una afirmación de tráfico ALB ponderado 20/80 ni
de un AnalysisRun con CloudWatch: esas integraciones no son reproducibles con
este perfil de Floci.

## Pruebas ejecutadas

Todas finalizaron correctamente:

```text
npm run lint
npm run build
npm test                         # 3 unitarias
npm run test:graphql-schema
npm run test:integration         # 6 contra Compose/DynamoDB Local reales
npm run test:resilience          # 1 de concurrencia real
npm run test:e2e                 # Playwright: 1 escenario de UI
terraform fmt -check -recursive infra/terraform
terraform validate               # producción y raíces locales
python3 scripts/validate_kubernetes.py
python3 scripts/validate_workflows.py
```

Compose se inició solamente para las pruebas de integración/resiliencia/E2E y
se detiene al final sin ejecutar `down -v`; esas pruebas no sustituyen la
validación adicional hecha en los pods de Floci.

## Reproducibilidad

```bash
# 1. Floci persistente y validación de salud/API local.
./scripts/floci-up.sh
./scripts/floci-verify.sh

# 2. Bootstrap compartido, luego infraestructura por workspace.
./scripts/floci-bootstrap.sh init
./scripts/floci-bootstrap.sh apply
./scripts/floci-terraform.sh init
./scripts/floci-terraform.sh apply dev
./scripts/floci-terraform.sh apply test
./scripts/floci-terraform.sh apply prod

# 3. Construir/importar imágenes y desplegar la aplicación en EKS/k3s Floci.
./scripts/floci-build-images.sh
./scripts/floci-eks-deploy.sh aegisvolt-dev
./scripts/floci-eks-deploy.sh aegisvolt-test
./scripts/floci-eks-deploy.sh aegisvolt-prod
./scripts/demo-canary-floci.sh aegisvolt-dev

# 4. Inspección y apagado no destructivo.
./scripts/floci-verify.sh
./scripts/floci-state-backup.sh
./scripts/floci-down.sh
```

Cada `apply` de los scripts locales primero genera un plan guardado y lo
rechaza si contiene cualquier acción `delete`; además toma un respaldo con
SHA-256 antes de aplicar. Los respaldos quedan ignorados por Git bajo
`artifacts/local-floci-state-backups/`.

## Limitaciones conocidas

- El socket Docker es necesario para EKS de Floci. Está montado `:ro`, pero la
  API Docker no es de solo lectura; úsese únicamente en una estación local de
  confianza. El puerto de Floci queda limitado a loopback y la red Docker es
  aislada.
- El contenedor activo conserva el healthcheck original de la imagen, que usa
  `wget` inexistente y Docker lo marca `unhealthy` aunque
  `/_localstack/health` responda HTTP 200. `compose.floci.yaml` reemplaza ese
  check por uno con Bash/HTTP para cualquier recreación futura; no se recreó el
  contenedor actual para respetar la preservación solicitada.
- CloudWatch, IAM, VPC/VPCE, ECR y EKS se verificaron mediante las APIs
  emuladas. El grupo `/aegisvolt/dev/graphql-gateway` existe, pero tenía cero
  log streams: los clústeres actuales siguen sin Fluent Bit porque el overlay
  preparado en esta tarea no se desplegó. No se declara
  equivalencia operacional con AWS ni se verificó Fluent Bit/IRSA, ALB/NLB,
  API Gateway privado, distribución canary 20/80 o alarmas/AnalysisRun basados
  en telemetría real.
