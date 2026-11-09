# Settings that used to fail late (at the API) or silently (nothing created)
# must stop the plan. No reference file holds such a value, so each run
# merges it over a workspace file with settings_override (locals.tf).

mock_provider "google" {}
mock_provider "google" {
  alias = "unlabelled"
}
mock_provider "google-beta" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "sops" {}
mock_provider "archive" {}
mock_provider "oci" {}

variables {
  elastic_psc = {
    service_attachment = "projects/example-provider-project/regions/europe-west1/serviceAttachments/example-attachment"
  }
}

run "elastic_psc_without_network_is_refused" {
  command = plan

  variables {
    settings_override = {
      elastic_psc = var.elastic_psc
    }
  }

  expect_failures = [
    check.settings_workspace_unset,
    google_compute_address.elastic_psc_address,
  ]
}

run "elastic_psc_with_network_plans" {
  command = plan

  variables {
    settings_workspace = "dev"
    settings_override = {
      elastic_psc = var.elastic_psc
    }
  }

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition     = local.network_enabled && length(google_compute_address.elastic_psc_address) == 1 && length(google_compute_forwarding_rule.elastic_psc_endpoint) == 1
    error_message = "With the shared VPC, elastic_psc creates its address and endpoint (positive control)."
  }
}

run "log_alert_rate_limit_under_300s_is_refused" {
  command = plan

  variables {
    settings_override = {
      monitoring = {
        log_alerts = {
          firewall_change = {
            notification_rate_limit = "60s"
          }
        }
      }
    }
  }

  expect_failures = [
    check.settings_workspace_unset,
    google_monitoring_alert_policy.log_alerts,
  ]
}

run "log_alert_auto_close_under_1800s_is_refused" {
  command = plan

  variables {
    settings_override = {
      monitoring = {
        log_alerts = {
          firewall_change = {
            auto_close = "600s"
          }
        }
      }
    }
  }

  expect_failures = [
    check.settings_workspace_unset,
    google_monitoring_alert_policy.log_alerts,
  ]
}

run "secret_access_duration_without_unit_is_refused" {
  command = plan

  variables {
    settings_override = {
      monitoring = {
        secret_access = {
          notification_rate_limit = "5m"
        }
      }
    }
  }

  expect_failures = [
    check.settings_workspace_unset,
    google_monitoring_alert_policy.log_alerts,
  ]
}

run "log_alert_durations_at_the_minimum_plan" {
  command = plan

  variables {
    settings_override = {
      monitoring = {
        log_alerts = {
          firewall_change = {
            notification_rate_limit = "300s"
            auto_close              = "1800s"
          }
          custom_role_change = {
            notification_rate_limit = "3600s"
            auto_close              = "604800s"
          }
        }
      }
    }
  }

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition = (
      google_monitoring_alert_policy.log_alerts["firewall_change"].alert_strategy[0].notification_rate_limit[0].period == "300s"
      && google_monitoring_alert_policy.log_alerts["firewall_change"].alert_strategy[0].auto_close == "1800s"
      && length(google_monitoring_alert_policy.log_alerts) == 2
    )
    error_message = "300s and 1800s are accepted (positive control for the two refusals)."
  }
}

run "disable_service_account_keys_not_a_bool_is_refused" {
  command = plan

  variables {
    settings_override = {
      security = {
        alerts_email                 = "replace-me@example.com"
        disable_service_account_keys = "yes"
      }
    }
  }

  expect_failures = [
    check.settings_workspace_unset,
    google_monitoring_notification_channel.security_alerts,
  ]
}

run "essential_contacts_true_uses_alerts_email" {
  command = plan

  variables {
    settings_override = {
      security = {
        alerts_email       = "Replace-Me@example.com"
        essential_contacts = true
      }
    }
  }

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition = (
      keys(google_essential_contacts_contact.contacts) == ["replace-me@example.com"]
      && google_essential_contacts_contact.contacts["replace-me@example.com"].notification_category_subscriptions == tolist(["SECURITY", "TECHNICAL"])
      && google_essential_contacts_contact.contacts["replace-me@example.com"].language_tag == "en"
    )
    error_message = "essential_contacts: true creates one contact for alerts_email on SECURITY and TECHNICAL (positive control)."
  }
}

run "essential_contacts_unknown_category_is_refused" {
  command = plan

  variables {
    settings_override = {
      security = {
        alerts_email       = "replace-me@example.com"
        essential_contacts = [{ email = "replace-me@example.com", categories = ["SECURITY", "OUTAGES"] }]
      }
    }
  }

  expect_failures = [
    check.settings_workspace_unset,
    google_essential_contacts_contact.contacts,
  ]
}

run "essential_contacts_not_a_list_is_refused" {
  command = plan

  variables {
    settings_override = {
      security = {
        alerts_email       = "replace-me@example.com"
        essential_contacts = "replace-me@example.com"
      }
    }
  }

  expect_failures = [
    check.settings_workspace_unset,
    google_monitoring_notification_channel.security_alerts,
  ]
}
