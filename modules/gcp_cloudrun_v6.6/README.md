## Changes in v6.6

`cloudrun.binary_authorization` (default `false`): `true` sets
`binary_authorization { use_default = true }` on the service, so every deploy is
checked against the project's Binary Authorization policy. Without it the policy
exists and Cloud Run never asks it.

## Breaking changes

Since 27/10/2023 you need to add the var service\_account.name by hand, matching the name of the already created account, to be backwards compatible.

Since 21/11/2023 the module uses the google\_cloud\_run\_v2\_service resource, so old versions of the module are not compatible anymore. The same options are available, so the only problem is that the cloudrun will be recreated.

## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google-beta_google_cloud_run_v2_service.service](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_cloud_run_v2_service) | resource |
| [google_cloud_run_v2_service_iam_member.permissions](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service_iam_member) | resource |
| [google_monitoring_alert_policy.cloud_run](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_project_service.cloudrun](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_project_service.iam](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_project_service.monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_secret_manager_secret_iam_member.secrets_permissions](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |
| [google_service_account.cloudrun](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_base_name"></a> [base\_name](#input\_base\_name) | Base name | `string` | n/a | yes |
| <a name="input_cloudrun"></a> [cloudrun](#input\_cloudrun) | n/a | <pre>object({<br>    execution_environment     = optional(string, "EXECUTION_ENVIRONMENT_GEN2")<br>    concurrency               = optional(number, 0)<br>    ingress                   = optional(string, "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER")<br>    launch_stage              = optional(string, null)<br>    timeout                   = optional(string, "3600s")<br>    cloud_sql_instances_mount = optional(list(string), null)<br><br>    containers = list(object({<br>      name        = string<br>      image       = string<br>      command     = optional(list(string), null)<br>      args        = optional(list(string), null)<br>      working_dir = optional(string, null)<br>      depends_on  = optional(list(string), null)<br><br>      volumes = optional(map(object({<br>        mount_path = string<br><br>        gcs = optional(object({<br>          storage_bucket = string<br>          read_only      = optional(bool, false)<br>        }), null)<br><br>        empty_dir = optional(object({<br>          medium     = optional(string, "MEMORY")<br>          size_limit = optional(string, null)<br>        }), null)<br><br>        secret = optional(object({<br>          secret       = string<br>          default_mode = optional(string, "0444")<br>          items = object({<br>            path    = string<br>            version = optional(string, "latest")<br>          })<br>        }), null)<br><br>      })), {})<br><br>      liveness_probe = optional(object({<br>        initial_delay_seconds = optional(number, null)<br>        timeout_seconds       = optional(number, null)<br>        period_seconds        = optional(number, null)<br>        failure_threshold     = optional(number, null)<br><br>        http_get = optional(object({<br>          path = optional(string, null)<br>          port = optional(number, null)<br><br>          http_headers = optional(list(object({<br>            name  = string<br>            value = optional(string, null)<br>          })), [])<br><br>        }), null)<br><br>        # Not currently supported. But TF message is "Exactly one probe action must be set (http_get, tcp_socket, or grpc)"<br>        #tcp_socket = optional(object({<br>        #  port = optional(number, null)<br>        #}), null)<br><br>        grpc = optional(object({<br>          port    = optional(number, null)<br>          service = optional(string, null)<br>        }), null)<br><br>      }), null)<br><br>      startup_probe = optional(object({<br>        initial_delay_seconds = optional(number, null)<br>        timeout_seconds       = optional(number, null)<br>        period_seconds        = optional(number, null)<br>        failure_threshold     = optional(number, null)<br><br>        http_get = optional(object({<br>          path = optional(string, null)<br>          port = optional(number, null)<br><br>          http_headers = optional(list(object({<br>            name  = string<br>            value = optional(string, null)<br>          })), [])<br><br>        }), null)<br><br>        tcp_socket = optional(object({<br>          port = number<br>        }), null)<br><br>        grpc = optional(object({<br>          port    = optional(number)<br>          service = optional(string)<br>        }), null)<br><br>      }), null)<br><br>      envs = optional(list(object({<br>        name  = string<br>        value = any<br>      })), [])<br><br>      secrets = optional(list(object({<br>        name    = string<br>        secret  = string<br>        version = optional(string, "latest")<br>      })), [])<br><br>      resources = optional(object({<br>        cpu               = optional(string, "2000m")<br>        memory            = optional(string, "2048Mi")<br>        startup_cpu_boost = optional(bool, true)<br>        cpu_idle          = optional(bool, false)<br>      }), {})<br><br>      ports = optional(object({<br>        name           = optional(string, "http1")<br>        container_port = number<br>      }), null)<br>    }))<br><br>    vpc_access = optional(object({<br>      connector = optional(string, null)<br>      egress    = optional(string, "ALL_TRAFFIC")<br><br>      network_interfaces = optional(object({<br>        network    = string<br>        subnetwork = string<br>        tags       = optional(list(string), null)<br>      }), null)<br>    }), null)<br><br>    autoscaling = optional(object({<br>      min = optional(number, 0)<br>      max = optional(number, 10)<br>    }), {})<br><br>    annotations = optional(map(string), null)<br>    iap_enabled = optional(bool, false)<br><br>    binary_authorization = optional(bool, false)<br>  })</pre> | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Whether Terraform will be prevented from destroying the service. Defaults to true | `bool` | `true` | no |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project ID | `string` | n/a | yes |
| <a name="input_gcp_project_sys_id"></a> [gcp\_project\_sys\_id](#input\_gcp\_project\_sys\_id) | GCP Project ID SYS | `string` | n/a | yes |
| <a name="input_monitoring"></a> [monitoring](#input\_monitoring) | Constants | <pre>object({<br>    cpu = optional(object({<br>      duration         = optional(string, "1800s")<br>      threshold_value  = optional(number, 0.85)<br>      alignment_period = optional(string, "60s")<br>    }), {})<br>    memory = optional(object({<br>      duration         = optional(string, "300s")<br>      threshold_value  = optional(number, 0.95)<br>      alignment_period = optional(string, "60s")<br>    }), {})<br><br>    instances_count = optional(object({<br>      duration             = optional(string, "900s")<br>      alignment_period     = optional(string, "60s")<br>      trigger_count_series = optional(number, 1)<br>    }), {})<br><br>    request_5XX_count = optional(object({<br>      duration             = optional(string, "300s")<br>      threshold_value      = optional(number, 50)<br>      alignment_period     = optional(string, "60s")<br>      trigger_count_series = optional(number, 1)<br>    }), {})<br><br>    notification_channels = optional(list(string), [])<br>    repo_iac              = string<br>  })</pre> | n/a | yes |
| <a name="input_permissions"></a> [permissions](#input\_permissions) | Permissions CloudRun | <pre>map(object({<br>    account     = string,<br>    permissions = list(string)<br>  }))</pre> | `{}` | no |
| <a name="input_region_name"></a> [region\_name](#input\_region\_name) | GCP region name | `string` | n/a | yes |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Set the external to true and put the external service account in name, or set a name to create a new internal service account. | <pre>object({<br>    name     = string<br>    external = optional(bool, false)<br>  })</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloudrun_name"></a> [cloudrun\_name](#output\_cloudrun\_name) | n/a |
| <a name="output_cloudrun_service_url"></a> [cloudrun\_service\_url](#output\_cloudrun\_service\_url) | n/a |
| <a name="output_sa_email"></a> [sa\_email](#output\_sa\_email) | n/a |
| <a name="output_sa_id"></a> [sa\_id](#output\_sa\_id) | n/a |