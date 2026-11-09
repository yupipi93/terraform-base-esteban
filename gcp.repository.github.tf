####################################################################################
# GITHUB – Connection, Repository, Secret & IAM
####################################################################################
# Resources created per unique GitHub repo (local.github_repos).
# Secrets required:
#   - <repo>-github-token  (OAuth token or Personal Access Token)
#
# Prerequisites:
#   1. Install the Cloud Build GitHub App on your GitHub org/user.
#   2. Note the app_installation_id (github.com/settings/installations).
#   3. After first `terraform apply`, set the token secret value in
#      Secret Manager before running apply again.
####################################################################################

# --- Connection ----------------------------------------------------------
resource "google_cloudbuildv2_connection" "github" {
  count = length(local.github_repos) > 0 ? 1 : 0

  project  = local.settings.project.id
  location = local.settings.region_name
  name     = try(local.provider_configs["github"].connection_name, "github-repo-connection")

  github_config {
    app_installation_id = try(local.provider_configs["github"].app_installation_id, null)

    authorizer_credential {
      oauth_token_secret_version = format("projects/%s/secrets/%s/versions/latest", local.settings.project.id, google_secret_manager_secret.github_token[0].secret_id)
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_binding.github_token
  ]
}

# --- Repository ----------------------------------------------------------
resource "google_cloudbuildv2_repository" "github" {
  for_each = local.github_repos

  project           = local.settings.project.id
  location          = local.settings.region_name
  name              = format("%s--gh-repository", each.key)
  parent_connection = google_cloudbuildv2_connection.github[0].id
  remote_uri        = format("https://github.com/%s/%s.git", each.value.owner, each.key)

  depends_on = [google_cloudbuildv2_connection.github]
}

########################################################
# SECRET (OAuth / PAT token)
########################################################

resource "google_secret_manager_secret" "github_token" {
  count = length(local.github_repos) > 0 ? 1 : 0

  project   = local.settings.project.id
  secret_id = format("%s-github-token", try(local.provider_configs["github"].connection_name, "github-repo-connection"))

  labels = local.common_labels

  replication {
    user_managed {
      replicas {
        location = local.settings.region_name
      }
    }
  }
}

########################################################
# IAM BINDING
########################################################

resource "google_secret_manager_secret_iam_binding" "github_token" {
  count = length(local.github_repos) > 0 ? 1 : 0

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.github_token[0].secret_id
  role      = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:service-${local.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  ]

  depends_on = [
    google_secret_manager_secret.github_token
  ]
}
