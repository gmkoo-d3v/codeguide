
# codeguide operational stability tests

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
DOC_GARDEN="$SCRIPTS_DIR/doc_garden.sh"
VALIDATE="$SCRIPTS_DIR/validate_docs.sh"
RUN_CODEGUIDE="$SCRIPTS_DIR/run_codeguide.sh"
RUN_EXTERNAL_REVIEWS="$SCRIPTS_DIR/run_external_plan_reviews.sh"
EXTERNAL_REVIEW_RUNNER="$SCRIPTS_DIR/external_review_runner.py"
INIT_SCAFFOLD="$SCRIPTS_DIR/init_docs_scaffold.sh"
CHECK_ENGLISH_DOCS="$SCRIPTS_DIR/check_english_docs.sh"
SHADOW_PROBE="$SCRIPTS_DIR/shadow_evidence_probe.py"
SHADOW_QUEUE="$SCRIPTS_DIR/shadow_review_queue.py"
SHADOW_LLM_CANDIDATE="$SCRIPTS_DIR/shadow_llm_candidate_wrapper.py"
SHADOW_USER_DECISION="$SCRIPTS_DIR/shadow_user_decision_wrapper.py"
SHADOW_APPLY_GATE="$SCRIPTS_DIR/shadow_apply_gate.py"
SHADOW_EFFECT_WRITER="$SCRIPTS_DIR/shadow_effect_writer.py"
SHADOW_POLICY_LOADER="$SCRIPTS_DIR/shadow_policy_loader.py"
SHADOW_V2_SKELETON="$SCRIPTS_DIR/shadow_v2_gate_skeleton.py"
SHADOW_V2_USER_DECISION="$SCRIPTS_DIR/shadow_v2_user_decision_assistant.py"
SHADOW_V2_REVIEW_PACKET="$SCRIPTS_DIR/shadow_v2_review_packet_generator.py"
SHADOW_V2_PIPELINE="$SCRIPTS_DIR/shadow_v2_pipeline_wrapper.py"
source "$SCRIPTS_DIR/codeguide_paths.sh"

docs_root_for_project() {
  local project_root="$1"
  local project_root_abs

  project_root_abs="$(codeguide_resolve_project_root "$project_root")"
  codeguide_docs_root "$project_root_abs"
}

sha256_file_ref() {
  python3 -c 'import hashlib,sys; p=sys.argv[1]; print("sha256:"+hashlib.sha256(open(p,"rb").read()).hexdigest())' "$1"
}

sha256_text_ref() {
  python3 -c 'import hashlib,sys; print("sha256:"+hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest())' "$1"
}

sha256_json_file_ref() {
  python3 -c 'import hashlib,json,sys; value=json.load(open(sys.argv[1])); encoded=json.dumps(value,sort_keys=True,separators=(",",":")); print("sha256:"+hashlib.sha256(encoded.encode("utf-8")).hexdigest())' "$1"
}

parser_identity_ref() {
  printf 'shadow_evidence_probe.py:%s:%s' "$1" "$2"
}

external_handoff_dir() {
  local task_id="$1"
  local plan_version="$2"
  local review_round="$3"

  find "$DOCS_ROOT/orchestration/${task_id}/external-cli" \
    -mindepth 2 \
    -maxdepth 2 \
    -type d \
    -path "*/${plan_version}/${review_round}" \
    | sort \
    | tail -n 1
}

setup() {
  # Tests must not inherit environment markers from the calling shell: an
  # exported CODEX_SANDBOX* flips the external-review sandbox guard and fails
  # unrelated tests, CODEGUIDE_SOURCE_ROOT poisons scaffold root resolution,
  # and CODEGUIDE_*_BIN overrides reroute runner binaries. Tests that need any
  # of these inject them explicitly per invocation (e.g. `env CODEX_SANDBOX=1`).
  unset CODEX_SANDBOX CODEX_SANDBOX_NETWORK_DISABLED
  unset CODEGUIDE_SOURCE_ROOT
  unset CODEGUIDE_ANTIGRAVITY_BIN CODEGUIDE_CLAUDE_BIN CODEGUIDE_CODEX_BIN

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

create_mock_external_review_artifact() {
  local task_id="$1"
  # The close gate only accepts antigravity/agy evaluators, so the fixture runs
  # with a codex primary to place agy in the cross-vendor reviewer set
  # (vendor defaults resolve to agy:current + claude:current response slugs).
  local reviewer="${2:-agy-current}"
  local plan_version="v1.0"
  local review_round="r01"
  local plan_file="$DOCS_ROOT/plan/PLAN-${task_id}-${plan_version}.md"
  local mock_bin="$TEST_WORKSPACE/mock-bin-${task_id}"
  local run_output="$TEST_WORKSPACE/${task_id}-external-review.out"
  local handoff_dir

  cat > "$plan_file" <<EOF
# PLAN-${task_id}-${plan_version}

- task_id: ${task_id}
- plan_version: ${plan_version}
- objective: create wrapper-generated external review artifacts
- scope: test fixture generation
- assumptions: mock agy CLI returns parser-compatible accept responses
- risks: fixture generation failure
- acceptance_signals: response and provenance files are written
- stop_conditions: wrapper completes
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  mkdir -p "$mock_bin"
  # Mock EVERY registry runner binary so no test ever invokes a real external
  # CLI (hermetic tests double as the egress guard: a real codex/claude call
  # from a fixture is an unapproved external-service invocation).
  write_mock_cli "$mock_bin/agy" '#!/usr/bin/env bash
cat <<EOF
- verdict: accept
- summary: Mock agy accepts the bounded review packet.
- strengths: The handoff is constrained.
- risks: This is a deterministic test fixture.
- requested_changes: None.
EOF'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
cat <<EOF
- verdict: accept
- summary: Mock claude accepts the bounded review packet.
- strengths: The handoff is constrained.
- risks: This is a deterministic test fixture.
- requested_changes: None.
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
- verdict: accept
- summary: Mock codex accepts the bounded review packet.
- strengths: The handoff is constrained.
- risks: This is a deterministic test fixture.
- requested_changes: None.
EOF'

  env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "$task_id" \
    --plan-version "$plan_version" \
    --primary-tool "codex" \
    --reviewer "agy-current" \
    --review-round "$review_round" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-${task_id}" \
    --approved-next-step "run external review ${task_id} ${plan_version} ${review_round}" \
    > "$run_output" 2>&1 || {
      cat "$run_output" >&2
      return 1
    }

  handoff_dir="$(external_handoff_dir "$task_id" "$plan_version" "$review_round")"
  if [[ -z "$handoff_dir" ]]; then
    cat "$run_output" >&2
    return 1
  fi
  printf "%s/%s.response.md\n" "$handoff_dir" "$reviewer"
}

create_mock_internal_review_artifact() {
  local task_id="$1"
  local route="${2:-internal_subagent_md_handoff}"
  local artifact="$DOCS_ROOT/report/LLM-REVIEW-${task_id}-${route}-r01.md"

  mkdir -p "$DOCS_ROOT/report"
  cat > "$artifact" <<EOF
- evaluator: internal-subagent
- review_route: ${route}
- verdict: accept
- priority_findings: none
- contract_mismatches: none
- missing_evidence: none
- residual_risks: local review artifacts are not tamper-proof
EOF
  printf "%s\n" "$artifact"
}
