# ===================================================================
# BILLING BUDGET AND AUTOMATED COST CONTROL (STOP BILLING)
# ===================================================================
# This section handles budget alerts and, only when
# `budget.enable_auto_stop: true`, the Cloud Function that disables billing
# automatically if limits are exceeded.

# 3. Pub/Sub topic to receive budget notifications
resource "google_pubsub_topic" "stop_billing_budget_notifications" {
  count   = local.enable_stop_billing ? 1 : 0
  project = local.settings.project.id
  name    = "${local.base_name}-budget-notifications"

  labels = local.common_labels
}

# 4. Service Account for the Cloud Function
resource "google_service_account" "stop_billing_sa" {
  count        = local.enable_stop_billing ? 1 : 0
  account_id   = "${local.base_name}-stop-billing-sa"
  display_name = "Service Account for Stop Billing Function"
  project      = local.settings.project.id
}

# 5. IAM Permissions for the Stop Billing SA
#    These roles allow the function to read and modify billing settings

# 5.1 Billing Project Manager - allows linking/unlinking projects
resource "google_project_iam_member" "stop_billing_project_manager" {
  count   = local.enable_stop_billing ? 1 : 0
  project = local.settings.project.id
  role    = "roles/billing.projectManager"
  member  = "serviceAccount:${google_service_account.stop_billing_sa[0].email}"

  depends_on = [google_service_account.stop_billing_sa]
}

# 5.2 Service Usage Consumer - allows reading service usage
resource "google_project_iam_member" "stop_billing_service_usage_consumer" {
  count   = local.enable_stop_billing ? 1 : 0
  project = local.settings.project.id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.stop_billing_sa[0].email}"

  depends_on = [google_service_account.stop_billing_sa]
}

# 5.3 Cloud Functions Developer - allows access to Cloud APIs
resource "google_project_iam_member" "stop_billing_cloud_functions_developer" {
  count   = local.enable_stop_billing ? 1 : 0
  project = local.settings.project.id
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.stop_billing_sa[0].email}"

  depends_on = [google_service_account.stop_billing_sa]
}

# 6. Function Source Code Preparation
locals {
  # Create deterministic hash based on file contents
  # Ensure these files exist in your local directory structure!
  stop_billing_files = {
    "main.py"          = filemd5("${path.module}/cloud_function_source/stop_billing/main.py")
    "requirements.txt" = filemd5("${path.module}/cloud_function_source/stop_billing/requirements.txt")
  }
  stop_billing_content_hash = md5(jsonencode(local.stop_billing_files))

  # Check if the budget section exists in settings at all
  enable_billing = try(local.settings.budget, null) != null

  # Opt-in: the function disables billing on the project, which stops every
  # billable service in it. Only `budget.enable_auto_stop: true` deploys it.
  enable_stop_billing = local.enable_billing && try(local.settings.budget.enable_auto_stop, false)
}

# ===================================================================
# STOP BILLING CODE BUCKET
# ===================================================================
# Bucket to store the Cloud Function source code for stop billing.
# Only created when stop billing is enabled.
module "stop_billing_code_bucket" {
  count  = local.enable_stop_billing ? 1 : 0
  source = "./modules/gcp_storage_v2.7"

  base_name      = "${local.base_name_medium}-stop-billing-code"
  region_name    = local.settings.region_name
  gcp_project_id = local.settings.project.id

  class                          = "REGIONAL"
  force_destroy                  = true
  enable_versioning              = false
  uniform_bucket_level_access    = true
  authoritative_permissions      = false
  soft_delete_retention_duration = 7 * 86400 # 7 days in seconds

  lifecycle_rules = {}
  permissions     = {}
  cors            = []
  website         = null
}

data "archive_file" "stop_billing_source" {
  count            = local.enable_stop_billing ? 1 : 0
  type             = "zip"
  source_dir       = "${path.module}/cloud_function_source/stop_billing"
  output_path      = "/tmp/stop_billing_${local.stop_billing_content_hash}.zip"
  output_file_mode = "0666"

  excludes = [
    ".DS_Store",
    "Thumbs.db",
    ".git*",
    "*.tmp"
  ]
}

# 7. Upload Source Code
resource "google_storage_bucket_object" "stop_billing_source" {
  count  = local.enable_stop_billing ? 1 : 0
  name   = "source/stop_billing_${local.stop_billing_content_hash}.zip"
  bucket = module.stop_billing_code_bucket[0].bucket_name
  source = data.archive_file.stop_billing_source[0].output_path

  depends_on = [module.stop_billing_code_bucket]
}

# 8. Cloud Function (Gen 2) to stop billing
resource "google_cloudfunctions2_function" "stop_billing" {
  count = local.enable_stop_billing ? 1 : 0

  name        = "${local.base_name}-stop-billing"
  location    = local.settings.region_name
  description = "Disables billing for the project when the budget is exceeded."
  project     = local.settings.project.id

  labels = local.common_labels

  build_config {
    runtime     = "python313"
    entry_point = "stop_billing"
    source {
      storage_source {
        bucket = module.stop_billing_code_bucket[0].bucket_name
        object = google_storage_bucket_object.stop_billing_source[0].name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.stop_billing_sa[0].email
    environment_variables = {
      GCP_PROJECT = local.settings.project.id
    }
  }

  event_trigger {
    trigger_region = local.settings.region_name
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.stop_billing_budget_notifications[0].id
  }

  depends_on = [
    google_project_service.enabled_apis,
    module.stop_billing_code_bucket
  ]

  lifecycle {
    ignore_changes = [
      event_trigger[0].retry_policy
    ]
  }
}

# 9. Create the Billing Budget
resource "google_billing_budget" "billing_budget" {
  count           = local.enable_billing && try(local.settings.budget.billing_account, null) != null ? 1 : 0
  billing_account = try(local.settings.budget.billing_account, "")
  display_name    = "${local.base_name_medium}-budget"

  amount {
    specified_amount {
      currency_code = "EUR"
      units         = try(local.settings.budget.amount, 0)
    }
  }

  budget_filter {
    projects = ["projects/${local.project_number}"]
  }

  dynamic "all_updates_rule" {
    for_each = local.enable_stop_billing ? [1] : []
    content {
      pubsub_topic   = google_pubsub_topic.stop_billing_budget_notifications[0].id
      schema_version = "1.0"
    }
  }

  dynamic "threshold_rules" {
    for_each = toset(try(local.settings.budget.alert_spent_percents, []))
    content {
      spend_basis       = "CURRENT_SPEND"
      threshold_percent = threshold_rules.value
    }
  }

  depends_on = [
    google_project_service.enabled_apis
  ]
}
