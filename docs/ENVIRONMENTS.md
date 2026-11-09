# Environments

`AGENTS.md` names the workspaces `dev`, `stg` and `pro`, and each has its own
cost profile: dev is the cheapest that still runs the app, stg is one step up
with the shape of pro, pro is highly available. `settings/pre.yaml` is the stg
profile under the older name, with project id `example-app-pre`. It stays so
the auditor still finds a pre workspace. Use `stg` for a new project.

They describe one service: Cloud Run, a private Cloud SQL instance, one bucket,
one shared VPC, a budget, and a GitHub Cloud Build connection. Stg and pro put
the service behind the HTTPS load balancer, Cloud Armor and IAP, and add Redis
and Cloud NAT; dev has none of them and serves its run.app URL behind IAM
("Reaching dev" below). Anything else (Pub/Sub,
Firestore, a VM, Elastic) stays in `settings/example.yaml` until the project
needs it.

The files are full of placeholders (`example-app-dev`, `example-app-stg`, `example-app-pro`,
`000000-000000-000000`, `replace-me@example.com`, GitHub owner `example-org`,
installation id `1`). Replace those, put the state bucket name in
`backend.hcl` (copied from `backend.hcl.example`), run
`terraform init -backend-config=backend.hcl`, and plan. Applying is a separate decision. Planning this file
unchanged fails at GCP because the project and the billing account do not
exist, which is what we want.

`terraform validate` does succeed. It does not talk to GCP.

## What changes between them

| | dev | stg (and pre) | pro |
|---|---|---|---|
| Cloud Run | scale to zero, 1 vCPU, 512Mi, deletion protection off | same as dev | one warm instance, 2 vCPU, 2Gi, deletion protection on |
| Entry point | run.app URL, `INGRESS_TRAFFIC_ALL`, IAM only (`allow_unauthenticated: false`) | HTTPS load balancer, `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` | same as stg |
| Load balancer, Cloud Armor, IAP | none | yes, IAP on `/*` | yes, IAP on `/*` |
| Cloud Run CPU (`cpu_idle` default) | only during requests (`true`) | only during requests (`true`) | always allocated (`false`) |
| Cloud Run VPC egress | `PRIVATE_RANGES_ONLY`: public traffic leaves directly | `ALL_TRAFFIC` through Cloud NAT | `ALL_TRAFFIC` through Cloud NAT |
| Cloud NAT | none | one NAT, one static address | one NAT, one static address |
| Deploys | a push to `main` | a push to `main` | a tag `pro-YYYYMMDDHH` |
| Cloud SQL tier | `db-f1-micro` (shared core, 0.6 GB, no SLA), zonal | `db-custom-1-3840` (1 vCPU, 3.75 GB), zonal | `db-custom-2-7680` (2 vCPU, 7.5 GB), regional |
| Cloud SQL disk | 10 GB SSD | 10 GB SSD | 20 GB SSD |
| Cloud SQL deletion protection | off | on | on |
| Cloud SQL `max_connections` | 25 | 100 | 200 |
| Cloud SQL backups | 7, no point-in-time recovery | 7, no point-in-time recovery | 30, 7 days of WAL |
| Cloud SQL insights | off | off | on |
| Cloud SQL audit flags | none | none | connections, disconnections, statements over 1 s, lock waits, pgAudit `ddl,role` |
| Generated database passwords | letters and digits | letters and digits | letters, digits and `-_.~` |
| Redis | none | basic, 1 GB, no TLS | standard HA, 1 GB, TLS |
| Redis deletion protection | no Redis | off | on |
| Redis RDB snapshots | no Redis | off | every 12 hours |
| Firestore, when a workspace adds one (`firestore`) | no point-in-time recovery, delete protection as the database has it (off when new) | same as dev | point-in-time recovery (7 days), delete protection on |
| Bucket soft delete | 7 days (the shortest above off) | 7 days | 30 days |
| Bucket noncurrent versions | kept | kept | deleted after 30 days (`docs/STORAGE.md`) |
| Budget | 25 | 80 | 400 |
| _Default log retention | 30 days | 30 days | 90 days |
| Audit log archive | none | none | locked log bucket, 365 days |
| Log-based security alerts | none | none | seven presets, one email per event |
| Security module threshold alerts (`security.metric_alerts`) | all eight families | all eight families | network, routes and owner; the other five come from the log-based presets |
| Load balancer TLS policy (`lb.ssl_policy`) | no load balancer (run.app serves Google's own TLS) | `MODERN`, TLS 1.2 minimum (default) | `RESTRICTED`, TLS 1.2 minimum |
| Load balancer alerts (`monitoring.lb`) | none | none | 5xx, p99 latency, Cloud Armor 403 |
| Uptime check (`monitoring.uptime`) | none | none | the first `lb.domain` every 5 minutes from 3 regions |
| Secret read alert (`monitoring.secret_access`) | none | none | Secret Manager Data Access logs, one email per unexpected reader |
| Binary Authorization | off | off | enforced: Cloud Build signs each digest with a KMS key, unsigned images are refused |
| Service account keys (`security.disable_service_account_keys`) | allowed | allowed | refused: creation and upload, by organization policy on the project |
| Essential Contacts (`security.essential_contacts`) | none of its own (inherited, else the owners) | none of its own (inherited, else the owners) | one contact for `SECURITY`, `TECHNICAL` and `SUSPENSION` |
| External CI federation (`wif`) | none | none | none, a commented example (`docs/WIF.md`) |
| VPC | `10.8.1.0/24` | `10.10.1.0/24` | `10.20.1.0/24` |
| Private Service Access range (no charge) | `10.9.0.0/16` | `10.11.0.0/16` | `10.21.0.0/16` |
| Monthly cost, estimate | about 10 to 25 USD | about 130 to 160 USD | about 420 to 500 USD |

The cost row is a ballpark from Google Cloud list prices in `europe-west1`
(USD, on-demand, no free tier, no committed-use discounts), for an idle
project with little traffic. It is not a quote: requests, egress, log volume,
build minutes and storage growth come on top. Run the
[pricing calculator](https://cloud.google.com/products/calculator) before
committing to a figure. What drives it:

- Stg and pro pay the HTTPS load balancer forwarding rule (about 18 USD) and
  the Cloud Armor policy with its 11 rules (about 16 USD) before anything else,
  so about 34 USD is their floor. Dev has no load balancer.
- Dev pays the shared-core instance and its disk (about 10 to 12 USD). The
  rest (Cloud Run scaled to zero, Secret Manager, Artifact Registry storage,
  logs under 30 days) is cents to a few dollars at dev traffic, hence the
  upper end of about 25 USD.
- Stg adds the dedicated-core instance (about 55 USD), Redis BASIC (about 35
  to 40 USD) and Cloud NAT with its address (about 5 to 10 USD).
- Pro adds the regional instance, which bills both zones (about 220 to 240
  USD), Redis STANDARD_HA (about 50 USD), one always-allocated Cloud Run
  instance (about 95 to 105 USD), Cloud NAT and the audit archive. The
  Binary Authorization signing key is one KMS key version, cents a month.

The `budget.amount` values are placeholders. `gcp.billing.tf` sends them in EUR,
and Cloud Billing refuses a budget whose currency differs from the billing
account's. Set each one above the estimate for that workspace, or its alerts
fire every month.

Dev has no Redis, so the app must start without a cache; no service in
`settings/dev.yaml` references one. Dev has no Cloud NAT either: the service
sets `cloudrun.vpc.egress: "PRIVATE_RANGES_ONLY"`, so only private addresses
(the Cloud SQL private IP) go through the VPC and calls to public hosts leave
Cloud Run directly. Those calls come from a Google-owned address, not a
static one. When a third party must allowlist the egress IP, copy the
`network.nats` block from stg and drop the `vpc.egress` override.

Redis `deletion_protection` defaults to `true` in pro and `false` elsewhere,
so stg can be torn down and pro cannot: `terraform destroy`, or a change that
would replace the instance, fails while it is `true`. The flag lives in
Terraform state only. Turning it off is an in-place update with no API call,
applied before the destroy. Pro also sets `persistence`: an RDB snapshot every
12 hours. A STANDARD_HA instance fails over to its replica first and loads the
snapshot only when the replica is lost too; a BASIC instance reloads it after
every restart, scale or version upgrade. Only the last snapshot is kept and it
cannot be restored by hand, so it is not a backup: use `gcloud redis instances
export` for that. Snapshots need Redis 5.0 or later and add no charge to the
instance. Stg leaves them off because its cache can be rebuilt, not to save
money.

All of them keep the database private, require SSL, require an identity in
front of the service (IAP on `/*` in stg and pro, IAM on the run.app URL in
dev), and refuse to disable billing when the budget is hit. Stg and pro also
protect the Cloud SQL instance from deletion. Dev does not, so `terraform
destroy` removes it: export the data first when it matters (`gcloud sql
export sql`), since by default the automated backups are deleted with the
instance. `enable_auto_stop: false` matches the Terraform default and is written
out so nobody turns it on by accident: `true` deploys a function that turns
billing off, and every service in the project with it.

Stg and pro answer HTTP on port 80 with a 301 redirect to HTTPS, and the
HTTPS proxy uses the SSL policy set by `lb.ssl_policy` (`profile`,
`min_tls_version`, and `custom_features` with `CUSTOM` only). Without the
block it is `MODERN` with TLS 1.2 as the minimum, which is what stg uses. Pro sets `RESTRICTED`: only AES-GCM and ChaCha20 suites with forward
secrecy, so clients without them (very old Android, Java 7, Windows 7, some
embedded HTTP libraries) fail the handshake. Check the load balancer logs for
such clients before tightening another workspace. `TLS_1_3` as the minimum
needs `RESTRICTED` and refuses every TLS 1.2 client. A profile or version
change is an in-place update of the policy, with no new cost and no downtime.

`cloudrun.cpu_idle` defaults to `true` in every workspace but pro: a service
gets CPU only while it serves a request and is billed per request. Work that
keeps running after the response (a thread, a queue consumer, a flush on a
timer) is throttled and may never finish. A service that needs it sets
`cpu_idle: false`, which bills the CPU for as long as an instance is up. Pro
defaults to `false`, so its warm instance keeps its CPU.

The pro audit flags write to Cloud Logging, so dev and stg leave them out.
`db-f1-micro` and `db-g1-small` share a CPU and are not covered by the Cloud
SQL SLA, which is fine for dev and the reason stg uses a dedicated core.
`cloudsql.enable_pgaudit` only loads pgAudit: the application's migration
must run `CREATE EXTENSION pgaudit;` once in each database before
`pgaudit.log` records anything. This stack has no PostgreSQL provider and
does not run SQL. `pgaudit.log` stays at `ddl,role` because `write` logs the
text of every data change, literal values included. Add it only when the
retention and access rules of those logs allow it.

Pro sets `logging.audit_archive`: a log bucket `audit-archive` and a sink that
copies every Cloud Audit Log (admin activity, data access, system event,
policy denied) into it for 365 days. A project owner can shorten or empty
`_Default`; the archive is locked so nobody can. Two things to know before the
first apply:

- **A locked bucket is permanent for its retention.** It cannot be unlocked,
  its `retention_days` can only grow, and it cannot be deleted, by Terraform or
  by hand, until every entry in it is older than 365 days. `terraform destroy`
  of pro fails on it. To try the archive first, apply with `locked: false`,
  check the logs arrive, then lock it.
- **It is billed.** Logs routed to the archive count as ingestion (billed past
  the free monthly allotment), and log bucket storage beyond 30 days is billed
  per GiB-month. Audit volume grows with `security.audit_logging` data reads
  and writes. Dev and stg leave the key out and get neither the bucket nor the
  sink.

The bucket is in the same project as the sink, so no IAM grant is needed for
the sink's writer identity.

Pro sets `monitoring.log_alerts`: `gcp.monitoring.tf` turns each enabled entry
into an alert policy that matches Admin Activity audit log entries and emails
the `security.alerts_email` channel once per event, with the principal, the
method and the resource in the incident. The presets are:

| Preset | Fires on |
|---|---|
| `iam_policy_change` | `SetIamPolicy` on the project |
| `service_account_key_created` | a service account key created or uploaded |
| `firewall_change` | a VPC firewall rule inserted, patched, updated or deleted |
| `audit_config_change` | a `SetIamPolicy` that changes the audit log configuration |
| `custom_role_change` | a custom role created, updated, deleted or restored |
| `sql_instance_change` | a Cloud SQL instance created, updated or deleted |
| `bucket_iam_change` | `storage.setIamPermissions` on a bucket |

Any other key is a custom alert and needs its own `filter`. Entries take
`enabled`, `severity`, `notification_rate_limit` (one email per period, 5
minutes by default and at least that), `auto_close` (30 minutes by default
and at least that; the plan refuses a shorter value of either) and
`excluded_principals`. `monitoring.excluded_principals`
applies to every alert: put the identity that runs `terraform apply` there,
or each apply that touches IAM or a firewall pages the channel. Pro lists a
placeholder Terraform service account; replace it.

The basic security module has its own threshold alerts on the same firewall,
custom role, audit config, Cloud SQL and bucket IAM changes, which aggregate
over ten minutes and do not say who made the change. Pro turns those five off
with `security.metric_alerts`, so each change sends one email, from the
log-based preset. The module keeps its network, route and owner alerts, which
no preset covers. The check `security_metric_alerts_covered` warns when a
family is off and its preset is not in `log_alerts`. A change to an audit
config also matches `iam_policy_change`, since both are a `SetIamPolicy`.

Log-based alert policies are not billed, and they read logs Cloud Logging
already keeps. Dev and stg still leave the key out and keep every module
alert (`security.metric_alerts` defaults to `true`), so their channel only
gets the module's alerts.

Pro also sets `monitoring.lb`, read by the load balancer monitoring module in
`gcp.lb.tf`: more than 25 responses with a 5xx code in 3 minutes (ERROR), a
p99 latency above 3000 ms for 5 minutes (WARNING), and more than 150 requests
blocked by Cloud Armor in 3 minutes (WARNING). Each key needs all five fields
(`duration`, `threshold_value`, `alignment_period`, `severity`, `enabled`).
The Cloud Armor alert counts a log-based metric the module creates on the
load balancer request logs, which the backends already write. Tune the
thresholds to the real traffic after the first weeks.

`monitoring.uptime` adds one HTTPS uptime check per entry in
`gcp.monitoring.tf` and an alert policy that emails the same channel when the
check fails from `failing_regions` regions (2 by default) in the same window.
The host defaults to the first `lb.domain`. Pro probes `/` every 5 minutes
from three regions with a 10 second timeout. Two things to know:

- **IAP answers first.** Pro puts IAP on `/*`, so an anonymous probe gets a
  302 to the sign-in page (401 for some clients) and never reaches the app.
  Pro accepts `2xx`, `302` and `401`: the check proves that DNS, the
  certificate, the load balancer and IAP answer, not that the backend is
  healthy. To cover the backend, add a load balancer rule without IAP for a
  health path that returns no data, point `path` at it and accept `2xx` only.
- **It fails until the domain is real.** `app.example.com` is a placeholder,
  so the check fails and the alert fires from the first apply until
  `lb.domain` holds the real name and its certificate is active.

Each regional execution of an uptime check is billed at 0.30 USD per 1,000
past the free 1 million per project and month; three regions every 5 minutes
make about 26,000. Alert policies on uptime metrics are not billed. Cloud
Monitoring has announced a charge for metric alert policies from September
2027 at the earliest; the load balancer alerts fall under it, the uptime and
log-based ones do not. Dev and stg leave both keys out.

Pro sets `monitoring.secret_access`. A secret read (`AccessSecretVersion`) is
only logged as a Data Access audit log entry, and pro keeps
`security.audit_logging.data_read` off for every service, so the key adds a
`google_project_iam_audit_config` with `DATA_READ` for
`secretmanager.googleapis.com` alone (`gcp.security.tf`). The basic security
module keeps the `allServices` entry; both are separate service entries of the
project audit config, and no resource here manages the IAM policy as a whole.
`gcp.monitoring.tf` then adds a log-based alert, `secret_access`, that emails
the security channel once per read with the principal and the secret version,
unless the reader is expected:

- the service account of each Cloud Run service and job (the `external_sa` or
  the external job account when one is set), `run-cloudbuild-sa` and the
  Cloud Build service agent that reads the repository connection tokens,
  and the `user:` and `serviceAccount:` accessors granted in
  `secrets.<id>.accessors` and `external_secret_access.<id>.accessors`
  (`exclude_stack_principals: false` drops these). A `group:`, `domain:` or
  `principalSet://` accessor is not skipped: the log entry names the member
  who read the secret, not the group, so list that member in
  `allowed_principals`;
- `monitoring.excluded_principals`, where the Terraform identity goes: a
  refresh of a `google_secret_manager_secret_version` reads the payload;
- `monitoring.secret_access.allowed_principals`.

`secrets` limits the alert to a list of secret ids. The alert policy is not
billed. The log entries are: Data Access logs count towards the free 50 GiB of
log ingestion per project and month and cost 0.50 USD per GiB past it, and pro
also keeps them for 365 days in the locked audit archive. One read is a small
entry, written when an instance starts, a job runs or a build reads a secret,
so the volume is low, but it is not zero. Dev and stg leave the key out.

Pro sets `security.disable_service_account_keys`. `gcp.security.tf` then
enforces two boolean organization policy constraints on the project with
`google_org_policy_policy`: `iam.disableServiceAccountKeyCreation` (no new
key) and `iam.disableServiceAccountKeyUpload` (no public key of an external
key pair uploaded to a service account). The `service_account_key_created`
log alert stays on as a second line, for the day the policy is lifted. Keys
that exist keep working; list them with
`gcloud iam service-accounts keys list` and delete the user-managed ones.
Nothing in this stack needs a key: Cloud Run, jobs and Cloud Build run as
attached service accounts, and external CI uses `wif`. Two things to know:

- **The applier needs `roles/orgpolicy.policyAdmin`.** The role can only be
  granted on the organization or a folder, never on the project, so it
  usually comes from whoever runs the organization. Without it the apply
  fails on these two resources with a 403. The Org Policy API
  (`orgpolicy.googleapis.com`) is enabled with them and costs nothing.
- **The organization may enforce it already.** Organizations created since
  May 2024 enforce both constraints by default, and then the project policy only
  states the same rule in code, so it survives a change at the folder.
  Setting the key to `false` deletes the project policy and the project
  inherits again; it does not grant an exception. An exception (a third-party
  tool that only takes a key) is a project policy with `enforce = "FALSE"`,
  which this stack does not write.

Dev and stg leave the key out: a policy costs nothing, but a sandbox may need
a key for a quick test, and the folder policy decides there.

Pro sets `security.essential_contacts`, read in `gcp.security.tf`: one
`google_essential_contacts_contact` per entry on the project, with the
Essential Contacts API enabled with them. Google sends its mandatory notices
(a security incident or a compromised resource, an outage, a project about to
be suspended) to these contacts instead of only to the project owners, who
may be a person who left or a group nobody reads. The value is `true` for
`security.alerts_email` on `SECURITY` and `TECHNICAL`, or a list of entries
with `email` (default `alerts_email`), `categories` (default `SECURITY` and
`TECHNICAL`) and `language_tag` (default `en`); absent or `false` creates
none. Pro lists one entry with no `email`, so it follows `alerts_email`, with
`SECURITY`, `TECHNICAL` and `SUSPENSION`. Notes:

- `BILLING` on a project contact only gets the notices about that project.
  Invoices and payment problems go to the contacts of the billing account,
  which this stack does not own. `ALL` adds product updates, mostly noise.
- An organization can restrict the domains a contact may use
  (`essentialcontacts.allowedContactDomains`); an address outside them fails
  at apply. One address appears once per project; list every category it
  needs on that entry.
- Contacts cost nothing. Dev and stg leave the key out, so their notices
  still reach the owners, and the folder or organization contacts are
  inherited either way.

No reference file has a `firestore` section. When a workspace adds one,
`gcp.firestore.tf` defaults `point_in_time_recovery` to `true` and
`delete_protection_state` to `DELETE_PROTECTION_ENABLED` in pro. Elsewhere
point-in-time recovery defaults to `false` and delete protection is left
unset: the field is optional and computed, so Terraform keeps whatever the
database has (disabled for a new one, the API default) and never turns off a
protection someone set by hand. A value in the YAML wins. Both are updated
in place, without replacing the database, so outside pro the plan shows no
change and in pro it shows the two updates.
Point-in-time recovery keeps 7 days of versions, billed as storage, which is
why only pro has it. `deletion_policy` keeps the provider default,
`ABANDON`: a destroy, or a block removed from the YAML, drops the database
from state and leaves it and its data in GCP. With delete protection on,
`DELETE` fails at the API until the protection is turned off, which is the
point in pro. A disposable dev database that should go away with the stack
sets `deletion_policy: "DELETE"`.

The first Cloud Run revision is the public hello image. Cloud Build replaces
the digest and Terraform leaves it alone. Do not pin a real image in the YAML.

The database name `api-db` and the user `api-app-user` are the default, built
from the service name `api`, because these files omit `databases` and `users`.
Set those lists on the instance (siblings of `sql`) when a service should not
get a database, or when the names should differ.

## Reaching dev

Dev has no load balancer, so the service answers only on its run.app URL
(`terraform output cloud_run_service_urls`). It accepts traffic from the
internet (`INGRESS_TRAFFIC_ALL`) but `allow_unauthenticated` stays `false`:
Cloud Run refuses any request without a Google identity token of a principal
that holds `roles/run.invoker` on the service. `project_access.operators` get
that role on each service; viewers do not. Two ways in, with the operator's
own login:

```bash
# A local proxy that adds the token: open http://localhost:8080
gcloud run services proxy <client.name>-api --project example-app-dev \
  --region europe-west1 --port 8080

# One request with an identity token
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  "$(terraform output -json cloud_run_service_urls | jq -r .api)/"
```

A browser cannot send the token by itself, so a web front end is tested
through the proxy. A caller that is not a person (another service, a job, a
CI step) needs `roles/run.invoker` on the service and an identity token whose
audience is the service URL. When dev needs a domain, a browser login or
Cloud Armor, copy the `lb` and `iap` blocks and the service's
`loadbalancer.rules` from stg and set the ingress back to
`INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`; that brings the 34 USD floor back.

## What this is not

These files describe one application in one project per environment. There
is one VPC, not one per service. There is no external scanner instance, no
CMEK programme, and no separate monitoring project. `docs/audit/BACKLOG.md`
lists what is still open and what was left out on purpose.
