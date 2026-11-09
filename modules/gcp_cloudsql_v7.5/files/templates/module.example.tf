locals {
  sql = {
    # Those locals are optional. If removed, no databases or users will be created.
    # Use an empty array for it, or just remove it from the "module" too
    databases = [
      "${local.base_name_medium}--backend",
    ],
    users = [
      { name = "user-name", host = "" },
    ]
  }

}

module "cloud_sql" {
  source = "./modules/gcp_cloudsql_v7.5"

  gcp_project_id     = local.settings.project.id
  gcp_project_sys_id = local.settings.project_sys.id
  base_name          = local.base_name
  region_name        = local.settings.region_name

  ## All the below options are optional and if not provided, the default settings will be used
  dbe                     = local.settings.app.sql
  databases               = local.sql.databases
  users                   = local.sql.users
  backup_configuration    = local.settings.app.sql.backup
  maintenance_window      = local.settings.app.sql.maintenance
  deny_maintenance_period = local.settings.app.sql.deny_maintenance_period
  zones_name              = local.settings.zones_name
  special_characters_pass = local.settings.app.sql.special_password
  secrets_locations       = []                            # Global secrets as default
  net_id                  = google_compute_network.net.id # This option is mandatory if dbe.ipv4_enabled is false (no external IP)
  insights_config = {
    query_insights_enabled  = false
    query_plans_per_minute  = 0
    query_string_length     = 256
    record_application_tags = false
    record_client_address   = false
  }
  monitoring                        = local.settings.app.sql.monitoring
  flags                             = local.settings.app.sql.flags
  notification_channels             = []
  notification_channels_not_on_call = []
}
