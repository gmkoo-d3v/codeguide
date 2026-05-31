# Orchestration Contract

Extracted verbatim from SKILL.md for Phase 1 coverage audit; SKILL.md retains the original until Phase 2.

## Orchestration Contract
- Main thread acts as the supervising lead architect and workflow supervisor: gather requirements, choose delegation boundaries, own architectural direction, monitor progress, integrate outcomes, and make final safety/quality decisions.
- Run risk preflight in the main thread before spawning sub-agents, invoking external reviewers, or starting any ping-pong loop.
- If risk preflight finds a safety, privacy, permission, destructive-action, external-side-effect, sensitive-data, scope, or user-decision gate, stop orchestration before delegation: do not spawn new sub-agents, do not invoke external CLIs, and pause or close any pending delegated work until the user explicitly approves the exact next step.
- A single agent's unilateral refusal or risk judgment is not a valid ping-pong result. Ping-pong starts only after the supervising lead architect records the risk gate outcome and the user has approved proceeding when approval is required.
- Default orchestration recording is `execution_mode: solo`; delegated agent fields, external review fields, or `execution_mode: supervisor_subagents` require an explicit risk preflight status before they may be recorded.
- `risk_preflight_recorded_by` must identify the main-thread supervising lead architect; evaluator/tool identities such as `antigravity`, `agy`, `claude`, `codex`, `gemini`, `external-review-wrapper`, or `external-cli*` cannot record the preflight gate.
- `risk_preflight_status: approved` must pair with `approval_required: true`, a concrete `approval_ref`, and the exact `approved_next_step`; `risk_preflight_status: pass` must pair with `approval_required: false`.
- Delegate only when the current runtime permits it, the user has explicitly requested sub-agents or external review, and the work is material, separable, and worth the coordination cost.
- Keep simple, urgent, tightly coupled, or low-risk work in the main thread.
- When delegated planning is justified, planner/reviewer agents create and critique plan versions while the supervising lead architect decides when the plan is execution-ready.
- When delegated coding is justified, each coding agent must own a disjoint write scope.
- The supervising lead architect may do the primary implementation when that is the fastest correct path; otherwise focus on orchestration, conflict resolution, architecture integrity, and final validation.
- When a close gate requires multiple reviewer routes, every required route is an all-of condition. Required internal routes need a durable accepted `.md` Markdown response artifact under project `docs/report/` or `docs/orchestration/<task-id>/` with parser-compatible review fields. Required external routes additionally need a durable accepted response artifact under `docs/orchestration/<task-id>/external-cli/<plan-version>/<round>/` or `docs/orchestration/<task-id>/current-task/responses/` with matching companion request file, wrapper-generated provenance manifest, evaluator runner, requested/actual route, `verdict: accept`, parser-compatible review fields, command-response path, response path, and hash provenance. If any required route is unavailable, policy-blocked, tool-blocked, auth-blocked, missing, or artifact-invalid, stop as `blocked`; do not substitute sub-agent acceptance, model consensus, or local tests for the blocked required route unless the user explicitly changes the close condition.
- When ORCH marks an external review as required for `implementation_start`, the same all-of review evidence rule applies before plan-dependent implementation starts. The matching active TASK must carry a same-task `consumes_plan_ref`, the referenced round directory must match that plan version, every required route must be non-empty, parseable, registry-resolvable, and accepted, and missing, blocked, pending, or invalid gate state is a stop signal in the authoring workflow.
- When the user explicitly includes a sub-agent trigger (`서브에이전트`, `서브 에이전트`, `subagent`, `subagents`, `sub-agent`, `sub-agents`) with `codeguide` code writing, implementation, or build-out work, default to delegation-first execution:
  - create or reuse sub-agents for planner, reviewer/evaluator, implementation, and validation responsibilities when those tracks are materially distinct
  - keep the main thread in a tech-lead architect and supervisor role unless delegation is not practical
- Active delegated tasks must maintain `orchestration/<task-id>/ORCH.md` with supervising lead architect identity, delegated agent roles, and owned scopes.
- For solo work, create or update orchestration docs only when the docs lifecycle is already active or the task risk/traceability need justifies it.
- Track plan authorship and review routing in orchestration docs:
  - `primary_author_tool`: `antigravity|agy|claude|codex|human|external-runner`
  - `review_mode`: `external_cli|current_task_debate|agy_subagents`
- Treat the following user phrases as the same sub-agent trigger: `서브에이전트`, `서브 에이전트`, `subagent`, `subagents`, `sub-agent`, `sub-agents`.
- If delegation is skipped, record `execution_mode: solo` plus a non-empty `delegation_note` explaining the exception.

## Safety Baseline Carry-forward
- External service calls, destructive edits, sensitive data handling, or delegated/external review must pass the relevant risk preflight before proceeding.
- Run risk preflight in the main thread before spawning sub-agents, invoking external reviewers, or starting any ping-pong loop.
- If risk preflight finds a gate, do not spawn new sub-agents, do not invoke external CLIs, and wait for explicit approval of the exact next step.
- Ping-pong starts only after the supervising lead architect records the risk gate outcome and required user approval is granted.
