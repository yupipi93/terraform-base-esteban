## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.8 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 6.8 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_address.nat_ip](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address) | resource |
| [google_compute_global_address.net_private](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_network.net](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_router.router](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router) | resource |
| [google_compute_router_nat.nat](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_nat) | resource |
| [google_compute_subnetwork.subnet](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_monitoring_alert_policy.nat](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_project_service.serverless_vpc_api](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_project_service.servicenetworking](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_service_networking_connection.net_private_connection](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_networking_connection) | resource |
| [google_vpc_access_connector.serverless_vpc_connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vpc_access_connector) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_base_name"></a> [base\_name](#input\_base\_name) | Project for the resource | `string` | n/a | yes |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project source | `string` | n/a | yes |
| <a name="input_gcp_project_sys_id"></a> [gcp\_project\_sys\_id](#input\_gcp\_project\_sys\_id) | GCP Project ID SYS (Required for monitoring the NAT if used) | `string` | `""` | no |
| <a name="input_internal_connection"></a> [internal\_connection](#input\_internal\_connection) | Create an internal VPC network to allow SaS services to be used in that network | `bool` | `false` | no |
| <a name="input_module_name"></a> [module\_name](#input\_module\_name) | Constant for module | `string` | `"networking"` | no |
| <a name="input_monitoring"></a> [monitoring](#input\_monitoring) | n/a | <pre>object({<br/>    dropped_sent_endpoint_independence_conflict = optional(object({<br/>      duration         = optional(string, "1800s")<br/>      threshold_value  = optional(number, 10)<br/>      alignment_period = optional(string, "60s")<br/>    }), {}),<br/>    dropped_sent_out_of_resources = optional(object({<br/>      duration         = optional(string, "1800s")<br/>      threshold_value  = optional(number, 10)<br/>      alignment_period = optional(string, "60s")<br/>    }), {}),<br/>    nat_allocation_failed = optional(object({<br/>      duration         = optional(string, "1800s")<br/>      threshold_value  = optional(number, 1) # Is a True/False measurement.<br/>      alignment_period = optional(string, "60s")<br/>    }), {}),<br/><br/>    notification_channels = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_nats"></a> [nats](#input\_nats) | Nats that will be created into the project | <pre>map(object({<br/>    region                              = string<br/>    number_of_addresses                 = optional(number, 0)  # if not provided, auto mode will be used<br/>    name_v3                             = optional(bool, true) # If you named the NAT IP with version 3.1, 3.2, or 3.3, set this variable to false<br/>    old_naming_method                   = optional(bool, false)<br/>    min_vm_ports                        = optional(number, 1024)<br/>    max_vm_ports                        = optional(number)<br/>    enable_dynamic_port_allocation      = optional(bool, false)<br/>    enable_endpoint_independent_mapping = optional(bool, false)<br/>    subnets                             = optional(list(string), []) # List of the subnetworks created in subnets. If not provided, all the subnets in the region.<br/>  }))</pre> | `{}` | no |
| <a name="input_network_tier"></a> [network\_tier](#input\_network\_tier) | Network Tier | `string` | `"PREMIUM"` | no |
| <a name="input_private_service_access_required"></a> [private\_service\_access\_required](#input\_private\_service\_access\_required) | A private Cloud SQL or Memorystore instance uses this network: the plan stops when services\_ip\_ranges has no VPC\_PEERING entry | `bool` | `false` | no |
| <a name="input_repo_iac"></a> [repo\_iac](#input\_repo\_iac) | URL or name of IAC repository | `string` | n/a | yes |
| <a name="input_reserved_cidrs"></a> [reserved\_cidrs](#input\_reserved\_cidrs) | CIDRs outside this module's subnets that an explicit services\_ip\_ranges address must not overlap | `list(string)` | `[]` | no |
| <a name="input_serverless_vpc_connectors"></a> [serverless\_vpc\_connectors](#input\_serverless\_vpc\_connectors) | serverless\_vpc\_connector configuration | <pre>map(object({<br/>    cidr          = optional(string, "10.8.0.0/28")<br/>    region        = string<br/>    machine_type  = optional(string, "e2-micro")<br/>    subnet        = optional(string)<br/>    max_instances = optional(number, 3)<br/>    min_instances = optional(number, 2)<br/>  }))</pre> | `{}` | no |
| <a name="input_services_ip_ranges"></a> [services\_ip\_ranges](#input\_services\_ip\_ranges) | google\_compute\_global\_address configuration (Services IP Ranges). Every VPC\_PEERING entry is reserved for one Private Service Access connection. | <pre>map(object({<br/>    address       = optional(string, null)<br/>    description   = optional(string, null)<br/>    prefix_length = optional(number, 16)<br/>    address_type  = optional(string, "INTERNAL")<br/>    purpose       = optional(string, "VPC_PEERING")<br/>    single_dash   = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Subnets that will be created into the network | <pre>map(object({<br/>    cidr                  = string<br/>    region                = string<br/>    purpose               = optional(string)<br/>    role                  = optional(string)<br/>    private_google_access = optional(bool, true)<br/>    single_dash           = optional(bool, false)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ip_nat"></a> [ip\_nat](#output\_ip\_nat) | Cloud NAT IPs |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | Network id |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Network name |
| <a name="output_psa_connection_id"></a> [psa\_connection\_id](#output\_psa\_connection\_id) | Private Service Access connection id, null when no VPC\_PEERING range is set |
| <a name="output_psa_network_id"></a> [psa\_network\_id](#output\_psa\_network\_id) | Network id that depends on the Private Service Access connection. A private Cloud SQL or Memorystore instance given this id is created after the peering. |
| <a name="output_services_ip_range_names"></a> [services\_ip\_range\_names](#output\_services\_ip\_range\_names) | Allocated range name per services\_ip\_ranges key |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | Network link |
| <a name="output_subnetworks"></a> [subnetworks](#output\_subnetworks) | Subnetworks data |
| <a name="output_vpc_connectors"></a> [vpc\_connectors](#output\_vpc\_connectors) | VPC connectors data |
