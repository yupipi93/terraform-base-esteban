resource "google_logging_metric" "custom-roles-monitoring" {
  count = var.metric_alerts.custom_roles ? 1 : 0

  name = format("%s--custom-roles-monitoring", local.m_base_name_medium)

  description = "Custom Roles Monitoring"
  filter      = "resource.type=\"iam_role\" AND (protoPayload.methodName=\"google.iam.admin.v1.CreateRole\" OR protoPayload.methodName=\"google.iam.admin.v1.DeleteRole\" OR protoPayload.methodName=\"google.iam.admin.v1.UpdateRole\")"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
