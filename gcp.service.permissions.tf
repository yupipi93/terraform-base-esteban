# ===================================================================
# SERVICE ACCOUNT PROJECT-LEVEL PERMISSIONS
# ===================================================================
# This file manages project-level IAM permissions for service accounts.
# For services with external_sa (SA migration Step 1), the dedicated SA
# is referenced from google_service_account.dedicated_cloudrun_sa to
# ensure the SA exists before IAM bindings are applied.

locals {
  # Resolve the dedicated SA member for each service
  service_sa_members = {
    for key, config in local.app_services : key =>
    try(config.cloudrun.external_sa, null) != null ?
    "serviceAccount:${config.cloudrun.external_sa}" :
    format("serviceAccount:%s-%s-sa@%s.iam.gserviceaccount.com",
      local.base_name,
      try(config.name, key),
    local.settings.project.id)
  }
}

# Additional roles for service accounts
resource "google_project_iam_member" "service_additional_roles" {
  for_each = {
    for pair in flatten([
      for service_key, service in local.app_services : [
        for role in try(service.cloudrun.additional_roles, []) : {
          key          = service_key
          service_name = try(service.name, service_key)
          role         = role
        }
      ]
    ]) : "${pair.service_name}/${pair.role}" => pair
  }

  project = local.settings.project.id
  role    = each.value.role
  member  = local.service_sa_members[each.value.key]
}

# Default roles for all Cloud Run services
# Grant logging.logWriter to allow services to write logs to Cloud Logging
resource "google_project_iam_member" "service_logging_role" {
  for_each = local.app_services

  project = local.settings.project.id
  role    = "roles/logging.logWriter"
  member  = local.service_sa_members[each.key]

  depends_on = [module.cloud_run_services]
}

# Grant compute.networkUser to allow services to use VPC (Direct VPC Egress)
resource "google_project_iam_member" "service_network_role" {
  for_each = local.app_services

  project = local.settings.project.id
  role    = "roles/compute.networkUser"
  member  = local.service_sa_members[each.key]

  depends_on = [module.cloud_run_services]
}

# Grant cloudsql.client to allow services to connect to Cloud SQL
resource "google_project_iam_member" "service_cloudsql_role" {
  for_each = local.app_services

  project = local.settings.project.id
  role    = "roles/cloudsql.client"
  member  = local.service_sa_members[each.key]

  depends_on = [module.cloud_run_services]
}
