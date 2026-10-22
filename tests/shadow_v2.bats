#!/usr/bin/env bats

load codeguide_helper

@test "shadow_v2_gate_skeleton prints a no-write Phase 0 contract" {
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-before.txt"

  run python3 "$SHADOW_V2_SKELETON" --project-root "$TEST_PROJECT" --print-contract

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" '"phase":"shadow_v2_phase0_gate_skeleton"'
  assert_contains "$output" '"writes_shadow_docs":false'
  assert_contains "$output" '"auto_promotes_facts":false'
  assert_contains "$output" '"batch_apply_enabled":false'
  assert_contains "$output" 'user_decision_assistant'
  assert_contains "$output" 'review_packet_generator'
  assert_contains "$output" 'supervised_pipeline_wrapper'

  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-v2-before.txt" "$TEST_WORKSPACE/shadow-v2-after.txt"
  [ "$status" -eq 0 ]
}

@test "shadow_v2_gate_skeleton activates hints only after project scope is verified" {
  local fresh_project="$TEST_WORKSPACE/unscaffolded-repo"
  mkdir -p "$fresh_project"

  run python3 "$SHADOW_V2_SKELETON" --project-root "$fresh_project" --check-scope

  [ "$status" -eq 1 ]
  assert_contains "$output" "docs_root must exist before automatic hint lookup"
  assert_contains "$output" '"allowed":false'
  assert_contains "$output" '"mode":"hint_only"'

  run python3 "$SHADOW_V2_SKELETON" --project-root "$TEST_PROJECT" --project-id "test-project" --check-scope

  [ "$status" -eq 0 ]
  assert_contains "$output" '"allowed":true'
  assert_contains "$output" '"trigger":"project_scope_verified"'
  assert_contains "$output" '"project_identity":"test-project"'
}

@test "shadow_v2_gate_skeleton blocks external review by default and disables batch apply" {
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --record-count 2 \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "external antigravity review requires explicit user request"
  assert_contains "$output" "batch apply is disabled in Phase 0"
  assert_contains "$output" '"writes_shadow_docs":false'

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "external antigravity review requires concrete approval_ref"
  assert_contains "$output" "external antigravity review requires approved_next_step"
  assert_contains "$output" "external antigravity review requires main-thread recorded_by"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "generate external review packet only" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --print-contract

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
}

@test "shadow_v2_gate_skeleton blocks combined close when required external review is blocked" {
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --blocked-review "external_antigravity" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"blocked"'
  assert_contains "$output" "required review route is blocked: external_antigravity"
  assert_contains "$output" "stop without substituting another reviewer route"
  assert_contains "$output" "sub-agent acceptance cannot substitute for blocked external antigravity review"
  assert_contains "$output" '"combined_review_close_gate":"all_required_routes_must_complete"'

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --blocked-review "external_antigravity=platform_permission_blocked" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "required review route is blocked: external_antigravity (platform_permission_blocked)"
  assert_contains "$output" "switch permission mode"
  assert_contains "$output" '"blocked_review_reasons":{"external_antigravity":"platform_permission_blocked"}'

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "required review route is missing: external_antigravity"
}

@test "shadow_v2_gate_skeleton requires durable accepted internal review artifact before close completion" {
  local internal_artifact
  local non_markdown_artifact="$DOCS_ROOT/report/LLM-REVIEW-shadow-v2-internal-close.txt"
  internal_artifact="$(create_mock_internal_review_artifact "shadow-v2-internal-close")"
  cat > "$non_markdown_artifact" <<'EOF'
- verdict: accept
- priority_findings: none
- contract_mismatches: none
- missing_evidence: none
- residual_risks: none
EOF

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --completed-review "internal_subagent_md_handoff" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "completed internal review route requires a durable response artifact: internal_subagent_md_handoff"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$non_markdown_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "completed internal review artifact must be a Markdown .md file"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --print-contract

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" '"completed_review_artifacts":'
  assert_contains "$output" '"sha256":"sha256:'
}

@test "shadow_v2_gate_skeleton requires durable accepted external review artifact before close completion" {
  local stub_artifact="$TEST_WORKSPACE/external-stub-review.md"
  local empty_dir="$DOCS_ROOT/orchestration/shadow-v2-close/external-cli/v1.0/r-empty"
  local blocked_dir="$DOCS_ROOT/orchestration/shadow-v2-close/external-cli/v1.0/r-blocked"
  local no_manifest_dir="$DOCS_ROOT/orchestration/shadow-v2-close/external-cli/v1.0/r-no-manifest"
  local thin_dir="$DOCS_ROOT/orchestration/shadow-v2-close/external-cli/v1.0/r-thin"
  local empty_artifact="$empty_dir/agy.response.md"
  local blocked_artifact="$blocked_dir/agy.response.md"
  local no_manifest_artifact="$no_manifest_dir/agy.response.md"
  local thin_artifact="$thin_dir/agy.response.md"
  local internal_artifact
  local accepted_artifact
  mkdir -p "$empty_dir" "$blocked_dir" "$no_manifest_dir" "$thin_dir"
  cat > "$stub_artifact" <<'EOF'
evaluator: agy
verdict: accept
priority_findings: none
EOF
  : > "$empty_artifact"
  cat > "$empty_dir/agy.request.md" <<EOF
evaluator: agy
command_response_path: $empty_dir/agy.command-response.raw.md
sanitized_response_file: $empty_artifact
EOF
  cat > "$blocked_artifact" <<'EOF'
evaluator: agy
verdict: blocked
status: blocked
EOF
  cat > "$blocked_dir/agy.request.md" <<EOF
evaluator: agy
command_response_path: $blocked_dir/agy.command-response.raw.md
sanitized_response_file: $blocked_artifact
EOF
  local blocked_hash
  blocked_hash="$(sha256_file_ref "$blocked_artifact")"
  cat > "$blocked_dir/agy.response.provenance.md" <<EOF
artifact_kind: external_cli_review_response_provenance
generated_by: run_external_plan_reviews.sh
evaluator: agy
verdict: blocked
request_file: $blocked_dir/agy.request.md
response_file: $blocked_artifact
response_sha256: $blocked_hash
command_response_path: $blocked_dir/agy.command-response.raw.md
raw_capture_deleted: true
sanitized_response: true
EOF
  cat > "$no_manifest_artifact" <<'EOF'
evaluator: agy
verdict: accept
priority_findings: none
EOF
  cat > "$no_manifest_dir/agy.request.md" <<EOF
evaluator: agy
command_response_path: $no_manifest_dir/agy.command-response.raw.md
sanitized_response_file: $no_manifest_artifact
EOF
  cat > "$thin_artifact" <<'EOF'
evaluator: agy
verdict: accept
EOF
  cat > "$thin_dir/agy.request.md" <<EOF
evaluator: agy
command_response_path: $thin_dir/agy.command-response.raw.md
sanitized_response_file: $thin_artifact
EOF
  local thin_hash
  thin_hash="$(sha256_file_ref "$thin_artifact")"
  cat > "$thin_dir/agy.response.provenance.md" <<EOF
artifact_kind: external_cli_review_response_provenance
generated_by: run_external_plan_reviews.sh
review_style: standard
evaluator: agy
verdict: accept
request_file: $thin_dir/agy.request.md
response_file: $thin_artifact
response_sha256: $thin_hash
command_response_path: $thin_dir/agy.command-response.raw.md
raw_capture_deleted: true
sanitized_response: true
EOF
  accepted_artifact="$(create_mock_external_review_artifact "shadow-v2-close-accepted" "agy-current")"
  internal_artifact="$(create_mock_internal_review_artifact "shadow-v2-close-internal")"
  [ -n "$accepted_artifact" ]
  [ -n "$internal_artifact" ]
  run test -f "$accepted_artifact"
  [ "$status" -eq 0 ]
  run test -f "${accepted_artifact%.md}.provenance.md"
  [ "$status" -eq 0 ]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "completed external antigravity review requires a durable response artifact"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$stub_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "completed external antigravity review artifact must be under docs/orchestration/<task-id>/external-cli"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$no_manifest_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "completed external antigravity review artifact requires provenance manifest"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$thin_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "completed external antigravity review artifact requires parser-compatible field summary"
  assert_contains "$output" "completed external antigravity review artifact requires parser-compatible field requested_changes"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$empty_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "completed review artifact must be non-empty for route external_antigravity"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$blocked_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "completed external antigravity review artifact verdict must be accept"
  assert_contains "$output" "completed external antigravity review artifact contains blocked/error/no-response marker"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$accepted_artifact" \
    --print-contract

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" '"sha256":"sha256:'
  assert_contains "$output" '"evaluator":"agy"'
  assert_contains "$output" '"request_file":'
  assert_contains "$output" '"command_response_path":'
  assert_contains "$output" '"provenance_file":'
}

@test "shadow_v2_gate_skeleton ignores optional blocked external close route" {
  local internal_artifact
  internal_artifact="$(create_mock_internal_review_artifact "shadow-v2-optional-external")"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --blocked-review "external_antigravity" \
    --print-contract

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  refute_contains "$output" "sub-agent acceptance cannot substitute for blocked external antigravity review"
}

@test "shadow_v2_gate_skeleton rejects hint evidence for confirmed facts" {
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --target-status "confirmed" \
    --evidence-type "auxiliary_hint" \
    --evidence-type "source_probe" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "evidence_type cannot confirm facts in v2 gates: auxiliary_hint"
  assert_contains "$output" "evidence_type cannot confirm facts in v2 gates: source_probe"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --target-status "confirmed" \
    --evidence-type "deterministic_code" \
    --evidence-type "user_decision_fact_evidence" \
    --decision-type "business_intent" \
    --print-contract

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
}

@test "shadow_v2_gate_skeleton rejects generic user decisions and final apply as fact evidence" {
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --target-status "confirmed" \
    --evidence-type "user_decision" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "generic user_decision cannot confirm facts"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --target-status "confirmed" \
    --evidence-type "user_decision_fact_evidence" \
    --decision-type "final_shadow_apply" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "final_shadow_apply cannot confirm facts"
}

@test "shadow_v2_user_decision_assistant turns source probes into bounded user questions" {
  local probe_file="$TEST_WORKSPACE/source-probe.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/UserService.java:6","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/UserService.java","anchor_symbol":"userRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-decision-before.txt"

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --input "$probe_file" --task-id "shadow-effect-map-01"

  [ "$status" -eq 0 ]
  assert_contains "$output" "# Shadow v2 User Decision Assistant"
  assert_contains "$output" "- writes_shadow_docs: false"
  assert_contains "$output" "- auto_promotes_facts: false"
  assert_contains "$output" "- question_count: 1"
  assert_contains "$output" "- question_group_count: 1"
  assert_contains "$output" "## Question Groups"
  assert_contains "$output" "source_kind: evidence_candidate"
  assert_contains "$output" "decision_type: classification_or_evidence_gap"
  assert_contains "$output" "recommended_default_status: unknown"
  assert_contains "$output" "command_ready: false"
  assert_contains "$output" "Does the syntactic source probe"

  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-decision-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-v2-decision-before.txt" "$TEST_WORKSPACE/shadow-v2-decision-after.txt"
  [ "$status" -eq 0 ]
}

@test "shadow_v2_user_decision_assistant groups bounded questions without answering them" {
  local probe_file="$TEST_WORKSPACE/source-probes.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/UserService.java:6","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","entry_ref":"UserController.update","anchor_file":"src/UserService.java","anchor_symbol":"userRepository.save","call_chain_candidate":"UserController.update -> UserService.updateUser -> userRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/OrderService.java:9","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","entry_ref":"OrderController.update","anchor_file":"src/OrderService.java","anchor_symbol":"orderRepository.save","call_chain_candidate":"OrderController.update -> OrderService.updateOrder -> orderRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --input "$probe_file" --task-id "shadow-effect-map-01" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"question_count": 2'
  assert_contains "$output" '"question_group_count": 1'
  assert_contains "$output" '"id": "UDG-001"'
  assert_contains "$output" '"question_ids": ['
  assert_contains "$output" '"UDQ-001"'
  assert_contains "$output" '"UDQ-002"'
  assert_contains "$output" '"auto_promotes_facts": false'
}

@test "shadow_v2_user_decision_assistant enforces project-scope hint activation" {
  local fresh_project="$TEST_WORKSPACE/unscaffolded-decision-repo"
  mkdir -p "$fresh_project"

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$fresh_project" --enable-hints --format json

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status": "blocked"'
  assert_contains "$output" "docs_root must exist before automatic hint lookup"
  assert_contains "$output" '"allowed": false'

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --enable-hints --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status": "ok"'
  assert_contains "$output" '"allowed": true'
  assert_contains "$output" '"trigger": "project_scope_verified"'
}

@test "shadow_v2_user_decision_assistant does not hang when stdin is an open pipe with no data" {
  # Regression for a `not sys.stdin.isatty()` heuristic: "not a terminal" was
  # read as "has piped data", but a non-tty stdin can be an open pipe with no
  # writer ready yet -- exactly what a background job, CI runner, or an agent
  # harness pipe looks like -- and the old code blocked on read() forever.
  # `timeout` is not installed on this machine, so termination is verified
  # with a background PID plus a bounded poll loop instead.
  local fifo="$TEST_WORKSPACE/no-data.fifo"
  mkfifo "$fifo"

  # Opening a fifo read-write on one fd never blocks (unlike plain `<` or `>`
  # on a fifo) and, because the same fd holds both ends open, the reader
  # never sees EOF either. That reproduces "not a tty, no data, no EOF"
  # without a second process and without ever hanging the test harness.
  exec 9<>"$fifo"

  python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --enable-hints --format json \
    <&9 > "$TEST_WORKSPACE/stdin-hang.out" 2>&1 &
  local pid=$!

  local waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 50 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  local hung="false"
  if kill -0 "$pid" 2>/dev/null; then
    hung="true"
    kill -9 "$pid" 2>/dev/null
  fi

  exec 9>&-
  exec 9<&-

  assert_equal "$hung" "false"

  local exit_status=0
  wait "$pid" || exit_status=$?
  local output
  output="$(cat "$TEST_WORKSPACE/stdin-hang.out")"

  assert_equal "$exit_status" "0"
  assert_contains "$output" '"status": "ok"'
  assert_contains "$output" '"question_count": 0'
}

@test "shadow_v2_user_decision_assistant surfaces writer user-decision command hints" {
  local writer_result="$TEST_WORKSPACE/writer-result.json"
  cat > "$writer_result" <<EOF
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "confirmed fact requires a separate user_decision fact-evidence artifact",
      "command": ["python3", "$SHADOW_USER_DECISION", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01"],
      "command_text": "python3 $SHADOW_USER_DECISION --decision-type business_intent --answer confirmed",
      "then": "rerun shadow_effect_writer.py with --evidence-decision <evidence-decision.json>"
    }
  ]
}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --writer-result "$writer_result" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"question_count": 1'
  assert_contains "$output" '"source_kind": "writer_next_action"'
  assert_contains "$output" '"decision_type": "business_intent"'
  assert_contains "$output" '"command_ready": true'
  assert_contains "$output" "shadow_user_decision_wrapper.py"
  assert_contains "$output" "--decision-type business_intent"
  assert_contains "$output" '"writes_shadow_docs": false'
}

@test "shadow_v2_user_decision_assistant blocks forged writer command hints" {
  local forged_writer_result="$TEST_WORKSPACE/forged-writer-result.json"
  cat > "$forged_writer_result" <<EOF
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "forged writer result",
      "command": ["python3", "shadow_effect_writer.py", "--mode", "write"],
      "command_text": "python3 shadow_effect_writer.py --mode write",
      "then": "do not run"
    },
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "final apply is not fact evidence",
      "command": ["python3", "$SHADOW_USER_DECISION", "--decision-type", "final_shadow_apply"],
      "command_text": "python3 $SHADOW_USER_DECISION --decision-type final_shadow_apply"
    }
  ]
}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --writer-result "$forged_writer_result" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"question_count": 2'
  assert_contains "$output" '"command_ready": false'
  assert_contains "$output" "python command hint must execute shadow_user_decision_wrapper.py directly"
  assert_contains "$output" "command hint must not target write, external, or reviewer tools: shadow_effect_writer.py"
  assert_contains "$output" "final_shadow_apply command hints are not fact-evidence decisions"
  refute_contains "$output" '"command_hint"'
  refute_contains "$output" "shadow_effect_writer.py --mode write"
}

@test "shadow_v2_user_decision_assistant blocks external reviewer command hint tools" {
  local forged_writer_result="$TEST_WORKSPACE/forged-external-tool-result.json"
  cat > "$forged_writer_result" <<EOF
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "external reviewer tools cannot author user fact decisions",
      "command": ["python3", "$SHADOW_USER_DECISION", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "antigravity", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "gemini should not be part of this command hint", "--source-ref", "external-cli:agy"]
    }
  ]
}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --writer-result "$forged_writer_result" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"question_count": 1'
  assert_contains "$output" '"command_ready": false'
  assert_contains "$output" "command hint must not target write, external, or reviewer tools:"
  assert_contains "$output" "antigravity"
  assert_contains "$output" "external-cli:agy"
  assert_contains "$output" "gemini"
  refute_contains "$output" '"command_hint"'
}

@test "shadow_v2_user_decision_assistant renders command text only from validated argv" {
  local misleading_writer_result="$TEST_WORKSPACE/misleading-command-text-result.json"
  cat > "$misleading_writer_result" <<EOF
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "safe argv with hostile command_text",
      "command": ["python3", "$SHADOW_USER_DECISION", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01"],
      "command_text": "python3 shadow_effect_writer.py --mode write"
    }
  ]
}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --writer-result "$misleading_writer_result" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"command_ready": true'
  assert_contains "$output" "shadow_user_decision_wrapper.py"
  assert_contains "$output" "--decision-type"
  assert_contains "$output" "business_intent"
  refute_contains "$output" "shadow_effect_writer.py --mode write"
}

@test "shadow_v2_user_decision_assistant rejects python command smuggling" {
  local smuggled_writer_result="$TEST_WORKSPACE/smuggled-command-result.json"
  cat > "$smuggled_writer_result" <<'EOF'
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "wrapper appears only as argument",
      "command": ["python3", "-c", "print('x')", "shadow_user_decision_wrapper.py", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01"]
    }
  ]
}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --writer-result "$smuggled_writer_result" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"command_ready": false'
  assert_contains "$output" "python command hint must execute shadow_user_decision_wrapper.py directly"
  assert_contains "$output" "command hint must not use python -c"
  refute_contains "$output" '"command_hint"'
}

@test "shadow_v2_user_decision_assistant rejects duplicate decision flags" {
  local duplicate_flag_result="$TEST_WORKSPACE/duplicate-flag-command-result.json"
  cat > "$duplicate_flag_result" <<EOF
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "duplicate decision type",
      "command": ["python3", "$SHADOW_USER_DECISION", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01", "--decision-type", "final_shadow_apply"]
    }
  ]
}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --writer-result "$duplicate_flag_result" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"command_ready": false'
  assert_contains "$output" "command hint duplicate flag is not allowed: --decision-type"
  refute_contains "$output" '"command_hint"'
}

@test "shadow_v2_user_decision_assistant rejects spoofed wrapper paths" {
  local spoofed_path_result="$TEST_WORKSPACE/spoofed-wrapper-path-result.json"
  local relative_path_result="$TEST_WORKSPACE/relative-wrapper-path-result.json"
  cat > "$spoofed_path_result" <<'EOF'
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "spoofed wrapper path",
      "command": ["python3", "/tmp/shadow_user_decision_wrapper.py", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01"]
    }
  ]
}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --writer-result "$spoofed_path_result" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"command_ready": false'
  assert_contains "$output" "python command hint must execute shadow_user_decision_wrapper.py directly"
  refute_contains "$output" '"command_hint"'

  cat > "$relative_path_result" <<'EOF'
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "relative wrapper path",
      "command": ["python3", "shadow_user_decision_wrapper.py", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01"]
    }
  ]
}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --writer-result "$relative_path_result" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"command_ready": false'
  assert_contains "$output" "python command hint must execute shadow_user_decision_wrapper.py directly"
  refute_contains "$output" '"command_hint"'
}

@test "shadow_v2_user_decision_assistant refuses outputs under docs shadow" {
  run python3 "$SHADOW_V2_USER_DECISION" \
    --project-root "$TEST_PROJECT" \
    --output "$DOCS_ROOT/shadow/user-decision-packet.md"

  [ "$status" -eq 64 ]
  assert_contains "$output" "--output must not be under docs/shadow"
  assert_contains "$output" '"writes_shadow_docs":false'

  run python3 "$SHADOW_V2_USER_DECISION" \
    --project-root "$TEST_PROJECT" \
    --output "$TEST_WORKSPACE/outside-user-decision-packet.md"

  [ "$status" -eq 64 ]
  assert_contains "$output" "--output must be under project docs"
}

@test "shadow_v2_review_packet_generator emits bounded internal review packets" {
  local writer_result="$DOCS_ROOT/report/review-writer-result.json"
  cat > "$writer_result" <<'EOF'
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "confirmed fact requires a separate user_decision fact-evidence artifact",
      "then": "rerun writer"
    }
  ],
  "source_refs": ["src/UserService.java:6"]
}
EOF
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-review-before.txt"

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --task-id "shadow-effect-map-01" \
    --writer-result "$writer_result" \
    --source-ref "TASK-shadow-effect-map-01"

  [ "$status" -eq 0 ]
  assert_contains "$output" "# Shadow v2 Review Packet"
  assert_contains "$output" "review_route: internal_subagent_md_handoff"
  assert_contains "$output" "privacy_boundary: packet_only_no_workspace_dump"
  assert_contains "$output" "review_provenance: internal_md_handoff"
  assert_contains "$output" "unsupported_by_packet: none"
  assert_contains "$output" "kind: writer_result"
  assert_contains "$output" "path: docs/report/review-writer-result.json"
  assert_contains "$output" "artifact_hash: sha256:"
  assert_contains "$output" "artifact_bytes:"
  assert_contains "$output" "TASK-shadow-effect-map-01"
  # The plural-source_refs expectation is deferred on its own (see the test below and
  # the project docs); every other
  # assertion in this test keeps running.
  assert_contains "$output" "- verdict: accept | revise | blocked"
  assert_contains "$output" "- writes_shadow_docs: false"

  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-review-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-v2-review-before.txt" "$TEST_WORKSPACE/shadow-v2-review-after.txt"
  [ "$status" -eq 0 ]
}

@test "shadow_v2_review_packet_generator carries plural source_refs into the packet" {
  local writer_result="$TEST_WORKSPACE/review-writer-result.json"
  cat > "$writer_result" <<'JSONEOF'
{"status":"blocked","writes_shadow_docs":false,"auto_promotes_facts":false,"source_refs":["src/UserService.java:6"]}
JSONEOF
  cp "$writer_result" "$DOCS_ROOT/report/review-writer-result.json"

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --task-id "shadow-effect-map-01" \
    --writer-result "$DOCS_ROOT/report/review-writer-result.json"

  [ "$status" -eq 0 ]
  assert_contains "$output" "src/UserService.java:6"
}

@test "shadow_v2_review_packet_generator combines singular and plural refs within the limit" {
  local writer_result="$DOCS_ROOT/report/review-mixed-refs.json"
  cat > "$writer_result" <<'JSONEOF'
{"status":"blocked","source_ref":"src/Singular.java:1","source_refs":["src/Plural00.java:1","src/Plural01.java:1","src/Plural02.java:1","src/Plural03.java:1","src/Plural04.java:1","src/Plural05.java:1","src/Plural06.java:1","src/Plural07.java:1","src/Plural08.java:1","src/Plural09.java:1","src/Plural10.java:1","src/Plural11.java:1","src/Plural12.java:1","src/Plural13.java:1","src/Plural14.java:1","src/Plural15.java:1","src/Plural16.java:1","src/Plural17.java:1","src/Plural18.java:1","src/Plural19.java:1"]}
JSONEOF

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --task-id "shadow-effect-map-01" \
    --writer-result "$writer_result" \
    --format json

  [ "$status" -eq 0 ]
  run python3 -c 'import json, sys; refs = json.loads(sys.argv[1])["source_refs"]; assert refs == ["src/Singular.java:1"] + [f"src/Plural{i:02}.java:1" for i in range(19)]; assert len(refs) == 20' "$output"
  [ "$status" -eq 0 ]
}

@test "shadow_v2_review_packet_generator bounds plural refs with deduped input order" {
  local writer_result="$DOCS_ROOT/report/review-plural-refs.json"
  local refs_json
  refs_json="$(python3 -c 'import json; refs = [f"src/Ref{i:02}.java:1" for i in range(24)]; refs.insert(2, refs[1]); print(json.dumps(refs))')"
  printf '{"status":"blocked","source_refs":%s}\n' "$refs_json" > "$writer_result"

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --task-id "shadow-effect-map-01" \
    --writer-result "$writer_result" \
    --format json

  [ "$status" -eq 0 ]
  run python3 -c 'import json, sys; refs = json.loads(sys.argv[1])["source_refs"]; assert refs == [f"src/Ref{i:02}.java:1" for i in range(20)]; assert len(refs) == len(set(refs)) == 20' "$output"
  [ "$status" -eq 0 ]
}

@test "shadow_v2_review_packet_generator refuses artifact inputs outside project root" {
  local writer_result="$TEST_WORKSPACE/review-writer-result.json"
  cat > "$writer_result" <<'EOF'
{"status":"blocked","writes_shadow_docs":false,"auto_promotes_facts":false,"source_refs":["src/UserService.java:6"]}
EOF

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --task-id "shadow-effect-map-01" \
    --writer-result "$writer_result" \
    --source-ref "TASK-shadow-effect-map-01" \
    --format json

  [ "$status" -eq 64 ]
  assert_contains "$output" "--writer-result must stay under project root"
  assert_contains "$output" '"writes_shadow_docs":false'
}

@test "shadow_v2_review_packet_generator blocks external route unless requested" {
  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --format json

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status": "blocked"'
  assert_contains "$output" "external antigravity review requires explicit user request"
  assert_contains "$output" "external_review_user_request"
  assert_contains "$output" "external_review_approval_ref"
  assert_contains "$output" "external_review_approved_next_step"
  assert_contains "$output" "external_review_recorded_by"
  assert_contains "$output" '"review_provenance": "external_review_missing_user_request"'
  refute_contains "$output" '"review_provenance": "external_user_approved"'

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --source-ref "TASK-shadow-effect-map-01" \
    --format json

  [ "$status" -eq 1 ]
  assert_contains "$output" '"review_provenance": "external_review_missing_approval_provenance"'
  assert_contains "$output" "external antigravity review requires concrete approval_ref"

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "generate external review packet only" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --source-ref "TASK-shadow-effect-map-01" \
    --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status": "ok"'
  assert_contains "$output" '"review_provenance": "external_user_approved"'
  assert_contains "$output" '"external_review_approval_ref": "user-approval-001"'
  assert_contains "$output" '"required_response_fields": ['
  assert_contains "$output" '"summary"'
  assert_contains "$output" '"strengths"'
  assert_contains "$output" '"risks"'
  assert_contains "$output" '"requested_changes"'
  refute_contains "$output" '"priority_findings"'
}

@test "shadow_v2_review_packet_generator refuses outputs under docs shadow" {
  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --source-ref "TASK-shadow-effect-map-01" \
    --output "$DOCS_ROOT/shadow/review-packet.md"

  [ "$status" -eq 64 ]
  assert_contains "$output" "--output must not be under docs/shadow"
  assert_contains "$output" '"writes_shadow_docs":false'

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --source-ref "TASK-shadow-effect-map-01" \
    --output "$TEST_WORKSPACE/outside-review-packet.md"

  [ "$status" -eq 64 ]
  assert_contains "$output" "--output must be under project docs"
}

@test "shadow_v2_pipeline_wrapper emits incomplete dry-run plans without executing commands" {
  run python3 "$SHADOW_V2_PIPELINE" --project-root "$TEST_PROJECT" --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status": "incomplete"'
  assert_contains "$output" '"plan_kind": "dry_run_plan"'
  assert_contains "$output" '"executes_commands": false'
  assert_contains "$output" '"final_apply": "blocked"'
  assert_contains "$output" "run_deterministic_probes"
  assert_contains "$output" "pending_input"
  assert_contains "$output" "final_shadow_apply"
}

@test "shadow_v2_pipeline_wrapper writer command is dry-run only" {
  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --record "$TEST_WORKSPACE/record.json" \
    --candidate-file "$TEST_WORKSPACE/candidate.json" \
    --user-decision "$TEST_WORKSPACE/decision.json" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status": "incomplete"'
  assert_contains "$output" "shadow_effect_writer.py"
  assert_contains "$output" "--mode"
  assert_contains "$output" "dry-run"
  refute_contains "$output" "--mode write"
}

@test "shadow_v2_pipeline_wrapper blocks external review route without approval" {
  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --format json

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status": "blocked"'
  assert_contains "$output" "external antigravity review requires explicit user request"
  assert_contains "$output" '"executes_commands": false'

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --format json

  [ "$status" -eq 1 ]
  assert_contains "$output" "external antigravity review requires concrete approval_ref"
  assert_contains "$output" "external antigravity review requires approved_next_step"
  assert_contains "$output" "external antigravity review requires main-thread recorded_by"

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "generate external review packet only" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status": "incomplete"'
  assert_contains "$output" '"approval_ref": "user-approval-001"'
  assert_contains "$output" '"executes_commands": false'
}

@test "shadow_v2_pipeline_wrapper blocks combined close when required external review is blocked" {
  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --blocked-review "external_antigravity" \
    --format json

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status": "blocked"'
  assert_contains "$output" "close_review_gate"
  assert_contains "$output" "required review route is blocked: external_antigravity"
  assert_contains "$output" "sub-agent acceptance cannot substitute for blocked external antigravity review"
  assert_contains "$output" '"executes_commands": false'

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --blocked-review "external_antigravity=platform_permission_blocked" \
    --format json

  [ "$status" -eq 1 ]
  assert_contains "$output" "required review route is blocked: external_antigravity (platform_permission_blocked)"
  assert_contains "$output" "switch permission mode"
  assert_contains "$output" '"blocked_review_reasons"'
  assert_contains "$output" '"platform_permission_blocked"'
}

@test "shadow_v2_pipeline_wrapper requires external close artifact provenance" {
  local accepted_artifact
  local internal_artifact
  accepted_artifact="$(create_mock_external_review_artifact "shadow-v2-pipeline-accepted" "agy-current")"
  internal_artifact="$(create_mock_internal_review_artifact "shadow-v2-pipeline-internal")"
  [ -n "$accepted_artifact" ]
  [ -n "$internal_artifact" ]
  run test -f "$accepted_artifact"
  [ "$status" -eq 0 ]
  run test -f "${accepted_artifact%.md}.provenance.md"
  [ "$status" -eq 0 ]

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --format json

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status": "blocked"'
  assert_contains "$output" "completed external antigravity review requires a durable response artifact"
  assert_contains "$output" '"executes_commands": false'

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$accepted_artifact" \
    --format json

  [ "$status" -eq 0 ]
  assert_contains "$output" '"close_review_gate"'
  assert_contains "$output" '"status": "satisfied"'
  assert_contains "$output" '"completed_review_artifacts"'
  assert_contains "$output" '"sha256": "sha256:'
  refute_contains "$output" "completed external antigravity review requires a durable response artifact"
}

@test "shadow_v2_pipeline_wrapper refuses outputs under docs shadow" {
  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --output "$DOCS_ROOT/shadow/pipeline-plan.md"

  [ "$status" -eq 64 ]
  assert_contains "$output" "--output must not be under docs/shadow"
  assert_contains "$output" '"writes_shadow_docs":false'

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --output "$TEST_WORKSPACE/outside-pipeline-plan.md"

  [ "$status" -eq 64 ]
  assert_contains "$output" "--output must be under project docs"
}


@test "shadow_v2_gate_skeleton blocks a declared non-antigravity evaluator despite an agy filename" {
  local accepted_artifact
  local internal_artifact
  local round_dir
  local forged
  accepted_artifact="$(create_mock_external_review_artifact "shadow-v2-evaluator-forge" "agy-current")"
  internal_artifact="$(create_mock_internal_review_artifact "shadow-v2-evaluator-forge-internal")"
  round_dir="$(dirname "$accepted_artifact")"
  forged="$round_dir/agy-current-forged.response.md"
  {
    echo "- evaluator: gemini"
    cat "$accepted_artifact"
  } > "$forged"

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$forged" \
    --print-contract

  [ "$status" -eq 1 ]
  assert_contains "$output" "requires evaluator antigravity or agy"
}

# ========== Adversarial field rule in the close gate ==========
# references/orchestration-review-contract.md: on an adversarial accept the debate keys
# (objection/counterproposal/rebuttal) must be present but may be empty; residual_risk is
# non-empty on every verdict. The gate must read each key on its own line -- a reader that
# crosses line breaks makes the result depend on field order.

# Runs the wrapper with agy as the adversarial reviewer (mocked; every runner mock is
# local) and prints the sanitized response path. $2 is the raw response body.
create_adversarial_agy_artifact() {
  local task_id="$1"
  local body="$2"
  local mock_bin="$TEST_WORKSPACE/mock-bin-${task_id}"
  local body_file="$TEST_WORKSPACE/${task_id}.agy-body.md"
  local run_output="$TEST_WORKSPACE/${task_id}-external-review.out"
  cat > "$DOCS_ROOT/plan/PLAN-${task_id}-v1.0.md" <<EOF
# PLAN-${task_id}-v1.0

- task_id: ${task_id}
- plan_version: v1.0
- objective: adversarial close-gate fixture
- scope: test fixture generation
- assumptions: none
- risks: fixture generation failure
- acceptance_signals: response and provenance files are written
- stop_conditions: wrapper completes
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF
  printf '%s\n' "$body" > "$body_file"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/agy" "#!/usr/bin/env bash
cat \"$body_file\""
  local runner
  for runner in claude codex gemini; do
    write_mock_cli "$mock_bin/$runner" '#!/usr/bin/env bash
exit 99'
  done
  env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "$task_id" --plan-version "v1.0" --primary-tool "codex" \
    --reviewer "agy-current" --adversarial-evaluator "agy-current" --review-round "r01" \
    --risk-preflight-status "approved" --approval-ref "user-approval-${task_id}" \
    --approved-next-step "run external review ${task_id} v1.0 r01" > "$run_output" 2>&1 || {
      cat "$run_output" >&2
      return 1
    }
  printf "%s/agy-current.response.md\n" "$(external_handoff_dir "$task_id" "v1.0" "r01")"
}

# Rewrites a sanitized response and re-binds its provenance hash, so the gate's own
# field rule is exercised on input the wrapper would have refused to produce.
rewrite_adversarial_response() {
  local artifact="$1"
  local body="$2"
  printf '%s\n' "$body" > "$artifact"
  local digest
  digest="sha256:$(shasum -a 256 "$artifact" | awk '{print $1}')"
  sed -i.bak "s/^- response_sha256: .*/- response_sha256: ${digest}/" "${artifact%.md}.provenance.md"
  rm -f "${artifact%.md}.provenance.md.bak"
}

run_close_gate_with_external() {
  local artifact="$1"
  local internal_artifact
  internal_artifact="$(create_mock_internal_review_artifact "shadow-v2-adv-internal")"
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --completed-review "external_antigravity" \
    --completed-review-artifact "external_antigravity=$artifact" \
    --print-contract
}

ADV_STANDARD_LINES='- verdict: accept
- summary: The plan is execution-ready for this bounded scope.
- strengths: It separates review collection from plan mutation.
- risks: Operators may still skim the adversarial report.
- requested_changes: None blocking.'

@test "shadow_v2 close gate accepts an adversarial accept with empty debate fields in any field order" {
  local artifact
  artifact="$(create_adversarial_agy_artifact "adv-gate-canonical" "${ADV_STANDARD_LINES}
- objection:
- counterproposal:
- rebuttal:
- residual_risk: Did not exercise the rollback path.")"
  [ -f "$artifact" ]
  run_close_gate_with_external "$artifact"
  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'

  # Empty debate key as the LAST line: nothing follows it for a line-crossing reader.
  artifact="$(create_adversarial_agy_artifact "adv-gate-rebuttal-last" "${ADV_STANDARD_LINES}
- residual_risk: Did not exercise the rollback path.
- objection:
- counterproposal:
- rebuttal:")"
  [ -f "$artifact" ]
  run_close_gate_with_external "$artifact"
  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  refute_contains "$output" "requires parser-compatible field"
}

@test "shadow_v2 close gate blocks an adversarial accept missing a debate key or with empty residual_risk" {
  local artifact key
  for key in objection counterproposal rebuttal residual_risk; do
    artifact="$(create_adversarial_agy_artifact "adv-gate-missing-${key}" "${ADV_STANDARD_LINES}
- objection:
- counterproposal:
- rebuttal:
- residual_risk: Did not exercise the rollback path.")"
    [ -f "$artifact" ]
    rewrite_adversarial_response "$artifact" "$(grep -v -E "^- ${key}:" "$artifact")"
    run_close_gate_with_external "$artifact"
    [ "$status" -eq 1 ]
    assert_contains "$output" "completed adversarial external antigravity review artifact requires parser-compatible field ${key}"
  done

  # Empty residual_risk followed by another line: a line-crossing reader would read the
  # next bullet as its value and let it through.
  artifact="$(create_adversarial_agy_artifact "adv-gate-empty-residual" "${ADV_STANDARD_LINES}
- objection:
- counterproposal:
- rebuttal:
- residual_risk: Did not exercise the rollback path.")"
  rewrite_adversarial_response "$artifact" "${ADV_STANDARD_LINES}
- residual_risk:
- objection:
- counterproposal:
- rebuttal:"
  run_close_gate_with_external "$artifact"
  [ "$status" -eq 1 ]
  assert_contains "$output" "completed adversarial external antigravity review artifact requires parser-compatible field residual_risk"
  refute_contains "$output" "response_sha256 must match"
}
