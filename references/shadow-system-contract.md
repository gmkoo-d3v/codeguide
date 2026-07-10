# Shadow System Contract

Use this reference for the shadow graph itself: topology-first buckets, the fixed document roles, every shadow template (router/global/bucket/unit/leaf/effect/redirect), and the anti-dump line caps. See `references/shadow-effect-map-workflow.md` for the side-effect ledger workflow that sits on top of the `effect_map` role.

## Anti-dump policy (default recommended, strict in CI)
- Keep shadow docs close to 200 lines and preferably at or below 300 lines.
- If a shadow doc exceeds 300 lines or stops narrowing the read path quickly, split it by concern instead of mirroring the underlying source file.
- Keep each `docs/task/TASK-*.md` at or below 220 lines.
- Keep each `docs/decisions/decision-*.md` at or below 180 lines.
- Keep shadow docs routing-oriented and link to deeper docs instead of copying large text blocks.

Use:
- `scripts/validate_docs.sh <project-root> --mode advisory` for local warning mode
- `scripts/validate_docs.sh <project-root> --mode strict` for CI blocking mode

## Shadow graph contract

Use `<project-root>/docs/shadow/` as the canonical AI-facing routing layer for the project.

Shadow rules:
- Keep shadow docs in English.
- Keep shadow docs in Markdown only.
- Do not add JSON sidecars or empty concern placeholder files.
- Use topology-first typed buckets:
  - `apps`
  - `services`
  - `packages`
  - `infra`
  - `data`
- Use this default read path:
  - `project-shadow.md -> <bucket>/_index.md -> <bucket>/<unit>/overview.md -> concern leaf`
- Treat `_global.md` as an optional side path for cross-unit facts, not as a required read hop.
- Use unit `overview.md` as the day-one landing doc for detected units.
- Materialize concern leaf docs only when source evidence or an explicit task justifies them.
- Preserve old shadow paths with thin redirect shims and archive replaced bodies under `_deprecated` or `_obsolete`.

### Top Router Template

Use `<project-root>/docs/shadow/project-shadow.md` as the top router only.

```markdown
# Project Shadow

- doc_role: router
- read_path:
- fast_entry:
- bucket_links:
- global_doc:
- last_updated:
- updated_by_task:
- latest_change_note:
```

### Global Cross-Unit Template

Use `<project-root>/docs/shadow/_global.md` for cross-unit invariants only.

```markdown
# Shadow Global

- doc_role: global
- shared_runtime_rules:
- shared_config_rules:
- naming_rules:
- cross_unit_integration_contracts:
- last_updated:
```

### Bucket Registry Template

Use `<project-root>/docs/shadow/<bucket>/_index.md` for unit membership only.

```markdown
# Shadow Bucket Index

- doc_role: bucket_index
- bucket:
- last_updated:

## Units
- unit_id:
  - overview_doc:
  - secondary_tags:
```

### Unit Overview Template

Use `<project-root>/docs/shadow/<bucket>/<unit>/overview.md` as the landing doc plus concern router.

```markdown
# Shadow Unit Overview

- doc_role: unit_overview
- home_bucket:
- secondary_tags:
- unit_summary:
- owns:
- entrypoints:
- planned_concerns:
- next_docs:
- source_of_truth_paths:
- last_updated:
```

### Concern Leaf Template

Use a concern leaf doc for concrete facts only.

```markdown
# Shadow Concern

- doc_role: concern_leaf
- concern_id:
- canonical_for:
- source_of_truth_paths:
- change_hotspots:
- contracts_and_rules:
- next_split_trigger:
- last_updated:
```

### Source-of-truth digest (optional, freshness binding)

A unit overview or concern leaf that lists `source_of_truth_paths` may optionally add a `source_of_truth_digest` field to bind the doc to the current CONTENT of those sources, so freshness is checked against what the source actually is rather than a timestamp. It is opt-in and advisory:

- Write it only with `scripts/shadow_source_digest.py <doc> --project-root <root> --write`. It is a deliberate verification assertion — `doc_garden.sh` and the scaffold never write or bump it.
- `scripts/validate_docs.sh --mode advisory` recomputes the digest (via `--check`) and warns on drift (source changed since last verification), a missing declared source, or a source path that escapes the project root. Strict mode skips it (recommended tier).

### Effect Map Leaf Template

Use `doc_role: effect_map` only for shadow docs that record side-effect entries under the Shadow Effect Map Workflow Contract. Effect maps are concern-leaf style docs with a stricter writer gate; they must not replace routers, bucket indexes, unit overviews, or general navigation summaries.

```markdown
# Shadow Effects

- doc_role: effect_map
- generated_by: shadow_effect_writer.py
```

Confirmed deterministic entries must render only after the writer re-checks registry compatibility, policy-declared rule-to-effect compatibility, current artifact identity, a matching probe-result artifact path/hash, and its own probe rerun from structured `probe_args`. Code evidence records include `evidence_rule_id`, `evidence_ref`, `evidence_source_ref`, `evidence_source_hash`, `evidence_probe_result_ref`, and `evidence_probe_result_hash`; runtime evidence records include `evidence_ref`, `evidence_trace_ref`, `evidence_artifact_hash`, `evidence_probe_result_ref`, and `evidence_probe_result_hash`. User-decision evidence records require a separate affirmative fact-evidence decision bound to the record id, effect type, statement hash, and anchor; write-mode final apply decisions are authorization only and must bind the exact target file plus record content hash fields.

### Redirect Shim Template

Use a thin redirect shim at the legacy path when a shadow doc moves.

```markdown
# Shadow Redirect

- doc_role: redirect_shim
- legacy_path:
- canonical_path:
- redirects_fact_scope:
- deprecated_since:
- status: redirected
- edit_policy: read_only
- replacement_reason:
- last_updated:
```

Purpose:
- Allow agents to understand the project quickly without scanning many source files.
- Keep the shadow graph routing-oriented instead of source-mirroring.
- Keep cross-unit facts, unit routing, and leaf facts in separate homes.
- Keep deep and verbose content in linked docs; keep shadow concise and map-like.
