data "aws_region" "current" {}
resource "aws_security_group" "endpoints" {
  name        = "aegisvolt-${var.environment}-vpce"
  description = "Solo TLS desde la VPC hacia endpoints privados"
  vpc_id      = var.vpc_id
  ingress {
    description = "TLS desde workloads privados"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
  tags = var.tags
}
resource "aws_vpc_endpoint" "gateway" {
  for_each          = toset(["s3", "dynamodb"])
  vpc_id            = var.vpc_id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  route_table_ids   = var.private_route_table_ids
  tags              = merge(var.tags, { Name = "aegisvolt-${var.environment}-${each.value}-gateway" })
}
resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(["logs", "execute-api", "ecr.api", "ecr.dkr", "sts"])
  vpc_id              = var.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "aegisvolt-${var.environment}-${replace(each.value, ".", "-")}-interface" })
}
