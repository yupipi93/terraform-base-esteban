resource "google_logging_metric" "storage-permissions-changes" {
  count = var.metric_alerts.storage_permissions ? 1 : 0

  name = format("%s--storage-permissions-changes", local.m_base_name_medium)

  description = "Storage Permissions Changes"
  filter      = "resource.type=gcs_bucket AND protoPayload.methodName=\"storage.setIamPermissions\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
