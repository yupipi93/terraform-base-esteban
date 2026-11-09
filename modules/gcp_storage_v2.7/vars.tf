# Constant for module
variable "module_name" {
  type    = string
  default = "storage"
}

variable "base_name" {
  type        = string
  description = "Name for the resource"
}

variable "region_name" {
  type        = string
  description = "Region name"
}

variable "class" {
  type        = string
  description = "Bucket type"
  default     = "REGIONAL"
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
  description = "Permissions to the bucket"
  default     = {}
}

variable "authoritative_permissions" {
  type        = bool
  description = "Set authoritative_permissions"
  default     = true
}

variable "force_destroy" {
  type    = string
  default = "true"
}

variable "enable_versioning" {
  type    = bool
  default = true
}

variable "uniform_bucket_level_access" {
  type    = bool
  default = true
}

variable "public_access_prevention" {
  description = "enforced stops a later allUsers binding from making the bucket public."
  type        = string
  default     = "enforced"
}

variable "lifecycle_rules" {
  type = map(
    object({
      age                        = optional(number, null)
      days_since_noncurrent_time = optional(number, null)
      num_newer_versions         = optional(number, null)
      action_type                = string
      action_sc                  = optional(string, null)
      matches_prefixes           = optional(list(string), [])
      matches_storage_class      = optional(list(string), [])
      matches_suffix             = optional(list(string), [])
    })
  )

  validation {
    condition     = alltrue([for item in var.lifecycle_rules : item.age != null || item.days_since_noncurrent_time != null || item.num_newer_versions != null])
    error_message = "Each lifecycle rule needs at least one of age, days_since_noncurrent_time or num_newer_versions."
  }

  validation {
    condition     = alltrue([for item in var.lifecycle_rules : (item.days_since_noncurrent_time == null || try(item.days_since_noncurrent_time >= 1, false)) && (item.num_newer_versions == null || try(item.num_newer_versions >= 1, false))])
    error_message = "days_since_noncurrent_time and num_newer_versions must be at least 1 (the provider does not send a 0)."
  }

  validation {
    condition     = alltrue([for item in var.lifecycle_rules : (item.action_sc == null && item.action_type != "SetStorageClass") || (item.action_sc != null && item.action_type == "SetStorageClass")])
    error_message = "With the action_type SetStorageClass you must configure the destination storage class with action_sc."
  }

  validation {
    condition     = alltrue([for item in var.lifecycle_rules : contains(["Delete", "SetStorageClass", "AbortIncompleteMultipartUpload"], item.action_type)])
    error_message = "The action_type option only supports the 'Delete', 'SetStorageClass' and 'AbortIncompleteMultipartUpload' options (case sensitive)."
  }

  validation {
    condition     = alltrue([for item in var.lifecycle_rules : contains(["STANDARD", "MULTI_REGIONAL", "REGIONAL", "NEARLINE", "COLDLINE", "ARCHIVE"], item.action_sc != null ? item.action_sc : "ARCHIVE")])
    error_message = "The action_sc option only supports the 'STANDARD', 'MULTI_REGIONAL', 'REGIONAL', 'NEARLINE', 'COLDLINE' and 'ARCHIVE' options (case sensitive)."
  }

  description = "Parameters to configure the lifecycles"
  default     = {}
}


variable "website" {
  type = object({
    main_page_suffix = optional(string, null)
    not_found_page   = optional(string, null)
  })

  description = "The website configuration for the bucket."
  default     = null
}

variable "cors" {
  type = list(object({
    origin          = optional(list(string), null)
    method          = optional(list(string), null)
    response_header = optional(list(string), null)
    max_age_seconds = optional(number, null)
  }))

  description = "The cors configurations for the storage"
  default     = []
}

variable "soft_delete_retention_duration" {
  type        = number
  description = "The time that the soft delete policy retains deleted objects; if it is set to 0, this policy does not exist"
  default     = 604800
}

variable "autoclass" {
  type = object({
    enabled                = bool
    terminal_storage_class = optional(string, "ARCHIVE")
  })
  description = "Autoclass configuration for the bucket. Set to null to disable."
  default     = null
}

variable "retention_policy" {
  type = object({
    retention_period = number
    is_locked        = optional(bool, false)
  })
  description = "Bucket retention policy: no object can be deleted or replaced before it is retention_period seconds old. is_locked = true is irreversible. Null for none."
  default     = null

  validation {
    condition     = var.retention_policy == null || try(var.retention_policy.retention_period >= 1 && var.retention_policy.retention_period < 3155760000 && floor(var.retention_policy.retention_period) == var.retention_policy.retention_period, false)
    error_message = "retention_period is a whole number of seconds, at least 1 and less than 3,155,760,000 (100 years)."
  }
}

variable "logging" {
  type = object({
    log_bucket        = string
    log_object_prefix = optional(string, null)
  })
  description = "Usage and storage logs: the bucket that receives the log objects and an optional object prefix (default: this bucket's name). Null for none."
  default     = null

  validation {
    condition     = var.logging == null || can(regex("^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$", var.logging.log_bucket))
    error_message = "log_bucket is a bucket name (lowercase letters, digits, dots, hyphens, underscores), without gs://."
  }
}

variable "use_random_suffix" {
  type        = bool
  description = "Append a random hex suffix to the bucket name. Set to false to use the base name as-is."
  default     = true
}
