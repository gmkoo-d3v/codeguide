# Performance Optimization

Extracted verbatim from references/integration-patterns.md for Phase 4 index-ization.

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
