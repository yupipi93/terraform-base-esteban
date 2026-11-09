# Constant for module
variable "module_name" {
  type    = string
  default = "security"
}

variable "base_name" {
  type        = string
  description = "Base name"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "audit_logging" {
  type = object({
    admin_read = optional(bool, true)
    data_read  = optional(bool, false)
    data_write = optional(bool, false)
  })

  default = {}
}

# One switch per alert family: false removes its log-based metric and its
# threshold alert policy. The OS Login metadata and the audit config do not
# depend on it.
variable "metric_alerts" {
  type = object({
    audit_config        = optional(bool, true)
    cloud_sql           = optional(bool, true)
    custom_roles        = optional(bool, true)
    firewall            = optional(bool, true)
    network             = optional(bool, true)
    owner               = optional(bool, true)
    routes              = optional(bool, true)
    storage_permissions = optional(bool, true)
  })
  description = "Metric threshold alerts to create, per family. Every family is on by default."
  default     = {}
  nullable    = false
}

// In this case notification channels are required to fully remove all SCC alerts
variable "notification_channels" {
  type        = list(any)
  description = "List of notification channel resources"
}
