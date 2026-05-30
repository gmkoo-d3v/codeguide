# React (JavaScript) Frontend Reference

> Secondary reference notice: This document is a deprecated secondary reference inside `codeguide`. Do not use it as the primary source for framework setup or API details. Prefer dedicated framework skills, official documentation, and repository-specific conventions first.

Use this reference only for codeguide architecture and quality decisions in React JavaScript projects.

## Source Preference
- Use the official React docs for setup, hooks API details, routing ecosystem choices, and version-specific syntax.
- Use repository-local conventions as the final authority for folder layout, build tooling, lint rules, and test libraries.
- Use this file to decide boundaries, state ownership, side-effect placement, and review focus.

## Project And Module Boundaries
- Treat Vite setup, environment files, and build configuration as framework/tooling concerns; do not copy generic setup snippets into project policy.
- Keep application entrypoints thin: provider wiring, router mounting, and global CSS imports belong near the root, not inside feature components.
- Keep feature folders responsible for their own UI, hooks, services, and tests when the behavior is product-specific.

## Component Patterns
- Prefer presentation components for reusable UI; they receive explicit props and avoid fetching, mutation orchestration, or global state reads.
- Use container components or custom hooks when a feature needs data loading, transformation, or coordination across child components.
- Split components when rendering, state transitions, and side effects become difficult to review independently.

## Performance Hooks
- Use `useMemo` only for expensive derived values or stable referential identity that is observable by children or dependencies.
- Use `useCallback` when function identity matters for memoized children, effect dependencies, or external subscriptions; avoid wrapping every handler by default.
- Use `useRef` for mutable values that must persist without re-rendering, DOM handles, timers, previous values, and imperative integration points.
- Treat combined optimization examples such as data tables as proof that measurement and clear dependency ownership matter more than blanket memoization.

## State Management
- Use `useState` for simple local state with one owner and straightforward updates.
- Use `useReducer` when state transitions are coupled, event-like, or easier to test as a reducer contract.
- Use Context for low-frequency shared dependencies such as theme, session, or configuration, not for every piece of server-backed data.
- Use a store such as Zustand only when multiple routes or feature slices need shared client state with explicit actions and selectors.
- Keep server state separate from client UI state; do not mirror remote data into local caches without invalidation rules.

## API Service Layer
- Put fetch calls, response normalization, auth headers, and transport errors behind a service or hook boundary.
- Components should render states and dispatch intent; they should not assemble URLs, retry rules, or response-shape assumptions inline.
- Define loading, empty, error, and retry behavior for user-visible data paths.

## Cross-Cutting Concerns
- Centralize error handling, auth guards, logging, and telemetry so feature components do not duplicate policy.
- Use higher-order components or wrapper components only when they simplify a repeated boundary; prefer hooks when behavior is local to a feature.
- Use Error Boundaries for render-time failures and pair them with operational logging where the product needs diagnosis.

## Testing
- Component tests should cover visible rendering branches and user interactions, not framework internals.
- Hook tests should cover state transitions, side-effect contracts, and error paths.
- Integration or E2E tests are justified when behavior crosses routing, browser APIs, service boundaries, or multiple feature modules.

## Official Documentation
- React: https://react.dev

For setup, APIs, and version-specific syntax, use the official documentation and dedicated framework skills first; this reference covers only codeguide architecture/quality decisions.
