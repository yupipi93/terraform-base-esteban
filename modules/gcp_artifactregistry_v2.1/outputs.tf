output "artifact_repo_name" {
  value       = google_artifact_registry_repository.artifact_registry.name
  description = "The name of the Artifact Registry repository"
}

output "artifact_repo_id" {
  value       = google_artifact_registry_repository.artifact_registry.id
  description = "The ID of the Artifact Registry repository"
}

output "artifact_repo_url" {
  value       = format("%s-%s.pkg.dev/%s/%s", var.region_name, lower(var.format), var.gcp_project_id, local.m_base_name)
  description = "Url of the artifact registry"
}
