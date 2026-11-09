resource "google_monitoring_alert_policy" "backend-latency" {
  for_each     = var.latency
  project      = var.gcp_project_id
  display_name = format("%s | %s %s | High Latency", var.gcp_project_id_monitoring, var.load_balancer, each.key)
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = each.value.enabled
  conditions {
    display_name = format("%s | %s %s | High Latency", var.gcp_project_id, var.load_balancer, each.key)
    condition_threshold {
      filter                  = format("metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" resource.type=\"https_lb_rule\" resource.label.\"project_id\"=\"%s\" resource.label.\"url_map_name\"=\"%s\"", var.gcp_project_id_monitoring, var.load_balancer)
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
      duration                = each.value.duration
      comparison              = "COMPARISON_GT"
      threshold_value         = each.value.threshold_value
      aggregations {
        alignment_period     = each.value.alignment_period
        per_series_aligner   = "ALIGN_PERCENTILE_99"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }
  notification_channels = each.value.notification_channels
}
