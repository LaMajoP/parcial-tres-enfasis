variable "floci_endpoint" {
  type        = string
  default     = "http://127.0.0.1:4567"
  description = "Endpoint local de Floci; esta raíz no admite AWS real."

  validation {
    condition     = var.floci_endpoint == "http://127.0.0.1:4567"
    error_message = "local-floci-bootstrap sólo permite el endpoint loopback de Floci."
  }
}

variable "aws_region" { type = string }
variable "owner" { type = string }

variable "state_bucket_name" {
  type        = string
  description = "Bucket S3 emulado, reservado para comprobar el bootstrap local."
}
