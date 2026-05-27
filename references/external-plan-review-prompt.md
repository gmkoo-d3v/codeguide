# External Plan Review Prompt

Use this template for semi-automated external ping-pong review of `PLAN-*` docs.

External reviewer output is advisory only. The supervising lead architect owns risk preflight, approval gates, convergence, and the final decision to proceed.
Wrappers must not invoke external reviewers until the main thread records `risk_preflight_status: approved` with a concrete approval ref and exact approved next step.
Wrapper scripts must write the full request to a redacted Markdown handoff file and capture sanitized stdout in a Markdown response file before parsing it into `docs/report/`.
Wrapper scripts should pass only a short instruction plus the absolute request-file path to external CLIs; the Markdown request file is the handoff contract, not stdin.
The short CLI command must also include an explicit absolute command-output path through shell stdout redirection or `--output-format text`; the wrapper may then sanitize that raw capture into the durable response file and delete the raw capture.
The prompt text alone is not a sufficient output-location contract.
External CLI reviews are runner-neutral. Runners, route-qualified model ids, aliases, quota groups, default reviewers, quota-error patterns, and fallback rules come from `config/ai_model_registry.json` or `CODEGUIDE_MODEL_REGISTRY`.
Approved runner environments should treat direct external CLI invocation as the primary path. Codex app sessions may need to enqueue `docs/orchestration/<task-id>/current-task/` packets and let an approved external-review runner execute them.
If the user approved the exact external CLI step but an automatic guardian reviewer still blocks private workspace egress, classify the result as `platform_permission_blocked`, stop retrying, and ask the user to switch the thread/workspace permission mode so escalation prompts go to the user approval path.
For Shadow v2 close tracking, record that blocker with the runner route, for example `--blocked-review external_cli:agy=platform_permission_blocked`, so the gate reports the permission-mode remediation instead of a generic blocked route.
Only as a last-resort fallback, after the user explicitly accepts user-operated CLI execution, use `run_external_plan_reviews.sh --manual-handoff-only` to write request files and manual command files. After the user runs those commands in their own terminal, use `run_external_plan_reviews.sh --ingest-manual-responses` with the same review options to normalize raw responses into sanitized reports and provenance.
For implementation-review packets that include diffs or source excerpts, use an inline-only packet unless the external CLI is intentionally allowed to inspect files. If file inspection is allowed, include the project root via `--include-directories`.
**Quota fallback**: automatic fallback is allowed only when a registered exhausted route has an explicit `fallback_policy` match for the current task phase. Unregistered routes and registered routes without a matching fallback fail closed. `quota_fallback_triggered: true` is recorded in the provenance and report when a fallback occurred.
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
