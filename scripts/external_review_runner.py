#!/usr/bin/env python3
"""Tool-neutral current-task debate runner for CodeGuide orchestration."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from ai_model_registry import VALID_PHASES, RegistryError, is_quota_error, load_registry, model_for_route, resolve_model_route, runner_for_route
from codeguide_paths import docs_root_for, external_cli_dir_for, orchestration_task_dir_for, resolve_project_root


REDACTIONS = [
    re.compile(r"sk-[A-Za-z0-9_\-]{16,}"),
    re.compile(r"sk-proj-[A-Za-z0-9_\-]{16,}"),
    re.compile(r"ghp_[A-Za-z0-9_]{16,}"),
]

REQUIRED_STANDARD_FIELDS = ("verdict", "summary", "strengths", "risks", "requested_changes")
REQUIRED_ADVERSARIAL_FIELDS = ("objection", "counterproposal", "rebuttal", "residual_risk")
PLATFORM_PERMISSION_PATTERNS = (
    "platform_permission_blocked",
    "permission layer",
    "private workspace egress",
    "private local project",
    "external egress",
    "blocked private workspace",
    "guardian reviewer",
)
AUTH_ERROR_PATTERNS = (
    "auth",
    "authentication",
    "not authenticated",
    "unauthorized",
    "sign in",
    "login required",
    "please login",
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def slug(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-") or "route"


def redact(text: str) -> str:
    redacted = text
    for pattern in REDACTIONS:
        redacted = pattern.sub("[REDACTED_SECRET]", redacted)
    return redacted


def sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def provenance_markdown(values: dict[str, Any]) -> str:
    lines = ["# External CLI Review Response Provenance", ""]
    for key, value in values.items():
        if isinstance(value, bool):
            rendered = str(value).lower()
        else:
            rendered = str(value)
        lines.append(f"- {key}: {rendered}")
    return "\n".join(lines) + "\n"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def current_task_dir(project_root: Path, task_id: str) -> Path:
    return orchestration_task_dir_for(project_root, task_id) / "current-task"


def command_for_route(registry: dict[str, Any], route: str, request_file: Path, response_file: Path, project_root: Path) -> list[str]:
    runner = runner_for_route(registry, route)
    binary = os.environ.get(runner.get("env_binary") or "", runner["binary"])
    prompt = (
        f"Read the Markdown request file at {request_file}. "
        "Return only the requested Markdown fields to stdout. "
        f"Command-level response path: {response_file}."
    )
    if runner["command_kind"] == "agy":
        return [
            binary,
            "--add-dir",
            str(project_root),
            "-p",
            prompt,
        ]
    if runner["command_kind"] == "claude_code":
        return [
            binary,
            "-p",
            prompt,
            "--no-session-persistence",
            "--tools",
            "",
            "--add-dir",
            str(project_root),
        ]
    if runner["command_kind"] == "codex_cli":
        return [
            binary,
            "exec",
            "--cd",
            str(project_root),
            "--sandbox",
            "read-only",
            "--ephemeral",
            "--output-last-message",
            str(response_file),
            prompt,
        ]
    raise ValueError(f"unsupported command_kind: {runner['command_kind']}")


def run_command_for_route(registry: dict[str, Any], route: str, command: list[str], response_file: Path) -> subprocess.CompletedProcess[str]:
    runner = runner_for_route(registry, route)
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    if runner["command_kind"] != "codex_cli" or result.returncode != 0:
        return result
    response_text = read_text(response_file) if response_file.exists() else ""
    stderr_text = result.stderr
    if result.stdout.strip():
        stderr_text = (stderr_text + "\n" + result.stdout).strip() + "\n"
    if not response_text.strip():
        stderr_text = stderr_text + f"[ERROR] codex final message file was empty: {response_file}\n"
        return subprocess.CompletedProcess(result.args, 1, "", stderr_text)
    return subprocess.CompletedProcess(result.args, 0, response_text, stderr_text)


def model_selection_for_route(registry: dict[str, Any], route: str) -> str:
    model_for_route(registry, route)
    return "preconfigured_runtime"


def quota_exhausted_message(registry: dict[str, Any], route: str) -> str:
    model = model_for_route(registry, route)
    return (
        f"[BLOCKED] Quota exhausted for route '{route}' (quota_group={model['quota_group']}).\n"
        f"Switch the globally selected model in runner '{model['runner']}' to a non-exhausted model, "
        "then rerun with a reviewer route that records that selection.\n"
        "Do not auto-edit runner settings from this wrapper.\n"
    )


def status_dir_for(debate_dir: Path) -> Path:
    return debate_dir / "status"


def route_status_file(debate_dir: Path, route: str) -> Path:
    return status_dir_for(debate_dir) / f"{slug(route)}.status.json"


def write_route_status(
    debate_dir: Path,
    route: str,
    status: str,
    *,
    registry: dict[str, Any],
    reason: str = "",
    details: dict[str, Any] | None = None,
) -> None:
    model = model_for_route(registry, route)
    payload: dict[str, Any] = {
        "schema_version": "codeguide.external_review.status.v1",
        "updated_at": utc_now(),
        "status": status,
        "route": route,
        "runner": model["runner"],
        "cli_model": model["cli_model"],
        "model_selection": model_selection_for_route(registry, route),
    }
    if reason:
        payload["reason"] = reason
    if details:
        payload.update(details)
    write_text(route_status_file(debate_dir, route), json.dumps(payload, indent=2, sort_keys=True) + "\n")


def review_field(text: str, field: str) -> str:
    match = re.search(rf"(?im)^\s*-\s*{re.escape(field)}\s*:\s*(.*)$", text)
    return match.group(1).strip() if match else ""


def missing_review_fields(text: str, review_style: str = "standard") -> list[str]:
    required = list(REQUIRED_STANDARD_FIELDS)
    if review_style == "adversarial":
        required.extend(REQUIRED_ADVERSARIAL_FIELDS)
    missing = [field for field in required if not review_field(text, field)]
    verdict = review_field(text, "verdict").lower()
    if "verdict" not in missing and verdict not in {"accept", "revise", "blocked"}:
        missing.append("verdict")
    return missing


def classify_failure(registry: dict[str, Any], route: str, stderr_text: str) -> tuple[str, str]:
    if is_quota_error(registry, stderr_text):
        return "quota_blocked", quota_exhausted_message(registry, route).strip()
    folded = stderr_text.lower()
    if any(pattern in folded for pattern in PLATFORM_PERMISSION_PATTERNS):
        return (
            "platform_permission_blocked",
            "External CLI egress was blocked by the hosting platform permission layer; use the user-owned executor path.",
        )
    if any(pattern in folded for pattern in AUTH_ERROR_PATTERNS):
        return "auth_blocked", "External CLI authentication is required before this route can run."
    return "invalid_response", "External CLI command failed before producing a parser-compatible response."


def enqueue(args: argparse.Namespace) -> int:
    project_root = resolve_project_root(args.project_root)
    registry = load_registry(args.registry)
    if args.task_phase not in VALID_PHASES:
        print("[ERROR] --task-phase must be planning, review, code, or implementation", file=sys.stderr)
        return 64
    debate_dir = current_task_dir(project_root, args.task_id)
    responses_dir = debate_dir / "responses"
    provenance_dir = debate_dir / "provenance"
    status_dir = status_dir_for(debate_dir)
    responses_dir.mkdir(parents=True, exist_ok=True)
    provenance_dir.mkdir(parents=True, exist_ok=True)
    status_dir.mkdir(parents=True, exist_ok=True)

    if args.request_file:
        request_text = read_text(args.request_file)
    else:
        request_text = sys.stdin.read()
    if not request_text.strip():
        print("[ERROR] request content must not be empty", file=sys.stderr)
        return 64
    request_file = debate_dir / "request.md"
    write_text(request_file, redact(request_text))

    participant_values = args.participant or registry["default_reviewer_aliases"]
    participants = []
    for value in participant_values:
        if value == "codex:current":
            participants.append({"id": value, "role": "participant", "runner_route": "manual/current-thread"})
            continue
        route = resolve_model_route(registry, value)
        model_for_route(registry, route)
        participants.append({"id": route, "role": "reviewer", "runner_route": route})

    debate = {
        "schema_version": "codeguide.debate.v1",
        "task_id": args.task_id,
        "plan_version": args.plan_version,
        "review_round": args.review_round,
        "task_phase": args.task_phase,
        "coordinator": args.coordinator,
        "request_file": "request.md",
        "participants": participants,
        "response_contract": args.response_contract,
        "output_dir": "responses",
        "provenance_dir": "provenance",
        "external_cli_dir": str(external_cli_dir_for(project_root, args.task_id, args.plan_version, args.review_round).relative_to(docs_root_for(project_root))),
        "created_at": utc_now(),
    }
    write_text(debate_dir / "debate.json", json.dumps(debate, indent=2, sort_keys=True) + "\n")
    for participant in participants:
        route = participant["runner_route"]
        if route != "manual/current-thread":
            write_route_status(debate_dir, route, "pending", registry=registry)
    print(str(debate_dir / "debate.json"))
    return 0


def execute_debate(
    *,
    project_root: Path,
    registry: dict[str, Any],
    task_id: str,
    force: bool = False,
    dry_run: bool = False,
    runner_filter: str = "all",
    executor_kind: str = "direct",
) -> int:
    debate_dir = current_task_dir(project_root, task_id)
    debate_file = debate_dir / "debate.json"
    if not debate_file.is_file():
        print(f"[ERROR] debate file not found: {debate_file}", file=sys.stderr)
        return 64
    debate = json.loads(read_text(debate_file))
    request_file = debate_dir / debate["request_file"]
    request_text = read_text(request_file)
    phase = debate.get("task_phase", "planning")
    external_dir = external_cli_dir_for(project_root, debate["task_id"], debate["plan_version"], debate["review_round"])
    external_dir.mkdir(parents=True, exist_ok=True)

    failures = 0
    for participant in debate["participants"]:
        route = participant["runner_route"]
        if route == "manual/current-thread":
            continue
        route = resolve_model_route(registry, route)
        route_model = model_for_route(registry, route)
        if runner_filter != "all" and route_model["runner"] != runner_filter:
            continue
        route_slug = slug(route)
        current_response = debate_dir / "responses" / f"{route_slug}.response.md"
        current_provenance = debate_dir / "provenance" / f"{route_slug}.provenance.md"
        external_request = external_dir / f"{route_slug}.request.md"
        external_response = external_dir / f"{route_slug}.response.md"
        external_stderr = external_dir / f"{route_slug}.stderr.md"
        external_provenance = external_dir / f"{route_slug}.provenance.md"
        if current_response.exists() and not force:
            write_route_status(
                debate_dir,
                route,
                "ingested",
                registry=registry,
                details={"response_file": str(current_response), "provenance_file": str(current_provenance)},
            )
            continue
        write_text(external_request, request_text)

        actual_route = route
        fallback_triggered = False
        command = command_for_route(registry, route, external_request, external_response, project_root)
        if dry_run:
            print(" ".join(shlex.quote(part) for part in command))
            continue

        write_route_status(
            debate_dir,
            route,
            "running",
            registry=registry,
            details={
                "executor": executor_kind,
                "request_file": str(external_request),
                "response_file": str(external_response),
            },
        )
        result = run_command_for_route(registry, route, command, external_response)
        stderr_text = result.stderr
        stdout_text = result.stdout
        if result.returncode != 0:
            status, reason = classify_failure(registry, route, stderr_text)
            if status == "quota_blocked":
                stderr_text = stderr_text + "\n" + reason + "\n"
            write_text(external_stderr, redact(stderr_text))
            write_route_status(
                debate_dir,
                route,
                status,
                registry=registry,
                reason=reason,
                details={"stderr_file": str(external_stderr), "executor": executor_kind},
            )
            failures += 1
            continue
        response_text = redact(stdout_text)
        write_text(external_response, response_text)
        write_route_status(
            debate_dir,
            route,
            "executed",
            registry=registry,
            details={
                "executor": executor_kind,
                "request_file": str(external_request),
                "response_file": str(external_response),
            },
        )
        missing_fields = missing_review_fields(response_text, debate.get("review_style", "standard"))
        if missing_fields:
            write_text(external_stderr, f"[ERROR] response missing required fields: {', '.join(missing_fields)}\n")
            write_route_status(
                debate_dir,
                route,
                "invalid_response",
                registry=registry,
                reason=f"missing required fields: {', '.join(missing_fields)}",
                details={
                    "executor": executor_kind,
                    "request_file": str(external_request),
                    "response_file": str(external_response),
                    "stderr_file": str(external_stderr),
                },
            )
            failures += 1
            continue
        write_text(current_response, response_text)
        provenance = {
            "schema_version": "codeguide.debate.provenance.v1",
            "generated_at": utc_now(),
            "task_id": debate["task_id"],
            "plan_version": debate["plan_version"],
            "review_round": debate["review_round"],
            "requested_route": route,
            "actual_route": actual_route,
            "requested_cli_model": model_for_route(registry, route)["cli_model"],
            "requested_display_name": model_for_route(registry, route).get("display_name", route),
            "model_selection": model_selection_for_route(registry, actual_route),
            "quota_fallback_triggered": fallback_triggered,
            "request_file": str(external_request),
            "response_file": str(external_response),
            "response_sha256": sha256_text(response_text),
            "runner": model_for_route(registry, actual_route)["runner"],
            "raw_capture_deleted": True,
            "sanitized_response": True,
        }
        encoded = provenance_markdown(provenance)
        write_text(external_provenance, encoded)
        write_text(current_provenance, encoded)
        write_route_status(
            debate_dir,
            route,
            "ingested",
            registry=registry,
            details={
                "executor": executor_kind,
                "request_file": str(external_request),
                "response_file": str(current_response),
                "provenance_file": str(current_provenance),
                "external_response_file": str(external_response),
                "external_provenance_file": str(external_provenance),
            },
        )
    return 1 if failures else 0


def execute_once(args: argparse.Namespace) -> int:
    project_root = resolve_project_root(args.project_root)
    registry = load_registry(args.registry)
    return execute_debate(
        project_root=project_root,
        registry=registry,
        task_id=args.task_id,
        force=args.force,
        dry_run=args.dry_run,
        runner_filter=getattr(args, "runner", "all"),
        executor_kind="direct",
    )


def status(args: argparse.Namespace) -> int:
    project_root = resolve_project_root(args.project_root)
    debate_dir = current_task_dir(project_root, args.task_id)
    debate_file = debate_dir / "debate.json"
    if not debate_file.is_file():
        print(json.dumps({"status": "missing", "debate_file": str(debate_file)}, sort_keys=True))
        return 1
    debate = json.loads(read_text(debate_file))
    responses = sorted(path.name for path in (debate_dir / "responses").glob("*.response.md"))
    statuses = {}
    for path in sorted(status_dir_for(debate_dir).glob("*.status.json")):
        try:
            payload = json.loads(read_text(path))
        except json.JSONDecodeError:
            payload = {"status": "invalid_status_json", "file": str(path)}
        statuses[path.stem.removesuffix(".status")] = payload
    print(json.dumps({"status": "ok", "debate_file": str(debate_file), "responses": responses, "route_statuses": statuses}, sort_keys=True))
    return 0


def main(argv: list[str] | None = None) -> int:
    default_registry = Path(__file__).resolve().parent.parent / "config" / "ai_model_registry.json"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path("."))
    parser.add_argument("--registry", type=Path, default=Path(os.environ.get("CODEGUIDE_MODEL_REGISTRY", default_registry)))
    subparsers = parser.add_subparsers(dest="command", required=True)

    enqueue_parser = subparsers.add_parser("enqueue")
    enqueue_parser.add_argument("--task-id", required=True)
    enqueue_parser.add_argument("--plan-version", default="v1.0")
    enqueue_parser.add_argument("--review-round", default="r01")
    enqueue_parser.add_argument("--task-phase", default="planning")
    enqueue_parser.add_argument("--coordinator", default="human")
    enqueue_parser.add_argument("--response-contract", default="codeguide.review.v1")
    enqueue_parser.add_argument("--request-file", type=Path)
    enqueue_parser.add_argument("--participant", action="append")
    enqueue_parser.set_defaults(func=enqueue)

    run_parser = subparsers.add_parser("run-once")
    run_parser.add_argument("--task-id", required=True)
    run_parser.add_argument("--force", action="store_true")
    run_parser.add_argument("--dry-run", action="store_true")
    run_parser.add_argument("--runner", choices=["agy", "claude", "codex", "all"], default="all")
    run_parser.set_defaults(func=execute_once)

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("--task-id", required=True)
    status_parser.set_defaults(func=status)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (RegistryError, ValueError, OSError, subprocess.SubprocessError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
