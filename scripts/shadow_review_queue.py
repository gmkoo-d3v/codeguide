#!/usr/bin/env python3
"""Build a bounded human review queue from shadow evidence probe JSON.

The queue is a Markdown handoff artifact. It does not write shadow docs, infer
rule ids, or promote evidence to confirmed facts.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


USAGE_ERROR = 64
ALLOWED_PROMOTION_LIMITS = {"low", "medium", "high", "critical"}
ALLOWED_REVIEW_RISKS = {"low", "medium", "high", "critical"}
TRUSTED_REVIEW_RISK_SOURCES = {"policy", "rule_registry", "user_decision"}


@dataclass(frozen=True)
class QueueItem:
    item_id: str
    record: dict[str, Any]
    strength: str
    source_ref: str
    promotion_limit: str
    trusted_review_risk: str
    missing_context: tuple[str, ...]


def emit_error(message: str) -> int:
    print(json.dumps({"status": "error", "error": message}, sort_keys=True, separators=(",", ":")))
    return USAGE_ERROR


def read_records(input_path: str | None) -> list[dict[str, Any]]:
    if input_path:
        text = Path(input_path).read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()

    stripped = text.strip()
    if not stripped:
        return []

    if stripped.startswith("["):
        parsed = json.loads(stripped)
        if not isinstance(parsed, list):
            raise ValueError("JSON array input must contain objects")
        records = parsed
    else:
        records = [json.loads(line) for line in stripped.splitlines() if line.strip()]

    invalid = [index + 1 for index, record in enumerate(records) if not isinstance(record, dict)]
    if invalid:
        raise ValueError(f"record must be an object at line/index {invalid[0]}")
    return records


def classify_strength(record: dict[str, Any]) -> str:
    status = str(record.get("status", ""))
    if status in {"unsupported", "error"}:
        return status
    if record.get("fallback_pattern_id"):
        return "fallback_regex"
    if record.get("evidence_type") == "runtime_trace":
        return "runtime_trace"
    if record.get("parser_backed") is True:
        return "parser_backed"
    if record.get("validator_kind") == "source_probe":
        return "source_probe"
    return "unknown"


def get_source_ref(record: dict[str, Any]) -> str:
    return str(record.get("source_ref") or record.get("trace_ref") or "unknown")


def record_ref(record: dict[str, Any]) -> str:
    return str(record.get("validator_id") or record.get("fallback_pattern_id") or "unknown")


def normalized_promotion_limit(record: dict[str, Any]) -> str:
    raw_value = str(record.get("promotion_limit") or "unknown").lower()
    return raw_value if raw_value in ALLOWED_PROMOTION_LIMITS else "unknown"


def trusted_review_risk(record: dict[str, Any]) -> str:
    source = str(record.get("review_risk_source") or "").lower()
    risk = str(record.get("review_risk") or record.get("unresolved_risk") or "").lower()
    if source in TRUSTED_REVIEW_RISK_SOURCES and risk in ALLOWED_REVIEW_RISKS:
        return risk
    return "unknown"


def has_value(record: dict[str, Any], key: str) -> bool:
    value = record.get(key)
    return isinstance(value, str) and bool(value.strip())


def missing_question_context(record: dict[str, Any], source_ref: str) -> tuple[str, ...]:
    missing: list[str] = []
    if source_ref == "unknown":
        missing.append("source_ref_or_trace_ref")
    if not (has_value(record, "endpoint") or has_value(record, "entry_ref")):
        missing.append("endpoint_or_entry_ref")
    for key in ("call_chain_candidate", "anchor_file", "anchor_symbol", "missing_evidence"):
        if not has_value(record, key):
            missing.append(key)
    if record.get("recommended_default_status") not in {"unknown", "blocked"}:
        missing.append("recommended_default_status")
    return tuple(missing)


def queue_items(records: list[dict[str, Any]]) -> list[QueueItem]:
    items: list[QueueItem] = []
    for index, record in enumerate(records, start=1):
        source_ref = get_source_ref(record)
        items.append(
            QueueItem(
                item_id=f"QE-{index:03d}",
                record=record,
                strength=classify_strength(record),
                source_ref=source_ref,
                promotion_limit=normalized_promotion_limit(record),
                trusted_review_risk=trusted_review_risk(record),
                missing_context=missing_question_context(record, source_ref),
            )
        )
    return items


def question_priority(item: QueueItem) -> str:
    status = str(item.record.get("status", ""))
    if item.trusted_review_risk in {"critical", "high"}:
        return item.trusted_review_risk
    if status in {"error", "unsupported"}:
        return "high"
    if item.strength in {"source_probe", "fallback_regex"}:
        return "medium"
    if item.strength == "runtime_trace":
        return "medium"
    if item.strength == "unknown":
        return "medium"
    return "low"


def should_question(item: QueueItem, ask_confirmed: bool) -> bool:
    if item.trusted_review_risk in {"critical", "high"}:
        return True
    status = str(item.record.get("status", ""))
    if status in {"error", "unsupported", "fail"}:
        return True
    if item.strength in {"source_probe", "fallback_regex", "runtime_trace", "unknown"}:
        return True
    return ask_confirmed


def question_text(item: QueueItem) -> str:
    status = str(item.record.get("status", ""))
    ref = record_ref(item.record)
    source = item.source_ref

    if status == "unsupported":
        return f"Which supported validator or fallback should replace `{ref}` for `{source}`?"
    if status == "error":
        return f"Should `{ref}` at `{source}` stay unknown, or should the input/path be corrected and probed again?"
    if status == "fail":
        return f"Should missing evidence for `{ref}` at `{source}` keep this fact unknown?"
    if item.strength == "source_probe":
        return f"Does the syntactic source probe `{ref}` at `{source}` represent the intended production effect?"
    if item.strength == "fallback_regex":
        return f"Does fallback regex `{ref}` at `{source}` need stronger evidence before promotion?"
    if item.strength == "runtime_trace":
        return f"Is runtime trace `{source}` from the relevant scenario and observation window?"
    if item.strength == "parser_backed":
        return f"Is parser-backed evidence `{ref}` at `{source}` sufficient for the intended shadow fact?"
    return f"What user decision is needed for `{ref}` at `{source}`?"


def recommended_default_status(item: QueueItem) -> str:
    declared = item.record.get("recommended_default_status")
    if declared in {"unknown", "blocked"}:
        return str(declared)
    status = str(item.record.get("status", ""))
    if status in {"error", "unsupported"}:
        return "blocked"
    return "unknown"


def sorted_question_items(items: list[QueueItem], ask_confirmed: bool) -> list[QueueItem]:
    priority_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
    candidates = [item for item in items if should_question(item, ask_confirmed) and not item.missing_context]
    return sorted(candidates, key=lambda item: (priority_order[question_priority(item)], item.item_id))


def select_question_items(items: list[QueueItem], ask_confirmed: bool, max_questions: int) -> tuple[list[QueueItem], int, int, int]:
    sorted_items = sorted_question_items(items, ask_confirmed)
    required = [item for item in sorted_items if question_priority(item) in {"critical", "high"}]
    capped_candidates = [item for item in sorted_items if question_priority(item) not in {"critical", "high"}]
    capped_limit = max(0, max_questions - len(required))
    selected_capped = capped_candidates[:capped_limit]
    selected_ids = {item.item_id for item in required + selected_capped}
    selected = [item for item in sorted_items if item.item_id in selected_ids]
    deferred_missing_context = len([item for item in items if should_question(item, ask_confirmed) and item.missing_context])
    deferred_count = len(sorted_items) - len(selected) + deferred_missing_context
    return selected, len(required), deferred_count, deferred_missing_context


def markdown_escape(value: Any) -> str:
    text = str(value)
    return text.replace("\n", " ").strip()


def append_optional_record_fields(lines: list[str], record: dict[str, Any]) -> None:
    for key in (
        "rule_id",
        "validator_kind",
        "parser_backed",
        "validator_result",
        "trace_ref",
        "scenario_ref",
        "user_decision_ref",
        "entry_ref",
        "endpoint",
        "call_chain_candidate",
        "anchor_file",
        "anchor_line",
        "anchor_symbol",
        "missing_evidence",
        "recommended_default_status",
        "review_risk",
        "review_risk_source",
    ):
        if key in record:
            lines.append(f"  {key}: {markdown_escape(record[key])}")


def render_markdown(
    records: list[dict[str, Any]],
    task_id: str,
    max_questions: int,
    ask_confirmed: bool,
) -> str:
    items = queue_items(records)
    question_items, uncapped_required_count, deferred_question_count, deferred_missing_context_count = select_question_items(
        items, ask_confirmed, max_questions
    )
    lines: list[str] = []

    lines.extend(
        [
            "# Shadow Evidence Review Queue",
            "",
            "- doc_role: review_queue",
            f"- task_id: {task_id}",
            "- generated_by: shadow_review_queue.py",
            f"- generated_at: {dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
            "- ttl_days: 7",
            "- writes_shadow_docs: false",
            "- auto_promotes_facts: false",
            f"- input_records: {len(records)}",
            f"- max_questions: {max_questions}",
            f"- question_count: {len(question_items)}",
            f"- uncapped_required_questions: {uncapped_required_count}",
            f"- deferred_question_count: {deferred_question_count}",
            f"- deferred_missing_context_count: {deferred_missing_context_count}",
            "",
            "## Evidence Candidates",
            "",
        ]
    )

    if not items:
        lines.append("- no evidence records supplied")
    for item in items:
        record = item.record
        lines.extend(
            [
                f"- id: {item.item_id}",
                f"  status: {markdown_escape(record.get('status', 'unknown'))}",
                f"  evidence_ref: {markdown_escape(record_ref(record))}",
                f"  evidence_type: {markdown_escape(record.get('evidence_type', 'unknown'))}",
                f"  strength: {item.strength}",
                f"  source_ref: {markdown_escape(item.source_ref)}",
                f"  promotion_limit: {markdown_escape(item.promotion_limit)}",
                f"  trusted_review_risk: {markdown_escape(item.trusted_review_risk)}",
                f"  question_state: {'deferred_missing_context' if item.missing_context else 'ready'}",
                "  shadow_action: candidate_only",
            ]
        )
        if item.missing_context:
            lines.append(f"  missing_question_context: {', '.join(item.missing_context)}")
        if record.get("artifact_hash"):
            lines.append(f"  artifact_hash: {markdown_escape(record['artifact_hash'])}")
        append_optional_record_fields(lines, record)
        if record.get("error"):
            lines.append(f"  error: {markdown_escape(record['error'])}")

    lines.extend(["", "## Review Questions", ""])

    if not question_items:
        lines.append("- no user questions generated")
    for index, item in enumerate(question_items, start=1):
        lines.extend(
            [
                f"- id: RQ-{index:03d}",
                f"  evidence_ref: {item.item_id}",
                f"  priority: {question_priority(item)}",
                f"  decision_policy_ref: shadow-effect-map-workflow.md#stop-and-ask",
                f"  default_status: {recommended_default_status(item)}",
                f"  question: {question_text(item)}",
                "  options: confirm_intent | keep_unknown | reject_evidence | require_stronger_evidence",
            ]
        )

    lines.extend(
        [
            "",
            "## Guardrails",
            "",
            "- This queue is a human review aid only.",
            "- Do not treat queue consensus as evidence.",
            "- Do not promote source_probe or fallback_regex evidence above medium without a separate gate.",
            "- Error, unsupported, and trusted high/critical policy questions are emitted even when they exceed max_questions.",
            "- Under-specified records are deferred_missing_context and must not become user questions.",
            "- Keep unresolved answers as unknown.",
        ]
    )
    return "\n".join(lines) + "\n"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a bounded human review queue from probe JSON.")
    parser.add_argument("--input", help="Probe JSONL or JSON array file. Defaults to stdin.")
    parser.add_argument("--task-id", default="shadow-effect-map-01", help="Task id to include in Markdown.")
    parser.add_argument("--max-questions", type=int, default=5, help="Maximum review questions to emit.")
    parser.add_argument("--ask-confirmed", action="store_true", help="Also ask questions for parser-backed pass records.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.max_questions < 0:
        return emit_error("--max-questions must be non-negative")
    try:
        records = read_records(args.input)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        return emit_error(str(exc))

    sys.stdout.write(render_markdown(records, args.task_id, args.max_questions, args.ask_confirmed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
