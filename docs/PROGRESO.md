# Progreso verificable — AegisVolt

Leyenda: `IMPLEMENTADO` tiene artefactos de código; `NO VERIFICADO` requiere una dependencia no disponible y no equivale a éxito.

| Fase | Estado | Evidencia / nota |
|---|---|---|
| A. Inspección y diseño | IMPLEMENTADO | Especificación oficial transcrita y guía complementaria leídas completas; ADRs, modelo y diagramas creados. |
| B. Vertical slice DynamoDB Local, servicios, SAGA y GraphQL | IMPLEMENTADO / NO VERIFICADO | Servicios, gateway, Compose, readiness y pruebas de integración existen. `npm ci`/Docker no pudieron ejecutarse en sandbox. |
| C. Flags, resiliencia y frontend | IMPLEMENTADO / NO VERIFICADO | Flags persistentes, UI conectada, timeout sin sesión fantasma y pruebas. Requiere npm/Docker para ejecución. |
| D. Kubernetes y observabilidad | IMPLEMENTADO / PARCIAL | Rollout único 20/80, políticas DNS/web, target nginx, Fluent Bit/EMF y Prefect. YAML/contratos estáticos verificados; Kind/EKS/CloudWatch bloqueados. |
| E. Terraform | IMPLEMENTADO / NO VERIFICADO | Bootstrap/módulos, roles IRSA Fluent Bit, dashboard/alarmas alineados. Terraform/AWS no disponibles/autorizados. |
| F. Git, CI/CD y canary | IMPLEMENTADO / PARCIAL | Workflows YAML corregidos, plan base-ref, CD private runner/digests, build-release y checks estáticos. No hubo push, ejecución Actions ni EKS. |
| G. Auditoría final contra rúbrica | PARCIAL | Auditoría contra PDF, orden final, matriz, demo, manual y resultados actualizados. Pendiente evidencia externa real. |

## Condiciones bloqueantes observadas

- Registro npm: `EAI_AGAIN` al resolver `registry.npmjs.org`; no se instalaron dependencias ni generó `package-lock.json` real.
- Docker: el cliente existe, pero el socket `/var/run/docker.sock` devuelve permiso denegado.
- Terraform, Kind, kubectl y Helm no están disponibles en PATH.
- Git existe en `main` con `origin` configurado; la resolución DNS impidió consultar/push al remoto. No hay credenciales AWS utilizables ni autorización de despliegue.
