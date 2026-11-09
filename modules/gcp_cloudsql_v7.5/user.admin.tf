resource "random_password" "admin_password" {
  length           = 32
  special          = var.special_characters_pass.enabled
  override_special = var.special_characters_pass.characters
}

resource "random_id" "admin_name" {
  byte_length = 2
}

resource "random_id" "admin_sufix" {
  byte_length = 2
}

resource "google_secret_manager_secret" "admin_password" {
  project   = var.gcp_project_id
  secret_id = format("%s--user-admin-password--%s", local.m_base_name_medium, random_id.admin_sufix.hex)
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

resource "google_secret_manager_secret_version" "admin_password" {
  secret      = google_secret_manager_secret.admin_password.id
  secret_data = random_password.admin_password.result
}

resource "google_secret_manager_secret" "admin_name" {
  project   = var.gcp_project_id
  secret_id = format("%s--user-admin-name--%s", local.m_base_name_medium, random_id.admin_sufix.hex)
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

resource "google_secret_manager_secret_version" "admin_name" {
  secret      = google_secret_manager_secret.admin_name.id
  secret_data = format("admin-%s", random_id.admin_name.hex)
}

resource "google_sql_user" "admin" {
  project    = var.gcp_project_id
  name       = format("admin-%s", random_id.admin_name.hex)
  instance   = google_sql_database_instance.dbe.name
  password   = google_secret_manager_secret_version.admin_password.secret_data
  depends_on = [google_sql_database_instance.dbe]
}
