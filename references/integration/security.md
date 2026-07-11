# Security Integration Patterns

Extracted from references/integration-patterns.md for Phase 4 index-ization; auth-token guidance rewritten to secure-by-default (cookie/BFF over browser storage) 2026-07-11.

## Security

### Authentication (JWT)

**Token storage decision (frontend) — decide before writing any client auth code:**
- Default: never expose the session token to page JavaScript. Deliver it as an `HttpOnly; Secure; SameSite=Strict` (or `Lax`) cookie the server sets, or run a Backend-for-Frontend (BFF) that holds the token server-side and gives the browser only a first-party session cookie.
- Rationale: an `HttpOnly` cookie is unreadable to injected scripts, so a single XSS flaw cannot exfiltrate the session — the dominant SPA token-theft vector.
- Cost: cookies ride along automatically, so the session is now exposed to CSRF. Pair the cookie default with the CSRF defense below; a BFF carries the same obligation for state-changing calls.
- Reject browser-readable storage for access or refresh tokens as the default. That is a tradeoff, not a baseline — see "Browser-storage tokens" at the end of this section.

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

The two filters above validate a JWT presented as `Authorization: Bearer`. With the cookie default the browser does not send that header — read the token from the `HttpOnly` session cookie instead, or let a BFF/gateway translate the cookie into a Bearer header for downstream services. The Bearer form stays correct for non-browser clients (mobile apps, service-to-service).

**Frontend (cookie session — default):**
```typescript
// The token lives only in an HttpOnly cookie the server sets:
//   Set-Cookie: session=<jwt>; HttpOnly; Secure; SameSite=Strict; Path=/
// Page JavaScript can neither read nor write it, so XSS cannot steal it.

// services/apiClient.ts
const api = axios.create({
    baseURL: '/api',
    withCredentials: true, // browser attaches the HttpOnly session cookie
});

// Login and logout are server round-trips; no token is handled in JS.
async function login(email: string, password: string) {
    await api.post('/auth/login', { email, password }); // server sets the cookie
}
async function logout() {
    await api.post('/auth/logout');                     // server clears the cookie
}

// Auth state comes from the server, not from a readable token.
async function currentUser() {
    const { data } = await api.get('/auth/me'); // 401 -> treat as logged out
    return data;
}

// State-changing requests must carry the CSRF token (see CSRF Protection).
api.interceptors.request.use(config => {
    config.headers['X-XSRF-TOKEN'] = getCsrfToken();
    return config;
});
```

**Browser-storage tokens (threat-model tradeoff — not the default):**
- What it is: holding the access (and sometimes refresh) token in `sessionStorage` or `localStorage` and attaching it as an `Authorization: Bearer` header from client code.
- Exposure it creates: the value is readable by any script on the origin, so one XSS flaw — including a compromised third-party dependency — exfiltrates the live session. A stored refresh token upgrades that to long-lived account takeover.
- When it may be acceptable: a token-only API with no cookie support, a same-origin app under a strict audited `Content-Security-Policy` with no third-party scripts, short access-token TTLs, and no high-value scope behind the token.
- Required mitigations if you accept it: enforce a strict CSP, keep access-token TTL short, never keep a refresh token in browser storage, sanitize every DOM sink, and pin and scan dependencies. Prefer `sessionStorage` (dies with the tab) over `localStorage`.
- This is a documented deviation, not a pattern to copy by default. If you cannot meet every mitigation above, fall back to the cookie or BFF default.

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

