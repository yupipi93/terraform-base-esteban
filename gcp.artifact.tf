# ===================================================================
# CLEANUP POLICY: every repository, both kinds
# ===================================================================
# Observed in practice: the module's default ("keep 5, delete untagged") with
# cleanup_policy_dry_run = true deletes NOTHING. And "untagged" barely matches anyway
# when the pipeline tags every image with its commit SHA, so storage piles up with
# builds nobody runs.
#
# A version is deleted when the DELETE policy matches and no KEEP policy does:
#   KEEP   the `keep_count` most recent versions of each image (package)
#   KEEP   anything carrying a tag in `keep_tags` (e.g. jobs that run `<image>:latest`)
#   DELETE everything else older than `delete_older_than`. The grace window covers the gap
#          between a push and its deploy, so a burst of failed deploys cannot push the
#          running image out of the newest two.
#
# Artifact Registry knows nothing about Cloud Run: a job pinned to an old tag is deleted
# like any stale build. `bin/ar-cleanup-check.py` lists everything Cloud Run runs and fails
# if the policy would delete any of it, or if it is already gone. Run it before changing
# these numbers (`--policy` simulates) and after the first cleanup.
#
# Override per workspace with `artifact_cleanup:` in settings/<ws>.yaml, per service or
# standalone repo with `artifact_cleanup:` on its entry. Same keys as below.
#
# PROVIDER TRAP (observed with google provider 6.42): an apply that REMOVES a policy whose
# block has a `condition` fails with `Error 400: invalid cleanup policy: policy  is missing
# a condition`: the SDK leaves a blank element in the set (note the empty name). Adding
# and changing policies works; the API itself accepts the removal. So renaming a policy id
# here fails on every repository: delete the old id first with
#   gcloud artifacts repositories delete-cleanup-policies <repo> --policynames=<old-id>
# and then apply. The same applies when retiring the module's default keep-5/untagged pair.
locals {
  artifact_cleanup = merge({
    keep_count        = 2
    keep_tags         = ["latest"]
    delete_older_than = "86400s"
    dry_run           = false
  }, try(local.settings.artifact_cleanup, {}))

  artifact_cleanup_cfg = merge(
    { for k, s in local.app_services : "svc/${k}" => merge(local.artifact_cleanup, try(s.artifact_cleanup, {})) },
    { for k, r in try(local.settings.artifact_repos, {}) : "repo/${k}" => merge(local.artifact_cleanup, try(r.artifact_cleanup, {})) },
  )

  # Every entry has the same attributes (nulls where unused) so the map type unifies and a
  # `dynamic` block can iterate it.
  artifact_cleanup_policies = {
    for k, c in local.artifact_cleanup_cfg : k => merge(
      {
        "keep-most-recent" = {
          action               = "KEEP"
          condition            = null
          most_recent_versions = { keep_count = c.keep_count, package_name_prefixes = null }
        }
        "delete-everything-else" = {
          action               = "DELETE"
          condition            = { tag_state = "ANY", tag_prefixes = null, older_than = c.delete_older_than }
          most_recent_versions = null
        }
      },
      # TAGGED with an empty prefix list would keep every tagged version, i.e. everything.
      length(c.keep_tags) == 0 ? {} : {
        "keep-tags" = {
          action               = "KEEP"
          condition            = { tag_state = "TAGGED", tag_prefixes = c.keep_tags, older_than = null }
          most_recent_versions = null
        }
      },
    )
  }
}

# Artifact Registry for each Cloud Run service
module "artifact_registry" {
  for_each = local.app_services

  source = "./modules/gcp_artifactregistry_v2.1"

  gcp_project_id = local.settings.project.id
  base_name      = try(each.value.custom_name, null) != null ? each.value.custom_name : format("%s-%s", local.base_name, try(each.value.name, each.key))
  region_name    = local.settings.region_name

  permissions = {
    cloudbuild = {
      members = concat(
        [format("serviceAccount:%s@cloudbuild.gserviceaccount.com", local.project_number)],
        local.cloudbuild_sa_enabled ? [format("serviceAccount:%s", local.cloudbuild_sa_email)] : []
      )
      roles = [
        "roles/artifactregistry.reader",
        "roles/artifactregistry.writer",
      ]
    }
  }

  format = "DOCKER"

  cleanup_policies       = local.artifact_cleanup_policies["svc/${each.key}"]
  cleanup_policy_dry_run = local.artifact_cleanup_cfg["svc/${each.key}"].dry_run

  depends_on = [
    google_service_account.cloudbuild
  ]
}
