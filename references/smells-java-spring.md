# Smells - Java/Spring

## Good smells (do)
- Controllers are thin; services contain business logic.
- Transactions live in service layer; boundaries are explicit.
- Entities enforce invariants via factories/builders.
- Repositories are small, query-focused, and testable.
- DTOs isolate external contracts from domain models.
- Validation happens at boundaries with explicit error mapping.

## Bad smells (avoid)
- Fat controllers orchestrating domain logic.
- @Transactional on controllers or repositories.
- Entities with public setters and no invariants.
- Mapping duplicated across layers.
- Looping and calling repositories per item (N+1).
- Returning entities directly from controllers.

## Do vs Don't (code)

```java
// Don't: transaction in controller
@RestController
class AppointmentController {
    private final AppointmentRepository repo;

    @PostMapping("/appointments")
    @Transactional
    public void create(@RequestBody CreateAppointment req) {
        repo.save(Appointment.from(req));
    }
}

// Do: transaction in service
@Service
class AppointmentService {
    private final AppointmentRepository repo;

    @Transactional
    public void create(CreateAppointment req) {
        repo.save(Appointment.from(req));
    }
}
```

```java
// Don't: entity with public setters
@Entity
class User {
    @Setter private String email;
}

// Do: factory enforces invariants
@Entity
class User {
    private String email;

    protected User() {}

    private User(String email) {
        this.email = validate(email);
    }

    public static User create(String email) {
        return new User(email);
    }

    private static String validate(String email) {
        return Objects.requireNonNull(email);
    }
}
```

```java
// Don't: return entity directly
@GetMapping("/{id}")
public User getUser(@PathVariable Long id) {
    return userService.getEntity(id);
}

// Do: return DTO
@GetMapping("/{id}")
public UserDto getUser(@PathVariable Long id) {
    return userService.getDto(id);
}
```
