# Tools and Automation

Use this reference when planning or evaluating local quality checks, CI gates, and test automation.

## Execution strategy
- Prefer the fewest useful tool loops that still prove correctness, safety, and required grounding.
- Run fast static checks first (lint/type checks) to fail early.
- Run unit tests before integration/E2E tests.
- Run the smallest command set that still proves correctness and safety.
- Prefer deterministic, repeatable commands with pinned tool versions.
- Before starting local servers, containers, watchers, or background jobs for validation, record ownership context such as command, PID/container name, port, and purpose when available.
- After validation, terminate only the resources started for that validation unless the user explicitly asks to keep them running; do not stop pre-existing user or system processes.
- Stop once the core request is answered with sufficient evidence and additional checks are unlikely to change the result materially.

## Recommended command matrix

### Java / Spring Boot
- Prefer Gradle: `./gradlew test` and `./gradlew check`.
- Prefer Maven: `mvn test` and `mvn verify`.
- Add focused test runs for changed packages when the suite is large.

### Node / Express and Frontend
- Run lint: `npm run lint` (or `pnpm`/`yarn` equivalent).
- Run unit tests: `npm test`.
- Run build/type checks when available: `npm run build` and `npm run typecheck`.
- Run E2E only when behavior spans pages or integrations: `npx playwright test`.

### Python / FastAPI
- Run lint/format checks: `ruff check .` and formatter checks if configured.
- Run type checks when enabled: `mypy`.
- Run tests: `pytest` with focused markers first, then full suite as needed.

## Review automation checklist
- Verify lint and formatter status.
- Verify unit and integration test status.
- Verify migration and schema compatibility for DB changes.
- Verify API contract stability for externally consumed endpoints.
- Verify no secrets in code, config, or logs.

## Docs automation checklist
- Preferred single entrypoint for material docs lifecycle work: `scripts/run_codeguide.sh <project-root> --mode auto`.
- Preferred UX: zero-command for user when docs lifecycle is justified; skip docs automation for small direct answers and trivial edits.
- Run docs scaffold setup for new repositories: `scripts/init_docs_scaffold.sh <project-root>`.
- Run doc sync for each task/decision update: `scripts/doc_garden.sh <project-root> ...`.
- Run local docs validation in warning mode: `scripts/validate_docs.sh <project-root> --mode advisory`.
- Run CI docs validation in blocking mode: `scripts/validate_docs.sh <project-root> --mode strict`.
- Ensure 5-axis records are present in docs:
  - decisions: Why/What/How/Where/Verify
  - tasks: Why/Where/Verify

## CodeGuide command quick reference

Use `<skill-dir>` for the directory containing this skill package and `SKILL.md`.

- `<skill-dir>/scripts/run_codeguide.sh <project-root> --mode auto`
- `<skill-dir>/scripts/run_codeguide.sh <project-root> --mode auto --task-status in_progress`
- `<skill-dir>/scripts/run_codeguide.sh <project-root> --mode auto --task-status in_progress --shadow-note "search and navigation updated"`
- `<skill-dir>/scripts/run_codeguide.sh <project-root> --mode auto --task-status done --shadow-note "final architecture synced"`
- `<skill-dir>/scripts/run_external_plan_reviews.sh <project-root> --task-id <TASK_ID> --plan-version <vX.Y> --primary-tool agy --primary-model <alias> --review-round <rNN> --risk-preflight-status approved --approval-ref <USER_APPROVAL_REF> --approved-next-step "run external CLI review round <rNN>"`
  - Route selection: use `--primary-model <alias>` for self-review exclusion and repeat `--reviewer <alias>` for reviewer routes; aliases, quota groups, default reviewers, and quota-error patterns come from `config/ai_model_registry.json` or the configured model registry path.
  - External reviewer model selection is runner-specific: the wrapper never mutates runner settings; runners without a documented per-call model flag use the globally selected runtime model, while runners with a documented flag may receive the registry `cli_model` for that route.
  - If the Codex app sandbox blocks private workspace egress, request explicit user approval and rerun the same external CLI command through the user-approved unsandboxed path; record `platform_permission_blocked` only when that approval path is unavailable or still blocked.
  - If a runner reports `Not logged in` from inside the Codex app but works in a normal user Terminal, treat it as a sandbox/keychain permission boundary and rerun through the user-approved unsandboxed path before asking the user to log in.
  - On quota exhaustion, stop and ask the user to switch the runner's globally selected model, then rerun with a reviewer route that records that selection.
- `python3 <skill-dir>/scripts/external_review_runner.py --project-root <project-root> enqueue ...`
  - Use only to create artifact-centered review packets under `docs/orchestration/<task-id>/current-task/`; this is a review handoff tool, not an authoring tool.
- `<skill-dir>/scripts/doc_garden.sh <project-root> --task-id <TASK_ID>`
- `<skill-dir>/scripts/validate_docs.sh <project-root> --mode advisory`
- `<skill-dir>/scripts/validate_docs.sh <project-root> --mode strict`
- `<skill-dir>/scripts/check_english_docs.sh <skill-dir>`
- `bats <skill-dir>/tests/` (runs the full feature-split bats suite)
  - Capture the pass/fail baseline from the current HEAD at review time; do not rely on a stored count. Some pre-existing failures may exist in a given environment, so the gate is "no NEW failures versus the freshly captured baseline," not "zero failures."

## No-RAG baseline
- Baseline workflow should not require vector DB, embedding jobs, or retrieval pipelines.
- Add RAG/embedding only when repository scale or retrieval quality demonstrably requires it.

## CI gate guidance
- Keep branch-level checks fast; move expensive suites to required merge gates if needed.
- Fail CI on must-fix quality signals (lint errors, failing tests, critical security checks).
- Keep optional checks visible but non-blocking if they are noisy; convert to blocking after stabilization.

## Reporting format
- Report command, scope, and result (`pass`/`fail`/`not run`).
- Report cleanup status for validation resources that were started during the task.
- Explain failures with root cause and next fix action.
- State residual risk when any critical check is skipped.
