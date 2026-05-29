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
- Natural-language scope aliases:
  - treat `독스모드`, `문서모드`, `계획모드`, `docs mode`, `docs-only mode`, `document mode`, and `planning mode` as requests for `docs-only`
  - treat explicit runtime-verification language such as `테스트까지`, `lint까지`, `e2e까지`, `실행 검증`, `runtime 검증`, `test too`, `run tests`, or `run lint/e2e` as requests for `code-or-runtime`
- `design`: boundaries, contracts, risk/test strategy
- `refactor`: incremental plan, invariants, rollback points
- `review`: severity-ordered findings with file/line evidence
- `debug`: repro -> hypothesis -> fix -> verification

## Always Apply
- Safety hard stop: Never store raw secret values in docs; policy, privacy, destructive-action, external-side-effect, provenance, permission, and user-decision gates are hard stops; stop and wait for explicit approval of the exact next step. → `references/orchestration-contract.md`
- Report language: report in Korean by default; reason in English internally; change only on explicit request. → `references/operating-model.md`
- Defect-seeking review: Reviewer and evaluator roles should both assume defects are likely until checked, especially for code-related work where API contracts, team conventions, integration boundaries, validation rules, and regression exposure are commonly missed. For code review, prefer surfacing contract violations, convention drift, missing validation, integration risk, and weak verification before style-level praise. → `references/review-checklist.md`
- Docs = system of record: material work uses project docs as the system of record; keep code and docs synchronized. → `references/docs-system-of-record.md`

## Navigation
| Need | Reference |
|---|---|
| Operating model, response style, evidence lookup, reasoning-budget behavior | `references/operating-model.md` |
| Workflow, scope modes, micro-design, edge scans, docs/runtime validation, goal loops | `references/workflow.md`, `references/goal-loop-contract.md` |
| Documentation language policy | `references/doc-language-policy.md` |
| Docs system of record, templates, scaffolding, gardening, validation | `references/docs-system-of-record.md`, `references/doc-gardening-agent.md` |
| Tools, automation, command matrix, runtime validation strategy | `references/tools-automation.md` |
| MCP context, Serena, memory, graph/vector hints, evidence authority | `references/mcp-context-integration.md`, `references/serena-workflow.md`, `references/mem0-policy.md` |
| Shadow docs, shadow effect maps, deterministic evidence, review queues, user decisions | `references/shadow-effect-map-workflow.md` |
| Supervising-architect orchestration, risk preflight, delegation, close gates | `references/orchestration-contract.md` |
| External CLI file handoff, runner-neutral review packets, provenance, quota fallback | `references/external-cli-handoff.md` |
| Plan/review ping-pong, plan versioning, adversarial review, convergence | `references/plan-orchestration-loop.md` |
| Review checklists and smell catalogs | `references/review-checklist.md`, `references/smells-overview.md` |
| Backend, frontend, integration, and security architecture aids | `references/index.md` |

## Skill Boundary
- `codeguide`: policy, process, validation strategy, review standard, orchestration rules.
- `react`: React API/architecture and TypeScript-first framework guidance.
- `javascript-es6`: React JavaScript (`.jsx`) language-level implementation patterns.
- `springboot-official`: Spring Boot framework/API specifics.
- Use `codeguide` to decide what standards to enforce, what to validate, and how to document or review changes.
- For framework setup, API-by-API references, library versions, and runtime behavior details, use the dedicated framework skill and official documentation first; return to `codeguide` for architecture, quality gates, and review standards.

## Commands
- `<skill-dir>/scripts/run_codeguide.sh <project-root> --mode auto --task-status in_progress`
- `<skill-dir>/scripts/run_codeguide.sh <project-root> --mode auto --task-status done --shadow-note "final state"`
