# Frontend Examples - React (JavaScript)

## Project Setup with Vite

**Create New Project:**
```bash
# Using npm
npm create vite@latest my-app -- --template react

# Using yarn
yarn create vite my-app --template react

# Using pnpm
pnpm create vite my-app --template react

cd my-app
npm install
npm run dev  # Start dev server at http://localhost:5173
```

**Project Structure:**
```
my-app/
├── public/          # Static assets
├── src/
│   ├── assets/      # Images, fonts, etc.
│   ├── components/  # React components
│   ├── hooks/       # Custom hooks
│   ├── services/    # API clients
│   ├── utils/       # Utilities
│   ├── App.jsx      # Main app component
│   └── main.jsx     # Entry point
├── index.html       # HTML template
├── vite.config.js   # Vite configuration
└── package.json
```

**Vite Configuration (vite.config.js):**
```javascript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],

  // Path aliases
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@components': path.resolve(__dirname, './src/components'),
      '@hooks': path.resolve(__dirname, './src/hooks'),
      '@services': path.resolve(__dirname, './src/services'),
      '@utils': path.resolve(__dirname, './src/utils')
    }
  },

  // Dev server
  server: {
    port: 3000,
    open: true,  // Auto-open browser
    proxy: {
      // Proxy API requests during development
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true
      }
    }
  },

  // Build options
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

**package.json Scripts:**
```json
{
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "lint": "eslint src --ext js,jsx"
  }
}
```

**Using Path Aliases:**
```javascript
// Instead of: import Button from '../../../components/Button'
import Button from '@components/Button';
import { useUser } from '@hooks/useUser';
import { userService } from '@services/userService';
```

**Environment Variables:**
```bash
# .env.development
VITE_API_URL=http://localhost:8080/api
VITE_APP_TITLE=My App (Dev)

# .env.production
VITE_API_URL=https://api.production.com
VITE_APP_TITLE=My App
```

```javascript
// Access in code (must prefix with VITE_)
const apiUrl = import.meta.env.VITE_API_URL;
const appTitle = import.meta.env.VITE_APP_TITLE;
const isDev = import.meta.env.DEV;
const isProd = import.meta.env.PROD;
```

**Hot Module Replacement (HMR):**
- Vite provides instant HMR out of the box
- Changes reflect immediately without full page reload
- React state is preserved during updates

**Build for Production:**
```bash
npm run build        # Creates optimized build in dist/
npm run preview      # Preview production build locally
```

## Component Patterns

### Presentation Component
```javascript
// components/UserCard.jsx
export function UserCard({ user, onEdit, onDelete }) {
    return (
        <div className="user-card">
            <div className="user-info">
                <h3>{user.name}</h3>
                <p>{user.email}</p>
                <span className="user-role">{user.role}</span>
            </div>
            <div className="user-actions">
                <button onClick={() => onEdit(user.id)} className="btn-edit">
                    Edit
                </button>
                <button onClick={() => onDelete(user.id)} className="btn-delete">
                    Delete
                </button>
            </div>
        </div>
    );
}
```

### Container Component with Custom Hook
```javascript
// hooks/useUser.js
import { useState, useEffect } from 'react';
import { userService } from '../services/userService';

export function useUser(id) {
    const [user, setUser] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        let cancelled = false;

        async function fetchUser() {
            try {
                setLoading(true);
                setError(null);
                const data = await userService.getById(id);

                if (!cancelled) {
                    setUser(data);
                }
            } catch (err) {
                if (!cancelled) {
                    setError(err);
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

    const refetch = useCallback(() => {
        setLoading(true);
        userService.getById(id)
            .then(setUser)
            .catch(setError)
            .finally(() => setLoading(false));
    }, [id]);

    return { user, loading, error, refetch };
}

// pages/UserProfile.jsx
import { useParams, useNavigate } from 'react-router-dom';
import { useUser } from '../hooks/useUser';
import { UserCard } from '../components/UserCard';

export function UserProfile() {
    const { id } = useParams();
    const navigate = useNavigate();
    const { user, loading, error, refetch } = useUser(id);

    const handleEdit = (userId) => {
        navigate(`/users/${userId}/edit`);
    };

    const handleDelete = async (userId) => {
        if (confirm('Are you sure?')) {
            await userService.delete(userId);
            navigate('/users');
        }
    };

    if (loading) return <Spinner />;
    if (error) return <ErrorMessage error={error} />;
    if (!user) return <NotFound />;

    return (
        <div>
            <h1>User Profile</h1>
            <UserCard
                user={user}
                onEdit={handleEdit}
                onDelete={handleDelete}
            />
        </div>
    );
}
```

## Performance Hooks

### useMemo (Memoize Expensive Calculations)
```javascript
import { useMemo } from 'react';

function ProductList({ products, filterCategory, sortBy }) {
    // Expensive filtering and sorting - only recalculate when dependencies change
    const filteredAndSortedProducts = useMemo(() => {
        console.log('Recalculating filtered products...');

        let result = products;

        // Filter by category
        if (filterCategory) {
            result = result.filter(p => p.category === filterCategory);
        }

        // Sort
        result = [...result].sort((a, b) => {
            if (sortBy === 'price') return a.price - b.price;
            if (sortBy === 'name') return a.name.localeCompare(b.name);
            return 0;
        });

        return result;
    }, [products, filterCategory, sortBy]); // Only recalculate when these change

    return (
        <div>
            {filteredAndSortedProducts.map(product => (
                <ProductCard key={product.id} product={product} />
            ))}
        </div>
    );
}

// Without useMemo: recalculates on every render
// With useMemo: only recalculates when dependencies change
```

**When to use useMemo:**
- Expensive calculations (filtering large arrays, complex computations)
- Preventing unnecessary re-renders of child components
- Deriving data from props/state

**When NOT to use:**
- Simple calculations (addition, string concatenation)
- Values that change on every render anyway
- Premature optimization

### useCallback (Memoize Functions)
```javascript
import { useCallback, memo } from 'react';

function TodoList({ todos }) {
    const [filter, setFilter] = useState('all');

    // Without useCallback: creates new function on every render
    // With useCallback: returns same function reference unless dependencies change
    const handleToggle = useCallback((id) => {
        todoService.toggle(id).then(refetch);
    }, []); // Empty deps = function never changes

    const handleDelete = useCallback((id) => {
        todoService.delete(id).then(refetch);
    }, []);

    const handleFilter = useCallback((newFilter) => {
        setFilter(newFilter);
    }, []); // setFilter is stable, no need to include

    const filteredTodos = useMemo(() => {
        if (filter === 'all') return todos;
        if (filter === 'active') return todos.filter(t => !t.completed);
        if (filter === 'completed') return todos.filter(t => t.completed);
    }, [todos, filter]);

    return (
        <div>
            <FilterButtons onFilter={handleFilter} />
            {filteredTodos.map(todo => (
                <TodoItem
                    key={todo.id}
                    todo={todo}
                    onToggle={handleToggle}
                    onDelete={handleDelete}
                />
            ))}
        </div>
    );
}

// TodoItem is memoized - only re-renders if props change
const TodoItem = memo(({ todo, onToggle, onDelete }) => {
    console.log('Rendering TodoItem', todo.id);

    return (
        <div className="todo-item">
            <input
                type="checkbox"
                checked={todo.completed}
                onChange={() => onToggle(todo.id)}
            />
            <span>{todo.text}</span>
            <button onClick={() => onDelete(todo.id)}>Delete</button>
        </div>
    );
});
```

**When to use useCallback:**
- Passing callbacks to memoized child components
- Dependencies for useEffect/useMemo
- Event handlers passed to many child components

**When NOT to use:**
- Callbacks only used in current component
- Child components aren't memoized
- Function doesn't cause performance issues

### useRef (Persist Values Without Re-rendering)
```javascript
import { useRef, useEffect } from 'react';

// Use case 1: Accessing DOM elements
function AutoFocusInput() {
    const inputRef = useRef(null);

    useEffect(() => {
        // Focus input on mount
        inputRef.current?.focus();
    }, []);

    return <input ref={inputRef} type="text" />;
}

// Use case 2: Storing mutable values without causing re-render
function Timer() {
    const [count, setCount] = useState(0);
    const intervalRef = useRef(null);

    const startTimer = () => {
        if (intervalRef.current) return; // Already running

        intervalRef.current = setInterval(() => {
            setCount(c => c + 1);
        }, 1000);
    };

    const stopTimer = () => {
        if (intervalRef.current) {
            clearInterval(intervalRef.current);
            intervalRef.current = null;
        }
    };

    useEffect(() => {
        return () => stopTimer(); // Cleanup on unmount
    }, []);

    return (
        <div>
            <p>Count: {count}</p>
            <button onClick={startTimer}>Start</button>
            <button onClick={stopTimer}>Stop</button>
        </div>
    );
}

// Use case 3: Tracking previous values
function usePrevious(value) {
    const ref = useRef();

    useEffect(() => {
        ref.current = value;
    }, [value]);

    return ref.current;
}

function UserProfile({ userId }) {
    const [user, setUser] = useState(null);
    const previousUserId = usePrevious(userId);

    useEffect(() => {
        if (userId !== previousUserId) {
            console.log(`User changed from ${previousUserId} to ${userId}`);
            fetchUser(userId).then(setUser);
        }
    }, [userId, previousUserId]);

    return <div>{user?.name}</div>;
}

// Use case 4: Avoiding stale closures in callbacks
function SearchInput() {
    const [query, setQuery] = useState('');
    const queryRef = useRef(query);

    useEffect(() => {
        queryRef.current = query; // Keep ref in sync
    }, [query]);

    useEffect(() => {
        const handleGlobalSearch = (e) => {
            if (e.key === '/') {
                // Always has latest query value, even if event handler is old
                console.log('Current search:', queryRef.current);
            }
        };

        document.addEventListener('keydown', handleGlobalSearch);
        return () => document.removeEventListener('keydown', handleGlobalSearch);
    }, []); // Empty deps - handler only created once

    return (
        <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
        />
    );
}
```

**When to use useRef:**
- Accessing DOM elements directly
- Storing mutable values that don't trigger re-renders (timers, subscriptions)
- Tracking previous values
- Avoiding stale closures

**When NOT to use:**
- Storing state that should trigger re-renders (use useState instead)
- Values that should be part of component's render output

### Combined Example: Optimized Data Table
```javascript
import { useState, useMemo, useCallback, useRef, memo } from 'react';

function DataTable({ data }) {
    const [sortColumn, setSortColumn] = useState('name');
    const [sortDirection, setSortDirection] = useState('asc');
    const [searchQuery, setSearchQuery] = useState('');
    const searchInputRef = useRef(null);

    // Memoize filtered and sorted data
    const processedData = useMemo(() => {
        console.log('Processing data...');

        let result = data;

        // Filter
        if (searchQuery) {
            result = result.filter(item =>
                item.name.toLowerCase().includes(searchQuery.toLowerCase())
            );
        }

        // Sort
        result = [...result].sort((a, b) => {
            const aVal = a[sortColumn];
            const bVal = b[sortColumn];
            const modifier = sortDirection === 'asc' ? 1 : -1;

            if (typeof aVal === 'string') {
                return aVal.localeCompare(bVal) * modifier;
            }
            return (aVal - bVal) * modifier;
        });

        return result;
    }, [data, sortColumn, sortDirection, searchQuery]);

    // Memoize callbacks
    const handleSort = useCallback((column) => {
        if (sortColumn === column) {
            setSortDirection(dir => dir === 'asc' ? 'desc' : 'asc');
        } else {
            setSortColumn(column);
            setSortDirection('asc');
        }
    }, [sortColumn]);

    const handleSearch = useCallback((e) => {
        setSearchQuery(e.target.value);
    }, []);

    const clearSearch = useCallback(() => {
        setSearchQuery('');
        searchInputRef.current?.focus();
    }, []);

    return (
        <div>
            <div className="search-bar">
                <input
                    ref={searchInputRef}
                    type="text"
                    value={searchQuery}
                    onChange={handleSearch}
                    placeholder="Search..."
                />
                {searchQuery && (
                    <button onClick={clearSearch}>Clear</button>
                )}
            </div>

            <table>
                <TableHeader
                    sortColumn={sortColumn}
                    sortDirection={sortDirection}
                    onSort={handleSort}
                />
                <tbody>
                    {processedData.map(item => (
                        <TableRow key={item.id} item={item} />
                    ))}
                </tbody>
            </table>
        </div>
    );
}

const TableHeader = memo(({ sortColumn, sortDirection, onSort }) => (
    <thead>
        <tr>
            <th onClick={() => onSort('name')}>
                Name {sortColumn === 'name' && (sortDirection === 'asc' ? '↑' : '↓')}
            </th>
            <th onClick={() => onSort('age')}>
                Age {sortColumn === 'age' && (sortDirection === 'asc' ? '↑' : '↓')}
            </th>
        </tr>
    </thead>
));

const TableRow = memo(({ item }) => {
    console.log('Rendering row', item.id);

    return (
        <tr>
            <td>{item.name}</td>
            <td>{item.age}</td>
        </tr>
    );
});
```

## State Management

### useState (Simple State)
```javascript
function Counter() {
    const [count, setCount] = useState(0);

    return (
        <div>
            <p>Count: {count}</p>
            <button onClick={() => setCount(count + 1)}>Increment</button>
            <button onClick={() => setCount(count - 1)}>Decrement</button>
            <button onClick={() => setCount(0)}>Reset</button>
        </div>
    );
}
```

### useReducer (Complex State)
```javascript
const initialState = {
    items: [],
    loading: false,
    error: null,
    filter: 'all'
};

function reducer(state, action) {
    switch (action.type) {
        case 'FETCH_START':
            return { ...state, loading: true, error: null };

        case 'FETCH_SUCCESS':
            return { ...state, loading: false, items: action.payload };

        case 'FETCH_ERROR':
            return { ...state, loading: false, error: action.error };

        case 'ADD_ITEM':
            return { ...state, items: [...state.items, action.item] };

        case 'REMOVE_ITEM':
            return {
                ...state,
                items: state.items.filter(item => item.id !== action.id)
            };

        case 'UPDATE_ITEM':
            return {
                ...state,
                items: state.items.map(item =>
                    item.id === action.id ? { ...item, ...action.updates } : item
                )
            };

        case 'SET_FILTER':
            return { ...state, filter: action.filter };

        default:
            return state;
    }
}

function ItemList() {
    const [state, dispatch] = useReducer(reducer, initialState);

    useEffect(() => {
        dispatch({ type: 'FETCH_START' });
        itemService.getAll()
            .then(items => dispatch({ type: 'FETCH_SUCCESS', payload: items }))
            .catch(error => dispatch({ type: 'FETCH_ERROR', error: error.message }));
    }, []);

    const addItem = (item) => dispatch({ type: 'ADD_ITEM', item });
    const removeItem = (id) => dispatch({ type: 'REMOVE_ITEM', id });
    const updateItem = (id, updates) => dispatch({ type: 'UPDATE_ITEM', id, updates });
    const setFilter = (filter) => dispatch({ type: 'SET_FILTER', filter });

    const filteredItems = state.items.filter(item => {
        if (state.filter === 'all') return true;
        if (state.filter === 'active') return !item.completed;
        if (state.filter === 'completed') return item.completed;
        return true;
    });

    if (state.loading) return <Spinner />;
    if (state.error) return <Error message={state.error} />;

    return (
        <div>
            <FilterButtons filter={state.filter} setFilter={setFilter} />
            {filteredItems.map(item => (
                <Item
                    key={item.id}
                    data={item}
                    onUpdate={updateItem}
                    onRemove={removeItem}
                />
            ))}
        </div>
    );
}
```

### Context API (Global State)
```javascript
// contexts/AuthContext.jsx
import { createContext, useContext, useState, useEffect } from 'react';
import { authService } from '../services/authService';

const AuthContext = createContext();

export function AuthProvider({ children }) {
    const [user, setUser] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        // Check if user is already logged in
        const token = authService.getToken();
        if (token && authService.isAuthenticated()) {
            authService.getCurrentUser()
                .then(setUser)
                .catch(() => authService.logout())
                .finally(() => setLoading(false));
        } else {
            setLoading(false);
        }
    }, []);

    const login = async (email, password) => {
        const { token, user } = await authService.login(email, password);
        setUser(user);
    };

    const logout = () => {
        authService.logout();
        setUser(null);
    };

    const updateProfile = async (updates) => {
        const updated = await authService.updateProfile(updates);
        setUser(updated);
    };

    if (loading) return <Spinner />;

    return (
        <AuthContext.Provider value={{ user, login, logout, updateProfile }}>
            {children}
        </AuthContext.Provider>
    );
}

export const useAuth = () => {
    const context = useContext(AuthContext);
    if (!context) {
        throw new Error('useAuth must be used within AuthProvider');
    }
    return context;
};

// App.jsx
function App() {
    return (
        <AuthProvider>
            <Router>
                <Routes>
                    <Route path="/login" element={<Login />} />
                    <Route path="/dashboard" element={<Dashboard />} />
                </Routes>
            </Router>
        </AuthProvider>
    );
}
```

### Zustand (Recommended for Complex Apps)
```javascript
// stores/authStore.js
import { create } from 'zustand';
import { authService } from '../services/authService';

export const useAuthStore = create((set, get) => ({
    user: null,
    token: localStorage.getItem('token'),
    loading: false,
    error: null,

    login: async (email, password) => {
        set({ loading: true, error: null });
        try {
            const { token, user } = await authService.login(email, password);
            set({ user, token, loading: false });
            localStorage.setItem('token', token);
        } catch (error) {
            set({ error: error.message, loading: false });
            throw error;
        }
    },

    logout: () => {
        set({ user: null, token: null });
        localStorage.removeItem('token');
    },

    updateProfile: async (updates) => {
        const user = get().user;
        if (!user) throw new Error('No user logged in');

        set({ loading: true });
        try {
            const updated = await authService.updateProfile(updates);
            set({ user: updated, loading: false });
        } catch (error) {
            set({ error: error.message, loading: false });
            throw error;
        }
    },

    setUser: (user) => set({ user })
}));

// Usage in component
function Profile() {
    const { user, logout, updateProfile, loading } = useAuthStore();

    const handleUpdate = async (data) => {
        await updateProfile(data);
    };

    if (loading) return <Spinner />;

    return (
        <div>
            <h1>{user.name}</h1>
            <button onClick={logout}>Logout</button>
            <ProfileForm user={user} onSubmit={handleUpdate} />
        </div>
    );
}
```

## API Service Layer

```javascript
// services/apiClient.js
import axios from 'axios';

const api = axios.create({
    baseURL: '/api',
    headers: {
        'Content-Type': 'application/json'
    },
    timeout: 10000
});

// Request interceptor - add auth token
api.interceptors.request.use(
    (config) => {
        const token = localStorage.getItem('token');
        if (token) {
            config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
    },
    (error) => Promise.reject(error)
);

// Response interceptor - handle errors
api.interceptors.response.use(
    (response) => response,
    async (error) => {
        const originalRequest = error.config;

        // Handle 401 - Unauthorized
        if (error.response?.status === 401 && !originalRequest._retry) {
            originalRequest._retry = true;

            const refreshToken = localStorage.getItem('refreshToken');
            if (refreshToken) {
                try {
                    const { token } = await authService.refresh(refreshToken);
                    localStorage.setItem('token', token);
                    originalRequest.headers.Authorization = `Bearer ${token}`;
                    return api(originalRequest);
                } catch {
                    localStorage.removeItem('token');
                    localStorage.removeItem('refreshToken');
                    window.location.href = '/login';
                }
            } else {
                window.location.href = '/login';
            }
        }

        // Handle 403 - Forbidden
        if (error.response?.status === 403) {
            window.location.href = '/forbidden';
        }

        return Promise.reject(error);
    }
);

export default api;

// services/userService.js
import api from './apiClient';

export const userService = {
    getAll: () => api.get('/users').then(res => res.data),

    getById: (id) => api.get(`/users/${id}`).then(res => res.data),

    create: (data) => api.post('/users', data).then(res => res.data),

    update: (id, data) => api.put(`/users/${id}`, data).then(res => res.data),

    delete: (id) => api.delete(`/users/${id}`).then(res => res.data),

    search: (query) => api.get('/users/search', { params: { q: query } }).then(res => res.data)
};
```

## Cross-Cutting Concerns

### Error Handling Hook
```javascript
// hooks/useApiError.js
import { useNotification } from './useNotification';

export function useApiError() {
    const { showNotification } = useNotification();

    return {
        handle(error) {
            const apiError = error.response?.data;

            if (!apiError) {
                showNotification('Network error. Please try again.', 'error');
                return;
            }

            switch (apiError.code) {
                case 'NOT_FOUND':
                    showNotification('Resource not found', 'error');
                    break;

                case 'VALIDATION_ERROR':
                    showNotification('Invalid input', 'error');
                    return apiError.details; // Return field errors

                case 'UNAUTHORIZED':
                    showNotification('Please log in', 'error');
                    window.location.href = '/login';
                    break;

                case 'FORBIDDEN':
                    showNotification('Access denied', 'error');
                    break;

                default:
                    showNotification(apiError.message || 'An error occurred', 'error');
            }
        }
    };
}

// Usage in component
function UserForm() {
    const { handle } = useApiError();
    const [errors, setErrors] = useState({});

    const handleSubmit = async (data) => {
        try {
            await userService.create(data);
            navigate('/users');
        } catch (error) {
            const fieldErrors = handle(error);
            if (fieldErrors) {
                setErrors(fieldErrors);
            }
        }
    };

    return <form onSubmit={handleSubmit}>...</form>;
}
```

### HOC for Authentication
```javascript
// hocs/withAuth.jsx
import { useAuth } from '../contexts/AuthContext';
import { Navigate } from 'react-router-dom';

export function withAuth(Component, options = {}) {
    return function AuthenticatedComponent(props) {
        const { user } = useAuth();
        const { requireRole } = options;

        if (!user) {
            return <Navigate to="/login" replace />;
        }

        if (requireRole && !user.roles.includes(requireRole)) {
            return <Navigate to="/forbidden" replace />;
        }

        return <Component {...props} />;
    };
}

// Usage
const AdminDashboard = withAuth(Dashboard, { requireRole: 'ADMIN' });
const UserProfile = withAuth(Profile);
```

### Error Boundary
```javascript
// components/ErrorBoundary.jsx
import React from 'react';

export class ErrorBoundary extends React.Component {
    constructor(props) {
        super(props);
        this.state = { hasError: false, error: null };
    }

    static getDerivedStateFromError(error) {
        return { hasError: true, error };
    }

    componentDidCatch(error, errorInfo) {
        console.error('ErrorBoundary caught:', error, errorInfo);
        // Send to logging service (e.g., Sentry)
        if (window.Sentry) {
            window.Sentry.captureException(error, { extra: errorInfo });
        }
    }

    render() {
        if (this.state.hasError) {
            return (
                this.props.fallback || (
                    <div className="error-page">
                        <h1>Something went wrong</h1>
                        <p>{this.state.error?.message}</p>
                        <button onClick={() => window.location.reload()}>
                            Reload Page
                        </button>
                    </div>
                )
            );
        }

        return this.props.children;
    }
}

// Usage
function App() {
    return (
        <ErrorBoundary>
            <Router>
                <Routes>...</Routes>
            </Router>
        </ErrorBoundary>
    );
}
```

## Testing

### Component Test
```javascript
// __tests__/UserCard.test.jsx
import { render, screen, fireEvent } from '@testing-library/react';
import { UserCard } from '../components/UserCard';

describe('UserCard', () => {
    const mockUser = {
        id: 1,
        name: 'Test User',
        email: 'test@example.com',
        role: 'USER'
    };

    test('renders user information', () => {
        const onEdit = jest.fn();
        const onDelete = jest.fn();

        render(<UserCard user={mockUser} onEdit={onEdit} onDelete={onDelete} />);

        expect(screen.getByText('Test User')).toBeInTheDocument();
        expect(screen.getByText('test@example.com')).toBeInTheDocument();
        expect(screen.getByText('USER')).toBeInTheDocument();
    });

    test('calls onEdit when edit button clicked', () => {
        const onEdit = jest.fn();
        const onDelete = jest.fn();

        render(<UserCard user={mockUser} onEdit={onEdit} onDelete={onDelete} />);

        fireEvent.click(screen.getByText('Edit'));

        expect(onEdit).toHaveBeenCalledWith(1);
        expect(onDelete).not.toHaveBeenCalled();
    });

    test('calls onDelete when delete button clicked', () => {
        const onEdit = jest.fn();
        const onDelete = jest.fn();

        render(<UserCard user={mockUser} onEdit={onEdit} onDelete={onDelete} />);

        fireEvent.click(screen.getByText('Delete'));

        expect(onDelete).toHaveBeenCalledWith(1);
        expect(onEdit).not.toHaveBeenCalled();
    });
});
```

### Hook Test
```javascript
// __tests__/useUser.test.js
import { renderHook, waitFor } from '@testing-library/react';
import { useUser } from '../hooks/useUser';
import { userService } from '../services/userService';

jest.mock('../services/userService');

describe('useUser', () => {
    test('fetches user successfully', async () => {
        const mockUser = { id: 1, name: 'Test', email: 'test@example.com' };
        userService.getById.mockResolvedValue(mockUser);

        const { result } = renderHook(() => useUser('1'));

        expect(result.current.loading).toBe(true);

        await waitFor(() => {
            expect(result.current.loading).toBe(false);
        });

        expect(result.current.user).toEqual(mockUser);
        expect(result.current.error).toBeNull();
    });

    test('handles error when fetch fails', async () => {
        const mockError = new Error('Not found');
        userService.getById.mockRejectedValue(mockError);

        const { result } = renderHook(() => useUser('999'));

        await waitFor(() => {
            expect(result.current.loading).toBe(false);
        });

        expect(result.current.user).toBeNull();
        expect(result.current.error).toEqual(mockError);
    });
});
```

### Integration Test (E2E)
```javascript
// e2e/userProfile.spec.js (Playwright)
import { test, expect } from '@playwright/test';

test.describe('User Profile', () => {
    test.beforeEach(async ({ page }) => {
        // Login first
        await page.goto('/login');
        await page.fill('input[name="email"]', 'test@example.com');
        await page.fill('input[name="password"]', 'password123');
        await page.click('button[type="submit"]');
        await page.waitForURL('/dashboard');
    });

    test('displays user information', async ({ page }) => {
        await page.goto('/users/1');

        await expect(page.locator('h3')).toContainText('Test User');
        await expect(page.locator('p')).toContainText('test@example.com');
    });

    test('navigates to edit page when edit clicked', async ({ page }) => {
        await page.goto('/users/1');

        await page.click('button:has-text("Edit")');

        await expect(page).toHaveURL('/users/1/edit');
    });

    test('deletes user after confirmation', async ({ page }) => {
        await page.goto('/users/1');

        page.on('dialog', dialog => dialog.accept());
        await page.click('button:has-text("Delete")');

        await expect(page).toHaveURL('/users');
    });
});
```
