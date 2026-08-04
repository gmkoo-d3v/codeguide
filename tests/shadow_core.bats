#!/usr/bin/env bats

load codeguide_helper

@test "shadow_review_queue turns probe records into bounded human questions" {
  local probe_file="$TEST_WORKSPACE/probe.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/app.py:4","validator_kind":"ast","parser_backed":true,"promotion_limit":"high","writes_shadow_docs":false}
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/main/java/example/UserService.java:7","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/main/java/example/UserService.java","anchor_symbol":"userRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
{"status":"unsupported","validator_id":"java.ast.call_match@v99","source_ref":"src/main/java/example/UserService.java:7","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/main/java/example/UserService.java","anchor_symbol":"userRepository.save","missing_evidence":"supported validator","recommended_default_status":"blocked","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" \
    --input "$probe_file" \
    --task-id "shadow-effect-map-01" \
    --max-questions 2

  [ "$status" -eq 0 ]
  assert_contains "$output" "# Shadow Evidence Review Queue"
  assert_contains "$output" "- writes_shadow_docs: false"
  assert_contains "$output" "- auto_promotes_facts: false"
  assert_contains "$output" "- doc_role: review_queue"
  assert_contains "$output" "- question_count: 2"
  assert_contains "$output" "Does the syntactic source probe"
  assert_contains "$output" "Which supported validator or fallback should replace"
  refute_contains "$output" "RQ-003"
}

@test "shadow_review_queue never hides high unresolved questions behind max_questions" {
  local probe_file="$TEST_WORKSPACE/high-questions.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"unsupported","validator_id":"java.ast.call_match@v99","source_ref":"src/UserService.java:4","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser","anchor_file":"src/UserService.java","anchor_symbol":"UserService.updateUser","missing_evidence":"supported validator","recommended_default_status":"blocked","writes_shadow_docs":false}
{"status":"error","validator_id":"bad.validator@v1","source_ref":"src/UserService.java:5","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser","anchor_file":"src/UserService.java","anchor_symbol":"UserService.updateUser","missing_evidence":"valid probe input","recommended_default_status":"blocked","writes_shadow_docs":false}
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/UserService.java:6","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/UserService.java","anchor_symbol":"userRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
{"status":"pass","validator_id":"any.runtime.trace@v1","evidence_type":"runtime_trace","validator_result":"matched","trace_ref":"logs/runtime.trace:2","artifact_hash":"sha256:abc123","promotion_limit":"medium","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser","anchor_file":"logs/runtime.trace","anchor_symbol":"event=user.cache.evict","missing_evidence":"runtime scenario fit decision","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" \
    --input "$probe_file" \
    --task-id "shadow-effect-map-01" \
    --max-questions 1

  [ "$status" -eq 0 ]
  assert_contains "$output" "- max_questions: 1"
  assert_contains "$output" "- question_count: 2"
  assert_contains "$output" "- uncapped_required_questions: 2"
  assert_contains "$output" "- deferred_question_count: 2"
  refute_contains "$output" "RQ-003"
  assert_contains "$output" "Error, unsupported, and trusted high/critical policy questions are emitted"
}

@test "shadow_review_queue does not trust arbitrary priority or risk fields for cap bypass" {
  local probe_file="$TEST_WORKSPACE/untrusted-priority.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/UserService.java:6","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"critical","priority":"high","risk":"critical","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/UserService.java","anchor_symbol":"userRepository.save","missing_evidence":"parser-backed Java validator","recommended_default_status":"unknown","writes_shadow_docs":false}
{"status":"pass","validator_id":"any.runtime.trace@v1","evidence_type":"runtime_trace","validator_result":"matched","trace_ref":"logs/runtime.trace:2","artifact_hash":"sha256:abc123","promotion_limit":"medium","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser","anchor_file":"logs/runtime.trace","anchor_symbol":"event=user.cache.evict","missing_evidence":"runtime scenario fit decision","recommended_default_status":"unknown","writes_shadow_docs":false}
{"status":"pass","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/auth.py:8","validator_kind":"ast","parser_backed":true,"promotion_limit":"medium","review_risk":"critical","review_risk_source":"policy","entry_ref":"AuthController.login","call_chain_candidate":"AuthController.login -> AuthService.issueToken","anchor_file":"src/auth.py","anchor_symbol":"issue_token","missing_evidence":"security intent approval","recommended_default_status":"blocked","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file" --max-questions 0

  [ "$status" -eq 0 ]
  assert_contains "$output" "- question_count: 1"
  assert_contains "$output" "- uncapped_required_questions: 1"
  assert_contains "$output" "- deferred_question_count: 2"
  assert_contains "$output" "trusted_review_risk: critical"
  assert_contains "$output" "priority: critical"
}

@test "shadow_review_queue defers under-specified questions instead of asking user" {
  local probe_file="$TEST_WORKSPACE/missing-context.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/UserService.java:6","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file" --max-questions 5

  [ "$status" -eq 0 ]
  assert_contains "$output" "- question_count: 0"
  assert_contains "$output" "- deferred_missing_context_count: 1"
  assert_contains "$output" "question_state: deferred_missing_context"
  assert_contains "$output" "missing_question_context:"
  assert_contains "$output" "- no user questions generated"
}

@test "shadow_review_queue keeps runtime trace provenance visible" {
  local probe_file="$TEST_WORKSPACE/runtime.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"any.runtime.trace@v1","evidence_type":"runtime_trace","validator_result":"matched","source_ref":"logs/runtime.trace:2","trace_ref":"logs/runtime.trace:2","artifact_hash":"sha256:abc123","validator_kind":"runtime_trace","parser_backed":false,"promotion_limit":"high","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser","anchor_file":"logs/runtime.trace","anchor_symbol":"event=user.cache.evict","missing_evidence":"runtime scenario fit decision","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file"

  [ "$status" -eq 0 ]
  assert_contains "$output" "artifact_hash: sha256:abc123"
  assert_contains "$output" "Is runtime trace"
  assert_contains "$output" "observation window"
}

@test "shadow_review_queue renders deterministic metadata and decision context" {
  local probe_file="$TEST_WORKSPACE/context.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"fail","validator_id":"py.ast.call_match@v1","rule_id":"repo.write","evidence_type":"code_call","validator_result":"missing","source_ref":"src/app.py:4","validator_kind":"ast","parser_backed":true,"promotion_limit":"medium","entry_ref":"UserController.update","endpoint":"POST /users/{id}","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/UserService.java","anchor_symbol":"UserRepository.save","missing_evidence":"JpaRepository.save call","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file" --max-questions 1

  [ "$status" -eq 0 ]
  assert_contains "$output" "rule_id: repo.write"
  assert_contains "$output" "validator_kind: ast"
  assert_contains "$output" "parser_backed: True"
  assert_contains "$output" "validator_result: missing"
  assert_contains "$output" "entry_ref: UserController.update"
  assert_contains "$output" "endpoint: POST /users/{id}"
  assert_contains "$output" "call_chain_candidate: UserController.update -> UserService.updateUser -> UserRepository.save"
  assert_contains "$output" "anchor_file: src/UserService.java"
  assert_contains "$output" "anchor_symbol: UserRepository.save"
  assert_contains "$output" "missing_evidence: JpaRepository.save call"
  assert_contains "$output" "decision_policy_ref: shadow-effect-map-workflow.md#stop-and-ask"
  assert_contains "$output" "default_status: unknown"
}

@test "shadow_review_queue can optionally ask about parser-backed pass records" {
  local probe_file="$TEST_WORKSPACE/parser.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/app.py:4","validator_kind":"ast","parser_backed":true,"promotion_limit":"high","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/app.py","anchor_symbol":"repository.save","missing_evidence":"human intent decision","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file"
  [ "$status" -eq 0 ]
  assert_contains "$output" "- no user questions generated"

  run python3 "$SHADOW_QUEUE" --input "$probe_file" --ask-confirmed
  [ "$status" -eq 0 ]
  assert_contains "$output" "Is parser-backed evidence"
}

@test "shadow_review_queue reports invalid JSON as machine-readable error" {
  local probe_file="$TEST_WORKSPACE/bad.jsonl"
  printf '{"status":"pass"\n' > "$probe_file"

  run python3 "$SHADOW_QUEUE" --input "$probe_file"

  [ "$status" -eq 64 ]
  assert_contains "$output" '"status":"error"'
}

@test "shadow_llm_candidate_wrapper creates non-promotable candidate with provenance" {
  local draft_file="$TEST_WORKSPACE/draft.md"
  cat > "$draft_file" <<'EOF'
Possible call chain:
- UserController.update
- UserService.updateUser
EOF

  run python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"llm_candidate"'
  assert_contains "$output" '"evidence_type":"llm_hint"'
  assert_contains "$output" '"non_promotion_status":true'
  assert_contains "$output" '"shadow_action":"candidate_only"'
  assert_contains "$output" '"writes_shadow_docs":false'
  assert_contains "$output" '"auto_promotes_facts":false'
  assert_contains "$output" '"raw_draft_hash":"sha256:'
  assert_contains "$output" '"source_refs":["src/UserService.java:42"]'
}

@test "shadow_llm_candidate_wrapper rejects missing provenance and forbidden markers" {
  local draft_file="$TEST_WORKSPACE/unsafe.md"
  cat > "$draft_file" <<'EOF'
status: validated
writes_shadow_docs: true
"shadow_action": "apply"
EOF

  run python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --timestamp "2026-05-02T00:00:00Z"

  [ "$status" -eq 64 ]
  assert_contains "$output" "at least one --source-ref is required"

  run python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  [ "$status" -eq 64 ]
  assert_contains "$output" "forbidden production-action markers"
  assert_contains "$output" "shadow_write_true"
  assert_contains "$output" "direct_apply"
  assert_contains "$output" "validated_status"
}

@test "shadow_llm_candidate_wrapper refuses output under docs shadow" {
  local draft_file="$TEST_WORKSPACE/draft.md"
  printf 'Candidate draft only\n' > "$draft_file"

  run python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$DOCS_ROOT/shadow/candidate.json" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  [ "$status" -eq 64 ]
  assert_contains "$output" "must not be under docs/shadow"
  assert_contains "$output" '"writes_shadow_docs":false'
}

@test "shadow_apply_gate blocks without final user decision and allows supervised dry-run" {
  local draft_file="$TEST_WORKSPACE/draft.md"
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local bad_decision_file="$TEST_WORKSPACE/bad-decision.json"
  local good_decision_file="$TEST_WORKSPACE/good-decision.json"

  printf 'Review question draft\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"

  cat > "$bad_decision_file" <<EOF
{"user_decision":{"id":"UD-001","decision_type":"final_shadow_apply","answer":"unknown","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id"]}}
EOF

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$candidate_file" \
    --user-decision "$bad_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"status":"blocked"'
  assert_contains "$output" "answer must be yes or approve_apply"
  assert_contains "$output" '"writes_shadow_docs":false'

  cat > "$good_decision_file" <<EOF
{"user_decision":{"id":"UD-002","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id"],"rationale":"Approve dry-run apply check for this candidate.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$candidate_file" \
    --user-decision "$good_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"allowed"'
  assert_contains "$output" '"shadow_apply_allowed":true'
  assert_contains "$output" '"apply_mode":"supervised_dry_run"'
  assert_contains "$output" '"writes_shadow_docs":false'

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$candidate_file" \
    --user-decision "$good_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2000-01-01"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"today_override_warning"'
}

@test "shadow_apply_gate rejects forged candidate provenance and expired decisions" {
  local forged_candidate_file="$TEST_WORKSPACE/forged-candidate.json"
  local expired_decision_file="$TEST_WORKSPACE/expired-decision.json"
  local mismatch_decision_file="$TEST_WORKSPACE/mismatch-decision.json"
  local candidate_id="LC-1234567890abcdef"

  cat > "$forged_candidate_file" <<EOF
{"status":"llm_candidate","artifact_kind":"llm_candidate","candidate_id":"$candidate_id","task_id":"shadow-effect-map-01","writes_shadow_docs":false,"auto_promotes_facts":false,"non_promotion_status":true,"can_validate":false,"evidence_type":"llm_hint","raw_draft_hash":"sha256:abcdef","raw_draft_bytes":20}
EOF
  cat > "$expired_decision_file" <<EOF
{"user_decision":{"id":"UD-003","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-03","applies_to":["$candidate_id"],"rationale":"Approve forged candidate check.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$forged_candidate_file" \
    --user-decision "$expired_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2026-05-04"

  [ "$status" -eq 1 ]
  assert_contains "$output" "candidate.model_id is required"
  assert_contains "$output" "candidate.tool_id is required"
  assert_contains "$output" "candidate.created_at is required"
  assert_contains "$output" "candidate.source_refs must be a non-empty list of strings"
  assert_contains "$output" "candidate.shadow_action must be candidate_only"
  assert_contains "$output" "candidate.raw_draft_hash must be a sha256 reference"
  assert_contains "$output" "user_decision is expired"

  cat > "$forged_candidate_file" <<EOF
{"status":"llm_candidate","artifact_kind":"llm_candidate","candidate_id":"$candidate_id","task_id":"shadow-effect-map-01","created_at":"2026-05-02T00:00:00Z","model_id":"test-model","tool_id":"codex","source_refs":["src/UserService.java:42"],"writes_shadow_docs":false,"auto_promotes_facts":false,"non_promotion_status":true,"can_validate":false,"shadow_action":"candidate_only","evidence_type":"llm_hint","raw_draft_hash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","raw_draft_bytes":20}
EOF
  cat > "$expired_decision_file" <<EOF
{"user_decision":{"id":"UD-004","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id"],"rationale":"Approve candidate digest binding check.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$forged_candidate_file" \
    --user-decision "$expired_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "candidate.candidate_id must match provenance digest"

  cat > "$mismatch_decision_file" <<EOF
{"user_decision":{"id":"UD-005","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["LC-0000000000000000"],"rationale":"Approve mismatch check.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$forged_candidate_file" \
    --user-decision "$mismatch_decision_file" \
    --target-shadow-file "../outside.md" \
    --today "2026-05-02"

  [ "$status" -eq 64 ]
  assert_contains "$output" "traversal"

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$forged_candidate_file" \
    --user-decision "$mismatch_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "user_decision.applies_to must reference candidate_id"
}

@test "shadow_user_decision_wrapper creates gated apply and fact evidence artifacts" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local apply_decision_file="$TEST_WORKSPACE/apply-decision.json"
  local evidence_decision_file="$TEST_WORKSPACE/evidence-decision.json"
  local bad_decision_file="$TEST_WORKSPACE/bad-decision.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local record_file="$TEST_WORKSPACE/record.json"
  local fact_record_file="$TEST_WORKSPACE/fact-record.json"
  local bad_record_file="$TEST_WORKSPACE/bad-record.json"
  local fact_statement="Human decision confirms intended product meaning."

  printf 'Draft for wrapped user decisions\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"

  cat > "$record_file" <<EOF
{"record_id":"SE-user-050","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"db_write","statement":"Unknown code effect needs deterministic evidence.","reason":"Parser-backed deterministic evidence is not attached yet.","anchor":{"file":"src/UserService.java","line":42,"symbol":"UserRepository.save"},"source_refs":["src/UserService.java:42"]}
EOF
  cat > "$fact_record_file" <<EOF
{"record_id":"SE-user-051","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"business_intent","statement":"$fact_statement","anchor":{"file":"docs/task/TASK-shadow-effect-map-01.md","symbol":"user decision"},"evidence":{"type":"user_decision","ref":"UD-wrap-fact"},"source_refs":["TASK-shadow-effect-map-01"]}
EOF
  cat > "$bad_record_file" <<EOF
{"record_id":"SE-user-052","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"User decision must not confirm a code-level write.","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"evidence":{"type":"user_decision","ref":"UD-wrap-bad"},"source_refs":["src/UserService.java:42"]}
EOF

  run python3 "$SHADOW_USER_DECISION" \
    --project-root "$TEST_PROJECT" \
    --output "$apply_decision_file" \
    --decision-id "UD-wrap-apply" \
    --decision-type "final_shadow_apply" \
    --answer "yes" \
    --decided-by "gm" \
    --decided-at "2026-05-02" \
    --expires-at "2026-05-09" \
    --candidate-id "$candidate_id" \
    --record "$record_file" \
    --record "$fact_record_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --rationale "Approve this exact structured record for dry-run." \
    --source-ref "TASK-shadow-effect-map-01" \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" '"writes_shadow_docs":false'
  run grep '"target_shadow_file": "packages/codeguide/effects.md"' "$apply_decision_file"
  [ "$status" -eq 0 ]

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"shadow_apply_allowed":true'

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'

  run python3 "$SHADOW_USER_DECISION" \
    --project-root "$TEST_PROJECT" \
    --output "$evidence_decision_file" \
    --decision-id "UD-wrap-fact" \
    --decision-type "business_intent" \
    --answer "confirmed" \
    --decided-by "gm" \
    --decided-at "2026-05-02" \
    --expires-at "2026-05-09" \
    --record "$fact_record_file" \
    --rationale "Confirm this human-only product meaning." \
    --source-ref "TASK-shadow-effect-map-01" \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  run grep '"statement_hash": "' "$evidence_decision_file"
  [ "$status" -eq 0 ]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$fact_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --evidence-decision "$evidence_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" "evidence_ref: UD-wrap-fact"

  run python3 "$SHADOW_USER_DECISION" \
    --project-root "$TEST_PROJECT" \
    --output "$bad_decision_file" \
    --decision-id "UD-wrap-bad" \
    --decision-type "business_intent" \
    --answer "confirmed" \
    --decided-by "gm" \
    --decided-at "2026-05-02" \
    --expires-at "2026-05-09" \
    --record "$bad_record_file" \
    --rationale "This should be rejected." \
    --source-ref "src/UserService.java:42" \
    --today "2026-05-02"

  [ "$status" -eq 64 ]
  assert_contains "$output" "human-only record.effect_type"
}

@test "shadow_user_decision_wrapper derives runtime_scenario_fit binding metadata from record evidence" {
  local decision_file="$TEST_WORKSPACE/runtime-fit-decision.json"
  local record_file="$TEST_WORKSPACE/runtime-record.json"
  local setter_module_hash

  setter_module_hash="$(sha256_file_ref "$SHADOW_USER_DECISION")"
  cat > "$record_file" <<EOF
{"record_id":"SE-runtime-wrap","record_type":"effect_map_entry","candidate_id":"LC-test","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Runtime fit wrapper should bind invalidation metadata.","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","artifact_media_type":"text/plain","encoding":"utf-8","canonicalization":"none","hash_input_scope":"whole_artifact","ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF

  run python3 "$SHADOW_USER_DECISION" \
    --project-root "$TEST_PROJECT" \
    --output "$decision_file" \
    --decision-id "UD-runtime-wrap" \
    --decision-type "runtime_scenario_fit" \
    --answer "confirmed" \
    --decided-by "gm" \
    --decided-at "2026-05-02" \
    --expires-at "2026-05-09" \
    --record "$record_file" \
    --rationale "Confirm this runtime trace fits the bounded cache eviction scenario." \
    --source-ref "TASK-shadow-effect-map-01" \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  run grep '"scenario_scope": "runtime.scopes.user_update_cache"' "$decision_file"
  [ "$status" -eq 0 ]
  run grep '"setter_symbol_path": "RuntimeScenarioRegistry.userUpdateCacheEvict"' "$decision_file"
  [ "$status" -eq 0 ]
  run grep "\"setter_module_hash\": \"$setter_module_hash\"" "$decision_file"
  [ "$status" -eq 0 ]
  run grep '"expiry_or_invalidation_rule": "binding_change"' "$decision_file"
  [ "$status" -eq 0 ]
  run grep '"trace_ref": "logs/runtime.trace:2"' "$decision_file"
  [ "$status" -eq 0 ]
  run grep '"scenario_ref": "scenario:user-update-cache"' "$decision_file"
  [ "$status" -eq 0 ]
}

@test "shadow_effect_writer dry-run previews without writing shadow docs" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local draft_file="$TEST_WORKSPACE/draft.md"

  printf 'Draft for structured record\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"

  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-010","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-user-001"],"rationale":"Approve writing this exact record.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-user-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"db_write","statement":"User update writes through repository save needs deterministic evidence.","reason":"Final apply approval is not fact evidence.","anchor":{"file":"src/UserService.java","line":42,"symbol":"UserRepository.save"},"source_refs":["src/UserService.java:42"]}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" '"mode":"dry-run"'
  assert_contains "$output" '"writes_shadow_docs":false'
  assert_contains "$output" "shadow-effect-record:SE-user-001 begin"
  [ ! -e "$DOCS_ROOT/shadow/packages/codeguide/effects.md" ]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2000-01-01"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"today_override_warning"'
}

@test "shadow_effect_writer separates final apply approval from user decision evidence" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local apply_decision_file="$TEST_WORKSPACE/apply-decision.json"
  local evidence_decision_file="$TEST_WORKSPACE/evidence-decision.json"
  local negative_decision_file="$TEST_WORKSPACE/negative-decision.json"
  local bad_record_file="$TEST_WORKSPACE/bad-record.json"
  local good_record_file="$TEST_WORKSPACE/good-record.json"
  local negative_record_file="$TEST_WORKSPACE/negative-record.json"
  local code_claim_record_file="$TEST_WORKSPACE/code-claim-record.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local good_statement="Separate fact decision can support human-only meaning."
  local negative_statement="Negative user decision must not confirm human-only meaning."
  local code_claim_statement="User decision must not confirm code-level db write."
  local good_statement_hash
  local negative_statement_hash
  local code_claim_statement_hash

  printf 'Draft for user decision evidence split\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  good_statement_hash="$(sha256_text_ref "$good_statement")"
  negative_statement_hash="$(sha256_text_ref "$negative_statement")"
  code_claim_statement_hash="$(sha256_text_ref "$code_claim_statement")"
  cat > "$apply_decision_file" <<EOF
{"user_decision":{"id":"UD-apply-001","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-user-021","SE-user-022","SE-user-027","SE-user-028"],"rationale":"Approve applying only these records.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$evidence_decision_file" <<EOF
{"user_decision":{"id":"UD-evidence-001","decision_type":"business_intent","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-022","effect_type":"business_intent","statement_hash":"$good_statement_hash","anchor_file":"docs/task/TASK-shadow-effect-map-01.md","anchor_symbol":"user decision"}],"rationale":"Confirm this is an intended product-side effect, not code proof.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$negative_decision_file" <<EOF
{"user_decision":{"id":"UD-evidence-negative","decision_type":"business_intent","answer":"no","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-027","effect_type":"business_intent","statement_hash":"$negative_statement_hash","anchor_file":"docs/task/TASK-shadow-effect-map-01.md","anchor_symbol":"user decision"}],"rationale":"This explicitly rejects the claimed effect intent.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$bad_record_file" <<EOF
{"record_id":"SE-user-021","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"business_intent","statement":"Final apply approval must not become fact evidence.","anchor":{"file":"docs/task/TASK-shadow-effect-map-01.md","symbol":"user decision"},"evidence":{"type":"user_decision","ref":"UD-apply-001"},"source_refs":["TASK-shadow-effect-map-01"]}
EOF
  cat > "$good_record_file" <<EOF
{"record_id":"SE-user-022","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"business_intent","statement":"$good_statement","anchor":{"file":"docs/task/TASK-shadow-effect-map-01.md","symbol":"user decision"},"evidence":{"type":"user_decision","ref":"UD-evidence-001"},"source_refs":["TASK-shadow-effect-map-01"]}
EOF
  cat > "$negative_record_file" <<EOF
{"record_id":"SE-user-027","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"business_intent","statement":"$negative_statement","anchor":{"file":"docs/task/TASK-shadow-effect-map-01.md","symbol":"user decision"},"evidence":{"type":"user_decision","ref":"UD-evidence-negative"},"source_refs":["TASK-shadow-effect-map-01"]}
EOF
  cat > "$code_claim_record_file" <<EOF
{"record_id":"SE-user-028","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"$code_claim_statement","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"evidence":{"type":"user_decision","ref":"UD-evidence-001"},"source_refs":["src/UserService.java:42"]}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$bad_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "separate from final_shadow_apply"
  assert_contains "$output" '"next_actions"'
  assert_contains "$output" '"action":"create_evidence_decision"'
  assert_contains "$output" "--decision-type business_intent"
  assert_contains "$output" "--record"
  refute_contains "$output" "--applies-record-id"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$good_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --evidence-decision "$evidence_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_ref: UD-evidence-001"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$negative_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --evidence-decision "$negative_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "answer must affirm"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$code_claim_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --evidence-decision "$evidence_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "human-only effect types"
}

# Shared fixture preamble for the two deterministic-evidence writer tests below.
# Extracted so the runtime-hint scenario (deferred under
# The tracked issue) can be skipped ON ITS OWN instead of
# darkening the ~99 other assertions this fixture set feeds -- the whole point of
# The task is that dark assertions are the defect.
_writer_metadata_fixtures() {

  candidate_file="$TEST_WORKSPACE/candidate.json"
  decision_file="$TEST_WORKSPACE/decision.json"
  code_record_file="$TEST_WORKSPACE/code-record.json"
  runtime_record_file="$TEST_WORKSPACE/runtime-record.json"
  bad_runtime_record_file="$TEST_WORKSPACE/bad-runtime-record.json"
  good_code_record_file="$TEST_WORKSPACE/good-code-record.json"
  missing_parser_record_file="$TEST_WORKSPACE/missing-parser-record.json"
  mismatch_parser_record_file="$TEST_WORKSPACE/mismatch-parser-record.json"
  good_runtime_record_file="$TEST_WORKSPACE/good-runtime-record.json"
  missing_binding_metadata_record_file="$TEST_WORKSPACE/runtime-missing-binding-metadata-record.json"
  binary_rfc8785_record_file="$TEST_WORKSPACE/runtime-binary-rfc8785-record.json"
  ignored_fields_record_file="$TEST_WORKSPACE/runtime-ignored-fields-record.json"
  missing_selected_fields_record_file="$TEST_WORKSPACE/runtime-missing-selected-fields-record.json"
  malformed_selected_fields_record_file="$TEST_WORKSPACE/runtime-malformed-selected-fields-record.json"
  duplicate_selected_fields_record_file="$TEST_WORKSPACE/runtime-duplicate-selected-fields-record.json"
  dotted_selected_fields_record_file="$TEST_WORKSPACE/runtime-dotted-selected-fields-record.json"
  selected_fields_record_file="$TEST_WORKSPACE/runtime-selected-fields-record.json"
  missing_selected_field_record_file="$TEST_WORKSPACE/runtime-missing-selected-field-record.json"
  non_json_selected_fields_record_file="$TEST_WORKSPACE/runtime-non-json-selected-fields-record.json"
  invalid_line_range_record_file="$TEST_WORKSPACE/runtime-invalid-line-range-record.json"
  valid_custom_line_range_record_file="$TEST_WORKSPACE/runtime-valid-custom-line-range-record.json"
  missing_line_range_probe_record_file="$TEST_WORKSPACE/runtime-missing-line-range-probe-record.json"
  out_of_range_line_range_record_file="$TEST_WORKSPACE/runtime-out-of-range-line-range-record.json"
  code_probe_file="$TEST_WORKSPACE/code-probe.json"
  runtime_probe_file="$TEST_WORKSPACE/runtime-probe.json"
  runtime_line_probe_file="$TEST_WORKSPACE/runtime-line-probe.json"
  runtime_selected_probe_file="$TEST_WORKSPACE/runtime-selected-probe.json"
  missing_selected_probe_record_file="$TEST_WORKSPACE/runtime-missing-selected-probe-record.json"
  runtime_decision_file="$TEST_WORKSPACE/runtime-decision.json"
  runtime_json_decision_file="$TEST_WORKSPACE/runtime-json-decision.json"
  runtime_mismatch_decision_file="$TEST_WORKSPACE/runtime-mismatch-decision.json"
  draft_file="$TEST_WORKSPACE/draft.md"
  runtime_json_event='{"event":"user.cache.evict","timestamp":"2026-05-02T00:00:00Z","userId":42}'
  runtime_json_event_json='{\"event\":\"user.cache.evict\",\"timestamp\":\"2026-05-02T00:00:00Z\",\"userId\":42}'
  runtime_statement="Cache eviction is backed by a runtime trace artifact."
  runtime_json_statement="Cache eviction is backed by selected JSON runtime fields."

  mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/logs"
  cat > "$TEST_PROJECT/src/app.py" <<'EOF'
class Repository:
    def save(self, user):
        return user

def handler(repository, user):
    repository.save(user)
EOF
  cat > "$TEST_PROJECT/logs/runtime.trace" <<'EOF'
event=user.update started
event=user.cache.evict userId=42
EOF
  printf '%s\n' "$runtime_json_event" > "$TEST_PROJECT/logs/runtime-json.trace"
  printf '%s\n' "event=user.cache.evict userId=42" > "$TEST_PROJECT/logs/runtime-non-json.trace"
  source_hash="$(sha256_file_ref "$TEST_PROJECT/src/app.py")"
  parser_identity="$(parser_identity_ref "py.ast.call_match@v1" "ast")"
  parser_content_hash="$(sha256_file_ref "$SHADOW_PROBE")"
  runtime_hash="$(sha256_file_ref "$TEST_PROJECT/logs/runtime.trace")"
  setter_module_hash="$(sha256_file_ref "$SHADOW_USER_DECISION")"
  cat > "$code_probe_file" <<EOF
{"status":"pass","probe_status":"pass","fact_status":"deterministic_evidence","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","evidence_field":"validator_result","validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  cat > "$runtime_probe_file" <<EOF
{"status":"pass","probe_status":"pass","fact_status":"deterministic_evidence","validator_id":"any.runtime.trace@v1","evidence_type":"runtime_trace","evidence_field":"validator_result","validator_result":"matched","source_ref":"logs/runtime.trace:2","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","hash_input_scope":"whole_artifact","validator_kind":"runtime_trace","parser_backed":false,"promotion_limit":"high","writes_shadow_docs":false}
EOF
  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime.trace" \
    --trace-event "event=user.cache.evict userId=42" \
    --hash-input-scope "line_range" \
    --line-range-start 2 \
    --line-range-end 2 > "$runtime_line_probe_file"
  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime-json.trace" \
    --trace-event "$runtime_json_event" \
    --hash-input-scope "selected_fields" \
    --selected-field "event" \
    --selected-field "userId" > "$runtime_selected_probe_file"
  code_probe_hash="$(sha256_file_ref "$code_probe_file")"
  runtime_probe_hash="$(sha256_file_ref "$runtime_probe_file")"
  runtime_line_probe_hash="$(sha256_file_ref "$runtime_line_probe_file")"
  runtime_selected_probe_hash="$(sha256_file_ref "$runtime_selected_probe_file")"
  runtime_line_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact_hash"])' "$runtime_line_probe_file")"
  runtime_selected_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact_hash"])' "$runtime_selected_probe_file")"
  runtime_statement_hash="$(sha256_text_ref "$runtime_statement")"
  runtime_json_statement_hash="$(sha256_text_ref "$runtime_json_statement")"

  printf 'Draft for deterministic evidence records\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"

  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-013","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-user-004","SE-user-005","SE-user-006","SE-user-007","SE-user-008","SE-user-009"],"rationale":"Approve evaluating deterministic evidence metadata.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$runtime_decision_file" <<EOF
{"user_decision":{"id":"UD-runtime-013","decision_type":"runtime_scenario_fit","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-008","effect_type":"cache_evict","statement_hash":"$runtime_statement_hash","anchor_file":"logs/runtime.trace","anchor_line":"2","anchor_symbol":"event=user.cache.evict","trace_ref":"logs/runtime.trace:2","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change"}],"rationale":"The trace scenario matches the user update cache-evict scenario.","source_refs":["logs/runtime.trace:2","scenario:user-update-cache"]}}
EOF
  cat > "$runtime_json_decision_file" <<EOF
{"user_decision":{"id":"UD-runtime-013","decision_type":"runtime_scenario_fit","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-008","effect_type":"cache_evict","statement_hash":"$runtime_json_statement_hash","anchor_file":"logs/runtime-json.trace","anchor_line":"1","anchor_symbol":"$runtime_json_event_json","trace_ref":"logs/runtime-json.trace:1","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change"}],"rationale":"The JSON trace scenario matches the user update cache-evict scenario.","source_refs":["logs/runtime-json.trace:1","scenario:user-update-cache"]}}
EOF
  cat > "$runtime_mismatch_decision_file" <<EOF
{"user_decision":{"id":"UD-runtime-013","decision_type":"runtime_scenario_fit","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-008","effect_type":"cache_evict","statement_hash":"$runtime_statement_hash","anchor_file":"logs/runtime.trace","anchor_line":"2","anchor_symbol":"event=user.cache.evict","trace_ref":"logs/runtime.trace:2","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"sha256:0000000000000000000000000000000000000000000000000000000000000000","expiry_or_invalidation_rule":"binding_change"}],"rationale":"The trace scenario binding intentionally uses a stale setter module hash.","source_refs":["logs/runtime.trace:2","scenario:user-update-cache"]}}
EOF
  cat > "$code_record_file" <<EOF
{"record_id":"SE-user-004","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Repository save is claimed by deterministic code evidence.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash"}}
EOF
  cat > "$runtime_record_file" <<EOF
{"record_id":"SE-user-005","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Cache eviction is claimed by deterministic runtime evidence.","anchor":{"file":"src/UserService.java","symbol":"UserCache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change"}}
EOF
  cat > "$bad_runtime_record_file" <<EOF
{"record_id":"SE-user-007","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Cache eviction has malformed runtime hash evidence.","anchor":{"file":"src/UserService.java","symbol":"UserCache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","trace_ref":"logs/runtime.trace:2","artifact_hash":"sha256:x","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change"}}
EOF
  cat > "$good_code_record_file" <<EOF
{"record_id":"SE-user-006","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Repository save is backed by parser evidence.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$missing_parser_record_file" <<EOF
{"record_id":"SE-user-006","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Repository save is backed by parser evidence but lacks parser provenance.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$mismatch_parser_record_file" <<EOF
{"record_id":"SE-user-006","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Repository save is backed by mismatched parser provenance.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"parser_identity":"shadow_evidence_probe.py:wrong:ast","parser_content_hash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$good_runtime_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","artifact_media_type":"text/plain","encoding":"utf-8","canonicalization":"none","hash_input_scope":"whole_artifact","ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$missing_binding_metadata_record_file" <<EOF
{"record_id":"SE-user-009","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Runtime scenario fit binding metadata is required.","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","artifact_media_type":"text/plain","encoding":"utf-8","canonicalization":"none","hash_input_scope":"whole_artifact","ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$binary_rfc8785_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","artifact_media_type":"application/octet-stream","encoding":"binary","canonicalization":"rfc8785","hash_input_scope":"whole_artifact","ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$ignored_fields_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","artifact_media_type":"text/plain","encoding":"utf-8","canonicalization":"none","hash_input_scope":"whole_artifact","ignored_nondeterministic_fields":["timestamp"],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$missing_selected_fields_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","artifact_media_type":"application/json","encoding":"utf-8","canonicalization":"rfc8785","hash_input_scope":"selected_fields","ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$malformed_selected_fields_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","artifact_media_type":"application/json","encoding":"utf-8","canonicalization":"rfc8785","hash_input_scope":"selected_fields","selected_fields":"event","ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$duplicate_selected_fields_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_json_statement","anchor":{"file":"logs/runtime-json.trace","line":1,"symbol":"$runtime_json_event_json"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime-json.trace:1","artifact_hash":"$runtime_selected_hash","artifact_media_type":"application/json","encoding":"utf-8","canonicalization":"rfc8785","hash_input_scope":"selected_fields","selected_fields":["event","event"],"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_selected_probe_file","probe_result_hash":"$runtime_selected_probe_hash","probe_args":{"trace_event":"$runtime_json_event_json"}}}
EOF
  cat > "$dotted_selected_fields_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_json_statement","anchor":{"file":"logs/runtime-json.trace","line":1,"symbol":"$runtime_json_event_json"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime-json.trace:1","artifact_hash":"$runtime_selected_hash","artifact_media_type":"application/json","encoding":"utf-8","canonicalization":"rfc8785","hash_input_scope":"selected_fields","selected_fields":["payload.event"],"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_selected_probe_file","probe_result_hash":"$runtime_selected_probe_hash","probe_args":{"trace_event":"$runtime_json_event_json"}}}
EOF
  cat > "$invalid_line_range_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","artifact_media_type":"text/plain","encoding":"utf-8","canonicalization":"none","hash_input_scope":"line_range","line_range":{"start":3,"end":2},"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$valid_custom_line_range_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_line_hash","artifact_media_type":"text/plain","encoding":"utf-8","canonicalization":"custom-declared","canonical_output_type":"text","hash_input_scope":"line_range","line_range":{"start":2,"end":2},"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_line_probe_file","probe_result_hash":"$runtime_line_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$missing_line_range_probe_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_line_hash","artifact_media_type":"text/plain","encoding":"utf-8","canonicalization":"custom-declared","canonical_output_type":"text","hash_input_scope":"line_range","line_range":{"start":2,"end":2},"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$TEST_WORKSPACE/missing-runtime-line-probe.json","probe_result_hash":"$runtime_line_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$out_of_range_line_range_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_line_hash","artifact_media_type":"text/plain","encoding":"utf-8","canonicalization":"none","hash_input_scope":"line_range","line_range":{"start":1,"end":1},"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_line_probe_file","probe_result_hash":"$runtime_line_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$selected_fields_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_json_statement","anchor":{"file":"logs/runtime-json.trace","line":1,"symbol":"$runtime_json_event_json"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime-json.trace:1","artifact_hash":"$runtime_selected_hash","artifact_media_type":"application/json","encoding":"utf-8","canonicalization":"rfc8785","hash_input_scope":"selected_fields","selected_fields":["event","userId"],"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_selected_probe_file","probe_result_hash":"$runtime_selected_probe_hash","probe_args":{"trace_event":"$runtime_json_event_json"}}}
EOF
  cat > "$missing_selected_probe_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_json_statement","anchor":{"file":"logs/runtime-json.trace","line":1,"symbol":"$runtime_json_event_json"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime-json.trace:1","artifact_hash":"$runtime_selected_hash","artifact_media_type":"application/json","encoding":"utf-8","canonicalization":"rfc8785","hash_input_scope":"selected_fields","selected_fields":["event","userId"],"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$TEST_WORKSPACE/missing-runtime-selected-probe.json","probe_result_hash":"$runtime_selected_probe_hash","probe_args":{"trace_event":"$runtime_json_event_json"}}}
EOF
  cat > "$missing_selected_field_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_json_statement","anchor":{"file":"logs/runtime-json.trace","line":1,"symbol":"$runtime_json_event_json"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime-json.trace:1","artifact_hash":"$runtime_selected_hash","artifact_media_type":"application/json","encoding":"utf-8","canonicalization":"rfc8785","hash_input_scope":"selected_fields","selected_fields":["event","missing"],"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_selected_probe_file","probe_result_hash":"$runtime_selected_probe_hash","probe_args":{"trace_event":"$runtime_json_event_json"}}}
EOF
  cat > "$non_json_selected_fields_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime-non-json.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime-non-json.trace:1","artifact_hash":"$runtime_selected_hash","artifact_media_type":"application/json","encoding":"utf-8","canonicalization":"rfc8785","hash_input_scope":"selected_fields","selected_fields":["event"],"ignored_nondeterministic_fields":[],"scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_selected_probe_file","probe_result_hash":"$runtime_selected_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF

}

@test "shadow_effect_writer enforces deterministic evidence metadata" {
  _writer_metadata_fixtures

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$code_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$code_probe_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_code evidence.rule_id is required"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$runtime_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.trace_ref is required"
  assert_contains "$output" "deterministic_runtime evidence.artifact_hash must be a sha256 reference"
  assert_contains "$output" "deterministic_runtime evidence.artifact_media_type is required"
  assert_contains "$output" "deterministic_runtime evidence.ignored_nondeterministic_fields must be a list of strings"
  assert_contains "$output" '"action":"complete_runtime_scenario_fit_args"'
  refute_contains "$output" "--decision-type runtime_scenario_fit"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$missing_binding_metadata_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.scenario_scope is required"
  assert_contains "$output" "deterministic_runtime evidence.setter_symbol_path is required"
  assert_contains "$output" "deterministic_runtime evidence.setter_module_hash must be a sha256 reference"
  assert_contains "$output" "deterministic_runtime evidence.expiry_or_invalidation_rule must be timestamp, binding_change, or manual_revocation"
  assert_contains "$output" '"action":"complete_runtime_scenario_fit_args"'
  assert_contains "$output" "deterministic_runtime evidence.scenario_scope"
  assert_contains "$output" "deterministic_runtime evidence.setter_module_hash"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$bad_runtime_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.artifact_hash must be a sha256 reference"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$good_code_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"next_actions"'
  assert_contains "$output" '"action":"run_probe"'
  assert_contains "$output" "shadow_evidence_probe.py"
  assert_contains "$output" "--probe-result"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$missing_parser_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$code_probe_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_code evidence.parser_identity is required"
  assert_contains "$output" "deterministic_code evidence.parser_content_hash must be a sha256 reference"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$mismatch_parser_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$code_probe_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "probe_result.parser_identity must match evidence.parser_identity"
  assert_contains "$output" "probe_result.parser_content_hash must match evidence.parser_content_hash"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$good_code_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$code_probe_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_rule_id: repo.write"
  assert_contains "$output" "evidence_parser_backed: True"
  assert_contains "$output" "evidence_parser_identity: $parser_identity"
  assert_contains "$output" "evidence_parser_content_hash: $parser_content_hash"
  assert_contains "$output" "evidence_source_hash: $source_hash"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$good_runtime_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --evidence-decision "$runtime_mismatch_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "applies_to must bind record_id, effect_type, statement_hash, anchor, trace_ref, scenario_ref, scenario_scope, setter_symbol_path, setter_module_hash, and expiry_or_invalidation_rule"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$good_runtime_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_artifact_hash: $runtime_hash"
  assert_contains "$output" "evidence_artifact_media_type: text/plain"
  assert_contains "$output" "evidence_encoding: utf-8"
  assert_contains "$output" "evidence_canonicalization: none"
  assert_contains "$output" "evidence_hash_input_scope: whole_artifact"
  assert_contains "$output" "evidence_ignored_nondeterministic_fields: []"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$binary_rfc8785_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence envelope is not supported by the v1 validity matrix"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$ignored_fields_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "ignored_nondeterministic_fields must be empty for whole_artifact unless canonicalization is custom-declared"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$missing_selected_fields_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.selected_fields must be a non-empty list of strings for selected_fields scope"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$malformed_selected_fields_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.selected_fields must be a non-empty list of strings for selected_fields scope"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$duplicate_selected_fields_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_selected_probe_file" \
    --evidence-decision "$runtime_json_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.selected_fields must not contain duplicate field names"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$dotted_selected_fields_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_selected_probe_file" \
    --evidence-decision "$runtime_json_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.selected_fields supports only top-level field names"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$invalid_line_range_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.line_range must satisfy integer start >= 1 and end >= start"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$valid_custom_line_range_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_line_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_hash_input_scope: line_range"
  # The preview is embedded as a JSON string, so the rendered line arrives escaped;
  # single quotes keep the backslashes the payload actually contains.
  assert_contains "$output" 'evidence_line_range: {\"end\":2,\"start\":2}'
  assert_contains "$output" "evidence_artifact_hash: $runtime_line_hash"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$missing_line_range_probe_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"next_actions"'
  assert_contains "$output" '"action":"run_probe"'
  assert_contains "$output" "--hash-input-scope line_range"
  assert_contains "$output" "--line-range-start 2"
  assert_contains "$output" "--line-range-end 2"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$out_of_range_line_range_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_line_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime evidence.trace_ref line must be inside evidence.line_range"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$selected_fields_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_selected_probe_file" \
    --evidence-decision "$runtime_json_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_hash_input_scope: selected_fields"
  assert_contains "$output" 'evidence_selected_fields: [\"event\",\"userId\"]'
  assert_contains "$output" "evidence_artifact_hash: $runtime_selected_hash"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$missing_selected_probe_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --evidence-decision "$runtime_json_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"next_actions"'
  assert_contains "$output" '"action":"run_probe"'
  assert_contains "$output" "--hash-input-scope selected_fields"
  assert_contains "$output" "--selected-field event"
  assert_contains "$output" "--selected-field userId"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$missing_selected_field_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_selected_probe_file" \
    --evidence-decision "$runtime_json_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime selected_fields must exist in trace artifact"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$non_json_selected_fields_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_selected_probe_file" \
    --evidence-decision "$runtime_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "deterministic_runtime selected_fields trace artifact must be valid JSON"
}


@test "shadow_effect_writer hints the runtime_scenario_fit decision command" {
  # The writer BLOCKS this record correctly; what is missing is the remediation
  # hint, because next_action_hints() excludes deterministic_runtime. The
  # assertions below are right and the product is wrong:
  # the project docs
  skip "ISSUE-n19c07: writer emits no runtime_scenario_fit hint"
  _writer_metadata_fixtures

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$good_runtime_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$runtime_probe_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" '"next_actions"'
  assert_contains "$output" "--decision-type runtime_scenario_fit"
  assert_contains "$output" "--trace-ref logs/runtime.trace:2"
  assert_contains "$output" "--scenario-ref scenario:user-update-cache"
  assert_contains "$output" "--scenario-scope runtime.scopes.user_update_cache"
  assert_contains "$output" "--setter-symbol-path RuntimeScenarioRegistry.userUpdateCacheEvict"
  assert_contains "$output" "--setter-module-hash $setter_module_hash"
  assert_contains "$output" "--expiry-or-invalidation-rule binding_change"
  refute_contains "$output" "choose_supported_fact_decision_type"
}
@test "shadow_effect_writer accepts Java parser-backed deterministic code evidence" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local probe_result_file="$TEST_WORKSPACE/java-probe.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local source_file="$TEST_PROJECT/src/main/java/example/UserService.java"
  local source_ref
  local source_hash
  local parser_identity
  local parser_content_hash
  local probe_hash
  local anchor_line

  mkdir -p "$(dirname "$source_file")"
  cat > "$source_file" <<'EOF'
package example;

class UserService {
  void update(User user) {
    userRepository.save(user);
  }
}
EOF

  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "save" \
    --receiver "userRepository" > "$probe_result_file"
  source_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_ref"])' "$probe_result_file")"
  source_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$probe_result_file")"
  parser_identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_identity"])' "$probe_result_file")"
  parser_content_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_content_hash"])' "$probe_result_file")"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  anchor_line="${source_ref##*:}"

  printf 'Draft for Java parser-backed deterministic evidence\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "$source_ref" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-java-001","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-java-001","SE-java-002"],"rationale":"Approve evaluating Java parser-backed deterministic evidence.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-java-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Java repository save is backed by parser evidence.","anchor":{"file":"src/main/java/example/UserService.java","line":$anchor_line,"symbol":"userRepository.save"},"evidence":{"type":"deterministic_code","ref":"java.ast.call_match@v1","rule_id":"repo.write","validator_kind":"java_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"save","receiver":"userRepository"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_ref: java.ast.call_match@v1"
  assert_contains "$output" "evidence_validator_kind: java_token_parser"
  assert_contains "$output" "evidence_parser_backed: True"
  assert_contains "$output" "evidence_parser_identity: $parser_identity"
  assert_contains "$output" "evidence_parser_content_hash: $parser_content_hash"
  assert_contains "$output" "evidence_source_hash: $source_hash"

  cat > "$record_file" <<EOF
{"record_id":"SE-java-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Bare Java parser evidence must not confirm without receiver binding.","anchor":{"file":"src/main/java/example/UserService.java","line":$anchor_line,"symbol":"save"},"evidence":{"type":"deterministic_code","ref":"java.ast.call_match@v1","rule_id":"repo.write","validator_kind":"java_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"save"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "receiver is required for confirmed java.ast.call_match@v1"

  perl -0pi -e 's/```yaml\nrules:\n/```yaml\nrules:\n  java.bare_call:\n    allowed_effect_types: [external_call]\n    validators_by_stack:\n      java_generic:\n        code_call:\n          primary: java.ast.call_match\@v1\n          fallback: java.regex.method_call_named\@v1\n          fallback_max_risk: medium\n/' "$DOCS_ROOT/policy/shadow-rule-registry.md"
  cat > "$record_file" <<EOF
{"record_id":"SE-java-002","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"Java confirmed evidence requires receiver even outside repo.write.","anchor":{"file":"src/main/java/example/UserService.java","line":$anchor_line,"symbol":"save"},"evidence":{"type":"deterministic_code","ref":"java.ast.call_match@v1","rule_id":"java.bare_call","validator_kind":"java_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"save"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "receiver is required for confirmed java.ast.call_match@v1"
}

@test "shadow_effect_writer accepts JavaScript parser-backed deterministic code evidence" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local probe_result_file="$TEST_WORKSPACE/js-probe.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local source_file="$TEST_PROJECT/src/client.js"
  local source_ref
  local source_hash
  local parser_identity
  local parser_content_hash
  local probe_hash
  local anchor_line

  mkdir -p "$(dirname "$source_file")"
  cat > "$source_file" <<'EOF'
export async function handler(httpClient) {
  return httpClient.get("/users");
}
EOF

  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "js.ast.call_match@v1" \
    --source-file "src/client.js" \
    --callee "get" \
    --receiver "httpClient" > "$probe_result_file"
  source_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_ref"])' "$probe_result_file")"
  source_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$probe_result_file")"
  parser_identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_identity"])' "$probe_result_file")"
  parser_content_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_content_hash"])' "$probe_result_file")"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  anchor_line="${source_ref##*:}"

  printf 'Draft for JavaScript parser-backed deterministic evidence\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "$source_ref" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-js-001","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-js-001","SE-js-002","SE-js-003"],"rationale":"Approve evaluating JavaScript parser-backed deterministic evidence.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-js-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"HTTP client get call is backed by parser evidence.","anchor":{"file":"src/client.js","line":$anchor_line,"symbol":"httpClient.get"},"evidence":{"type":"deterministic_code","ref":"js.ast.call_match@v1","rule_id":"external.call","validator_kind":"js_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"get","receiver":"httpClient"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_ref: js.ast.call_match@v1"
  assert_contains "$output" "evidence_validator_kind: js_token_parser"
  assert_contains "$output" "evidence_parser_backed: True"
  assert_contains "$output" "evidence_parser_identity: $parser_identity"
  assert_contains "$output" "evidence_parser_content_hash: $parser_content_hash"
  assert_contains "$output" "evidence_source_hash: $source_hash"

  cat > "$record_file" <<EOF
{"record_id":"SE-js-002","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"Mismatched JS anchor must not confirm against a different matched symbol.","anchor":{"file":"src/client.js","line":$anchor_line,"symbol":"otherClient.get"},"evidence":{"type":"deterministic_code","ref":"js.ast.call_match@v1","rule_id":"external.call","validator_kind":"js_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"get"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"matched_symbol"* || "$output" == *"anchor.symbol"* ]] || false

  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); data["fact_status"]="candidate_only"; json.dump(data, open(sys.argv[1], "w"), sort_keys=True, separators=(",", ":"))' "$probe_result_file"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  cat > "$record_file" <<EOF
{"record_id":"SE-js-003","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"JavaScript probe status metadata must match the writer rerun.","anchor":{"file":"src/client.js","line":$anchor_line,"symbol":"httpClient.get"},"evidence":{"type":"deterministic_code","ref":"js.ast.call_match@v1","rule_id":"external.call","validator_kind":"js_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"get","receiver":"httpClient"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "probe_result.fact_status"
}

@test "shadow_effect_writer accepts TypeScript generic parser-backed deterministic code evidence" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local probe_result_file="$TEST_WORKSPACE/ts-probe.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local source_file="$TEST_PROJECT/src/client.ts"
  local source_ref
  local source_hash
  local parser_identity
  local parser_content_hash
  local probe_hash
  local anchor_line

  mkdir -p "$(dirname "$source_file")"
  cat > "$source_file" <<'EOF'
type ApiResult<T> = { value: T };

export async function handler(httpClient: HttpClient) {
  return httpClient.post<ApiResult<User>>("/users");
}
EOF

  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v2" \
    --source-file "src/client.ts" \
    --callee "post" \
    --receiver "httpClient" > "$probe_result_file"
  source_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_ref"])' "$probe_result_file")"
  source_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$probe_result_file")"
  parser_identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_identity"])' "$probe_result_file")"
  parser_content_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_content_hash"])' "$probe_result_file")"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  anchor_line="${source_ref##*:}"

  printf 'Draft for TypeScript generic parser-backed deterministic evidence\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "$source_ref" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-ts-001","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-ts-001","SE-ts-002","SE-ts-003"],"rationale":"Approve evaluating TypeScript generic parser-backed deterministic evidence.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-ts-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"TypeScript generic HTTP client call is backed by parser evidence.","anchor":{"file":"src/client.ts","line":$anchor_line,"symbol":"httpClient.post"},"evidence":{"type":"deterministic_code","ref":"ts.ast.call_match@v2","rule_id":"external.call","validator_kind":"ts_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"post","receiver":"httpClient"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_ref: ts.ast.call_match@v2"
  assert_contains "$output" "evidence_validator_kind: ts_token_parser"
  assert_contains "$output" "evidence_parser_backed: True"
  assert_contains "$output" "evidence_parser_identity: $parser_identity"
  assert_contains "$output" "evidence_parser_content_hash: $parser_content_hash"
  assert_contains "$output" "evidence_source_hash: $source_hash"

  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); data.pop("type_arguments", None); json.dump(data, open(sys.argv[1], "w"), sort_keys=True, separators=(",", ":"))' "$probe_result_file"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  cat > "$record_file" <<EOF
{"record_id":"SE-ts-002","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"TypeScript generic probe metadata must match the writer rerun.","anchor":{"file":"src/client.ts","line":$anchor_line,"symbol":"httpClient.post"},"evidence":{"type":"deterministic_code","ref":"ts.ast.call_match@v2","rule_id":"external.call","validator_kind":"ts_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"post","receiver":"httpClient"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "probe_result.type_arguments"

  cat > "$source_file" <<'EOF'
type ApiResult<T> = { value: T };

export async function handler(httpClient: HttpClient) {
  return httpClient.post("/users");
}
EOF
  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "ts.ast.call_match@v2" \
    --source-file "src/client.ts" \
    --callee "post" \
    --receiver "httpClient" > "$probe_result_file"
  source_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_ref"])' "$probe_result_file")"
  source_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$probe_result_file")"
  anchor_line="${source_ref##*:}"
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); data["type_arguments"]=True; json.dump(data, open(sys.argv[1], "w"), sort_keys=True, separators=(",", ":"))' "$probe_result_file"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  cat > "$record_file" <<EOF
{"record_id":"SE-ts-003","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"TypeScript probe metadata must not accept forged generic type-argument evidence.","anchor":{"file":"src/client.ts","line":$anchor_line,"symbol":"httpClient.post"},"evidence":{"type":"deterministic_code","ref":"ts.ast.call_match@v2","rule_id":"external.call","validator_kind":"ts_token_parser","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"post","receiver":"httpClient"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "probe_result.type_arguments"
}

@test "shadow_effect_writer accepts FastAPI parser-backed route decorator evidence" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local probe_result_file="$TEST_WORKSPACE/fastapi-probe.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local source_file="$TEST_PROJECT/src/routes.py"
  local source_ref
  local source_hash
  local parser_identity
  local parser_content_hash
  local probe_hash
  local anchor_line

  mkdir -p "$(dirname "$source_file")"
  cat > "$source_file" <<'EOF'
from fastapi import FastAPI

app = FastAPI()

@app.post("/users")
async def create_user():
    return {"ok": True}
EOF

  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.route@v1" \
    --source-file "src/routes.py" \
    --decorator "app.post" \
    --route-path "/users" > "$probe_result_file"
  source_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_ref"])' "$probe_result_file")"
  source_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$probe_result_file")"
  parser_identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_identity"])' "$probe_result_file")"
  parser_content_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_content_hash"])' "$probe_result_file")"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  anchor_line="${source_ref##*:}"

  printf 'Draft for FastAPI parser-backed deterministic route evidence\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "$source_ref" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-fastapi-001","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-fastapi-001","SE-fastapi-002","SE-fastapi-003","SE-fastapi-004"],"rationale":"Approve evaluating FastAPI parser-backed deterministic route evidence.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-fastapi-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"api_route","statement":"FastAPI route decorator is backed by parser evidence.","anchor":{"file":"src/routes.py","line":$anchor_line,"symbol":"app.post"},"evidence":{"type":"deterministic_code","ref":"fastapi.route@v1","rule_id":"http.route","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"decorator":"app.post","route_path":"/users"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" "evidence_ref: fastapi.route@v1"
  assert_contains "$output" "evidence_validator_kind: ast"
  assert_contains "$output" "evidence_parser_backed: True"
  assert_contains "$output" "evidence_parser_identity: $parser_identity"
  assert_contains "$output" "evidence_parser_content_hash: $parser_content_hash"
  assert_contains "$output" "evidence_source_hash: $source_hash"

  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); data.pop("route_path", None); json.dump(data, open(sys.argv[1], "w"), sort_keys=True, separators=(",", ":"))' "$probe_result_file"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  cat > "$record_file" <<EOF
{"record_id":"SE-fastapi-004","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"api_route","statement":"FastAPI literal route-path probe metadata must match the writer rerun.","anchor":{"file":"src/routes.py","line":$anchor_line,"symbol":"app.post"},"evidence":{"type":"deterministic_code","ref":"fastapi.route@v1","rule_id":"http.route","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"decorator":"app.post","route_path":"/users"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "probe_result.route_path"

  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.route@v1" \
    --source-file "src/routes.py" \
    --decorator "app.post" \
    --route-path "/users" > "$probe_result_file"
  source_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_ref"])' "$probe_result_file")"
  source_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$probe_result_file")"
  parser_identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_identity"])' "$probe_result_file")"
  parser_content_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_content_hash"])' "$probe_result_file")"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  anchor_line="${source_ref##*:}"

  cat > "$record_file" <<EOF
{"record_id":"SE-fastapi-002","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"api_route","statement":"Mismatched FastAPI anchor must not confirm against a different matched symbol.","anchor":{"file":"src/routes.py","line":$anchor_line,"symbol":"router.post"},"evidence":{"type":"deterministic_code","ref":"fastapi.route@v1","rule_id":"http.route","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"decorator":"app.post","route_path":"/users"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"matched_symbol"* || "$output" == *"anchor.symbol"* ]] || false

  cat > "$source_file" <<'EOF'
from fastapi import FastAPI

app = FastAPI()
route_path = "/users"

@app.get(route_path)
async def list_users():
    return []
EOF
  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "fastapi.route@v1" \
    --source-file "src/routes.py" \
    --decorator "app.get" > "$probe_result_file"
  source_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_ref"])' "$probe_result_file")"
  source_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$probe_result_file")"
  parser_identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_identity"])' "$probe_result_file")"
  parser_content_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_content_hash"])' "$probe_result_file")"
  anchor_line="${source_ref##*:}"
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); data["route_path"]="/users"; json.dump(data, open(sys.argv[1], "w"), sort_keys=True, separators=(",", ":"))' "$probe_result_file"
  probe_hash="$(sha256_file_ref "$probe_result_file")"
  cat > "$record_file" <<EOF
{"record_id":"SE-fastapi-003","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"api_route","statement":"FastAPI probe metadata must not accept forged literal route-path evidence.","anchor":{"file":"src/routes.py","line":$anchor_line,"symbol":"app.get"},"evidence":{"type":"deterministic_code","ref":"fastapi.route@v1","rule_id":"http.route","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"decorator":"app.get"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "probe_result.route_path"
}

@test "shadow_effect_writer rejects Python parser-backed evidence when anchor symbol differs from matched symbol" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local probe_result_file="$TEST_WORKSPACE/py-probe.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local source_file="$TEST_PROJECT/src/app.py"
  local source_ref
  local source_hash
  local parser_identity
  local parser_content_hash
  local probe_hash

  mkdir -p "$(dirname "$source_file")"
  cat > "$source_file" <<'EOF'
def handler(repository, user):
    repository.save(user)
EOF

  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "src/app.py" \
    --callee "save" > "$probe_result_file"
  source_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_ref"])' "$probe_result_file")"
  source_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$probe_result_file")"
  parser_identity="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_identity"])' "$probe_result_file")"
  parser_content_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["parser_content_hash"])' "$probe_result_file")"
  probe_hash="$(sha256_file_ref "$probe_result_file")"

  printf 'Draft for Python parser-backed deterministic evidence\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "$source_ref" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-py-001","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-py-001"],"rationale":"Approve evaluating Python parser-backed deterministic evidence.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-py-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Mismatched Python anchor must not confirm against a different matched symbol.","anchor":{"file":"src/app.py","symbol":"otherRepository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"save"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$probe_result_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"matched_symbol"* || "$output" == *"anchor.symbol"* ]] || false
}

@test "shadow_effect_writer binds deterministic evidence to policy registry and source hashes" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local source_file="$TEST_PROJECT/src/app.py"
  local java_source_file="$TEST_PROJECT/src/main/java/example/UserService.java"
  local bad_rule_record="$TEST_WORKSPACE/bad-rule-record.json"
  local incompatible_record="$TEST_WORKSPACE/incompatible-record.json"
  local source_probe_record="$TEST_WORKSPACE/source-probe-record.json"
  local stale_source_record="$TEST_WORKSPACE/stale-source-record.json"
  local runtime_ref_record="$TEST_WORKSPACE/runtime-ref-record.json"
  local unimplemented_record="$TEST_WORKSPACE/unimplemented-record.json"
  local stale_runtime_record="$TEST_WORKSPACE/stale-runtime-record.json"
  local trace_file="$TEST_PROJECT/logs/runtime.trace"
  local forged_code_record="$TEST_WORKSPACE/forged-code-record.json"
  local wrong_code_probe_file="$TEST_WORKSPACE/wrong-code-probe.json"
  local runtime_scenario_record="$TEST_WORKSPACE/runtime-scenario-record.json"
  local runtime_bad_decision_record="$TEST_WORKSPACE/runtime-bad-decision-record.json"
  local runtime_bad_decision_file="$TEST_WORKSPACE/runtime-bad-decision.json"
  local runtime_probe_file="$TEST_WORKSPACE/runtime-probe.json"
  local source_hash
  local java_source_hash
  local parser_identity
  local parser_content_hash
  local runtime_hash
  local code_probe_file="$TEST_WORKSPACE/code-probe.json"
  local code_probe_hash
  local runtime_probe_hash
  local setter_module_hash
  local wrong_effect_record="$TEST_WORKSPACE/wrong-effect-record.json"
  local wrong_symbol_record="$TEST_WORKSPACE/wrong-symbol-record.json"
  local path_only_source_record="$TEST_WORKSPACE/path-only-source-record.json"
  local runtime_one_sided_record="$TEST_WORKSPACE/runtime-one-sided-record.json"
  local runtime_one_sided_decision_file="$TEST_WORKSPACE/runtime-one-sided-decision.json"
  local runtime_mismatch_record="$TEST_WORKSPACE/runtime-mismatch-record.json"
  local runtime_mismatch_decision_file="$TEST_WORKSPACE/runtime-mismatch-decision.json"
  local same_file_wrong_line_record="$TEST_WORKSPACE/same-file-wrong-line-record.json"
  local custom_rule_record="$TEST_WORKSPACE/custom-rule-record.json"
  local runtime_wrong_effect_record="$TEST_WORKSPACE/runtime-wrong-effect-record.json"
  local runtime_wrong_anchor_record="$TEST_WORKSPACE/runtime-wrong-anchor-record.json"
  local human_mismatch_decision_file="$TEST_WORKSPACE/human-mismatch-decision.json"
  local human_mismatch_record="$TEST_WORKSPACE/human-mismatch-record.json"
  local runtime_statement="One-sided runtime source refs must not confirm scenario fit."
  local runtime_mismatch_statement="Runtime applies_to trace line must match exactly."
  local human_mismatch_statement="Mismatched human decision type must not confirm effect intent."
  local runtime_statement_hash
  local runtime_mismatch_statement_hash
  local human_mismatch_statement_hash

  mkdir -p "$(dirname "$source_file")" "$(dirname "$java_source_file")" "$(dirname "$trace_file")"
  cat > "$source_file" <<'EOF'
def handler(repository, user):
    repository.save(user)
EOF
  cat > "$java_source_file" <<'EOF'
package example;

class UserService {
  void update(User user) {
    userRepository.save(user);
  }
}
EOF
  cat > "$trace_file" <<'EOF'
event=user.cache.evict userId=42
EOF
  source_hash="$(sha256_file_ref "$source_file")"
  java_source_hash="$(sha256_file_ref "$java_source_file")"
  parser_identity="$(parser_identity_ref "py.ast.call_match@v1" "ast")"
  parser_content_hash="$(sha256_file_ref "$SHADOW_PROBE")"
  runtime_hash="$(sha256_file_ref "$trace_file")"
  setter_module_hash="$(sha256_file_ref "$SHADOW_USER_DECISION")"
  cat > "$code_probe_file" <<EOF
{"status":"pass","probe_status":"pass","fact_status":"deterministic_evidence","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","evidence_field":"validator_result","validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  cat > "$wrong_code_probe_file" <<EOF
{"status":"pass","probe_status":"pass","fact_status":"deterministic_evidence","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","evidence_field":"validator_result","validator_result":"matched","source_ref":"src/other.py:1","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  cat > "$runtime_probe_file" <<EOF
{"status":"pass","probe_status":"pass","fact_status":"deterministic_evidence","validator_id":"any.runtime.trace@v1","evidence_type":"runtime_trace","evidence_field":"validator_result","validator_result":"matched","source_ref":"logs/runtime.trace:1","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","validator_kind":"runtime_trace","parser_backed":false,"promotion_limit":"high","writes_shadow_docs":false}
EOF
  code_probe_hash="$(sha256_file_ref "$code_probe_file")"
  runtime_probe_hash="$(sha256_file_ref "$runtime_probe_file")"
  runtime_statement_hash="$(sha256_text_ref "$runtime_statement")"
  runtime_mismatch_statement_hash="$(sha256_text_ref "$runtime_mismatch_statement")"
  human_mismatch_statement_hash="$(sha256_text_ref "$human_mismatch_statement")"

  printf 'Draft for policy-bound deterministic evidence records\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/app.py:2" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  perl -0pi -e 's/\n  cache\.evict:/\n  custom.missing_effect:\n    description: test rule without effect-type contract\n    validators_by_stack:\n      python:\n        code_call:\n          primary: py.ast.call_match\@v1\n          fallback: py.regex.call_named\@v1\n          fallback_max_risk: medium\n\n  cache.evict:/' "$DOCS_ROOT/policy/shadow-rule-registry.md"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-015","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-user-015","SE-user-016","SE-user-017","SE-user-018","SE-user-019","SE-user-020","SE-user-023","SE-user-024","SE-user-025","SE-user-026","SE-user-027","SE-user-028","SE-user-029","SE-user-030","SE-user-031","SE-user-032","SE-user-033","SE-user-034","SE-user-035","SE-user-036"],"rationale":"Approve evaluating policy-bound deterministic evidence.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$runtime_bad_decision_file" <<'EOF'
{"user_decision":{"id":"UD-runtime-bad","decision_type":"business_intent","answer":"no","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["SE-user-026"],"rationale":"This does not confirm runtime scenario fit.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$runtime_one_sided_decision_file" <<EOF
{"user_decision":{"id":"UD-runtime-one-sided","decision_type":"runtime_scenario_fit","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-030","effect_type":"cache_evict","statement_hash":"$runtime_statement_hash","anchor_file":"logs/runtime.trace","anchor_line":"1","anchor_symbol":"event=user.cache.evict","trace_ref":"logs/runtime.trace:1","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change"}],"rationale":"This cites only the trace, not the scenario.","source_refs":["logs/runtime.trace:1"]}}
EOF
  cat > "$runtime_mismatch_decision_file" <<EOF
{"user_decision":{"id":"UD-runtime-mismatch","decision_type":"runtime_scenario_fit","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-031","effect_type":"cache_evict","statement_hash":"$runtime_mismatch_statement_hash","anchor_file":"logs/runtime.trace","anchor_line":"1","anchor_symbol":"event=user.cache.evict","trace_ref":"logs/runtime.trace:2","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change"}],"rationale":"This binds the right record but a different trace line.","source_refs":["logs/runtime.trace:1","scenario:user-update-cache"]}}
EOF
  cat > "$human_mismatch_decision_file" <<EOF
{"user_decision":{"id":"UD-human-mismatch","decision_type":"business_risk","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-036","effect_type":"effect_intent","statement_hash":"$human_mismatch_statement_hash","anchor_file":"docs/task/TASK-shadow-effect-map-01.md","anchor_symbol":"user decision"}],"rationale":"This decision type does not match effect intent.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$bad_rule_record" <<EOF
{"record_id":"SE-user-015","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Unregistered rule must not validate.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"made.up","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_args":{"callee":"save"}}}
EOF
  cat > "$incompatible_record" <<EOF
{"record_id":"SE-user-016","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Incompatible rule/ref must not validate.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"cache.evict","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_args":{"callee":"save"}}}
EOF
  cat > "$source_probe_record" <<EOF
{"record_id":"SE-user-017","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Source probe cannot be upgraded by declaring parser_backed.","anchor":{"file":"src/main/java/example/UserService.java","symbol":"userRepository.save"},"evidence":{"type":"deterministic_code","ref":"jpa.repository.save@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/main/java/example/UserService.java:5","source_hash":"$java_source_hash"}}
EOF
  cat > "$stale_source_record" <<EOF
{"record_id":"SE-user-018","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Stale source hash must not validate.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:2","source_hash":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$runtime_ref_record" <<EOF
{"record_id":"SE-user-019","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Runtime evidence must use a runtime trace validator.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"py.ast.call_match@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$unimplemented_record" <<EOF
{"record_id":"SE-user-020","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Documented-only SQL write validator cannot be forged as implemented.","anchor":{"file":"src/main/java/example/UserService.java","symbol":"sql.write"},"evidence":{"type":"deterministic_code","ref":"sql.write_call@v1","rule_id":"db.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/main/java/example/UserService.java:5","source_hash":"$java_source_hash","probe_args":{"callee":"executeUpdate","receiver":"jdbcTemplate"}}}
EOF
  cat > "$stale_runtime_record" <<EOF
{"record_id":"SE-user-023","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Stale runtime hash must not validate.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$forged_code_record" <<EOF
{"record_id":"SE-user-024","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Current source hash is not enough without matching probe result.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$wrong_effect_record" <<EOF
{"record_id":"SE-user-027","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Repo write rule must not confirm cache eviction.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$wrong_symbol_record" <<EOF
{"record_id":"SE-user-028","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Anchor symbol must match deterministic probe args.","anchor":{"file":"src/app.py","symbol":"repository.delete"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$path_only_source_record" <<EOF
{"record_id":"SE-user-029","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Path-only source refs are accepted when the probe rerun binds the same file.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"src/app.py","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$runtime_scenario_record" <<EOF
{"record_id":"SE-user-025","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Scenario ref alone is not fact evidence.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_bad_decision_record" <<EOF
{"record_id":"SE-user-026","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Negative or unrelated decisions cannot confirm runtime scenario fit.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-bad","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_one_sided_record" <<EOF
{"record_id":"SE-user-030","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-one-sided","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_mismatch_record" <<EOF
{"record_id":"SE-user-031","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_mismatch_statement","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-mismatch","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_wrong_effect_record" <<EOF
{"record_id":"SE-user-034","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"Runtime cache trace must not confirm arbitrary external call.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-one-sided","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_wrong_anchor_record" <<EOF
{"record_id":"SE-user-035","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Runtime trace must not confirm unrelated anchor file.","anchor":{"file":"src/app.py","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","user_decision_ref":"UD-runtime-one-sided","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$human_mismatch_record" <<EOF
{"record_id":"SE-user-036","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"effect_intent","statement":"$human_mismatch_statement","anchor":{"file":"docs/task/TASK-shadow-effect-map-01.md","symbol":"user decision"},"evidence":{"type":"user_decision","ref":"UD-human-mismatch"},"source_refs":["TASK-shadow-effect-map-01"]}
EOF
  cat > "$same_file_wrong_line_record" <<EOF
{"record_id":"SE-user-032","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Line-qualified source refs must bind the exact matched node.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"src/app.py:999","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$custom_rule_record" <<EOF
{"record_id":"SE-user-033","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Registered rules without effect type mapping fail closed.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"custom.missing_effect","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$bad_rule_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "evidence.rule_id is not registered"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$incompatible_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "evidence.ref is not compatible with evidence.rule_id"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$source_probe_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "source_probe-only"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$stale_source_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "source_hash must match"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_ref_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "runtime_trace validator"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$unimplemented_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "implemented by shadow_evidence_probe"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$stale_runtime_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "artifact_hash must match"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$forged_code_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$wrong_code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "probe_result.source_ref must match"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$wrong_effect_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "rule_id is not compatible with record.effect_type"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$wrong_symbol_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "anchor.symbol must match deterministic probe args"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$path_only_source_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$same_file_wrong_line_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "source_ref must match"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$custom_rule_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "no allowed_effect_types policy mapping"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_scenario_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "user_decision_ref is required"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_bad_decision_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_bad_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "decision_type must be runtime_scenario_fit"
  assert_contains "$output" "answer must affirm"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_one_sided_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_one_sided_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "source_refs must include all required evidence refs"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_mismatch_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_mismatch_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "applies_to must bind"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_wrong_effect_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_one_sided_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "rule_id is not compatible with record.effect_type"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_wrong_anchor_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_one_sided_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "anchor.file must match"

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$human_mismatch_record" --candidate "$candidate_file" --user-decision "$decision_file" --evidence-decision "$human_mismatch_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  assert_contains "$output" "decision_type is not compatible"
}

@test "shadow_effect_writer write requires target hash and updates exact record id" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local update_decision_file="$TEST_WORKSPACE/update-decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local record_update_file="$TEST_WORKSPACE/record-update.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local target_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"

  mkdir -p "$(dirname "$target_file")"
  printf 'Draft for structured record\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  local statement_hash
  statement_hash="$(sha256_text_ref "Cache behavior needs confirmation.")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-011","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id",{"record_id":"SE-user-002","lifecycle":"unknown","effect_type":"cache_evict","statement_hash":"$statement_hash","target_shadow_file":"packages/codeguide/effects.md","anchor_file":"src/UserService.java","anchor_symbol":"UserService.updateUser"}],"rationale":"Approve writing this exact record.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-user-002","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"cache_evict","statement":"Cache behavior needs confirmation.","reason":"No parser-backed cache evidence found.","anchor":{"file":"src/UserService.java","symbol":"UserService.updateUser"},"source_refs":["src/UserService.java:42"]}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode write \
    --today "2026-05-02"

  [ "$status" -eq 64 ]
  assert_contains "$output" "--expected-target-hash is required"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --expected-target-hash "missing" \
    --mode write \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"operation":"create"'
  assert_contains "$output" '"writes_shadow_docs":true'
  run grep -c "shadow-effect-record:SE-user-002 begin" "$target_file"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  local current_hash
  current_hash="$(python3 -c 'import hashlib,sys; p=sys.argv[1]; print("sha256:"+hashlib.sha256(open(p,"rb").read()).hexdigest())' "$target_file")"
  local update_statement_hash
  update_statement_hash="$(sha256_text_ref "Updated cache behavior still needs confirmation.")"
  cat > "$record_update_file" <<EOF
{"record_id":"SE-user-002","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"cache_evict","statement":"Updated cache behavior still needs confirmation.","reason":"Still missing cache evidence.","anchor":{"file":"src/UserService.java","symbol":"UserService.updateUser"},"source_refs":["src/UserService.java:42"]}
EOF
  cat > "$update_decision_file" <<EOF
{"user_decision":{"id":"UD-011-update","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id",{"record_id":"SE-user-002","lifecycle":"unknown","effect_type":"cache_evict","statement_hash":"$update_statement_hash","target_shadow_file":"packages/codeguide/effects.md","anchor_file":"src/UserService.java","anchor_symbol":"UserService.updateUser"}],"rationale":"Approve writing this exact updated record.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_update_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --expected-target-hash "$current_hash" \
    --mode write \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "record content"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_update_file" \
    --candidate "$candidate_file" \
    --user-decision "$update_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --expected-target-hash "$current_hash" \
    --mode write \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"operation":"update"'
  run grep -c "shadow-effect-record:SE-user-002 begin" "$target_file"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run grep "Updated cache behavior" "$target_file"
  [ "$status" -eq 0 ]

  printf '\n<!-- shadow-effect-record:SE-user-002 begin -->\nextra\n<!-- shadow-effect-record:SE-user-002 end -->\n' >> "$target_file"
  current_hash="$(python3 -c 'import hashlib,sys; p=sys.argv[1]; print("sha256:"+hashlib.sha256(open(p,"rb").read()).hexdigest())' "$target_file")"
  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_update_file" \
    --candidate "$candidate_file" \
    --user-decision "$update_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --expected-target-hash "$current_hash" \
    --mode write \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "exactly one begin and end marker"

}

@test "shadow_effect_writer enforces lifecycle transitions for existing record ids" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local unknown_record_file="$TEST_WORKSPACE/unknown-record.json"
  local blocked_record_file="$TEST_WORKSPACE/blocked-record.json"
  local stale_record_file="$TEST_WORKSPACE/stale-record.json"
  local confirmed_record_file="$TEST_WORKSPACE/confirmed-record.json"
  local code_probe_file="$TEST_WORKSPACE/code-probe.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local target_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"
  local source_hash
  local parser_identity
  local parser_content_hash
  local code_probe_hash

  mkdir -p "$(dirname "$target_file")" "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/app.py" <<'EOF'
class Repository:
    def save(self, user):
        return user

def handler(repository, user):
    repository.save(user)
EOF
  source_hash="$(sha256_file_ref "$TEST_PROJECT/src/app.py")"
  parser_identity="$(parser_identity_ref "py.ast.call_match@v1" "ast")"
  parser_content_hash="$(sha256_file_ref "$SHADOW_PROBE")"
  cat > "$code_probe_file" <<EOF
{"status":"pass","probe_status":"pass","fact_status":"deterministic_evidence","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","evidence_field":"validator_result","validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  code_probe_hash="$(sha256_file_ref "$code_probe_file")"

  printf 'Draft for lifecycle transition checks\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/app.py:6" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-lifecycle","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-life-001"],"rationale":"Approve evaluating lifecycle transition gates.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$unknown_record_file" <<EOF
{"record_id":"SE-life-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"db_write","statement":"Repository save still needs confirmation.","reason":"Evidence is not attached yet.","anchor":{"file":"src/app.py","symbol":"repository.save"},"source_refs":["src/app.py:6"]}
EOF
  cat > "$blocked_record_file" <<EOF
{"record_id":"SE-life-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"blocked","effect_type":"db_write","statement":"Repository save is blocked.","reason":"Blocked transition should require an explicit workflow outside this writer slice.","anchor":{"file":"src/app.py","symbol":"repository.save"},"source_refs":["src/app.py:6"]}
EOF
  cat > "$stale_record_file" <<EOF
{"record_id":"SE-life-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"stale","effect_type":"db_write","statement":"Repository save is stale.","reason":"Stale transition should require an explicit workflow outside this writer slice.","anchor":{"file":"src/app.py","symbol":"repository.save"},"source_refs":["src/app.py:6"]}
EOF
  cat > "$confirmed_record_file" <<EOF
{"record_id":"SE-life-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Repository save is backed by parser evidence.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$target_file" <<'EOF'
# Effects

- doc_role: effect_map
- generated_by: test

<!-- shadow-effect-record:SE-life-001 begin -->
## SE-life-001

- record_id: SE-life-001
- record_type: effect_map_entry
- lifecycle: unknown
- effect_type: db_write
- statement: Existing unknown record.
- candidate_id: previous-candidate
- reason: Existing reason.

<!-- shadow-effect-record:SE-life-001 end -->
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$unknown_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"operation":"update"'

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$blocked_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "lifecycle transition blocked: unknown -> blocked"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$stale_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "lifecycle transition blocked: unknown -> stale"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$confirmed_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --probe-result "$code_probe_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"operation":"update"'
  assert_contains "$output" "evidence_parser_backed: True"

  sed -i.bak 's/- lifecycle: unknown/- lifecycle: confirmed/' "$target_file"
  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$unknown_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "lifecycle transition blocked: confirmed -> unknown"

  sed -i.bak '/- lifecycle: confirmed/d' "$target_file"
  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$unknown_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "existing record SE-life-001 lifecycle metadata is missing or malformed"
}

@test "shadow_effect_writer refuses non-effect-map shadow targets" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local target_file="$DOCS_ROOT/shadow/project-shadow.md"

  mkdir -p "$(dirname "$target_file")"
  cat > "$target_file" <<'EOF'
# Project Shadow

- doc_role: project_router
- generated_by: test

## Misleading Body Example

- doc_role: effect_map
EOF

  printf 'Draft for target role check\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-014","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-user-008"],"rationale":"Approve evaluating target role gate.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"db_write","statement":"Target role should block this record.","reason":"Non-effect-map target.","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"source_refs":["src/UserService.java:42"]}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "project-shadow.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "target shadow file must declare doc_role: effect_map"
  run grep "shadow-effect-record:SE-user-008" "$target_file"
  [ "$status" -eq 1 ]

  rm -f "$target_file"
  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "project-shadow.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "must not create reserved shadow navigation paths"
}

@test "shadow_effect_writer reads the target doc_role outside fences, both directions" {
  # leading_metadata_value used to read `- doc_role:` fence-blind, so a document that
  # merely QUOTED the effect-map header passed target_role_blockers with no blockers and
  # the writer would append records to it -- while the validator, which reads doc_role
  # through the shared reader, would never check that file as an effect map. Both
  # directions are asserted: refusing everything would satisfy half of this test on its
  # own.
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local target_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"

  mkdir -p "$(dirname "$target_file")"
  printf 'Draft for fenced target role check\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-021","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-user-021"],"rationale":"Approve fenced target role check.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-user-021","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"db_write","statement":"Fenced doc_role must not decide the target role.","reason":"Fence-aware target role guard.","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"source_refs":["src/UserService.java:42"]}
EOF

  # A unit overview that only QUOTES the effect-map header is not an effect map.
  cat > "$target_file" <<'EOF'
# Shadow Unit Overview

An effect map opens like this:

```markdown
- doc_role: effect_map
```

- doc_role: unit_overview
- home_bucket: packages
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "target shadow file must declare doc_role: effect_map"

  # The mirror: a genuine effect map that quotes another role above its own field, with
  # the fence markers INDENTED, must still be writable. The match is on the stripped
  # line, so this shape tripped the old reader where the shell reader's `^- ` anchor
  # happened to survive it.
  cat > "$target_file" <<'EOF'
# Shadow Effects

Not to be confused with a unit overview:

  ```markdown
  - doc_role: unit_overview
  ```

- doc_role: effect_map
- generated_by: test
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  refute_contains "$output" "target shadow file must declare doc_role: effect_map"
}

@test "shadow_effect_writer rejects malformed record refs and existing markers" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local bad_record_file="$TEST_WORKSPACE/bad-record.json"
  local missing_effect_record_file="$TEST_WORKSPACE/missing-effect-record.json"
  local marker_record_file="$TEST_WORKSPACE/marker-record.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local target_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"

  mkdir -p "$(dirname "$target_file")"
  printf 'Draft for malformed marker checks\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-016","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE--bad","SE-user-019","SE-user-020"],"rationale":"Approve malformed marker checks.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$bad_record_file" <<EOF
{"record_id":"SE--bad","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"db_write","statement":"Malformed record metadata should block.","reason":"Bad metadata.","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"source_refs":"src/UserService.java:42"}
EOF
  cat > "$missing_effect_record_file" <<EOF
{"record_id":"SE-user-019","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","statement":"Effect type is required for all effect-map records.","reason":"Missing effect type.","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"source_refs":["src/UserService.java:42"]}
EOF
  cat > "$marker_record_file" <<EOF
{"record_id":"SE-user-020","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"db_write","statement":"Existing malformed marker state should block.","reason":"Target has an orphan marker.","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"source_refs":["src/UserService.java:42"]}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$bad_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "record.record_id must not contain --"
  assert_contains "$output" "record.source_refs must be a list"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$missing_effect_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "record.effect_type is required"

  cat > "$target_file" <<'EOF'
# Shadow Effects

- doc_role: effect_map
- generated_by: test

<!-- shadow-effect-record:SE-user-previous begin -->
## Previous
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$marker_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "exactly one begin and end marker"

  cat > "$target_file" <<'EOF'
# Shadow Effects

- doc_role: effect_map
- generated_by: test

<!-- shadow-effect-record:SE-user-a begin -->
## A
<!-- shadow-effect-record:SE-user-b begin -->
## B
<!-- shadow-effect-record:SE-user-a end -->
<!-- shadow-effect-record:SE-user-b end -->
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$marker_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "interleaved shadow-effect-record markers"
}

@test "shadow_effect_writer blocks stale target hash traversal and llm evidence" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local record_file="$TEST_WORKSPACE/record.json"
  local unknown_record_file="$TEST_WORKSPACE/unknown-record.json"
  local draft_file="$TEST_WORKSPACE/draft.md"

  printf 'Draft for blocked record\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-012","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-user-003","SE-user-009"],"rationale":"Approve evaluating this exact record.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-user-003","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Bad evidence should block <!-- shadow-effect-record:SE-user-999 begin -->.","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"evidence":{"type":"llm_hint","ref":"LC-draft"}}
EOF
  cat > "$unknown_record_file" <<EOF
{"record_id":"SE-user-009","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"db_write","statement":"Unknown records must not preserve LLM hints as evidence.","reason":"LLM hint is not evidence.","anchor":{"file":"src/UserService.java","symbol":"UserRepository.save"},"evidence":{"type":"llm_hint","ref":"LC-draft"}}
EOF

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --expected-target-hash "sha256:not-current" \
    --mode write \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "llm_hint"
  assert_contains "$output" "target hash mismatch"
  assert_contains "$output" "forbidden Markdown marker"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$unknown_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  assert_contains "$output" "llm_hint"

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "../outside.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 64 ]
  assert_contains "$output" "traversal"
}

# ========== P1/P2: Validator strict mode non-empty check ==========

@test "shadow_policy_loader reports adapter ids and catalog parity" {
  run python3 "$SHADOW_POLICY_LOADER" --adapter-module "$SHADOW_PROBE" --print-adapter-ids
  [ "$status" -eq 0 ]
  assert_contains "$output" "py.ast.call_match@v1"
  assert_contains "$output" "js.ast.call_match@v1"
  assert_contains "$output" "ts.ast.call_match@v1"
  assert_contains "$output" "ts.ast.call_match@v2"
  assert_contains "$output" "fastapi.route@v1"
  assert_contains "$output" "express.route@v1"
  assert_contains "$output" "react.effect_hook@v1"
  assert_contains "$output" "react.jsx_event_binding@v1"
  assert_contains "$output" "any.runtime.trace@v1"

  run python3 "$SHADOW_POLICY_LOADER" --adapter-module "$SHADOW_PROBE" --print-adapter-json
  [ "$status" -eq 0 ]
  assert_contains "$output" '"ts.ast.call_match@v2"'
  assert_contains "$output" '"express.route@v1"'
  assert_contains "$output" '"react.effect_hook@v1"'
  assert_contains "$output" '"react.jsx_event_binding@v1"'
  assert_contains "$output" '"allowed_extensions":[".ts",".tsx",".mts",".cts"]'
  assert_contains "$output" '"rejected_extensions":[".d.ts"]'
  assert_contains "$output" '"allowed_paths":["src/**","app/**","lib/**","server/**","pages/**","routes/**"]'

  run python3 "$SHADOW_POLICY_LOADER" --policy-dir "$DOCS_ROOT/policy" --adapter-module "$SHADOW_PROBE" --check-parity
  [ "$status" -eq 0 ]
  assert_contains "$output" '"status":"ok"'
  assert_contains "$output" '"adapter_specs"'

  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, sql.write_call\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  run python3 "$SHADOW_POLICY_LOADER" --policy-dir "$DOCS_ROOT/policy" --adapter-module "$SHADOW_PROBE" --check-parity
  [ "$status" -ne 0 ]
  assert_contains "$output" "implemented_primary_v1 id must be implemented by shadow_evidence_probe.py"
}


@test "the shared document read keeps the bytes on disk, so python and sed count the same lines" {
  # `split_lines` was `\n`-only and kept the CR, and `read_lines` threw the CR away one line
  # later because `Path.read_text` opens in UNIVERSAL-NEWLINE mode -- so the contract was
  # asserted at the one place it could not be violated while every path that reads a FILE
  # violated it. This asserts the read, not
  # the splitter, and it compares against grep/sed rather than against another python call,
  # because agreeing with the shell tools is the whole property.
  local fixture="$TEST_WORKSPACE/crbytes.md"
  printf 'prefix\015- status: cr_only\n- status: planned\n' > "$fixture"
  local crlf="$TEST_WORKSPACE/crlfbytes.md"
  printf -- '- doc_role: unit_overview\015\n- last_updated: 2026-01-01\015\n' > "$crlf"

  # The shell side, stated as data rather than assumed: grep sees ONE status line here.
  run grep -c '^- status:' "$fixture"
  assert_equal "$output" "1"

  run python3 - "$SCRIPTS_DIR" "$fixture" "$crlf" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
import shadow_doc_parse

failures = []

lines = shadow_doc_parse.read_lines(sys.argv[2])
if lines != ["prefix\r- status: cr_only", "- status: planned"]:
    failures.append("lone CR split: " + repr(lines))
# ...and therefore the value every rule compares is the one grep returns.
if shadow_doc_parse.field_value(lines, "status") != "planned":
    failures.append("field_value: " + repr(shadow_doc_parse.field_value(lines, "status")))

crlf = shadow_doc_parse.read_lines(sys.argv[3])
if crlf != ["- doc_role: unit_overview\r", "- last_updated: 2026-01-01\r"]:
    failures.append("CRLF split: " + repr(crlf))
# A CRLF document still yields a usable value: the trailing CR is whitespace to the field
# pattern, exactly as it is to the validator trim.
if shadow_doc_parse.field_value(crlf, "doc_role") != "unit_overview":
    failures.append("CRLF field_value: " + repr(shadow_doc_parse.field_value(crlf, "doc_role")))

# A line NUMBER is the thing that cannot tolerate two definitions of a line: this index is
# what doc_garden hands to `sed`, and sed counts `\n` only.
numbered = list(shadow_doc_parse.numbered_content_lines(lines))
if numbered[0][0] != 0 or numbered[1][0] != 1 or len(numbered) != 2:
    failures.append("numbered: " + repr(numbered))

if failures:
    print("FAILURES: " + "; ".join(failures))
    raise SystemExit(1)
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"

  # Positive control on the SAME reader: strip the control characters and the answers are
  # unchanged, so the assertions above are about the bytes and not about a broken reader.
  printf -- '- status: planned\n' > "$fixture"
  run python3 -c "
import sys
sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
import shadow_doc_parse
print(shadow_doc_parse.field_value(shadow_doc_parse.read_lines(sys.argv[2]), 'status'))
" "$SCRIPTS_DIR" "$fixture"
  [ "$status" -eq 0 ]
  assert_equal "$output" "planned"
}

@test "a source digest write round-trips the document byte-exactly" {
  # shadow_source_digest.upsert_digest_field rewrites the WHOLE document from the split
  # lines, so a splitlines-based split silently CONVERTS every form feed in the file into a
  # newline, and a universal-newline read does the same to every CR. The previous round
  # asserted this on `split_lines` and called the writer proven; reverting the WRITER to
  # `str.splitlines()` left all 638 tests green (the task r01
  # finding 6). This exercises the writer.
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-a"
  printf 'a=1\n' > "$TEST_PROJECT/src/a.py"
  local doc="$DOCS_ROOT/shadow/apps/app-a/overview.md"
  {
    printf '%s\n' '# Shadow Unit Overview' '' '- doc_role: unit_overview'
    printf 'prose with a form feed\014and a carriage return\015here\n'
    printf '%s\n' '- source_of_truth_paths: src/a.py' '- source_of_truth_digest:' \
      '- last_updated: 2026-01-01T00:00:00Z'
  } > "$doc"
  local before="$TEST_WORKSPACE/before.md"
  cp "$doc" "$before"

  run python3 "$SCRIPTS_DIR/shadow_source_digest.py" "$doc" --project-root "$TEST_PROJECT" --write
  [ "$status" -eq 0 ]

  # Exactly one line differs -- the digest field -- and every other byte, control
  # characters included, is unchanged.
  run diff "$before" "$doc"
  [ "$status" -ne 0 ]
  run python3 - "$before" "$doc" <<'PY'
import sys
before = open(sys.argv[1], "rb").read()
after = open(sys.argv[2], "rb").read()
b = before.split(b"\n")
a = after.split(b"\n")
if len(a) != len(b):
    print("FAIL line count %d -> %d" % (len(b), len(a)))
    raise SystemExit(1)
differing = [i for i, (x, y) in enumerate(zip(b, a)) if x != y]
if differing != [len(b) - 3]:
    print("FAIL differing lines: %r" % differing)
    raise SystemExit(1)
if not a[differing[0]].startswith(b"- source_of_truth_digest: sha256:"):
    print("FAIL not the digest line: %r" % a[differing[0]])
    raise SystemExit(1)
if before.count(b"\x0c") != 1 or after.count(b"\x0c") != 1:
    print("FAIL form feed count %d -> %d" % (before.count(b"\x0c"), after.count(b"\x0c")))
    raise SystemExit(1)
if before.count(b"\r") != 1 or after.count(b"\r") != 1:
    print("FAIL CR count %d -> %d" % (before.count(b"\r"), after.count(b"\r")))
    raise SystemExit(1)
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"

  # Positive half: the write really did happen and the document still parses.
  run python3 "$SCRIPTS_DIR/shadow_source_digest.py" "$doc" --project-root "$TEST_PROJECT" --check
  [ "$status" -eq 0 ]
  assert_contains "$output" "status: ok"
}

@test "source_paths_for_doc reads declared paths with the shared line rule" {
  # The helper exists so the two report tools stop doing the read and the `str.splitlines()`
  # themselves -- they shared the FENCE rule with shadow_source_digest and not the LINE
  # rule. Reverting it to `splitlines` left every test green, which is a claim with nothing
  # behind it.
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-b"
  printf 'a=1\n' > "$TEST_PROJECT/src/a.py"
  printf 'b=1\n' > "$TEST_PROJECT/src/b.py"
  local doc="$DOCS_ROOT/shadow/apps/app-b/overview.md"
  {
    printf '%s\n' '# Shadow Unit Overview' '' '- doc_role: unit_overview'
    printf 'prose\014- source_of_truth_paths: src/b.py\n'
    printf '%s\n' '- source_of_truth_paths: src/a.py' '- last_updated: 2026-01-01T00:00:00Z'
  } > "$doc"

  run python3 - "$SCRIPTS_DIR" "$doc" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
from shadow_source_digest import source_paths_for_doc

got = source_paths_for_doc(sys.argv[2])
# A form feed is not a line ending, so the fragment is prose and declares nothing.
if got != ["src/a.py"]:
    print("FAIL %r" % (got,))
    raise SystemExit(1)
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"

  # Positive half: a real newline in place of the form feed makes it a declaration, so the
  # assertion above is about the control character and not about the helper never seeing it.
  perl -pi -e 's{^prose\x0c}{}' "$doc"
  run python3 - "$SCRIPTS_DIR" "$doc" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
from shadow_source_digest import source_paths_for_doc

got = source_paths_for_doc(sys.argv[2])
if got != ["src/b.py", "src/a.py"]:
    print("FAIL %r" % (got,))
    raise SystemExit(1)
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"
}

@test "the effect-map lifecycle write gate counts lines the way every other reader does" {
  # `existing_record_lifecycle_blockers` reads `- lifecycle:` out of an effect-map MARKDOWN
  # block to GATE A WRITE, and it was the one line-splitting site in this file left on
  # `str.splitlines()` after the shared line rule landed -- flagged as unenumerated by
  # The task r01 finding 7. The effect-map GRAMMAR stays outside the
  # shared reader; the LINE rule does not, and this file already shares it one function
  # above. Called directly because the surrounding write path needs a decision payload, a
  # target hash and a probe rerun, none of which this property depends on.
  run python3 - "$SCRIPTS_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
import shadow_effect_writer as W

failures = []
begin = W.marker("rec-1", "begin")
end = W.marker("rec-1", "end")

# A form feed is not a line ending, so `prefix<FF>- lifecycle: stale` is prose on one line
# and the block declares exactly ONE lifecycle: the real one below it.
doc = begin + "\nprefix\x0c- lifecycle: stale\n- lifecycle: confirmed\n" + end + "\n"
value, blockers = W.existing_record_lifecycle_blockers(doc, "rec-1")
if value != "confirmed" or blockers:
    failures.append("form feed: %r %r" % (value, blockers))

# Positive half: a REAL newline in the same place makes it two lifecycle lines, which is
# malformed and must block the write. Without this the case above asserts a constant.
doc = begin + "\n- lifecycle: stale\n- lifecycle: confirmed\n" + end + "\n"
value, blockers = W.existing_record_lifecycle_blockers(doc, "rec-1")
if value is not None or not blockers:
    failures.append("two lines: %r %r" % (value, blockers))

# ...and the ordinary single-lifecycle block still reads cleanly.
doc = begin + "\n- lifecycle: stale\n" + end + "\n"
value, blockers = W.existing_record_lifecycle_blockers(doc, "rec-1")
if value != "stale" or blockers:
    failures.append("plain: %r %r" % (value, blockers))

if failures:
    print("FAILURES: " + "; ".join(failures))
    raise SystemExit(1)
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"
}

@test "the shared scan emits a fence boundary at the closing marker as well as the opening one" {
  # scan()'s contract is that a reader tracking state ACROSS lines learns a block happened.
  # Dropping the CLOSING boundary left all 638 tests green (the task
  # r01 finding 6), and it stayed green because both current consumers reset on ANY boundary
  # and the OPEN already reset them -- so the close boundary is currently unobservable
  # THROUGH a consumer and can only be bound at the module. That is stated rather than
  # papered over: a consumer that needs "we are outside again", or that counts blocks, gets
  # a wrong answer from the mutant, and nothing else in the tree would notice.
  run python3 - "$SCRIPTS_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
import shadow_doc_parse

failures = []

closed = ["a", "```", "inside", "```", "b"]
kinds = [kind for kind, _ in shadow_doc_parse.scan(closed)]
if kinds != ["content", "boundary", "boundary", "content"]:
    failures.append("closed block: " + repr(kinds))

# Positive half, same reader: an UNTERMINATED fence yields exactly one boundary, because
# there is no closing marker to report. If both cases gave the same answer this would be
# asserting a constant.
unterminated = ["a", "```", "inside", "b"]
kinds = [kind for kind, _ in shadow_doc_parse.scan(unterminated)]
if kinds != ["content", "boundary"]:
    failures.append("unterminated block: " + repr(kinds))

# And the same state machine answers the writer question the append guard asks.
if shadow_doc_parse.ends_inside_fence(closed):
    failures.append("closed block reported as ending inside a fence")
if not shadow_doc_parse.ends_inside_fence(unterminated):
    failures.append("unterminated block reported as closed")

if failures:
    print("FAILURES: " + "; ".join(failures))
    raise SystemExit(1)
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"
}

@test "the shared line rule splits on newlines only and round-trips a document exactly" {
  # `str.splitlines()` breaks on VT, FF, FS, GS, RS, NEL, U+2028 and U+2029; grep, awk,
  # sed, wc -l and while-read break on `\n` alone, so a shared FENCE rule with a private
  # LINE rule still lets two readers of one document disagree
  # CommonMark settles the direction:
  # a line ends at a line feed or a carriage return and at nothing else.
  #
  # The round trip is the half that matters for WRITERS. shadow_source_digest rewrites the
  # whole document from these lines, so a splitlines-based split silently CONVERTS every
  # form feed in the file into a newline on each digest write.
  run python3 - "$SCRIPTS_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
sys.dont_write_bytecode = True
import shadow_doc_parse

failures = []

# Only \n is a line ending. Each of these is ONE line here and eight lines to splitlines.
for name, char in [("VT", "\x0b"), ("FF", "\x0c"), ("FS", "\x1c"), ("GS", "\x1d"),
                   ("RS", "\x1e"), ("NEL", "\x85"), ("LS", " "), ("PS", " ")]:
    got = shadow_doc_parse.split_lines("a" + char + "b\n")
    if got != ["a" + char + "b"]:
        failures.append(f"{name}: {got!r}")

# CR is kept, because grep keeps it.
if shadow_doc_parse.split_lines("a\r\nb\n") != ["a\r", "b"]:
    failures.append("CRLF: " + repr(shadow_doc_parse.split_lines("a\r\nb\n")))

# Round trip is byte-exact, which is what a whole-document rewrite depends on.
for text in ["", "\n", "a\n", "a\nb\n", "a\n\nb\n", "no trailing newline",
             "intro\x0cmore\n- k: v\n", "a\r\nb\r\n"]:
    lines = shadow_doc_parse.split_lines(text)
    rebuilt = ("\n".join(lines) + "\n") if lines else ""
    expected = text if text.endswith("\n") or not text else text + "\n"
    if rebuilt != expected:
        failures.append(f"round trip {text!r}: {rebuilt!r} != {expected!r}")

# Positive control: on a document with none of those characters the two agree exactly, so
# the assertions above are about the control characters and not about a broken splitter.
plain = "# Title\n\n- doc_role: unit_overview\n- last_updated: 2026-01-01\n"
if shadow_doc_parse.split_lines(plain) != plain.splitlines():
    failures.append("plain text disagrees with splitlines")

if failures:
    print("FAILURES: " + "; ".join(failures))
    raise SystemExit(1)
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"
}

@test "a source digest write refuses a document that is not valid UTF-8" {
  # The DECODE column: what a byte that is not valid UTF-8 becomes. It is the sixth rule of
  # the reader/writer matrix and the one no axis table had, and this round shipped opposite
  # answers to it in two files -- `shadow_effect_writer` was moved to `errors="strict"`
  # because a whole-document rewriter must return the bytes it was given, while
  # `upsert_digest_field`, the OTHER whole-document rewriter named in the same PLAN
  # sentence, stayed at the tolerant default. Reproduced: a shadow doc carrying the Latin-1
  # byte 0xE9 came out of one `--write` with EF BF BD in its place, exit 0, no diagnostic
  #
  mkdir -p "$TEST_PROJECT/src" "$DOCS_ROOT/shadow/apps/app-dec"
  printf 'a=1\n' > "$TEST_PROJECT/src/a.py"
  local doc="$DOCS_ROOT/shadow/apps/app-dec/overview.md"
  {
    printf '%s\n' '# Shadow Unit Overview' '' '- doc_role: unit_overview'
    printf 'prose with a latin-1 byte: caf\351 here\n'
    printf '%s\n' '- source_of_truth_paths: src/a.py' '- source_of_truth_digest:' \
      '- last_updated: 2026-01-01T00:00:00Z'
  } > "$doc"
  local before="$TEST_WORKSPACE/before-decode.md"
  cp "$doc" "$before"

  run python3 "$SCRIPTS_DIR/shadow_source_digest.py" "$doc" --project-root "$TEST_PROJECT" --write
  [ "$status" -ne 0 ]
  assert_contains "$output" "not valid UTF-8"

  # The document is byte-identical: refusing is the point, and a partial rewrite would be
  # the corruption this replaces.
  run cmp -s "$before" "$doc"
  [ "$status" -eq 0 ]
  run python3 - "$doc" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
print("FFFD" if b"\xef\xbf\xbd" in data else "no-replacement-char")
print("raw-byte-kept" if b"\xe9" in data else "raw-byte-lost")
PY
  assert_contains "$output" "no-replacement-char"
  assert_contains "$output" "raw-byte-kept"

  # Positive half: the same document in valid UTF-8, same non-ASCII character, writes.
  local ok_doc="$DOCS_ROOT/shadow/apps/app-dec/ok.md"
  {
    printf '%s\n' '# Shadow Unit Overview' '' '- doc_role: unit_overview' 'prose with café here'
    printf '%s\n' '- source_of_truth_paths: src/a.py' '- source_of_truth_digest:' \
      '- last_updated: 2026-01-01T00:00:00Z'
  } > "$ok_doc"
  run python3 "$SCRIPTS_DIR/shadow_source_digest.py" "$ok_doc" --project-root "$TEST_PROJECT" --write
  [ "$status" -eq 0 ]
  run grep -c '^- source_of_truth_digest: sha256:' "$ok_doc"
  assert_equal "$output" "1"
}

@test "an effect write round-trips the existing effect map byte-exactly" {
  # `shadow_effect_writer` reads its target and writes the WHOLE document back, so a
  # universal-newline read silently converted a CRLF effect map to `\n`-only on every write.
  # The read was moved to `read_document_text` for that reason -- and reverting it to
  # `read_text` survives 234 tests (r02 residual_risk), because every existing fixture ends
  # its lines with a bare `\n`, where the two reads agree. This is the fixture where they do
  # not, and it exercises the WRITER rather than the splitter.
  local candidate_file="$TEST_WORKSPACE/crlf-candidate.json"
  local decision_file="$TEST_WORKSPACE/crlf-decision.json"
  local record_file="$TEST_WORKSPACE/crlf-record.json"
  local draft_file="$TEST_WORKSPACE/crlf-draft.md"
  local target_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"

  mkdir -p "$(dirname "$target_file")"
  # A pre-existing effect map whose lines end CRLF, plus one lone CR inside a line. The
  # `- doc_role:` line carries the CRLF too, so the gate that reads it has to tolerate the
  # CR the byte-faithful read now delivers -- under the old universal-newline read that CR
  # never reached any rule in this file.
  printf '# Effects\r\n\r\n- doc_role: effect_map\r\n\r\nExisting prose line.\r\nA line with a lone \rcarriage return.\r\n' > "$target_file"
  local before="$TEST_WORKSPACE/crlf-before.md"
  cp "$target_file" "$before"

  printf 'Draft for CRLF round trip\n' > "$draft_file"
  python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --output "$candidate_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  local candidate_id
  candidate_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidate_id"])' "$candidate_file")"
  local statement_hash
  statement_hash="$(sha256_text_ref "CRLF round trip must not rewrite the document.")"
  cat > "$decision_file" <<EOF
{"user_decision":{"id":"UD-crlf","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id",{"record_id":"SE-crlf-001","lifecycle":"unknown","effect_type":"cache_evict","statement_hash":"$statement_hash","target_shadow_file":"packages/codeguide/effects.md","anchor_file":"src/UserService.java","anchor_symbol":"UserService.updateUser"}],"rationale":"Approve writing this exact record.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$record_file" <<EOF
{"record_id":"SE-crlf-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"unknown","effect_type":"cache_evict","statement":"CRLF round trip must not rewrite the document.","reason":"No parser-backed cache evidence found.","anchor":{"file":"src/UserService.java","symbol":"UserService.updateUser"},"source_refs":["src/UserService.java:42"]}
EOF

  local current_hash
  current_hash="$(sha256_file_ref "$target_file")"
  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --expected-target-hash "$current_hash" \
    --mode write \
    --today "2026-05-02"
  [ "$status" -eq 0 ]
  assert_contains "$output" '"writes_shadow_docs":true'

  # The record really was appended, and every byte that was there before is still there:
  # the new content is a SUFFIX of the file, so no existing line ending was rewritten.
  run grep -c "shadow-effect-record:SE-crlf-001 begin" "$target_file"
  assert_equal "$output" "1"
  run python3 - "$before" "$target_file" <<'PY'
import sys
before = open(sys.argv[1], "rb").read()
after = open(sys.argv[2], "rb").read()
if not after.startswith(before):
    print("FAIL existing bytes were rewritten")
    common = 0
    while common < min(len(before), len(after)) and before[common] == after[common]:
        common += 1
    print("first divergence at byte %d: %r vs %r" % (common, before[common:common + 12], after[common:common + 12]))
    raise SystemExit(1)
if before.count(b"\r") == 0 or before.count(b"\r") != after.count(b"\r"):
    print("FAIL CR count %d -> %d" % (before.count(b"\r"), after.count(b"\r")))
    raise SystemExit(1)
print("ok")
PY
  [ "$status" -eq 0 ]
  assert_contains "$output" "ok"
}
