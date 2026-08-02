#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  init_docs_scaffold.sh [project-root]

Initializes the project docs/ scaffold for codeguide documentation.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/codeguide_paths.sh"

PROJECT_ROOT_ABS="$(codeguide_resolve_project_root "$TARGET_ROOT")"
DOCS_DIR="$(codeguide_docs_root "$PROJECT_ROOT_ABS")"

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
ORCHESTRATION_DIR="$(codeguide_orchestration_root "$PROJECT_ROOT_ABS")"
ORCHESTRATION_TEMPLATES_DIR="$(codeguide_orchestration_templates_dir "$PROJECT_ROOT_ABS")"
POLICY_DIR="${DOCS_DIR}/policy"
ISSUES_DIR="${DOCS_DIR}/issues"
SHADOW_BUCKETS=(apps services packages infra data)
SHADOW_ARCHIVE_DIRS=(_deprecated _obsolete)
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "${TASK_DIR}" "${SHADOW_DIR}" "${DECISIONS_DIR}" "${PLAN_DIR}" "${REPORT_DIR}" "${ORCHESTRATION_DIR}" "${ORCHESTRATION_TEMPLATES_DIR}" "${POLICY_DIR}" \
  "${ISSUES_DIR}/current" "${ISSUES_DIR}/resolved" "${ISSUES_DIR}/templates"

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

write_if_missing "${PROJECT_ROOT_ABS}/AGENTS.md" '# Agent Router

- Treat `docs/` as the system of record.
- For non-trivial tasks, start from `docs/shadow/project-shadow.md`.
- Use `docs/task/task-index.md` for task state.
- Use `docs/plan/`, `docs/report/`, `docs/decisions/`, and `docs/orchestration/` for durable plans, reviews, decisions, and handoffs.
- Use Serena for semantic code navigation before broad file reads.
- Keep Mem0 disabled for now; later use it only for hints, preferences, and recent-work pointers.
- Verify tool or memory hints against direct source reads, tests, command output, or runtime evidence.
- Keep paths as code spans like `docs/...`; do not use import syntax for documentation paths.
- Do not store long plans, architecture dumps, secrets, or chat transcripts here.

## Operating Loop

1. Read this router.
2. Read `docs/shadow/project-shadow.md` for project navigation.
3. Read the relevant task, plan, decision, and report files.
4. Inspect current source files and tests before editing.
5. Update durable docs when behavior, architecture, APIs, or decisions change.
'

write_if_missing "${PROJECT_ROOT_ABS}/CLAUDE.md" '# Claude Router

- Treat `docs/` as the system of record.
- For non-trivial tasks, start from `docs/shadow/project-shadow.md`.
- Use `docs/task/task-index.md` for task state.
- Use `docs/plan/`, `docs/report/`, `docs/decisions/`, and `docs/orchestration/` for durable plans, reviews, decisions, and handoffs.
- Use Serena for semantic code navigation before broad file reads.
- Keep Mem0 disabled for now; later use it only for hints, preferences, and recent-work pointers.
- Verify tool or memory hints against direct source reads, tests, command output, or runtime evidence.
- Keep paths as code spans like `docs/...`; do not use `@docs/...` import syntax.
- Do not store long plans, architecture dumps, secrets, or chat transcripts here.

## Operating Loop

1. Read this router.
2. Read `docs/shadow/project-shadow.md` for project navigation.
3. Read the relevant task, plan, decision, and report files.
4. Inspect current source files and tests before editing.
5. Update durable docs when behavior, architecture, APIs, or decisions change.
'

write_if_missing "${POLICY_DIR}/shadow-validator-catalog.md" '# Shadow Validator Catalog

- catalog_id: shadow-validator-catalog
- catalog_version: 1
- status: active-draft
- template_linked_task: TASK-shadow-effect-map-01
- template_linked_decision: decision-shadow-validator-taxonomy-01
- template_lineage: codeguide built-in shadow v2 policy template; replace with local linked_task and linked_decision after project adoption
- purpose: Define which validators can support shadow fact promotion.
- last_updated: 2026-04-30T13:49:45Z

## Contract

- Validator ids must include category prefix and version suffix.
- A validator not listed here cannot produce a confirmed shadow fact.

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
    validates: Java call syntax exists at source anchor; confirmed evidence requires receiver binding
    limitations: [does_not_prove_runtime_execution, does_not_prove_overload_resolution]
  java.annotation.match@v1:
    evidence_type: annotation
    validates: Java annotation exists
    limitations: [does_not_prove_proxy_activation]
  js.ast.call_match@v1:
    evidence_type: code_call
    validates: JavaScript call syntax exists in .js, .jsx, .mjs, or .cjs source files
    limitations: [does_not_prove_runtime_execution, dynamic_dispatch_can_hide_target, excludes_dependency_build_coverage_and_test_paths]
  ts.ast.call_match@v1:
    evidence_type: code_call
    validates: TypeScript call syntax exists in .ts, .tsx, .mts, or .cts source files
    limitations: [does_not_prove_runtime_execution, type_declaration_only_rejected, typescript_generic_call_syntax_unsupported_v1, excludes_dependency_build_coverage_and_test_paths]
  ts.ast.call_match@v2:
    evidence_type: code_call
    validates: TypeScript call syntax exists in .ts, .tsx, .mts, or .cts source files, including generic call type arguments
    limitations: [does_not_prove_runtime_execution, type_declaration_only_rejected, type_argument_syntax_only, excludes_dependency_build_coverage_and_test_paths]
  py.ast.call_match@v1:
    evidence_type: code_call
    validates: Python call exists
    limitations: [dynamic_dispatch_can_hide_target]
  py.decorator.match@v1:
    evidence_type: annotation
    validates: Python decorator exists
    limitations: [dynamic_imports_can_hide_route_registration]
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
  react.jsx_event_binding@v1:
    evidence_type: code_reference
    validates: JSX event binding syntax metadata exists or is absent on a JSX element
    limitations: [syntax_only, no_react_import_binding_required, no_type_checking, no_semantic_event_handler_claim, writer_confirmed_promotion_unsupported]
  fastapi.route@v1:
    evidence_type: annotation
    validates: FastAPI route decorator exists
    limitations: [does_not_prove_app_mount, does_not_prove_dependency_success, decorator_syntax_only]
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

## Probe Implementation Coverage

```yaml
probe_coverage:
  probe_script: scripts/shadow_evidence_probe.py
  implemented_primary_v1: [py.ast.call_match@v1, py.decorator.match@v1, java.ast.call_match@v1, js.ast.call_match@v1, ts.ast.call_match@v1, ts.ast.call_match@v2, fastapi.route@v1, fastapi.dependency@v1, express.route@v1, react.effect_hook@v1, react.jsx_event_binding@v1, java.annotation.match@v1, spring_boot.request_mapping@v1, spring_boot.cache_evict.annotation@v1, jpa.repository.save@v1, any.runtime.trace@v1]
  parser_backed_now: [py.ast.call_match@v1, py.decorator.match@v1, java.ast.call_match@v1, js.ast.call_match@v1, ts.ast.call_match@v1, ts.ast.call_match@v2, fastapi.route@v1, fastapi.dependency@v1, express.route@v1, react.effect_hook@v1, react.jsx_event_binding@v1]
  source_probe_only: [java.annotation.match@v1, spring_boot.request_mapping@v1, spring_boot.cache_evict.annotation@v1, jpa.repository.save@v1]
  unsupported_behavior: unsupported_no_infer_no_write_no_promote
```
'

write_if_missing "${POLICY_DIR}/shadow-regex-patterns.md" '# Shadow Regex Pattern Registry

- registry_id: shadow-regex-patterns
- registry_version: 1
- status: active-draft
- template_linked_task: TASK-shadow-effect-map-01
- template_linked_decision: decision-shadow-regex-standard-01
- template_lineage: codeguide built-in shadow v2 policy template; replace with local linked_task and linked_decision after project adoption
- purpose: Define approved regex fallback patterns for shadow evidence discovery.
- last_updated: 2026-04-30T13:49:45Z

## Contract

- Regex ids must include a version suffix.
- Regex-only promotion is capped at low or medium.

```yaml
regex_patterns:
  java.regex.method_call_named@v1:
    pattern: java-call-pattern
    target: code_call
    allowed_paths: ["src/main/java/**"]
    excluded_paths: ["src/test/**", "build/**", "target/**"]
    validates: named Java call syntax appears
    cannot_validate: [runtime_execution, overload_resolution]
    max_promotion_risk: medium
  java.regex.repository_save_call@v1:
    pattern: java-repository-save-pattern
    target: code_call
    allowed_paths: ["src/main/java/**"]
    excluded_paths: ["src/test/**", "build/**", "target/**"]
    validates: repository save syntax appears
    cannot_validate: [transaction_success, downstream_listeners]
    max_promotion_risk: medium
  java.regex.annotation_named@v1:
    pattern: java-annotation-pattern
    target: annotation
    allowed_paths: ["src/main/java/**"]
    excluded_paths: ["src/test/**", "build/**", "target/**"]
    validates: named Java annotation syntax appears
    cannot_validate: [proxy_activation, runtime_behavior]
    max_promotion_risk: medium
  spring_boot.regex.request_mapping@v1:
    pattern: spring-request-mapping-pattern
    target: annotation
    allowed_paths: ["src/main/java/**"]
    excluded_paths: ["src/test/**", "build/**", "target/**"]
    validates: Spring request mapping annotation syntax appears
    cannot_validate: [route_reachable, security_allowed]
    max_promotion_risk: medium
  js.regex.call_named@v1:
    pattern: js-call-pattern
    target: code_call
    allowed_paths: ["src/**", "app/**", "lib/**", "server/**", "pages/**", "routes/**"]
    excluded_paths: ["node_modules/**", "**/node_modules/**", "dist/**", "**/dist/**", "build/**", "**/build/**", "coverage/**", "**/coverage/**", "test/**", "**/test/**", "tests/**", "**/tests/**", "__tests__/**", "**/__tests__/**", "**/*.test.*", "**/*.spec.*"]
    validates: named JavaScript call syntax appears
    cannot_validate: [runtime_execution, async_completion]
    max_promotion_risk: medium
  ts.regex.call_named@v1:
    pattern: ts-call-pattern
    target: code_call
    allowed_paths: ["src/**", "app/**", "lib/**", "server/**", "pages/**", "routes/**"]
    excluded_paths: ["node_modules/**", "**/node_modules/**", "dist/**", "**/dist/**", "build/**", "**/build/**", "coverage/**", "**/coverage/**", "test/**", "**/test/**", "tests/**", "**/tests/**", "__tests__/**", "**/__tests__/**", "**/*.test.*", "**/*.spec.*", "**/*.d.ts"]
    validates: named TypeScript call syntax appears
    cannot_validate: [runtime_execution, async_completion, type_declaration_only]
    max_promotion_risk: medium
  py.regex.call_named@v1:
    pattern: py-call-pattern
    target: code_call
    allowed_paths: ["**/*.py"]
    excluded_paths: ["tests/**", ".venv/**", "venv/**", "build/**"]
    validates: named Python call syntax appears
    cannot_validate: [runtime_execution, monkey_patch_target]
    max_promotion_risk: medium
  py.regex.decorator_named@v1:
    pattern: py-decorator-pattern
    target: annotation
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
- template_linked_task: TASK-shadow-effect-map-01
- template_linked_decisions: decision-shadow-practical-contract-01, decision-shadow-validator-taxonomy-01, decision-shadow-regex-standard-01
- template_lineage: codeguide built-in shadow v2 policy template; replace with local linked_task and linked_decisions after project adoption
- purpose: Map shadow rule ids to compatible validators, approved regex fallback patterns, risk floors, and promotion gates.
- last_updated: 2026-04-30T13:49:45Z

## Contract

- Rule ids not listed here cannot produce confirmed shadow facts.
- Regex fallback must reference shadow-regex-patterns.md.
- Regex-only promotion cannot exceed medium.

```yaml
rules:
  repo.write:
    allowed_effect_types: [db_write]
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
    allowed_effect_types: [cache_evict]
    validators_by_stack:
      spring_boot:
        annotation:
          primary: spring_boot.cache_evict.annotation@v1
          fallback: java.regex.annotation_named@v1
          fallback_max_risk: medium
      common:
        runtime_trace:
          primary: any.runtime.trace@v1
  external.call:
    allowed_effect_types: [external_call]
    validators_by_stack:
      node:
        code_call:
          primary: js.ast.call_match@v1
          fallback: js.regex.call_named@v1
          fallback_max_risk: medium
      typescript:
        code_call:
          primary: ts.ast.call_match@v2
          fallback: ts.regex.call_named@v1
          fallback_max_risk: medium
  security.auth:
    allowed_effect_types: [auth, auth_boundary, security_boundary]
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
    allowed_effect_types: [http_route, api_route]
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

## Superseded

## Cancelled

## Done
'

write_if_missing "${DECISIONS_DIR}/decision-index.md" '# Decision Index

## Proposed

## Accepted

## Superseded
'

write_if_missing "${SHADOW_DIR}/project-shadow.md" "# Project Shadow

- doc_role: router
- read_path: project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf
- fast_entry:
- bucket_links: apps/_index.md, services/_index.md, packages/_index.md, infra/_index.md, data/_index.md
- global_doc: _global.md
- last_updated: ${NOW_UTC}
- updated_by_task:
- latest_change_note:
"

write_if_missing "${SHADOW_DIR}/_global.md" "# Shadow Global

- doc_role: global
- shared_runtime_rules:
- shared_config_rules:
- naming_rules:
- cross_unit_integration_contracts:
- last_updated: ${NOW_UTC}
"

for bucket in "${SHADOW_BUCKETS[@]}"; do
  write_if_missing "${SHADOW_DIR}/${bucket}/_index.md" "# Shadow Bucket Index

- doc_role: bucket_index
- bucket: ${bucket}
- last_updated: ${NOW_UTC}

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
- claimed_at:
- due_date:
- axis_why:
- axis_where:
- axis_verify:
- resume_source_head:
- resume_changed_files:
- resume_checkpointed_at:
- resume_state_revision:
- resume_next_action:
- resume_last_verified:
- resume_blockers:
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

write_if_missing "${REPORT_DIR}/LLM-REVIEW-template.md" '# PLAN-<task-id>-v1.0 review (<runner>/<model-slug>)

- task_id: <task-id>
- plan_version: v1.0
- evaluator: <runner>
- evaluator_requested_model: <model-slug>
- evaluator_actual_model: <model-slug>
- evaluator_model_selection: preconfigured_runtime | cli_flag
- quota_fallback_triggered: false
- review_style: standard
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

write_if_missing "${ORCHESTRATION_TEMPLATES_DIR}/ORCH.md" '# ORCH-<task-id>

- task_id:
- execution_mode:
- primary_author_tool:
- review_mode:
- external_review_status:
- external_review_required_for:
- required_review_routes:
- external_review_round:
- external_review_result_ref:
- external_review_waiver_ref:
- external_review_waiver_reason:
- supervisor_agent:
- planner_agents:
- reviewer_agents:
- implementation_agents:
- validation_agents:
- owned_scopes:
- delegation_status:
- delegation_note:
- risk_preflight_status:
- risk_preflight_recorded_by:
- risk_preflight_summary:
- approval_required:
- approval_ref:
- approved_next_step:
- last_updated:

Allowed primary_author_tool values: antigravity | agy | claude | codex | human | external-runner.
Allowed review_mode values: external_cli | current_task_debate | agy_subagents | claude_subagents | codex_subagents.
Allowed external_review_status values: not_requested | requested | running | awaiting_response | ingested | blocked | waived.
Allowed external_review_required_for values: plan_acceptance | implementation_start | commit | close.
'

write_if_missing "${ORCHESTRATION_TEMPLATES_DIR}/prompt.md" '# Orchestration Prompt

- task_id:
- purpose:
- audience:
- expected_output:

## Why

## What

## How

## Where

## Verify
'

write_if_missing "${DOCS_DIR}/SECURITY-NOTES.md" '# Documentation Security Notes

- Never store raw key/token/password/private-key values in docs.
- Only reference environment variable names (example: PROVIDER_API_KEY).
- Redact sensitive values immediately if found.
'

write_if_missing "${ISSUES_DIR}/README.md" '# Runtime Issue Tracker

- purpose: Track runtime bugs and operational defects like GitHub issues, with a PR-like resolution record.
- owner: project maintainers.
- current_issues: `docs/issues/current/`
- resolved_issues: `docs/issues/resolved/`
- templates: `docs/issues/templates/`

## Roles

- auditor: the full-sweep inspection side. Finds defects, files issues, and verifies fixes. Does not implement fixes for issues it filed in the same pass.
- fixer: the implementation side. Picks up open issues, implements the fix, and writes the resolution document.
- One person or agent may hold different roles on different issues, but the fixer must not self-verify: verification evidence is produced against the running stack and checked by the auditor (or another verifier) before the issue is closed.

## Lifecycle (GitHub-issue / PR style)

1. **File** (auditor): create one markdown file per defect under `docs/issues/current/` from `templates/ISSUE-template.md`.
   - Use a stable ID: `ISSUE-YYYYMMDD-short-slug.md`. The ID never changes after filing.
   - Add one row to the index table in `current/README.md`.
   - Set `status: open`.
2. **Pick up** (fixer): set `owner:` to yourself and `status: investigating`. Record findings in `Current Hypothesis` as you go.
3. **Fix** (fixer): implement the fix, fill in `Resolution Notes`, set `status: fixed_pending_verify`.
4. **Verify** (auditor/verifier): run the commands in the `Verification` section against a running local stack. Record command output and evidence in the issue file.
5. **Close** (fixer, after verification passes):
   - Write `docs/issues/resolved/RESOLUTION-<same-id-without-ISSUE-prefix>.md` from `templates/RESOLUTION-template.md`. This is the PR-equivalent record: root cause, change summary, files changed, commits, verification evidence, residual risks.
   - Move the issue file from `current/` to `resolved/`, set `status: resolved`, fill `resolved_at:` and `resolution_doc:`.
   - Remove the issue row from `current/README.md` and add a row to `resolved/README.md`.
6. **Reopen** (anyone): if the defect recurs, move the issue file back to `current/`, set `status: reopened`, add a row back to `current/README.md`, and add a `Superseded` note at the top of the old resolution doc. File follow-up fixes as a new resolution doc revision (`-r02` suffix).

An issue is not resolved until both files exist in `resolved/`: the moved issue file and its resolution doc. Moving the issue without a resolution doc, or writing a resolution doc without verification evidence, is an incomplete close.

## Rules

- One defect per issue file. Split multi-defect findings into separate issues.
- Do not store secrets, raw API keys, account numbers, bearer tokens, cookies, or full environment dumps.
- Do not delete issue files. History lives in `resolved/`, not in deletion.
- Do not weaken safety gates to make a verification pass.
- Keep every status transition inside the issue file (`status:` field), and keep both index tables in sync with the folders.

## Status Values

- `open`: filed, no owner yet.
- `investigating`: fixer assigned and actively working.
- `blocked`: progress stopped; the blocker must be named in the issue body.
- `fixed_pending_verify`: fix landed, verification evidence not yet accepted.
- `resolved`: verified and closed; file lives in `resolved/`.
- `reopened`: defect recurred after a resolution; file is back in `current/`.

## Severity Guide

- critical: can cause destructive actions, data corruption, or secret exposure.
- high: blocks a core product path or causes materially wrong behavior.
- medium: degrades workflow, observability, or non-critical feature behavior.
- low: cosmetic, docs-only, or minor ergonomics.
'

write_if_missing "${ISSUES_DIR}/current/README.md" '# Current Runtime Issues

Open defects that must remain visible during development.

Index rules:

- Every file in this folder (except this README) has exactly one row here, and every row points at a file in this folder.
- The auditor adds the row when filing the issue; the fixer removes it when closing (the row moves to `../resolved/README.md`).
- Keep `Status` in sync with the `status:` field inside the issue file.

| ID | Severity | Status | Area | Title |
| --- | --- | --- | --- | --- |
'

write_if_missing "${ISSUES_DIR}/resolved/README.md" '# Resolved Runtime Issues

Closed defects with their PR-style resolution records.

Index rules:

- Every resolved issue appears here as one row, added by the fixer at close time.
- A close is complete only when this folder holds both files: the moved `ISSUE-*.md` (with `status: resolved`, `resolved_at:`, `resolution_doc:` filled) and its `RESOLUTION-*.md`.
- If an issue is reopened, remove its row from this table, move the issue file back to `../current/`, and mark the resolution doc as superseded; keep the resolution doc here for history.

| ID | Severity | Area | Resolved At | Resolution Doc | Title |
| --- | --- | --- | --- | --- | --- |
'

write_if_missing "${ISSUES_DIR}/templates/ISSUE-template.md" '# ISSUE-YYYYMMDD-short-slug

- title:
- status: open | investigating | blocked | fixed_pending_verify | resolved | reopened
- severity: critical | high | medium | low
- area:
- owner:
- created_at:
- last_seen_at:
- detected_by:
- related_files:
- related_endpoints:
- security_note:
- resolved_at: (fill at close)
- resolution_doc: (fill at close, e.g. RESOLUTION-YYYYMMDD-short-slug.md)

## Problem

Describe the user-visible failure and the exact system behavior.

## Evidence

- command:
- result:
- log_excerpt:
- screenshot:

## Impact

Describe affected workflows, data quality, and operational risk.

## Current Hypothesis

State what is believed to be wrong. Mark uncertain claims with `[uncertain]`.

## Non-Goals

State what should not be implemented while fixing this issue.

## Next Actions

- [ ] Reproduce on the running local stack.
- [ ] Isolate owner: config, network, dependency, backend, frontend, or data.
- [ ] Fix the root cause without weakening safety gates.
- [ ] Verify with real calls and user-visible flow.
- [ ] Update this issue with final evidence.

## Verification

Commands and user-visible checks required before resolving the issue.

## Resolution Notes

Fill after the fix lands.
'

write_if_missing "${ISSUES_DIR}/templates/RESOLUTION-template.md" '# RESOLUTION-YYYYMMDD-short-slug

- issue: ../resolved/ISSUE-YYYYMMDD-short-slug.md
- title:
- resolved_at:
- fixed_by:
- verified_by:
- commits:
- revision: r01

## Root Cause

State the actual defect that was fixed, not the symptom. If it differs from the Current Hypothesis in the issue, say how.

## Change Summary

Describe what was changed and why this fixes the root cause, like a PR description.

## Files Changed

- `path/to/file` - what changed and why.

## Verification Evidence

Copy the verification commands from the issue and their actual passing results on the running local stack.

- command:
- result:
- user_visible_check:
- screenshot:

## What Was Not Changed

Scope deliberately left out (matches the Non-Goals of the issue, plus anything discovered during the fix).

## Residual Risks

Remaining weaknesses, follow-up candidates, and any new issues filed as a result of this fix.

## Rollback

How to revert this fix if it causes a regression (commits to revert, config to restore).
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

- Docs live under the project root `docs/...`.
- The project root is the selected root; when invoked inside a git repository, scripts resolve it to the git root.
- Reusable skills projects are the narrow exception: if the resolved git root is a skill package with `SKILL.md` metadata, has no local `docs/`, and its parent already has `docs/`, scripts may use the parent as the system-of-record root.
- Do not create sibling `../docs`, `docs/<repo-name>`, or `docs/repos/<repo-name>` layers unless the user explicitly requests it.

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
- Declare rationale with the optional `linked_decisions` field on `unit_overview` and `concern_leaf` docs only: an inline comma list of repo-relative `docs/decisions/decision-<id>.md` capsules that currently govern the unit or concern. It is the "why" hop of the read path, taken only when the question is why; an absent or empty field is silent. Curate it (about five entries), do not accumulate history — `decision-index.md` is the full record. Advisory validation resolves each entry and warns on superseded targets; `scripts/shadow_rationale_report.py` derives the reverse direction on demand instead of storing backlinks. Field grammar and semantics live in the skill'"'"'s `references/shadow-system-contract.md`.

## Shadow freshness

- Refresh affected shadow graph docs for same-session implementation changes before closing the task.
- External git-driven shadow refresh happens only when the user explicitly requests shadow update.
- Keep shadow docs routing-oriented instead of mirroring large code blocks.

## Orchestration contract

- Main thread is the supervising lead architect, not the primary implementer.
- Run main-thread risk preflight before sub-agents, external reviewers, or ping-pong loops.
- If preflight finds a safety, privacy, permission, destructive-action, external-side-effect, sensitive-data, scope, or user-decision gate, stop before delegation/external review until the user approves the exact next step.
- Record `risk_preflight_status`, `risk_preflight_recorded_by`, `risk_preflight_summary`, `approval_required`, `approval_ref`, and `approved_next_step` in `orchestration/<task-id>/ORCH.md`.
- `risk_preflight_recorded_by` must identify the main-thread supervising lead architect, not evaluator/tool identity such as `external-runner`; `approved` requires `approval_required: true`, a concrete `approval_ref`, and a concrete `approved_next_step`.
- Active tasks require `orchestration/<task-id>/ORCH.md`.
- Default orchestration is `execution_mode: solo`; `execution_mode: supervisor_subagents` or delegated/external review fields are available only after the preflight gate allows delegation.
- Orchestration rules still apply in `docs-only` work.
- Record `primary_author_tool` and `review_mode` for plan review routing.
- Treat `서브에이전트`, `서브 에이전트`, `subagent`, `subagents`, `sub-agent`, and `sub-agents` as the same sub-agent trigger.
- If `execution_mode: solo` is used, `delegation_note` must explain why sub-agent delegation was not practical.
- In strict mode, supervising-lead-architect/sub-agent ownership fields must be populated for `supervisor_subagents`.

## Validation policy

- status/scope enum values are validated in both write phase and validation phase.
- Secret scan supports known key formats, quoted assignments, and yaml/env-style assignments.
- Add custom secret scan exclusions with --secret-scan-exclude-glob.

## Issue tracker contract

- Runtime defects are tracked like GitHub issues under `docs/issues/` (see `docs/issues/README.md` for the full lifecycle).
- The auditor (full-sweep inspection side) files issues in `docs/issues/current/` from `docs/issues/templates/ISSUE-template.md`; the fixer resolves them; the fixer must not self-verify.
- Closing an issue is PR-like: move the issue file to `docs/issues/resolved/`, write a paired `RESOLUTION-*.md` from `docs/issues/templates/RESOLUTION-template.md` with root cause, change summary, files changed, and verification evidence, and update both index READMEs.
- A close without a resolution doc, or a resolution doc without verification evidence from the running stack, is incomplete.
- Issue files are never deleted; history lives in `docs/issues/resolved/`. Recurred defects move back to `current/` with `status: reopened`.

## Docs lifecycle (no physical archive for task/plan/orchestration)

- Never physically move or archive `docs/task/TASK-*.md`, `docs/plan/PLAN-*.md`, or `docs/orchestration/<task-id>/`. Keep them flat under their project-root directories permanently, even after a task reaches `status: done`.
- `docs/task/task-index.md` is the single source of truth for task/plan/orchestration lifecycle state. A completed task is managed, not archived: its row stays under the correct status section (Planned/In Progress/Blocked/Done) and its `TASK-*.md`, `PLAN-*.md`, and `orchestration/<task-id>/ORCH.md` files stay exactly where they are.
- Do not create `plan-index.md` or any second ledger for plan files. Plan files are already keyed by `task_id` in their filename (`PLAN-<task-id>-vX.Y.md`), so `task-index.md` plus filename globbing is sufficient; a second index would drift from the first.
- `validate_docs.sh` enforces `task-index.md` accuracy in both directions: every `TASK-*.md` must have a row, every row must point at an existing task file listed under the section matching its actual `status:`, and no task_id may have duplicate rows.
- `docs/issues/` is the one exception: it physically moves files between `current/` and `resolved/` as part of its normal lifecycle (see Issue tracker contract above), because closing an issue produces a new `RESOLUTION-*.md` at that same moment. `validate_docs.sh` enforces `current/`<->`resolved/` pairing and index consistency the same way.
- Rationale: task/plan/orchestration files are cross-referenced by concrete literal paths from other docs (evaluator report rounds, `ORCH.md` fields such as `external_review_result_ref`, prose citations of prior round files). Physically moving them at scale silently breaks those citations in ways no validator catches. Keeping them flat and relying on index accuracy avoids that risk. A folder growing large is an accepted tradeoff; the goal is that work stays tracked and auditable, not that directories look tidy.

## Concurrent session claim contract

- When multiple agent sessions run against the same project at once, each session must atomically claim a task before setting `status: in_progress`: `mkdir docs/task/.claims/<task-id>/` (a bare directory; no contents required). `mkdir` fails if the directory already exists, so only one concurrent session can ever win the claim on a given task.
- If the `mkdir` fails, the task is already claimed by another session; do not start work on it, pick a different task instead.
- After a successful claim, set `owner:` (a session-identifying value, e.g. a short session id) and `claimed_at:` (ISO timestamp) on the `TASK-<id>.md` file, then move its `task-index.md` row to `In Progress`.
- On completing or abandoning the task, remove `docs/task/.claims/<task-id>/` in the same step that changes `status` away from `in_progress`.
- A stale claim (owner unresponsive, session crashed) is detected the same way any stale in_progress task is: `last_updated` ages past `--max-task-age-days`. Do not auto-release a stale claim; surface it to the user and let them confirm before another session takes over.
- Sub-agents spawned within a session inherit that session claim; they do not need their own claim directories.
- `validate_docs.sh` treats `owner`, `claimed_at`, and the claim directory as recommended (advisory-mode warning) for `in_progress` tasks, same tier as `risk_level`, so existing task corpora are not broken by adopting this contract. It always flags (strict-mode failure) a claim directory that has no matching task file, or that survives after its task leaves `in_progress`.

## Plan orchestration loop

- Create plan file first: project docs `plan/PLAN-<task-id>-v1.0.md`.
- Write evaluator report files in project docs `report/` with runner and model slug placeholders in the filename: `PLAN-<id>-<version>-review-<runner>-<model-slug>-rNN.md`.
- External CLI handoff files live under `orchestration/<task-id>/external-cli/<plan-version>/<round>/`.
- External CLI requests use metadata plus `Why`, `What`, `How`, `Where`, `Verify`, then payload; the command itself must name an explicit command-output path before the wrapper captures sanitized Markdown and parser-compatible bullet fields.
- Pass only a short instruction plus the request file path and command-output path to CLIs that can reliably read the request file; runners whose safe non-interactive mode cannot read workspace paths may receive the already-written request content on stdin while the Markdown request file remains the durable handoff contract.
- If the application platform sandbox blocks private workspace egress, request explicit user approval and rerun the same external CLI command through the user-approved unsandboxed path; record `platform_permission_blocked` only when that approval path is unavailable or still blocked.
- If a runner reports authentication failure inside the application platform, including `Not logged in`, `Please run /login`, `Failed to authenticate`, `Invalid authentication credentials`, or `API Error: 401`, treat it first as a sandbox/keychain permission boundary and rerun the same command through the user-approved unsandboxed path before asking the user to operate a terminal manually or log in.
- External CLI ping-pong runs only when explicitly approved with concrete approval provenance; if the user explicitly asks for sub-agent ping-pong review, interpret it as runtime sub-agent review mode instead.
- Mark high-risk work with `risk_level: high|critical` on the task or linked decision.
- Advisory validation warns when an active task omits `risk_level`.
- If a task or linked non-superseded decision is high-risk, strict validation requires one adversarial review pass with objection/counterproposal/rebuttal/residual_risk.
- For each revision, create a new versioned plan file (v1.1, v1.2, ...), do not overwrite old versions.
- Semi-automated external review must stop after collecting report docs and showing the user the result; it does not auto-create the next plan version.
- Do not use a fixed iteration count, token budget, or cost cap as the primary stop condition.
- Continue only while iterations produce new material evidence, reduce verified risk, fix a checked failure, improve validation, or move toward explicit acceptance criteria.
- Stop when acceptance criteria and required verification pass, no new material findings appear, the same failure repeats without new evidence, an off-goal loop is detected, scope expands beyond the approved goal, a hard gate applies, or user decision/approval is required.

## Anti-dump limits

- Keep shadow docs close to 200 lines and preferably at or below 300 lines.
- If a shadow doc exceeds 300 lines or stops narrowing the read path quickly, split it by concern instead of mirroring the underlying source file.
- docs/task/TASK-*.md <= 220 lines
- docs/decisions/decision-*.md <= 180 lines
- docs/orchestration/<task-id>/ORCH.md <= 180 lines

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

echo "Initialized project docs scaffold under: ${DOCS_DIR}"
echo "Repository root: ${PROJECT_ROOT_ABS}"
echo "Created directories:"
echo "  - ${TASK_DIR}"
echo "  - ${SHADOW_DIR}"
echo "  - ${DECISIONS_DIR}"
echo "  - ${PLAN_DIR}"
echo "  - ${REPORT_DIR}"
echo "  - ${ORCHESTRATION_DIR}"
echo "  - ${ISSUES_DIR}"
echo "Template files are created only when missing."
