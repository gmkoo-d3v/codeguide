# Serena Workflow

Use this reference when symbolic code navigation can reduce risk, context size, or missed-reference probability.

## Role
- Serena is an auxiliary symbolic-code navigation and refactor assistant.
- Serena collects current-codebase evidence: symbols, anchors, references, call chains, dependency edges, and code topology.
- Serena is not a source of truth and must not override docs, direct file reads, command output, tests, or runtime evidence.
- Serena memory or project state must not override current repository files.

## Status
- Serena is always-on support for shadow-related work when available and verified in the current runtime.
- Shadow-related work includes reading or updating shadow docs, effect maps, call-chain records, review-question packets, user-decision context, anchors, references, and current-code topology for shadow evidence.
- Outside shadow-related work, Serena remains flow-triggered semi-automatic support for material symbolic code work.
- The user does not need to mention Serena when shadow-related work or another concrete trigger fits, unless a current kill switch disables it.
- Serena observations are advisory until verified with direct file reads, `rg`, command output, tests, or runtime evidence.
- Serena is not required for non-shadow simple docs-only edits, isolated single-file changes, mechanical changes that are already fully scoped, or tasks where direct file reads are sufficient.

## Flow triggers
- Use Serena for shadow-related work by default.
- Use Serena when explicitly requested.
- Use Serena when the task requires symbol lookup.
- Use Serena when the task requires reference search.
- Use Serena when the task requires call-chain analysis.
- Use Serena when the task requires cross-file impact analysis.
- Use Serena when the task requires safe rename, move, or extraction planning.
- Use Serena when the task requires architecture navigation or unfamiliar codebase mapping.
- Use Serena when the task changes shared DTOs, APIs, schemas, or configuration.
- Use Serena when a code change touches three or more files, unless the change is mechanical, already fully scoped, or Serena is unavailable.
- Skip Serena when the user disables it, current-runtime verification fails, no concrete trigger fits for non-shadow work, the task is an isolated non-shadow single-file or docs-only change, or the change is mechanical and already fully scoped with direct file reads.

## Context budget role
- Use Serena to narrow the current-code search space to specific symbols, references, call-chain candidates, and impacted files.
- Do not paste broad symbolic overviews into the working context when a short list of paths, symbols, and line anchors is enough.
- Treat Serena output as a navigation index that points to direct source reads; do not treat it as final validation evidence.
- Prefer Serena before broad manual file reading when symbolic scope is unclear; for shadow-related work, keep it available even when the first target file is obvious because follow-on anchors and references are often the real risk.
- Do not persist raw Serena observations into mem0, Neo4j, or project docs; record only verified source-backed facts or concise pointers.

## Result limits and invocation strategy
- The CodeGuide Docker Serena deployment overrides global `default_max_tool_answer_chars` to `200000` characters. Serena source has a separate built-in fallback of `150000`, which applies only when deployment configuration does not override it. The deployed `200000` value is a server default, not a promise that an MCP bridge or a Codex client can accept, retain, or display all `200000` characters; see `mcp-context-integration.md` for that boundary.
- `max_answer_chars=-1` uses Serena's global default. A positive per-call `max_answer_chars` overrides that default for the call; zero and other negative values are invalid.
- When a full result exceeds the effective limit, Serena does not return a truncated full body. It returns an "answer is too long" message; tools with a built-in shortening strategy can instead attach the first shorter summary that fits. Treat either response as a refinement signal, not as complete evidence.
- The first `find_symbol` search call must narrow scope: set `relative_path`, use `depth=0`, set `include_body=false`, and set `max_matches` when the expected match set is not already bounded. Example: `find_symbol(name_path_pattern="Target", relative_path="scripts", depth=0, include_body=false, max_matches=20, max_answer_chars=-1)`.
- Retrieve source bodies only in a separate call for the required symbols after the narrowed search identifies them. Do not request bodies in the initial search.
- For `read_file`, split reads into 50–150-line ranges with explicit zero-based, inclusive `start_line` and `end_line` values instead of requesting an entire large file.
- On an overflow response, proceed in this order: (1) make the query more specific; (2) restrict `relative_path`; (3) reduce `depth` or keep `include_body=false`; (4) limit `max_matches`; (5) split by file, symbol, or line range; (6) increase `max_answer_chars` only as a last resort. Do not retry the same broad query indefinitely.

## Workflow
1. Discover Serena tools through the current runtime's approved discovery path.
2. Activate or select the correct project if required and supported.
3. Define the repository root, target modules, anchors, and symbols of interest; for shadow-related work, include the affected shadow docs or effect records.
4. Use Serena-provided symbolic overview, symbol search, reference search, and dependency navigation when available.
5. Verify every material observation with direct file reads, `rg`, command output, tests, or runtime evidence before editing.
6. Apply edits within the requested ownership boundary.
7. Run the smallest validation set that proves the changed behavior.
8. Refresh project docs or shadow docs when the symbolic change affects behavior, architecture, public contracts, or verified project knowledge.

## Fallback
- If Serena is unavailable, stale, misconfigured, disabled, too slow, or not useful, continue with `rg`, direct file reads, docs, validated command output, and runtime evidence.
- Prefer `rg --files`, `rg`, and direct reads for fallback navigation.
- Report fallback when it affects confidence, missed-reference risk, or final documentation.
- Do not pause implementation solely because Serena is unavailable when direct sources are enough.

## Freshness checks
- Confirm the active Serena project matches the repository being edited before relying on symbolic results. In the skills layout the authoritative Serena project is the SOURCE repo (the skill package), never the docs root: a docs-only parent repo gitignores the source directory, and with ignore_all_files_in_gitignore enabled a parent-rooted project would hide every source file from indexing.
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
- Keep project `docs/` as the system of record even when Serena project memory contains a matching summary.

## Verification expectations
- For refactors, prove references compile or tests cover the changed surface.
- For API or DTO changes, verify consumers, schemas, and serialization boundaries.
- For configuration changes, verify environment defaults and failure behavior.
- For debugging, document the repro, hypothesis, changed symbol path, and validation result.
