#!/usr/bin/env python3
"""Supervised writer for structured shadow effect records.

The writer only applies structured records after re-checking candidate and user
decision provenance. It never reads raw LLM drafts and never treats an LLM
candidate as evidence.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

from shadow_apply_gate import (
    candidate_blockers,
    decision_blockers,
    load_json,
    parse_date,
    resolve_target,
    today_from,
)
from shadow_policy_loader import load_policy_registry


BLOCKED = 1
USAGE_ERROR = 64

ALLOWED_LIFECYCLES = {"confirmed", "unknown", "blocked", "stale"}
ALLOWED_EVIDENCE_TYPES = {"deterministic_code", "deterministic_runtime", "user_decision"}
AFFIRMATIVE_DECISION_ANSWERS = {"approve", "approved", "confirmed", "yes"}
USER_DECISION_EFFECT_TYPES = {
    "business_intent",
    "business_risk",
    "bug_or_intended_design",
    "domain_intent",
    "effect_intent",
    "human_fact",
    "waiver_approval",
}
FACT_DECISION_TYPE_BY_EFFECT_TYPE = {
    "business_intent": "business_intent",
    "business_risk": "business_risk",
    "bug_or_intended_design": "bug_or_intended_design",
    "domain_intent": "domain_intent",
    "effect_intent": "effect_intent",
    "human_fact": "human_fact_evidence",
    "waiver_approval": "waiver_approval",
}
ALLOWED_FACT_DECISION_TYPES = {
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
FORBIDDEN_KEYS = {"raw_draft", "raw_llm_text", "llm_output", "prompt", "completion", "probe_result"}
FORBIDDEN_VALUE_MARKERS = ("shadow-effect-record:", "<!--")
RECORD_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{3,120}$")
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
SOURCE_EVIDENCE_TYPES = {"code_call", "annotation", "code_reference", "config_binding"}
MARKER_RE = re.compile(r"<!--\s*shadow-effect-record:([^ ]+)\s+(begin|end)\s*-->")


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for chunk in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def current_hash(path: Path) -> str:
    if not path.exists():
        return "missing"
    if not path.is_file():
        raise ValueError("target shadow file must be a file")
    return sha256_file(path)


def sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_json(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return sha256_text(encoded)


def single_line(value: Any) -> str:
    return str(value).replace("\n", " ").replace("\r", " ").strip()


def has_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def add_optional_warning(payload: dict[str, Any], warning: str | None) -> dict[str, Any]:
    if warning:
        payload["today_override_warning"] = warning
    return payload


def today_override_warning(raw_today: str | None, current_day: dt.date) -> str | None:
    if not raw_today:
        return None
    wall_clock_day = dt.datetime.now(dt.timezone.utc).date()
    if current_day < wall_clock_day:
        return f"--today override is before current UTC date {wall_clock_day.isoformat()}"
    return None




def source_path_from_ref(source_ref: str) -> str:
    head, sep, tail = source_ref.rpartition(":")
    if sep and tail.isdigit() and head and ("/" in head or "\\" in head or Path(head).suffix):
        return head
    return source_ref


def is_line_qualified_ref(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    head, sep, tail = value.rpartition(":")
    return bool(sep and tail.isdigit() and head and ("/" in head or "\\" in head or Path(head).suffix))


def line_from_ref(value: Any) -> str | None:
    if not is_line_qualified_ref(value):
        return None
    return str(value).rpartition(":")[2]


def same_ref(expected: Any, actual: Any) -> bool:
    if not isinstance(expected, str) or not isinstance(actual, str):
        return False
    if is_line_qualified_ref(expected):
        return expected == actual
    return source_path_from_ref(expected) == source_path_from_ref(actual)


def source_ref_matches(expected: str, actual: str) -> bool:
    return same_ref(expected, actual)


def path_ref_matches(expected: Any, actual: Path | None, project_root: Path) -> bool:
    if actual is None or not isinstance(expected, str) or not expected.strip():
        return False
    expected_path = Path(expected)
    candidates = {expected}
    try:
        candidates.add(str(expected_path.resolve(strict=False)))
    except OSError:
        pass
    if not expected_path.is_absolute():
        candidates.add(str((project_root / expected_path).resolve(strict=False)))
    return str(actual) in candidates


def anchor_line_matches_ref(anchor_line: Any, ref: Any) -> bool:
    expected_line = line_from_ref(ref)
    if expected_line is None or not has_text(anchor_line):
        return True
    return str(anchor_line).strip() == expected_line


def file_ref_path_matches(expected: Any, actual: Any, project_root: Path) -> bool:
    if not isinstance(expected, str) or not isinstance(actual, str):
        return False
    expected_path = Path(source_path_from_ref(expected))
    actual_path = Path(source_path_from_ref(actual))
    if not expected_path.is_absolute():
        expected_path = project_root / expected_path
    if not actual_path.is_absolute():
        actual_path = project_root / actual_path
    return expected_path.resolve(strict=False) == actual_path.resolve(strict=False)


def decision_source_refs_include_all(decision_payload: dict[str, Any], candidates: list[str]) -> bool:
    decision = decision_payload.get("user_decision")
    if not isinstance(decision, dict):
        return False
    source_refs = decision.get("source_refs")
    if not isinstance(source_refs, list):
        return False
    required = [candidate for candidate in candidates if candidate]
    if not required:
        return True
    actual_refs = [source_ref for source_ref in source_refs if isinstance(source_ref, str)]
    for required_ref in required:
        if not any(source_ref_matches(required_ref, actual_ref) for actual_ref in actual_refs):
            return False
    return True


def decision_has_record_binding(
    decision_payload: dict[str, Any],
    record_id: str,
    expected_effect_type: str,
    expected_statement_hash: str,
    expected_anchor: dict[str, Any] | None,
    expected_trace_ref: str | None = None,
    expected_scenario_ref: str | None = None,
) -> bool:
    decision = decision_payload.get("user_decision")
    if not isinstance(decision, dict):
        return False
    applies_to = decision.get("applies_to")
    if not isinstance(applies_to, list):
        return False
    expected_anchor = expected_anchor if isinstance(expected_anchor, dict) else {}
    for item in applies_to:
        if not isinstance(item, dict) or item.get("record_id") != record_id:
            continue
        if item.get("effect_type") != expected_effect_type:
            continue
        if item.get("statement_hash") != expected_statement_hash:
            continue
        if has_text(expected_anchor.get("file")) and item.get("anchor_file") != expected_anchor.get("file"):
            continue
        if has_text(expected_anchor.get("line")) and str(item.get("anchor_line", "")).strip() != str(expected_anchor.get("line")).strip():
            continue
        if has_text(expected_anchor.get("symbol")) and item.get("anchor_symbol") != expected_anchor.get("symbol"):
            continue
        if has_text(expected_trace_ref) and item.get("trace_ref") != expected_trace_ref:
            continue
        if has_text(expected_scenario_ref) and item.get("scenario_ref") != expected_scenario_ref:
            continue
        return True
    return False


def anchor_symbol_matches_probe_args(evidence: dict[str, Any], anchor: dict[str, Any]) -> bool:
    symbol = anchor.get("symbol")
    if not isinstance(symbol, str) or not symbol.strip():
        return True
    probe_args = evidence.get("probe_args")
    if not isinstance(probe_args, dict):
        return True
    ref = evidence.get("ref")
    if ref in {"py.ast.call_match@v1", "java.ast.call_match@v1"}:
        callee = probe_args.get("callee")
        receiver = probe_args.get("receiver")
        if isinstance(receiver, str) and receiver.strip() and isinstance(callee, str) and callee.strip():
            return symbol == f"{receiver.strip()}.{callee.strip()}"
        if not isinstance(callee, str) or not callee.strip():
            return True
        callee = callee.strip()
        return symbol == callee or symbol.endswith("." + callee)
    if ref == "py.decorator.match@v1":
        decorator = probe_args.get("decorator")
        if not isinstance(decorator, str) or not decorator.strip():
            return True
        decorator = decorator.strip().lstrip("@")
        normalized_symbol = symbol.lstrip("@")
        return normalized_symbol == decorator or normalized_symbol.endswith("." + decorator)
    if ref == "any.runtime.trace@v1":
        trace_event = probe_args.get("trace_event")
        if not isinstance(trace_event, str) or not trace_event.strip():
            return True
        trace_event = trace_event.strip()
        return trace_event == symbol or trace_event.startswith(symbol + " ")
    return True


def decision_type_effect_blockers(decision_payload: dict[str, Any] | None, record_effect_type: str) -> list[str]:
    if decision_payload is None:
        return []
    decision = decision_payload.get("user_decision")
    if not isinstance(decision, dict):
        return []
    decision_type = decision.get("decision_type")
    allowed_by_decision_type = {
        "business_intent": {"business_intent"},
        "business_risk": {"business_risk"},
        "bug_or_intended_design": {"bug_or_intended_design"},
        "domain_intent": {"domain_intent"},
        "effect_intent": {"effect_intent"},
        "human_fact_evidence": {"human_fact"},
        "waiver_approval": {"waiver_approval"},
    }
    allowed = allowed_by_decision_type.get(str(decision_type))
    if allowed is not None and record_effect_type not in allowed:
        return ["user_decision evidence decision_type is not compatible with record.effect_type"]
    if decision_type in {"promotion_decision", "runtime_scenario_fit"}:
        return ["user_decision evidence decision_type is not allowed for generic human-only evidence"]
    return []


def resolve_source_ref(project_root: Path, source_ref: str) -> Path:
    raw_path = source_path_from_ref(source_ref)
    candidate = Path(raw_path)
    if ".." in candidate.parts:
        raise ValueError("deterministic_code evidence.source_ref must not contain traversal segments")
    if not candidate.is_absolute():
        candidate = project_root / candidate
    resolved = candidate.resolve(strict=True)
    try:
        resolved.relative_to(project_root)
    except ValueError as exc:
        raise ValueError("deterministic_code evidence.source_ref must stay under project root") from exc
    if not resolved.is_file():
        raise ValueError("deterministic_code evidence.source_ref must point to a file")
    return resolved


def resolve_trace_ref(project_root: Path, trace_ref: str) -> Path:
    raw_path = source_path_from_ref(trace_ref)
    candidate = Path(raw_path)
    if ".." in candidate.parts:
        raise ValueError("deterministic_runtime evidence.trace_ref must not contain traversal segments")
    if not candidate.is_absolute():
        candidate = project_root / candidate
    resolved = candidate.resolve(strict=True)
    try:
        resolved.relative_to(project_root)
    except ValueError as exc:
        raise ValueError("deterministic_runtime evidence.trace_ref must stay under project root") from exc
    if not resolved.is_file():
        raise ValueError("deterministic_runtime evidence.trace_ref must point to a file")
    return resolved


def source_hash_blockers(evidence: dict[str, Any], project_root: Path) -> list[str]:
    blockers: list[str] = []
    source_hash = evidence.get("source_hash")
    if not isinstance(source_hash, str) or not SHA256_RE.match(source_hash):
        return ["deterministic_code evidence.source_hash must be a sha256 reference"]
    try:
        source_path = resolve_source_ref(project_root, str(evidence.get("source_ref", "")))
    except (OSError, ValueError) as exc:
        return [str(exc)]
    try:
        if sha256_file(source_path) != source_hash:
            blockers.append("deterministic_code evidence.source_hash must match current source_ref file")
    except OSError as exc:
        blockers.append(f"deterministic_code evidence.source_hash could not be verified: {exc}")
    return blockers


def trace_hash_blockers(evidence: dict[str, Any], project_root: Path) -> list[str]:
    artifact_hash = evidence.get("artifact_hash")
    if not isinstance(artifact_hash, str) or not SHA256_RE.match(artifact_hash):
        return ["deterministic_runtime evidence.artifact_hash must be a sha256 reference"]
    try:
        trace_path = resolve_trace_ref(project_root, str(evidence.get("trace_ref", "")))
    except (OSError, ValueError) as exc:
        return [str(exc)]
    try:
        if sha256_file(trace_path) != artifact_hash:
            return ["deterministic_runtime evidence.artifact_hash must match current trace_ref file"]
    except OSError as exc:
        return [f"deterministic_runtime evidence.artifact_hash could not be verified: {exc}"]
    return []


def probe_arg_value(evidence: dict[str, Any], name: str) -> str | None:
    probe_args = evidence.get("probe_args")
    if not isinstance(probe_args, dict):
        return None
    value = probe_args.get(name)
    if not isinstance(value, str) or not value.strip():
        return None
    return value.strip()


def build_probe_command(evidence: dict[str, Any], project_root: Path) -> tuple[list[str], list[str]]:
    ref = evidence.get("ref")
    evidence_type = evidence.get("type")
    if not isinstance(ref, str):
        return [], ["evidence.ref is required before probe rerun"]
    probe_script = Path(__file__).with_name("shadow_evidence_probe.py")
    command = [sys.executable, str(probe_script), "--project-root", str(project_root), "--validator-id", ref]

    if evidence_type == "deterministic_code":
        source_ref = evidence.get("source_ref")
        if not has_text(source_ref):
            return [], ["deterministic_code evidence.source_ref is required before probe rerun"]
        command.extend(["--source-file", source_path_from_ref(str(source_ref))])
        if ref in {"py.ast.call_match@v1", "java.ast.call_match@v1"}:
            callee = probe_arg_value(evidence, "callee")
            if callee is None:
                return [], [f"deterministic_code evidence.probe_args.callee is required for {ref}"]
            command.extend(["--callee", callee])
            receiver = probe_arg_value(evidence, "receiver")
            if ref == "java.ast.call_match@v1" and receiver is None:
                return [], ["deterministic_code evidence.probe_args.receiver is required for confirmed java.ast.call_match@v1"]
            if evidence.get("rule_id") == "repo.write" and receiver is None:
                return [], [f"deterministic_code evidence.probe_args.receiver is required for repo.write {ref}"]
            if receiver is not None:
                command.extend(["--receiver", receiver])
        elif ref == "py.decorator.match@v1":
            decorator = probe_arg_value(evidence, "decorator")
            if decorator is None:
                return [], ["deterministic_code evidence.probe_args.decorator is required for py.decorator.match@v1"]
            command.extend(["--decorator", decorator])
        else:
            return [], [f"writer probe rerun is unsupported for confirmed deterministic_code validator {ref}"]
        return command, []

    if evidence_type == "deterministic_runtime":
        if ref != "any.runtime.trace@v1":
            return [], [f"writer probe rerun is unsupported for confirmed deterministic_runtime validator {ref}"]
        trace_ref = evidence.get("trace_ref")
        if not has_text(trace_ref):
            return [], ["deterministic_runtime evidence.trace_ref is required before probe rerun"]
        trace_event = probe_arg_value(evidence, "trace_event")
        if trace_event is None:
            return [], ["deterministic_runtime evidence.probe_args.trace_event is required for any.runtime.trace@v1"]
        command.extend(["--trace-file", source_path_from_ref(str(trace_ref)), "--trace-event", trace_event])
        return command, []

    return [], ["probe rerun is only supported for deterministic evidence"]


def command_text(command: list[str]) -> str:
    return " ".join(shlex.quote(item) for item in command)


def evidence_decision_command_hint(
    record: dict[str, Any],
    project_root: Path,
    record_path: str | None,
    decision_type: str,
    source_refs: list[str],
    target_ref: str | None = None,
) -> dict[str, Any]:
    command = [
        sys.executable,
        str(Path(__file__).with_name("shadow_user_decision_wrapper.py")),
        "--project-root",
        str(project_root),
        "--output",
        "<evidence-decision.json>",
        "--decision-id",
        "<decision-id>",
        "--decision-type",
        decision_type,
        "--answer",
        "confirmed",
        "--decided-by",
        "<reviewer>",
        "--decided-at",
        "<YYYY-MM-DD>",
        "--expires-at",
        "<YYYY-MM-DD>",
        "--rationale",
        "<why this fact is true>",
    ]
    if record_path:
        command.extend(["--record", record_path])
    else:
        command.extend(["--record", "<record.json>"])
    if target_ref:
        command.extend(["--target-shadow-file", target_ref])
    evidence = record.get("evidence") if isinstance(record.get("evidence"), dict) else {}
    if decision_type == "runtime_scenario_fit" and isinstance(evidence, dict):
        if has_text(evidence.get("trace_ref")):
            command.extend(["--trace-ref", str(evidence["trace_ref"])])
        if has_text(evidence.get("scenario_ref")):
            command.extend(["--scenario-ref", str(evidence["scenario_ref"])])
    for source_ref in source_refs:
        command.extend(["--source-ref", source_ref])
    return {
        "action": "create_evidence_decision",
        "requires_user_input": True,
        "reason": "confirmed fact requires a separate user_decision fact-evidence artifact",
        "command": command,
        "command_text": command_text(command),
        "then": "rerun shadow_effect_writer.py with --evidence-decision <evidence-decision.json>",
    }


def fact_decision_type_for_record(record: dict[str, Any]) -> str | None:
    effect_type = record.get("effect_type")
    return FACT_DECISION_TYPE_BY_EFFECT_TYPE.get(str(effect_type)) if isinstance(effect_type, str) else None


def next_action_hints(
    blockers: list[str],
    record: dict[str, Any],
    project_root: Path,
    target_ref: str,
    before_hash: str,
    record_path: str | None = None,
) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    evidence = record.get("evidence") if isinstance(record.get("evidence"), dict) else {}
    evidence_type = evidence.get("type") if isinstance(evidence, dict) else None

    if evidence_type in {"deterministic_code", "deterministic_runtime"} and any("probe" in blocker for blocker in blockers):
        command, command_blockers = build_probe_command(evidence, project_root)
        if command:
            output_hint = evidence.get("probe_result_ref")
            if not has_text(output_hint):
                output_hint = "<probe-result.json>"
            actions.append(
                {
                    "action": "run_probe",
                    "requires_user_input": False,
                    "reason": "confirmed deterministic evidence requires a matching probe result artifact",
                    "command": command,
                    "command_text": command_text(command),
                    "stdout_to": output_hint,
                    "then": "set evidence.probe_result_ref/evidence.probe_result_hash and rerun writer with --probe-result",
                }
            )
        else:
            actions.append(
                {
                    "action": "complete_probe_args",
                    "requires_user_input": False,
                    "reason": "writer cannot rerun the probe until structured probe_args are complete",
                    "missing": command_blockers,
                }
            )

    if evidence_type == "deterministic_runtime" and any(
        "runtime_scenario_fit" in blocker or "runtime scenario fit" in blocker or "scenario fit" in blocker
        for blocker in blockers
    ):
        trace_ref = evidence.get("trace_ref")
        scenario_ref = evidence.get("scenario_ref")
        missing = []
        if not has_text(trace_ref):
            missing.append("deterministic_runtime evidence.trace_ref")
        if not has_text(scenario_ref):
            missing.append("deterministic_runtime evidence.scenario_ref")
        if missing:
            actions.append(
                {
                    "action": "complete_runtime_scenario_fit_args",
                    "requires_user_input": True,
                    "reason": "runtime_scenario_fit user_decision command requires trace_ref and scenario_ref",
                    "missing": missing,
                }
            )
        else:
            actions.append(
                evidence_decision_command_hint(
                    record,
                    project_root,
                    record_path,
                    "runtime_scenario_fit",
                    [str(trace_ref), str(scenario_ref)],
                    target_ref,
                )
            )

    if evidence_type != "deterministic_runtime" and any(
        "fact evidence requires --evidence-decision" in blocker for blocker in blockers
    ):
        source_refs = [item for item in record.get("source_refs", []) if isinstance(item, str) and item.strip()]
        decision_type = fact_decision_type_for_record(record)
        if decision_type is None:
            actions.append(
                {
                    "action": "choose_supported_fact_decision_type",
                    "requires_user_input": True,
                    "reason": "record.effect_type is not compatible with a generic user_decision fact-evidence command",
                    "supported_effect_types": sorted(FACT_DECISION_TYPE_BY_EFFECT_TYPE),
                }
            )
        else:
            actions.append(
                evidence_decision_command_hint(
                    record,
                    project_root,
                    record_path,
                    decision_type,
                    source_refs or [target_ref],
                    target_ref,
                )
            )

    if "target hash mismatch" in blockers:
        actions.append(
            {
                "action": "refresh_target_hash",
                "requires_user_input": False,
                "reason": "writer write mode requires the current target hash",
                "target_shadow_file": target_ref,
                "current_target_hash": before_hash,
                "then": "rerun writer with --expected-target-hash set to current_target_hash",
            }
        )
    return actions


def rerun_probe_result(evidence: dict[str, Any], project_root: Path) -> tuple[dict[str, Any] | None, list[str]]:
    command, blockers = build_probe_command(evidence, project_root)
    if blockers:
        return None, blockers
    try:
        completed = subprocess.run(
            command,
            cwd=str(project_root),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, [f"probe rerun failed: {exc}"]
    stdout = completed.stdout.strip()
    if completed.returncode != 0:
        detail = stdout or completed.stderr.strip()
        return None, [f"probe rerun must pass for confirmed deterministic evidence: {single_line(detail)}"]
    try:
        parsed = json.loads(stdout.splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        return None, [f"probe rerun output must be valid JSON: {exc}"]
    if not isinstance(parsed, dict):
        return None, ["probe rerun output must be a JSON object"]
    return parsed, []


def probe_result_blockers(evidence: dict[str, Any], probe_result: dict[str, Any] | None, project_root: Path) -> list[str]:
    rerun_result, rerun_blockers = rerun_probe_result(evidence, project_root)
    blockers: list[str] = list(rerun_blockers)
    if probe_result is None:
        blockers.append("confirmed deterministic evidence requires --probe-result artifact")
    if rerun_result is not None and probe_result is not None:
        compare_fields = [
            "status",
            "validator_id",
            "evidence_type",
            "validator_result",
            "writes_shadow_docs",
        ]
        if evidence.get("type") == "deterministic_code":
            compare_fields.extend(["source_hash", "validator_kind", "parser_backed"])
            if "matched_symbol" in rerun_result:
                compare_fields.append("matched_symbol")
        if evidence.get("type") == "deterministic_runtime":
            compare_fields.extend(["trace_ref", "artifact_hash"])
        for field_name in compare_fields:
            if field_name in rerun_result and probe_result.get(field_name) != rerun_result.get(field_name):
                blockers.append(f"probe_result.{field_name} must match writer probe rerun")
        if evidence.get("type") == "deterministic_code" and not same_ref(
            rerun_result.get("source_ref"), probe_result.get("source_ref")
        ):
            blockers.append("probe_result.source_ref must match writer probe rerun")
    effective_result = rerun_result if rerun_result is not None else probe_result
    if effective_result is None:
        return blockers
    evidence_type = evidence.get("type")
    ref = evidence.get("ref")
    if effective_result.get("status") != "pass":
        blockers.append("probe_result.status must be pass for confirmed deterministic evidence")
    if effective_result.get("writes_shadow_docs") is not False:
        blockers.append("probe_result.writes_shadow_docs must be false")
    if effective_result.get("validator_id") != ref:
        blockers.append("probe_result.validator_id must match evidence.ref")
    if effective_result.get("validator_result") != "matched":
        blockers.append("probe_result.validator_result must be matched")
    if effective_result.get("fallback_pattern_id"):
        blockers.append("probe_result must not be fallback regex evidence for confirmed deterministic evidence")

    if evidence_type == "deterministic_code":
        for field_name in ("validator_kind", "parser_backed", "source_hash"):
            if effective_result.get(field_name) != evidence.get(field_name):
                blockers.append(f"probe_result.{field_name} must match evidence.{field_name}")
        if not same_ref(evidence.get("source_ref"), effective_result.get("source_ref")):
            blockers.append("probe_result.source_ref must match evidence.source_ref")
        if has_text(evidence.get("source_ref")):
            blockers.extend(source_hash_blockers(evidence, project_root))

    if evidence_type == "deterministic_runtime":
        if effective_result.get("trace_ref") != evidence.get("trace_ref"):
            blockers.append("probe_result.trace_ref must match evidence.trace_ref")
        if effective_result.get("artifact_hash") != evidence.get("artifact_hash"):
            blockers.append("probe_result.artifact_hash must match evidence.artifact_hash")
        if effective_result.get("evidence_type") != "runtime_trace":
            blockers.append("probe_result.evidence_type must be runtime_trace")
        if has_text(evidence.get("trace_ref")):
            blockers.extend(trace_hash_blockers(evidence, project_root))
    return blockers


def probe_artifact_blockers(evidence: dict[str, Any], probe_result_path: Path | None, project_root: Path) -> list[str]:
    blockers: list[str] = []
    if probe_result_path is None:
        return blockers
    if not path_ref_matches(evidence.get("probe_result_ref"), probe_result_path, project_root):
        blockers.append("confirmed deterministic evidence.probe_result_ref must match --probe-result path")
    probe_result_hash = evidence.get("probe_result_hash")
    if not isinstance(probe_result_hash, str) or not SHA256_RE.match(probe_result_hash):
        blockers.append("confirmed deterministic evidence.probe_result_hash must be a sha256 reference")
    else:
        try:
            if sha256_file(probe_result_path) != probe_result_hash:
                blockers.append("confirmed deterministic evidence.probe_result_hash must match --probe-result artifact")
        except OSError as exc:
            blockers.append(f"confirmed deterministic probe_result_hash could not be verified: {exc}")
    return blockers


def policy_evidence_blockers(evidence: dict[str, Any], project_root: Path) -> list[str]:
    registry = load_policy_registry(project_root)
    blockers = list(registry.errors)
    if blockers:
        return blockers

    evidence_type = evidence.get("type")
    ref = evidence.get("ref")
    if not isinstance(ref, str):
        return blockers

    if ref in registry.regex_patterns:
        blockers.append("confirmed evidence.ref must not be a regex fallback id")

    validator_evidence_type = registry.validators.get(ref)
    if validator_evidence_type is None:
        blockers.append("confirmed evidence.ref must be a registered primary validator")
        return blockers

    if ref not in registry.implemented_primary:
        blockers.append("confirmed evidence.ref must be implemented by shadow_evidence_probe")

    if evidence_type == "deterministic_code":
        rule_id = evidence.get("rule_id")
        if isinstance(rule_id, str) and rule_id.strip():
            rule_id = rule_id.strip()
            rule = registry.rule_primaries.get(rule_id)
            if rule is None:
                blockers.append("deterministic_code evidence.rule_id is not registered")
            else:
                compatible_refs = {item for refs in rule.values() for item in refs}
                if ref not in compatible_refs:
                    blockers.append("deterministic_code evidence.ref is not compatible with evidence.rule_id")
                if validator_evidence_type not in SOURCE_EVIDENCE_TYPES:
                    blockers.append("deterministic_code evidence.ref must reference source evidence, not runtime/test evidence")
        if ref in registry.source_probe_only:
            blockers.append("deterministic_code evidence.ref must not be source_probe-only for confirmed records")
        if ref not in registry.parser_backed_now:
            blockers.append("deterministic_code evidence.ref must be parser-backed in the validator catalog")
        if evidence.get("validator_kind") == "source_probe":
            blockers.append("deterministic_code evidence.validator_kind must not be source_probe for confirmed records")

    if evidence_type == "deterministic_runtime":
        rule_id = evidence.get("rule_id")
        if isinstance(rule_id, str) and rule_id.strip():
            rule_id = rule_id.strip()
            rule = registry.rule_primaries.get(rule_id)
            if rule is None:
                blockers.append("deterministic_runtime evidence.rule_id is not registered")
            else:
                compatible_refs = {item for refs in rule.values() for item in refs}
                if ref not in compatible_refs:
                    blockers.append("deterministic_runtime evidence.ref is not compatible with evidence.rule_id")
        if validator_evidence_type != "runtime_trace":
            blockers.append("deterministic_runtime evidence.ref must reference a runtime_trace validator")
    return blockers


def user_decision_id(decision_payload: dict[str, Any]) -> str:
    decision = decision_payload.get("user_decision")
    if not isinstance(decision, dict):
        return ""
    value = decision.get("id")
    return value.strip() if isinstance(value, str) else ""


def find_forbidden_keys(value: Any, prefix: str = "") -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            path = f"{prefix}.{key_text}" if prefix else key_text
            if key_text in FORBIDDEN_KEYS:
                found.append(path)
            found.extend(find_forbidden_keys(child, path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(find_forbidden_keys(child, f"{prefix}[{index}]"))
    return found


def find_forbidden_values(value: Any, prefix: str = "") -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            found.extend(find_forbidden_values(child, path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(find_forbidden_values(child, f"{prefix}[{index}]"))
    elif isinstance(value, str):
        if any(marker in value for marker in FORBIDDEN_VALUE_MARKERS):
            found.append(prefix or "<root>")
    return found


def decision_applies_to_record(decision_payload: dict[str, Any], record_id: str) -> bool:
    decision = decision_payload.get("user_decision")
    if not isinstance(decision, dict):
        return False
    applies_to = decision.get("applies_to")
    if not isinstance(applies_to, list):
        return False
    for item in applies_to:
        if item == record_id:
            return True
        if isinstance(item, dict) and item.get("record_id") == record_id:
            return True
    return False


def writer_decision_blockers(
    decision_payload: dict[str, Any],
    record: dict[str, Any],
    target_ref: str,
    require_exact_record: bool,
) -> list[str]:
    record_id = str(record.get("record_id", ""))
    if not decision_applies_to_record(decision_payload, record_id):
        return ["user_decision.applies_to must reference record_id for writer apply"]
    if not require_exact_record:
        return []

    decision = decision_payload.get("user_decision")
    applies_to = decision.get("applies_to") if isinstance(decision, dict) else None
    if not isinstance(applies_to, list):
        return ["user_decision.applies_to must include exact record binding for write mode"]
    anchor = record.get("anchor") if isinstance(record.get("anchor"), dict) else {}
    evidence = record.get("evidence") if isinstance(record.get("evidence"), dict) else None
    for item in applies_to:
        if not isinstance(item, dict) or item.get("record_id") != record_id:
            continue
        if item.get("lifecycle") != record.get("lifecycle"):
            continue
        if item.get("effect_type") != record.get("effect_type"):
            continue
        if item.get("statement_hash") != sha256_text(str(record.get("statement", ""))):
            continue
        if item.get("target_shadow_file") != target_ref:
            continue
        if has_text(anchor.get("file")) and item.get("anchor_file") != anchor.get("file"):
            continue
        if has_text(anchor.get("line")) and str(item.get("anchor_line", "")).strip() != str(anchor.get("line")).strip():
            continue
        if has_text(anchor.get("symbol")) and item.get("anchor_symbol") != anchor.get("symbol"):
            continue
        if evidence is not None:
            if item.get("evidence_ref") != evidence.get("ref"):
                continue
            if item.get("evidence_hash") != sha256_json(evidence):
                continue
        return []
    return ["user_decision.applies_to must bind record content, target, anchor, and evidence for write mode"]


def fact_decision_blockers(
    decision_payload: dict[str, Any] | None,
    record_id: str,
    current_day: Any,
    *,
    expected_effect_type: str | None = None,
    expected_statement_hash: str | None = None,
    expected_anchor: dict[str, Any] | None = None,
    expected_trace_ref: str | None = None,
    expected_scenario_ref: str | None = None,
    required_decision_type: str | None = None,
    required_answer_values: set[str] | None = None,
    required_source_refs: list[str] | None = None,
) -> list[str]:
    if decision_payload is None:
        return ["fact evidence requires --evidence-decision separate from final_shadow_apply authorization"]
    decision = decision_payload.get("user_decision")
    if not isinstance(decision, dict):
        return ["evidence user_decision object is required"]

    blockers: list[str] = []
    decision_type = decision.get("decision_type")
    if decision_type == "final_shadow_apply":
        blockers.append("final_shadow_apply is write authorization, not fact evidence")
    elif required_decision_type is not None and decision_type != required_decision_type:
        blockers.append(f"evidence user_decision.decision_type must be {required_decision_type}")
    elif decision_type not in ALLOWED_FACT_DECISION_TYPES:
        blockers.append("evidence user_decision.decision_type must be an allowed fact-evidence decision type")
    answer = decision.get("answer")
    answer_values = required_answer_values if required_answer_values is not None else AFFIRMATIVE_DECISION_ANSWERS
    if not isinstance(answer, str) or answer.strip().lower() not in answer_values:
        blockers.append("evidence user_decision.answer must affirm the fact evidence")
    if not has_text(decision.get("id")):
        blockers.append("evidence user_decision.id is required")
    if not has_text(answer):
        blockers.append("evidence user_decision.answer is required")
    if not has_text(decision.get("decided_by")):
        blockers.append("evidence user_decision.decided_by is required")
    if not decision_applies_to_record(decision_payload, record_id):
        blockers.append("evidence user_decision.applies_to must reference record_id")
    if expected_statement_hash:
        if not has_text(expected_effect_type):
            blockers.append("evidence user_decision.applies_to binding requires record.effect_type")
        elif not decision_has_record_binding(
            decision_payload,
            record_id,
            str(expected_effect_type),
            expected_statement_hash,
            expected_anchor,
            expected_trace_ref,
            expected_scenario_ref,
        ):
            blockers.append("evidence user_decision.applies_to must bind record_id, effect_type, statement_hash, anchor, trace_ref, and scenario_ref when required")
    if not has_text(decision.get("rationale")):
        blockers.append("evidence user_decision.rationale is required")
    source_refs = decision.get("source_refs")
    if (
        not isinstance(source_refs, list)
        or not source_refs
        or any(not isinstance(item, str) or not item.strip() for item in source_refs)
    ):
        blockers.append("evidence user_decision.source_refs must be a non-empty list of strings")
    elif required_source_refs and not decision_source_refs_include_all(decision_payload, required_source_refs):
        blockers.append("evidence user_decision.source_refs must include all required evidence refs")
    try:
        decided_at = parse_date(decision.get("decided_at"), "decided_at")
        expires_at = parse_date(decision.get("expires_at"), "expires_at")
        if expires_at < current_day:
            blockers.append("evidence user_decision is expired")
        if expires_at < decided_at:
            blockers.append("evidence user_decision.expires_at must not be before decided_at")
    except ValueError as exc:
        blockers.append(str(exc).replace("user_decision.", "evidence user_decision."))
    return blockers


def evidence_blockers(
    evidence: dict[str, Any],
    decision_payload: dict[str, Any],
    project_root: Path,
    evidence_decision_payload: dict[str, Any] | None,
    probe_result_payload: dict[str, Any] | None,
    probe_result_path: Path | None,
    record_id: str,
    record_effect_type: str,
    record_statement_hash: str,
    record_anchor: dict[str, Any] | None,
    current_day: Any,
) -> list[str]:
    blockers: list[str] = []
    evidence_type = evidence.get("type")
    if evidence_type not in ALLOWED_EVIDENCE_TYPES:
        blockers.append("confirmed record.evidence.type must be deterministic_code, deterministic_runtime, or user_decision")
    if not has_text(evidence.get("ref")):
        blockers.append("confirmed record.evidence.ref is required")

    if evidence_type == "deterministic_code":
        if not has_text(evidence.get("rule_id")):
            blockers.append("deterministic_code evidence.rule_id is required")
        if not has_text(evidence.get("validator_kind")):
            blockers.append("deterministic_code evidence.validator_kind is required")
        if evidence.get("parser_backed") is not True:
            blockers.append("deterministic_code evidence.parser_backed must be true")
        if evidence.get("validator_result") != "matched":
            blockers.append("deterministic_code evidence.validator_result must be matched")
        if not has_text(evidence.get("source_ref")):
            blockers.append("deterministic_code evidence.source_ref is required")
        if has_text(evidence.get("source_ref")):
            blockers.extend(source_hash_blockers(evidence, project_root))
        blockers.extend(probe_result_blockers(evidence, probe_result_payload, project_root))
        blockers.extend(probe_artifact_blockers(evidence, probe_result_path, project_root))

    if evidence_type == "deterministic_runtime":
        if not has_text(evidence.get("rule_id")):
            blockers.append("deterministic_runtime evidence.rule_id is required")
        if not has_text(evidence.get("trace_ref")):
            blockers.append("deterministic_runtime evidence.trace_ref is required")
        artifact_hash = evidence.get("artifact_hash")
        if not isinstance(artifact_hash, str) or not SHA256_RE.match(artifact_hash):
            blockers.append("deterministic_runtime evidence.artifact_hash must be a sha256 reference")
        if has_text(evidence.get("trace_ref")):
            blockers.extend(trace_hash_blockers(evidence, project_root))
        if not has_text(evidence.get("scenario_ref")):
            blockers.append("deterministic_runtime evidence.scenario_ref is required")
        if not has_text(evidence.get("user_decision_ref")):
            blockers.append("deterministic_runtime evidence.user_decision_ref is required for scenario fit")
        if has_text(evidence.get("user_decision_ref")):
            blockers.extend(
                fact_decision_blockers(
                    evidence_decision_payload,
                    record_id,
                    current_day,
                    expected_effect_type=record_effect_type,
                    expected_statement_hash=record_statement_hash,
                    expected_anchor=record_anchor,
                    expected_trace_ref=str(evidence.get("trace_ref", "")),
                    expected_scenario_ref=str(evidence.get("scenario_ref", "")),
                    required_decision_type="runtime_scenario_fit",
                    required_answer_values=AFFIRMATIVE_DECISION_ANSWERS,
                    required_source_refs=[
                        str(evidence.get("trace_ref", "")),
                        str(evidence.get("scenario_ref", "")),
                    ],
                )
            )
            if evidence.get("user_decision_ref") != user_decision_id(evidence_decision_payload or {}):
                blockers.append("deterministic_runtime evidence.user_decision_ref must match evidence user_decision.id")
        blockers.extend(probe_result_blockers(evidence, probe_result_payload, project_root))
        blockers.extend(probe_artifact_blockers(evidence, probe_result_path, project_root))

    if evidence_type == "user_decision":
        if record_effect_type not in USER_DECISION_EFFECT_TYPES:
            blockers.append("user_decision evidence can only confirm human-only effect types")
        blockers.extend(decision_type_effect_blockers(evidence_decision_payload, record_effect_type))
        blockers.extend(
            fact_decision_blockers(
                evidence_decision_payload,
                record_id,
                current_day,
                expected_effect_type=record_effect_type,
                expected_statement_hash=record_statement_hash,
                expected_anchor=record_anchor,
                required_answer_values=AFFIRMATIVE_DECISION_ANSWERS,
            )
        )
        if evidence.get("ref") != user_decision_id(evidence_decision_payload or {}):
            blockers.append("user_decision evidence.ref must match evidence user_decision.id")
    if evidence_type in {"deterministic_code", "deterministic_runtime"}:
        blockers.extend(policy_evidence_blockers(evidence, project_root))
    return blockers


def anchor_binding_blockers(record: dict[str, Any], evidence: dict[str, Any], project_root: Path) -> list[str]:
    anchor = record.get("anchor")
    if not isinstance(anchor, dict):
        return []
    blockers: list[str] = []
    if evidence.get("type") == "deterministic_code" and has_text(anchor.get("file")) and has_text(evidence.get("source_ref")):
        if not file_ref_path_matches(anchor["file"], evidence["source_ref"], project_root):
            blockers.append("deterministic_code anchor.file must match evidence.source_ref path")
        if not anchor_line_matches_ref(anchor.get("line"), evidence.get("source_ref")):
            blockers.append("deterministic_code anchor.line must match evidence.source_ref line")
    if evidence.get("type") == "deterministic_runtime" and has_text(anchor.get("file")) and has_text(evidence.get("trace_ref")):
        if not file_ref_path_matches(anchor["file"], evidence["trace_ref"], project_root):
            blockers.append("deterministic_runtime anchor.file must match evidence.trace_ref path")
        if not anchor_line_matches_ref(anchor.get("line"), evidence.get("trace_ref")):
            blockers.append("deterministic_runtime anchor.line must match evidence.trace_ref line")
    return blockers


def rule_effect_blockers(record: dict[str, Any], evidence: dict[str, Any], project_root: Path) -> list[str]:
    if evidence.get("type") not in {"deterministic_code", "deterministic_runtime"}:
        return []
    rule_id = evidence.get("rule_id")
    if not isinstance(rule_id, str):
        return []
    registry = load_policy_registry(project_root)
    if registry.errors:
        return list(registry.errors)
    allowed = registry.rule_effect_types.get(rule_id.strip())
    if not allowed:
        return [f"{evidence.get('type')} evidence.rule_id has no allowed_effect_types policy mapping"]
    effect_type = record.get("effect_type")
    if effect_type not in allowed:
        return [f"{evidence.get('type')} evidence.rule_id is not compatible with record.effect_type"]
    return []


def record_blockers(
    record: dict[str, Any],
    candidate_id: str,
    decision_payload: dict[str, Any],
    project_root: Path,
    evidence_decision_payload: dict[str, Any] | None,
    probe_result_payload: dict[str, Any] | None,
    probe_result_path: Path | None,
    current_day: Any,
) -> list[str]:
    blockers: list[str] = []
    record_id = record.get("record_id")
    if not isinstance(record_id, str) or not RECORD_ID_RE.match(record_id):
        blockers.append("record.record_id must be 3-120 chars of letters, numbers, _, ., :, or -")
    elif "--" in record_id:
        blockers.append("record.record_id must not contain --")
    if record.get("record_type") != "effect_map_entry":
        blockers.append("record.record_type must be effect_map_entry")
    if not has_text(record.get("effect_type")):
        blockers.append("record.effect_type is required")
    if record.get("candidate_id") != candidate_id:
        blockers.append("record.candidate_id must match candidate.candidate_id")
    lifecycle = record.get("lifecycle")
    if lifecycle not in ALLOWED_LIFECYCLES:
        blockers.append("record.lifecycle must be confirmed, unknown, blocked, or stale")
    if not isinstance(record.get("statement"), str) or not record.get("statement", "").strip():
        blockers.append("record.statement is required")
    if not isinstance(record.get("anchor"), dict):
        blockers.append("record.anchor object is required")
    else:
        anchor = record["anchor"]
        if lifecycle == "confirmed":
            if not anchor.get("file") or not anchor.get("symbol"):
                blockers.append("confirmed record.anchor must include file and symbol")
        elif not anchor.get("file") and not anchor.get("symbol"):
            blockers.append("record.anchor must include file or symbol")

    evidence = record.get("evidence")
    if lifecycle == "confirmed":
        if not isinstance(evidence, dict):
            blockers.append("record.evidence object is required for confirmed records")
        else:
            record_statement_hash = sha256_text(str(record.get("statement", "")))
            record_anchor = record.get("anchor") if isinstance(record.get("anchor"), dict) else None
            blockers.extend(
                evidence_blockers(
                    evidence,
                    decision_payload,
                    project_root,
                    evidence_decision_payload,
                    probe_result_payload,
                    probe_result_path,
                    str(record_id),
                    str(record.get("effect_type", "")),
                    record_statement_hash,
                    record_anchor,
                    current_day,
                )
            )
            blockers.extend(anchor_binding_blockers(record, evidence, project_root))
            blockers.extend(rule_effect_blockers(record, evidence, project_root))
            if isinstance(record_anchor, dict) and not anchor_symbol_matches_probe_args(evidence, record_anchor):
                blockers.append("confirmed record.anchor.symbol must match deterministic probe args")
    else:
        reason = record.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            blockers.append("record.reason is required for non-confirmed records")

    if isinstance(evidence, dict) and evidence.get("type") == "llm_hint":
        blockers.append("record.evidence.type must not be llm_hint")

    forbidden = find_forbidden_keys(record)
    if forbidden:
        blockers.append("record contains forbidden raw LLM fields: " + ", ".join(forbidden))
    forbidden_values = find_forbidden_values(record)
    if forbidden_values:
        blockers.append("record contains forbidden Markdown marker fields: " + ", ".join(forbidden_values))
    source_refs = record.get("source_refs")
    if source_refs is not None and (
        not isinstance(source_refs, list)
        or any(not isinstance(item, str) or not item.strip() for item in source_refs)
    ):
        blockers.append("record.source_refs must be a list of non-empty strings when present")
    return blockers


def reserved_target_blockers(target_ref: str, existing: str) -> list[str]:
    path = Path(target_ref)
    name = path.name
    if existing.strip():
        return []
    if target_ref == "project-shadow.md" or name in {"_index.md", "overview.md", "_global.md"}:
        return ["effect writer must not create reserved shadow navigation paths"]
    return []


def marker(record_id: str, edge: str) -> str:
    return f"<!-- shadow-effect-record:{record_id} {edge} -->"


def render_record(record: dict[str, Any], user_decision_id: str) -> str:
    anchor = record.get("anchor") if isinstance(record.get("anchor"), dict) else {}
    evidence = record.get("evidence") if isinstance(record.get("evidence"), dict) else {}
    lines = [
        marker(str(record["record_id"]), "begin"),
        f"## {single_line(record['record_id'])}",
        "",
        f"- record_id: {single_line(record['record_id'])}",
        f"- record_type: {single_line(record['record_type'])}",
        f"- lifecycle: {single_line(record['lifecycle'])}",
        f"- effect_type: {single_line(record.get('effect_type', 'unknown'))}",
        f"- statement: {single_line(record['statement'])}",
        f"- candidate_id: {single_line(record['candidate_id'])}",
        f"- user_decision_ref: {single_line(user_decision_id)}",
    ]
    if anchor.get("file"):
        lines.append(f"- anchor_file: {single_line(anchor['file'])}")
    if anchor.get("line"):
        lines.append(f"- anchor_line: {single_line(anchor['line'])}")
    if anchor.get("symbol"):
        lines.append(f"- anchor_symbol: {single_line(anchor['symbol'])}")
    if evidence:
        lines.append(f"- evidence_type: {single_line(evidence.get('type', 'unknown'))}")
        lines.append(f"- evidence_ref: {single_line(evidence.get('ref', 'unknown'))}")
        for evidence_key in (
            "rule_id",
            "validator_kind",
            "parser_backed",
            "validator_result",
            "source_ref",
            "source_hash",
            "trace_ref",
            "artifact_hash",
            "scenario_ref",
            "user_decision_ref",
            "probe_result_ref",
            "probe_result_hash",
        ):
            if evidence_key in evidence:
                lines.append(f"- evidence_{evidence_key}: {single_line(evidence[evidence_key])}")
    if record.get("reason"):
        lines.append(f"- reason: {single_line(record['reason'])}")
    for source_ref in record.get("source_refs", []):
        lines.append(f"- source_ref: {single_line(source_ref)}")
    lines.extend(["", marker(str(record["record_id"]), "end")])
    return "\n".join(lines)


def default_doc_header(target_ref: str) -> str:
    title = target_ref.rsplit("/", 1)[-1].removesuffix(".md").replace("-", " ").replace("_", " ").title()
    return "\n".join(
        [
            f"# {title or 'Shadow Effects'}",
            "",
            "- doc_role: effect_map",
            "- generated_by: shadow_effect_writer.py",
            "",
        ]
    )


def upsert_record(existing: str, target_ref: str, rendered: str, record_id: str) -> tuple[str, str]:
    begin = marker(record_id, "begin")
    end = marker(record_id, "end")
    if not existing.strip():
        return default_doc_header(target_ref) + rendered + "\n", "create"

    begin_index = existing.find(begin)
    end_index = existing.find(end)
    if begin_index >= 0 and end_index >= begin_index:
        end_index += len(end)
        updated = existing[:begin_index].rstrip() + "\n\n" + rendered + "\n" + existing[end_index:].lstrip("\n")
        if not updated.endswith("\n"):
            updated += "\n"
        return updated, "update"

    return existing.rstrip() + "\n\n" + rendered + "\n", "append"


def leading_metadata_value(existing: str, field_name: str) -> str:
    for line in existing.splitlines()[:80]:
        stripped = line.strip()
        if stripped.startswith("## "):
            break
        if stripped.startswith("- " + field_name + ":"):
            return stripped.split(":", 1)[1].strip()
    return ""


def target_role_blockers(existing: str) -> list[str]:
    if not existing.strip():
        return []
    if leading_metadata_value(existing, "doc_role") != "effect_map":
        return ["target shadow file must declare doc_role: effect_map before effect writes"]
    return []


def existing_marker_blockers(existing: str, record_id: str) -> list[str]:
    blockers: list[str] = []
    marker_spans = [(match.start(), match.end()) for match in MARKER_RE.finditer(existing)]
    markerish_spans = [(match.start(), match.end()) for match in re.finditer(r"<!--\s*shadow-effect-record:.*?-->", existing)]
    if len(marker_spans) != len(markerish_spans):
        blockers.append("target contains malformed shadow-effect-record marker")

    events: dict[str, list[tuple[str, int]]] = {}
    stack: list[str] = []
    for match in MARKER_RE.finditer(existing):
        found_id, edge = match.group(1), match.group(2)
        if not RECORD_ID_RE.match(found_id) or "--" in found_id:
            blockers.append("target contains invalid shadow-effect-record marker id")
        events.setdefault(found_id, []).append((edge, match.start()))
        if edge == "begin":
            stack.append(found_id)
        elif not stack:
            blockers.append("target contains end marker without matching begin marker")
        elif stack[-1] != found_id:
            blockers.append("target contains interleaved shadow-effect-record markers")
        else:
            stack.pop()
    if stack:
        blockers.append("target contains unclosed shadow-effect-record marker")

    for found_id, found_events in events.items():
        begin_positions = [position for edge, position in found_events if edge == "begin"]
        end_positions = [position for edge, position in found_events if edge == "end"]
        if len(begin_positions) != 1 or len(end_positions) != 1:
            blockers.append("target must contain exactly one begin and end marker per record_id before update")
            continue
        if end_positions[0] < begin_positions[0]:
            blockers.append("target record_id end marker appears before begin marker")

    if record_id and record_id in events:
        begin_count = sum(1 for edge, _ in events[record_id] if edge == "begin")
        end_count = sum(1 for edge, _ in events[record_id] if edge == "end")
        if begin_count != 1 or end_count != 1:
            blockers.append("target must contain exactly one begin and end marker for record_id before update")

    return sorted(set(blockers))


def validate_line_cap(text: str, max_lines: int) -> list[str]:
    line_count = len(text.splitlines())
    if line_count > max_lines:
        return [f"target would exceed max line count ({line_count} > {max_lines})"]
    return []


def atomic_write_text(path: Path, text: str) -> None:
    temp_path = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    try:
        temp_path.write_text(text, encoding="utf-8")
        temp_path.replace(path)
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply structured shadow effect records through a supervised gate.")
    parser.add_argument("--project-root", required=True, help="Project root; docs root is resolved as project/docs.")
    parser.add_argument("--record", required=True, help="Structured effect_map_entry JSON file.")
    parser.add_argument("--candidate", required=True, help="llm_candidate JSON file.")
    parser.add_argument("--user-decision", required=True, help="user_decision JSON file.")
    parser.add_argument("--evidence-decision", help="Separate fact-evidence user_decision JSON file.")
    parser.add_argument("--probe-result", help="Read-only shadow_evidence_probe JSON result for deterministic evidence.")
    parser.add_argument("--target-shadow-file", required=True, help="Target Markdown path under docs/shadow.")
    parser.add_argument("--expected-target-hash", help="Expected current target hash, or 'missing'. Required in write mode.")
    parser.add_argument("--mode", choices=("dry-run", "write"), default="dry-run")
    parser.add_argument("--max-lines", type=int, default=300)
    parser.add_argument("--today", help="YYYY-MM-DD override for expiry checks.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.max_lines <= 0:
        emit({"status": "error", "error": "--max-lines must be positive", "writes_shadow_docs": False})
        return USAGE_ERROR
    if args.mode == "write" and not args.expected_target_hash:
        emit({"status": "error", "error": "--expected-target-hash is required in write mode", "writes_shadow_docs": False})
        return USAGE_ERROR

    try:
        project_root = Path(args.project_root).resolve(strict=True)
        if not project_root.is_dir():
            raise ValueError("--project-root must be a directory")
        target_path, target_ref = resolve_target(project_root, args.target_shadow_file)
        candidate = load_json(args.candidate, "candidate")
        decision_payload = load_json(args.user_decision, "user decision")
        evidence_decision_payload = load_json(args.evidence_decision, "evidence decision") if args.evidence_decision else None
        probe_result_path = Path(args.probe_result).resolve(strict=True) if args.probe_result else None
        probe_result_payload = load_json(str(probe_result_path), "probe result") if probe_result_path else None
        record = load_json(args.record, "record")
        current_day = today_from(args.today)
    except (OSError, ValueError) as exc:
        emit({"status": "error", "error": str(exc), "writes_shadow_docs": False, "auto_promotes_facts": False})
        return USAGE_ERROR

    override_warning = today_override_warning(args.today, current_day)
    candidate_id = str(candidate.get("candidate_id", ""))
    blockers = (
        candidate_blockers(candidate)
        + decision_blockers(decision_payload, candidate_id, current_day)
        + writer_decision_blockers(decision_payload, record, target_ref, args.mode == "write")
        + record_blockers(
            record,
            candidate_id,
            decision_payload,
            project_root,
            evidence_decision_payload,
            probe_result_payload,
            probe_result_path,
            current_day,
        )
    )

    try:
        before_hash = current_hash(target_path)
    except ValueError as exc:
        emit({"status": "error", "error": str(exc), "writes_shadow_docs": False, "auto_promotes_facts": False})
        return USAGE_ERROR
    if args.expected_target_hash and args.expected_target_hash != before_hash:
        blockers.append("target hash mismatch")

    existing = target_path.read_text(encoding="utf-8") if target_path.exists() else ""
    record_id = str(record.get("record_id", ""))
    blockers.extend(reserved_target_blockers(target_ref, existing))
    blockers.extend(target_role_blockers(existing))
    blockers.extend(existing_marker_blockers(existing, record_id))

    user_decision = decision_payload.get("user_decision", {})
    rendered = render_record(record, single_line(user_decision.get("id", "unknown"))) if not blockers else ""
    next_text, operation = upsert_record(existing, target_ref, rendered, str(record.get("record_id", "unknown"))) if not blockers else (existing, "blocked")
    blockers.extend(existing_marker_blockers(next_text, record_id) if not blockers else [])
    blockers.extend(validate_line_cap(next_text, args.max_lines) if not blockers else [])

    if blockers:
        next_actions = next_action_hints(blockers, record, project_root, target_ref, before_hash, args.record)
        emit(
            add_optional_warning(
                {
                "status": "blocked",
                "operation": operation,
                "target_shadow_file": target_ref,
                "record_id": record.get("record_id", "unknown"),
                "blockers": blockers,
                "next_actions": next_actions,
                "writes_shadow_docs": False,
                "auto_promotes_facts": False,
                },
                override_warning,
            )
        )
        return BLOCKED

    after_hash = sha256_text(next_text)
    payload: dict[str, Any] = {
        "status": "ok",
        "mode": args.mode,
        "operation": operation,
        "target_shadow_file": target_ref,
        "record_id": record["record_id"],
        "candidate_id": candidate_id,
        "before_hash": before_hash,
        "after_hash": after_hash,
        "writes_shadow_docs": args.mode == "write",
        "auto_promotes_facts": False,
    }
    if args.mode == "dry-run":
        payload["preview"] = rendered
        emit(add_optional_warning(payload, override_warning))
        return 0

    target_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        if current_hash(target_path) != before_hash:
            emit(
                add_optional_warning(
                    {
                    "status": "blocked",
                    "operation": "blocked",
                    "target_shadow_file": target_ref,
                    "record_id": record.get("record_id", "unknown"),
                    "blockers": ["target hash changed before write"],
                    "writes_shadow_docs": False,
                    "auto_promotes_facts": False,
                    },
                    override_warning,
                )
            )
            return BLOCKED
        freshness_blockers = record_blockers(
            record,
            candidate_id,
            decision_payload,
            project_root,
            evidence_decision_payload,
            probe_result_payload,
            probe_result_path,
            current_day,
        )
        if freshness_blockers:
            next_actions = next_action_hints(freshness_blockers, record, project_root, target_ref, before_hash, args.record)
            emit(
                add_optional_warning(
                    {
                    "status": "blocked",
                    "operation": "blocked",
                    "target_shadow_file": target_ref,
                    "record_id": record.get("record_id", "unknown"),
                    "blockers": freshness_blockers,
                    "next_actions": next_actions,
                    "writes_shadow_docs": False,
                    "auto_promotes_facts": False,
                    },
                    override_warning,
                )
            )
            return BLOCKED
        atomic_write_text(target_path, next_text)
    except OSError as exc:
        emit({"status": "error", "error": str(exc), "writes_shadow_docs": False, "auto_promotes_facts": False})
        return USAGE_ERROR
    emit(add_optional_warning(payload, override_warning))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
