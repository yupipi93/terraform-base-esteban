# =============================================================================
# CLOUD BUILD: one generic pipeline, everything else declared in YAML
# =============================================================================
# Every service, job and standalone build in this project renders the same file,
# `cloudbuild_files/cloudbuild.yaml`. That file knows nothing about any particular
# service: what differs between them is computed here from settings/<workspace>.yaml
# and injected as substitutions, and optional steps are selected by capability flags.
#
# Adding a build argument to an image is a line of YAML under
# `cloudbuild.build_args`, never an edit to the pipeline. See
# docs/cloudbuild-pipeline.md, and bin/cloudbuild-render.py to see what a given
# service actually builds with.

locals {
  # ---------------------------------------------------------------------------
  # The three places a build can be declared, normalised to one shape.
  #   raw: settings.cloudbuild.<key>                 (build only, no Cloud Run resource)
  #   app: settings.app.service.<key>.cloudbuild     (builds and deploys a service)
  #   job: settings.app.job.<key>.cloudbuild         (builds and updates a Cloud Run job)
  # `cb` is the cloudbuild block itself; the rest is context the block needs.
  # ---------------------------------------------------------------------------
  cloudbuild_sources = merge(
    {
      for key, value in local.raw_cloudbuild_configs : key => {
        cb          = value
        type        = "raw"
        name        = try(value.name, key)
        custom_name = try(value.custom_name, null)
        job_image   = null
      }
    },
    {
      for key, value in local.apps_with_cloudbuild : key => {
        cb          = value.cloudbuild
        type        = "app"
        name        = try(value.name, key)
        custom_name = try(value.custom_name, null)
        job_image   = null
      }
    },
    {
      for key, value in local.jobs_with_cloudbuild : key => {
        cb          = value.cloudbuild
        type        = "job"
        name        = try(value.name, key)
        custom_name = try(value.custom_name, null)
        # A job's image is declared once, in job-config, and read by gcp.jobs.tf. The
        # build pushes to that exact path so the job finds what the build produced.
        job_image = try(value["job-config"].image, null)
      }
    }
  )

  all_cloudbuild_configs = {
    for key, src in local.cloudbuild_sources : key => {
      type        = src.type
      name        = src.name
      custom_name = src.custom_name

      # ── where the code comes from ──
      repo_name          = src.cb.repo_name
      provider           = try(src.cb.provider, local.default_repo_provider)
      branch_pattern     = try(src.cb.branch_pattern, null)
      tag_pattern        = try(src.cb.tag_pattern, try(src.cb.branch_pattern, null) != null ? null : format("^%s-[0-9]{8}[0-9]{2}$", local.workspace))
      build_filter_paths = try(src.cb.build_filter_paths, null)

      # ── which pipeline runs ──
      # inline = true  → the pipeline is read from cloudbuild_files/ and stored in the
      #                  trigger, which is how this project builds everything.
      # inline = false → Cloud Build reads cloudbuild_file_path from the repository
      #                  itself, and none of the substitutions below apply unless that
      #                  file asks for them.
      inline               = try(src.cb.inline, false)
      cloudbuild_file_path = try(src.cb.cloudbuild_file_path, "cloudbuild.yaml")

      # ── what docker is told ──
      dockerfile_path    = try(src.cb.dockerfile_path, "Dockerfile")
      build_context_path = try(src.cb.build_context_path, ".")
      build_args         = try(src.cb.build_args, {})
      docker_target      = try(src.cb.docker_target, null)
      reqs_file          = try(src.cb.reqs_file, null)

      # ── how the build runs ──
      build_timeout         = try(src.cb.build_timeout, null)
      machine_type          = try(src.cb.machine_type, null)
      ar_token              = try(src.cb.artifact_registry_token, false)
      scan_secrets          = try(src.cb.scan.secrets, false) && !try(src.cb.scan.secrets_blocking, false)
      scan_secrets_blocking = try(src.cb.scan.secrets_blocking, false)
      scan_sast             = try(src.cb.scan.sast, false) && !try(src.cb.scan.sast_blocking, false)
      scan_sast_blocking    = try(src.cb.scan.sast_blocking, false)
      scan_deps             = try(src.cb.scan.deps, false) && !try(src.cb.scan.deps_blocking, false)
      scan_deps_blocking    = try(src.cb.scan.deps_blocking, false)

      # ── what the build rolls out ──
      # deploy: false builds and pushes without touching Cloud Run (base images,
      # libraries). job_name names a Cloud Run job that shares a service's image.
      deploy   = try(src.cb.deploy, true)
      job_name = try(src.cb.job_name, null)

      substitutions = try(src.cb.substitutions, {})

      # ── names ──
      prefixed_name = src.custom_name != null ? src.custom_name : format("%s-%s", local.base_name, src.name)
      raw_name      = src.custom_name != null ? src.custom_name : src.name

      # ── the image this build produces ──
      # An explicit `cloudbuild.image` wins; a job defaults to the image its job-config
      # declares (minus the tag), and everything else to <service-repo>/<service>.
      # A first segment containing a dot is already a registry host and is left alone.
      image = (
        try(src.cb.image, null) != null
        ? (length(regexall("\\.", split("/", src.cb.image)[0])) > 0 ? src.cb.image : "${local.registry_host}/${src.cb.image}")
        : src.type == "job" && src.job_image != null
        ? (length(regexall("\\.", split("/", src.job_image)[0])) > 0 ? split(":", src.job_image)[0] : "${local.registry_host}/${split(":", src.job_image)[0]}")
        : format("%s/%s/%s", local.registry_host,
          src.custom_name != null ? src.custom_name : format("%s-%s", local.base_name, src.name),
        src.custom_name != null ? src.custom_name : src.name)
      )

      # ── a base image pulled from this project's registries ──
      image_base = (
        try(src.cb.image_base, null) == null ? null :
        (
          length(regexall("\\.", split("/", src.cb.image_base)[0])) > 0 ?
          src.cb.image_base :
          "${length(regexall("/simple", src.cb.image_base)) > 0 ? local.registry_host_python : local.registry_host}/${src.cb.image_base}"
        )
      )
    }
  }

  # ---------------------------------------------------------------------------
  # Capability flags: what `x-when` in the pipeline is filtered against.
  # Derived, never a new boolean in settings when the answer is already there.
  # ---------------------------------------------------------------------------
  cloudbuild_capabilities = {
    for key, value in local.all_cloudbuild_configs : key => {
      ar_token              = value.ar_token
      scan_secrets          = value.scan_secrets
      scan_secrets_blocking = value.scan_secrets_blocking
      scan_sast             = value.scan_sast
      scan_sast_blocking    = value.scan_sast_blocking
      scan_deps             = value.scan_deps
      scan_deps_blocking    = value.scan_deps_blocking
      deploy_service        = value.type != "job" && value.deploy
      deploy_job            = value.type == "job" && value.deploy
      update_companion_job  = value.type != "job" && value.job_name != null
      # Every pushed image gets an attestation, deployed or not: a base image may be
      # run later, and the policy only admits signed digests.
      sign_image = local.enable_binary_auth
    }
  }

  # The Cloud Run job a build updates: its own, or the companion a service declares.
  cloudbuild_job_names = {
    for key, value in local.all_cloudbuild_configs : key =>
    value.type == "job" ? value.prefixed_name : value.job_name
  }

  # ---------------------------------------------------------------------------
  # Build arguments: the whole point of the refactor. Anything an image needs at
  # build time is a key under `cloudbuild.build_args` in the workspace YAML, and it
  # arrives as one deterministic, POSIX-quoted string.
  #
  # Single quotes stop bash expanding $, backticks, globs and whitespace; '\'' is the
  # standard close-escape-reopen for a value containing a quote. Cloud Build substitutes
  # once, so a value containing ${_FOO} is inserted verbatim and never re-expanded.
  # ---------------------------------------------------------------------------
  cloudbuild_build_args = {
    for key, value in local.all_cloudbuild_configs : key => merge(
      value.image_base == null ? {} : { IMAGE_BASE = value.image_base },
      value.reqs_file == null ? {} : { REQS_FILE = value.reqs_file },
      value.build_args
    )
  }

  cloudbuild_build_args_rendered = {
    for key, args in local.cloudbuild_build_args : key => join(" ", concat(
      # The token step wrote the file; only an image that asked for the token reads it.
      local.cloudbuild_capabilities[key].ar_token ? ["--build-arg GOOGLE_ACCESS_TOKEN=\"$(cat /workspace/access_token.txt)\""] : [],
      [
        for k in sort(keys(args)) :
        format("--build-arg %s='%s'", k, replace(args[k] == null ? "" : tostring(args[k]), "'", "'\\''"))
      ]
    ))
  }

  # ---------------------------------------------------------------------------
  # Substitutions. Cloud Build does not expand a substitution inside a substitution,
  # so every one of these is resolved here, in full, at plan time.
  # ---------------------------------------------------------------------------
  cloudbuild_substitutions = {
    for key, value in local.all_cloudbuild_configs : key => merge(
      # Who this build is. True whatever pipeline runs it.
      {
        _GCP_REGION         = local.settings.region_name
        _ENV                = local.workspace
        _RAW_NAME           = value.raw_name
        _PREFIXED_NAME      = value.prefixed_name
        _DOCKERFILE_PATH    = value.dockerfile_path
        _BUILD_CONTEXT_PATH = value.build_context_path
      },
      value.inline
      # The shared pipeline's own contract. Deliberately NOT sent to a pipeline this
      # repository cannot read: an external file may treat an unset substitution as a
      # signal (e.g. falling back to _IMAGE_BASE:SHORT_SHA when _IMAGE is empty),
      # and defining one here would silently change what it builds.
      ? merge(
        {
          _IMAGE         = value.image
          _BUILD_ARGS    = local.cloudbuild_build_args_rendered[key]
          _DOCKER_TARGET = value.docker_target == null ? "" : "--target=${value.docker_target}"
        },
        # Where the rollout lands. A service may sit outside the project's region
        # (three of them do, in us-east1); deploying it to region_name would create a
        # second service instead of updating the one that exists. Jobs are all created
        # in region_name by gcp.jobs.tf, so they say so separately.
        local.cloudbuild_capabilities[key].deploy_service ? { _DEPLOY_REGION = try(local.service_regions[key], local.settings.region_name) } : {},
        local.cloudbuild_job_names[key] == null ? {} : {
          _JOB_NAME   = local.cloudbuild_job_names[key]
          _JOB_REGION = local.settings.region_name
        },
        # Only with Binary Authorization on, so the sign-image step and its inputs
        # come and go together (gcp.binary_auth.tf).
        local.cloudbuild_capabilities[key].sign_image ? {
          _BINAUTH_ATTESTOR        = local.binauth_attestor
          _BINAUTH_KMS_KEY_VERSION = local.binauth_key_version
        } : {},
      )
      # What an external pipeline has always been handed, and nothing new.
      : {
        _PYTHON_REPO_URL  = "https://${local.registry_host_python}/${value.prefixed_name}/"
        _ARTIFACTS_BUCKET = "gs://${one(module.cloudbuild_artifacts_bucket[*].bucket_name)}/artifacts"
      },
      value.substitutions
    )
  }

  # ---------------------------------------------------------------------------
  # The pipeline, per service: decoded, filtered, and its dependencies rewritten.
  # ---------------------------------------------------------------------------
  cloudbuild_file_missing = {
    for key, value in local.all_cloudbuild_configs : key =>
    value.inline && !fileexists("${path.module}/cloudbuild_files/${value.cloudbuild_file_path}")
  }

  parsed_yaml_configs = {
    for key, value in local.all_cloudbuild_configs : key => (
      value.inline && !local.cloudbuild_file_missing[key]
      ? yamldecode(file("${path.module}/cloudbuild_files/${value.cloudbuild_file_path}"))
      : null
    )
  }

  # Indexing [key][flag] directly, not lookup(..., false): a mistyped x-when flag has to
  # be a plan error, not a step that silently never runs again.
  cloudbuild_steps = {
    for key, value in local.all_cloudbuild_configs : key => [
      for s in try(local.parsed_yaml_configs[key].steps, []) : s
      if alltrue([for f in try(s["x-when"], []) : local.cloudbuild_capabilities[key][f]])
    ]
  }

  cloudbuild_step_ids = {
    for key, steps in local.cloudbuild_steps : key => compact([for s in steps : try(s.id, "")])
  }

  # waitFor, rewritten for the steps that survived. "-" is never a step id, so it is kept
  # and "start immediately" survives. If nothing a step waited for survived, emit null
  # (= wait for everything before it) rather than ["-"]: null can only over-serialise,
  # while ["-"] could start a step before a dependency it genuinely needed.
  cloudbuild_wait_for = {
    for key, steps in local.cloudbuild_steps : key => [
      for s in steps : (
        try(s.waitFor, null) == null ? null :
        (
          length([for w in s.waitFor : w if w == "-" || contains(local.cloudbuild_step_ids[key], w)]) == 0
          ? null
          : [for w in s.waitFor : w if w == "-" || contains(local.cloudbuild_step_ids[key], w)]
        )
      )
    ]
  }

  # Secrets follow the steps that use them: a secretEnv with no availableSecrets entry is
  # a hard INVALID_ARGUMENT at apply time, and the reverse is dead configuration.
  cloudbuild_secret_envs = {
    for key, steps in local.cloudbuild_steps : key =>
    distinct(flatten([for s in steps : try(s.secretEnv, try(s.secret_env, []))]))
  }
}

resource "google_cloudbuild_trigger" "cloudbuild_triggers" {
  for_each = local.all_cloudbuild_configs

  project     = local.settings.project.id
  location    = local.settings.region_name
  name        = format("%s-%s", local.base_name, try(each.value.name, each.key))
  description = format("Cloud Build trigger for %s service in %s environment", try(each.value.name, each.key), local.workspace)

  included_files = each.value.build_filter_paths

  repository_event_config {
    repository = local.repo_id_map["${each.value.provider}/${each.value.repo_name}"]
    push {
      tag    = each.value.tag_pattern
      branch = each.value.branch_pattern
    }
  }

  lifecycle {
    precondition {
      condition     = !local.cloudbuild_file_missing[each.key]
      error_message = "cloudbuild_files/${each.value.cloudbuild_file_path} does not exist, and '${each.key}' is declared inline. Fix cloudbuild_file_path in settings/${local.workspace}.yaml."
    }

    # A newline in a build argument breaks the backslash-continued docker build command.
    precondition {
      condition     = !can(regex("\n", local.cloudbuild_build_args_rendered[each.key]))
      error_message = "A build_args value of '${each.key}' contains a newline, which would break the docker build command."
    }

    precondition {
      condition     = !each.value.inline || !(local.cloudbuild_capabilities[each.key].deploy_job || local.cloudbuild_capabilities[each.key].update_companion_job) || local.cloudbuild_job_names[each.key] != null
      error_message = "'${each.key}' updates a Cloud Run job but no job name could be resolved."
    }
  }

  # === DYNAMIC BUILD BLOCK ===
  # Inline builds: the pipeline is read from cloudbuild_files/ and stored in the trigger.
  dynamic "build" {
    for_each = each.value.inline ? [1] : []
    content {

      # 1. STEPS: only those whose x-when capabilities are on for this service.
      dynamic "step" {
        for_each = local.cloudbuild_steps[each.key]
        content {
          id            = try(step.value.id, null)
          name          = try(step.value.name, null)
          entrypoint    = try(step.value.entrypoint, null)
          script        = try(step.value.script, null)
          args          = try(step.value.args, null)
          wait_for      = local.cloudbuild_wait_for[each.key][step.key]
          dir           = try(step.value.dir, null)
          timeout       = try(step.value.timeout, null)
          env           = try(step.value.env, null)
          secret_env    = try(step.value.secretEnv, try(step.value.secret_env, null))
          allow_failure = try(step.value.allowFailure, try(step.value.allow_failure, null))

          dynamic "volumes" {
            for_each = try(step.value.volumes, [])
            content {
              name = volumes.value.name
              path = volumes.value.path
            }
          }
        }
      }

      # 2. GLOBAL SETTINGS: the YAML value is the default, settings may override it.
      timeout = coalesce(each.value.build_timeout, try(local.parsed_yaml_configs[each.key].timeout, "1800s"))
      tags    = try(local.parsed_yaml_configs[each.key].tags, [])
      images  = try(local.parsed_yaml_configs[each.key].images, [])

      # 3. OPTIONS
      dynamic "options" {
        for_each = try([local.parsed_yaml_configs[each.key].options], [])
        content {
          machine_type            = each.value.machine_type != null ? each.value.machine_type : try(options.value.machineType, try(options.value.machine_type, null))
          disk_size_gb            = try(options.value.diskSizeGb, try(options.value.disk_size_gb, null))
          logging                 = try(options.value.logging, null)
          env                     = try(options.value.env, null)
          secret_env              = try(options.value.secretEnv, null)
          worker_pool             = try(options.value.pool.name, try(options.value.pool, null))
          substitution_option     = try(options.value.substitutionOption, null)
          dynamic_substitutions   = try(options.value.dynamicSubstitutions, null)
          log_streaming_option    = try(options.value.logStreamingOption, null)
          requested_verify_option = try(options.value.requestedVerifyOption, null)

          dynamic "volumes" {
            for_each = try(options.value.volumes, [])
            content {
              name = volumes.value.name
              path = volumes.value.path
            }
          }
        }
      }

      # 4. ARTIFACTS
      dynamic "artifacts" {
        for_each = try([local.parsed_yaml_configs[each.key].artifacts], [])
        content {
          images = try(artifacts.value.images, null)

          dynamic "objects" {
            for_each = try([artifacts.value.objects], [])
            content {
              location = try(objects.value.location, null)
              paths    = try(objects.value.paths, [])
            }
          }

          dynamic "python_packages" {
            for_each = try([artifacts.value.pythonPackages], [])
            content {
              repository = python_packages.value.repository
              paths      = python_packages.value.paths
            }
          }
          dynamic "maven_artifacts" {
            for_each = try([artifacts.value.mavenArtifacts], [])
            content {
              repository  = maven_artifacts.value.repository
              path        = maven_artifacts.value.path
              artifact_id = try(maven_artifacts.value.artifactId, null)
              group_id    = try(maven_artifacts.value.groupId, null)
              version     = try(maven_artifacts.value.version, null)
            }
          }
        }
      }

      # 5. AVAILABLE SECRETS: narrowed to what the surviving steps consume.
      dynamic "available_secrets" {
        for_each = length(local.cloudbuild_secret_envs[each.key]) > 0 ? try([local.parsed_yaml_configs[each.key].availableSecrets], []) : []
        content {
          dynamic "secret_manager" {
            for_each = [
              for sm in try(available_secrets.value.secretManager, []) : sm
              if contains(local.cloudbuild_secret_envs[each.key], sm.env)
            ]
            content {
              version_name = secret_manager.value.versionName
              env          = secret_manager.value.env
            }
          }
        }
      }

      substitutions = local.cloudbuild_substitutions[each.key]
    }
  }

  # Non-inline: Cloud Build reads the file from the repository itself.
  filename = each.value.inline ? null : each.value.cloudbuild_file_path

  substitutions   = local.cloudbuild_substitutions[each.key]
  service_account = google_service_account.cloudbuild[0].id

  depends_on = [
    google_cloudbuildv2_repository.bitbucket,
    google_cloudbuildv2_repository.github,
    google_service_account.cloudbuild,
    module.artifact_registry,
    module.cloudbuild_artifacts_bucket
  ]
}


# The build account, the artifacts bucket and their grants exist only when something
# builds: a trigger (settings.cloudbuild, or a cloudbuild block under app.service or
# app.job), or a standalone repository that lists "cloudbuild" as a writer
# (gcp.artifact.standalone.tf). A workspace with neither gets none of them.
locals {
  cloudbuild_enabled    = length(local.all_cloudbuild_configs) > 0
  cloudbuild_sa_enabled = local.cloudbuild_enabled || length(local.standalone_artifact_legacy_writers) > 0
  cloudbuild_sa_email   = one(google_service_account.cloudbuild[*].email)
}

# Workspaces created before these were counted keep them: the address moves, nothing
# is destroyed. A workspace with no build then plans their removal.
moved {
  from = google_service_account.cloudbuild
  to   = google_service_account.cloudbuild[0]
}

moved {
  from = module.iam_member_permission_run_cloudbuild_sa
  to   = module.iam_member_permission_run_cloudbuild_sa[0]
}

moved {
  from = module.cloudbuild_artifacts_bucket
  to   = module.cloudbuild_artifacts_bucket[0]
}

# Service Account for Cloud Build
resource "google_service_account" "cloudbuild" {
  count = local.cloudbuild_sa_enabled ? 1 : 0

  project      = local.settings.project.id
  account_id   = "run-cloudbuild-sa"
  display_name = "Cloud Build Service Account for Run services"
}

# IAM permissions for Cloud Build Service Account using standardized module
module "iam_member_permission_run_cloudbuild_sa" {
  count  = local.cloudbuild_sa_enabled ? 1 : 0
  source = "./modules/gcp_project_iam_permissions_v2.0"

  project_id = local.settings.project.id
  permissions = [
    {
      members = [format("serviceAccount:%s", local.cloudbuild_sa_email)]
      roles = [
        "roles/cloudbuild.builds.builder",
        "roles/run.admin",
        "roles/iam.serviceAccountUser",
        "roles/artifactregistry.writer",
        "roles/logging.logWriter",
      ]
    }
  ]

  depends_on = [
    google_service_account.cloudbuild
  ]
}


# The build account may sign a JWT as itself (roles/iam.serviceAccountTokenCreator on its
# OWN resource, never project-wide: project-wide would let it act as every account in the
# project). Off unless a workspace sets `cloudbuild_sa_self_sign_jwt: true`. Useful for a
# build step that makes an IAP-authenticated check of a candidate revision.
resource "google_service_account_iam_member" "cloudbuild_self_sign" {
  count = local.cloudbuild_sa_enabled && try(local.settings.cloudbuild_sa_self_sign_jwt, false) ? 1 : 0

  service_account_id = google_service_account.cloudbuild[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = format("serviceAccount:%s", local.cloudbuild_sa_email)
}


# ===================================================================
# CLOUD BUILD ARTIFACTS BUCKET
# ===================================================================
# Created when the workspace has at least one Cloud Build trigger.
# It stores Python packages and build dependencies for Cloud Build.

# Admin members come from `cloudbuild_artifacts_admins` in the workspace yaml
# (e.g. ["group:cloud-admins@example.com"]). Empty by default.
locals {
  cloudbuild_artifacts_admins = try(local.settings.cloudbuild_artifacts_admins, [])
  cloudbuild_artifacts_permissions = length(local.cloudbuild_artifacts_admins) > 0 ? {
    admin = {
      members = local.cloudbuild_artifacts_admins
      roles   = ["roles/storage.admin"]
    }
  } : {}
}

module "cloudbuild_artifacts_bucket" {
  count  = local.cloudbuild_enabled ? 1 : 0
  source = "./modules/gcp_storage_v2.7"

  base_name      = "${local.base_name_medium}-cloudbuild-artifacts"
  region_name    = local.settings.region_name
  gcp_project_id = local.settings.project.id

  class                          = "REGIONAL"
  force_destroy                  = false
  enable_versioning              = false
  uniform_bucket_level_access    = true
  authoritative_permissions      = false
  soft_delete_retention_duration = 7 * 86400 # 7 days in seconds

  lifecycle_rules = {}
  permissions     = local.cloudbuild_artifacts_permissions
  cors            = []
  website         = null
}
