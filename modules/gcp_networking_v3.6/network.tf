resource "google_compute_network" "net" {
  project                 = var.gcp_project_id
  name                    = local.m_base_name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.servicenetworking]

  # Preconditions, not check blocks: a check only warns, and both cases must
  # stop the plan. The network is planned whenever the module is, so the rules
  # run even when services_ip_ranges is empty.
  lifecycle {
    precondition {
      condition     = !var.private_service_access_required || length(local.psa_range_keys) > 0
      error_message = "A private data store (Cloud SQL without a public IP, or Memorystore in PRIVATE_SERVICE_ACCESS mode) needs a VPC_PEERING entry in services_ip_ranges."
    }
    precondition {
      condition     = local.psa_ranges_disjoint
      error_message = "A services_ip_ranges entry overlaps a subnet or reserved_cidrs. Pick a block outside them."
    }
  }
}

resource "google_compute_subnetwork" "subnet" {
  for_each                 = var.subnets
  project                  = var.gcp_project_id
  name                     = format("%s%s%s", local.m_base_name, each.value.single_dash ? "-" : "--", each.key)
  private_ip_google_access = each.value.private_google_access
  network                  = google_compute_network.net.self_link
  ip_cidr_range            = each.value.cidr
  region                   = each.value.region
  purpose                  = each.value.purpose
  role                     = each.value.role
}


