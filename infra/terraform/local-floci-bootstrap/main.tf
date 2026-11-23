# Bootstrap exclusivamente local. Reutiliza el módulo ECR de producción y
# declara el mismo endurecimiento de bucket, pero conserva backend local para
# que los estados de laboratorio nunca se mezclen con el backend S3 real.
locals {
  tags = {
    Project     = "AegisVolt"
    ManagedBy   = "Terraform"
    Owner       = var.owner
    Scope       = "floci-local-bootstrap"
    Emulation   = "floci-local"
    Environment = "shared"
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
    sts = var.floci_endpoint
    iam = var.floci_endpoint
    s3  = var.floci_endpoint
    ecr = var.floci_endpoint
  }
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

module "ecr" {
  source = "../modules/ecr"
  tags   = local.tags
}
