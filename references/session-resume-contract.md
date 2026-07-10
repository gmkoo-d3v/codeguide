# Session Resume Contract

Use this reference when starting a session on a project with active tasks, when checkpointing work state, or after context compaction.

## Problem
A fresh session (or a post-compaction self) does not remember the previous session's goal, verification state, or next step. Docs are the only durable memory, so every in_progress task must carry a resume capsule that restores working state from a bounded read.

## Resume capsule fields (on the TASK file)

Script-maintained — written ONLY by `doc_garden.sh --resume-checkpoint`, never by hand (the P0/P1 lesson: hand-maintained derivable fields rot):

```markdown
- resume_source_head:      # source-repo HEAD sha + short dirty summary
- resume_changed_files:    # working-tree changes, SOURCE-REPO-relative paths, sorted, capped (top 10 + count)
- resume_checkpointed_at:  # UTC ISO timestamp
- resume_state_revision:   # monotonic integer, incremented per checkpoint
```

Agent-maintained — exactly three, no more (hard cap; adding a fourth requires amending this contract):

```markdown
- resume_next_action:      # the exact next step, concrete enough to execute cold
- resume_last_verified:    # the last state PROVEN true and how (command/suite/review)
- resume_blockers:         # what stops progress, or `none`
```

The snapshot fields come from the SOURCE repo via `codeguide_source_root` (see `references/docs-system-of-record.md` source-root precedence), so they stay meaningful in split-root layouts.

## Checkpoint cadence (event-driven, not token-driven)
Checkpoint after any of: a verified milestone (suite green, review verdict in), a plan/phase/ownership change, immediately before a handoff or an expected context compaction, and at session end for any task staying in_progress. One command per checkpoint:

```bash
<skill-dir>/scripts/doc_garden.sh <project-root> --task-id <id> --resume-checkpoint \
  --resume-next-action "..." --resume-last-verified "..." --resume-blockers "none"
```

Do not store conversation content, private reasoning, or raw logs — the capsule records STATE, not transcripts.

## Recovery read order (fixed; budget ≈ router + index + one task + one plan)
1. Read the project router (`CLAUDE.md`/`AGENTS.md`) and `docs/task/task-index.md` ONLY.
2. Pick the task: the one the user names, else the session's own claim in `docs/task/.claims/`, else — if multiple are in_progress — ask; never guess by mtime.
3. Read that TASK file. Its resume capsule is the state of record: goal (objective), last proven state (resume_last_verified), next step (resume_next_action), blockers, changed paths.
4. Compare `resume_source_head` against the live source repo (`git -C <source-root> rev-parse HEAD` + status). A mismatch means the checkpoint is STALE: re-verify `resume_last_verified` before acting on it, and say so.
5. Read only what the TASK points at: the `consumes_plan_ref` plan, its ORCH capsule, and the shadow units it names. Nothing else by default.
6. Use Serena starting from the files in `resume_changed_files`; re-verify material claims against direct source before editing.

After context compaction, do NOT trust the compaction summary for task state: re-run this read order (steps 3-6) — the capsule, not the summary, is the state of record.

## Enforcement tiers
- Advisory: an in_progress task without the resume capsule fields warns (adoption nudge; pre-contract corpora keep working).
- Strict: an in_progress task whose capsule fields are PRESENT but with empty `resume_next_action` or `resume_last_verified` fails — a declared capsule must be truthful.
- `validate_docs.sh` warns (both modes, never blocking) when `resume_state_revision` is present but non-numeric. A single-snapshot validator cannot detect revision regressions or lost updates; concurrency protection comes from the checkpoint command itself (it serializes the read-modify-write with the task-file lock) layered on the concurrent-session claim contract in `references/docs-system-of-record.md`.
