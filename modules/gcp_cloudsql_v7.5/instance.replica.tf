resource "google_sql_database_instance" "dbe_slave" {
  // Add random suffix to dbname to allow recreation
  project              = var.gcp_project_id
  count                = var.dbe.replica
  name                 = format("%s--%s--slave--%s", local.m_base_name_medium, random_string.random_suffix_sql_name.result, count.index)
  database_version     = var.dbe.version
  region               = var.region_name
  deletion_protection  = var.dbe.deletion_protection
  master_instance_name = google_sql_database_instance.dbe.name

  replica_configuration {
    failover_target = false
  }

  settings {
    tier              = var.dbe.tier
    disk_autoresize   = true
    disk_size         = var.dbe.disk.size
    disk_type         = var.dbe.disk.type
    availability_type = var.dbe.availability
    ip_configuration {
      ipv4_enabled    = var.dbe.ipv4_enabled
      private_network = var.net_id
      ssl_mode        = var.dbe.ssl_mode

      dynamic "authorized_networks" {
        for_each = { for item in var.dbe.allowed_networks : format("%s_%s", item.name, item.value) => item }
        iterator = address

        content {
          name  = address.value.name
          value = address.value.value
        }
      }
    }
    backup_configuration {
      enabled    = false
      start_time = "05:00"
    }
    dynamic "database_flags" {
      for_each = try(var.flags, {})
      iterator = flag

      content {
        name  = flag.key
        value = flag.value
      }
    }
  }
}
