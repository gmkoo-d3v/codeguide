# Documentation Language Policy

Single source of truth for artifact language across this skill and the project docs it governs. Runtime interaction and report-delivery behavior is governed by `references/operating-model.md`.

## Artifact Language Rules

- All Markdown authored or maintained under this governance is English only. This covers `SKILL.md`, curated references, `codeguide/README.md`, and project documents created or rewritten under this governance.
- AI-to-AI communication and durable AI handoff artifacts are English only: subagent requests, review packets, external CLI handoffs and responses, and evaluator reports.
- New project plans under `docs/plan/` are English only.
- Existing project docs are historical and grandfathered; do not rewrite them into English as part of this policy. Apply English-only to newly authored documents and to passages rewritten for other reasons.
- Exact user-trigger aliases and path literals (for example `서브에이전트`, `독스모드`) stay verbatim as literals; they are triggers, not prose, and never justify adding Korean prose.

## Human-Facing Reports

- Human-facing reports (status reports, analysis write-ups, review summaries produced for the user to read) are the sole Korean-language report output: written in Korean by default and changed only on explicit request.
- Human-facing reports must be built as interactive HTML pages via the Artifact tool, never static Markdown or plain text. There is no plain-text/Markdown override for human-facing reports.
- Strict artifacts (code, JSON, diff, commit text) are not reports; they follow their required format and language.
- `docs/report/` evaluator reports are agent-facing, machine-consumed English Markdown system-of-record documents parsed by validators. They are not human-facing reports and never take the Korean/HTML report form.

## Repository Entry Document

- `codeguide/README.md` is English prose under the same English-only documentation policy; the former Korean-first exception is removed. Preserve exact user-trigger aliases and path literals where they appear, but add no Korean prose.

## Boundary

Runtime report language (which language addresses the user during interaction) is operating/interaction behavior, not an artifact-language rule; its single source of truth is `references/operating-model.md` (Operating Model). This file governs documentation-artifact language only.
