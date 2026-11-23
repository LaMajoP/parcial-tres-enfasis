# AegisVolt — Estado final de implementación

## Aplicación y patrones arquitectónicos

Validaciones locales reportadas como exitosas:

- Microservicios y frontend sobre Docker Compose.
- API GraphQL y DynamoDB Local.
- SAGA exitosa y compensaciones por fallo de cobro y cargador.
- Pruebas de integración, idempotencia, resiliencia y E2E.
- Kubernetes Kind con Argo Rollouts.
- Canary local con respuesta HTTP 500 intencional y restauración.

## Prefect

Se ejecutó `npm run prefect:run` contra los servicios locales.

Resultado:
- Flow: enlightened-corgi.
- Estado: Completed.
- Health checks: correctos.
- SAGAs inspeccionadas: 115.
- Anomalías detectadas: 6 registros PENDING históricos.
- Auditoría de solo lectura, sin alterar datos.

## Terraform y LocalStack

Emulación local con LocalStack Community 3.8.1.

Se comprobaron:
- Bucket S3 local con versionado y bloqueo público.
- Migración del state a S3 emulado.
- Workspaces dev, test y prod.
- Una tabla DynamoDB por workspace.
- Estados separados en env/dev, env/test y env/prod.
- Historial de versiones de los estados.
- Planes idempotentes sin cambios posteriores.

## Límites de la demostración

No se desplegaron recursos AWS reales.

Los servicios EKS, VPC, VPCE, CloudWatch, API Gateway,
IAM/OIDC y los despliegues reales de Kubernetes en AWS
no quedan demostrados por LocalStack.

La configuración de infraestructura AWS está definida
como código, pero su ejecución real permanece pendiente
por restricciones de cuenta y costos no autorizados.

El Canary local no equivale a demostrar distribución
real 20/80 mediante ALB y métricas de CloudWatch.

## Reproducibilidad

Aplicación:
- npm run test:all
- npm run test:e2e
- npm run demo:success
- npm run demo:fail-billing
- npm run demo:fail-charger
- npm run kind:up
- npm run demo:canary:kind

Prefect:
- npm run prefect:run

Los estados del emulador dependen de que LocalStack
y sus datos locales sigan disponibles.
