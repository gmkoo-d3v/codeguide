# Tailwind CSS with React

> Secondary reference notice: This document is a deprecated secondary reference inside `codeguide`. Do not use it as the primary source for framework setup or API details. Prefer dedicated framework skills, official documentation, and repository-specific conventions first.

## Installation

**With Vite:**
```bash
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
```

**Configure tailwind.config.js:**
```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

**Add Tailwind directives to CSS:**
```css
/* src/index.css */
@tailwind base;
@tailwind components;
@tailwind utilities;
```

**Import CSS in main.jsx/tsx:**
```javascript
import './index.css';
```

## Basic Usage

**Utility Classes:**
```jsx
function Card() {
  return (
    <div className="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow">
      <h2 className="text-2xl font-bold mb-2">Card Title</h2>
      <p className="text-gray-600">Card description</p>
      <button className="mt-4 bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">
        Click Me
      </button>
    </div>
  );
}
```

## Common Patterns

**Flexbox Layout:**
```jsx
<div className="flex items-center justify-between gap-4">
  <div>Left</div>
  <div>Center</div>
  <div>Right</div>
</div>

<div className="flex flex-col gap-2">
  <div>Item 1</div>
  <div>Item 2</div>
</div>
```

**Grid Layout:**
```jsx
<div className="grid grid-cols-3 gap-4">
  <div>Column 1</div>
  <div>Column 2</div>
  <div>Column 3</div>
</div>

<div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
  {/* Responsive grid */}
</div>
```

**Responsive Design:**
```jsx
<div className="text-sm md:text-base lg:text-lg">
  Responsive text
</div>

<div className="hidden md:block">
  Only visible on medium screens and up
</div>
```

**Dark Mode:**
```javascript
// tailwind.config.js
export default {
  darkMode: 'class', // or 'media'
  // ...
}
```

```jsx
<div className="bg-white dark:bg-gray-800 text-black dark:text-white">
  Theme-aware content
</div>
```

## Custom Styles

**Extend Theme:**
```javascript
// tailwind.config.js
export default {
  theme: {
    extend: {
      colors: {
        primary: '#3B82F6',
        secondary: '#10B981',
      },
      spacing: {
        '128': '32rem',
      },
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
      }
    },
  },
}
```

**Custom Components:**
```css
/* src/index.css */
@layer components {
  .btn-primary {
    @apply bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600 transition-colors;
  }

  .card {
    @apply bg-white rounded-lg shadow-md p-6;
  }
}
```

```jsx
<button className="btn-primary">Primary Button</button>
<div className="card">Card content</div>
```

## shadcn/ui Integration

shadcn/ui provides pre-built, accessible components built with Tailwind CSS.

**Installation:**
```bash
npx shadcn-ui@latest init
```

**Add Components:**
```bash
npx shadcn-ui@latest add button
npx shadcn-ui@latest add card
npx shadcn-ui@latest add dialog
```

**Usage:**
```jsx
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";

function MyComponent() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Hello</CardTitle>
      </CardHeader>
      <CardContent>
        <Button variant="default">Click me</Button>
        <Button variant="outline">Outline</Button>
        <Button variant="ghost">Ghost</Button>
      </CardContent>
    </Card>
  );
}
```

**Popular shadcn/ui Components:**
- Button, Input, Label, Checkbox, Radio
- Card, Dialog, Sheet, Popover
- Dropdown Menu, Select, Tabs
- Table, Form, Alert
- Toast, Badge, Avatar

## Best Practices

**1. Use Tailwind's Design System:**
```jsx
// ✅ Good - uses spacing scale
<div className="p-4 gap-2">

// ❌ Avoid - arbitrary values
<div className="p-[17px] gap-[9px]">
```

**2. Extract Repeated Patterns:**
```jsx
// ✅ Good - reusable component
const PrimaryButton = ({ children, ...props }) => (
  <button className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600" {...props}>
    {children}
  </button>
);

// ❌ Avoid - repeating classes
<button className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">A</button>
<button className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">B</button>
```

**3. Use clsx/cn for Conditional Classes:**
```javascript
import clsx from 'clsx';

function Button({ variant, className, ...props }) {
  return (
    <button
      className={clsx(
        'px-4 py-2 rounded transition-colors',
        {
          'bg-blue-500 text-white hover:bg-blue-600': variant === 'primary',
          'bg-gray-200 text-gray-800 hover:bg-gray-300': variant === 'secondary',
        },
        className
      )}
      {...props}
    />
  );
}
```

**4. Mobile-First Approach:**
```jsx
// ✅ Good - mobile first
<div className="w-full md:w-1/2 lg:w-1/3">

// ❌ Avoid - desktop first
<div className="w-1/3 lg:w-1/3 md:w-1/2 w-full">
```

## VS Code Extensions

- **Tailwind CSS IntelliSense**: Autocomplete, linting, hover previews
- **Headwind**: Sorts Tailwind classes automatically

## Performance Tips

**1. Purge Unused CSS (enabled by default in production)**
```javascript
// tailwind.config.js
export default {
  content: ['./src/**/*.{js,jsx,ts,tsx}'], // Only scan these files
}
```

**2. Use JIT Mode (default in Tailwind 3+)**
- Generates styles on-demand
- Faster build times
- Smaller CSS files

**3. Avoid @apply in Production**
- Use utility classes directly when possible
- @apply increases bundle size

## Resources

- **Official Docs**: https://tailwindcss.com/docs
- **shadcn/ui**: https://ui.shadcn.com
- **Tailwind UI**: https://tailwindui.com (premium components)
- **Headless UI**: https://headlessui.com (unstyled, accessible components)

## Advanced: artifacts-builder Skill

For complex, multi-component React applications with Tailwind + shadcn/ui, consider using the `artifacts-builder` skill which provides:
- Pre-configured React + TypeScript + Vite + Tailwind + shadcn/ui
- 40+ shadcn/ui components pre-installed
- Optimized build setup
- Single HTML artifact bundling

Use `artifacts-builder` skill for creating elaborate UI components or full applications.
