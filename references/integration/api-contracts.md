# API Contract Management

Extracted verbatim from references/integration-patterns.md for Phase 4 index-ization.

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

