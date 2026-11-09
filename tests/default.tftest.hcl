# The default workspace reads settings/default.yaml alone: placeholders, no
# sections. It must plan without a VPC, a database, a load balancer or the
# Cloud Build service account. Mock providers: no credentials, no API call.

mock_provider "google" {}
mock_provider "google" {
  alias = "unlabelled"
}
mock_provider "google-beta" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "sops" {}
mock_provider "archive" {}
mock_provider "oci" {}

run "empty_shape_creates_nothing_optional" {
  command = plan

  assert {
    condition     = local.workspace == "default" && local.settings.project.id == "my-project-id"
    error_message = "With settings_workspace unset the default workspace must read settings/default.yaml."
  }

  assert {
    condition     = !local.network_enabled && length(module.network) == 0 && !local.private_service_access_needed && length(local.services_ip_ranges) == 0
    error_message = "No network section: no shared VPC, no Private Service Access range and no servicenetworking connection."
  }

  assert {
    condition     = length(module.cloud_sql) == 0 && length(google_redis_instance.redis_instances) == 0
    error_message = "No database or redis section: no Cloud SQL and no Memorystore."
  }

  assert {
    condition = (
      !local.lb_enabled
      && length(google_compute_global_forwarding_rule.lb_forwarding_rule) == 0
      && length(google_compute_url_map.load_balancer) == 0
      && length(google_compute_global_address.lb_static_ip) == 0
    )
    error_message = "No lb section: no load balancer, URL map or static IP."
  }

  assert {
    condition     = length(google_service_account.cloudbuild) == 0 && length(google_cloudbuild_trigger.cloudbuild_triggers) == 0
    error_message = "No cloudbuild entry: no Cloud Build service account and no trigger."
  }

  assert {
    condition     = length(try(local.settings.network.nats, {})) == 0 && length(google_compute_router_nat.nat) == 0
    error_message = "No NAT without a network section."
  }

  assert {
    condition     = length(google_logging_project_bucket_config.audit_archive) == 0 && length(google_monitoring_alert_policy.log_alerts) == 0
    error_message = "No audit archive and no log alerts outside the workspaces that ask for them."
  }

  assert {
    condition     = google_logging_project_bucket_config.default.retention_days == 30
    error_message = "_Default keeps 30 days outside pro."
  }
}
