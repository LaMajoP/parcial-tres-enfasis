terraform {
  required_version = ">= 1.10.0"
  backend "s3" {
    key                  = "aegisvolt.tfstate"
    workspace_key_prefix = "env"
    encrypt              = true
    use_lockfile         = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
  default_tags { tags = local.tags }
}
