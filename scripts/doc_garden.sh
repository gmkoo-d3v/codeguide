#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  doc_garden.sh <project-root> [options]

Options:
  --task-id <id>                  Task ID (creates/updates docs/task/TASK-<id>.md)
  --task-title "<title>"          Task title
  --task-status <status>          planned|in_progress|blocked|done (default: in_progress)
  --decision-id <id>              Decision ID (creates/updates docs/decisions/decision-<id>.md)
  --decision-title "<title>"      Decision title
  --scope-type <type>             task|hotfix|pr|release|incident|ops|other (default: task)
  --decision-status <status>      proposed|accepted|superseded (default: accepted)
  --chosen-by "<name>"            Decision owner (default: user)
  --selected-option "<text>"      Selected option summary
  --implementation-plan "<text>"  Implementation plan summary
  --context "<text>"              Decision context summary
  --rationale "<text>"            Decision rationale summary
  --impact "<text>"               Decision impact/risk summary
  --linked-task "<TASK-id>"       Linked task ID (defaults to TASK-<task-id> when provided)
  --linked-pr "<pr-ref>"          Linked PR reference
  --linked-hotfix "<id>"          Linked hotfix reference
  --axis-why "<text>"             Principle rationale (SOLID/DRY/KISS/YAGNI/LoD/SoC/CQS/POLA)
  --axis-what "<text>"            Expression choices (naming/function/comments/format)
  --axis-how "<text>"             Implementation choices (patterns/refactor/smells)
  --axis-where "<text>"           Structural placement (MVC/Layered/Hexagonal/Clean)
  --axis-verify "<text>"          Verification strategy (TDD/pyramid/FIRST)
  --shadow-note "<text>"          Short note for shadow map latest change
  --allow-empty-overwrite          Allow empty values to overwrite existing values
  --no-init                        Skip scaffold initialization
  -h, --help                      Show this message
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

TASK_ID=""
TASK_TITLE=""
TASK_STATUS="in_progress"
DECISION_ID=""
DECISION_TITLE=""
SCOPE_TYPE="task"
DECISION_STATUS="accepted"
CHOSEN_BY="user"
SELECTED_OPTION=""
IMPLEMENTATION_PLAN=""
DECISION_CONTEXT=""
DECISION_RATIONALE=""
DECISION_IMPACT=""
LINKED_TASK=""
LINKED_PR=""
LINKED_HOTFIX=""
AXIS_WHY=""
AXIS_WHAT=""
AXIS_HOW=""
AXIS_WHERE=""
AXIS_VERIFY=""
SHADOW_NOTE=""
ALLOW_EMPTY_OVERWRITE="false"
RUN_INIT="true"

require_option_value() {
  local option_name="$1"
  local remaining_args="$2"
  if (( remaining_args < 2 )); then
    echo "[ERROR] Option ${option_name} requires a value" >&2
    usage
    exit 1
  fi
}

validate_identifier() {
  local option_name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "[ERROR] Invalid ${option_name} value: ${value} (allowed: letters, digits, dot, underscore, hyphen)" >&2
    exit 1
  fi
}

validate_task_status() {
  local value="$1"
  case "$value" in
    planned|in_progress|blocked|done) ;;
    *)
      echo "[ERROR] Invalid --task-status: ${value} (use planned, in_progress, blocked, or done)" >&2
      exit 1
      ;;
  esac
}

validate_scope_type() {
  local value="$1"
  case "$value" in
    task|hotfix|pr|release|incident|ops|other) ;;
    *)
      echo "[ERROR] Invalid --scope-type: ${value} (use task, hotfix, pr, release, incident, ops, or other)" >&2
      exit 1
      ;;
  esac
}

validate_decision_status() {
  local value="$1"
  case "$value" in
    proposed|accepted|superseded) ;;
    *)
      echo "[ERROR] Invalid --decision-status: ${value} (use proposed, accepted, or superseded)" >&2
      exit 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      require_option_value "$1" "$#"
      TASK_ID="${2:-}"
      shift 2
      ;;
    --task-title)
      require_option_value "$1" "$#"
      TASK_TITLE="${2:-}"
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
    --decision-title)
      require_option_value "$1" "$#"
      DECISION_TITLE="${2:-}"
      shift 2
      ;;
    --scope-type)
      require_option_value "$1" "$#"
      SCOPE_TYPE="${2:-}"
      shift 2
      ;;
    --decision-status)
      require_option_value "$1" "$#"
      DECISION_STATUS="${2:-}"
      shift 2
      ;;
    --chosen-by)
      require_option_value "$1" "$#"
      CHOSEN_BY="${2:-}"
      shift 2
      ;;
    --selected-option)
      require_option_value "$1" "$#"
      SELECTED_OPTION="${2:-}"
      shift 2
      ;;
    --implementation-plan)
      require_option_value "$1" "$#"
      IMPLEMENTATION_PLAN="${2:-}"
      shift 2
      ;;
    --context)
      require_option_value "$1" "$#"
      DECISION_CONTEXT="${2:-}"
      shift 2
      ;;
    --rationale)
      require_option_value "$1" "$#"
      DECISION_RATIONALE="${2:-}"
      shift 2
      ;;
    --impact)
      require_option_value "$1" "$#"
      DECISION_IMPACT="${2:-}"
      shift 2
      ;;
    --linked-task)
      require_option_value "$1" "$#"
      LINKED_TASK="${2:-}"
      shift 2
      ;;
    --linked-pr)
      require_option_value "$1" "$#"
      LINKED_PR="${2:-}"
      shift 2
      ;;
    --linked-hotfix)
      require_option_value "$1" "$#"
      LINKED_HOTFIX="${2:-}"
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
    --shadow-note)
      require_option_value "$1" "$#"
      SHADOW_NOTE="${2:-}"
      shift 2
      ;;
    --allow-empty-overwrite)
      ALLOW_EMPTY_OVERWRITE="true"
      shift
      ;;
    --no-init)
      RUN_INIT="false"
      shift
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

if [[ -n "$TASK_ID" ]]; then
  validate_identifier "--task-id" "$TASK_ID"
fi

if [[ -n "$DECISION_ID" ]]; then
  validate_identifier "--decision-id" "$DECISION_ID"
fi

validate_task_status "$TASK_STATUS"
validate_scope_type "$SCOPE_TYPE"
validate_decision_status "$DECISION_STATUS"

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_SCRIPT="$THIS_DIR/init_docs_scaffold.sh"

if [[ "$RUN_INIT" == "true" ]]; then
  if [[ ! -d "$PROJECT_ROOT/docs/task" || ! -d "$PROJECT_ROOT/docs/shadow" || ! -d "$PROJECT_ROOT/docs/decisions" ]]; then
    "$INIT_SCRIPT" "$PROJECT_ROOT"
  fi
fi

DOCS_DIR="$PROJECT_ROOT/docs"
TASK_DIR="$DOCS_DIR/task"
SHADOW_DIR="$DOCS_DIR/shadow"
DECISIONS_DIR="$DOCS_DIR/decisions"
TASK_INDEX="$TASK_DIR/task-index.md"
DECISION_INDEX="$DECISIONS_DIR/decision-index.md"
SHADOW_FILE="$SHADOW_DIR/project-shadow.md"
TMP_FILES=()
LOCK_DIRS=()

register_tmp_file() {
  TMP_FILES+=("$1")
}

acquire_lock() {
  local resource="$1"
  local lock_dir="${resource}.lock.d"
  local attempts=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if (( attempts > 200 )); then
      echo "[ERROR] Timed out waiting for lock: $lock_dir" >&2
      exit 1
    fi
    sleep 0.05
  done
  LOCK_DIRS+=("$lock_dir")
}

cleanup_runtime_artifacts() {
  local tmp
  local lock_dir

  for tmp in "${TMP_FILES[@]:-}"; do
    rm -f "$tmp" 2>/dev/null || true
  done

  for lock_dir in "${LOCK_DIRS[@]:-}"; do
    rmdir "$lock_dir" 2>/dev/null || true
  done
}

trap cleanup_runtime_artifacts EXIT

normalize() {
  printf "%s" "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ *//; s/ *$//'
}

trim_value() {
  printf "%s" "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

escape_sed() {
  printf "%s" "$1" | sed 's/[\\&|]/\\&/g'
}

escape_pipe_field() {
  printf "%s" "$1" | sed 's/|/\\\\|/g'
}

upsert_field() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  local normalized
  local escaped

  normalized="$(normalize "$value")"

  # Prevent empty values from overwriting existing non-empty values
  if [[ -z "$normalized" && "$ALLOW_EMPTY_OVERWRITE" != "true" ]]; then
    if grep -qE "^- ${key}:" "$file_path"; then
      return 0
    fi
  fi

  escaped="$(escape_sed "$normalized")"

  if grep -qE "^- ${key}:" "$file_path"; then
    sed -i.bak "s|^- ${key}:.*|- ${key}: ${escaped}|" "$file_path"
    rm -f "${file_path}.bak"
  else
    printf -- "- %s: %s\n" "$key" "$normalized" >> "$file_path"
  fi
}

ensure_task_file() {
  local task_file="$1"
  local template="$TASK_DIR/task-template.md"

  if [[ ! -f "$task_file" ]]; then
    if [[ -f "$template" ]]; then
      cp "$template" "$task_file"
      sed -i.bak "1s|^# TASK-<id>$|# TASK-${TASK_ID}|" "$task_file"
      rm -f "${task_file}.bak"
    else
      cat > "$task_file" <<EOF
# TASK-${TASK_ID}

- title:
- objective:
- acceptance_criteria:
- non_goals:
- affected_modules:
- interfaces_changed:
- data_migrations:
- test_scope:
- risks:
- status: planned | in_progress | blocked | done
- owner:
- due_date:
- axis_why:
- axis_where:
- axis_verify:
EOF
    fi
  fi
}

ensure_decision_file() {
  local decision_file="$1"
  local template="$DECISIONS_DIR/decision-template.md"

  if [[ ! -f "$decision_file" ]]; then
    if [[ -f "$template" ]]; then
      cp "$template" "$decision_file"
      sed -i.bak "1s|^# decision-<id>$|# decision-${DECISION_ID}|" "$decision_file"
      rm -f "${decision_file}.bak"
    else
      cat > "$decision_file" <<EOF
# decision-${DECISION_ID}

- decision_id:
- title:
- date:
- scope_type: task | hotfix | pr | release | incident | ops | other
- status: proposed | accepted | superseded
- chosen_by:
- linked_task:
- linked_pr:
- linked_hotfix:
- context:
- selected_option:
- alternatives_considered:
- rationale:
- implementation_plan:
- impact_and_risks:
- rollback_or_mitigation:
- axis_why:
- axis_what:
- axis_how:
- axis_where:
- axis_verify:
EOF
    fi
  fi
}

status_to_section() {
  case "$1" in
    planned)     printf "## Planned" ;;
    in_progress) printf "## In Progress" ;;
    blocked)     printf "## Blocked" ;;
    done)        printf "## Done" ;;
    *)           printf "## In Progress" ;;
  esac
}

update_task_index() {
  local task_ref="$1"
  local title="$2"
  local safe_title
  local row
  local tmp_file
  local target_section

  safe_title="$(printf "%s" "$title" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ *//; s/ *$//; s/|/\\\\|/g')"
  row="- ${task_ref} | ${TASK_STATUS} | ${safe_title}"
  target_section="$(status_to_section "$TASK_STATUS")"
  acquire_lock "$TASK_INDEX"

  if [[ ! -f "$TASK_INDEX" ]]; then
    printf "# Task Index\n\n## Planned\n\n## In Progress\n\n## Blocked\n\n## Done\n" > "$TASK_INDEX"
  fi

  # Remove any existing row for this task (prevents duplicates)
  tmp_file="$(mktemp)"
  register_tmp_file "$tmp_file"
  grep -vF -- "- ${task_ref} |" "$TASK_INDEX" > "$tmp_file" || true
  mv "$tmp_file" "$TASK_INDEX"

  # Insert the row under the correct status section
  tmp_file="$(mktemp)"
  register_tmp_file "$tmp_file"
  awk -v section="$target_section" -v row="$row" '
    BEGIN { inserted = 0 }
    {
      print
      if (!inserted && $0 == section) {
        # Print the row after a blank line following the section header
        # Check if next line is blank or another section
        inserted = 1
        getline nextline
        if (nextline ~ /^$/) {
          print row
          print ""
        } else if (nextline ~ /^##/) {
          print row
          print ""
          print nextline
        } else {
          print row
          print nextline
        }
      }
    }
    END { if (!inserted) print row }
  ' "$TASK_INDEX" > "$tmp_file"
  mv "$tmp_file" "$TASK_INDEX"
}

decision_status_to_section() {
  case "$1" in
    proposed)   printf "## Proposed" ;;
    accepted)   printf "## Accepted" ;;
    superseded) printf "## Superseded" ;;
    *)          printf "## Accepted" ;;
  esac
}

ensure_decision_index_sections() {
  local tmp_file
  if [[ ! -f "$DECISION_INDEX" ]]; then
    printf "# Decision Index\n\n## Proposed\n\n## Accepted\n\n## Superseded\n" > "$DECISION_INDEX"
    return
  fi

  tmp_file="$(mktemp)"
  register_tmp_file "$tmp_file"
  cp "$DECISION_INDEX" "$tmp_file"

  for sec in "## Proposed" "## Accepted" "## Superseded"; do
    if ! grep -qF "$sec" "$tmp_file"; then
      printf "\n%s\n" "$sec" >> "$tmp_file"
    fi
  done

  mv "$tmp_file" "$DECISION_INDEX"
}

insert_index_row_under_section() {
  local section="$1"
  local row="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  register_tmp_file "$tmp_file"
  awk -v section="$section" -v row="$row" '
    BEGIN { inserted = 0 }
    {
      print
      if (!inserted && $0 == section) {
        inserted = 1
        getline nextline
        if (nextline ~ /^$/) {
          print row
          print ""
        } else if (nextline ~ /^##/) {
          print row
          print ""
          print nextline
        } else {
          print row
          print nextline
        }
      }
    }
    END { if (!inserted) print row }
  ' "$DECISION_INDEX" > "$tmp_file"
  mv "$tmp_file" "$DECISION_INDEX"
}

apply_decision_index_row() {
  local file_name="$1"
  local row="$2"
  local status="$3"
  local tmp_file
  local target_section

  target_section="$(decision_status_to_section "$status")"

  tmp_file="$(mktemp)"
  register_tmp_file "$tmp_file"
  grep -vF -- "- ${file_name} |" "$DECISION_INDEX" > "$tmp_file" || true
  mv "$tmp_file" "$DECISION_INDEX"

  insert_index_row_under_section "$target_section" "$row"
}

migrate_legacy_decision_index() {
  local backup_file
  local tmp_file
  local line
  local raw_file
  local raw_decision_id
  local raw_scope_type
  local raw_date
  local raw_status
  local raw_chosen_by
  local raw_task
  local raw_pr
  local raw_hotfix
  local raw_summary
  local file_name
  local decision_id
  local scope_type
  local decision_date
  local decision_status
  local linked_task
  local summary
  local row

  backup_file="${DECISION_INDEX}.bak.$(date -u +"%Y%m%d%H%M%S")"
  cp "$DECISION_INDEX" "$backup_file"

  tmp_file="$(mktemp)"
  register_tmp_file "$tmp_file"
  grep -vE "^\|" "$DECISION_INDEX" > "$tmp_file" || true
  mv "$tmp_file" "$DECISION_INDEX"
  ensure_decision_index_sections

  while IFS= read -r line; do
    [[ "$line" == \|* ]] || continue
    [[ "$line" =~ ^\|[[:space:]]*file[[:space:]]*\| ]] && continue
    [[ "$line" =~ ^\|[[:space:]]*[-:]+[[:space:]]*\| ]] && continue

    IFS='|' read -r _ raw_file raw_decision_id raw_scope_type raw_date raw_status raw_chosen_by raw_task raw_pr raw_hotfix raw_summary _ <<< "$line"

    file_name="$(trim_value "$raw_file")"
    decision_id="$(trim_value "$raw_decision_id")"
    scope_type="$(trim_value "$raw_scope_type")"
    decision_date="$(trim_value "$raw_date")"
    decision_status="$(trim_value "$raw_status")"
    linked_task="$(trim_value "$raw_task")"
    summary="$(trim_value "$raw_summary")"

    [[ -z "$file_name" ]] && continue

    case "$scope_type" in
      task|hotfix|pr|release|incident|ops|other) ;;
      *) scope_type="other" ;;
    esac

    case "$decision_status" in
      proposed|accepted|superseded) ;;
      *) decision_status="accepted" ;;
    esac

    if [[ -z "$decision_date" ]]; then
      decision_date="$TODAY"
    fi

    row="- $(escape_pipe_field "$file_name") | $(escape_pipe_field "$decision_id") | $(escape_pipe_field "$scope_type") | $(escape_pipe_field "$decision_date") | $(escape_pipe_field "$decision_status") | $(escape_pipe_field "$linked_task") | $(escape_pipe_field "$summary")"
    apply_decision_index_row "$file_name" "$row" "$decision_status"
  done < "$backup_file"

  echo "[INFO] Migrated legacy decision index with backup: $backup_file"
}

update_decision_index() {
  local file_name="$1"
  local task_ref="$2"
  local safe_summary
  local row

  safe_summary="$(escape_pipe_field "$(normalize "${SELECTED_OPTION:-}")")"
  row="- $(escape_pipe_field "$file_name") | $(escape_pipe_field "$DECISION_ID") | $(escape_pipe_field "$SCOPE_TYPE") | $(escape_pipe_field "$TODAY") | $(escape_pipe_field "$DECISION_STATUS") | $(escape_pipe_field "$task_ref") | ${safe_summary}"
  acquire_lock "$DECISION_INDEX"

  ensure_decision_index_sections

  # Migrate legacy table format: if file still has table header, convert it
  if grep -qE "^\| file \|" "$DECISION_INDEX" 2>/dev/null; then
    migrate_legacy_decision_index
  fi

  apply_decision_index_row "$file_name" "$row" "$DECISION_STATUS"
}

NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TODAY="$(date -u +"%Y-%m-%d")"

if [[ -n "$TASK_ID" ]]; then
  TASK_FILE="$TASK_DIR/TASK-${TASK_ID}.md"
  ensure_task_file "$TASK_FILE"
  upsert_field "$TASK_FILE" "title" "${TASK_TITLE:-Task ${TASK_ID}}"
  upsert_field "$TASK_FILE" "status" "$TASK_STATUS"
  if [[ -n "$AXIS_WHY" ]]; then
    upsert_field "$TASK_FILE" "axis_why" "$AXIS_WHY"
  fi
  if [[ -n "$AXIS_WHERE" ]]; then
    upsert_field "$TASK_FILE" "axis_where" "$AXIS_WHERE"
  fi
  if [[ -n "$AXIS_VERIFY" ]]; then
    upsert_field "$TASK_FILE" "axis_verify" "$AXIS_VERIFY"
  fi
  upsert_field "$TASK_FILE" "last_updated" "$NOW_UTC"
  update_task_index "TASK-${TASK_ID}" "${TASK_TITLE:-Task ${TASK_ID}}"
fi

if [[ -n "$DECISION_ID" ]]; then
  DECISION_FILE="$DECISIONS_DIR/decision-${DECISION_ID}.md"
  ensure_decision_file "$DECISION_FILE"

  if [[ -z "$LINKED_TASK" && -n "$TASK_ID" ]]; then
    LINKED_TASK="TASK-${TASK_ID}"
  fi

  upsert_field "$DECISION_FILE" "decision_id" "$DECISION_ID"
  upsert_field "$DECISION_FILE" "title" "${DECISION_TITLE:-Decision ${DECISION_ID}}"
  upsert_field "$DECISION_FILE" "date" "$TODAY"
  upsert_field "$DECISION_FILE" "scope_type" "$SCOPE_TYPE"
  upsert_field "$DECISION_FILE" "status" "$DECISION_STATUS"
  upsert_field "$DECISION_FILE" "chosen_by" "$CHOSEN_BY"
  upsert_field "$DECISION_FILE" "linked_task" "$LINKED_TASK"
  upsert_field "$DECISION_FILE" "linked_pr" "$LINKED_PR"
  upsert_field "$DECISION_FILE" "linked_hotfix" "$LINKED_HOTFIX"
  upsert_field "$DECISION_FILE" "context" "$DECISION_CONTEXT"
  upsert_field "$DECISION_FILE" "selected_option" "$SELECTED_OPTION"
  upsert_field "$DECISION_FILE" "rationale" "$DECISION_RATIONALE"
  upsert_field "$DECISION_FILE" "implementation_plan" "$IMPLEMENTATION_PLAN"
  upsert_field "$DECISION_FILE" "impact_and_risks" "$DECISION_IMPACT"
  if [[ -n "$AXIS_WHY" ]]; then
    upsert_field "$DECISION_FILE" "axis_why" "$AXIS_WHY"
  fi
  if [[ -n "$AXIS_WHAT" ]]; then
    upsert_field "$DECISION_FILE" "axis_what" "$AXIS_WHAT"
  fi
  if [[ -n "$AXIS_HOW" ]]; then
    upsert_field "$DECISION_FILE" "axis_how" "$AXIS_HOW"
  fi
  if [[ -n "$AXIS_WHERE" ]]; then
    upsert_field "$DECISION_FILE" "axis_where" "$AXIS_WHERE"
  fi
  if [[ -n "$AXIS_VERIFY" ]]; then
    upsert_field "$DECISION_FILE" "axis_verify" "$AXIS_VERIFY"
  fi
  upsert_field "$DECISION_FILE" "last_updated" "$NOW_UTC"

  update_decision_index "decision-${DECISION_ID}.md" "$LINKED_TASK"
fi

if [[ -f "$SHADOW_FILE" ]]; then
  upsert_field "$SHADOW_FILE" "last_updated" "$NOW_UTC"
  if [[ -n "$TASK_ID" ]]; then
    upsert_field "$SHADOW_FILE" "updated_by_task" "TASK-${TASK_ID}"
  fi
  if [[ -n "$SHADOW_NOTE" ]]; then
    upsert_field "$SHADOW_FILE" "latest_change_note" "$SHADOW_NOTE"
  fi
fi

echo "[OK] Doc-gardening sync complete."
echo "  - Project: $PROJECT_ROOT"
if [[ -n "$TASK_ID" ]]; then
  echo "  - Task: TASK-${TASK_ID}"
fi
if [[ -n "$DECISION_ID" ]]; then
  echo "  - Decision: decision-${DECISION_ID}.md"
fi
