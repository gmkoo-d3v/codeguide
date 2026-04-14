---
name: codeguide
description: Production-grade architecture and code quality guidance for designing, refactoring, reviewing, and debugging full-stack systems. Use when Codex must enforce SOLID/DRY/KISS/Clean Code/Boy Scout, config-first rules, centralized cross-cutting concerns, secure coding, and test/review standards across Java/Spring Boot, Node/Express, Python/FastAPI, React, and Vue. Also use to run a supervising-lead-architect multi-agent workflow where workspace docs remain the system of record, sub-agents handle planning/review/coding loops, and collaboration requires Korean-facing reports with English internal planning.
---

# Code Guide

Reference-first governance skill for architecture, code quality, documentation lifecycle, and supervising-lead-architect multi-agent orchestration.

## Language Operation
- Parse user requests in their original language.
- Translate intent, planning, and execution reasoning into English internally before taking action.
- Report progress, findings, and final results in Korean by default.
- Change report language only when explicitly requested by the user.
- Keep technical terms in English when precision is improved.
- Preserve user-provided literals (names, IDs, exact constraints) without translation.

## Documentation Language Policy
- Authoritative skill documents must be written in English.
- This policy applies to `SKILL.md`, curated markdown references, and other maintained markdown artifacts in this skill.
- Public-facing repository entry docs are the exception:
  - `README.md` may be Korean-first for portfolio and repository presentation
  - `README.en.md` should provide the English companion when practical
- Experimental research artifacts are excluded from this policy:
  - documents under `mold/`
  - generated traces and scratch artifacts under `mold/temp/`
- Secondary references may preserve legacy examples, but deprecation and routing notices must remain in English.

## Skill Boundary
- `codeguide`: policy, process, validation strategy, review standard, orchestration rules
- `react`: React API/architecture and TypeScript-first framework guidance
- `javascript-es6`: React JavaScript (`.jsx`) language-level implementation patterns
- `springboot-official`: Spring Boot framework/API specifics
- Use `codeguide` to decide what standards to enforce, what to validate, and how to document or review changes.
- Do not treat `codeguide` as the primary source for framework setup tutorials or API-by-API reference material.

## Command Root
- Resolve once:
  - `CODEGUIDE_ROOT="${CODEX_HOME:-$HOME/.codex}/skills/codeguide"`
- Execute scripts via:
  - `"$CODEGUIDE_ROOT/scripts/..."`

## Change Scope Policy
- `docs-only`:
  - run docs lifecycle + docs validation only
  - skip runtime suites (`npm test`, lint, junit, playwright) unless user explicitly requests
- `code-or-runtime`:
  - run docs validation and impacted runtime suites
  - pass runtime commands via options:
    - `--runtime-test-cmd`
    - `--runtime-lint-cmd`
    - `--runtime-e2e-cmd`
- Natural-language scope aliases:
  - treat `독스모드`, `문서모드`, `계획모드`, `docs mode`, `docs-only mode`, `document mode`, and `planning mode` as requests for `docs-only`
  - treat explicit runtime-verification language such as `테스트까지`, `lint까지`, `e2e까지`, `실행 검증`, `runtime 검증`, `test too`, `run tests`, or `run lint/e2e` as requests for `code-or-runtime`

## Docs Root Policy
- Interpret `<project-root>` as the repository root.
- Resolve the documentation root to the parent workspace folder: `<project-root>/../docs`.
- Treat `docs/{task,shadow,decisions,plan,report,orchestration}` as the system of record for that workspace task flow.
- Keep repository code and workspace docs synchronized, but do not duplicate the docs tree inside the repo unless the user explicitly requests it.

## Shadow System Contract
- Treat `docs/shadow/` as a Markdown-only compressed context layer for agents.
- Use topology-first typed buckets:
  - `apps`
  - `services`
  - `packages`
  - `infra`
  - `data`
- Shadow document roles are fixed:
  - `docs/shadow/project-shadow.md`: top router only
  - `docs/shadow/_global.md`: optional side path for cross-unit invariants only
  - `docs/shadow/<bucket>/_index.md`: unit membership only
  - `docs/shadow/<bucket>/<unit>/overview.md`: landing doc plus concern router
  - concern leaf docs: concrete facts only
- Default read path:
  - `project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf`
- Keep shadow docs in English and Markdown only; do not add JSON sidecars or empty concern placeholder files.
- Use unit `overview.md` as the day-one landing doc when a unit is detected.
- Same-session changes should refresh affected shadow docs during final sync; external git-driven changes should refresh shadow only on explicit user request.
- Preserve legacy compatibility with thin redirect shims at old paths and archive replaced bodies under `_deprecated` or `_obsolete`.
- Target roughly 200 lines per shadow doc; use 300 lines as a soft cap and split by concern when a doc stops routing well.

## Orchestration Contract
- Main thread acts as the supervising lead architect and workflow supervisor: gather requirements, choose delegation boundaries, own architectural direction, monitor progress, integrate outcomes, and make final safety/quality decisions.
- Sub-agents own execution tracks: planning, plan review, implementation, and targeted verification should be delegated to separate agents when the work is material and separable.
- Planning loop is sub-agent driven: planner/reviewer agents create and critique plan versions while the supervising lead architect decides when the plan is execution-ready.
- Coding is multi-agent by default when the task cleanly splits by ownership; each coding agent must own a disjoint write scope.
- The supervising lead architect should avoid doing the primary implementation work when delegation is practical; focus on orchestration, conflict resolution, architecture integrity, and final validation.
- When the user explicitly includes a sub-agent trigger (`서브에이전트`, `서브 에이전트`, `subagent`, `subagents`, `sub-agent`, `sub-agents`) with `codeguide` code writing, implementation, or build-out work, default to delegation-first execution:
  - create or reuse sub-agents for planner, reviewer/evaluator, implementation, and validation responsibilities when those tracks are materially distinct
  - keep the main thread in a tech-lead architect and supervisor role unless delegation is not practical
- Active tasks must maintain `orchestration/ORCH-<task-id>.md` with supervising lead architect identity, delegated agent roles, and owned scopes.
- Orchestration rules apply in both `docs-only` and `code-or-runtime` work; `docs-only` does not disable planning or review delegation.
- Track plan authorship and review routing in orchestration docs:
  - `primary_author_tool`: `gemini|claude|codex`
  - `review_mode`: `external_cli|codex_subagents`
- Treat the following user phrases as the same sub-agent trigger: `서브에이전트`, `서브 에이전트`, `subagent`, `subagents`, `sub-agent`, `sub-agents`.
- If delegation is skipped, record `execution_mode: solo` plus a non-empty `delegation_note` explaining the exception.

## Minimal Workflow
1. Start lifecycle: `run_codeguide.sh <project-root> --task-status in_progress`
2. The supervising lead architect resolves delegation boundaries and assigns sub-agents for plan/review/code tracks
3. Sub-agents execute their owned work; the supervising lead architect records decisions with 5-axis fields: `Why/What/How/Where/Verify`
4. On every material structure/API/config change, re-run `run_codeguide.sh <project-root> --task-status in_progress --shadow-note "..."`
5. Validate workspace docs (`validate_docs.sh <project-root> --mode advisory`) after each sync or before handoff
6. If `code-or-runtime`, run impacted runtime validations
7. Finish lifecycle once per task close: `run_codeguide.sh <project-root> --task-status done --shadow-note "final state"` (or `blocked`) and refresh the affected `docs/shadow/` graph.

## Plan Orchestration Loop
1. The supervising lead architect creates or delegates the initial plan doc at workspace docs `docs/plan/PLAN-<task-id>-v1.0.md`.
2. Planning sub-agent drafts the plan; review sub-agent(s) critique it and write one report per evaluator in workspace `docs/report/`:
   - evaluator label must be exactly one of: `gemini`, `claude`, `codex`
   - reviewer and evaluator tracks both default to defect-seeking review rather than approval-seeking review; prioritize logical gaps, weak assumptions, missing verification, understated risks, contract mismatches, and team-convention violations over praise
   - keep critical review evidence-based: prefer concrete defects, violated rules, and missing safeguards over vague negativity
   - do not require exact command phrases for stronger scrutiny; infer review intensity from task context, user wording, and risk level
   - treat natural-language signals such as `비판적으로`, `논리오류`, `논리 허점`, `허점`, `구멍`, `문제점 위주`, `빡세게`, `가차없이`, `critical`, and `harsh review` as requests for stronger critical scrutiny
   - `execution_mode: supervisor_subagents` tasks must have at least one evaluator report before strict handoff
   - when the task or any linked decision sets `risk_level: high|critical`, require one adversarial review pass before strict handoff; this pass assumes the initial plan is wrong and records `objection`, `counterproposal`, `rebuttal`, and `residual_risk`
   - default ping-pong behavior uses external evaluators: primary author tool writes the plan, the other two tools review it
   - if a task or linked decision is high-risk and the operator does not explicitly pick an adversarial evaluator, external CLI ping-pong should auto-select one of the non-primary reviewers for the adversarial pass
   - if the user explicitly requests ping-pong review with sub-agents (including the alias forms listed in the orchestration contract), interpret that as Codex sub-agent review mode and do not call external `gemini`/`claude` evaluators by default
3. The supervising lead architect consolidates feedback into the next versioned plan file without overwriting old versions:
   - version examples: `v1.1`, `v1.2`, `v2.0`
4. Repeat the sub-agent review/revision loop until one of these stop conditions is met:
   - plan is acceptable for execution
   - user explicitly asks to stop
   - semi-automated external review mode must stop after collecting report docs and showing the user the results; it must not auto-create the next plan version
   - external CLI ping-pong should use each tool's default model unless the operator explicitly overrides it; do not depend on hardcoded model-version strings
5. When implementation begins, coding sub-agents own disjoint code scopes while the supervising lead architect tracks the selected plan version in related `decision-*` and `TASK-*` docs.
   - for `codeguide`-invoked code writing work that explicitly requests sub-agents, prefer a standard four-track split when practical: planner, reviewer/evaluator, implementation, validation
6. At task close, ensure the final architecture/runtime state is reflected in the affected `docs/shadow/` router, `_global.md` when applicable, bucket indexes, unit overviews, and leaf docs.

## Review/Debug Contract
- `design`: boundaries, contracts, risk/test strategy
- `refactor`: incremental plan, invariants, rollback points
- `review`: severity-ordered findings with file/line evidence
- `debug`: repro -> hypothesis -> fix -> verification
- reviewer and evaluator roles should both assume defects are likely until checked, especially for code-related work where API contracts, team conventions, integration boundaries, validation rules, and regression exposure are commonly missed
- for code review, prefer surfacing contract violations, convention drift, missing validation, integration risk, and weak verification before style-level praise

## Safety Baseline
- Never store raw secret values in docs
- Prefer config-first and centralized cross-cutting concerns
- Enforce deterministic tests (unit-first, integration where needed)

## Command Quick Reference
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status in_progress`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status in_progress --shadow-note "search and navigation updated"`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status done --shadow-note "final architecture synced"`
- `"$CODEGUIDE_ROOT/scripts/run_external_plan_reviews.sh" <project-root> --task-id <TASK_ID> --plan-version <vX.Y> --primary-tool <gemini|claude|codex> --review-round <rNN>`
- `"$CODEGUIDE_ROOT/scripts/doc_garden.sh" <project-root> --task-id <TASK_ID>`
- `"$CODEGUIDE_ROOT/scripts/validate_docs.sh" <project-root> --mode advisory`
- `"$CODEGUIDE_ROOT/scripts/validate_docs.sh" <project-root> --mode strict`
- `"$CODEGUIDE_ROOT/scripts/check_english_docs.sh" "$CODEGUIDE_ROOT"`
- `bats "$CODEGUIDE_ROOT/tests/codeguide.bats"`

## References
- Start with: `references/index.md`
- Load only required reference file(s) for the active task
- Prefer core governance and quality-gate references first; use secondary framework references only for legacy examples or migration context.
- `mold*` research artifacts are intentionally excluded from the curated reference set.
