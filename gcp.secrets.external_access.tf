# Access to secrets this project did NOT create
#
# `gcp.secrets.standalone.tf` owns the secrets declared under `secrets:`. It CREATES the
# container and a placeholder version, then leaves the payload alone. That is the right
# shape for a secret this workspace is the source of.
#
# It is the wrong shape for a secret that already exists and belongs to somewhere else
# (created by hand, by another repository, or by a service). Declaring it under `secrets:`
# to add an accessor would make terraform try to create it, and creating a Secret Manager
# secret that exists is an error, while importing it would put a live credential's
# container under a resource whose first act is to add a placeholder version.
#
# So this file grants IAM and NOTHING else. No secret is created, no version is written,
# and if a secret named here disappears the apply fails loudly instead of quietly making a
# new empty one.
#
# Declared in the workspace yaml:
#
#   external_secret_access:
#     some-existing-secret:
#       accessors:
#         - "serviceAccount:reader@my-project.iam.gserviceaccount.com"
#
# Every grant is `roles/secretmanager.secretAccessor`: read a version, nothing else. The
# identity cannot add a version, cannot change the secret, and cannot delete it.

locals {
  # {secret_id -> {accessors: [...]}} for secrets this project grants access to but does
  # not own. Empty in every workspace that has none.
  external_secret_access = try(local.settings.external_secret_access, {})

  external_secret_accessors = {
    for pair in flatten([
      for secret_id, config in local.external_secret_access : [
        for member in try(config.accessors, []) : {
          key       = "${secret_id}/${member}"
          secret_id = secret_id
          member    = member
        }
      ]
    ]) : pair.key => pair
  }
}

# Named `secret_id` rather than looked up through a data source on purpose: a data source
# would fail the whole plan on a typo, at refresh time, in a message about a missing secret
# rather than about a wrong name. The IAM member resource fails at apply with the secret's
# name in it, which is the error a person can act on.
resource "google_secret_manager_secret_iam_member" "external_accessors" {
  for_each = local.external_secret_accessors

  project   = local.settings.project.id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
