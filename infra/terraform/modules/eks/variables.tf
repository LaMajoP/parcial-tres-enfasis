variable "environment" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "access_principal_arns" { type = list(string) }
variable "tags" { type = map(string) }
variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "bootstrap_self_managed_addons" {
  type        = bool
  default     = null
  nullable    = true
  description = "Null conserva el valor por defecto del provider; la emulación puede fijarlo explícitamente."
}

variable "bootstrap_cluster_creator_admin_permissions" {
  type        = bool
  default     = false
  description = "Mantiene el patrón de access entries explícitos usado por los ambientes AWS."
}
