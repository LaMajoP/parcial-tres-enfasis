variable "enabled" {
  type    = bool
  default = false
}
variable "environment" { type = string }
variable "execute_api_vpce_id" { type = string }
variable "internal_nlb_arn" {
  type     = string
  default  = null
  nullable = true
}
variable "internal_nlb_dns_name" {
  type     = string
  default  = null
  nullable = true
}
variable "tags" { type = map(string) }
