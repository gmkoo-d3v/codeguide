# Docs System of Record

Use this reference to initialize agent-readable repository documentation and as the thin hub for the docs system. It keeps only cross-cutting defaults, the required directory tree, script entry points, source-root/local-only-repo rules, and secret rules; domain policy for tasks, shadow, and orchestration lives in the three linked contracts below.

For repeatable setup, run:
- `scripts/run_codeguide.sh <project-root> --mode auto`
- `scripts/init_docs_scaffold.sh <project-root>`
- `scripts/doc_garden.sh <project-root> --task-id <TASK_ID>`
- `scripts/validate_docs.sh <project-root> --mode advisory`
- `scripts/validate_docs.sh <project-root> --mode strict`

Default assumption:
- Do not require RAG or embedding for baseline operation.
- Use project docs files (`task`, `shadow`, `decisions`, `plan`, `report`, `orchestration`) as durable memory first.
- Default operation is zero-command for the user when docs lifecycle is justified; the agent runs docs lifecycle commands for material architecture, multi-file, cross-service, delegated, or durable planning work.
- Skip docs lifecycle commands for small direct answers and trivial edits unless the user explicitly requests documentation sync.
- Reusable skills projects are the only built-in docs-root exception: if a git root is itself a skill package with `SKILL.md` metadata, has no local `docs/`, and its parent has `docs/`, scripts may use the parent as the system-of-record root. Ordinary app/service repositories must keep docs inside their own project root.
- Source root vs docs root: git-dependent behavior (branch-based task inference, `git_diff` shadow refresh, impact/coverage change sets) targets the SOURCE repository resolved by `codeguide_source_root` (bash) / `codeguide_paths.source_root_for` (python), never the docs root. Resolution precedence, most explicit first: `CODEGUIDE_SOURCE_ROOT` (normalized to its git toplevel), the `<project-root>/.codeguide-source-root` marker file naming the source repo path (the explicit contract for docs-only parent repos), the invoking path's own repo when it is a skill package, the project root's enclosing repo (an ordinary project — a vendored skill-package child never hijacks it), and a unique skill-package child repo only when the project root is not inside any repo. Explicit declarations (override or marker) that do not resolve inside a git repository fail closed with a distinct diagnostic — a declared source that is not a repo is a configuration error, not a degradable state; ambiguity fails loudly the same way, and only the DETECTION paths (no declaration anywhere) downgrade to non-git fallbacks with an explicit warning.
- The docs root may be tracked in a local-only git repo (no remote, never pushed) for history and rollback; docs must never be absorbed into a distributed source/skill repo.

## Change scope execution
- `run_codeguide.sh` supports `--change-scope docs-only|code-or-runtime` to control validation behavior.
- `docs-only` (default): runs docs lifecycle + docs validation only.
- `code-or-runtime`: additionally runs user-provided runtime commands via `--runtime-test-cmd`, `--runtime-lint-cmd`, `--runtime-e2e-cmd`.
- Runtime commands are never hardcoded; they must be passed as CLI options.

## Required structure

`<project-root>` is the selected project root; when invoked from inside a git repository, scripts resolve it to that repository root. Resolve docs to `<project-root>/docs`.

For reusable skills packages, `<project-root>` may be the parent workspace root when the skill package is intentionally shared through symlinks and the parent contains the project-level `docs/`.

```text
project-root/
├── docs/
    ├── task/
    ├── shadow/
    │   ├── project-shadow.md
    │   ├── _global.md
    │   ├── apps/
    │   │   └── _index.md
    │   ├── services/
    │   │   └── _index.md
    │   ├── packages/
    │   │   └── _index.md
    │   ├── infra/
    │   │   └── _index.md
    │   ├── data/
    │   │   └── _index.md
    │   ├── _deprecated/
    │   └── _obsolete/
    ├── decisions/
    ├── plan/
    ├── report/
    └── orchestration/
```

Create these project-root files if missing:
- `<project-root>/AGENTS.md`
- `<project-root>/CLAUDE.md`
- `<project-root>/docs/task/project-dictionary.md`
- `<project-root>/docs/task/task-index.md`
- `<project-root>/docs/shadow/project-shadow.md`
- `<project-root>/docs/shadow/_global.md`
- `<project-root>/docs/shadow/apps/_index.md`
- `<project-root>/docs/shadow/services/_index.md`
- `<project-root>/docs/shadow/packages/_index.md`
- `<project-root>/docs/shadow/infra/_index.md`
- `<project-root>/docs/shadow/data/_index.md`
- `<project-root>/docs/decisions/decision-index.md`
- `<project-root>/docs/plan/PLAN-template.md`
- `<project-root>/docs/report/LLM-REVIEW-template.md`
- `<project-root>/docs/orchestration/_templates/ORCH.md`

## Domain contracts
- Task/decision dictionaries, task-index rules, concurrent-session claims, no-archive policy, update rules, hotfix exception, freshness SLA: `references/task-state-contract.md`
- Shadow buckets, document roles, every shadow template, anti-dump line caps: `references/shadow-system-contract.md`
- ORCH gate template and allowed values, project dictionary, plan and evaluator-report templates, PR/commit pointer: `references/orchestration-review-contract.md`

## Secret and sensitive data rules
- Never put raw secrets in docs.
- Never put key/token/password/private key values in docs.
- In docs, reference only variable names such as `PROVIDER_API_KEY`, `DB_PASSWORD`, `JWT_SECRET`.
- If sensitive data is accidentally documented, redact immediately and log remediation in `docs/decisions`.
