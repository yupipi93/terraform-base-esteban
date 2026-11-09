# gcp_monitoring_lb

Alert policies on an external HTTPS load balancer: latency, request count, 4xx,
404, 5xx, and 403 from the backends or from Cloud Armor.

v2.6 over v2.5: the 403 policies depend on the log-based metric they read, so
the first apply no longer fails on a metric that does not exist yet.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_logging_metric.request_count_403_backend](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.request_count_403_ca](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_monitoring_alert_policy.backend-latency](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.lb_403_ca_errors](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.lb_403_errors](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.lb_404_errors](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.lb_4xx_errors](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.lb_5xx_errors](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.request_count](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project where will be the Alerting | `string` | `""` | no |
| <a name="input_gcp_project_id_monitoring"></a> [gcp\_project\_id\_monitoring](#input\_gcp\_project\_id\_monitoring) | GCP Project source | `string` | n/a | yes |
| <a name="input_latency"></a> [latency](#input\_latency) | n/a | <pre>map(object({<br>    duration              = string<br>    threshold_value       = number<br>    alignment_period      = string<br>    severity              = string<br>    enabled               = bool<br>    notification_channels = optional(list(string))<br>  }))</pre> | <pre>{<br>  "default": {<br>    "alignment_period": "60s",<br>    "duration": "300s",<br>    "enabled": true,<br>    "notification_channels": [],<br>    "severity": "WARNING",<br>    "threshold_value": 3000<br>  }<br>}</pre> | no |
| <a name="input_load_balancer"></a> [load\_balancer](#input\_load\_balancer) | LB name to monitoring | `string` | n/a | yes |
| <a name="input_region_name"></a> [region\_name](#input\_region\_name) | GCP region name | `string` | n/a | yes |
| <a name="input_repo_iac"></a> [repo\_iac](#input\_repo\_iac) | URL or name of IAC repository | `string` | n/a | yes |
| <a name="input_request_count"></a> [request\_count](#input\_request\_count) | n/a | <pre>map(object({<br>    duration              = string<br>    threshold_value       = number<br>    alignment_period      = string<br>    severity              = string<br>    enabled               = bool<br>    notification_channels = optional(list(string))<br>  }))</pre> | <pre>{<br>  "default": {<br>    "alignment_period": "60s",<br>    "duration": "180s",<br>    "enabled": true,<br>    "notification_channels": [],<br>    "severity": "ERROR",<br>    "threshold_value": 100<br>  }<br>}</pre> | no |
| <a name="input_status_403_backends"></a> [status\_403\_backends](#input\_status\_403\_backends) | n/a | <pre>map(object({<br>    duration         = string<br>    threshold_value  = number<br>    alignment_period = string<br>    severity         = string<br>    enabled          = bool<br>    # ignore_backends       = optional(list(string)) # To Do<br>    notification_channels = optional(list(string))<br>  }))</pre> | <pre>{<br>  "default": {<br>    "alignment_period": "60s",<br>    "duration": "180s",<br>    "enabled": true,<br>    "notification_channels": [],<br>    "severity": "ERROR",<br>    "threshold_value": 100<br>  }<br>}</pre> | no |
| <a name="input_status_403_cloud_armor"></a> [status\_403\_cloud\_armor](#input\_status\_403\_cloud\_armor) | n/a | <pre>map(object({<br>    duration              = string<br>    threshold_value       = number<br>    alignment_period      = string<br>    severity              = string<br>    enabled               = bool<br>    notification_channels = optional(list(string))<br>  }))</pre> | `{}` | no |
| <a name="input_status_404_backends"></a> [status\_404\_backends](#input\_status\_404\_backends) | n/a | <pre>map(object({<br>    duration              = string<br>    threshold_value       = number<br>    alignment_period      = string<br>    severity              = string<br>    enabled               = bool<br>    ignore_backends       = optional(list(string))<br>    notification_channels = optional(list(string))<br>  }))</pre> | <pre>{<br>  "default": {<br>    "alignment_period": "60s",<br>    "duration": "180s",<br>    "enabled": true,<br>    "ignore_backends": [],<br>    "notification_channels": [],<br>    "severity": "ERROR",<br>    "threshold_value": 100<br>  }<br>}</pre> | no |
| <a name="input_status_4xx_backends"></a> [status\_4xx\_backends](#input\_status\_4xx\_backends) | n/a | <pre>map(object({<br>    duration              = string<br>    threshold_value       = number<br>    alignment_period      = string<br>    severity              = string<br>    enabled               = bool<br>    ignore_backends       = optional(list(string))<br>    notification_channels = optional(list(string))<br>  }))</pre> | <pre>{<br>  "default": {<br>    "alignment_period": "60s",<br>    "duration": "180s",<br>    "enabled": true,<br>    "ignore_backends": [],<br>    "notification_channels": [],<br>    "severity": "ERROR",<br>    "threshold_value": 100<br>  }<br>}</pre> | no |
| <a name="input_status_5xx_backends"></a> [status\_5xx\_backends](#input\_status\_5xx\_backends) | n/a | <pre>map(object({<br>    duration              = string<br>    threshold_value       = number<br>    alignment_period      = string<br>    severity              = string<br>    enabled               = bool<br>    ignore_backends       = optional(list(string))<br>    notification_channels = optional(list(string))<br>  }))</pre> | <pre>{<br>  "default": {<br>    "alignment_period": "60s",<br>    "duration": "180s",<br>    "enabled": true,<br>    "ignore_backends": [],<br>    "notification_channels": [],<br>    "severity": "ERROR",<br>    "threshold_value": 100<br>  }<br>}</pre> | no |

## Outputs

No outputs.