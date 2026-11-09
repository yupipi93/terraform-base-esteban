terraform {
  required_version = ">= 1.14.0"

  # Remote state, partial configuration: the bucket (and an optional prefix) come
  # from a gitignored backend.hcl, so no clone edits a tracked file. Create the
  # bucket once, copy backend.hcl.example to backend.hcl, then
  # `terraform init -backend-config=backend.hcl`. Workspaces share the bucket:
  # each one gets its own path under the prefix automatically.
  backend "gcs" {}

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.27.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.42.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.42.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }
}
