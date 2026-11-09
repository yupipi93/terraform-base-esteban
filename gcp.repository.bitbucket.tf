####################################################################################
# BITBUCKET CLOUD – Connection, Repository, Secrets & IAM
####################################################################################
# Resources created per unique Bitbucket repo (local.bitbucket_repos).
# Secrets required:
#   - <repo>-read-connector-token   (read-only app password)
#   - <repo>-admin-connector-token  (admin app password)
#   - <repo>-webhook-connector-secret (auto-generated UUID)
#
# After first `terraform apply`, manually set the read and admin token
# secret values in Secret Manager before running apply again.
####################################################################################

# --- Connection ----------------------------------------------------------
resource "google_cloudbuildv2_connection" "bitbucket" {
  for_each = local.bitbucket_repos

  project  = local.settings.project.id
  location = local.settings.region_name
  name     = format("%s--connection", each.key)

  bitbucket_cloud_config {
    workspace = each.value.workspace

    authorizer_credential {
      user_token_secret_version = format("projects/%s/secrets/%s/versions/latest", local.settings.project.id, google_secret_manager_secret.bitbucket_admin_token[each.key].secret_id)
    }

    read_authorizer_credential {
      user_token_secret_version = format("projects/%s/secrets/%s/versions/latest", local.settings.project.id, google_secret_manager_secret.bitbucket_read_token[each.key].secret_id)
    }

    webhook_secret_secret_version = format("projects/%s/secrets/%s/versions/latest", local.settings.project.id, google_secret_manager_secret.bitbucket_webhook_secret[each.key].secret_id)
  }

  depends_on = [
    google_secret_manager_secret_iam_binding.bitbucket_read_token,
    google_secret_manager_secret_iam_binding.bitbucket_admin_token,
    google_secret_manager_secret_iam_binding.bitbucket_webhook_secret
  ]
}

# --- Repository ----------------------------------------------------------
resource "google_cloudbuildv2_repository" "bitbucket" {
  for_each = local.bitbucket_repos

  project           = local.settings.project.id
  location          = local.settings.region_name
  name              = format("%s--repository", each.key)
  parent_connection = google_cloudbuildv2_connection.bitbucket[each.key].id
  remote_uri        = format("https://bitbucket.org/%s/%s.git", each.value.workspace, each.key)

  depends_on = [google_cloudbuildv2_connection.bitbucket]
}

########################################################
# IMPORT BLOCKS (prevent errors when secrets already exist)
########################################################

import {
  for_each = local.bitbucket_repos
  to       = google_secret_manager_secret.bitbucket_read_token[each.key]
  id       = format("projects/%s/secrets/%s-read-connector-token", local.settings.project.id, each.key)
}

import {
  for_each = local.bitbucket_repos
  to       = google_secret_manager_secret.bitbucket_admin_token[each.key]
  id       = format("projects/%s/secrets/%s-admin-connector-token", local.settings.project.id, each.key)
}

########################################################
# SECRETS
########################################################

resource "google_secret_manager_secret" "bitbucket_read_token" {
  for_each = local.bitbucket_repos

  project   = local.settings.project.id
  secret_id = format("%s-read-connector-token", each.key)

  labels = local.common_labels

  replication {
    user_managed {
      replicas {
        location = local.settings.region_name
      }
    }
  }
}

resource "google_secret_manager_secret" "bitbucket_admin_token" {
  for_each = local.bitbucket_repos

  project   = local.settings.project.id
  secret_id = format("%s-admin-connector-token", each.key)

  labels = local.common_labels

  replication {
    user_managed {
      replicas {
        location = local.settings.region_name
      }
    }
  }
}

resource "google_secret_manager_secret" "bitbucket_webhook_secret" {
  for_each = local.bitbucket_repos

  project   = local.settings.project.id
  secret_id = format("%s-webhook-connector-secret", each.key)

  labels = local.common_labels

  replication {
    user_managed {
      replicas {
        location = local.settings.region_name
      }
    }
  }
}

resource "random_uuid" "bitbucket_webhook_secret" {
  for_each = local.bitbucket_repos
}

resource "google_secret_manager_secret_version" "bitbucket_webhook_secret" {
  for_each = local.bitbucket_repos

  secret      = google_secret_manager_secret.bitbucket_webhook_secret[each.key].id
  secret_data = random_uuid.bitbucket_webhook_secret[each.key].result

  lifecycle {
    ignore_changes = [secret_data]
  }

  depends_on = [
    random_uuid.bitbucket_webhook_secret
  ]
}

########################################################
# IAM BINDINGS
########################################################

resource "google_secret_manager_secret_iam_binding" "bitbucket_read_token" {
  for_each = local.bitbucket_repos

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.bitbucket_read_token[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:service-${local.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  ]

  depends_on = [
    google_secret_manager_secret.bitbucket_read_token
  ]
}

resource "google_secret_manager_secret_iam_binding" "bitbucket_admin_token" {
  for_each = local.bitbucket_repos

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.bitbucket_admin_token[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:service-${local.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  ]

  depends_on = [
    google_secret_manager_secret.bitbucket_admin_token
  ]
}

resource "google_secret_manager_secret_iam_binding" "bitbucket_webhook_secret" {
  for_each = local.bitbucket_repos

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.bitbucket_webhook_secret[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:service-${local.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  ]

  depends_on = [
    google_secret_manager_secret.bitbucket_webhook_secret
  ]
}
