# Code Guide

Production-oriented Codex skill for architecture governance, code quality, project documentation lifecycle, external review orchestration, and shadow documentation safety.

## Core Scripts

- `scripts/init_docs_scaffold.sh`: creates the project-root `docs/` scaffold and embedded default policy registries.
- `scripts/run_codeguide.sh`: starts or syncs the docs lifecycle and runtime validation flow.
- `scripts/doc_garden.sh`: updates task, decision, orchestration, and shadow routing docs.
- `scripts/validate_docs.sh`: validates docs structure, policy registries, shadow graph freshness, effect-map records, review-queue artifacts, and secret scans.
- `scripts/run_external_plan_reviews.sh`: creates external CLI review handoffs and report docs without mutating the plan.
- `scripts/shadow_policy_loader.py`: reads only fenced `yaml` policy registry blocks as declarations and checks parity against implemented probe adapters.
- `scripts/shadow_evidence_probe.py`: emits deterministic probe artifacts only through the static `AdapterRegistry`; parser-backed Python AST and runtime-trace evidence are implemented, while Java/Spring/JPA entries are source probes until parser-backed validators are implemented.
- `scripts/shadow_review_queue.py`: turns unresolved probe outputs into bounded human review queues with required context and no fact promotion.
- `scripts/shadow_llm_candidate_wrapper.py`: wraps LLM drafts as non-promotable candidate artifacts.
- `scripts/shadow_user_decision_wrapper.py`: creates guarded final-apply and fact-evidence user-decision artifacts.
- `scripts/shadow_apply_gate.py`: checks final apply approval in supervised dry-run mode.
- `scripts/shadow_effect_writer.py`: writes structured shadow effect records only after candidate, decision, policy, probe, hash, anchor, and target gates pass; blocked results include actionable `next_actions` for missing probe or user-decision evidence when possible.

## Shadow v2 Principle

LLM output, multi-model consensus, mem0, vectorstore, Neo4j, and Serena are hints only. Confirmed shadow effects require deterministic code/runtime evidence or explicit user-decision provenance through the writer gate.
