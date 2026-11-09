# ===================================================================
# CLOUD SCHEDULER CONFIGURATION
# ===================================================================
# This file manages Cloud Scheduler jobs using YAML-based configuration
# Jobs are defined in settings/{workspace}.yaml under app.scheduler section

# Service Accounts for Cloud Scheduler (only when not using external SA)
resource "google_service_account" "scheduler_sa" {
  for_each = {
    for k, v in try(local.settings.scheduler, {}) : k => v
    if try(v.external_sa, null) == null
  }

  project      = local.settings.project.id
  account_id   = format("%s-%s-sch-sa", local.base_name, substr(each.key, 0, 19))
  display_name = format("Scheduler SA for %s", each.key)
}

# Grant the Scheduler Service Account permission to execute the target job (managed SAs
# only). TWO roles, and the second is not optional here.
#
# `roles/run.invoker` grants `run.jobs.run`. It does NOT grant `run.jobs.runWithOverrides`,
# and every request this file sends carries an `overrides` body, so every request is a
# runWithOverrides. A scheduler SA holding only run.invoker therefore gets a flat 403 with
# no hint as to which permission is missing:
#
#   status: PERMISSION_DENIED
#   debugInfo: "URL_ERROR-ERROR_OTHER. Original HTTP response code number = 403"
#
# Measured on a nightly database backup job, after first (wrongly) blaming the v1
# namespaces endpoint and moving it to v2. Both were true: v1 also resolves IAM against the
# project. The v2 move is still right, but this is what actually unblocked it.
#
# The comment in gcp.jobs.tf claiming run.invoker covers "run.jobs.run /
# run.jobs.runWithOverrides" is wrong, and has been corrected there.
locals {
  scheduler_invoker_roles = ["roles/run.invoker", "roles/run.jobsExecutorWithOverrides"]

  scheduler_invokers = merge([
    for k, v in try(local.settings.scheduler, {}) : {
      for role in local.scheduler_invoker_roles : "${k}/${role}" => {
        scheduler_key = k
        target_job    = v.target_job
        role          = role
      }
    } if try(v.external_sa, null) == null
  ]...)
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  for_each = local.scheduler_invokers

  project  = local.settings.project.id
  location = local.settings.region_name
  name     = try(local.settings.app.job[each.value.target_job].custom_name, format("%s-%s", local.base_name, each.value.target_job))
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.scheduler_sa[each.value.scheduler_key].email}"
}

# Cloud Scheduler Jobs
resource "google_cloud_scheduler_job" "scheduler_jobs" {
  for_each = try(local.settings.scheduler, {})

  name             = try(each.value.custom_name, format("%s-%s", local.base_name, each.key))
  description      = try(each.value.description, "Scheduler for ${each.key}")
  schedule         = each.value.schedule
  time_zone        = try(each.value.time_zone, "Etc/UTC")
  attempt_deadline = try(each.value.attempt_deadline, "320s")
  # `paused: true` in the YAML stops the trigger but keeps it, its IAM and its arguments,
  # so turning it back on is one line and not a re-creation.
  paused  = try(each.value.paused, false)
  region  = local.settings.region_name
  project = local.settings.project.id

  retry_config {
    retry_count = try(each.value.retry_count, 1)
  }

  # `job_api: v2` opts an entry into the Cloud Run **v2** endpoint. Default stays v1 so
  # nothing already scheduled changes.
  #
  # WHY IT MATTERS, measured on a nightly database backup job: the v1 endpoint is
  # `.../apis/run.googleapis.com/v1/namespaces/<project>/jobs/<job>:run`, and it resolves
  # permission against the NAMESPACE, i.e. the project. A `roles/run.invoker` binding on
  # the job itself is invisible to it. The scheduler had exactly that binding, confirmed in
  # `gcloud run jobs get-iam-policy`, and every attempt still came back
  # `PERMISSION_DENIED ... Original HTTP response code number = 403`.
  #
  # The only way to make v1 work is a project-wide run.invoker, which is why the older
  # entry here uses the default compute account. v2 checks IAM on the job resource, so a
  # per-scheduler service account that can invoke exactly one job is enough, which is the
  # posture worth having, not a workaround.
  http_target {
    http_method = "POST"
    uri = (
      try(each.value.job_api, "v1") == "v2"
      ? "https://${local.settings.region_name}-run.googleapis.com/v2/projects/${local.settings.project.id}/locations/${local.settings.region_name}/jobs/${try(local.settings.app.job[each.value.target_job].custom_name, format("%s-%s", local.base_name, each.value.target_job))}:run"
      : "https://${local.settings.region_name}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${local.settings.project.id}/jobs/${try(local.settings.app.job[each.value.target_job].custom_name, format("%s-%s", local.base_name, each.value.target_job))}:run"
    )

    oauth_token {
      service_account_email = try(each.value.external_sa, google_service_account.scheduler_sa[each.key].email)
    }

    # Cloud Run Job overrides. The two APIs spell the same field differently: v1 takes
    # snake_case through the Knative shim, v2 is a normal Google JSON API and wants
    # camelCase. Sending the wrong one is silently ignored, not rejected, which is the
    # worst of both worlds.
    body = base64encode(jsonencode(
      try(each.value.job_api, "v1") == "v2"
      ? {
        overrides = {
          containerOverrides = [
            {
              args = try(each.value.args, [])
            }
          ]
        }
      }
      : {
        overrides = {
          container_overrides = [
            {
              args = try(each.value.args, [])
            }
          ]
        }
      }
    ))
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_service_account.scheduler_sa,
    google_cloud_run_v2_job_iam_member.scheduler_invoker
  ]
}


# ===================================================================
# CLOUD SCHEDULER → CLOUD RUN SERVICES (not jobs)
# ===================================================================
# Service-targeted scheduler jobs use OIDC tokens to invoke Cloud Run services.
# Defined in settings/{workspace}.yaml under service_scheduler section.

# Service Accounts for Service Scheduler (only when not using external SA)
resource "google_service_account" "service_scheduler_sa" {
  for_each = {
    for k, v in try(local.settings.service_scheduler, {}) : k => v
    if try(v.external_sa, null) == null
  }

  project      = local.settings.project.id
  account_id   = format("%s-%s-ssch-sa", local.base_name, substr(each.key, 0, 18))
  display_name = format("Service Scheduler SA for %s", each.key)
}

# Grant Cloud Run Invoker on the target Cloud Run service
resource "google_cloud_run_v2_service_iam_member" "service_scheduler_invoker" {
  for_each = {
    for k, v in try(local.settings.service_scheduler, {}) : k => v
    if try(v.external_sa, null) == null
  }

  project  = local.settings.project.id
  location = local.settings.region_name
  name     = try(local.settings.app.service[each.value.target_service].custom_name, format("%s-%s", local.base_name, each.value.target_service))
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.service_scheduler_sa[each.key].email}"
}

# Cloud Scheduler Jobs targeting Cloud Run Services
resource "google_cloud_scheduler_job" "service_scheduler_jobs" {
  for_each = try(local.settings.service_scheduler, {})

  name             = try(each.value.custom_name, format("%s-%s", local.base_name, each.key))
  description      = try(each.value.description, "Service scheduler for ${each.key}")
  schedule         = each.value.schedule
  time_zone        = try(each.value.time_zone, "Etc/UTC")
  attempt_deadline = try(each.value.attempt_deadline, "320s")
  region           = local.settings.region_name
  project          = local.settings.project.id

  retry_config {
    retry_count = try(each.value.retry_count, 1)
  }

  http_target {
    http_method = "POST"
    uri         = "${module.cloud_run_services[each.value.target_service].cloudrun_service_url}${each.value.target_path}"

    oidc_token {
      service_account_email = try(each.value.external_sa, google_service_account.service_scheduler_sa[each.key].email)
      audience              = module.cloud_run_services[each.value.target_service].cloudrun_service_url
    }
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_service_account.service_scheduler_sa,
    google_cloud_run_v2_service_iam_member.service_scheduler_invoker,
    module.cloud_run_services
  ]
}
