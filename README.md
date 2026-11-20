# AegisVolt

Plataforma cloud-native para operadores de flotas eléctricas: consulta conectores, reserva, cobra una billetera y activa una sesión de carga simulada mediante una SAGA orquestada durable. El repositorio contiene una demo local real sobre DynamoDB Local y la infraestructura declarativa para AWS; no afirma que AWS haya sido desplegado.

## Arranque local

Requisitos: Docker Engine con acceso al socket, Docker Compose v2, Node 24 y un `package-lock.json` revisado. Copie configuración no sensible y levante los contenedores:

```bash
cp -n .env.example .env
npm ci --no-audit --no-fund
docker compose up --build -d
npm run seed
```

Abra `http://localhost:5173`, GraphiQL en `http://localhost:4000/graphql`, DynamoDB Local en `http://localhost:8000` y Prefect en `http://localhost:4200`. Las credenciales `local/local` solo sirven para DynamoDB Local y no son credenciales AWS.

Si el clone aún no tiene `package-lock.json`, no ejecute una instalación no reproducible: siga el paso único de `scripts/generate-lockfile.sh` en [docs/ORDEN_EJECUCION_FINAL.md](docs/ORDEN_EJECUCION_FINAL.md). La ausencia actual se debe a que el sandbox no resolvió npm; está declarada como bloqueo, no como éxito.

Para detener sin borrar la evidencia local: `docker compose down`. Para borrar también tablas locales: `docker compose down -v`.

## Recorridos demostrables

```bash
npm run demo:success
npm run demo:fail-charger
npm run test:integration
npm run test:resilience
npm run test:e2e
```

`demo:fail-billing` no falsifica una falla: el caso se ejecuta en `tests/integration/saga.integration.test.ts` creando una billetera real de 1 centavo en DynamoDB Local. El flujo completo y comandos están en [docs/DEMO_SUSTENTACION.md](docs/DEMO_SUSTENTACION.md).

## Componentes

- `services/station-reservation-service`: propietario de estaciones, conectores y bloqueos condicionales.
- `services/billing-wallet-service`: propietario de saldos enteros y movimientos inmutables mediante `TransactWriteItems`.
- `services/energy-dispatch-service`: activación física simulada, estados y telemetría.
- `apps/graphql-gateway`: API GraphQL, SAGA durable, flags y resiliencia; no toca tablas ajenas.
- `apps/web`: UI React responsive que consulta el gateway y actualiza por polling de 3 s.
- `observability/prefect`: health checks y auditoría read-only de SAGAs reales.

## Seguridad y límites

Los servicios no incluyen secretos. En AWS usan IRSA/roles por dominio y las tablas se inyectan por configuración. El modo `DEMO_MODE=true` expone rutas de semilla solo para Compose local; no está definido en manifests Kubernetes. La autorización de la UI demo utiliza `x-aegisvolt-role`; AWS debe integrar OIDC/JWT antes de abrir una entrada de navegador.

La auditoría por requisito está en [docs/AUDITORIA_CONTRA_PDF.md](docs/AUDITORIA_CONTRA_PDF.md) y las verificaciones reales, incluidos bloqueos, en [docs/RESULTADOS_VERIFICACION.md](docs/RESULTADOS_VERIFICACION.md). Consulte [docs/ACCIONES_MANUALES.md](docs/ACCIONES_MANUALES.md) antes de usar AWS o GitHub.
