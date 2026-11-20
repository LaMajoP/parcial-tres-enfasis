variable "aws_region" { type = string }
variable "owner" { type = string }
variable "github_repository" {
  type        = string
  description = "owner/repository; obligatorio para OIDC CI/CD"
}
variable "vpc_cidrs" { type = map(string) }
variable "availability_zones" { type = list(string) }
variable "enable_private_api" {
  type    = bool
  default = false
}
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
variable "lab_profile" {
  type    = bool
  default = true
}
