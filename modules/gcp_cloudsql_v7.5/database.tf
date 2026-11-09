resource "google_sql_database" "dbe" {
  for_each = toset(var.databases)
  name     = each.value
  instance = google_sql_database_instance.dbe.name
  project  = var.gcp_project_id
}
