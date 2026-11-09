output "db_engine_name" {
  value       = google_sql_database_instance.dbe.name
  description = "Database Engine Name"
}

output "db_engine_sa" {
  value       = google_sql_database_instance.dbe.service_account_email_address
  description = "Database Engine SA"
}

output "db_engine_private_ip" {
  value       = google_sql_database_instance.dbe.private_ip_address
  description = "Database Engine Private IP"
}

output "db_engine_public_ip" {
  value       = google_sql_database_instance.dbe.public_ip_address
  description = "Database Engine Public IP"
}

output "connection_name" {
  value       = google_sql_database_instance.dbe.connection_name
  description = "Database Engine Connection Name"
}

output "service_account_name" {
  value       = google_sql_database_instance.dbe.service_account_email_address
  description = "Service Account Name"
}

output "secret_users_password" {
  value       = google_secret_manager_secret.user_password
  description = "Users DB Secret ID"
}

output "secret_admin_name" {
  value       = google_secret_manager_secret.admin_name
  description = "Admin DB Username Secret ID"
}

output "secret_admin_password" {
  value       = google_secret_manager_secret.admin_password
  description = "Admin DB Password Secret ID"
}

output "secret_admin_name_secret_data" {
  value       = google_secret_manager_secret_version.admin_name.secret_data
  description = "Admin DB Username Data"
  sensitive   = true
}
output "secret_admin_password_secret_data" {
  value       = google_secret_manager_secret_version.admin_password.secret_data
  description = "Admin DB Username Password Data"
  sensitive   = true
}
