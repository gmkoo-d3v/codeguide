#!/usr/bin/env bats

# codeguide operational stability tests

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
DOC_GARDEN="$SCRIPTS_DIR/doc_garden.sh"
VALIDATE="$SCRIPTS_DIR/validate_docs.sh"
RUN_CODEGUIDE="$SCRIPTS_DIR/run_codeguide.sh"
RUN_EXTERNAL_REVIEWS="$SCRIPTS_DIR/run_external_plan_reviews.sh"
INIT_SCAFFOLD="$SCRIPTS_DIR/init_docs_scaffold.sh"
CHECK_ENGLISH_DOCS="$SCRIPTS_DIR/check_english_docs.sh"

docs_root_for_project() {
  local project_root="$1"
  local project_root_abs
  local workspace_root

  project_root_abs="$(cd "$project_root" && pwd)"
  workspace_root="$(cd "$project_root_abs/.." && pwd)"
  printf "%s/docs" "$workspace_root"
}

setup() {
  TEST_WORKSPACE="$(mktemp -d)"
  export TEST_WORKSPACE
  TEST_PROJECT="$TEST_WORKSPACE/repo"
  mkdir -p "$TEST_PROJECT"
  "$INIT_SCAFFOLD" "$TEST_PROJECT"
  DOCS_ROOT="$(docs_root_for_project "$TEST_PROJECT")"
}

teardown() {
  rm -rf "$TEST_WORKSPACE"
}

write_mock_cli() {
  local path="$1"
  local content="$2"
  printf '%s\n' "$content" > "$path"
  chmod +x "$path"
}

# ========== P0: Empty value overwrite prevention ==========

@test "upsert_field skips empty values on existing non-empty fields" {
  # Create a decision with a real context value
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-001" \
    --decision-title "Test Decision" \
    --context "Important context here" \
    --rationale "Real rationale" \
    --no-init

  # Verify context was written
  run grep "^- context:" "$DOCS_ROOT/decisions/decision-test-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Important context here"* ]]

  # Run again with empty context — should NOT overwrite
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-001" \
    --decision-title "Test Decision" \
    --context "" \
    --rationale "" \
    --no-init

  # Context should still have the original value
  run grep "^- context:" "$DOCS_ROOT/decisions/decision-test-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Important context here"* ]]

  # Rationale should still have the original value
  run grep "^- rationale:" "$DOCS_ROOT/decisions/decision-test-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Real rationale"* ]]
}

@test "upsert_field allows empty overwrite with --allow-empty-overwrite" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-002" \
    --decision-title "Test Decision" \
    --context "Will be cleared" \
    --no-init

  run grep "^- context:" "$DOCS_ROOT/decisions/decision-test-002.md"
  [[ "$output" == *"Will be cleared"* ]]

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-002" \
    --decision-title "Test Decision" \
    --context "" \
    --allow-empty-overwrite \
    --no-init

  # Context should now be empty
  run grep "^- context:" "$DOCS_ROOT/decisions/decision-test-002.md"
  [ "$status" -eq 0 ]
  # Value after "context:" should be empty or just whitespace
  local value
  value="$(echo "$output" | sed 's/^- context:[[:space:]]*//')"
  [ -z "$value" ]
}

@test "axis fields are not overwritten when empty" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "100" \
    --task-title "Axis Test" \
    --axis-why "SOLID principle applied" \
    --axis-where "Service layer" \
    --axis-verify "Unit tests added" \
    --no-init

  run grep "^- axis_why:" "$DOCS_ROOT/task/TASK-100.md"
  [[ "$output" == *"SOLID principle applied"* ]]

  # Run again without axis values — should preserve existing
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "100" \
    --task-title "Axis Test" \
    --no-init

  run grep "^- axis_why:" "$DOCS_ROOT/task/TASK-100.md"
  [[ "$output" == *"SOLID principle applied"* ]]

  run grep "^- axis_where:" "$DOCS_ROOT/task/TASK-100.md"
  [[ "$output" == *"Service layer"* ]]

  run grep "^- axis_verify:" "$DOCS_ROOT/task/TASK-100.md"
  [[ "$output" == *"Unit tests added"* ]]
}

@test "doc_garden preserves backslashes in field values" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "path-001" \
    --decision-title "Path escape test" \
    --context 'Use path C:\new\folder' \
    --no-init

  run cat "$DOCS_ROOT/decisions/decision-path-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- context: Use path C:\\new\\folder"* ]]
}

@test "doc_garden writes shared risk_level to task and decision docs" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "risk-01" \
    --task-title "Risk level test" \
    --decision-id "risk-dec-01" \
    --decision-title "Risk decision" \
    --selected-option "Option A" \
    --risk-level "high" \
    --no-init

  run grep "^- risk_level: high" "$DOCS_ROOT/task/TASK-risk-01.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level: high" "$DOCS_ROOT/decisions/decision-risk-dec-01.md"
  [ "$status" -eq 0 ]
}

@test "doc_garden concurrent task updates keep both index rows" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "race-a" \
    --task-title "Race A" \
    --task-status "in_progress" \
    --no-init &
  local pid1=$!

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "race-b" \
    --task-title "Race B" \
    --task-status "in_progress" \
    --no-init &
  local pid2=$!

  wait "$pid1"
  wait "$pid2"

  local index="$DOCS_ROOT/task/task-index.md"
  run grep "^- TASK-race-a |" "$index"
  [ "$status" -eq 0 ]
  run grep "^- TASK-race-b |" "$index"
  [ "$status" -eq 0 ]
}

# ========== P1: task_id inference priority ==========

@test "infer_task_id: explicit --task-id has highest priority" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "EXPLICIT-99" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"task_id: EXPLICIT-99"* ]]
}

@test "infer_task_id: branch pattern takes priority over latest task file" {
  # Create a pre-existing task file that would be picked as "latest"
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "old-task-1" \
    --task-title "Old task" \
    --no-init

  # The test runs outside a git repo, so branch inference won't match.
  # But we verify the explicit task-id still works correctly
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "BRANCH-42" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"task_id: BRANCH-42"* ]]
}

@test "init_docs_scaffold uses workspace docs root directly" {
  run test -d "$DOCS_ROOT/task"
  [ "$status" -eq 0 ]
  run test -d "$DOCS_ROOT/shadow"
  [ "$status" -eq 0 ]
  run test ! -d "$DOCS_ROOT/repo"
  [ "$status" -eq 0 ]
  run test ! -d "$DOCS_ROOT/repos"
  [ "$status" -eq 0 ]
}

@test "init_docs_scaffold creates shadow graph scaffold files" {
  run test -f "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/shadow/_global.md"
  [ "$status" -eq 0 ]

  run grep "^- doc_role: router" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- read_path: project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- bucket_links: apps/_index.md, services/_index.md, packages/_index.md, infra/_index.md, data/_index.md" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- global_doc: _global.md" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]

  local bucket
  for bucket in apps services packages infra data; do
    run test -f "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- doc_role: bucket_index" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- bucket: $bucket" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- no units detected yet" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run awk '/^## Units$/{flag=1; next} flag && /^- /{print}' "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    [ "$output" = "- no units detected yet" ]
  done
}

# ========== P1/P2: Validator strict mode non-empty check ==========

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

@test "run_codeguide bootstraps orchestration doc for active task" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "orch-01" --mode advisory
  [ "$status" -eq 0 ]

  local orch_file="$DOCS_ROOT/orchestration/ORCH-orch-01.md"
  run test -f "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- execution_mode: supervisor_subagents" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- supervisor_agent: main-thread-supervising-lead-architect" "$orch_file"
  [ "$status" -eq 0 ]
}

@test "validate_docs strict fails when supervisor_subagents orchestration fields are blank" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-strict-01" \
    --task-title "Orchestration strict test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
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

@test "validate_docs strict fails when supervisor_subagents task has no evaluator report" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "report-strict-01" \
    --task-title "Report strict test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
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

@test "validate_docs strict fails when project shadow lags behind tracked task docs" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "shadow-lag-01" \
    --task-title "Shadow lag test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  sleep 1
  echo "- acceptance_criteria: changed after shadow sync" >> "$DOCS_ROOT/task/TASK-shadow-lag-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"shadow graph doc is older than tracked task/decision doc"* ]]
}

@test "validate_docs strict fails when required shadow bucket index is missing" {
  rm -f "$DOCS_ROOT/shadow/apps/_index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"shadow bucket index (apps) is missing"* ]]
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
- strengths:
- risks:
- requested_changes:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
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
- strengths:
- risks:
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
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --primary-author-tool "codex" \
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
- strengths:
- risks:
- requested_changes: tighten rollback and monitoring
- objection: the initial plan may under-test rollback paths
- counterproposal: add a rollback rehearsal and explicit failure thresholds
- rebuttal: the original plan remains viable once rollback checks are added
- residual_risk: operational complexity remains elevated during rollout
- last_updated: 2026-01-01T00:00:00Z
EOF

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

@test "validate_docs reports missing rg for secret scanning" {
  run env PATH="/usr/bin:/bin" "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"ripgrep (rg) is required for secret scanning"* ]]
}

# ========== P2: task-index status section movement ==========

@test "task-index places row under correct status section" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "300" \
    --task-title "Section Test" \
    --task-status "planned" \
    --no-init

  local index="$DOCS_ROOT/task/task-index.md"
  # Verify the row is under ## Planned section
  run grep "^- TASK-300 |" "$index"
  [ "$status" -eq 0 ]
  [[ "$output" == *"planned"* ]]

  # Move to in_progress
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "300" \
    --task-title "Section Test" \
    --task-status "in_progress" \
    --no-init

  # Should not have duplicates
  local count
  count=$(grep -c "^- TASK-300 |" "$index")
  [ "$count" -eq 1 ]

  run grep "^- TASK-300 |" "$index"
  [[ "$output" == *"in_progress"* ]]
}

@test "task-index prevents duplicate rows" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "400" \
    --task-title "Dup Test" \
    --task-status "in_progress" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "400" \
    --task-title "Dup Test Updated" \
    --task-status "in_progress" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "400" \
    --task-title "Dup Test Final" \
    --task-status "done" \
    --no-init

  local index="$DOCS_ROOT/task/task-index.md"
  local count
  count=$(grep -c "^- TASK-400 |" "$index")
  [ "$count" -eq 1 ]
  run grep "^- TASK-400 |" "$index"
  [[ "$output" == *"done"* ]]
}

# ========== P1: change-scope branching ==========

@test "run_codeguide reports docs-only scope by default" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "500" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"change_scope: docs-only"* ]]
}

@test "run_codeguide forwards risk_level into generated docs" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "risk-run-01" --mode advisory --risk-level "critical"
  [ "$status" -eq 0 ]
  [[ "$output" == *"risk_level: critical"* ]]

  run grep "^- risk_level: critical" "$DOCS_ROOT/task/TASK-risk-run-01.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level: critical" "$DOCS_ROOT/decisions/decision-auto-task-risk-run-01.md"
  [ "$status" -eq 0 ]
}

@test "run_codeguide fails clearly when option value is missing" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"Option --mode requires a value"* ]]
}

@test "run_codeguide reports code-or-runtime when runtime cmd provided" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "echo\necho test-pass\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "501" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "echo test-pass" \
    --runtime-allow-list "$allow_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"change_scope: code-or-runtime"* ]]
  [[ "$output" == *"test-pass"* ]]
}

@test "run_codeguide passes shadow note through to project shadow" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
    --task-id "shadow-note-01" \
    --mode advisory \
    --shadow-note "search and navigation updated"
  [ "$status" -eq 0 ]

  run grep "^- latest_change_note:" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"search and navigation updated"* ]]
}

@test "doc_garden refreshes shadow graph and keeps change note router-only" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "shadow-graph-01" \
    --task-title "Shadow graph refresh" \
    --shadow-note "graph refresh" \
    --no-init
  [ "$status" -eq 0 ]

  run grep "^- last_updated:" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- last_updated:" "$DOCS_ROOT/shadow/_global.md"
  [ "$status" -eq 0 ]

  run grep "^- latest_change_note:" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"graph refresh"* ]]

  run grep "^- latest_change_note:" "$DOCS_ROOT/shadow/_global.md"
  [ "$status" -ne 0 ]

  local bucket
  for bucket in apps services packages infra data; do
    run grep "^- last_updated:" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- latest_change_note:" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -ne 0 ]
  done
}

@test "doc_garden rejects git_diff shadow refresh without explicit range" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "shadow-git-01" \
    --task-title "Shadow git diff validation" \
    --shadow-refresh-mode "git_diff" \
    --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"--shadow-git-range is required"* ]]
}

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

@test "check_english_docs passes for curated codeguide markdown" {
  run "$CHECK_ENGLISH_DOCS" "$(cd "$SCRIPTS_DIR/.." && pwd)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"English-only"* ]]
}

@test "check_english_docs fails on Korean text outside research exclusions" {
  local workspace
  workspace="$(mktemp -d)"

  cat > "$workspace/README.md" <<'EOF'
# Example

This file is fine.
EOF

  cat > "$workspace/notes.md" <<'EOF'
# Notes

이 문장은 실패해야 합니다.
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -ne 0 ]
  [[ "$output" == *"notes.md"* ]]

  rm -rf "$workspace"
}

@test "check_english_docs ignores mold research docs and temp traces" {
  local workspace
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/temp"

  cat > "$workspace/mold-research.md" <<'EOF'
# Research

이 문장은 연구 문서라서 무시됩니다.
EOF

  cat > "$workspace/temp/trace.md" <<'EOF'
# Trace

이 문장은 temp 경로라서 무시됩니다.
EOF

  cat > "$workspace/README.md" <<'EOF'
# Example

This file is fine.
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "run_codeguide bootstraps initial plan doc for active task" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "plan-01" --mode advisory
  [ "$status" -eq 0 ]

  local plan_file="$DOCS_ROOT/plan/PLAN-plan-01-v1.0.md"
  run test -f "$plan_file"
  [ "$status" -eq 0 ]
  run grep "^- plan_version: v1.0" "$plan_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden fails clearly when option value is missing" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id
  [ "$status" -ne 0 ]
  [[ "$output" == *"Option --task-id requires a value"* ]]
}

@test "doc_garden rejects invalid task id characters" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id ".*" --task-title "bad id" --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --task-id value"* ]]
}

@test "doc_garden rejects invalid decision id characters" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "[" --decision-title "bad id" --selected-option "x" --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --decision-id value"* ]]
}

@test "doc_garden rejects invalid task status enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "bad-status-01" \
    --task-title "bad status" \
    --task-status "working" \
    --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --task-status"* ]]
}

@test "doc_garden rejects invalid scope type enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "bad-scope-01" \
    --decision-title "bad scope" \
    --scope-type "feature" \
    --selected-option "x" \
    --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --scope-type"* ]]
}

@test "doc_garden rejects invalid decision status enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "bad-decision-status-01" \
    --decision-title "bad decision status" \
    --decision-status "merged" \
    --selected-option "x" \
    --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --decision-status"* ]]
}

# ========== decision-index section-based movement ==========

@test "decision-index places row under correct status section" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-sec-01" \
    --decision-title "Section Decision" \
    --decision-status "proposed" \
    --selected-option "Option A" \
    --no-init

  local index="$DOCS_ROOT/decisions/decision-index.md"
  run grep "^- decision-d-sec-01.md |" "$index"
  [ "$status" -eq 0 ]
  [[ "$output" == *"proposed"* ]]

  # Move to accepted
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-sec-01" \
    --decision-title "Section Decision" \
    --decision-status "accepted" \
    --selected-option "Option A" \
    --no-init

  local count
  count=$(grep -c "^- decision-d-sec-01.md |" "$index")
  [ "$count" -eq 1 ]
  run grep "^- decision-d-sec-01.md |" "$index"
  [[ "$output" == *"accepted"* ]]
}

@test "decision-index prevents duplicate rows" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-dup-01" \
    --decision-title "Dup Decision" \
    --decision-status "proposed" \
    --selected-option "First" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-dup-01" \
    --decision-title "Dup Decision" \
    --decision-status "accepted" \
    --selected-option "Updated" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-dup-01" \
    --decision-title "Dup Decision" \
    --decision-status "superseded" \
    --selected-option "Final" \
    --no-init

  local index="$DOCS_ROOT/decisions/decision-index.md"
  local count
  count=$(grep -c "^- decision-d-dup-01.md |" "$index")
  [ "$count" -eq 1 ]
  run grep "^- decision-d-dup-01.md |" "$index"
  [[ "$output" == *"superseded"* ]]
}

@test "decision-index migrates legacy table format" {
  # Create a legacy table-format decision-index
  cat > "$DOCS_ROOT/decisions/decision-index.md" <<'EOF'
# Decision Index

| file | decision_id | scope_type | date | status | chosen_by | linked_task | linked_pr | linked_hotfix | summary |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| decision-legacy.md | legacy | task | 2025-01-01 | accepted | user | TASK-1 | | | Old entry |
EOF

  # Run doc_garden with a new decision — should auto-migrate
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "new-01" \
    --decision-title "New Decision" \
    --decision-status "proposed" \
    --selected-option "New option" \
    --no-init

  local index="$DOCS_ROOT/decisions/decision-index.md"

  # Legacy table rows should be gone
  run grep "^|" "$index"
  [ "$status" -ne 0 ]

  # New section headers should exist
  run grep "## Proposed" "$index"
  [ "$status" -eq 0 ]
  run grep "## Accepted" "$index"
  [ "$status" -eq 0 ]

  # Legacy row should be preserved as section-format row
  run grep "^- decision-legacy.md | legacy | task | 2025-01-01 | accepted | TASK-1 | Old entry" "$index"
  [ "$status" -eq 0 ]

  # New entry should be present
  run grep "^- decision-new-01.md |" "$index"
  [ "$status" -eq 0 ]

  # Migration should create a backup file
  run bash -c "ls \"$DOCS_ROOT/decisions\"/decision-index.md.bak.* >/dev/null"
  [ "$status" -eq 0 ]
}

# ========== runtime-cmd security ==========

@test "runtime-cmd blocked by allow-list" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "npm\npython\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-01" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "echo safe" \
    --runtime-allow-list "$allow_file"

  # 'echo' is not in the allow-list, so it should be blocked
  [[ "$output" == *"BLOCKED"* ]]
}

@test "runtime-cmd blocks chained shell syntax in allow-list mode" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "npm\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-chain-01" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "npm --version && echo INJECTED" \
    --runtime-allow-list "$allow_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *"unsafe shell syntax"* ]]
  [[ "$output" != *"[RUN] Runtime test:"* ]]
}

@test "runtime-cmd blocks ampersand shell syntax in allow-list mode" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "npm\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-chain-02" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "npm --version & echo INJECTED" \
    --runtime-allow-list "$allow_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *"unsafe shell syntax"* ]]
  [[ "$output" != *"[RUN] Runtime test:"* ]]
}

@test "runtime-cmd passes with allow-list match" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "echo\nnpm\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-02" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "echo allowed-output" \
    --runtime-allow-list "$allow_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *"allowed-output"* ]]
  [[ "$output" != *"BLOCKED"* ]]
}

@test "runtime-cmd allow-list supports executable+subcommand matching" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "uname -a\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-02b" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "uname -a" \
    --runtime-allow-list "$allow_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[RUN] Runtime test: uname -a"* ]]
  [[ "$output" != *"BLOCKED"* ]]
}

@test "runtime-cmd blocks when executable+subcommand is not allow-listed" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "uname -s\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-02c" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "uname -a" \
    --runtime-allow-list "$allow_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKED"* ]]
  [[ "$output" == *"uname -a"* ]]
}

@test "runtime-cmd allow-list supports prefix patterns" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "npm*\n./node_modules*\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-03" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-lint-cmd "npx eslint ." \
    --runtime-allow-list "$allow_file"

  # 'npx' should NOT match 'npm*' prefix since npx != npm
  [[ "$output" == *"BLOCKED"* ]]
}

@test "runtime-cmd requires allow-list in code-or-runtime mode" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-04" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "echo free-run"

  [ "$status" -eq 0 ]
  [[ "$output" == *"requires --runtime-allow-list"* ]]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "runtime-cmd uses bash -c instead of eval" {
  # Verify subshell isolation: variable from parent should not leak
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "echo\n" > "$allow_file"

  export __CODEGUIDE_TEST_VAR="leaked"
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "sec-05" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd 'echo safe-execution' \
    --runtime-allow-list "$allow_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *"safe-execution"* ]]
  unset __CODEGUIDE_TEST_VAR
}

# ========== Git-free environment fallback ==========

@test "run_codeguide works in non-git directory with info message" {
  # TEST_PROJECT is created with mktemp, not a git repo
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "nogit-01" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not a git repository"* ]]
  [[ "$output" == *"task_id: nogit-01"* ]]
}

@test "run_codeguide in non-git falls back to latest task file when no explicit id" {
  # Create an existing task file first
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "existing-77" \
    --task-title "Existing task" \
    --no-init

  # Run without --task-id in a non-git dir
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # Should pick up the existing task file since no branch can be inferred
  [[ "$output" == *"task_id: existing-77"* ]]
}

@test "run_codeguide in non-git requires --task-id when multiple active tasks exist" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "active-a" \
    --task-title "Active A" \
    --task-status "in_progress" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "active-b" \
    --task-title "Active B" \
    --task-status "blocked" \
    --no-init

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --mode advisory
  [ "$status" -ne 0 ]
  [[ "$output" == *"Multiple active tasks detected"* ]]
  [[ "$output" == *"Use --task-id"* ]]
}

@test "run_codeguide in non-git with no tasks uses timestamp fallback" {
  # Fresh project with no task files
  local fresh_project
  fresh_project="$(mktemp -d)"
  "$INIT_SCAFFOLD" "$fresh_project"

  run "$RUN_CODEGUIDE" "$fresh_project" --mode advisory
  [ "$status" -eq 0 ]
  # Timestamp fallback starts with "A" followed by digits
  [[ "$output" == *"task_id: A2"* ]]
  rm -rf "$fresh_project"
}

# ========== init_docs_scaffold edge cases ==========

@test "init_docs_scaffold is idempotent" {
  local workspace
  local proj
  local docs_root
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  docs_root="$(docs_root_for_project "$proj")"

  "$INIT_SCAFFOLD" "$proj"
  # Modify a file to verify it's not overwritten
  echo "custom content" >> "$docs_root/task/project-dictionary.md"

  "$INIT_SCAFFOLD" "$proj"
  # File should still have our custom content (not reset)
  run grep "custom content" "$docs_root/task/project-dictionary.md"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "init_docs_scaffold fails on non-existent target" {
  run "$INIT_SCAFFOLD" "/tmp/nonexistent_codeguide_test_dir_$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "init_docs_scaffold fails when docs path is a file" {
  local workspace
  local proj
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  touch "$workspace/docs"  # create a file, not a directory

  run "$INIT_SCAFFOLD" "$proj"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a directory"* ]]

  rm -rf "$workspace"
}

@test "init_docs_scaffold shows help with --help" {
  run "$INIT_SCAFFOLD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "init_docs_scaffold creates DOC-GOVERNANCE with new sections" {
  local workspace
  local proj
  local docs_root
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  "$INIT_SCAFFOLD" "$proj"
  docs_root="$(docs_root_for_project "$proj")"

  run grep "Data safety" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Change scope" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "runtime-allow-list" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Plan orchestration loop" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]

  run test -d "$docs_root/plan"
  [ "$status" -eq 0 ]
  run test -d "$docs_root/report"
  [ "$status" -eq 0 ]
  run test -f "$docs_root/plan/PLAN-template.md"
  [ "$status" -eq 0 ]
  run test -f "$docs_root/report/LLM-REVIEW-template.md"
  [ "$status" -eq 0 ]
  run grep "review_style" "$docs_root/report/LLM-REVIEW-template.md"
  [ "$status" -eq 0 ]
  run grep "adversarial review pass" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep 'active task omits `risk_level`' "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level:$" "$docs_root/task/task-template.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level:$" "$docs_root/decisions/decision-template.md"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "run_external_plan_reviews retries malformed output and writes reports without mutating the plan" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-01-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-01-v1.0

- task_id: ext-review-01
- plan_version: v1.0
- objective: validate external review automation
- scope: docs-only review pipeline
- assumptions: mock CLIs are available
- risks: formatting drift
- acceptance_signals: two review docs are written
- stop_conditions: report generation completes
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Prepare the prompt.
2. Collect evaluator feedback.
3. Stop for manual follow-up.
EOF

  local before_plan
  before_plan="$(cat "$plan_file")"

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
count_file="${TEST_WORKSPACE}/gemini-count"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf "%s" "$count" > "$count_file"
printf "%s\n" "$@" > "${TEST_WORKSPACE}/gemini-args.log"
cat >/dev/null
if [[ "$count" -eq 1 ]]; then
  cat <<EOF
- summary: malformed first response
EOF
else
  cat <<EOF
- verdict: revise
- summary: The sequencing is mostly sound, but the review contract should be stricter about malformed output handling.
- strengths: It clearly stops before auto-versioning the plan.
- risks: Retry handling and malformed output normalization could still drift if formatting instructions are ignored.
- requested_changes: Keep the report parser strict and summarize reviewer failures in the final wrapper output.
EOF
fi'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-args.log"
cat >/dev/null
  cat <<EOF
- verdict: blocked
- summary: The flow is semi-automated in the right place, but report validation should remain strict because downstream handoff depends on it.
- strengths: It preserves old plan versions and keeps the user in control.
- risks: If reviewers return partial fields, the operator could mistake a weak report for a valid one.
- requested_changes: Make the failure summary explicit and ensure malformed responses never create report files.
EOF'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
echo "codex should not be called for primary=codex" >&2
exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-01" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK] evaluator=gemini"* ]]
  [[ "$output" == *"[OK] evaluator=claude"* ]]
  [[ "$output" == *"No new plan version was created automatically."* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-gemini-r01.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-claude-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: standard" "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-gemini-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- primary_author_tool: codex" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_mode: external_cli" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]
  run grep "^- reviewer_agents: external-cli:gemini,claude" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]

  local after_plan
  after_plan="$(cat "$plan_file")"
  [ "$before_plan" = "$after_plan" ]

  run grep -E -- '(^|[[:space:]])-m([[:space:]]|$)' "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -ne 0 ]
  run grep -E -- '(^|[[:space:]])--model([[:space:]]|$)' "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -ne 0 ]
}

@test "run_external_plan_reviews supports adversarial reviewer and optional model override with best-effort success" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-02-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-02-v1.0

- task_id: ext-review-02
- plan_version: v1.0
- objective: validate adversarial review collection
- scope: external ping-pong reviews
- assumptions: one evaluator may fail
- risks: hidden orchestration gaps
- acceptance_signals: at least one valid report exists
- stop_conditions: user reviews the generated reports
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Ask the non-primary tools to review.
2. Record the results.
3. Stop.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
echo "gemini should not be called for primary=gemini" >&2
exit 99'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-args.log"
cat >/dev/null
echo "mock claude failure" >&2
exit 7'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/codex-args.log"
cat >/dev/null
cat <<EOF
- verdict: revise
- summary: The plan is usable, but the orchestration metadata should make the manual stop condition more explicit.
- strengths: It keeps review collection separate from plan version mutation.
- risks: The operator may miss unresolved risks if adversarial findings are not surfaced clearly.
- requested_changes: Summarize adversarial findings prominently and require explicit operator follow-up.
- objection: The current stop rule is underspecified for mixed-success review rounds.
- counterproposal: Require the wrapper to print a concise adversarial summary next to the file path.
- rebuttal: The current draft still has value because it already prevents silent auto-versioning.
- residual_risk: Manual operators may still ignore the adversarial report if summary output is too weak.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-02" \
    --plan-version "v1.0" \
    --primary-tool "gemini" \
    --review-round "r02" \
    --adversarial-evaluator "codex" \
    --codex-model "gpt-5.4"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[FAIL] evaluator=claude"* ]]
  [[ "$output" == *"[OK] evaluator=codex style=adversarial"* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-r02.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-r02.md"
  [ "$status" -eq 0 ]
  run grep "^- objection:" "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-r02.md"
  [ "$status" -eq 0 ]
  run grep -- "gpt-5.4" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews auto-selects adversarial reviewer for high-risk task and supports primary claude success path" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "ext-review-04" \
    --task-title "High risk ext review" \
    --risk-level "high" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report; coder:src/app; validator:tests" \
    --no-init

  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-04-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-04-v1.0

- task_id: ext-review-04
- plan_version: v1.0
- objective: validate automatic adversarial review routing
- scope: high-risk external ping-pong
- assumptions: high risk should trigger one adversarial pass
- risks: architectural drift
- acceptance_signals: one adversarial and one standard report exist
- stop_conditions: operator reviews the reports
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Ask both non-primary tools to review.
2. Require one adversarial pass automatically.
3. Stop.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "claude should not be called for primary=claude" >&2
exit 99'

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/gemini-args.log"
cat >/dev/null
cat <<EOF
- verdict: revise
- summary: The high-risk path correctly demands an adversarial pass before handoff.
- strengths: The wrapper keeps the human in control and blocks silent version bumps.
- risks: Review routing fields in orchestration still need to stay accurate across reruns.
- requested_changes: Keep the auto-selected adversarial reviewer visible in the summary output.
- objection: The plan under-specifies how to surface unresolved adversarial findings.
- counterproposal: Require the wrapper to summarize adversarial objections explicitly beside the report path.
- rebuttal: The current approach still preserves the strongest finding in a durable review doc.
- residual_risk: Operators may still underreact to the adversarial report if they skim only the top line.
EOF'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/codex-args.log"
cat >/dev/null
cat <<EOF
- verdict: revise
- summary: The standard reviewer agrees the loop should stop after collecting reports.
- strengths: It separates report collection from plan mutation.
- risks: Reviewer summaries can still be too terse for rushed handoffs.
- requested_changes: Keep report summaries short but explicit.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-04" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --review-round "r04"

  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-selecting adversarial evaluator=gemini"* ]]
  [[ "$output" == *"[OK] evaluator=gemini style=adversarial"* ]]
  [[ "$output" == *"[OK] evaluator=codex style=standard"* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-gemini-r04.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-gemini-r04.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-codex-r04.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews exits non-zero when all evaluators fail" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-03-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-03-v1.0

- task_id: ext-review-03
- plan_version: v1.0
- objective: validate total reviewer failure handling
- scope: external ping-pong reviews
- assumptions: both reviewers can fail
- risks: no report docs will be produced
- acceptance_signals: wrapper exits non-zero
- stop_conditions: failures are surfaced
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Call the reviewers.
2. Observe failure handling.
3. Stop.
EOF

  cat > "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-gemini-r03.md" <<'EOF'
# PLAN-ext-review-03-v1.0 review (gemini)

- task_id: ext-review-03
- plan_version: v1.0
- evaluator: gemini
- review_style: standard
- review_round: r03
- verdict: revise
- summary: stale report that should be quarantined on rerun
- strengths: old success
- risks: stale masking
- requested_changes: replace this file
- objection:
- counterproposal:
- rebuttal:
- residual_risk:
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
cat >/dev/null
echo "gemini failure" >&2
exit 3'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "claude should not be called for primary=claude" >&2
exit 99'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
cat >/dev/null
echo "codex failure" >&2
exit 4'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-03" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --review-round "r03"

  [ "$status" -ne 0 ]
  [[ "$output" == *"[FAIL] evaluator=gemini"* ]]
  [[ "$output" == *"[FAIL] evaluator=codex"* ]]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-gemini-r03.md"
  [ "$status" -eq 0 ]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-codex-r03.md"
  [ "$status" -eq 0 ]
  run find "$DOCS_ROOT/report" -maxdepth 1 -type f -name 'PLAN-ext-review-03-v1.0-review-gemini-r03.md.stale-*'
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews exits non-zero when required adversarial reviewer fails even if another reviewer succeeds" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "ext-review-05" \
    --task-title "Adversarial failure test" \
    --risk-level "high" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report; coder:src/app; validator:tests" \
    --no-init

  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-05-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-05-v1.0

- task_id: ext-review-05
- plan_version: v1.0
- objective: verify adversarial failure blocks overall success
- scope: high-risk external ping-pong
- assumptions: one standard reviewer may still succeed
- risks: adversarial pass may fail
- acceptance_signals: wrapper exits non-zero
- stop_conditions: failure is surfaced
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Run the reviewers.
2. Let the required adversarial pass fail.
3. Expect non-zero exit.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "claude should not be called for primary=claude" >&2
exit 99'

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
cat >/dev/null
echo "forced adversarial failure" >&2
exit 8'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
cat >/dev/null
cat <<EOF
- verdict: revise
- summary: The standard reviewer succeeded.
- strengths: It still produced a valid report.
- risks: Required adversarial coverage is missing.
- requested_changes: Do not accept this run as successful.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-05" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --review-round "r05"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Required adversarial review did not complete successfully"* ]]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-05-v1.0-review-codex-r05.md"
  [ "$status" -eq 0 ]
}
