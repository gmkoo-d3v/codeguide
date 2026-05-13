# Codeguide References Index

Use this file to pick the smallest authoritative reference set for the active task.

## Core Governance
- Docs system-of-record and templates: `docs-system-of-record.md`
- Doc-gardening process: `doc-gardening-agent.md`
- Tools and automation details: `tools-automation.md`
- External plan review prompt: `external-plan-review-prompt.md`
- PR and commit templates: `git-pr-commit-templates.md`
- Engineering operating principles: `harness-engineering-principles.md`
- Goal-oriented loop stop/continue contract: `goal-loop-contract.md`

## Context and Retrieval Routing
- Context-budget workflow and MCP source-authority rules: `mcp-context-integration.md`
- Shadow effect-map workflow, document role separation, evidence hierarchy, and user-question gates: `shadow-effect-map-workflow.md`
- Serena symbolic narrowing for current-code anchors, references, call chains, and impact analysis: `serena-workflow.md`
- mem0, pgvector, and Neo4j restricted prior-context and graph/vector hint policy: `mem0-policy.md`
- Default order for large or uncertain investigations: docs/shadow first, `rg` plus Serena for current-code narrowing, mem0/pgvector/Neo4j for bounded prior-context hints, then direct source/test/runtime validation.
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
- Backend architecture patterns: `backend-patterns.md`
- Frontend architecture decision rules: `frontend-patterns.md`
- Integration and security patterns: `integration-patterns.md`

## Deprecated / Secondary Framework References
- React (JavaScript) legacy examples: `frontend-react-javascript.md`
- React (TypeScript) legacy examples: `frontend-react-typescript.md`
- Tailwind legacy examples: `frontend-tailwind.md`
- Vue legacy examples: `frontend-vue.md`
- Claude SC comparative playbooks: `claude-sc/index.md`
- Use dedicated framework skills and official documentation first for setup, API details, and version-specific behavior.
- Legacy Claude SC playbooks are comparative references only; their Serena or memory instructions must not override `SKILL.md`, `mcp-context-integration.md`, `serena-workflow.md`, or `mem0-policy.md`.

## Selection Rules
1. Start with one core governance or quality-gate file.
2. For shadow effect, side-effect, review-question, or call-chain documentation work, load `shadow-effect-map-workflow.md` plus `mcp-context-integration.md`.
3. For goal-oriented review, ping-pong, Ralph Wiggum, `/goal`, test-fix, or implementation loops, load `goal-loop-contract.md` before choosing more specific references.
4. For other context-heavy, MCP, memory, or call-chain work, load `mcp-context-integration.md` before choosing `serena-workflow.md` or `mem0-policy.md`.
5. Expand to architecture decision aids only when the task needs structural or integration guidance.
6. Use deprecated / secondary framework references only for legacy examples or migration context.
7. Keep outputs concise and evidence-based.

## Exclusions
- Documents under `mold/` and generated traces under `mold/temp/` are outside this curated index and the English-only documentation policy.
- The public-facing `README.md` is also outside that policy and may be Korean-first.
