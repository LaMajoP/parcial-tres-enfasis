output "state_bucket_name" { value = aws_s3_bucket.terraform_state.bucket }
output "backend_init_command" { value = "terraform -chdir=infra/terraform/environments init -reconfigure -backend-config=bucket=${aws_s3_bucket.terraform_state.bucket} -backend-config=region=${var.aws_region}" }
