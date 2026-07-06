# Docs System of Record

Use this reference to initialize and maintain agent-readable repository documentation.

For repeatable setup, run:
- `scripts/run_codeguide.sh <project-root> --mode auto`
- `scripts/init_docs_scaffold.sh <project-root>`
- `scripts/doc_garden.sh <project-root> --task-id <TASK_ID>`
- `scripts/validate_docs.sh <project-root> --mode advisory`
- `scripts/validate_docs.sh <project-root> --mode strict`

Default assumption:
- Do not require RAG or embedding for baseline operation.
- Use project docs files (`task`, `shadow`, `decisions`, `plan`, `report`, `orchestration`) as durable memory first.
- Default operation is zero-command for the user when docs lifecycle is justified; the agent runs docs lifecycle commands for material architecture, multi-file, cross-service, delegated, or durable planning work.
- Skip docs lifecycle commands for small direct answers and trivial edits unless the user explicitly requests documentation sync.
- Reusable skills projects are the only built-in docs-root exception: if a git root is itself a skill package with `SKILL.md` metadata, has no local `docs/`, and its parent has `docs/`, scripts may use the parent as the system-of-record root. Ordinary app/service repositories must keep docs inside their own project root.

## Data safety rules
- Empty values never overwrite existing non-empty fields during doc-gardening. Use `--allow-empty-overwrite` to explicitly clear a field.
- Axis values (Why/What/How/Where/Verify) are only written when explicitly provided; no generic defaults are injected.
- `task_id` inference priority: explicit `--task-id` > branch pattern (ABC-123 or numeric) > latest task file > timestamp fallback.
- `task-index.md` rows are placed under the correct status section (Planned/In Progress/Blocked/Done) and deduplicated.
- `validate_docs.sh --mode strict` enforces non-empty values for required fields, not just key existence.
- Freshness checks use `last_updated` field when available; fall back to file mtime only when the field is absent.
- Validation checks plan/report contracts:
  - active tasks (`in_progress|blocked|done`) require at least one `PLAN-<task-id>-v*.md`
  - evaluator reports must follow `PLAN-...-review-<runner>-<model-slug>-rNN.md`

## Change scope execution
- `run_codeguide.sh` supports `--change-scope docs-only|code-or-runtime` to control validation behavior.
- `docs-only` (default): runs docs lifecycle + docs validation only.
- `code-or-runtime`: additionally runs user-provided runtime commands via `--runtime-test-cmd`, `--runtime-lint-cmd`, `--runtime-e2e-cmd`.
- Runtime commands are never hardcoded; they must be passed as CLI options.

## Required structure

`<project-root>` is the selected project root; when invoked from inside a git repository, scripts resolve it to that repository root. Resolve docs to `<project-root>/docs`.

For reusable skills packages, `<project-root>` may be the parent workspace root when the skill package is intentionally shared through symlinks and the parent contains the project-level `docs/`.

```text
project-root/
├── docs/
    ├── task/
    ├── shadow/
    │   ├── project-shadow.md
    │   ├── _global.md
    │   ├── apps/
    │   │   └── _index.md
    │   ├── services/
    │   │   └── _index.md
    │   ├── packages/
    │   │   └── _index.md
    │   ├── infra/
    │   │   └── _index.md
    │   ├── data/
    │   │   └── _index.md
    │   ├── _deprecated/
    │   └── _obsolete/
    ├── decisions/
    ├── plan/
    ├── report/
    └── orchestration/
```

Create these project-root files if missing:
- `<project-root>/docs/task/project-dictionary.md`
- `<project-root>/docs/task/task-index.md`
- `<project-root>/docs/shadow/project-shadow.md`
- `<project-root>/docs/shadow/_global.md`
- `<project-root>/docs/shadow/apps/_index.md`
- `<project-root>/docs/shadow/services/_index.md`
- `<project-root>/docs/shadow/packages/_index.md`
- `<project-root>/docs/shadow/infra/_index.md`
- `<project-root>/docs/shadow/data/_index.md`
- `<project-root>/docs/decisions/decision-index.md`
- `<project-root>/docs/plan/PLAN-template.md`
- `<project-root>/docs/report/LLM-REVIEW-template.md`
- `<project-root>/docs/orchestration/_templates/ORCH.md`

## Orchestration Gate Template

Use one task capsule per delegated or externally reviewed task: `docs/orchestration/<task-id>/ORCH.md`.

```markdown
# ORCH-<task-id>

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
```

Allowed primary_author_tool values: antigravity | agy | claude | codex | human | external-runner.
Allowed review_mode values: external_cli | current_task_debate | agy_subagents | claude_subagents | codex_subagents.

`review_mode: claude_subagents` runs review/analysis natively inside Claude Code instead of an external CLI, with no involvement of `config/ai_model_registry.json` or external runner scripts. Select the sub-agent model tier from the task's `risk_level`: `high`/`critical` -> deep tier (`model: sonnet`); `low`/`medium`/unset -> fast tier (`model: haiku`); an explicit user request for deep or fast analysis overrides the `risk_level` default. Claude Code sub-agent spawning only selects a model (`sonnet` | `opus` | `haiku` | `fable`), not a separate reasoning-effort dial. Independent-scope sub-agents may run in parallel in a single message; record the tier used in `reviewer_agents`/`implementation_agents` (e.g., `claude-subagent:sonnet-deep`, `claude-subagent:haiku-fast`).
Allowed external_review_status values: not_requested | requested | running | awaiting_response | ingested | blocked | waived.
Allowed external_review_required_for values: plan_acceptance | implementation_start | commit | close.
Allowed orchestration lifecycle values: `execution_mode=supervisor_subagents|solo`, `delegation_status=planned|active|completed|blocked`, `risk_preflight_status=pass|approved|blocked|approval_required`, `approval_required=true|false`.

Run and record main-thread risk preflight before spawning sub-agents, invoking external reviewers, or starting ping-pong. Default orchestration is `execution_mode: solo`; delegated fields, external review fields, or `execution_mode: supervisor_subagents` require explicit preflight. If preflight is `blocked` or `approval_required`, stop before delegation/external review. Continue only when the status is `pass`, or when the user approves the exact next step and the status is `approved` with `approval_required: true`, a concrete `approval_ref`, and a concrete `approved_next_step`. External CLI review requires the `approved` form because it crosses an external-service boundary. `risk_preflight_recorded_by` must identify the main-thread supervising lead architect, not evaluator/tool identities such as `antigravity`, `agy`, `claude`, `codex`, `gemini`, `external-runner`, `external-review-wrapper`, or `external-cli*`.

External review await gate fields live in `ORCH.md`. `required_review_routes` uses registry colon routes such as `agy:current`; report and response file names use route slugs and must not be treated as canonical route ids. `external_review_result_ref` points at the round directory `docs/orchestration/<task-id>/external-cli/<plan-version>/<round>/`, whose `<plan-version>` must match the consumed plan version. For a plan-dependent transition, only `external_review_status: ingested` with a satisfied ingested guard, or `external_review_status: waived` with a satisfied waiver guard, passes; `not_requested`, `requested`, `running`, `awaiting_response`, `blocked`, missing, empty, or unknown status values warn in advisory mode. The ingested guard requires `required_review_routes` to be non-empty, comma-split parseable, non-placeholder, registry-resolvable, and for every listed route to have an inspectable accepted artifact with `verdict: accept` under the referenced round directory. Every "for every item" gate first proves the item set is non-empty, parseable, and well formed; empty, null, duplicate, placeholder, or unresolvable members fail the guard instead of satisfying it vacuously. The waiver guard requires non-placeholder `external_review_waiver_ref` and `external_review_waiver_reason`.

## Project dictionary template

`<project-root>/docs/task/project-dictionary.md`

```markdown
# Project Dictionary

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
```

## Task dictionary template

Use one file per task: `docs/task/TASK-<id>.md`

```markdown
# TASK-<id>

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
- consumes_plan_ref:
- status: planned | in_progress | blocked | done
- owner:
- claimed_at:
- due_date:
- axis_why: # principles applied (SOLID/DRY/KISS/YAGNI/LoD/SoC/CQS/POLA)
- axis_where: # structure and boundary choice
- axis_verify: # test strategy (TDD/pyramid/FIRST)
```

`<project-root>/docs/task/task-index.md` should list task ids organized by status section (Planned/In Progress/Blocked/Done). Rows are automatically moved between sections when task status changes.

`consumes_plan_ref` is required when the matching ORCH capsule sets `external_review_required_for: implementation_start` and the task is `in_progress` or `done`. It must reference a same-task plan in the form `PLAN-<task-id>-vX.Y`; cross-task plan consumption is out of scope for this gate and warns instead of being treated as independent.

## Docs lifecycle (no physical archive for task/plan/orchestration)

Never physically move or archive `docs/task/TASK-*.md`, `docs/plan/PLAN-*.md`, or `docs/orchestration/<task-id>/`, even after a task reaches `status: done`. Keep them flat permanently.

- `docs/task/task-index.md` is the single source of truth for task/plan/orchestration lifecycle state. A completed task is managed, not archived: its row stays under the correct status section and its `TASK-*.md`/`PLAN-*.md`/`orchestration/<task-id>/ORCH.md` files stay exactly where they are.
- Do not create `plan-index.md` or any second ledger for plan files. Plan files are already keyed by `task_id` via filename (`PLAN-<task-id>-vX.Y.md`), so `task-index.md` plus filename globbing is sufficient; a second index would drift from the first, reintroducing the exact staleness problem an index is meant to solve.
- `scripts/validate_docs.sh` enforces `task-index.md` accuracy in both directions: every `TASK-*.md` must have a row, every row must point at an existing task file listed under the section matching its actual `status:` field, and no task_id may appear more than once.
- `docs/issues/` (see `docs/issues/README.md` when a project has one) is the one exception that does physically move files, between `current/` and `resolved/`, because closing an issue produces a new `RESOLUTION-*.md` at that same moment — the move is a natural lifecycle event, not a later cleanup pass. `validate_docs.sh` enforces that pairing and index consistency the same way.
- Rationale: task/plan/orchestration files are cross-referenced by concrete literal paths from other docs (evaluator report rounds, `ORCH.md` fields such as `external_review_result_ref`, prose citations of prior round files by name). Physically moving them at scale silently breaks those citations in ways no validator catches. A folder growing large and looking cluttered is an accepted tradeoff — the goal of docs governance is that work stays tracked and auditable, not that directories look tidy.

## Concurrent session claim contract

When multiple Claude Code sessions run against the same project at once, use an atomic filesystem claim so two sessions cannot pick up the same task:

- Before setting `status: in_progress`, atomically claim the task: `mkdir docs/task/.claims/<task-id>/` (a bare directory, no contents required). `mkdir` fails if the directory already exists, so only one concurrent session ever wins the claim.
- If the `mkdir` fails, the task is already claimed by another session; pick a different task instead of starting work on it.
- After a successful claim, set `owner:` (a session-identifying value) and `claimed_at:` (ISO timestamp) on the task file, then move its `task-index.md` row to `In Progress`.
- On completing or abandoning the task, remove `docs/task/.claims/<task-id>/` in the same step that changes `status` away from `in_progress`.
- A stale claim (session crashed without releasing it) is detected the same way any stale in_progress task is: `last_updated` ages past the freshness threshold. Do not auto-release a stale claim; surface it to the user first.
- Sub-agents spawned within a session inherit that session claim; they do not need their own claim directories.
- `scripts/validate_docs.sh` treats `owner`, `claimed_at`, and the claim directory as recommended (advisory-mode warning) for `in_progress` tasks, the same tier as `risk_level`, so existing task corpora are not broken by adopting this contract. It always flags (strict-mode failure) a claim directory with no matching task file, or one that survives after its task leaves `in_progress`.

## Anti-dump policy (default recommended, strict in CI)
- Keep shadow docs close to 200 lines and preferably at or below 300 lines.
- If a shadow doc exceeds 300 lines or stops narrowing the read path quickly, split it by concern instead of mirroring the underlying source file.
- Keep each `docs/task/TASK-*.md` at or below 220 lines.
- Keep each `docs/decisions/decision-*.md` at or below 180 lines.
- Keep shadow docs routing-oriented and link to deeper docs instead of copying large text blocks.

Use:
- `scripts/validate_docs.sh <project-root> --mode advisory` for local warning mode
- `scripts/validate_docs.sh <project-root> --mode strict` for CI blocking mode

## Shadow graph contract

Use `<project-root>/docs/shadow/` as the canonical AI-facing routing layer for the project.

Shadow rules:
- Keep shadow docs in English.
- Keep shadow docs in Markdown only.
- Do not add JSON sidecars or empty concern placeholder files.
- Use topology-first typed buckets:
  - `apps`
  - `services`
  - `packages`
  - `infra`
  - `data`
- Use this default read path:
  - `project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf`
- Treat `_global.md` as an optional side path for cross-unit facts, not as a required read hop.
- Use unit `overview.md` as the day-one landing doc for detected units.
- Materialize concern leaf docs only when source evidence or an explicit task justifies them.
- Preserve old shadow paths with thin redirect shims and archive replaced bodies under `_deprecated` or `_obsolete`.

### Top Router Template

Use `<project-root>/docs/shadow/project-shadow.md` as the top router only.

```markdown
# Project Shadow

- doc_role: router
- read_path:
- fast_entry:
- bucket_links:
- global_doc:
- last_updated:
- updated_by_task:
- latest_change_note:
```

### Global Cross-Unit Template

Use `<project-root>/docs/shadow/_global.md` for cross-unit invariants only.

```markdown
# Shadow Global

- doc_role: global
- shared_runtime_rules:
- shared_config_rules:
- naming_rules:
- cross_unit_integration_contracts:
- last_updated:
```

### Bucket Registry Template

Use `<project-root>/docs/shadow/<bucket>/_index.md` for unit membership only.

```markdown
# Shadow Bucket Index

- doc_role: bucket_index
- bucket:
- last_updated:

## Units
- unit_id:
  - overview_doc:
  - secondary_tags:
```

### Unit Overview Template

Use `<project-root>/docs/shadow/<bucket>/<unit>/overview.md` as the landing doc plus concern router.

```markdown
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket:
- secondary_tags:
- unit_summary:
- owns:
- entrypoints:
- planned_concerns:
- next_docs:
- source_of_truth_paths:
- last_updated:
```

### Concern Leaf Template

Use a concern leaf doc for concrete facts only.

```markdown
# Shadow Concern

- doc_role: concern_leaf
- concern_id:
- canonical_for:
- source_of_truth_paths:
- change_hotspots:
- contracts_and_rules:
- next_split_trigger:
- last_updated:
```

### Effect Map Leaf Template

Use `doc_role: effect_map` only for shadow docs that record side-effect entries under the Shadow Effect Map Workflow Contract. Effect maps are concern-leaf style docs with a stricter writer gate; they must not replace routers, bucket indexes, unit overviews, or general navigation summaries.

```markdown
# Shadow Effects

- doc_role: effect_map
- generated_by: shadow_effect_writer.py
```

Confirmed deterministic entries must render only after the writer re-checks registry compatibility, policy-declared rule-to-effect compatibility, current artifact identity, a matching probe-result artifact path/hash, and its own probe rerun from structured `probe_args`. Code evidence records include `evidence_rule_id`, `evidence_ref`, `evidence_source_ref`, `evidence_source_hash`, `evidence_probe_result_ref`, and `evidence_probe_result_hash`; runtime evidence records include `evidence_ref`, `evidence_trace_ref`, `evidence_artifact_hash`, `evidence_probe_result_ref`, and `evidence_probe_result_hash`. User-decision evidence records require a separate affirmative fact-evidence decision bound to the record id, effect type, statement hash, and anchor; write-mode final apply decisions are authorization only and must bind the exact target file plus record content hash fields.

### Redirect Shim Template

Use a thin redirect shim at the legacy path when a shadow doc moves.

```markdown
# Shadow Redirect

- doc_role: redirect_shim
- legacy_path:
- canonical_path:
- redirects_fact_scope:
- deprecated_since:
- status: redirected
- edit_policy: read_only
- replacement_reason:
- last_updated:
```

Purpose:
- Allow agents to understand the project quickly without scanning many source files.
- Keep the shadow graph routing-oriented instead of source-mirroring.
- Keep cross-unit facts, unit routing, and leaf facts in separate homes.
- Keep deep and verbose content in linked docs; keep shadow concise and map-like.

## Decision template

Use one file per decision: `docs/decisions/decision-<id>.md`

```markdown
# decision-<id>

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
- axis_why: # principle rationale
- axis_what: # expression rules (naming/function/comments/format)
- axis_how: # implementation approach (pattern/refactor/smell)
- axis_where: # structural placement and boundaries
- axis_verify: # verification strategy and test evidence
```

`<project-root>/docs/decisions/decision-index.md` should organize decisions by status section (Proposed/Accepted/Superseded). Rows are automatically moved between sections when decision status changes. Legacy table format is auto-migrated on first update.

## Plan and model-review templates

Use one file per plan version: `docs/plan/PLAN-<task-id>-v<major>.<minor>.md`

```markdown
# PLAN-<task-id>-v1.0

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
```

Use one file per evaluator report:
`docs/report/PLAN-<task-id>-v<major>.<minor>-review-<runner>-<model-slug>-r<nn>.md`

Evaluator label is the actual runner id, such as `agy` or `claude`, from `config/ai_model_registry.json`.
External CLI model selection is `preconfigured_runtime`: the wrapper records the requested route but uses the model already selected in the runner runtime.

```markdown
# PLAN-<task-id>-v1.0 review (<runner>/<route>)

- task_id: <task-id>
- plan_version: v1.0
- evaluator: <runner>
- evaluator_requested_runner: <runner>
- evaluator_actual_runner: <runner>
- evaluator_requested_route: <runner:model-route>
- evaluator_actual_route: <runner:model-route>
- evaluator_requested_model: <runner:model-route>
- evaluator_actual_model: <runner:model-route>
- evaluator_requested_cli_model: <cli-model>
- evaluator_actual_cli_model: <cli-model>
- evaluator_model_selection: preconfigured_runtime
- quota_fallback_triggered: false
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
```

## PR and commit standards
- For PR-based delivery, use the canonical templates in:
  - `references/git-pr-commit-templates.md`
- Apply both:
  - PR description template (`## ✨ PR Summary` ... `## 🙋 Reviewer Notes`)
  - Commit message template (`<type>: <short summary>` with `Why/What changed/Impact/Refs`)

## Update rules
- Update docs for every task without exception.
- Before implementation, create an initial plan file (usually `v1.0`).
- For each feedback round, write evaluator-specific report files in `docs/report/` with runner route slug in the filename: `PLAN-<id>-<version>-review-<runner>-<model-slug>-rNN.md`.
- Set `risk_level: high|critical` on the task or a linked decision when the change is high risk.
- Record `risk_preflight_status`, `risk_preflight_recorded_by`, `risk_preflight_summary`, `approval_required`, `approval_ref`, and `approved_next_step` before delegated or external review work begins; `pass` pairs with `approval_required: false`, and `approved` pairs with `approval_required: true`.
- In advisory mode, active tasks without `risk_level` should emit a warning so teams can backfill the signal before strict policy tightens.
- If a task or any linked non-superseded decision has `risk_level: high|critical`, strict validation requires at least one adversarial evaluator report with `review_style: adversarial` plus `objection`, `counterproposal`, `rebuttal`, and `residual_risk`.
- When improving the plan, create a new versioned plan file (for example `v1.1`) instead of overwriting previous files.
- Repeat plan -> review -> revision until execution-ready, no new material findings appear, a hard gate blocks progress, or user stop. Do not use fixed iteration count, token budget, or cost cap as the primary stop condition.
- When user chooses any option, update or create a `decision-*` file immediately.
- Apply this to all work types: task, hotfix, PR, release, incident, and operations.
- When plan changes, append revised `implementation_plan` in the same `decision-*`.
- When task scope changes, update `TASK-*` and relevant dictionary keys.
- For tiny edits, reuse the current `TASK-*` file instead of creating unnecessary new task files.
- At task close, refresh the affected shadow router, `_global.md` when applicable, bucket indexes, unit overviews, and leaf docs.
- Keep 5-axis fields current:
  - tasks: maintain `axis_why`, `axis_where`, `axis_verify`.
  - decisions: maintain full `axis_why`, `axis_what`, `axis_how`, `axis_where`, `axis_verify`.
- Keep freshness SLA:
  - same-session changes should refresh the affected shadow graph entries in the same implementation change.
  - external git-driven changes should refresh shadow only on explicit user request.
  - `in_progress` task docs should be refreshed within 7 days.
  - `decision-index.md` should be updated in the same change as decision files.

## Hotfix exception policy
- At urgent release time, allow minimum required docs:
  - one `decision-*` with selected option, risk, and scope `hotfix`
  - one linked task status update
- Complete full task and affected shadow updates within 24 hours after release.

## Secret and sensitive data rules
- Never put raw secrets in docs.
- Never put key/token/password/private key values in docs.
- In docs, reference only variable names such as `PROVIDER_API_KEY`, `DB_PASSWORD`, `JWT_SECRET`.
- If sensitive data is accidentally documented, redact immediately and log remediation in `docs/decisions`.
