# Codeguide References Index

Use this file to pick the smallest authoritative reference set for the active task.

## Core Governance
- Docs system-of-record and templates: `docs-system-of-record.md`
- Doc-gardening process: `doc-gardening-agent.md`
- Tools and automation details: `tools-automation.md`
- MCP context integration policy: `mcp-context-integration.md`
- Serena symbolic workflow: `serena-workflow.md`
- mem0 restricted memory policy: `mem0-policy.md`
- External plan review prompt: `external-plan-review-prompt.md`
- PR and commit templates: `git-pr-commit-templates.md`
- Engineering operating principles: `harness-engineering-principles.md`

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
2. Expand to architecture decision aids only when the task needs structural or integration guidance.
3. Use deprecated / secondary framework references only for legacy examples or migration context.
4. Keep outputs concise and evidence-based.

## Exclusions
- Documents under `mold/` and generated traces under `mold/temp/` are outside this curated index and the English-only documentation policy.
- The public-facing `README.md` is also outside that policy and may be Korean-first.
