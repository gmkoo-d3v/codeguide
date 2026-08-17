#!/usr/bin/env bats

# Terminal close-record gate tests (Release A of
# The plan): the static, transition-free matrix
# (done -> objective + acceptance_criteria + outcome; superseded/cancelled ->
# objective + disposition, outcome optional; active -> none), the exact-match
# placeholder check (tbd/TBD/n/a/none/미정, prefix matching forbidden), the
# legacy-marker exemption, and the envelope boundary (a close field below the
# first unfenced `##` heading is narrative and never satisfies the gate).
#
# The rules live in validate_docs.d/30-rules-task.sh. Release A/B shipped them
# advisory-only (a plain --mode strict run skipped them via gate_skipped_under_strict).
# Release C flips the CLOSE_RECORD_STRICT_PROMOTED switch to default ON, so a plain
# strict run now enforces the gate; the "strict" tests below exercise that behavior
# (some via the explicit env var, some via the default).

load codeguide_helper

# Same four-file stack the validator loads (00-report, shared adapter, parse module,
# task rules) with the gate invoked on a fixture. Runs in a fresh `bash -c` so no
# function or variable leaks between tests. FENCE_STRIP_CACHE is unset so the strip
# falls back to a per-call python spawn: correct output, and the cached path is covered
# deterministically in task_envelope.bats.
run_gate() {
  bash -c '
    MODE="$1"
    ISSUE_COUNT=0
    VALIDATE_FORMAT=text
    source "$2"
    source "$3"
    source "$4"
    source "$5"
    check_terminal_close_record "$6" "$7" "$8"
    echo "ISSUE_COUNT=$ISSUE_COUNT"
  ' _ "$1" "$SCRIPTS_DIR/validate_docs.d/00-report.sh" "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$SCRIPTS_DIR/validate_docs.d/10-parse.sh" "$SCRIPTS_DIR/validate_docs.d/30-rules-task.sh" "$2" "$3" "$4"
}

# Promoted-strict variant: Release C behavior, exercised through the switch.
run_gate_promoted_strict() {
  env CLOSE_RECORD_STRICT_PROMOTED=1 bash -c '
    MODE="strict"
    ISSUE_COUNT=0
    VALIDATE_FORMAT=text
    source "$1"
    source "$2"
    source "$3"
    source "$4"
    check_terminal_close_record "$5" "$6" "$7"
    echo "ISSUE_COUNT=$ISSUE_COUNT"
  ' _ "$SCRIPTS_DIR/validate_docs.d/00-report.sh" "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$SCRIPTS_DIR/validate_docs.d/10-parse.sh" "$SCRIPTS_DIR/validate_docs.d/30-rules-task.sh" "$1" "$2" "$3"
}

# --- matrix: done ---

@test "close-record gate passes a done task with objective + acceptance_criteria + outcome" {
  local doc="$TEST_WORKSPACE/gate-done-full.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: all release-A gates green
EOF

  run run_gate advisory "$doc" "TASK-gate-done-full" "done"
  [ "$status" -eq 0 ]
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "close-record gate passes a done task whose objective and acceptance_criteria are nested-bullet blocks" {
  local doc="$TEST_WORKSPACE/gate-done-nested-blocks.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective:
  - first objective bullet
  - second objective bullet
- acceptance_criteria:
  - [block-reader] nested bullets are non-empty content
  - [matrix] done requires objective + acceptance_criteria + outcome
- status: done
- outcome: all release-A gates green
EOF

  run run_gate advisory "$doc" "TASK-gate-done-nested-blocks" "done"
  [ "$status" -eq 0 ]
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "close-record gate warns when a done task is missing outcome" {
  local doc="$TEST_WORKSPACE/gate-done-no-outcome.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
EOF

  run run_gate advisory "$doc" "TASK-gate-done-no-outcome" "done"
  [ "$status" -eq 0 ]
  assert_contains "$output" "ISSUE_COUNT=1"
  assert_contains "$output" "outcome is missing in done task"
}

@test "close-record gate warns when a done task is missing objective" {
  local doc="$TEST_WORKSPACE/gate-done-no-objective.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- acceptance_criteria: gate behavior observed
- status: done
- outcome: all release-A gates green
EOF

  run run_gate advisory "$doc" "TASK-gate-done-no-objective" "done"
  assert_contains "$output" "ISSUE_COUNT=1"
  assert_contains "$output" "objective is missing in done task"
}

@test "close-record gate warns when a done task has an empty objective" {
  local doc="$TEST_WORKSPACE/gate-done-empty-objective.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective:
- acceptance_criteria: gate behavior observed
- status: done
- outcome: all release-A gates green
EOF

  run run_gate advisory "$doc" "TASK-gate-done-empty-objective" "done"
  assert_contains "$output" "ISSUE_COUNT=1"
  assert_contains "$output" "objective is present but empty in done task"
}

@test "close-record gate warns when a done task is missing acceptance_criteria" {
  local doc="$TEST_WORKSPACE/gate-done-no-ac.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- status: done
- outcome: all release-A gates green
EOF

  run run_gate advisory "$doc" "TASK-gate-done-no-ac" "done"
  assert_contains "$output" "ISSUE_COUNT=1"
  assert_contains "$output" "acceptance_criteria is missing in done task"
}

# --- matrix: superseded / cancelled ---

@test "close-record gate passes a superseded task with objective + disposition" {
  local doc="$TEST_WORKSPACE/gate-superseded-full.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- status: superseded
- disposition: superseded by TASK-successor-01
EOF

  run run_gate advisory "$doc" "TASK-gate-superseded-full" "superseded"
  [ "$status" -eq 0 ]
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "close-record gate does not require outcome for superseded tasks" {
  local doc="$TEST_WORKSPACE/gate-superseded-no-outcome.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- status: superseded
- disposition: superseded by TASK-successor-01
EOF

  run run_gate advisory "$doc" "TASK-gate-superseded-no-outcome" "superseded"
  [ "$status" -eq 0 ]
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "close-record gate warns when a cancelled task is missing objective" {
  local doc="$TEST_WORKSPACE/gate-cancelled-no-objective.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- status: cancelled
- disposition: need lapsed
EOF

  run run_gate advisory "$doc" "TASK-gate-cancelled-no-objective" "cancelled"
  assert_contains "$output" "ISSUE_COUNT=1"
  assert_contains "$output" "objective is missing in cancelled task"
}

@test "close-record gate does not require acceptance_criteria for cancelled tasks" {
  local doc="$TEST_WORKSPACE/gate-cancelled-no-ac.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- status: cancelled
- disposition: need lapsed
EOF

  run run_gate advisory "$doc" "TASK-gate-cancelled-no-ac" "cancelled"
  [ "$status" -eq 0 ]
  assert_equal "$output" "ISSUE_COUNT=0"
}

# --- matrix: active statuses require nothing ---

@test "close-record gate requires nothing for active statuses" {
  local doc="$TEST_WORKSPACE/gate-active.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: still open
- status: in_progress
EOF

  run run_gate advisory "$doc" "TASK-gate-active" "in_progress"
  [ "$status" -eq 0 ]
  assert_equal "$output" "ISSUE_COUNT=0"

  local doc2="$TEST_WORKSPACE/gate-active-2.md"
  cat > "$doc2" <<'EOF'
# Capsule

- title: Fixture
- status: blocked
EOF
  run run_gate advisory "$doc2" "TASK-gate-active-2" "blocked"
  assert_equal "$output" "ISSUE_COUNT=0"
}

# --- transition-free ---

@test "close-record gate is transition-free: an already-done file with empty close fields fails without any transition" {
  # The fixture is a STATIC file that was written as done with an empty outcome -- no
  # status change happens anywhere in this test. The gate is a static invariant.
  local doc="$TEST_WORKSPACE/gate-transition-free.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome:
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-transition-free" "done"
  assert_contains "$output" "[FAIL] outcome is missing in done task"
  assert_contains "$output" "ISSUE_COUNT=1"
}

# --- placeholder exact match ---

@test "placeholder exact match tbd fails under promoted strict" {
  local doc="$TEST_WORKSPACE/gate-placeholder-tbd.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: tbd
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-placeholder-tbd" "done"
  assert_contains "$output" "[FAIL] outcome in done task TASK-gate-placeholder-tbd is the placeholder 'tbd'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

@test "placeholder exact match TBD fails under promoted strict" {
  local doc="$TEST_WORKSPACE/gate-placeholder-TBD.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: TBD
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-placeholder-TBD" "done"
  assert_contains "$output" "[FAIL] outcome in done task TASK-gate-placeholder-TBD is the placeholder 'TBD'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

@test "placeholder exact match n/a fails under promoted strict" {
  local doc="$TEST_WORKSPACE/gate-placeholder-na.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: n/a
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-placeholder-na" "done"
  assert_contains "$output" "is the placeholder 'n/a'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

@test "placeholder exact match none fails under promoted strict" {
  local doc="$TEST_WORKSPACE/gate-placeholder-none.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: none
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-placeholder-none" "done"
  assert_contains "$output" "is the placeholder 'none'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

@test "placeholder exact match korean mijeong fails under promoted strict" {
  local doc="$TEST_WORKSPACE/gate-placeholder-mijeong.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: 미정
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-placeholder-mijeong" "done"
  assert_contains "$output" "is the placeholder '미정'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

# --- placeholder: prefix/partial matching forbidden ---

@test "prefix matching is forbidden: 'tbd later' is real content, not a placeholder" {
  local doc="$TEST_WORKSPACE/gate-placeholder-prefix-tbd.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: tbd later
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-placeholder-prefix-tbd" "done"
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "partial matching is forbidden: 'none of the above' is real content" {
  local doc="$TEST_WORKSPACE/gate-placeholder-partial-none.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: none of the above
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-placeholder-partial-none" "done"
  assert_equal "$output" "ISSUE_COUNT=0"
}

@test "close-field placeholders are rejected on disposition for superseded tasks" {
  local doc="$TEST_WORKSPACE/gate-placeholder-disp.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- status: superseded
- disposition: tbd
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-placeholder-disp" "superseded"
  assert_contains "$output" "is the placeholder 'tbd'"
  assert_contains "$output" "ISSUE_COUNT=1"
}

# --- legacy marker exemption ---

@test "legacy marker is exempt from the placeholder check" {
  local doc="$TEST_WORKSPACE/gate-legacy-marker.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
- outcome: legacy — no close-time record found
EOF

  run run_gate_promoted_strict "$doc" "TASK-gate-legacy-marker" "done"
  assert_equal "$output" "ISSUE_COUNT=0"
}

# --- envelope boundary ---

@test "close-record gate does not fire on a close field below the first unfenced ## heading" {
  local doc="$TEST_WORKSPACE/gate-outside-envelope.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
## Close-out
- outcome: completed everything below the envelope
EOF

  # The `- outcome:` sits under the first unfenced `##` heading: narrative by contract,
  # outside the metadata envelope, so extract_field_block reads it as empty and the gate
  # still warns that outcome is missing.
  run run_gate advisory "$doc" "TASK-gate-outside-envelope" "done"
  assert_contains "$output" "ISSUE_COUNT=1"
  assert_contains "$output" "outcome is missing in done task"
}

# --- advisory vs strict tiering ---

@test "close-record gate warns in advisory mode and fails under promoted strict" {
  local doc="$TEST_WORKSPACE/gate-tiering.md"
  cat > "$doc" <<'EOF'
# Capsule

- title: Fixture
- objective: exercise the close-record gate
- acceptance_criteria: gate behavior observed
- status: done
EOF

  run run_gate advisory "$doc" "TASK-gate-tiering" "done"
  assert_contains "$output" "[WARN] outcome is missing in done task"
  assert_contains "$output" "ISSUE_COUNT=1"

  run run_gate_promoted_strict "$doc" "TASK-gate-tiering" "done"
  assert_contains "$output" "[FAIL] outcome is missing in done task"
  assert_contains "$output" "ISSUE_COUNT=1"
}

# --- integration through the real validator ---

@test "validate_docs advisory reports close-record gaps for done tasks" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "gate-int-01" --task-title "Gate int" --task-status done --no-init >/dev/null 2>&1

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "outcome is missing in done task TASK-gate-int-01"
}

@test "validate_docs plain strict run fails on a done task with empty close fields (Release C promotion is the default)" {
  # Release A/B: the close-record rules were skipped under a plain strict run (the
  # CLOSE_RECORD_STRICT_PROMOTED switch defaulted OFF). Release C flips the switch to
  # default ON, so a plain strict run now FAILS on the close-record gate -- this test
  # pins the promoted behavior without exporting the switch.
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "gate-int-strict-01" --task-title "Gate int strict" --task-status done --no-init >/dev/null 2>&1

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "outcome is missing in done task TASK-gate-int-strict-01"
  assert_contains "$output" "close-record gate"
}

@test "validate_docs promoted strict fails on a done task with empty close fields" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "gate-promoted-01" --task-title "Gate promoted" --task-status done --no-init >/dev/null 2>&1

  run env CLOSE_RECORD_STRICT_PROMOTED=1 "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "outcome is missing in done task TASK-gate-promoted-01"
}
