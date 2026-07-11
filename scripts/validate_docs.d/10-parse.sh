#!/usr/bin/env bash
# validate_docs.d/10-parse.sh — Generic document inspection: field extraction, structural checks, date/epoch helpers, filename parsers, slugs.
# Sourced by validate_docs.sh after CLI/global setup; not executable alone.
# Split from validate_docs.sh (behavior-preserving; function bodies verbatim).

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
