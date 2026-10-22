# Helpers for the review-contract integration suite (tests/review_contract_integration.bats).
# Load AFTER codeguide_helper.
#
# Isolation guarantee: no real agy / claude / codex binary is reachable or executed.
#  - The test PATH is mock-bin : tripwire-bin : tools-bin : /usr/bin:/bin:/usr/sbin:/sbin. The
#    directories that hold the real CLIs (~/.local/bin, /opt/homebrew/bin) are NOT on it;
#    tools-bin holds symlinks to just the two tools the validators need from there (rg, git).
#  - CODEGUIDE_*_BIN point at the mocks explicitly, so resolution never depends on PATH.
#  - tripwire-bin has a shim for every CLI name that appends to tripwire.log and exits 97;
#    teardown fails any test whose tripwire log is not empty.
#  - Every mock runner appends its name to mock-calls.log, so call and retry counts are exact.

RG_CLI_NAMES="agy claude codex gemini antigravity"

rg_base_setup() {
  unset CODEX_SANDBOX CODEX_SANDBOX_NETWORK_DISABLED
  unset CODEGUIDE_SOURCE_ROOT CODEGUIDE_ANTIGRAVITY_BIN CODEGUIDE_CLAUDE_BIN CODEGUIDE_CODEX_BIN

  TEST_WORKSPACE="$(mktemp -d)"
  export TEST_WORKSPACE
  TEST_PROJECT="$TEST_WORKSPACE/repo"
  mkdir -p "$TEST_PROJECT"
  "$INIT_SCAFFOLD" "$TEST_PROJECT" > /dev/null
  DOCS_ROOT="$(docs_root_for_project "$TEST_PROJECT")"

  local guard="$TEST_WORKSPACE/guard"
  RG_MOCK_BIN="$guard/mock-bin"
  RG_TRIPWIRE_BIN="$guard/tripwire-bin"
  RG_TOOLS_BIN="$guard/tools-bin"
  mkdir -p "$RG_MOCK_BIN" "$RG_TRIPWIRE_BIN" "$RG_TOOLS_BIN"
  : > "$TEST_WORKSPACE/tripwire.log"
  : > "$TEST_WORKSPACE/mock-calls.log"

  local name
  for name in $RG_CLI_NAMES; do
    write_mock_cli "$RG_TRIPWIRE_BIN/$name" "#!/usr/bin/env bash
printf '%s %s\\n' '$name' \"\$*\" >> \"$TEST_WORKSPACE/tripwire.log\"
exit 97"
  done
  ln -s "$(command -v rg)" "$RG_TOOLS_BIN/rg"
  ln -s "$(command -v git)" "$RG_TOOLS_BIN/git"

  rg_write_mock_runners
  RG_PATH="$RG_MOCK_BIN:$RG_TRIPWIRE_BIN:$RG_TOOLS_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  RG_ENV=(
    "PATH=$RG_PATH"
    "CODEGUIDE_ANTIGRAVITY_BIN=$RG_MOCK_BIN/agy"
    "CODEGUIDE_CLAUDE_BIN=$RG_MOCK_BIN/claude"
    "CODEGUIDE_CODEX_BIN=$RG_MOCK_BIN/codex"
  )
}

rg_teardown() {
  local rc=0
  if [ -s "$TEST_WORKSPACE/tripwire.log" ]; then
    printf 'TRIPWIRE FIRED (a non-mock CLI name was executed):\n' >&2
    cat "$TEST_WORKSPACE/tripwire.log" >&2
    rc=1
  fi
  rm -rf "${TEST_WORKSPACE:?}"
  return $rc
}

# Each mock logs one line per invocation and prints that runner's body file.
rg_write_mock_runners() {
  local runner
  for runner in agy claude; do
    write_mock_cli "$RG_MOCK_BIN/$runner" "#!/usr/bin/env bash
printf '%s\\n' '$runner' >> \"$TEST_WORKSPACE/mock-calls.log\"
cat \"$TEST_WORKSPACE/mock-body.$runner\""
  done
  write_mock_cli "$RG_MOCK_BIN/codex" "#!/usr/bin/env bash
printf '%s\\n' 'codex' >> \"$TEST_WORKSPACE/mock-calls.log\"
output_file=\"/dev/stdout\"
while [[ \$# -gt 0 ]]; do
  if [[ \"\$1\" == \"--output-last-message\" ]]; then output_file=\"\${2:-}\"; shift 2; else shift; fi
done
cat \"$TEST_WORKSPACE/mock-body.codex\" > \"\$output_file\""
}

# rg_mock_body <runner> <text>: what that mock prints on every call.
rg_mock_body() {
  printf '%s\n' "$2" > "$TEST_WORKSPACE/mock-body.$1"
}

# rg_mock_calls [runner]: number of logged mock invocations (all runners when omitted).
rg_mock_calls() {
  if [ -n "${1:-}" ]; then
    grep -c "^$1\$" "$TEST_WORKSPACE/mock-calls.log" || true
  else
    wc -l < "$TEST_WORKSPACE/mock-calls.log" | tr -d ' '
  fi
}

rg_mock_calls_reset() {
  : > "$TEST_WORKSPACE/mock-calls.log"
}

# Response builder (same defaults as tests/external_review.bats adversarial_response).
# $1 = verdict; each remaining arg is key=value (value may be empty) or -key to drop the line.
rg_adversarial_response() {
  local verdict="$1"
  shift
  local -a keys=(summary strengths risks requested_changes objection counterproposal rebuttal residual_risk)
  local -a values=(
    "The plan is execution-ready for this bounded scope."
    "It separates review collection from plan mutation."
    "Operators may still skim the adversarial report."
    "None blocking."
    "The rollout order is unproven."
    "Stage the rollout behind a validation gate."
    "The current draft still isolates review from mutation."
    "Did not exercise the rollback path, only reviewed it."
  )
  local override key i
  local -a dropped=()
  for override in "$@"; do
    if [[ "$override" == -* ]]; then
      dropped+=("${override#-}")
      continue
    fi
    key="${override%%=*}"
    for i in "${!keys[@]}"; do
      if [[ "${keys[$i]}" == "$key" ]]; then
        values[$i]="${override#*=}"
      fi
    done
  done
  printf -- '- verdict: %s\n' "$verdict"
  for i in "${!keys[@]}"; do
    if [[ " ${dropped[*]-} " == *" ${keys[$i]} "* ]]; then
      continue
    fi
    if [[ -n "${values[$i]}" ]]; then
      printf -- '- %s: %s\n' "${keys[$i]}" "${values[$i]}"
    else
      printf -- '- %s:\n' "${keys[$i]}"
    fi
  done
}

# Standard response: verdict plus the four standard fields; -key drops a line.
rg_standard_response() {
  local verdict="$1"
  shift
  local -a keys=(summary strengths risks requested_changes)
  local -a values=(
    "The plan is execution-ready for this bounded scope."
    "It separates review collection from plan mutation."
    "Operators may still skim the report."
    "None blocking."
  )
  local override i
  local -a dropped=()
  for override in "$@"; do
    if [[ "$override" == -* ]]; then
      dropped+=("${override#-}")
    fi
  done
  printf -- '- verdict: %s\n' "$verdict"
  for i in "${!keys[@]}"; do
    if [[ " ${dropped[*]-} " == *" ${keys[$i]} "* ]]; then
      continue
    fi
    printf -- '- %s: %s\n' "${keys[$i]}" "${values[$i]}"
  done
}

rg_evidence_dir() {
  printf '%s/orchestration/%s/external-cli/%s/%s' "$DOCS_ROOT" "$1" "$2" "$3"
}

rg_ensure_plan() {
  local task_id="$1" plan_version="$2"
  mkdir -p "$DOCS_ROOT/plan"
  [ -f "$DOCS_ROOT/plan/PLAN-${task_id}-${plan_version}.md" ] || cat > "$DOCS_ROOT/plan/PLAN-${task_id}-${plan_version}.md" <<EOF
# PLAN-${task_id}-${plan_version}

- task_id: ${task_id}
- plan_version: ${plan_version}
- objective: integration contract test
- scope: test fixture
- assumptions: mock runners only
- risks: low
- acceptance_signals: wrapper writes request, response and provenance
- stop_conditions: wrapper completes
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF
}

# rg_review <task> <plan-version> <round> <standard|adversarial> <alias>...
# Runs the REAL run_external_plan_reviews.sh against the mocks. Sets bats $status / $output.
rg_review() {
  local task_id="$1" plan_version="$2" review_round="$3" review_style="$4"
  shift 4
  local -a reviewer_args=() style_args=()
  local alias_name
  for alias_name in "$@"; do
    reviewer_args+=(--reviewer "$alias_name")
  done
  if [ "$review_style" = "adversarial" ]; then
    style_args+=(--adversarial-all)
  fi
  rg_ensure_plan "$task_id" "$plan_version"
  run env "${RG_ENV[@]}" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "$task_id" \
    --plan-version "$plan_version" \
    --primary-tool "codex" \
    "${reviewer_args[@]}" \
    ${style_args[@]+"${style_args[@]}"} \
    --review-round "$review_round" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-${task_id}" \
    --approved-next-step "run external review ${task_id} ${plan_version} ${review_round}"
}

rg_field() {
  sed -n "s/^- $2:[[:space:]]*//p" "$1" | head -n 1
}

# The wrapper accepted the response on its FIRST attempt and wrote the full artifact set.
# $1 task, $2 route slug (e.g. agy-current), $3 round, $4 expected style, $5 expected verdict.
rg_assert_first_attempt_accept() {
  local task_id="$1" slug="$2" review_round="$3" style="$4" verdict="${5:-accept}"
  local dir
  dir="$(rg_evidence_dir "$task_id" v1.0 "$review_round")"
  [ -f "$dir/${slug}.request.md" ]
  [ -f "$dir/${slug}.response.md" ]
  [ -f "$dir/${slug}.response.provenance.md" ]
  [ -f "$DOCS_ROOT/report/PLAN-${task_id}-v1.0-review-${slug}-${review_round}.md" ]
  # no retry artifacts and exactly one CLI call
  [ ! -e "$dir/${slug}.retry-request.md" ]
  [ ! -e "$dir/${slug}.retry-response.md" ]
  [ "$(rg_mock_calls)" -eq 1 ]
  [ "$(rg_field "$dir/${slug}.response.provenance.md" review_style)" = "$style" ]
  [ "$(rg_field "$dir/${slug}.response.provenance.md" verdict)" = "$verdict" ]
}

# The wrapper's parser refused the response: formatting retry happened (2 calls), the round
# FAILed, and neither provenance nor report exists.
rg_assert_parse_rejected() {
  local task_id="$1" slug="$2" review_round="$3"
  local dir
  dir="$(rg_evidence_dir "$task_id" v1.0 "$review_round")"
  assert_contains "$output" "[FAIL] evaluator="
  [ ! -e "$dir/${slug}.response.provenance.md" ]
  [ ! -e "$dir/${slug}.retry-response.provenance.md" ]
  [ ! -e "$DOCS_ROOT/report/PLAN-${task_id}-v1.0-review-${slug}-${review_round}.md" ]
  [ "$(rg_mock_calls)" -eq 2 ]
}

# Run the evidence verifier directly: <task> <plan-version> <round> <route>. Sets $status/$output.
rg_verify() {
  run python3 -I "$SCRIPTS_DIR/validate_docs_review_evidence.py" "$(rg_evidence_dir "$1" "$2" "$3")" "$4" "$1" "$2" "$3"
}

# Fail-closed gate: <task> [to-status]. Sets $status/$output.
rg_gate() {
  if [ -n "${2:-}" ]; then
    run env "${RG_ENV[@]}" "$VALIDATE" "$TEST_PROJECT" --gate external-review --task-id "$1" --to-status "$2"
  else
    run env "${RG_ENV[@]}" "$VALIDATE" "$TEST_PROJECT" --gate external-review --task-id "$1"
  fi
}

# Task + plan + ORCH + index row for the gate. Same shape as validate_docs.bats' fixture.
# <task> <status> <required_for> <consumes_plan_ref> <ext_status> <routes> <result_ref> <waiver_ref> <waiver_reason>
rg_write_task() {
  local task_id="$1" task_status="$2" required_for="$3" consumes_plan_ref="$4"
  local external_status="$5" required_routes="$6" result_ref="$7" waiver_ref="$8" waiver_reason="$9"
  local orch_dir="$DOCS_ROOT/orchestration/${task_id}"

  cat > "$DOCS_ROOT/task/TASK-${task_id}.md" <<EOF
# TASK-${task_id}

- title: Integration contract fixture
- objective: exercise the review gate
- acceptance_criteria: gate verdict observed
- non_goals: production docs
- affected_modules: docs
- interfaces_changed: none
- data_migrations: none
- test_scope: bats
- risks: low
- risk_level: low
- consumes_plan_ref: ${consumes_plan_ref}
- status: ${task_status}
- owner: test
- due_date:
- axis_why: integration contract
- axis_where: docs fixture
- axis_verify: bats
EOF
  rg_ensure_plan "$task_id" v1.0
  mkdir -p "$orch_dir"
  cat > "$orch_dir/ORCH.md" <<EOF
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
- supervisor_agent: main-thread-supervising-lead-architect
- planner_agents:
- reviewer_agents:
- implementation_agents:
- validation_agents:
- owned_scopes:
- delegation_status: planned
- delegation_note: integration fixture is solo
- risk_preflight_status: pass
- risk_preflight_recorded_by: main-thread
- risk_preflight_summary: no external side effect in fixture
- approval_required: false
- approval_ref: not_required
- approved_next_step: not_required
- last_updated: 2026-01-01T00:00:00Z
EOF
  # idempotent: the fixture can be rewritten after a wrapper run without duplicating the row
  grep -vF -- "- TASK-${task_id} " "$DOCS_ROOT/task/task-index.md" > "$DOCS_ROOT/task/task-index.md.tmp" || true
  mv "$DOCS_ROOT/task/task-index.md.tmp" "$DOCS_ROOT/task/task-index.md"
  printf '%s\n' "- TASK-${task_id} ${task_status}" >> "$DOCS_ROOT/task/task-index.md"
}

rg_write_decision() {
  local task_id="$1" decision_id="$2" decision_status="$3" chosen_by="$4" linked_task="$5"
  mkdir -p "$DOCS_ROOT/decisions"
  cat > "$DOCS_ROOT/decisions/decision-${decision_id}.md" <<EOF
# decision-${decision_id}

- decision_id: ${decision_id}
- title: Waive external review for ${task_id}
- date: 2026-01-01
- scope_type: task
- status: ${decision_status}
- chosen_by: ${chosen_by}
- linked_task: ${linked_task}
- context: external review is unavailable for ${task_id}
- selected_option: waive the implementation_start external review
- rationale: recorded user decision for the waiver fixture
- risk_level: low
- last_updated: 2026-01-01T00:00:00Z
EOF
}

# Overwrite one evidence file's response and keep the manifest coherent (hash + verdict), so a
# test can hand the verifier a forged-but-consistent set around ANY response text.
rg_forge_response() {
  local task_id="$1" review_round="$2" slug="$3" response_text="$4" verdict="$5"
  local dir
  dir="$(rg_evidence_dir "$task_id" v1.0 "$review_round")"
  printf '%s\n' "$response_text" > "$dir/${slug}.response.md"
  sed -i.bak "s#^- response_sha256: .*#- response_sha256: $(sha256_file_ref "$dir/${slug}.response.md")#; s#^- verdict: .*#- verdict: ${verdict}#" "$dir/${slug}.response.provenance.md"
  rm -f "${dir:?}/${slug}.response.provenance.md.bak"
}
