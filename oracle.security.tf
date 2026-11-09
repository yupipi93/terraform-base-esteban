locals {
  oracle_nsgs = try(local.settings.oracle.nsgs, {})

  # Flattened rules for iterating over oci_core_network_security_group_security_rule
  nsg_rules = flatten([
    for nsg_key, nsg_val in local.oracle_nsgs : [
      for idx, rule in try(nsg_val.rules, []) : [
        for port_idx, port in try(rule.ports, [null]) : merge(rule, {
          nsg_key  = nsg_key
          rule_key = port != null ? "${nsg_key}-rule-${idx}-port-${port}" : "${nsg_key}-rule-${idx}"
          tcp_options = port != null && try(rule.protocol, "") == "6" ? {
            destination_port_range = { min = port, max = port }
          } : try(rule.tcp_options, null)
          udp_options = port != null && try(rule.protocol, "") == "17" ? {
            destination_port_range = { min = port, max = port }
          } : try(rule.udp_options, null)
        })
      ]
    ]
  ])
  nsg_rules_map = { for r in local.nsg_rules : r.rule_key => r }
}

resource "oci_core_network_security_group" "main" {
  for_each = local.oracle_nsgs

  compartment_id = local.oracle_compartment_id
  vcn_id         = try(each.value.vcn_id, oci_core_vcn.main[each.value.network_key].id)

  display_name = each.key
}

resource "oci_core_network_security_group_security_rule" "main" {
  for_each = local.nsg_rules_map

  network_security_group_id = oci_core_network_security_group.main[each.value.nsg_key].id
  direction                 = each.value.direction
  protocol                  = each.value.protocol

  description      = try(each.value.description, null)
  destination      = try(each.value.destination, null)
  destination_type = try(each.value.destination_type, null)
  source           = try(each.value.source, null)
  source_type      = try(each.value.source_type, null)
  stateless        = try(each.value.stateless, false)

  dynamic "tcp_options" {
    for_each = try(each.value.tcp_options, null) != null ? [each.value.tcp_options] : []
    content {
      dynamic "destination_port_range" {
        for_each = try(tcp_options.value.destination_port_range, null) != null ? [tcp_options.value.destination_port_range] : []
        content {
          max = destination_port_range.value.max
          min = destination_port_range.value.min
        }
      }
      dynamic "source_port_range" {
        for_each = try(tcp_options.value.source_port_range, null) != null ? [tcp_options.value.source_port_range] : []
        content {
          max = source_port_range.value.max
          min = source_port_range.value.min
        }
      }
    }
  }

  dynamic "udp_options" {
    for_each = try(each.value.udp_options, null) != null ? [each.value.udp_options] : []
    content {
      dynamic "destination_port_range" {
        for_each = try(udp_options.value.destination_port_range, null) != null ? [udp_options.value.destination_port_range] : []
        content {
          max = destination_port_range.value.max
          min = destination_port_range.value.min
        }
      }
      dynamic "source_port_range" {
        for_each = try(udp_options.value.source_port_range, null) != null ? [udp_options.value.source_port_range] : []
        content {
          max = source_port_range.value.max
          min = source_port_range.value.min
        }
      }
    }
  }

  dynamic "icmp_options" {
    for_each = try(each.value.icmp_options, null) != null ? [each.value.icmp_options] : []
    content {
      type = try(icmp_options.value.type, null)
      code = try(icmp_options.value.code, null)
    }
  }
}

# ─── Default security list per VCN ──────────────────────────────────────────
# Managed only when settings define oracle.networks.<key>.default_security_list.
# Rationale: OCI security lists are ADDITIVE to NSGs: the Oracle-created default
# list allowed SSH from 0.0.0.0/0, silently bypassing ssh-whitelist-nsg. Managing
# it here makes NSGs the single source of ingress truth.
locals {
  oracle_default_security_lists = {
    for net_key, net in try(local.settings.oracle.networks, {}) :
    net_key => net.default_security_list
    if try(net.default_security_list, null) != null
  }
}

resource "oci_core_default_security_list" "main" {
  for_each = local.oracle_default_security_lists

  manage_default_resource_id = oci_core_vcn.main[each.key].default_security_list_id

  dynamic "ingress_security_rules" {
    for_each = try(each.value.ingress, [])
    content {
      protocol    = ingress_security_rules.value.protocol
      source      = ingress_security_rules.value.source
      source_type = try(ingress_security_rules.value.source_type, "CIDR_BLOCK")
      description = try(ingress_security_rules.value.description, null)
      stateless   = try(ingress_security_rules.value.stateless, false)

      dynamic "icmp_options" {
        for_each = try(ingress_security_rules.value.icmp_type, null) != null ? [1] : []
        content {
          type = ingress_security_rules.value.icmp_type
          code = try(ingress_security_rules.value.icmp_code, -1)
        }
      }
      dynamic "tcp_options" {
        for_each = try(ingress_security_rules.value.port, null) != null && ingress_security_rules.value.protocol == "6" ? [1] : []
        content {
          min = ingress_security_rules.value.port
          max = ingress_security_rules.value.port
        }
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = try(each.value.egress, [])
    content {
      protocol         = egress_security_rules.value.protocol
      destination      = egress_security_rules.value.destination
      destination_type = try(egress_security_rules.value.destination_type, "CIDR_BLOCK")
      description      = try(egress_security_rules.value.description, null)
      stateless        = try(egress_security_rules.value.stateless, false)
    }
  }
}
