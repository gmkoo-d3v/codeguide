# Code Review Checklist

## Architecture
- Layers are separated (model/domain, controller/route, view/presentation).
- Cross-cutting concerns are centralized (AOP, middleware, hooks).
- Dependencies are injected; no hidden globals.
- Each module has a single clear responsibility.

## Code Quality
- No duplicated logic; single source of truth.
- Clear naming; boolean names use is/has/can.
- Functions are small and focused; split when responsibilities diverge.
- Comments explain why or non-obvious logic only.

## SOLID
- SRP: one reason to change.
- OCP: extension over modification.
- LSP: subtypes preserve contracts.
- ISP: interfaces are narrow.
- DIP: depend on abstractions.

## Testing
- Core business logic has unit tests.
- Critical paths have integration tests.
- Tests are readable and deterministic.

## Error Handling
- Errors are handled centrally where possible.
- Exceptions map to consistent response formats.
- No silent failures.

## Security
- No hardcoded secrets or tokens.
- Input validation at boundaries.
- Injection defenses (SQL, XSS) in place.
- Authn/authz enforced at every boundary.
- CSRF protections enabled where applicable.

## Standards
- Linters/formatters pass.
- Build/test warnings resolved.

## Smells (Good/Bad)
- Controllers/routes/components stay thin; business logic lives in services.
- No hardcoded config values (URLs, timeouts, flags).
- No silent failures; errors mapped consistently.
- No duplicated logic across layers.
- No per-item DB calls in loops (avoid N+1).

## Common Anti-Patterns to Avoid
- God objects and manager classes doing everything.
- Tight coupling or leaking implementation details.
- Scattered cross-cutting concerns.
- Anemic domain models.
- Big ball of mud architecture.
