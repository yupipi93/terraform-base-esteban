# Workload Identity Federation for external CI (GitHub Actions, GitLab CI, any OIDC issuer).
# A pipeline exchanges its own OIDC token for a short-lived token of a service account, so
# no service account key is ever exported. Nothing here is created without `settings.wif`.
#
# Every provider must carry an attribute_condition. Without one, any token the issuer signs
# (any repository on github.com, for example) is accepted by the pool.

locals {
  wif_pools   = try(local.settings.wif.pools, {})
  wif_enabled = length(local.wif_pools) > 0

  wif_default_issuer = {
    github = "https://token.actions.githubusercontent.com"
    gitlab = "https://gitlab.com"
    oidc   = ""
  }

  # attribute.repository exists for every CI type so a binding's principal_set reads the same.
  wif_default_mapping = {
    github = {
      "google.subject"             = "assertion.sub"
      "attribute.actor"            = "assertion.actor"
      "attribute.repository"       = "assertion.repository"
      "attribute.repository_owner" = "assertion.repository_owner"
      "attribute.ref"              = "assertion.ref"
      "attribute.workflow_ref"     = "assertion.job_workflow_ref"
    }
    gitlab = {
      "google.subject"           = "assertion.sub"
      "attribute.actor"          = "assertion.user_login"
      "attribute.repository"     = "assertion.project_path"
      "attribute.namespace_path" = "assertion.namespace_path"
      "attribute.ref"            = "assertion.ref"
      "attribute.ref_type"       = "assertion.ref_type"
    }
    oidc = {
      "google.subject" = "assertion.sub"
    }
  }

  wif_providers = {
    for item in flatten([
      for pool_key, pool in local.wif_pools : [
        for provider_key, provider in try(pool.providers, {}) : {
          key                 = "${pool_key}/${provider_key}"
          pool_key            = pool_key
          provider_key        = provider_key
          type                = try(provider.type, "oidc")
          display_name        = try(provider.display_name, provider_key)
          issuer_uri          = try(provider.issuer_uri, local.wif_default_issuer[try(provider.type, "oidc")], "")
          allowed_audiences   = try(provider.allowed_audiences, [])
          attribute_mapping   = merge(try(local.wif_default_mapping[try(provider.type, "oidc")], {}), try(provider.attribute_mapping, {}))
          attribute_condition = try(trimspace(provider.attribute_condition), "")
        }
      ]
    ]) : item.key => item
  }

  # service_account is either an existing email or a key: a key creates <client.name>-<key>.
  wif_bindings = {
    for item in flatten([
      for pool_key, pool in local.wif_pools : [
        for binding in try(pool.bindings, []) : {
          key             = "${pool_key}/${binding.service_account}/${try(binding.principal_set, "")}"
          pool_key        = pool_key
          service_account = binding.service_account
          principal_set   = try(trimspace(binding.principal_set), "")
          roles           = try(binding.roles, [])
        }
      ]
    ]) : item.key => item
  }

  wif_service_accounts = toset([
    for binding in values(local.wif_bindings) : binding.service_account
    if !strcontains(binding.service_account, "@")
  ])

  wif_sa_email = {
    for sa in distinct([for binding in values(local.wif_bindings) : binding.service_account]) :
    sa => strcontains(sa, "@") ? sa : google_service_account.wif[sa].email
  }

  wif_role_grants = {
    for grant in distinct(flatten([
      for binding in values(local.wif_bindings) : [
        for role in binding.roles : {
          service_account = binding.service_account
          role            = role
        }
      ]
    ])) : "${grant.service_account}/${grant.role}" => grant
  }
}

# A deleted pool or provider id stays reserved for 30 days, so a key cannot be reused at once.
resource "google_iam_workload_identity_pool" "wif" {
  for_each = local.wif_pools

  project                   = local.settings.project.id
  workload_identity_pool_id = each.key
  display_name              = try(each.value.display_name, each.key)
  description               = try(each.value.description, "External CI federation (${each.key})")

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z0-9-]{4,32}$", each.key)) && !startswith(each.key, "gcp-")
      error_message = "wif.pools.${each.key}: a pool id is 4 to 32 lowercase letters, digits or hyphens and cannot start with gcp-."
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

resource "google_iam_workload_identity_pool_provider" "wif" {
  for_each = local.wif_providers

  project                            = local.settings.project.id
  workload_identity_pool_id          = google_iam_workload_identity_pool.wif[each.value.pool_key].workload_identity_pool_id
  workload_identity_pool_provider_id = each.value.provider_key
  display_name                       = each.value.display_name
  attribute_mapping                  = each.value.attribute_mapping
  attribute_condition                = each.value.attribute_condition

  oidc {
    issuer_uri        = each.value.issuer_uri
    allowed_audiences = each.value.allowed_audiences
  }

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z0-9-]{4,32}$", each.value.provider_key)) && !startswith(each.value.provider_key, "gcp-")
      error_message = "wif.pools.${each.value.pool_key}.providers.${each.value.provider_key}: a provider id is 4 to 32 lowercase letters, digits or hyphens and cannot start with gcp-."
    }
    precondition {
      condition     = contains(keys(local.wif_default_issuer), each.value.type)
      error_message = "wif.pools.${each.value.pool_key}.providers.${each.value.provider_key}.type must be github, gitlab or oidc."
    }
    precondition {
      condition     = each.value.attribute_condition != ""
      error_message = "wif.pools.${each.value.pool_key}.providers.${each.value.provider_key} has no attribute_condition, so any identity of the issuer could use the pool. Restrict it, for example: assertion.repository == 'example-org/example-repo'."
    }
    precondition {
      condition     = startswith(each.value.issuer_uri, "https://")
      error_message = "wif.pools.${each.value.pool_key}.providers.${each.value.provider_key} needs an https issuer_uri (mandatory for type oidc)."
    }
  }
}

resource "google_service_account" "wif" {
  for_each = local.wif_service_accounts

  project      = local.settings.project.id
  account_id   = "${local.base_name}-${each.key}"
  display_name = "External CI (${each.key})"
  description  = "Impersonated through Workload Identity Federation. Has no keys."

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", "${local.base_name}-${each.key}"))
      error_message = "Service account id ${local.base_name}-${each.key} must be 6 to 30 lowercase letters, digits or hyphens. Shorten the binding key."
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

resource "google_project_iam_member" "wif_roles" {
  for_each = local.wif_role_grants

  project = local.settings.project.id
  role    = each.value.role
  member  = "serviceAccount:${local.wif_sa_email[each.value.service_account]}"
}

# Lets the identities of the pool that match principal_set impersonate the service account.
# projects/- resolves the project from the email, so an existing account elsewhere works too.
resource "google_service_account_iam_member" "wif_workload_identity_user" {
  for_each = local.wif_bindings

  service_account_id = "projects/-/serviceAccounts/${local.wif_sa_email[each.value.service_account]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.wif[each.value.pool_key].name}/${each.value.principal_set}"

  lifecycle {
    precondition {
      condition     = each.value.principal_set != ""
      error_message = "A binding in wif.pools.${each.value.pool_key} for ${each.value.service_account} has no principal_set, for example attribute.repository/example-org/example-repo."
    }
  }
}
