resource "google_logging_metric" "network-monitoring" {
  count = var.metric_alerts.network ? 1 : 0

  name = format("%s--network-monitoring", local.m_base_name_medium)

  description = "Network Monitoring"
  filter      = "resource.type=\"gce_network\" AND (protoPayload.methodName:\"compute.networks.insert\" OR protoPayload.methodName:\"compute.networks.patch\" OR protoPayload.methodName:\"compute.networks.delete\" OR protoPayload.methodName:\"compute.networks.removePeering\" OR protoPayload.methodName:\"compute.networks.addPeering\")"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
