# Frontend Examples - React (TypeScript)

> Secondary reference notice: This document is a deprecated secondary reference inside `codeguide`. Do not use it as the primary source for framework setup or API details. Prefer dedicated framework skills, official documentation, and repository-specific conventions first.

## Project Setup with Vite

**Create New Project:**
```bash
# Using npm
npm create vite@latest my-app -- --template react-ts

# Using yarn
yarn create vite my-app --template react-ts

# Using pnpm
pnpm create vite my-app --template react-ts

cd my-app
npm install
npm run dev  # Start dev server at http://localhost:5173
```

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

## Vite Configuration

**vite.config.ts:**
```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],

  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@components': path.resolve(__dirname, './src/components'),
      '@hooks': path.resolve(__dirname, './src/hooks'),
      '@services': path.resolve(__dirname, './src/services'),
      '@utils': path.resolve(__dirname, './src/utils'),
      '@types': path.resolve(__dirname, './src/types')
    }
  },

  server: {
    port: 3000,
    open: true,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true
      }
    }
  },

  build: {
    outDir: 'dist',
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', 'react-router-dom'],
          axios: ['axios']
        }
      }
    }
  }
});
```

**tsconfig.json (Path Aliases):**
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "jsx": "react-jsx",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"],
      "@components/*": ["./src/components/*"],
      "@hooks/*": ["./src/hooks/*"],
      "@services/*": ["./src/services/*"],
      "@utils/*": ["./src/utils/*"],
      "@types/*": ["./src/types/*"]
    }
  }
}
```

**Environment Variables:**
```typescript
// src/vite-env.d.ts
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL: string;
  readonly VITE_APP_TITLE: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

// Usage
const apiUrl = import.meta.env.VITE_API_URL;
const appTitle = import.meta.env.VITE_APP_TITLE;
```

## Performance Hooks

### useMemo
```typescript
import { useMemo } from 'react';

interface Product {
  id: number;
  name: string;
  price: number;
  category: string;
}

function ProductList({ products, filterCategory, sortBy }: {
  products: Product[];
  filterCategory?: string;
  sortBy?: 'price' | 'name';
}) {
  const filteredAndSortedProducts = useMemo(() => {
    let result = products;

    if (filterCategory) {
      result = result.filter(p => p.category === filterCategory);
    }

    return [...result].sort((a, b) => {
      if (sortBy === 'price') return a.price - b.price;
      if (sortBy === 'name') return a.name.localeCompare(b.name);
      return 0;
    });
  }, [products, filterCategory, sortBy]);

  return (
    <div>
      {filteredAndSortedProducts.map(product => (
        <ProductCard key={product.id} product={product} />
      ))}
    </div>
  );
}
```

### useCallback
```typescript
import { useCallback, memo } from 'react';

const TodoItem = memo<{ todo: Todo; onToggle: (id: number) => void }>(
  ({ todo, onToggle }) => (
    <div>
      <input
        type="checkbox"
        checked={todo.completed}
        onChange={() => onToggle(todo.id)}
      />
      <span>{todo.text}</span>
    </div>
  )
);

function TodoList() {
  const [todos, setTodos] = useState<Todo[]>([]);

  const handleToggle = useCallback((id: number) => {
    setTodos(prev => prev.map(t =>
      t.id === id ? { ...t, completed: !t.completed } : t
    ));
  }, []);

  return (
    <div>
      {todos.map(todo => (
        <TodoItem key={todo.id} todo={todo} onToggle={handleToggle} />
      ))}
    </div>
  );
}
```

### useRef
```typescript
import { useRef, useEffect } from 'react';

function AutoFocusInput() {
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  return <input ref={inputRef} type="text" />;
}

function Timer() {
  const [count, setCount] = useState(0);
  const intervalRef = useRef<number | null>(null);

  const startTimer = () => {
    if (intervalRef.current !== null) return;
    intervalRef.current = window.setInterval(() => {
      setCount(c => c + 1);
    }, 1000);
  };

  const stopTimer = () => {
    if (intervalRef.current !== null) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
  };

  return (
    <div>
      <p>Count: {count}</p>
      <button onClick={startTimer}>Start</button>
      <button onClick={stopTimer}>Stop</button>
    </div>
  );
}
```

## Zustand (TypeScript)

```typescript
// stores/authStore.ts
import { create } from 'zustand';

interface User {
  id: number;
  email: string;
  name: string;
  roles: string[];
}

interface AuthState {
  user: User | null;
  token: string | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  setUser: (user: User | null) => void;
}

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  token: localStorage.getItem('token'),
  loading: false,

  login: async (email, password) => {
    set({ loading: true });
    try {
      const { token, user } = await authService.login(email, password);
      set({ user, token, loading: false });
      localStorage.setItem('token', token);
    } catch (error) {
      set({ loading: false });
      throw error;
    }
  },

  logout: () => {
    set({ user: null, token: null });
    localStorage.removeItem('token');
  },

  setUser: (user) => set({ user })
}));

// Usage
function Profile() {
  const { user, logout } = useAuthStore();
  return <div>{user?.name} <button onClick={logout}>Logout</button></div>;
}

// Optimized - only re-renders when name changes
function UserBadge() {
  const userName = useAuthStore(state => state.user?.name);
  return <div>{userName}</div>;
}
```
