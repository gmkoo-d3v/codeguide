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
Allowed review_mode values: external_cli | current_task_debate | agy_subagents | claude_subagents | codex_subagents. This enum governs the `ORCH.md` field only, and that field records the routing path. Review request artifacts have independently used a same-named field for an unrelated thing — the review's stance, with values such as `critical` or `adversarial_external_llm` sitting beside `requested_stance`/`verdict_values` — which is not drawn from this enum and is not validated against it. Treat them as two different fields that happen to share a word: comparing a capsule's `review_mode` against a round artifact's is meaningless, and reading one as the other has already produced false findings.

`review_mode: claude_subagents` runs review/analysis natively inside Claude Code instead of an external CLI, with no involvement of `config/ai_model_registry.json` or external runner scripts. Select the sub-agent model tier from the task's `risk_level`: `high`/`critical` -> deep tier (`model: sonnet`); `low`/`medium`/unset -> fast tier (`model: haiku`); an explicit user request for deep or fast analysis overrides the `risk_level` default. Claude Code sub-agent spawning only selects a model (`sonnet` | `opus` | `haiku` | `fable`), not a separate reasoning-effort dial. Independent-scope sub-agents may run in parallel in a single message; record the tier used in `reviewer_agents`/`implementation_agents` (e.g., `claude-subagent:sonnet-deep`, `claude-subagent:haiku-fast`). A project may define a role-routing policy in its own governance docs that supersedes this `risk_level` tier default inside full role-split pipelines (a standing user-approved override recorded in that project's decision log); when one applies, record the applied policy and the selected role assignment in `ORCH.md` (`delegation_note`), and keep this tier default for review legs outside such pipelines.
Allowed external_review_status values: not_requested | requested | running | awaiting_response | ingested | blocked | waived.
Allowed external_review_required_for values: plan_acceptance | implementation_start | commit | close.
Allowed orchestration lifecycle values: `execution_mode=supervisor_subagents|solo`, `delegation_status=planned|active|completed|blocked`, `risk_preflight_status=pass|approved|blocked|approval_required`, `approval_required=true|false`.

Run and record main-thread risk preflight before spawning sub-agents, invoking external reviewers, or starting ping-pong. Default orchestration is `execution_mode: solo`; delegated fields, external review fields, or `execution_mode: supervisor_subagents` require explicit preflight. If preflight is `blocked` or `approval_required`, stop before delegation/external review. Continue only when the status is `pass`, or when the user approves the exact next step and the status is `approved` with `approval_required: true`, a concrete `approval_ref`, and a concrete `approved_next_step`. External CLI review requires the `approved` form because it crosses an external-service boundary. `risk_preflight_recorded_by` must identify the main-thread supervising lead architect, not evaluator/tool identities such as `antigravity`, `agy`, `claude`, `codex`, `gemini`, `external-runner`, `external-review-wrapper`, or `external-cli*`.

External review await gate fields live in `ORCH.md`. `required_review_routes` uses registry colon routes such as `agy:current`; report and response file names use route slugs and must not be treated as canonical route ids. `external_review_result_ref` points at the round directory `docs/orchestration/<task-id>/external-cli/<plan-version>/<round>/`, whose `<plan-version>` must match the consumed plan version. For a plan-dependent transition, only `external_review_status: ingested` with a satisfied ingested guard, or `external_review_status: waived` with a satisfied waiver guard, passes; `not_requested`, `requested`, `running`, `awaiting_response`, `blocked`, missing, empty, or unknown status values fail the gate (a WARN in advisory mode, a FAIL in strict mode and in the fail-closed gate below). The ingested guard requires `required_review_routes` to be non-empty, comma-split parseable, non-placeholder, registry-resolvable, and for every listed route to have a complete wrapper-generated evidence set under the referenced round directory — a file that merely says `verdict: accept` is not evidence. The set is the accepted response with every parser-compatible review field (adversarial reviews add `objection`/`counterproposal`/`rebuttal`/`residual_risk`), the companion request file, and the `run_external_plan_reviews.sh` provenance manifest (`<slug>.response.provenance.md`, or the `retry-*` trio after a retry) whose `task_id`, `plan_version`, `review_round`, requested and actual route, verdict, recorded request/response/raw-capture file names, and `response_sha256` (recomputed from the response bytes) all agree with the consumed plan, the round and the route, with no quota fallback and the raw capture deleted; `scripts/validate_docs_review_evidence.py` is the authority and reports the first mismatch as the reason. Recorded paths are compared by their `<task>/external-cli/<plan-version>/<round>/<file>` tail so genuine artifacts survive a moved or cloned project. This is consistency evidence, not tamper-proof attestation: a writable workspace can still forge a matching triple, so a review that must resist tampering needs an external signing or audit mechanism. Every "for every item" gate first proves the item set is non-empty, parseable, and well formed; empty, null, duplicate, placeholder, or unresolvable members fail the guard instead of satisfying it vacuously. The waiver guard is a user-decision check, not a string check: `external_review_waiver_reason` must be concrete and `external_review_waiver_ref` must resolve to an existing `docs/decisions/decision-<id>.md` (a direct child of `docs/decisions/`, not a symlink) that is `status: accepted`, `chosen_by: user`, and `linked_task: TASK-<task-id>`; free text, a missing file, another task's decision, or a decision recorded by anyone but the user does not waive.

Enforcement tiers. Document checks (`validate_docs.sh --mode advisory|strict`): an `in_progress` task that enters the gate is evaluated in both modes with the full evidence verification; a `done` task is evaluated in advisory mode only, with the earlier verdict-level reading and string-level waiver check, because a closed task's evidence is immutable history and is not re-measured against rules introduced after it closed (the same precedent as the orchestration size cap). The gate keys on the primary status token, so a parenthetical note on `status` cannot bypass it. Fail-closed gate: `validate_docs.sh <project-root> --gate external-review [--task-id <id>]` evaluates only this gate, ignores every unrelated document finding, and exits 0 (not required, or satisfied) or 1 (required and not satisfied, or not verifiable); with `--task-id` it answers for that task whatever its stored status because the transition is requested before the status moves (an already closed task has no transition left unless `--to-status <status>` names a different status, i.e. a reopen, so re-syncing a historical task keeps working), without it for every `in_progress` task; `--format json` keeps the same exit code. `run_codeguide.sh` runs it before any docs mutation or runtime command whenever the run sets `--task-status in_progress` or `done`, and refuses with `[BLOCKED]` and exit 1 when it fails; planning-only runs (`planned`, `blocked`) are not gated, and a task with no `implementation_start` requirement passes silently. Ordinary advisory warnings elsewhere stay non-fatal.

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

Adversarial-report field rule (`review_style: adversarial`): `objection`, `counterproposal`, and `rebuttal` must be non-empty in strict mode when the verdict is `revise` or `blocked` — a reviewer pushing back must show the debate. On `verdict: accept` the three fields must still exist but may stay empty: a reviewer who accepts has no objection to state, and reviewer artifacts are immutable, so the validator accepts the coherent case instead of forcing post-hoc edits. `residual_risk` is required non-empty in strict mode regardless of verdict — even an accept must name what it did not cover. `run_external_plan_reviews.sh` applies the same rule when it parses an adversarial reviewer response, and the Shadow v2 close gate (`shadow_v2_gate_skeleton.py`) applies it to the accepted external response, reading each key on its own line: a missing key is malformed on every verdict, while present-but-empty debate fields are accepted on `accept`.

## PR and commit standards
- For PR-based delivery, use the canonical templates in:
  - `references/git-pr-commit-templates.md`
- Apply both:
  - PR description template (`## ✨ PR Summary` ... `## 🙋 Reviewer Notes`)
  - Commit message template (`<type>: <short summary>` with `Why/What changed/Impact/Refs`)
