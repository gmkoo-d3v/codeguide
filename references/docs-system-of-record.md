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
- Use workspace docs files (`task`, `shadow`, `decisions`, `plan`, `report`, `orchestration`) as durable memory first.
- Default operation is zero-command for user; agent runs docs lifecycle commands.

## Data safety rules
- Empty values never overwrite existing non-empty fields during doc-gardening. Use `--allow-empty-overwrite` to explicitly clear a field.
- Axis values (Why/What/How/Where/Verify) are only written when explicitly provided; no generic defaults are injected.
- `task_id` inference priority: explicit `--task-id` > branch pattern (ABC-123 or numeric) > latest task file > timestamp fallback.
- `task-index.md` rows are placed under the correct status section (Planned/In Progress/Blocked/Done) and deduplicated.
- `validate_docs.sh --mode strict` enforces non-empty values for required fields, not just key existence.
- Freshness checks use `last_updated` field when available; fall back to file mtime only when the field is absent.
- Validation checks plan/report contracts:
  - active tasks (`in_progress|blocked|done`) require at least one `PLAN-<task-id>-v*.md`
  - evaluator reports must follow `PLAN-...-review-(gemini|claude|codex)-rNN.md`

## Change scope execution
- `run_codeguide.sh` supports `--change-scope docs-only|code-or-runtime` to control validation behavior.
- `docs-only` (default): runs docs lifecycle + docs validation only.
- `code-or-runtime`: additionally runs user-provided runtime commands via `--runtime-test-cmd`, `--runtime-lint-cmd`, `--runtime-e2e-cmd`.
- Runtime commands are never hardcoded; they must be passed as CLI options.

## Required structure

`<project-root>` is the repository root. Resolve docs to `<project-root>/../docs`.

```text
workspace-root/
├── <repo>/
└── docs/
    ├── task/
    ├── shadow/
    ├── decisions/
    ├── plan/
    ├── report/
    └── orchestration/
```

Create these workspace-root files if missing:
- `<workspace-root>/docs/task/project-dictionary.md`
- `<workspace-root>/docs/task/task-index.md`
- `<workspace-root>/docs/shadow/project-shadow.md`
- `<workspace-root>/docs/decisions/decision-index.md`
- `<workspace-root>/docs/plan/PLAN-template.md`
- `<workspace-root>/docs/report/LLM-REVIEW-template.md`
- `<workspace-root>/docs/orchestration/ORCH-template.md`

## Project dictionary template

`<workspace-root>/docs/task/project-dictionary.md`

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
- status: planned | in_progress | blocked | done
- owner:
- due_date:
- axis_why: # principles applied (SOLID/DRY/KISS/YAGNI/LoD/SoC/CQS/POLA)
- axis_where: # structure and boundary choice
- axis_verify: # test strategy (TDD/pyramid/FIRST)
```

`<workspace-root>/docs/task/task-index.md` should list task ids organized by status section (Planned/In Progress/Blocked/Done). Rows are automatically moved between sections when task status changes.

## Anti-dump policy (default recommended, strict in CI)
- Keep `<workspace-root>/docs/shadow/project-shadow.md` at or below 220 lines.
- Keep each `docs/task/TASK-*.md` at or below 220 lines.
- Keep each `docs/decisions/decision-*.md` at or below 180 lines.
- Keep shadow map summary-only and link to deeper docs instead of copying large text blocks.

Use:
- `scripts/validate_docs.sh <project-root> --mode advisory` for local warning mode
- `scripts/validate_docs.sh <project-root> --mode strict` for CI blocking mode

## Shadow system-map template

Use `<workspace-root>/docs/shadow/project-shadow.md` as the canonical project system map.

```markdown
# Project Shadow

- project_summary:
- domain_glossary:
- module_map:
- navigation_map_to_detailed_docs:
- runtime_entrypoints:
- integration_map:
- config_map: # variable names only; no values
- current_risks:
- known_constraints:
- last_updated:
- updated_by_task:
```

Purpose:
- Allow agents to understand the project quickly without scanning many source files.
- Keep project-level meaning and structure centralized and current.
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

`<workspace-root>/docs/decisions/decision-index.md` should organize decisions by status section (Proposed/Accepted/Superseded). Rows are automatically moved between sections when decision status changes. Legacy table format is auto-migrated on first update.

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
`docs/report/PLAN-<task-id>-v<major>.<minor>-review-<evaluator>-r<nn>.md`

Evaluator label must be one of:
- `gemini`
- `claude`
- `codex`

```markdown
# PLAN-<task-id>-v1.0 review (gemini)

- task_id:
- plan_version: v1.0
- evaluator: gemini
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
- For each feedback round, write evaluator-specific report files in `docs/report/` with evaluator labels `gemini|claude|codex`.
- Set `risk_level: high|critical` on the task or a linked decision when the change is high risk.
- In advisory mode, active tasks without `risk_level` should emit a warning so teams can backfill the signal before strict policy tightens.
- If a task or any linked non-superseded decision has `risk_level: high|critical`, strict validation requires at least one adversarial evaluator report with `review_style: adversarial` plus `objection`, `counterproposal`, `rebuttal`, and `residual_risk`.
- When improving the plan, create a new versioned plan file (for example `v1.1`) instead of overwriting previous files.
- Repeat plan -> review -> revision until execution-ready or user stop.
- When user chooses any option, update or create a `decision-*` file immediately.
- Apply this to all work types: task, hotfix, PR, release, incident, and operations.
- When plan changes, append revised `implementation_plan` in the same `decision-*`.
- When task scope changes, update `TASK-*` and relevant dictionary keys.
- For tiny edits, reuse the current `TASK-*` file instead of creating unnecessary new task files.
- At task close, refresh `<workspace-root>/docs/shadow/project-shadow.md` and keep it aligned with latest architecture and flows.
- Keep 5-axis fields current:
  - tasks: maintain `axis_why`, `axis_where`, `axis_verify`.
  - decisions: maintain full `axis_why`, `axis_what`, `axis_how`, `axis_where`, `axis_verify`.
- Keep freshness SLA:
  - `<workspace-root>/docs/shadow/project-shadow.md` should be updated on every meaningful change and at least once every 7 days.
  - `in_progress` task docs should be refreshed within 7 days.
  - `decision-index.md` should be updated in the same change as decision files.

## Hotfix exception policy
- At urgent release time, allow minimum required docs:
  - one `decision-*` with selected option, risk, and scope `hotfix`
  - one linked task status update
- Complete full task and shadow updates within 24 hours after release.

## Secret and sensitive data rules
- Never put raw secrets in docs.
- Never put key/token/password/private key values in docs.
- In docs, reference only variable names such as `OPENAI_API_KEY`, `DB_PASSWORD`, `JWT_SECRET`.
- If sensitive data is accidentally documented, redact immediately and log remediation in `docs/decisions`.
