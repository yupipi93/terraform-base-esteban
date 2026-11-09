# ===================================================================
# CLOUD NAT FOR VMs ON THE `default` NETWORK
# ===================================================================
# The networking module only manages the project VPC (gcp.network.tf, `network.nats`).
# VMs in `compute_instances` live on the auto-created `default` network, so
# their NAT is declared here, one router + one NAT per `compute_nats` entry.
#
# A VM with NO external IP has this NAT as its only route to the internet
# (apt, Docker pulls). Names are immutable: renaming means replace, which cuts
# the VM off, so keep the existing name when adopting a NAT made by hand.
#
# IMPORT EXISTING NATs:
#   terraform import 'google_compute_router.nat["<key>"]' \
#     projects/<project>/regions/<region>/routers/<router_name>
#   terraform import 'google_compute_router_nat.nat["<key>"]' \
#     <project>/<region>/<router_name>/<nat_name>
# ===================================================================

locals {
  compute_nats = try(local.settings.compute_nats, {})
}

resource "google_compute_router" "nat" {
  for_each = local.compute_nats

  name    = each.value.router_name
  project = local.settings.project.id
  region  = each.value.region
  network = try(each.value.network, "default")
}

resource "google_compute_router_nat" "nat" {
  for_each = local.compute_nats

  name    = each.value.nat_name
  project = local.settings.project.id
  region  = each.value.region
  router  = google_compute_router.nat[each.key].name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  endpoint_types                     = ["ENDPOINT_TYPE_VM"]

  # `auto_network_tier` is deliberately NOT declared. Live it is STANDARD, but the
  # provider reads it back as null after import, so declaring it would write to the
  # NAT for nothing. Absent leaves the live value alone.

  log_config {
    enable = false
    filter = "ALL"
  }
}
