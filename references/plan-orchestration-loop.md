# Plan Orchestration Loop

Extracted verbatim from SKILL.md for Phase 1 coverage audit; SKILL.md retains the original until Phase 2.

## Plan Orchestration Loop
1. The supervising lead architect performs risk preflight before orchestration begins. If approval is required, stop before sub-agent or external-review work and ask the user for approval; only continue after approval is granted.
2. The supervising lead architect creates or delegates the initial plan doc at project docs `docs/plan/PLAN-<task-id>-v1.0.md`.
3. Planning sub-agent drafts the plan; review sub-agent(s) critique it and write one report per evaluator in project `docs/report/`:
   - evaluator is the actual runner (`agy`, `claude`, etc.); reports are named by route slug (e.g. `PLAN-<id>-<version>-review-<runner>-<model-slug>-rNN.md`)
   - requested/actual runner, route, CLI model, and model-selection mode are recorded in the report; quota exhaustion stops for user-directed model switching
   - reviewer and evaluator tracks both default to defect-seeking review rather than approval-seeking review; prioritize logical gaps, weak assumptions, missing verification, understated risks, contract mismatches, and team-convention violations over praise
   - keep critical review evidence-based: prefer concrete defects, violated rules, and missing safeguards over vague negativity
   - do not require exact command phrases for stronger scrutiny; infer review intensity from task context, user wording, and risk level
   - treat natural-language signals such as `비판적으로`, `논리오류`, `논리 허점`, `허점`, `구멍`, `문제점 위주`, `빡세게`, `가차없이`, `critical`, and `harsh review` as requests for stronger critical scrutiny
   - `execution_mode: supervisor_subagents` tasks must have at least one evaluator report before strict handoff
   - when the task or any linked decision sets `risk_level: high|critical`, require one adversarial review pass before strict handoff; this pass assumes the initial plan is wrong and records `objection`, `counterproposal`, `rebuttal`, and `residual_risk`
   - when explicitly approved external CLI ping-pong is requested, the primary author tool writes the plan and the other two tools review it
   - if a task or linked decision is high-risk and the operator does not explicitly pick an adversarial evaluator, external CLI ping-pong should auto-select one of the non-primary reviewers for the adversarial pass
   - if the user explicitly requests ping-pong review with sub-agents (including the alias forms listed in the orchestration contract), external reviewers default to the registry's `default_reviewer_aliases` unless the user specifies route aliases with `--reviewer`
   - when invoking external ping-pong, the primary author model should differ from the reviewer routes; accepted shortcuts are the aliases declared in `config/ai_model_registry.json` or `CODEGUIDE_MODEL_REGISTRY`
4. The supervising lead architect consolidates feedback into the next versioned plan file without overwriting old versions:
   - version examples: `v1.1`, `v1.2`, `v2.0`
5. Repeat the sub-agent review/revision loop only while it is improving correctness or risk reduction. Stop when one of these conditions is met:
   - plan is acceptable for execution
   - user explicitly asks to stop
   - another review loop is unlikely to change the decision materially
   - semi-automated external review mode must stop after collecting report docs and showing the user the results; it must not auto-create the next plan version
   - external CLI ping-pong should use Markdown request/response files for tool handoff, use each tool's default model unless the operator explicitly overrides it, and avoid hardcoded model-version strings
   - fixed iteration count, token budget, and cost cap are not primary stop conditions; use `Goal Loop Contract` hard stops instead
6. When delegated implementation begins, coding sub-agents own disjoint code scopes while the supervising lead architect tracks the selected plan version in related `decision-*` and `TASK-*` docs.
   - for `codeguide`-invoked code writing work that explicitly requests sub-agents, prefer a standard four-track split when practical: planner, reviewer/evaluator, implementation, validation
   - before plan-dependent implementation starts, run `scripts/validate_docs.sh <project-root> --mode advisory`; if the external-review await gate emits a WARN for the consumed plan, treat that WARN as a stop signal and wait for an accepted external review or an explicit waiver
   - when ORCH sets `external_review_required_for: implementation_start`, the matching active TASK must declare a same-task `consumes_plan_ref`; deleting that field is not a valid way to claim independence
   - parallel or post-hoc work remains allowed only when ORCH does not require an implementation-start review gate for the current task
7. At task close, ensure the final architecture/runtime state is reflected in the affected `docs/shadow/` router, `_global.md` when applicable, bucket indexes, unit overviews, and leaf docs.
