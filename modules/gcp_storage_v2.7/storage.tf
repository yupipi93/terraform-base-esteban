resource "random_id" "base" {
  count       = var.use_random_suffix ? 1 : 0
  byte_length = 2
}

resource "google_storage_bucket" "base" {
  project                     = var.gcp_project_id
  name                        = var.use_random_suffix ? format("%s--%s", local.m_base_name, random_id.base[0].hex) : local.m_base_name
  storage_class               = var.class
  location                    = var.region_name
  force_destroy               = var.force_destroy
  uniform_bucket_level_access = var.uniform_bucket_level_access
  public_access_prevention    = var.public_access_prevention

  soft_delete_policy {
    retention_duration_seconds = var.soft_delete_retention_duration
  }

  versioning {
    enabled = var.enable_versioning
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      condition {
        age                        = lifecycle_rule.value.age
        days_since_noncurrent_time = lifecycle_rule.value.days_since_noncurrent_time
        num_newer_versions         = lifecycle_rule.value.num_newer_versions
        matches_prefix             = lifecycle_rule.value.matches_prefixes
        matches_storage_class      = lifecycle_rule.value.matches_storage_class
        matches_suffix             = lifecycle_rule.value.matches_suffix
      }
      action {
        type          = lifecycle_rule.value.action_type
        storage_class = lifecycle_rule.value.action_sc
      }
    }
  }

  dynamic "retention_policy" {
    for_each = var.retention_policy != null ? [var.retention_policy] : []
    content {
      retention_period = tostring(retention_policy.value.retention_period)
      is_locked        = retention_policy.value.is_locked
    }
  }

  dynamic "logging" {
    for_each = var.logging != null ? [var.logging] : []
    content {
      log_bucket        = logging.value.log_bucket
      log_object_prefix = logging.value.log_object_prefix
    }
  }

  dynamic "autoclass" {
    for_each = var.autoclass != null ? [var.autoclass] : []
    content {
      enabled                = autoclass.value.enabled
      terminal_storage_class = autoclass.value.terminal_storage_class
    }
  }

  dynamic "website" {
    for_each = var.website != null ? { "a" = "b" } : {}
    content {
      main_page_suffix = var.website.main_page_suffix
      not_found_page   = var.website.not_found_page
    }
  }

  dynamic "cors" {
    for_each = var.cors
    content {
      origin          = cors.value.origin
      method          = cors.value.method
      response_header = cors.value.response_header
      max_age_seconds = cors.value.max_age_seconds
    }
  }
}
