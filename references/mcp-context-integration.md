# MCP Context Integration

Use this reference when MCP tools may affect context discovery, source authority, durable memory behavior, or evidence reporting.

## Operating principle
- Workspace `docs/` folders are the authoritative project record and system of record.
- Repository files, validated command output, tests, and runtime observations are current evidence.
- Serena, mem0, pgvector, Neo4j, and other MCP tools are auxiliary evidence collectors only.
- Never promote Serena, mem0, pgvector, Neo4j, or another auxiliary MCP tool to system of record.
- If code, tests, command output, or runtime evidence conflicts with docs, treat docs as a stale candidate and report the conflict before changing either side.
- If auxiliary tool output conflicts with docs, code, tests, command output, or runtime evidence, mark the auxiliary result as stale, unsupported, unresolved, or blocked.
- Prefer the smallest MCP interaction that improves correctness or reduces context load.

## Trigger posture
- MCP tools are not unconditional defaults.
- Use an MCP tool only when explicitly requested or when the task flow has a concrete trigger for that tool.
- A matching flow trigger can use the tool even when the user did not name the tool.
- A current kill switch overrides normal flow triggers.

## Evidence report shape
Use this shape when MCP evidence materially affects a task:

```yaml
authoritative_record: docs
evidence_basis: docs | code | command_output | runtime | mixed | unresolved
project_scope:
  id: "<project id or none>"
  source: env | config | tool_filter | docs | mcp_project | unavailable
  confidence: verified | derived_unverified | unsupported
  verified_against: "<path, command, tool result, or none>"
mem0_status: used | skipped | blocked
mem0_write_status: disabled | not_requested | approved | blocked
serena_status: used | skipped | blocked
unsupported_memory:
  - item: "<memory hint>"
    reason: "<why it is unsupported>"
verified_against:
  - path_or_command: "<path or command>"
    evidence_type: docs | code | test | runtime
conflicts:
  - item: "<conflicting item>"
    docs_claim: "<claim from docs>"
    observed_evidence: "<evidence from code, command output, test, or runtime>"
    action: update_docs | fix_code | unresolved | blocked
stale_or_blocked_items:
  - item: "<stale or blocked item>"
    reason: "<reason>"
    fallback: "<fallback source or action>"
mutations:
  - tool: mem0 | graph | other
    status: disabled | dry_run | approved | blocked
    approval_ref: "<user approval or none>"
    summary: "<exact batch summary or none>"
```

## Discovery rules
- Discover available MCP tools through the current runtime's approved discovery path.
- Prefer `tool_search` when available.
- If no discovery mechanism is available, report `[blocked: discovery_unavailable]`.
- Do not assume create, write, update, delete, search, graph, pagination, or scope tools exist.
- If a requested capability is absent, report `[blocked]`.
- If a tool exists but fails, report the sanitized failure class.
- If the adapter only returns a generic error, use `[unknown_failure]` with a sanitized summary.
- Fall back to docs, repository files, validated command output, and `rg`.

## Supported MCP roles
- Serena: auxiliary current-codebase symbolic and structural evidence collector for anchors, symbols, references, call-chain discovery, and impact analysis.
- mem0: auxiliary durable memory/index for prior judgments, historical reasoning context, preferences, conventions, and previous decision context.
- pgvector: auxiliary semantic retrieval backend for mem0-like memory, never authority.
- Neo4j: auxiliary graph retrieval backend for relationships between evidence sources, never authority.
- Other MCP tools: use only when their output can be checked against authoritative docs or current runtime evidence, or when the user explicitly requests the connected system.

## Project scope isolation
- For shared MCP backing stores, always identify the active project scope before relying on auxiliary results.
- Use config-first project identity when available, such as `GRAPH_SYNC_PROJECT_ID`.
- Derive the expected project id from the active project's docs, runtime config, checked environment, or verified MCP project selection.
- Do not hard-code one repository's project id as the default for other projects.
- Mem0, pgvector, and Neo4j results for project-specific work must be filtered by project id when the runtime exposes project-scoped metadata.
- Treat missing, `global`, ambiguous, or default-derived project ids as unsupported for project-specific facts; use them only as retrieval hints after labeling the scope problem.
- Serena normal project memories are isolated by the active project's `.serena/memories`; do not redesign them around DB-level project ids.
- Global Serena memories and global Serena configuration are not project-local and require the same caution as other shared auxiliary context.

## Combined workflow
1. Read current docs/system-of-record material when relevant.
2. Inspect repository files with `rg` and direct reads.
3. Use Serena only when explicitly requested or a symbolic-code flow trigger fits.
4. Use mem0 only when explicitly requested, prior context cannot be answered from docs/code, or a phase gate requires memory consistency checks.
5. Synthesize conflicts explicitly.
6. Implement scoped changes when requested.
7. Verify with compile checks, tests, runtime checks, or documented review.
8. Update docs only when behavior, architecture, API, or verified project knowledge changes.
9. Report unresolved auxiliary-tool gaps.

## Conflict handling
- Treat MCP output as a retrieval hint until checked.
- Treat docs as system of record, but do not silently ignore code or runtime evidence that contradicts docs.
- When docs and current evidence conflict, report the conflict and classify the likely action as `update_docs`, `fix_code`, `unresolved`, or `blocked`.
- When auxiliary MCP output conflicts with docs or current evidence, mark the MCP output stale or unsupported.
- Do not use stale MCP context to override a newer user instruction or verified docs update.

## Fallback rules
- If an MCP server is unavailable, stale, misconfigured, disabled, slow, or irrelevant, continue with `rg`, direct file reads, workspace docs, validated command output, and runtime evidence.
- Fallback must not block low-risk work when direct sources are sufficient.
- Report fallback briefly when it materially affects confidence, completeness, or documentation.
- Do not invent MCP results to fill a missing lookup.

## Kill switches
- Honor global kill switches: `skip mcp`, `manual only`, `MCP off`, `MCP 끄고`.
- Honor Serena kill switches: `no serena`, `Serena 쓰지 말고`.
- Honor memory kill switches: `no memory`, `do not use mem0`, `forget memory for this task`.
- Honor graph kill switches: `no graph`, `mem0 graph off`, `Neo4j off`.
- A current-turn kill switch overrides any normal trigger for the named tool or all MCP tools.

## Audit and reporting
- Record MCP usage only when it materially shaped the plan, implementation, or verification.
- For material use, summarize what was checked and how it was verified against docs, current files, tests, command output, or runtime evidence.
- Do not quote or cite memory or graph results as evidence unless the claim has been verified against authoritative docs or current runtime evidence.
- Keep reports concise; MCP details should support decisions, not replace them.

## Write consent
- MCP write operations require explicit user consent unless the write is an ordinary, reversible local file edit already requested by the user.
- mem0 writes are disabled in the default workflow until all mem0 activation gates pass.
- Explicit user consent cannot bypass missing activation gates.
- After activation, memory writes still require explicit per-item consent and must show the exact content or a precise summary of what will be stored.
- Never write secrets, credentials, tokens, sensitive personal data, raw conversation logs, unverified external claims, volatile branch/PR/issue state, or temporary debugging details.

## Final rule
Do not claim a tool capability is working because it exists in a prompt, config, container, or tool list. Claim it only after current-runtime verification.
