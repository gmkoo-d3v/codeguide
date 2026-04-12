# External Plan Review Prompt

Use this template for semi-automated external ping-pong review of `PLAN-*` docs.

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
