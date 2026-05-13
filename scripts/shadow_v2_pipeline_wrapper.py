#!/usr/bin/env python3
"""Supervised dry-run pipeline wrapper for Shadow v2 automation.

The wrapper composes the existing shadow helpers into an auditable plan. Phase 3
does not execute write steps, does not call external reviewers, and always stops
before final shadow apply.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shlex
import sys
from pathlib import Path
from typing import Any

from codeguide_paths import docs_root_for, resolve_project_root
from shadow_v2_gate_skeleton import (
    REVIEW_ROUTES,
    close_review_blockers,
    completed_review_artifacts,
    review_route_blockers,
    scope_status,
)


PASS = 0
BLOCKED = 1
USAGE_ERROR = 64


def emit_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def has_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def single_line(value: Any) -> str:
    return str(value).replace("\n", " ").replace("\r", " ").strip()


def command_text(command: list[str]) -> str:
    return " ".join(shlex.quote(item) for item in command)


def ensure_output_allowed(project_root: Path, output: Path) -> None:
    resolved = output.resolve(strict=False)
    docs_root = docs_root_for(project_root).resolve(strict=False)
    docs_shadow = (docs_root / "shadow").resolve(strict=False)
    try:
        resolved.relative_to(docs_root)
    except ValueError as exc:
        raise ValueError("--output must be under project docs") from exc
    try:
        resolved.relative_to(docs_shadow)
    except ValueError:
        return
    raise ValueError("--output must not be under docs/shadow")


def script_path(name: str) -> str:
    return str(Path(__file__).with_name(name))


def base_command(script: str, project_root: Path) -> list[str]:
    return [sys.executable, script_path(script), "--project-root", str(project_root)]


def append_repeated(command: list[str], flag: str, values: list[str] | None) -> None:
    for value in values or []:
        command.extend([flag, value])


def step(step_id: str, status: str, reason: str, command: list[str] | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": step_id,
        "status": status,
        "reason": reason,
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
    }
    if command:
        payload["command"] = command
        payload["command_text"] = command_text(command)
    return payload


def user_decision_command(args: argparse.Namespace, project_root: Path) -> list[str]:
    command = base_command("shadow_v2_user_decision_assistant.py", project_root)
    command.extend(["--task-id", args.task_id])
    if args.enable_hints:
        command.append("--enable-hints")
    if args.evidence_input:
        command.extend(["--input", args.evidence_input])
    append_repeated(command, "--writer-result", args.writer_results)
    return command


def review_packet_command(args: argparse.Namespace, project_root: Path) -> list[str]:
    command = base_command("shadow_v2_review_packet_generator.py", project_root)
    command.extend(["--task-id", args.task_id, "--review-route", args.review_route])
    if args.external_review_requested:
        command.append("--external-review-requested")
    if args.external_review_approval_ref:
        command.extend(["--external-review-approval-ref", args.external_review_approval_ref])
    if args.external_review_approved_next_step:
        command.extend(["--external-review-approved-next-step", args.external_review_approved_next_step])
    if args.external_review_recorded_by:
        command.extend(["--external-review-recorded-by", args.external_review_recorded_by])
    if args.enable_hints:
        command.append("--enable-hints")
    append_repeated(command, "--source-ref", args.source_refs)
    append_repeated(command, "--candidate", args.candidates)
    append_repeated(command, "--probe-result", args.probe_results)
    append_repeated(command, "--writer-result", args.writer_results)
    append_repeated(command, "--user-decision-packet", args.user_decision_packets)
    return command


def close_review_step(args: argparse.Namespace, close_blockers: list[str]) -> dict[str, Any]:
    blockers = close_blockers
    if blockers:
        return step("close_review_gate", "blocked", "; ".join(blockers))
    if args.close_required_review:
        return step("close_review_gate", "satisfied", "all required review routes completed")
    return step("close_review_gate", "not_required", "no combined close review gate requested")


def writer_dry_run_command(args: argparse.Namespace, project_root: Path) -> tuple[list[str], list[str]]:
    missing: list[str] = []
    command = base_command("shadow_effect_writer.py", project_root)
    if args.record:
        command.extend(["--record", args.record])
    else:
        missing.append("--record")
    if args.candidate:
        command.extend(["--candidate", args.candidate])
    else:
        missing.append("--candidate")
    if args.user_decision:
        command.extend(["--user-decision", args.user_decision])
    else:
        missing.append("--user-decision")
    append_repeated(command, "--probe-result", args.probe_results)
    append_repeated(command, "--evidence-decision", args.evidence_decisions)
    if args.target_shadow_file:
        command.extend(["--target-shadow-file", args.target_shadow_file])
    else:
        missing.append("--target-shadow-file")
    command.extend(["--mode", "dry-run"])
    return command, missing


def build_steps(
    args: argparse.Namespace,
    project_root: Path,
    scope_blockers: list[str],
    route_blockers: list[str],
    close_blockers: list[str],
) -> list[dict[str, Any]]:
    steps: list[dict[str, Any]] = []
    if scope_blockers and args.enable_hints:
        steps.append(step("resolve_project_scope", "blocked", "; ".join(scope_blockers)))
    else:
        steps.append(step("resolve_project_scope", "ok", "project scope resolved; hint mode remains hint-only"))

    steps.append(step("read_shadow_navigation", "manual", "read docs/shadow router and affected unit docs before source expansion"))

    if args.enable_hints:
        status = "ok" if not scope_blockers else "blocked"
        reason = "hint-only lookup may run after verified scope" if not scope_blockers else "hint lookup blocked until scope is verified"
    else:
        status = "skipped"
        reason = "hint lookup disabled for this run"
    steps.append(step("collect_hint_anchors", status, reason))

    if args.probe_results:
        steps.append(step("run_deterministic_probes", "satisfied", "probe-result artifacts supplied"))
    else:
        steps.append(step("run_deterministic_probes", "pending_input", "provide structured probe args or probe-result artifacts"))

    steps.append(
        step(
            "generate_user_decision_packet",
            "ready",
            "build bounded user-only question packet",
            user_decision_command(args, project_root),
        )
    )

    review_status = "blocked" if route_blockers else "ready"
    steps.append(
        step(
            "generate_review_packet",
            review_status,
            "; ".join(route_blockers) if route_blockers else "build packet-only independent review handoff",
            review_packet_command(args, project_root),
        )
    )
    steps.append(close_review_step(args, close_blockers))

    writer_command, writer_missing = writer_dry_run_command(args, project_root)
    writer_status = "pending_input" if writer_missing else "ready"
    writer_reason = "missing " + ", ".join(writer_missing) if writer_missing else "run writer in dry-run mode only"
    steps.append(step("writer_dry_run", writer_status, writer_reason, writer_command if not writer_missing else None))

    steps.append(
        step(
            "final_shadow_apply",
            "blocked",
            "Phase 3 wrapper stops before final apply; explicit final_shadow_apply provenance and writer gate are required",
        )
    )
    return steps


def render_markdown(payload: dict[str, Any]) -> str:
    lines = [
        "# Shadow v2 Supervised Pipeline",
        "",
        "- artifact_kind: shadow_v2_pipeline_plan",
        "- plan_kind: dry_run_plan",
        "- generated_by: shadow_v2_pipeline_wrapper.py",
        f"- generated_at: {payload['generated_at']}",
        f"- status: {payload['status']}",
        f"- task_id: {payload['task_id']}",
        "- writes_shadow_docs: false",
        "- auto_promotes_facts: false",
        "- executes_commands: false",
        "- final_apply: blocked",
        "",
    ]
    if payload["blockers"]:
        lines.extend(["## Blockers", ""])
        for blocker in payload["blockers"]:
            lines.append(f"- {single_line(blocker)}")
        lines.append("")
    if payload["completion_blockers"]:
        lines.extend(["## Completion Blockers", ""])
        for blocker in payload["completion_blockers"]:
            lines.append(f"- {single_line(blocker)}")
        lines.append("")
    if payload["completed_review_artifacts"]:
        lines.extend(["## Completed Review Artifacts", ""])
        for route, artifacts in payload["completed_review_artifacts"].items():
            for artifact in artifacts:
                lines.append(f"- route: {single_line(route)}")
                lines.append(f"  status: {single_line(artifact.get('status', 'unknown'))}")
                lines.append(f"  path: {single_line(artifact.get('path', ''))}")
                if artifact.get("sha256"):
                    lines.append(f"  sha256: {single_line(artifact['sha256'])}")
                if artifact.get("evaluator"):
                    lines.append(f"  evaluator: {single_line(artifact['evaluator'])}")
                if artifact.get("verdict"):
                    lines.append(f"  verdict: {single_line(artifact['verdict'])}")
        lines.append("")
    lines.extend(["## Steps", ""])
    for item in payload["steps"]:
        lines.extend(
            [
                f"- id: {item['id']}",
                f"  status: {item['status']}",
                f"  reason: {single_line(item['reason'])}",
            ]
        )
        if item.get("command_text"):
            lines.append(f"  command_hint: {single_line(item['command_text'])}")
    lines.extend(
        [
            "",
            "## Stop Conditions",
            "",
            "- stop when a user decision is required",
            "- stop when external review is requested without approval",
            "- stop when any required review route is blocked; do not substitute sub-agent acceptance for blocked external review",
            "- stop when deterministic probe args are missing",
            "- stop before final shadow apply",
            "- stop if repeated runs produce no new material evidence",
        ]
    )
    return "\n".join(lines) + "\n"


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], list[str]]:
    project_root = resolve_project_root(Path(args.project_root))
    scope, scope_blockers = scope_status(project_root, args.project_id)
    review_artifacts, artifact_blockers = completed_review_artifacts(args.completed_review_artifact, project_root)
    route_blockers = review_route_blockers(
        args.review_route,
        args.external_review_requested,
        args.external_review_approval_ref,
        args.external_review_approved_next_step,
        args.external_review_recorded_by,
    )
    close_blockers = [
        *artifact_blockers,
        *close_review_blockers(
            args.close_required_review,
            args.completed_review,
            args.blocked_review,
            review_artifacts,
            args.external_review_requested,
            args.external_review_approval_ref,
            args.external_review_approved_next_step,
            args.external_review_recorded_by,
        ),
    ]
    blockers: list[str] = []
    if args.enable_hints:
        blockers.extend(scope_blockers)
    blockers.extend(route_blockers)
    blockers.extend(close_blockers)
    steps = build_steps(args, project_root, scope_blockers, route_blockers, close_blockers)
    if any(item["status"] == "blocked" for item in steps):
        blockers.extend(item["reason"] for item in steps if item["status"] == "blocked" and item["id"] != "final_shadow_apply")
    blockers = list(dict.fromkeys(blockers))
    completion_blockers = [
        f"{item['id']}: {item['reason']}"
        for item in steps
        if item["status"] in {"pending_input", "blocked"}
    ]
    status = "blocked" if blockers else "incomplete" if completion_blockers else "dry_run_plan_generated"
    payload = {
        "status": status,
        "blockers": blockers,
        "completion_blockers": completion_blockers,
        "artifact_kind": "shadow_v2_pipeline_plan",
        "plan_kind": "dry_run_plan",
        "generated_by": "shadow_v2_pipeline_wrapper.py",
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "task_id": args.task_id,
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
        "executes_commands": False,
        "final_apply": "blocked",
        "close_required_reviews": args.close_required_review,
        "completed_reviews": args.completed_review,
        "completed_review_artifacts": review_artifacts,
        "blocked_reviews": args.blocked_review,
        "external_review_approval": {
            "requested": args.external_review_requested,
            "approval_ref": args.external_review_approval_ref or "",
            "approved_next_step": args.external_review_approved_next_step or "",
            "recorded_by": args.external_review_recorded_by or "",
        },
        "scope": scope,
        "steps": steps,
    }
    return payload, blockers


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a supervised Shadow v2 dry-run pipeline plan.")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--project-id")
    parser.add_argument("--task-id", default="shadow-effect-map-01")
    parser.add_argument("--enable-hints", action="store_true")
    parser.add_argument("--evidence-input")
    parser.add_argument("--review-route", default="codex_subagent_md_handoff", choices=sorted(REVIEW_ROUTES))
    parser.add_argument("--external-review-requested", action="store_true")
    parser.add_argument("--external-review-approval-ref")
    parser.add_argument("--external-review-approved-next-step")
    parser.add_argument("--external-review-recorded-by")
    parser.add_argument("--close-required-review", action="append", default=[])
    parser.add_argument("--completed-review", action="append", default=[])
    parser.add_argument("--completed-review-artifact", action="append", default=[])
    parser.add_argument("--blocked-review", action="append", default=[])
    parser.add_argument("--source-ref", dest="source_refs", action="append")
    parser.add_argument("--candidate", dest="candidates", action="append")
    parser.add_argument("--probe-result", dest="probe_results", action="append")
    parser.add_argument("--writer-result", dest="writer_results", action="append")
    parser.add_argument("--user-decision-packet", dest="user_decision_packets", action="append")
    parser.add_argument("--record")
    parser.add_argument("--candidate-file", dest="candidate")
    parser.add_argument("--user-decision")
    parser.add_argument("--evidence-decision", dest="evidence_decisions", action="append")
    parser.add_argument("--target-shadow-file")
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown")
    parser.add_argument("--output")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        project_root = resolve_project_root(Path(args.project_root))
        payload, blockers = build_payload(args)
        rendered = json.dumps(payload, sort_keys=True, indent=2) + "\n" if args.format == "json" else render_markdown(payload)
        if args.output:
            output_path = Path(args.output)
            ensure_output_allowed(project_root, output_path)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(rendered, encoding="utf-8")
            emit_json(
                {
                    "status": payload["status"],
                    "output": str(output_path),
                    "writes_shadow_docs": False,
                    "auto_promotes_facts": False,
                    "executes_commands": False,
                }
            )
        else:
            sys.stdout.write(rendered)
        return BLOCKED if blockers else PASS
    except (OSError, ValueError) as exc:
        emit_json({"status": "error", "error": str(exc), "writes_shadow_docs": False, "auto_promotes_facts": False})
        return USAGE_ERROR


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
