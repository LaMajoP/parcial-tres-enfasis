variable "region" {
  description = "Región nominal que LocalStack emula; no identifica una cuenta AWS."
  type        = string
  default     = "us-east-2"
}

variable "endpoint" {
  description = "Único endpoint permitido para esta demostración local."
  type        = string
  default     = "http://127.0.0.1:4566"

  validation {
    condition     = var.endpoint == "http://127.0.0.1:4566"
    error_message = "La demostración local solo permite http://127.0.0.1:4566; no admite endpoints AWS ni remotos."
  }
}

variable "state_bucket" {
  description = "Bucket de state exclusivo de LocalStack; no corresponde a AWS."
  type        = string
  default     = "aegisvolt-local-terraform-state"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket debe tener un nombre de bucket S3 válido."
  }
}
