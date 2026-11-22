# Orden de ejecución final y reproducible

Siga estas etapas en orden. Pare ante un fallo: no promueva artefactos ni ejecute Terraform apply para ocultarlo.

## 1. Cerrar dependencias locales

1. Compruebe `node --version` (24.x), `docker version` y `docker compose version`.
2. El repositorio ya contiene `package-lock.json`; instale exactamente las dependencias bloqueadas:

   ```bash
   npm ci --no-audit --no-fund
   ```

3. Use solo `npm ci`; no sustituya CI/Docker por `npm install`.

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

Resultado esperado: todas finalizan con código 0. La configuración de etiquetas propias para actionlint está versionada en `.github/actionlint.yaml`; la comprobación reproducible sin instalarlo en la máquina es:

```bash
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest -no-color
```

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
npm run kind:down
npm run kind:up
kubectl -n aegisvolt-dev get pods,svc,rollouts,networkpolicy
kubectl -n aegisvolt-dev wait --for=condition=Healthy rollout/graphql-gateway --timeout=5m
kubectl -n aegisvolt-dev wait --for=condition=Available rollout/graphql-gateway --timeout=5m
```

`kind:up` reconstruye el inicializador y ejecuta una semilla condicional de DynamoDB Local en cada arranque. No borra el volumen `aegisvolt_dynamodb-data`: conserva operaciones existentes y recrea solo las entidades demo que falten. El script valida el Rollout por las condiciones del CRD con `kubectl wait`; el plugin opcional `kubectl argo` no es necesario.

Kind valida manifiestos, imágenes, probes y el controlador Argo. No puede demostrar ALB weighted routing, VPCE, API Gateway privada ni CloudWatch; esos puntos pertenecen a la fase AWS.

## 5. GitHub, AWS y promoción

1. Siga exactamente `ACCIONES_MANUALES.md` y [TERRAFORM_AWS_PRIMER.md](TERRAFORM_AWS_PRIMER.md): cree las referencias remotas de `dev`, `test` y `prod` una sola vez desde `main`, aplique los rulesets previamente revisados, y cree los tres Environments con los roles OIDC separados de plan y despliegue. No publique las ramas ni aplique rulesets sin la autorización administrativa correspondiente.
2. Un PR solo puede seguir `feature/* → dev`, `dev → test` o `test → prod`. CI ejecuta lint/build/schema, unitarias, integración, resiliencia, E2E, build local de las cinco imágenes y validaciones Terraform/Kubernetes. Mantenga `TF_PLAN_ENABLED` ausente hasta configurar OIDC, backend, workspace y las seis variables del Environment del destino. Al fijarla a `true`, el job declara ese Environment, valida los valores reales y ejecuta el plan; antes de ello queda `skipped`, sin simularlo.
3. Mantenga `CD_ENABLED` ausente o distinto de `true` hasta completar backend, OIDC, runner privado, Environments y aprobaciones. Así, un push no puede llegar a `terraform apply` ni publicar en ECR.
4. Solo después de habilitar explícitamente esa variable, el merge a `dev` ejecuta `build_dev_images` una sola vez y adjunta `promoted-images-<SHA>.json`. Copie ese mismo JSON de digests a `PROMOTED_IMAGES_JSON` de `test` y `prod`; esos ambientes no recompilan. El workflow manual **Construir imágenes inmutables de desarrollo** es únicamente recuperación autorizada cuando el build de dev no publicó nada.

## 6. Evidencia final

Actualice `docs/RESULTADOS_VERIFICACION.md` con fecha, comando, salida y estado. Capture únicamente la evidencia listada en `EVIDENCIAS_A_OBTENER.md`. El guion de sustentación es `DEMO_SUSTENTACION.md`.
