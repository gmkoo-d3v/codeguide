# Doc-Gardening Agent Workflow

Use this reference to keep repository docs continuously synchronized with code and decisions.

## Objective
- Keep workspace docs under `docs/` current for material tasks.
- Prevent stale context that causes wrong agent behavior.

## Execution points
- Run once before implementation when the task is material architecture, multi-file, cross-service, delegated, or durable planning work.
- Run once after implementation and validation when the docs lifecycle was started.
- Run on plan pivot or major scope change.
- For urgent hotfix, record minimum decision/task data immediately, then run full sync within 24 hours.
- Default user experience is zero-command when docs lifecycle is justified: the agent runs these steps automatically.
- Skip this workflow for small direct answers and trivial edits unless the user explicitly requests docs sync.

Recommended command flow:
- `scripts/run_codeguide.sh <project-root> --mode auto` (preferred semi-auto; docs resolve to `<project-root>/../docs`)
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
- Trigger condition: user invokes this skill for material architecture, multi-file, cross-service, delegated, or durable planning work.
- Agent action:
  - supervising lead architect runs start sync automatically with `--task-status in_progress`
  - supervising lead architect delegates plan drafting/review to sub-agents only when the user explicitly requested delegation or external review and the task is separable enough to justify it
  - supervising lead architect delegates implementation to coding sub-agents with disjoint ownership only when explicitly requested and practical
  - supervising lead architect runs finish sync automatically with `--task-status done` (or `blocked`)
  - bootstrap `docs/plan/PLAN-<task-id>-v1.0.md` automatically when planning artifacts are needed
  - maintain `orchestration/ORCH-<task-id>.md` for delegated or externally reviewed active tasks
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
  - preserve previous versions for audit and orchestration traceability
- `docs/report`:
  - write one evaluator report per feedback per round
  - evaluator label must be exactly one of `gemini`, `claude`, `codex`
  - keep report file names version-aware (`PLAN-...-vX.Y-review-<evaluator>-rNN.md`)
  - `execution_mode: supervisor_subagents` tasks must have at least one evaluator report before strict validation/merge handoff
- `docs/shadow/`:
  - refresh the top router, `_global.md` when applicable, bucket indexes, unit overviews, and affected concern leaves
  - keep `project-shadow.md` navigation-only
  - keep `_global.md` optional and cross-unit only
  - keep bucket `_index.md` files membership-only
  - keep unit `overview.md` files as landing docs plus concern routing
  - keep concern leaf docs factual and concrete
- `docs/orchestration`:
  - record supervising lead architect identity, delegated agent roles, owned scopes, and exception notes

## Quality checks
- Check that every user decision is traceable to a decision file.
- Check that every task/hotfix/PR/release/incident has related decision records when a user choice was made.
- Check that shadow routing docs match current structure and naming.
- Check that the default read path remains `project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf`.
- Check that any moved shadow doc leaves a thin redirect shim at the old path and archives the replaced body under `_deprecated` or `_obsolete`.
- Check that task status reflects actual implementation state.
- Check that no secret values appear in any docs file.

Mode guidance:
- advisory mode: keep development flow fast, surface warnings
- strict mode: block merge/deploy when docs guardrails fail

## Minimal checklist
- [ ] Task file updated
- [ ] Decision file created/updated
- [ ] Plan file created/updated with semantic version (`v1.0`, `v1.1`, ...)
- [ ] Evaluator report file(s) added (`gemini|claude|codex`) when `execution_mode: supervisor_subagents`
- [ ] Shadow router, `_global.md` when applicable, bucket indexes, unit overviews, and affected leaf docs refreshed
- [ ] Thin redirect shims added for moved shadow paths and replaced bodies archived under `_deprecated` or `_obsolete`
- [ ] Decision index updated
- [ ] No secrets in docs
