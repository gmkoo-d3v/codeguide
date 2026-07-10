# Codeguide References Index

Use this file to pick the smallest authoritative reference set for the active task.

## Core Governance
- Operating model, response style, and evidence lookup rules: `operating-model.md`
- Workflow, scope modes, and validation routing: `workflow.md`
- Docs system-of-record hub: cross-cutting defaults, directory tree, script entry points, secret rules: `docs-system-of-record.md`
- Task/decision dictionaries, task-index rules, concurrent-session claims, update rules, hotfix exception, freshness SLA: `task-state-contract.md`
- Shadow buckets, document roles, shadow templates, anti-dump line caps: `shadow-system-contract.md`
- ORCH gate template and allowed values, project dictionary, plan and evaluator-report templates: `orchestration-review-contract.md`
- Doc-gardening process: `doc-gardening-agent.md`
- Tools and automation details: `tools-automation.md`
- External plan review prompt: `external-plan-review-prompt.md`
- PR and commit templates: `git-pr-commit-templates.md`
- Engineering operating principles: `harness-engineering-principles.md`
- Goal-oriented loop stop/continue contract: `goal-loop-contract.md`
- Session resume capsule and recovery read order: `session-resume-contract.md`
- Documentation language policy: `doc-language-policy.md`
- Orchestration contract: `orchestration-contract.md`
- External CLI file handoff contract: `external-cli-handoff.md`
- Plan orchestration loop: `plan-orchestration-loop.md`

## Context and Retrieval Routing
- Context-budget workflow and MCP source-authority rules: `mcp-context-integration.md`
- Shadow effect-map workflow, document role separation, evidence hierarchy, and user-question gates: `shadow-effect-map-workflow.md`
- Shadow v2 automation plan and user-decision assistant scope: `shadow-v2-automation-plan.md`
- Serena always-on shadow narrowing plus symbolic narrowing for current-code anchors, references, call chains, and impact analysis: `serena-workflow.md`
- mem0, pgvector, and Neo4j heavy-context prior-context and graph/vector hint policy: `mem0-policy.md`
- Default order for shadow investigations: docs/shadow first, `rg` plus always-on Serena for current-code narrowing, mem0/pgvector/Neo4j only for heavy-context prior hints, then direct source/test/runtime validation; see `mcp-context-integration.md`, `serena-workflow.md`, and `mem0-policy.md`.
- Skip auxiliary retrieval when direct docs or target files already answer the task with low risk.

## Quality Gates
- Review checklist: `review-checklist.md`
- Smells overview: `smells-overview.md`
- Java/Spring smells: `smells-java-spring.md`
- Node/Express smells: `smells-node-express.md`
- Python/FastAPI smells: `smells-python-fastapi.md`
- React smells: `smells-react.md`
- Vue smells: `smells-vue.md`

## Architecture Decision Aids
- Backend architecture patterns: `backend/_index.md`
- Frontend architecture decision rules: `frontend-patterns.md`
- Integration and security patterns: `integration/_index.md`

## Deprecated / Secondary Framework References
- Frontend legacy examples by stack: `frontend/_index.md`
- Use dedicated framework skills and official documentation first for setup, API details, and version-specific behavior.

## Selection Rules
1. Start with one core governance or quality-gate file.
2. For shadow effect, side-effect, review-question, or call-chain documentation work, load `shadow-effect-map-workflow.md`, `mcp-context-integration.md`, and `serena-workflow.md`.
3. For goal-oriented review, ping-pong, Ralph Wiggum, `/goal`, test-fix, or implementation loops, load `goal-loop-contract.md` before choosing more specific references.
4. For other context-heavy, MCP, memory, or call-chain work, load `mcp-context-integration.md` before choosing `serena-workflow.md` or `mem0-policy.md`.
5. Expand to architecture decision aids only when the task needs structural or integration guidance.
6. Use deprecated / secondary framework references only for legacy examples or migration context.
7. Keep outputs concise and evidence-based.

## Exclusions
- The public-facing `README.md` is outside the English-only documentation policy and may be Korean-first.
