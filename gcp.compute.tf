# ===================================================================
# COMPUTE INSTANCES (VMs)
# ===================================================================
# Manages GCE virtual machine instances defined in settings YAML.
# Each entry in compute_instances creates a google_compute_instance.
#
# IMPORT EXISTING VMs:
#   terraform import 'google_compute_instance.vm["<key>"]' \
#     projects/<project>/zones/<zone>/instances/<name>

locals {
  compute_instances = try(local.settings.compute_instances, {})
}

# Data source for the default network (used by VMs not on the managed VPC)
data "google_compute_network" "default" {
  count   = length(local.compute_instances) > 0 ? 1 : 0
  name    = "default"
  project = local.settings.project.id
}

resource "google_compute_instance" "vm" {
  for_each = local.compute_instances

  name                = each.value.name
  machine_type        = each.value.machine_type
  zone                = each.value.zone
  project             = local.settings.project.id
  description         = try(each.value.description, null)
  deletion_protection = try(each.value.deletion_protection, local.workspace == "pro")
  tags                = try(each.value.tags, [])
  can_ip_forward      = try(each.value.can_ip_forward, false)
  enable_display      = try(each.value.enable_display, false)
  labels              = try(each.value.labels, {})

  # --- Boot disk ---
  boot_disk {
    auto_delete = try(each.value.boot_disk.auto_delete, true)

    initialize_params {
      image = each.value.boot_disk.image
      size  = try(each.value.boot_disk.size_gb, 10)
      type  = try(each.value.boot_disk.type, "pd-standard")
    }
  }

  # --- Network interface ---
  network_interface {
    network    = try(each.value.network, "default") == "default" ? data.google_compute_network.default[0].self_link : try(module.network[0].network_self_link, null)
    subnetwork = try(each.value.subnetwork, null) == "default" ? "projects/${local.settings.project.id}/regions/${each.value.region}/subnetworks/default" : null
  }

  # --- Service account ---
  service_account {
    email  = try(each.value.service_account_email, null)
    scopes = try(each.value.service_account_scopes, ["https://www.googleapis.com/auth/cloud-platform"])
  }

  # --- Scheduling ---
  scheduling {
    preemptible         = try(each.value.scheduling.preemptible, false)
    automatic_restart   = try(each.value.scheduling.automatic_restart, true)
    on_host_maintenance = try(each.value.scheduling.on_host_maintenance, "MIGRATE")
    provisioning_model  = try(each.value.scheduling.preemptible, false) ? "SPOT" : "STANDARD"
  }

  # --- Shielded instance ---
  shielded_instance_config {
    enable_vtpm                 = try(each.value.shielded_instance.enable_vtpm, true)
    enable_integrity_monitoring = try(each.value.shielded_instance.enable_integrity_monitoring, true)
    enable_secure_boot          = try(each.value.shielded_instance.enable_secure_boot, false)
  }

  # --- Confidential instance (disabled by default) ---
  confidential_instance_config {
    enable_confidential_compute = try(each.value.confidential_compute, false)
  }

  # --- Reservation affinity ---
  reservation_affinity {
    type = try(each.value.reservation_affinity, "ANY_RESERVATION")
  }

  # Ignore attributes that cause spurious diffs or forced replacements on imported VMs
  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"],
      key_revocation_action_type,
    ]
  }
}
