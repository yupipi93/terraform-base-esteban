# Audit backlog

The list of work that takes this template to a public, production-grade
release: dev and stg cheap, pro ready for a security, backup and
data-retention audit. Each item has a check in `bin/audit-terraform.py`.

Open: 0. Done: 64. Accepted, not a gap: 22.

Regenerate with `python3 bin/audit-terraform.py --write` in the pull request
that closes an item. `--next` names the item to take. How a session works an
item: `docs/audit/OPERATING.md`.


## Open

None.

## Accepted, not a gap

### OK-MODULE-VPC (p1) Do not create one VPC per service or per module

One project, one application, one shared VPC created only when the YAML asks for it. A network per service adds peering and NAT for an isolation boundary this template does not have.

Next change: Leave it.

### OK-APP-SHAPE (p1) Do not nest services under a module map

app.service and app.job are the flat shape a single application wants.

Next change: Keep app.service.

### OK-SCANNER-INSTANCE (p2) Do not add a scanner that needs its own instance

Harbor or SonarQube need a server, robots and tokens. In-build scanners (gitleaks, semgrep, trivy fs) and Artifact Registry scanning are opt-in and need none.

Next change: Use cloudbuild.scan and security.artifact_scanning.

### OK-RETENTION-JOB (p3) Do not ship a row-deletion job

Deleting expired rows is application logic. When a project needs it, it is an app.job entry.

Next change: Leave it out.

### OK-SQL-RESIZER (p3) Do not stop Cloud SQL at night

A night stop needs functions and schedulers. dev gets a shared-core tier instead.

Next change: Leave it out.

### OK-RENOVATE (p3) Do not ship a dependency bot

Dependency updates are the adopter's choice.

Next change: Leave it out.

### OK-VPCSC (p2) Do not manage VPC Service Controls here

A perimeter is an organization policy a project stack cannot own.

Next change: Leave it out.

### OK-MODEL-ARMOR (p3) Do not enable Model Armor or DLP by default

Add the API where it is called.

Next change: Leave them commented.

### OK-GROUPS (p3) Do not create Google groups from Terraform

Group creation is an organization process. Membership is a list on project_access and iap.

Next change: Leave it out.

### OK-IAM-MATRIX (p2) Keep the two access lists

viewers and operators fit one team. A large custom role matrix belongs to a platform.

Next change: Put group emails in the workspace files.

### OK-BUILD-CHAT (p3) Do not ship a build-failure chat notifier

It needs a webhook and a space the adopter may not have.

Next change: Leave it out.

### OK-SYS-PROJECT (p2) Do not require a separate monitoring project

project_sys can be the workspace project until several apps share one.

Next change: Leave it.

### OK-SHALLOW-MERGE (p1) Keep the shallow settings merge

A deep merge would change every existing workspace in silence. Environment files are complete and do not set active-apis.

Next change: Document it.

### OK-CMEK (p2) Do not encrypt every resource with CMEK by default

Google-managed encryption is the starting point. CMEK follows the data classification, one resource family per change.

Next change: Leave it out. SOPS has its own key.

### OK-HELLO-IMAGE (p3) The first Cloud Run image stays the public hello image

The first apply boots a placeholder and Cloud Build replaces it. Terraform ignores later image changes.

Next change: Leave it.

### OK-MODULE-SNAPSHOTS (p2) Vendored modules stay snapshots

A module changes only through a new version directory, named modules/gcp_<name>_v<major.minor> with no timestamp. Newer private modules are not copied in.

Next change: Upgrade one module per change, with a new directory that bumps the version, and delete the old one once no source points at it.

### OK-OCI (p3) The optional Oracle Cloud files stay

oracle.*.tf create nothing without an oracle section. The provider is required at init only.

Next change: Leave it. Document it as optional.

### OK-OWNER (p3) CODEOWNERS and LICENSE name the repository owner

That is the owner of this repository, not a leak. A fork replaces it.

Next change: Leave it.

### OK-ACTIVE-APIS-KEY (p3) Keep the active-apis key name

Renaming it breaks every existing workspace for a style gain.

Next change: Leave it.

### OK-SOPS-OPTIONAL (p2) SOPS stays opt-in, also in pro

It needs a KMS key and encrypted files the adopter creates. The placeholder path is safe by default.

Next change: Document it in docs/SOPS.md.

### OK-SQL-REPLICA (p3) No read replica by default in pro

REGIONAL availability already gives a standby. A replica is a read scaling choice.

Next change: Leave it.

### OK-PRE-ALIAS (p3) settings/pre.yaml stays as the older name of stg

Existing users have a pre workspace. New projects use stg.

Next change: Keep it equal to stg.

## Done

- AUD-NET (p0) The shared VPC is created even when the workspace has no network section
- AUD-VPC-DEFAULT (p0) Cloud Run and jobs attach to the VPC by default
- AUD-FW-CIDR (p1) The internal firewall allows two CIDRs the VPC does not have
- AUD-BUCKET (p0) A workspace with no bucket key cannot plan
- AUD-AUDIT (p0) Admin-read audit logs are off
- AUD-DELETE (p0) Cloud Run services and jobs can be destroyed with deletion_protection left false
- AUD-INSIGHTS (p1) Cloud SQL Query Insights cannot be turned on
- AUD-PRE (p1) There is no stg workspace
- AUD-PRO (p1) There is no pro workspace
- AUD-LOCK (p1) The provider lock file is gitignored
- AUD-CI (p1) Nothing checks fmt or validate on a pull request
- AUD-SOPS (p1) Secret values have no sealed path into the plan
- AUD-PROVIDER (p2) The Google provider is pinned to 6.x
- AUD-PAP (p2) Buckets cannot set public access prevention
- AUD-LABELS (p2) Resources do not share an environment label
- AUD-SQL-SCHEMA (p2) Every Cloud Run service gets a database on every SQL instance
- AUD-PUBSUB-AGENT (p3) The Pub/Sub service identity is created in every workspace
- AUD-BINAUTH (p2) Binary Authorization, when turned on, only dry-runs an allow-all rule
- AUD-LOGS (p3) Log buckets keep the Google default retention
- AUD-CODEOWNERS (p3) No CODEOWNERS file
- AUD-AGENTS (p1) A session that opens this repo has no operating rules
- AUD-PUB-LEAKS (p0) Tracked files name private companies, products, people or real addresses
- AUD-PUB-ELASTIC (p1) The Elastic Private Service Connect target is a literal project path
- AUD-SQL-PITR (p1) Point-in-time recovery in the YAML never reaches Cloud SQL
- AUD-SQL-HARDEN (p1) Pro PostgreSQL has no connection or statement audit trail
- AUD-AUDIT-ARCHIVE (p1) Audit logs are not archived in a locked bucket
- AUD-GCS-RETENTION (p2) Buckets cannot set a retention policy or access logs, and pro keeps old versions forever
- AUD-REDIS (p2) Redis blocks destroy in every workspace and has no persistence option
- AUD-MON-LOG-ALERTS (p1) No alert fires on IAM, firewall, service account key or audit config changes
- AUD-MON-LB (p2) Pro has no load balancer error alerts and no uptime check
- AUD-SECRET-ACCESS (p2) Nobody is alerted when a secret is read by an unexpected principal
- AUD-WIF (p1) External CI can only authenticate with a service account key
- AUD-BINAUTH-PRO (p2) Pro turns Binary Authorization on but never blocks
- AUD-TLS (p2) The TLS profile is hardcoded
- AUD-TF-GUARDS (p1) A minimal workspace still fails on missing keys and wrong defaults
- AUD-TF-ALWAYS-ON (p2) Some resources are created in every workspace whether used or not
- AUD-TF-LABELS (p2) common_labels are not applied by the providers
- AUD-TF-OUTPUTS (p2) The root module has no outputs
- AUD-TF-BACKEND (p2) The state bucket is a literal in versions.tf
- AUD-TF-SCHEMA (p2) Nothing validates the settings files before a plan
- AUD-TF-TESTS (p3) There are no terraform tests
- AUD-CI-MATRIX (p1) CI validates only the default workspace
- AUD-CI-RUNNER (p1) CI runs on a moving runner label with Node 20 actions
- AUD-LINT (p3) No tflint or pre-commit configuration
- AUD-COST-DEFAULTS (p1) Two code defaults cost money when a key is left out
- AUD-COST-PROFILES (p1) dev is a copy of stg and stg a copy of pre
- AUD-COST-APIS (p3) APIs for SQL, Redis, Firestore and other features are enabled when unused
- AUD-NAMES (p2) Module directories carry build timestamps and some root files break the naming pattern
- AUD-LANG (p1) Docs and comments mix Spanish with English, and use em dashes
- AUD-DOC-OSS (p2) The repository has no contributor, security or change files
- AUD-PSA (p1) Private Service Access is never created, so private Cloud SQL and Redis fail on a new project
- AUD-PROJECT-NUMBER (p1) A workspace that sets project with only an id loses the project number
- AUD-IAM-OPERATORS (p1) Operators can invoke every service and act as every service account
- AUD-DEV-NO-LB (p1) The dev reference still pays for a load balancer and Cloud Armor
- AUD-MON-SECURITY-DUP (p2) The security module's metric alerts cannot be turned off and duplicate the log alerts
- AUD-SECRET-READERS (p2) Secret readers granted from YAML trigger the secret access alert
- AUD-INPUT-GUARDS (p3) Two settings fail late or silently
- AUD-SA-KEY-POLICY (p2) Nothing prevents service account key creation
- AUD-ESSENTIAL-CONTACTS (p2) Google has nobody to tell about security, legal or billing notices
- AUD-DEV-SQL-DISPOSABLE (p3) dev keeps Cloud SQL deletion protection on
- AUD-FIRESTORE-PRO (p3) Firestore in pro starts without PITR or delete protection
- AUD-DOC-STALE (p1) Several docs describe files, keys and names that changed
- AUD-DOC-COMPLIANCE (p1) Nothing maps the pro settings to audit controls
- AUD-DOC-README (p1) The README does not explain the project at a glance
