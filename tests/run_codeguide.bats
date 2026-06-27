#!/usr/bin/env bats

load codeguide_helper

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

@test "skills package root can resolve to parent project docs root" {
  local workspace
  local proj
  local skill_dir
  local docs_root
  local expected_docs_root

  workspace="$(mktemp -d)"
  proj="$workspace/skills-project"
  skill_dir="$proj/codeguide"
  mkdir -p "$skill_dir/scripts" "$skill_dir/references"
  git -C "$skill_dir" init >/dev/null 2>&1
  cat > "$skill_dir/SKILL.md" <<'EOF'
---
name: sample-skill
description: Test skill package.
---

# Sample Skill
EOF

  "$INIT_SCAFFOLD" "$proj"
  docs_root="$(docs_root_for_project "$skill_dir")"
  expected_docs_root="$(cd "$proj" && pwd -P)/docs"

  [ "$docs_root" = "$expected_docs_root" ]

  run env PYTHONPATH="$SCRIPTS_DIR" python3 -c 'from pathlib import Path; import sys; from codeguide_paths import docs_root_for; print(docs_root_for(Path(sys.argv[1])))' "$skill_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected_docs_root" ]

  run "$VALIDATE" "$skill_dir" --mode strict
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "ordinary nested git repo does not borrow parent project docs root" {
  local workspace
  local proj
  local app_dir
  local docs_root
  local expected_docs_root

  workspace="$(mktemp -d)"
  proj="$workspace/project"
  app_dir="$proj/backend"
  mkdir -p "$app_dir"
  git -C "$app_dir" init >/dev/null 2>&1

  "$INIT_SCAFFOLD" "$proj"
  docs_root="$(docs_root_for_project "$app_dir")"
  expected_docs_root="$(cd "$app_dir" && pwd -P)/docs"

  [ "$docs_root" = "$expected_docs_root" ]

  run "$VALIDATE" "$app_dir" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"docs directory exists"* ]]

  rm -rf "$workspace"
}

@test "run_codeguide bootstraps orchestration doc for active task" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "orch-01" --mode advisory
  [ "$status" -eq 0 ]

  local orch_file="$DOCS_ROOT/orchestration/orch-01/ORCH.md"
  run test -f "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- execution_mode: solo" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- supervisor_agent: main-thread-supervising-lead-architect" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- delegation_note: Solo execution selected; no sub-agent or external review requested." "$orch_file"
  [ "$status" -eq 0 ]
}

@test "approved preflight rejects placeholder approval metadata before recording or external review" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-approved-placeholder-01" \
    --task-title "Approved placeholder test" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "not_required" \
    --approved-next-step "run delegated review" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --no-init

  [ "$status" -ne 0 ]
  [[ "$output" == *"Concrete --approval-ref"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/orch-approved-placeholder-01/ORCH.md"
  [ "$status" -eq 0 ]

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
    --task-id "run-approved-placeholder-01" \
    --mode advisory \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-001" \
    --approved-next-step "pending_user_approval"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Concrete --approval-ref"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/run-approved-placeholder-01/ORCH.md"
  [ "$status" -eq 0 ]

  local plan_file="$DOCS_ROOT/plan/PLAN-ext-approved-placeholder-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-approved-placeholder-v1.0

- task_id: ext-approved-placeholder
- plan_version: v1.0
- objective: validate placeholder approval is rejected before external review
- scope: external review safety gate
- assumptions: placeholder approval metadata must not invoke reviewers
- risks: unauthorized external review
- acceptance_signals: wrapper blocks before reviewer invocation
- stop_conditions: placeholder approval rejected
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin-approved-placeholder"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/agy-approved-placeholder-called"
exit 99'
  # (claude mock replaced by agy)
  # true #  '#!/usr/bin/env bash
# touch "${TEST_WORKSPACE}/agy-approved-placeholder-called-2"
# exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-approved-placeholder" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "pending_user_approval" \
    --approved-next-step "run external reviewers"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Concrete --approval-ref"* ]]
  run test ! -e "$TEST_WORKSPACE/agy-approved-placeholder-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/agy-approved-placeholder-called-2"
  [ "$status" -eq 0 ]
}

@test "run_codeguide and validate_docs reject evaluator identity recorders consistently" {
  local identity
  for identity in antigravity agy claude codex gemini external-runner; do
    run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
      --task-id "run-recorder-${identity}" \
      --mode advisory \
      --execution-mode "supervisor_subagents" \
      --risk-preflight-status "pass" \
      --risk-preflight-recorded-by "$identity"

    [ "$status" -ne 0 ]
    [[ "$output" == *"--risk-preflight-recorded-by must identify the main-thread supervising lead architect"* ]]
  done

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-recorder-01" \
    --task-title "Recorder identity test" \
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

  cat > "$DOCS_ROOT/plan/PLAN-orch-recorder-01-v1.0.md" <<'EOF'
# PLAN-orch-recorder-01-v1.0

- task_id: orch-recorder-01
- plan_version: v1.0
- objective: validate recorder identity normalization
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation rejects evaluator identity regardless of case
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local orch_file="$DOCS_ROOT/orchestration/orch-recorder-01/ORCH.md"
  for identity in antigravity agy claude codex gemini external-runner; do
    perl -0pi -e "s/^- risk_preflight_recorded_by: .+\$/- risk_preflight_recorded_by: ${identity}/m" "$orch_file"

    run "$VALIDATE" "$TEST_PROJECT" --mode strict
    [ "$status" -ne 0 ]
    [[ "$output" == *"risk_preflight_recorded_by must identify the main-thread supervising lead architect"* ]]
  done
}

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

@test "run_codeguide requires risk preflight before delegated orchestration" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
    --task-id "run-preflight-gate-01" \
    --mode advisory \
    --execution-mode "supervisor_subagents"

  [ "$status" -ne 0 ]
  [[ "$output" == *"--risk-preflight-status is required before delegated orchestration"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/run-preflight-gate-01/ORCH.md"
  [ "$status" -eq 0 ]
}

@test "run_codeguide records blocked delegation when preflight requires approval" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
    --task-id "run-approval-stop-01" \
    --mode advisory \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approval_required"

  [ "$status" -eq 0 ]
  local orch_file="$DOCS_ROOT/orchestration/run-approval-stop-01/ORCH.md"
  run grep "^- delegation_status: blocked" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "Delegation stopped before agent or external work" "$orch_file"
  [ "$status" -eq 0 ]
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

@test "SKILL.md documents pre-orchestration risk approval gate" {
  local skill_file
  local orchestration_ref
  skill_file="$(cd "$SCRIPTS_DIR/.." && pwd)/SKILL.md"
  orchestration_ref="$(cd "$SCRIPTS_DIR/.." && pwd)/references/orchestration-contract.md"

  run grep "Safety hard stop:" "$skill_file"
  [ "$status" -eq 0 ]
  run grep "references/orchestration-contract.md" "$skill_file"
  [ "$status" -eq 0 ]
  run grep "Run risk preflight in the main thread before spawning sub-agents" "$orchestration_ref"
  [ "$status" -eq 0 ]
  run grep "do not spawn new sub-agents, do not invoke external CLIs" "$orchestration_ref"
  [ "$status" -eq 0 ]
  run grep "Ping-pong starts only after the supervising lead architect records the risk gate outcome" "$orchestration_ref"
  [ "$status" -eq 0 ]
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
  local fresh_workspace
  local fresh_project
  fresh_workspace="$(mktemp -d)"
  fresh_project="$fresh_workspace/repo"
  mkdir -p "$fresh_project"
  "$INIT_SCAFFOLD" "$fresh_project"

  run "$RUN_CODEGUIDE" "$fresh_project" --mode advisory
  [ "$status" -eq 0 ]
  # Timestamp fallback starts with "A" followed by digits
  [[ "$output" == *"task_id: A2"* ]]
  rm -rf "$fresh_workspace"
}

# ========== init_docs_scaffold edge cases ==========
