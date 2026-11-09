#!/usr/bin/env python3
"""Validate settings/*.yaml against schemas/settings.schema.json.

    python3 bin/validate-settings.py

Each settings/<workspace>.yaml is checked the way locals.tf reads it: merged
over settings/default.yaml with a shallow merge (a top-level key of the
workspace file replaces the whole value). default.yaml is the default
workspace. example.yaml is also checked alone, without the top-level
required keys, because it documents sections, not a full workspace.

Two cross-checks keep the schema honest:

- every top-level key a root .tf file reads (local.settings.<key>,
  local.settings["<key>"], lookup(local.settings, "<key>", ...)) is in the
  schema;
- every top-level key of every settings file (example.yaml included) is in
  the schema.

Requirements: PyYAML. jsonschema is used when installed; otherwise a built-in
validator covers the keywords the schema uses ($ref, type, properties,
required, additionalProperties, enum, items, pattern, minimum, maximum).
SETTINGS_SCHEMA_ENGINE=builtin forces the built-in one.

Without PyYAML the cross-checks still run (top-level keys are read line by
line), then the script exits 2, or 0 with "skipped: PyYAML not installed" on
stderr when SETTINGS_SCHEMA_OPTIONAL=1.

Exit 0 when every check passes, 1 on a finding, 2 when PyYAML is missing.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "schemas" / "settings.schema.json"
SETTINGS = ROOT / "settings"

SUPPORTED = {
    "$schema", "$id", "$ref", "$defs", "title", "description",
    "type", "properties", "required", "additionalProperties",
    "enum", "items", "pattern", "minimum", "maximum",
}

TF_KEY_PATTERNS = (
    re.compile(r"local\.settings\.([A-Za-z_][A-Za-z0-9_-]*)"),
    re.compile(r"local\.settings\[\"([^\"]+)\"\]"),
    re.compile(r"lookup\(\s*local\.settings\s*,\s*\"([^\"]+)\""),
)
TOP_LEVEL_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*)\s*:")


# ------------------------------------------------------------ cross-checks


def tf_keys() -> dict[str, str]:
    """Top-level settings keys read by root .tf files, with one file that reads each."""
    found: dict[str, str] = {}
    for path in sorted(ROOT.glob("*.tf")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith(("#", "//")):
                continue
            for pattern in TF_KEY_PATTERNS:
                for key in pattern.findall(line):
                    found.setdefault(key, path.name)
    return found


def line_keys(path: Path) -> list[str]:
    """Top-level keys of a YAML file without a YAML parser: unindented `key:` lines."""
    return [m.group(1) for m in map(TOP_LEVEL_LINE.match, path.read_text(encoding="utf-8").splitlines()) if m]


def schema_keywords(node: Any, where: str, errors: list[str]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            if key not in SUPPORTED:
                errors.append(f"schema {where}: keyword {key!r} is not supported by the built-in validator")
            if key in ("properties", "$defs"):
                for name, sub in value.items():
                    schema_keywords(sub, f"{where}/{key}/{name}", errors)
            elif key in ("items", "additionalProperties") and isinstance(value, dict):
                schema_keywords(value, f"{where}/{key}", errors)


def cross_check(schema: dict, files: list[Path]) -> list[str]:
    errors: list[str] = []
    known = set(schema["properties"])
    for key, source in sorted(tf_keys().items()):
        if key not in known:
            errors.append(f"schema: top-level key {key!r} is read by {source} but missing in {SCHEMA_PATH.name}")
    for path in files:
        for key in line_keys(path):
            if key not in known:
                errors.append(f"settings/{path.name}: top-level key {key!r} is not in {SCHEMA_PATH.name}")
    schema_keywords(schema, "#", errors)
    return errors


# ------------------------------------------------------------- YAML loader


def yaml_loader():
    """A SafeLoader close to Terraform's yamldecode (YAML 1.2 core scalars).

    PyYAML follows YAML 1.1, where yes/no/on/off are booleans, 02:00 is a
    sexagesimal integer and 2025-12-20 a date. yamldecode reads all of them
    as strings, so those resolvers are replaced. Duplicate keys are errors.
    """
    import yaml

    class Loader(yaml.SafeLoader):
        pass

    Loader.yaml_implicit_resolvers = {
        first: [(tag, rx) for tag, rx in resolvers if tag.rsplit(":", 1)[-1] not in ("bool", "int", "float", "timestamp")]
        for first, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
    }
    Loader.add_implicit_resolver(
        "tag:yaml.org,2002:bool", re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"), list("tTfF")
    )
    Loader.add_implicit_resolver(
        "tag:yaml.org,2002:int", re.compile(r"^(?:[-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$"), list("-+0123456789")
    )
    Loader.add_implicit_resolver(
        "tag:yaml.org,2002:float",
        re.compile(r"^(?:[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$"),
        list("-+0123456789."),
    )

    def construct_bool(loader, node):
        return loader.construct_scalar(node).lower() == "true"

    def construct_int(loader, node):
        value = loader.construct_scalar(node)
        if value.startswith("0o"):
            return int(value[2:], 8)
        if value.startswith("0x"):
            return int(value[2:], 16)
        return int(value, 10)

    def construct_float(loader, node):
        value = loader.construct_scalar(node).lower()
        if value.endswith(".inf"):
            return float("-inf") if value.startswith("-") else float("inf")
        if value == ".nan":
            return float("nan")
        return float(value)

    def construct_mapping(loader, node):
        loader.flatten_mapping(node)
        result = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=True)
            if key in result:
                raise yaml.constructor.ConstructorError(
                    None, None, f"duplicate key {key!r}", key_node.start_mark
                )
            result[key] = loader.construct_object(value_node, deep=True)
        return result

    Loader.add_constructor("tag:yaml.org,2002:bool", construct_bool)
    Loader.add_constructor("tag:yaml.org,2002:int", construct_int)
    Loader.add_constructor("tag:yaml.org,2002:float", construct_float)
    Loader.add_constructor("tag:yaml.org,2002:map", construct_mapping)
    return yaml, Loader


# ------------------------------------------------------- built-in validator


def type_ok(value: Any, name: str) -> bool:
    if name == "object":
        return isinstance(value, dict)
    if name == "array":
        return isinstance(value, list)
    if name == "string":
        return isinstance(value, str)
    if name == "boolean":
        return isinstance(value, bool)
    if name == "integer":
        return (isinstance(value, int) and not isinstance(value, bool)) or (isinstance(value, float) and value.is_integer())
    if name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if name == "null":
        return value is None
    raise ValueError(f"unknown type {name}")


def builtin_errors(value: Any, schema: dict, root: dict, path: str) -> list[str]:
    if "$ref" in schema:
        ref = schema["$ref"]
        if not ref.startswith("#/$defs/"):
            raise ValueError(f"unsupported $ref {ref}")
        return builtin_errors(value, root["$defs"][ref[len("#/$defs/"):]], root, path)

    errors: list[str] = []
    if "type" in schema:
        names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(type_ok(value, n) for n in names):
            return [f"{path}: {value!r} is not of type {' or '.join(names)}"]
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} is not one of {schema['enum']}")
    if isinstance(value, str) and "pattern" in schema and not re.search(schema["pattern"], value):
        errors.append(f"{path}: {value!r} does not match {schema['pattern']!r}")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: {value!r} is less than the minimum of {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: {value!r} is greater than the maximum of {schema['maximum']}")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: {key!r} is a required property")
        properties = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for key, item in value.items():
            child = f"{path}.{key}" if path else str(key)
            if key in properties:
                errors += builtin_errors(item, properties[key], root, child)
            elif extra is False:
                errors.append(f"{path or '(root)'}: additional property {key!r} is not allowed")
            elif isinstance(extra, dict):
                errors += builtin_errors(item, extra, root, child)
    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for index, item in enumerate(value):
            errors += builtin_errors(item, schema["items"], root, f"{path}[{index}]")
    return errors


# ---------------------------------------------------------------- engines


def make_engine(schema: dict):
    """Return (name, validate) where validate(document, schema) gives error strings."""
    if os.environ.get("SETTINGS_SCHEMA_ENGINE") != "builtin":
        try:
            import jsonschema
        except ImportError:
            jsonschema = None
        if jsonschema is not None:
            jsonschema.Draft202012Validator.check_schema(schema)

            def validate(document: Any, active: dict) -> list[str]:
                validator = jsonschema.Draft202012Validator(active)
                out = []
                for error in sorted(validator.iter_errors(document), key=lambda e: list(map(str, e.absolute_path))):
                    where = "".join(f"[{p}]" if isinstance(p, int) else f".{p}" for p in error.absolute_path).lstrip(".")
                    out.append(f"{where or '(root)'}: {error.message}")
                return out

            return "jsonschema", validate

    return "builtin", lambda document, active: builtin_errors(document, active, active, "")


def load(yaml, loader, path: Path) -> dict:
    data = yaml.load(path.read_text(encoding="utf-8"), Loader=loader)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError("the top level is not a map")
    return data


def main() -> int:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    files = sorted(SETTINGS.glob("*.yaml"))
    errors = cross_check(schema, files)

    try:
        yaml, loader = yaml_loader()
    except ImportError:
        for error in errors:
            print(error, file=sys.stderr)
        if errors:
            return 1
        if os.environ.get("SETTINGS_SCHEMA_OPTIONAL") == "1":
            print(
                f"cross-checks passed for {len(files)} settings files; "
                "skipped: PyYAML not installed (pip install pyyaml jsonschema for the full check)",
                file=sys.stderr,
            )
            return 0
        print("PyYAML not installed: pip install pyyaml jsonschema (or set SETTINGS_SCHEMA_OPTIONAL=1)", file=sys.stderr)
        return 2

    engine, validate = make_engine(schema)
    documents: dict[str, dict] = {}
    for path in files:
        try:
            documents[path.name] = load(yaml, loader, path)
        except (yaml.YAMLError, ValueError) as exc:
            errors.append(f"settings/{path.name}: cannot be read: {exc}")

    defaults = documents.get("default.yaml")
    if defaults is None:
        errors.append("settings/default.yaml is missing or unreadable")
        defaults = {}

    alone = {key: value for key, value in schema.items() if key != "required"}
    checked = 0
    for name, document in documents.items():
        for error in validate({**defaults, **document}, schema):
            errors.append(f"settings/{name} (merged over default.yaml): {error}")
        checked += 1
        if name == "example.yaml":
            for error in validate(document, alone):
                errors.append(f"settings/{name} (alone): {error}")

    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"{len(errors)} finding(s) in {checked} settings files ({engine} validator)", file=sys.stderr)
        return 1
    print(f"ok: {checked} settings files match {SCHEMA_PATH.relative_to(ROOT)} ({engine} validator)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
