# The project number, for the Cloud Build identities
# (<number>@cloudbuild.gserviceaccount.com, service-<number>@gcp-sa-cloudbuild...)
# and the budget filter. project.number in the YAML wins when it holds a real
# number. Left out (the merge is shallow, so `project: {id: x}` drops the one in
# default.yaml) or left at the all-zero placeholder, it is read from the project.
# The read is a projects.get call at plan time: it needs resourcemanager.projects.get
# on the project and the Cloud Resource Manager API enabled there, because the
# provider bills the call to the project itself (providers.tf). Being read at plan
# time, the number is known there, so the for_each keys built from it (the
# Artifact Registry members) stay known too.
locals {
  project_number_setting = try(tostring(local.settings.project.number), null)

  # null for an absent value, the all-zero placeholder or a malformed value; the
  # data source below then reads the number, and refuses the malformed one.
  project_number_from_yaml = can(regex("^0*[1-9][0-9]*$", local.project_number_setting)) ? local.project_number_setting : null

  project_number = coalesce(local.project_number_from_yaml, one(data.google_project.current[*].number))
}

data "google_project" "current" {
  count = local.project_number_from_yaml == null ? 1 : 0

  project_id = local.settings.project.id

  lifecycle {
    precondition {
      condition     = local.project_number_setting == null || can(regex("^[0-9]+$", local.project_number_setting))
      error_message = "project.number is \"${local.project_number_setting == null ? "" : local.project_number_setting}\": use the digits of the project number, or leave it out to read it from project.id."
    }
  }
}
