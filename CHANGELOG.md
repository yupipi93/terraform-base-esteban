# Changelog

All notable changes to this template are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). There are no tagged
releases yet: `main` is the only supported version, and each entry names the
backlog item of `docs/audit/BACKLOG.md` that brought it.

## [Unreleased]

The production readiness work: dev and stg cheap, pro ready for a security,
backup and data-retention audit.

### Added

- Reference workspaces `settings/dev.yaml`, `settings/stg.yaml` and
  `settings/pro.yaml`, with the cost and protection matrix in
  `docs/ENVIRONMENTS.md` (AUD-PRE, AUD-PRO, AUD-COST-PROFILES).
- Optional SOPS path: a KMS key per workspace and secret versions read from
  `secrets/<workspace>/<service>.enc.yaml` (AUD-SOPS).
- Workload Identity Federation for external CI (`wif`), so GitHub Actions or
  GitLab CI deploy without a service account key (AUD-WIF).
- Log-based alerts on IAM, service account key, firewall, audit config, custom
  role, Cloud SQL and bucket IAM changes (`monitoring.log_alerts`)
  (AUD-MON-LOG-ALERTS).
- Load balancer alerts and an HTTPS uptime check (`monitoring.lb`,
  `monitoring.uptime`) (AUD-MON-LB).
- An alert when a secret is read by an unexpected principal
  (`monitoring.secret_access`), skipping readers granted from the YAML
  (AUD-SECRET-ACCESS, AUD-SECRET-READERS).
- A locked log bucket that archives every Cloud Audit Log
  (`logging.audit_archive`) and `_Default` retention from
  `logging.retention_days` (AUD-AUDIT-ARCHIVE, AUD-LOGS).
- Bucket retention policies, usage logs and lifecycle rules for noncurrent
  versions (AUD-GCS-RETENTION), and public access prevention (AUD-PAP).
- Cloud SQL point-in-time recovery, Query Insights and, in pro, connection,
  statement and pgAudit flags (AUD-SQL-PITR, AUD-INSIGHTS, AUD-SQL-HARDEN).
- Redis deletion protection and RDB persistence from the YAML (AUD-REDIS).
- Configurable TLS policy on the load balancer (`lb.ssl_policy`) (AUD-TLS).
- Optional organization policy refusing service account keys
  (`security.disable_service_account_keys`) (AUD-SA-KEY-POLICY).
- Essential Contacts (`security.essential_contacts`) (AUD-ESSENTIAL-CONTACTS).
- Private Service Access: reserved ranges and the service networking
  connection for private Cloud SQL and Redis (AUD-PSA).
- Root outputs (`outputs.tf`) and a partial GCS backend with
  `backend.hcl.example` (AUD-TF-OUTPUTS, AUD-TF-BACKEND).
- A settings schema and `bin/validate-settings.py` (AUD-TF-SCHEMA).
- `terraform test` suites with mock providers (AUD-TF-TESTS).
- CI: fmt, tflint, validate per workspace, tests and the script checks, on a
  pinned runner; `.tflint.hcl` and `.pre-commit-config.yaml` (AUD-CI,
  AUD-CI-MATRIX, AUD-CI-RUNNER, AUD-LINT).
- Shared labels on every labelled resource, applied by the providers
  (AUD-LABELS, AUD-TF-LABELS).
- `AGENTS.md`, `docs/audit/OPERATING.md`, `CODEOWNERS`, a committed provider
  lock file, and the contributor, security and change files (AUD-AGENTS,
  AUD-CODEOWNERS, AUD-LOCK, AUD-DOC-OSS).

### Changed

- The shared VPC, and the Cloud Run and job attachment to it, exist only when
  `network.services_cidr` is set (AUD-NET, AUD-VPC-DEFAULT).
- Dev has no load balancer, Cloud Armor, Redis or NAT; it serves its run.app
  URL behind IAM, and its Cloud SQL instance can be destroyed (AUD-DEV-NO-LB,
  AUD-DEV-SQL-DISPOSABLE).
- The billing shutdown function is opt-in (`budget.enable_auto_stop` defaults
  to false), and Cloud Run CPU is billed per request outside pro
  (AUD-COST-DEFAULTS).
- Feature APIs are enabled only while their feature exists
  (`local.feature_apis`) (AUD-COST-APIS).
- Resources that were always created (the Cloud Build account and bucket, the
  IAP identity, the Pub/Sub service identity) follow the settings that need them
  (AUD-TF-ALWAYS-ON, AUD-PUBSUB-AGENT).
- Operators get `run.invoker` per service and `serviceAccountUser` per runtime
  account instead of project-wide grants (AUD-IAM-OPERATORS).
- The security module's threshold alerts can be turned off where a log-based
  alert covers the same event, as pro does (AUD-MON-SECURITY-DUP).
- Cloud SQL databases and users come from each instance's YAML (AUD-SQL-SCHEMA).
- Binary Authorization requires an attestation, Cloud Build signs each digest,
  and pro enforces it (AUD-BINAUTH, AUD-BINAUTH-PRO).
- Firestore defaults to point-in-time recovery and delete protection in pro
  (AUD-FIRESTORE-PRO).
- Google providers moved to `~> 7.42` (AUD-PROVIDER).
- Module directories renamed to `gcp_<name>_v<major.minor>` and root files to
  the dotted pattern (AUD-NAMES).
- Docs and comments in English, without em dashes, and rewritten against the
  current code (AUD-LANG, AUD-DOC-STALE).

### Fixed

- A workspace without a `bucket` section, an `lb` section, a network or
  `security.alerts_email` plans, or stops with a clear message (AUD-BUCKET,
  AUD-TF-GUARDS).
- The internal firewall reads its range from the settings instead of two
  hardcoded CIDRs (AUD-FW-CIDR).
- The project number is read from the project when the YAML leaves it out or
  keeps the placeholder (AUD-PROJECT-NUMBER).
- The Elastic Private Service Connect target comes from the settings
  (AUD-PUB-ELASTIC).
- Invalid durations and an Elastic endpoint without a network stop the plan
  (AUD-INPUT-GUARDS).

### Security

- Admin-read audit logs are on by default (AUD-AUDIT).
- Cloud Run services and jobs are protected from deletion in pro by default
  (AUD-DELETE).
- Tracked files carry no private names, real addresses or project ids
  (AUD-PUB-LEAKS).
