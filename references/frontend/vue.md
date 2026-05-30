# Vue Frontend Reference

> Secondary reference notice: This document is a deprecated secondary reference inside `codeguide`. Do not use it as the primary source for framework setup or API details. Prefer official documentation and repository-specific conventions first.

Use this reference only for codeguide architecture and quality decisions in Vue projects.

## Source Preference
- Use the official Vue docs for setup, Single-File Component syntax, Composition API details, routing, Pinia APIs, and version-specific behavior.
- Use repository-local conventions for folder layout, testing tools, state library usage, and plugin registration.
- Use this file to decide boundaries, state ownership, service contracts, and review focus.

## Project And Component Boundaries
- Treat project structure examples as prompts to name ownership, not as folder templates to copy blindly.
- Keep presentation components focused on props, emitted events, slots, and accessible markup.
- Use container components or composables when data loading, feature coordination, or mutation flows would otherwise crowd a template.
- Keep app-level plugin registration, router wiring, and provider setup near entrypoints.

## Composables
- Use composables for reusable feature logic, API orchestration, subscriptions, and shared state transitions.
- A composable should expose a clear contract for refs, computed values, actions, loading state, and error state.
- Avoid composables that hide broad global side effects or make ownership of mutations unclear.

## State Management
- Use local component state for view-local interaction state.
- Use Pinia or an agreed store only when state is shared across routes or feature boundaries and needs explicit actions.
- Keep server-backed data ownership, cache invalidation, and optimistic update rules separate from short-lived UI state.

## API Service Layer
- Put HTTP calls, auth headers, response normalization, and transport errors behind service functions or composables.
- Components should render product states and trigger actions, not assemble request details inline.
- Define loading, empty, error, and retry behavior for user-visible data paths.

## Cross-Cutting Concerns
- Centralize error handler plugins, auth router guards, and logging composables so policy remains consistent.
- Keep router guards narrow: validate access and redirect intent, then delegate product logic to services or stores.
- Prefer plugins only when behavior is truly app-wide; feature-local behavior should stay near the feature.

## Common Frontend Patterns
- Container/presentation separation remains useful in Vue when one layer owns orchestration and the other owns rendering.
- Composables are the Vue equivalent of reusable hook-style logic; they should be named around product behavior, not implementation trivia.
- Service layers protect components from transport details and make integration tests easier to target.
- Provider/store patterns should make shared dependencies explicit rather than creating hidden global coupling.

## Testing
- Component tests should cover props, emitted events, slots, and visible rendering branches.
- Composable tests should cover state transitions, cleanup, and error paths.
- Integration tests should cover router, store, and service seams when behavior crosses module boundaries.

## Official Documentation
- Vue: https://vuejs.org

For setup, APIs, and version-specific syntax, use the official documentation and dedicated framework skills first; this reference covers only codeguide architecture/quality decisions.
