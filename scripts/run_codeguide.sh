#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_codeguide.sh [project-root] [options]

Options:
  --mode <auto|advisory|strict>  Validation mode (default: auto)
  --task-id <id>                 Optional task id override
  --task-status <status>         Task status (planned|in_progress|blocked|done; default: in_progress)
  --decision-id <id>             Optional decision id override
  --scope-type <type>            Optional scope override (task|hotfix|pr|release|incident|ops|other)
  --task-title "<title>"         Optional task title
  --selected-option "<text>"     Optional selected option
  --shadow-note "<text>"         Optional shadow change note for sync/finalization
  --axis-why "<text>"            Optional Why axis
  --axis-what "<text>"           Optional What axis
  --axis-how "<text>"            Optional How axis
  --axis-where "<text>"          Optional Where axis
  --axis-verify "<text>"         Optional Verify axis
  --change-scope <scope>         docs-only|code-or-runtime (default: auto-detect)
  --runtime-test-cmd "<cmd>"     Runtime test command (code-or-runtime only)
  --runtime-lint-cmd "<cmd>"     Runtime lint command (code-or-runtime only)
  --runtime-e2e-cmd "<cmd>"      Runtime e2e command (code-or-runtime only)
  --runtime-allow-list "<file>"  Allowlist file for runtime commands (one pattern per line)
  -h, --help                     Show this message
EOF
}

PROJECT_ROOT="."
if [[ $# -gt 0 && "${1:-}" != -* ]]; then
  PROJECT_ROOT="${1%/}"
  shift
fi

MODE="auto"
TASK_ID=""
TASK_STATUS="in_progress"
DECISION_ID=""
SCOPE_TYPE=""
TASK_TITLE=""
SELECTED_OPTION=""
SHADOW_NOTE=""
AXIS_WHY=""
AXIS_WHAT=""
AXIS_HOW=""
AXIS_WHERE=""
AXIS_VERIFY=""
CHANGE_SCOPE=""
RUNTIME_TEST_CMD=""
RUNTIME_LINT_CMD=""
RUNTIME_E2E_CMD=""
RUNTIME_ALLOW_LIST=""

require_option_value() {
  local option_name="$1"
  local remaining_args="$2"
  if (( remaining_args < 2 )); then
    echo "[ERROR] Option ${option_name} requires a value" >&2
    usage
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
    --task-id)
      require_option_value "$1" "$#"
      TASK_ID="${2:-}"
      shift 2
      ;;
    --task-status)
      require_option_value "$1" "$#"
      TASK_STATUS="${2:-}"
      shift 2
      ;;
    --decision-id)
      require_option_value "$1" "$#"
      DECISION_ID="${2:-}"
      shift 2
      ;;
    --scope-type)
      require_option_value "$1" "$#"
      SCOPE_TYPE="${2:-}"
      shift 2
      ;;
    --task-title)
      require_option_value "$1" "$#"
      TASK_TITLE="${2:-}"
      shift 2
      ;;
    --selected-option)
      require_option_value "$1" "$#"
      SELECTED_OPTION="${2:-}"
      shift 2
      ;;
    --shadow-note)
      require_option_value "$1" "$#"
      SHADOW_NOTE="${2:-}"
      shift 2
      ;;
    --axis-why)
      require_option_value "$1" "$#"
      AXIS_WHY="${2:-}"
      shift 2
      ;;
    --axis-what)
      require_option_value "$1" "$#"
      AXIS_WHAT="${2:-}"
      shift 2
      ;;
    --axis-how)
      require_option_value "$1" "$#"
      AXIS_HOW="${2:-}"
      shift 2
      ;;
    --axis-where)
      require_option_value "$1" "$#"
      AXIS_WHERE="${2:-}"
      shift 2
      ;;
    --axis-verify)
      require_option_value "$1" "$#"
      AXIS_VERIFY="${2:-}"
      shift 2
      ;;
    --change-scope)
      require_option_value "$1" "$#"
      CHANGE_SCOPE="${2:-}"
      shift 2
      ;;
    --runtime-test-cmd)
      require_option_value "$1" "$#"
      RUNTIME_TEST_CMD="${2:-}"
      shift 2
      ;;
    --runtime-lint-cmd)
      require_option_value "$1" "$#"
      RUNTIME_LINT_CMD="${2:-}"
      shift 2
      ;;
    --runtime-e2e-cmd)
      require_option_value "$1" "$#"
      RUNTIME_E2E_CMD="${2:-}"
      shift 2
      ;;
    --runtime-allow-list)
      require_option_value "$1" "$#"
      RUNTIME_ALLOW_LIST="${2:-}"
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

if [[ "$MODE" != "auto" && "$MODE" != "advisory" && "$MODE" != "strict" ]]; then
  echo "[ERROR] Invalid mode: $MODE (use auto, advisory, or strict)" >&2
  exit 1
fi

if [[ -n "$CHANGE_SCOPE" && "$CHANGE_SCOPE" != "docs-only" && "$CHANGE_SCOPE" != "code-or-runtime" ]]; then
  echo "[ERROR] Invalid change-scope: $CHANGE_SCOPE (use docs-only or code-or-runtime)" >&2
  exit 1
fi

if [[ "$TASK_STATUS" != "planned" && "$TASK_STATUS" != "in_progress" && "$TASK_STATUS" != "blocked" && "$TASK_STATUS" != "done" ]]; then
  echo "[ERROR] Invalid task status: $TASK_STATUS (use planned, in_progress, blocked, or done)" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "[ERROR] Project root not found: $PROJECT_ROOT" >&2
  exit 1
fi

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_SCRIPT="$THIS_DIR/init_docs_scaffold.sh"
GARDEN_SCRIPT="$THIS_DIR/doc_garden.sh"
VALIDATE_SCRIPT="$THIS_DIR/validate_docs.sh"

slugify() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/--\+/-/g; s/^-//; s/-$//'
}

is_git_repo() {
  git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

current_branch() {
  if is_git_repo; then
    git -C "$PROJECT_ROOT" symbolic-ref --short HEAD 2>/dev/null || \
      git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true
  fi
}

latest_task_from_docs() {
  local task_dir="$PROJECT_ROOT/docs/task"
  local latest_file=""

  if [[ ! -d "$task_dir" ]]; then
    return
  fi

  if compgen -G "$task_dir/TASK-*.md" >/dev/null; then
    latest_file="$(ls -t "$task_dir"/TASK-*.md 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -n "$latest_file" ]]; then
    sed -n 's|.*/TASK-\(.*\)\.md$|\1|p' <<<"$latest_file"
  fi
}

count_non_git_active_tasks() {
  local task_dir="$PROJECT_ROOT/docs/task"
  local task_file
  local task_status
  local active_count=0

  if [[ ! -d "$task_dir" ]]; then
    printf "0"
    return
  fi

  while IFS= read -r task_file; do
    task_status="$(sed -n 's/^- status:[[:space:]]*//p' "$task_file" | head -n 1 | sed 's/[[:space:]]*$//')"
    case "$task_status" in
      in_progress|blocked) active_count=$((active_count + 1)) ;;
    esac
  done < <(find "$task_dir" -maxdepth 1 -type f -name 'TASK-*.md' | sort)

  printf "%s" "$active_count"
}

infer_scope_type() {
  local branch="$1"
  if [[ -n "$SCOPE_TYPE" ]]; then
    printf "%s" "$SCOPE_TYPE"
    return
  fi
  case "$branch" in
    hotfix/*) printf "hotfix" ;;
    release/*) printf "release" ;;
    incident/*) printf "incident" ;;
    pr/*) printf "pr" ;;
    ops/*) printf "ops" ;;
    *) printf "task" ;;
  esac
}

infer_task_id() {
  local branch="$1"
  local inferred=""

  # 1. Explicit --task-id (highest priority)
  if [[ -n "$TASK_ID" ]]; then
    printf "%s" "$TASK_ID"
    return
  fi

  # 2. Branch pattern: ABC-123 style
  inferred="$(printf "%s" "$branch" | grep -Eo '[A-Za-z]+-[0-9]+' | head -n 1 || true)"
  if [[ -n "$inferred" ]]; then
    printf "%s" "$(slugify "$inferred")"
    return
  fi

  # 3. Branch pattern: numeric id (e.g. feature/123-foo)
  inferred="$(printf "%s" "$branch" | sed -n 's|.*/\([0-9][0-9]*\).*|\1|p' | head -n 1)"
  if [[ -n "$inferred" ]]; then
    printf "%s" "$inferred"
    return
  fi

  # 4. Latest task file in docs/task/
  inferred="$(latest_task_from_docs)"
  if [[ -n "$inferred" ]]; then
    printf "%s" "$inferred"
    return
  fi

  # 5. Timestamp fallback
  date -u +"A%Y%m%d%H%M%S"
}

infer_decision_id() {
  local branch="$1"
  local task_id="$2"
  local raw

  if [[ -n "$DECISION_ID" ]]; then
    printf "%s" "$DECISION_ID"
    return
  fi

  raw="$(slugify "$branch")"
  if [[ -z "$raw" || "$raw" == "head" ]]; then
    raw="task-${task_id}"
  fi
  printf "auto-%s" "$raw"
}

resolve_validation_mode() {
  local scope="$1"
  if [[ "$MODE" == "advisory" || "$MODE" == "strict" ]]; then
    printf "%s" "$MODE"
    return
  fi
  if [[ "${CI:-}" == "true" ]]; then
    printf "strict"
    return
  fi
  case "$scope" in
    hotfix|release|incident) printf "strict" ;;
    *) printf "advisory" ;;
  esac
}

ensure_plan_and_report_docs() {
  local task_id="$1"
  local plan_dir="$PROJECT_ROOT/docs/plan"
  local report_dir="$PROJECT_ROOT/docs/report"
  local plan_file="$plan_dir/PLAN-${task_id}-v1.0.md"
  local now_utc

  mkdir -p "$plan_dir" "$report_dir"
  now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [[ ! -f "$plan_file" ]]; then
    cat > "$plan_file" <<EOF
# PLAN-${task_id}-v1.0

- task_id: ${task_id}
- plan_version: v1.0
- objective:
- scope:
- assumptions:
- risks:
- acceptance_signals:
- stop_conditions:
- owner:
- last_updated: ${now_utc}

## Steps
1.
2.
3.
EOF
    echo "[INFO] Created initial plan doc: $plan_file"
  fi

  if compgen -G "$report_dir/PLAN-${task_id}-v*-review-*.md" >/dev/null; then
    local report_count
    report_count="$(find "$report_dir" -maxdepth 1 -type f -name "PLAN-${task_id}-v*-review-*.md" | wc -l | tr -d ' ')"
    echo "[INFO] Found evaluator report(s) for task ${task_id}: ${report_count}"
  else
    echo "[INFO] No evaluator report found for task ${task_id} yet (expected after feedback rounds)."
  fi
}

"$INIT_SCRIPT" "$PROJECT_ROOT"

BRANCH="$(current_branch)"

IS_GIT_REPO="true"
if ! is_git_repo; then
  IS_GIT_REPO="false"
  echo "[INFO] Not a git repository. Branch-based inference disabled; using fallback strategies." >&2
fi

if [[ "$IS_GIT_REPO" != "true" && -z "$TASK_ID" ]]; then
  ACTIVE_TASK_COUNT="$(count_non_git_active_tasks)"
  if (( ACTIVE_TASK_COUNT > 1 )); then
    echo "[ERROR] Multiple active tasks detected (${ACTIVE_TASK_COUNT}) in non-git mode. Use --task-id to disambiguate." >&2
    exit 1
  fi
fi

RESOLVED_SCOPE="$(infer_scope_type "$BRANCH")"
RESOLVED_TASK_ID="$(infer_task_id "$BRANCH")"
RESOLVED_DECISION_ID="$(infer_decision_id "$BRANCH" "$RESOLVED_TASK_ID")"
RESOLVED_MODE="$(resolve_validation_mode "$RESOLVED_SCOPE")"

if [[ -z "$TASK_TITLE" ]]; then
  TASK_TITLE="Task ${RESOLVED_TASK_ID}"
fi

if [[ -z "$SELECTED_OPTION" ]]; then
  if [[ -n "${BRANCH:-}" ]]; then
    SELECTED_OPTION="Auto-tracked update for ${RESOLVED_SCOPE} on ${BRANCH}"
  else
    SELECTED_OPTION="Auto-tracked update for ${RESOLVED_SCOPE}"
  fi
fi

GARDEN_ARGS=(
  "$PROJECT_ROOT"
  --task-id "$RESOLVED_TASK_ID"
  --task-title "$TASK_TITLE"
  --task-status "$TASK_STATUS"
  --decision-id "$RESOLVED_DECISION_ID"
  --decision-title "Decision ${RESOLVED_DECISION_ID}"
  --scope-type "$RESOLVED_SCOPE"
  --chosen-by user
  --selected-option "$SELECTED_OPTION"
)

if [[ -n "$SHADOW_NOTE" ]]; then
  GARDEN_ARGS+=(--shadow-note "$SHADOW_NOTE")
fi

# Only pass axis values when explicitly provided (no generic defaults)
if [[ -n "$AXIS_WHY" ]]; then
  GARDEN_ARGS+=(--axis-why "$AXIS_WHY")
fi

if [[ -n "$AXIS_WHAT" ]]; then
  GARDEN_ARGS+=(--axis-what "$AXIS_WHAT")
fi

if [[ -n "$AXIS_HOW" ]]; then
  GARDEN_ARGS+=(--axis-how "$AXIS_HOW")
fi

if [[ -n "$AXIS_WHERE" ]]; then
  GARDEN_ARGS+=(--axis-where "$AXIS_WHERE")
fi

if [[ -n "$AXIS_VERIFY" ]]; then
  GARDEN_ARGS+=(--axis-verify "$AXIS_VERIFY")
fi

# Resolve change scope: explicit > auto-detect
RESOLVED_CHANGE_SCOPE="$CHANGE_SCOPE"
if [[ -z "$RESOLVED_CHANGE_SCOPE" ]]; then
  # Auto-detect: if any runtime cmd is provided, assume code-or-runtime
  if [[ -n "$RUNTIME_TEST_CMD" || -n "$RUNTIME_LINT_CMD" || -n "$RUNTIME_E2E_CMD" ]]; then
    RESOLVED_CHANGE_SCOPE="code-or-runtime"
  else
    RESOLVED_CHANGE_SCOPE="docs-only"
  fi
fi

# Phase 1: docs lifecycle (always runs)
"$GARDEN_SCRIPT" "${GARDEN_ARGS[@]}"

# Phase 1.5: plan/report bootstrap for plan ping-pong workflow
ensure_plan_and_report_docs "$RESOLVED_TASK_ID"

# Phase 2: docs validation (always runs)
"$VALIDATE_SCRIPT" "$PROJECT_ROOT" --mode "$RESOLVED_MODE"

contains_forbidden_shell_syntax() {
  local candidate="$1"
  [[ "$candidate" == *$'\n'* || "$candidate" == *$'\r'* ]] && return 0
  [[ "$candidate" == *"&"* ]] && return 0
  [[ "$candidate" == *";"* || "$candidate" == *"|"* ]] && return 0
  [[ "$candidate" == *'$('* || "$candidate" == *'`'* ]] && return 0
  [[ "$candidate" == *">"* || "$candidate" == *"<"* ]] && return 0
  return 1
}

allow_pattern_match() {
  local candidate="$1"
  local pattern="$2"
  local prefix

  if [[ "$pattern" == *'*' ]]; then
    prefix="${pattern%\*}"
    [[ "$candidate" == "$prefix"* ]]
    return
  fi

  [[ "$candidate" == "$pattern" ]]
}

# Runtime command security: enforce allow-list and validate command syntax.
check_runtime_allowed() {
  local cmd="$1"
  local label="$2"
  local allowed="false"
  local pattern
  local executable
  local subcommand
  local command_prefix

  # Reject shell metacharacters to prevent command chaining/injection.
  if contains_forbidden_shell_syntax "$cmd"; then
    echo "[BLOCKED] ${label} command contains unsafe shell syntax: $cmd" >&2
    return 1
  fi

  if [[ -z "$RUNTIME_ALLOW_LIST" ]]; then
    echo "[BLOCKED] ${label} command requires --runtime-allow-list in code-or-runtime mode." >&2
    return 1
  fi

  if [[ ! -f "$RUNTIME_ALLOW_LIST" ]]; then
    echo "[ERROR] Runtime allow-list file not found: $RUNTIME_ALLOW_LIST" >&2
    exit 1
  fi

  executable="$(printf "%s" "$cmd" | awk '{print $1}')"
  subcommand="$(printf "%s" "$cmd" | awk '{print $2}')"
  command_prefix="$executable"
  if [[ -n "$subcommand" ]]; then
    command_prefix="${executable} ${subcommand}"
  fi

  while IFS= read -r pattern; do
    pattern="$(printf "%s" "$pattern" | sed 's/[[:space:]]*$//; s/^[[:space:]]*//')"
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue

    if allow_pattern_match "$command_prefix" "$pattern" || allow_pattern_match "$executable" "$pattern"; then
      allowed="true"
      break
    fi
  done < "$RUNTIME_ALLOW_LIST"

  if [[ "$allowed" != "true" ]]; then
    echo "[BLOCKED] ${label} command '${command_prefix}' is not in allow-list: $RUNTIME_ALLOW_LIST" >&2
    return 1
  fi

  return 0
}

# Execute a runtime command safely using bash -c (no eval)
run_runtime_cmd() {
  local cmd="$1"
  local label="$2"

  if ! check_runtime_allowed "$cmd" "$label"; then
    RUNTIME_FAILURES=$((RUNTIME_FAILURES + 1))
    return
  fi

  echo "[RUN] Runtime ${label}: $cmd"
  if ! bash -c "$cmd"; then
    echo "[FAIL] Runtime ${label} failed" >&2
    RUNTIME_FAILURES=$((RUNTIME_FAILURES + 1))
  fi
}

# Phase 3: runtime validations (code-or-runtime only)
RUNTIME_FAILURES=0
if [[ "$RESOLVED_CHANGE_SCOPE" == "code-or-runtime" ]]; then
  if [[ -n "$RUNTIME_LINT_CMD" ]]; then
    run_runtime_cmd "$RUNTIME_LINT_CMD" "lint"
  fi
  if [[ -n "$RUNTIME_TEST_CMD" ]]; then
    run_runtime_cmd "$RUNTIME_TEST_CMD" "test"
  fi
  if [[ -n "$RUNTIME_E2E_CMD" ]]; then
    run_runtime_cmd "$RUNTIME_E2E_CMD" "e2e"
  fi
fi

echo "[OK] run_codeguide completed."
echo "  - mode: $RESOLVED_MODE"
echo "  - change_scope: $RESOLVED_CHANGE_SCOPE"
echo "  - scope_type: $RESOLVED_SCOPE"
echo "  - task_id: $RESOLVED_TASK_ID"
echo "  - decision_id: $RESOLVED_DECISION_ID"

if (( RUNTIME_FAILURES > 0 )); then
  echo "[WARN] ${RUNTIME_FAILURES} runtime validation(s) failed." >&2
  if [[ "$RESOLVED_MODE" == "strict" ]]; then
    exit 1
  fi
fi
