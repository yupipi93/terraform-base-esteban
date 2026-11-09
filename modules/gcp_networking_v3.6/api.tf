resource "google_project_service" "servicenetworking" {
  project            = var.gcp_project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}
