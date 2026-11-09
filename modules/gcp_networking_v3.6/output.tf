output "network_self_link" {
  description = "Network link"
  value       = google_compute_network.net.self_link
}

output "ip_nat" {
  description = "Cloud NAT IPs"
  value       = [for value in google_compute_address.nat_ip : value.address]
}

output "network_id" {
  description = "Network id"
  value       = google_compute_network.net.id
}

output "psa_network_id" {
  description = "Network id that depends on the Private Service Access connection. A private Cloud SQL or Memorystore instance given this id is created after the peering."
  value       = google_compute_network.net.id
  depends_on  = [google_service_networking_connection.net_private_connection]
}

output "psa_connection_id" {
  description = "Private Service Access connection id, null when no VPC_PEERING range is set"
  value       = try(google_service_networking_connection.net_private_connection[0].id, null)
}

output "services_ip_range_names" {
  description = "Allocated range name per services_ip_ranges key"
  value       = { for key, range in google_compute_global_address.net_private : key => range.name }
}

output "network_name" {
  description = "Network name"
  value       = google_compute_network.net.name
}

output "subnetworks" {
  description = "Subnetworks data"
  value       = google_compute_subnetwork.subnet
}

output "vpc_connectors" {
  description = "VPC connectors data"
  value       = google_vpc_access_connector.serverless_vpc_connector
}
