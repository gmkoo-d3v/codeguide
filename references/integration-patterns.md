# Integration Patterns - Backend + Frontend

This reference provides patterns for integrating backend and frontend applications.

## API Contract Management

### OpenAPI / Swagger Specification

**Define Once, Generate Everywhere:**

```yaml
# openapi.yaml
openapi: 3.0.0
info:
  title: User API
  version: 1.0.0

paths:
  /api/users/{id}:
    get:
      summary: Get user by ID
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: integer
      responses:
        '200':
          description: User found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'
        '404':
          description: User not found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'

components:
  schemas:
    User:
      type: object
      required:
        - id
        - email
        - name
      properties:
        id:
          type: integer
        email:
          type: string
          format: email
        name:
          type: string
    Error:
      type: object
      properties:
        code:
          type: string
        message:
          type: string
        details:
          type: object
```

### Backend Integration (Spring Boot)

**Generate from OpenAPI:**
```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.openapitools</groupId>
    <artifactId>openapi-generator-maven-plugin</artifactId>
    <version>6.6.0</version>
    <executions>
        <execution>
            <goals>
                <goal>generate</goal>
            </goals>
            <configuration>
                <inputSpec>${project.basedir}/openapi.yaml</inputSpec>
                <generatorName>spring</generatorName>
                <configOptions>
                    <interfaceOnly>true</interfaceOnly>
                    <useSpringBoot3>true</useSpringBoot3>
                </configOptions>
            </configuration>
        </execution>
    </executions>
</plugin>
```

**Serve Specification:**
```java
// SpringDoc automatically generates OpenAPI spec
// Add dependency: springdoc-openapi-starter-webmvc-ui

// Visit: http://localhost:8080/swagger-ui.html
```

### Frontend Integration

**Generate TypeScript Types:**
```bash
# Using openapi-typescript
npx openapi-typescript ./openapi.yaml -o ./src/types/api.ts
```

```typescript
// src/types/api.ts (generated)
export interface User {
    id: number;
    email: string;
    name: string;
}

export interface Error {
    code?: string;
    message?: string;
    details?: Record<string, any>;
}

export interface paths {
    "/api/users/{id}": {
        get: operations["getUserById"];
    };
}
```

**Type-Safe API Client:**
```typescript
// services/apiClient.ts
import type { User, Error as ApiError } from '@/types/api';

export const apiClient = {
    async getUser(id: number): Promise<User> {
        const response = await fetch(`/api/users/${id}`);
        if (!response.ok) {
            const error: ApiError = await response.json();
            throw new Error(error.message);
        }
        return response.json();
    }
};
```

### Contract Testing

**Backend (Spring Boot):**
```java
@SpringBootTest
class ApiContractTest {
    @Autowired
    private MockMvc mockMvc;

    @Test
    void getUserById_matchesContract() throws Exception {
        mockMvc.perform(get("/api/users/1"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.id").isNumber())
            .andExpect(jsonPath("$.email").isString())
            .andExpect(jsonPath("$.name").isString());
    }
}
```

**Frontend (TypeScript):**
```typescript
// Type checking ensures contract compliance
const user: User = await apiClient.getUser(1);
// TypeScript error if shape doesn't match
```

---

## Error Protocol

### Standard Error Format

**Backend Implementation:**

**Java/Spring:**
```java
public class ErrorResponse {
    private String code;
    private String message;
    private Map<String, Object> details;

    // constructors, getters, setters
}

@ControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(NotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(NotFoundException ex) {
        ErrorResponse error = new ErrorResponse(
            "NOT_FOUND",
            ex.getMessage(),
            Map.of("resource", ex.getResourceType())
        );
        return ResponseEntity.status(404).body(error);
    }

    @ExceptionHandler(ValidationException.class)
    public ResponseEntity<ErrorResponse> handleValidation(ValidationException ex) {
        ErrorResponse error = new ErrorResponse(
            "VALIDATION_ERROR",
            "Invalid input",
            ex.getFieldErrors()
        );
        return ResponseEntity.status(400).body(error);
    }
}
```

**Node/Express:**
```javascript
class ErrorResponse {
    constructor(code, message, details = {}) {
        this.code = code;
        this.message = message;
        this.details = details;
    }
}

function errorHandler(err, req, res, next) {
    if (err instanceof NotFoundException) {
        return res.status(404).json(
            new ErrorResponse('NOT_FOUND', err.message, { resource: err.resourceType })
        );
    }

    if (err instanceof ValidationError) {
        return res.status(400).json(
            new ErrorResponse('VALIDATION_ERROR', 'Invalid input', err.fieldErrors)
        );
    }

    res.status(500).json(
        new ErrorResponse('INTERNAL_ERROR', 'Something went wrong')
    );
}
```

**Python/FastAPI:**
```python
class ErrorResponse(BaseModel):
    code: str
    message: str
    details: dict = {}

@app.exception_handler(NotFoundException)
async def not_found_handler(request: Request, exc: NotFoundException):
    return JSONResponse(
        status_code=404,
        content=ErrorResponse(
            code="NOT_FOUND",
            message=str(exc),
            details={"resource": exc.resource_type}
        ).dict()
    )
```

### Frontend Error Handling

**React Hook:**
```typescript
// hooks/useApiError.ts
interface ApiError {
    code: string;
    message: string;
    details?: Record<string, any>;
}

export function useApiError() {
    const showNotification = useNotification();

    return {
        handle(error: any) {
            if (isApiError(error)) {
                const apiError = error as ApiError;

                switch (apiError.code) {
                    case 'NOT_FOUND':
                        showNotification('Resource not found', 'error');
                        break;
                    case 'VALIDATION_ERROR':
                        showNotification('Invalid input', 'error');
                        return apiError.details; // Return field errors
                    case 'UNAUTHORIZED':
                        // Redirect to login
                        window.location.href = '/login';
                        break;
                    default:
                        showNotification('An error occurred', 'error');
                }
            } else {
                showNotification('Network error', 'error');
            }
        }
    };
}

function isApiError(error: any): error is ApiError {
    return error && typeof error.code === 'string';
}
```

**Vue Composable:**
```typescript
// composables/useApiError.ts
import { inject } from 'vue';

export function useApiError() {
    const notification = inject('notification');

    return {
        handle(error: any) {
            if (error.code) {
                switch (error.code) {
                    case 'NOT_FOUND':
                        notification.error('Resource not found');
                        break;
                    case 'VALIDATION_ERROR':
                        notification.error('Invalid input');
                        return error.details;
                    case 'UNAUTHORIZED':
                        router.push('/login');
                        break;
                    default:
                        notification.error('An error occurred');
                }
            } else {
                notification.error('Network error');
            }
        }
    };
}
```

**Usage in Component:**
```typescript
// React
function UserForm() {
    const { handle } = useApiError();

    const handleSubmit = async (data) => {
        try {
            await userService.create(data);
        } catch (error) {
            const fieldErrors = handle(error);
            if (fieldErrors) {
                setErrors(fieldErrors);
            }
        }
    };
}

// Vue
async function handleSubmit() {
    try {
        await userService.create(formData);
    } catch (error) {
        const fieldErrors = errorHandler.handle(error);
        if (fieldErrors) {
            errors.value = fieldErrors;
        }
    }
}
```

---

## Security

### Authentication (JWT)

**Backend (Spring Security):**
```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/auth/**").permitAll()
                .anyRequest().authenticated()
            )
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS)
            )
            .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}

@Component
public class JwtAuthFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String token = extractToken(request);

        if (token != null && jwtService.validateToken(token)) {
            String username = jwtService.getUsernameFromToken(token);
            UsernamePasswordAuthenticationToken auth =
                new UsernamePasswordAuthenticationToken(username, null, authorities);
            SecurityContextHolder.getContext().setAuthentication(auth);
        }

        filterChain.doFilter(request, response);
    }

    private String extractToken(HttpServletRequest request) {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            return header.substring(7);
        }
        return null;
    }
}
```

**Backend (Node/Express):**
```javascript
const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
    const token = req.headers.authorization?.split(' ')[1];

    if (!token) {
        return res.status(401).json({ code: 'UNAUTHORIZED', message: 'No token provided' });
    }

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        req.user = decoded;
        next();
    } catch (error) {
        return res.status(401).json({ code: 'UNAUTHORIZED', message: 'Invalid token' });
    }
}

// Protected route
app.get('/api/users/:id', authMiddleware, userController.getUser);
```

**Frontend (React):**
```typescript
// contexts/AuthContext.tsx
export function AuthProvider({ children }: { children: ReactNode }) {
    const [token, setToken] = useState<string | null>(
        localStorage.getItem('token')
    );

    const login = async (email: string, password: string) => {
        const response = await authService.login(email, password);
        setToken(response.token);
        localStorage.setItem('token', response.token);
    };

    const logout = () => {
        setToken(null);
        localStorage.removeItem('token');
    };

    return (
        <AuthContext.Provider value={{ token, login, logout }}>
            {children}
        </AuthContext.Provider>
    );
}

// services/apiClient.ts
axios.interceptors.request.use(config => {
    const token = localStorage.getItem('token');
    if (token) {
        config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
});

// Refresh token on 401
axios.interceptors.response.use(
    response => response,
    async error => {
        if (error.response?.status === 401) {
            const refreshToken = localStorage.getItem('refreshToken');
            if (refreshToken) {
                const { token } = await authService.refresh(refreshToken);
                localStorage.setItem('token', token);
                // Retry original request
                error.config.headers.Authorization = `Bearer ${token}`;
                return axios.request(error.config);
            } else {
                // Redirect to login
                window.location.href = '/login';
            }
        }
        return Promise.reject(error);
    }
);
```

### CORS Configuration

**Spring Boot:**
```java
@Configuration
public class CorsConfig {
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of("http://localhost:3000"));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
```

**Express:**
```javascript
const cors = require('cors');

app.use(cors({
    origin: 'http://localhost:3000',
    credentials: true
}));
```

**FastAPI:**
```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### CSRF Protection

**Spring Boot:**
```java
// CSRF typically disabled for stateless JWT APIs
http.csrf(csrf -> csrf.disable())

// For session-based auth, enable CSRF:
http.csrf(csrf -> csrf
    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
)
```

**Frontend (with CSRF):**
```typescript
// Read CSRF token from cookie
function getCsrfToken(): string {
    const match = document.cookie.match(/XSRF-TOKEN=([^;]+)/);
    return match ? match[1] : '';
}

axios.interceptors.request.use(config => {
    config.headers['X-XSRF-TOKEN'] = getCsrfToken();
    return config;
});
```

---

## Deployment Strategies

### Monolith (Embedded Frontend)

**Spring Boot with React build:**
```xml
<!-- pom.xml -->
<plugin>
    <groupId>com.github.eirslett</groupId>
    <artifactId>frontend-maven-plugin</artifactId>
    <executions>
        <execution>
            <id>npm install</id>
            <goals><goal>npm</goal></goals>
            <configuration>
                <arguments>install</arguments>
            </configuration>
        </execution>
        <execution>
            <id>npm build</id>
            <goals><goal>npm</goal></goals>
            <configuration>
                <arguments>run build</arguments>
            </configuration>
        </execution>
    </executions>
</plugin>

<plugin>
    <artifactId>maven-resources-plugin</artifactId>
    <executions>
        <execution>
            <id>copy-frontend</id>
            <phase>process-resources</phase>
            <goals><goal>copy-resources</goal></goals>
            <configuration>
                <outputDirectory>${project.build.outputDirectory}/static</outputDirectory>
                <resources>
                    <resource>
                        <directory>frontend/build</directory>
                    </resource>
                </resources>
            </configuration>
        </execution>
    </executions>
</plugin>
```

**Application Properties:**
```yaml
# application.yml
spring:
  web:
    resources:
      static-locations: classpath:/static/
  mvc:
    view:
      prefix: /
      suffix: .html
```

**Serve Frontend:**
```java
@Controller
public class FrontendController {
    @GetMapping(value = "/{path:[^\\.]*}")
    public String forward() {
        return "forward:/index.html";
    }
}
```

### Separate Deployments

**Backend (Docker):**
```dockerfile
# Dockerfile
FROM openjdk:17-jdk-slim
WORKDIR /app
COPY target/app.jar app.jar
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

**Frontend (Nginx):**
```dockerfile
# Dockerfile
FROM node:18 AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

**Nginx Config:**
```nginx
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }

    location /api {
        proxy_pass http://backend:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**Docker Compose:**
```yaml
version: '3.8'
services:
  backend:
    build: ./backend
    ports:
      - "8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=prod

  frontend:
    build: ./frontend
    ports:
      - "80:80"
    depends_on:
      - backend
```

### CI/CD Pipeline

**GitHub Actions:**
```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  test-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-java@v3
        with:
          java-version: '17'
      - run: mvn test

  test-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm ci
      - run: npm test

  deploy:
    needs: [test-backend, test-frontend]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build and push Docker images
        run: |
          docker build -t myapp-backend ./backend
          docker build -t myapp-frontend ./frontend
          docker push myapp-backend
          docker push myapp-frontend
      - name: Deploy to production
        run: |
          # SSH to server and pull/restart containers
```

---

## Versioning

### API Versioning

**URL Versioning:**
```java
// Spring Boot
@RestController
@RequestMapping("/api/v1/users")
public class UserControllerV1 { }

@RestController
@RequestMapping("/api/v2/users")
public class UserControllerV2 { }
```

**Header Versioning:**
```java
@GetMapping(value = "/users", headers = "API-Version=1")
public List<UserDTO> getUsersV1() { }

@GetMapping(value = "/users", headers = "API-Version=2")
public List<UserDTO> getUsersV2() { }
```

**Frontend Client:**
```typescript
const api = axios.create({
    baseURL: '/api/v1',
    headers: { 'API-Version': '1' }
});
```

---

## Performance Optimization

### Caching

**Backend (Spring):**
```java
@Configuration
@EnableCaching
public class CacheConfig {
    @Bean
    public CacheManager cacheManager() {
        return new ConcurrentMapCacheManager("users", "products");
    }
}

@Service
public class UserService {
    @Cacheable(value = "users", key = "#id")
    public UserDTO findById(Long id) {
        // Expensive operation
    }

    @CacheEvict(value = "users", key = "#id")
    public void update(Long id, UserDTO user) {
        // Update operation
    }
}
```

**Frontend (React Query):**
```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

function useUser(id: string) {
    return useQuery({
        queryKey: ['user', id],
        queryFn: () => userService.getById(id),
        staleTime: 5 * 60 * 1000, // 5 minutes
    });
}

function useUpdateUser() {
    const queryClient = useQueryClient();

    return useMutation({
        mutationFn: ({ id, data }: { id: string; data: Partial<User> }) =>
            userService.update(id, data),
        onSuccess: (_, { id }) => {
            queryClient.invalidateQueries({ queryKey: ['user', id] });
        },
    });
}
```

### Pagination

**Backend:**
```java
@GetMapping
public Page<UserDTO> getUsers(
    @RequestParam(defaultValue = "0") int page,
    @RequestParam(defaultValue = "20") int size
) {
    Pageable pageable = PageRequest.of(page, size);
    return userService.findAll(pageable);
}
```

**Frontend:**
```typescript
function UserList() {
    const [page, setPage] = useState(0);
    const { data, loading } = useQuery({
        queryKey: ['users', page],
        queryFn: () => userService.getAll({ page, size: 20 }),
    });

    return (
        <>
            <List items={data?.content} />
            <Pagination
                page={page}
                totalPages={data?.totalPages}
                onPageChange={setPage}
            />
        </>
    );
}
```
