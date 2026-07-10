# Shadow v2 Automation Plan

> Size justification (2026-07-11, P5): this file intentionally exceeds the ~300-line reference budget — it is a single operational playbook whose phases cross-reference each other, and the P5 dedup made it the canonical home for two routed clauses; splitting it is a recorded follow-up candidate, not an oversight.

Use this reference when planning or implementing the next automation layer for the shadow effect-map workflow.

## Status

- plan_id: shadow-v2-automation-01
- status: phase0-4-implemented-and-tested
- selected_by_user: 2026-05-13
- independent_review_gate: default-internal-subagent-artifact-required-external-cli-user-requested-only

## Locked Decisions

- v2 automation scope includes all three automation tracks:
  - user-decision assistant
  - review-packet generator
  - supervised pipeline wrapper
- Implementation order starts with the user-decision assistant; this is priority, not exclusion.
- First parser-backed expansion target: Java family first.
- Hint-layer mode: automatic hint-only lookup is allowed after project scope is verified.
- External Gemini/Claude review is user-requested only by default.
- Normal independent review uses sub-agents with durable Markdown request/response handoff artifacts in project docs.
- Separate-session critique is a future/runtime-dependent option; use it only when the active tool supports a true independent non-sub-agent session.
- A separate non-sub-agent session from a different tool remains an external/user-requested review route, not the internal-runtime default.
- Unknown/stale escalation uses the default operating policy in this plan unless the user later overrides it.

## User Choice Boundary

The v2 automation may standardize workflow defaults, but it must not decide human-only meaning.

Already selected defaults:

- build all three automation tracks instead of choosing only one
- implement the user-decision assistant first, then review packets, pipeline wrapper, and parser-backed expansion
- start parser-backed expansion with Java
- activate automatic hint lookup only after project scope is verified
- use the active runtime's own sub-agent Markdown review as the default independent review route
- use Gemini/Claude external review only when the user explicitly requests it
- keep external review provenance at local request/response/provenance hash consistency; do not require stronger tamper resistance in v2
- keep supervised apply as one record per explicit final-apply decision; do not enable batch apply by default
- use runtime evidence proactively by surfacing and preparing deterministic trace artifacts, while still requiring explicit `runtime_scenario_fit` for confirmed runtime facts
- future Express validator scope is route registration syntax only; do not claim middleware order, app mounting, or runtime reachability
- future React validator scope is `useEffect` and event handler binding syntax only; do not claim render lifecycle timing, effect execution, or product intent
- group bounded user-decision questions when deterministic grouping is possible, without answering them or collapsing distinct record bindings

Deferred user choices during real shadow authoring:

- whether an observed effect is product intent, expected behavior, or a bug
- business risk meaning and risk escalation or de-escalation
- waiver or delayed-approval acceptance
- runtime trace scenario fit
- non-exact deduplication when two facts look similar but are not mechanically identical
- final shadow apply approval
- any batch apply permission if that option is introduced later

Automation requirement:

- ask these as bounded user questions with source refs, anchors, missing evidence, and recommended default status
- never answer them through LLM consensus, mem0, graph/vector hints, source probes, or regex matches
- keep unchosen items as `unknown`, `blocked`, or dry-run plans until the user answers

## Goal

Make shadow effect-map work easier to operate without expanding authority.

v2 automates question planning, hint collection, and evidence-prep routing. It does not turn LLMs, memory, graphs, source probes, or regex matches into confirmed facts.

## Non-Goals

- No automatic final shadow apply.
- No model-consensus-as-evidence.
- No mem0, vectorstore, Neo4j, Serena, or graph-sync authority.
- No source-probe or fallback-regex promotion to `confirmed`.
- No full cross-language extraction in the first v2 scope.
- No unbounded user-question generation.

## v2 Architecture

## Blueprint Consensus

The external blueprint ping-pong loop converged on this sequence:

1. Phase 0: shared schemas, gate constants, and no-write test harness.
2. Phase 1: user-decision assistant.
3. Phase 2: review-packet generator.
4. Phase 3: supervised pipeline wrapper.
5. Phase 4: Java parser-backed adapter expansion.

Phase 0 is not the pipeline wrapper feature. It is a thin safety scaffold so the user-decision assistant can share stable gates, stop reasons, and no-write tests from the beginning.

Required r02 corrections:

- project-scope-verified hint activation must use a deterministic logged trigger
- batch-apply gate must exist as a disabled stub
- sub-agent Markdown review must declare isolation and handoff provenance
- review packets must include timestamp and provenance fields
- negative-evidence default must remain explicit: non-deterministic signals stay discarded, `unknown`, `blocked`, or `candidate_only`

Phase 0 implementation entrypoint:

- `scripts/shadow_v2_gate_skeleton.py`

The Phase 0 skeleton exposes shared constants and no-write checks for project-scope hint activation, review route provenance, disabled batch apply, and confirmable evidence types. It must remain a contract harness until the user-decision assistant begins.

Phase 0 verification:

- the skeleton emits `writes_shadow_docs=false`
- the skeleton emits `auto_promotes_facts=false`
- contract printing does not require a scoped project
- project-scope checking blocks hint activation until `docs/`, `docs/shadow/`, and `docs/policy/` exist
- external Gemini/Claude review is blocked unless explicitly requested
- completed external Gemini/Claude review is blocked unless a durable accepted response artifact under `docs/orchestration/<task-id>/external-cli/<plan-version>/<round>/` is supplied with a matching companion request file, wrapper-generated provenance manifest, evaluator, `verdict: accept`, parser-compatible review fields, command-response path, response path, bytes, and sha256 provenance
- completed internal sub-agent or runtime-independent-session review is blocked unless a durable accepted `.md` Markdown response artifact under `docs/report/` or `docs/orchestration/` is supplied with `verdict: accept`, `priority_findings`, `contract_mismatches`, `missing_evidence`, `residual_risks`, bytes, and sha256 provenance
- batch apply is disabled
- non-confirming evidence types cannot confirm facts
- generic `user_decision` and `final_shadow_apply` cannot confirm facts; user fact evidence must declare an allowed fact-decision type
- independent sub-agent review: close acceptance requires the response itself to be captured as a durable accepted artifact

### Track 1: User-Decision Assistant

Primary first component.

Implementation entrypoint:

- `scripts/shadow_v2_user_decision_assistant.py`

Purpose:

- Convert `unknown`, `blocked`, and missing-human-judgment cases into bounded questions.
- Ask only when the missing part is human judgment.
- Provide a recommended default status, usually `unknown` or `blocked`.
- Explain the effect of each answer before asking.

Inputs:

- shadow effect candidate records
- JSON/JSONL evidence candidate records using the same record shape consumed by `shadow_review_queue.py`, not that script's Markdown output
- `shadow_effect_writer.py` blocked `next_actions`
- source anchors and call-chain candidates
- policy/rule registry metadata
- hint-only context when project scope is verified

Outputs:

- bounded decision question packet
- required evidence or decision type
- recommended default status
- command hint for `shadow_user_decision_wrapper.py` only when enough structured fields exist

Implemented v2 behavior:

- accepts evidence/probe JSON records and writer blocked `next_actions`
- preserves `writes_shadow_docs=false`
- preserves `auto_promotes_facts=false`
- blocks hint activation unless project scope is verified when hint mode is enabled
- turns writer user-decision `next_actions` into command hints but never executes them
- allows command hints only for `shadow_user_decision_wrapper.py` and supported fact-evidence decision types
- renders command text only from validated structured argv, never from writer-supplied `command_text`
- rejects spoofed wrapper paths, Python `-c`, shell-control tokens, forbidden tools, duplicate single-use flags, and unsupported fact-decision types
- refuses packet output under `docs/shadow/`
- independent sub-agent review: accepted in r04 with no remaining P0/P1 blockers

Must not:

- answer for the user
- write shadow docs
- promote facts
- treat final apply approval as fact evidence

### Track 2: Review-Packet Generator

Second automation track.

Implementation entrypoint:

- `scripts/shadow_v2_review_packet_generator.py`

Purpose:

- Generate bounded internal review packets from supplied source refs and candidate/probe/writer/user-decision artifacts.
- Generate external review packets only when the user explicitly requests external Gemini/Claude review.
- Include only the minimum required evidence snippets.
- Preserve privacy boundaries by default.
- Mark unsupported context as `unsupported_by_packet`.

Inputs:

- selected task id
- source refs
- candidate artifact paths
- probe result artifact paths
- writer dry-run artifact paths
- user-decision packet artifact paths

Outputs:

- Markdown or JSON review packet
- review route, usually `internal_subagent_md_handoff`
- privacy boundary
- unsupported-by-packet context marker
- route-specific expected response fields: internal packets use `priority_findings`, `contract_mismatches`, `missing_evidence`, and `residual_risks`; external packets use `summary`, `strengths`, `risks`, and `requested_changes`

Implemented v2 behavior:

- creates packet-only Markdown or JSON handoffs
- summarizes candidate, probe, writer, and user-decision packet artifacts without broad workspace dumps
- bounds supplied artifact inputs to the resolved project root and records raw artifact sha256 and byte size in packet summaries
- preserves `writes_shadow_docs=false`
- preserves `auto_promotes_facts=false`
- blocks `external_antigravity` unless explicit user request, concrete approval ref, approved next step, and main-thread recorder are provided
- treats Codex CLI review artifacts as advisory plan-review outputs only; they do not satisfy the Gemini/Claude close route unless the close gate is explicitly expanded
- treats direct Gemini/Claude CLI invocation through `require_escalated` and user approval as the primary path; if a guardian reviewer blocks after explicit approval, records `platform_permission_blocked` and asks for permission-mode change before considering the last-resort manual handoff route
- marks blocked external packets as `external_review_missing_user_request`, not `external_user_requested`
- marks missing packet context in `unsupported_by_packet`
- refuses packet output under `docs/shadow/`
- independent sub-agent review: accepted in r04 with no remaining P0/P1 blockers

Must not:

- include broad workspace dumps
- claim external review happened before response capture
- turn reviewer agreement into evidence
- write shadow docs

Default review route:

- internal reviewer: the active runtime's own sub-agent with durable Markdown request/response handoff artifacts
- separate session reviewer: only when the active runtime supports a true independent non-sub-agent session
- handoff medium: Markdown request/response files
- purpose: reduce shared-memory coupling and prompt anchoring bias
- external reviewer: Gemini/Claude only on explicit user request
- combined close gate: when sub-agent and external CLI review are both required, every required route must complete with a valid accepted artifact before acceptance
- substitution rule: sub-agent acceptance, local tests, or model consensus must not substitute for a policy-blocked, tool-blocked, auth-blocked, missing, or response-less required external CLI route

### Track 3: Supervised Pipeline Wrapper

Third automation track.

Draft implementation entrypoint:

- `scripts/shadow_v2_pipeline_wrapper.py`

Purpose:

- Plan existing script calls in a dry-run-first sequence without executing them.
- Make the workflow repeatable without weakening gates.
- Stop at user-decision, evidence, privacy, or final-apply boundaries.

Initial sequence:

1. Resolve project scope.
2. Read shadow navigation context.
3. Collect hint-only anchors.
4. Prepare deterministic probe command hints where structured args exist.
5. Surface review queue generation as a planned step.
6. Prepare the user-decision assistant command hint.
7. Prepare internal review packet generation when independent review is useful.
8. Prepare writer dry-run command hint.
9. Stop before write unless explicit final apply provenance exists.

Must not:

- auto-confirm facts
- auto-apply final shadow writes
- bypass `shadow_apply_gate.py`
- continue after a user decision is required

Draft v2 behavior:

- emits `plan_kind=dry_run_plan`
- emits `executes_commands=false`
- emits `final_apply=blocked`
- emits `status=incomplete` when required probe, writer, or final-apply gates are not satisfied
- includes writer command hints only with `--mode dry-run`
- blocks external review routes unless explicit user request, concrete approval ref, approved next step, and main-thread recorder are provided
- blocks combined close when any required review route is blocked or lacks a valid accepted artifact
- blocks combined close when a completed external Gemini/Claude route has no durable accepted response artifact under `docs/orchestration/<task-id>/external-cli/<plan-version>/<round>/` with matching companion request and wrapper-generated provenance manifest
- ignores blocked external routes that are not part of the required close gate
- refuses pipeline output under `docs/shadow/`
- independent sub-agent review: accepted in r04 as a dry-run draft only

### Java Parser-Backed Expansion

Secondary roadmap after the user-decision assistant.

Phase 4 current state:

- `java.ast.call_match@v1` has a narrow parser-backed token adapter implemented in `shadow_evidence_probe.py`.
- The adapter ignores comments and string literals through masked Java-like token scanning.
- The adapter supports exact `callee` matching and optional probe-time `receiver` binding.
- `shadow_effect_writer.py` can rerun the Java parser-backed probe from structured `probe_args`.
- Confirmed `java.ast.call_match@v1` evidence requires `probe_args.receiver`, including non-`repo.write` policy mappings.
- Bare Java probe matching is treated as probe-level discovery only and is filtered against obvious method and constructor declarations.
- The Java parser-backed adapter is declared in `implemented_primary_v1` and `parser_backed_now`.
- Internal sub-agent review accepted Phase 4 in r04 for implementation quality only; close gate remains blocked when required external CLI review has no durable accepted response.
- Gemini/Claude external review was attempted for Phase 4 after user request, but the runtime escalation reviewer blocked sending private workspace review material to external CLI services. No raw external response was produced. Treat external review as policy-blocked unless the runtime policy changes or a safer external-review boundary is approved outside this workflow.

Initial target family:

- Java
- Spring Boot
- JPA

Planned validator direction:

- `java.ast.call_match@v1` implemented as the first narrow parser-backed Java adapter
- `java.annotation.match@v1`
- `spring_boot.request_mapping@v1`
- `spring_boot.cache_evict.annotation@v1`
- `jpa.repository.save@v1` or a new version if semantics change

Promotion rule:

- Existing Java/Spring/JPA source probes remain `candidate_only` until a parser-backed adapter exists, is declared in `parser_backed_now`, and passes writer validation.

### Automatic Hint Layer

Allowed only after project scope is verified.

Required scope check:

- project root is resolved
- docs root is resolved
- project id or equivalent workspace identity is known
- hint source is labeled
- hint output is bounded to paths, symbols, or candidate ids

Hint order:

1. `docs/shadow`
2. `rg`
3. Always-on Serena for shadow symbol, anchor, reference, or call-chain narrowing
4. mem0, vectorstore, or Neo4j only as scoped heavy-context prior hints
5. direct source, test, command, or runtime validation for evidence

Hint output must be labeled `auxiliary_hint` or equivalent and must not enter `confirmed` evidence fields.

## Twenty-Questions Flow

The assistant asks one bounded question at a time when user judgment is required.

Question packet fields:

Common fields:

- id
- source_kind
- source_ref
- decision_type
- priority
- recommended_default_status
- question
- options
- command_ready
- shadow_write_impact

Evidence-candidate fields when present:

- evidence_queue_ref
- evidence_ref
- endpoint or entry_ref
- call_chain_candidate
- anchor_file
- anchor_line
- anchor_symbol
- missing_evidence

Writer-next-action fields when present:

- reason
- command_hint
- blocked_command_hint
- missing
- supported_effect_types

Default stop conditions:

- enough information exists to create a user-decision artifact command hint
- the user selects `unknown` or `blocked`
- the question requires code/runtime evidence instead of human judgment
- the same question repeats without new evidence
- scope expands beyond the active shadow task

## Remaining User Choices

These are not chosen yet and should be asked later only when needed:

- whether supervised apply can batch multiple records after explicit approval

## Default Operating Policy

- High and critical unknowns force a bounded user question when the missing part is human judgment.
- Medium unknowns enter a capped review queue by default.
- Low unknowns remain tracked with TTL and residual-risk reporting.
- External Gemini/Claude review is not mandatory and is used only when the user explicitly requests it.
- If the user makes external CLI review part of the close condition, blocked or missing external review is a hard stop. The workflow must report `blocked` and wait; it must not continue by treating sub-agent review as equivalent.
- External close-review provenance is a local consistency gate, not tamper-proof attestation. Matching response/request/provenance files reduce accidental or label-only acceptance, but a writable workspace can still forge them; true tamper resistance requires a separate signing or audit mechanism and is out of v2 scope.
- Default independent review uses the active runtime's own sub-agents with Markdown request/response handoffs.
- Separate-session review is not assumed available in Codex; keep it as a future/runtime-dependent option.
- Java parser-backed expansion currently starts with the narrow `java.ast.call_match@v1` token matcher only; annotation and JPA repository-save semantics remain source-probe-only until separate parser-backed adapters are implemented.
- Supervised apply starts as one record per explicit final-apply decision; batch apply remains a later option.

### JavaScript And TypeScript Parser-Backed Expansion

Phase 5 current state:

- `js.ast.call_match@v1`, `ts.ast.call_match@v1`, and `ts.ast.call_match@v2` are narrow parser-backed token adapters implemented in `shadow_evidence_probe.py`.
- `js.ast.call_match@v1` accepts `.js`, `.jsx`, `.mjs`, and `.cjs`; it rejects TypeScript extensions.
- `ts.ast.call_match@v1` accepts `.ts`, `.tsx`, `.mts`, and `.cts`; it rejects JavaScript extensions and `.d.ts` declaration files.
- Both adapters use exclude-wins path scope. Dependency, build, coverage, and test directories are excluded at the repository root and when nested under allowed roots such as `src/`.
- The adapters ignore comments, string literals, and regex literals through masked JavaScript-like token scanning.
- The adapters support exact `callee` matching, optional probe-time `receiver` binding, and optional chaining receiver syntax such as `client?.post(...)`.
- TypeScript generic call syntax such as `client.post<string>(...)` remains unsupported in `ts.ast.call_match@v1`.
- `ts.ast.call_match@v2` supports syntactic TypeScript generic call type arguments such as `client.post<Result<User>>(...)`; it does not prove type checking, overload resolution, runtime execution, module resolution, async completion, or framework middleware order.
- The adapters filter obvious function, method, and TypeScript signature declarations, but they do not prove runtime execution, module resolution, async completion, dynamic dispatch targets, or framework middleware order.
- `shadow_effect_writer.py` can rerun JS/TS parser-backed probes from structured `probe_args`.
- `shadow_effect_writer.py` must reject deterministic call evidence when `anchor.symbol` conflicts with the probe rerun `matched_symbol`.
- `external.call` maps Node JavaScript to `js.ast.call_match@v1` and TypeScript to `ts.ast.call_match@v2`; regex fallback remains capped as candidate-only evidence.
- `fastapi.route@v1` is a narrow parser-backed decorator adapter for FastAPI route declarations. It confirms decorator syntax, route method, and optional literal route path only; it does not prove app mounting, dependency success, middleware order, runtime reachability, or OpenAPI exposure.
- `shadow_policy_loader.py` exposes primary adapter path and extension scope metadata through adapter JSON and parity output so downstream review and automation consume the same executable contract.
- Future Express parser-backed work is limited to route registration syntax such as `app.get(...)`, `app.post(...)`, and router variants; it must not claim middleware order, app mounting, or runtime reachability.
- Future React parser-backed work is limited to `useEffect(...)` and event handler binding syntax; it must not claim lifecycle timing, effect completion, render behavior, or product intent.
- Other framework-specific JS/TS validators remain registry contracts until separate parser-backed adapters are implemented.

## Acceptance Criteria

- User-decision assistant never writes shadow docs.
- User-decision assistant never answers human judgment questions itself.
- Generated questions are bounded, anchored, and include default status.
- Generated question groups preserve each question id and source binding; grouping is presentation metadata only.
- Generated command hints use `shadow_user_decision_wrapper.py` only for supported decision types.
- Java parser-backed expansion cannot promote source probes until adapter, policy, and writer checks agree.
- Hint-layer output remains non-authoritative.
- Tests prove no auto-promotion and no auto-apply.

## Verification

For documentation-only changes:

```bash
"<skill-dir>/scripts/check_english_docs.sh"
"<skill-dir>/scripts/validate_docs.sh" "<project-root>" --mode advisory
```

For future implementation:

```bash
bats --filter 'shadow_v2|shadow_user_decision|shadow_review_queue|shadow_effect_writer|shadow_policy_loader' tests/
```
