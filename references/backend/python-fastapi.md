# Python / FastAPI Backend Patterns

> Non-authoritative legacy examples. For version-specific APIs and setup, route to the official FastAPI/Pydantic skill or docs first.

Extracted verbatim from references/backend-patterns.md for Phase 4 index-ization.

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
        return UserResponse.model_validate(user) if user else None

    async def create_user(self, user_data: UserCreate) -> UserResponse:
        existing = await self.user_repository.find_by_email(user_data.email)
        if existing:
            raise ValidationError("Email already exists")

        user = await self.user_repository.create(user_data)
        return UserResponse.model_validate(user)
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
        user = User(**user_data.model_dump())
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
from httpx import ASGITransport, AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_create_user_integration():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/api/users",
            json={"email": "test@example.com", "name": "Test User"}
        )

    assert response.status_code == 201
    assert response.json()["email"] == "test@example.com"
```

---

