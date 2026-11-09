# Optional SOPS path. A workspace opts in with sops.enabled. Terraform creates a
# Cloud KMS key in this project unless sops.kms_key already names one. Encrypted
# files under secrets/<workspace>/<service>.enc.yaml replace the placeholder
# version of a matching Cloud Run secret. No file means the placeholder stays.
# This stack does not reuse a key ring from another project.

locals {
  sops_enabled    = try(local.settings.sops.enabled, false)
  sops_kms_key    = try(local.settings.sops.kms_key, null)
  sops_create_key = local.sops_enabled && local.sops_kms_key == null

  sops_service_files = {
    for name, _ in local.app_services :
    name => "${path.module}/secrets/${local.workspace}/${name}.enc.yaml"
    if fileexists("${path.module}/secrets/${local.workspace}/${name}.enc.yaml")
  }
}

resource "google_kms_key_ring" "sops" {
  count    = local.sops_create_key ? 1 : 0
  project  = local.settings.project.id
  name     = "${local.base_name_medium}-sops"
  location = local.settings.region_name

  depends_on = [google_project_service.enabled_apis]
}

resource "google_kms_crypto_key" "sops" {
  count    = local.sops_create_key ? 1 : 0
  name     = "sops"
  key_ring = google_kms_key_ring.sops[0].id
  purpose  = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "sops_users" {
  for_each      = local.sops_create_key ? toset(try(local.settings.sops.decrypters, [])) : []
  crypto_key_id = google_kms_crypto_key.sops[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = each.value
}

locals {
  sops_kms_id = local.sops_enabled ? coalesce(local.sops_kms_key, try(google_kms_crypto_key.sops[0].id, null)) : null
}

data "sops_file" "service" {
  for_each    = local.sops_service_files
  source_file = each.value
}

locals {
  sops_secret_names = {
    for name, file in data.sops_file.service :
    name => nonsensitive(keys(file.data))
  }

  secrets_from_sops = {
    for key, item in local.secrets_map : key => item
    if contains(try(local.sops_secret_names[item.service_name], []), item.secret_name)
  }

  secrets_placeholder = {
    for key, item in local.secrets_map : key => item
    if !contains(try(local.sops_secret_names[item.service_name], []), item.secret_name)
  }
}

output "sops_kms_key" {
  description = "KMS key id to put in .sops.yaml. Null when sops.enabled is false."
  value       = local.sops_kms_id
}
