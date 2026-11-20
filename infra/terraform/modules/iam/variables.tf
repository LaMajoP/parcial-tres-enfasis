variable "environment" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
variable "table_arns" { type = map(string) }
variable "tags" { type = map(string) }
