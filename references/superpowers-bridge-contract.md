# Superpowers Bridge Contract

This contract governs the harmonization between `/using-superpowers` (Agile UI artifacts & subagent workflows) and `/codeguide` (System of Record in `docs/`).

## 1. Non-Destructive Symlink & Reference Registration Protocol

- **Superpowers In-Place Preservation**: Plan files and artifacts generated via Superpowers (`.superpowers/plans/`, AGY artifacts `implementation_plan.md`) must **NEVER be deleted, renamed, or moved** out of their original paths to ensure Superpowers skills continue to function without error.
- **Automated Script Execution**:
  - Symlink creation and task index registration are **executed mechanically via scripts** (e.g. `codeguide/scripts/doc_garden.sh` or automation scripts), not manual LLM text edits.
  - The script automatically:
    1. Creates relative Symbolic Link `docs/plan/PLAN-<task_id>-v1.0.md` pointing to the Superpowers draft path.
    2. Updates `docs/task/task-index.md` ledger (`TASK-<task_id> | in_progress`).
    3. Scaffolds `docs/task/TASK-<task_id>.md` and `docs/orchestration/<task_id>/ORCH.md`.

## 2. Multi-Agent & External CLI Delegation Protocol

- **Model-Agnostic Delegation**: Subagents and external CLIs (such as Anthropic/Claude, DeepSeek, or native AGY subagents) are assigned roles based on task-specific orchestration plans (`docs/orchestration/<task>/ORCH.md`).
- **Durable File Handoffs**: All external CLI and subagent calls must pass durable markdown request/response/provenance files under `docs/orchestration/<task_id>/`.
- **Dual Co-Inspection Gate**: Before marking a task `done` in `docs/task/task-index.md`, the Main Supervising Agent and assigned reviewer/evaluator must complete a dual co-inspection of code edits and test results.
