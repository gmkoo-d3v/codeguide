#!/usr/bin/env bats

load codeguide_helper

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

@test "doc_garden records blocked delegation when preflight still needs approval" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-approval-stop-01" \
    --task-title "Approval stop test" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approval_required" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  [ "$status" -eq 0 ]
  local orch_file="$DOCS_ROOT/orchestration/orch-approval-stop-01/ORCH.md"
  run grep "^- delegation_status: blocked" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- approval_required: true" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "Delegation stopped before agent or external work" "$orch_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden rejects external_cli review with pass preflight" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-external-pass-01" \
    --task-title "External pass should block" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "external_cli" \
    --planner-agents "planner-1" \
    --reviewer-agents "external-cli:gemini" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  [ "$status" -ne 0 ]
  [[ "$output" == *"External CLI review requires --risk-preflight-status approved"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/orch-external-pass-01/ORCH.md"
  [ "$status" -eq 0 ]
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

@test "doc_garden fails clearly when option value is missing" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id
  [ "$status" -ne 0 ]
  [[ "$output" == *"Option --task-id requires a value"* ]]
}

@test "doc_garden requires risk preflight before delegated orchestration is recorded" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "doc-preflight-gate-01" \
    --task-title "Doc preflight gate" \
    --execution-mode "supervisor_subagents" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --no-init

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires --risk-preflight-status"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/doc-preflight-gate-01/ORCH.md"
  [ "$status" -eq 0 ]
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

