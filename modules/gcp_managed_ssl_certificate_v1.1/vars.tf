# Constant for module
variable "module_name" {
  type    = string
  default = "cert"
}

variable "base_name" {
  type        = string
  description = "Name for the resource"
}

variable "region_name" {
  type        = string
  description = "Region name"
}

variable "domain" {
  type        = list(string)
  description = "List of domains to add"
  default     = []
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project source"
}
