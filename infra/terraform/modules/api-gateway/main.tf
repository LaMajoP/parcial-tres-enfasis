locals { create = var.enabled && var.internal_nlb_arn != null && var.internal_nlb_dns_name != null }
resource "aws_api_gateway_vpc_link" "graphql" {
  count       = local.create ? 1 : 0
  name        = "aegisvolt-${var.environment}-graphql-private-link"
  target_arns = [var.internal_nlb_arn]
  tags        = var.tags
}
resource "aws_api_gateway_rest_api" "private" {
  count = local.create ? 1 : 0
  name  = "aegisvolt-${var.environment}-private-graphql"
  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [var.execute_api_vpce_id]
  }
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Deny", Principal = "*", Action = "execute-api:Invoke", Resource = "execute-api:/*", Condition = { StringNotEquals = { "aws:SourceVpce" = var.execute_api_vpce_id } } },
    { Effect = "Allow", Principal = "*", Action = "execute-api:Invoke", Resource = "execute-api:/*" }
  ] })
  tags = var.tags
}
resource "aws_api_gateway_resource" "graphql" {
  count       = local.create ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.private[0].id
  parent_id   = aws_api_gateway_rest_api.private[0].root_resource_id
  path_part   = "graphql"
}
resource "aws_api_gateway_method" "graphql_post" {
  count         = local.create ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.private[0].id
  resource_id   = aws_api_gateway_resource.graphql[0].id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "graphql" {
  count                   = local.create ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.private[0].id
  resource_id             = aws_api_gateway_resource.graphql[0].id
  http_method             = aws_api_gateway_method.graphql_post[0].http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.graphql[0].id
  uri                     = "http://${var.internal_nlb_dns_name}/graphql"
}
resource "aws_api_gateway_deployment" "private" {
  count       = local.create ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.private[0].id
  depends_on  = [aws_api_gateway_integration.graphql]
  triggers    = { redeployment = sha1(jsonencode([aws_api_gateway_resource.graphql, aws_api_gateway_integration.graphql])) }
  lifecycle { create_before_destroy = true }
}
resource "aws_api_gateway_stage" "private" {
  count         = local.create ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.private[0].id
  deployment_id = aws_api_gateway_deployment.private[0].id
  stage_name    = var.environment
  tags          = var.tags
}
