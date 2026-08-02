#!/usr/bin/env bash

set -euo pipefail

# Output-format contract (--format text|json; default text):
#   text mode is frozen and byte-identical to historical behavior. In json mode
#   stdout carries exactly one JSON object and every diagnostic stays on stderr
#   (CLI errors route usage() to stderr in both modes; -h/--help keeps usage on
#   stdout); the exit code is identical in both modes. Each reported issue
#   carries a stable id equal to the name of the check FUNCTION that raised it
#   (bash FUNCNAME[1]) plus a caller field naming that function's own caller
#   (FUNCNAME[2]); issues raised from this file's top-level phase flow carry
#   "main" in either slot. Consumers discriminate rules by (id, caller,
#   message-prefix): helper-emitted issues carry the helper as id (e.g.
#   check_field_non_empty) and the invoking rule (or "main") as caller. Rule
#   ids ARE check-function names: renaming a check function is an ID break and
#   MUST be called out in the commit. See validate_docs.d/00-report.sh for the
#   record/serialization mechanics.

usage() {
  cat <<'EOF'
Usage:
  validate_docs.sh <project-root> [options]

Options:
  --mode <advisory|strict>   Validation mode (default: advisory)
  --format <text|json>        Output format (default: text; json => one JSON object on stdout)
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
  usage >&2
  exit 1
fi

PROJECT_ROOT="${1%/}"
shift

MODE="advisory"
VALIDATE_FORMAT="text"
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
    usage >&2
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
    --format)
      require_option_value "$1" "$#"
      VALIDATE_FORMAT="${2:-}"
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
      usage >&2
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

if [[ "$VALIDATE_FORMAT" != "text" && "$VALIDATE_FORMAT" != "json" ]]; then
  echo "[ERROR] Invalid format: $VALIDATE_FORMAT (use text or json)" >&2
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
PASS_COUNT=0
# json mode buffers one NUL-delimited record per issue here; text mode leaves it
# empty and never writes. The early trap covers the window until the secret-scan
# trap below takes over cleanup of both temp files.
VALIDATE_JSON_RECORD_FILE=""
if [[ "$VALIDATE_FORMAT" == "json" ]]; then
  VALIDATE_JSON_RECORD_FILE="$(mktemp)"
  trap 'rm -f "$VALIDATE_JSON_RECORD_FILE"' EXIT
fi

# Rule modules: themed function libraries split from this file (audit P1).
# Definition order is irrelevant — everything is sourced before the phase
# flow below runs. Each module is a pure function library.
for validate_docs_module in "$SCRIPT_DIR"/validate_docs.d/[0-9][0-9]-*.sh; do
  # shellcheck source=/dev/null
  source "$validate_docs_module"
done
unset validate_docs_module

for _required_cmd in python3 perl; do
  if ! command -v "$_required_cmd" >/dev/null 2>&1; then
    echo "[ERROR] ${_required_cmd} is required for documentation validation but was not found in PATH" >&2
    exit 1
  fi
done


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

check_shadow_empty_graph

# Navigation link integrity is advisory-only (recommended tier): it warns on a
# rotting read path but is skipped in strict mode so existing shadow corpora with
# in-progress references are not blocked. Escalation to strict is a deliberate
# follow-up once corpora are known clean.
if [[ -d "$SHADOW_DIR" && "$MODE" != "strict" ]]; then
  check_shadow_navigation_links
  check_shadow_source_digest
  check_shadow_source_paths_exist
  check_shadow_unit_schema
  check_shadow_linked_decisions
  check_shadow_router_task_link
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

    check_enum_membership "$task_status" "task.status" "$task_file" planned in_progress blocked done superseded cancelled || true
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

      check_resume_capsule_for_task "$task_file" "$task_ref"
    fi

    # Superseded/cancelled tasks closed without completing: the disposition
    # field must say why (successor task, staleness, overtaken by events) so
    # the ledger stays honest without fabricating done-style close-out evidence.
    if [[ "$task_status_primary" == "superseded" || "$task_status_primary" == "cancelled" ]]; then
      if [[ "$MODE" == "strict" ]]; then
        check_field_non_empty "$task_file" "disposition" "${task_status_primary} task" || true
      else
        check_field_exists "$task_file" "disposition" "${task_status_primary} task" || true
      fi
    fi

    # Active tasks must have at least one versioned plan file. Gating keys on
    # the primary status token (parenthetical notes tolerated, same as the
    # task-index section check); the full value still has to pass the enum
    # check above, so a noted status never slips past strict silently.
    if is_active_task_status "$task_status_primary"; then
      if [[ "$MODE" != "strict" && -z "$task_risk_level" ]]; then
        fail "risk_level is recommended for active task ${task_ref}: set low|medium|high|critical to improve review routing"
      fi
      if compgen -G "$PLAN_DIR/PLAN-${task_id}-v*.md" >/dev/null; then
        pass "plan exists for active task ${task_ref}"
        latest_plan_version="$(latest_plan_version_for_task "$task_id")"
      else
        fail "missing plan file for active task ${task_ref}: expected ${PLAN_DIR}/PLAN-${task_id}-v*.md"
      fi
      check_orchestration_file_for_task "$task_id" "$task_ref" "$task_status_primary"
      check_external_review_await_gate_for_task "$task_id" "$task_ref" "$task_file" "$task_status"
      orchestration_mode="$(orchestration_execution_mode_for_task "$task_id")"
      adversarial_source="$(adversarial_requirement_source_for_task "$task_id")"
      check_evaluator_reports_for_task "$task_id" "$task_ref" "$orchestration_mode" "$adversarial_source" "$latest_plan_version" "$task_status_primary"
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

    if [[ ! "$plan_base" =~ ^PLAN-[A-Za-z0-9._-]+-v[0-9]+\.[0-9]+\.md$ ]]; then
      fail "invalid plan file name format: ${plan_base} (expected PLAN-<task-id>-v<major>.<minor>.md)"
    fi

    # Plans of terminal-status tasks are immutable evidence: identity checks
    # (task_id, plan_version) still apply, but authorship-completeness fields
    # and the size cap gate active work only and are not applied retroactively
    # to schema generations that predate them.
    plan_task_status=""
    plan_file_task_id="$(printf "%s" "$plan_base" | sed -E 's/^PLAN-(.*)-v[0-9]+\.[0-9]+\.md$/\1/')"
    if [[ -f "$TASK_DIR/TASK-${plan_file_task_id}.md" ]]; then
      plan_task_status="$(extract_field_value "$TASK_DIR/TASK-${plan_file_task_id}.md" "status")"
      plan_task_status="${plan_task_status%% *}"
    fi

    if is_terminal_task_status "$plan_task_status"; then
      pass "plan size cap skipped for terminal task artifact (status=${plan_task_status}): ${plan_file}"
    else
      check_line_limit "$plan_file" "$MAX_PLAN_LINES" "plan document"
    fi

    if [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$plan_file" "task_id" "plan" || true
      check_field_non_empty "$plan_file" "plan_version" "plan" || true
    else
      check_field_exists "$plan_file" "task_id" "plan" || true
      check_field_exists "$plan_file" "plan_version" "plan" || true
    fi
    if is_terminal_task_status "$plan_task_status"; then
      pass "plan completeness fields skipped for terminal task artifact (status=${plan_task_status}): ${plan_file}"
    elif [[ "$MODE" == "strict" ]]; then
      check_field_non_empty "$plan_file" "objective" "plan" || true
      check_field_non_empty "$plan_file" "scope" "plan" || true
      check_field_non_empty "$plan_file" "last_updated" "plan" || true
    else
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
      # An adversarial reviewer who ACCEPTS has no objection to state: the
      # debate fields must exist but may stay empty on verdict accept.
      # residual_risk is required either way — even an accept must name what
      # it did not cover. Reviewer artifacts are immutable, so the rule adapts
      # to the coherent case rather than forcing post-hoc edits to reports.
      report_verdict="$(extract_field_value "$report_file" "verdict")"
      if [[ "$MODE" == "strict" && "$report_verdict" != "accept" ]]; then
        check_field_non_empty "$report_file" "objection" "adversarial evaluator report" || true
        check_field_non_empty "$report_file" "counterproposal" "adversarial evaluator report" || true
        check_field_non_empty "$report_file" "rebuttal" "adversarial evaluator report" || true
        check_field_non_empty "$report_file" "residual_risk" "adversarial evaluator report" || true
      elif [[ "$MODE" == "strict" ]]; then
        check_field_exists "$report_file" "objection" "adversarial evaluator report" || true
        check_field_exists "$report_file" "counterproposal" "adversarial evaluator report" || true
        check_field_exists "$report_file" "rebuttal" "adversarial evaluator report" || true
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
trap 'rm -f "$TMP_SECRET_REPORT" ${VALIDATE_JSON_RECORD_FILE:+"$VALIDATE_JSON_RECORD_FILE"}' EXIT

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
if [[ "$VALIDATE_FORMAT" == "json" ]]; then
  # json mode: emit exactly one JSON object on stdout (the [RESULT] line is
  # replaced by the "result" field) and keep the exit code identical to text
  # mode — strict + issues => 1, otherwise 0.
  emit_json_result
  if (( ISSUE_COUNT > 0 )) && [[ "$MODE" == "strict" ]]; then
    exit 1
  fi
  exit 0
fi

if (( ISSUE_COUNT > 0 )); then
  if [[ "$MODE" == "strict" ]]; then
    echo "[RESULT] Docs validation failed with ${ISSUE_COUNT} issue(s)." >&2
    exit 1
  fi
  echo "[RESULT] Docs validation advisory completed with ${ISSUE_COUNT} warning(s)." >&2
  exit 0
fi

echo "[RESULT] Docs validation passed."
