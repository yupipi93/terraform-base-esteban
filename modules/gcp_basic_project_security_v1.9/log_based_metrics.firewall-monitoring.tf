resource "google_logging_metric" "firewall-monitoring" {
  count = var.metric_alerts.firewall ? 1 : 0

  name = format("%s--firewall-monitoring", local.m_base_name_medium)

  description = "Firewall Monitoring"
  filter      = "resource.type=\"gce_firewall_rule\" AND (protoPayload.methodName:\"compute.firewalls.insert\" OR protoPayload.methodName:\"compute.firewalls.patch\" OR protoPayload.methodName:\"compute.firewalls.delete\")"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
