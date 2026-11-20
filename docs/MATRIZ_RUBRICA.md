# Matriz de rúbrica oficial

Fuente: `Especificacion_Oficial_AegisVolt_Para_Codex.md`. Los porcentajes son capas de evaluación oral; la columna de estado representa implementación/evidencia actual, no una nota garantizada.

| Criterio | Peso | Archivos concretos | Prueba/comando | Resultado real | Evidencia | Pendiente externo | Estado |
|---|---:|---|---|---|---|---|---|
| Bootstrap S3 privado, cifrado, bloqueo público y versionado | 30 % | `infra/terraform/bootstrap-state/*` | `terraform plan/apply` autorizado; `aws s3api get-bucket-versioning` | No ejecutado | HCL + manual | Cuenta/rol AWS | IMPLEMENTADO / NO VERIFICADO |
| Workspaces `dev/test/prod`, state separado y lockfile S3 | 30 % | `environments/versions.tf`, `scripts/terraform-{init,plan}.sh` | `terraform workspace list`, `list-object-versions` | No ejecutado | backend `workspace_key_prefix=env` | Terraform/AWS | IMPLEMENTADO / NO VERIFICADO |
| VPC por workspace, subredes privadas, VPCE y recorrido API válido | 30 % | módulos `network`, `vpc-endpoints`, `api-gateway`; `ARQUITECTURA.md` | plan + DNS/rutas AWS | No ejecutado | diagrama/ADR-0004 | AWS | IMPLEMENTADO / NO VERIFICADO |
| Tablas DynamoDB por dominio y ambiente | 30 % | módulo `dynamodb`, `bootstrap-dynamodb.mjs` | Compose + `aws dynamodb list-tables` | Compose bloqueado | código de tablas dev/test/prod | Docker/AWS | IMPLEMENTADO / NO VERIFICADO |
| CI PR: lint, build, schema, unit, integración y E2E | 25 % | `.github/workflows/ci.yml`, `scripts/check-graphql-schema.ts` | PR a `dev`, `test`, `prod` | YAML válido; no ejecución remota | `validate_workflows.py` | lockfile, GitHub | IMPLEMENTADO / PARCIAL |
| Terraform plan según `github.base_ref`, sin falso éxito | 25 % | `.github/workflows/ci.yml` | PR con Environment/OIDC | No ejecutado; falla explícitamente sin variables | job `terraform-plan` | OIDC/backend | IMPLEMENTADO / NO VERIFICADO |
| Reglas Git y promoción `feature→dev→test→prod` | 25 % | `scripts/{create-branches,github-rulesets}.sh`, manual | rulesets + rechazo remoto | No ejecutado | script/API reproducibles | permisos GitHub | PARCIAL |
| CD usa rama actualizada y evita applies simultáneos | 25 % | `.github/workflows/deploy.yml` | push protegido a cada ambiente | YAML válido; no ejecución | `github.ref_name`, concurrency | runner/AWS | IMPLEMENTADO / PARCIAL |
| Imagen inmutable construida una vez y promovida por digest | 25 % | `build-release-images.yml`, `deploy-kubernetes.sh` | workflow manual + artifact JSON | No ejecutado | validación `@sha256` | ECR/runner | IMPLEMENTADO / NO VERIFICADO |
| Canary 20/80 con análisis CloudWatch y rollback | 25 % | `base/{graphql-gateway,analysis-template}.yaml`, `demo-canary.sh` | `kubectl argo rollouts ...` | YAML estático válido; no EKS | checks de 20 %, muestra, 5xx, p95 | ALB/Argo/CW | IMPLEMENTADO / PARCIAL |
| Tres microservicios desacoplados y gateway GraphQL | 25 % | `services/*`, `apps/graphql-gateway` | Compose health + integración | No ejecutado | contratos HTTP/GraphQL | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| SAGA durable: reservar, debitar, activar; compensación en orden | 25 % | gateway, billing, station, dispatch, `SAGA_ESTADOS_Y_FALLOS.md` | `npm run test:integration` | No ejecutado | persistencia antes/después + tests | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| Idempotencia, concurrencia, retries y reconciliación | 25 % | servicios, `tests/{integration,resilience}` | `npm run test:resilience` | No ejecutado | conditionals/markers/bulkhead | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| Flags runtime aisladas por ambiente | 25 % | gateway, contracts, overlays, tablas flags | integración dev/prod | No ejecutado | cache/invalida/rol prod | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| Logs JSON, métricas, alarmas y dashboard CloudWatch | 12 % | observability package, Fluent Bit, módulos IAM/CW | Logs Insights/CW metrics | Código estático validado; no AWS | EMF dimensiones alineadas | EKS/CW | IMPLEMENTADO / PARCIAL |
| Prefect health y auditoría real de SAGA | 12 % | `observability/prefect/*` | pytest/flow/dashboard | No ejecutado | flow read-only/fixture | pip/Docker | IMPLEMENTADO / NO VERIFICADO |
| UI web: disponibilidad, reserva, flags, historial, billetera/telemetría | 8 % | `apps/web`, E2E | Playwright/Compose | No ejecutado | UI GraphQL/polling | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| Calidad de manifests/probes/policies/seguridad | Transversal | Kustomize, NetworkPolicy, Dockerfile, service accounts | `validate_kubernetes.py`, Kind | Validación estática OK | 37 documentos / sin placeholders | Kind/EKS | IMPLEMENTADO / PARCIAL |

Consulte `AUDITORIA_CONTRA_PDF.md` para correcciones de segunda fase y `RESULTADOS_VERIFICACION.md` para la evidencia de comandos realmente ejecutados.
