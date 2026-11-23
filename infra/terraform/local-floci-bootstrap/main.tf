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

# Bucket dedicado para logs: evita autorreferencia y mantiene el backend local
# aislado de cualquier cuenta o backend S3 de producción.
resource "aws_s3_bucket" "terraform_access_logs" {
  bucket = "${var.state_bucket_name}-access-logs"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.terraform_access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.terraform_access_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.terraform_access_logs.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.terraform_access_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

data "aws_iam_policy_document" "state_bucket_transport" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.terraform_state.arn, "${aws_s3_bucket.terraform_state.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state_bucket_transport" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.state_bucket_transport.json
}

data "aws_iam_policy_document" "access_logs" {
  statement {
    sid       = "AllowS3ServerAccessLogging"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.terraform_access_logs.arn}/terraform-state/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.terraform_state.arn]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.terraform_access_logs.arn, "${aws_s3_bucket.terraform_access_logs.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.terraform_access_logs.id
  policy = data.aws_iam_policy_document.access_logs.json
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.terraform_state.id
  target_bucket = aws_s3_bucket.terraform_access_logs.id
  target_prefix = "terraform-state/"
  depends_on    = [aws_s3_bucket_policy.access_logs]
}

module "ecr" {
  source = "../modules/ecr"
  tags   = local.tags
}
