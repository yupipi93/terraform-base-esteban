# Firewall Rules
# Only with the shared VPC. The rules follow settings.network.services_cidr
# instead of a hardcoded subnet that the project may not use.
# try() is there because Terraform still type-checks a count = 0 resource.
# The fallback values are never applied.

moved {
  from = google_compute_firewall.allow_iap_ssh
  to   = google_compute_firewall.allow_iap_ssh[0]
}

moved {
  from = google_compute_firewall.allow_internal_vpc
  to   = google_compute_firewall.allow_internal_vpc[0]
}

moved {
  from = google_compute_firewall.allow_http
  to   = google_compute_firewall.allow_http[0]
}

moved {
  from = google_compute_firewall.allow_https
  to   = google_compute_firewall.allow_https[0]
}

# IAP SSH Access Rule
resource "google_compute_firewall" "allow_iap_ssh" {
  count = local.network_enabled ? 1 : 0

  name    = format("%s-allow-iap-ssh", local.base_name)
  network = try(module.network[0].network_name, "unused")
  project = local.settings.project.id

  description = "Allow SSH access from Google Cloud IAP"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = []

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Internal VPC Communication Rule
resource "google_compute_firewall" "allow_internal_vpc" {
  count = local.network_enabled ? 1 : 0

  name    = format("%s-allow-internal-vpc", local.base_name)
  network = try(module.network[0].network_name, "unused")
  project = local.settings.project.id

  description = "Allow internal communication within VPC subnets"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = try(distinct(concat(
    [local.settings.network.services_cidr],
    try(local.settings.network.extra_internal_cidrs, []),
  )), ["0.0.0.0/32"])
  target_tags = []

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# HTTP Ingress Rule
resource "google_compute_firewall" "allow_http" {
  count = local.network_enabled ? 1 : 0

  name    = format("%s-vpc-allow-http", local.base_name)
  network = try(module.network[0].network_name, "unused")
  project = local.settings.project.id

  description = "Allow HTTP traffic from internet"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# HTTPS Ingress Rule
resource "google_compute_firewall" "allow_https" {
  count = local.network_enabled ? 1 : 0

  name    = format("%s-vpc-allow-https", local.base_name)
  network = try(module.network[0].network_name, "unused")
  project = local.settings.project.id

  description = "Allow HTTPS traffic from internet"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["httpsserver"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
