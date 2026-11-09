## Convert v2.6-202302141211 and below versions to the new version

# The module is fully compatible with the v2.6-202302141211 version and similar (older versions can have incompatibilities).
# To convert the resource you have to add the following:

/*
 module "network" {
  ...
  services_ip_ranges = {
    private = {}
  }
  ...
}
*/

# and execute the following comand:
#  terraform state mv 'module.network.google_compute_global_address.net_private[0]' 'module.network.google_compute_global_address.net_private["private"]'


module "network" {
  source = "./modules/gcp_networking_v3.6"

  # Base name used in module (Mandatory)
  base_name = local.base_name
  # Project ID where to create the resources (Mandatory)
  gcp_project_id = local.settings.project.id
  # Project ID where to create the monitoring resources (Mandatory only when NAT is created)
  gcp_project_sys_id = local.settings.project_sys.id
  # Network tier used for the created NAT IP addresses (Optional. Only used when NAT is created. Default: PREMIUM)
  network_tier = local.settings.network.network_tier
  # Create an internal connector to be used in SaS resources (Optional. Default: false)
  internal_connection = local.settings.network.internal_connection

  # Create one or more subnetworks (Optional, but for sure you will need at least one)
  subnets = {
    services = {
      # Cidr used in the new subnetwork (Mandatory)
      cidr = local.settings.network.services_cidr
      # Region where will be created (Mandatory)
      region = local.settings.region_name
      # Subnetwork purpose (Optional. Used for internal LB for example. Default: null)
      purpose = null
      # Subnetwork role (Optiona. Used for internal LB for example. Default: null)
      role = null
      # Enable the private access to google resources. (Optional. Must be false if purpose = INTERNAL_HTTPS_LOAD_BALANCER. Default: true)
      private_google_access = local.settings.network.private_google_access
      # The service range name will use single dashes instead double dashes
      single_dash = false
    }
  }

  # Create one or more nats (Optional)
  nats = {
    services = {
      # Region where the nat will be created. It must match the subnet/s region. (Mandatory)
      region = local.settings.region_name
      # Number of IP addresses to create "manualy". If not provided, the AUTO MODE will be used. (Optional. Default: 0)
      number_of_addresses = local.settings.network.nat_addresses

      # Alternative naming methods
      name_v3           = true
      old_naming_method = false

      # Min number of ports reserverd for every instance (Optional. Default: 1024)
      min_vm_ports = local.settings.network.nat_min_vm_ports
      # Max number of ports reserver for every instance (Optional. If min and max are provided, the reserved ports number will be managed automatically between both. Default: nul.)
      max_vm_ports = local.settings.network.nat_max_vm_ports
      # Enable Dynamic port allocation (required to use min_vm_ports and max_vm_ports but not compatible with enable_endpoint_independent_mapping)
      enable_dynamic_port_allocation = optional(bool, false)
      # Enable enable_endpoint_independent_mapping. enable_dynamic_port_allocation must be disabled when this is enabled.
      enable_endpoint_independent_mapping = optional(bool, false)

      # A list of subnets where to link the NAT. The key used in subnets argument must be used ("services" in the above example).
      # If not provided, the NAT will be used in all the subnetworks in that region. (Optional. Default: [])
      subnets = [
        "services"
      ]
    }
  }

  # Create one or more serverless connectors (Optional)
  serverless_vpc_connectors = {
    services = {
      # CIDR that will be used in the connector (Optional. Default: 10.8.0.0/28)
      cidr = "10.8.0.0/28"
      # Region where to create the connector (Mandatory)
      region = local.settings.region_name
      # Machine type used in the connector (Optional. Default: e2-micro)
      machine_type = "e2-micro"
      # Subnet where to link the connector. If provided, the CIDR will be ignored in favor of the subnetwork cidr.
      # The key used in subnets argument must be used ("services" in the above example). This subnet mask MUST BE /28 (Google side requirement)
      # (Optional. Default: null)
      subnet = null
      # Instances count (Optional. Default: max_instances=3, min_instances=2)
      max_instances = 3
      min_instances = 2
    }
  }

  services_ip_ranges = {
    private = {
      # All the below values are optional
      # IP of the new created services address
      address = null
      # Just a description for the address
      description = null
      # The prefix length for the cidr (address/prefix_length)
      prefix_length = 16
      # Address tipe
      address_type = "INTERNAL"
      # Purpose
      purpose = "VPC_PEERING"
      # The service range name will use single dashes instead double dashes
      single_dash = false
    }
  }

  # Optional values
  # min_vm_ports           = local.settings.net.min_vm_ports
  monitoring = {
    # Configuration for the Dropped Sent Independence Conflict (All Optional. Any of them can be provided without cause an error. Defaults specified on every entry.)
    dropped_sent_endpoint_independence_conflict = {
      duration         = "1800s"
      threshold_value  = 10
      alignment_period = "60s"
    },
    # Configuration for the Dropped Out of Resources (All Optional. Any of them can be provided without cause an error. Defaults specified on every entry.)
    dropped_sent_out_of_resources = {
      duration         = "1800s"
      threshold_value  = 10
      alignment_period = "60s"
    },
    # Configuration for the NAT allocations errors (All Optional. Any of them can be provided without cause an error. Defaults specified on every entry.)
    nat_allocation_failed = {
      duration         = "1800s"
      threshold_value  = 1
      alignment_period = "60s"
    }

    # Channels to be used to notify any error in the NAT policy
    notification_channels = []
  }
  # IAC Repository to help the notifications to be more polite with the person who have to fix it.
  repo_iac = "your IAC repo URL"
}
