# The two overrides mirror the stable provider below, and they are not cosmetic.
# Without them a google-beta call bills quota to gcloud's own shared client project
# instead of ours, and any beta API that is enabled HERE but not THERE answers 403
# SERVICE_DISABLED, naming a project number nobody recognises. That is exactly how
# importing beta resources tends to fail, and the error text blames a missing quota
# project rather than the provider that forgot to set one.
#
# default_labels puts local.common_labels on every resource that has a top-level
# `labels` field (or `metadata.labels`); a label the resource sets itself wins.
# Resources without labels ignore it.
provider "google-beta" {
  project               = local.settings.project.id
  region                = local.settings.region_name
  user_project_override = true
  billing_project       = local.settings.project.id
  default_labels        = local.common_labels
}

provider "google" {
  project               = local.settings.project.id
  region                = local.settings.region_name
  user_project_override = true
  billing_project       = local.settings.project.id
  default_labels        = local.common_labels
}

# Same provider without default labels, for resources whose labels are immutable.
# On google_cloud_run_domain_mapping a change to terraform_labels forces a
# replacement, so adding default labels would recreate every existing mapping and
# its certificate.
provider "google" {
  alias                 = "unlabelled"
  project               = local.settings.project.id
  region                = local.settings.region_name
  user_project_override = true
  billing_project       = local.settings.project.id
}

provider "oci" {
  auth                = "ApiKey"
  config_file_profile = "DEFAULT"
}
