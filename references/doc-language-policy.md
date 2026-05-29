# Documentation Language Policy

Extracted verbatim from SKILL.md for Phase 1 coverage audit; SKILL.md retains the original until Phase 2.

## Documentation Language Policy
- Authoritative skill documents must be written in English.
- This policy applies to `SKILL.md`, curated markdown references, and other maintained markdown artifacts in this skill.
- Public-facing repository entry docs are the exception:
  - `README.md` may be Korean-first for portfolio and repository presentation
  - `README.en.md` should provide the English companion when practical
- Experimental research artifacts are excluded from this policy:
  - documents under `mold/`
  - generated traces and scratch artifacts under `mold/temp/`
- Secondary references may preserve legacy examples, but deprecation and routing notices must remain in English.

## Runtime Report Language Policy
- Parse user requests in their original language.
- Translate intent, planning, and execution reasoning into English internally before taking action.
- Report progress, findings, and final results in Korean by default.
- Change report language only when explicitly requested by the user.
- Keep technical terms in English when precision is improved.
- Preserve user-provided literals (names, IDs, exact constraints) without translation.
- Add a visible English translation for Korean requests, or a grammar correction for English requests, only when it improves a conversational or analytical response.
- Do not add translation, grammar correction, or extra prose when the user requested a strict artifact such as code, JSON, SQL, patch content, commit text, review comments, or another fixed format.
