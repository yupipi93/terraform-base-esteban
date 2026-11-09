locals {
  enable_binary_auth  = try(local.settings.binary_authorization.enabled, false)
  binauth_evaluation  = try(local.settings.binary_authorization.evaluation_mode, "REQUIRE_ATTESTATION")
  binauth_enforcement = try(local.settings.binary_authorization.enforcement_mode, "DRYRUN_AUDIT_LOG_ONLY")

  # Built from names, not from resource ids, so the Cloud Build substitutions are
  # known at plan time and bin/cloudbuild-render.py can compute the same strings.
  binauth_attestor_name = "${local.base_name_medium}-attestor"
  binauth_key_ring_name = "${local.base_name_medium}-binauth"
  binauth_key_name      = "attestor-signer"
  binauth_attestor      = "projects/${local.settings.project.id}/attestors/${local.binauth_attestor_name}"
  binauth_key_version = format(
    "projects/%s/locations/%s/keyRings/%s/cryptoKeys/%s/cryptoKeyVersions/1",
    local.settings.project.id, local.settings.region_name, local.binauth_key_ring_name, local.binauth_key_name
  )
}

# The key Cloud Build signs attestations with. A key ring cannot be deleted: turning
# Binary Authorization off drops it from state only, and turning it back on needs a
# `terraform import` of the ring (docs/cloudbuild-pipeline.md).
resource "google_kms_key_ring" "binauth" {
  count    = local.enable_binary_auth ? 1 : 0
  project  = local.settings.project.id
  name     = local.binauth_key_ring_name
  location = local.settings.region_name

  depends_on = [google_project_service.enabled_apis]
}

# Asymmetric keys do not rotate automatically. Version 1 is the one the attestor
# trusts and the pipeline signs with.
resource "google_kms_crypto_key" "binauth" {
  count    = local.enable_binary_auth ? 1 : 0
  name     = local.binauth_key_name
  key_ring = google_kms_key_ring.binauth[0].id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "EC_SIGN_P256_SHA256"
    protection_level = "SOFTWARE"
  }
}

data "google_kms_crypto_key_version" "binauth" {
  count      = local.enable_binary_auth ? 1 : 0
  crypto_key = google_kms_crypto_key.binauth[0].id
  version    = 1
}

resource "google_container_analysis_note" "binauth" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id
  name    = local.binauth_attestor_name

  attestation_authority {
    hint {
      human_readable_name = "${local.base_name_medium} attestor"
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

resource "google_binary_authorization_attestor" "binauth" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id
  name    = local.binauth_attestor_name

  attestation_authority_note {
    note_reference = google_container_analysis_note.binauth[0].id

    public_keys {
      id = data.google_kms_crypto_key_version.binauth[0].id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.binauth[0].public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.binauth[0].public_key[0].algorithm
      }
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# The attestor reads attestations from the note as its own service account.
resource "google_container_analysis_note_iam_member" "binauth_attestor_reader" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id
  note    = google_container_analysis_note.binauth[0].name
  role    = "roles/containeranalysis.notes.occurrences.viewer"
  member  = "serviceAccount:${google_binary_authorization_attestor.binauth[0].attestation_authority_note[0].delegation_service_account_email}"
}

# What the sign-image step of cloudbuild_files/cloudbuild.yaml needs, and nothing
# when Binary Authorization is off or nothing builds.
resource "google_binary_authorization_attestor_iam_member" "cloudbuild_viewer" {
  count    = local.enable_binary_auth && local.cloudbuild_enabled ? 1 : 0
  project  = local.settings.project.id
  attestor = google_binary_authorization_attestor.binauth[0].name
  role     = "roles/binaryauthorization.attestorsViewer"
  member   = "serviceAccount:${local.cloudbuild_sa_email}"
}

resource "google_container_analysis_note_iam_member" "cloudbuild_attacher" {
  count   = local.enable_binary_auth && local.cloudbuild_enabled ? 1 : 0
  project = local.settings.project.id
  note    = google_container_analysis_note.binauth[0].name
  role    = "roles/containeranalysis.notes.attacher"
  member  = "serviceAccount:${local.cloudbuild_sa_email}"
}

# Occurrences live in the project, not under the note, so this one is project-wide.
resource "google_project_iam_member" "cloudbuild_occurrences" {
  count   = local.enable_binary_auth && local.cloudbuild_enabled ? 1 : 0
  project = local.settings.project.id
  role    = "roles/containeranalysis.occurrences.editor"
  member  = "serviceAccount:${local.cloudbuild_sa_email}"
}

resource "google_kms_crypto_key_iam_member" "cloudbuild_signer" {
  count         = local.enable_binary_auth && local.cloudbuild_enabled ? 1 : 0
  crypto_key_id = google_kms_crypto_key.binauth[0].id
  role          = "roles/cloudkms.signerVerifier"
  member        = "serviceAccount:${local.cloudbuild_sa_email}"
}

resource "google_binary_authorization_policy" "policy" {
  count   = local.enable_binary_auth ? 1 : 0
  project = local.settings.project.id

  global_policy_evaluation_mode = "ENABLE"

  default_admission_rule {
    evaluation_mode         = local.binauth_evaluation
    enforcement_mode        = local.binauth_enforcement
    require_attestations_by = google_binary_authorization_attestor.binauth[*].name
  }

  admission_whitelist_patterns {
    name_pattern = "gcr.io/google_containers/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google-containers/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/cloud-builders/*"
  }
  # The hello placeholder every service and job is created with (gcp.cloudrun.tf,
  # gcp.jobs.tf). Without it the first apply of an enforcing workspace is refused.
  admission_whitelist_patterns {
    name_pattern = "us-docker.pkg.dev/cloudrun/container/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/gae-runtimes/*"
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_binary_authorization_attestor.binauth,
  ]
}
