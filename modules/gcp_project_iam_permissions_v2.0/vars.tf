variable "project_id" {
  type        = string
  description = "GCP Project source id"
}

variable "permissions" {
  type = list(object({
    members = list(string)
    roles   = list(string)
  }))
  description = "List the members and list of roles to assign"
}

