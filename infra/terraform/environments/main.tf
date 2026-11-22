locals {
  environment = terraform.workspace
  tags = {
    Project          = "AegisVolt"
    Environment      = local.environment
    ManagedBy        = "Terraform"
    Owner            = var.owner
    GitHubRepository = var.github_repository
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
    condition = !var.enable_private_api || (
      var.internal_nlb_arn != null && trimspace(var.internal_nlb_arn) != "" &&
      var.internal_nlb_dns_name != null && trimspace(var.internal_nlb_dns_name) != ""
    )
    error_message = "enable_private_api exige ARN y DNS no vacíos de un NLB interno ya verificado."
  }
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
  source                = "../modules/eks"
  environment           = local.environment
  private_subnet_ids    = module.network.private_subnet_ids
  access_principal_arns = var.eks_access_principal_arns
  tags                  = local.tags
  # Sin NAT, cree primero los endpoints usados por nodos, IRSA y el runner.
  # Esto también evita que la lectura del emisor OIDC dependa de DNS público.
  depends_on = [module.vpc_endpoints]
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
data "aws_caller_identity" "current" {}
module "cloudwatch" {
  source             = "../modules/cloudwatch"
  environment        = local.environment
  tags               = local.tags
  log_retention_days = local.environment == "prod" ? 90 : 30
}
module "api_gateway" {
  source                = "../modules/api-gateway"
  environment           = local.environment
  execute_api_vpce_id   = module.vpc_endpoints.execute_api_vpce_id
  enabled               = var.enable_private_api
  internal_nlb_arn      = var.internal_nlb_arn
  internal_nlb_dns_name = var.internal_nlb_dns_name
  tags                  = local.tags
}
