# SEGUNDA FASE CODEX — AUDITORÍA, CORRECCIÓN Y VERIFICACIÓN REAL DE AEGISVOLT

## Rol y objetivo

Actúa como arquitecto principal, ingeniero DevOps/Cloud, backend, frontend y QA. **No vuelvas a crear el proyecto desde cero**: trabaja sobre el monorepo existente `LaMajoP/parcial-tres-enfasis`, preserva sus funcionalidades útiles y corrige defectos reales. Tu objetivo NO es presentar porcentajes estimados de avance: es alcanzar condiciones de aceptación verificables, con evidencia reproducible y lista de pasos externos restantes.

## Autoridad de los requisitos

1. Lee de inicio a fin `Especificacion_Oficial_AegisVolt_Para_Codex.md` que yo proporcionaré en la raíz; contiene las **11 páginas** del PDF oficial extraídas a texto. Cuando exista discrepancia, el PDF original prevalece.
2. Lee también `agente-patrones-avanzados.md`, `docs/MATRIZ_RUBRICA.md`, `docs/RESULTADOS_VERIFICACION.md` y `docs/ACCIONES_MANUALES.md`.
3. **NO afirmes que el PDF es ilegible ni que has confirmado su contenido si no has leído el archivo de texto proporcionado.** Reconstruye la matriz requisito por requisito partiendo del documento oficial, no de suposiciones.
4. La rúbrica es: IaC 30 %, CI/CD y Git/Canary 25 %, backend/GraphQL/SAGA/flags 25 %, CloudWatch/Prefect 12 %, frontend 8 %. En la sustentación se califican respuestas y demostraciones prácticas.

## Hallazgos externos ya observados que debes investigar y resolver

Al 20-11-2026, en GitHub solo existe `main` sin protección y hay dos ejecuciones de Actions en rojo para `ci.yml` y `deploy.yml` originadas por un push a `main`, ambas sin jobs. Revisa **la validez del YAML y los mensajes reales** de GitHub, no asumas simplemente una causa. `package-lock.json` está ausente mientras `actions/setup-node@v4` utiliza `cache: npm`, lo que puede bloquear la CI antes de ejecutar pruebas. No inventes ejecuciones exitosas.

El workflow `.github/workflows/deploy.yml` aplica overlays con un `Deployment` `graphql-gateway`, pero el Canary de Argo se define como un recurso `Rollout` separado (`graphql-gateway-canary`) en `infra/kubernetes/rollouts/`; los overlays no incluyen actualmente esos manifiestos de Rollout. La tubería no demuestra control de tráfico 20/80 ni análisis de CloudWatch real, y aún utiliza imágenes placeholder `REPLACE_AT_CD`/`REPLACE_DIGEST`. Falta verificar un proceso completo de build, publicación en ECR por digest inmutable, actualización de imágenes y promoción. El comando `kubectl config use-context` no genera por sí mismo credenciales ni conectividad hacia un EKS privado; revisa acceso desde runners GitHub hospedados fuera de VPC.

Existe una `NetworkPolicy` default-deny para ingress/egress sin una excepción clara para DNS (UDP/TCP 53), y la UI web tampoco tiene una política de ingress. Si la CNI hace enforcement, el sistema puede quedarse sin resolución DNS o acceso web. Revisa los overlays, selectors con `nameSuffix`, namespaces y ServiceAccounts, RBAC/IRSA, endpoints EKS/DynamoDB/CloudWatch y enrutamiento real.

`packages/shared-observability/src/index.ts` escribe logs JSON a stdout y expone contadores en memoria en formato Prometheus; esto **no equivale por sí mismo** a enviar logs ni métricas a CloudWatch. Terraform crea grupos, dashboard y alarmas, pero debes conectar el pipeline real de logs/métricas y demostrar que la consulta por `correlation_id` y las consultas de Argo/Prefect tienen datos reales. Valida también las consultas, los IAM roles y el aislamiento por ambiente.

La demo documentada usa `npm run test:integration -- --runInBand`; verifica compatibilidad con Vitest y corrige ese comando si corresponde. Inspecciona scripts, pruebas y cobertura reales. El stack no ha sido instalado ni ejecutado con Docker, Terraform o Kubernetes en el sandbox previo.

## Ejecución obligatoria por fases

### Fase 1 — Baseline y especificación
- Registra SHA, árbol, versiones, `git status`, dependencias y problemas existentes. No reescribas todo.
- Produce una matriz granular `docs/AUDITORIA_CONTRA_PDF.md`: cada requisito textual, peso/capa, ruta de archivo, comando de validación, evidencia, estado REAL (PASS/FAIL/BLOCKED), corrección pendiente y responsable (Codex/usuario).
- Detecta contradicciones entre requisitos, código, Docker, Kubernetes, pipelines, documentación y CLI. Da prioridad a bloqueantes arquitectónicos.

### Fase 2 — Entorno local realmente ejecutable
- Crea `package-lock.json` reproducible compatible con npm y usa `npm ci` en CI y Docker cuando aplique.
- Revisa y corrige TypeScript, dependencias, workspaces, GraphQL, Vite, Dockerfile, Compose, health checks, seed y errores de arranque.
- Comprueba `npm run lint`, `npm run build`, `npm test`, `npm run test:graphql-schema`, `docker compose config`, y, si Docker está disponible, `docker compose up --build -d`, `node scripts/seed.mjs`, demos y E2E.
- Implementa readiness/wait con timeouts; haz que cada comando reporte fallos en lugar de continuar silenciosamente.
- Si no tienes Docker/npm/red, NO marques PASS: deja comandos exactos y errores completos para que yo ejecute en mi terminal y te entregue sus salidas.

### Fase 3 — SAGA, datos y funcionalidad
- Verifica reserva, débito, activación, éxito, saldo insuficiente y falla física; confirma orden reembolso→liberación, persistencia real en DynamoDB Local, transiciones, retries seguros, idempotencia bajo duplicados y carreras concurrentes.
- Evalúa reconciliación después de un crash en cada etapa, compensación fallida, expiración de bloqueos, consistencia de saldo y prevención de dobles cobros.
- Añade y ejecuta pruebas de negocio, integración y resiliencia para los escenarios reales, no mocks que solo simulen verde.
- Valida flags `ENABLE_DYNAMIC_SURGE_PRICING`, `ENABLE_FAST_CHARGE_BOOST` y `SIMULATE_CHARGER_HARDWARE_FAULT` con estados separados por dev/test/prod y actualización en caliente sin re-deploy.
- Verifica la UI conectada a GraphQL con disponibilidad, reserva, estado SAGA, fallos/compensaciones, telemetría y flags.

### Fase 4 — GitHub CI y gobierno
- Corrige sintaxis y validez de los workflows antes de crear ramas protegidas; verifica con un parser y, cuando sea posible, `actionlint` o GH Actions real.
- Garantiza checks de PR: lint/build/schema, unit, integración, E2E y `terraform plan` real del workspace destino; sin pasos `echo` como sustitutos de planes efectivos.
- Divide verificaciones locales/offline de verificaciones cloud con OIDC para que sea claro qué no puede correr sin acceso real. Documenta las dependencias y muestra fallos honestos.
- Corrige el `deploy.yml` para desplegar únicamente tras merge a dev/test/prod, sin desplegar por pushes a main/feature; respeta promoción `feature/* → dev → test → prod`, no reutilices credenciales persistentes.
- Documenta `gh` commands y reglas de protección GitHub con prohibición de push directo, no-force-push, checks obligatorios y PRs, incluida prueba real de rechazo.

### Fase 5 — Terraform, redes privadas, Kubernetes, Canary
- Ejecuta `terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate`, y si es posible `terraform plan` por workspace con backend remoto S3. No despliegues servicios facturables sin aprobación explícita.
- Valida S3 versionado y backend con locking, aislamiento de `terraform.workspace`, VPC/subnets/rutas/endpoints, DynamoDB database-per-service, IRSA, EKS, ECR, CloudWatch, API Gateway privado y la comunicación real VPCE→API Gateway→VPC Link→NLB→Pod.
- Arregla manifests Kustomize, NetworkPolicies (DNS y web), selectors, namespace, imágenes, probes, recursos, permisos y acceso a EKS privado. Valida con `kubectl kustomize` y herramientas de schema cuando estén disponibles.
- Integra **de verdad** un único mecanismo Canary basado en Argo Rollouts: ingresa traffic routing correcto, stable/canary Services, ingreso/router compatible, análisis con métricas verificables, peso 20 % → 100 % o abort/rollback. El pipeline debe desplegar/promover `Rollout`, no solo un `Deployment` tradicional.
- Diseña operativamente el acceso desde CI a clusters privados (runner self-hosted dentro de VPC, o solución privada equivalente), con requisitos de seguridad y costo; no asumas acceso a EKS desde GitHub-hosted runner.

### Fase 6 — CloudWatch y Prefect
- Conecta colector de logs stdout JSON a CloudWatch por ambiente con `correlation_id`, log groups y permisos mínimos; enlaza métricas reales al dashboard, alarmas y AnalysisTemplates del Canary. Documenta el camino de las métricas y añade prueba de existencia de datos.
- Haz ejecutables Prefect Flow/Tasks: health real de los tres ambientes, escaneo read-only de SAGA, alertas sobre transacciones huérfanas y compensaciones incompletas, pruebas y dashboard; no registres ejecuciones inexistentes.

### Fase 7 — Verificación, informe y pasos del usuario
- Actualiza README, `docs/RESULTADOS_VERIFICACION.md`, `docs/MATRIZ_RUBRICA.md` y `docs/ACCIONES_MANUALES.md` exclusivamente con hechos observados.
- Agrega `docs/ORDEN_EJECUCION_FINAL.md` con etapas ordenadas por dependencia y comandos literalmente copiables; separa local, GitHub, AWS y defensa.
- Agrega `docs/DEMO_SUSTENTACION.md` verificado con resultados esperados: S3 state versions, workspaces, network packet path, push rechazado, promoción PR, Canary, fallo SAGA, idempotencia, Prefect/CloudWatch y cambios de flags por ambiente.
- Entrega tabla final de PASS / FAIL / BLOCKED, 10 bloqueantes principales, archivos modificados y comandos ejecutados con salidas verificables.

## Límites y criterios de aceptación

- **No despliegues ni destruyas AWS, no crees recursos facturables, no modifiques configuraciones de cuenta ni reglas de GitHub sin autorización explícita.** Puedes preparar IaC y comandos.
- No hagas `git push --force`. Mantén un flujo de ramas coherente.
- No finjas pruebas, cobertura, screenshots, PRs, despliegues, métricas, planes o versiones S3.
- Si detectas un error, corrígelo y vuelve a comprobarlo antes de declarar éxito.
- Haz tantas iteraciones como permita tu entorno hasta agotar los problemas reparables localmente; no te limites a listar recomendaciones.
- El resultado final debe permitir que YO complete las acciones externas mediante pasos que pueda seguir sin diseñar ni escribir código adicional.
