# Constant for module
variable "module_name" {
  type    = string
  default = "networking"
}

variable "base_name" {
  type        = string
  description = "Project for the resource"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP Project source"
}

variable "gcp_project_sys_id" {
  type        = string
  description = "GCP Project ID SYS (Required for monitoring the NAT if used)"
  default     = ""
}

variable "network_tier" {
  type        = string
  description = "Network Tier"
  default     = "PREMIUM"
}

variable "internal_connection" {
  type        = bool
  description = "Create an internal VPC network to allow SaS services to be used in that network"
  default     = false
}

variable "subnets" {
  type = map(object({
    cidr                  = string
    region                = string
    purpose               = optional(string)
    role                  = optional(string)
    private_google_access = optional(bool, true)
    single_dash           = optional(bool, false)
  }))
  description = "Subnets that will be created into the network"
  default     = {}
}

variable "nats" {
  type = map(object({
    region                              = string
    number_of_addresses                 = optional(number, 0)  # if not provided, auto mode will be used
    name_v3                             = optional(bool, true) # If you named the NAT IP with version 3.1, 3.2, or 3.3, set this variable to false
    old_naming_method                   = optional(bool, false)
    min_vm_ports                        = optional(number, 1024)
    max_vm_ports                        = optional(number)
    enable_dynamic_port_allocation      = optional(bool, false)
    enable_endpoint_independent_mapping = optional(bool, false)
    subnets                             = optional(list(string), []) # List of the subnetworks created in subnets. If not provided, all the subnets in the region.
  }))
  description = "Nats that will be created into the project"
  default     = {}
}

variable "serverless_vpc_connectors" {
  type = map(object({
    cidr          = optional(string, "10.8.0.0/28")
    region        = string
    machine_type  = optional(string, "e2-micro")
    subnet        = optional(string)
    max_instances = optional(number, 3)
    min_instances = optional(number, 2)
  }))

  description = "serverless_vpc_connector configuration"
  default     = {}
}

variable "services_ip_ranges" {
  type = map(object({
    address       = optional(string, null)
    description   = optional(string, null)
    prefix_length = optional(number, 16)
    address_type  = optional(string, "INTERNAL")
    purpose       = optional(string, "VPC_PEERING")
    single_dash   = optional(bool, false)
  }))

  description = "google_compute_global_address configuration (Services IP Ranges). Every VPC_PEERING entry is reserved for one Private Service Access connection."
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for range in values(var.services_ip_ranges) :
      range.purpose != "VPC_PEERING" || (range.address_type == "INTERNAL" && range.prefix_length >= 8 && range.prefix_length <= 24)
    ])
    error_message = "A VPC_PEERING services range must be INTERNAL with a prefix_length from 8 to 24 (Cloud SQL needs at least a /24)."
  }

  validation {
    condition = alltrue([
      for range in values(var.services_ip_ranges) :
      range.address == null || try(cidrhost(format("%s/%d", range.address, range.prefix_length), 0) == range.address, false)
    ])
    error_message = "A services range address must be the first IPv4 address of its block (address/prefix_length), for example 10.9.0.0 with 16."
  }
}

variable "private_service_access_required" {
  type        = bool
  description = "A private Cloud SQL or Memorystore instance uses this network: the plan stops when services_ip_ranges has no VPC_PEERING entry"
  default     = false
  nullable    = false
}

variable "reserved_cidrs" {
  type        = list(string)
  description = "CIDRs outside this module's subnets that an explicit services_ip_ranges address must not overlap"
  default     = []
  nullable    = false
}

variable "repo_iac" {
  type        = string
  description = "URL or name of IAC repository"
}

variable "monitoring" {
  type = object({
    dropped_sent_endpoint_independence_conflict = optional(object({
      duration         = optional(string, "1800s")
      threshold_value  = optional(number, 10)
      alignment_period = optional(string, "60s")
    }), {}),
    dropped_sent_out_of_resources = optional(object({
      duration         = optional(string, "1800s")
      threshold_value  = optional(number, 10)
      alignment_period = optional(string, "60s")
    }), {}),
    nat_allocation_failed = optional(object({
      duration         = optional(string, "1800s")
      threshold_value  = optional(number, 1) # Is a True/False measurement.
      alignment_period = optional(string, "60s")
    }), {}),

    notification_channels = optional(list(string), [])
  })
  default = {}
}
