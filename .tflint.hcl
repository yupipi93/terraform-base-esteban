# tflint for the root module: `tflint --init`, then `tflint` from the repository
# root (CI runs the same, pre-commit too).
#
# modules/ is not linted: neither `--recursive` nor module calls
# (call_module_type = "none"). The modules are vendored snapshots that change only
# through a new version directory (docs/audit/OPERATING.md), and they carry 31
# findings of their own (missing required_version and provider constraints,
# unused declarations, deprecated interpolation). Fix those in the module's next
# version, then lint that directory with `tflint --chdir modules/<name>`.

config {
  call_module_type = "none"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Most arguments come from the settings YAML and are unknown to tflint, so these
# rules catch literals: machine types, regions, invalid names.
plugin "google" {
  enabled = true
  version = "0.41.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
