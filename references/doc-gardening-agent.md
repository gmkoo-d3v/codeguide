# Doc-Gardening Agent Workflow

Use this reference to keep repository docs continuously synchronized with code and decisions.

## Objective
- Keep project docs under `docs/` current for material tasks.
- Prevent stale context that causes wrong agent behavior.

## Execution points
- Run once before implementation when the task is material architecture, multi-file, cross-service, delegated, or durable planning work.
- Run once after implementation and validation when the docs lifecycle was started.
- Run on plan pivot or major scope change.
- For urgent hotfix, record minimum decision/task data immediately, then run full sync within 24 hours.
- Default user experience is zero-command when docs lifecycle is justified: the agent runs these steps automatically.
- Skip this workflow for small direct answers and trivial edits unless the user explicitly requests docs sync.

Recommended command flow:
- `scripts/run_codeguide.sh <project-root> --mode auto` (preferred semi-auto; docs resolve to `<project-root>/docs`)
- `scripts/doc_garden.sh <project-root> --task-id <TASK_ID> --task-status in_progress`
- `scripts/doc_garden.sh <project-root> --task-id <TASK_ID> --decision-id <DECISION_ID> --scope-type <type> --selected-option "<choice>"`
- `scripts/validate_docs.sh <project-root> --mode advisory`
- `scripts/validate_docs.sh <project-root> --mode strict` (CI)

## Semi-auto inference logic (`run_codeguide.sh`)
- `scope_type`:
  - branch prefix `hotfix/`, `release/`, `incident/`, `pr/`, `ops/` -> mapped scope
  - otherwise `task`
- `task_id`:
  - explicit `--task-id` wins (accepts canonical `<id>` or display form `TASK-<id>`; one leading `TASK-` prefix is stripped before downstream use)
  - else branch pattern `ABC-123`
  - else branch numeric id, such as `feature/123-name`
  - else most recent `docs/task/TASK-*.md`
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
  - if other Claude Code sessions may be working the same project concurrently, atomically claim the task first (`mkdir docs/task/.claims/<task-id>/`; abort and pick another task if it already exists) before running start sync with `--task-status in_progress` (see `references/task-state-contract.md` Concurrent session claim contract)
  - supervising lead architect runs risk preflight before sub-agents, external reviewers, or ping-pong loops
  - if preflight finds a safety, privacy, permission, destructive-action, external-side-effect, sensitive-data, scope, or user-decision gate, stop before delegation/external review until the user approves the exact next step
  - default `execution_mode` is `solo`; delegated agent fields, external review fields, or `supervisor_subagents` require explicit `risk_preflight_status`
  - `approved` preflight requires `approval_required: true`, concrete approval metadata, and a main-thread recorder rather than evaluator/tool identity
  - supervising lead architect delegates plan drafting/review to sub-agents only when the user explicitly requested delegation or external review, preflight permits it, and the task is separable enough to justify it
  - for `review_mode: claude_subagents`, pick the sub-agent model tier from `risk_level`: `high`/`critical` -> `model: sonnet` (deep tier), `low`/`medium`/unset -> `model: haiku` (fast tier), unless the user explicitly asked for a specific depth; a project role-routing policy in the project's governance docs supersedes this default inside full role-split pipelines (record the applied policy in `delegation_note`); independent-scope sub-agents may run in parallel in one message
  - supervising lead architect delegates implementation to coding sub-agents with disjoint ownership only when explicitly requested and practical
  - supervising lead architect runs finish sync automatically with `--task-status done` (or `blocked`)
  - bootstrap `docs/plan/PLAN-<task-id>-v1.0.md` automatically when planning artifacts are needed
  - maintain `orchestration/<task-id>/ORCH.md` for delegated or externally reviewed active tasks
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
  - never move or archive `TASK-*.md`; `task-index.md` is the single source of truth for lifecycle state, done tasks stay flat
  - remove `docs/task/.claims/<task-id>/` when a task leaves `in_progress` (finish sync)
- `docs/decisions`:
  - create/update `decision-<id>.md` with selected option and plan
  - include `scope_type`, `chosen_by`, and links (`linked_pr`, `linked_hotfix`) when applicable
  - update `decision-index.md`
- `docs/plan`:
  - create initial `PLAN-<task-id>-v1.0.md` before implementation
  - when plan changes, create next version file (`v1.1`, `v1.2`, ...)
  - preserve previous versions for audit and orchestration traceability
  - never move plan files to an archive folder and never create a separate `plan-index.md`; they stay discoverable via `task_id` filename globbing
- `docs/report`:
  - write one evaluator report per feedback per round
  - external CLI evaluator label is the actual runner (`agy`, `claude`, etc.); model identity belongs in requested/actual route and CLI model fields
  - keep report file names version-aware (`PLAN-...-vX.Y-review-<runner>-<model-slug>-rNN.md`)
  - `execution_mode: supervisor_subagents` tasks must have at least one evaluator report before strict validation/merge handoff
- `docs/shadow/`:
  - refresh the top router, `_global.md` when applicable, bucket indexes, unit overviews, and affected concern leaves
  - keep `project-shadow.md` navigation-only
  - keep `_global.md` optional and cross-unit only
  - keep bucket `_index.md` files membership-only
  - keep unit `overview.md` files as landing docs plus concern routing
  - keep concern leaf docs factual and concrete
- `docs/orchestration`:
  - record supervising lead architect identity, delegated agent roles, owned scopes, risk preflight status, approval refs, and exception notes
  - never move a task's `orchestration/<task-id>/` capsule to an archive folder; other docs cite its round files by literal path, so relocating it silently breaks those citations
- `docs/issues/` (when a project has one): this is the one series that DOES physically move files, from `current/` to `resolved/`, at close time — see the Issue tracker contract in `DOC-GOVERNANCE.md`

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
- [ ] Evaluator report file(s) added when `execution_mode: supervisor_subagents`
- [ ] Shadow router, `_global.md` when applicable, bucket indexes, unit overviews, and affected leaf docs refreshed
- [ ] Thin redirect shims added for moved shadow paths and replaced bodies archived under `_deprecated` or `_obsolete`
- [ ] Decision index updated
- [ ] No secrets in docs
