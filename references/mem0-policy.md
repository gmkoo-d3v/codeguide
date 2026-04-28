# mem0 Policy

Use this reference only when durable memory could affect prior judgments, historical reasoning context, user preferences, architectural decisions, recurring conventions, or workflow constraints.

## Role
- mem0 is an auxiliary memory/index layer, not a source of truth.
- pgvector semantic search and Neo4j graph search are auxiliary retrieval backends, not authority.
- Use mem0 only when the user explicitly asks to search memory, prior-context lookup is needed and cannot be answered from docs or code, or a phase gate/review requires memory consistency checks.
- Unsupported memory facts may be used only as retrieval hints and must be labeled `[unsupported-memory]`.
- Memory output is never authoritative until verified against docs, code, command output, tests, or runtime evidence.

## Status
- mem0 is not an active semi-automatic workflow.
- mem0 is disabled by default for normal task startup.
- Allowed usage is restricted to read-only, advisory lookups under explicit triggers.
- mem0 writes are prohibited until all broader activation gates pass.

## Scope rules
- Use explicit scope identifiers where supported.
- Choose scope by data ownership before applying the default order: personal preferences should use `user_id` when available, while shared project conventions and decisions should use project or workspace scope.
- Preferred scope order:
  1. project or workspace scope
  2. `app_id` or `app`
  3. `user_id`
  4. `agent_id`
  5. `run_id`
  6. tool default scope only if no explicit scope is available
- Always report the exact scope used.
- If explicit scope is unsupported, report the fallback scope and treat results as lower confidence.

## Read functions
When available, use read-only functions first:
- `search`: semantic memory search.
- `get`: retrieve by id.
- `list`: list memories in scope.
- `list_entities`: inspect entity-like scopes.
- `graph/query`: inspect auxiliary graph relationships.
- pagination or cursor tools: read bounded pages.

Read rules:
- Record whether results are sampled or exhaustive.
- Default pagination cap: `max_pages=5`, `max_items=100`, unless the runtime config is stricter.
- Stop when no cursor remains, the cap is reached, timeout occurs, or the item is `[blocked]`.
- Report non-exhaustive reads explicitly.
- Verify memory claims before using them as factual claims.

## Write functions
Write-like functions may include:
- `add`
- `create`
- `write`
- `update`
- `delete`
- `delete_all`
- stale marking
- graph cleanup
- graph rebuild
- pagination-aware batch mutation

Write rules:
- mem0 writes are disabled by default.
- Activation gates are mandatory; explicit user approval cannot bypass missing gates.
- After all activation gates pass, require explicit user approval for the exact write batch.
- No auxiliary tool may trigger mutation, cleanup, deletion, rebuild, or persistent storage without explicit approval.
- Never store secrets, raw tokens, private keys, raw conversation logs, sensitive personal data, or unverified claims.
- Prefer source references, hashes, source paths, timestamps, and short verified summaries.
- Include these fields where schema supports them:
  - `source_ref`
  - `source_type`
  - `last_verified_at`
  - `freshness`
  - `stale_reason`
  - deletion/update path
- If required metadata is unsupported by the tool schema, block the write or use an approved wrapper that preserves the metadata.
- If update is overwrite-only, read the current value first, compute the replacement, and confirm overwrite risk.
- If delete is destructive, require explicit confirmation.

## Graph and semantic search
- Treat semantic and graph results as auxiliary retrieval signals.
- Never use graph edges as authoritative facts.
- Require `source_ref`, `last_verified_at`, and freshness metadata before trusting an edge even as a strong hint.
- If source docs or code changed, produce a stale-candidate dry-run report first.
- Stale marking or cleanup requires explicit approval after dry-run.
- For graph cleanup, never delete shared entities unless the tool proves they are orphaned.
- Use bounded pagination for graph reads and report coverage.
- Do not persist raw Serena observations into mem0 or Neo4j.
- Prefer docs-derived pointers and indexes over storing decision claims directly in graph nodes or edges.

## Capability checklist
Never claim all mem0 features are active unless the current runtime verifies:
- read: `get`
- read: `search`
- read: `list`
- read: `list_entities`
- write: `add/create/write`
- write: `update`
- write: `delete`
- semantic search
- graph read/query
- graph stale marking
- graph cleanup/rebuild dry-run
- pagination/cursor handling
- scope handling with explicit ids
- error handling for adapter, local-mode, `user_id`, and schema failures

If any item is missing or unverified, report partial activation.

## Failure handling
If mem0 fails, report `[blocked]` with one of:
- `missing_tool_exposure`
- `adapter_error`
- `local_mode_wrapper_issue`
- `user_id_scope_mismatch`
- `schema_version_mismatch`
- `graph_backend_unavailable`
- `pagination_unsupported`
- `discovery_unavailable`
- `unknown_failure`

Then continue with docs, code, validated command output, and `rg`. Use Serena only if independently available and verified.

## Forbidden memory content
- Secrets.
- Credentials.
- API keys or raw tokens.
- Private keys.
- Sensitive personal data.
- Raw conversation logs.
- Unverified external claims.
- Volatile facts such as branch names, PR states, issue states, or temporary debugging details.
- Temporary local paths or environment state unless the user explicitly asks to remember a durable workspace convention.

## Activation gates for broader use
- Storage compatibility issues, including vector dimension mismatch, are resolved.
- Graph backend availability and schema compatibility are verified when Neo4j is used.
- Retention and expiration policy is documented.
- Deletion and update workflow is documented.
- Read/write logging or audit trail is available.
- Explicit opt-in phrase is defined.
- Stale-memory conflict handling is documented.
- Write approval flow is documented and tested.

## Conflict handling
- Current instructions override memory.
- Docs are the system of record, but code/tests/runtime evidence can mark docs as stale candidates.
- Repository files, command output, tests, runtime evidence, and workspace docs override unsupported memory.
- When memory conflicts with current sources, use the current source for the immediate task and report the stale memory only if it affects confidence or user expectations.
- Do not persist conflict corrections unless the user gives explicit consent for the replacement memory item.
