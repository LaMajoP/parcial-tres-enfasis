locals {
  # Las cinco imágenes de aplicación se promueven por el pipeline. Las tres
  # imágenes de plataforma se reflejan una vez desde una estación con Internet
  # antes de iniciar nodos EKS privados sin NAT.
  components = toset([
    "web",
    "graphql-gateway",
    "station-reservation",
    "billing-wallet",
    "energy-dispatch",
    "aws-for-fluent-bit",
    "argo-rollouts",
    "aws-load-balancer-controller",
  ])
}
resource "aws_ecr_repository" "this" {
  for_each             = local.components
  name                 = "aegisvolt/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = merge(var.tags, { Component = each.value })
}
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Conservar 30 imágenes inmutables", selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }, action = { type = "expire" } }] })
}
