---
name: codeguide
description: Production-grade architecture and code quality guidance for designing, refactoring, reviewing, and debugging full-stack systems. Use when Codex must enforce SOLID/DRY/KISS/Clean Code/Boy Scout, config-first rules, centralized cross-cutting concerns, secure coding, and test/review standards across Java/Spring Boot, Node/Express, Python/FastAPI, React, and Vue. Also use to run an agent-first repository workflow where every task updates docs as the system of record (`docs/task`, `docs/shadow`, `docs/decisions`), with decision logging and doc-gardening, and when collaboration requires Korean-facing reports with English internal planning.
---

# Code Guide

Reference-first governance skill for architecture, code quality, and documentation lifecycle.

## Language Operation
- Parse user requests in their original language.
- Translate intent, planning, and execution reasoning into English internally before taking action.
- Report progress, findings, and final results in Korean by default.
- Change report language only when explicitly requested by the user.
- Keep technical terms in English when precision is improved.
- Preserve user-provided literals (names, IDs, exact constraints) without translation.

## Skill Boundary
- `codeguide`: policy, process, validation strategy, review standard
- `react`: React API/architecture and TypeScript-first framework guidance
- `javascript-es6`: React JavaScript (`.jsx`) language-level implementation patterns
- `springboot-official`: Spring Boot framework/API specifics

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

## Minimal Workflow
1. Start lifecycle: `run_codeguide.sh ... --task-status in_progress`
2. Execute task
3. Record decisions with 5-axis fields: `Why/What/How/Where/Verify`
4. On every material structure/API/config change, re-run `run_codeguide.sh ... --task-status in_progress --shadow-note "..."`
5. Validate docs (`validate_docs.sh --mode advisory`) after each sync or before handoff
6. If `code-or-runtime`, run runtime validations
7. Finish lifecycle once per task close: `run_codeguide.sh ... --task-status done --shadow-note "final state"` (or `blocked`) and refresh `docs/shadow/project-shadow.md`

## Plan Ping-Pong Loop
1. Create initial plan doc: `docs/plan/PLAN-<task-id>-v1.0.md`
2. Request external model evaluations and write one report per evaluator in `docs/report/`:
   - evaluator label must be exactly one of: `gemini`, `claude`, `codex`
3. Consolidate feedback into the plan and create a new plan version file (do not overwrite old versions):
   - version examples: `v1.1`, `v1.2`, `v2.0`
4. Repeat evaluation and revision cycle until one of these stop conditions is met:
   - plan is acceptable for execution
   - user explicitly asks to stop
5. Reflect the selected plan version in related `decision-*` and `TASK-*` docs.
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
- `bats "$CODEGUIDE_ROOT/tests/codeguide.bats"`

## References
- Start with: `references/index.md`
- Load only required reference file(s) for the active task
