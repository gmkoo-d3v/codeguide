#!/usr/bin/env bash
# Non-destructive Superpowers Bridge Automation Script
# Promotes Superpowers draft plans to Codeguide SSOT via Symbolic Link & Task Index Registration

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bridge_superpowers.sh <project-root> promote --draft <draft-path> --task-id <TASK-id> [options]

Options:
  --draft <path>          Path to Superpowers draft plan (.superpowers/plans/... or AGY artifact)
  --task-id <id>          Task ID (e.g. TASK-superpowers-feature-01)
  --task-title "<title>"  Task title (optional)
  --risk-level <level>    low|medium|high|critical (default: low)
  -h, --help              Show this message
EOF
}

PROJECT_ROOT="."
if [[ $# -gt 0 && "${1:-}" != -* ]]; then
  PROJECT_ROOT="${1%/}"
  shift
fi

COMMAND=""
if [[ $# -gt 0 && "${1:-}" != -* ]]; then
  COMMAND="$1"
  shift
fi

DRAFT_PATH=""
TASK_ID=""
TASK_TITLE=""
RISK_LEVEL="low"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --draft)
      [[ $# -lt 2 ]] && { echo "Error: --draft requires a path argument" >&2; exit 1; }
      DRAFT_PATH="$2"
      shift 2
      ;;
    --task-id)
      [[ $# -lt 2 ]] && { echo "Error: --task-id requires an ID argument" >&2; exit 1; }
      TASK_ID="$2"
      shift 2
      ;;
    --task-title)
      [[ $# -lt 2 ]] && { echo "Error: --task-title requires a title argument" >&2; exit 1; }
      TASK_TITLE="$2"
      shift 2
      ;;
    --risk-level)
      [[ $# -lt 2 ]] && { echo "Error: --risk-level requires a level argument" >&2; exit 1; }
      RISK_LEVEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$COMMAND" != "promote" ]]; then
  echo "Error: Command must be 'promote'" >&2
  usage
  exit 1
fi

if [[ -z "$DRAFT_PATH" ]]; then
  echo "Error: --draft <path> is required" >&2
  exit 1
fi

if [[ -z "$TASK_ID" ]]; then
  echo "Error: --task-id <id> is required" >&2
  exit 1
fi

case "$RISK_LEVEL" in
  low|medium|high|critical) ;;
  *)
    echo "Error: Invalid --risk-level '$RISK_LEVEL'. Allowed: low|medium|high|critical" >&2
    exit 1
    ;;
esac

# Clean TASK_ID prefix
TASK_ID="${TASK_ID#TASK-}"
FULL_TASK_ID="TASK-${TASK_ID}"
PLAN_FILE_NAME="PLAN-${TASK_ID}-v1.0.md"

# Validate the STRIPPED task id against the same identifier rule doc_garden
# applies (^[A-Za-z0-9._-]+$), BEFORE any mkdir: the id feeds ORCH_DIR, so a
# stray path segment (e.g. ../../evil) must never create directories.
if [[ ! "$TASK_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Error: Invalid --task-id '${TASK_ID}' (after TASK- prefix strip). Allowed: letters, digits, dot, underscore, hyphen." >&2
  exit 1
fi

ABS_PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
DOCS_DIR="${ABS_PROJECT_ROOT}/docs"
PLAN_DIR="${DOCS_DIR}/plan"
TASK_DIR="${DOCS_DIR}/task"
ORCH_DIR="${DOCS_DIR}/orchestration/${TASK_ID}"

# Draft check (F7): a REGULAR file is required. -f follows symlinks, so a
# symlink to a regular file still passes; a symlink to a directory, a
# dangling symlink, or a missing file all fail here. Runs BEFORE any
# directory creation: an invalid invocation leaves no directory artifacts.
if [[ ! -f "$DRAFT_PATH" ]]; then
  echo "Error: Draft file at '$DRAFT_PATH' does not exist." >&2
  exit 1
fi

ABS_DRAFT="$(cd "$(dirname "$DRAFT_PATH")" && pwd)/$(basename "$DRAFT_PATH")"
TARGET_PLAN_PATH="${PLAN_DIR}/${PLAN_FILE_NAME}"

# Prevent overwriting if target equals draft
if [[ "$ABS_DRAFT" == "$TARGET_PLAN_PATH" ]]; then
  echo "Error: Draft file and target plan path are identical ($TARGET_PLAN_PATH)" >&2
  exit 1
fi

# Compute relative symlink target from docs/plan/ to draft safely via sys.argv
RELATIVE_DRAFT="$(python3 -c "import sys, os; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$ABS_DRAFT" "$PLAN_DIR")"

# Target guard — never destroy an existing target. The only pre-existing state
# admitted is a symlink this script itself created (same relative target:
# idempotent re-promotion). A real plan file, a symlink pointing elsewhere, or
# a dangling symlink aborts BEFORE any write, naming the existing target.
if [[ -L "$TARGET_PLAN_PATH" ]]; then
  EXISTING_TARGET="$(readlink "$TARGET_PLAN_PATH")"
  if [[ "$EXISTING_TARGET" != "$RELATIVE_DRAFT" ]]; then
    echo "Error: Refusing to overwrite existing symlink '$TARGET_PLAN_PATH' (points at '$EXISTING_TARGET', not at the draft '$ABS_DRAFT')." >&2
    exit 1
  fi
  echo "Target symlink already points at the draft; re-promoting idempotently."
elif [[ -e "$TARGET_PLAN_PATH" ]]; then
  echo "Error: Refusing to overwrite existing target '$TARGET_PLAN_PATH' (a real file). Remove or move it manually, then re-run." >&2
  exit 1
fi

# doc_garden fail-closed: presence must be verified BEFORE any state change,
# so an unusable install can never print "Successfully promoted" with no
# ledger registration.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC_GARDEN="${SCRIPT_DIR}/doc_garden.sh"

if [[ ! -f "$DOC_GARDEN" ]]; then
  echo "Error: doc_garden.sh not found at '$DOC_GARDEN'; cannot register the task ledger. Aborting promotion." >&2
  exit 1
fi

# All preconditions hold (draft exists, target is clear, doc_garden present);
# only now is it safe to create the SoR directories.
mkdir -p "$PLAN_DIR" "$TASK_DIR" "$ORCH_DIR"

echo "Promoting Superpowers draft to Codeguide SSOT via Symbolic Link..."
echo "  Draft: $ABS_DRAFT"
echo "  Target Symlink: $TARGET_PLAN_PATH"
echo "  Relative Target: $RELATIVE_DRAFT"

# Non-destructive Symlink creation. The guard verified the target is absent or
# already pointing at the draft, so nothing is ever replaced here.
SYMLINK_CREATED=false
if [[ ! -L "$TARGET_PLAN_PATH" && ! -e "$TARGET_PLAN_PATH" ]]; then
  ln -s "$RELATIVE_DRAFT" "$TARGET_PLAN_PATH"
  SYMLINK_CREATED=true
fi

# Verify symlink target resolves cleanly. Rollback only ever removes a symlink
# this run created: a PRE-EXISTING symlink (idempotent admission) that has gone
# dangling is left in place, but still aborts the promotion.
if [[ ! -e "$TARGET_PLAN_PATH" ]]; then
  if [[ "$SYMLINK_CREATED" == "true" ]]; then
    echo "Error: Created symlink '$TARGET_PLAN_PATH' is dangling or unresolved." >&2
    rm -f "$TARGET_PLAN_PATH"
  else
    echo "Error: Pre-existing symlink '$TARGET_PLAN_PATH' is dangling or unresolved; left in place." >&2
  fi
  exit 1
fi

# Run doc_garden.sh to register task & scaffold task/orchestration files.
# Explicit failure handling (set -e alone would abort without cleanup):
# roll back the symlink we created and exit non-zero, so the SoR is left
# unchanged.
echo "Executing doc_garden.sh to register task index..."
if ! bash "$DOC_GARDEN" "$ABS_PROJECT_ROOT" \
    --task-id "$TASK_ID" \
    --task-title "${TASK_TITLE:-Promoted Superpowers Plan ${TASK_ID}}" \
    --task-status "in_progress" \
    --risk-level "$RISK_LEVEL"; then
  if [[ "$SYMLINK_CREATED" == "true" ]]; then
    rm -f "$TARGET_PLAN_PATH"
    echo "Error: doc_garden.sh failed; promotion aborted and the created symlink '$TARGET_PLAN_PATH' was removed." >&2
  else
    echo "Error: doc_garden.sh failed; promotion aborted (pre-existing symlink left untouched)." >&2
  fi
  exit 1
fi

# Post-condition (F2b + F8 + F10): doc_garden exited 0, but an exit 0 without
# registration must never be accepted. Verify with the SAME fence-aware
# grammar doc_garden's writer uses: a live (unfenced) ledger row whose row
# PREFIX is exactly `- TASK-<id> | in_progress |` — PREFIX mode anchors the
# status field with the following `|`, so a status merely PREFIXED with
# in_progress (e.g. in_progress_stale) cannot satisfy it — plus the task
# capsule and ORCH scaffold. The `if ! ASSIGNMENT` form propagates a reader
# failure into the rollback branch (a substitution failure makes the
# assignment fail, `!` flips it, rollback runs). Same SYMLINK_CREATED gate.
CODEGUIDE_DOC_LINES_SCRIPT_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/codeguide_doc_lines.sh"
LEDGER_INDEX="${TASK_DIR}/task-index.md"
if ! LIVE_ROWS="$(require_unfenced_lines "$LEDGER_INDEX" prefix "- ${FULL_TASK_ID} | in_progress |")" \
   || [[ -z "$LIVE_ROWS" ]] \
   || [[ ! -f "$TASK_DIR/TASK-${TASK_ID}.md" ]] \
   || [[ ! -f "$ORCH_DIR/ORCH.md" ]]; then
  if [[ "$SYMLINK_CREATED" == "true" ]]; then
    rm -f "$TARGET_PLAN_PATH"
    echo "Error: doc_garden.sh exited 0 but the live ledger row '- ${FULL_TASK_ID} | in_progress' or a scaffold file (task capsule / ORCH) is missing; promotion aborted and the created symlink '$TARGET_PLAN_PATH' was removed." >&2
  else
    echo "Error: doc_garden.sh exited 0 but the live ledger row '- ${FULL_TASK_ID} | in_progress' or a scaffold file (task capsule / ORCH) is missing; promotion aborted (pre-existing symlink left untouched)." >&2
  fi
  exit 1
fi

echo "Successfully promoted Superpowers plan to Codeguide SSOT!"
echo "  Symlink: $TARGET_PLAN_PATH -> $RELATIVE_DRAFT"
echo "  Task ID: $FULL_TASK_ID"
