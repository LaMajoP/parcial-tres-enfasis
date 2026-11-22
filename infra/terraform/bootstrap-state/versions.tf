terraform {
  required_version = ">= 1.10.0"
  # Este root inicia deliberadamente con backend local: es el responsable de
  # crear el bucket S3 que albergará su propio state. Tras el primer apply
  # autorizado, copie backend.s3.tf.example a backend.s3.tf (ignorado por Git)
  # y ejecute `terraform init -migrate-state` con bucket y región verificados.
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
