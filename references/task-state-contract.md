# Task State Contract

Use this reference for task and decision lifecycle: the task and decision dictionaries, task-index rules, concurrent-session claims, the no-archive policy, update rules, the hotfix exception, and the freshness SLA. See `references/docs-system-of-record.md` for cross-cutting defaults, the required directory tree, and secret rules.

## Data safety rules
- Empty values never overwrite existing non-empty fields during doc-gardening. Use `--allow-empty-overwrite` to explicitly clear a field.
- Axis values (Why/What/How/Where/Verify) are only written when explicitly provided; no generic defaults are injected.
- `task_id` inference priority: explicit `--task-id` > branch pattern (ABC-123 or numeric) > latest task file > timestamp fallback.
- `run_codeguide.sh --task-id` accepts both the canonical `<id>` and the display form `TASK-<id>`; exactly one leading `TASK-` prefix is stripped so `doc_garden.sh` (which always writes `docs/task/TASK-<id>.md`) never receives a double-prefixed id. `doc_garden.sh --task-id` itself takes the canonical `<id>` only.
- `task-index.md` rows are placed under the correct status section (Planned/In Progress/Blocked/Done/Superseded/Cancelled) and deduplicated.
- `validate_docs.sh --mode strict` enforces non-empty values for required fields, not just key existence.
- Freshness checks use `last_updated` field when available; fall back to file mtime only when the field is absent.
- Validation checks plan/report contracts:
  - active tasks (`in_progress|blocked|done`) require at least one `PLAN-<task-id>-v*.md`
  - evaluator reports must follow `PLAN-...-review-<runner>-<model-slug>-rNN.md`
  - `in_progress|blocked` tasks require a fresh evaluator report for the LATEST plan version; `done` tasks require at least one identity-valid report anywhere in the plan lineage (`PLAN-<task-id>-v*-review-*.md`) — plan versions added after close must not reopen the gate retroactively
  - plans and ORCH capsules of terminal-status tasks (`done|superseded|cancelled`) keep identity checks (task_id, plan_version) but are exempt from authorship-completeness fields (objective/scope/last_updated) and size caps: closed artifacts are immutable evidence and later schema generations are not applied to them retroactively

## Task dictionary template

Use one file per task: `docs/task/TASK-<id>.md`

```markdown
# TASK-<id>

- title:
- objective:
- acceptance_criteria:
- non_goals:
- affected_modules:
- interfaces_changed:
- data_migrations:
- test_scope:
- risks:
- risk_level:
- consumes_plan_ref:
- status: planned | in_progress | blocked | done | superseded | cancelled
- disposition: # required for superseded/cancelled: why the task closed without completing
- outcome: # for done status; mutually exclusive with disposition (outcome for done, disposition for superseded/cancelled)
- owner:
- claimed_at:
- due_date:
- axis_why: # principles applied (SOLID/DRY/KISS/YAGNI/LoD/SoC/CQS/POLA)
- axis_where: # structure and boundary choice
- axis_verify: # test strategy (TDD/pyramid/FIRST)
- resume_source_head:      # source-repo HEAD sha + short dirty summary
- resume_changed_files:    # source-repo-relative changed paths, sorted and capped
- resume_checkpointed_at:  # UTC ISO timestamp
- resume_state_revision:   # monotonic integer, incremented per checkpoint
- resume_next_action:      # exact next step, concrete enough to execute cold
- resume_last_verified:    # last state proven true and how
- resume_blockers:         # blocker, or `none`
```

The `resume_*` capsule is maintained under `references/session-resume-contract.md`; use that contract for field ownership, checkpointing, and recovery read order.

## Metadata envelope

Every envelope-aware rule, writer, and scan in this repo answers the boundary question with ONE shared implementation (`doc_lines_envelope` in `codeguide/scripts/codeguide_doc_lines.sh`): the metadata envelope is the fence-stripped lines of a document BEFORE the first unfenced `##` heading (blank lines and indentation preserved). Everything at or below that heading is narrative by contract and is never schema. Consequences:

- A close field (`outcome`, `disposition`) below the first unfenced `##` heading is narrative and never satisfies the close-record gate; meaningful close-time text that lives only below the boundary must either be migrated into the metadata envelope or marked honestly with the legacy marker.
- The unknown-key scan covers only envelope lines; fenced example keys and narrative-section keys (`verdict`, `pending`, `reason`) are never scanned.
- The task-index row summary projects from envelope fields only.
- A fenced `##` inside a quoted example is block content, not a boundary.

## Close-record gate (terminal statuses)

The terminal close-record matrix is a static invariant, not a transition rule: a task file that is ALREADY `done` with empty close fields fails without any transition being observed. Required fields, read from the metadata envelope only (`extract_field_block`):

| status | required | optional (never required, never injected) |
|--------|----------|------------------------------------------|
| `done` | `objective` + `acceptance_criteria` + `outcome` | `disposition` is not applicable |
| `superseded` / `cancelled` | `objective` + `disposition` | `outcome` |
| `planned` / `in_progress` / `blocked` | none | none |

- `outcome` is the close-time record for work that shipped (evidence: implementation commits/diffs, the migration audit, release-gate outputs). `disposition` explains a close without completing (successor task or reason). They are mutually exclusive: `outcome` for `done`, `disposition` for `superseded`/`cancelled`.
- Close-field values that are an EXACT match of a placeholder token (`tbd`, `TBD`, `n/a`, `none`, `미정`) fail under strict. Prefix or partial matching is forbidden: `tbd later`, `none of the above` are real content. The one exemption is the legacy marker literal `legacy — no close-time record found`, which is a truthful statement that the standard search protocol found no close-time record and passes.
- In Release A these checks are advisory-only (warnings); Release C promotes them to strict-mode failures by flipping `CLOSE_RECORD_STRICT_PROMOTED` in `validate_docs.d/30-rules-task.sh`.

## Legacy-key classification (envelope-bounded, measured)

Keys in the metadata envelope that predate this dictionary are classified as follows. Preserve-classified keys are registered dictionary members (no longer unknown; existing file content is left untouched as immutable evidence). Rename-classified keys move to the canonical key during migration (value normalized where noted) and are removed from the file afterward.

| key | classification | handling |
|-----|----------------|----------|
| `last_updated` | preserve | tool-generated key; allowed, never unknown |
| `plan_ref` | rename | → `consumes_plan_ref`, value normalized `docs/plan/PLAN-X-v1.0.md` → bare `PLAN-X-v1.0` |
| `decision_ref` | preserve | allowed reference key |
| `orchestration_ref` | preserve | allowed reference key |
| `reviewers` | preserve | allowed key |
| `close_out_note` | rename | → `outcome` (semantically equivalent close-time record) |
| `verdict` / `pending` / `reason` | n/a | narrative content below the envelope; never scanned |

## Standard search protocol

When a close-time record is not found on the task file, the default is evidence discovery before any legacy marker is written. Search sources, in order:

1. Same-`task_id` PLAN / REPORT / DECISION / ORCH documents (`docs/plan/PLAN-<task-id>-v*.md`, `docs/report/PLAN-<task-id>-*-review-*.md`, linked `docs/decisions/decision-*.md`, `docs/orchestration/<task-id>/ORCH.md`).
2. Commits referenced by the task's artifacts (plan/report/orchestration fields, `resume_source_head`, ORCH handoff dirs).
3. Commits returned by `git log` search for the `task_id`.

Evidence discovery is the default; each individual use of the legacy marker literal `legacy — no close-time record found` requires separate reviewer approval (no aggregated approvals), and the aggregate marker count is recorded in the migration audit.

`<project-root>/docs/task/task-index.md` should list task ids organized by status section (Planned/In Progress/Blocked/Done/Superseded/Cancelled). Rows are automatically moved between sections when task status changes.

`superseded` and `cancelled` are terminal statuses for tasks that close WITHOUT completing: `superseded` when a successor task absorbed the remaining scope, `cancelled` when the need lapsed (stale, overtaken by events). Both require a non-empty `disposition:` field naming the successor or the reason (strict-mode failure when missing). They are set by direct ledger edit at disposition time, not by the session wizard. Terminal tasks are inactive: no plan, orchestration capsule, or evaluator report is required, and their existing artifacts stay in place as immutable evidence per the no-archive policy. Do not use them to dodge a review gate on work that actually shipped — shipped work closes as `done`.

`consumes_plan_ref` is required when the matching ORCH capsule sets `external_review_required_for: implementation_start` and the task is `in_progress` or `done`. It must reference a same-task plan in the form `PLAN-<task-id>-vX.Y`; cross-task plan consumption is out of scope for this gate and warns instead of being treated as independent.

## Docs lifecycle (no physical archive for task/plan/orchestration)

Never physically move or archive `docs/task/TASK-*.md`, `docs/plan/PLAN-*.md`, or `docs/orchestration/<task-id>/`, even after a task reaches `status: done`. Keep them flat permanently.

- `docs/task/task-index.md` is the single source of truth for task/plan/orchestration lifecycle state. A completed task is managed, not archived: its row stays under the correct status section and its `TASK-*.md`/`PLAN-*.md`/`orchestration/<task-id>/ORCH.md` files stay exactly where they are.
- Do not create `plan-index.md` or any second ledger for plan files. Plan files are already keyed by `task_id` via filename (`PLAN-<task-id>-vX.Y.md`), so `task-index.md` plus filename globbing is sufficient; a second index would drift from the first, reintroducing the exact staleness problem an index is meant to solve.
- `scripts/validate_docs.sh` enforces `task-index.md` accuracy in both directions: every `TASK-*.md` must have a row, every row must point at an existing task file listed under the section matching its actual `status:` field, and no task_id may appear more than once.
- `docs/issues/` (see `docs/issues/README.md` when a project has one) is the one exception that does physically move files, between `current/` and `resolved/`, because closing an issue produces a new `RESOLUTION-*.md` at that same moment — the move is a natural lifecycle event, not a later cleanup pass. `validate_docs.sh` enforces that pairing and index consistency the same way.
- Rationale: task/plan/orchestration files are cross-referenced by concrete literal paths from other docs (evaluator report rounds, `ORCH.md` fields such as `external_review_result_ref`, prose citations of prior round files by name). Physically moving them at scale silently breaks those citations in ways no validator catches. A folder growing large and looking cluttered is an accepted tradeoff — the goal of docs governance is that work stays tracked and auditable, not that directories look tidy.

## Concurrent session claim contract

When multiple Claude Code sessions run against the same project at once, use an atomic filesystem claim so two sessions cannot pick up the same task:

- Before setting `status: in_progress`, atomically claim the task: `mkdir docs/task/.claims/<task-id>/` (a bare directory, no contents required). `mkdir` fails if the directory already exists, so only one concurrent session ever wins the claim.
- If the `mkdir` fails, the task is already claimed by another session; pick a different task instead of starting work on it.
- After a successful claim, set `owner:` (a session-identifying value) and `claimed_at:` (ISO timestamp) on the task file, then move its `task-index.md` row to `In Progress`.
- On completing or abandoning the task, remove `docs/task/.claims/<task-id>/` in the same step that changes `status` away from `in_progress`.
- A stale claim (session crashed without releasing it) is detected the same way any stale in_progress task is: `last_updated` ages past the freshness threshold. Do not auto-release a stale claim; surface it to the user first.
- Sub-agents spawned within a session inherit that session claim; they do not need their own claim directories.
- `scripts/validate_docs.sh` treats `owner`, `claimed_at`, and the claim directory as recommended (advisory-mode warning) for `in_progress` tasks, the same tier as `risk_level`, so existing task corpora are not broken by adopting this contract. It always flags (strict-mode failure) a claim directory with no matching task file, or one that survives after its task leaves `in_progress`.

## Decision template

Use one file per decision: `docs/decisions/decision-<id>.md`

```markdown
# decision-<id>

- decision_id:
- title:
- date:
- scope_type: task | hotfix | pr | release | incident | ops | other
- status: proposed | accepted | superseded
- chosen_by:
- linked_task:
- linked_pr:
- linked_hotfix:
- context:
- selected_option:
- alternatives_considered:
- rationale:
- implementation_plan:
- impact_and_risks:
- risk_level:
- rollback_or_mitigation:
- axis_why: # principle rationale
- axis_what: # expression rules (naming/function/comments/format)
- axis_how: # implementation approach (pattern/refactor/smell)
- axis_where: # structural placement and boundaries
- axis_verify: # verification strategy and test evidence
```

`<project-root>/docs/decisions/decision-index.md` should organize decisions by status section (Proposed/Accepted/Superseded). Rows are automatically moved between sections when decision status changes. Legacy table format is auto-migrated on first update.

## Update rules
- Update docs for every task that runs the docs lifecycle.
- Before implementation, create an initial plan file (usually `v1.0`).
- For each feedback round, write evaluator-specific report files in `docs/report/` with runner route slug in the filename: `PLAN-<id>-<version>-review-<runner>-<model-slug>-rNN.md`.
- Set `risk_level: high|critical` on the task or a linked decision when the change is high risk.
- Record `risk_preflight_status`, `risk_preflight_recorded_by`, `risk_preflight_summary`, `approval_required`, `approval_ref`, and `approved_next_step` before delegated or external review work begins; `pass` pairs with `approval_required: false`, and `approved` pairs with `approval_required: true`.
- In advisory mode, active tasks without `risk_level` should emit a warning so teams can backfill the signal before strict policy tightens.
- If a task or any linked non-superseded decision has `risk_level: high|critical`, strict validation requires at least one adversarial evaluator report with `review_style: adversarial` plus `objection`, `counterproposal`, `rebuttal`, and `residual_risk`.
- When improving the plan, create a new versioned plan file (for example `v1.1`) instead of overwriting previous files.
- Repeat plan -> review -> revision until execution-ready, no new material findings appear, a hard gate blocks progress, or user stop. Do not use fixed iteration count, token budget, or cost cap as the primary stop condition.
- When user chooses any option, update or create a `decision-*` file immediately.
- Apply this to all work types: task, hotfix, PR, release, incident, and operations.
- When plan changes, append revised `implementation_plan` in the same `decision-*`.
- When task scope changes, update `TASK-*` and relevant dictionary keys.
- For tiny edits, reuse the current `TASK-*` file instead of creating unnecessary new task files.
- At task close, refresh the affected shadow router, `_global.md` when applicable, bucket indexes, unit overviews, and leaf docs.
- Keep 5-axis fields current:
  - tasks: maintain `axis_why`, `axis_where`, `axis_verify`.
  - decisions: maintain full `axis_why`, `axis_what`, `axis_how`, `axis_where`, `axis_verify`.
- Keep freshness SLA:
  - same-session changes should refresh the affected shadow graph entries in the same implementation change.
  - external git-driven changes should refresh shadow only on explicit user request.
  - `in_progress` task docs should be refreshed within 7 days.
  - `decision-index.md` should be updated in the same change as decision files.

## Hotfix exception policy
- At urgent release time, allow minimum required docs:
  - one `decision-*` with selected option, risk, and scope `hotfix`
  - one linked task status update
- Complete full task and affected shadow updates within 24 hours after release.
