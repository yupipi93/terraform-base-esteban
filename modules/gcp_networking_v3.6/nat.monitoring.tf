locals {
  nat_alert_policy_doc = <<-EOF
        # NAT errors fixes

        [Cloud Nat Link](https://console.cloud.google.com/net-services/nat/details/%s/%s/%s?project=%s&tab=details)

        ## Dropped sent packets -> Endpoint Independence Conflict

        If you have enabled the Endpoint-Independent Mapping, then disable it and check if this errors still happens.
 
        ## Dropped sent packets -> Out Of Resources

        This errors normally means a problem allocating new ports for a virtual machine. Try to increase the ports number for vm in nat configuration and if the error persists, the number of IP addresses allocated in the NAT.

        ## NAT allocation failed
 
        Mostly this error happens when the NAT doesn't have enough IP addresses. Try to add more addresses and check if the problem persists.

        # Repository IAC
        %s
  EOF
}

resource "google_monitoring_alert_policy" "nat" {
  for_each     = var.nats
  project      = var.gcp_project_sys_id
  display_name = format("%s | %s | %s NAT", var.base_name, title(var.module_name), google_compute_router_nat.nat[each.key].name)
  enabled      = true
  combiner     = "OR"
  user_labels = {
    created_by = "terraform"
  }

  conditions {
    display_name = format("%s | %s | %s NAT | %s", var.base_name, title(var.module_name), google_compute_router_nat.nat[each.key].name, "Dropped sent packets -> Endpoint Independence Conflict")
    condition_threshold {
      filter                  = format("resource.type = \"nat_gateway\" AND (resource.labels.project_id = \"%s\" AND resource.labels.gateway_name = \"%s\") AND metric.type = \"router.googleapis.com/nat/dropped_sent_packets_count\" AND metric.labels.reason = \"ENDPOINT_INDEPENDENCE_CONFLICT\"", var.gcp_project_id, google_compute_router_nat.nat[each.key].name)
      duration                = var.monitoring.dropped_sent_endpoint_independence_conflict.duration
      comparison              = "COMPARISON_GT"
      threshold_value         = var.monitoring.dropped_sent_endpoint_independence_conflict.threshold_value
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
      aggregations {
        cross_series_reducer = "REDUCE_SUM"
        alignment_period     = var.monitoring.dropped_sent_endpoint_independence_conflict.alignment_period
        per_series_aligner   = "ALIGN_MAX"
      }


      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | %s NAT | %s", var.base_name, title(var.module_name), google_compute_router_nat.nat[each.key].name, "Dropped sent packets -> Out Of Resources")
    condition_threshold {
      filter                  = format("resource.type = \"nat_gateway\" AND (resource.labels.project_id = \"%s\" AND resource.labels.gateway_name = \"%s\") AND metric.type = \"router.googleapis.com/nat/dropped_sent_packets_count\" AND metric.labels.reason = \"OUT_OF_RESOURCES\"", var.gcp_project_id, google_compute_router_nat.nat[each.key].name)
      duration                = var.monitoring.dropped_sent_out_of_resources.duration
      comparison              = "COMPARISON_GT"
      threshold_value         = var.monitoring.dropped_sent_out_of_resources.threshold_value
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
      aggregations {
        cross_series_reducer = "REDUCE_SUM"
        alignment_period     = var.monitoring.dropped_sent_out_of_resources.alignment_period
        per_series_aligner   = "ALIGN_MAX"
      }


      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | %s NAT | %s", var.base_name, title(var.module_name), google_compute_router_nat.nat[each.key].name, "Allocation failed")
    condition_threshold {
      filter                  = format("resource.type = \"nat_gateway\" AND (resource.labels.project_id = \"%s\" AND resource.labels.gateway_name = \"%s\") AND metric.type = \"router.googleapis.com/nat/nat_allocation_failed\"", var.gcp_project_id, google_compute_router_nat.nat[each.key].name)
      duration                = var.monitoring.nat_allocation_failed.duration
      comparison              = "COMPARISON_GT"
      threshold_value         = var.monitoring.nat_allocation_failed.threshold_value
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
      aggregations {
        alignment_period   = var.monitoring.nat_allocation_failed.alignment_period
        per_series_aligner = "ALIGN_COUNT_TRUE"
      }


      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  documentation {
    content   = format(local.nat_alert_policy_doc, each.value.region, google_compute_router.router[each.key].name, google_compute_router_nat.nat[each.key].name, var.gcp_project_id, var.repo_iac)
    mime_type = "text/markdown"
  }

  notification_channels = var.monitoring.notification_channels
}
