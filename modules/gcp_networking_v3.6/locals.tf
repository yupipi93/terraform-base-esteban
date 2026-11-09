locals {
  m_base_name        = var.base_name
  m_base_name_medium = format("%s--%s", local.m_base_name, var.module_name)

  # Only VPC_PEERING ranges can be reserved for the service networking peering.
  psa_range_keys = sort([for key, range in var.services_ip_ranges : key if range.purpose == "VPC_PEERING"])

  # Two blocks overlap when they share the network address of the shorter
  # prefix. A range without an address is allocated by Google from free space.
  psa_ranges_disjoint = alltrue([
    for range in values(var.services_ip_ranges) : alltrue([
      for other in distinct(concat([for subnet in values(var.subnets) : subnet.cidr], var.reserved_cidrs)) :
      cidrhost(format("%s/%d", range.address, min(range.prefix_length, tonumber(split("/", other)[1]))), 0)
      != cidrhost(format("%s/%d", split("/", other)[0], min(range.prefix_length, tonumber(split("/", other)[1]))), 0)
    ]) if range.address != null
  ])
}
