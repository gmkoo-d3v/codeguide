# Smells Overview - Good and Bad Signals

Use this reference when asked for good smells, bad smells, or best practices. Treat smells as heuristics, not absolute rules.

## Good smells (do)
- Single responsibility per module, with clear ownership.
- Small, composable functions with explicit inputs/outputs.
- Pure domain logic separated from I/O and framework glue.
- Centralized cross-cutting concerns (logging, authz, validation).
- Config-first values for environment-specific settings.
- Explicit contracts between layers (DTOs/interfaces).
- Tests named for behavior with clear Arrange-Act-Assert structure.

## Bad smells (avoid)
- Mixing business logic with controllers/routes/UI components.
- Hardcoded URLs, feature flags, timeouts, or magic numbers.
- Deep nesting, long methods, and hidden side effects.
- Duplicate logic across layers or features.
- Silent error handling or overly broad exception catches.
- Implicit global state and hidden coupling.
- Classes/functions with unrelated responsibilities.

## Do vs Don't (generic)

```text
# Don't: cross-cutting scattered
controller -> service -> repo (each logs/authz/validation)

# Do: cross-cutting centralized
controller -> service -> repo
          \-> middleware/aspect handles logging/authz/validation
```

```text
# Don't: config values inline
const timeout = 10000

# Do: config values injected
const timeout = config.httpTimeoutMs
```

```text
# Don't: swallow errors
try { doWork() } catch (e) {}

# Do: surface and map errors
try { doWork() } catch (e) { log(e); throw mapError(e) }
```
