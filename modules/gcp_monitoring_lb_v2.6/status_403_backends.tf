resource "google_monitoring_alert_policy" "lb_403_errors" {
  for_each     = var.status_403_backends
  project      = var.gcp_project_id
  display_name = format("%s | %s %s | 403 errors in the backends", var.gcp_project_id_monitoring, var.load_balancer, each.key)
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = each.value.enabled
  conditions {
    display_name = format("%s | %s %s | 403 errors in the backends", var.gcp_project_id, var.load_balancer, each.key)
    condition_threshold {
      filter                  = format("metric.type = \"logging.googleapis.com/user/request_count_403_backend\" resource.label.\"project_id\"=\"%s\" resource.type = \"l7_lb_rule\" ", var.gcp_project_id_monitoring)
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
      duration                = each.value.duration
      comparison              = "COMPARISON_GT"
      threshold_value         = each.value.threshold_value
      aggregations {
        alignment_period     = each.value.alignment_period
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "metric.label.response_code",
        ]
      }
      trigger {
        count   = 1
        percent = 0
      }
    }
  }
  notification_channels = each.value.notification_channels
  user_labels = {
    service    = "lb"
    created_by = "terraform"
    repo_iac   = var.repo_iac
  }

  # The condition names the metric by type only: without this the policy can
  # be created before the metric and the API rejects it.
  depends_on = [google_logging_metric.request_count_403_backend]
}

resource "google_logging_metric" "request_count_403_backend" { # TODO: add ignored backends
  count   = length(var.status_403_backends) == 0 ? 0 : 1
  name    = "request_count_403_backend"
  project = var.gcp_project_id_monitoring
  filter  = format("resource.type=\"http_load_balancer\" httpRequest.status=\"403\" jsonPayload.statusDetails=\"response_sent_by_backend\"")
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
  timeouts {}
}
