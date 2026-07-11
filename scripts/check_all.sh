#!/usr/bin/env bash
# Single quality gate for the codeguide skill: from a clean checkout, one
# command verifies the environment contract, runs the full test suites, and
# runs strict docs validation plus the English-policy check.
#
# Usage:
#   check_all.sh [project-root] [--skip-pytest]
#
# project-root defaults to the git toplevel containing this script (the repo
# whose docs/ tree is validated). All stages run even after a failure so one
# invocation reports the full picture; the exit code is nonzero if any stage
# failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_ROOT=""
SKIP_PYTEST="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pytest) SKIP_PYTEST="true"; shift ;;
    -h|--help)
      sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "[ERROR] Unknown option: $1" >&2; exit 2 ;;
    *) PROJECT_ROOT="$1"; shift ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git -C "$SKILL_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$PROJECT_ROOT" || ! -d "$PROJECT_ROOT" ]]; then
  echo "[ERROR] Cannot resolve project root; pass it explicitly: check_all.sh <project-root>" >&2
  exit 2
fi

declare -a STAGE_NAMES=()
declare -a STAGE_RESULTS=()
OVERALL=0

run_stage() {
  local name="$1"
  shift
  printf '\n=== [STAGE] %s ===\n' "$name"
  if "$@"; then
    STAGE_NAMES+=("$name"); STAGE_RESULTS+=("PASS")
  else
    STAGE_NAMES+=("$name"); STAGE_RESULTS+=("FAIL")
    OVERALL=1
  fi
}

if [[ "$SKIP_PYTEST" == "true" ]]; then
  run_stage "environment contract (check_env.sh --skip-pytest)" bash "$SCRIPT_DIR/check_env.sh" --skip-pytest
else
  run_stage "environment contract (check_env.sh)" bash "$SCRIPT_DIR/check_env.sh"
fi

run_stage "bats suite (tests/)" bats "$SKILL_ROOT/tests"

if [[ "$SKIP_PYTEST" == "true" ]]; then
  printf '\n=== [STAGE] pytest suite — skipped (--skip-pytest) ===\n'
  STAGE_NAMES+=("pytest suite (tests/)"); STAGE_RESULTS+=("SKIP")
else
  run_stage "pytest suite (tests/)" python3 -m pytest -q "$SKILL_ROOT/tests"
fi

run_stage "strict docs validation (validate_docs.sh)" bash "$SCRIPT_DIR/validate_docs.sh" "$PROJECT_ROOT" --mode strict

run_stage "English docs policy (check_english_docs.sh)" bash "$SCRIPT_DIR/check_english_docs.sh" "$SKILL_ROOT"

printf '\n=== [SUMMARY] ===\n'
for i in "${!STAGE_NAMES[@]}"; do
  printf '%-6s %s\n' "[${STAGE_RESULTS[$i]}]" "${STAGE_NAMES[$i]}"
done
if (( OVERALL == 0 )); then
  printf '[RESULT] All quality gates passed.\n'
else
  printf '[RESULT] Quality gate failed; see stages marked FAIL above.\n'
fi
exit "$OVERALL"
