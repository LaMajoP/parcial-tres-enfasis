variable "floci_endpoint" {
  type        = string
  default     = "http://127.0.0.1:4567"
  description = "Endpoint loopback del emulador local; nunca admite AWS real."
  validation {
    condition     = var.floci_endpoint == "http://127.0.0.1:4567"
    error_message = "La raíz local-floci sólo permite http://127.0.0.1:4567."
  }
}

variable "aws_region" { type = string }
variable "owner" { type = string }
variable "github_repository" { type = string }
variable "eks_access_principal_arns" { type = list(string) }
variable "vpc_cidrs" { type = map(string) }
variable "availability_zones" { type = list(string) }
variable "enable_private_api" { type = bool }
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
