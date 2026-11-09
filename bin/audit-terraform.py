#!/usr/bin/env python3
"""Audit this Terraform template for a public, production-grade release.

Every backlog item has a mechanical check that reads the repository. The
status in docs/audit/BACKLOG.md comes from those checks, never from a tick by
hand. Two goals drive the list:

- dev and stg stay cheap: zonal, small, scale to zero, short retention;
- pro passes a security, backup and data-retention audit.

    python3 bin/audit-terraform.py              # print the backlog
    python3 bin/audit-terraform.py --next       # the next item to work on
    python3 bin/audit-terraform.py --id AUD-X   # one item, exit 1 while open
    python3 bin/audit-terraform.py --write      # refresh docs/audit/BACKLOG.md
    python3 bin/audit-terraform.py --fail-on p0

The leak scan reads extra forbidden terms, one regular expression per line,
from the file named by AUDIT_DENYLIST or from .audit-denylist at the repo
root. That file is gitignored: a fork keeps its own private names in it.

Exit 0 unless --fail-on is set and an open item is at that severity or above.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]

SEVERITY_RANK = {"p0": 0, "p1": 1, "p2": 2, "p3": 3}

TEXT_SUFFIXES = {".tf", ".hcl", ".md", ".yaml", ".yml", ".py", ".json", ".svg", ".sh", ".txt", ""}


# ---------------------------------------------------------------- helpers


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def exists(rel: str) -> bool:
    return (ROOT / rel).exists()


def globbed(pattern: str) -> list[Path]:
    return sorted(ROOT.glob(pattern))


def read_any(pattern: str) -> str:
    return "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in globbed(pattern) if p.is_file())


def root_tf() -> str:
    return read_any("*.tf")


def workflows() -> str:
    return read_any(".github/workflows/*.yml") + read_any(".github/workflows/*.yaml")


def tracked_files() -> list[str]:
    try:
        out = subprocess.run(
            ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout
        return [line for line in out.splitlines() if line]
    except (OSError, subprocess.CalledProcessError):
        return [str(p.relative_to(ROOT)) for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.parts]


def tracked_text() -> list[tuple[str, str]]:
    files = []
    for rel in tracked_files():
        path = ROOT / rel
        if path.suffix not in TEXT_SUFFIXES or not path.is_file():
            continue
        files.append((rel, path.read_text(encoding="utf-8", errors="replace")))
    return files


def denylist() -> list[re.Pattern]:
    source = os.environ.get("AUDIT_DENYLIST") or str(ROOT / ".audit-denylist")
    path = Path(source)
    if not path.is_file():
        return []
    patterns = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            patterns.append(re.compile(line, re.IGNORECASE))
    return patterns


REAL_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]{2,}")
EMAIL_ALLOWED = re.compile(
    r"@((my|your-?)?(example|domain|company|org)\.(com|org|net)"
    r"|users\.noreply\.github\.com|project\.iam|.*\.gserviceaccount\.com)$",
    re.IGNORECASE,
)


def leak_hits() -> list[str]:
    patterns = denylist()
    hits = []
    for rel, text in tracked_text():
        if rel == ".terraform.lock.hcl":
            continue
        for number, line in enumerate(text.splitlines(), 1):
            for pattern in patterns:
                if pattern.search(line):
                    hits.append(f"{rel}:{number}")
            for match in REAL_EMAIL.finditer(line):
                address = match.group(0)
                if "${" in line or EMAIL_ALLOWED.search(address) or address.startswith("git@"):
                    continue
                hits.append(f"{rel}:{number}: {address}")
    return hits


SPANISH = re.compile(
    r"[áéíóúñ¿¡]|\b(para|los|las|una|esta|este|desde|cuando|también"
    r"|permite|ejecutar|servicios?|despliegue|usuarios?|cuentas?|configuracion)\b",
    re.IGNORECASE,
)
EM_DASH = re.compile("\u2014")


def prose_hits(pattern: re.Pattern) -> list[str]:
    hits = []
    for rel, text in tracked_text():
        if rel.startswith("docs/audit/") or rel == "bin/audit-terraform.py":
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if pattern.search(line):
                hits.append(f"{rel}:{number}")
    return hits


def spanish_hits() -> list[str]:
    return prose_hits(SPANISH)


def em_dash_hits() -> list[str]:
    return prose_hits(EM_DASH)


def yaml_has(name: str, *pieces: str) -> bool:
    text = read(f"settings/{name}.yaml")
    return bool(text) and all(piece in text for piece in pieces)


def block(text: str, start: str, size: int = 600) -> str:
    index = text.find(start)
    return text[index : index + size] if index >= 0 else ""


def runs_ok(*cmd: str, env: dict[str, str] | None = None) -> bool:
    try:
        return subprocess.run(
            list(cmd), cwd=ROOT, capture_output=True, timeout=120, env={**os.environ, **(env or {})}
        ).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


# ------------------------------------------------------- phase 1 checks


def network_is_optional() -> bool:
    text = read("gcp.network.tf")
    return "count " in text and "network_enabled" in text


def bucket_is_guarded() -> bool:
    return "try(local.settings.bucket" in read("gcp.storage.tf")


def firewall_uses_settings_cidr() -> bool:
    text = read("gcp.firewall.tf")
    return "10.20.0.0/24" not in text and "services_cidr" in text


def vpc_follows_network() -> bool:
    return "local.network_enabled" in read("gcp.cloudrun.tf") and "local.network_enabled" in read("gcp.jobs.tf")


def audit_admin_read_on() -> bool:
    return "security.audit_logging.admin_read" in read("gcp.security.tf")


def deletion_protection_from_settings() -> bool:
    return "cloudrun.deletion_protection" in read("gcp.cloudrun.tf") and "job-config.deletion_protection" in read("gcp.jobs.tf")


def insights_from_settings() -> bool:
    return "sql.insights" in read("gcp.sql.tf")


ENV_KEYS = ("project:", "security:", "network:", "database:", "app:", "budget:", "lb:")


def stg_settings() -> bool:
    return yaml_has("stg", *ENV_KEYS) or yaml_has("pre", *ENV_KEYS)


def pro_settings() -> bool:
    return yaml_has("pro", *ENV_KEYS) and yaml_has("pro", 'availability: "REGIONAL"', "min_instances: 1")


def lockfile_committed() -> bool:
    ignored = any(line.strip() == "*.lock.hcl" for line in read(".gitignore").splitlines())
    return (not ignored) and exists(".terraform.lock.hcl")


def ci_validates() -> bool:
    return "terraform validate" in workflows()


def sops_provider() -> bool:
    return "carlpett/sops" in read("versions.tf")


def provider_major_7() -> bool:
    versions = read("versions.tf")
    return 'source  = "hashicorp/google"' in versions and "~> 7." in versions


def storage_module_has_pap() -> bool:
    return "public_access_prevention" in read_any("modules/*storage*/vars.tf")


def common_labels() -> bool:
    return "common_labels" in read("locals.tf")


def sql_databases_from_yaml() -> bool:
    return "for service in local.service_names" not in read("gcp.sql.tf")


def pubsub_agent_optional() -> bool:
    return "count " in read("gcp.pubsub.tf").split("google_project_service_identity", 1)[-1][:400]


def binary_auth_can_enforce() -> bool:
    return "ALWAYS_ALLOW" not in read("gcp.binary_auth.tf")


def log_retention() -> bool:
    return "google_logging_project_bucket_config" in root_tf()


def codeowners() -> bool:
    return exists("CODEOWNERS") or exists(".github/CODEOWNERS")


def agents_guide() -> bool:
    text = read("AGENTS.md")
    return "bin/audit-terraform.py" in text and "BACKLOG.md" in text


# ------------------------------------------------------- phase 2 checks


def no_leaks() -> bool:
    return not leak_hits()


def elastic_from_settings() -> bool:
    text = read("gcp.elastic.psc.tf")
    if not text:
        return True
    return not re.search(r'"projects/[a-z][a-z0-9-]+-\d+/', text) and "local.settings" in text


def sql_module_pitr() -> bool:
    sql = read("gcp.sql.tf")
    match = re.search(r'source\s*=\s*"\./(modules/[^"]+)"', sql)
    if not match:
        return False
    module = read_any(f"{match.group(1)}/*.tf")
    return "point_in_time_recovery_enabled" in module and "transaction_log_retention_days" in module


def sql_pro_hardened() -> bool:
    return yaml_has(
        "pro",
        "log_connections",
        "log_disconnections",
        "log_min_duration_statement",
        "cloudsql.enable_pgaudit",
        "special_password",
    )


def audit_log_archive() -> bool:
    logging = read("gcp.logging.tf")
    return (
        "google_logging_project_sink" in logging
        and "locked" in logging
        and "audit_archive" in logging
        and yaml_has("pro", "audit_archive")
    )


def bucket_retention_options() -> bool:
    module = read_any("modules/*storage*/*.tf")
    return (
        "retention_policy" in module
        and "logging" in module
        and ("days_since_noncurrent_time" in read("settings/pro.yaml") or "noncurrent" in read("settings/pro.yaml"))
    )


def redis_protection_from_settings() -> bool:
    text = read("gcp.redis.tf")
    return "prevent_destroy = true" not in text and "persistence_config" in text and "deletion_protection" in text


def log_based_alerts() -> bool:
    tf = root_tf()
    return "condition_matched_log" in tf and "log_alerts" in tf and yaml_has("pro", "log_alerts")


def lb_alerts_and_uptime() -> bool:
    return "google_monitoring_uptime_check_config" in root_tf() and yaml_has("pro", "status_5xx", "uptime")


def secret_access_alerts() -> bool:
    return "secret_access" in root_tf() and yaml_has("pro", "secret_access")


def workload_identity() -> bool:
    text = read("gcp.wif.tf")
    return "google_iam_workload_identity_pool" in text and "try(local.settings.wif" in text and "wif:" in read("settings/example.yaml")


def binauth_pro_enforced() -> bool:
    pipeline = read_any("cloudbuild_files/*.yaml") + read("gcp.cloudbuild.tf")
    return yaml_has("pro", "ENFORCED_BLOCK_AND_AUDIT_LOG") and ("attestations" in pipeline or "binauthz" in pipeline)


def tls_policy_from_settings() -> bool:
    return "lb.ssl_policy" in read("gcp.lb.tf") and yaml_has("pro", "RESTRICTED")


def plan_guards() -> bool:
    security = read("gcp.security.tf")
    apis = read("gcp.enabled.apis.tf")
    sql = read("gcp.sql.tf")
    run = read("gcp.cloudrun.tf")
    ingress_default = re.search(r"ingress\s*=\s*try\([^\n]*\)", run)
    return (
        ("try(local.settings.security.alerts_email" in security or 'check "alerts_email"' in root_tf())
        and "try(local.settings.active-apis" in apis
        and "depends_on = [module.network]" not in sql
        and bool(ingress_default)
        and "lb_enabled" in ingress_default.group(0)
    )


def no_always_on_resources() -> bool:
    cloudbuild = read("gcp.cloudbuild.tf")
    sa = block(cloudbuild, 'resource "google_service_account" "cloudbuild"', 300)
    bucket = block(cloudbuild, 'module "cloudbuild_artifacts_bucket"', 300)
    iap = block(read("gcp.iam.tf"), "google_project_service_identity", 300)
    return all(("count" in part or "for_each" in part) for part in (sa, bucket)) and "count = 1" not in iap


def provider_default_labels() -> bool:
    return read("providers.tf").count("default_labels") >= 2


def root_outputs() -> bool:
    return len(re.findall(r'^output "', read("outputs.tf"), re.M)) >= 4


def partial_backend() -> bool:
    versions = read("versions.tf")
    return re.search(r'backend "gcs" \{\s*\}', versions) is not None and exists("backend.hcl.example")


def settings_schema() -> bool:
    # SETTINGS_SCHEMA_OPTIONAL=1: without PyYAML the validator still runs its
    # cross-checks (keys read by the .tf files and top-level keys of every
    # settings file against the schema) and skips only the full validation, so
    # the status does not depend on the local Python packages. CI runs it all.
    return (
        exists("schemas/settings.schema.json")
        and exists("bin/validate-settings.py")
        and "validate-settings.py" in workflows()
        and runs_ok(sys.executable, "bin/validate-settings.py", env={"SETTINGS_SCHEMA_OPTIONAL": "1"})
    )


def terraform_tests() -> bool:
    tests = read_any("tests/*.tftest.hcl")
    return "mock_provider" in tests and "terraform test" in workflows()


def ci_matrix() -> bool:
    flows = workflows()
    return all(ws in flows for ws in ("dev", "stg", "pro")) and "cloudbuild-render-test.py" in flows and "TF_WORKSPACE" in flows


def ci_runner_pinned() -> bool:
    flows = workflows()
    return (
        bool(flows)
        and "ubuntu-latest" not in flows
        and not re.search(r"actions/checkout@v[1-5]\b|setup-terraform@v[1-3]\b|setup-python@v[1-5]\b", flows)
    )


def lint_tooling() -> bool:
    return exists(".tflint.hcl") and exists(".pre-commit-config.yaml") and "tflint" in workflows()


def cost_safe_defaults() -> bool:
    billing = read("gcp.billing.tf")
    run = read("gcp.cloudrun.tf")
    cpu_idle = re.search(r"cpu_idle\s*=\s*try\([^\n]*\)", run)
    return "enable_auto_stop, false)" in billing and bool(cpu_idle) and "pro" in cpu_idle.group(0)


def cost_profiles() -> bool:
    dev = read("settings/dev.yaml")
    stg = read("settings/stg.yaml")
    if not dev or not stg:
        return False
    dev_tier = re.search(r'tier:\s*"(db-[^"]+)"', dev)
    stg_tier = re.search(r'tier:\s*"(db-[^"]+)"', stg)
    retained = re.search(r"retained_backups:\s*(\d+)", dev)
    return (
        "\nredis:" not in dev
        and "nats:" not in dev
        and bool(dev_tier)
        and dev_tier.group(1) in ("db-f1-micro", "db-g1-small")
        and bool(stg_tier)
        and stg_tier.group(1) != dev_tier.group(1)
        and bool(retained)
        and int(retained.group(1)) <= 7
        and "# Pre workspace" not in dev
    )


def feature_apis() -> bool:
    text = read("gcp.enabled.apis.tf") + read("locals.tf")
    return "feature_apis" in text and "sqladmin.googleapis.com" in text


def clean_names() -> bool:
    stamped = [p for p in globbed("modules/*") if re.search(r"-\d{12}$", p.name)]
    allowed = {"locals.tf", "providers.tf", "versions.tf", "outputs.tf"}
    bad_files = [
        p.name
        for p in globbed("*.tf")
        if p.name not in allowed and not re.fullmatch(r"(gcp|oracle)(\.[a-z0-9_]+)+\.tf", p.name)
    ]
    return not stamped and not bad_files


def english_only() -> bool:
    return not spanish_hits() and not em_dash_hits()


def readme_showcase() -> bool:
    readme = read("README.md")
    lower = readme.lower()
    return (
        "img.shields.io" in readme
        and "```mermaid" in readme
        and "quick start" in lower
        and all(ws in readme for ws in ("`dev`", "`stg`", "`pro`"))
        and "## cost" in lower
        and "## security" in lower
        and "docs/README.md" in readme
        and exists("docs/README.md")
        and all(p.name in read("docs/README.md") for p in globbed("docs/*.md") if p.name != "README.md")
        and "`dns_zones`" in readme
        and "sops_kms_key" in readme
        and "always created" not in lower
        and "platform features" not in lower
        and "rules i'd" not in lower
    )


# ------------------------------------------------------- round 2 checks


def module_source(rootfile: str, block_name: str) -> str:
    text = read(rootfile)
    match = re.search(r'module "' + re.escape(block_name) + r'"\s*\{[^}]*?source\s*=\s*"\./([^"]+)"', text, re.S)
    return read_any(f"{match.group(1)}/*.tf") if match else ""


def private_service_access() -> bool:
    module = module_source("gcp.network.tf", "network")
    root = root_tf()
    created = "google_service_networking_connection" in module or "google_service_networking_connection" in root
    return created and "google_compute_global_address" in (module + root) and "services_ip_ranges" in (module + root)


def project_number_resolved() -> bool:
    tf = root_tf()
    return 'data "google_project"' in tf or 'check "project_number' in tf


def operators_scoped() -> bool:
    iam = read("gcp.iam.tf")
    return not re.search(r'google_project_iam_member"\s+"run_invokers"', iam) and not re.search(
        r'resource "google_project_iam_member"[^}]*roles/iam\.serviceAccountUser', iam, re.S
    )


def dev_without_lb() -> bool:
    dev = read("settings/dev.yaml")
    amount = re.search(r"amount:\s*(\d+)", dev)
    return "\nlb:" not in dev and bool(amount) and int(amount.group(1)) >= 25 and "INTERNAL_LOAD_BALANCER" not in dev


def security_metric_alerts_toggle() -> bool:
    return "metric_alerts" in read("gcp.security.tf") and "metric_alerts" in module_source("gcp.security.tf", "basic_security")


def secret_alert_yaml_readers() -> bool:
    text = read("gcp.monitoring.tf")
    return "standalone" in text and "external" in text and "secret_access_stack_principals" in text


def input_guards() -> bool:
    elastic = read("gcp.elastic.psc.tf")
    monitoring = read("gcp.monitoring.tf")
    return (
        re.search(r"condition\s*=[^\n]*network_enabled", elastic) is not None
        and re.search(r"condition\s*=[^\n]*>=\s*300", monitoring) is not None
        and re.search(r"condition\s*=[^\n]*>=\s*1800", monitoring) is not None
    )


def sa_key_policy() -> bool:
    return "iam.disableServiceAccountKeyCreation" in root_tf()


def essential_contacts() -> bool:
    return "google_essential_contacts_contact" in root_tf()


def dev_sql_disposable() -> bool:
    dev = read("settings/dev.yaml")
    section = dev.split("\ndatabase:", 1)[-1] if "\ndatabase:" in dev else ""
    return "deletion_protection: false" in section.split("\nredis:", 1)[0]


def firestore_pro_defaults() -> bool:
    text = read("gcp.firestore.tf")
    return "local.workspace == \"pro\"" in text and "DELETE_PROTECTION_ENABLED" in text


def docs_current() -> bool:
    tags = read("docs/cloudbuild-tag-patterns.md")
    cloudrun = read("docs/cloudrun-service-resources.md")
    structure = read("docs/PROJECT_STRUCTURE.md")
    example = read("settings/example.yaml")
    return (
        "project.cloudbuild.tf" not in tags
        and "gcp.cloudbuild.tf" in tags
        and "dns_zones" in example
        and re.search(r"^#?\s*sops:", example, re.M) is not None
        and "PRIVATE_RANGES_ONLY" in cloudrun
        and "pre-2025" not in cloudrun
        and "The first plan after this change" not in read("docs/CONFIGURATION_GUIDE.md")
        and all(name in structure for name in ("dev.yaml", "stg.yaml", "pro.yaml"))
        and "production baseline" not in read("AGENTS.md").lower()
        and "another platform" not in read("docs/SOPS.md")
        and "Pre leaves" not in read("docs/SCANNING.md")
    )


def oss_files() -> bool:
    return all(
        exists(path)
        for path in (
            "CONTRIBUTING.md",
            "SECURITY.md",
            "CHANGELOG.md",
            ".github/pull_request_template.md",
            ".github/ISSUE_TEMPLATE",
        )
    )


def compliance_doc() -> bool:
    text = read("docs/COMPLIANCE.md")
    return all(term in text for term in ("ISO 27001", "SOC 2", "GDPR", "settings/pro.yaml")) and "COMPLIANCE.md" in read("README.md")


# ----------------------------------------------------------------- items


@dataclass
class Item:
    id: str
    severity: str
    title: str
    why: str
    change: str
    ok: Callable[[], bool] = lambda: True
    disposition: str = "fix"
    after: list[str] = field(default_factory=list)


ACCEPTED = "accepted"

ITEMS: list[Item] = [
    # Phase 1: the template becomes a stack with dev, stg and pro.
    Item("AUD-NET", "p0", "The shared VPC is created even when the workspace has no network section",
         "A workspace without network.services_cidr must plan without a VPC.",
         "Gate module.network on local.network_enabled.", network_is_optional),
    Item("AUD-VPC-DEFAULT", "p0", "Cloud Run and jobs attach to the VPC by default",
         "With the VPC optional, the attachment must follow it.",
         "Default vpc_access_enabled to local.network_enabled.", vpc_follows_network),
    Item("AUD-FW-CIDR", "p1", "The internal firewall allows two CIDRs the VPC does not have",
         "Firewall ranges come from the settings, not from hardcoded ranges.",
         "Read network.services_cidr.", firewall_uses_settings_cidr),
    Item("AUD-BUCKET", "p0", "A workspace with no bucket key cannot plan",
         "A missing settings section creates nothing.", "Wrap the map in try().", bucket_is_guarded),
    Item("AUD-AUDIT", "p0", "Admin-read audit logs are off",
         "Admin reads are the trail after an IAM change.", "Default admin_read to true.", audit_admin_read_on),
    Item("AUD-DELETE", "p0", "Cloud Run services and jobs can be destroyed with deletion_protection left false",
         "Pro must opt out of protection, not opt in.", "Read deletion_protection from the YAML, true in pro.",
         deletion_protection_from_settings),
    Item("AUD-INSIGHTS", "p1", "Cloud SQL Query Insights cannot be turned on",
         "Slow queries need a trace in pro.", "Pass sql.insights to the module.", insights_from_settings),
    Item("AUD-PRE", "p1", "There is no stg workspace", "A reference staging file shows the cheap shape.",
         "Add settings/stg.yaml.", stg_settings),
    Item("AUD-PRO", "p1", "There is no pro workspace", "A reference production file shows the hardened shape.",
         "Add settings/pro.yaml.", pro_settings),
    Item("AUD-LOCK", "p1", "The provider lock file is gitignored", "Every clone must use the same provider builds.",
         "Commit .terraform.lock.hcl.", lockfile_committed),
    Item("AUD-CI", "p1", "Nothing checks fmt or validate on a pull request", "A broken file must not reach main.",
         "Add a workflow with fmt and validate.", ci_validates),
    Item("AUD-SOPS", "p1", "Secret values have no sealed path into the plan",
         "An optional SOPS path keeps values encrypted in git.", "Add the SOPS provider and gcp.sops.tf.", sops_provider),
    Item("AUD-PROVIDER", "p2", "The Google provider is pinned to 6.x", "New arguments and fixes land in 7.x.",
         "Move both Google providers to ~> 7.42.", provider_major_7),
    Item("AUD-PAP", "p2", "Buckets cannot set public access prevention", "A bucket must not be made public by mistake.",
         "Add public_access_prevention to the storage module.", storage_module_has_pap),
    Item("AUD-LABELS", "p2", "Resources do not share an environment label", "Bills and asset searches filter by label.",
         "Add common_labels in locals.tf.", common_labels),
    Item("AUD-SQL-SCHEMA", "p2", "Every Cloud Run service gets a database on every SQL instance",
         "Databases and users come from the instance YAML.", "Read databases and users per instance.",
         sql_databases_from_yaml),
    Item("AUD-PUBSUB-AGENT", "p3", "The Pub/Sub service identity is created in every workspace",
         "Only a workspace with topics needs it.", "Count it on the topics map.", pubsub_agent_optional),
    Item("AUD-BINAUTH", "p2", "Binary Authorization, when turned on, only dry-runs an allow-all rule",
         "Turning it on must be able to reject an unsigned image.", "Require an attestation.", binary_auth_can_enforce),
    Item("AUD-LOGS", "p3", "Log buckets keep the Google default retention", "Retention is a per-workspace decision.",
         "Set _Default retention from logging.retention_days.", log_retention),
    Item("AUD-CODEOWNERS", "p3", "No CODEOWNERS file", "A pro change needs a named reviewer.", "Add CODEOWNERS.", codeowners),
    Item("AUD-AGENTS", "p1", "A session that opens this repo has no operating rules",
         "Agents and people need the same procedure.", "Add AGENTS.md and docs/audit/OPERATING.md.", agents_guide),

    # Phase 2: public release, cost profile and a pro that passes an audit.
    Item("AUD-PUB-LEAKS", "p0", "Tracked files name private companies, products, people or real addresses",
         "The repository is public and generic. A name from the project it was cut from, a real email or a real "
         "project id tells a reader where it came from and can expose that party. The scan uses the generic email "
         "check plus the private denylist described in the module docstring.",
         "Reword every hit generically. Run with AUDIT_DENYLIST pointing at the fork's private list.", no_leaks),
    Item("AUD-PUB-ELASTIC", "p1", "The Elastic Private Service Connect target is a literal project path",
         "gcp.elastic.psc.tf hardcodes a provider-side service attachment. A different region or deployment "
         "cannot use it, and the template should not ship a third party's project id as a default.",
         "Read the attachment, region and name from settings.elastic_psc. Create nothing when the key is absent. "
         "Document it in settings/example.yaml.", elastic_from_settings),
    Item("AUD-SQL-PITR", "p1", "Point-in-time recovery in the YAML never reaches Cloud SQL",
         "settings/pro.yaml sets backup.point_in_time_recovery_enabled, but the vendored Cloud SQL module has no "
         "such argument, so pro restores only from the nightly backup. Any audit asks for an RPO measured in minutes.",
         "Copy the module to a new version directory, add point_in_time_recovery_enabled and "
         "transaction_log_retention_days to backup_configuration, and point gcp.sql.tf at it.", sql_module_pitr),
    Item("AUD-SQL-HARDEN", "p1", "Pro PostgreSQL has no connection or statement audit trail",
         "Auditors ask who connected and what ran. Pro sets only max_connections, and generated passwords have "
         "no special characters.",
         "In settings/pro.yaml add log_connections, log_disconnections, log_min_duration_statement, "
         "cloudsql.enable_pgaudit and pgaudit.log flags, and special_password enabled. Keep dev and stg without them.",
         sql_pro_hardened, after=["AUD-SQL-PITR"]),
    Item("AUD-AUDIT-ARCHIVE", "p1", "Audit logs are not archived in a locked bucket",
         "Admin activity stays 400 days in _Required, but data access and policy-denied logs follow _Default, which "
         "a project owner can shorten or delete. Retention evidence needs a sink an admin cannot quietly purge.",
         "Add logging.audit_archive (retention_days, locked) and a sink of cloudaudit.googleapis.com logs to a "
         "dedicated log bucket. Pro: 365 days, locked. Dev and stg: absent.", audit_log_archive),
    Item("AUD-GCS-RETENTION", "p2", "Buckets cannot set a retention policy or access logs, and pro keeps old versions forever",
         "Versioning without a lifecycle keeps every deleted object, which breaks data minimisation. A regulated "
         "bucket also needs an optional retention policy and access logs.",
         "Copy the storage module to a new version with retention_policy and logging. In pro, delete noncurrent "
         "versions after a set number of days.", bucket_retention_options),
    Item("AUD-REDIS", "p2", "Redis blocks destroy in every workspace and has no persistence option",
         "prevent_destroy = true is a literal, so dev cannot be torn down, while pro has no RDB snapshot.",
         "Replace prevent_destroy with deletion_protection from the YAML (true in pro) and add persistence_config.",
         redis_protection_from_settings),
    Item("AUD-MON-LOG-ALERTS", "p1", "No alert fires on IAM, firewall, service account key or audit config changes",
         "These are the controls an auditor samples first. The security module covers only part of them.",
         "Add gcp.monitoring.tf with log-based alert policies driven by monitoring.log_alerts. Enable them in pro.",
         log_based_alerts),
    Item("AUD-MON-LB", "p2", "Pro has no load balancer error alerts and no uptime check",
         "The LB monitoring module exists, but pro sets no monitoring.lb block, and nothing probes the public domain.",
         "Set monitoring.lb (5xx, latency, Cloud Armor 403) in pro and add google_monitoring_uptime_check_config "
         "driven by monitoring.uptime.", lb_alerts_and_uptime, after=["AUD-MON-LOG-ALERTS"]),
    Item("AUD-SECRET-ACCESS", "p2", "Nobody is alerted when a secret is read by an unexpected principal",
         "Secret reads are invisible without data access logs for Secret Manager and an alert on them.",
         "Add monitoring.secret_access: data access audit logs on secretmanager.googleapis.com and a log alert "
         "excluding the expected service accounts. Enable it in pro.", secret_access_alerts,
         after=["AUD-MON-LOG-ALERTS"]),
    Item("AUD-WIF", "p1", "External CI can only authenticate with a service account key",
         "Long-lived keys are the first finding in any cloud audit. Workload Identity Federation removes them.",
         "Add gcp.wif.tf driven by settings.wif (pool, providers for GitHub Actions or another OIDC issuer, "
         "attribute_condition, bound service account). Document it in settings/example.yaml.", workload_identity),
    Item("AUD-BINAUTH-PRO", "p2", "Pro turns Binary Authorization on but never blocks",
         "Dry-run records violations and deploys them anyway. Pro should enforce once the pipeline signs images.",
         "Sign images in the Cloud Build pipeline when binary_authorization.enabled, then set pro to "
         "ENFORCED_BLOCK_AND_AUDIT_LOG.", binauth_pro_enforced),
    Item("AUD-TLS", "p2", "The TLS profile is hardcoded", "Pro should be able to require RESTRICTED without a code change.",
         "Read lb.ssl_policy.profile and min_tls_version, MODERN by default, RESTRICTED in pro.", tls_policy_from_settings),
    Item("AUD-TF-GUARDS", "p1", "A minimal workspace still fails on missing keys and wrong defaults",
         "security.alerts_email and active-apis are read without try(), SQL depends on module.network even when "
         "there is none, and Cloud Run ingress defaults to the load balancer when the workspace has no lb.",
         "Guard both keys (a check block with a clear message is fine for the email), drop the unconditional "
         "depends_on, and default ingress from local.lb_enabled.", plan_guards),
    Item("AUD-TF-ALWAYS-ON", "p2", "Some resources are created in every workspace whether used or not",
         "The Cloud Build service account and artifacts bucket exist without triggers, and the IAP identity with a "
         "60 second sleep exists without IAP rules. That costs plan time and clutters a small project.",
         "Count each on the settings that need it.", no_always_on_resources),
    Item("AUD-TF-LABELS", "p2", "common_labels are not applied by the providers",
         "Only some resources pass labels by hand.", "Set default_labels = local.common_labels on google and google-beta.",
         provider_default_labels),
    Item("AUD-TF-OUTPUTS", "p2", "The root module has no outputs",
         "A user has to dig in state to find the LB IP, service URLs, SQL connection names or the registry.",
         "Add outputs.tf with at least those four, nothing sensitive.", root_outputs),
    Item("AUD-TF-BACKEND", "p2", "The state bucket is a literal in versions.tf",
         "Every clone has to edit a tracked file, and a forgotten edit points at the wrong bucket.",
         'Use backend "gcs" {} with backend.hcl.example and terraform init -backend-config.', partial_backend),
    Item("AUD-TF-SCHEMA", "p2", "Nothing validates the settings files before a plan",
         "A typo in a YAML key is silently ignored by try(). example.yaml can drift from the code.",
         "Add schemas/settings.schema.json and bin/validate-settings.py (stdlib or PyYAML), checking every "
         "settings/*.yaml including example.yaml, and run it in CI.", settings_schema),
    Item("AUD-TF-TESTS", "p3", "There are no terraform tests",
         "The settings merge and the feature toggles have no regression test.",
         "Add tests/*.tftest.hcl with mock_provider for the empty, dev and pro shapes, and run terraform test in CI.",
         terraform_tests, after=["AUD-CI-MATRIX"]),
    Item("AUD-CI-MATRIX", "p1", "CI validates only the default workspace",
         "dev, stg and pro read different files. One of them can break while default stays green. The Cloud "
         "Build render test exists and does not run.",
         "Validate a matrix of default, dev, stg and pro with TF_WORKSPACE and a local backend override, and run "
         "bin/cloudbuild-render-test.py.", ci_matrix),
    Item("AUD-CI-RUNNER", "p1", "CI runs on a moving runner label with Node 20 actions",
         "ubuntu-latest is migrating to a new image and Node 20 actions are deprecated. Runs on the fork created "
         "only some matrix jobs and could not be retried, so a pull request can look green without validating "
         "every workspace.",
         "Pin runs-on to ubuntu-24.04 and move checkout, setup-terraform and setup-python to their Node 24 majors.",
         ci_runner_pinned),
    Item("AUD-LINT", "p3", "No tflint or pre-commit configuration",
         "Contributors get fmt and lint errors only after a push.", "Add .tflint.hcl with the google ruleset, "
         ".pre-commit-config.yaml (fmt, validate, tflint, the auditor) and a tflint step in CI.", lint_tooling,
         after=["AUD-CI-MATRIX"]),
    Item("AUD-COST-DEFAULTS", "p1", "Two code defaults cost money when a key is left out",
         "budget.enable_auto_stop defaults to true, which deploys a function that disables billing and takes the "
         "project down. cpu_idle defaults to false, so every non-pro service pays for CPU between requests.",
         "Default enable_auto_stop to false and cpu_idle to true outside pro.", cost_safe_defaults),
    Item("AUD-COST-PROFILES", "p1", "dev is a copy of stg and stg a copy of pre",
         "dev runs NAT, Redis and a custom SQL tier, so the cheapest workspace is not cheap. stg and pre are the "
         "same file. The header of dev.yaml still says pre.",
         "dev: shared-core SQL, no Redis, no NAT, at most 7 backups, scale to zero. stg: one step up. pro: HA. "
         "Fix the headers and the matrix in docs/ENVIRONMENTS.md.", cost_profiles, after=["AUD-COST-DEFAULTS"]),
    Item("AUD-COST-APIS", "p3", "APIs for SQL, Redis, Firestore and other features are enabled when unused",
         "default.yaml lists every API, so a Cloud Run only project enables the SQL Admin and Redis APIs.",
         "Keep base APIs in default.yaml and add a feature_apis map in locals that turns on an API when its "
         "section exists.", feature_apis),
    Item("AUD-NAMES", "p2", "Module directories carry build timestamps and some root files break the naming pattern",
         "modules/tf_gcp_x_v1.8-202405071510 reads like a build export, not a version. gcp.compute-nat.tf and "
         "gcp.repository.github-extra.tf mix hyphens into a dotted pattern.",
         "Rename modules to modules/gcp_<name>_v<major.minor> and update every source. Rename the two root files "
         "with dots. Module addresses in state do not change.", clean_names),
    Item("AUD-LANG", "p1", "Docs and comments mix Spanish with English, and use em dashes",
         "A public template has one language. docs/cloudrun-service-resources.md and several comments are Spanish, "
         "and many files use the em dash (U+2014), which many readers take as a sign of machine-written text.",
         "Translate to English and replace every em dash with a comma, colon, parentheses or hyphen "
         "(`--leaks` prints `lang` and `dash` lines).", english_only),
    Item("AUD-DOC-OSS", "p2", "The repository has no contributor, security or change files",
         "A public project needs to say how to contribute, how to report a vulnerability and what changed.",
         "Add CONTRIBUTING.md, SECURITY.md, CHANGELOG.md, a pull request template and issue templates.", oss_files),
    # Round 2: found by a second full audit after the first list was closed.
    Item("AUD-PSA", "p1", "Private Service Access is never created, so private Cloud SQL and Redis fail on a new project",
         "gcp.network.tf passes services_ip_ranges to the networking module, but the module creates only the VPC "
         "and subnets: no reserved range and no servicenetworking connection. A private-IP Cloud SQL instance or a "
         "PRIVATE_SERVICE_ACCESS Redis fails at apply on a fresh project, and nothing warns at plan time.",
         "Copy the networking module to a new version that creates google_compute_global_address and "
         "google_service_networking_connection from services_ip_ranges, expose the connection, and make Cloud SQL "
         "and Redis wait for it. Add a check when a private data store has no range.", private_service_access),
    Item("AUD-PROJECT-NUMBER", "p1", "A workspace that sets project with only an id loses the project number",
         "The settings merge is shallow, so project: {id: x} drops project.number from default.yaml, and several "
         "files interpolate local.settings.project.number without a fallback.",
         "Read the number from data.google_project when the YAML leaves it out, or stop the plan with a check "
         "that names the key.", project_number_resolved),
    Item("AUD-IAM-OPERATORS", "p1", "Operators can invoke every service and act as every service account",
         "gcp.iam.tf grants project_access.operators roles/run.invoker and roles/iam.serviceAccountUser on the "
         "whole project. serviceAccountUser on the project lets an operator deploy as any account, including the "
         "Cloud Build one. Least privilege is the first IAM question of an audit.",
         "Grant run.invoker per service and serviceAccountUser per runtime service account, only where the "
         "operator needs it. Document the change for existing users.", operators_scoped),
    Item("AUD-DEV-NO-LB", "p1", "The dev reference still pays for a load balancer and Cloud Armor",
         "The load balancer and its policy are a fixed cost of about 34 USD a month, most of dev's bill, and the "
         "dev budget is below the estimate in docs/ENVIRONMENTS.md.",
         "dev: no lb section, services reached on their run.app URL with IAM (allow_unauthenticated false), and a "
         "budget at or above the estimate. Keep the LB in stg and pro and update the matrix.", dev_without_lb),
    Item("AUD-MON-SECURITY-DUP", "p2", "The security module's metric alerts cannot be turned off and duplicate the log alerts",
         "Pro gets two emails for a firewall, custom role, audit config, SQL or bucket IAM change.",
         "Add a metric_alerts switch to a new security module version and turn it off where monitoring.log_alerts "
         "covers the same events.", security_metric_alerts_toggle),
    Item("AUD-SECRET-READERS", "p2", "Secret readers granted from YAML trigger the secret access alert",
         "Accessors set in the standalone and external secret settings are not in the default exclusion list.",
         "Add them to secret_access_stack_principals.", secret_alert_yaml_readers, after=["AUD-SECRET-ACCESS"]),
    Item("AUD-INPUT-GUARDS", "p3", "Two settings fail late or silently",
         "elastic_psc without a network creates nothing and says nothing. A log alert with a rate limit under "
         "300s or an auto close under 1800s fails only at the API.",
         "Add a check for elastic_psc without network, and preconditions for the two durations.", input_guards),
    Item("AUD-SA-KEY-POLICY", "p2", "Nothing prevents service account key creation",
         "The template only alerts after a key exists. A project-level organization policy can refuse it.",
         "Optional security.disable_service_account_keys enforcing iam.disableServiceAccountKeyCreation on the "
         "project, on in pro. Document the permission it needs.", sa_key_policy),
    Item("AUD-ESSENTIAL-CONTACTS", "p2", "Google has nobody to tell about security, legal or billing notices",
         "Essential Contacts route mandatory notifications. Without them they go to project owners only.",
         "security.essential_contacts (email and categories), defaulting to alerts_email for SECURITY and "
         "TECHNICAL. On in pro.", essential_contacts),
    Item("AUD-DEV-SQL-DISPOSABLE", "p3", "dev keeps Cloud SQL deletion protection on",
         "dev is meant to be torn down, and the database is the one resource that blocks it.",
         "Set deletion_protection false on dev's database. Keep stg and pro as they are.", dev_sql_disposable),
    Item("AUD-FIRESTORE-PRO", "p3", "Firestore in pro starts without PITR or delete protection",
         "A pro workspace that adds a firestore section gets the unprotected defaults.",
         "Default point-in-time recovery and DELETE_PROTECTION_ENABLED to on in pro, off elsewhere, still "
         "overridable from YAML.", firestore_pro_defaults),
    Item("AUD-DOC-STALE", "p1", "Several docs describe files, keys and names that changed",
         "cloudbuild-tag-patterns.md names project.cloudbuild.tf, example.yaml lacks dns_zones and sops, the "
         "Cloud Run doc states one egress default and a pre tag, CONFIGURATION_GUIDE keeps a one-off migration "
         "note, PROJECT_STRUCTURE lists only pre and pro, AGENTS.md talks about a production baseline, SOPS.md "
         "and SCANNING.md use old wording.",
         "Rewrite each passage against the current code.", docs_current),
    Item("AUD-DOC-COMPLIANCE", "p1", "Nothing maps the pro settings to audit controls",
         "An auditor or a buyer asks which control covers backups, retention, logging, encryption and access.",
         "Add docs/COMPLIANCE.md mapping each pro setting to ISO 27001 Annex A, SOC 2 and GDPR article 32, "
         "with the gaps a user still owns, and link it from the README.", compliance_doc,
         after=["AUD-SQL-HARDEN", "AUD-AUDIT-ARCHIVE", "AUD-MON-LOG-ALERTS", "AUD-WIF", "AUD-PSA",
                "AUD-IAM-OPERATORS", "AUD-SA-KEY-POLICY", "AUD-ESSENTIAL-CONTACTS", "AUD-MON-SECURITY-DUP"]),
    Item("AUD-DOC-README", "p1", "The README does not explain the project at a glance",
         "A first-time visitor needs what it is, a diagram, a quick start, the environment and cost matrix, the "
         "security posture and where the docs are, in one screen.",
         "Rewrite README.md with badges, a mermaid diagram, quick start, an environment matrix for dev, stg and "
         "pro, cost and security sections, and a docs index in docs/README.md that lists every docs page. Fix "
         "the key table (dns_zones), list every root output (sops_kms_key too), say firewall rules exist only "
         "with a network, keep the tone impersonal, and separate the adopter's path from the maintainer's "
         "backlog in docs/audit/.",
         readme_showcase, after=["AUD-DOC-COMPLIANCE", "AUD-COST-PROFILES", "AUD-NAMES", "AUD-LANG", "AUD-DOC-OSS",
                                 "AUD-DOC-STALE", "AUD-DEV-NO-LB"]),

    # Decisions: these are not gaps. Do not reopen them.
    Item("OK-MODULE-VPC", "p1", "Do not create one VPC per service or per module",
         "One project, one application, one shared VPC created only when the YAML asks for it. A network per "
         "service adds peering and NAT for an isolation boundary this template does not have.",
         "Leave it.", disposition=ACCEPTED),
    Item("OK-APP-SHAPE", "p1", "Do not nest services under a module map",
         "app.service and app.job are the flat shape a single application wants.", "Keep app.service.",
         disposition=ACCEPTED),
    Item("OK-SCANNER-INSTANCE", "p2", "Do not add a scanner that needs its own instance",
         "Harbor or SonarQube need a server, robots and tokens. In-build scanners (gitleaks, semgrep, trivy fs) "
         "and Artifact Registry scanning are opt-in and need none.",
         "Use cloudbuild.scan and security.artifact_scanning.", disposition=ACCEPTED),
    Item("OK-RETENTION-JOB", "p3", "Do not ship a row-deletion job", "Deleting expired rows is application logic. "
         "When a project needs it, it is an app.job entry.", "Leave it out.", disposition=ACCEPTED),
    Item("OK-SQL-RESIZER", "p3", "Do not stop Cloud SQL at night", "A night stop needs functions and schedulers. "
         "dev gets a shared-core tier instead.", "Leave it out.", disposition=ACCEPTED),
    Item("OK-RENOVATE", "p3", "Do not ship a dependency bot", "Dependency updates are the adopter's choice.",
         "Leave it out.", disposition=ACCEPTED),
    Item("OK-VPCSC", "p2", "Do not manage VPC Service Controls here",
         "A perimeter is an organization policy a project stack cannot own.", "Leave it out.", disposition=ACCEPTED),
    Item("OK-MODEL-ARMOR", "p3", "Do not enable Model Armor or DLP by default", "Add the API where it is called.",
         "Leave them commented.", disposition=ACCEPTED),
    Item("OK-GROUPS", "p3", "Do not create Google groups from Terraform",
         "Group creation is an organization process. Membership is a list on project_access and iap.",
         "Leave it out.", disposition=ACCEPTED),
    Item("OK-IAM-MATRIX", "p2", "Keep the two access lists", "viewers and operators fit one team. A large custom role "
         "matrix belongs to a platform.", "Put group emails in the workspace files.", disposition=ACCEPTED),
    Item("OK-BUILD-CHAT", "p3", "Do not ship a build-failure chat notifier",
         "It needs a webhook and a space the adopter may not have.", "Leave it out.", disposition=ACCEPTED),
    Item("OK-SYS-PROJECT", "p2", "Do not require a separate monitoring project",
         "project_sys can be the workspace project until several apps share one.", "Leave it.", disposition=ACCEPTED),
    Item("OK-SHALLOW-MERGE", "p1", "Keep the shallow settings merge",
         "A deep merge would change every existing workspace in silence. Environment files are complete and do "
         "not set active-apis.", "Document it.", disposition=ACCEPTED),
    Item("OK-CMEK", "p2", "Do not encrypt every resource with CMEK by default",
         "Google-managed encryption is the starting point. CMEK follows the data classification, one resource "
         "family per change.", "Leave it out. SOPS has its own key.", disposition=ACCEPTED),
    Item("OK-HELLO-IMAGE", "p3", "The first Cloud Run image stays the public hello image",
         "The first apply boots a placeholder and Cloud Build replaces it. Terraform ignores later image changes.",
         "Leave it.", disposition=ACCEPTED),
    Item("OK-MODULE-SNAPSHOTS", "p2", "Vendored modules stay snapshots",
         "A module changes only through a new version directory, named modules/gcp_<name>_v<major.minor> with no "
         "timestamp. Newer private modules are not copied in.",
         "Upgrade one module per change, with a new directory that bumps the version, and delete the old one "
         "once no source points at it.", disposition=ACCEPTED),
    Item("OK-OCI", "p3", "The optional Oracle Cloud files stay",
         "oracle.*.tf create nothing without an oracle section. The provider is required at init only.",
         "Leave it. Document it as optional.", disposition=ACCEPTED),
    Item("OK-OWNER", "p3", "CODEOWNERS and LICENSE name the repository owner",
         "That is the owner of this repository, not a leak. A fork replaces it.", "Leave it.", disposition=ACCEPTED),
    Item("OK-ACTIVE-APIS-KEY", "p3", "Keep the active-apis key name",
         "Renaming it breaks every existing workspace for a style gain.", "Leave it.", disposition=ACCEPTED),
    Item("OK-SOPS-OPTIONAL", "p2", "SOPS stays opt-in, also in pro",
         "It needs a KMS key and encrypted files the adopter creates. The placeholder path is safe by default.",
         "Document it in docs/SOPS.md.", disposition=ACCEPTED),
    Item("OK-SQL-REPLICA", "p3", "No read replica by default in pro",
         "REGIONAL availability already gives a standby. A replica is a read scaling choice.", "Leave it.",
         disposition=ACCEPTED),
    Item("OK-PRE-ALIAS", "p3", "settings/pre.yaml stays as the older name of stg",
         "Existing users have a pre workspace. New projects use stg.", "Keep it equal to stg.", disposition=ACCEPTED),
]


# ----------------------------------------------------------------- engine


_cache: dict[str, str] = {}


def status_of(item: Item) -> str:
    if item.disposition == ACCEPTED:
        return "accepted"
    if item.id not in _cache:
        _cache[item.id] = "done" if item.ok() else "open"
    return _cache[item.id]


def ready(item: Item) -> bool:
    by_id = {i.id: i for i in ITEMS}
    return status_of(item) == "open" and all(status_of(by_id[dep]) != "open" for dep in item.after)


def next_item() -> Item | None:
    candidates = [i for i in ITEMS if ready(i)]
    candidates.sort(key=lambda i: SEVERITY_RANK[i.severity])
    return candidates[0] if candidates else None


def selected(fail_on: str | None) -> list[Item]:
    if fail_on is None:
        return []
    ceiling = SEVERITY_RANK[fail_on]
    return [i for i in ITEMS if status_of(i) == "open" and SEVERITY_RANK[i.severity] <= ceiling]


def render() -> str:
    counts = {"open": 0, "done": 0, "accepted": 0}
    for item in ITEMS:
        counts[status_of(item)] += 1

    def section(title: str, status: str, detail: bool) -> str:
        lines = [f"## {title}", ""]
        found = [i for i in ITEMS if status_of(i) == status]
        if not found:
            return "\n".join(lines + ["None.", ""])
        for item in found:
            if not detail:
                lines.append(f"- {item.id} ({item.severity}) {item.title}")
                continue
            lines += [f"### {item.id} ({item.severity}) {item.title}", "", item.why, "", f"Next change: {item.change}", ""]
            if item.after:
                lines += [f"After: {', '.join(item.after)}", ""]
        if not detail:
            lines.append("")
        return "\n".join(lines)

    header = f"""# Audit backlog

The list of work that takes this template to a public, production-grade
release: dev and stg cheap, pro ready for a security, backup and
data-retention audit. Each item has a check in `bin/audit-terraform.py`.

Open: {counts['open']}. Done: {counts['done']}. Accepted, not a gap: {counts['accepted']}.

Regenerate with `python3 bin/audit-terraform.py --write` in the pull request
that closes an item. `--next` names the item to take. How a session works an
item: `docs/audit/OPERATING.md`.

"""
    parts = [
        header,
        section("Open", "open", True),
        section("Accepted, not a gap", "accepted", True),
        section("Done", "done", False),
    ]
    return "\n".join(parts).rstrip() + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", action="store_true", help="write docs/audit/BACKLOG.md")
    parser.add_argument("--fail-on", choices=tuple(SEVERITY_RANK), help="exit 1 on an open item at this severity or above")
    parser.add_argument("--id", help="print one item; exit 1 while it is open")
    parser.add_argument("--next", action="store_true", help="print the next item to work on; exit 1 when none is left")
    parser.add_argument("--leaks", action="store_true", help="print every leak, language and em dash hit")
    args = parser.parse_args(argv)

    if args.leaks:
        for hit in leak_hits():
            print(f"leak  {hit}")
        for hit in spanish_hits():
            print(f"lang  {hit}")
        for hit in em_dash_hits():
            print(f"dash  {hit}")
        print(f"denylist patterns loaded: {len(denylist())}", file=sys.stderr)
        return 0

    if args.id:
        match = [i for i in ITEMS if i.id == args.id]
        if not match:
            print(f"unknown id {args.id}", file=sys.stderr)
            return 2
        item = match[0]
        print(f"{status_of(item)} {item.id} ({item.severity}) {item.title}\n\n{item.why}\n\nNext change: {item.change}")
        return 1 if status_of(item) == "open" else 0

    if args.next:
        item = next_item()
        if item is None:
            print("nothing left")
            return 1
        print(f"{item.id} ({item.severity}) {item.title}\n\n{item.why}\n\nNext change: {item.change}")
        return 0

    for item in ITEMS:
        flag = "" if status_of(item) != "open" or ready(item) else " (waits)"
        print(f"{status_of(item):8} {item.severity:3} {item.id:20} {item.title}{flag}")

    if args.write:
        destination = ROOT / "docs" / "audit" / "BACKLOG.md"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(render(), encoding="utf-8")
        print(f"wrote {destination.relative_to(ROOT)}")

    failing = selected(args.fail_on)
    if failing:
        print(f"{len(failing)} open item(s) at or above {args.fail_on}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
