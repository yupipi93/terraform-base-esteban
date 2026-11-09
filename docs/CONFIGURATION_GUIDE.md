# Configuration guide (YAML)

This guide explains how to manage infrastructure using the YAML settings in the `settings/` directory.

## Basic workflow

1. Open `settings/${workspace}.yaml`.
2. Add or modify the desired resource block.
3. Run `python3 bin/validate-settings.py` (see below).
4. Run `terraform plan` to verify the changes.
5. Run `terraform apply` once the plan has been reviewed and approved.

## Validating the settings

The root files read most keys through `try()`, so a misspelled key (`netwrok:`,
`min_instance:`) is not an error in Terraform: the default applies and the plan
looks fine. `bin/validate-settings.py` checks every `settings/*.yaml` against
`schemas/settings.schema.json` before a plan:

```bash
python3 -m pip install pyyaml jsonschema   # jsonschema is optional
python3 bin/validate-settings.py
```

- Each workspace file is validated merged over `default.yaml`, the shallow merge of
  `locals.tf`. `example.yaml` is also validated alone, without the required keys.
- An unknown top-level key is an error. So is an unknown key in the sections whose
  shape the root files fix (`project`, `security`, `logging`, `monitoring`, `lb`,
  `network`, `budget`, `database.<name>`, `redis.<name>`, `wif`, ...). Entries passed
  whole to a module (`app.service.<name>.cloudrun`, `job-config`, `bucket.<name>`,
  `database.<name>.sql`) have their known keys typed and accept others.
- It also fails when a root `.tf` file reads a top-level key the schema does not
  list: a new setting goes into the schema in the same change, and into
  `settings/example.yaml`.
- The YAML is read like Terraform's `yamldecode` (YAML 1.2): `on`, `yes` and
  unquoted `02:00` are strings, and a duplicated key is an error.
- Without jsonschema a built-in validator handles the keywords the schema uses.
  Without PyYAML only the key cross-checks run and the script exits 2;
  `SETTINGS_SCHEMA_OPTIONAL=1` turns that into exit 0 with a `skipped` notice.

## Labels

Both Google providers set `default_labels` to `local.common_labels`
(`locals.tf`), so every resource with a `labels` field gets the same four:

| Label | Value |
|---|---|
| `workspace` | the Terraform workspace |
| `client` | `client.name` |
| `managed_by` | `terraform` |
| `repo` | `iac.repo` (default `terraform-base`) |

```yaml
client:
  name: "app"
iac:
  repo: "terraform-base"
```

GCP label values take at most 63 lowercase letters, digits, `_` and `-`, so
the values are lowercased, any other character becomes `-` and the result is
cut to 63. A label set on the resource (Redis `labels`, a VM's `labels`) is
merged on top and wins on the same key. Resources without labels (IAM, DNS
records, alert policies) are not affected. Cloud SQL keeps its labels in
`user_labels`, which the provider default does not reach. Repositories adopted
with `artifact_repos.<key>.adopt` get the four labels too, next to the ones they
already have.

Cloud Run domain mappings use the `google.unlabelled` provider alias, which has
no default labels: their labels are immutable, and adding one would destroy and
recreate the mapping and its certificate.

## Enabled APIs

`gcp.enabled.apis.tf` enables one list, the distinct union of three sources:

| Source | Where | What |
|---|---|---|
| `active-apis` | `settings/default.yaml` | The base every workspace needs: Resource Manager, IAM, IAM Credentials, Compute Engine (the security baseline sets OS Login metadata), Cloud Build, Cloud Run, Artifact Registry, Cloud Storage, Secret Manager, Logging, Monitoring |
| `local.feature_apis` | `gcp.enabled.apis.tf` | The APIs of a feature, on only while the feature exists |
| `extra-apis` | workspace file | Anything else the workspace needs, for example `aiplatform.googleapis.com` |

| Feature | Turned on by | APIs |
|---|---|---|
| `database` | a `database` instance | `sqladmin`, `servicenetworking` |
| `cloud_sql_mount` | a service with `cloudrun.cloud_sql_instances_mount` or a job with `job-config.cloud_sql_instances_mount`, also without a `database` section (an instance in another project) | `sqladmin` |
| `redis` | a `redis` instance | `redis`, `servicenetworking` |
| `network` | `network.services_cidr` | `compute`, `servicenetworking` (Private Service Access), `vpcaccess` |
| `lb` | an `lb` section | `compute` |
| `compute` | `compute_instances` or `compute_nats` | `compute` |
| `iap` | a service with `cloudrun.iap.enabled` or an IAP load balancer rule | `iap` |
| `dns` | `dns_zones`, or `elastic_psc.dns_domain` | `dns` |
| `firestore` | a `firestore` database | `firestore` |
| `pubsub` | `pubsub.topics` | `pubsub` |
| `cloud_tasks` | `cloud_tasks` queues | `cloudtasks` |
| `scheduler` | `scheduler` or `service_scheduler` jobs | `cloudscheduler` |
| `budget` | a `budget` section | `billingbudgets`, `cloudbilling` |
| `budget_auto_stop` | `budget.enable_auto_stop: true` | `cloudfunctions`, `eventarc`, `pubsub` |
| `contacts` | `security.essential_contacts` with at least one contact | `essentialcontacts` |
| `org_policy` | `security.disable_service_account_keys: true` | `orgpolicy` |
| `artifact_scanning` | `security.artifact_scanning: true` | `containerscanning` |
| `binary_authorization` | `binary_authorization.enabled: true` | `binaryauthorization`, `containeranalysis`, `cloudkms` |
| `sops` | `sops.enabled: true` | `cloudkms` |
| `vpc_connector` | a job with `job-config.vpc_access.connector` | `vpcaccess` |
| `wif` | a `wif.pools` key | `sts`, `iamcredentials` |

Every gate is the expression that creates the feature's resources, so the two
cannot drift apart. A new feature that calls a new API adds a line to both maps.
Direct VPC egress (`vpc_access_enabled`, `enable_vpc_access`, a job's
`vpc_access.network_interfaces`) onto a network this stack does not create needs
Compute Engine only, which is in the base. Secrets read from another project and
Pub/Sub, Cloud Tasks or Cloud Scheduler calls to Cloud Run need no API beyond
their own feature and the base.

```yaml
# settings/<workspace>.yaml
extra-apis:
  - "aiplatform.googleapis.com"
```

Do not set `active-apis` in a workspace file: the settings merge is shallow, so
it would replace the whole base list.

An API that leaves the list is never disabled. `google_project_service` has
`disable_on_destroy = false`, so the plan shows a destroy that only drops the
entry from state, and the project keeps the API on. A workspace applied with
an older, longer base list sees such a destroy for every API its sections do not
use (Firestore, Cloud Tasks, Cloud Scheduler, DNS, Cloud Functions and Eventarc
when the auto stop is off). A feature it does use keeps its API under the same
`enabled_apis["<api>"]` address, with no change.

The APIs that older versions managed as their own resource (`wif_sts`, `binary_authorization`,
`container_analysis`, `binauth_kms`, `container_scanning`) are moved into
`enabled_apis` with `moved` blocks. Cloud KMS had two copies, one for Binary
Authorization (`binauth_kms`) and one for SOPS (`cloudkms`), and only one move
can target `enabled_apis["cloudkms.googleapis.com"]`. The Binary Authorization
copy moves; the SOPS copy (`google_project_service.cloudkms[0]`) leaves state
through a `removed` block with `destroy = false`, so no API call is made. With
Binary Authorization on, the moved entry carries on. With SOPS only,
`enabled_apis` declares the API again: the plan shows a create, and enabling an
API that is already on changes nothing in the project.

## Cloud Run services

Services are defined under `app.service`.

### Adding a new service

```yaml
app:
  service:
    my-new-service:
      name: "my-new-service"
      cloudrun:
        container_port: 8080
        cpu: 1
        ram: "512Mi"
        max_instances: 5
        min_instances: 0
        allow_unauthenticated: true
```

### Environment variables and secrets

#### Plain text environment variables
```yaml
        env:
          - name: APP_COLOR
            value: "blue"
```

#### Mounting an existing secret as a file
```yaml
        existing_secret_volume:
          - name: "config-secret"
            secret_id: "my-secret-id"
            mount_path: "/etc/secrets"
            file_name: "config.json"
```

### Storage volumes (GCS)

You can mount GCS buckets as volumes. With `create_gcs: true` the bucket is
created too. Without it the volume mounts `bucket_name`, or
`{client}-{workspace}-{service}-{name}` when that is not set, and the bucket
must exist.

```yaml
        gcs_volume:
          - name: "uploads"
            mount_path: "/data/uploads"
            create_gcs: true # Creates {client}-{workspace}-{service}-uploads--<random hex>
```

## GCS buckets

Stand-alone buckets are defined under `bucket`.

```yaml
bucket:
  my-data-bucket:
    custom_name: "my-data-bucket"
    class: "STANDARD"
    region: "europe-west1"
    soft_delete_days: 7
```

Lifecycle rules, retention policies (Bucket Lock) and usage logs, and when to
use each, are in [STORAGE.md](STORAGE.md).

## Compute instances (VMs)

VMs are defined under `compute_instances`.

```yaml
compute_instances:
  my-vm:
    name: "my-vm"
    zone: "us-east1-c"
    machine_type: "e2-micro"
    boot_disk:
      image: "ubuntu-os-cloud/ubuntu-2204-lts"
      size_gb: 20
```

## Private Service Access (private Cloud SQL and Memorystore)

A Cloud SQL instance with `ipv4_enabled: false` and a redis with
`connect_mode: PRIVATE_SERVICE_ACCESS` take their IP from a range reserved in
the shared VPC and reached through one peering to the Google service network.
`network.services_ip_ranges` lists those ranges. The networking module creates
one `google_compute_global_address` (purpose `VPC_PEERING`) per entry and one
`google_service_networking_connection` that carries all of them, and the
database and the redis are created after that connection. Ranges and peering
cost nothing.

```yaml
network:
  services_cidr: "10.10.1.0/24"
  services_ip_ranges:
    private:                  # range name: <vpc>--private
      address: "10.11.0.0"    # optional, default: Google picks a free block
      prefix_length: 16       # 8 to 24, default 16
```

- Key left out: a workspace with a private data store gets one `/16` named
  `private` that Google allocates from the free private space of the VPC, so it
  cannot overlap `services_cidr`. A workspace without one gets no range and no
  connection.
- `services_ip_ranges: {}`: nothing is created, and a private data store stops
  the plan with an error (a precondition on the VPC in the networking module).
- An explicit `address` that overlaps `services_cidr` or `extra_internal_cidrs`
  stops the plan with an error from the same place.
- `redis.<name>.reserved_ip_range` may name a key of this map; it is passed as
  the allocated range name.
- On destroy the connection is abandoned (`deletion_policy = "ABANDON"`): the
  API refuses to delete it while Cloud SQL still holds the peering, which it
  does for some days after the instance is gone. The peering goes away with
  the VPC.
- A range in use cannot shrink or move. Add a second key to grow.

### Workspaces that created the peering by hand

Older versions passed the ranges to the module but created nothing, so a
running private database in a workspace applied with one of them means someone
made the range and the connection outside Terraform. Bring them into state
before the next apply instead of letting the plan create a second range. With the VPC named
`<base_name>-vpc` and the range key `private` (`terraform state show
'module.network[0].google_compute_network.net'` prints the name):

```bash
gcloud compute addresses list --global --filter="purpose=VPC_PEERING" --project=<project-id>
gcloud services vpc-peerings list --network=<vpc-name> --project=<project-id>

terraform import 'module.network[0].google_compute_global_address.net_private["private"]' \
  'projects/<project-id>/global/addresses/<vpc-name>--private'
terraform import 'module.network[0].google_service_networking_connection.net_private_connection[0]' \
  '/projects/<project-id>/global/networks/<vpc-name>:servicenetworking.googleapis.com'
terraform plan
```

Write the existing block in `services_ip_ranges` (`address`, `prefix_length`)
so the plan shows no replacement. A range made by hand under a name other
than `<vpc-name>--<key>` cannot be adopted: address names are immutable and
the module derives them from the key. Do not apply in that case, because the
connection update would drop a range that is in use. Import edits
state, so it needs the same go as an apply. If the connection is not imported,
`update_on_creation_fail` makes the create patch the existing one with the
ranges in the settings instead of failing.

## Private endpoint for Elastic Cloud

`elastic_psc` creates an internal address in the `services` subnet and a PSC
endpoint to the provider's service attachment. Without the key nothing is
created. The attachment must be in `region_name`, and `network.services_cidr`
must be set: without it the plan stops with an error instead of creating
nothing.
`dns_domain` is optional and adds a private zone with apex and wildcard records
pointing at the endpoint.

```yaml
elastic_psc:
  service_attachment: "projects/example-provider-project/regions/europe-west1/serviceAttachments/example-attachment"
  dns_domain: "psc.example-provider.example.com"
```

## Security and access

### Project operators
Define who runs the application day to day. `viewers` get `roles/viewer` on
the project; `operators` get it too, plus:

```yaml
project_access:
  operators:
    - "user:admin@example.com"
```

| Grant | Scope |
|---|---|
| `roles/run.invoker` | each Cloud Run service under `app.service` |
| `roles/iam.serviceAccountUser` | each runtime service account this stack creates for a service or a job |
| `CloudRunJobOperatorWithOverrides` (custom: run jobs, with overrides, and read executions) | project |
| `roles/cloudbuild.builds.editor` | project |

Operators can act as the runtime accounts of the stack but not as
`run-cloudbuild-sa`, which holds `roles/run.admin` and
`roles/iam.serviceAccountUser` on the project. So creating, editing or running
a Cloud Build trigger by hand needs that account's owner; pushes and tags
still start builds. A service with `cloudrun.external_sa`, or a job with an
external `service_account`, uses an account this stack does not manage:
whoever owns it grants `actAs` on it.

Older versions granted operators `run.invoker`,
`iam.serviceAccountUser` and `cloudbuild.connectionAdmin` on the whole
project. On a workspace applied with one of them, the next apply removes those three project bindings and adds the
per-resource ones. Operators then lose: invoking Cloud Run services this
stack does not manage, acting as any other service account in the project
(`run-cloudbuild-sa` and the default compute account included), running or
editing triggers by hand, and managing repository connections (which also
lets a caller fetch a read-write token for every linked repository). Grant
any of those back outside `project_access`, on the one resource that needs
it.

### Security alerts
```yaml
security:
  alerts_email: "security@example.com"
```

Every alert policy notifies this channel, so the address is required: the plan
stops with a clear error when it is missing or malformed. The settings merge is
shallow, so a workspace that declares `security:` must repeat `alerts_email`.

### Cloud Run ingress
A service without an explicit `cloudrun.ingress` gets
`INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` when the workspace has an `lb:` section
and `INGRESS_TRAFFIC_ALL` when it has none. Without a load balancer the service
still requires IAM (`allow_unauthenticated` defaults to false).

### External CI without keys
GitHub Actions, GitLab CI or another OIDC issuer authenticate through Workload
Identity Federation (`wif`), never with a service account key. Every provider
needs an `attribute_condition`. See [WIF.md](WIF.md) for the keys and a
`google-github-actions/auth` workflow.
