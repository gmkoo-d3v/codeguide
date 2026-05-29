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
- v2 parser-backed code confirmation is implemented for Python AST validators, the narrow Java call matcher `java.ast.call_match@v1`, JS/TS call matchers, and narrow FastAPI route decorators; confirmed Java call evidence requires `probe_args.receiver`; FastAPI `@app.api_route(...)` remains unsupported until `methods=[...]` parsing is implemented; Spring, JPA, Express, and React entries remain cataloged as source-probe or planned parser-backed coverage unless the validator catalog marks them implemented and parser-backed.
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
<skill-dir>/scripts/check_english_docs.sh <skill-dir>
<skill-dir>/scripts/validate_docs.sh <project-root> --mode advisory
```

For script behavior changes, also run focused Bats tests for the touched script.

## Core Policy (extracted from SKILL.md — Phase 1, pending Phase 2/4 consolidation)

Extracted verbatim from SKILL.md for Phase 1 coverage audit; SKILL.md retains the original until Phase 2.

## Shadow System Contract
- Treat `docs/shadow/` as a Markdown-only compressed context layer for agents.
- Use topology-first typed buckets:
  - `apps`
  - `services`
  - `packages`
  - `infra`
  - `data`
- Shadow document roles are fixed:
  - `docs/shadow/project-shadow.md`: top router only
  - `docs/shadow/_global.md`: optional side path for cross-unit invariants only
  - `docs/shadow/<bucket>/_index.md`: unit membership only
  - `docs/shadow/<bucket>/<unit>/overview.md`: landing doc plus concern router
  - concern leaf docs: concrete facts only
- Default read path:
  - `project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf`
- Keep shadow docs in English and Markdown only; do not add JSON sidecars or empty concern placeholder files.
- Use unit `overview.md` as the day-one landing doc when a unit is detected.
- Same-session changes should refresh affected shadow docs during final sync; external git-driven changes should refresh shadow only on explicit user request.
- Preserve legacy compatibility with thin redirect shims at old paths and archive replaced bodies under `_deprecated` or `_obsolete`.
- Target roughly 200 lines per shadow doc; use 300 lines as a soft cap and split by concern when a doc stops routing well.

## Shadow Effect Map Workflow Contract
- Apply this contract whenever a shadow update records side effects, call chains, review questions, or user decisions; use `references/shadow-effect-map-workflow.md` for the detailed workflow.
- Separate document roles before writing: `navigation_summary`, `effect_map`, `review_queue`, `user_decision`, and `llm_candidate`.
- Treat call chains as observable candidates and effects as claims; do not promote an effect from call-chain presence alone.
- Evidence authority is limited to deterministic code/runtime results and explicit user decision provenance; LLM output, multi-model consensus, mem0, vectorstore, Neo4j, and Serena are hints only.
- `confirmed` effects require an allowed evidence type, a source anchor when available, a registered rule or user-decision reference, and non-stale/non-conflicting provenance.
- Keep `source_probe`, `fallback_regex`, `unsupported`, `error`, `fail`, conflict, and unresolved intent as `unknown`, `candidate_only`, or `blocked`; never hide them behind a successful status.
- In probe output, `status=pass` is only probe execution status; durable fact meaning must come from `fact_status`, evidence type, validator contract, and writer gates.
- User-only decisions include product/domain intent, business side-effect meaning, bug-versus-intended-design, waiver approval, high/critical promotion or de-escalation, runtime trace scenario fit, non-exact deduplication, and final shadow apply.
- LLM-derived durable output is blocked until a deterministic `llm_candidate` wrapper records source refs, raw draft hash, model/tool identity, timestamp, and non-promotion status.
- Use `scripts/shadow_policy_loader.py` for fenced-`yaml` policy-registry parsing and adapter parity checks, `scripts/shadow_llm_candidate_wrapper.py` for LLM candidate wrapping, `scripts/shadow_user_decision_wrapper.py` for guarded user-decision artifacts, `scripts/shadow_apply_gate.py` for supervised dry-run apply checks, and `scripts/shadow_effect_writer.py` only for structured record writes after gate re-checks.
- Shadow writes require explicit write mode, user-decision provenance with rationale/source refs, candidate id and exact record-content binding, target hash check, exact single record id update, confirmed file/symbol anchor, and rejection of raw LLM fields or `llm_hint` evidence.
- Confirmed `deterministic_code` evidence requires `rule_id`, policy-declared rule-to-effect compatibility through `allowed_effect_types`, a registered compatible implemented parser-backed primary validator, `validator_kind`, `parser_backed=true`, `validator_result=matched`, line-exact `source_ref` when line-qualified, matching `source_hash`, `probe_result_ref`, `probe_result_hash`, a matching read-only probe-result artifact, and writer-side probe rerun from structured `probe_args`; confirmed `java.ast.call_match@v1` evidence additionally requires `probe_args.receiver`; deterministic call/decorator evidence must bind `anchor.symbol` to the probe rerun `matched_symbol` when present; policy Markdown is declaration-only, only fenced `yaml` registry blocks are canonical, and declarations must be checked against the static probe `AdapterRegistry`, with exclude-wins path scope for allowed/excluded paths including nested dependency, build, coverage, and test directories under allowed roots; v2 parser-backed code confirmation is currently implemented for Python AST validators, narrow Java, JavaScript, TypeScript call matchers, and narrow FastAPI route decorators; JavaScript call matching is scoped to `.js`, `.jsx`, `.mjs`, and `.cjs`; TypeScript call matching is scoped to `.ts`, `.tsx`, `.mts`, and `.cts` while excluding `.d.ts`; JS/TS call matching masks comments, string literals, and regex literals, supports optional chaining receiver syntax, keeps TypeScript generic call syntax unsupported in `ts.ast.call_match@v1`, and supports syntactic generic call type arguments in `ts.ast.call_match@v2` without proving type checking or overload resolution; FastAPI route matching confirms only method-specific decorator syntax, HTTP method name, and optional literal route path, not `@app.api_route(...)`, app mounting, dependency success, middleware order, or runtime reachability; future Express parser-backed matching is limited to route registration syntax, and future React parser-backed matching is limited to `useEffect` and event handler binding syntax; Spring/JPA/Express/React catalog entries remain source-probe or registry contracts until parser-backed probes are implemented; confirmed `deterministic_runtime` evidence requires an implemented runtime-trace validator, line-exact `trace_ref`, matching `sha256` artifact hash, `probe_result_ref`, `probe_result_hash`, matching probe-result artifact, writer-side probe rerun, and a separate affirmative `runtime_scenario_fit` user-decision ref bound to exact trace and scenario fit.
- When `shadow_effect_writer.py` blocks on missing deterministic probe artifacts or fact-evidence decisions, it should return machine-readable `next_actions` with command arrays and plain command text where enough structured inputs exist; these suggestions are usability hints only and do not bypass evidence gates.
- Human `user_decision` evidence is limited to human-only effect types and must use a separate affirmative fact-evidence decision bound to record id, effect type, statement hash, and anchor; residual risks such as unsigned local decision artifacts, narrow syntactic validator meaning, policy-registry formatting drift, and concurrent writer contention must remain visible.
- Treat `final_shadow_apply` as write authorization only; it must not be reused as `user_decision` fact evidence.
- Review queues are bounded question artifacts only; `writes_shadow_docs=false` and `auto_promotes_facts=false` semantics must be preserved.
- Review queues may uncap high/critical questions only from trusted `review_risk_source` values such as `policy`, `rule_registry`, or `user_decision`; arbitrary `risk` or `priority` fields are hints only.
- User-decision assistants may group bounded questions by deterministic metadata, but grouping must not answer questions, merge record bindings, or remove per-question source refs.
- Review packet generation must use project-root-bounded artifact inputs and include raw artifact hash and byte-size provenance; packets remain bounded context and must not dump arbitrary workspace files.
- Ask the user only after providing endpoint or entry, call-chain candidate, file/symbol anchor, missing evidence, and a recommended default status, usually `unknown` or `blocked`.
