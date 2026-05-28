---
name: codeguide
description: Architecture/code-quality governance for SOLID/DRY/KISS refactors, reviews, debugging, and validation across Java/Spring Boot, Node/Express, Python/FastAPI, React, and Vue; includes supervising-architect workflows with docs as system of record.
---

# Code Guide

Outcome-first governance skill for architecture, code quality, documentation lifecycle, and supervising-architect orchestration.

## When To Use
- Use for material architecture, refactoring, reviewing, debugging, performance, security, testing strategy, and documentation lifecycle work.
- Use when the task needs SOLID, DRY, KISS, Clean Code, Boy Scout, config-first design, centralized cross-cutting concerns, secure coding, or test/review standards.
- Use when project docs, shadow docs, external review, sub-agent coordination, or durable handoff artifacts must stay synchronized with the repository.
- Use dedicated framework skills and official documentation first for setup, API details, library versions, and framework-specific behavior.
- Skip the docs lifecycle for small direct answers and trivial edits unless the user asks for durable documentation.

## Operating Model
- Parse user requests in their original language.
- Translate intent, planning, and execution reasoning into English internally before taking action.
- Report progress, findings, and final results in Korean by default.
- Change report language only when explicitly requested by the user.
- Keep technical terms in English when precision is improved.
- Preserve user-provided literals (names, IDs, exact constraints) without translation.
- Add a visible English translation for Korean requests, or a grammar correction for English requests, only when it improves a conversational or analytical response.
- Do not add translation, grammar correction, or extra prose when the user requested a strict artifact such as code, JSON, SQL, patch content, commit text, review comments, or another fixed format.
- Prefer outcome-first prompts and responses: define the target result, constraints, evidence, validation, and stopping condition before adding process detail.
- Keep process proportional to task risk. Use the smallest workflow that can produce a correct, grounded, and verifiable result.
- For multi-step or tool-heavy tasks, begin with a short visible preamble before tool use that acknowledges the request and states the first step.
- When the runtime exposes a reasoning-effort or thinking-budget control, start low and escalate only when complexity/ambiguity/safety/correctness justifies it.
- User-requested structure wins over the default codeguide structure unless it violates safety, grounding, or required validation.
- Use plain concise prose by default. Add headers, bullets, tables, or fixed sections only when they improve comprehension, traceability, reviewability, or product UI fit.
- Use the `Why/What/How/Where/Verify` axis for substantial software engineering work, architecture decisions, implementation plans, durable handoff files, and project docs.
- For small answers, direct questions, trivial edits, or strict artifacts, use the lightest structure that satisfies the user.
- Preserve requested artifact type, length, structure, and genre when editing or drafting; improve clarity and correctness without inventing unsupported claims.
- Use the minimum evidence sufficient to answer correctly, cite or name the evidence when citation/reporting is required, then stop.
- Start with one broad, discriminative lookup or code search when evidence is needed and the target is not already known.
- Make another retrieval call only when the core question remains unanswered, a required fact is missing, the user asked for exhaustive coverage, a specific artifact must be read, or the answer would otherwise include an important unsupported factual claim.
- Do not retrieve again just to improve wording, add nonessential examples, or support phrasing that can safely be made more generic.
- Absence of evidence is not proof of absence; report unsupported or incomplete findings as such.

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
- Natural-language scope aliases:
  - treat `독스모드`, `문서모드`, `계획모드`, `docs mode`, `docs-only mode`, `document mode`, and `planning mode` as requests for `docs-only`
  - treat explicit runtime-verification language such as `테스트까지`, `lint까지`, `e2e까지`, `실행 검증`, `runtime 검증`, `test too`, `run tests`, or `run lint/e2e` as requests for `code-or-runtime`
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
- `design`: boundaries, contracts, risk/test strategy
- `refactor`: incremental plan, invariants, rollback points
- `review`: severity-ordered findings with file/line evidence
- `debug`: repro -> hypothesis -> fix -> verification
- Reviewer and evaluator roles should both assume defects are likely until checked, especially for code-related work where API contracts, team conventions, integration boundaries, validation rules, and regression exposure are commonly missed.
- For code review, prefer surfacing contract violations, convention drift, missing validation, integration risk, and weak verification before style-level praise.

## Skill Boundary
- `codeguide`: policy, process, validation strategy, review standard, orchestration rules.
- `react`: React API/architecture and TypeScript-first framework guidance.
- `javascript-es6`: React JavaScript (`.jsx`) language-level implementation patterns.
- `springboot-official`: Spring Boot framework/API specifics.
- Use `codeguide` to decide what standards to enforce, what to validate, and how to document or review changes.
- For framework setup, API-by-API references, library versions, and runtime behavior details, use the dedicated framework skill and official documentation first; return to `codeguide` for architecture, quality gates, and review standards.

## Safety Baseline
- Never store raw secret values in docs.
- Prefer config-first and centralized cross-cutting concerns.
- Enforce deterministic tests (unit-first, integration where needed).
- Policy, privacy, destructive-action, external-side-effect, provenance, permission, and user-decision gates are hard stops.
- External service calls, destructive edits, sensitive data handling, or delegated/external review must pass the relevant risk preflight before proceeding.
- Run risk preflight in the main thread before spawning sub-agents, invoking external reviewers, or starting any ping-pong loop.
- If risk preflight finds a gate, do not spawn new sub-agents, do not invoke external CLIs, and wait for explicit approval of the exact next step.
- Ping-pong starts only after the supervising lead architect records the risk gate outcome and required user approval is granted.

## Runtime Adapter
- Treat `CODEGUIDE_ROOT` as the installed skill root supplied by the host or operator.
- H-3 pending: do not encode runtime path precedence in this document; Phase 3 owns the adapter implementation.
- Until Phase 3 lands, command examples assume `CODEGUIDE_ROOT` already points at this skill root.
- Resolve scripts through `CODEGUIDE_ROOT/scripts/...` and keep command examples host-neutral.

## Routing Map
- Documentation language policy: `references/doc-language-policy.md`.
- Docs system of record, templates, and gardening: `references/docs-system-of-record.md`, `references/doc-gardening-agent.md`.
- Goal-oriented stop/continue behavior: `references/goal-loop-contract.md`.
- MCP context, Serena, memory, graph/vector hints, and evidence authority: `references/mcp-context-integration.md`, `references/serena-workflow.md`, `references/mem0-policy.md`.
- Shadow docs, shadow effect maps, deterministic evidence, review queues, user decisions, and LLM candidate handling: `references/shadow-effect-map-workflow.md`.
- Supervising-architect orchestration, risk preflight, sub-agent/delegation triggers, and close gates: `references/orchestration-contract.md`.
- External CLI file handoff, runner-neutral review packets, provenance, platform-permission blocks, and quota fallback: `references/external-cli-handoff.md`.
- Plan/review ping-pong, versioning, adversarial review, and convergence: `references/plan-orchestration-loop.md`.
- Tools and automation details: `references/tools-automation.md`.
- Review checklists and smell catalogs: `references/review-checklist.md`, `references/smells-overview.md`, and language/framework smell references.
- Backend, frontend, integration, and security architecture aids: load only the relevant reference from `references/index.md`.

## Command Quick Reference
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status in_progress`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status in_progress --shadow-note "search and navigation updated"`
- `"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" <project-root> --mode auto --task-status done --shadow-note "final architecture synced"`
- `"$CODEGUIDE_ROOT/scripts/run_external_plan_reviews.sh" <project-root> --task-id <TASK_ID> --plan-version <vX.Y> --primary-tool agy --primary-model <alias> --review-round <rNN> --risk-preflight-status approved --approval-ref <USER_APPROVAL_REF> --approved-next-step "run external CLI review round <rNN>"`
  - Model selection: use `--primary-model <alias>` and repeat `--reviewer <alias>`; aliases, quota groups, default reviewers, and phase fallback rules come from `config/ai_model_registry.json` or `CODEGUIDE_MODEL_REGISTRY`.
  - Quota fallback is automatic only for registered routes with an explicit `fallback_policy` match for the current task phase; unconfigured or unregistered quota-exhausted routes fail closed.
- Use `"$CODEGUIDE_ROOT/scripts/external_review_runner.py" --project-root <project-root> enqueue ...` to create artifact-centered `docs/orchestration/<task-id>/current-task/` debate packets that can be executed by an approved external-review runner, whether the coordinator is the current runtime, an external gateway, direct CLI, or a human.
- If the current app blocks direct external execution after explicit user approval, treat that as `platform_permission_blocked` and move execution to the approved runner. Use `--manual-handoff-only` and `--ingest-manual-responses` only as the last-resort user-operated fallback.
- `"$CODEGUIDE_ROOT/scripts/doc_garden.sh" <project-root> --task-id <TASK_ID>`
- `"$CODEGUIDE_ROOT/scripts/validate_docs.sh" <project-root> --mode advisory`
- `"$CODEGUIDE_ROOT/scripts/validate_docs.sh" <project-root> --mode strict`
- `"$CODEGUIDE_ROOT/scripts/check_english_docs.sh" "$CODEGUIDE_ROOT"`
- `bats "$CODEGUIDE_ROOT/tests/codeguide.bats"`

## References
- Start with: `references/index.md`
- Load only required reference file(s) for the active task
- Prefer core governance and quality-gate references first; use secondary framework references only for legacy examples or migration context.
- Use `references/mcp-context-integration.md`, `references/serena-workflow.md`, and `references/mem0-policy.md` when MCP context behavior affects a task.
- `mold*` research artifacts are intentionally excluded from the curated reference set.
