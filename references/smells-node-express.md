# Smells - Node/Express

## Good smells (do)
- Routes are thin; services handle business logic.
- Use middleware for authz, validation, and logging.
- Async errors centralized with a handler.
- Config-driven URLs/keys/timeouts.
- Repositories isolate DB access.
- Request validation via schemas at the boundary.

## Bad smells (avoid)
- Business logic in route handlers.
- req/res objects passed deep into services.
- Inline SQL and string concatenation.
- Unhandled promise rejections.
- Mixed concerns in a single file.
- Trusting raw req.body without validation.

## Do vs Don't (code)

```javascript
// Don't: error handling in every route
app.get('/users/:id', async (req, res) => {
  try {
    const user = await userService.getById(req.params.id)
    res.json(user)
  } catch (err) {
    res.status(500).json({ message: 'error' })
  }
})

// Do: async wrapper + central handler
const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next)

app.get('/users/:id', asyncHandler(async (req, res) => {
  const user = await userService.getById(req.params.id)
  res.json(user)
}))

app.use((err, req, res, next) => {
  res.status(500).json({ message: err.message })
})
```

```javascript
// Don't: DB access in route
app.post('/users', async (req, res) => {
  const user = await db.query(`insert into users(name) values('${req.body.name}')`)
  res.json(user)
})

// Do: service + repository
app.post('/users', asyncHandler(async (req, res) => {
  const user = await userService.create(req.body)
  res.json(user)
}))
```

```javascript
// Don't: accept raw body
app.post('/users', asyncHandler(async (req, res) => {
  const user = await userService.create(req.body)
  res.json(user)
}))

// Do: validate at boundary (example with zod)
const userSchema = z.object({ name: z.string().min(1) })
app.post('/users', asyncHandler(async (req, res) => {
  const payload = userSchema.parse(req.body)
  const user = await userService.create(payload)
  res.json(user)
}))
```
