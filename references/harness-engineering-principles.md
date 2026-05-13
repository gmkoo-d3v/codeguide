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
- Keep durable knowledge in project `docs/task`, `docs/shadow`, `docs/decisions`.
- Keep `AGENTS.md` as a concise map to standards and key references.
- Avoid hidden decisions in chat-only history.
- Treat `docs/shadow/project-shadow.md` as the top router into the shadow graph for agent onboarding.
- Use `_global.md`, bucket `_index.md`, unit `overview.md`, and concern leaves to keep cross-unit rules, membership, routing, and concrete facts in their proper homes.
- Run doc-gardening updates for material tasks to avoid stale memory.
- Record material user choices in `docs/decisions`, including hotfix and PR decisions.

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
- For goal-oriented code loops, do not stop because an arbitrary iteration count, token budget, or cost cap was reached.
- Continue implementation/test-fix loops while each pass reduces a verified failure or produces new evidence.
- Stop code loops when verification passes, the same failure repeats without a new hypothesis, scope expands beyond the approved goal, or user approval is required.

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
- [ ] Shadow graph routing docs are current and readable.
- [ ] Decision records capture user-selected options and plans.
- [ ] Quality gates are automated and routinely executed.
- [ ] Escalation rules are explicit for risky actions.
- [ ] Cleanup cadence is scheduled and tracked.
- [ ] Docs contain no raw secret values.
- [ ] Goal loops use evidence and verification gates instead of fixed iteration limits.
