resource "google_project_service" "cloudrun" {
  project            = var.gcp_project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}


resource "google_project_service" "iam" {
  project            = var.gcp_project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  project            = var.gcp_project_sys_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}
