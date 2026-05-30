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
  [[ "$output" == *"# Shadow Evidence Review Queue"* ]]
  [[ "$output" == *"- writes_shadow_docs: false"* ]]
  [[ "$output" == *"- auto_promotes_facts: false"* ]]
  [[ "$output" == *"- doc_role: review_queue"* ]]
  [[ "$output" == *"- question_count: 2"* ]]
  [[ "$output" == *"Does the syntactic source probe"* ]]
  [[ "$output" == *"Which supported validator or fallback should replace"* ]]
  [[ "$output" != *"RQ-003"* ]]
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
  [[ "$output" == *"- max_questions: 1"* ]]
  [[ "$output" == *"- question_count: 2"* ]]
  [[ "$output" == *"- uncapped_required_questions: 2"* ]]
  [[ "$output" == *"- deferred_question_count: 2"* ]]
  [[ "$output" != *"RQ-003"* ]]
  [[ "$output" == *"Error, unsupported, and trusted high/critical policy questions are emitted"* ]]
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
  [[ "$output" == *"- question_count: 1"* ]]
  [[ "$output" == *"- uncapped_required_questions: 1"* ]]
  [[ "$output" == *"- deferred_question_count: 2"* ]]
  [[ "$output" == *"trusted_review_risk: critical"* ]]
  [[ "$output" == *"priority: critical"* ]]
}

@test "shadow_review_queue defers under-specified questions instead of asking user" {
  local probe_file="$TEST_WORKSPACE/missing-context.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"jpa.repository.save@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/UserService.java:6","validator_kind":"source_probe","parser_backed":false,"promotion_limit":"medium","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file" --max-questions 5

  [ "$status" -eq 0 ]
  [[ "$output" == *"- question_count: 0"* ]]
  [[ "$output" == *"- deferred_missing_context_count: 1"* ]]
  [[ "$output" == *"question_state: deferred_missing_context"* ]]
  [[ "$output" == *"missing_question_context:"* ]]
  [[ "$output" == *"- no user questions generated"* ]]
}

@test "shadow_review_queue keeps runtime trace provenance visible" {
  local probe_file="$TEST_WORKSPACE/runtime.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"any.runtime.trace@v1","evidence_type":"runtime_trace","validator_result":"matched","source_ref":"logs/runtime.trace:2","trace_ref":"logs/runtime.trace:2","artifact_hash":"sha256:abc123","validator_kind":"runtime_trace","parser_backed":false,"promotion_limit":"high","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser","anchor_file":"logs/runtime.trace","anchor_symbol":"event=user.cache.evict","missing_evidence":"runtime scenario fit decision","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *"artifact_hash: sha256:abc123"* ]]
  [[ "$output" == *"Is runtime trace"* ]]
  [[ "$output" == *"observation window"* ]]
}

@test "shadow_review_queue renders deterministic metadata and decision context" {
  local probe_file="$TEST_WORKSPACE/context.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"fail","validator_id":"py.ast.call_match@v1","rule_id":"repo.write","evidence_type":"code_call","validator_result":"missing","source_ref":"src/app.py:4","validator_kind":"ast","parser_backed":true,"promotion_limit":"medium","entry_ref":"UserController.update","endpoint":"POST /users/{id}","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/UserService.java","anchor_symbol":"UserRepository.save","missing_evidence":"JpaRepository.save call","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file" --max-questions 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"rule_id: repo.write"* ]]
  [[ "$output" == *"validator_kind: ast"* ]]
  [[ "$output" == *"parser_backed: True"* ]]
  [[ "$output" == *"validator_result: missing"* ]]
  [[ "$output" == *"entry_ref: UserController.update"* ]]
  [[ "$output" == *"endpoint: POST /users/{id}"* ]]
  [[ "$output" == *"call_chain_candidate: UserController.update -> UserService.updateUser -> UserRepository.save"* ]]
  [[ "$output" == *"anchor_file: src/UserService.java"* ]]
  [[ "$output" == *"anchor_symbol: UserRepository.save"* ]]
  [[ "$output" == *"missing_evidence: JpaRepository.save call"* ]]
  [[ "$output" == *"decision_policy_ref: shadow-effect-map-workflow.md#stop-and-ask"* ]]
  [[ "$output" == *"default_status: unknown"* ]]
}

@test "shadow_review_queue can optionally ask about parser-backed pass records" {
  local probe_file="$TEST_WORKSPACE/parser.jsonl"
  cat > "$probe_file" <<'EOF'
{"status":"pass","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/app.py:4","validator_kind":"ast","parser_backed":true,"promotion_limit":"high","entry_ref":"UserController.update","call_chain_candidate":"UserController.update -> UserService.updateUser -> UserRepository.save","anchor_file":"src/app.py","anchor_symbol":"repository.save","missing_evidence":"human intent decision","recommended_default_status":"unknown","writes_shadow_docs":false}
EOF

  run python3 "$SHADOW_QUEUE" --input "$probe_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- no user questions generated"* ]]

  run python3 "$SHADOW_QUEUE" --input "$probe_file" --ask-confirmed
  [ "$status" -eq 0 ]
  [[ "$output" == *"Is parser-backed evidence"* ]]
}

@test "shadow_review_queue reports invalid JSON as machine-readable error" {
  local probe_file="$TEST_WORKSPACE/bad.jsonl"
  printf '{"status":"pass"\n' > "$probe_file"

  run python3 "$SHADOW_QUEUE" --input "$probe_file"

  [ "$status" -eq 64 ]
  [[ "$output" == *'"status":"error"'* ]]
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
  [[ "$output" == *'"status":"llm_candidate"'* ]]
  [[ "$output" == *'"evidence_type":"llm_hint"'* ]]
  [[ "$output" == *'"non_promotion_status":true'* ]]
  [[ "$output" == *'"shadow_action":"candidate_only"'* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]
  [[ "$output" == *'"auto_promotes_facts":false'* ]]
  [[ "$output" == *'"raw_draft_hash":"sha256:'* ]]
  [[ "$output" == *'"source_refs":["src/UserService.java:42"]'* ]]
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
  [[ "$output" == *"at least one --source-ref is required"* ]]

  run python3 "$SHADOW_LLM_CANDIDATE" \
    --input "$draft_file" \
    --task-id "shadow-effect-map-01" \
    --model-id "test-model" \
    --tool-id "codex" \
    --source-ref "src/UserService.java:42" \
    --timestamp "2026-05-02T00:00:00Z"

  [ "$status" -eq 64 ]
  [[ "$output" == *"forbidden production-action markers"* ]]
  [[ "$output" == *"shadow_write_true"* ]]
  [[ "$output" == *"direct_apply"* ]]
  [[ "$output" == *"validated_status"* ]]
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
  [[ "$output" == *"must not be under docs/shadow"* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]
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
  [[ "$output" == *'"status":"blocked"'* ]]
  [[ "$output" == *"answer must be yes or approve_apply"* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]

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
  [[ "$output" == *'"status":"allowed"'* ]]
  [[ "$output" == *'"shadow_apply_allowed":true'* ]]
  [[ "$output" == *'"apply_mode":"supervised_dry_run"'* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$candidate_file" \
    --user-decision "$good_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2000-01-01"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"today_override_warning"'* ]]
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
  [[ "$output" == *"candidate.model_id is required"* ]]
  [[ "$output" == *"candidate.tool_id is required"* ]]
  [[ "$output" == *"candidate.created_at is required"* ]]
  [[ "$output" == *"candidate.source_refs must be a non-empty list of strings"* ]]
  [[ "$output" == *"candidate.shadow_action must be candidate_only"* ]]
  [[ "$output" == *"candidate.raw_draft_hash must be a sha256 reference"* ]]
  [[ "$output" == *"user_decision is expired"* ]]

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
  [[ "$output" == *"candidate.candidate_id must match provenance digest"* ]]

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
  [[ "$output" == *"traversal"* ]]

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$forged_candidate_file" \
    --user-decision "$mismatch_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"user_decision.applies_to must reference candidate_id"* ]]
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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]
  run grep '"target_shadow_file": "packages/codeguide/effects.md"' "$apply_decision_file"
  [ "$status" -eq 0 ]

  run python3 "$SHADOW_APPLY_GATE" \
    --project-root "$TEST_PROJECT" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"allowed":true'* ]]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$apply_decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]

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
  [[ "$output" == *"evidence_ref: UD-wrap-fact"* ]]

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
  [[ "$output" == *"human-only record.effect_type"* ]]
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
  [[ "$output" == *'"status":"ok"'* ]]
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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"mode":"dry-run"'* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]
  [[ "$output" == *"shadow-effect-record:SE-user-001 begin"* ]]
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
  [[ "$output" == *'"today_override_warning"'* ]]
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
  [[ "$output" == *"separate from final_shadow_apply"* ]]
  [[ "$output" == *'"next_actions"'* ]]
  [[ "$output" == *'"action":"create_evidence_decision"'* ]]
  [[ "$output" == *"--decision-type business_intent"* ]]
  [[ "$output" == *"--record"* ]]
  [[ "$output" != *"--applies-record-id"* ]]

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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_ref: UD-evidence-001"* ]]

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
  [[ "$output" == *"answer must affirm"* ]]

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
  [[ "$output" == *"human-only effect types"* ]]
}

@test "shadow_effect_writer enforces deterministic evidence metadata" {
  local candidate_file="$TEST_WORKSPACE/candidate.json"
  local decision_file="$TEST_WORKSPACE/decision.json"
  local code_record_file="$TEST_WORKSPACE/code-record.json"
  local runtime_record_file="$TEST_WORKSPACE/runtime-record.json"
  local bad_runtime_record_file="$TEST_WORKSPACE/bad-runtime-record.json"
  local good_code_record_file="$TEST_WORKSPACE/good-code-record.json"
  local missing_parser_record_file="$TEST_WORKSPACE/missing-parser-record.json"
  local mismatch_parser_record_file="$TEST_WORKSPACE/mismatch-parser-record.json"
  local good_runtime_record_file="$TEST_WORKSPACE/good-runtime-record.json"
  local missing_binding_metadata_record_file="$TEST_WORKSPACE/runtime-missing-binding-metadata-record.json"
  local binary_rfc8785_record_file="$TEST_WORKSPACE/runtime-binary-rfc8785-record.json"
  local ignored_fields_record_file="$TEST_WORKSPACE/runtime-ignored-fields-record.json"
  local missing_selected_fields_record_file="$TEST_WORKSPACE/runtime-missing-selected-fields-record.json"
  local malformed_selected_fields_record_file="$TEST_WORKSPACE/runtime-malformed-selected-fields-record.json"
  local duplicate_selected_fields_record_file="$TEST_WORKSPACE/runtime-duplicate-selected-fields-record.json"
  local dotted_selected_fields_record_file="$TEST_WORKSPACE/runtime-dotted-selected-fields-record.json"
  local selected_fields_record_file="$TEST_WORKSPACE/runtime-selected-fields-record.json"
  local missing_selected_field_record_file="$TEST_WORKSPACE/runtime-missing-selected-field-record.json"
  local non_json_selected_fields_record_file="$TEST_WORKSPACE/runtime-non-json-selected-fields-record.json"
  local invalid_line_range_record_file="$TEST_WORKSPACE/runtime-invalid-line-range-record.json"
  local valid_custom_line_range_record_file="$TEST_WORKSPACE/runtime-valid-custom-line-range-record.json"
  local missing_line_range_probe_record_file="$TEST_WORKSPACE/runtime-missing-line-range-probe-record.json"
  local out_of_range_line_range_record_file="$TEST_WORKSPACE/runtime-out-of-range-line-range-record.json"
  local code_probe_file="$TEST_WORKSPACE/code-probe.json"
  local runtime_probe_file="$TEST_WORKSPACE/runtime-probe.json"
  local runtime_line_probe_file="$TEST_WORKSPACE/runtime-line-probe.json"
  local runtime_selected_probe_file="$TEST_WORKSPACE/runtime-selected-probe.json"
  local missing_selected_probe_record_file="$TEST_WORKSPACE/runtime-missing-selected-probe-record.json"
  local runtime_decision_file="$TEST_WORKSPACE/runtime-decision.json"
  local runtime_json_decision_file="$TEST_WORKSPACE/runtime-json-decision.json"
  local runtime_mismatch_decision_file="$TEST_WORKSPACE/runtime-mismatch-decision.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local source_hash
  local parser_identity
  local parser_content_hash
  local runtime_hash
  local runtime_line_hash
  local runtime_selected_hash
  local runtime_json_event='{"event":"user.cache.evict","timestamp":"2026-05-02T00:00:00Z","userId":42}'
  local runtime_json_event_json='{\"event\":\"user.cache.evict\",\"timestamp\":\"2026-05-02T00:00:00Z\",\"userId\":42}'
  local code_probe_hash
  local runtime_probe_hash
  local runtime_line_probe_hash
  local runtime_selected_probe_hash
  local setter_module_hash
  local runtime_statement="Cache eviction is backed by a runtime trace artifact."
  local runtime_json_statement="Cache eviction is backed by selected JSON runtime fields."
  local runtime_statement_hash
  local runtime_json_statement_hash

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

  local candidate_id
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
  [[ "$output" == *"deterministic_code evidence.rule_id is required"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence.trace_ref is required"* ]]
  [[ "$output" == *"deterministic_runtime evidence.artifact_hash must be a sha256 reference"* ]]
  [[ "$output" == *"deterministic_runtime evidence.artifact_media_type is required"* ]]
  [[ "$output" == *"deterministic_runtime evidence.ignored_nondeterministic_fields must be a list of strings"* ]]
  [[ "$output" == *'"action":"complete_runtime_scenario_fit_args"'* ]]
  [[ "$output" != *"--decision-type runtime_scenario_fit"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence.scenario_scope is required"* ]]
  [[ "$output" == *"deterministic_runtime evidence.setter_symbol_path is required"* ]]
  [[ "$output" == *"deterministic_runtime evidence.setter_module_hash must be a sha256 reference"* ]]
  [[ "$output" == *"deterministic_runtime evidence.expiry_or_invalidation_rule must be timestamp, binding_change, or manual_revocation"* ]]
  [[ "$output" == *'"action":"complete_runtime_scenario_fit_args"'* ]]
  [[ "$output" == *"deterministic_runtime evidence.scenario_scope"* ]]
  [[ "$output" == *"deterministic_runtime evidence.setter_module_hash"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$bad_runtime_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"deterministic_runtime evidence.artifact_hash must be a sha256 reference"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$good_code_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *'"next_actions"'* ]]
  [[ "$output" == *'"action":"run_probe"'* ]]
  [[ "$output" == *"shadow_evidence_probe.py"* ]]
  [[ "$output" == *"--probe-result"* ]]

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
  [[ "$output" == *"deterministic_code evidence.parser_identity is required"* ]]
  [[ "$output" == *"deterministic_code evidence.parser_content_hash must be a sha256 reference"* ]]

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
  [[ "$output" == *"probe_result.parser_identity must match evidence.parser_identity"* ]]
  [[ "$output" == *"probe_result.parser_content_hash must match evidence.parser_content_hash"* ]]

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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_rule_id: repo.write"* ]]
  [[ "$output" == *"evidence_parser_backed: True"* ]]
  [[ "$output" == *"evidence_parser_identity: $parser_identity"* ]]
  [[ "$output" == *"evidence_parser_content_hash: $parser_content_hash"* ]]
  [[ "$output" == *"evidence_source_hash: $source_hash"* ]]

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
  [[ "$output" == *'"next_actions"'* ]]
  [[ "$output" == *"--decision-type runtime_scenario_fit"* ]]
  [[ "$output" == *"--trace-ref logs/runtime.trace:2"* ]]
  [[ "$output" == *"--scenario-ref scenario:user-update-cache"* ]]
  [[ "$output" == *"--scenario-scope runtime.scopes.user_update_cache"* ]]
  [[ "$output" == *"--setter-symbol-path RuntimeScenarioRegistry.userUpdateCacheEvict"* ]]
  [[ "$output" == *"--setter-module-hash $setter_module_hash"* ]]
  [[ "$output" == *"--expiry-or-invalidation-rule binding_change"* ]]
  [[ "$output" != *"choose_supported_fact_decision_type"* ]]

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
  [[ "$output" == *"applies_to must bind record_id, effect_type, statement_hash, anchor, trace_ref, scenario_ref, scenario_scope, setter_symbol_path, setter_module_hash, and expiry_or_invalidation_rule"* ]]

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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_artifact_hash: $runtime_hash"* ]]
  [[ "$output" == *"evidence_artifact_media_type: text/plain"* ]]
  [[ "$output" == *"evidence_encoding: utf-8"* ]]
  [[ "$output" == *"evidence_canonicalization: none"* ]]
  [[ "$output" == *"evidence_hash_input_scope: whole_artifact"* ]]
  [[ "$output" == *"evidence_ignored_nondeterministic_fields: []"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence envelope is not supported by the v1 validity matrix"* ]]

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
  [[ "$output" == *"ignored_nondeterministic_fields must be empty for whole_artifact unless canonicalization is custom-declared"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence.selected_fields must be a non-empty list of strings for selected_fields scope"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence.selected_fields must be a non-empty list of strings for selected_fields scope"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence.selected_fields must not contain duplicate field names"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence.selected_fields supports only top-level field names"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence.line_range must satisfy integer start >= 1 and end >= start"* ]]

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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_hash_input_scope: line_range"* ]]
  [[ "$output" == *"evidence_line_range: {\"end\":2,\"start\":2}"* ]]
  [[ "$output" == *"evidence_artifact_hash: $runtime_line_hash"* ]]

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
  [[ "$output" == *'"next_actions"'* ]]
  [[ "$output" == *'"action":"run_probe"'* ]]
  [[ "$output" == *"--hash-input-scope line_range"* ]]
  [[ "$output" == *"--line-range-start 2"* ]]
  [[ "$output" == *"--line-range-end 2"* ]]

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
  [[ "$output" == *"deterministic_runtime evidence.trace_ref line must be inside evidence.line_range"* ]]

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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_hash_input_scope: selected_fields"* ]]
  [[ "$output" == *"evidence_selected_fields: [\"event\",\"userId\"]"* ]]
  [[ "$output" == *"evidence_artifact_hash: $runtime_selected_hash"* ]]

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
  [[ "$output" == *'"next_actions"'* ]]
  [[ "$output" == *'"action":"run_probe"'* ]]
  [[ "$output" == *"--hash-input-scope selected_fields"* ]]
  [[ "$output" == *"--selected-field event"* ]]
  [[ "$output" == *"--selected-field userId"* ]]

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
  [[ "$output" == *"deterministic_runtime selected_fields must exist in trace artifact"* ]]

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
  [[ "$output" == *"deterministic_runtime selected_fields trace artifact must be valid JSON"* ]]
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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_ref: java.ast.call_match@v1"* ]]
  [[ "$output" == *"evidence_validator_kind: java_token_parser"* ]]
  [[ "$output" == *"evidence_parser_backed: True"* ]]
  [[ "$output" == *"evidence_parser_identity: $parser_identity"* ]]
  [[ "$output" == *"evidence_parser_content_hash: $parser_content_hash"* ]]
  [[ "$output" == *"evidence_source_hash: $source_hash"* ]]

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
  [[ "$output" == *"receiver is required for confirmed java.ast.call_match@v1"* ]]

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
  [[ "$output" == *"receiver is required for confirmed java.ast.call_match@v1"* ]]
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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_ref: js.ast.call_match@v1"* ]]
  [[ "$output" == *"evidence_validator_kind: js_token_parser"* ]]
  [[ "$output" == *"evidence_parser_backed: True"* ]]
  [[ "$output" == *"evidence_parser_identity: $parser_identity"* ]]
  [[ "$output" == *"evidence_parser_content_hash: $parser_content_hash"* ]]
  [[ "$output" == *"evidence_source_hash: $source_hash"* ]]

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
  [[ "$output" == *"matched_symbol"* || "$output" == *"anchor.symbol"* ]]

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
  [[ "$output" == *"probe_result.fact_status"* ]]
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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_ref: ts.ast.call_match@v2"* ]]
  [[ "$output" == *"evidence_validator_kind: ts_token_parser"* ]]
  [[ "$output" == *"evidence_parser_backed: True"* ]]
  [[ "$output" == *"evidence_parser_identity: $parser_identity"* ]]
  [[ "$output" == *"evidence_parser_content_hash: $parser_content_hash"* ]]
  [[ "$output" == *"evidence_source_hash: $source_hash"* ]]

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
  [[ "$output" == *"probe_result.type_arguments"* ]]

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
  [[ "$output" == *"probe_result.type_arguments"* ]]
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
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"evidence_ref: fastapi.route@v1"* ]]
  [[ "$output" == *"evidence_validator_kind: ast"* ]]
  [[ "$output" == *"evidence_parser_backed: True"* ]]
  [[ "$output" == *"evidence_parser_identity: $parser_identity"* ]]
  [[ "$output" == *"evidence_parser_content_hash: $parser_content_hash"* ]]
  [[ "$output" == *"evidence_source_hash: $source_hash"* ]]

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
  [[ "$output" == *"probe_result.route_path"* ]]

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
  [[ "$output" == *"matched_symbol"* || "$output" == *"anchor.symbol"* ]]

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
  [[ "$output" == *"probe_result.route_path"* ]]
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
  [[ "$output" == *"matched_symbol"* || "$output" == *"anchor.symbol"* ]]
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
{"record_id":"SE-user-019","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Runtime evidence must use a runtime trace validator.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.command.output@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","scenario_scope":"runtime.scopes.user_update_cache","setter_symbol_path":"RuntimeScenarioRegistry.userUpdateCacheEvict","setter_module_hash":"$setter_module_hash","expiry_or_invalidation_rule":"binding_change","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$unimplemented_record" <<EOF
{"record_id":"SE-user-020","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"api_route","statement":"Documented-only Express route validator cannot be forged as implemented.","anchor":{"file":"src/main/java/example/UserService.java","symbol":"app.get"},"evidence":{"type":"deterministic_code","ref":"express.route@v1","rule_id":"http.route","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/main/java/example/UserService.java:5","source_hash":"$java_source_hash","probe_args":{"callee":"get","receiver":"app"}}}
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
  [[ "$output" == *"evidence.rule_id is not registered"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$incompatible_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence.ref is not compatible with evidence.rule_id"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$source_probe_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"source_probe-only"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$stale_source_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"source_hash must match"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_ref_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"runtime_trace validator"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$unimplemented_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"implemented by shadow_evidence_probe"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$stale_runtime_record" --candidate "$candidate_file" --user-decision "$decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_hash must match"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$forged_code_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$wrong_code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"probe_result.source_ref must match"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$wrong_effect_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rule_id is not compatible with record.effect_type"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$wrong_symbol_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"anchor.symbol must match deterministic probe args"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$path_only_source_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$same_file_wrong_line_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"source_ref must match"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$custom_rule_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$code_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no allowed_effect_types policy mapping"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_scenario_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"user_decision_ref is required"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_bad_decision_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_bad_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision_type must be runtime_scenario_fit"* ]]
  [[ "$output" == *"answer must affirm"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_one_sided_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_one_sided_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"source_refs must include all required evidence refs"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_mismatch_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_mismatch_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"applies_to must bind"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_wrong_effect_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_one_sided_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rule_id is not compatible with record.effect_type"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$runtime_wrong_anchor_record" --candidate "$candidate_file" --user-decision "$decision_file" --probe-result "$runtime_probe_file" --evidence-decision "$runtime_one_sided_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"anchor.file must match"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" --project-root "$TEST_PROJECT" --record "$human_mismatch_record" --candidate "$candidate_file" --user-decision "$decision_file" --evidence-decision "$human_mismatch_decision_file" --target-shadow-file "packages/codeguide/effects.md" --mode dry-run --today "2026-05-02"
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision_type is not compatible"* ]]
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
  [[ "$output" == *"--expected-target-hash is required"* ]]

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
  [[ "$output" == *'"operation":"create"'* ]]
  [[ "$output" == *'"writes_shadow_docs":true'* ]]
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
  [[ "$output" == *"record content"* ]]

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
  [[ "$output" == *'"operation":"update"'* ]]
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
  [[ "$output" == *"exactly one begin and end marker"* ]]

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
  [[ "$output" == *'"operation":"update"'* ]]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$blocked_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"lifecycle transition blocked: unknown -> blocked"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$stale_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"lifecycle transition blocked: unknown -> stale"* ]]

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
  [[ "$output" == *'"operation":"update"'* ]]
  [[ "$output" == *"evidence_parser_backed: True"* ]]

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
  [[ "$output" == *"lifecycle transition blocked: confirmed -> unknown"* ]]

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
  [[ "$output" == *"existing record SE-life-001 lifecycle metadata is missing or malformed"* ]]
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
  [[ "$output" == *"target shadow file must declare doc_role: effect_map"* ]]
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
  [[ "$output" == *"must not create reserved shadow navigation paths"* ]]
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
  [[ "$output" == *"record.record_id must not contain --"* ]]
  [[ "$output" == *"record.source_refs must be a list"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$missing_effect_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"record.effect_type is required"* ]]

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
  [[ "$output" == *"exactly one begin and end marker"* ]]

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
  [[ "$output" == *"interleaved shadow-effect-record markers"* ]]
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
  [[ "$output" == *"llm_hint"* ]]
  [[ "$output" == *"target hash mismatch"* ]]
  [[ "$output" == *"forbidden Markdown marker"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$unknown_record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "packages/codeguide/effects.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 1 ]
  [[ "$output" == *"llm_hint"* ]]

  run python3 "$SHADOW_EFFECT_WRITER" \
    --project-root "$TEST_PROJECT" \
    --record "$record_file" \
    --candidate "$candidate_file" \
    --user-decision "$decision_file" \
    --target-shadow-file "../outside.md" \
    --mode dry-run \
    --today "2026-05-02"

  [ "$status" -eq 64 ]
  [[ "$output" == *"traversal"* ]]
}

# ========== P1/P2: Validator strict mode non-empty check ==========

@test "shadow_policy_loader reports adapter ids and catalog parity" {
  run python3 "$SHADOW_POLICY_LOADER" --adapter-module "$SHADOW_PROBE" --print-adapter-ids
  [ "$status" -eq 0 ]
  [[ "$output" == *"py.ast.call_match@v1"* ]]
  [[ "$output" == *"js.ast.call_match@v1"* ]]
  [[ "$output" == *"ts.ast.call_match@v1"* ]]
  [[ "$output" == *"ts.ast.call_match@v2"* ]]
  [[ "$output" == *"fastapi.route@v1"* ]]
  [[ "$output" == *"express.route@v1"* ]]
  [[ "$output" == *"react.effect_hook@v1"* ]]
  [[ "$output" == *"react.jsx_event_binding@v1"* ]]
  [[ "$output" == *"any.runtime.trace@v1"* ]]

  run python3 "$SHADOW_POLICY_LOADER" --adapter-module "$SHADOW_PROBE" --print-adapter-json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ts.ast.call_match@v2"'* ]]
  [[ "$output" == *'"express.route@v1"'* ]]
  [[ "$output" == *'"react.effect_hook@v1"'* ]]
  [[ "$output" == *'"react.jsx_event_binding@v1"'* ]]
  [[ "$output" == *'"allowed_extensions":[".ts",".tsx",".mts",".cts"]'* ]]
  [[ "$output" == *'"rejected_extensions":[".d.ts"]'* ]]
  [[ "$output" == *'"allowed_paths":["src/**","app/**","lib/**","server/**","pages/**","routes/**"]'* ]]

  run python3 "$SHADOW_POLICY_LOADER" --policy-dir "$DOCS_ROOT/policy" --adapter-module "$SHADOW_PROBE" --check-parity
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"adapter_specs"'* ]]

  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, sql.write_call\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  run python3 "$SHADOW_POLICY_LOADER" --policy-dir "$DOCS_ROOT/policy" --adapter-module "$SHADOW_PROBE" --check-parity
  [ "$status" -ne 0 ]
  [[ "$output" == *"implemented_primary_v1 id must be implemented by shadow_evidence_probe.py"* ]]
}

