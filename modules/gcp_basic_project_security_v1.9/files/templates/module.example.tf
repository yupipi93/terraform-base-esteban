module "basic_security" {
  source = "./modules/gcp_basic_project_security_v1.9"

  base_name      = local.settings.project_name
  gcp_project_id = local.settings.project_id

  # Audit logging is optional
  audit_logging = {
    admin_read = true
    data_read  = false
    data_write = false
  }

  # Optional: every family is on by default. Turn off the ones another
  # alert already covers.
  metric_alerts = {
    firewall = false
  }

  notification_channels = [
    "notification_channel"
  ]
}

