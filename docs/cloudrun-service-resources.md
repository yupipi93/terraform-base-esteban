# Resources created when you define a new Cloud Run service

This page lists the Google Cloud resources Terraform creates when a workspace file (`settings/<workspace>.yaml`) declares a Cloud Run service. A short entry is enough; the rest comes from defaults.

Adding an entry under `app.service` in a workspace file (for example `settings/dev.yaml`) creates the following resources.

## 1. Cloud Run service and service account

The Cloud Run service runs the container, with the CPU, memory, concurrency and `timeout` set in the YAML:

```yaml
app:
  service:
    my-service:
      cloudrun:
        min_instances: 0
        max_instances: 2
        container_port: 8080
        cpu: 1
        ram: "512Mi"
```

Each service gets its own service account, named `{client.name}-{service.name}-sa@{project.id}.iam.gserviceaccount.com` (for example `app-my-service-sa@example-app-dev.iam.gserviceaccount.com` with the default `client.name: app`). Set `cloudrun.external_sa` to run as an existing account instead. Roles listed in `cloudrun.additional_roles` are granted to the account on the project (for example `roles/aiplatform.user`).

When the workspace has a network (`network.services_cidr`), or the service sets `cloudrun.vpc_access_enabled: true`, the service uses direct VPC egress onto the shared VPC to reach private resources (Cloud SQL, Redis). Without a network it gets no VPC attachment. `cloudrun.vpc.egress` decides what goes through the VPC:

| Value | Behaviour | Used by |
|---|---|---|
| `ALL_TRAFFIC` (default) | Every outbound request goes through the VPC, so calls to public hosts need Cloud NAT (`network.nats`) | stg and pro, with one NAT and one static address |
| `PRIVATE_RANGES_ONLY` | Only private addresses go through the VPC; public traffic leaves Cloud Run directly, from a Google-owned address | the dev profile, which has no NAT (`docs/ENVIRONMENTS.md`) |

## 2. Secret Manager

Each `secret_env` entry (unless it sets `create_secret: false`) and each `secret_volume` entry creates a secret named `{client.name}-{service.name}-{secret.name}`:

```yaml
app:
  service:
    my-service:
      cloudrun:
        secret_env:
          - name: MY_API_KEY          # creates app-my-service-MY_API_KEY
            var_name: API_KEY
            version: latest
          - name: my-db-password      # an existing secret, used by this exact name
            var_name: DB_PASS
            create_secret: false
            raw_name: true
        secret_volume:
          - name: my-credentials      # creates app-my-service-my-credentials
            file_name: credentials.json
            mount_path: "/etc/secrets"
```

`raw_name: true` only matters with `create_secret: false`: it names the existing secret as is instead of adding the prefix. A secret this stack does not create is mounted as a file with `existing_secret_volume` (`secret_id`, `mount_path`, `file_name`).

Every created secret gets a first version with the value `PLACEHOLDER_VALUE_TO_BE_REPLACED`. Add the real value after the deployment (`gcloud secrets versions add`). Terraform ignores changes to `secret_data` on these versions, so the value can be managed outside Terraform. With `sops.enabled`, a matching key in `secrets/<workspace>/<service>.enc.yaml` becomes the version instead (`docs/SOPS.md`).

The service account of the service gets `roles/secretmanager.secretAccessor` on each secret it uses, created or existing, so it can read it at runtime and no other service can.

## 3. Cloud Build

A service with a `cloudbuild` block gets a trigger on the connected repository (`repo_name`, GitHub or Bitbucket through `repo_providers`). By default it fires on tags matching `^<workspace>-[0-9]{8}[0-9]{2}$` (for example `pro-2026010112`); `tag_pattern` or `branch_pattern` changes that (`docs/cloudbuild-tag-patterns.md`).

```yaml
app:
  service:
    my-service:
      cloudbuild:
        repo_name: "my-service-repo"
        inline: true
        cloudbuild_file_path: "cloudbuild.yaml"
        dockerfile_path: "Dockerfile"
```

With `inline: true` the pipeline is read from `cloudbuild_files/` and stored in the trigger; with `false` (the default) Cloud Build reads `cloudbuild_file_path` from the application repository. Substitutions pass the region, the service name, the Dockerfile path, the build context and the rest. See `docs/cloudbuild-pipeline.md`.

One shared account, `run-cloudbuild-sa`, runs every trigger. It holds `roles/cloudbuild.builds.builder`, `roles/run.admin`, `roles/iam.serviceAccountUser`, `roles/artifactregistry.writer` and `roles/logging.logWriter`, so it can build and push images and deploy services. The account and the `<client.name>-<workspace>-cloudbuild-artifacts` bucket exist only when the workspace declares at least one build (`cloudbuild`, or a `cloudbuild` block under `app.service` or `app.job`); a standalone repository listing `cloudbuild` as a writer also creates the account. A workspace with no build gets neither.

## 4. Cloud SQL (PostgreSQL)

The Cloud SQL instance is usually shared. When an instance omits its own `databases` and `users` lists, every Cloud Run service gets a database (`my-service-db`) and a user (`my-service-app-user`) inside it:

```yaml
app:
  service:
    my-service:
      cloudrun:
        env:
          - name: DATABASE_NAME
            value: my-service-db
          - name: DATABASE_USER
            value: my-service-app-user
```

The user's generated password is stored in Secret Manager as `<client.name>-<instance name>--<user>-password` (`app-main--my-service-app-user-password`). Nothing grants a service access to that secret on its own: list it in `secret_env` with `raw_name: true` and `create_secret: false`, and the stack grants the service account `roles/secretmanager.secretAccessor` on it.

`cloud_sql_instances_mount` on the service mounts the instance through a UNIX socket, the connection method Google recommends for Cloud Run.

## 5. Cloud Storage

Buckets declared under `bucket` grant roles to the service account through their `permissions`. A member written as `cloudrun:my-service` is turned into the email of that service's account:

```yaml
bucket:
  assets:
    permissions:
      creator:
        members: ["cloudrun:my-service"]
        roles: ["roles/storage.objectAdmin"]
```

## 6. Load balancer and IAP

A service with `loadbalancer.rules`, in a workspace with an `lb` section, gets:

- a serverless network endpoint group (NEG) that points at the service;
- a backend service on that NEG;
- URL map rules that route requests to it by the `path` and `rewrite` of each rule.

```yaml
app:
  service:
    my-service:
      loadbalancer:
        rules:
          - path: "/my-service/*"
            rewrite: "/"
            iap:
              enabled: false
```

When a rule sets `iap.enabled: true`, the backend service uses IAP, and the listed `members` (or the shared `iap.admin_access.members` with `use_default_members: true`) get `roles/iap.httpsResourceAccessor`. The IAP service agent gets `roles/run.invoker` on the service. That agent, and the 60 second wait for it to propagate, are created only when at least one service enables IAP (here or under `cloudrun.iap.enabled`).

## 7. Cloud DNS

No DNS resource is created per service. Public zones are declared once per workspace under `dns_zones` (`gcp.dns.tf`) and serve every service behind the load balancer.
