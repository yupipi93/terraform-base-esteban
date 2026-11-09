locals {
  # Access lists read from the settings YAML files
  viewers   = try(local.settings.project_access.viewers, [])
  operators = try(local.settings.project_access.operators, [])

  # Viewers and operators merged for the basic viewer role
  all_viewers_list = setunion(local.viewers, local.operators)
}

resource "google_project_iam_member" "viewers" {
  for_each = toset(local.all_viewers_list)

  project = local.settings.project.id
  role    = "roles/viewer"
  member  = each.value
}

# Operators invoke each Cloud Run service of this stack, not every service in the
# project.
resource "google_cloud_run_v2_service_iam_member" "operator_invokers" {
  for_each = {
    for pair in setproduct(keys(local.app_services), local.operators) :
    "${pair[0]}/${pair[1]}" => { service_key = pair[0], member = pair[1] }
  }

  project  = local.settings.project.id
  location = local.service_regions[each.value.service_key]
  name     = module.cloud_run_services[each.value.service_key].cloudrun_name
  role     = "roles/run.invoker"
  member   = each.value.member
}

# Operators act as the runtime accounts this stack creates for its services and
# jobs, and no other. A project-wide serviceAccountUser would also cover
# run-cloudbuild-sa, which holds run.admin and serviceAccountUser on the
# project. An external_sa or an external job account is not managed here: its
# owner grants actAs on it.
locals {
  operator_runtime_accounts = merge(
    {
      for key, config in local.app_services : "service/${key}" => module.cloud_run_services[key].sa_id
      if try(config.cloudrun.external_sa, null) == null
    },
    {
      for key, account in google_service_account.cloudrun_job : "job/${key}" => account.name
    }
  )
}

resource "google_service_account_iam_member" "operator_act_as" {
  for_each = {
    for pair in setproduct(keys(local.operator_runtime_accounts), local.operators) :
    "${pair[0]}/${pair[1]}" => { account_key = pair[0], member = pair[1] }
  }

  service_account_id = local.operator_runtime_accounts[each.value.account_key]
  role               = "roles/iam.serviceAccountUser"
  member             = each.value.member
}

resource "google_project_iam_custom_role" "job_operator_overrides" {
  count = length(local.operators) > 0 ? 1 : 0

  role_id     = "CloudRunJobOperatorWithOverrides"
  title       = "Cloud Run Job Operator (With Overrides)"
  description = "Runs Cloud Run Jobs with overrides."

  permissions = [
    "run.jobs.run",
    "run.jobs.runWithOverrides",
    "run.executions.get",
    "run.executions.list",
    "run.locations.list"
  ]
}

resource "google_project_iam_member" "job_operators_binding" {
  for_each = toset(local.operators)

  project = local.settings.project.id
  role    = google_project_iam_custom_role.job_operator_overrides[0].id
  member  = each.value
}

# Cancel builds. Creating, editing or running a trigger by hand also needs actAs
# on run-cloudbuild-sa, which operators do not get: that would hand them its
# run.admin. Pushes and tags still start the builds.
# No connectionAdmin: it can fetch a read-write token for every linked
# repository and delete or repoint the connection Terraform manages.
resource "google_project_iam_member" "cloudbuild_editors" {
  for_each = toset(local.operators)

  project = local.settings.project.id
  role    = "roles/cloudbuild.builds.editor"
  member  = each.value
}


# Services behind IAP, directly (cloudrun.iap.enabled) or through a load balancer
# rule with iap.enabled. The IAP service agent and its wait exist only when one does.
locals {
  iap_invoker_services = {
    for k, v in local.app_services : k => v
    if try(v.cloudrun.iap.enabled, false) == true || length([
      for rule in try(v.loadbalancer.rules, []) : rule
      if try(rule.iap.enabled, false) == true
    ]) > 0
  }
  iap_identity_enabled = length(local.iap_invoker_services) > 0
}

# 1. Service identity (the IAP service agent)
resource "google_project_service_identity" "iap_sa" {
  count    = local.iap_identity_enabled ? 1 : 0
  provider = google-beta
  project  = local.settings.project.id
  service  = "iap.googleapis.com"
}

# 2. Safety wait (60s for the service agent to propagate)
resource "time_sleep" "wait_for_iap_sa" {
  count           = local.iap_identity_enabled ? 1 : 0
  create_duration = "60s"
  depends_on      = [google_project_service_identity.iap_sa]
}

# 3. Invoker permission PER SERVICE (only services with IAP enabled)

resource "google_cloud_run_service_iam_member" "iap_invoker_services" {
  for_each = local.iap_invoker_services

  project  = local.settings.project.id
  location = try(each.value.cloudrun.region, local.settings.region_name)
  service  = try(each.value.custom_name, null) != null ? each.value.custom_name : "${local.base_name}-${try(each.value.name, each.key)}"

  role   = "roles/run.invoker"
  member = "serviceAccount:${google_project_service_identity.iap_sa[0].email}"

  depends_on = [time_sleep.wait_for_iap_sa, module.cloud_run_services]
}

# 4. ACCESS permission (IAP-Secured Web App User)
# Lets specific users and groups reach the application through IAP
resource "google_iap_web_cloud_run_service_iam_member" "iap_access_members" {
  for_each = {
    for pair in flatten([
      for service_key, service in local.app_services : [
        for member in try(service.cloudrun.iap.members, []) : {
          key         = "${service_key}-${member}"
          service_key = service_key
          member      = member
        }
      ]
    ]) : pair.key => pair
  }

  project                = local.settings.project.id
  location               = try(local.app_services[each.value.service_key].cloudrun.region, local.settings.region_name)
  cloud_run_service_name = try(local.app_services[each.value.service_key].custom_name, null) != null ? local.app_services[each.value.service_key].custom_name : "${local.base_name}-${try(local.app_services[each.value.service_key].name, each.value.service_key)}"
  role                   = "roles/iap.httpsResourceAccessor"
  member                 = each.value.member

  depends_on = [module.cloud_run_services]
}
