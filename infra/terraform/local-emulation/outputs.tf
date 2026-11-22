output "state_bucket" {
  value       = try(aws_s3_bucket.terraform_state[0].id, null)
  description = "Bucket del backend emulado; solo existe dentro de LocalStack."
}

output "workspace_table" {
  value       = try(aws_dynamodb_table.workspace_proof[0].name, null)
  description = "Tabla de evidencia del workspace local actual."
}
