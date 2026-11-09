# _Default retention is written down so a project does not keep Google's
# unspoken default. _Required stays untouched unless the YAML sets it: Google
# rejects a value under 400 days.
#
# logging.audit_archive copies every Cloud Audit Log into a dedicated log
# bucket. _Default can be shortened or emptied by a project owner; a locked
# archive cannot. Without the key nothing is created.

locals {
  audit_archive         = try(local.settings.logging.audit_archive, null)
  audit_archive_enabled = local.audit_archive != null

  audit_archive_default_filter = join(" OR ", [
    for log in ["activity", "data_access", "system_event", "policy"] :
    "log_id(\"cloudaudit.googleapis.com/${log}\")"
  ])
}

check "required_log_retention" {
  assert {
    condition     = try(local.settings.logging.required_retention_days, 400) >= 400
    error_message = "logging.required_retention_days must be at least 400. Omit the key to leave the _Required bucket alone."
  }
}

check "audit_archive_retention" {
  assert {
    condition     = !local.audit_archive_enabled || try(local.audit_archive.retention_days >= 1 && local.audit_archive.retention_days <= 3650, false)
    error_message = "logging.audit_archive.retention_days must be set, between 1 and 3650. A locked bucket keeps it for good, so choose it before setting locked: true."
  }
}

resource "google_logging_project_bucket_config" "default" {
  project        = local.settings.project.id
  location       = "global"
  bucket_id      = "_Default"
  retention_days = try(local.settings.logging.retention_days, local.workspace == "pro" ? 90 : 30)

  depends_on = [google_project_service.enabled_apis]
}

resource "google_logging_project_bucket_config" "required" {
  count          = try(local.settings.logging.required_retention_days, null) == null ? 0 : 1
  project        = local.settings.project.id
  location       = "global"
  bucket_id      = "_Required"
  retention_days = try(local.settings.logging.required_retention_days, 400)

  depends_on = [google_project_service.enabled_apis]
}

# A locked bucket cannot be unlocked, its retention can only grow, and it can
# be deleted only once every entry in it is older than retention_days.
resource "google_logging_project_bucket_config" "audit_archive" {
  count          = local.audit_archive_enabled ? 1 : 0
  project        = local.settings.project.id
  location       = try(local.audit_archive.location, "global")
  bucket_id      = try(local.audit_archive.bucket_id, "audit-archive")
  description    = "Cloud Audit Logs archive, managed by Terraform"
  retention_days = try(local.audit_archive.retention_days, null)
  locked         = try(local.audit_archive.locked, false)

  depends_on = [google_project_service.enabled_apis]
}

# The destination is a log bucket in the same project, so the sink needs no
# IAM grant on it: Cloud Logging writes there on its own authority.
resource "google_logging_project_sink" "audit_archive" {
  count                  = local.audit_archive_enabled ? 1 : 0
  project                = local.settings.project.id
  name                   = "${local.base_name_medium}-audit-archive"
  description            = "Routes Cloud Audit Logs to the locked audit archive bucket"
  destination            = "logging.googleapis.com/${google_logging_project_bucket_config.audit_archive[0].id}"
  filter                 = try(local.audit_archive.filter, local.audit_archive_default_filter)
  unique_writer_identity = true
}
