# React (TypeScript) Frontend Reference

> Secondary reference notice: This document is a deprecated secondary reference inside `codeguide`. Do not use it as the primary source for framework setup or API details. Prefer dedicated framework skills, official documentation, and repository-specific conventions first.

Use this reference only for codeguide architecture and quality decisions in React TypeScript projects.

## Source Preference
- Use official React and TypeScript docs for setup, compiler options, type syntax, hooks details, and version-specific APIs.
- Use repository-local conventions for folder layout, path aliases, strictness level, test libraries, and generated types.
- Use this file to decide type boundaries, state ownership, service contracts, and review focus.

## Project And Type Boundaries
- Treat Vite setup, `tsconfig`, environment typing, and module aliases as tooling concerns that should be verified against official docs and project standards.
- Keep domain DTOs, API response shapes, and component props explicit rather than leaking loosely typed transport objects across feature boundaries.
- Use shared types when multiple modules depend on a contract; keep screen-local props and view models close to their feature.

## Component Patterns
- Separate presentation components from containers so reusable UI depends on typed props, not ambient services or global stores.
- Prefer typed custom hooks for feature orchestration, data loading, and state transitions that would otherwise make components procedural.
- Use discriminated unions or narrow state models when a component has mutually exclusive loading, success, empty, and error states.

## Custom Hooks
- Hooks should expose a stable, typed contract that names data, status, actions, and errors explicitly.
- Keep fetch orchestration, subscriptions, timers, and effect cleanup inside hooks when multiple components need the same behavior.
- Avoid hooks that hide broad global side effects or return loosely shaped objects that callers must guess how to use.

## State Management
- Use `useState` for simple local state with obvious ownership and type inference.
- Use `useReducer` when transitions need action names, reducer tests, or compile-time exhaustiveness checks.
- Use Context for typed low-frequency dependencies such as theme, session, or configuration.
- Use external stores such as Zustand when shared client state needs explicit actions, selectors, and module-level ownership.

## API Service Layer
- Keep HTTP clients, auth headers, response normalization, and error mapping behind typed service functions.
- Model API failures with predictable error shapes instead of throwing untyped values into component code.
- Do not let generated or transport-level types become the only domain language if the UI needs product-specific view models.

## Cross-Cutting Concerns
- Centralize Error Boundaries, auth gates, logging hooks, and telemetry wrappers so policy remains reviewable.
- Use higher-order components only for repeated boundary behavior; prefer typed hooks or wrapper components for local concerns.
- Make cross-cutting utilities generic only when more than one real caller benefits.

## Testing
- Component tests should verify typed props lead to the expected rendering and interaction states.
- Hook and reducer tests should cover action transitions, cleanup behavior, and error branches.
- Integration tests should cover service boundaries where compile-time types do not prove runtime behavior.

## Performance Hooks
- Use `useMemo` for expensive derived values or stable typed objects passed to memoized children.
- Use `useCallback` when callback identity is part of a dependency or memoization contract.
- Use `useRef` for mutable handles, previous values, timers, and imperative integrations that should not trigger render cycles.

## Official Documentation
- React TypeScript: https://react.dev/learn/typescript
- TypeScript: https://www.typescriptlang.org/docs

For setup, APIs, and version-specific syntax, use the official documentation and dedicated framework skills first; this reference covers only codeguide architecture/quality decisions.
