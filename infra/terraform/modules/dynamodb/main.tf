locals { domains = toset(["reservations", "billing", "dispatch", "saga", "flags"]) }

resource "aws_dynamodb_table" "domain" {
  for_each     = local.domains
  name         = "aegisvolt-${each.value}-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  dynamic "attribute" {
    for_each = each.value == "saga" ? [1] : []
    content {
      name = "GSI1PK"
      type = "S"
    }
  }
  dynamic "attribute" {
    for_each = each.value == "saga" ? [1] : []
    content {
      name = "GSI1SK"
      type = "S"
    }
  }
  dynamic "global_secondary_index" {
    for_each = each.value == "saga" ? [1] : []
    content {
      name            = "GSI1"
      hash_key        = "GSI1PK"
      range_key       = "GSI1SK"
      projection_type = "ALL"
    }
  }
  ttl {
    attribute_name = "expiresAt"
    enabled        = each.value == "reservations"
  }
  point_in_time_recovery { enabled = var.point_in_time_recovery }
  server_side_encryption { enabled = true }
  tags = merge(var.tags, { Name = "aegisvolt-${each.value}-${var.environment}", Domain = each.value })
}
