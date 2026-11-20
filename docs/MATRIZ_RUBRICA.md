# Matriz de rúbrica oficial

`Resultado real` nunca equivale a una nota. “NO VERIFICADO” significa que el código existe pero el sandbox no permitió ejecutar el recorrido externo/local indicado.

| Criterio | Peso | Archivos concretos | Prueba/comando | Resultado real | Evidencia | Pendiente externo | Estado |
|---|---:|---|---|---|---|---|---|
| Bootstrap S3 privado, cifrado y versionado | 30% | `infra/terraform/bootstrap-state/*` | `terraform apply` bootstrap autorizado | No ejecutado | outputs + `list-object-versions` en manual | Cuenta AWS | IMPLEMENTADO / NO VERIFICADO |
| Workspaces/state histórico aislado | 30% | `environments/versions.tf`, `scripts/terraform-*` | `terraform workspace list`; `aws s3api list-object-versions` | No ejecutado | `ADR-0003` | AWS + Terraform | IMPLEMENTADO / NO VERIFICADO |
| VPC privada, VPCE y recorrido válido | 30% | módulos `network`, `vpc-endpoints`, `api-gateway` | comandos DNS/rutas manual | No ejecutado | diagrama despliegue | AWS | IMPLEMENTADO / NO VERIFICADO |
| Tablas DynamoDB por servicio/ambiente | 30% | módulo `dynamodb`, `bootstrap-dynamodb.mjs` | Compose + `aws dynamodb list-tables` | Compose bloqueado por socket | nombres/código | Docker accesible | IMPLEMENTADO / NO VERIFICADO |
| CI de PR: lint/build/tests/schema | 25% | `.github/workflows/ci.yml` | PR remoto | No repo Git remoto | workflow | GitHub | IMPLEMENTADO / NO VERIFICADO |
| Plan según `github.base_ref`, sin echo falso | 25% | `ci.yml` job `terraform-plan` | PR a cada rama | No ejecutado | job falla sin OIDC/backend | GitHub/AWS | IMPLEMENTADO / NO VERIFICADO |
| Promoción dev→test→prod y apply según rama | 25% | `deploy.yml`, reglas | merge protegido | No ejecutado | `github.ref_name`, concurrency | GitHub/AWS | IMPLEMENTADO / NO VERIFICADO |
| Protección remota Git | 25% | `github-rulesets.sh`, manual | `git push`/force push contra remoto | No hay remoto | comando reproducible | GitHub | PARCIAL |
| Canary 20/80 y rollback | 25% | `rollouts/*`, `demo-canary.sh` | `kubectl argo rollouts` + CloudWatch | No ejecutado | AnalysisTemplate | EKS/ALB/CW | IMPLEMENTADO / NO VERIFICADO |
| Tres microservicios desacoplados | 25% | `services/*/src/index.ts` | Compose health | No ejecutado | interfaces HTTP | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| GraphQL unificado y UI conectada | 25% / 8% | `apps/graphql-gateway`, `apps/web` | E2E Playwright | No ejecutado | `operations.spec.ts` | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| SAGA durable, orden y compensación | 25% | gateway, `SAGA_ESTADOS_Y_FALLOS.md` | `test:integration` | No ejecutado | pruebas específicas | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| Idempotencia/concurrencia | 25% | servicios, `tests/resilience` | `npm run test:resilience` | No ejecutado | test no simulado | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| Flags aisladas y cambio caliente | 25% / 8% | gateway, frontend, contratos | integración + UI | No ejecutado | tablas por env/caché | npm/Docker | IMPLEMENTADO / NO VERIFICADO |
| CloudWatch logs, métricas, alarmas | 12% | observabilidad, módulo cloudwatch | EKS + Logs Insights | No ejecutado | queries | AWS | IMPLEMENTADO / NO VERIFICADO |
| Prefect health/auditoría real | 12% | `observability/prefect/*` | `python flows.py`/dashboard | Dependencias no instaladas | flow y test | pip/Docker | IMPLEMENTADO / NO VERIFICADO |
| UI disponibilidad, reserva, flags, auditoría, telemetría | 8% | `apps/web/src/main.tsx` | Playwright | No ejecutado | E2E | npm/Docker | IMPLEMENTADO / NO VERIFICADO |

La ausencia de PDF extraíble se registra en `RESULTADOS_VERIFICACION.md`; esta matriz sigue la rúbrica transcrita del enunciado y no inventa confirmación del documento dañado.
