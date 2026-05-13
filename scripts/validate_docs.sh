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
  "**/ORCH-template.md"
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
SHADOW_DIR="$DOCS_DIR/shadow"
SHADOW_GLOBAL_FILE="$SHADOW_DIR/_global.md"
SHADOW_BUCKETS=(apps services packages infra data)
DECISIONS_DIR="$DOCS_DIR/decisions"
PLAN_DIR="$DOCS_DIR/plan"
REPORT_DIR="$DOCS_DIR/report"
ORCHESTRATION_DIR="$DOCS_DIR/orchestration"
POLICY_DIR="$DOCS_DIR/policy"

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

  check_field_value_equals "$file_path" "doc_role" "redirect_shim" "$label"
  check_field_exists "$file_path" "legacy_path" "$label"
  check_field_exists "$file_path" "canonical_path" "$label"
  check_field_exists "$file_path" "redirects_fact_scope" "$label"
  check_field_exists "$file_path" "deprecated_since" "$label"
  check_field_value_equals "$file_path" "status" "redirected" "$label"
  check_field_value_equals "$file_path" "edit_policy" "read_only" "$label"
  check_field_exists "$file_path" "replacement_reason" "$label"
  check_field_exists "$file_path" "last_updated" "$label"
}

check_effect_map_file() {
  local file_path="$1"
  local issue_output

  check_field_value_equals "$file_path" "doc_role" "effect_map" "shadow effect_map"
  issue_output="$(python3 - "$file_path" "$POLICY_DIR" "$PROJECT_ROOT_ABS" "$SCRIPT_DIR" <<'PY'
import hashlib
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
id_re = re.compile(r"^ {2,}([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+@v[0-9]+):\s*$")
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
            if fields.get("evidence_artifact_hash") and not sha_re.match(fields["evidence_artifact_hash"]):
                issues.append(f"record {open_id}: deterministic_runtime evidence_artifact_hash must be sha256")
            if fields.get("evidence_probe_result_hash") and not sha_re.match(fields["evidence_probe_result_hash"]):
                issues.append(f"record {open_id}: deterministic_runtime evidence_probe_result_hash must be sha256")
            check_rule(open_id, "deterministic_runtime", fields.get("evidence_rule_id", ""), fields.get("effect_type", ""), fields.get("evidence_ref", ""))
            if catalog_evidence_types.get(fields.get("evidence_ref")) != "runtime_trace":
                issues.append(f"record {open_id}: deterministic_runtime evidence_ref must reference runtime_trace")
            if fields.get("evidence_ref") not in implemented_validators:
                issues.append(f"record {open_id}: deterministic_runtime evidence_ref must be implemented")
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

  check_field_value_equals "$file_path" "doc_role" "review_queue" "shadow review_queue"
  check_field_non_empty "$file_path" "task_id" "shadow review_queue"
  check_field_value_equals "$file_path" "generated_by" "shadow_review_queue.py" "shadow review_queue"
  check_field_non_empty "$file_path" "generated_at" "shadow review_queue"
  check_field_non_empty "$file_path" "ttl_days" "shadow review_queue"
  check_field_value_equals "$file_path" "writes_shadow_docs" "false" "shadow review_queue"
  check_field_value_equals "$file_path" "auto_promotes_facts" "false" "shadow review_queue"

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

  check_field_non_empty "$catalog_file" "catalog_id" "shadow validator catalog"
  check_field_non_empty "$catalog_file" "catalog_version" "shadow validator catalog"
  check_field_non_empty "$catalog_file" "status" "shadow validator catalog"
  check_any_field_non_empty "$catalog_file" "shadow validator catalog" "linked_task" "template_linked_task"
  check_any_field_non_empty "$catalog_file" "shadow validator catalog" "linked_decision" "template_linked_decision"
  check_field_non_empty "$catalog_file" "purpose" "shadow validator catalog"
  check_field_non_empty "$catalog_file" "last_updated" "shadow validator catalog"

  check_field_non_empty "$regex_file" "registry_id" "shadow regex pattern registry"
  check_field_non_empty "$regex_file" "registry_version" "shadow regex pattern registry"
  check_field_non_empty "$regex_file" "status" "shadow regex pattern registry"
  check_any_field_non_empty "$regex_file" "shadow regex pattern registry" "linked_task" "template_linked_task"
  check_any_field_non_empty "$regex_file" "shadow regex pattern registry" "linked_decision" "template_linked_decision"
  check_field_non_empty "$regex_file" "purpose" "shadow regex pattern registry"
  check_field_non_empty "$regex_file" "last_updated" "shadow regex pattern registry"

  check_field_non_empty "$rule_file" "registry_id" "shadow rule registry"
  check_field_non_empty "$rule_file" "registry_version" "shadow rule registry"
  check_field_non_empty "$rule_file" "status" "shadow rule registry"
  check_any_field_non_empty "$rule_file" "shadow rule registry" "linked_task" "template_linked_task"
  check_any_field_non_empty "$rule_file" "shadow rule registry" "linked_decisions" "template_linked_decisions"
  check_field_non_empty "$rule_file" "purpose" "shadow rule registry"
  check_field_non_empty "$rule_file" "last_updated" "shadow rule registry"

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
  local orchestration_file="$ORCHESTRATION_DIR/ORCH-${task_id}.md"
  local execution_mode
  local delegation_status
  local doc_task_id
  local primary_author_tool
  local review_mode
  local risk_preflight_status
  local risk_preflight_recorded_by
  local approval_required
  local approval_ref
  local approved_next_step
  local risk_preflight_recorded_by_normalized

  if [[ ! -f "$orchestration_file" ]]; then
    fail "missing orchestration file for active task ${task_ref}: expected ${orchestration_file}"
    return
  fi

  pass "orchestration file exists for active task ${task_ref}"
  check_line_limit "$orchestration_file" "$MAX_ORCHESTRATION_LINES" "orchestration document"

  if [[ "$MODE" == "strict" ]]; then
    check_field_non_empty "$orchestration_file" "task_id" "orchestration"
    check_field_non_empty "$orchestration_file" "execution_mode" "orchestration"
    check_field_exists "$orchestration_file" "primary_author_tool" "orchestration"
    check_field_exists "$orchestration_file" "review_mode" "orchestration"
    check_field_non_empty "$orchestration_file" "supervisor_agent" "orchestration"
    check_field_non_empty "$orchestration_file" "delegation_status" "orchestration"
    check_field_non_empty "$orchestration_file" "risk_preflight_status" "orchestration"
    check_field_non_empty "$orchestration_file" "risk_preflight_recorded_by" "orchestration"
    check_field_non_empty "$orchestration_file" "risk_preflight_summary" "orchestration"
    check_field_non_empty "$orchestration_file" "approval_required" "orchestration"
    check_field_non_empty "$orchestration_file" "approval_ref" "orchestration"
    check_field_non_empty "$orchestration_file" "approved_next_step" "orchestration"
    check_field_non_empty "$orchestration_file" "last_updated" "orchestration"
  else
    check_field_exists "$orchestration_file" "task_id" "orchestration"
    check_field_exists "$orchestration_file" "execution_mode" "orchestration"
    check_field_exists "$orchestration_file" "primary_author_tool" "orchestration"
    check_field_exists "$orchestration_file" "review_mode" "orchestration"
    check_field_exists "$orchestration_file" "supervisor_agent" "orchestration"
    check_field_exists "$orchestration_file" "delegation_status" "orchestration"
    check_field_exists "$orchestration_file" "risk_preflight_status" "orchestration"
    check_field_exists "$orchestration_file" "risk_preflight_recorded_by" "orchestration"
    check_field_exists "$orchestration_file" "risk_preflight_summary" "orchestration"
    check_field_exists "$orchestration_file" "approval_required" "orchestration"
    check_field_exists "$orchestration_file" "approval_ref" "orchestration"
    check_field_exists "$orchestration_file" "approved_next_step" "orchestration"
    check_field_exists "$orchestration_file" "last_updated" "orchestration"
  fi

  doc_task_id="$(extract_field_value "$orchestration_file" "task_id")"
  if [[ -n "$doc_task_id" && "$doc_task_id" != "$task_id" ]]; then
    fail "task_id mismatch in orchestration for ${task_ref}: ${doc_task_id} != ${task_id}"
  fi

  execution_mode="$(extract_field_value "$orchestration_file" "execution_mode")"
  primary_author_tool="$(extract_field_value "$orchestration_file" "primary_author_tool")"
  review_mode="$(extract_field_value "$orchestration_file" "review_mode")"
  delegation_status="$(extract_field_value "$orchestration_file" "delegation_status")"
  risk_preflight_status="$(extract_field_value "$orchestration_file" "risk_preflight_status")"
  risk_preflight_recorded_by="$(extract_field_value "$orchestration_file" "risk_preflight_recorded_by")"
  approval_required="$(extract_field_value "$orchestration_file" "approval_required")"
  approval_ref="$(extract_field_value "$orchestration_file" "approval_ref")"
  approved_next_step="$(extract_field_value "$orchestration_file" "approved_next_step")"
  check_enum_membership "$execution_mode" "orchestration.execution_mode" "$orchestration_file" supervisor_subagents solo || true
  check_enum_membership "$primary_author_tool" "orchestration.primary_author_tool" "$orchestration_file" gemini claude codex || true
  check_enum_membership "$review_mode" "orchestration.review_mode" "$orchestration_file" external_cli codex_subagents || true
  check_enum_membership "$delegation_status" "orchestration.delegation_status" "$orchestration_file" planned active completed blocked || true
  check_enum_membership "$risk_preflight_status" "orchestration.risk_preflight_status" "$orchestration_file" pass approved blocked approval_required || true
  check_enum_membership "$approval_required" "orchestration.approval_required" "$orchestration_file" true false || true

  risk_preflight_recorded_by_normalized="$(printf "%s" "$risk_preflight_recorded_by" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$risk_preflight_recorded_by_normalized" in
    gemini|claude|codex|external-review-wrapper|external-cli*)
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

  if [[ "$execution_mode" != "solo" || "$review_mode" == "external_cli" || "$review_mode" == "codex_subagents" ]]; then
    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$orchestration_file" "primary_author_tool" "orchestration"
      check_field_non_empty "$orchestration_file" "review_mode" "orchestration"
    fi
    if [[ "$risk_preflight_status" == "blocked" || "$risk_preflight_status" == "approval_required" ]]; then
      fail "orchestration risk preflight must be pass or approved before delegated/external review: ${orchestration_file}"
    fi
  fi

  if [[ "$execution_mode" == "solo" ]]; then
    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$orchestration_file" "delegation_note" "orchestration"
    else
      check_field_exists "$orchestration_file" "delegation_note" "orchestration"
    fi
    return
  fi

  if [[ "$MODE" == "strict" ]]; then
    check_field_non_empty "$orchestration_file" "planner_agents" "orchestration"
    check_field_non_empty "$orchestration_file" "reviewer_agents" "orchestration"
    check_field_non_empty "$orchestration_file" "implementation_agents" "orchestration"
    check_field_non_empty "$orchestration_file" "validation_agents" "orchestration"
    check_field_non_empty "$orchestration_file" "owned_scopes" "orchestration"
  else
    check_field_exists "$orchestration_file" "planner_agents" "orchestration"
    check_field_exists "$orchestration_file" "reviewer_agents" "orchestration"
    check_field_exists "$orchestration_file" "implementation_agents" "orchestration"
    check_field_exists "$orchestration_file" "validation_agents" "orchestration"
    check_field_exists "$orchestration_file" "owned_scopes" "orchestration"
  fi
}

orchestration_execution_mode_for_task() {
  local task_id="$1"
  local orchestration_file="$ORCHESTRATION_DIR/ORCH-${task_id}.md"

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
      file_report_task_id="$(printf "%s" "$report_base" | sed -E 's/^PLAN-(.*)-v[0-9]+\.[0-9]+-review-[a-z]+-r[0-9]{2}\.md$/\1/')"
      file_evaluator="$(printf "%s" "$report_base" | sed -E 's/^.*-review-([a-z]+)-r[0-9]{2}\.md$/\1/')"
      file_round="$(printf "%s" "$report_base" | sed -E 's/^.*-review-[a-z]+-(r[0-9]{2})\.md$/\1/')"
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
      fail "missing adversarial evaluator report for high-risk task ${task_ref} latest plan ${latest_plan_version} (${adversarial_source}): expected ${REPORT_DIR}/PLAN-${task_id}-${latest_plan_version}-review-(gemini|claude|codex)-rNN.md with review_style: adversarial"
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
    fail "missing evaluator report for active task ${task_ref} latest plan ${latest_plan_version}: expected ${REPORT_DIR}/PLAN-${task_id}-${latest_plan_version}-review-(gemini|claude|codex)-rNN.md"
  fi
}

is_active_task_status() {
  local status="$1"
  case "$status" in
    in_progress|blocked|done) return 0 ;;
    *) return 1 ;;
  esac
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
check_file_exists "$ORCHESTRATION_DIR/ORCH-template.md" "orchestration template"

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
  check_field_value_equals "$SHADOW_DIR/project-shadow.md" "doc_role" "router" "shadow router"
  check_field_exists "$SHADOW_DIR/project-shadow.md" "read_path" "shadow router"
  check_field_exists "$SHADOW_DIR/project-shadow.md" "bucket_links" "shadow router"
  check_field_exists "$SHADOW_DIR/project-shadow.md" "global_doc" "shadow router"
  check_field_exists "$SHADOW_DIR/project-shadow.md" "updated_by_task" "shadow router"
  check_field_exists "$SHADOW_DIR/project-shadow.md" "latest_change_note" "shadow router"
  if [[ "$MODE" == "strict" ]]; then
    check_timestamp_field_valid_non_future "$SHADOW_DIR/project-shadow.md" "last_updated" "shadow router"
  else
    check_field_exists "$SHADOW_DIR/project-shadow.md" "last_updated" "shadow router"
  fi
  check_freshness_days "$SHADOW_DIR/project-shadow.md" "$MAX_SHADOW_AGE_DAYS" "shadow router"
fi

if [[ -f "$SHADOW_GLOBAL_FILE" ]]; then
  SHADOW_TRACKED_FILES+=("$SHADOW_GLOBAL_FILE")
  check_field_value_equals "$SHADOW_GLOBAL_FILE" "doc_role" "global" "shadow global"
  if [[ "$MODE" == "strict" ]]; then
    check_timestamp_field_valid_non_future "$SHADOW_GLOBAL_FILE" "last_updated" "shadow global"
  else
    check_field_exists "$SHADOW_GLOBAL_FILE" "last_updated" "shadow global"
  fi
  check_freshness_days "$SHADOW_GLOBAL_FILE" "$MAX_SHADOW_AGE_DAYS" "shadow global"
fi

for shadow_bucket in "${SHADOW_BUCKETS[@]}"; do
  shadow_bucket_file="$SHADOW_DIR/${shadow_bucket}/_index.md"
  if [[ -f "$shadow_bucket_file" ]]; then
    SHADOW_TRACKED_FILES+=("$shadow_bucket_file")
    check_field_value_equals "$shadow_bucket_file" "doc_role" "bucket_index" "shadow bucket index (${shadow_bucket})"
    check_field_value_equals "$shadow_bucket_file" "bucket" "$shadow_bucket" "shadow bucket index (${shadow_bucket})"
    if [[ "$MODE" == "strict" ]]; then
      check_timestamp_field_valid_non_future "$shadow_bucket_file" "last_updated" "shadow bucket index (${shadow_bucket})"
    else
      check_field_exists "$shadow_bucket_file" "last_updated" "shadow bucket index (${shadow_bucket})"
    fi
    check_freshness_days "$shadow_bucket_file" "$MAX_SHADOW_AGE_DAYS" "shadow bucket index (${shadow_bucket})"
  fi
done

if [[ -d "$SHADOW_DIR" && ${#SHADOW_TRACKED_FILES[*]} -gt 0 ]]; then
  check_shadow_graph_tracks_doc_updates "${SHADOW_TRACKED_FILES[@]}"
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
      check_field_non_empty "$task_file" "axis_why" "task file"
      check_field_non_empty "$task_file" "axis_where" "task file"
      check_field_non_empty "$task_file" "axis_verify" "task file"
      check_field_non_empty "$task_file" "title" "task file"
      check_field_non_empty "$task_file" "status" "task file"
    else
      check_field_exists "$task_file" "axis_why" "task file"
      check_field_exists "$task_file" "axis_where" "task file"
      check_field_exists "$task_file" "axis_verify" "task file"
      check_field_exists "$task_file" "status" "task file"
    fi

    check_enum_membership "$task_status" "task.status" "$task_file" planned in_progress blocked done || true
    check_enum_membership "$task_risk_level" "task.risk_level" "$task_file" low medium high critical || true

    # Freshness check for in_progress tasks
    if grep -qE "^- status:.*in_progress" "$task_file" 2>/dev/null; then
      check_freshness_days "$task_file" "$MAX_TASK_AGE_DAYS" "in-progress task"
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
      check_field_non_empty "$decision_file" "decision_id" "decision"
      check_field_non_empty "$decision_file" "scope_type" "decision"
      check_field_non_empty "$decision_file" "status" "decision"
      check_field_non_empty "$decision_file" "selected_option" "decision"
      check_field_non_empty "$decision_file" "axis_why" "decision"
      check_field_non_empty "$decision_file" "axis_what" "decision"
      check_field_non_empty "$decision_file" "axis_how" "decision"
      check_field_non_empty "$decision_file" "axis_where" "decision"
      check_field_non_empty "$decision_file" "axis_verify" "decision"
    else
      check_field_exists "$decision_file" "decision_id" "decision"
      check_field_exists "$decision_file" "scope_type" "decision"
      check_field_exists "$decision_file" "status" "decision"
      check_field_exists "$decision_file" "selected_option" "decision"
      check_field_exists "$decision_file" "axis_why" "decision"
      check_field_exists "$decision_file" "axis_what" "decision"
      check_field_exists "$decision_file" "axis_how" "decision"
      check_field_exists "$decision_file" "axis_where" "decision"
      check_field_exists "$decision_file" "axis_verify" "decision"
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
      check_field_non_empty "$plan_file" "task_id" "plan"
      check_field_non_empty "$plan_file" "plan_version" "plan"
      check_field_non_empty "$plan_file" "objective" "plan"
      check_field_non_empty "$plan_file" "scope" "plan"
      check_field_non_empty "$plan_file" "last_updated" "plan"
    else
      check_field_exists "$plan_file" "task_id" "plan"
      check_field_exists "$plan_file" "plan_version" "plan"
      check_field_exists "$plan_file" "objective" "plan"
      check_field_exists "$plan_file" "scope" "plan"
      check_field_exists "$plan_file" "last_updated" "plan"
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

    if [[ ! "$report_base" =~ ^PLAN-[A-Za-z0-9._-]+-v[0-9]+\.[0-9]+-review-(gemini|claude|codex)-r[0-9]{2}\.md$ ]]; then
      fail "invalid evaluator report file name format: ${report_base}"
    fi

    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$report_file" "task_id" "evaluator report"
      check_field_non_empty "$report_file" "plan_version" "evaluator report"
      check_field_non_empty "$report_file" "evaluator" "evaluator report"
      check_field_non_empty "$report_file" "review_round" "evaluator report"
      check_field_non_empty "$report_file" "verdict" "evaluator report"
      check_field_non_empty "$report_file" "summary" "evaluator report"
      check_field_non_empty "$report_file" "strengths" "evaluator report"
      check_field_non_empty "$report_file" "risks" "evaluator report"
      check_field_non_empty "$report_file" "requested_changes" "evaluator report"
      check_field_non_empty "$report_file" "last_updated" "evaluator report"
    else
      check_field_exists "$report_file" "task_id" "evaluator report"
      check_field_exists "$report_file" "plan_version" "evaluator report"
      check_field_exists "$report_file" "evaluator" "evaluator report"
      check_field_exists "$report_file" "review_round" "evaluator report"
      check_field_exists "$report_file" "verdict" "evaluator report"
      check_field_exists "$report_file" "summary" "evaluator report"
      check_field_exists "$report_file" "strengths" "evaluator report"
      check_field_exists "$report_file" "risks" "evaluator report"
      check_field_exists "$report_file" "requested_changes" "evaluator report"
      check_field_exists "$report_file" "last_updated" "evaluator report"
    fi

    report_evaluator="$(extract_field_value "$report_file" "evaluator")"
    if [[ -n "$report_evaluator" && ! "$report_evaluator" =~ ^(gemini|claude|codex)$ ]]; then
      fail "invalid evaluator in ${report_base}: ${report_evaluator} (expected gemini|claude|codex)"
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

    file_evaluator="$(printf "%s" "$report_base" | sed -E 's/^.*-review-([a-z]+)-r[0-9]{2}\.md$/\1/')"
    if [[ -n "$report_evaluator" && "$report_evaluator" != "$file_evaluator" ]]; then
      fail "evaluator mismatch between file name and field in ${report_base}: ${file_evaluator} != ${report_evaluator}"
    fi

    file_plan_ref="$(printf "%s" "$report_base" | sed -E 's/^(PLAN-.*)-review-[a-z]+-r[0-9]{2}\.md$/\1/')"
    expected_plan_file="${PLAN_DIR}/${file_plan_ref}.md"
    if [[ ! -f "$expected_plan_file" ]]; then
      fail "evaluator report references missing plan file: ${expected_plan_file}"
    fi

    file_report_task_id="$(printf "%s" "$report_base" | sed -E 's/^PLAN-(.*)-v[0-9]+\.[0-9]+-review-[a-z]+-r[0-9]{2}\.md$/\1/')"
    report_task_id="$(extract_field_value "$report_file" "task_id")"
    if [[ -n "$report_task_id" && "$report_task_id" != "$file_report_task_id" ]]; then
      fail "task_id mismatch between file name and field in ${report_base}: ${file_report_task_id} != ${report_task_id}"
    fi

    file_report_plan_version="$(printf "%s" "$report_base" | sed -E 's/^.*-(v[0-9]+\.[0-9]+)-review-.*$/\1/')"
    report_plan_version="$(extract_field_value "$report_file" "plan_version")"
    if [[ -n "$report_plan_version" && "$report_plan_version" != "$file_report_plan_version" ]]; then
      fail "plan_version mismatch between file name and field in ${report_base}: ${file_report_plan_version} != ${report_plan_version}"
    fi

    file_report_round="$(printf "%s" "$report_base" | sed -E 's/^.*-review-[a-z]+-(r[0-9]{2})\.md$/\1/')"
    if [[ -n "$report_round" && "$report_round" != "$file_report_round" ]]; then
      fail "review_round mismatch between file name and field in ${report_base}: ${file_report_round} != ${report_round}"
    fi

    if [[ "$report_review_style" == "adversarial" ]]; then
      if [[ "$MODE" == "strict" ]]; then
        check_field_non_empty "$report_file" "objection" "adversarial evaluator report"
        check_field_non_empty "$report_file" "counterproposal" "adversarial evaluator report"
        check_field_non_empty "$report_file" "rebuttal" "adversarial evaluator report"
        check_field_non_empty "$report_file" "residual_risk" "adversarial evaluator report"
      else
        check_field_exists "$report_file" "objection" "adversarial evaluator report"
        check_field_exists "$report_file" "counterproposal" "adversarial evaluator report"
        check_field_exists "$report_file" "rebuttal" "adversarial evaluator report"
        check_field_exists "$report_file" "residual_risk" "adversarial evaluator report"
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
    "sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----" \
    "potential secret values detected in docs (known key formats)" \
    "no known key-format secret patterns found"

  scan_secret_pattern \
    "(api[_-]?key|token|password|secret|private[_-]?key)\\s*[:=]\\s*(\"[^\"]{6,}\"|'[^']{6,}')" \
    "potential quoted secret assignments detected in docs" \
    "no quoted secret assignment patterns found" \
    "true"

  scan_secret_pattern \
    "(api[_-]?key|token|password|secret|private[_-]?key)\\s*[:=]\\s*(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})" \
    "potential yaml/env-style secret assignments detected in docs" \
    "no yaml/env-style secret assignment patterns found" \
    "true"

  scan_secret_pattern \
    "OPENAI_API_KEY\\s*[:=]\\s*(sk-[A-Za-z0-9_-]{20,}|\"sk-[A-Za-z0-9_-]{20,}\"|'sk-[A-Za-z0-9_-]{20,}')" \
    "potential OPENAI API key assignment detected in docs" \
    "no OPENAI API key assignment patterns found"
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
