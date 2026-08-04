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
  assert_contains "$output" "- context: Use path C:\\new\\folder"
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
  assert_contains "$output" "External CLI review requires --risk-preflight-status approved"
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
  refute_contains "$output" "invalid orchestration.review_mode"
}

@test "orchestration enum contract stays aligned across references and producers" {
  local repo_root
  repo_root="$(cd "$SCRIPTS_DIR/.." && pwd)"
  local canonical_primary="Allowed primary_author_tool values: antigravity | agy | claude | codex | human | external-runner."
  local canonical_review="Allowed review_mode values: external_cli | current_task_debate | agy_subagents | claude_subagents | codex_subagents."
  local canonical_external_status="Allowed external_review_status values: not_requested | requested | running | awaiting_response | ingested | blocked | waived."
  local canonical_required_for="Allowed external_review_required_for values: plan_acceptance | implementation_start | commit | close."

  for path in \
    "$repo_root/references/orchestration-review-contract.md" \
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

  # The producing call lives in the validator's rule modules since the P1
  # split; search the adapter and validate_docs.d/ so the gate stays
  # layout-agnostic.
  run grep -rF "check_enum_membership \"\$review_mode\" \"orchestration.review_mode\"" "$repo_root/scripts/validate_docs.sh" "$repo_root/scripts/validate_docs.d"
  [ "$status" -eq 0 ]
  assert_contains "$output" "external_cli current_task_debate agy_subagents claude_subagents codex_subagents"
}

@test "doc_garden scaffold orchestration validates without enum template warnings" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-template-values-01" \
    --task-title "Template values stay blank or valid" \
    --no-init
  [ "$status" -eq 0 ]

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  refute_contains "$output" "invalid orchestration."
}

@test "doc_garden rejects external-runner as risk preflight recorder" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-recorder-external-runner-01" \
    --task-title "External runner recorder rejection" \
    --risk-preflight-recorded-by "external-runner" \
    --no-init

  [ "$status" -ne 0 ]
  assert_contains "$output" "--risk-preflight-recorded-by must identify the main-thread supervising lead architect"
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
  assert_contains "$output" "graph refresh"

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

@test "doc_garden router no-op refresh (same task, same note) leaves the file byte-identical" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "router-noop-01" \
    --task-title "Router no-op" \
    --shadow-note "same note" \
    --no-init

  local before after
  before="$(cat "$DOCS_ROOT/shadow/project-shadow.md")"

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "router-noop-01" \
    --task-title "Router no-op" \
    --shadow-note "same note" \
    --no-init

  after="$(cat "$DOCS_ROOT/shadow/project-shadow.md")"
  [ "$before" = "$after" ]
}

@test "doc_garden router bumps last_updated only when task or note actually differs" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "router-diff-01" \
    --task-title "Router diff" \
    --shadow-note "first note" \
    --no-init

  local before after
  before="$(cat "$DOCS_ROOT/shadow/project-shadow.md")"

  # Re-run with the identical task-id and note first: still a no-op.
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "router-diff-01" \
    --task-title "Router diff" \
    --shadow-note "first note" \
    --no-init
  after="$(cat "$DOCS_ROOT/shadow/project-shadow.md")"
  [ "$before" = "$after" ]

  # A genuinely different note is a real change and must bump the router.
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "router-diff-01" \
    --task-title "Router diff" \
    --shadow-note "second note" \
    --no-init
  after="$(cat "$DOCS_ROOT/shadow/project-shadow.md")"
  [ "$before" != "$after" ]

  run grep "^- latest_change_note: second note" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
}

@test "doc_garden never bumps bucket or global shadow metadata docs across refreshes" {
  local global_before global_after apps_before apps_after
  global_before="$(cat "$DOCS_ROOT/shadow/_global.md")"
  apps_before="$(cat "$DOCS_ROOT/shadow/apps/_index.md")"

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "garden-no-touch-01" \
    --task-title "Garden never touches global or bucket docs" \
    --shadow-note "first refresh" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "garden-no-touch-02" \
    --task-title "Garden never touches global or bucket docs again" \
    --shadow-note "second refresh" \
    --no-init

  global_after="$(cat "$DOCS_ROOT/shadow/_global.md")"
  apps_after="$(cat "$DOCS_ROOT/shadow/apps/_index.md")"

  [ "$global_before" = "$global_after" ]
  [ "$apps_before" = "$apps_after" ]
}

@test "doc_garden rejects git_diff shadow refresh without explicit range" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "shadow-git-01" \
    --task-title "Shadow git diff validation" \
    --shadow-refresh-mode "git_diff" \
    --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "--shadow-git-range is required"
}

@test "doc_garden fails clearly when option value is missing" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id
  [ "$status" -ne 0 ]
  assert_contains "$output" "Option --task-id requires a value"
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
  assert_contains "$output" "requires --risk-preflight-status"
  run test ! -f "$DOCS_ROOT/orchestration/doc-preflight-gate-01/ORCH.md"
  [ "$status" -eq 0 ]
}

@test "doc_garden rejects invalid task id characters" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id ".*" --task-title "bad id" --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "Invalid --task-id value"
}

@test "doc_garden rejects invalid decision id characters" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "[" --decision-title "bad id" --selected-option "x" --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "Invalid --decision-id value"
}

@test "doc_garden rejects invalid task status enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "bad-status-01" \
    --task-title "bad status" \
    --task-status "working" \
    --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "Invalid --task-status"
}

@test "doc_garden rejects invalid scope type enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "bad-scope-01" \
    --decision-title "bad scope" \
    --scope-type "feature" \
    --selected-option "x" \
    --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "Invalid --scope-type"
}

@test "doc_garden rejects invalid decision status enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "bad-decision-status-01" \
    --decision-title "bad decision status" \
    --decision-status "merged" \
    --selected-option "x" \
    --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "Invalid --decision-status"
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
  [[ "$changed_line" == *" (+4 more)" ]] || false
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
  assert_contains "$output" "[WARN] Not a git repository: no source repo reachable"

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
  assert_contains "$output" "--resume-checkpoint requires --task-id"
}

@test "doc_garden rejects resume pass-through options without --resume-checkpoint" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-guard-01" --resume-next-action "x" --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "require --resume-checkpoint"
}

@test "doc_garden rejects --resume-checkpoint for a task file that does not exist yet" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "resume-missing-01" --resume-checkpoint
  [ "$status" -ne 0 ]
  assert_contains "$output" "requires an existing task file"
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

@test "resume checkpoint preserves special characters verbatim in agent fields" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "special-01" --task-title "Special chars" --no-init >/dev/null

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "special-01" --resume-checkpoint --no-init \
    --resume-next-action "run legs A + B, then C++ build & re-verify (x+y)" \
    --resume-last-verified "suite green + lint clean" \
    --resume-blockers "none" >/dev/null

  run grep -F -- "- resume_next_action: run legs A + B, then C++ build & re-verify (x+y)" "$DOCS_ROOT/task/TASK-special-01.md"
  [ "$status" -eq 0 ]
  run grep -F -- "- resume_last_verified: suite green + lint clean" "$DOCS_ROOT/task/TASK-special-01.md"
  [ "$status" -eq 0 ]
}

@test "concurrent resume checkpoints serialize and never lose revision increments" {
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "race-cp-01" --task-title "Checkpoint race" --no-init >/dev/null

  local pids=()
  for _ in 1 2 3 4 5 6 7 8; do
    "$DOC_GARDEN" "$TEST_PROJECT" --task-id "race-cp-01" --resume-checkpoint --no-init >/dev/null 2>&1 &
    pids+=($!)
  done
  local pid
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  run grep "^- resume_state_revision: 8$" "$DOCS_ROOT/task/TASK-race-cp-01.md"
  [ "$status" -eq 0 ]
}

@test "doc_garden does not rewrite a fenced example line as if it were the real field" {
  # doc_garden WRITES the capsules validate_docs reads, and it answered "where is this
  # field" with a fence-blind grep plus a `sed` carrying NO line address, so it replaced
  # every column-0 match including one inside a quoted template
  # Reproduced before the fix: a task
  # quoting the resume-capsule template had the EXAMPLE filled with live checkpoint data,
  # and `resume_state_revision` counted up from the example's number, on lines the
  # validator -- fence-aware since that task -- can no longer see at all. This one WRITES,
  # so a mistake corrupts the capsule rather than misreporting it.
  #
  # The quoted example sits ABOVE the real fields on purpose: with it below, a merely
  # line-ADDRESSED writer that is still fence-blind targets the real field by accident and
  # the fixture proves nothing. Above, only a fence-AWARE lookup skips it.
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "fenced-upsert-01" --task-title "Fenced upsert" \
    --task-status planned --risk-level low --no-init >/dev/null

  local task_file="$DOCS_ROOT/task/TASK-fenced-upsert-01.md"
  cat > "$task_file" <<'FIXTURE'
# TASK-fenced-upsert-01

## Resume capsule template (quoted example, must never be edited)

```markdown
- status: in_progress
- risk_level: critical
- resume_state_revision: 7
- resume_next_action: <what to do next>
- last_updated: <ISO>
```

- title: Fenced upsert
- objective: the writer edits the real field, never the quoted one
- acceptance_criteria: the fenced block is byte-identical afterwards
- non_goals: none
- affected_modules: docs
- interfaces_changed: none
- data_migrations: none
- test_scope: doc_garden
- risks: none
- risk_level: low
- consumes_plan_ref:
- status: planned
- owner: test
- due_date:
- axis_why: fixture
- axis_where: fixture
- axis_verify: bats
- last_updated: 2020-01-01T00:00:00Z
FIXTURE
  local fenced_before
  fenced_before="$(sed -n '/^```markdown$/,/^```$/p' "$task_file")"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "fenced-upsert-01" --task-title "Fenced upsert" \
    --task-status done --risk-level high --no-init >/dev/null
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "fenced-upsert-01" --resume-checkpoint --no-init \
    --resume-next-action "carry on" >/dev/null

  # The quoted example is byte-identical after upserts naming five keys it holds.
  local fenced_after
  fenced_after="$(sed -n '/^```markdown$/,/^```$/p' "$task_file")"
  [ "$fenced_before" = "$fenced_after" ]

  # Positive half: the REAL fields did move, so the writer is fence-aware rather than
  # merely inert, and the revision counter started from the document rather than from the
  # example's 7.
  run grep -c "^- status: done$" "$task_file"
  [ "$output" = "1" ]
  run grep -c "^- status: planned$" "$task_file"
  [ "$output" = "0" ]
  run grep -c "^- risk_level: high$" "$task_file"
  [ "$output" = "1" ]
  run grep -c "^- resume_next_action: carry on$" "$task_file"
  [ "$output" = "1" ]
  run grep -c "^- resume_state_revision: 1$" "$task_file"
  [ "$output" = "1" ]
}

@test "doc_garden edits the line sed addresses when a capsule carries a carriage return" {
  # The writer resolves a line NUMBER with the shared reader and applies it as a `sed`
  # address. While that reader went through `Path.read_text`, whose universal-newline mode
  # turns a lone CR into `\n`, one stray CR above the field shifted python one line past
  # sed: `--task-status done` exited 0, printed `[OK] Doc-gardening sync complete`, and left
  # `- status: planned` untouched -- a silent no-op WRITE (the task
  # r01 finding 2, reproduced on a real scaffold). A line number is the one thing that
  # cannot tolerate two definitions of a line.
  local task_file="$DOCS_ROOT/task/TASK-craddr-01.md"
  {
    printf '%s\n' \
      '# TASK-craddr-01' \
      '' \
      '- title: CR address fixture' \
      '- objective: the writer and sed count the same lines' \
      '- acceptance_criteria: none' \
      '- non_goals: none' \
      '- affected_modules: docs' \
      '- interfaces_changed: none' \
      '- data_migrations: none' \
      '- test_scope: none' \
      '- risks: none' \
      '- risk_level: low' \
      '- consumes_plan_ref:'
    printf 'prose with a stray\015carriage return\n'
    printf '%s\n' '- status: planned' '- owner: test' '- last_updated: 2020-01-01T00:00:00Z'
  } > "$task_file"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "craddr-01" --task-title "CR address fixture" \
    --task-status done --no-init >/dev/null

  run grep -c '^- status: done$' "$task_file"
  assert_equal "$output" "1"
  # The CR itself is preserved: the fix is that the reader keeps the bytes, not that it
  # normalizes them away.
  run grep -c $'^prose with a stray\015carriage return$' "$task_file"
  assert_equal "$output" "1"
  # Positive control: the same capsule without the CR behaves identically, so the assertion
  # above is about the address and not about the fixture happening to work.
  perl -pi -e 's{\x0d}{ }' "$task_file"
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "craddr-01" --task-title "CR address fixture" \
    --task-status blocked --no-init >/dev/null
  run grep -c '^- status: blocked$' "$task_file"
  assert_equal "$output" "1"
}

@test "doc_garden does not rewrite a fenced example when a carriage return shifts the line count" {
  # The same defect one step worse: with TWO CRs above the field the shifted address landed
  # on a FENCED `- status: EXAMPLE` two lines below the real field, so the maintenance tool
  # filled a quoted template with live data while the real field stayed stale -- which is
  # the exact defect the previous round closed, reproduced against the code that closed it.
  local task_file="$DOCS_ROOT/task/TASK-crfence-01.md"
  {
    printf '%s\n' \
      '# TASK-crfence-01' \
      '' \
      '- title: CR fence fixture' \
      '- objective: a fenced example survives a shifted address' \
      '- acceptance_criteria: none' \
      '- non_goals: none' \
      '- affected_modules: docs' \
      '- interfaces_changed: none' \
      '- data_migrations: none' \
      '- test_scope: none'
    printf 'prose one\015with CR\n'
    printf 'prose two\015with CR\n'
    printf '%s\n' '- risks: none' '- risk_level: low' '- consumes_plan_ref:' '- status: planned' \
      '```' '- status: EXAMPLE' '```' '- owner: test' '- last_updated: 2020-01-01T00:00:00Z'
  } > "$task_file"
  local before="$TEST_WORKSPACE/crfence-before.md"
  cp "$task_file" "$before"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "crfence-01" --task-title "CR fence fixture" \
    --task-status done --no-init >/dev/null

  # The real field moved...
  run grep -c '^- status: done$' "$task_file"
  assert_equal "$output" "1"
  # ...and the quoted example is byte-identical.
  run grep -c '^- status: EXAMPLE$' "$task_file"
  assert_equal "$output" "1"
  # Exactly two lines differ from the original: the status and the timestamp.
  run bash -c "diff '$before' '$task_file' | grep -c '^>'"
  assert_equal "$output" "2"
}

@test "doc_garden targets a column-0 field line, not any line that contains the key" {
  # The writer shares the validator's `^- key:` anchor, and the lookup enforces it with a
  # literal `str.startswith`. Replacing that with `prefix in line` left every test green
  # the lookup then returns the INDENTED
  # line, whose `sed` substitution does not match, so the tool exits 0 and writes nothing.
  local task_file="$DOCS_ROOT/task/TASK-anchor-01.md"
  {
    printf '%s\n' \
      '# TASK-anchor-01' \
      '' \
      '- title: Anchor fixture' \
      '- objective: an indented mention is not the field' \
      '- acceptance_criteria: none' \
      '- non_goals: none' \
      '- affected_modules: docs' \
      '- interfaces_changed: none' \
      '- data_migrations: none' \
      '- test_scope: none' \
      '- risks: none' \
      '- risk_level: low' \
      '- consumes_plan_ref:' \
      '  - status: indented_mention' \
      '- status: planned' \
      '- owner: test' \
      '- last_updated: 2020-01-01T00:00:00Z'
  } > "$task_file"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "anchor-01" --task-title "Anchor fixture" \
    --task-status done --no-init >/dev/null

  run grep -c '^- status: done$' "$task_file"
  assert_equal "$output" "1"
  # The indented mention is untouched: it is not the field, in either direction.
  run grep -c '^  - status: indented_mention$' "$task_file"
  assert_equal "$output" "1"
}

@test "doc_garden writes a task-index row outside a quoted row-format example" {
  # `update_task_index` was fence-blind in BOTH halves -- a `grep -vF` delete and an awk
  # `$0 == section` insert -- while `task_index_row_present` reads the fence-stripped copy.
  # Reproduced end to end: the live row landed INSIDE the quoted example, doc_garden exited
  # 0, and the validator then reported "task-index missing row" for the task it had just
  # written. Same shape as the field writer
  # the previous round fixed, 300 lines below it in the same file.
  local index="$DOCS_ROOT/task/task-index.md"
  cat > "$index" <<'EOF'
# Task Index

Row format (quoted example)

```
## In Progress

- TASK-example-01 | in_progress | Example row
```

## Planned

## In Progress

## Blocked

## Done
EOF
  local before="$TEST_WORKSPACE/index-before.md"
  cp "$index" "$before"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "fencedrow-01" --task-title "Fenced row" \
    --task-status in_progress --no-init >/dev/null

  # The fenced block is byte-identical.
  run bash -c "sed -n '1,10p' '$before' | diff - <(sed -n '1,10p' '$index') >/dev/null && echo same"
  assert_equal "$output" "same"
  # The live row sits under the REAL heading, which is the one the validator walks.
  run bash -c "awk '/^## In Progress\$/{found=NR} END{print found}' '$index'"
  assert_equal "$output" "13"
  run bash -c "grep -n '^- TASK-fencedrow-01 | in_progress | Fenced row\$' '$index' | cut -d: -f1"
  assert_equal "$output" "14"
  # ...and the validator agrees, which is the property that failed before.
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  refute_contains "$output" "task-index missing row for TASK-fencedrow-01"
}

@test "doc_garden writes a decision-index row outside a quoted row-format example" {
  # Same axis, the sibling index. `decision_index_row_present` reads the stripped copy, so a
  # fence-blind delete/insert here writes the live row into a quoted example and the
  # validator reports it missing.
  local index="$DOCS_ROOT/decisions/decision-index.md"
  cat > "$index" <<'EOF'
# Decision Index

Row format (quoted example)

```
## Accepted

- decision-example-01.md | example-01 | task | 2026-01-01 | accepted | TASK-x | Example
```

## Proposed

## Accepted

## Superseded
EOF
  local before="$TEST_WORKSPACE/dindex-before.md"
  cp "$index" "$before"

  "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "fenceddec-01" --decision-title "Fenced dec" \
    --selected-option "Option A" --no-init >/dev/null

  run bash -c "sed -n '1,10p' '$before' | diff - <(sed -n '1,10p' '$index') >/dev/null && echo same"
  assert_equal "$output" "same"
  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  refute_contains "$output" "decision index missing row for decision-fenceddec-01.md"
  # Positive half: the row really is in the file, under the real heading rather than the
  # quoted one.
  run bash -c "grep -n '^- decision-fenceddec-01.md |' '$index' | cut -d: -f1"
  assert_equal "$output" "14"
}

@test "doc_garden refuses to append a field to a capsule that ends inside an unterminated fence" {
  # When no unfenced occurrence exists the writer appends -- and if the document ends inside
  # an unterminated fence the appended line lands inside that block, invisible to the next
  # lookup, so the next run appends again. Reproduced at three runs: `grep -c "^- status:"`
  # went 1 to 4 and the capsule still had no field any reader could see
  # The writer fails loud instead, like
  # every other thing it cannot answer.
  local task_file="$DOCS_ROOT/task/TASK-unterm-01.md"
  cat > "$task_file" <<'EOF'
# TASK-unterm-01

- title: Unterminated fence fixture
```
- status: quoted_example
EOF
  local before
  before="$(cat "$task_file")"

  # --task-title repeats the value already on the line, so the one field that DOES have an
  # unfenced occurrence is rewritten to itself and the capsule is byte-identical either way:
  # what this asserts is the append branch refusing on `status`, not the absence of writes.
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "unterm-01" \
    --task-title "Unterminated fence fixture" --task-status planned --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "ends inside an unterminated fenced block; refusing to append"
  [ "$before" = "$(cat "$task_file")" ]

  # Positive half: close the fence and the same invocation appends exactly once, so the
  # refusal is about the unterminated block and not about the arguments.
  printf '```\n' >> "$task_file"
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "unterm-01" \
    --task-title "Unterminated fence fixture" --task-status planned --no-init >/dev/null
  run grep -c '^- status: planned$' "$task_file"
  assert_equal "$output" "1"
  run grep -c '^- status: quoted_example$' "$task_file"
  assert_equal "$output" "1"
}

@test "doc_garden refuses to edit a capsule when the shared fence reader is unavailable" {
  # The validator's READ path degrades silently to the original document on a strip
  # failure -- deliberate, because blanking every field is worse. A WRITER must not make
  # the same trade: degrading to a fence-blind lookup would put live data back into quoted
  # templates, which is the defect this round closed, and appending a duplicate field
  # would corrupt the capsule a different way. So the writer fails loud instead.
  local fake_scripts="$TEST_WORKSPACE/fake-scripts"
  mkdir -p "$fake_scripts"
  cp "$SCRIPTS_DIR/doc_garden.sh" "$fake_scripts/"
  cp "$SCRIPTS_DIR/codeguide_paths.sh" "$fake_scripts/"
  cp "$SCRIPTS_DIR/codeguide_paths.py" "$fake_scripts/"
  cp "$SCRIPTS_DIR/codeguide_doc_lines.sh" "$fake_scripts/"
  # Deliberately no shadow_doc_parse.py beside it: the adapter is present and the RULE it
  # adapts is not, which is the failure this asserts. Omitting the adapter too would only
  # prove that bash cannot source a missing file.

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "loud-01" --task-title "Loud failure" \
    --task-status planned --no-init >/dev/null
  local task_file="$DOCS_ROOT/task/TASK-loud-01.md"
  local before
  before="$(cat "$task_file")"

  run "$fake_scripts/doc_garden.sh" "$TEST_PROJECT" --task-id "loud-01" \
    --task-title "Rewritten by a blind writer" --task-status done --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "with the shared fence reader; refusing to edit"
  [ "$before" = "$(cat "$task_file")" ]

  # ...and it must refuse for the same reason no matter WHERE the caller is standing.
  # `python3 -` puts the caller's working directory at sys.path[0], so before the adapter
  # stripped it, running this same fixture from a directory that happens to hold a
  # `shadow_doc_parse.py` imported THAT one and the refusal never fired — which is how it
  # was found: `check_all.sh` invoked from `scripts/` turned this test green for the wrong
  # reason. A writer whose fence rule depends on the user's `cd` is one document with two
  # answers decided by something incidental, which is the defect this adapter exists to end.
  local decoy_cwd="$TEST_WORKSPACE/decoy-cwd"
  mkdir -p "$decoy_cwd"
  cp "$SCRIPTS_DIR/shadow_doc_parse.py" "$decoy_cwd/"
  run bash -c 'cd "$1" && "$2" "$3" --task-id "loud-01" \
    --task-title "Rewritten from a decoy cwd" --task-status done --no-init' \
    _ "$decoy_cwd" "$fake_scripts/doc_garden.sh" "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  assert_contains "$output" "with the shared fence reader; refusing to edit"
  [ "$before" = "$(cat "$task_file")" ]

  # Positive half: the SAME invocation through the real scripts directory succeeds and
  # writes, so the refusal above is about the missing reader and not about the arguments.
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "loud-01" \
    --task-title "Rewritten by a blind writer" --task-status done --no-init
  [ "$status" -eq 0 ]
  run grep -c "^- status: done$" "$task_file"
  [ "$output" = "1" ]
}

@test "doc_garden refuses to append an index ROW into an unterminated fence" {
  # The unterminated-fence guard was fitted to the FIELD writer and to NEITHER row writer,
  # so the exact defect the field fixture above exists for was alive in the row half -- and
  # the row half is the unbounded one, because the fence-aware delete on the next run cannot
  # see the row a fence-blind append wrote. Reproduced before this guard existed: three
  # `doc_garden.sh` runs took a decision-index from 10 lines to 31 with `^## Accepted` going
  # 1 to 4, three live rows and three duplicate section blocks INSIDE the fence, exit 0 each
  # time, and `validate_docs.sh` then reported all three rows missing
  #
  local index="$DOCS_ROOT/decisions/decision-index.md"
  printf '# Decision Index\n\nRow format (quoted example):\n\n```\n## Proposed\n\n## Accepted\n\n## Superseded\n' > "$index"
  local before
  before="$(cat "$index")"

  run "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "grow-d01" \
    --decision-title "Grow" --selected-option "A" --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "ends inside an unterminated fenced block; refusing to append"
  [ "$before" = "$(cat "$index")" ]

  # The growth half, which is what makes this worse than the field case: repeating the
  # refused command must not accumulate anything.
  run "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "grow-d02" \
    --decision-title "Grow" --selected-option "A" --no-init
  [ "$status" -ne 0 ]
  run "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "grow-d03" \
    --decision-title "Grow" --selected-option "A" --no-init
  [ "$status" -ne 0 ]
  [ "$before" = "$(cat "$index")" ]
  run grep -c '^## Accepted' "$index"
  assert_equal "$output" "1"

  # Positive half: close the fence and the same invocation lands the row under the REAL
  # heading, so the refusal is about the unterminated block and not about the arguments.
  # Two `^## Accepted` lines exist by construction here -- the quoted one and the real one --
  # and the row must sit under the real one, at the line after it.
  printf '```\n\n## Proposed\n\n## Accepted\n\n## Superseded\n' >> "$index"
  "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "grow-d01" \
    --decision-title "Grow" --selected-option "A" --no-init >/dev/null
  run grep -c '^- decision-grow-d01.md |' "$index"
  assert_equal "$output" "1"
  run grep -c '^## Accepted' "$index"
  assert_equal "$output" "2"
  run bash -c "grep -n '^## Accepted' '$index' | tail -n 1 | cut -d: -f1"
  local real_heading="$output"
  run bash -c "grep -n '^- decision-grow-d01.md |' '$index' | cut -d: -f1"
  assert_equal "$output" "$((real_heading + 1))"
}

@test "doc_garden refuses to append a task-index ROW into an unterminated fence" {
  # The task-index half of the same defect, and its own distinct consequence: with the row
  # written inside the fence, a later STATUS CHANGE appended a SECOND live row instead of
  # replacing the first (`- TASK-grow-t01 | planned |` and `- TASK-grow-t01 | done |` both
  # live), because the fence-aware delete cannot see what the fence-blind append wrote.
  local index="$DOCS_ROOT/task/task-index.md"
  printf '# Task Index\n\nRow format (quoted example):\n\n```\n## Planned\n\n## In Progress\n\n## Blocked\n\n## Done\n' > "$index"
  local before
  before="$(cat "$index")"

  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id "grow-t01" \
    --task-title "Grow T" --task-status planned --no-init
  [ "$status" -ne 0 ]
  assert_contains "$output" "ends inside an unterminated fenced block; refusing to append"
  [ "$before" = "$(cat "$index")" ]

  # Positive half, and the duplicate-row property in one: close the fence, write the row,
  # then CHANGE the status -- exactly one live row survives, under the new section.
  printf '```\n\n## Planned\n\n## In Progress\n\n## Blocked\n\n## Done\n' >> "$index"
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "grow-t01" \
    --task-title "Grow T" --task-status planned --no-init >/dev/null
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "grow-t01" \
    --task-title "Grow T" --task-status done --no-init >/dev/null
  run grep -c '^- TASK-grow-t01 |' "$index"
  assert_equal "$output" "1"
  run grep -c '^- TASK-grow-t01 | done |' "$index"
  assert_equal "$output" "1"
}

@test "ensure_decision_index_sections creates the REAL heading when a fence quotes one" {
  # `ensure_decision_index_sections` reverted to a fence-blind `grep -F` survives the whole
  # suite (r02 residual_risk), and it is the probe whose failure compounds: satisfied by a
  # QUOTED heading, it never creates the real one, so every later row is appended at end of
  # file instead of under a section. The fence here is TERMINATED, so the refusal above
  # cannot be what makes this pass.
  local index="$DOCS_ROOT/decisions/decision-index.md"
  printf '# Decision Index\n\nSection layout (quoted example):\n\n```\n## Proposed\n\n## Accepted\n\n## Superseded\n```\n' > "$index"

  "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "realsec-01" \
    --decision-title "Real section" --selected-option "A" --no-init >/dev/null

  # Three real headings created BELOW the quoted block, and the quoted block untouched.
  run grep -c '^## Accepted' "$index"
  assert_equal "$output" "2"
  run bash -c "grep -n '^## Accepted' '$index' | tail -n 1 | cut -d: -f1"
  local real_heading="$output"
  run bash -c "grep -n '^- decision-realsec-01.md |' '$index' | cut -d: -f1"
  assert_equal "$output" "$((real_heading + 1))"

  # And a second run adds no further headings -- the probe must SEE the one it created.
  "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "realsec-02" \
    --decision-title "Real section two" --selected-option "A" --no-init >/dev/null
  run grep -c '^## Accepted' "$index"
  assert_equal "$output" "2"
}

@test "doc_garden inserts an index row under the FIRST unfenced section heading" {
  # `require_first_unfenced_line` returning the LAST unfenced match instead of the first
  # survives 191 tests (r02 residual_risk), because every other fixture in the suite has a
  # single unfenced heading, where first and last coincide. This is the fixture where they
  # do not.
  local index="$DOCS_ROOT/task/task-index.md"
  printf '# Task Index\n\n## In Progress\n\n## Planned\n\n## Blocked\n\n## Done\n\n## In Progress\n\n' > "$index"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "firstsec-01" \
    --task-title "First section" --task-status in_progress --no-init >/dev/null

  # The row sits under the heading at line 3, not the duplicate at line 11.
  run bash -c "grep -n '^- TASK-firstsec-01 |' '$index' | cut -d: -f1"
  assert_equal "$output" "4"
}

@test "doc_garden deletes EVERY stale index row, not just the first" {
  # `delete_lines_by_number` deleting only the first stale row survives 146 tests (r02
  # residual_risk): it is the property the old `grep -vF` had and nothing asserted after the
  # move to line numbers. A duplicate row is exactly what a half-delete leaves behind.
  local index="$DOCS_ROOT/task/task-index.md"
  printf '# Task Index\n\n## Planned\n- TASK-dupe-01 | planned | Stale one\n\n## In Progress\n- TASK-dupe-01 | in_progress | Stale two\n\n## Blocked\n\n## Done\n' > "$index"

  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "dupe-01" \
    --task-title "Deduped" --task-status done --no-init >/dev/null

  run grep -c '^- TASK-dupe-01 |' "$index"
  assert_equal "$output" "1"
  run grep -c '^- TASK-dupe-01 | done | Deduped$' "$index"
  assert_equal "$output" "1"

  # Positive half: a row for a DIFFERENT task is not collateral damage.
  printf -- '- TASK-keepme-01 | planned | Keep me\n' >> "$index"
  "$DOC_GARDEN" "$TEST_PROJECT" --task-id "dupe-01" \
    --task-title "Deduped" --task-status planned --no-init >/dev/null
  run grep -c '^- TASK-keepme-01 |' "$index"
  assert_equal "$output" "1"
}
