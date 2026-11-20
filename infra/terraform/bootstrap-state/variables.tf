variable "aws_region" { type = string }

variable "state_bucket_name" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "El bucket debe ser un nombre S3 válido y globalmente único."
  }
}

variable "allowed_principal_arns" {
  type = set(string)
  validation {
    condition     = length(var.allowed_principal_arns) > 0
    error_message = "Declare identidades concretas autorizadas; no se acepta una política pública."
  }
}

variable "owner" {
  type    = string
  default = "platform-team"
}
