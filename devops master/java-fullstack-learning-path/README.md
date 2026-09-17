# ☕⚛️ JAVA FULL STACK — The Complete SDE 3 / MAANG Learning Path

> **From "what is a variable?" to "design a rate limiter that survives a region failover."**
>
> Beginner in **explanation style**. Staff-level in **depth**. Every file is self-contained, every program is explained in its own comments, and every file ends with tasks **and** answers.
>
> **184 files · 9 folders · 1 application that grows the whole way through.**

---

## 📇 How to use this folder

| If you… | Go to |
|---|---|
| are starting today | [`00-MASTER-ROADMAP.md`](./00-MASTER-ROADMAP.md) → then [`01-core-java/`](./01-core-java/) |
| only have ONE day | [`01-core-java/00-ONE-DAY-MASTER-PLAN.md`](./01-core-java/00-ONE-DAY-MASTER-PLAN.md) |
| want to know what each file is for | **this page** — every file has a one-line explanation below |
| are 3 weeks from an interview | [`09-sde3-interview-vault/`](./09-sde3-interview-vault/) |
| want the whole thing at a glance | each folder's `CHEATSHEET.md` |

**The rule for every file in this path:** the body teaches, the tail tests. Practice questions and their full answers are always at the **END** of a file, never inline — so you can read the teaching half without spoiling the practice half.

---

## 🔢 Version anchors — verified **16 September 2026**

⭐ These are checked, not guessed. Every code sample in this path is annotated `// since Java N` against this table.

| Thing | Version | Notes |
|---|---|---|
| **Java — teaching baseline** | ⭐ **21 LTS** | Released Sept 2023. Still the **widest production target** and what most interviewers assume. Support to Sept 2031 (Temurin). Everything here compiles on 21 |
| **Java — current LTS** | **25 LTS** | GA 16 Sept 2025; latest update **25.0.4.1** (18 Aug 2026). Support to Sept 2033 |
| **Java — current non-LTS** | **26** | GA 17 Mar 2026, **EOL Sept 2026**. Adds HTTP/3 in `HttpClient`; *Primitive Types in Patterns* is in its 4th preview (JEP 530) |
| **Java — next** | **27** | Due Sept 2026 (RC now). Re-verify if you read this later |
| **Spring Boot** | **4.1.1** (21 Aug 2026) | Built on **Spring Framework 7.0.9**, Jakarta EE 11. Java **17 minimum**, supports through Java 26. OSS support to 31 Jul 2027 |
| Spring Boot 4.0 | 4.0.8 | ⚠️ **EOS 31 Dec 2026** — don't start here |
| Spring Boot 3.5 | 3.5.16 | ⛔ **EOL 30 Jun 2026** — still common in the wild, so it is taught as a contrast |
| Spring Security | **7.1.1** | |
| Hibernate ORM | **7.4.5.Final** | Standalone line is 7.3.0.Final (Mar 2026); **8.0.0.Beta1** in flight |
| Tomcat (embedded) | **11.0.24** | Servlet 6.1 / Jakarta EE 11 |
| **React** | **19.3.0** (9 Sept 2026) | Adds View Transitions, Fragment Refs, `browser()`, Trusted Types. 19.2 (Oct 2025) added `Activity`, `useEffectEvent`, Performance Tracks |
| React security note | — | ⚠️ **React2Shell** affected 19.0.0–19.2.0; patched in **19.2.1+**. Never ship 19.0.x |
| Node.js | **24 LTS** (Active LTS since Oct 2025) | Node 26 is current; becomes LTS Oct 2026. **Re-verify before the frontend folder** |
| Java 21 → 25 language delta | — | **finalised in 25**: instance `main` methods, compact source files, module import declarations, flexible constructor bodies, scoped values. **Under the hood**: compact object headers, AOT method profiling, generational Shenandoah |

⭐ **The teaching decision, stated honestly:** this path teaches **Java 21 as the baseline** and marks every later addition. Reason: 21 is what your interviewer is running, what most job ads say, and what every framework supports. Teaching 25-only syntax would make you unable to read the codebase you'd actually join. Every feature from 22–26 that matters is still covered — in a dedicated table in `04-ADVANCED-CORE-JAVA.md` — so you can say *"that's Java 25, we're on 21"* in an interview, which is itself a senior signal.

---

## 🧵 The application that runs through all 184 files

⭐ **One app, grown continuously.** You do not learn Spring on a `Todo` class and then throw it away. `shop` starts as a console program in Folder 1 and ends as a containerised, monitored, canary-deployed full-stack system in Folder 8 — the **same** system you already built in the Docker, Kubernetes, Monitoring and CI/CD paths.

| Service | Layer | Language / stack | Port | First appears |
|---|---|---|---|---|
| `shop-ui` | FE | React 19.3 + Vite, nginx | 80 | Folder 2 |
| `shop-api` | BE | **Java 21 + Spring Boot 4.1** | 8080 (+9090 metrics) | ⭐ Folder 1 (as plain Java) |
| `checkout` | BE | Go 1.23 | 9091 | Docker path |
| `order-worker` | BE | Python 3.13 | 9092 | Docker path |
| `payment-mock` | BE | Go 1.23 | 9093 | Docker path |
| `postgres` / `redis` / `rabbitmq` | infra | pinned upstream | 5432 / 6379 / 5672 | Folder 3 |

**Domain:** a small shop. `Product`, `Customer`, `Order`, `OrderLine`, `Payment`. Deliberately boring — boring domain, interesting engineering. That is what real MAANG interviews look like.

| Stage | What `shop` is | Folder |
|---|---|---|
| 1 | A console app: `Product` records in an `ArrayList`, printed with a `for` loop | 01 |
| 2 | Same, but persisted to CSV/JSON via NIO.2 | 01 |
| 3 | Same, but persisted to PostgreSQL via raw JDBC | 01, 03 |
| 4 | A browser UI you built by hand in HTML/CSS/JS, talking to nothing yet | 02 |
| 5 | A React UI, talking to a mock API | 02 |
| 6 | A servlet-based storefront (to *understand* Spring MVC, not to ship) | 04 |
| 7 | JPA entities, relationships, and the N+1 problem you will cause and then fix | 05 |
| 8 | A Spring container with beans, AOP, transactions | 06 |
| 9 | `shop-api` — a real REST service with security, actuator, tests | 07 |
| 10 | ⭐ `shop-ui` + `shop-api` + PostgreSQL + Redis + RabbitMQ, on Kubernetes, monitored, in CI/CD | 08 |

---

# 📂 THE COMPLETE FILE INDEX

**One line per file.** 184 files across 9 folders plus the root.

| Folder | Files | Time |
|---|---|---|
| root | 2 | — |
| `01-core-java/` ⭐ **current focus** | 11 | 55–70 h |
| `02-frontend/` | 82 | 85–110 h |
| `03-jdbc-deep/` | 11 | 14–18 h |
| `04-jsp-servlets/` | 11 | 12–16 h |
| `05-hibernate-jpa/` | 16 | 28–35 h |
| `06-spring-core/` | 14 | 22–28 h |
| `07-spring-boot/` | 15 | 28–35 h |
| `08-fullstack-capstone/` | 11 | 35–45 h |
| `09-sde3-interview-vault/` | 11 | 35–45 h |
| **Total** | **184** | **≈ 320–400 h** |

---

## 📁 Root

| File | One line |
|---|---|
| **`README.md`** | ⭐ **This page.** The master index: one-line explanation for every folder and every file, the version anchors, the app-continuity map, the learning order |
| **`00-MASTER-ROADMAP.md`** | The whole-stack plan — week by week and hour by hour, with the dependency graph between folders, a "short on time" express path, and what to skip without breaking anything later |

---

## 📁 `01-core-java/` — ⭐ BUILD THIS FIRST (11 files)

> **Your current focus.** Everything else in this path assumes you own this folder cold. It is also ~60% of the Java interview.

| File | One line |
|---|---|
| `README.md` | The folder index — one line per file, the reading order, and the Core Java version anchors |
| `00-ONE-DAY-MASTER-PLAN.md` | ⏰ Hour-by-hour plan for all six core files, with a 3-day and a 6-day version, plus an "if the day goes wrong" table |
| **`01-BASICS-AND-TOPIC-MAP.md`** | ⭐ **THE MAP FIRST** — a complete tree of every Core Java topic, each tagged `[MUST KNOW]` / `[SHOULD KNOW]` / `[SDE3 DIFFERENTIATOR]` / `[RARELY ASKED]` with the file that covers it — then the fundamentals from absolute zero: JDK/JRE/JVM, bytecode and the JIT, `javac` → `.class` → `java`, `javap`, the classpath, the `main` signature deconstructed, all 8 primitives, wrapper caches and the `Integer ==` trap, every operator including bitwise, precedence, casting, control flow (old and new `switch`), arrays, method overloading resolution, ⭐⭐ **pass-by-value proven four ways**, `String` immutability and the pool, `static` and initialisation order, stack vs heap, I/O, the toolchain and `jshell` |
| **`02A-CASE-A-oops-complete.md`** | ⭐ **CASE A — EVERY OOP topic, nothing skipped, with exactly FIVE graduated assignments per topic** (reproduce → vary → combine → break → design) and full commented solutions at the end. 20 topics: classes & objects · fields & methods · constructors · initialisation order · inheritance · overriding · overloading · polymorphism & the five `invoke` bytecodes · encapsulation & the 4×4 access matrix · abstraction · interfaces & the diamond · `final` · every `Object` method · immutability · composition over inheritance · inner & nested classes · `enum` · `record` · `sealed` classes · annotations |
| **`02B-CASE-B-lld-for-sde3.md`** | ⭐ **CASE B — LLD + OOP at the SDE 3 bar.** The 25 MAANG LLD problems with timed scripts: requirement gathering, the object model, SOLID (with a violation and a fix per principle), the 12 patterns you actually use, class-diagram notation, extensibility vs simplicity, the "why not a database?" conversation, and how to drive a 45-minute LLD round without being told what to do |
| `03-FILE-HANDLING-AND-IO.md` | Everything about getting bytes in and out: `File` vs `Path`, the NIO.2 API, streams vs readers vs channels, byte vs character and why encodings bite, buffering (and measuring the difference), `try-with-resources` and `AutoCloseable`, serialisation and why `ObjectInputStream` is a security hole, ZIP/GZIP, file watching, memory-mapped files, and the `java.io` Decorator pattern as the canonical composition example |
| `04-ADVANCED-CORE-JAVA.md` | The SDE 3 differentiators: ⭐⭐⭐ **concurrency** (threads, the JMM, `volatile`, `synchronized`, atomics, `java.util.concurrent`, executors, `CompletableFuture`, **virtual threads**), ⭐⭐ **generics** (erasure, wildcards, PECS), **reflection & dynamic proxies**, **lambdas & the Stream API** (lazy evaluation, short-circuiting, parallel-stream traps), **exceptions** (checked vs unchecked honestly), `Optional`, **the JVM** (classloading, memory areas, GC algorithms and tuning), date/time, and **what Java 22→26 changed** |
| `05-JDBC-BASICS-AND-CRUD.md` | JDBC from zero: the driver, the `Connection`, `Statement` vs ⭐ `PreparedStatement` (and the SQL-injection proof), `ResultSet` and its types, **complete CRUD on the `shop` schema**, transactions and `commit`/`rollback`, batch inserts (with the rewriteBatchedStatements benchmark), and the 8 mistakes everyone makes |
| **`06-COLLECTIONS-MASTERY.md`** | ⭐ **"master each"** — every collection, its internals, its complexity table, and its failure mode: the `Collection` hierarchy, `List` (`ArrayList` vs `LinkedList` vs `CopyOnWriteArrayList`), `Set` (`HashSet`/`LinkedHashSet`/`TreeSet`/`EnumSet`), `Map` (⭐⭐⭐ `HashMap` from memory: the hash function, `(n-1) & hash`, treeify at 8, resize, the mutable-key orphaning bug), `LinkedHashMap` and LRU, `TreeMap`, ⭐⭐⭐ `ConcurrentHashMap` (why no locking on read, CAS + `synchronized` bins, the size lie), `Queue`/`Deque`/`PriorityQueue`/`BlockingQueue`, `Iterator` and `fail-fast`, `Comparable` vs `Comparator`, `Spliterator`, sorting internals (TimSort), `Collections` unmodifiable vs `List.of` immutability, and choosing a collection in 10 seconds |
| `07-PROJECTS.md` | The Core Java mini-projects — each 3–5 tasks with answers at the end: console shop · CSV/JSON persistence · a thread-safe in-memory cache · a log analyser · a mini test framework via reflection · a producer/consumer order queue · a rate limiter · an LRU cache from `LinkedHashMap` |
| `08-CHEATSHEET.md` | All of Core Java on one page — every complexity table, every trap, every `// since Java N`, every interview line |

---

## 📁 `02-frontend/` — 6 sub-folders + 15 projects (82 files)

> **Complete frontend, taught to a backend engineer.** Every sub-folder has the same shape: numbered teaching files, an `INTERNALS` file, and a `CHEATSHEET`. The `projects/` folder is where it becomes real — 15 complete React applications, each a different scenario.

### `02-frontend/` root

| File | One line |
|---|---|
| `README.md` | The frontend index — all 82 files, one line each, plus the recommended order (HTML → CSS → DOM → JS → React → projects) |
| `00-ONE-DAY-MASTER-PLAN.md` | ⏰ The frontend sprint plan — and the honest "you cannot learn frontend in a day, here is the 3-week version" |

### `02-frontend/html/` — 10 files

| File | One line |
|---|---|
| `01-FUNDAMENTALS.md` | What HTML actually is, the document tree, `<!DOCTYPE>`, elements vs tags vs attributes, void elements, nesting rules, how the parser recovers from your mistakes |
| `02-TEXT-AND-SEMANTICS.md` | Headings, paragraphs, lists, emphasis, and ⭐ why semantic elements (`article`, `section`, `nav`, `main`) matter for accessibility, SEO and maintainability — not for looks |
| `03-LINKS-MEDIA-EMBEDDING.md` | `a`/`href`/`target`/`rel="noopener"`, images and `srcset`/`sizes`, `picture`, lazy loading, `iframe`, `video`/`audio`, and the security of embedding third-party content |
| `04-FORMS-AND-VALIDATION.md` | Every `input` type, `label` and why `for`/`id` is non-negotiable, the Constraint Validation API, `pattern`, `required`, custom error messages, autocomplete, and what the browser does when you press submit |
| `05-TABLES-LISTS-FIGURES.md` | Accessible data tables (`caption`, `scope`, `headers`), description lists, `figure`/`figcaption`, and when a table is the right layout (data) vs the wrong one (page structure) |
| `06-ACCESSIBILITY.md` | ⭐ The a11y file: the accessibility tree, ARIA and the **first rule of ARIA** (don't use it), roles/states/properties, focus management, keyboard navigation, colour contrast, screen-reader testing, and the audit checklist |
| `07-SEO-AND-METADATA.md` | `head` in full: `title`, meta description, canonical, Open Graph, Twitter cards, structured data (JSON-LD), robots, hreflang — and what actually moves rankings vs what is folklore |
| `08-PERFORMANCE-AND-CRITICAL-RENDER-PATH.md` | ⭐⭐ Where the bytes go: HTML → CSSOM → DOM → render tree → layout → paint → composite; render-blocking resources, `preload`/`prefetch`/`preconnect`/`modulepreload`, font loading, Core Web Vitals (LCP/INP/CLS) and how to hit them |
| `09-INTERNALS-PARSING-AND-REFLOW.md` | ⭐⭐⭐ How Blink actually parses HTML, speculative parsing, why the parser blocks on scripts, `defer` vs `async` vs module, what triggers reflow vs repaint vs composite, and layer promotion |
| `10-CHEATSHEET.md` | Every element, every attribute that matters, the a11y checklist, the performance checklist — one page |

### `02-frontend/css/` — 13 files

| File | One line |
|---|---|
| `01-CASCADE-SPECIFICITY-INHERITANCE.md` | ⭐⭐⭐ The mental model that makes CSS make sense: the cascade's five origins, specificity arithmetic, `!important` and why it loses anyway, inheritance and the `inherit`/`initial`/`unset`/`revert` keywords, `@layer` |
| `02-SELECTORS.md` | Every selector: type/class/id/attribute, combinators, pseudo-classes and pseudo-elements, `:has()` (the parent selector that finally arrived), `:is()`/`:where()`/`:not()` and their specificity differences, and selector performance |
| `03-BOX-MODEL.md` | `content`/`padding`/`border`/`margin`, ⭐ `box-sizing: border-box` and why it is the first line of every stylesheet, margin collapsing (all four rules), `display` types, replaced elements |
| `04-LAYOUT-FLEXBOX.md` | Flexbox completely: main vs cross axis, every `flex-*` property, `flex: 1` deconstructed, alignment, wrapping, order, the 8 layouts you build with it forever, and the bugs (min-width, shrink-to-zero) |
| `05-LAYOUT-GRID.md` | Grid completely: tracks, `fr`, `minmax`, `auto-fill` vs `auto-fit`, named areas, implicit vs explicit grid, `subgrid`, and the ⭐ honest decision table for Grid vs Flexbox |
| `06-POSITIONING-AND-STACKING.md` | `static`/`relative`/`absolute`/`fixed`/`sticky` (and sticky's real behaviour), containing blocks, ⭐ `z-index` and **stacking contexts** — the thing that makes `z-index: 99999` not work |
| `07-RESPONSIVE-AND-CONTAINER-QUERIES.md` | Media queries, mobile-first, fluid typography with `clamp()`, ⭐ **container queries** (`@container`) and why they beat media queries for components, `dvh`/`svh`/`lvh`, the responsive images pattern |
| `08-TYPOGRAPHY-AND-COLOR.md` | Font stacks, `@font-face` and `font-display`, variable fonts, line-height and measure, the colour spaces (`srgb`, `oklch`, `display-p3`), relative colour syntax, and designing a type scale |
| `09-TRANSITIONS-ANIMATIONS-TRANSFORMS.md` | `transition` and its four properties, `@keyframes`, ⭐ `transform` and why it is the only performant way to move things, compositing, `will-change`, the FLIP technique, and respecting `prefers-reduced-motion` |
| `10-CUSTOM-PROPERTIES-AND-FUNCTIONS.md` | CSS variables (and how they differ from Sass variables), the cascade with custom properties, `var()` fallbacks, `calc()`, `min()`/`max()`/`clamp()`, the new colour functions, and theming/dark mode done properly |
| `11-PERFORMANCE-AND-REPAINT.md` | ⭐⭐ What makes CSS slow: selector cost, layout thrashing, forced synchronous layout, paint area, the critical CSS pattern, `contain` and `content-visibility`, and measuring with DevTools' performance panel |
| `12-ARCHITECTURE-BEM-TAILWIND-DESIGN-SYSTEMS.md` | ⭐⭐ How to organise CSS at scale: BEM, ITCSS, CSS Modules, CSS-in-JS (and its runtime cost), ⭐ **Tailwind** honestly, design tokens, and building the `shop` design system you'll use in React |
| `13-CHEATSHEET.md` | Every property that matters, the specificity table, the flex/grid alignment grid, the debugging ladder — one page |

### `02-frontend/dom/` — 10 files

| File | One line |
|---|---|
| `01-THE-TREE.md` | What the DOM is (an object model of the parsed HTML, not the HTML), node types, `Document`/`Element`/`Text`, the tree as a live API, and how it relates to the render tree |
| `02-SELECTING-AND-TRAVERSING.md` | `querySelector`/`querySelectorAll` vs the old `getElementsBy*` (⭐ **live vs static** collections — the classic bug), parent/child/sibling traversal, `closest()`, `matches()`, and iteration |
| `03-CREATING-AND-MUTATING.md` | `createElement`, `appendChild`/`append`, `insertBefore`, `replaceChildren`, removal, ⭐ `DocumentFragment` and why batching matters, `innerHTML` vs `textContent` (and the XSS difference), `cloneNode` shallow vs deep |
| `04-EVENTS-AND-DELEGATION.md` | ⭐⭐ The event model: capture → target → bubble, `addEventListener` options, `event.target` vs `currentTarget`, `preventDefault` vs `stopPropagation` vs `stopImmediatePropagation`, **event delegation** and why it is the pattern, custom events, passive listeners and scroll performance |
| `05-ATTRIBUTES-PROPERTIES-DATASET.md` | ⭐ Attributes vs properties — they are NOT the same thing, the reflection rules, `data-*` and `dataset`, `classList`, and the bugs this distinction causes |
| `06-FORMS-AND-CONSTRAINT-VALIDATION-API.md` | Reading and writing form state, `FormData`, the Constraint Validation API from JS, custom validity, and building a real validation library by hand |
| `07-ASYNC-DOM-MUTATION-OBSERVER-RAF.md` | `requestAnimationFrame` and the frame budget, `IntersectionObserver` (lazy loading, infinite scroll), `MutationObserver`, `ResizeObserver`, and microtask-timed DOM reads |
| `08-PERFORMANCE-REFLOW-REPAINT-VIRTUAL-DOM.md` | ⭐⭐⭐ Layout thrashing (reading then writing then reading), how to batch, `content-visibility`, virtualisation for 100k rows, and **what a virtual DOM actually buys you** — which is not speed, it is *declarative correctness* |
| `09-INTERNALS-PARSING-LIVENESS-SHADOW-DOM.md` | How Blink builds and mutates the tree, style/layout/paint invalidation, live collections under the hood, Shadow DOM and encapsulation, custom elements, and web components vs React |
| `10-CHEATSHEET.md` | Every selection, mutation, traversal and event API — one page |

### `02-frontend/javascript/` — 13 files

| File | One line |
|---|---|
| `01-THE-ENGINE-AND-RUNTIME.md` | V8 vs SpiderMonkey vs JavaScriptCore, what a JS runtime adds (the host: browser APIs, Node), the parse→compile→execute pipeline, and why JS is "weird" — it was designed in 10 days and then frozen for compatibility |
| `02-TYPES-VALUES-COERCION.md` | ⭐⭐⭐ The 8 types, primitives vs objects, `==` vs `===` and the actual coercion algorithm, `null` vs `undefined`, `NaN` (and `Object.is`), truthiness, the `typeof` lies, and why `"1" + 1 === "11"` but `"1" - 1 === 0` |
| `03-FUNCTIONS-SCOPE-CLOSURES.md` | ⭐⭐⭐ Declarations vs expressions vs arrows (and `this`), hoisting, block scope, **closures** — what they really are, the loop-variable trap, closures as the only privacy mechanism JS had for 20 years, memory retention |
| `04-OBJECTS-PROTOTYPES-CLASSES.md` | ⭐⭐⭐ Object internals, property descriptors, the prototype chain drawn, `Object.create`, `class` syntax and **what it actually compiles to**, `super`, private `#fields`, `instanceof` and `Symbol.hasInstance`, and the Java-developer's translation table |
| `05-ARRAYS-AND-ITERATION.md` | Every array method with complexity and mutability marked, `map`/`filter`/`reduce` properly, the iteration protocols (`Symbol.iterator`), generators, spread/rest, destructuring, and `Array.prototype.at`/`findLast`/`toSorted` |
| `06-ASYNCHRONOUS-CALLBACKS-PROMISES-ASYNC-AWAIT.md` | ⭐⭐⭐ Why JS is single-threaded and non-blocking, callbacks and callback hell, the Promise states and the gotchas, `Promise.all`/`allSettled`/`race`/`any`, `async`/`await` and **what it desugars to**, error handling, and the "await in a loop" performance trap |
| `07-EVENT-LOOP-AND-MICROTASKS.md` | ⭐⭐⭐ The call stack, the microtask queue, the macrotask queue, `setTimeout(fn, 0)`, the **exact** ordering rules, and the 15 "what does this print?" programs that separate senior from staff |
| `08-ERRORS-AND-DEFENSIVE-CODING.md` | `try`/`catch`/`finally`, error types, `Error` vs throwing a string, `window.onerror`/`unhandledrejection`, error boundaries' JS-side equivalent, retries with backoff, and validating at the boundary |
| `09-MODULES-BUNDLERS-TOOLCHAIN.md` | ESM vs CommonJS (and the interop mess), `import`/`export`, tree shaking and why it needs ESM, what Vite/webpack/esbuild/Rollup actually do, source maps, `package.json` fields, and the npm dependency model |
| `10-IMMUTABILITY-FUNCTIONAL-PATTERNS.md` | ⭐⭐ Immutability in a mutable-by-default language, `Object.freeze` (shallow only), structural sharing, pure functions, composition, and why React *requires* you to understand this |
| `11-TYPESCRIPT-FOR-JAVA-DEVS.md` | ⭐⭐ TS as the Java developer's homecoming: structural vs nominal typing, generics, unions and narrowing, `unknown` vs `any`, utility types, declaration files, `tsconfig` strictness, and where the type system lies to you |
| `12-INTERNALS-V8-HIDDEN-CLASSES-GC.md` | ⭐⭐⭐ Hidden classes and inline caches, why object shape stability matters, the optimizing/deoptimizing pipeline, generational GC and its pauses, and writing measurably faster JS without micro-optimisation folklore |
| `13-CHEATSHEET.md` | Every method, the coercion table, the event-loop ordering rules, the `this` rules — one page |

### `02-frontend/react/` — 19 files

| File | One line |
|---|---|
| `01-MENTAL-MODEL.md` | ⭐⭐⭐ UI = f(state). What React is and is not, the render model, why "re-render" doesn't mean "re-paint", and the five ideas that make everything else obvious |
| `02-JSX-AND-COMPONENTS.md` | JSX and what Babel turns it into, components as functions, composition, children, fragments, the rules of JSX, and file organisation |
| `03-PROPS-AND-STATE.md` | Props are read-only, state is local and asynchronous-in-effect, lifting state up, controlled vs uncontrolled, and ⭐ the "where should this state live?" decision tree |
| `04-EVENTS-AND-FORMS.md` | Synthetic events, controlled inputs, the full form lifecycle, validation, and building a reusable `Field` component |
| `05-CONDITIONAL-RENDERING-AND-LISTS.md` | Every conditional pattern (and the `&&` with `0` bug), rendering lists, ⭐⭐ **the `key` prop** — what it is for, why index-as-key breaks, and reconciliation |
| `06-USESTATE-USEEFFECT-DEEP.md` | ⭐⭐⭐ The two hooks that cause 90% of React bugs: batching, stale closures, the updater function, `useEffect`'s real purpose (synchronising with external systems), the dependency array, cleanup, StrictMode's double-invoke, and the 8 effects you should delete |
| `07-USEREF-USEMEMO-USECALLBACK.md` | `useRef` for mutable values *and* DOM nodes, `useMemo`/`useCallback` and ⭐⭐ **when they are a pessimisation**, referential equality and why it matters to `React.memo` |
| `08-CUSTOM-HOOKS.md` | Extracting logic, the rules of hooks and *why* they exist (hook order), composing hooks, and building 6 real ones: `useFetch`, `useDebounce`, `useLocalStorage`, `useMediaQuery`, `usePrevious`, `useInterval` |
| `09-CONTEXT-AND-STATE-ARCHITECTURE.md` | ⭐⭐ Context, its performance problem, when it is the right tool (theme, auth, i18n) and when it is not (frequent updates), then the state-architecture decision: local → context → reducer → external store |
| `10-ROUTER.md` | React Router: routes, nesting, layouts, params, loaders and actions (the data-router model), redirects, 404s, protected routes, and code-splitting per route |
| `11-DATA-FETCHING-TANSTACK-QUERY.md` | ⭐⭐⭐ Why `useEffect` is the wrong place to fetch: caching, deduplication, revalidation, pagination, optimistic updates, `TanStack Query` completely, and the `shop-api` integration |
| `12-FORMS-REACT-HOOK-FORM-ZOD.md` | Uncontrolled-by-default forms, `react-hook-form`, schema validation with `zod`, error display, arrays of fields, and the accessible form pattern |
| `13-REDUCER-AND-USE-REDUX-WHEN.md` | `useReducer` and when it beats `useState`, the reducer pattern from Java's perspective, `Redux Toolkit` honestly — and the ⭐ answer to "do you still need Redux in 2026?" |
| `14-ERROR-BOUNDARIES-SUSPENSE-LAZY.md` | Error boundaries (and why they are still class components), `Suspense`, `lazy` and code splitting, `Activity` (React 19.2), and building a resilient shell |
| `15-PERFORMANCE-AND-RECONCILIATION.md` | ⭐⭐⭐ What triggers a render, the reconciliation algorithm, `React.memo`/`useMemo`/`useCallback` as a system, list virtualisation, bundle analysis, React Performance Tracks, and profiling with the DevTools profiler |
| `16-TESTING.md` | ⭐⭐ Vitest + React Testing Library: the philosophy (test behaviour, not implementation), queries by priority, user-event, mocking, MSW for API mocking, and Playwright for e2e |
| `17-INTERNALS-FIBER-CONCURRENT-REACT-COMPILER.md` | ⭐⭐⭐ Fiber and the work loop, time slicing, lanes and priority, the concurrent renderer, `useTransition`/`useDeferredValue`/`useSyncExternalStore`, Server Components and what they actually change, `View Transitions` (19.3), and the **React Compiler** — automatic memoisation |
| `18-CHEATSHEET.md` | Every hook with its signature and trap, the rules of hooks, the performance checklist, the debugging ladder — one page |
| `19-PROJECTS-INDEX.md` | The index of the 15 projects below, with a "which project teaches which skill" matrix and a suggested order |

### `02-frontend/projects/` — ⭐ 15 complete React applications, one file each

> Each is a **full scenario**: requirements, architecture, every component, every hook, the API contract, the tests, and tasks with answers at the end. Together they cover the complete frontend.

| File | Scenario | What it teaches |
|---|---|---|
| `P01-DASHBOARD-ANALYTICS.md` | 📊 An analytics dashboard with charts, filters, date ranges and live refreshing | layout systems, data fetching & caching, charting, derived state, responsive grids |
| `P02-E-COMMERCE-STOREFRONT.md` | 🛒 **The `shop-ui` you deploy in Folder 8** — catalogue, search, filters, cart, checkout | the full app: routing, cart state, optimistic updates, API integration, SEO |
| `P03-AUTH-AND-PROTECTED-ROUTES.md` | 🔐 Login, signup, JWT + refresh tokens, protected routes, role-based UI | auth flows, token storage trade-offs, route guards, context, 401 handling |
| `P04-REAL-TIME-CHAT-WEBSOCKET.md` | 💬 Real-time chat over WebSocket with presence, typing indicators and reconnection | WebSockets, reconnection with backoff, message ordering, refs, performance under churn |
| `P05-INFINITE-FEED-AND-VIRTUALISATION.md` | 📜 An infinite-scroll feed with 100k items at 60 fps | `IntersectionObserver`, windowing, pagination, scroll restoration, memory |
| `P06-MULTI-STEP-WIZARD-FORM.md` | 🧭 A 6-step booking wizard with validation, back-navigation and a draft save | complex form state, reducers, validation, persistence, accessible step patterns |
| `P07-FILE-UPLOAD-DRAG-DROP-PROGRESS.md` | 📤 Drag-and-drop multi-file upload with progress, chunking and retry | the File API, `XMLHttpRequest`/`fetch` progress, AbortController, chunked upload |
| `P08-DESIGN-SYSTEM-COMPONENT-LIBRARY.md` | 🎨 Build and publish the `shop` component library: tokens, Button, Input, Modal, Toast, Table | composition, `forwardRef`/ref-as-prop, a11y, theming, documentation, packaging |
| `P09-ADMIN-CRUD-DATATABLE.md` | 🗂️ An admin panel: sortable/filterable/paginated server-side table with inline edit | server-driven state, URL-as-state, debounce, optimistic mutations, permissions |
| `P10-BOOKING-CALENDAR.md` | 📅 A calendar with drag-to-create, timezones, recurrence and conflict detection | date/time handling, drag interactions, complex derived state, virtualised grids |
| `P11-OFFLINE-FIRST-PWA.md` | 📴 An offline-first app: service worker, IndexedDB, background sync, install prompt | service workers, caching strategies, IndexedDB, sync conflicts, PWA manifest |
| `P12-SSR-AND-SEO-NEXT.md` | 🌐 The storefront re-rendered server-side: SSR, SSG, ISR, streaming, metadata | hydration, server components, data fetching on the server, Core Web Vitals, SEO |
| `P13-ACCESSIBILITY-AUDIT-REBUILD.md` | ♿ Take an inaccessible app, audit it, and fix every issue to WCAG 2.2 AA | the a11y tree, focus management, ARIA done right, screen-reader testing, contrast |
| `P14-PERFORMANCE-RESCUE.md` | 🚑 A deliberately slow app: profile it, find the 9 problems, fix them, measure the win | the profiler, bundle analysis, render counts, memoisation, code splitting, LCP/INP/CLS |
| `P15-MICRO-FRONTEND-AND-MODULE-FEDERATION.md` | 🧩 Two teams, two deployables, one page: Module Federation, shared deps, isolation | micro-frontends honestly, version skew, shared state boundaries, build orchestration |

---

## 📁 `03-jdbc-deep/` — production JDBC (11 files)

> Folder 1 taught you JDBC. This folder teaches you JDBC the way it exists in a real service.

| File | One line |
|---|---|
| `README.md` | The folder index and the "why raw JDBC still matters in a Hibernate world" argument |
| `00-ONE-DAY-MASTER-PLAN.md` | ⏰ Hour-by-hour plan for this folder |
| `01-JDBC-ARCHITECTURE-AND-DRIVERS.md` | The four driver types (and why only Type 4 survived), the SPI and `DriverManager` vs `DataSource`, driver versions vs server versions, and what happens on `getConnection()` |
| `02-CONNECTIONS-AND-POOLING.md` | ⭐⭐⭐ Why pooling exists (the TCP + auth + session cost, measured), HikariCP completely and its settings explained, pool sizing arithmetic, leak detection, and the "connection pool exhausted" incident |
| `03-STATEMENTS-PREPARED-CALLABLE-BATCH.md` | The three statement types, ⭐ server-side vs client-side prepared statements, `rewriteBatchedStatements`, batch sizing benchmarks, stored procedures honestly, and statement caching |
| `04-RESULTSETS-AND-MAPPING.md` | ResultSet types and concurrency, forward-only streaming for huge results, `fetchSize` and the MySQL `Integer.MIN_VALUE` trick, the row-mapper pattern, and mapping to records |
| `05-TRANSACTIONS-AND-ISOLATION.md` | ⭐⭐⭐ ACID, the four isolation levels, and the **three anomalies** (dirty read, non-repeatable read, phantom) demonstrated with two real connections; `READ COMMITTED` vs `REPEATABLE READ` in PostgreSQL vs MySQL; savepoints; distributed transactions and why 2PC is a trap |
| `06-METADATA-AND-DYNAMIC-SQL.md` | `DatabaseMetaData`, generating code from a schema, building dynamic `WHERE` clauses **safely** (the parameter-binding pattern), and the SQL-injection audit |
| `07-MIGRATIONS-FLYWAY-LIQUIDBASE.md` | ⭐⭐ Schema versioning, Flyway vs Liquibase, naming conventions, **expand/contract migrations** for zero-downtime deploys, checksums, and the migration that takes a lock and brings down prod |
| `08-TESTING-TESTCONTAINERS.md` | ⭐⭐ Why H2 is a lie, Testcontainers with real PostgreSQL, `@ServiceConnection`, fixtures, transactional test rollback vs truncation, and testing concurrency bugs |
| `09-PROJECTS.md` | The projects: a repository layer from scratch · a connection-pool tuner · a migration runner · a slow-query detector · a sharded key generator |
| `10-CHEATSHEET.md` | Every JDBC type, the isolation/anomaly matrix, the HikariCP settings, the migration rules — one page |

---

## 📁 `04-jsp-servlets/` — the web tier (11 files)

> ⭐ **Learned to UNDERSTAND Spring MVC, not to build new products.** Nobody ships JSP in 2026. Every Spring annotation you will ever use is a wrapper around something in here, and interviewers ask about the underlying mechanism to see whether you know what your framework is doing.

| File | One line |
|---|---|
| `README.md` | The folder index, and an honest statement of why this folder exists and how much time it deserves |
| `00-ONE-DAY-MASTER-PLAN.md` | ⏰ Hour-by-hour plan |
| `01-LIFECYCLE.md` | ⭐⭐⭐ The servlet lifecycle: load → `init` → `service` → `destroy`, one instance many threads, why instance fields are a concurrency bug, `ServletConfig` vs `ServletContext`, and `web.xml` vs annotations |
| `02-REQUEST-RESPONSE.md` | The `HttpServletRequest`/`Response` objects completely, parameters, headers, bodies, forwarding vs redirecting (⭐ the classic interview question), and how a URL becomes a servlet |
| `03-SESSION-AND-STATE.md` | ⭐⭐ HTTP is stateless; here are the five ways to add state: cookies, URL rewriting, hidden fields, sessions, tokens. `HttpSession`, session fixation, sticky sessions, and why JWT is not a session |
| `04-FILTERS-LISTENERS.md` | The filter chain, filter ordering, and ⭐ **this is exactly what a Spring `Interceptor` and a Spring Security `FilterChainProxy` are**; context/request/session listeners |
| `05-JSP-EL-JSTL.md` | How a JSP becomes a servlet (and reading the generated Java), EL expressions, JSTL, the standard taglib, and why templating moved to the client |
| `06-MVC-MODEL2.md` | ⭐⭐ Model 2 / front controller — build one by hand in 80 lines, and then recognise every piece of it inside `DispatcherServlet` |
| `07-SECURITY.md` | The servlet security model, `security-constraint`, container auth, and the OWASP Top 10 as it appears in a servlet app: XSS, CSRF, SQLi, session hijacking, path traversal |
| `08-PROJECT-SHOP-STOREFRONT.md` | 🏗️ **The project**: a servlet+JSP storefront for `shop` — catalogue, cart, checkout — front controller, filters, DAO layer, then a side-by-side of "this in Spring MVC" |
| `09-CHEATSHEET.md` | The lifecycle, every request/response method, forward vs redirect, the filter chain — one page |

---

## 📁 `05-hibernate-jpa/` — JPA + Hibernate + Spring Data (16 files)

| File | One line |
|---|---|
| `README.md` | The folder index and the JPA-vs-Hibernate-vs-Spring-Data layering explained |
| `00-ONE-DAY-MASTER-PLAN.md` | ⏰ Hour-by-hour plan |
| `01-JPA-VS-HIBERNATE.md` | ⭐ The spec vs the implementation, `persistence.xml` vs `EntityManagerFactory` bootstrapping, Jakarta namespace migration, and the other providers |
| `02-PERSISTENCE-CONTEXT.md` | ⭐⭐⭐ **The single most important file in this folder.** The first-level cache, managed/detached entities, the flush, dirty checking, `EntityManager` lifecycle, and every bug that comes from not understanding it |
| `03-ENTITY-LIFECYCLE.md` | ⭐⭐ transient → managed → detached → removed, the transitions drawn, identifier generation strategies (`IDENTITY` vs `SEQUENCE` vs `TABLE` and why `IDENTITY` breaks batch inserts), `@Version` optimistic locking |
| `04-MAPPING.md` | Every mapping: `@Entity`/`@Table`/`@Column`, embedded, enums (⭐ `ORDINAL` is a data-corruption bug), temporal types, converters/`AttributeConverter`, inheritance strategies (`SINGLE_TABLE`/`JOINED`/`TABLE_PER_CLASS` with the trade-offs), and why **records cannot be entities** |
| `05-RELATIONSHIPS.md` | ⭐⭐⭐ `@OneToMany`/`@ManyToOne`/`@OneToOne`/`@ManyToMany`, the owning side, bidirectional consistency, cascade types, orphan removal, and the 7 relationship bugs that appear in production |
| `06-FETCHING-AND-THE-N-PLUS-1.md` | ⭐⭐⭐ **The most-asked Hibernate question.** LAZY vs EAGER, how lazy loading actually works (proxies), the N+1 demonstrated and then fixed five ways: `JOIN FETCH`, `@EntityGraph`, batch size, DTO projection, and pagination — plus how to *detect* it automatically |
| `07-QUERIES.md` | JPQL/HQL, criteria API, ⭐ native queries and their costs, named queries, DTO projections, pagination, and `@Query` in Spring Data |
| `08-TRANSACTIONS-AND-LOCKING.md` | ⭐⭐⭐ `@Transactional` and the proxy (why self-invocation silently does nothing), propagation levels with a scenario each, read-only transactions, pessimistic vs optimistic locking, and the lost-update problem |
| `09-CACHING.md` | ⭐⭐ The three cache levels: persistence context (L1), second-level (L2) and query cache — what each caches, when L2 is worth it (rarely), and how to invalidate it correctly |
| `10-PERFORMANCE.md` | ⭐⭐⭐ Making Hibernate fast: batch inserts/updates, `StatelessSession`, fetch tuning, read-only, avoiding `save` on detached graphs, SQL logging, and the 10 metrics that tell you it is slow |
| `11-SPRING-DATA-JPA.md` | ⭐⭐ Repository interfaces, derived query methods (and their limits), `@Query`, projections, `Specification`, auditing, pagination/sorting, and the traps (`getOne` vs `getReferenceById` vs `findById`) |
| `12-TESTING.md` | `@DataJpaTest` vs `@SpringBootTest`, Testcontainers, `@Sql` fixtures, asserting the generated SQL, and testing lazy-loading behaviour without a session |
| `13-PROJECTS.md` | The projects: the full `shop` persistence layer · a reporting service with DTO projections · an audit-trail entity · a multi-tenant schema · a migration from raw JDBC to JPA |
| `14-CHEATSHEET.md` | Every annotation, the lifecycle diagram, the fetch decision table, the propagation table — one page |

---

## 📁 `06-spring-core/` — IoC, DI, AOP, transactions, MVC (14 files)

| File | One line |
|---|---|
| `README.md` | The folder index, and why you learn Spring *without* Boot first |
| `00-ONE-DAY-MASTER-PLAN.md` | ⏰ Hour-by-hour plan |
| `01-IOC-AND-DI.md` | ⭐⭐⭐ Inversion of Control and Dependency Injection from zero: what problem it solves, the three injection styles (constructor wins, and here is the proof), the container, `ApplicationContext`, and beans as objects-with-a-manager |
| `02-BEAN-LIFECYCLE.md` | ⭐⭐⭐ Instantiate → populate → `BeanNameAware` → `BeanPostProcessor` before → `@PostConstruct` → `InitializingBean` → `init-method` → post-process after → ready → `@PreDestroy` → destroy. The full sequence, with a program that prints every step |
| `03-SCOPES-AND-AUTOWIRING.md` | singleton/prototype/request/session/application, ⭐ the singleton-holding-a-prototype bug and its three fixes, `@Autowired` resolution, `@Qualifier`/`@Primary`, and circular dependencies (why constructor injection makes them fail fast — which is a feature) |
| `04-CONFIGURATION.md` | XML vs `@Configuration` vs `@ComponentScan` vs `@Bean`, **full vs lite mode** (⭐ CGLIB proxying of `@Configuration`, and what breaks in lite mode), profiles, `@PropertySource`, `Environment`, and conditional beans |
| `05-AOP.md` | ⭐⭐⭐ Aspect-oriented programming: advice types, pointcut expressions, **JDK dynamic proxy vs CGLIB** and when each is chosen, the self-invocation problem, ordering aspects, and the 6 things AOP is genuinely good for |
| `06-TRANSACTIONS.md` | ⭐⭐⭐ `@Transactional` in depth: the proxy, propagation (all seven with a scenario), isolation, rollback rules (⭐ checked exceptions do NOT roll back by default), read-only, and the 9 ways it silently does nothing |
| `07-SPRING-MVC.md` | ⭐⭐ `DispatcherServlet` request-by-request, handler mapping, `@Controller`/`@RestController`, `@RequestMapping` and its variants, argument resolvers, `HttpMessageConverter` and Jackson, `@ControllerAdvice` and exception handling, interceptors, and validation |
| `08-DATA-ACCESS.md` | `JdbcTemplate`, exception translation (⭐ the whole point: checked `SQLException` → unchecked `DataAccessException`), `DataSource` configuration, and how Spring manages the connection/transaction boundary |
| `09-TESTING.md` | ⭐⭐ `@SpringJUnitConfig`, `Mockito` with Spring, `@MockBean` vs `@SpyBean` vs constructor-injected mocks, `MockMvc`, slices, and what to unit test vs integration test |
| `10-PATTERNS-INSIDE-SPRING.md` | ⭐⭐ The GoF patterns Spring is built from — Factory, Builder, Singleton (⭐ and how it differs from the GoF one), Proxy, Template Method, Strategy, Observer, Adapter, Decorator — each located in real Spring source |
| `11-PROJECTS.md` | The projects: a container from scratch (60 lines, and suddenly `@Autowired` is not magic) · an AOP audit logger · a transactional service · a mini MVC framework |
| `12-CHEATSHEET.md` | Every annotation, the bean lifecycle, the propagation table, the AOP pointcut syntax — one page |

---

## 📁 `07-spring-boot/` — 15 files

| File | One line |
|---|---|
| `README.md` | The folder index and the Boot 3.x → 4.x migration notes |
| `00-ONE-DAY-MASTER-PLAN.md` | ⏰ Hour-by-hour plan |
| `01-WHAT-BOOT-ACTUALLY-DOES.md` | ⭐⭐ The three things and nothing more: auto-configuration, starters, and the embedded server. `@SpringBootApplication` deconstructed, the `spring.factories`/`AutoConfiguration.imports` mechanism, conditionals, and how to see it all with `--debug` |
| `02-CONFIGURATION.md` | ⭐⭐ `application.yml` and the **externalised configuration order** (17 sources, ranked), profiles, `@ConfigurationProperties` vs `@Value`, relaxed binding, validation with `@Validated`, config servers, and type-safe config |
| `03-WEB-AND-REST.md` | Building `shop-api`: controllers, DTOs vs entities (⭐ never expose an entity), validation, error handling with `@ControllerAdvice`, `ProblemDetail` (RFC 7807), content negotiation, HATEOAS honestly, versioning, and OpenAPI/Swagger |
| `04-DATA.md` | Spring Data JPA in Boot, Flyway integration, ⭐ the repository/service/controller layering, transactions in a web request, pagination, and the `shop` schema end to end |
| `05-SECURITY.md` | ⭐⭐⭐ Spring Security 7: the filter chain (and why it is 15 filters), `SecurityFilterChain` beans, authentication vs authorisation, `UserDetailsService`, password encoding, ⭐ **JWT done properly**, OAuth2/OIDC resource server, CSRF (and when to disable it), CORS, method security, and the 10 misconfigurations that cause breaches |
| `06-ACTUATOR-AND-OBSERVABILITY.md` | ⭐⭐ Every actuator endpoint and which ones you must never expose, health indicators, Micrometer metrics, ⭐ **OpenTelemetry tracing**, structured logging, Prometheus scraping, and the handoff to the monitoring learning path |
| `07-TESTING.md` | ⭐⭐ `@SpringBootTest` and its web environments, `@WebMvcTest`/`@DataJpaTest`/`@JsonTest` slices, `TestRestTemplate`/`WebTestClient`, Testcontainers with `@ServiceConnection`, `@MockitoBean` (Boot 3.4+), testcontainers reuse, and the test pyramid for a Boot service |
| `08-DEPLOYMENT.md` | ⭐⭐ The layered jar and why it makes Docker builds 100× faster, ⭐ the Dockerfile (JRE base, non-root, `MaxRAMPercentage`, graceful shutdown), Kubernetes probes mapped to actuator, Helm values, config injection, and the handoff to the Docker/K8s/CI-CD paths |
| `09-MESSAGING-CACHING-BATCH.md` | RabbitMQ/Kafka with Spring, `@RabbitListener`/`@KafkaListener`, retry and dead-letter queues, idempotent consumers, Redis caching with `@Cacheable` (and its proxy traps), Spring Batch, and `@Scheduled` |
| `10-WEBFLUX-VS-VIRTUAL-THREADS.md` | ⭐⭐⭐ The 2026 concurrency question answered: reactive (WebFlux, Project Reactor, backpressure) vs **virtual threads** (Java 21+). Benchmarks, when each wins, the blocking-call trap in reactive code, structured concurrency, and ⭐ the honest verdict for most teams |
| `11-MICROSERVICES-HONESTLY.md` | ⭐⭐ When a monolith is right (usually), service boundaries, the distributed-systems tax (network, consistency, observability, deployment), resilience (timeouts, retries, circuit breakers, bulkheads), Saga vs 2PC, and the questions to ask before you split |
| `12-PROJECTS.md` | The projects: `shop-api` complete · an auth service · a notification worker · a rate-limited public API · a batch report job · a resilient service with circuit breakers |
| `13-CHEATSHEET.md` | Every starter, every property that matters, every annotation, the security filter chain, the deployment checklist — one page |

---

## 📁 `08-fullstack-capstone/` — ⭐⭐ the centrepiece (11 files)

> **React + Spring Boot + PostgreSQL + Redis + RabbitMQ**, containerised, on Kubernetes, monitored, in CI/CD — plugging directly into your four existing learning paths. This is the project you talk about in the interview.

| File | One line |
|---|---|
| `README.md` | The capstone index, the definition of done, and how it connects to the Docker/K8s/Monitoring/CI-CD folders |
| `00-ONE-DAY-MASTER-PLAN.md` | ⏰ The capstone plan — and the realistic 2-week version |
| `01-ARCHITECTURE.md` | ⭐⭐⭐ The system design: the C4 diagrams, the service boundaries and *why* they are there, synchronous vs asynchronous calls, the data model, consistency boundaries, failure modes, and the ADRs (architecture decision records) written as if for a real team |
| `02-BACKEND.md` | Build `shop-api` end to end: domain, persistence, services, REST contract, validation, security, transactions, caching, messaging, observability, tests |
| `03-FRONTEND.md` | Build `shop-ui` end to end: design system, routing, data layer, cart state, auth, forms, accessibility, performance budget, tests |
| `04-INTEGRATION.md` | ⭐⭐ The contract between them: OpenAPI-first design, generated TypeScript types from the Java DTOs, CORS, error mapping, pagination/filter conventions, versioning, and the contract tests that prove they agree |
| `05-SECURITY.md` | Threat-model the whole system: OWASP Top 10 across both tiers, the auth flow end to end, secrets management, dependency scanning, image signing, and the security test suite |
| `06-OBSERVABILITY.md` | ⭐⭐ The three pillars wired together: structured logs with correlation IDs across FE→BE→worker, Micrometer metrics, distributed traces spanning HTTP and AMQP, dashboards, and the SLOs + alerts |
| `07-DEPLOYMENT.md` | ⭐⭐ Dockerfiles and compose for local, the Kubernetes manifests, Helm chart, ingress, secrets, the CI pipeline, the GitOps CD path, canary rollout, and the rollback drill |
| `08-PROJECT-TASKS-AND-ANSWERS.md` | ⭐ **The tasks.** 12 numbered requirements with a definition of done each, and the complete answers at the **END** of the file |
| `09-CHEATSHEET.md` | The whole capstone on one page: the architecture, every command, every gotcha, and the 5-minute interview pitch |

---

## 📁 `09-sde3-interview-vault/` — ⭐⭐ the MAANG layer (11 files)

> Everything above teaches you the craft. This folder teaches you the **interview** — which is a different skill with different rules.

| File | One line |
|---|---|
| `README.md` | The vault index, the interview loop structure at each MAANG company, and a 4-week preparation plan |
| `01-JAVA-DEEP-DIVE-300.md` | ⭐ **300 Java questions with model answers** at SDE 3 depth — organised by topic, each with the follow-up the interviewer will ask and its answer |
| `02-LLD-QUESTION-BANK.md` | ⭐⭐ **The 25 MAANG LLD problems** with timed 45-minute scripts: parking lot, elevator, bookmyshow, rate limiter, cache, notification service, ride sharing, splitwise, snake & ladder, hotel management, and 15 more — each with requirement gathering, the object model, the pattern choices and the trade-off conversation |
| `03-HLD-FOR-JAVA-DEVS.md` | ⭐⭐⭐ System design from the Java seat: URL shortener, news feed, chat, payments, search autocomplete, video streaming — with the *Java-specific* decisions (threading model, connection pools, serialisation, JVM memory) that most candidates never mention and every interviewer loves |
| `04-CONCURRENCY-INTERVIEWS.md` | ⭐⭐⭐ **The hardest round, isolated.** The JMM, happens-before, the classic problems (producer/consumer, reader/writer, dining philosophers), deadlock detection and prevention, lock-free data structures, `CompletableFuture`, virtual threads, and 20 timed problems with solutions |
| `05-COLLECTIONS-AND-INTERNALS.md` | ⭐⭐⭐ `HashMap` and `ConcurrentHashMap` **from memory**: draw the array, the bucket, the treeify transition, the resize, the CAS loop. Plus `ArrayList` vs `LinkedList` internals, `TreeMap` red-black tree, and the 40 "what does this print?" programs |
| `06-JVM-GC-PERFORMANCE.md` | ⭐⭐⭐ The staff-level round: classloading, memory areas, every GC algorithm (Serial/Parallel/G1/ZGC/Shenandoah) with its pause profile, GC tuning, JIT and C2, escape analysis, profiling with JFR/async-profiler, flame graphs, and a full latency-investigation walkthrough |
| `07-SPRING-INTERVIEWS.md` | ⭐⭐ The framework-depth round: bean lifecycle, the proxy, `@Transactional` failure modes, auto-configuration internals, security filter chain, circular dependencies, Boot vs plain Spring, and "when would you NOT use Spring?" |
| `08-BEHAVIOURAL-SDE3.md` | ⭐⭐⭐ **The SDE 3 bar.** Leadership principles decoded, the STAR-plus-impact format, 40 questions with model answers, the "scope" and "ambiguity" dimensions that separate L5 from L6, and how to talk about disagreement, failure and influence without authority |
| `09-WHAT-HAPPENS-WHEN.md` | ⭐⭐ The classic openers answered end to end: "what happens when you type a URL and press enter?" (DNS → TCP → TLS → HTTP → server → framework → ORM → DB → response → render), "what happens when you run `java Foo`?", "what happens when a Spring bean is created?", "what happens when you commit a row?" |
| `10-MOCK-INTERVIEW-SCRIPTS.md` | ⭐⭐ **Six full 45-minute rounds, scripted** — the interviewer's questions, the pauses, the follow-ups, and a model candidate answer for each beat: one LLD, one HLD, one concurrency, one Java deep-dive, one debugging/performance, one behavioural |

---

## 🗺️ Learning order and dependencies

```
                         ┌─────────────────────────┐
                         │  01-core-java  ⭐ START  │
                         │  01 → 02A → 02B → 06 →   │
                         │  03 → 05 → 04 → 07       │
                         └───────────┬─────────────┘
                                     │ nothing works without this
              ┌──────────────────────┼──────────────────────┐
              ▼                      ▼                      ▼
   ┌────────────────────┐  ┌──────────────────┐  ┌────────────────────┐
   │  02-frontend       │  │  03-jdbc-deep    │  │  04-jsp-servlets   │
   │  html→css→dom→js   │  │  (needs 01/05)   │  │  (needs 01)        │
   │  →react→projects   │  └────────┬─────────┘  └─────────┬──────────┘
   └─────────┬──────────┘           │                      │
             │                      └──────────┬───────────┘
             │                                 ▼
             │                      ┌──────────────────────┐
             │                      │  05-hibernate-jpa    │
             │                      │  (needs 03)          │
             │                      └──────────┬───────────┘
             │                                 ▼
             │                      ┌──────────────────────┐
             │                      │  06-spring-core      │
             │                      │  (needs 05)          │
             │                      └──────────┬───────────┘
             │                                 ▼
             │                      ┌──────────────────────┐
             └─────────────────────▶│  07-spring-boot      │
                     (needs both)   │  (needs 06 + 02)     │
                                    └──────────┬───────────┘
                                               ▼
                                    ┌──────────────────────┐
                                    │ 08-fullstack-capstone│
                                    │  + the Docker / K8s / │
                                    │    Monitoring / CI-CD │
                                    │    learning paths     │
                                    └──────────┬───────────┘
                                               ▼
                                    ┌──────────────────────┐
                                    │ 09-interview-vault   │  ← start this in
                                    │  (any time, really)  │     PARALLEL, not
                                    └──────────────────────┘     at the end
```

⭐ **Two pieces of non-obvious advice:**

1. **Start `09-sde3-interview-vault/` in week 2, not at the end.** Read `01-JAVA-DEEP-DIVE-300.md` *before* you know the answers. It tells you what "done" looks like, which changes how you read everything else. Then return to it every week.
2. **Do not skip `04-jsp-servlets/` because it is obsolete.** It is short (12–16 h) and it is the only place you will see what `DispatcherServlet`, `Filter`, `HandlerInterceptor` and the servlet lifecycle actually are. When an interviewer asks *"what does `@Transactional` proxy?"* the answer is a mechanism you can only picture if you have written the un-magicked version once.

### ⚡ The express path — if you have 6 weeks, not 16

| Priority | Do | Skip | Why |
|---|---|---|---|
| 1 | `01-core-java/` in full | nothing | it is 60% of the interview and 100% of the prerequisite |
| 2 | `09-sde3-interview-vault/01`, `02`, `04`, `05`, `06` | `03`, `07`, `09`, `10` (for now) | LLD + concurrency + internals are the differentiating rounds |
| 3 | `05-hibernate-jpa/02`, `05`, `06`, `08` | the rest | persistence context, relationships, N+1, transactions — the four that get asked |
| 4 | `06-spring-core/01`, `02`, `05`, `06` | the rest | IoC/DI, bean lifecycle, AOP, transactions |
| 5 | `07-spring-boot/01`, `03`, `05`, `08` | the rest | auto-config, REST, security, deployment |
| 6 | `02-frontend/javascript/02`, `03`, `06`, `07` + `react/01`, `03`, `05`, `06`, `11` | the rest | enough frontend to be credible as full stack |
| 7 | `08-fullstack-capstone/01`, `02`, `08` | the rest | one project you can talk about for 20 minutes |
| — | `03-jdbc-deep/02`, `05` | the rest | pooling and isolation are the two that get asked |
| — | `04-jsp-servlets/01`, `06` | the rest | lifecycle + Model 2, so Spring MVC isn't magic |

⛔ **What you must never skip**, however short on time you are: `01-core-java/02A` (OOP complete), `01-core-java/06` (collections), `02B` (LLD), `04` (concurrency), `05-hibernate-jpa/06` (N+1), `06-spring-core/06` (transactions), `07-spring-boot/05` (security). Those seven files are, on their own, most of a Java SDE interview.

---

## 📐 The house rules (every file obeys these)

| # | Rule |
|---|---|
| 1 | **Beginner-first, SDE3-deep.** Every topic runs `WHAT → WHY → HOW → ⭐ TRAP`, then internals, then the production failure mode, then 🔑 the interview line |
| 2 | **Every file is self-contained.** Cross-references are welcome; dependencies are not |
| 3 | ⭐ **Every program is explained in its comments** — a `WHAT / WHY / OUTPUT / JAVA` header block, then WHY-not-WAT comments on the non-obvious lines, then an `── OUTPUT ──` block with the exact console output |
| 4 | **Tasks and answers go at the END**, behind a `<a name="tasks--answers">` anchor. Never inline. An answer never appears before its question |
| 5 | **No placeholder code.** Package, imports, class, `main` — complete and compilable. Never `// ... rest of the code` |
| 6 | **Tables over prose** wherever a comparison exists |
| 7 | **ASCII diagrams**, no external images. Memory layouts, class hierarchies, call sequences, object graphs |
| 8 | **Versions pinned and marked**: `// since Java N`, and `⚠️ PREVIEW` where applicable |
| 9 | **Completeness over brevity.** No "and so on", no "similarly for the rest" |
| 10 | **Honest trade-offs.** Every recommendation says what it costs and when the opposite choice is right |
| 11 | **Markers used consistently**: ⭐ insight · ⭐⭐ junior↔senior · ⭐⭐⭐ senior↔staff · ⛔ anti-pattern · ⚠️ trap · ✅ correct · 🔑 say this in the interview |
| 12 | **Every file ends with the footer** |

---

## 🧰 Setup — do this once

```bash
# ⭐ Java 21 (the teaching baseline) — Temurin, not Oracle
#    macOS:   brew install --cask temurin@21
#    Ubuntu:  sudo apt install -y temurin-21-jdk
#    Windows: winget install EclipseAdoptium.Temurin.21.JDK
#    or use SDKMAN to hold several:
curl -s "https://get.sdkman.io" | bash
sdk install java 21.0.5-tem && sdk install java 25.0.0-tem   # baseline + current LTS

java -version      # ✅ VERIFY: openjdk 21.x
javac -version

# ⭐ build tools
sdk install maven 3.9.9
sdk install gradle 8.10

# ⭐ the REPL — the single best Java learning tool, and most people never use it
jshell
#   jshell> int x = 5;
#   jshell> x * 2
#   ⭐ /vars, /methods, /types, /list  — inspect what you have defined
#   ⭐ Ctrl-D to exit

# ⭐ single-file execution (Java 11+) — no javac, no class file
#    cat > Hello.java  then:
java Hello.java    # ✅ compiles in memory and runs. Perfect for examples

# ⭐ frontend (verify the Node version before Folder 2)
node --version     # target: v24 LTS
npm --version

# ⭐ databases — via Docker (you already know it)
docker run -d --name shop-pg -e POSTGRES_PASSWORD=shop -e POSTGRES_DB=shop \
  -p 5432:5432 postgres:17
docker run -d --name shop-redis -p 6379:6379 redis:7
docker run -d --name shop-rabbit -p 5672:5672 -p 15672:15672 rabbitmq:3-management

# ⭐ the workspace layout this path assumes
mkdir -p ~/java-fullstack/{01-core-java-lab,shop}
cd ~/java-fullstack/01-core-java-lab
#   every program in Folder 1 is a single self-contained file you can run
#   with `java File.java`. No IDE required, no build file required.
```

**IDE:** IntelliJ IDEA Community is free and is what the industry uses. But ⭐ **do not let it write your code for the first two folders.** Type the programs by hand, run them from the terminal with `java File.java`, and read the compiler errors yourself. The IDE's auto-import and live-template features will hide exactly the mechanics Folder 1 is trying to teach you.

---

## 🔗 The other learning paths in this workspace

| Path | Folder | Status | How it connects |
|---|---|---|---|
| 🐳 Docker | [`../docker-learning-path/`](../docker-learning-path/) | ✅ 19 files | Folder 7 §08 produces the Dockerfiles; the capstone containerises `shop` |
| ☸️ Kubernetes | [`../kubernetes-learning-path/`](../kubernetes-learning-path/) | ✅ 20 files | The capstone deploys `shop` to the `shop` namespace |
| 📊 Monitoring & Alerting | [`../monitoring-alerting-learning-path/`](../monitoring-alerting-learning-path/) | ✅ 7 files | `shop-api` exposes Micrometer/OTel; Folder 7 §06 wires it |
| 🚀 CI/CD | [`../cicd-learning-path/`](../cicd-learning-path/) | ✅ 9 files | The capstone ships through CI/CD; **file 07** deploys `shop-api` |
| 🎯 The generator prompt | [`../PROMPT-java-fullstack-sde3.md`](../PROMPT-java-fullstack-sde3.md) | ✅ | The self-contained prompt that produces this path — reuse it folder by folder |

⭐ **Together these five paths are one curriculum on one application.** You build `shop` in Java, give it a React frontend, persist it, serve it, containerise it, orchestrate it, observe it, ship it — and then you can talk about a *system you actually built* for twenty minutes in an interview, which is worth more than any framework trivia.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*184 files. One application. Beginner explanations, staff-level depth.*

</div>
