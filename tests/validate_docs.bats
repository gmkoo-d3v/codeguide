#!/usr/bin/env bats

load codeguide_helper

@test "validate_docs rejects legacy root orchestration paths" {
  cat > "$DOCS_ROOT/orchestration/ORCH-legacy-01.md" <<'EOF'
# ORCH-legacy-01

- task_id: legacy-01
EOF
  mkdir -p "$DOCS_ROOT/orchestration/external-cli"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"legacy root orchestration file is not supported"* ]]
  [[ "$output" == *"legacy external CLI handoff root is not supported"* ]]
}

@test "validate_docs strict mode fails on empty required fields" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "200" \
    --task-title "" \
    --no-init

  # The task file will have title: (empty because upsert_field skips it on new file with template value)
  # Let's manually clear the axis fields to test strict validation
  local task_file="$DOCS_ROOT/task/TASK-200.md"
  # Ensure axis fields exist but are empty
  if ! grep -q "^- axis_why:" "$task_file"; then
    echo "- axis_why:" >> "$task_file"
  fi
  sed -i.bak 's/^- axis_why:.*$/- axis_why:/' "$task_file"
  rm -f "${task_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]] || [[ "$output" == *"FAIL"* ]]
}

@test "validate_docs strict audits effect_map markers and confirmed fields" {
  local effect_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"
  mkdir -p "$(dirname "$effect_file")"
  cat > "$effect_file" <<'EOF'
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-user-100 begin -->
## SE-user-100

- record_id: SE-user-100
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: db_write
- statement: confirmed record missing evidence fields
- anchor_file: src/UserService.java
- anchor_symbol: UserRepository.save

<!-- shadow-effect-record:SE-user-100 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"confirmed record requires evidence_type"* ]]
  [[ "$output" == *"shadow effect_map"* ]]

  cat > "$effect_file" <<'EOF'
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-user-101 begin -->
## SE-user-101

- record_id: SE-user-101
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: db_write
- statement: confirmed deterministic code record has shallow evidence only
- anchor_file: src/UserService.java
- anchor_symbol: UserRepository.save
- evidence_type: deterministic_code
- evidence_ref: py.ast.call_match@v1

<!-- shadow-effect-record:SE-user-101 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"deterministic_code record requires evidence_rule_id"* ]]
  [[ "$output" == *"deterministic_code record requires evidence_probe_result_hash"* ]]

  cat > "$effect_file" <<'EOF'
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-user-102 begin -->
## SE-user-102

- record_id: SE-user-102
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: forged deterministic code metadata must still fail semantic checks
- anchor_file: src/UserService.java
- anchor_symbol: UserRepository.save
- evidence_type: deterministic_code
- evidence_ref: py.ast.call_match@v1
- evidence_rule_id: repo.write
- evidence_validator_kind: ast
- evidence_parser_backed: true
- evidence_parser_identity: shadow_evidence_probe.py:py.ast.call_match@v1:ast
- evidence_parser_content_hash: sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
- evidence_validator_result: matched
- evidence_source_ref: src/OtherService.java:9
- evidence_source_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_probe_result_ref: missing-probe.json
- evidence_probe_result_hash: sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

<!-- shadow-effect-record:SE-user-102 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"evidence_rule_id is not compatible with effect_type"* ]]
  [[ "$output" == *"anchor_file must match evidence ref path"* ]]
  [[ "$output" == *"probe artifact must exist"* ]]
}

@test "validate_docs strict audits deterministic_runtime envelope metadata" {
  local effect_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"
  local runtime_probe_file="$TEST_PROJECT/probe-results/runtime-probe.json"
  local runtime_line_probe_file="$TEST_PROJECT/probe-results/runtime-line-probe.json"
  local runtime_selected_probe_file="$TEST_PROJECT/probe-results/runtime-selected-probe.json"
  local runtime_json_event='{"event":"user.cache.evict","userId":42,"timestamp":"2026-05-02T00:00:00Z"}'
  local runtime_probe_hash
  local runtime_line_probe_hash
  local runtime_selected_probe_hash
  local runtime_line_hash
  local runtime_selected_hash
  local setter_module_hash

  mkdir -p "$(dirname "$effect_file")" "$(dirname "$runtime_probe_file")" "$TEST_PROJECT/logs"
  printf '%s\n' "event=user.cache.evict" > "$TEST_PROJECT/logs/runtime.trace"
  printf '%s\n' "$runtime_json_event" > "$TEST_PROJECT/logs/runtime-json.trace"
  printf '{"status":"pass"}\n' > "$runtime_probe_file"
  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime.trace" \
    --trace-event "event=user.cache.evict" \
    --hash-input-scope "line_range" \
    --line-range-start 1 \
    --line-range-end 1 > "$runtime_line_probe_file"
  python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime-json.trace" \
    --trace-event "$runtime_json_event" \
    --hash-input-scope "selected_fields" \
    --selected-field "event" \
    --selected-field "userId" > "$runtime_selected_probe_file"
  runtime_probe_hash="$(sha256_file_ref "$runtime_probe_file")"
  runtime_line_probe_hash="$(sha256_file_ref "$runtime_line_probe_file")"
  runtime_selected_probe_hash="$(sha256_file_ref "$runtime_selected_probe_file")"
  runtime_line_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact_hash"])' "$runtime_line_probe_file")"
  runtime_selected_hash="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact_hash"])' "$runtime_selected_probe_file")"
  setter_module_hash="$(sha256_file_ref "$SHADOW_USER_DECISION")"

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-100 begin -->
## SE-runtime-100

- record_id: SE-runtime-100
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Runtime evidence without envelope metadata must fail strict docs validation.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_scenario_ref: scenario:user-update-cache
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-100 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"deterministic_runtime record requires evidence_artifact_media_type"* ]]
  [[ "$output" == *"deterministic_runtime record requires evidence_ignored_nondeterministic_fields"* ]]
  [[ "$output" == *"deterministic_runtime record requires evidence_scenario_scope"* ]]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-105 begin -->
## SE-runtime-105

- record_id: SE-runtime-105
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Malformed runtime scenario fit metadata must fail strict docs validation.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: none
- evidence_hash_input_scope: whole_artifact
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: no
- evidence_setter_symbol_path: 1Invalid.setter
- evidence_setter_module_hash: sha256:x
- evidence_expiry_or_invalidation_rule: automatic
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-105 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"deterministic_runtime evidence_scenario_scope must match"* ]]
  [[ "$output" == *"deterministic_runtime evidence_setter_symbol_path must match"* ]]
  [[ "$output" == *"deterministic_runtime evidence_setter_module_hash must be sha256"* ]]
  [[ "$output" == *"deterministic_runtime evidence_expiry_or_invalidation_rule must be timestamp, binding_change, or manual_revocation"* ]]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-106 begin -->
## SE-runtime-106

- record_id: SE-runtime-106
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Rendered runtime line-range evidence should validate with scoped artifact hashing.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: $runtime_line_hash
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: custom-declared
- evidence_canonical_output_type: text
- evidence_hash_input_scope: line_range
- evidence_line_range: {"end":1,"start":1}
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-line-probe.json
- evidence_probe_result_hash: $runtime_line_probe_hash

<!-- shadow-effect-record:SE-runtime-106 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-108 begin -->
## SE-runtime-108

- record_id: SE-runtime-108
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Rendered runtime selected-fields evidence must reject duplicate field names.
- anchor_file: logs/runtime-json.trace
- anchor_line: 1
- anchor_symbol: $runtime_json_event
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime-json.trace:1
- evidence_artifact_hash: $runtime_selected_hash
- evidence_artifact_media_type: application/json
- evidence_encoding: utf-8
- evidence_canonicalization: rfc8785
- evidence_hash_input_scope: selected_fields
- evidence_selected_fields: ["event","event"]
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-selected-probe.json
- evidence_probe_result_hash: $runtime_selected_probe_hash

<!-- shadow-effect-record:SE-runtime-108 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"deterministic_runtime evidence_selected_fields must not contain duplicate field names"* ]]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-109 begin -->
## SE-runtime-109

- record_id: SE-runtime-109
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Rendered runtime selected-fields evidence must reject nested field names.
- anchor_file: logs/runtime-json.trace
- anchor_line: 1
- anchor_symbol: $runtime_json_event
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime-json.trace:1
- evidence_artifact_hash: $runtime_selected_hash
- evidence_artifact_media_type: application/json
- evidence_encoding: utf-8
- evidence_canonicalization: rfc8785
- evidence_hash_input_scope: selected_fields
- evidence_selected_fields: ["payload.event"]
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-selected-probe.json
- evidence_probe_result_hash: $runtime_selected_probe_hash

<!-- shadow-effect-record:SE-runtime-109 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"deterministic_runtime evidence_selected_fields supports only top-level field names"* ]]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-107 begin -->
## SE-runtime-107

- record_id: SE-runtime-107
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Rendered runtime selected-fields evidence should validate with scoped artifact hashing.
- anchor_file: logs/runtime-json.trace
- anchor_line: 1
- anchor_symbol: $runtime_json_event
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime-json.trace:1
- evidence_artifact_hash: $runtime_selected_hash
- evidence_artifact_media_type: application/json
- evidence_encoding: utf-8
- evidence_canonicalization: rfc8785
- evidence_hash_input_scope: selected_fields
- evidence_selected_fields: ["event","userId"]
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-selected-probe.json
- evidence_probe_result_hash: $runtime_selected_probe_hash

<!-- shadow-effect-record:SE-runtime-107 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-101 begin -->
## SE-runtime-101

- record_id: SE-runtime-101
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Binary RFC8785 runtime envelope must fail the strict matrix.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: application/octet-stream
- evidence_encoding: binary
- evidence_canonicalization: rfc8785
- evidence_hash_input_scope: whole_artifact
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-101 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"deterministic_runtime evidence envelope is not supported by the v1 validity matrix"* ]]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-102 begin -->
## SE-runtime-102

- record_id: SE-runtime-102
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Non-custom runtime envelope must reject canonical_output_type.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: none
- evidence_canonical_output_type: text
- evidence_hash_input_scope: whole_artifact
- evidence_ignored_nondeterministic_fields: []
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-102 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"evidence_canonical_output_type is only valid for custom-declared canonicalization"* ]]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-103 begin -->
## SE-runtime-103

- record_id: SE-runtime-103
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Whole-artifact runtime envelope must not ignore fields without custom canonicalization.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: none
- evidence_hash_input_scope: whole_artifact
- evidence_ignored_nondeterministic_fields: ["timestamp"]
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-103 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"evidence_ignored_nondeterministic_fields must be [] for whole_artifact unless canonicalization is custom-declared"* ]]

  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-runtime-104 begin -->
## SE-runtime-104

- record_id: SE-runtime-104
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: cache_evict
- statement: Custom textual line-range runtime envelope is declared by the matrix but not implemented by runtime trace hashing.
- anchor_file: logs/runtime.trace
- anchor_line: 1
- anchor_symbol: event=user.cache.evict
- evidence_type: deterministic_runtime
- evidence_ref: any.runtime.trace@v1
- evidence_rule_id: cache.evict
- evidence_trace_ref: logs/runtime.trace:1
- evidence_artifact_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- evidence_artifact_media_type: text/plain
- evidence_encoding: utf-8
- evidence_canonicalization: custom-declared
- evidence_canonical_output_type: text
- evidence_hash_input_scope: line_range
- evidence_ignored_nondeterministic_fields: []
- evidence_line_range: {"end":1,"start":1}
- evidence_scenario_ref: scenario:user-update-cache
- evidence_scenario_scope: runtime.scopes.user_update_cache
- evidence_setter_symbol_path: RuntimeScenarioRegistry.userUpdateCacheEvict
- evidence_setter_module_hash: $setter_module_hash
- evidence_expiry_or_invalidation_rule: binding_change
- evidence_user_decision_ref: UD-runtime-013
- evidence_probe_result_ref: probe-results/runtime-probe.json
- evidence_probe_result_hash: $runtime_probe_hash

<!-- shadow-effect-record:SE-runtime-104 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"deterministic_runtime evidence_artifact_hash must match scoped trace artifact"* ]]
}

@test "validate_docs strict accepts canonical probe coverage for valid effect_map evidence" {
  local effect_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"
  local source_file="$TEST_PROJECT/src/app.py"
  local probe_file="$TEST_PROJECT/probe-results/code-probe.json"
  local source_hash
  local parser_identity
  local parser_content_hash
  local probe_hash

  mkdir -p "$(dirname "$effect_file")" "$(dirname "$source_file")" "$(dirname "$probe_file")"
  cat > "$source_file" <<'EOF'
def handler(repository, user):
    repository.save(user)
EOF
  source_hash="$(sha256_file_ref "$source_file")"
  parser_identity="$(parser_identity_ref "py.ast.call_match@v1" "ast")"
  parser_content_hash="$(sha256_file_ref "$SHADOW_PROBE")"
  cat > "$probe_file" <<EOF
{"status":"pass","probe_status":"pass","fact_status":"deterministic_evidence","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","evidence_field":"validator_result","validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"parser_identity":"$parser_identity","parser_content_hash":"$parser_content_hash","promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  probe_hash="$(sha256_file_ref "$probe_file")"
  cat > "$effect_file" <<EOF
# Effects

- doc_role: effect_map

<!-- shadow-effect-record:SE-user-103 begin -->
## SE-user-103

- record_id: SE-user-103
- record_type: effect_map_entry
- lifecycle: confirmed
- effect_type: db_write
- statement: Repository save is backed by canonical parser evidence.
- anchor_file: src/app.py
- anchor_symbol: repository.save
- evidence_type: deterministic_code
- evidence_ref: py.ast.call_match@v1
- evidence_rule_id: repo.write
- evidence_validator_kind: ast
- evidence_parser_backed: true
- evidence_parser_identity: $parser_identity
- evidence_parser_content_hash: $parser_content_hash
- evidence_validator_result: matched
- evidence_source_ref: src/app.py:2
- evidence_source_hash: $source_hash
- evidence_probe_result_ref: probe-results/code-probe.json
- evidence_probe_result_hash: $probe_hash

<!-- shadow-effect-record:SE-user-103 end -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadow effect_map records valid"* ]]
}

@test "validate_docs strict audits review_queue metadata" {
  local queue_file="$DOCS_ROOT/report/shadow-review-queue.md"
  cat > "$queue_file" <<'EOF'
# Shadow Evidence Review Queue

- doc_role: review_queue
- task_id: shadow-effect-map-01
- generated_by: shadow_review_queue.py
- generated_at: 2026-05-03T00:00:00Z
- writes_shadow_docs: false
- auto_promotes_facts: false
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"ttl_days"* ]]
}

@test "validate_docs strict allows mixed review_queue with deferred and bounded question" {
  local queue_file="$DOCS_ROOT/report/shadow-review-queue.md"
  cat > "$queue_file" <<'EOF'
# Shadow Evidence Review Queue

- doc_role: review_queue
- task_id: shadow-effect-map-01
- generated_by: shadow_review_queue.py
- generated_at: 2026-05-03T00:00:00Z
- ttl_days: 7
- writes_shadow_docs: false
- auto_promotes_facts: false
- input_records: 2
- max_questions: 1
- question_count: 1

## Evidence Candidates

- id: QE-001
  status: pass
  evidence_ref: jpa.repository.save@v1
  evidence_type: code_call
  strength: source_probe
  source_ref: unknown
  question_state: deferred_missing_context
  missing_question_context: source_ref_or_trace_ref
- id: QE-002
  status: fail
  evidence_ref: py.ast.call_match@v1
  evidence_type: code_call
  strength: parser_backed
  source_ref: src/app.py:4
  question_state: ready

## Review Questions

- id: RQ-001
  evidence_ref: QE-002
  priority: medium
  question: Should missing evidence stay unknown?
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadow review_queue source refs are bounded"* ]]
}

@test "validate_docs strict fails when policy rule registry has no mappings" {
  cat > "$DOCS_ROOT/policy/shadow-rule-registry.md" <<'EOF'
# Shadow Rule Registry

- registry_id: shadow-rule-registry
- registry_version: 1
- status: active-draft
- linked_task: TASK-shadow-effect-map-01
- linked_decisions: decision-shadow-practical-contract-01
- purpose: empty registry should fail
- last_updated: 2026-04-30T13:49:45Z

## Promotion Gates

```yaml
promotion_gates:
  regex_only:
    max_effective_risk: medium
  high_or_critical:
    requires_one_of:
      - parser_backed_validator
  unknown_defaults:
    unlisted_rule: unknown
    unlisted_boundary: unknown
    unmapped_stack: unknown
    unmapped_evidence_type: unknown
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"shadow rule registry missing rules block"* ]] || [[ "$output" == *"must contain at least one rule id mapping"* ]]
}

@test "validate_docs strict fails on invalid policy fallback risk enum" {
  sed -i.bak 's/max_promotion_risk: medium/max_promotion_risk: extreme/' "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  rm -f "$DOCS_ROOT/policy/shadow-regex-patterns.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"max_promotion_risk must be low|medium"* ]]
}

@test "validate_docs strict fails when policy promotion gate contract drifts" {
  sed -i.bak 's/forbidden_field: validator_result/forbidden_field: claim_result/' "$DOCS_ROOT/policy/shadow-rule-registry.md"
  rm -f "$DOCS_ROOT/policy/shadow-rule-registry.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"regex_only.forbidden_field must be validator_result"* ]]
}

@test "validate_docs strict fails when promotion gate token appears only outside scoped block" {
  sed -i.bak 's/max_effective_risk: medium/max_effective_risk: high/' "$DOCS_ROOT/policy/shadow-rule-registry.md"
  rm -f "$DOCS_ROOT/policy/shadow-rule-registry.md.bak"
  cat >> "$DOCS_ROOT/policy/shadow-rule-registry.md" <<'EOF'

<!-- misleading example: max_effective_risk: medium -->
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"regex_only.max_effective_risk must be medium"* ]]
}

@test "validate_docs strict fails when fallback mapping lacks its own cap" {
  perl -0pi -e 's/\n          fallback_max_risk: medium//' "$DOCS_ROOT/policy/shadow-rule-registry.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"fallback mapping missing fallback_max_risk"* ]]
}

@test "validate_docs strict fails when validator evidence type mismatches rule evidence branch" {
  perl -0pi -e 's/primary: jpa\.repository\.save\@v1/primary: any.runtime.trace\@v1/' "$DOCS_ROOT/policy/shadow-rule-registry.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"primary validator evidence_type mismatch"* ]]
}

@test "validate_docs strict fails when policy roots leave fenced yaml blocks" {
  perl -0pi -e 's/```yaml\nvalidators:/```text\nvalidators:/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"must define validators inside a fenced yaml block"* ]]
}

@test "validate_docs strict fails when validator catalog probe coverage metadata is missing" {
  perl -0pi -e 's/\n  source_probe_only:.*//' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"must declare source_probe_only"* ]]
}

@test "validate_docs strict fails when catalog coverage id is undeclared" {
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, py.missing_validator\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"implemented_primary_v1 id must be declared in validators block"* ]]
}

@test "validate_docs strict fails when catalog claims unimplemented probe primary" {
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, sql.write_call\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"implemented_primary_v1 id must be implemented by shadow_evidence_probe.py"* ]]
}

@test "validate_docs strict ignores validator ids declared outside validators block" {
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, py.outside_block\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  cat >> "$DOCS_ROOT/policy/shadow-validator-catalog.md" <<'EOF'

## Non Validator Example

```yaml
examples:
  py.outside_block@v1:
    evidence_type: code_call
```
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"implemented_primary_v1 id must be declared in validators block"* ]]
}

@test "validate_docs strict fails when adapter metadata drifts from catalog" {
  perl -0pi -e 's/(py\.ast\.call_match\@v1:\n\s+)evidence_type: code_call/${1}evidence_type: runtime_trace/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"evidence_type must match AdapterRegistry"* ]]
}

@test "validate_docs strict fails when fallback regex evidence type mismatches rule evidence branch" {
  perl -0pi -e 's/target: code_call/target: annotation/' "$DOCS_ROOT/policy/shadow-regex-patterns.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"fallback regex evidence_type mismatch"* ]]
}

@test "validate_docs strict fails when supervisor_subagents orchestration fields are blank" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-strict-01" \
    --task-title "Orchestration strict test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-orch-strict-01-v1.0.md" <<'EOF'
# PLAN-orch-strict-01-v1.0

- task_id: orch-strict-01
- plan_version: v1.0
- objective: validate orchestration strictness
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation fails on blank delegated ownership
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"planner_agents"* ]] || [[ "$output" == *"implementation_agents"* ]] || [[ "$output" == *"validation_agents"* ]]
}

@test "validate_docs strict fails when delegated orchestration preflight is blocked" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-preflight-01" \
    --task-title "Orchestration preflight strict test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-orch-preflight-01-v1.0.md" <<'EOF'
# PLAN-orch-preflight-01-v1.0

- task_id: orch-preflight-01
- plan_version: v1.0
- objective: validate orchestration preflight strictness
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation fails on blocked preflight
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local orch_file="$DOCS_ROOT/orchestration/orch-preflight-01/ORCH.md"
  perl -0pi -e 's/^- risk_preflight_status: pass$/- risk_preflight_status: approval_required/m; s/^- approval_required: false$/- approval_required: true/m; s/^- approval_ref:.*$/- approval_ref: user-approval-pending-001/m; s/^- approved_next_step:.*$/- approved_next_step: await user approval/m' "$orch_file"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"orchestration risk preflight must be pass or approved"* ]]
}

@test "validate_docs strict fails when approved preflight leaves approval_required false" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-approved-01" \
    --task-title "Approved preflight consistency test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-001" \
    --approved-next-step "run delegated review round r01" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-orch-approved-01-v1.0.md" <<'EOF'
# PLAN-orch-approved-01-v1.0

- task_id: orch-approved-01
- plan_version: v1.0
- objective: validate approved preflight field consistency
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation fails on approved/false mismatch
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local orch_file="$DOCS_ROOT/orchestration/orch-approved-01/ORCH.md"
  perl -0pi -e 's/^- approval_required: true$/- approval_required: false/m' "$orch_file"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"risk_preflight_status=approved requires approval_required=true"* ]]
}

@test "validate_docs strict fails when supervisor_subagents task has no evaluator report" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "report-strict-01" \
    --task-title "Report strict test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-report-strict-01-v1.0.md" <<'EOF'
# PLAN-report-strict-01-v1.0

- task_id: report-strict-01
- plan_version: v1.0
- objective: validate evaluator report enforcement
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation fails on missing evaluator report
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing evaluator report for active task TASK-report-strict-01"* ]]
}

@test "validate_docs advisory mode passes with empty fields (warns only)" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "201" \
    --task-title "Advisory test" \
    --no-init

  local task_file="$DOCS_ROOT/task/TASK-201.md"
  if ! grep -q "^- axis_why:" "$task_file"; then
    echo "- axis_why:" >> "$task_file"
  fi

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  # advisory mode should exit 0 even with warnings
  [ "$status" -eq 0 ]
}

@test "validate_docs strict fails when project shadow lags behind tracked task docs" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "shadow-lag-01" \
    --task-title "Shadow lag test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  sed -i.bak 's/^- last_updated:.*$/- last_updated: 2000-01-01T00:00:00Z/' "$DOCS_ROOT/shadow/project-shadow.md"
  rm -f "$DOCS_ROOT/shadow/project-shadow.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"shadow graph doc is older than tracked task/decision doc"* ]]
}

@test "validate_docs strict fails when shadow bucket index lags behind tracked task docs" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "shadow-bucket-lag-01" \
    --task-title "Shadow bucket lag test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  sed -i.bak 's/^- last_updated:.*$/- last_updated: 2000-01-01T00:00:00Z/' "$DOCS_ROOT/shadow/apps/_index.md"
  rm -f "$DOCS_ROOT/shadow/apps/_index.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"shadow graph doc is older than tracked task/decision doc"* ]]
  [[ "$output" == *"apps/_index.md"* ]]
}

@test "validate_docs strict fails when required shadow bucket index is missing" {
  rm -f "$DOCS_ROOT/shadow/apps/_index.md"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"shadow bucket index (apps) is missing"* ]]
}

@test "validate_docs strict fails when tracked shadow last_updated is blank or future" {
  sed -i.bak 's/^- last_updated:.*$/- last_updated:/' "$DOCS_ROOT/shadow/project-shadow.md"
  rm -f "$DOCS_ROOT/shadow/project-shadow.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"last_updated is present but empty in shadow router"* ]]

  "$INIT_SCAFFOLD" "$TEST_PROJECT"
  sed -i.bak 's/^- last_updated:.*$/- last_updated: 2999-01-01T00:00:00Z/' "$DOCS_ROOT/shadow/project-shadow.md"
  rm -f "$DOCS_ROOT/shadow/project-shadow.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"last_updated must not be in the future in shadow router"* ]]
}

@test "validate_docs strict fails when active task has no linked plan file" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "301" \
    --task-title "Plan linkage test" \
    --axis-why "Documented rationale" \
    --axis-where "Service boundary" \
    --axis-verify "Unit tests" \
    --no-init

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing plan file for active task TASK-301"* ]]
}

@test "validate_docs strict fails on invalid evaluator label in report file" {
  # Create a valid plan file first
  cat > "$DOCS_ROOT/plan/PLAN-qa-01-v1.0.md" <<'EOF'
# PLAN-qa-01-v1.0

- task_id: qa-01
- plan_version: v1.0
- objective: verify evaluator label check
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: validation fails as expected
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  # Invalid evaluator in both filename and field
  cat > "$DOCS_ROOT/report/PLAN-qa-01-v1.0-review-gpt-r01.md" <<'EOF'
# PLAN-qa-01-v1.0 review (gpt)

- task_id: qa-01
- plan_version: v1.0
- evaluator: gpt
- review_round: r01
- verdict: revise
- summary: invalid evaluator
- strengths:
- risks:
- requested_changes:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid evaluator report file name format"* ]] || [[ "$output" == *"invalid evaluator in PLAN-qa-01-v1.0-review-gpt-r01.md"* ]]
}

@test "validate_docs strict fails on invalid task risk_level enum" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "risk-enum-task-01" \
    --task-title "Task risk enum test" \
    --task-status "planned" \
    --risk-level "low" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  local task_file="$DOCS_ROOT/task/TASK-risk-enum-task-01.md"
  sed -i.bak 's/^- risk_level:.*$/- risk_level: unknown/' "$task_file"
  rm -f "${task_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid task.risk_level value"* ]]
}

@test "validate_docs advisory warns on invalid decision risk_level enum" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "risk-enum-decision-01" \
    --decision-title "Decision risk enum test" \
    --selected-option "Option A" \
    --risk-level "medium" \
    --axis-why "why" \
    --axis-what "what" \
    --axis-how "how" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  local decision_file="$DOCS_ROOT/decisions/decision-risk-enum-decision-01.md"
  sed -i.bak 's/^- risk_level:.*$/- risk_level: severe/' "$decision_file"
  rm -f "${decision_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid decision.risk_level value"* ]]
}

@test "validate_docs advisory warns when active task omits risk_level" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "risk-missing-01" \
    --task-title "Missing risk level task" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-risk-missing-01-v1.0.md" <<'EOF'
# PLAN-risk-missing-01-v1.0

- task_id: risk-missing-01
- plan_version: v1.0
- objective: verify advisory warning when risk_level is omitted
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: advisory warning is emitted
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-risk-missing-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-risk-missing-01-v1.0 review (codex)

- task_id: risk-missing-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: accept
- summary: standard review exists
- strengths:
- risks:
- requested_changes:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"risk_level is recommended for active task TASK-risk-missing-01"* ]]
}

@test "validate_docs strict passes legacy evaluator report without review_style" {
  cat > "$DOCS_ROOT/plan/PLAN-legacy-01-v1.0.md" <<'EOF'
# PLAN-legacy-01-v1.0

- task_id: legacy-01
- plan_version: v1.0
- objective: verify legacy report compatibility
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation passes without review_style
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-legacy-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-legacy-01-v1.0 review (codex)

- task_id: legacy-01
- plan_version: v1.0
- evaluator: codex
- review_round: r01
- verdict: accept
- summary: legacy format remains valid
- strengths: legacy report still contains parser-compatible fields
- risks: missing review_style is tolerated for backward compatibility
- requested_changes: none
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs strict fails on hollow evaluator report fields" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "hollow-report-01" \
    --task-title "Hollow report test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-hollow-report-01-v1.0.md" <<'EOF'
# PLAN-hollow-report-01-v1.0

- task_id: hollow-report-01
- plan_version: v1.0
- objective: verify strict report fields
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: strict validation fails on empty report field
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-hollow-report-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-hollow-report-01-v1.0 review (codex)

- task_id: hollow-report-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: report exists
- strengths: has a strength
- risks: has a risk
- requested_changes:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"requested_changes is present but empty in evaluator report"* ]]
}

@test "validate_docs strict requires evaluator report for latest plan version" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "latest-report-01" \
    --task-title "Latest report test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-latest-report-01-v1.0.md" <<'EOF'
# PLAN-latest-report-01-v1.0

- task_id: latest-report-01
- plan_version: v1.0
- objective: old plan
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: old report exists
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/plan/PLAN-latest-report-01-v1.1.md" <<'EOF'
# PLAN-latest-report-01-v1.1

- task_id: latest-report-01
- plan_version: v1.1
- objective: latest plan
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: latest report required
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-02T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-latest-report-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-latest-report-01-v1.0 review (codex)

- task_id: latest-report-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: old plan reviewed
- strengths: old report exists
- risks: latest plan remains unreviewed
- requested_changes: review the latest plan
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing evaluator report for active task TASK-latest-report-01 latest plan v1.1"* ]]
}

@test "validate_docs strict rejects stale evaluator report for latest plan" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "stale-report-01" \
    --task-title "Stale report test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-stale-report-01-v1.0.md" <<'EOF'
# PLAN-stale-report-01-v1.0

- task_id: stale-report-01
- plan_version: v1.0
- objective: latest plan
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: fresh report required
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-02T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-stale-report-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-stale-report-01-v1.0 review (codex)

- task_id: stale-report-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: stale report
- strengths: report exists
- risks: plan changed after review
- requested_changes: refresh review
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing fresh evaluator report for active task TASK-stale-report-01 latest plan v1.0"* ]]
}

@test "validate_docs strict rejects evaluator report task identity mismatch" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "identity-report-01" \
    --task-title "Identity report test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-identity-report-01-v1.0.md" <<'EOF'
# PLAN-identity-report-01-v1.0

- task_id: identity-report-01
- plan_version: v1.0
- objective: identity plan
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: identity mismatch fails
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-identity-report-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-identity-report-01-v1.0 review (codex)

- task_id: other-task
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: wrong task
- strengths: report exists
- risks: report can attach to wrong task
- requested_changes: bind identity
- last_updated: 2026-01-02T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"evaluator report identity mismatch"* ]] || [[ "$output" == *"task_id mismatch between file name and field"* ]]
}

@test "validate_docs strict fails when high-risk task has only standard review" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "highrisk-01" \
    --task-title "High risk task" \
    --task-status "in_progress" \
    --risk-level "high" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-highrisk-01-v1.0.md" <<'EOF'
# PLAN-highrisk-01-v1.0

- task_id: highrisk-01
- plan_version: v1.0
- objective: verify automatic adversarial requirement for high-risk tasks
- scope: docs validation
- assumptions: none
- risks: high
- acceptance_signals: strict validation fails without adversarial report
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-highrisk-01-v1.0-review-codex-r01.md" <<'EOF'
# PLAN-highrisk-01-v1.0 review (codex)

- task_id: highrisk-01
- plan_version: v1.0
- evaluator: codex
- review_style: standard
- review_round: r01
- verdict: revise
- summary: standard review exists
- strengths:
- risks:
- requested_changes: tighten the implementation plan
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing adversarial evaluator report for high-risk task TASK-highrisk-01"* ]]
}

@test "validate_docs strict fails when linked high-risk decision has only standard review" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "linkedrisk-01" \
    --task-title "Linked risk task" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "antigravity" \
    --review-mode "agy_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "linkedrisk-dec-01" \
    --decision-title "Linked high risk decision" \
    --linked-task "TASK-linkedrisk-01" \
    --selected-option "Option A" \
    --risk-level "critical" \
    --axis-why "why" \
    --axis-what "what" \
    --axis-how "how" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-linkedrisk-01-v1.0.md" <<'EOF'
# PLAN-linkedrisk-01-v1.0

- task_id: linkedrisk-01
- plan_version: v1.0
- objective: verify linked decision drives adversarial enforcement
- scope: docs validation
- assumptions: none
- risks: high
- acceptance_signals: strict validation fails without adversarial report
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-linkedrisk-01-v1.0-review-gemini-r01.md" <<'EOF'
# PLAN-linkedrisk-01-v1.0 review (gemini)

- task_id: linkedrisk-01
- plan_version: v1.0
- evaluator: gemini
- review_style: standard
- review_round: r01
- verdict: revise
- summary: standard review exists
- strengths:
- risks:
- requested_changes: revisit the failure modes
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"decision-linkedrisk-dec-01.md risk_level=critical"* ]]
}

@test "validate_docs strict fails when adversarial evaluator report omits rebuttal fields" {
  cat > "$DOCS_ROOT/plan/PLAN-adv-01-v1.0.md" <<'EOF'
# PLAN-adv-01-v1.0

- task_id: adv-01
- plan_version: v1.0
- objective: verify adversarial review requirements
- scope: docs validation
- assumptions: none
- risks: medium
- acceptance_signals: strict validation fails on missing adversarial fields
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-adv-01-v1.0-review-claude-r01.md" <<'EOF'
# PLAN-adv-01-v1.0 review (claude)

- task_id: adv-01
- plan_version: v1.0
- evaluator: claude
- review_style: adversarial
- review_round: r01
- verdict: revise
- summary: challenge the initial plan once
- strengths: adversarial framing is present
- risks: missing adversarial details should fail strict validation
- requested_changes: tighten the design before implementation
- objection: the initial plan may understate failure modes
- counterproposal:
- rebuttal:
- residual_risk:
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"counterproposal"* ]] || [[ "$output" == *"rebuttal"* ]] || [[ "$output" == *"residual_risk"* ]]
}

@test "validate_docs strict passes when high-risk task has adversarial review" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "highrisk-pass-01" \
    --task-title "High risk pass task" \
    --task-status "in_progress" \
    --risk-level "critical" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-highrisk-pass-01" \
    --approved-next-step "record external adversarial review for highrisk-pass-01" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --primary-author-tool "antigravity" \
    --review-mode "external_cli" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-highrisk-pass-01-v1.0.md" <<'EOF'
# PLAN-highrisk-pass-01-v1.0

- task_id: highrisk-pass-01
- plan_version: v1.0
- objective: verify high-risk task passes with adversarial review
- scope: docs validation
- assumptions: none
- risks: high
- acceptance_signals: strict validation passes
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  cat > "$DOCS_ROOT/report/PLAN-highrisk-pass-01-v1.0-review-claude-r01.md" <<'EOF'
# PLAN-highrisk-pass-01-v1.0 review (claude)

- task_id: highrisk-pass-01
- plan_version: v1.0
- evaluator: claude
- review_style: adversarial
- review_round: r01
- verdict: revise
- summary: adversarial review completed
- strengths: adversarial coverage exists
- risks: rollback and monitoring remain important
- requested_changes: tighten rollback and monitoring
- objection: the initial plan may under-test rollback paths
- counterproposal: add a rollback rehearsal and explicit failure thresholds
- rebuttal: the original plan remains viable once rollback checks are added
- residual_risk: operational complexity remains elevated during rollout
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs fails clearly when option value is missing" {
  run "$VALIDATE" "$TEST_PROJECT" --mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"Option --mode requires a value"* ]]
}

@test "validate_docs fails clearly when numeric option is invalid" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "num-01" \
    --task-title "Numeric validation test" \
    --no-init

  run "$VALIDATE" "$TEST_PROJECT" --max-task-lines notanumber
  [ "$status" -ne 0 ]
  [[ "$output" == *"--max-task-lines must be a positive integer"* ]]
}

@test "validate_docs strict fails on invalid task status enum" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "enum-task-01" \
    --task-title "Enum strict test" \
    --task-status "in_progress" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  local task_file="$DOCS_ROOT/task/TASK-enum-task-01.md"
  sed -i.bak 's/^- status:.*$/- status: invalid_status/' "$task_file"
  rm -f "${task_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid task.status value"* ]]
}

@test "validate_docs advisory warns on invalid decision enum values" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "enum-decision-01" \
    --decision-title "Enum advisory test" \
    --selected-option "x" \
    --no-init

  local decision_file="$DOCS_ROOT/decisions/decision-enum-decision-01.md"
  sed -i.bak 's/^- scope_type:.*$/- scope_type: nonsense/' "$decision_file"
  sed -i.bak 's/^- status:.*$/- status: unknown/' "$decision_file"
  rm -f "${decision_file}.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid decision.scope_type value"* ]]
  [[ "$output" == *"invalid decision.status value"* ]]
}

@test "validate_docs secret scan skips default template files" {
  cat > "$DOCS_ROOT/report/LLM-REVIEW-template.md" <<'EOF'
# template
- token: "sk-ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs secret scan catches hyphenated OpenAI key formats" {
  cat > "$DOCS_ROOT/SECURITY-NOTES.md" <<'EOF'
# accidental leak
OPENAI_API_KEY=sk-proj-12345678901234567890
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"potential secret values detected"* ]] || [[ "$output" == *"OPENAI API key assignment"* ]]
  [[ "$output" == *"[REDACTED_SECRET]"* ]]
  [[ "$output" != *"sk-proj-12345678901234567890"* ]]
}

@test "validate_docs secret scan catches Google Gemini API key formats" {
  local google_key
  google_key="$(printf 'AIzaSy%033d' 0)"

  cat > "$DOCS_ROOT/SECURITY-NOTES.md" <<EOF
# accidental leak
GEMINI_API_KEY=$google_key
Bare value: $google_key
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"potential secret values detected"* ]] || [[ "$output" == *"yaml/env-style secret assignments"* ]]
  [[ "$output" == *"[REDACTED_SECRET]"* ]]
  [[ "$output" != *"$google_key"* ]]
}

@test "validate_docs secret scan allows provider variable names without values" {
  cat > "$DOCS_ROOT/SECURITY-NOTES.md" <<'EOF'
# variable names only
Reference variable names such as PROVIDER_API_KEY, DB_PASSWORD, and JWT_SECRET.
Set API_KEY in the environment before running local tools.
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs reports missing rg for secret scanning" {
  run env PATH="/usr/bin:/bin" "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"ripgrep (rg) is required for secret scanning"* ]]
}

# ========== P2: task-index status section movement ==========

@test "validate_docs strict allows missing shadow archive directories" {
  rm -rf "$DOCS_ROOT/shadow/_deprecated" "$DOCS_ROOT/shadow/_obsolete"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs strict fails when root-level legacy shadow doc is not a redirect shim" {
  cat > "$DOCS_ROOT/shadow/legacy-shadow.md" <<'EOF'
# Legacy Shadow

- doc_role: note
- last_updated: 2026-01-01T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"legacy shadow shim"* ]] || [[ "$output" == *"redirect_shim"* ]]
}

@test "validate_docs strict passes with a valid root-level redirect shim" {
  cat > "$DOCS_ROOT/shadow/legacy-shadow.md" <<'EOF'
# Shadow Redirect

- doc_role: redirect_shim
- legacy_path: docs/shadow/legacy-shadow.md
- canonical_path: docs/shadow/apps/app-a/overview.md
- redirects_fact_scope: unit:app-a:overview
- deprecated_since: 2026-04-15
- status: redirected
- edit_policy: read_only
- replacement_reason: moved into topology-first shadow graph
- last_updated: 2026-04-15T00:00:00Z
EOF

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -eq 0 ]
}

@test "validate_docs strict escapes decision filenames in decision-index checks" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "dot.a" \
    --decision-title "Dot decision" \
    --selected-option "Option A" \
    --axis-why "why" \
    --axis-what "what" \
    --axis-how "how" \
    --axis-where "where" \
    --axis-verify "verify" \
    --no-init

  sed -i.bak 's/decision-dot\.a\.md/decision-dotXa.md/' "$DOCS_ROOT/decisions/decision-index.md"
  rm -f "$DOCS_ROOT/decisions/decision-index.md.bak"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"decision index missing row for decision-dot.a.md"* ]]
}

