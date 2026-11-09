## Summary

<!-- What changes and why, in two or three sentences. -->

Backlog item: <!-- AUD-XXX from docs/audit/BACKLOG.md, or "none" with the issue it comes from -->

## Changes

<!-- One line per file or group of files. -->

-

## Validation

<!-- The checks of CONTRIBUTING.md. Tick what you ran; say why for anything skipped. -->

- [ ] `terraform fmt -check` on the root files and tests
- [ ] `tflint` on the root module
- [ ] `terraform init -backend=false` and `terraform validate`
- [ ] `terraform validate` in dev, stg, pre and pro with a local backend override
- [ ] `terraform test`
- [ ] `python3 bin/validate-settings.py`
- [ ] `python3 bin/cloudbuild-render-test.py`
- [ ] `python3 bin/audit-terraform.py --fail-on p0`
- [ ] `python3 bin/audit-terraform.py --id <ID>` exits 0, and `docs/audit/BACKLOG.md` refreshed with `--write`
- [ ] `python3 bin/audit-terraform.py --leaks` (with the private denylist, if you have one) prints no `leak` line
- [ ] New settings keys are in `schemas/settings.schema.json`, `settings/example.yaml` and the matching doc
- [ ] No cost increase in dev or stg

## Rollback

<!-- How to undo it: revert the commit, and anything a revert does not undo (state moves, resources to delete by hand). -->

<!-- Nobody applies from a pull request. An apply is a separate, explicit decision by the owner of the target project. -->
