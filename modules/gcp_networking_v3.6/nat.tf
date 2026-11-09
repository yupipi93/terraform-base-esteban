resource "google_compute_address" "nat_ip" {
  for_each = merge(
    flatten([
      for key, value in var.nats : [for i in range(value.number_of_addresses) : { format("%s/%02d", key, i) = { name = (value.old_naming_method == true ? i + 1 : value.name_v3 ? format("%s/%02d", key, i) : i == 0 ? key : format("%s/%02d", key, i)), region = value.region } }] if value.number_of_addresses > 0
    ])...
  )

  project      = var.gcp_project_id
  region       = each.value.region
  name         = format("%s--nat-ip--%s", local.m_base_name, replace(each.value.name, "/", "-"))
  network_tier = var.network_tier
}

resource "google_compute_router" "router" {
  for_each = var.nats

  project = var.gcp_project_id
  name    = format("%s--%srouter", local.m_base_name, each.value.old_naming_method == true ? "" : format("%s--", each.key))
  region  = each.value.region
  network = google_compute_network.net.self_link
}

resource "google_compute_router_nat" "nat" {
  for_each = var.nats

  project                             = var.gcp_project_id
  name                                = format("%s--%snat", local.m_base_name, each.value.old_naming_method == true ? "" : format("%s--", each.key))
  router                              = google_compute_router.router[each.key].name
  region                              = each.value.region
  min_ports_per_vm                    = each.value.min_vm_ports
  max_ports_per_vm                    = each.value.max_vm_ports
  enable_dynamic_port_allocation      = each.value.enable_dynamic_port_allocation
  enable_endpoint_independent_mapping = each.value.enable_endpoint_independent_mapping

  nat_ip_allocate_option = each.value.number_of_addresses > 0 ? "MANUAL_ONLY" : "AUTO_ONLY"
  nat_ips                = [for key, value in google_compute_address.nat_ip : value.self_link if can(regex(format("^%s/", each.key), key))]

  log_config {
    enable = false
    filter = "ALL"
  }

  source_subnetwork_ip_ranges_to_nat = length(each.value.subnets) > 0 ? "LIST_OF_SUBNETWORKS" : "ALL_SUBNETWORKS_ALL_IP_RANGES"
  dynamic "subnetwork" {
    for_each = toset(each.value.subnets)

    content {
      name                     = google_compute_subnetwork.subnet[subnetwork.key].self_link
      secondary_ip_range_names = []
      source_ip_ranges_to_nat  = ["ALL_IP_RANGES"]
    }
  }

  depends_on = [
    google_compute_router.router,
    #google_compute_address.nat_ip
  ]
}
