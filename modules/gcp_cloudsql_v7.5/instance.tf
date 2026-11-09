resource "random_string" "random_suffix_sql_name" {
  length  = 4
  special = false
  upper   = false
}

resource "google_sql_database_instance" "dbe" {
  project             = var.gcp_project_id
  name                = format("%s--%s", local.m_base_name_medium, random_string.random_suffix_sql_name.result)
  database_version    = var.dbe.version
  region              = var.region_name
  deletion_protection = var.dbe.deletion_protection
  settings {
    tier                        = var.dbe.tier
    disk_autoresize             = true
    disk_size                   = var.dbe.disk.size
    disk_type                   = var.dbe.disk.type
    availability_type           = var.dbe.availability
    edition                     = var.dbe.edition
    deletion_protection_enabled = var.dbe.deletion_protection
    ip_configuration {
      ipv4_enabled    = var.dbe.ipv4_enabled
      private_network = var.net_id
      ssl_mode        = var.dbe.ssl_mode

      dynamic "authorized_networks" {
        for_each = { for item in var.dbe.allowed_networks : format("%s_%s", item.name, item.value) => item }
        iterator = address

        content {
          name  = address.value.name
          value = address.value.value
        }
      }
    }
    backup_configuration {
      enabled    = true
      location   = var.backup_configuration.location
      start_time = var.backup_configuration.start_time
      # binary_log_enabled must be false outside MySQL, point_in_time_recovery_enabled is not valid on MySQL
      binary_log_enabled             = local.is_mysql ? local.pitr_enabled : false
      point_in_time_recovery_enabled = local.is_mysql ? null : local.pitr_enabled
      transaction_log_retention_days = local.pitr_enabled ? var.backup_configuration.transaction_log_retention_days : null
      backup_retention_settings {
        retained_backups = var.backup_configuration.retained_backups
      }
    }
    maintenance_window {
      day  = var.maintenance_window.day
      hour = var.maintenance_window.hour
    }
    dynamic "deny_maintenance_period" {
      for_each = var.deny_maintenance_period == null ? [] : [var.deny_maintenance_period]
      content {
        start_date = deny_maintenance_period.value.start_date
        end_date   = deny_maintenance_period.value.end_date
        time       = deny_maintenance_period.value.time
      }
    }
    dynamic "database_flags" {
      for_each = try(var.flags, {})
      iterator = flag

      content {
        name  = flag.key
        value = flag.value
      }
    }
    insights_config {
      query_insights_enabled  = var.insights_config.query_insights_enabled
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
      query_string_length     = var.insights_config.query_string_length
      record_application_tags = var.insights_config.record_application_tags
      record_client_address   = var.insights_config.record_client_address
    }
  }
  #  lifecycle {
  #    ignore_changes = [settings[0].replication_type]
  #  }
}
