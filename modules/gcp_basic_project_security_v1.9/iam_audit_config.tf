resource "google_project_iam_audit_config" "project" {
  for_each = (
    var.audit_logging.admin_read == true ||
    var.audit_logging.data_read == true ||
    var.audit_logging.data_write == true
    ? { "apply" : true } : {}
  )

  project = var.gcp_project_id
  service = "allServices"

  dynamic "audit_log_config" {
    for_each = var.audit_logging.admin_read == true ? ["A"] : []
    content {
      log_type = "ADMIN_READ"
    }
  }

  dynamic "audit_log_config" {
    for_each = var.audit_logging.data_read == true ? ["A"] : []
    content {
      log_type = "DATA_READ"
    }
  }

  dynamic "audit_log_config" {
    for_each = var.audit_logging.data_write == true ? ["A"] : []
    content {
      log_type = "DATA_WRITE"
    }
  }
}
