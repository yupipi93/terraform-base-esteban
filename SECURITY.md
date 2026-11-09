# Security policy

## Reporting a vulnerability

Report it privately through GitHub security advisories: the repository's
**Security** tab, then **Report a vulnerability**
([direct link](../../security/advisories/new)). Only the maintainers see the
report until an advisory is published.

Please include:

- what is affected (a root file, a module directory, a settings key, a script);
- how to reproduce it, ideally with a minimal `settings/<workspace>.yaml` and the
  `terraform plan` output with project ids and names replaced;
- the impact you expect (exposed data, privilege, a resource made public).

The maintainers answer on the advisory itself. A fix lands through a normal pull
request, and the advisory credits the reporter unless asked otherwise.

## Never put secrets in an issue

Do not paste credentials, tokens, keys, passwords, state files, real project ids,
billing account ids or email addresses into an issue, a pull request, a
discussion or an advisory. Refer to a secret by its Secret Manager name. If a
secret was exposed, rotate it first, then report.

## Supported versions

Only `main` is supported. There are no release branches; fixes go to `main`, and
`CHANGELOG.md` lists them.

## Scope

In scope:

- Terraform in this repository (root files, `modules/`, `tests/`) that creates a
  resource more open than its settings say: public access, broader IAM, missing
  encryption in transit, a protection that does not apply;
- the reference settings (`settings/*.yaml`) and their defaults;
- the scripts under `bin/`, the Cloud Build pipeline in `cloudbuild_files/` and
  the function in `cloud_function_source/`;
- the CI workflow in `.github/`.

Out of scope:

- vulnerabilities in Google Cloud, Terraform, the providers or third-party tools
  (report those to their owners);
- a project deployed from this template with its own changes or settings;
- the placeholder values of the reference files, which are not meant to be
  applied as they are;
- choices recorded as accepted in `docs/audit/BACKLOG.md` (for example no CMEK by
  default, no VPC Service Controls), unless you show a concrete exploit.
