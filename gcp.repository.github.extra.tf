####################################################################################
# GITHUB – Extra connections (other GitHub accounts)
####################################################################################
# gcp.repository.github.tf creates ONE connection, for repo_providers.github. A
# Cloud Build GitHub connection is bound to one GitHub App installation, which
# belongs to one GitHub account, so a repository owned by somebody else needs a
# connection of its own. Each extra one is another key under repo_providers with
# `type: "github"`:
#
#   repo_providers:
#     github-pablo:
#       type: "github"
#       owner: "pabloxzx99"
#       app_installation_id: 12345678
#       connection_name: "pablo-github"
#
# and a service picks it with `cloudbuild.provider: "github-pablo"`. The base
# provider "github" stays in gcp.repository.github.tf, so none of its resource
# addresses move.
#
# Secret <connection_name>-github-token is created empty, like the base one: its
# value (a classic PAT with repo + read:user) is added as a version out of band,
# because a token in Terraform would be a token in the state file.
####################################################################################

locals {
  github_extra_providers = {
    for k, v in local.provider_configs : k => v
    if k != "github" && try(v.type, "") == "github"
  }

  # Keyed "<provider>/<repo>", the same shape repo_id_map uses.
  github_extra_repos = {
    for k, v in local.unique_repo_map : k => v
    if contains(keys(local.github_extra_providers), v.provider)
  }

  # Only providers that some service actually uses get a connection.
  github_extra_used = {
    for p, cfg in local.github_extra_providers : p => cfg
    if length([for r in values(local.github_extra_repos) : r if r.provider == p]) > 0
  }
}

resource "google_secret_manager_secret" "github_extra_token" {
  for_each = local.github_extra_used

  project   = local.settings.project.id
  secret_id = format("%s-github-token", each.value.connection_name)

  labels = local.common_labels

  replication {
    user_managed {
      replicas {
        location = local.settings.region_name
      }
    }
  }
}

resource "google_secret_manager_secret_iam_binding" "github_extra_token" {
  for_each = local.github_extra_used

  project   = local.settings.project.id
  secret_id = google_secret_manager_secret.github_extra_token[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:service-${local.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  ]
}

resource "google_cloudbuildv2_connection" "github_extra" {
  for_each = local.github_extra_used

  project  = local.settings.project.id
  location = local.settings.region_name
  name     = each.value.connection_name

  github_config {
    app_installation_id = each.value.app_installation_id

    authorizer_credential {
      oauth_token_secret_version = format("projects/%s/secrets/%s/versions/latest", local.settings.project.id, google_secret_manager_secret.github_extra_token[each.key].secret_id)
    }
  }

  depends_on = [google_secret_manager_secret_iam_binding.github_extra_token]
}

resource "google_cloudbuildv2_repository" "github_extra" {
  for_each = local.github_extra_repos

  project           = local.settings.project.id
  location          = local.settings.region_name
  name              = format("%s--gh-repository", each.value.repo_name)
  parent_connection = google_cloudbuildv2_connection.github_extra[each.value.provider].id
  remote_uri        = format("https://github.com/%s/%s.git", each.value.owner, each.value.repo_name)
}
