resource "google_logging_metric" "cloud-sql-monitoring" {
  count = var.metric_alerts.cloud_sql ? 1 : 0

  name = format("%s--cloud-sql-monitoring", local.m_base_name_medium)

  description = "Cloud SQL Monitoring"
  filter      = "protoPayload.methodName=\"cloudsql.instances.update\" OR protoPayload.methodName=\"cloudsql.instances.create\" OR protoPayload.methodName=\"cloudsql.instances.delete\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
