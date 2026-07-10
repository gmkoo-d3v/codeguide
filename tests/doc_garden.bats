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

@test "doc_garden accepts canonical codex current-task debate orchestration fields" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-codex-debate-01" \
    --task-title "Codex debate enum test" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "codex" \
    --review-mode "current_task_debate" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  [ "$status" -eq 0 ]
  local orch_file="$DOCS_ROOT/orchestration/orch-codex-debate-01/ORCH.md"
  run grep "^- primary_author_tool: codex" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- review_mode: current_task_debate" "$orch_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden accepts canonical claude native subagent orchestration fields" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-claude-subagents-01" \
    --task-title "Claude native subagents enum test" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "claude" \
    --review-mode "claude_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  [ "$status" -eq 0 ]
  local orch_file="$DOCS_ROOT/orchestration/orch-claude-subagents-01/ORCH.md"
  run grep "^- primary_author_tool: claude" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- review_mode: claude_subagents" "$orch_file"
  [ "$status" -eq 0 ]

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"invalid orchestration.review_mode"* ]]
}

@test "orchestration enum contract stays aligned across references and producers" {
  local repo_root
  repo_root="$(cd "$SCRIPTS_DIR/.." && pwd)"
  local canonical_primary="Allowed primary_author_tool values: antigravity | agy | claude | codex | human | external-runner."
  local canonical_review="Allowed review_mode values: external_cli | current_task_debate | agy_subagents | claude_subagents | codex_subagents."
  local canonical_external_status="Allowed external_review_status values: not_requested | requested | running | awaiting_response | ingested | blocked | waived."
  local canonical_required_for="Allowed external_review_required_for values: plan_acceptance | implementation_start | commit | close."

  for path in \
    "$repo_root/references/docs-system-of-record.md" \
    "$repo_root/scripts/init_docs_scaffold.sh" \
    "$repo_root/scripts/doc_garden.sh" \
    "$repo_root/scripts/run_external_plan_reviews.sh"; do
    run grep -F -- "${canonical_primary}" "$path"
    [ "$status" -eq 0 ]
    run grep -F -- "${canonical_review}" "$path"
    [ "$status" -eq 0 ]
    run grep -F -- "${canonical_external_status}" "$path"
    [ "$status" -eq 0 ]
    run grep -F -- "${canonical_required_for}" "$path"
    [ "$status" -eq 0 ]
  done

  run grep -F -- '`primary_author_tool`: `antigravity|agy|claude|codex|human|external-runner`' "$repo_root/references/orchestration-contract.md"
  [ "$status" -eq 0 ]
  run grep -F -- '`review_mode`: `external_cli|current_task_debate|agy_subagents|claude_subagents|codex_subagents`' "$repo_root/references/orchestration-contract.md"
  [ "$status" -eq 0 ]

  run grep -F "check_enum_membership \"\$review_mode\" \"orchestration.review_mode\"" "$repo_root/scripts/validate_docs.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"external_cli current_task_debate agy_subagents claude_subagents codex_subagents"* ]]
}

@test "doc_garden scaffold orchestration validates without enum template warnings" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-template-values-01" \
    --task-title "Template values stay blank or valid" \
    --no-init
  [ "$status" -eq 0 ]

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" != *"invalid orchestration."* ]]
}

@test "doc_garden rejects external-runner as risk preflight recorder" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-recorder-external-runner-01" \
    --task-title "External runner recorder rejection" \
    --risk-preflight-recorded-by "external-runner" \
    --no-init

  [ "$status" -ne 0 ]
  [[ "$output" == *"--risk-preflight-recorded-by must identify the main-thread supervising lead architect"* ]]
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

# ========== resume capsule checkpoint (session-resume-contract.md) ==========

make_resume_source_repo() {
  local source_repo="$1"

  mkdir -p "$source_repo"
  git -C "$source_repo" init --quiet
  git -C "$source_repo" config user.email "test@test.com"
  git -C "$source_repo" config user.name "test"
  printf 'one\n' > "$source_repo/a.txt"
  git -C "$source_repo" add a.txt
  git -C "$source_repo" commit -q -m "init"
}

@test "doc_garden resume-checkpoint writes all four script-maintained fields" {
  local source_repo="$TEST_WORKSPACE/resume-source-01"
  make_resume_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-fields-01" --task-title "Resume fields" --task-status in_progress --no-init

  printf 'two\n' >> "$source_repo/a.txt"

  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-fields-01" --resume-checkpoint
  [ "$status" -eq 0 ]

  local task_file="$DOCS_ROOT/task/TASK-resume-fields-01.md"
  local head_sha
  head_sha="$(git -C "$source_repo" rev-parse HEAD)"

  run grep "^- resume_source_head: ${head_sha} (dirty: 1 files)$" "$task_file"
  [ "$status" -eq 0 ]
  run grep "^- resume_changed_files: a.txt$" "$task_file"
  [ "$status" -eq 0 ]
  run grep -E "^- resume_checkpointed_at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$task_file"
  [ "$status" -eq 0 ]
  run grep "^- resume_state_revision: 1$" "$task_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden resume-checkpoint split-root fixture resolves the source repo via the marker file" {
  local source_repo="$TEST_WORKSPACE/resume-source-splitroot"
  make_resume_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-splitroot-01" --task-title "Split root" --task-status in_progress --no-init

  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-splitroot-01" --resume-checkpoint
  [ "$status" -eq 0 ]

  local task_file="$DOCS_ROOT/task/TASK-resume-splitroot-01.md"
  local head_sha
  head_sha="$(git -C "$source_repo" rev-parse HEAD)"

  # Clean source repo (no working-tree changes) resolves via the marker file,
  # not the (non-git) docs root itself.
  run grep "^- resume_source_head: ${head_sha} (clean)$" "$task_file"
  [ "$status" -eq 0 ]
  run grep "^- resume_changed_files: none$" "$task_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden resume-checkpoint is deterministic apart from checkpointed_at and revision" {
  local source_repo="$TEST_WORKSPACE/resume-source-determinism"
  make_resume_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"
  printf 'two\n' >> "$source_repo/a.txt"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-determinism-01" --task-title "Determinism" --task-status in_progress --no-init

  local task_file="$DOCS_ROOT/task/TASK-resume-determinism-01.md"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-determinism-01" --resume-checkpoint
  local head_line_1 changed_line_1
  head_line_1="$(grep "^- resume_source_head:" "$task_file")"
  changed_line_1="$(grep "^- resume_changed_files:" "$task_file")"

  sleep 1
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-determinism-01" --resume-checkpoint
  local head_line_2 changed_line_2
  head_line_2="$(grep "^- resume_source_head:" "$task_file")"
  changed_line_2="$(grep "^- resume_changed_files:" "$task_file")"

  [ "$head_line_1" = "$head_line_2" ]
  [ "$changed_line_1" = "$changed_line_2" ]

  run grep "^- resume_state_revision: 2$" "$task_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden resume-checkpoint increments resume_state_revision across runs and resets from a non-numeric value" {
  local source_repo="$TEST_WORKSPACE/resume-source-revision"
  make_resume_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-revision-01" --task-title "Revision" --task-status in_progress --no-init
  local task_file="$DOCS_ROOT/task/TASK-resume-revision-01.md"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-revision-01" --resume-checkpoint
  run grep "^- resume_state_revision: 1$" "$task_file"
  [ "$status" -eq 0 ]

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-revision-01" --resume-checkpoint
  run grep "^- resume_state_revision: 2$" "$task_file"
  [ "$status" -eq 0 ]

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-revision-01" --resume-checkpoint
  run grep "^- resume_state_revision: 3$" "$task_file"
  [ "$status" -eq 0 ]

  sed -i.bak 's/^- resume_state_revision: 3/- resume_state_revision: corrupted/' "$task_file"
  rm -f "${task_file}.bak"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-revision-01" --resume-checkpoint
  run grep "^- resume_state_revision: 1$" "$task_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden resume-checkpoint caps resume_changed_files at 10 entries with a (+N more) suffix" {
  local source_repo="$TEST_WORKSPACE/resume-source-cap"
  make_resume_source_repo "$source_repo"
  printf '%s' "$source_repo" > "$TEST_PROJECT/.codeguide-source-root"

  local i
  for i in $(seq 1 14); do
    printf 'x\n' > "$source_repo/untracked-file-$(printf '%02d' "$i").txt"
  done

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-cap-01" --task-title "Cap test" --task-status in_progress --no-init

  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-cap-01" --resume-checkpoint
  [ "$status" -eq 0 ]

  local task_file="$DOCS_ROOT/task/TASK-resume-cap-01.md"
  run grep "^- resume_source_head:.*(dirty: 14 files)$" "$task_file"
  [ "$status" -eq 0 ]

  local changed_line
  changed_line="$(grep "^- resume_changed_files:" "$task_file")"
  [[ "$changed_line" == *" (+4 more)" ]]
  # Exactly 10 capped entries before the suffix.
  local entries
  entries="${changed_line#- resume_changed_files: }"
  entries="${entries% (+4 more)}"
  local entry_count
  entry_count="$(printf "%s\n" "$entries" | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' ')"
  [ "$entry_count" -eq 10 ]
  # Sorted ascending.
  local sorted_entries
  sorted_entries="$(printf "%s\n" "$entries" | tr ',' '\n' | sort)"
  [ "$(printf "%s\n" "$entries" | tr ',' '\n')" = "$sorted_entries" ]
}

@test "doc_garden resume-checkpoint writes no-source-repo when no source repo is reachable" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-nosource-01" --task-title "No source" --task-status in_progress --no-init
  [ "$status" -eq 0 ]

  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-nosource-01" --resume-checkpoint
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] Not a git repository: no source repo reachable"* ]]

  local task_file="$DOCS_ROOT/task/TASK-resume-nosource-01.md"
  run grep "^- resume_source_head: no-source-repo$" "$task_file"
  [ "$status" -eq 0 ]
  run grep "^- resume_changed_files: none$" "$task_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden resume-checkpoint pass-through options land the three agent-maintained fields" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-passthrough-01" --task-title "Pass-through" --task-status in_progress --no-init
  [ "$status" -eq 0 ]

  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-passthrough-01" --resume-checkpoint \
    --resume-next-action "run the bats suite" \
    --resume-last-verified "bash -n scripts/doc_garden.sh" \
    --resume-blockers "none"
  [ "$status" -eq 0 ]

  local task_file="$DOCS_ROOT/task/TASK-resume-passthrough-01.md"
  run grep "^- resume_next_action: run the bats suite$" "$task_file"
  [ "$status" -eq 0 ]
  run grep "^- resume_last_verified: bash -n scripts/doc_garden.sh$" "$task_file"
  [ "$status" -eq 0 ]
  run grep "^- resume_blockers: none$" "$task_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden resume-checkpoint does not touch the shadow graph or any other doc mutation" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-surgical-01" --task-title "Surgical" --task-status in_progress --no-init
  [ "$status" -eq 0 ]

  local shadow_before shadow_global_before index_before orch_before
  shadow_before="$(cat "$DOCS_ROOT/shadow/project-shadow.md")"
  shadow_global_before="$(cat "$DOCS_ROOT/shadow/_global.md")"
  index_before="$(cat "$DOCS_ROOT/task/task-index.md")"
  orch_before="$(cat "$DOCS_ROOT/orchestration/resume-surgical-01/ORCH.md")"

  sleep 1
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-surgical-01" --resume-checkpoint \
    --resume-next-action "x" --resume-last-verified "y" --resume-blockers "none"
  [ "$status" -eq 0 ]

  [ "$(cat "$DOCS_ROOT/shadow/project-shadow.md")" = "$shadow_before" ]
  [ "$(cat "$DOCS_ROOT/shadow/_global.md")" = "$shadow_global_before" ]
  [ "$(cat "$DOCS_ROOT/task/task-index.md")" = "$index_before" ]
  [ "$(cat "$DOCS_ROOT/orchestration/resume-surgical-01/ORCH.md")" = "$orch_before" ]
}

@test "doc_garden rejects --resume-checkpoint without --task-id" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --resume-checkpoint
  [ "$status" -ne 0 ]
  [[ "$output" == *"--resume-checkpoint requires --task-id"* ]]
}

@test "doc_garden rejects resume pass-through options without --resume-checkpoint" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-guard-01" --resume-next-action "x" --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"require --resume-checkpoint"* ]]
}

@test "doc_garden rejects --resume-checkpoint for a task file that does not exist yet" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-missing-01" --resume-checkpoint
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires an existing task file"* ]]
}

@test "resume checkpoint records an unborn source-repo HEAD instead of dying" {
  local parent="$TEST_WORKSPACE/unborn-root"
  mkdir -p "$parent/docs" "$parent/skillpkg/scripts"
  printf -- "---\nname: fixture-skill\n---\n" > "$parent/skillpkg/SKILL.md"
  git -C "$parent/skillpkg" init --quiet
  printf 'skillpkg\n' > "$parent/.codeguide-source-root"
  printf 'x=1\n' > "$parent/skillpkg/new.py"
  "$DOC_GARDEN" "$parent" --task-id "unborn-01" --task-title "Unborn fixture" >/dev/null

  run "$DOC_GARDEN" "$parent" --task-id "unborn-01" --resume-checkpoint --no-init
  [ "$status" -eq 0 ]
  run grep "^- resume_source_head: unborn (dirty: 2 files)" "$parent/docs/task/TASK-unborn-01.md"
  [ "$status" -eq 0 ]
  run grep "^- resume_changed_files: SKILL.md,new.py" "$parent/docs/task/TASK-unborn-01.md"
  [ "$status" -eq 0 ]
}
