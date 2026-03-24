# Backend Patterns - Java/Spring, Node/Express, Python/FastAPI

This reference provides stack-specific implementation patterns for backend development.

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

## Node / Express

### Project Structure

```
src/
├── models/          # Domain entities, database models
├── repositories/    # Data access layer
├── services/        # Business logic
├── controllers/     # Route handlers
├── middleware/      # Cross-cutting concerns
├── routes/          # Route definitions
└── config/          # Configuration, DI container
```

### Controllers

**Best Practices:**
- Thin controllers: delegate to services
- Async/await for all async operations
- Validate input with middleware (Joi, Zod)
- Return consistent error format

```javascript
// controllers/userController.js
class UserController {
    constructor(userService) {
        this.userService = userService;
    }

    async getUser(req, res, next) {
        try {
            const { id } = req.params;
            const user = await this.userService.findById(id);

            if (!user) {
                return res.status(404).json({
                    code: 'NOT_FOUND',
                    message: 'User not found'
                });
            }

            res.json(user);
        } catch (error) {
            next(error);
        }
    }

    async createUser(req, res, next) {
        try {
            const user = await this.userService.createUser(req.body);
            res.status(201).json(user);
        } catch (error) {
            next(error);
        }
    }
}

module.exports = UserController;
```

### Services

**Best Practices:**
- Inject dependencies via constructor
- Handle transactions at service level
- Throw domain-specific errors

```javascript
// services/userService.js
class UserService {
    constructor(userRepository, emailService) {
        this.userRepository = userRepository;
        this.emailService = emailService;
    }

    async findById(id) {
        return this.userRepository.findById(id);
    }

    async createUser(userData) {
        const existing = await this.userRepository.findByEmail(userData.email);
        if (existing) {
            throw new ValidationError('Email already exists');
        }

        const user = await this.userRepository.create(userData);
        await this.emailService.sendWelcomeEmail(user.email);

        return user;
    }
}

module.exports = UserService;
```

### Repositories

**Best Practices:**
- Encapsulate database operations
- Use ORM (Sequelize, TypeORM, Prisma) or query builders
- Return domain objects, not raw database results

```javascript
// repositories/userRepository.js
class UserRepository {
    constructor(db) {
        this.db = db;
    }

    async findById(id) {
        return this.db.user.findUnique({ where: { id } });
    }

    async findByEmail(email) {
        return this.db.user.findUnique({ where: { email } });
    }

    async create(userData) {
        return this.db.user.create({ data: userData });
    }

    async update(id, userData) {
        return this.db.user.update({
            where: { id },
            data: userData
        });
    }
}

module.exports = UserRepository;
```

### Middleware (Cross-Cutting)

**Logging Middleware:**
```javascript
// middleware/logger.js
const logger = require('../utils/logger');

function requestLogger(req, res, next) {
    const start = Date.now();

    res.on('finish', () => {
        const duration = Date.now() - start;
        logger.info({
            method: req.method,
            url: req.url,
            status: res.statusCode,
            duration: `${duration}ms`
        });
    });

    next();
}

module.exports = requestLogger;
```

**Error Handler:**
```javascript
// middleware/errorHandler.js
function errorHandler(err, req, res, next) {
    const statusCode = err.statusCode || 500;
    const code = err.code || 'INTERNAL_ERROR';

    res.status(statusCode).json({
        code,
        message: err.message,
        ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
    });
}

module.exports = errorHandler;
```

### Dependency Injection

```javascript
// config/container.js
const UserRepository = require('../repositories/userRepository');
const UserService = require('../services/userService');
const UserController = require('../controllers/userController');

class Container {
    constructor(db, emailService) {
        this.db = db;
        this.emailService = emailService;
    }

    getUserController() {
        if (!this.userController) {
            const userRepository = new UserRepository(this.db);
            const userService = new UserService(userRepository, this.emailService);
            this.userController = new UserController(userService);
        }
        return this.userController;
    }
}

module.exports = Container;
```

### Testing

**Unit Test:**
```javascript
// __tests__/services/userService.test.js
const UserService = require('../../services/userService');

describe('UserService', () => {
    let userService;
    let mockUserRepository;
    let mockEmailService;

    beforeEach(() => {
        mockUserRepository = {
            findById: jest.fn(),
            findByEmail: jest.fn(),
            create: jest.fn()
        };
        mockEmailService = {
            sendWelcomeEmail: jest.fn()
        };
        userService = new UserService(mockUserRepository, mockEmailService);
    });

    test('createUser creates user and sends email', async () => {
        const userData = { email: 'test@example.com', name: 'Test' };
        mockUserRepository.findByEmail.mockResolvedValue(null);
        mockUserRepository.create.mockResolvedValue({ id: 1, ...userData });

        const result = await userService.createUser(userData);

        expect(result.id).toBe(1);
        expect(mockEmailService.sendWelcomeEmail).toHaveBeenCalledWith('test@example.com');
    });
});
```

---

## Python / FastAPI

### Project Structure

```
app/
├── models/          # SQLAlchemy models, Pydantic schemas
├── repositories/    # Data access layer
├── services/        # Business logic
├── routers/         # API endpoints
├── dependencies/    # Dependency injection
└── core/            # Config, security, middleware
```

### Routers (Controllers)

**Best Practices:**
- Use dependency injection for services
- Pydantic models for validation
- Type hints for all parameters and returns

```python
# routers/users.py
from fastapi import APIRouter, Depends, HTTPException, status
from app.services.user_service import UserService
from app.schemas.user import UserCreate, UserResponse
from app.dependencies import get_user_service

router = APIRouter(prefix="/api/users", tags=["users"])

@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: int,
    user_service: UserService = Depends(get_user_service)
):
    user = await user_service.find_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    user_data: UserCreate,
    user_service: UserService = Depends(get_user_service)
):
    return await user_service.create_user(user_data)
```

### Services

**Best Practices:**
- Inject repositories via constructor
- Use async/await for I/O operations
- Raise domain-specific exceptions

```python
# services/user_service.py
from app.repositories.user_repository import UserRepository
from app.schemas.user import UserCreate, UserResponse
from app.exceptions import ValidationError

class UserService:
    def __init__(self, user_repository: UserRepository):
        self.user_repository = user_repository

    async def find_by_id(self, user_id: int) -> UserResponse | None:
        user = await self.user_repository.find_by_id(user_id)
        return UserResponse.from_orm(user) if user else None

    async def create_user(self, user_data: UserCreate) -> UserResponse:
        existing = await self.user_repository.find_by_email(user_data.email)
        if existing:
            raise ValidationError("Email already exists")

        user = await self.user_repository.create(user_data)
        return UserResponse.from_orm(user)
```

### Repositories

**Best Practices:**
- Async SQLAlchemy for database operations
- Return domain objects or None
- Handle database-specific errors

```python
# repositories/user_repository.py
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.user import User
from app.schemas.user import UserCreate

class UserRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def find_by_id(self, user_id: int) -> User | None:
        result = await self.db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()

    async def find_by_email(self, email: str) -> User | None:
        result = await self.db.execute(select(User).where(User.email == email))
        return result.scalar_one_or_none()

    async def create(self, user_data: UserCreate) -> User:
        user = User(**user_data.dict())
        self.db.add(user)
        await self.db.commit()
        await self.db.refresh(user)
        return user
```

### Dependency Injection

```python
# dependencies.py
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.repositories.user_repository import UserRepository
from app.services.user_service import UserService

def get_user_repository(db: AsyncSession = Depends(get_db)) -> UserRepository:
    return UserRepository(db)

def get_user_service(
    user_repository: UserRepository = Depends(get_user_repository)
) -> UserService:
    return UserService(user_repository)
```

### Middleware (Cross-Cutting)

**Logging Middleware:**
```python
# middleware/logging.py
import time
import logging
from fastapi import Request

logger = logging.getLogger(__name__)

async def log_requests(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    logger.info(
        f"{request.method} {request.url.path} "
        f"status={response.status_code} duration={duration:.3f}s"
    )

    return response
```

**Exception Handler:**
```python
# core/exception_handlers.py
from fastapi import Request
from fastapi.responses import JSONResponse
from app.exceptions import ValidationError, NotFoundError

async def validation_exception_handler(request: Request, exc: ValidationError):
    return JSONResponse(
        status_code=400,
        content={"code": "VALIDATION_ERROR", "message": str(exc)}
    )

async def not_found_exception_handler(request: Request, exc: NotFoundError):
    return JSONResponse(
        status_code=404,
        content={"code": "NOT_FOUND", "message": str(exc)}
    )
```

### Testing

**Unit Test:**
```python
# tests/services/test_user_service.py
import pytest
from unittest.mock import AsyncMock
from app.services.user_service import UserService
from app.schemas.user import UserCreate

@pytest.mark.asyncio
async def test_create_user_success():
    mock_repo = AsyncMock()
    mock_repo.find_by_email.return_value = None
    mock_repo.create.return_value = User(id=1, email="test@example.com", name="Test")

    service = UserService(mock_repo)
    user_data = UserCreate(email="test@example.com", name="Test")

    result = await service.create_user(user_data)

    assert result.id == 1
    assert result.email == "test@example.com"
    mock_repo.create.assert_called_once()
```

**Integration Test:**
```python
# tests/integration/test_users_api.py
import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_create_user_integration():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post(
            "/api/users",
            json={"email": "test@example.com", "name": "Test User"}
        )

    assert response.status_code == 201
    assert response.json()["email"] == "test@example.com"
```

---

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
