#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  init_docs_scaffold.sh [project-root]

Initializes the workspace docs/ scaffold for codeguide documentation.
Creates directories and template files only when missing (idempotent).

Options:
  -h, --help   Show this message
EOF
}

# Handle --help before positional args
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

TARGET_ROOT="${1:-.}"

if [[ ! -d "$TARGET_ROOT" ]]; then
  echo "[ERROR] Target root does not exist or is not a directory: $TARGET_ROOT" >&2
  exit 1
fi

INPUT_ROOT_ABS="$(cd "$TARGET_ROOT" && pwd)"

resolve_repo_root() {
  git -C "$INPUT_ROOT_ABS" rev-parse --show-toplevel 2>/dev/null || printf "%s" "$INPUT_ROOT_ABS"
}

PROJECT_ROOT_ABS="$(resolve_repo_root)"
WORKSPACE_ROOT="$(cd "$PROJECT_ROOT_ABS/.." && pwd)"
WORKSPACE_DOCS_ROOT="${WORKSPACE_ROOT}/docs"
DOCS_DIR="${WORKSPACE_DOCS_ROOT}"

# Guard: if docs path exists but is a file, abort
if [[ -e "$DOCS_DIR" && ! -d "$DOCS_DIR" ]]; then
  echo "[ERROR] $DOCS_DIR exists but is not a directory. Cannot initialize scaffold." >&2
  exit 1
fi

TASK_DIR="${DOCS_DIR}/task"
SHADOW_DIR="${DOCS_DIR}/shadow"
DECISIONS_DIR="${DOCS_DIR}/decisions"
PLAN_DIR="${DOCS_DIR}/plan"
REPORT_DIR="${DOCS_DIR}/report"
ORCHESTRATION_DIR="${DOCS_DIR}/orchestration"
EXTERNAL_CLI_DIR="${ORCHESTRATION_DIR}/external-cli"
POLICY_DIR="${DOCS_DIR}/policy"
SHADOW_BUCKETS=(apps services packages infra data)
SHADOW_ARCHIVE_DIRS=(_deprecated _obsolete)

mkdir -p "${TASK_DIR}" "${SHADOW_DIR}" "${DECISIONS_DIR}" "${PLAN_DIR}" "${REPORT_DIR}" "${ORCHESTRATION_DIR}" "${EXTERNAL_CLI_DIR}" "${POLICY_DIR}"

for bucket in "${SHADOW_BUCKETS[@]}"; do
  mkdir -p "${SHADOW_DIR}/${bucket}"
done

for archive_dir in "${SHADOW_ARCHIVE_DIRS[@]}"; do
  mkdir -p "${SHADOW_DIR}/${archive_dir}"
done

write_if_missing() {
  local file_path="$1"
  local content="$2"
  if [[ ! -f "${file_path}" ]]; then
    printf "%s\n" "${content}" > "${file_path}"
  fi
}

copy_policy_defaults_if_available() {
  local source_dir="${SCRIPT_DIR}/../../docs/policy"
  local source_abs
  local dest_abs
  local policy_file

  [[ -d "$source_dir" ]] || return 1

  source_abs="$(cd "$source_dir" && pwd)"
  dest_abs="$(cd "$POLICY_DIR" && pwd)"
  [[ "$source_abs" == "$dest_abs" ]] && return 0

  for policy_file in shadow-validator-catalog.md shadow-regex-patterns.md shadow-rule-registry.md; do
    if [[ -f "${source_abs}/${policy_file}" && ! -f "${POLICY_DIR}/${policy_file}" ]]; then
      cp "${source_abs}/${policy_file}" "${POLICY_DIR}/${policy_file}"
    fi
  done
}

copy_policy_defaults_if_available || true

write_if_missing "${POLICY_DIR}/shadow-validator-catalog.md" '# Shadow Validator Catalog

- catalog_id: shadow-validator-catalog
- catalog_version: 1
- status: active-draft
- linked_task: TASK-shadow-effect-map-01
- linked_decision: decision-shadow-validator-taxonomy-01
- purpose: Define which validators can support shadow fact promotion.
- last_updated: 2026-04-30T13:49:45Z

## Contract

- Validator ids must include category prefix and version suffix.
- A validator not listed here cannot produce a validated shadow fact.

```yaml
validators:
  any.test.assertion@v1:
    evidence_type: test_assertion
    validates: matching test assertion exists
    limitations: [depends_on_test_scope]
  any.runtime.trace@v1:
    evidence_type: runtime_trace
    validates: runtime event exists
    limitations: [observation_window_may_be_incomplete]
  java.ast.call_match@v1:
    evidence_type: code_call
    validates: Java call exists at source anchor
    limitations: [does_not_prove_runtime_execution]
  java.annotation.match@v1:
    evidence_type: annotation
    validates: Java annotation exists
    limitations: [does_not_prove_proxy_activation]
  js.ast.call_match@v1:
    evidence_type: code_call
    validates: JavaScript call exists
    limitations: [dynamic_dispatch_can_hide_target]
  ts.ast.call_match@v1:
    evidence_type: code_call
    validates: TypeScript call exists
    limitations: [does_not_prove_runtime_execution]
  py.ast.call_match@v1:
    evidence_type: code_call
    validates: Python call exists
    limitations: [dynamic_dispatch_can_hide_target]
  spring_boot.request_mapping@v1:
    evidence_type: annotation
    validates: Spring Boot request mapping annotation exists
    limitations: [does_not_prove_route_reachable]
  spring_boot.cache_evict.annotation@v1:
    evidence_type: annotation
    validates: Spring cache eviction annotation exists
    limitations: [does_not_prove_proxy_activation]
  express.route@v1:
    evidence_type: code_call
    validates: Express route registration call exists
    limitations: [does_not_prove_middleware_order]
  react.effect_hook@v1:
    evidence_type: code_call
    validates: React effect hook call exists
    limitations: [does_not_prove_effect_execution_timing]
  fastapi.route@v1:
    evidence_type: annotation
    validates: FastAPI route decorator exists
    limitations: [does_not_prove_app_mount]
  fastapi.dependency@v1:
    evidence_type: code_reference
    validates: FastAPI dependency declaration exists
    limitations: [does_not_prove_dependency_success]
  jpa.repository.save@v1:
    evidence_type: code_call
    validates: JPA repository save-like call exists
    limitations: [does_not_prove_flush_or_commit]
  sql.write_call@v1:
    evidence_type: code_call
    validates: SQL write invocation exists
    limitations: [does_not_prove_rows_affected]
```
'

write_if_missing "${POLICY_DIR}/shadow-regex-patterns.md" '# Shadow Regex Pattern Registry

- registry_id: shadow-regex-patterns
- registry_version: 1
- status: active-draft
- linked_task: TASK-shadow-effect-map-01
- linked_decision: decision-shadow-regex-standard-01
- purpose: Define approved regex fallback patterns for shadow evidence discovery.
- last_updated: 2026-04-30T13:49:45Z

## Contract

- Regex ids must include a version suffix.
- Regex-only promotion is capped at low or medium.

```yaml
regex_patterns:
  java.regex.method_call_named@v1:
    pattern: java-call-pattern
    allowed_paths: ["src/main/java/**"]
    excluded_paths: ["src/test/**", "build/**", "target/**"]
    validates: named Java call syntax appears
    cannot_validate: [runtime_execution, overload_resolution]
    max_promotion_risk: medium
  java.regex.repository_save_call@v1:
    pattern: java-repository-save-pattern
    allowed_paths: ["src/main/java/**"]
    excluded_paths: ["src/test/**", "build/**", "target/**"]
    validates: repository save syntax appears
    cannot_validate: [transaction_success, downstream_listeners]
    max_promotion_risk: medium
  java.regex.annotation_named@v1:
    pattern: java-annotation-pattern
    allowed_paths: ["src/main/java/**"]
    excluded_paths: ["src/test/**", "build/**", "target/**"]
    validates: named Java annotation syntax appears
    cannot_validate: [proxy_activation, runtime_behavior]
    max_promotion_risk: medium
  spring_boot.regex.request_mapping@v1:
    pattern: spring-request-mapping-pattern
    allowed_paths: ["src/main/java/**"]
    excluded_paths: ["src/test/**", "build/**", "target/**"]
    validates: Spring request mapping annotation syntax appears
    cannot_validate: [route_reachable, security_allowed]
    max_promotion_risk: medium
  js.regex.call_named@v1:
    pattern: js-call-pattern
    allowed_paths: ["src/**", "app/**", "lib/**"]
    excluded_paths: ["node_modules/**", "dist/**", "build/**"]
    validates: named JavaScript call syntax appears
    cannot_validate: [runtime_execution, async_completion]
    max_promotion_risk: medium
  py.regex.call_named@v1:
    pattern: py-call-pattern
    allowed_paths: ["**/*.py"]
    excluded_paths: ["tests/**", ".venv/**", "venv/**", "build/**"]
    validates: named Python call syntax appears
    cannot_validate: [runtime_execution, monkey_patch_target]
    max_promotion_risk: medium
  py.regex.decorator_named@v1:
    pattern: py-decorator-pattern
    allowed_paths: ["**/*.py"]
    excluded_paths: ["tests/**", ".venv/**", "venv/**", "build/**"]
    validates: named Python decorator syntax appears
    cannot_validate: [decorator_runtime_behavior, dependency_success]
    max_promotion_risk: medium
```
'

write_if_missing "${POLICY_DIR}/shadow-rule-registry.md" '# Shadow Rule Registry

- registry_id: shadow-rule-registry
- registry_version: 1
- status: active-draft
- linked_task: TASK-shadow-effect-map-01
- linked_decisions: decision-shadow-practical-contract-01, decision-shadow-validator-taxonomy-01, decision-shadow-regex-standard-01
- purpose: Map shadow rule ids to compatible validators, approved regex fallback patterns, risk floors, and promotion gates.
- last_updated: 2026-04-30T13:49:45Z

## Contract

- Rule ids not listed here cannot produce validated shadow facts.
- Regex fallback must reference shadow-regex-patterns.md.
- Regex-only promotion cannot exceed medium.

```yaml
rules:
  repo.write:
    validators_by_stack:
      spring_boot_jpa:
        code_call:
          primary: jpa.repository.save@v1
          fallback: java.regex.repository_save_call@v1
          fallback_max_risk: medium
      java_generic:
        code_call:
          primary: java.ast.call_match@v1
          fallback: java.regex.method_call_named@v1
          fallback_max_risk: medium
      python:
        code_call:
          primary: py.ast.call_match@v1
          fallback: py.regex.call_named@v1
          fallback_max_risk: medium
  cache.evict:
    validators_by_stack:
      spring_boot:
        annotation:
          primary: spring_boot.cache_evict.annotation@v1
          fallback: java.regex.annotation_named@v1
          fallback_max_risk: medium
  external.call:
    validators_by_stack:
      node:
        code_call:
          primary: js.ast.call_match@v1
          fallback: js.regex.call_named@v1
          fallback_max_risk: medium
  security.auth:
    validators_by_stack:
      spring_boot:
        annotation:
          primary: java.annotation.match@v1
          fallback: java.regex.annotation_named@v1
          fallback_max_risk: medium
      common:
        runtime_trace:
          primary: any.runtime.trace@v1
  http.route:
    validators_by_stack:
      spring_boot:
        annotation:
          primary: spring_boot.request_mapping@v1
          fallback: spring_boot.regex.request_mapping@v1
          fallback_max_risk: medium
      express:
        code_call:
          primary: express.route@v1
          fallback: js.regex.call_named@v1
          fallback_max_risk: medium
      fastapi:
        annotation:
          primary: fastapi.route@v1
          fallback: py.regex.decorator_named@v1
          fallback_max_risk: medium
```

```yaml
promotion_gates:
  regex_only:
    max_effective_risk: medium
    evidence_field: fallback_result
    forbidden_field: validator_result
  high_or_critical:
    requires_one_of:
      - parser_backed_validator
      - test_assertion
      - runtime_trace
      - valid_waiver
  unknown_defaults:
    unlisted_rule: unknown
    unlisted_boundary: unknown
    unmapped_stack: unknown
    unmapped_evidence_type: unknown
```
'

write_if_missing "${TASK_DIR}/project-dictionary.md" '# Project Dictionary

- project_name:
- business_goal:
- scope_in:
- scope_out:
- architecture_style:
- key_domains:
- critical_user_flows:
- environments:
- dependencies:
- security_constraints:
- compliance_constraints:
- performance_slo:
- reliability_slo:
- owners:
- decision_policy:
'

write_if_missing "${TASK_DIR}/task-index.md" '# Task Index

## Planned

## In Progress

## Blocked

## Done
'

write_if_missing "${DECISIONS_DIR}/decision-index.md" '# Decision Index

## Proposed

## Accepted

## Superseded
'

write_if_missing "${SHADOW_DIR}/project-shadow.md" '# Project Shadow

- doc_role: router
- read_path: project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf
- fast_entry:
- bucket_links: apps/_index.md, services/_index.md, packages/_index.md, infra/_index.md, data/_index.md
- global_doc: _global.md
- last_updated:
- updated_by_task:
- latest_change_note:
'

write_if_missing "${SHADOW_DIR}/_global.md" '# Shadow Global

- doc_role: global
- shared_runtime_rules:
- shared_config_rules:
- naming_rules:
- cross_unit_integration_contracts:
- last_updated:
'

for bucket in "${SHADOW_BUCKETS[@]}"; do
  write_if_missing "${SHADOW_DIR}/${bucket}/_index.md" "# Shadow Bucket Index

- doc_role: bucket_index
- bucket: ${bucket}
- last_updated:

## Units
- no units detected yet
"
done

write_if_missing "${TASK_DIR}/task-template.md" '# TASK-<id>

- title:
- objective:
- acceptance_criteria:
- non_goals:
- affected_modules:
- interfaces_changed:
- data_migrations:
- test_scope:
- risks:
- risk_level:
- status: planned | in_progress | blocked | done
- owner:
- due_date:
- axis_why:
- axis_where:
- axis_verify:
'

write_if_missing "${DECISIONS_DIR}/decision-template.md" '# decision-<id>

- decision_id:
- title:
- date:
- scope_type: task | hotfix | pr | release | incident | ops | other
- status: proposed | accepted | superseded
- chosen_by:
- linked_task:
- linked_pr:
- linked_hotfix:
- context:
- selected_option:
- alternatives_considered:
- rationale:
- implementation_plan:
- impact_and_risks:
- risk_level:
- rollback_or_mitigation:
- axis_why:
- axis_what:
- axis_how:
- axis_where:
- axis_verify:
'

write_if_missing "${PLAN_DIR}/PLAN-template.md" '# PLAN-<task-id>-v1.0

- task_id:
- plan_version: v1.0
- objective:
- scope:
- assumptions:
- risks:
- acceptance_signals:
- stop_conditions:
- owner:
- last_updated:

## Steps
1.
2.
3.
'

write_if_missing "${REPORT_DIR}/LLM-REVIEW-template.md" '# PLAN-<task-id>-v1.0 review (gemini)

- task_id:
- plan_version: v1.0
- evaluator: gemini # allowed: gemini | claude | codex
- review_style: standard | adversarial
- review_round: r01
- verdict: accept | revise | blocked
- summary:
- strengths:
- risks:
- requested_changes:
- objection:
- counterproposal:
- rebuttal:
- residual_risk:
- last_updated:
'

write_if_missing "${ORCHESTRATION_DIR}/ORCH-template.md" '# ORCH-<task-id>

- task_id:
- execution_mode: supervisor_subagents | solo
- primary_author_tool: gemini | claude | codex
- review_mode: external_cli | codex_subagents
- supervisor_agent:
- planner_agents:
- reviewer_agents:
- implementation_agents:
- validation_agents:
- owned_scopes:
- delegation_status: planned | active | completed | blocked
- delegation_note:
- last_updated:
'

write_if_missing "${DOCS_DIR}/SECURITY-NOTES.md" '# Documentation Security Notes

- Never store raw key/token/password/private-key values in docs.
- Only reference environment variable names (example: OPENAI_API_KEY).
- Redact sensitive values immediately if found.
'

write_if_missing "${DOCS_DIR}/DOC-GOVERNANCE.md" '# Docs Governance

## Required commands

- scripts/run_codeguide.sh <project-root> --mode auto
- scripts/doc_garden.sh <project-root> --task-id <TASK_ID>
- scripts/validate_docs.sh <project-root> --mode advisory
- scripts/validate_docs.sh <project-root> --mode strict (CI)

## Data safety

- Empty values never overwrite existing non-empty fields (use --allow-empty-overwrite to override).
- Axis values are only updated when explicitly provided (no generic defaults injected).
- task_id inference: explicit --task-id > branch pattern > latest task file > timestamp.
- In non-git mode with multiple active tasks, --task-id is required to avoid task mis-linking.

## Change scope

- docs-only (default): docs lifecycle + docs validation only.
- code-or-runtime: also runs user-provided commands via --runtime-test-cmd, --runtime-lint-cmd, --runtime-e2e-cmd.
- --runtime-allow-list is required in code-or-runtime mode.
- Runtime allow-list matching supports executable and executable+subcommand prefixes.
- Runtime commands with shell metacharacters are blocked.

## Docs root

- Docs live under workspace-root `docs/...`.
- The workspace root is exactly one level above the git-tracked project root.
- Do not add an extra `docs/<repo-name>` or `docs/repos/<repo-name>` layer unless the user explicitly requests it.

## Shadow graph contract

- Keep shadow docs in English.
- Keep shadow docs in Markdown only.
- Do not add JSON sidecars.
- Do not auto-create unit overview docs or concern leaf docs during bootstrap.
- Treat `docs/shadow/project-shadow.md` as the top router only.
- Treat `docs/shadow/_global.md` as the optional side path for cross-unit facts.
- Treat `docs/shadow/<bucket>/_index.md` as unit membership only.
- Use typed buckets only:
  - `apps`
  - `services`
  - `packages`
  - `infra`
  - `data`
- Create `_deprecated/` and `_obsolete/` under `docs/shadow/` for archived bodies and obsolete material.
- Preserve this default read path:
  - `project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf`

## Shadow freshness

- Refresh affected shadow graph docs for same-session implementation changes before closing the task.
- External git-driven shadow refresh happens only when the user explicitly requests shadow update.
- Keep shadow docs routing-oriented instead of mirroring large code blocks.

## Orchestration contract

- Main thread is the supervising lead architect, not the primary implementer.
- Active tasks require `orchestration/ORCH-<task-id>.md`.
- `execution_mode: supervisor_subagents` is the default path.
- Orchestration rules still apply in `docs-only` work.
- Record `primary_author_tool` and `review_mode` for plan review routing.
- Treat `서브에이전트`, `서브 에이전트`, `subagent`, `subagents`, `sub-agent`, and `sub-agents` as the same sub-agent trigger.
- If `execution_mode: solo` is used, `delegation_note` must explain why sub-agent delegation was not practical.
- In strict mode, supervising-lead-architect/sub-agent ownership fields must be populated for `supervisor_subagents`.

## Validation policy

- status/scope enum values are validated in both write phase and validation phase.
- Secret scan supports known key formats, quoted assignments, and yaml/env-style assignments.
- Add custom secret scan exclusions with --secret-scan-exclude-glob.

## Plan orchestration loop

- Create plan file first: workspace docs `plan/PLAN-<task-id>-v1.0.md`.
- Write evaluator report files in workspace docs `report/` with evaluator labels: gemini | claude | codex.
- External CLI handoff files live under `orchestration/external-cli/<MonDD_YYYY>/<task-id>/<plan-version>/<round>/`, for example `Apr29_2026/...`.
- External CLI requests use metadata plus `Why`, `What`, `How`, `Where`, `Verify`, then payload; CLI stdout is captured as sanitized Markdown and valid responses use parser-compatible bullet fields.
- Pass only a short instruction plus the request file path to the CLI.
- Default ping-pong mode uses external evaluators; if the user explicitly asks for sub-agent ping-pong review, interpret it as Codex sub-agent mode instead.
- Mark high-risk work with `risk_level: high|critical` on the task or linked decision.
- Advisory validation warns when an active task omits `risk_level`.
- If a task or linked non-superseded decision is high-risk, strict validation requires one adversarial review pass with objection/counterproposal/rebuttal/residual_risk.
- For each revision, create a new versioned plan file (v1.1, v1.2, ...), do not overwrite old versions.
- Semi-automated external review must stop after collecting report docs and showing the user the result; it does not auto-create the next plan version.
- Repeat review/revision loop until execution-ready or user stop.

## Anti-dump limits

- Keep shadow docs close to 200 lines and preferably at or below 300 lines.
- If a shadow doc exceeds 300 lines or stops narrowing the read path quickly, split it by concern instead of mirroring the underlying source file.
- docs/task/TASK-*.md <= 220 lines
- docs/decisions/decision-*.md <= 180 lines
- docs/orchestration/ORCH-*.md <= 180 lines

## Freshness SLA

- Same-session implementation changes refresh affected shadow graph docs in the same working session.
- External git-driven changes refresh shadow docs only on explicit user request.
- in_progress task files updated within 7 days.
- decision-index and task-index updated with each file change.

## Hotfix exception

- At urgent release time, write minimum decision log first.
- Complete full task and affected shadow sync within 24 hours.

## 5-axis records

- decision files: Why/What/How/Where/Verify
- task files: Why/Where/Verify
'

echo "Initialized workspace docs scaffold under: ${DOCS_DIR}"
echo "Repository root: ${PROJECT_ROOT_ABS}"
echo "Workspace root: ${WORKSPACE_ROOT}"
echo "Created directories:"
echo "  - ${TASK_DIR}"
echo "  - ${SHADOW_DIR}"
echo "  - ${DECISIONS_DIR}"
echo "  - ${PLAN_DIR}"
echo "  - ${REPORT_DIR}"
echo "  - ${ORCHESTRATION_DIR}"
echo "  - ${EXTERNAL_CLI_DIR}"
echo "Template files are created only when missing."
