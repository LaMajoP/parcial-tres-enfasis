output "state_bucket_name" { value = aws_s3_bucket.terraform_state.bucket }
output "backend_init_command" { value = "terraform -chdir=infra/terraform/environments init -reconfigure -backend-config=bucket=${aws_s3_bucket.terraform_state.bucket} -backend-config=region=${var.aws_region}" }
output "bootstrap_state_migration_command" { value = "terraform -chdir=infra/terraform/bootstrap-state init -migrate-state -input=false -backend-config=bucket=${aws_s3_bucket.terraform_state.bucket} -backend-config=region=${var.aws_region}" }
output "github_actions_oidc_provider_arn" { value = aws_iam_openid_connect_provider.github_actions.arn }
output "ecr_repositories" { value = module.ecr.repository_urls }
