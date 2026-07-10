#!/usr/bin/env bats

load codeguide_helper

@test "shadow_v2_gate_skeleton prints a no-write Phase 0 contract" {
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-before.txt"

  run python3 "$SHADOW_V2_SKELETON" --project-root "$TEST_PROJECT" --print-contract

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"phase":"shadow_v2_phase0_gate_skeleton"'* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]
  [[ "$output" == *'"auto_promotes_facts":false'* ]]
  [[ "$output" == *'"batch_apply_enabled":false'* ]]
  [[ "$output" == *'user_decision_assistant'* ]]
  [[ "$output" == *'review_packet_generator'* ]]
  [[ "$output" == *'supervised_pipeline_wrapper'* ]]

  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-v2-before.txt" "$TEST_WORKSPACE/shadow-v2-after.txt"
  [ "$status" -eq 0 ]
}

@test "shadow_v2_gate_skeleton activates hints only after project scope is verified" {
  local fresh_project="$TEST_WORKSPACE/unscaffolded-repo"
  mkdir -p "$fresh_project"

  run python3 "$SHADOW_V2_SKELETON" --project-root "$fresh_project" --check-scope

  [ "$status" -eq 1 ]
  [[ "$output" == *"docs_root must exist before automatic hint lookup"* ]]
  [[ "$output" == *'"allowed":false'* ]]
  [[ "$output" == *'"mode":"hint_only"'* ]]

  run python3 "$SHADOW_V2_SKELETON" --project-root "$TEST_PROJECT" --project-id "test-project" --check-scope

  [ "$status" -eq 0 ]
  [[ "$output" == *'"allowed":true'* ]]
  [[ "$output" == *'"trigger":"project_scope_verified"'* ]]
  [[ "$output" == *'"project_identity":"test-project"'* ]]
}

@test "shadow_v2_gate_skeleton blocks external review by default and disables batch apply" {
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --record-count 2 \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"external antigravity review requires explicit user request"* ]]
  [[ "$output" == *"batch apply is disabled in Phase 0"* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"external antigravity review requires concrete approval_ref"* ]]
  [[ "$output" == *"external antigravity review requires approved_next_step"* ]]
  [[ "$output" == *"external antigravity review requires main-thread recorded_by"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "generate external review packet only" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --print-contract

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
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
  [[ "$output" == *'"status":"blocked"'* ]]
  [[ "$output" == *"required review route is blocked: external_antigravity"* ]]
  [[ "$output" == *"stop without substituting another reviewer route"* ]]
  [[ "$output" == *"sub-agent acceptance cannot substitute for blocked external antigravity review"* ]]
  [[ "$output" == *'"combined_review_close_gate":"all_required_routes_must_complete"'* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --blocked-review "external_antigravity=platform_permission_blocked" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"required review route is blocked: external_antigravity (platform_permission_blocked)"* ]]
  [[ "$output" == *"switch permission mode"* ]]
  [[ "$output" == *'"blocked_review_reasons":{"external_antigravity":"platform_permission_blocked"}'* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"required review route is missing: external_antigravity"* ]]
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
  [[ "$output" == *"completed internal review route requires a durable response artifact: internal_subagent_md_handoff"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$non_markdown_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"completed internal review artifact must be a Markdown .md file"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --completed-review "internal_subagent_md_handoff" \
    --completed-review-artifact "internal_subagent_md_handoff=$internal_artifact" \
    --print-contract

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"completed_review_artifacts":'* ]]
  [[ "$output" == *'"sha256":"sha256:'* ]]
}

@test "shadow_v2_gate_skeleton requires durable accepted external review artifact before close completion" {
  local stub_artifact="$TEST_WORKSPACE/external-stub-review.md"
  local empty_dir="$DOCS_ROOT/orchestration/shadow-v2-close/external-cli/v1.0/r-empty"
  local blocked_dir="$DOCS_ROOT/orchestration/shadow-v2-close/external-cli/v1.0/r-blocked"
  local no_manifest_dir="$DOCS_ROOT/orchestration/shadow-v2-close/external-cli/v1.0/r-no-manifest"
  local thin_dir="$DOCS_ROOT/orchestration/shadow-v2-close/external-cli/v1.0/r-thin"
  local empty_artifact="$empty_dir/gemini.response.md"
  local blocked_artifact="$blocked_dir/gemini.response.md"
  local no_manifest_artifact="$no_manifest_dir/gemini.response.md"
  local thin_artifact="$thin_dir/gemini.response.md"
  local internal_artifact
  local accepted_artifact
  mkdir -p "$empty_dir" "$blocked_dir" "$no_manifest_dir" "$thin_dir"
  cat > "$stub_artifact" <<'EOF'
evaluator: gemini
verdict: accept
priority_findings: none
EOF
  : > "$empty_artifact"
  cat > "$empty_dir/gemini.request.md" <<EOF
evaluator: gemini
command_response_path: $empty_dir/gemini.command-response.raw.md
sanitized_response_file: $empty_artifact
EOF
  cat > "$blocked_artifact" <<'EOF'
evaluator: gemini
verdict: blocked
status: blocked
EOF
  cat > "$blocked_dir/gemini.request.md" <<EOF
evaluator: gemini
command_response_path: $blocked_dir/gemini.command-response.raw.md
sanitized_response_file: $blocked_artifact
EOF
  local blocked_hash
  blocked_hash="$(sha256_file_ref "$blocked_artifact")"
  cat > "$blocked_dir/gemini.response.provenance.md" <<EOF
artifact_kind: external_cli_review_response_provenance
generated_by: run_external_plan_reviews.sh
evaluator: gemini
verdict: blocked
request_file: $blocked_dir/gemini.request.md
response_file: $blocked_artifact
response_sha256: $blocked_hash
command_response_path: $blocked_dir/gemini.command-response.raw.md
raw_capture_deleted: true
sanitized_response: true
EOF
  cat > "$no_manifest_artifact" <<'EOF'
evaluator: gemini
verdict: accept
priority_findings: none
EOF
  cat > "$no_manifest_dir/gemini.request.md" <<EOF
evaluator: gemini
command_response_path: $no_manifest_dir/gemini.command-response.raw.md
sanitized_response_file: $no_manifest_artifact
EOF
  cat > "$thin_artifact" <<'EOF'
evaluator: gemini
verdict: accept
EOF
  cat > "$thin_dir/gemini.request.md" <<EOF
evaluator: gemini
command_response_path: $thin_dir/gemini.command-response.raw.md
sanitized_response_file: $thin_artifact
EOF
  local thin_hash
  thin_hash="$(sha256_file_ref "$thin_artifact")"
  cat > "$thin_dir/gemini.response.provenance.md" <<EOF
artifact_kind: external_cli_review_response_provenance
generated_by: run_external_plan_reviews.sh
review_style: standard
evaluator: gemini
verdict: accept
request_file: $thin_dir/gemini.request.md
response_file: $thin_artifact
response_sha256: $thin_hash
command_response_path: $thin_dir/gemini.command-response.raw.md
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
  [[ "$output" == *"completed external antigravity review requires a durable response artifact"* ]]

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
  [[ "$output" == *"completed external antigravity review artifact must be under docs/orchestration/<task-id>/external-cli"* ]]

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
  [[ "$output" == *"completed external antigravity review artifact requires provenance manifest"* ]]

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
  [[ "$output" == *"completed external antigravity review artifact requires parser-compatible field summary"* ]]
  [[ "$output" == *"completed external antigravity review artifact requires parser-compatible field requested_changes"* ]]

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
  [[ "$output" == *"completed review artifact must be non-empty for route external_antigravity"* ]]

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
  [[ "$output" == *"completed external antigravity review artifact verdict must be accept"* ]]
  [[ "$output" == *"completed external antigravity review artifact contains blocked/error/no-response marker"* ]]

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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"sha256":"sha256:'* ]]
  [[ "$output" == *'"evaluator":"agy"'* ]]
  [[ "$output" == *'"request_file":'* ]]
  [[ "$output" == *'"command_response_path":'* ]]
  [[ "$output" == *'"provenance_file":'* ]]
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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" != *"sub-agent acceptance cannot substitute for blocked external antigravity review"* ]]
}

@test "shadow_v2_gate_skeleton rejects hint evidence for confirmed facts" {
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --target-status "confirmed" \
    --evidence-type "auxiliary_hint" \
    --evidence-type "source_probe" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence_type cannot confirm facts in v2 gates: auxiliary_hint"* ]]
  [[ "$output" == *"evidence_type cannot confirm facts in v2 gates: source_probe"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --target-status "confirmed" \
    --evidence-type "deterministic_code" \
    --evidence-type "user_decision_fact_evidence" \
    --decision-type "business_intent" \
    --print-contract

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
}

@test "shadow_v2_gate_skeleton rejects generic user decisions and final apply as fact evidence" {
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --target-status "confirmed" \
    --evidence-type "user_decision" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"generic user_decision cannot confirm facts"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --target-status "confirmed" \
    --evidence-type "user_decision_fact_evidence" \
    --decision-type "final_shadow_apply" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"final_shadow_apply cannot confirm facts"* ]]
}

@test "shadow_v2_user_decision_assistant turns source probes into bounded user questions" {
  local probe_file="$TEST_WORKSPACE/source-probe.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/UserService.java:6","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/UserService.java","anchor_symbol":"userRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-decision-before.txt"

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --input "$probe_file" --task-id "shadow-effect-map-01"

  [ "$status" -eq 0 ]
  [[ "$output" == *"# Shadow v2 User Decision Assistant"* ]]
  [[ "$output" == *"- writes_shadow_docs: false"* ]]
  [[ "$output" == *"- auto_promotes_facts: false"* ]]
  [[ "$output" == *"- question_count: 1"* ]]
  [[ "$output" == *"- question_group_count: 1"* ]]
  [[ "$output" == *"## Question Groups"* ]]
  [[ "$output" == *"source_kind: evidence_candidate"* ]]
  [[ "$output" == *"decision_type: classification_or_evidence_gap"* ]]
  [[ "$output" == *"recommended_default_status: unknown"* ]]
  [[ "$output" == *"command_ready: false"* ]]
  [[ "$output" == *"Does the syntactic source probe"* ]]

  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-decision-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-v2-decision-before.txt" "$TEST_WORKSPACE/shadow-v2-decision-after.txt"
  [ "$status" -eq 0 ]
}

@test "shadow_v2_user_decision_assistant groups bounded questions without answering them" {
  local probe_file="$TEST_WORKSPACE/source-probes.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/UserService.java:6","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","entry_ref":"UserController.update","anchor_file":"src/UserService.java","anchor_symbol":"userRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/OrderService.java:9","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","entry_ref":"OrderController.update","anchor_file":"src/OrderService.java","anchor_symbol":"orderRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --input "$probe_file" --task-id "shadow-effect-map-01" --format json

  [ "$status" -eq 0 ]
  [[ "$output" == *'"question_count": 2'* ]]
  [[ "$output" == *'"question_group_count": 1'* ]]
  [[ "$output" == *'"id": "UDG-001"'* ]]
  [[ "$output" == *'"question_ids": ['* ]]
  [[ "$output" == *'"UDQ-001"'* ]]
  [[ "$output" == *'"UDQ-002"'* ]]
  [[ "$output" == *'"auto_promotes_facts": false'* ]]
}

@test "shadow_v2_user_decision_assistant enforces project-scope hint activation" {
  local fresh_project="$TEST_WORKSPACE/unscaffolded-decision-repo"
  mkdir -p "$fresh_project"

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$fresh_project" --enable-hints --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"docs_root must exist before automatic hint lookup"* ]]
  [[ "$output" == *'"allowed": false'* ]]

  run python3 "$SHADOW_V2_USER_DECISION" --project-root "$TEST_PROJECT" --enable-hints --format json

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "ok"'* ]]
  [[ "$output" == *'"allowed": true'* ]]
  [[ "$output" == *'"trigger": "project_scope_verified"'* ]]
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
  [[ "$output" == *'"question_count": 1'* ]]
  [[ "$output" == *'"source_kind": "writer_next_action"'* ]]
  [[ "$output" == *'"decision_type": "business_intent"'* ]]
  [[ "$output" == *'"command_ready": true'* ]]
  [[ "$output" == *"shadow_user_decision_wrapper.py --decision-type business_intent"* ]]
  [[ "$output" == *'"writes_shadow_docs": false'* ]]
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
  [[ "$output" == *'"question_count": 2'* ]]
  [[ "$output" == *'"command_ready": false'* ]]
  [[ "$output" == *"command hint executable must be shadow_user_decision_wrapper.py"* ]]
  [[ "$output" == *"command hint must not target write, external, or reviewer tools: shadow_effect_writer.py"* ]]
  [[ "$output" == *"final_shadow_apply command hints are not fact-evidence decisions"* ]]
  [[ "$output" != *'"command_hint"'* ]]
  [[ "$output" != *"shadow_effect_writer.py --mode write"* ]]
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
  [[ "$output" == *'"question_count": 1'* ]]
  [[ "$output" == *'"command_ready": false'* ]]
  [[ "$output" == *"command hint must not target write, external, or reviewer tools:"* ]]
  [[ "$output" == *"antigravity"* ]]
  [[ "$output" == *"external-cli:agy"* ]]
  [[ "$output" == *"gemini"* ]]
  [[ "$output" != *'"command_hint"'* ]]
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
  [[ "$output" == *'"command_ready": true'* ]]
  [[ "$output" == *"shadow_user_decision_wrapper.py"* ]]
  [[ "$output" == *"--decision-type"* ]]
  [[ "$output" == *"business_intent"* ]]
  [[ "$output" != *"shadow_effect_writer.py --mode write"* ]]
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
  [[ "$output" == *'"command_ready": false'* ]]
  [[ "$output" == *"python command hint must execute shadow_user_decision_wrapper.py directly"* ]]
  [[ "$output" == *"command hint must not use python -c"* ]]
  [[ "$output" != *'"command_hint"'* ]]
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
  [[ "$output" == *'"command_ready": false'* ]]
  [[ "$output" == *"command hint duplicate flag is not allowed: --decision-type"* ]]
  [[ "$output" != *'"command_hint"'* ]]
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
  [[ "$output" == *'"command_ready": false'* ]]
  [[ "$output" == *"python command hint must execute shadow_user_decision_wrapper.py directly"* ]]
  [[ "$output" != *'"command_hint"'* ]]

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
  [[ "$output" == *'"command_ready": false'* ]]
  [[ "$output" == *"python command hint must execute shadow_user_decision_wrapper.py directly"* ]]
  [[ "$output" != *'"command_hint"'* ]]
}

@test "shadow_v2_user_decision_assistant refuses outputs under docs shadow" {
  run python3 "$SHADOW_V2_USER_DECISION" \
    --project-root "$TEST_PROJECT" \
    --output "$DOCS_ROOT/shadow/user-decision-packet.md"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--output must not be under docs/shadow"* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]

  run python3 "$SHADOW_V2_USER_DECISION" \
    --project-root "$TEST_PROJECT" \
    --output "$TEST_WORKSPACE/outside-user-decision-packet.md"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--output must be under project docs"* ]]
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
  [[ "$output" == *"# Shadow v2 Review Packet"* ]]
  [[ "$output" == *"review_route: internal_subagent_md_handoff"* ]]
  [[ "$output" == *"privacy_boundary: packet_only_no_workspace_dump"* ]]
  [[ "$output" == *"review_provenance: internal_md_handoff"* ]]
  [[ "$output" == *"unsupported_by_packet: none"* ]]
  [[ "$output" == *"kind: writer_result"* ]]
  [[ "$output" == *"path: docs/report/review-writer-result.json"* ]]
  [[ "$output" == *"artifact_hash: sha256:"* ]]
  [[ "$output" == *"artifact_bytes:"* ]]
  [[ "$output" == *"TASK-shadow-effect-map-01"* ]]
  [[ "$output" == *"src/UserService.java:6"* ]]
  [[ "$output" == *"- verdict: accept | revise | blocked"* ]]
  [[ "$output" == *"- writes_shadow_docs: false"* ]]

  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-review-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-v2-review-before.txt" "$TEST_WORKSPACE/shadow-v2-review-after.txt"
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
  [[ "$output" == *"--writer-result must stay under project root"* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]
}

@test "shadow_v2_review_packet_generator blocks external route unless requested" {
  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"external antigravity review requires explicit user request"* ]]
  [[ "$output" == *"external_review_user_request"* ]]
  [[ "$output" == *"external_review_approval_ref"* ]]
  [[ "$output" == *"external_review_approved_next_step"* ]]
  [[ "$output" == *"external_review_recorded_by"* ]]
  [[ "$output" == *'"review_provenance": "external_review_missing_user_request"'* ]]
  [[ "$output" != *'"review_provenance": "external_user_approved"'* ]]

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --source-ref "TASK-shadow-effect-map-01" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"review_provenance": "external_review_missing_approval_provenance"'* ]]
  [[ "$output" == *"external antigravity review requires concrete approval_ref"* ]]

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
  [[ "$output" == *'"status": "ok"'* ]]
  [[ "$output" == *'"review_provenance": "external_user_approved"'* ]]
  [[ "$output" == *'"external_review_approval_ref": "user-approval-001"'* ]]
  [[ "$output" == *'"required_response_fields": ['* ]]
  [[ "$output" == *'"summary"'* ]]
  [[ "$output" == *'"strengths"'* ]]
  [[ "$output" == *'"risks"'* ]]
  [[ "$output" == *'"requested_changes"'* ]]
  [[ "$output" != *'"priority_findings"'* ]]
}

@test "shadow_v2_review_packet_generator refuses outputs under docs shadow" {
  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --source-ref "TASK-shadow-effect-map-01" \
    --output "$DOCS_ROOT/shadow/review-packet.md"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--output must not be under docs/shadow"* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --source-ref "TASK-shadow-effect-map-01" \
    --output "$TEST_WORKSPACE/outside-review-packet.md"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--output must be under project docs"* ]]
}

@test "shadow_v2_pipeline_wrapper emits incomplete dry-run plans without executing commands" {
  run python3 "$SHADOW_V2_PIPELINE" --project-root "$TEST_PROJECT" --format json

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "incomplete"'* ]]
  [[ "$output" == *'"plan_kind": "dry_run_plan"'* ]]
  [[ "$output" == *'"executes_commands": false'* ]]
  [[ "$output" == *'"final_apply": "blocked"'* ]]
  [[ "$output" == *"run_deterministic_probes"* ]]
  [[ "$output" == *"pending_input"* ]]
  [[ "$output" == *"final_shadow_apply"* ]]
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
  [[ "$output" == *'"status": "incomplete"'* ]]
  [[ "$output" == *"shadow_effect_writer.py"* ]]
  [[ "$output" == *"--mode"* ]]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" != *"--mode write"* ]]
}

@test "shadow_v2_pipeline_wrapper blocks external review route without approval" {
  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"external antigravity review requires explicit user request"* ]]
  [[ "$output" == *'"executes_commands": false'* ]]

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *"external antigravity review requires concrete approval_ref"* ]]
  [[ "$output" == *"external antigravity review requires approved_next_step"* ]]
  [[ "$output" == *"external antigravity review requires main-thread recorded_by"* ]]

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_antigravity" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "generate external review packet only" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --format json

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "incomplete"'* ]]
  [[ "$output" == *'"approval_ref": "user-approval-001"'* ]]
  [[ "$output" == *'"executes_commands": false'* ]]
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
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"close_review_gate"* ]]
  [[ "$output" == *"required review route is blocked: external_antigravity"* ]]
  [[ "$output" == *"sub-agent acceptance cannot substitute for blocked external antigravity review"* ]]
  [[ "$output" == *'"executes_commands": false'* ]]

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "internal_subagent_md_handoff" \
    --close-required-review "external_antigravity" \
    --completed-review "internal_subagent_md_handoff" \
    --blocked-review "external_antigravity=platform_permission_blocked" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *"required review route is blocked: external_antigravity (platform_permission_blocked)"* ]]
  [[ "$output" == *"switch permission mode"* ]]
  [[ "$output" == *'"blocked_review_reasons"'* ]]
  [[ "$output" == *'"platform_permission_blocked"'* ]]
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
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"completed external antigravity review requires a durable response artifact"* ]]
  [[ "$output" == *'"executes_commands": false'* ]]

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
  [[ "$output" == *'"close_review_gate"'* ]]
  [[ "$output" == *'"status": "satisfied"'* ]]
  [[ "$output" == *'"completed_review_artifacts"'* ]]
  [[ "$output" == *'"sha256": "sha256:'* ]]
  [[ "$output" != *"completed external antigravity review requires a durable response artifact"* ]]
}

@test "shadow_v2_pipeline_wrapper refuses outputs under docs shadow" {
  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --output "$DOCS_ROOT/shadow/pipeline-plan.md"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--output must not be under docs/shadow"* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --output "$TEST_WORKSPACE/outside-pipeline-plan.md"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--output must be under project docs"* ]]
}

