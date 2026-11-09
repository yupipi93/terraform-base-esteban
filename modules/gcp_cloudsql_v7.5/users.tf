resource "random_password" "user_password" {
  for_each = { for data in var.users : "${data["name"]}" => data if length(var.users) > 0 }

  length           = 32
  special          = var.special_characters_pass.enabled
  override_special = var.special_characters_pass.characters
}

resource "google_secret_manager_secret" "user_password" {
  for_each = { for data in var.users : "${data["name"]}" => data if length(var.users) > 0 }

  project   = var.gcp_project_id
  secret_id = format("%s--%s-password", local.m_base_name_medium, each.value.name)
  replication {
    dynamic "auto" {
      for_each = length(var.secrets_locations) == 0 ? toset(["auto"]) : toset([])
      content {
      }
    }
    dynamic "user_managed" {
      for_each = length(var.secrets_locations) > 0 ? toset(["user_managed"]) : toset([])
      content {
        dynamic "replicas" {
          for_each = var.secrets_locations
          content {
            location = replicas.value
          }
        }
      }
    }
  }
  depends_on = [
    google_project_service.secret_manager
  ]
}

resource "google_secret_manager_secret_version" "user_password" {
  for_each = { for data in var.users : "${data["name"]}" => data if length(var.users) > 0 }

  secret      = google_secret_manager_secret.user_password[each.key].id
  secret_data = random_password.user_password[each.key].result
}

resource "google_sql_user" "user" {
  for_each = { for data in var.users : "${data["name"]}" => data if length(var.users) > 0 }

  project    = var.gcp_project_id
  name       = each.value.name
  instance   = google_sql_database_instance.dbe.name
  password   = google_secret_manager_secret_version.user_password[each.key].secret_data
  host       = each.value.host
  depends_on = [google_sql_database_instance.dbe]
}
