#!/usr/bin/env python3
"""Invariantes que terraform validate no puede inferir entre workspaces."""
from pathlib import Path
import sys


def read(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


errors: list[str] = []
bootstrap = read("infra/terraform/bootstrap-state/main.tf")
bootstrap_versions = read("infra/terraform/bootstrap-state/versions.tf")
bootstrap_backend_example = read("infra/terraform/bootstrap-state/backend.s3.tf.example")
environments = read("infra/terraform/environments/main.tf")
eks = read("infra/terraform/modules/eks/main.tf")
endpoints = read("infra/terraform/modules/vpc-endpoints/main.tf")
iam = read("infra/terraform/modules/iam/main.tf")
ecr = read("infra/terraform/modules/ecr/main.tf")
cloudwatch = read("infra/terraform/modules/cloudwatch/main.tf")
runtime_config = read("infra/kubernetes/base/configmap.yaml")
fluent_bit = read("infra/kubernetes/base/fluent-bit.yaml")
gitignore = read(".gitignore")
ci = read(".github/workflows/ci.yml")
deploy = read(".github/workflows/deploy.yml")

if 'module "ecr"' not in bootstrap or 'source = "../modules/ecr"' not in bootstrap:
    errors.append("Los repositorios ECR compartidos deben pertenecer al estado bootstrap, no a un workspace.")
if 'module "ecr"' in environments:
    errors.append("Un workspace no puede crear repositorios ECR globales duplicados.")
if 'aws_iam_openid_connect_provider" "github_actions' not in bootstrap:
    errors.append("El proveedor OIDC de GitHub debe declararse una sola vez en bootstrap.")
if 'bucket_key_enabled' in bootstrap:
    errors.append("S3 Bucket Key no debe combinarse con cifrado SSE-S3 AES256.")
if 'backend "s3"' in bootstrap_versions:
    errors.append("Bootstrap debe iniciar con backend local; el bucket S3 aún no existe en la primera ejecución.")
if 'backend "s3"' not in bootstrap_backend_example or 'bootstrap/aegisvolt.tfstate' not in bootstrap_backend_example or 'use_lockfile = true' not in bootstrap_backend_example:
    errors.append("El ejemplo de backend bootstrap debe migrar a S3 con prefijo dedicado y locking nativo.")
if 'infra/terraform/bootstrap-state/backend.s3.tf' not in gitignore:
    errors.append("El backend local creado tras bootstrap debe permanecer ignorado por Git.")
for required in ('aws_eks_access_entry" "deployer', 'aws_eks_access_policy_association" "deployer', 'API_AND_CONFIG_MAP'):
    if required not in eks:
        errors.append("EKS debe declarar acceso API explícito para el rol de despliegue privado.")
for service in ('"ec2"', '"elasticloadbalancing"', '"eks"', '"oidc-eks"'):
    if service not in endpoints:
        errors.append(f"La red privada requiere el endpoint de interfaz {service}.")
if '"${arn}/index/*"' not in iam:
    errors.append("El rol del gateway debe autorizar los ARN de índices DynamoDB.")
for component in ('"aws-for-fluent-bit"', '"argo-rollouts"', '"aws-load-balancer-controller"'):
    if component not in ecr:
        errors.append(f"ECR debe reservar un repositorio privado para {component} en nodos sin NAT.")
for log_group in ('"web"', '"aws-for-fluent-bit"'):
    if log_group not in cloudwatch:
        errors.append(f"CloudWatch debe crear el grupo que Fluent Bit deriva del label app: {log_group}.")
if '"fluent-bit"' in cloudwatch:
    errors.append("El grupo fluent-bit no coincide con el label app=aws-for-fluent-bit de Fluent Bit.")
if 'AWS_REGION: us-east-2' not in runtime_config:
    errors.append("Los manifiestos AWS deben usar la región objetivo us-east-2.")
if 'public.ecr.aws' in fluent_bit or 'aegisvolt/aws-for-fluent-bit:3.5.6' not in fluent_bit:
    errors.append("Fluent Bit debe referenciar la imagen privada sustituible, no un registry público.")
for required in ('AWS_DEPLOY_ROLE_ARN', 'EKS_ACCESS_PRINCIPAL_ARNS', 'TF_VAR_eks_access_principal_arns'):
    if required not in ci or required not in deploy:
        errors.append(f"CI y CD deben propagar {required} hacia Terraform.")
if 'vars.CD_ENABLED == \'true\'' not in deploy:
    errors.append("CD debe mantenerse bloqueado hasta CD_ENABLED=true.")
if 'PLATFORM_IMAGES_JSON' not in deploy:
    errors.append("CD debe requerir los digests privados de imágenes de plataforma.")
if 'workspace new' in ci:
    errors.append("Un PR no puede crear workspaces Terraform.")

if errors:
    print("VALIDACIÓN DE LAYOUT TERRAFORM FALLÓ", file=sys.stderr)
    print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
    sys.exit(1)
print("Layout Terraform válido: estado global separado, EKS privado y roles CI/CD alineados.")
