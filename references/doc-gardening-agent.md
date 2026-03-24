# Doc-Gardening Agent Workflow

Use this reference to keep repository docs continuously synchronized with code and decisions.

## Objective
- Keep `docs/task`, `docs/shadow`, `docs/decisions`, `docs/plan`, and `docs/report` current on every task.
- Prevent stale context that causes wrong agent behavior.

## Mandatory execution points
- Run once before implementation (bootstrap and context sync).
- Run once after implementation and validation (final sync).
- Run on plan pivot or major scope change.
- For urgent hotfix, record minimum decision/task data immediately, then run full sync within 24 hours.
- Default user experience is zero-command: the agent runs these steps automatically.

Recommended command flow:
- `scripts/run_codeguide.sh <project-root> --mode auto` (preferred semi-auto)
- `scripts/doc_garden.sh <project-root> --task-id <TASK_ID> --task-status in_progress`
- `scripts/doc_garden.sh <project-root> --task-id <TASK_ID> --decision-id <DECISION_ID> --scope-type <type> --selected-option "<choice>"`
- `scripts/validate_docs.sh <project-root> --mode advisory`
- `scripts/validate_docs.sh <project-root> --mode strict` (CI)

## Semi-auto inference logic (`run_codeguide.sh`)
- `scope_type`:
  - branch prefix `hotfix/`, `release/`, `incident/`, `pr/`, `ops/` -> mapped scope
  - otherwise `task`
- `task_id`:
  - explicit `--task-id` wins
  - else most recent `docs/task/TASK-*.md`
  - else branch pattern (`ABC-123` or numeric id)
  - else UTC timestamp id
- `decision_id`:
  - explicit `--decision-id` wins
  - else `auto-<branch-slug>` (fallback `auto-task-<task_id>`)
- validation mode:
  - explicit `--mode` wins
  - CI or scope `hotfix/release/incident` -> `strict`
  - otherwise `advisory`

## Zero-command execution contract
- Trigger condition: user invokes this skill for a work task.
- Agent action:
  - run start sync automatically with `--task-status in_progress`
  - run finish sync automatically with `--task-status done` (or `blocked`)
  - bootstrap `docs/plan/PLAN-<task-id>-v1.0.md` automatically when missing
- Ask user only when path/scope cannot be inferred with reasonable confidence.

5-axis capture guidance:
- decisions: set `--axis-why`, `--axis-what`, `--axis-how`, `--axis-where`, `--axis-verify`
- tasks: set `--axis-why`, `--axis-where`, `--axis-verify`

## Input signals
- Changed files and modules
- User-selected options
- Work-type metadata (task, hotfix, PR, release, incident, ops)
- PR metadata (PR number, review outcome, merge strategy)
- Updated acceptance criteria
- Test and validation outcomes

## Update actions
- `docs/task`:
  - update task status, scope, touched modules, tests, and residual risks
- `docs/decisions`:
  - create/update `decision-<id>.md` with selected option and plan
  - include `scope_type`, `chosen_by`, and links (`linked_pr`, `linked_hotfix`) when applicable
  - update `decision-index.md`
- `docs/plan`:
  - create initial `PLAN-<task-id>-v1.0.md` before implementation
  - when plan changes, create next version file (`v1.1`, `v1.2`, ...)
  - preserve previous versions for audit and ping-pong traceability
- `docs/report`:
  - write one evaluator report per feedback per round
  - evaluator label must be exactly one of `gemini`, `claude`, `codex`
  - keep report file names version-aware (`PLAN-...-vX.Y-review-<evaluator>-rNN.md`)
- `docs/shadow/project-shadow.md`:
  - refresh architecture summary, module map, integrations, and constraints
  - keep concise and high-signal

## Quality checks
- Check that every user decision is traceable to a decision file.
- Check that every task/hotfix/PR/release/incident has related decision records when a user choice was made.
- Check that shadow dictionary matches current structure and naming.
- Check that task status reflects actual implementation state.
- Check that no secret values appear in any docs file.

Mode guidance:
- advisory mode: keep development flow fast, surface warnings
- strict mode: block merge/deploy when docs guardrails fail

## Minimal checklist
- [ ] Task file updated
- [ ] Decision file created/updated
- [ ] Plan file created/updated with semantic version (`v1.0`, `v1.1`, ...)
- [ ] Evaluator report file(s) added (`gemini|claude|codex`)
- [ ] Shadow dictionary refreshed
- [ ] Decision index updated
- [ ] No secrets in docs
