output "cloudrun_name" {
  value = google_cloud_run_v2_service.service.name
}

output "sa_email" {
  value = var.service_account.external ? var.service_account.name : google_service_account.cloudrun[0].email
}

output "sa_id" {
  value = var.service_account.external ? null : google_service_account.cloudrun[0].id
}

output "cloudrun_service_url" {
  value = google_cloud_run_v2_service.service.uri
}
