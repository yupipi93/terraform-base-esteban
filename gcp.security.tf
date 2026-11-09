# Notification Channel for Security Alerts
resource "google_monitoring_notification_channel" "security_alerts" {
  display_name = "${local.base_name}-security-alerts"
  type         = "email"

  labels = {
    email_address = try(local.settings.security.alerts_email, "")
  }

  description = "Email notification channel for security alerts in ${local.base_name} project"

  # Keep enabled: every alert policy in the repo (security, Cloud Run, LB, NAT)
  # points here, so a disabled channel silently mutes all of them.
  enabled = true

  lifecycle {
    # merge() in locals.tf is shallow: a workspace that sets any security key
    # replaces the whole map and must repeat alerts_email.
    precondition {
      condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", try(local.settings.security.alerts_email, "")))
      error_message = "Set security.alerts_email to a valid address in settings/default.yaml or the workspace file. A workspace that declares security: must repeat it, because the merge is shallow."
    }
    # A module block takes no precondition, so the metric_alerts shape is
    # checked here, on the channel those alerts notify.
    precondition {
      condition = can(tobool(local.security_metric_alerts_setting)) || (
        can(keys(local.security_metric_alerts_setting))
        && length(setsubtract(try(keys(local.security_metric_alerts_setting), []), local.security_metric_alert_families)) == 0
        && alltrue([for value in try(values(local.security_metric_alerts_setting), []) : can(tobool(value))])
      )
      error_message = "security.metric_alerts is true, false or a map of ${join(", ", local.security_metric_alert_families)} to true or false."
    }
    # Checked here for the same reason: with a value that is not a bool the
    # org policies below have no instance to carry a precondition.
    precondition {
      condition     = local.disable_service_account_keys != null
      error_message = "security.disable_service_account_keys is true or false."
    }
    precondition {
      condition     = local.essential_contacts_list != null
      error_message = "security.essential_contacts is true, false or a list of maps with email, categories and language_tag."
    }
  }
}

# security.metric_alerts switches the threshold alerts of the basic security
# module: true or false for all of them, or a map of family => bool where an
# omitted family stays on. Five families report the same events as a
# monitoring.log_alerts preset, which also names the principal and skips the
# Terraform identity; pro turns those five off. Network, routes and owner have
# no preset.
locals {
  security_metric_alert_families = ["audit_config", "cloud_sql", "custom_roles", "firewall", "network", "owner", "routes", "storage_permissions"]

  security_metric_alert_presets = {
    audit_config        = "audit_config_change"
    cloud_sql           = "sql_instance_change"
    custom_roles        = "custom_role_change"
    firewall            = "firewall_change"
    storage_permissions = "bucket_iam_change"
  }

  security_metric_alerts_setting = try(local.settings.security.metric_alerts, true)

  security_metric_alerts = {
    for family in local.security_metric_alert_families : family => try(
      tobool(local.security_metric_alerts_setting),
      tobool(local.security_metric_alerts_setting[family]),
      true,
    )
  }

  # Families switched off with no log alert on the same events left.
  security_metric_alerts_uncovered = [
    for family, enabled in local.security_metric_alerts : family
    if !enabled && !contains(keys(local.log_alerts), try(local.security_metric_alert_presets[family], ""))
  ]
}

check "security_metric_alerts_covered" {
  assert {
    condition     = length(local.security_metric_alerts_uncovered) == 0
    error_message = "security.metric_alerts turns off ${join(", ", local.security_metric_alerts_uncovered)} with no monitoring.log_alerts preset on the same events, so nothing alerts on them."
  }
}

module "basic_security" {
  source = "./modules/gcp_basic_project_security_v1.9"

  base_name      = local.base_name
  gcp_project_id = local.settings.project.id

  # Admin activity is the trail you need after an IAM or firewall change.
  # Data access logs are expensive, so they stay off unless a workspace asks.
  audit_logging = {
    admin_read = try(local.settings.security.audit_logging.admin_read, true)
    data_read  = try(local.settings.security.audit_logging.data_read, false)
    data_write = try(local.settings.security.audit_logging.data_write, false)
  }

  metric_alerts = local.security_metric_alerts

  notification_channels = [
    google_monitoring_notification_channel.security_alerts.name
  ]
}

# security.disable_service_account_keys enforces two boolean organization policy
# constraints on this project: no new service account key can be created, and no
# public key can be uploaded to a service account. Keys that already exist keep
# working until someone deletes them. Nothing in this stack needs a key: Cloud
# Run, jobs and Cloud Build run as attached service accounts, and external CI
# federates through wif. The identity that applies needs
# roles/orgpolicy.policyAdmin, which can only be granted on the organization or
# a folder above the project, so it usually comes from the platform team.
locals {
  # null when the value is not a bool; the channel's precondition stops the plan.
  disable_service_account_keys = try(tobool(coalesce(try(local.settings.security.disable_service_account_keys, null), false)), null)

  service_account_key_constraints = local.disable_service_account_keys == true ? [
    "iam.disableServiceAccountKeyCreation",
    "iam.disableServiceAccountKeyUpload",
  ] : []
}

resource "google_org_policy_policy" "service_account_keys" {
  for_each = toset(local.service_account_key_constraints)

  name   = "projects/${local.settings.project.id}/policies/${each.value}"
  parent = "projects/${local.settings.project.id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# security.essential_contacts names who Google tells about security incidents,
# outages, suspensions and legal notices for this project; without it they go to
# the project owners only. Absent or false: no contact. true: alerts_email for
# SECURITY and TECHNICAL. A list: one contact per entry, where email defaults to
# alerts_email, categories to SECURITY and TECHNICAL, language_tag to en.
locals {
  essential_contact_categories = ["ALL", "SUSPENSION", "SECURITY", "TECHNICAL", "BILLING", "LEGAL", "PRODUCT_UPDATES", "TECHNICAL_INCIDENTS"]
  essential_contact_defaults   = ["SECURITY", "TECHNICAL"]

  essential_contacts_setting = try(local.settings.security.essential_contacts, null)

  # The entries, or null when the value is neither a bool nor a list of maps.
  essential_contacts_list = try(
    [for contact in [{}] : contact if(local.essential_contacts_setting == null ? false : tobool(local.essential_contacts_setting))],
    !can(keys(local.essential_contacts_setting)) && alltrue([for contact in local.essential_contacts_setting : can(keys(contact))]) ? [for contact in local.essential_contacts_setting : contact] : null,
    null,
  )

  essential_contacts = {
    for contact in try([for entry in local.essential_contacts_list : entry], []) :
    lower(try(contact.email, local.settings.security.alerts_email)) => {
      categories   = distinct(try(tolist(contact.categories), local.essential_contact_defaults))
      language_tag = try(contact.language_tag, "en")
    }
  }
}

resource "google_essential_contacts_contact" "contacts" {
  for_each = local.essential_contacts

  parent                              = "projects/${local.settings.project.id}"
  email                               = each.key
  language_tag                        = each.value.language_tag
  notification_category_subscriptions = each.value.categories

  lifecycle {
    precondition {
      condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", each.key))
      error_message = "security.essential_contacts: ${each.key} is not an email address."
    }
    precondition {
      condition     = length(each.value.categories) > 0 && length(setsubtract(each.value.categories, local.essential_contact_categories)) == 0
      error_message = "security.essential_contacts: the categories of ${each.key} must be one or more of ${join(", ", local.essential_contact_categories)}."
    }
    precondition {
      condition     = can(regex("^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$", each.value.language_tag))
      error_message = "security.essential_contacts: language_tag of ${each.key} must be a BCP-47 tag such as en, es or en-GB."
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# Data Access logs for Secret Manager only, so the secret_access alert in
# gcp.monitoring.tf has entries to match. The module above owns the
# allServices audit config; a config per service is a separate entry in the
# project IAM policy, and no resource here manages the policy as a whole.
resource "google_project_iam_audit_config" "secret_manager_data_read" {
  count   = local.secret_access_enabled ? 1 : 0
  project = local.settings.project.id
  service = "secretmanager.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
}

# security.artifact_scanning turns on Artifact Registry automatic scanning through
# the Container Scanning API (feature_apis in gcp.enabled.apis.tf). It is not a
# registry product that has to be installed beside the project.
