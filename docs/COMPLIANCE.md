# Compliance map of the pro workspace

This page lists what `settings/pro.yaml` puts in place for a security, backup and
data-retention audit, where each control lives in the code, and how an auditor
can check it on a running project. It covers the pro workspace only. Dev and stg
are cheap on purpose and are described at the end.

A control here is the technical half of a requirement. Certification is about the
organisation as a whole: policies, people, suppliers and the evidence that the
process runs. The section "What you still own" lists the parts this stack cannot
provide.

The mappings name ISO/IEC 27001:2022 Annex A controls, the 2017 AICPA Trust
Services Criteria used for SOC 2 (CC for the common criteria, A for availability,
C for confidentiality) and GDPR articles. A dash means no direct mapping. They
show where a control is relevant evidence, not that the control alone satisfies
the requirement.

The evidence commands use two shell variables and the resource prefix:

```bash
P=example-app-pro     # project.id in settings/pro.yaml
R=europe-west1        # region_name in settings/default.yaml
# <client> is client.name; most names start with <client>-pro-
```

Keys are paths inside `settings/pro.yaml`. "Code default" means pro gets the value
without the file setting it.

## Identity and access

| Control | Key | Terraform resource | Evidence | ISO 27001 | SOC 2 | GDPR |
|---|---|---|---|---|---|---|
| Two access lists: viewers read the project, operators also invoke and act as the stack's own runtime accounts | `project_access.viewers`, `project_access.operators` | `google_project_iam_member.viewers`, `google_cloud_run_v2_service_iam_member.operator_invokers`, `google_service_account_iam_member.operator_act_as` | `gcloud projects get-iam-policy $P`; `gcloud run services get-iam-policy <client>-api --region=$R --project=$P` | 5.15, 5.18, 8.2 | CC6.1, CC6.3 | 32(1)(b) |
| Every request through the load balancer passes IAP, which admits only the listed members | `iap.admin_access.members`, `app.service.api.loadbalancer.rules[].iap` | `google_compute_backend_service.iap_backend`, `google_iap_web_iam_binding.iap_resource_accessor` | `gcloud iap web get-iam-policy --project=$P`; console: Security, Identity-Aware Proxy | 5.15, 8.5 | CC6.1 | 32(1)(b) |
| Cloud Run takes no traffic from the internet except through the load balancer; the internal ingress also admits the project's VPC and Google services such as Cloud Scheduler, Cloud Tasks and Pub/Sub, and every caller still needs `roles/run.invoker`, so there is no anonymous access | `app.service.api.cloudrun.ingress`, `app.service.api.cloudrun.allow_unauthenticated` | `module.cloud_run_services` | `gcloud run services describe <client>-api --region=$R --project=$P` (ingress annotation); the IAM policy above has no `allUsers` | 8.3, 8.20 | CC6.1, CC6.6 | 32(1)(b) |
| No service account key can be created or uploaded | `security.disable_service_account_keys` | `google_org_policy_policy.service_account_keys` | `gcloud org-policies describe iam.disableServiceAccountKeyCreation --project=$P --effective` (and `iam.disableServiceAccountKeyUpload`) | 5.17, 8.5 | CC6.1 | 32(1)(b) |
| Secret values live in Secret Manager; the stack grants each service account access to its own secrets only | `app.service.api.cloudrun.secret_env` | `google_secret_manager_secret.run_secrets`, `google_secret_manager_secret_iam_member.run_secrets_access` | `gcloud secrets list --project=$P`; `gcloud secrets get-iam-policy <secret> --project=$P` | 5.17, 8.3 | CC6.1 | 32(1)(b) |
| Generated database passwords with a wider character set | `database.main.sql.special_password` | `module.cloud_sql` | the password is a Secret Manager secret of the instance; `gcloud secrets list --project=$P` | 5.17 | CC6.1 | - |

External CI that deploys without a key goes through workload identity federation
(`wif`, `docs/WIF.md`). Pro keeps it as a commented example until a pipeline outside
Cloud Build needs it.

## Logging and audit trail

| Control | Key | Terraform resource | Evidence | ISO 27001 | SOC 2 | GDPR |
|---|---|---|---|---|---|---|
| Admin Read audit logs for every service, on top of the Admin Activity logs Google always writes | `security.audit_logging` | `module.basic_security` (`google_project_iam_audit_config.project`) | `gcloud projects get-iam-policy $P --format="yaml(auditConfigs)"` | 8.15 | CC7.2 | - |
| Data Access logs for Secret Manager reads | `monitoring.secret_access` | `google_project_iam_audit_config.secret_manager_data_read` | same command, `secretmanager.googleapis.com` entry with `DATA_READ` | 8.15 | CC7.2 | 32(1)(b) |
| Every Cloud Audit Log copied to a locked bucket for 365 days | `logging.audit_archive` | `google_logging_project_bucket_config.audit_archive`, `google_logging_project_sink.audit_archive` | `gcloud logging buckets describe audit-archive --location=global --project=$P` (`locked: true`); `gcloud logging sinks describe <client>-pro-audit-archive --project=$P` | 5.28, 5.33, 8.15 | CC7.2 | - |
| Database connections, slow statements, lock waits and DDL or role changes logged | `database.main.sql.flags` (`log_*`, `cloudsql.enable_pgaudit`, `pgaudit.log`) | `module.cloud_sql` | `gcloud sql instances describe <instance> --project=$P --format="yaml(settings.databaseFlags)"` | 8.15 | CC7.2 | - |
| Load balancer request logs, every request | Code default with `lb` | `google_compute_backend_service.iap_backend`, `service_backend` and `default_backend` (`log_config`) | console: Logging, Logs Explorer, resource `http_load_balancer` | 8.15 | CC7.2 | - |

pgAudit records nothing until the application runs `CREATE EXTENSION pgaudit;` in
each database (`docs/ENVIRONMENTS.md`).

## Data protection and backups

| Control | Key | Terraform resource | Evidence | ISO 27001 | SOC 2 | GDPR |
|---|---|---|---|---|---|---|
| Cloud SQL has no public IP and refuses unencrypted connections | `database.main.sql.ipv4_enabled`, `database.main.sql.ssl_mode` | `module.cloud_sql` | `gcloud sql instances describe <instance> --project=$P --format="yaml(settings.ipConfiguration)"` | 8.20, 8.24 | CC6.1, CC6.7 | 32(1)(a), 32(1)(b) |
| Cloud SQL runs in two zones with automatic failover | `database.main.sql.availability` | `module.cloud_sql` | `availabilityType: REGIONAL` in the describe output | 8.14 | A1.2 | 32(1)(b) |
| Daily backups kept 30 times in a multi-region location, with 7 days of point-in-time recovery | `database.main.sql.backup` | `module.cloud_sql` | `gcloud sql backups list --instance=<instance> --project=$P`; `settings.backupConfiguration` in the describe output | 8.13 | A1.2 | 32(1)(c) |
| Redis is highly available, needs AUTH and TLS, and takes an RDB snapshot every 12 hours | `redis.cache.tier`, `redis.cache.auth_enabled`, `redis.cache.transit_encryption_mode`, `redis.cache.persistence` | `google_redis_instance.redis_instances` | `gcloud redis instances describe <client>-pro-cache --region=$R --project=$P` | 8.14, 8.24 | A1.2, CC6.7 | 32(1)(a), 32(1)(b) |
| The bucket keeps overwritten and deleted objects: versioning, then 30 days of soft delete | `bucket.uploads.enable_versioning`, `bucket.uploads.soft_delete_days` | `module.storage_buckets` | `gcloud storage buckets describe gs://<bucket> --format="yaml(versioning_enabled,soft_delete_policy)"` | 8.13 | A1.2 | 32(1)(c) |
| Public access prevention is enforced and access is uniform at bucket level, so no object ACL or `allUsers` grant takes effect while those settings stay | `bucket.uploads.uniform_access`; public access prevention is a code default (`enforced`) | `module.storage_buckets` | same command, `uniform_bucket_level_access` and `public_access_prevention` | 8.3 | CC6.1 | 32(1)(b) |
| A destroy, or a change that replaces the database, the service or Redis, fails while their deletion protection is on; turning it off is a separate, visible change | `database.main.sql.deletion_protection`, `app.service.api.cloudrun.deletion_protection`, `redis.cache.deletion_protection` | `module.cloud_sql`, `module.cloud_run_services`, `google_redis_instance.redis_instances` | `settings.deletionProtectionEnabled` in the SQL describe output; the Redis and Cloud Run flags are in Terraform state only (`terraform state show`) | 5.30 | A1.2 | 32(1)(b) |
| Encryption at rest | none: Google-managed keys on every resource | - | Google Cloud default, no setting to show | 8.24 | CC6.1 | 32(1)(a) |

## Retention and deletion

| Control | Key | Terraform resource | Evidence | ISO 27001 | SOC 2 | GDPR |
|---|---|---|---|---|---|---|
| `_Default` log bucket keeps 90 days, written down instead of left to Google's default | `logging.retention_days` | `google_logging_project_bucket_config.default` | `gcloud logging buckets describe _Default --location=global --project=$P` | 8.15 | C1.2 | 5(1)(e) |
| Audit logs kept 365 days; once locked, the retention cannot be shortened and no entry can be deleted before it expires | `logging.audit_archive.retention_days`, `logging.audit_archive.locked` | `google_logging_project_bucket_config.audit_archive` | describe output of `audit-archive` above | 5.33, 8.15 | CC7.2 | 5(1)(e) |
| Noncurrent object versions deleted 30 days after they stop being current | `bucket.uploads.lifecycle_rules.delete_noncurrent_versions` | `module.storage_buckets` | `gcloud storage buckets describe gs://<bucket> --format="yaml(lifecycle_config)"` | 8.10 | C1.2 | 5(1)(e), 17 |
| No locked retention policy on the bucket, so a user's files can be erased | no `retention_policy` under `bucket.uploads` | `module.storage_buckets` | same command, no `retention_policy` | 8.10 | C1.2 | 17 |
| Database backups expire after 30 backups and 7 days of logs | `database.main.sql.backup.retained_backups`, `database.main.sql.backup.transaction_log_retention_days` | `module.cloud_sql` | `settings.backupConfiguration` in the describe output | 8.10, 8.13 | C1.2 | 5(1)(e), 17 |

An erased row or file stays in the database backups for up to 30 days, and a
deleted object in soft delete for 30 more, until each one expires. Say so in the
privacy notice and the erasure procedure.

## Network and perimeter

| Control | Key | Terraform resource | Evidence | ISO 27001 | SOC 2 | GDPR |
|---|---|---|---|---|---|---|
| HTTPS load balancer with a Google-managed certificate; port 80 only redirects | `lb.domain` | `google_compute_target_https_proxy.lb_https_proxy`, `module.certificate_main`, `google_compute_url_map.lb_http_redirect` | `gcloud compute target-https-proxies list --project=$P`; `gcloud compute url-maps list --project=$P` | 8.20, 8.24 | CC6.6, CC6.7 | 32(1)(a) |
| TLS 1.2 minimum with the `RESTRICTED` cipher profile | `lb.ssl_policy` | `google_compute_ssl_policy.lb_ssl_policy` | `gcloud compute ssl-policies describe <client>-pro-ssl-policy --project=$P` | 8.24 | CC6.7 | 32(1)(a) |
| Cloud Armor policy with the OWASP preconfigured rules in front of every backend | Code default with `lb` | `google_compute_security_policy.cloud_armor_waf` | `gcloud compute security-policies describe <client>-pro-waf-policy --project=$P` | 8.20 | CC6.6 | 32(1)(b) |
| One private VPC; Cloud SQL and Redis reach it only through Private Service Access | `network.services_cidr`, `network.services_ip_ranges`, `network.private_google_access` | `module.network` | `gcloud services vpc-peerings list --network=<network> --project=$P`; `gcloud compute networks subnets list --project=$P` | 8.20, 8.22 | CC6.6 | 32(1)(b) |
| Outbound traffic leaves through Cloud NAT from one static address | `network.nats` | `module.network` (`google_compute_router_nat`) | `gcloud compute routers list --project=$P`; `gcloud compute addresses list --project=$P` | 8.20 | CC6.6 | - |
| Firewall rules exist only with the network: IAP SSH range, internal VPC ranges, and HTTP and HTTPS for tagged instances (pro has none) | `network.services_cidr` | `google_compute_firewall.allow_iap_ssh`, `allow_internal_vpc`, `allow_http`, `allow_https` | `gcloud compute firewall-rules list --project=$P` | 8.20 | CC6.6 | - |

## Change and supply chain

| Control | Key | Terraform resource | Evidence | ISO 27001 | SOC 2 | GDPR |
|---|---|---|---|---|---|---|
| Changes are expected through pull requests and a reviewed plan; a plan with no drift shows nothing was changed outside Terraform | none: the repository and `AGENTS.md` (not enforced, see below) | the whole stack | pull request history; `terraform plan` shows no drift | 8.9, 8.32 | CC8.1 | - |
| A pro release is a tag `pro-YYYYMMDDHH`, not a branch push | `app.service.api.cloudbuild` (tag pattern code default `^pro-[0-9]{8}[0-9]{2}$`) | `google_cloudbuild_trigger.cloudbuild_triggers` | `gcloud builds triggers list --region=$R --project=$P`; `gcloud builds list --region=$R --project=$P` | 8.32 | CC8.1 | - |
| Each build fails on a leaked secret and reports code and dependency findings | `app.service.api.cloudbuild.scan` | `google_cloudbuild_trigger.cloudbuild_triggers` (inline pipeline steps) | the build logs of `gcloud builds list` | 8.8, 8.28, 8.29 | CC7.1, CC8.1 | - |
| Images in Artifact Registry are scanned for known vulnerabilities | `security.artifact_scanning` | `google_project_service.enabled_apis` (`containerscanning.googleapis.com`) | `gcloud artifacts docker images list <repository> --show-occurrences` | 8.8 | CC7.1 | - |
| Cloud Run refuses images without a Cloud Build attestation, except the allowlisted Google images (the hello placeholder, Google builders) | `binary_authorization` | `google_binary_authorization_policy.policy`, `google_binary_authorization_attestor.binauth`, `google_kms_crypto_key.binauth` | `gcloud container binauthz policy export --project=$P` | 8.19, 8.32 | CC6.8, CC8.1 | - |

`docs/SCANNING.md` names the scanner versions; `docs/cloudbuild-pipeline.md`
explains image signing.

## Monitoring and incident response

| Control | Key | Terraform resource | Evidence | ISO 27001 | SOC 2 | GDPR |
|---|---|---|---|---|---|---|
| Every alert policy of the stack notifies one email channel (budget alerts go to the billing account's contacts) | `security.alerts_email` | `google_monitoring_notification_channel.security_alerts` | `gcloud beta monitoring channels list --project=$P` | 5.24, 6.8 | CC7.3 | 33 |
| An email when an IAM, key, firewall, audit config, custom role, Cloud SQL or bucket IAM change happens, naming who made it; each policy sends at most one notification per 5 minutes (`notification_rate_limit`), so a burst of changes shares one email and the rest stay in the audit logs | `monitoring.log_alerts`, `monitoring.excluded_principals` | `google_monitoring_alert_policy.log_alerts` | `gcloud monitoring policies list --project=$P`; console: Monitoring, Alerting | 8.16 | CC7.2, CC7.3 | 33 |
| Threshold alerts on network, route and owner changes | `security.metric_alerts` | `module.basic_security` | same command | 8.16 | CC7.2 | - |
| An email when an identity the stack did not grant reads a secret, at most one per 5 minutes for the policy | `monitoring.secret_access` | `google_monitoring_alert_policy.log_alerts` (`secret_access`) | same command | 8.16 | CC7.2, CC7.3 | 33 |
| Alerts on load balancer 5xx, p99 latency and Cloud Armor blocks | `monitoring.lb` | `module.monitoring_load_balancing` | same command | 8.16 | CC7.2, A1.1 | - |
| HTTPS uptime check of the public domain from three regions | `monitoring.uptime` | `google_monitoring_uptime_check_config.uptime`, `google_monitoring_alert_policy.uptime` | `gcloud monitoring uptime list-configs --project=$P` | 8.16 | CC7.2 | 32(1)(b) |
| Google's security, technical and suspension notices go to a named contact | `security.essential_contacts` | `google_essential_contacts_contact.contacts` | `gcloud essential-contacts list --project=$P` | 5.24 | CC7.4 | - |
| Query insights on the database | `database.main.sql.insights` | `module.cloud_sql` | console: SQL, the instance, Query insights | 8.16 | CC7.2 | - |

## Cost guard

| Control | Key | Terraform resource | Evidence | ISO 27001 | SOC 2 | GDPR |
|---|---|---|---|---|---|---|
| A monthly budget alerts at 50, 75, 90 and 100 percent of spend | `budget.amount`, `budget.alert_spent_percents`, `budget.billing_account` | `google_billing_budget.billing_budget` | `gcloud billing budgets list --billing-account=<billing-account-id>` | - | - | - |
| Hitting the budget never turns billing off, so pro stays up | `budget.enable_auto_stop` (`false`) | no function, topic or service account is created | `gcloud functions list --project=$P` shows no billing function | - | A1.2 | 32(1)(b) |

A budget is a financial control, not a security one. It is listed because an audit
of availability asks what happens when spend spikes; in pro the answer is an email,
never a shutdown (`docs/billing-budget-control.md`).

## What you still own

These sit outside a project-level stack, or are decisions this template leaves to
the adopter on purpose. The accepted items are in `docs/audit/BACKLOG.md`.

- **Organization policies above the project.** Resource locations, domain
  restricted sharing, OS Login and the rest are set on the organization or the
  folder. Pro sets only the two service account key constraints, and the applier
  needs `roles/orgpolicy.policyAdmin` from whoever runs the organization.
- **Change control.** The template does not enforce review. Turn on branch
  protection with required reviews and status checks on the repository, and limit
  console write access (Owner and Editor) to a break-glass group, so that the pull
  request history really is the change record (ISO 8.32, SOC 2 CC8.1).
- **Access reviews.** The stack grants what `project_access` and `iap` list. Who
  belongs on those lists, the review every quarter or so and the removal of
  leavers are a process (ISO 5.18, SOC 2 CC6.2 and CC6.3). Put group emails in the
  lists; groups are created by the organization
  ([OK-GROUPS](audit/BACKLOG.md#ok-groups-p3-do-not-create-google-groups-from-terraform),
  [OK-IAM-MATRIX](audit/BACKLOG.md#ok-iam-matrix-p2-keep-the-two-access-lists)).
- **Data processing agreement and records.** Accept the Google Cloud data
  processing terms for the billing account, and keep your own records of
  processing (GDPR articles 28 and 30).
- **Incident process.** The stack sends emails. Someone has to read
  `alerts_email`, triage, escalate and, for a personal data breach, notify the
  supervisory authority within 72 hours (GDPR article 33, ISO 5.24 to 5.27, SOC 2
  CC7.3 to CC7.5).
- **Key and secret rotation.** The SOPS key, when `sops` is on, has no rotation
  period; the Binary Authorization signing key is asymmetric and does not rotate
  automatically; secret values, the database passwords included, are rotated by
  hand.
- **Restore drills.** Backups count once a restore has been tried: clone the
  instance to a point in time (`gcloud sql instances clone`), restore an object
  version, export Redis with `gcloud redis instances export`. Record the result
  and the time it took (ISO 8.13, SOC 2 A1.3, GDPR article 32(1)(d)).
- **More logs, if your risk analysis asks for them.** Data Access logs for other
  services (`security.audit_logging.data_read` and `data_write`), VPC flow logs
  and Cloud NAT logs are off. They are billed by volume.
- **Retention inside the database.** Deleting expired rows is application logic,
  an `app.job` entry when needed
  ([OK-RETENTION-JOB](audit/BACKLOG.md#ok-retention-job-p3-do-not-ship-a-row-deletion-job)).
- **VPC Service Controls.** A perimeter is an organization resource
  ([OK-VPCSC](audit/BACKLOG.md#ok-vpcsc-p2-do-not-manage-vpc-service-controls-here)).
- **CMEK, if your data classification requires it.** Google-managed encryption is
  the starting point; customer-managed keys follow the classification, one
  resource family per change
  ([OK-CMEK](audit/BACKLOG.md#ok-cmek-p2-do-not-encrypt-every-resource-with-cmek-by-default)).
- **Vulnerability triage.** The scanners report; fixing or accepting each finding
  in time is yours (ISO 8.8).
- **Placeholders.** `replace-me@example.com`, `app.example.com`, the excluded
  Terraform service account and the billing account in `settings/pro.yaml` are
  examples. An audit of the file as shipped would audit nothing.

## How dev and stg differ

Dev and stg are cheap on purpose, and keep out of audit scope as long as they
hold no production or personal data. Each environment is its own project
(`AGENTS.md`), which is the separation ISO 8.31 asks for.

Both keep the database private with SSL required, an identity in front of the
service (IAM on the run.app URL in dev, IAP in stg), Admin Activity audit logs and
a budget. They leave out the audit archive, the log-based and uptime alerts, the
secret read alert, point-in-time recovery, Binary Authorization, the service
account key policy and the Essential Contacts, and keep logs 30 days instead of
90. `docs/ENVIRONMENTS.md` has the full matrix and the cost of each workspace.
