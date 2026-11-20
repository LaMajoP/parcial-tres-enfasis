locals { components = toset(["web", "graphql-gateway", "station-reservation", "billing-wallet", "energy-dispatch"]) }
resource "aws_ecr_repository" "this" {
  for_each = local.components
  name = "aegisvolt/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = merge(var.tags, { Component = each.value })
}
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Conservar 30 imágenes inmutables", selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }, action = { type = "expire" } }] })
}
