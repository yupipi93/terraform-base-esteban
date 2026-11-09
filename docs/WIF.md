# Workload Identity Federation (CI without keys)

`gcp.wif.tf` lets an external pipeline (GitHub Actions, GitLab CI, any OIDC
issuer) act as a service account with tokens that last one hour. The pipeline
presents the OIDC token its CI already issues; Google checks it against the
pool's provider and returns a short-lived token of the service account. No
JSON key is created, stored in a CI secret or rotated.

Nothing is created until a workspace sets `wif`. When it does, the stack
creates:

- `sts.googleapis.com` (the token exchange) and `iamcredentials.googleapis.com`,
  through the `wif` entry of `local.feature_apis`;
- one Workload Identity Pool per `wif.pools` key;
- one OIDC provider per `providers` key, with its `attribute_condition`;
- a service account `<client.name>-<key>` for each binding whose
  `service_account` is a key and not an email;
- the binding's `roles` on the project for that service account;
- `roles/iam.workloadIdentityUser` on the service account for
  `principalSet://iam.googleapis.com/<pool>/<principal_set>`.

None of these is billed. `settings/example.yaml` (section 22) documents every
key.

## The attribute condition is mandatory

A provider for `https://token.actions.githubusercontent.com` without a
condition accepts a token from any repository on github.com. The plan stops on
a provider without `attribute_condition`. Restrict it to your owner or
repository, and narrow the binding further with `principal_set`:

```yaml
wif:
  pools:
    ci-pool:
      providers:
        github:
          type: "github"
          attribute_condition: "assertion.repository_owner == 'example-org'"
      bindings:
        - service_account: "deployer"
          principal_set: "attribute.repository/example-org/example-repo"
          roles:
            - "roles/run.developer"
            - "roles/artifactregistry.writer"
```

For deploys from one branch only, put it in the condition
(`assertion.repository == 'example-org/example-repo' && assertion.ref == 'refs/heads/main'`)
or bind `principal_set: "attribute.ref/refs/heads/main"`.

The pool and provider keys are their ids: 4 to 32 lowercase letters, digits or
hyphens, not starting with `gcp-` (the plan stops otherwise). A deleted pool or
provider id stays reserved for 30 days. Pick keys you will keep.

## GitHub Actions

Read the provider name once after the apply:

```bash
gcloud iam workload-identity-pools providers describe github \
  --project=example-app-dev --location=global --workload-identity-pool=ci-pool \
  --format='value(name)'
```

`terraform output wif_providers` prints the same name for every provider (keyed
`<pool>/<provider>`), and `terraform output wif_service_accounts` the email of
each binding's account.

Then, in the workflow:

```yaml
permissions:
  contents: read
  id-token: write   # lets the job request its OIDC token

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/123456789/locations/global/workloadIdentityPools/ci-pool/providers/github
          service_account: app-deployer@example-app-dev.iam.gserviceaccount.com
      - uses: google-github-actions/setup-gcloud@v2
      - run: gcloud run services list --project=example-app-dev
```

A binding key creates the account `<client.name>-<key>`, so with the default
`client.name: app` the key `deployer` becomes
`app-deployer@<project id>.iam.gserviceaccount.com`. The provider name and the
service account email are not secrets; they can live in repository variables.

## GitLab CI

Use `type: gitlab` (`issuer_uri` defaults to `https://gitlab.com`; set it for a
self-managed instance). `attribute.repository` maps to the project path, so the
same `principal_set` form works. In the job, request an `id_tokens` entry whose
`aud` is `https://iam.googleapis.com/<provider name>` and pass it to
`gcloud iam workload-identity-pools create-cred-config`.

## No service account keys

No resource in this repository creates a `google_service_account_key`. Keep it
that way: a pipeline that needs Google credentials uses this file. Pro's
`monitoring.log_alerts.service_account_key_created` alerts when someone creates
a key by hand.
