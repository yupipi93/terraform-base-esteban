# Buckets: retention, lifecycle and access logs

Every bucket under `bucket:` in the settings goes through
`modules/gcp_storage_v2.7` (`gcp.storage.tf`). This page covers the three
settings that decide how long objects live and who can see that they were
read: `lifecycle_rules`, `retention_policy` and `access_logs`. All three are
off unless a bucket sets them. `settings/example.yaml` shows every key.

## Lifecycle rules or a retention policy

They answer opposite questions.

| | Lifecycle rule | Retention policy (Bucket Lock) |
|---|---|---|
| Goal | Delete or move data once it is no longer needed | Keep data at least this long, whatever anyone does |
| Who can undo it | Anyone who can edit the bucket | Unlocked: a bucket admin. Locked: nobody, ever |
| Typical use | Old versions, temporary files, exports past their use | Records a law or a contract says must be kept |
| Settings key | `lifecycle_rules` | `retention_policy` |

Use a **retention policy** only for records that must be kept for a known
period: invoices, signed contracts, audit exports, anything under a legal
hold. While an object is younger than `retention_days` it cannot be deleted
or overwritten, by the app, by a bucket admin or by Terraform. With
`is_locked: true` that is permanent:

- the policy cannot be removed and its period can only grow;
- the bucket cannot be deleted until every object in it is older than the
  period, so `terraform destroy` of that workspace fails on it;
- an object cannot be erased early, even when a person has the right to have
  their data deleted.

Apply a new policy unlocked first, check that the app still works (an
overwrite of a young object fails), then set `is_locked: true` in a second
change. `retention_days` is in days and is converted to seconds; the API
limit is just under 100 years. A lifecycle rule on the same bucket still runs,
but it only deletes an object once the retention period has passed.

Use a **lifecycle rule** to get rid of data: that is data minimisation. Each
rule needs at least one condition:

- `age`: days since the object was created;
- `days_since_noncurrent_time`: days since a version was replaced or deleted;
- `num_newer_versions`: delete a version once this many newer ones exist.

The last two only match noncurrent versions, so they only do something on a
bucket with `enable_versioning: true`. Without such a rule, versioning keeps
every overwritten and deleted object forever.

## What the reference workspaces do

The `uploads` bucket holds user content, so it gets a lifecycle rule and no
retention policy.

| | dev | stg (and pre) | pro |
|---|---|---|---|
| Versioning | on | on | on |
| Noncurrent versions | kept | kept | deleted 30 days after they stop being current |
| Soft delete | 7 days | 7 days | 30 days |
| Retention policy | none | none | none |
| Usage logs | none | none | none |

In pro, a file the app overwrites or deletes stays readable as a noncurrent
version for 30 days, then the lifecycle rule deletes it and soft delete keeps
it, unreadable but restorable by a storage admin, for 30 more. After about 60
days it is gone. A locked retention policy on this bucket would make an
erasure request impossible to honour, which is why pro does not set one. Put
records that must be kept in their own bucket with a `retention_policy`.

Dev and stg keep their noncurrent versions. Add the same rule there if their
storage grows.

## Access logs: usage logs or audit logs

Cloud Storage can record access in two ways.

**Data Access audit logs** (recommended). Cloud Audit Logs entries in Cloud
Logging: who (the principal), what (`storage.objects.get`, `create`,
`delete`), which object, from where, and whether it was allowed. They can be
queried, alerted on (`monitoring.log_alerts`) and copied into the locked
`logging.audit_archive` bucket that pro already has. They are switched on with
`security.audit_logging.data_read` and `data_write`. In this template that
setting covers every service in the project (`allServices`), so the volume,
and the ingestion bill past the free allotment, grows with all traffic, not
only with bucket reads. Pro leaves both off; turn them on when an auditor asks
who read which file, and check the log volume for a few days after.

**Usage and storage logs** (`access_logs`). Hourly CSV files of every request
and a daily file of the bucket size, written as objects into another bucket.
They carry the requester's IP address and user agent but no identity, they
are not in Cloud Logging, so no query, alert or archive, and they arrive with
a delay. Use them when a tool needs the raw request files (traffic reports,
billing per object) or for a bucket served to anonymous clients. To turn them
on:

1. Create the log bucket first, for example as another `bucket:` entry with
   `custom_name` so its name is known. `log_bucket` takes a literal bucket
   name: it cannot point at another key of the same map, because the buckets
   are one `for_each`.
2. Grant `roles/storage.objectCreator` on the log bucket to the Cloud Storage
   analytics group named in Google's
   [usage logs guide](https://cloud.google.com/storage/docs/access-logs), with
   a `permissions` entry on that bucket.
3. Set `access_logs.log_bucket` (and optionally `log_object_prefix`, which
   defaults to the logged bucket's name) on the bucket to log.

The log objects are billed as storage in the log bucket: give it a lifecycle
rule with an `age` that matches how long the logs are needed.
