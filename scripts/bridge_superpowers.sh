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
      DRAFT_PATH="$2"
      shift 2
      ;;
    --task-id)
      TASK_ID="$2"
      shift 2
      ;;
    --task-title)
      TASK_TITLE="$2"
      shift 2
      ;;
    --risk-level)
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

# Clean TASK_ID prefix
TASK_ID="${TASK_ID#TASK-}"
FULL_TASK_ID="TASK-${TASK_ID}"
PLAN_FILE_NAME="PLAN-${TASK_ID}-v1.0.md"

ABS_PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
DOCS_DIR="${ABS_PROJECT_ROOT}/docs"
PLAN_DIR="${DOCS_DIR}/plan"
TASK_DIR="${DOCS_DIR}/task"
ORCH_DIR="${DOCS_DIR}/orchestration/${TASK_ID}"

mkdir -p "$PLAN_DIR" "$TASK_DIR" "$ORCH_DIR"

if [[ ! -f "$DRAFT_PATH" && ! -L "$DRAFT_PATH" ]]; then
  echo "Error: Draft file at '$DRAFT_PATH' does not exist." >&2
  exit 1
fi

ABS_DRAFT="$(cd "$(dirname "$DRAFT_PATH")" && pwd)/$(basename "$DRAFT_PATH")"
TARGET_PLAN_PATH="${PLAN_DIR}/${PLAN_FILE_NAME}"

# Compute relative symlink target from docs/plan/ to draft
RELATIVE_DRAFT="$(python3 -c "import os; print(os.path.relpath('$ABS_DRAFT', '$PLAN_DIR'))")"

echo "Promoting Superpowers draft to Codeguide SSOT via Symbolic Link..."
echo "  Draft: $ABS_DRAFT"
echo "  Target Symlink: $TARGET_PLAN_PATH"
echo "  Relative Target: $RELATIVE_DRAFT"

# Non-destructive Symlink creation
rm -f "$TARGET_PLAN_PATH"
ln -sf "$RELATIVE_DRAFT" "$TARGET_PLAN_PATH"

# Run doc_garden.sh to register task & scaffold task/orchestration files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC_GARDEN="${SCRIPT_DIR}/doc_garden.sh"

if [[ -x "$DOC_GARDEN" || -f "$DOC_GARDEN" ]]; then
  echo "Executing doc_garden.sh to register task index..."
  bash "$DOC_GARDEN" "$ABS_PROJECT_ROOT" \
    --task-id "$TASK_ID" \
    --task-title "${TASK_TITLE:-Promoted Superpowers Plan ${TASK_ID}}" \
    --task-status "in_progress" \
    --risk-level "$RISK_LEVEL" || true
fi

echo "Successfully promoted Superpowers plan to Codeguide SSOT!"
echo "  Symlink: $TARGET_PLAN_PATH -> $RELATIVE_DRAFT"
echo "  Task ID: $FULL_TASK_ID"
