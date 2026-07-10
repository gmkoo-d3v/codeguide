#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate_docs.sh <project-root> [options]

Options:
  --mode <advisory|strict>   Validation mode (default: advisory)
  --max-shadow-lines <n>      Maximum lines per project docs/shadow/*.md file (default: 300)
  --max-task-lines <n>        Maximum lines per project docs/task/TASK-*.md (default: 220)
  --max-decision-lines <n>    Maximum lines per project docs/decisions/decision-*.md (default: 180)
  --max-plan-lines <n>        Maximum lines per project docs/plan/PLAN-*.md (default: 220)
  --max-report-lines <n>      Maximum lines per project docs/report/PLAN-*-review-*.md (default: 180)
  --max-policy-lines <n>      Maximum lines per project docs/policy/*.md file (default: 220)
  --max-shadow-age-days <n>   Max allowed age for required shadow graph docs (default: 0, disabled)
  --max-task-age-days <n>     Max age for in_progress tasks (default: 7)
  --secret-scan-exclude-glob <glob>
                              Exclude glob for secret scan (repeatable).
  -h, --help                  Show this message
EOF
}

# Handle --help before requiring positional args
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PROJECT_ROOT="${1%/}"
shift

MODE="advisory"
MAX_SHADOW_LINES=300
MAX_TASK_LINES=220
MAX_DECISION_LINES=180
MAX_PLAN_LINES=220
MAX_REPORT_LINES=180
MAX_ORCHESTRATION_LINES=180
MAX_POLICY_LINES=220
MAX_SHADOW_AGE_DAYS=0
MAX_TASK_AGE_DAYS=7
SECRET_SCAN_EXCLUDE_GLOBS=(
  "**/task-template.md"
  "**/decision-template.md"
  "**/PLAN-template.md"
  "**/LLM-REVIEW-template.md"
  "**/orchestration/_templates/*.md"
)

require_option_value() {
  local option_name="$1"
  local remaining_args="$2"
  if (( remaining_args < 2 )); then
    echo "[ERROR] Option ${option_name} requires a value" >&2
    usage
    exit 1
  fi
}

require_positive_integer() {
  local option_name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ || "$value" -le 0 ]]; then
    echo "[ERROR] ${option_name} must be a positive integer: ${value}" >&2
    exit 1
  fi
}

require_non_negative_integer() {
  local option_name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] ${option_name} must be a non-negative integer: ${value}" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      require_option_value "$1" "$#"
      MODE="${2:-}"
      shift 2
      ;;
    --max-shadow-lines)
      require_option_value "$1" "$#"
      MAX_SHADOW_LINES="${2:-}"
      shift 2
      ;;
    --max-task-lines)
      require_option_value "$1" "$#"
      MAX_TASK_LINES="${2:-}"
      shift 2
      ;;
    --max-decision-lines)
      require_option_value "$1" "$#"
      MAX_DECISION_LINES="${2:-}"
      shift 2
      ;;
    --max-plan-lines)
      require_option_value "$1" "$#"
      MAX_PLAN_LINES="${2:-}"
      shift 2
      ;;
    --max-report-lines)
      require_option_value "$1" "$#"
      MAX_REPORT_LINES="${2:-}"
      shift 2
      ;;
    --max-policy-lines)
      require_option_value "$1" "$#"
      MAX_POLICY_LINES="${2:-}"
      shift 2
      ;;
    --max-shadow-age-days)
      require_option_value "$1" "$#"
      MAX_SHADOW_AGE_DAYS="${2:-}"
      shift 2
      ;;
    --max-task-age-days)
      require_option_value "$1" "$#"
      MAX_TASK_AGE_DAYS="${2:-}"
      shift 2
      ;;
    --secret-scan-exclude-glob)
      require_option_value "$1" "$#"
      SECRET_SCAN_EXCLUDE_GLOBS+=("${2:-}")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "[ERROR] Project root does not exist: $PROJECT_ROOT" >&2
  exit 1
fi

if [[ "$MODE" != "advisory" && "$MODE" != "strict" ]]; then
  echo "[ERROR] Invalid mode: $MODE (use advisory or strict)" >&2
  exit 1
fi

require_positive_integer "--max-shadow-lines" "$MAX_SHADOW_LINES"
require_positive_integer "--max-task-lines" "$MAX_TASK_LINES"
require_positive_integer "--max-decision-lines" "$MAX_DECISION_LINES"
require_positive_integer "--max-plan-lines" "$MAX_PLAN_LINES"
require_positive_integer "--max-report-lines" "$MAX_REPORT_LINES"
require_positive_integer "--max-policy-lines" "$MAX_POLICY_LINES"
require_non_negative_integer "--max-shadow-age-days" "$MAX_SHADOW_AGE_DAYS"
require_non_negative_integer "--max-task-age-days" "$MAX_TASK_AGE_DAYS"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/codeguide_paths.sh"

PROJECT_ROOT_ABS="$(codeguide_resolve_project_root "$PROJECT_ROOT")"
DOCS_DIR="$(codeguide_docs_root "$PROJECT_ROOT_ABS")"
TASK_DIR="$DOCS_DIR/task"
TASK_CLAIMS_DIR="$TASK_DIR/.claims"
SHADOW_DIR="$DOCS_DIR/shadow"
SHADOW_GLOBAL_FILE="$SHADOW_DIR/_global.md"
SHADOW_BUCKETS=(apps services packages infra data)
DECISIONS_DIR="$DOCS_DIR/decisions"
PLAN_DIR="$DOCS_DIR/plan"
REPORT_DIR="$DOCS_DIR/report"
ORCHESTRATION_DIR="$(codeguide_orchestration_root "$PROJECT_ROOT_ABS")"
ORCHESTRATION_TEMPLATES_DIR="$(codeguide_orchestration_templates_dir "$PROJECT_ROOT_ABS")"
POLICY_DIR="$DOCS_DIR/policy"
ISSUE_TRACKER_DIR="$DOCS_DIR/issues"
ISSUE_TRACKER_CURRENT_DIR="$ISSUE_TRACKER_DIR/current"
ISSUE_TRACKER_RESOLVED_DIR="$ISSUE_TRACKER_DIR/resolved"

ISSUE_COUNT=0

fail() {
  if [[ "$MODE" == "strict" ]]; then
    echo "[FAIL] $1" >&2
  else
    echo "[WARN] $1" >&2
  fi
  ISSUE_COUNT=$((ISSUE_COUNT + 1))
}

pass() {
  echo "[PASS] $1"
}

for _required_cmd in python3 perl; do
  if ! command -v "$_required_cmd" >/dev/null 2>&1; then
    echo "[ERROR] ${_required_cmd} is required for documentation validation but was not found in PATH" >&2
    exit 1
  fi
done

file_mtime_epoch() {
  local file_path="$1"
  if stat -f %m "$file_path" >/dev/null 2>&1; then
    stat -f %m "$file_path"
  else
    stat -c %Y "$file_path"
  fi
}

file_age_days() {
  local file_path="$1"
  local now_epoch
  local mtime_epoch

  now_epoch="$(date +%s)"
  mtime_epoch="$(file_mtime_epoch "$file_path")"
  echo $(((now_epoch - mtime_epoch) / 86400))
}

parse_iso_date_epoch() {
  local value="$1"
  local parsed=""
  local date_part=""

  if [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$value" "+%s" >/dev/null 2>&1; then
      parsed="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$value" "+%s")"
    else
      parsed="$(date -u -d "$value" "+%s" 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$parsed" ]]; then
    date_part="$(printf "%s" "$value" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1 || true)"
    if [[ -n "$date_part" ]]; then
      if date -j -f "%Y-%m-%d" "$date_part" "+%s" >/dev/null 2>&1; then
        parsed="$(date -j -f "%Y-%m-%d" "$date_part" "+%s")"
      else
        parsed="$(date -d "$date_part" "+%s" 2>/dev/null || true)"
      fi
    fi
  fi

  if [[ "$parsed" =~ ^[0-9]+$ ]]; then
    printf "%s" "$parsed"
  else
    printf "0"
  fi
}

file_effective_epoch() {
  local file_path="$1"
  local last_updated
  local parsed_epoch

  last_updated="$(extract_field_value "$file_path" "last_updated")"
  if [[ -n "$last_updated" ]]; then
    parsed_epoch="$(parse_iso_date_epoch "$last_updated")"
    if (( parsed_epoch > 0 )); then
      printf "%s" "$parsed_epoch"
      return
    fi
  fi

  file_mtime_epoch "$file_path"
}

file_newest_change_epoch() {
  local file_path="$1"
  local last_updated
  local parsed_epoch=0
  local mtime_epoch

  last_updated="$(extract_field_value "$file_path" "last_updated")"
  if [[ -n "$last_updated" ]]; then
    parsed_epoch="$(parse_iso_date_epoch "$last_updated")"
  fi

  mtime_epoch="$(file_mtime_epoch "$file_path")"
  if (( parsed_epoch > mtime_epoch )); then
    printf "%s" "$parsed_epoch"
  else
    printf "%s" "$mtime_epoch"
  fi
}

check_timestamp_field_valid_non_future() {
  local file_path="$1"
  local key="$2"
  local label="$3"
  local value
  local parsed_epoch
  local now_epoch

  value="$(extract_field_value "$file_path" "$key")"
  if [[ -z "$value" ]]; then
    fail "${key} is present but empty in ${label}: $file_path"
    return 1
  fi

  parsed_epoch="$(parse_iso_date_epoch "$value")"
  if (( parsed_epoch <= 0 )); then
    fail "${key} must be a valid ISO date in ${label}: ${value} (${file_path})"
    return 1
  fi

  now_epoch="$(date +%s)"
  if (( parsed_epoch > now_epoch )); then
    fail "${key} must not be in the future in ${label}: ${value} (${file_path})"
    return 1
  fi

  return 0
}

escape_ere_literal() {
  printf "%s" "$1" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g'
}

# Extract the value part of a "- key: value" line. Returns empty if key missing or value empty.
extract_field_value() {
  local file_path="$1"
  local key="$2"
  local raw
  raw="$(grep -E "^- ${key}:" "$file_path" 2>/dev/null | head -n 1 | sed "s/^- ${key}:[[:space:]]*//" || true)"
  # Trim whitespace
  printf "%s" "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Check that a field exists AND has a non-empty value
check_field_non_empty() {
  local file_path="$1"
  local key="$2"
  local label="$3"
  local value

  if ! grep -qE "^- ${key}:" "$file_path" 2>/dev/null; then
    fail "${key} is missing in ${label}: $file_path"
    return 1
  fi

  value="$(extract_field_value "$file_path" "$key")"
  if [[ -z "$value" ]]; then
    fail "${key} is present but empty in ${label}: $file_path"
    return 1
  fi
  return 0
}

check_any_field_non_empty() {
  local file_path="$1"
  local label="$2"
  shift 2
  local key
  local value
  local keys_text

  for key in "$@"; do
    value="$(extract_field_value "$file_path" "$key")"
    if [[ -n "$value" ]]; then
      return 0
    fi
  done

  keys_text="$(printf "%s|" "$@")"
  keys_text="${keys_text%|}"
  fail "one of ${keys_text} is required and non-empty in ${label}: $file_path"
  return 1
}

# Check field exists (key presence only, for backward compat in advisory mode)
check_field_exists() {
  local file_path="$1"
  local key="$2"
  local label="$3"

  if ! grep -qE "^- ${key}:" "$file_path" 2>/dev/null; then
    fail "${key} is missing in ${label}: $file_path"
    return 1
  fi
  return 0
}

check_field_value_equals() {
  local file_path="$1"
  local key="$2"
  local expected="$3"
  local label="$4"
  local value

  value="$(extract_field_value "$file_path" "$key")"
  if [[ -z "$value" ]]; then
    fail "${key} is missing in ${label}: $file_path"
    return 1
  fi

  if [[ "$value" != "$expected" ]]; then
    fail "invalid ${key} in ${label}: expected ${expected}, found ${value} (${file_path})"
    return 1
  fi
  return 0
}

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

# Freshness check using last_updated field first, then mtime fallback
check_freshness_days() {
  local file_path="$1"
  local max_days="$2"
  local label="$3"
  local age_days
  local last_updated

  if (( max_days == 0 )); then
    pass "${label} age-based freshness check disabled: $file_path"
    return 0
  fi

  last_updated="$(extract_field_value "$file_path" "last_updated")"
  if [[ -n "$last_updated" ]]; then
    # Parse ISO date from last_updated (supports YYYY-MM-DDTHH:MM:SSZ and YYYY-MM-DD)
    local lu_date
    lu_date="$(printf "%s" "$last_updated" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1 || true)"
    if [[ -n "$lu_date" ]]; then
      local lu_epoch now_epoch
      lu_epoch="$(parse_iso_date_epoch "$last_updated")"
      now_epoch="$(date +%s)"
      if (( lu_epoch > 0 )); then
        age_days=$(( (now_epoch - lu_epoch) / 86400 ))
        if (( age_days > max_days )); then
          fail "${label} is stale by last_updated (${age_days} days > ${max_days}): $file_path"
        else
          pass "${label} freshness OK by last_updated (${age_days} days): $file_path"
        fi
        return
      fi
    fi
  fi

  # Fallback to file mtime
  age_days="$(file_age_days "$file_path")"
  if (( age_days > max_days )); then
    fail "${label} is stale by mtime (${age_days} days > ${max_days}): $file_path"
  else
    pass "${label} freshness OK by mtime (${age_days} days): $file_path"
  fi
}

check_shadow_graph_tracks_doc_updates() {
  local newest_doc=""
  local newest_doc_epoch
  local shadow_file
  local shadow_epoch
  local candidate
  local candidate_epoch

  newest_doc_epoch="0"

  while IFS= read -r candidate; do
    candidate_epoch="$(file_effective_epoch "$candidate")"
    if (( candidate_epoch > newest_doc_epoch )); then
      newest_doc_epoch="$candidate_epoch"
      newest_doc="$candidate"
    fi
  done < <(
    find "$TASK_DIR" "$DECISIONS_DIR" -maxdepth 1 -type f \
      \( -name 'TASK-*.md' -o -name 'decision-*.md' \) \
      ! -name 'task-template.md' \
      ! -name 'decision-template.md' \
      ! -name 'task-index.md' \
      ! -name 'decision-index.md' \
      | sort
  )

  if [[ -z "$newest_doc" ]]; then
    pass "shadow graph is not older than tracked task/decision docs"
    return 0
  fi

  for shadow_file in "$@"; do
    [[ -f "$shadow_file" ]] || continue

    shadow_epoch="$(file_effective_epoch "$shadow_file")"
    if (( shadow_epoch < newest_doc_epoch )); then
      fail "shadow graph doc is older than tracked task/decision doc: ${shadow_file} < ${newest_doc}. Run doc_garden.sh and refresh the shadow graph"
    else
      pass "shadow graph doc is not older than tracked task/decision docs: ${shadow_file}"
    fi
  done
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

check_file_exists() {
  local file_path="$1"
  local label="$2"
  if [[ -f "$file_path" ]]; then
    pass "$label exists"
  else
    fail "$label is missing: $file_path"
  fi
}

check_dir_exists() {
  local dir_path="$1"
  local label="$2"
  if [[ -d "$dir_path" ]]; then
    pass "$label exists"
  else
    fail "$label is missing: $dir_path"
  fi
}

check_line_limit() {
  local file_path="$1"
  local max_lines="$2"
  local label="$3"
  local lines

  lines="$(wc -l < "$file_path" | tr -d ' ')"
  if (( lines > max_lines )); then
    fail "$label is too large (${lines} lines > ${max_lines}): $file_path"
  else
    pass "$label size OK (${lines}/${max_lines}): $file_path"
  fi
}

check_enum_membership() {
  local value="$1"
  local field_name="$2"
  local label="$3"
  shift 3
  local allowed_values=("$@")
  local candidate
  local allowed_text

  if [[ -z "$value" ]]; then
    return 0
  fi

  for candidate in "${allowed_values[@]}"; do
    if [[ "$value" == "$candidate" ]]; then
      return 0
    fi
  done

  allowed_text="$(printf "%s|" "${allowed_values[@]}")"
  allowed_text="${allowed_text%|}"
  fail "invalid ${field_name} value in ${label}: ${value} (allowed: ${allowed_text})"
  return 1
}

REPORT_FILE_TASK_ID=""
REPORT_FILE_PLAN_VERSION=""
REPORT_FILE_EVALUATOR=""
REPORT_FILE_ROUND=""
REPORT_FILE_PLAN_REF=""

parse_evaluator_report_filename() {
  local report_base="$1"

  REPORT_FILE_TASK_ID=""
  REPORT_FILE_PLAN_VERSION=""
  REPORT_FILE_EVALUATOR=""
  REPORT_FILE_ROUND=""
  REPORT_FILE_PLAN_REF=""

  if [[ "$report_base" =~ ^PLAN-([A-Za-z0-9._-]+)-(v[0-9]+\.[0-9]+)-review-([A-Za-z0-9._]+)(-[A-Za-z0-9._-]+)?-(r[0-9]{2})\.md$ ]]; then
    REPORT_FILE_TASK_ID="${BASH_REMATCH[1]}"
    REPORT_FILE_PLAN_VERSION="${BASH_REMATCH[2]}"
    REPORT_FILE_EVALUATOR="${BASH_REMATCH[3]}"
    REPORT_FILE_ROUND="${BASH_REMATCH[5]}"
    REPORT_FILE_PLAN_REF="PLAN-${REPORT_FILE_TASK_ID}-${REPORT_FILE_PLAN_VERSION}"
    return 0
  fi

  return 1
}

is_allowed_evaluator_slug() {
  local value="$1"
  case "$value" in
    antigravity|agy|claude|codex|gemini|human)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_placeholder_approval_value() {
  local value="$1"
  local normalized
  normalized="$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$normalized" in
    ""|not_required|pending_user_approval|awaiting_approval|none|null|n/a|na|tbd|todo)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

check_file_contains_pattern() {
  local file_path="$1"
  local pattern="$2"
  local pass_msg="$3"
  local fail_msg="$4"

  if grep -qE -- "$pattern" "$file_path" 2>/dev/null; then
    pass "$pass_msg"
  else
    fail "$fail_msg"
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

risk_level_requires_adversarial() {
  local value="$1"
  [[ "$value" == "high" || "$value" == "critical" ]]
}

normalize_risk_level_value() {
  local value="$1"
  if [[ "$value" == "low | medium | high | critical" ]]; then
    printf ""
    return
  fi
  printf "%s" "$value"
}

adversarial_requirement_source_for_task() {
  local task_id="$1"
  local task_file="$TASK_DIR/TASK-${task_id}.md"
  local task_risk_level
  local decision_file
  local linked_task
  local decision_status
  local decision_risk_level
  local decision_base

  if [[ -f "$task_file" ]]; then
    task_risk_level="$(normalize_risk_level_value "$(extract_field_value "$task_file" "risk_level")")"
    if risk_level_requires_adversarial "$task_risk_level"; then
      printf "task risk_level=%s" "$task_risk_level"
      return
    fi
  fi

  if [[ ! -d "$DECISIONS_DIR" ]]; then
    return
  fi

  while IFS= read -r decision_file; do
    linked_task="$(extract_field_value "$decision_file" "linked_task")"
    [[ "$linked_task" == "TASK-${task_id}" ]] || continue

    decision_status="$(extract_field_value "$decision_file" "status")"
    [[ "$decision_status" == "superseded" ]] && continue

    decision_risk_level="$(normalize_risk_level_value "$(extract_field_value "$decision_file" "risk_level")")"
    if risk_level_requires_adversarial "$decision_risk_level"; then
      decision_base="$(basename "$decision_file")"
      printf "%s risk_level=%s" "$decision_base" "$decision_risk_level"
      return
    fi
  done < <(find "$DECISIONS_DIR" -maxdepth 1 -type f -name 'decision-*.md' ! -name 'decision-template.md' ! -name 'decision-index.md' | sort)
}

check_orchestration_file_for_task() {
  local task_id="$1"
  local task_ref="$2"
  local orchestration_file
  local execution_mode
  local delegation_status
  local doc_task_id
  local primary_author_tool
  local review_mode
  local external_review_status
  local external_review_required_for
  local risk_preflight_status
  local risk_preflight_recorded_by
  local approval_required
  local approval_ref
  local approved_next_step
  local risk_preflight_recorded_by_normalized

  orchestration_file="$(codeguide_orchestration_file "$PROJECT_ROOT_ABS" "$task_id")"

  if [[ ! -f "$orchestration_file" ]]; then
    fail "missing orchestration file for active task ${task_ref}: expected ${orchestration_file}"
    return
  fi

  pass "orchestration file exists for active task ${task_ref}"
  check_line_limit "$orchestration_file" "$MAX_ORCHESTRATION_LINES" "orchestration document"

  if [[ "$MODE" == "strict" ]]; then
    check_field_non_empty "$orchestration_file" "task_id" "orchestration" || true
    check_field_non_empty "$orchestration_file" "execution_mode" "orchestration" || true
    check_field_exists "$orchestration_file" "primary_author_tool" "orchestration" || true
    check_field_exists "$orchestration_file" "review_mode" "orchestration" || true
    check_field_non_empty "$orchestration_file" "supervisor_agent" "orchestration" || true
    check_field_non_empty "$orchestration_file" "delegation_status" "orchestration" || true
    check_field_non_empty "$orchestration_file" "risk_preflight_status" "orchestration" || true
    check_field_non_empty "$orchestration_file" "risk_preflight_recorded_by" "orchestration" || true
    check_field_non_empty "$orchestration_file" "risk_preflight_summary" "orchestration" || true
    check_field_non_empty "$orchestration_file" "approval_required" "orchestration" || true
    check_field_non_empty "$orchestration_file" "approval_ref" "orchestration" || true
    check_field_non_empty "$orchestration_file" "approved_next_step" "orchestration" || true
    check_field_non_empty "$orchestration_file" "last_updated" "orchestration" || true
  else
    check_field_exists "$orchestration_file" "task_id" "orchestration" || true
    check_field_exists "$orchestration_file" "execution_mode" "orchestration" || true
    check_field_exists "$orchestration_file" "primary_author_tool" "orchestration" || true
    check_field_exists "$orchestration_file" "review_mode" "orchestration" || true
    check_field_exists "$orchestration_file" "supervisor_agent" "orchestration" || true
    check_field_exists "$orchestration_file" "delegation_status" "orchestration" || true
    check_field_exists "$orchestration_file" "risk_preflight_status" "orchestration" || true
    check_field_exists "$orchestration_file" "risk_preflight_recorded_by" "orchestration" || true
    check_field_exists "$orchestration_file" "risk_preflight_summary" "orchestration" || true
    check_field_exists "$orchestration_file" "approval_required" "orchestration" || true
    check_field_exists "$orchestration_file" "approval_ref" "orchestration" || true
    check_field_exists "$orchestration_file" "approved_next_step" "orchestration" || true
    check_field_exists "$orchestration_file" "last_updated" "orchestration" || true
  fi

  doc_task_id="$(extract_field_value "$orchestration_file" "task_id")"
  if [[ -n "$doc_task_id" && "$doc_task_id" != "$task_id" ]]; then
    fail "task_id mismatch in orchestration for ${task_ref}: ${doc_task_id} != ${task_id}"
  fi

  execution_mode="$(extract_field_value "$orchestration_file" "execution_mode")"
  primary_author_tool="$(extract_field_value "$orchestration_file" "primary_author_tool")"
  review_mode="$(extract_field_value "$orchestration_file" "review_mode")"
  external_review_status="$(extract_field_value "$orchestration_file" "external_review_status")"
  external_review_required_for="$(extract_field_value "$orchestration_file" "external_review_required_for")"
  delegation_status="$(extract_field_value "$orchestration_file" "delegation_status")"
  risk_preflight_status="$(extract_field_value "$orchestration_file" "risk_preflight_status")"
  risk_preflight_recorded_by="$(extract_field_value "$orchestration_file" "risk_preflight_recorded_by")"
  approval_required="$(extract_field_value "$orchestration_file" "approval_required")"
  approval_ref="$(extract_field_value "$orchestration_file" "approval_ref")"
  approved_next_step="$(extract_field_value "$orchestration_file" "approved_next_step")"
  check_enum_membership "$execution_mode" "orchestration.execution_mode" "$orchestration_file" supervisor_subagents solo || true
  check_enum_membership "$primary_author_tool" "orchestration.primary_author_tool" "$orchestration_file" antigravity agy claude codex human external-runner || true
  check_enum_membership "$review_mode" "orchestration.review_mode" "$orchestration_file" external_cli current_task_debate agy_subagents claude_subagents codex_subagents || true
  if [[ -n "$external_review_status" ]]; then
    check_enum_membership "$external_review_status" "orchestration.external_review_status" "$orchestration_file" not_requested requested running awaiting_response ingested blocked waived || true
  fi
  if [[ -n "$external_review_required_for" ]]; then
    check_enum_membership "$external_review_required_for" "orchestration.external_review_required_for" "$orchestration_file" plan_acceptance implementation_start commit close || true
  fi
  check_enum_membership "$delegation_status" "orchestration.delegation_status" "$orchestration_file" planned active completed blocked || true
  check_enum_membership "$risk_preflight_status" "orchestration.risk_preflight_status" "$orchestration_file" pass approved blocked approval_required || true
  check_enum_membership "$approval_required" "orchestration.approval_required" "$orchestration_file" true false || true

  risk_preflight_recorded_by_normalized="$(printf "%s" "$risk_preflight_recorded_by" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$risk_preflight_recorded_by_normalized" in
    antigravity|agy|claude|codex|gemini|external-runner|external-review-wrapper|external-cli*)
      fail "orchestration risk_preflight_recorded_by must identify the main-thread supervising lead architect, not evaluator/tool identity: ${orchestration_file}"
      ;;
  esac

  if [[ "$risk_preflight_status" == "approved" && "$approval_required" != "true" ]]; then
    fail "orchestration risk_preflight_status=approved requires approval_required=true: ${orchestration_file}"
  fi
  if [[ "$risk_preflight_status" == "approval_required" && "$approval_required" != "true" ]]; then
    fail "orchestration risk_preflight_status=approval_required requires approval_required=true: ${orchestration_file}"
  fi
  if [[ "$risk_preflight_status" == "pass" && "$approval_required" != "false" ]]; then
    fail "orchestration risk_preflight_status=pass requires approval_required=false: ${orchestration_file}"
  fi
  if [[ "$risk_preflight_status" == "blocked" && "$approval_required" != "false" ]]; then
    fail "orchestration risk_preflight_status=blocked requires approval_required=false: ${orchestration_file}"
  fi
  if [[ "$approval_required" == "true" && "$risk_preflight_status" != "approved" && "$risk_preflight_status" != "approval_required" ]]; then
    fail "orchestration approval_required=true requires risk_preflight_status=approved or approval_required: ${orchestration_file}"
  fi
  if [[ "$risk_preflight_status" == "approved" ]]; then
    if is_placeholder_approval_value "$approval_ref"; then
      fail "orchestration approved preflight requires a concrete approval_ref: ${orchestration_file}"
    fi
    if is_placeholder_approval_value "$approved_next_step"; then
      fail "orchestration approved preflight requires approved_next_step: ${orchestration_file}"
    fi
  fi
  if [[ "$review_mode" == "external_cli" && "$risk_preflight_status" != "approved" ]]; then
    fail "orchestration review_mode=external_cli requires risk_preflight_status=approved with concrete approval provenance: ${orchestration_file}"
  fi

  if [[ "$execution_mode" != "solo" || "$review_mode" == "external_cli" || "$review_mode" == "current_task_debate" || "$review_mode" == "agy_subagents" || "$review_mode" == "claude_subagents" || "$review_mode" == "codex_subagents" ]]; then
    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$orchestration_file" "primary_author_tool" "orchestration" || true
      check_field_non_empty "$orchestration_file" "review_mode" "orchestration" || true
    fi
    if [[ "$risk_preflight_status" == "blocked" || "$risk_preflight_status" == "approval_required" ]]; then
      fail "orchestration risk preflight must be pass or approved before delegated/external review: ${orchestration_file}"
    fi
  fi

  if [[ "$execution_mode" == "solo" ]]; then
    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$orchestration_file" "delegation_note" "orchestration" || true
    else
      check_field_exists "$orchestration_file" "delegation_note" "orchestration" || true
    fi
    return
  fi

  if [[ "$MODE" == "strict" ]]; then
    check_field_non_empty "$orchestration_file" "planner_agents" "orchestration" || true
    check_field_non_empty "$orchestration_file" "reviewer_agents" "orchestration" || true
    check_field_non_empty "$orchestration_file" "implementation_agents" "orchestration" || true
    check_field_non_empty "$orchestration_file" "validation_agents" "orchestration" || true
    check_field_non_empty "$orchestration_file" "owned_scopes" "orchestration" || true
  else
    check_field_exists "$orchestration_file" "planner_agents" "orchestration" || true
    check_field_exists "$orchestration_file" "reviewer_agents" "orchestration" || true
    check_field_exists "$orchestration_file" "implementation_agents" "orchestration" || true
    check_field_exists "$orchestration_file" "validation_agents" "orchestration" || true
    check_field_exists "$orchestration_file" "owned_scopes" "orchestration" || true
  fi
}

# ORCH semantic-contradiction checks (advisory warning tier -- gated by
# MODE != strict, the same "recommended" tier as the concurrent-session claim
# contract's owner/claimed_at/claim-directory fields, so it never promotes to
# a strict-mode failure). Flags internally self-contradictory ORCH capsules
# regardless of whether the owning task is currently "active": a capsule can
# drift into a contradictory state on a blocked/done task just as easily as
# an in_progress one, and the per-active-task checks above do not cover that.
check_orchestration_semantic_contradictions() {
  local orchestration_file="$1"
  local orch_ref="$2"
  local task_file="${3:-}"
  local execution_mode
  local delegation_status
  local external_review_status
  local required_review_routes
  local external_review_result_ref
  local task_status
  local agent_key
  local has_agent_field="false"

  if [[ "$MODE" == "strict" ]]; then
    return 0
  fi

  delegation_status="$(extract_field_value "$orchestration_file" "delegation_status")"

  execution_mode="$(extract_field_value "$orchestration_file" "execution_mode")"
  if [[ "$execution_mode" == "supervisor_subagents" ]]; then
    for agent_key in planner_agents reviewer_agents implementation_agents validation_agents; do
      if [[ -n "$(extract_field_value "$orchestration_file" "$agent_key")" ]]; then
        has_agent_field="true"
        break
      fi
    done
    if [[ "$has_agent_field" != "true" ]]; then
      fail "orchestration execution_mode=supervisor_subagents requires at least one non-empty agent field (planner_agents/reviewer_agents/implementation_agents/validation_agents) for ${orch_ref}: ${orchestration_file}"
    fi
    if [[ -z "$delegation_status" ]]; then
      fail "orchestration execution_mode=supervisor_subagents requires a non-empty delegation_status for ${orch_ref}: ${orchestration_file}"
    fi
  fi

  # Enum validation for every capsule (the per-active-task checks below only
  # reach capsules of active tasks, so a corrupted value on a planned-task
  # capsule would otherwise be invisible).
  if [[ -n "$delegation_status" ]]; then
    check_enum_membership "$delegation_status" "orchestration.delegation_status" "$orchestration_file" planned active completed blocked || true
  fi

  # Cross-artifact coherence: a capsule's delegation_status must not
  # contradict its task's ledger status (done tasks cannot still be
  # planned/active; blocked tasks cannot still be active).
  if [[ -n "$task_file" && -f "$task_file" ]]; then
    task_status="$(extract_field_value "$task_file" "status")"
    task_status="${task_status%% *}"
    if [[ "$task_status" == "done" && ( "$delegation_status" == "active" || "$delegation_status" == "planned" ) ]]; then
      fail "orchestration delegation_status '${delegation_status}' contradicts task status done for ${orch_ref}: ${orchestration_file}"
    fi
    if [[ "$task_status" == "blocked" && "$delegation_status" == "active" ]]; then
      fail "orchestration delegation_status 'active' contradicts task status blocked for ${orch_ref}: ${orchestration_file}"
    fi
  fi

  external_review_status="$(extract_field_value "$orchestration_file" "external_review_status")"
  if [[ "$external_review_status" == "ingested" ]]; then
    required_review_routes="$(extract_field_value "$orchestration_file" "required_review_routes")"
    external_review_result_ref="$(extract_field_value "$orchestration_file" "external_review_result_ref")"
    if [[ -z "$required_review_routes" ]]; then
      fail "orchestration external_review_status=ingested requires a non-empty required_review_routes for ${orch_ref}: ${orchestration_file}"
    fi
    if [[ -z "$external_review_result_ref" ]]; then
      fail "orchestration external_review_status=ingested requires a non-empty external_review_result_ref for ${orch_ref}: ${orchestration_file}"
    fi
  fi
}

# tmp/ path reference detection (advisory warning tier -- gated by
# MODE != strict, same rationale as check_orchestration_semantic_contradictions
# above): scans only durable, authored docs -- docs/task/*.md, docs/plan/*.md,
# and docs/orchestration/*/{INDEX.md,ORCH.md} -- for `codeguide/tmp/` or
# `/tmp/` path references. Deliberately does NOT touch docs/report/* or any
# external-cli *.response.md payload: external tool responses legitimately
# quote arbitrary filesystem paths that are not durable-doc references. Skips
# fenced code examples using the same fence-aware idiom as extract_shadow_field.
check_tmp_path_references() {
  local file_path
  local match_line_no

  while IFS= read -r file_path; do
    [[ -z "$file_path" ]] && continue
    while IFS= read -r match_line_no; do
      [[ -z "$match_line_no" ]] && continue
      fail "docs reference a gitignored tmp/ path (${file_path}:${match_line_no})"
    done < <(awk '
      /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
      infence { next }
      /codeguide\/tmp\// { print NR; next }
      /(^|[^A-Za-z0-9_.-])\/tmp\// { print NR }
    ' "$file_path" 2>/dev/null)
    # Dangling archive references: the no-archive policy deletes _archive
    # directories, so any surviving path reference into one is a broken link.
    while IFS= read -r match_line_no; do
      [[ -z "$match_line_no" ]] && continue
      fail "docs reference a deleted _archive path (${file_path}:${match_line_no})"
    done < <(awk '
      /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
      infence { next }
      /docs\/(plan|task|orchestration)\/_archive\// { print NR }
    ' "$file_path" 2>/dev/null)
  done < <(
    {
      find "$TASK_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null
      find "$PLAN_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null
      find "$ORCHESTRATION_DIR" -mindepth 2 -maxdepth 2 -type f \( -name 'INDEX.md' -o -name 'ORCH.md' \) 2>/dev/null
    } | sort
  )
}

orchestration_execution_mode_for_task() {
  local task_id="$1"
  local orchestration_file

  orchestration_file="$(codeguide_orchestration_file "$PROJECT_ROOT_ABS" "$task_id")"

  if [[ ! -f "$orchestration_file" ]]; then
    return
  fi

  extract_field_value "$orchestration_file" "execution_mode"
}

latest_plan_version_for_task() {
  local task_id="$1"
  local plan_file
  local plan_base
  local version
  local major
  local minor
  local best_major=-1
  local best_minor=-1
  local best_version=""

  while IFS= read -r plan_file; do
    plan_base="$(basename "$plan_file")"
    version="$(printf "%s" "$plan_base" | sed -E 's/^PLAN-.*-(v[0-9]+\.[0-9]+)\.md$/\1/')"
    [[ "$version" =~ ^v[0-9]+\.[0-9]+$ ]] || continue
    major="${version#v}"
    major="${major%%.*}"
    minor="${version##*.}"
    major=$((10#$major))
    minor=$((10#$minor))
    if (( major > best_major || (major == best_major && minor > best_minor) )); then
      best_major="$major"
      best_minor="$minor"
      best_version="$version"
    fi
  done < <(find "$PLAN_DIR" -maxdepth 1 -type f -name "PLAN-${task_id}-v*.md" ! -name 'PLAN-template.md' | sort)

  printf "%s" "$best_version"
}

check_evaluator_reports_for_task() {
  local task_id="$1"
  local task_ref="$2"
  local execution_mode="$3"
  local adversarial_source="${4:-}"
  local latest_plan_version="${5:-}"
  local report_count=0
  local adversarial_count=0
  local stale_report_count=0
  local report_file
  local report_review_style
  local expected_report_glob
  local report_base
  local report_task_id
  local report_plan_version
  local report_evaluator
  local report_round
  local file_report_task_id
  local file_evaluator
  local file_round
  local plan_file
  local report_epoch
  local plan_epoch

  if [[ -z "$latest_plan_version" ]]; then
    latest_plan_version="$(latest_plan_version_for_task "$task_id")"
  fi
  if [[ -z "$latest_plan_version" ]]; then
    fail "cannot determine latest plan version for active task ${task_ref}"
    return
  fi

  expected_report_glob="$REPORT_DIR/PLAN-${task_id}-${latest_plan_version}-review-*.md"
  plan_file="$PLAN_DIR/PLAN-${task_id}-${latest_plan_version}.md"
  if compgen -G "$expected_report_glob" >/dev/null; then
    while IFS= read -r report_file; do
      report_base="$(basename "$report_file")"
      if ! parse_evaluator_report_filename "$report_base"; then
        fail "evaluator report identity mismatch for active task gate: ${report_base}"
        continue
      fi
      file_report_task_id="$REPORT_FILE_TASK_ID"
      file_evaluator="$REPORT_FILE_EVALUATOR"
      file_round="$REPORT_FILE_ROUND"
      report_task_id="$(extract_field_value "$report_file" "task_id")"
      report_plan_version="$(extract_field_value "$report_file" "plan_version")"
      report_evaluator="$(extract_field_value "$report_file" "evaluator")"
      report_round="$(extract_field_value "$report_file" "review_round")"

      if [[ "$file_report_task_id" != "$task_id" || "$report_task_id" != "$task_id" || "$report_plan_version" != "$latest_plan_version" || "$report_evaluator" != "$file_evaluator" || "$report_round" != "$file_round" ]]; then
        fail "evaluator report identity mismatch for active task gate: ${report_base}"
        continue
      fi

      if [[ -f "$plan_file" ]]; then
        report_epoch="$(file_effective_epoch "$report_file")"
        plan_epoch="$(file_effective_epoch "$plan_file")"
        if (( report_epoch < plan_epoch )); then
          stale_report_count=$((stale_report_count + 1))
          continue
        fi
      fi

      report_count=$((report_count + 1))
      report_review_style="$(extract_field_value "$report_file" "review_style")"
      if [[ "$report_review_style" == "adversarial" ]]; then
        adversarial_count=$((adversarial_count + 1))
      fi
    done < <(find "$REPORT_DIR" -maxdepth 1 -type f -name "PLAN-${task_id}-${latest_plan_version}-review-*.md" | sort)
  fi

  if [[ -n "$adversarial_source" ]]; then
    if (( adversarial_count > 0 )); then
      pass "adversarial evaluator report exists for high-risk task ${task_ref} latest plan ${latest_plan_version} (${adversarial_count})"
    else
      fail "missing adversarial evaluator report for high-risk task ${task_ref} latest plan ${latest_plan_version} (${adversarial_source}): expected ${REPORT_DIR}/PLAN-${task_id}-${latest_plan_version}-review-<runner>-<model-slug>-rNN.md with review_style: adversarial"
    fi
    return
  fi

  if [[ "$execution_mode" == "solo" ]]; then
    pass "evaluator reports optional for solo execution on ${task_ref}"
    return
  fi

  if (( report_count > 0 )); then
    pass "evaluator report exists for active task ${task_ref} latest plan ${latest_plan_version} (${report_count})"
  elif (( stale_report_count > 0 )); then
    fail "missing fresh evaluator report for active task ${task_ref} latest plan ${latest_plan_version}: ${stale_report_count} stale report(s) ignored"
  else
    fail "missing evaluator report for active task ${task_ref} latest plan ${latest_plan_version}: expected ${REPORT_DIR}/PLAN-${task_id}-${latest_plan_version}-review-<runner>-<model-slug>-rNN.md"
  fi
}

is_active_task_status() {
  local status="$1"
  case "$status" in
    in_progress|blocked|done) return 0 ;;
    *) return 1 ;;
  esac
}

# Maps a task-index.md "## <Section>" header to the task.status enum value
# shown under it (mirrors status_to_section in doc_garden.sh, inverted).
task_index_section_status() {
  case "$1" in
    "## Planned")     printf "planned" ;;
    "## In Progress") printf "in_progress" ;;
    "## Blocked")     printf "blocked" ;;
    "## Done")        printf "done" ;;
    *)                printf "" ;;
  esac
}

# Reverse-direction task-index check (the per-task loop already checks that
# every TASK-*.md has a row; this checks every row back against reality):
# every row must reference an existing task file, sit under the section
# matching that file's actual status, and appear only once in the index.
# This is the enforcement mechanism for keeping task-index.md trustworthy
# without physically archiving/moving TASK-*.md files.
check_task_index_integrity() {
  local index_file="$1"
  local all_refs_file
  local section=""
  local expected_status
  local task_ref
  local task_file
  local file_status
  local file_status_primary
  local dup_ref

  all_refs_file="$(mktemp)"

  while IFS= read -r line; do
    if [[ "$line" =~ ^\#\#\  ]]; then
      section="$line"
      continue
    fi
    if [[ "$line" =~ ^-\ (TASK-[A-Za-z0-9._-]+) ]]; then
      task_ref="${BASH_REMATCH[1]}"
      printf "%s\n" "$task_ref" >> "$all_refs_file"
      task_file="$TASK_DIR/${task_ref}.md"

      if [[ ! -f "$task_file" ]]; then
        fail "task-index row for ${task_ref} has no matching task file: expected ${task_file}"
        continue
      fi

      expected_status="$(task_index_section_status "$section")"
      if [[ -n "$expected_status" ]]; then
        file_status="$(extract_field_value "$task_file" "status")"
        # Compare only the first token: some task files append a trailing
        # parenthetical note after the enum value (e.g. "done (Phase 1 r02...)").
        file_status_primary="${file_status%% *}"
        if [[ -n "$file_status_primary" && "$file_status_primary" != "$expected_status" ]]; then
          fail "task-index section mismatch for ${task_ref}: task file status is ${file_status} but row is listed under ${section#"## "}"
        fi
      fi
    fi
  done < "$index_file"

  if [[ -s "$all_refs_file" ]]; then
    while IFS= read -r dup_ref; do
      [[ -n "$dup_ref" ]] && fail "task-index has duplicate rows for ${dup_ref}"
    done < <(sort "$all_refs_file" | uniq -d)
  fi

  rm -f "$all_refs_file"
}

# Runtime issue tracker (docs/issues/current <-> docs/issues/resolved) consistency.
# This tracker is the one docs series that DOES physically move files as part of
# its normal lifecycle (unlike task/plan/orchestration, which stay flat and rely
# on check_task_index_integrity instead), because closing an issue creates a new
# RESOLUTION doc at the same moment, making the move a natural lifecycle event.
check_issue_tracker_integrity() {
  local issue_file
  local issue_base
  local issue_id
  local issue_status
  local resolved_at
  local resolution_doc_field
  local expected_resolution_base
  local resolution_file
  local resolution_base
  local expected_issue_base
  local all_ids_file
  local dup_id

  all_ids_file="$(mktemp)"

  if [[ -d "$ISSUE_TRACKER_CURRENT_DIR" ]]; then
    while IFS= read -r issue_file; do
      issue_base="$(basename "$issue_file")"
      issue_id="${issue_base%.md}"
      printf "%s\n" "$issue_base" >> "$all_ids_file"
      issue_status="$(extract_field_value "$issue_file" "status")"

      check_enum_membership "$issue_status" "issue.status" "$issue_file" open investigating blocked fixed_pending_verify reopened || true
      if [[ "$issue_status" == "resolved" ]]; then
        fail "issue ${issue_base} is status: resolved but still lives in docs/issues/current/ (move it to docs/issues/resolved/ with a paired RESOLUTION doc)"
      fi

      if [[ -f "$ISSUE_TRACKER_CURRENT_DIR/README.md" ]] && ! grep -qE "\|[[:space:]]*${issue_id}(\.md)?[[:space:]]*\|" "$ISSUE_TRACKER_CURRENT_DIR/README.md" 2>/dev/null; then
        fail "docs/issues/current/README.md missing index row for ${issue_base}"
      fi
    done < <(find "$ISSUE_TRACKER_CURRENT_DIR" -maxdepth 1 -type f -name 'ISSUE-*.md' | sort)
  fi

  if [[ -d "$ISSUE_TRACKER_RESOLVED_DIR" ]]; then
    while IFS= read -r issue_file; do
      issue_base="$(basename "$issue_file")"
      issue_id="${issue_base%.md}"
      printf "%s\n" "$issue_base" >> "$all_ids_file"
      issue_status="$(extract_field_value "$issue_file" "status")"
      resolved_at="$(extract_field_value "$issue_file" "resolved_at")"
      resolution_doc_field="$(extract_field_value "$issue_file" "resolution_doc")"

      if [[ "$issue_status" != "resolved" ]]; then
        fail "issue ${issue_base} lives in docs/issues/resolved/ but status is '${issue_status}' (expected resolved)"
      fi
      if [[ -z "$resolved_at" ]]; then
        fail "resolved_at is missing in resolved issue ${issue_base}"
      fi
      if [[ -z "$resolution_doc_field" ]]; then
        fail "resolution_doc is missing in resolved issue ${issue_base}"
      fi

      expected_resolution_base="RESOLUTION-${issue_base#ISSUE-}"
      resolution_file="$ISSUE_TRACKER_RESOLVED_DIR/${expected_resolution_base}"
      if [[ ! -f "$resolution_file" ]]; then
        fail "resolved issue ${issue_base} has no paired resolution doc: expected ${resolution_file}"
      fi

      if [[ -f "$ISSUE_TRACKER_RESOLVED_DIR/README.md" ]] && ! grep -qE "\|[[:space:]]*${issue_id}(\.md)?[[:space:]]*\|" "$ISSUE_TRACKER_RESOLVED_DIR/README.md" 2>/dev/null; then
        fail "docs/issues/resolved/README.md missing index row for ${issue_base}"
      fi
    done < <(find "$ISSUE_TRACKER_RESOLVED_DIR" -maxdepth 1 -type f -name 'ISSUE-*.md' | sort)

    while IFS= read -r resolution_file; do
      resolution_base="$(basename "$resolution_file")"
      expected_issue_base="ISSUE-${resolution_base#RESOLUTION-}"
      if [[ ! -f "$ISSUE_TRACKER_RESOLVED_DIR/${expected_issue_base}" ]]; then
        fail "resolution doc ${resolution_base} has no paired issue file: expected ${ISSUE_TRACKER_RESOLVED_DIR}/${expected_issue_base}"
      fi
    done < <(find "$ISSUE_TRACKER_RESOLVED_DIR" -maxdepth 1 -type f -name 'RESOLUTION-*.md' | sort)
  fi

  if [[ -s "$all_ids_file" ]]; then
    while IFS= read -r dup_id; do
      [[ -n "$dup_id" ]] && fail "issue id ${dup_id} exists in both docs/issues/current/ and docs/issues/resolved/ (or is duplicated)"
    done < <(sort "$all_ids_file" | uniq -d)
  fi

  rm -f "$all_ids_file"
}

trim_value() {
  printf "%s" "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

is_registry_colon_route() {
  local route="$1"
  python3 - "$SCRIPT_DIR" "$route" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

script_dir = Path(sys.argv[1])
route = sys.argv[2]
sys.path.insert(0, str(script_dir))
from ai_model_registry import RegistryError, load_registry

try:
    registry = load_registry(script_dir.parent / "config" / "ai_model_registry.json")
except RegistryError:
    raise SystemExit(1)

if route not in registry["models"] or ":" not in route:
    raise SystemExit(1)
PY
}

route_slug_for_filename() {
  printf "%s" "$1" | sed 's/[^A-Za-z0-9._-]/-/g'
}

resolve_docs_ref_path() {
  local ref="$1"
  ref="${ref%/}"
  case "$ref" in
    /*) printf "%s" "$ref" ;;
    docs/*) printf "%s/%s" "$PROJECT_ROOT_ABS" "$ref" ;;
    *) printf "%s/%s" "$DOCS_DIR" "$ref" ;;
  esac
}

await_gate_route_has_accept_artifact() {
  local result_dir="$1"
  local route="$2"
  local slug
  local candidate
  local verdict

  slug="$(route_slug_for_filename "$route")"
  for candidate in "$result_dir/${slug}.response.md" "$result_dir/${slug}.retry-response.md"; do
    if [[ ! -f "$candidate" ]]; then
      continue
    fi
    verdict="$(extract_field_value "$candidate" "verdict")"
    if [[ "$verdict" == "accept" ]]; then
      return 0
    fi
  done

  return 1
}

parse_required_review_routes_for_await_gate() {
  local raw_routes="$1"
  local route
  local normalized
  local seen_routes="|"
  local parsed_count=0

  AWAIT_GATE_ROUTES=()
  if is_placeholder_approval_value "$raw_routes"; then
    fail "external review await gate requires non-empty required_review_routes"
    return 1
  fi

  IFS=',' read -r -a AWAIT_GATE_RAW_ROUTES <<< "$raw_routes"
  for route in "${AWAIT_GATE_RAW_ROUTES[@]}"; do
    normalized="$(trim_value "$route")"
    if [[ -z "$normalized" ]]; then
      fail "external review await gate required_review_routes contains an empty route member"
      return 1
    fi
    if [[ "$seen_routes" == *"|${normalized}|"* ]]; then
      fail "external review await gate required_review_routes contains duplicate route: ${normalized}"
      return 1
    fi
    if ! is_registry_colon_route "$normalized"; then
      fail "external review await gate required_review_routes must use registered colon route: ${normalized}"
      return 1
    fi
    seen_routes="${seen_routes}${normalized}|"
    AWAIT_GATE_ROUTES+=("$normalized")
    parsed_count=$((parsed_count + 1))
  done

  if (( parsed_count == 0 )); then
    fail "external review await gate requires non-empty required_review_routes"
    return 1
  fi
  return 0
}

check_ingested_external_review_await_gate() {
  local task_id="$1"
  local consumes_plan_ref="$2"
  local consumed_plan_version="$3"
  local orchestration_file="$4"
  local required_review_routes
  local review_round
  local result_ref
  local result_dir
  local result_dir_physical
  local expected_dir
  local expected_dir_physical
  local route

  required_review_routes="$(extract_field_value "$orchestration_file" "required_review_routes")"
  if ! parse_required_review_routes_for_await_gate "$required_review_routes"; then
    return
  fi

  review_round="$(extract_field_value "$orchestration_file" "external_review_round")"
  if [[ ! "$review_round" =~ ^r[0-9][0-9]$ ]]; then
    fail "external review await gate requires external_review_round rNN for ${consumes_plan_ref}"
    return
  fi

  result_ref="$(extract_field_value "$orchestration_file" "external_review_result_ref")"
  if is_placeholder_approval_value "$result_ref"; then
    fail "external review await gate requires external_review_result_ref directory for ${consumes_plan_ref}"
    return
  fi

  result_dir="$(resolve_docs_ref_path "$result_ref")"
  if [[ ! -d "$result_dir" ]]; then
    fail "external review await gate result_ref directory missing or not a directory: ${result_ref}"
    return
  fi

  expected_dir="$(codeguide_external_cli_dir "$PROJECT_ROOT_ABS" "$task_id" "$consumed_plan_version" "$review_round")"
  result_dir_physical="$(cd "$result_dir" && pwd -P)"
  if [[ -d "$expected_dir" ]]; then
    expected_dir_physical="$(cd "$expected_dir" && pwd -P)"
  else
    expected_dir_physical="$expected_dir"
  fi
  if [[ "$result_dir_physical" != "$expected_dir_physical" ]]; then
    fail "external review await gate result_ref must match consumed plan version and round: ${result_ref} != ${expected_dir}"
    return
  fi

  for route in "${AWAIT_GATE_ROUTES[@]}"; do
    if ! await_gate_route_has_accept_artifact "$result_dir_physical" "$route"; then
      fail "external review await gate missing accepted route artifact for ${route} under ${result_ref}"
      return
    fi
  done

  pass "external review await gate satisfied for ${consumes_plan_ref}"
}

check_waived_external_review_await_gate() {
  local orchestration_file="$1"
  local waiver_ref
  local waiver_reason

  waiver_ref="$(extract_field_value "$orchestration_file" "external_review_waiver_ref")"
  waiver_reason="$(extract_field_value "$orchestration_file" "external_review_waiver_reason")"
  if is_placeholder_approval_value "$waiver_ref" || is_placeholder_approval_value "$waiver_reason"; then
    fail "external review await gate waiver requires concrete external_review_waiver_ref and external_review_waiver_reason"
    return
  fi

  pass "external review await gate waived with concrete provenance"
}

check_external_review_await_gate_for_task() {
  local task_id="$1"
  local task_ref="$2"
  local task_file="$3"
  local task_status="$4"
  local orchestration_file
  local required_for
  local consumes_plan_ref
  local consumed_plan_version
  local status

  [[ "$MODE" == "advisory" ]] || return 0
  [[ "$task_status" == "in_progress" || "$task_status" == "done" ]] || return 0

  orchestration_file="$(codeguide_orchestration_file "$PROJECT_ROOT_ABS" "$task_id")"
  [[ -f "$orchestration_file" ]] || return 0

  required_for="$(extract_field_value "$orchestration_file" "external_review_required_for")"
  [[ "$required_for" == "implementation_start" ]] || return 0

  consumes_plan_ref="$(extract_field_value "$task_file" "consumes_plan_ref")"
  if [[ "$consumes_plan_ref" != PLAN-"${task_id}"-v* ]]; then
    fail "external review await gate requires same-task consumes_plan_ref for ${task_ref}"
    return
  fi
  consumed_plan_version="${consumes_plan_ref#PLAN-${task_id}-}"
  if [[ ! "$consumed_plan_version" =~ ^v[0-9]+\.[0-9]+$ ]]; then
    fail "external review await gate requires same-task consumes_plan_ref for ${task_ref}"
    return
  fi
  if [[ ! -f "$PLAN_DIR/${consumes_plan_ref}.md" ]]; then
    fail "external review await gate consumes_plan_ref points to missing plan: ${consumes_plan_ref}"
    return
  fi

  status="$(extract_field_value "$orchestration_file" "external_review_status")"
  case "$status" in
    ingested)
      check_ingested_external_review_await_gate "$task_id" "$consumes_plan_ref" "$consumed_plan_version" "$orchestration_file"
      ;;
    waived)
      check_waived_external_review_await_gate "$orchestration_file"
      ;;
    "")
      fail "external review await gate requires external_review_status for ${task_ref}"
      ;;
    not_requested|requested|running|awaiting_response|blocked)
      fail "external review await gate not satisfied for ${task_ref}: external_review_status=${status}"
      ;;
    *)
      fail "external review await gate has invalid external_review_status for ${task_ref}: ${status}"
      ;;
  esac
  return 0
}

# --- Structure checks ---
check_dir_exists "$DOCS_DIR" "docs directory"
check_dir_exists "$TASK_DIR" "task directory"
check_dir_exists "$SHADOW_DIR" "shadow directory"
check_dir_exists "$DECISIONS_DIR" "decisions directory"
check_dir_exists "$PLAN_DIR" "plan directory"
check_dir_exists "$REPORT_DIR" "report directory"
check_dir_exists "$ORCHESTRATION_DIR" "orchestration directory"
check_dir_exists "$POLICY_DIR" "policy directory"

check_file_exists "$TASK_DIR/project-dictionary.md" "project dictionary"
check_file_exists "$TASK_DIR/task-index.md" "task index"
check_file_exists "$SHADOW_DIR/project-shadow.md" "shadow router"
check_file_exists "$SHADOW_GLOBAL_FILE" "shadow global"
for shadow_bucket in "${SHADOW_BUCKETS[@]}"; do
  check_file_exists "$SHADOW_DIR/${shadow_bucket}/_index.md" "shadow bucket index (${shadow_bucket})"
done
check_file_exists "$DECISIONS_DIR/decision-index.md" "decision index"
check_file_exists "$PLAN_DIR/PLAN-template.md" "plan template"
check_file_exists "$REPORT_DIR/LLM-REVIEW-template.md" "report template"
check_file_exists "$ORCHESTRATION_TEMPLATES_DIR/ORCH.md" "orchestration template"
check_file_exists "$ORCHESTRATION_TEMPLATES_DIR/prompt.md" "orchestration prompt template"

if [[ -d "$ORCHESTRATION_DIR" ]]; then
  while IFS= read -r legacy_orchestration_file; do
    fail "legacy root orchestration file is not supported; move it to docs/orchestration/<task-id>/ORCH.md: ${legacy_orchestration_file}"
  done < <(find "$ORCHESTRATION_DIR" -maxdepth 1 -type f -name 'ORCH-*.md' | sort)
  if [[ -d "$ORCHESTRATION_DIR/external-cli" ]]; then
    fail "legacy external CLI handoff root is not supported; use docs/orchestration/<task-id>/external-cli/<plan-version>/<round>"
  fi

  # Orphaned orchestration capsules: every orchestration directory (except
  # _templates) is expected to correspond to a real, indexed task. This is the
  # reverse direction of check_orchestration_file_for_task above (which only
  # runs per active task found by the task-file loop below), so it is the only
  # check that catches a capsule that was never registered as a task at all.
  # Same tier as an orphaned claim directory: always flags (strict-mode
  # failure, advisory-mode warning) since it only ever fires once a capsule
  # exists with no matching task, so it cannot break pre-existing corpora.
  while IFS= read -r orchestration_task_dir; do
    orchestration_task_id="$(basename "$orchestration_task_dir")"
    if [[ "$orchestration_task_id" == "_templates" ]]; then
      continue
    fi

    orchestration_capsule_task_file="$TASK_DIR/TASK-${orchestration_task_id}.md"
    if [[ ! -f "$orchestration_capsule_task_file" ]]; then
      fail "orphaned orchestration capsule with no matching task file: ${orchestration_task_dir} (expected ${orchestration_capsule_task_file})"
    fi
    if [[ -f "$TASK_DIR/task-index.md" ]] && ! grep -qE "^- TASK-${orchestration_task_id} " "$TASK_DIR/task-index.md" 2>/dev/null; then
      fail "orphaned orchestration capsule: task-index missing row for TASK-${orchestration_task_id} (capsule: ${orchestration_task_dir})"
    fi

    orchestration_capsule_orch_file="$orchestration_task_dir/ORCH.md"
    if [[ -f "$orchestration_capsule_orch_file" ]]; then
      check_orchestration_semantic_contradictions "$orchestration_capsule_orch_file" "TASK-${orchestration_task_id}" "$orchestration_capsule_task_file"
    fi
  done < <(find "$ORCHESTRATION_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
fi

# --- Physical-archive detection (no-archive policy) ---
# docs/task, docs/plan, and docs/orchestration must stay flat: task-index.md
# (and the equivalent status fields elsewhere) is the sole source of truth,
# per docs/DOC-GOVERNANCE.md's no-move-to-archive lifecycle policy. Same tier
# as an orphaned claim directory: always flags (strict-mode failure,
# advisory-mode warning).
for archive_dir_candidate in "$PLAN_DIR/_archive" "$TASK_DIR/_archive" "$ORCHESTRATION_DIR/_archive"; do
  if [[ -d "$archive_dir_candidate" ]]; then
    fail "physical archive directory violates the no-archive policy (docs stay flat; task-index.md is the sole source of truth): ${archive_dir_candidate}"
  fi
done

if [[ "$MODE" != "strict" ]]; then
  check_tmp_path_references
fi

# --- Shadow policy checks ---
if [[ -d "$POLICY_DIR" ]]; then
  check_shadow_policy_files
fi

# --- Shadow graph checks ---
SHADOW_TRACKED_FILES=()
if [[ -d "$SHADOW_DIR" ]]; then
  while IFS= read -r shadow_doc; do
    check_line_limit "$shadow_doc" "$MAX_SHADOW_LINES" "shadow document"
    if [[ "$(extract_field_value "$shadow_doc" "doc_role")" == "effect_map" ]]; then
      check_effect_map_file "$shadow_doc"
    fi
  done < <(
    find "$SHADOW_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
fi

if [[ -d "$DOCS_DIR" ]]; then
  while IFS= read -r review_queue_doc; do
    if [[ "$(extract_field_value "$review_queue_doc" "doc_role")" == "review_queue" ]]; then
      check_review_queue_file "$review_queue_doc"
    fi
  done < <(
    find "$DOCS_DIR" -type f -name '*.md' \
      ! -path "$SHADOW_DIR/_deprecated/*" \
      ! -path "$SHADOW_DIR/_obsolete/*" \
      | sort
  )
fi

if [[ -d "$SHADOW_DIR" ]]; then
  while IFS= read -r legacy_shadow_doc; do
    check_redirect_shim_file "$legacy_shadow_doc" "legacy shadow shim"
  done < <(
    find "$SHADOW_DIR" -maxdepth 1 -type f -name '*.md' \
      ! -name 'project-shadow.md' \
      ! -name '_global.md' \
      | sort
  )
fi

if [[ -f "$SHADOW_DIR/project-shadow.md" ]]; then
  SHADOW_TRACKED_FILES+=("$SHADOW_DIR/project-shadow.md")
  check_field_value_equals "$SHADOW_DIR/project-shadow.md" "doc_role" "router" "shadow router" || true
  check_field_exists "$SHADOW_DIR/project-shadow.md" "read_path" "shadow router" || true
  check_field_exists "$SHADOW_DIR/project-shadow.md" "bucket_links" "shadow router" || true
  check_field_exists "$SHADOW_DIR/project-shadow.md" "global_doc" "shadow router" || true
  check_field_exists "$SHADOW_DIR/project-shadow.md" "updated_by_task" "shadow router" || true
  check_field_exists "$SHADOW_DIR/project-shadow.md" "latest_change_note" "shadow router" || true
  if [[ "$MODE" == "strict" ]]; then
    check_timestamp_field_valid_non_future "$SHADOW_DIR/project-shadow.md" "last_updated" "shadow router" || true
  else
    check_field_exists "$SHADOW_DIR/project-shadow.md" "last_updated" "shadow router" || true
  fi
  check_freshness_days "$SHADOW_DIR/project-shadow.md" "$MAX_SHADOW_AGE_DAYS" "shadow router"
fi

if [[ -f "$SHADOW_GLOBAL_FILE" ]]; then
  SHADOW_TRACKED_FILES+=("$SHADOW_GLOBAL_FILE")
  check_field_value_equals "$SHADOW_GLOBAL_FILE" "doc_role" "global" "shadow global" || true
  if [[ "$MODE" == "strict" ]]; then
    check_timestamp_field_valid_non_future "$SHADOW_GLOBAL_FILE" "last_updated" "shadow global" || true
  else
    check_field_exists "$SHADOW_GLOBAL_FILE" "last_updated" "shadow global" || true
  fi
  check_freshness_days "$SHADOW_GLOBAL_FILE" "$MAX_SHADOW_AGE_DAYS" "shadow global"
fi

for shadow_bucket in "${SHADOW_BUCKETS[@]}"; do
  shadow_bucket_file="$SHADOW_DIR/${shadow_bucket}/_index.md"
  if [[ -f "$shadow_bucket_file" ]]; then
    SHADOW_TRACKED_FILES+=("$shadow_bucket_file")
    check_field_value_equals "$shadow_bucket_file" "doc_role" "bucket_index" "shadow bucket index (${shadow_bucket})" || true
    check_field_value_equals "$shadow_bucket_file" "bucket" "$shadow_bucket" "shadow bucket index (${shadow_bucket})" || true
    if [[ "$MODE" == "strict" ]]; then
      check_timestamp_field_valid_non_future "$shadow_bucket_file" "last_updated" "shadow bucket index (${shadow_bucket})" || true
    else
      check_field_exists "$shadow_bucket_file" "last_updated" "shadow bucket index (${shadow_bucket})" || true
    fi
    check_freshness_days "$shadow_bucket_file" "$MAX_SHADOW_AGE_DAYS" "shadow bucket index (${shadow_bucket})"
  fi
done

if [[ -d "$SHADOW_DIR" && ${#SHADOW_TRACKED_FILES[*]} -gt 0 ]]; then
  check_shadow_graph_tracks_doc_updates "${SHADOW_TRACKED_FILES[@]}"
fi

# Navigation link integrity is advisory-only (recommended tier): it warns on a
# rotting read path but is skipped in strict mode so existing shadow corpora with
# in-progress references are not blocked. Escalation to strict is a deliberate
# follow-up once corpora are known clean.
if [[ -d "$SHADOW_DIR" && "$MODE" != "strict" ]]; then
  check_shadow_navigation_links
  check_shadow_source_digest
  check_shadow_source_paths_exist
  check_shadow_unit_schema
fi

# --- Task file checks ---
if [[ -d "$TASK_DIR" ]]; then
  while IFS= read -r task_file; do
    task_base="$(basename "$task_file")"
    task_ref="${task_base%.md}"
    task_id="${task_ref#TASK-}"
    task_status="$(extract_field_value "$task_file" "status")"
    task_risk_level="$(normalize_risk_level_value "$(extract_field_value "$task_file" "risk_level")")"
    orchestration_mode=""
    adversarial_source=""
    latest_plan_version=""
    check_line_limit "$task_file" "$MAX_TASK_LINES" "task document"

    # In strict mode: check non-empty values; in advisory: check existence only
    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$task_file" "axis_why" "task file" || true
      check_field_non_empty "$task_file" "axis_where" "task file" || true
      check_field_non_empty "$task_file" "axis_verify" "task file" || true
      check_field_non_empty "$task_file" "title" "task file" || true
      check_field_non_empty "$task_file" "status" "task file" || true
    else
      check_field_exists "$task_file" "axis_why" "task file" || true
      check_field_exists "$task_file" "axis_where" "task file" || true
      check_field_exists "$task_file" "axis_verify" "task file" || true
      check_field_exists "$task_file" "status" "task file" || true
    fi

    check_enum_membership "$task_status" "task.status" "$task_file" planned in_progress blocked done || true
    check_enum_membership "$task_risk_level" "task.risk_level" "$task_file" low medium high critical || true

    # Freshness check for in_progress tasks
    if grep -qE "^- status:.*in_progress" "$task_file" 2>/dev/null; then
      check_freshness_days "$task_file" "$MAX_TASK_AGE_DAYS" "in-progress task"
    fi

    # Concurrent session claim contract: recommended (not required) so existing
    # task corpora predating this contract are not broken. See DOC-GOVERNANCE.md
    # "Concurrent session claim contract".
    task_status_primary="${task_status%% *}"
    if [[ "$task_status_primary" == "in_progress" ]]; then
      task_owner="$(extract_field_value "$task_file" "owner")"
      task_claimed_at="$(extract_field_value "$task_file" "claimed_at")"
      if [[ "$MODE" != "strict" && -z "$task_owner" ]]; then
        fail "owner is recommended for in_progress task ${task_ref}: set a session-identifying owner so concurrent sessions do not claim the same task"
      fi
      if [[ "$MODE" != "strict" && -z "$task_claimed_at" ]]; then
        fail "claimed_at is recommended for in_progress task ${task_ref}: record when the task was atomically claimed"
      fi
      if [[ "$MODE" != "strict" && ! -d "$TASK_CLAIMS_DIR/${task_id}" ]]; then
        fail "claim directory is recommended for in_progress task ${task_ref}: mkdir ${TASK_CLAIMS_DIR}/${task_id}/ atomically before setting status: in_progress so two concurrent sessions cannot claim the same task"
      fi
    fi

    # Active tasks must have at least one versioned plan file
    if is_active_task_status "$task_status"; then
      if [[ "$MODE" != "strict" && -z "$task_risk_level" ]]; then
        fail "risk_level is recommended for active task ${task_ref}: set low|medium|high|critical to improve review routing"
      fi
      if compgen -G "$PLAN_DIR/PLAN-${task_id}-v*.md" >/dev/null; then
        pass "plan exists for active task ${task_ref}"
        latest_plan_version="$(latest_plan_version_for_task "$task_id")"
      else
        fail "missing plan file for active task ${task_ref}: expected ${PLAN_DIR}/PLAN-${task_id}-v*.md"
      fi
      check_orchestration_file_for_task "$task_id" "$task_ref"
      check_external_review_await_gate_for_task "$task_id" "$task_ref" "$task_file" "$task_status"
      orchestration_mode="$(orchestration_execution_mode_for_task "$task_id")"
      adversarial_source="$(adversarial_requirement_source_for_task "$task_id")"
      check_evaluator_reports_for_task "$task_id" "$task_ref" "$orchestration_mode" "$adversarial_source" "$latest_plan_version"
    fi

    # Task-index consistency: verify task appears in task-index.md
    if [[ -f "$TASK_DIR/task-index.md" ]]; then
      if ! grep -qE "^- ${task_ref} " "$TASK_DIR/task-index.md" 2>/dev/null; then
        fail "task-index missing row for ${task_ref}"
      fi
    fi
  done < <(find "$TASK_DIR" -maxdepth 1 -type f -name 'TASK-*.md' | sort)

  if [[ -f "$TASK_DIR/task-index.md" ]]; then
    check_task_index_integrity "$TASK_DIR/task-index.md"
  fi

  # Orphaned/stale claim directories: unlike the recommended owner/claimed_at
  # fields above, this always fails because it only ever fires once a project
  # has adopted docs/task/.claims/, so it cannot break pre-existing corpora.
  if [[ -d "$TASK_CLAIMS_DIR" ]]; then
    while IFS= read -r claim_dir; do
      claim_task_id="$(basename "$claim_dir")"
      claim_task_file="$TASK_DIR/TASK-${claim_task_id}.md"
      if [[ ! -f "$claim_task_file" ]]; then
        fail "orphaned claim directory with no matching task file: ${claim_dir} (expected ${claim_task_file})"
        continue
      fi
      claim_task_status="$(extract_field_value "$claim_task_file" "status")"
      claim_task_status_primary="${claim_task_status%% *}"
      if [[ "$claim_task_status_primary" != "in_progress" ]]; then
        fail "stale claim directory for TASK-${claim_task_id} (status=${claim_task_status}): remove ${claim_dir} when releasing the task"
      fi
    done < <(find "$TASK_CLAIMS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  fi
fi

# --- Issue tracker checks (docs/issues/ is optional; only validated when present) ---
if [[ -d "$ISSUE_TRACKER_DIR" ]]; then
  check_issue_tracker_integrity
fi

# --- Decision file checks ---
if [[ -d "$DECISIONS_DIR" ]]; then
  while IFS= read -r decision_file; do
    decision_base="$(basename "$decision_file")"
    decision_base_escaped="$(escape_ere_literal "$decision_base")"
    decision_scope_type="$(extract_field_value "$decision_file" "scope_type")"
    decision_status="$(extract_field_value "$decision_file" "status")"
    decision_risk_level="$(normalize_risk_level_value "$(extract_field_value "$decision_file" "risk_level")")"
    check_line_limit "$decision_file" "$MAX_DECISION_LINES" "decision document"

    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$decision_file" "decision_id" "decision" || true
      check_field_non_empty "$decision_file" "scope_type" "decision" || true
      check_field_non_empty "$decision_file" "status" "decision" || true
      check_field_non_empty "$decision_file" "selected_option" "decision" || true
      check_field_non_empty "$decision_file" "axis_why" "decision" || true
      check_field_non_empty "$decision_file" "axis_what" "decision" || true
      check_field_non_empty "$decision_file" "axis_how" "decision" || true
      check_field_non_empty "$decision_file" "axis_where" "decision" || true
      check_field_non_empty "$decision_file" "axis_verify" "decision" || true
    else
      check_field_exists "$decision_file" "decision_id" "decision" || true
      check_field_exists "$decision_file" "scope_type" "decision" || true
      check_field_exists "$decision_file" "status" "decision" || true
      check_field_exists "$decision_file" "selected_option" "decision" || true
      check_field_exists "$decision_file" "axis_why" "decision" || true
      check_field_exists "$decision_file" "axis_what" "decision" || true
      check_field_exists "$decision_file" "axis_how" "decision" || true
      check_field_exists "$decision_file" "axis_where" "decision" || true
      check_field_exists "$decision_file" "axis_verify" "decision" || true
    fi

    check_enum_membership "$decision_scope_type" "decision.scope_type" "$decision_file" task hotfix pr release incident ops other || true
    check_enum_membership "$decision_status" "decision.status" "$decision_file" proposed accepted superseded || true
    check_enum_membership "$decision_risk_level" "decision.risk_level" "$decision_file" low medium high critical || true

    # Decision-index consistency (supports both section-based and legacy table format)
    if [[ -f "$DECISIONS_DIR/decision-index.md" ]]; then
      if ! grep -qE "(^- ${decision_base_escaped} \\||^\\| ${decision_base_escaped} \\|)" "$DECISIONS_DIR/decision-index.md" 2>/dev/null; then
        fail "decision index missing row for ${decision_base}"
      fi
    fi
  done < <(find "$DECISIONS_DIR" -maxdepth 1 -type f -name 'decision-*.md' ! -name 'decision-template.md' ! -name 'decision-index.md' | sort)
fi

# --- Plan file checks ---
if [[ -d "$PLAN_DIR" ]]; then
  while IFS= read -r plan_file; do
    plan_base="$(basename "$plan_file")"
    check_line_limit "$plan_file" "$MAX_PLAN_LINES" "plan document"

    if [[ ! "$plan_base" =~ ^PLAN-[A-Za-z0-9._-]+-v[0-9]+\.[0-9]+\.md$ ]]; then
      fail "invalid plan file name format: ${plan_base} (expected PLAN-<task-id>-v<major>.<minor>.md)"
    fi

    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$plan_file" "task_id" "plan" || true
      check_field_non_empty "$plan_file" "plan_version" "plan" || true
      check_field_non_empty "$plan_file" "objective" "plan" || true
      check_field_non_empty "$plan_file" "scope" "plan" || true
      check_field_non_empty "$plan_file" "last_updated" "plan" || true
    else
      check_field_exists "$plan_file" "task_id" "plan" || true
      check_field_exists "$plan_file" "plan_version" "plan" || true
      check_field_exists "$plan_file" "objective" "plan" || true
      check_field_exists "$plan_file" "scope" "plan" || true
      check_field_exists "$plan_file" "last_updated" "plan" || true
    fi

    file_plan_version="$(printf "%s" "$plan_base" | sed -E 's/^.*-(v[0-9]+\.[0-9]+)\.md$/\1/')"
    doc_plan_version="$(extract_field_value "$plan_file" "plan_version")"
    if [[ -n "$doc_plan_version" && "$doc_plan_version" != "$file_plan_version" ]]; then
      fail "plan_version mismatch between file name and field in ${plan_base}: ${file_plan_version} != ${doc_plan_version}"
    fi
    if [[ -n "$doc_plan_version" && ! "$doc_plan_version" =~ ^v[0-9]+\.[0-9]+$ ]]; then
      fail "invalid plan_version format in ${plan_base}: ${doc_plan_version} (expected v<major>.<minor>)"
    fi

    file_task_id="$(printf "%s" "$plan_base" | sed -E 's/^PLAN-(.*)-v[0-9]+\.[0-9]+\.md$/\1/')"
    doc_task_id="$(extract_field_value "$plan_file" "task_id")"
    if [[ -n "$doc_task_id" && "$doc_task_id" != "$file_task_id" ]]; then
      fail "task_id mismatch between file name and field in ${plan_base}: ${file_task_id} != ${doc_task_id}"
    fi
  done < <(find "$PLAN_DIR" -maxdepth 1 -type f -name 'PLAN-*.md' ! -name 'PLAN-template.md' | sort)
fi

# --- Evaluator report checks ---
if [[ -d "$REPORT_DIR" ]]; then
  while IFS= read -r report_file; do
    report_base="$(basename "$report_file")"
    report_review_style=""
    check_line_limit "$report_file" "$MAX_REPORT_LINES" "evaluator report"

    if parse_evaluator_report_filename "$report_base"; then
      file_report_task_id="$REPORT_FILE_TASK_ID"
      file_report_plan_version="$REPORT_FILE_PLAN_VERSION"
      file_evaluator="$REPORT_FILE_EVALUATOR"
      file_report_round="$REPORT_FILE_ROUND"
      file_plan_ref="$REPORT_FILE_PLAN_REF"
    else
      fail "invalid evaluator report file name format: ${report_base}"
      file_report_task_id=""
      file_report_plan_version=""
      file_evaluator=""
      file_report_round=""
      file_plan_ref=""
    fi
    if [[ -n "$file_evaluator" ]] && ! is_allowed_evaluator_slug "$file_evaluator"; then
      fail "invalid evaluator report file name format: ${report_base}"
    fi

    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$report_file" "task_id" "evaluator report" || true
      check_field_non_empty "$report_file" "plan_version" "evaluator report" || true
      check_field_non_empty "$report_file" "evaluator" "evaluator report" || true
      check_field_non_empty "$report_file" "review_round" "evaluator report" || true
      check_field_non_empty "$report_file" "verdict" "evaluator report" || true
      check_field_non_empty "$report_file" "summary" "evaluator report" || true
      check_field_non_empty "$report_file" "strengths" "evaluator report" || true
      check_field_non_empty "$report_file" "risks" "evaluator report" || true
      check_field_non_empty "$report_file" "requested_changes" "evaluator report" || true
      check_field_non_empty "$report_file" "last_updated" "evaluator report" || true
    else
      check_field_exists "$report_file" "task_id" "evaluator report" || true
      check_field_exists "$report_file" "plan_version" "evaluator report" || true
      check_field_exists "$report_file" "evaluator" "evaluator report" || true
      check_field_exists "$report_file" "review_round" "evaluator report" || true
      check_field_exists "$report_file" "verdict" "evaluator report" || true
      check_field_exists "$report_file" "summary" "evaluator report" || true
      check_field_exists "$report_file" "strengths" "evaluator report" || true
      check_field_exists "$report_file" "risks" "evaluator report" || true
      check_field_exists "$report_file" "requested_changes" "evaluator report" || true
      check_field_exists "$report_file" "last_updated" "evaluator report" || true
    fi

    report_evaluator="$(extract_field_value "$report_file" "evaluator")"
    if [[ -n "$report_evaluator" && ! "$report_evaluator" =~ ^[A-Za-z0-9._]+$ ]]; then
      fail "invalid evaluator in ${report_base}: ${report_evaluator} (expected runner slug)"
    elif [[ -n "$report_evaluator" ]] && ! is_allowed_evaluator_slug "$report_evaluator"; then
      fail "invalid evaluator in ${report_base}: ${report_evaluator} (expected registered runner slug)"
    fi

    report_review_style="$(extract_field_value "$report_file" "review_style")"
    if [[ -n "$report_review_style" && ! "$report_review_style" =~ ^(standard|adversarial)$ ]]; then
      fail "invalid review_style in ${report_base}: ${report_review_style} (expected standard|adversarial)"
    fi

    report_round="$(extract_field_value "$report_file" "review_round")"
    if [[ -n "$report_round" && ! "$report_round" =~ ^r[0-9]{2}$ ]]; then
      fail "invalid review_round in ${report_base}: ${report_round} (expected rNN)"
    fi

    report_verdict="$(extract_field_value "$report_file" "verdict")"
    if [[ -n "$report_verdict" && ! "$report_verdict" =~ ^(accept|revise|blocked)$ ]]; then
      fail "invalid verdict in ${report_base}: ${report_verdict} (expected accept|revise|blocked)"
    fi

    if [[ -n "$file_evaluator" && -n "$report_evaluator" && "$report_evaluator" != "$file_evaluator" ]]; then
      fail "evaluator mismatch between file name and field in ${report_base}: ${file_evaluator} != ${report_evaluator}"
    fi

    expected_plan_file="${PLAN_DIR}/${file_plan_ref}.md"
    if [[ -n "$file_plan_ref" && ! -f "$expected_plan_file" ]]; then
      fail "evaluator report references missing plan file: ${expected_plan_file}"
    fi

    report_task_id="$(extract_field_value "$report_file" "task_id")"
    if [[ -n "$file_report_task_id" && -n "$report_task_id" && "$report_task_id" != "$file_report_task_id" ]]; then
      fail "task_id mismatch between file name and field in ${report_base}: ${file_report_task_id} != ${report_task_id}"
    fi

    report_plan_version="$(extract_field_value "$report_file" "plan_version")"
    if [[ -n "$file_report_plan_version" && -n "$report_plan_version" && "$report_plan_version" != "$file_report_plan_version" ]]; then
      fail "plan_version mismatch between file name and field in ${report_base}: ${file_report_plan_version} != ${report_plan_version}"
    fi

    if [[ -n "$file_report_round" && -n "$report_round" && "$report_round" != "$file_report_round" ]]; then
      fail "review_round mismatch between file name and field in ${report_base}: ${file_report_round} != ${report_round}"
    fi

    if [[ "$report_review_style" == "adversarial" ]]; then
      if [[ "$MODE" == "strict" ]]; then
        check_field_non_empty "$report_file" "objection" "adversarial evaluator report" || true
        check_field_non_empty "$report_file" "counterproposal" "adversarial evaluator report" || true
        check_field_non_empty "$report_file" "rebuttal" "adversarial evaluator report" || true
        check_field_non_empty "$report_file" "residual_risk" "adversarial evaluator report" || true
      else
        check_field_exists "$report_file" "objection" "adversarial evaluator report" || true
        check_field_exists "$report_file" "counterproposal" "adversarial evaluator report" || true
        check_field_exists "$report_file" "rebuttal" "adversarial evaluator report" || true
        check_field_exists "$report_file" "residual_risk" "adversarial evaluator report" || true
      fi
    fi
  done < <(find "$REPORT_DIR" -maxdepth 1 -type f -name 'PLAN-*-review-*.md' ! -name 'LLM-REVIEW-template.md' | sort)
fi

# --- Secret scanning ---
TMP_SECRET_REPORT="$(mktemp)"
trap 'rm -f "$TMP_SECRET_REPORT"' EXIT

redact_secret_report() {
  perl -pe '
    s/sk-[A-Za-z0-9_-]{20,}/[REDACTED_SECRET]/g;
    s/ghp_[A-Za-z0-9]{20,}/[REDACTED_SECRET]/g;
    s/AKIA[0-9A-Z]{16}/[REDACTED_AWS_ACCESS_KEY]/g;
    s/AIza[0-9A-Za-z_-]{35}/[REDACTED_SECRET]/g;
    s/((?:api[_-]?key|token|password|secret|private[_-]?key)\s*[:=]\s*)(?:"[^"\n]{6,}"|'\''[^'\''\n]{6,}'\''|[^\s\n]{6,})/${1}[REDACTED_SECRET]/gi;
  ' "$1"
}

scan_secret_pattern() {
  local regex="$1"
  local fail_msg="$2"
  local pass_msg="$3"
  local insensitive="${4:-false}"
  local exclude_glob
  local -a rg_cmd

  rg_cmd=(rg -n)
  if [[ "$insensitive" == "true" ]]; then
    rg_cmd+=(-i)
  fi

  for exclude_glob in "${SECRET_SCAN_EXCLUDE_GLOBS[@]}"; do
    rg_cmd+=(--glob "!${exclude_glob}")
  done

  rg_cmd+=("$regex" "$DOCS_DIR")

  if "${rg_cmd[@]}" > "$TMP_SECRET_REPORT" 2>/dev/null; then
    fail "$fail_msg"
    redact_secret_report "$TMP_SECRET_REPORT" >&2
  else
    pass "$pass_msg"
  fi
}

if ! command -v rg >/dev/null 2>&1; then
  fail "ripgrep (rg) is required for secret scanning but was not found in PATH"
else
  scan_secret_pattern \
    "sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----" \
    "potential secret values detected in docs (known key formats)" \
    "no known key-format secret patterns found"

  scan_secret_pattern \
    "(api[_-]?key|token|password|secret|private[_-]?key)\\s*[:=]\\s*(\"[^\"]{6,}\"|'[^']{6,}')" \
    "potential quoted secret assignments detected in docs" \
    "no quoted secret assignment patterns found" \
    "true"

  # Matches key-name suffixes inside provider-specific env vars, e.g. FOO_API_KEY=known-format-value.
  scan_secret_pattern \
    "(api[_-]?key|token|password|secret|private[_-]?key)\\s*[:=]\\s*(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35})" \
    "potential yaml/env-style secret assignments detected in docs" \
    "no yaml/env-style secret assignment patterns found" \
    "true"
fi

# --- Result ---
if (( ISSUE_COUNT > 0 )); then
  if [[ "$MODE" == "strict" ]]; then
    echo "[RESULT] Docs validation failed with ${ISSUE_COUNT} issue(s)." >&2
    exit 1
  fi
  echo "[RESULT] Docs validation advisory completed with ${ISSUE_COUNT} warning(s)." >&2
  exit 0
fi

echo "[RESULT] Docs validation passed."
