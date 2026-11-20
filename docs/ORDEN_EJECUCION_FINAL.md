# Orden de ejecución final y reproducible

Siga estas etapas en orden. Pare ante un fallo: no promueva artefactos ni ejecute Terraform apply para ocultarlo.

## 1. Cerrar dependencias locales

1. Compruebe `node --version` (24.x), `docker version`, `docker compose version` y conectividad a `registry.npmjs.org`.
2. Como falta el lockfile debido al bloqueo DNS del sandbox, en una red autorizada ejecute una sola vez:

   ```bash
   bash scripts/generate-lockfile.sh
   npm ci --no-audit --no-fund
   git add package-lock.json .npmrc
   git commit -m "chore: lock dependencias npm"
   ```

3. Desde ese momento use solo `npm ci`; no sustituya CI/Docker por `npm install`.

## 2. Validaciones sin infraestructura cloud

```bash
python3 scripts/validate_workflows.py
python3 scripts/validate_kubernetes.py
bash -n scripts/*.sh
docker compose config -q
npm run lint
npm run build
npm run test:graphql-schema
npm test
```

Resultado esperado: todas finalizan con código 0. `actionlint` es una comprobación adicional si está instalado: `actionlint`.

## 3. Recorrido local real

```bash
cp -n .env.example .env
docker compose up --build -d
npm run seed
npm run test:integration
npm run test:resilience
npm run test:e2e
KEEP_DEMO_SESSION=true npm run demo:success
npm run demo:fail-billing
npm run demo:fail-charger
docker compose logs --no-color graphql-gateway station-reservation-service billing-wallet-service energy-dispatch-service
```

Abra `http://localhost:5173` y Prefect en `http://localhost:4200`. `demo:success` libera el conector al final salvo que se defina `KEEP_DEMO_SESSION=true`; conserva telemetría durable.

## 4. Kubernetes local (límite explícito)

```bash
npm run kind:up
kubectl -n aegisvolt-dev get pods,svc,rollouts,networkpolicy
npm run kind:down
```

Kind valida manifiestos, imágenes, probes y el controlador Argo. No puede demostrar ALB weighted routing, VPCE, API Gateway privada ni CloudWatch; esos puntos pertenecen a la fase AWS.

## 5. GitHub, AWS y promoción

Siga exactamente `ACCIONES_MANUALES.md`: bootstrap de state, workspaces, rulesets, OIDC, runner privado y controllers. El push post-merge a `dev` ejecuta `build_dev_images` una sola vez y adjunta `promoted-images-<SHA>.json`; copie ese JSON en `PROMOTED_IMAGES_JSON` de `test` y `prod` al promocionar. El workflow manual **Construir imágenes inmutables de desarrollo** es solo recuperación controlada si el job dev falló antes de publicar; ECR inmutable impide sobrescribir el tag. Test y prod no recompilan.

## 6. Evidencia final

Actualice `docs/RESULTADOS_VERIFICACION.md` con fecha, comando, salida y estado. Capture únicamente la evidencia listada en `EVIDENCIAS_A_OBTENER.md`. El guion de sustentación es `DEMO_SUSTENTACION.md`.
