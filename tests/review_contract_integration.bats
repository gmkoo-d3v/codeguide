#!/usr/bin/env bats
#
# Integration contract: the adversarial-review rebuttal rule x the evidence-verified external
# approval gate. One response must receive the same verdict from every component that reads it:
#   1. run_external_plan_reviews.sh   (parse_review_response -> artifacts, report, provenance)
#   2. validate_docs_review_evidence.py (evidence set verification)
#   3. validate_docs.sh               (--gate external-review and the strict/advisory await gate)
#   4. run_codeguide.sh               (the implementation-start transition)
#
# Adversarial field rule (references/orchestration-review-contract.md):
#   accept  : objection/counterproposal/rebuttal keys PRESENT, values may be empty; residual_risk non-empty
#   revise  : all four non-empty            blocked : all four non-empty
# revise/blocked are format-valid reviews but never approve an implementation start.
#
# Every test runs on its own temp project with mock runners only. The PATH excludes the
# directories holding the real agy/claude/codex, every CLI name has a logging tripwire, and
# teardown fails any test that fired one (see tests/review_gate_helper.bash).

load codeguide_helper
load review_gate_helper

setup() { rg_base_setup; }
teardown() { rg_teardown; }

# <task>: genuine adversarial accept with present-but-empty debate fields, task in_progress + ingested.
adv_empty_base() {
  local task="$1"
  rg_mock_body agy "$(rg_adversarial_response accept objection= counterproposal= rebuttal=)"
  rg_review "$task" v1.0 r01 adversarial agy-current
  [ "$status" -eq 0 ]
  rg_write_task "$task" in_progress implementation_start "PLAN-${task}-v1.0" ingested "agy:current" "docs/orchestration/${task}/external-cli/v1.0/r01" "" ""
  rg_gate "$task"
  [ "$status" -eq 0 ]
}

# The review-field FAIL lines the strict document check must NOT raise for a contract-valid accept.
refute_review_field_fail() {
  if grep -E '^\[FAIL\].*(objection|counterproposal|rebuttal|residual_risk)' <<<"$1"; then
    return 1
  fi
}

# ---------------------------------------------------------------------------------------------
# GUARD: nothing in this suite can reach a real external CLI
# ---------------------------------------------------------------------------------------------

@test "GUARD-01 no real agy/claude/codex/gemini/antigravity is reachable from the test PATH" {
  local name resolved
  for name in agy claude codex gemini antigravity; do
    resolved="$(PATH="$RG_PATH" command -v "$name")"
    [[ "$resolved" == "$TEST_WORKSPACE/guard/"* ]]
  done
  [[ ":$RG_PATH:" != *"/.local/bin"* ]]
  [[ ":$RG_PATH:" != *"/opt/homebrew/bin"* ]]
  [[ " ${RG_ENV[*]} " == *" CODEGUIDE_ANTIGRAVITY_BIN=$RG_MOCK_BIN/agy "* ]]
  [[ " ${RG_ENV[*]} " == *" CODEGUIDE_CLAUDE_BIN=$RG_MOCK_BIN/claude "* ]]
  [[ " ${RG_ENV[*]} " == *" CODEGUIDE_CODEX_BIN=$RG_MOCK_BIN/codex "* ]]
}

@test "GUARD-02 the tripwire records and refuses any CLI name that is not a mock" {
  run env "PATH=$RG_PATH" gemini --version
  [ "$status" -eq 97 ]
  grep -qx 'gemini --version' "$TEST_WORKSPACE/tripwire.log"
  : > "$TEST_WORKSPACE/tripwire.log"
}

# ---------------------------------------------------------------------------------------------
# A. Well-formed responses are approved by every component
# ---------------------------------------------------------------------------------------------

@test "TC-01 adversarial accept with present-but-empty debate fields: one attempt, full artifact set, evidence verified, strict gate passes" {
  rg_mock_body agy "$(rg_adversarial_response accept objection= counterproposal= rebuttal=)"
  rg_review tc01 v1.0 r01 adversarial agy-current
  [ "$status" -eq 0 ]
  assert_contains "$output" "[OK] evaluator=agy requested_route=agy:current actual_route=agy:current"
  rg_assert_first_attempt_accept tc01 agy-current r01 adversarial accept
  [ "$(rg_mock_calls agy)" -eq 1 ]

  rg_verify tc01 v1.0 r01 agy:current
  [ "$status" -eq 0 ]

  rg_write_task tc01 in_progress implementation_start PLAN-tc01-v1.0 ingested "agy:current" "docs/orchestration/tc01/external-cli/v1.0/r01" "" ""
  run env "${RG_ENV[@]}" "$VALIDATE" "$TEST_PROJECT" --mode strict
  assert_contains "$output" "[PASS] external review await gate satisfied for PLAN-tc01-v1.0"
  refute_contains "$output" "[FAIL] external review await gate"
  refute_review_field_fail "$output"
  rg_gate tc01
  [ "$status" -eq 0 ]
}

@test "TC-02 adversarial accept with every debate field filled is still approved end to end" {
  rg_mock_body agy "$(rg_adversarial_response accept)"
  rg_review tc02 v1.0 r01 adversarial agy-current
  [ "$status" -eq 0 ]
  rg_assert_first_attempt_accept tc02 agy-current r01 adversarial accept

  rg_verify tc02 v1.0 r01 agy:current
  [ "$status" -eq 0 ]
  rg_write_task tc02 in_progress implementation_start PLAN-tc02-v1.0 ingested "agy:current" "docs/orchestration/tc02/external-cli/v1.0/r01" "" ""
  run env "${RG_ENV[@]}" "$VALIDATE" "$TEST_PROJECT" --mode strict
  assert_contains "$output" "[PASS] external review await gate satisfied for PLAN-tc02-v1.0"
  refute_contains "$output" "[FAIL] external review await gate"
}

@test "TC-03 standard accept: the standard field rule is unchanged and the result passes the gate" {
  rg_mock_body agy "$(rg_standard_response accept)"
  rg_review tc03 v1.0 r01 standard agy-current
  [ "$status" -eq 0 ]
  rg_assert_first_attempt_accept tc03 agy-current r01 standard accept
  rg_verify tc03 v1.0 r01 agy:current
  [ "$status" -eq 0 ]
  rg_write_task tc03 in_progress implementation_start PLAN-tc03-v1.0 ingested "agy:current" "docs/orchestration/tc03/external-cli/v1.0/r01" "" ""
  rg_gate tc03
  [ "$status" -eq 0 ]
  assert_contains "$output" "[PASS] external review await gate satisfied for PLAN-tc03-v1.0"

  # unchanged strictness: a standard review missing a standard field is refused after the retry
  rg_mock_calls_reset
  rg_mock_body agy "$(rg_standard_response accept -strengths)"
  rg_review tc03-missing v1.0 r01 standard agy-current
  [ "$status" -ne 0 ]
  rg_assert_parse_rejected tc03-missing agy-current r01
}

# ---------------------------------------------------------------------------------------------
# B. Format and verdict
# ---------------------------------------------------------------------------------------------

@test "TC-04 adversarial accept with a MISSING debate key is rejected, unlike the same response with the key present but empty" {
  rg_mock_body agy "$(rg_adversarial_response accept objection= counterproposal= rebuttal=)"
  rg_review tc04 v1.0 r01 adversarial agy-current
  [ "$status" -eq 0 ]
  rg_assert_first_attempt_accept tc04 agy-current r01 adversarial accept

  local key
  for key in objection counterproposal rebuttal; do
    rg_mock_calls_reset
    rg_mock_body agy "$(rg_adversarial_response accept objection= counterproposal= rebuttal= "-$key")"
    rg_review "tc04-$key" v1.0 r01 adversarial agy-current
    [ "$status" -ne 0 ]
    rg_assert_parse_rejected "tc04-$key" agy-current r01
  done
}

@test "TC-05 adversarial accept with residual_risk missing or empty is rejected" {
  local variant id
  for variant in "-residual_risk" "residual_risk="; do
    id="tc05-empty"
    [ "${variant:0:1}" = "-" ] && id="tc05-missing"
    rg_mock_calls_reset
    rg_mock_body agy "$(rg_adversarial_response accept objection= counterproposal= rebuttal= "$variant")"
    rg_review "$id" v1.0 r01 adversarial agy-current
    [ "$status" -ne 0 ]
    rg_assert_parse_rejected "$id" agy-current r01
  done
}

@test "TC-06 revise and blocked: filled responses are format-valid but never approve; an empty debate value is rejected by the parser" {
  local verdict key
  for verdict in revise blocked; do
    rg_mock_calls_reset
    rg_mock_body agy "$(rg_adversarial_response "$verdict")"
    rg_review "tc06-$verdict" v1.0 r01 adversarial agy-current
    [ "$status" -eq 0 ]
    rg_assert_first_attempt_accept "tc06-$verdict" agy-current r01 adversarial "$verdict"

    rg_verify "tc06-$verdict" v1.0 r01 agy:current
    [ "$status" -eq 1 ]
    assert_contains "$output" "expected accept"
    rg_write_task "tc06-$verdict" in_progress implementation_start "PLAN-tc06-${verdict}-v1.0" ingested "agy:current" "docs/orchestration/tc06-${verdict}/external-cli/v1.0/r01" "" ""
    rg_gate "tc06-$verdict"
    [ "$status" -eq 1 ]
    assert_contains "$output" "[FAIL] external review await gate missing accepted route artifact for agy:current"

    for key in objection counterproposal rebuttal; do
      rg_mock_calls_reset
      rg_mock_body agy "$(rg_adversarial_response "$verdict" "$key=")"
      rg_review "tc06-$verdict-$key" v1.0 r01 adversarial agy-current
      [ "$status" -ne 0 ]
      rg_assert_parse_rejected "tc06-$verdict-$key" agy-current r01
    done
  done
}

# ---------------------------------------------------------------------------------------------
# C. Provenance and integrity (base: the TC-01 evidence, so the integrated path is what is attacked)
# ---------------------------------------------------------------------------------------------

@test "TC-07 an accepted response without its Request file is not approved" {
  adv_empty_base tc07
  local dir
  dir="$(rg_evidence_dir tc07 v1.0 r01)"
  rm -f "${dir:?}/agy-current.request.md"
  rg_verify tc07 v1.0 r01 agy:current
  [ "$status" -eq 1 ]
  assert_contains "$output" "companion request file is missing"
  rg_gate tc07
  [ "$status" -eq 1 ]
}

@test "TC-08 an accepted response without its Provenance manifest is not approved" {
  adv_empty_base tc08
  local dir
  dir="$(rg_evidence_dir tc08 v1.0 r01)"
  rm -f "${dir:?}/agy-current.response.provenance.md"
  rg_verify tc08 v1.0 r01 agy:current
  [ "$status" -eq 1 ]
  assert_contains "$output" "provenance manifest is missing"
  rg_gate tc08
  [ "$status" -eq 1 ]
}

@test "TC-09 a Response edited after review fails the SHA-256 binding and the gate" {
  adv_empty_base tc09
  local dir
  dir="$(rg_evidence_dir tc09 v1.0 r01)"
  printf '%s\n' "- note: edited after review" >> "$dir/agy-current.response.md"
  rg_verify tc09 v1.0 r01 agy:current
  [ "$status" -eq 1 ]
  assert_contains "$output" "response_sha256 does not match"
  rg_gate tc09
  [ "$status" -eq 1 ]
  assert_contains "$output" "[FAIL] external review await gate missing accepted route artifact for agy:current"
}

@test "TC-10 any identifier mismatch (task, plan version, round, route, request/response linkage) is rejected" {
  adv_empty_base tc10
  local dir slug=agy-current pristine="$TEST_WORKSPACE/tc10-pristine" row mutation
  dir="$(rg_evidence_dir tc10 v1.0 r01)"
  cp -R "$dir" "$pristine"
  local rows=(
    "wrong_task|provenance task_id"
    "wrong_plan_version|provenance plan_version"
    "wrong_round|provenance review_round"
    "wrong_route_requested|provenance evaluator_requested_route"
    "wrong_route_actual|provenance evaluator_actual_route"
    "request_other_route|request evaluator"
    "request_other_task|request task_id"
    "request_link|provenance request_file"
    "response_link|provenance response_file"
  )
  for row in "${rows[@]}"; do
    mutation="${row%%|*}"
    rm -rf "${dir:?}"
    cp -R "$pristine" "$dir"
    case "$mutation" in
      wrong_task) sed -i.bak 's/^- task_id: .*/- task_id: some-other-task/' "$dir/${slug}.response.provenance.md" ;;
      wrong_plan_version) sed -i.bak 's/^- plan_version: .*/- plan_version: v9.9/' "$dir/${slug}.response.provenance.md" ;;
      wrong_round) sed -i.bak 's/^- review_round: .*/- review_round: r09/' "$dir/${slug}.response.provenance.md" ;;
      wrong_route_requested) sed -i.bak 's/^- evaluator_requested_route: .*/- evaluator_requested_route: claude:current/' "$dir/${slug}.response.provenance.md" ;;
      wrong_route_actual) sed -i.bak 's/^- evaluator_actual_route: .*/- evaluator_actual_route: claude:current/' "$dir/${slug}.response.provenance.md" ;;
      request_other_route) sed -i.bak 's/^- evaluator: .*/- evaluator: claude:current/' "$dir/${slug}.request.md" ;;
      request_other_task) sed -i.bak 's/^- task_id: .*/- task_id: some-other-task/' "$dir/${slug}.request.md" ;;
      request_link) sed -i.bak 's#^- request_file: .*#- request_file: /elsewhere/other.request.md#' "$dir/${slug}.response.provenance.md" ;;
      response_link) sed -i.bak 's#^- response_file: .*#- response_file: /elsewhere/other.response.md#' "$dir/${slug}.response.provenance.md" ;;
    esac
    rm -f "${dir:?}"/*.bak
    rg_gate tc10
    if [ "$status" -ne 1 ]; then
      printf 'mutation %s was NOT rejected (status=%s)\n%s\n' "$mutation" "$status" "$output" >&2
      return 1
    fi
    if [[ "$output" != *"${row#*|}"* ]]; then
      printf 'mutation %s rejected for the wrong reason (wanted: %s)\n%s\n' "$mutation" "${row#*|}" "$output" >&2
      return 1
    fi
  done
}

# ---------------------------------------------------------------------------------------------
# D. The real transition: run_codeguide.sh
# ---------------------------------------------------------------------------------------------

@test "TC-11 run_codeguide refuses the in_progress transition without an approved review: non-zero, no runtime, no state or metadata change" {
  rg_write_task tc11 planned implementation_start PLAN-tc11-v1.0 requested "agy:current" "" "" ""
  local marker="$TEST_WORKSPACE/runtime-ran-tc11" allow="$TEST_WORKSPACE/allow-tc11.txt" orch before
  orch="$DOCS_ROOT/orchestration/tc11/ORCH.md"
  printf 'touch\n' > "$allow"
  before="$(shasum -a 256 < "$orch")"

  run env "${RG_ENV[@]}" "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id tc11 --mode advisory \
    --task-status in_progress --change-scope code-or-runtime \
    --runtime-test-cmd "touch $marker" --runtime-allow-list "$allow"

  [ "$status" -ne 0 ]
  assert_contains "$output" "[BLOCKED] external review gate"
  [ ! -e "$marker" ]
  run grep '^- status: planned' "$DOCS_ROOT/task/TASK-tc11.md"
  [ "$status" -eq 0 ]
  [ "$(shasum -a 256 < "$orch")" = "$before" ]
  [ "$(rg_mock_calls)" -eq 0 ]
}

@test "TC-12 after an approved empty-debate adversarial accept, run_codeguide enters in_progress and runs only the allowed mock runtime command" {
  rg_mock_body agy "$(rg_adversarial_response accept objection= counterproposal= rebuttal=)"
  rg_review tc12 v1.0 r01 adversarial agy-current
  [ "$status" -eq 0 ]
  rg_write_task tc12 planned implementation_start PLAN-tc12-v1.0 ingested "agy:current" "docs/orchestration/tc12/external-cli/v1.0/r01" "" ""
  local marker="$TEST_WORKSPACE/runtime-ran-tc12" allow="$TEST_WORKSPACE/allow-tc12.txt"
  printf 'touch\n' > "$allow"

  run env "${RG_ENV[@]}" "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id tc12 --mode advisory \
    --task-status in_progress --change-scope code-or-runtime \
    --runtime-lint-cmd "echo not-allowed" \
    --runtime-test-cmd "touch $marker" --runtime-allow-list "$allow"

  [ "$status" -eq 0 ]
  assert_contains "$output" "[PASS] external review await gate satisfied for PLAN-tc12-v1.0"
  [ -e "$marker" ]
  assert_contains "$output" "[BLOCKED] lint command 'echo not-allowed' is not in allow-list"
  refute_contains "$output" "[RUN] Runtime lint"
  run grep '^- status: in_progress' "$DOCS_ROOT/task/TASK-tc12.md"
  [ "$status" -eq 0 ]
  # the only CLI call was the review itself; run_codeguide made none
  [ "$(rg_mock_calls)" -eq 1 ]
}

@test "TC-13 with two required routes, implementation is blocked until BOTH are genuine accepts" {
  local ref="docs/orchestration/tc13/external-cli/v1.0/r01" routes="agy:current, claude:current"
  local marker="$TEST_WORKSPACE/runtime-ran-tc13" allow="$TEST_WORKSPACE/allow-tc13.txt"
  printf 'touch\n' > "$allow"

  rg_mock_body agy "$(rg_adversarial_response accept objection= counterproposal= rebuttal=)"
  rg_review tc13 v1.0 r01 adversarial agy-current
  [ "$status" -eq 0 ]

  # (a) the second route has no evidence at all
  rg_write_task tc13 planned implementation_start PLAN-tc13-v1.0 ingested "$routes" "$ref" "" ""
  rg_gate tc13 in_progress
  [ "$status" -eq 1 ]
  assert_contains "$output" "missing accepted route artifact for claude:current"
  run env "${RG_ENV[@]}" "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id tc13 --mode advisory --task-status in_progress \
    --change-scope code-or-runtime --runtime-test-cmd "touch $marker" --runtime-allow-list "$allow"
  [ "$status" -ne 0 ]
  [ ! -e "$marker" ]

  # (b) the second route answered REVISE (a genuine, format-valid review)
  rg_mock_body claude "$(rg_adversarial_response revise)"
  rg_review tc13 v1.0 r01 adversarial claude-current
  [ "$status" -eq 0 ]
  rg_write_task tc13 planned implementation_start PLAN-tc13-v1.0 ingested "$routes" "$ref" "" ""
  rg_gate tc13 in_progress
  [ "$status" -eq 1 ]
  assert_contains "$output" "claude:current"

  # (c) the second route answered BLOCKED
  rg_mock_body claude "$(rg_adversarial_response blocked)"
  rg_review tc13 v1.0 r01 adversarial claude-current
  [ "$status" -eq 0 ]
  rg_write_task tc13 planned implementation_start PLAN-tc13-v1.0 ingested "$routes" "$ref" "" ""
  rg_gate tc13 in_progress
  [ "$status" -eq 1 ]

  # (d) the second route is an accept the wrapper itself refused (incomplete): response file, no provenance
  rg_mock_body claude "- verdict: accept"
  rg_review tc13 v1.0 r01 adversarial claude-current
  [ "$status" -ne 0 ]
  rg_write_task tc13 planned implementation_start PLAN-tc13-v1.0 ingested "$routes" "$ref" "" ""
  rg_gate tc13 in_progress
  [ "$status" -eq 1 ]

  # (e) both routes genuine accepts: the transition is allowed
  rg_mock_body claude "$(rg_adversarial_response accept objection= counterproposal= rebuttal=)"
  rg_review tc13 v1.0 r01 adversarial claude-current
  [ "$status" -eq 0 ]
  rg_write_task tc13 planned implementation_start PLAN-tc13-v1.0 ingested "$routes" "$ref" "" ""
  run env "${RG_ENV[@]}" "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id tc13 --mode advisory --task-status in_progress \
    --change-scope code-or-runtime --runtime-test-cmd "touch $marker" --runtime-allow-list "$allow"
  [ "$status" -eq 0 ]
  assert_contains "$output" "[PASS] external review await gate satisfied for PLAN-tc13-v1.0"
  [ -e "$marker" ]
}

@test "TC-14 a status carrying a note (in_progress (resumed)) cannot bypass an unapproved review" {
  rg_write_task tc14 "in_progress (resumed)" implementation_start PLAN-tc14-v1.0 requested "agy:current" "" "" ""
  local marker="$TEST_WORKSPACE/runtime-ran-tc14" allow="$TEST_WORKSPACE/allow-tc14.txt"
  printf 'touch\n' > "$allow"

  run env "${RG_ENV[@]}" "$VALIDATE" "$TEST_PROJECT" --mode advisory
  assert_contains "$output" "[WARN] external review await gate not satisfied for TASK-tc14: external_review_status=requested"
  run env "${RG_ENV[@]}" "$VALIDATE" "$TEST_PROJECT" --mode strict
  assert_contains "$output" "[FAIL] external review await gate not satisfied for TASK-tc14: external_review_status=requested"

  run env "${RG_ENV[@]}" "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id tc14 --mode advisory --task-status in_progress \
    --change-scope code-or-runtime --runtime-test-cmd "touch $marker" --runtime-allow-list "$allow"
  [ "$status" -ne 0 ]
  assert_contains "$output" "[BLOCKED] external review gate"
  [ ! -e "$marker" ]
}

# ---------------------------------------------------------------------------------------------
# E. Existing behavior that must survive the integration
# ---------------------------------------------------------------------------------------------

@test "TC-15 a default-option run_codeguide leaves an existing external_cli ORCH approval and review metadata intact" {
  local task=tc15 orch="$DOCS_ROOT/orchestration/tc15/ORCH.md" key
  run env "${RG_ENV[@]}" "$DOC_GARDEN" "$TEST_PROJECT" --task-id "$task" --task-title "Seeded" \
    --execution-mode supervisor_subagents --primary-author-tool codex --review-mode external_cli \
    --risk-preflight-status approved --risk-preflight-summary "user approved the external review of ${task}" \
    --approval-ref "user-approval-${task}" --approved-next-step "run external review for ${task}" \
    --planner-agents planner-a --reviewer-agents "external-cli:agy:current" \
    --implementation-agents impl-a --validation-agents val-a --owned-scopes scope-a \
    --delegation-note "Seeded review capsule."
  [ "$status" -eq 0 ]
  local -a keys=(execution_mode review_mode risk_preflight_status approval_required approval_ref approved_next_step risk_preflight_summary supervisor_agent delegation_note)
  local -a before=()
  for key in "${keys[@]}"; do before+=("$(rg_field "$orch" "$key")"); done
  [ "${before[0]}" = "supervisor_subagents" ]
  [ "${before[2]}" = "approved" ]

  run env "${RG_ENV[@]}" "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "$task" --mode advisory
  [ "$status" -eq 0 ]
  local i
  for i in "${!keys[@]}"; do
    [ "$(rg_field "$orch" "${keys[$i]}")" = "${before[$i]}" ]
  done
  refute_contains "$output" "orchestration review_mode=external_cli requires risk_preflight_status=approved"
}

@test "TC-16 a waiver is honoured only for an existing accepted user decision linked to the task" {
  rg_write_decision tc16 ok accepted user TASK-tc16
  rg_write_task tc16 in_progress implementation_start PLAN-tc16-v1.0 waived "agy:current" "" "docs/decisions/decision-ok.md" "user accepted the waiver"
  rg_gate tc16
  [ "$status" -eq 0 ]
  assert_contains "$output" "[PASS] external review await gate waived with a verified user decision"

  # the same ref cannot be reused by another task
  rg_write_task tc16-other in_progress implementation_start PLAN-tc16-other-v1.0 waived "agy:current" "" "docs/decisions/decision-ok.md" "user accepted the waiver"
  rg_gate tc16-other
  [ "$status" -eq 1 ]
  assert_contains "$output" "linked_task must be TASK-tc16-other"

  # a ref to no file, a proposed decision, and a decision chosen by an agent are all refused
  rg_write_task tc16 in_progress implementation_start PLAN-tc16-v1.0 waived "agy:current" "" "docs/decisions/decision-never-written.md" "user accepted the waiver"
  rg_gate tc16
  [ "$status" -eq 1 ]
  assert_contains "$output" "does not resolve to an existing decision record"
  rg_write_decision tc16 proposed proposed user TASK-tc16
  rg_write_task tc16 in_progress implementation_start PLAN-tc16-v1.0 waived "agy:current" "" "docs/decisions/decision-proposed.md" "user accepted the waiver"
  rg_gate tc16
  [ "$status" -eq 1 ]
  rg_write_decision tc16 agent accepted codex TASK-tc16
  rg_write_task tc16 in_progress implementation_start PLAN-tc16-v1.0 waived "agy:current" "" "docs/decisions/decision-agent.md" "user accepted the waiver"
  rg_gate tc16
  [ "$status" -eq 1 ]
  assert_contains "$output" "chosen_by must be user"
}

# ---------------------------------------------------------------------------------------------
# PARITY: the wrapper and the approval path never contradict each other on the same response
# ---------------------------------------------------------------------------------------------

@test "PARITY-01 for every response variant the wrapper parser and the evidence verifier agree" {
  # style|verdict|overrides (space separated)|wrapper parses it (ok/rej)|verifier approves it (ok/rej)
  local -a table=(
    "adv|accept||ok|ok"
    "adv|accept|objection= counterproposal= rebuttal=|ok|ok"
    "adv|accept|-objection|rej|rej"
    "adv|accept|-counterproposal|rej|rej"
    "adv|accept|-rebuttal|rej|rej"
    "adv|accept|residual_risk=|rej|rej"
    "adv|accept|-residual_risk|rej|rej"
    "adv|revise||ok|rej"
    "adv|blocked||ok|rej"
    "adv|revise|rebuttal=|rej|rej"
    "adv|blocked|objection=|rej|rej"
    "std|accept||ok|ok"
    "std|accept|-strengths|rej|rej"
  )
  # authentic bases the verifier is later handed forged-but-coherent responses around
  rg_mock_body agy "$(rg_adversarial_response accept)"
  rg_review par-adv v1.0 r01 adversarial agy-current
  [ "$status" -eq 0 ]
  rg_mock_body agy "$(rg_standard_response accept)"
  rg_review par-std v1.0 r01 standard agy-current
  [ "$status" -eq 0 ]

  local row style verdict overrides wrapper verifier body task n=0 want_calls
  for row in "${table[@]}"; do
    n=$((n + 1))
    IFS='|' read -r style verdict overrides wrapper verifier <<< "$row"
    if [ "$style" = "adv" ]; then
      # shellcheck disable=SC2086
      body="$(rg_adversarial_response "$verdict" $overrides)"
    else
      # shellcheck disable=SC2086
      body="$(rg_standard_response "$verdict" $overrides)"
    fi

    # 1. the wrapper, end to end
    task="par-$n"
    rg_mock_calls_reset
    rg_mock_body agy "$body"
    if [ "$style" = "adv" ]; then rg_review "$task" v1.0 r01 adversarial agy-current; else rg_review "$task" v1.0 r01 standard agy-current; fi
    if [ "$wrapper" = "ok" ]; then
      want_calls=1
      [ "$status" -eq 0 ]
      [ -f "$(rg_evidence_dir "$task" v1.0 r01)/agy-current.response.provenance.md" ]
    else
      want_calls=2
      [ "$status" -ne 0 ]
      [ ! -e "$(rg_evidence_dir "$task" v1.0 r01)/agy-current.response.provenance.md" ]
    fi
    if [ "$(rg_mock_calls)" -ne "$want_calls" ]; then
      printf 'variant %s: wrapper made %s CLI calls, expected %s\n' "$row" "$(rg_mock_calls)" "$want_calls" >&2
      return 1
    fi

    # 2. the verifier on the same response text inside a coherent forged set
    local base=par-adv
    [ "$style" = "std" ] && base=par-std
    rg_forge_response "$base" r01 agy-current "$body" "$verdict"
    rg_verify "$base" v1.0 r01 agy:current
    if [ "$verifier" = "ok" ] && [ "$status" -ne 0 ]; then
      printf 'variant %s: wrapper=%s but verifier REJECTED: %s\n' "$row" "$wrapper" "$output" >&2
      return 1
    fi
    if [ "$verifier" = "rej" ] && [ "$status" -eq 0 ]; then
      printf 'variant %s: wrapper=%s but verifier APPROVED\n' "$row" "$wrapper" >&2
      return 1
    fi
  done
}

# ---------------------------------------------------------------------------------------------
# E. The review is bound to the plan it read and the request it answered (plan_sha256, request_sha256)
#    These two used to be pinned as known limitations KL-1 and KL-2; the manifest now records both
#    hashes and the verifier recomputes them, so an edit after the review is refused.
# ---------------------------------------------------------------------------------------------

@test "TC-17 a PLAN edited after its review is refused by the verifier and the gate (plan_sha256)" {
  adv_empty_base tc17
  printf '\n%s\n' "- note: plan changed after the external review accepted it" >> "$DOCS_ROOT/plan/PLAN-tc17-v1.0.md"
  rg_verify tc17 v1.0 r01 agy:current
  [ "$status" -ne 0 ]
  assert_contains "$output" "provenance plan_sha256 does not match PLAN-tc17-v1.0.md"
  rg_gate tc17
  [ "$status" -eq 1 ]
  assert_contains "$output" "plan_sha256 does not match"
}

@test "TC-18 an altered Request payload is refused by the verifier and the gate (request_sha256)" {
  adv_empty_base tc18
  printf '%s\n' "payload line added after the review ran" >> "$(rg_evidence_dir tc18 v1.0 r01)/agy-current.request.md"
  rg_verify tc18 v1.0 r01 agy:current
  [ "$status" -ne 0 ]
  assert_contains "$output" "provenance request_sha256 does not match the request file"
  rg_gate tc18
  [ "$status" -eq 1 ]
  assert_contains "$output" "request_sha256 does not match"
}

@test "TC-19 a manifest recorded before plan and request hashing is refused: the reason asks for a new review round" {
  adv_empty_base tc19
  local provenance
  provenance="$(rg_evidence_dir tc19 v1.0 r01)/agy-current.response.provenance.md"
  sed -i.bak '/^- request_sha256:/d; /^- plan_sha256:/d' "$provenance"
  rm -f "$provenance.bak"
  rg_verify tc19 v1.0 r01 agy:current
  [ "$status" -ne 0 ]
  assert_contains "$output" "provenance request_sha256 is missing"
  assert_contains "$output" "provenance plan_sha256 is missing"
  assert_contains "$output" "run a new review round"
  rg_gate tc19
  [ "$status" -eq 1 ]
}

@test "TC-20 a request whose recorded plan hash disagrees with the manifest is refused" {
  adv_empty_base tc20
  local request provenance
  request="$(rg_evidence_dir tc20 v1.0 r01)/agy-current.request.md"
  provenance="$(rg_evidence_dir tc20 v1.0 r01)/agy-current.response.provenance.md"
  sed -i.bak 's#^- plan_sha256: .*#- plan_sha256: sha256:0000000000000000000000000000000000000000000000000000000000000000#' "$request"
  rm -f "$request.bak"
  # re-bind request_sha256 to the edited request so only the plan-hash disagreement remains
  sed -i.bak "s#^- request_sha256: .*#- request_sha256: $(sha256_file_ref "$request")#" "$provenance"
  rm -f "$provenance.bak"
  rg_verify tc20 v1.0 r01 agy:current
  [ "$status" -ne 0 ]
  assert_contains "$output" "request plan_sha256 disagrees with the provenance plan_sha256"
}

@test "TC-21 a missing plan file cannot be verified, so the review is refused rather than assumed current" {
  adv_empty_base tc21
  mv "$DOCS_ROOT/plan/PLAN-tc21-v1.0.md" "$DOCS_ROOT/plan/PLAN-tc21-v1.0.md.moved"
  rg_verify tc21 v1.0 r01 agy:current
  [ "$status" -ne 0 ]
  assert_contains "$output" "plan_sha256 cannot be verified"
}

# ---------------------------------------------------------------------------------------------
# KNOWN LIMITATIONS: pinned CURRENT behaviour, not fixes. Each of these passes today because the
# contract does not cover it; strengthening any of them should make its test fail on purpose and
# be replaced by a real test. They are tracked in the plan of the integration task.
# ---------------------------------------------------------------------------------------------

@test "KNOWN-LIMITATION KL-3 work that skips the harness is not gated: a planning-only run on an unapproved review exits 0" {
  rg_write_task kl3 planned implementation_start PLAN-kl3-v1.0 requested "agy:current" "" "" ""
  run env "${RG_ENV[@]}" "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id kl3 --mode advisory --task-status planned
  [ "$status" -eq 0 ]
  refute_contains "$output" "[BLOCKED] external review gate"
}

@test "KNOWN-LIMITATION KL-4 an agent that leaves external_review_required_for empty makes the task look review-free" {
  rg_write_task kl4 in_progress "" PLAN-kl4-v1.0 requested "agy:current" "" "" ""
  rg_gate kl4
  [ "$status" -eq 0 ]
  assert_contains "$output" "[PASS] external review gate not required for TASK-kl4"
}

@test "KNOWN-LIMITATION KL-5 a done task's approval history is not re-checked (strict ignores it, the gate skips it)" {
  rg_write_task kl5 done implementation_start PLAN-kl5-v1.0 requested "agy:current" "" "" ""
  rg_gate kl5
  [ "$status" -eq 0 ]
  assert_contains "$output" "task is already done"
  run env "${RG_ENV[@]}" "$VALIDATE" "$TEST_PROJECT" --mode strict
  refute_contains "$output" "external review await gate"
}
