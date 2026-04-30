# Tools and Automation

Use this reference when planning or evaluating local quality checks, CI gates, and test automation.

## Execution strategy
- Prefer the fewest useful tool loops that still prove correctness, safety, and required grounding.
- Run fast static checks first (lint/type checks) to fail early.
- Run unit tests before integration/E2E tests.
- Run the smallest command set that still proves correctness and safety.
- Prefer deterministic, repeatable commands with pinned tool versions.
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

## No-RAG baseline
- Baseline workflow should not require vector DB, embedding jobs, or retrieval pipelines.
- Add RAG/embedding only when repository scale or retrieval quality demonstrably requires it.

## CI gate guidance
- Keep branch-level checks fast; move expensive suites to required merge gates if needed.
- Fail CI on must-fix quality signals (lint errors, failing tests, critical security checks).
- Keep optional checks visible but non-blocking if they are noisy; convert to blocking after stabilization.

## Reporting format
- Report command, scope, and result (`pass`/`fail`/`not run`).
- Explain failures with root cause and next fix action.
- State residual risk when any critical check is skipped.
