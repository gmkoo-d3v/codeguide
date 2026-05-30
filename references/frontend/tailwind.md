# Tailwind CSS Frontend Reference

> Secondary reference notice: This document is a deprecated secondary reference inside `codeguide`. Do not use it as the primary source for framework setup or API details. Prefer dedicated framework skills, official documentation, and repository-specific conventions first.

Use this reference only for codeguide architecture and quality decisions when Tailwind is part of the frontend stack.

## Source Preference
- Use the official Tailwind docs for installation, configuration, directives, responsive variants, dark mode, plugins, and version-specific syntax.
- Use repository-local design tokens, component libraries, and accessibility standards as the final authority for styling decisions.
- Use this file to decide styling boundaries, utility discipline, component ownership, and review focus.

## Setup And Configuration Boundaries
- Treat installation commands, config file syntax, CSS directives, and build integration as framework documentation concerns.
- Keep Tailwind configuration centralized and review changes to content globs, theme extension, plugin lists, and dark-mode strategy as architecture-affecting.
- Avoid scattering theme decisions across components when a token, preset, or shared primitive would make the rule explicit.

## Utility Class Usage
- Utility classes are appropriate for local layout, spacing, typography, and state styling when they remain readable.
- Extract repeated class combinations into shared components, variants, or design-system primitives when repetition hides intent.
- Do not encode business rules in class strings; product state should choose semantic variants, not arbitrary utility bundles.

## Layout And Responsiveness
- Prefer mobile-first responsive rules and make breakpoint behavior intentional for each component.
- Use flex and grid utilities to express layout ownership locally, but keep page-level layout constraints at route or shell boundaries.
- Review responsive, dark-mode, hover, focus, disabled, and error states together so visual behavior is complete.

## Custom Styles
- Extend the theme for repeated colors, spacing, typography, shadows, and animation values that represent product design language.
- Use custom CSS sparingly for browser quirks, animation details, or reusable patterns that utilities cannot express clearly.
- Be cautious with `@apply`; prefer direct utilities unless extraction improves maintainability without increasing bundle or cascade risk.

## Component Libraries
- Treat shadcn/ui, Tailwind UI, Headless UI, and similar libraries as implementation choices behind component boundaries.
- Preserve accessibility defaults when wrapping library components, especially focus management, labels, keyboard behavior, and error messaging.
- Keep library customization close to shared primitives rather than repeating overrides in feature screens.

## Tooling And Developer Experience
- Editor extensions and class sorting tools are convenience aids, not architecture requirements.
- Prefer automated formatting or linting rules when class ordering affects review noise.
- Keep generated or copied snippets out of policy docs; link to official docs and project conventions instead.

## Performance And Build Review
- Review content scanning patterns because missed files can drop styles and broad globs can increase build work.
- Verify production builds when configuration, plugin, or theme changes affect generated CSS.
- Keep JIT/default build behavior aligned with the installed Tailwind version rather than assuming an old setup.

## Official Documentation
- Tailwind CSS: https://tailwindcss.com/docs

For setup, APIs, and version-specific syntax, use the official documentation and dedicated framework skills first; this reference covers only codeguide architecture/quality decisions.
