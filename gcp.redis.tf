# ===================================================================
# REDIS INSTANCES CONFIGURATION
# ===================================================================
# This file creates Redis instances based on settings configuration
# following the same pattern as Cloud SQL module usage

check "redis_needs_shared_vpc" {
  assert {
    condition     = length(try(local.settings.redis, {})) == 0 || local.network_enabled
    error_message = "A redis entry needs network.services_cidr. Memorystore joins the one shared VPC."
  }
}

# Create Redis instances for each configuration in settings
resource "google_redis_instance" "redis_instances" {
  for_each = try(local.settings.redis, {})

  # Basic Configuration
  name        = "${local.base_name_medium}-${each.value.name}"
  project     = local.settings.project.id
  region      = local.settings.region_name
  location_id = local.settings.zones_name[0] # Use first zone from zones_name list

  # Memory and Performance
  memory_size_gb = each.value.memory_size_gb
  tier           = each.value.tier

  # Network Configuration - VPC Integration
  # psa_network_id depends on the Private Service Access connection. With
  # PRIVATE_SERVICE_ACCESS, reserved_ip_range may name a network.services_ip_ranges
  # key; it is passed as the allocated range name. Left out, Google picks a block
  # inside the connection's ranges.
  connect_mode       = each.value.connect_mode
  authorized_network = try(module.network[0].psa_network_id, null)
  reserved_ip_range = try(
    module.network[0].services_ip_range_names[each.value.reserved_ip_range],
    each.value.reserved_ip_range,
    null,
  )

  # Security Configuration
  auth_enabled            = try(each.value.auth_enabled, true)
  transit_encryption_mode = try(each.value.transit_encryption_mode, "DISABLED")

  # Redis Configuration
  redis_version = try(each.value.redis_version, "REDIS_7_0")
  display_name  = "${local.base_name_medium}-${each.value.name}"

  # Labels for resource management
  labels = merge(local.common_labels, try(each.value.labels, {}))

  # Redis configuration parameters (optional)
  redis_configs = try(each.value.redis_configs, {})

  # Terraform refuses to destroy the instance while this is true. It lives
  # only in Terraform state, so changing it is an in-place update with no API call.
  deletion_protection = try(each.value.deletion_protection, local.workspace == "pro")

  # RDB snapshots (optional). Removing the block keeps the current mode on the
  # instance; set persistence_mode to "DISABLED" to turn snapshots off.
  dynamic "persistence_config" {
    for_each = try(each.value.persistence, null) != null ? [each.value.persistence] : []
    content {
      persistence_mode        = try(persistence_config.value.persistence_mode, "RDB")
      rdb_snapshot_period     = try(persistence_config.value.persistence_mode, "RDB") == "RDB" ? try(persistence_config.value.rdb_snapshot_period, null) : null
      rdb_snapshot_start_time = try(persistence_config.value.rdb_snapshot_start_time, null)
    }
  }

  # Maintenance policy (optional)
  dynamic "maintenance_policy" {
    for_each = try(each.value.maintenance_policy, null) != null ? [each.value.maintenance_policy] : []
    content {
      weekly_maintenance_window {
        day = maintenance_policy.value.day
        start_time {
          hours   = maintenance_policy.value.start_time.hours
          minutes = try(maintenance_policy.value.start_time.minutes, 0)
          seconds = try(maintenance_policy.value.start_time.seconds, 0)
          nanos   = try(maintenance_policy.value.start_time.nanos, 0)
        }
      }
    }
  }

  # Dependencies
  depends_on = [
    google_project_service.enabled_apis,
    module.network
  ]

  lifecycle {
    precondition {
      condition     = contains(["RDB", "DISABLED"], try(each.value.persistence.persistence_mode, "RDB"))
      error_message = "redis.${each.key}.persistence.persistence_mode must be RDB or DISABLED."
    }
    precondition {
      condition = (
        try(each.value.persistence, null) == null
        || try(each.value.persistence.persistence_mode, "RDB") != "RDB"
        || contains(["ONE_HOUR", "SIX_HOURS", "TWELVE_HOURS", "TWENTY_FOUR_HOURS"], try(each.value.persistence.rdb_snapshot_period, ""))
      )
      error_message = "redis.${each.key}.persistence.rdb_snapshot_period is required with RDB: ONE_HOUR, SIX_HOURS, TWELVE_HOURS or TWENTY_FOUR_HOURS."
    }
    precondition {
      condition = (
        try(each.value.persistence, null) == null
        || try(each.value.persistence.persistence_mode, "RDB") != "RDB"
        || !contains(["REDIS_3_2", "REDIS_4_0"], try(each.value.redis_version, "REDIS_7_0"))
      )
      error_message = "redis.${each.key}: RDB snapshots need redis_version REDIS_5_0 or later."
    }
    precondition {
      condition     = try(each.value.persistence.rdb_snapshot_start_time, null) == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?Z$", try(each.value.persistence.rdb_snapshot_start_time, "")))
      error_message = "redis.${each.key}.persistence.rdb_snapshot_start_time must be an RFC 3339 UTC timestamp, for example 2026-01-01T03:00:00Z."
    }
  }
}
