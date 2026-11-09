# How to change this Terraform

The backlog in `BACKLOG.md` is the list of work. `bin/audit-terraform.py`
decides which items are still open by reading the code. Edit the script when
you add a check. Do not tick a box by hand.

## The audit loop

The backlog is worked by a loop with three separate roles. One person or agent
can play several roles, but never worker and verifier for the same item.

1. **Auditor.** Reads the whole repository (Terraform, YAML, file and module
   names, docs, every comment) and looks for gaps against the two goals: dev
   and stg cheap, pro ready for a security, backup and data-retention audit.
   Every finding becomes an `Item` in `bin/audit-terraform.py` with a check
   that fails today. A finding that is a deliberate choice becomes an
   `accepted` item instead, with the reason.
2. **Worker.** Takes the item `python3 bin/audit-terraform.py --next` prints,
   changes only what that item needs, and opens one pull request.
3. **Verifier.** Reads the diff against the item text, not the worker's
   summary, runs the checks below, and sends the item back when the check
   passes for the wrong reason (a string added to a comment, a setting nobody
   reads).

When `--next` prints `nothing left`, the auditor runs again. The loop stops
when a full audit adds no new item.

## One item, one pull request

1. Run `python3 bin/audit-terraform.py --next`.
2. Branch: `<type>/<id-lower>-<short-slug>`, for example
   `fix/aud-sql-pitr-wire-backup`.
3. Change only that item. A drive-by edit belongs in its own item.
4. Run the auditor again. The item you took must say `done`
   (`python3 bin/audit-terraform.py --id <ID>` exits 0). Then
   `python3 bin/audit-terraform.py --write` and commit the refreshed
   `docs/audit/BACKLOG.md` in the same pull request.
5. If you touched `.tf` files: `terraform fmt` on those files,
   `terraform init -backend=false`, `terraform validate`, and the same
   validate in the `dev`, `stg` and `pro` workspaces (a local backend
   override, `*_override.tf`, is gitignored).
6. CI repeats part of this on the pull request: `terraform fmt -check`,
   `tflint` on the root module, `terraform validate` in `default`, `dev`,
   `stg`, `pre` and `pro`, `terraform test`,
   `python3 bin/cloudbuild-render-test.py`,
   `python3 bin/validate-settings.py` and
   `python3 bin/audit-terraform.py --fail-on p0`. A key you add to the
   settings goes into `schemas/settings.schema.json` and
   `settings/example.yaml` in the same pull request. It does not run
   `--id <ID>` or `--leaks`; run those yourself.
7. Open the pull request with a Summary, the list of changes, how you
   validated, and how to roll it back. Do not apply.

`terraform apply` and `terraform destroy` wait for an explicit yes for that
plan, in that workspace. A pull request is not that yes.

## The two profiles

`settings/dev.yaml`, `settings/stg.yaml` and `settings/pro.yaml` are the
reference workspaces. `settings/pre.yaml` is the older name for the stg shape
and stays. Dev and stg are small, zonal and scale to zero. Pro is regional,
warm, protected against an accidental delete, and keeps the logs and backups
an audit asks for. They use placeholders (`example-app-dev`,
`example-app-stg`, `example-app-pro`, `replace-me@example.com`). Planning
them against a real project comes after those values are replaced. Applying
them is a separate decision. The difference is `docs/ENVIRONMENTS.md`.

Secret values never go in YAML or in HCL. The stack creates the secret and a
placeholder version. The payload is added with `gcloud secrets versions add`,
or through the SOPS path in `docs/SOPS.md`.

## Generic by design

This repository is public. Tracked files name no company, client, product or
person, and carry no real email, project id or billing id. `AUD-PUB-LEAKS`
scans for real-looking emails, and for any extra terms listed one regular
expression per line in a gitignored `.audit-denylist` (or the file named by
`AUDIT_DENYLIST`). A fork that was cut from a private stack lists that
stack's names there.

## Settings merge

`locals.tf` merges the workspace file over `settings/default.yaml` with
`merge()`. A map in the workspace file replaces the whole map. Do not set
`active-apis` in an environment file. Add an API to `default.yaml` when
every workspace needs it, to `local.feature_apis` in `gcp.enabled.apis.tf`
when one feature needs it, and to the workspace's `extra-apis` otherwise.

## Vendored modules

`modules/*` are snapshots. The directory is the module name plus its version,
`modules/gcp_<name>_v<major.minor>` (`modules/gcp_cloudsql_v7.5`), with no build
timestamp. Do not edit a module in place: copy it to a directory with the next
version (`gcp_cloudsql_v7.6`, or the next major for a breaking change), edit the
copy, point every `source` at it, and delete the old directory once nothing
references it. Only the versions a root file uses are kept. The one exception is a
comment or documentation fix (a translation, a typo) that changes no argument,
default or expression: it may be made in place, because a new directory would only
churn every `source` for nothing.

Renaming a module directory changes its `source` only. The module address in state
is the block name (`module.cloud_sql`), so the rename needs `terraform init` and
leaves the plan empty.

## File names

Root files are `gcp.<type>.tf` or `gcp.<type>.<part>.tf` (`oracle.` for the OCI
side): dots between levels, underscores inside a word
(`gcp.cloudrun.domain_mappings.tf`, `gcp.compute.nat.tf`), no hyphens. Only
`locals.tf`, `providers.tf`, `versions.tf` and `outputs.tf` sit outside the pattern.
`AUD-NAMES` checks both conventions.

## Tests

`tests/*.tftest.hcl` plan the reference shapes with mock providers, so
`terraform init -backend=false` then `terraform test` needs no GCP login and
calls no API. `terraform test` always runs in the default workspace, so a test
picks its shape with the `settings_workspace` variable (`locals.tf`), which
replaces `terraform.workspace` for the settings file, the names and the
pro-only defaults. Root files therefore read `local.workspace`, never
`terraform.workspace`. Left unset, the workspace decides as before; set
outside a test, the `settings_workspace_unset` check warns.

A test that needs a value no reference file holds, typically one a
precondition must refuse, passes it in `settings_override`: top-level keys
merged over the workspace file, as shallow as the file itself, so a key there
replaces the whole section. The same check warns when it is set.
`input_guards.tftest.hcl` uses it with `expect_failures`.

A behaviour that only a workspace shape shows (a resource that must not exist
in dev, a protection pro must have) gets an assertion in the matching test
file, with a positive control so an empty plan cannot pass it. A test cannot
read resources inside a module of the stack: assert on the root resource or
local that feeds it, or plan the module alone as `pro_cloud_sql.tftest.hcl`
does.
