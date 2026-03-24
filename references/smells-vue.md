# Smells - Vue

## Good smells (do)
- Use computed for derived state.
- Use composables for reusable logic.
- Keep templates declarative; move logic to script.
- Validate props and emit typed events.
- Keep side effects in watchers or lifecycle hooks.
- Provide stable keys in v-for.

## Bad smells (avoid)
- Complex logic in templates.
- Mutating props directly.
- Overusing watchers for derived state.
- Global mutable state without store boundaries.
- Using index as key in v-for.
- Mixing composition and options APIs in the same file.

## Do vs Don't (code)

```vue
<!-- Don't: heavy logic in template -->
<template>
  <div>{{ items.filter(i => i.active).reduce((s, i) => s + i.price, 0) }}</div>
</template>

<!-- Do: computed in script -->
<script setup>
import { computed } from 'vue'
const props = defineProps({ items: Array })
const total = computed(() => props.items.filter(i => i.active).reduce((s, i) => s + i.price, 0))
</script>
<template>
  <div>{{ total }}</div>
</template>
```

```vue
<!-- Don't: mutate prop -->
<script setup>
const props = defineProps({ modelValue: String })
props.modelValue = props.modelValue.trim()
</script>

<!-- Do: emit update -->
<script setup>
const props = defineProps({ modelValue: String })
const emit = defineEmits(['update:modelValue'])
const update = (value) => emit('update:modelValue', value.trim())
</script>
```

```vue
<!-- Don't: index key -->
<template>
  <li v-for="(item, index) in items" :key="index">{{ item.name }}</li>
</template>

<!-- Do: stable key -->
<template>
  <li v-for="item in items" :key="item.id">{{ item.name }}</li>
</template>
```
