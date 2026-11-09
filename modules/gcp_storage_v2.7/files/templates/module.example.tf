module "storage_processing" {
  source = "./modules/gcp_storage_v2.7"

  base_name      = local.base_name
  region_name    = local.settings.region_name
  gcp_project_id = local.settings.project.id

  # Another optional variables (It has defaults values on vars.tf file)
  # class = local.settings.class
  # force_destroy = true
  # enable_versioning = true
  # uniform_bucket_level_access = true
  # authoritative_permissions = true
  # soft_delete_retention_duration = 604800

  # Lifecycle rules are optional and the name is only used to keep it simple
  lifecycle_rules = {
    delete_tmp_files = {
      age         = 1,
      action_type = "Delete",
      action_sc   = "ARCHIVE",
      prefixes = [
        "tmp/",
      ]
    }
    delete_noncurrent_versions = {
      days_since_noncurrent_time = 30,
      action_type                = "Delete",
    }
  }

  # Retention policy (Optional): objects cannot be deleted or replaced for 10 years.
  # is_locked = true is irreversible.
  retention_policy = {
    retention_period = 10 * 365 * 86400
    is_locked        = false
  }

  # Usage and storage logs (Optional), written into an existing bucket
  logging = {
    log_bucket        = "example-app-gcs-logs"
    log_object_prefix = "processing"
  }

  # Permissions are optional
  permissions = {
    admin = {
      members = ["group:name@.domain.com", "user:pepe@domain.net"]
      roles = [
        "roles/storage.admin",
      ]
    },
    viewer = {
      members = ["user:user@domain.com", "user:pepe@domain.net"]
      roles = [
        "roles/storage.objectViewer",
        "roles/storage.objectCreator",
      ]
    }
  }

  # Configure the storage to be a website (Optional)
  website = {
    main_page_suffix = "index.html" # The index page that will be shown when the root path is requested (https://site.com/).
    not_found_page   = "404.html"   # The HTML to send when there is a 404 error.
  }

  # Configure the storage cors (Optional)
  # Multiple cors can be configured (different sites for example).
  cors = [
    {
      origin          = ["https://myluckysite.com"] # This is the ORIGIN header sent by the client browser. curl -> curl -I -H "ORIGIN: https://myluckysite.com" https://storage.googleapis.com...
      method          = ["GET", "HEAD"]             # Methods to which the CORS will be sent: "GET", "HEAD", "PUT", "POST", "DELETE"
      response_header = ["https://myluckysite.com"] # Header sent to the client browser. Normally the same as the origin.
      max_age_seconds = 3600
    }
  ]
}
