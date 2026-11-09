module "cloudrun_backend" {
  source = "./modules/gcp_cloudrun_v6.6"

  base_name          = local.base_name
  gcp_project_id     = local.settings.project.id
  gcp_project_sys_id = local.settings.project_sys.id
  region_name        = local.settings.region_name

  cloudrun = {
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"             // (Optional) EXECUTION_ENVIRONMENT_GEN1 or EXECUTION_ENVIRONMENT_GEN2
    concurrency           = 0                                        // (Optional)
    ingress               = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" // (Optional) INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER
    launch_stage          = "GA"                                     // Set the launch stage. BETA is used for some things like for example direct VPC or gcs_volumes.
    timeout               = "3600s"                                  // (Optional)

    // Mount one or more CloudSQL instance as socket in the "/cloudsql" path. The internal ip connection is preferred if possible.
    // Multiple databases can be provided here to be mounted in the same path
    cloud_sql_instances_mount = ["database-project:database-region:database-name"]

    // Multiple containers can be created in a sidecar way using this list
    containers = [
      {
        name        = "something-running"
        image       = "nginx:latest"
        command     = ["nginx"]           // (Optional)
        args        = ["-t"]              // (Optional)
        working_dir = "/nginx"            // (Optional)
        depends_on  = ["other_container"] // (Optional)

        // This feature requires to change the launch_stage to BETA for now (untill will be available in GA)
        gcs_volumes = {
          nice-bucket = {
            mount_path = "/static"
            gcs = {
              storage_bucket = "nice-bucket-to-mount"
              read_only      = false // (Optional)
            }
          },

          cache = {
            mount_path = "/cache"
            empty_dir = {
              medium     = "MEMORY" // Optional: For now only MEMORY is allowd
              size_limit = "64Mi"   // Optional: The memory usage limit.
            }
          }
          sa = {
            mount_path = "/credentials/"
            secret = {
              secret       = "secret-id"
              default_mode = "0444" // (Optional): The default mode of the secret
              items = {
                path    = "filename.extension"
                version = "latest" // (Optional): The version of the secret to use
              }
            }
          }
        }

        // Environment variables. This is optional.
        envs = [
          {
            name  = "Foo"
            value = "Bar"
          }
        ]

        // Secrets to mount as env variables. This is optional.
        // The CloudRun service account will receive the "secretmanager.secretAccessor" role automatically in the provided secret
        secrets = [
          {
            name    = "Foo"
            secret  = google_secret_manager_secret.secret.secret_id
            project = local.settings.project.id
            version = "latest" // (Optional)
          }
        ]

        // Resources to assign to the cloudrun. It is optional and if not provided the default will be used.
        resources = {
          cpu               = "2000m"
          memory            = "2048Mi"
          startup_cpu_boost = true
          cpu_idle          = false
        }

        ports = {
          name           = "http1" // Protocol to use in the connections (http1 or h2c).
          container_port = "8000"  # Mandatory
        }

        // Liveness probe. It is optional and if not provided it won't be created
        liveness_probe = {
          failure_threshold     = "3"
          initial_delay_seconds = "0"
          timeout_seconds       = "1"
          period_seconds        = "10"
          http_get = {
            path = "/"
            port = "8080"
            http_headers = [
              {
                name  = "header_name"
                value = "header_test"
              },
              {
                name  = "header_name2"
                value = "header_test2"
              },
            ]
          }
          grpc = {
            port    = "8080"
            service = ""
          }
          # Not currently supported. But TF message is "Exactly one probe action must be set (http_get, tcp_socket, or grpc)"
          #tcp_socket = {
          #  port = "8080"
          #}
        }

        // Startup probe. It is optional and if not provided it will be created by default or not depending on your configurations
        startup_probe = {
          failure_threshold     = "3"
          initial_delay_seconds = "0"
          timeout_seconds       = "1"
          period_seconds        = "10"
          http_get = {
            path = "/"
            port = "8080"
            http_headers = [
              {
                name  = "header_name"
                value = "header_test"
              },
              {
                name  = "header_name2"
                value = "header_test2"
              },
            ]
          }
          grpc = {
            port    = "8080"
            service = ""
          }
          tcp_socket = {
            port = "8080"
          }
        }
      }
    ]

    // This is optional. The connector and the network interfaces options must not be used together.
    //   connector = Uses the provided vpc connnector to connect the CloudRun to the network.
    //   network_interfaces = Create a Direct VPC access which connects the CloudRun directly to the provided network/subnetwork.
    // If not provided, no connection will be created.
    vpc_access = {
      connector = google_vpc_access_connector.connector.id // (Optional)
      egress    = "ALL_TRAFFIC"                            // (Optional) ALL_TRAFFIC or PRIVATE_RANGES_ONLY

      // To use this options you should enable the BETA launch_stage (launch_stage = "BETA")
      network_interfaces = {
        network    = "network-name"
        subnetwork = "subnet-name"
        tags       = ["network-tag1", "network-tag2"] // (Optional) Network tags to be added to the CR
      }
    }

    // Autoscaling... this is optional and if not provided the default will be used.
    autoscaling = {
      min = 0
      max = 10
    }

    // Add custom annotations to the resource. This is optional
    annotations = {
      "fire" = "in the hole"
    }
  }

  // You must provide only one of the following service account options
  service_account = {
    // In case we want a service account created inside the module we just put the name in "name"
    name     = "cloudrun-internal-sa"
    external = false // Optional
    // In case we want to pass an external service account, we put the service account in name and marked it as external
    name     = google_service_account.external.email
    external = true
  }

  permissions = {
    cloudbuild = {
      account     = format("serviceAccount:%s@cloudbuild.gserviceaccount.com", local.settings.project.number)
      permissions = ["roles/run.admin"]
    },
    cloudrun_all = {
      account     = format("allUsers")
      permissions = ["roles/run.invoker"]
    }
  }

  // Only the repo_iac option is mandatory. The rest are optional.
  monitoring = {
    cpu = {
      duration         = "1800s"
      threshold_value  = 0.85
      alignment_period = "60s"
    }
    memory = {
      duration         = "300s"
      threshold_value  = 0.95
      alignment_period = "60s"
    }

    instances_count = {
      duration             = "900s"
      alignment_period     = "60s"
      trigger_count_series = 1
    }

    request_5XX_count = {
      duration             = "300s"
      threshold_value      = 50
      alignment_period     = "60s"
      trigger_count_series = 1
    }

    notification_channels = [google_monitoring_notification_channel.test.name]
    repo_iac              = ""
  }
}
