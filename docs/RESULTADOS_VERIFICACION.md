# Resultados de verificación reales

Fecha de auditoría/corrección: 2026-11-20. Baseline inspeccionado: `bcd6a40593df46f41bed8e51bd86146f0a0c198f` (`main`, `origin` configurado). Los resultados siguientes son literales: `NO VERIFICADO` no significa aprobado.

| Fecha | Comando / acción | Resultado real | Estado |
|---|---|---|---|
| 2026-11-20 | Lectura de `Especificacion_Oficial_AegisVolt_Para_Codex.md` | Leída completa; reemplaza la limitación previa de extracción del PDF y se usó como fuente normativa. | OK |
| 2026-11-20 | Lectura de `Prompt_Segunda_Fase_Codex_AegisVolt_Auditoria_y_Correccion.md` | Leído completo y ejecutado mediante auditoría/correcciones documentadas. | OK |
| 2026-11-20 | `git rev-parse HEAD`, `git status --short`, `git remote -v` | Repo Git válido, baseline `bcd6a40`, remoto configurado. Existen cambios locales de esta segunda fase y los dos documentos de entrada sin seguimiento al inicio. | OK |
| 2026-11-20 | `node --version`, `npm --version`, Docker | Node `v24.19.0`, npm `11.17.0`, Docker client/Compose presentes. | OK |
| 2026-11-20 | `npm install --package-lock-only --offline` con caché copiada a `/tmp` | Falló `ENOTCACHED` para `@aws-sdk/client-dynamodb`; no se generó un lockfile ficticio. | BLOQUEADO |
| 2026-11-20 | Acceso a `registry.npmjs.org` / instalación npm | Falló por DNS `EAI_AGAIN`. No existen `node_modules` ni `package-lock.json`; por ello no se ejecutaron build, ESLint, Vitest, Playwright ni schema con dependencias reales. | BLOQUEADO |
| 2026-11-20 | `npm ping --fetch-timeout=5000 --fetch-retries=0` | Falló nuevamente con `getaddrinfo EAI_AGAIN registry.npmjs.org`. Se reintentó antes de cerrar verificaciones; el bloqueo persiste. | BLOQUEADO |
| 2026-11-20 | `docker version` | Docker client detectado; socket `/var/run/docker.sock` respondió permiso denegado. No se construyeron imágenes ni se inició Compose. | BLOQUEADO |
| 2026-11-20 | `command -v terraform kind kubectl helm actionlint` | Herramientas no disponibles en PATH. No se ejecutaron validate/plan Terraform, Kind, Argo real ni actionlint. | BLOQUEADO |
| 2026-11-20 | `git ls-remote origin` | DNS no resolvió `github.com`. No se consultaron logs de las dos ejecuciones rojas, ni se hizo push o cambio de rulesets. | BLOQUEADO |
| 2026-11-20 | `python3 scripts/validate_workflows.py` | Pasó: YAML de los tres workflows parseable; CI por PR dev/test/prod, CD solo por push dev/test/prod y runner privado para EKS. | OK |
| 2026-11-20 | `python3 scripts/validate_kubernetes.py` | Pasó: 37 documentos YAML, Rollout base con 20/80/ALB y sin placeholders desplegables. Es validación estática, no render Kustomize ni clúster. | OK PARCIAL |
| 2026-11-20 | `bash -n scripts/*.sh` | Sintaxis de scripts shell válida. | OK |
| 2026-11-20 | `node --check` / `node --experimental-strip-types --check` | Sintaxis válida para scripts JS y fuentes TS no JSX comprobadas, incluidos gateway y dispatch. No sustituye `tsc` ni resolución de imports. | OK PARCIAL |
| 2026-11-20 | `docker compose config -q` | Configuración Compose válida estáticamente después de healthchecks/target web runtime. | OK |
| 2026-11-20 | `git diff --check` | Sin errores de whitespace en el diff local. | OK |
| 2026-11-20 | `python3 -m py_compile observability/prefect/flows.py observability/prefect/tests/test_flows.py` | Sintaxis Python de flow y fixture válida. `prefect`/`boto3` no están instalados, por lo que no se ejecutó el flow ni pytest. | OK PARCIAL |
| 2026-11-20 | `npm run test:graphql-schema` | Falló con `tsx: command not found`; no hay dependencias porque no existe lockfile y npm sigue bloqueado por DNS. | BLOQUEADO |
| 2026-11-20 | `npm run build` | Falló con `tsc: command not found` en workspaces; no se declara como build válido. | BLOQUEADO |
| 2026-11-20 | `npm run terraform:validate` | Falló con `terraform: command not found`. | BLOQUEADO |
| 2026-11-20 | `npm run kind:up` | Terminó con código 69 y mensaje `Instale Kind`; no se creó clúster. | BLOQUEADO |
| 2026-11-20 | `npm run lint`, `npm test`, `npm run test:integration`, `npm run test:e2e` | Todos fallaron con código 127 (`eslint`, `vitest`, `playwright` no encontrados) por dependencias ausentes; no se reportó ningún test como ejecutado. | BLOQUEADO |
| 2026-11-20 | `docker compose up --build -d` | Falló con permiso denegado al socket Docker. No se levantó la aplicación local. | BLOQUEADO |

## Comandos pendientes al desbloquear entorno

```bash
bash scripts/generate-lockfile.sh   # una vez, revisar y versionar package-lock.json
npm ci --no-audit --no-fund
npm run lint && npm run build && npm run test:graphql-schema
npm test && npm run test:integration && npm run test:resilience && npm run test:e2e
docker compose up --build -d && npm run seed
npm run kind:up
npm run terraform:validate
actionlint
```

No se registran como verdes despliegues AWS, CloudWatch, Prefect, GitHub Actions, EKS, VPCE, API Gateway privada, rulesets remotos, canary ponderado ni pruebas de navegador porque no se ejecutaron en este entorno.
