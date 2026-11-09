resource "google_monitoring_alert_policy" "cloud_run" {
  project      = var.gcp_project_sys_id
  display_name = format("%s | %s ", var.base_name, title(local.module_name))
  enabled      = true
  combiner     = "OR"
  user_labels = {
    created_by = "terraform"
    repo_iac   = var.monitoring.repo_iac
  }

  conditions {
    display_name = format("%s | %s | %s", var.base_name, title(local.module_name), "CPU Utilization")
    condition_threshold {
      filter          = format("metric.type=\"run.googleapis.com/container/cpu/utilizations\" resource.type=\"cloud_run_revision\" resource.label.\"project_id\"=\"%s\" resource.label.\"service_name\"=\"%s\"", var.gcp_project_id, local.m_base_name)
      duration        = var.monitoring.cpu.duration
      comparison      = "COMPARISON_GT"
      threshold_value = var.monitoring.cpu.threshold_value
      aggregations {
        cross_series_reducer = "REDUCE_PERCENTILE_99"
        group_by_fields = [
          "resource.label.service_name",
        ]
        alignment_period   = var.monitoring.cpu.alignment_period
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | %s ", var.base_name, title(local.module_name), "Memory Usage")
    condition_threshold {
      filter          = format("metric.type=\"run.googleapis.com/container/memory/utilizations\" resource.type=\"cloud_run_revision\" resource.label.\"project_id\"=\"%s\" resource.label.\"service_name\"=\"%s\"", var.gcp_project_id, local.m_base_name)
      duration        = var.monitoring.memory.duration
      comparison      = "COMPARISON_GT"
      threshold_value = var.monitoring.memory.threshold_value
      aggregations {
        cross_series_reducer = "REDUCE_PERCENTILE_99"
        group_by_fields = [
          "resource.label.service_name",
        ]
        alignment_period   = var.monitoring.memory.alignment_period
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | %s ", var.base_name, title(local.module_name), "Instances Count")
    condition_threshold {
      filter          = format("metric.type=\"run.googleapis.com/container/instance_count\" resource.type=\"cloud_run_revision\" resource.label.\"project_id\"=\"%s\" resource.label.\"service_name\"=\"%s\" metric.label.\"state\"=\"active\"", var.gcp_project_id, local.m_base_name)
      duration        = var.monitoring.instances_count.duration
      comparison      = "COMPARISON_GT"
      threshold_value = var.cloudrun.autoscaling.max
      aggregations {
        cross_series_reducer = "REDUCE_SUM"
        alignment_period     = var.monitoring.instances_count.alignment_period
        per_series_aligner   = "ALIGN_MEAN"
      }

      trigger {
        count   = var.monitoring.instances_count.trigger_count_series
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | %s ", var.base_name, title(local.module_name), "Request 5XX Count")
    condition_threshold {
      filter          = format("metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.\"project_id\"=\"%s\" resource.label.\"service_name\"=\"%s\" metric.label.\"response_code_class\"=\"5xx\"", var.gcp_project_id, local.m_base_name)
      duration        = var.monitoring.request_5XX_count.duration
      comparison      = "COMPARISON_GT"
      threshold_value = var.monitoring.request_5XX_count.threshold_value
      aggregations {
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "resource.label.service_name",
        ]
        per_series_aligner = "ALIGN_MEAN"
        alignment_period   = var.monitoring.request_5XX_count.alignment_period
      }

      trigger {
        count   = var.monitoring.request_5XX_count.trigger_count_series
        percent = 0
      }
    }
  }

  notification_channels = var.monitoring.notification_channels
}
