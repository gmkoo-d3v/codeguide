# Common Backend Patterns

Extracted verbatim from references/backend-patterns.md for Phase 4 index-ization.

## Common Backend Patterns

### Repository Pattern
- Abstracts data access logic
- Single source of truth for database operations
- Enables easy mocking for tests

### Service Layer Pattern
- Contains business logic
- Transaction boundaries
- Coordinates between repositories and external services

### DTO Pattern
- Transfer data between layers
- Decouple API contracts from domain models
- Validation and transformation

### Unit of Work Pattern
- Manages transactions across multiple operations
- Ensures atomicity
- Rolls back on failure

### Factory Pattern
- Encapsulates object creation logic
- Useful for complex entity initialization
- Centralize creation rules

### Strategy Pattern
- Different algorithms for same task
- Payment processing, notification sending
- Switch implementations at runtime
