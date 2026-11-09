resource "google_monitoring_alert_policy" "storage-permissions-changes" {
  count = var.metric_alerts.storage_permissions ? 1 : 0

  display_name = format("%s--storage-permissions-changes", local.m_base_name_medium)
  combiner     = "OR"

  alert_strategy {
    auto_close = "604800s"
  }

  conditions {
    display_name = "storage-permissions-changes"
    condition_threshold {
      filter     = "resource.type = \"gcs_bucket\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.storage-permissions-changes[0].name}\""
      duration   = "0s"
      comparison = "COMPARISON_GT"
      aggregations {
        alignment_period     = "600s"
        cross_series_reducer = "REDUCE_SUM"
        per_series_aligner   = "ALIGN_DELTA"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  notification_channels = var.notification_channels
}
