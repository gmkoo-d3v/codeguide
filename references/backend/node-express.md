# Node / Express Backend Patterns

Extracted verbatim from references/backend-patterns.md for Phase 4 index-ization.

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

