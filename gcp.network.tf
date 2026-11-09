# One shared VPC for the whole project. It is created only when the workspace
# sets network.services_cidr. A project that does not need private connectivity
# plans with no network, no NAT and no firewall. This is not a VPC per service.
locals {
  network_enabled = can(local.settings.network.services_cidr)

  # Cloud SQL without a public IP and Memorystore in PRIVATE_SERVICE_ACCESS mode
  # take their address from a Private Service Access range of the shared VPC.
  private_service_access_needed = anytrue(concat(
    [for db in try(values(local.settings.database), []) : !try(db.sql.ipv4_enabled, false)],
    [for redis in try(values(local.settings.redis), []) : try(redis.connect_mode, "") == "PRIVATE_SERVICE_ACCESS"],
  ))

  # network.services_ip_ranges as written. Left out, a workspace that needs
  # Private Service Access gets one /16 that Google allocates from the free
  # private space of the VPC, so it cannot overlap services_cidr. An explicit
  # empty map creates no range and no connection.
  services_ip_ranges = try(
    coalesce(local.settings.network.services_ip_ranges),
    local.private_service_access_needed ? { private = { prefix_length = 16 } } : {},
  )
}

# Addresses before this count was introduced. Harmless on a fresh state.
moved {
  from = module.network
  to   = module.network[0]
}

module "network" {
  count  = local.network_enabled ? 1 : 0
  source = "./modules/gcp_networking_v3.6"

  # Base name used in module (Mandatory)
  base_name = format("%s-vpc", local.base_name)
  # Project ID where to create the resources (Mandatory)
  gcp_project_id = local.settings.project.id
  # Project ID where to create the monitoring resources (Mandatory only when NAT is created)
  gcp_project_sys_id = local.settings.project_sys.id
  # Network tier used for the created NAT IP addresses (Optional. Only used when NAT is created. Default: PREMIUM)
  network_tier = try(local.settings.network.network_tier, "PREMIUM")
  # Create an internal connector to be used in SaS resources (Optional. Default: false)
  internal_connection = try(local.settings.network.internal_connection, true)

  # Create one or more subnetworks (Optional, but for sure you will need at least one)
  subnets = {
    services = {
      # Cidr used in the new subnetwork (Mandatory)
      cidr = try(local.settings.network.services_cidr, null)
      # Region where will be created (Mandatory)
      region = local.settings.region_name
      # Subnetwork purpose (Optional. Used for internal LB for example. Default: null)
      purpose = null
      # Subnetwork role (Optional. Used for internal LB for example. Default: null)
      role = null
      # Enable the private access to google resources. (Optional. Must be false if purpose = INTERNAL_HTTPS_LOAD_BALANCER. Default: true)
      private_google_access = try(local.settings.network.private_google_access, true)
      # The service range name will use single dashes instead double dashes
      single_dash = false
    }
  }

  # Create one or more serverless connectors (Optional)
  #serverless_vpc_connectors = {
  #  services = {
  #    # CIDR that will be used in the connector (Optional. Default: 10.8.0.0/28)
  #    cidr = "10.8.0.0/28"
  #    # Region where to create the connector (Mandatory)
  #    region = local.settings.region_name
  #    # Machine type used in the connector (Optional. Default: e2-micro)
  #    machine_type = "e2-micro"
  #    # Subnet where to link the connector. If provided, the CIDR will be ignored in favor of the subnetwork cidr.
  #    # The key used in subnets argument must be used ("services" in the above example). This subnet mask MUST BE /28 (Google side requirement)
  #    # (Optional. Default: null)
  #    subnet = null
  #    # Instances count (Optional. Default: max_instances=3, min_instances=2)
  #    max_instances = 3
  #    min_instances = 2
  #  }
  #}

  # Private Service Access ranges (network.services_ip_ranges, see the locals
  # above). Every VPC_PEERING entry becomes a reserved global address, and all
  # of them go into one servicenetworking connection.
  services_ip_ranges = local.services_ip_ranges
  # The module stops the plan (preconditions on its network) when a private
  # data store has no range, or an explicit range overlaps services_cidr or
  # one of these CIDRs.
  private_service_access_required = local.private_service_access_needed
  reserved_cidrs                  = try(local.settings.network.extra_internal_cidrs, [])

  # IAC Repository to help the notifications to be more polite with the person who have to fix it.
  repo_iac = local.settings.iac.repo

  nats = try(local.settings.network.nats, {})

  # Same channel every other alert in this repo uses (gcp.security.tf).
  monitoring = {
    notification_channels = [google_monitoring_notification_channel.security_alerts.id]
  }
}
