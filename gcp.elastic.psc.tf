# ===================================================================
# PRIVATE SERVICE CONNECT CONFIGURATION
# ===================================================================
# This file configures Private Service Connect (PSC) to enable Cloud Run services
# to securely connect to an Elastic Cloud deployment without exposing traffic
# to the public internet. The setup creates:
#
# 1. A Private Service Connect endpoint that routes to the provider's service attachment
# 2. Optionally, a private DNS zone and records resolving the provider domain to the private IP
#
# Everything comes from settings.elastic_psc. Without that key nothing is created.
# The endpoint takes its IP from the services subnet, so the key also needs
# network.services_cidr: without it the plan stops at the address precondition.
# Cloud Run services can then connect to Elastic using the private endpoint address

locals {
  elastic_psc_settings = try(local.settings.elastic_psc, null)

  enable_elastic_psc = local.elastic_psc_settings != null

  elastic_psc = {
    service_attachment = try(local.elastic_psc_settings.service_attachment, "")
    name               = try(local.elastic_psc_settings.name, "elastic-psc")
    ip_address         = try(local.elastic_psc_settings.ip_address, null)
    dns_domain         = trimsuffix(try(local.elastic_psc_settings.dns_domain, ""), ".")
  }

  enable_elastic_psc_dns = local.enable_elastic_psc && local.elastic_psc.dns_domain != ""
}

# Create a Private Service Connect endpoint
resource "google_compute_address" "elastic_psc_address" {
  count = local.enable_elastic_psc ? 1 : 0

  name         = "${local.base_name_medium}-${local.elastic_psc.name}-address"
  region       = local.settings.region_name
  subnetwork   = try(module.network[0].subnetworks["services"].self_link, null)
  address      = local.elastic_psc.ip_address
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  description  = "Private Service Connect IP address for Elastic Cloud"

  labels = local.common_labels

  lifecycle {
    precondition {
      condition     = local.network_enabled
      error_message = "elastic_psc needs the shared VPC: set network.services_cidr, or remove elastic_psc. The endpoint IP comes from the services subnet."
    }
  }
}

resource "google_compute_forwarding_rule" "elastic_psc_endpoint" {
  count = local.enable_elastic_psc ? 1 : 0

  name                  = "${local.base_name_medium}-${local.elastic_psc.name}-endpoint"
  region                = local.settings.region_name
  network               = try(module.network[0].network_id, null)
  ip_address            = google_compute_address.elastic_psc_address[0].id
  target                = local.elastic_psc.service_attachment
  load_balancing_scheme = ""
  description           = "Private Service Connect endpoint to Elastic Cloud deployment"

  labels = local.common_labels

  lifecycle {
    precondition {
      condition     = can(regex("^projects/[^/]+/regions/${local.settings.region_name}/serviceAttachments/[^/]+$", local.elastic_psc.service_attachment))
      error_message = "elastic_psc.service_attachment must be projects/<project>/regions/<region>/serviceAttachments/<name>, in region_name (the region of the services subnet)."
    }
  }
}

# Create a private DNS zone for the Elastic Cloud domain
resource "google_dns_managed_zone" "elastic_private_zone" {
  count = local.enable_elastic_psc_dns ? 1 : 0

  name        = "${local.base_name_medium}-elastic-dns-zone"
  dns_name    = "${local.elastic_psc.dns_domain}."
  description = "Private DNS zone for Elastic Cloud domain"

  labels = local.common_labels

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = try(module.network[0].network_id, null)
    }
  }
}

# Create DNS record pointing to PSC endpoint IP address
resource "google_dns_record_set" "elastic_dns_record" {
  count = local.enable_elastic_psc_dns ? 1 : 0

  name         = "${local.elastic_psc.dns_domain}."
  managed_zone = google_dns_managed_zone.elastic_private_zone[0].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.elastic_psc_address[0].address]
}

# Create DNS record for wildcard subdomains
resource "google_dns_record_set" "elastic_wildcard_dns_record" {
  count = local.enable_elastic_psc_dns ? 1 : 0

  name         = "*.${local.elastic_psc.dns_domain}."
  managed_zone = google_dns_managed_zone.elastic_private_zone[0].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.elastic_psc_address[0].address]
}
