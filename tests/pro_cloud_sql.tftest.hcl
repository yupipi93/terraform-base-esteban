# The Cloud SQL module with the instance settings of settings/pro.yaml, passed
# the way gcp.sql.tf passes them (dbe, backup, maintenance and flags from
# database.<name>.sql). It checks what the module makes of them: pro.tftest.hcl
# checks that the pro settings ask for it.

mock_provider "google" {}
mock_provider "random" {}

run "pro_cloud_sql_instance" {
  command = plan

  module {
    source = "./modules/gcp_cloudsql_v7.5"
  }

  variables {
    gcp_project_id       = "example-app-pro"
    gcp_project_sys_id   = "example-app-pro"
    base_name            = "app-main"
    region_name          = "europe-west1"
    zones_name           = ["europe-west1-b"]
    net_id               = "projects/example-app-pro/global/networks/app-pro"
    dbe                  = yamldecode(file("settings/pro.yaml")).database.main.sql
    backup_configuration = yamldecode(file("settings/pro.yaml")).database.main.sql.backup
    maintenance_window   = yamldecode(file("settings/pro.yaml")).database.main.sql.maintenance
    flags                = yamldecode(file("settings/pro.yaml")).database.main.sql.flags
  }

  assert {
    condition     = google_sql_database_instance.dbe.settings[0].availability_type == "REGIONAL"
    error_message = "The pro instance is regional."
  }

  assert {
    condition     = google_sql_database_instance.dbe.deletion_protection && google_sql_database_instance.dbe.settings[0].deletion_protection_enabled
    error_message = "The pro instance is protected in Terraform and in the API."
  }

  assert {
    condition = (
      google_sql_database_instance.dbe.settings[0].backup_configuration[0].enabled
      && google_sql_database_instance.dbe.settings[0].backup_configuration[0].point_in_time_recovery_enabled
      && google_sql_database_instance.dbe.settings[0].backup_configuration[0].transaction_log_retention_days == 7
    )
    error_message = "The pro instance has backups and point-in-time recovery with 7 days of WAL."
  }

  assert {
    condition     = google_sql_database_instance.dbe.settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "The pro instance has no public IP."
  }
}
