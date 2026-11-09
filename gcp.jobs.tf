# ===================================================================
# GOOGLE CLOUD RUN V2 JOBS CONFIGURATION
# ===================================================================
# This file manages Cloud Run v2 Jobs using YAML-based configuration
# Jobs are defined in settings/{workspace}.yaml under app.job section
# Each job automatically gets:
# - Conditional service account creation
# - Environment variables and secrets management
# - VPC integration and Cloud SQL connections
# - Dynamic container configuration

# Service Accounts for Cloud Run Jobs
resource "google_service_account" "cloudrun_job" {
  for_each = {
    for k, v in try(local.settings.app.job, {}) : k => v
    if try(v.service_account.external, false) == false
  }

  project      = local.settings.project.id
  account_id   = format("%s-%s-job-sa", local.base_name, try(each.value.name, each.key))
  display_name = format("Service Account for Job %s", try(each.value.custom_name, format("%s-%s", local.base_name, try(each.value.name, each.key))))

  depends_on = [
    google_project_service.enabled_apis
  ]
}

# Wait for IAM propagation before creating/updating jobs
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on = [
    google_service_account.cloudrun_job,
    module.cloud_run_services,
    # A job's own secret grants must be in here too, or the 30s below starts before they
    # exist and does nothing for them. Observed in practice: a job created a few seconds
    # after its secretAccessor binding can have its revision refused by Cloud Run
    # ("Permission denied on secret ... The service account used must be granted the
    # 'Secret Manager Secret Accessor' role") on a grant terraform had just made in the
    # same apply. A second apply succeeds with no changes to anything. If you add a
    # root-level secret grant for a job, list it here.
    # Also depend on root level IAM bindings
    # google_secret_manager_secret_iam_member.run_secrets_access
  ]

  create_duration = "30s"
}

# Cloud Run v2 Jobs
resource "google_cloud_run_v2_job" "jobs" {
  for_each = try(local.settings.app.job, {})

  project             = local.settings.project.id
  name                = try(each.value.custom_name, format("%s-%s", local.base_name, try(each.value.name, each.key)))
  location            = local.settings.region_name
  launch_stage        = try(each.value.job-config.launch_stage, "GA")
  deletion_protection = try(each.value.job-config.deletion_protection, local.workspace == "pro")

  labels = local.common_labels

  # Every image update is checked against the policy in gcp.binary_auth.tf. A
  # job-config.image that no pipeline has signed is refused once the policy
  # enforces.
  dynamic "binary_authorization" {
    for_each = local.enable_binary_auth ? [1] : []
    content {
      use_default = true
    }
  }

  template {
    parallelism = try(each.value.job-config.parallelism, 1)
    task_count  = try(each.value.job-config.task_count, 1)

    template {
      max_retries     = try(each.value.job-config.max_retries, 3)
      timeout         = try(each.value.job-config.timeout, "3600s")
      service_account = try(each.value.service_account.external, false) ? each.value.service_account.name : google_service_account.cloudrun_job[each.key].email

      dynamic "containers" {
        for_each = try(each.value.job-config.containers, [
          {
            name = try(each.value.name, each.key)
            # Use specified image or default to hello world.
            # If image doesn't look like a URL (no dots in first segment), prepend registry host.
            image = (
              try(each.value.job-config.image, null) == null ?
              "us-docker.pkg.dev/cloudrun/container/hello:latest" :
              (
                length(regexall("\\.", split("/", each.value.job-config.image)[0])) > 0 ?
                each.value.job-config.image :
                "${local.registry_host}/${each.value.job-config.image}"
              )
            )
            command     = try(each.value.job-config.command, null)
            args        = try(each.value.job-config.args, null)
            working_dir = try(each.value.job-config.working_dir, null)
            envs        = []
            secrets     = []
            volumes     = {}
            ports       = null
            resources = {
              cpu    = try(each.value.job-config.cpu, 1)
              memory = try(each.value.job-config.ram, "512Mi")
            }
          }
        ])

        content {
          name        = containers.value.name
          image       = containers.value.image
          command     = containers.value.command
          args        = containers.value.args
          working_dir = containers.value.working_dir

          # Default environment variables
          dynamic "env" {
            for_each = concat([
              {
                name  = "SERVICE_NAME"
                value = try(each.value.name, each.key)
              },
              {
                name  = "REGION"
                value = local.settings.region_name
              },
              {
                name  = "PROJECT"
                value = local.settings.project.id
              }
              ],
              # Custom environment variables from settings
              try(each.value.job-config.env, []),
              # Container-specific environment variables
              try(containers.value.envs, [])
            )

            content {
              name  = env.value.name
              value = tostring(env.value.value)
            }
          }

          # Secret environment variables
          dynamic "env" {
            for_each = concat(
              try(each.value.job-config.secret_env, []),
              try(containers.value.secrets, [])
            )

            content {
              name = env.value.var_name != null ? env.value.var_name : env.value.name

              value_source {
                secret_key_ref {
                  secret  = try(env.value.create_secret, true) != false ? google_secret_manager_secret.run_secrets[try(env.value.raw_name, false) ? env.value.name : "${local.base_name}-${try(each.value.name, each.key)}-${env.value.name}"].secret_id : (try(env.value.raw_name, false) ? env.value.name : "${local.base_name}-${try(each.value.name, each.key)}-${env.value.name}")
                  version = try(env.value.version, "latest")
                }
              }
            }
          }

          # Cloud Storage volume mounts
          dynamic "volume_mounts" {
            for_each = merge(
              try(containers.value.volumes, {}),
              try(each.value.job-config.secret_volume, null) != null ? {
                for volume in each.value.job-config.secret_volume : "${containers.value.name}_${volume.name}" => {
                  mount_path = volume.mount_path
                }
              } : {}
            )

            content {
              name       = volume_mounts.key
              mount_path = volume_mounts.value.mount_path
            }
          }

          # Cloud SQL instances mount (applied only to first container)
          dynamic "volume_mounts" {
            for_each = alltrue([
              try(each.value.job-config.cloud_sql_instances_mount, null) != null,
              containers.value.name == try(each.value.job-config.containers[0].name, try(each.value.name, each.key))
            ]) ? { cloudsql = "cloudsql" } : {}

            content {
              name       = "cloudsql"
              mount_path = "/cloudsql"
            }
          }

          resources {
            limits = {
              cpu    = format("%dm", try(containers.value.resources.cpu, 1) * 1000)
              memory = try(containers.value.resources.memory, "512Mi")
            }
          }

          # Container ports (optional for jobs)
          dynamic "ports" {
            for_each = containers.value.ports != null ? ["dummy"] : []

            content {
              name           = containers.value.ports.name
              container_port = containers.value.ports.container_port
            }
          }
        }
      }

      # VPC Access configuration
      dynamic "vpc_access" {
        for_each = try(each.value.job-config.vpc_access, null) != null ? ["dummy"] : (
          try(each.value.job-config.enable_vpc_access, local.network_enabled) ? ["dummy"] : []
        )

        content {
          connector = try(each.value.job-config.vpc_access.connector, null)
          egress    = try(each.value.job-config.vpc_access.egress, "ALL_TRAFFIC")

          dynamic "network_interfaces" {
            for_each = try(each.value.job-config.vpc_access.network_interfaces, null) != null ? ["dummy"] : (
              try(each.value.job-config.enable_vpc_access, local.network_enabled) ? ["dummy"] : []
            )

            content {
              network    = try(each.value.job-config.vpc_access.network_interfaces.network, format("%s-vpc", local.base_name))
              subnetwork = try(each.value.job-config.vpc_access.network_interfaces.subnetwork, format("%s-vpc--services", local.base_name))
              tags       = try(each.value.job-config.vpc_access.network_interfaces.tags, ["cloud-run-job"])
            }
          }
        }
      }

      # Cloud SQL volumes
      dynamic "volumes" {
        for_each = try(each.value.job-config.cloud_sql_instances_mount, null) != null ? { cloudsql = "cloudsql" } : {}

        content {
          name = "cloudsql"
          cloud_sql_instance {
            instances = [
              for instance in each.value.job-config.cloud_sql_instances_mount :
              length(regexall(":", instance)) > 0 ? instance : "${local.settings.project.id}:${local.settings.region_name}:${instance}"
            ]
          }
        }
      }

      # Secret volumes
      dynamic "volumes" {
        for_each = try(each.value.job-config.secret_volume, null) != null ? {
          for volume in each.value.job-config.secret_volume : "${try(each.value.job-config.containers[0].name, try(each.value.name, each.key))}_${volume.name}" => volume
        } : {}

        content {
          name = volumes.key
          secret {
            secret = (
              try(volumes.value.create_secret, true) != false
              ? google_secret_manager_secret.run_secrets[
                try(volumes.value.raw_name, false)
                ? volumes.value.name
                : "${local.base_name}-${try(each.value.name, each.key)}-${volumes.value.name}"
              ].secret_id
              : (
                try(volumes.value.raw_name, false)
                ? "projects/${local.settings.project.id}/secrets/${volumes.value.name}"
                : "projects/${local.settings.project.id}/secrets/${local.base_name}-${try(each.value.name, each.key)}-${volumes.value.name}"
              )
            )
            default_mode = try(volumes.value.default_mode, "0444")
            items {
              path    = volumes.value.file_name
              version = try(volumes.value.version, "latest")
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_service_account.cloudrun_job,
    google_secret_manager_secret_version.run_secrets_version,
    module.network,
    module.cloud_sql,
    module.cloud_run_services,
    time_sleep.wait_for_iam_propagation
  ]

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].template[0].containers[0].image,
      template[0].template[0].containers[1].image,
      template[0].template[0].containers[2].image,
      template[0].template[0].containers[3].image,
      template[0].template[0].containers[4].image,
      template[0].template[0].containers[5].image,
      template[0].template[0].containers[6].image,
      template[0].template[0].containers[7].image,
      template[0].template[0].containers[8].image,
      template[0].template[0].containers[9].image,
    ]
  }
}

# ===================================================================
# JOB INVOKERS (YAML: app.job.<key>.invokers)
# ===================================================================
# Principals allowed to trigger executions of a job. NOTE: this grants
# `roles/run.invoker`, which covers `run.jobs.run` and NOT `run.jobs.runWithOverrides`
# (a common source of confusion). A caller that passes container overrides (Cloud Scheduler always does; see
# gcp.scheduler.tf) additionally needs `roles/run.jobsExecutorWithOverrides`. Supports the same
# member shortcuts as the Firestore permissions block:
#   - "cloudrun:<service>"     → the service's dedicated runtime SA
#   - "cloudrun_job:<job>"     → another job's dedicated SA
#   - any literal IAM member ("serviceAccount:...", "user:...", ...)
# Example (settings/{workspace}.yaml):
#   app:
#     job:
#       my-tasks:
#         invokers:
#           - "cloudrun:my-service"

locals {
  # Two roles per member, for the reason spelled out in gcp.scheduler.tf: `roles/run.invoker`
  # covers `run.jobs.run` and stops there. Anyone passing `--args` (Cloud Scheduler always,
  # and a human debugging with `gcloud run jobs execute --args=...`) is making a
  # runWithOverrides call and gets a bare 403 without the second role. Measured twice in one
  # afternoon, once from each direction.
  job_invoker_roles = ["roles/run.invoker", "roles/run.jobsExecutorWithOverrides"]

  job_invokers = {
    for pair in flatten([
      for job_key, job in try(local.settings.app.job, {}) : [
        for member in try(job.invokers, []) : [
          for role in local.job_invoker_roles : {
            key     = "${job_key}/${member}/${role}"
            job_key = job_key
            role    = role
            member = (
              startswith(member, "cloudrun:")
              ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun:")}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
              : startswith(member, "cloudrun_job:")
              ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun_job:")}-job-sa@${local.settings.project.id}.iam.gserviceaccount.com"
              : member
            )
          }
        ]
      ]
    ]) : pair.key => pair
  }
}

# ===================================================================
# JOB DEPLOYERS (YAML: app.job.<key>.deployers)
# ===================================================================
# Principals allowed to UPDATE a job: in practice, to point it at a new image.
#
# Why this exists at all, since GCP here is Terraform-only: the image is deliberately
# inside this resource's `ignore_changes` (see the lifecycle block above), because an image
# is an artifact and not infrastructure. The consequence is easy to miss (observed in
# practice): a `terraform apply` that changes the image tag in YAML reports
# «0 to change» and the job keeps running the old one. Cloud Run resolves a tag to a digest
# when the job is DEPLOYED, not when it runs, so pushing `:latest` changes nothing by
# itself. Somebody has to run `gcloud run jobs update --image`, and that somebody needs
# `roles/run.developer` plus `actAs` on the job's own service account.
#
# Scoped per job on purpose, rather than a project-wide run.developer: a deploy agent
# should be able to redeploy the jobs it builds images for, and nothing else.
#
# Same member shortcuts as `invokers`.
locals {
  job_deployers = {
    for pair in flatten([
      for job_key, job in try(local.settings.app.job, {}) : [
        for member in try(job.deployers, []) : {
          key     = "${job_key}/${member}"
          job_key = job_key
          member = (
            startswith(member, "cloudrun:")
            ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun:")}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
            : startswith(member, "cloudrun_job:")
            ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun_job:")}-job-sa@${local.settings.project.id}.iam.gserviceaccount.com"
            : member
          )
        }
      ]
    ]) : pair.key => pair
  }
}

resource "google_cloud_run_v2_job_iam_member" "job_deployers" {
  for_each = local.job_deployers

  project  = local.settings.project.id
  location = local.settings.region_name
  name     = google_cloud_run_v2_job.jobs[each.value.job_key].name
  role     = "roles/run.developer"
  member   = each.value.member

  depends_on = [google_cloud_run_v2_job.jobs]
}

# `run.developer` on the job is not enough on its own: deploying a revision that runs AS a
# service account requires `iam.serviceAccountUser` on THAT account. Without it the update
# fails with a message about the caller, not about the runtime identity, which sends you
# looking at the wrong principal.
resource "google_service_account_iam_member" "job_deployer_act_as" {
  for_each = {
    for k, v in local.job_deployers : k => v
    if try(local.settings.app.job[v.job_key].service_account.external, false) == false
  }

  service_account_id = google_service_account.cloudrun_job[each.value.job_key].name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value.member
}

# ===================================================================
# JOB VIEWERS (YAML: app.job.<key>.viewers)
# ===================================================================
# Principals allowed to READ a job, e.g. its latest execution. Neither invoker role has
# `run.jobs.get`, so a caller that wants to start a job only when it is idle (e.g. a
# webhook) needs this as well. Same member shortcuts as `invokers`.
locals {
  job_viewers = {
    for pair in flatten([
      for job_key, job in try(local.settings.app.job, {}) : [
        for member in try(job.viewers, []) : {
          key     = "${job_key}/${member}"
          job_key = job_key
          member = (
            startswith(member, "cloudrun:")
            ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun:")}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
            : startswith(member, "cloudrun_job:")
            ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun_job:")}-job-sa@${local.settings.project.id}.iam.gserviceaccount.com"
            : member
          )
        }
      ]
    ]) : pair.key => pair
  }
}

resource "google_cloud_run_v2_job_iam_member" "job_viewers" {
  for_each = local.job_viewers

  project  = local.settings.project.id
  location = local.settings.region_name
  name     = google_cloud_run_v2_job.jobs[each.value.job_key].name
  role     = "roles/run.viewer"
  member   = each.value.member

  depends_on = [google_cloud_run_v2_job.jobs]
}

resource "google_cloud_run_v2_job_iam_member" "job_invokers" {
  for_each = local.job_invokers

  project  = local.settings.project.id
  location = local.settings.region_name
  name     = google_cloud_run_v2_job.jobs[each.value.job_key].name
  role     = each.value.role
  member   = each.value.member

  depends_on = [
    google_cloud_run_v2_job.jobs,
    module.cloud_run_services
  ]
}
