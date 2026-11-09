# ===================================================================
# FIRESTORE CONFIGURATION
# ===================================================================
# YAML-driven Firestore databases and project-level IAM.
# Declared at root-level (firestore:) in settings/*.yaml.
#
# NOTE: If "(default)" database already exists in the project,
#       use `terraform import` to adopt it before applying.
#
# YAML parameters:
#   name                    (required) - Database name, typically "(default)"
#   type                    (required) - "FIRESTORE_NATIVE" or "DATASTORE_MODE"
#   location_id             (optional) - Default from region_name
#   concurrency_mode        (optional) - e.g. "OPTIMISTIC"
#   point_in_time_recovery  (optional) - Default true in pro, false elsewhere
#   delete_protection_state (optional) - Default "DELETE_PROTECTION_ENABLED" in pro;
#                                        unset elsewhere, which keeps what the
#                                        database has
#   deletion_policy         (optional) - "ABANDON" (provider default) or "DELETE".
#                                        ABANDON drops the database from Terraform
#                                        state on destroy but LEAVES IT RUNNING in
#                                        GCP, so a removed block reports "destroyed"
#                                        while the data and its billing survive.
#                                        Set "DELETE" when the database is meant to
#                                        disappear for real.
#   permissions             (optional) - Map of permission groups

locals {
  # Resolve custom member aliases and Cloud Run shortcuts in Firestore permissions.
  firestore_custom_member_map = {
    "custom:viewer_members"    = try(local.settings.project_access.viewers, [])
    "custom:operator_members"  = try(local.settings.project_access.operators, [])
    "custom:iap_admin_members" = try(local.settings.iap.admin_access.members, [])
  }

  firestore_permissions = {
    for db_key, db_config in local.all_firestore : db_key => {
      for perm_name, perm_config in try(db_config.permissions, {}) : perm_name => {
        members = [
          for member in flatten([
            for m in perm_config.members :
            try(local.firestore_custom_member_map[m], [m])
          ]) :
          startswith(member, "cloudrun:")
          ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun:")}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
          : startswith(member, "cloudrun_service:")
          ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun_service:")}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
          : startswith(member, "cloudrun_job:")
          ? "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun_job:")}-job-sa@${local.settings.project.id}.iam.gserviceaccount.com"
          : member
        ]
        roles = perm_config.roles
      }
    }
  }

  firestore_iam_bindings = {
    for item in flatten([
      for db_key, perms in local.firestore_permissions : [
        for perm_name, perm_config in perms : [
          for role in perm_config.roles : [
            for member in perm_config.members : {
              key    = "${db_key}/${perm_name}/${role}/${member}"
              role   = role
              member = member
            }
          ]
        ]
      ]
    ]) : item.key => item
  }
}

resource "google_firestore_database" "databases" {
  for_each = local.all_firestore

  project                           = local.settings.project.id
  name                              = each.value.name
  location_id                       = try(each.value.location_id, local.settings.region_name)
  type                              = each.value.type
  concurrency_mode                  = try(each.value.concurrency_mode, null)
  point_in_time_recovery_enablement = try(each.value.point_in_time_recovery, local.workspace == "pro") ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
  # Both values are updated in place. Outside pro delete protection is left
  # unset: the field is optional and computed, so Terraform keeps whatever the
  # database has instead of turning off a protection set by hand.
  delete_protection_state = try(each.value.delete_protection_state, local.workspace == "pro" ? "DELETE_PROTECTION_ENABLED" : null)
  deletion_policy         = try(each.value.deletion_policy, null)

  depends_on = [google_project_service.enabled_apis]
}

resource "google_firestore_index" "indexes" {
  for_each = local.all_firestore_indexes

  project    = local.settings.project.id
  database   = each.value.database
  collection = each.value.val.collection

  dynamic "fields" {
    for_each = each.value.val.fields
    content {
      field_path   = fields.value.field_path
      order        = try(fields.value.order, null)
      array_config = try(fields.value.array_config, null)
    }
  }

  depends_on = [google_firestore_database.databases]
}

resource "google_project_iam_member" "firestore_permissions" {
  for_each = local.firestore_iam_bindings

  project = local.settings.project.id
  role    = each.value.role
  member  = each.value.member

  depends_on = [module.cloud_run_services, google_service_account.cloudrun_job]
}
