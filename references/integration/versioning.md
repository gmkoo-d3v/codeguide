# Versioning

Extracted verbatim from references/integration-patterns.md for Phase 4 index-ization.

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

