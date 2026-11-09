# Cloud Build triggers: tag and branch patterns

Every build declared in the settings gets one Cloud Build trigger that fires on a
push to its repository. This page covers what decides which push starts it.

## Where triggers come from

Terraform creates them as `google_cloudbuild_trigger.cloudbuild_triggers` in
`gcp.cloudbuild.tf`, one per entry of `local.all_cloudbuild_configs`. An entry is a
`cloudbuild` block under `app.service.<name>` or `app.job.<name>`, or an entry of
the top-level `cloudbuild` map (a build with no Cloud Run resource), in
`settings/<workspace>.yaml`. The repository is on GitHub or Bitbucket, reached
through the connection in `gcp.repository.connection.tf`: `cloudbuild.provider`
picks one, and `repo_providers.default` (default `github`) applies when it is
left out.

## The default: a tag named after the workspace

With neither `tag_pattern` nor `branch_pattern` set, the trigger fires on a tag
that starts with the workspace name and carries ten digits:

```hcl
tag_pattern = try(src.cb.tag_pattern, try(src.cb.branch_pattern, null) != null ? null : format("^%s-[0-9]{8}[0-9]{2}$", local.workspace))
```

`local.workspace` is the Terraform workspace, or `settings_workspace` in a test
(`docs/audit/OPERATING.md`, "Tests"). The ten digits read as `YYYYMMDDNN`, a date
and a two-digit counter:

| Workspace | Pattern | Tag that fires it |
|---|---|---|
| `dev` | `^dev-[0-9]{8}[0-9]{2}$` | `dev-2026010101` |
| `stg` | `^stg-[0-9]{8}[0-9]{2}$` | `stg-2026010101` |
| `pro` | `^pro-[0-9]{8}[0-9]{2}$` | `pro-2026010101` |

## Overriding it

Set one of the two keys in the `cloudbuild` block:

- `tag_pattern`: another tag regular expression.
- `branch_pattern`: fire on a push to a matching branch instead. When it is set and
  `tag_pattern` is not, the trigger has no tag pattern at all.

```yaml
app:
  service:
    web:
      name: "web"
      cloudbuild:
        repo_name: "example-web"
        provider: "github"          # optional, default repo_providers.default
        tag_pattern: "^release-v[0-9]+\\.[0-9]+\\.[0-9]+$"
```

That trigger fires on `release-v1.0.0` and `release-v2.1.5`. The reference files
use both forms: dev and stg (and pre) set `branch_pattern: "^main$"` and deploy
every push to `main`; pro keeps the default and deploys on a `pro-` tag.

`build_filter_paths` limits a trigger to pushes that change those paths. It
only makes sense with a branch pattern, since a tag carries no diff.

## The trigger resource

```hcl
resource "google_cloudbuild_trigger" "cloudbuild_triggers" {
  for_each = local.all_cloudbuild_configs

  # ...

  repository_event_config {
    repository = local.repo_id_map["${each.value.provider}/${each.value.repo_name}"]
    push {
      tag    = each.value.tag_pattern
      branch = each.value.branch_pattern
    }
  }
}
```

The defaults and the merge of the three places a build can be declared live in
the `locals` block at the top of `gcp.cloudbuild.tf`. `docs/cloudbuild-pipeline.md`
lists every other key of the block.

## Changing a pattern

1. Edit `settings/<workspace>.yaml`.
2. Run `terraform plan`. The trigger is updated in place.
3. Apply after the plan is reviewed and approved.

## Starting a build

Push a tag that matches the pattern to the configured repository:

```bash
git tag pro-2026010101
git push origin pro-2026010101
```

Cloud Build picks the push up and runs the pipeline. With a branch pattern, a
push to the branch is enough.
