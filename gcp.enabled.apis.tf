# APIs of the workspace project, in one resource keyed by service name.
#
#   - `active-apis` (default.yaml): the base every workspace needs, whatever its sections.
#   - `extra-apis` (workspace file): the additive door for an API nothing here knows about.
#     `settings` is a SHALLOW merge of default.yaml and the workspace file, so a workspace
#     that declares `active-apis` replaces the whole base list instead of adding to it.
#   - `local.feature_apis`: the APIs of one feature, turned on by the same expression that
#     creates the feature's resources, so a Cloud Run only project does not enable the SQL
#     Admin or Redis APIs.
#
# disable_on_destroy = false: an API that leaves the list (a section removed, or an
# existing workspace whose base list got shorter) is dropped from state and stays
# enabled in the project. Terraform never disables an API here.
locals {
  feature_apis = {
    artifact_scanning    = ["containerscanning.googleapis.com"]
    binary_authorization = ["binaryauthorization.googleapis.com", "containeranalysis.googleapis.com", "cloudkms.googleapis.com"]
    budget               = ["billingbudgets.googleapis.com", "cloudbilling.googleapis.com"]
    # The stop billing function is a 2nd gen Cloud Function fed by a Pub/Sub topic.
    budget_auto_stop = ["cloudfunctions.googleapis.com", "eventarc.googleapis.com", "pubsub.googleapis.com"]
    # A service or job that mounts a Cloud SQL instance (this project's or another's)
    # needs the SQL Admin API in its own project, with or without a database section.
    cloud_sql_mount = ["sqladmin.googleapis.com"]
    cloud_tasks     = ["cloudtasks.googleapis.com"]
    compute         = ["compute.googleapis.com"]
    contacts        = ["essentialcontacts.googleapis.com"]
    database        = ["sqladmin.googleapis.com", "servicenetworking.googleapis.com"]
    dns             = ["dns.googleapis.com"]
    firestore       = ["firestore.googleapis.com"]
    iap             = ["iap.googleapis.com"]
    lb              = ["compute.googleapis.com"]
    network         = ["compute.googleapis.com", "servicenetworking.googleapis.com", "vpcaccess.googleapis.com"]
    org_policy      = ["orgpolicy.googleapis.com"]
    pubsub          = ["pubsub.googleapis.com"]
    redis           = ["redis.googleapis.com", "servicenetworking.googleapis.com"]
    scheduler       = ["cloudscheduler.googleapis.com"]
    sops            = ["cloudkms.googleapis.com"]
    # A job that names a Serverless VPC Access connector instead of direct VPC egress.
    vpc_connector = ["vpcaccess.googleapis.com"]
    wif           = ["sts.googleapis.com", "iamcredentials.googleapis.com"]
  }

  # Each gate is the expression the feature's resources (or the module input) are built from.
  feature_enabled = {
    artifact_scanning    = try(local.settings.security.artifact_scanning, false)
    binary_authorization = local.enable_binary_auth
    budget               = local.enable_billing
    budget_auto_stop     = local.enable_stop_billing
    cloud_sql_mount = anytrue(concat(
      [for config in values(local.app_services) : try(config.cloudrun.cloud_sql_instances_mount, null) != null],
      [for config in values(try(local.settings.app.job, {})) : try(config.job-config.cloud_sql_instances_mount, null) != null],
    ))
    cloud_tasks = length(local.cloud_tasks_configs) > 0
    compute     = length(local.compute_instances) > 0 || length(local.compute_nats) > 0
    contacts    = length(local.essential_contacts) > 0
    database    = length(try(local.settings.database, {})) > 0
    dns         = length(local.dns_zones) > 0 || local.enable_elastic_psc_dns
    firestore   = length(local.all_firestore) > 0
    iap         = local.iap_identity_enabled
    lb          = local.lb_enabled
    network     = local.network_enabled
    org_policy  = length(local.service_account_key_constraints) > 0
    pubsub      = length(try(local.settings.pubsub.topics, {})) > 0
    redis       = length(try(local.settings.redis, {})) > 0
    scheduler   = length(try(local.settings.scheduler, {})) > 0 || length(try(local.settings.service_scheduler, {})) > 0
    sops        = local.sops_enabled
    vpc_connector = anytrue([
      for config in values(try(local.settings.app.job, {})) : try(config.job-config.vpc_access.connector, null) != null
    ])
    wif = local.wif_enabled
  }

  enabled_apis = sort(distinct(concat(
    # coalesce also covers a key left empty in YAML, which decodes to null.
    coalesce(try(local.settings.active-apis, null), []),
    coalesce(try(local.settings.extra-apis, null), []),
    flatten([for feature, apis in local.feature_apis : apis if local.feature_enabled[feature]]),
  )))
}

resource "google_project_service" "enabled_apis" {
  for_each = toset(local.enabled_apis)

  project = local.settings.project.id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# These APIs had a resource of their own before feature_apis. The moves keep the same
# remote object under its new key, so the plan shows no destroy and no create.
moved {
  from = google_project_service.wif_sts[0]
  to   = google_project_service.enabled_apis["sts.googleapis.com"]
}

moved {
  from = google_project_service.binary_authorization[0]
  to   = google_project_service.enabled_apis["binaryauthorization.googleapis.com"]
}

moved {
  from = google_project_service.container_analysis[0]
  to   = google_project_service.enabled_apis["containeranalysis.googleapis.com"]
}

moved {
  from = google_project_service.binauth_kms[0]
  to   = google_project_service.enabled_apis["cloudkms.googleapis.com"]
}

moved {
  from = google_project_service.container_scanning[0]
  to   = google_project_service.enabled_apis["containerscanning.googleapis.com"]
}

# Binary Authorization and SOPS both enabled Cloud KMS and only one move can own the key.
# The SOPS copy leaves state without an API call. With SOPS only, enabled_apis declares
# the API again, a create that changes nothing on an API that is already on.
removed {
  from = google_project_service.cloudkms

  lifecycle {
    destroy = false
  }
}
