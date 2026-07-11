# Java / Spring Boot Backend Patterns

> Non-authoritative legacy examples. For version-specific APIs and setup, route to the official Spring Boot skill or docs first.

Extracted verbatim from references/backend-patterns.md for Phase 4 index-ization.

## Java / Spring Boot

### Project Structure

```
com.example.project/
├── domain/           # Entities, Value Objects
├── repository/       # JPA/Data interfaces
├── service/          # Business logic, transaction boundaries
├── web/              # REST controllers, DTOs, handlers
└── config/           # Security, AOP, beans
```

### Controllers

**Best Practices:**
- Use `@RestController` + `@RequestMapping("/api/...")`
- Keep thin: delegate all logic to services
- Validate DTOs with `@Validated`, `@NotNull`, `@Size`
- Return appropriate HTTP status codes

```java
@RestController
@RequestMapping("/api/users")
@Validated
public class UserController {
    private final UserService userService;

    @Autowired
    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/{id}")
    public ResponseEntity<UserDTO> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<UserDTO> createUser(@Valid @RequestBody CreateUserRequest request) {
        UserDTO user = userService.createUser(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(user);
    }
}
```

### Services

**Best Practices:**
- Interface + implementation pattern
- `@Transactional` at service layer only
- One service per domain aggregate
- Inject repositories via constructor

```java
public interface UserService {
    Optional<UserDTO> findById(Long id);
    UserDTO createUser(CreateUserRequest request);
}

@Service
public class UserServiceImpl implements UserService {
    private final UserRepository userRepository;

    @Autowired
    public UserServiceImpl(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<UserDTO> findById(Long id) {
        return userRepository.findById(id)
            .map(UserMapper::toDTO);
    }

    @Override
    @Transactional
    public UserDTO createUser(CreateUserRequest request) {
        User user = UserMapper.toEntity(request);
        User saved = userRepository.save(user);
        return UserMapper.toDTO(saved);
    }
}
```

### Entities & Repositories

**Entities:**
- Minimize setters; use builders or factory methods
- Value Objects for domain concepts
- Validation in domain logic, not just DTOs

```java
@Entity
@Table(name = "users")
public class User {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String name;

    // Constructor, getters, builder
    protected User() {} // JPA requires

    private User(String email, String name) {
        this.email = Objects.requireNonNull(email);
        this.name = Objects.requireNonNull(name);
    }

    public static User create(String email, String name) {
        validateEmail(email);
        return new User(email, name);
    }

    private static void validateEmail(String email) {
        // domain validation logic
    }
}
```

**Repositories:**
```java
public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);

    @Query("SELECT u FROM User u WHERE u.name LIKE %:name%")
    List<User> searchByName(@Param("name") String name);
}
```

### AOP & Cross-Cutting

**Logging Aspect:**
```java
@Aspect
@Component
public class LoggingAspect {
    private static final Logger log = LoggerFactory.getLogger(LoggingAspect.class);

    @Around("@annotation(LogExecutionTime)")
    public Object logExecutionTime(ProceedingJoinPoint joinPoint) throws Throwable {
        long start = System.currentTimeMillis();
        Object result = joinPoint.proceed();
        long duration = System.currentTimeMillis() - start;
        log.info("{} executed in {}ms", joinPoint.getSignature(), duration);
        return result;
    }
}
```

**Global Exception Handler:**
```java
@ControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(NotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(NotFoundException ex) {
        ErrorResponse error = new ErrorResponse("NOT_FOUND", ex.getMessage());
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @ExceptionHandler(ValidationException.class)
    public ResponseEntity<ErrorResponse> handleValidation(ValidationException ex) {
        ErrorResponse error = new ErrorResponse("VALIDATION_ERROR", ex.getMessage());
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
    }
}
```

### Testing

**Unit Test (Controller):**
```java
@WebMvcTest(UserController.class)
class UserControllerTest {
    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private UserService userService;

    @Test
    void getUser_whenExists_returnsUser() throws Exception {
        UserDTO user = new UserDTO(1L, "test@example.com", "Test User");
        when(userService.findById(1L)).thenReturn(Optional.of(user));

        mockMvc.perform(get("/api/users/1"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.email").value("test@example.com"));
    }
}
```

**Integration Test:**
```java
@SpringBootTest
@AutoConfigureTestDatabase
class UserServiceIntegrationTest {
    @Autowired
    private UserService userService;

    @Autowired
    private UserRepository userRepository;

    @Test
    @Transactional
    void createUser_savesToDatabase() {
        CreateUserRequest request = new CreateUserRequest("new@example.com", "New User");
        UserDTO created = userService.createUser(request);

        assertThat(created.getId()).isNotNull();
        assertThat(userRepository.findById(created.getId())).isPresent();
    }
}
```

---

