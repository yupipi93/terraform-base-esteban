# Log-based alert policies on Admin Activity audit logs, driven by
# settings.monitoring.log_alerts. Without the key nothing is created.
#
# Each entry of log_alerts is either a preset (a key of
# local.log_alert_presets, with no filter) or a custom alert (any key, with its
# own filter). Every policy notifies the security alerts channel, once per
# matching entry, with the principal and the method in the incident.
#
# The basic security module already counts some of these events in metric
# threshold policies (firewall, custom roles, audit config, Cloud SQL, bucket
# IAM). Those aggregate over ten minutes, cannot skip the identity that runs
# Terraform and say nothing about who made the change. The presets of the same
# name are the per-event version, and security.metric_alerts turns the module's
# copy off (gcp.security.tf); project IAM changes beyond roles/owner and
# service account keys are only covered here.

locals {
  log_alert_activity = "log_id(\"cloudaudit.googleapis.com/activity\")"

  log_alert_presets = {
    iam_policy_change = {
      severity    = "WARNING"
      description = "The IAM policy of the project changed."
      filter      = "${local.log_alert_activity} AND resource.type=\"project\" AND protoPayload.methodName=\"SetIamPolicy\""
    }
    service_account_key_created = {
      severity    = "ERROR"
      description = "A service account key was created or uploaded. Keys are long-lived credentials."
      filter      = "${local.log_alert_activity} AND protoPayload.methodName=(\"google.iam.admin.v1.CreateServiceAccountKey\" OR \"google.iam.admin.v1.UploadServiceAccountKey\")"
    }
    firewall_change = {
      severity    = "WARNING"
      description = "A VPC firewall rule was created, changed or deleted."
      filter      = "${local.log_alert_activity} AND resource.type=\"gce_firewall_rule\" AND protoPayload.methodName:(\"compute.firewalls.insert\" OR \"compute.firewalls.patch\" OR \"compute.firewalls.update\" OR \"compute.firewalls.delete\")"
    }
    audit_config_change = {
      severity    = "ERROR"
      description = "The audit logging configuration of the project changed."
      filter      = "${local.log_alert_activity} AND protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*"
    }
    custom_role_change = {
      severity    = "WARNING"
      description = "A custom IAM role was created, changed, deleted or restored."
      filter      = "${local.log_alert_activity} AND resource.type=\"iam_role\" AND protoPayload.methodName=(\"google.iam.admin.v1.CreateRole\" OR \"google.iam.admin.v1.UpdateRole\" OR \"google.iam.admin.v1.DeleteRole\" OR \"google.iam.admin.v1.UndeleteRole\")"
    }
    sql_instance_change = {
      severity    = "WARNING"
      description = "A Cloud SQL instance was created, changed or deleted."
      filter      = "${local.log_alert_activity} AND protoPayload.methodName=(\"cloudsql.instances.create\" OR \"cloudsql.instances.update\" OR \"cloudsql.instances.delete\")"
    }
    bucket_iam_change = {
      severity    = "WARNING"
      description = "The IAM policy of a Cloud Storage bucket changed."
      filter      = "${local.log_alert_activity} AND resource.type=\"gcs_bucket\" AND protoPayload.methodName=\"storage.setIamPermissions\""
    }
  }

  log_alerts_settings           = try(local.settings.monitoring.log_alerts, {})
  log_alert_excluded_principals = try(local.settings.monitoring.excluded_principals, [])

  log_alerts = merge(
    {
      for name, alert in local.log_alerts_settings : name => {
        filter      = try(alert.filter, local.log_alert_presets[name].filter, null)
        severity    = try(alert.severity, local.log_alert_presets[name].severity, "WARNING")
        description = try(alert.description, local.log_alert_presets[name].description, "Custom log-based alert ${name}.")
        rate_limit  = try(alert.notification_rate_limit, "300s")
        auto_close  = try(alert.auto_close, "1800s")
        excluded    = distinct(concat(local.log_alert_excluded_principals, try(alert.excluded_principals, [])))
      } if try(alert.enabled, true)
    },
    local.secret_access_enabled ? { secret_access = local.secret_access_alert } : {},
  )
}

# Secret reads by an unexpected principal, driven by
# settings.monitoring.secret_access. Without the key nothing is created.
#
# A secret read (AccessSecretVersion) is only logged as a Data Access audit
# log entry, so the key also turns on DATA_READ for secretmanager.googleapis.com
# alone (gcp.security.tf), not for every service. The alert skips the
# identities this stack gives secret access to: the service account of every
# Cloud Run service and job (the external one when set), the Cloud Build
# service account, the Cloud Build service agent that reads the repository
# connection tokens, and the accessors granted in YAML on standalone secrets
# (secrets.<id>.accessors) and external ones
# (external_secret_access.<id>.accessors). allowed_principals and
# monitoring.excluded_principals (the Terraform identity, which reads secret
# versions on every refresh) are skipped too.
#
# The audit log names the identity that made the call, in principalEmail. Only
# user: and serviceAccount: members are that identity. A group:, domain: or
# principalSet:// grant is read by one of its members, whose email this stack
# does not know, so such a reader still alerts until it is listed in
# allowed_principals.

locals {
  secret_access_settings = try(local.settings.monitoring.secret_access, null)
  secret_access_enabled  = local.secret_access_settings != null && try(local.secret_access_settings.enabled, true)

  secret_access_yaml_readers = distinct([
    for member in concat(
      [for grant in values(local.standalone_secret_accessors) : grant.member],
      [for grant in values(local.external_secret_accessors) : grant.member],
    ) : regex("^(?:user|serviceAccount):([^:?]+)$", member)[0]
    if can(regex("^(?:user|serviceAccount):([^:?]+)$", member))
  ])

  secret_access_stack_principals = concat(
    [
      for key, config in local.app_services :
      try(config.cloudrun.external_sa, null) != null ? config.cloudrun.external_sa : format("%s-%s-sa@%s.iam.gserviceaccount.com", local.base_name, local.run_service_names[key], local.settings.project.id)
    ],
    [
      for key, job in try(local.settings.app.job, {}) :
      try(job.service_account.external, false) ? job.service_account.name : format("%s-%s-job-sa@%s.iam.gserviceaccount.com", local.base_name, try(job.name, key), local.settings.project.id)
    ],
    [
      format("run-cloudbuild-sa@%s.iam.gserviceaccount.com", local.settings.project.id),
      format("service-%s@gcp-sa-cloudbuild.iam.gserviceaccount.com", local.project_number),
    ],
    local.secret_access_yaml_readers,
  )

  secret_access_secrets = try(local.secret_access_settings.secrets, [])

  secret_access_alert = {
    filter = join(" AND ", concat(
      [
        "log_id(\"cloudaudit.googleapis.com/data_access\")",
        "protoPayload.serviceName=\"secretmanager.googleapis.com\"",
        "protoPayload.methodName=\"google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion\"",
      ],
      length(local.secret_access_secrets) == 0 ? [] : [
        format("protoPayload.resourceName:(%s)", join(" OR ", [for secret in local.secret_access_secrets : "\"/secrets/${secret}/versions/\""])),
      ],
    ))
    severity    = try(local.secret_access_settings.severity, "ERROR")
    description = "A secret version was read by a principal this stack does not expect."
    rate_limit  = try(local.secret_access_settings.notification_rate_limit, "300s")
    auto_close  = try(local.secret_access_settings.auto_close, "1800s")
    excluded = distinct(concat(
      try(local.secret_access_settings.exclude_stack_principals, true) ? local.secret_access_stack_principals : [],
      local.log_alert_excluded_principals,
      try(local.secret_access_settings.allowed_principals, []),
    ))
  }
}

resource "google_monitoring_alert_policy" "log_alerts" {
  for_each = local.log_alerts

  project      = local.settings.project.id
  display_name = "${local.base_name_medium}-log-${replace(each.key, "_", "-")}"
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = true

  conditions {
    display_name = each.key

    condition_matched_log {
      filter = length(each.value.excluded) == 0 ? each.value.filter : format(
        "(%s) AND NOT protoPayload.authenticationInfo.principalEmail=(%s)",
        each.value.filter,
        join(" OR ", [for principal in each.value.excluded : "\"${principal}\""]),
      )

      label_extractors = {
        principal = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
        method    = "EXTRACT(protoPayload.methodName)"
        resource  = "EXTRACT(protoPayload.resourceName)"
      }
    }
  }

  # A log match policy is rejected without a notification rate limit.
  alert_strategy {
    auto_close = each.value.auto_close

    notification_rate_limit {
      period = each.value.rate_limit
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "${each.value.description}\n\nPrincipal: $${log.extracted_label.principal}\n\nMethod: $${log.extracted_label.method}\n\nResource: $${log.extracted_label.resource}"
  }

  notification_channels = [google_monitoring_notification_channel.security_alerts.name]

  lifecycle {
    precondition {
      condition     = each.value.filter != null
      error_message = "monitoring.log_alerts.${each.key} is not a preset (${join(", ", keys(local.log_alert_presets))}), so it needs a filter."
    }
    precondition {
      condition     = !(each.key == "secret_access" && contains(keys(local.log_alerts_settings), "secret_access") && local.secret_access_enabled)
      error_message = "monitoring.log_alerts.secret_access clashes with the alert of monitoring.secret_access. Rename the log_alerts entry."
    }
    precondition {
      condition     = each.key != "secret_access" || alltrue([for secret in local.secret_access_secrets : can(regex("^[A-Za-z0-9_-]{1,255}$", secret))])
      error_message = "monitoring.secret_access.secrets takes secret ids (letters, digits, - and _), not resource names."
    }
    # Cloud Monitoring refuses a log match policy that notifies more often than
    # every 5 minutes or auto closes before 30 minutes, but only at apply.
    precondition {
      condition     = can(regex("^[0-9]+(\\.[0-9]+)?s$", each.value.rate_limit)) && try(tonumber(trimsuffix(each.value.rate_limit, "s")) >= 300, false)
      error_message = "The notification_rate_limit of the ${each.key} alert is ${each.value.rate_limit}: it takes seconds (\"300s\") and at least 300s."
    }
    precondition {
      condition     = can(regex("^[0-9]+(\\.[0-9]+)?s$", each.value.auto_close)) && try(tonumber(trimsuffix(each.value.auto_close, "s")) >= 1800, false)
      error_message = "The auto_close of the ${each.key} alert is ${each.value.auto_close}: it takes seconds (\"1800s\") and at least 1800s."
    }
    precondition {
      condition     = try(length(each.value.filter), 0) + 70 + length(join(" OR ", [for principal in each.value.excluded : "\"${principal}\""])) <= 20000
      error_message = "monitoring.log_alerts.${each.key}: the filter with its excluded principals is longer than the 20000 characters Cloud Logging accepts."
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# HTTPS uptime checks, driven by settings.monitoring.uptime: one check and one
# alert policy per entry. Without the key nothing is created.
#
# The host defaults to the first lb.domain. A check fails on any status code
# outside accepted_status_codes; it does not follow redirects. Behind IAP an
# anonymous request gets 302 (or 401), so either accept those codes, which
# proves the load balancer, certificate and IAP answer, or point the check at
# a path routed without IAP to prove the backend too.

locals {
  uptime_regions = ["ASIA_PACIFIC", "EUROPE", "SOUTH_AMERICA", "USA_IOWA", "USA_OREGON", "USA_VIRGINIA"]

  uptime_checks = {
    for name, check in try(local.settings.monitoring.uptime, {}) : name => {
      host            = try(check.host, try(local.settings.lb.domain[0], null))
      path            = try(check.path, "/")
      port            = try(check.port, 443)
      use_ssl         = try(check.use_ssl, true)
      period          = try(check.period, "300s")
      timeout         = try(check.timeout, "10s")
      regions         = try(check.regions, [])
      accepted        = [for code in try(check.accepted_status_codes, ["2xx"]) : lower(tostring(code))]
      content         = try(check.content_matcher.content, null)
      matcher         = try(check.content_matcher.matcher, "CONTAINS_STRING")
      failing_regions = try(check.failing_regions, 2)
      severity        = try(check.severity, "ERROR")
    } if try(check.enabled, true)
  }
}

resource "google_monitoring_uptime_check_config" "uptime" {
  for_each = local.uptime_checks

  project          = local.settings.project.id
  display_name     = "${local.base_name_medium}-uptime-${replace(each.key, "_", "-")}"
  period           = each.value.period
  timeout          = each.value.timeout
  selected_regions = length(each.value.regions) == 0 ? null : each.value.regions

  http_check {
    path           = each.value.path
    port           = each.value.port
    use_ssl        = each.value.use_ssl
    validate_ssl   = each.value.use_ssl
    request_method = "GET"

    dynamic "accepted_response_status_codes" {
      for_each = each.value.accepted

      content {
        status_class = can(regex("^[1-5]xx$", accepted_response_status_codes.value)) ? "STATUS_CLASS_${upper(accepted_response_status_codes.value)}" : null
        status_value = can(regex("^[1-5]xx$", accepted_response_status_codes.value)) ? null : try(tonumber(accepted_response_status_codes.value), null)
      }
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = local.settings.project.id
      host       = each.value.host
    }
  }

  dynamic "content_matchers" {
    for_each = each.value.content == null ? [] : [each.value.content]

    content {
      content = content_matchers.value
      matcher = each.value.matcher
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.host != null
      error_message = "monitoring.uptime.${each.key} needs a host, or lb.domain must list one."
    }
    precondition {
      condition     = contains(["60s", "300s", "600s", "900s"], each.value.period)
      error_message = "monitoring.uptime.${each.key}.period must be 60s, 300s, 600s or 900s."
    }
    precondition {
      condition     = can(regex("^[0-9]+s$", each.value.timeout)) && try(tonumber(trimsuffix(each.value.timeout, "s")) >= 1 && tonumber(trimsuffix(each.value.timeout, "s")) <= 60, false)
      error_message = "monitoring.uptime.${each.key}.timeout must be between 1s and 60s."
    }
    precondition {
      condition     = length(each.value.regions) == 0 || (length(each.value.regions) >= 3 && length(setsubtract(each.value.regions, local.uptime_regions)) == 0)
      error_message = "monitoring.uptime.${each.key}.regions must list at least three of ${join(", ", local.uptime_regions)}, or be omitted for all of them."
    }
    precondition {
      condition     = alltrue([for code in each.value.accepted : can(regex("^([1-5]xx|[1-5][0-9][0-9])$", code))])
      error_message = "monitoring.uptime.${each.key}.accepted_status_codes takes codes (302) or classes (2xx)."
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# Fires when at least failing_regions regions report the check as failed in
# the same window, so one flaky checker location does not page anyone.
# Alert policies on uptime metrics are not billed.
resource "google_monitoring_alert_policy" "uptime" {
  for_each = local.uptime_checks

  project      = local.settings.project.id
  display_name = "${local.base_name_medium}-uptime-${replace(each.key, "_", "-")}"
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = true

  conditions {
    display_name = "${each.value.host}${each.value.path} failing"

    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.uptime[each.key].uptime_check_id}\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.failing_regions - 1

      aggregations {
        alignment_period     = "${2 * tonumber(trimsuffix(each.value.period, "s"))}s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "The uptime check ${each.key} on ${each.value.use_ssl ? "https" : "http"}://${each.value.host}:${each.value.port}${each.value.path} failed from at least ${each.value.failing_regions} regions."
  }

  notification_channels = [google_monitoring_notification_channel.security_alerts.name]

  lifecycle {
    precondition {
      condition     = each.value.failing_regions >= 1 && each.value.failing_regions <= (length(each.value.regions) == 0 ? length(local.uptime_regions) : length(each.value.regions))
      error_message = "monitoring.uptime.${each.key}.failing_regions must be between 1 and the number of regions the check runs from."
    }
  }
}
