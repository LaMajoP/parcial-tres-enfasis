locals {
  permissions = {
    station  = [var.table_arns.reservations]
    billing  = [var.table_arns.billing]
    dispatch = [var.table_arns.dispatch]
    gateway  = [var.table_arns.saga, var.table_arns.flags]
  }
  service_accounts = { station = "station-reservation", billing = "billing-wallet", dispatch = "energy-dispatch", gateway = "graphql-gateway" }
}
data "aws_iam_policy_document" "assume_irsa" {
  for_each = local.permissions
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:aegisvolt-${var.environment}:${local.service_accounts[each.key]}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "service" {
  for_each           = local.permissions
  name               = "aegisvolt-${var.environment}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume_irsa[each.key].json
  tags               = var.tags
}
resource "aws_iam_role_policy" "dynamodb" {
  for_each = local.permissions
  name     = "dynamodb-domain-only"
  role     = aws_iam_role.service[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:TransactWriteItems"], Resource = each.value }] })
}
