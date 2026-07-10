#!/usr/bin/env bats

load codeguide_helper

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

@test "run_external_plan_reviews requires passing preflight before invoking reviewers" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-gate-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-gate-v1.0

- task_id: ext-review-gate
- plan_version: v1.0
- objective: verify preflight gate before external review
- scope: external review safety gate
- assumptions: reviewers must not run before preflight passes
- risks: token waste and unapproved external side effects
- acceptance_signals: wrapper blocks before reviewer invocation
- stop_conditions: preflight block is surfaced
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Try to run reviewers without a passing preflight.
2. Confirm no external CLI is invoked.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/gemini-called"
exit 99'
  # (claude mock replaced by agy)
  # true #  '#!/usr/bin/env bash
# touch "${TEST_WORKSPACE}/claude-called"
# exit 99'
  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/codex-called"
exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-gate" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01"

  [ "$status" -ne 0 ]
  [[ "$output" == *"--risk-preflight-status is required"* ]]
  run test ! -e "$TEST_WORKSPACE/gemini-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-called"
  [ "$status" -eq 0 ]

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-gate" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01" \
    --risk-preflight-status "pass"

  [ "$status" -ne 0 ]
  [[ "$output" == *"External CLI review requires explicit user approval provenance"* ]]
  run test ! -e "$TEST_WORKSPACE/gemini-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-called"
  [ "$status" -eq 0 ]

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-gate" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01" \
    --risk-preflight-status "approval_required"

  [ "$status" -ne 0 ]
  [[ "$output" == *"external review is stopped before orchestration/delegation"* ]]
  run test ! -e "$TEST_WORKSPACE/gemini-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-called"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews retries malformed output and writes reports without mutating the plan" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-01-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-01-v1.0

- task_id: ext-review-01
- plan_version: v1.0
- objective: validate external review automation
- scope: docs-only review pipeline
- assumptions: mock CLIs are available with api_key="sk-12345678901234567890" and OPENAI_API_KEY=sk-proj-12345678901234567890
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

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
count_file="${TEST_WORKSPACE}/gemini-count"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf "%s" "$count" > "$count_file"
printf "%s\n" "$@" > "${TEST_WORKSPACE}/gemini-args.log"
if [[ "$count" -eq 1 ]]; then
  cat <<EOF
- verdict: accept
- summary: saved to /tmp/evil-plan.md
- strengths: This response is otherwise parseable.
- risks: It claims an unsupported save location.
- requested_changes: Reject unsupported save-location claims.
EOF
else
  cat <<EOF
- verdict: revise
- summary: The sequencing is mostly sound, but the review contract should be stricter about malformed output handling.
- strengths: It clearly stops before auto-versioning the plan.
- risks: Retry handling and malformed output normalization could still drift if token="ghp_12345678901234567890" or OPENAI_API_KEY=sk-proj-12345678901234567890 is echoed.
- requested_changes: Keep the report parser strict and summarize reviewer failures in the final wrapper output.
EOF
fi'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-args.log"
cat >> "${TEST_WORKSPACE}/claude-args.log"
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
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-01" \
    --approved-next-step "run external review ext-review-01 v1.0 r01"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK] evaluator=agy"* ]]
  [[ "$output" == *"[OK] evaluator=claude"* ]]
  [[ "$output" == *"No new plan version was created automatically."* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-agy-current-r01.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-claude-current-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: standard" "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-agy-current-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- primary_author_tool: codex" "$DOCS_ROOT/orchestration/ext-review-01/ORCH.md"
  [ "$status" -eq 0 ]
  run grep "^- review_mode: external_cli" "$DOCS_ROOT/orchestration/ext-review-01/ORCH.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_preflight_status: approved" "$DOCS_ROOT/orchestration/ext-review-01/ORCH.md"
  [ "$status" -eq 0 ]
  run grep "^- approval_required: true" "$DOCS_ROOT/orchestration/ext-review-01/ORCH.md"
  [ "$status" -eq 0 ]
  run grep "^- approval_ref: user-approval-ext-review-01" "$DOCS_ROOT/orchestration/ext-review-01/ORCH.md"
  [ "$status" -eq 0 ]
  run grep "^- reviewer_agents: external-cli:agy:current,claude:current" "$DOCS_ROOT/orchestration/ext-review-01/ORCH.md"
  [ "$status" -eq 0 ]

  local after_plan
  after_plan="$(cat "$plan_file")"
  [ "$before_plan" = "$after_plan" ]

  run grep -E -- '(^|[[:space:]])-m([[:space:]]|$)' "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -ne 0 ]
  run grep -E -- '(^|[[:space:]])--model([[:space:]]|$)' "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -ne 0 ]
  run grep -- "--include-directories" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -ne 0 ]
  run grep -- "--add-dir" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep -- "$TEST_PROJECT" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--tools" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--bare" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -ne 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-01" "v1.0" "r01")"
  [ -n "$handoff_dir" ]
  [[ "$handoff_dir" =~ /[A-Z][a-z]{2}[0-9]{2}_[0-9]{4}/ext-review-01/v1\.0/r01$ ]]
  run test -f "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/agy-current.response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/agy-current.retry-request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/agy-current.retry-response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude-current.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude-current.response.md"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/claude-current.stderr.md"
  [ "$status" -eq 0 ]
  run grep "## Why" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep "## What" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep "## How" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep "## Where" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep "## Verify" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep "## Payload" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep "### Plan under review" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep "# PLAN-ext-review-01-v1.0" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep "malformed first response" "$handoff_dir/agy-current.response.md"
  [ "$status" -ne 0 ]
  run grep "/tmp/evil-plan.md" "$handoff_dir/agy-current.response.md"
  [ "$status" -eq 0 ]
  run grep "unsupported save-location claim" "$handoff_dir/agy-current.stderr.md"
  [ "$status" -eq 0 ]
  run grep "review contract should be stricter" "$handoff_dir/agy-current.retry-response.md"
  [ "$status" -eq 0 ]
  run grep -F "[REDACTED_SECRET]" "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run grep -F "[REDACTED_SECRET]" "$handoff_dir/agy-current.retry-response.md"
  [ "$status" -eq 0 ]
  run grep "sk-12345678901234567890" "$handoff_dir/agy-current.request.md"
  [ "$status" -ne 0 ]
  run grep "sk-proj-12345678901234567890" "$handoff_dir/agy-current.request.md"
  [ "$status" -ne 0 ]
  run grep "ghp_12345678901234567890" "$handoff_dir/agy-current.retry-response.md"
  [ "$status" -ne 0 ]
  run grep "sk-proj-12345678901234567890" "$handoff_dir/agy-current.retry-response.md"
  [ "$status" -ne 0 ]
  run grep "$handoff_dir/agy-current.retry-request.md" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/agy-current.retry-command-response.raw.md" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep "command_response_path: $handoff_dir/agy-current.retry-command-response.raw.md" "$handoff_dir/agy-current.retry-request.md"
  [ "$status" -eq 0 ]
  run grep "sanitized_response_file: $handoff_dir/agy-current.retry-response.md" "$handoff_dir/agy-current.retry-request.md"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/agy-current.retry-command-response.raw.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/agy-current.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  local agy_retry_hash
  agy_retry_hash="$(sha256_file_ref "$handoff_dir/agy-current.retry-response.md")"
  run grep "artifact_kind: external_cli_review_response_provenance" "$handoff_dir/agy-current.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "generated_by: run_external_plan_reviews.sh" "$handoff_dir/agy-current.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "response_file: $handoff_dir/agy-current.retry-response.md" "$handoff_dir/agy-current.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "response_sha256: $agy_retry_hash" "$handoff_dir/agy-current.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "command_response_path: $handoff_dir/agy-current.retry-command-response.raw.md" "$handoff_dir/agy-current.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "raw_capture_deleted: true" "$handoff_dir/agy-current.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/claude-current.command-response.raw.md" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/claude-current.command-response.raw.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude-current.response.provenance.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews can target a selected reviewer only" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-07-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-07-v1.0

- task_id: ext-review-07
- plan_version: v1.0
- objective: validate selected reviewer routing
- scope: external review runner options
- assumptions: operator may need to rerun only one failed reviewer
- risks: reruns could resend context to unrelated external tools
- acceptance_signals: only the requested reviewer is invoked
- stop_conditions: targeted review report is written
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Select one reviewer.
2. Run the wrapper.
3. Confirm unrelated reviewers were not invoked.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/gemini-called"
echo "gemini should not be called for selected reviewer claude" >&2
exit 99'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-args.log"
cat >> "${TEST_WORKSPACE}/claude-args.log"
cat <<EOF
- verdict: accept
- summary: The selected reviewer path invokes only Claude and still writes the standard report artifacts.
- strengths: It preserves the normal request, response, report, and provenance flow.
- risks: Reviewer selection could hide missing multi-review coverage if operators use it for initial review rounds.
- requested_changes: Use targeted reviewer selection only for focused reruns or explicitly scoped review rounds.
EOF'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/codex-called"
echo "codex should not be called for primary=codex" >&2
exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-07" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r07" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-07" \
    --approved-next-step "run targeted external review ext-review-07 v1.0 r07" \
    --reviewer "claude"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK] evaluator=claude"* ]]
  [[ "$output" != *"evaluator=gemini"* ]]
  [[ "$output" != *"evaluator=codex"* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-07-v1.0-review-claude-current-r07.md"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/gemini-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/codex-called"
  [ "$status" -eq 0 ]
  run grep "^- reviewer_agents: external-cli:claude:current" "$DOCS_ROOT/orchestration/ext-review-07/ORCH.md"
  [ "$status" -eq 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-07" "v1.0" "r07")"
  [ -n "$handoff_dir" ]
  run test -f "$handoff_dir/claude-current.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude-current.response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude-current.response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/claude-current.command-response.raw.md" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews supports last-resort manual handoff and response ingest without invoking CLIs" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-manual-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-manual-v1.0

- task_id: ext-review-manual
- plan_version: v1.0
- objective: validate manual fallback for platform-blocked external review
- scope: external review wrapper fallback
- assumptions: direct external CLI invocation remains the primary path
- risks: manual fallback could accidentally become the default path
- acceptance_signals: manual mode writes handoff commands without invoking external CLIs; ingest mode writes reports from existing raw responses
- stop_conditions: reports and provenance are generated without CLI calls
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Prepare manual handoff files only.
2. Simulate user-run raw responses.
3. Ingest responses into reports and provenance.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/gemini-called"
exit 99'
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-called"
exit 99'
  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/codex-called"
exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-manual" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-manual" \
    --approved-next-step "run external review ext-review-manual v1.0 r01" \
    --manual-handoff-only

  [ "$status" -eq 0 ]
  [[ "$output" == *"[MANUAL] evaluator=agy"* ]]
  [[ "$output" == *"[MANUAL] evaluator=claude"* ]]
  [[ "$output" == *"manual_handoff_only=true"* ]]
  [[ "$output" == *"--ingest-manual-responses"* ]]
  run test ! -e "$TEST_WORKSPACE/gemini-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/codex-called"
  [ "$status" -eq 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-manual" "v1.0" "r01")"
  [ -n "$handoff_dir" ]
  run test -f "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude-current.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/agy-current.manual-command.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude-current.manual-command.md"
  [ "$status" -eq 0 ]
  run grep "last-resort fallback" "$handoff_dir/agy-current.manual-command.md"
  [ "$status" -eq 0 ]
  run grep "user-operated handoff" "$handoff_dir/claude-current.manual-command.md"
  [ "$status" -eq 0 ]
  run grep "cat.*claude-current.request.md" "$handoff_dir/claude-current.manual-command.md"
  [ "$status" -eq 0 ]

  cat > "$handoff_dir/agy-current.command-response.raw.md" <<'EOF'
- verdict: accept
- summary: Gemini manual raw response accepts the bounded external review fallback contract.
- strengths: It preserves direct invocation as primary while keeping a recoverable user-operated fallback.
- risks: Operators could still overuse manual mode if platform permission settings are not fixed.
- requested_changes: Keep manual handoff documented as last-resort only.
EOF
  cat > "$handoff_dir/claude-current.command-response.raw.md" <<'EOF'
- verdict: revise
- summary: Claude manual raw response confirms ingest can normalize existing responses without invoking the CLI.
- strengths: It produces the same report and provenance artifacts after user-operated execution.
- risks: Manual responses still rely on local file integrity and operator discipline.
- requested_changes: Prefer permission-mode repair before falling back to manual execution.
EOF

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-manual" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-manual" \
    --approved-next-step "run external review ext-review-manual v1.0 r01" \
    --ingest-manual-responses

  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK] evaluator=agy"* ]]
  [[ "$output" == *"[OK] evaluator=claude"* ]]
  run test ! -e "$TEST_WORKSPACE/gemini-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-called"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-manual-v1.0-review-agy-current-r01.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-manual-v1.0-review-claude-current-r01.md"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/agy-current.command-response.raw.md"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/claude-current.command-response.raw.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/agy-current.response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "raw_capture_deleted: true" "$handoff_dir/agy-current.response.provenance.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews supports adversarial reviewer with best-effort success" {
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

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
echo "agy should not be called for primary=agy" >&2
exit 99'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-args.log"
cat >> "${TEST_WORKSPACE}/claude-args.log"
echo "mock claude failure with token=sk-proj-12345678901234567890" >&2
exit 7'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/codex-args.log"
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ -z "$output_file" ]]; then
  output_file="/dev/stdout"
fi
cat > "$output_file" <<EOF
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
    --primary-tool "agy" \
    --review-round "r02" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-02" \
    --approved-next-step "run external review ext-review-02 v1.0 r02" \
    --allow-partial-review \
    --adversarial-evaluator "codex"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[FAIL] evaluator=claude"* ]]
  [[ "$output" == *"[OK] evaluator=codex style=adversarial"* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-current-r02.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-current-r02.md"
  [ "$status" -eq 0 ]
  run grep "^- objection:" "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-current-r02.md"
  [ "$status" -eq 0 ]
  run grep -- "--sandbox" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "read-only" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--ephemeral" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--output-last-message" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -F -- "--cd" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "$TEST_PROJECT" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-02" "v1.0" "r02")"
  [ -n "$handoff_dir" ]
  [[ "$handoff_dir" =~ /[A-Z][a-z]{2}[0-9]{2}_[0-9]{4}/ext-review-02/v1\.0/r02$ ]]
  run test -f "$handoff_dir/codex-current.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/codex-current.response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude-current.stderr.md"
  [ "$status" -eq 0 ]
  run grep "# PLAN-ext-review-02-v1.0" "$handoff_dir/codex-current.request.md"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/codex-current.request.md" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/codex-current.command-response.raw.md" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/codex-current.command-response.raw.md"
  [ "$status" -eq 0 ]
  run grep -F "[REDACTED_SECRET]" "$handoff_dir/claude-current.stderr.md"
  [ "$status" -eq 0 ]
  run grep "sk-proj-12345678901234567890" "$handoff_dir/claude-current.stderr.md"
  [ "$status" -ne 0 ]
}

@test "run_external_plan_reviews auto-selects adversarial reviewer for high-risk task and supports primary claude success path" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "ext-review-04" \
    --task-title "High risk ext review" \
    --risk-level "high" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-04" \
    --approved-next-step "run external review ext-review-04 v1.0 r04" \
    --primary-author-tool "antigravity" \
    --review-mode "external_cli" \
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

  # (claude mock replaced by agy)
  # true #  '#!/usr/bin/env bash
# echo "claude should not be called for primary=claude" >&2
# exit 99'

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/gemini-args.log"
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
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ -z "$output_file" ]]; then
  output_file="/dev/stdout"
fi
cat > "$output_file" <<EOF
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
    --review-round "r04" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-04" \
    --approved-next-step "run external review ext-review-04 v1.0 r04"

  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-selecting adversarial evaluator=agy:current"* ]]
  [[ "$output" == *"[OK] evaluator=agy style=adversarial"* ]]
  [[ "$output" == *"[OK] evaluator=codex style=standard"* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-agy-current-r04.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-agy-current-r04.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-codex-current-r04.md"
  [ "$status" -eq 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-04" "v1.0" "r04")"
  [ -n "$handoff_dir" ]
  [[ "$handoff_dir" =~ /[A-Z][a-z]{2}[0-9]{2}_[0-9]{4}/ext-review-04/v1\.0/r04$ ]]
  run test -f "$handoff_dir/agy-current.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/agy-current.response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/codex-current.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/codex-current.response.md"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/agy-current.command-response.raw.md" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/codex-current.command-response.raw.md" "$TEST_WORKSPACE/codex-args.log"
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

  cat > "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-agy-current-r03.md" <<'EOF'
# PLAN-ext-review-03-v1.0 review (agy)

- task_id: ext-review-03
- plan_version: v1.0
- evaluator: agy
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

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
echo "gemini failure" >&2
exit 3'

  # (claude mock replaced by agy)
  # true #  '#!/usr/bin/env bash
# echo "claude should not be called for primary=claude" >&2
# exit 99'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
echo "codex failure" >&2
exit 4'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-03" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --review-round "r03" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-03" \
    --approved-next-step "run external review ext-review-03 v1.0 r03"

  [ "$status" -ne 0 ]
  [[ "$output" == *"[FAIL] evaluator=agy"* ]]
  [[ "$output" == *"[FAIL] evaluator=codex"* ]]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-agy-current-r03.md"
  [ "$status" -eq 0 ]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-codex-current-r03.md"
  [ "$status" -eq 0 ]
  run find "$DOCS_ROOT/report" -maxdepth 1 -type f -name 'PLAN-ext-review-03-v1.0-review-agy-current-r03.md.stale-*'
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews exits non-zero when required adversarial reviewer fails even if another reviewer succeeds" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "ext-review-05" \
    --task-title "Adversarial failure test" \
    --risk-level "high" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-05" \
    --approved-next-step "run external review ext-review-05 v1.0 r05" \
    --primary-author-tool "antigravity" \
    --review-mode "external_cli" \
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

  # (claude mock replaced by agy)
  # true #  '#!/usr/bin/env bash
# echo "claude should not be called for primary=claude" >&2
# exit 99'

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
echo "forced adversarial failure" >&2
exit 8'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ -z "$output_file" ]]; then
  output_file="/dev/stdout"
fi
cat > "$output_file" <<EOF
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
    --review-round "r05" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-05" \
    --approved-next-step "run external review ext-review-05 v1.0 r05"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Required adversarial review did not complete successfully"* ]]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-05-v1.0-review-codex-current-r05.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews treats empty codex final message as failure" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-review-06-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-review-06-v1.0

- task_id: ext-review-06
- plan_version: v1.0
- objective: verify codex empty final-message handling
- scope: external ping-pong reviews
- assumptions: codex can exit zero without writing final message
- risks: runtime logs could be mistaken for model response
- acceptance_signals: wrapper exits non-zero
- stop_conditions: empty final message is surfaced
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Run reviewers.
2. Let codex exit zero without writing --output-last-message.
3. Expect failure.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
echo "agy should not be called for primary=agy" >&2
exit 99'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
cat >/dev/null
cat <<EOF
- verdict: accept
- summary: Mock Claude accepts the review packet.
- strengths: none in particular.
- risks: none.
- requested_changes: none.
EOF'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/codex-args.log"
echo "codex runtime log only"
exit 0'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-06" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --review-round "r06" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-06" \
    --approved-next-step "run external review ext-review-06 v1.0 r06"

  [ "$status" -ne 0 ]
  [[ "$output" == *"[FAIL] evaluator=codex"* ]]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-review-06-v1.0-review-codex-current-r06.md"
  [ "$status" -eq 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-06" "v1.0" "r06")"
  [ -n "$handoff_dir" ]
  run grep "codex final message file was empty" "$handoff_dir/codex-current.stderr.md"
  [ "$status" -eq 0 ]
  run grep "codex runtime log only" "$handoff_dir/codex-current.stderr.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews stops on agy quota exhaustion and asks for user model switch in planning phase" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-fallback-plan-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-fallback-plan-v1.0

- task_id: ext-fallback-plan
- plan_version: v1.0
- objective: test runner-neutral quota stop
- scope: external review
- assumptions: gemini exhausted
- risks: wrapper auto-switches model without user control
- acceptance_signals: wrapper stops with model-switch guidance
- stop_conditions: no fallback CLI is invoked
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Test quota stop.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
  printf "%s\n" "$@" > "${TEST_WORKSPACE}/agy-calls.log"
  echo "Error 429: resource_exhausted rate limit exceeded" >&2
  exit 1'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
  touch "${TEST_WORKSPACE}/claude-calls.log"
  echo "claude should not be auto-invoked after agy quota exhaustion" >&2
  exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-fallback-plan" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --primary-model "claude-sonnet-4.6" \
    --reviewer "agy-gemini-3.5-flash-medium" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-fallback-plan" \
    --approved-next-step "run external review ext-fallback-plan" \
    --task-phase "planning"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Quota exhausted for route 'agy:gemini-3.5-flash-medium' (quota_group=agy-gemini-shared)"* ]]
  [[ "$output" == *"Switch the globally selected model in runner 'agy'"* ]]
  [[ "$output" == *"Do not auto-edit runner settings"* ]]

  run grep -- "--add-dir" "$TEST_WORKSPACE/agy-calls.log"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/agy-settings.json"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-calls.log"
  [ "$status" -eq 0 ]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-fallback-plan-v1.0-review-agy-gemini-3.5-flash-medium-r01.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews stops on agy quota exhaustion and asks for user model switch in code phase" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-fallback-code-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-fallback-code-v1.0

- task_id: ext-fallback-code
- plan_version: v1.0
- objective: test code-phase quota stop
- scope: external review
- assumptions: gemini exhausted
- risks: wrapper auto-switches model without user control
- acceptance_signals: wrapper stops with model-switch guidance
- stop_conditions: no fallback CLI is invoked
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Test quota stop.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
  printf "%s\n" "$@" > "${TEST_WORKSPACE}/agy-calls-code.log"
  echo "Error 429: resource_exhausted rate limit exceeded" >&2
  exit 1'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
  touch "${TEST_WORKSPACE}/claude-calls-code.log"
  echo "claude should not be auto-invoked after agy quota exhaustion" >&2
  exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-fallback-code" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --primary-model "claude-opus-4.8" \
    --reviewer "agy-gemini-3.5-flash-medium" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-fallback-code" \
    --approved-next-step "run external review ext-fallback-code" \
    --task-phase "code"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Quota exhausted for route 'agy:gemini-3.5-flash-medium' (quota_group=agy-gemini-shared)"* ]]
  [[ "$output" == *"Switch the globally selected model in runner 'agy'"* ]]
  [[ "$output" == *"Do not auto-edit runner settings"* ]]

  run grep -- "--add-dir" "$TEST_WORKSPACE/agy-calls-code.log"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/agy-settings-code.json"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-calls-code.log"
  [ "$status" -eq 0 ]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-fallback-code-v1.0-review-agy-gemini-3.5-flash-medium-r01.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews direct Claude quota exhaustion fails closed without explicit fallback" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-fallback-fail-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-fallback-fail-v1.0

- task_id: ext-fallback-fail
- plan_version: v1.0
- objective: test direct Claude fail-closed behavior
- scope: external review
- assumptions: direct subscription exhausted
- risks: implicit agy fallback happens
- acceptance_signals: script fails
- stop_conditions: script exits
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Test failure.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
  printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-calls-fail.log"
  echo "Error 429: resource_exhausted rate limit exceeded" >&2
  exit 1'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-fallback-fail" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --primary-model "agy-gemini-3.5-flash-medium" \
    --reviewer "claude-opus-4.8" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-fallback-fail" \
    --approved-next-step "run external review ext-fallback-fail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Quota exhausted for route 'claude:opus-4.8' (quota_group=claude-direct-subscription)"* ]]
  [[ "$output" == *"Switch the globally selected model in runner 'claude'"* ]]
  [[ "$output" != *"Registry fallback succeeded"* ]]
  run grep -E -- '(^|[[:space:]])--model([[:space:]]|$)' "$TEST_WORKSPACE/claude-calls-fail.log"
  [ "$status" -eq 0 ]
  run grep -- "opus-4.8" "$TEST_WORKSPACE/claude-calls-fail.log"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews sends Claude request on stdin and passes explicit registry model" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-claude-stdin-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-claude-stdin-v1.0

- task_id: ext-claude-stdin
- plan_version: v1.0
- objective: verify Claude stdin request contract
- scope: external review
- assumptions: Claude runner receives request body on stdin
- risks: file-read prompt fails when tools are disabled
- acceptance_signals: mock Claude sees the plan payload on stdin
- stop_conditions: no stdin payload
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Test Claude stdin.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-stdin-args.log"
cat > "${TEST_WORKSPACE}/claude-stdin-payload.md"
cat <<EOF
- verdict: accept
- summary: Mock Claude accepted the stdin-delivered review packet.
- strengths: The request payload arrived without file-reading tools.
- risks: None.
- requested_changes: None.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-claude-stdin" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --reviewer "claude-opus-4.8" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-claude-stdin" \
    --approved-next-step "run external review ext-claude-stdin"

  [ "$status" -eq 0 ]
  run grep -- "--model" "$TEST_WORKSPACE/claude-stdin-args.log"
  [ "$status" -eq 0 ]
  run grep -- "opus-4.8" "$TEST_WORKSPACE/claude-stdin-args.log"
  [ "$status" -eq 0 ]
  run grep -- "PLAN-ext-claude-stdin-v1.0" "$TEST_WORKSPACE/claude-stdin-payload.md"
  [ "$status" -eq 0 ]
  run grep -- "Review only the Markdown request provided on stdin" "$TEST_WORKSPACE/claude-stdin-payload.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-claude-stdin-v1.0-review-claude-opus-4.8-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- evaluator_model_selection: cli_flag" "$DOCS_ROOT/report/PLAN-ext-claude-stdin-v1.0-review-claude-opus-4.8-r01.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews passes explicit Codex registry model" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-codex-model-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-codex-model-v1.0

- task_id: ext-codex-model
- plan_version: v1.0
- objective: verify explicit Codex model routing
- scope: external review
- assumptions: registered Codex models use the documented per-call model flag
- risks: explicit route silently uses the globally configured model
- acceptance_signals: mock Codex receives gpt-5.6-sol
- stop_conditions: model flag is absent
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Run an explicit Codex reviewer route.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/codex-model-args.log"
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
cat > "$output_file" <<EOF
- verdict: accept
- summary: Mock Codex accepted the explicit GPT-5.6 Sol route.
- strengths: The registry model reached the CLI.
- risks: None.
- requested_changes: None.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-codex-model" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --primary-model "agy-current" \
    --reviewer "codex-5.6-sol" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-codex-model" \
    --approved-next-step "run external review ext-codex-model"

  [ "$status" -eq 0 ]
  run grep -- "--model" "$TEST_WORKSPACE/codex-model-args.log"
  [ "$status" -eq 0 ]
  run grep -- "gpt-5.6-sol" "$TEST_WORKSPACE/codex-model-args.log"
  [ "$status" -eq 0 ]
  run grep "^- evaluator_model_selection: cli_flag" "$DOCS_ROOT/report/PLAN-ext-codex-model-v1.0-review-codex-gpt-5.6-sol-r01.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews stops on Claude model unavailable before parser retry" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-claude-model-blocked-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-claude-model-blocked-v1.0

- task_id: ext-claude-model-blocked
- plan_version: v1.0
- objective: classify unavailable Claude model separately from malformed response
- scope: external review
- assumptions: model access errors are not parser retry candidates
- risks: wrapper reports missing fields instead of access blocker
- acceptance_signals: model_unavailable_or_access_blocked blocker is reported
- stop_conditions: retry is attempted
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Test model blocker.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "There'\''s an issue with the selected model (opus-4.8). It may not exist or you may not have access to it. Run --model to pick a different model."
exit 1'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-claude-model-blocked" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --reviewer "claude-opus-4.8" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-claude-model-blocked" \
    --approved-next-step "run external review ext-claude-model-blocked"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Model unavailable or access blocked for route 'claude:opus-4.8'"* ]]
  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-claude-model-blocked" "v1.0" "r01")"
  [ -n "$handoff_dir" ]
  run test ! -f "$handoff_dir/claude-opus-4.8.retry-request.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews reports Claude 401 auth unavailable with sandbox guidance" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-claude-auth-blocked-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-claude-auth-blocked-v1.0

- task_id: ext-claude-auth-blocked
- plan_version: v1.0
- objective: classify Claude auth context blockers
- scope: external review
- assumptions: sandboxed CLI may not see the user terminal login context
- risks: wrapper reports missing fields instead of auth remediation
- acceptance_signals: auth unavailable blocker is reported
- stop_conditions: retry is attempted
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Test auth blocker.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "Failed to authenticate. API Error: 401 Invalid authentication credentials"
exit 1'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-claude-auth-blocked" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --reviewer "claude-opus-4.8" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-claude-auth-blocked" \
    --approved-next-step "run external review ext-claude-auth-blocked"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Runner authentication unavailable for route 'claude:opus-4.8'"* ]]
  [[ "$output" == *"sandbox/keychain permission boundary"* ]]
  [[ "$output" == *"user-approved unsandboxed path"* ]]
  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-claude-auth-blocked" "v1.0" "r01")"
  [ -n "$handoff_dir" ]
  run test ! -f "$handoff_dir/claude-opus-4.8.retry-request.md"
  [ "$status" -eq 0 ]
}

@test "bundled registry exposes the requested OpenAI and Anthropic lineups" {
  local registry_file="$SCRIPTS_DIR/../config/ai_model_registry.json"

  run python3 "$SCRIPTS_DIR/ai_model_registry.py" validate "$registry_file"
  [ "$status" -eq 0 ]

  run python3 "$SCRIPTS_DIR/ai_model_registry.py" emit-shell "$registry_file"
  [ "$status" -eq 0 ]
  local registry_output="$output"

  [[ "$registry_output" == *$'model\tcodex:gpt-5.6-sol\tcodex\tgpt-5.6-sol'* ]]
  [[ "$registry_output" == *$'model\tcodex:gpt-5.6-terra\tcodex\tgpt-5.6-terra'* ]]
  [[ "$registry_output" == *$'model\tcodex:gpt-5.6-luna\tcodex\tgpt-5.6-luna'* ]]
  [[ "$registry_output" == *$'model\tclaude:fable-5\tclaude\tclaude-fable-5'* ]]
  [[ "$registry_output" == *$'model\tclaude:sonnet-5\tclaude\tclaude-sonnet-5'* ]]
  [[ "$registry_output" == *$'model\tclaude:opus-4.8\tclaude\topus-4.8'* ]]
}

@test "run_external_plan_reviews loads runner routes from registry override and still stops on quota" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-registry-override-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-registry-override-v1.0

- task_id: ext-registry-override
- plan_version: v1.0
- objective: test registry-owned model routing
- scope: external review
- assumptions: local registry can add new model aliases without script edits
- risks: wrapper ignores registry override
- acceptance_signals: configured route is invoked and quota stop is reported
- stop_conditions: no fallback CLI is invoked
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Test registry override.
EOF

  local registry_file="$TEST_WORKSPACE/model-registry.json"
  cat > "$registry_file" <<'EOF'
{
  "default_model_alias": "new-sonnet",
  "default_task_phase": "planning",
  "runners": {
    "agy": {
      "binary": "agy",
      "env_binary": "CODEGUIDE_ANTIGRAVITY_BIN",
      "command_kind": "agy"
    },
    "claude": {
      "binary": "claude",
      "env_binary": "CODEGUIDE_CLAUDE_BIN",
      "command_kind": "claude_code"
    }
  },
  "models": {
    "agy:new-gemini": {
      "runner": "agy",
      "cli_model": "gemini-3.6-pro",
      "quota_group": "agy-future-gemini",
      "display_name": "Future Gemini"
    },
    "claude:new-sonnet": {
      "runner": "claude",
      "cli_model": "claude-4.7-sonnet",
      "quota_group": "claude-direct-future",
      "display_name": "Future Sonnet"
    }
  },
  "aliases": {
    "new-gemini": "agy:new-gemini",
    "new-sonnet": "claude:new-sonnet"
  },
  "default_reviewer_aliases": [
    "new-gemini"
  ],
  "fallback_policy": {
    "on_quota_exhausted": [
      {
        "from_quota_group": "agy-future-gemini",
        "phases": ["planning", "review"],
        "to": "new-sonnet"
      }
    ],
    "fail_closed_for_unregistered_models": true
  },
  "quota_error_patterns": [
    "resource_exhausted"
  ]
}
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
  printf "%s\n" "$@" > "${TEST_WORKSPACE}/agy-registry-calls.log"
  echo "Error 429: resource_exhausted" >&2
  exit 1'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
  touch "${TEST_WORKSPACE}/claude-registry-calls.log"
  echo "claude should not be auto-invoked after agy quota exhaustion" >&2
  exit 99'

  run env CODEGUIDE_MODEL_REGISTRY="$registry_file" PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-registry-override" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --primary-model "new-sonnet" \
    --reviewer "new-gemini" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-registry-override" \
    --approved-next-step "run external review ext-registry-override"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Quota exhausted for route 'agy:new-gemini' (quota_group=agy-future-gemini)"* ]]
  [[ "$output" == *"Switch the globally selected model in runner 'agy'"* ]]

  run grep -- "--add-dir" "$TEST_WORKSPACE/agy-registry-calls.log"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/agy-registry-settings.json"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-registry-calls.log"
  [ "$status" -eq 0 ]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-registry-override-v1.0-review-agy-new-gemini-r01.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews --help does not require a readable model registry" {
  run env CODEGUIDE_MODEL_REGISTRY="$TEST_WORKSPACE/missing-registry.json" bash "$RUN_EXTERNAL_REVIEWS" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" != *"Model registry not found"* ]]
}

@test "run_external_plan_reviews rejects invalid task phase before fallback routing" {
  run bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-invalid-phase" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-invalid-phase" \
    --approved-next-step "run external review ext-invalid-phase" \
    --task-phase "cod"

  [ "$status" -ne 0 ]
  [[ "$output" == *"[ERROR] Invalid --task-phase: cod"* ]]
}

@test "run_external_plan_reviews unregistered reviewer route fails closed before invocation" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-unknown-model-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-unknown-model-v1.0

- task_id: ext-unknown-model
- plan_version: v1.0
- objective: test unknown model quota behavior
- scope: external review
- assumptions: unknown model exhausts quota
- risks: wrapper guesses fallback pool
- acceptance_signals: script fails closed
- stop_conditions: script exits
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
echo "Error 429: resource_exhausted" >&2
exit 1'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-unknown-model" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --primary-model "claude-sonnet-4.6" \
    --reviewer "future-model" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-unknown-model" \
    --approved-next-step "run external review ext-unknown-model"

  [ "$status" -ne 0 ]
  [[ "$output" == *"resolves to unregistered model 'future-model'"* ]]
  [[ "$output" != *"Registry fallback succeeded"* ]]
}

@test "run_external_plan_reviews rejects registry fallback targets outside known routes" {
  local registry_file="$TEST_WORKSPACE/bad-fallback-registry.json"
  cat > "$registry_file" <<'EOF'
{
  "default_model_alias": "gemini",
  "runners": {
    "agy": {
      "binary": "agy",
      "env_binary": "CODEGUIDE_ANTIGRAVITY_BIN",
      "command_kind": "agy"
    }
  },
  "models": {
    "agy:gemini-local": {
      "runner": "agy",
      "cli_model": "gemini-local",
      "quota_group": "agy-gemini",
      "display_name": "Gemini Local"
    }
  },
  "aliases": {
    "gemini": "agy:gemini-local",
    "fallback": "agy:missing"
  },
  "default_reviewer_aliases": [
    "gemini"
  ],
  "fallback_policy": {
    "on_quota_exhausted": [
      {
        "from_quota_group": "agy-gemini",
        "phases": ["planning"],
        "to": "fallback"
      }
    ],
    "fail_closed_for_unregistered_models": true
  },
  "quota_error_patterns": [
    "quota"
  ]
}
EOF

  run env CODEGUIDE_MODEL_REGISTRY="$registry_file" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-bad-fallback" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-bad-fallback" \
    --approved-next-step "run external review ext-bad-fallback"

  [ "$status" -ne 0 ]
  [[ "$output" == *"references unknown model route"* ]]
}

@test "run_external_plan_reviews stops after first exhausted route without fallback invocation" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-fallback-exhausted-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-fallback-exhausted-v1.0

- task_id: ext-fallback-exhausted
- plan_version: v1.0
- objective: test quota stop classification
- scope: external review
- assumptions: primary route exhausts quota
- risks: fallback CLI is invoked without user model selection
- acceptance_signals: model-switch guidance appears and fallback CLI is not called
- stop_conditions: script exits
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
echo "Error 429: resource_exhausted rate limit exceeded" >&2
exit 1'
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-fallback-called"
echo "Error 429: resource_exhausted rate limit exceeded" >&2
exit 1'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-fallback-exhausted" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --primary-model "claude-sonnet-4.6" \
    --reviewer "agy-gemini-3.5-flash-medium" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-fallback-exhausted" \
    --approved-next-step "run external review ext-fallback-exhausted"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Quota exhausted for route 'agy:gemini-3.5-flash-medium' (quota_group=agy-gemini-shared)"* ]]
  [[ "$output" == *"Switch the globally selected model in runner 'agy'"* ]]
  run test ! -e "$TEST_WORKSPACE/claude-fallback-called"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews resolves adversarial evaluator runner aliases" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-adversarial-alias-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-adversarial-alias-v1.0

- task_id: ext-adversarial-alias
- plan_version: v1.0
- objective: test adversarial evaluator alias
- scope: external review
- assumptions: adversarial evaluator is a model alias
- risks: alias validation rejects the evaluator
- acceptance_signals: adversarial report is written
- stop_conditions: report generated
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
cat <<EOF
- verdict: accept
- summary: Standard agy review completed.
- strengths: The request was bounded.
- risks: None.
- requested_changes: None.
EOF'
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
cat <<EOF
- verdict: revise
- summary: Alias review completed.
- strengths: The request was bounded.
- risks: The adversarial path needs clear metadata.
- requested_changes: Keep adversarial style visible.
- objection: Alias handling may be brittle.
- counterproposal: Resolve aliases before matching reviewers.
- rebuttal: The resolved reviewer list can still preserve intent.
- residual_risk: Operators may misconfigure aliases.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-adversarial-alias" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --primary-model "claude-opus-4.8" \
    --reviewer "agy-gemini-3.5-flash-medium" \
    --reviewer "claude-sonnet-4.6" \
    --adversarial-evaluator "claude-sonnet-4.6" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-adversarial-alias" \
    --approved-next-step "run external review ext-adversarial-alias"

  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-adversarial-alias-v1.0-review-claude-sonnet-4.6-r01.md"
  [ "$status" -eq 0 ]
}

@test "external_review_runner enqueues current-task debate and dry-runs runner participants" {
  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-neutral" --plan-version "v1.0" --review-round "r01" --task-phase "planning" --coordinator "claude" --participant "agy-current" --participant "claude-current" --participant "codex-current"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"

  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/orchestration/runner-neutral/current-task/debate.json"
  [ "$status" -eq 0 ]
  run grep '"coordinator": "claude"' "$DOCS_ROOT/orchestration/runner-neutral/current-task/debate.json"
  [ "$status" -eq 0 ]
  run grep '"runner_route": "agy:current"' "$DOCS_ROOT/orchestration/runner-neutral/current-task/debate.json"
  [ "$status" -eq 0 ]
  run grep '"runner_route": "claude:current"' "$DOCS_ROOT/orchestration/runner-neutral/current-task/debate.json"
  [ "$status" -eq 0 ]
  run grep '"runner_route": "codex:current"' "$DOCS_ROOT/orchestration/runner-neutral/current-task/debate.json"
  [ "$status" -eq 0 ]

  run python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-neutral" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"agy --add-dir"* ]]
  [[ "$output" == *"claude -p"* ]]
  [[ "$output" == *"codex exec"* ]]
  [[ "$output" != *"--model"* ]]
  [[ "$output" != *" -m "* ]]
}

@test "external_review_runner treats any coordinator's own current route as manual/current-thread, not only codex" {
  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-coordinator-neutral" --plan-version "v1.0" --review-round "r01" --task-phase "planning" --coordinator "claude" --participant "claude:current" --participant "agy-current"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"

  [ "$status" -eq 0 ]
  run grep '"coordinator": "claude"' "$DOCS_ROOT/orchestration/runner-coordinator-neutral/current-task/debate.json"
  [ "$status" -eq 0 ]
  run grep -A2 '"id": "claude:current"' "$DOCS_ROOT/orchestration/runner-coordinator-neutral/current-task/debate.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"role": "participant"'* ]]
  [[ "$output" == *'"runner_route": "manual/current-thread"'* ]]
  run grep '"runner_route": "agy:current"' "$DOCS_ROOT/orchestration/runner-coordinator-neutral/current-task/debate.json"
  [ "$status" -eq 0 ]

  run python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-coordinator-neutral" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" != *"claude -p"* ]]
  [[ "$output" == *"agy --add-dir"* ]]
}

@test "external_review_runner executes agy with current CLI flags and preconfigured model selection" {
  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/runner-agy-args.log"
cat <<EOF
- verdict: accept
- summary: Mock agy accepted the current-task debate packet.
- strengths: The runner used current CLI flags.
- risks: None.
- requested_changes: None.
EOF'

  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-agy-exec" --plan-version "v1.0" --review-round "r01" --task-phase "review" --coordinator "codex" --participant "agy-gemini-3.5-flash-high"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-agy-exec" --force
  [ "$status" -eq 0 ]

  run test ! -e "$TEST_WORKSPACE/runner-agy-settings.json"
  [ "$status" -eq 0 ]
  run grep -- "--add-dir" "$TEST_WORKSPACE/runner-agy-args.log"
  [ "$status" -eq 0 ]
  run grep -E -- '(^|[[:space:]])-m([[:space:]]|$)|--approval-mode|--output-format|--include-directories' "$TEST_WORKSPACE/runner-agy-args.log"
  [ "$status" -ne 0 ]
  run test -f "$DOCS_ROOT/orchestration/runner-agy-exec/current-task/responses/agy-gemini-3.5-flash-high.response.md"
  [ "$status" -eq 0 ]
  run grep "^- model_selection: preconfigured_runtime" "$DOCS_ROOT/orchestration/runner-agy-exec/current-task/provenance/agy-gemini-3.5-flash-high.provenance.md"
  [ "$status" -eq 0 ]
}

@test "external_review_runner run-once warns and skips a participant whose response already exists without --force" {
  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
printf "x" >> "${TEST_WORKSPACE}/runner-skip-warn-agy.count"
cat <<EOF
- verdict: accept
- summary: Mock agy accepted the current-task debate packet.
- strengths: Fixture invocation counter.
- risks: None.
- requested_changes: None.
EOF'

  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-skip-warn" --plan-version "v1.0" --review-round "r01" --task-phase "review" --coordinator "codex" --participant "agy-gemini-3.5-flash-high"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  # First run creates the response (forced, since nothing exists yet).
  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-skip-warn" --force
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/orchestration/runner-skip-warn/current-task/responses/agy-gemini-3.5-flash-high.response.md"
  [ "$status" -eq 0 ]
  run cat "$TEST_WORKSPACE/runner-skip-warn-agy.count"
  [ "$output" = "x" ]

  # Second run without --force must skip and warn, and must NOT invoke the CLI again.
  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-skip-warn"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] skipping participant agy:gemini-3.5-flash-high: response already exists (use --force to rerun)"* ]]
  run cat "$TEST_WORKSPACE/runner-skip-warn-agy.count"
  [ "$output" = "x" ]
}

@test "external_review_runner run-once --force suppresses the skip warning and actually reruns the participant" {
  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
printf "x" >> "${TEST_WORKSPACE}/runner-force-rerun-agy.count"
cat <<EOF
- verdict: accept
- summary: Mock agy accepted the current-task debate packet.
- strengths: Fixture invocation counter.
- risks: None.
- requested_changes: None.
EOF'

  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-force-rerun" --plan-version "v1.0" --review-round "r01" --task-phase "review" --coordinator "codex" --participant "agy-gemini-3.5-flash-high"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-force-rerun" --force
  [ "$status" -eq 0 ]
  run cat "$TEST_WORKSPACE/runner-force-rerun-agy.count"
  [ "$output" = "x" ]

  # Rerunning with --force must invoke the CLI again (no skip warning either).
  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-force-rerun" --force
  [ "$status" -eq 0 ]
  [[ "$output" != *"[WARN] skipping participant"* ]]
  run cat "$TEST_WORKSPACE/runner-force-rerun-agy.count"
  [ "$output" = "xx" ]
}

@test "external_review_runner executes codex with preconfigured model selection" {
  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/runner-codex-args.log"
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
cat > "$output_file" <<EOF
- verdict: accept
- summary: Mock Codex accepted the current-task debate packet.
- strengths: The runner used global Codex configuration.
- risks: None.
- requested_changes: None.
EOF'

  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-codex-exec" --plan-version "v1.0" --review-round "r01" --task-phase "review" --coordinator "agy" --participant "codex-current"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-codex-exec" --force
  [ "$status" -eq 0 ]

  run grep -- "exec" "$TEST_WORKSPACE/runner-codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--output-last-message" "$TEST_WORKSPACE/runner-codex-args.log"
  [ "$status" -eq 0 ]
  run grep -E -- '(^|[[:space:]])-m([[:space:]]|$)|--model' "$TEST_WORKSPACE/runner-codex-args.log"
  [ "$status" -ne 0 ]
  run test -f "$DOCS_ROOT/orchestration/runner-codex-exec/current-task/responses/codex-current.response.md"
  [ "$status" -eq 0 ]
  run grep "^- model_selection: preconfigured_runtime" "$DOCS_ROOT/orchestration/runner-codex-exec/current-task/provenance/codex-current.provenance.md"
  [ "$status" -eq 0 ]
}

@test "external_review_runner passes explicit Codex registry model" {
  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/runner-codex-model-args.log"
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
cat > "$output_file" <<EOF
- verdict: accept
- summary: Mock Codex accepted the explicit GPT-5.6 Terra route.
- strengths: The registered model reached the CLI.
- risks: None.
- requested_changes: None.
EOF'

  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-codex-model" --plan-version "v1.0" --review-round "r01" --task-phase "review" --coordinator "agy" --participant "codex-5.6-terra"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-codex-model" --force
  [ "$status" -eq 0 ]

  run grep -- "--model" "$TEST_WORKSPACE/runner-codex-model-args.log"
  [ "$status" -eq 0 ]
  run grep -- "gpt-5.6-terra" "$TEST_WORKSPACE/runner-codex-model-args.log"
  [ "$status" -eq 0 ]
  run grep "^- model_selection: cli_flag" "$DOCS_ROOT/orchestration/runner-codex-model/current-task/provenance/codex-gpt-5.6-terra.provenance.md"
  [ "$status" -eq 0 ]
}

@test "external_review_runner preserves auth-unavailable stdout in stderr artifact" {
  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
cat >/dev/null
echo "Not logged in · Please run /login"
exit 1'

  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-claude-auth" --plan-version "v1.0" --review-round "r01" --task-phase "review" --coordinator "codex" --participant "claude-opus-4.8"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-claude-auth" --force
  [ "$status" -ne 0 ]

  local stderr_file="$DOCS_ROOT/orchestration/runner-claude-auth/external-cli/v1.0/r01/claude-opus-4.8.stderr.md"
  run test -f "$stderr_file"
  [ "$status" -eq 0 ]
  run grep "Runner authentication unavailable for route 'claude:opus-4.8'" "$stderr_file"
  [ "$status" -eq 0 ]
  run grep "Not logged in" "$stderr_file"
  [ "$status" -eq 0 ]
}

@test "external_review_runner classifies Claude 401 auth failure as auth unavailable" {
  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
cat >/dev/null
echo "Failed to authenticate. API Error: 401 Invalid authentication credentials"
exit 1'

  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: debate request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-claude-auth-401" --plan-version "v1.0" --review-round "r01" --task-phase "review" --coordinator "codex" --participant "claude-opus-4.8"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run env PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-claude-auth-401" --force
  [ "$status" -ne 0 ]

  local stderr_file="$DOCS_ROOT/orchestration/runner-claude-auth-401/external-cli/v1.0/r01/claude-opus-4.8.stderr.md"
  run test -f "$stderr_file"
  [ "$status" -eq 0 ]
  run grep "Runner authentication unavailable for route 'claude:opus-4.8'" "$stderr_file"
  [ "$status" -eq 0 ]
  run grep "Invalid authentication credentials" "$stderr_file"
  [ "$status" -eq 0 ]
  run grep "user-approved unsandboxed path" "$stderr_file"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews --adversarial-all runs same-vendor peer and cross-vendor reviewers adversarially" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-adv-all-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-adv-all-v1.0

- task_id: ext-adv-all
- plan_version: v1.0
- objective: validate all-adversarial cross-vendor review rounds
- scope: external review wrapper adversarial routing
- assumptions: author vendor peer model differs from the author model
- risks: same-vendor agreement bias could overfit the review
- acceptance_signals: three adversarial reports exist
- stop_conditions: operator reviews the reports
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Run one same-vendor peer and two cross-vendor reviewers.
2. Require adversarial style from all of them.
3. Stop.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
cat <<EOF
- verdict: revise
- summary: Gemini adversarial pass finds sequencing gaps.
- strengths: Bounded review flow.
- risks: Sequencing gaps remain.
- requested_changes: Tighten step ordering.
- objection: The rollout order is unproven.
- counterproposal: Stage the rollout behind a validation gate.
- rebuttal: The current draft still isolates review from mutation.
- residual_risk: Operators may skip the staged gate.
EOF'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-args.log"
cat >> "${TEST_WORKSPACE}/claude-args.log"
cat <<EOF
- verdict: revise
- summary: Same-vendor peer adversarial pass challenges the assumptions.
- strengths: The plan keeps the operator in control.
- risks: Assumption coverage is thin.
- requested_changes: Add explicit assumption checks.
- objection: The primary author may share blind spots with this reviewer.
- counterproposal: Weight cross-vendor findings higher on conflict.
- rebuttal: A same-vendor peer still catches model-family-specific drift.
- residual_risk: Vendor-shared training bias is not fully eliminated.
EOF'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ -z "$output_file" ]]; then
  output_file="/dev/stdout"
fi
cat > "$output_file" <<EOF
- verdict: revise
- summary: OpenAI adversarial pass questions verification depth.
- strengths: Artifacts are durable.
- risks: Verification is shallow.
- requested_changes: Add negative-path checks.
- objection: The stop conditions are underspecified.
- counterproposal: Enumerate explicit failure stop conditions.
- rebuttal: The draft still blocks silent auto-versioning.
- residual_risk: Manual convergence may miss one reviewer objection.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-adv-all" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --primary-model "claude-fable-5" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-adv-all" \
    --approved-next-step "run external review ext-adv-all v1.0 r01" \
    --reviewer "claude-sonnet-5" \
    --reviewer "agy-current" \
    --reviewer "codex-current" \
    --adversarial-all

  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK] evaluator=claude"*"style=adversarial"* ]]
  [[ "$output" == *"[OK] evaluator=agy"*"style=adversarial"* ]]
  [[ "$output" == *"[OK] evaluator=codex"*"style=adversarial"* ]]
  [[ "$output" != *"style=standard"* ]]

  run grep -- "--model" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run grep -- "claude-sonnet-5" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]

  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-adv-all-v1.0-review-claude-sonnet-5-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-adv-all-v1.0-review-agy-current-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-adv-all-v1.0-review-codex-current-r01.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews repeatable adversarial evaluators fail closed even with allow-partial-review" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-adv-multi-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-adv-multi-v1.0

- task_id: ext-adv-multi
- plan_version: v1.0
- objective: verify multi-adversarial failure blocks partial acceptance
- scope: external review wrapper adversarial gating
- assumptions: one adversarial reviewer may fail
- risks: partial acceptance could mask a missing adversarial pass
- acceptance_signals: wrapper exits non-zero when any adversarial reviewer fails
- stop_conditions: failure is surfaced
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Mark two reviewers adversarial.
2. Let one adversarial reviewer fail.
3. Expect non-zero exit despite --allow-partial-review.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
echo "forced agy adversarial failure" >&2
exit 8'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
cat >/dev/null
cat <<EOF
- verdict: revise
- summary: Claude adversarial pass succeeded.
- strengths: Bounded handoff.
- risks: One adversarial peer is missing.
- requested_changes: Rerun the failed adversarial reviewer.
- objection: Partial adversarial coverage is not sufficient.
- counterproposal: Block acceptance until every adversarial pass lands.
- rebuttal: The successful passes still carry signal.
- residual_risk: Convergence may proceed on incomplete objections.
EOF'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ -z "$output_file" ]]; then
  output_file="/dev/stdout"
fi
cat > "$output_file" <<EOF
- verdict: revise
- summary: Codex standard pass succeeded.
- strengths: Reports are durable.
- risks: None noted.
- requested_changes: None.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-adv-multi" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-adv-multi" \
    --approved-next-step "run external review ext-adv-multi v1.0 r01" \
    --adversarial-evaluator "agy-current" \
    --adversarial-evaluator "claude-current" \
    --allow-partial-review

  [ "$status" -ne 0 ]
  [[ "$output" == *"[FAIL] evaluator=agy"*"style=adversarial"* ]]
  [[ "$output" == *"[OK] evaluator=claude"*"style=adversarial"* ]]
  [[ "$output" == *"Required adversarial review did not complete successfully"* ]]
  [[ "$output" == *"agy:current"* ]]
}

@test "run_external_plan_reviews --adversarial-cross-check auto-selects registry vendor peer and cross-vendor reviewers" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-cross-check-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-cross-check-v1.0

- task_id: ext-cross-check
- plan_version: v1.0
- objective: validate registry-driven cross-vendor adversarial auto-selection
- scope: external review wrapper vendor automation
- assumptions: primary author is a direct Anthropic model
- risks: same-model-family review could overfit and miss defects
- acceptance_signals: a same-vendor peer plus every other vendor reviews adversarially
- stop_conditions: operator reviews the reports
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Run with --adversarial-cross-check and no manual reviewer selection.
2. Confirm the registry adversarial_peer and vendor_default_reviewers drove selection.
3. Confirm every selected reviewer ran in adversarial style.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
cat <<EOF
- verdict: revise
- summary: Gemini cross-vendor adversarial pass finds sequencing gaps.
- strengths: Bounded review flow.
- risks: Sequencing gaps remain.
- requested_changes: Tighten step ordering.
- objection: The rollout order is unproven.
- counterproposal: Stage the rollout behind a validation gate.
- rebuttal: The current draft still isolates review from mutation.
- residual_risk: Operators may skip the staged gate.
EOF'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-args.log"
cat >> "${TEST_WORKSPACE}/claude-args.log"
cat <<EOF
- verdict: revise
- summary: Same-vendor peer adversarial pass challenges shared assumptions.
- strengths: The plan keeps the operator in control.
- risks: Assumption coverage is thin.
- requested_changes: Add explicit assumption checks.
- objection: The primary author may share blind spots with this reviewer.
- counterproposal: Weight cross-vendor findings higher on conflict.
- rebuttal: A same-vendor peer still catches model-family-specific drift.
- residual_risk: Vendor-shared training bias is not fully eliminated.
EOF'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ -z "$output_file" ]]; then
  output_file="/dev/stdout"
fi
cat > "$output_file" <<EOF
- verdict: revise
- summary: OpenAI cross-vendor adversarial pass questions verification depth.
- strengths: Artifacts are durable.
- risks: Verification is shallow.
- requested_changes: Add negative-path checks.
- objection: The stop conditions are underspecified.
- counterproposal: Enumerate explicit failure stop conditions.
- rebuttal: The draft still blocks silent auto-versioning.
- residual_risk: Manual convergence may miss one reviewer objection.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-cross-check" \
    --plan-version "v1.0" \
    --primary-tool "claude" \
    --primary-model "claude-fable-5" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-cross-check" \
    --approved-next-step "run external review ext-cross-check v1.0 r01" \
    --adversarial-cross-check

  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-selected reviewers=claude:sonnet-5 agy:current codex:current"* ]]
  [[ "$output" == *"[OK] evaluator=claude"*"style=adversarial"* ]]
  [[ "$output" == *"[OK] evaluator=agy"*"style=adversarial"* ]]
  [[ "$output" == *"[OK] evaluator=codex"*"style=adversarial"* ]]
  [[ "$output" != *"style=standard"* ]]

  run grep -- "--model" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run grep -- "claude-sonnet-5" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]

  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-cross-check-v1.0-review-claude-sonnet-5-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-cross-check-v1.0-review-agy-current-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-cross-check-v1.0-review-codex-current-r01.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews --adversarial-cross-check rejects combination with --reviewer" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-cross-check-conflict-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-cross-check-conflict-v1.0

- task_id: ext-cross-check-conflict
- plan_version: v1.0
- objective: verify cross-check auto-selection cannot be mixed with manual reviewer selection
- scope: external review wrapper vendor automation
- assumptions: operators should not partially override registry-driven selection
- risks: silently merged manual and automatic reviewer sets could hide missing coverage
- acceptance_signals: wrapper fails closed before invoking any reviewer
- stop_conditions: conflicting options are rejected
- owner: test
- last_updated: 2026-01-01T00:00:00Z

## Steps
1. Pass --adversarial-cross-check together with --reviewer.
2. Expect an immediate error before any CLI is invoked.
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/agy-called"
exit 99'
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-called"
exit 99'
  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/codex-called"
exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-cross-check-conflict" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-cross-check-conflict" \
    --approved-next-step "run external review ext-cross-check-conflict v1.0 r01" \
    --reviewer "agy-current" \
    --adversarial-cross-check

  [ "$status" -ne 0 ]
  [[ "$output" == *"--adversarial-cross-check cannot be combined with --reviewer"* ]]
  run test ! -e "$TEST_WORKSPACE/agy-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/codex-called"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews passes codex reasoning effort for cli_effort routes" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-effort-01-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-effort-01-v1.0

- task_id: ext-effort-01
- plan_version: v1.0
- objective: validate cli_effort passthrough for codex routes
- scope: external review command construction
- assumptions: mock codex records its argv
- risks: effort flag silently dropped
- acceptance_signals: codex argv contains model_reasoning_effort
- stop_conditions: wrapper completes
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin-effort"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/codex-effort-args.log"
output_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    output_file="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ -z "$output_file" ]]; then
  output_file="/dev/stdout"
fi
cat > "$output_file" <<EOF
- verdict: accept
- summary: Mock codex accepts the effort-routed review.
- strengths: Deterministic fixture.
- risks: None.
- requested_changes: None.
EOF'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-effort-01" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --reviewer "codex-gpt-5.6-sol-high" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-effort-01" \
    --approved-next-step "run external review ext-effort-01 v1.0 r01"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK] evaluator=codex"* ]]
  run grep -- "--model" "$TEST_WORKSPACE/codex-effort-args.log"
  [ "$status" -eq 0 ]
  run grep -x -- "gpt-5.6-sol" "$TEST_WORKSPACE/codex-effort-args.log"
  [ "$status" -eq 0 ]
  run grep -x -- "model_reasoning_effort=high" "$TEST_WORKSPACE/codex-effort-args.log"
  [ "$status" -eq 0 ]
}

@test "external_review_runner dry-run includes codex reasoning effort for cli_effort routes" {
  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: effort route request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-effort" --plan-version "v1.0" --review-round "r01" --task-phase "planning" --coordinator "claude" --participant "codex-gpt-5.6-sol-high"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-effort" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec"* ]]
  [[ "$output" == *"--model gpt-5.6-sol"* ]]
  [[ "$output" == *"model_reasoning_effort=high"* ]]
}

@test "run_external_plan_reviews blocks sandboxed claude invocation with non-sandboxed remediation" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-sandbox-01-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-sandbox-01-v1.0

- task_id: ext-sandbox-01
- plan_version: v1.0
- objective: validate codex sandbox guard for claude routes
- scope: external review invocation guard
- assumptions: CODEX_SANDBOX marks a sandboxed codex shell
- risks: claude invoked from a sandbox burns the round on auth failure
- acceptance_signals: claude binary is never invoked
- stop_conditions: wrapper reports the blocked route
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin-sandbox"
  mkdir -p "$mock_bin"

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-sandbox-called"
cat <<EOF
- verdict: accept
- summary: should never run
- strengths: none
- risks: none
- requested_changes: none
EOF'

  run env CODEX_SANDBOX=seatbelt PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-sandbox-01" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --reviewer "claude-current" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-sandbox-01" \
    --approved-next-step "run external review ext-sandbox-01 v1.0 r01"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Codex sandbox detected"* ]]
  [[ "$output" == *"non-sandboxed"* ]]
  run test -e "$TEST_WORKSPACE/claude-sandbox-called"
  [ "$status" -ne 0 ]
}

@test "external_review_runner blocks sandboxed claude invocation before running the binary" {
  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: sandbox guard request" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" enqueue --task-id "runner-sandbox" --plan-version "v1.0" --review-round "r01" --task-phase "planning" --coordinator "codex" --participant "claude-current"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local mock_bin="$TEST_WORKSPACE/mock-bin-runner-sandbox"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/runner-claude-sandbox-called"
echo "- verdict: accept"'

  run env CODEX_SANDBOX=seatbelt PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" run-once --task-id "runner-sandbox"

  [ "$status" -ne 0 ]
  run test -e "$TEST_WORKSPACE/runner-claude-sandbox-called"
  [ "$status" -ne 0 ]
  run bash -c 'grep -rl "Codex sandbox detected" "$1"/docs/orchestration/runner-sandbox' _ "$TEST_PROJECT"
  [ "$status" -eq 0 ]
}

@test "sandbox guard ignores explicitly falsy codex markers" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-sandbox-02-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-sandbox-02-v1.0

- task_id: ext-sandbox-02
- plan_version: v1.0
- objective: falsy sandbox markers must not block claude routes
- scope: sandbox marker boolean semantics
- assumptions: inherited markers may carry 0/false values
- risks: false-positive guard blocks legitimate unsandboxed runs
- acceptance_signals: claude runs when markers are falsy
- stop_conditions: wrapper completes
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin-sandbox-falsy"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-falsy-called"
cat <<EOF
- verdict: accept
- summary: falsy markers must not block
- strengths: bounded
- risks: none
- requested_changes: none
EOF'

  run env CODEX_SANDBOX=false CODEX_SANDBOX_NETWORK_DISABLED=0 PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-sandbox-02" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --reviewer "claude-current" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-sandbox-02" \
    --approved-next-step "run external review ext-sandbox-02 v1.0 r01"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK] evaluator=claude"* ]]
  run test -e "$TEST_WORKSPACE/claude-falsy-called"
  [ "$status" -eq 0 ]
}

@test "sandbox guard blocks on a truthy network-disabled marker alone" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-sandbox-03-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-sandbox-03-v1.0

- task_id: ext-sandbox-03
- plan_version: v1.0
- objective: network-disabled marker alone must block claude routes
- scope: sandbox marker boolean semantics
- assumptions: CODEX_SANDBOX_NETWORK_DISABLED=1 marks a sandboxed shell
- risks: claude invoked without network burns the round
- acceptance_signals: claude binary is never invoked
- stop_conditions: wrapper reports the blocked route
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin-sandbox-net"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-net-called"
echo "- verdict: accept"'

  run env CODEX_SANDBOX_NETWORK_DISABLED=1 PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-sandbox-03" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --reviewer "claude-current" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-sandbox-03" \
    --approved-next-step "run external review ext-sandbox-03 v1.0 r01"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Codex sandbox detected"* ]]
  run test -e "$TEST_WORKSPACE/claude-net-called"
  [ "$status" -ne 0 ]
}

@test "model registry rejects control characters in registry fields" {
  local bad_registry="$TEST_WORKSPACE/bad-registry.json"
  python3 - "$bad_registry" <<'PY'
import json
import sys

registry = {
    "default_model_alias": "agy-current",
    "default_task_phase": "planning",
    "runners": {"agy": {"binary": "agy", "env_binary": "X", "command_kind": "agy"}},
    "models": {
        "agy:current": {
            "runner": "agy",
            "cli_model": "preconfigured-runtime",
            "display_name": "BadName",
            "quota_group": "g",
            "vendor": "google",
        }
    },
    "aliases": {"agy-current": "agy:current"},
    "default_reviewer_aliases": ["agy-current"],
    "vendor_default_reviewers": {"google": "agy-current"},
    "fallback_policy": {"fail_closed_for_unregistered_models": True, "on_quota_exhausted": []},
    "quota_error_patterns": ["quota"],
}
with open(sys.argv[1], "w") as handle:
    json.dump(registry, handle)
PY

  run python3 "$SCRIPTS_DIR/ai_model_registry.py" emit-shell "$bad_registry"
  [ "$status" -ne 0 ]
  [[ "$output" == *"control characters"* ]]
}

@test "model registry rejects cli_effort on non-codex runners" {
  local bad_registry="$TEST_WORKSPACE/effort-registry.json"
  python3 - "$bad_registry" <<'PY'
import json
import sys

registry = {
    "default_model_alias": "agy-current",
    "default_task_phase": "planning",
    "runners": {"agy": {"binary": "agy", "env_binary": "X", "command_kind": "agy"}},
    "models": {
        "agy:current": {
            "runner": "agy",
            "cli_model": "preconfigured-runtime",
            "cli_effort": "high",
            "display_name": "Preconfigured",
            "quota_group": "g",
            "vendor": "google",
        }
    },
    "aliases": {"agy-current": "agy:current"},
    "default_reviewer_aliases": ["agy-current"],
    "vendor_default_reviewers": {"google": "agy-current"},
    "fallback_policy": {"fail_closed_for_unregistered_models": True, "on_quota_exhausted": []},
    "quota_error_patterns": ["quota"],
}
with open(sys.argv[1], "w") as handle:
    json.dump(registry, handle)
PY

  run python3 "$SCRIPTS_DIR/ai_model_registry.py" emit-shell "$bad_registry"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cli_effort is only supported for codex_cli runners"* ]]
}

@test "sandbox guard trims whitespace before truthiness (parity with python)" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-sandbox-04-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-sandbox-04-v1.0

- task_id: ext-sandbox-04
- plan_version: v1.0
- objective: padded falsy markers must not block claude routes
- scope: sandbox marker whitespace parity
- assumptions: markers may carry padded values
- risks: shell and python truthiness diverging on whitespace
- acceptance_signals: claude runs when the marker is a padded falsy value
- stop_conditions: wrapper completes
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin-sandbox-pad"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-pad-called"
cat <<EOF
- verdict: accept
- summary: padded falsy markers must not block
- strengths: bounded
- risks: none
- requested_changes: none
EOF'

  run env "CODEX_SANDBOX= false " PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-sandbox-04" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --reviewer "claude-current" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-sandbox-04" \
    --approved-next-step "run external review ext-sandbox-04 v1.0 r01"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK] evaluator=claude"* ]]
  run test -e "$TEST_WORKSPACE/claude-pad-called"
  [ "$status" -eq 0 ]

  python3 - <<PY
import sys
sys.path.insert(0, "$SCRIPTS_DIR")
from external_review_runner import _sandbox_marker_truthy
assert _sandbox_marker_truthy(" false ") is False
assert _sandbox_marker_truthy(" seatbelt ") is True
PY
}

@test "sandbox guard fires for any claude_code-kind runner id, not only 'claude'" {
  local plan_file="$DOCS_ROOT/plan/PLAN-ext-sandbox-05-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-sandbox-05-v1.0

- task_id: ext-sandbox-05
- plan_version: v1.0
- objective: guard must key on command_kind, not the runner-id string
- scope: sandbox guard dispatch
- assumptions: a second claude_code runner id may be registered later
- risks: renamed claude-family runner bypasses the guard
- acceptance_signals: the second runner's binary is never invoked
- stop_conditions: wrapper reports the blocked route
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local custom_registry="$TEST_WORKSPACE/claude2-registry.json"
  python3 - "$SCRIPTS_DIR/../config/ai_model_registry.json" "$custom_registry" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    registry = json.load(handle)
registry["runners"]["claude2"] = {"binary": "claude2", "env_binary": "CODEGUIDE_CLAUDE2_BIN", "command_kind": "claude_code"}
registry["models"]["claude2:current"] = {
    "runner": "claude2",
    "cli_model": "preconfigured-runtime",
    "display_name": "Claude2 preconfigured",
    "quota_group": "claude2-preconfigured",
    "vendor": "anthropic",
}
registry["aliases"]["claude2-current"] = "claude2:current"
with open(sys.argv[2], "w") as handle:
    json.dump(registry, handle)
PY

  local mock_bin="$TEST_WORKSPACE/mock-bin-claude2"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/claude2" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude2-called"
echo "- verdict: accept"'

  run env CODEX_SANDBOX=seatbelt CODEGUIDE_MODEL_REGISTRY="$custom_registry" PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-sandbox-05" \
    --plan-version "v1.0" \
    --primary-tool "agy" \
    --reviewer "claude2-current" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-sandbox-05" \
    --approved-next-step "run external review ext-sandbox-05 v1.0 r01"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Codex sandbox detected"* ]]
  run test -e "$TEST_WORKSPACE/claude2-called"
  [ "$status" -ne 0 ]
}

@test "external_review_runner blocks a second claude_code runner id under a sandbox (regression pin)" {
  local custom_registry="$TEST_WORKSPACE/claude2-runner-registry.json"
  python3 - "$SCRIPTS_DIR/../config/ai_model_registry.json" "$custom_registry" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    registry = json.load(handle)
registry["runners"]["claude2"] = {"binary": "claude2", "env_binary": "CODEGUIDE_CLAUDE2_BIN", "command_kind": "claude_code"}
registry["models"]["claude2:current"] = {
    "runner": "claude2",
    "cli_model": "preconfigured-runtime",
    "display_name": "Claude2 preconfigured",
    "quota_group": "claude2-preconfigured",
    "vendor": "anthropic",
}
registry["aliases"]["claude2-current"] = "claude2:current"
with open(sys.argv[2], "w") as handle:
    json.dump(registry, handle)
PY

  run bash -c 'printf "%s\n" "- verdict: accept" "- summary: pin" "- strengths: bounded" "- risks: none" "- requested_changes: none" | python3 "$1" --project-root "$2" --registry "$3" enqueue --task-id "runner-claude2-sandbox" --plan-version "v1.0" --review-round "r01" --task-phase "planning" --coordinator "codex" --participant "claude2-current"' _ "$EXTERNAL_REVIEW_RUNNER" "$TEST_PROJECT" "$custom_registry"
  [ "$status" -eq 0 ]

  local mock_bin="$TEST_WORKSPACE/mock-bin-runner-claude2"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/claude2" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/runner-claude2-called"
echo "- verdict: accept"'

  run env CODEX_SANDBOX=seatbelt PATH="$mock_bin:$PATH" python3 "$EXTERNAL_REVIEW_RUNNER" --project-root "$TEST_PROJECT" --registry "$custom_registry" run-once --task-id "runner-claude2-sandbox"

  [ "$status" -ne 0 ]
  run test -e "$TEST_WORKSPACE/runner-claude2-called"
  [ "$status" -ne 0 ]
  run bash -c 'grep -rl "Codex sandbox detected" "$1"/docs/orchestration/runner-claude2-sandbox' _ "$TEST_PROJECT"
  [ "$status" -eq 0 ]
}
