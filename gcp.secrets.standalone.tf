# Standalone Secret Manager secrets
#
# Secrets that are NOT bound to a Cloud Run service (those live in gcp.secrets.tf,
# keyed by service). These are declared flat in the workspace yaml under `secrets:`
# and exist to share operational credentials/config between machines and agents.
#
# Values are NEVER stored in this repo or in terraform state: terraform creates the
# secret container plus a PLACEHOLDER first version, and the real payload is pushed
# out of band with `gcloud secrets versions add`. `ignore_changes = [secret_data]`
# keeps terraform from reverting it. Consumers must always read `versions/latest`.
locals {
  standalone_secrets = try(local.settings.secrets, {})

  # Flattened {secret_id -> member} pairs for the optional per-secret WRITER list.
  # Separate from accessors because they are genuinely different powers, and most secrets
  # want only the first. A writer can add a version; it still cannot read one back unless
  # it is also an accessor. The case that needs both is a credential the holder RENEWS:
  # a job that reads a session token it was given, and when a login replaces it has to
  # hand the new one back or the next run starts logged out.
  standalone_secret_writers = {
    for pair in flatten([
      for secret_id, secret_config in local.standalone_secrets : [
        for member in try(secret_config.writers, []) : {
          key       = "${secret_id}/${member}"
          secret_id = secret_id
          member    = member
        }
      ]
    ]) : pair.key => pair
  }

  # Flattened {secret_id -> member} pairs for the optional per-secret VERSION MANAGER list.
  # A version manager can add, list, disable and destroy versions, and still cannot read
  # one. Observed in practice: a webhook that stores a rotating credential as a new version
  # has to destroy the version it replaced, or every old version stays billed as an active
  # version forever.
  standalone_secret_version_managers = {
    for pair in flatten([
      for secret_id, secret_config in local.standalone_secrets : [
        for member in try(secret_config.version_managers, []) : {
          key       = "${secret_id}/${member}"
          secret_id = secret_id
          member    = member
        }
      ]
    ]) : pair.key => pair
  }

  # Flattened {secret_id -> member} pairs for the optional per-secret accessor list
  standalone_secret_accessors = {
    for pair in flatten([
      for secret_id, secret_config in local.standalone_secrets : [
        for member in try(secret_config.accessors, []) : {
          key       = "${secret_id}/${member}"
          secret_id = secret_id
          member    = member
        }
      ]
    ]) : pair.key => pair
  }
}

resource "google_secret_manager_secret" "standalone" {
  for_each = local.standalone_secrets

  project   = local.settings.project.id
  secret_id = each.key

  labels = merge(local.common_labels, {
    purpose = try(each.value.purpose, "general")
  })

  replication {
    user_managed {
      replicas {
        location = local.settings.region_name
      }
    }
  }
}

# Placeholder first version: the real value is added out of band (see the guide in
# docs/oracle-credentials-bootstrap.md). Terraform must never learn the real value.
resource "google_secret_manager_secret_version" "standalone_placeholder" {
  for_each = local.standalone_secrets

  secret      = google_secret_manager_secret.standalone[each.key].id
  secret_data = "PLACEHOLDER_VALUE_TO_BE_REPLACED"

  lifecycle {
    ignore_changes = [secret_data]
  }

  depends_on = [
    google_secret_manager_secret.standalone
  ]
}

resource "google_secret_manager_secret_iam_member" "standalone_writers" {
  for_each = local.standalone_secret_writers

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.standalone[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member

  depends_on = [
    google_secret_manager_secret.standalone
  ]
}

resource "google_secret_manager_secret_iam_member" "standalone_version_managers" {
  for_each = local.standalone_secret_version_managers

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.standalone[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionManager"
  member    = each.value.member

  depends_on = [
    google_secret_manager_secret.standalone
  ]
}

resource "google_secret_manager_secret_iam_member" "standalone_accessors" {
  for_each = local.standalone_secret_accessors

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.standalone[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member

  depends_on = [
    google_secret_manager_secret.standalone
  ]
}
