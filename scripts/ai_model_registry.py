#!/usr/bin/env python3
"""Load and validate CodeGuide's runner-neutral AI model registry."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


VALID_PHASES = {"planning", "review", "code", "implementation"}


class RegistryError(ValueError):
    """Raised when a registry is structurally invalid."""


def _fail(message: str) -> None:
    raise RegistryError(message)


def _scalar(value: Any, field: str) -> str:
    if not isinstance(value, str):
        _fail(f"{field} must be a string")
    if not value.strip():
        _fail(f"{field} must not be empty")
    if any(ch in value for ch in ("\t", "\n", "\r")):
        _fail(f"{field} must not contain tabs or newlines")
    return value


def _string_list(value: Any, field: str, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list):
        _fail(f"{field} must be a list")
    if not value and not allow_empty:
        _fail(f"{field} must be a non-empty list")
    return [_scalar(item, f"{field}[]") for item in value]


def load_registry(path: Path) -> dict[str, Any]:
    try:
        registry = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _fail(f"invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}")
    except OSError as exc:
        _fail(str(exc))
    if not isinstance(registry, dict):
        _fail("root must be an object")
    validate_registry(registry)
    return registry


def resolve_model_route(registry: dict[str, Any], value: str) -> str:
    if value in registry["models"]:
        return value
    return registry["aliases"].get(value, value)


def model_for_route(registry: dict[str, Any], route: str) -> dict[str, Any]:
    models = registry["models"]
    if route not in models:
        _fail(f"unknown model route: {route}")
    return models[route]


def runner_for_route(registry: dict[str, Any], route: str) -> dict[str, Any]:
    model = model_for_route(registry, route)
    return registry["runners"][model["runner"]]


def fallback_for(registry: dict[str, Any], route: str, phase: str) -> str | None:
    route = resolve_model_route(registry, route)
    model = model_for_route(registry, route)
    quota_group = model["quota_group"]
    phase_norm = phase.lower().strip()
    for rule in registry["fallback_policy"]["on_quota_exhausted"]:
        if rule["from_quota_group"] != quota_group:
            continue
        if phase_norm not in rule["phases"]:
            continue
        return resolve_model_route(registry, rule["to"])
    return None


def quota_error_patterns(registry: dict[str, Any]) -> list[str]:
    return list(registry["quota_error_patterns"])


def is_quota_error(registry: dict[str, Any], text: str) -> bool:
    folded = text.lower()
    return any(pattern.lower() in folded for pattern in quota_error_patterns(registry))


def validate_registry(registry: dict[str, Any]) -> None:
    default_alias = _scalar(registry.get("default_model_alias", ""), "default_model_alias")
    default_task_phase = _scalar(registry.get("default_task_phase", "planning"), "default_task_phase").lower()
    if default_task_phase not in VALID_PHASES:
        _fail("default_task_phase must be planning, review, code, or implementation")

    runners = registry.get("runners")
    if not isinstance(runners, dict) or not runners:
        _fail("runners must be a non-empty object")
    for runner_id, runner in runners.items():
        _scalar(runner_id, "runners key")
        if not isinstance(runner, dict):
            _fail(f"runners[{runner_id!r}] must be an object")
        _scalar(runner.get("binary", ""), f"runners[{runner_id!r}].binary")
        env_binary = runner.get("env_binary", "")
        if env_binary not in ("", None):
            _scalar(env_binary, f"runners[{runner_id!r}].env_binary")
        command_kind = _scalar(runner.get("command_kind", ""), f"runners[{runner_id!r}].command_kind")
        if command_kind not in {"agy", "claude_code", "manual"}:
            _fail(f"runners[{runner_id!r}].command_kind must be agy, claude_code, or manual")

    models = registry.get("models")
    if not isinstance(models, dict) or not models:
        _fail("models must be a non-empty object")
    quota_groups: set[str] = set()
    for route, model in models.items():
        _scalar(route, "models key")
        if ":" not in route:
            _fail(f"model route must include runner prefix: {route}")
        if not isinstance(model, dict):
            _fail(f"models[{route!r}] must be an object")
        runner_id = _scalar(model.get("runner", ""), f"models[{route!r}].runner")
        if runner_id not in runners:
            _fail(f"models[{route!r}].runner references unknown runner: {runner_id}")
        _scalar(model.get("cli_model", ""), f"models[{route!r}].cli_model")
        quota_group = _scalar(model.get("quota_group", ""), f"models[{route!r}].quota_group")
        quota_groups.add(quota_group)
        display_name = model.get("display_name", route)
        _scalar(display_name, f"models[{route!r}].display_name")

    aliases = registry.get("aliases")
    if not isinstance(aliases, dict) or not aliases:
        _fail("aliases must be a non-empty object")
    for alias, route in aliases.items():
        _scalar(alias, "aliases key")
        route = _scalar(route, f"aliases[{alias!r}]")
        if route not in models:
            _fail(f"aliases[{alias!r}] references unknown model route: {route}")

    if resolve_model_route(registry, default_alias) not in models:
        _fail("default_model_alias must resolve to a known model route")
    for index, alias in enumerate(_string_list(registry.get("default_reviewer_aliases"), "default_reviewer_aliases")):
        if resolve_model_route(registry, alias) not in models:
            _fail(f"default_reviewer_aliases[{index}] must resolve to a known model route")

    fallback_policy = registry.get("fallback_policy")
    if not isinstance(fallback_policy, dict):
        _fail("fallback_policy must be an object")
    if fallback_policy.get("fail_closed_for_unregistered_models") is not True:
        _fail("fallback_policy.fail_closed_for_unregistered_models must be true")
    rules = fallback_policy.get("on_quota_exhausted")
    if not isinstance(rules, list):
        _fail("fallback_policy.on_quota_exhausted must be a list")
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict):
            _fail(f"fallback_policy.on_quota_exhausted[{index}] must be an object")
        from_group = _scalar(rule.get("from_quota_group", ""), f"fallback_policy.on_quota_exhausted[{index}].from_quota_group")
        if from_group not in quota_groups:
            _fail(f"fallback_policy.on_quota_exhausted[{index}].from_quota_group references unknown quota group: {from_group}")
        phases = _string_list(rule.get("phases"), f"fallback_policy.on_quota_exhausted[{index}].phases")
        for phase in phases:
            if phase.lower() not in VALID_PHASES:
                _fail(f"fallback_policy.on_quota_exhausted[{index}].phases contains invalid phase: {phase}")
        target = resolve_model_route(registry, _scalar(rule.get("to", ""), f"fallback_policy.on_quota_exhausted[{index}].to"))
        if target not in models:
            _fail(f"fallback_policy.on_quota_exhausted[{index}].to references unknown model route: {target}")

    _string_list(registry.get("quota_error_patterns"), "quota_error_patterns")


def emit_shell(registry: dict[str, Any]) -> None:
    def emit(*parts: str) -> None:
        print("\t".join(parts))

    emit("default_model", resolve_model_route(registry, registry["default_model_alias"]))
    emit("default_task_phase", registry.get("default_task_phase", "planning"))
    for alias, route in registry["aliases"].items():
        emit("alias", alias, route)
    for runner_id, runner in registry["runners"].items():
        emit(
            "runner",
            runner_id,
            runner["binary"],
            runner.get("env_binary") or "",
            runner["command_kind"],
        )
    for route, model in registry["models"].items():
        emit(
            "model",
            route,
            model["runner"],
            model["cli_model"],
            model["quota_group"],
            model.get("display_name", route),
        )
    for alias in registry["default_reviewer_aliases"]:
        emit("default_reviewer", resolve_model_route(registry, alias))
    for rule in registry["fallback_policy"]["on_quota_exhausted"]:
        target = resolve_model_route(registry, rule["to"])
        for phase in rule["phases"]:
            emit("fallback", rule["from_quota_group"], phase.lower(), target)
    for pattern in registry["quota_error_patterns"]:
        emit("quota_pattern", pattern)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["validate", "emit-shell"])
    parser.add_argument("registry", type=Path)
    args = parser.parse_args(argv)

    try:
        registry = load_registry(args.registry)
    except RegistryError as exc:
        print(f"[ERROR] Invalid model registry {args.registry}: {exc}", file=sys.stderr)
        return 1

    if args.command == "emit-shell":
        emit_shell(registry)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
