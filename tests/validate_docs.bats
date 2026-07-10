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
  [[ "$output" == *"[WARN] external review await gate not satisfied for TASK-await-gate-requested-01: external_review_status=requested"* ]]
}

@test "validate_docs advisory warns when dependent external review is not requested" {
  write_await_gate_fixture "await-gate-not-requested-01" "in_progress" "implementation_start" "PLAN-await-gate-not-requested-01-v1.0" "not_requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate not satisfied for TASK-await-gate-not-requested-01: external_review_status=not_requested"* ]]
}

@test "validate_docs advisory warns when dependent external review is blocked" {
  write_await_gate_fixture "await-gate-blocked-01" "in_progress" "implementation_start" "PLAN-await-gate-blocked-01-v1.0" "blocked" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate not satisfied for TASK-await-gate-blocked-01: external_review_status=blocked"* ]]
}

@test "validate_docs advisory warns when ingested review lacks required route accept" {
  local result_ref
  result_ref="$(create_await_gate_result_dir "await-gate-missing-route-01" "v1.0" "r01" "agy:current=accept" "claude:current=revise")"
  write_await_gate_fixture "await-gate-missing-route-01" "in_progress" "implementation_start" "PLAN-await-gate-missing-route-01-v1.0" "ingested" "agy:current, claude:current" "$result_ref" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate missing accepted route artifact for claude:current"* ]]
}

@test "validate_docs advisory passes when ingested review has all required route accepts" {
  local result_ref
  result_ref="$(create_await_gate_result_dir "await-gate-accept-01" "v1.0" "r01" "agy:current=accept" "claude:current=accept")"
  write_await_gate_fixture "await-gate-accept-01" "in_progress" "implementation_start" "PLAN-await-gate-accept-01-v1.0" "ingested" "agy:current, claude:current" "$result_ref" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"[WARN] external review await gate"* ]]
  [[ "$output" == *"[PASS] external review await gate satisfied for PLAN-await-gate-accept-01-v1.0"* ]]
}

@test "validate_docs advisory warns when waived review lacks ref or reason" {
  write_await_gate_fixture "await-gate-waived-missing-01" "in_progress" "implementation_start" "PLAN-await-gate-waived-missing-01-v1.0" "waived" "agy:current" "" "" "user approved waiver"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate waiver requires concrete external_review_waiver_ref and external_review_waiver_reason"* ]]
}

@test "validate_docs advisory passes when waived review has concrete ref and reason" {
  write_await_gate_fixture "await-gate-waived-ok-01" "in_progress" "implementation_start" "PLAN-await-gate-waived-ok-01-v1.0" "waived" "agy:current" "" "docs/decisions/decision-waive-01.md" "user accepted external review waiver for this implementation"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"[WARN] external review await gate"* ]]
  [[ "$output" == *"[PASS] external review await gate waived with concrete provenance"* ]]
}

@test "validate_docs advisory does not warn independent task when ORCH does not require implementation review" {
  write_await_gate_fixture "await-gate-independent-01" "in_progress" "close" "" "requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"[WARN] external review await gate"* ]]
}

@test "validate_docs advisory warns when dependent task misses external_review_status" {
  write_await_gate_fixture "await-gate-missing-status-01" "in_progress" "implementation_start" "PLAN-await-gate-missing-status-01-v1.0" "" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate requires external_review_status for TASK-await-gate-missing-status-01"* ]]
}

@test "validate_docs advisory warns when implementation-start review omits consumes_plan_ref" {
  write_await_gate_fixture "await-gate-no-consumes-01" "in_progress" "implementation_start" "" "requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate requires same-task consumes_plan_ref for TASK-await-gate-no-consumes-01"* ]]
}

@test "validate_docs advisory warns when external_review_status is outside allowlist enum" {
  write_await_gate_fixture "await-gate-invalid-status-01" "in_progress" "implementation_start" "PLAN-await-gate-invalid-status-01-v1.0" "skipped" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate has invalid external_review_status for TASK-await-gate-invalid-status-01: skipped"* ]]
}

@test "validate_docs advisory warns when external_review_required_for is outside allowlist enum" {
  write_await_gate_fixture "await-gate-invalid-required-for-01" "in_progress" "before_implementation" "PLAN-await-gate-invalid-required-for-01-v1.0" "not_requested" "agy:current" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] invalid orchestration.external_review_required_for value in "*": before_implementation (allowed: plan_acceptance|implementation_start|commit|close)"* ]]
}

@test "validate_docs advisory warns when ingested result_ref directory is absent" {
  write_await_gate_fixture "await-gate-missing-dir-01" "in_progress" "implementation_start" "PLAN-await-gate-missing-dir-01-v1.0" "ingested" "agy:current" "docs/orchestration/await-gate-missing-dir-01/external-cli/v1.0/r01" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate result_ref directory missing or not a directory"* ]]
}

@test "validate_docs advisory warns when waived review uses placeholder values" {
  write_await_gate_fixture "await-gate-waived-placeholder-01" "in_progress" "implementation_start" "PLAN-await-gate-waived-placeholder-01-v1.0" "waived" "agy:current" "" "TBD" "TODO"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate waiver requires concrete external_review_waiver_ref and external_review_waiver_reason"* ]]
}

@test "validate_docs advisory warns when ingested review routes are empty or unparseable" {
  local result_ref
  result_ref="$(create_await_gate_result_dir "await-gate-empty-routes-01" "v1.0" "r01" "agy:current=accept")"
  write_await_gate_fixture "await-gate-empty-routes-01" "in_progress" "implementation_start" "PLAN-await-gate-empty-routes-01-v1.0" "ingested" "" "$result_ref" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate requires non-empty required_review_routes"* ]]
}

@test "validate_docs advisory warns when required review route is not registry resolvable" {
  local result_ref
  result_ref="$(create_await_gate_result_dir "await-gate-unknown-route-01" "v1.0" "r01")"
  write_await_gate_fixture "await-gate-unknown-route-01" "in_progress" "implementation_start" "PLAN-await-gate-unknown-route-01-v1.0" "ingested" "agy:not-a-real-route" "$result_ref" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] external review await gate required_review_routes must use registered colon route: agy:not-a-real-route"* ]]
}

@test "validate_docs rejects legacy root orchestration paths" {
  cat > "$DOCS_ROOT/orchestration/ORCH-legacy-01.md" <<'EOF'
# ORCH-legacy-01

- task_id: legacy-01
EOF
  mkdir -p "$DOCS_ROOT/orchestration/external-cli"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"legacy root orchestration file is not supported"* ]]
  [[ "$output" == *"legacy external CLI handoff root is not supported"* ]]
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
  [[ "$output" == *"orphaned orchestration capsule with no matching task file"* ]]
  [[ "$output" == *"docs/orchestration/ghost-capsule-01"* ]]
  [[ "$output" == *"TASK-ghost-capsule-01.md"* ]]
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
  [[ "$output" == *"[WARN] orphaned orchestration capsule: task-index missing row for TASK-capsule-no-index-01"* ]]
  [[ "$output" != *"orphaned orchestration capsule with no matching task file"* ]]
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
  [[ "$output" != *"orphaned orchestration capsule"* ]]
}

@test "validate_docs strict fails when docs/plan/_archive exists" {
  mkdir -p "$DOCS_ROOT/plan/_archive"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"physical archive directory violates the no-archive policy"* ]]
  [[ "$output" == *"docs/plan/_archive"* ]]
}

@test "validate_docs advisory warns when docs/task/_archive exists" {
  mkdir -p "$DOCS_ROOT/task/_archive"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] physical archive directory violates the no-archive policy"* ]]
  [[ "$output" == *"docs/task/_archive"* ]]
}

@test "validate_docs strict fails when docs/orchestration/_archive exists" {
  mkdir -p "$DOCS_ROOT/orchestration/_archive"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"physical archive directory violates the no-archive policy"* ]]
  [[ "$output" == *"docs/orchestration/_archive"* ]]
}

@test "validate_docs advisory does not warn about archive directories when none exist" {
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"violates the no-archive policy"* ]]
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
  [[ "$output" == *"[WARN] docs reference a gitignored tmp/ path (${DOCS_ROOT}/task/TASK-tmp-ref-fixture-01.md:"* ]]
  [[ "$output" == *"[WARN] docs reference a gitignored tmp/ path (${DOCS_ROOT}/plan/PLAN-tmp-ref-fixture-01-v1.0.md:"* ]]
  [[ "$output" == *"[WARN] docs reference a gitignored tmp/ path (${DOCS_ROOT}/orchestration/tmp-ref-fixture-01/INDEX.md:"* ]]
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
  [[ "$output" != *"gitignored tmp/ path"* ]]
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
  [[ "$output" != *"gitignored tmp/ path"* ]]
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
  [[ "$output" == *"empty"* ]] || [[ "$output" == *"FAIL"* ]]
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
  [[ "$output" == *"confirmed record requires evidence_type"* ]]
  [[ "$output" == *"shadow effect_map"* ]]

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
  [[ "$output" == *"deterministic_code record requires evidence_rule_id"* ]]
  [[ "$output" == *"deterministic_code record requires evidence_probe_result_hash"* ]]

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
  [[ "$output" == *"evidence_rule_id is not compatible with effect_type"* ]]
  [[ "$output" == *"anchor_file must match evidence ref path"* ]]
  [[ "$output" == *"probe artifact must exist"* ]]
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
  [[ "$output" == *"deterministic_runtime record requires evidence_artifact_media_type"* ]]
  [[ "$output" == *"deterministic_runtime record requires evidence_ignored_nondeterministic_fields"* ]]
  [[ "$output" == *"deterministic_runtime record requires evidence_scenario_scope"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence_scenario_scope must match"* ]]
  [[ "$output" == *"deterministic_runtime evidence_setter_symbol_path must match"* ]]
  [[ "$output" == *"deterministic_runtime evidence_setter_module_hash must be sha256"* ]]
  [[ "$output" == *"deterministic_runtime evidence_expiry_or_invalidation_rule must be timestamp, binding_change, or manual_revocation"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence_selected_fields must not contain duplicate field names"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence_selected_fields supports only top-level field names"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence envelope is not supported by the v1 validity matrix"* ]]

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
  [[ "$output" == *"evidence_canonical_output_type is only valid for custom-declared canonicalization"* ]]

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
  [[ "$output" == *"evidence_ignored_nondeterministic_fields must be [] for whole_artifact unless canonicalization is custom-declared"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence_artifact_hash must match scoped trace artifact"* ]]
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
  [[ "$output" == *"shadow effect_map records valid"* ]]
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
  [[ "$output" == *"ttl_days"* ]]
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
  [[ "$output" == *"shadow review_queue source refs are bounded"* ]]
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
  [[ "$output" == *"shadow rule registry missing rules block"* ]] || [[ "$output" == *"must contain at least one rule id mapping"* ]]
}

@test "validate_docs strict fails on invalid policy fallback risk enum" {
  sed -i.bak 's/max_promotion_risk: medium/max_promotion_risk: extreme/' "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  rm -f "$DOCS_ROOT/policy/shadow-regex-patterns.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"max_promotion_risk must be low|medium"* ]]
}

@test "validate_docs strict fails when policy promotion gate contract drifts" {
  sed -i.bak 's/forbidden_field: validator_result/forbidden_field: claim_result/' "$DOCS_ROOT/policy/shadow-rule-registry.md"
  rm -f "$DOCS_ROOT/policy/shadow-rule-registry.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"regex_only.forbidden_field must be validator_result"* ]]
}

@test "validate_docs strict fails when promotion gate token appears only outside scoped block" {
  sed -i.bak 's/max_effective_risk: medium/max_effective_risk: high/' "$DOCS_ROOT/policy/shadow-rule-registry.md"
  rm -f "$DOCS_ROOT/policy/shadow-rule-registry.md.bak"
  cat >> "$DOCS_ROOT/policy/shadow-rule-registry.md" <<'EOF'

<!-- misleading example: max_effective_risk: medium -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"regex_only.max_effective_risk must be medium"* ]]
}

@test "validate_docs strict fails when fallback mapping lacks its own cap" {
  perl -0pi -e 's/\n          fallback_max_risk: medium//' "$DOCS_ROOT/policy/shadow-rule-registry.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"fallback mapping missing fallback_max_risk"* ]]
}

@test "validate_docs strict fails when validator evidence type mismatches rule evidence branch" {
  perl -0pi -e 's/primary: jpa\.repository\.save\@v1/primary: any.runtime.trace\@v1/' "$DOCS_ROOT/policy/shadow-rule-registry.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"primary validator evidence_type mismatch"* ]]
}

@test "validate_docs strict fails when policy roots leave fenced yaml blocks" {
  perl -0pi -e 's/```yaml\nvalidators:/```text\nvalidators:/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"must define validators inside a fenced yaml block"* ]]
}

@test "validate_docs strict fails when validator catalog probe coverage metadata is missing" {
  perl -0pi -e 's/\n  source_probe_only:.*//' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"must declare source_probe_only"* ]]
}

@test "validate_docs strict fails when catalog coverage id is undeclared" {
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, py.missing_validator\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"implemented_primary_v1 id must be declared in validators block"* ]]
}

@test "validate_docs strict fails when catalog claims unimplemented probe primary" {
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, sql.write_call\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"implemented_primary_v1 id must be implemented by shadow_evidence_probe.py"* ]]
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
  [[ "$output" == *"implemented_primary_v1 id must be declared in validators block"* ]]
}

@test "validate_docs strict fails when adapter metadata drifts from catalog" {
  perl -0pi -e 's/(py\.ast\.call_match\@v1:\n\s+)evidence_type: code_call/${1}evidence_type: runtime_trace/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"evidence_type must match AdapterRegistry"* ]]
}

@test "validate_docs strict fails when fallback regex evidence type mismatches rule evidence branch" {
  perl -0pi -e 's/target: code_call/target: annotation/' "$DOCS_ROOT/policy/shadow-regex-patterns.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"fallback regex evidence_type mismatch"* ]]
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
  [[ "$output" == *"[WARN] orchestration execution_mode=supervisor_subagents requires at least one non-empty agent field (planner_agents/reviewer_agents/implementation_agents/validation_agents) for TASK-orch-contradiction-01"* ]]
  [[ "$output" == *"[WARN] orchestration execution_mode=supervisor_subagents requires a non-empty delegation_status for TASK-orch-contradiction-01"* ]]
}

@test "validate_docs advisory warns when an ingested ORCH capsule lacks required_review_routes or external_review_result_ref" {
  write_await_gate_fixture "orch-ingested-contradiction-01" "planned" "" "" "ingested" "" "" "" ""

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] orchestration external_review_status=ingested requires a non-empty required_review_routes for TASK-orch-ingested-contradiction-01"* ]]
  [[ "$output" == *"[WARN] orchestration external_review_status=ingested requires a non-empty external_review_result_ref for TASK-orch-ingested-contradiction-01"* ]]
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
  [[ "$output" != *"execution_mode=supervisor_subagents requires"* ]]
  [[ "$output" != *"external_review_status=ingested requires"* ]]
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
  [[ "$output" != *"execution_mode=supervisor_subagents requires"* ]]
  [[ "$output" != *"external_review_status=ingested requires"* ]]
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
  [[ "$output" == *"planner_agents"* ]] || [[ "$output" == *"implementation_agents"* ]] || [[ "$output" == *"validation_agents"* ]]
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
  [[ "$output" == *"orchestration risk preflight must be pass or approved"* ]]
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
  [[ "$output" == *"risk_preflight_status=approved requires approval_required=true"* ]]
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
  [[ "$output" == *"missing evaluator report for active task TASK-report-strict-01"* ]]
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
  [[ "$output" == *"[FAIL] shadow graph is empty"* ]]
  [[ "$output" == *"shadow_coverage_report.py"* ]]
}

@test "validate_docs advisory warns (does not fail) on an entirely empty shadow graph" {
  local source_repo="$TEST_WORKSPACE/gate-source-advisory"
  make_empty_graph_gate_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] shadow graph is empty"* ]]
}

@test "validate_docs shadow empty-graph gate never fires without a reachable source repo" {
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [[ "$output" != *"shadow graph is empty"* ]]
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
  [[ "$output" != *"shadow graph is empty"* ]]
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
  [[ "$output" != *"shadow graph is empty"* ]]
}

@test "validate_docs strict fails when required shadow bucket index is missing" {
  rm -f "$DOCS_ROOT/shadow/apps/_index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"shadow bucket index (apps) is missing"* ]]
}

@test "validate_docs strict fails when tracked shadow last_updated is blank or future" {
  sed -i.bak 's/^- last_updated:.*$/- last_updated:/' "$DOCS_ROOT/shadow/project-shadow.md"
  rm -f "$DOCS_ROOT/shadow/project-shadow.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"last_updated is present but empty in shadow router"* ]]

  "$INIT_SCAFFOLD" "$TEST_PROJECT"
  sed -i.bak 's/^- last_updated:.*$/- last_updated: 2999-01-01T00:00:00Z/' "$DOCS_ROOT/shadow/project-shadow.md"
  rm -f "$DOCS_ROOT/shadow/project-shadow.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"last_updated must not be in the future in shadow router"* ]]
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
  [[ "$output" == *"missing plan file for active task TASK-301"* ]]
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
  [[ "$output" == *"invalid evaluator report file name format"* ]] || [[ "$output" == *"invalid evaluator in PLAN-qa-01-v1.0-review-gpt-r01.md"* ]]
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
  [[ "$output" == *"invalid task.risk_level value"* ]]
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
  [[ "$output" == *"invalid decision.risk_level value"* ]]
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
  [[ "$output" == *"risk_level is recommended for active task TASK-risk-missing-01"* ]]
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
  [[ "$output" == *"requested_changes is present but empty in evaluator report"* ]]
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
  [[ "$output" == *"missing evaluator report for active task TASK-latest-report-01 latest plan v1.1"* ]]
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
  [[ "$output" == *"missing fresh evaluator report for active task TASK-stale-report-01 latest plan v1.0"* ]]
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
  [[ "$output" == *"evaluator report identity mismatch"* ]] || [[ "$output" == *"task_id mismatch between file name and field"* ]]
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
  [[ "$output" == *"missing adversarial evaluator report for high-risk task TASK-highrisk-01"* ]]
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
  [[ "$output" == *"decision-linkedrisk-dec-01.md risk_level=critical"* ]]
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
  [[ "$output" == *"counterproposal"* ]] || [[ "$output" == *"rebuttal"* ]] || [[ "$output" == *"residual_risk"* ]]
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
  [[ "$output" == *"Option --mode requires a value"* ]]
}

@test "validate_docs fails clearly when numeric option is invalid" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "num-01" \
    --task-title "Numeric validation test" \
    --no-init

  run "$VALIDATE" "$TEST_PROJECT" --max-task-lines notanumber
  [ "$status" -ne 0 ]
  [[ "$output" == *"--max-task-lines must be a positive integer"* ]]
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
  [[ "$output" == *"invalid task.status value"* ]]
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
  [[ "$output" == *"invalid decision.scope_type value"* ]]
  [[ "$output" == *"invalid decision.status value"* ]]
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
  [[ "$output" == *"potential secret values detected"* ]] || [[ "$output" == *"OPENAI API key assignment"* ]]
  [[ "$output" == *"[REDACTED_SECRET]"* ]]
  [[ "$output" != *"sk-proj-12345678901234567890"* ]]
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
  [[ "$output" == *"potential secret values detected"* ]] || [[ "$output" == *"yaml/env-style secret assignments"* ]]
  [[ "$output" == *"[REDACTED_SECRET]"* ]]
  [[ "$output" != *"$google_key"* ]]
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
  [[ "$output" == *"ripgrep (rg) is required for secret scanning"* ]]
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
  [[ "$output" == *"legacy shadow shim"* ]] || [[ "$output" == *"redirect_shim"* ]]
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
  [[ "$output" == *"decision index missing row for decision-dot.a.md"* ]]
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
  [[ "$output" == *"task-index row for TASK-idx-stale-01 has no matching task file"* ]]
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
  [[ "$output" == *"task-index section mismatch for TASK-idx-mismatch-01: task file status is done but row is listed under Planned"* ]]
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
  [[ "$output" == *"task-index has duplicate rows for TASK-idx-dup-01"* ]]
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
  [[ "$output" == *"is status: resolved but still lives in docs/issues/current/"* ]]
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
  [[ "$output" == *"docs/issues/current/README.md missing index row for ISSUE-20260101-no-row.md"* ]]
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
  [[ "$output" == *"resolved issue ISSUE-20260101-missing-resolution.md has no paired resolution doc"* ]]
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
  [[ "$output" == *"resolution doc RESOLUTION-20260101-orphan.md has no paired issue file"* ]]
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
  [[ "$output" != *"task-index section mismatch"* ]]
}

@test "validate_docs advisory continues past a missing orchestration field instead of aborting" {
  write_await_gate_fixture "orch-abort-01" "in_progress" "implementation_start" "PLAN-orch-abort-01-v1.0" "not_requested" "" "" "" ""

  sed -i.bak '/^- primary_author_tool:/d' "$DOCS_ROOT/orchestration/orch-abort-01/ORCH.md"
  rm -f "$DOCS_ROOT/orchestration/orch-abort-01/ORCH.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[RESULT]"* ]]
  [[ "$output" == *"primary_author_tool is missing"* ]]
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
  [[ "$output" == *"owner is recommended for in_progress task TASK-claim-owner-01"* ]]
  [[ "$output" != *"claimed_at is recommended for in_progress task"* ]]
  [[ "$output" != *"claim directory is recommended for in_progress task"* ]]
}

@test "validate_docs advisory warns when an in_progress task is missing claimed_at" {
  write_await_gate_fixture "claim-time-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  mkdir -p "$DOCS_ROOT/task/.claims/claim-time-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"claimed_at is recommended for in_progress task TASK-claim-time-01"* ]]
  [[ "$output" != *"owner is recommended for in_progress task"* ]]
  [[ "$output" != *"claim directory is recommended for in_progress task"* ]]
}

@test "validate_docs advisory warns when an in_progress task has no claim directory" {
  write_await_gate_fixture "claim-dir-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-claim-dir-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"claim directory is recommended for in_progress task TASK-claim-dir-01: mkdir"* ]]
  [[ "$output" == *"docs/task/.claims/claim-dir-01/"* ]]
  [[ "$output" != *"owner is recommended for in_progress task"* ]]
  [[ "$output" != *"claimed_at is recommended for in_progress task"* ]]
}

@test "validate_docs advisory does not warn when the claim contract is fully satisfied" {
  write_await_gate_fixture "claim-ok-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-claim-ok-01.md"
  mkdir -p "$DOCS_ROOT/task/.claims/claim-ok-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"owner is recommended for in_progress task"* ]]
  [[ "$output" != *"claimed_at is recommended for in_progress task"* ]]
  [[ "$output" != *"claim directory is recommended for in_progress task"* ]]
}

@test "validate_docs strict fails on a stale claim directory whose task already left in_progress" {
  write_await_gate_fixture "claim-stale-01" "done" "not_requested" "" "not_requested" "" "" "" ""
  mkdir -p "$DOCS_ROOT/task/.claims/claim-stale-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"stale claim directory for TASK-claim-stale-01 (status=done): remove"* ]]
}

@test "validate_docs strict fails on an orphaned claim directory with no matching task file" {
  mkdir -p "$DOCS_ROOT/task/.claims/claim-ghost-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"orphaned claim directory with no matching task file"* ]]
  [[ "$output" == *"docs/task/.claims/claim-ghost-01"* ]]
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
  [[ "$output" == *"resume capsule missing for in_progress task TASK-resume-missing-01"* ]]
  [[ "$output" == *"doc_garden.sh --task-id resume-missing-01 --resume-checkpoint"* ]]
}

@test "validate_docs advisory does not nudge adoption once any resume_* field is present" {
  write_await_gate_fixture "resume-present-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-resume-present-01.md"
  mkdir -p "$DOCS_ROOT/task/.claims/resume-present-01"
  printf '%s\n' "- resume_checkpointed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-resume-present-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"resume capsule missing for in_progress task"* ]]
}

@test "validate_docs strict does not fail an in_progress task with no resume_* fields at all" {
  write_strict_clean_resume_fixture "resume-absent-strict-01"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  [[ "$output" != *"resume_next_action is present but empty"* ]]
  [[ "$output" != *"resume_last_verified is present but empty"* ]]
}

@test "validate_docs strict fails when resume_next_action is present but empty" {
  write_await_gate_fixture "resume-empty-next-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- resume_next_action:" >> "$DOCS_ROOT/task/TASK-resume-empty-next-01.md"
  printf '%s\n' "- resume_last_verified: bats suite green" >> "$DOCS_ROOT/task/TASK-resume-empty-next-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"resume_next_action is present but empty for in_progress task TASK-resume-empty-next-01"* ]]
  [[ "$output" != *"resume_last_verified is present but empty"* ]]
}

@test "validate_docs strict fails when resume_last_verified is present but empty" {
  write_await_gate_fixture "resume-empty-verified-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- resume_next_action: run the bats suite" >> "$DOCS_ROOT/task/TASK-resume-empty-verified-01.md"
  printf '%s\n' "- resume_last_verified:" >> "$DOCS_ROOT/task/TASK-resume-empty-verified-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"resume_last_verified is present but empty for in_progress task TASK-resume-empty-verified-01"* ]]
  [[ "$output" != *"resume_next_action is present but empty"* ]]
}

@test "validate_docs strict passes when resume_next_action and resume_last_verified are both truthfully filled" {
  write_strict_clean_resume_fixture "resume-filled-01"
  printf '%s\n' "- resume_next_action: run the bats suite" >> "$DOCS_ROOT/task/TASK-resume-filled-01.md"
  printf '%s\n' "- resume_last_verified: bats suite green" >> "$DOCS_ROOT/task/TASK-resume-filled-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  [[ "$output" != *"resume_next_action is present but empty"* ]]
  [[ "$output" != *"resume_last_verified is present but empty"* ]]
}

@test "validate_docs strict does not fail when resume_state_revision is present but non-numeric" {
  write_strict_clean_resume_fixture "resume-revision-strict-01"
  printf '%s\n' "- resume_next_action: run the bats suite" >> "$DOCS_ROOT/task/TASK-resume-revision-strict-01.md"
  printf '%s\n' "- resume_last_verified: bats suite green" >> "$DOCS_ROOT/task/TASK-resume-revision-strict-01.md"
  printf '%s\n' "- resume_state_revision: corrupted" >> "$DOCS_ROOT/task/TASK-resume-revision-strict-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] resume_state_revision is present but non-numeric for in_progress task TASK-resume-revision-strict-01"* ]]
}

@test "validate_docs advisory warns when resume_state_revision is present but non-numeric" {
  write_await_gate_fixture "resume-revision-advisory-01" "in_progress" "not_requested" "" "not_requested" "" "" "" ""
  printf '%s\n' "- claimed_at: 2026-01-01T00:00:00Z" >> "$DOCS_ROOT/task/TASK-resume-revision-advisory-01.md"
  mkdir -p "$DOCS_ROOT/task/.claims/resume-revision-advisory-01"
  printf '%s\n' "- resume_state_revision: not-a-number" >> "$DOCS_ROOT/task/TASK-resume-revision-advisory-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] resume_state_revision is present but non-numeric for in_progress task TASK-resume-revision-advisory-01"* ]]
}

@test "validate_docs does not warn about resume_state_revision when it is a valid integer" {
  write_strict_clean_resume_fixture "resume-revision-ok-01"
  printf '%s\n' "- resume_next_action: run the bats suite" >> "$DOCS_ROOT/task/TASK-resume-revision-ok-01.md"
  printf '%s\n' "- resume_last_verified: bats suite green" >> "$DOCS_ROOT/task/TASK-resume-revision-ok-01.md"
  printf '%s\n' "- resume_state_revision: 3" >> "$DOCS_ROOT/task/TASK-resume-revision-ok-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  [[ "$output" != *"resume_state_revision is present but non-numeric"* ]]
}

@test "validate_docs advisory warns when a bucket index overview_doc reference does not resolve" {
  cat >> "$DOCS_ROOT/shadow/apps/_index.md" <<'EOF'
- unit_id: app-a
  - overview_doc: apps/app-a/overview.md
  - secondary_tags: web
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadow navigation reference does not resolve"* ]]
  [[ "$output" == *"overview_doc -> apps/app-a/overview.md"* ]]
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
  [[ "$output" == *"shadow navigation reference does not resolve"* ]]
  [[ "$output" == *"canonical_path -> docs/shadow/apps/app-a/overview.md"* ]]
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
  [[ "$output" == *"shadow navigation reference does not resolve"* ]]
  [[ "$output" == *"next_docs -> apps/app-a/auth.md"* ]]
  # source_of_truth code paths are not .md and must not be flagged by this check
  [[ "$output" != *"src/app_a/auth.py"* ]]
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
  [[ "$output" == *"shadow navigation references resolve to real files"* ]]
  [[ "$output" != *"shadow navigation reference does not resolve"* ]]
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
  [[ "$output" != *"shadow navigation reference does not resolve"* ]]
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
  [[ "$output" != *"shadow navigation reference does not resolve"* ]]
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
  [[ "$output" != *"never-created.md"* ]]
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
  [[ "$output" == *"shadow navigation reference does not resolve"* ]]
  [[ "$output" == *"next_docs -> apps/app-a/missing-leaf.md"* ]]
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
  [[ "$output" == *"shadow navigation reference does not resolve"* ]]
  [[ "$output" == *"next_docs -> apps/app-a/api.md"* ]]
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
  [[ "$output" == *"shadow source-of-truth digests verified against current source"* ]]
  [[ "$output" != *"digest drift"* ]]
}

@test "validate_docs advisory warns on source-of-truth digest drift when source content changes" {
  _seed_source_digest_overview
  printf 'def login():\n    return False  # changed\n' > "$TEST_PROJECT/src/auth.py"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadow source-of-truth digest drift"* ]]
  [[ "$output" == *"apps/app-a/overview.md"* ]]
}

@test "validate_docs advisory warns when a declared source-of-truth path is deleted" {
  _seed_source_digest_overview
  rm "$TEST_PROJECT/src/auth.py"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadow source-of-truth declared path does not exist: src/auth.py"* ]]
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
  [[ "$output" != *"digest drift"* ]]
  [[ "$output" != *"source-of-truth digests verified"* ]]
}

@test "validate_docs strict skips the advisory source-of-truth digest check" {
  _seed_source_digest_overview
  printf 'def login():\n    return False\n' > "$TEST_PROJECT/src/auth.py"
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [[ "$output" != *"digest drift"* ]]
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
  [[ "$output" == *"shadow source-of-truth digest drift"* ]]
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
  [[ "$output" == *"status: ok"* ]]
  [[ "$output" != *"no_paths"* ]]
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
  [[ "$output" == *"escapes the project root: ../outside.txt"* ]]
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
  [[ "$output" == "0" ]]
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
  [[ "$output" == *"shadow source_of_truth path does not exist: src/gone.py"* ]]
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
  [[ "$output" == *"shadow source_of_truth path escapes the project root: ../outside.txt"* ]]
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
  [[ "$output" == *"shadow source_of_truth_paths all resolve to real in-project files"* ]]
  [[ "$output" != *"source_of_truth path does not exist"* ]]
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
  [[ "$output" == *"shadow source-of-truth declared path does not exist: src/auth.py"* ]]
  [[ "$output" != *"shadow source_of_truth path does not exist: src/auth.py"* ]]
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
  [[ "$output" == *"shadow source_of_truth path does not exist: src/gone.py"* ]]
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
  [[ "$output" == *"shadow source_of_truth path does not exist: src/gone.py"* ]]
}

@test "validate_docs does not abort the whole run on a malformed (NUL-byte) source path" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# Shadow Unit Overview\n- doc_role: unit_overview\n- source_of_truth_paths: src/a\000b.py\n- last_updated: 2026-01-01T00:00:00Z\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  # The malformed path must be handled (missing), and the script must run to the end
  # (the final [RESULT] line proves it did not abort mid-run under set -e).
  [ "$status" -eq 0 ]
  [[ "$output" == *"[RESULT]"* ]]
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
  [[ "$output" == *"shadow unit/concern docs have valid schema"* ]]
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
  [[ "$output" == *"shadow unit overview missing home_bucket"* ]]
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
  [[ "$output" == *"home_bucket is not a known bucket (widgets)"* ]]
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
  [[ "$output" == *"shadow concern leaf missing concern_id"* ]]
}

@test "validate_docs strict skips the advisory unit schema check" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  cat > "$DOCS_ROOT/shadow/apps/app-a/overview.md" <<'EOF'
# Shadow Unit Overview

- doc_role: unit_overview
- last_updated: 2026-01-01T00:00:00Z
EOF
  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [[ "$output" != *"shadow unit overview missing home_bucket"* ]]
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
  [[ "$output" != *"shadow unit overview missing"* ]]
  [[ "$output" != *"shadow unit/concern docs have valid schema"* ]]
}

@test "validate_docs advisory surfaces an indented unit overview instead of skipping it" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# Shadow Unit Overview\n  - doc_role: unit_overview\n  - last_updated: 2026-01-01T00:00:00Z\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/overview.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadow unit overview missing home_bucket"* ]]
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
  [[ "$output" == *"shadow unit/concern docs have valid schema"* ]]
}

@test "validate_docs advisory takes the first non-empty concern_id, ignoring an empty stub" {
  mkdir -p "$DOCS_ROOT/shadow/apps/app-a"
  printf '# Shadow Concern\n- doc_role: concern_leaf\n- concern_id:\n- concern_id: auth-flow-01\n' \
    > "$DOCS_ROOT/shadow/apps/app-a/auth.md"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"shadow concern leaf missing concern_id"* ]]
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
  [[ "$output" == *"delegation_status 'active' contradicts task status done"* ]]

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [[ "$output" != *"contradicts task status done"* ]]
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
  [[ "$output" == *"orchestration.delegation_status"* ]]
  [[ "$output" == *"totally_bogus_value"* ]]
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
  [[ "$output" == *"reference a deleted _archive path"* ]]
  [[ "$output" == *"PLAN-archive-ref-01-v1.0.md"* ]]
}

@test "empty-graph gate ignores scaffold-only docs projects (routers are not source)" {
  local parent="$TEST_WORKSPACE/docs-only"
  mkdir -p "$parent"
  "$INIT_SCAFFOLD" "$parent" >/dev/null
  git -C "$parent" init --quiet
  git -C "$parent" add -A
  git -C "$parent" -c user.email=t@t -c user.name=t commit -qm init

  run "$VALIDATE" "$parent" --mode strict
  [[ "$output" != *"shadow graph is empty"* ]]

  printf 'x=1\n' > "$parent/src.py"
  git -C "$parent" add -A
  git -C "$parent" -c user.email=t@t -c user.name=t commit -qm code

  run "$VALIDATE" "$parent" --mode strict
  [[ "$output" == *"shadow graph is empty"* ]]
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
  [[ "$output" == *"shadow graph is empty"* ]]

  python3 - "$parent/docs/shadow/apps/_index.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("- x", "- billing-service:\n  - overview_doc: apps/billing-service/overview.md"))
PY

  run "$VALIDATE" "$parent" --mode advisory
  [[ "$output" != *"shadow graph is empty"* ]]
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
  [[ "$output" == *"execution_mode=solo contradicts non-empty delegated agent fields"* ]]
}
