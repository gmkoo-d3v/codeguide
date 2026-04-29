# External Plan Review Prompt

Use this template for semi-automated external ping-pong review of `PLAN-*` docs.

Wrapper scripts must write the full request to a redacted Markdown handoff file and capture sanitized stdout in a Markdown response file before parsing it into `docs/report/`.
Wrapper scripts should pass only a short instruction plus the absolute request-file path to external CLIs; the Markdown request file is the handoff contract, not stdin.
When a CLI emits runtime logs on stdout, wrappers should capture the final model message through a dedicated response-file option if the CLI supports one.
Request handoff files should use metadata plus `Why`, `What`, `How`, `Where`, `Verify`, then payload.
Valid response handoff files should use the parser-compatible bullet fields below; malformed sanitized stdout may be preserved for retry diagnostics.

## Review stance
- Default to defect-seeking review rather than approval-seeking review.
- Assume the plan may contain logical gaps, sequencing flaws, weak assumptions, contract mismatches, convention drift, missing verification, and understated risk until checked.
- Keep criticism evidence-based and actionable.

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
- Prefer `revise` or `blocked` unless the plan is clearly ready to execute.
