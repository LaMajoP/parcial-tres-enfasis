locals {
  # Deben coincidir exactamente con `app` en los Pods, porque Fluent Bit usa
  # ese label para construir el nombre del grupo y no crea grupos dinámicos.
  services = toset([
    "graphql-gateway",
    "station-reservation",
    "billing-wallet",
    "energy-dispatch",
    "web",
    "aws-for-fluent-bit",
  ])
}
resource "aws_cloudwatch_log_group" "service" {
  for_each          = local.services
  name              = "/aegisvolt/${var.environment}/${each.value}"
  retention_in_days = var.log_retention_days
  tags              = merge(var.tags, { Service = each.value })
}
resource "aws_cloudwatch_metric_alarm" "saga_compensation_failure" {
  alarm_name          = "aegisvolt-${var.environment}-saga-compensation-failed"
  namespace           = "AegisVolt/Gateway"
  metric_name         = "CompensationFailed"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "Una compensación requiere reconciliación manual/automática."
  dimensions          = { Environment = var.environment, Service = "graphql-gateway" }
  tags                = var.tags
}
resource "aws_cloudwatch_dashboard" "operations" {
  dashboard_name = "aegisvolt-${var.environment}-operations"
  dashboard_body = jsonencode({ widgets = [{
    type = "metric"
    properties = {
      title  = "Gateway: SAGAs, errores y p95"
      view   = "timeSeries"
      region = data.aws_region.current.name
      metrics = [
        ["AegisVolt/Gateway", "SagaCompleted", "Environment", var.environment, "Service", "graphql-gateway", { stat = "Sum" }],
        [".", "CompensationFailed", ".", ".", ".", ".", { stat = "Sum" }],
        [".", "Http5xx", ".", ".", ".", ".", { stat = "Sum" }],
        [".", "LatencyMs", ".", ".", ".", ".", { stat = "p95" }]
      ]
    }
  }] })
}
data "aws_region" "current" {}
