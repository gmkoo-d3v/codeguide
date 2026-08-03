#!/usr/bin/env bats

load codeguide_helper

await_gate_route_slug() {
  printf "%s" "$1" | sed 's/[^A-Za-z0-9._-]/-/g'
}

write_await_gate_fixture() {
  local task_id="$1"
  local task_status="$2"
  local required_for="$3"
  local consumes_plan_ref="$4"
  local external_status="$5"
  local required_routes="$6"
  local result_ref="$7"
  local waiver_ref="$8"
  local waiver_reason="$9"
  local task_file="$DOCS_ROOT/task/TASK-${task_id}.md"
  local plan_version="v1.0"
  local plan_file="$DOCS_ROOT/plan/PLAN-${task_id}-${plan_version}.md"
  local orch_dir="$DOCS_ROOT/orchestration/${task_id}"
  local orch_file="$orch_dir/ORCH.md"

  cat > "$task_file" <<EOF
# TASK-${task_id}

- title: Await gate fixture
- objective: exercise external review await gate
- acceptance_criteria: validator emits the expected gate warning
- non_goals: production docs
- affected_modules: docs
- interfaces_changed: none
- data_migrations: none
- test_scope: validate_docs
- risks: low
- risk_level: low
- consumes_plan_ref: ${consumes_plan_ref}
- status: ${task_status}
- owner: test
- due_date:
- axis_why: verify await gate behavior
- axis_where: docs validation fixture
- axis_verify: bats
EOF

  cat > "$plan_file" <<EOF
# PLAN-${task_id}-${plan_version}

- task_id: ${task_id}
- plan_version: ${plan_version}
- objective: await gate fixture plan
- scope: validate_docs test
- assumptions: test fixture
- risks: low
- acceptance_signals: validator behavior observed
- stop_conditions: test done
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  mkdir -p "$orch_dir"
  cat > "$orch_file" <<EOF
# ORCH-${task_id}

- task_id: ${task_id}
- execution_mode: solo
- primary_author_tool: human
- review_mode: agy_subagents
- external_review_status: ${external_status}
- external_review_required_for: ${required_for}
- required_review_routes: ${required_routes}
- external_review_round: r01
- external_review_result_ref: ${result_ref}
- external_review_waiver_ref: ${waiver_ref}
- external_review_waiver_reason: ${waiver_reason}
- supervisor_agent:
- planner_agents:
- reviewer_agents:
- implementation_agents:
- validation_agents:
- owned_scopes:
- delegation_status: planned
- delegation_note: await gate fixture is solo
- risk_preflight_status: pass
- risk_preflight_recorded_by: main-thread
- risk_preflight_summary: no external side effect in fixture
- approval_required: false
- approval_ref: not_required
- approved_next_step: not_required
- last_updated: 2026-01-01T00:00:00Z
EOF

  printf '%s\n' "- TASK-${task_id} ${task_status}" >> "$DOCS_ROOT/task/task-index.md"
}

create_await_gate_result_dir() {
  local task_id="$1"
  local plan_version="${2:-v1.0}"
  local review_round="${3:-r01}"
  local result_dir="$DOCS_ROOT/orchestration/${task_id}/external-cli/${plan_version}/${review_round}"
  local route_spec
  local route
  local verdict
  local slug

  mkdir -p "$result_dir"
  shift 3
  for route_spec in "$@"; do
    route="${route_spec%=*}"
    verdict="${route_spec##*=}"
    slug="$(await_gate_route_slug "$route")"
    cat > "$result_dir/${slug}.response.md" <<EOF
# External Review ${slug}

- verdict: ${verdict}
- summary: fixture response
- strengths: fixture
- risks: fixture
- requested_changes: none
EOF
  done

  printf "%s\n" "docs/orchestration/${task_id}/external-cli/${plan_version}/${review_round}"
}

@test "validate_docs advisory warns when dependent external review is requested" {
  write_await_gate_fixture "await-gate-requested-01" "in_progress" "implementation_start" "PLAN-await-gate-requested-01-v1.0" "requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate not satisfied for TASK-await-gate-requested-01: external_review_status=requested"
}

@test "validate_docs advisory warns when dependent external review is not requested" {
  write_await_gate_fixture "await-gate-not-requested-01" "in_progress" "implementation_start" "PLAN-await-gate-not-requested-01-v1.0" "not_requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate not satisfied for TASK-await-gate-not-requested-01: external_review_status=not_requested"
}

@test "validate_docs advisory warns when dependent external review is blocked" {
  write_await_gate_fixture "await-gate-blocked-01" "in_progress" "implementation_start" "PLAN-await-gate-blocked-01-v1.0" "blocked" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate not satisfied for TASK-await-gate-blocked-01: external_review_status=blocked"
}

@test "validate_docs advisory warns when ingested review lacks required route accept" {
  local result_ref
  result_ref="$(create_await_gate_result_dir "await-gate-missing-route-01" "v1.0" "r01" "agy:current=accept" "claude:current=revise")"
  write_await_gate_fixture "await-gate-missing-route-01" "in_progress" "implementation_start" "PLAN-await-gate-missing-route-01-v1.0" "ingested" "agy:current, claude:current" "$result_ref" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate missing accepted route artifact for claude:current"
}

@test "validate_docs advisory passes when ingested review has all required route accepts" {
  local result_ref
  result_ref="$(create_await_gate_result_dir "await-gate-accept-01" "v1.0" "r01" "agy:current=accept" "claude:current=accept")"
  write_await_gate_fixture "await-gate-accept-01" "in_progress" "implementation_start" "PLAN-await-gate-accept-01-v1.0" "ingested" "agy:current, claude:current" "$result_ref" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "[WARN] external review await gate"
  assert_contains "$output" "[PASS] external review await gate satisfied for PLAN-await-gate-accept-01-v1.0"
}

@test "validate_docs advisory warns when waived review lacks ref or reason" {
  write_await_gate_fixture "await-gate-waived-missing-01" "in_progress" "implementation_start" "PLAN-await-gate-waived-missing-01-v1.0" "waived" "agy:current" "" "" "user approved waiver"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate waiver requires concrete external_review_waiver_ref and external_review_waiver_reason"
}

@test "validate_docs advisory passes when waived review has concrete ref and reason" {
  write_await_gate_fixture "await-gate-waived-ok-01" "in_progress" "implementation_start" "PLAN-await-gate-waived-ok-01-v1.0" "waived" "agy:current" "" "docs/decisions/decision-waive-01.md" "user accepted external review waiver for this implementation"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "[WARN] external review await gate"
  assert_contains "$output" "[PASS] external review await gate waived with concrete provenance"
}

@test "validate_docs advisory does not warn independent task when ORCH does not require implementation review" {
  write_await_gate_fixture "await-gate-independent-01" "in_progress" "close" "" "requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "[WARN] external review await gate"
}

@test "validate_docs advisory warns when dependent task misses external_review_status" {
  write_await_gate_fixture "await-gate-missing-status-01" "in_progress" "implementation_start" "PLAN-await-gate-missing-status-01-v1.0" "" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate requires external_review_status for TASK-await-gate-missing-status-01"
}

@test "validate_docs advisory warns when implementation-start review omits consumes_plan_ref" {
  write_await_gate_fixture "await-gate-no-consumes-01" "in_progress" "implementation_start" "" "requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate requires same-task consumes_plan_ref for TASK-await-gate-no-consumes-01"
}

@test "validate_docs advisory warns when external_review_status is outside allowlist enum" {
  write_await_gate_fixture "await-gate-invalid-status-01" "in_progress" "implementation_start" "PLAN-await-gate-invalid-status-01-v1.0" "skipped" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate has invalid external_review_status for TASK-await-gate-invalid-status-01: skipped"
}

@test "validate_docs advisory warns when external_review_required_for is outside allowlist enum" {
  write_await_gate_fixture "await-gate-invalid-required-for-01" "in_progress" "before_implementation" "PLAN-await-gate-invalid-required-for-01-v1.0" "not_requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] invalid orchestration.external_review_required_for value in "
  assert_contains "$output" ": before_implementation (allowed: plan_acceptance|implementation_start|commit|close)"
}

@test "validate_docs advisory warns when ingested result_ref directory is absent" {
  write_await_gate_fixture "await-gate-missing-dir-01" "in_progress" "implementation_start" "PLAN-await-gate-missing-dir-01-v1.0" "ingested" "agy:current" "docs/orchestration/await-gate-missing-dir-01/external-cli/v1.0/r01" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate result_ref directory missing or not a directory"
}

@test "validate_docs advisory warns when waived review uses placeholder values" {
  write_await_gate_fixture "await-gate-waived-placeholder-01" "in_progress" "implementation_start" "PLAN-await-gate-waived-placeholder-01-v1.0" "waived" "agy:current" "" "TBD" "TODO"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate waiver requires concrete external_review_waiver_ref and external_review_waiver_reason"
}

@test "validate_docs advisory warns when ingested review routes are empty or unparseable" {
  local result_ref
  result_ref="$(create_await_gate_result_dir "await-gate-empty-routes-01" "v1.0" "r01" "agy:current=accept")"
  write_await_gate_fixture "await-gate-empty-routes-01" "in_progress" "implementation_start" "PLAN-await-gate-empty-routes-01-v1.0" "ingested" "" "$result_ref" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate requires non-empty required_review_routes"
}

@test "validate_docs advisory warns when required review route is not registry resolvable" {
  local result_ref
  result_ref="$(create_await_gate_result_dir "await-gate-unknown-route-01" "v1.0" "r01")"
  write_await_gate_fixture "await-gate-unknown-route-01" "in_progress" "implementation_start" "PLAN-await-gate-unknown-route-01-v1.0" "ingested" "agy:not-a-real-route" "$result_ref" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] external review await gate required_review_routes must use registered colon route: agy:not-a-real-route"
}

@test "validate_docs rejects legacy root orchestration paths" {
  cat > "$DOCS_ROOT/orchestration/ORCH-legacy-01.md" <<'EOF'
# ORCH-legacy-01

- task_id: legacy-01
EOF
  mkdir -p "$DOCS_ROOT/orchestration/external-cli"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "legacy root orchestration file is not supported"
  assert_contains "$output" "legacy external CLI handoff root is not supported"
}

@test "validate_docs strict fails on an orphaned orchestration capsule with no matching task file" {
  mkdir -p "$DOCS_ROOT/orchestration/ghost-capsule-01"
  cat > "$DOCS_ROOT/orchestration/ghost-capsule-01/ORCH.md" <<'EOF'
# ORCH-ghost-capsule-01

- task_id: ghost-capsule-01
- execution_mode: solo
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "orphaned orchestration capsule with no matching task file"
  assert_contains "$output" "docs/orchestration/ghost-capsule-01"
  assert_contains "$output" "TASK-ghost-capsule-01.md"
}

@test "validate_docs advisory warns when an orchestration capsule is missing its task-index row" {
  cat > "$DOCS_ROOT/task/TASK-capsule-no-index-01.md" <<'EOF'
# TASK-capsule-no-index-01

- title: capsule missing its task-index row
- status: planned
- owner: test
EOF
  mkdir -p "$DOCS_ROOT/orchestration/capsule-no-index-01"
  cat > "$DOCS_ROOT/orchestration/capsule-no-index-01/ORCH.md" <<'EOF'
# ORCH-capsule-no-index-01

- task_id: capsule-no-index-01
- execution_mode: solo
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] orphaned orchestration capsule: task-index missing row for TASK-capsule-no-index-01"
  refute_contains "$output" "orphaned orchestration capsule with no matching task file"
}

@test "validate_docs advisory does not warn when an orchestration capsule is properly registered" {
  cat > "$DOCS_ROOT/task/TASK-capsule-ok-01.md" <<'EOF'
# TASK-capsule-ok-01

- title: capsule properly registered
- status: planned
- owner: test
EOF
  printf '%s\n' "- TASK-capsule-ok-01 planned" >> "$DOCS_ROOT/task/task-index.md"
  mkdir -p "$DOCS_ROOT/orchestration/capsule-ok-01"
  cat > "$DOCS_ROOT/orchestration/capsule-ok-01/ORCH.md" <<'EOF'
# ORCH-capsule-ok-01

- task_id: capsule-ok-01
- execution_mode: solo
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "orphaned orchestration capsule"
}

@test "validate_docs strict fails when docs/plan/_archive exists" {
  mkdir -p "$DOCS_ROOT/plan/_archive"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "physical archive directory violates the no-archive policy"
  assert_contains "$output" "docs/plan/_archive"
}

@test "validate_docs advisory warns when docs/task/_archive exists" {
  mkdir -p "$DOCS_ROOT/task/_archive"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] physical archive directory violates the no-archive policy"
  assert_contains "$output" "docs/task/_archive"
}

@test "validate_docs strict fails when docs/orchestration/_archive exists" {
  mkdir -p "$DOCS_ROOT/orchestration/_archive"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "physical archive directory violates the no-archive policy"
  assert_contains "$output" "docs/orchestration/_archive"
}

@test "validate_docs advisory does not warn about archive directories when none exist" {
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "violates the no-archive policy"
}

@test "validate_docs advisory warns when durable docs reference a gitignored tmp/ path" {
  cat > "$DOCS_ROOT/task/TASK-tmp-ref-fixture-01.md" <<'EOF'
# TASK-tmp-ref-fixture-01

- title: tmp reference fixture
- status: planned
- owner: test
- notes: see /tmp/scratch-notes.md for the working draft
EOF

  cat > "$DOCS_ROOT/plan/PLAN-tmp-ref-fixture-01-v1.0.md" <<'EOF'
# PLAN-tmp-ref-fixture-01-v1.0

- task_id: tmp-ref-fixture-01
- plan_version: v1.0
- objective: exercise tmp-reference detection
- assumptions: draft evidence lives at codeguide/tmp/plan-notes.md
EOF

  mkdir -p "$DOCS_ROOT/orchestration/tmp-ref-fixture-01"
  cat > "$DOCS_ROOT/orchestration/tmp-ref-fixture-01/INDEX.md" <<'EOF'
# Capsule Index

- see codeguide/tmp/index-draft.md for the working notes
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] docs reference a gitignored tmp/ path (${DOCS_ROOT}/task/TASK-tmp-ref-fixture-01.md:"
  assert_contains "$output" "[WARN] docs reference a gitignored tmp/ path (${DOCS_ROOT}/plan/PLAN-tmp-ref-fixture-01-v1.0.md:"
  assert_contains "$output" "[WARN] docs reference a gitignored tmp/ path (${DOCS_ROOT}/orchestration/tmp-ref-fixture-01/INDEX.md:"
}

@test "validate_docs strict mode does not flag gitignored tmp/ path references" {
  cat > "$DOCS_ROOT/task/TASK-tmp-ref-strict-01.md" <<'EOF'
# TASK-tmp-ref-strict-01

- title: tmp reference strict fixture
- status: planned
- owner: test
- notes: see /tmp/scratch-notes.md for the working draft
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "gitignored tmp/ path"
}

@test "validate_docs advisory does not warn about tmp/ path references inside a fenced code block" {
  cat > "$DOCS_ROOT/plan/PLAN-tmp-ref-fenced-01-v1.0.md" <<'EOF'
# PLAN-tmp-ref-fenced-01-v1.0

- task_id: tmp-ref-fenced-01
- plan_version: v1.0
- objective: fenced tmp reference should be skipped
```
example: /tmp/should-be-skipped.md
```
- assumptions: none
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "gitignored tmp/ path"
}

@test "validate_docs closes a tmp-scan fence only on a same-character marker" {
  # The third private fence grammar in the tree, and it carried the toggle-on-any-marker
  # bug that the recorded decision exists to end: a `~~~` inside a ``` example
  # -- a template quoting a template, which is what half this corpus is -- flipped the
  # state, so this rule reported a path the shared reader sees as fence content
  #
  cat > "$DOCS_ROOT/plan/PLAN-tmp-tilde-fence-01-v1.0.md" <<'EOF'
# PLAN-tmp-tilde-fence-01-v1.0

- task_id: tmp-tilde-fence-01
- plan_version: v1.0
- objective: a tilde marker inside a backtick fence is content, not a closer
- scope: fixture
- assumptions: none
- owner: test
- last_updated: 2026-01-01T00:00:00Z

```markdown
~~~
scratch lives at /tmp/example-scratch/run.log
~~~
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "gitignored tmp/ path (${DOCS_ROOT}/plan/PLAN-tmp-tilde-fence-01-v1.0.md:"

  # A longer opener is not closed by a shorter marker either (CommonMark, and the case
  # that makes a template-quoting-a-template swallow the rest of the document).
  cat > "$DOCS_ROOT/plan/PLAN-tmp-long-fence-01-v1.0.md" <<'EOF'
# PLAN-tmp-long-fence-01-v1.0

- task_id: tmp-long-fence-01
- plan_version: v1.0
- objective: a 3-backtick line does not close a 4-backtick opener
- scope: fixture
- assumptions: none
- owner: test
- last_updated: 2026-01-01T00:00:00Z

````markdown
```
scratch lives at /tmp/example-scratch/run.log
```
````
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "gitignored tmp/ path (${DOCS_ROOT}/plan/PLAN-tmp-long-fence-01-v1.0.md:"

  # Positive half: the same reference OUTSIDE the block is still reported, in the same
  # file, so this is fence tracking and not a blanket mute.
  cat >> "$DOCS_ROOT/plan/PLAN-tmp-tilde-fence-01-v1.0.md" <<'EOF'

Real reference: /tmp/really-outside/run.log
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] docs reference a gitignored tmp/ path (${DOCS_ROOT}/plan/PLAN-tmp-tilde-fence-01-v1.0.md:"
}

@test "validate_docs advisory completes on a multi-file corpus (ISSUE-20260802 crash regression)" {
  # Regression guard for the tracked issue: every other
  # fixture validates a near-empty scaffold, so the per-file nested process
  # substitutions in check_tmp_path_references never ran often enough to corrupt
  # the bash 3.2 heap and kill the run with a fatal signal in a later phase.
  # The trigger is the SIZE OF ITS SCAN LIST (task + plan + ORCH files), not the
  # task count: measured on the pre-fix function, 30 tasks (92 files) survived
  # and 45 tasks (137 files) died deterministically, so this fixture builds 50.
  # Tasks are `done` (not `planned`) on purpose: a terminal task pulls in the
  # plan/report/ORCH lineage checks, and the crash needed that per-task work in
  # addition to the long scan list.
  local i id
  for ((i=1; i<=50; i++)); do
    id="$(printf 'bulk-fixture-%03d' "$i")"
    cat > "$DOCS_ROOT/task/TASK-${id}.md" <<EOF
# TASK-${id}

- title: bulk corpus fixture ${i}
- status: done
- owner: test
- risk_level: low
- axis_why: fixture
- axis_where: fixture
- axis_verify: fixture
- last_updated: 2026-08-01T00:00:00Z
EOF
    cat > "$DOCS_ROOT/plan/PLAN-${id}-v1.0.md" <<EOF
# PLAN-${id}-v1.0

- task_id: ${id}
- plan_version: v1.0
- objective: bulk corpus fixture ${i}
- scope: fixture
- owner: test
- last_updated: 2026-08-01T00:00:00Z
EOF
    cat > "$DOCS_ROOT/report/PLAN-${id}-v1.0-review-claude-sonnet-5-r01.md" <<EOF
# PLAN-${id}-v1.0 review (claude)

- task_id: ${id}
- plan_version: v1.0
- evaluator: claude
- review_style: standard
- review_round: r01
- verdict: accept
- summary: fixture
- residual_risk: none
- last_updated: 2026-08-01T00:00:00Z
EOF
    mkdir -p "$DOCS_ROOT/orchestration/${id}"
    cat > "$DOCS_ROOT/orchestration/${id}/ORCH.md" <<EOF
# ORCH-${id}

- task_id: ${id}
- execution_mode: solo
- delegation_note: fixture
- last_updated: 2026-08-01T00:00:00Z
EOF
    printf -- '- TASK-%s | done | bulk corpus fixture %d\n' "$id" "$i" >> "$DOCS_ROOT/task/task-index.md"
  done

  # `env -i` is load-bearing, not hygiene: the crash is heap-layout sensitive and
  # bats' own environment masks it (a plain `run "$VALIDATE"` passes even against
  # the pre-fix function, while the identical corpus dies outside the harness).
  # Under a minimal environment the pre-fix function reproduces the fatal signal
  # inside bats, which is what makes this a real guard rather than a smoke test.
  run env -i PATH="$PATH" HOME="$HOME" bash "$VALIDATE" "$TEST_PROJECT" --mode advisory
  # The crash killed the shell mid-run: no [RESULT] line and a 128+signal status.
  [ "$status" -eq 0 ]
  assert_contains "$output" "[RESULT]"
}

@test "validate_docs advisory reports tmp and _archive references from the same corpus scan" {
  # The single-pass scan emits both finding classes from one awk invocation:
  # prove they do not shadow each other and that per-file fence state resets.
  cat > "$DOCS_ROOT/task/TASK-mixed-scan-01.md" <<'EOF'
# TASK-mixed-scan-01

- title: mixed scan fixture
- status: planned
- owner: test
- notes: see /tmp/scratch-notes.md for the working draft
EOF

  cat > "$DOCS_ROOT/plan/PLAN-mixed-scan-01-v1.0.md" <<'EOF'
# PLAN-mixed-scan-01-v1.0

- task_id: mixed-scan-01
- plan_version: v1.0
- objective: mixed scan fixture
- prior_round: docs/plan/_archive/PLAN-mixed-scan-01-v0.9.md
EOF

  # An unterminated fence in an EARLIER file must not silence a later file.
  cat > "$DOCS_ROOT/plan/PLAN-aaa-fence-leak-01-v1.0.md" <<'EOF'
# PLAN-aaa-fence-leak-01-v1.0

- task_id: aaa-fence-leak-01
- plan_version: v1.0
- objective: unterminated fence
```
still inside the fence at end of file
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] docs reference a gitignored tmp/ path (${DOCS_ROOT}/task/TASK-mixed-scan-01.md:"
  assert_contains "$output" "[WARN] docs reference a deleted _archive path (${DOCS_ROOT}/plan/PLAN-mixed-scan-01-v1.0.md:"
}

@test "validate_docs advisory reports both classes when one line matches tmp and _archive" {
  # The single-pass rewrite originally
  # used `next` between the two rules, which silently dropped the _archive finding
  # for any line that also matched tmp/. The independent audit of that fix caught
  # it; this pins the independence of the two classes.
  cat > "$DOCS_ROOT/task/TASK-dual-class-01.md" <<'EOF'
# TASK-dual-class-01

- title: dual class fixture
- status: planned
- owner: test
- note: see /tmp/scratch.md and docs/plan/_archive/PLAN-old-v0.9.md for the prior draft
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "docs reference a gitignored tmp/ path (${DOCS_ROOT}/task/TASK-dual-class-01.md:6)"
  assert_contains "$output" "docs reference a deleted _archive path (${DOCS_ROOT}/task/TASK-dual-class-01.md:6)"
}

@test "validate_docs strict mode fails on empty required fields" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "200" \
    --task-title "" \
    --no-init

  # The task file will have title: (empty because upsert_field skips it on new file with template value)
  # Let's manually clear the axis fields to test strict validation
  local task_file="$DOCS_ROOT/task/TASK-200.md"
  # Ensure axis fields exist but are empty
  if ! grep -q "^- axis_why:" "$task_file"; then
    echo "- axis_why:" >> "$task_file"
  fi
  sed -i.bak 's/^- axis_why:.*$/- axis_why:/' "$task_file"
  rm -f "${task_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "empty" || assert_contains "$output" "FAIL"
}

@test "validate_docs strict audits effect_map markers and confirmed fields" {
  local effect_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"
  mkdir -p "$(dirname "$effect_file")"
  cat > "$effect_file" <<'EOF'
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-user-100 begin -->
## SE-user-100

- record_id: SE-user-100
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: db_write
- statement: confirmed record missing evidence fields
- anchor_file: src/UserService.java
- anchor_symbol: UserRepository.save

<!-- shadow-effect-record:SE-user-100 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "confirmed record requires evidence_type"
  assert_contains "$output" "shadow effect_map"

  cat > "$effect_file" <<'EOF'
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-user-101 begin -->
## SE-user-101

- record_id: SE-user-101
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: db_write
- statement: confirmed deterministic code record has shallow evidence only
- anchor_file: src/UserService.java
- anchor_symbol: UserRepository.save
- evidence_type: deterministic_code
- evidence_ref: py.ast.call_match@v1

<!-- shadow-effect-record:SE-user-101 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "deterministic_code record requires evidence_rule_id"
  assert_contains "$output" "deterministic_code record requires evidence_probe_result_hash"

  cat > "$effect_file" <<'EOF'
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-user-102 begin -->
## SE-user-102

- record_id: SE-user-102
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: forged deterministic code metadata must still fail semantic checks
- anchor_file: src/UserService.java
- anchor_symbol: UserRepository.save
- evidence_type: deterministic_code
- evidence_ref: py.ast.call_match@v1
- evidence_rule_id: repo.write
- evidence_validator_kind: ast
- evidence_parser_backed: true
- evidence_parser_identity: shadow_evidence_probe.py:py.ast.call_match@v1:ast
- evidence_parser_content_hash: sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
- evidence_validator_result: matched
- evidence_source_ref: src/OtherService.java:9
- evidence_source_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_probe_result_ref: missing-probe.json
- evidence_probe_result_hash: sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

<!-- shadow-effect-record:SE-user-102 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "evidence_rule_id is not compatible with effect_type"
  assert_contains "$output" "anchor_file must match evidence ref path"
  assert_contains "$output" "probe artifact must exist"
}

@test "validate_docs strict audits deterministic_runtime envelope metadata" {
  local effect_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"
  local runtime_probe_file="$TEST_PROJECT/probe-results/runtime-probe.json"
  local runtime_line_probe_file="$TEST_PROJECT/probe-results/runtime-line-probe.json"
  local runtime_selected_probe_file="$TEST_PROJECT/probe-results/runtime-selected-probe.json"
  local runtime_json_event='{"event":"user.cache.evict","userId":42,"timestamp":"2026-05-02T00:00:00Z"}'
  local runtime_probe_hash
  local runtime_line_probe_hash
  local runtime_selected_probe_hash
  local runtime_line_hash
  local runtime_selected_hash
  local setter_module_hash

  mkdir -p "$(dirname "$effect_file")" "$(dirname "$runtime_probe_file")" "$TEST_PROJECT/logs"
  printf '%s\n' "event=user.cache.evict" > "$TEST_PROJECT/logs/runtime.trace"
  printf '%s\n' "$runtime_json_event" > "$TEST_PROJECT/logs/runtime-json.trace"
  printf '{"status":"pass"}\n' > "$runtime_probe_file"
  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime.trace" \
    --trace-event "event=user.cache.evict" \
    --hash-input-scope "line_range" \
    --line-range-start 1 \
    --line-range-end 1 > "$runtime_line_probe_file"
  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime-json.trace" \
    --trace-event "$runtime_json_event" \
    --hash-input-scope "selected_fields" \
    --selected-field "event" \
    --selected-field "userId" > "$runtime_selected_probe_file"
  runtime_probe_hash="$(sha256_file_ref "$runtime_probe_file")"
  runtime_line_probe_hash="$(sha256_file_ref "$runtime_line_probe_file")"
  runtime_selected_probe_hash="$(sha256_file_ref "$runtime_selected_probe_file")"
  runtime_line_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact_hash"])' "$runtime_line_probe_file")"
  runtime_selected_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact_hash"])' "$runtime_selected_probe_file")"
  setter_module_hash="$(sha256_file_ref "$SHADOW_USER_DECISION")"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-100 begin -->
## SE-runtime-100

- record_id: SE-runtime-100
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Runtime evidence without envelope metadata must fail strict docs validation.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_scenario_ref: scenario:user-update-cache
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-100 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "deterministic_runtime record requires evidence_artifact_media_type"
  assert_contains "$output" "deterministic_runtime record requires evidence_ignored_nondeterministic_fields"
  assert_contains "$output" "deterministic_runtime record requires evidence_scenario_scope"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-105 begin -->
## SE-runtime-105

- record_id: SE-runtime-105
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Malformed runtime scenario fit metadata must fail strict docs validation.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: none
- evidence_hash_input_scope: whole_artifact
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: no
- evidence_setter_symbol_path: 1Invalid.setter
- evidence_setter_module_hash: sha256:x
- evidence_expiry_or_invalidation_rule: automatic
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-105 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "deterministic_runtime evidence_scenario_scope must match"
  assert_contains "$output" "deterministic_runtime evidence_setter_symbol_path must match"
  assert_contains "$output" "deterministic_runtime evidence_setter_module_hash must be sha256"
  assert_contains "$output" "deterministic_runtime evidence_expiry_or_invalidation_rule must be timestamp, binding_change, or manual_revocation"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-106 begin -->
## SE-runtime-106

- record_id: SE-runtime-106
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Rendered runtime line-range evidence should validate with scoped artifact hashing.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: $runtime_line_hash
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: custom-declared
- evidence_canonical_output_type: text
- evidence_hash_input_scope: line_range
- evidence_line_range: {"end":1,"start":1}
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-line-probe.json
- evidence_probe_result_hash: $runtime_line_probe_hash

<!-- shadow-effect-record:SE-runtime-106 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-108 begin -->
## SE-runtime-108

- record_id: SE-runtime-108
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Rendered runtime selected-fields evidence must reject duplicate field names.
- anchor_file: logs/runtime-json.trace
- anchor_line: 1
- anchor_symbol: $runtime_json_event
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime-json.trace:1
- evidence_artifact_hash: $runtime_selected_hash
- evidence_artifact_media_type: application/json
- evidence_encoding: utf-8
- evidence_canonicalization: rfc8785
- evidence_hash_input_scope: selected_fields
- evidence_selected_fields: ["event","event"]
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-selected-probe.json
- evidence_probe_result_hash: $runtime_selected_probe_hash

<!-- shadow-effect-record:SE-runtime-108 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "deterministic_runtime evidence_selected_fields must not contain duplicate field names"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-109 begin -->
## SE-runtime-109

- record_id: SE-runtime-109
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Rendered runtime selected-fields evidence must reject nested field names.
- anchor_file: logs/runtime-json.trace
- anchor_line: 1
- anchor_symbol: $runtime_json_event
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime-json.trace:1
- evidence_artifact_hash: $runtime_selected_hash
- evidence_artifact_media_type: application/json
- evidence_encoding: utf-8
- evidence_canonicalization: rfc8785
- evidence_hash_input_scope: selected_fields
- evidence_selected_fields: ["payload.event"]
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-selected-probe.json
- evidence_probe_result_hash: $runtime_selected_probe_hash

<!-- shadow-effect-record:SE-runtime-109 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "deterministic_runtime evidence_selected_fields supports only top-level field names"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-107 begin -->
## SE-runtime-107

- record_id: SE-runtime-107
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Rendered runtime selected-fields evidence should validate with scoped artifact hashing.
- anchor_file: logs/runtime-json.trace
- anchor_line: 1
- anchor_symbol: $runtime_json_event
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime-json.trace:1
- evidence_artifact_hash: $runtime_selected_hash
- evidence_artifact_media_type: application/json
- evidence_encoding: utf-8
- evidence_canonicalization: rfc8785
- evidence_hash_input_scope: selected_fields
- evidence_selected_fields: ["event","userId"]
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-selected-probe.json
- evidence_probe_result_hash: $runtime_selected_probe_hash

<!-- shadow-effect-record:SE-runtime-107 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-101 begin -->
## SE-runtime-101

- record_id: SE-runtime-101
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Binary RFC8785 runtime envelope must fail the strict matrix.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: application/octet-stream
- evidence_encoding: binary
- evidence_canonicalization: rfc8785
- evidence_hash_input_scope: whole_artifact
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-101 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "deterministic_runtime evidence envelope is not supported by the v1 validity matrix"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-102 begin -->
## SE-runtime-102

- record_id: SE-runtime-102
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Non-custom runtime envelope must reject canonical_output_type.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: none
- evidence_canonical_output_type: text
- evidence_hash_input_scope: whole_artifact
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-102 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "evidence_canonical_output_type is only valid for custom-declared canonicalization"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-103 begin -->
## SE-runtime-103

- record_id: SE-runtime-103
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Whole-artifact runtime envelope must not ignore fields without custom canonicalization.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: none
- evidence_hash_input_scope: whole_artifact
- evidence_ignored_nondeterministic_fields: ["timestamp"]
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-103 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "evidence_ignored_nondeterministic_fields must be [] for whole_artifact unless canonicalization is custom-declared"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-104 begin -->
## SE-runtime-104

- record_id: SE-runtime-104
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Custom textual line-range runtime envelope is declared by the matrix but not implemented by runtime trace hashing.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: custom-declared
- evidence_canonical_output_type: text
- evidence_hash_input_scope: line_range
- evidence_ignored_nondeterministic_fields: []
- evidence_line_range: {"end":1,"start":1}
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-104 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "deterministic_runtime evidence_artifact_hash must match scoped trace artifact"
}

@test "validate_docs strict accepts canonical probe coverage for valid effect_map evidence" {
  local effect_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"
  local source_file="$TEST_PROJECT/src/app.py"
  local probe_file="$TEST_PROJECT/probe-results/code-probe.json"
  local source_hash
  local parser_identity
  local parser_content_hash
  local probe_hash

  mkdir -p "$(dirname "$effect_file")" "$(dirname "$source_file")" "$(dirname "$probe_file")"
  cat > "$source_file" <<'EOF'
def handler(repository, user):
    repository.save(user)
EOF
  source_hash="$(sha256_file_ref "$source_file")"
  parser_identity="$(parser_identity_ref "py.ast.call_match@v1" "ast")"
  parser_content_hash="$(sha256_file_ref "$SHADOW_PROBE")"
  cat > "$probe_file" <<EOF
{"status":"pass","probe_status":"pass","fact_status":"deterministic_evidence","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","evidence_field":"validator_result","validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  probe_hash="$(sha256_file_ref "$probe_file")"
  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-user-103 begin -->
## SE-user-103

- record_id: SE-user-103
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: db_write
- statement: Repository save is backed by canonical parser evidence.
- anchor_file: src/app.py
- anchor_symbol: repository.save
- evidence_type: deterministic_code
- evidence_ref: py.ast.call_match@v1
- evidence_rule_id: repo.write
- evidence_validator_kind: ast
- evidence_parser_backed: true
- evidence_parser_identity: $parser_identity
- evidence_parser_content_hash: $parser_content_hash
- evidence_validator_result: matched
- evidence_source_ref: src/app.py:2
- evidence_source_hash: $source_hash
- evidence_probe_result_ref: probe-results/code-probe.json
- evidence_probe_result_hash: $probe_hash

<!-- shadow-effect-record:SE-user-103 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow effect_map records valid"
}

@test "validate_docs strict audits review_queue metadata" {
  local queue_file="$DOCS_ROOT/report/shadow-review-queue.md"
  cat > "$queue_file" <<'EOF'
# Shadow Evidence Review Queue

- doc_role: review_queue
- task_id: shadow-effect-map-01
- generated_by: shadow_review_queue.py
- generated_at: 2026-05-03T00:00:00Z
- writes_shadow_docs: false
- auto_promotes_facts: false
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "ttl_days"
}

@test "validate_docs strict allows mixed review_queue with deferred and bounded question" {
  local queue_file="$DOCS_ROOT/report/shadow-review-queue.md"
  cat > "$queue_file" <<'EOF'
# Shadow Evidence Review Queue

- doc_role: review_queue
- task_id: shadow-effect-map-01
- generated_by: shadow_review_queue.py
- generated_at: 2026-05-03T00:00:00Z
- ttl_days: 7
- writes_shadow_docs: false
- auto_promotes_facts: false
- input_records: 2
- max_questions: 1
- question_count: 1

## Evidence Candidates

- id: QE-001
  status: pass
  evidence_ref: jpa.repository.save@v1
  evidence_type: code_call
  strength: source_probe
  source_ref: unknown
  question_state: deferred_missing_context
  missing_question_context: source_ref_or_trace_ref
- id: QE-002
  status: fail
  evidence_ref: py.ast.call_match@v1
  evidence_type: code_call
  strength: parser_backed
  source_ref: src/app.py:4
  question_state: ready

## Review Questions

- id: RQ-001
  evidence_ref: QE-002
  priority: medium
  question: Should missing evidence stay unknown?
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow review_queue source refs are bounded"
}

@test "validate_docs strict fails when policy rule registry has no mappings" {
  cat > "$DOCS_ROOT/policy/shadow-rule-registry.md" <<'EOF'
# Shadow Rule Registry

- registry_id: shadow-rule-registry
- registry_version: 1
- status: active-draft
- linked_task: TASK-shadow-effect-map-01
- linked_decisions: decision-shadow-practical-contract-01
- purpose: empty registry should fail
- last_updated: 2026-04-30T13:49:45Z

## Promotion Gates

```yaml
promotion_gates:
  regex_only:
    max_effective_risk: medium
  high_or_critical:
    requires_one_of:
      - parser_backed_validator
  unknown_defaults:
    unlisted_rule: unknown
    unlisted_boundary: unknown
    unmapped_stack: unknown
    unmapped_evidence_type: unknown
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "shadow rule registry missing rules block" || assert_contains "$output" "must contain at least one rule id mapping"
}

@test "validate_docs strict fails when rule registry has rule ids but no primary validator mappings" {
  # Deliberately narrower than the "no mappings" fixture above: this keeps at
  # least one top-level rule id AND at least one allowed_effect_types line so
  # rule_count/effect_type_count stay non-zero (both of those grep|wc
  # pipelines are unprotected under `set -o pipefail` and abort the whole
  # script on a zero-match grep -- a real crash in the product code, not a
  # fixture problem; see the flagged follow-up). Only "primary:" lines are
  # stripped, which zeroes primary_count via collect_rule_registry_refs's own
  # `|| true`-guarded pipeline, so this specific fail() path is reachable.
  perl -0pi -e 's/^[ \t]+primary:.*\n//gm' "$DOCS_ROOT/policy/shadow-rule-registry.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "must contain at least one primary validator mapping"
  # Full attributable literal for check_rule_registry_has_mappings
  # (rule-coverage matrix arbiter).
  assert_contains "$output" "shadow rule registry must contain at least one primary validator mapping: "
}

@test "validate_docs strict completes and cleanly fails when the rule registry rules block is present but has zero rule id mappings" {
  # Regression for check_rule_registry_has_mappings's rule_count pipeline
  # (scripts/validate_docs.d/20-rules-shadow.sh): `grep | grep -Ev | wc -l | tr -d ' '`
  # had no `|| true` guard, unlike the sibling collect_rule_registry_refs
  # pipeline. Under `set -euo pipefail`, a "rules:" block that legitimately
  # declares its structure but contains zero rule-id mapping lines makes the
  # first grep's no-match exit (1) propagate through the pipe and abort the
  # whole validator right after the "declares rules block" PASS line, so the
  # designed clean fail() below never ran. This fixture keeps "rules:" present
  # (structure intact) but empty, isolating that exact zero-match path.
  cat > "$DOCS_ROOT/policy/shadow-rule-registry.md" <<'EOF'
# Shadow Rule Registry

- registry_id: shadow-rule-registry
- registry_version: 1
- status: active-draft
- linked_task: TASK-shadow-effect-map-01
- linked_decisions: decision-shadow-practical-contract-01
- purpose: rules block present but empty must yield a clean fail, not a crash
- last_updated: 2026-04-30T13:49:45Z

## Contract

- Rule ids not listed here cannot produce confirmed shadow facts.

```yaml
rules: {}
```

```yaml
promotion_gates:
  regex_only:
    max_effective_risk: medium
    evidence_field: fallback_result
    forbidden_field: validator_result
  high_or_critical:
    requires_one_of:
      - parser_backed_validator
      - test_assertion
      - runtime_trace
      - valid_waiver
  unknown_defaults:
    unlisted_rule: unknown
    unlisted_boundary: unknown
    unmapped_stack: unknown
    unmapped_evidence_type: unknown
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "shadow rule registry declares rules block"
  # Full attributable literal for check_rule_registry_has_mappings.
  assert_contains "$output" "shadow rule registry must contain at least one rule id mapping: "
  # Proves the run reached the end instead of aborting mid-pipeline.
  assert_contains "$output" "[RESULT]"
}

@test "validate_docs strict completes and cleanly fails when a rule id has zero allowed_effect_types mappings" {
  # Regression for check_rule_registry_has_mappings's effect_type_count
  # pipeline (scripts/validate_docs.d/20-rules-shadow.sh): `grep | wc -l | tr -d ' '`
  # had no `|| true` guard. Under `set -euo pipefail`, a rule id with zero
  # `allowed_effect_types:` lines anywhere in the file makes that grep's
  # no-match exit (1) propagate through the pipe and abort the validator
  # before its designed `effect_type_count < rule_count` fail() could run.
  # This fixture keeps one real rule id (so rule_count is non-zero) but
  # strips its allowed_effect_types line, isolating that exact zero-match
  # path from the rule_count one covered by the test above.
  cat > "$DOCS_ROOT/policy/shadow-rule-registry.md" <<'EOF'
# Shadow Rule Registry

- registry_id: shadow-rule-registry
- registry_version: 1
- status: active-draft
- linked_task: TASK-shadow-effect-map-01
- linked_decisions: decision-shadow-practical-contract-01
- purpose: a rule id with no allowed_effect_types must yield a clean fail, not a crash
- last_updated: 2026-04-30T13:49:45Z

## Contract

- Rule ids not listed here cannot produce confirmed shadow facts.

```yaml
rules:
  repo.write:
    validators_by_stack:
      spring_boot_jpa:
        code_call:
          primary: jpa.repository.save@v1
          fallback: java.regex.repository_save_call@v1
          fallback_max_risk: medium
```

```yaml
promotion_gates:
  regex_only:
    max_effective_risk: medium
    evidence_field: fallback_result
    forbidden_field: validator_result
  high_or_critical:
    requires_one_of:
      - parser_backed_validator
      - test_assertion
      - runtime_trace
      - valid_waiver
  unknown_defaults:
    unlisted_rule: unknown
    unlisted_boundary: unknown
    unmapped_stack: unknown
    unmapped_evidence_type: unknown
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "shadow rule registry contains rule id mappings (1)"
  # Full attributable literal for check_rule_registry_has_mappings.
  assert_contains "$output" "shadow rule registry must declare allowed_effect_types for every rule (0/1): "
  # Proves the run reached the end instead of aborting mid-pipeline.
  assert_contains "$output" "[RESULT]"
}

@test "validate_docs strict fails on invalid policy fallback risk enum" {
  sed -i.bak 's/max_promotion_risk: medium/max_promotion_risk: extreme/' "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  rm -f "$DOCS_ROOT/policy/shadow-regex-patterns.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "max_promotion_risk must be low|medium"
}

@test "validate_docs strict fails when policy promotion gate contract drifts" {
  sed -i.bak 's/forbidden_field: validator_result/forbidden_field: claim_result/' "$DOCS_ROOT/policy/shadow-rule-registry.md"
  rm -f "$DOCS_ROOT/policy/shadow-rule-registry.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "regex_only.forbidden_field must be validator_result"
}

@test "validate_docs strict fails when promotion gate token appears only outside scoped block" {
  sed -i.bak 's/max_effective_risk: medium/max_effective_risk: high/' "$DOCS_ROOT/policy/shadow-rule-registry.md"
  rm -f "$DOCS_ROOT/policy/shadow-rule-registry.md.bak"
  cat >> "$DOCS_ROOT/policy/shadow-rule-registry.md" <<'EOF'

<!-- misleading example: max_effective_risk: medium -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "regex_only.max_effective_risk must be medium"
}

@test "validate_docs strict fails when fallback mapping lacks its own cap" {
  perl -0pi -e 's/\n          fallback_max_risk: medium//' "$DOCS_ROOT/policy/shadow-rule-registry.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "fallback mapping missing fallback_max_risk"
}

@test "validate_docs strict fails when validator evidence type mismatches rule evidence branch" {
  perl -0pi -e 's/primary: jpa\.repository\.save\@v1/primary: any.runtime.trace\@v1/' "$DOCS_ROOT/policy/shadow-rule-registry.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "primary validator evidence_type mismatch"
}

@test "validate_docs strict fails when rule registry primary reference is not a declared catalog id" {
  # A primary ref pointing at an id that is not in shadow-validator-catalog.md's
  # validators block: check_rule_registry_mapping_contracts is a no-op for an
  # unknown id (its evidence_type-mismatch check only fires for ids that ARE
  # in the catalog), so this isolates check_rule_registry_refs_exist.
  perl -0pi -e 's/primary: jpa\.repository\.save\@v1/primary: jpa.repository.save_missing\@v1/' "$DOCS_ROOT/policy/shadow-rule-registry.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "jpa.repository.save_missing@v1"
  # Full attributable literal for check_rule_registry_refs_exist
  # (rule-coverage matrix arbiter).
  assert_contains "$output" "rule registry references unknown "
  assert_contains "$output" "rule registry references unknown primary validator catalog id: jpa.repository.save_missing@v1"
}

@test "validate_docs strict fails when policy roots leave fenced yaml blocks" {
  perl -0pi -e 's/```yaml\nvalidators:/```text\nvalidators:/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "must define validators inside a fenced yaml block"
}

@test "validate_docs strict fails when validator catalog probe coverage metadata is missing" {
  perl -0pi -e 's/\n  source_probe_only:.*//' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "must declare source_probe_only"
  # Full attributable literal for check_catalog_probe_coverage (rule-coverage
  # matrix arbiter). Deliberately NOT the "implemented_primary_v1 id must be
  # declared/implemented..." family: those exact literals are ALSO emitted
  # independently by shadow_policy_loader.py's parity_diagnostics (wrapped by
  # check_policy_loader_contract), so asserting on them would still pass with
  # check_catalog_probe_coverage's own body neutered -- a cosmetic match. This
  # "must declare source_probe_only (" literal (with the trailing catalog_file
  # paren) has no python-side counterpart: shadow_policy_loader.py's
  # equivalent message ends at "source_probe_only" with no trailing "(", so it
  # cannot satisfy this candidate.
  assert_contains "$output" "shadow validator catalog must declare source_probe_only ("
}

@test "validate_docs strict fails when catalog coverage id is undeclared" {
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, py.missing_validator\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "implemented_primary_v1 id must be declared in validators block"
}

@test "validate_docs strict fails when catalog claims unimplemented probe primary" {
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, sql.write_call\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "implemented_primary_v1 id must be implemented by shadow_evidence_probe.py"
}

@test "validate_docs strict ignores validator ids declared outside validators block" {
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, py.outside_block\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  cat >> "$DOCS_ROOT/policy/shadow-validator-catalog.md" <<'EOF'

## Non Validator Example

```yaml
examples:
  py.outside_block@v1:
    evidence_type: code_call
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "implemented_primary_v1 id must be declared in validators block"
}

@test "validate_docs strict fails when adapter metadata drifts from catalog" {
  perl -0pi -e 's/(py\.ast\.call_match\@v1:\n\s+)evidence_type: code_call/${1}evidence_type: runtime_trace/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "evidence_type must match AdapterRegistry"
  # Same fixture also exercises check_policy_loader_contract: the strict
  # policy-loader parity check (shadow_policy_loader.py --check-parity)
  # surfaces this exact drift through its own fail() wrapper. Full
  # attributable literal (rule-coverage matrix arbiter).
  assert_contains "$output" "shadow policy loader strict contract failed: "
}

@test "validate_docs strict fails when fallback regex evidence type mismatches rule evidence branch" {
  perl -0pi -e 's/target: code_call/target: annotation/' "$DOCS_ROOT/policy/shadow-regex-patterns.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "fallback regex evidence_type mismatch"
}

@test "validate_docs advisory warns when supervisor_subagents ORCH capsule has no agent fields or delegation_status" {
  cat > "$DOCS_ROOT/task/TASK-orch-contradiction-01.md" <<'EOF'
# TASK-orch-contradiction-01

- title: ORCH semantic contradiction fixture
- status: planned
- owner: test
EOF
  printf '%s\n' "- TASK-orch-contradiction-01 planned" >> "$DOCS_ROOT/task/task-index.md"

  mkdir -p "$DOCS_ROOT/orchestration/orch-contradiction-01"
  cat > "$DOCS_ROOT/orchestration/orch-contradiction-01/ORCH.md" <<'EOF'
# ORCH-orch-contradiction-01

- task_id: orch-contradiction-01
- execution_mode: supervisor_subagents
- delegation_status:
- planner_agents:
- reviewer_agents:
- implementation_agents:
- validation_agents:
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] orchestration execution_mode=supervisor_subagents requires at least one non-empty agent field (planner_agents/reviewer_agents/implementation_agents/validation_agents) for TASK-orch-contradiction-01"
  assert_contains "$output" "[WARN] orchestration execution_mode=supervisor_subagents requires a non-empty delegation_status for TASK-orch-contradiction-01"
}

@test "validate_docs advisory warns when an ingested ORCH capsule lacks required_review_routes or external_review_result_ref" {
  write_await_gate_fixture "orch-ingested-contradiction-01" "planned" "" "" "ingested" "" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] orchestration external_review_status=ingested requires a non-empty required_review_routes for TASK-orch-ingested-contradiction-01"
  assert_contains "$output" "[WARN] orchestration external_review_status=ingested requires a non-empty external_review_result_ref for TASK-orch-ingested-contradiction-01"
}

@test "validate_docs advisory does not warn when ORCH capsule fields are mutually consistent" {
  cat > "$DOCS_ROOT/task/TASK-orch-consistent-01.md" <<'EOF'
# TASK-orch-consistent-01

- title: ORCH semantic consistency fixture
- status: planned
- owner: test
EOF
  printf '%s\n' "- TASK-orch-consistent-01 planned" >> "$DOCS_ROOT/task/task-index.md"

  mkdir -p "$DOCS_ROOT/orchestration/orch-consistent-01"
  cat > "$DOCS_ROOT/orchestration/orch-consistent-01/ORCH.md" <<'EOF'
# ORCH-orch-consistent-01

- task_id: orch-consistent-01
- execution_mode: supervisor_subagents
- delegation_status: active
- planner_agents: planner-1
- reviewer_agents:
- implementation_agents:
- validation_agents:
- external_review_status: ingested
- required_review_routes: agy:current
- external_review_result_ref: docs/orchestration/orch-consistent-01/external-cli/v1.0/r01
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "execution_mode=supervisor_subagents requires"
  refute_contains "$output" "external_review_status=ingested requires"
}

@test "validate_docs strict mode does not apply ORCH semantic-contradiction checks" {
  cat > "$DOCS_ROOT/task/TASK-orch-contradiction-strict-01.md" <<'EOF'
# TASK-orch-contradiction-strict-01

- title: ORCH semantic contradiction strict-tier fixture
- status: planned
- owner: test
EOF
  printf '%s\n' "- TASK-orch-contradiction-strict-01 planned" >> "$DOCS_ROOT/task/task-index.md"

  mkdir -p "$DOCS_ROOT/orchestration/orch-contradiction-strict-01"
  cat > "$DOCS_ROOT/orchestration/orch-contradiction-strict-01/ORCH.md" <<'EOF'
# ORCH-orch-contradiction-strict-01

- task_id: orch-contradiction-strict-01
- execution_mode: supervisor_subagents
- delegation_status:
- planner_agents:
- reviewer_agents:
- implementation_agents:
- validation_agents:
- external_review_status: ingested
- required_review_routes:
- external_review_result_ref:
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "execution_mode=supervisor_subagents requires"
  refute_contains "$output" "external_review_status=ingested requires"
}

@test "validate_docs strict fails when supervisor_subagents orchestration fields are blank" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-strict-01" \
    --task-title "Orchestration strict test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-orch-strict-01-v1.0.md" <<'EOF'
# PLAN-orch-strict-01-v1.0

- task_id: orch-strict-01
- plan_version: v1.0
- objective: validate orchestration strictness
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation fails on blank delegated ownership
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "planner_agents" || assert_contains "$output" "implementation_agents" || assert_contains "$output" "validation_agents"
}

@test "validate_docs strict fails when delegated orchestration preflight is blocked" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-preflight-01" \
    --task-title "Orchestration preflight strict test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-orch-preflight-01-v1.0.md" <<'EOF'
# PLAN-orch-preflight-01-v1.0

- task_id: orch-preflight-01
- plan_version: v1.0
- objective: validate orchestration preflight strictness
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation fails on blocked preflight
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local orch_file="$DOCS_ROOT/orchestration/orch-preflight-01/ORCH.md"
  perl -0pi -e 's/^- risk_preflight_status: pass$/- risk_preflight_status: approval_required/m; s/^- approval_required: false$/- approval_required: true/m; s/^- approval_ref:.*$/- approval_ref: user-approval-pending-001/m; s/^- approved_next_step:.*$/- approved_next_step: await user approval/m' "$orch_file"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "orchestration risk preflight must be pass or approved"
  # Full attributable literal for check_orchestration_file_for_task
  # (rule-coverage matrix arbiter): includes the rest of the leading literal
  # that the fragment above truncates before the $orchestration_file expansion.
  assert_contains "$output" "orchestration risk preflight must be pass or approved before delegated/external review: "
}

@test "validate_docs strict fails when approved preflight leaves approval_required false" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-approved-01" \
    --task-title "Approved preflight consistency test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-001" \
    --approved-next-step "run delegated review round r01" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-orch-approved-01-v1.0.md" <<'EOF'
# PLAN-orch-approved-01-v1.0

- task_id: orch-approved-01
- plan_version: v1.0
- objective: validate approved preflight field consistency
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation fails on approved/false mismatch
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local orch_file="$DOCS_ROOT/orchestration/orch-approved-01/ORCH.md"
  perl -0pi -e 's/^- approval_required: true$/- approval_required: false/m' "$orch_file"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "risk_preflight_status=approved requires approval_required=true"
}

@test "validate_docs strict fails when supervisor_subagents task has no evaluator report" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "report-strict-01" \
    --task-title "Report strict test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-report-strict-01-v1.0.md" <<'EOF'
# PLAN-report-strict-01-v1.0

- task_id: report-strict-01
- plan_version: v1.0
- objective: validate evaluator report enforcement
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation fails on missing evaluator report
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing evaluator report for active task TASK-report-strict-01"
}

@test "validate_docs advisory mode passes with empty fields (warns only)" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "201" \
    --task-title "Advisory test" \
    --no-init

  local task_file="$DOCS_ROOT/task/TASK-201.md"
  if ! grep -q "^- axis_why:" "$task_file"; then
    echo "- axis_why:" >> "$task_file"
  fi

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  # advisory mode should exit 0 even with warnings
  [ "$status" -eq 0 ]
}

### ========== Empty shadow graph gate (content-based, replaces timestamp heuristic) ==========

make_empty_graph_gate_source_repo() {
  local source_repo="$1"

  mkdir -p "$source_repo"
  git -C "$source_repo" init --quiet
  git -C "$source_repo" config user.email "test@test.com"
  git -C "$source_repo" config user.name "test"
  printf 'print("hi")\n' > "$source_repo/app.py"
  git -C "$source_repo" add app.py
  git -C "$source_repo" commit -q -m "init"
}

@test "validate_docs strict fails on an entirely empty shadow graph when a source repo is reachable" {
  local source_repo="$TEST_WORKSPACE/gate-source-strict"
  make_empty_graph_gate_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "[FAIL] shadow graph is empty"
  assert_contains "$output" "shadow_coverage_report.py"
  # Full attributable literal (rule-coverage matrix arbiter): the entire
  # fail() message has no $ interpolation, so this is the whole candidate.
  assert_contains "$output" "shadow graph is empty: no bucket declares a unit and no shadow doc declares source_of_truth_paths, though the source repo has trackable files to document. Author shadow units; see shadow_coverage_report.py for the coverage gap"
}

@test "validate_docs advisory warns (does not fail) on an entirely empty shadow graph" {
  local source_repo="$TEST_WORKSPACE/gate-source-advisory"
  make_empty_graph_gate_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] shadow graph is empty"
}

@test "validate_docs shadow empty-graph gate never fires without a reachable source repo" {
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "shadow graph is empty"
}

@test "validate_docs shadow empty-graph gate does not fire once a bucket declares a unit" {
  local source_repo="$TEST_WORKSPACE/gate-source-units"
  make_empty_graph_gate_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  cat >> "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
- unit_id: app-a
  - overview_doc: apps/app-a/overview.md
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  refute_contains "$output" "shadow graph is empty"
}

@test "validate_docs shadow empty-graph gate does not fire once any shadow doc declares source_of_truth_paths" {
  local source_repo="$TEST_WORKSPACE/gate-source-declared"
  make_empty_graph_gate_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  mkdir -p "$TEST_PROJECT/src/widget"
  printf 'x = 1\n' > "$TEST_PROJECT/src/widget/core.py"
  cat >> "$DOCS_ROOT/shadow/_global.md" <<'EOF'
- source_of_truth_paths: src/widget/core.py
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  refute_contains "$output" "shadow graph is empty"
}

@test "validate_docs strict fails when required shadow bucket index is missing" {
  rm -f "$DOCS_ROOT/shadow/apps/_index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "shadow bucket index (apps) is missing"
}

@test "validate_docs strict fails when tracked shadow last_updated is blank or future" {
  sed -i.bak 's/^- last_updated:.*$/- last_updated:/' "$DOCS_ROOT/shadow/project-shadow.md"
  rm -f "$DOCS_ROOT/shadow/project-shadow.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "last_updated is present but empty in shadow router"

  "$INIT_SCAFFOLD" "$TEST_PROJECT"
  sed -i.bak 's/^- last_updated:.*$/- last_updated: 2999-01-01T00:00:00Z/' "$DOCS_ROOT/shadow/project-shadow.md"
  rm -f "$DOCS_ROOT/shadow/project-shadow.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "last_updated must not be in the future in shadow router"
}

@test "validate_docs strict fails when active task has no linked plan file" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "301" \
    --task-title "Plan linkage test" \
    --axis-why "Documented rationale" \
    --axis-where "Service boundary" \
    --axis-verify "Unit tests" \
    --no-init

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing plan file for active task TASK-301"
}

@test "validate_docs strict fails on invalid evaluator label in report file" {
  # Create a valid plan file first
  cat > "$DOCS_ROOT/plan/PLAN-qa-01-v1.0.md" <<'EOF'
# PLAN-qa-01-v1.0

- task_id: qa-01
- plan_version: v1.0
- objective: verify evaluator label check
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: validation fails as expected
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  # Invalid evaluator in both filename and field
  cat > "$DOCS_ROOT/report/PLAN-qa-01-v1.0-review-gpt-r01.md" <<'EOF'
# PLAN-qa-01-v1.0 review (gpt)

- task_id: qa-01
- plan_version: v1.0
- evaluator: gpt
- review_round: r01
- verdict: revise
- summary: invalid evaluator
- strengths:
- risks:
- requested_changes:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "invalid evaluator report file name format" || assert_contains "$output" "invalid evaluator in PLAN-qa-01-v1.0-review-gpt-r01.md"
}

@test "validate_docs strict fails on invalid task risk_level enum" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "risk-enum-task-01" \
    --task-title "Task risk enum test" \
    --task-status "planned" \
    --risk-level "low" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  local task_file="$DOCS_ROOT/task/TASK-risk-enum-task-01.md"
  sed -i.bak 's/^- risk_level:.*$/- risk_level: unknown/' "$task_file"
  rm -f "${task_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "invalid task.risk_level value"
}

@test "validate_docs advisory warns on invalid decision risk_level enum" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "risk-enum-decision-01" \
    --decision-title "Decision risk enum test" \
    --selected-option "Option A" \
    --risk-level "medium" \
    --axis-why "why" \
    --axis-what "what" \
    --axis-how "how" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  local decision_file="$DOCS_ROOT/decisions/decision-risk-enum-decision-01.md"
  sed -i.bak 's/^- risk_level:.*$/- risk_level: severe/' "$decision_file"
  rm -f "${decision_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "invalid decision.risk_level value"
}

@test "validate_docs advisory warns when active task omits risk_level" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "risk-missing-01" \
    --task-title "Missing risk level task" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-risk-missing-01-v1.0.md" <<'EOF'
# PLAN-risk-missing-01-v1.0

- task_id: risk-missing-01
- plan_version: v1.0
- objective: verify advisory warning when risk_level is omitted
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: advisory warning is emitted
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-risk-missing-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-risk-missing-01-v1.0 review (codex)

- task_id: risk-missing-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: accept
- summary: standard review exists
- strengths:
- risks:
- requested_changes:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "risk_level is recommended for active task TASK-risk-missing-01"
}

@test "validate_docs strict passes legacy evaluator report without review_style" {
  cat > "$DOCS_ROOT/plan/PLAN-legacy-01-v1.0.md" <<'EOF'
# PLAN-legacy-01-v1.0

- task_id: legacy-01
- plan_version: v1.0
- objective: verify legacy report compatibility
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation passes without review_style
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-legacy-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-legacy-01-v1.0 review (codex)

- task_id: legacy-01
- plan_version: v1.0
- evaluator: codex
- review_round: r01
- verdict: accept
- summary: legacy format remains valid
- strengths: legacy report still contains parser-compatible fields
- risks: missing review_style is tolerated for backward compatibility
- requested_changes: none
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs strict fails on hollow evaluator report fields" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "hollow-report-01" \
    --task-title "Hollow report test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-hollow-report-01-v1.0.md" <<'EOF'
# PLAN-hollow-report-01-v1.0

- task_id: hollow-report-01
- plan_version: v1.0
- objective: verify strict report fields
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: strict validation fails on empty report field
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-hollow-report-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-hollow-report-01-v1.0 review (codex)

- task_id: hollow-report-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: report exists
- strengths: has a strength
- risks: has a risk
- requested_changes:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "requested_changes is present but empty in evaluator report"
}

@test "validate_docs strict requires evaluator report for latest plan version" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "latest-report-01" \
    --task-title "Latest report test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-latest-report-01-v1.0.md" <<'EOF'
# PLAN-latest-report-01-v1.0

- task_id: latest-report-01
- plan_version: v1.0
- objective: old plan
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: old report exists
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/plan/PLAN-latest-report-01-v1.1.md" <<'EOF'
# PLAN-latest-report-01-v1.1

- task_id: latest-report-01
- plan_version: v1.1
- objective: latest plan
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: latest report required
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-02T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-latest-report-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-latest-report-01-v1.0 review (codex)

- task_id: latest-report-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: old plan reviewed
- strengths: old report exists
- risks: latest plan remains unreviewed
- requested_changes: review the latest plan
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing evaluator report for active task TASK-latest-report-01 latest plan v1.1"
}

@test "validate_docs strict rejects stale evaluator report for latest plan" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "stale-report-01" \
    --task-title "Stale report test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-stale-report-01-v1.0.md" <<'EOF'
# PLAN-stale-report-01-v1.0

- task_id: stale-report-01
- plan_version: v1.0
- objective: latest plan
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: fresh report required
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-02T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-stale-report-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-stale-report-01-v1.0 review (codex)

- task_id: stale-report-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: stale report
- strengths: report exists
- risks: plan changed after review
- requested_changes: refresh review
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing fresh evaluator report for active task TASK-stale-report-01 latest plan v1.0"
}

@test "validate_docs strict rejects evaluator report task identity mismatch" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "identity-report-01" \
    --task-title "Identity report test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-identity-report-01-v1.0.md" <<'EOF'
# PLAN-identity-report-01-v1.0

- task_id: identity-report-01
- plan_version: v1.0
- objective: identity plan
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: identity mismatch fails
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-identity-report-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-identity-report-01-v1.0 review (codex)

- task_id: other-task
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: wrong task
- strengths: report exists
- risks: report can attach to wrong task
- requested_changes: bind identity
- last_updated: 2026-01-02T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "evaluator report identity mismatch" || assert_contains "$output" "task_id mismatch between file name and field"
}

@test "validate_docs strict fails when high-risk task has only standard review" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "highrisk-01" \
    --task-title "High risk task" \
    --task-status "in_progress" \
    --risk-level "high" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-highrisk-01-v1.0.md" <<'EOF'
# PLAN-highrisk-01-v1.0

- task_id: highrisk-01
- plan_version: v1.0
- objective: verify automatic adversarial requirement for high-risk tasks
- scope: docs validation
- assumptions: none
- risks: high
- acceptance_signals: strict validation fails without adversarial report
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-highrisk-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-highrisk-01-v1.0 review (codex)

- task_id: highrisk-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: standard review exists
- strengths:
- risks:
- requested_changes: tighten the implementation plan
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing adversarial evaluator report for high-risk task TASK-highrisk-01"
}

@test "validate_docs strict fails when linked high-risk decision has only standard review" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "linkedrisk-01" \
    --task-title "Linked risk task" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "linkedrisk-dec-01" \
    --decision-title "Linked high risk decision" \
    --linked-task "TASK-linkedrisk-01" \
    --selected-option "Option A" \
    --risk-level "critical" \
    --axis-why "why" \
    --axis-what "what" \
    --axis-how "how" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-linkedrisk-01-v1.0.md" <<'EOF'
# PLAN-linkedrisk-01-v1.0

- task_id: linkedrisk-01
- plan_version: v1.0
- objective: verify linked decision drives adversarial enforcement
- scope: docs validation
- assumptions: none
- risks: high
- acceptance_signals: strict validation fails without adversarial report
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-linkedrisk-01-v1.0-review-gemini-r01.md" <<'EOF'
# PLAN-linkedrisk-01-v1.0 review (gemini)

- task_id: linkedrisk-01
- plan_version: v1.0
- evaluator: gemini
- review_style: standard
- review_round: r01
- verdict: revise
- summary: standard review exists
- strengths:
- risks:
- requested_changes: revisit the failure modes
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "decision-linkedrisk-dec-01.md risk_level=critical"
}

@test "validate_docs strict fails when adversarial evaluator report omits rebuttal fields" {
  cat > "$DOCS_ROOT/plan/PLAN-adv-01-v1.0.md" <<'EOF'
# PLAN-adv-01-v1.0

- task_id: adv-01
- plan_version: v1.0
- objective: verify adversarial review requirements
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: strict validation fails on missing adversarial fields
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-adv-01-v1.0-review-claude-r01.md" <<'EOF'
# PLAN-adv-01-v1.0 review (claude)

- task_id: adv-01
- plan_version: v1.0
- evaluator: claude
- review_style: adversarial
- review_round: r01
- verdict: revise
- summary: challenge the initial plan once
- strengths: adversarial framing is present
- risks: missing adversarial details should fail strict validation
- requested_changes: tighten the design before implementation
- objection: the initial plan may understate failure modes
- counterproposal:
- rebuttal:
- residual_risk:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "counterproposal" || assert_contains "$output" "rebuttal" || assert_contains "$output" "residual_risk"
}

@test "validate_docs strict passes when high-risk task has adversarial review" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "highrisk-pass-01" \
    --task-title "High risk pass task" \
    --task-status "in_progress" \
    --risk-level "critical" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-highrisk-pass-01" \
    --approved-next-step "record external adversarial review for highrisk-pass-01" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --primary-author-tool "antigravity" \
    --review-mode "external_cli" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-highrisk-pass-01-v1.0.md" <<'EOF'
# PLAN-highrisk-pass-01-v1.0

- task_id: highrisk-pass-01
- plan_version: v1.0
- objective: verify high-risk task passes with adversarial review
- scope: docs validation
- assumptions: none
- risks: high
- acceptance_signals: strict validation passes
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-highrisk-pass-01-v1.0-review-claude-r01.md" <<'EOF'
# PLAN-highrisk-pass-01-v1.0 review (claude)

- task_id: highrisk-pass-01
- plan_version: v1.0
- evaluator: claude
- review_style: adversarial
- review_round: r01
- verdict: revise
- summary: adversarial review completed
- strengths: adversarial coverage exists
- risks: rollback and monitoring remain important
- requested_changes: tighten rollback and monitoring
- objection: the initial plan may under-test rollback paths
- counterproposal: add a rollback rehearsal and explicit failure thresholds
- rebuttal: the original plan remains viable once rollback checks are added
- residual_risk: operational complexity remains elevated during rollout
- last_updated: 2026-01-01T00:00:00Z
EOF

  # The scaffolded task template now carries the seven resume_* capsule fields
  # (session-resume-contract.md), and presence marks adoption: strict demands a
  # truthful capsule on an in_progress task. Checkpoint the way a real strict
  # handoff would before validating.
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "highrisk-pass-01" \
    --resume-checkpoint \
    --resume-next-action "record external adversarial review verdict" \
    --resume-last-verified "adversarial evaluator report r01 ingested" \
    --resume-blockers "none"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs fails clearly when option value is missing" {
  run "$VALIDATE" "$TEST_PROJECT" --mode
  [ "$status" -ne 0 ]
  assert_contains "$output" "Option --mode requires a value"
}

@test "validate_docs fails clearly when numeric option is invalid" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "num-01" \
    --task-title "Numeric validation test" \
    --no-init

  run "$VALIDATE" "$TEST_PROJECT" --max-task-lines notanumber
  [ "$status" -ne 0 ]
  assert_contains "$output" "--max-task-lines must be a positive integer"
}

@test "validate_docs strict fails on invalid task status enum" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "enum-task-01" \
    --task-title "Enum strict test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  local task_file="$DOCS_ROOT/task/TASK-enum-task-01.md"
  sed -i.bak 's/^- status:.*$/- status: invalid_status/' "$task_file"
  rm -f "${task_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "invalid task.status value"
}

@test "validate_docs advisory warns on invalid decision enum values" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "enum-decision-01" \
    --decision-title "Enum advisory test" \
    --selected-option "x" \
    --no-init

  local decision_file="$DOCS_ROOT/decisions/decision-enum-decision-01.md"
  sed -i.bak 's/^- scope_type:.*$/- scope_type: nonsense/' "$decision_file"
  sed -i.bak 's/^- status:.*$/- status: unknown/' "$decision_file"
  rm -f "${decision_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "invalid decision.scope_type value"
  assert_contains "$output" "invalid decision.status value"
}

@test "validate_docs secret scan skips default template files" {
  cat > "$DOCS_ROOT/report/LLM-REVIEW-template.md" <<'EOF'
# template
- token: "sk-ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs secret scan catches hyphenated OpenAI key formats" {
  cat > "$DOCS_ROOT/SECURITY-NOTES.md" <<'EOF'
# accidental leak
OPENAI_API_KEY=sk-proj-12345678901234567890
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "potential secret values detected" || assert_contains "$output" "OPENAI API key assignment"
  assert_contains "$output" "[REDACTED_SECRET]"
  refute_contains "$output" "sk-proj-12345678901234567890"
}

@test "validate_docs secret scan catches Google Gemini API key formats" {
  local google_key
  google_key="$(printf 'AIzaSy%033d' 0)"

  cat > "$DOCS_ROOT/SECURITY-NOTES.md" <<EOF
# accidental leak
GEMINI_API_KEY=$google_key
Bare value: $google_key
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "potential secret values detected" || assert_contains "$output" "yaml/env-style secret assignments"
  assert_contains "$output" "[REDACTED_SECRET]"
  refute_contains "$output" "$google_key"
}

@test "validate_docs secret scan allows provider variable names without values" {
  cat > "$DOCS_ROOT/SECURITY-NOTES.md" <<'EOF'
# variable names only
Reference variable names such as PROVIDER_API_KEY, DB_PASSWORD, and JWT_SECRET.
Set API_KEY in the environment before running local tools.
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs reports missing rg for secret scanning" {
  run env PATH="/usr/bin:/bin" "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "ripgrep (rg) is required for secret scanning"
}

# ========== P2: task-index status section movement ==========

@test "validate_docs strict allows missing shadow archive directories" {
  rm -rf "$DOCS_ROOT/shadow/_deprecated" "$DOCS_ROOT/shadow/_obsolete"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs strict fails when root-level legacy shadow doc is not a redirect shim" {
  cat > "$DOCS_ROOT/shadow/legacy-shadow.md" <<'EOF'
# Legacy Shadow

- doc_role: note
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "legacy shadow shim" || assert_contains "$output" "redirect_shim"
}

@test "validate_docs strict passes with a valid root-level redirect shim" {
  cat > "$DOCS_ROOT/shadow/legacy-shadow.md" <<'EOF'
# Shadow Redirect

- doc_role: redirect_shim
- legacy_path: docs/shadow/legacy-shadow.md
- canonical_path: docs/shadow/apps/app-a/overview.md
- redirects_fact_scope: unit:app-a:overview
- deprecated_since: 2026-04-15
- status: redirected
- edit_policy: read_only
- replacement_reason: moved into topology-first shadow graph
- last_updated: 2026-04-15T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs strict escapes decision filenames in decision-index checks" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "dot.a" \
    --decision-title "Dot decision" \
    --selected-option "Option A" \
    --axis-why "why" \
    --axis-what "what" \
    --axis-how "how" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  sed -i.bak 's/decision-dot\.a\.md/decision-dotXa.md/' "$DOCS_ROOT/decisions/decision-index.md"
  rm -f "$DOCS_ROOT/decisions/decision-index.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "decision index missing row for decision-dot.a.md"
}

@test "validate_docs reads a decision-index row quoted inside a fence as no row at all" {
  # decision-index.md has only ONE reader, so this could never CONTRADICT a second one --
  # but a row that exists only inside a quoted example still silenced the check outright,
  # which is the same "a template answers for the real thing" hole as the bucket-index unit
  # rows and the task-index rows. Found by the task's own axis
  # enumeration rather than by a review.
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "fenced-row-01" \
    --decision-title "Fenced index row" \
    --selected-option "Option A" \
    --axis-why "why" \
    --axis-what "what" \
    --axis-how "how" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  # Sanity: the garden wrote a real row, and the check is silent about it.
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "decision index missing row for decision-fenced-row-01.md"

  python3 - "$DOCS_ROOT/decisions/decision-index.md" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
row = next(line for line in lines if line.startswith("- decision-fenced-row-01.md "))
out = []
for line in lines:
    out.append("```markdown" if False else line)
    if line == row:
        out[-1] = "```markdown"
        out.extend([row, "```"])
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "decision index missing row for decision-fenced-row-01.md"
}

# ========== Task-index reverse integrity (no physical archive policy) ==========

@test "validate_docs strict fails on a stale task-index row with no matching task file" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "idx-stale-01" \
    --task-title "Stale row fixture" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  rm -f "$DOCS_ROOT/task/TASK-idx-stale-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "task-index row for TASK-idx-stale-01 has no matching task file"
}

@test "validate_docs strict fails when a task-index row sits under the wrong status section" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "idx-mismatch-01" \
    --task-title "Section mismatch fixture" \
    --task-status planned \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  sed -i.bak 's/^- status: planned/- status: done/' "$DOCS_ROOT/task/TASK-idx-mismatch-01.md"
  rm -f "$DOCS_ROOT/task/TASK-idx-mismatch-01.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "task-index section mismatch for TASK-idx-mismatch-01: task file status is done but row is listed under Planned"
}

@test "validate_docs strict fails on duplicate task-index rows for the same task" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "idx-dup-01" \
    --task-title "Duplicate row fixture" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  printf '%s\n' "- TASK-idx-dup-01 | in_progress | Duplicate row fixture" >> "$DOCS_ROOT/task/task-index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "task-index has duplicate rows for TASK-idx-dup-01"
}

@test "validate_docs reads a task-index row quoted inside a fence as no row at all" {
  # The ROW grammar had three readers -- two `grep -qE "^- <ref> "` probes in
  # validate_docs.sh and the `while read` walk here -- and all three were fence-blind. The
  # PLAN deferred them as "they agree today", which was true and beside the point: they
  # agreed on a FALSEHOOD. A row that exists only inside a quoted example silenced
  # "task-index missing row" AND earned a section verdict, so the run said "row is listed
  # under Done" about a row a markdown reader never sees. Both halves must now say the
  # index has no row for this task.
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "idx-fenced-01" \
    --task-title "Fenced row fixture" \
    --task-status planned \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  python3 - "$DOCS_ROOT/task/task-index.md" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
row = next(line for line in lines if line.startswith("- TASK-idx-fenced-01"))
# Move the only row for this task under "## Done" AND inside a fence: the section is
# wrong on purpose, so a fence-blind walk has something untrue to say about it.
lines = [line for line in lines if line != row]
out = []
for line in lines:
    out.append(line)
    if line.strip() == "## Done":
        out.extend(["", "```markdown", row, "```"])
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  # The probe half: the task file has no row, and that is the truthful finding.
  assert_contains "$output" "task-index missing row for TASK-idx-fenced-01"
  # The walk half: it must not simultaneously claim the quoted row is listed somewhere.
  refute_contains "$output" "task-index section mismatch for TASK-idx-fenced-01"

  # Positive half: unfenced, the very same row under the very same wrong section is a real
  # row, and both halves must say so -- no missing-row finding, one section mismatch.
  python3 - "$DOCS_ROOT/task/task-index.md" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("```markdown\n", "").replace("\n```\n", "\n"), encoding="utf-8")
PY

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  refute_contains "$output" "task-index missing row for TASK-idx-fenced-01"
  assert_contains "$output" "task-index section mismatch for TASK-idx-fenced-01: task file status is planned but row is listed under Done"
}

@test "validate_docs treats a bare task-index row as present in both readers" {
  # The probes required a space after the ref and the walk did not, so the two disagreed
  # about `- TASK-foo` with nothing after it: one reported "task-index missing row" while
  # the other gave the same row a section verdict. One row shape now, in both.
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "idx-bare-01" \
    --task-title "Bare row fixture" \
    --task-status planned \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  perl -pi -e 's{^- TASK-idx-bare-01 .*$}{- TASK-idx-bare-01}' "$DOCS_ROOT/task/task-index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "task-index missing row for TASK-idx-bare-01"

  # Positive half: a DIFFERENT task whose ref merely shares this prefix is still missing,
  # so the boundary is a boundary and not a blanket match.
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "idx-bare-01-extra" \
    --task-title "Prefix collision fixture" \
    --task-status planned \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init
  perl -ni -e 'print unless /^- TASK-idx-bare-01-extra /' "$DOCS_ROOT/task/task-index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "task-index missing row for TASK-idx-bare-01-extra"
}

# ========== Issue tracker current/resolved consistency ==========

@test "validate_docs strict fails when a current issue is marked resolved" {
  cat > "$DOCS_ROOT/issues/current/ISSUE-20260101-stuck-status.md" <<'EOF'
# ISSUE-20260101-stuck-status

- title: Stuck status fixture
- status: resolved
- severity: low
- area: docs
- owner: test
- created_at: 2026-01-01
- last_seen_at: 2026-01-01
- detected_by: test
- related_files:
- related_endpoints:
- security_note:
- resolved_at:
- resolution_doc:
EOF
  printf '%s\n' "| ISSUE-20260101-stuck-status | low | resolved | docs | Stuck status fixture |" >> "$DOCS_ROOT/issues/current/README.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "is status: resolved but still lives in docs/issues/current/"
}

@test "validate_docs strict fails on a current issue missing its current/README index row" {
  cat > "$DOCS_ROOT/issues/current/ISSUE-20260101-no-row.md" <<'EOF'
# ISSUE-20260101-no-row

- title: No index row fixture
- status: open
- severity: low
- area: docs
- owner: test
- created_at: 2026-01-01
- last_seen_at: 2026-01-01
- detected_by: test
- related_files:
- related_endpoints:
- security_note:
- resolved_at:
- resolution_doc:
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "docs/issues/current/README.md missing index row for ISSUE-20260101-no-row.md"
}

@test "validate_docs strict fails when a resolved issue has no paired resolution doc" {
  cat > "$DOCS_ROOT/issues/resolved/ISSUE-20260101-missing-resolution.md" <<'EOF'
# ISSUE-20260101-missing-resolution

- title: Missing resolution fixture
- status: resolved
- severity: low
- area: docs
- owner: test
- created_at: 2026-01-01
- last_seen_at: 2026-01-01
- detected_by: test
- related_files:
- related_endpoints:
- security_note:
- resolved_at: 2026-01-02T00:00:00Z
- resolution_doc: RESOLUTION-20260101-missing-resolution.md
EOF
  printf '%s\n' "| ISSUE-20260101-missing-resolution | low | docs | 2026-01-02 | RESOLUTION-20260101-missing-resolution.md | Missing resolution fixture |" >> "$DOCS_ROOT/issues/resolved/README.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "resolved issue ISSUE-20260101-missing-resolution.md has no paired resolution doc"
}

@test "validate_docs strict fails on an orphaned resolution doc with no paired issue file" {
  cat > "$DOCS_ROOT/issues/resolved/RESOLUTION-20260101-orphan.md" <<'EOF'
# RESOLUTION-20260101-orphan

- issue: ../resolved/ISSUE-20260101-orphan.md
- title: Orphan resolution fixture
- resolved_at: 2026-01-02T00:00:00Z
- fixed_by: test
- verified_by: test
- commits:
- revision: r01
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "resolution doc RESOLUTION-20260101-orphan.md has no paired issue file"
}

@test "validate_docs strict tolerates a status field with trailing parenthetical notes for task-index section match" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "idx-decorated-01" \
    --task-title "Decorated status fixture" \
    --task-status planned \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  sed -i.bak 's/^- status: planned/- status: planned (Phase 1 r02 notes)/' "$DOCS_ROOT/task/TASK-idx-decorated-01.md"
  rm -f "$DOCS_ROOT/task/TASK-idx-decorated-01.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "task-index section mismatch"
}

@test "validate_docs advisory continues past a missing orchestration field instead of aborting" {
  write_await_gate_fixture "orch-abort-01" "in_progress" "implementation_start" "PLAN-orch-abort-01-v1.0" "not_requested" "" "" "" ""

  sed -i.bak '/^- primary_author_tool:/d' "$DOCS_ROOT/orchestration/orch-abort-01/ORCH.md"
  rm -f "$DOCS_ROOT/orchestration/orch-abort-01/ORCH.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[RESULT]"
  assert_contains "$output" "primary_author_tool is missing"
}

@test "validate_docs strict passes with a well-formed resolved issue and paired resolution doc" {
  cat > "$DOCS_ROOT/issues/resolved/ISSUE-20260101-clean-pair.md" <<'EOF'
# ISSUE-20260101-clean-pair

- title: Clean pair fixture
- status: resolved
- severity: low
- area: docs
- owner: test
- created_at: 2026-01-01
- last_seen_at: 2026-01-01
- detected_by: test
- related_files:
- related_endpoints:
- security_note:
- resolved_at: 2026-01-02T00:00:00Z
- resolution_doc: RESOLUTION-20260101-clean-pair.md
EOF
  cat > "$DOCS_ROOT/issues/resolved/RESOLUTION-20260101-clean-pair.md" <<'EOF'
# RESOLUTION-20260101-clean-pair

- issue: ../resolved/ISSUE-20260101-clean-pair.md
- title: Clean pair fixture
- resolved_at: 2026-01-02T00:00:00Z
- fixed_by: test
- verified_by: test
- commits:
- revision: r01
EOF
  printf '%s\n' "| ISSUE-20260101-clean-pair | low | docs | 2026-01-02 | RESOLUTION-20260101-clean-pair.md | Clean pair fixture |" >> "$DOCS_ROOT/issues/resolved/README.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

# ========== Concurrent session claim contract ==========

@test "validate_docs advisory warns when an in_progress task is missing owner" {
  write_await_gate_fixture "claim-owner-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-claim-owner-01.md"
  mkdir -p "$DOCS_ROOT/task/.claims/claim-owner-01"
  sed -i.bak 's/^- owner: test/- owner:/' "$DOCS_ROOT/task/TASK-claim-owner-01.md"
  rm -f "$DOCS_ROOT/task/TASK-claim-owner-01.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "owner is recommended for in_progress task TASK-claim-owner-01"
  refute_contains "$output" "claimed_at is recommended for in_progress task"
  refute_contains "$output" "claim directory is recommended for in_progress task"
}

@test "validate_docs advisory warns when an in_progress task is missing claimed_at" {
  write_await_gate_fixture "claim-time-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  mkdir -p "$DOCS_ROOT/task/.claims/claim-time-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "claimed_at is recommended for in_progress task TASK-claim-time-01"
  refute_contains "$output" "owner is recommended for in_progress task"
  refute_contains "$output" "claim directory is recommended for in_progress task"
}

@test "validate_docs advisory warns when an in_progress task has no claim directory" {
  write_await_gate_fixture "claim-dir-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-claim-dir-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "claim directory is recommended for in_progress task TASK-claim-dir-01: mkdir"
  assert_contains "$output" "docs/task/.claims/claim-dir-01/"
  refute_contains "$output" "owner is recommended for in_progress task"
  refute_contains "$output" "claimed_at is recommended for in_progress task"
}

@test "validate_docs advisory does not warn when the claim contract is fully satisfied" {
  write_await_gate_fixture "claim-ok-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-claim-ok-01.md"
  mkdir -p "$DOCS_ROOT/task/.claims/claim-ok-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "owner is recommended for in_progress task"
  refute_contains "$output" "claimed_at is recommended for in_progress task"
  refute_contains "$output" "claim directory is recommended for in_progress task"
}

@test "validate_docs strict fails on a stale claim directory whose task already left in_progress" {
  write_await_gate_fixture "claim-stale-01" "done" "not_requested" "" "not_requested" "" "" "" ""
  mkdir -p "$DOCS_ROOT/task/.claims/claim-stale-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "stale claim directory for TASK-claim-stale-01 (status=done): remove"
}

@test "validate_docs strict fails on an orphaned claim directory with no matching task file" {
  mkdir -p "$DOCS_ROOT/task/.claims/claim-ghost-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "orphaned claim directory with no matching task file"
  assert_contains "$output" "docs/task/.claims/claim-ghost-01"
}

# ========== Resume capsule (session-resume-contract.md) ==========

# write_await_gate_fixture is only ever exercised under --mode advisory
# elsewhere in this suite (or under --mode strict expecting FAILURE), so it
# carries three latent strict-mode issues that were never surfaced: a blank
# orchestration.supervisor_agent, an external_review_required_for value
# ("not_requested") outside that field's enum, and a task-index row appended
# to the physically-last section regardless of status. None of those are
# resume-capsule concerns, so normalize them here to get a strict-clean
# baseline the resume checks can be asserted against in isolation.
write_strict_clean_resume_fixture() {
  local task_id="$1"
  local orch_file="$DOCS_ROOT/orchestration/${task_id}/ORCH.md"

  write_await_gate_fixture "$task_id" "in_progress" "" "" "not_requested" "" "" "" ""

  sed -i.bak "s/^- supervisor_agent:.*/- supervisor_agent: main-thread-supervising-lead-architect/" "$orch_file"
  rm -f "${orch_file}.bak"

  grep -vF -- "- TASK-${task_id} " "$DOCS_ROOT/task/task-index.md" > "$DOCS_ROOT/task/task-index.md.tmp"
  mv "$DOCS_ROOT/task/task-index.md.tmp" "$DOCS_ROOT/task/task-index.md"
  awk -v section="## In Progress" -v row="- TASK-${task_id} in_progress" '
    { print; if ($0 == section) { print row } }
  ' "$DOCS_ROOT/task/task-index.md" > "$DOCS_ROOT/task/task-index.md.tmp"
  mv "$DOCS_ROOT/task/task-index.md.tmp" "$DOCS_ROOT/task/task-index.md"
}

@test "validate_docs advisory warns when an in_progress task has no resume capsule fields at all" {
  write_await_gate_fixture "resume-missing-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-resume-missing-01.md"
  mkdir -p "$DOCS_ROOT/task/.claims/resume-missing-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "resume capsule missing for in_progress task TASK-resume-missing-01"
  assert_contains "$output" "doc_garden.sh --task-id resume-missing-01 --resume-checkpoint"
}

@test "validate_docs advisory does not nudge adoption once any resume_* field is present" {
  write_await_gate_fixture "resume-present-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-resume-present-01.md"
  mkdir -p "$DOCS_ROOT/task/.claims/resume-present-01"
  printf '%s\n' "- resume_checkpointed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-resume-present-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "resume capsule missing for in_progress task"
}

@test "validate_docs strict does not fail an in_progress task with no resume_* fields at all" {
  write_strict_clean_resume_fixture "resume-absent-strict-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  refute_contains "$output" "resume_next_action is present but empty"
  refute_contains "$output" "resume_last_verified is present but empty"
}

@test "validate_docs strict fails when resume_next_action is present but empty" {
  write_await_gate_fixture "resume-empty-next-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- resume_next_action:" >> "$DOCS_ROOT/task/TASK-resume-empty-next-01.md"
  printf '%s\n' "- resume_last_verified: bats suite green" >> "$DOCS_ROOT/task/TASK-resume-empty-next-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "resume_next_action is present but empty for in_progress task TASK-resume-empty-next-01"
  refute_contains "$output" "resume_last_verified is present but empty"
}

@test "validate_docs strict fails when resume_last_verified is present but empty" {
  write_await_gate_fixture "resume-empty-verified-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- resume_next_action: run the bats suite" >> "$DOCS_ROOT/task/TASK-resume-empty-verified-01.md"
  printf '%s\n' "- resume_last_verified:" >> "$DOCS_ROOT/task/TASK-resume-empty-verified-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "resume_last_verified is present but empty for in_progress task TASK-resume-empty-verified-01"
  refute_contains "$output" "resume_next_action is present but empty"
}

@test "validate_docs strict passes when resume_next_action and resume_last_verified are both truthfully filled" {
  write_strict_clean_resume_fixture "resume-filled-01"
  printf '%s\n' "- resume_next_action: run the bats suite" >> "$DOCS_ROOT/task/TASK-resume-filled-01.md"
  printf '%s\n' "- resume_last_verified: bats suite green" >> "$DOCS_ROOT/task/TASK-resume-filled-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  refute_contains "$output" "resume_next_action is present but empty"
  refute_contains "$output" "resume_last_verified is present but empty"
}

@test "validate_docs strict does not fail when resume_state_revision is present but non-numeric" {
  write_strict_clean_resume_fixture "resume-revision-strict-01"
  printf '%s\n' "- resume_next_action: run the bats suite" >> "$DOCS_ROOT/task/TASK-resume-revision-strict-01.md"
  printf '%s\n' "- resume_last_verified: bats suite green" >> "$DOCS_ROOT/task/TASK-resume-revision-strict-01.md"
  printf '%s\n' "- resume_state_revision: corrupted" >> "$DOCS_ROOT/task/TASK-resume-revision-strict-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] resume_state_revision is present but non-numeric for in_progress task TASK-resume-revision-strict-01"
}

@test "validate_docs advisory warns when resume_state_revision is present but non-numeric" {
  write_await_gate_fixture "resume-revision-advisory-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-resume-revision-advisory-01.md"
  mkdir -p "$DOCS_ROOT/task/.claims/resume-revision-advisory-01"
  printf '%s\n' "- resume_state_revision: not-a-number" >> "$DOCS_ROOT/task/TASK-resume-revision-advisory-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "[WARN] resume_state_revision is present but non-numeric for in_progress task TASK-resume-revision-advisory-01"
}

@test "validate_docs does not warn about resume_state_revision when it is a valid integer" {
  write_strict_clean_resume_fixture "resume-revision-ok-01"
  printf '%s\n' "- resume_next_action: run the bats suite" >> "$DOCS_ROOT/task/TASK-resume-revision-ok-01.md"
  printf '%s\n' "- resume_last_verified: bats suite green" >> "$DOCS_ROOT/task/TASK-resume-revision-ok-01.md"
  printf '%s\n' "- resume_state_revision: 3" >> "$DOCS_ROOT/task/TASK-resume-revision-ok-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  refute_contains "$output" "resume_state_revision is present but non-numeric"
}

@test "validate_docs advisory warns when a bucket index overview_doc reference does not resolve" {
  cat >> "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
- unit_id: app-a
  - overview_doc: apps/app-a/overview.md
  - secondary_tags: web
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow navigation reference does not resolve"
  assert_contains "$output" "overview_doc -> apps/app-a/overview.md"
  # Full attributable literal (rule-coverage matrix arbiter): includes the
  # trailing ": " that the fragment above omits.
  assert_contains "$output" "shadow navigation reference does not resolve: "
}

@test "validate_docs advisory warns when a redirect shim canonical_path does not resolve" {
  cat > "$DOCS_ROOT/shadow/legacy-shadow.md" <<'EOF'
# Shadow Redirect

- doc_role: redirect_shim
- legacy_path: docs/shadow/legacy-shadow.md
- canonical_path: docs/shadow/apps/app-a/overview.md
- redirects_fact_scope: unit:app-a:overview
- deprecated_since: 2026-04-15
- status: redirected
- edit_policy: read_only
- replacement_reason: moved into topology-first shadow graph
- last_updated: 2026-04-15T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow navigation reference does not resolve"
  assert_contains "$output" "canonical_path -> docs/shadow/apps/app-a/overview.md"
}

@test "validate_docs advisory warns when a unit overview next_docs reference dangles" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- next_docs: apps/app-a/auth.md
- source_of_truth_paths: src/app_a/auth.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  # Item 4 (source-path existence) would otherwise legitimately flag this code path;
  # create it so this test isolates the navigation-link behavior it is about.
  mkdir -p "$TEST_PROJECT/src/app_a"
  printf 'x=1\n' > "$TEST_PROJECT/src/app_a/auth.py"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow navigation reference does not resolve"
  assert_contains "$output" "next_docs -> apps/app-a/auth.md"
  # source_of_truth code paths are not .md and must not be flagged by this check
  refute_contains "$output" "src/app_a/auth.py"
}

@test "validate_docs advisory passes navigation links when every referenced doc exists" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat >> "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
- unit_id: app-a
  - overview_doc: apps/app-a/overview.md
  - secondary_tags: web
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- next_docs: apps/app-a/auth.md
- last_updated: 2026-01-01T00:00:00Z
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-a/auth.md" <<'EOF'
# Shadow Concern

- doc_role: concern_leaf
- concern_id: auth
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow navigation references resolve to real files"
  refute_contains "$output" "shadow navigation reference does not resolve"
}

@test "validate_docs strict skips the advisory navigation link check (recommended tier)" {
  cat >> "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
- unit_id: app-a
  - overview_doc: apps/app-a/overview.md
  - secondary_tags: web
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  # A dangling nav reference alone must not turn strict red, and the advisory-only
  # navigation warning must not be emitted in strict mode.
  refute_contains "$output" "shadow navigation reference does not resolve"
}

@test "validate_docs advisory resolves Markdown-link next_docs syntax without a false positive" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- next_docs: [Auth Flow](apps/app-a/auth.md)
- last_updated: 2026-01-01T00:00:00Z
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-a/auth.md" <<'EOF'
# Shadow Concern

- doc_role: concern_leaf
- concern_id: auth
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "shadow navigation reference does not resolve"
}

@test "validate_docs advisory ignores navigation references inside fenced code examples" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- last_updated: 2026-01-01T00:00:00Z

## Authoring example

```markdown
- canonical_path: docs/shadow/apps/example/never-created.md
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "never-created.md"
}

@test "validate_docs advisory catches a dangling reference in a nested-list next_docs block" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- next_docs:
  - apps/app-a/missing-leaf.md
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow navigation reference does not resolve"
  assert_contains "$output" "next_docs -> apps/app-a/missing-leaf.md"
}

@test "validate_docs advisory does not let an unrelated same-named file mask a dangling shadow ref" {
  # A real dangling ref: apps/app-a/api.md does not exist under the shadow tree.
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- next_docs: apps/app-a/api.md
- last_updated: 2026-01-01T00:00:00Z
EOF
  # A decoy with the same basename elsewhere in the project must not mask it.
  printf '# decoy\n' > "$DOCS_ROOT/api.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow navigation reference does not resolve"
  assert_contains "$output" "next_docs -> apps/app-a/api.md"
}

@test "validate_docs advisory de-duplicates a repeated dangling navigation reference" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- next_docs: apps/app-a/missing.md, apps/app-a/missing.md
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  local hits
  hits="$(printf '%s\n' "$output" | grep -c 'next_docs -> apps/app-a/missing.md')"
  [ "$hits" -eq 1 ]
}

_seed_source_digest_overview() {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'def login():\n    return True\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- source_of_truth_paths: src/auth.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  python3 "$SCRIPTS_DIR/shadow_source_digest.py" \
    "$DOCS_ROOT/shadow/apps/app-a/overview.md" --project-root "$TEST_PROJECT" --write
}

@test "validate_docs advisory passes when a shadow source-of-truth digest matches current source" {
  _seed_source_digest_overview
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source-of-truth digests verified against current source"
  refute_contains "$output" "digest drift"
}

@test "validate_docs advisory warns on source-of-truth digest drift when source content changes" {
  _seed_source_digest_overview
  printf 'def login():\n    return False  # changed\n' > "$TEST_PROJECT/src/auth.py"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source-of-truth digest drift"
  assert_contains "$output" "apps/app-a/overview.md"
}

@test "validate_docs advisory warns when a declared source-of-truth path is deleted" {
  _seed_source_digest_overview
  rm "$TEST_PROJECT/src/auth.py"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source-of-truth declared path does not exist: src/auth.py"
}

@test "validate_docs advisory is silent about source digest when a doc does not opt in" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'x = 1\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- source_of_truth_paths: src/auth.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "digest drift"
  refute_contains "$output" "source-of-truth digests verified"
}

@test "validate_docs strict skips the advisory source-of-truth digest check" {
  _seed_source_digest_overview
  printf 'def login():\n    return False\n' > "$TEST_PROJECT/src/auth.py"
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "digest drift"
}

@test "doc_garden does not write or alter source_of_truth_digest (freshness must stay content-bound)" {
  _seed_source_digest_overview
  local before after
  before="$(grep 'source_of_truth_digest' "$DOCS_ROOT/shadow/apps/app-a/overview.md")"
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id t-digest --task-title x --task-status in_progress --shadow-note "touch" >/dev/null 2>&1
  after="$(grep 'source_of_truth_digest' "$DOCS_ROOT/shadow/apps/app-a/overview.md")"
  [ -n "$before" ]
  [ "$before" = "$after" ]
}

@test "a fenced source_of_truth_digest example does not manufacture a verified verdict" {
  # The prefilter that decides which documents are worth a python spawn is a fence-BLIND
  # grep, and it used to set `checked` as well -- so a unit overview that merely SHOWS the
  # reader how to declare a digest produced "[PASS] shadow source-of-truth digests verified
  # against current source" on a corpus where the fence-aware helper says no_digest and
  # nothing whatsoever was verified. A PASS that certifies work nobody did is worse than a
  # missing check.
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- last_updated: 2026-01-01T00:00:00Z

## How to declare a digest

```markdown
- source_of_truth_paths: src/app.py
- source_of_truth_digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "shadow source-of-truth digests verified against current source"
  # Positive anchor: the shadow rules really did run over this document.
  assert_contains "$output" "shadow navigation references resolve to real files"

  # Positive half: a REAL declaration in the same document still earns the verdict, so
  # this is not the check quietly switching itself off.
  mkdir -p "$TEST_PROJECT/src"
  printf 'x = 1\n' > "$TEST_PROJECT/src/app.py"
  perl -pi -e 's{^- last_updated: 2026-01-01T00:00:00Z$}{- source_of_truth_paths: src/app.py\n- source_of_truth_digest: sha256:0\n- last_updated: 2026-01-01T00:00:00Z}' \
    "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  python3 "$SCRIPTS_DIR/shadow_source_digest.py" \
    "$DOCS_ROOT/shadow/apps/app-a/overview.md" --project-root "$TEST_PROJECT" --write >/dev/null

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source-of-truth digests verified against current source"
}

@test "shadow source digest detects drift in the mixed inline+nested source_of_truth_paths form" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/a.py"
  printf 'b=1\n' > "$TEST_PROJECT/src/b.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/a.py
  - src/b.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  python3 "$SCRIPTS_DIR/shadow_source_digest.py" \
    "$DOCS_ROOT/shadow/apps/app-a/overview.md" --project-root "$TEST_PROJECT" --write
  # Mutating the NESTED path must be detected (this was a silent false negative).
  printf 'b=2\n' > "$TEST_PROJECT/src/b.py"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source-of-truth digest drift"
}

@test "shadow source digest --write does not corrupt the pure nested-bullet form" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/a.py"
  printf 'c=1\n' > "$TEST_PROJECT/src/c.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths:
  - src/a.py
  - src/c.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  run python3 "$SCRIPTS_DIR/shadow_source_digest.py" \
    "$DOCS_ROOT/shadow/apps/app-a/overview.md" --project-root "$TEST_PROJECT" --write
  [ "$status" -eq 0 ]
  # After writing, the doc must still parse: --check reports ok, not no_paths.
  run python3 "$SCRIPTS_DIR/shadow_source_digest.py" \
    "$DOCS_ROOT/shadow/apps/app-a/overview.md" --project-root "$TEST_PROJECT" --check
  [ "$status" -eq 0 ]
  assert_contains "$output" "status: ok"
  refute_contains "$output" "no_paths"
}

@test "validate_docs advisory warns when a declared source-of-truth path escapes the project root" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf 'secret\n' > "$TEST_WORKSPACE/outside.txt"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: ../outside.txt
- source_of_truth_digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "escapes the project root: ../outside.txt"
}

@test "doc_garden does not ADD a source_of_truth_digest to a doc that has none" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/a.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/a.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id t-noadd --task-title x --task-status in_progress --shadow-note "touch" >/dev/null 2>&1
  run grep -c 'source_of_truth_digest' "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  assert_equal "$output" "0"
}

@test "validate_docs advisory warns on a dead source_of_truth path in a digest-less doc" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/auth.py, src/gone.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source_of_truth path does not exist: src/gone.py"
}

@test "validate_docs advisory warns on an escaping source_of_truth path in a digest-less doc" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf 'x\n' > "$TEST_WORKSPACE/outside.txt"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: ../outside.txt
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source_of_truth path escapes the project root: ../outside.txt"
}

@test "validate_docs advisory is silent when digest-less source_of_truth paths all exist" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/auth.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source_of_truth_paths all resolve to real in-project files"
  refute_contains "$output" "source_of_truth path does not exist"
}

@test "validate_docs does not double-warn a dead source when the doc carries a digest" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/auth.py
- last_updated: 2026-01-01T00:00:00Z
EOF
  python3 "$SCRIPTS_DIR/shadow_source_digest.py" \
    "$DOCS_ROOT/shadow/apps/app-a/overview.md" --project-root "$TEST_PROJECT" --write
  # Now the source disappears: the digest check owns this doc, the paths-exist check skips it.
  rm "$TEST_PROJECT/src/auth.py"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # The digest check reports the missing source; the paths-exist check must NOT also fire.
  assert_contains "$output" "shadow source-of-truth declared path does not exist: src/auth.py"
  refute_contains "$output" "shadow source_of_truth path does not exist: src/auth.py"
}

@test "validate_docs advisory is not silenced by an EMPTY source_of_truth_digest field" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/auth.py, src/gone.py
- source_of_truth_digest:
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # A bare (empty) digest line must NOT let the dead source escape the check.
  assert_contains "$output" "shadow source_of_truth path does not exist: src/gone.py"
}

@test "validate_docs advisory is not silenced by a fenced source_of_truth_digest example" {
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/auth.py"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- source_of_truth_paths: src/auth.py, src/gone.py
- last_updated: 2026-01-01T00:00:00Z

```markdown
- source_of_truth_digest: sha256:deadbeef
```
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow source_of_truth path does not exist: src/gone.py"
}

@test "validate_docs does not abort the whole run on a malformed (NUL-byte) source path" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# Shadow Unit Overview\n- doc_role: unit_overview\n- source_of_truth_paths: src/a\000b.py\n- last_updated: 2026-01-01T00:00:00Z\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  # The malformed path must be handled (missing), and the script must run to the end
  # (the final [RESULT] line proves it did not abort mid-run under set -e).
  [ "$status" -eq 0 ]
  assert_contains "$output" "[RESULT]"
}

@test "validate_docs advisory passes a well-formed unit overview schema" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow unit/concern docs have valid schema"
}

@test "validate_docs advisory warns when a unit overview is missing home_bucket" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow unit overview missing home_bucket"
}

@test "validate_docs advisory warns when a unit overview home_bucket is not a known bucket" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: widgets
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "home_bucket is not a known bucket (widgets)"
}

@test "validate_docs advisory warns when a concern leaf is missing concern_id" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/auth.md" <<'EOF'
# Shadow Concern

- doc_role: concern_leaf
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow concern leaf missing concern_id"
  # Full attributable literal (rule-coverage matrix arbiter): includes the
  # trailing ": " that the fragment above omits.
  assert_contains "$output" "shadow concern leaf missing concern_id: "
}

@test "validate_docs strict skips the advisory unit schema check" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "shadow unit overview missing home_bucket"
}

@test "validate_docs advisory does not treat a fenced doc_role example as a carrier doc" {
  mkdir -p "$DOCS_ROOT/shadow/apps"
  cat > "$DOCS_ROOT/shadow/apps/readme.md" <<'EOF'
# How to write a shadow unit overview

An overview looks like:

```markdown
- doc_role: unit_overview
- home_bucket: apps
```
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "shadow unit overview missing"
  refute_contains "$output" "shadow unit/concern docs have valid schema"
}

# --- extract_field_value fence awareness ---
#
# extract_field_value is the validator's GENERAL capsule reader (80 invocations across
# task, plan, orchestration, decision, issue and report documents), and it used to be a
# fence-blind `grep -E "^- key:" | head -1`. A quoted TEMPLATE therefore outranked the
# real field. The three fixtures below all put a deliberately WRONG real value below the
# example so every case asserts a finding the rule must PRODUCE: a blank fence-stripped
# copy would say "bucket is missing" and a fence-blind read would say "found widgets",
# so the expected literal distinguishes all three outcomes rather than only proving
# silence.

_bucket_index_with_example() {
  # $1 = the example block, fenced or not -- the only thing that varies across the three
  mkdir -p "$DOCS_ROOT/shadow/apps"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<EOF
# Shadow Bucket Index

A unit overview looks like:

$1

- doc_role: bucket_index
- bucket: not-apps
- last_updated: 2026-08-01T00:00:00Z
EOF
}

@test "validate_docs advisory keeps a bucket index doc_role when the file quotes the unit overview template in a fence" {
  _bucket_index_with_example '```markdown
- doc_role: unit_overview
- bucket: widgets
```'
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # Positive: the real fields BELOW the fence are still read, and read correctly.
  assert_contains "$output" "invalid bucket in shadow bucket index (apps): expected apps, found not-apps"
  # The regression: the quoted example must not answer for doc_role.
  refute_contains "$output" "invalid doc_role in shadow bucket index (apps)"
}

@test "validate_docs advisory still reports the doc_role drift when the same example is NOT fenced" {
  # Fence awareness must not become a blanket mute: unfenced, this really is a document
  # declaring two roles, and the first one really is what the reader returns.
  _bucket_index_with_example '- doc_role: unit_overview
- bucket: widgets'
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "invalid doc_role in shadow bucket index (apps): expected bucket_index, found unit_overview"
  assert_contains "$output" "invalid bucket in shadow bucket index (apps): expected apps, found widgets"
}

@test "validate_docs advisory treats an indented fence marker like a column-0 one" {
  # The fence markers are indented, the example lines are not: exactly the shape that
  # the `^- ` anchored grep sees as real fields while a markdown renderer sees an example.
  _bucket_index_with_example '   ```markdown
- doc_role: unit_overview
- bucket: widgets
   ```'
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "invalid bucket in shadow bucket index (apps): expected apps, found not-apps"
  refute_contains "$output" "invalid doc_role in shadow bucket index (apps)"
}

# --- Key-PRESENCE probes answer with the same grammar as the value read
#     ---
#
# Making extract_field_value fence-aware while the `grep -qE "^- key:"` probes beside it
# stayed fence-blind recreated the defect this line of work exists to remove. Before that
# change both spellings were blind and therefore AGREED; after it they contradicted each
# other about the same bytes. Reproduced: a task whose only `- status: in_progress` sat in
# a quoted template produced "in-progress task is stale by last_updated" from the probe at
# validate_docs.sh:489 while every other rule in the SAME run read the file as `planned`.
#
# Each test below asserts the truthful finding as well as the absence of the false one.
# A refute alone would also pass if the rule simply stopped running, which is how this
# repo has shipped tests that proved nothing.

_probe_task_index_row() {
  # Put a row under a named section. Appending drops it under "## Done" and manufactures
  # an unrelated section mismatch that would muddy every assertion here.
  python3 - "$DOCS_ROOT/task/task-index.md" "$1" "$2" <<'PY'
import sys

path, section, row = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding="utf-8").read().splitlines()
out = []
for line in lines:
    out.append(line)
    if line.strip() == section:
        out.extend(["", row])
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
}

_probe_task_file() {
  # $1 task id, $2 status value, $3 body appended after the capsule (fenced or not).
  # $3 arrives through a parameter expansion, so any fence markers in it stay literal.
  cat > "$DOCS_ROOT/task/TASK-${1}.md" <<EOF
# TASK-${1}

- title: Presence probe fixture
- objective: presence and value must answer with one grammar
- acceptance_criteria: the validator emits the truthful finding
- non_goals: none
- affected_modules: docs
- interfaces_changed: none
- data_migrations: none
- test_scope: validate_docs
- risks: none
- risk_level: low
- consumes_plan_ref:
- status: ${2}
- owner: test
- claimed_at: 2020-01-01T00:00:00Z
- due_date:
- axis_why: fixture
- axis_where: fixture
- axis_verify: bats
- last_updated: 2020-01-01T00:00:00Z

## Quoted template

${3}
EOF
}

@test "validate_docs answers in-progress freshness with the status VALUE, not a second read of the document" {
  # Two fixtures, two axes, one rule. The freshness gate must fire exactly when the
  # document's status IS in_progress -- the value every other task rule uses -- and must
  # not be decided by a separate scan that can find a `- status:` line the value reader
  # never returns. r01 broke this on the FENCE axis (a quoted template answered), r02 on
  # the OCCURRENCE axis (a later line answered for the first one).
  _probe_task_file "fence-status-probe-01" "planned" '```
- status: in_progress
```'
  _probe_task_index_row "## Planned" "- TASK-fence-status-probe-01 planned"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # The false finding: an in-progress freshness verdict on a document the status rule,
  # the claim rule, the resume rule and the task-index rule all read as `planned`.
  # Every in-progress-task verdict, PASS or FAIL, day count and all: none of them may be
  # about this document, because the rule must not have run on it at all.
  refute_contains "$(printf '%s\n' "$output" | grep 'in-progress task' || true)" \
    "TASK-fence-status-probe-01.md"
  # Positive anchor for the same run: the fixture really was scanned as a task, and the
  # status the rest of the run used is the one this rule must agree with.
  assert_contains "$output" "task document size OK"
  refute_contains "$output" "task-index section mismatch for TASK-fence-status-probe-01"

  # OCCURRENCE axis: unfenced, those bytes really are a second column-0 status line -- and
  # they are still not this document's status, because extract_field_value returns the
  # FIRST one. An ANY-LINE probe fires here; the value comparison does not.
  _probe_task_file "fence-status-probe-01" "planned" '- status: in_progress'
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$(printf '%s\n' "$output" | grep 'in-progress task' || true)" \
    "TASK-fence-status-probe-01.md"
  # The same run must still read the document as planned, so the two answers agree.
  refute_contains "$output" "task-index section mismatch for TASK-fence-status-probe-01"
  assert_contains "$output" "task document size OK"
}

@test "validate_docs still reports a genuinely in-progress task as stale by last_updated" {
  # The positive half of the rule above: deleting the freshness call entirely would pass
  # both refutes there, so the gate has to be shown firing on a document whose FIRST
  # `- status:` line really is in_progress.
  _probe_task_file "real-status-probe-01" "in_progress" 'No quoted template here.'
  _probe_task_index_row "## In Progress" "- TASK-real-status-probe-01 in_progress"
  mkdir -p "$DOCS_ROOT/task/.claims/real-status-probe-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "in-progress task is stale by last_updated"
  assert_contains "$output" "days > 7): $DOCS_ROOT/task/TASK-real-status-probe-01.md"

  # And it fires on the value even when the value carries a trailing parenthetical, which
  # is why the comparison is against the first TOKEN rather than the whole field.
  _probe_task_file "real-status-probe-01" "in_progress (r02 fix round)" 'No quoted template here.'
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "days > 7): $DOCS_ROOT/task/TASK-real-status-probe-01.md"
}

@test "validate_docs reads a fenced resume-capsule template as no capsule at all" {
  _probe_task_file "fence-resume-probe-01" "in_progress" '```
- resume_next_action:
- resume_last_verified:
- resume_state_revision:
```'
  _probe_task_index_row "## In Progress" "- TASK-fence-resume-probe-01 in_progress"
  mkdir -p "$DOCS_ROOT/task/.claims/fence-resume-probe-01"

  # Advisory: the truthful finding. The fence-blind probe at 30-rules-task.sh:48 read the
  # quoted template as a declared capsule and suppressed exactly this line.
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "resume capsule missing for in_progress task TASK-fence-resume-probe-01"

  # Strict: the three findings the fence-blind probes invented about a document that
  # declares no capsule at all.
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "resume_next_action is present but empty for in_progress task TASK-fence-resume-probe-01"
  refute_contains "$output" "resume_last_verified is present but empty for in_progress task TASK-fence-resume-probe-01"
  refute_contains "$output" "resume_state_revision is present but non-numeric for in_progress task TASK-fence-resume-probe-01"

  # Positive twin: unfenced, all three are true of the document and must be reported.
  _probe_task_file "fence-resume-probe-01" "in_progress" '- resume_next_action:
- resume_last_verified:
- resume_state_revision:'
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  assert_contains "$output" "resume_next_action is present but empty for in_progress task TASK-fence-resume-probe-01"
  assert_contains "$output" "resume_last_verified is present but empty for in_progress task TASK-fence-resume-probe-01"
  assert_contains "$output" "resume_state_revision is present but non-numeric for in_progress task TASK-fence-resume-probe-01"
  refute_contains "$output" "resume capsule missing for in_progress task TASK-fence-resume-probe-01"
}

@test "validate_docs reports a fenced-only capsule field as missing rather than present-but-empty" {
  # check_field_exists (advisory) and check_field_non_empty (strict) both probed presence
  # fence-blind, so a quoted template made a field that is NOT in the capsule report as
  # "present but empty" under strict and pass silently under advisory.
  cat > "$DOCS_ROOT/task/TASK-fence-field-probe-01.md" <<'EOF'
# TASK-fence-field-probe-01

- title: Presence probe fixture
- objective: a key that exists only inside a fence is not present
- acceptance_criteria: the validator says missing, not empty
- non_goals: none
- affected_modules: docs
- interfaces_changed: none
- data_migrations: none
- test_scope: validate_docs
- risks: none
- risk_level: low
- consumes_plan_ref:
- status: planned
- owner: test
- due_date:
- axis_where: fixture
- axis_verify: bats
- last_updated: 2020-01-01T00:00:00Z

## Quoted template

```
- axis_why: quoted example
```
EOF
  _probe_task_index_row "## Planned" "- TASK-fence-field-probe-01 planned"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "axis_why is missing in task file: $DOCS_ROOT/task/TASK-fence-field-probe-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  assert_contains "$output" "axis_why is missing in task file: $DOCS_ROOT/task/TASK-fence-field-probe-01.md"
  refute_contains "$output" "axis_why is present but empty in task file: $DOCS_ROOT/task/TASK-fence-field-probe-01.md"

  # Positive twin for the other branch: a REAL but empty axis_why is still present-but-empty,
  # so this is not a blanket downgrade of the empty-value rule.
  perl -pi -e 's{^- axis_where: fixture$}{- axis_why:\n- axis_where: fixture}' \
    "$DOCS_ROOT/task/TASK-fence-field-probe-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  assert_contains "$output" "axis_why is present but empty in task file: $DOCS_ROOT/task/TASK-fence-field-probe-01.md"
  refute_contains "$output" "axis_why is missing in task file: $DOCS_ROOT/task/TASK-fence-field-probe-01.md"
}

@test "validate_docs answers key presence with the same column-0 anchor the value read uses" {
  # The INDENTATION axis, the third way these two readers can disagree about one document
  # (fence was r01, first-vs-any-occurrence was r02). field_key_present and
  # extract_field_value both anchor at `^- `; the shared reader tolerates leading space and
  # this one deliberately does not, which is a recorded residual. What is NOT allowed is
  # for the two shell readers to disagree: widening only the probe makes an indented field
  # "present" to the probe and empty to the reader, and the validator then says
  # "present but empty" about a line that literally reads `  - axis_why: indented value`.
  # r02's mutant B did exactly that and survived all 616 tests.
  cat > "$DOCS_ROOT/task/TASK-indent-field-probe-01.md" <<'EOF'
# TASK-indent-field-probe-01

- title: Indentation probe fixture
- objective: presence and value use one anchor
- acceptance_criteria: the validator says missing, not empty
- non_goals: none
- affected_modules: docs
- interfaces_changed: none
- data_migrations: none
- test_scope: validate_docs
- risks: none
- risk_level: low
- consumes_plan_ref:
- status: planned
- owner: test
- due_date:
  - axis_why: indented value the column-0 reader cannot return
- axis_where: fixture
- axis_verify: bats
- last_updated: 2020-01-01T00:00:00Z
EOF
  _probe_task_index_row "## Planned" "- TASK-indent-field-probe-01 planned"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  assert_contains "$output" "axis_why is missing in task file: $DOCS_ROOT/task/TASK-indent-field-probe-01.md"
  refute_contains "$output" "axis_why is present but empty in task file: $DOCS_ROOT/task/TASK-indent-field-probe-01.md"

  # Positive half: at column 0 the same line is read, and its VALUE is returned -- so the
  # anchor is what decides, not the fixture being unreadable for some other reason.
  perl -pi -e 's{^  - axis_why: indented value the column-0 reader cannot return$}{- axis_why: column-0 value}' \
    "$DOCS_ROOT/task/TASK-indent-field-probe-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "axis_why is missing in task file: $DOCS_ROOT/task/TASK-indent-field-probe-01.md"
  refute_contains "$output" "axis_why is present but empty in task file: $DOCS_ROOT/task/TASK-indent-field-probe-01.md"
}

# --- The pre-strip cache ---
#
# The cache decides which BYTES all 80 extract_field_value call sites read, so it is on the
# correctness path, not the performance path. Its known failure mode has already been
# observed once: keying the pre-strip on `doc.resolve()` misses every lookup on macOS,
# where a workspace under /var/folders resolves to /private/var/folders. That mutant passed
# the entire suite, which means the fix had no test binding at all.

_python3_call_log_shim() {
  # Log every python3 argv, then exec the real interpreter. Lets a test see WHICH python
  # the validator spawned rather than only what it printed -- a cache miss is output-neutral.
  local shim_dir="$1"
  local log="$2"
  local real_python3
  real_python3="$(command -v python3)"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/python3" <<SHIM
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
exec "$real_python3" "\$@"
SHIM
  chmod +x "$shim_dir/python3"
}

_on_demand_strip_count() {
  # fence_stripped_file is the only python3 invocation shaped `- <doc>.md <scripts dir>`:
  # the corpus pre-strip passes three arguments, and every other stdin-script call in the
  # validator passes one, three or four. The positive control below proves this can match.
  grep -cE '^- [^ ]+\.md [^ ]+$' "$1" 2>/dev/null || true
}

@test "the pre-strip cache is keyed by the walked docs path, so no field read re-strips" {
  local shim_dir="$TEST_WORKSPACE/py-shim"
  local log="$TEST_WORKSPACE/python3-argv.log"
  local link="$TEST_WORKSPACE/project-link"

  _python3_call_log_shim "$shim_dir" "$log"

  # A docs root reached through a symlink, which is what every macOS run already is:
  # `mktemp -d` yields /var/folders/... and Path.resolve() rewrites it to /private/var/...
  # The extra hop makes the same divergence hold on filesystems where /tmp is not a link.
  ln -s "$TEST_PROJECT" "$link"
  mkdir -p "$DOCS_ROOT/shadow/apps"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
# Shadow Bucket Index

A unit overview looks like:

```markdown
- doc_role: unit_overview
- bucket: widgets
```

- doc_role: bucket_index
- bucket: not-apps
- last_updated: 2026-08-01T00:00:00Z
EOF

  : > "$log"
  run env PATH="$shim_dir:$PATH" "$VALIDATE" "$link" --mode advisory
  [ "$status" -eq 0 ]
  # Positive: the corpus pre-strip really ran, and it ran against the WALKED path.
  assert_contains "$(cat "$log")" "- $link/docs "
  # Positive: the cached bytes are the fence-stripped ones, so the read is fence-aware.
  assert_contains "$output" "invalid bucket in shadow bucket index (apps): expected apps, found not-apps"
  refute_contains "$output" "invalid doc_role in shadow bucket index (apps)"
  # The binding assertion: a wrongly keyed pre-strip misses every lookup, and every field
  # read then pays its own strip. Correct output, hundreds of spawns, 27s -> 39s.
  assert_equal "$(_on_demand_strip_count "$log")" "0"

  # Positive control for the counter itself: an assertion of "zero" is worthless unless
  # the thing being counted is known to be countable.
  : > "$log"
  run env PATH="$shim_dir:$PATH" bash -c \
    "unset FENCE_STRIP_CACHE; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_value '$DOCS_ROOT/shadow/apps/_index.md' doc_role"
  [ "$status" -eq 0 ]
  assert_equal "$output" "bucket_index"
  assert_equal "$(_on_demand_strip_count "$log")" "1"
}

@test "a zero-byte cache entry is refused and rebuilt instead of blanking every field" {
  # In a real run the pre-strip covers the whole corpus, so the cache-HIT branch is the
  # only one ever taken. It validated nothing: one truncated entry made extract_field_value
  # return empty for every key on that document, which reads as a capsule with no metadata.
  local doc="$TEST_WORKSPACE/capsule.md"
  local cache="$TEST_WORKSPACE/fence-cache"
  printf '# Capsule\n\n```\n- owner: quoted-example\n```\n\n- owner: real-owner\n' > "$doc"
  mkdir -p "$cache/$(dirname "${doc#/}")"
  : > "$cache/${doc#/}"

  run bash -c \
    "export FENCE_STRIP_CACHE='$cache'; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_value '$doc' owner"
  [ "$status" -eq 0 ]
  assert_equal "$output" "real-owner"

  # Positive: the poisoned entry was replaced by a real stripped copy, not merely bypassed.
  assert_contains "$(cat "$cache/${doc#/}")" "- owner: real-owner"
  refute_contains "$(cat "$cache/${doc#/}")" "quoted-example"
}

@test "a cache entry the source has outrun is refused, and a current one is still served" {
  # r01 asked for a guard against "a zero-length OR older-than-source entry"; only the
  # zero-length half shipped, so a document rewritten after the corpus pre-strip was
  # answered from the pre-run snapshot for the rest of the run (r02 finding 7).
  local doc="$TEST_WORKSPACE/capsule.md"
  local cache="$TEST_WORKSPACE/fence-cache"
  local entry

  printf '# Capsule\n\n- owner: real-owner\n' > "$doc"
  entry="$cache/${doc#/}"
  mkdir -p "$(dirname "$entry")"

  # Positive half FIRST, so the negative half below cannot pass by the cache being dead:
  # an entry the source has NOT outrun is served verbatim, wrong value and all. That the
  # stale value comes back here is the whole point of having a cache.
  printf '# Capsule\n\n- owner: cached-owner\n' > "$entry"
  touch "$doc"
  sleep 1
  touch "$entry"
  run bash -c \
    "export FENCE_STRIP_CACHE='$cache'; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_value '$doc' owner"
  [ "$status" -eq 0 ]
  assert_equal "$output" "cached-owner"

  # Negative half: the same entry, now demonstrably older than the document it describes.
  printf '# Capsule\n\n- owner: cached-owner\n' > "$entry"
  touch -t 200001010000 "$entry"
  run bash -c \
    "export FENCE_STRIP_CACHE='$cache'; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_value '$doc' owner"
  [ "$status" -eq 0 ]
  assert_equal "$output" "real-owner"
  # And it was rebuilt rather than merely bypassed, so the next read is fast again.
  assert_contains "$(cat "$entry")" "- owner: real-owner"
}

@test "the corpus pre-strip terminates a fully fenced document with a newline, so zero bytes still means corrupt" {
  # "Zero bytes means the entry is corrupt" is only true while EVERY writer ends its output
  # with a newline. Drop the trailing newline from the corpus pre-strip and a document with
  # no content lines at all -- a capsule that is entirely a quoted template -- writes a
  # legitimate 0-byte entry, which the guard above then refuses on every read. The answer
  # stays correct and the cache silently stops working for that document, which is exactly
  # the regression class the cache exists to prevent and is invisible in the output.
  # r02's mutant F survived all 616 tests.
  local shim_dir="$TEST_WORKSPACE/py-shim"
  local log="$TEST_WORKSPACE/python3-argv.log"
  local doc="$DOCS_ROOT/task/TASK-all-fenced-01.md"

  _python3_call_log_shim "$shim_dir" "$log"
  # Line 1 opens the fence and the last line closes it: content_lines is empty.
  printf '```markdown\n# TASK-all-fenced-01\n\n- title: quoted template\n- status: planned\n```\n' > "$doc"
  _probe_task_index_row "## Planned" "- TASK-all-fenced-01 planned"

  : > "$log"
  run env PATH="$shim_dir:$PATH" "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # Positive: the task rules really did read this document, so a strip really was needed.
  assert_contains "$output" "task document size OK (6/220): $doc"
  # Positive: and they read the STRIPPED bytes -- every field is inside the fence, so the
  # capsule is empty, not "planned".
  assert_contains "$output" "status is missing in task file: $doc"
  # The binding assertion: the pre-strip's entry was usable, so no read re-stripped it.
  assert_equal "$(grep -cE "^- $doc [^ ]+$" "$log" || true)" "0"

  # Positive control: this document CAN be counted when it really is stripped on demand.
  : > "$log"
  run env PATH="$shim_dir:$PATH" bash -c \
    "unset FENCE_STRIP_CACHE; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_value '$doc' status"
  [ "$status" -eq 0 ]
  assert_equal "$output" ""
  assert_equal "$(grep -cE "^- $doc [^ ]+$" "$log" || true)" "1"
}

@test "a cache entry becomes visible only when complete, so a concurrent read never sees half a document" {
  # The shell strip writes to "<entry>.strip.$$" and renames. Without the staging step a
  # reader that arrives mid-write finds a NON-EMPTY prefix of the document, which the
  # usable-guard accepts -- every field below the write point then reads as absent, on a
  # document that has them. Only a reader racing the writer can see the difference, so
  # that is what this builds; r02's mutant G survived all 616 tests.
  local doc="$TEST_WORKSPACE/capsule.md"
  local cache="$TEST_WORKSPACE/fence-cache"
  local shim_dir="$TEST_WORKSPACE/slow-py"
  local writer_pid

  # Fence-free, so a plain copy IS the correct stripped output and the slow shim below
  # stays an honest stand-in for the real strip rather than a wrong one.
  printf '# Capsule\n\n- owner: real-owner\n- reviewer: real-reviewer\n' > "$doc"
  mkdir -p "$cache" "$shim_dir"
  cat > "$shim_dir/python3" <<'SHIM'
#!/bin/sh
# Stand-in for the strip: emit the first half, stall, emit the rest. $2 is the source
# document (the real call is `python3 - <src> <scripts dir>` with the script on stdin).
head -n 3 "$2"
sleep 3
tail -n +4 "$2"
SHIM
  chmod +x "$shim_dir/python3"

  (
    export FENCE_STRIP_CACHE="$cache"
    export PATH="$shim_dir:$PATH"
    # shellcheck disable=SC1090
    source "$SCRIPTS_DIR/validate_docs.d/10-parse.sh"
    fence_stripped_file "$doc"
  ) >/dev/null 2>&1 &
  writer_pid=$!

  sleep 1
  # Mid-write: the first half is on disk somewhere. `reviewer` lives in the second half.
  run env PATH="$shim_dir:$PATH" bash -c \
    "export FENCE_STRIP_CACHE='$cache'; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_value '$doc' reviewer"
  [ "$status" -eq 0 ]
  assert_equal "$output" "real-reviewer"

  wait "$writer_pid" || true
  # Positive: the entry that was finally published is the whole document, and the staging
  # file did not survive as cache litter.
  assert_contains "$(cat "$cache/${doc#/}")" "- reviewer: real-reviewer"
  assert_equal "$(find "$cache" -name '*.strip.*' | wc -l | tr -d ' ')" "0"
}

@test "a failed strip degrades to the original document rather than to an empty one" {
  # The "on ANY failure keep the original path" guard was unreachable: zero strips ran in a
  # full validator run. Pointing SCRIPT_DIR at a directory with no shadow_doc_parse makes
  # the strip fail for real, and the answer must degrade to the fence-BLIND value -- wrong
  # about fences, but a document's metadata -- never to nothing at all.
  local doc="$TEST_WORKSPACE/capsule.md"
  local cache="$TEST_WORKSPACE/fence-cache"
  printf '# Capsule\n\n```\n- owner: quoted-example\n```\n\n- owner: real-owner\n' > "$doc"
  mkdir -p "$cache/$(dirname "${doc#/}")" "$TEST_WORKSPACE/no-shared-reader"
  : > "$cache/${doc#/}"

  run bash -c \
    "export FENCE_STRIP_CACHE='$cache' SCRIPT_DIR='$TEST_WORKSPACE/no-shared-reader'; source '$SCRIPTS_DIR/validate_docs.d/10-parse.sh'; extract_field_value '$doc' owner"
  [ "$status" -eq 0 ]
  assert_equal "$output" "quoted-example"
}

@test "validate_docs advisory surfaces an indented unit overview instead of skipping it" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# Shadow Unit Overview\n  - doc_role: unit_overview\n  - last_updated: 2026-01-01T00:00:00Z\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow unit overview missing home_bucket"
}

@test "validate_docs advisory passes a well-formed concern leaf" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/auth.md" <<'EOF'
# Shadow Concern

- doc_role: concern_leaf
- concern_id: auth-flow-01
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow unit/concern docs have valid schema"
}

@test "validate_docs advisory takes the first non-empty concern_id, ignoring an empty stub" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# Shadow Concern\n- doc_role: concern_leaf\n- concern_id:\n- concern_id: auth-flow-01\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/auth.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "shadow concern leaf missing concern_id"
}

@test "validate_docs advisory warns when a done task's capsule still says delegation_status active" {
  cat > "$DOCS_ROOT/task/TASK-orch-done-active-01.md" <<'EOF'
# TASK-orch-done-active-01

- title: done-vs-active contradiction fixture
- status: done
- owner: test
EOF
  printf '%s\n' "- TASK-orch-done-active-01 done" >> "$DOCS_ROOT/task/task-index.md"

  mkdir -p "$DOCS_ROOT/orchestration/orch-done-active-01"
  cat > "$DOCS_ROOT/orchestration/orch-done-active-01/ORCH.md" <<'EOF'
# ORCH-orch-done-active-01

- task_id: orch-done-active-01
- execution_mode: solo
- delegation_status: active
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "delegation_status 'active' contradicts task status done"

  # Promoted to strict per quality-baseline review r01 C1: the ledger
  # contradiction is a strict failure too, not an advisory-only warning.
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "delegation_status 'active' contradicts task status done"
}

@test "validate_docs advisory validates delegation_status enum on planned-task capsules" {
  cat > "$DOCS_ROOT/task/TASK-orch-enum-01.md" <<'EOF'
# TASK-orch-enum-01

- title: planned-task capsule enum fixture
- status: planned
- owner: test
EOF
  printf '%s\n' "- TASK-orch-enum-01 planned" >> "$DOCS_ROOT/task/task-index.md"

  mkdir -p "$DOCS_ROOT/orchestration/orch-enum-01"
  cat > "$DOCS_ROOT/orchestration/orch-enum-01/ORCH.md" <<'EOF'
# ORCH-orch-enum-01

- task_id: orch-enum-01
- execution_mode: solo
- delegation_status: totally_bogus_value
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "orchestration.delegation_status"
  assert_contains "$output" "totally_bogus_value"
}

@test "validate_docs advisory warns on dangling _archive path references" {
  cat > "$DOCS_ROOT/plan/PLAN-archive-ref-01-v1.0.md" <<'EOF'
# PLAN-archive-ref-01-v1.0

- task_id: archive-ref-01
- plan_version: v1.0
- supersedes: docs/plan/_archive/PLAN-archive-ref-01-v0.9.md
- objective: dangling archive reference fixture
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "reference a deleted _archive path"
  assert_contains "$output" "PLAN-archive-ref-01-v1.0.md"
}

@test "empty-graph gate ignores scaffold-only docs projects (routers are not source)" {
  local parent="$TEST_WORKSPACE/docs-only"
  mkdir -p "$parent"
  "$INIT_SCAFFOLD" "$parent" >/dev/null
  git -C "$parent" init --quiet
  git -C "$parent" add -A
  git -C "$parent" -c user.email=t@t -c user.name=t commit -qm init

  run "$VALIDATE" "$parent" --mode strict
  refute_contains "$output" "shadow graph is empty"

  printf 'x=1\n' > "$parent/src.py"
  git -C "$parent" add -A
  git -C "$parent" -c user.email=t@t -c user.name=t commit -qm code

  run "$VALIDATE" "$parent" --mode strict
  assert_contains "$output" "shadow graph is empty"
}

@test "empty-graph gate is not silenced by a garbage unit line" {
  local parent="$TEST_WORKSPACE/garbage-unit"
  mkdir -p "$parent"
  "$INIT_SCAFFOLD" "$parent" >/dev/null
  git -C "$parent" init --quiet
  printf 'x=1\n' > "$parent/src.py"
  git -C "$parent" add -A
  git -C "$parent" -c user.email=t@t -c user.name=t commit -qm init
  python3 - "$parent/docs/shadow/apps/_index.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("- no units detected yet", "- x"))
PY

  run "$VALIDATE" "$parent" --mode advisory
  assert_contains "$output" "shadow graph is empty"

  python3 - "$parent/docs/shadow/apps/_index.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("- x", "- billing-service:\n  - overview_doc: apps/billing-service/overview.md"))
PY

  run "$VALIDATE" "$parent" --mode advisory
  refute_contains "$output" "shadow graph is empty"
}

@test "empty-graph gate is not silenced by a unit row quoted inside a fence" {
  # The two halves of check_shadow_empty_graph read the same bucket _index.md:
  # bucket_index_has_units and shadow_tree_has_source_declarations. The second was
  # fence-aware on purpose and the first was blind, so a quoted example unit row --
  # exactly what a bucket index is expected to explain to its next reader -- manufactured
  # `[PASS] shadow graph is not empty` on a corpus that documents nothing, and the strict
  # FAIL disappeared. A bare scaffold cannot reproduce it: the gate returns early unless a
  # git source root has trackable files outside docs/, which is why this fixture commits
  # src.py first.
  local parent="$TEST_WORKSPACE/fenced-unit"
  mkdir -p "$parent"
  "$INIT_SCAFFOLD" "$parent" >/dev/null
  git -C "$parent" init --quiet
  printf 'x=1\n' > "$parent/src.py"
  git -C "$parent" add -A
  git -C "$parent" -c user.email=t@t -c user.name=t commit -qm init

  # Control: the untouched scaffold declares no unit, so the gate must fire. Without this
  # the fenced case below could pass for the wrong reason.
  run "$VALIDATE" "$parent" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "[FAIL] shadow graph is empty"

  python3 - "$parent/docs/shadow/apps/_index.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(p.read_text().replace(
    "- no units detected yet",
    "```markdown\n- billing-service:\n  - overview_doc: apps/billing-service/overview.md\n```"))
PY

  run "$VALIDATE" "$parent" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "[FAIL] shadow graph is empty"

  # Positive half: the same bytes unfenced are a real declaration and must silence it,
  # so this is fence awareness and not a blanket refusal to see units.
  python3 - "$parent/docs/shadow/apps/_index.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("```markdown\n", "").replace(
    "  - overview_doc: apps/billing-service/overview.md\n```",
    "  - overview_doc: apps/billing-service/overview.md"))
PY

  run "$VALIDATE" "$parent" --mode strict
  refute_contains "$output" "shadow graph is empty"
}

@test "validate_docs advisory warns when a solo ORCH names delegated agents" {
  cat > "$DOCS_ROOT/task/TASK-orch-solo-agents-01.md" <<'EOF'
# TASK-orch-solo-agents-01

- title: solo-with-agents contradiction fixture
- status: planned
- owner: test
EOF
  printf '%s\n' "- TASK-orch-solo-agents-01 planned" >> "$DOCS_ROOT/task/task-index.md"
  mkdir -p "$DOCS_ROOT/orchestration/orch-solo-agents-01"
  cat > "$DOCS_ROOT/orchestration/orch-solo-agents-01/ORCH.md" <<'EOF'
# ORCH-orch-solo-agents-01

- task_id: orch-solo-agents-01
- execution_mode: solo
- delegation_status: active
- reviewer_agents: some-subagent
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "execution_mode=solo contradicts non-empty delegated agent fields"
}

# --- Terminal task statuses (superseded/cancelled) and retroactivity rules ---

write_terminal_task_fixture() {
  local task_id="$1"
  local task_status="$2"
  local disposition="$3"
  local task_file="$DOCS_ROOT/task/TASK-${task_id}.md"

  cat > "$task_file" <<EOF
# TASK-${task_id}

- title: Terminal status fixture
- objective: exercise terminal-status validation
- acceptance_criteria: validator behavior observed
- non_goals: production docs
- affected_modules: docs
- interfaces_changed: none
- data_migrations: none
- test_scope: validate_docs
- risks: low
- risk_level: low
- status: ${task_status}
- disposition: ${disposition}
- owner:
- due_date:
- axis_why: verify terminal status handling
- axis_where: docs validation fixture
- axis_verify: bats
- last_updated: 2026-01-01T00:00:00Z
EOF

  printf '%s\n' "" "## ${4:-Superseded}" "- TASK-${task_id} ${task_status}" >> "$DOCS_ROOT/task/task-index.md"
}

@test "validate_docs strict passes superseded task with disposition and no plan or report" {
  write_terminal_task_fixture "term-pass-01" "superseded" "superseded by TASK-successor-01; remaining scope shipped there" "Superseded"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  refute_contains "$output" "missing plan file for active task TASK-term-pass-01"
  [[ "$output" != *"missing evaluator report"*"TASK-term-pass-01"* ]] || false
}

@test "validate_docs strict fails superseded task without disposition" {
  write_terminal_task_fixture "term-nodisp-01" "superseded" "" "Superseded"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "disposition is present but empty in superseded task"
}

@test "validate_docs strict fails cancelled task without a disposition field" {
  write_terminal_task_fixture "term-cancel-01" "cancelled" "" "Cancelled"
  sed -i.bak '/^- disposition:/d' "$DOCS_ROOT/task/TASK-term-cancel-01.md"
  rm -f "$DOCS_ROOT/task/TASK-term-cancel-01.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "disposition is missing in cancelled task"
}

@test "validate_docs flags task-index section mismatch for terminal statuses" {
  write_terminal_task_fixture "term-idx-01" "superseded" "superseded by TASK-successor-01" "Cancelled"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "task-index section mismatch for TASK-term-idx-01"
}

@test "validate_docs strict skips plan size cap and completeness fields for terminal task artifacts" {
  write_terminal_task_fixture "term-plan-01" "superseded" "superseded by TASK-successor-01" "Superseded"

  {
    printf '%s\n' "# PLAN-term-plan-01-v1.0" "" "- task_id: term-plan-01" "- plan_version: v1.0" "- objective: oversized historical plan"
    for i in $(seq 1 240); do printf '%s\n' "- historical line ${i}"; done
  } > "$DOCS_ROOT/plan/PLAN-term-plan-01-v1.0.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  assert_contains "$output" "plan size cap skipped for terminal task artifact (status=superseded)"
  assert_contains "$output" "plan completeness fields skipped for terminal task artifact"
  refute_contains "$output" "scope is missing in plan"
}

@test "validate_docs strict still enforces plan size cap and scope for active tasks" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "active-plan-cap-01" \
    --task-title "Active plan cap" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  {
    printf '%s\n' "# PLAN-active-plan-cap-01-v1.0" "" "- task_id: active-plan-cap-01" "- plan_version: v1.0" "- objective: oversized active plan"
    for i in $(seq 1 240); do printf '%s\n' "- filler line ${i}"; done
  } > "$DOCS_ROOT/plan/PLAN-active-plan-cap-01-v1.0.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "plan document is too large"
  assert_contains "$output" "scope is missing in plan"
}

@test "validate_docs flags superseded task whose capsule delegation_status is still planned in both modes" {
  write_await_gate_fixture "term-deleg-01" "superseded" "close" "PLAN-term-deleg-01-v1.0" "not_requested" "" "" "" ""
  printf '%s\n' "- disposition: superseded by TASK-successor-01" >> "$DOCS_ROOT/task/TASK-term-deleg-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "orchestration delegation_status 'planned' contradicts terminal task status superseded"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "orchestration delegation_status 'planned' contradicts terminal task status superseded"
}

@test "validate_docs strict passes done task whose evaluator report covers an earlier plan version" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "lineage-done-01" \
    --task-title "Lineage done test" \
    --task-status "done" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --delegation-status "completed" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-lineage-done-01-v1.0.md" <<'EOF'
# PLAN-lineage-done-01-v1.0

- task_id: lineage-done-01
- plan_version: v1.0
- objective: consumed plan
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: reviewed before close
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/plan/PLAN-lineage-done-01-v1.1.md" <<'EOF'
# PLAN-lineage-done-01-v1.1

- task_id: lineage-done-01
- plan_version: v1.1
- objective: post-close review record
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: records the r01 outcome
- stop_conditions: closed
- owner: test
- last_updated: 2026-01-02T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-lineage-done-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-lineage-done-01-v1.0 review (codex)

- task_id: lineage-done-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: accept
- summary: consumed plan reviewed before close
- strengths: complete
- risks: none
- requested_changes: none
- last_updated: 2026-01-01T12:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  assert_contains "$output" "evaluator report exists in plan lineage for done task TASK-lineage-done-01"
}

@test "validate_docs strict fails done task with no evaluator report anywhere in the lineage" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "lineage-miss-01" \
    --task-title "Lineage missing test" \
    --task-status "done" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --delegation-status "completed" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-lineage-miss-01-v1.0.md" <<'EOF'
# PLAN-lineage-miss-01-v1.0

- task_id: lineage-miss-01
- plan_version: v1.0
- objective: never reviewed
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: gate fires
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing evaluator report in plan lineage for done task TASK-lineage-miss-01"
}

@test "validate_docs strict allows empty adversarial debate fields on accept verdict" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "adv-accept-01" \
    --task-title "Adversarial accept" \
    --task-status "planned" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-adv-accept-01-v1.0.md" <<'EOF'
# PLAN-adv-accept-01-v1.0

- task_id: adv-accept-01
- plan_version: v1.0
- objective: adversarial accept fixture
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: accept report passes
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-adv-accept-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-adv-accept-01-v1.0 review (codex)

- task_id: adv-accept-01
- plan_version: v1.0
- evaluator: codex
- review_style: adversarial
- review_round: r01
- verdict: accept
- summary: accepted with nothing to object to
- strengths: clean
- risks: none observed
- requested_changes: none
- objection:
- counterproposal:
- rebuttal:
- residual_risk: did not execute the plan steps, only reviewed them
- last_updated: 2026-01-01T12:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  refute_contains "$output" "objection is present but empty"
}

@test "validate_docs strict still requires adversarial debate fields on revise verdict" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "adv-revise-01" \
    --task-title "Adversarial revise" \
    --task-status "planned" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-adv-revise-01-v1.0.md" <<'EOF'
# PLAN-adv-revise-01-v1.0

- task_id: adv-revise-01
- plan_version: v1.0
- objective: adversarial revise fixture
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: revise report must show the debate
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-adv-revise-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-adv-revise-01-v1.0 review (codex)

- task_id: adv-revise-01
- plan_version: v1.0
- evaluator: codex
- review_style: adversarial
- review_round: r01
- verdict: revise
- summary: pushing back without stating the objection
- strengths: none
- risks: some
- requested_changes: fix things
- objection:
- counterproposal:
- rebuttal:
- residual_risk: unclear
- last_updated: 2026-01-01T12:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "objection is present but empty in adversarial evaluator report"
}

@test "validate_docs strict requires residual_risk even on adversarial accept verdict" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "adv-resid-01" \
    --task-title "Adversarial residual" \
    --task-status "planned" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-adv-resid-01-v1.0.md" <<'EOF'
# PLAN-adv-resid-01-v1.0

- task_id: adv-resid-01
- plan_version: v1.0
- objective: residual risk fixture
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: residual_risk stays required
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-adv-resid-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-adv-resid-01-v1.0 review (codex)

- task_id: adv-resid-01
- plan_version: v1.0
- evaluator: codex
- review_style: adversarial
- review_round: r01
- verdict: accept
- summary: accept but silent on coverage
- strengths: clean
- risks: none observed
- requested_changes: none
- objection:
- counterproposal:
- rebuttal:
- residual_risk:
- last_updated: 2026-01-01T12:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "residual_risk is present but empty in adversarial evaluator report"
}

@test "validate_docs strict lineage gate ignores a report naming a phantom plan version" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "lineage-phantom-01" \
    --task-title "Lineage phantom test" \
    --task-status "done" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --delegation-status "completed" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-lineage-phantom-01-v1.0.md" <<'EOF'
# PLAN-lineage-phantom-01-v1.0

- task_id: lineage-phantom-01
- plan_version: v1.0
- objective: only real plan version
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: phantom-version report does not satisfy the gate
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-lineage-phantom-01-v9.9-review-codex-r01.md" <<'EOF'
# PLAN-lineage-phantom-01-v9.9 review (codex)

- task_id: lineage-phantom-01
- plan_version: v9.9
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: accept
- summary: report against a plan version that never existed
- strengths: none
- risks: none
- requested_changes: none
- last_updated: 2026-01-01T12:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing evaluator report in plan lineage for done task TASK-lineage-phantom-01"
}

@test "validate_docs strict keeps active-task gates on a status with a parenthetical note" {
  write_terminal_task_fixture "noted-status-01" "done (paused for later)" "" "Done"
  sed -i.bak '/^- disposition:/d' "$DOCS_ROOT/task/TASK-noted-status-01.md"
  rm -f "$DOCS_ROOT/task/TASK-noted-status-01.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  assert_contains "$output" "invalid task.status value"
  assert_contains "$output" "missing plan file for active task TASK-noted-status-01"
}

@test "init_docs_scaffold task-index template includes terminal status sections" {
  # The scaffold's golden output must track the validator's section map
  # (review r01 sonnet #2): a fresh project needs a home for terminal rows.
  run grep -c '^## ' "$DOCS_ROOT/task/task-index.md"
  [ "$status" -eq 0 ]
  grep -q '^## Superseded$' "$DOCS_ROOT/task/task-index.md"
  grep -q '^## Cancelled$' "$DOCS_ROOT/task/task-index.md"
  grep -q '^## Done$' "$DOCS_ROOT/task/task-index.md"
}

# --- Output format contract: --format text|json ---

# Extract field $3 (id/caller/tier/message) of the first issue whose message
# contains $2, from JSON in $1.
json_issue_field() {
  python3 -c '
import json, sys
obj = json.loads(sys.argv[1])
needle = sys.argv[2]
field = sys.argv[3]
for issue in obj["issues"]:
    if needle in issue["message"]:
        sys.stdout.write(issue[field])
        break
' "$1" "$2" "$3"
}

@test "validate_docs default output equals --format text byte-for-byte (passing scaffold)" {
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  local noflag_status="$status"
  local noflag_output="$output"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format text
  [ "$status" -eq "$noflag_status" ]
  [ "$output" = "$noflag_output" ]
}

@test "validate_docs default output equals --format text byte-for-byte (with FAIL and WARN lines)" {
  write_terminal_task_fixture "fmt-parity-01" "superseded" "" "Superseded"

  # strict path exercises [FAIL]/[PASS] lines
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  local strict_noflag_status="$status"
  local strict_noflag_output="$output"
  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format text
  [ "$status" -eq "$strict_noflag_status" ]
  [ "$output" = "$strict_noflag_output" ]

  # advisory path exercises [WARN]/[PASS] lines
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  local adv_noflag_status="$status"
  local adv_noflag_output="$output"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory --format text
  [ "$status" -eq "$adv_noflag_status" ]
  [ "$output" = "$adv_noflag_output" ]
}

@test "validate_docs --format json emits a single parseable JSON object (passing scaffold)" {
  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
obj = json.loads(sys.stdin.read())
assert obj["format_version"] == 1, obj
assert obj["mode"] == "strict", obj
assert obj["result"] == "pass", obj
assert obj["counts"]["fail"] == 0, obj
assert obj["issues"] == [], obj
assert set(obj.keys()) == {"mode","project_root","format_version","issues","counts","result"}, obj
'
}

@test "validate_docs --format json rejects an invalid format value" {
  run "$VALIDATE" "$TEST_PROJECT" --format xml
  [ "$status" -eq 1 ]
  assert_contains "$output" "[ERROR] Invalid format: xml"
}

@test "validate_docs --format json captures the emitting check-function name as issue id" {
  # disposition failure is raised by check_field_non_empty (helper emitter)
  # called from the top-level task-file loop, so caller is "main".
  write_terminal_task_fixture "json-id-disp-01" "superseded" "" "Superseded"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format json
  [ "$status" -eq 1 ]

  local needle="disposition is present but empty in superseded task"
  [ "$(json_issue_field "$output" "$needle" "id")" = "check_field_non_empty" ]
  [ "$(json_issue_field "$output" "$needle" "caller")" = "main" ]
}

@test "validate_docs --format json records the invoking rule as caller for helper-emitted issues" {
  # The await-gate ORCH fixture leaves supervisor_agent empty; in strict mode
  # check_field_non_empty flags it from INSIDE check_orchestration_file_for_task,
  # so (id, caller) discriminates this rule from other users of the same helper.
  write_await_gate_fixture "json-caller-01" "in_progress" "implementation_start" "PLAN-json-caller-01-v1.0" "requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format json
  [ "$status" -eq 1 ]

  local needle="supervisor_agent is present but empty in orchestration"
  [ "$(json_issue_field "$output" "$needle" "id")" = "check_field_non_empty" ]
  [ "$(json_issue_field "$output" "$needle" "caller")" = "check_orchestration_file_for_task" ]
}

@test "validate_docs --format json tags top-level phase-flow issues with id main" {
  # A task absent from the index is flagged by the top-level flow, not a helper.
  cat > "$DOCS_ROOT/task/TASK-json-id-main-01.md" <<EOF
# TASK-json-id-main-01

- title: main id fixture
- status: planned
- risk_level: low
- axis_why: x
- axis_where: y
- axis_verify: z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format json
  [ "$status" -eq 1 ]

  local needle="task-index missing row for TASK-json-id-main-01"
  [ "$(json_issue_field "$output" "$needle" "id")" = "main" ]
  [ "$(json_issue_field "$output" "$needle" "caller")" = "main" ]
}

@test "validate_docs CLI errors keep json-mode stdout empty and route usage to stderr" {
  # Unknown option: stdout must stay pure (empty) so json consumers never see
  # usage text; the [ERROR] line and usage() both land on stderr.
  run bash -c "\"$VALIDATE\" \"$TEST_PROJECT\" --format json --bogus-option 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]

  # Missing option value path goes through require_option_value -> usage >&2.
  run bash -c "\"$VALIDATE\" \"$TEST_PROJECT\" --format json --mode 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]

  # The stderr side still carries the diagnostics.
  run bash -c "\"$VALIDATE\" \"$TEST_PROJECT\" --format json --bogus-option 2>&1 1>/dev/null"
  [ "$status" -eq 1 ]
  assert_contains "$output" "[ERROR] Unknown option: --bogus-option"
  assert_contains "$output" "Usage:"

  # -h/--help keeps usage on stdout and exits 0.
  run bash -c "\"$VALIDATE\" --help 2>/dev/null"
  [ "$status" -eq 0 ]
  assert_contains "$output" "Usage:"
}

@test "validate_docs --format json survives hostile message content (quotes, backslash, tab, non-ASCII)" {
  # A bad status value is echoed verbatim into the enum-check message. A literal
  # tab in the value would break naive tab-splitting; the NUL-record format must
  # round-trip it intact through JSON.
  printf '%s\n' \
    '# TASK-json-id-hostile-01' \
    '' \
    '- title: hostile' \
    $'- status: bad"\\\tval\xc3\x9ce' \
    '- axis_why: x' \
    '- axis_where: y' \
    '- axis_verify: z' > "$DOCS_ROOT/task/TASK-json-id-hostile-01.md"
  printf '%s\n' "- TASK-json-id-hostile-01 x" >> "$DOCS_ROOT/task/task-index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format json

  echo "$output" | python3 -c '
import json, sys
obj = json.loads(sys.stdin.read())
matches = [i for i in obj["issues"] if "invalid task.status value" in i["message"]]
assert matches, obj
msg = matches[0]["message"]
assert matches[0]["id"] == "check_enum_membership", matches[0]
# quote, backslash, real tab, and U+00DC must all survive intact
assert "bad\"\\\tvalÜe" in msg, repr(msg)
'
}

@test "validate_docs --format json result and exit code mirror text mode (advisory vs strict)" {
  # A task absent from the index raises the same unconditional fail() in both
  # modes, so it demotes fail-tier (strict) to warn-tier (advisory).
  cat > "$DOCS_ROOT/task/TASK-json-tier-01.md" <<EOF
# TASK-json-tier-01

- title: tier fixture
- status: planned
- risk_level: low
- axis_why: x
- axis_where: y
- axis_verify: z
EOF

  # strict: exit 1, result fail, one fail-tier issue
  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format json
  local strict_json_status="$status"
  local strict_json="$output"
  run "$VALIDATE" "$TEST_PROJECT" --mode strict --format text
  [ "$status" -eq "$strict_json_status" ]
  [ "$strict_json_status" -eq 1 ]
  echo "$strict_json" | python3 -c '
import json, sys
o = json.loads(sys.stdin.read())
assert o["result"] == "fail", o
assert o["counts"]["fail"] == 1, o
assert o["counts"]["warn"] == 0, o
assert all(i["tier"] == "fail" for i in o["issues"]), o
'

  # advisory: exit 0, result pass, the same issue demoted to warn tier
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory --format json
  local adv_json_status="$status"
  local adv_json="$output"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory --format text
  [ "$status" -eq "$adv_json_status" ]
  [ "$adv_json_status" -eq 0 ]
  echo "$adv_json" | python3 -c '
import json, sys
o = json.loads(sys.stdin.read())
assert o["result"] == "pass", o
assert o["counts"]["fail"] == 0, o
assert o["counts"]["warn"] == 1, o
assert all(i["tier"] == "warn" for i in o["issues"]), o
'
}

# --- linked_decisions rationale edges ---

_rationale_capsule() {
  # $1 = decision id suffix, $2 = status
  cat > "$DOCS_ROOT/decisions/decision-${1}.md" <<EOF
# decision-${1}

- decision_id: ${1}
- title: fixture
- date: 2026-08-01
- scope_type: task
- status: ${2}
- chosen_by: user
- linked_task: TASK-${1}
- last_updated: 2026-08-01T00:00:00Z
EOF
}

_rationale_overview() {
  # $1 = linked_decisions value (may be empty)
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  {
    printf '# Shadow Unit Overview\n\n- doc_role: unit_overview\n- home_bucket: apps\n'
    printf -- '- linked_decisions: %s\n' "$1"
    printf -- '- last_updated: 2026-08-01T00:00:00Z\n'
  } > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
}

@test "validate_docs advisory accepts linked_decisions pointing at an accepted capsule" {
  _rationale_capsule rationale-ok-01 accepted
  _rationale_overview "docs/decisions/decision-rationale-ok-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow linked_decisions resolve to operative decision capsules"
  refute_contains "$output" "[WARN] shadow linked_decisions"
}

@test "validate_docs advisory warns when a linked_decisions entry does not resolve" {
  _rationale_overview "docs/decisions/decision-nowhere-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow linked_decisions reference does not resolve (docs/decisions/decision-nowhere-01.md)"
}

@test "validate_docs advisory warns when linked_decisions points at a superseded decision" {
  _rationale_capsule rationale-old-01 superseded
  _rationale_overview "docs/decisions/decision-rationale-old-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "points at a superseded decision (docs/decisions/decision-rationale-old-01.md); link the successor"
}

@test "validate_docs notes a proposed linked_decisions target without failing strict" {
  _rationale_capsule rationale-proposed-01 proposed
  _rationale_overview "docs/decisions/decision-rationale-proposed-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "points at a proposed decision (docs/decisions/decision-rationale-proposed-01.md)"
  # soft_warn never contributes to the issue count, in either mode.
  [ "$status" -eq 0 ]
}

@test "validate_docs advisory warns when a linked_decisions target has no readable status" {
  mkdir -p "$DOCS_ROOT/decisions"
  printf '# decision-rationale-nostatus-01\n\n- decision_id: rationale-nostatus-01\n' \
    > "$DOCS_ROOT/decisions/decision-rationale-nostatus-01.md"
  _rationale_overview "docs/decisions/decision-rationale-nostatus-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow linked_decisions target has no readable status (docs/decisions/decision-rationale-nostatus-01.md)"
}

@test "validate_docs advisory warns on a duplicate or empty linked_decisions member" {
  _rationale_capsule rationale-dup-01 accepted
  _rationale_overview "docs/decisions/decision-rationale-dup-01.md, docs/decisions/decision-rationale-dup-01.md, , docs/decisions/decision-rationale-dup-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "lists a duplicate decision (docs/decisions/decision-rationale-dup-01.md)"
  assert_contains "$output" "shadow linked_decisions has an empty member"
}

@test "validate_docs advisory warns when linked_decisions names the decision index" {
  _rationale_overview "docs/decisions/decision-index.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "must name a decision capsule, not the index (docs/decisions/decision-index.md)"
}

@test "validate_docs advisory warns on a bare-id linked_decisions member" {
  _rationale_overview "n26fa0-01"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "must be a repo-relative docs/decisions/decision-<id>.md path (n26fa0-01)"
}

@test "validate_docs advisory warns when linked_decisions sits on a non-carrier doc_role" {
  _rationale_capsule rationale-role-01 accepted
  cat > "$DOCS_ROOT/shadow/_global.md" <<'EOF'
# Shadow Global

- doc_role: global
- linked_decisions: docs/decisions/decision-rationale-role-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "only valid on unit_overview or concern_leaf (doc_role=global)"
}

@test "validate_docs advisory warns when linked_decisions is written as nested bullets" {
  _rationale_capsule rationale-nested-01 accepted
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- linked_decisions:
  - docs/decisions/decision-rationale-nested-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "must be an inline comma list, not nested bullets"
}

@test "validate_docs advisory stays silent on an empty or fenced-only linked_decisions" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- linked_decisions:
- last_updated: 2026-08-01T00:00:00Z

Template example:

```
- linked_decisions: docs/decisions/decision-fenced-example-01.md
```
~~~
- linked_decisions: docs/decisions/decision-tilde-example-01.md
~~~
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "shadow linked_decisions"
}

@test "the nav-link and linked_decisions rules agree on a tilde marker inside a backtick block" {
  # One document, two rules, one fence grammar. Both a navigation reference and a
  # rationale edge sit inside the SAME block, whose closing backtick line follows a
  # `~~~` line. A reader that closes on any marker sees the block end early (leaking
  # the examples) and then reopens at the real closing fence (swallowing the fields
  # below), so the two rules would disagree about every line in this file.
  _rationale_capsule rationale-agree-01 accepted
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps

```
- next_docs: nowhere-nav-example.md
- linked_decisions: docs/decisions/decision-nowhere-example-01.md
~~~
```

- next_docs: apps/app-a/really-missing.md
- linked_decisions: docs/decisions/decision-rationale-agree-01.md
- last_updated: 2026-08-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # Neither rule reports anything it read inside the block ...
  refute_contains "$output" "nowhere-nav-example.md"
  refute_contains "$output" "decision-nowhere-example-01.md"
  # ... and BOTH read past it. One positive assertion per rule, so a rule that has
  # stopped reporting altogether fails this test instead of passing it: the nav-link
  # half is the dangling reference below the fence, the rationale half is the PASS
  # line, which only prints when the parser counted a real declaration.
  assert_contains "$output" "really-missing.md"
  assert_contains "$output" "shadow linked_decisions resolve to operative decision capsules"
}

@test "validate_docs strict mode skips the linked_decisions check entirely" {
  _rationale_overview "docs/decisions/decision-nowhere-01.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "shadow linked_decisions"
}

@test "validate_docs advisory warns when the shadow router updated_by_task does not resolve" {
  perl -0pi -e 's{^- updated_by_task:.*$}{- updated_by_task: TASK-does-not-exist-01}m' \
    "$DOCS_ROOT/shadow/project-shadow.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow router updated_by_task does not resolve to a task file (TASK-does-not-exist-01)"
}

@test "validate_docs advisory accepts a resolving router updated_by_task and ignores an empty one" {
  # Scaffold ships the field empty: that is "not yet claimed", not a defect.
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "shadow router updated_by_task"

  printf '# TASK-router-link-01\n\n- title: t\n- status: planned\n- owner: test\n' \
    > "$DOCS_ROOT/task/TASK-router-link-01.md"
  printf -- '- TASK-router-link-01 | planned | t\n' >> "$DOCS_ROOT/task/task-index.md"
  perl -0pi -e 's{^- updated_by_task:.*$}{- updated_by_task: TASK-router-link-01}m' \
    "$DOCS_ROOT/shadow/project-shadow.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow router updated_by_task resolves to a real task"
}

@test "validate_docs advisory nudges an unfilled policy template_linked_decision only once decisions exist" {
  # Fresh scaffold: policy files carry only their shipped placeholders and there
  # is no local capsule to link, so the nudge must stay silent.
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "still carries only the shipped template_linked_decision placeholder"

  _rationale_capsule policy-nudge-01 accepted
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow rule registry still carries only the shipped template_linked_decision placeholder"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "still carries only the shipped template_linked_decision placeholder"
}

@test "validate_docs advisory resolves a concrete policy linked_decision value" {
  _rationale_capsule policy-real-01 accepted
  printf -- '- linked_decision: decision-policy-real-01\n' >> "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  printf -- '- linked_decision: decision-policy-missing-01\n' >> "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "shadow validator catalog linked_decision does not resolve"
  assert_contains "$output" "shadow regex pattern registry linked_decision does not resolve to a decision capsule (decision-policy-missing-01)"
}

@test "validate_docs advisory flags a trailing-comma linked_decisions member" {
  # `IFS=',' read -a` silently drops a trailing empty field, which would let the
  # bash rule accept a value the python report (str.split) reports as malformed.
  # The two implementations must agree on the grammar, so this pins the split.
  _rationale_capsule rationale-trailing-01 accepted
  _rationale_overview "docs/decisions/decision-rationale-trailing-01.md,"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow linked_decisions has an empty member"
}

# --- hop-2 selection_summary ---

_selection_fixture() {
  # $1 = row selection_summary, $2 = overview unit_summary
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<EOF
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
  - overview_doc: app-a/overview.md
  - selection_summary: $1
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<EOF
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- unit_summary: $2
- last_updated: 2026-08-01T00:00:00Z
EOF
}

@test "validate_docs advisory accepts a selection_summary that prefixes the unit_summary" {
  _selection_fixture "Auth service." "Auth service. Owns login, token refresh, and session revocation."
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow bucket rows carry a selection_summary that prefixes their unit overview"
}

@test "validate_docs advisory flags selection_summary drift from the row side" {
  _selection_fixture "Billing service." "Auth service. Owns login, token refresh, and session revocation."
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow selection_summary is not a prefix of the overview unit_summary (app-a -> app-a/overview.md)"
}

@test "validate_docs advisory flags selection_summary drift from the overview side" {
  # The row is untouched; the overview opening was rewritten. Same finding, which is
  # the point of binding the two: neither side can drift unnoticed.
  _selection_fixture "Auth service." "Identity service. Owns login, token refresh, and session revocation."
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow selection_summary is not a prefix of the overview unit_summary"
}

@test "validate_docs advisory flags a missing selection_summary on a unit row" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<EOF
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
  - overview_doc: app-a/overview.md
EOF
  printf '# o\n\n- doc_role: unit_overview\n- home_bucket: apps\n- unit_summary: Auth service.\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow bucket unit is missing selection_summary (app-a)"
}

@test "validate_docs advisory flags an over-cap selection_summary" {
  local long
  long="$(python3 -c "print('x' * 251)")"
  _selection_fixture "$long" "$long and more"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow selection_summary exceeds 250 characters (app-a, 251)"
}

@test "validate_docs advisory flags an overview with no unit_summary to prefix" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<EOF
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
  - overview_doc: app-a/overview.md
  - selection_summary: Auth service.
EOF
  printf '# o\n\n- doc_role: unit_overview\n- home_bucket: apps\n' > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow selection_summary target overview has no unit_summary (app-a -> app-a/overview.md)"
}

@test "validate_docs advisory flags the removed secondary_tags field if it comes back" {
  _selection_fixture "Auth service." "Auth service. Owns login."
  printf -- '- secondary_tags: shell, python\n' >> "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow doc still declares the removed secondary_tags field"
}

@test "validate_docs strict mode skips the selection_summary check entirely" {
  _selection_fixture "Billing service." "Auth service. Owns login."
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "selection_summary"
}

@test "validate_docs advisory flags a unit row with no overview_doc" {
  # The navigation-link check only follows references that exist, so nothing else
  # reports a row that points nowhere (external review r01).
  mkdir -p "$DOCS_ROOT/shadow/apps"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<EOF
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow bucket unit row has no overview_doc (app-a)"
}

@test "validate_docs advisory flags a multi-line selection_summary continuation" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<EOF
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
  - overview_doc: app-a/overview.md
  - selection_summary: Auth service.
    a sneaky continuation line
EOF
  printf '# o\n\n- doc_role: unit_overview\n- home_bucket: apps\n- unit_summary: Auth service. Owns login.\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow selection_summary must be a single line (app-a)"
}

@test "validate_docs advisory flags a degenerate one-character selection_summary" {
  _selection_fixture "A" "A short summary that starts with A."
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow selection_summary is too short to select anything (app-a, 1 chars)"
}

@test "validate_docs advisory ignores secondary_tags in fenced examples and archive trees" {
  _selection_fixture "Auth service." "Auth service. Owns login."
  mkdir -p "$DOCS_ROOT/shadow/_deprecated/old"
  printf '# old\n\n- doc_role: unit_overview\n- secondary_tags: legacy\n' \
    > "$DOCS_ROOT/shadow/_deprecated/old/overview.md"
  cat >> "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<EOF

The removed field looked like this:

\`\`\`
- secondary_tags: shell, python
\`\`\`
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # Frozen history and a quoted example are not regressions.
  refute_contains "$output" "still declares the removed secondary_tags field"
}

@test "validate_docs advisory flags a selection_summary that is a substring but not a prefix" {
  # This is the test that pins the word "prefix". Without it, mutating startswith()
  # to a containment check passes the whole suite and the legislated relation
  # silently degrades to "appears anywhere" (Opus 5 review r01, finding R01-02).
  _selection_fixture "Owns login and token refresh." "Auth service. Owns login and token refresh."
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow selection_summary is not a prefix of the overview unit_summary (app-a -> app-a/overview.md)"
}

@test "validate_docs advisory does not invent unit rows from bucket-index header fields" {
  # `- bucket:` and `- last_updated:` left empty are the Bucket Registry Template's
  # own shape; a scan not bounded to "## Units" reads them as rows with no
  # overview_doc (Opus 5 review r01, finding R01-01).
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
# Shadow Bucket Index

- doc_role: bucket_index
- bucket:
- last_updated:

## Units
- app-a:
  - overview_doc: app-a/overview.md
  - selection_summary: Auth service.
EOF
  printf '# o\n\n- doc_role: unit_overview\n- home_bucket: apps\n- unit_summary: Auth service. Owns login.\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "has no overview_doc"
  assert_contains "$output" "shadow bucket rows carry a selection_summary that prefixes their unit overview"
}

@test "validate_docs advisory treats a tilde-fenced example as an example in every shadow rule" {
  # Before the recorded decision the navigation-link check was blind to
  # ~~~ fences while extract_shadow_field honored them, so this same block was a
  # dangling reference to one rule and an example to another.
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
  - overview_doc: app-a/overview.md
  - selection_summary: Auth service.
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- unit_summary: Auth service. Owns login.
- last_updated: 2026-08-01T00:00:00Z

Template example, not a real reference:

~~~
- next_docs: apps/app-a/does-not-exist.md
- home_bucket: not-a-bucket
~~~
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "does-not-exist.md"
  refute_contains "$output" "home_bucket is not a known bucket"
}

@test "validate_docs advisory still honors backtick fences after the parser unification" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
  - overview_doc: app-a/overview.md
  - selection_summary: Auth service.
EOF
  {
    printf '# Shadow Unit Overview\n\n- doc_role: unit_overview\n- home_bucket: apps\n'
    printf -- '- unit_summary: Auth service. Owns login.\n- last_updated: 2026-08-01T00:00:00Z\n\n'
    printf '%s\n- next_docs: apps/app-a/also-missing.md\n%s\n' '```' '```'
  } > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "also-missing.md"
}

@test "validate_docs advisory still sees references OUTSIDE fences (fence handling is not a blanket mute)" {
  # Positive counterpart to the fenced-example tests. Without it, mutating is_fence
  # to always-true makes every fence-aware rule a no-op and the negative assertions
  # all still pass (Opus 5 review r01, finding 3).
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
  - overview_doc: app-a/overview.md
  - selection_summary: Auth service.
EOF
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket: apps
- unit_summary: Auth service. Owns login.
- next_docs: apps/app-a/genuinely-missing.md
- last_updated: 2026-08-01T00:00:00Z

~~~
- next_docs: apps/app-a/only-an-example.md
~~~
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # The real reference is reported; the fenced one is not. Both halves matter.
  assert_contains "$output" "shadow navigation reference does not resolve: next_docs -> apps/app-a/genuinely-missing.md"
  refute_contains "$output" "only-an-example.md"
  # And the fence-aware field reader still finds the field it should.
  refute_contains "$output" "shadow unit overview missing home_bucket"
}

@test "validate_docs advisory closes a fence only on a same-character marker" {
  # A ~~~ line inside a ``` block must not flip the state: the first cut of the
  # shared reader toggled on any marker, which swallowed a real dangling reference
  # and made the rule print PASS (Opus 5 review r01, finding 1, case A).
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
# Shadow Bucket Index

- doc_role: bucket_index
- bucket: apps
- last_updated: 2026-08-01T00:00:00Z

## Units
- app-a:
  - overview_doc: app-a/overview.md
  - selection_summary: Auth service.
EOF
  {
    printf '# Shadow Unit Overview\n\n- doc_role: unit_overview\n- home_bucket: apps\n'
    printf -- '- unit_summary: Auth service. Owns login.\n- last_updated: 2026-08-01T00:00:00Z\n\n'
    printf 'Documenting fence syntax inside a backtick block:\n\n'
    printf '%s\n~~~\n%s\n\n' '```' '```'
    printf -- '- next_docs: apps/app-a/after-the-block.md\n'
  } > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  assert_contains "$output" "shadow navigation reference does not resolve: next_docs -> apps/app-a/after-the-block.md"
}
