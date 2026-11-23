# Esta raíz es una evidencia local limitada. No comparte state ni recursos con
# bootstrap-state/environments y no sustituye la arquitectura AWS prevista.
provider "aws" {
  region                      = var.region
  access_key                  = "local"
  secret_key                  = "local"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    dynamodb = var.endpoint
    iam      = var.endpoint
    s3       = var.endpoint
    sts      = var.endpoint
  }
}

# El workspace default únicamente bootstrappea el backend compartido local.
# Los ambientes académicos son exclusivamente dev, test y prod.
resource "aws_s3_bucket" "terraform_state" {
  count  = terraform.workspace == "default" ? 1 : 0
  bucket = var.state_bucket

  tags = {
    ManagedBy = "terraform-local-emulation"
    Scope     = "local-only"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  count  = terraform.workspace == "default" ? 1 : 0
  bucket = aws_s3_bucket.terraform_state[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  count                   = terraform.workspace == "default" ? 1 : 0
  bucket                  = aws_s3_bucket.terraform_state[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cada workspace de ambiente tiene su propia tabla; no se usa default para datos.
resource "aws_dynamodb_table" "workspace_proof" {
  count        = terraform.workspace == "default" ? 0 : 1
  name         = "aegisvolt-emulation-${terraform.workspace}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  attribute {
    name = "PK"
    type = "S"
  }

  tags = {
    Environment = terraform.workspace
    ManagedBy   = "terraform-local-emulation"
    Scope       = "local-only"
  }
}
