# ===================================================================
# CLOUD RUN DOMAIN MAPPINGS
# ===================================================================
# Manages custom domain mappings for Cloud Run services.
# Each entry in domain_mappings creates a google_cloud_run_domain_mapping.
#
# IMPORT EXISTING MAPPINGS:
#   terraform import 'google_cloud_run_domain_mapping.mapping["<key>"]' \
#     locations/<region>/namespaces/<project>/domainmappings/<domain>

locals {
  legacy_mappings = try(local.settings.domain_mappings, {})

  # Extract services that have 'domain' configured in their cloudrun block
  services_with_domains = {
    for k, v in try(local.settings.app.service, {}) : k => v
    if can(v.cloudrun.domain)
  }

  # Flatten to a list of mappings
  service_domain_list = flatten([
    for service_key, service_config in local.services_with_domains : [
      # Support both string and list of strings for 'domain'
      for domain in flatten([service_config.cloudrun.domain]) : {
        # Generate a unique key for the mapping (e.g., "web-app-example-com")
        key    = "${service_key}-${replace(domain, ".", "-")}"
        domain = domain
        # Determine the Cloud Run service name consistent with gcp.cloudrun.tf
        service = try(service_config.custom_name, "${local.base_name}-${try(service_config.name, service_key)}")
        region  = local.service_regions[service_key]

        # Optional overrides
        certificate_mode = try(service_config.cloudrun.domain_certificate_mode, "AUTOMATIC")
        force_override   = try(service_config.cloudrun.domain_force_override, false)
      }
    ]
  ])

  # Convert list to map for merging
  new_mappings = {
    for mapping in local.service_domain_list : mapping.key => mapping
  }

  # Merge legacy and new mappings
  domain_mappings = merge(local.legacy_mappings, local.new_mappings)
}

resource "google_cloud_run_domain_mapping" "mapping" {
  for_each = local.domain_mappings
  # Its labels are immutable: provider default labels would replace the mapping.
  provider = google.unlabelled

  name     = each.value.domain
  location = try(each.value.region, local.settings.region_name)
  project  = local.settings.project.id

  metadata {
    namespace = local.settings.project.id
  }

  spec {
    route_name       = each.value.service
    certificate_mode = try(each.value.certificate_mode, "AUTOMATIC")
    force_override   = try(each.value.force_override, false)
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
      # Provider-computed default label (goog-terraform-provisioned) drifts on
      # mappings created via gcloud; domain mappings don't support update, so
      # any label diff turns into a hard apply error. Ignore it.
      metadata[0].terraform_labels,
      # Mappings created/recreated via gcloud (e.g. by a domain-verified owner
      # account) read back without certificate_mode; managing it would force
      # a replacement that requires domain-verified credentials.
      spec[0].certificate_mode,
    ]
  }

  depends_on = [module.cloud_run_services]
}
