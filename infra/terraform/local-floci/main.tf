# Raíz exclusiva para Floci. Conserva los módulos de producción sin modificar
# sus providers/backends y usa workspaces locales independientes por ambiente.
locals {
  environment = terraform.workspace
  tags = {
    Project          = "AegisVolt"
    Environment      = local.environment
    ManagedBy        = "Terraform"
    Owner            = var.owner
    GitHubRepository = var.github_repository
    Emulation        = "floci-local"
  }
}

check "workspace_is_explicit" {
  assert {
    condition     = contains(["dev", "test", "prod"], local.environment)
    error_message = "Seleccione workspace dev, test o prod; default está prohibido."
  }
}

check "private_api_inputs_are_complete" {
  assert {
    condition     = !var.enable_private_api || (var.internal_nlb_arn != null && trimspace(var.internal_nlb_arn) != "" && var.internal_nlb_dns_name != null && trimspace(var.internal_nlb_dns_name) != "")
    error_message = "enable_private_api exige ARN y DNS no vacíos de un NLB interno ya verificado."
  }
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = "floci"
  secret_key                  = "floci"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
  s3_use_path_style           = true

  default_tags { tags = local.tags }

  endpoints {
    sts                  = var.floci_endpoint
    iam                  = var.floci_endpoint
    ec2                  = var.floci_endpoint
    eks                  = var.floci_endpoint
    ecr                  = var.floci_endpoint
    s3                   = var.floci_endpoint
    dynamodb             = var.floci_endpoint
    logs                 = var.floci_endpoint
    cloudwatch           = var.floci_endpoint
    elasticloadbalancing = var.floci_endpoint
    apigateway           = var.floci_endpoint
  }
}

data "aws_caller_identity" "current" {}

# En AWS este principal se suministra desde el entorno CI/CD y no se crea en la
# raíz de ambientes. Floci valida que un EKS Access Entry apunte a un rol
# existente, por lo que el laboratorio declara su equivalente local, sin
# permisos adjuntos ni credenciales reales. La política de acceso EKS del
# módulo sigue siendo quien concede el acceso al API del clúster.
resource "aws_iam_role" "local_deployer" {
  # El rol es global en la cuenta emulada. El workspace dev lo materializa una
  # vez; test y prod lo referencian por el ARN estático de floci.tfvars.
  count = terraform.workspace == "dev" ? 1 : 0
  name  = "aegisvolt-local-deployer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = merge(local.tags, { Scope = "floci-local-deployer" })
}

# Conserva el state de dev creado antes de que el rol se hiciera compartido.
moved {
  from = aws_iam_role.local_deployer
  to   = aws_iam_role.local_deployer[0]
}

module "network" {
  source      = "../modules/network"
  environment = local.environment
  vpc_cidr    = var.vpc_cidrs[local.environment]
  azs         = var.availability_zones
  tags        = local.tags
}

module "vpc_endpoints" {
  source                  = "../modules/vpc-endpoints"
  environment             = local.environment
  vpc_id                  = module.network.vpc_id
  vpc_cidr                = var.vpc_cidrs[local.environment]
  private_subnet_ids      = module.network.private_subnet_ids
  private_route_table_ids = module.network.private_route_table_ids
  tags                    = local.tags
}

module "dynamodb" {
  source                 = "../modules/dynamodb"
  environment            = local.environment
  tags                   = local.tags
  point_in_time_recovery = !var.lab_profile
}

module "eks" {
  source             = "../modules/eks"
  environment        = local.environment
  private_subnet_ids = module.network.private_subnet_ids
  # El ARN se mantiene estático para que el for_each interno del módulo se
  # conozca durante el plan; depends_on garantiza que el rol local exista antes
  # de que Floci valide CreateAccessEntry.
  access_principal_arns = var.eks_access_principal_arns
  # Floci conserva el permiso bootstrap como un valor de creación inmutable.
  # test fue creado por una ejecución incompleta con ese permiso activo; esta
  # variante lo conserva para reconciliar el state sin recrear su k3s.
  bootstrap_self_managed_addons               = false
  bootstrap_cluster_creator_admin_permissions = local.environment == "test"
  tags                                        = local.tags
  depends_on                                  = [module.vpc_endpoints, aws_iam_role.local_deployer]
}

module "iam" {
  source            = "../modules/iam"
  environment       = local.environment
  aws_region        = var.aws_region
  account_id        = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  table_arns        = module.dynamodb.table_arns
  tags              = local.tags
}

module "cloudwatch" {
  source             = "../modules/cloudwatch"
  environment        = local.environment
  tags               = local.tags
  log_retention_days = local.environment == "prod" ? 90 : 30
}

# Se conserva el módulo. En Floci queda explícitamente deshabilitado hasta que
# exista un NLB interno verificable; no se inventa un DNS ni se simula tráfico.
module "api_gateway" {
  source                = "../modules/api-gateway"
  environment           = local.environment
  execute_api_vpce_id   = module.vpc_endpoints.execute_api_vpce_id
  enabled               = var.enable_private_api
  internal_nlb_arn      = var.internal_nlb_arn
  internal_nlb_dns_name = var.internal_nlb_dns_name
  tags                  = local.tags
}
