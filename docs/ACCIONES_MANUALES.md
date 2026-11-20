# Acciones manuales en orden de dependencia

Estas son las únicas operaciones que requieren cuenta, aprobación o consola. Terraform crea recursos AegisVolt; no cree VPC, EKS, tablas ni endpoints manualmente.

## 1. Preparar cuenta y presupuesto

1. Inicie sesión con una cuenta AWS autorizada y elija una región que soporte EKS y dos AZ, por ejemplo `us-east-1`.
2. En [Billing Budgets](https://console.aws.amazon.com/billing/home#/budgets), cree un budget mensual con alertas al 50 %, 80 % y 100 %. Guarde la confirmación.
3. Configure identidad temporal, preferiblemente IAM Identity Center:

   ```bash
   aws configure sso
   aws sso login --profile aegisvolt-admin
   AWS_PROFILE=aegisvolt-admin aws sts get-caller-identity
   ```

   Evidencia esperada: Account y ARN del rol; no pegue secretos en el repositorio.

4. Pida al administrador un rol inicial de Terraform con mínimo privilegio organizacional y MFA/SSO. Esta identidad bootstrap no es una credencial embebida del proyecto.

## 2. Crear backend de estado (una vez por cuenta/región)

1. Copie el ejemplo sin versionarlo: `cp infra/terraform/bootstrap-state/terraform.tfvars.example /tmp/aegisvolt-bootstrap.tfvars`.
2. Reemplace el bucket por uno único, el ARN del rol operador y owner.
3. Ejecute y revise el plan:

   ```bash
   AWS_PROFILE=aegisvolt-admin terraform -chdir=infra/terraform/bootstrap-state init
   AWS_PROFILE=aegisvolt-admin terraform -chdir=infra/terraform/bootstrap-state plan -var-file=/tmp/aegisvolt-bootstrap.tfvars
   AWS_PROFILE=aegisvolt-admin terraform -chdir=infra/terraform/bootstrap-state apply -var-file=/tmp/aegisvolt-bootstrap.tfvars
   ```

4. Guarde el output `state_bucket_name`. Compruebe bloqueo público, cifrado y versionamiento:

   ```bash
   aws s3api get-bucket-versioning --bucket REEMPLAZAR_BUCKET
   aws s3api get-public-access-block --bucket REEMPLAZAR_BUCKET
   ```

## 3. Inicializar los tres estados

1. Copie `infra/terraform/environments/terraform.tfvars.example` a `infra/terraform/environments/terraform.tfvars`, que está ignorado por Git. Complete valores reales.
2. Inicialice el backend y cree/seleccione workspaces:

   ```bash
   scripts/terraform-init.sh REEMPLAZAR_BUCKET us-east-1
   terraform -chdir=infra/terraform/environments workspace list
   ```

   Evidencia: `dev`, `test`, `prod`; no use `default`.
3. Para cada ambiente, seleccione su workspace y **revise** plan. No ejecute apply sin presupuesto/aprobación:

   ```bash
   terraform -chdir=infra/terraform/environments workspace select dev
   terraform -chdir=infra/terraform/environments plan -var-file=terraform.tfvars
   ```

4. Tras un apply aprobado, compruebe claves y versiones. Con `workspace_key_prefix=env`, las claves no-default son `env:/dev/aegisvolt.tfstate`, etc.

   ```bash
   aws s3api list-object-versions --bucket REEMPLAZAR_BUCKET --prefix 'env:/dev/aegisvolt.tfstate'
   aws s3api get-object --bucket REEMPLAZAR_BUCKET --key 'env:/dev/aegisvolt.tfstate' --version-id REEMPLAZAR_VERSION /tmp/aegisvolt-state-inspection.json
   ```

   Para recuperación: guarde copia del state actual, revise el state histórico en `/tmp`, restaure por procedimiento aprobado/versionado S3 y corra `terraform plan` antes de cualquier apply. Nunca edite JSON state a mano.

## 4. GitHub y gobernanza

1. Cree el repositorio privado en [GitHub](https://github.com/new), agregue remoto y publique el código tras revisar que `.env`/`*.tfvars` no viajen.
2. Cree ramas desde `dev` exclusivamente:

   ```bash
   scripts/create-branches.sh
   git push -u origin dev test prod
   ```

3. Con un token `admin:repo_hook`/permisos de administración y GitHub CLI autenticada, ejecute:

   ```bash
   gh auth login
   scripts/github-rulesets.sh ORGANIZACION/REPOSITORIO
   ```

   En Settings → Rules → Rulesets confirme PR obligatorio, no force-push, no borrado y checks `lint-build`, `unit-tests`, `integration-tests`, `e2e-tests`, `terraform-plan`. Pruebe el servidor remoto (en una rama descartable): `git push --force origin HEAD:dev`; la evidencia esperada es rechazo del servidor.
4. En Settings → Environments cree `dev`, `test`, `prod`. En `prod` configure required reviewers antes del job de despliegue. Por ambiente agregue variables `AWS_ROLE_ARN`, `AWS_REGION`, `TF_STATE_BUCKET`, `TF_OWNER`, `VPC_CIDRS_JSON`, `AVAILABILITY_ZONES_JSON`, `EKS_CONTEXT`, `PROMOTED_IMAGE_DIGEST`.
5. Configure el rol OIDC de GitHub en la cuenta con issuer `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com` y trust restringido a `repo:ORGANIZACION/REPOSITORIO:ref:refs/heads/<ambiente>`. El rol debe tener solo permisos necesarios para el plan/apply de ese ambiente y acceso al prefijo state correspondiente. Compruebe el claim en una ejecución de Actions; no use access keys persistentes.

## 5. Desplegar AWS y entrada privada

1. Después del plan aprobado, ejecute el apply en cada workspace según la promoción permitida. Terraform crea VPC, endpoints, EKS, tablas, roles de servicio, ECR y grupos CloudWatch.
2. Instale AWS Load Balancer Controller y Argo Rollouts con versiones compatibles con el EKS elegido, usando roles IRSA aprobados. Esto es un prerequisito de controller, no un recurso creado manualmente por AegisVolt.
3. Publique las imágenes por digest, aplique el overlay del ambiente y espere probes:

   ```bash
   kubectl apply -k infra/kubernetes/overlays/test
   kubectl -n aegisvolt-test get pods,svc,networkpolicy
   kubectl -n aegisvolt-test describe pod REEMPLAZAR_POD
   ```

4. Cuando el Service `graphql-gateway` cree el NLB interno, copie ARN y DNS verificables como variables de Terraform, ponga `enable_private_api=true`, revise plan y aplique. El módulo crea REST API privada y VPC Link. Compruebe:

   ```bash
   aws apigateway get-rest-apis
   aws ec2 describe-vpc-endpoints --filters Name=vpc-endpoint-type,Values=Interface
   kubectl -n aegisvolt-test get svc graphql-gateway -o wide
   ```

5. Desde una red conectada (VPN/host dentro VPC), resuelva e invoque la URL privada. Desde Internet debe fallar; esa es la conducta esperada. Confirme que `SourceVpce` de la llamada coincide con el VPCE configurado.

## 6. CloudWatch, Prefect y evidencia

1. Abra CloudWatch → Logs Insights y use las consultas de `observability/cloudwatch/logs-insights.queries.md` sobre `/aegisvolt/<env>/*`.
2. Para local, abra `http://localhost:4200`; cree un work pool `aegisvolt-local`, instale `observability/prefect/requirements.txt`, despliegue `prefect.yaml` y ejecute un run. Para AWS use una identidad solo lectura a la tabla SAGA correspondiente y URLs privadas del gateway.
3. Capture solo evidencia real indicada en [EVIDENCIAS_A_OBTENER.md](EVIDENCIAS_A_OBTENER.md).
