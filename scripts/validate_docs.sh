#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate_docs.sh <project-root> [options]

Options:
  --mode <advisory|strict>   Validation mode (default: advisory)
  --max-shadow-lines <n>      Maximum lines for workspace docs/shadow/project-shadow.md (default: 220)
  --max-task-lines <n>        Maximum lines per workspace docs/task/TASK-*.md (default: 220)
  --max-decision-lines <n>    Maximum lines per workspace docs/decisions/decision-*.md (default: 180)
  --max-plan-lines <n>        Maximum lines per workspace docs/plan/PLAN-*.md (default: 220)
  --max-report-lines <n>      Maximum lines per workspace docs/report/PLAN-*-review-*.md (default: 180)
  --max-shadow-age-days <n>   Max allowed age for project shadow (default: 7)
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
MAX_SHADOW_LINES=220
MAX_TASK_LINES=220
MAX_DECISION_LINES=180
MAX_PLAN_LINES=220
MAX_REPORT_LINES=180
MAX_ORCHESTRATION_LINES=180
MAX_SHADOW_AGE_DAYS=7
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
require_non_negative_integer "--max-shadow-age-days" "$MAX_SHADOW_AGE_DAYS"
require_non_negative_integer "--max-task-age-days" "$MAX_TASK_AGE_DAYS"

INPUT_ROOT_ABS="$(cd "$PROJECT_ROOT" && pwd)"
resolve_repo_root() {
  git -C "$INPUT_ROOT_ABS" rev-parse --show-toplevel 2>/dev/null || printf "%s" "$INPUT_ROOT_ABS"
}

PROJECT_ROOT_ABS="$(resolve_repo_root)"
WORKSPACE_ROOT="$(cd "$PROJECT_ROOT_ABS/.." && pwd)"
DOCS_DIR="$WORKSPACE_ROOT/docs"
TASK_DIR="$DOCS_DIR/task"
SHADOW_DIR="$DOCS_DIR/shadow"
DECISIONS_DIR="$DOCS_DIR/decisions"
PLAN_DIR="$DOCS_DIR/plan"
REPORT_DIR="$DOCS_DIR/report"
ORCHESTRATION_DIR="$DOCS_DIR/orchestration"

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

# Freshness check using last_updated field first, then mtime fallback
check_freshness_days() {
  local file_path="$1"
  local max_days="$2"
  local label="$3"
  local age_days
  local last_updated

  last_updated="$(extract_field_value "$file_path" "last_updated")"
  if [[ -n "$last_updated" ]]; then
    # Parse ISO date from last_updated (supports YYYY-MM-DDTHH:MM:SSZ and YYYY-MM-DD)
    local lu_date
    lu_date="$(printf "%s" "$last_updated" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1 || true)"
    if [[ -n "$lu_date" ]]; then
      local lu_epoch now_epoch
      # macOS date -j vs GNU date
      if date -j -f "%Y-%m-%d" "$lu_date" "+%s" >/dev/null 2>&1; then
        lu_epoch="$(date -j -f "%Y-%m-%d" "$lu_date" "+%s")"
      else
        lu_epoch="$(date -d "$lu_date" "+%s" 2>/dev/null || echo 0)"
      fi
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

check_shadow_tracks_doc_updates() {
  local shadow_file="$1"
  local newest_doc=""
  local newest_doc_epoch
  local shadow_epoch
  local candidate
  local candidate_epoch

  if [[ ! -f "$shadow_file" ]]; then
    return 0
  fi

  shadow_epoch="$(file_mtime_epoch "$shadow_file")"
  newest_doc_epoch="$shadow_epoch"

  while IFS= read -r candidate; do
    candidate_epoch="$(file_mtime_epoch "$candidate")"
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

  if [[ -n "$newest_doc" ]]; then
    fail "project shadow is older than tracked task/decision doc: ${newest_doc}. Run doc_garden.sh and refresh workspace docs/shadow/project-shadow.md"
  else
    pass "shadow map is not older than tracked task/decision docs"
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

  if [[ ! -f "$orchestration_file" ]]; then
    fail "missing orchestration file for active task ${task_ref}: expected ${orchestration_file}"
    return
  fi

  pass "orchestration file exists for active task ${task_ref}"
  check_line_limit "$orchestration_file" "$MAX_ORCHESTRATION_LINES" "orchestration document"

  if [[ "$MODE" == "strict" ]]; then
    check_field_non_empty "$orchestration_file" "task_id" "orchestration"
    check_field_non_empty "$orchestration_file" "execution_mode" "orchestration"
    check_field_non_empty "$orchestration_file" "supervisor_agent" "orchestration"
    check_field_non_empty "$orchestration_file" "delegation_status" "orchestration"
    check_field_non_empty "$orchestration_file" "last_updated" "orchestration"
  else
    check_field_exists "$orchestration_file" "task_id" "orchestration"
    check_field_exists "$orchestration_file" "execution_mode" "orchestration"
    check_field_exists "$orchestration_file" "supervisor_agent" "orchestration"
    check_field_exists "$orchestration_file" "delegation_status" "orchestration"
    check_field_exists "$orchestration_file" "last_updated" "orchestration"
  fi

  doc_task_id="$(extract_field_value "$orchestration_file" "task_id")"
  if [[ -n "$doc_task_id" && "$doc_task_id" != "$task_id" ]]; then
    fail "task_id mismatch in orchestration for ${task_ref}: ${doc_task_id} != ${task_id}"
  fi

  execution_mode="$(extract_field_value "$orchestration_file" "execution_mode")"
  delegation_status="$(extract_field_value "$orchestration_file" "delegation_status")"
  check_enum_membership "$execution_mode" "orchestration.execution_mode" "$orchestration_file" supervisor_subagents solo || true
  check_enum_membership "$delegation_status" "orchestration.delegation_status" "$orchestration_file" planned active completed blocked || true

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

check_evaluator_reports_for_task() {
  local task_id="$1"
  local task_ref="$2"
  local execution_mode="$3"
  local adversarial_source="${4:-}"
  local report_count=0
  local adversarial_count=0
  local report_file
  local report_review_style

  if compgen -G "$REPORT_DIR/PLAN-${task_id}-v*-review-*.md" >/dev/null; then
    while IFS= read -r report_file; do
      report_count=$((report_count + 1))
      report_review_style="$(extract_field_value "$report_file" "review_style")"
      if [[ "$report_review_style" == "adversarial" ]]; then
        adversarial_count=$((adversarial_count + 1))
      fi
    done < <(find "$REPORT_DIR" -maxdepth 1 -type f -name "PLAN-${task_id}-v*-review-*.md" | sort)
  fi

  if [[ -n "$adversarial_source" ]]; then
    if (( adversarial_count > 0 )); then
      pass "adversarial evaluator report exists for high-risk task ${task_ref} (${adversarial_count})"
    else
      fail "missing adversarial evaluator report for high-risk task ${task_ref} (${adversarial_source}): expected ${REPORT_DIR}/PLAN-${task_id}-v*-review-(gemini|claude|codex)-rNN.md with review_style: adversarial"
    fi
    return
  fi

  if [[ "$execution_mode" == "solo" ]]; then
    pass "evaluator reports optional for solo execution on ${task_ref}"
    return
  fi

  if (( report_count > 0 )); then
    pass "evaluator report exists for active task ${task_ref} (${report_count})"
  else
    fail "missing evaluator report for active task ${task_ref}: expected ${REPORT_DIR}/PLAN-${task_id}-v*-review-(gemini|claude|codex)-rNN.md"
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

check_file_exists "$TASK_DIR/project-dictionary.md" "project dictionary"
check_file_exists "$TASK_DIR/task-index.md" "task index"
check_file_exists "$SHADOW_DIR/project-shadow.md" "project shadow"
check_file_exists "$DECISIONS_DIR/decision-index.md" "decision index"
check_file_exists "$PLAN_DIR/PLAN-template.md" "plan template"
check_file_exists "$REPORT_DIR/LLM-REVIEW-template.md" "report template"
check_file_exists "$ORCHESTRATION_DIR/ORCH-template.md" "orchestration template"

# --- Shadow map checks ---
if [[ -f "$SHADOW_DIR/project-shadow.md" ]]; then
  check_line_limit "$SHADOW_DIR/project-shadow.md" "$MAX_SHADOW_LINES" "shadow map"
  check_freshness_days "$SHADOW_DIR/project-shadow.md" "$MAX_SHADOW_AGE_DAYS" "shadow map"
  check_shadow_tracks_doc_updates "$SHADOW_DIR/project-shadow.md"
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
      else
        fail "missing plan file for active task ${task_ref}: expected ${PLAN_DIR}/PLAN-${task_id}-v*.md"
      fi
      check_orchestration_file_for_task "$task_id" "$task_ref"
      orchestration_mode="$(orchestration_execution_mode_for_task "$task_id")"
      adversarial_source="$(adversarial_requirement_source_for_task "$task_id")"
      check_evaluator_reports_for_task "$task_id" "$task_ref" "$orchestration_mode" "$adversarial_source"
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
      if ! grep -qE "(^- ${decision_base} \\||^\\| ${decision_base} \\|)" "$DECISIONS_DIR/decision-index.md" 2>/dev/null; then
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
      check_field_non_empty "$report_file" "last_updated" "evaluator report"
    else
      check_field_exists "$report_file" "task_id" "evaluator report"
      check_field_exists "$report_file" "plan_version" "evaluator report"
      check_field_exists "$report_file" "evaluator" "evaluator report"
      check_field_exists "$report_file" "review_round" "evaluator report"
      check_field_exists "$report_file" "verdict" "evaluator report"
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

    file_report_plan_version="$(printf "%s" "$report_base" | sed -E 's/^.*-(v[0-9]+\.[0-9]+)-review-.*$/\1/')"
    report_plan_version="$(extract_field_value "$report_file" "plan_version")"
    if [[ -n "$report_plan_version" && "$report_plan_version" != "$file_report_plan_version" ]]; then
      fail "plan_version mismatch between file name and field in ${report_base}: ${file_report_plan_version} != ${report_plan_version}"
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
    cat "$TMP_SECRET_REPORT" >&2
  else
    pass "$pass_msg"
  fi
}

if ! command -v rg >/dev/null 2>&1; then
  fail "ripgrep (rg) is required for secret scanning but was not found in PATH"
else
  scan_secret_pattern \
    "sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----" \
    "potential secret values detected in docs (known key formats)" \
    "no known key-format secret patterns found"

  scan_secret_pattern \
    "(api[_-]?key|token|password|secret|private[_-]?key)\\s*[:=]\\s*(\"[^\"]{6,}\"|'[^']{6,}')" \
    "potential quoted secret assignments detected in docs" \
    "no quoted secret assignment patterns found" \
    "true"

  scan_secret_pattern \
    "(api[_-]?key|token|password|secret|private[_-]?key)\\s*[:=]\\s*(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})" \
    "potential yaml/env-style secret assignments detected in docs" \
    "no yaml/env-style secret assignment patterns found" \
    "true"

  scan_secret_pattern \
    "OPENAI_API_KEY\\s*[:=]\\s*(sk-[A-Za-z0-9]{20,}|\"sk-[A-Za-z0-9]{20,}\"|'sk-[A-Za-z0-9]{20,}')" \
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
