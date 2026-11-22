# Primer plan real de Terraform en AWS

Este procedimiento prepara AWS sin introducir credenciales permanentes en GitHub ni en el repositorio. Los comandos `apply` se muestran solo como pasos posteriores sujetos a aprobación de costo; no forman parte de la validación local.

## 1. Qué administra cada state

- `bootstrap-state` es global por cuenta/región: bucket S3 de state con versionado, cifrado SSE-S3, bloqueo público, ownership enforced, repositorios ECR compartidos y el proveedor OIDC de GitHub. ECR no puede estar en `dev`, `test` y `prod` porque un mismo repositorio/digest debe promoverse entre ambientes.
- `environments` usa los workspaces `dev`, `test` y `prod`. Cada uno crea VPC, subredes, endpoints, EKS, tablas DynamoDB, roles IRSA, CloudWatch y, en una segunda fase, API Gateway privada.
- El state remoto queda en `env:/<workspace>/aegisvolt.tfstate`. Nunca use `default`.

No ejecute `terraform apply`, `destroy` ni habilite los gates de GitHub hasta completar los pasos externos siguientes.

## 2. Prerrequisitos y presupuesto

1. Seleccione una región y dos AZ reales. El ejemplo usa `us-east-1a` y `us-east-1b`.
2. Cree un AWS Budget y alertas antes de aprovisionar EKS, endpoints o balanceadores.
3. Configure una sesión temporal de IAM Identity Center para un operador inicial; no cree access keys permanentes.
4. Revise [COSTOS_AWS.md](COSTOS_AWS.md) y confirme quién autoriza el primer apply.

La versión EKS declarada es `1.35`; se eligió para evitar crear un clúster nuevo sobre la versión `1.31`, que ya está en soporte extendido al momento de esta auditoría. Consulte el ciclo antes de elegir otra versión. [AWS EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)

## 3. Fase A: bootstrap global (una sola vez)

1. Copie el ejemplo fuera de Git y reemplace únicamente los marcadores:

   ```bash
   cp infra/terraform/bootstrap-state/terraform.tfvars.example /tmp/aegisvolt-bootstrap.tfvars
   ```

2. En `allowed_principal_arns`, incluya inicialmente el rol temporal del operador. Después de crear los roles OIDC del paso 4, añada también los tres roles de plan y los tres de despliegue para que puedan leer/escribir el state y su archivo `.tflock`.

3. Tras la aprobación de costo, ejecute en una estación administrativa autenticada:

   ```bash
   terraform -chdir=infra/terraform/bootstrap-state init -backend=false -input=false
   terraform -chdir=infra/terraform/bootstrap-state plan -var-file=/tmp/aegisvolt-bootstrap.tfvars
   # Solo con autorización explícita:
   terraform -chdir=infra/terraform/bootstrap-state apply -var-file=/tmp/aegisvolt-bootstrap.tfvars
   terraform -chdir=infra/terraform/bootstrap-state init -migrate-state -input=false \
     -backend-config="bucket=NOMBRE_BUCKET" -backend-config="region=REGION"
   terraform -chdir=infra/terraform/bootstrap-state output github_actions_oidc_provider_arn
   ```

La primera ejecución usa state local porque es precisamente la que crea el
bucket. El último `init -migrate-state` traslada ese state al prefijo
`bootstrap/aegisvolt.tfstate` y activa el bloqueo S3 nativo; no descarte el
state local ni acepte prompts de migración sin revisar el destino.

4. Si `token.actions.githubusercontent.com` ya existe como proveedor OIDC en la cuenta, impórtelo en vez de crear un duplicado:

   ```bash
   terraform -chdir=infra/terraform/bootstrap-state import \
     aws_iam_openid_connect_provider.github_actions \
     arn:aws:iam::CUENTA:oidc-provider/token.actions.githubusercontent.com
   ```

`prevent_destroy` protege el bucket de state. No lo retire para apagar un ambiente: primero gestione los recursos del workspace, mantenga las versiones de state y solo trate el bucket al cerrar definitivamente la cuenta/proyecto.

## 4. Roles OIDC separados: plan de PR y despliegue

Cada Environment necesita dos roles distintos.

| Rol | Uso | Permisos mínimos esperados |
|---|---|---|
| `AWS_ROLE_ARN` | `terraform-plan` de PR interno | Lectura de los servicios declarados, `sts:GetCallerIdentity` y acceso S3 al state/lockfile. No `apply`, ECR push ni acceso Kubernetes. |
| `AWS_DEPLOY_ROLE_ARN` | CD tras push protegido | Permisos de Terraform para los recursos declarados, acceso al state, `eks:DescribeCluster`, EKS access entries y despliegue Kubernetes. Debe someterse a un permissions boundary/política aprobada por la cuenta. |

El proveedor OIDC es `https://token.actions.githubusercontent.com` con audiencia `sts.amazonaws.com`. No use comodines de repositorio.

Los jobs de este repositorio declaran un GitHub Environment. Por ello el `sub` toma la forma `repo:OWNER/REPO:environment:ENV`; no la forma de rama. Para cada ambiente cree dos trusts con `OWNER/REPO` y `ENV` reales.

Plan de PR interno (solo lectura):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::CUENTA:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:environment:ENV"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:ref": "refs/pull/*/merge"
      }
    }
  }]
}
```

Despliegue tras merge (escritura):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::CUENTA:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:environment:ENV",
        "token.actions.githubusercontent.com:ref": "refs/heads/ENV"
      }
    }
  }]
}
```

La diferencia es intencional: en PR el `ref` es una merge ref, y tras `push` es `refs/heads/<ambiente>`. El workflow excluye forks, pero el rol de plan sigue siendo solo lectura. Restrinja además los branches permitidos y los reviewers en cada GitHub Environment. AWS recomienda condicionar el `sub` y, cuando un Environment elimina la rama del sujeto, restringir también el `ref`. [AWS IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-reference-policy-checks.html) [GitHub OIDC](https://docs.github.com/en/actions/reference/security/oidc)

Si el repositorio se renombra, se transfiere o activa el formato OIDC inmutable, inspeccione el token en un PR privado y actualice el `sub`: GitHub puede incluir IDs inmutables de owner y repositorio.

## 5. Inicializar el backend y los workspaces

Después del bootstrap y de actualizar la política S3 con los roles, prepare un `terraform.tfvars` local no versionado:

```bash
cp infra/terraform/environments/terraform.tfvars.example \
  infra/terraform/environments/terraform.tfvars
```

Complete los datos reales, incluido `eks_access_principal_arns` con el ARN del rol de despliegue del Environment. Luego:

```bash
bash scripts/terraform-init.sh NOMBRE_BUCKET ESTADO_REGION
terraform -chdir=infra/terraform/environments workspace list
terraform -chdir=infra/terraform/environments workspace select dev
terraform -chdir=infra/terraform/environments plan -input=false -lock-timeout=5m -var-file=terraform.tfvars
```

El primer apply autorizado debe ejecutarlo un operador temporal desde una ubicación con acceso a las APIs AWS. El runner privado de EKS todavía no existe antes de crear la VPC y el clúster; no intente resolver ese ciclo habilitando CD prematuramente.

## 6. GitHub Environments y variables

En GitHub cree `dev`, `test` y `prod`. Limite branches desplegables a su ambiente; exija aprobación para `prod`. En cada Environment configure variables no secretas:

```text
AWS_ROLE_ARN                 # rol read-only para terraform-plan
AWS_DEPLOY_ROLE_ARN          # rol de escritura para CD y kubectl
AWS_REGION
TF_STATE_BUCKET
TF_OWNER
VPC_CIDRS_JSON               # mapa JSON con dev/test/prod
AVAILABILITY_ZONES_JSON      # lista JSON de al menos dos AZ
EKS_ACCESS_PRINCIPAL_ARNS    # lista JSON; incluye AWS_DEPLOY_ROLE_ARN
ENABLE_PRIVATE_API           # false inicialmente; true solo tras verificar el NLB
INTERNAL_NLB_ARN             # vacío mientras ENABLE_PRIVATE_API=false
INTERNAL_NLB_DNS_NAME        # vacío mientras ENABLE_PRIVATE_API=false
PROMOTED_IMAGES_JSON         # test/prod: cinco referencias @sha256 aprobadas
```

Mantenga las variables de repositorio siguientes ausentes o distintas de `true` durante esta preparación:

```text
TF_PLAN_ENABLED
CD_ENABLED
```

Después de comprobar roles, state, workspaces y Environments, habilite primero `TF_PLAN_ENABLED=true` y abra un PR interno permitido. Confirme que el artefacto `terraform-plan-<ambiente>` procede del workspace destino. `CD_ENABLED` se habilita solo después de aprobar el primer apply y de registrar un runner privado.

## 7. Red privada y segunda fase de API

El perfil no usa NAT. Además de S3/DynamoDB, declara endpoints para ECR, STS, CloudWatch Logs, EC2, EKS, Elastic Load Balancing, execute-api y `oidc-eks`. Esto permite nodos privados, IRSA y el controlador de balanceadores sin salida pública; cada endpoint de interfaz añade cargos. AWS enumera ECR, ELB, CloudWatch, STS y S3 como dependencias típicas de un clúster privado. [AWS EKS](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html)

1. Primer apply aprobado: deje `ENABLE_PRIVATE_API=false`.
2. Desde red privada, instale AWS Load Balancer Controller con su rol IRSA mínimo y despliegue los manifiestos; espere el NLB interno `graphql-gateway-stable`.
3. Si no hay NAT, refleje previamente las imágenes públicas de Fluent Bit, AWS Load Balancer Controller y Argo Rollouts hacia ECR privado, o autorice una ruta de salida controlada para el bootstrap. Ninguna imagen `public.ecr.aws`, Docker Hub o GHCR debe suponerse accesible desde nodos sin Internet.
4. Copie ARN/DNS verificados del NLB a las variables del Environment, ponga `ENABLE_PRIVATE_API=true`, ejecute un nuevo plan y revíselo antes del segundo apply autorizado.

## 8. Runner privado y verificación final

Registre el runner después de que exista la VPC/EKS, dentro de la VPC, una red conectada o VPN. Debe tener Docker, Node 24, Terraform, AWS CLI, `kubectl`, `kustomize`, `jq` y conectividad DNS/TLS a los endpoints privados y al API privado de EKS. El endpoint EKS de PrivateLink permite las APIs de administración de EKS, no sustituye el endpoint Kubernetes privado. [AWS EKS](https://docs.aws.amazon.com/eks/latest/userguide/vpc-interface-endpoints.html)

Antes de habilitar CD, compruebe:

```bash
aws sts get-caller-identity
terraform -chdir=infra/terraform/environments workspace show
aws eks describe-cluster --name aegisvolt-dev --region REGION
aws eks update-kubeconfig --name aegisvolt-dev --region REGION
kubectl auth can-i '*' '*' --all-namespaces
```

No active `CD_ENABLED=true` si cualquiera falla. El primer despliegue debe demostrar la creación de roles de acceso EKS, el rollout de Argo y los cinco digests inmutables antes de promover a `test`.
