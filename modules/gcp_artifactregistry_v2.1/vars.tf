# Constant for module
variable "base_name" {
  type        = string
  description = "Name for the resource"
}

variable "region_name" {
  type        = string
  description = "Region name"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project source"
}

variable "permissions" {
  type = map(object({
    members = list(string)
    roles   = list(string)
  }))
  description = "Permissions Artifact Registry"
  default     = {}
}

variable "authoritative_permissions" {
  type        = bool
  description = "Set authoritative_permissions"
  default     = true
}

variable "format" {
  type        = string
  default     = "DOCKER"
  description = "Format Artifact Registry Repo"
}

variable "cleanup_policy_dry_run" {
  type        = bool
  description = "Set cleanup_policy_dry_run"
  default     = true
}

variable "cleanup_policies" {
  type = map(object({
    action = optional(string)
    condition = optional(object({
      tag_state             = optional(string, null)
      tag_prefixes          = optional(list(string))
      version_name_prefixes = optional(list(string))
      package_name_prefixes = optional(list(string))
      older_than            = optional(string)
      newer_than            = optional(string)
    }), null)
    most_recent_versions = optional(object({
      package_name_prefixes = optional(list(string))
      keep_count            = optional(number)
    }), null)
  }))

  default = {
    "keep-minimum-versions" = {
      action = "KEEP"
      most_recent_versions = {
        keep_count = 5
      }
    },
    "remove-untagged-versions" = {
      action = "DELETE"
      condition = {
        tag_state = "UNTAGGED"
      }
    }
  }

  description = "Set a list of cleanup_policies"
}

variable "immutable_tags" {
  type        = bool
  description = "Set immutable_tags flag"
  default     = false
}
