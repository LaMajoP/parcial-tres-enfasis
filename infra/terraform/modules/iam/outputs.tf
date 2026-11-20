output "service_role_arns" { value = { for key, role in aws_iam_role.service : key => role.arn } }
