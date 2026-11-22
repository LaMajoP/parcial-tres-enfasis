# Resultados de verificación reales

> La sección del 2026-11-22 es el estado vigente y prevalece sobre notas históricas de este archivo cuando haya contradicción. No equivale a un despliegue AWS.

## Ejecución local y revisión de preparación — 2026-11-22

### Alcance y restricciones respetadas

- No se ejecutó `terraform apply`, `destroy`, `import`, una migración de state, publicación ECR, push/merge, cambio IAM/SCP ni configuración de facturación.
- La cuenta AWS `289663675871` en `us-east-2` mantiene las restricciones SCP descritas por la propietaria; por decisión expresa no se crean recursos ni se asumen costos. La infraestructura AWS permanece **definida en código, no desplegada**.
- `TF_PLAN_ENABLED` y `CD_ENABLED` permanecen desactivados. No se activó ningún despliegue automático.

### Correcciones realizadas

- `bootstrap-state` ya no declara un backend S3 antes de que exista el bucket: inicia con state local. `backend.s3.tf.example` se copia localmente y se migra solo después de un apply autorizado; el archivo generado está ignorado.
- Toda la configuración de aplicación, ejemplos Terraform y defaults locales quedó alineada a `us-east-2` (DynamoDB Local sigue siendo local).
- CloudWatch declara los grupos que Fluent Bit deriva realmente de labels: incluye `web` y `aws-for-fluent-bit`, no el grupo incongruente `fluent-bit`.
- ECR declara ocho repositorios: cinco de aplicación y tres de plataforma. `scripts/mirror-platform-images.sh` deja preparada la futura réplica privada de Fluent Bit, Argo Rollouts y AWS Load Balancer Controller; **no se ejecutó ni publicó imágenes**.
- CD exige un digest privado de Fluent Bit en `PLATFORM_IMAGES_JSON`; con nodos privados sin NAT no puede depender de imágenes públicas.
- `kind-up.sh` reutiliza el clúster y reinicia el CRD Rollout mediante una anotación de PodTemplate, no mediante el subcomando incompatible `kubectl rollout restart`.
- Pruebas y demos usan flotas/billeteras efímeras y un conector `AVAILABLE`; no dependen de saldo, sesiones o volúmenes conservados de ejecuciones previas. La prueba de concurrencia libera su reserva ganadora.
- El overlay Kind habilita `DEMO_MODE=true` solo localmente para sembrar datos aislados; dev/test/prod no lo habilitan.

### Herramientas detectadas

| Herramienta | Resultado |
|---|---|
| Docker Engine / Compose | Disponibles (`29.10.0` / `5.8.0`); Compose levantó todos los servicios locales. |
| Node / npm | Node `24.19.0`; `npm ci --no-audit --no-fund` instaló 355 paquetes bloqueados. |
| Terraform | Disponible; providers desde lockfile (AWS `5.100.0`, TLS `4.4.2`). |
| Kind / kubectl | Clúster `aegisvolt` existente, kubectl `1.37.2`, Kustomize integrado `5.8.1`. |
| Helm / binario `kustomize` | No presentes; no fueron necesarios para el overlay Kind. El runner AWS futuro sí debe instalar `kustomize` autónomo. |

### Pruebas ejecutadas

| Comando o comprobación | Resultado real |
|---|---|
| `npm ci --no-audit --no-fund` | OK; 355 paquetes. Avisos de deprecación de dependencias, sin error. |
| `npm run lint`, `npm run build`, `npm run test:graphql-schema`, `npm test` | OK; build de todos los workspaces, esquema válido, 3/3 unitarias. |
| `docker compose up --build -d`, `npm run seed` | OK; DynamoDB Local, tres servicios, gateway y web saludables. Se preservó el volumen existente. |
| `npm run test:integration` | OK; 6/6: rechazos terminales, saldo insuficiente, éxito, idempotencia, reembolso antes de liberar y timeout. |
| `npm run test:resilience` | OK; 1/1: dos flotas no adquieren el mismo conector y se libera la reserva de prueba. |
| `npm run test:e2e` | OK; 1/1 Playwright: UI, disponibilidad, flags, sesión `COMPLETED` con flota aislada y cierre de la sesión. |
| `npm run demo:success` | OK; `COMPLETED`, reserva/débito/activación y cierre propio. |
| `npm run demo:fail-billing` | OK; `COMPENSATED`, `INSUFFICIENT_FUNDS` y `RELEASE_SUCCEEDED`. |
| `npm run demo:fail-charger` | OK; `COMPENSATED`, `REFUND_SUCCEEDED` antes de `RELEASE_SUCCEEDED`; el flag se restableció. |
| `npm run kind:up` y consultas `kubectl` | Clúster reutilizado; deployments de dominio/web 2/2, Argo controller 1/1 y Rollout `Healthy=True`, `Available=True`, `Completed=True`. |
| SAGA mediante port-forward de Kind | OK con billetera `kind-proof-20261122`: reserva, débito, activación, `COMPLETED`; tras `closeCharging`, evento `CHARGE_STOPPED` y `connector-04=AVAILABLE`. |
| Canary Kind controlado | El pod de revisión defectuosa respondió HTTP 500 `DEMO_CANARY_FAILURE` conservando readiness. Se restauró la imagen sana y el Rollout volvió a `Healthy=True`/`Available=True`. Es rollback manual local, no AnalysisRun AWS. |
| `terraform fmt -check -recursive`, `npm run terraform:validate` | OK; los dos roots inicializados con backend deshabilitado para validar, sin state remoto ni apply. |
| `terraform ... bootstrap-state plan -refresh=false` | BLOQUEADO antes de planificar: el provider AWS no encontró una fuente de credenciales en este proceso. No hubo cambios ni llamadas de creación. `aws sts get-caller-identity` sí devolvió la cuenta/rol esperados; falta hacer visible esa sesión al proceso Terraform, sin guardar secretos. |
| `validate_terraform_layout.py`, `validate_kubernetes.py`, `validate_workflows.py`, `kubectl kustomize`, `bash -n`, `git diff --check` | OK; 38 documentos Kubernetes, workflows/gates y sintaxis validados. |

### Estado local final

- Compose permanece arriba y saludable; no se ejecutó `docker compose down` ni se eliminaron volúmenes.
- Kind permanece arriba. El Rollout final referencia `aegisvolt/graphql-gateway:0.0.0`, no la imagen defectuosa.
- Fluent Bit está deliberadamente sin pods en Kind (`nodeSelector` local) para no simular CloudWatch. Los logs JSON/EMF se observan en stdout local, no en CloudWatch.
- `git ls-remote --heads origin main dev test prod` confirmó `dev=7060e448…`; `main`, `test` y `prod=1831034…`. Las refs de seguimiento locales de `origin/*` están desactualizadas y no se hizo `fetch`, merge ni push. La rama de trabajo local sigue siendo `feature/terraform-aws` en `f24a548…` con los cambios no confirmados de esta ejecución.

### Límites aún no verificables

- Backend S3, locking remoto, OIDC/IAM, ECR real, VPC, endpoints privados, EKS, IRSA, ALB/NLB, API Gateway privada, CloudWatch y costos: bloqueados por SCP y por falta de autorización de gasto.
- Aunque AWS CLI autenticó `AccountFullAccessRole` en `289663675871`, el provider Terraform no recibió esa fuente de credenciales al ejecutar el plan. Resolver la propagación de la sesión (sin access keys persistentes) es un requisito previo incluso para un plan autenticado.
- El Canary 20/80, el tráfico ALB y el AnalysisRun que consulta CloudWatch no pueden inferirse de Kind. Kind solo prueba reconciliación Argo, health/readiness, defecto controlado y rollback manual.
- No hubo run GitHub Actions del SHA actual, publicación ECR ni evaluación remota de reglas de protección; las ramas/remoto no se modificaron.

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

- No se inyectó una pérdida de conectividad de DynamoDB: no hay un mecanismo de fallo seguro implementado para hacerlo sin interrumpir servicios reales. Los errores técnicos reintentables permanecen en `PENDING` para reconciliación.
- No se ejecutaron Terraform contra backend AWS, AWS, GitHub Actions, CloudWatch ni Prefect contra cuentas externas; no se hizo `terraform apply`.

## Auditoría CI/CD

Fecha: 2026-11-20 (America/Bogota). Esta sección separa deliberadamente las pruebas locales de la configuración verificada en GitHub.

### Estado remoto observado

- `origin/main` y la rama local `main` apuntaban a `bd574b5cdf5d47506e1d53fd91acae3136b7a54f`. Solo existía `main` en el remoto. Se crearon las referencias **locales** `dev`, `test` y `prod` desde ese mismo commit; no se publicaron, no se forzó ningún push y `main` no se modificó.
- La consulta pública `GET /repos/LaMajoP/parcial-tres-enfasis/rulesets` devolvió `[]` y `GET /environments` devolvió `total_count: 0`. Por tanto, las protecciones y Environments no estaban configurados al momento de la auditoría.
- No había GitHub CLI ni `GITHUB_TOKEN`; la protección de ramas que requiere autenticación no pudo verificarse. El script de rulesets se ejecutó solo en modo lectura y propuso exactamente los tres payloads, sin mutar GitHub.
- Los únicos runs públicos eran fallos históricos sobre `bcd6a40593df` y evento `push` a `main`: [CI](https://github.com/LaMajoP/parcial-tres-enfasis/actions/runs/44802500445) y [CD](https://github.com/LaMajoP/parcial-tres-enfasis/actions/runs/44802502459). No son ejecuciones de la configuración local actual ni de un PR a `dev`, `test` o `prod`.

### Cambios auditados

- `ci.yml` ahora corre solo para PR con destino `dev`, `test` o `prod`; valida la cadena de promoción, usa `npm ci`, separa lint/build/schema, pruebas unitarias, integración, resiliencia, E2E y builds Docker sin publicar. Cada job Compose recoge logs y elimina su volumen efímero.
- `terraform-offline` valida HCL sin backend AWS. `terraform-plan` usa OIDC y el workspace de `github.base_ref` solamente en PR internos cuando la compuerta de repositorio `TF_PLAN_ENABLED` es `true`; ya dentro del Environment exige los seis valores reales antes de solicitar OIDC. Sin esa compuerta se omite, sin escribir un falso éxito ni crear workspaces.
- CD permanece estructurado para `github.ref_name`, OIDC, runner privado, digests inmutables, promoción sin recompilación y Argo Rollouts. `CD_ENABLED == 'true'` es un cierre seguro explícito antes de cualquier `apply` o publicación ECR.
- `scripts/github-rulesets.sh` dejó de depender de `gh`: inspecciona por REST, muestra los JSON y solo permite crear rulesets ausentes mediante `--apply` con token administrativo explícito. `scripts/deploy-kubernetes.sh` usa condiciones del CRD `Rollout` con `kubectl`, por lo que ya no requiere el plugin cliente de Argo.

| Comando / acción | Resultado real | Estado |
|---|---|---|
| `python3 scripts/validate_workflows.py` | Validó triggers, jobs, limpieza Compose, plan condicional, bloqueo CD y promoción por digest. | OK |
| `docker run … rhysd/actionlint:latest -no-color` | Sin diagnósticos después de registrar la etiqueta privada en `.github/actionlint.yaml`. | OK |
| `python3 scripts/validate_kubernetes.py` | 37 documentos válidos; Rollout 20/80 sin placeholders. | OK |
| `npm ci --no-audit --no-fund` | Instaló las 355 dependencias bloqueadas desde `package-lock.json`; solo avisos de deprecación/allow-scripts de dependencias. | OK |
| `npm run lint && npm run build` | ESLint sin warnings; todos los workspaces compilaron. | OK |
| `npm run test:graphql-schema` | Contratos GraphQL obligatorios válidos. | OK |
| `npm test` | 3/3 unitarias aprobadas. | OK |
| `npm run terraform:validate` | `fmt`, `init -backend=false` y `validate` correctos; sin credenciales AWS. | OK |
| Stack temporal `aegisvolt-ci` + `npm run test:integration` | DynamoDB Local y servicios reales; 6/6 aprobadas. El volumen temporal se eliminó y el volumen original se preservó. | OK |
| `npm run test:resilience` | 1/1 aprobada contra ese stack temporal. | OK |
| `npm run test:e2e` | Playwright 1/1 aprobada contra frontend, gateway y servicios reales temporales. | OK |
| Cinco `docker build --target` | `graphql-gateway`, `station-reservation`, `billing-wallet`, `energy-dispatch` y `web` construyeron con etiquetas efímeras; no se publicó imagen. | OK |
| API pública GitHub Actions | Solo los dos runs históricos fallidos citados arriba; no se ejecutó CI remoto de estos cambios porque no se hizo commit ni push. | PENDIENTE EXTERNO |

### Pendientes externos de CI/CD

- Publicar las ramas iniciales mediante una acción administrativa auditada, aplicar los rulesets revisados y crear los Environments `dev`, `test` y `prod`.
- Configurar en cada Environment `AWS_ROLE_ARN`, `AWS_REGION`, `TF_STATE_BUCKET`, `TF_OWNER`, `VPC_CIDRS_JSON`, `AVAILABILITY_ZONES_JSON` y, al promover, `PROMOTED_IMAGES_JSON`.
- Configurar confianza OIDC, backend S3, workspaces existentes y runner autohospedado privado con Docker, Node 24, Terraform, AWS CLI, kubectl, kustomize y jq. Solo entonces habilitar `TF_PLAN_ENABLED=true` para demostrar un plan autenticado real; `CD_ENABLED` permanece independiente hasta autorizar despliegues.
- No se ejecutaron `terraform plan` autenticado, `terraform apply`, ECR, EKS, Argo en AWS ni una ejecución GitHub Actions del SHA actual.

## Auditoría Terraform para AWS

El root `bootstrap-state` inicia sin backend remoto, ya que crea el bucket. El
validador puede usar `-backend=false`; tras el primer apply autorizado se copia
`backend.s3.tf.example` a un archivo local ignorado y el procedimiento migra
ese state a `bootstrap/aegisvolt.tfstate` con lockfile S3.

Fecha: 2026-11-20 (America/Bogota). Alcance: validación offline de HCL, providers, scripts, workflows y manifiestos. No se usaron credenciales AWS ni se ejecutaron `plan`, `apply` o `destroy` contra una cuenta.

### Correcciones técnicas

- El state `bootstrap-state` ahora posee los recursos globales de cuenta: ECR compartido y el proveedor OIDC de GitHub. Antes, cada workspace intentaría crear los mismos repositorios ECR; `dev`, `test` y `prod` habrían colisionado y no habría promoción del mismo digest.
- El bucket de state conserva versionado, cifrado SSE-S3, bloqueo público y ahora ownership enforced, `prevent_destroy` y permisos explícitos para `GetBucketLocation`, versiones y el lockfile S3. Se retiró `bucket_key_enabled`: las S3 Bucket Keys aplican a SSE-KMS, no a SSE-S3 AES256.
- La validación offline inicializaba solo `environments`. Ahora inicializa y valida ambos roots, y se versiona `bootstrap-state/.terraform.lock.hcl`.
- EKS pasó a `1.35`, declara access entries para el rol de despliegue, nodos AL2023 privados y endpoints necesarios sin NAT: EC2, EKS, ELB, EKS OIDC, ECR, STS, CloudWatch y execute-api.
- IRSA del gateway ahora autoriza el ARN de índices DynamoDB, necesario para consultar `GSI1`. Fluent Bit recibe egress TLS explícito hacia CloudWatch bajo el default-deny.
- CI conserva `AWS_ROLE_ARN` como rol de plan read-only y CD usa `AWS_DEPLOY_ROLE_ARN`. Ambos propagan `EKS_ACCESS_PRINCIPAL_ARNS`; los inputs de API privada se validan antes de OIDC/Apply.

| Comando / acción | Resultado real | Estado |
|---|---|---|
| `terraform fmt -check -recursive infra/terraform` | Formato válido tras las correcciones. | OK |
| `npm run terraform:validate` | Inicializó con `-backend=false` y validó `bootstrap-state` y `environments` con AWS provider 5.100.0 y TLS 4.4.2. | OK |
| `python3 scripts/validate_terraform_layout.py` | Confirmó state global/ECR, OIDC, access entries EKS, endpoints privados, índices DynamoDB y variables CI/CD. | OK |
| `bash -n scripts/terraform-*.sh` | Sintaxis de scripts válida. | OK |
| `python3 scripts/validate_workflows.py` | Gates `TF_PLAN_ENABLED`/`CD_ENABLED`, roles separados y variables Terraform validados estáticamente. | OK |
| `python3 scripts/validate_kubernetes.py` | 38 manifiestos válidos; incluye egress CloudWatch para Fluent Bit. | OK |
| `docker run … rhysd/actionlint:latest -no-color` | Workflows GitHub Actions sin diagnósticos. | OK |

### Pendientes para un plan AWS real

- Presupuesto, operador temporal, bootstrap aprobado, roles OIDC de plan/deploy y actualización posterior de la política del bucket con sus ARNs.
- `terraform.tfvars` no versionado con CIDRs, AZ y principal de despliegue reales; creación explícita de los workspaces.
- Environments GitHub con todas las variables del primer plan, protección de branches/reviewers y runner privado posterior al primer apply autorizado.
- Instalación del AWS Load Balancer Controller, imagen Fluent Bit accesible sin NAT y segunda fase para habilitar API Gateway privada después de obtener el NLB interno.
- No existe evidencia de plan remoto autenticado, recursos AWS, EKS, ECR o API Gateway creados.
