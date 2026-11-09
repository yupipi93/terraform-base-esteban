# Project structure

This document describes how the files in this repository fit together.

## Root directory

- `README.md`: overview and getting started.
- `locals.tf`: loads `settings/default.yaml`, merges `settings/<workspace>.yaml` on top, and exposes the result as `local.settings`.
- `providers.tf` and `versions.tf`: provider configuration, version pins and the remote state backend. The backend is an empty `backend "gcs" {}`; its bucket and prefix come from the gitignored `backend.hcl` (template `backend.hcl.example`) through `terraform init -backend-config=backend.hcl`.
- `outputs.tf`: root outputs (load balancer IP and domains, Cloud Run URLs, Cloud SQL connection names, registry paths, federation providers and accounts, audit archive bucket). Three more sit next to their feature: `dns_zone_name_servers` and `dns_record_names` in `gcp.dns.tf`, `sops_kms_key` in `gcp.sops.tf`. Each is an empty map or null when its feature is absent; none is a secret.
- `backend.hcl.example` and `.sops.yaml.example`: templates for the gitignored `backend.hcl` and for `.sops.yaml` (`docs/SOPS.md`).
- `gcp.<type>.tf`: one root file per GCP resource type. Each one reads its section of `local.settings` and creates nothing when that section is absent. The exceptions are the base APIs and the security baseline of `gcp.security.tf` (alert channel, audit log config, baseline alerts), which every workspace gets.
  - `gcp.project.tf`: the project number (`local.project_number`), from `project.number` or read from the project when the YAML leaves it out or keeps the all-zero placeholder.
  - `gcp.cloudrun.tf`: Cloud Run services, their service accounts, IAM and volumes.
  - `gcp.jobs.tf`: Cloud Run jobs.
  - `gcp.cloudbuild.tf`: Cloud Build triggers that build and deploy every image through `cloudbuild_files/cloudbuild.yaml`.
  - `gcp.network.tf`: the shared VPC, its `services` subnet, Private Service Access and Cloud NAT, only when `network.services_cidr` is set. Cloud Run reaches it with direct VPC egress; no Serverless VPC Access connector is created.
  - `gcp.lb.tf` and `gcp.waf.tf`: global HTTPS load balancer, backends, URL map, Cloud Armor.
  - `gcp.sql.tf`, `gcp.redis.tf`, `gcp.firestore.tf`: data stores.
  - `gcp.storage.tf`, `gcp.secrets*.tf`, `gcp.artifact*.tf`: buckets (`docs/STORAGE.md`), secrets, registries.
  - `gcp.iam.tf`, `gcp.service.permissions.tf`, `gcp.security.tf`: project IAM and the security baseline.
  - `gcp.wif.tf`: Workload Identity Federation for external CI (`docs/WIF.md`).
  - `gcp.billing.tf`: budget with optional automatic billing shutdown.
  - `gcp.enabled.apis.tf`: the base APIs plus `local.feature_apis`, the APIs each feature turns on (`docs/CONFIGURATION_GUIDE.md`).
  - `gcp.logging.tf` and `gcp.monitoring.tf`: log retention, the audit archive, log-based alerts, uptime checks and the secret read alert (`docs/ENVIRONMENTS.md`).
  - `gcp.sops.tf`: the optional SOPS key and the secret versions read from encrypted files (`docs/SOPS.md`).
  - `gcp.cloudrun.domain_mappings.tf`, `gcp.dns.tf`, `gcp.pubsub.tf`, `gcp.cloudtasks.tf`, `gcp.scheduler.tf`, `gcp.compute*.tf`, `gcp.firewall.tf`, `gcp.elastic.psc.tf`, `gcp.binary_auth.tf`, `gcp.repository.*.tf`: the rest, same pattern.
- `oracle.compute.tf`, `oracle.network.tf`, `oracle.security.tf`: the optional Oracle Cloud side (VMs, VCN, security lists), driven by the `oracle:` section.

## Subdirectories

### `settings/`

YAML files that define the infrastructure, one per workspace.

- `default.yaml`: baseline shared by every workspace (region, client prefix, base APIs; feature APIs come from `gcp.enabled.apis.tf`).
- `example.yaml`: commented reference, one section per feature, with defaults. `schemas/settings.schema.json` is the full list of keys.
- `dev.yaml`, `stg.yaml` and `pro.yaml`: the reference workspaces, one small service sized for each environment. See `docs/ENVIRONMENTS.md`. Replace the placeholders before planning.
- `pre.yaml`: the stg profile under its older name, kept as a legacy alias. Use `stg` for a new project.
- `<workspace>.yaml`: any further project. One file per workspace.

### `modules/`

Vendored Terraform modules, one directory per module version: `gcp_<name>_v<major.minor>`, for example `gcp_cloudsql_v7.5`. Each one covers a single component (Cloud Run v2, Cloud SQL, networking, storage, IAM, LB monitoring, Artifact Registry, managed SSL, project security). The version is in the directory name, so upgrading a module is an explicit, reviewable change: a new directory with the next version, every `source` pointed at it, the old directory deleted. Only the versions a root file uses are kept.

### `docs/`

Guides for the settings, the environments, the Cloud Build pipeline and its triggers, Cloud Run resources, storage, secrets, scanning, federation and billing control. [`docs/README.md`](README.md) is the index of every page. `docs/audit/` holds the maintainer's backlog (`BACKLOG.md`) and how it is worked (`OPERATING.md`).

### `schemas/`

`settings.schema.json`, the JSON Schema of the settings files, read by `bin/validate-settings.py`.

### `tests/`

`*.tftest.hcl` files that plan the default, dev and pro shapes with mock providers: `terraform test` needs no GCP login.

### `bin/`

Helper scripts:

- `validate-settings.py`: check every `settings/*.yaml` against the schema.
- `cloudbuild-render.py` and `cloudbuild-render-test.py`: render the effective Cloud Build pipeline of a service from the YAML, and its self-test.
- `audit-terraform.py`: the backlog checks (`docs/audit/OPERATING.md`).
- `ar-cleanup-check.py`: audit Artifact Registry cleanup policies.

### `.github/`

`workflows/terraform.yml`, the CI run on every pull request: format, tflint, `terraform test`, validate per workspace, the settings and render checks, and the p0 audit.

### `cloudbuild_files/`

The single shared Cloud Build pipeline. Per-service differences are substitutions generated from the YAML, never edits to this file.

### `cloud_function_source/`

Source of the Cloud Function that disables billing when the budget is exceeded.
