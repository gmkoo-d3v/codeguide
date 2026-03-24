# Smells - React

## Good smells (do)
- Components focus on rendering; data logic in hooks/services.
- Effects declare correct dependencies.
- Derived state uses memoization or computed values.
- Keys are stable IDs, not indices.
- Side effects live in hooks, not render paths.
- State updates are immutable and predictable.

## Bad smells (avoid)
- API calls inside render or conditionals.
- Missing dependencies in useEffect.
- Large components doing too many things.
- Using array index as key for dynamic lists.
- Mutating state directly.
- setState calls inside render loops.

## Do vs Don't (code)

```jsx
// Don't: fetch in render
function Users() {
  const [users, setUsers] = useState([])
  fetch('/api/users').then((r) => r.json()).then(setUsers)
  return users.map((u) => <div key={u.id}>{u.name}</div>)
}

// Do: fetch in effect
function Users() {
  const [users, setUsers] = useState([])

  useEffect(() => {
    let cancelled = false
    fetch('/api/users')
      .then((r) => r.json())
      .then((data) => { if (!cancelled) setUsers(data) })
    return () => { cancelled = true }
  }, [])

  return users.map((u) => <div key={u.id}>{u.name}</div>)
}
```

```jsx
// Don't: missing deps
useEffect(() => {
  setTotal(items.reduce((sum, i) => sum + i.price, 0))
}, [])

// Do: derive or include deps
const total = useMemo(() => items.reduce((sum, i) => sum + i.price, 0), [items])
```

```jsx
// Don't: mutate state
setItems((prev) => {
  prev.push(newItem)
  return prev
})

// Do: immutable update
setItems((prev) => [...prev, newItem])
```
