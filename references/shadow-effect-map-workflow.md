# Shadow Effect Map Workflow

Use this reference when creating or updating shadow docs that mention call chains, side effects, evidence, review questions, or user decisions.

## Goal

Keep shadow docs useful for fast context while preventing side-effect claims from being promoted by LLM inference.

The core split is:

- Navigation shadow docs summarize structure for reading.
- Effect maps record claims only with explicit evidence state.
- Review queues turn unresolved effects into bounded user questions.
- User decisions record human judgment with provenance.
- LLM candidates are untrusted drafts until wrapped by a deterministic gate.

YAGNI: do not build automatic shadow apply, broad graph sync, or full cross-language extraction inside this workflow.

## Document Roles

| Role | Purpose | Allowed content | Forbidden content |
| --- | --- | --- | --- |
| `navigation_summary` | Fast project, API, service, and module routing | Stable structure, links, source paths, concise facts | Silent side-effect promotion |
| `effect_map` | Side-effect ledger | `confirmed`, `unknown`, `blocked`, `stale` effect records | Free-text "likely" claims as facts |
| `review_queue` | Bounded human questions | Candidate records, missing evidence, user questions | Shadow writes or auto-promotion |
| `user_decision` | Human judgment record | Owner, timestamp, scope, expiry, answer, rationale | LLM-authored answers without approval |
| `llm_candidate` | Durable LLM draft wrapper | Source refs, raw hash, model/tool id, timestamp, non-promotion status | Evidence, validation, waiver, or apply authority |

## Classification Matrix

Classify each item before writing:

| Class | Meaning | Destination | Gate |
| --- | --- | --- | --- |
| `summary_fact` | Structural/API/service fact | `navigation_summary` | Current source or existing docs |
| `call_chain_candidate` | Observed or tool-derived path | `effect_map` as candidate or review queue | Anchor required |
| `effect_claim` | Side-effect assertion | `effect_map` | Evidence required |
| `evidence_record` | Support for an effect | `effect_map` | Deterministic result or user decision |
| `unknown_effect` | Missing, weak, stale, conflicting, or intent-dependent claim | `effect_map` or `review_queue` | No promotion |
| `review_question` | Question for user judgment | `review_queue` | Bounded and anchored |
| `blocked_decision` | Cannot continue safely | Task/report plus review queue | User decision required |

Do not use `possible`, `suspected_type`, or `likely effect` in durable effect records. Use `unknown` with a reason and missing evidence instead.

## Evidence Authority

| Evidence class | Can validate? | Notes |
| --- | --- | --- |
| `deterministic_code` | Yes, within validator scope | Parser-backed validator result with rule id and anchor |
| `deterministic_runtime` | Yes, within scenario scope | Exact trace artifact match with hash/reference |
| `user_decision` | Yes, for human-only meaning | Requires owner, timestamp, scope, expiry |
| `source_probe` | No by itself | Syntactic source clue; cap at medium and keep limitations visible |
| `fallback_regex` | No by itself | Fallback match only; never label as parser-backed |
| `llm_hint` | No | Scratch or wrapped candidate only |
| `auxiliary_hint` | No | mem0, vectorstore, Neo4j, Serena, or graph hints |

`evidence.detail` is explanatory only. It must not drive validation without a structured rule id, validator type, parser-backed status, result, and source anchor.

Probe output `status` reports probe execution result only. Durable fact state is expressed by `fact_status` and can be promoted only by writer gates; `source_probe` and `fallback_regex` pass results remain `candidate_only`.

## Promotion Gate

An effect may become `confirmed` only when all applicable checks pass:

- Anchor exists with file and symbol; line is included when stable enough.
- Evidence type is allowed for the target risk level.
- Registered `rule_id` or separate fact-evidence `user_decision` reference exists; final apply decisions authorize writes only and include rationale and source refs.
- Validator output is implemented and parser-backed when claimed as code validation.
- v2 parser-backed code confirmation is implemented for Python AST validators; Java, Spring, JPA, JavaScript, TypeScript, and FastAPI entries remain cataloged as source-probe or planned parser-backed coverage unless the validator catalog marks them implemented and parser-backed.
- Runtime trace has exact artifact reference and scenario confirmation when needed.
- Stale and conflict checks pass.
- No `unsupported`, `error`, `fail`, `source_probe`, or `fallback_regex` result is being hidden.

Risk is not LLM confidence. Use deterministic or user-approved criteria from the rule registry and user decision policy.

## Stop And Ask

Ask the user only when the missing part is human judgment:

- product or domain intent
- business side-effect meaning
- bug versus intended design
- waiver approval
- high or critical promotion/de-escalation
- runtime trace scenario fit
- non-exact deduplication
- final shadow apply approval

Before asking, include:

- endpoint or entry
- call-chain candidate
- file/symbol anchor
- missing evidence
- current default status, usually `unknown` or `blocked`
- effect of each answer where practical

If any required context is missing, mark the item as `deferred_missing_context` instead of asking the user. Question caps must not hide high or critical unresolved items only when the risk source is trusted policy, rule-registry, or user-decision provenance. Backlog means "tracked with TTL", not ignored.

## Write Rules

- If the task only updates structure or routing, write `navigation_summary`.
- If the task records effects, use `effect_map`.
- If evidence is missing, write `unknown` or `review_question`, not `confirmed`.
- If output comes from an LLM, write at most `llm_candidate` through `scripts/shadow_llm_candidate_wrapper.py`.
- If the wrapper is unavailable or rejects the draft, keep LLM output non-durable scratch.
- Never auto-apply review queue output into shadow docs.
- Preserve `writes_shadow_docs=false` and `auto_promotes_facts=false` semantics for queue artifacts.
- Keep residual risks visible when a user decision narrows but does not eliminate uncertainty.

## Tool Gates

Use the script gates as narrow enforcement helpers:

| Script | Role | Writes shadow docs? | Promotes facts? |
| --- | --- | --- | --- |
| `scripts/shadow_policy_loader.py` | Read policy Markdown as declarations and check probe adapter parity | No | No |
| `scripts/shadow_evidence_probe.py` | Validate narrow code/runtime evidence | No | No |
| `scripts/shadow_review_queue.py` | Render bounded user questions | No | No |
| `scripts/shadow_llm_candidate_wrapper.py` | Wrap LLM drafts as non-promotable candidates | No | No |
| `scripts/shadow_user_decision_wrapper.py` | Create guarded user-decision artifacts | No | No |
| `scripts/shadow_apply_gate.py` | Check final-apply preconditions as dry run | No | No |
| `scripts/shadow_effect_writer.py` | Apply structured records after re-checking gates | Yes, only in explicit write mode | No |

`shadow_policy_loader.py` treats Markdown policy files as declarations only; only fenced `yaml` registry blocks are canonical, and `parser_backed_now` is not authoritative without matching probe adapter implementation. `shadow_evidence_probe.py` owns the static `AdapterRegistry`, accepts structured probe arguments, and preserves exclude-wins path scope for both primary validators and fallback patterns. `shadow_llm_candidate_wrapper.py` must reject missing source refs and forbidden production-action markers. `shadow_user_decision_wrapper.py` must create non-promoting user-decision artifacts, reject shadow output paths, enforce final-apply candidate binding, and enforce human-only fact-evidence compatibility before the writer consumes those artifacts. `shadow_apply_gate.py` must require a final user decision, matching candidate id, non-expired provenance, and a target under `docs/shadow`, then return an allowed/blocked dry-run result.
`shadow_effect_writer.py` must re-check candidate and user-decision provenance, require a target hash in write mode, reject raw LLM fields and `llm_hint` evidence, require file and symbol anchors for confirmed records, block duplicate, interleaved, or malformed existing record markers, re-check the target hash immediately before atomic write, re-check deterministic source or trace evidence immediately before write, and update records only by exact `record_id` markers. Write-mode `final_shadow_apply` decisions must bind the exact record content: record id, lifecycle, effect type, statement hash, target shadow file, anchor, and evidence ref/hash when evidence exists. For confirmed records, `deterministic_code` must include `rule_id`, a registry-compatible implemented parser-backed primary validator `ref`, policy-declared rule-to-effect compatibility via `allowed_effect_types`, `validator_kind`, `parser_backed=true`, `validator_result=matched`, line-exact `source_ref` when a line is present, matching `source_hash`, `probe_result_ref`, `probe_result_hash`, a matching read-only probe-result artifact, and structured `probe_args` that the writer uses to rerun the probe; code anchors must bind to the evidence file and probe argument symbol, including qualified receiver where the rule requires one. `deterministic_runtime` must include an implemented runtime-trace validator `ref`, line-exact `trace_ref`, matching `sha256` artifact hash, `probe_result_ref`, `probe_result_hash`, matching probe-result artifact, writer-side probe rerun, and a separate affirmative `runtime_scenario_fit` `user_decision_ref` for scenario fit; that decision must bind the record id, effect type, statement hash, anchor, exact trace ref, and exact scenario ref. Human `user_decision` evidence is limited to human-only effect types, requires an affirmative separate fact-evidence decision, and must bind record id, effect type, statement hash, and anchor. Source-probe-only validators, documented-only validators, and regex fallback ids remain non-confirming even when other fields are present. `final_shadow_apply` is write authorization only and must not be reused as `user_decision` fact evidence.
When blocked on missing probe artifacts or fact-evidence decisions, `shadow_effect_writer.py` may emit `next_actions` with command arrays and command text. These suggestions reduce operator friction only; they are not evidence, do not write shadow docs, and do not bypass writer gates.

Residual risk remains explicit rather than hidden: local JSON candidate and decision artifacts are process-trusted, not cryptographically signed; parser-backed validators prove narrow syntax, not product semantics; Markdown policy registries are formatting-sensitive; and concurrent writers rely on final hash checks plus atomic replace rather than a cross-process lock.

`--today` exists for deterministic tests and replay diagnostics only. When it is set earlier than the current UTC date, apply and writer gates must surface a `today_override_warning` field in JSON output so expiry bypasses are visible.

## Invalid Patterns

- Multi-model agreement recorded as evidence.
- `direct code evidence` without rule id, validator type, parser-backed status, and anchor.
- `source_probe` displayed like `validator_result`.
- `fallback_regex` promoted to high or critical validation.
- Question cap suppressing a high-risk unknown.
- Review queue acceptance treated as final shadow apply.
- LLM-authored risk classification treated as durable policy.
- Non-exact duplicate merged without user decision.

## Standard Workflow

1. Read existing shadow docs for navigation context.
2. Use `rg` and, when triggered, Serena for current-code anchors and call-chain narrowing.
3. Treat mem0, vectorstore, Neo4j, and graph sync as bounded hints only.
4. Run deterministic probes where a registered validator or fallback exists.
5. Classify each item using the matrix above.
6. Write navigation summaries separately from effect maps.
7. Convert unresolved human-judgment items into bounded review questions.
8. Wrap any durable LLM draft with `shadow_llm_candidate_wrapper.py`.
9. Create final-apply or fact-evidence decisions with `shadow_user_decision_wrapper.py` when the user has supplied the decision.
10. Run `shadow_apply_gate.py` before any future supervised writer applies a shadow change.
11. Use `shadow_effect_writer.py --mode dry-run` for previews and `--mode write` only with an expected target hash.
12. Stop before final apply unless explicit user approval and provenance are present.

## Verification

For workflow changes, verify the smallest relevant set:

```bash
"$CODEGUIDE_ROOT/scripts/check_english_docs.sh" "$CODEGUIDE_ROOT"
"$CODEGUIDE_ROOT/scripts/validate_docs.sh" "$CODEGUIDE_ROOT" --mode advisory
```

For script behavior changes, also run focused Bats tests for the touched script.
