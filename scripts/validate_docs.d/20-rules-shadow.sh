#!/usr/bin/env bash
# validate_docs.d/20-rules-shadow.sh — Shadow rules: graph/schema/digest/nav-link checks plus the effect-map, review-queue, and policy/registry families.
# Sourced by validate_docs.sh after CLI/global setup; not executable alone.
# Split from validate_docs.sh (behavior-preserving; function bodies verbatim).

check_redirect_shim_file() {
  local file_path="$1"
  local label="$2"

  check_field_value_equals "$file_path" "doc_role" "redirect_shim" "$label" || true
  check_field_exists "$file_path" "legacy_path" "$label" || true
  check_field_exists "$file_path" "canonical_path" "$label" || true
  check_field_exists "$file_path" "redirects_fact_scope" "$label" || true
  check_field_exists "$file_path" "deprecated_since" "$label" || true
  check_field_value_equals "$file_path" "status" "redirected" "$label" || true
  check_field_value_equals "$file_path" "edit_policy" "read_only" "$label" || true
  check_field_exists "$file_path" "replacement_reason" "$label" || true
  check_field_exists "$file_path" "last_updated" "$label" || true
}

check_effect_map_file() {
  local file_path="$1"
  local issue_output

  check_field_value_equals "$file_path" "doc_role" "effect_map" "shadow effect_map" || true
  issue_output="$(python3 - "$file_path" "$POLICY_DIR" "$PROJECT_ROOT_ABS" "$SCRIPT_DIR" <<'PY'
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

path = sys.argv[1]
policy_dir = Path(sys.argv[2])
project_root = Path(sys.argv[3])
script_dir = Path(sys.argv[4])
sys.path.insert(0, str(script_dir))
from shadow_policy_loader import load_policy_registry_from_dir
marker = re.compile(r"^<!--\s*shadow-effect-record:([A-Za-z0-9_.:-]+)\s+(begin|end)\s*-->$")
markerish = re.compile(r"shadow-effect-record:")
allowed_lifecycles = {"confirmed", "unknown", "blocked", "stale"}
human_effect_types = {
    "business_intent",
    "business_risk",
    "bug_or_intended_design",
    "domain_intent",
    "effect_intent",
    "human_fact",
    "waiver_approval",
}
sha_re = re.compile(r"^sha256:[0-9a-f]{64}$")
scenario_scope_re = re.compile(r"^[A-Za-z0-9_.:/-]{3,120}$")
setter_symbol_path_re = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$")
id_re = re.compile(r"^ {2,}([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+@v[0-9]+):\s*$")
runtime_envelope_encodings = {"utf-8", "binary"}
runtime_envelope_canonicalizations = {"none", "rfc8785", "custom-declared"}
runtime_envelope_hash_input_scopes = {"whole_artifact", "selected_fields", "line_range"}
runtime_envelope_canonical_output_types = {"text", "binary"}
expiry_or_invalidation_rules = {"timestamp", "binding_change", "manual_revocation"}
runtime_envelope_v1_matrix = {
    ("utf-8", "rfc8785", None, "whole_artifact"),
    ("utf-8", "rfc8785", None, "selected_fields"),
    ("utf-8", "none", None, "whole_artifact"),
    ("utf-8", "none", None, "line_range"),
    ("utf-8", "custom-declared", "text", "whole_artifact"),
    ("utf-8", "custom-declared", "text", "selected_fields"),
    ("utf-8", "custom-declared", "text", "line_range"),
    ("utf-8", "custom-declared", "binary", "whole_artifact"),
    ("binary", "none", None, "whole_artifact"),
    ("binary", "custom-declared", "binary", "whole_artifact"),
}
bt = chr(96)
issues = []
open_id = None
fields = {}
record_count = 0


def parse_inline_list(value: str) -> set[str]:
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        value = value[1:-1]
    return {item.strip().strip("\"'") for item in value.split(",") if item.strip()}


policy_registry = load_policy_registry_from_dir(policy_dir)
catalog_evidence_types = policy_registry.validators
implemented_validators = policy_registry.implemented_primary
parser_backed_validators = policy_registry.parser_backed_now
rule_allowed_effects = policy_registry.rule_effect_types
rule_compatible_refs = {
    rule_id: {item for refs in evidence_refs.values() for item in refs}
    for rule_id, evidence_refs in policy_registry.rule_primaries.items()
}


def sha256_file(value: Path) -> str:
    digest = hashlib.sha256()
    with value.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def source_path_from_ref(ref: str) -> str:
    head, sep, tail = ref.rpartition(":")
    if sep and tail.isdigit() and head and ("/" in head or "\\" in head or Path(head).suffix):
        return head
    return ref


def line_from_ref(ref: str) -> str | None:
    head, sep, tail = ref.rpartition(":")
    if sep and tail.isdigit() and head and ("/" in head or "\\" in head or Path(head).suffix):
        return tail
    return None


def is_json_media_type(value: str) -> bool:
    media_type = value.split(";", 1)[0].strip().lower()
    return media_type == "application/json" or media_type.endswith("+json")


def parse_top_level_json_object_without_duplicates(text: str) -> dict:
    def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
        result = {}
        for key, item in pairs:
            if key in result:
                raise ValueError("no duplicate top-level field names")
            result[key] = item
        return result

    parsed = json.loads(text, object_pairs_hook=reject_duplicate_keys)
    if not isinstance(parsed, dict):
        raise ValueError("a JSON object")
    return parsed


def normalized_path(ref: str) -> Path:
    raw = Path(source_path_from_ref(ref))
    if not raw.is_absolute():
        raw = project_root / raw
    return raw.resolve(strict=False)


def check_path_binding(record_id: str, prefix: str, anchor_file: str, ref: str, anchor_line: str | None = None) -> None:
    if anchor_file and ref and normalized_path(anchor_file) != normalized_path(ref):
        issues.append(f"record {record_id}: {prefix} anchor_file must match evidence ref path")
    ref_line = line_from_ref(ref or "")
    if anchor_line and ref_line and str(anchor_line).strip() != ref_line:
        issues.append(f"record {record_id}: {prefix} anchor_line must match evidence ref line")


def check_probe_artifact(record_id: str, probe_ref: str, probe_hash: str, label: str) -> None:
    if not sha_re.match(probe_hash or ""):
        return
    if not probe_ref:
        return
    probe_path = Path(source_path_from_ref(probe_ref))
    if not probe_path.is_absolute():
        probe_path = project_root / probe_path
    try:
        resolved = probe_path.resolve(strict=True)
    except OSError:
        issues.append(f"record {record_id}: {label} probe artifact must exist")
        return
    if not resolved.is_file():
        issues.append(f"record {record_id}: {label} probe artifact must be a file")
        return
    try:
        if sha256_file(resolved) != probe_hash:
            issues.append(f"record {record_id}: {label} probe artifact hash must match")
    except OSError as exc:
        issues.append(f"record {record_id}: {label} probe artifact hash could not be verified: {exc}")


def check_rule(record_id: str, evidence_type: str, rule_id: str, effect_type: str, evidence_ref: str) -> None:
    if not rule_id:
        issues.append(f"record {record_id}: {evidence_type} evidence_rule_id is required")
        return
    if rule_id not in rule_allowed_effects:
        issues.append(f"record {record_id}: {evidence_type} evidence_rule_id must be registered")
        return
    if effect_type not in rule_allowed_effects.get(rule_id, set()):
        issues.append(f"record {record_id}: {evidence_type} evidence_rule_id is not compatible with effect_type")
    if evidence_ref not in rule_compatible_refs.get(rule_id, set()):
        issues.append(f"record {record_id}: {evidence_type} evidence_ref is not compatible with evidence_rule_id")


def is_rendered_list(value: str) -> bool:
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return False
    return isinstance(parsed, list)


def parsed_json_field(record_id: str, key: str, expected_type: type):
    raw = fields.get(key, "")
    if not raw:
        issues.append(f"record {record_id}: deterministic_runtime record requires {key}")
        return None
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        issues.append(f"record {record_id}: deterministic_runtime {key} must be valid JSON")
        return None
    if not isinstance(parsed, expected_type):
        issues.append(f"record {record_id}: deterministic_runtime {key} has the wrong JSON type")
        return None
    return parsed


def runtime_trace_hash(record_id: str) -> str | None:
    trace_ref = fields.get("evidence_trace_ref", "")
    if not trace_ref:
        return None
    trace_path = Path(source_path_from_ref(trace_ref))
    if not trace_path.is_absolute():
        trace_path = project_root / trace_path
    try:
        raw_bytes = trace_path.resolve(strict=True).read_bytes()
    except OSError as exc:
        issues.append(f"record {record_id}: deterministic_runtime trace artifact could not be read: {exc}")
        return None

    hash_input_scope = fields.get("evidence_hash_input_scope", "")
    if hash_input_scope == "whole_artifact":
        return sha256_bytes(raw_bytes)

    if hash_input_scope == "line_range":
        line_range = parsed_json_field(record_id, "evidence_line_range", dict)
        if line_range is None:
            return None
        start = line_range.get("start")
        end = line_range.get("end")
        if type(start) is not int or type(end) is not int or start < 1 or end < start:
            issues.append(f"record {record_id}: deterministic_runtime evidence_line_range must satisfy integer start >= 1 and end >= start")
            return None
        matched_line = line_from_ref(trace_ref)
        if matched_line is None:
            issues.append(f"record {record_id}: deterministic_runtime evidence_trace_ref must be line-qualified for line_range scope")
            return None
        if not (start <= int(matched_line) <= end):
            issues.append(f"record {record_id}: deterministic_runtime evidence_trace_ref line must be inside evidence_line_range")
            return None
        lines = raw_bytes.splitlines(keepends=True)
        if end > len(lines):
            issues.append(f"record {record_id}: deterministic_runtime evidence_line_range must be within trace artifact line count")
            return None
        return sha256_bytes(b"".join(lines[start - 1 : end]))

    if hash_input_scope == "selected_fields":
        selected_fields = parsed_json_field(record_id, "evidence_selected_fields", list)
        if selected_fields is None:
            return None
        if not selected_fields or not all(isinstance(item, str) for item in selected_fields):
            issues.append(f"record {record_id}: deterministic_runtime evidence_selected_fields must be a non-empty JSON list of strings")
            return None
        if len(set(selected_fields)) != len(selected_fields):
            issues.append(f"record {record_id}: deterministic_runtime evidence_selected_fields must not contain duplicate field names")
            return None
        if any(not item or "." in item for item in selected_fields):
            issues.append(f"record {record_id}: deterministic_runtime evidence_selected_fields supports only top-level field names")
            return None
        if line_from_ref(trace_ref) != "1":
            issues.append(f"record {record_id}: deterministic_runtime evidence_trace_ref must point at the single JSON trace line for selected_fields scope")
            return None
        try:
            text = raw_bytes.decode("utf-8")
        except UnicodeDecodeError as exc:
            issues.append(f"record {record_id}: deterministic_runtime selected_fields trace artifact must be utf-8: {exc}")
            return None
        lines = text.splitlines()
        if len(lines) != 1:
            issues.append(f"record {record_id}: deterministic_runtime selected_fields trace artifact must be a single JSON line")
            return None
        try:
            parsed = parse_top_level_json_object_without_duplicates(text)
        except json.JSONDecodeError as exc:
            issues.append(f"record {record_id}: deterministic_runtime selected_fields trace artifact must be valid JSON: {exc}")
            return None
        except ValueError as exc:
            issues.append(f"record {record_id}: deterministic_runtime selected_fields trace artifact must be {exc}")
            return None
        if any(field not in parsed for field in selected_fields):
            issues.append(f"record {record_id}: deterministic_runtime selected_fields must exist in trace artifact")
            return None
        selected = {field: parsed[field] for field in selected_fields}
        return sha256_bytes(json.dumps(selected, sort_keys=True, separators=(",", ":")).encode("utf-8"))

    return None


def check_runtime_envelope(record_id: str) -> None:
    for key in (
        "evidence_artifact_media_type",
        "evidence_encoding",
        "evidence_canonicalization",
        "evidence_hash_input_scope",
        "evidence_ignored_nondeterministic_fields",
    ):
        if not fields.get(key):
            issues.append(f"record {record_id}: deterministic_runtime record requires {key}")

    encoding = fields.get("evidence_encoding", "")
    canonicalization = fields.get("evidence_canonicalization", "")
    hash_input_scope = fields.get("evidence_hash_input_scope", "")
    ignored_fields = fields.get("evidence_ignored_nondeterministic_fields", "")
    canonical_output_type = fields.get("evidence_canonical_output_type")

    if encoding and encoding not in runtime_envelope_encodings:
        issues.append(f"record {record_id}: deterministic_runtime evidence_encoding must be utf-8 or binary")
    if canonicalization and canonicalization not in runtime_envelope_canonicalizations:
        issues.append(
            f"record {record_id}: deterministic_runtime evidence_canonicalization must be none, rfc8785, or custom-declared"
        )
    if hash_input_scope and hash_input_scope not in runtime_envelope_hash_input_scopes:
        issues.append(
            f"record {record_id}: deterministic_runtime evidence_hash_input_scope must be whole_artifact, selected_fields, or line_range"
        )
    if ignored_fields and not is_rendered_list(ignored_fields):
        issues.append(f"record {record_id}: deterministic_runtime evidence_ignored_nondeterministic_fields must be a JSON list")

    if canonicalization == "custom-declared":
        if canonical_output_type not in runtime_envelope_canonical_output_types:
            issues.append(
                f"record {record_id}: deterministic_runtime evidence_canonical_output_type must be text or binary for custom-declared canonicalization"
            )
    elif canonical_output_type:
        issues.append(
            f"record {record_id}: deterministic_runtime evidence_canonical_output_type is only valid for custom-declared canonicalization"
        )

    if (
        hash_input_scope == "whole_artifact"
        and ignored_fields
        and ignored_fields != "[]"
        and canonicalization != "custom-declared"
    ):
        issues.append(
            f"record {record_id}: deterministic_runtime evidence_ignored_nondeterministic_fields must be [] for whole_artifact unless canonicalization is custom-declared"
        )

    if hash_input_scope == "selected_fields":
        selected_fields = fields.get("evidence_selected_fields", "")
        if not selected_fields:
            issues.append(f"record {record_id}: deterministic_runtime record requires evidence_selected_fields")
        elif not is_rendered_list(selected_fields):
            issues.append(f"record {record_id}: deterministic_runtime evidence_selected_fields must be a JSON list")
        if (
            fields.get("evidence_ref") == "any.runtime.trace@v1"
            and (encoding != "utf-8" or canonicalization != "rfc8785" or not is_json_media_type(fields.get("evidence_artifact_media_type", "")))
        ):
            issues.append(
                f"record {record_id}: deterministic_runtime any.runtime.trace@v1 selected_fields requires JSON artifact_media_type, encoding utf-8, and canonicalization rfc8785"
            )

    if hash_input_scope == "line_range":
        if not fields.get("evidence_line_range", ""):
            issues.append(f"record {record_id}: deterministic_runtime record requires evidence_line_range")
        if fields.get("evidence_ref") == "any.runtime.trace@v1" and not line_from_ref(fields.get("evidence_trace_ref", "")):
            issues.append(f"record {record_id}: deterministic_runtime evidence_trace_ref must be line-qualified for line_range scope")

    canonical_output = canonical_output_type if canonicalization == "custom-declared" else None
    if (
        encoding in runtime_envelope_encodings
        and canonicalization in runtime_envelope_canonicalizations
        and hash_input_scope in runtime_envelope_hash_input_scopes
        and (canonicalization != "custom-declared" or canonical_output_type in runtime_envelope_canonical_output_types)
        and (encoding, canonicalization, canonical_output, hash_input_scope) not in runtime_envelope_v1_matrix
    ):
        issues.append(f"record {record_id}: deterministic_runtime evidence envelope is not supported by the v1 validity matrix")


def check_runtime_scenario_fit_metadata(record_id: str) -> None:
    for key in (
        "evidence_scenario_scope",
        "evidence_setter_symbol_path",
        "evidence_setter_module_hash",
        "evidence_expiry_or_invalidation_rule",
    ):
        if not fields.get(key):
            issues.append(f"record {record_id}: deterministic_runtime record requires {key}")

    scenario_scope = fields.get("evidence_scenario_scope", "")
    setter_symbol_path = fields.get("evidence_setter_symbol_path", "")
    setter_module_hash = fields.get("evidence_setter_module_hash", "")
    expiry_or_invalidation_rule = fields.get("evidence_expiry_or_invalidation_rule", "")

    if scenario_scope and not scenario_scope_re.match(scenario_scope):
        issues.append(
            f"record {record_id}: deterministic_runtime evidence_scenario_scope must match ^[A-Za-z0-9_.:/-]{{3,120}}$"
        )
    if setter_symbol_path and not setter_symbol_path_re.match(setter_symbol_path):
        issues.append(
            f"record {record_id}: deterministic_runtime evidence_setter_symbol_path must match ^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$"
        )
    if setter_module_hash and not sha_re.match(setter_module_hash):
        issues.append(f"record {record_id}: deterministic_runtime evidence_setter_module_hash must be sha256")
    if expiry_or_invalidation_rule and expiry_or_invalidation_rule not in expiry_or_invalidation_rules:
        issues.append(
            f"record {record_id}: deterministic_runtime evidence_expiry_or_invalidation_rule must be timestamp, binding_change, or manual_revocation"
        )


def finish(line_no: int, end_id: str) -> None:
    global open_id, fields, record_count
    if open_id is None:
        issues.append(f"line {line_no}: end marker without begin marker")
        return
    if end_id != open_id:
        issues.append(f"line {line_no}: marker id mismatch for {open_id}")
    record_count += 1
    lifecycle = fields.get("lifecycle", "")
    if lifecycle not in allowed_lifecycles:
        issues.append(f"record {open_id}: lifecycle must be confirmed, unknown, blocked, or stale")
    if not fields.get("record_id"):
        issues.append(f"record {open_id}: record_id is required")
    elif fields["record_id"] != open_id:
        issues.append(f"record {open_id}: record_id must match marker id")
    if fields.get("record_type") != "effect_map_entry":
        issues.append(f"record {open_id}: record_type must be effect_map_entry")
    if not fields.get("effect_type"):
        issues.append(f"record {open_id}: effect_type is required")
    if lifecycle == "confirmed":
        for key in ("anchor_file", "anchor_symbol", "evidence_type", "evidence_ref"):
            if not fields.get(key):
                issues.append(f"record {open_id}: confirmed record requires {key}")
        evidence_type = fields.get("evidence_type", "")
        if evidence_type == "deterministic_code":
            for key in (
                "evidence_rule_id",
                "evidence_validator_kind",
                "evidence_parser_backed",
                "evidence_parser_identity",
                "evidence_parser_content_hash",
                "evidence_validator_result",
                "evidence_source_ref",
                "evidence_source_hash",
                "evidence_probe_result_ref",
                "evidence_probe_result_hash",
            ):
                if not fields.get(key):
                    issues.append(f"record {open_id}: deterministic_code record requires {key}")
            if fields.get("evidence_parser_backed", "").lower() != "true":
                issues.append(f"record {open_id}: deterministic_code evidence_parser_backed must be true")
            if fields.get("evidence_parser_content_hash") and not sha_re.match(fields["evidence_parser_content_hash"]):
                issues.append(f"record {open_id}: deterministic_code evidence_parser_content_hash must be sha256")
            if fields.get("evidence_validator_result") != "matched":
                issues.append(f"record {open_id}: deterministic_code evidence_validator_result must be matched")
            if fields.get("evidence_source_hash") and not sha_re.match(fields["evidence_source_hash"]):
                issues.append(f"record {open_id}: deterministic_code evidence_source_hash must be sha256")
            if fields.get("evidence_probe_result_hash") and not sha_re.match(fields["evidence_probe_result_hash"]):
                issues.append(f"record {open_id}: deterministic_code evidence_probe_result_hash must be sha256")
            check_rule(open_id, "deterministic_code", fields.get("evidence_rule_id", ""), fields.get("effect_type", ""), fields.get("evidence_ref", ""))
            if fields.get("evidence_ref") not in catalog_evidence_types:
                issues.append(f"record {open_id}: deterministic_code evidence_ref must be registered in validator catalog")
            elif catalog_evidence_types.get(fields.get("evidence_ref")) not in {"code_call", "annotation", "code_reference", "config_binding"}:
                issues.append(f"record {open_id}: deterministic_code evidence_ref must reference source evidence")
            if fields.get("evidence_ref") not in implemented_validators:
                issues.append(f"record {open_id}: deterministic_code evidence_ref must be implemented")
            if fields.get("evidence_ref") not in parser_backed_validators:
                issues.append(f"record {open_id}: deterministic_code evidence_ref must be parser-backed")
            check_path_binding(open_id, "deterministic_code", fields.get("anchor_file", ""), fields.get("evidence_source_ref", ""), fields.get("anchor_line"))
            check_probe_artifact(open_id, fields.get("evidence_probe_result_ref", ""), fields.get("evidence_probe_result_hash", ""), "deterministic_code")
        elif evidence_type == "deterministic_runtime":
            for key in (
                "evidence_rule_id",
                "evidence_trace_ref",
                "evidence_artifact_hash",
                "evidence_scenario_ref",
                "evidence_user_decision_ref",
                "evidence_probe_result_ref",
                "evidence_probe_result_hash",
            ):
                if not fields.get(key):
                    issues.append(f"record {open_id}: deterministic_runtime record requires {key}")
            check_runtime_envelope(open_id)
            check_runtime_scenario_fit_metadata(open_id)
            if fields.get("evidence_artifact_hash") and not sha_re.match(fields["evidence_artifact_hash"]):
                issues.append(f"record {open_id}: deterministic_runtime evidence_artifact_hash must be sha256")
            if fields.get("evidence_probe_result_hash") and not sha_re.match(fields["evidence_probe_result_hash"]):
                issues.append(f"record {open_id}: deterministic_runtime evidence_probe_result_hash must be sha256")
            check_rule(open_id, "deterministic_runtime", fields.get("evidence_rule_id", ""), fields.get("effect_type", ""), fields.get("evidence_ref", ""))
            if catalog_evidence_types.get(fields.get("evidence_ref")) != "runtime_trace":
                issues.append(f"record {open_id}: deterministic_runtime evidence_ref must reference runtime_trace")
            if fields.get("evidence_ref") not in implemented_validators:
                issues.append(f"record {open_id}: deterministic_runtime evidence_ref must be implemented")
            if fields.get("evidence_ref") == "any.runtime.trace@v1" and sha_re.match(fields.get("evidence_artifact_hash", "")):
                current_artifact_hash = runtime_trace_hash(open_id)
                if current_artifact_hash and current_artifact_hash != fields["evidence_artifact_hash"]:
                    issues.append(f"record {open_id}: deterministic_runtime evidence_artifact_hash must match scoped trace artifact")
            check_path_binding(open_id, "deterministic_runtime", fields.get("anchor_file", ""), fields.get("evidence_trace_ref", ""), fields.get("anchor_line"))
            check_probe_artifact(open_id, fields.get("evidence_probe_result_ref", ""), fields.get("evidence_probe_result_hash", ""), "deterministic_runtime")
        elif evidence_type == "user_decision":
            if fields.get("effect_type") not in human_effect_types:
                issues.append(f"record {open_id}: user_decision evidence requires human-only effect_type")
            if fields.get("evidence_ref") and fields.get("user_decision_ref") and fields["evidence_ref"] == fields["user_decision_ref"]:
                issues.append(f"record {open_id}: user_decision evidence_ref must be separate from final apply user_decision_ref")
        elif evidence_type:
            issues.append(f"record {open_id}: unsupported evidence_type {evidence_type}")
    elif lifecycle in {"unknown", "blocked", "stale"} and not fields.get("reason"):
        issues.append(f"record {open_id}: non-confirmed record requires reason")
    open_id = None
    fields = {}

with open(path, encoding="utf-8", errors="replace") as fh:
    for line_no, raw in enumerate(fh, start=1):
        line = raw.rstrip("\n")
        match = marker.match(line)
        if markerish.search(line) and not match:
            issues.append(f"line {line_no}: malformed shadow-effect-record marker")
        if match and match.group(2) == "begin":
            if open_id is not None:
                issues.append(f"line {line_no}: nested begin marker before closing {open_id}")
            open_id = match.group(1)
            fields = {}
            continue
        if match and match.group(2) == "end":
            finish(line_no, match.group(1))
            continue
        if open_id is not None and line.startswith("- ") and ":" in line:
            key, value = line[2:].split(":", 1)
            fields[key.strip()] = value.strip()

if open_id is not None:
    issues.append(f"record {open_id}: missing end marker")

for issue in issues:
    print(issue)
PY
)"
  if [[ -n "$issue_output" ]]; then
    while IFS= read -r issue; do
      [[ -n "$issue" ]] && fail "${issue} in shadow effect_map: $file_path"
    done <<< "$issue_output"
  else
    pass "shadow effect_map records valid: $file_path"
  fi
}

check_review_queue_file() {
  local file_path="$1"
  local issue_output

  check_field_value_equals "$file_path" "doc_role" "review_queue" "shadow review_queue" || true
  check_field_non_empty "$file_path" "task_id" "shadow review_queue" || true
  check_field_value_equals "$file_path" "generated_by" "shadow_review_queue.py" "shadow review_queue" || true
  check_field_non_empty "$file_path" "generated_at" "shadow review_queue" || true
  check_field_non_empty "$file_path" "ttl_days" "shadow review_queue" || true
  check_field_value_equals "$file_path" "writes_shadow_docs" "false" "shadow review_queue" || true
  check_field_value_equals "$file_path" "auto_promotes_facts" "false" "shadow review_queue" || true

  issue_output="$(python3 - "$file_path" <<'PY'
import sys

path = sys.argv[1]
candidates = {}
questions = []
section = ""
current = None
current_kind = ""

def flush():
    global current
    if not current:
        return
    if current_kind == "candidate":
        candidates[current.get("id", "")] = dict(current)
    elif current_kind == "question":
        questions.append(dict(current))
    current = None

with open(path, encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if line == "## Evidence Candidates":
            flush()
            section = "candidates"
            continue
        if line == "## Review Questions":
            flush()
            section = "questions"
            continue
        if line.startswith("## "):
            flush()
            section = ""
            continue
        if line.startswith("- id: ") and section in {"candidates", "questions"}:
            flush()
            current_kind = "candidate" if section == "candidates" else "question"
            current = {"id": line.split(":", 1)[1].strip()}
            continue
        if current is not None and line.startswith("  ") and ":" in line:
            key, value = line.strip().split(":", 1)
            current[key.strip()] = value.strip()
flush()

issues = []
for candidate_id, candidate in candidates.items():
    if candidate.get("source_ref") == "unknown" and candidate.get("question_state") != "deferred_missing_context":
        issues.append(f"candidate {candidate_id}: unknown source_ref requires question_state deferred_missing_context")
for question in questions:
    ref = question.get("evidence_ref", "")
    candidate = candidates.get(ref)
    if not candidate:
        issues.append(f"question {question.get('id', '<unknown>')}: evidence_ref does not resolve to candidate {ref}")
        continue
    if candidate.get("source_ref") == "unknown" or candidate.get("question_state") == "deferred_missing_context":
        issues.append(f"question {question.get('id', '<unknown>')}: must not ask about deferred or unknown-source candidate {ref}")
for issue in issues:
    print(issue)
PY
)"
  if [[ -n "$issue_output" ]]; then
    while IFS= read -r issue; do
      [[ -n "$issue" ]] && fail "${issue} in shadow review_queue: $file_path"
    done <<< "$issue_output"
  else
    pass "shadow review_queue source refs are bounded: $file_path"
  fi
}

# Content-based replacement for the removed timestamp heuristic (a shadow doc
# "older than" the newest task/decision doc): garden no longer blind-bumps
# bucket/_global docs and only bumps the router on a real change, so a
# last_updated-vs-last_updated comparison would just measure which script ran
# most recently, not whether the shadow graph documents anything. What DOES
# matter is a shadow graph that is entirely EMPTY -- no unit anywhere, no
# source_of_truth_paths declared anywhere -- while the project has real source
# to document. Fires only when a source repo is actually reachable and has
# git-tracked files outside docs/; a scaffold-only fixture with no source repo
# must never trip it.
check_shadow_empty_graph() {
  local source_root
  local bucket
  local bucket_file
  local any_units="false"

  source_root="$(codeguide_source_root "$PROJECT_ROOT_ABS" 2>/dev/null || true)"
  [[ -n "$source_root" ]] || return 0

  # Scaffold artifacts are not "source needing documentation": a freshly
  # bootstrapped docs-only project tracks its routers and markers but no code
  # (fable/sonnet P3-r01 shared finding — the gate must not fail it).
  if ! git -C "$source_root" ls-files 2>/dev/null \
    | grep -qvE '^(docs/|AGENTS\.md$|CLAUDE\.md$|README\.md$|\.gitignore$|\.codeguide-source-root$)'; then
    return 0
  fi

  [[ -d "$SHADOW_DIR" ]] || return 0

  for bucket in "${SHADOW_BUCKETS[@]}"; do
    bucket_file="$SHADOW_DIR/$bucket/_index.md"
    [[ -f "$bucket_file" ]] || continue
    if bucket_index_has_units "$bucket_file"; then
      any_units="true"
      break
    fi
  done

  if [[ "$any_units" == "true" ]]; then
    pass "shadow graph is not empty: at least one bucket declares a unit"
    return 0
  fi

  if shadow_tree_has_source_declarations; then
    pass "shadow graph is not empty: at least one shadow doc declares source_of_truth_paths"
    return 0
  fi

  fail "shadow graph is empty: no bucket declares a unit and no shadow doc declares source_of_truth_paths, though the source repo has trackable files to document. Author shadow units; see shadow_coverage_report.py for the coverage gap"
}

# True if the bucket index's "## Units" section lists a real unit entry. The
# schema shape is "- <unit_id>:" (identifier then colon) with indented detail
# lines; an arbitrary garbage line like "- x" must not be able to silence the
# empty-graph gate (sonnet P3-r01 finding 2).
bucket_index_has_units() {
  local bucket_file="$1"
  local remaining

  remaining="$(awk '/^## Units$/{flag=1; next} /^## /{flag=0} flag && /^- /{print}' "$bucket_file" 2>/dev/null \
    | grep -vFx -- '- no units detected yet' \
    | grep -E '^- [A-Za-z0-9._-]+:' || true)"
  [[ -n "$remaining" ]]
}

# True if ANY shadow doc (excluding _deprecated/_obsolete) declares at least
# one real source_of_truth_paths entry. Reuses shadow_source_digest.py's
# fence-aware parser (the same one check_shadow_source_paths_exist trusts) so
# a fenced-code-block mention of the field cannot manufacture coverage.
shadow_tree_has_source_declarations() {
  local digest_helper="$SCRIPT_DIR/shadow_source_digest.py"
  local shadow_doc
  local result
  local has_paths

  [[ -f "$digest_helper" ]] || return 1
  [[ -d "$SHADOW_DIR" ]] || return 1

  while IFS= read -r shadow_doc; do
    grep -qE "source_of_truth_paths" "$shadow_doc" 2>/dev/null || continue
    result="$(python3 "$digest_helper" "$shadow_doc" --project-root "$PROJECT_ROOT_ABS" --verify-paths 2>/dev/null || true)"
    has_paths="$(printf "%s\n" "$result" | grep -m1 "^has_paths: " | sed 's/^has_paths: //')"
    if [[ "$has_paths" == "true" ]]; then
      return 0
    fi
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
  return 1
}

# Advisory-only (recommended tier): every navigation reference in a shadow doc
# that names a Markdown target must resolve to a real file. This catches a
# rotting read path (dangling overview_doc/next_docs/bucket_links/global_doc, or a
# redirect shim whose canonical_path no longer exists) without breaking existing
# corpora, so it is guarded to advisory mode by the caller (same tier as
# owner/claimed_at). Only values that end in .md are resolved, which excludes tags,
# prose, ids, and source_of_truth code paths (those are covered by other checks).
check_shadow_navigation_links() {
  local issue_output

  issue_output="$(python3 - "$SHADOW_DIR" "$PROJECT_ROOT_ABS" "$DOCS_DIR" <<'PY'
import re
import sys
from pathlib import Path

shadow_dir = Path(sys.argv[1])
project_root = Path(sys.argv[2])
docs_dir = Path(sys.argv[3])

path_fields = ("canonical_path", "overview_doc", "next_docs", "bucket_links", "global_doc")
fields_alt = "|".join(path_fields)
# A path field with an inline value on the same line.
inline_re = re.compile(r"^\s*-\s*(" + fields_alt + r")\s*:\s*(\S.*?)\s*$")
# A bare path-field header whose values are nested bullet lines beneath it.
header_re = re.compile(r"^(\s*)-\s*(" + fields_alt + r")\s*:\s*$")
bullet_re = re.compile(r"^(\s*)-\s+(.*?)\s*$")
# A doc token is a run of path characters ending in .md. The restricted class
# stops the greedy match at Markdown link punctuation, so [label](auth.md) and
# <auth.md> both yield the bare path auth.md rather than a garbled token.
token_re = re.compile(r"[A-Za-z0-9._/-]+\.md\b")
fence = chr(96) * 3


def resolves(ref_file: Path, token: str) -> bool:
    token = token.strip()
    if not token:
        return True
    candidate = Path(token)
    if candidate.is_absolute():
        try:
            return candidate.resolve(strict=False).is_file()
        except OSError:
            return False
    # Precise bases: docs/-prefixed refs (redirect shims) are project-root
    # relative; every other shadow ref resolves against the shadow root or the
    # directory of the referencing doc. This avoids a whole-project search that
    # would let an unrelated same-named file mask a genuinely dangling ref.
    if token.startswith("docs/"):
        bases = (project_root,)
    else:
        bases = (shadow_dir, ref_file.parent)
    for base in bases:
        try:
            if (base / candidate).resolve(strict=False).is_file():
                return True
        except OSError:
            continue
    return False


def scan_value(ref_file: Path, field: str, value: str, issues: list) -> None:
    for token in token_re.findall(value):
        if not resolves(ref_file, token):
            issues.append((str(ref_file), field, token))


issues = []
for md in sorted(shadow_dir.rglob("*.md")):
    rel_parts = md.relative_to(shadow_dir).parts
    if rel_parts and rel_parts[0] in ("_deprecated", "_obsolete"):
        continue
    try:
        lines = md.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        continue
    in_fence = False
    pending_field = None
    pending_indent = -1
    for line in lines:
        if line.lstrip().startswith(fence):
            in_fence = not in_fence
            pending_field = None
            continue
        if in_fence:
            continue
        inline = inline_re.match(line)
        if inline:
            pending_field = None
            scan_value(md, inline.group(1), inline.group(2), issues)
            continue
        header = header_re.match(line)
        if header:
            pending_field = header.group(2)
            pending_indent = len(header.group(1))
            continue
        if pending_field is not None:
            bullet = bullet_re.match(line)
            if bullet and len(bullet.group(1)) > pending_indent:
                scan_value(md, pending_field, bullet.group(2), issues)
                continue
            if line.strip():
                pending_field = None

seen = set()
for ref_file, field, token in issues:
    key = (ref_file, field, token)
    if key in seen:
        continue
    seen.add(key)
    print(f"{ref_file}\t{field}\t{token}")
PY
)"

  if [[ -n "$issue_output" ]]; then
    while IFS=$'\t' read -r ref_file field token; do
      [[ -n "$ref_file" ]] && fail "shadow navigation reference does not resolve: ${field} -> ${token} (${ref_file}); fix the link or remove the stale reference"
    done <<< "$issue_output"
  else
    pass "shadow navigation references resolve to real files"
  fi
}

# Advisory-only (recommended tier): for any shadow doc that has opted in by carrying
# a source_of_truth_digest, recompute the digest of its declared source_of_truth_paths
# and warn on drift or a missing declared source. This binds freshness to source
# CONTENT (not a timestamp that doc_garden auto-bumps). The digest algorithm lives in
# scripts/shadow_source_digest.py; this only consumes its --check result.
check_shadow_source_digest() {
  local digest_helper="$SCRIPT_DIR/shadow_source_digest.py"
  if [[ ! -f "$digest_helper" ]]; then
    return 0
  fi
  local checked=0
  local problems=0
  local shadow_doc
  local result
  local rc
  local line
  local status_line
  while IFS= read -r shadow_doc; do
    grep -qE "^[[:space:]]*-[[:space:]]*source_of_truth_digest:" "$shadow_doc" 2>/dev/null || continue
    checked=1
    # `if !` keeps a helper crash from aborting the whole run under `set -e`.
    if ! result="$(python3 "$digest_helper" "$shadow_doc" --project-root "$PROJECT_ROOT_ABS" --check 2>/dev/null)"; then
      fail "could not verify shadow source-of-truth digest (helper error): $shadow_doc"
      problems=1
      continue
    fi
    status_line=""
    while IFS= read -r line; do
      case "$line" in
        "status: "*) status_line="${line#status: }" ;;
        "missing: "*)
          fail "shadow source-of-truth declared path does not exist: ${line#missing: } ($shadow_doc)"
          problems=1
          ;;
        "escaped: "*)
          fail "shadow source-of-truth declared path escapes the project root: ${line#escaped: } ($shadow_doc)"
          problems=1
          ;;
      esac
    done <<< "$result"
    if [[ -z "$status_line" ]]; then
      fail "could not verify shadow source-of-truth digest (helper error): $shadow_doc"
      problems=1
      continue
    fi
    case "$status_line" in
      drift)
        fail "shadow source-of-truth digest drift, source changed since last verification: $shadow_doc; re-verify then rerun scripts/shadow_source_digest.py --write"
        problems=1
        ;;
      no_paths)
        fail "shadow source_of_truth_digest present but no source_of_truth_paths declared: $shadow_doc"
        problems=1
        ;;
    esac
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
  if (( checked == 1 && problems == 0 )); then
    pass "shadow source-of-truth digests verified against current source"
  fi
}

# Advisory-only (recommended tier): every source_of_truth_paths entry must resolve to
# a real in-project file. This catches a dead/renamed/typo source pointer even when the
# doc has not opted into a source_of_truth_digest. Docs that DO carry a digest are
# skipped here because check_shadow_source_digest already reports their missing/escaped
# sources; this avoids duplicate warnings.
check_shadow_source_paths_exist() {
  local digest_helper="$SCRIPT_DIR/shadow_source_digest.py"
  if [[ ! -f "$digest_helper" ]]; then
    return 0
  fi
  local checked=0
  local problems=0
  local shadow_doc
  local result
  local line
  local has_paths
  local has_digest
  while IFS= read -r shadow_doc; do
    # Cheap pre-filter only; the skip/report decision below is parser-backed.
    grep -qE "source_of_truth_paths" "$shadow_doc" 2>/dev/null || continue
    # `if !` keeps a helper crash from aborting the whole run under `set -e`.
    if ! result="$(python3 "$digest_helper" "$shadow_doc" --project-root "$PROJECT_ROOT_ABS" --verify-paths 2>/dev/null)"; then
      fail "could not verify shadow source_of_truth_paths (helper error): $shadow_doc"
      problems=1
      continue
    fi
    has_paths=""
    has_digest=""
    while IFS= read -r line; do
      case "$line" in
        "has_paths: "*) has_paths="${line#has_paths: }" ;;
        "has_digest: "*) has_digest="${line#has_digest: }" ;;
      esac
    done <<< "$result"
    # Parser-backed gating: skip docs with no real declared paths, and docs that carry
    # a real digest (check_shadow_source_digest owns those). Deciding this from the
    # fence-aware parser rather than a raw grep closes the empty/fenced-field evasion
    # where a bare or fenced source_of_truth_digest line silenced this check.
    [[ "$has_paths" == "true" ]] || continue
    [[ "$has_digest" == "true" ]] && continue
    checked=1
    while IFS= read -r line; do
      case "$line" in
        "missing: "*)
          fail "shadow source_of_truth path does not exist: ${line#missing: } ($shadow_doc)"
          problems=1
          ;;
        "escaped: "*)
          fail "shadow source_of_truth path escapes the project root: ${line#escaped: } ($shadow_doc)"
          problems=1
          ;;
      esac
    done <<< "$result"
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
  if (( checked == 1 && problems == 0 )); then
    pass "shadow source_of_truth_paths all resolve to real in-project files"
  fi
}

# Fence-aware reader for a top-level "- key:" field: returns the first non-empty value
# that is NOT inside a fenced code example, tolerating leading indentation. This avoids
# treating a fenced template example as a real field, surfaces indented carriers instead
# of silently skipping them, and skips an empty stub in favour of a later real value.
extract_shadow_field() {
  local file_path="$1"
  local key="$2"
  awk -v key="$key" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
    infence { next }
    {
      pat = "^[[:space:]]*-[[:space:]]*" key ":"
      if ($0 ~ pat) {
        val = $0
        sub(pat, "", val)
        val = trim(val)
        if (val != "") { print val; exit }
      }
    }
  ' "$file_path" 2>/dev/null
}

# Advisory-only (recommended tier): the shadow value-carrier docs (unit_overview,
# concern_leaf) have no field validation elsewhere -- only the line-limit and effect_map
# checks touch them. Verify the minimal IDENTIFYING schema (home_bucket / concern_id) so a
# malformed carrier is surfaced, without enforcing optional fields like last_updated
# (which has a documented mtime fallback elsewhere). Other doc_roles keep their own checks.
check_shadow_unit_schema() {
  local shadow_doc
  local doc_role
  local bucket_value
  local checked=0
  local problems=0
  while IFS= read -r shadow_doc; do
    doc_role="$(extract_shadow_field "$shadow_doc" "doc_role")"
    case "$doc_role" in
      unit_overview)
        checked=1
        bucket_value="$(extract_shadow_field "$shadow_doc" "home_bucket")"
        if [[ -z "$bucket_value" ]]; then
          fail "shadow unit overview missing home_bucket: $shadow_doc"
          problems=1
        elif ! printf '%s\n' "${SHADOW_BUCKETS[@]}" | grep -qxF -- "$bucket_value"; then
          fail "shadow unit overview home_bucket is not a known bucket (${bucket_value}): $shadow_doc"
          problems=1
        fi
        ;;
      concern_leaf)
        checked=1
        if [[ -z "$(extract_shadow_field "$shadow_doc" "concern_id")" ]]; then
          fail "shadow concern leaf missing concern_id: $shadow_doc"
          problems=1
        fi
        ;;
    esac
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
  if (( checked == 1 && problems == 0 )); then
    pass "shadow unit/concern docs have valid schema"
  fi
}

collect_versioned_registry_ids() {
  local file_path="$1"
  grep -E '^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+:' "$file_path" 2>/dev/null \
    | sed -E 's/^[[:space:]]*([^:]+):.*$/\1/' \
    | sort -u || true
}

collect_versioned_registry_ids_in_block() {
  local file_path="$1"
  local block_name="$2"
  awk -v block_name="$block_name" '
    $0 == block_name ":" {
      in_block=1
      next
    }
    in_block && /^```/ {
      in_block=0
      next
    }
    in_block && /^[^[:space:]`#][^:]*:/ && $0 != block_name ":" {
      in_block=0
      next
    }
    in_block && /^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+:/ {
      id=$1
      sub(/:$/, "", id)
      print id
    }
  ' "$file_path" | sort -u || true
}

collect_rule_registry_refs() {
  local file_path="$1"
  local key="$2"
  grep -E "^[[:space:]]+${key}:[[:space:]]*[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+" "$file_path" 2>/dev/null \
    | sed -E "s/^[[:space:]]+${key}:[[:space:]]*([^ #]+).*$/\1/" \
    | sort -u || true
}

collect_backtick_registry_ids_for_field() {
  local file_path="$1"
  local field_name="$2"
  grep -E "^[[:space:]]*-[[:space:]]*${field_name}:" "$file_path" 2>/dev/null \
    | grep -oE '`[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+`' \
    | tr -d '`' \
    | sort -u || true
}

collect_probe_primary_validator_ids() {
  local probe_script="$1"
  python3 "$SCRIPT_DIR/shadow_policy_loader.py" --adapter-module "$probe_script" --print-adapter-ids 2>/dev/null || true
}

collect_policy_loader_ids() {
  local field_name="$1"
  set +e
  python3 "$SCRIPT_DIR/shadow_policy_loader.py" --policy-dir "$POLICY_DIR" --print-policy-json 2>/dev/null \
    | python3 -c 'import json,sys
field=sys.argv[1]
try:
    data=json.load(sys.stdin)
except Exception:
    data={}
value=data.get(field)
if isinstance(value, dict):
    items=sorted(value.keys())
elif isinstance(value, list):
    items=sorted(str(item) for item in value)
else:
    items=[]
for item in items:
    print(item)
' "$field_name"
  local status=$?
  set -e
  return "$status"
}

check_policy_loader_contract() {
  local loader_output
  local loader_status
  local issue_output

  set +e
  loader_output="$(python3 "$SCRIPT_DIR/shadow_policy_loader.py" --policy-dir "$POLICY_DIR" --adapter-module "$SCRIPT_DIR/shadow_evidence_probe.py" --check-parity 2>&1)"
  loader_status=$?
  set -e
  if (( loader_status == 0 )); then
    pass "shadow policy loader strict contract passes"
    return
  fi

  issue_output="$(printf "%s" "$loader_output" | python3 -c 'import json,sys
raw=sys.stdin.read()
try:
    data=json.loads(raw)
    errors=data.get("errors") or [data.get("error") or raw]
except Exception:
    errors=[raw]
for item in errors:
    print(item)
' 2>/dev/null || printf "%s\n" "$loader_output")"
  while IFS= read -r issue; do
    [[ -n "$issue" ]] && fail "shadow policy loader strict contract failed: ${issue}"
  done <<< "$issue_output"
}

check_catalog_probe_coverage() {
  local catalog_file="$1"
  local implemented_ids
  local parser_ids
  local source_probe_ids
  local declared_ids
  local probe_ids
  local id
  local mismatch_count=0

  declared_ids="$(collect_policy_loader_ids "validators")"
  implemented_ids="$(collect_policy_loader_ids "implemented_primary")"
  parser_ids="$(collect_policy_loader_ids "parser_backed_now")"
  source_probe_ids="$(collect_policy_loader_ids "source_probe_only")"
  probe_ids="$(collect_probe_primary_validator_ids "$SCRIPT_DIR/shadow_evidence_probe.py")"

  if [[ -z "$implemented_ids" ]]; then
    fail "shadow validator catalog must declare implemented_primary_v1 (${catalog_file})"
  else
    pass "shadow validator catalog declares implemented_primary_v1"
  fi
  if [[ -z "$parser_ids" ]]; then
    fail "shadow validator catalog must declare parser_backed_now (${catalog_file})"
  else
    pass "shadow validator catalog declares parser_backed_now"
  fi
  if [[ -z "$source_probe_ids" ]]; then
    fail "shadow validator catalog must declare source_probe_only (${catalog_file})"
  else
    pass "shadow validator catalog declares source_probe_only"
  fi
  if [[ -z "$probe_ids" ]]; then
    fail "shadow_evidence_probe.py must expose primary AdapterRegistry ids (${catalog_file})"
    mismatch_count=$((mismatch_count + 1))
  fi

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! printf "%s\n" "$declared_ids" | grep -Fxq "$id"; then
      fail "implemented_primary_v1 id must be declared in validators block: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
    if [[ -n "$probe_ids" ]] && ! printf "%s\n" "$probe_ids" | grep -Fxq "$id"; then
      fail "implemented_primary_v1 id must be implemented by shadow_evidence_probe.py: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
  done <<< "$implemented_ids"

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! printf "%s\n" "$implemented_ids" | grep -Fxq "$id"; then
      fail "shadow_evidence_probe.py primary validator missing from implemented_primary_v1: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
  done <<< "$probe_ids"

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! printf "%s\n" "$declared_ids" | grep -Fxq "$id"; then
      fail "parser_backed_now id must be declared in validators block: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
    if ! printf "%s\n" "$implemented_ids" | grep -Fxq "$id"; then
      fail "parser_backed_now id must also be implemented_primary_v1: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
  done <<< "$parser_ids"

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! printf "%s\n" "$declared_ids" | grep -Fxq "$id"; then
      fail "source_probe_only id must be declared in validators block: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
    if ! printf "%s\n" "$implemented_ids" | grep -Fxq "$id"; then
      fail "source_probe_only id must also be implemented_primary_v1: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
    if printf "%s\n" "$parser_ids" | grep -Fxq "$id"; then
      fail "source_probe_only id must not also be parser_backed_now: ${id} (${catalog_file})"
      mismatch_count=$((mismatch_count + 1))
    fi
  done <<< "$source_probe_ids"

  if (( mismatch_count == 0 )); then
    pass "shadow validator catalog probe coverage sets are internally consistent"
  fi
}

check_rule_registry_ref_versions() {
  local rule_file="$1"
  local line
  local key
  local ref
  local invalid_count=0

  while IFS= read -r line; do
    key="$(printf "%s" "$line" | sed -E 's/^[[:space:]]+(primary|fallback):.*$/\1/')"
    ref="$(printf "%s" "$line" | sed -E 's/^[[:space:]]+(primary|fallback):[[:space:]]*([^ #]+).*$/\2/')"
    if [[ ! "$ref" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+$ ]]; then
      fail "rule registry ${key} reference must be versioned: ${ref} (${rule_file})"
      invalid_count=$((invalid_count + 1))
    fi
  done < <(grep -E '^[[:space:]]+(primary|fallback):' "$rule_file" 2>/dev/null || true)

  if (( invalid_count == 0 )); then
    pass "rule registry primary/fallback references are versioned"
  fi
}

check_policy_risk_field_values() {
  local file_path="$1"
  local field_name="$2"
  local label="$3"
  local line
  local value
  local seen_count=0
  local invalid_count=0

  while IFS= read -r line; do
    seen_count=$((seen_count + 1))
    value="$(printf "%s" "$line" | sed -E "s/^[[:space:]]+${field_name}:[[:space:]]*([^ #]+).*$/\1/")"
    if [[ ! "$value" =~ ^(low|medium)$ ]]; then
      fail "${field_name} must be low|medium in ${label}: ${value} (${file_path})"
      invalid_count=$((invalid_count + 1))
    fi
  done < <(grep -E "^[[:space:]]+${field_name}:" "$file_path" 2>/dev/null || true)

  if (( seen_count == 0 )); then
    fail "${field_name} is missing in ${label}: ${file_path}"
    return
  fi

  if (( invalid_count == 0 )); then
    pass "${field_name} values are low|medium in ${label}"
  fi
}

collect_validator_evidence_map() {
  local file_path="$1"
  awk '
    /^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+:/ {
      id=$1
      sub(/:$/, "", id)
      current=id
      next
    }
    current != "" && /^[[:space:]]+evidence_type:[[:space:]]*/ {
      evidence=$0
      sub(/^[[:space:]]+evidence_type:[[:space:]]*/, "", evidence)
      sub(/[[:space:]#].*$/, "", evidence)
      print current " " evidence
      current=""
    }
  ' "$file_path"
}

collect_regex_evidence_map() {
  local file_path="$1"
  awk '
    /^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+@v[0-9]+:/ {
      id=$1
      sub(/:$/, "", id)
      current=id
      next
    }
    current != "" && /^[[:space:]]+(target|evidence_type):[[:space:]]*/ {
      evidence=$0
      sub(/^[[:space:]]+(target|evidence_type):[[:space:]]*/, "", evidence)
      sub(/[[:space:]#].*$/, "", evidence)
      print current " " evidence
      current=""
    }
  ' "$file_path"
}

check_rule_registry_promotion_gates() {
  local rule_file="$1"
  local failures

  failures="$(awk '
    function mark_list(value) {
      if (value == "parser_backed_validator") parser=1
      if (value == "test_assertion") test=1
      if (value == "runtime_trace") runtime=1
      if (value == "valid_waiver") waiver=1
    }
    /^promotion_gates:[[:space:]]*$/ {
      in_pg=1
      section=""
      seen_pg=1
      next
    }
    in_pg && /^```/ {
      in_pg=0
      section=""
      next
    }
    in_pg && /^[^[:space:]][^:]*:[[:space:]]*$/ && $0 !~ /^promotion_gates:/ {
      in_pg=0
      section=""
      next
    }
    !in_pg { next }
    /^[[:space:]]{2}regex_only:[[:space:]]*$/ {
      section="regex"
      seen_regex=1
      next
    }
    /^[[:space:]]{2}high_or_critical:[[:space:]]*$/ {
      section="high"
      seen_high=1
      next
    }
    /^[[:space:]]{2}unknown_defaults:[[:space:]]*$/ {
      section="unknown"
      seen_unknown=1
      next
    }
    section == "regex" && /^[[:space:]]{4}max_effective_risk:[[:space:]]*medium([[:space:]#]|$)/ { regex_max=1 }
    section == "regex" && /^[[:space:]]{4}evidence_field:[[:space:]]*fallback_result([[:space:]#]|$)/ { regex_evidence=1 }
    section == "regex" && /^[[:space:]]{4}forbidden_field:[[:space:]]*validator_result([[:space:]#]|$)/ { regex_forbidden=1 }
    section == "high" && /^[[:space:]]{6}-[[:space:]]*/ {
      value=$0
      sub(/^[[:space:]]{6}-[[:space:]]*/, "", value)
      sub(/[[:space:]#].*$/, "", value)
      mark_list(value)
    }
    section == "unknown" && /^[[:space:]]{4}unlisted_rule:[[:space:]]*unknown([[:space:]#]|$)/ { unknown_rule=1 }
    section == "unknown" && /^[[:space:]]{4}unlisted_boundary:[[:space:]]*unknown([[:space:]#]|$)/ { unknown_boundary=1 }
    section == "unknown" && /^[[:space:]]{4}unmapped_stack:[[:space:]]*unknown([[:space:]#]|$)/ { unknown_stack=1 }
    section == "unknown" && /^[[:space:]]{4}unmapped_evidence_type:[[:space:]]*unknown([[:space:]#]|$)/ { unknown_evidence=1 }
    END {
      if (!seen_pg) print "shadow rule registry missing promotion_gates"
      if (!seen_regex) print "shadow rule registry missing regex_only gate"
      if (!regex_max) print "shadow rule registry regex_only.max_effective_risk must be medium"
      if (!regex_evidence) print "shadow rule registry regex_only.evidence_field must be fallback_result"
      if (!regex_forbidden) print "shadow rule registry regex_only.forbidden_field must be validator_result"
      if (!seen_high) print "shadow rule registry missing high_or_critical gate"
      if (!parser) print "shadow rule registry high_or_critical missing parser_backed_validator"
      if (!test) print "shadow rule registry high_or_critical missing test_assertion"
      if (!runtime) print "shadow rule registry high_or_critical missing runtime_trace"
      if (!waiver) print "shadow rule registry high_or_critical missing valid_waiver"
      if (!seen_unknown) print "shadow rule registry missing unknown_defaults"
      if (!unknown_rule) print "shadow rule registry must default unlisted_rule to unknown"
      if (!unknown_boundary) print "shadow rule registry must default unlisted_boundary to unknown"
      if (!unknown_stack) print "shadow rule registry must default unmapped_stack to unknown"
      if (!unknown_evidence) print "shadow rule registry must default unmapped_evidence_type to unknown"
    }
  ' "$rule_file")"

  if [[ -n "$failures" ]]; then
    while IFS= read -r failure_line; do
      [[ -n "$failure_line" ]] || continue
      fail "${failure_line} (${rule_file})"
    done <<< "$failures"
  else
    pass "shadow rule registry promotion gates are scoped and complete"
  fi
}

check_rule_registry_mapping_contracts() {
  local rule_file="$1"
  local catalog_file="$2"
  local regex_file="$3"
  local catalog_map
  local regex_map
  local failures

  catalog_map="$(mktemp)"
  regex_map="$(mktemp)"
  collect_validator_evidence_map "$catalog_file" > "$catalog_map"
  collect_regex_evidence_map "$regex_file" > "$regex_map"

  failures="$(awk -v catalog_file="$catalog_map" -v regex_file="$regex_map" '
    FILENAME == catalog_file {
      catalog[$1]=$2
      next
    }
    FILENAME == regex_file {
      regex[$1]=$2
      next
    }
    function flush_fallback() {
      if (pending_fallback && !fallback_cap_seen) {
        print "fallback mapping missing fallback_max_risk for " pending_fallback_id " under " current_evidence " at line " pending_fallback_line
      }
      pending_fallback=0
      fallback_cap_seen=0
      pending_fallback_id=""
      pending_fallback_line=0
    }
    /^[[:space:]]{8}[a-z_][a-z0-9_]*:[[:space:]]*$/ {
      flush_fallback()
      current_evidence=$0
      sub(/^[[:space:]]+/, "", current_evidence)
      sub(/:.*$/, "", current_evidence)
      next
    }
    current_evidence != "" && /^[[:space:]]{10}primary:[[:space:]]*/ {
      id=$0
      sub(/^[[:space:]]+primary:[[:space:]]*/, "", id)
      sub(/[[:space:]#].*$/, "", id)
      if ((id in catalog) && catalog[id] != current_evidence) {
        print "primary validator evidence_type mismatch for " id ": expected " current_evidence ", found " catalog[id] " at line " NR
      }
      next
    }
    current_evidence != "" && /^[[:space:]]{10}fallback:[[:space:]]*/ {
      flush_fallback()
      id=$0
      sub(/^[[:space:]]+fallback:[[:space:]]*/, "", id)
      sub(/[[:space:]#].*$/, "", id)
      pending_fallback=1
      pending_fallback_id=id
      pending_fallback_line=NR
      if ((id in regex) && regex[id] != current_evidence) {
        print "fallback regex evidence_type mismatch for " id ": expected " current_evidence ", found " regex[id] " at line " NR
      }
      next
    }
    current_evidence != "" && /^[[:space:]]{10}fallback_max_risk:[[:space:]]*/ {
      value=$0
      sub(/^[[:space:]]+fallback_max_risk:[[:space:]]*/, "", value)
      sub(/[[:space:]#].*$/, "", value)
      if (value !~ /^(low|medium)$/) {
        print "fallback_max_risk must be low|medium in shadow rule registry: " value " at line " NR
      }
      if (pending_fallback) {
        fallback_cap_seen=1
      }
      next
    }
    END {
      flush_fallback()
    }
  ' "$catalog_map" "$regex_map" "$rule_file")"

  rm -f "$catalog_map" "$regex_map"

  if [[ -n "$failures" ]]; then
    while IFS= read -r failure_line; do
      [[ -n "$failure_line" ]] || continue
      fail "${failure_line} (${rule_file})"
    done <<< "$failures"
  else
    pass "shadow rule registry mapping contracts are structurally valid"
  fi
}

check_rule_registry_refs_exist() {
  local rule_file="$1"
  local ref_kind="$2"
  local known_ids="$3"
  local known_label="$4"
  local ref
  local missing_count=0

  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    if ! printf "%s\n" "$known_ids" | grep -Fxq "$ref"; then
      fail "rule registry references unknown ${ref_kind} ${known_label}: ${ref} (${rule_file})"
      missing_count=$((missing_count + 1))
    fi
  done < <(collect_rule_registry_refs "$rule_file" "$ref_kind")

  if (( missing_count == 0 )); then
    pass "rule registry ${ref_kind} references resolve against ${known_label}"
  fi
}

check_rule_registry_has_mappings() {
  local rule_file="$1"
  local rule_count
  local primary_count
  local effect_type_count
  local effect_type_failures

  check_file_contains_pattern "$rule_file" "^[[:space:]]{0,2}rules:" "shadow rule registry declares rules block" "shadow rule registry missing rules block (${rule_file})"

  rule_count="$(grep -E '^[[:space:]]{2,}[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+:' "$rule_file" 2>/dev/null | grep -Ev '@v[0-9]+:' | wc -l | tr -d ' ')"
  primary_count="$(collect_rule_registry_refs "$rule_file" "primary" | wc -l | tr -d ' ')"
  effect_type_count="$(grep -E '^[[:space:]]{4}allowed_effect_types:[[:space:]]*\[[a-z0-9_,[:space:]]+\]' "$rule_file" 2>/dev/null | wc -l | tr -d ' ')"

  if (( rule_count == 0 )); then
    fail "shadow rule registry must contain at least one rule id mapping: $rule_file"
  else
    pass "shadow rule registry contains rule id mappings (${rule_count})"
  fi

  if (( primary_count == 0 )); then
    fail "shadow rule registry must contain at least one primary validator mapping: $rule_file"
  else
    pass "shadow rule registry contains primary validator mappings (${primary_count})"
  fi

  if (( effect_type_count < rule_count )); then
    fail "shadow rule registry must declare allowed_effect_types for every rule (${effect_type_count}/${rule_count}): $rule_file"
  else
    pass "shadow rule registry declares allowed_effect_types for every rule (${effect_type_count})"
  fi

  effect_type_failures="$(awk '
    /^[[:space:]]{4}allowed_effect_types:[[:space:]]*/ {
      value=$0
      sub(/^[[:space:]]+allowed_effect_types:[[:space:]]*\[/, "", value)
      sub(/\].*$/, "", value)
      n=split(value, parts, ",")
      for (i=1; i<=n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
        if (parts[i] !~ /^[a-z][a-z0-9_]*$/) {
          print "invalid allowed_effect_types value: " parts[i] " at line " NR
        }
      }
    }
  ' "$rule_file")"
  if [[ -n "$effect_type_failures" ]]; then
    while IFS= read -r failure_line; do
      [[ -n "$failure_line" ]] || continue
      fail "${failure_line} (${rule_file})"
    done <<< "$effect_type_failures"
  else
    pass "shadow rule registry allowed_effect_types values are structurally valid"
  fi
}

check_shadow_policy_files() {
  local catalog_file="$POLICY_DIR/shadow-validator-catalog.md"
  local regex_file="$POLICY_DIR/shadow-regex-patterns.md"
  local rule_file="$POLICY_DIR/shadow-rule-registry.md"
  local required_prefix
  local catalog_ids
  local regex_ids

  check_file_exists "$catalog_file" "shadow validator catalog"
  check_file_exists "$regex_file" "shadow regex pattern registry"
  check_file_exists "$rule_file" "shadow rule registry"

  [[ -f "$catalog_file" && -f "$regex_file" && -f "$rule_file" ]] || return

  check_line_limit "$catalog_file" "$MAX_POLICY_LINES" "shadow validator catalog"
  check_line_limit "$regex_file" "$MAX_POLICY_LINES" "shadow regex pattern registry"
  check_line_limit "$rule_file" "$MAX_POLICY_LINES" "shadow rule registry"

  check_field_non_empty "$catalog_file" "catalog_id" "shadow validator catalog" || true
  check_field_non_empty "$catalog_file" "catalog_version" "shadow validator catalog" || true
  check_field_non_empty "$catalog_file" "status" "shadow validator catalog" || true
  check_any_field_non_empty "$catalog_file" "shadow validator catalog" "linked_task" "template_linked_task" || true
  check_any_field_non_empty "$catalog_file" "shadow validator catalog" "linked_decision" "template_linked_decision" || true
  check_field_non_empty "$catalog_file" "purpose" "shadow validator catalog" || true
  check_field_non_empty "$catalog_file" "last_updated" "shadow validator catalog" || true

  check_field_non_empty "$regex_file" "registry_id" "shadow regex pattern registry" || true
  check_field_non_empty "$regex_file" "registry_version" "shadow regex pattern registry" || true
  check_field_non_empty "$regex_file" "status" "shadow regex pattern registry" || true
  check_any_field_non_empty "$regex_file" "shadow regex pattern registry" "linked_task" "template_linked_task" || true
  check_any_field_non_empty "$regex_file" "shadow regex pattern registry" "linked_decision" "template_linked_decision" || true
  check_field_non_empty "$regex_file" "purpose" "shadow regex pattern registry" || true
  check_field_non_empty "$regex_file" "last_updated" "shadow regex pattern registry" || true

  check_field_non_empty "$rule_file" "registry_id" "shadow rule registry" || true
  check_field_non_empty "$rule_file" "registry_version" "shadow rule registry" || true
  check_field_non_empty "$rule_file" "status" "shadow rule registry" || true
  check_any_field_non_empty "$rule_file" "shadow rule registry" "linked_task" "template_linked_task" || true
  check_any_field_non_empty "$rule_file" "shadow rule registry" "linked_decisions" "template_linked_decisions" || true
  check_field_non_empty "$rule_file" "purpose" "shadow rule registry" || true
  check_field_non_empty "$rule_file" "last_updated" "shadow rule registry" || true

  for required_prefix in any java js ts py spring_boot express react fastapi jpa sql; do
    check_file_contains_pattern \
      "$catalog_file" \
      "^[[:space:]]{2,}${required_prefix}\\.[a-z0-9_.]+@v[0-9]+:" \
      "shadow validator catalog includes ${required_prefix} versioned validators" \
      "shadow validator catalog missing ${required_prefix} versioned validator prefix (${catalog_file})"
  done
  check_catalog_probe_coverage "$catalog_file"
  check_policy_loader_contract

  check_file_contains_pattern \
    "$regex_file" \
    "^[[:space:]]{2,}[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+@v[0-9]+:" \
    "shadow regex registry uses versioned regex ids" \
    "shadow regex registry has no versioned regex ids (${regex_file})"
  check_file_contains_pattern "$regex_file" "allowed_paths:" "shadow regex registry declares allowed_paths" "shadow regex registry missing allowed_paths (${regex_file})"
  check_file_contains_pattern "$regex_file" "excluded_paths:" "shadow regex registry declares excluded_paths" "shadow regex registry missing excluded_paths (${regex_file})"
  check_file_contains_pattern "$regex_file" "validates:" "shadow regex registry declares validates" "shadow regex registry missing validates (${regex_file})"
  check_file_contains_pattern "$regex_file" "cannot_validate:" "shadow regex registry declares cannot_validate" "shadow regex registry missing cannot_validate (${regex_file})"
  check_file_contains_pattern "$regex_file" "max_promotion_risk:" "shadow regex registry declares max_promotion_risk" "shadow regex registry missing max_promotion_risk (${regex_file})"

  check_policy_risk_field_values "$regex_file" "max_promotion_risk" "shadow regex pattern registry"

  check_rule_registry_has_mappings "$rule_file"
  check_rule_registry_ref_versions "$rule_file"
  check_rule_registry_promotion_gates "$rule_file"
  check_rule_registry_mapping_contracts "$rule_file" "$catalog_file" "$regex_file"

  catalog_ids="$(collect_versioned_registry_ids_in_block "$catalog_file" "validators")"
  regex_ids="$(collect_versioned_registry_ids_in_block "$regex_file" "regex_patterns")"
  check_rule_registry_refs_exist "$rule_file" "primary" "$catalog_ids" "validator catalog id"
  check_rule_registry_refs_exist "$rule_file" "fallback" "$regex_ids" "regex pattern id"
}
