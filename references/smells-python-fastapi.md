# Smells - Python/FastAPI

## Good smells (do)
- Routers are thin; services hold business rules.
- Pydantic models for request/response contracts.
- Dependencies manage DB sessions and auth.
- Central exception handlers for consistent errors.
- Settings managed via environment/config.
- Use response_model to enforce output shape.

## Bad smells (avoid)
- Business logic inside route functions.
- Global DB sessions or mutable globals.
- Returning raw dicts without response models.
- Catch-all exceptions that hide errors.
- Blocking I/O in async endpoints.
- Pydantic validation bypassed with dict access.

## Do vs Don't (code)

```python
# Don't: logic and DB in route
@router.post('/users')
async def create_user(payload: dict):
    user = User(**payload)
    db.add(user)
    db.commit()
    return {'id': user.id}

# Do: dependency + service
@router.post('/users', response_model=UserOut)
async def create_user(payload: UserIn, service: UserService = Depends()):
    return await service.create(payload)
```

```python
# Don't: config inline
TIMEOUT_MS = 10000

# Do: settings object
class Settings(BaseSettings):
    http_timeout_ms: int = 10000

settings = Settings()
```

```python
# Don't: ignore response_model
@router.get('/users/{user_id}')
async def get_user(user_id: int):
    user = await service.get(user_id)
    return {'id': user.id, 'email': user.email}

# Do: enforce output contract
@router.get('/users/{user_id}', response_model=UserOut)
async def get_user(user_id: int):
    return await service.get(user_id)
```
