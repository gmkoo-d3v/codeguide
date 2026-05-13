#!/usr/bin/env bats

# codeguide operational stability tests

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
DOC_GARDEN="$SCRIPTS_DIR/doc_garden.sh"
VALIDATE="$SCRIPTS_DIR/validate_docs.sh"
RUN_CODEGUIDE="$SCRIPTS_DIR/run_codeguide.sh"
RUN_EXTERNAL_REVIEWS="$SCRIPTS_DIR/run_external_plan_reviews.sh"
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

external_handoff_dir() {
  local task_id="$1"
  local plan_version="$2"
  local review_round="$3"

  find "$DOCS_ROOT/orchestration/external-cli" \
    -mindepth 4 \
    -maxdepth 4 \
    -type d \
    -path "*/${task_id}/${plan_version}/${review_round}" \
    | sort \
    | tail -n 1
}

setup() {
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
  local reviewer="$2"
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
- assumptions: mock CLIs return parser-compatible accept responses
- risks: fixture generation failure
- acceptance_signals: response and provenance files are written
- stop_conditions: wrapper completes
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
cat <<EOF
- verdict: accept
- summary: Mock Gemini accepts the bounded review packet.
- strengths: The handoff is constrained.
- risks: This is a deterministic test fixture.
- requested_changes: None.
EOF'
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
cat <<EOF
- verdict: accept
- summary: Mock Claude accepts the bounded review packet.
- strengths: The handoff is constrained.
- risks: This is a deterministic test fixture.
- requested_changes: None.
EOF'
  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
echo "codex should not be called for primary=codex" >&2
exit 99'

  env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "$task_id" \
    --plan-version "$plan_version" \
    --primary-tool "codex" \
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

# ========== P0: Empty value overwrite prevention ==========

@test "upsert_field skips empty values on existing non-empty fields" {
  # Create a decision with a real context value
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-001" \
    --decision-title "Test Decision" \
    --context "Important context here" \
    --rationale "Real rationale" \
    --no-init

  # Verify context was written
  run grep "^- context:" "$DOCS_ROOT/decisions/decision-test-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Important context here"* ]]

  # Run again with empty context — should NOT overwrite
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-001" \
    --decision-title "Test Decision" \
    --context "" \
    --rationale "" \
    --no-init

  # Context should still have the original value
  run grep "^- context:" "$DOCS_ROOT/decisions/decision-test-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Important context here"* ]]

  # Rationale should still have the original value
  run grep "^- rationale:" "$DOCS_ROOT/decisions/decision-test-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Real rationale"* ]]
}

@test "upsert_field allows empty overwrite with --allow-empty-overwrite" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-002" \
    --decision-title "Test Decision" \
    --context "Will be cleared" \
    --no-init

  run grep "^- context:" "$DOCS_ROOT/decisions/decision-test-002.md"
  [[ "$output" == *"Will be cleared"* ]]

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "test-002" \
    --decision-title "Test Decision" \
    --context "" \
    --allow-empty-overwrite \
    --no-init

  # Context should now be empty
  run grep "^- context:" "$DOCS_ROOT/decisions/decision-test-002.md"
  [ "$status" -eq 0 ]
  # Value after "context:" should be empty or just whitespace
  local value
  value="$(echo "$output" | sed 's/^- context:[[:space:]]*//')"
  [ -z "$value" ]
}

@test "axis fields are not overwritten when empty" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "100" \
    --task-title "Axis Test" \
    --axis-why "SOLID principle applied" \
    --axis-where "Service layer" \
    --axis-verify "Unit tests added" \
    --no-init

  run grep "^- axis_why:" "$DOCS_ROOT/task/TASK-100.md"
  [[ "$output" == *"SOLID principle applied"* ]]

  # Run again without axis values — should preserve existing
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "100" \
    --task-title "Axis Test" \
    --no-init

  run grep "^- axis_why:" "$DOCS_ROOT/task/TASK-100.md"
  [[ "$output" == *"SOLID principle applied"* ]]

  run grep "^- axis_where:" "$DOCS_ROOT/task/TASK-100.md"
  [[ "$output" == *"Service layer"* ]]

  run grep "^- axis_verify:" "$DOCS_ROOT/task/TASK-100.md"
  [[ "$output" == *"Unit tests added"* ]]
}

@test "doc_garden preserves backslashes in field values" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "path-001" \
    --decision-title "Path escape test" \
    --context 'Use path C:\new\folder' \
    --no-init

  run cat "$DOCS_ROOT/decisions/decision-path-001.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- context: Use path C:\\new\\folder"* ]]
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

@test "infer_task_id: explicit --task-id has highest priority" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "EXPLICIT-99" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"task_id: EXPLICIT-99"* ]]
}

@test "infer_task_id: branch pattern takes priority over latest task file" {
  # Create a pre-existing task file that would be picked as "latest"
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "old-task-1" \
    --task-title "Old task" \
    --no-init

  # The test runs outside a git repo, so branch inference won't match.
  # But we verify the explicit task-id still works correctly
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "BRANCH-42" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"task_id: BRANCH-42"* ]]
}

@test "init_docs_scaffold uses project docs root directly" {
  run test -d "$DOCS_ROOT/task"
  [ "$status" -eq 0 ]
  run test -d "$DOCS_ROOT/shadow"
  [ "$status" -eq 0 ]
  run test -d "$DOCS_ROOT/orchestration/external-cli"
  [ "$status" -eq 0 ]
  run test ! -d "$DOCS_ROOT/repo"
  [ "$status" -eq 0 ]
  run test ! -d "$DOCS_ROOT/repos"
  [ "$status" -eq 0 ]
}

@test "init_docs_scaffold resolves git subdir to project docs root" {
  local workspace
  local proj
  local app_dir
  local docs_root
  local expected_docs_root
  workspace="$(mktemp -d)"
  proj="$workspace/wall"
  app_dir="$proj/backend"
  mkdir -p "$app_dir"
  git -C "$proj" init >/dev/null 2>&1

  "$INIT_SCAFFOLD" "$app_dir"
  docs_root="$(docs_root_for_project "$app_dir")"
  expected_docs_root="$(cd "$proj" && pwd -P)/docs"

  [ "$docs_root" = "$expected_docs_root" ]
  run test -d "$proj/docs/task"
  [ "$status" -eq 0 ]
  run test -d "$proj/docs/shadow"
  [ "$status" -eq 0 ]
  run test ! -e "$workspace/docs"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "init_docs_scaffold creates shadow graph scaffold files" {
  run test -f "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/shadow/_global.md"
  [ "$status" -eq 0 ]

  run grep "^- doc_role: router" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- read_path: project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- bucket_links: apps/_index.md, services/_index.md, packages/_index.md, infra/_index.md, data/_index.md" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  run grep "^- global_doc: _global.md" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]

  local bucket
  for bucket in apps services packages infra data; do
    run test -f "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- doc_role: bucket_index" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- bucket: $bucket" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run grep "^- no units detected yet" "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    run awk '/^## Units$/{flag=1; next} flag && /^- /{print}' "$DOCS_ROOT/shadow/$bucket/_index.md"
    [ "$status" -eq 0 ]
    [ "$output" = "- no units detected yet" ]
  done
}

@test "init_docs_scaffold creates shadow policy scaffold files" {
  run test -f "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/policy/shadow-rule-registry.md"
  [ "$status" -eq 0 ]

  run grep "^- catalog_id: shadow-validator-catalog" "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  [ "$status" -eq 0 ]
  run grep "^- template_linked_task: TASK-shadow-effect-map-01" "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  [ "$status" -eq 0 ]
  run grep "^- registry_id: shadow-regex-patterns" "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  [ "$status" -eq 0 ]
  run grep "^- template_linked_decision: decision-shadow-regex-standard-01" "$DOCS_ROOT/policy/shadow-regex-patterns.md"
  [ "$status" -eq 0 ]
  run grep "^- registry_id: shadow-rule-registry" "$DOCS_ROOT/policy/shadow-rule-registry.md"
  [ "$status" -eq 0 ]
  run grep "^- template_linked_decisions: decision-shadow-practical-contract-01, decision-shadow-validator-taxonomy-01, decision-shadow-regex-standard-01" "$DOCS_ROOT/policy/shadow-rule-registry.md"
  [ "$status" -eq 0 ]
}

@test "init_docs_scaffold fallback policy templates validate in strict mode" {
  local package_root="$TEST_WORKSPACE/pkg/codeguide"
  local fallback_project="$TEST_WORKSPACE/fallback/repo"

  mkdir -p "$package_root/scripts" "$fallback_project"
  cp "$INIT_SCAFFOLD" "$package_root/scripts/init_docs_scaffold.sh"
  cp "$SCRIPTS_DIR/codeguide_paths.sh" "$package_root/scripts/codeguide_paths.sh"
  cp "$SCRIPTS_DIR/codeguide_paths.py" "$package_root/scripts/codeguide_paths.py"
  chmod +x "$package_root/scripts/init_docs_scaffold.sh"

  "$package_root/scripts/init_docs_scaffold.sh" "$fallback_project"

  run "$VALIDATE" "$fallback_project" --mode strict
  [ "$status" -eq 0 ]
}

@test "shadow_evidence_probe returns unsupported for unknown validator without guessing" {
  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v99"

  [ "$status" -eq 2 ]
  [[ "$output" == *'"status":"unsupported"'* ]]
  [[ "$output" == *'"validator_id":"java.ast.call_match@v99"'* ]]
}

@test "shadow_evidence_probe uses Python AST for real calls and ignores comments or strings" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/app.py" <<'EOF'
# delete_user()
text = "delete_user()"

def handler(service):
    service.save_user()
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "src/app.py" \
    --callee "save_user"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"pass"'* ]]
  [[ "$output" == *'"parser_backed":true'* ]]
  [[ "$output" == *'"validator_result":"matched"'* ]]
  [[ "$output" == *'"source_hash":"sha256:'* ]]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "src/app.py" \
    --callee "delete_user"

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"fail"'* ]]
  [[ "$output" == *'"validator_result":"not_found"'* ]]
}

@test "shadow_evidence_probe rejects Python AST primary evidence from test paths" {
  mkdir -p "$TEST_PROJECT/tests"
  cat > "$TEST_PROJECT/tests/test_app.py" <<'EOF'
def test_handler():
    save_user()
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "tests/test_app.py" \
    --callee "save_user"

  [ "$status" -eq 64 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"validator_id":"py.ast.call_match@v1"'* ]]
  [[ "$output" == *"primary validator"* ]]
}

@test "shadow_evidence_probe uses Python AST for real decorators" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/routes.py" <<'EOF'
class Router:
    def post(self, path):
        def wrapper(fn):
            return fn
        return wrapper

router = Router()

@router.post("/users")
def create_user():
    return None
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.decorator.match@v1" \
    --source-file "src/routes.py" \
    --decorator "router.post"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"pass"'* ]]
  [[ "$output" == *'"parser_backed":true'* ]]
}

@test "shadow_evidence_probe regex fallback emits fallback_result only" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

class UserService {
  void update(User user) {
    // auditRepository.save(user);
    String sample = "auditRepository.save(user)";
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "java.regex.repository_save_call@v1" \
    --source-file "src/main/java/example/UserService.java"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"pass"'* ]]
  [[ "$output" == *'"probe_status":"pass"'* ]]
  [[ "$output" == *'"fact_status":"candidate_only"'* ]]
  [[ "$output" == *'"fallback_result":"matched"'* ]]
  [[ "$output" == *'"evidence_field":"fallback_result"'* ]]
  [[ "$output" == *'"source_hash":"sha256:'* ]]
  [[ "$output" != *'"validator_result"'* ]]
}

@test "shadow_evidence_probe Java primary source_probe is scoped and non-parser-backed" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

class UserService {
  void update(User user) {
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "jpa.repository.save@v1" \
    --source-file "src/main/java/example/UserService.java"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"pass"'* ]]
  [[ "$output" == *'"probe_status":"pass"'* ]]
  [[ "$output" == *'"fact_status":"candidate_only"'* ]]
  [[ "$output" == *'"validator_kind":"source_probe"'* ]]
  [[ "$output" == *'"parser_backed":false'* ]]
  [[ "$output" == *'"promotion_limit":"medium"'* ]]
  [[ "$output" == *'"source_hash":"sha256:'* ]]
}

@test "shadow_evidence_probe Java parser-backed call matcher ignores comments and strings" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

class UserService {
  void update(User user) {
    // userRepository.delete(user);
    String text = "userRepository.delete(user)";
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "save" \
    --receiver "userRepository"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"pass"'* ]]
  [[ "$output" == *'"probe_status":"pass"'* ]]
  [[ "$output" == *'"fact_status":"deterministic_evidence"'* ]]
  [[ "$output" == *'"validator_kind":"java_token_parser"'* ]]
  [[ "$output" == *'"parser_backed":true'* ]]
  [[ "$output" == *'"matched_symbol":"userRepository.save"'* ]]
  [[ "$output" == *'"source_hash":"sha256:'* ]]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "delete" \
    --receiver "userRepository"

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"fail"'* ]]
  [[ "$output" == *'"validator_result":"not_found"'* ]]
}

@test "shadow_evidence_probe Java parser-backed call matcher rejects declarations and test paths" {
  mkdir -p "$TEST_PROJECT/src/main/java/example" "$TEST_PROJECT/src/test/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/UserService.java" <<'EOF'
package example;

@interface UserAnnotation {
  String value() default "";
}

interface UserPort {
  User save(User user);
}

abstract class AbstractUserService {
  public abstract User save(User user);
}

class UserService {
  UserService(User user) {}
  void save(User user) {}
  void update(User user) {
    save(user);
  }
}
EOF
  cat > "$TEST_PROJECT/src/test/java/example/UserServiceTest.java" <<'EOF'
package example;

class UserServiceTest {
  void update(User user) {
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "save"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"pass"'* ]]
  [[ "$output" == *'"matched_symbol":"save"'* ]]
  [[ "$output" == *'"source_ref":"src/main/java/example/UserService.java:15"'* ]]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "UserService"

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"fail"'* ]]
  [[ "$output" == *'"validator_result":"not_found"'* ]]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "value"

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"fail"'* ]]
  [[ "$output" == *'"validator_result":"not_found"'* ]]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/main/java/example/UserService.java" \
    --callee "save" \
    --receiver "missingReceiver"

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"fail"'* ]]
  [[ "$output" == *'"validator_result":"not_found"'* ]]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "java.ast.call_match@v1" \
    --source-file "src/test/java/example/UserServiceTest.java" \
    --callee "save" \
    --receiver "userRepository"

  [ "$status" -eq 64 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *"outside allowed_paths"* ]]
}

@test "shadow_evidence_probe regex fallback ignores comments and strings" {
  mkdir -p "$TEST_PROJECT/src/main/java/example"
  cat > "$TEST_PROJECT/src/main/java/example/CommentOnly.java" <<'EOF'
package example;

class CommentOnly {
  void update() {
    // userRepository.save(user);
    String sample = "userRepository.save(user)";
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "java.regex.repository_save_call@v1" \
    --source-file "src/main/java/example/CommentOnly.java"

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"fail"'* ]]
  [[ "$output" == *'"fallback_result":"not_found"'* ]]
}

@test "shadow_evidence_probe rejects fallback evidence from excluded paths" {
  mkdir -p "$TEST_PROJECT/src/test/java/example"
  cat > "$TEST_PROJECT/src/test/java/example/UserServiceTest.java" <<'EOF'
class UserServiceTest {
  void testSave() {
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --fallback-pattern-id "java.regex.repository_save_call@v1" \
    --source-file "src/test/java/example/UserServiceTest.java"

  [ "$status" -eq 64 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *"outside allowed_paths"* || "$output" == *"excluded"* ]]
}

@test "shadow_evidence_probe rejects primary source_probe evidence from excluded paths" {
  mkdir -p "$TEST_PROJECT/src/test/java/example"
  cat > "$TEST_PROJECT/src/test/java/example/UserServiceTest.java" <<'EOF'
class UserServiceTest {
  void testSave() {
    userRepository.save(user);
  }
}
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "jpa.repository.save@v1" \
    --source-file "src/test/java/example/UserServiceTest.java"

  [ "$status" -eq 64 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"validator_id":"jpa.repository.save@v1"'* ]]
  [[ "$output" == *"primary validator"* ]]
}

@test "shadow_evidence_probe runtime trace requires exact explicit event line" {
  mkdir -p "$TEST_PROJECT/logs"
  cat > "$TEST_PROJECT/logs/runtime.trace" <<'EOF'
event=user.update started
event=user.cache.evict userId=42
EOF

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime.trace" \
    --trace-event "event=user.cache.evict userId=42"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"pass"'* ]]
  [[ "$output" == *'"probe_status":"pass"'* ]]
  [[ "$output" == *'"fact_status":"deterministic_evidence"'* ]]
  [[ "$output" == *'"evidence_type":"runtime_trace"'* ]]
  [[ "$output" == *'"artifact_hash":"sha256:'* ]]
  [[ "$output" == *'"trace_ref":"logs/runtime.trace:2"'* ]]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "any.runtime.trace@v1" \
    --trace-file "logs/runtime.trace" \
    --trace-event "user.cache.evict"

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"fail"'* ]]
}

@test "shadow_evidence_probe rejects traversal and does not write shadow docs" {
  mkdir -p "$TEST_PROJECT/src"
  cat > "$TEST_PROJECT/src/app.py" <<'EOF'
def handler():
    save_user()
EOF
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-before.txt"

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "src/app.py" \
    --callee "save_user"

  [ "$status" -eq 0 ]
  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-before.txt" "$TEST_WORKSPACE/shadow-after.txt"
  [ "$status" -eq 0 ]

  run python3 "$SHADOW_PROBE" \
    --project-root "$TEST_PROJECT" \
    --validator-id "py.ast.call_match@v1" \
    --source-file "../outside.py" \
    --callee "save_user"

  [ "$status" -eq 64 ]
  [[ "$output" == *"traversal"* ]]
  [[ "$output" == *'"validator_id":"py.ast.call_match@v1"'* ]]
}

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
  local good_runtime_record_file="$TEST_WORKSPACE/good-runtime-record.json"
  local code_probe_file="$TEST_WORKSPACE/code-probe.json"
  local runtime_probe_file="$TEST_WORKSPACE/runtime-probe.json"
  local runtime_decision_file="$TEST_WORKSPACE/runtime-decision.json"
  local draft_file="$TEST_WORKSPACE/draft.md"
  local source_hash
  local runtime_hash
  local code_probe_hash
  local runtime_probe_hash
  local runtime_statement="Cache eviction is backed by a runtime trace artifact."
  local runtime_statement_hash

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
  source_hash="$(sha256_file_ref "$TEST_PROJECT/src/app.py")"
  runtime_hash="$(sha256_file_ref "$TEST_PROJECT/logs/runtime.trace")"
  cat > "$code_probe_file" <<EOF
{"status":"pass","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  cat > "$runtime_probe_file" <<EOF
{"status":"pass","validator_id":"any.runtime.trace@v1","evidence_type":"runtime_trace","validator_result":"matched","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","validator_kind":"runtime_trace","parser_backed":false,"promotion_limit":"high","writes_shadow_docs":false}
EOF
  code_probe_hash="$(sha256_file_ref "$code_probe_file")"
  runtime_probe_hash="$(sha256_file_ref "$runtime_probe_file")"
  runtime_statement_hash="$(sha256_text_ref "$runtime_statement")"

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
{"user_decision":{"id":"UD-013","decision_type":"final_shadow_apply","answer":"yes","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":["$candidate_id","SE-user-004","SE-user-005","SE-user-006","SE-user-007","SE-user-008"],"rationale":"Approve evaluating deterministic evidence metadata.","source_refs":["TASK-shadow-effect-map-01"]}}
EOF
  cat > "$runtime_decision_file" <<EOF
{"user_decision":{"id":"UD-runtime-013","decision_type":"runtime_scenario_fit","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-008","effect_type":"cache_evict","statement_hash":"$runtime_statement_hash","anchor_file":"logs/runtime.trace","anchor_line":"2","anchor_symbol":"event=user.cache.evict","trace_ref":"logs/runtime.trace:2","scenario_ref":"scenario:user-update-cache"}],"rationale":"The trace scenario matches the user update cache-evict scenario.","source_refs":["logs/runtime.trace:2","scenario:user-update-cache"]}}
EOF
  cat > "$code_record_file" <<EOF
{"record_id":"SE-user-004","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Repository save is claimed by deterministic code evidence.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash"}}
EOF
  cat > "$runtime_record_file" <<EOF
{"record_id":"SE-user-005","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Cache eviction is claimed by deterministic runtime evidence.","anchor":{"file":"src/UserService.java","symbol":"UserCache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","scenario_ref":"scenario:user-update-cache"}}
EOF
  cat > "$bad_runtime_record_file" <<EOF
{"record_id":"SE-user-007","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Cache eviction has malformed runtime hash evidence.","anchor":{"file":"src/UserService.java","symbol":"UserCache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","trace_ref":"logs/runtime.trace:2","artifact_hash":"sha256:x","scenario_ref":"scenario:user-update-cache"}}
EOF
  cat > "$good_code_record_file" <<EOF
{"record_id":"SE-user-006","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Repository save is backed by parser evidence.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:6","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$good_runtime_record_file" <<EOF
{"record_id":"SE-user-008","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":2,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:2","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","user_decision_ref":"UD-runtime-013","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
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
  [[ "$output" == *'"action":"complete_runtime_scenario_fit_args"'* ]]
  [[ "$output" != *"--decision-type runtime_scenario_fit"* ]]

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
  [[ "$output" != *"choose_supported_fact_decision_type"* ]]

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
{"record_id":"SE-java-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Java repository save is backed by parser evidence.","anchor":{"file":"src/main/java/example/UserService.java","line":$anchor_line,"symbol":"userRepository.save"},"evidence":{"type":"deterministic_code","ref":"java.ast.call_match@v1","rule_id":"repo.write","validator_kind":"java_token_parser","parser_backed":true,"validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"save","receiver":"userRepository"}}}
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
  [[ "$output" == *"evidence_source_hash: $source_hash"* ]]

  cat > "$record_file" <<EOF
{"record_id":"SE-java-001","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Bare Java parser evidence must not confirm without receiver binding.","anchor":{"file":"src/main/java/example/UserService.java","line":$anchor_line,"symbol":"save"},"evidence":{"type":"deterministic_code","ref":"java.ast.call_match@v1","rule_id":"repo.write","validator_kind":"java_token_parser","parser_backed":true,"validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"save"}}}
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
{"record_id":"SE-java-002","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"Java confirmed evidence requires receiver even outside repo.write.","anchor":{"file":"src/main/java/example/UserService.java","line":$anchor_line,"symbol":"save"},"evidence":{"type":"deterministic_code","ref":"java.ast.call_match@v1","rule_id":"java.bare_call","validator_kind":"java_token_parser","parser_backed":true,"validator_result":"matched","source_ref":"$source_ref","source_hash":"$source_hash","probe_result_ref":"$probe_result_file","probe_result_hash":"$probe_hash","probe_args":{"callee":"save"}}}
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
  local runtime_hash
  local code_probe_file="$TEST_WORKSPACE/code-probe.json"
  local code_probe_hash
  local runtime_probe_hash
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
  runtime_hash="$(sha256_file_ref "$trace_file")"
  cat > "$code_probe_file" <<EOF
{"status":"pass","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  cat > "$wrong_code_probe_file" <<EOF
{"status":"pass","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/other.py:1","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
EOF
  cat > "$runtime_probe_file" <<EOF
{"status":"pass","validator_id":"any.runtime.trace@v1","evidence_type":"runtime_trace","validator_result":"matched","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","validator_kind":"runtime_trace","parser_backed":false,"promotion_limit":"high","writes_shadow_docs":false}
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
{"user_decision":{"id":"UD-runtime-one-sided","decision_type":"runtime_scenario_fit","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-030","effect_type":"cache_evict","statement_hash":"$runtime_statement_hash","anchor_file":"logs/runtime.trace","anchor_line":"1","anchor_symbol":"event=user.cache.evict","trace_ref":"logs/runtime.trace:1","scenario_ref":"scenario:user-update-cache"}],"rationale":"This cites only the trace, not the scenario.","source_refs":["logs/runtime.trace:1"]}}
EOF
  cat > "$runtime_mismatch_decision_file" <<EOF
{"user_decision":{"id":"UD-runtime-mismatch","decision_type":"runtime_scenario_fit","answer":"confirmed","decided_by":"gm","decided_at":"2026-05-02","expires_at":"2026-05-09","applies_to":[{"record_id":"SE-user-031","effect_type":"cache_evict","statement_hash":"$runtime_mismatch_statement_hash","anchor_file":"logs/runtime.trace","anchor_line":"1","anchor_symbol":"event=user.cache.evict","trace_ref":"logs/runtime.trace:2","scenario_ref":"scenario:user-update-cache"}],"rationale":"This binds the right record but a different trace line.","source_refs":["logs/runtime.trace:1","scenario:user-update-cache"]}}
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
{"record_id":"SE-user-019","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Runtime evidence must use a runtime trace validator.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.command.output@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$unimplemented_record" <<EOF
{"record_id":"SE-user-020","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"api_route","statement":"Documented-only Express route validator cannot be forged as implemented.","anchor":{"file":"src/main/java/example/UserService.java","symbol":"app.get"},"evidence":{"type":"deterministic_code","ref":"express.route@v1","rule_id":"http.route","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/main/java/example/UserService.java:5","source_hash":"$java_source_hash","probe_args":{"callee":"get","receiver":"app"}}}
EOF
  cat > "$stale_runtime_record" <<EOF
{"record_id":"SE-user-023","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Stale runtime hash must not validate.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","scenario_ref":"scenario:user-update-cache","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$forged_code_record" <<EOF
{"record_id":"SE-user-024","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Current source hash is not enough without matching probe result.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$wrong_effect_record" <<EOF
{"record_id":"SE-user-027","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Repo write rule must not confirm cache eviction.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$wrong_symbol_record" <<EOF
{"record_id":"SE-user-028","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Anchor symbol must match deterministic probe args.","anchor":{"file":"src/app.py","symbol":"repository.delete"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$path_only_source_record" <<EOF
{"record_id":"SE-user-029","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Path-only source refs are accepted when the probe rerun binds the same file.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$runtime_scenario_record" <<EOF
{"record_id":"SE-user-025","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Scenario ref alone is not fact evidence.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_bad_decision_record" <<EOF
{"record_id":"SE-user-026","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Negative or unrelated decisions cannot confirm runtime scenario fit.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","user_decision_ref":"UD-runtime-bad","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_one_sided_record" <<EOF
{"record_id":"SE-user-030","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_statement","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","user_decision_ref":"UD-runtime-one-sided","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_mismatch_record" <<EOF
{"record_id":"SE-user-031","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"$runtime_mismatch_statement","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","user_decision_ref":"UD-runtime-mismatch","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_wrong_effect_record" <<EOF
{"record_id":"SE-user-034","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"external_call","statement":"Runtime cache trace must not confirm arbitrary external call.","anchor":{"file":"logs/runtime.trace","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","user_decision_ref":"UD-runtime-one-sided","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$runtime_wrong_anchor_record" <<EOF
{"record_id":"SE-user-035","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"cache_evict","statement":"Runtime trace must not confirm unrelated anchor file.","anchor":{"file":"src/app.py","line":1,"symbol":"event=user.cache.evict"},"evidence":{"type":"deterministic_runtime","ref":"any.runtime.trace@v1","rule_id":"cache.evict","trace_ref":"logs/runtime.trace:1","artifact_hash":"$runtime_hash","scenario_ref":"scenario:user-update-cache","user_decision_ref":"UD-runtime-one-sided","probe_result_ref":"$runtime_probe_file","probe_result_hash":"$runtime_probe_hash","probe_args":{"trace_event":"event=user.cache.evict userId=42"}}}
EOF
  cat > "$human_mismatch_record" <<EOF
{"record_id":"SE-user-036","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"effect_intent","statement":"$human_mismatch_statement","anchor":{"file":"docs/task/TASK-shadow-effect-map-01.md","symbol":"user decision"},"evidence":{"type":"user_decision","ref":"UD-human-mismatch"},"source_refs":["TASK-shadow-effect-map-01"]}
EOF
  cat > "$same_file_wrong_line_record" <<EOF
{"record_id":"SE-user-032","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Line-qualified source refs must bind the exact matched node.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"repo.write","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:999","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
EOF
  cat > "$custom_rule_record" <<EOF
{"record_id":"SE-user-033","record_type":"effect_map_entry","candidate_id":"$candidate_id","lifecycle":"confirmed","effect_type":"db_write","statement":"Registered rules without effect type mapping fail closed.","anchor":{"file":"src/app.py","symbol":"repository.save"},"evidence":{"type":"deterministic_code","ref":"py.ast.call_match@v1","rule_id":"custom.missing_effect","validator_kind":"ast","parser_backed":true,"validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","probe_result_ref":"$code_probe_file","probe_result_hash":"$code_probe_hash","probe_args":{"callee":"save","receiver":"repository"}}}
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

@test "validate_docs strict accepts canonical probe coverage for valid effect_map evidence" {
  local effect_file="$DOCS_ROOT/shadow/packages/codeguide/effects.md"
  local source_file="$TEST_PROJECT/src/app.py"
  local probe_file="$TEST_PROJECT/probe-results/code-probe.json"
  local source_hash
  local probe_hash

  mkdir -p "$(dirname "$effect_file")" "$(dirname "$source_file")" "$(dirname "$probe_file")"
  cat > "$source_file" <<'EOF'
def handler(repository, user):
    repository.save(user)
EOF
  source_hash="$(sha256_file_ref "$source_file")"
  cat > "$probe_file" <<EOF
{"status":"pass","validator_id":"py.ast.call_match@v1","evidence_type":"code_call","validator_result":"matched","source_ref":"src/app.py:2","source_hash":"$source_hash","validator_kind":"ast","parser_backed":true,"promotion_limit":"high","writes_shadow_docs":false,"matched_symbol":"repository.save"}
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

@test "shadow_policy_loader reports adapter ids and catalog parity" {
  run python3 "$SHADOW_POLICY_LOADER" --adapter-module "$SHADOW_PROBE" --print-adapter-ids
  [ "$status" -eq 0 ]
  [[ "$output" == *"py.ast.call_match@v1"* ]]
  [[ "$output" == *"any.runtime.trace@v1"* ]]

  run python3 "$SHADOW_POLICY_LOADER" --policy-dir "$DOCS_ROOT/policy" --adapter-module "$SHADOW_PROBE" --check-parity
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]

  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, js.ast.call_match\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"
  run python3 "$SHADOW_POLICY_LOADER" --policy-dir "$DOCS_ROOT/policy" --adapter-module "$SHADOW_PROBE" --check-parity
  [ "$status" -ne 0 ]
  [[ "$output" == *"implemented_primary_v1 id must be implemented by shadow_evidence_probe.py"* ]]
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
  perl -0pi -e 's/(implemented_primary_v1: \[[^\]]*any\.runtime\.trace\@v1)/$1, js.ast.call_match\@v1/' "$DOCS_ROOT/policy/shadow-validator-catalog.md"

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
    --review-route "external_gemini_claude" \
    --record-count 2 \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"external Gemini/Claude review requires explicit user request"* ]]
  [[ "$output" == *"batch apply is disabled in Phase 0"* ]]
  [[ "$output" == *'"writes_shadow_docs":false'* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_gemini_claude" \
    --external-review-requested \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"external Gemini/Claude review requires concrete approval_ref"* ]]
  [[ "$output" == *"external Gemini/Claude review requires approved_next_step"* ]]
  [[ "$output" == *"external Gemini/Claude review requires main-thread recorded_by"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_gemini_claude" \
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
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --blocked-review "external_gemini_claude" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"blocked"'* ]]
  [[ "$output" == *"required review route is blocked: external_gemini_claude"* ]]
  [[ "$output" == *"stop without substituting another reviewer route"* ]]
  [[ "$output" == *"sub-agent acceptance cannot substitute for blocked external Gemini/Claude review"* ]]
  [[ "$output" == *'"combined_review_close_gate":"all_required_routes_must_complete"'* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"required review route is missing: external_gemini_claude"* ]]
}

@test "shadow_v2_gate_skeleton requires durable accepted external review artifact before close completion" {
  local stub_artifact="$TEST_WORKSPACE/external-stub-review.md"
  local empty_dir="$DOCS_ROOT/orchestration/external-cli/May13_2026/shadow-v2-close/v1.0/r-empty"
  local blocked_dir="$DOCS_ROOT/orchestration/external-cli/May13_2026/shadow-v2-close/v1.0/r-blocked"
  local no_manifest_dir="$DOCS_ROOT/orchestration/external-cli/May13_2026/shadow-v2-close/v1.0/r-no-manifest"
  local thin_dir="$DOCS_ROOT/orchestration/external-cli/May13_2026/shadow-v2-close/v1.0/r-thin"
  local empty_artifact="$empty_dir/gemini.response.md"
  local blocked_artifact="$blocked_dir/gemini.response.md"
  local no_manifest_artifact="$no_manifest_dir/gemini.response.md"
  local thin_artifact="$thin_dir/gemini.response.md"
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
verdict: block
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
verdict: block
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
  accepted_artifact="$(create_mock_external_review_artifact "shadow-v2-close-accepted" "gemini")"
  [ -n "$accepted_artifact" ]
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
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"completed external Gemini/Claude review requires a durable response artifact"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --completed-review-artifact "external_gemini_claude=$stub_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"completed external Gemini/Claude review artifact must be under docs/orchestration/external-cli"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --completed-review-artifact "external_gemini_claude=$no_manifest_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"completed external Gemini/Claude review artifact requires provenance manifest"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --completed-review-artifact "external_gemini_claude=$thin_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"completed external Gemini/Claude review artifact requires parser-compatible field summary"* ]]
  [[ "$output" == *"completed external Gemini/Claude review artifact requires parser-compatible field requested_changes"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --completed-review-artifact "external_gemini_claude=$empty_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"completed review artifact must be non-empty for route external_gemini_claude"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --completed-review-artifact "external_gemini_claude=$blocked_artifact" \
    --print-contract

  [ "$status" -eq 1 ]
  [[ "$output" == *"completed external Gemini/Claude review artifact verdict must be accept"* ]]
  [[ "$output" == *"completed external Gemini/Claude review artifact contains blocked/error/no-response marker"* ]]

  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --completed-review-artifact "external_gemini_claude=$accepted_artifact" \
    --print-contract

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"sha256":"sha256:'* ]]
  [[ "$output" == *'"evaluator":"gemini"'* ]]
  [[ "$output" == *'"request_file":'* ]]
  [[ "$output" == *'"command_response_path":'* ]]
  [[ "$output" == *'"provenance_file":'* ]]
}

@test "shadow_v2_gate_skeleton ignores optional blocked external close route" {
  run python3 "$SHADOW_V2_SKELETON" \
    --project-root "$TEST_PROJECT" \
    --close-required-review "codex_subagent_md_handoff" \
    --completed-review "codex_subagent_md_handoff" \
    --blocked-review "external_gemini_claude" \
    --print-contract

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" != *"sub-agent acceptance cannot substitute for blocked external Gemini/Claude review"* ]]
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
  [[ "$output" == *"source_kind: evidence_candidate"* ]]
  [[ "$output" == *"decision_type: classification_or_evidence_gap"* ]]
  [[ "$output" == *"recommended_default_status: unknown"* ]]
  [[ "$output" == *"command_ready: false"* ]]
  [[ "$output" == *"Does the syntactic source probe"* ]]

  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-decision-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-v2-decision-before.txt" "$TEST_WORKSPACE/shadow-v2-decision-after.txt"
  [ "$status" -eq 0 ]
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
      "command": ["python3", "shadow_user_decision_wrapper.py", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01"],
      "command_text": "python3 shadow_user_decision_wrapper.py --decision-type business_intent --answer confirmed",
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
  cat > "$forged_writer_result" <<'EOF'
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
      "command": ["python3", "shadow_user_decision_wrapper.py", "--decision-type", "final_shadow_apply"],
      "command_text": "python3 shadow_user_decision_wrapper.py --decision-type final_shadow_apply"
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

@test "shadow_v2_user_decision_assistant renders command text only from validated argv" {
  local misleading_writer_result="$TEST_WORKSPACE/misleading-command-text-result.json"
  cat > "$misleading_writer_result" <<'EOF'
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "safe argv with hostile command_text",
      "command": ["python3", "shadow_user_decision_wrapper.py", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01"],
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
  cat > "$duplicate_flag_result" <<'EOF'
{
  "status": "blocked",
  "writes_shadow_docs": false,
  "auto_promotes_facts": false,
  "next_actions": [
    {
      "action": "create_evidence_decision",
      "requires_user_input": true,
      "reason": "duplicate decision type",
      "command": ["python3", "shadow_user_decision_wrapper.py", "--project-root", "/repo", "--output", "<evidence-decision.json>", "--decision-id", "<decision-id>", "--decision-type", "business_intent", "--answer", "confirmed", "--decided-by", "<reviewer>", "--decided-at", "<YYYY-MM-DD>", "--expires-at", "<YYYY-MM-DD>", "--rationale", "<why this fact is true>", "--source-ref", "TASK-shadow-effect-map-01", "--decision-type", "final_shadow_apply"]
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
  local writer_result="$TEST_WORKSPACE/review-writer-result.json"
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
  [[ "$output" == *"review_route: codex_subagent_md_handoff"* ]]
  [[ "$output" == *"privacy_boundary: packet_only_no_workspace_dump"* ]]
  [[ "$output" == *"review_provenance: internal_md_handoff"* ]]
  [[ "$output" == *"unsupported_by_packet: none"* ]]
  [[ "$output" == *"kind: writer_result"* ]]
  [[ "$output" == *"TASK-shadow-effect-map-01"* ]]
  [[ "$output" == *"src/UserService.java:6"* ]]
  [[ "$output" == *"- writes_shadow_docs: false"* ]]

  find "$DOCS_ROOT/shadow" -type f | sort > "$TEST_WORKSPACE/shadow-v2-review-after.txt"
  run cmp "$TEST_WORKSPACE/shadow-v2-review-before.txt" "$TEST_WORKSPACE/shadow-v2-review-after.txt"
  [ "$status" -eq 0 ]
}

@test "shadow_v2_review_packet_generator blocks external route unless requested" {
  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_gemini_claude" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"external Gemini/Claude review requires explicit user request"* ]]
  [[ "$output" == *"external_review_user_request"* ]]
  [[ "$output" == *"external_review_approval_ref"* ]]
  [[ "$output" == *"external_review_approved_next_step"* ]]
  [[ "$output" == *"external_review_recorded_by"* ]]
  [[ "$output" == *'"review_provenance": "external_review_missing_user_request"'* ]]
  [[ "$output" != *'"review_provenance": "external_user_approved"'* ]]

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_gemini_claude" \
    --external-review-requested \
    --source-ref "TASK-shadow-effect-map-01" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"review_provenance": "external_review_missing_approval_provenance"'* ]]
  [[ "$output" == *"external Gemini/Claude review requires concrete approval_ref"* ]]

  run python3 "$SHADOW_V2_REVIEW_PACKET" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_gemini_claude" \
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
    --review-route "external_gemini_claude" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"external Gemini/Claude review requires explicit user request"* ]]
  [[ "$output" == *'"executes_commands": false'* ]]

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_gemini_claude" \
    --external-review-requested \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *"external Gemini/Claude review requires concrete approval_ref"* ]]
  [[ "$output" == *"external Gemini/Claude review requires approved_next_step"* ]]
  [[ "$output" == *"external Gemini/Claude review requires main-thread recorded_by"* ]]

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --review-route "external_gemini_claude" \
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
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --blocked-review "external_gemini_claude" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"close_review_gate"* ]]
  [[ "$output" == *"required review route is blocked: external_gemini_claude"* ]]
  [[ "$output" == *"sub-agent acceptance cannot substitute for blocked external Gemini/Claude review"* ]]
  [[ "$output" == *'"executes_commands": false'* ]]
}

@test "shadow_v2_pipeline_wrapper requires external close artifact provenance" {
  local accepted_artifact
  accepted_artifact="$(create_mock_external_review_artifact "shadow-v2-pipeline-accepted" "claude")"
  [ -n "$accepted_artifact" ]
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
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --format json

  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "blocked"'* ]]
  [[ "$output" == *"completed external Gemini/Claude review requires a durable response artifact"* ]]
  [[ "$output" == *'"executes_commands": false'* ]]

  run python3 "$SHADOW_V2_PIPELINE" \
    --project-root "$TEST_PROJECT" \
    --external-review-requested \
    --external-review-approval-ref "user-approval-001" \
    --external-review-approved-next-step "close shadow v2 external review gate" \
    --external-review-recorded-by "main-thread-supervising-lead-architect" \
    --close-required-review "codex_subagent_md_handoff" \
    --close-required-review "external_gemini_claude" \
    --completed-review "codex_subagent_md_handoff" \
    --completed-review "external_gemini_claude" \
    --completed-review-artifact "external_gemini_claude=$accepted_artifact" \
    --format json

  [ "$status" -eq 0 ]
  [[ "$output" == *'"close_review_gate"'* ]]
  [[ "$output" == *'"status": "satisfied"'* ]]
  [[ "$output" == *'"completed_review_artifacts"'* ]]
  [[ "$output" == *'"sha256": "sha256:'* ]]
  [[ "$output" != *"completed external Gemini/Claude review requires a durable response artifact"* ]]
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

@test "run_codeguide bootstraps orchestration doc for active task" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "orch-01" --mode advisory
  [ "$status" -eq 0 ]

  local orch_file="$DOCS_ROOT/orchestration/ORCH-orch-01.md"
  run test -f "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- execution_mode: solo" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- supervisor_agent: main-thread-supervising-lead-architect" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- delegation_note: Solo execution selected; no sub-agent or external review requested." "$orch_file"
  [ "$status" -eq 0 ]
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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

  local orch_file="$DOCS_ROOT/orchestration/ORCH-orch-preflight-01.md"
  perl -0pi -e 's/^- risk_preflight_status: pass$/- risk_preflight_status: approval_required/m; s/^- approval_required: false$/- approval_required: true/m; s/^- approval_ref:.*$/- approval_ref: user-approval-pending-001/m; s/^- approved_next_step:.*$/- approved_next_step: await user approval/m' "$orch_file"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"orchestration risk preflight must be pass or approved"* ]]
}

@test "doc_garden records blocked delegation when preflight still needs approval" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-approval-stop-01" \
    --task-title "Approval stop test" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approval_required" \
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  [ "$status" -eq 0 ]
  local orch_file="$DOCS_ROOT/orchestration/ORCH-orch-approval-stop-01.md"
  run grep "^- delegation_status: blocked" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "^- approval_required: true" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "Delegation stopped before agent or external work" "$orch_file"
  [ "$status" -eq 0 ]
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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

  local orch_file="$DOCS_ROOT/orchestration/ORCH-orch-approved-01.md"
  perl -0pi -e 's/^- approval_required: true$/- approval_required: false/m' "$orch_file"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"risk_preflight_status=approved requires approval_required=true"* ]]
}

@test "approved preflight rejects placeholder approval metadata before recording or external review" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-approved-placeholder-01" \
    --task-title "Approved placeholder test" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "not_required" \
    --approved-next-step "run delegated review" \
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
    --no-init

  [ "$status" -ne 0 ]
  [[ "$output" == *"Concrete --approval-ref"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/ORCH-orch-approved-placeholder-01.md"
  [ "$status" -eq 0 ]

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
    --task-id "run-approved-placeholder-01" \
    --mode advisory \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-001" \
    --approved-next-step "pending_user_approval"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Concrete --approval-ref"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/ORCH-run-approved-placeholder-01.md"
  [ "$status" -eq 0 ]

  local plan_file="$DOCS_ROOT/plan/PLAN-ext-approved-placeholder-v1.0.md"
  cat > "$plan_file" <<'EOF'
# PLAN-ext-approved-placeholder-v1.0

- task_id: ext-approved-placeholder
- plan_version: v1.0
- objective: validate placeholder approval is rejected before external review
- scope: external review safety gate
- assumptions: placeholder approval metadata must not invoke reviewers
- risks: unauthorized external review
- acceptance_signals: wrapper blocks before reviewer invocation
- stop_conditions: placeholder approval rejected
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local mock_bin="$TEST_WORKSPACE/mock-bin-approved-placeholder"
  mkdir -p "$mock_bin"
  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/gemini-approved-placeholder-called"
exit 99'
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-approved-placeholder-called"
exit 99'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-approved-placeholder" \
    --plan-version "v1.0" \
    --primary-tool "codex" \
    --review-round "r01" \
    --risk-preflight-status "approved" \
    --approval-ref "pending_user_approval" \
    --approved-next-step "run external reviewers"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Concrete --approval-ref"* ]]
  run test ! -e "$TEST_WORKSPACE/gemini-approved-placeholder-called"
  [ "$status" -eq 0 ]
  run test ! -e "$TEST_WORKSPACE/claude-approved-placeholder-called"
  [ "$status" -eq 0 ]
}

@test "doc_garden rejects external_cli review with pass preflight" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-external-pass-01" \
    --task-title "External pass should block" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "codex" \
    --review-mode "external_cli" \
    --planner-agents "planner-1" \
    --reviewer-agents "external-cli:gemini" \
    --owned-scopes "planner:docs/plan; reviewer:docs/report" \
    --no-init

  [ "$status" -ne 0 ]
  [[ "$output" == *"External CLI review requires --risk-preflight-status approved"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/ORCH-orch-external-pass-01.md"
  [ "$status" -eq 0 ]
}

@test "validate_docs strict rejects evaluator identity recorder case-insensitively" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "orch-recorder-01" \
    --task-title "Recorder identity test" \
    --axis-why "why" \
    --axis-where "where" \
    --axis-verify "verify" \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "pass" \
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
    --planner-agents "planner-1" \
    --reviewer-agents "reviewer-1" \
    --implementation-agents "coder-1" \
    --validation-agents "validator-1" \
    --owned-scopes "planner:docs/plan; coder:src/app" \
    --no-init

  cat > "$DOCS_ROOT/plan/PLAN-orch-recorder-01-v1.0.md" <<'EOF'
# PLAN-orch-recorder-01-v1.0

- task_id: orch-recorder-01
- plan_version: v1.0
- objective: validate recorder identity normalization
- scope: docs validation
- assumptions: none
- risks: low
- acceptance_signals: strict validation rejects evaluator identity regardless of case
- stop_conditions: fixed
- owner: test
- last_updated: 2026-01-01T00:00:00Z
EOF

  local orch_file="$DOCS_ROOT/orchestration/ORCH-orch-recorder-01.md"
  perl -0pi -e 's/^- risk_preflight_recorded_by: .+$/- risk_preflight_recorded_by: Gemini/m' "$orch_file"

  run "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"risk_preflight_recorded_by must identify the main-thread supervising lead architect"* ]]
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
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
    --primary-author-tool "codex" \
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

@test "validate_docs reports missing rg for secret scanning" {
  run env PATH="/usr/bin:/bin" "$VALIDATE" "$TEST_PROJECT" --mode strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"ripgrep (rg) is required for secret scanning"* ]]
}

# ========== P2: task-index status section movement ==========

@test "task-index places row under correct status section" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "300" \
    --task-title "Section Test" \
    --task-status "planned" \
    --no-init

  local index="$DOCS_ROOT/task/task-index.md"
  # Verify the row is under ## Planned section
  run grep "^- TASK-300 |" "$index"
  [ "$status" -eq 0 ]
  [[ "$output" == *"planned"* ]]

  # Move to in_progress
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "300" \
    --task-title "Section Test" \
    --task-status "in_progress" \
    --no-init

  # Should not have duplicates
  local count
  count=$(grep -c "^- TASK-300 |" "$index")
  [ "$count" -eq 1 ]

  run grep "^- TASK-300 |" "$index"
  [[ "$output" == *"in_progress"* ]]
}

@test "task-index prevents duplicate rows" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "400" \
    --task-title "Dup Test" \
    --task-status "in_progress" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "400" \
    --task-title "Dup Test Updated" \
    --task-status "in_progress" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "400" \
    --task-title "Dup Test Final" \
    --task-status "done" \
    --no-init

  local index="$DOCS_ROOT/task/task-index.md"
  local count
  count=$(grep -c "^- TASK-400 |" "$index")
  [ "$count" -eq 1 ]
  run grep "^- TASK-400 |" "$index"
  [[ "$output" == *"done"* ]]
}

# ========== P1: change-scope branching ==========

@test "run_codeguide reports docs-only scope by default" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "500" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"change_scope: docs-only"* ]]
}

@test "run_codeguide forwards risk_level into generated docs" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "risk-run-01" --mode advisory --risk-level "critical"
  [ "$status" -eq 0 ]
  [[ "$output" == *"risk_level: critical"* ]]

  run grep "^- risk_level: critical" "$DOCS_ROOT/task/TASK-risk-run-01.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level: critical" "$DOCS_ROOT/decisions/decision-auto-task-risk-run-01.md"
  [ "$status" -eq 0 ]
}

@test "run_codeguide fails clearly when option value is missing" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"Option --mode requires a value"* ]]
}

@test "run_codeguide requires risk preflight before delegated orchestration" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
    --task-id "run-preflight-gate-01" \
    --mode advisory \
    --execution-mode "supervisor_subagents"

  [ "$status" -ne 0 ]
  [[ "$output" == *"--risk-preflight-status is required before delegated orchestration"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/ORCH-run-preflight-gate-01.md"
  [ "$status" -eq 0 ]
}

@test "run_codeguide records blocked delegation when preflight requires approval" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
    --task-id "run-approval-stop-01" \
    --mode advisory \
    --execution-mode "supervisor_subagents" \
    --risk-preflight-status "approval_required"

  [ "$status" -eq 0 ]
  local orch_file="$DOCS_ROOT/orchestration/ORCH-run-approval-stop-01.md"
  run grep "^- delegation_status: blocked" "$orch_file"
  [ "$status" -eq 0 ]
  run grep "Delegation stopped before agent or external work" "$orch_file"
  [ "$status" -eq 0 ]
}

@test "run_codeguide reports code-or-runtime when runtime cmd provided" {
  local allow_file="$TEST_PROJECT/runtime-allow.txt"
  printf "echo\necho test-pass\n" > "$allow_file"

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "501" --mode advisory \
    --change-scope "code-or-runtime" \
    --runtime-test-cmd "echo test-pass" \
    --runtime-allow-list "$allow_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"change_scope: code-or-runtime"* ]]
  [[ "$output" == *"test-pass"* ]]
}

@test "run_codeguide passes shadow note through to project shadow" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" \
    --task-id "shadow-note-01" \
    --mode advisory \
    --shadow-note "search and navigation updated"
  [ "$status" -eq 0 ]

  run grep "^- latest_change_note:" "$DOCS_ROOT/shadow/project-shadow.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"search and navigation updated"* ]]
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
  [[ "$output" == *"graph refresh"* ]]

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

@test "doc_garden rejects git_diff shadow refresh without explicit range" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "shadow-git-01" \
    --task-title "Shadow git diff validation" \
    --shadow-refresh-mode "git_diff" \
    --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"--shadow-git-range is required"* ]]
}

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

@test "check_english_docs passes for curated codeguide markdown" {
  run "$CHECK_ENGLISH_DOCS" "$(cd "$SCRIPTS_DIR/.." && pwd)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"English-only"* ]]
}

@test "SKILL.md documents pre-orchestration risk approval gate" {
  local skill_file
  skill_file="$(cd "$SCRIPTS_DIR/.." && pwd)/SKILL.md"

  run grep "Run risk preflight in the main thread before spawning sub-agents" "$skill_file"
  [ "$status" -eq 0 ]
  run grep "do not spawn new sub-agents, do not invoke external CLIs" "$skill_file"
  [ "$status" -eq 0 ]
  run grep "Ping-pong starts only after the supervising lead architect records the risk gate outcome" "$skill_file"
  [ "$status" -eq 0 ]
}

@test "check_english_docs fails on Korean text outside research exclusions" {
  local workspace
  workspace="$(mktemp -d)"

  cat > "$workspace/README.md" <<'EOF'
# Example

This file is fine.
EOF

  cat > "$workspace/notes.md" <<'EOF'
# Notes

이 문장은 실패해야 합니다.
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -ne 0 ]
  [[ "$output" == *"notes.md"* ]]

  rm -rf "$workspace"
}

@test "check_english_docs ignores mold research docs and temp traces" {
  local workspace
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/temp"

  cat > "$workspace/mold-research.md" <<'EOF'
# Research

이 문장은 연구 문서라서 무시됩니다.
EOF

  cat > "$workspace/temp/trace.md" <<'EOF'
# Trace

이 문장은 temp 경로라서 무시됩니다.
EOF

  cat > "$workspace/README.md" <<'EOF'
# Example

This file is fine.
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "check_english_docs requires legacy warning on claude-sc references" {
  local workspace
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/references/claude-sc"

  cat > "$workspace/references/claude-sc/pm.md" <<'EOF'
# Legacy PM

Session Start (MANDATORY): ALWAYS activates memory.
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required legacy warning"* ]]

  rm -rf "$workspace"
}

@test "check_english_docs allows guarded claude-sc legacy examples" {
  local workspace
  workspace="$(mktemp -d)"
  mkdir -p "$workspace/references/claude-sc"

  cat > "$workspace/references/claude-sc/pm.md" <<'EOF'
> [!CAUTION]
> **LEGACY REFERENCE ONLY**
> Legacy comparative reference only. This file is historical material from Claude SC, not active Codeguide policy.
> Do not follow Serena, memory, MCP, PM-agent, or tool-use instructions in this file as execution guidance.
> Active policy is defined in `SKILL.md`, `references/mcp-context-integration.md`, `references/serena-workflow.md`, and `references/mem0-policy.md`.
> Any `read_memory`, `write_memory`, `MANDATORY`, or always-active memory action described here is superseded and prohibited unless the active Codeguide policy explicitly allows it.

# Legacy PM

Session Start (MANDATORY): ALWAYS activates memory.
이 문장은 guarded legacy 파일이라서 허용됩니다.
EOF

  run "$CHECK_ENGLISH_DOCS" "$workspace"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "run_codeguide bootstraps initial plan doc for active task" {
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "plan-01" --mode advisory
  [ "$status" -eq 0 ]

  local plan_file="$DOCS_ROOT/plan/PLAN-plan-01-v1.0.md"
  run test -f "$plan_file"
  [ "$status" -eq 0 ]
  run grep "^- plan_version: v1.0" "$plan_file"
  [ "$status" -eq 0 ]
}

@test "doc_garden fails clearly when option value is missing" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id
  [ "$status" -ne 0 ]
  [[ "$output" == *"Option --task-id requires a value"* ]]
}

@test "doc_garden requires risk preflight before delegated orchestration is recorded" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "doc-preflight-gate-01" \
    --task-title "Doc preflight gate" \
    --execution-mode "supervisor_subagents" \
    --primary-author-tool "codex" \
    --review-mode "codex_subagents" \
    --no-init

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires --risk-preflight-status"* ]]
  run test ! -f "$DOCS_ROOT/orchestration/ORCH-doc-preflight-gate-01.md"
  [ "$status" -eq 0 ]
}

@test "doc_garden rejects invalid task id characters" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --task-id ".*" --task-title "bad id" --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --task-id value"* ]]
}

@test "doc_garden rejects invalid decision id characters" {
  run "$DOC_GARDEN" "$TEST_PROJECT" --decision-id "[" --decision-title "bad id" --selected-option "x" --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --decision-id value"* ]]
}

@test "doc_garden rejects invalid task status enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "bad-status-01" \
    --task-title "bad status" \
    --task-status "working" \
    --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --task-status"* ]]
}

@test "doc_garden rejects invalid scope type enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "bad-scope-01" \
    --decision-title "bad scope" \
    --scope-type "feature" \
    --selected-option "x" \
    --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --scope-type"* ]]
}

@test "doc_garden rejects invalid decision status enum" {
  run "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "bad-decision-status-01" \
    --decision-title "bad decision status" \
    --decision-status "merged" \
    --selected-option "x" \
    --no-init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --decision-status"* ]]
}

# ========== decision-index section-based movement ==========

@test "decision-index places row under correct status section" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-sec-01" \
    --decision-title "Section Decision" \
    --decision-status "proposed" \
    --selected-option "Option A" \
    --no-init

  local index="$DOCS_ROOT/decisions/decision-index.md"
  run grep "^- decision-d-sec-01.md |" "$index"
  [ "$status" -eq 0 ]
  [[ "$output" == *"proposed"* ]]

  # Move to accepted
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-sec-01" \
    --decision-title "Section Decision" \
    --decision-status "accepted" \
    --selected-option "Option A" \
    --no-init

  local count
  count=$(grep -c "^- decision-d-sec-01.md |" "$index")
  [ "$count" -eq 1 ]
  run grep "^- decision-d-sec-01.md |" "$index"
  [[ "$output" == *"accepted"* ]]
}

@test "decision-index prevents duplicate rows" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-dup-01" \
    --decision-title "Dup Decision" \
    --decision-status "proposed" \
    --selected-option "First" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-dup-01" \
    --decision-title "Dup Decision" \
    --decision-status "accepted" \
    --selected-option "Updated" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "d-dup-01" \
    --decision-title "Dup Decision" \
    --decision-status "superseded" \
    --selected-option "Final" \
    --no-init

  local index="$DOCS_ROOT/decisions/decision-index.md"
  local count
  count=$(grep -c "^- decision-d-dup-01.md |" "$index")
  [ "$count" -eq 1 ]
  run grep "^- decision-d-dup-01.md |" "$index"
  [[ "$output" == *"superseded"* ]]
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

@test "decision-index migrates legacy table format" {
  # Create a legacy table-format decision-index
  cat > "$DOCS_ROOT/decisions/decision-index.md" <<'EOF'
# Decision Index

| file | decision_id | scope_type | date | status | chosen_by | linked_task | linked_pr | linked_hotfix | summary |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| decision-legacy.md | legacy | task | 2025-01-01 | accepted | user | TASK-1 | | | Old entry |
EOF

  # Run doc_garden with a new decision — should auto-migrate
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --decision-id "new-01" \
    --decision-title "New Decision" \
    --decision-status "proposed" \
    --selected-option "New option" \
    --no-init

  local index="$DOCS_ROOT/decisions/decision-index.md"

  # Legacy table rows should be gone
  run grep "^|" "$index"
  [ "$status" -ne 0 ]

  # New section headers should exist
  run grep "## Proposed" "$index"
  [ "$status" -eq 0 ]
  run grep "## Accepted" "$index"
  [ "$status" -eq 0 ]

  # Legacy row should be preserved as section-format row
  run grep "^- decision-legacy.md | legacy | task | 2025-01-01 | accepted | TASK-1 | Old entry" "$index"
  [ "$status" -eq 0 ]

  # New entry should be present
  run grep "^- decision-new-01.md |" "$index"
  [ "$status" -eq 0 ]

  # Migration should create a backup file
  run bash -c "ls \"$DOCS_ROOT/decisions\"/decision-index.md.bak.* >/dev/null"
  [ "$status" -eq 0 ]
}

# ========== runtime-cmd security ==========

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

@test "run_codeguide works in non-git directory with info message" {
  # TEST_PROJECT is created with mktemp, not a git repo
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --task-id "nogit-01" --mode advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not a git repository"* ]]
  [[ "$output" == *"task_id: nogit-01"* ]]
}

@test "run_codeguide in non-git falls back to latest task file when no explicit id" {
  # Create an existing task file first
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "existing-77" \
    --task-title "Existing task" \
    --no-init

  # Run without --task-id in a non-git dir
  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --mode advisory
  [ "$status" -eq 0 ]
  # Should pick up the existing task file since no branch can be inferred
  [[ "$output" == *"task_id: existing-77"* ]]
}

@test "run_codeguide in non-git requires --task-id when multiple active tasks exist" {
  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "active-a" \
    --task-title "Active A" \
    --task-status "in_progress" \
    --no-init

  "$DOC_GARDEN" "$TEST_PROJECT" \
    --task-id "active-b" \
    --task-title "Active B" \
    --task-status "blocked" \
    --no-init

  run "$RUN_CODEGUIDE" "$TEST_PROJECT" --mode advisory
  [ "$status" -ne 0 ]
  [[ "$output" == *"Multiple active tasks detected"* ]]
  [[ "$output" == *"Use --task-id"* ]]
}

@test "run_codeguide in non-git with no tasks uses timestamp fallback" {
  # Fresh project with no task files
  local fresh_workspace
  local fresh_project
  fresh_workspace="$(mktemp -d)"
  fresh_project="$fresh_workspace/repo"
  mkdir -p "$fresh_project"
  "$INIT_SCAFFOLD" "$fresh_project"

  run "$RUN_CODEGUIDE" "$fresh_project" --mode advisory
  [ "$status" -eq 0 ]
  # Timestamp fallback starts with "A" followed by digits
  [[ "$output" == *"task_id: A2"* ]]
  rm -rf "$fresh_workspace"
}

# ========== init_docs_scaffold edge cases ==========

@test "init_docs_scaffold is idempotent" {
  local workspace
  local proj
  local docs_root
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  docs_root="$(docs_root_for_project "$proj")"

  "$INIT_SCAFFOLD" "$proj"
  # Modify a file to verify it's not overwritten
  echo "custom content" >> "$docs_root/task/project-dictionary.md"

  "$INIT_SCAFFOLD" "$proj"
  # File should still have our custom content (not reset)
  run grep "custom content" "$docs_root/task/project-dictionary.md"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

@test "init_docs_scaffold fails on non-existent target" {
  run "$INIT_SCAFFOLD" "/tmp/nonexistent_codeguide_test_dir_$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "init_docs_scaffold fails when docs path is a file" {
  local workspace
  local proj
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  touch "$proj/docs"  # create a file, not a directory

  run "$INIT_SCAFFOLD" "$proj"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a directory"* ]]

  rm -rf "$workspace"
}

@test "init_docs_scaffold shows help with --help" {
  run "$INIT_SCAFFOLD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "init_docs_scaffold creates DOC-GOVERNANCE with new sections" {
  local workspace
  local proj
  local docs_root
  workspace="$(mktemp -d)"
  proj="$workspace/repo"
  mkdir -p "$proj"
  "$INIT_SCAFFOLD" "$proj"
  docs_root="$(docs_root_for_project "$proj")"

  run grep "Data safety" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Change scope" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "runtime-allow-list" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Plan orchestration loop" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "Run main-thread risk preflight before sub-agents" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]

  run test -d "$docs_root/plan"
  [ "$status" -eq 0 ]
  run test -d "$docs_root/report"
  [ "$status" -eq 0 ]
  run test -f "$docs_root/plan/PLAN-template.md"
  [ "$status" -eq 0 ]
  run test -f "$docs_root/report/LLM-REVIEW-template.md"
  [ "$status" -eq 0 ]
  run grep "review_style" "$docs_root/report/LLM-REVIEW-template.md"
  [ "$status" -eq 0 ]
  run grep "adversarial review pass" "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep 'active task omits `risk_level`' "$docs_root/DOC-GOVERNANCE.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level:$" "$docs_root/task/task-template.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_level:$" "$docs_root/decisions/decision-template.md"
  [ "$status" -eq 0 ]

  rm -rf "$workspace"
}

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
  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/gemini-called"
exit 99'
  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
touch "${TEST_WORKSPACE}/claude-called"
exit 99'
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

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
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
  [[ "$output" == *"[OK] evaluator=gemini"* ]]
  [[ "$output" == *"[OK] evaluator=claude"* ]]
  [[ "$output" == *"No new plan version was created automatically."* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-gemini-r01.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-claude-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: standard" "$DOCS_ROOT/report/PLAN-ext-review-01-v1.0-review-gemini-r01.md"
  [ "$status" -eq 0 ]
  run grep "^- primary_author_tool: codex" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]
  run grep "^- review_mode: external_cli" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]
  run grep "^- risk_preflight_status: approved" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]
  run grep "^- approval_required: true" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]
  run grep "^- approval_ref: user-approval-ext-review-01" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]
  run grep "^- reviewer_agents: external-cli:gemini,claude" "$DOCS_ROOT/orchestration/ORCH-ext-review-01.md"
  [ "$status" -eq 0 ]

  local after_plan
  after_plan="$(cat "$plan_file")"
  [ "$before_plan" = "$after_plan" ]

  run grep -E -- '(^|[[:space:]])-m([[:space:]]|$)' "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -ne 0 ]
  run grep -E -- '(^|[[:space:]])--model([[:space:]]|$)' "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -ne 0 ]
  run grep -- "--include-directories" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep -- "$TEST_PROJECT" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--add-dir" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run grep -- "$TEST_PROJECT" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--tools" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run grep -- "Read" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--bare" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -ne 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-01" "v1.0" "r01")"
  [ -n "$handoff_dir" ]
  [[ "$handoff_dir" =~ /[A-Z][a-z]{2}[0-9]{2}_[0-9]{4}/ext-review-01/v1\.0/r01$ ]]
  run test -f "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/gemini.response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/gemini.retry-request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/gemini.retry-response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude.response.md"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/claude.stderr.md"
  [ "$status" -eq 0 ]
  run grep "## Why" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep "## What" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep "## How" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep "## Where" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep "## Verify" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep "## Payload" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep "### Plan under review" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep "# PLAN-ext-review-01-v1.0" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep "malformed first response" "$handoff_dir/gemini.response.md"
  [ "$status" -ne 0 ]
  run grep "/tmp/evil-plan.md" "$handoff_dir/gemini.response.md"
  [ "$status" -eq 0 ]
  run grep "unsupported save-location claim" "$handoff_dir/gemini.stderr.md"
  [ "$status" -eq 0 ]
  run grep "review contract should be stricter" "$handoff_dir/gemini.retry-response.md"
  [ "$status" -eq 0 ]
  run grep -F "[REDACTED_SECRET]" "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run grep -F "[REDACTED_SECRET]" "$handoff_dir/gemini.retry-response.md"
  [ "$status" -eq 0 ]
  run grep "sk-12345678901234567890" "$handoff_dir/gemini.request.md"
  [ "$status" -ne 0 ]
  run grep "sk-proj-12345678901234567890" "$handoff_dir/gemini.request.md"
  [ "$status" -ne 0 ]
  run grep "ghp_12345678901234567890" "$handoff_dir/gemini.retry-response.md"
  [ "$status" -ne 0 ]
  run grep "sk-proj-12345678901234567890" "$handoff_dir/gemini.retry-response.md"
  [ "$status" -ne 0 ]
  run grep "$handoff_dir/gemini.retry-request.md" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/gemini.retry-command-response.raw.md" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep "command_response_path: $handoff_dir/gemini.retry-command-response.raw.md" "$handoff_dir/gemini.retry-request.md"
  [ "$status" -eq 0 ]
  run grep "sanitized_response_file: $handoff_dir/gemini.retry-response.md" "$handoff_dir/gemini.retry-request.md"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/gemini.retry-command-response.raw.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/gemini.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  local gemini_retry_hash
  gemini_retry_hash="$(sha256_file_ref "$handoff_dir/gemini.retry-response.md")"
  run grep "artifact_kind: external_cli_review_response_provenance" "$handoff_dir/gemini.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "generated_by: run_external_plan_reviews.sh" "$handoff_dir/gemini.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "response_file: $handoff_dir/gemini.retry-response.md" "$handoff_dir/gemini.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "response_sha256: $gemini_retry_hash" "$handoff_dir/gemini.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "command_response_path: $handoff_dir/gemini.retry-command-response.raw.md" "$handoff_dir/gemini.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "raw_capture_deleted: true" "$handoff_dir/gemini.retry-response.provenance.md"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/claude.command-response.raw.md" "$TEST_WORKSPACE/claude-args.log"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/claude.command-response.raw.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude.response.provenance.md"
  [ "$status" -eq 0 ]
}

@test "run_external_plan_reviews supports adversarial reviewer and optional model override with best-effort success" {
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

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
echo "gemini should not be called for primary=gemini" >&2
exit 99'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/claude-args.log"
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
    --primary-tool "gemini" \
    --review-round "r02" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-02" \
    --approved-next-step "run external review ext-review-02 v1.0 r02" \
    --allow-partial-review \
    --adversarial-evaluator "codex" \
    --codex-model "gpt-5.4"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[FAIL] evaluator=claude"* ]]
  [[ "$output" == *"[OK] evaluator=codex style=adversarial"* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-r02.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-r02.md"
  [ "$status" -eq 0 ]
  run grep "^- objection:" "$DOCS_ROOT/report/PLAN-ext-review-02-v1.0-review-codex-r02.md"
  [ "$status" -eq 0 ]
  run grep -- "gpt-5.4" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--sandbox" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "read-only" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--ephemeral" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "--output-last-message" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -F -- "-C" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep -- "$TEST_PROJECT" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-02" "v1.0" "r02")"
  [ -n "$handoff_dir" ]
  [[ "$handoff_dir" =~ /[A-Z][a-z]{2}[0-9]{2}_[0-9]{4}/ext-review-02/v1\.0/r02$ ]]
  run test -f "$handoff_dir/codex.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/codex.response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/claude.stderr.md"
  [ "$status" -eq 0 ]
  run grep "# PLAN-ext-review-02-v1.0" "$handoff_dir/codex.request.md"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/codex.request.md" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/codex.command-response.raw.md" "$TEST_WORKSPACE/codex-args.log"
  [ "$status" -eq 0 ]
  run test ! -f "$handoff_dir/codex.command-response.raw.md"
  [ "$status" -eq 0 ]
  run grep -F "[REDACTED_SECRET]" "$handoff_dir/claude.stderr.md"
  [ "$status" -eq 0 ]
  run grep "sk-proj-12345678901234567890" "$handoff_dir/claude.stderr.md"
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
    --primary-author-tool "codex" \
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

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "claude should not be called for primary=claude" >&2
exit 99'

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
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
  [[ "$output" == *"auto-selecting adversarial evaluator=gemini"* ]]
  [[ "$output" == *"[OK] evaluator=gemini style=adversarial"* ]]
  [[ "$output" == *"[OK] evaluator=codex style=standard"* ]]

  run test -f "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-gemini-r04.md"
  [ "$status" -eq 0 ]
  run grep "^- review_style: adversarial" "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-gemini-r04.md"
  [ "$status" -eq 0 ]
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-04-v1.0-review-codex-r04.md"
  [ "$status" -eq 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-04" "v1.0" "r04")"
  [ -n "$handoff_dir" ]
  [[ "$handoff_dir" =~ /[A-Z][a-z]{2}[0-9]{2}_[0-9]{4}/ext-review-04/v1\.0/r04$ ]]
  run test -f "$handoff_dir/gemini.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/gemini.response.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/codex.request.md"
  [ "$status" -eq 0 ]
  run test -f "$handoff_dir/codex.response.md"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/gemini.command-response.raw.md" "$TEST_WORKSPACE/gemini-args.log"
  [ "$status" -eq 0 ]
  run grep "$handoff_dir/codex.command-response.raw.md" "$TEST_WORKSPACE/codex-args.log"
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

  cat > "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-gemini-r03.md" <<'EOF'
# PLAN-ext-review-03-v1.0 review (gemini)

- task_id: ext-review-03
- plan_version: v1.0
- evaluator: gemini
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

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
echo "gemini failure" >&2
exit 3'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "claude should not be called for primary=claude" >&2
exit 99'

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
  [[ "$output" == *"[FAIL] evaluator=gemini"* ]]
  [[ "$output" == *"[FAIL] evaluator=codex"* ]]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-gemini-r03.md"
  [ "$status" -eq 0 ]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-review-03-v1.0-review-codex-r03.md"
  [ "$status" -eq 0 ]
  run find "$DOCS_ROOT/report" -maxdepth 1 -type f -name 'PLAN-ext-review-03-v1.0-review-gemini-r03.md.stale-*'
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
    --primary-author-tool "codex" \
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

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "claude should not be called for primary=claude" >&2
exit 99'

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
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
  run test -f "$DOCS_ROOT/report/PLAN-ext-review-05-v1.0-review-codex-r05.md"
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

  write_mock_cli "$mock_bin/gemini" '#!/usr/bin/env bash
echo "gemini should not be called for primary=gemini" >&2
exit 99'

  write_mock_cli "$mock_bin/claude" '#!/usr/bin/env bash
echo "mock claude failure" >&2
exit 7'

  write_mock_cli "$mock_bin/codex" '#!/usr/bin/env bash
printf "%s\n" "$@" > "${TEST_WORKSPACE}/codex-args.log"
echo "codex runtime log only"
exit 0'

  run env PATH="$mock_bin:$PATH" bash "$RUN_EXTERNAL_REVIEWS" "$TEST_PROJECT" \
    --task-id "ext-review-06" \
    --plan-version "v1.0" \
    --primary-tool "gemini" \
    --review-round "r06" \
    --risk-preflight-status "approved" \
    --approval-ref "user-approval-ext-review-06" \
    --approved-next-step "run external review ext-review-06 v1.0 r06"

  [ "$status" -ne 0 ]
  [[ "$output" == *"[FAIL] evaluator=codex"* ]]
  run test ! -f "$DOCS_ROOT/report/PLAN-ext-review-06-v1.0-review-codex-r06.md"
  [ "$status" -eq 0 ]

  local handoff_dir
  handoff_dir="$(external_handoff_dir "ext-review-06" "v1.0" "r06")"
  [ -n "$handoff_dir" ]
  run grep "codex final message file was empty" "$handoff_dir/codex.stderr.md"
  [ "$status" -eq 0 ]
  run grep "codex runtime log only" "$handoff_dir/codex.stderr.md"
  [ "$status" -eq 0 ]
}
