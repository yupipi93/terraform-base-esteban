resource "google_logging_metric" "routes-monitoring" {
  count = var.metric_alerts.routes ? 1 : 0

  name = format("%s--routes-monitoring", local.m_base_name_medium)

  description = "Routes Monitoring"
  filter      = "resource.type=\"gce_route\" AND (protoPayload.methodName:\"compute.routes.delete\" OR protoPayload.methodName:\"compute.routes.insert\")"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
