# v1.9 put count on the metrics and alert policies. These blocks move the
# objects a v1.8 workspace already has to instance [0], so the upgrade plans
# no destroy. A family switched off afterwards plans its own destroy.

moved {
  from = google_logging_metric.audit-config-changes
  to   = google_logging_metric.audit-config-changes[0]
}

moved {
  from = google_monitoring_alert_policy.audit-config-changes
  to   = google_monitoring_alert_policy.audit-config-changes[0]
}

moved {
  from = google_logging_metric.cloud-sql-monitoring
  to   = google_logging_metric.cloud-sql-monitoring[0]
}

moved {
  from = google_monitoring_alert_policy.cloud-sql-monitoring
  to   = google_monitoring_alert_policy.cloud-sql-monitoring[0]
}

moved {
  from = google_logging_metric.custom-roles-monitoring
  to   = google_logging_metric.custom-roles-monitoring[0]
}

moved {
  from = google_monitoring_alert_policy.custom-roles-monitoring
  to   = google_monitoring_alert_policy.custom-roles-monitoring[0]
}

moved {
  from = google_logging_metric.firewall-monitoring
  to   = google_logging_metric.firewall-monitoring[0]
}

moved {
  from = google_monitoring_alert_policy.firewall-monitoring
  to   = google_monitoring_alert_policy.firewall-monitoring[0]
}

moved {
  from = google_logging_metric.network-monitoring
  to   = google_logging_metric.network-monitoring[0]
}

moved {
  from = google_monitoring_alert_policy.network-monitoring
  to   = google_monitoring_alert_policy.network-monitoring[0]
}

moved {
  from = google_logging_metric.owner-monitoring
  to   = google_logging_metric.owner-monitoring[0]
}

moved {
  from = google_monitoring_alert_policy.owner-monitoring
  to   = google_monitoring_alert_policy.owner-monitoring[0]
}

moved {
  from = google_logging_metric.routes-monitoring
  to   = google_logging_metric.routes-monitoring[0]
}

moved {
  from = google_monitoring_alert_policy.routes-monitoring
  to   = google_monitoring_alert_policy.routes-monitoring[0]
}

moved {
  from = google_logging_metric.storage-permissions-changes
  to   = google_logging_metric.storage-permissions-changes[0]
}

moved {
  from = google_monitoring_alert_policy.storage-permissions-changes
  to   = google_monitoring_alert_policy.storage-permissions-changes[0]
}
