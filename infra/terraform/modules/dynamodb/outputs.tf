output "table_arns" { value = { for domain, table in aws_dynamodb_table.domain : domain => table.arn } }
output "table_names" { value = { for domain, table in aws_dynamodb_table.domain : domain => table.name } }
