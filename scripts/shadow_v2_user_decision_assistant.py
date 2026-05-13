#!/usr/bin/env python3
"""Build bounded user-decision packets for Shadow v2.

The assistant turns evidence candidates and writer next-action hints into
human-answerable questions. It never writes shadow docs, promotes facts, or
answers on behalf of the user.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shlex
import sys
from pathlib import Path
from typing import Any

from codeguide_paths import docs_root_for, resolve_project_root
from shadow_review_queue import (
    get_source_ref,
    question_priority,
    question_text,
    read_records,
    recommended_default_status,
    record_ref,
    select_question_items,
    queue_items,
)
from shadow_v2_gate_skeleton import scope_status


PASS = 0
BLOCKED = 1
USAGE_ERROR = 64

HUMAN_FACT_DECISION_BY_EFFECT_TYPE = {
    "business_intent": "business_intent",
    "business_risk": "business_risk",
    "bug_or_intended_design": "bug_or_intended_design",
    "domain_intent": "domain_intent",
    "effect_intent": "effect_intent",
    "human_fact": "human_fact_evidence",
    "waiver_approval": "waiver_approval",
}
SUPPORTED_COMMAND_DECISION_TYPES = {
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
FORBIDDEN_COMMAND_TOOLS = {
    "shadow_effect_writer.py",
    "run_external_plan_reviews.sh",
    "gemini",
    "claude",
    "codex",
}
SINGLE_USE_WRAPPER_FLAGS = {
    "--project-root",
    "--output",
    "--decision-id",
    "--decision-type",
    "--answer",
    "--decided-by",
    "--decided-at",
    "--expires-at",
    "--rationale",
    "--candidate-id",
    "--target-shadow-file",
    "--trace-ref",
    "--scenario-ref",
    "--today",
}
REPEATABLE_WRAPPER_FLAGS = {
    "--source-ref",
    "--record",
    "--record-id",
}
ALLOWED_WRAPPER_FLAGS = SINGLE_USE_WRAPPER_FLAGS | REPEATABLE_WRAPPER_FLAGS
REQUIRED_WRAPPER_FLAGS = {
    "--project-root",
    "--output",
    "--decision-id",
    "--decision-type",
    "--answer",
    "--decided-by",
    "--decided-at",
    "--expires-at",
    "--rationale",
    "--source-ref",
}
SHELL_CONTROL_TOKENS = {";", "&&", "||", "|", ">", ">>", "<", "$(", "`"}


def emit_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))


def has_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def single_line(value: Any) -> str:
    return str(value).replace("\n", " ").replace("\r", " ").strip()


def load_json_file(path: str, label: str) -> Any:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} must be valid JSON: {exc}") from exc


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


def command_flag(command: list[Any], flag: str) -> str | None:
    values = [str(item) for item in command]
    try:
        index = values.index(flag)
    except ValueError:
        return None
    if index + 1 >= len(values):
        return None
    value = values[index + 1].strip()
    return value or None


def command_text(command: list[Any]) -> str:
    return " ".join(shlex.quote(str(item)) for item in command)


def is_python_executable(value: Any) -> bool:
    name = Path(str(value)).name
    return bool(name == "python" or re.fullmatch(r"python\d+(\.\d+)?", name))


def is_trusted_wrapper_token(value: Any) -> bool:
    text = str(value)
    path = Path(text).expanduser()
    if not path.is_absolute():
        return False
    trusted = Path(__file__).with_name("shadow_user_decision_wrapper.py").resolve(strict=False)
    return path.resolve(strict=False) == trusted


def command_tokens(command: list[Any]) -> set[str]:
    tokens: set[str] = set()
    for item in command:
        for part in str(item).split():
            tokens.add(Path(part).name)
    return tokens


def wrapper_script_index(command: list[Any]) -> tuple[int | None, list[str]]:
    blockers: list[str] = []
    if not command:
        return None, ["command hint is empty"]
    first = Path(str(command[0])).name
    if is_trusted_wrapper_token(command[0]):
        return 0, []
    if is_python_executable(command[0]):
        if len(command) < 2 or not is_trusted_wrapper_token(command[1]):
            return None, ["python command hint must execute shadow_user_decision_wrapper.py directly"]
        return 1, []
    blockers.append("command hint executable must be shadow_user_decision_wrapper.py with optional python prefix")
    return None, blockers


def wrapper_flag_blockers(command: list[Any], script_index: int) -> list[str]:
    blockers: list[str] = []
    seen_flags: set[str] = set()
    index = script_index + 1
    while index < len(command):
        flag = str(command[index])
        if flag not in ALLOWED_WRAPPER_FLAGS:
            blockers.append(f"command hint flag is not allowed: {flag}")
            index += 1
            continue
        if flag in SINGLE_USE_WRAPPER_FLAGS and flag in seen_flags:
            blockers.append(f"command hint duplicate flag is not allowed: {flag}")
        seen_flags.add(flag)
        if index + 1 >= len(command):
            blockers.append(f"command hint flag requires a value: {flag}")
            break
        value = str(command[index + 1])
        if value in ALLOWED_WRAPPER_FLAGS:
            blockers.append(f"command hint flag requires a value: {flag}")
            index += 1
            continue
        index += 2
    missing = sorted(REQUIRED_WRAPPER_FLAGS - seen_flags)
    if missing:
        blockers.append("command hint missing required wrapper flags: " + ", ".join(missing))
    return blockers


def validate_user_decision_command(command: list[Any]) -> tuple[bool, list[str]]:
    blockers: list[str] = []
    script_index, shape_blockers = wrapper_script_index(command)
    blockers.extend(shape_blockers)
    names = command_tokens(command)
    forbidden = sorted(names.intersection(FORBIDDEN_COMMAND_TOOLS))
    if forbidden:
        blockers.append("command hint must not target write, external, or reviewer tools: " + ", ".join(forbidden))
    if any(str(item) in SHELL_CONTROL_TOKENS for item in command):
        blockers.append("command hint must not contain shell control tokens")
    if "-c" in {str(item) for item in command}:
        blockers.append("command hint must not use python -c")
    if script_index is not None:
        blockers.extend(wrapper_flag_blockers(command, script_index))
    decision_type = command_flag(command, "--decision-type")
    if decision_type == "final_shadow_apply":
        blockers.append("final_shadow_apply command hints are not fact-evidence decisions")
    elif decision_type not in SUPPORTED_COMMAND_DECISION_TYPES:
        blockers.append("command hint decision_type is not supported for fact evidence")
    return not blockers, blockers


def decision_type_for_record(record: dict[str, Any], fallback: str) -> str:
    effect_type = str(record.get("effect_type") or "")
    if effect_type in HUMAN_FACT_DECISION_BY_EFFECT_TYPE:
        return HUMAN_FACT_DECISION_BY_EFFECT_TYPE[effect_type]
    if str(record.get("evidence_type")) == "runtime_trace":
        return "runtime_scenario_fit"
    return fallback


def base_options(default_status: str) -> list[dict[str, str]]:
    default_answer = "keep_unknown" if default_status == "unknown" else "keep_blocked"
    return [
        {
            "id": default_answer,
            "meaning": f"Leave the candidate as {default_status}; no fact evidence is created.",
        },
        {
            "id": "require_stronger_evidence",
            "meaning": "Ask the workflow to collect deterministic code/runtime evidence before promotion.",
        },
        {
            "id": "reject_evidence",
            "meaning": "Treat the current evidence as not suitable for the claimed fact.",
        },
        {
            "id": "confirm_user_only_fact",
            "meaning": "Only for product/domain/business intent facts that cannot be proven by code alone.",
        },
    ]


def questions_from_records(records: list[dict[str, Any]], max_questions: int, ask_confirmed: bool) -> tuple[list[dict[str, Any]], dict[str, int]]:
    items = queue_items(records)
    selected, uncapped_count, deferred_count, deferred_missing_context_count = select_question_items(
        items, ask_confirmed, max_questions
    )
    questions: list[dict[str, Any]] = []
    for index, item in enumerate(selected, start=1):
        record = item.record
        default_status = recommended_default_status(item)
        decision_type = decision_type_for_record(record, "classification_or_evidence_gap")
        source_ref = get_source_ref(record)
        question = {
            "id": f"UDQ-{index:03d}",
            "source_kind": "evidence_candidate",
            "source_ref": source_ref,
            "evidence_queue_ref": item.item_id,
            "evidence_ref": record_ref(record),
            "decision_type": decision_type,
            "priority": question_priority(item),
            "user_only": True,
            "recommended_default_status": default_status,
            "question": question_text(item),
            "options": base_options(default_status),
            "command_ready": False,
            "shadow_write_impact": "none",
        }
        for key in (
            "entry_ref",
            "endpoint",
            "call_chain_candidate",
            "anchor_file",
            "anchor_line",
            "anchor_symbol",
            "missing_evidence",
            "review_risk",
            "review_risk_source",
        ):
            if key in record:
                question[key] = record[key]
        questions.append(question)
    stats = {
        "input_records": len(records),
        "question_count_from_records": len(questions),
        "uncapped_required_questions": uncapped_count,
        "deferred_question_count": deferred_count,
        "deferred_missing_context_count": deferred_missing_context_count,
    }
    return questions, stats


def normalize_writer_results(raw_values: list[Any]) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for raw in raw_values:
        if isinstance(raw, dict):
            results.append(raw)
        elif isinstance(raw, list):
            results.extend(item for item in raw if isinstance(item, dict))
        else:
            raise ValueError("--writer-result must contain a JSON object or array of objects")
    return results


def questions_from_writer_results(writer_results: list[dict[str, Any]], start_index: int) -> list[dict[str, Any]]:
    questions: list[dict[str, Any]] = []
    next_index = start_index
    for result_index, result in enumerate(writer_results, start=1):
        actions = result.get("next_actions")
        if not isinstance(actions, list):
            continue
        for action in actions:
            if not isinstance(action, dict) or action.get("requires_user_input") is not True:
                continue
            next_index += 1
            command = action.get("command") if isinstance(action.get("command"), list) else []
            command_ready, command_blockers = validate_user_decision_command(command) if command else (False, [])
            decision_type = command_flag(command, "--decision-type") or str(action.get("action") or "user_decision")
            question = {
                "id": f"UDQ-{next_index:03d}",
                "source_kind": "writer_next_action",
                "source_ref": f"writer_result:{result_index}",
                "decision_type": decision_type,
                "priority": "high" if action.get("action") in {"create_evidence_decision", "choose_supported_fact_decision_type"} else "medium",
                "user_only": True,
                "recommended_default_status": "blocked",
                "question": writer_action_question(action, decision_type),
                "options": base_options("blocked"),
                "command_ready": command_ready,
                "shadow_write_impact": "none",
                "reason": action.get("reason", ""),
            }
            if command_ready:
                question["command_hint"] = {
                    "command": [str(item) for item in command],
                    "command_text": command_text(command),
                    "then": action.get("then", ""),
                }
            elif command_blockers:
                question["blocked_command_hint"] = command_blockers
            if isinstance(action.get("missing"), list):
                question["missing"] = action["missing"]
            if isinstance(action.get("supported_effect_types"), list):
                question["supported_effect_types"] = action["supported_effect_types"]
            questions.append(question)
    return questions


def writer_action_question(action: dict[str, Any], decision_type: str) -> str:
    action_name = str(action.get("action") or "user_decision")
    if action_name == "create_evidence_decision":
        return f"Do you explicitly confirm `{decision_type}` for this exact record binding?"
    if action_name == "choose_supported_fact_decision_type":
        return "Which supported human-only decision type should be used for this effect, if any?"
    if action_name == "complete_runtime_scenario_fit_args":
        return "Which trace and scenario references prove that this runtime observation matches the intended scenario?"
    return f"What user decision is required for writer action `{action_name}`?"


def render_markdown(payload: dict[str, Any]) -> str:
    lines = [
        "# Shadow v2 User Decision Assistant",
        "",
        "- artifact_kind: shadow_v2_user_decision_packet",
        "- generated_by: shadow_v2_user_decision_assistant.py",
        f"- generated_at: {payload['generated_at']}",
        f"- status: {payload['status']}",
        f"- task_id: {payload['task_id']}",
        "- writes_shadow_docs: false",
        "- auto_promotes_facts: false",
        f"- question_count: {payload['question_count']}",
        f"- default_review_route: {payload['default_review_route']}",
        "",
        "## Scope",
        "",
        f"- project_root: {payload['scope']['project_root']}",
        f"- docs_root: {payload['scope']['docs_root']}",
        f"- hint_activation_allowed: {str(payload['scope']['hint_activation']['allowed']).lower()}",
        f"- hint_activation_mode: {payload['scope']['hint_activation']['mode']}",
        f"- hint_trigger_ref: {payload['scope']['hint_activation']['trigger_ref']}",
        "",
        "## Questions",
        "",
    ]
    if payload["blockers"]:
        lines.extend(["## Blockers", ""])
        for blocker in payload["blockers"]:
            lines.append(f"- {single_line(blocker)}")
        lines.append("")
    if not payload["questions"]:
        lines.append("- no user decisions required")
    for question in payload["questions"]:
        lines.extend(
            [
                f"- id: {question['id']}",
                f"  source_kind: {question['source_kind']}",
                f"  source_ref: {single_line(question['source_ref'])}",
                f"  decision_type: {single_line(question['decision_type'])}",
                f"  priority: {single_line(question['priority'])}",
                f"  recommended_default_status: {single_line(question['recommended_default_status'])}",
                f"  question: {single_line(question['question'])}",
                f"  command_ready: {str(question['command_ready']).lower()}",
                "  options:",
            ]
        )
        for option in question["options"]:
            lines.append(f"    - {option['id']}: {option['meaning']}")
        for key in (
            "endpoint",
            "entry_ref",
            "call_chain_candidate",
            "anchor_file",
            "anchor_line",
            "anchor_symbol",
            "missing_evidence",
            "reason",
        ):
            if has_text(question.get(key)):
                lines.append(f"  {key}: {single_line(question[key])}")
        if question.get("command_hint"):
            command_hint = question["command_hint"]
            lines.append(f"  command_hint: {single_line(command_hint.get('command_text', ''))}")
            if has_text(command_hint.get("then")):
                lines.append(f"  then: {single_line(command_hint['then'])}")
        if isinstance(question.get("blocked_command_hint"), list) and question["blocked_command_hint"]:
            lines.append("  blocked_command_hint: " + ", ".join(single_line(item) for item in question["blocked_command_hint"]))
        if isinstance(question.get("missing"), list) and question["missing"]:
            lines.append("  missing: " + ", ".join(single_line(item) for item in question["missing"]))
        if isinstance(question.get("supported_effect_types"), list) and question["supported_effect_types"]:
            lines.append("  supported_effect_types: " + ", ".join(single_line(item) for item in question["supported_effect_types"]))
    lines.extend(
        [
            "",
            "## Guardrails",
            "",
            "- The assistant asks only; it does not decide.",
            "- Keep unresolved or ambiguous answers as unknown or blocked.",
            "- `final_shadow_apply` is write authorization only, not fact evidence.",
            "- Model agreement, memory, graph, vector, source_probe, and fallback_regex outputs are hints only.",
            "- Run shadow_user_decision_wrapper.py only after the user provides an explicit answer.",
        ]
    )
    return "\n".join(lines) + "\n"


def build_payload(args: argparse.Namespace) -> tuple[dict[str, Any], list[str]]:
    project_root = resolve_project_root(Path(args.project_root))
    scope, scope_blockers = scope_status(project_root, args.project_id)
    blockers: list[str] = []
    if args.enable_hints:
        blockers.extend(scope_blockers)

    records = read_records(args.input) if args.input or not sys.stdin.isatty() else []
    record_questions, stats = questions_from_records(records, args.max_questions, args.ask_confirmed)

    writer_raw = [load_json_file(path, "--writer-result") for path in args.writer_results or []]
    writer_results = normalize_writer_results(writer_raw)
    writer_questions = questions_from_writer_results(writer_results, len(record_questions))
    questions = record_questions + writer_questions

    payload = {
        "status": "blocked" if blockers else "ok",
        "blockers": blockers,
        "artifact_kind": "shadow_v2_user_decision_packet",
        "generated_by": "shadow_v2_user_decision_assistant.py",
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "task_id": args.task_id,
        "writes_shadow_docs": False,
        "auto_promotes_facts": False,
        "default_review_route": "codex_subagent_md_handoff",
        "scope": scope,
        "stats": {
            **stats,
            "writer_result_count": len(writer_results),
            "question_count_from_writer_results": len(writer_questions),
        },
        "question_count": len(questions),
        "questions": questions,
    }
    return payload, blockers


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a bounded Shadow v2 user-decision packet.")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--project-id")
    parser.add_argument("--input", help="Probe/review JSONL or JSON array file. Defaults to stdin when piped.")
    parser.add_argument("--writer-result", dest="writer_results", action="append")
    parser.add_argument("--task-id", default="shadow-effect-map-01")
    parser.add_argument("--max-questions", type=int, default=5)
    parser.add_argument("--ask-confirmed", action="store_true")
    parser.add_argument("--enable-hints", action="store_true", help="Require verified project scope before hint activation.")
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown")
    parser.add_argument("--output")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.max_questions < 0:
        emit_json({"status": "error", "error": "--max-questions must be non-negative", "writes_shadow_docs": False})
        return USAGE_ERROR
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
                    "question_count": payload["question_count"],
                    "writes_shadow_docs": False,
                    "auto_promotes_facts": False,
                }
            )
        else:
            sys.stdout.write(rendered)
        return BLOCKED if blockers else PASS
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        emit_json({"status": "error", "error": str(exc), "writes_shadow_docs": False, "auto_promotes_facts": False})
        return USAGE_ERROR


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
