# ===================================================================
# CLOUD RUN SERVICES CONFIGURATION
# ===================================================================
# This file manages Cloud Run services with support for:
# - Environment variables and secrets
# - GCS volume mounting
# - VPC access and networking
# - IAM permissions

# ===================================================================
# LOCAL VARIABLES FOR CLOUD RUN CONFIGURATION
# ===================================================================

locals {
  # Normalize app.service to empty map when null (no Cloud Run services declared)
  app_services = try(local.settings.app.service, {})


  # Extract service name for each app
  run_service_names = {
    for key, config in local.app_services : key => try(config.name, key)
  }

  # Determine region for each service
  service_regions = {
    for key, config in local.app_services : key => try(config.cloudrun.region, local.settings.region_name)
  }

  # Protected from destroy by default in pro only
  service_deletion_protection = {
    for key, config in local.app_services : key => try(config.cloudrun.deletion_protection, local.workspace == "pro")
  }

  # Extract environment variables per service from YAML configuration
  service_env_vars = {
    for key, config in local.app_services : key => [
      for env_var in try(config.cloudrun.env, []) : {
        name = env_var.name
        value = tostring(
          env_var.name == "DB_HOST" && try(config.cloudrun.db_host_from_database, null) != null
          ? try(module.cloud_sql[config.cloudrun.db_host_from_database].db_engine_private_ip, env_var.value)
          : env_var.value
        )
      }
    ]
  }

  # Extract secret environment variables per service
  service_secret_env_vars = {
    for key, config in local.app_services : key =>
    try(config.cloudrun.secret_env, null) != null ? [
      for secret in config.cloudrun.secret_env : {
        name    = secret.var_name
        secret  = try(secret.create_secret, true) != false ? google_secret_manager_secret.run_secrets["${local.base_name}-${local.run_service_names[key]}-${secret.name}"].secret_id : (try(secret.raw_name, false) ? secret.name : "${local.base_name}-${local.run_service_names[key]}-${secret.name}")
        project = local.settings.project.id
        version = try(secret.version, "latest")
      }
    ] : []
  }

  # Extract secret volumes per service
  service_secret_volumes = {
    for key, config in local.app_services : key =>
    try(config.cloudrun.secret_volume, null) != null ? {
      for volume in config.cloudrun.secret_volume : volume.name => {
        mount_path = volume.mount_path
        secret = {
          secret       = google_secret_manager_secret.run_secrets["${local.base_name}-${local.run_service_names[key]}-${volume.name}"].secret_id
          default_mode = try(volume.default_mode, "0444")
          items = {
            path    = volume.file_name
            version = try(volume.version, "latest")
          }
        }
      }
    } : {}
  }

  # Extract GCS volumes per service
  # Supports bucket_name override for imported services with pre-existing buckets
  service_gcs_volumes = {
    for key, config in local.app_services : key =>
    try(config.cloudrun.gcs_volume, null) != null ? {
      for volume in config.cloudrun.gcs_volume : volume.name => {
        mount_path = volume.mount_path
        gcs = {
          storage_bucket = try(volume.bucket_name, null) != null ? volume.bucket_name : (try(volume.create_gcs, false) ? module.cloudrun_gcs_volumes["${key}-${volume.name}"].bucket_name : "${local.base_name_medium}-${local.run_service_names[key]}-${volume.name}")
          read_only      = try(volume.read_only, false)
        }
      }
    } : {}
  }

  # Pre-existing secret volumes (for imported services with secrets not managed by Terraform)
  # These reference Secret Manager secrets directly by secret_id, bypassing the standard naming
  service_existing_secret_volumes = {
    for key, config in local.app_services : key => {
      for volume in try(config.cloudrun.existing_secret_volume, []) : volume.name => {
        mount_path = volume.mount_path
        secret = {
          secret       = volume.secret_id
          default_mode = try(volume.default_mode, "0444")
          items = {
            path    = volume.file_name
            version = try(volume.version, "latest")
          }
        }
      }
    }
  }

  # Combine all volume types per service
  service_all_volumes = {
    for key, config in local.app_services : key => merge(
      local.service_secret_volumes[key],
      local.service_gcs_volumes[key],
      local.service_existing_secret_volumes[key]
    )
  }



  # Launch stage (BETA required for GCS volumes)
  service_launch_stages = {
    for key, config in local.app_services : key => "GA"
  }

  # Build permissions per service
  service_permissions = {
    for key, config in local.app_services : key => merge(
      {
        cloudbuild = {
          account     = "serviceAccount:${local.project_number}@cloudbuild.gserviceaccount.com"
          permissions = ["roles/run.admin"]
        }
      },
      try(config.cloudrun.allow_unauthenticated, false) ? {
        cloudrun_all = {
          account     = "allUsers"
          permissions = ["roles/run.invoker"]
        }
      } : {}
    )
  }
}

# ===================================================================
# GCS BUCKETS FOR CLOUD RUN VOLUMES
# ===================================================================

locals {
  # Extract GCS volume requirements
  gcs_volume_requirements = flatten([
    for service_key, service_config in local.app_services : [
      for volume in try(service_config.cloudrun.gcs_volume, []) : {
        key           = "${service_key}-${volume.name}"
        service_key   = service_key
        service_name  = local.run_service_names[service_key]
        volume_name   = volume.name
        volume_config = volume
      }
      if try(volume.create_gcs, false)
    ]
  ])

  # Convert to map for for_each
  gcs_volumes_to_create = {
    for req in local.gcs_volume_requirements : req.key => req
  }

  # Map bucket names for easy reference
  gcs_bucket_names = {
    for key, req in local.gcs_volumes_to_create : key =>
    "${local.base_name_medium}-${req.service_name}-${req.volume_name}"
  }

  # Service to bucket mapping for IAM
  bucket_service_mapping = {
    for key, req in local.gcs_volumes_to_create : key => req.service_name
  }


}

# Create GCS buckets for Cloud Run volumes
module "cloudrun_gcs_volumes" {
  for_each = local.gcs_volumes_to_create

  source = "./modules/gcp_storage_v2.7"

  base_name      = local.gcs_bucket_names[each.key]
  region_name    = local.settings.region_name
  gcp_project_id = local.settings.project.id

  # Basic bucket configuration
  class                          = "REGIONAL"
  force_destroy                  = false
  enable_versioning              = false
  uniform_bucket_level_access    = true
  authoritative_permissions      = false
  soft_delete_retention_duration = 604800 # 7 days

  # No initial permissions - set separately to avoid circular dependency
  permissions = {}
}

# IAM permissions for Cloud Run services to access their GCS buckets
resource "google_storage_bucket_iam_member" "cloudrun_gcs_access" {
  for_each = module.cloudrun_gcs_volumes

  bucket = each.value.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.base_name}-${local.bucket_service_mapping[each.key]}-sa@${local.settings.project.id}.iam.gserviceaccount.com"

  depends_on = [
    module.cloud_run_services,
    module.cloudrun_gcs_volumes
  ]
}

# ===================================================================
# CLOUD RUN SERVICES
# ===================================================================

module "cloud_run_services" {
  for_each = local.app_services

  source = "./modules/gcp_cloudrun_v6.6"

  # If custom_name is set, use the exact service name; otherwise use standard naming
  base_name           = try(each.value.custom_name, null) != null ? each.value.custom_name : "${local.base_name}-${local.run_service_names[each.key]}"
  gcp_project_id      = local.settings.project.id
  gcp_project_sys_id  = local.settings.project_sys.id
  region_name         = local.service_regions[each.key]
  deletion_protection = local.service_deletion_protection[each.key]

  # Service account: use external SA if specified, otherwise create a dedicated one
  service_account = try(each.value.cloudrun.external_sa, null) != null ? {
    name     = each.value.cloudrun.external_sa
    external = true
    } : {
    name     = "${local.base_name}-${local.run_service_names[each.key]}-sa"
    external = false
  }

  # Cloud Run configuration
  cloudrun = {
    execution_environment = try(each.value.cloudrun.execution_environment, "EXECUTION_ENVIRONMENT_GEN2")
    concurrency           = try(each.value.cloudrun.concurrency, 100)
    # Without a load balancer the service has no other way in, so it accepts all
    # traffic and stays private behind IAM unless allow_unauthenticated is set.
    ingress      = try(each.value.cloudrun.ingress, local.lb_enabled ? "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" : "INGRESS_TRAFFIC_ALL")
    timeout      = try(each.value.cloudrun.timeout, "3600s")
    launch_stage = local.service_launch_stages[each.key]

    # Same short-name rule as the jobs: a name without ":" is an instance of this project,
    # in region_name, where gcp.sql.tf creates them.
    cloud_sql_instances_mount = try(each.value.cloudrun.cloud_sql_instances_mount, null) == null ? null : [
      for instance in each.value.cloudrun.cloud_sql_instances_mount :
      length(regexall(":", instance)) > 0 ? instance : "${local.settings.project.id}:${local.settings.region_name}:${instance}"
    ]

    containers = [
      {
        name  = local.run_service_names[each.key]
        image = "us-docker.pkg.dev/cloudrun/container/hello:latest"

        # Pass-through so a service can override the image's ENTRYPOINT/CMD from YAML.
        # Observed in practice: Cloud Run injects PORT=<container_port>, and an image whose
        # entrypoint runs an app server behind its own internal proxy may read that PORT
        # and try to bind the port the proxy already holds: EADDRINUSE, crash loop, and a
        # 502 from the proxy. `command`/`args` let you adjust the startup (e.g. unset PORT)
        # for that one service without forking the image.
        command = try(each.value.cloudrun.command, null)
        args    = try(each.value.cloudrun.args, null)

        ports = {
          container_port = try(each.value.cloudrun.container_port, 8080)
        }

        resources = {
          # `cpu: 1` renders as "1000m", which is what Cloud Run keeps for almost every
          # service. Some services report "1" back no matter how many times "1000m" is
          # written to them, so every plan shows the same cosmetic "1" -> "1000m" change
          # forever and it survives an apply. Neither region nor execution environment
          # explains it. Rather than guess the rule, `cpu_limit` lets a service state the
          # exact string GCP stores.
          cpu               = try(each.value.cloudrun.cpu_limit, format("%dm", try(each.value.cloudrun.cpu, 2) * 1000))
          memory            = try(each.value.cloudrun.ram, "2048Mi")
          startup_cpu_boost = try(each.value.cloudrun.startup_cpu_boost, true)
          # true = CPU only while a request is served (request-based billing); work
          # left running after the response is throttled. Pro keeps CPU allocated
          # so its warm instances can run background work.
          cpu_idle = try(each.value.cloudrun.cpu_idle, local.workspace != "pro")
        }

        # Environment variables
        envs = local.service_env_vars[each.key]

        # Secret environment variables
        secrets = local.service_secret_env_vars[each.key]

        # All volumes (secrets + GCS + existing secrets) from settings configuration
        volumes = local.service_all_volumes[each.key]

        # Probes (optional, pass-through from YAML)
        startup_probe  = try(each.value.cloudrun.startup_probe, null)
        liveness_probe = try(each.value.cloudrun.liveness_probe, null)
      }
    ]

    # VPC access configuration
    vpc_access = try(each.value.cloudrun.vpc_access_enabled, local.network_enabled) ? {
      egress = try(each.value.cloudrun.vpc.egress, "ALL_TRAFFIC")
      network_interfaces = {
        network    = try(each.value.cloudrun.vpc.network, "${local.base_name}-vpc")
        subnetwork = try(each.value.cloudrun.vpc.subnetwork, "${local.base_name}-vpc--services")
        tags       = try(each.value.cloudrun.vpc.tags, ["cloud-run"])
      }
    } : null

    # Autoscaling configuration
    autoscaling = {
      min = try(each.value.cloudrun.min_instances, 0)
      max = try(each.value.cloudrun.max_instances, 10)
    }

    iap_enabled = try(each.value.cloudrun.iap.enabled, false)

    # Deploys are checked against the policy in gcp.binary_auth.tf.
    binary_authorization = local.enable_binary_auth
  }

  # Permissions
  permissions = local.service_permissions[each.key]

  # Dependencies
  depends_on = [
    google_secret_manager_secret_version.run_secrets_version,
    module.artifact_registry,
    module.network
  ]

  # Monitoring configuration
  monitoring = merge(
    try(local.settings.monitoring.cloudrun, {}),
    {
      notification_channels = [google_monitoring_notification_channel.security_alerts.name]
      repo_iac              = local.settings.iac.repo
    }
  )
}

# ===================================================================
# EXISTING SECRET VOLUME IAM
# ===================================================================
# Grant dedicated SAs access to pre-existing secrets referenced via
# existing_secret_volume. The Cloud Run module only handles secrets
# declared in container.secrets, not volume-mounted ones.

locals {
  existing_secret_volume_iam = {
    for pair in flatten([
      for key, config in local.app_services : [
        for volume in try(config.cloudrun.existing_secret_volume, []) : {
          key         = "${key}/${volume.secret_id}"
          service_key = key
          secret_id   = volume.secret_id
        }
      ]
      if try(config.cloudrun.external_sa, null) == null
    ]) : pair.key => pair
  }

  existing_gcs_volume_iam = {
    for pair in flatten([
      for key, config in local.app_services : [
        for volume in try(config.cloudrun.gcs_volume, []) : {
          key         = "${key}/${volume.bucket_name}"
          service_key = key
          bucket_name = volume.bucket_name
        }
        if try(volume.bucket_name, null) != null
      ]
      if try(config.cloudrun.external_sa, null) == null
    ]) : pair.key => pair
  }
}

resource "google_secret_manager_secret_iam_member" "dedicated_sa_secret_access" {
  for_each = local.existing_secret_volume_iam

  project   = local.settings.project.id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member = format("serviceAccount:%s-%s-sa@%s.iam.gserviceaccount.com",
    local.base_name,
    local.run_service_names[each.value.service_key],
  local.settings.project.id)

  depends_on = [module.cloud_run_services]
}

resource "google_storage_bucket_iam_member" "dedicated_sa_gcs_access" {
  for_each = local.existing_gcs_volume_iam

  bucket = each.value.bucket_name
  role   = "roles/storage.objectAdmin"
  member = format("serviceAccount:%s-%s-sa@%s.iam.gserviceaccount.com",
    local.base_name,
    local.run_service_names[each.value.service_key],
  local.settings.project.id)

  depends_on = [module.cloud_run_services]
}
