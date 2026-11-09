# The basic security module with security.metric_alerts of settings/pro.yaml.
# pro.tftest.hcl checks that pro turns off the families a log alert preset
# covers; this checks the module then creates no metric and no policy for
# them, so pro gets no duplicate alert, and keeps the other three.

mock_provider "google" {}

run "pro_has_no_duplicate_security_alerts" {
  command = plan

  module {
    source = "./modules/gcp_basic_project_security_v1.9"
  }

  variables {
    base_name             = "app-pro"
    gcp_project_id        = "example-app-pro"
    metric_alerts         = yamldecode(file("settings/pro.yaml")).security.metric_alerts
    notification_channels = ["projects/example-app-pro/notificationChannels/0"]
  }

  assert {
    condition = (
      length(google_monitoring_alert_policy.audit-config-changes) == 0
      && length(google_monitoring_alert_policy.cloud-sql-monitoring) == 0
      && length(google_monitoring_alert_policy.custom-roles-monitoring) == 0
      && length(google_monitoring_alert_policy.firewall-monitoring) == 0
      && length(google_monitoring_alert_policy.storage-permissions-changes) == 0
    )
    error_message = "pro creates no module alert policy for the events its log alert presets report."
  }

  assert {
    condition = (
      length(google_logging_metric.audit-config-changes) == 0
      && length(google_logging_metric.cloud-sql-monitoring) == 0
      && length(google_logging_metric.custom-roles-monitoring) == 0
      && length(google_logging_metric.firewall-monitoring) == 0
      && length(google_logging_metric.storage-permissions-changes) == 0
    )
    error_message = "A family that is off leaves no log-based metric behind."
  }

  assert {
    condition = (
      length(google_monitoring_alert_policy.network-monitoring) == 1
      && length(google_monitoring_alert_policy.routes-monitoring) == 1
      && length(google_monitoring_alert_policy.owner-monitoring) == 1
      && length(google_logging_metric.owner-monitoring) == 1
    )
    error_message = "pro keeps the network, routes and owner alerts (positive control)."
  }

  assert {
    condition     = length(google_project_iam_audit_config.project) == 1
    error_message = "The audit config does not depend on metric_alerts."
  }
}

run "every_family_is_on_by_default" {
  command = plan

  module {
    source = "./modules/gcp_basic_project_security_v1.9"
  }

  variables {
    base_name             = "app-dev"
    gcp_project_id        = "example-app-dev"
    notification_channels = ["projects/example-app-dev/notificationChannels/0"]
  }

  assert {
    condition = (
      length(google_monitoring_alert_policy.audit-config-changes) == 1
      && length(google_monitoring_alert_policy.cloud-sql-monitoring) == 1
      && length(google_monitoring_alert_policy.custom-roles-monitoring) == 1
      && length(google_monitoring_alert_policy.firewall-monitoring) == 1
      && length(google_monitoring_alert_policy.network-monitoring) == 1
      && length(google_monitoring_alert_policy.owner-monitoring) == 1
      && length(google_monitoring_alert_policy.routes-monitoring) == 1
      && length(google_monitoring_alert_policy.storage-permissions-changes) == 1
    )
    error_message = "Without metric_alerts the module keeps all eight alert policies, as v1.8 did."
  }
}
