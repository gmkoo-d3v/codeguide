# Error Protocol

Extracted verbatim from references/integration-patterns.md for Phase 4 index-ization.

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

