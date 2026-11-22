terraform {
  required_version = ">= 1.10.0"
  # El bucket aún no existe en la primera ejecución. Inicialice esa ejecución
  # con -backend=false y, tras crear el bucket, migre este state al backend
  # parcial con `terraform init -migrate-state -backend-config=...`.
  backend "s3" {
    key          = "bootstrap/aegisvolt.tfstate"
    encrypt      = true
    use_lockfile = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
