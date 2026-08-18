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
