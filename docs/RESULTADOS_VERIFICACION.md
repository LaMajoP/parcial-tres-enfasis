# Resultados de verificación

| Fecha | Comando / acción | Resultado real | Estado |
|---|---|---|---|
| 2026-11-20 | Inspección inicial (`rg --files`) | El repositorio contenía únicamente el PDF normativo y `agente-patrones-avanzados.md`. | OK |
| 2026-11-20 | Lectura de guía complementaria | Leída completa (492 líneas). | OK |
| 2026-11-20 | Extracción del PDF | `pdfinfo` y `pdftotext` no están instalados. La inspección de streams revela bytes de reemplazo UTF-8 en contenido Flate, por lo que no es descomprimible con `zlib`; no se asumió contenido adicional. | NO VERIFICADO |

Las verificaciones posteriores se añaden al final con su salida honesta.

| Fecha | Comando / acción | Resultado real | Estado |
|---|---|---|---|
| 2026-11-20 | `npm install --cache /tmp/aegisvolt-npm-cache --no-audit --no-fund` | Falló por DNS `EAI_AGAIN` contra `registry.npmjs.org`; no hay dependencias ni `package-lock.json`. | BLOQUEADO |
| 2026-11-20 | `docker version` | Cliente 29.9.2 detectado; acceso al daemon denegado en `/var/run/docker.sock`. Compose/Kind no se ejecutaron. | BLOQUEADO |
| 2026-11-20 | `command -v terraform kind kubectl helm` | No disponibles en PATH. Validación Terraform/Kind no ejecutada. | BLOQUEADO |
| 2026-11-20 | `git status` | El directorio no es un repositorio Git; no hay remoto para validar rulesets/push reject. | BLOQUEADO |
| 2026-11-20 | `node --check` para scripts, `node --experimental-strip-types --check` para `.ts` no JSX, `bash -n scripts/*.sh`, `docker compose config -q` | Sintaxis JavaScript/TypeScript no JSX, shell y Compose válida. Node no puede comprobar `.tsx` con `--check`; TypeScript/Vite real requiere dependencias npm. | OK PARCIAL |

No se registran tests, builds, despliegues AWS, canaries ni screenshots como exitosos porque no se ejecutaron en este entorno.
