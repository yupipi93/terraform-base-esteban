// If the CR service account doesn't have permissions at creation time, it will fail
// This will always fails if the service account is created inside the module, because the
// terraform is not able to create the Service account, apply outside resources and then continue
// with the internal resources and then will try to apply all the internal at once.
resource "google_secret_manager_secret_iam_member" "secrets_permissions" {
  for_each = { for idx, value in
    distinct(flatten([
      for container in var.cloudrun.containers : [
        for secret in try(container.secrets, []) : secret.secret
      ]
    ])) : idx => value
  }

  project   = length(try(regex("projects/([a-z][-a-z0-9]{4,28}[a-z0-9]{1})/", each.value), [])) > 0 ? regex("projects/([a-z][-a-z0-9]{4,28}[a-z0-9]{1})/", each.value)[0] : var.gcp_project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account.external ? var.service_account.name : google_service_account.cloudrun[0].email}"
}
