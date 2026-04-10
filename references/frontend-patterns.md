# Frontend Architecture Decision Rules

This reference is authoritative for frontend architecture decisions inside `codeguide`.

Use it to decide boundaries, state ownership, verification scope, and review criteria.
Do not use it as a framework tutorial or API reference. Prefer dedicated framework skills, official documentation, and repository-specific conventions for setup and syntax details.

## Source Preference
- Use `codeguide` references for architecture, review standards, and validation expectations.
- Use dedicated framework skills or official documentation for framework APIs, version-specific behavior, and installation steps.
- Use repository-local docs and source code as the final authority when project conventions differ from generic guidance.

## Decision Triggers
- Use this reference when deciding component boundaries, feature ownership, data flow, routing structure, integration seams, or test scope.
- Escalate to deeper framework guidance only after the boundary decision is already clear.

## Architecture Boundaries
- Route-level pages compose features; they should not accumulate business logic that belongs in feature services or domain modules.
- Shared UI components stay presentation-focused and receive state through explicit props or narrow context contracts.
- Feature modules own feature-specific data loading, mutation flows, and local coordination logic.
- Cross-cutting concerns such as analytics, auth session wiring, error reporting, and global notifications must be centralized.
- Keep framework-specific wiring near entrypoints and providers rather than scattering setup code across feature modules.

## State Ownership
- Keep state as local as possible and move it upward only when multiple consumers need a shared source of truth.
- Distinguish server state from client state; do not mirror remote data into ad hoc local caches without a reason.
- Prefer explicit ownership for derived state and loading state to avoid duplicate flags across layers.
- Avoid global stores for short-lived view state such as modal visibility, tab selection, or transient form drafts unless multiple routes truly share it.

## Data Flow And Side Effects
- Move API calls and external integration code behind explicit services, clients, or hooks that expose stable contracts.
- Keep components declarative: render from state, dispatch intent, and leave orchestration to hooks, services, or feature controllers.
- Make asynchronous state transitions observable through consistent loading, success, and failure paths.
- Define cancellation, retry, and stale-data behavior intentionally for user-visible fetches and long-running mutations.

## Forms And Validation
- Validate at the boundary where user input enters the system, then map validation failures to predictable UI states.
- Keep form field wiring and domain validation separate when business rules are reusable outside a single screen.
- Treat server validation as authoritative for persisted data, even when client-side validation exists for UX.

## Styling And Accessibility
- Keep styling decisions aligned with semantic structure; avoid coupling business rules to CSS utility combinations.
- Shared primitives should preserve accessibility defaults for focus, labels, error messaging, and keyboard navigation.
- Prefer design tokens, theme variables, or agreed utility patterns over one-off color and spacing values.

## Integration Seams
- Frontend-backend contracts should be explicit about shape, loading states, and failure modes.
- Normalize transport-specific details at the edge so feature code can depend on product-level concepts.
- Keep client routing, API paths, and environment configuration centralized and discoverable.

## Testing And Verification
- Unit tests should cover state transitions, rendering branches, and reusable pure helpers.
- Integration tests should cover feature flows across components, hooks, and API boundary adapters.
- E2E coverage is required only when behavior crosses pages, browser APIs, or multiple integrations.
- Verification notes should record command, scope, result, and any residual risk when a layer is intentionally skipped.

## Review Heuristics
- Flag components that fetch data, transform business rules, and render complex UI in the same file.
- Flag repeated loading or error handling patterns that should be centralized.
- Flag hidden dependencies on global singletons, ambient config, or DOM state.
- Flag routing or provider changes that do not come with verification of user-visible navigation paths.

## Anti-Patterns
- Tutorial-style folder structures copied without checking project constraints.
- Global stores used as a shortcut for poor module boundaries.
- Multiple sources of truth for the same server-backed entity.
- Styling systems mixed without a clear precedence rule.
- Ad hoc fetch logic embedded in reusable presentation components.

## Handoff Checklist
- State ownership is explicit.
- Integration boundaries are named.
- Shared versus feature-local concerns are separated.
- Verification scope is proportional to the risk of the change.
