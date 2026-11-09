# Standalone Artifact Registry repositories
#
# The per-service repositories live in gcp.artifact.tf, one per entry in
# `app.service`. That is the right shape for a service that builds its own image, and
# the wrong one for a Cloud Run *job* that belongs to no service: operational work with no
# web front end, whose images still need somewhere to live.
#
# Declared flat in the workspace yaml under `artifact_repos:`, mirroring the
# `secrets:` convention in gcp.secrets.standalone.tf:
#
#   artifact_repos:
#     house-jobs:
#       description: "Images for the scheduled operational jobs"
#       writers:
#         - "cloudbuild"          # shorthand for the project's Cloud Build SAs
#         - "serviceAccount:..."  # or any literal IAM member
#
# Absent from a workspace, `try(..., {})` makes the whole file a no-op; the other two
# workspaces are unaffected.
#
# Also the home of repositories made by hand (or by Cloud Functions / `gcloud run deploy
# --source`) that terraform ADOPTS so they get the cleanup policy of gcp.artifact.tf:
#
#     legacy-images-us-east1:
#       adopt: true                       # import it; never recreated
#       repository_id: "legacy-images"    # when the key cannot be the real id
#       location: "us-east1"              # default: the workspace region
#       description: "..."                # only if it has one today
#       immutable_tags: false             # only if it has a docker_config today
#
# An adopted repository keeps its description and its own labels: the import must declare
# what is there. The plan shows the cleanup policy and, in place, the provider default
# labels (common_labels, providers.tf) added next to the labels it has. Removing an adopted
# entry from the yaml plans a DESTROY of the repository and every image in it. The apply
# procedure stops on destroys; take it out of state with a `removed` block instead.

locals {
  standalone_artifact_repos = try(local.settings.artifact_repos, {})

  standalone_artifact_writers = {
    for pair in flatten([
      for repo_id, repo in local.standalone_artifact_repos : [
        for member in try(repo.writers, []) : {
          key     = "${repo_id}/${member}"
          repo_id = repo_id
          member = (
            member == "cloudbuild"
            ? "serviceAccount:${local.cloudbuild_sa_email}"
            : member
          )
        }
      ]
    ]) : pair.key => pair
  }

  # The legacy @cloudbuild.gserviceaccount.com agent, which the per-service module also
  # grants. Kept separate so a repo asking for "cloudbuild" gets both identities and a
  # build does not fail on whichever one Cloud Build happens to pick.
  standalone_artifact_legacy_writers = {
    for repo_id, repo in local.standalone_artifact_repos : repo_id => repo
    if contains(try(repo.writers, []), "cloudbuild")
  }
}

resource "google_artifact_registry_repository" "standalone" {
  for_each = local.standalone_artifact_repos

  project       = local.settings.project.id
  location      = try(each.value.location, local.settings.region_name)
  repository_id = try(each.value.repository_id, each.key)
  description   = try(each.value.description, try(each.value.adopt, false) ? null : "Managed by terraform")
  format        = try(each.value.format, "DOCKER")

  labels = try(each.value.adopt, false) ? {} : local.common_labels

  # Declared only when the yaml says so: an adopted repository that has the block must
  # keep it, or the plan never converges.
  dynamic "docker_config" {
    for_each = try([each.value.immutable_tags], [])
    content {
      immutable_tags = docker_config.value
    }
  }

  cleanup_policy_dry_run = local.artifact_cleanup_cfg["repo/${each.key}"].dry_run

  dynamic "cleanup_policies" {
    for_each = local.artifact_cleanup_policies["repo/${each.key}"]
    content {
      id     = cleanup_policies.key
      action = cleanup_policies.value.action

      dynamic "condition" {
        for_each = cleanup_policies.value.condition[*]
        content {
          tag_state    = condition.value.tag_state
          tag_prefixes = condition.value.tag_prefixes
          older_than   = condition.value.older_than
        }
      }

      dynamic "most_recent_versions" {
        for_each = cleanup_policies.value.most_recent_versions[*]
        content {
          keep_count = most_recent_versions.value.keep_count
        }
      }
    }
  }

  depends_on = [
    google_project_service.enabled_apis
  ]
}

import {
  for_each = { for k, r in local.standalone_artifact_repos : k => r if try(r.adopt, false) }
  to       = google_artifact_registry_repository.standalone[each.key]
  id = format("projects/%s/locations/%s/repositories/%s", local.settings.project.id,
  try(each.value.location, local.settings.region_name), try(each.value.repository_id, each.key))
}

resource "google_artifact_registry_repository_iam_member" "standalone_writers" {
  for_each = local.standalone_artifact_writers

  project    = local.settings.project.id
  location   = google_artifact_registry_repository.standalone[each.value.repo_id].location
  repository = google_artifact_registry_repository.standalone[each.value.repo_id].name
  role       = "roles/artifactregistry.writer"
  member     = each.value.member
}

resource "google_artifact_registry_repository_iam_member" "standalone_legacy_cloudbuild" {
  for_each = local.standalone_artifact_legacy_writers

  project    = local.settings.project.id
  location   = google_artifact_registry_repository.standalone[each.key].location
  repository = google_artifact_registry_repository.standalone[each.key].name
  role       = "roles/artifactregistry.writer"
  member     = format("serviceAccount:%s@cloudbuild.gserviceaccount.com", local.project_number)
}

# Readers: Cloud Run pulls as the job's own service account, and those are created in
# gcp.jobs.tf. Rather than enumerate them, grant the project's default compute and run
# agents plus any explicit reader, the same posture the per-service module takes.
resource "google_artifact_registry_repository_iam_member" "standalone_readers" {
  for_each = {
    for pair in flatten([
      for repo_id, repo in local.standalone_artifact_repos : [
        for member in try(repo.readers, []) : {
          key = "${repo_id}/${member}", repo_id = repo_id, member = member
        }
      ]
    ]) : pair.key => pair
  }

  project    = local.settings.project.id
  location   = google_artifact_registry_repository.standalone[each.value.repo_id].location
  repository = google_artifact_registry_repository.standalone[each.value.repo_id].name
  role       = "roles/artifactregistry.reader"
  member     = each.value.member
}

# ===================================================================
# AN EXTERNAL BUILD IDENTITY CAN SUBMIT BUILDS FOR THESE IMAGES
# ===================================================================
# Optional. When a workspace sets `build_submitter: "serviceAccount:..."` (an identity that
# already exists, for example a CI runner or an operations machine), it gets what a
# `gcloud builds submit` needs, and nothing more:
#
#   cloudbuild.builds.editor  submit a build and read its result. NOT builds.approver:
#                             it cannot release anything gated on human approval.
#   serviceUsageConsumer      billing for the staging-bucket calls lands on the calling
#                             project.
#   storage.bucketViewer      `gcloud builds submit` calls CreateBucketIfNotExists, which is a
#                             `buckets.list` ON THE PROJECT, not a get on the bucket. The
#                             error it raises otherwise names the wrong resource and the
#                             wrong permission; `--verbosity=debug` shows the real one:
#                               403 storage.buckets.list denied on resource
#   storage.objectAdmin on    `gcloud builds submit` uploads the source context there
#   the _cloudbuild bucket    first. Scoped to that one bucket, not the project.
#   artifactregistry.writer   push the result. Granted per repository via the `writers`
#                             list in the workspace yaml, not here.
#
# What it still cannot do: deploy. Creating or updating the Cloud Run job stays a
# terraform apply. Build and deploy are deliberately different privileges.
# Gated on a repository that names writers, not on any repository existing.
locals {
  build_submitter        = try(local.settings.build_submitter, "")
  build_submitter_builds = local.build_submitter != "" && length([for k, r in local.standalone_artifact_repos : k if length(try(r.writers, [])) > 0]) > 0
  # Resolved per role so the provider's static member check only sees a real value.
  build_submitter_members = local.build_submitter_builds ? {
    "roles/cloudbuild.builds.editor"          = local.build_submitter
    "roles/serviceusage.serviceUsageConsumer" = local.build_submitter
    "roles/storage.bucketViewer"              = local.build_submitter
    "roles/storage.objectAdmin"               = local.build_submitter
  } : {}
}

resource "google_project_iam_member" "build_submitter" {
  for_each = local.build_submitter_builds ? toset([
    "roles/cloudbuild.builds.editor",
    "roles/serviceusage.serviceUsageConsumer",
    # bucketViewer, not storage.admin: it grants buckets.get and buckets.list and NOTHING
    # about objects. Objects are readable or writable only in the one bucket granted below.
    "roles/storage.bucketViewer",
  ]) : toset([])

  project = local.settings.project.id
  role    = each.value
  member  = local.build_submitter_members[each.value]
}

# The staging bucket `gcloud builds submit` uploads the source tarball to. It is created
# by Cloud Build itself on first use, so this is a binding on a bucket terraform does not
# own: deliberate, and the reason it is a `google_storage_bucket_iam_member` on a literal
# name rather than a reference.
resource "google_storage_bucket_iam_member" "build_submitter_staging" {
  for_each = local.build_submitter_builds ? toset([
    "roles/storage.objectAdmin",
  ]) : toset([])

  bucket = "${local.settings.project.id}_cloudbuild"
  role   = each.value
  member = local.build_submitter_members[each.value]
}
