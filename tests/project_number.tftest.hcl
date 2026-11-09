# project.number comes from the YAML when it holds a real number, and from
# data.google_project.current when it is left out or at the all-zero
# placeholder of the reference files. The mock provider returns the number
# set in override_data, so each run can tell which source was used.

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

override_data {
  target = data.google_project.current
  values = {
    number = "123456789012"
  }
}

variables {
  settings_workspace = "pro"
}

run "number_left_out_is_read_from_the_project" {
  command = plan

  variables {
    settings_override = {
      project = { id = "example-app-pro", name = "example-app-pro" }
    }
  }

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition     = length(data.google_project.current) == 1 && local.project_number == "123456789012"
    error_message = "Without project.number the number is read from the project."
  }

  assert {
    condition = (
      google_secret_manager_secret_iam_binding.github_token[0].members == toset(["serviceAccount:service-123456789012@gcp-sa-cloudbuild.iam.gserviceaccount.com"])
      && contains(local.secret_access_stack_principals, "service-123456789012@gcp-sa-cloudbuild.iam.gserviceaccount.com")
    )
    error_message = "The Cloud Build service agent is built from the number read from the project."
  }
}

run "placeholder_number_is_read_from_the_project" {
  command = plan

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition     = local.settings.project.number == "000000000000" && length(data.google_project.current) == 1 && local.project_number == "123456789012"
    error_message = "The all-zero placeholder of settings/pro.yaml does not override the real number."
  }
}

run "yaml_number_wins" {
  command = plan

  variables {
    settings_override = {
      project = { id = "example-app-pro", name = "example-app-pro", number = 234567890123 }
    }
  }

  expect_failures = [check.settings_workspace_unset]

  assert {
    condition     = length(data.google_project.current) == 0 && local.project_number == "234567890123"
    error_message = "A real project.number, string or integer, is used as is and nothing is read."
  }
}

run "malformed_number_is_refused" {
  command = plan

  variables {
    settings_override = {
      project = { id = "example-app-pro", name = "example-app-pro", number = "1234-5678" }
    }
  }

  expect_failures = [
    check.settings_workspace_unset,
    data.google_project.current,
  ]
}
