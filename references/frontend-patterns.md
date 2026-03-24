# Frontend Patterns - React & Vue

This reference provides stack-specific implementation patterns for frontend development.

## React

### Project Structure

```
src/
├── components/       # Reusable UI components
│   ├── common/      # Shared across app (Button, Input)
│   └── features/    # Feature-specific components
├── hooks/           # Custom hooks (logic reuse)
├── services/        # API clients, external integrations
├── contexts/        # React Context providers
├── pages/           # Route-level components
├── utils/           # Pure utility functions
└── types/           # TypeScript type definitions
```

### Component Patterns

#### Presentation vs Container

**Presentation Component (Pure UI):**
```typescript
// components/UserCard.tsx
interface UserCardProps {
    user: User;
    onEdit: (id: number) => void;
}

export function UserCard({ user, onEdit }: UserCardProps) {
    return (
        <div className="user-card">
            <h3>{user.name}</h3>
            <p>{user.email}</p>
            <button onClick={() => onEdit(user.id)}>Edit</button>
        </div>
    );
}
```

**Container Component (Logic & Data):**
```typescript
// pages/UserProfile.tsx
export function UserProfile() {
    const { id } = useParams<{ id: string }>();
    const { user, loading, error } = useUser(id);
    const navigate = useNavigate();

    const handleEdit = (userId: number) => {
        navigate(`/users/${userId}/edit`);
    };

    if (loading) return <Spinner />;
    if (error) return <ErrorMessage error={error} />;
    if (!user) return <NotFound />;

    return <UserCard user={user} onEdit={handleEdit} />;
}
```

### Custom Hooks

**Data Fetching Hook:**
```typescript
// hooks/useUser.ts
export function useUser(id: string) {
    const [user, setUser] = useState<User | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<Error | null>(null);

    useEffect(() => {
        let cancelled = false;

        async function fetchUser() {
            try {
                setLoading(true);
                const data = await userService.getById(id);
                if (!cancelled) {
                    setUser(data);
                    setError(null);
                }
            } catch (err) {
                if (!cancelled) {
                    setError(err as Error);
                }
            } finally {
                if (!cancelled) {
                    setLoading(false);
                }
            }
        }

        fetchUser();

        return () => {
            cancelled = true;
        };
    }, [id]);

    return { user, loading, error };
}
```

**Form Handling Hook:**
```typescript
// hooks/useForm.ts
export function useForm<T>(initialValues: T, onSubmit: (values: T) => void) {
    const [values, setValues] = useState<T>(initialValues);
    const [errors, setErrors] = useState<Partial<Record<keyof T, string>>>({});

    const handleChange = (name: keyof T, value: any) => {
        setValues(prev => ({ ...prev, [name]: value }));
        setErrors(prev => ({ ...prev, [name]: undefined }));
    };

    const handleSubmit = async (e: FormEvent) => {
        e.preventDefault();
        try {
            await onSubmit(values);
        } catch (err) {
            // Handle errors
        }
    };

    return { values, errors, handleChange, handleSubmit };
}
```

### State Management

#### Local State (useState)

```typescript
function Counter() {
    const [count, setCount] = useState(0);

    return (
        <div>
            <p>Count: {count}</p>
            <button onClick={() => setCount(count + 1)}>Increment</button>
        </div>
    );
}
```

#### Complex State (useReducer)

```typescript
type State = {
    items: Item[];
    loading: boolean;
    error: string | null;
};

type Action =
    | { type: 'FETCH_START' }
    | { type: 'FETCH_SUCCESS'; payload: Item[] }
    | { type: 'FETCH_ERROR'; error: string }
    | { type: 'ADD_ITEM'; item: Item };

function reducer(state: State, action: Action): State {
    switch (action.type) {
        case 'FETCH_START':
            return { ...state, loading: true, error: null };
        case 'FETCH_SUCCESS':
            return { ...state, loading: false, items: action.payload };
        case 'FETCH_ERROR':
            return { ...state, loading: false, error: action.error };
        case 'ADD_ITEM':
            return { ...state, items: [...state.items, action.item] };
        default:
            return state;
    }
}

function ItemList() {
    const [state, dispatch] = useReducer(reducer, {
        items: [],
        loading: false,
        error: null
    });

    // Use dispatch to update state
}
```

#### Global State (Context API)

```typescript
// contexts/AuthContext.tsx
interface AuthContextType {
    user: User | null;
    login: (email: string, password: string) => Promise<void>;
    logout: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
    const [user, setUser] = useState<User | null>(null);

    const login = async (email: string, password: string) => {
        const userData = await authService.login(email, password);
        setUser(userData);
        localStorage.setItem('token', userData.token);
    };

    const logout = () => {
        setUser(null);
        localStorage.removeItem('token');
    };

    return (
        <AuthContext.Provider value={{ user, login, logout }}>
            {children}
        </AuthContext.Provider>
    );
}

export function useAuth() {
    const context = useContext(AuthContext);
    if (!context) {
        throw new Error('useAuth must be used within AuthProvider');
    }
    return context;
}
```

### API Service Layer

```typescript
// services/userService.ts
import axios from 'axios';

const api = axios.create({
    baseURL: '/api',
    headers: { 'Content-Type': 'application/json' }
});

// Request interceptor (add auth token)
api.interceptors.request.use(config => {
    const token = localStorage.getItem('token');
    if (token) {
        config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
});

// Response interceptor (handle errors)
api.interceptors.response.use(
    response => response,
    error => {
        if (error.response?.status === 401) {
            // Redirect to login
        }
        return Promise.reject(error);
    }
);

export const userService = {
    getById: async (id: string): Promise<User> => {
        const response = await api.get(`/users/${id}`);
        return response.data;
    },

    create: async (userData: CreateUserRequest): Promise<User> => {
        const response = await api.post('/users', userData);
        return response.data;
    },

    update: async (id: string, userData: Partial<User>): Promise<User> => {
        const response = await api.put(`/users/${id}`, userData);
        return response.data;
    },

    delete: async (id: string): Promise<void> => {
        await api.delete(`/users/${id}`);
    }
};
```

### Cross-Cutting Concerns

#### Error Boundary (Error Handling)

```typescript
// components/ErrorBoundary.tsx
import { Component, ReactNode, ErrorInfo } from 'react';

interface Props {
    children: ReactNode;
    fallback?: ReactNode;
}

interface State {
    hasError: boolean;
    error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
    constructor(props: Props) {
        super(props);
        this.state = { hasError: false, error: null };
    }

    static getDerivedStateFromError(error: Error): State {
        return { hasError: true, error };
    }

    componentDidCatch(error: Error, errorInfo: ErrorInfo) {
        console.error('ErrorBoundary caught:', error, errorInfo);
        // Send to logging service
    }

    render() {
        if (this.state.hasError) {
            return this.props.fallback || <ErrorFallback error={this.state.error} />;
        }

        return this.props.children;
    }
}
```

#### Higher-Order Component (HOC)

```typescript
// hocs/withAuth.tsx
export function withAuth<P extends object>(
    Component: ComponentType<P>
): ComponentType<P> {
    return function AuthenticatedComponent(props: P) {
        const { user } = useAuth();
        const navigate = useNavigate();

        useEffect(() => {
            if (!user) {
                navigate('/login');
            }
        }, [user, navigate]);

        if (!user) {
            return <Spinner />;
        }

        return <Component {...props} />;
    };
}

// Usage
const ProtectedPage = withAuth(UserDashboard);
```

#### Custom Hook for Logging

```typescript
// hooks/useLogger.ts
export function useLogger(componentName: string) {
    useEffect(() => {
        console.log(`[${componentName}] mounted`);
        return () => {
            console.log(`[${componentName}] unmounted`);
        };
    }, [componentName]);

    return {
        logEvent: (eventName: string, data?: any) => {
            console.log(`[${componentName}] ${eventName}`, data);
            // Send to analytics service
        }
    };
}

// Usage
function MyComponent() {
    const { logEvent } = useLogger('MyComponent');

    const handleClick = () => {
        logEvent('button_clicked', { buttonId: 'submit' });
    };

    return <button onClick={handleClick}>Submit</button>;
}
```

### Testing

**Component Test (React Testing Library):**
```typescript
// __tests__/UserCard.test.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { UserCard } from '../components/UserCard';

describe('UserCard', () => {
    const mockUser = { id: 1, name: 'Test User', email: 'test@example.com' };
    const mockOnEdit = jest.fn();

    test('renders user information', () => {
        render(<UserCard user={mockUser} onEdit={mockOnEdit} />);

        expect(screen.getByText('Test User')).toBeInTheDocument();
        expect(screen.getByText('test@example.com')).toBeInTheDocument();
    });

    test('calls onEdit when edit button clicked', () => {
        render(<UserCard user={mockUser} onEdit={mockOnEdit} />);

        fireEvent.click(screen.getByText('Edit'));

        expect(mockOnEdit).toHaveBeenCalledWith(1);
    });
});
```

**Hook Test:**
```typescript
// __tests__/useUser.test.ts
import { renderHook, waitFor } from '@testing-library/react';
import { useUser } from '../hooks/useUser';
import { userService } from '../services/userService';

jest.mock('../services/userService');

describe('useUser', () => {
    test('fetches user successfully', async () => {
        const mockUser = { id: 1, name: 'Test', email: 'test@example.com' };
        (userService.getById as jest.Mock).mockResolvedValue(mockUser);

        const { result } = renderHook(() => useUser('1'));

        expect(result.current.loading).toBe(true);

        await waitFor(() => {
            expect(result.current.loading).toBe(false);
        });

        expect(result.current.user).toEqual(mockUser);
        expect(result.current.error).toBeNull();
    });
});
```

---

## Vue

### Project Structure

```
src/
├── components/      # Reusable UI components
├── composables/     # Composition functions (Vue 3)
├── services/        # API clients
├── stores/          # Pinia stores (state management)
├── views/           # Route-level components
├── router/          # Vue Router config
└── types/           # TypeScript type definitions
```

### Component Patterns

#### Presentation Component

```vue
<!-- components/UserCard.vue -->
<template>
    <div class="user-card">
        <h3>{{ user.name }}</h3>
        <p>{{ user.email }}</p>
        <button @click="$emit('edit', user.id)">Edit</button>
    </div>
</template>

<script setup lang="ts">
interface Props {
    user: User;
}

defineProps<Props>();
defineEmits<{
    edit: [id: number];
}>();
</script>
```

#### Container Component

```vue
<!-- views/UserProfile.vue -->
<template>
    <div>
        <Spinner v-if="loading" />
        <ErrorMessage v-else-if="error" :error="error" />
        <NotFound v-else-if="!user" />
        <UserCard v-else :user="user" @edit="handleEdit" />
    </div>
</template>

<script setup lang="ts">
import { useRoute, useRouter } from 'vue-router';
import { useUser } from '@/composables/useUser';
import UserCard from '@/components/UserCard.vue';

const route = useRoute();
const router = useRouter();
const { user, loading, error } = useUser(route.params.id as string);

function handleEdit(userId: number) {
    router.push(`/users/${userId}/edit`);
}
</script>
```

### Composables (Custom Logic)

**Data Fetching Composable:**
```typescript
// composables/useUser.ts
import { ref, onMounted, watch } from 'vue';
import { userService } from '@/services/userService';

export function useUser(id: string) {
    const user = ref<User | null>(null);
    const loading = ref(true);
    const error = ref<Error | null>(null);

    async function fetchUser() {
        try {
            loading.value = true;
            error.value = null;
            user.value = await userService.getById(id);
        } catch (err) {
            error.value = err as Error;
        } finally {
            loading.value = false;
        }
    }

    onMounted(fetchUser);

    // Refetch if id changes
    watch(() => id, fetchUser);

    return { user, loading, error, refetch: fetchUser };
}
```

**Form Handling Composable:**
```typescript
// composables/useForm.ts
import { ref, reactive } from 'vue';

export function useForm<T extends object>(
    initialValues: T,
    onSubmit: (values: T) => Promise<void>
) {
    const values = reactive<T>({ ...initialValues });
    const errors = ref<Partial<Record<keyof T, string>>>({});
    const submitting = ref(false);

    function updateField(name: keyof T, value: any) {
        values[name] = value;
        errors.value[name] = undefined;
    }

    async function handleSubmit() {
        try {
            submitting.value = true;
            errors.value = {};
            await onSubmit(values);
        } catch (err) {
            // Handle validation errors
        } finally {
            submitting.value = false;
        }
    }

    return { values, errors, submitting, updateField, handleSubmit };
}
```

### State Management (Pinia)

```typescript
// stores/auth.ts
import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { authService } from '@/services/authService';

export const useAuthStore = defineStore('auth', () => {
    const user = ref<User | null>(null);
    const token = ref<string | null>(localStorage.getItem('token'));

    const isAuthenticated = computed(() => !!user.value);

    async function login(email: string, password: string) {
        const response = await authService.login(email, password);
        user.value = response.user;
        token.value = response.token;
        localStorage.setItem('token', response.token);
    }

    function logout() {
        user.value = null;
        token.value = null;
        localStorage.removeItem('token');
    }

    return { user, token, isAuthenticated, login, logout };
});
```

### API Service Layer

```typescript
// services/userService.ts
import axios from 'axios';
import { useAuthStore } from '@/stores/auth';

const api = axios.create({
    baseURL: '/api',
    headers: { 'Content-Type': 'application/json' }
});

api.interceptors.request.use(config => {
    const authStore = useAuthStore();
    if (authStore.token) {
        config.headers.Authorization = `Bearer ${authStore.token}`;
    }
    return config;
});

api.interceptors.response.use(
    response => response,
    error => {
        if (error.response?.status === 401) {
            const authStore = useAuthStore();
            authStore.logout();
        }
        return Promise.reject(error);
    }
);

export const userService = {
    async getById(id: string): Promise<User> {
        const response = await api.get(`/users/${id}`);
        return response.data;
    },

    async create(userData: CreateUserRequest): Promise<User> {
        const response = await api.post('/users', userData);
        return response.data;
    },

    async update(id: string, userData: Partial<User>): Promise<User> {
        const response = await api.put(`/users/${id}`, userData);
        return response.data;
    },

    async delete(id: string): Promise<void> {
        await api.delete(`/users/${id}`);
    }
};
```

### Cross-Cutting Concerns

#### Error Handler Plugin

```typescript
// plugins/errorHandler.ts
import { App } from 'vue';

export default {
    install(app: App) {
        app.config.errorHandler = (err, instance, info) => {
            console.error('Global error:', err, info);
            // Send to logging service
        };
    }
};
```

#### Router Guard (Authentication)

```typescript
// router/index.ts
import { createRouter, createWebHistory } from 'vue-router';
import { useAuthStore } from '@/stores/auth';

const router = createRouter({
    history: createWebHistory(),
    routes: [
        {
            path: '/dashboard',
            component: () => import('@/views/Dashboard.vue'),
            meta: { requiresAuth: true }
        },
        {
            path: '/login',
            component: () => import('@/views/Login.vue')
        }
    ]
});

router.beforeEach((to, from, next) => {
    const authStore = useAuthStore();

    if (to.meta.requiresAuth && !authStore.isAuthenticated) {
        next('/login');
    } else {
        next();
    }
});

export default router;
```

#### Logging Composable

```typescript
// composables/useLogger.ts
import { onMounted, onUnmounted } from 'vue';

export function useLogger(componentName: string) {
    onMounted(() => {
        console.log(`[${componentName}] mounted`);
    });

    onUnmounted(() => {
        console.log(`[${componentName}] unmounted`);
    });

    return {
        logEvent(eventName: string, data?: any) {
            console.log(`[${componentName}] ${eventName}`, data);
            // Send to analytics
        }
    };
}
```

### Testing

**Component Test (Vue Test Utils):**
```typescript
// __tests__/UserCard.spec.ts
import { mount } from '@vue/test-utils';
import UserCard from '@/components/UserCard.vue';

describe('UserCard', () => {
    const mockUser = { id: 1, name: 'Test User', email: 'test@example.com' };

    test('renders user information', () => {
        const wrapper = mount(UserCard, {
            props: { user: mockUser }
        });

        expect(wrapper.text()).toContain('Test User');
        expect(wrapper.text()).toContain('test@example.com');
    });

    test('emits edit event when button clicked', async () => {
        const wrapper = mount(UserCard, {
            props: { user: mockUser }
        });

        await wrapper.find('button').trigger('click');

        expect(wrapper.emitted('edit')).toBeTruthy();
        expect(wrapper.emitted('edit')![0]).toEqual([1]);
    });
});
```

**Composable Test:**
```typescript
// __tests__/useUser.spec.ts
import { mount } from '@vue/test-utils';
import { useUser } from '@/composables/useUser';
import { userService } from '@/services/userService';

jest.mock('@/services/userService');

describe('useUser', () => {
    test('fetches user successfully', async () => {
        const mockUser = { id: 1, name: 'Test', email: 'test@example.com' };
        (userService.getById as jest.Mock).mockResolvedValue(mockUser);

        let result: any;
        const TestComponent = {
            setup() {
                result = useUser('1');
                return {};
            },
            template: '<div></div>'
        };

        mount(TestComponent);

        await new Promise(resolve => setTimeout(resolve, 0));

        expect(result.loading.value).toBe(false);
        expect(result.user.value).toEqual(mockUser);
    });
});
```

---

## Common Frontend Patterns

### Container/Presentation Pattern
- Container: manages state, data fetching, business logic
- Presentation: pure UI, receives props, emits events

### Custom Hooks/Composables Pattern
- Extract reusable logic
- Combine multiple hooks for complex behavior
- Share stateful logic across components

### Service Layer Pattern
- Centralize API calls
- Consistent error handling
- Interceptors for auth, logging

### Provider Pattern (Context/Store)
- Share state across component tree
- Avoid prop drilling
- Global user, theme, localization

### HOC/Plugin Pattern
- Wrap components with additional behavior
- Auth guards, logging, analytics
- Cross-cutting concerns

### Render Props Pattern (React)
- Share code via function props
- More flexible than HOCs
- Use sparingly; hooks often better

### Compound Components Pattern
- Components work together (e.g., Tabs + Tab)
- Share implicit state
- Flexible API for consumers
