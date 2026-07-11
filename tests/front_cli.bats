#!/usr/bin/env bats

load codeguide_helper

bats_require_minimum_version 1.5.0

CODEGUIDE="$SCRIPTS_DIR/codeguide"
CHECK_ALL="$SCRIPTS_DIR/check_all.sh"
TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

# --- dispatcher (scripts/codeguide) ----------------------------------------

@test "codeguide with no args prints usage listing every subcommand and exits 0" {
  run "$CODEGUIDE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  for sub in doctor check validate docs-sync scaffold review \
    shadow-impact shadow-coverage shadow-metrics shadow-digest; do
    [[ "$output" == *"$sub"* ]]
  done
}

@test "codeguide -h, --help, and help all print identical usage and exit 0" {
  run "$CODEGUIDE" -h
  [ "$status" -eq 0 ]
  local bare_output="$output"

  run "$CODEGUIDE" --help
  [ "$status" -eq 0 ]
  [ "$output" = "$bare_output" ]

  run "$CODEGUIDE" help
  [ "$status" -eq 0 ]
  [ "$output" = "$bare_output" ]
}

@test "codeguide rejects an unknown subcommand: exits 2 with usage on stderr" {
  run --separate-stderr "$CODEGUIDE" bogus-subcommand
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"Unknown subcommand: bogus-subcommand"* ]]
  [[ "$stderr" == *"Usage:"* ]]
  [[ "$output" != *"Unknown subcommand"* ]]
}

@test "codeguide <subcommand> --help delegates verbatim to that tool's own usage" {
  # sub|substring expected in the underlying tool's own --help output
  # (its own script basename, which only appears if dispatch reached it).
  while IFS='|' read -r sub hint; do
    [ -z "$sub" ] && continue
    run "$CODEGUIDE" "$sub" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"$hint"* ]]
  done <<'TABLE'
doctor|check_env.sh
check|check_all.sh
validate|validate_docs.sh
docs-sync|doc_garden.sh
scaffold|init_docs_scaffold.sh
review|run_external_plan_reviews.sh
shadow-impact|shadow_impact_report.py
shadow-coverage|shadow_coverage_report.py
shadow-metrics|shadow_metrics_report.py
shadow-digest|shadow_source_digest.py
TABLE
}

@test "codeguide validate runs end-to-end in advisory mode on a scratch scaffold" {
  run "$CODEGUIDE" validate "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docs validation passed."* ]]
}

@test "codeguide docs-sync preserves a quoted multi-word --task-title (arg-vector survival)" {
  # If the dispatcher's exec lost quoting, doc_garden.sh would see "there"
  # and "general" as unrecognized options and fail (verified manually: an
  # unquoted equivalent invocation fails with "[ERROR] Unknown option: there").
  run "$CODEGUIDE" docs-sync "$TEST_PROJECT" \
    --task-id front-cli-quote-01 \
    --task-title "hello there general" \
    --task-status planned
  [ "$status" -eq 0 ]

  run cat "$DOCS_ROOT/task/TASK-front-cli-quote-01.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- title: hello there general"* ]]
}

# --- suites (check_all.sh --suite) -----------------------------------------

@test "check_all --suite fast runs only the fast suite files" {
  local expected=0
  local f
  for f in check_env.bats codeguide_paths.bats scaffold_english.bats; do
    expected=$(( expected + $(grep -c '^@test' "$TESTS_DIR/$f") ))
  done

  run bash "$CHECK_ALL" "$TEST_PROJECT" --suite fast --skip-pytest
  [ "$status" -eq 0 ]
  [[ "$output" == *"1..${expected}"* ]]
  [[ "$output" == *"[PASS] bats suite (--suite fast: 3 file(s))"* ]]
  [[ "$output" == *"[SKIP] pytest suite (tests/)"* ]]
  # A test title that only exists in a contract-suite file must not run.
  [[ "$output" != *"validate_docs advisory warns when dependent external review is requested"* ]]
}

@test "check_all rejects an unknown --suite name" {
  run bash "$CHECK_ALL" "$TEST_PROJECT" --suite bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown suite: bogus"* ]]
}

@test "check_all --suite fails loudly before any stage when a suite member file is missing" {
  local skill_copy="$TEST_WORKSPACE/skill-copy"
  mkdir -p "$skill_copy/scripts" "$skill_copy/tests"
  cp "$CHECK_ALL" "$skill_copy/scripts/check_all.sh"
  cp "$TESTS_DIR/check_env.bats" "$TESTS_DIR/scaffold_english.bats" "$skill_copy/tests/"
  # codeguide_paths.bats (a fast-suite member) is intentionally left out.

  run bash "$skill_copy/scripts/check_all.sh" "$TEST_PROJECT" --suite fast
  [ "$status" -eq 2 ]
  [[ "$output" == *"Suite 'fast' references a missing test file: tests/codeguide_paths.bats"* ]]
  [[ "$output" != *"[STAGE]"* ]]
}

# --- artifacts (check_all.sh --artifacts) -----------------------------------

@test "check_all --artifacts writes stage logs, a junit report, and names the dir in the summary" {
  local artifacts_dir="$TEST_WORKSPACE/artifacts"

  run bash "$CHECK_ALL" "$TEST_PROJECT" --suite fast --skip-pytest --artifacts "$artifacts_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ARTIFACTS] $artifacts_dir"* ]]

  local log
  for log in 01-env-contract.log 02-bats-suite.log 03-pytest-suite.log \
    04-strict-docs-validation.log 05-english-docs-policy.log; do
    run test -s "$artifacts_dir/$log"
    [ "$status" -eq 0 ]
  done

  run test -s "$artifacts_dir/report.xml"
  [ "$status" -eq 0 ]
  run grep -q "<testsuite" "$artifacts_dir/report.xml"
  [ "$status" -eq 0 ]
}
