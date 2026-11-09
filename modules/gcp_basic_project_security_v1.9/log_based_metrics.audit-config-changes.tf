resource "google_logging_metric" "audit-config-changes" {
  count = var.metric_alerts.audit_config ? 1 : 0

  name = format("%s--audit-config-changes", local.m_base_name_medium)

  description = "Audit Config Changes"
  filter      = "protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
