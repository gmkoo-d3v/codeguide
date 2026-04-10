# Harness Engineering Principles (OpenAI-aligned)

Source:
- https://openai.com/index/harness-engineering/ (accessed 2026-02-12)

Use this reference when defining team process for agentic software development.

## Core ideas to apply
- Shift team focus from coding every detail to steering agents with clear intent and constraints.
- Treat repository documentation as the primary memory and coordination layer for agents.
- Optimize for agent readability, not only human style preference.
- Use executable guardrails (lint, tests, architecture checks) to encode standards.
- Keep architectural boundaries strict while allowing implementation freedom inside modules.
- Manage risk with autonomy levels and explicit escalation points.
- Continuously remove entropy with recurring cleanup and standards hardening.

## Concrete translation for this skill

### 1) Humans steer, agents execute
- Human responsibilities:
  - define outcomes, constraints, and priorities
  - decide on high-impact trade-offs
  - approve or reject major decisions
- Agent responsibilities:
  - implement scoped changes
  - run validation loops
  - document decisions and progress in-repo

### 2) Repository as memory
- Keep durable knowledge in workspace `docs/task`, `docs/shadow`, `docs/decisions`.
- Keep `AGENTS.md` as a concise map to standards and key references.
- Avoid hidden decisions in chat-only history.
- Treat `docs/shadow/project-shadow.md` as the fast system map for agent onboarding.
- Run doc-gardening updates on every task to avoid stale memory.
- Record every user choice in `docs/decisions`, including hotfix and PR decisions.

### 3) Agent legibility standards
- Prefer explicit naming and stable folder conventions.
- Make contracts discoverable (API schemas, DTOs, migrations, runbooks).
- Keep setup and quality commands documented and runnable.

### 4) Mechanize quality
- Convert style and architecture expectations into checks:
  - lint and format checks
  - unit/integration/E2E tests
  - boundary tests (forbidden imports, layering checks)
  - security scans where available

### 5) Throughput with safety
- Prefer small, reviewable increments.
- Keep deployment and rollback simple.
- Do not block progress for perfection when risks are bounded and follow-up tasks are captured.

### 6) Autonomy ladder
- Level 1: suggest only
- Level 2: implement with approval before risky steps
- Level 3: implement and validate autonomously in approved scope

Define the required level per task in `docs/task/TASK-<id>.md`.

### 7) Entropy management
- Schedule recurring cleanup tasks:
  - dead code removal
  - docs sync
  - flaky test triage
  - dependency and security baseline refresh
- Track each cleanup wave as a task and link decisions if standards change.

## Adoption checklist
- [ ] Docs scaffold exists and is maintained.
- [ ] Shadow dictionary is current and readable.
- [ ] Decision records capture user-selected options and plans.
- [ ] Quality gates are automated and routinely executed.
- [ ] Escalation rules are explicit for risky actions.
- [ ] Cleanup cadence is scheduled and tracked.
- [ ] Docs contain no raw secret values.
