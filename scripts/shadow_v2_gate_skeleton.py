#!/usr/bin/env python3
"""Phase 0 gate skeleton for Shadow v2 automation.

This helper exposes the shared v2 contract before product-facing automation
starts. It validates scope, review route, batch-apply stubs, and evidence-type
boundaries without writing shadow docs or promoting facts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

from codeguide_paths import docs_root_for, resolve_project_root


PASS = 0
BLOCKED = 1
USAGE_ERROR = 64

CONFIRMABLE_EVIDENCE_TYPES = {"deterministic_code", "deterministic_runtime", "user_decision_fact_evidence"}
USER_FACT_DECISION_TYPES = {
    "business_intent",
    "business_risk",
    "bug_or_intended_design",
    "domain_intent",
    "effect_intent",
    "human_fact_evidence",
    "promotion_decision",
    "runtime_scenario_fit",
    "waiver_approval",
}
NON_CONFIRMING_EVIDENCE_TYPES = {
    "source_probe",
    "fallback_regex",
    "llm_hint",
    "auxiliary_hint",
    "model_consensus",
    "memory_hint",
    "vector_hint",
    "graph_hint",
    "serena_hint",
    "user_decision",
    "final_shadow_apply",
}
REVIEW_ROUTES = {
    "codex_subagent_md_handoff",
    "runtime_independent_session_md_handoff",
    "external_gemini_claude",
}
EXTERNAL_REVIEW_ROUTE = "external_gemini_claude"
EXTERNAL_REVIEW_EVALUATORS = {"gemini", "claude"}
STANDARD_EXTERNAL_REVIEW_FIELDS = ("summary", "strengths", "risks", "requested_changes")
ADVERSARIAL_EXTERNAL_REVIEW_FIELDS = ("objection", "counterproposal", "rebuttal", "residual_risk")
BLOCKED_REVIEW_MARKERS = (
    "status: blocked",
    "verdict: block",
    "verdict: blocked",
    "no_model_response",
    "policy-blocked",
    "policy blocked",
    "no usable response",
    "no durable response",
)
PLACEHOLDER_APPROVAL_VALUES = {
    "",
    "not_required",
    "pending_user_approval",
    "awaiting_approval",
    "none",
    "null",
    "n/a",
    "na",
    "tbd",
    "todo",
}
EVALUATOR_IDENTITIES = {"gemini", "claude", "codex", "external-review-wrapper", "external-cli"}


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def stable_digest(*values: str) -> str:
    joined = "\n".join(values)
    return "sha256:" + hashlib.sha256(joined.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def review_field(text: str, field: str) -> str | None:
    match = re.search(rf"(?im)^\s*(?:[-*]\s*)?{re.escape(field)}\s*:\s*(.+?)\s*$", text)
    if not match:
        return None
    return match.group(1).strip()


def normalized_text(value: str | None) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip().lower()


def is_placeholder_approval_value(value: str | None) -> bool:
    return normalized_text(value) in PLACEHOLDER_APPROVAL_VALUES


def is_tool_identity(value: str | None) -> bool:
    normalized = normalized_text(value)
    return normalized in EVALUATOR_IDENTITIES or normalized.startswith("external-cli")


def is_relative_to_path(path: Path, base: Path) -> bool:
    try:
        path.relative_to(base)
        return True
    except ValueError:
        return False


def request_file_for_response(path: Path, evaluator: str) -> Path:
    retry_name = f"{evaluator}.retry-response.md"
    request_name = f"{evaluator}.retry-request.md" if path.name == retry_name else f"{evaluator}.request.md"
    return path.with_name(request_name)


def provenance_file_for_response(path: Path) -> Path:
    return path.with_suffix(".provenance.md")


def validate_external_response_artifact(summary: dict[str, Any], path: Path, content: str, project_root: Path) -> list[str]:
    blockers: list[str] = []
    docs_external_root = (docs_root_for(project_root) / "orchestration" / "external-cli").resolve(strict=False)
    resolved_path = path.resolve(strict=True)
    if not is_relative_to_path(resolved_path, docs_external_root):
        blockers.append(
            f"completed external Gemini/Claude review artifact must be under docs/orchestration/external-cli: {path}"
        )
        return blockers

    evaluator = review_field(content, "evaluator")
    verdict = review_field(content, "verdict")
    if evaluator:
        summary["evaluator"] = evaluator
    if verdict:
        summary["verdict"] = verdict
    normalized_evaluator = normalized_text(evaluator)
    if normalized_evaluator not in EXTERNAL_REVIEW_EVALUATORS:
        for candidate in sorted(EXTERNAL_REVIEW_EVALUATORS):
            if path.name in {f"{candidate}.response.md", f"{candidate}.retry-response.md"}:
                normalized_evaluator = candidate
                summary["evaluator"] = candidate
                break
    if normalized_evaluator not in EXTERNAL_REVIEW_EVALUATORS:
        blockers.append(
            f"completed external Gemini/Claude review artifact requires evaluator gemini or claude in content or filename: {path}"
        )
        return blockers

    expected_names = {f"{normalized_evaluator}.response.md", f"{normalized_evaluator}.retry-response.md"}
    if path.name not in expected_names:
        blockers.append(
            f"completed external Gemini/Claude review artifact filename must match evaluator response file: {path}"
        )

    request_file = request_file_for_response(path, normalized_evaluator)
    summary["request_file"] = str(request_file)
    if not request_file.is_file():
        blockers.append(f"completed external Gemini/Claude review artifact requires companion request file: {request_file}")
        return blockers
    request_content = request_file.read_text(encoding="utf-8", errors="replace")
    if not request_content.strip():
        blockers.append(f"completed external Gemini/Claude review companion request file must be non-empty: {request_file}")
        return blockers

    request_evaluator = normalized_text(review_field(request_content, "evaluator"))
    if request_evaluator != normalized_evaluator:
        blockers.append(
            f"completed external Gemini/Claude review companion request evaluator must match response evaluator: {request_file}"
        )

    sanitized_response_file = review_field(request_content, "sanitized_response_file")
    if not sanitized_response_file:
        blockers.append(
            f"completed external Gemini/Claude review companion request requires sanitized_response_file: {request_file}"
        )
    else:
        sanitized_path = Path(sanitized_response_file).expanduser().resolve(strict=False)
        if sanitized_path != resolved_path:
            blockers.append(
                f"completed external Gemini/Claude review companion request sanitized_response_file must match artifact path: {request_file}"
            )

    command_response_path = review_field(request_content, "command_response_path")
    raw_path: Path | None = None
    if not command_response_path:
        blockers.append(
            f"completed external Gemini/Claude review companion request requires command_response_path: {request_file}"
        )
    else:
        raw_path = Path(command_response_path).expanduser().resolve(strict=False)
        summary["command_response_path"] = str(raw_path)
        if not is_relative_to_path(raw_path, docs_external_root):
            blockers.append(
                f"completed external Gemini/Claude review command_response_path must be under docs/orchestration/external-cli: {request_file}"
            )
        if raw_path.parent != resolved_path.parent:
            blockers.append(
                f"completed external Gemini/Claude review command_response_path must share the response directory: {request_file}"
            )
        if raw_path.name not in {
            f"{normalized_evaluator}.command-response.raw.md",
            f"{normalized_evaluator}.retry-command-response.raw.md",
        }:
            blockers.append(
                f"completed external Gemini/Claude review command_response_path filename must match evaluator raw capture: {request_file}"
            )
        if raw_path.exists():
            blockers.append(
                f"completed external Gemini/Claude review raw command capture must be sanitized and deleted: {raw_path}"
            )

    provenance_file = provenance_file_for_response(path)
    summary["provenance_file"] = str(provenance_file)
    if not provenance_file.is_file():
        blockers.append(f"completed external Gemini/Claude review artifact requires provenance manifest: {provenance_file}")
        return blockers
    provenance_content = provenance_file.read_text(encoding="utf-8", errors="replace")
    if not provenance_content.strip():
        blockers.append(f"completed external Gemini/Claude review provenance manifest must be non-empty: {provenance_file}")
        return blockers
    if review_field(provenance_content, "artifact_kind") != "external_cli_review_response_provenance":
        blockers.append(f"completed external Gemini/Claude review provenance manifest has invalid artifact_kind: {provenance_file}")
    if review_field(provenance_content, "generated_by") != "run_external_plan_reviews.sh":
        blockers.append(f"completed external Gemini/Claude review provenance manifest must be generated by run_external_plan_reviews.sh: {provenance_file}")
    review_style = normalized_text(review_field(provenance_content, "review_style"))
    if review_style not in {"standard", "adversarial"}:
        blockers.append(f"completed external Gemini/Claude review provenance manifest requires review_style standard or adversarial: {provenance_file}")
    if normalized_text(review_field(provenance_content, "evaluator")) != normalized_evaluator:
        blockers.append(f"completed external Gemini/Claude review provenance evaluator must match response evaluator: {provenance_file}")
    if normalized_text(review_field(provenance_content, "verdict")) != normalized_text(verdict):
        blockers.append(f"completed external Gemini/Claude review provenance verdict must match response verdict: {provenance_file}")
    manifest_response_file = review_field(provenance_content, "response_file")
    if not manifest_response_file:
        blockers.append(f"completed external Gemini/Claude review provenance manifest requires response_file: {provenance_file}")
    elif Path(manifest_response_file).expanduser().resolve(strict=False) != resolved_path:
        blockers.append(f"completed external Gemini/Claude review provenance response_file must match artifact path: {provenance_file}")
    if review_field(provenance_content, "response_sha256") != summary["sha256"]:
        blockers.append(f"completed external Gemini/Claude review provenance response_sha256 must match artifact hash: {provenance_file}")
    manifest_request_file = review_field(provenance_content, "request_file")
    if not manifest_request_file:
        blockers.append(f"completed external Gemini/Claude review provenance manifest requires request_file: {provenance_file}")
    elif Path(manifest_request_file).expanduser().resolve(strict=False) != request_file.resolve(strict=True):
        blockers.append(f"completed external Gemini/Claude review provenance request_file must match companion request: {provenance_file}")
    manifest_command_response_path = review_field(provenance_content, "command_response_path")
    if not manifest_command_response_path:
        blockers.append(f"completed external Gemini/Claude review provenance manifest requires command_response_path: {provenance_file}")
    elif raw_path is not None and Path(manifest_command_response_path).expanduser().resolve(strict=False) != raw_path:
        blockers.append(f"completed external Gemini/Claude review provenance command_response_path must match companion request: {provenance_file}")
    if normalized_text(review_field(provenance_content, "raw_capture_deleted")) != "true":
        blockers.append(f"completed external Gemini/Claude review provenance must record raw_capture_deleted: true: {provenance_file}")
    if normalized_text(review_field(provenance_content, "sanitized_response")) != "true":
        blockers.append(f"completed external Gemini/Claude review provenance must record sanitized_response: true: {provenance_file}")

    if not verdict:
        blockers.append(f"completed external Gemini/Claude review artifact requires verdict: {path}")
    elif verdict.strip().lower() != "accept":
        blockers.append(f"completed external Gemini/Claude review artifact verdict must be accept: {path}")
    for field in STANDARD_EXTERNAL_REVIEW_FIELDS:
        if not review_field(content, field):
            blockers.append(f"completed external Gemini/Claude review artifact requires parser-compatible field {field}: {path}")
    if review_style == "adversarial":
        for field in ADVERSARIAL_EXTERNAL_REVIEW_FIELDS:
            if not review_field(content, field):
                blockers.append(f"completed adversarial external Gemini/Claude review artifact requires parser-compatible field {field}: {path}")
    if any(marker in content.lower() for marker in BLOCKED_REVIEW_MARKERS):
        blockers.append(f"completed external Gemini/Claude review artifact contains blocked/error/no-response marker: {path}")
    return blockers


def contract_payload() -> dict[str, Any]:
    return {
        "phase": "shadow_v2_phase0_gate_skeleton",
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
        "batch_apply_enabled": False,
        "product_feature": False,
        "tracks": [
            "user_decision_assistant",
            "review_packet_generator",
            "supervised_pipeline_wrapper",
        ],
        "implementation_order": [
            "phase0_gate_skeleton",
            "user_decision_assistant",
            "review_packet_generator",
            "supervised_pipeline_wrapper",
            "java_parser_backed_adapter",
        ],
        "confirmable_evidence_types": sorted(CONFIRMABLE_EVIDENCE_TYPES),
        "user_fact_decision_types": sorted(USER_FACT_DECISION_TYPES),
        "non_fact_user_decision_types": ["final_shadow_apply"],
        "non_confirming_evidence_types": sorted(NON_CONFIRMING_EVIDENCE_TYPES),
        "default_review_route": "codex_subagent_md_handoff",
        "external_review_default": "user_requested_only",
        "combined_review_close_gate": "all_required_routes_must_complete",
        "blocked_required_review_behavior": "stop_without_substitution",
        "required_review_packet_fields": [
            "review_packet_id",
            "review_route",
            "created_at",
            "source_refs",
            "privacy_boundary",
            "review_provenance",
            "external_review_approval_ref",
            "external_review_approved_next_step",
            "external_review_recorded_by",
            "unsupported_by_packet",
        ],
    }


def scope_status(project_root: Path, project_id: str | None) -> tuple[dict[str, Any], list[str]]:
    root = resolve_project_root(project_root)
    docs_root = docs_root_for(root)
    shadow_root = docs_root / "shadow"
    policy_root = docs_root / "policy"
    identity = project_id.strip() if isinstance(project_id, str) and project_id.strip() else f"path:{root}"
    blockers: list[str] = []
    if not root.is_dir():
        blockers.append("project_root must exist and be a directory")
    if not docs_root.is_dir():
        blockers.append("docs_root must exist before automatic hint lookup")
    if not shadow_root.is_dir():
        blockers.append("docs/shadow must exist before automatic hint lookup")
    if not policy_root.is_dir():
        blockers.append("docs/policy must exist before automatic hint lookup")
    trigger_ref = stable_digest(str(root), str(docs_root), identity)
    return (
        {
            "project_root": str(root),
            "docs_root": str(docs_root),
            "project_identity": identity,
            "hint_activation": {
                "allowed": not blockers,
                "mode": "hint_only",
                "trigger": "project_scope_verified",
                "trigger_ref": trigger_ref,
                "logged_by": "shadow_v2_gate_skeleton.py",
            },
        },
        blockers,
    )


def review_route_blockers(
    route: str,
    external_requested: bool,
    external_approval_ref: str | None = None,
    external_approved_next_step: str | None = None,
    external_recorded_by: str | None = None,
) -> list[str]:
    blockers: list[str] = []
    if route not in REVIEW_ROUTES:
        blockers.append("review_route is not supported")
    if route == "external_gemini_claude" and not external_requested:
        blockers.append("external Gemini/Claude review requires explicit user request")
    if route == "external_gemini_claude" and is_placeholder_approval_value(external_approval_ref):
        blockers.append("external Gemini/Claude review requires concrete approval_ref")
    if route == "external_gemini_claude" and is_placeholder_approval_value(external_approved_next_step):
        blockers.append("external Gemini/Claude review requires approved_next_step")
    if route == "external_gemini_claude":
        if not external_recorded_by or not external_recorded_by.strip():
            blockers.append("external Gemini/Claude review requires main-thread recorded_by")
        elif is_tool_identity(external_recorded_by):
            blockers.append("external Gemini/Claude approval must be recorded by the main-thread supervising lead architect")
    return blockers


def completed_review_artifacts(entries: list[str], project_root: Path) -> tuple[dict[str, list[dict[str, Any]]], list[str]]:
    artifacts: dict[str, list[dict[str, Any]]] = {}
    blockers: list[str] = []
    for entry in entries:
        if "=" not in entry:
            blockers.append("--completed-review-artifact must use route=path")
            continue

        route, raw_path = entry.split("=", 1)
        route = route.strip()
        raw_path = raw_path.strip()
        summary: dict[str, Any] = {"route": route, "path": raw_path, "status": "blocked", "blockers": []}
        artifacts.setdefault(route, []).append(summary)

        if route not in REVIEW_ROUTES:
            message = f"completed review artifact route is not supported: {route}"
            summary["blockers"].append(message)
            blockers.append(message)
            continue
        if not raw_path:
            message = f"completed review artifact path is required for route: {route}"
            summary["blockers"].append(message)
            blockers.append(message)
            continue

        path = Path(raw_path).expanduser()
        if not path.is_absolute():
            path = project_root / path
        summary["path"] = str(path)
        if not path.is_file():
            message = f"completed review artifact must exist for route {route}: {path}"
            summary["blockers"].append(message)
            blockers.append(message)
            continue

        content = path.read_text(encoding="utf-8", errors="replace")
        summary["bytes"] = len(path.read_bytes())
        summary["sha256"] = sha256_file(path)
        if not content.strip():
            message = f"completed review artifact must be non-empty for route {route}: {path}"
            summary["blockers"].append(message)
            blockers.append(message)
            continue

        if route == EXTERNAL_REVIEW_ROUTE:
            for message in validate_external_response_artifact(summary, path, content, project_root):
                summary["blockers"].append(message)
                blockers.append(message)
        else:
            evaluator = review_field(content, "evaluator")
            verdict = review_field(content, "verdict")
            if evaluator:
                summary["evaluator"] = evaluator
            if verdict:
                summary["verdict"] = verdict

        if not summary["blockers"]:
            summary["status"] = "ok"
            del summary["blockers"]

    return artifacts, blockers


def close_review_blockers(
    required: list[str],
    completed: list[str],
    blocked: list[str],
    artifacts: dict[str, list[dict[str, Any]]] | None = None,
    external_requested: bool = False,
    external_approval_ref: str | None = None,
    external_approved_next_step: str | None = None,
    external_recorded_by: str | None = None,
) -> list[str]:
    blockers: list[str] = []
    artifacts = artifacts or {}
    required_set = set(required)
    completed_set = set(completed)
    blocked_set = set(blocked)
    unknown_routes = (required_set | completed_set | blocked_set) - REVIEW_ROUTES
    for route in sorted(unknown_routes):
        blockers.append(f"close review route is not supported: {route}")
    for route in sorted(required_set & blocked_set):
        blockers.append(
            f"required review route is blocked: {route}; stop without substituting another reviewer route"
        )
    for route in sorted(required_set - completed_set - blocked_set):
        blockers.append(f"required review route is missing: {route}")
    if EXTERNAL_REVIEW_ROUTE in completed_set:
        if not external_requested:
            blockers.append("completed external Gemini/Claude review requires explicit user request")
        if is_placeholder_approval_value(external_approval_ref):
            blockers.append("completed external Gemini/Claude review requires concrete approval_ref")
        if is_placeholder_approval_value(external_approved_next_step):
            blockers.append("completed external Gemini/Claude review requires approved_next_step")
        if not external_recorded_by or not external_recorded_by.strip():
            blockers.append("completed external Gemini/Claude review requires main-thread recorded_by")
        elif is_tool_identity(external_recorded_by):
            blockers.append(
                "completed external Gemini/Claude review approval must be recorded by the main-thread supervising lead architect"
            )
        if not artifacts.get(EXTERNAL_REVIEW_ROUTE):
            blockers.append("completed external Gemini/Claude review requires a durable response artifact")
    if (
        EXTERNAL_REVIEW_ROUTE in required_set
        and EXTERNAL_REVIEW_ROUTE in blocked_set
        and "codex_subagent_md_handoff" in completed_set
    ):
        blockers.append("sub-agent acceptance cannot substitute for blocked external Gemini/Claude review")
    return blockers


def batch_blockers(record_count: int) -> list[str]:
    if record_count > 1:
        return ["batch apply is disabled in Phase 0"]
    return []


def evidence_blockers(target_status: str, evidence_types: list[str], decision_types: list[str]) -> list[str]:
    blockers: list[str] = []
    if target_status != "confirmed":
        return blockers
    for evidence_type in evidence_types:
        if evidence_type == "user_decision":
            blockers.append(
                "generic user_decision cannot confirm facts; use user_decision_fact_evidence with --decision-type"
            )
        elif evidence_type == "user_decision_fact_evidence":
            if not decision_types:
                blockers.append("user_decision_fact_evidence requires --decision-type")
            for decision_type in decision_types:
                if decision_type == "final_shadow_apply":
                    blockers.append("final_shadow_apply cannot confirm facts")
                elif decision_type not in USER_FACT_DECISION_TYPES:
                    blockers.append(f"user_decision_fact_evidence decision_type is not allowed: {decision_type}")
        elif evidence_type not in CONFIRMABLE_EVIDENCE_TYPES:
            blockers.append(f"evidence_type cannot confirm facts in v2 gates: {evidence_type}")
    return blockers


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check Shadow v2 Phase 0 gate skeleton contracts.")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--project-id")
    parser.add_argument("--print-contract", action="store_true")
    parser.add_argument("--check-scope", action="store_true")
    parser.add_argument("--review-route", default="codex_subagent_md_handoff")
    parser.add_argument("--external-review-requested", action="store_true")
    parser.add_argument("--external-review-approval-ref")
    parser.add_argument("--external-review-approved-next-step")
    parser.add_argument("--external-review-recorded-by")
    parser.add_argument("--close-required-review", action="append", default=[])
    parser.add_argument("--completed-review", action="append", default=[])
    parser.add_argument("--completed-review-artifact", action="append", default=[])
    parser.add_argument("--blocked-review", action="append", default=[])
    parser.add_argument("--record-count", type=int, default=1)
    parser.add_argument("--target-status", default="unknown", choices=["confirmed", "unknown", "blocked", "stale"])
    parser.add_argument("--evidence-type", action="append", default=[])
    parser.add_argument("--decision-type", action="append", default=[])
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.record_count < 1:
        emit({"status": "error", "error": "--record-count must be positive", "writes_shadow_docs": False})
        return USAGE_ERROR

    project_root = resolve_project_root(Path(args.project_root))
    scope, scope_blockers = scope_status(project_root, args.project_id)
    review_artifacts, artifact_blockers = completed_review_artifacts(args.completed_review_artifact, project_root)
    blockers: list[str] = []
    if args.check_scope:
        blockers.extend(scope_blockers)
    blockers.extend(
        review_route_blockers(
            args.review_route,
            args.external_review_requested,
            args.external_review_approval_ref,
            args.external_review_approved_next_step,
            args.external_review_recorded_by,
        )
    )
    blockers.extend(artifact_blockers)
    blockers.extend(
        close_review_blockers(
            args.close_required_review,
            args.completed_review,
            args.blocked_review,
            review_artifacts,
            args.external_review_requested,
            args.external_review_approval_ref,
            args.external_review_approved_next_step,
            args.external_review_recorded_by,
        )
    )
    blockers.extend(batch_blockers(args.record_count))
    blockers.extend(evidence_blockers(args.target_status, args.evidence_type, args.decision_type))

    payload = {
        "status": "blocked" if blockers else "ok",
        "blockers": blockers,
        "contract": contract_payload(),
        "scope": scope,
        "review_route": args.review_route,
        "external_review_approval": {
            "requested": args.external_review_requested,
            "approval_ref": args.external_review_approval_ref or "",
            "approved_next_step": args.external_review_approved_next_step or "",
            "recorded_by": args.external_review_recorded_by or "",
        },
        "close_required_reviews": args.close_required_review,
        "completed_reviews": args.completed_review,
        "completed_review_artifacts": review_artifacts,
        "blocked_reviews": args.blocked_review,
        "review_provenance_required": True,
        "decision_types": args.decision_type,
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
        "batch_apply_enabled": False,
    }
    if args.print_contract or args.check_scope or blockers:
        emit(payload)
    else:
        emit({"status": "ok", "writes_shadow_docs": False, "auto_promotes_facts": False})
    return BLOCKED if blockers else PASS


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
