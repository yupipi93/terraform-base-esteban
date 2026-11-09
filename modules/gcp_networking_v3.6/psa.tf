# Private Service Access: the ranges Google-managed services (Cloud SQL private
# IP, Memorystore PRIVATE_SERVICE_ACCESS) take their addresses from, and the one
# peering to the service producer network that carries them.

resource "google_compute_global_address" "net_private" {
  for_each = var.services_ip_ranges

  project       = var.gcp_project_id
  name          = format("%s%s%s", local.m_base_name, each.value.single_dash ? "-" : "--", each.key)
  description   = each.value.description
  network       = google_compute_network.net.id
  address       = each.value.address
  prefix_length = each.value.prefix_length
  address_type  = each.value.address_type
  purpose       = each.value.purpose

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", format("%s%s%s", local.m_base_name, each.value.single_dash ? "-" : "--", each.key)))
      error_message = "services_ip_ranges.${each.key}: the range name (base name, dashes, key) must be 1 to 63 lowercase letters, digits or hyphens, starting with a letter."
    }
  }
}

resource "google_service_networking_connection" "net_private_connection" {
  count = length(local.psa_range_keys) > 0 ? 1 : 0

  network                 = google_compute_network.net.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [for key in local.psa_range_keys : google_compute_global_address.net_private[key].name]

  # Deleting the connection fails while a producer still uses it (Cloud SQL keeps
  # the peering for days after the instance is gone). ABANDON drops it from state
  # only, and the peering goes away with the network.
  deletion_policy = "ABANDON"
  # A connection that already exists (made by hand, or by a failed earlier apply)
  # is patched with these ranges instead of failing the create.
  update_on_creation_fail = true

  depends_on = [google_project_service.servicenetworking]
}
