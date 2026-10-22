# codeguide

`codeguide` is an outcome-first LLM collaboration skill built for architecture governance, decision traceability, and documentation lifecycle automation.

It started from manually maintaining markdown documents during a bootcamp final project and grew into a shell-based workflow that keeps project context, decisions, plans, and validation rules reproducibly synchronized.

## Motivation

LLM-driven development usually wobbles at these points:

- Context disappears when the session changes
- Architecture decisions get made but leave no record
- Implementation drifts away from the agreed plan
- Unrelated files pollute the current working context
- Documentation quality depends on personal habits

`codeguide` reduces these problems with a docs-as-system-of-record approach and lightweight automation scripts, focused on documenting and validating only as much as the runtime actually requires.

## Core Structure

- `docs/task`, `docs/shadow`, and `docs/decisions` separate active work, current system state, and architecture decisions
- Material changes, design decisions, and handoff work are recorded along five axes: `Why`, `What`, `How`, `Where`, `Verify`
- The Plan Ping-Pong Loop runs external evaluation only when needed and converges plans incrementally
- The Change Scope Policy separates `docs-only` and `code-or-runtime` work
- When delegation actually happens, orchestration docs record the supervising agent, delegated sub-agents, and owned scopes
- Project docs live under `docs/` in the selected project root, tracked alongside sub-units such as backend/frontend/app
- As an exception, a reusable skills project shared by multiple CLIs via symlinks may separate the skill package root from the project-level `docs/` root

## What This Skill Does

`codeguide` is less a collection of shell scripts than a skill that provides the operating rules and documentation workflow an agent follows during design, refactoring, review, and debug work.

The core expectations are:

- Adapt the ELI5 plain-language explanation style for Korean conversational replies, using simple words and familiar examples while preserving accuracy and requested depth. This guidance is based on the upstream [ELI5 skill](https://github.com/anthropics/claude-plugins-community/blob/main/eli5/skills/eli5/SKILL.md).
- Document task purpose, constraints, and risks before significant implementation
- Leave material choices as `decision-*` records explained through the five axes `Why/What/How/Where/Verify`
- Make plan-worthy work reviewable through `PLAN-*` and review documents
- Separate active work, current system state, and architecture decisions into distinct documents
- Run documentation and runtime validation together before handoff

In other words, the protagonist of this repository is not the `sh` files but the collaboration contract that makes LLMs behave consistently.

## Using It as a Skill

This skill matters most when you ask an agent to work under `codeguide`, rather than memorizing shell commands yourself.

Example requests (trigger phrasings preserved verbatim):

- `codeguide 기준으로 이 변경 설계 리뷰해줘` — review this change design under codeguide
- `codeguide로 리팩터링 계획부터 세우고 Why/What/How/Where/Verify로 정리해줘` — draft the refactoring plan first and organize it along Why/What/How/Where/Verify
- `codeguide로 이 버그를 repro -> hypothesis -> fix -> verification 흐름으로 잡아줘` — attack this bug through the repro -> hypothesis -> fix -> verification flow
- `high risk로 보고 plan review 한 번 더 돌려줘` — treat it as high risk and run one more plan review round
- `docs도 같이 동기화하면서 진행해줘` — proceed while keeping docs synchronized too

The typical flow:

1. The agent decides whether the current work is a `design`, `refactor`, `review`, or `debug` flow.
2. Based on task size and risk, it decides whether task, decision, plan, and orchestration documents are needed under the project root's `docs/`.
3. For high-risk changes it runs the plan review loop; high risk requires adversarial review.
4. After implementation it synchronizes shadow and document state where needed and runs relevant lint/test/e2e.
5. Finally it checks that sufficient evidence and validation exist, and stops when additional loops would not materially change the conclusion.

The point is not for the user to operate scripts, but to make the agent follow this skill's policy.

## Sub-Agent Orchestration

This skill does not assume solo work only. The default model is a supervising lead architect who sets direction, with role-specific sub-agents taking separated responsibilities when the user explicitly requests it and the work is large and separable enough.

- planner: drafts the plan
- reviewer: critically reviews the plan or change proposal for gaps, contradictions, omissions, and rule violations
- implementation agent: makes the actual code changes
- validation agent: tests, validates, and checks handoff readiness
- evaluator: leaves an `accept | revise | blocked` verdict in the report document; like the reviewer, it defaults to a defect-seeking rather than approval-seeking stance

When delegation actually happens, this role separation is recorded in `docs/orchestration/<task-id>/ORCH.md` and tracked through fields such as `execution_mode`, `supervisor_agent`, `planner_agents`, `reviewer_agents`, `implementation_agents`, `validation_agents`, `owned_scopes`, `risk_preflight_status`, and `approval_ref`.

Before starting sub-agents or an external evaluator, the main supervising lead architect must run risk preflight first. If safety, privacy, permission, destructive action, external side effect, sensitive data, scope, or user-decision gates apply, delegation/external review does not start; ping-pong starts only with a user-approved exact next step.

In particular, when `/codeguide` is used to request code writing or implementation together with an explicit `서브에이전트`-family trigger, the default — absent a specific reason otherwise — is to distribute planner/reviewer/evaluator/implementation/validation roles to sub-agents while the main agent acts as tech lead architect and supervisor rather than writing most of the code itself.

Orchestration rules also hold for `docs-only` work where delegation or external review occurred. Even in planning/review phases that run no code, if multiple parties were involved, the primary author and review mode are recorded in the docs.

## Internal Automation

Not the center of this README, but the skill automates its operating rules with a few shell scripts:

- [`scripts/codeguide`](./scripts/codeguide): single entry point bundling the scripts below into one subcommand interface (see [Single entry point: scripts/codeguide](#single-entry-point-scriptscodeguide))
- [`scripts/run_codeguide.sh`](./scripts/run_codeguide.sh): entry point for docs lifecycle start, sync, validation, and runtime validation
- [`scripts/run_external_plan_reviews.sh`](./scripts/run_external_plan_reviews.sh): semi-automatic ping-pong review command that requests `PLAN-*` reviews from two evaluators excluding the primary authoring tool, produces report documents, then stops
- [`scripts/doc_garden.sh`](./scripts/doc_garden.sh): task, decision, orchestration, and shadow document updates
- [`scripts/init_docs_scaffold.sh`](./scripts/init_docs_scaffold.sh): creates the project-root `docs/` default structure and templates
- [`scripts/validate_docs.sh`](./scripts/validate_docs.sh): validates document consistency, freshness, review/orchestration rules, and secret scan
- [`scripts/check_english_docs.sh`](./scripts/check_english_docs.sh): checks the English policy for curated operational docs
- [`scripts/shadow_policy_loader.py`](./scripts/shadow_policy_loader.py): reads only the fenced `yaml` registry block of shadow policy Markdown as the declared registry and checks parity with probe adapter implementations
- [`scripts/shadow_evidence_probe.py`](./scripts/shadow_evidence_probe.py): runs only validators registered in the static `AdapterRegistry`, converting shadow effect candidates into deterministic probe results
- [`scripts/shadow_review_queue.py`](./scripts/shadow_review_queue.py): converts effect candidates lacking evidence into a bounded human review queue
- [`scripts/shadow_llm_candidate_wrapper.py`](./scripts/shadow_llm_candidate_wrapper.py): wraps LLM drafts as non-promotable candidate artifacts
- [`scripts/shadow_user_decision_wrapper.py`](./scripts/shadow_user_decision_wrapper.py): creates guarded user_decision artifacts for final apply approvals and human fact-evidence decisions
- [`scripts/shadow_apply_gate.py`](./scripts/shadow_apply_gate.py): dry-run check of final shadow apply approval conditions
- [`scripts/shadow_effect_writer.py`](./scripts/shadow_effect_writer.py): writes gate-passed `confirmed/unknown/blocked/stale` structured effect records into the shadow effect_map, proposing possible next probe/decision commands as `next_actions` for blocked results
- [`tests/`](./tests/): feature-split bats regression suite for the automation above

The scripts are less the skill's body than an implementation layer that makes its operating principles repeatable.

For high-risk work, `run_external_plan_reviews.sh` reads the `risk_level` of the task or linked decision and automatically promotes one non-primary reviewer to an adversarial pass even when the user did not name an adversarial evaluator.

## Runtime Environment Contract

Supported toolchain: bash >= 3.2, python3 >= 3.9, bats-core >= 1.5, git; Python dev dependencies are just `requirements-dev.txt` (pytest). Runtime scripts keep a stdlib-only contract.

```bash
scripts/check_env.sh                                 # toolchain doctor (per-cause remediation output); same as the scripts/codeguide doctor alias
python3 -m pip install -r requirements-dev.txt      # install dev dependencies
scripts/check_all.sh                                 # single gate: env + bats + pytest + strict docs + English policy; same as the scripts/codeguide check alias
```

From a clean checkout, `check_all.sh` alone reproduces the full quality gate (dependency check, full test suite, strict docs validation). Tests do not depend on the calling shell's environment variables: `setup()` in `tests/codeguide_helper.bash` initializes `CODEX_SANDBOX*`, `CODEGUIDE_SOURCE_ROOT`, and `CODEGUIDE_*_BIN`, and sandbox behavior tests inject required variables per test.

`validate_docs.sh --gate external-review [--task-id <id>]` is the fail-closed counterpart of the advisory/strict document checks: it evaluates only the implementation-start external review await gate and exits 0 (not required or satisfied) or 1 (required and not satisfied); `run_codeguide.sh` runs it before moving a task to `in_progress` or `done`. `validate_docs.sh --format json` emits exactly one JSON object on stdout (`{mode, project_root, format_version, issues[{tier,id,caller,message}], counts, result}`), sends diagnostics to stderr, and returns the same exit code as text mode. Each issue's `id` is the name of the check function that raised it and `caller` is the upstream function that called it (top-level flow uses `main` for both) — a stable contract, so consumers distinguish rules by `(id, caller, message prefix)`; renaming check functions breaks ids and must be called out in the commit (default `--format text` output stays byte-frozen).

`scripts/check_all.sh --metrics-out <file>` appends one JSONL line per run with per-stage result and duration in seconds, forming the basis for runtime/flake trend collection (observation-only — behavior and output are unchanged without the flag), and `scripts/packaging_smoke.py` classifies the entire skill tree as SHIP/DEV-ARTIFACT/UNKNOWN and fails read-only hygiene checks when the deploy manifest contains disallowed entries (UNKNOWN).

## Validation & Reliability

What the automation verifies about itself, and where that stops. The reports behind these statements are in [`case-studies/`](./case-studies/).

- **Fail-closed approval gate.** `validate_docs.sh --gate external-review` (run by `run_codeguide.sh` before a task moves to `in_progress` or `done`) lets implementation start only when each required external review left a complete evidence set: the request, the sanitized response and a provenance manifest that agree on task, plan version, round and route, with the response bytes matching the recorded SHA-256. A bare `verdict: accept` file, an edited response, a missing manifest, or a waiver without a recorded user decision does not pass.
- **One contract for adversarial reviews.** The wrapper parser (`run_external_plan_reviews.sh`), the evidence verifier (`validate_docs_review_evidence.py`) and the Shadow v2 close gate apply the same field rule: all four debate keys present, `residual_risk` non-empty, the other three may be empty only on `accept`. `tests/review_contract_integration.bats` fails if the wrapper and the verifier ever disagree on a response, and its mock runners sit behind a `PATH` tripwire that refuses and records any real `agy`, `claude` or `codex` call.
- **Tests shown to be able to fail.** The contract tests were run against the previous code and fail there, and the suites were compared with an unmodified baseline rather than a remembered count. The default test run never executes the real `agy` (the live model-catalog comparison is opt-in: `CODEGUIDE_LIVE_AGY_CATALOG=1`), and `tests/pipe_safety.bats` keeps pipelines whose consumer exits early (`grep -q`, `head`) out of `scripts/`, because under `set -o pipefail` they turn a correct answer into a failure.
- **Known limits.** Pinned as current behavior in the tests (`KL-*`) or tracked as follow-ups, not claimed as fixed: a plan edited after its review, or a request altered after it was sent, is not detected; work that skips the harness is not gated; the review requirement is a field the agent writes; a done task's approval history is not re-checked; the evidence is consistency evidence, not attestation, so a writable workspace can still forge a matching manifest.

Case studies (Korean, point-in-time reports of the work as it happened):

- [External review approval gate hardening](./case-studies/external-review-gate-hardening.html)
- [Adversarial rule x approval gate integration](./case-studies/adversarial-gate-integration.html)
- [Test reliability hardening](./case-studies/test-reliability-hardening.html): early-exit pipes under `pipefail` (14 sites, 3 reproduced), the default run no longer executes the real `agy`, plan and request hash binding for approved reviews (on its own branch, not yet merged), and the model registry update.

## Single Entry Point: scripts/codeguide

Instead of memorizing individual script paths, `scripts/codeguide` exposes every automation entry point through one subcommand interface. Each subcommand forwards remaining arguments verbatim (quoted) to the target tool via `exec`, so `scripts/codeguide <subcommand> --help` shows the target tool's own usage.

```bash
scripts/codeguide                       # subcommand list + one-line descriptions (bare / -h / --help / help all identical)
scripts/codeguide <subcommand> --help   # delegates to the target tool's own usage
```

| Subcommand | Target script | Purpose |
| --- | --- | --- |
| `doctor` | `check_env.sh` | toolchain doctor |
| `check` | `check_all.sh` | single quality gate |
| `validate` | `validate_docs.sh` | document consistency/freshness/secret scan validation |
| `docs-sync` | `doc_garden.sh` | task/decision/orchestration/shadow document updates |
| `scaffold` | `init_docs_scaffold.sh` | initialize project `docs/` scaffold |
| `review` | `run_external_plan_reviews.sh` | ping-pong external plan review round |
| `shadow-impact` | `shadow_impact_report.py` | report sources changed without shadow doc updates |
| `shadow-coverage` | `shadow_coverage_report.py` | report changed sources not covered by any shadow doc |
| `shadow-metrics` | `shadow_metrics_report.py` | measure shadow doc token cost/size against caps |
| `shadow-digest` | `shadow_source_digest.py` | compute/verify source-of-truth content digests for shadow docs |

`check_all.sh` (= `scripts/codeguide check`) additionally supports two options for reproducible subset runs and failure-diagnosis artifact preservation:

- `--suite <fast|contract|external|shadow|full>`: restricts the bats stage to the given file subset. The default `full` runs the whole `tests/` tree identically to a flag-less run. If any suite member file is missing, execution fails loudly before any stage starts. The pytest stage runs only in the `full` suite (reported as skip otherwise).
  ```bash
  scripts/codeguide check --suite fast --skip-pytest   # reproduce a fast subset only
  ```
- `--artifacts <dir>`: tees each stage's stdout+stderr to `<dir>/<NN>-<stage>.log`, and the bats stage additionally leaves a JUnit report in `<dir>` (`--report-formatter junit --output <dir>`). Exit code semantics are unchanged; the summary prints the artifact directory path.
  ```bash
  scripts/codeguide check --artifacts .artifacts/check-all   # logs + JUnit preservation for failure diagnosis
  ```

## When to Call Scripts Directly

If you need a lower-level tool not covered by `scripts/codeguide` (the review queue/decision/apply-gate steps of the shadow effect pipeline, or `run_codeguide.sh` integrated mode), you can call scripts under `scripts/` directly.

```bash
cd <skill-dir>
scripts/run_codeguide.sh /path/to/project --mode auto
python3 scripts/shadow_policy_loader.py --project-root /path/to/project --adapter-module scripts/shadow_evidence_probe.py --check-parity
python3 scripts/shadow_evidence_probe.py --project-root /path/to/project --validator-id py.ast.call_match@v1 --source-file src/app.py --callee save
python3 scripts/shadow_review_queue.py --input probe.jsonl --task-id shadow-effect-map-01
python3 scripts/shadow_user_decision_wrapper.py --project-root /path/to/project --output decision.json --decision-id UD-001 --decision-type final_shadow_apply --answer yes --decided-by gm --decided-at 2026-05-03 --expires-at 2026-05-10 --candidate-id LC-... --record record.json --target-shadow-file packages/app/effects.md --rationale "Approve exact record" --source-ref TASK-shadow-effect-map-01
bats tests/
```

`run_external_plan_reviews.sh` (= `scripts/codeguide review`) uses the CLI's default model by default and avoids hardcoded version names unless the user provides an override. Long prompts round-trip as Markdown request/response files under `docs/orchestration/<task-id>/external-cli/<plan-version>/<round>/` instead of being passed as shell arguments. Short bash commands sent to external CLIs must specify an absolute command-output path via stdout redirection, `tee`, or tool-specific options like `--output-last-message`; mentioning a path inside the prompt alone is insufficient. The wrapper redacts raw command output before storing the durable response file and deletes the raw capture. Requests include the `Why/What/How/Where/Verify` axes, valid responses follow parser-friendly bullet fields, and preserved files are redacted of sensitive values before storage. This command creates the review report and then stops; it does not auto-generate the next `PLAN-v1.1`.

These commands are less the essence of using the skill than an auxiliary interface for reproducing or verifying the skill's operating state.

## Project Structure

```text
codeguide/
├── README.md
├── SKILL.md
├── agents/
├── case-studies/
├── references/
├── scripts/
└── tests/
```

- `SKILL.md`: operating contracts and workflow policy
- `agents/`: skill-facing agent configuration
- `case-studies/`: point-in-time reports (Korean HTML) of validation and reliability work; kept apart from the project-level `docs/` root on purpose
- `references/`: governance, architecture, and review standard documents
- `scripts/`: executable automation layer
- `tests/`: shell tool regression tests

## Evolution

- Inspired by other skills technologies
- Manual markdown operation during a bootcamp final project
- Repeated experience with context loss and decision drift
- Consolidated into shell scripts for a repeatable docs lifecycle
- Added multi-agent orchestration rules based on the supervising architect model
- Added consistency, freshness, and secret hygiene validation gates
