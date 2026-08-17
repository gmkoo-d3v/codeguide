#!/usr/bin/env bats

# Envelope-bounded unknown-key rejection tests (Release A of
# The plan): a column-0 key in the metadata envelope
# that is NOT in the task dictionary or the legacy classification table warns.
# Preserve-classified legacy keys (last_updated, decision_ref, orchestration_ref,
# reviewers) are allowed; rename-classified keys (plan_ref, close_out_note) still
# warn until Release B migrates them. Fenced example keys, narrative-section keys
# and nested block content are never scanned. Advisory-only in Release A/B; the
# CLOSE_RECORD_STRICT_PROMOTED switch defaults ON since Release C, so a plain strict
# run now enforces the rejection.

load codeguide_helper

# Same four-file stack as close_record.bats, with the unknown-key scan invoked on a
# fixture.
run_unknown_scan() {
  bash -c '
    MODE="$1"
    ISSUE_COUNT=0
    VALIDATE_FORMAT=text
    source "$2"
    source "$3"
    source "$4"
    source "$5"
    check_unknown_task_keys "$6" "$7"
    echo "ISSUE_COUNT=$ISSUE_COUNT"
  ' _ "$1" "$SCRIPTS_DIR/validate_docs.d/00-report.sh" "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$SCRIPTS_DIR/validate_docs.d/10-parse.sh" "$SCRIPTS_DIR/validate_docs.d/30-rules-task.sh" "$2" "$3"
}

run_unknown_scan_promoted_strict() {
  env CLOSE_RECORD_STRICT_PROMOTED=1 bash -c '
    MODE="strict"
    ISSUE_COUNT=0
    VALIDATE_FORMAT=text
    source "$1"
    source "$2"
    source "$3"
    source "$4"
    check_unknown_task_keys "$5" "$6"
    echo "ISSUE_COUNT=$ISSUE_COUNT"
  ' _ "$SCRIPTS_DIR/validate_docs.d/00-report.sh" "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$SCRIPTS_DIR/validate_docs.d/10-parse.sh" "$SCRIPTS_DIR/validate_docs.d/30-rules-task.sh" "$1" "$2"
}

@test "a fully dictionary-conformant task file scans clean" {
  local doc="$TEST_WORKSPACE/unknown-clean.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-clean

- title: Clean fixture
- objective: nothing to see
- acceptance_criteria: nothing to see
- status: planned
- owner: session-1
- axis_why: gate tests
- axis_where: docs
- axis_verify: bats
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-clean"
  [ "$status" -eq 0 ]
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "plan_ref warns as a rename-classified legacy key" {
  local doc="$TEST_WORKSPACE/unknown-plan-ref.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-plan-ref

- title: Legacy fixture
- status: done
- plan_ref: docs/plan/PLAN-X-v1.0.md
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-plan-ref"
  assert_contains "$output" "unknown task-dictionary key 'plan_ref'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

@test "close_out_note warns as a rename-classified legacy key" {
  local doc="$TEST_WORKSPACE/unknown-close-note.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-close-note

- title: Legacy fixture
- status: done
- close_out_note: closed 2026-08-01
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-close-note"
  assert_contains "$output" "unknown task-dictionary key 'close_out_note'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

@test "last_updated is an allowed tool key" {
  local doc="$TEST_WORKSPACE/unknown-last-updated.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-last-updated

- title: Tool-key fixture
- status: planned
- last_updated: 2026-08-16T00:00:00Z
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-last-updated"
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "preserve-classified legacy keys are allowed: decision_ref / orchestration_ref / reviewers" {
  local doc="$TEST_WORKSPACE/unknown-preserve.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-preserve

- title: Preserve fixture
- status: done
- decision_ref: decision-abc-01
- orchestration_ref: TASK-abc-01
- reviewers: human
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-preserve"
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "a genuinely unknown key warns" {
  local doc="$TEST_WORKSPACE/unknown-bogus.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-bogus

- title: Bogus fixture
- status: planned
- bogus_field: should not be here
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-bogus"
  assert_contains "$output" "unknown task-dictionary key 'bogus_field'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

@test "fenced example keys are never scanned" {
  local doc="$TEST_WORKSPACE/unknown-fenced.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-fenced

- title: Fenced fixture
- status: planned
```markdown
- status: planned | in_progress | blocked | done
- fenced_only_key: quoted example
```
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-fenced"
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "narrative keys below the first unfenced ## heading are never scanned" {
  local doc="$TEST_WORKSPACE/unknown-narrative.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-narrative

- title: Narrative fixture
- status: done
## Close-out
- verdict: accept
- pending: none
- reason: below the envelope
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-narrative"
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "nested keys inside a close-field block are block content, never fields" {
  local doc="$TEST_WORKSPACE/unknown-nested.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-nested

- title: Nested fixture
- status: done
- outcome:
  - bogus_nested_key: block content, not a column-0 key
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-nested"
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "each unknown key is reported once per file" {
  local doc="$TEST_WORKSPACE/unknown-two-keys.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-two-keys

- title: Two-key fixture
- status: done
- plan_ref: PLAN-X-v1.0
- close_out_note: closed
EOF

  run run_unknown_scan advisory "$doc" "TASK-unknown-two-keys"
  assert_contains "$output" "unknown task-dictionary key 'plan_ref'"
  assert_contains "$output" "unknown task-dictionary key 'close_out_note'"
  assert_contains "$output" "ISSUE_COUNT=2"
}

@test "unknown-key scan fails under a plain strict run (Release C promotion is the default)" {
  # Release A/B: skipped under plain strict (switch defaulted OFF). Release C flips the
  # switch to default ON, so a plain strict run FAILS on the unknown-key scan -- this
  # test pins the promoted behavior without exporting the switch.
  local doc="$TEST_WORKSPACE/unknown-plain-strict.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-plain-strict

- title: Strict fixture
- status: done
- plan_ref: PLAN-X-v1.0
EOF

  run run_unknown_scan strict "$doc" "TASK-unknown-plain-strict"
  assert_contains "$output" "[FAIL] unknown task-dictionary key 'plan_ref'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

@test "unknown-key scan fails under promoted strict" {
  local doc="$TEST_WORKSPACE/unknown-promoted.md"
  cat > "$doc" <<'EOF'
# TASK-unknown-promoted

- title: Promoted fixture
- status: done
- plan_ref: PLAN-X-v1.0
EOF

  run run_unknown_scan_promoted_strict "$doc" "TASK-unknown-promoted"
  assert_contains "$output" "[FAIL] unknown task-dictionary key 'plan_ref'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

# --- integration through the real validator ---

@test "validate_docs advisory warns on a rename-classified legacy key" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "ukey-int-01" --task-title "Ukey int" --no-init >/dev/null 2>&1
  printf '%s\n' "- plan_ref: PLAN-ukey-int-01-v1.0" >> "$DOCS_ROOT/task/TASK-ukey-int-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "unknown task-dictionary key 'plan_ref' in envelope of TASK-ukey-int-01"
}

@test "validate_docs plain strict run fails on a rename-classified legacy key (Release C promotion is the default)" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "ukey-int-strict-01" --task-title "Ukey int strict" --no-init >/dev/null 2>&1
  printf '%s\n' "- plan_ref: PLAN-ukey-int-strict-01-v1.0" >> "$DOCS_ROOT/task/TASK-ukey-int-strict-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "unknown task-dictionary key 'plan_ref' in envelope of TASK-ukey-int-strict-01"
}
