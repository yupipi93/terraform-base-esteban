module "monitoring_load_balancing" {
  source                    = "./modules/gcp_monitoring_lb_v2.6"
  gcp_project_id            = local.settings.project_sys.id
  gcp_project_id_monitoring = local.settings.project.id
  region_name               = local.settings.region_name
  load_balancer             = google_compute_url_map.https.name
  repo_iac                  = local.settings.repo_iac

  ### Alerts Configuration ###
  # If you dont need any alert you can leave it blank so it wont be created:
  # status_403_backends = {} // This alert wont be created
  #
  # You can create multiple alerts for the same metric with different configurations using blocks inside the variables:
  # "low" = merge(
  #   local.settings.monitoring.lb.latency,
  #   {
  #     notification_channels = [google_monitoring_notification_channel.ticket_low.id]
  #   }
  # )

  latency = {
    "main" = merge(
      local.settings.monitoring.lb.latency,
      {
        notification_channels = [google_monitoring_notification_channel.ticket_high.id]
      }
    )
  }
  request_count = {
    "main" = merge(
      local.settings.monitoring.lb.request_count,
      {
        notification_channels = [google_monitoring_notification_channel.ticket_low.id]
      }
    )
  }
  status_403_cloud_armor = { # This alert wont be created by default
    "main" = merge(
      local.settings.monitoring.lb.status_403_cloud_armor,
      {
        notification_channels = [google_monitoring_notification_channel.ticket_high.id]
      }
    )
  }
  status_403_backends = {
    "main" = merge(
      local.settings.monitoring.lb.status_403_backends,
      {
        notification_channels = [google_monitoring_notification_channel.ticket_high.id]
      }
    )
  }
  status_404_backends = {
    "main" = merge(
      local.settings.monitoring.lb.status_404_backends,
      {
        ignore_backends       = []
        notification_channels = [google_monitoring_notification_channel.ticket_high.id]
      }
    )
  }

  status_4xx_backends = {
    "main" = merge(
      local.settings.monitoring.lb.status_4xx_backends,
      {
        ignore_backends       = []
        notification_channels = [google_monitoring_notification_channel.ticket_high.id]
      }
    )
  }
  status_5xx_backends = {
    "main" = merge(
      local.settings.monitoring.lb.status_5xx_backends,
      {
        ignore_backends       = []
        notification_channels = [google_monitoring_notification_channel.ticket_high.id]
      }
    )
  }
}