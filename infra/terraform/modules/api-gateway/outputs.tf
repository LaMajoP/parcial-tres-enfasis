output "private_api_id" { value = try(aws_api_gateway_rest_api.private[0].id, null) }
output "private_invoke_url" { value = try("https://${aws_api_gateway_rest_api.private[0].id}-${var.execute_api_vpce_id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}/graphql", null) }
data "aws_region" "current" {}
