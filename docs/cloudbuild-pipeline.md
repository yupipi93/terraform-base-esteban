# The Cloud Build pipeline

One file, `cloudbuild_files/cloudbuild.yaml`, builds every image in this project. It
contains no service names, no build arguments, no image paths and no timeouts. Anything
that differs between two services is **data in `settings/<workspace>.yaml`**, turned into
Cloud Build substitutions by `gcp.cloudbuild.tf` at plan time.

The rule that follows from that: **you never edit the pipeline to give one service what
it needs.** If you find yourself about to, the key you are looking for is below.

```
settings/<workspace>.yaml          gcp.cloudbuild.tf              cloudbuild.yaml
  app.service.<svc>.cloudbuild  →  local.all_cloudbuild_configs →  substitutions
    build_args: {K: v}          →  _BUILD_ARGS                  →  docker build --build-arg
    job_name / deploy / …       →  local.cloudbuild_capabilities → x-when filter on steps
```

## Giving an image a build-time variable

```yaml
app:
  service:
    web:
      cloudbuild:
        repo_name: "example-web"
        build_args:
          SITE_ENV: "dev"
```

Terraform renders every entry into one deterministic string, sorted by key and
single-quoted, and the pipeline passes it verbatim to `docker build`:

```
--build-arg SITE_ENV='dev'
```

Single quotes are what make an arbitrary value safe: `$`, backticks, globs, spaces and
newlines cannot reach the shell, and an embedded quote is escaped the POSIX way
(`'\''`). A value containing `${_FOO}` is inserted literally: Cloud Build substitutes
once and never re-expands what it inserted.

Two consequences worth knowing:

- **An argument the Dockerfile does not declare is dropped by docker**, with a warning.
  Passing one is harmless; forgetting one is not.
- **An argument you stop declaring here restores the Dockerfile's own `ARG` default.**
  Before removing one, read the Dockerfile.

## Every key, and what it does

All of them live under `cloudbuild:` in a service, a job, or a top-level `cloudbuild`
entry. `settings/example.yaml` carries the same list with inline comments.

| Key | Default | What it does |
|---|---|---|
| `repo_name` | none | mandatory; the connected repository |
| `provider` | `repo_providers.default` | `github` or `bitbucket` |
| `inline` | `false` | `true`: pipeline read from `cloudbuild_files/`. `false`: from the application repository, and only `substitutions` reach it |
| `cloudbuild_file_path` | `cloudbuild.yaml` | which pipeline file |
| `dockerfile_path` | `Dockerfile` | matched literally; `dockerfile` is a different file |
| `build_context_path` | `.` | what docker sees; a Dockerfile that `COPY`s from its own directory needs that directory |
| `build_args` | `{}` | **any** build-time variable, as a map |
| `docker_target` | none | `--target=<stage>` for a multi-stage Dockerfile. Not a build arg |
| `image` | `<client>-<svc>/<svc>` | Artifact Registry path, or a job's `job-config.image` minus the tag |
| `image_base` | none | passed as `--build-arg IMAGE_BASE`, resolved against this project's registry when it has no host of its own |
| `reqs_file` | none | passed as `--build-arg REQS_FILE` |
| `artifact_registry_token` | `false` | adds a step that mints an access token and passes it as `--build-arg GOOGLE_ACCESS_TOKEN`. Only for images that install private packages from Artifact Registry |
| `build_timeout` | pipeline's `1800s` | per-service build timeout |
| `machine_type` | pipeline's default worker | a bigger builder |
| `deploy` | `true` | `false` builds and pushes without touching Cloud Run |
| `job_name` | none | a Cloud Run **job** that shares this service's image; the build repoints it at the digest it just pushed |
| `cloudrun.region` (outside the `cloudbuild` block) | `region_name` | where the service lives, and therefore where the build deploys it |
| `branch_pattern` / `tag_pattern` | tag `^<workspace>-YYYYMMDDNN$`, no tag pattern once `branch_pattern` is set | what fires the trigger (`docs/cloudbuild-tag-patterns.md`) |
| `build_filter_paths` | none | only build when these paths changed (branch triggers) |
| `scan` | all off | gitleaks, semgrep and trivy steps before `docker build` (`docs/SCANNING.md`) |
| `substitutions` | `{}` | raw Cloud Build substitutions, for a pipeline this repository cannot see |

## Optional steps: `x-when`

A step in the pipeline may carry `x-when: [flag, ...]`: a Terraform-only key, ANDed,
absent meaning unconditional. Terraform keeps the step only if every flag is on for that
service, then **rewrites the `waitFor` of the steps that survived**, so removing a step
never leaves a dangling dependency. A flag that is not a real capability is a plan
error, never a step that silently stops running.

| Capability | On when |
|---|---|
| `ar_token` | `artifact_registry_token: true` |
| `deploy_service` | the entry is a service (or a raw build) and `deploy` is not `false` |
| `deploy_job` | the entry is a Cloud Run job and `deploy` is not `false` |
| `update_companion_job` | a service declared `job_name` |
| `sign_image` | `binary_authorization.enabled` in the workspace; adds `sign-image` and the two `_BINAUTH_*` substitutions |
| `scan_secrets`, `scan_sast`, `scan_deps` | `scan.secrets`, `scan.sast`, `scan.deps` without the blocking flag of the same tool |
| `scan_secrets_blocking`, `scan_sast_blocking`, `scan_deps_blocking` | `scan.secrets_blocking`, `scan.sast_blocking`, `scan.deps_blocking` (`docs/SCANNING.md`) |

Because the `x-*` keys are not Cloud Build syntax, the file is a **Terraform-only
artifact**: `gcloud builds submit --config cloudbuild_files/cloudbuild.yaml` rejects it.
Read it with the renderer instead.

## Seeing what a service actually builds

```bash
bin/cloudbuild-render.py my-workspace --list          # every build, with its capabilities
bin/cloudbuild-render.py my-workspace my-service      # the effective pipeline, substituted
bin/cloudbuild-render.py my-workspace my-service --raw # …with ${_PLACEHOLDERS} intact
```

The renderer is a reader; Terraform is the source of truth. What keeps the two honest is
a check against a real plan:

```bash
terraform workspace select my-workspace
terraform plan -refresh=false -out=/tmp/w.plan
terraform show -json /tmp/w.plan > /tmp/w.json
bin/cloudbuild-render.py my-workspace --check-plan /tmp/w.json
```

It compares every planned trigger's steps, order, `waitFor` and substitutions with what
the renderer produces, and exits non-zero on the first disagreement. Run it whenever you
change `gcp.cloudbuild.tf` or the pipeline.

And the pipeline's own self-test, which needs no credentials:

```bash
python3 bin/cloudbuild-render-test.py    # exit 0 required
```

## Traps that have already cost time here

- **Cloud Build reads `$WORD` anywhere in the pipeline file, comments included**, as a
  substitution, and refuses a name that is not a valid builtin. Shell variables inside a
  step are lowercase; a literal dollar for the shell is `$$`.
- **`ALLOW_LOOSE` is forced on triggered builds**: an unset custom substitution becomes
  an empty string instead of an error. Nothing tells you a variable never arrived; the
  image just builds with the Dockerfile's default. A value declared under
  `substitutions:` instead of `build_args:` fails this way: an inline build never passes
  it to docker, so a dev image can ship with the production default of that argument.
- **A substitution is not expanded inside another substitution.** Everything is resolved
  in Terraform, in full, which is why `_IMAGE` is a literal path and not a template.
- **An external pipeline (`inline: false`) is handed as little as possible**: the naming
  substitutions, the registry helpers, and whatever `substitutions:` declares, never
  `_IMAGE`, `_BUILD_ARGS`, `_DOCKER_TARGET` or `_JOB_NAME`. A file this repository cannot
  read may treat an unset substitution as a signal; a common pattern is one that
  falls back to `${_IMAGE_BASE}:${SHORT_SHA}` when `$_IMAGE` is empty. Defining one for
  it would change what it builds, with no error to show it.
- **The rollout goes where the resource is.** A service may set its own `cloudrun.region`,
  different from the project's `region_name`, so the deploy step uses `_DEPLOY_REGION`
  (the service's region) and the job steps use `_JOB_REGION` (`region_name`, where
  `gcp.jobs.tf` creates every job). `gcloud run
  deploy` with the wrong region does not fail: it creates a second service.
- **Cloud Run pins the image digest at deploy time.** A job that shares a service's image
  keeps running the digest it was created with until something updates it, and that is what
  `job_name` is for.

## Image signing

With `binary_authorization.enabled: true` (`gcp.binary_auth.tf`) the workspace gets
an attestor backed by a KMS key, a policy that requires its attestation, and
`binary_authorization { use_default = true }` on every Cloud Run service and job.
The inline pipeline adds one step, `sign-image`, after `push`:

1. it reads the digest of `${_IMAGE}:${SHORT_SHA}` from Artifact Registry;
2. `gcloud beta container binauthz attestations sign-and-create` signs that digest
   with `_BINAUTH_KMS_KEY_VERSION` and stores the attestation for
   `_BINAUTH_ATTESTOR`.

`deploy-service`, `deploy-job` and `update-companion-job` wait for it, so nothing
rolls out a digest before it is signed. A build that only pushes (`deploy: false`)
is signed too. The two substitutions exist only while the flag is on, and are built
from names (`projects/<project>/attestors/<client>-<workspace>-attestor`, key ring
`<client>-<workspace>-binauth`, key `attestor-signer`, version 1), so the renderer
shows them before the first apply. The Cloud Build account gets
`binaryauthorization.attestorsViewer` on the attestor,
`containeranalysis.notes.attacher` on the note, `containeranalysis.occurrences.editor`
on the project and `cloudkms.signerVerifier` on the key, only while it is on.

The hello placeholder (`us-docker.pkg.dev/cloudrun/container/*`) is on the policy
whitelist, which is what lets the first apply of an enforcing workspace create its
services and jobs before any build has run.

### Rolling it out

Pro ships with `enforcement_mode: ENFORCED_BLOCK_AND_AUDIT_LOG`, which is right for
a new project. For a project that already serves images built before signing, go
through a dry-run first:

1. Optional rehearsal in stg: set `binary_authorization.enabled: true`
   with `enforcement_mode: DRYRUN_AUDIT_LOG_ONLY`, apply, run every trigger once,
   and check that the builds sign and the deploys log no violation. It costs one
   KMS key version; turn it off again afterwards.
2. Pro in dry-run: apply with `DRYRUN_AUDIT_LOG_ONLY`, then rebuild every service
   and job through its trigger so each one runs a signed digest.
3. Read the dry-run entries: Binary Authorization writes a Cloud Audit Log entry
   for every deploy it would have refused (Cloud Logging, search for
   `binaryauthorization` in the Cloud Run revision and job logs). Nothing left:
   switch to `ENFORCED_BLOCK_AND_AUDIT_LOG` and apply.

An emergency deploy of an unsigned image uses breakglass
(`gcloud run deploy --breakglass=<justification>`), which is logged.

### Traps

- **An external pipeline (`inline: false`) is not signed.** It is never handed the
  `_BINAUTH_*` substitutions; sign in that pipeline, or its deploys are refused once
  the policy enforces.
- **A job whose `job-config.image` points at an image no build has signed** cannot be
  created or updated while the policy enforces. Build it once in dry-run, or leave the
  image unset so the job starts on the hello placeholder.
- **A KMS key ring cannot be deleted.** Turning the flag off removes the ring from
  state and schedules the key version for destruction (30 days). Turning it on again
  in the same project needs `terraform import` of the ring and the key, and a new
  key version if the old one was destroyed (then move the attestor and the
  substitutions to it).

## Scans

`cloudbuild.scan` turns on gitleaks, semgrep and trivy fs. They are off by
default. Harbor and SonarQube are not part of this pipeline. See
`docs/SCANNING.md`.
