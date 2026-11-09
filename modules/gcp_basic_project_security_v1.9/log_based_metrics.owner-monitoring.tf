resource "google_logging_metric" "owner-monitoring" {
  count = var.metric_alerts.owner ? 1 : 0

  name = format("%s--owner-monitoring", local.m_base_name_medium)

  description = "Owner Monitoring"
  filter      = "(protoPayload.serviceName=\"cloudresourcemanager.googleapis.com\") AND (ProjectOwnership OR projectOwnerInvitee) OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"REMOVE\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\") OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"ADD\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\")"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
