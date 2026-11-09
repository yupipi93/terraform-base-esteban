resource "google_artifact_registry_repository" "artifact_registry" {
  project                = var.gcp_project_id
  location               = var.region_name
  repository_id          = local.m_base_name
  description            = format("Artifact regisry - %s", local.m_base_name_medium)
  format                 = var.format
  cleanup_policy_dry_run = var.cleanup_policy_dry_run
  dynamic "docker_config" {
    for_each = var.format == "DOCKER" ? [1] : []
    content {
      immutable_tags = var.immutable_tags
    }
  }
  dynamic "cleanup_policies" {
    for_each = var.cleanup_policies
    content {
      id     = cleanup_policies.key
      action = cleanup_policies.value.action

      dynamic "condition" {
        for_each = cleanup_policies.value.condition[*]
        content {
          tag_state             = condition.value.tag_state
          tag_prefixes          = condition.value.tag_prefixes
          older_than            = condition.value.older_than
          newer_than            = condition.value.newer_than
          version_name_prefixes = condition.value.version_name_prefixes
          package_name_prefixes = condition.value.package_name_prefixes
        }
      }

      dynamic "most_recent_versions" {
        for_each = cleanup_policies.value.most_recent_versions[*]
        content {
          package_name_prefixes = most_recent_versions.value.package_name_prefixes
          keep_count            = most_recent_versions.value.keep_count
        }
      }
    }
  }
  depends_on = [
    google_project_service.artifact_registry_api
  ]
}


moved {
  from = google_artifact_registry_repository.base
  to   = google_artifact_registry_repository.artifact_registry
}
