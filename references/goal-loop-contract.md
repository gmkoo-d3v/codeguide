# Goal Loop Contract

Use this reference for goal-oriented document, planning, review, and code-writing loops.

## Core Rule

Do not use a fixed iteration count, token budget, or cost cap as the primary stop condition.

Continue while each iteration materially improves correctness, reduces risk, fixes a verified failure, adds new evidence, or moves the task closer to explicit acceptance criteria.

Stop when a hard gate is reached.

YAGNI: do not build an autonomous infinite runner, scheduler, or background daemon inside this contract.

## Preconditions

Before starting a goal loop, define:

- explicit acceptance criteria
- non-goals or scope boundary
- required verification command, review standard, or evidence source
- current owner of convergence decisions, usually the supervising lead architect

If acceptance criteria or scope boundary are missing, stop and request clarification instead of starting an open loop.

## Applies To

- Plan review ping-pong loops.
- Ralph Wiggum style critique loops.
- Sub-agent review and implementation loops.
- External evaluator review loops.
- Shadow effect-map question and decision loops.
- Code implementation, test-fix, refactor, and validation loops.

## Continue Conditions

Continue when at least one condition is true:

- New material evidence was found.
- A verified failure was reduced or fixed.
- Tests, lint, type checks, docs validation, or runtime validation are improving.
- Review findings remain concrete, actionable, and in scope.
- The next change moves the work toward explicit acceptance criteria.
- A previous answer exposed a new local inconsistency that can be checked without expanding scope.

## Material Evidence

Treat evidence as material only when it can change correctness, risk, acceptance status, or the next implementation step.

Examples by workflow:

- Code loop: a new failing or passing test signal, compiler/type/lint output, runtime trace, reproducible bug observation, or source-level invariant violation.
- Review loop: a new defect category, missed requirement, violated contract, underestimated risk, or missing verification that was not already captured.
- Documentation loop: a contract mismatch, stale source reference, missing decision provenance, broken link, or validation finding.
- Shadow loop: deterministic evidence, missing evidence, source anchor conflict, stale/unknown/blocked status change, or user-decision requirement.

Non-material changes include wording polish, repeated objections with no new rationale, stylistic preferences outside the goal, and evidence already recorded with no changed implication.

## Hard Stop Conditions

Stop immediately when any condition is true:

- Acceptance criteria are met and required verification passed.
- No new material findings appear after review.
- The same failure repeats without new evidence or a new hypothesis.
- An off-goal loop is detected.
- The next step requires a user decision, such as product intent, business risk override, waiver, defer, or final apply.
- The next step expands scope beyond the approved goal.
- The next step requires destructive action, external side effects, sensitive data, or elevated permission not already approved.
- Security, privacy, policy, or provenance gates block progress.
- Required source, tool, dependency, or runtime access is unavailable and no safe fallback remains.

The supervising lead architect decides whether a review or implementation loop has converged, using the evidence above and the explicit acceptance criteria.

## Off-Goal Loop Detection

Stop when the loop is repeating actions, reviews, rewrites, or fixes that no longer move toward the user's stated goal or acceptance criteria.

Examples:

- The same critique repeats without new material evidence.
- Code changes keep touching unrelated files.
- Reviewers request process expansion instead of solving the goal.
- Implementation optimizes style while the core verification still fails.
- A shadow workflow keeps asking policy questions when the user needs an actual record or bounded user-decision packet.
- The loop keeps generating artifacts that are not part of the accepted deliverable.

When this happens:

- stop the loop
- report the goal mismatch
- show the last useful evidence
- propose the next safe action
- ask whether to continue, narrow scope, or change the goal

## Non-Stop Conditions

These are not sufficient stop reasons by themselves:

- A fixed number of iterations has completed.
- A large number of tokens was used.
- Cost is increasing.
- The loop has already run longer than usual.

The operator may still stop manually at any time.

Cost or token checkpoints are optional telemetry only when the operator explicitly requests them. They must not pause, stop, or require confirmation by default.

## Scope Expansion

Treat the next step as scope expansion when it requires:

- a new deliverable not named in the acceptance criteria
- edits outside the approved owned scope
- new runtime services, credentials, infrastructure, or external accounts
- changing public API, data migration, security posture, or deployment behavior not already approved
- resolving a different bug or feature discovered during the loop

Normal decomposition inside the approved goal is not scope expansion when it only breaks the accepted work into smaller verified steps.

## Code-Writing Loop

For code work:

1. Implement the smallest in-scope patch that addresses the current verified finding.
2. Run the narrowest relevant verification.
3. If verification fails, inspect the failure and form a new hypothesis.
4. Continue only while the hypothesis is new, in scope, and testable.
5. Stop when verification passes or a hard stop condition applies.

Do not keep changing code after passing verification unless there is a remaining in-scope finding or an explicit acceptance criterion is still unmet.

## Documentation And Review Loop

For document, plan, or review work:

1. Compare the current artifact to the explicit contract and acceptance criteria.
2. Ask reviewers or sub-agents for defect-seeking feedback when review is justified.
3. Create the next revision only when feedback changes risk, correctness, or execution readiness.
4. Stop when additional review is unlikely to change the decision materially.
5. Keep all remaining uncertainty visible as residual risk, unknown, blocked, or user-decision-required.

External semi-automated review loops must still stop after collecting evaluator reports and showing results to the user unless the user explicitly asks to continue.

For ping-pong or Ralph Wiggum critique loops, repeated feedback must introduce a new material defect category, new evidence, or a changed risk assessment. Otherwise classify the loop as converged and stop.

## Shadow-Specific Gate

For shadow effect-map work, the loop must stop before promotion or write when user judgment is required.

Skills may generate:

- bounded question packets
- `user_decision` schema skeletons
- missing-evidence summaries
- default `unknown` or `blocked` statuses

Skills must not decide:

- product intent
- bug versus intended behavior
- business risk override
- waiver or defer approval
- final shadow apply

## Required Reporting

When a loop stops before completion, report:

- current status
- last verified evidence
- blocker or hard stop condition
- next safe action
- whether user decision is required
