## Metric alerts

Each family (audit config, Cloud SQL, custom roles, firewall, network, owner,
routes, storage permissions) is a log-based metric and a threshold alert
policy. `metric_alerts.<family> = false` creates neither. The OS Login
metadata and the project audit config are always managed. `moved.tf` maps the
objects of a v1.8 workspace to instance `[0]`, so the upgrade plans no destroy.

## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_project_metadata_item.enable_oslogin](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_project_metadata_item) | resource |
| [google_logging_metric.audit-config-changes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.cloud-sql-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.custom-roles-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.firewall-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.network-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.owner-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.routes-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.storage-permissions-changes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_monitoring_alert_policy.audit-config-changes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.cloud-sql-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.custom-roles-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.firewall-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.network-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.owner-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.routes-monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.storage-permissions-changes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_project_iam_audit_config.project](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_audit_config) | resource |
| [google_project_service.compute_engine](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project_service) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_audit_logging"></a> [audit\_logging](#input\_audit\_logging) | n/a | <pre>object({<br>    admin_read = optional(bool, true)<br>    data_read  = optional(bool, false)<br>    data_write = optional(bool, false)<br>  })</pre> | `{}` | no |
| <a name="input_base_name"></a> [base\_name](#input\_base\_name) | Base name | `string` | n/a | yes |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project ID | `string` | n/a | yes |
| <a name="input_metric_alerts"></a> [metric\_alerts](#input\_metric\_alerts) | Metric threshold alerts to create, per family. Every family is on by default. | <pre>object({<br>    audit_config        = optional(bool, true)<br>    cloud_sql           = optional(bool, true)<br>    custom_roles        = optional(bool, true)<br>    firewall            = optional(bool, true)<br>    network             = optional(bool, true)<br>    owner               = optional(bool, true)<br>    routes              = optional(bool, true)<br>    storage_permissions = optional(bool, true)<br>  })</pre> | `{}` | no |
| <a name="input_module_name"></a> [module\_name](#input\_module\_name) | Constant for module | `string` | `"security"` | no |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | List of notification channel resources | `list(any)` | n/a | yes |

## Outputs

No outputs.
