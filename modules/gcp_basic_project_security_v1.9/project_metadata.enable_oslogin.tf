data "google_project_service" "compute_engine" {
  service = "compute.googleapis.com"
}

resource "google_compute_project_metadata_item" "enable_oslogin" {
  for_each = data.google_project_service.compute_engine.id != null ? { os-login = "dummy" } : {}
  key      = "enable-oslogin"
  value    = "TRUE"
}
