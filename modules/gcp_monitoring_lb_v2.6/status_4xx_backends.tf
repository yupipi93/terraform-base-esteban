resource "google_monitoring_alert_policy" "lb_4xx_errors" {
  for_each     = var.status_4xx_backends
  project      = var.gcp_project_id
  display_name = format("%s | %s %s | 4XX errors excluding 403 and 404 in the backends", var.gcp_project_id_monitoring, var.load_balancer, each.key)
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = each.value.enabled
  conditions {
    display_name = format("%s | %s %s | 4XX errors excluding 403 and 404 in the backends", var.gcp_project_id, var.load_balancer, each.key)
    condition_threshold {
      filter          = format("metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\" resource.label.\"project_id\"=\"%s\" resource.labels.\"url_map_name\"=\"%s\" metric.label.\"response_code_class\"=\"%d\" metric.label.\"response_code\"!=\"%d\" metric.label.\"response_code\"!=\"%d\" resource.labels.backend_type != \"NO_BACKEND_SELECTED\" %s", var.gcp_project_id_monitoring, var.load_balancer, 400, 404, 403, join(" ", [for i in each.value.ignore_backends : "resource.label.\"backend_target_name\"!=\"${i}\""]))
      duration        = each.value.duration
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold_value
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
}

