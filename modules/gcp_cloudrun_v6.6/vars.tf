# Inherited variables
variable "base_name" {
  type        = string
  description = "Base name"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "gcp_project_sys_id" {
  type        = string
  description = "GCP Project ID SYS"
}

variable "region_name" {
  type        = string
  description = "GCP region name"
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Whether Terraform will be prevented from destroying the service. Defaults to true"
}

variable "cloudrun" {
  type = object({
    execution_environment     = optional(string, "EXECUTION_ENVIRONMENT_GEN2")
    concurrency               = optional(number, 0)
    ingress                   = optional(string, "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER")
    launch_stage              = optional(string, null)
    timeout                   = optional(string, "3600s")
    cloud_sql_instances_mount = optional(list(string), null)

    containers = list(object({
      name        = string
      image       = string
      command     = optional(list(string), null)
      args        = optional(list(string), null)
      working_dir = optional(string, null)
      depends_on  = optional(list(string), null)

      volumes = optional(map(object({
        mount_path = string

        gcs = optional(object({
          storage_bucket = string
          read_only      = optional(bool, false)
        }), null)

        empty_dir = optional(object({
          medium     = optional(string, "MEMORY")
          size_limit = optional(string, null)
        }), null)

        secret = optional(object({
          secret       = string
          default_mode = optional(string, "0444")
          items = object({
            path    = string
            version = optional(string, "latest")
          })
        }), null)

      })), {})

      liveness_probe = optional(object({
        initial_delay_seconds = optional(number, null)
        timeout_seconds       = optional(number, null)
        period_seconds        = optional(number, null)
        failure_threshold     = optional(number, null)

        http_get = optional(object({
          path = optional(string, null)
          port = optional(number, null)

          http_headers = optional(list(object({
            name  = string
            value = optional(string, null)
          })), [])

        }), null)

        # Not currently supported. But TF message is "Exactly one probe action must be set (http_get, tcp_socket, or grpc)"
        #tcp_socket = optional(object({
        #  port = optional(number, null)
        #}), null)

        grpc = optional(object({
          port    = optional(number, null)
          service = optional(string, null)
        }), null)

      }), null)

      startup_probe = optional(object({
        initial_delay_seconds = optional(number, null)
        timeout_seconds       = optional(number, null)
        period_seconds        = optional(number, null)
        failure_threshold     = optional(number, null)

        http_get = optional(object({
          path = optional(string, null)
          port = optional(number, null)

          http_headers = optional(list(object({
            name  = string
            value = optional(string, null)
          })), [])

        }), null)

        tcp_socket = optional(object({
          port = number
        }), null)

        grpc = optional(object({
          port    = optional(number)
          service = optional(string)
        }), null)

      }), null)

      envs = optional(list(object({
        name  = string
        value = any
      })), [])

      secrets = optional(list(object({
        name    = string
        secret  = string
        version = optional(string, "latest")
      })), [])

      resources = optional(object({
        cpu               = optional(string, "2000m")
        memory            = optional(string, "2048Mi")
        startup_cpu_boost = optional(bool, true)
        cpu_idle          = optional(bool, false)
      }), {})

      ports = optional(object({
        name           = optional(string, "http1")
        container_port = number
      }), null)
    }))

    vpc_access = optional(object({
      connector = optional(string, null)
      egress    = optional(string, "ALL_TRAFFIC")

      network_interfaces = optional(object({
        network    = string
        subnetwork = string
        tags       = optional(list(string), null)
      }), null)
    }), null)

    autoscaling = optional(object({
      min = optional(number)
      max = optional(number)
    }), {})

    annotations = optional(map(string), null)
    iap_enabled = optional(bool, false)

    # true: every deploy of the service is checked against the project's
    # Binary Authorization policy.
    binary_authorization = optional(bool, false)
  })

  validation {
    condition     = length(var.cloudrun.containers) > 0
    error_message = "The cloud run instance must have at least one container"
  }
}

variable "service_account" {
  type = object({
    name     = string
    external = optional(bool, false)
  })

  validation {
    condition     = var.service_account.name != null
    error_message = "You must provide name variable with correct value. The external option as + name of the external service account or a string to be created inside the module"
  }

  validation {
    condition = (
      (var.service_account.name != null && var.service_account.external == true)
      || (
        length(var.service_account.name == null ? "" : var.service_account.name) >= 6
        && length(var.service_account.name == null ? "" : var.service_account.name) <= 30
        && var.service_account.external == false
      )
    )
    error_message = "SA name must be 6-30 character long."
  }

  description = "Set the external to true and put the external service account in name, or set a name to create a new internal service account."
}

variable "permissions" {
  type = map(object({
    account     = string,
    permissions = list(string)
  }))
  description = "Permissions CloudRun"
  default     = {}
}

# Constants
variable "monitoring" {
  type = object({
    cpu = optional(object({
      duration         = optional(string, "1800s")
      threshold_value  = optional(number, 0.85)
      alignment_period = optional(string, "60s")
    }), {})
    memory = optional(object({
      duration         = optional(string, "300s")
      threshold_value  = optional(number, 0.95)
      alignment_period = optional(string, "60s")
    }), {})

    instances_count = optional(object({
      duration             = optional(string, "900s")
      alignment_period     = optional(string, "60s")
      trigger_count_series = optional(number, 1)
    }), {})

    request_5XX_count = optional(object({
      duration             = optional(string, "300s")
      threshold_value      = optional(number, 50)
      alignment_period     = optional(string, "60s")
      trigger_count_series = optional(number, 1)
    }), {})

    notification_channels = optional(list(string), [])
    repo_iac              = string
  })
}
