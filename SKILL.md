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

## Docs Root Policy
- Interpret `<project-root>` as the repository root.
- Resolve the documentation root to the parent workspace folder: `<project-root>/../docs`.
- Treat `docs/{task,shadow,decisions,plan,report,orchestration}` as the system of record for that workspace task flow.
- Keep repository code and workspace docs synchronized, but do not duplicate the docs tree inside the repo unless the user explicitly requests it.

## Orchestration Contract
- Main thread acts as the supervising lead architect and workflow supervisor: gather requirements, choose delegation boundaries, own architectural direction, monitor progress, integrate outcomes, and make final safety/quality decisions.
- Sub-agents own execution tracks: planning, plan review, implementation, and targeted verification should be delegated to separate agents when the work is material and separable.
- Planning loop is sub-agent driven: planner/reviewer agents create and critique plan versions while the supervising lead architect decides when the plan is execution-ready.
- Coding is multi-agent by default when the task cleanly splits by ownership; each coding agent must own a disjoint write scope.
- The supervising lead architect should avoid doing the primary implementation work when delegation is practical; focus on orchestration, conflict resolution, architecture integrity, and final validation.
- Active tasks must maintain `orchestration/ORCH-<task-id>.md` with supervising lead architect identity, delegated agent roles, and owned scopes.
- If delegation is skipped, record `execution_mode: solo` plus a non-empty `delegation_note` explaining the exception.

## Minimal Workflow
1. Start lifecycle: `run_codeguide.sh <project-root> --task-status in_progress`
2. The supervising lead architect resolves delegation boundaries and assigns sub-agents for plan/review/code tracks
3. Sub-agents execute their owned work; the supervising lead architect records decisions with 5-axis fields: `Why/What/How/Where/Verify`
4. On every material structure/API/config change, re-run `run_codeguide.sh <project-root> --task-status in_progress --shadow-note "..."`
5. Validate workspace docs (`validate_docs.sh <project-root> --mode advisory`) after each sync or before handoff
6. If `code-or-runtime`, run impacted runtime validations
7. Finish lifecycle once per task close: `run_codeguide.sh <project-root> --task-status done --shadow-note "final state"` (or `blocked`) and refresh `docs/shadow/project-shadow.md`

## Plan Orchestration Loop
1. The supervising lead architect creates or delegates the initial plan doc at workspace docs `docs/plan/PLAN-<task-id>-v1.0.md`.
2. Planning sub-agent drafts the plan; review sub-agent(s) critique it and write one report per evaluator in workspace `docs/report/`:
   - evaluator label must be exactly one of: `gemini`, `claude`, `codex`
   - `execution_mode: supervisor_subagents` tasks must have at least one evaluator report before strict handoff
   - when the task or any linked decision sets `risk_level: high|critical`, require one adversarial review pass before strict handoff; this pass assumes the initial plan is wrong and records `objection`, `counterproposal`, `rebuttal`, and `residual_risk`
3. The supervising lead architect consolidates feedback into the next versioned plan file without overwriting old versions:
   - version examples: `v1.1`, `v1.2`, `v2.0`
4. Repeat the sub-agent review/revision loop until one of these stop conditions is met:
   - plan is acceptable for execution
   - user explicitly asks to stop
5. When implementation begins, coding sub-agents own disjoint code scopes while the supervising lead architect tracks the selected plan version in related `decision-*` and `TASK-*` docs.
6. At task close, ensure the final architecture/runtime state is reflected in `docs/shadow/project-shadow.md`.

## Review/Debug Contract
- `design`: boundaries, contracts, risk/test strategy
- `refactor`: incremental plan, invariants, rollback points
- `review`: severity-ordered findings with file/line evidence
- `debug`: repro -> hypothesis -> fix -> verification

## Safety Baseline
- Never store raw secret values in docs
- Prefer config-first and centralized cross-cutting concerns
- Enforce deterministic tests (unit-first, integration where needed)

## Command Quick Reference
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status in_progress`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status in_progress --shadow-note "search and navigation updated"`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status done --shadow-note "final architecture synced"`
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
