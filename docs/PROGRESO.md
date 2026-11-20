# Progreso verificable — AegisVolt

Leyenda: `IMPLEMENTADO` tiene artefactos de código; `NO VERIFICADO` requiere una dependencia no disponible y no equivale a éxito.

| Fase | Estado | Evidencia / nota |
|---|---|---|
| A. Inspección y diseño | IMPLEMENTADO | Guía complementaria leída; PDF presente pero streams dañados/no hay extractor. Limitación registrada. ADRs, modelo y diagramas creados. |
| B. Vertical slice DynamoDB Local, servicios, SAGA y GraphQL | IMPLEMENTADO / NO VERIFICADO | Código en `services/*`, `apps/graphql-gateway`, Compose y pruebas de integración. npm/Docker impidieron ejecución aquí. |
| C. Flags, resiliencia y frontend | IMPLEMENTADO / NO VERIFICADO | Flags persistentes por tabla, control de rol, retry/bulkhead/circuit y React/UI/E2E. Requiere npm/Docker para ejecución. |
| D. Kubernetes y observabilidad | IMPLEMENTADO / NO VERIFICADO | Base/overlays/rollouts, logs, Prefect flow. Kind/Prefect no ejecutables en sandbox. |
| E. Terraform | IMPLEMENTADO / NO VERIFICADO | Bootstrap y módulos entregados. Terraform no está instalado y AWS no está autorizado. |
| F. Git, CI/CD y canary | IMPLEMENTADO / NO VERIFICADO | Workflows, rulesets y Argo manifests listos. No hay remoto/EKS/CloudWatch. |
| G. Auditoría final contra rúbrica | PARCIAL | Matriz, demo, manual, preguntas y resultados creados; queda verificación externa real. |

## Condiciones bloqueantes observadas

- Registro npm: `EAI_AGAIN` al resolver `registry.npmjs.org`; no se instalaron dependencias ni generó lockfile.
- Docker: el cliente existe, pero el socket `/var/run/docker.sock` devuelve permiso denegado.
- Terraform, Kind, kubectl y Helm no están disponibles en PATH.
- No hay repositorio Git inicializado/remoto ni credenciales AWS/GitHub.
