# Frontend Frameworks - Complete Comparison + Architecture (Expanded Edition)

## 1. React (Meta - 2013)

**Architecture**: Component-Based + Virtual DOM + Unidirectional Data Flow + Declarative + Fiber Reconciler

- **Core**: Library not full framework, component = function returning JSX, JSX compiles to React.createElement
- **Virtual DOM**: In-memory copy of real DOM, diffing (Reconciliation) then batch update real DOM - fast. Fiber architecture (React 16+) enables incremental rendering, can pause/resume work, prioritization
- **Unidirectional**: Parent -> Child via props, Child -> Parent via callbacks/events
- **State Management**: useState, useReducer, Context API, External: Redux Toolkit (Flux), Zustand (simple, recommended 2025), Recoil, Jotai, MobX
- **Rendering**: CSR by default, but supports SSR via Next.js, SSG, ISR, RSC
- **Architecture Pattern Used**: 
  - Flux / Redux: Action -> Dispatcher -> Store -> View (unidirectional)
  - Atomic Design: Atoms -> Molecules -> Organisms -> Templates -> Pages (design system)
  - Container/Presentational pattern (old) -> Now Hooks pattern + Server/Client Components

```jsx
// Component architecture with hooks + server state
function UserCard({ user }) { // Presentational
  const [expanded, setExpanded] = useState(false);
  return <div onClick={()=>setExpanded(!expanded)}>{user.name}</div>
}
// Container with logic + TanStack Query for server state
function UserContainer() {
  const { data, isLoading } = useQuery({ queryKey: ['users'], queryFn: () => fetch('/api/users').then(r=>r.json()) });
  if (isLoading) return <Skeleton />;
  return data.map(u => <UserCard key={u.id} user={u} />)
}
// Server Component (Next.js 13+)
async function UserServer() {
  const users = await db.user.findMany(); // direct DB access on server, zero JS to client
  return <UserList users={users} />
}
```

- **Pros**: Huge ecosystem (npm largest), flexible, performance via VDOM + Fiber, React Native for mobile, strong community, job market #1, concurrent features (useTransition, useDeferredValue)
- **Cons**: Too flexible (no opinionated structure), need choose router (React Router), state lib, build tool, JSX learning
- **When Use**: SPA, complex interactive UI, need mobile app via React Native, large team, startup to enterprise, dashboard
- **Versions**: 17 (2020 no major), 18 (2022 concurrent features, Suspense, automatic batching, useId), 19 (2024 Server Components stable, Actions, use() hook, Document Metadata)
- **Build Tools**: Vite (fast ESM + esbuild), CRA (deprecated), Next.js, Parcel

### React Architecture Deep Dive - Fiber
- Fiber = unit of work, linked list of components, can pause work for high priority updates (e.g. user input)
- Reconciliation: Diff old fiber tree vs new elements, determines what changed
- Commit phase: Apply changes to DOM
- Concurrent Mode: Can interrupt rendering for urgent updates

---

## 2. Angular (Google - 2010 AngularJS, 2016 Angular 2+)

**Architecture**: Full MVC Framework + Component-Based + Two-way Data Binding + Dependency Injection + RxJS + Zone.js

- **Core**: Full framework (opinionated), everything included: Router, Forms, HttpClient, DI, CLI, Testing
- **Architecture**: 
  - **Modules**: NgModule (old) -> Standalone components (new Angular 15+ - no NgModule needed)
  - **Components**: @Component decorator with template + style + class, lifecycle hooks (ngOnInit, ngOnDestroy)
  - **Services + DI**: Injectable services singleton via hierarchical DI container (root, module, component level)
  - **Directives**: Structural (*ngIf, *ngFor, @if @for new), Attribute ([ngClass])
  - **Pipes**: Transform data in template (date, currency, custom)
  - **RxJS**: Reactive programming with Observables for async (Http, events, forms) - powerful but learning curve, operators (map, filter, switchMap, mergeMap)

```
App (Standalone)
  -> Components (UI, @Component, template + logic)
  -> Services (Business logic, @Injectable, singleton)
  -> Directives & Pipes (Reusable UI logic)
  -> Router (Lazy loading via loadComponent)
  -> Forms (Reactive Forms with FormControl, FormGroup - type safe)
  -> Signals (Angular 16+ - new reactivity primitive)
```

- **Data Flow**: Two-way binding `[(ngModel)]` (banana in box) + One-way `[prop]` `(event)` + Signals two-way
- **Rendering**: CSR default, SSR via Angular Universal (now @angular/ssr), SSG via Scully/Analog, Hydration
- **Change Detection**: Zone.js patches async APIs and triggers change detection, now with signals + OnPush + zoneless upcoming (Angular 18+)
- **State Management**: Services + RxJS BehaviorSubject (simple), NgRx (Redux for Angular - Actions, Reducers, Effects, Selectors), NGXS, Akita, Elf, Signals store
- **Pros**: Full framework (batteries included), TypeScript first (since beginning), DI powerful, enterprise ready, CLI powerful (ng generate), strict structure good for large teams, forms powerful, RxJS powerful for complex async
- **Cons**: Heavy bundle, steep learning (RxJS, DI, decorators), slower initial load vs React/Vue, less flexible, build slower (but esbuild now)
- **When Use**: Large enterprise apps, banking, admin dashboards, team needs strict structure, TypeScript heavy, long-term maintenance
- **Versions**: 12-14 Ivy renderer (faster), 15 standalone components (no NgModule), 16 signals + required inputs, 17 new control flow @if @for @switch + deferrable views + esbuild default, 18 signals stable + zoneless experimental + material 3, 19 (2024-25) incremental hydration, signal forms

### Angular Signals Deep Dive (New 16+)
```ts
// Old RxJS
count$ = new BehaviorSubject(0);
double$ = this.count$.pipe(map(c => c*2));

// New Signals
count = signal(0);
double = computed(() => this.count() * 2);
effect(() => console.log(this.count())); // side effect
// Template: {{ count() }} not {{ count | async }}
// Pros: Fine-grained reactivity, no RxJS needed for simple state, better performance, simpler mental model
```

---

## 3. Vue.js (Evan You - 2014)

**Architecture**: Progressive Framework + Component-Based + Reactive (Proxy) + Virtual DOM + Two-way binding + SFC

- **Core**: Progressive - can use as library for part of page or full SPA framework, gentle learning curve, HTML template familiar
- **Architecture**:
  - **Options API** (Vue 2): data, methods, computed, watch, lifecycle in object - simple for small components
  - **Composition API** (Vue 3): setup() with ref, reactive, computed, watch, composables (like React hooks) - better for large apps, logic reuse, TypeScript
  - **SFC**: Single File Component .vue file (template + script + style in one) - great DX
  - **Reactivity**: Proxy based (Vue 3) tracks dependencies automatically via ES6 Proxy, ref() for primitives, reactive() for objects

```vue
<template>
  <div @click="count++">{{ count }} - {{ double }}</div>
  <Child :msg="count" @update="onUpdate" />
</template>
<script setup>
import { ref, computed, watch, onMounted } from 'vue'
const count = ref(0)
const double = computed(() => count.value * 2)
watch(count, (newVal) => console.log(newVal))
onMounted(() => console.log('mounted'))
function onUpdate(val) { count.value = val }
</script>
<style scoped> div { color: red; } </style>
```

- **State Management**: Pinia (official, composition API based, replaces Vuex, simple), Vuex (old, mutations/actions)
- **Rendering**: CSR default, SSR via Nuxt.js, SSG, ISR
- **Pros**: Easy learning (HTML template familiar), lightweight (~30KB), great docs (best), flexible, performance good (faster than React in some benchmarks), gentle learning curve, SFC great DX
- **Cons**: Smaller market than React/Angular (but growing), ecosystem smaller than React, mostly Asia/Europe popularity, fewer jobs in US
- **When Use**: Small-medium apps, quick prototyping, team new to frameworks, progressive enhancement (add Vue to existing page), marketing sites
- **Versions**: Vue 2 (2016-2023, Object.defineProperty reactivity), Vue 3 (2020+ Composition API, Proxy reactivity, faster, smaller, TS), Nuxt 3 (2022, Vue 3 + Vite + Nitro)

---

## 4. Next.js (Vercel - 2016, React Framework)

**Architecture**: Fullstack React Framework + File-based Routing + Hybrid Rendering (SSR, SSG, ISR, CSR, RSC, PPR) + Edge

- **Core**: React on steroids for production, built-in routing, optimization, fullstack, Vercel's flagship
- **Rendering Strategies** (Key for interview):

| Strategy | When renders | Use Case | Pros | Cons |
|----------|--------------|----------|------|------|
| **CSR** | Client side (useEffect, "use client") | Interactive UI, dashboards after login | Fast navigation after load | SEO bad, initial blank, JS heavy |
| **SSR** | Server side per request (Server Component async) | Dynamic data per request, personalized | SEO good, fresh data, fast FCP | TTFB slower, server cost, no CDN cache |
| **SSG** | Static at build time (generateStaticParams) | Blog, marketing, docs | Fastest (CDN), cheap, SEO | Stale data, build time large for many pages |
| **ISR** | Static but revalidate every X sec (revalidate: 60) | E-commerce product pages, blog with frequent updates | Fast like SSG but fresh, best of both | Stale for X sec, first request after expiry slow |
| **RSC** | React Server Components (default in App Router) | Data fetching, direct DB access, large dependencies | Zero JS to client, secure (no API keys to client), fast | Can't use useState/useEffect, need client components for interactivity |
| **PPR** | Partial Prerendering (Next 14+ experimental) | Mix static shell + dynamic holes | Fast static shell + dynamic streaming | Complex |

```
app/ (App Router Next 13+ - recommended)
  layout.tsx (root layout, shared UI)
  page.tsx (route / - Server Component by default)
  loading.tsx (Suspense fallback)
  error.tsx (Error boundary)
  not-found.tsx (404)
  users/
    page.tsx (/users) - Server Component
    [id]/page.tsx (/users/123) - dynamic route
    [id]/loading.tsx
  (group)/ - route groups not in URL
  @modal/ - parallel routes
  api/
    users/route.ts (API routes - Route Handlers) - fullstack!

File-based routing: file path = URL path, no config
```

- **Features**: 
  - Image optimization (next/image - automatic WebP, lazy, responsive)
  - Font optimization (next/font - no layout shift)
  - API routes (fullstack - backend in same project)
  - Middleware (edge, auth, redirects)
  - Edge runtime (run on edge close to user, fast, but limited Node APIs)
  - Turbopack (Rust bundler 10x faster than Webpack)
  - Server Actions (Next 13+ - call server functions from client components without API route)

```tsx
// Server Component (default) - zero JS to client, direct DB
async function ProductPage({ params }: { params: { id: string } }) {
  const product = await db.product.findUnique({ where: { id: params.id } }); // direct DB!
  return <ProductDetail product={product} />
}
// Client Component - interactivity
"use client"
function Counter() {
  const [count, setCount] = useState(0);
  return <button onClick={()=>setCount(count+1)}>{count}</button>
}
// Server Action - mutation without API route
async function createProduct(formData: FormData) {
  "use server"
  await db.product.create({ data: { name: formData.get('name') } });
  revalidatePath('/products');
}
```

- **State Management**: Same as React (Zustand, Redux Toolkit, Jotai)
- **Pros**: Best performance (hybrid rendering), SEO (SSR/SSG), DX great, image/font optimization, fullstack (API routes + Server Actions), middleware, edge, Vercel deployment easy (git push deploy), industry standard for React prod, large community
- **Cons**: Vercel lock-in slight (but can deploy anywhere), complexity of rendering modes (need to understand RSC), App Router learning curve from Pages Router, caching complex (fetch cache)
- **When Use**: SEO needed (e-commerce, blogs, marketing, landing pages), performance critical, fullstack React, production React app - **Recommended default for React in 2025-26**
- **Versions**: 12 (SSR/SSG), 13 (App Router + RSC + Turbopack beta), 14 (Turbopack stable, Server Actions stable, PPR experimental), 15 (2024 - React 19 support, Turbopack, improved caching)

---

## 5. Other Frontend Frameworks Detailed

### Svelte / SvelteKit (Rich Harris - 2016)

**Architecture**: Compiler Framework - No Virtual DOM, compiles to vanilla JS at build time, truly reactive assignments, runes (Svelte 5)

- **Core**: No VDOM, compiler converts Svelte syntax to imperative JS that directly updates DOM, no runtime overhead, smallest bundle
- **Reactivity**: 
  - Svelte 4: `let count = 0; $: double = count*2;` reactive declarations via `$:`
  - Svelte 5 (2024): Runes - `$state`, `$derived`, `$effect` similar to signals
```svelte
<script>
  let count = $state(0);
  let double = $derived(count*2);
  $effect(() => console.log(count));
</script>
<button onclick={()=>count++}>{count} - {double}</button>
<style> button { color: red; } </style>
```
- **SvelteKit**: Fullstack framework like Next.js but for Svelte, file-based routing, SSR/SSG, adapters for Vercel/Netlify/Node
- **Pros**: Smallest bundle (no runtime), fastest runtime (no VDOM diffing), simple syntax (closest to vanilla HTML/JS/CSS), no boilerplate, great DX, built-in transitions/animations
- **Cons**: Smaller ecosystem (but growing), fewer jobs, fewer UI libraries, TypeScript support improved but not as good as React
- **When**: Performance critical, small bundle needed (e.g. embedded widgets), new projects where bundle size matters, marketing sites, team wants simplicity
- **Benchmarks**: Often fastest in JS framework benchmarks (https://krausest.github.io/js-framework-benchmark/)

### Solid.js (Ryan Carniato - 2021)

**Architecture**: Fine-grained Reactivity + No VDOM + JSX + Signals (pioneer of signals)

- **Core**: Looks like React (JSX, hooks-like) but fine-grained reactivity - no VDOM, components run once, only reactive primitives re-execute, extremely fast
- **Reactivity**: `createSignal`, `createEffect`, `createMemo` (similar to Svelte runes, now adopted by Angular)
```jsx
import { createSignal, createEffect } from 'solid-js';
function Counter() {
  const [count, setCount] = createSignal(0);
  createEffect(() => console.log(count()));
  return <button onClick={()=>setCount(count()+1)}>{count()}</button>;
}
```
- **Pros**: Fastest benchmarks often #1, React-like syntax easy for React devs, small bundle, fine-grained (only changed DOM updates)
- **Cons**: Very small community, fewer jobs, ecosystem tiny, JSX but not React (can't use React libs)
- **When**: Performance absolute critical, want React-like but faster, small projects

### Astro (2021)

**Architecture**: Islands Architecture + Content-focused + Multi-framework + Zero JS by default

- **Core**: Static site generator, ships zero JS by default, only hydrates interactive components (islands) when needed, can use React, Vue, Svelte, Solid components in same project
- **Islands**: Static HTML by default, interactive components are islands: `<Counter client:load />` only Counter JS shipped, rest static
- **Pros**: Fastest for content sites (blogs, marketing, docs), zero JS default, multi-framework, great for SEO, Markdown/MDX great
- **Cons**: Not for highly interactive apps (use Next.js), islands architecture learning
- **When**: Content-heavy sites, blogs, marketing, docs, portfolios - **best for content**

### Qwik (Miško Hevery - Angular creator - 2022)

**Architecture**: Resumability not Hydration + Edge + Instant On

- **Core**: Traditional frameworks hydrate (download JS, execute to make interactive) - slow. Qwik resumable: Server renders HTML with serialized state, client resumes without re-executing, instant interactive, only loads JS for interaction
- **Pros**: Fastest Time to Interactive (TTI), instant on even large apps, edge first, perfect Lighthouse scores
- **Cons**: Very new, small ecosystem, different mental model (resumability)
- **When**: Performance critical e-commerce, need instant loading, edge

### Remix (Now merged into React Router v7 - 2021)

**Architecture**: Fullstack React + SSR focused + Web Standards (forms, loaders) + Nested Routing + Progressive Enhancement

- **Core**: SSR by default, loaders (data fetching on server), actions (mutations), forms work without JS (progressive enhancement), nested routing (each route can have own data, error boundary)
- **Pros**: Great UX (fast navigation, pending UI), web standards, progressive enhancement (works without JS), nested routing powerful
- **Cons**: Now part of React Router v7, future unclear but still good, smaller than Next.js
- **When**: Need SSR, great UX, forms heavy, progressive enhancement

---

## Frontend Architecture Patterns Detailed Comparison

| Pattern | Description | Pros | Cons | Used In |
|---------|-------------|------|------|---------|
| **Component-Based** | UI as reusable components with props, state, lifecycle | Reusability, maintainability, team scalability | Prop drilling, need state management | All modern (React, Vue, Angular, Svelte) |
| **Virtual DOM** | In-memory DOM tree, diffing, batch updates | Fast, declarative, cross-platform (React Native) | Memory overhead, diffing cost | React, Vue, Preact |
| **No VDOM (Compiler)** | Compiles to direct imperative DOM updates at build time | Smallest bundle, fastest runtime, no diff overhead | Compile time, less flexible | Svelte, Solid, Qwik |
| **MVC / MVVM** | Model-View-ViewModel separation, two-way binding | Separation, testable, familiar | Complexity, two-way can cause loops | Angular (MVVM), Vue (MVVM), Knockout |
| **Flux / Redux** | Unidirectional: Action->Dispatcher->Store->View, single source of truth | Predictable, time travel, debugging | Boilerplate, overkill small apps | React (Redux), Vue (Vuex), NgRx (Angular) |
| **Reactive (RxJS)** | Streams, observables, operators for async, declarative async | Powerful for complex async, cancellation, composition | Steep learning, overkill simple | Angular (RxJS heavy), Vue with RxJS |
| **Signals** | Fine-grained reactivity primitive: signal, computed, effect | Simple, performant, fine-grained (only dependent updates), no VDOM needed | New, ecosystem adopting | Angular 16+, Solid (pioneer), Vue ref, Svelte 5 runes, Qwik, Preact Signals |
| **Atomic Design** | Atoms (Button) -> Molecules (SearchForm) -> Organisms (Header) -> Templates -> Pages | Design system, consistency, reusability | Over-engineering small apps | Design systems, Storybook, any framework |
| **Micro Frontends** | Frontend as independent micro apps (Module Federation) | Team autonomy, independent deploy, tech diversity | Bundle duplication, consistency, perf overhead | Large org, Webpack Module Federation, Single-SPA |
| **Islands** | Static HTML by default, only interactive components hydrated as islands | Zero JS by default, fast, SEO | Not for highly interactive apps | Astro, Fresh (Deno), Eleventy |
| **Resumability** | Server serializes state, client resumes without re-executing, no hydration | Instant interactive, no hydration cost | New mental model, small eco | Qwik |
| **File-based Routing** | File path = URL, convention over configuration | Simple, no router config, code splitting auto | Less flexible for complex routes | Next.js, Nuxt, SvelteKit, Remix, Astro |

## Performance Benchmarks (Approximate 2024-25)

| Framework | Bundle Size (Hello World) | Runtime Speed | Memory | Build Speed | Lighthouse |
|-----------|---------------------------|---------------|--------|-------------|------------|
| Svelte | 2-3KB | Fastest | Low | Fast | 100 |
| Solid | 3-5KB | Fastest | Low | Fast | 100 |
| Vue | 20-30KB | Fast | Medium | Fast (Vite) | 95-100 |
| React | 40-50KB | Good | Medium | Fast (Vite) | 90-95 |
| Angular | 100-150KB | Good | High | Medium (esbuild now fast) | 85-90 |
| Next.js | 80-100KB + optimizations | Good + SSR fast | Medium | Medium (Turbopack fast) | 95-100 (SSR) |
| Qwik | 1KB initial | Instant TTI | Low | Fast | 100 |

*Note: Bundle size depends on features, not just framework*

## How to Choose Frontend Framework? (Interview Answer Detailed)

```
Factors to evaluate:

1. Team skill:
   - JS devs familiar with JSX -> React / Next.js
   - Java/.NET enterprise with TypeScript OOP -> Angular
   - Beginners or HTML template lovers -> Vue
   - Performance purists -> Svelte / Solid

2. Project type:
   - SEO critical e-commerce, blogs, marketing, landing -> Next.js (SSR/SSG/ISR) or Astro (content)
   - Admin dashboard internal, complex forms -> Angular (full framework) or React + Ant Design
   - Highly interactive SPA (Figma-like) -> React or Solid (fine-grained)
   - Content-heavy blog/docs -> Astro (zero JS) or Next.js
   - Need mobile app too -> React + React Native (code sharing)
   - Embedded widget small bundle -> Svelte or Solid

3. Performance:
   - Absolute fastest runtime + smallest bundle -> Svelte / Solid / Qwik
   - Good enough + ecosystem -> React + Next.js with optimizations (image, font, code splitting)
   - Large enterprise okay with larger bundle -> Angular

4. Ecosystem & Jobs:
   - Largest ecosystem + jobs -> React + Next.js (safe bet)
   - Enterprise banking -> Angular (many banks use)
   - Asia/Europe quick MVPs -> Vue

5. Long term maintenance:
   - Large team need strict structure -> Angular (opinionated) or Next.js with good conventions
   - Small team fast iteration -> React + Vite or Vue

My choice for new project in 2026:

- Default: Next.js 15 (React 19) with App Router, Server Components for data fetching (zero JS), Client Components for interactivity, Zustand for client state, TanStack Query for server state caching, Tailwind for CSS, TypeScript strict, shadcn/ui for components, deployed on Vercel or CloudFront+S3.

- Why? SEO + performance (hybrid rendering) + fullstack (API routes + Server Actions) + image optimization + huge ecosystem + React Native sharing + job market.

- For large banking enterprise with 50+ devs need strict structure: Angular 18 with standalone components + signals + NgRx + Angular Material, TypeScript strict, ESLint strict.

- For content blog/docs: Astro with islands, zero JS, Markdown, multi-framework if needed.

- For embedded widget where bundle size critical (e.g. chat widget to embed on other sites): Svelte or Solid for 2-3KB bundle.

I have used React 18 + Next.js 14 for e-commerce handling 10k daily users, implemented micro frontends via Module Federation for search team independent deployment, and Angular 15 for admin dashboard.
```

## Frontend Build Tools Detailed

- **Vite**: Fastest dev server (ESM native + esbuild for deps), HMR instant, build via Rollup, default for Vue, React now via `npm create vite@latest`, plugin ecosystem large, **recommended for dev**
- **Webpack**: Old bundler, powerful, loaders, plugins, code splitting, but slow dev server, still used in many legacy, CRA uses, Angular uses custom webpack (now esbuild)
- **Turbopack**: Rust based, Next.js 15 default dev bundler, 10x faster than Webpack, incremental, **future**
- **esbuild**: Go based, extremely fast bundler/minifier, used by Vite for deps, not full bundler for prod (but can)
- **Rollup**: For libraries, tree shaking excellent, ESM first
- **Parcel**: Zero config, fast, good for beginners
- **Rspack**: Rust based Webpack compatible, fast, by ByteDance

## State Management Decision Tree

```
Need state?

- Local to component only?
  Yes -> useState / ref / signal

- Shared between few components parent-child?
  Yes -> Props drilling + callbacks (if 2-3 levels okay) or Context / Provide-Inject

- Global client state (theme, user, cart)?
  - Simple -> Zustand (1KB, simple, recommended 2025) or Jotai or Valtio
  - Complex with time travel, middleware -> Redux Toolkit (large apps) or Pinia (Vue) or NgRx (Angular)

- Server state (data from API)?
  - Must separate from client state!
  - Use TanStack Query (React Query) - caching, dedup, background refetch, pagination, infinite scroll, optimistic updates
  - Or SWR (Vercel) - similar
  - Or RTK Query (Redux Toolkit Query)
  - Why separate? Server state is async, cached, needs sync with server, client state is sync local

- Forms?
  - React Hook Form (performant, minimal re-renders) + Zod for validation
  - Formik (older)
  - Angular Reactive Forms
  - Vue FormKit

- URL state?
  - Use URL search params for shareable state (filters, pagination) - e.g. ?page=2&sort=name

My stack 2026:
- Client state: Zustand
- Server state: TanStack Query
- Forms: React Hook Form + Zod
- URL state: nuqs (Next.js) or useSearchParams
```

## Testing Frontend

- **Unit**: Vitest (fast, Vite native) or Jest, React Testing Library (test user behavior not implementation)
- **Component**: Storybook (visual testing), Chromatic
- **E2E**: Playwright (recommended 2025, fast, multi-browser), Cypress (older)
- **Visual Regression**: Percy, Chromatic

## Interview Q&A Frontend

**Q: Virtual DOM vs Real DOM?**
- Real DOM manipulation expensive (reflow/repaint). VDOM in-memory JS object representation of real DOM, diffing (reconciliation) finds minimal changes, batch updates real DOM, reduces expensive operations.

**Q: React Fiber?**
- Fiber is reimplementation of React core algorithm (React 16+), unit of work, linked list, can pause/resume/abort work, enables concurrent features (useTransition), incremental rendering, better scheduling.

**Q: Server Components vs Client Components?**
- Server Components: Render on server, zero JS to client, can directly access DB, secure, fast, but no useState/useEffect, no interactivity. Client Components: "use client" directive, render on client, can use state, effects, interactivity, but JS bundle.
- Use Server for data fetching, Client for interactivity, compose.

**Q: How to optimize React performance?**
- Memoization: React.memo for components, useMemo for expensive calculations, useCallback for functions to prevent child re-renders
- Code splitting: React.lazy + Suspense, Next.js dynamic import
- Virtualization: react-window for long lists (only render visible)
- Bundle: Analyze with @next/bundle-analyzer, tree shaking, remove unused deps
- Images: next/image WebP, lazy loading
- State: Colocate state (keep state close to where used), lift only when needed, use Zustand not Context for frequent updates (Context causes all consumers re-render)
- TanStack Query for server state caching to avoid refetching

**Q: Angular Signals vs RxJS?**
- RxJS powerful for complex async streams, operators, cancellation, but steep learning, need unsubscribe. Signals simple for state, fine-grained, synchronous, no need unsubscribe, better performance, simpler mental model. Angular moving to signals for state, RxJS still for complex async (Http, events) but can interop via toSignal, toObservable.

---

## Expanded: More Frameworks Detailed

### 6. Astro (2021) - Islands Architecture Pioneer

**Architecture**: Islands + Content-focused + Zero JS by default + Multi-framework + SSG/SSR

- **Islands Architecture**: Static HTML by default (zero JS shipped), only interactive components hydrated as islands. Each island independent, only JS for interactive parts shipped.
```astro
---
// Astro component (server only, zero JS to client by default)
import Counter from '../components/Counter.jsx'; // React component
import VueCounter from '../components/VueCounter.vue';
---
<html>
  <body>
    <h1>Static content - zero JS</h1>
    <Counter client:load /> <!-- Only this island JS shipped, hydrates on load -->
    <VueCounter client:visible /> <!-- Hydrates when visible in viewport -->
    <Counter client:idle /> <!-- Hydrates when browser idle -->
  </body>
</html>
```
- **Directives**: client:load (hydrate on load), client:idle (when idle), client:visible (when visible), client:media (media query), client:only (client only, no SSR)
- **Multi-framework**: Use React, Vue, Svelte, Solid components in same Astro page! Perfect for migration or using best component from each eco
- **Content**: Markdown, MDX first-class, content collections with Zod validation, great for blogs, docs, marketing
- **Pros**: Fastest for content sites (Lighthouse 100, zero JS), multi-framework, great DX for content, SSG/SSR/ISR, simple
- **Cons**: Not for highly interactive apps (use Next.js), islands communication via props or Nano Stores
- **When**: Blogs, marketing, docs, portfolios, content-heavy sites - **best for content 2024-25**
- **Versions**: Astro 3, 4 (2024)

### 7. Qwik (Miško Hevery - Angular creator - 2022) - Resumability

**Architecture**: Resumability not Hydration + Edge + Instant On + Optimizer

- **Problem with Hydration**: Traditional frameworks SSR HTML, then client downloads JS and executes to make interactive (hydrate) - duplicate work, slow TTI for large apps
- **Resumability**: Server renders HTML + serializes state + event listeners + component tree, client resumes without re-executing, only loads JS for interaction when needed (e.g. click), instant interactive, no hydration cost
- **Optimizer**: Qwik optimizer splits code into tiny chunks (1KB), loads only needed chunk on interaction
```tsx
// Qwik component
import { component$, useSignal } from '@builder.io/qwik';
export const Counter = component$(() => {
  const count = useSignal(0);
  return <button onClick$={() => count.value++}>{count.value}</button>; // onClick$ is resumable, $ suffix
});
```
- **Pros**: Fastest Time to Interactive (TTI) even large apps, instant on, edge first (Cloudflare Workers), perfect Lighthouse 100, no hydration
- **Cons**: Very new (2022), small ecosystem, different mental model (resumability, $ suffix), fewer jobs
- **When**: Performance critical e-commerce, need instant loading even large app, edge, marketing with interactivity
- **Versions**: Qwik 1.x

### 8. Remix (Now React Router v7 - 2021) - Web Standards

**Architecture**: Fullstack React + SSR focused + Web Standards (forms, loaders, actions) + Nested Routing + Progressive Enhancement

- **Core**: SSR by default, loaders (data fetching on server per route), actions (mutations via forms), forms work without JS (progressive enhancement - form POST works even if JS disabled), nested routing (each route has own loader, action, error boundary, pending UI)
- **Nested Routing**: Root layout -> Users layout -> User detail, each with own data, errors don't crash whole app
```tsx
// Remix loader (server)
export async function loader({ params }) {
  const user = await db.user.findUnique({ where: { id: params.id } });
  return json(user);
}
// Component uses loader data
export default function User() {
  const user = useLoaderData<typeof loader>();
  return <div>{user.name}</div>
}
// Action for mutation via form
export async function action({ request }) {
  const formData = await request.formData();
  const name = formData.get('name');
  await db.user.create({ data: { name } });
  return redirect('/users');
}
// Form works without JS!
export default function NewUser() {
  return <Form method="post"><input name="name" /><button>Create</button></Form>
}
```
- **Pros**: Great UX (fast navigation, pending UI, optimistic UI), web standards (forms, HTTP), progressive enhancement, nested routing powerful, error boundaries per route
- **Cons**: Now merged into React Router v7, future as Remix brand unclear but concepts in React Router, smaller than Next.js
- **When**: Need SSR, great UX, forms heavy, progressive enhancement, nested routing

### 9. SolidStart (Solid.js fullstack)

**Architecture**: Solid.js + File-based Routing + SSR/SSG + Fine-grained Reactivity

- Similar to Next.js but for Solid, fastest runtime, fine-grained
- When: Want Solid performance with fullstack routing

---

## Expanded: Frontend Performance Deep Dive

### Bundle Optimization

```js
// 1. Code Splitting
// React.lazy + Suspense
const HeavyComponent = React.lazy(() => import('./HeavyComponent'));
<Suspense fallback={<Spinner />}><HeavyComponent /></Suspense>

// Next.js dynamic
const DynamicComponent = dynamic(() => import('../components/Heavy'), { loading: () => <Spinner />, ssr: false });

// 2. Tree Shaking - remove unused code
// Use ES modules, avoid import * as _, use named imports
import { debounce } from 'lodash-es'; // not import _ from 'lodash'

// 3. Bundle Analyzer
// @next/bundle-analyzer, vite-bundle-visualizer
// Analyze what contributes to bundle size, remove large deps (moment.js -> date-fns)

// 4. Remove console in prod
// Terser plugin

// 5. Compression
// gzip (70% reduction), Brotli (80% reduction) via Nginx or CDN
```

### Image Optimization

```jsx
// Next.js Image - automatic WebP, responsive, lazy loading, blur placeholder
import Image from 'next/image';
<Image src="/hero.jpg" alt="Hero" width={800} height={600} placeholder="blur" blurDataURL="..." priority={true} sizes="(max-width: 768px) 100vw, 50vw" />

// Why? 
// - WebP/AVIF smaller than JPEG/PNG (30% smaller)
// - Responsive: Serves different sizes for different viewports via srcset
// - Lazy loading: Only loads when visible
// - No layout shift: width/height reserves space
```

### Caching

```
// HTTP Cache Headers for static assets (versioned filename app.v123.js)
Cache-Control: public, max-age=31536000, immutable // 1 year, immutable (filename changes when content changes)

// For HTML (not versioned)
Cache-Control: public, max-age=0, must-revalidate // Always revalidate

// Next.js handles automatically via file hashing
```

### Rendering Optimization

```
// 1. Virtualization for long lists (10k items)
import { FixedSizeList } from 'react-window';
<FixedSizeList height={500} itemCount={10000} itemSize={35} width={300}>
  {({ index, style }) => <div style={style}>Row {index}</div>}
</FixedSizeList>
// Only renders visible items (10) not 10k, huge perf

// 2. Debounce/Throttle for search, scroll, resize
const debouncedSearch = useMemo(() => debounce((q) => search(q), 300), []);
<input onChange={(e) => debouncedSearch(e.target.value)} />

// 3. Memoization
const expensiveValue = useMemo(() => computeExpensive(a, b), [a, b]); // only recompute when a,b change
const memoizedCallback = useCallback(() => doSomething(a), [a]); // stable reference
const MemoizedComponent = React.memo(Component); // only re-render if props change

// 4. Web Workers for CPU heavy tasks (don't block main thread)
const worker = new Worker(new URL('./worker.js', import.meta.url));
worker.postMessage(data);
worker.onmessage = (e) => console.log(e.data);
```

## Expanded: Micro Frontends Deep Dive with Module Federation

```js
// Webpack Module Federation - host (shell) and remote (micro frontend)

// Remote - search micro frontend (search team owns, deployed independently)
// webpack.config.js for search app
new ModuleFederationPlugin({
  name: 'search',
  filename: 'remoteEntry.js', // entry file
  exposes: {
    './Search': './src/Search', // expose Search component
    './SearchStore': './src/store'
  },
  shared: { react: { singleton: true }, 'react-dom': { singleton: true } } // share React to avoid duplicate
});

// Host - shell app (main team)
// webpack.config.js for shell
new ModuleFederationPlugin({
  name: 'shell',
  remotes: {
    search: 'search@https://search.example.com/remoteEntry.js', // load remote from URL
    cart: 'cart@https://cart.example.com/remoteEntry.js'
  },
  shared: { react: { singleton: true }, 'react-dom': { singleton: true } }
});

// Host usage - load remote component dynamically
import { lazy, Suspense } from 'react';
const Search = lazy(() => import('search/Search')); // from remote
const Cart = lazy(() => import('cart/Cart'));
function App() {
  return (
    <div>
      <Suspense fallback={<div>Loading Search...</div>}><Search /></Suspense>
      <Suspense fallback={<div>Loading Cart...</div>}><Cart /></Suspense>
    </div>
  );
}
// Search team can deploy search micro frontend independently without deploying shell!
// Shell loads latest search remoteEntry.js at runtime
```

**Challenges & Solutions**:

| Challenge | Solution |
|-----------|----------|
| Bundle duplication (React twice) | shared: { react: { singleton: true } } ensures one React |
| Routing (each micro frontend has own router) | Use single router in shell, micro frontends use memory router or receive route via props, or use single-spa for routing |
| Shared state (cart needs user) | Use custom events, or shared store via Module Federation shared, or Nano Stores, or props drilling via shell, or global event bus |
| CSS conflicts (styles leak) | Use CSS Modules, or Scoped CSS, or Shadow DOM (Web Components), or Tailwind with prefix |
| Versioning (breaking change in remote) | Versioned remoteEntry.js (remoteEntry.v1.js, v2), or feature flags, or contract testing |
| Performance (many remotes) | Lazy load remotes, preload critical, shared deps |

## Expanded: Interview Q&A More

**Q: CSR vs SSR vs SSG vs ISR vs RSC? When use which?**

```
CSR (Client Side Rendering):
- Renders in browser via JS, empty HTML initially, JS fetches data and renders
- Pros: Fast navigation after load (SPA), rich interactivity
- Cons: SEO bad (crawlers see empty), initial blank, slow FCP, JS heavy
- Use: Dashboards after login (SEO not needed), highly interactive apps

SSR (Server Side Rendering):
- Renders HTML on server per request, sends HTML to client, client hydrates to interactive
- Pros: SEO good (crawlers see HTML), fast FCP (HTML ready), fresh data per request
- Cons: TTFB slower (server render time), server cost (render per request), no CDN cache (dynamic)
- Use: Dynamic personalized pages (cart, checkout, user profile), SEO needed + fresh data

SSG (Static Site Generation):
- Renders HTML at build time, static HTML files, served via CDN
- Pros: Fastest (CDN), cheap (no server), SEO good, scalable
- Cons: Stale data (built once), build time large for many pages (1M pages build hours)
- Use: Blogs, marketing, docs, product listing if not too dynamic

ISR (Incremental Static Regeneration):
- SSG but revalidate every X sec, static but fresh, hybrid SSG+SSR
- First request after revalidate time triggers background regeneration, serves stale while regenerating, next request fresh
- Pros: Fast like SSG but fresh, best of both, scalable
- Cons: Stale for X sec, first request after expiry slow (but can use on-demand revalidation via webhook)
- Use: E-commerce product detail (revalidate 60 sec), blog with frequent updates, **recommended for many use cases**

RSC (React Server Components):
- Server Components render on server, zero JS to client, can directly access DB, secure, Client Components for interactivity
- Pros: Zero JS for server components, direct DB access, secure (no API keys to client), fast, automatic code splitting
- Cons: Can't use useState/useEffect in server components, need client components for interactivity, new mental model
- Use: Data fetching, direct DB access, large dependencies (e.g. markdown parser) that should not go to client

My choice:
- Marketing/blog/docs -> SSG or Astro (zero JS)
- Product listing (1000 products) -> SSG or ISR revalidate 60 sec (fast + SEO + fresh)
- Product detail (dynamic price, inventory) -> ISR revalidate 10 sec or SSR if need real-time inventory
- Cart/checkout (personalized) -> SSR or CSR (after login SEO not needed, CSR okay)
- Dashboard after login -> CSR (SEO not needed)
- Use RSC for data fetching in Next.js App Router - server components for data, client for interactivity
```

**Q: How to handle state management in large React app?**

```
- Local state: useState for component local (e.g. form input, toggle)
- Lifted state: Lift to parent if shared between few siblings
- Context: For theme, user, locale (infrequent updates) - but Context causes all consumers re-render on any change, not good for frequent updates like cart
- Global client state: Zustand (1KB, simple, no boilerplate, recommended 2025) or Jotai (atomic) or Redux Toolkit (large apps with time travel, middleware, but boilerplate)
- Server state: Separate! Use TanStack Query (React Query) for data from API - caching, dedup, background refetch, pagination, infinite scroll, optimistic updates, handles loading/error states
  - Why separate? Server state is async, cached, needs sync with server, shared, stale, while client state is sync local
  - Example: useQuery for users list, useMutation for create user with optimistic update
- Forms: React Hook Form (performant, minimal re-renders, uncontrolled) + Zod for validation
- URL state: Use URL search params for shareable state (filters, pagination, sort) via nuqs or useSearchParams - e.g. ?page=2&sort=name shareable via URL

My stack:
- Client: Zustand for cart, theme, user
- Server: TanStack Query for all API data
- Forms: React Hook Form + Zod
- URL: nuqs for filters

Avoid: Putting server state in Redux/Zustand (duplicate, need manual sync), use TanStack Query instead.
```


---

## Expanded Again: Even More Frontend Frameworks & Advanced Topics

### 10. Ember.js (2011) - Convention over Configuration for Ambitious Apps

**Architecture**: MVC + Convention over Configuration + Glimmer VM + Ember Data

- **Core**: Oldest modern framework, convention, everything included: Router, Data layer (Ember Data), CLI, Testing
- **Architecture**: MVC, Router maps URL to Route -> Model hook fetches data -> Controller -> Template (Handlebars)
- **Glimmer VM**: Fast rendering engine, similar to VDOM but more efficient
- **Pros**: Convention, stability, great for large long-lived apps, Ember Data powerful, CLI, strong conventions reduce decisions
- **Cons**: Heavy, less popular now, smaller community than React, learning curve for conventions, less flexible
- **When**: Large ambitious web apps, long-term maintenance, team wants convention, e.g. LinkedIn, Apple Music used Ember
- **Versions**: Ember 4, 5 (2023-24)

### 11. Alpine.js (2019) - Minimal for Sprinkling Interactivity

**Architecture**: Minimal + Declarative + Directives (like Vue but tiny)

- **Core**: Tiny (15KB), no build, add interactivity directly in HTML via x-data, x-bind, x-on directives, like Tailwind for JS
```html
<div x-data="{ count: 0 }">
  <button @click="count++" x-text="count"></button>
</div>
```
- **Pros**: Tiny, no build, easy to add to existing server-rendered pages (Laravel, Rails), simple
- **Cons**: Not for large SPAs, limited
- **When**: Add small interactivity to server-rendered pages, progressive enhancement, small widgets

### 12. Lit (Google - 2018) - Web Components

**Architecture**: Web Components + LitElement + Reactive Properties + Shadow DOM

- **Core**: Builds on Web Components standard (custom elements, Shadow DOM, HTML templates), lightweight (5KB), fast, interoperable with any framework
- **Pros**: Web standards, interoperable, small, fast, no framework lock-in, Shadow DOM encapsulation
- **Cons**: Web Components still not mainstream, smaller eco
- **When**: Design system that needs to work in React, Vue, Angular any framework, reusable widgets, micro frontends via Web Components

### 13. Fresh (Deno - 2022) - Islands + Deno + Preact

**Architecture**: Islands + Deno + Preact + No Build + Edge + JIT

- **Core**: Deno's fullstack framework, islands architecture (like Astro), Preact for UI, no build step in dev (esbuild on demand), edge, TypeScript first
- **Pros**: No build, Deno secure by default, islands fast, edge, TypeScript
- **Cons**: Deno ecosystem smaller than Node, new
- **When**: Deno projects, edge, islands

---

## Expanded: Advanced Frontend Architecture Patterns

### 14. Hydration vs Resumability vs Islands vs Streaming SSR

| Pattern | How works | JS shipped | TTI | Use Case | Frameworks |
|---------|-----------|------------|-----|----------|------------|
| **CSR** | Empty HTML + JS fetches data + renders | All JS | Slow (JS download + exec + data fetch) | Dashboards after login | React CSR, Vue CSR |
| **SSR + Hydration** | Server renders HTML + sends HTML + JS, client JS hydrates (re-executes to make interactive) | All JS for page | Medium (HTML fast but hydration cost) | SEO + dynamic | Next.js SSR, Nuxt SSR, Angular Universal |
| **SSG** | Build time renders HTML static, CDN | JS for interactivity only | Fast (CDN) | Blogs, marketing | Next.js SSG, Astro SSG, Gatsby |
| **ISR** | SSG + revalidate every X sec, stale-while-revalidate | JS for interactivity | Fast like SSG | E-commerce product | Next.js ISR |
| **Streaming SSR** | Server streams HTML chunks as ready via Suspense, client progressively hydrates | JS chunked | Fast (first chunk fast) | Large pages with slow data | Next.js App Router with Suspense, React 18 streaming |
| **Islands** | Static HTML by default, only interactive components (islands) hydrated, rest static zero JS | Only islands JS | Fastest for content (zero JS default) | Content sites with few interactive | Astro, Fresh |
| **Resumability** | Server renders HTML + serializes state + listeners, client resumes without re-executing, only loads JS on interaction | Tiny initially, loads on interaction | Instant (no hydration) | Perf critical e-commerce | Qwik |
| **PPR** | Partial Prerendering - static shell + dynamic holes streamed | Shell static zero JS + dynamic JS | Fast shell + dynamic | Mix static + dynamic | Next.js 14+ PPR experimental |

**Interview Q: Hydration vs Resumability?**
- Hydration: Server renders HTML, client JS re-executes component code to attach event listeners and make interactive, duplicate work (server rendered + client re-executes), slow TTI for large apps
- Resumability: Server renders HTML + serializes state + listeners into HTML, client resumes from where server left off without re-executing, only loads JS for interaction when needed (e.g. click), instant TTI, no duplicate work
- Qwik is resumability pioneer, React moving towards resumability concepts via Server Components

### 15. Module Federation Deep Dive Advanced - Shared Dependencies, Versioning, Fallbacks

```js
// Advanced Module Federation with shared deps and fallbacks

// Remote - search app with shared React singleton and fallback
new ModuleFederationPlugin({
  name: 'search',
  filename: 'remoteEntry.js',
  exposes: {
    './Search': './src/Search',
    './SearchStore': './src/store'
  },
  shared: {
    react: { 
      singleton: true, // only one React instance
      requiredVersion: '^18.0.0', // version requirement
      strictVersion: true, // fail if version mismatch
      eager: false // lazy load
    },
    'react-dom': { singleton: true, requiredVersion: '^18.0.0' },
    zustand: { singleton: true } // share Zustand store
  }
});

// Host with fallbacks and version handling
new ModuleFederationPlugin({
  name: 'shell',
  remotes: {
    search: `promise new Promise(resolve => {
      const script = document.createElement('script');
      script.src = 'https://search.example.com/remoteEntry.js';
      script.onload = () => {
        const proxy = {
          get: (request) => window.search.get(request),
          init: (arg) => {
            try { return window.search.init(arg) } catch(e) { console.log('search init error', e) }
          }
        };
        resolve(proxy);
      };
      script.onerror = () => {
        // Fallback to local search if remote fails
        resolve({
          get: () => () => ({ default: () => <div>Search fallback - remote failed</div> }),
          init: () => {}
        });
      };
      document.head.appendChild(script);
    })`
  },
  shared: { react: { singleton: true }, 'react-dom': { singleton: true }, zustand: { singleton: true } }
});
```

**Advanced Challenges**:

- **Version Mismatch**: Remote uses React 18, host uses React 17, singleton strictVersion true will fail, need ensure same version or use loose versioning
- **Fallbacks**: If remote fails (network, deployment), show fallback UI, not crash whole shell, implement via promise with error handling as above
- **Shared State**: How cart in shell knows about search? Use custom events `window.dispatchEvent(new CustomEvent('search:select', { detail: product }))`, or shared store via Zustand singleton shared, or props via shell, or global event bus
- **CSS Isolation**: Use CSS Modules `import styles from './Search.module.css'` or Scoped CSS in Vue or Shadow DOM in Web Components or Tailwind with prefix `tw-` to avoid conflicts
- **Routing**: Shell owns routing (React Router), micro frontends use memory router or receive route via props, or use single-spa for routing
- **Deployment**: Each micro frontend independent deployment, but need versioned remoteEntry.js (remoteEntry.v1.js, v2) for rollback, or use feature flags to toggle new micro frontend

### 16. State Management Advanced - When to Use What Detailed

**Zustand (Recommended 2025 for client state)**:

```ts
// Simple, 1KB, no boilerplate, no Provider needed
import { create } from 'zustand';
interface CartStore {
  items: CartItem[];
  addItem: (item: CartItem) => void;
  removeItem: (id: string) => void;
  total: () => number;
}
const useCartStore = create<CartStore>((set, get) => ({
  items: [],
  addItem: (item) => set({ items: [...get().items, item] }),
  removeItem: (id) => set({ items: get().items.filter(i => i.id !== id) }),
  total: () => get().items.reduce((sum, i) => sum + i.price * i.quantity, 0)
}));
// Usage
function Cart() {
  const { items, total, addItem } = useCartStore();
  // Only re-renders when items changes, not when other store changes (fine-grained)
}
// Pros: Simple, no Provider, no boilerplate, TypeScript great, middleware for persist, devtools
```

**Redux Toolkit (For large apps with complex logic, time travel)**:

```ts
// More boilerplate but powerful for large apps with complex state logic, middleware, time travel debugging
import { createSlice, configureStore } from '@reduxjs/toolkit';
const cartSlice = createSlice({
  name: 'cart',
  initialState: { items: [] },
  reducers: {
    addItem: (state, action) => { state.items.push(action.payload); },
    removeItem: (state, action) => { state.items = state.items.filter(i => i.id !== action.payload); }
  }
});
const store = configureStore({ reducer: { cart: cartSlice.reducer } });
// Usage with useSelector, useDispatch
// Pros: Time travel, middleware (redux-thunk, redux-saga for complex async), DevTools excellent, predictable
// Cons: Boilerplate more than Zustand, need Provider
```

**TanStack Query (For server state - must separate from client state!)**:

```ts
// Server state is different from client state!
// Server state: Data from API, async, cached, needs sync, stale, shared, e.g. users list, products
// Client state: UI state, sync, local, e.g. modal open, form input, theme

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

// Fetch users - caching, dedup, background refetch, stale-while-revalidate
function Users() {
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['users', { role: 'admin' }], // cache key
    queryFn: () => fetch('/api/users?role=admin').then(r => r.json()),
    staleTime: 1000 * 60 * 5, // 5 min fresh, after that background refetch
    cacheTime: 1000 * 60 * 30, // 30 min cache
    retry: 3,
    refetchOnWindowFocus: true // refetch when window focused
  });
  if (isLoading) return <Spinner />;
  if (error) return <div>Error</div>;
  return data.map(u => <UserCard key={u.id} user={u} />);
}

// Mutation with optimistic update
function CreateUser() {
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: (newUser) => fetch('/api/users', { method: 'POST', body: JSON.stringify(newUser) }).then(r => r.json()),
    onMutate: async (newUser) => {
      // Optimistic update: Immediately update UI before server response
      await queryClient.cancelQueries({ queryKey: ['users'] });
      const previousUsers = queryClient.getQueryData(['users']);
      queryClient.setQueryData(['users'], (old) => [...old, { ...newUser, id: 'temp-id' }]);
      return { previousUsers }; // rollback data
    },
    onError: (err, newUser, context) => {
      // Rollback on error
      queryClient.setQueryData(['users'], context.previousUsers);
    },
    onSettled: () => {
      // Refetch after mutation
      queryClient.invalidateQueries({ queryKey: ['users'] });
    }
  });
  return <button onClick={() => mutation.mutate({ name: 'John' })}>Create</button>
}
```

**Decision**:

- Local UI state (toggle, form input) -> useState / useSignal
- Shared between few components -> Props drilling (if 2-3 levels) or Context (if infrequent updates like theme, user)
- Global client state (cart, theme, auth) frequent updates -> Zustand (simple) or Redux Toolkit (complex)
- Server state (API data) -> TanStack Query (must! separate from client state)
- Form state -> React Hook Form + Zod
- URL state (filters, pagination) -> nuqs or useSearchParams (shareable via URL)

### 17. Testing Frontend Advanced

**Unit Testing with Vitest + React Testing Library**:

```ts
// Vitest - fast, Vite native, Jest compatible
// React Testing Library - test user behavior not implementation

import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import UserCard from './UserCard';

describe('UserCard', () => {
  it('should render user name', () => {
    render(<UserCard user={{ name: 'John' }} />);
    expect(screen.getByText('John')).toBeInTheDocument();
  });
  it('should call onClick when clicked', async () => {
    const onClick = vi.fn();
    render(<UserCard user={{ name: 'John' }} onClick={onClick} />);
    fireEvent.click(screen.getByText('John'));
    expect(onClick).toHaveBeenCalled();
  });
  it('should fetch users', async () => {
    // Mock fetch
    global.fetch = vi.fn(() => Promise.resolve({ json: () => Promise.resolve([{ name: 'John' }]) }));
    render(<UserList />);
    await waitFor(() => expect(screen.getByText('John')).toBeInTheDocument());
  });
});
```

**Component Testing with Storybook + Chromatic (Visual)**:

```ts
// Storybook - isolated component development + visual testing
// Button.stories.tsx
export default { title: 'Button', component: Button };
export const Primary = { args: { label: 'Primary', variant: 'primary' } };
export const Secondary = { args: { label: 'Secondary', variant: 'secondary' } };
// Chromatic - visual regression testing, screenshots each story, detects visual changes
```

**E2E with Playwright (Recommended 2025)**:

```ts
// Playwright - fast, multi-browser, auto wait, great DX
import { test, expect } from '@playwright/test';
test('should login and see dashboard', async ({ page }) => {
  await page.goto('https://app.example.com/login');
  await page.fill('input[name="email"]', 'john@example.com');
  await page.fill('input[name="password"]', 'secret');
  await page.click('button[type="submit"]');
  await expect(page).toHaveURL('https://app.example.com/dashboard');
  await expect(page.locator('text=Welcome John')).toBeVisible();
});
```

## Expanded: Accessibility (a11y) & PWA

### Accessibility

- **Why**: 15% users have disabilities, legal requirement (ADA), SEO, better UX for all
- **WCAG**: Web Content Accessibility Guidelines 2.1 AA standard
- **Practices**:
  - Semantic HTML: <button> not <div onClick>, <nav>, <main>, <header>, <footer>
  - Alt text for images: <img alt="Description" />
  - Keyboard navigation: Tab, Enter, Escape, focus management, focus trap for modals
  - ARIA: aria-label, aria-describedby, aria-hidden, role
  - Color contrast: 4.5:1 for normal text, 3:1 for large
  - Screen reader testing: VoiceOver (Mac), NVDA (Windows)
- **Tools**: axe-core, Lighthouse a11y audit, eslint-plugin-jsx-a11y

### PWA (Progressive Web App)

- **What**: Web app that feels like native app: Installable, offline, push notifications, fast
- **Features**: Service Worker (caching, offline, background sync), Web App Manifest (name, icons, theme), Push API, HTTPS required
- **Pros**: Installable (Add to Home Screen), offline support, push notifications, fast (service worker caching), no app store needed, cross-platform
- **Cons**: iOS support limited (push notifications limited), not full native capabilities (Bluetooth, NFC limited)
- **Use**: E-commerce, news, any web app that benefits from offline + installable
- **Tools**: Workbox (Google library for service worker), next-pwa for Next.js

```js
// Service Worker registration
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').then(reg => console.log('SW registered'));
}
// sw.js - caching
self.addEventListener('install', (e) => {
  e.waitUntil(caches.open('v1').then(cache => cache.addAll(['/','/styles.css','/app.js'])));
});
self.addEventListener('fetch', (e) => {
  e.respondWith(caches.match(e.request).then(cached => cached || fetch(e.request)));
});
```

