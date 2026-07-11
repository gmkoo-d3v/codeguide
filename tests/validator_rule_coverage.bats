#!/usr/bin/env bats

load codeguide_helper

COVERAGE() {
  python3 "$SCRIPTS_DIR/validator_rule_coverage.py" "$@"
}

# Seeds a minimal fixture project under $TEST_PROJECT with its own
# scripts/validate_docs.d/*.sh module, a scripts/validate_docs.sh adapter
# stand-in, and tests/*.bats -- independent of the real skill repo, so
# classification behavior can be pinned against known-shape input.
#
# The fixture module deliberately reproduces two traps called out in the
# task and its review round:
#   - heredoc_trap_rule() shells out to python3 via a `<<'PY'` heredoc whose
#     body contains a column-0 `}` (a dict literal closer) before the
#     function's own real closing brace. A scanner that is not heredoc-aware
#     slices the function body there and either loses heredoc_trap_rule's
#     real fail() call or misattributes rule_after_trap() (the function
#     immediately following it) to the wrong boundaries.
#   - ambiguous_prefix_rule()'s entire leading literal is a PREFIX of
#     ambiguous_prefix_sibling_rule()'s literal (the shape behind the real
#     check_rule_registry_ref_versions false positive, review r01 item 1),
#     and the fixture bats file contains that shared prefix inside unrelated
#     prose. A matcher without the attribution/ambiguity rule classifies
#     ambiguous_prefix_rule TESTED on text it cannot attribute.
# The fixture adapter carries two TOP-LEVEL (runtime id="main") emit sites
# -- one quoted by the fixture bats file, one quoted nowhere -- to pin the
# main-flow disclosure row (review r01 item 2).
_seed_fixture_project() {
  mkdir -p "$TEST_PROJECT/scripts/validate_docs.d" "$TEST_PROJECT/tests"

  cat > "$TEST_PROJECT/scripts/validate_docs.d/50-fixture.sh" <<'EOF'
#!/usr/bin/env bash

tested_rule() {
  fail "this distinctive fixture message should be matched by the fixture test"
}

untested_rule() {
  fail "this other distinctive fixture message is never referenced by any test file anywhere"
}

no_emit_helper() {
  return 0
}

heredoc_trap_rule() {
  local lookup
  lookup="$(python3 - <<'PY'
data = {
"a": 1,
}
print(data)
PY
)"
  fail "heredoc trap rule distinctive failure message for fixture verification"
}

rule_after_trap() {
  fail "distinctive message proving the parser resynced after the heredoc trap"
}

ambiguous_prefix_rule() {
  fail "shared ambiguous prefix text: ${1} is not allowed"
}

ambiguous_prefix_sibling_rule() {
  fail "shared ambiguous prefix text: reference must exist (${1})"
}
EOF

  cat > "$TEST_PROJECT/scripts/validate_docs.sh" <<'EOF'
#!/usr/bin/env bash

adapter_helper() {
  return 0
}

if [[ -z "${FIXTURE_READY:-}" ]]; then
  fail "fixture main flow distinctive message quoted by the test file"
fi
fail "fixture main flow message that no test ever quotes anywhere at all"
EOF

  cat > "$TEST_PROJECT/tests/fixture.bats" <<'EOF'
#!/usr/bin/env bats
# distinctive fixture coverage: this distinctive fixture message should be matched by the fixture test
# main-flow coverage marker: fixture main flow distinctive message quoted by the test file
# ambiguous-prefix collision bait (mimics an unrelated test title): shared ambiguous prefix text: nothing here
@test "placeholder" {
  run true
  [ "$status" -eq 0 ]
}
EOF
}

@test "coverage tool inventories the real repo without crashing and reports a summary" {
  run COVERAGE
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Validator Rule Coverage Report"* ]]
  [[ "$output" == *"- TESTED:"* ]]
  [[ "$output" == *"- UNTESTED:"* ]]
  [[ "$output" == *"- NO-EMIT:"* ]]
  [[ "$output" == *"- HEURISTIC-UNRESOLVED:"* ]]
  [[ "$output" == *"- MAIN-FLOW-AGGREGATE: 1"* ]]
  [[ "$output" == *"- main_flow_sites: "* ]]

  total_line="$(printf '%s\n' "$output" | grep '^- total:')"
  total="$(printf '%s' "$total_line" | grep -oE '[0-9]+')"
  [ -n "$total" ]
  [ "$total" -ge 70 ]
}

@test "coverage tool real-repo run discloses the adapter main-flow aggregate row with sites" {
  run COVERAGE --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
main_rows = [r for r in payload["rules"] if r["status"] == "MAIN-FLOW-AGGREGATE"]
assert len(main_rows) == 1, main_rows
row = main_rows[0]
assert row["function"] == "main", row
assert row["module"] == "adapter", row
# The adapter's top-level phase flow has dozens of live id="main" emit sites;
# a low floor keeps this robust to refactors while still failing loud if the
# row ever silently drops to zero (the invisibility this row exists to fix).
assert row["messages_scanned"] >= 10, row
assert payload["summary"]["main_flow_sites"] == row["messages_scanned"], payload["summary"]
PY
}

@test "coverage tool real-repo run inventories known adapter and module functions" {
  run COVERAGE
  [ "$status" -eq 0 ]
  [[ "$output" == *"adapter"*"usage"* ]]
  [[ "$output" == *"00-report"*"fail"* ]]
  [[ "$output" == *"10-parse"*"check_field_non_empty"* ]]
}

@test "coverage tool fixture classifies TESTED/UNTESTED/NO-EMIT rules correctly" {
  # "untested_rule" contains "tested_rule" as a substring, and "UNTESTED"
  # contains "TESTED" as a substring, so this asserts on parsed JSON (exact
  # per-function fields) rather than fuzzy text globs, which could pass on
  # the wrong row.
  _seed_fixture_project
  run COVERAGE --project-root "$TEST_PROJECT" --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
rules = {rule["function"]: rule for rule in payload["rules"]}

assert rules["tested_rule"]["status"] == "TESTED", rules["tested_rule"]
assert rules["tested_rule"]["matched_tests"] == ["tests/fixture.bats"], rules["tested_rule"]
assert rules["untested_rule"]["status"] == "UNTESTED", rules["untested_rule"]
assert rules["untested_rule"]["matched_tests"] == [], rules["untested_rule"]
assert rules["no_emit_helper"]["status"] == "NO-EMIT", rules["no_emit_helper"]
assert rules["adapter_helper"]["status"] == "NO-EMIT", rules["adapter_helper"]
assert rules["adapter_helper"]["module"] == "adapter", rules["adapter_helper"]
PY
}

@test "coverage tool never marks a rule TESTED on an ambiguous shared-prefix literal" {
  # Pins the review r01 item 1 reclassification: ambiguous_prefix_rule's only
  # long-enough literal is a prefix of ambiguous_prefix_sibling_rule's, and
  # the fixture bats file contains that prefix inside unrelated prose. The
  # match is unattributable, so the rule must land HEURISTIC-UNRESOLVED --
  # never TESTED -- while the sibling (whose full literal is quoted nowhere)
  # stays honestly UNTESTED.
  _seed_fixture_project
  run COVERAGE --project-root "$TEST_PROJECT" --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
rules = {rule["function"]: rule for rule in payload["rules"]}

amb = rules["ambiguous_prefix_rule"]
assert amb["status"] == "HEURISTIC-UNRESOLVED", amb
assert amb["matched_tests"] == [], amb

sib = rules["ambiguous_prefix_sibling_rule"]
assert sib["status"] == "UNTESTED", sib
PY
}

@test "coverage tool discloses fixture main-flow sites as one aggregate row with matched tests" {
  # Pins the review r01 item 2 disclosure: the fixture adapter has exactly
  # two top-level emit sites (runtime id="main"); one literal is quoted by
  # the fixture bats file. The row reports the count and the matching test,
  # but its status stays MAIN-FLOW-AGGREGATE -- never TESTED/UNTESTED.
  _seed_fixture_project
  run COVERAGE --project-root "$TEST_PROJECT" --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
rules = {rule["function"]: rule for rule in payload["rules"]}

row = rules["main"]
assert row["module"] == "adapter", row
assert row["status"] == "MAIN-FLOW-AGGREGATE", row
assert row["messages_scanned"] == 2, row
assert row["matched_tests"] == ["tests/fixture.bats"], row
assert payload["summary"]["main_flow_sites"] == 2, payload["summary"]
assert payload["summary"]["MAIN-FLOW-AGGREGATE"] == 1, payload["summary"]
PY
}

@test "coverage tool is heredoc-aware: a column-0 brace inside a python heredoc does not truncate the function" {
  _seed_fixture_project
  run COVERAGE --project-root "$TEST_PROJECT" --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
rules = {rule["function"]: rule for rule in payload["rules"]}

# heredoc_trap_rule's only real fail() call site is OUTSIDE the heredoc; the
# dict literal's column-0 '}' inside the heredoc must not be mistaken for the
# function's closing brace (which would either drop this call site or merge
# it with the next function).
trap_rule = rules["heredoc_trap_rule"]
assert trap_rule["messages_scanned"] == 1, trap_rule
assert trap_rule["module"] == "50-fixture", trap_rule

# rule_after_trap must still be discovered as its own, separate function with
# its own single emit site -- proof the parser resynced after the heredoc.
after = rules["rule_after_trap"]
assert after["messages_scanned"] == 1, after
assert after["module"] == "50-fixture", after
PY
}

@test "coverage tool --format json parses and matches the text-mode summary counts" {
  _seed_fixture_project
  run COVERAGE --project-root "$TEST_PROJECT" --format json
  [ "$status" -eq 0 ]
  json_output="$output"

  run COVERAGE --project-root "$TEST_PROJECT" --format text
  [ "$status" -eq 0 ]
  text_output="$output"

  python3 - "$json_output" "$text_output" <<'PY'
import json
import re
import sys

payload = json.loads(sys.argv[1])
text = sys.argv[2]

assert payload["tool"] == "validator_rule_coverage"
assert payload["format_version"] == 1
assert isinstance(payload["rules"], list) and payload["rules"]
statuses = {"TESTED", "UNTESTED", "NO-EMIT", "HEURISTIC-UNRESOLVED", "MAIN-FLOW-AGGREGATE"}
for rule in payload["rules"]:
    for key in ("function", "module", "status", "matched_tests", "messages_scanned"):
        assert key in rule, rule
    assert rule["status"] in statuses, rule

summary = payload["summary"]
for key in sorted(statuses) + ["total", "main_flow_sites"]:
    assert key in summary, summary
assert summary["total"] == len(payload["rules"])
assert summary["total"] == sum(summary[s] for s in statuses)

text_total = int(re.search(r"^- total: (\d+)$", text, re.MULTILINE).group(1))
assert text_total == summary["total"], (text_total, summary["total"])
PY
}

@test "coverage tool --exit-code is nonzero when an UNTESTED rule exists" {
  _seed_fixture_project
  run COVERAGE --project-root "$TEST_PROJECT" --exit-code
  [ "$status" -eq 1 ]
}

@test "coverage tool --exit-code is zero without --exit-code even when UNTESTED rules exist" {
  _seed_fixture_project
  run COVERAGE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
}

@test "coverage tool --exit-code is zero when no rule is UNTESTED (main-flow row never triggers it)" {
  mkdir -p "$TEST_PROJECT/scripts/validate_docs.d" "$TEST_PROJECT/tests"
  cat > "$TEST_PROJECT/scripts/validate_docs.d/60-clean.sh" <<'EOF'
#!/usr/bin/env bash

only_tested_rule() {
  fail "this fully covered fixture message must appear in the paired test file"
}
EOF
  # An adapter whose only emit site is top-level (main flow) and quoted by no
  # test: the disclosure row reports it, but it must not flip --exit-code --
  # only an UNTESTED rule FUNCTION does.
  cat > "$TEST_PROJECT/scripts/validate_docs.sh" <<'EOF'
#!/usr/bin/env bash

fail "unquoted top-level main flow message that appears in no test file"
EOF
  cat > "$TEST_PROJECT/tests/clean.bats" <<'EOF'
#!/usr/bin/env bats
# this fully covered fixture message must appear in the paired test file
@test "placeholder" {
  run true
}
EOF
  run COVERAGE --project-root "$TEST_PROJECT" --exit-code
  [ "$status" -eq 0 ]
  [[ "$output" == *"- main_flow_sites: 1"* ]]
}

@test "coverage tool does not crash on a project root with no validate_docs.d directory" {
  mkdir -p "$TEST_PROJECT/scripts" "$TEST_PROJECT/tests"
  run COVERAGE --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- total: 0"* ]]
}
