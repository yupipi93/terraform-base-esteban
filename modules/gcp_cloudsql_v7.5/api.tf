resource "google_project_service" "secret_manager" {
  service            = "secretmanager.googleapis.com"
  project            = var.gcp_project_id
  disable_on_destroy = false
}

