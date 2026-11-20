variable "environment" { type = string }
variable "tags" { type = map(string) }
variable "point_in_time_recovery" { type = bool, default = true }
