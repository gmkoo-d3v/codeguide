#!/usr/bin/env python3
"""Create guarded user_decision artifacts for shadow effect-map gates.

The wrapper writes only user-decision JSON artifacts. It never writes shadow
docs and never promotes facts by itself.
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

AFFIRMATIVE_ANSWERS = {"approve", "approved", "confirmed", "yes"}
FINAL_DECISION_TYPE = "final_shadow_apply"
FACT_DECISION_TYPES = {
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
HUMAN_ONLY_EFFECT_TYPES = {
    "business_intent",
    "business_risk",
    "bug_or_intended_design",
    "domain_intent",
    "effect_intent",
    "human_fact",
    "waiver_approval",
}
DECISION_TYPE_EFFECT_TYPES = {
    "business_intent": {"business_intent"},
    "business_risk": {"business_risk"},
    "bug_or_intended_design": {"bug_or_intended_design"},
    "domain_intent": {"domain_intent"},
    "effect_intent": {"effect_intent"},
    "human_fact_evidence": {"human_fact"},
    "waiver_approval": {"waiver_approval"},
}
ALLOWED_DECISION_TYPES = {FINAL_DECISION_TYPE, *FACT_DECISION_TYPES}
FORBIDDEN_VALUE_MARKERS = ("shadow-effect-record:", "<!--")
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def sha256_text(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_json(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return sha256_text(encoded)


def load_json(path: str, label: str) -> dict[str, Any]:
    try:
        parsed = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} must be valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError(f"{label} must be a JSON object")
    return parsed


def parse_date(value: str, field: str) -> dt.date:
    try:
        return dt.date.fromisoformat(value[:10])
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{field} must begin with YYYY-MM-DD") from exc


def today_from(value: str | None) -> dt.date:
    if not value:
        return dt.datetime.now(dt.timezone.utc).date()
    return parse_date(value, "--today")


def ensure_output_allowed(project_root: Path, output: Path) -> None:
    resolved = output.resolve(strict=False)
    docs_shadow = (docs_root_for(project_root).resolve(strict=False) / "shadow").resolve(strict=False)
    try:
        resolved.relative_to(docs_shadow)
    except ValueError:
        return
    raise ValueError("--output must not be under docs/shadow")


def contains_forbidden_marker(value: Any) -> bool:
    if isinstance(value, dict):
        return any(contains_forbidden_marker(child) for child in value.values())
    if isinstance(value, list):
        return any(contains_forbidden_marker(child) for child in value)
    if isinstance(value, str):
        return any(marker in value for marker in FORBIDDEN_VALUE_MARKERS)
    return False


def as_record_payload(raw: dict[str, Any]) -> dict[str, Any]:
    if isinstance(raw.get("record"), dict):
        return raw["record"]
    return raw


def record_binding(record: dict[str, Any], target_shadow_file: str | None) -> dict[str, Any]:
    record_id = str(record.get("record_id", ""))
    if not record_id:
        raise ValueError("record.record_id is required for decision binding")
    binding: dict[str, Any] = {
        "record_id": record_id,
        "effect_type": record.get("effect_type"),
        "statement_hash": sha256_text(str(record.get("statement", ""))),
    }
    if record.get("lifecycle") is not None:
        binding["lifecycle"] = record.get("lifecycle")
    if target_shadow_file:
        binding["target_shadow_file"] = target_shadow_file
    anchor = record.get("anchor") if isinstance(record.get("anchor"), dict) else {}
    if anchor.get("file"):
        binding["anchor_file"] = anchor.get("file")
    if anchor.get("line") is not None:
        binding["anchor_line"] = anchor.get("line")
    if anchor.get("symbol"):
        binding["anchor_symbol"] = anchor.get("symbol")
    evidence = record.get("evidence") if isinstance(record.get("evidence"), dict) else None
    if evidence is not None:
        binding["evidence_ref"] = evidence.get("ref")
        binding["evidence_hash"] = sha256_json(evidence)
    return {k: v for k, v in binding.items() if v not in (None, "")}


def source_refs_from(values: list[str] | None) -> list[str]:
    refs = []
    for value in values or []:
        stripped = value.strip()
        if stripped and stripped not in refs:
            refs.append(stripped)
    return refs


def validate_decision_artifact(payload: dict[str, Any], current_day: dt.date) -> list[str]:
    blockers: list[str] = []
    if payload.get("artifact_kind") != "user_decision":
        blockers.append("artifact_kind must be user_decision")
    if payload.get("writes_shadow_docs") is not False:
        blockers.append("writes_shadow_docs must be false")
    if payload.get("auto_promotes_facts") is not False:
        blockers.append("auto_promotes_facts must be false")
    decision = payload.get("user_decision")
    if not isinstance(decision, dict):
        return blockers + ["user_decision object is required"]

    for field in ("id", "decision_type", "answer", "decided_by", "decided_at", "expires_at", "rationale"):
        if not isinstance(decision.get(field), str) or not decision.get(field, "").strip():
            blockers.append(f"user_decision.{field} is required")
    decision_type = decision.get("decision_type")
    if decision_type not in ALLOWED_DECISION_TYPES:
        blockers.append("user_decision.decision_type is not allowed")
    applies_to = decision.get("applies_to")
    if not isinstance(applies_to, list) or not applies_to:
        blockers.append("user_decision.applies_to must be a non-empty list")
    source_refs = decision.get("source_refs")
    if (
        not isinstance(source_refs, list)
        or not source_refs
        or any(not isinstance(item, str) or not item.strip() for item in source_refs)
    ):
        blockers.append("user_decision.source_refs must be a non-empty list of strings")
    if contains_forbidden_marker(payload):
        blockers.append("user_decision artifact must not contain shadow record markers")

    try:
        decided_at = parse_date(str(decision.get("decided_at", "")), "user_decision.decided_at")
        expires_at = parse_date(str(decision.get("expires_at", "")), "user_decision.expires_at")
        if expires_at < decided_at:
            blockers.append("user_decision.expires_at must not be before decided_at")
        if expires_at < current_day:
            blockers.append("user_decision is expired")
    except ValueError as exc:
        blockers.append(str(exc))

    answer = str(decision.get("answer", "")).strip().lower()
    if decision_type in {FINAL_DECISION_TYPE, "runtime_scenario_fit"} and answer not in AFFIRMATIVE_ANSWERS:
        blockers.append(f"user_decision.answer must affirm {decision_type}")
    return blockers


def build_payload(args: argparse.Namespace) -> dict[str, Any]:
    decision_type = args.decision_type
    applies_to: list[Any] = []
    records: list[dict[str, Any]] = []
    if args.candidate_id:
        applies_to.append(args.candidate_id)
    for record_path in args.records or []:
        record = as_record_payload(load_json(record_path, "--record"))
        records.append(record)
        binding = record_binding(record, args.target_shadow_file)
        if decision_type == "runtime_scenario_fit":
            trace_ref = args.trace_ref or str((record.get("evidence") or {}).get("trace_ref", ""))
            scenario_ref = args.scenario_ref or str((record.get("evidence") or {}).get("scenario_ref", ""))
            if trace_ref:
                binding["trace_ref"] = trace_ref
            if scenario_ref:
                binding["scenario_ref"] = scenario_ref
        applies_to.append(binding)
    for record_id in args.record_ids or []:
        applies_to.append(record_id)

    if decision_type == FINAL_DECISION_TYPE and not args.candidate_id:
        raise ValueError("--candidate-id is required for final_shadow_apply")
    if decision_type != FINAL_DECISION_TYPE and not records:
        raise ValueError("--record is required for fact-evidence decisions")
    if decision_type not in {FINAL_DECISION_TYPE, "runtime_scenario_fit"}:
        for record in records:
            if record.get("effect_type") not in HUMAN_ONLY_EFFECT_TYPES:
                raise ValueError("human fact-evidence decisions require a human-only record.effect_type")
            allowed_effects = DECISION_TYPE_EFFECT_TYPES.get(decision_type)
            if allowed_effects is not None and record.get("effect_type") not in allowed_effects:
                raise ValueError("decision_type is not compatible with record.effect_type")
    if decision_type == "runtime_scenario_fit":
        if len(records) != 1:
            raise ValueError("runtime_scenario_fit requires exactly one --record")
        trace_ref = args.trace_ref or str((records[0].get("evidence") or {}).get("trace_ref", ""))
        scenario_ref = args.scenario_ref or str((records[0].get("evidence") or {}).get("scenario_ref", ""))
        if not trace_ref or not scenario_ref:
            raise ValueError("runtime_scenario_fit requires trace_ref and scenario_ref")

    source_refs = source_refs_from(args.source_refs)
    if decision_type == "runtime_scenario_fit":
        trace_ref = args.trace_ref or str((records[0].get("evidence") or {}).get("trace_ref", ""))
        scenario_ref = args.scenario_ref or str((records[0].get("evidence") or {}).get("scenario_ref", ""))
        for ref in (trace_ref, scenario_ref):
            if ref and ref not in source_refs:
                source_refs.append(ref)

    return {
        "artifact_kind": "user_decision",
        "generated_by": "shadow_user_decision_wrapper.py",
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
        "user_decision": {
            "id": args.decision_id,
            "decision_type": decision_type,
            "answer": args.answer,
            "decided_by": args.decided_by,
            "decided_at": args.decided_at,
            "expires_at": args.expires_at,
            "applies_to": applies_to,
            "rationale": args.rationale,
            "source_refs": source_refs,
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create guarded shadow user_decision JSON artifacts.")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--decision-id", required=True)
    parser.add_argument("--decision-type", required=True, choices=sorted(ALLOWED_DECISION_TYPES))
    parser.add_argument("--answer", required=True)
    parser.add_argument("--decided-by", required=True)
    parser.add_argument("--decided-at", required=True)
    parser.add_argument("--expires-at", required=True)
    parser.add_argument("--rationale", required=True)
    parser.add_argument("--source-ref", dest="source_refs", action="append", required=True)
    parser.add_argument("--candidate-id")
    parser.add_argument("--record", dest="records", action="append")
    parser.add_argument("--record-id", dest="record_ids", action="append")
    parser.add_argument("--target-shadow-file")
    parser.add_argument("--trace-ref")
    parser.add_argument("--scenario-ref")
    parser.add_argument("--today")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        project_root = Path(args.project_root).resolve(strict=True)
        output_path = Path(args.output)
        ensure_output_allowed(project_root, output_path)
        payload = build_payload(args)
        blockers = validate_decision_artifact(payload, today_from(args.today))
        if blockers:
            emit({"status": "blocked", "blockers": blockers, "writes_shadow_docs": False, "auto_promotes_facts": False})
            return BLOCKED
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(payload, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        emit(
            {
                "status": "ok",
                "output": str(output_path),
                "decision_id": payload["user_decision"]["id"],
                "decision_type": payload["user_decision"]["decision_type"],
                "writes_shadow_docs": False,
                "auto_promotes_facts": False,
            }
        )
        return 0
    except ValueError as exc:
        emit({"status": "error", "error": str(exc), "writes_shadow_docs": False, "auto_promotes_facts": False})
        return USAGE_ERROR


if __name__ == "__main__":
    sys.exit(main())
