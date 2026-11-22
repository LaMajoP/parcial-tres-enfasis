#!/usr/bin/env python3
"""Invariantes que terraform validate no puede inferir entre workspaces."""
from pathlib import Path
import sys


def read(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


errors: list[str] = []
bootstrap = read("infra/terraform/bootstrap-state/main.tf")
bootstrap_versions = read("infra/terraform/bootstrap-state/versions.tf")
environments = read("infra/terraform/environments/main.tf")
eks = read("infra/terraform/modules/eks/main.tf")
endpoints = read("infra/terraform/modules/vpc-endpoints/main.tf")
iam = read("infra/terraform/modules/iam/main.tf")
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
if 'backend "s3"' not in bootstrap_versions or 'bootstrap/aegisvolt.tfstate' not in bootstrap_versions:
    errors.append("El state bootstrap debe migrar a su prefijo S3 dedicado después de crear el bucket.")
for required in ('aws_eks_access_entry" "deployer', 'aws_eks_access_policy_association" "deployer', 'API_AND_CONFIG_MAP'):
    if required not in eks:
        errors.append("EKS debe declarar acceso API explícito para el rol de despliegue privado.")
for service in ('"ec2"', '"elasticloadbalancing"', '"eks"', '"oidc-eks"'):
    if service not in endpoints:
        errors.append(f"La red privada requiere el endpoint de interfaz {service}.")
if '"${arn}/index/*"' not in iam:
    errors.append("El rol del gateway debe autorizar los ARN de índices DynamoDB.")
for required in ('AWS_DEPLOY_ROLE_ARN', 'EKS_ACCESS_PRINCIPAL_ARNS', 'TF_VAR_eks_access_principal_arns'):
    if required not in ci or required not in deploy:
        errors.append(f"CI y CD deben propagar {required} hacia Terraform.")
if 'vars.CD_ENABLED == \'true\'' not in deploy:
    errors.append("CD debe mantenerse bloqueado hasta CD_ENABLED=true.")
if 'workspace new' in ci:
    errors.append("Un PR no puede crear workspaces Terraform.")

if errors:
    print("VALIDACIÓN DE LAYOUT TERRAFORM FALLÓ", file=sys.stderr)
    print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
    sys.exit(1)
print("Layout Terraform válido: estado global separado, EKS privado y roles CI/CD alineados.")
