# External Plan Review Prompt

Use this template for semi-automated external ping-pong review of `PLAN-*` docs.

External reviewer output is advisory only. The supervising lead architect owns risk preflight, approval gates, convergence, and the final decision to proceed.
Wrappers must not invoke external reviewers until the main thread records `risk_preflight_status: approved` with a concrete approval ref and exact approved next step.
Wrapper scripts must write the full request to a redacted Markdown handoff file and capture sanitized command output in a Markdown response file before parsing it into `docs/report/`.
Wrapper scripts should pass only a short instruction plus the absolute request-file path to external CLIs that can reliably read that file in the approved runner context. If a runner's safe non-interactive mode disables file tools or cannot read workspace paths, the wrapper may stream the already-written Markdown request content on stdin while keeping the request file as the durable handoff contract.
The short CLI command must also include an explicit absolute command-output path through shell stdout redirection or an equivalent runner-supported output option; the wrapper may then sanitize that raw capture into the durable response file and delete the raw capture.
The prompt text alone is not a sufficient output-location contract.
External CLI reviews are runner-neutral. Runners, route-qualified model ids, aliases, quota groups, default reviewers, and quota-error patterns come from `config/ai_model_registry.json` or `CODEGUIDE_MODEL_REGISTRY`.
Approved runner environments should treat direct external CLI invocation as the primary path. In Codex app sessions, the fix path is not Terminal UI automation or settings-file mutation: request explicit user approval for the external CLI command, rerun through the user-approved unsandboxed execution path, and preserve the request/response/provenance artifacts under `docs/orchestration/<task-id>/external-cli/<plan-version>/<round>/`.
If the user approved the exact external CLI step but an automatic guardian reviewer still blocks private workspace egress, classify the result as `platform_permission_blocked`, stop retrying, and ask the user to switch the thread/workspace permission mode so escalation prompts go to the user approval path. Do not mark required external review as accepted until a parser-compatible response and provenance are ingested.
If a runner reports authentication failure inside the Codex/app sandbox, including `Not logged in`, `Please run /login`, `Failed to authenticate`, `Invalid authentication credentials`, or `API Error: 401`, treat that first as a sandbox/keychain permission boundary and rerun the same command through the approved unsandboxed path before asking the user to operate a terminal manually or log in.
For Shadow v2 close tracking, record that blocker with the runner route, for example `--blocked-review external_cli:agy=platform_permission_blocked`, so the gate reports the permission-mode remediation instead of a generic blocked route.
Only as a last-resort fallback, after the user explicitly accepts user-operated CLI execution, use `run_external_plan_reviews.sh --manual-handoff-only` to write request files and manual command files. After the user runs those commands in their own terminal, use `run_external_plan_reviews.sh --ingest-manual-responses` with the same review options to normalize raw responses into sanitized reports and provenance.
For implementation-review packets that include diffs or source excerpts, use an inline-only packet unless the external CLI is intentionally allowed to inspect files. If file inspection is allowed, attach the project root with the configured runner workspace mechanism.
**Quota exhaustion**: automatic model fallback is disabled. When a registered route exhausts quota, stop and ask the user to switch the runner's globally selected model, then rerun with a reviewer route that records that selection.
Request handoff files should use metadata plus `Why`, `What`, `How`, `Where`, `Verify`, then payload.
Valid response handoff files should use the parser-compatible bullet fields below; malformed sanitized stdout may be preserved for retry diagnostics.

## Review stance
- Default to defect-seeking review rather than approval-seeking review.
- Assume the plan may contain logical gaps, sequencing flaws, weak assumptions, contract mismatches, convention drift, missing verification, and understated risk until checked.
- Keep criticism evidence-based and actionable.
- Avoid process expansion for its own sake; request more planning or review only when it materially reduces execution risk.

## Standard review
- Judge whether the plan is execution-ready.
- Prioritize architectural risk, missing verification, unclear ownership, incomplete stop conditions, and integration blind spots.
- Return concise single-line values for:
  - `verdict`
  - `summary`
  - `strengths`
  - `risks`
  - `requested_changes`

## Adversarial review
- Start from the assumption that the current plan is wrong or unsafe.
- Push on the most fragile assumptions first.
- Return the standard fields plus:
  - `objection`
  - `counterproposal`
  - `rebuttal`
  - `residual_risk`

## Output discipline
- Return only the requested markdown bullet fields.
- Keep every field value on a single line so wrapper scripts can normalize the response into `docs/report/`.
- Use only the command-level response path and sanitized response file named by the wrapper; do not claim that the review was saved to any other file.
- Prefer `revise` or `blocked` unless the plan is clearly ready to execute.
- Prefer `accept` when remaining issues are minor, already covered by validation, or unlikely to change implementation choices.
