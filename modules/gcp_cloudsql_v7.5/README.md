# Module requirements

From version v5.5 and above, you need to update the Google Cloud Provider to >=4.75.0

From version v7.5, `backup_configuration` takes `point_in_time_recovery_enabled` and
`transaction_log_retention_days`. MySQL gets point-in-time recovery from the binary log,
PostgreSQL and SQL Server from `point_in_time_recovery_enabled`. Leaving
`point_in_time_recovery_enabled` unset keeps the v7.4 behaviour (MySQL follows
`dbe.binary_log_enabled`, other engines off).

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 6.0 |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_monitoring_alert_policy.sql_master_disk](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.sql_master_disk_autoresize](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.sql_master_log_entries](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.sql_master_performance](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.sql_replicas_disk](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.sql_replicas_performance](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_project_service.secret_manager](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_secret_manager_secret.admin_name](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret.admin_password](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret.user_password](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret_version.admin_name](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_secret_manager_secret_version.admin_password](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_secret_manager_secret_version.user_password](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_sql_database.dbe](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database) | resource |
| [google_sql_database_instance.dbe](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance) | resource |
| [google_sql_database_instance.dbe_slave](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance) | resource |
| [google_sql_user.admin](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_user) | resource |
| [google_sql_user.user](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_user) | resource |
| [random_id.admin_name](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_id.admin_sufix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_password.admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.random_suffix_sql_name](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_configuration"></a> [backup\_configuration](#input\_backup\_configuration) | Cloud SQL Backup configuration | <pre>object({<br>    start_time       = optional(string, "03:00")<br>    retained_backups = optional(number, 7)<br>    location         = optional(string, null)<br>    point_in_time_recovery_enabled = optional(bool, null)<br>    transaction_log_retention_days = optional(number, null)<br>  })</pre> | `{}` | no |
| <a name="input_base_name"></a> [base\_name](#input\_base\_name) | Base name | `string` | n/a | yes |
| <a name="input_databases"></a> [databases](#input\_databases) | n/a | `list(string)` | `[]` | no |
| <a name="input_dbe"></a> [dbe](#input\_dbe) | n/a | <pre>object({<br>    version      = optional(string, "MYSQL_8_0")<br>    tier         = optional(string, "db-f1-micro")<br>    availability = optional(string, "ZONAL")<br>    edition      = optional(string, "ENTERPRISE")<br>    ipv4_enabled = optional(bool, false)<br>    ssl_mode     = optional(string, "ENCRYPTED_ONLY")<br>    allowed_networks = optional(list(object({<br>      name  = optional(string, "")<br>      value = string<br>    })), [])<br>    disk = optional(object({<br>      type = optional(string, "PD_SSD")<br>      size = optional(number, 10)<br>    }), {})<br>    binary_log_enabled  = optional(bool, true)<br>    replica             = optional(number, 0)<br>    deletion_protection = optional(bool, true)<br>    flags               = optional(map(string))<br>  })</pre> | `{}` | no |
| <a name="input_flags"></a> [flags](#input\_flags) | n/a | `map` | `{}` | no |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project ID | `string` | n/a | yes |
| <a name="input_gcp_project_sys_id"></a> [gcp\_project\_sys\_id](#input\_gcp\_project\_sys\_id) | GCP SYS Project ID | `string` | n/a | yes |
| <a name="input_insights_config"></a> [insights\_config](#input\_insights\_config) | Active the Query Insights in the database | <pre>object({<br>    query_insights_enabled  = optional(bool, false)<br>    query_plans_per_minute  = optional(number, 0)<br>    query_string_length     = optional(number, 256)<br>    record_application_tags = optional(bool, false)<br>    record_client_address   = optional(bool, false)<br>  })</pre> | `{}` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Cloud SQL maintenance window | <pre>object({<br>    day  = optional(number, 2)<br>    hour = optional(number, 7)<br>  })</pre> | `{}` | no |
| <a name="input_module_name"></a> [module\_name](#input\_module\_name) | Constant for module | `string` | `"cloudsql"` | no |
| <a name="input_monitoring"></a> [monitoring](#input\_monitoring) | n/a | <pre>object({<br>    cpu = optional(object({<br>      duration         = optional(string, "1800s")<br>      threshold_value  = optional(number, 0.85)<br>      alignment_period = optional(string, "60s")<br>    }), {})<br>    memory = optional(object({<br>      duration         = optional(string, "300s")<br>      threshold_value  = optional(number, 0.85)<br>      limit_ram        = optional(number, null)<br>      alignment_period = optional(string, "60s")<br>    }), {})<br>    connections = optional(object({<br>      duration         = optional(string, "120s")<br>      threshold_value  = optional(number, 0.85)<br>      max_connections  = optional(number, null)<br>      alignment_period = optional(string, "60s")<br>    }), {})<br>    disk_space = optional(object({<br>      duration         = optional(string, "600s")<br>      threshold_value  = optional(number, 0.85)<br>      alignment_period = optional(string, "60s")<br>    }), {})<br>    disk_iops = optional(object({<br>      duration         = optional(string, "1800s")<br>      threshold_value  = optional(number, 0.85)<br>      alignment_period = optional(string, "60s")<br>    }), {})<br>    log_entries = optional(object({<br>      duration         = optional(string, "60s")<br>      threshold_value  = optional(number, 0)<br>      alignment_period = optional(string, "60s")<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_net_id"></a> [net\_id](#input\_net\_id) | n/a | `string` | `""` | no |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | List of notification channel resources | `list(any)` | `[]` | no |
| <a name="input_notification_channels_not_on_call"></a> [notification\_channels\_not\_on\_call](#input\_notification\_channels\_not\_on\_call) | List of notification channel resources | `list(any)` | `[]` | no |
| <a name="input_region_name"></a> [region\_name](#input\_region\_name) | Region name | `string` | n/a | yes |
| <a name="input_secrets_locations"></a> [secrets\_locations](#input\_secrets\_locations) | n/a | `list(string)` | `[]` | no |
| <a name="input_special_characters_pass"></a> [special\_characters\_pass](#input\_special\_characters\_pass) | n/a | <pre>object({<br>    enabled    = optional(bool, false)<br>    characters = optional(string, "_%@<>:")<br>  })</pre> | `{}` | no |
| <a name="input_users"></a> [users](#input\_users) | n/a | <pre>list(object({<br>    name = string<br>    host = string<br>  }))</pre> | `[]` | no |
| <a name="input_zones_name"></a> [zones\_name](#input\_zones\_name) | Inherited variables | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_connection_name"></a> [connection\_name](#output\_connection\_name) | Database Engine Connection Name |
| <a name="output_db_engine_name"></a> [db\_engine\_name](#output\_db\_engine\_name) | Database Engine Name |
| <a name="output_db_engine_private_ip"></a> [db\_engine\_private\_ip](#output\_db\_engine\_private\_ip) | Database Engine Private IP |
| <a name="output_db_engine_public_ip"></a> [db\_engine\_public\_ip](#output\_db\_engine\_public\_ip) | Database Engine Public IP |
| <a name="output_db_engine_sa"></a> [db\_engine\_sa](#output\_db\_engine\_sa) | Database Engine SA |
| <a name="output_secret_admin_name"></a> [secret\_admin\_name](#output\_secret\_admin\_name) | Admin DB Username Secret ID |
| <a name="output_secret_admin_password"></a> [secret\_admin\_password](#output\_secret\_admin\_password) | Admin DB Password Secret ID |
| <a name="output_secret_users_password"></a> [secret\_users\_password](#output\_secret\_users\_password) | Users DB Secret ID |
| <a name="output_service_account_name"></a> [service\_account\_name](#output\_service\_account\_name) | Service Account Name |