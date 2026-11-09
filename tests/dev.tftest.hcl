# settings/dev.yaml: the cheapest shape. A shared VPC for private Cloud SQL,
# but no Memorystore and no Cloud NAT, a zonal shared-core database, services
# that scale to zero without deletion protection.

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

variables {
  settings_workspace = "dev"
}

run "dev_shape_is_cheap" {
  command = plan

  # The override warns on purpose outside terraform test.
  expect_failures = [check.settings_workspace_unset]

  assert {
    condition     = local.workspace == "dev" && local.settings.project.id == "example-app-dev"
    error_message = "settings_workspace = dev must read settings/dev.yaml."
  }

  assert {
    condition     = alltrue(values(local.security_metric_alerts)) && length(local.security_metric_alerts) == 8
    error_message = "dev has no log alerts, so it keeps every threshold alert of the security module."
  }

  assert {
    condition     = length(google_org_policy_policy.service_account_keys) == 0 && !contains(local.enabled_apis, "orgpolicy.googleapis.com")
    error_message = "dev writes no organization policy and does not enable the Org Policy API."
  }

  assert {
    condition     = length(google_essential_contacts_contact.contacts) == 0 && !contains(local.enabled_apis, "essentialcontacts.googleapis.com")
    error_message = "dev creates no Essential Contact and does not enable its API."
  }

  assert {
    condition     = local.network_enabled && length(module.network) == 1
    error_message = "dev has network.services_cidr: one shared VPC (positive control for the NAT check)."
  }

  assert {
    condition     = length(try(local.settings.network.nats, {})) == 0 && length(google_compute_router_nat.nat) == 0
    error_message = "dev must not create Cloud NAT: it is billed per hour."
  }

  assert {
    condition     = length(google_redis_instance.redis_instances) == 0
    error_message = "dev must not create Memorystore: it is billed per hour."
  }

  assert {
    condition = alltrue([
      for db in values(local.settings.database) :
      try(db.sql.availability, "ZONAL") == "ZONAL" && contains(["db-f1-micro", "db-g1-small"], db.sql.tier)
    ]) && length(module.cloud_sql) > 0
    error_message = "dev Cloud SQL is zonal and shared-core."
  }

  assert {
    condition = length(module.cloud_sql) > 0 && alltrue([
      for db in values(local.settings.database) : db.sql.deletion_protection == false
    ])
    error_message = "dev Cloud SQL can be destroyed: deletion_protection false (pro.tftest.hcl asserts it on in pro)."
  }

  assert {
    condition     = !anytrue(values(local.service_deletion_protection))
    error_message = "dev services can be destroyed without editing the YAML."
  }

  assert {
    condition     = length(google_logging_project_bucket_config.audit_archive) == 0 && google_logging_project_bucket_config.default.retention_days <= 30
    error_message = "dev keeps no audit archive and at most 30 days of logs."
  }

  assert {
    condition = (
      !local.lb_enabled
      && length(google_compute_url_map.load_balancer) == 0
      && length(google_compute_global_address.lb_static_ip) == 0
      && length(google_compute_security_policy.cloud_armor_waf) == 0
      && length(google_project_service_identity.iap_sa) == 0
    )
    error_message = "dev has no load balancer, Cloud Armor policy or IAP: about 34 USD a month."
  }

  assert {
    condition = length(local.app_services) > 0 && alltrue([
      for key, service in local.app_services :
      service.cloudrun.ingress == "INGRESS_TRAFFIC_ALL" && !try(service.cloudrun.allow_unauthenticated, false)
      && !contains(keys(local.service_permissions[key]), "cloudrun_all")
    ])
    error_message = "dev services take traffic on run.app and still require IAM (no allUsers invoker)."
  }

  assert {
    condition     = local.settings.budget.amount >= 25
    error_message = "The dev budget is at or above the cost estimate in docs/ENVIRONMENTS.md."
  }
}

run "operators_are_scoped" {
  command = plan

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition = (
      length(local.operators) > 0 && length(local.app_services) > 0
      && length(google_cloud_run_v2_service_iam_member.operator_invokers) == length(local.app_services) * length(local.operators)
    )
    error_message = "Each operator invokes each dev service, one binding per service."
  }

  assert {
    condition = (
      length(google_service_account_iam_member.operator_act_as) == length(local.operator_runtime_accounts) * length(local.operators)
      && contains(keys(local.operator_runtime_accounts), "service/api")
      && alltrue([for binding in values(google_service_account_iam_member.operator_act_as) : binding.role == "roles/iam.serviceAccountUser"])
    )
    error_message = "Operators get serviceAccountUser on each runtime account of the stack (positive control)."
  }

  assert {
    condition = !anytrue([
      for binding in concat(
        values(google_project_iam_member.viewers),
        values(google_project_iam_member.cloudbuild_editors),
      ) : contains(["roles/iam.serviceAccountUser", "roles/run.invoker", "roles/cloudbuild.connectionAdmin"], binding.role)
    ])
    error_message = "No project-level serviceAccountUser, run.invoker or connectionAdmin for anyone in project_access."
  }
}
