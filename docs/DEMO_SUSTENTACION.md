# Guion de sustentación (10–15 minutos)

Solo declare como desplegado lo que esté visible durante la demo. Compose/Kind no prueban AWS.

## 0. Preparación (antes de la defensa)

```bash
npm ci --no-audit --no-fund
docker compose up --build -d
npm run seed
docker compose ps
```

Salida esperada: DynamoDB Local y los tres servicios/gateway `healthy`; web accesible en `http://localhost:5173`, GraphiQL en `http://localhost:4000/graphql`, Prefect en `http://localhost:4200`.

## 1. Estados Terraform y red (2 min, AWS real)

```bash
terraform -chdir=infra/terraform/environments workspace list
aws s3api list-object-versions --bucket REEMPLAZAR_BUCKET --prefix 'env:/dev/aegisvolt.tfstate'
```

Muestre `dev`, `test`, `prod` y versiones S3. Explique `workspace_key_prefix=env`, por qué no se interpola workspace en backend, y que rollback empieza inspeccionando una versión/plan. Abra `docs/diagrams/despliegue-red.md`: cliente privado → VPCE `execute-api` → API REST privada → VPC Link → NLB/ALB interno → gateway/pods. Aclare que VPCE y VPC Link no son intercambiables.

## 2. Flujo exitoso local (2 min)

En UI, elija conector disponible y pulse **Confirmar reserva y carga**. Muestre `COMPLETED`, `sessionId`, timeline y `correlationId`. En consola:

```bash
npm run demo:success
curl -s http://localhost:3003/sessions | jq
```

Por defecto el script cierra su propia sesión para dejar el conector disponible; use `KEEP_DEMO_SESSION=true npm run demo:success` solo si desea mantenerla visible y ciérrela después desde GraphQL. Explique reserva condicional, movimiento DynamoDB atómico y telemetría del simulador.

## 3. Compensaciones e idempotencia (2 min)

```bash
npm run test:integration
npm run test:resilience
npm run demo:fail-billing
npm run demo:fail-charger
```

Cada demo crea una billetera local única y elige un conector `AVAILABLE`; billing deja el conector disponible y no activa hardware. El caso charger muestra `COMPENSATED` con `REFUND_SUCCEEDED` antes de `RELEASE_SUCCEEDED`. `demo:fail-charger` vuelve a apagar su flag en `finally`. Abra `docs/SAGA_ESTADOS_Y_FALLOS.md` para la máquina durable y recuperación.

## 4. Flags, logs y Prefect (2 min)

Active `ENABLE_DYNAMIC_SURGE_PRICING` en dev desde UI y espere hasta 3 s de polling; muestre el nuevo estimado. Consulte flags prod desde tabla/endpoint prod, sin cambiarlo. Filtre un `correlation_id` real en CloudWatch Logs Insights y ejecute el flow:

```bash
python3 observability/prefect/flows.py --environment dev --gateway-url http://localhost:4000
```

Muestre el resumen de health, SAGAs escaneadas y anomalías reales en Prefect. No presente métricas hardcodeadas.

## 5. PR, promoción y canary (2–3 min, GitHub/EKS real)

1. Muestre PR `feature/* → dev`: checks `lockfile`, lint/build/schema, unit, integración, E2E y `terraform-plan`; el plan toma `github.base_ref`.
2. Muestre un intento de force-push rechazado por el servidor y los Environments/approval prod.
3. Muestre `promoted-images-<SHA>.json` del workflow de build: son cinco referencias por digest y `test`/`prod` reutilizan el mismo JSON.
4. En `test`:

   ```bash
   kubectl -n aegisvolt-test argo rollouts get rollout graphql-gateway
   kubectl -n aegisvolt-test get analysisrun
   ```

   Durante la pausa, verifique 20 % canary / 80 % stable en target groups ALB y la muestra de CloudWatch. No confunda porcentaje de pods con distribución garantizada de solicitudes.
5. Construya previamente el target Docker `gateway-defective`, publíquelo solo en ECR de test y use su digest. Mantiene `/health/ready`, pero responde 500 en `/graphql`, de modo que el `AnalysisRun` falla por métricas reales:

   ```bash
   CANARY_DEFECTIVE_IMAGE='REEMPLAZAR_ECR/aegisvolt/graphql-gateway-defective@sha256:REEMPLAZAR' npm run demo:canary
   ```

   Muestre el `AnalysisRun` fallido y:

   ```bash
   kubectl -n aegisvolt-test argo rollouts abort graphql-gateway
   kubectl -n aegisvolt-test argo rollouts get rollout graphql-gateway
   ```

   Resultado esperado: stable conserva tráfico; no se reemplaza 100 % antes del análisis.

## Limpieza segura

```bash
docker compose down        # conserva volumen local
docker compose down -v     # borra DynamoDB Local deliberadamente
```

Para AWS, siga `COSTOS_AWS.md`; no destruya state antes de recursos y solicite aprobación antes de apagar infraestructura.
