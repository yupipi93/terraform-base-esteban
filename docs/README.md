# Documentation

Every page under `docs/`, grouped by what you are doing.

## Setting up

- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md): what each file and directory holds.
- [ENVIRONMENTS.md](ENVIRONMENTS.md): the dev, stg and pro reference workspaces, their cost and what differs between them.
- [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md): the settings files, validation, labels, APIs, services, buckets, private networking and access.

## Building and deploying

- [cloudbuild-pipeline.md](cloudbuild-pipeline.md): the shared Cloud Build pipeline, every build key, optional steps and image signing.
- [cloudbuild-tag-patterns.md](cloudbuild-tag-patterns.md): which tag or branch push starts a build.
- [cloudrun-service-resources.md](cloudrun-service-resources.md): what one entry under `app.service` creates.
- [WIF.md](WIF.md): external CI (GitHub Actions, GitLab CI) without service account keys.

## Data, secrets and security

- [STORAGE.md](STORAGE.md): bucket lifecycle rules, retention policies and access logs.
- [SOPS.md](SOPS.md): secret values from SOPS-encrypted files.
- [SCANNING.md](SCANNING.md): secret, code, dependency and image scanning.
- [COMPLIANCE.md](COMPLIANCE.md): what the pro workspace gives an auditor, mapped to ISO 27001, SOC 2 and GDPR, and what stays with you.
- [billing-budget-control.md](billing-budget-control.md): the budget, its alerts and the optional billing shutdown.

## Maintaining the template

- [audit/OPERATING.md](audit/OPERATING.md): how backlog items are worked, validated and reviewed.
- [audit/BACKLOG.md](audit/BACKLOG.md): the generated backlog, open and done.
