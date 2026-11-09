#!/usr/bin/env python3
"""Show the pipeline a service actually builds with, and prove Terraform agrees.

`cloudbuild_files/cloudbuild.yaml` is one file shared by every build in the project.
What a given service ends up running depends on its capability flags (which steps
survive the `x-when` filter) and on the substitutions Terraform computes from
settings/<workspace>.yaml. Simulating that in your head is exactly the mistake this
script exists to remove:

    bin/cloudbuild-render.py my-workspace my-service
    bin/cloudbuild-render.py my-workspace --list
    bin/cloudbuild-render.py my-workspace --check-plan /tmp/plan.json

Terraform is the source of truth; this is a reader for it. `--check-plan` is what keeps
the two honest: it takes `terraform show -json <plan>` and fails if a single planned
trigger disagrees with what this file renders: same steps, same order, same waitFor,
same substitutions.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - environment problem, not a logic one
    sys.exit("PyYAML is required: pip install pyyaml")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# --------------------------------------------------------------------------- settings
def load_settings(root: str, workspace: str) -> dict:
    """default.yaml overlaid by <workspace>.yaml: the merge locals.tf does."""
    with open(os.path.join(root, "settings", "default.yaml")) as fh:
        settings = yaml.safe_load(fh) or {}
    path = os.path.join(root, "settings", f"{workspace}.yaml")
    if os.path.exists(path):
        with open(path) as fh:
            settings.update(yaml.safe_load(fh) or {})
    return settings


def registry_host(settings: dict) -> str:
    return f"{settings['region_name']}-docker.pkg.dev/{settings['project']['id']}"


def registry_host_python(settings: dict) -> str:
    return f"{settings['region_name']}-python.pkg.dev/{settings['project']['id']}"


def _resolve_image(ref: str, settings: dict, python: bool = False) -> str:
    """A first segment with a dot in it is already a registry host."""
    host = registry_host_python(settings) if python else registry_host(settings)
    return ref if "." in ref.split("/")[0] else f"{host}/{ref}"


def binauth_enabled(settings: dict) -> bool:
    return bool((settings.get("binary_authorization") or {}).get("enabled", False))


def binauth_names(settings: dict, workspace: str) -> dict:
    """The attestor and key version gcp.binary_auth.tf builds from names."""
    medium = f"{settings['client']['name']}-{workspace}"
    project = settings["project"]["id"]
    return {
        "_BINAUTH_ATTESTOR": f"projects/{project}/attestors/{medium}-attestor",
        "_BINAUTH_KMS_KEY_VERSION": (
            f"projects/{project}/locations/{settings['region_name']}/keyRings/{medium}-binauth"
            "/cryptoKeys/attestor-signer/cryptoKeyVersions/1"
        ),
    }


def collect_configs(settings: dict, workspace: str) -> dict:
    """Every build declared in the workspace, normalised: gcp.cloudbuild.tf's locals."""
    base = settings["client"]["name"]
    sign_image = binauth_enabled(settings)
    app = settings.get("app") or {}
    sources = []
    for key, value in (settings.get("cloudbuild") or {}).items():
        sources.append((key, value, value, "raw", None))
    for key, value in (app.get("service") or {}).items():
        if (value or {}).get("cloudbuild", {}).get("repo_name"):
            sources.append((key, value, value["cloudbuild"], "app", None))
    for key, value in (app.get("job") or {}).items():
        if (value or {}).get("cloudbuild", {}).get("repo_name"):
            job_image = (value.get("job-config") or {}).get("image")
            sources.append((key, value, value["cloudbuild"], "job", job_image))

    configs = {}
    for key, owner, cb, kind, job_image in sources:
        if not cb.get("repo_name"):
            continue
        name = owner.get("name", key) if kind != "raw" else cb.get("name", key)
        custom = owner.get("custom_name") if kind != "raw" else cb.get("custom_name")
        prefixed = custom if custom else f"{base}-{name}"
        raw = custom if custom else name

        if cb.get("image"):
            image = _resolve_image(cb["image"], settings)
        elif kind == "job" and job_image:
            image = _resolve_image(job_image.split(":")[0], settings)
        else:
            image = f"{registry_host(settings)}/{prefixed}/{raw}"

        image_base = cb.get("image_base")
        if image_base:
            image_base = _resolve_image(image_base, settings, python="/simple" in image_base)

        deploy = cb.get("deploy", True)
        scan = cb.get("scan") or {}
        # A service may live outside the project's region; a job never does.
        deploy_region = ((owner.get("cloudrun") or {}).get("region") or settings["region_name"]) if kind == "app" else settings["region_name"]
        configs[key] = {
            "key": key,
            "type": kind,
            "name": name,
            "trigger": f"{base}-{name}",
            "prefixed_name": prefixed,
            "raw_name": raw,
            "image": image,
            "image_base": image_base,
            "reqs_file": cb.get("reqs_file"),
            "inline": cb.get("inline", False),
            "pipeline": cb.get("cloudbuild_file_path", "cloudbuild.yaml"),
            "dockerfile_path": cb.get("dockerfile_path", "Dockerfile"),
            "build_context_path": cb.get("build_context_path", "."),
            "build_args": cb.get("build_args") or {},
            "docker_target": cb.get("docker_target"),
            "build_timeout": cb.get("build_timeout"),
            "machine_type": cb.get("machine_type"),
            "substitutions": cb.get("substitutions") or {},
            "capabilities": {
                "ar_token": bool(cb.get("artifact_registry_token", False)),
                "scan_secrets": bool(scan.get("secrets", False)) and not bool(scan.get("secrets_blocking", False)),
                "scan_secrets_blocking": bool(scan.get("secrets_blocking", False)),
                "scan_sast": bool(scan.get("sast", False)) and not bool(scan.get("sast_blocking", False)),
                "scan_sast_blocking": bool(scan.get("sast_blocking", False)),
                "scan_deps": bool(scan.get("deps", False)) and not bool(scan.get("deps_blocking", False)),
                "scan_deps_blocking": bool(scan.get("deps_blocking", False)),
                "deploy_service": kind != "job" and deploy,
                "deploy_job": kind == "job" and deploy,
                "update_companion_job": kind != "job" and cb.get("job_name") is not None,
                "sign_image": sign_image,
            },
            "job_name": prefixed if kind == "job" else cb.get("job_name"),
            "deploy_region": deploy_region,
            "job_region": settings["region_name"],
        }
    return configs


# ----------------------------------------------------------------------- the pipeline
def render_build_args(config: dict) -> str:
    args = {}
    if config["image_base"]:
        args["IMAGE_BASE"] = config["image_base"]
    if config["reqs_file"]:
        args["REQS_FILE"] = config["reqs_file"]
    args.update(config["build_args"])

    parts = []
    if config["capabilities"]["ar_token"]:
        parts.append('--build-arg GOOGLE_ACCESS_TOKEN="$(cat /workspace/access_token.txt)"')
    for k in sorted(args):
        v = "" if args[k] is None else str(args[k])
        parts.append("--build-arg {}='{}'".format(k, v.replace("'", "'\\''")))
    return " ".join(parts)


def substitutions(config: dict, settings: dict, workspace: str, bucket: str = "<artifacts-bucket>") -> dict:
    subs = {
        "_GCP_REGION": settings["region_name"],
        "_ENV": workspace,
        "_RAW_NAME": config["raw_name"],
        "_PREFIXED_NAME": config["prefixed_name"],
        "_DOCKERFILE_PATH": config["dockerfile_path"],
        "_BUILD_CONTEXT_PATH": config["build_context_path"],
    }
    if config["inline"]:
        # The shared pipeline's contract. An external pipeline never gets these: it may
        # read an unset substitution as a signal, and defining one would change its build.
        subs["_IMAGE"] = config["image"]
        subs["_BUILD_ARGS"] = render_build_args(config)
        subs["_DOCKER_TARGET"] = "" if not config["docker_target"] else f"--target={config['docker_target']}"
        if config["capabilities"]["deploy_service"]:
            subs["_DEPLOY_REGION"] = config["deploy_region"]
        if config["job_name"]:
            subs["_JOB_NAME"] = config["job_name"]
            subs["_JOB_REGION"] = config["job_region"]
        if config["capabilities"]["sign_image"]:
            subs.update(binauth_names(settings, workspace))
    else:
        subs["_PYTHON_REPO_URL"] = f"https://{registry_host_python(settings)}/{config['prefixed_name']}/"
        subs["_ARTIFACTS_BUCKET"] = f"gs://{bucket}/artifacts"
    subs.update({k: str(v) for k, v in config["substitutions"].items()})
    return subs


def filter_steps(pipeline: dict, capabilities: dict) -> list:
    """`x-when` is AND over capabilities; an unknown flag is an error, not a silent skip."""
    kept = []
    for step in pipeline.get("steps", []):
        flags = step.get("x-when", [])
        for flag in flags:
            if flag not in capabilities:
                raise KeyError(f"unknown x-when capability '{flag}' on step '{step.get('id')}'")
        if all(capabilities[f] for f in flags):
            kept.append(step)
    return kept


def rewrite_wait_for(steps: list) -> list:
    """waitFor for the steps that survived. Nothing left to wait for means None (wait
    for everything before it), never ["-"], which could start a step too early."""
    ids = [s["id"] for s in steps if s.get("id")]
    out = []
    for step in steps:
        wait = step.get("waitFor")
        if wait is None:
            out.append(None)
            continue
        kept = [w for w in wait if w == "-" or w in ids]
        out.append(kept or None)
    return out


def apply_substitutions(text: str, subs: dict) -> str:
    """What Cloud Build does to the step text. Unset custom substitutions become empty
    strings: ALLOW_LOOSE is forced on every triggered build."""

    def one(match):
        name = match.group(1) or match.group(2)
        if name.startswith("_"):
            return subs.get(name, "")
        return match.group(0)  # a builtin: SHORT_SHA, PROJECT_ID, ...

    return re.sub(r"\$\{([A-Z_][A-Z0-9_]*)\}|\$([A-Z_][A-Z0-9_]*)", one, text)


def substitute_deep(value, subs: dict):
    """apply_substitutions over every string in a step, structure untouched."""
    if isinstance(value, str):
        return apply_substitutions(value, subs)
    if isinstance(value, list):
        return [substitute_deep(v, subs) for v in value]
    if isinstance(value, dict):
        return {k: substitute_deep(v, subs) for k, v in value.items()}
    return value


def render(config: dict, settings: dict, workspace: str, root: str, resolve: bool = True,
           bucket: str = "<artifacts-bucket>") -> dict:
    path = os.path.join(root, "cloudbuild_files", config["pipeline"])
    if not config["inline"]:
        return {"external": config["pipeline"],
                "substitutions": substitutions(config, settings, workspace, bucket)}
    if not os.path.exists(path):
        raise FileNotFoundError(f"{config['key']}: cloudbuild_files/{config['pipeline']} does not exist")
    with open(path) as fh:
        pipeline = yaml.safe_load(fh)

    steps = filter_steps(pipeline, config["capabilities"])
    waits = rewrite_wait_for(steps)
    subs = substitutions(config, settings, workspace, bucket)

    rendered = []
    for step, wait in zip(steps, waits):
        step = {k: v for k, v in step.items() if k != "x-when"}
        step["waitFor"] = wait
        if resolve:
            step = substitute_deep(step, subs)
        rendered.append(step)

    return {
        "trigger": config["trigger"],
        "steps": rendered,
        "timeout": config["build_timeout"] or pipeline.get("timeout", "1800s"),
        "machine_type": config["machine_type"] or (pipeline.get("options") or {}).get("machineType"),
        "substitutions": subs,
    }


# ------------------------------------------------------------------------- presenting
def print_human(config: dict, result: dict) -> None:
    print(f"── {config['key']}  ({config['type']})  trigger: {config['trigger']}")
    if "external" in result:
        print(f"   pipeline: {result['external']} (read from the application repository)")
        print("   substitutions:")
        for k, v in sorted(result["substitutions"].items()):
            print(f"     {k} = {v}")
        return
    caps = ", ".join(k for k, v in config["capabilities"].items() if v) or "none"
    print(f"   capabilities: {caps}")
    print(f"   timeout: {result['timeout']}" + (f"   machine: {result['machine_type']}" if result["machine_type"] else ""))
    for step in result["steps"]:
        wait = step.get("waitFor")
        print(f"   • {step.get('id', '(unnamed)')}  [{step.get('name')}]" + (f"  after {wait}" if wait else ""))
        for arg in step.get("args", []):
            for line in str(arg).splitlines():
                if line.strip():
                    print(f"       {line}")
    print("   substitutions:")
    for k, v in sorted(result["substitutions"].items()):
        print(f"     {k} = {v}")


# ------------------------------------------------------------------------ plan checking
def _find_artifacts_bucket(module: dict) -> str | None:
    """The bucket carries a random suffix only the state knows; read it off the plan."""
    for res in module.get("resources", []):
        if res.get("type") == "google_storage_bucket" and "cloudbuild-artifacts" in str(res["values"].get("name", "")):
            return res["values"]["name"]
    for child in module.get("child_modules", []):
        found = _find_artifacts_bucket(child)
        if found:
            return found
    return None


def check_plan(plan_path: str, configs: dict, settings: dict, workspace: str, root: str) -> int:
    with open(plan_path) as fh:
        plan = json.load(fh)

    root_module = plan.get("planned_values", {}).get("root_module", {})
    bucket = _find_artifacts_bucket(root_module) or "<artifacts-bucket>"

    planned = {}
    for res in root_module.get("resources", []):
        if res.get("type") == "google_cloudbuild_trigger":
            planned[res["values"]["name"]] = res["values"]

    problems = []
    checked = 0
    for key, config in sorted(configs.items()):
        values = planned.get(config["trigger"])
        if values is None:
            problems.append(f"{key}: no planned trigger named {config['trigger']}")
            continue
        result = render(config, settings, workspace, root, resolve=False, bucket=bucket)
        checked += 1

        want_subs = {k: str(v) for k, v in result["substitutions"].items()}
        got_subs = {k: str(v) for k, v in (values.get("substitutions") or {}).items()}
        if want_subs != got_subs:
            for k in sorted(set(want_subs) | set(got_subs)):
                if want_subs.get(k) != got_subs.get(k):
                    problems.append(f"{key}: substitution {k}: plan {got_subs.get(k)!r} != render {want_subs.get(k)!r}")

        if "external" in result:
            continue
        build = (values.get("build") or [{}])[0]
        got_steps = build.get("step") or []
        want_steps = result["steps"]
        if len(got_steps) != len(want_steps):
            problems.append(f"{key}: plan has {len(got_steps)} steps, render has {len(want_steps)}")
            continue
        for got, want in zip(got_steps, want_steps):
            if got.get("id") != want.get("id"):
                problems.append(f"{key}: step id {got.get('id')!r} != {want.get('id')!r}")
            got_wait = got.get("wait_for") or None
            want_wait = want.get("waitFor") or None
            if got_wait != want_wait:
                problems.append(f"{key}: {want.get('id')} waitFor {got_wait} != {want_wait}")
            if (got.get("args") or None) != (want.get("args") or None):
                problems.append(f"{key}: {want.get('id')} args differ from the plan")

    if problems:
        print(f"FAIL: {len(problems)} disagreement(s) between the plan and this renderer:")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"PASS: {checked} trigger(s) in the plan render exactly as this script does")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("workspace", help="terraform workspace, i.e. a file in settings/")
    ap.add_argument("service", nargs="?", help="one build key; omit for all of them")
    ap.add_argument("--list", action="store_true", help="one line per build, no pipeline")
    ap.add_argument("--json", action="store_true", help="machine-readable")
    ap.add_argument("--raw", action="store_true", help="keep ${_SUBSTITUTIONS} unresolved")
    ap.add_argument("--check-plan", metavar="FILE", help="`terraform show -json <plan>` output to verify against")
    ap.add_argument("--root", default=ROOT, help=argparse.SUPPRESS)
    args = ap.parse_args()

    settings = load_settings(args.root, args.workspace)
    configs = collect_configs(settings, args.workspace)
    if args.service:
        if args.service not in configs:
            sys.exit(f"no build named '{args.service}' in {args.workspace}. Known: {', '.join(sorted(configs))}")
        configs = {args.service: configs[args.service]}

    if args.check_plan:
        return check_plan(args.check_plan, configs, settings, args.workspace, args.root)

    if args.list:
        for key, config in sorted(configs.items()):
            caps = ",".join(k for k, v in config["capabilities"].items() if v) or "-"
            print(f"{key:32} {config['type']:4} {config['pipeline'] if config['inline'] else '(repo) ' + config['pipeline']:34} {caps}")
        return 0

    out = {}
    for key, config in sorted(configs.items()):
        result = render(config, settings, args.workspace, args.root, resolve=not args.raw)
        out[key] = result
        if not args.json:
            print_human(config, result)
            print()
    if args.json:
        print(json.dumps(out, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
