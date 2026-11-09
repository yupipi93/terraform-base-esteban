resource "google_project_service" "serverless_vpc_api" {
  project            = var.gcp_project_id
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false

  # Enable it only if the connectors will be used
  count = length(var.serverless_vpc_connectors) > 0 ? 1 : 0
}


resource "google_vpc_access_connector" "serverless_vpc_connector" {
  # For now the machine_type only exists in beta provider
  project = var.gcp_project_id

  for_each      = var.serverless_vpc_connectors
  name          = format("%s-%s", substr(format("%s-%s", local.m_base_name, each.key), 0, 20), substr(md5(each.key), 0, 4))
  region        = each.value.region
  ip_cidr_range = each.value.subnet == null ? each.value.cidr : null
  network       = each.value.subnet == null ? google_compute_network.net.name : null
  machine_type  = each.value.machine_type

  dynamic "subnet" {
    for_each = each.value.subnet != null ? { "dummy" = each.value.subnet } : {}

    content {
      name       = google_compute_subnetwork.subnet[subnet.value].name
      project_id = var.gcp_project_id
    }
  }

  max_instances = each.value.max_instances
  min_instances = each.value.min_instances


  depends_on = [google_project_service.serverless_vpc_api]
}
