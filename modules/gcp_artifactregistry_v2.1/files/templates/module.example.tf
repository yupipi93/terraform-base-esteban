#
module "artifact_registry" {
  source = "./modules/gcp_artifactregistry_v2.1"

  gcp_project_id = local.settings.project.id
  base_name      = local.base_name_medium
  region_name    = local.settings.region_name
  permissions = {
    cloudbuild = {
      members = ["serviceAccount:${local.settings.project_sys.number}@cloudbuild.gserviceaccount.com", "user:pepe@domain.com"]
      roles = [
        "roles/artifactregistry.reader",
        "roles/artifactregistry.writer",
      ]
    }
    viewer = {
      members = ["user:pepe@domain.com", "user:ramon@domain.com"]
      roles = [
        "roles/artifactregistry.reader",
        "roles/artifactregistry.writer",
      ]
    }
  }
  format = "DOCKER"
}

