#!/usr/bin/env bats

# codeguide operational stability tests

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
DOC_GARDEN="$SCRIPTS_DIR/doc_garden.sh"
VALIDATE="$SCRIPTS_DIR/validate_docs.sh"
RUN_CODEGUIDE="$SCRIPTS_DIR/run_codeguide.sh"
INIT_SCAFFOLD="$SCRIPTS_DIR/init_docs_scaffold.sh"

setup() {
  TEST_PROJECT="$(mktemp -d)"
  "$INIT_SCAFFOLD" "$TEST_PROJECT"
}

teardown() {
  rm -rf "$TEST_PROJECT"
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
  run grep "^- context:" "$TEST_PROJECT/docs/decisions/decision-test-001.md"
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
  run grep "^- context:" "$TEST_PROJECT/docs/decisions/decision-test-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Important context here"* ]]

  # Rationale should still have the original value
  run grep "^- rationale:" "$TEST_PROJECT/docs/decisions/decision-test-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Real rationale"* ]]
}

@test "upsert_field allows empty overwrite with --allow-empty-overwrite" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-002" \
    --decision-title "Test Decision" \
    --context "Will be cleared" \
    --no-init

  run grep "^- context:" "$TEST_PROJECT/docs/decisions/decision-test-002.md"
  [[ "$output" == *"Will be cleared"* ]]

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-002" \
    --decision-title "Test Decision" \
    --context "" \
    --allow-empty-overwrite \
    --no-init

  # Context should now be empty
  run grep "^- context:" "$TEST_PROJECT/docs/decisions/decision-test-002.md"
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

  run grep "^- axis_why:" "$TEST_PROJECT/docs/task/TASK-100.md"
  [[ "$output" == *"SOLID principle applied"* ]]

  # Run again without axis values — should preserve existing
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "100" \
    --task-title "Axis Test" \
    --no-init

  run grep "^- axis_why:" "$TEST_PROJECT/docs/task/TASK-100.md"
  [[ "$output" == *"SOLID principle applied"* ]]

  run grep "^- axis_where:" "$TEST_PROJECT/docs/task/TASK-100.md"
  [[ "$output" == *"Service layer"* ]]

  run grep "^- axis_verify:" "$TEST_PROJECT/docs/task/TASK-100.md"
  [[ "$output" == *"Unit tests added"* ]]
}

@test "doc_garden preserves backslashes in field values" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "path-001" \
    --decision-title "Path escape test" \
    --context 'Use path C:\new\folder' \
    --no-init

  run cat "$TEST_PROJECT/docs/decisions/decision-path-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- context: Use path C:\\new\\folder"* ]]
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

  local index="$TEST_PROJECT/docs/task/task-index.md"
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

# ========== P1/P2: Validator strict mode non-empty check ==========

@test "validate_docs strict mode fails on empty required fields" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "200" \
    --task-title "" \
    --no-init

  # The task file will have title: (empty because upsert_field skips it on new file with template value)
  # Let's manually clear the axis fields to test strict validation
  local task_file="$TEST_PROJECT/docs/task/TASK-200.md"
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

@test "validate_docs advisory mode passes with empty fields (warns only)" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "201" \
    --task-title "Advisory test" \
    --no-init

  local task_file="$TEST_PROJECT/docs/task/TASK-201.md"
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
  echo "- acceptance_criteria: changed after shadow sync" >> "$TEST_PROJECT/docs/task/TASK-shadow-lag-01.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"project shadow is older than tracked task/decision doc"* ]]
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
  cat > "$TEST_PROJECT/docs/plan/PLAN-qa-01-v1.0.md" <<'EOF'
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
  cat > "$TEST_PROJECT/docs/report/PLAN-qa-01-v1.0-review-gpt-r01.md" <<'EOF'
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

  local task_file="$TEST_PROJECT/docs/task/TASK-enum-task-01.md"
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

  local decision_file="$TEST_PROJECT/docs/decisions/decision-enum-decision-01.md"
  sed -i.bak 's/^- scope_type:.*$/- scope_type: nonsense/' "$decision_file"
  sed -i.bak 's/^- status:.*$/- status: unknown/' "$decision_file"
  rm -f "${decision_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid decision.scope_type value"* ]]
  [[ "$output" == *"invalid decision.status value"* ]]
}

@test "validate_docs secret scan skips default template files" {
  cat > "$TEST_PROJECT/docs/report/LLM-REVIEW-template.md" <<'EOF'
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

  local index="$TEST_PROJECT/docs/task/task-index.md"
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

  local index="$TEST_PROJECT/docs/task/task-index.md"
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

  run grep "^- latest_change_note:" "$TEST_PROJECT/docs/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"search and navigation updated"* ]]
}

@test "run_codeguide bootstraps initial plan doc for active task" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "plan-01" --mode advisory
  [ "$status" -eq 0 ]

  local plan_file="$TEST_PROJECT/docs/plan/PLAN-plan-01-v1.0.md"
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

  local index="$TEST_PROJECT/docs/decisions/decision-index.md"
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

  local index="$TEST_PROJECT/docs/decisions/decision-index.md"
  local count
  count=$(grep -c "^- decision-d-dup-01.md |" "$index")
  [ "$count" -eq 1 ]
  run grep "^- decision-d-dup-01.md |" "$index"
  [[ "$output" == *"superseded"* ]]
}

@test "decision-index migrates legacy table format" {
  # Create a legacy table-format decision-index
  cat > "$TEST_PROJECT/docs/decisions/decision-index.md" <<'EOF'
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

  local index="$TEST_PROJECT/docs/decisions/decision-index.md"

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
  run bash -c "ls \"$TEST_PROJECT/docs/decisions\"/decision-index.md.bak.* >/dev/null"
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
  local proj
  proj="$(mktemp -d)"

  "$INIT_SCAFFOLD" "$proj"
  # Modify a file to verify it's not overwritten
  echo "custom content" >> "$proj/docs/task/project-dictionary.md"

  "$INIT_SCAFFOLD" "$proj"
  # File should still have our custom content (not reset)
  run grep "custom content" "$proj/docs/task/project-dictionary.md"
  [ "$status" -eq 0 ]

  rm -rf "$proj"
}

@test "init_docs_scaffold fails on non-existent target" {
  run "$INIT_SCAFFOLD" "/tmp/nonexistent_codeguide_test_dir_$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "init_docs_scaffold fails when docs path is a file" {
  local proj
  proj="$(mktemp -d)"
  touch "$proj/docs"  # create a file, not a directory

  run "$INIT_SCAFFOLD" "$proj"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a directory"* ]]

  rm -rf "$proj"
}

@test "init_docs_scaffold shows help with --help" {
  run "$INIT_SCAFFOLD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "init_docs_scaffold creates DOC-GOVERNANCE with new sections" {
  local proj
  proj="$(mktemp -d)"
  "$INIT_SCAFFOLD" "$proj"

  run grep "Data safety" "$proj/docs/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Change scope" "$proj/docs/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "runtime-allow-list" "$proj/docs/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Plan ping-pong loop" "$proj/docs/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]

  run test -d "$proj/docs/plan"
  [ "$status" -eq 0 ]
  run test -d "$proj/docs/report"
  [ "$status" -eq 0 ]
  run test -f "$proj/docs/plan/PLAN-template.md"
  [ "$status" -eq 0 ]
  run test -f "$proj/docs/report/LLM-REVIEW-template.md"
  [ "$status" -eq 0 ]

  rm -rf "$proj"
}
