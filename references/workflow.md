# Workflow

Extracted verbatim from SKILL.md for Phase 3 navigator completion; SKILL.md retains only triggers, invariants, and navigation pointers.

## Workflow
- For substantial implementation, API, architecture, data, security, performance, or correctness-critical tasks, perform a micro-design before code:
  - architecture pattern
  - components
  - data flow
  - dependencies
  - validation and rollback path
- For trivial or low-risk changes, fold design reasoning into the implementation and final note instead of forcing visible ceremony.
- Run edge-case scans for non-trivial or risk-bearing work, covering null/empty input, boundary values, concurrency, resource exhaustion, timeout/network failure, and security-sensitive cases when relevant.
- Do not implement speculative abstractions, broad frameworks, or future-proofing that the current goal does not need.
- `docs-only`:
  - run docs lifecycle + docs validation only
  - skip runtime suites (`npm test`, lint, junit, playwright) unless user explicitly requests
- `code-or-runtime`:
  - run docs validation and impacted runtime suites
  - pass runtime commands via options:
    - `--runtime-test-cmd`
    - `--runtime-lint-cmd`
    - `--runtime-e2e-cmd`
- Interpret `<project-root>` as the selected project root; when invoked from inside a git repository, resolve it to that repository root.
- Resolve the documentation root inside the project root: `<project-root>/docs`.
- Reusable skills projects are the narrow exception: when the selected root resolves to a skill package root with `SKILL.md` metadata, no local `docs/`, and an existing parent `docs/`, scripts may treat the parent as the system-of-record project root.
- Treat `docs/{task,shadow,decisions,plan,report,orchestration}` as the system of record for that workspace task flow.
- Keep repository code and project docs synchronized in the selected root; do not create sibling `../docs` trees or nested `docs/<repo-name>` layers unless the user explicitly requests them.
- Apply `references/goal-loop-contract.md` to goal-oriented document, planning, review, shadow, and code-writing loops.
- Define acceptance criteria, non-goals or scope boundary, required verification, and convergence owner before starting a goal loop; if they are missing, stop and ask for clarification.
- Do not use a fixed iteration count, token budget, or cost cap as the primary stop condition.
- Continue while iterations produce new material evidence, reduce verified risk, fix a checked failure, improve validation, or move the work toward explicit acceptance criteria.
- Stop when acceptance criteria and required verification pass, no new material findings appear, the same failure repeats without new evidence, an off-goal loop is detected, scope expands beyond the approved goal, or user decision/approval is required.
- Cost or token use is not a stopping reason by itself, but policy, privacy, destructive-action, external-side-effect, provenance, permission, and user-decision gates remain hard stops.
- When stopping before completion, report the blocker, last verified evidence, next safe action, and whether user decision is required.
- Decide whether the task needs the docs lifecycle. Use it for material architecture, multi-file, cross-service, delegated, or durable planning work; skip it for small direct answers and trivial edits.
- If the lifecycle is needed, start it with `run_codeguide.sh <project-root> --task-status in_progress`.
- Choose solo or delegated execution based on user request, separability, risk, and coordination cost.
- Record material decisions with 5-axis fields: `Why/What/How/Where/Verify`.
- On material structure/API/config changes, re-run `run_codeguide.sh <project-root> --task-status in_progress --shadow-note "..."`.
- Validate project docs (`validate_docs.sh <project-root> --mode advisory`) after each sync or before handoff.
- If `code-or-runtime`, run impacted runtime validations.
- Finish lifecycle once per task close: `run_codeguide.sh <project-root> --task-status done --shadow-note "final state"` (or `blocked`) and refresh the affected `docs/shadow/` graph.
