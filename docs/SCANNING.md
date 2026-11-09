# Scanning without a second product

Harbor and SonarQube stay out. They need a host, robots and a token, and this
template does not have that instance. The scans below run in the build or in
Artifact Registry.

## Cloud Build

Off until a build asks. Set them under `scan` in the `cloudbuild` block of a
service, a job or a top-level `cloudbuild` entry. A blocking flag wins over the
report-only flag of the same tool.

| Key | Tool | What it does |
|---|---|---|
| `secrets` | gitleaks v8.30.1 | report leaked secrets, and keep building |
| `secrets_blocking` | gitleaks v8.30.1 | fail the build on a leaked secret |
| `sast` | semgrep 1.184.0, ruleset `p/default` | report findings |
| `sast_blocking` | semgrep 1.184.0 | fail the build on a finding |
| `deps` | trivy 0.76.2 `fs` | report HIGH and CRITICAL |
| `deps_blocking` | trivy 0.76.2 `fs` | fail the build on HIGH or CRITICAL |

`settings/pro.yaml` turns on `secrets_blocking`, `sast` and `deps` for the
example service. Dev and stg (and pre) leave them off.

The steps sit before `docker build` and only run in the inline pipeline
(`inline: true`). Dropped steps are removed from `waitFor`, so a service with
no scans still builds.

## Artifact Registry

`security.artifact_scanning: true` enables `containerscanning.googleapis.com`.
Google scans images after they land in Artifact Registry. Pro sets this; dev
and stg do not, because the scan is billed per image. It is not a registry you
install yourself.
