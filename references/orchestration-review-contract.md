# Orchestration Review Contract

Use this reference for the delegation/review capsule and the project, plan, and evaluator-report templates: the ORCH gate template and its allowed values, preflight pairing rules, external-review await-gate field semantics, the project dictionary template, plan and evaluator-report templates, and the PR/commit template pointer. See `references/orchestration-contract.md` for the behavioral orchestration rules these templates back.

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

`review_mode: claude_subagents` runs review/analysis natively inside Claude Code instead of an external CLI, with no involvement of `config/ai_model_registry.json` or external runner scripts. Select the sub-agent model tier from the task's `risk_level`: `high`/`critical` -> deep tier (`model: sonnet`); `low`/`medium`/unset -> fast tier (`model: haiku`); an explicit user request for deep or fast analysis overrides the `risk_level` default. Claude Code sub-agent spawning only selects a model (`sonnet` | `opus` | `haiku` | `fable`), not a separate reasoning-effort dial. Independent-scope sub-agents may run in parallel in a single message; record the tier used in `reviewer_agents`/`implementation_agents` (e.g., `claude-subagent:sonnet-deep`, `claude-subagent:haiku-fast`). A project may define a role-routing policy in its own governance docs that supersedes this `risk_level` tier default inside full role-split pipelines (a standing user-approved override recorded in that project's decision log); when one applies, record the applied policy and the selected role assignment in `ORCH.md` (`delegation_note`), and keep this tier default for review legs outside such pipelines.
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
External CLI model selection is runner-specific: provenance records `preconfigured_runtime` when the runner's current model is used and `cli_flag` when the registry's `cli_model` is passed through a documented per-call flag.

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
- evaluator_model_selection: preconfigured_runtime | cli_flag
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

Adversarial-report field rule (`review_style: adversarial`): `objection`, `counterproposal`, and `rebuttal` must be non-empty in strict mode when the verdict is `revise` or `blocked` — a reviewer pushing back must show the debate. On `verdict: accept` the three fields must still exist but may stay empty: a reviewer who accepts has no objection to state, and reviewer artifacts are immutable, so the validator accepts the coherent case instead of forcing post-hoc edits. `residual_risk` is required non-empty in strict mode regardless of verdict — even an accept must name what it did not cover.

## PR and commit standards
- For PR-based delivery, use the canonical templates in:
  - `references/git-pr-commit-templates.md`
- Apply both:
  - PR description template (`## ✨ PR Summary` ... `## 🙋 Reviewer Notes`)
  - Commit message template (`<type>: <short summary>` with `Why/What changed/Impact/Refs`)
