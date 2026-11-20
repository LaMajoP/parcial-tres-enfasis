# Guion de sustentación (10–15 min)

## Antes de empezar

Ejecute `npm install --no-audit --no-fund`, `docker compose up --build -d` y `node scripts/seed.mjs`. Verifique `docker compose ps`. No diga que AWS está desplegado si usa solo Compose.

## 1. Aislamiento e infraestructura (2 min)

```bash
terraform -chdir=infra/terraform/environments workspace list
aws s3api list-object-versions --bucket REEMPLAZAR_BUCKET --prefix 'env:/dev/aegisvolt.tfstate'
```

Muestre las tres claves `env:/...`; explique que versionamiento permite inspección/rollback seguro. Muestre `docs/diagrams/despliegue-red.md`: VPCE invoca la API privada; VPC Link llega al NLB, no al revés.

## 2. Flujo exitoso (3 min)

Abra `http://localhost:5173` y pulse “Confirmar reserva y carga” con un conector disponible. Debe aparecer `COMPLETED`, session id y timeline. En otra terminal:

```bash
npm run demo:success
curl -s http://localhost:3003/sessions | jq
```

Explique reserva condicional, `TransactWriteItems`, sesión/telemetría y el mismo `correlation_id`.

## 3. Fallos y compensación (3 min)

```bash
npm run test:integration -- --runInBand
npm run demo:fail-charger
```

En UI active `SIMULATE_CHARGER_HARDWARE_FAULT`, ejecute una carga y muestre `COMPENSATED`. El timeline debe ordenar `REFUND_SUCCEEDED` antes de `RELEASE_SUCCEEDED`. El caso de saldo insuficiente está en la prueba de integración con billetera de un centavo: libera sin activar.

## 4. Flags y observabilidad (2 min)

Cambie `ENABLE_DYNAMIC_SURGE_PRICING` en la UI dev; el estimado cambia tras el polling. Consulte flags en prod desde su endpoint/tabla prod y muestre que no cambió. Muestre Logs Insights filtrando el `correlation_id` y un run de Prefect auditando tabla SAGA real.

## 5. CI/CD y canary (2–3 min, AWS real)

Muestre un PR `feature/* → dev` con los cinco checks y artifact plan. Luego la promoción dev→test→prod con aprobación prod. En test:

```bash
kubectl -n aegisvolt-test argo rollouts get rollout graphql-gateway-canary
kubectl -n aegisvolt-test get analysisrun
```

Muestre peso 20/80, muestra mínima, éxito a 100 % o `kubectl ... argo rollouts abort graphql-gateway-canary` con la imagen defectuosa. No confunda réplicas con peso de tráfico.

## Limpieza

`docker compose down` conserva volumen; `docker compose down -v` lo borra. Para AWS siga el procedimiento aprobado de [COSTOS_AWS.md](COSTOS_AWS.md), nunca destruya state antes de recursos.
