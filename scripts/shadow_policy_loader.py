#!/usr/bin/env python3
"""Policy loader for shadow effect-map validator contracts.

This module reads the Markdown policy registries as declarations only. Runtime
authority stays with concrete probe adapters and writer-side probe reruns.
"""

from __future__ import annotations

import argparse
import functools
import importlib.util
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from codeguide_paths import docs_root_for


PASS = 0
FAIL = 1
USAGE_ERROR = 64

POLICY_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+@v[0-9]+$")
SOURCE_EVIDENCE_TYPES = {"code_call", "annotation", "code_reference", "config_binding"}


@dataclass(frozen=True)
class PolicyRegistry:
    validators: dict[str, str] = field(default_factory=dict)
    regex_patterns: dict[str, str] = field(default_factory=dict)
    rule_primaries: dict[str, dict[str, set[str]]] = field(default_factory=dict)
    rule_effect_types: dict[str, set[str]] = field(default_factory=dict)
    implemented_primary: set[str] = field(default_factory=set)
    parser_backed_now: set[str] = field(default_factory=set)
    source_probe_only: set[str] = field(default_factory=set)
    errors: tuple[str, ...] = ()


@dataclass(frozen=True)
class FencedBlock:
    language: str
    body: str
    start_line: int


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def parse_backtick_ids(text: str) -> set[str]:
    return {item for item in re.findall(r"`([^`]+@v[0-9]+)`", text) if POLICY_ID_RE.match(item)}


def read_policy_text(path: Path, label: str, errors: list[str]) -> str:
    if not path.is_file():
        errors.append(f"{label} is required for confirmed deterministic evidence")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def collect_fenced_blocks(text: str, label: str, errors: list[str]) -> list[FencedBlock]:
    blocks: list[FencedBlock] = []
    in_block = False
    language = ""
    start_line = 0
    body: list[str] = []
    for line_no, raw in enumerate(text.splitlines(), start=1):
        if raw.startswith("```"):
            if not in_block:
                in_block = True
                language = raw[3:].strip().lower()
                start_line = line_no
                body = []
                continue
            blocks.append(FencedBlock(language, "\n".join(body), start_line))
            in_block = False
            language = ""
            start_line = 0
            body = []
            continue
        if in_block:
            body.append(raw)
    if in_block:
        errors.append(f"{label} has an unclosed fenced code block starting at line {start_line}")
    return blocks


def yaml_blocks_for_roots(
    text: str,
    label: str,
    required_roots: tuple[str, ...],
    errors: list[str],
    single_roots: tuple[str, ...] = (),
) -> str:
    yaml_blocks = [block for block in collect_fenced_blocks(text, label, errors) if block.language in {"yaml", "yml"}]
    root_hits: dict[str, int] = {root: 0 for root in required_roots}
    root_pattern_by_key = {
        root: re.compile(r"^" + re.escape(root) + r":\s*(?:#.*)?$", re.MULTILINE) for root in required_roots
    }
    for block in yaml_blocks:
        for root, pattern in root_pattern_by_key.items():
            if pattern.search(block.body):
                root_hits[root] += 1
    for root, count in root_hits.items():
        if count == 0:
            errors.append(f"{label} must define {root} inside a fenced yaml block")
        elif root in single_roots and count > 1:
            errors.append(f"{label} must define exactly one fenced yaml {root} block")
    return "\n".join(block.body for block in yaml_blocks)


def collect_evidence_map(text: str, root_key: str, evidence_field: str) -> dict[str, str]:
    results: dict[str, str] = {}
    current_id = ""
    in_root = False
    id_pattern = re.compile(r"^\s+([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+@v[0-9]+):\s*$")
    field_pattern = re.compile(r"^\s+" + re.escape(evidence_field) + r":\s*([^ #]+)")
    for line in text.splitlines():
        if re.match(r"^" + re.escape(root_key) + r":\s*(?:#.*)?$", line):
            in_root = True
            current_id = ""
            continue
        if in_root and line and not line.startswith(" "):
            in_root = False
            current_id = ""
        if not in_root:
            continue
        id_match = id_pattern.match(line)
        if id_match:
            current_id = id_match.group(1)
            continue
        field_match = field_pattern.match(line)
        if current_id and field_match:
            results[current_id] = field_match.group(1).strip()
            current_id = ""
    return results


def collect_catalog_id_list(text: str, field_name: str) -> set[str]:
    in_root = False
    for line in text.splitlines():
        if re.match(r"^probe_coverage:\s*(?:#.*)?$", line):
            in_root = True
            continue
        if in_root and line and not line.startswith(" "):
            in_root = False
        if in_root and re.match(r"^\s+" + re.escape(field_name) + r":", line):
            return parse_inline_list(line.split(":", 1)[1])
    return set()


def parse_inline_list(value: str) -> set[str]:
    cleaned = value.strip()
    if cleaned.startswith("[") and cleaned.endswith("]"):
        cleaned = cleaned[1:-1]
    return {item.strip().strip('"\'`') for item in cleaned.split(",") if item.strip()}


def collect_rule_primaries(text: str) -> dict[str, dict[str, set[str]]]:
    primaries: dict[str, dict[str, set[str]]] = {}
    in_rules = False
    current_rule = ""
    current_evidence = ""
    rule_pattern = re.compile(r"^  ([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*):\s*$")
    evidence_pattern = re.compile(r"^        ([a-z_][a-z0-9_]*):\s*$")
    primary_pattern = re.compile(r"^          primary:\s*([^ #]+)")

    for line in text.splitlines():
        if line.startswith("rules:"):
            in_rules = True
            current_rule = ""
            current_evidence = ""
            continue
        if not in_rules:
            continue
        if line.startswith("promotion_gates:") or (line and not line.startswith((" ", "`")) and not line.startswith("rules:")):
            in_rules = False
            continue
        rule_match = rule_pattern.match(line)
        if rule_match:
            current_rule = rule_match.group(1)
            current_evidence = ""
            primaries.setdefault(current_rule, {})
            continue
        evidence_match = evidence_pattern.match(line)
        if current_rule and evidence_match:
            current_evidence = evidence_match.group(1)
            primaries[current_rule].setdefault(current_evidence, set())
            continue
        primary_match = primary_pattern.match(line)
        if current_rule and current_evidence and primary_match:
            primaries[current_rule][current_evidence].add(primary_match.group(1).strip())
    return primaries


def collect_rule_effect_types(text: str) -> dict[str, set[str]]:
    effect_types: dict[str, set[str]] = {}
    in_rules = False
    current_rule = ""
    rule_pattern = re.compile(r"^  ([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*):\s*$")
    effect_pattern = re.compile(r"^\s{4}allowed_effect_types:\s*(.+)$")

    for line in text.splitlines():
        if line.startswith("rules:"):
            in_rules = True
            current_rule = ""
            continue
        if not in_rules:
            continue
        if line.startswith("promotion_gates:") or (line and not line.startswith((" ", "`")) and not line.startswith("rules:")):
            in_rules = False
            continue
        rule_match = rule_pattern.match(line)
        if rule_match:
            current_rule = rule_match.group(1)
            continue
        effect_match = effect_pattern.match(line)
        if current_rule and effect_match:
            effect_types[current_rule] = parse_inline_list(effect_match.group(1))
    return effect_types


def load_policy_registry_from_dir(policy_root: Path) -> PolicyRegistry:
    errors: list[str] = []
    catalog_text = read_policy_text(policy_root / "shadow-validator-catalog.md", "shadow validator catalog", errors)
    regex_text = read_policy_text(policy_root / "shadow-regex-patterns.md", "shadow regex pattern registry", errors)
    rule_text = read_policy_text(policy_root / "shadow-rule-registry.md", "shadow rule registry", errors)
    catalog_yaml = (
        yaml_blocks_for_roots(
            catalog_text,
            "shadow validator catalog",
            ("validators", "probe_coverage"),
            errors,
            ("probe_coverage",),
        )
        if catalog_text
        else ""
    )
    regex_yaml = (
        yaml_blocks_for_roots(regex_text, "shadow regex pattern registry", ("regex_patterns",), errors, ("regex_patterns",))
        if regex_text
        else ""
    )
    rule_yaml = (
        yaml_blocks_for_roots(
            rule_text,
            "shadow rule registry",
            ("rules", "promotion_gates"),
            errors,
            ("rules", "promotion_gates"),
        )
        if rule_text
        else ""
    )
    validators = collect_evidence_map(catalog_yaml, "validators", "evidence_type") if catalog_yaml else {}
    regex_patterns = collect_evidence_map(regex_yaml, "regex_patterns", "target") if regex_yaml else {}
    rule_primaries = collect_rule_primaries(rule_yaml) if rule_yaml else {}
    rule_effect_types = collect_rule_effect_types(rule_yaml) if rule_yaml else {}
    implemented_primary = collect_catalog_id_list(catalog_yaml, "implemented_primary_v1") if catalog_yaml else set()
    parser_backed_now = collect_catalog_id_list(catalog_yaml, "parser_backed_now") if catalog_yaml else set()
    source_probe_only = collect_catalog_id_list(catalog_yaml, "source_probe_only") if catalog_yaml else set()
    if catalog_text:
        if not validators:
            errors.append("shadow validator catalog validators block must declare evidence_type entries")
        if not implemented_primary:
            errors.append("shadow validator catalog must declare implemented_primary_v1")
        if not parser_backed_now:
            errors.append("shadow validator catalog must declare parser_backed_now")
        if not source_probe_only:
            errors.append("shadow validator catalog must declare source_probe_only")
    if regex_text and not regex_patterns:
        errors.append("shadow regex pattern registry regex_patterns block must declare target entries")
    if rule_text:
        if not rule_primaries:
            errors.append("shadow rule registry rules block must declare primary mappings")
        if not rule_effect_types:
            errors.append("shadow rule registry rules block must declare allowed_effect_types")
    return PolicyRegistry(
        validators,
        regex_patterns,
        rule_primaries,
        rule_effect_types,
        implemented_primary,
        parser_backed_now,
        source_probe_only,
        tuple(errors),
    )


@functools.lru_cache(maxsize=8)
def load_policy_registry(project_root: Path) -> PolicyRegistry:
    return load_policy_registry_from_dir(docs_root_for(project_root) / "policy")


def import_adapter_module(adapter_module: Path) -> Any:
    spec = importlib.util.spec_from_file_location("shadow_evidence_probe_adapter_module", adapter_module)
    if spec is None or spec.loader is None:
        raise ValueError(f"cannot import adapter module: {adapter_module}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def adapter_specs_from_module(adapter_module: Path) -> dict[str, dict[str, Any]]:
    module = import_adapter_module(adapter_module)
    specs: dict[str, dict[str, Any]] = {}
    adapters = getattr(module, "PRIMARY_ADAPTERS", None)
    if adapters is not None:
        for item in adapters:
            if hasattr(item, "validator_id") and hasattr(item, "spec"):
                specs[str(item.validator_id)] = primary_spec_payload(item.spec)
        return specs
    validators = getattr(module, "PRIMARY_VALIDATORS", None)
    if isinstance(validators, dict):
        return {str(validator_id): primary_spec_payload(spec) for validator_id, spec in validators.items()}
    registry = getattr(module, "ADAPTER_REGISTRY", None)
    if registry is not None and hasattr(registry, "ids"):
        return {str(validator_id): {} for validator_id in registry.ids()}
    return {}


def adapter_ids_from_module(adapter_module: Path) -> set[str]:
    return set(adapter_specs_from_module(adapter_module).keys())


def primary_spec_payload(spec: Any) -> dict[str, Any]:
    return {
        "evidence_type": getattr(spec, "evidence_type", None),
        "kind": getattr(spec, "kind", None),
        "parser_backed": getattr(spec, "parser_backed", None),
        "promotion_limit": getattr(spec, "promotion_limit", None),
        "language": getattr(spec, "language", None),
        "allowed_paths": list(getattr(spec, "allowed_paths", ()) or ()),
        "excluded_paths": list(getattr(spec, "excluded_paths", ()) or ()),
    }


def parity_diagnostics(registry: PolicyRegistry, adapter_ids: set[str], adapter_specs: dict[str, dict[str, Any]] | None = None) -> list[str]:
    issues = list(registry.errors)
    adapter_specs = adapter_specs or {}
    declared_ids = set(registry.validators.keys())
    if not registry.implemented_primary:
        issues.append("shadow validator catalog must declare implemented_primary_v1")
    if not registry.parser_backed_now:
        issues.append("shadow validator catalog must declare parser_backed_now")
    if not registry.source_probe_only:
        issues.append("shadow validator catalog must declare source_probe_only")

    for validator_id in sorted(registry.implemented_primary):
        if validator_id not in declared_ids:
            issues.append(f"implemented_primary_v1 id must be declared in validators block: {validator_id}")
        if adapter_ids and validator_id not in adapter_ids:
            issues.append(f"implemented_primary_v1 id must be implemented by shadow_evidence_probe.py: {validator_id}")
        adapter_spec = adapter_specs.get(validator_id)
        if adapter_spec and registry.validators.get(validator_id) != adapter_spec.get("evidence_type"):
            issues.append(f"implemented_primary_v1 evidence_type must match AdapterRegistry for {validator_id}")

    for validator_id in sorted(adapter_ids):
        if validator_id not in registry.implemented_primary:
            issues.append(f"shadow_evidence_probe.py primary validator missing from implemented_primary_v1: {validator_id}")
        adapter_spec = adapter_specs.get(validator_id)
        if adapter_spec and validator_id in declared_ids and registry.validators.get(validator_id) != adapter_spec.get("evidence_type"):
            issues.append(f"validator catalog evidence_type must match AdapterRegistry for {validator_id}")
        if adapter_spec and adapter_spec.get("parser_backed") is True and validator_id not in registry.parser_backed_now:
            issues.append(f"parser-backed AdapterRegistry id missing from parser_backed_now: {validator_id}")
        if adapter_spec and adapter_spec.get("kind") == "source_probe" and validator_id not in registry.source_probe_only:
            issues.append(f"source_probe AdapterRegistry id missing from source_probe_only: {validator_id}")
        if (
            adapter_spec
            and adapter_spec.get("evidence_type") in SOURCE_EVIDENCE_TYPES
            and (not adapter_spec.get("allowed_paths") or not adapter_spec.get("excluded_paths"))
        ):
            issues.append(f"source AdapterRegistry id must declare allowed_paths and excluded_paths: {validator_id}")

    for validator_id in sorted(registry.parser_backed_now):
        if validator_id not in declared_ids:
            issues.append(f"parser_backed_now id must be declared in validators block: {validator_id}")
        if validator_id not in registry.implemented_primary:
            issues.append(f"parser_backed_now id must also be implemented_primary_v1: {validator_id}")
        adapter_spec = adapter_specs.get(validator_id)
        if adapter_spec and adapter_spec.get("parser_backed") is not True:
            issues.append(f"parser_backed_now id must be parser_backed in AdapterRegistry: {validator_id}")

    for validator_id in sorted(registry.source_probe_only):
        if validator_id not in declared_ids:
            issues.append(f"source_probe_only id must be declared in validators block: {validator_id}")
        if validator_id not in registry.implemented_primary:
            issues.append(f"source_probe_only id must also be implemented_primary_v1: {validator_id}")
        if validator_id in registry.parser_backed_now:
            issues.append(f"source_probe_only id must not also be parser_backed_now: {validator_id}")
        adapter_spec = adapter_specs.get(validator_id)
        if adapter_spec and (adapter_spec.get("kind") != "source_probe" or adapter_spec.get("parser_backed") is not False):
            issues.append(f"source_probe_only id must be source_probe and non-parser-backed in AdapterRegistry: {validator_id}")
    return issues


def registry_summary(registry: PolicyRegistry) -> dict[str, Any]:
    return {
        "validators": registry.validators,
        "regex_patterns": registry.regex_patterns,
        "rule_effect_types": {key: sorted(value) for key, value in sorted(registry.rule_effect_types.items())},
        "rule_primaries": {
            rule_id: {evidence_type: sorted(refs) for evidence_type, refs in sorted(mapping.items())}
            for rule_id, mapping in sorted(registry.rule_primaries.items())
        },
        "implemented_primary": sorted(registry.implemented_primary),
        "parser_backed_now": sorted(registry.parser_backed_now),
        "source_probe_only": sorted(registry.source_probe_only),
        "errors": list(registry.errors),
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Load shadow effect-map policy registries.")
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--project-root", help="Project root whose docs/policy directory should be loaded.")
    source.add_argument("--policy-dir", help="Policy directory containing shadow policy Markdown files.")
    parser.add_argument("--adapter-module", help="Probe module that exposes ADAPTER_REGISTRY or PRIMARY_ADAPTERS.")
    parser.add_argument("--print-policy-json", action="store_true", help="Print normalized policy registry JSON.")
    parser.add_argument("--print-adapter-ids", action="store_true", help="Print one primary adapter id per line.")
    parser.add_argument("--check-parity", action="store_true", help="Validate catalog implemented ids against probe adapters.")
    return parser.parse_args(argv)


def resolve_policy_dir(args: argparse.Namespace) -> Path:
    if args.policy_dir:
        return Path(args.policy_dir).resolve()
    if args.project_root:
        return docs_root_for(Path(args.project_root).resolve()) / "policy"
    raise ValueError("--project-root or --policy-dir is required")


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        adapter_specs: dict[str, dict[str, Any]] = {}
        adapter_ids: set[str] = set()
        if args.adapter_module:
            adapter_specs = adapter_specs_from_module(Path(args.adapter_module).resolve())
            adapter_ids = set(adapter_specs.keys())
        if args.print_adapter_ids:
            for validator_id in sorted(adapter_ids):
                print(validator_id)
            return PASS
        policy_dir = resolve_policy_dir(args)
        registry = load_policy_registry_from_dir(policy_dir)
        if args.check_parity:
            issues = parity_diagnostics(registry, adapter_ids, adapter_specs)
            emit({"status": "ok" if not issues else "fail", "errors": issues, "adapter_ids": sorted(adapter_ids)})
            return PASS if not issues else FAIL
        if args.print_policy_json:
            emit(registry_summary(registry))
            return PASS
        emit({"status": "ok", "errors": list(registry.errors)})
        return PASS if not registry.errors else FAIL
    except (OSError, ValueError, AttributeError) as exc:
        emit({"status": "error", "error": str(exc)})
        return USAGE_ERROR


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
