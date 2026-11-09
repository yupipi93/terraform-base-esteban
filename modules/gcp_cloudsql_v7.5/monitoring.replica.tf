locals {
  # For now the replicas are equal to the master, but this code allows to include custom replicas in the future.
  sql_replicas_performance = [for i in range(var.dbe.replica) : {
    connections_metric = try(regex("(?i)postgres", var.dbe.version), null) != null ? "cloudsql.googleapis.com/database/postgresql/num_backends" : "cloudsql.googleapis.com/database/network/connections"
    # The default max_connections number for most of the instances is 4k.
    # Only the very low profile DB have less connections (db‑f1‑micro -> 250, db‑g1‑small -> 1000).
    max_connections = (
      # Custom limit configured via monitoring
      var.monitoring.connections.max_connections != null ? var.monitoring.connections.max_connections :
      # Custom limit configured via flags
      try(var.flags.max_connections, null) != null ? var.flags.max_connections :
      # Shared core instance db-f1-micro
      var.dbe.tier == "db-f1-micro" ? 250 :
      # Shared core instance db-f1-mini
      var.dbe.tier == "db-g1-small" ? 2000 :
      # All the other type instances
      4000
    )
    memory_size = (
      # Custom limit configured
      var.monitoring.memory.limit_ram != null ? var.monitoring.memory.limit_ram :
      # Shared core instance db-f1-micro
      var.dbe.tier == "db-f1-micro" ? 614 :
      # Shared core instance db-f1-mini
      var.dbe.tier == "db-g1-small" ? 1740 :
      # All the other type instances
      try(regex("db\\-custom\\-(\\d+)\\-(\\d+)", var.dbe.tier)[1], 0)
    )
  }]
}

resource "google_monitoring_alert_policy" "sql_replicas_performance" {
  count        = var.dbe.replica
  project      = var.gcp_project_sys_id
  display_name = format("%s | %s | Replica %d | Performance", var.base_name, title(var.module_name), count.index)
  enabled      = true
  combiner     = "OR"
  user_labels = {
    created_by = "terraform"
  }

  conditions {
    display_name = format("%s | %s | Replica %d | %s", var.base_name, title(var.module_name), count.index, "CPU Usage")

    condition_threshold {
      filter                  = format("metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"%s:%s\"", var.gcp_project_id, google_sql_database_instance.dbe_slave[count.index].name)
      duration                = var.monitoring.cpu.duration
      comparison              = "COMPARISON_GT"
      threshold_value         = var.monitoring.cpu.threshold_value
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"

      aggregations {
        cross_series_reducer = "REDUCE_MAX"

        alignment_period   = var.monitoring.cpu.alignment_period
        per_series_aligner = "ALIGN_MAX"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | Replica %d | %s", var.base_name, title(var.module_name), count.index, "Memory Usage")

    condition_threshold {
      filter                  = format("metric.type=\"cloudsql.googleapis.com/database/memory/utilization\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"%s:%s\"", var.gcp_project_id, google_sql_database_instance.dbe_slave[count.index].name)
      duration                = var.monitoring.memory.duration
      comparison              = "COMPARISON_GT"
      threshold_value         = local.sql_replicas_performance[count.index].memory_size * 1024 * 1024 * var.monitoring.memory.threshold_value
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"

      aggregations {
        cross_series_reducer = "REDUCE_MAX"
        alignment_period     = var.monitoring.memory.alignment_period
        per_series_aligner   = "ALIGN_MEAN"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | Replica %d | %s", var.base_name, title(var.module_name), count.index, "Connections")

    condition_threshold {
      comparison      = "COMPARISON_GT"
      duration        = var.monitoring.connections.duration
      filter          = format("metric.type=\"cloudsql.googleapis.com/database/network/connections\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"%s:%s\"", var.gcp_project_id, google_sql_database_instance.dbe_slave[count.index].name)
      threshold_value = (local.sql_replicas_performance[count.index].max_connections * var.monitoring.connections.threshold_value)

      aggregations {
        alignment_period   = var.monitoring.connections.alignment_period
        per_series_aligner = "ALIGN_MAX"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  notification_channels = var.notification_channels_not_on_call
}


resource "google_monitoring_alert_policy" "sql_replicas_disk" {
  count        = var.dbe.replica
  project      = var.gcp_project_sys_id
  display_name = format("%s | %s | Replica %d | Disk", var.base_name, title(var.module_name), count.index)
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = format("%s | %s | Replica %d | %s", var.base_name, title(var.module_name), count.index, "Disk Space")

    condition_threshold {
      comparison              = "COMPARISON_GT"
      duration                = var.monitoring.disk_space.duration
      filter                  = format("metric.type=\"cloudsql.googleapis.com/database/disk/utilization\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"%s:%s\"", var.gcp_project_id, google_sql_database_instance.dbe_slave[count.index].name)
      threshold_value         = var.monitoring.disk_space.threshold_value
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"

      aggregations {
        alignment_period   = var.monitoring.disk_space.alignment_period
        per_series_aligner = "ALIGN_MAX"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | Replica %d | %s", var.base_name, title(var.module_name), count.index, "Disk Read IO")

    condition_threshold {
      comparison = "COMPARISON_GT"
      duration   = var.monitoring.disk_iops.duration
      filter     = format("metric.type=\"cloudsql.googleapis.com/database/disk/read_ops_count\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"%s:%s\"", var.gcp_project_id, google_sql_database_instance.dbe_slave[count.index].name)
      # Value is calculated using the the thresholde percent of disk size * 30 (SSD per GB IOPS)
      threshold_value         = (var.dbe.disk.size * var.monitoring.disk_iops.threshold_value) * 30
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"

      aggregations {
        alignment_period   = var.monitoring.disk_iops.alignment_period
        per_series_aligner = "ALIGN_RATE"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  conditions {
    display_name = format("%s | %s | Replica %d | %s", var.base_name, title(var.module_name), count.index, "Disk Write IO")

    condition_threshold {
      comparison = "COMPARISON_GT"
      duration   = var.monitoring.disk_iops.duration
      filter     = format("metric.type=\"cloudsql.googleapis.com/database/disk/write_ops_count\" resource.type=\"cloudsql_database\" resource.label.\"database_id\"=\"%s:%s\"", var.gcp_project_id, google_sql_database_instance.dbe_slave[count.index].name)
      # Value is calculated using the the threshold percent of disk size * 30 (SSD per GB IOPS)
      threshold_value         = (var.dbe.disk.size * var.monitoring.disk_iops.threshold_value) * 30
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"

      aggregations {
        alignment_period   = var.monitoring.disk_iops.alignment_period
        per_series_aligner = "ALIGN_RATE"
      }

      trigger {
        count   = 1
        percent = 0
      }
    }
  }

  notification_channels = var.notification_channels_not_on_call
}
