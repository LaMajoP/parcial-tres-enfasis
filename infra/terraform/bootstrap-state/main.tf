resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name
  lifecycle {
    prevent_destroy = true
  }
  tags = {
    Project   = "AegisVolt"
    ManagedBy = "Terraform"
    Owner     = var.owner
    Purpose   = "terraform-state"
  }
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
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Los repositorios no pertenecen a un workspace: el mismo digest construido en
# dev debe promoverse a test y prod dentro de la misma cuenta AWS.
module "ecr" {
  source = "../modules/ecr"
  tags = {
    Project   = "AegisVolt"
    ManagedBy = "Terraform"
    Owner     = var.owner
    Scope     = "shared"
  }
}

# El IdP de GitHub también es único por cuenta. Los roles que lo usan son un
# prerrequisito IAM manual, porque sus permisos dependen de la cuenta y de las
# políticas organizacionales, pero todos referencian este único proveedor.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags = {
    Project   = "AegisVolt"
    ManagedBy = "Terraform"
    Owner     = var.owner
    Scope     = "shared"
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.terraform_state.arn, "${aws_s3_bucket.terraform_state.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } },
      { Sid = "AllowDeclaredStateOperators", Effect = "Allow", Principal = { AWS = tolist(var.allowed_principal_arns) }, Action = ["s3:GetBucketLocation", "s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:ListBucketVersions", "s3:GetBucketVersioning"], Resource = [aws_s3_bucket.terraform_state.arn, "${aws_s3_bucket.terraform_state.arn}/*"] }
    ]
  })
}
