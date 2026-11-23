# Estado de continuidad — Floci local

Fecha de cierre: 2026-11-22/23 (hora local del laboratorio).

## Completado y preservado

- Floci 2.5.0 persistente en `127.0.0.1:4567`, con datos en el volumen
  `aegisvolt-floci-data`; se comprobó persistencia tras reinicio.
- Terraform local separado de AWS real: bootstrap (S3/ECR) y workspaces
  `dev`, `test`, `prod`. Los planes finales de los tres workspaces no tenían
  cambios.
- Recursos API emulados verificados: 15 tablas DynamoDB, 3 VPC AegisVolt,
  33 endpoints, 3 EKS, 22 log groups, 3 dashboards, 3 alarmas, 1 bucket y 8
  repositorios ECR.
- k3s real de Floci y AegisVolt desplegados en `aegisvolt-dev`,
  `aegisvolt-test` y `aegisvolt-prod`. En cada ambiente: cuatro Deployments
  2/2 y Rollout GraphQL Healthy 4/4.
- Flujos GraphQL SAGA dev, pruebas unitarias/integración/resiliencia/E2E,
  validaciones Terraform/Kubernetes/workflows y rollback canary local fueron
  ejecutados con éxito. Los detalles están en
  `docs/entrega-final/ESTADO_FINAL.md`.
- Backups de estados locales con SHA-256 en
  `artifacts/local-floci-state-backups/` (ignorados por Git). No se borraron
  estados, contenedores, volúmenes ni backups.

## Estado activo al detenerse

- Floci y los tres k3s siguen activos.
- Los contenedores Compose usados para test están detenidos, sin borrarse.
- Las cinco imágenes locales `aegisvolt/*:0.0.0` están construidas.

## Limitaciones y pendientes conocidos

- API Gateway/VPC Link permanece deshabilitado localmente: no se verificó un
  NLB/ALB Controller real en Floci.
- CloudWatch se validó como API y grupos de logs; Fluent Bit/IRSA y envío real
  de logs no se demostraron. El grupo del gateway tenía cero streams.
- El healthcheck heredado del contenedor activo usa `wget` inexistente y Docker
  puede mostrarlo como `unhealthy` aunque `/_localstack/health` devuelve 200.
  `compose.floci.yaml` ya contiene el healthcheck correcto para una recreación
  futura, que no se hizo para preservar el contenedor actual.
- El socket Docker es necesario para EKS de Floci; `:ro` no limita las
  operaciones de la API Docker. Usar solo en una estación de confianza.

## Comandos exactos para continuar

```bash
# Inspección no destructiva y arranque si Floci está detenido.
./scripts/floci-up.sh
./scripts/floci-verify.sh
./scripts/floci-state-backup.sh

# Planes seguros: no aplicar si aparece una acción delete.
./scripts/floci-bootstrap.sh plan
./scripts/floci-terraform.sh plan dev
./scripts/floci-terraform.sh plan test
./scripts/floci-terraform.sh plan prod

# Reconstruir/importar la aplicación local si es necesario.
./scripts/floci-build-images.sh
./scripts/floci-eks-deploy.sh aegisvolt-dev
./scripts/floci-eks-deploy.sh aegisvolt-test
./scripts/floci-eks-deploy.sh aegisvolt-prod

# Verificaciones funcionales/canary ya disponibles.
./scripts/demo-canary-floci.sh aegisvolt-dev

# Detención no destructiva al finalizar.
./scripts/floci-down.sh
```

No ejecutar `terraform destroy`, `docker compose down -v`, ni eliminar
volúmenes/estados/backups para retomar este laboratorio.
