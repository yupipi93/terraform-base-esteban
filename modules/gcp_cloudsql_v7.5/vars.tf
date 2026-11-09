# Inherited variables
variable "zones_name" {
  type    = list(string)
  default = []
}

variable "special_characters_pass" {
  type = object({
    enabled    = optional(bool, false)
    characters = optional(string, "_%@<>:")
  })
  default = {}
}

variable "secrets_locations" {
  type    = list(string)
  default = []
}

variable "net_id" {
  type    = string
  default = ""
}

variable "databases" {
  type    = list(string)
  default = []
}

variable "users" {
  type = list(object({
    name = string
    host = string
  }))

  default = []
}

variable "dbe" {
  type = object({
    version      = optional(string, "MYSQL_8_0")
    tier         = optional(string, "db-f1-micro")
    availability = optional(string, "ZONAL")
    edition      = optional(string, "ENTERPRISE")
    ipv4_enabled = optional(bool, false)
    ssl_mode     = optional(string, "ENCRYPTED_ONLY")
    allowed_networks = optional(list(object({
      name  = optional(string, "")
      value = string
    })), [])
    disk = optional(object({
      type = optional(string, "PD_SSD")
      size = optional(number, 10)
    }), {})
    binary_log_enabled  = optional(bool, true)
    replica             = optional(number, 0)
    deletion_protection = optional(bool, true)
    flags               = optional(map(string))
  })

  default = {}
}

variable "flags" {
  default = {}
}

variable "insights_config" {
  type = object({
    query_insights_enabled  = optional(bool, false)
    query_plans_per_minute  = optional(number, 0)
    query_string_length     = optional(number, 256)
    record_application_tags = optional(bool, false)
    record_client_address   = optional(bool, false)
  })
  default     = {}
  description = "Active the Query Insights in the database"
}

# Constant for module
variable "module_name" {
  type    = string
  default = "cloudsql"
}

variable "base_name" {
  type        = string
  description = "Base name"
}

variable "region_name" {
  type        = string
  description = "Region name"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "gcp_project_sys_id" {
  type        = string
  description = "GCP SYS Project ID"
}

variable "backup_configuration" {
  type = object({
    start_time       = optional(string, "03:00")
    retained_backups = optional(number, 7)
    location         = optional(string, null)
    # null keeps the previous behaviour: MySQL follows dbe.binary_log_enabled, other engines stay off.
    point_in_time_recovery_enabled = optional(bool, null)
    # Days of transaction logs (WAL or binary log) kept for point-in-time recovery. null uses the GCP default.
    transaction_log_retention_days = optional(number, null)
  })
  description = "Cloud SQL Backup configuration"
  default     = {}

  validation {
    condition = (
      var.backup_configuration.transaction_log_retention_days == null ||
      try(var.backup_configuration.transaction_log_retention_days >= 1 && var.backup_configuration.transaction_log_retention_days <= 35, false)
    )
    error_message = "backup_configuration.transaction_log_retention_days must be between 1 and 35 (7 at most on the ENTERPRISE edition)."
  }
}

variable "maintenance_window" {
  type = object({
    day  = optional(number, 2)
    hour = optional(number, 7)
  })
  description = "Cloud SQL maintenance window"
  default     = {}
}
variable "deny_maintenance_period" {
  type = object({
    start_date = string
    end_date   = string
    time       = string
  })
  description = "Deny maintenance window - Max 90 days"
  default     = null
}
variable "monitoring" {
  type = object({
    cpu = optional(object({
      duration         = optional(string, "1800s")
      threshold_value  = optional(number, 0.85)
      alignment_period = optional(string, "60s")
    }), {})
    memory = optional(object({
      duration         = optional(string, "300s")
      threshold_value  = optional(number, 0.85)
      limit_ram        = optional(number, null)
      alignment_period = optional(string, "60s")
    }), {})
    connections = optional(object({
      duration         = optional(string, "120s")
      threshold_value  = optional(number, 0.85)
      max_connections  = optional(number, null)
      alignment_period = optional(string, "60s")
    }), {})
    disk_space = optional(object({
      duration         = optional(string, "600s")
      threshold_value  = optional(number, 0.85)
      alignment_period = optional(string, "60s")
    }), {})
    disk_iops = optional(object({
      duration         = optional(string, "1800s")
      threshold_value  = optional(number, 0.85)
      alignment_period = optional(string, "60s")
    }), {})
    log_entries = optional(object({
      duration         = optional(string, "60s")
      threshold_value  = optional(number, 0)
      alignment_period = optional(string, "60s")
    }), {})
  })
  default = {}
}

variable "notification_channels" {
  type        = list(any)
  default     = []
  description = "List of notification channel resources"
}

variable "notification_channels_not_on_call" {
  type        = list(any)
  default     = []
  description = "List of notification channel resources"
}

variable "evaluation_missing_data_behavior" {
  # EVALUATION_MISSING_DATA_ACTIVE: treat missing data as an active alert.
  # EVALUATION_MISSING_DATA_INACTIVE: treat missing data as an inactive alert.
  # EVALUATION_MISSING_DATA_NO_OP: ignore missing data (GCP's default when unset).
  description = "Behavior when data are missing in the evaluation"
  type        = string
  default     = "EVALUATION_MISSING_DATA_ACTIVE"
}

