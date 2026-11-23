output "state_bucket_name" { value = aws_s3_bucket.terraform_state.bucket }
output "ecr_repositories" { value = module.ecr.repository_urls }
