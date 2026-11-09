####################################################################################
# MULTI-PROVIDER REPOSITORY CONNECTION (shared locals)
####################################################################################
# Supports Bitbucket Cloud and GitHub via Cloud Build V2 connections.
#
# Each cloudbuild entry (in app.service or raw cloudbuild section) can specify:
#   provider:  "bitbucket" | "github"  (defaults to repo_providers.default)
#   workspace: override for Bitbucket workspace (optional)
#   owner:     override for GitHub owner/org    (optional)
#
# Provider-specific resources live in dedicated files:
#   gcp.repository.bitbucket.tf  - Bitbucket Cloud connection, secrets & IAM
#   gcp.repository.github.tf     - GitHub connection, secret & IAM
#
# The unified `repo_id_map` local lets Cloud Build triggers reference any
# provider transparently.
####################################################################################

locals {
  # ---------------------------------------------------------------------------
  # Provider defaults (backward-compatible with legacy bitbucket_workspace)
  # ---------------------------------------------------------------------------
  default_repo_provider = try(local.settings.repo_providers.default, "github")

  provider_configs = try(local.settings.repo_providers, {
    bitbucket = {
      workspace = try(local.settings.bitbucket_workspace, "")
    }
  })

  # ---------------------------------------------------------------------------
  # Repo configs extracted from app.service cloudbuild entries
  # ---------------------------------------------------------------------------
  app_repo_configs = {
    for k, v in local.app_services : k => {
      repo_name           = v.cloudbuild.repo_name
      provider            = try(v.cloudbuild.provider, local.default_repo_provider)
      workspace           = try(v.cloudbuild.workspace, try(local.provider_configs[try(v.cloudbuild.provider, local.default_repo_provider)].workspace, ""))
      owner               = try(v.cloudbuild.owner, try(local.provider_configs[try(v.cloudbuild.provider, local.default_repo_provider)].owner, ""))
      app_installation_id = try(local.provider_configs[try(v.cloudbuild.provider, local.default_repo_provider)].app_installation_id, null)
    } if lookup(v, "cloudbuild", null) != null && lookup(v.cloudbuild, "repo_name", null) != null
  }

  # ---------------------------------------------------------------------------
  # Repo configs extracted from app.job cloudbuild entries
  # ---------------------------------------------------------------------------
  job_repo_configs = {
    for k, v in try(local.settings.app.job, {}) : k => {
      repo_name           = v.cloudbuild.repo_name
      provider            = try(v.cloudbuild.provider, local.default_repo_provider)
      workspace           = try(v.cloudbuild.workspace, try(local.provider_configs[try(v.cloudbuild.provider, local.default_repo_provider)].workspace, ""))
      owner               = try(v.cloudbuild.owner, try(local.provider_configs[try(v.cloudbuild.provider, local.default_repo_provider)].owner, ""))
      app_installation_id = try(local.provider_configs[try(v.cloudbuild.provider, local.default_repo_provider)].app_installation_id, null)
    } if lookup(v, "cloudbuild", null) != null && lookup(v.cloudbuild, "repo_name", null) != null
  }

  # ---------------------------------------------------------------------------
  # Repo configs extracted from standalone cloudbuild section
  # ---------------------------------------------------------------------------
  raw_repo_configs = {
    for k, v in lookup(local.settings, "cloudbuild", {}) : k => {
      repo_name           = v.repo_name
      provider            = try(v.provider, local.default_repo_provider)
      workspace           = try(v.workspace, try(local.provider_configs[try(v.provider, local.default_repo_provider)].workspace, ""))
      owner               = try(v.owner, try(local.provider_configs[try(v.provider, local.default_repo_provider)].owner, ""))
      app_installation_id = try(local.provider_configs[try(v.provider, local.default_repo_provider)].app_installation_id, null)
    } if lookup(v, "repo_name", null) != null
  }

  # ---------------------------------------------------------------------------
  # Combine & deduplicate by provider/repo_name
  # ---------------------------------------------------------------------------
  _all_repo_configs = merge(local.app_repo_configs, local.job_repo_configs, local.raw_repo_configs)

  _repo_groups = {
    for key, config in local._all_repo_configs : "${config.provider}/${config.repo_name}" => config...
  }

  unique_repo_map = {
    for key, configs in local._repo_groups : key => configs[0]
  }

  # ---------------------------------------------------------------------------
  # Provider-specific maps (keyed by repo_name for backward compatibility)
  # ---------------------------------------------------------------------------
  bitbucket_repos = { for k, v in local.unique_repo_map : v.repo_name => v if v.provider == "bitbucket" }
  github_repos    = { for k, v in local.unique_repo_map : v.repo_name => v if v.provider == "github" }

  # ---------------------------------------------------------------------------
  # Unified repository ID lookup for Cloud Build triggers
  # Usage: local.repo_id_map["bitbucket/my-repo"] or local.repo_id_map["github/my-repo"]
  # ---------------------------------------------------------------------------
  repo_id_map = merge(
    { for k, v in google_cloudbuildv2_repository.bitbucket : "bitbucket/${k}" => v.id },
    { for k, v in google_cloudbuildv2_repository.github : "github/${k}" => v.id },
    { for k, v in google_cloudbuildv2_repository.github_extra : k => v.id }
  )

  # ---------------------------------------------------------------------------
  # Cross-file locals consumed by gcp.cloudbuild.tf
  # ---------------------------------------------------------------------------
  apps_with_cloudbuild = {
    for k, v in local.app_services : k => v if lookup(v, "cloudbuild", null) != null && lookup(v.cloudbuild, "repo_name", null) != null
  }

  jobs_with_cloudbuild = {
    for k, v in try(local.settings.app.job, {}) : k => v if lookup(v, "cloudbuild", null) != null && lookup(v.cloudbuild, "repo_name", null) != null
  }

  raw_cloudbuild_configs = {
    for k, v in lookup(local.settings, "cloudbuild", {}) : k => v if lookup(v, "repo_name", null) != null
  }
}
