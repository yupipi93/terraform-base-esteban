# terraform test runs every file in the default workspace, so the tests under
# tests/ pick the settings file and the workspace-dependent defaults with this
# variable. Leave it unset everywhere else: the workspace then decides, as before.
variable "settings_workspace" {
  type        = string
  default     = null
  description = "Workspace name used instead of terraform.workspace (settings file, names, pro defaults). For terraform test only."

  validation {
    condition     = var.settings_workspace == null || can(regex("^[a-z][a-z0-9-]*$", var.settings_workspace))
    error_message = "settings_workspace must be lowercase letters, digits and hyphens, like a workspace name."
  }
}

# Top-level keys a test merges over the workspace file, the same shallow way,
# to plan a value no reference file holds (one that a precondition refuses).
variable "settings_override" {
  type        = any
  default     = {}
  nullable    = false
  description = "Top-level settings keys merged over the workspace file. For terraform test only."
}

check "settings_workspace_unset" {
  assert {
    condition     = (var.settings_workspace == null || var.settings_workspace == terraform.workspace) && length(var.settings_override) == 0
    error_message = "settings_workspace (${coalesce(var.settings_workspace, "unset")}) or settings_override (${length(var.settings_override)} keys) overrides workspace ${terraform.workspace}. Unset them outside terraform test."
  }
}

locals {
  # Every root file reads the workspace name from here, never terraform.workspace.
  workspace = coalesce(var.settings_workspace, terraform.workspace)

  // Loading settings from yml files
  workspace_file = "./settings/${local.workspace}.yaml"
  defaults       = file("./settings/default.yaml")
  workspace_data = fileexists(local.workspace_file) ? file(local.workspace_file) : yamlencode({})
  settings = merge(
    yamldecode(local.defaults),
    yamldecode(local.workspace_data),
    var.settings_override,
  )
  base_name        = format("%s", local.settings.client.name)
  base_name_medium = format("%s-%s", local.settings.client.name, local.workspace)

  # Standard Artifact Registry host for the project's region
  registry_host        = "${local.settings.region_name}-docker.pkg.dev/${local.settings.project.id}"
  registry_host_python = "${local.settings.region_name}-python.pkg.dev/${local.settings.project.id}"

  # One label set for every resource that accepts labels, applied by the providers
  # (providers.tf). GCP label values allow at most 63 lowercase letters, digits,
  # `_` and `-`, so the values read from YAML are lowercased, every other
  # character becomes `-`, and the result is cut to 63.
  common_labels = {
    for key, value in {
      workspace  = local.workspace
      client     = local.settings.client.name
      managed_by = "terraform"
      repo       = try(local.settings.iac.repo, "terraform-base")
    } : key => substr(replace(lower(value), "/[^a-z0-9_-]/", "-"), 0, 63)
  }
}

locals {
  all_firestore = try(local.settings.firestore, {})

  all_firestore_indexes = {
    for item in flatten([
      for db_key, db_config in local.all_firestore : [
        for idx, index_config in try(jsondecode(file(db_config.indexes_file)), []) : {
          key      = "${db_key}/${index_config.collection}/${idx}"
          database = db_config.name
          val      = index_config
        }
      ] if try(db_config.indexes_file, null) != null
    ]) : item.key => item
  }
}
