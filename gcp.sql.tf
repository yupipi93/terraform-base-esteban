
locals {
  # Used only when an instance omits databases and users. A list on the instance
  # entry (database.<name>.databases / .users) replaces this default.
  sql_default_databases = [for name in keys(local.app_services) : "${name}-db"]
  sql_default_users = [
    for name in keys(local.app_services) : { name = "${name}-app-user", host = "" }
  ]
}

check "private_sql_needs_shared_vpc" {
  assert {
    condition = alltrue([
      for db in try(values(local.settings.database), []) :
      try(db.sql.ipv4_enabled, false) || local.network_enabled
    ])
    error_message = "A database with ipv4_enabled false needs network.services_cidr so it can take a private IP on the shared VPC."
  }
}

# Create Cloud SQL instances for each database configuration
module "cloud_sql" {
  source = "./modules/gcp_cloudsql_v7.5"

  # Loop through each database configuration in the sql section
  for_each = try(local.settings.database, {})

  gcp_project_id     = local.settings.project.id
  gcp_project_sys_id = local.settings.project_sys.id
  base_name          = "${local.base_name}-${each.value.name}" # Include database key in name
  region_name        = local.settings.region_name

  ## All the below options are optional and if not provided, the default settings will be used
  dbe = try(each.value.sql, null)
  databases = length(try(each.value.databases, [])) > 0 ? [
    for db in each.value.databases : try(db.name, db)
  ] : local.sql_default_databases
  users = length(try(each.value.users, [])) > 0 ? [
    for user in each.value.users : {
      name = try(user.name, user)
      host = try(user.host, "")
    }
  ] : local.sql_default_users
  backup_configuration    = try(each.value.sql.backup, null)
  maintenance_window      = try(each.value.sql.maintenance, null)
  deny_maintenance_period = try(each.value.sql.deny_maintenance_period, null)
  zones_name              = try(local.settings.zones_name, [])
  special_characters_pass = try(each.value.sql.special_password, {})
  secrets_locations       = [local.settings.region_name] # Use regional location for secrets
  # psa_network_id depends on the Private Service Access connection, so a
  # private instance is created after the peering it takes its IP from.
  net_id = try(each.value.sql.ipv4_enabled, false) ? null : try(module.network[0].psa_network_id, null)
  insights_config = {
    query_insights_enabled  = try(each.value.sql.insights.enabled, false)
    query_plans_per_minute  = try(each.value.sql.insights.query_plans_per_minute, 0)
    query_string_length     = try(each.value.sql.insights.query_string_length, 2048)
    record_application_tags = try(each.value.sql.insights.record_application_tags, false)
    record_client_address   = try(each.value.sql.insights.record_client_address, false)
  }
  monitoring                        = try(each.value.sql.monitoring, {})
  flags                             = try(each.value.sql.flags, {})
  notification_channels             = [google_monitoring_notification_channel.security_alerts.id]
  notification_channels_not_on_call = [google_monitoring_notification_channel.security_alerts.id]
}
