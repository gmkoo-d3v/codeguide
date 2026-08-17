#!/usr/bin/env bats

# Task-index projection + writer-mechanics tests (Release A of
# The plan):
#
#  - the row summary derives from the TASK FILE's stored fields via the ONE shared
#    implementation (task_index_projection_summary): planned/in_progress/blocked ->
#    title, done -> outcome, superseded/cancelled -> disposition. Reusing
#    is_active_task_status for this is forbidden: done projects to outcome.
#  - multi-line outcome row summaries are canonicalized (collapse meaningful lines,
#    whitespace normalization, pipe escaping, bullet markers joined with '; ') and
#    pinned byte-for-byte.
#  - update_task_index no longer clobbers a stored title/status on update.
#  - --rebuild-task-index is atomic, sorted by task_ref, preserves comments/fenced
#    examples/section headers, includes Superseded/Cancelled sections, and is
#    idempotent (two rebuilds -> identical sha256).
#  - the validator's check_task_index_projection flags a row summary that does not
#    match the stored-field projection (advisory in Release A/B; strict since
#    Release C, where CLOSE_RECORD_STRICT_PROMOTED defaults ON).

load codeguide_helper

run_canonical() {
  bash -c 'source "$1"; task_index_summary_canonical "$2"' _ "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$1"
}

run_projection() {
  bash -c 'source "$1"; task_index_projection_summary "$2" "$3"' _ "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$1" "$2"
}

# --- canonical summary unit tests ---

@test "canonical summary passes an inline scalar through normalized" {
  run run_canonical "completed by 2026-08-16"
  [ "$status" -eq 0 ]
  assert_equal "$output" "completed by 2026-08-16"
}

@test "canonical summary collapses multi-line bullet content joined with '; '" {
  run run_canonical $'  - Evidence: commit abc123 merged\n  - Summary: all release-A gates green'
  assert_equal "$output" "Evidence: commit abc123 merged; Summary: all release-A gates green"
}

@test "canonical summary normalizes whitespace and drops blank lines" {
  run run_canonical $'  - Evidence:    commit abc123\n\n  - Summary:   all gates   green'
  assert_equal "$output" "Evidence: commit abc123; Summary: all gates green"
}

@test "canonical summary drops bare dash lines" {
  run run_canonical $'  -\n  - Evidence: commit abc123\n  -\n  - Summary: all gates green'
  assert_equal "$output" "Evidence: commit abc123; Summary: all gates green"
}

@test "canonical summary escapes pipes" {
  run run_canonical "phase one | phase two"
  assert_equal "$output" "phase one \| phase two"
}

@test "canonical summary of empty input is empty" {
  run run_canonical ""
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
}

# --- projection unit tests ---

write_projection_fixture() {
  local doc="$1"
  local status="$2"
  shift 2
  cat > "$doc" <<EOF
# TASK-projection

- title: Stored title
- objective: stored objective
- acceptance_criteria: stored criteria
- status: ${status}
EOF
  if [[ -n "$1" ]]; then
    printf '%s\n' "$1" >> "$doc"
  fi
}

@test "projection maps planned/in_progress/blocked to title" {
  local doc="$TEST_WORKSPACE/proj-active.md"
  write_projection_fixture "$doc" "in_progress"
  run run_projection "$doc" "in_progress"
  assert_equal "$output" "Stored title"

  run run_projection "$doc" "planned"
  assert_equal "$output" "Stored title"

  run run_projection "$doc" "blocked"
  assert_equal "$output" "Stored title"
}

@test "projection maps done to outcome, never to title" {
  local doc="$TEST_WORKSPACE/proj-done.md"
  write_projection_fixture "$doc" "done"
  printf '%s\n' "- outcome: merged the gate" >> "$doc"

  run run_projection "$doc" "done"
  assert_equal "$output" "merged the gate"
}

@test "projection maps superseded/cancelled to disposition" {
  local doc="$TEST_WORKSPACE/proj-superseded.md"
  write_projection_fixture "$doc" "superseded"
  printf '%s\n' "- disposition: superseded by TASK-successor-01" >> "$doc"

  run run_projection "$doc" "superseded"
  assert_equal "$output" "superseded by TASK-successor-01"

  local doc2="$TEST_WORKSPACE/proj-cancelled.md"
  write_projection_fixture "$doc2" "cancelled"
  printf '%s\n' "- disposition: need lapsed" >> "$doc2"
  run run_projection "$doc2" "cancelled"
  assert_equal "$output" "need lapsed"
}

@test "projection is envelope-bounded: an outcome below ## Close-out is narrative" {
  local doc="$TEST_WORKSPACE/proj-outside-envelope.md"
  cat > "$doc" <<'EOF'
# TASK-proj-outside-envelope

- title: Stored title
- status: done
## Close-out
- outcome: completed below the envelope
EOF

  run run_projection "$doc" "done"
  assert_equal "$output" ""
}

@test "projection ignores an outcome that only exists in a fenced example" {
  local doc="$TEST_WORKSPACE/proj-fenced-outcome.md"
  cat > "$doc" <<'EOF'
# TASK-proj-fenced-outcome

- title: Stored title
- status: done
```markdown
- outcome: quoted outcome
```
EOF

  run run_projection "$doc" "done"
  assert_equal "$output" ""
}

@test "projection canonicalizes a multi-line outcome block byte-for-byte" {
  local doc="$TEST_WORKSPACE/proj-multiline.md"
  cat > "$doc" <<'EOF'
# TASK-proj-multiline

- title: Stored title
- status: done
- outcome:
  - Evidence: commit abc123 merged
  - Summary: all release-A gates green
EOF

  run run_projection "$doc" "done"
  assert_equal "$output" "Evidence: commit abc123 merged; Summary: all release-A gates green"
}

# --- writer: update_task_index derives rows from stored fields ---

@test "update_task_index derives the row summary from stored outcome, not the CLI title" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-cli-01" --task-title "CLI stale title" --task-status done --no-init >/dev/null 2>&1

  python3 - "$DOCS_ROOT/task/TASK-proj-cli-01.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("- outcome:\n", "- outcome: merged the gate\n")
open(p, "w").write(s)
PY

  # Re-run WITHOUT --task-title: the row must re-derive from the stored outcome, and the
  # CLI-passed title must not leak into the summary.
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-cli-01" --no-init >/dev/null 2>&1
  run grep "^- TASK-proj-cli-01 |" "$DOCS_ROOT/task/task-index.md"
  assert_equal "$output" "- TASK-proj-cli-01 | done | merged the gate"
}

@test "update_task_index derives the row status from the stored status" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-status-01" --task-title "Status fixture" --task-status planned --no-init >/dev/null 2>&1

  # Change the stored status to done and set an outcome, then re-run WITHOUT
  # --task-status: the row must follow the stored status (default in_progress must not
  # rewrite it), and move to the Done section.
  python3 - "$DOCS_ROOT/task/TASK-proj-status-01.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("- status: planned\n", "- status: done\n")
s = s.replace("- outcome:\n", "- outcome: status followed stored field\n")
open(p, "w").write(s)
PY

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-status-01" --no-init >/dev/null 2>&1
  run grep "^- TASK-proj-status-01 |" "$DOCS_ROOT/task/task-index.md"
  assert_equal "$output" "- TASK-proj-status-01 | done | status followed stored field"
}

@test "status default in_progress applies only at creation" {
  # Creation without --task-status -> in_progress.
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-default-01" --task-title "Default status" --no-init >/dev/null 2>&1
  run grep "^- status:" "$DOCS_ROOT/task/TASK-proj-default-01.md"
  assert_equal "$output" "- status: in_progress"

  # Update without --task-status: the persisted status is retained.
  python3 - "$DOCS_ROOT/task/TASK-proj-default-01.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("- status: in_progress\n", "- status: done\n")
open(p, "w").write(s)
PY
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-default-01" --no-init >/dev/null 2>&1
  run grep "^- status:" "$DOCS_ROOT/task/TASK-proj-default-01.md"
  assert_equal "$output" "- status: done"
}

@test "an existing title is never clobbered by the default on update" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-title-01" --task-title "Real title" --no-init >/dev/null 2>&1

  # Update with no --task-title: the stored title is retained.
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-title-01" --no-init >/dev/null 2>&1
  run grep "^- title:" "$DOCS_ROOT/task/TASK-proj-title-01.md"
  assert_equal "$output" "- title: Real title"
}

@test "an explicitly given title is persisted on update" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-title-02" --task-title "First title" --no-init >/dev/null 2>&1
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-title-02" --task-title "Second title" --no-init >/dev/null 2>&1
  run grep "^- title:" "$DOCS_ROOT/task/TASK-proj-title-02.md"
  assert_equal "$output" "- title: Second title"
}

# --- writer: --rebuild-task-index ---

@test "rebuild creates a new index with all six status sections" {
  rm -f "$DOCS_ROOT/task/task-index.md"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "rebuild-new-01" --task-title "New index" --task-status done --no-init >/dev/null 2>&1
  "$DOC_GARDEN" "$TEST_PROJECT" --rebuild-task-index --no-init >/dev/null 2>&1

  run grep -c '^## ' "$DOCS_ROOT/task/task-index.md"
  assert_equal "$output" "6"
  grep -q '^## Planned$' "$DOCS_ROOT/task/task-index.md"
  grep -q '^## In Progress$' "$DOCS_ROOT/task/task-index.md"
  grep -q '^## Blocked$' "$DOCS_ROOT/task/task-index.md"
  grep -q '^## Done$' "$DOCS_ROOT/task/task-index.md"
  grep -q '^## Superseded$' "$DOCS_ROOT/task/task-index.md"
  grep -q '^## Cancelled$' "$DOCS_ROOT/task/task-index.md"
}

@test "rebuild preserves comments, fenced examples and section headers" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "rebuild-preserve-01" --task-title "Preserve" --no-init >/dev/null 2>&1

  cat >> "$DOCS_ROOT/task/task-index.md" <<'EOF'
# A comment that must survive the rebuild
## In Progress

Row format (quoted example):

```
- TASK-quoted-01 | planned | this row must survive inside the fence
```
EOF

  "$DOC_GARDEN" "$TEST_PROJECT" --rebuild-task-index --no-init >/dev/null 2>&1

  grep -q "^# A comment that must survive the rebuild$" "$DOCS_ROOT/task/task-index.md"
  grep -q '^- TASK-quoted-01 | planned | this row must survive inside the fence$' "$DOCS_ROOT/task/task-index.md"
  grep -q '^## In Progress$' "$DOCS_ROOT/task/task-index.md"
  # The quoted row is documentation inside a fence; it must NOT be duplicated as a live row.
  run grep -c '^- TASK-quoted-01 |' "$DOCS_ROOT/task/task-index.md"
  assert_equal "$output" "1"
}

@test "rebuild sorts rows by task_ref lexicographically" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "zeta-01" --task-title "Zeta" --task-status planned --no-init >/dev/null 2>&1
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "alpha-01" --task-title "Alpha" --task-status planned --no-init >/dev/null 2>&1
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "mid-01" --task-title "Mid" --task-status planned --no-init >/dev/null 2>&1

  "$DOC_GARDEN" "$TEST_PROJECT" --rebuild-task-index --no-init >/dev/null 2>&1

  run grep '^- TASK-.* | planned |' "$DOCS_ROOT/task/task-index.md"
  assert_equal "$output" $'- TASK-alpha-01 | planned | Alpha\n- TASK-mid-01 | planned | Mid\n- TASK-zeta-01 | planned | Zeta'
}

@test "rebuild canonicalizes a multi-line outcome row byte-for-byte" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "rebuild-ml-01" --task-title "Multi-line" --task-status done --no-init >/dev/null 2>&1
  python3 - "$DOCS_ROOT/task/TASK-rebuild-ml-01.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("- outcome:\n", "- outcome:\n  - Evidence: commit abc123\n  - Summary: all gates green\n")
open(p, "w").write(s)
PY

  "$DOC_GARDEN" "$TEST_PROJECT" --rebuild-task-index --no-init >/dev/null 2>&1
  run grep '^- TASK-rebuild-ml-01 |' "$DOCS_ROOT/task/task-index.md"
  assert_equal "$output" "- TASK-rebuild-ml-01 | done | Evidence: commit abc123; Summary: all gates green"
}

@test "rebuild escapes pipes in row summaries" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "rebuild-pipe-01" --task-title "Pipe" --task-status done --no-init >/dev/null 2>&1
  python3 - "$DOCS_ROOT/task/TASK-rebuild-pipe-01.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("- outcome:\n", "- outcome: phase one | phase two\n")
open(p, "w").write(s)
PY

  "$DOC_GARDEN" "$TEST_PROJECT" --rebuild-task-index --no-init >/dev/null 2>&1
  run grep '^- TASK-rebuild-pipe-01 |' "$DOCS_ROOT/task/task-index.md"
  assert_equal "$output" "- TASK-rebuild-pipe-01 | done | phase one \| phase two"
}

@test "rebuild is idempotent: two consecutive rebuilds produce identical sha256" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "rebuild-idem-01" --task-title "Idempotent" --task-status done --no-init >/dev/null 2>&1
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "rebuild-idem-02" --task-title "Idempotent two" --task-status planned --no-init >/dev/null 2>&1

  "$DOC_GARDEN" "$TEST_PROJECT" --rebuild-task-index --no-init >/dev/null 2>&1
  local first_sha
  first_sha="$(sha256_file_ref "$DOCS_ROOT/task/task-index.md")"

  "$DOC_GARDEN" "$TEST_PROJECT" --rebuild-task-index --no-init >/dev/null 2>&1
  local second_sha
  second_sha="$(sha256_file_ref "$DOCS_ROOT/task/task-index.md")"

  assert_equal "$second_sha" "$first_sha"
}

# --- validator: check_task_index_projection ---

@test "validate_docs advisory flags a row summary that does not match the stored-field projection" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-mismatch-01" --task-title "Mismatch" --task-status done --no-init >/dev/null 2>&1
  # Leave the row stale: overwrite the Done row with the OLD CLI-title projection.
  perl -pi -e 's{^- TASK-proj-mismatch-01 \| done \| .*$}{- TASK-proj-mismatch-01 | done | stale cli title}' "$DOCS_ROOT/task/task-index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "task-index row summary for TASK-proj-mismatch-01 does not match the stored-field projection"
}

@test "validate_docs promoted strict fails on a row summary projection mismatch" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-mismatch-strict-01" --task-title "Mismatch strict" --task-status done --no-init >/dev/null 2>&1
  perl -pi -e 's{^- TASK-proj-mismatch-strict-01 \| done \| .*$}{- TASK-proj-mismatch-strict-01 | done | stale cli title}' "$DOCS_ROOT/task/task-index.md"

  run env CLOSE_RECORD_STRICT_PROMOTED=1 "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "task-index row summary for TASK-proj-mismatch-strict-01 does not match the stored-field projection"
}

@test "validate_docs accepts a row the rebuild just derived (writer and validator agree)" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-agree-01" --task-title "Agree" --task-status done --no-init >/dev/null 2>&1
  python3 - "$DOCS_ROOT/task/TASK-proj-agree-01.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("- outcome:\n", "- outcome:\n  - Evidence: commit abc\n  - Summary: agreed\n")
open(p, "w").write(s)
PY
  "$DOC_GARDEN" "$TEST_PROJECT" --rebuild-task-index --no-init >/dev/null 2>&1

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  refute_contains "$output" "task-index row summary for TASK-proj-agree-01 does not match"
}

@test "validate_docs plain strict run fails on a projection mismatch (Release C promotion is the default)" {
  # Release A/B: the index-projection rule was skipped under plain strict (switch
  # defaulted OFF). Release C flips the switch to default ON, so a plain strict run now
  # FAILS on a row-summary projection mismatch -- this test pins the promoted behavior
  # without exporting the switch.
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "proj-plain-01" --task-title "Plain" --task-status done --no-init >/dev/null 2>&1
  perl -pi -e 's{^- TASK-proj-plain-01 \| done \| .*$}{- TASK-proj-plain-01 | done | stale cli title}' "$DOCS_ROOT/task/task-index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "task-index row summary for TASK-proj-plain-01 does not match"
}
