# Acciones manuales, en orden de dependencia

Este manual contiene solo accesos, aprobaciones o acciones externas. No cree manualmente VPC, EKS, tablas DynamoDB, endpoints, API Gateway ni grupos CloudWatch: Terraform los declara. No ejecute `apply` o destrucción sin presupuesto/aprobación.

## 1. Recuperar ejecución local reproducible

1. Desde la raíz, instale exactamente el lockfile ya versionado:

   ```bash
   npm ci --no-audit --no-fund
   ```

   Éxito esperado: `npm ci` termina en código 0. No publique `node_modules` ni sustituya este paso por `npm install`.

2. Verifique Docker con un usuario que pueda abrir `/var/run/docker.sock`:

   ```bash
   docker version
   docker compose up --build -d
   npm run seed
   npm run test:integration
   npm run test:e2e
   docker compose down
   ```

   Éxito esperado: gateway y tres servicios `healthy`, pruebas verdes. Si Docker responde permiso denegado, resuelva la pertenencia al grupo/servicio con el administrador local; no use privilegios amplios en scripts del repositorio.

## 2. Preparar AWS y presupuesto

La secuencia completa de bootstrap, roles OIDC, workspaces, runner privado y primer plan está en [TERRAFORM_AWS_PRIMER.md](TERRAFORM_AWS_PRIMER.md). Este documento conserva las acciones externas transversales.

1. Elija región con EKS y al menos dos AZ (por ejemplo `us-east-1`) y cree presupuesto/alertas en [AWS Billing Budgets](https://console.aws.amazon.com/billing/home#/budgets) al 50 %, 80 % y 100 %.
2. Configure una identidad temporal con IAM Identity Center:

   ```bash
   aws configure sso
   aws sso login --profile aegisvolt-admin
   AWS_PROFILE=aegisvolt-admin aws sts get-caller-identity
   ```

3. Pida un rol Terraform de mínimo privilegio, MFA/SSO y permiso para los servicios declarados. Guarde ARN/account id fuera del repo; no cree access keys persistentes.

## 3. Bootstrap remoto de state (una vez)

1. Copie el ejemplo fuera de Git y complete bucket único, rol operador y owner:

   ```bash
   cp infra/terraform/bootstrap-state/terraform.tfvars.example /tmp/aegisvolt-bootstrap.tfvars
   ```

2. Revise y, solo con aprobación explícita de costo, aplique:

   ```bash
   AWS_PROFILE=aegisvolt-admin terraform -chdir=infra/terraform/bootstrap-state init
   AWS_PROFILE=aegisvolt-admin terraform -chdir=infra/terraform/bootstrap-state plan -var-file=/tmp/aegisvolt-bootstrap.tfvars
   AWS_PROFILE=aegisvolt-admin terraform -chdir=infra/terraform/bootstrap-state apply -var-file=/tmp/aegisvolt-bootstrap.tfvars
   ```

3. Compruebe versión y acceso público bloqueado:

   ```bash
   aws s3api get-bucket-versioning --bucket REEMPLAZAR_BUCKET
   aws s3api get-public-access-block --bucket REEMPLAZAR_BUCKET
   ```

## 4. Crear tres estados aislados

1. Prepare `infra/terraform/environments/terraform.tfvars` desde el ejemplo (está ignorado). Después:

   ```bash
   bash scripts/terraform-init.sh REEMPLAZAR_BUCKET us-east-1
   terraform -chdir=infra/terraform/environments workspace list
   ```

   Éxito esperado: `dev`, `test`, `prod`; no use `default`.

2. Revise el plan sin aplicar para cada ambiente:

   ```bash
   terraform -chdir=infra/terraform/environments workspace select dev
   terraform -chdir=infra/terraform/environments plan -var-file=terraform.tfvars
   ```

3. Tras apply autorizado, demuestre el historial y no edite state manualmente:

   ```bash
   aws s3api list-object-versions --bucket REEMPLAZAR_BUCKET --prefix 'env:/dev/aegisvolt.tfstate'
   aws s3api get-object --bucket REEMPLAZAR_BUCKET --key 'env:/dev/aegisvolt.tfstate' --version-id REEMPLAZAR_VERSION /tmp/aegisvolt-state-inspection.json
   ```

   Para recuperación, archive el state actual, inspeccione la versión en `/tmp`, acuerde el rollback y ejecute `terraform plan` antes de cualquier restauración aprobada.

## 5. GitHub: ramas, rulesets y Environments

El remoto ya está configurado; no cree otro repositorio. Primero confirme el estado remoto y prepare solo las referencias locales:

```bash
git ls-remote --heads origin
bash scripts/create-branches.sh
git branch -vv
```

El script nunca publica, no sobrescribe ramas y se detiene si ya encuentra una rama remota. No cree `dev`, `test` o `prod` remotamente hasta que un administrador haya revisado los payloads de rulesets y `CD_ENABLED` siga ausente o distinto de `true`.

`scripts/github-rulesets.sh` usa la API REST con `curl` y Python; no requiere GitHub CLI. Consulte primero el estado y los JSON exactos sin mutar GitHub:

```bash
bash scripts/github-rulesets.sh LaMajoP/parcial-tres-enfasis
```

Con autorización administrativa explícita y un token temporal fine-grained con **Administration: write**, cree únicamente los rulesets ausentes:

```bash
GITHUB_TOKEN=... bash scripts/github-rulesets.sh --apply LaMajoP/parcial-tres-enfasis
```

El script rechaza sobrescribir un ruleset existente. Los tres rulesets propuestos exigen PR, review, resolución de hilos, no-force-push, no-borrado y los checks `promotion-policy`, `lockfile`, `lint-build`, `unit-tests`, `integration-tests`, `resilience-tests`, `e2e-tests`, `image-build`, `terraform-offline` y `terraform-plan`.

La primera creación remota de las tres ramas requiere una decisión de un administrador: no existe una PR hacia una rama que todavía no existe. Debe crear las referencias desde `main` una sola vez por UI/API administrativa auditada, sin force-push ni contenido adicional; después los rulesets bloquean el push directo y toda promoción seguirá PR. No pruebe las protecciones con un force-push real.

En **Settings → Environments**, cree `dev`, `test`, `prod`; configure reviewers obligatorios en `prod`. Por Environment declare variables no secretas:

- `AWS_ROLE_ARN` (solo lectura para plan), `AWS_DEPLOY_ROLE_ARN` (CD), `AWS_REGION`, `TF_STATE_BUCKET`, `TF_OWNER`
- `VPC_CIDRS_JSON`, `AVAILABILITY_ZONES_JSON`, `EKS_ACCESS_PRINCIPAL_ARNS`
- `ENABLE_PRIVATE_API`, `INTERNAL_NLB_ARN`, `INTERNAL_NLB_DNS_NAME`
- `PROMOTED_IMAGES_JSON` (objeto con cinco referencias ECR `@sha256`; nunca tags)

Configure trust OIDC con issuer `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com` y dos roles por Environment: uno de lectura para PR con merge ref y uno de despliegue restringido a `refs/heads/<ambiente>`. Los JSON de trust, la diferencia entre PR/push y los permisos requeridos están en [TERRAFORM_AWS_PRIMER.md](TERRAFORM_AWS_PRIMER.md); no use el mismo rol de escritura en un PR.

Mantenga ausente la variable de repositorio `CD_ENABLED` (o en un valor distinto de `true`) durante la preparación. El workflow CD queda `skipped` y no puede llegar a `terraform apply` ni publicar en ECR hasta que un administrador la establezca explícitamente en `true` después de completar OIDC, backend, runner y aprobaciones.

Mantenga también ausente `TF_PLAN_ENABLED` hasta que los seis valores del Environment estén completos y el backend/workspace ya exista. Esta es una variable de **repositorio** (no un secreto): permite que el job de plan quede `skipped` sin intentar AWS mientras se prepara la cuenta. Al fijarla explícitamente a `true`, el job declara el Environment, comprueba cada variable y solo entonces solicita OIDC y ejecuta el plan real; una configuración incompleta falla de forma explícita, no se convierte en éxito simulado.

## 6. Runner privado y controllers EKS

Antes de permitir el CD, registre un runner GitHub autohospedado etiquetado `self-hosted`, `linux`, `aegisvolt-private` dentro de la VPC o conectado por VPN. Instale Node 24, Docker, AWS CLI, Terraform, kubectl, el binario `kustomize` y `jq`. El endpoint EKS es privado: un hosted runner público no es válido. El despliegue espera las condiciones del CRD Rollout con `kubectl`; no requiere el plugin cliente de Argo.

Después del apply autorizado instale, con sus roles IAM mínimos, AWS Load Balancer Controller y Argo Rollouts compatibles con la versión EKS. Compruebe:

```bash
kubectl -n kube-system get deployment aws-load-balancer-controller
kubectl -n argo-rollouts get deployment argo-rollouts
```

El CD anotará los ServiceAccounts con los roles Terraform por IRSA y aplicará los digests. No pegue ARNs en los YAML.

## 7. Construir una vez y promover

1. Solo después de habilitar `CD_ENABLED=true` y aprobar infraestructura de `dev`, el job `build_dev_images` construye y publica una vez, tras `infrastructure`, y adjunta `promoted-images-<SHA>.json`. Si falló antes de publicar, use **Actions → Construir imágenes inmutables de desarrollo → Run workflow** con ese SHA de dev; no use el workflow manual para recompilar un tag ya existente.
2. Descargue `promoted-images-<SHA>/promoted-images.json`. Revise que contenga exactamente `graphql-gateway`, `station-reservation`, `billing-wallet`, `energy-dispatch`, `web`, todos con `@sha256`.
3. Copie ese JSON exacto a `PROMOTED_IMAGES_JSON` de **test** y luego **prod** al avanzar el mismo artefacto. El CD de dev usa el output del build; el de test/prod se bloquea si falta JSON o contiene tags.
4. Promueva solo por PR `feature/* → dev`, `dev → test`, `test → prod`; no recompila test/prod.

## 8. Red privada, observabilidad y evidencia

Una vez EKS/ALB estén listos, espere el Service `graphql-gateway-stable` de tipo `LoadBalancer`: AWS Load Balancer Controller creará el **NLB interno**. Entregue su ARN/DNS verificable al `tfvars`, habilite `enable_private_api=true`, revise plan y aplique autorizado. Desde VPN/host interno:

```bash
aws ec2 describe-vpc-endpoints --filters Name=vpc-endpoint-type,Values=Interface
kubectl -n aegisvolt-test get ingress,svc,rollout,analysisrun
kubectl -n aegisvolt-test get svc graphql-gateway-stable -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl -n aegisvolt-test argo rollouts get rollout graphql-gateway
```

Pruebe que la API privada se invoca desde el VPCE correcto y falla desde Internet. En CloudWatch → Logs Insights seleccione `/aegisvolt/<env>/*` y ejecute las consultas de `observability/cloudwatch/logs-insights.queries.md`. Para Prefect local abra `http://localhost:4200`, cree pool `aegisvolt-local`, instale `observability/prefect/requirements.txt`, despliegue `prefect.yaml` y lance un run read-only.

Capture únicamente las evidencias de `EVIDENCIAS_A_OBTENER.md`; actualice resultados con salida verdadera.
