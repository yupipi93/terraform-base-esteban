# The networking module with network.services_ip_ranges of settings/pro.yaml,
# passed the way gcp.network.tf passes it. It checks the Private Service Access
# resources the module creates and the preconditions that stop the plan:
# pro.tftest.hcl checks that pro asks for them and default.tftest.hcl that the
# default workspace asks for none.

mock_provider "google" {}

variables {
  base_name          = "app-pro-vpc"
  gcp_project_id     = "example-app-pro"
  gcp_project_sys_id = "example-app-pro"
  repo_iac           = "example-iac"
  subnets = {
    services = {
      cidr   = "10.20.1.0/24"
      region = "europe-west1"
    }
  }
}

run "pro_private_service_access" {
  command = plan

  module {
    source = "./modules/gcp_networking_v3.6"
  }

  variables {
    services_ip_ranges              = yamldecode(file("settings/pro.yaml")).network.services_ip_ranges
    private_service_access_required = true
  }

  assert {
    condition = (
      length(google_compute_global_address.net_private) == 1
      && google_compute_global_address.net_private["private"].name == "app-pro-vpc--private"
      && google_compute_global_address.net_private["private"].address == "10.21.0.0"
      && google_compute_global_address.net_private["private"].prefix_length == 16
      && google_compute_global_address.net_private["private"].purpose == "VPC_PEERING"
      && google_compute_global_address.net_private["private"].address_type == "INTERNAL"
    )
    error_message = "pro reserves 10.21.0.0/16 for VPC peering."
  }

  assert {
    condition = (
      length(google_service_networking_connection.net_private_connection) == 1
      && google_service_networking_connection.net_private_connection[0].service == "servicenetworking.googleapis.com"
      && google_service_networking_connection.net_private_connection[0].reserved_peering_ranges == tolist(["app-pro-vpc--private"])
      && google_service_networking_connection.net_private_connection[0].deletion_policy == "ABANDON"
    )
    error_message = "pro has one servicenetworking connection carrying its range, abandoned on destroy."
  }
}

run "no_range_no_connection" {
  command = plan

  module {
    source = "./modules/gcp_networking_v3.6"
  }

  variables {
    services_ip_ranges = {}
  }

  assert {
    condition     = length(google_compute_global_address.net_private) == 0 && length(google_service_networking_connection.net_private_connection) == 0
    error_message = "No services_ip_ranges entry: no reserved range and no connection."
  }

  assert {
    condition     = length(google_compute_subnetwork.subnet) == 1
    error_message = "The VPC and its subnet are still planned (positive control)."
  }
}

run "private_store_without_range_is_refused" {
  command = plan

  module {
    source = "./modules/gcp_networking_v3.6"
  }

  variables {
    services_ip_ranges              = {}
    private_service_access_required = true
  }

  expect_failures = [google_compute_network.net]
}

run "range_over_the_subnet_is_refused" {
  command = plan

  module {
    source = "./modules/gcp_networking_v3.6"
  }

  variables {
    services_ip_ranges = {
      private = { address = "10.20.0.0", prefix_length = 16 }
    }
  }

  expect_failures = [google_compute_network.net]
}

run "range_over_a_reserved_cidr_is_refused" {
  command = plan

  module {
    source = "./modules/gcp_networking_v3.6"
  }

  variables {
    services_ip_ranges = {
      private = { address = "10.21.0.0", prefix_length = 16 }
    }
    reserved_cidrs = ["10.21.4.0/24"]
  }

  expect_failures = [google_compute_network.net]
}

run "range_too_small_is_refused" {
  command = plan

  module {
    source = "./modules/gcp_networking_v3.6"
  }

  variables {
    services_ip_ranges = {
      private = { address = "10.21.0.0", prefix_length = 28 }
    }
  }

  expect_failures = [var.services_ip_ranges]
}
