# Vue Frontend Examples

> Secondary reference notice: This document is a deprecated secondary reference inside `codeguide`. Do not use it as the primary source for framework setup or API details. Prefer official documentation and repository-specific conventions first.

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
