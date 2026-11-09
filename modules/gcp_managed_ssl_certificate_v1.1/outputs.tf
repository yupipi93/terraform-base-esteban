output "id" {
  value       = google_compute_managed_ssl_certificate.base.id
  description = "An identifier for the resource with format projects/{{project}}/global/sslCertificates/{{name}}"
}

output "certificate_id" {
  value       = google_compute_managed_ssl_certificate.base.certificate_id
  description = "The unique identifier for the resource."
}

output "subject_alternative_names" {
  value       = google_compute_managed_ssl_certificate.base.subject_alternative_names
  description = "Domains associated with the certificate via Subject Alternative Name."
}

output "self_link" {
  value       = google_compute_managed_ssl_certificate.base.self_link
  description = "The URI of the created resource."
}
