#!/usr/bin/env bash
# Single quality gate for the codeguide skill: from a clean checkout, one
# command verifies the environment contract, runs the full test suites, and
# runs strict docs validation plus the English-policy check.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  check_all.sh [project-root] [--skip-pytest] [--suite <name>] [--artifacts <dir>]

Single quality gate for the codeguide skill: verifies the environment
contract, runs the bats and pytest suites, and runs strict docs validation
plus the English-policy check. project-root defaults to the git toplevel
containing this script (the repo whose docs/ tree is validated). All stages
run even after a failure so one invocation reports the full picture; the
exit code is nonzero if any stage failed.

Options:
  --skip-pytest       Skip the pytest stage and the pytest check inside the
                       environment contract stage.
  --suite <name>       Restrict the bats stage to a named file subset:
                         fast     - check_env.bats, codeguide_paths.bats,
                                    scaffold_english.bats
                         contract - validate_docs.bats, doc_garden.bats,
                                    run_codeguide.bats
                         external - external_review.bats
                         shadow   - shadow_core.bats, shadow_v2.bats,
                                    shadow_coverage_report.bats,
                                    shadow_evidence_probe.bats,
                                    shadow_impact_report.bats,
                                    shadow_metrics_report.bats,
                                    shadow_nav_graph_report.bats
                         full     - the tests/ directory (default; identical
                                    to the plain, no-flag invocation)
                       Suite membership is validated to exist at startup; a
                       missing member file fails loud before any stage runs.
                       --suite affects only the bats stage: strict docs
                       validation and the English-policy check still run
                       regardless of --suite. The pytest stage only runs for
                       the full suite -- it is skipped (and reported as
                       skipped) for any named subset.
  --artifacts <dir>    Create <dir> and tee each stage's combined
                       stdout+stderr to <dir>/<NN>-<stage>.log. The bats
                       stage additionally writes a JUnit report into <dir>
                       via --report-formatter junit --output <dir>. Exit
                       semantics are unchanged; the summary prints <dir>.
  -h, --help            Show this message.
EOF
}

PROJECT_ROOT=""
SKIP_PYTEST="false"
SUITE="full"
ARTIFACTS_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pytest) SKIP_PYTEST="true"; shift ;;
    --suite)
      if [[ $# -lt 2 ]]; then
        echo "[ERROR] --suite requires a value" >&2
        exit 2
      fi
      SUITE="$2"; shift 2
      ;;
    --artifacts)
      if [[ $# -lt 2 ]]; then
        echo "[ERROR] --artifacts requires a value" >&2
        exit 2
      fi
      ARTIFACTS_DIR="$2"; shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "[ERROR] Unknown option: $1" >&2; exit 2 ;;
    *) PROJECT_ROOT="$1"; shift ;;
  esac
done

# Suite membership (bash 3.2: no associative arrays). Sets SUITE_FILES as a
# list of tests/-relative .bats filenames; empty means "the tests/ directory
# as a whole" (the full/default suite).
# front_cli.bats is deliberately in no named subset: its tests execute
# check_all --suite themselves, so including it would nest bats inside bats
# recursively. Iterate on it directly: bats tests/front_cli.bats.
SUITE_FILES=()
set_suite_files() {
  case "$1" in
    fast)
      SUITE_FILES=(check_env.bats codeguide_paths.bats scaffold_english.bats)
      ;;
    contract)
      SUITE_FILES=(validate_docs.bats doc_garden.bats run_codeguide.bats)
      ;;
    external)
      SUITE_FILES=(external_review.bats)
      ;;
    shadow)
      SUITE_FILES=(shadow_core.bats shadow_v2.bats shadow_coverage_report.bats
        shadow_evidence_probe.bats shadow_impact_report.bats
        shadow_metrics_report.bats shadow_nav_graph_report.bats)
      ;;
    full)
      SUITE_FILES=()
      ;;
    *)
      return 1
      ;;
  esac
}

if ! set_suite_files "$SUITE"; then
  echo "[ERROR] Unknown suite: $SUITE (expected: fast, contract, external, shadow, full)" >&2
  exit 2
fi

BATS_TARGETS=()
if [[ "$SUITE" == "full" ]]; then
  BATS_TARGETS=("$SKILL_ROOT/tests")
else
  for suite_file in "${SUITE_FILES[@]}"; do
    suite_target="$SKILL_ROOT/tests/$suite_file"
    if [[ ! -f "$suite_target" ]]; then
      echo "[ERROR] Suite '$SUITE' references a missing test file: tests/$suite_file" >&2
      exit 2
    fi
    BATS_TARGETS+=("$suite_target")
  done
fi

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git -C "$SKILL_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$PROJECT_ROOT" || ! -d "$PROJECT_ROOT" ]]; then
  echo "[ERROR] Cannot resolve project root; pass it explicitly: check_all.sh <project-root>" >&2
  exit 2
fi

if [[ -n "$ARTIFACTS_DIR" ]]; then
  if ! mkdir -p "$ARTIFACTS_DIR"; then
    echo "[ERROR] Cannot create artifacts directory: $ARTIFACTS_DIR" >&2
    exit 2
  fi
  ARTIFACTS_DIR="$(cd "$ARTIFACTS_DIR" && pwd)"
fi

declare -a STAGE_NAMES=()
declare -a STAGE_RESULTS=()
STAGE_INDEX=0
OVERALL=0

# run_stage <slug> <display-name> <command...>
# slug is a filesystem-safe stage identifier used for the artifact log
# filename; display-name is the human-readable summary/header label.
run_stage() {
  local slug="$1"
  local name="$2"
  shift 2
  STAGE_INDEX=$((STAGE_INDEX + 1))
  printf '\n=== [STAGE] %s ===\n' "$name"
  local status
  if [[ -n "$ARTIFACTS_DIR" ]]; then
    local log_file
    log_file="$(printf '%s/%02d-%s.log' "$ARTIFACTS_DIR" "$STAGE_INDEX" "$slug")"
    "$@" 2>&1 | tee "$log_file"
    status="${PIPESTATUS[0]}"
  else
    "$@"
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    STAGE_NAMES+=("$name"); STAGE_RESULTS+=("PASS")
  else
    STAGE_NAMES+=("$name"); STAGE_RESULTS+=("FAIL")
    OVERALL=1
  fi
}

# skip_stage <slug> <display-name> <reason>
skip_stage() {
  local slug="$1"
  local name="$2"
  local reason="$3"
  STAGE_INDEX=$((STAGE_INDEX + 1))
  local line
  line="$(printf '\n=== [STAGE] %s -- skipped (%s) ===' "$name" "$reason")"
  if [[ -n "$ARTIFACTS_DIR" ]]; then
    local log_file
    log_file="$(printf '%s/%02d-%s.log' "$ARTIFACTS_DIR" "$STAGE_INDEX" "$slug")"
    printf '%s\n' "$line" | tee "$log_file"
  else
    printf '%s\n' "$line"
  fi
  STAGE_NAMES+=("$name"); STAGE_RESULTS+=("SKIP")
}

if [[ "$SKIP_PYTEST" == "true" ]]; then
  run_stage "env-contract" "environment contract (check_env.sh --skip-pytest)" bash "$SCRIPT_DIR/check_env.sh" --skip-pytest
else
  run_stage "env-contract" "environment contract (check_env.sh)" bash "$SCRIPT_DIR/check_env.sh"
fi

BATS_CMD=(bats)
if [[ -n "$ARTIFACTS_DIR" ]]; then
  BATS_CMD+=(--report-formatter junit --output "$ARTIFACTS_DIR")
fi
BATS_CMD+=("${BATS_TARGETS[@]}")
if [[ "$SUITE" == "full" ]]; then
  run_stage "bats-suite" "bats suite (tests/)" "${BATS_CMD[@]}"
else
  run_stage "bats-suite" "bats suite (--suite $SUITE: ${#BATS_TARGETS[@]} file(s))" "${BATS_CMD[@]}"
fi

if [[ "$SUITE" != "full" ]]; then
  skip_stage "pytest-suite" "pytest suite (tests/)" "suite=$SUITE (pytest runs in the full suite only)"
elif [[ "$SKIP_PYTEST" == "true" ]]; then
  skip_stage "pytest-suite" "pytest suite (tests/)" "--skip-pytest"
else
  run_stage "pytest-suite" "pytest suite (tests/)" python3 -m pytest -q "$SKILL_ROOT/tests"
fi

run_stage "strict-docs-validation" "strict docs validation (validate_docs.sh)" bash "$SCRIPT_DIR/validate_docs.sh" "$PROJECT_ROOT" --mode strict

run_stage "english-docs-policy" "English docs policy (check_english_docs.sh)" bash "$SCRIPT_DIR/check_english_docs.sh" "$SKILL_ROOT"

printf '\n=== [SUMMARY] ===\n'
for i in "${!STAGE_NAMES[@]}"; do
  printf '%-6s %s\n' "[${STAGE_RESULTS[$i]}]" "${STAGE_NAMES[$i]}"
done
if [[ -n "$ARTIFACTS_DIR" ]]; then
  printf '[ARTIFACTS] %s\n' "$ARTIFACTS_DIR"
fi
if (( OVERALL == 0 )); then
  printf '[RESULT] All quality gates passed.\n'
else
  printf '[RESULT] Quality gate failed; see stages marked FAIL above.\n'
fi
exit "$OVERALL"
