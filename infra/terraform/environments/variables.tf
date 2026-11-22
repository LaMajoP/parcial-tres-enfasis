variable "aws_region" {
  type = string
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region debe tener formato de región AWS, por ejemplo us-east-1."
  }
}
variable "owner" {
  type = string
  validation {
    condition     = trimspace(var.owner) != ""
    error_message = "owner no puede ser vacío."
  }
}
variable "github_repository" {
  type        = string
  description = "owner/repository; etiqueta de trazabilidad y referencia para la política OIDC externa"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository debe tener el formato owner/repository."
  }
}
variable "eks_access_principal_arns" {
  type        = list(string)
  description = "Roles IAM autorizados a administrar el API privado de EKS; incluya el rol de CD del Environment."
  validation {
    condition     = length(var.eks_access_principal_arns) > 0 && alltrue([for arn in var.eks_access_principal_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+", arn))])
    error_message = "Declare al menos un ARN de rol IAM válido para acceso al clúster EKS."
  }
}
variable "vpc_cidrs" {
  type = map(string)
  validation {
    condition = length(var.vpc_cidrs) == 3 && alltrue([
      for environment in ["dev", "test", "prod"] : can(cidrhost(lookup(var.vpc_cidrs, environment, ""), 0))
    ]) && length(distinct(values(var.vpc_cidrs))) == 3
    error_message = "vpc_cidrs debe contener CIDRs válidos y distintos exactamente para dev, test y prod."
  }
}
variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) == length(toset(var.availability_zones))
    error_message = "availability_zones requiere al menos dos zonas distintas."
  }
}
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
