# Serena Workflow

Use this reference when symbolic code navigation can reduce risk, context size, or missed-reference probability.

## Role
- Serena is an auxiliary symbolic-code navigation and refactor assistant.
- Serena collects current-codebase evidence: symbols, anchors, references, call chains, dependency edges, and code topology.
- Serena is not a source of truth and must not override docs, direct file reads, command output, tests, or runtime evidence.
- Serena memory or project state must not override current repository files.

## Status
- Serena is flow-triggered semi-automatic support for material symbolic code work when available and verified in the current runtime.
- Serena is not an unconditional default; use it when explicitly requested or when a concrete symbolic-code trigger fits the task flow.
- The user does not need to mention Serena when a trigger fits, unless a current kill switch disables it.
- Serena observations are advisory until verified with direct file reads, `rg`, command output, tests, or runtime evidence.
- Serena is not required for simple docs-only edits, isolated single-file changes, mechanical changes that are already fully scoped, or tasks where direct file reads are sufficient.

## Flow triggers
- Use Serena when explicitly requested.
- Use Serena when the task requires symbol lookup.
- Use Serena when the task requires reference search.
- Use Serena when the task requires call-chain analysis.
- Use Serena when the task requires cross-file impact analysis.
- Use Serena when the task requires safe rename, move, or extraction planning.
- Use Serena when the task requires architecture navigation or unfamiliar codebase mapping.
- Use Serena when the task changes shared DTOs, APIs, schemas, or configuration.
- Use Serena when a code change touches three or more files, unless the change is mechanical, already fully scoped, or Serena is unavailable.
- Skip Serena when the user disables it, current-runtime verification fails, no concrete trigger fits, the task is an isolated single-file or docs-only change, or the change is mechanical and already fully scoped with direct file reads.

## Workflow
1. Discover Serena tools through the current runtime's approved discovery path.
2. Activate or select the correct project if required and supported.
3. Define the repository root, target modules, anchors, and symbols of interest.
4. Use Serena-provided symbolic overview, symbol search, reference search, and dependency navigation when available.
5. Verify every material observation with direct file reads, `rg`, command output, tests, or runtime evidence before editing.
6. Apply edits within the requested ownership boundary.
7. Run the smallest validation set that proves the changed behavior.
8. Refresh workspace docs or shadow docs when the symbolic change affects behavior, architecture, public contracts, or verified project knowledge.

## Fallback
- If Serena is unavailable, stale, misconfigured, disabled, too slow, or not useful, continue with `rg`, direct file reads, docs, validated command output, and runtime evidence.
- Prefer `rg --files`, `rg`, and direct reads for fallback navigation.
- Report fallback when it affects confidence, missed-reference risk, or final documentation.
- Do not pause implementation solely because Serena is unavailable when direct sources are enough.

## Freshness checks
- Confirm the active Serena project matches the repository being edited before relying on symbolic results.
- Re-read affected source files directly before editing any symbol discovered through Serena.
- Treat missing, surprising, or contradictory symbol results as stale until direct file reads or command output confirm them.
- After large file moves, generated-code updates, branch changes, or MCP server restarts, prefer direct `rg` plus file reads until Serena results are checked against current files.
- Do not claim Serena is working because a port, container, prompt, config entry, or tool list exists; claim it only after a current-runtime tool call succeeds.

## Kill switches
- Do not use Serena when the current user says `no serena`, `Serena 쓰지 말고`, `skip mcp`, `manual only`, `MCP off`, or `MCP 끄고`.
- A kill switch applies for the current task unless the user re-enables Serena explicitly.
- If a kill switch conflicts with an older instruction or default policy, follow the current user instruction.

## Safety boundaries
- Do not let Serena observations override current repository files, docs, command output, test results, or runtime evidence.
- Do not use stale symbol maps as edit authority.
- Do not perform broad automated rewrites solely from symbolic references; inspect the affected source first.
- Do not persist raw Serena observations into mem0 or Neo4j.
- Keep generated notes free of secrets and sensitive personal data.

## Memory isolation
- Treat normal Serena project memories as project-local files under the active project's `.serena/memories`.
- Confirm the active project before reading or writing Serena project memory.
- Do not add DB-level project-id isolation to normal Serena project memories unless the runtime model changes.
- Treat global Serena memories or global Serena configuration as shared auxiliary context; verify them against docs, code, or runtime evidence before use.
- Keep workspace `docs/` as the system of record even when Serena project memory contains a matching summary.

## Verification expectations
- For refactors, prove references compile or tests cover the changed surface.
- For API or DTO changes, verify consumers, schemas, and serialization boundaries.
- For configuration changes, verify environment defaults and failure behavior.
- For debugging, document the repro, hypothesis, changed symbol path, and validation result.
