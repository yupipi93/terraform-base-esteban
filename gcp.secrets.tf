# Create secrets for each service
locals {
  # Create a list of all environment variable secrets
  env_secrets = flatten([
    for service_key, service_config in local.app_services : [
      for secret in try(service_config.cloudrun.secret_env, []) : {
        key          = "${local.base_name}-${service_config.name}-${secret.name}"
        service_name = service_config.name
        secret_name  = secret.name
        type         = "env"
      }
      if try(secret.create_secret, true) != false
    ]
  ])

  # Create a list of all volume secrets
  volume_secrets = flatten([
    for service_key, service_config in local.app_services : [
      for secret in try(service_config.cloudrun.secret_volume, []) : {
        key          = "${local.base_name}-${service_config.name}-${secret.name}"
        service_name = service_config.name
        secret_name  = secret.name
        type         = "volume"
      }
    ]
  ])

  # Combine both types of secrets
  service_secrets = concat(local.env_secrets, local.volume_secrets)

  # Convert to map for for_each
  secrets_map = { for item in local.service_secrets : item.key => item }
}

# Create Secret Manager secrets
resource "google_secret_manager_secret" "run_secrets" {
  for_each = local.secrets_map

  project   = local.settings.project.id
  secret_id = each.key

  labels = local.common_labels

  replication {
    user_managed {
      replicas {
        location = local.settings.region_name
      }
    }
  }
}

# Placeholder versions. A key present in secrets/<workspace>/<service>.enc.yaml
# is created by run_secrets_sops instead, and Terraform keeps that value.
resource "google_secret_manager_secret_version" "run_secrets_version" {
  for_each = local.secrets_placeholder

  secret      = google_secret_manager_secret.run_secrets[each.key].id
  secret_data = "PLACEHOLDER_VALUE_TO_BE_REPLACED"

  # Allow external management of secret values
  lifecycle {
    ignore_changes = [secret_data]
  }

  depends_on = [
    google_secret_manager_secret.run_secrets
  ]
}

resource "google_secret_manager_secret_version" "run_secrets_sops" {
  for_each = local.secrets_from_sops

  secret      = google_secret_manager_secret.run_secrets[each.key].id
  secret_data = data.sops_file.service[each.value.service_name].data[each.value.secret_name]

  depends_on = [
    google_secret_manager_secret.run_secrets
  ]
}

# Grant Cloud Run service accounts access to their respective secrets
resource "google_secret_manager_secret_iam_member" "run_secrets_access" {
  for_each = local.secrets_map

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.run_secrets[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.base_name}-${each.value.service_name}-sa@${local.settings.project.id}.iam.gserviceaccount.com"

  depends_on = [
    google_secret_manager_secret.run_secrets,
    module.cloud_run_services,
  ]
}

locals {
  external_env_secret_access = {
    for pair in flatten([
      for service_key, service_config in local.app_services : [
        for secret in try(service_config.cloudrun.secret_env, []) : {
          key          = "${service_config.name}/${try(secret.raw_name, false) ? secret.name : "${local.base_name}-${service_config.name}-${secret.name}"}"
          service_name = service_config.name
          secret_id    = try(secret.raw_name, false) ? secret.name : "${local.base_name}-${service_config.name}-${secret.name}"
        }
        if try(secret.create_secret, true) == false
      ]
    ]) : pair.key => pair
  }
}

resource "google_secret_manager_secret_iam_member" "external_env_secrets_access" {
  for_each = local.external_env_secret_access

  project   = local.settings.project.id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.base_name}-${each.value.service_name}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
}
