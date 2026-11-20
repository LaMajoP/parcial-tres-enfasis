variable "environment" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "tags" { type = map(string) }
variable "cluster_version" {
  type    = string
  default = "1.31"
}
