variable "environment" { type = string }
variable "tags" { type = map(string) }
variable "log_retention_days" {
  type    = number
  default = 30
}
