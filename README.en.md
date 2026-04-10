# codeguide

For the Korean-first public README, see [README.md](./README.md).

`codeguide` is a documentation-first LLM collaboration skill for architecture governance, decision traceability, and repeatable docs lifecycle automation.

It started from manual markdown operations in a final bootcamp project and evolved into a reusable shell-based workflow that keeps project context, decisions, plans, and validation rules synchronized.

## Problem

Typical LLM-assisted development breaks down in predictable ways:

- context disappears between sessions
- architecture decisions are made but not recorded
- implementation drifts away from the agreed plan
- unrelated files pollute the active working context
- documentation quality depends on individual discipline

`codeguide` addresses those problems with a docs-as-system-of-record workflow and lightweight automation scripts.

## Core Structure

- `docs/task`, `docs/shadow`, and `docs/decisions` split active work, current system state, and architectural decisions into separate concerns
- 5-axis decision recording keeps every meaningful change grounded in `Why`, `What`, `How`, `Where`, and `Verify`
- Plan Ping-Pong Loop supports iterative plan review with external evaluators before implementation handoff
- Change Scope Policy separates `docs-only` work from `code-or-runtime` work
- Orchestration documents capture supervising agent, delegated sub-agents, and owned scopes for multi-agent execution
- Workspace docs live outside the repo root at `../docs`, which reduces repo noise while keeping a shared source of truth

## Features

### 1. Workspace docs scaffold

[`scripts/init_docs_scaffold.sh`](./scripts/init_docs_scaffold.sh) creates an idempotent docs workspace:

- `docs/task`
- `docs/shadow`
- `docs/decisions`
- `docs/plan`
- `docs/report`
- `docs/orchestration`

It also generates templates such as task, decision, review, and orchestration documents.

### 2. Docs gardening automation

[`scripts/doc_garden.sh`](./scripts/doc_garden.sh) creates or updates task and decision documents while preserving existing non-empty values by default.

Key behaviors:

- writes shared `risk_level` to both task and decision docs
- protects existing values from accidental empty overwrites
- updates orchestration metadata for delegated workflows
- appends shadow notes for architecture/state synchronization

### 3. Lifecycle runner

[`scripts/run_codeguide.sh`](./scripts/run_codeguide.sh) is the main entry point for task execution flow.

It can:

- initialize the docs lifecycle
- infer or accept explicit task IDs
- synchronize task, decision, orchestration, and shadow records
- enforce `docs-only` vs `code-or-runtime` boundaries
- gate runtime commands through an allow-list in `code-or-runtime` mode

### 4. Documentation validation

[`scripts/validate_docs.sh`](./scripts/validate_docs.sh) validates the workspace docs in `advisory` or `strict` mode.

Checks include:

- required field presence and non-empty values
- freshness of active task and shadow documents
- line-count constraints for docs hygiene
- plan/review/orchestration consistency
- secret-pattern scanning for markdown docs

### 5. English-only docs policy check

[`scripts/check_english_docs.sh`](./scripts/check_english_docs.sh) checks curated markdown documents for Korean text so the skill stays maintainable as a public artifact.

### 6. Regression coverage

[`tests/codeguide.bats`](./tests/codeguide.bats) provides Bats-based regression tests for:

- overwrite protection
- task/decision synchronization
- orchestration bootstrapping
- strict validation failures
- secret scan edge cases
- workspace docs root behavior

## How To Use

Set the root once:

```bash
export CODEGUIDE_ROOT="$HOME/.codex/skills/codeguide"
```

Initialize the workspace docs scaffold:

```bash
"$CODEGUIDE_ROOT/scripts/init_docs_scaffold.sh" /path/to/project
```

Start or sync a task lifecycle:

```bash
"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" /path/to/project \
  --mode auto \
  --task-id search-nav-01 \
  --task-status in_progress \
  --shadow-note "search and navigation updated"
```

Create or update task and decision records directly:

```bash
"$CODEGUIDE_ROOT/scripts/doc_garden.sh" /path/to/project \
  --task-id search-nav-01 \
  --task-title "Refine search and navigation flow" \
  --decision-id nav-structure-01 \
  --decision-title "Adopt docs-first navigation updates" \
  --risk-level medium
```

Validate the docs before handoff or CI:

```bash
"$CODEGUIDE_ROOT/scripts/validate_docs.sh" /path/to/project --mode advisory
"$CODEGUIDE_ROOT/scripts/validate_docs.sh" /path/to/project --mode strict
```

Verify curated markdown stays English-only:

```bash
"$CODEGUIDE_ROOT/scripts/check_english_docs.sh" "$CODEGUIDE_ROOT"
```

Run regression tests:

```bash
bats "$CODEGUIDE_ROOT/tests/codeguide.bats"
```

## Example Workflow

1. Initialize `../docs` for a project.
2. Start a task with `run_codeguide.sh`.
3. Record task and decision context with `doc_garden.sh`.
4. Maintain plan and review documents during the Plan Ping-Pong Loop.
5. Re-sync shadow and orchestration docs after material changes.
6. Run `validate_docs.sh` before handoff.
7. Close the lifecycle with `--task-status done`.

## Project Structure

```text
codeguide/
├── README.md
├── README.en.md
├── SKILL.md
├── agents/
├── references/
├── scripts/
└── tests/
```

- `SKILL.md`: operating contract and workflow policy
- `agents/`: skill-facing agent configuration
- `references/`: curated governance, architecture, and review references
- `scripts/`: runnable workflow automation
- `tests/`: regression coverage for the shell tooling

## Evolution

- manual markdown operations in a bootcamp final project
- repeated pain around context loss and decision drift
- shell scripts for repeatable docs lifecycle management
- multi-agent orchestration rules with a supervising architect model
- validation gates for consistency, freshness, and secret hygiene

## Why This Repo Matters

This repository is not a CRUD demo or a one-off project delivery artifact.

It is a reusable engineering workflow asset that captures how I structure LLM-assisted software work:

- make decisions explicit
- separate active tasks from current system state
- keep plans reviewable
- reduce context noise
- automate quality gates around documentation and execution
