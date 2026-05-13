#!/usr/bin/env python3
"""Wrap an LLM draft as a non-promotable shadow candidate.

The wrapper creates a durable JSON artifact that records provenance for an LLM
draft without turning that draft into evidence or writing shadow docs.
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


USAGE_ERROR = 64

KEY_VALUE = r"(?:['\"]?{key}['\"]?)\s*:\s*['\"]?(?:{value})['\"]?"

FORBIDDEN_MARKERS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("shadow_write_true", re.compile(KEY_VALUE.format(key="writes_shadow_docs", value="true"), re.IGNORECASE)),
    ("auto_promote_true", re.compile(KEY_VALUE.format(key="auto_promotes_facts", value="true"), re.IGNORECASE)),
    ("direct_apply", re.compile(KEY_VALUE.format(key="shadow_action", value="apply|promote|validated|confirmed"), re.IGNORECASE)),
    ("validated_lifecycle", re.compile(KEY_VALUE.format(key="lifecycle", value="validated|confirmed"), re.IGNORECASE)),
    ("validated_status", re.compile(KEY_VALUE.format(key="status", value="validated|confirmed"), re.IGNORECASE)),
    ("user_decision_spoof", re.compile(r"['\"]?\buser_decision\b['\"]?\s*:", re.IGNORECASE)),
    ("waiver_spoof", re.compile(r"['\"]?\bwaiver\b['\"]?\s*:", re.IGNORECASE)),
)


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def emit_error(message: str, details: list[str] | None = None) -> int:
    payload: dict[str, Any] = {
        "status": "error",
        "error": message,
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
    }
    if details:
        payload["details"] = details
    emit(payload)
    return USAGE_ERROR


def read_draft(input_path: str | None) -> str:
    if input_path:
        return Path(input_path).read_text(encoding="utf-8")
    return sys.stdin.read()


def sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def normalize_timestamp(value: str | None) -> str:
    if not value:
        return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    normalized = value
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError("--timestamp must be ISO-8601") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def forbidden_markers(text: str) -> list[str]:
    return [name for name, pattern in FORBIDDEN_MARKERS if pattern.search(text)]


def candidate_id(task_id: str, draft_hash: str, source_refs: list[str], model_id: str, tool_id: str, timestamp: str) -> str:
    identity = json.dumps(
        {
            "task_id": task_id,
            "raw_draft_hash": draft_hash,
            "source_refs": source_refs,
            "model_id": model_id,
            "tool_id": tool_id,
            "created_at": timestamp,
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    return "LC-" + hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]


def is_shadow_path(path: Path) -> bool:
    parts = path.resolve(strict=False).parts
    return any(parts[index] == "docs" and index + 1 < len(parts) and parts[index + 1] == "shadow" for index in range(len(parts)))


def write_output(output_path: str | None, payload: dict[str, Any]) -> None:
    if not output_path:
        emit(payload)
        return

    target = Path(output_path)
    if is_shadow_path(target):
        raise ValueError("--output must not be under docs/shadow")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Wrap an LLM draft as a non-promotable shadow candidate.")
    parser.add_argument("--input", help="LLM draft file. Defaults to stdin.")
    parser.add_argument("--output", help="Optional JSON output path. Must not be under docs/shadow.")
    parser.add_argument("--task-id", required=True, help="Task id for candidate provenance.")
    parser.add_argument("--model-id", required=True, help="Model identity reported by the caller.")
    parser.add_argument("--tool-id", required=True, help="Tool/CLI identity reported by the caller.")
    parser.add_argument("--source-ref", action="append", default=[], help="Source reference used by the draft. Repeatable.")
    parser.add_argument("--timestamp", help="ISO-8601 timestamp. Defaults to current UTC time.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not args.source_ref:
        return emit_error("at least one --source-ref is required")

    try:
        draft = read_draft(args.input)
        timestamp = normalize_timestamp(args.timestamp)
    except (OSError, ValueError) as exc:
        return emit_error(str(exc))

    if not draft.strip():
        return emit_error("LLM draft must not be empty")

    markers = forbidden_markers(draft)
    if markers:
        return emit_error("LLM draft contains forbidden production-action markers", markers)

    draft_hash = sha256_text(draft)
    source_refs = sorted(dict.fromkeys(args.source_ref))
    payload: dict[str, Any] = {
        "status": "llm_candidate",
        "artifact_kind": "llm_candidate",
        "candidate_id": candidate_id(args.task_id, draft_hash, source_refs, args.model_id, args.tool_id, timestamp),
        "task_id": args.task_id,
        "created_at": timestamp,
        "model_id": args.model_id,
        "tool_id": args.tool_id,
        "source_refs": source_refs,
        "raw_draft_hash": draft_hash,
        "raw_draft_bytes": len(draft.encode("utf-8")),
        "evidence_type": "llm_hint",
        "can_validate": False,
        "non_promotion_status": True,
        "shadow_action": "candidate_only",
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
    }

    try:
        write_output(args.output, payload)
    except (OSError, ValueError) as exc:
        return emit_error(str(exc))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
