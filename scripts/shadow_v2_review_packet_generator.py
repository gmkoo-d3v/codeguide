#!/usr/bin/env python3
"""Generate bounded Shadow v2 review packets.

The generator prepares a minimal handoff packet for independent review. It does
not call reviewers, write shadow docs, or convert reviewer agreement into
evidence.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from codeguide_paths import docs_root_for, resolve_project_root
from shadow_v2_gate_skeleton import (
    REVIEW_ROUTES,
    is_placeholder_approval_value,
    is_tool_identity,
    review_route_blockers,
    scope_status,
)


PASS = 0
BLOCKED = 1
USAGE_ERROR = 64


def emit_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def stable_digest(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def single_line(value: Any) -> str:
    return str(value).replace("\n", " ").replace("\r", " ").strip()


def has_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def load_json_file(path: str, label: str) -> dict[str, Any]:
    try:
        parsed = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} must be valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError(f"{label} must be a JSON object")
    return parsed


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


def bounded_refs_from_value(value: Any, limit: int = 20) -> list[str]:
    refs: list[str] = []

    def visit(item: Any) -> None:
        if len(refs) >= limit:
            return
        if isinstance(item, dict):
            for key, child in item.items():
                if key in {
                    "source_ref",
                    "trace_ref",
                    "scenario_ref",
                    "target_shadow_file",
                    "anchor_file",
                    "probe_result_ref",
                    "output",
                } and has_text(child):
                    text = str(child).strip()
                    if text not in refs:
                        refs.append(text)
                else:
                    visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)

    visit(value)
    return refs


def summarize_json_artifact(kind: str, path: str, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "kind": kind,
        "path": path,
        "status": payload.get("status", "unknown"),
        "writes_shadow_docs": payload.get("writes_shadow_docs", False),
        "auto_promotes_facts": payload.get("auto_promotes_facts", False),
        "source_refs": bounded_refs_from_value(payload),
        "hash": stable_digest(payload),
    }


def review_provenance(
    route: str,
    external_requested: bool,
    external_approval_ref: str | None,
    external_approved_next_step: str | None,
    external_recorded_by: str | None,
) -> str:
    if route == "external_gemini_claude":
        if (
            external_requested
            and not is_placeholder_approval_value(external_approval_ref)
            and not is_placeholder_approval_value(external_approved_next_step)
            and external_recorded_by
            and external_recorded_by.strip()
            and not is_tool_identity(external_recorded_by)
        ):
            return "external_user_approved"
        if external_requested:
            return "external_review_missing_approval_provenance"
        return "external_review_missing_user_request"
    return "internal_md_handoff"


def render_markdown(payload: dict[str, Any]) -> str:
    response_fields = payload["required_response_fields"]
    lines = [
        "# Shadow v2 Review Packet",
        "",
        f"- review_packet_id: {payload['review_packet_id']}",
        f"- review_route: {payload['review_route']}",
        f"- created_at: {payload['created_at']}",
        f"- task_id: {payload['task_id']}",
        "- generated_by: shadow_v2_review_packet_generator.py",
        "- writes_shadow_docs: false",
        "- auto_promotes_facts: false",
        f"- privacy_boundary: {payload['privacy_boundary']}",
        f"- review_provenance: {payload['review_provenance']}",
        f"- external_review_approval_ref: {payload['external_review_approval_ref']}",
        f"- external_review_approved_next_step: {payload['external_review_approved_next_step']}",
        f"- external_review_recorded_by: {payload['external_review_recorded_by']}",
        f"- unsupported_by_packet: {', '.join(payload['unsupported_by_packet']) if payload['unsupported_by_packet'] else 'none'}",
        "",
    ]
    if payload["blockers"]:
        lines.extend(["## Blockers", ""])
        for blocker in payload["blockers"]:
            lines.append(f"- {single_line(blocker)}")
        lines.append("")

    lines.extend(
        [
            "## Source Refs",
            "",
        ]
    )
    if payload["source_refs"]:
        for source_ref in payload["source_refs"]:
            lines.append(f"- {single_line(source_ref)}")
    else:
        lines.append("- none supplied")

    lines.extend(["", "## Artifact Summaries", ""])
    if not payload["artifacts"]:
        lines.append("- no artifacts supplied")
    for artifact in payload["artifacts"]:
        lines.extend(
            [
                f"- kind: {artifact['kind']}",
                f"  path: {single_line(artifact['path'])}",
                f"  status: {single_line(artifact['status'])}",
                f"  writes_shadow_docs: {str(artifact['writes_shadow_docs']).lower()}",
                f"  auto_promotes_facts: {str(artifact['auto_promotes_facts']).lower()}",
                f"  hash: {artifact['hash']}",
            ]
        )
        if artifact["source_refs"]:
            lines.append("  source_refs: " + ", ".join(single_line(ref) for ref in artifact["source_refs"]))

    lines.extend(
        [
            "",
            "## Review Instructions",
            "",
            "- Critique contract gaps, unsupported claims, unsafe promotion paths, missing provenance, privacy leaks, and stale evidence.",
            "- Treat this packet as bounded context; anything not included is unsupported by packet.",
            "- Do not treat model agreement as evidence.",
            "- Do not recommend confirmed facts unless deterministic evidence or explicit user-decision provenance exists.",
            "",
            "## Expected Response Fields",
            "",
            "- verdict: accept | revise | blocked",
        ]
    )
    for field in response_fields:
        if field != "verdict":
            lines.append(f"- {field}:")
    return "\n".join(lines) + "\n"


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], list[str]]:
    project_root = resolve_project_root(Path(args.project_root))
    scope, scope_blockers = scope_status(project_root, args.project_id)
    blockers = review_route_blockers(
        args.review_route,
        args.external_review_requested,
        args.external_review_approval_ref,
        args.external_review_approved_next_step,
        args.external_review_recorded_by,
    )
    if args.enable_hints:
        blockers.extend(scope_blockers)

    artifacts: list[dict[str, Any]] = []
    source_refs: list[str] = []

    for explicit_ref in args.source_refs or []:
        if explicit_ref.strip() and explicit_ref.strip() not in source_refs:
            source_refs.append(explicit_ref.strip())

    for kind, paths in (
        ("candidate", args.candidates or []),
        ("probe_result", args.probe_results or []),
        ("writer_result", args.writer_results or []),
        ("user_decision_packet", args.user_decision_packets or []),
    ):
        for path in paths:
            payload = load_json_file(path, f"--{kind.replace('_', '-')}")
            summary = summarize_json_artifact(kind, path, payload)
            artifacts.append(summary)
            for source_ref in summary["source_refs"]:
                if source_ref not in source_refs:
                    source_refs.append(source_ref)

    unsupported_by_packet: list[str] = []
    if not source_refs:
        unsupported_by_packet.append("source_refs")
    if not artifacts:
        unsupported_by_packet.append("evidence_artifacts")
    if args.review_route == "external_gemini_claude":
        if not args.external_review_requested:
            unsupported_by_packet.append("external_review_user_request")
        if is_placeholder_approval_value(args.external_review_approval_ref):
            unsupported_by_packet.append("external_review_approval_ref")
        if is_placeholder_approval_value(args.external_review_approved_next_step):
            unsupported_by_packet.append("external_review_approved_next_step")
        if (
            not args.external_review_recorded_by
            or not args.external_review_recorded_by.strip()
            or is_tool_identity(args.external_review_recorded_by)
        ):
            unsupported_by_packet.append("external_review_recorded_by")

    payload_base = {
        "task_id": args.task_id,
        "review_route": args.review_route,
        "source_refs": source_refs[:20],
        "artifacts": artifacts,
    }
    if args.review_route == "external_gemini_claude":
        required_response_fields = [
            "verdict",
            "summary",
            "strengths",
            "risks",
            "requested_changes",
        ]
    else:
        required_response_fields = [
            "verdict",
            "priority_findings",
            "contract_mismatches",
            "missing_evidence",
            "residual_risks",
        ]

    payload = {
        "status": "blocked" if blockers else "ok",
        "blockers": blockers,
        "review_packet_id": "RVP-" + hashlib.sha256(json.dumps(payload_base, sort_keys=True).encode("utf-8")).hexdigest()[:16],
        "artifact_kind": "shadow_v2_review_packet",
        "task_id": args.task_id,
        "review_route": args.review_route,
        "created_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generated_by": "shadow_v2_review_packet_generator.py",
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
        "privacy_boundary": "packet_only_no_workspace_dump",
        "review_provenance": review_provenance(
            args.review_route,
            args.external_review_requested,
            args.external_review_approval_ref,
            args.external_review_approved_next_step,
            args.external_review_recorded_by,
        ),
        "external_review_approval_ref": args.external_review_approval_ref or "not_required",
        "external_review_approved_next_step": args.external_review_approved_next_step or "not_required",
        "external_review_recorded_by": args.external_review_recorded_by or "not_required",
        "scope": scope,
        "source_refs": source_refs[:20],
        "artifacts": artifacts,
        "unsupported_by_packet": unsupported_by_packet,
        "required_response_fields": required_response_fields,
    }
    return payload, blockers


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a bounded Shadow v2 review packet.")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--project-id")
    parser.add_argument("--task-id", default="shadow-effect-map-01")
    parser.add_argument("--review-route", default="codex_subagent_md_handoff", choices=sorted(REVIEW_ROUTES))
    parser.add_argument("--external-review-requested", action="store_true")
    parser.add_argument("--external-review-approval-ref")
    parser.add_argument("--external-review-approved-next-step")
    parser.add_argument("--external-review-recorded-by")
    parser.add_argument("--enable-hints", action="store_true")
    parser.add_argument("--source-ref", dest="source_refs", action="append")
    parser.add_argument("--candidate", dest="candidates", action="append")
    parser.add_argument("--probe-result", dest="probe_results", action="append")
    parser.add_argument("--writer-result", dest="writer_results", action="append")
    parser.add_argument("--user-decision-packet", dest="user_decision_packets", action="append")
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
                    "review_packet_id": payload["review_packet_id"],
                    "writes_shadow_docs": False,
                    "auto_promotes_facts": False,
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
