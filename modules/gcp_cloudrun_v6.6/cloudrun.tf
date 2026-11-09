resource "google_service_account" "cloudrun" {
  count        = var.service_account.external ? 0 : 1
  project      = var.gcp_project_id
  account_id   = var.service_account.name
  display_name = format("Service Account for %s", local.m_base_name_medium)
}

resource "google_cloud_run_v2_service" "service" {
  project             = var.gcp_project_id
  name                = local.m_base_name
  location            = var.region_name
  ingress             = var.cloudrun.ingress
  launch_stage        = var.cloudrun.launch_stage
  provider            = google-beta
  deletion_protection = var.deletion_protection
  iap_enabled         = var.cloudrun.iap_enabled

  dynamic "binary_authorization" {
    for_each = var.cloudrun.binary_authorization ? [1] : []
    content {
      use_default = true
    }
  }

  template {
    max_instance_request_concurrency = var.cloudrun.concurrency
    execution_environment            = var.cloudrun.execution_environment
    timeout                          = var.cloudrun.timeout
    service_account                  = var.service_account.external ? var.service_account.name : google_service_account.cloudrun[0].email
    annotations                      = var.cloudrun.annotations

    scaling {
      min_instance_count = var.cloudrun.autoscaling.min
      max_instance_count = var.cloudrun.autoscaling.max
    }

    dynamic "volumes" {
      for_each = merge([
        for cData in var.cloudrun.containers : {
          for vName, vData in cData.volumes : "${cData.name}_${vName}" => vData
        }
      ]...)
      content {
        name = volumes.key

        // GCP Storage
        dynamic "gcs" {
          for_each = volumes.value.gcs != null ? { d = "d" } : {}
          content {
            bucket    = volumes.value.gcs.storage_bucket
            read_only = volumes.value.gcs.read_only
          }
        }

        // Empty dir
        dynamic "empty_dir" {
          for_each = volumes.value.empty_dir != null ? { d = "d" } : {}
          content {
            medium     = volumes.value.empty_dir.medium
            size_limit = volumes.value.empty_dir.size_limit
          }
        }

        // Secrets
        dynamic "secret" {
          for_each = volumes.value.secret != null ? { d = "d" } : {}
          content {
            secret       = volumes.value.secret.secret
            default_mode = volumes.value.secret.default_mode
            items {
              path    = volumes.value.secret.items.path
              version = volumes.value.secret.items.version
            }
          }
        }
      }
    }

    dynamic "volumes" {
      for_each = var.cloudrun.cloud_sql_instances_mount != null ? { d = "d" } : {}
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = var.cloudrun.cloud_sql_instances_mount
        }
      }
    }

    dynamic "containers" {
      for_each = var.cloudrun.containers
      content {
        name        = containers.value.name
        image       = containers.value.image
        command     = containers.value.command
        args        = containers.value.args
        working_dir = containers.value.working_dir

        depends_on = containers.value.depends_on

        dynamic "env" {
          for_each = containers.value.envs
          content {
            name  = env.value.name
            value = env.value.value
          }
        }

        dynamic "env" {
          for_each = containers.value.secrets
          content {
            name = env.value.name

            value_source {
              secret_key_ref {
                secret  = env.value.secret
                version = env.value.version
              }
            }
          }
        }

        // Mount Cloud Storage volumes
        dynamic "volume_mounts" {
          for_each = {
            for vName, vData in containers.value.volumes : "${containers.value.name}_${vName}" => vData
          }
          content {
            name       = volume_mounts.key
            mount_path = volume_mounts.value.mount_path
          }
        }


        // The databases mount configuration is applied only in the first container (Google limitations)
        dynamic "volume_mounts" {
          for_each = alltrue([
            var.cloudrun.cloud_sql_instances_mount != null,
            containers.value.name == var.cloudrun.containers[0].name
          ]) ? { d = "d" } : {}

          content {
            name       = "cloudsql"
            mount_path = "/cloudsql"
          }
        }
        resources {
          limits = {
            cpu    = containers.value.resources.cpu
            memory = containers.value.resources.memory
          }
          cpu_idle          = containers.value.resources.cpu_idle
          startup_cpu_boost = containers.value.resources.startup_cpu_boost
        }

        dynamic "ports" {
          for_each = containers.value.ports != null ? ["dummy"] : []
          content {
            name           = containers.value.ports.name
            container_port = containers.value.ports.container_port
          }
        }

        dynamic "liveness_probe" {
          for_each = containers.value.liveness_probe != null ? [1] : []
          content {
            failure_threshold     = containers.value.liveness_probe.failure_threshold
            initial_delay_seconds = containers.value.liveness_probe.initial_delay_seconds
            timeout_seconds       = containers.value.liveness_probe.timeout_seconds
            period_seconds        = containers.value.liveness_probe.period_seconds
            dynamic "http_get" {
              for_each = containers.value.liveness_probe.http_get != null ? [1] : []
              content {
                path = containers.value.liveness_probe.http_get.path
                port = containers.value.liveness_probe.http_get.port
                dynamic "http_headers" {
                  for_each = containers.value.liveness_probe.http_get.http_headers
                  content {
                    name  = http_headers.value["name"]
                    value = http_headers.value["value"]
                  }
                }
              }
            }
            dynamic "grpc" {
              for_each = containers.value.liveness_probe.grpc != null ? [1] : []
              content {
                port    = containers.value.liveness_probe.grpc.port
                service = containers.value.liveness_probe.grpc.service
              }
            }
            # Not currently supported. But TF message is "Exactly one probe action must be set (http_get, tcp_socket, or grpc)"
            #dynamic "tcp_socket" {
            #  for_each = containers.value.liveness_probe.tcp_socket != null ? [1] : []
            #  content {
            #    port = containers.value.liveness_probe.tcp_socket.port
            #  }
            #}
          }
        }

        dynamic "startup_probe" {
          for_each = containers.value.startup_probe != null ? [1] : []
          content {
            failure_threshold     = containers.value.startup_probe.failure_threshold
            initial_delay_seconds = containers.value.startup_probe.initial_delay_seconds
            timeout_seconds       = containers.value.startup_probe.timeout_seconds
            period_seconds        = containers.value.startup_probe.period_seconds
            dynamic "http_get" {
              for_each = containers.value.startup_probe.http_get != null ? [1] : []
              content {
                path = containers.value.startup_probe.http_get.path
                port = containers.value.startup_probe.http_get.port
                dynamic "http_headers" {
                  for_each = containers.value.startup_probe.http_get.http_headers
                  content {
                    name  = http_headers.value["name"]
                    value = http_headers.value["value"]
                  }
                }
              }
            }
            dynamic "grpc" {
              for_each = containers.value.startup_probe.grpc != null ? [1] : []
              content {
                port    = containers.value.startup_probe.grpc.port
                service = containers.value.startup_probe.grpc.service
              }
            }
            dynamic "tcp_socket" {
              for_each = containers.value.startup_probe.tcp_socket != null ? [1] : []
              content {
                port = containers.value.startup_probe.tcp_socket.port
              }
            }
          }
        }
      }
    }


    dynamic "vpc_access" {
      for_each = var.cloudrun.vpc_access != null ? ["dummy"] : []
      content {
        connector = var.cloudrun.vpc_access.connector
        egress    = var.cloudrun.vpc_access.egress

        dynamic "network_interfaces" {
          for_each = var.cloudrun.vpc_access.network_interfaces != null ? ["dummy"] : []
          content {
            network    = var.cloudrun.vpc_access.network_interfaces.network
            subnetwork = var.cloudrun.vpc_access.network_interfaces.subnetwork
            tags       = var.cloudrun.vpc_access.network_interfaces.tags
          }
        }
      }
    }
  }

  depends_on = [
    google_service_account.cloudrun,
    google_project_service.cloudrun,
    google_secret_manager_secret_iam_member.secrets_permissions
  ]
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].containers[0].image,
      template[0].containers[1].image,
      template[0].containers[2].image,
      template[0].containers[3].image,
      template[0].containers[4].image,
      template[0].containers[5].image,
      template[0].containers[6].image,
      template[0].containers[7].image,
      template[0].containers[8].image,
      template[0].containers[9].image,
      template[0].labels["client.knative.dev/nonce"],
      template[0].scaling,
      scaling,
    ]
  }
}

/*
resource "google_cloud_run_service" "service" {
  lifecycle {
    ignore_changes = [
      metadata[0].annotations["client.knative.dev/user-image"],
      metadata[0].annotations["run.googleapis.com/client-name"],
      metadata[0].annotations["run.googleapis.com/client-version"],
      metadata[0].annotations["run.googleapis.com/ingress-status"],
      metadata[0].annotations["run.googleapis.com/launch-stage"],
      metadata[0].annotations["run.googleapis.com/operation-id"],
      metadata[0].annotations["serving.knative.dev/creator"],
      metadata[0].annotations["serving.knative.dev/lastModifier"],
      metadata[0].labels["cloud.googleapis.com/location"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"],
      template[0].metadata[0].annotations["run.googleapis.com/sandbox"],
      template[0].metadata[0].labels["run.googleapis.com/startupProbeType"],
      template[0].spec[0].containers[0].image,
      metadata[0].effective_annotations["run.googleapis.com/launch-stage"],
    ]
  }
  depends_on = [
    google_service_account.cloudrun,
    google_project_service.cloudrun,
    google_secret_manager_secret_iam_member.secrets_permissions
  ]
}
*/
