variable "gcp_project_id" {
  type        = string
  description = "GCP Project where will be the Alerting"
  default     = ""
}

variable "gcp_project_id_monitoring" {
  type        = string
  description = "GCP Project source"
}

variable "repo_iac" {
  type        = string
  description = "URL or name of IAC repository"
}

variable "region_name" {
  type        = string
  description = "GCP region name"
}

variable "load_balancer" {
  type        = string
  description = "LB name to monitoring"
}

variable "latency" {
  type = map(object({
    duration              = string
    threshold_value       = number
    alignment_period      = string
    severity              = string
    enabled               = bool
    notification_channels = optional(list(string))
  }))
  default = {
    "default" = {
      duration              = "300s"
      threshold_value       = 3000
      alignment_period      = "60s"
      severity              = "WARNING"
      enabled               = true
      notification_channels = []
    }
  }
}

variable "request_count" {
  type = map(object({
    duration              = string
    threshold_value       = number
    alignment_period      = string
    severity              = string
    enabled               = bool
    notification_channels = optional(list(string))
  }))
  default = {
    "default" = {
      duration              = "180s"
      threshold_value       = 100
      alignment_period      = "60s"
      severity              = "ERROR"
      enabled               = true
      notification_channels = []
    }
  }
}

variable "status_403_cloud_armor" {
  type = map(object({
    duration              = string
    threshold_value       = number
    alignment_period      = string
    severity              = string
    enabled               = bool
    notification_channels = optional(list(string))
  }))
  default = {

  }
}

variable "status_403_backends" {
  type = map(object({
    duration         = string
    threshold_value  = number
    alignment_period = string
    severity         = string
    enabled          = bool
    # ignore_backends       = optional(list(string)) # To Do
    notification_channels = optional(list(string))
  }))
  default = {
    "default" = {
      duration         = "180s"
      threshold_value  = 100
      alignment_period = "60s"
      severity         = "ERROR"
      enabled          = true
      # ignore_backends       = []
      notification_channels = []
    }
  }
}

variable "status_404_backends" {
  type = map(object({
    duration              = string
    threshold_value       = number
    alignment_period      = string
    severity              = string
    enabled               = bool
    ignore_backends       = optional(list(string))
    notification_channels = optional(list(string))
  }))
  default = {
    "default" = {
      duration              = "180s"
      threshold_value       = 100
      alignment_period      = "60s"
      severity              = "ERROR"
      enabled               = true
      ignore_backends       = []
      notification_channels = []
    }
  }
}

variable "status_4xx_backends" {
  type = map(object({
    duration              = string
    threshold_value       = number
    alignment_period      = string
    severity              = string
    enabled               = bool
    ignore_backends       = optional(list(string))
    notification_channels = optional(list(string))
  }))
  default = {
    "default" = {
      duration              = "180s"
      threshold_value       = 100
      alignment_period      = "60s"
      severity              = "ERROR"
      enabled               = true
      ignore_backends       = []
      notification_channels = []
    }
  }
}

variable "status_5xx_backends" {
  type = map(object({
    duration              = string
    threshold_value       = number
    alignment_period      = string
    severity              = string
    enabled               = bool
    ignore_backends       = optional(list(string))
    notification_channels = optional(list(string))
  }))
  default = {
    "default" = {
      duration              = "180s"
      threshold_value       = 100
      alignment_period      = "60s"
      severity              = "ERROR"
      enabled               = true
      ignore_backends       = []
      notification_channels = []
    }
  }
}