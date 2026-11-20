output "log_group_names" { value = { for service, group in aws_cloudwatch_log_group.service : service => group.name } }
