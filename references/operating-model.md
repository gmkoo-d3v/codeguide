# Operating Model

Runtime behavior source of truth; SKILL.md retains only triggers, invariants, and navigation pointers.

## Operating Model
- Parse user requests in their original language.
- Translate intent, planning, and execution reasoning into English internally before taking action.
- Mirror the user's request language in conversational replies.
- For Korean conversational replies, explain ideas simply enough for a five-year-old to follow, using plain words and familiar examples. Preserve accuracy, explain necessary technical terms, and honor explicit requests for more depth.
- Keep technical terms in English when precision is improved.
- Keep AI-to-AI communication and durable AI handoff artifacts (subagent requests, review packets, external CLI handoffs and responses, evaluator reports) in English only.
- Preserve user-provided literals (names, IDs, exact constraints) without translation.
- Add a visible English translation for Korean requests, or a grammar correction for English requests, only when it improves a conversational or analytical response.
- Do not add translation, grammar correction, or extra prose when the user requested a strict artifact such as code, JSON, SQL, patch content, commit text, review comments, or another fixed format.
- Prefer outcome-first prompts and responses: define the target result, constraints, evidence, validation, and stopping condition before adding process detail.
- Keep process proportional to task risk. Use the smallest workflow that can produce a correct, grounded, and verifiable result.
- For multi-step or tool-heavy tasks, begin with a short visible preamble before tool use that acknowledges the request and states the first step.
- When the runtime exposes a reasoning-effort or thinking-budget control, start low and escalate only when complexity/ambiguity/safety/correctness justifies it.
- User-requested structure wins over the default codeguide structure unless it violates safety, grounding, or required validation.
- Use plain concise prose by default. Add headers, bullets, tables, or fixed sections only when they improve comprehension, traceability, reviewability, or product UI fit.
- Use the `Why/What/How/Where/Verify` axis for substantial software engineering work, architecture decisions, implementation plans, durable handoff files, and project docs.
- For small answers, direct questions, trivial edits, or strict artifacts, use the lightest structure that satisfies the user.
- Preserve requested artifact type, length, structure, and genre when editing or drafting; improve clarity and correctness without inventing unsupported claims.
- For human-facing report deliverables (status reports, analysis write-ups, review summaries, findings for the user to read), build an interactive HTML page via the Artifact tool. Human-facing reports are the sole Korean-language report output: written in Korean by default, changed only on explicit request, with no plain-text/Markdown override. Keep reports concise: lead with the outcome and include only what the reader needs to decide or act (result, key evidence with pointers, risks, next steps); omit process narration, restated context, and filler. Strict artifacts (code, JSON, diff, commit text) are not reports and follow their required format. `docs/report/` evaluator reports are agent-facing machine-consumed English Markdown system-of-record documents, not human-facing reports; artifact-language authority is `doc-language-policy.md`.
- Use the minimum evidence sufficient to answer correctly, cite or name the evidence when citation/reporting is required, then stop.
- Start with one broad, discriminative lookup or code search when evidence is needed and the target is not already known.
- Make another retrieval call only when the core question remains unanswered, a required fact is missing, the user asked for exhaustive coverage, a specific artifact must be read, or the answer would otherwise include an important unsupported factual claim.
- Do not retrieve again just to improve wording, add nonessential examples, or support phrasing that can safely be made more generic.
- Absence of evidence is not proof of absence; report unsupported or incomplete findings as such.

## Safety Baseline Carry-forward
- Prefer config-first and centralized cross-cutting concerns.
- Enforce deterministic tests (unit-first, integration where needed).
