# Security Integration Patterns

Extracted verbatim from references/integration-patterns.md for Phase 4 index-ization.

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

