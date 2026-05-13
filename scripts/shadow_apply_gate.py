#!/usr/bin/env python3
"""Dry-run gate for supervised shadow apply requests.

The gate verifies candidate and user-decision provenance, then reports whether
a future writer may apply a shadow change. It never writes shadow docs itself.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

from codeguide_paths import docs_root_for


BLOCKED = 1
USAGE_ERROR = 64
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
CANDIDATE_ID_RE = re.compile(r"^LC-[0-9a-f]{16}$")


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def load_json(path: str, label: str) -> dict[str, Any]:
    try:
        parsed = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} must be valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError(f"{label} must be a JSON object")
    return parsed


def today_from(value: str | None) -> dt.date:
    if not value:
        return dt.datetime.now(dt.timezone.utc).date()
    try:
        return dt.date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError("--today must be YYYY-MM-DD") from exc


def today_override_warning(raw_today: str | None, current_day: dt.date) -> str | None:
    if not raw_today:
        return None
    wall_clock_day = dt.datetime.now(dt.timezone.utc).date()
    if current_day < wall_clock_day:
        return f"--today override is before current UTC date {wall_clock_day.isoformat()}"
    return None


def parse_date(value: Any, field: str) -> dt.date:
    if not isinstance(value, str) or not value:
        raise ValueError(f"user_decision.{field} is required")
    try:
        return dt.date.fromisoformat(value[:10])
    except ValueError as exc:
        raise ValueError(f"user_decision.{field} must begin with YYYY-MM-DD") from exc


def parse_timestamp(value: Any, field: str) -> dt.datetime:
    if not isinstance(value, str) or not value:
        raise ValueError(f"candidate.{field} is required")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError(f"candidate.{field} must be ISO-8601") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"candidate.{field} must include timezone")
    return parsed


def normalize_timestamp_for_id(value: Any) -> str:
    parsed = parse_timestamp(value, "created_at")
    return parsed.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def expected_candidate_id(candidate: dict[str, Any]) -> str:
    source_refs = sorted(dict.fromkeys(candidate["source_refs"]))
    identity = json.dumps(
        {
            "task_id": candidate["task_id"],
            "raw_draft_hash": candidate["raw_draft_hash"],
            "source_refs": source_refs,
            "model_id": candidate["model_id"],
            "tool_id": candidate["tool_id"],
            "created_at": normalize_timestamp_for_id(candidate["created_at"]),
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    return "LC-" + hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]


def resolve_target(project_root: Path, raw_target: str) -> tuple[Path, str]:
    if not raw_target:
        raise ValueError("--target-shadow-file is required")
    target = Path(raw_target)
    if ".." in target.parts:
        raise ValueError("--target-shadow-file must not contain traversal segments")
    docs_shadow = docs_root_for(project_root).resolve(strict=False) / "shadow"
    resolved = target if target.is_absolute() else docs_shadow / target
    resolved = resolved.resolve(strict=False)
    try:
        rel = resolved.relative_to(docs_shadow)
    except ValueError as exc:
        raise ValueError("--target-shadow-file must stay under docs/shadow") from exc
    if resolved.suffix != ".md":
        raise ValueError("--target-shadow-file must target a Markdown file")
    return resolved, rel.as_posix()


def decision_applies_to(decision: dict[str, Any], candidate_id: str) -> bool:
    applies_to = decision.get("applies_to")
    if not isinstance(applies_to, list):
        return False
    for item in applies_to:
        if item == candidate_id:
            return True
        if isinstance(item, dict) and item.get("candidate_id") == candidate_id:
            return True
    return False


def candidate_blockers(candidate: dict[str, Any]) -> list[str]:
    blockers: list[str] = []
    if candidate.get("status") != "llm_candidate":
        blockers.append("candidate.status must be llm_candidate")
    if candidate.get("artifact_kind") != "llm_candidate":
        blockers.append("candidate.artifact_kind must be llm_candidate")
    candidate_id = candidate.get("candidate_id")
    if not isinstance(candidate_id, str) or not CANDIDATE_ID_RE.match(candidate_id):
        blockers.append("candidate.candidate_id must be LC- followed by 16 lowercase hex chars")
    if not isinstance(candidate.get("task_id"), str) or not candidate.get("task_id", "").strip():
        blockers.append("candidate.task_id is required")
    if not isinstance(candidate.get("model_id"), str) or not candidate.get("model_id", "").strip():
        blockers.append("candidate.model_id is required")
    if not isinstance(candidate.get("tool_id"), str) or not candidate.get("tool_id", "").strip():
        blockers.append("candidate.tool_id is required")
    try:
        parse_timestamp(candidate.get("created_at"), "created_at")
    except ValueError as exc:
        blockers.append(str(exc))
    source_refs = candidate.get("source_refs")
    if (
        not isinstance(source_refs, list)
        or not source_refs
        or any(not isinstance(item, str) or not item.strip() for item in source_refs)
    ):
        blockers.append("candidate.source_refs must be a non-empty list of strings")
    if candidate.get("writes_shadow_docs") is not False:
        blockers.append("candidate.writes_shadow_docs must be false")
    if candidate.get("auto_promotes_facts") is not False:
        blockers.append("candidate.auto_promotes_facts must be false")
    if candidate.get("non_promotion_status") is not True:
        blockers.append("candidate.non_promotion_status must be true")
    if candidate.get("can_validate") is not False:
        blockers.append("candidate.can_validate must be false")
    if candidate.get("shadow_action") != "candidate_only":
        blockers.append("candidate.shadow_action must be candidate_only")
    if candidate.get("evidence_type") != "llm_hint":
        blockers.append("candidate.evidence_type must be llm_hint")
    raw_draft_hash = candidate.get("raw_draft_hash")
    if not isinstance(raw_draft_hash, str) or not SHA256_RE.match(raw_draft_hash):
        blockers.append("candidate.raw_draft_hash must be a sha256 reference")
    raw_draft_bytes = candidate.get("raw_draft_bytes")
    if not isinstance(raw_draft_bytes, int) or raw_draft_bytes <= 0:
        blockers.append("candidate.raw_draft_bytes must be a positive integer")
    if not blockers and candidate_id != expected_candidate_id(candidate):
        blockers.append("candidate.candidate_id must match provenance digest")
    return blockers


def decision_blockers(decision_payload: dict[str, Any], candidate_id: str, current_day: dt.date) -> list[str]:
    decision = decision_payload.get("user_decision")
    if not isinstance(decision, dict):
        return ["user_decision object is required"]

    blockers: list[str] = []
    if decision.get("decision_type") != "final_shadow_apply":
        blockers.append("user_decision.decision_type must be final_shadow_apply")
    if decision.get("answer") not in {"yes", "approve_apply"}:
        blockers.append("user_decision.answer must be yes or approve_apply")
    if not decision.get("id"):
        blockers.append("user_decision.id is required")
    if not decision.get("decided_by"):
        blockers.append("user_decision.decided_by is required")
    if not decision_applies_to(decision, candidate_id):
        blockers.append("user_decision.applies_to must reference candidate_id")
    if not isinstance(decision.get("rationale"), str) or not decision.get("rationale", "").strip():
        blockers.append("user_decision.rationale is required")
    source_refs = decision.get("source_refs")
    if (
        not isinstance(source_refs, list)
        or not source_refs
        or any(not isinstance(item, str) or not item.strip() for item in source_refs)
    ):
        blockers.append("user_decision.source_refs must be a non-empty list of strings")

    try:
        decided_at = parse_date(decision.get("decided_at"), "decided_at")
        expires_at = parse_date(decision.get("expires_at"), "expires_at")
        if expires_at < current_day:
            blockers.append("user_decision is expired")
        if expires_at < decided_at:
            blockers.append("user_decision.expires_at must not be before decided_at")
    except ValueError as exc:
        blockers.append(str(exc))
    return blockers


def result(
    status: str,
    blockers: list[str],
    candidate: dict[str, Any],
    target_ref: str | None,
    warning: str | None = None,
) -> dict[str, Any]:
    payload = {
        "status": status,
        "shadow_apply_allowed": status == "allowed",
        "apply_mode": "supervised_dry_run",
        "candidate_id": candidate.get("candidate_id", "unknown"),
        "target_shadow_file": target_ref or "unknown",
        "blockers": blockers,
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
    }
    if warning:
        payload["today_override_warning"] = warning
    return payload


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check supervised shadow apply preconditions without writing docs.")
    parser.add_argument("--project-root", required=True, help="Project root; docs root is resolved as project/docs.")
    parser.add_argument("--candidate", required=True, help="llm_candidate JSON file.")
    parser.add_argument("--user-decision", required=True, help="user_decision JSON file.")
    parser.add_argument("--target-shadow-file", required=True, help="Target Markdown path under docs/shadow.")
    parser.add_argument("--today", help="YYYY-MM-DD override for expiry checks.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        project_root = Path(args.project_root).resolve(strict=True)
        if not project_root.is_dir():
            raise ValueError("--project-root must be a directory")
        candidate = load_json(args.candidate, "candidate")
        decision = load_json(args.user_decision, "user decision")
        _, target_ref = resolve_target(project_root, args.target_shadow_file)
        current_day = today_from(args.today)
    except (OSError, ValueError) as exc:
        emit({"status": "error", "error": str(exc), "writes_shadow_docs": False, "auto_promotes_facts": False})
        return USAGE_ERROR

    candidate_id = str(candidate.get("candidate_id", ""))
    warning = today_override_warning(args.today, current_day)
    blockers = candidate_blockers(candidate) + decision_blockers(decision, candidate_id, current_day)
    if blockers:
        emit(result("blocked", blockers, candidate, target_ref, warning))
        return BLOCKED
    emit(result("allowed", [], candidate, target_ref, warning))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
