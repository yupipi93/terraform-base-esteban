# ===================================================================
# CLOUD STORAGE BUCKETS
# ===================================================================
# This file manages Cloud Storage buckets for the project
# using the gcp_storage module with configuration from settings YAML files.

# Local variables for dynamic permission processing
locals {
  # A workspace with no bucket: key creates nothing (AUD-BUCKET).
  buckets = try(local.settings.bucket, {})

  # Process bucket permissions, expanding the same member shorthands the rest of this repo
  # uses:
  #
  #   cloudrun:<service>   -> <client>-<service>-sa@…    (a Cloud Run service)
  #   cloudrun_job:<job>   -> <client>-<job>-job-sa@…    (a Cloud Run job)
  #
  # Observed in practice: if a prefix is not expanded here, the failure is not a validation
  # error in Terraform but a 400 from Google at apply time ("The member cloudrun_job:<job>
  # is of an unknown type"), half way through a plan, which is the worst moment to discover a typo-shaped problem. A
  # prefix should mean the same thing wherever it is written.
  bucket_permissions = {
    for bucket_name, bucket_config in local.buckets : bucket_name => {
      for permission_name, permission_config in try(bucket_config.permissions, {}) : permission_name => {
        members = [
          for member in permission_config.members :
          startswith(member, "cloudrun_job:") ?
          "serviceAccount:${local.base_name}-${trimprefix(member, "cloudrun_job:")}-job-sa@${local.settings.project.id}.iam.gserviceaccount.com" :
          startswith(member, "cloudrun:") ?
          "serviceAccount:${local.base_name}-${trimsuffix(trimprefix(member, "cloudrun:"), "")}-sa@${local.settings.project.id}.iam.gserviceaccount.com" :
          member
        ]
        roles = permission_config.roles
      }
    }
  }
}

# Create all storage buckets using for_each loop
module "storage_buckets" {
  for_each = local.buckets

  source = "./modules/gcp_storage_v2.7"

  # If custom_name is set, use the exact bucket name; otherwise use standard naming convention
  base_name      = try(each.value.custom_name, null) != null ? each.value.custom_name : "${local.base_name_medium}-${try(each.value.name, each.key)}"
  region_name    = try(each.value.region, local.settings.region_name)
  gcp_project_id = local.settings.project.id

  # Disable random suffix when using custom_name (importing existing buckets)
  use_random_suffix = try(each.value.custom_name, null) != null ? false : try(each.value.use_random_suffix, true)

  # Basic bucket configuration
  class                       = try(each.value.class, "REGIONAL")
  force_destroy               = try(each.value.force_destroy, false)
  enable_versioning           = try(each.value.enable_versioning, false)
  uniform_bucket_level_access = try(each.value.uniform_access, true)
  public_access_prevention    = try(each.value.public_access_prevention, "enforced")
  authoritative_permissions   = try(each.value.authoritative_permissions, false)
  # Soft delete retention: Convert days to seconds (GCP requires seconds, min 7 days, max 90 days)
  soft_delete_retention_duration = try(each.value.soft_delete_days, 7) * 86400

  # Autoclass configuration (for imported buckets with autoclass enabled)
  autoclass = try(each.value.autoclass, null) != null ? {
    enabled                = each.value.autoclass.enabled
    terminal_storage_class = try(each.value.autoclass.terminal_storage_class, "ARCHIVE")
  } : null

  # Lifecycle rules configuration
  lifecycle_rules = {
    for rule_name, rule_config in try(each.value.lifecycle_rules, {}) :
    rule_name => {
      age                        = try(rule_config.age, null)
      days_since_noncurrent_time = try(rule_config.days_since_noncurrent_time, null)
      num_newer_versions         = try(rule_config.num_newer_versions, null)
      action_type                = rule_config.action_type
      action_sc                  = try(rule_config.action_sc, null)
      matches_prefixes           = try(rule_config.prefixes, [])
      matches_storage_class      = try(rule_config.matches_storage_class, [])
      matches_suffix             = try(rule_config.matches_suffix, [])
    }
  }

  # Bucket Lock. The YAML takes days, the API takes seconds. Off unless set.
  retention_policy = try(each.value.retention_policy, null) != null ? {
    retention_period = each.value.retention_policy.retention_days * 86400
    is_locked        = try(each.value.retention_policy.is_locked, false)
  } : null

  # Usage and storage logs written as CSV objects into another, existing bucket.
  logging = try(each.value.access_logs, null) != null ? {
    log_bucket        = each.value.access_logs.log_bucket
    log_object_prefix = try(each.value.access_logs.log_object_prefix, null)
  } : null

  # Dynamic permissions with Cloud Run service account transformation
  permissions = try(local.bucket_permissions[each.key], {})
  cors        = try(each.value.cors, [])
  website     = try(each.value.website, null)

  # Ensure Cloud Run services are created before bucket permissions
  #
  # The second entry is the same class of problem for a principal Terraform CANNOT see.
  # A `permissions.members` entry written as a literal `serviceAccount:…` string (which
  # is the only way YAML can name one) creates NO dependency edge to the resource that
  # creates that account, so Terraform is free to grant the role first. Google then
  # rejects it with `Service account … does not exist`, which is a propagation delay
  # wearing the costume of a typo.
  #
  # Observed in practice: grants on a freshly created account failed on the first apply
  # and succeeded unchanged a few minutes later, confirmed from the GCS audit log:
  #   protoPayload.status.code=3, "Service account … does not exist."
  # If you add a file that creates service accounts referenced literally from bucket
  # permissions, add a `time_sleep` after them and list it here.
  depends_on = [module.cloud_run_services]
}
