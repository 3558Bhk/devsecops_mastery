# ☕ `01-core-java/01` — BASICS AND THE COMPLETE TOPIC MAP

### ⭐ THE MAP FIRST — every Core Java topic, tagged by how much it matters — then the fundamentals from absolute zero: how Java actually runs, what `javac` produces, and every construct you need before OOP makes sense.

> **Read Part 0 before anything else.** Thirty minutes with the map makes the next sixty hours roughly twenty percent more effective, because you always know where what you are reading goes.
>
> **Java version:** every program here compiles on **Java 21 LTS** (the teaching baseline). Anything from 22–26 is marked `// since Java N`.
> **How to run anything here:** `java 01-lab/File.java` — the single-file source launcher. No IDE, no build file, no `.class` cleanup.

---

## 📇 Contents

| Part | Topic |
|---|---|
| **[PART 0](#part-0---the-map-read-this-first)** | ⭐ **THE MAP** — every Core Java topic with its mastery tag and the file that covers it |
| [PART 1](#part-1--what-java-actually-is) | What Java actually is: JDK / JRE / JVM, bytecode, the JIT, the classpath |
| [PART 2](#part-2--running-your-first-program) | Running your first program; the `main` signature deconstructed |
| [PART 3](#part-3--primitives) | The 8 primitives, sizes, ranges, defaults, why `double` lies, `char` and Unicode |
| [PART 4](#part-4--wrappers-and-autoboxing) | Wrappers, ⭐ the −128..127 cache, autoboxing, the null-unboxing NPE |
| [PART 5](#part-5--operators) | Every operator, including all the bitwise ones and their real use cases |
| [PART 6](#part-6--type-casting) | Widening vs narrowing, `(int)` vs `Math.round`, the `char`+`int` surprise |
| [PART 7](#part-7--control-flow) | `if`, `switch` (1995 and 2023 forms), loops, ⭐ what the enhanced `for` compiles to |
| [PART 8](#part-8--arrays) | Arrays are objects, `length` is a field, the five kinds of copy, sorting |
| [PART 9](#part-9--methods) | Signatures, ⭐⭐ overloading resolution in three phases, compile vs runtime |
| [PART 10](#part-10---pass-by-value) | ⭐⭐ **PASS BY VALUE** — the most-asked Java question, proven four ways |
| [PART 11](#part-11--string) | `String`: immutability and why, the pool, `intern()`, the concatenation truth |
| [PART 12](#part-12--static) | `static`, and ⭐⭐ the complete initialisation order with a proof program |
| [PART 13](#part-13--jvm-memory-beginner-level) | Stack vs heap, and `StackOverflowError` vs `OutOfMemoryError` |
| [PART 14](#part-14--console-io) | `args`, `Scanner` vs `BufferedReader`, `printf` and every format specifier |
| [PART 15](#part-15--packages-imports-javadoc) | Packages, imports, access modifiers (preview), javadoc |
| [PART 16](#part-16--the-toolchain) | `javac`/`java` flags, ⭐ `jshell`, the single-file launcher, `jar` |
| **[PRACTICE](#tasks--answers)** | ⭐ 12 coding tasks · 22 "what does this print?" · 12 find-the-bug · 28 interview questions — **answers at the END** |

---

<a name="part-0"></a><a name="part-0---the-map-read-this-first"></a>
# PART 0 — ⭐ THE MAP (read this first)

## 0.1 The four mastery tags

Every Core Java topic below carries exactly one tag. The tag tells you **how much time it deserves**, which is the decision most self-taught engineers get wrong.

| Tag | Meaning | Time allocation | Interview weight |
|---|---|---|---|
| **[MUST KNOW]** | You will be asked, or you cannot read real Java code without it | Learn to **recall** — no notes, under pressure | ⭐⭐⭐ asked directly, constantly |
| **[SHOULD KNOW]** | You will use it weekly; interviewers use it as a follow-up | Learn to **recognise and use**, look up the details | ⭐⭐ follow-up territory |
| **[SDE3 DIFFERENTIATOR]** | Almost nobody knows this properly. Knowing it is the signal | Learn **deeply** — internals, failure modes, trade-offs | ⭐⭐⭐ separates senior from staff |
| **[RARELY ASKED]** | Real, useful, but not worth your week-1 hours | Skim once, return when you need it | ⭐ almost never asked |

⭐⭐ **The mistake this prevents:** spending six hours on `DateFormat` patterns (RARELY ASKED) and forty minutes on `HashMap` internals (SDE3 DIFFERENTIATOR). Effort feels evenly distributed; value is not.

## 0.2 The complete Core Java topic tree

```
CORE JAVA
│
├─ 1 · THE PLATFORM                                              [MUST KNOW]
│   ├─ JDK vs JRE vs JVM — what each contains .................... [MUST KNOW]
│   ├─ .java → javac → .class → java → JVM ...................... [MUST KNOW]
│   ├─ bytecode; reading `javap -c` ............................. [SHOULD KNOW]
│   ├─ ⭐ the JIT (C1/C2), tiered compilation, warmup ............. [SDE3 DIFF]
│   ├─ the classloader hierarchy; parent delegation ............. [SDE3 DIFF]
│   ├─ the classpath; `-cp`; package-vs-directory ............... [MUST KNOW]
│   ├─ "write once run anywhere" and what it actually costs ...... [SHOULD KNOW]
│   └─ the module system (JPMS) — pointer only .................. [RARELY ASKED]
│       └─ covered in 04-ADVANCED
│
├─ 2 · PROGRAM STRUCTURE                                         [MUST KNOW]
│   ├─ the `main` signature, modifier by modifier ................ [MUST KNOW]
│   ├─ `String[] args` vs `String... args` ...................... [SHOULD KNOW]
│   ├─ ⭐ Java 25 instance main + compact source files ........... [SHOULD KNOW]
│   ├─ classes, files, and the one-public-class-per-file rule .... [MUST KNOW]
│   └─ packages, imports, the auto-imported `java.lang` ......... [MUST KNOW]
│
├─ 3 · TYPES                                                     [MUST KNOW]
│   ├─ the 8 primitives: sizes, ranges, defaults ................ [MUST KNOW]
│   ├─ ⭐ why float/double are imprecise; money is never a double . [MUST KNOW]
│   ├─ BigDecimal vs long-cents .................................. [SHOULD KNOW]
│   ├─ char, UTF-16, code points, surrogate pairs ............... [SHOULD KNOW]
│   ├─ boolean and its unspecified size ......................... [RARELY ASKED]
│   ├─ literals: underscores, hex, binary, octal ................ [SHOULD KNOW]
│   ├─ the 8 wrappers; `valueOf` vs `new` (deprecated) .......... [MUST KNOW]
│   ├─ ⭐⭐ the Integer cache −128..127 and the `==` trap ......... [MUST KNOW]
│   ├─ autoboxing / unboxing .................................... [MUST KNOW]
│   ├─ ⭐ the NPE on unboxing a null wrapper ..................... [MUST KNOW]
│   ├─ boxing cost in a hot loop ................................ [SHOULD KNOW]
│   └─ ⭐⭐ var (local type inference) — what it is NOT ........... [SHOULD KNOW]
│
├─ 4 · OPERATORS                                                 [MUST KNOW]
│   ├─ arithmetic; integer division; `%` on negatives ........... [MUST KNOW]
│   ├─ ⭐ integer overflow — silent, and the `Math.*Exact` fix ... [SDE3 DIFF]
│   ├─ relational ............................................... [MUST KNOW]
│   ├─ ⭐ `&&` vs `&`, `||` vs `|` — short-circuit, proven ....... [MUST KNOW]
│   ├─ bitwise: `& | ^ ~` and the six real use cases ............ [SHOULD KNOW]
│   ├─ ⭐ `(n-1) & hash` — the HashMap index trick ............... [SDE3 DIFF]
│   ├─ shifts: `<< >> >>>` and sign extension ................... [SHOULD KNOW]
│   ├─ compound assignment and its implicit cast ................. [SHOULD KNOW]
│   ├─ ⭐ the ternary's numeric-promotion NPE trap ............... [SDE3 DIFF]
│   ├─ `instanceof`; ⭐ pattern matching for instanceof (16+) .... [MUST KNOW]
│   └─ precedence and associativity — the table, and "use parens"  [SHOULD KNOW]
│
├─ 5 · CASTING AND CONVERSION                                    [MUST KNOW]
│   ├─ widening (implicit) vs narrowing (explicit) .............. [MUST KNOW]
│   ├─ what narrowing actually loses ............................ [MUST KNOW]
│   ├─ `(int)` truncates vs `Math.round` rounds ................. [MUST KNOW]
│   ├─ ⭐ `char` + `int` = `int` — the arithmetic surprise ....... [MUST KNOW]
│   ├─ ⭐ `byte b = 1; b += 1;` compiles — why ................... [SDE3 DIFF]
│   ├─ String ↔ number: `parseInt` vs `valueOf` ................. [MUST KNOW]
│   └─ `Math.floorDiv` / `floorMod` vs `/` and `%` .............. [SHOULD KNOW]
│
├─ 6 · CONTROL FLOW                                              [MUST KNOW]
│   ├─ if / else if / else; the brace rule ...................... [MUST KNOW]
│   ├─ ⭐ switch statement (old) — fall-through, the silent bug .. [MUST KNOW]
│   ├─ ⭐ switch EXPRESSION (14+) — arrows, `yield`, no fall-thru  [MUST KNOW]
│   ├─ exhaustiveness; sealed types; omitting `default` ......... [SDE3 DIFF]
│   ├─ for / while / do-while ................................... [MUST KNOW]
│   ├─ ⭐ enhanced for — what it compiles to (array vs Iterable) . [SDE3 DIFF]
│   ├─ break / continue; ⭐ labelled break ....................... [SHOULD KNOW]
│   ├─ the infinite-loop idioms ................................. [RARELY ASKED]
│   └─ unreachable-code and definite-assignment rules ........... [SHOULD KNOW]
│
├─ 7 · ARRAYS                                                    [MUST KNOW]
│   ├─ ⭐ arrays are OBJECTS; `length` is a FIELD ............... [MUST KNOW]
│   ├─ declaration forms; default initialisation ................ [MUST KNOW]
│   ├─ 1D / 2D / jagged ......................................... [MUST KNOW]
│   ├─ ⭐ the five copies: `=` vs `clone` vs `copyOf` vs
│   │     `copyOfRange` vs `arraycopy` — shallow vs deep ........ [MUST KNOW]
│   ├─ `Arrays.sort` (dual-pivot quicksort) vs `TimSort` ....... [SHOULD KNOW]
│   ├─ `Arrays.binarySearch` and its preconditions ............. [SHOULD KNOW]
│   ├─ ⭐ varargs IS an array — the consequences ................ [SDE3 DIFF]
│   ├─ `ArrayIndexOutOfBounds` vs `NegativeArraySizeException` ... [MUST KNOW]
│   └─ `Arrays.asList` vs `List.of` vs `List.copyOf` ............ [SHOULD KNOW]
│
├─ 8 · METHODS                                                   [MUST KNOW]
│   ├─ anatomy; the signature (name + parameter types ONLY) ..... [MUST KNOW]
│   ├─ ⭐ return type is NOT part of the signature .............. [SDE3 DIFF]
│   ├─ `void`; returning early; the missing-return error ........ [MUST KNOW]
│   ├─ ⭐⭐ overloading resolution — the THREE PHASES ............. [MUST KNOW]
│   ├─ ambiguity errors; the `null` argument .................... [SHOULD KNOW]
│   ├─ varargs rules (last, only one) and the `@SafeVarargs` .... [SHOULD KNOW]
│   └─ ⭐⭐ compile-time (overload) vs runtime (override) ........ [MUST KNOW]
│
├─ 9 · ⭐⭐ PASS BY VALUE — the most-asked Java question .......... [MUST KNOW]
│   ├─ the sentence, stated correctly ........................... [MUST KNOW]
│   ├─ proof 1: a primitive ..................................... [MUST KNOW]
│   ├─ proof 2: mutating an object through the copy ............. [MUST KNOW]
│   ├─ proof 3: reassigning the reference (the decisive one) .... [MUST KNOW]
│   ├─ proof 4: the swap that fails ............................. [MUST KNOW]
│   ├─ why "pass by reference for objects" is wrong ............. [MUST KNOW]
│   └─ how to actually swap (holder / array / AtomicReference) .. [SHOULD KNOW]
│
├─ 10 · STRING                                                   [MUST KNOW]
│   ├─ ⭐⭐ immutability and the FOUR reasons why ................ [MUST KNOW]
│   ├─ ⭐ the String pool; `intern()`; heap vs pool ............. [MUST KNOW]
│   ├─ `==` vs `.equals()`; ⭐ constant folding ................. [MUST KNOW]
│   ├─ concatenation: the StringBuilder the compiler inserts .... [MUST KNOW]
│   ├─ ⭐ when it does NOT (loops) — and the O(n²) cost ......... [MUST KNOW]
│   ├─ String vs StringBuilder vs StringBuffer — the honest ..... [SHOULD KNOW]
│   │     answer (never use StringBuffer)
│   ├─ the methods table; `charAt` vs `codePointAt` ............. [SHOULD KNOW]
│   ├─ new since 11 / 12 / 15 / 20 / 21 ......................... [SHOULD KNOW]
│   ├─ text blocks (15+) and the incidental-whitespace rule ..... [SHOULD KNOW]
│   └─ ⭐ String concatenation in a log statement — the cost .... [SDE3 DIFF]
│
├─ 11 · static                                                   [MUST KNOW]
│   ├─ static fields, methods, blocks ........................... [MUST KNOW]
│   ├─ why a static method has no `this` ........................ [MUST KNOW]
│   ├─ static nested classes vs inner classes (pointer) ......... [SHOULD KNOW]
│   ├─ static imports and when they hurt readability ............ [RARELY ASKED]
│   ├─ ⭐⭐ THE INITIALISATION ORDER — the full sequence ......... [MUST KNOW]
│   ├─ ⭐ forward references — the rules that surprise everyone .. [SDE3 DIFF]
│   └─ static mutable state and thread safety (pointer) ......... [SDE3 DIFF]
│       └─ covered in 04-ADVANCED
│
├─ 12 · JVM MEMORY (beginner level) .............................. [MUST KNOW]
│   ├─ ⭐ the stack: frames, locals, operand stack .............. [MUST KNOW]
│   ├─ ⭐ the heap: where every object lives .................... [MUST KNOW]
│   ├─ what lives where — the diagram ........................... [MUST KNOW]
│   ├─ metaspace (class metadata), and the old PermGen .......... [SHOULD KNOW]
│   ├─ ⭐ StackOverflowError vs OutOfMemoryError ................ [MUST KNOW]
│   ├─ escape analysis and stack allocation ..................... [SDE3 DIFF]
│   ├─ `-Xmx` / `-Xss` / `MaxRAMPercentage` in containers ....... [SHOULD KNOW]
│   └─ GC algorithms — pointer only ............................. [SDE3 DIFF]
│       └─ covered in 04-ADVANCED
│
├─ 13 · CONSOLE I/O AND FORMATTING ............................... [SHOULD KNOW]
│   ├─ command-line `args` ...................................... [MUST KNOW]
│   ├─ `Scanner` — and why it is slow ........................... [SHOULD KNOW]
│   ├─ `BufferedReader` — the fast alternative .................. [SHOULD KNOW]
│   ├─ ⭐ `printf` and every format specifier ................... [SHOULD KNOW]
│   ├─ `System.console()` and why it is often null ............. [RARELY ASKED]
│   ├─ `System.out` vs `System.err`; flushing .................. [SHOULD KNOW]
│   └─ ⭐ structured logging vs System.out (pointer) ............ [SDE3 DIFF]
│
├─ 14 · PACKAGES, ACCESS, JAVADOC ................................ [MUST KNOW]
│   ├─ packages = directories; the naming convention ............ [MUST KNOW]
│   ├─ imports; fully-qualified names; no wildcard in teaching .. [MUST KNOW]
│   ├─ ⭐⭐ the four access modifiers — the 4×4 matrix ........... [MUST KNOW]
│   │     (full treatment in 02A §9)
│   └─ javadoc; `{@code}`, `{@link}`, `@param`, `@throws` ....... [RARELY ASKED]
│
└─ 15 · THE TOOLCHAIN                                            [SHOULD KNOW]
    ├─ ⭐ `javac -Xlint:all -Werror` — treat warnings as bugs .... [MUST KNOW]
    ├─ `-d`, `-g`, `-cp`, `--release`, `--enable-preview` ....... [SHOULD KNOW]
    ├─ `java -Xmx`, `-XX:+HeapDumpOnOutOfMemoryError` .......... [SHOULD KNOW]
    ├─ ⭐ `jshell` — the best Java learning tool nobody uses ..... [MUST KNOW]
    ├─ ⭐ the single-file source launcher (`java Foo.java`) ...... [MUST KNOW]
    ├─ `jar` — create, extract, the manifest, executable jars .... [SHOULD KNOW]
    └─ build tools (Maven/Gradle) — pointer ..................... [SHOULD KNOW]
        └─ covered in 05-JDBC and 07-spring-boot
```

## 0.3 Where each topic lives

| Topic cluster | This file (`01`) | Also in |
|---|---|---|
| Platform, bytecode, JIT | ✅ Part 1 | `04-ADVANCED` (classloaders, JIT detail, JVM tuning) |
| Primitives, wrappers | ✅ Parts 3–4 | `08-CHEATSHEET` (tables) |
| Operators, casting | ✅ Parts 5–6 | `06-COLLECTIONS` (the `&` index trick) |
| Control flow, arrays, methods | ✅ Parts 7–9 | `02A` (overriding vs overloading) |
| ⭐ Pass by value | ✅ Part 10 | `09-vault/01` (the interview version) |
| String | ✅ Part 11 | `04-ADVANCED` (StringConcatFactory, compact strings) |
| static, initialisation order | ✅ Part 12 | `02A` §4 (the full constructor chain) |
| JVM memory | ✅ Part 13 | `04-ADVANCED` (GC algorithms, JFR, tuning) |
| Console I/O | ✅ Part 14 | `03-FILE-HANDLING-AND-IO` (real I/O) |
| Packages, access | ✅ Part 15 | `02A` §9 (the complete encapsulation treatment) |
| Toolchain | ✅ Part 16 | — |

## 0.4 ⭐ The 20 things you must know cold before leaving this file

Not "have read". **Cold** — recallable with no notes, under pressure.

| # | Thing | Where |
|---|---|---|
| 1 | The `main` signature, and a reason for each of its four modifiers | §2.1 |
| 2 | All 8 primitives with sizes and ranges (`int` = 32-bit, −2³¹..2³¹−1) | §3.1 |
| 3 | Why money is never a `double`, and the two correct alternatives | §3.3 |
| 4 | `Integer.valueOf` caches −128..127 → why `==` fails *sometimes* | §4.2 |
| 5 | Why unboxing a `null` `Integer` throws NPE | §4.4 |
| 6 | `&&` vs `&` — and the two bugs the missing character causes | §5.3 |
| 7 | `(n-1) & hash` and why `n` must be a power of two | §5.4 |
| 8 | The ternary's numeric-promotion NPE trap | §5.7 |
| 9 | The precedence rows that matter, and "just use parentheses" | §5.9 |
| 10 | `(int)` truncates, `Math.round` rounds, `char + int` is `int` | §6.2–6.3 |
| 11 | The old `switch` falls through; the arrow form does not | §7.2–7.3 |
| 12 | ⭐ What the enhanced `for` compiles to for an array vs an `Iterable` | §7.5 |
| 13 | Arrays are objects; `length` is a field; `String.length()` is a method | §8.1 |
| 14 | The five kinds of array copy and which are shallow | §8.4 |
| 15 | ⭐⭐ Overloading resolution: the three phases, in order | §9.3 |
| 16 | ⭐⭐ The pass-by-value sentence, and proof 3 (reassignment) | §10 |
| 17 | ⭐ The four reasons `String` is immutable | §11.1 |
| 18 | Why `"a"+"b" == "ab"` is true but `(s+"b") == "ab"` is false | §11.2 |
| 19 | ⭐⭐ The complete initialisation order, parent and child | §12.2 |
| 20 | `StackOverflowError` (per-thread, recursion) vs `OutOfMemoryError` (heap, retention) | §13.3 |

---

<a name="part-1"></a><a name="part-1--what-java-actually-is"></a>
# PART 1 · What Java actually is

## 1.1 JDK vs JRE vs JVM — [MUST KNOW]

**WHAT.** Three nested things, and the names are genuinely confusing:

```
┌──────────────────────── JDK (Java Development Kit) ───────────────────────┐
│  what you install to WRITE Java                                            │
│                                                                            │
│  javac   the compiler          jar     the archive tool                   │
│  javadoc documentation         jdb     the debugger                       │
│  jshell  ⭐ the REPL           javap   the bytecode disassembler          │
│  jlink   custom runtimes       jfr     flight recorder                    │
│                                                                            │
│  ┌──────────────────── JRE (Java Runtime Environment) ─────────────────┐  │
│  │  what you install to RUN Java                                        │  │
│  │                                                                      │  │
│  │  the class libraries: java.lang, java.util, java.io, java.nio, …    │  │
│  │                                                                      │  │
│  │  ┌──────────────────── JVM (Java Virtual Machine) ───────────────┐  │  │
│  │  │  the thing that actually executes bytecode                    │  │  │
│  │  │  classloader → verifier → interpreter → JIT → GC              │  │  │
│  │  │  ⭐ there is a different JVM per OS/architecture              │  │  │
│  │  └────────────────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

**WHY the distinction matters.** Two practical reasons:

1. **Deployment size.** A container image with a full JDK is ~330 MB; a JRE-only image is ~200 MB; a `jlink`-ed custom runtime with only the modules you use can be **~50 MB**. ⭐ This is a real production decision — see `07-spring-boot/08-DEPLOYMENT.md`.
2. **Since Java 11 there is no separate JRE download from Oracle.** The JDK *is* the runtime, and you produce a smaller one with `jlink`. So in 2026 the honest answer is: *"install a JDK; if image size matters, build a custom runtime."*

⭐ **Which JDK?** **Temurin** (Eclipse Adoptium). Not Oracle's — Oracle's JDK has licence terms that have changed three times and surprised a lot of companies. Temurin is the same OpenJDK source, TCK-certified, free, and what most of the industry runs. Alternatives: Amazon Corretto, Azul Zulu, Microsoft Build of OpenJDK.

🔑 **The interview line:** *"The JVM is the per-platform execution engine; the JRE is the JVM plus the class libraries; the JDK adds the compiler and tools. Since Java 11 there's no separate JRE distribution — you install a JDK and, if you care about image size, use `jlink` to produce a minimal runtime containing only the modules your application actually uses."*

## 1.2 The pipeline — [MUST KNOW]

```
   Hello.java          ← SOURCE. Human-readable text. UTF-8.
       │
       │  javac Hello.java
       │  ⭐ the compiler does: parse → symbol table → attribute (type check)
       │    → flow analysis (definite assignment, reachability) → desugar
       │    (generics erasure, enhanced-for, string concat, inner classes)
       │    → generate bytecode
       ▼
   Hello.class         ← BYTECODE. Platform-neutral. NOT machine code.
       │                  A binary format: a constant pool, method bodies as
       │                  instructions for a stack machine, field tables.
       │  java Hello
       ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  JVM                                                          │
   │   1. CLASSLOADER   finds Hello.class on the classpath,        │
   │                    reads the bytes into a Class object        │
   │   2. VERIFIER      checks the bytecode is structurally valid  │
   │                    and cannot forge references / overflow the │
   │                    stack. ⭐ This is why Java is memory-safe  │
   │                    without you doing anything                 │
   │   3. PREPARATION   allocate static fields, set defaults       │
   │   4. INITIALISE    run static initialisers (Part 12)          │
   │   5. INVOKE        find `public static void main(String[])`   │
   │   6. EXECUTE       interpret bytecode; the JIT compiles hot   │
   │                    methods to machine code                    │
   │   7. GC            reclaims unreachable objects throughout    │
   └──────────────────────────────────────────────────────────────┘
```

⭐ **The desugaring step is the one worth knowing about.** `javac` rewrites several language features into simpler bytecode before it emits anything:

| Source feature | Desugared to | Consequence you will meet |
|---|---|---|
| Generics | erasure — `List<String>` becomes `List` + inserted casts | §9.3, and `04-ADVANCED` generics |
| Enhanced `for` | an index loop (arrays) or an `Iterator` loop (`Iterable`) | ⭐ §7.5 |
| String concatenation | `StringBuilder` (or `invokedynamic` since Java 9) | ⭐ §11.3 |
| `switch` on `String` | a `switch` on `hashCode()` then `equals()` | §7.3 |
| Inner classes | synthetic accessor methods + `Outer$Inner.class` | `02A` §16 |
| Autoboxing | `Integer.valueOf(...)` / `.intValue()` | §4.3 |
| `try-with-resources` | nested try/finally with `close()` | `03-FILE-HANDLING` |

**This is why `javap -c` sometimes shows code you did not write.** You are seeing the desugared form.

## 1.3 Bytecode and `javap` — [SHOULD KNOW]

You do not need to *write* bytecode. You need to be able to *read enough* of it to stop guessing.

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.01 — the smallest real program, for disassembly
// ══════════════════════════════════════════════════════════════════════
// WHAT   : prints one line. Nothing else.
// WHY    : its bytecode is short enough to read completely, so you can see
//          exactly what `System.out.println("hello")` becomes.
// OUTPUT : hello
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class Tiny {
    public static void main(String[] args) {
        System.out.println("hello");
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// hello
// ──────────────────────────────────────────────────────────────────────
```

```bash
javac -d out Tiny.java
javap -c -p out/Tiny.class
```

```text
Compiled from "Tiny.java"
public class Tiny {
  public Tiny();
    Code:
       0: aload_0                        ← push `this` (slot 0)
       1: invokespecial #1               ← call super() — Object.<init>
                                          ⭐ THE IMPLICIT super(). You did not
                                             write it. It is here anyway.
       4: return

  public static void main(java.lang.String[]);
    Code:
       0: getstatic     #7               ← push the static field System.out
                                          ⭐ `getstatic`: out belongs to the
                                             CLASS System, not to an instance
       3: ldc           #13              ← push the String constant "hello"
                                          ⭐ `ldc` = load from the constant
                                             pool. Strings live there.
       5: invokevirtual #15              ← call println(String) on it
                                          ⭐ `invokevirtual`: the target is
                                             resolved at RUNTIME by the
                                             object's actual class. THIS is
                                             polymorphism, in one instruction.
       8: return                         ← `void` methods still `return`
}
```

⭐ **The five `invoke` instructions** — you will need these in `02A` §8 (polymorphism):

| Bytecode | Used for | Resolved when | Polymorphic? |
|---|---|---|---|
| `invokestatic` | `static` methods | compile time | ⛔ no |
| `invokespecial` | constructors, `private` methods, `super.m()` | compile time | ⛔ no |
| `invokevirtual` | normal instance methods | ⭐ **runtime** (vtable) | ✅ yes |
| `invokeinterface` | interface methods | ⭐ **runtime** (itable) | ✅ yes |
| `invokedynamic` | lambdas, string concat (Java 9+), Groovy/Kotlin/Scala | ⭐ runtime, via a bootstrap method | ✅ yes |

**That table is why `private`, `static` and `final` methods cannot be overridden.** They are not dispatched with `invokevirtual` — or, for `final`, the JIT can devirtualise them because no subclass can exist. ⭐ A `final` method is a small, real optimisation opportunity, and that is the honest reason to use it (not "defensive design").

## 1.4 ⭐ The JIT — [SDE3 DIFFERENTIATOR]

**WHAT.** The JVM starts by *interpreting* bytecode — one instruction at a time, which is slow. As it runs, it counts how often each method and loop is executed. When something gets **hot**, the JIT (Just-In-Time compiler) compiles it to real machine code and the JVM switches to running that.

```
                     execution count
   interpreted ──────────────────────────▶
   (slow, universal)      │
                          │ hot (~1,500 invocations / ~10,000 loop back-edges)
                          ▼
                    C1 "client" compile      fast to compile, lightly optimised
                          │
                          │ very hot (~10,000 invocations)
                          ▼
                    C2 "server" compile      slow to compile, heavily optimised:
                                             inlining, escape analysis, loop
                                             unrolling, branch prediction
                                             from the OBSERVED profile
                          │
                          │ assumption invalidated (a new subclass is loaded)
                          ▼
                    DEOPTIMISE ──────────▶ back to interpreted, recompile later
```

**WHY you should care — three concrete consequences:**

1. ⭐ **Warmup.** A Java service is measurably slower for its first few thousand requests. In Kubernetes, this means a freshly-started pod that is immediately sent full traffic will have terrible p99 latency. The fixes are `minReadySeconds`, a startup probe, or a warmup script — see `cicd-learning-path/07` §6.6.
2. ⭐ **Benchmarks lie.** A JMH-less microbenchmark that runs a loop ten thousand times measures the JIT compiling, not your code. This is why "I benchmarked it in a `for` loop" is not evidence. Use JMH, or don't claim a number.
3. ⭐ **Scale-to-zero hurts Java.** A serverless function that cold-starts a JVM pays interpretation *every single invocation* because it never gets hot. This is a real architectural constraint, and GraalVM native image is the real answer to it.

**AOT (ahead-of-time) — the modern landscape:**

| Approach | What it does | Trade-off |
|---|---|---|
| **CDS / AppCDS** | pre-dump the loaded class metadata into a shared archive | ⭐ cheap, 20–40% faster startup, no code change. Do this first |
| **Project Leyden AOT cache** (Java 24+) | cache the AOT-compiled profile | the direction of travel |
| **AOT method profiling** (Java 25) | record the profile from a training run so C2 starts informed | ⭐ new in the current LTS |
| **GraalVM Native Image** | compile to a native binary, no JVM at all | ⭐ startup ~20 ms, memory ~5× less; but ⛔ no peak-throughput JIT, closed-world assumption breaks heavy reflection |

🔑 **The interview line:** *"Java is compiled twice — ahead-of-time to platform-neutral bytecode, then at runtime by a tiered JIT to machine code guided by the observed execution profile. That's the whole explanation for 'slow to start, fast to run', and it has three consequences I design around: services need warmup before they take traffic, microbenchmarks without JMH measure the compiler rather than the code, and cold-start-sensitive workloads need CDS or a native image rather than a JVM."*

## 1.5 "Write once, run anywhere" — and what it costs — [SHOULD KNOW]

The bytecode is platform-neutral, and each platform has its own JVM. That is the whole mechanism, and it works. But ⭐ **an SDE 3 answer names the costs:**

| Cost | What it means in practice |
|---|---|
| You ship a JVM | ~200 MB minimum. In containers, that is real money and real pull time |
| Startup time | hundreds of ms to seconds. Matters for CLI tools, serverless, autoscaling |
| Lowest common denominator | the API can only expose what every platform supports — hence the historic gaps in filesystem, process and signal handling that NIO.2 and `ProcessHandle` (Java 9) partly fixed |
| Filesystem and line-ending differences | `/` vs `\`, LF vs CRLF, case-sensitivity, path length. ⭐ "Runs on my machine" survives in Java too — see `03-FILE-HANDLING` |
| Locale, timezone, encoding | ⛔ the default charset differed between platforms until **Java 18 made UTF-8 the default** (JEP 400). Code written before that can genuinely behave differently on Windows |
| Performance profile | predictable steady state, unpredictable warmup |

## 1.6 The classloader (beginner level) — [SDE3 DIFFERENTIATOR, pointer]

```
        Bootstrap classloader      ← C++. Loads java.base: java.lang.*,
              │                       java.util.*. Has NO Java object.
              │ parent delegation: a loader asks its PARENT first,
              ▼                     and only loads the class itself if
        Platform classloader        the parent cannot. ⭐ This is why you
              │                     cannot override java.lang.String —
              ▼                     the bootstrap loader always wins.
        Application classloader  ← loads YOUR classes from the classpath
              │
              ▼
        your custom loaders      ← Tomcat (one per webapp), OSGi, hot-reload
```

**Why it matters now, briefly:** it explains three things you will meet later —
- ⛔ you cannot forge `java.lang.String` (parent delegation + the verifier),
- ⭐ `ClassNotFoundException` (the loader could not find it) vs `NoClassDefFoundError` (it was found at compile time but is missing/incompatible at runtime, or its static initialiser threw) — **these are different failures with different fixes**,
- Tomcat's classloader isolation, which is how one JVM hosts several webapps with conflicting library versions.

Full treatment in `04-ADVANCED-CORE-JAVA.md`.

## 1.7 The classpath — [MUST KNOW]

**WHAT.** An ordered list of locations the application classloader searches for `.class` files. That is all it is.

```bash
# the four ways to set it, in the order they override each other:
java -cp out:libs/gson.jar com.shop.demo.Tiny   # ⭐ 1. -cp / -classpath (use this)
export CLASSPATH=out:libs/gson.jar              # 2. the env var (⛔ avoid:
java com.shop.demo.Tiny                         #    it is invisible and bites
                                                #    you on the next machine)
# 3. the -jar manifest's Class-Path entry (only when running a jar)
# 4. the default: the current directory "."
```

| Separator | Platform |
|---|---|
| `:` | Linux, macOS |
| `;` | ⭐ Windows |
| `*` | "every `.jar` in this directory" — `libs/*`, **quoted** so the shell does not expand it |

⭐⭐ **The three classpath errors and what each actually means:**

| Error | Real cause | Fix |
|---|---|---|
| `ClassNotFoundException` | the class is not on the classpath **at all** | check the jar/dir is listed; check the spelling |
| `NoClassDefFoundError` | it **was** there at compile time, and is missing/incompatible now — **or its static initialiser threw** | ⭐ look *above* in the log for the real cause: an `ExceptionInInitializerError` earlier |
| `package X does not exist` | compile-time: the dependency is missing from `javac`'s classpath | add it to `-cp` for the compile step too |

⭐ **The #1 beginner classpath bug:** the directory structure must match the package. If your file says `package com.shop.demo.basics;` then the `.class` must be at `<classpath-root>/com/shop/demo/basics/Tiny.class`. `javac -d out` does this for you — which is exactly why you should always use `-d`.

```bash
# ✅ VERIFY: understand your own layout
javac -d out src/com/shop/demo/basics/*.java
find out -name '*.class'
# out/com/shop/demo/basics/Tiny.class     ← matches the package, exactly
java -cp out com.shop.demo.basics.Tiny    ← ⭐ the FULLY QUALIFIED name,
                                          #   with NO .class suffix
```

---

<a name="part-2"></a><a name="part-2--running-your-first-program"></a>
# PART 2 · Running your first program

## 2.1 The `main` signature, modifier by modifier — [MUST KNOW]

```java
public static void main(String[] args)
│      │      │    │     └───────────┬──────────┘
│      │      │    └─────────────────┴── the parameter: command-line args
│      │      └───────────────────────── no return value
│      └──────────────────────────────── belongs to the CLASS, not an object
└─────────────────────────────────────── callable from outside the package
```

| Piece | Why it is there | What happens if you remove it |
|---|---|---|
| `public` | the JVM calls it from **outside** your package | ⭐ With `java Foo.java` (single-file mode) it still runs. With `java -cp out Foo` it fails: *"main method not found"* — because the launcher cannot access a non-public entry point. **Keep it public** |
| `static` | the JVM must call it **before any object exists**. There is no instance to call it on | ⛔ *"main method not found"* — an instance method needs an object, and creating one would need `main` to exist first. Circular |
| `void` | there is nobody to return to. The process exit code is the real "return value" — via `System.exit(n)` | ⛔ compile error: *"missing return statement"* or invalid signature |
| `main` | the agreed name. It is a convention enforced by the launcher, **not** a keyword | ⛔ *"main method not found"* |
| `String[] args` | the command line, split on whitespace, as strings | ⛔ *"main method not found"* — the signature must match exactly |

⭐ **`String[] args` and `String... args` are the same thing.** Varargs *is* an array (§8.6) — it desugars to `String[]`. Both are valid entry points. `String...` is arguably nicer because it lets you call `main()` with no argument from your own code:

```java
public class VarargsMain {
    public static void main(String... args) {     // ✅ valid, since forever
        System.out.println("args.length = " + args.length);
    }
}
// run:  java VarargsMain.java a b c   → args.length = 3
// and from code: VarargsMain.main();  → args.length = 0   ⭐ no NPE
```

⭐ **Java 25 finalised two changes that make beginner Java look different** (`// since Java 25`):

```java
// ── the Java 21 form: what 99% of the code you will read looks like ─────
public class Hello {
    public static void main(String[] args) {
        System.out.println("hello");
    }
}

// ── the Java 25 form: compact source file + instance main ──────────────
// ⛔ NOT RUNNABLE BEFORE JAVA 25 — this is a COMPACT SOURCE FILE, so it is
//   the whole file, not a snippet inside a class. Do not paste it into the
//   class above. It is shown so you can recognise it, not so you can run it.
// ⚠️ No class declaration. No `public`. No `static`. No `String[]`.
void main() {
    IO.println("hello");        // java.lang.IO, implicitly imported in a
}                               //   compact source file
// Run:  java Hello.java
// ⭐ `void main()`, `static void main()`, and `void main(String[])` are all
//   accepted; the JVM picks the most specific one available.
```

**The teaching decision, honestly:** learn and write the **Java 21 form**. Know the Java 25 form exists and can name it. Reason — you will be interviewed on a 21 (often 17) codebase, and being unable to read `public static void main(String[] args)` as anything other than "the way you write it" is a small but real gap.

## 2.2 The three ways to break `main` — [SHOULD KNOW]

🧪 **Do this once. These three errors are 90% of "my program won't run".**

```bash
mkdir -p 01-lab && cd 01-lab

# ── break 1: not static ──────────────────────────────────────────────────
cat > Bad1.java <<'EOF'
public class Bad1 {
    public void main(String[] args) {          // ⛔ missing `static`
        System.out.println("never runs");
    }
}
EOF
java Bad1.java
# error: an instance method cannot be referenced from a static context
#   ... or, depending on the launcher path:
# Error: Main method not found in class Bad1, please define the main method as:
#    public static void main(String[] args)

# ── break 2: wrong parameter type ────────────────────────────────────────
cat > Bad2.java <<'EOF'
public class Bad2 {
    public static void main(String args) {     // ⛔ not an array
        System.out.println("never runs");
    }
}
EOF
java Bad2.java
# Error: Main method not found in class Bad2 ...

# ── break 3: wrong name ──────────────────────────────────────────────────
cat > Bad3.java <<'EOF'
public class Bad3 {
    public static void Main(String[] args) {   // ⛔ capital M
        System.out.println("never runs");
    }
}
EOF
java Bad3.java
# Error: Main method not found in class Bad3 ...
```

⭐ **Notice:** all three produce *the same* message — "Main method not found". The JVM does not tell you *why*. That is why you memorise the signature instead of debugging the error.

## 2.3 The single-file source launcher — [MUST KNOW]

```bash
# ⭐ Java 11+. This is how you should run EVERY example in this folder.
java 01-lab/Tiny.java
```

**What it does:** compiles the file **in memory** and runs it. No `.class` file is written to disk.

| Feature | Detail |
|---|---|
| Multiple classes in one file | ✅ works — helper classes may live in the same file as long as only one is `public` |
| Multiple **files** | ⛔ does not work. As soon as you need two source files, use `javac -d out` |
| Third-party jars | ✅ `java -cp libs/gson.jar Foo.java` |
| A shebang | ⭐ `#!/usr/bin/env -S java --source 21` on line 1, `chmod +x`, and it is a script |
| `--source N` | force a language level, e.g. `java --source 17 Foo.java` |

## 2.4 The flags that matter — [SHOULD KNOW]

```bash
# ── javac ────────────────────────────────────────────────────────────────
javac -d out src/**/*.java     # ⭐ -d: put .class files in `out`, in the
                               #   correct package directories. ALWAYS use it
javac -Xlint:all -Werror ...   # ⭐⭐ ALL warnings, and warnings are ERRORS.
                               #   Java's warnings are real bugs a surprising
                               #   fraction of the time: raw types, unchecked
                               #   casts, deprecations, fall-through, serial
javac -g ...                   # full debug info (line numbers, locals) —
                               #   needed for readable stack traces
javac --release 21 ...         # ⭐ compile against the Java 21 API AND
                               #   language level. Better than -source/-target,
                               #   which can let you use an API that does not
                               #   exist on the target
javac --enable-preview ...     # needed for any preview feature
javac -cp libs/'*' ...         # third-party jars

# ── java ─────────────────────────────────────────────────────────────────
java -cp out com.shop.demo.Tiny
java -Xmx512m ...              # max heap. ⛔ NEVER hard-code this in a
                               #   container — use -XX:MaxRAMPercentage=75
java -Xss512k ...              # per-thread stack size (affects recursion depth)
java --enable-preview ...      # must ALSO be set at runtime for previews
java -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp ...
                               # ⭐ OOM leaves evidence. Set this everywhere
java -verbose:gc ...           # GC logging; the modern form is -Xlog:gc*
java -XX:+PrintFlagsFinal -version | less   # every JVM flag and its default
java -XshowSettings:properties -version     # the whole system-property set

# ── jar ──────────────────────────────────────────────────────────────────
jar cf app.jar -C out .                  # create
jar cfe app.jar com.shop.demo.Tiny -C out .   # ⭐ e = the entry point
jar xf app.jar                           # extract
jar tf app.jar | head                    # list
java -jar app.jar                        # run (uses the manifest)
unzip -p app.jar META-INF/MANIFEST.MF    # ⭐ look at the manifest
```

---

<a name="part-3"></a><a name="part-3--primitives"></a>
# PART 3 · Primitives

## 3.1 All eight — [MUST KNOW]

| Type | Size | Range | Default (fields) | Literal example | Notes |
|---|---|---|---|---|---|
| `byte` | 8-bit | −128 … 127 | `0` | `(byte) 1` | ⚠️ **signed**. No byte literals — you must cast |
| `short` | 16-bit | −32,768 … 32,767 | `0` | `(short) 1` | ⚠️ **signed**. Almost never used |
| `int` | 32-bit | −2,147,483,648 … 2,147,483,647 | `0` | `42` | ⭐ the default integer type |
| `long` | 64-bit | −9,223,372,036,854,775,808 … 807 | `0L` | `42L` | ⭐ **always use the capital `L`** — lowercase `l` looks like `1` |
| `float` | 32-bit IEEE 754 | ~7 significant digits | `0.0f` | `1.5f` | ⛔ suffix required; ~7 digits is rarely enough |
| `double` | 64-bit IEEE 754 | ~15–17 significant digits | `0.0` | `1.5` | ⭐ the default floating-point type |
| `char` | 16-bit | 0 … 65,535 (one **UTF-16 code unit**) | `'\u0000'` | `'a'` | ⚠️ unsigned. **Not** one character — see §3.4 |
| `boolean` | *unspecified* | `true` / `false` | `false` | `true` | ⭐ the JVM is free to store it as a byte or an int |

⭐ **Two facts worth memorising exactly:**

```java
System.out.println(Integer.MIN_VALUE);   // -2147483648
System.out.println(Integer.MAX_VALUE);   //  2147483647
// ⭐ the range is ASYMMETRIC: one more negative value than positive.
//    That asymmetry causes a real bug — see §3.5.
System.out.println(Long.MIN_VALUE);      // -9223372036854775808
```

**Defaults apply to FIELDS only.** ⛔ Local variables have **no** default — the compiler refuses to let you read an uninitialised local. That is the *"variable x might not have been initialized"* error, and it is a feature:

```java
public class Defaults {
    static int    si;    static long   sl;    static double sd;
    static boolean sb;   static char   sc;    static Object so;

    public static void main(String[] args) {
        System.out.println("int=" + si + " long=" + sl + " double=" + sd);
        System.out.println("boolean=" + sb + " char=[" + sc + "] ref=" + so);
        // ⭐ char prints as an invisible NUL. Use (int) sc to see 0.
        int local;
        // System.out.println(local);   // ⛔ COMPILE ERROR:
        //   "variable local might not have been initialized"
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// int=0 long=0 double=0.0
// boolean=false char=[] ref=null
// ──────────────────────────────────────────────────────────────────────
// ⭐⭐ WHY `so` IS null AND `si` IS 0: reference types default to null,
//   primitives default to zero/false. That difference is the source of the
//   single most common Java exception — a NullPointerException on a field
//   nobody assigned.
```

## 3.2 The default-values table is a concurrency clue — [SHOULD KNOW]

⭐ Because fields get defaults and locals do not, **reading a field written by another thread can observe the default** (0 / null) rather than the intended value, unless publication is safe. This is the entry point to `volatile` and `final`-field semantics in `04-ADVANCED-CORE-JAVA.md`. Plant the seed now: *defaults are not nothing; they are a value another thread can see.*

## 3.3 ⭐ Why `double` lies, and why money is never a `double` — [MUST KNOW]

**WHAT.** `double` is a binary fraction: `sign × mantissa × 2^exponent`. Most decimal fractions have **no finite binary representation** — exactly as 1/3 has no finite decimal one.

```java
public class MoneyIsNotADouble {
    public static void main(String[] args) {
        System.out.println(0.1 + 0.2);                  // ⛔ 0.30000000000000004
        System.out.println(0.1 + 0.2 == 0.3);           // ⛔ false
        System.out.println(1.0 - 0.9);                  // ⛔ 0.09999999999999998
        System.out.println(0.1 * 3);                    // ⛔ 0.30000000000000004

        // ⭐ and the one that actually loses MONEY:
        double total = 0;
        for (int i = 0; i < 10; i++) total += 0.1;
        System.out.println("10 × 0.1 = " + total);      // ⛔ 0.9999999999999999
        System.out.println("(int)(total * 100) = " + (int)(total * 100));
        // ⛔ 99 — not 100. You have lost a cent, by truncation.

        // ✅ FIX 1 — integer minor units. The DEFAULT choice for money.
        long cents = 0;
        for (int i = 0; i < 10; i++) cents += 10;
        System.out.println("cents = " + cents);         // ✅ 100, exactly

        // ✅ FIX 2 — BigDecimal, constructed from a STRING.
        java.math.BigDecimal a = new java.math.BigDecimal("0.1");
        java.math.BigDecimal b = new java.math.BigDecimal("0.2");
        System.out.println("BD  = " + a.add(b));        // ✅ 0.3

        // ⛔ FIX 2, DONE WRONG — the trap inside the fix:
        System.out.println(new java.math.BigDecimal(0.1));
        // ⛔ 0.1000000000000000055511151231257827021181583404541015625
        //   The double was ALREADY wrong before BigDecimal saw it.
        System.out.println(java.math.BigDecimal.valueOf(0.1));
        // ✅ 0.1 — valueOf goes through Double.toString, which is correct
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// 0.30000000000000004
// false
// 0.09999999999999998
// 0.30000000000000004
// 10 × 0.1 = 0.9999999999999999
// (int)(total * 100) = 99
// cents = 100
// BD  = 0.3
// 0.1000000000000000055511151231257827021181583404541015625
// 0.1
// ──────────────────────────────────────────────────────────────────────
```

⭐⭐ **The decision, and the honest trade-off:**

| Approach | When | Cost |
|---|---|---|
| ⭐ **`long` minor units** (cents, paise, micros) | almost always — money, prices, balances | you must never forget the unit. Name the variable `priceCents`, and never expose it in an API as a bare number |
| **`BigDecimal`** | when you need decimal semantics, rounding modes, or arbitrary scale (tax, interest, invoicing) | ⛔ ~10–50× slower than `double`, allocates on every operation, and `equals` compares **scale** (`2.0` ≠ `2.00`) — use `compareTo` |
| `double` | scientific computation, graphics, anything where relative error is fine | ⛔ never for money, never for equality comparison |

```java
// ⭐ the BigDecimal `equals` trap — asked surprisingly often
BigDecimal x = new BigDecimal("2.0");
BigDecimal y = new BigDecimal("2.00");
System.out.println(x.equals(y));        // ⛔ false — different scale
System.out.println(x.compareTo(y));     // ✅ 0 — numerically equal
// 🔑 "For BigDecimal, equals compares value AND scale; compareTo compares
//     value only. So use compareTo for numeric equality — and note that
//     this also means BigDecimal is a poor HashMap key if the same number
//     can arrive at different scales."
```

## 3.4 `char` and Unicode — [SHOULD KNOW]

⭐ **A `char` is a UTF-16 code unit, not a character.** This distinction causes real bugs with emoji, mathematical symbols and CJK extension characters.

```java
public class CharIsNotACharacter {
    public static void main(String[] args) {
        char c = 'a';
        System.out.println(c);              // a
        System.out.println((int) c);        // 97    ⭐ a char IS a number
        System.out.println('a' + 1);        // 98    ⭐ NOT 'b' — an int!
        System.out.println((char)('a' + 1));// b     ← you must cast back

        String emoji = "🙂";
        System.out.println("length()      = " + emoji.length());       // ⛔ 2
        System.out.println("charAt(0)     = " + emoji.charAt(0));      // ⛔ garbage
        System.out.println("codePointCount= " + emoji.codePointCount(0, emoji.length())); // ✅ 1
        System.out.println("codePoints()  = " + emoji.codePoints().count());              // ✅ 1
        // ⭐ WHY: 🙂 is U+1F642, which needs 17 bits. UTF-16 encodes it as a
        //   SURROGATE PA — two chars. length() counts CHARS, not characters.
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// a
// 97
// 98
// b
// length()      = 2
// charAt(0)     = ?
// codePointCount= 1
// codePoints()  = 1
// ──────────────────────────────────────────────────────────────────────
// ⛔ THE PRODUCTION BUG: `str.substring(0, 10)` on a user's name containing
//   emoji can split a surrogate pair and produce an invalid string that
//   breaks JSON serialisation, database inserts, or renders as ▯▯.
// ✅ Truncate on code-point boundaries, not char boundaries.
```

## 3.5 ⭐ Integer overflow — silent, and it will bite you — [SDE3 DIFFERENTIATOR]

Java integer arithmetic **wraps around** on overflow. There is no exception, no warning, no NaN. It just gives you the wrong answer.

```java
public class OverflowIsSilent {
    public static void main(String[] args) {
        System.out.println(Integer.MAX_VALUE + 1);      // ⛔ -2147483648
        System.out.println(Integer.MAX_VALUE * 2);      // ⛔ -2

        // ⭐ THE CLASSIC: the binary-search midpoint
        //   ⚠️ NOTE THE VALUES. With lo = 0 the sum CANNOT overflow — which is
        //   exactly why this bug survives testing and only appears on a large
        //   array. You need lo + hi > Integer.MAX_VALUE.
        int lo = 1_500_000_000, hi = 2_000_000_000;     // ⭐ a big array
        int mid1 = (lo + hi) / 2;                       // ⛔ lo+hi overflows
        System.out.println("naive  mid = " + mid1);     //    → a NEGATIVE
        int mid2 = lo + (hi - lo) / 2;                  // ✅ correct
        System.out.println("safe   mid = " + mid2);
        int mid3 = (lo + hi) >>> 1;                     // ✅ also correct
        System.out.println("unsigned mid = " + mid3);   //   (>>> treats the
                                                        //    wrapped bits as
                                                        //    unsigned)
        System.out.println("(with lo=0 the naive form is FINE: " + ((0 + hi) / 2) + ")");
        // ⭐ This exact bug lived in java.util.Arrays.binarySearch for NINE
        //   YEARS (fixed in Java 6). Joshua Bloch wrote it up. If the JDK
        //   had it, your code has it.

        // ⭐ THE OTHER CLASSIC: the multiplication that overflows before
        //   it is widened.
        long nanos1 = 1000 * 60 * 60 * 24 * 30;         // ⛔ int math FIRST
        System.out.println("wrong = " + nanos1);        //    → -1702967296
        long nanos2 = 1000L * 60 * 60 * 24 * 30;        // ✅ the L matters
        System.out.println("right = " + nanos2);

        // ✅ THE FIX when you need to KNOW: the *Exact methods throw
        System.out.println(Math.addExact(Integer.MAX_VALUE, 1));
        // ⛔ ArithmeticException: integer overflow     ← this is what you want
        System.out.println(Math.multiplyExact(1_000_000, 1_000_000));
        // ⛔ ArithmeticException: integer overflow
        // also: subtractExact, negateExact, incrementExact, toIntExact
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// -2147483648
// -2
// naive  mid = -397483648            ⛔ NEGATIVE — the search is now broken
// safe   mid = 1750000000
// unsigned mid = 1750000000
// (with lo=0 the naive form is FINE: 1000000000)   ⭐ and THAT is why the bug
// wrong = -1702967296                                survives every small test
// right = 2592000000
// Exception in thread "main" java.lang.ArithmeticException: integer overflow
// 	at java.base/java.lang.Math.addExact(Math.java:911)
// 	at OverflowIsSilent.main(OverflowIsSilent.java:32)
// ──────────────────────────────────────────────────────────────────────
// ⚠️ The JDK-internal line number (911 here, Temurin 21.0.12.1) varies by JDK
//   build. Your stack trace will differ; that is expected and harmless.
// ⭐ THE ASYMMETRY TRAP: Math.abs(Integer.MIN_VALUE) == Integer.MIN_VALUE.
//   It is negative, because +2147483648 does not fit in an int. So
//   `Math.abs(x)` can return a NEGATIVE number. Guard it, or use
//   Math.absExact (throws) or a long.
// 🔑 THE INTERVIEW LINE: "Java integer overflow wraps silently — no
//    exception, no saturation. The two places it bites are the binary-search
//    midpoint and any int multiplication that is assigned to a long, because
//    the arithmetic happens at int width before the widening. I use
//    lo + (hi - lo) / 2 and Math.multiplyExact, and Math.abs needs a guard
//    because abs(MIN_VALUE) is MIN_VALUE."
```

## 3.6 Literals — [SHOULD KNOW]

```java
public class Literals {
    public static void main(String[] args) {
        // ⭐ underscores in numeric literals (Java 7+) — grouping only,
        //   ignored by the compiler. Massively improves readability.
        int million   = 1_000_000;
        long card     = 4111_1111_1111_1111L;     // ⭐ capital L. Lowercase l
        double pi     = 3.141_592_653;            //   is indistinguishable
        int mask      = 0b1010_0001_1000_0101;    //   from a 1 in most fonts
        System.out.println(million + " " + card + " " + pi);

        // the four bases
        int dec = 42;             // decimal
        int hex = 0x2A;           // ⭐ hexadecimal
        int oct = 052;            // ⚠️ a LEADING ZERO means OCTAL.
                                  //   052 == 42. This has caused real bugs:
                                  //   someone writes 09 and gets a COMPILE
                                  //   ERROR because 9 is not an octal digit.
        int bin = 0b101010;       // ⭐ binary (Java 7+)
        System.out.printf("dec=%d hex=%d oct=%d bin=%d%n", dec, hex, oct, bin);
        System.out.printf("as hex: %x  as octal: %o  as binary: %s%n",
                          dec, dec, Integer.toBinaryString(dec));

        // ⛔ ILLEGAL underscore positions (compile errors):
        // int bad1 = _1000;      // at the start
        // int bad2 = 1000_;      // at the end
        // double bad3 = 3._14;   // adjacent to the decimal point
        // long bad4 = 100_L;     // adjacent to the type suffix
        // String s = "_";        // (fine — that's a String, not a literal)

        // ⭐ floating-point suffixes
        float  f = 1.5f;          // ⛔ REQUIRED: 1.5 is a double, and
                                  //   double → float is a narrowing conversion
        double d = 1.5;           // no suffix needed
        double d2 = 1.5d;         // optional, and clearer in a table of numbers
        System.out.println(f + " " + d + " " + d2);

        // ⭐ hex floating point — legal, and used for exact constants
        double exact = 0x1.8p1;   // 1.5 × 2^1 = 3.0
        System.out.println(exact);

        // `final` on a primitive: a compile-time CONSTANT
        final int MAX_RETRIES = 3;
        // MAX_RETRIES = 4;       // ⛔ compile error
        System.out.println(MAX_RETRIES);
        // ⭐ a `final` primitive initialised with a constant expression is a
        //   COMPILE-TIME CONSTANT: it is INLINED into every class that uses
        //   it. That is why changing a constant in a library requires
        //   RECOMPILING the callers — the old value is baked into their .class
        //   files. This is a real, occasionally catastrophic, deployment bug.
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// 1000000 4111111111111111 3.141592653
// dec=42 hex=42 oct=42 bin=42
// as hex: 2a  as octal: 52  as binary: 101010
// 1.5 1.5 1.5
// 3.0
// 3
// ──────────────────────────────────────────────────────────────────────
```

---

<a name="part-4"></a><a name="part-4--wrappers-and-autoboxing"></a>
# PART 4 · Wrappers and autoboxing

## 4.1 The eight wrappers — [MUST KNOW]

| Primitive | Wrapper | ⭐ Parsing | ⭐ Converting | Notes |
|---|---|---|---|---|
| `byte` | `Byte` | `Byte.parseByte(s)` | `Byte.valueOf(s)` | |
| `short` | `Short` | `Short.parseShort(s)` | `Short.valueOf(s)` | |
| `int` | `Integer` | `Integer.parseInt(s)` | `Integer.valueOf(s)` | ⭐ **cached** |
| `long` | `Long` | `Long.parseLong(s)` | `Long.valueOf(s)` | ⭐ **cached** |
| `float` | `Float` | `Float.parseFloat(s)` | `Float.valueOf(s)` | |
| `double` | `Double` | `Double.parseDouble(s)` | `Double.valueOf(s)` | |
| `char` | `Character` | — (no `parseChar`) | `Character.valueOf(c)` | ⭐ the name is not `Char` |
| `boolean` | `Boolean` | `Boolean.parseBoolean(s)` | `Boolean.valueOf(b)` | ⭐⭐ only two instances exist |

⭐⭐ **`parseX` returns a primitive; `valueOf` returns the wrapper.** They are not interchangeable, and `valueOf` on the numeric types goes through the cache.

⛔ **`new Integer(42)` is deprecated since Java 9 and marked `forRemoval`.** It always allocates, defeating the cache. Use `Integer.valueOf(42)` or just `42`.

```java
// ⭐ the two surprises in this table:
System.out.println(Boolean.parseBoolean("TRUE"));    // true  (case-insensitive)
System.out.println(Boolean.parseBoolean("yes"));     // ⛔ FALSE. Only "true"
System.out.println(Boolean.parseBoolean(null));      // ⛔ false — NO exception!
// ⭐⭐ parseBoolean never throws. Anything that is not "true" (ignoring case)
//   is false, including null and "1". That is a silent configuration bug:
//   Boolean.parseBoolean(System.getProperty("feature.enabled")) is false
//   when the property is missing, when it is "yes", when it is "1", and when
//   it is "True " with a trailing space. Validate config explicitly.
```

## 4.2 ⭐⭐ The cache, and the `==` trap that fails only sometimes — [MUST KNOW]

```java
public class TheWrapperCache {
    public static void main(String[] args) {
        Integer a = 127, b = 127;       // autoboxed → Integer.valueOf(127)
        Integer c = 128, d = 128;       // autoboxed → Integer.valueOf(128)

        System.out.println(a == b);                 // ⭐ true
        System.out.println(c == d);                 // ⛔ FALSE
        System.out.println(c.equals(d));            // ✅ true
        System.out.println(System.identityHashCode(a) == System.identityHashCode(b));
                                                    // true — literally the same object
        // ⭐ WHY: Integer.valueOf caches −128..127 (IntegerCache). Inside
        //   that range every call returns the SAME object, so `==` on
        //   references succeeds. Outside it, two distinct objects, so `==`
        //   compares identity and fails.

        // the cache bounds are configurable at the top end:
        //   java -XX:AutoBoxCacheMax=10000 ...
        // ⛔ never rely on that. The BOTTOM (−128) is fixed by the spec.

        // Long and Short are also cached (−128..127). Character caches 0..127.
        Long l1 = 127L, l2 = 127L;   System.out.println(l1 == l2);   // true
        Long l3 = 128L, l4 = 128L;   System.out.println(l3 == l4);   // ⛔ false
        // ⭐ Boolean, Byte: ALL values cached. Float, Double: NEVER cached
        //   (infinitely many values).

        // ⛔ AND THE VERSION THAT BREAKS IN PRODUCTION:
        Integer x = 127;
        int y = 127;
        System.out.println(x == y);   // ✅ TRUE — one side is a primitive, so
                                      //   x is UNBOXED and this is a numeric
                                      //   comparison. Different rule entirely.
        Integer z = null;
        // System.out.println(z == y); // ⛔ NullPointerException at RUNTIME
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// true
// false
// true
// true
// true
// false
// true
// ──────────────────────────────────────────────────────────────────────
// ⛔ THE PRODUCTION INCIDENT: an `Integer` id compared with `==` in an
//   equality check. It works for ids 1..127 — so it passes every test, every
//   code review, and the first three months of production. It starts failing
//   at id 128, intermittently, for some users. There is no error, no log, no
//   exception: just wrong answers.
// 🔑 THE INTERVIEW LINE: "Never compare wrapper types with ==. Integer
//    .valueOf caches −128 to 127, so == appears to work for small values and
//    silently fails above 128 — which means the bug is invisible in testing
//    and appears in production once your ids grow. Use equals, or better,
//    unbox to a primitive first, and enable -Xlint:all which warns on some
//    of these."
```

## 4.3 Autoboxing and unboxing — [MUST KNOW]

**WHAT.** The compiler inserts `valueOf` (boxing) and `xValue` (unboxing) calls where a primitive and its wrapper meet. It is syntactic sugar, not magic.

```java
Integer boxed = 42;              // javac inserts: Integer.valueOf(42)
int prim = boxed;                // javac inserts: boxed.intValue()
boxed++;                         // ⭐ unbox → increment → BOX AGAIN. Three ops.
Integer sum = 1 + boxed;         // unbox boxed, add, box the result

List<Integer> list = new ArrayList<>();
list.add(1);                     // boxes: list.add(Integer.valueOf(1))
int first = list.get(0);         // unboxes: list.get(0).intValue()
// ⭐ a List<int> is IMPOSSIBLE — generics only work with reference types.
//   That single restriction is why boxing exists in collections at all,
//   and why the (still preview) "value classes" / Project Valhalla work
//   matters so much for performance.
```

## 4.4 ⭐ The null-unboxing NPE — [MUST KNOW]

```java
public class NullUnboxing {
    // ⭐ A very common shape: a nullable column mapped to a wrapper field.
    static Integer findStock(String sku) {
        return sku.equals("SKU-9") ? null : 42;      // out of stock → null
    }

    public static void main(String[] args) {
        Integer stock = findStock("SKU-9");

        // ⛔ 1. unboxing a null
        // int n = stock;                            // NullPointerException

        // ⛔ 2. the SAME THING, hidden inside a comparison
        // if (stock > 0) { }                        // NullPointerException
        //   WHY: `>` is a numeric operator, so stock is UNBOXED first.

        // ⛔ 3. hidden inside a ternary — see §5.7, the nastiest version

        // ✅ THE FIXES
        if (stock != null && stock > 0) {            // ⭐ short-circuit saves
            System.out.println("in stock");          //   you: the null check
        } else {                                     //   runs FIRST and &&
            System.out.println("out of stock");      //   skips the unboxing
        }

        int safe = (stock == null) ? 0 : stock;      // ✅ explicit default
        System.out.println("safe = " + safe);

        int safe2 = java.util.Optional.ofNullable(stock).orElse(0);   // ✅
        System.out.println("safe2 = " + safe2);

        int safe3 = java.util.Objects.requireNonNullElse(stock, 0);   // ✅ since 9
        System.out.println("safe3 = " + safe3);
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// out of stock
// safe = 0
// safe2 = 0
// safe3 = 0
// ──────────────────────────────────────────────────────────────────────
// ⭐⭐ WHY THIS IS DANGEROUS: the NullPointerException is thrown at the
//   UNBOXING site, not where the null came from. The stack trace points at
//   `if (stock > 0)` and says nothing about findStock returning null.
//   Java 14+ "helpful NPE messages" (JEP 358, ON BY DEFAULT since 15) helps:
//   "Cannot invoke java.lang.Integer.intValue() because <local3> is null"
// ✅ VERIFY: java -XX:+ShowCodeDetailsInExceptionMessages (default since 15)
```

## 4.5 The boxing cost in a loop — [SHOULD KNOW]

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.02 — the cost of boxing, measured THREE ways
// ══════════════════════════════════════════════════════════════════════
// WHAT   : the same 50-million-iteration accumulation with an `Integer`
//          accumulator, a primitive `long`, and a `Long` accumulator.
// WHY    : three variants are needed to separate TWO different problems that
//          a single comparison hides. Variant 1 is slow AND WRONG; variant 3
//          is slow but correct. Only by comparing 3 against 2 do you measure
//          what boxing itself costs.
// OUTPUT : verified on Temurin 21.0.12.1 — shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class BoxingCost {
    // ⭐ N chosen so the true sum fits in a long but NOT in an int.
    //   sum(0..N-1) = N*(N-1)/2 = 1,249,999,975,000,000 — way past int's max.
    static final int N = 50_000_000;

    public static void main(String[] args) {
        // ── VARIANT 1: `Integer` accumulator — TWO bugs at once ───────────
        long t0 = System.nanoTime();
        Integer intSum = 0;
        for (int i = 0; i < N; i++) {
            intSum = intSum + i;
            // ⭐ desugars to: intSum = Integer.valueOf(intSum.intValue() + i);
            //   Bug A: ONE NEW OBJECT per iteration (above the 127 cache).
            //   Bug B: the arithmetic is at INT WIDTH, so it OVERFLOWS and
            //          wraps — §3.5 arriving inside a performance example.
        }
        long t1 = System.nanoTime();

        // ── VARIANT 2: primitive `long` — correct and fast ────────────────
        long primSum = 0;
        for (int i = 0; i < N; i++) primSum += i;
        long t2 = System.nanoTime();

        // ── VARIANT 3: `Long` accumulator — isolates BOXING from OVERFLOW ─
        //   Correct answer, still slow. This is the honest measurement of
        //   what boxing alone costs.
        Long longSum = 0L;
        for (int i = 0; i < N; i++) {
            longSum = longSum + i;      // unbox Long, add as long, box again.
                                        // ⭐ Long.valueOf caches only -128..127
        }
        long t3 = System.nanoTime();

        System.out.printf("⛔ Integer accumulator : %7d ms   sum=%d%n", (t1-t0)/1_000_000, intSum);
        System.out.printf("✅ primitive long      : %7d ms   sum=%d%n", (t2-t1)/1_000_000, primSum);
        System.out.printf("⛔ Long accumulator    : %7d ms   sum=%d%n", (t3-t2)/1_000_000, longSum);
        System.out.println();
        System.out.println("  the Integer sum is WRONG: " + intSum + " != " + primSum);
        System.out.println("  it wrapped at Integer.MAX_VALUE = " + Integer.MAX_VALUE);
        System.out.println("  Long sum correct?  " + (longSum.longValue() == primSum));
        System.out.printf("  boxing-only cost (Long vs long): %.1fx%n",
                          (double)(t3-t2)/Math.max(1,(t2-t1)));
        System.out.printf("  total cost (Integer vs long)   : %.1fx%n",
                          (double)(t1-t0)/Math.max(1,(t2-t1)));
    }
}
// ── OUTPUT (verbatim, Temurin 21.0.12.1 — absolute ms are machine-specific) ─
// ⛔ Integer accumulator :     254 ms   sum=1283106752
// ✅ primitive long      :      18 ms   sum=1249999975000000
// ⛔ Long accumulator    :     225 ms   sum=1249999975000000
//
//   the Integer sum is WRONG: 1283106752 != 1249999975000000
//   it wrapped at Integer.MAX_VALUE = 2147483647
//   Long sum correct?  true
//   boxing-only cost (Long vs long): 11.9x
//   total cost (Integer vs long)   : 13.5x
// ──────────────────────────────────────────────────────────────────────
// ⚠️ NOT A JMH BENCHMARK. The milliseconds are machine-specific — I have seen
//   the boxing-only ratio between ~8x and ~120x depending on heap size, GC and
//   how much the JIT could optimise. The DIRECTION is reliable; the magnitude
//   is not. Never quote a ratio like this as fact without saying so.
//
// ⭐⭐ THE POINT OF RUNNING THREE VARIANTS, and it is the real lesson here:
//   a two-way comparison would have told you "the boxed version is 13.5x
//   slower", and you would have missed that its ANSWER WAS WRONG. Separating
//   the overflow (variant 1) from the boxing (variant 3) shows two independent
//   defects in one line of code: `Integer sum = 0; for (...) sum += i;`.
//   Benchmarking only for speed is how you ship a fast wrong answer.
//
// ✅ THE RULES THAT FOLLOW:
//   • never use a wrapper as a loop accumulator — use the primitive
//   • never use an `int` accumulator for anything that can exceed 2³¹ —
//     use `long`, or `Math.addExact` if you want it to throw instead
//   • in a hot path over a `List<Integer>`, prefer `mapToLong`/`mapToInt`
//     streams or an index loop, so the unboxing happens once per element
//     rather than producing a new boxed object per element
// 🔑 THE INTERVIEW LINE: "Autoboxing in a loop costs an allocation per
//    iteration above the cache range, which shows up as GC pressure rather
//    than arithmetic — I measured roughly an order of magnitude on a
//    50-million-iteration accumulation. But the more interesting failure is
//    that an `Integer` accumulator also does its arithmetic at int width, so
//    it silently overflowed and produced a wrong total while still being
//    'the slow one' in the benchmark. Measuring only throughput would have
//    hidden that entirely."
```

---

<a name="part-5"></a><a name="part-5--operators"></a>
# PART 5 · Operators

## 5.1 Arithmetic — [MUST KNOW]

| Operator | Notes |
|---|---|
| `+` | ⭐ also string concatenation if either operand is a `String` (§11.3) |
| `-` `*` | ordinary; ⛔ overflow wraps silently (§3.5) |
| `/` | ⭐ **integer division TRUNCATES toward zero.** `7/2 == 3`, `-7/2 == -3` |
| `%` | ⭐ remainder, not modulus. **The sign follows the dividend.** `-7 % 2 == -1` |
| `++` `--` | prefix returns the new value, postfix returns the old |

```java
public class ArithmeticEdges {
    public static void main(String[] args) {
        System.out.println(7 / 2);        // 3      ⭐ truncates, does not round
        System.out.println(-7 / 2);       // -3     ⭐ toward ZERO, not down
        System.out.println(7 % 2);        // 1
        System.out.println(-7 % 2);       // ⛔ -1  — sign follows the DIVIDEND
        System.out.println(7 % -2);       // 1
        System.out.println(-7 % -2);      // -1

        // ⭐ THE CONSEQUENCE: `x % n` is NOT a safe way to get a bucket index
        //   when x can be negative. The classic bug: a hash-based shard.
        int hash = -5;
        System.out.println("naive shard  = " + (hash % 3));       // ⛔ -2
        System.out.println("floorMod     = " + Math.floorMod(hash, 3)); // ✅ 1
        System.out.println("Math.floorDiv= " + Math.floorDiv(-7, 2));   // ✅ -4
        // ⭐ floorDiv rounds toward NEGATIVE INFINITY (the mathematical floor),
        //   so floorMod is always in [0, n). Use these for hashing and sharding.
        //   `HashMap` avoids the issue entirely with `(n-1) & hash` (§5.4).

        // prefix vs postfix
        int i = 5;
        System.out.println(i++);          // 5   ⭐ returns the OLD value, then
        System.out.println(i);            // 6      increments
        int j = 5;
        System.out.println(++j);          // 6   ⭐ increments, then returns
        System.out.println(j);            // 6

        // ⭐ the expression that surprises everyone:
        int k = 0;
        k = k++;
        System.out.println("k = " + k);   // ⛔ 0, NOT 1
        // WHY: `k++` evaluates to the OLD value of k (0) and, as a side
        //   effect, increments the VARIABLE k to 1. Then the assignment
        //   writes the expression's value (0) back into k. Net effect: 0.
        // ⛔ `x = x++` is always a no-op. javac -Xlint:all does not catch it,
        //   but every decent static analyser does.

        System.out.println(1.0 / 0.0);    // ⭐ Infinity — floating point does
        System.out.println(0.0 / 0.0);    // ⭐ NaN        NOT throw
        System.out.println(Double.isNaN(0.0 / 0.0));            // true
        System.out.println((0.0 / 0.0) == (0.0 / 0.0));         // ⛔ FALSE
        // ⭐ NaN is not equal to anything, including itself. ALWAYS use
        //   Double.isNaN(x), never x == Double.NaN.
        // System.out.println(1 / 0);     // ⛔ ArithmeticException: / by zero
        //   ⭐ integer division by zero THROWS; floating point does not.
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// 3
// -3
// 1
// -1
// 1
// -1
// naive shard  = -2
// floorMod     = 1
// Math.floorDiv= -4
// 5
// 6
// 6
// 6
// k = 0
// Infinity
// NaN
// true
// false
// ──────────────────────────────────────────────────────────────────────
```

## 5.2 Relational — [MUST KNOW]

`<  >  <=  >=  ==  !=`

⭐ **Rules that matter:**
- All six work on **numeric primitives** and compare by value.
- `==` and `!=` also work on **references**, where they compare **identity** (same object), not equality.
- `< > <= >=` on references is a **compile error**. You cannot order objects with operators — that is what `Comparable` is for (`06-COLLECTIONS`).
- ⚠️ `==` on two `String`s compiles fine and is almost always a bug (§11.2).

## 5.3 ⭐ `&&` vs `&`, `||` vs `|` — [MUST KNOW]

| Operator | Name | Short-circuits? | Use |
|---|---|---|---|
| `&&` | conditional AND | ✅ yes | ⭐ **the one you almost always want** |
| `&` | boolean AND *and* bitwise AND | ⛔ no | flags and masks (§5.4); boolean use is nearly always a bug |
| `\|\|` | conditional OR | ✅ yes | ⭐ **the one you almost always want** |
| `\|` | boolean OR *and* bitwise OR | ⛔ no | flags and masks |
| `!` | logical NOT | — | unary |
| `^` | XOR | — | flags, checksums |

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.03 — short-circuit, PROVEN with a side effect
// ══════════════════════════════════════════════════════════════════════
// WHAT   : a method with a visible side effect, used on both sides of &&
//          and &, so you can SEE which operands were evaluated.
// WHY    : short-circuiting is not a performance footnote — it is a
//          CORRECTNESS mechanism. Every null guard depends on it.
// OUTPUT : shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class ShortCircuitProof {

    // returns false, so the second operand is always *eligible* to be skipped
    static boolean touch(String label) {
        System.out.println("    evaluated " + label);
        return false;
    }

    static boolean thrower(String label) {
        System.out.println("    evaluated " + label + " (throws)");
        throw new IllegalStateException(label);
    }

    public static void main(String[] args) {
        System.out.println("① touch(a) && touch(b)");
        System.out.println("  result = " + (touch("a") && touch("b")));

        System.out.println("② touch(a) &  touch(b)");
        System.out.println("  result = " + (touch("a") & touch("b")));

        // ⭐⭐ THE REASON SHORT-CIRCUITING IS A CORRECTNESS FEATURE:
        String s = null;
        System.out.println("③ the null guard");
        if (s != null && s.length() > 3) {          // ✅ safe
            System.out.println("  long string");
        } else {
            System.out.println("  guarded: s was null, s.length() never ran");
        }
        // ⛔ with a single &, BOTH sides are evaluated → NullPointerException.
        //    The null guard is not a guard at all.

        System.out.println("④ short-circuit avoids the exception entirely");
        // ⭐⭐ `||` SHORT-CIRCUITS ONLY WHEN THE FIRST OPERAND IS *TRUE*.
        //   `false || thrower(...)` does NOT skip — it must evaluate the right
        //   side to know the answer. Getting this backwards is the single most
        //   common mistake when writing this example.
        boolean cheapTrue = true;
        boolean r = cheapTrue || thrower("expensive");  // ✅ thrower never runs
        System.out.println("  result = " + r);

        System.out.println("⑤ and the mirror image: false || ... does NOT skip");
        boolean cheapFalse = false;
        try {
            boolean r2 = cheapFalse || thrower("expensive");
            System.out.println("  result = " + r2);
        } catch (IllegalStateException e) {
            System.out.println("  ⛔ threw: the right side WAS evaluated");
        }
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ① touch(a) && touch(b)
//     evaluated a
//   result = false             ⭐ b NEVER evaluated — && stops at first FALSE
// ② touch(a) &  touch(b)
//     evaluated a
//     evaluated b                 ⛔ b WAS evaluated — `&` never stops
//   result = false
// ③ the null guard
//   guarded: s was null, s.length() never ran
// ④ short-circuit avoids the exception entirely
//   result = true              ⭐ thrower never ran — || stops at first TRUE
// ⑤ and the mirror image: false || ... does NOT skip
//     evaluated expensive (throws)
//   ⛔ threw: the right side WAS evaluated
// ──────────────────────────────────────────────────────────────────────
// ⭐⭐ THE RULE, STATED PRECISELY:
//   `&&` stops as soon as the result is KNOWN TO BE FALSE  → first false wins
//   `||` stops as soon as the result is KNOWN TO BE TRUE   → first true  wins
//   Neither stops "on the first operand". They stop when the ANSWER is settled.
// 🔑 THE INTERVIEW LINE: "&& and || short-circuit; & and | on booleans
//    evaluate both operands. That makes short-circuiting a correctness
//    mechanism, not just an optimisation — `s != null && s.length() > 0`
//    only works because && stops at the first false. Single & there is a
//    NullPointerException. And the detail people get wrong: || stops at the
//    first TRUE, not at the first operand, so `false || expensive()` still
//    calls expensive(). Legitimate uses of & on booleans are essentially
//    nonexistent, so seeing it in a code review is a smell."
```

## 5.4 Bitwise — every one, with the real use cases — [SHOULD KNOW / SDE3 DIFF]

| Op | Name | Truth | Mnemonic |
|---|---|---|---|
| `a & b` | AND | 1 only if **both** are 1 | "keep what both have" |
| `a \| b` | OR | 1 if **either** is 1 | "union" |
| `a ^ b` | XOR | 1 if they **differ** | "toggle" |
| `~a` | NOT | flips every bit | unary; ⭐ `~x == -x - 1` |
| `a << n` | left shift | ×2ⁿ | ⛔ overflow discarded |
| `a >> n` | arithmetic right | ÷2ⁿ, **sign-extended** | keeps the sign |
| `a >>> n` | logical right | ÷2ⁿ, **zero-filled** | ⭐ unsigned |

⭐ **Shift counts are taken mod the type width.** For `int`, `x << 33` is `x << 1`. For `long`, mod 64. This is a genuine trap — a shift by a computed amount can silently do the wrong thing.

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.04 — the six real uses of bitwise operators
// ══════════════════════════════════════════════════════════════════════
// WHAT   : flags, masks, parity, power-of-two, the HashMap index trick,
//          and the swap-without-temp.
// WHY    : these are the only six places bitwise ops legitimately appear in
//          application code. Learn these and you can read any of them.
// OUTPUT : shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class BitwiseInPractice {

    // ── USE 1: FLAG SETS ───────────────────────────────────────────────
    // ⭐ one int holds 32 independent booleans. This is exactly what
    //   java.lang.reflect.Modifier, Pattern.compile flags, and EnumSet do.
    static final int READ    = 1;        // 0001
    static final int WRITE   = 1 << 1;   // 0010
    static final int EXECUTE = 1 << 2;   // 0100
    static final int DELETE  = 1 << 3;   // 1000

    static boolean has(int perms, int flag)  { return (perms & flag) == flag; }
    static int     add(int perms, int flag)  { return perms | flag; }
    static int     rem(int perms, int flag)  { return perms & ~flag; }
    static int     tog(int perms, int flag)  { return perms ^ flag; }

    // ── USE 2: MASKS — keep only the bits you want ─────────────────────
    static int lowByte(int x)     { return x & 0xFF; }        // ✅ unsigned
    static int lowNibble(int x)   { return x & 0x0F; }
    // ⭐ `& 0xFF` is THE idiom for converting a signed byte to an unsigned
    //   int. Java's byte is signed, so (byte)200 is −56, and −56 & 0xFF is 200.

    public static void main(String[] args) {
        int perms = add(add(0, READ), WRITE);
        System.out.println("perms = " + perms + " (READ|WRITE)");
        System.out.println("  has READ    : " + has(perms, READ));
        System.out.println("  has EXECUTE : " + has(perms, EXECUTE));
        perms = add(perms, EXECUTE);
        System.out.println("  after +EXEC : " + perms);
        perms = rem(perms, WRITE);
        System.out.println("  after -WRITE: " + perms + " has WRITE = " + has(perms, WRITE));
        System.out.println("  toggle READ : " + tog(perms, READ));

        // ── USE 3: PARITY / EVEN-ODD without a division ────────────────
        System.out.println("7 & 1 = " + (7 & 1) + "   (1 = odd)");
        System.out.println("8 & 1 = " + (8 & 1) + "   (0 = even)");
        // ⭐ `x & 1` works for negatives too, where `x % 2` gives −1.
        System.out.println("-7 % 2 = " + (-7 % 2) + "   ⛔ not 1");
        System.out.println("-7 & 1 = " + (-7 & 1) + "   ✅ 1");

        // ── USE 4: IS IT A POWER OF TWO? ───────────────────────────────
        // ⭐ x > 0 && (x & (x - 1)) == 0 — one of the most-asked bit tricks.
        //   A power of two has exactly one bit set; subtracting 1 turns that
        //   bit off and turns every lower bit on, so the AND is zero.
        for (int x : new int[]{1, 2, 6, 8, 16, 1024, 1023}) {
            System.out.printf("  %4d power-of-two? %b%n", x, x > 0 && (x & (x - 1)) == 0);
        }

        // ── USE 5: ⭐⭐⭐ THE HASHMAP INDEX TRICK ────────────────────────
        // HashMap does:  index = (n - 1) & hash      where n = table length
        // WHY it works: if n is a power of two, n-1 is a mask of low 1-bits
        //   (16-1 = 0b01111), so ANDing is IDENTICAL to hash % n — but
        //   without a division, which is ~10× slower, and without the
        //   negative-result problem of %.
        int n = 16;
        System.out.println("n = " + n + ", n-1 = " + Integer.toBinaryString(n - 1));
        // ⭐ THREE columns: what HashMap does, what the naive `%` does, and
        //   what the mathematically-correct floorMod does. The middle column
        //   is the bug; the third is the proof that `&` is right.
        System.out.println("  hash  (n-1)&hash  hash%n  floorMod   verdict");
        for (int hash : new int[]{0, 5, 15, 16, 17, 31, -1}) {
            int anded   = (n - 1) & hash;
            int naive   = hash % n;                      // ⛔ can be negative
            int floored = Math.floorMod(hash, n);        // ✅ always in [0,n)
            System.out.printf("  %4d  %10d  %6d  %8d   %s%n",
                hash, anded, naive, floored,
                (naive == floored) ? "✅ % agrees"
                                   : "⛔ % gives " + naive + ", not " + floored);
        }
        // ⭐⭐ THIS IS WHY HashMap's CAPACITY IS ALWAYS A POWER OF TWO, and
        //   why it rounds your requested initial capacity UP to one.

        // ── USE 6: XOR SWAP (⛔ know it, never use it) ─────────────────
        int p = 3, q = 7;
        p ^= q; q ^= p; p ^= q;
        System.out.println("xor swap: p=" + p + " q=" + q);
        // ⛔ slower than a temp on every modern CPU, unreadable, and BREAKS
        //   when p and q are the same variable (both become 0). It is an
        //   interview party trick, not a technique.

        // ── USE 2 in action: the byte-to-unsigned idiom ────────────────
        byte signed = (byte) 200;
        System.out.println("byte 200 as signed   = " + signed);          // ⛔ -56
        System.out.println("byte 200 as unsigned = " + (signed & 0xFF)); // ✅ 200
        System.out.println("Byte.toUnsignedInt   = " + Byte.toUnsignedInt(signed)); // ✅ 200

        // ── the shift-modulo trap ──────────────────────────────────────
        System.out.println("1 << 33 = " + (1 << 33) + "  ⛔ == 1 << 1 = " + (1 << 1));
        System.out.println("1L << 33 = " + (1L << 33) + "  ✅ long shifts mod 64");
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// perms = 3 (READ|WRITE)
//   has READ    : true
//   has EXECUTE : false
//   after +EXEC : 7
//   after -WRITE: 5 has WRITE = false
//   toggle READ : 4
// 7 & 1 = 1   (1 = odd)
// 8 & 1 = 0   (0 = even)
// -7 % 2 = -1   ⛔ not 1
// -7 & 1 = 1   ✅ 1
//      1 power-of-two? true
//      2 power-of-two? true
//      6 power-of-two? false
//      8 power-of-two? true
//     16 power-of-two? true
//   1024 power-of-two? true
//   1023 power-of-two? false
// n = 16, n-1 = 1111
//   hash  (n-1)&hash  hash%n  floorMod   verdict
//      0           0       0         0   ✅ % agrees
//      5           5       5         5   ✅ % agrees
//     15          15      15        15   ✅ % agrees
//     16           0       0         0   ✅ % agrees
//     17           1       1         1   ✅ % agrees
//     31          15      15        15   ✅ % agrees
//     -1          15      -1        15   ⛔ % gives -1, not 15
// xor swap: p=7 q=3
// byte 200 as signed   = -56
// byte 200 as unsigned = 200
// Byte.toUnsignedInt   = 200
// 1 << 33 = 2  ⛔ == 1 << 1 = 2
// 1L << 33 = 8589934592  ✅ long shifts mod 64
// ──────────────────────────────────────────────────────────────────────
// ⭐⭐ THE LAST ROW OF THE HASH TABLE IS THE WHOLE POINT: for a NEGATIVE hash,
//   `%` gives a negative index (→ ArrayIndexOutOfBounds) while `&` gives a
//   valid one. HashMap never has to think about negative hashes.
// 🔑 THE INTERVIEW LINE: "HashMap indexes with (n-1) & hash rather than
//    hash % n for two reasons: it avoids a division, and — more importantly —
//    it always yields a non-negative index even for negative hash codes,
//    which % does not. That only works because the table length is always a
//    power of two, which is why HashMap rounds your requested capacity up."
```

## 5.5 Shifts — [SHOULD KNOW]

```java
int x = -8;
System.out.println(x >> 1);      // -4   ⭐ arithmetic: sign-extended (1s fill)
System.out.println(x >>> 1);     // 2147483644  ⭐ logical: zeros fill
System.out.println(x << 1);      // -16  (× 2, overflow discarded)
// ⭐ RULE: >> preserves the sign; >>> does not. For non-negative values they
//   are identical, so >>> only matters when the value can be negative.
// ⭐ THE MAIN USE OF >>>: treating an int as an unsigned 32-bit quantity —
//   the binary-search midpoint (§3.5) and hashing.
// ⚠️ there is no `<<<=`. And shift counts wrap: int mod 32, long mod 64.
```

## 5.6 Assignment and the implicit-cast surprise — [SHOULD KNOW]

```java
public class CompoundAssignmentHidesACast {
    public static void main(String[] args) {
        byte b = 1;
        b += 1;                      // ✅ COMPILES. b is now 2
        // b = b + 1;                // ⛔ COMPILE ERROR: "incompatible types:
                                     //   possible lossy conversion from int to byte"
        // ⭐⭐ WHY THEY DIFFER: `b += 1` is defined by the language as
        //   `b = (byte)(b + 1)` — the cast is INSERTED FOR YOU. So compound
        //   assignment silently narrows. This is in the JLS (§15.26.2).

        short s = 1;  s += 1;        // ✅ same
        char c = 'a'; c += 1;        // ✅ same — c is now 'b'
        System.out.println(b + " " + s + " " + c);

        // ⛔ THE DANGER: the silent narrowing can LOSE DATA without warning.
        byte big = 100;
        big += 100;                  // ✅ compiles
        System.out.println("big = " + big);   // ⛔ -56. Overflowed and wrapped.
        // ⭐ javac -Xlint:all does NOT warn about this. It is legal Java.
        //   This is why static analysis (SpotBugs, ErrorProne) earns its keep.

        float f = 1;  f /= 2;        // ✅
        System.out.println(f);
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// 2 2 b
// big = -56
// 0.5
// ──────────────────────────────────────────────────────────────────────
// 🔑 THE INTERVIEW LINE: "Compound assignment includes an implicit cast, so
//    `byte b = 1; b += 1;` compiles while `b = b + 1;` does not. The
//    consequence is that it can silently narrow and overflow — `byte b = 100;
//    b += 100;` gives −56 with no warning from javac. That's a genuine
//    argument for ErrorProne in a build, because -Xlint doesn't catch it."
```

## 5.7 ⭐ The ternary's numeric-promotion NPE trap — [SDE3 DIFFERENTIATOR]

**The rule, stated correctly — and it has two halves that people conflate:**

1. ⭐ **The conditional expression's TYPE is decided at compile time**, from the **static types of BOTH branches** (JLS 15.25), *before either branch is evaluated*.
2. ⭐ **Only the SELECTED branch is evaluated** at runtime. If the result type is a primitive numeric and the selected branch yields a boxed value — or `null` — it is **unboxed**, and unboxing `null` throws.

⛔ **The widespread misconception:** "if one branch is `int` and the other is `Integer`, the `Integer` branch is unboxed, so it can throw even when not selected." **That is false.** An unevaluated branch cannot throw. The danger is different, and more subtle.

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.05 — what the ternary actually does with null
// ══════════════════════════════════════════════════════════════════════
// WHAT   : seven cases. Predict EVERY one before running — the first one is
//          the one most people (and most blog posts) get wrong.
// WHY    : the real trap is not "the unselected branch throws". It is that
//          ADDING a primitive branch CHANGES THE EXPRESSION'S TYPE, which
//          turns a harmless null into a runtime NPE — at a call site that
//          used to be safe, with no change to that call site.
// OUTPUT : verified on Temurin 21.0.12.1 — shown below, exactly.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class TernaryNpe {
    static Integer nullable() { return null; }

    public static void main(String[] args) {
        boolean t = true, f = false;

        // ── A: the NULLABLE branch is NOT selected ───────────────────────
        // ⭐ NO NPE. Only the selected branch is evaluated, so nullable() is
        //   never even called. The result type is `int`, but there is nothing
        //   to unbox on the taken path.
        int a = t ? 1 : nullable();
        System.out.println("A  t ? 1 : nullable()          -> " + a);

        // ── B: the NULLABLE branch IS selected, result type is primitive ──
        // ⛔ NPE. Result type is `int`, selected value is null → unbox → throw.
        try { int b = t ? nullable() : 1; System.out.println("B -> " + b); }
        catch (NullPointerException e) {
            System.out.println("B  t ? nullable() : 1          -> NPE");
        }

        // ── C: BOTH branches boxed → result type is the wrapper ──────────
        // ✅ NO NPE. The null flows through as a null. No unboxing anywhere.
        Integer c = t ? nullable() : Integer.valueOf(1);
        System.out.println("C  t ? nullable() : valueOf(1) -> " + c);

        // ── D: result type is a REFERENCE type → no unboxing ─────────────
        Object d = t ? nullable() : "str";
        System.out.println("D  t ? nullable() : \"str\"       -> " + d);

        // ── E: the false branch is the null one, and IT is selected ──────
        try { int e = f ? 0 : (Integer) null; System.out.println("E -> " + e); }
        catch (NullPointerException ex) {
            System.out.println("E  f ? 0 : (Integer) null      -> NPE");
        }

        // ── F/G: `int` and the NULL LITERAL ──────────────────────────────
        // ⭐ The null literal is not a numeric type, so this is a REFERENCE
        //   conditional: the result type is lub(Integer, null) = Integer.
        //   NO unboxing. Neither form throws — F prints 1, G prints null.
        System.out.println("F  t ? 1 : null                -> " + (t ? 1 : null));
        System.out.println("G  f ? 1 : null                -> " + (f ? 1 : null));

        // ── ⭐⭐ H: THE SHAPE THAT ACTUALLY BITES IN PRODUCTION ───────────
        java.util.Map<String, Integer> counts = new java.util.HashMap<>();
        counts.put("SKU-1", null);              // ⭐ key PRESENT, value NULL.
                                                //   A HashMap allows this.
        try {
            int h = counts.containsKey("SKU-1") ? counts.get("SKU-1") : 0;
            System.out.println("H -> " + h);
        } catch (NullPointerException ex) {
            System.out.println("H  containsKey ? get : 0       -> NPE");
        }
        // ⭐ The guard WORKED — the key really is present — and it still threw,
        //   because the VALUE is null and the result type is `int`.

        // ── ⭐⭐⭐ I: AND getOrDefault DOES NOT SAVE YOU ────────────────────
        try {
            int i = counts.getOrDefault("SKU-1", 0);
            System.out.println("I -> " + i);
        } catch (NullPointerException ex) {
            System.out.println("I  getOrDefault(SKU-1, 0)      -> NPE  ⭐⭐⭐");
        }
        // ⭐⭐⭐ WHY: HashMap.getOrDefault is
        //     return (e = getNode(hash(key), key)) == null ? defaultValue : e.value;
        //   The NODE exists, so it returns e.value — which is null. The default
        //   is used only when the KEY IS ABSENT. "Present but null" is not
        //   "absent". Unboxing that null to `int` throws.
        System.out.println("J  getOrDefault(ABSENT, 0)     -> " + counts.getOrDefault("NOPE", 0));
        System.out.println("K  getOrDefault(SKU-1,0) boxed -> "
                           + (Object) counts.getOrDefault("SKU-1", 0));

        // ── ✅ THE FIXES THAT ACTUALLY WORK ──────────────────────────────
        Integer boxed = counts.get("SKU-1");
        int safe1 = (boxed == null) ? 0 : boxed;                  // ✅ explicit
        int safe2 = java.util.Optional.ofNullable(counts.get("SKU-1")).orElse(0);
        int safe3 = java.util.Objects.requireNonNullElse(counts.get("SKU-1"), 0);
        System.out.println("   fixes: " + safe1 + " " + safe2 + " " + safe3);
    }
}
// ── OUTPUT (verbatim, Temurin 21.0.12.1) ───────────────────────────────
// A  t ? 1 : nullable()          -> 1
// B  t ? nullable() : 1          -> NPE
// C  t ? nullable() : valueOf(1) -> null
// D  t ? nullable() : "str"       -> null
// E  f ? 0 : (Integer) null      -> NPE
// F  t ? 1 : null                -> 1
// G  f ? 1 : null                -> null
// H  containsKey ? get : 0       -> NPE
// I  getOrDefault(SKU-1, 0)      -> NPE  ⭐⭐⭐
// J  getOrDefault(ABSENT, 0)     -> 0
// K  getOrDefault(SKU-1,0) boxed -> null
//    fixes: 0 0 0
// ──────────────────────────────────────────────────────────────────────
```

⭐⭐ **THE REAL TRAP, and it is worse than the myth.** The expression's type is decided from **both** branches statically. So this refactor:

```java
Integer limit = config.getLimit();
Integer effective = (limit != null) ? limit : null;      // type: Integer. Safe.
// ... later someone "tidies up":
Integer effective2 = (limit != null) ? limit : 0;        // ⭐ type is STILL
                                                         //   Integer — fine
int effective3 = (limit != null) ? limit : 0;            // ⛔ type is now int.
                                                         //   If limit is null
                                                         //   and the condition
                                                         //   is false, 0 is fine;
                                                         //   but change the
                                                         //   condition and it
                                                         //   unboxes a null.
```

The generalisable lesson: **changing the type of one branch can change the type of the whole expression**, which changes whether unboxing happens. That is a source-compatible, behaviour-changing edit — invisible in a diff review, and it does not touch the line that throws.

⭐ **The two defensive rules that follow:**
1. ⛔ Never mix a boxed and an unboxed numeric type in a ternary. Make both branches the same type.
2. ⛔ Never unbox a ternary result into a primitive when any path can produce `null` — assign to the wrapper first, then null-check, then unbox.

⭐⭐ **And the map finding is the one to carry into `06-COLLECTIONS`:** `containsKey` guards against a *missing key*, not against a *null value*; `getOrDefault` defaults on a *missing key*, not on a *null value*. A `HashMap` that permits null values therefore has **two** distinct null cases and only one of them is guarded by either idiom. The robust fix is to forbid null values in the map at all — which is exactly why `ConcurrentHashMap`, `Map.of` and Guava's `ImmutableMap` reject them.

🔑 **The interview line:** *"A conditional expression's type is fixed at compile time from the static types of both branches, but only the selected branch is evaluated at runtime. So an unselected nullable branch cannot throw — that's a common misconception. The real hazard is that if the result type is a primitive, the SELECTED branch gets unboxed, so a null there throws; and adding a primitive branch to an expression can change the whole expression's type and introduce unboxing that wasn't there before. Related trap I'd volunteer: `getOrDefault` defaults on an absent KEY, not on a null VALUE, so a present-but-null mapping still NPEs on unboxing."*

---

## 5.8 `instanceof` and pattern matching — [MUST KNOW]

```java
// the three forms, oldest to newest
Object o = "hello";

// 1. the classic (Java 1.0) — check, then cast separately
if (o instanceof String) {
    String s = (String) o;                    // ⛔ the cast is redundant work
    System.out.println(s.length());           //   and a chance to get it wrong
}

// 2. ⭐ PATTERN MATCHING for instanceof — since Java 16, FINAL
if (o instanceof String s) {                  // ✅ check + bind in one step
    System.out.println(s.length());           //   `s` is in scope here
}
// ⭐ `s` is also in scope in the `else` of a NEGATED test — the compiler
//   does the flow analysis for you:
if (!(o instanceof String s)) {
    return;
}
System.out.println(s.length());               // ✅ s is definitely assigned

// 3. ⭐ PATTERN MATCHING for switch — since Java 21, FINAL
String describe(Object x) {
    return switch (x) {
        case Integer i      -> "int " + i;
        case Long l         -> "long " + l;
        case String s       -> "String of length " + s.length();
        case int[] arr      -> "int array of " + arr.length;
        case null           -> "null";          // ⭐ since Java 21 you can
        default             -> "something else";//   match null explicitly.
    };                                          //   Without a `case null`,
}                                               //   switch(null) THROWS NPE,
                                                //   unlike instanceof.
```

⭐ **The `switch(null)` asymmetry is worth remembering:** `null instanceof X` is `false` (never throws), but `switch(null)` throws `NullPointerException` **unless** you write `case null`. That is a behaviour change between the two constructs that catches people migrating from `if`-chains.

## 5.9 Precedence and associativity — [SHOULD KNOW]

| Precedence (highest → lowest) | Operators | Assoc. |
|---|---|---|
| 1 | `()` `[]` `.` `->` · method call · array index | left |
| 2 | `++` `--` (postfix) | left |
| 3 | `++ -- + - ! ~ (type)` (prefix / unary / cast) | **right** |
| 4 | `* / %` | left |
| 5 | `+ -` | left |
| 6 | `<< >> >>>` | left |
| 7 | `< <= > >= instanceof` | left |
| 8 | `== !=` | left |
| 9 | `&` | left |
| 10 | `^` | left |
| 11 | `\|` | left |
| 12 | `&&` | left |
| 13 | `\|\|` | left |
| 14 | `? :` (ternary) | **right** |
| 15 | `= += -= *= /= %= &= \|= ^= <<= >>= >>>=` | **right** |

⭐ **The four rows worth memorising:** `* / %` before `+ -`; `&&` before `||`; the ternary near the bottom; assignment at the very bottom and right-associative.

⭐⭐ **The two surprises:**
1. **Bitwise binds TIGHTER than relational-comparison's neighbours but LOOSER than equality.** So `a & b == c` parses as `a & (b == c)` — a compile error or nonsense. ⛔ Always parenthesise bitwise expressions.
2. **Assignment is right-associative**, so `a = b = c = 0` works right-to-left. And the ternary is right-associative, so nested ternaries group to the right — which is exactly why ⛔ **nested ternaries are unreadable** and should be an `if`/`switch`.

🔑 **The interview line, and the correct engineering answer:** *"I know the table well enough to read other people's code, and I use parentheses everywhere else. Precedence knowledge is for reading; parentheses are for writing. The one place I insist on parentheses regardless is bitwise expressions, because & binds looser than == and `a & b == c` is never what the author meant."*

---

<a name="part-6"></a><a name="part-6--type-casting"></a>
# PART 6 · Type casting

## 6.1 Widening vs narrowing — [MUST KNOW]

```
        byte ──┐
        short ─┼──▶  int  ──▶  long  ──▶  float  ──▶  double
        char ──┘             ⭐ WIDENING: automatic, no cast, no data loss
                             ⚠️ except long → float (see below)

        double ──▶ float ──▶ long ──▶ int ──▶ short/char ──▶ byte
                             ⭐ NARROWING: REQUIRES an explicit cast,
                                and SILENTLY LOSES DATA
```

⭐ **The one widening conversion that loses precision:** `long → float`. A `long` has 64 bits of integer precision; a `float` has only ~24 bits of mantissa. So `float f = 1234567890123456789L;` compiles without a cast and **silently rounds**. Java allows it because the *range* is wider even though the *precision* is not.

```java
long big = 1234567890123456789L;
float f = big;                     // ✅ compiles, no cast
System.out.println((long) f);      // ⛔ 1234567922431819776 — precision lost
System.out.println(big == (long) f); // false
```

## 6.2 `(int)` truncates; `Math.round` rounds — [MUST KNOW]

```java
public class TruncateVsRound {
    public static void main(String[] args) {
        double[] vals = {2.1, 2.5, 2.9, -2.1, -2.5, -2.9};
        System.out.printf("%-7s %-8s %-10s %-9s %-9s %-9s%n",
            "value", "(int)", "round", "floor", "ceil", "rint");
        for (double v : vals) {
            System.out.printf("%-7.1f %-8d %-10d %-9.1f %-9.1f %-9.1f%n",
                v,
                (int) v,                       // ⭐ TRUNCATES toward zero
                Math.round(v),                 // ⭐ rounds HALF UP
                                               //   (returns long for double!)
                Math.floor(v),                 // toward −∞
                Math.ceil(v),                  // toward +∞
                Math.rint(v));                 // ⭐ rounds HALF TO EVEN
            // ⚠️ NO `(long)` CASTS ON THE LAST THREE. `%f` requires a floating
            //   point argument: passing a `long` throws
            //   IllegalFormatConversionException AT RUNTIME — the exact trap
            //   from §14.3. Format strings are not type-checked at compile time.
        }
        // ⭐ Math.round(double) returns a LONG, not an int. Assigning it to an
        //   int is a COMPILE ERROR — a rare case where Java protects you.
        // ⭐ Math.round(-2.5) == -2, because round is defined as
        //   floor(x + 0.5). Bankers' rounding (half-to-even) is Math.rint.

        int i = 300;
        byte b = (byte) i;
        System.out.println("(byte)300 = " + b);   // ⛔ 44 — kept the low 8 bits
        // 300 = 0b1_0010_1100 → low 8 bits = 0b0010_1100 = 44

        // ✅ THE SAFE CONVERSIONS
        System.out.println(Math.toIntExact(300L));       // ✅ 300
        try {
            System.out.println(Math.toIntExact(3_000_000_000L));
        } catch (ArithmeticException e) {
            System.out.println("⭐ toIntExact threw: " + e.getMessage());
        }
        // ⭐ toIntExact / toShortExact / toByteExact THROW on loss instead of
        //   silently truncating. Use them at every boundary you don't control.
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// value   (int)    round      floor     ceil      rint
// 2.1     2        2          2.0       3.0       2.0
// 2.5     2        3          2.0       3.0       2.0     ⭐ rint → EVEN
// 2.9     2        3          2.0       3.0       3.0
// -2.1    -2       -2         -3.0      -2.0      -2.0
// -2.5    -2       -2         -3.0      -2.0      -2.0    ⭐ rint → EVEN
// -2.9    -2       -3         -3.0      -2.0      -3.0
// (byte)300 = 44
// 300
// ⭐ toIntExact threw: integer overflow
// ──────────────────────────────────────────────────────────────────────
```

## 6.3 ⭐ The `char` / `int` arithmetic surprise — [MUST KNOW]

```java
char c = 'a';
System.out.println(c);              // a
System.out.println(c + 1);          // ⛔ 98 — an INT, not 'b'
System.out.println((char)(c + 1));  // ✅ b
System.out.println('a' + 'b');      // ⛔ 195 — two ints added
System.out.println("" + 'a' + 'b');// ✅ "ab" — String first, so concatenation
System.out.println('a' + 'b' + ""); // ⛔ "195" — arithmetic happens FIRST

// ⭐ WHY: byte, short and char are all PROMOTED to int before any arithmetic.
//   This is "binary numeric promotion" in the JLS. The result of any
//   arithmetic on byte/short/char is an int — which is exactly why
//   `byte b = 1; b = b + 1;` fails to compile (§5.6).

// THE CAESAR-CIPHER IDIOM, done correctly:
static char shift(char c, int by) {
    return (char) ('a' + (c - 'a' + by) % 26);   // ⭐ subtract 'a' to get an
}                                                //   offset, add it back

// ⭐ COMPARING chars: 'a' < 'b' is TRUE — chars are numbers, so relational
//   operators work and compare code units. Useful, and occasionally wrong
//   for non-ASCII (code-unit order is not always collation order — use
//   java.text.Collator for that).
```

## 6.4 String ↔ number — [MUST KNOW]

| Direction | Correct | Notes |
|---|---|---|
| String → int | `Integer.parseInt("42")` | ⭐ returns a **primitive**; throws `NumberFormatException` |
| String → Integer | `Integer.valueOf("42")` | returns the wrapper, via the cache |
| any → String | `String.valueOf(x)` | ⭐ **null-safe**: returns `"null"`, never throws |
| any → String | `x.toString()` | ⛔ NPE if `x` is null |
| any → String | `"" + x` | works, null-safe, and slightly slower to read |
| String → boolean | `Boolean.parseBoolean(s)` | ⛔ never throws; anything ≠ "true" is false (§4.1) |

```java
// ⭐ parseInt is more capable than most people use it:
System.out.println(Integer.parseInt("ff", 16));      // 255 — parse in base 16
System.out.println(Integer.parseInt("1010", 2));     // 10  — base 2
System.out.println(Integer.parseInt("+42"));         // 42  — leading + is OK
System.out.println(Integer.parseInt(" 42"));         // ⛔ NumberFormatException
// ⭐ WHITESPACE IS NOT TRIMMED. Config values from a file or an env var are
//   the #1 source of this. Always .trim() first, or use .strip() (Java 11+).
System.out.println(Integer.parseInt(" 42 ".trim())); // ✅ 42
```

---

<a name="part-7"></a><a name="part-7--control-flow"></a>
# PART 7 · Control flow

## 7.1 `if` / `else` — [MUST KNOW]

```java
// ⛔ THE BRACE RULE. Not a style preference — a bug class.
if (debug)
    log("a");
    log("b");          // ⛔ ALWAYS runs. Indentation lies; the compiler
                       //   does not care about whitespace.
// ⭐ This exact bug (a missing-brace goto fail) was Apple's TLS
//   vulnerability CVE-2014-1266. It is not theoretical.
// ✅ ALWAYS use braces, even for a one-liner. Enforce it with Checkstyle.
```

## 7.2 ⭐ The old `switch` statement — and fall-through — [MUST KNOW]

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.06 — switch fall-through: the silent bug
// ══════════════════════════════════════════════════════════════════════
// WHAT   : a switch with a missing `break`.
// WHY    : fall-through is the DEFAULT in a switch statement. Forgetting one
//          `break` produces wrong behaviour with NO error, NO warning
//          (unless you enable -Xlint:fallthrough), and no test failure if
//          that branch is untested.
// OUTPUT : shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class FallThrough {
    static String buggy(int day) {
        String type;
        switch (day) {
            case 1: type = "Mon";        // ⛔ MISSING break
            case 2: type = "Tue"; break;
            case 3: type = "Wed"; break;
            default: type = "?";
        }
        return type;
    }
    static String fixed(int day) {
        return switch (day) {            // ✅ the expression form cannot
            case 1 -> "Mon";             //   fall through. Arrow labels have
            case 2 -> "Tue";             //   no fall-through semantics at all.
            case 3 -> "Wed";
            default -> "?";
        };
    }
    public static void main(String[] args) {
        for (int d = 1; d <= 4; d++) {
            System.out.printf("day %d: buggy=%-4s fixed=%s%n", d, buggy(d), fixed(d));
        }
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// day 1: buggy=Tue  fixed=Mon      ⛔ day 1 executed BOTH cases
// day 2: buggy=Tue  fixed=Tue
// day 3: buggy=Wed  fixed=Wed
// day 4: buggy=?    fixed=?
// ──────────────────────────────────────────────────────────────────────
// ⭐ TWO MORE OLD-SWITCH RULES:
//   • `default` with no `break` at the END is fine — there's nothing to
//     fall into. That's why the bug is easy to miss.
//   • a `switch` on a String works by hashing: javac emits a switch on
//     `s.hashCode()` and then `equals()` checks in each branch. So it is
//     O(1)-ish, not a chain of comparisons — but a null String THROWS NPE.
// ✅ THE FIX: javac -Xlint:fallthrough warns. Better: never write the
//   statement form again. Use the expression form.
```

## 7.3 ⭐ The `switch` expression (Java 14+) — [MUST KNOW]

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.07 — every form of switch, including sealed exhaustiveness
// ══════════════════════════════════════════════════════════════════════
// WHAT   : the four switch shapes you need to be able to read and write.
// WHY    : the expression form removes fall-through, produces a value, and —
//          with sealed types — lets the COMPILER prove you handled every case.
// OUTPUT : shown below.
// JAVA   : 21+ (pattern matching for switch was finalised in 21)
// ══════════════════════════════════════════════════════════════════════
public class SwitchForms {

    enum Status { NEW, PAID, SHIPPED, CANCELLED }

    // ── FORM 1: arrow labels, expression form ────────────────────────────
    static int rank(Status s) {
        return switch (s) {
            case NEW       -> 1;
            case PAID      -> 2;
            case SHIPPED   -> 3;
            case CANCELLED -> 0;
            // ⭐⭐ NO `default`. This is deliberate: the compiler knows every
            //   Status constant is covered. Add a fifth constant to the enum
            //   and EVERY switch like this one becomes a COMPILE ERROR.
            // ⛔ Adding `default` throws that guarantee away — a new enum
            //   constant would silently take the default branch.
        };
    }

    // ── FORM 2: multiple labels per arm; `yield` for a block ─────────────
    static String describe(Status s) {
        return switch (s) {
            case NEW             -> "awaiting payment";
            case PAID, SHIPPED   -> {              // ⭐ two labels, one arm
                String base = (s == Status.PAID) ? "paid" : "in transit";
                yield base + " — do not cancel";   // ⭐ `yield` returns a value
            }                                      //   from a BLOCK arm.
            case CANCELLED       -> "cancelled";   //   (`return` would exit
        };                                         //    the whole method)
    }

    // ── FORM 3: ⭐⭐⭐ SEALED + RECORD + PATTERN MATCHING = an ADT ────────
    sealed interface Payment permits Card, Upi, Cash, BankTransfer {}
    record Card(String number, String expiry, int cvv) implements Payment {}
    record Upi(String vpa) implements Payment {}
    record Cash() implements Payment {}
    record BankTransfer(String ifsc, String account) implements Payment {}

    // ⭐ DECONSTRUCTION PATTERNS: bind the components directly in the case.
    static String redact(Payment p) {
        return switch (p) {
            case Card(var num, var exp, var cvv) ->
                "Card[" + num.substring(0, Math.min(4, num.length())) + "****"
                        + " exp=" + exp + "]";       // ⭐ cvv deliberately unused
            case Upi(var vpa)          -> "Upi[" + vpa.replaceAll("(?<=.).(?=.*@)", "*") + "]";
            case Cash()                -> "Cash[]";
            case BankTransfer(var ifsc, var acct) -> "Bank[" + ifsc + " ****" +
                                                     acct.substring(Math.max(0, acct.length() - 4)) + "]";
            // ⭐⭐ NO default, and none is possible to need: `Payment` is
            //   SEALED with exactly four permitted implementations. Add a
            //   fifth (say `Wallet`) and this method FAILS TO COMPILE until
            //   you handle it. That is exhaustiveness as a compiler guarantee
            //   — the single best argument for sealed hierarchies.
        };
    }

    // ── FORM 4: guarded patterns (`when`) ────────────────────────────────
    static String classify(Payment p) {
        return switch (p) {
            case Card c when c.cvv() == 0        -> "card, cvv not set";   // since 21
            case Card c                          -> "card";
            case Upi u when u.vpa().endsWith("@okhdfcbank") -> "upi (HDFC)";
            case Upi u                           -> "upi";
            case Cash c                          -> "cash";
            case BankTransfer b                  -> "bank transfer";
        };
    }

    public static void main(String[] args) {
        for (Status s : Status.values()) {
            System.out.printf("%-10s rank=%d  %s%n", s, rank(s), describe(s));
        }
        System.out.println();
        Payment[] ps = {
            new Card("4111111111111111", "12/28", 123),
            new Upi("harish@example@okbank"),
            new Cash(),
            new BankTransfer("HDFC0001234", "50100123456789")
        };
        for (Payment p : ps) {
            System.out.printf("  %-42s %s%n", redact(p), classify(p));
        }
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// NEW        rank=1  awaiting payment
// PAID       rank=2  paid — do not cancel
// SHIPPED    rank=3  in transit — do not cancel
// CANCELLED  rank=0  cancelled
//
//   Card[4111**** exp=12/28]                   card
//   Upi[h*************@okbank]                 upi
//   Cash[]                                     cash
//   Bank[HDFC0001234 ****6789]                 bank transfer
// ──────────────────────────────────────────────────────────────────────
// ⭐ READ THE FIRST COLUMN: `Card[4111**** exp=12/28]` — the deconstruction
//   pattern bound `num`, `exp` and `cvv`, and `cvv` was deliberately NEVER
//   used, so it cannot leak into a log line. That is redaction by
//   construction rather than by discipline.
// ⭐ AND THE SECOND COLUMN: `classify` returned plain "card", not
//   "card, cvv not set", because the guard `c.cvv() == 0` was false. Guarded
//   patterns are tried IN ORDER, so the more specific arm must come first.
// ⚠️ `switch(null)` THROWS NullPointerException unless you add `case null`.
//   `null instanceof X` is false and never throws. The two constructs differ.
// 🔑 THE INTERVIEW LINE: "I use the arrow form and deliberately omit
//    default when the subject is an enum or a sealed type. Omitting default
//    converts 'someone added a case' from a silent behaviour change into a
//    compile error, which is the entire value of sealed hierarchies: the
//    compiler can prove exhaustiveness. Adding a default to an exhaustive
//    switch is a small anti-pattern that costs you that guarantee."
```

## 7.4 The three loops — [MUST KNOW]

```java
// for — when you need the index
for (int i = 0; i < n; i++) { }
// ⚠️ `int i` is scoped to the loop. Two sibling loops may both declare `i`.
// ⚠️ modifying the collection inside a for-index loop while using the
//    ORIGINAL size is a classic IndexOutOfBounds.

// while — when the condition is not a counter
while (queue.hasNext()) { }

// do-while — when the body must run AT LEAST ONCE
do {
    line = reader.readLine();
    process(line);
} while (line != null);
// ⭐ the only construct where a trailing semicolon after the brace is legal
//   and required. `do { } while (c);` ← that semicolon is not optional.

// ⭐ THE INFINITE-LOOP IDIOMS — all equivalent, all legal:
for (;;) { }                 // ⭐ the idiomatic one; no condition to evaluate
while (true) { }             // the readable one
do { } while (true);         // rare
// ⛔ `while (1)` is a COMPILE ERROR — Java's condition must be `boolean`.
//   There is no truthiness in Java. (This surprises C/Python/JS developers.)
```

## 7.5 ⭐ The enhanced `for` — what it actually compiles to — [SDE3 DIFFERENTIATOR]

⭐⭐ **The enhanced `for` is two different loops depending on the type.** Knowing which one you got explains several otherwise-mysterious behaviours.

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.08 — the enhanced for, desugared
// ══════════════════════════════════════════════════════════════════════
// WHAT   : the two forms the compiler generates, written out by hand.
// WHY    : it explains (a) why arrays are faster to iterate than Lists,
//          (b) why ConcurrentModificationException happens, and (c) why you
//          cannot remove an element in an enhanced for.
// OUTPUT : identical for both.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class EnhancedForDesugared {

    public static void main(String[] args) {
        int[] arr = {10, 20, 30};
        java.util.List<Integer> list = java.util.List.of(10, 20, 30);

        System.out.println("── the enhanced for ──");
        for (int x : arr)  System.out.print(x + " ");
        System.out.println();
        for (int x : list) System.out.print(x + " ");
        System.out.println("\n");

        // ⭐ FORM A — for an ARRAY, it compiles to an INDEX loop:
        System.out.println("── desugared: array ──");
        for (int i = 0; i < arr.length; i++) {     // ⭐ arr.length is read
            int x = arr[i];                        //   EVERY iteration
            System.out.print(x + " ");             //   (so caching it in a
        }                                          //   local is a real,
        System.out.println();                      //   if tiny, optimisation)

        // ⭐ FORM B — for an ITERABLE, it compiles to an ITERATOR loop:
        System.out.println("── desugared: Iterable ──");
        for (java.util.Iterator<Integer> it = list.iterator(); it.hasNext(); ) {
            int x = it.next();                     // ⭐ unboxing happens here
            System.out.print(x + " ");             //   for a List<Integer>
        }
        System.out.println();

        // ⭐⭐ THE CONSEQUENCES OF FORM B:
        // 1. Iterator.next() checks modCount against expectedModCount. If the
        //    collection was structurally modified by any other means, it throws
        //    ConcurrentModificationException. THAT is the fail-fast mechanism.
        // ⭐⭐ THE EXCEPTION IS *BEST EFFORT* — and here is the proof, live.
        //   Whether it fires depends on WHERE in the list you remove.
        java.util.List<Integer> mid = new java.util.ArrayList<>(list);
        try {
            for (int x : mid) if (x == 20) mid.remove(Integer.valueOf(x));
            System.out.println("\n⛔ removing the MIDDLE of 3: NO exception, list=" + mid);
        } catch (java.util.ConcurrentModificationException e) {
            System.out.println("\nremoving the MIDDLE of 3: " + e.getClass().getSimpleName());
        }
        // WHY NO THROW: after removing 20 the list is [10,30], size 2, and the
        //   iterator's cursor is already 2 → hasNext() is false → the loop ends
        //   WITHOUT calling next() again → the modCount check never runs.

        java.util.List<Integer> first = new java.util.ArrayList<>(list);
        try {
            for (int x : first) if (x == 10) first.remove(Integer.valueOf(x));
            System.out.println("removing the FIRST of 3: no exception, list=" + first);
        } catch (java.util.ConcurrentModificationException e) {
            System.out.println("✅ removing the FIRST of 3: " + e.getClass().getSimpleName());
        }
        // WHY THIS THROWS: after removing 10 the list is [20,30], size 2, cursor
        //   is 1 → hasNext() is true → next() runs → modCount != expectedModCount
        //   → ConcurrentModificationException.

        // ✅ the three correct ways:
        java.util.List<Integer> mutable = new java.util.ArrayList<>(list);
        mutable.removeIf(x -> x == 20);                              // ⭐ best
        for (var it = mutable.iterator(); it.hasNext(); ) { if (it.next() == 30) it.remove(); }
        var filtered = mutable.stream().filter(x -> x != 30).toList();  // since 16
        // ⭐ `.toList()` (Java 16+) returns an UNMODIFIABLE list. The older
        //   `.collect(Collectors.toList())` returns a mutable ArrayList.
        //   Swapping one for the other is a common source of
        //   UnsupportedOperationException after a Java upgrade.

        // 2. ⭐ An Iterator ALLOCATES. For a hot loop over a large List, the
        //    index form avoids one object per iteration — usually irrelevant
        //    (escape analysis often removes it), occasionally measurable.
        //    Do not micro-optimise this without a profiler.
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ── the enhanced for ──
// 10 20 30
// 10 20 30
//
// ── desugared: array ──
// 10 20 30
// ── desugared: Iterable ──
// 10 20 30
//
// ⛔ removing the MIDDLE of 3: NO exception, list=[10, 30]
// ✅ removing the FIRST of 3: ConcurrentModificationException
// ──────────────────────────────────────────────────────────────────────
// ⭐⭐ VERIFIED, NOT THEORISED: the SAME illegal operation throws or doesn't
//   depending only on WHERE in the list you remove. Fail-fast is a BUG
//   DETECTOR, not a guarantee — the Javadoc says so explicitly.
// ⛔ THE CONSEQUENCE: the bug ships, passes on a 3-element test list, and
//   corrupts a 3000-element production one — or throws there and not locally,
//   which is worse, because you cannot reproduce it.
// 🔑 THE INTERVIEW LINE: "The enhanced for desugars to an index loop for
//    arrays and an Iterator loop for Iterables. That's why removing during
//    iteration throws ConcurrentModificationException — the iterator's
//    modCount check — and why the exception is only best-effort and can
//    silently not fire. The fix is removeIf, or Iterator.remove, or don't
//    mutate at all and filter into a new list."
```

## 7.6 `break` / `continue` with labels — [SHOULD KNOW]

```java
public class LabelledBreak {
    public static void main(String[] args) {
        // ⭐ a label is an identifier followed by a colon, on a statement.
        outer:
        for (int i = 1; i <= 4; i++) {
            for (int j = 1; j <= 4; j++) {
                if (i * j > 6) {
                    System.out.println("  breaking out of BOTH at i=" + i + " j=" + j);
                    break outer;                // ✅ exits the LABELLED loop
                }
                System.out.println("  i=" + i + " j=" + j + " product=" + (i * j));
            }
        }

        // continue with a label — skip to the next iteration of the OUTER loop
        int found = 0;
        search:
        for (String name : new String[]{"espresso", "grinder", "tamper", "scale"}) {
            for (char c : name.toCharArray()) {
                if (c == 'z') { continue search; }    // next NAME
            }
            found++;
        }
        System.out.println("names without 'z': " + found);

        // ✅ THE MODERN ALTERNATIVE, which you should prefer:
        //   extract the inner loop into a method and `return`.
        //   Labels are legal but they are a readability cost, and a method
        //   gives you a name for what you were doing.
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
//   i=1 j=1 product=1
//   i=1 j=2 product=2
//   i=1 j=3 product=3
//   i=1 j=4 product=4
//   i=2 j=1 product=2
//   i=2 j=2 product=4
//   i=2 j=3 product=6
//   breaking out of BOTH at i=2 j=4
// names without 'z': 4
// ──────────────────────────────────────────────────────────────────────
// ⛔ you cannot `break` to a label that is not an ENCLOSING statement.
//   Labels are not goto — control can only transfer OUTWARD, never inward
//   or sideways. That restriction is what keeps them safe.
```

---

<a name="part-8"></a><a name="part-8--arrays"></a>
# PART 8 · Arrays

## 8.1 ⭐ Arrays are objects; `length` is a field — [MUST KNOW]

```java
int[] a = new int[3];
System.out.println(a instanceof Object);     // ⭐ true — arrays ARE objects
System.out.println(a.getClass().getName());  // [I   ← the JVM's name for int[]
System.out.println(a.getClass().isArray());  // true
System.out.println(a.getClass().getSuperclass());  // class java.lang.Object
System.out.println(a.getClass().getComponentType()); // int

System.out.println(a.length);       // ⭐ 3 — a FIELD. No parentheses.
// System.out.println(a.length());  // ⛔ COMPILE ERROR: cannot find symbol
System.out.println("abc".length()); // ⭐ a METHOD on String. The asymmetry
                                    //   between these two lines has cost
                                    //   every Java learner 10 minutes.
```

⭐ **Every array type is a real class**, generated at runtime, whose name is `[` + a type code (`I`=int, `Ljava/lang/String;`=String). `int[]` and `String[]` are unrelated types — `String[]` is assignable to `Object[]`, but `int[]` is **not** assignable to `Object[]`.

| Declaration form | Legal? | Note |
|---|---|---|
| `int[] a;` | ✅ | ⭐ the preferred form — the type is visually `int[]` |
| `int a[];` | ✅ | the C-style form. Legal; discouraged |
| `int[] a, b;` | ✅ | both are `int[]` |
| `int a[], b;` | ⚠️ | `a` is `int[]`, **`b` is `int`**. ⛔ never write this |
| `int[] a = {1,2,3};` | ✅ | ⭐ only in a **declaration**. `a = {1,2,3};` alone is an error |
| `int[] a = new int[]{1,2,3};` | ✅ | needed when passing directly: `f(new int[]{1,2})` |
| `int[] a = new int[3]{1,2,3};` | ⛔ | **compile error** — size and initialiser conflict |

## 8.2 Default initialisation — [MUST KNOW]

⭐ `new` **always** zero-fills. There is no such thing as an uninitialised array element in Java — which is a genuine memory-safety guarantee C does not give you.

| Element type | Default |
|---|---|
| `byte short int long` | `0` / `0L` |
| `float double` | `0.0f` / `0.0d` |
| `char` | `'\u0000'` (NUL — invisible when printed) |
| `boolean` | `false` |
| any reference | ⭐ `null` |

```java
int[] nums = new int[3];
String[] words = new String[3];
System.out.println(java.util.Arrays.toString(nums));    // [0, 0, 0]
System.out.println(java.util.Arrays.toString(words));   // [null, null, null]
System.out.println(words[0].length());                  // ⛔ NullPointerException
// ⭐ THE PATTERN: `new String[n]` gives you n nulls, and the NPE happens at
//   the first dereference, not at the allocation. Always fill before use.
```

## 8.3 1D, 2D, jagged — [MUST KNOW]

```java
int[][] grid = new int[3][4];       // ⭐ NOT a 2D array. It is an ARRAY OF
                                    //   3 ARRAYS, each of length 4. Java has
                                    //   no true multidimensional arrays.
System.out.println(grid.length);        // 3   ← rows
System.out.println(grid[0].length);     // 4   ← columns of row 0

// ⭐ JAGGED: because each row is an independent array, rows may differ
int[][] jagged = new int[3][];      // three null row references
jagged[0] = new int[1];
jagged[1] = new int[3];
jagged[2] = new int[2];
for (int[] row : jagged) {
    System.out.println(row.length + ": " + java.util.Arrays.toString(row));
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// 1: [0]
// 3: [0, 0, 0]
// 2: [0, 0]
// ──────────────────────────────────────────────────────────────────────

// literal initialisation
int[][] m = {
    {1, 2, 3},
    {4, 5, 6}
};
// ⭐ iterating a 2D array: the OUTER variable is a 1D ARRAY, not a value
for (int[] row : m) {
    for (int cell : row) System.out.print(cell + " ");
    System.out.println();
}
```

## 8.4 ⭐ The five kinds of copy — [MUST KNOW]

⭐⭐ **This is the section that explains shallow vs deep for the rest of your career.**

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.09 — five ways to "copy" an array, and what each really does
// ══════════════════════════════════════════════════════════════════════
// WHAT   : assignment, clone, copyOf, copyOfRange, arraycopy — plus a real
//          deep copy.
// WHY    : four of the five are SHALLOW. Confusing them is the source of
//          aliasing bugs that look like data corruption.
// OUTPUT : shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class FiveCopies {
    static class Point { int x, y; Point(int x, int y){this.x=x;this.y=y;}
        public String toString(){ return "("+x+","+y+")"; } }

    public static void main(String[] args) {
        int[] a = {1, 2, 3};

        // ── ① ASSIGNMENT: NOT A COPY AT ALL ────────────────────────────
        int[] b = a;                       // ⛔ two names for ONE array
        b[0] = 99;
        System.out.println("① assignment   : a=" + java.util.Arrays.toString(a)
                         + "  same object? " + (a == b));

        // ── ② clone(): a new array, same elements ──────────────────────
        int[] c = a.clone();               // ✅ new array, SHALLOW copy
        c[1] = 88;
        System.out.println("② clone        : a=" + java.util.Arrays.toString(a)
                         + " c=" + java.util.Arrays.toString(c)
                         + "  same object? " + (a == c));

        // ── ③ Arrays.copyOf: copy + optionally RESIZE ──────────────────
        int[] d = java.util.Arrays.copyOf(a, 5);      // ✅ length 5, padded 0
        int[] e = java.util.Arrays.copyOf(a, 2);      // ✅ length 2, truncated
        System.out.println("③ copyOf(5)    : " + java.util.Arrays.toString(d));
        System.out.println("③ copyOf(2)    : " + java.util.Arrays.toString(e));
        // ⭐ THIS is what ArrayList uses internally to grow.

        // ── ④ Arrays.copyOfRange: a SLICE ──────────────────────────────
        int[] f = java.util.Arrays.copyOfRange(a, 1, 3);   // [from, to)
        System.out.println("④ copyOfRange  : " + java.util.Arrays.toString(f));
        // ⭐ `to` is EXCLUSIVE. `to` may exceed a.length — the extra is zero.

        // ── ⑤ System.arraycopy: the fastest, into an EXISTING array ────
        int[] g = new int[5];
        System.arraycopy(a, 0, g, 2, 3);   // src, srcPos, dest, destPos, len
        System.out.println("⑤ arraycopy    : " + java.util.Arrays.toString(g));
        // ⭐ the lowest-level, fastest option — and the one JVMs can turn
        //   into a memmove intrinsic. It can copy overlapping regions
        //   correctly, unlike a naive loop.

        // ── ⭐⭐ AND THE ONE EVERYBODY MEANS: a DEEP copy ────────────────
        Point[] pts = { new Point(1,1), new Point(2,2) };
        Point[] shallow = pts.clone();                 // ⛔ SHALLOW: new array,
                                                       //   SAME Point objects
        Point[] deep = new Point[pts.length];          // ✅ DEEP: new Points too
        for (int i = 0; i < pts.length; i++) {
            deep[i] = new Point(pts[i].x, pts[i].y);
        }
        shallow[0].x = 999;
        System.out.println("deep?  pts[0]=" + pts[0] + "  shallow[0]=" + shallow[0]);
        System.out.println("deep?  pts[0]=" + pts[0] + "  deep[0]="    + deep[0]);
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ① assignment   : a=[99, 2, 3]  same object? true       ⛔ a changed!
// ② clone        : a=[99, 2, 3] c=[99, 88, 3]  same object? false
// ③ copyOf(5)    : [99, 2, 3, 0, 0]
// ③ copyOf(2)    : [99, 2]
// ④ copyOfRange  : [2, 3]
// ⑤ arraycopy    : [0, 0, 99, 2, 3]
// deep?  pts[0]=(999,1)  shallow[0]=(999,1)   ⛔ aliasing — both changed
// deep?  pts[0]=(999,1)  deep[0]=(1,1)        ✅ independent
// ──────────────────────────────────────────────────────────────────────
// ⭐ THE SUMMARY TABLE TO MEMORISE:
//   b = a              → NOT a copy. One array, two names.
//   a.clone()          → new array, SHALLOW elements.
//   Arrays.copyOf      → new array (resizable), SHALLOW elements.
//   Arrays.copyOfRange → new array (a slice),  SHALLOW elements.
//   System.arraycopy   → copies INTO an existing array, SHALLOW elements.
//   NONE of them is deep. For a deep copy you must copy the ELEMENTS too.
// 🔑 THE INTERVIEW LINE: "Every built-in array copy in Java is shallow —
//    you get a new array containing the same object references. That's fine
//    for primitives and for immutable elements like String, but for mutable
//    elements you must copy each one, which is why a copy constructor or a
//    static factory is the recommended approach over clone()."
```

## 8.5 Sorting and searching — [SHOULD KNOW]

| Method | Algorithm | Complexity | Stable? | Notes |
|---|---|---|---|---|
| `Arrays.sort(int[])` | dual-pivot quicksort | O(n log n) avg | ⛔ n/a (primitives) | ⭐ worst case O(n²), mitigated by the dual pivot |
| `Arrays.sort(Object[])` | ⭐ **TimSort** | O(n log n), **O(n) on nearly-sorted** | ✅ **stable** | merges runs; needs n/2 temp space |
| `Arrays.parallelSort(...)` | parallel merge sort | O(n log n / p) | ✅ | ⭐ only worth it above ~10⁵ elements |
| `Arrays.binarySearch(a, k)` | binary search | O(log n) | — | ⛔ **requires a sorted array**, else the result is undefined |
| `List.sort(cmp)` / `Collections.sort` | TimSort | same | ✅ | `List.of(...)` is immutable → throws |

```java
int[] a = {5, 2, 9, 1};
java.util.Arrays.sort(a);
System.out.println(java.util.Arrays.toString(a));          // [1, 2, 5, 9]
int idx = java.util.Arrays.binarySearch(a, 5);
System.out.println("index of 5 = " + idx);                 // 2
int missing = java.util.Arrays.binarySearch(a, 7);
System.out.println("index of 7 = " + missing);             // ⭐ -4
// ⭐⭐ THE NEGATIVE RESULT IS INFORMATION, not just "not found":
//   insertionPoint = -(result) - 1  →  -(-4)-1 = 3
//   i.e. 7 would be inserted at index 3 to keep the array sorted.

// sorting objects — the three ways
record Product(String sku, long priceCents) {}
Product[] ps = { new Product("b", 200), new Product("a", 300), new Product("c", 100) };
java.util.Arrays.sort(ps, java.util.Comparator.comparing(Product::sku));
java.util.Arrays.sort(ps, java.util.Comparator.comparingLong(Product::priceCents).reversed());
java.util.Arrays.sort(ps, java.util.Comparator.comparing(Product::sku)
        .thenComparingLong(Product::priceCents));
// ⭐ `comparingLong` avoids boxing the price into a Long. In a hot sort of a
//   million rows, that is a measurable difference — and a nice detail to mention.
```

## 8.6 ⭐ Varargs IS an array — [SDE3 DIFFERENTIATOR]

```java
static void log(String fmt, Object... args) {      // ⭐ args is Object[]
    System.out.println("  args.getClass() = " + args.getClass().getSimpleName());
    System.out.println("  args.length     = " + args.length);
}
log("x");                          // args is a real Object[0], NOT null
log("x", 1, "two", 3.0);           // args is Object[4]
log("x", (Object[]) null);         // ⛔ args IS null here — the one way

// ⭐⭐ THE CONSEQUENCES, and they are the interview content:
// 1. Every varargs call ALLOCATES an array. In a hot path that is real
//    garbage. String.format is the classic example of why it's slow.
// 2. ⛔ GENERIC VARARGS ARE UNSAFE — heap pollution:
@SafeVarargs                       // ⭐ a PROMISE by the author, not a check.
static <T> java.util.List<T> asList(T... items) {   //   It suppresses the
    return java.util.Arrays.asList(items);          //   warning. It does NOT
}                                                   //   make the code safe.
// ⭐ WHY IT'S UNSAFE: `T...` becomes `Object[]` at runtime (erasure), so you
//   can put the wrong type into a List<Integer> through the array. The
//   exception surfaces LATER, far from the cause.
// ✅ Since Java 9 you can declare a varargs method on a LAMBDA-compatible
//   position, and the rule is: make the method `static`, `final`, or a
//   private/constructor — then `@SafeVarargs` is legal and honest.
// 3. varargs must be the LAST parameter, and there can be only ONE.
```

## 8.7 The exceptions — [MUST KNOW]

| Exception | Thrown when | Type |
|---|---|---|
| `ArrayIndexOutOfBoundsException` | index `< 0` or `>= length` | unchecked (`RuntimeException`) |
| `NegativeArraySizeException` | ⭐ `new int[-1]` — a **negative size** | unchecked |
| `ArrayStoreException` | ⭐ storing the wrong type into an array of a supertype | unchecked |
| `NullPointerException` | dereferencing a null array reference | unchecked |

```java
// ⭐ ArrayStoreException — arrays are COVARIANT, and that is a hole:
Object[] objs = new String[3];     // ✅ legal! String[] IS-A Object[]
objs[0] = "fine";                  // ✅
objs[1] = Integer.valueOf(42);     // ⛔ ArrayStoreException at RUNTIME
// ⭐⭐ WHY THIS MATTERS: array covariance means the compiler CANNOT catch
//   this. It is a runtime check on every store — a small performance cost
//   and a real type-safety hole. THIS IS THE ARGUMENT FOR GENERICS, which
//   are INVARIANT: List<Object> is NOT a supertype of List<String>, so the
//   equivalent mistake is a COMPILE error.
// 🔑 THE INTERVIEW LINE: "Java arrays are covariant and reified, which
//    means a String[] can be assigned to an Object[] and the type error
//    only appears at runtime as an ArrayStoreException, with a check on
//    every store. Generics are invariant and erased, which moves that error
//    to compile time at the cost of losing the runtime type. That trade —
//    runtime safety versus compile-time safety — is the whole reason
//    collections replaced arrays in idiomatic Java."
```

## 8.8 `Arrays.asList` vs `List.of` vs `List.copyOf` — [SHOULD KNOW]

```java
Integer[] arr = {1, 2, 3};

java.util.List<Integer> a = java.util.Arrays.asList(arr);   // ⭐ FIXED SIZE,
                                                            //   backed BY the array
a.set(0, 99);                            // ✅ allowed
System.out.println(arr[0]);              // ⭐ 99 — the ARRAY CHANGED TOO
// a.add(4);                             // ⛔ UnsupportedOperationException
// a.remove(0);                          // ⛔ UnsupportedOperationException

java.util.List<Integer> b = java.util.List.of(1, 2, 3);     // ⭐ TRULY immutable
// b.set(0, 99);                         // ⛔ UnsupportedOperationException
// b.contains(null);                     // ⛔ throws NPE — List.of rejects null
                                         //   even in QUERIES, which surprises people
java.util.List<Integer> c = java.util.List.copyOf(a);       // ⭐ immutable COPY
                                                            //   (null-hostile too)

// ⭐ THE PRIMITIVE TRAP:
int[] ints = {1, 2, 3};
var wrong = java.util.Arrays.asList(ints);
System.out.println(wrong.size());        // ⛔ 1  — a List<int[]>!
// WHY: Arrays.asList is generic over T; int is not a T, so T binds to int[]
//   and you get a one-element list containing an array. The fix:
var right = java.util.Arrays.stream(ints).boxed().toList();
System.out.println(right);               // ✅ [1, 2, 3]
```

| | `Arrays.asList` | `List.of` (Java 9+) | `List.copyOf` (Java 10+) |
|---|---|---|---|
| Size fixed? | ✅ yes | ✅ yes | ✅ yes |
| Elements replaceable (`set`)? | ⭐ **yes** | ⛔ no | ⛔ no |
| Backed by the source array? | ⭐ **yes — aliasing!** | no | no (copies) |
| Allows null elements? | ✅ yes | ⛔ throws NPE | ⛔ throws NPE |
| `contains(null)` on a null-free list | returns false | ⛔ **throws NPE** | ⛔ **throws NPE** |
| Use when | you need a mutable-element view | ⭐ the default for constants | you need a defensive immutable copy |

---

<a name="part-9"></a><a name="part-9--methods"></a>
# PART 9 · Methods

## 9.1 Anatomy, and what the signature actually is — [MUST KNOW]

```java
public static int max(int a, int b) throws IllegalArgumentException {
│      │      │   │   └────┬────┘ │
│      │      │   │        │      └─ throws clause — NOT part of the signature
│      │      │   └────────────────  parameter types — PART of the signature
│      │      └────────────────────  return type — ⭐ NOT part of the signature
│      └───────────────────────────  static
└──────────────────────────────────  access modifier
              max                    ← the name — PART of the signature
```

⭐⭐ **The signature is the method NAME plus the PARAMETER TYPES.** Nothing else. Two consequences that get asked:

1. **You cannot overload on return type alone.** `int f()` and `long f()` in the same class is a compile error — *"both methods have same erasure"*.
2. **The `throws` clause is not part of it either.** So you cannot overload on checked exceptions.

```java
// ⛔ COMPILE ERROR — differing only in return type
int  compute(String s) { return s.length(); }
long compute(String s) { return s.length(); }   // "already defined"
```

## 9.2 `void` and returning early — [MUST KNOW]

```java
// ⭐ GUARD CLAUSES — the shape that keeps methods flat and readable.
static String discount(String tier, long totalCents) {
    if (tier == null)          return "NONE";      // ✅ return early
    if (totalCents <= 0)       return "NONE";      // ✅ one condition, one exit
    if (!tier.equals("GOLD"))  return "NONE";
    return totalCents > 100_00 ? "10_PERCENT" : "5_PERCENT";
}
// ⛔ versus the nested version, which is what beginners write:
//   if (tier != null) { if (totalCents > 0) { if (tier.equals("GOLD")) {
//     ...three more levels... } } }
// ⭐ the guard-clause version has the same behaviour, half the indentation,
//   and each `return` is adjacent to the reason for it.
```

## 9.3 ⭐⭐ Overloading resolution — the three phases — [MUST KNOW]

**This is the most-asked "what does this print?" mechanism in Java.** The compiler tries three phases **in order** and stops at the first phase in which *any* applicable method exists.

```
PHASE 1 ── strict invocation
            • no boxing, no unboxing, no varargs
            • exact match, or widening primitive conversion
                    │ none applicable?
                    ▼
PHASE 2 ── loose invocation
            • boxing and unboxing ARE allowed
            • varargs still NOT allowed
                    │ none applicable?
                    ▼
PHASE 3 ── variable arity
            • varargs methods are now eligible
                    │
                    ▼
        Among the applicable methods, pick the MOST SPECIFIC.
        If two are equally specific → ⛔ "reference to f is ambiguous"
```

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.10 — overloading resolution, phase by phase
// ══════════════════════════════════════════════════════════════════════
// WHAT   : six overloads and five calls; predict every answer first.
// WHY    : this mechanism decides which method runs, entirely at COMPILE
//          time, on STATIC types. Misjudging it is a classic interview fail.
// OUTPUT : shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class OverloadResolution {

    // ⭐ family 1 — fixed arity only. Note there is deliberately NO varargs
    //   overload here; adding one changes the answer to `f(null)`. See the
    //   ⭐⭐ callout under the OUTPUT — that is the most interesting thing in
    //   this whole program, and it is NOT what most textbooks say.
    static void f(int x)     { System.out.println("  f(int)"); }
    static void f(long x)    { System.out.println("  f(long)"); }
    static void f(Integer x) { System.out.println("  f(Integer)"); }
    static void f(Number x)  { System.out.println("  f(Number)"); }
    static void f(Object x)  { System.out.println("  f(Object)"); }

    // ⭐ family 2 — the varargs demo, kept separate on purpose
    static void v(int x)     { System.out.println("  v(int)      — phase 1"); }
    static void v(int... x)  { System.out.println("  v(int...)   — phase 3"); }

    // ⭐ family 3 — two siblings, for the ambiguity demo
    static void g(String s)         { System.out.println("  g(String)"); }
    static void g(StringBuilder sb) { System.out.println("  g(StringBuilder)"); }

    public static void main(String[] args) {
        System.out.println("f(1):");
        f(1);                       // predict: f(int)     — phase 1, exact

        System.out.println("f(1L):");
        f(1L);                      // predict: f(long)    — phase 1, exact

        System.out.println("f((short)1):");
        f((short) 1);               // predict: f(int)     — phase 1, WIDENING
                                    //   short→int beats boxing short→Short

        System.out.println("f(Integer.valueOf(1)):");
        f(Integer.valueOf(1));      // predict: f(Integer) — phase 1, exact

        System.out.println("f('a'):");
        f('a');                     // predict: f(int)     — phase 1, char→int

        System.out.println("f(null):");
        f(null);                    // predict: f(Integer) — most specific

        System.out.println("v(1):");
        v(1);                       // predict: v(int)     — ⭐ phase 1 beats
                                    //   phase 3. Varargs LOSES if anything else
                                    //   is applicable.
        System.out.println("v(1, 2):");
        v(1, 2);                    // predict: v(int...)  — phase 3, only option

        System.out.println("g(null):");
        // g(null);                 // ⛔ AMBIGUOUS — COMPILE ERROR:
                                    //   "reference to g is ambiguous:
                                    //    both method g(String) and method
                                    //    g(StringBuilder) match"
                                    //   String and StringBuilder are unrelated;
                                    //   neither is more specific.
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// f(1):
//   f(int)
// f(1L):
//   f(long)
// f((short)1):
//   f(int)
// f(Integer.valueOf(1)):
//   f(Integer)
// f('a'):
//   f(int)
// f(null):
//   f(Integer)
// v(1):
//   v(int)      — phase 1
// v(1, 2):
//   v(int...)   — phase 3
// g(null):
// ──────────────────────────────────────────────────────────────────────
// ⭐ that last bare `g(null):` is the header printing; the call itself is
//   commented out because it would not compile. Removing dead output is the
//   fix in real code — leaving it is how you get a log line with no result.
// ⭐ WHY `f(null)` PICKS f(Integer):
//   Phase 1 fails — `null` is not an int or a long.
//   Phase 2 succeeds: Integer, Number and Object are all applicable.
//   Then MOST SPECIFIC wins: Integer <: Number <: Object, so Integer.
//
// ⭐⭐⭐ THE FINDING THAT IS WORTH MORE THAN THE WHOLE PROGRAM:
//   Add `static void f(int... x)` to the family above — just ONE more
//   overload — and `f(null)` STOPS COMPILING:
//
//     error: reference to f is ambiguous
//       both method f(Number) in OverloadResolution and method f(int...) match
//
//   WHY: phase 2 succeeds, so we go to "most specific". For that comparison
//   the JLS treats a variable-arity `f(int...)` as if it were `f(int[])`.
//   Now compare `Integer` (or `Number`) against `int[]`: neither is a subtype
//   of the other, so NEITHER is more specific → ambiguous → compile error.
//   The varargs method was never even *applicable* to the call, and it still
//   destroyed it.
//
//   ✅ THE LESSON, AND IT IS A REAL DESIGN RULE: adding a varargs overload to
//   an existing overload set can break call sites that used to compile — with
//   no change at those call sites. It is a SOURCE-INCOMPATIBLE change to a
//   library API. This is why `List.of(a, b, c)` and `Arrays.asList` can
//   surprise you when you pass something odd, and why adding `log(String,
//   Object...)` next to `log(String, Object)` is a genuinely risky refactor.
//   (Verified empirically with javac, not recalled from a book — run it.)
//
// ⭐⭐ THE DEEPER POINT: overload resolution is 100% COMPILE TIME, on the
//   STATIC type. Pass an `ArrayList` through a parameter declared as `List`
//   and the `List` overload is chosen, forever, regardless of the runtime type.
//   Contrast with OVERRIDING, which is 100% runtime (§9.5).
// 🔑 THE INTERVIEW LINE: "Overloading is resolved at compile time in three
//    phases — strict (no boxing, no varargs), loose (boxing allowed), then
//    varargs — and within the winning phase the most specific method is
//    chosen, or it's an ambiguity error if two are siblings. Overriding is
//    resolved at runtime by the object's actual class. And the subtlety I'd
//    add unprompted: a varargs overload participates in the most-specific
//    comparison even when it isn't applicable, so adding one to an existing
//    overload set can turn a compiling `f(null)` call into an ambiguity error
//    — which makes it a source-incompatible API change."
```

## 9.4 The `null` argument and other ambiguity traps — [SHOULD KNOW]

```java
static void h(String s)  { }
static void h(Object o)  { }
h(null);                     // ✅ h(String) — String is more specific than Object

static void k(Integer i) { }
static void k(Long l)    { }
// k(null);                  // ⛔ AMBIGUOUS — Integer and Long are siblings

static void m(int x)     { }
static void m(Integer x) { }
m(5);                        // ✅ m(int) — phase 1 (no boxing) wins

// ⭐ THE VARARGS-LOSES RULE:
static void n(int a, int b)   { System.out.println("two ints"); }
static void n(int... a)       { System.out.println("varargs"); }
n(1, 2);                       // ✅ "two ints" — phase 1 beats phase 3
```

## 9.5 ⭐⭐ Compile-time (overload) vs runtime (override) — [MUST KNOW]

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.11 — the program that mixes both and surprises everyone
// ══════════════════════════════════════════════════════════════════════
// WHAT   : one overloaded method, one overridden method, one call that uses
//          both. Predict the output before running.
// WHY    : this single program is the clearest demonstration of static vs
//          dynamic dispatch in Java. It is asked constantly.
// OUTPUT : shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class StaticVsDynamic {

    static class Animal {
        String name() { return "generic animal"; }         // OVERRIDDEN below
    }
    static class Dog extends Animal {
        @Override String name() { return "dog"; }           // ⭐ runtime choice
    }

    // ⭐ OVERLOADS: chosen at COMPILE time on the STATIC type of the argument
    static void feed(Animal a) { System.out.println("  feed(Animal)  — " + a.name()); }
    static void feed(Dog d)    { System.out.println("  feed(Dog)     — " + d.name()); }

    public static void main(String[] args) {
        Dog    realDog     = new Dog();
        Animal upcastDog   = new Dog();      // ⭐ static type Animal, runtime Dog

        System.out.println("feed(realDog):");
        feed(realDog);
        System.out.println("feed(upcastDog):");
        feed(upcastDog);                     // ← predict carefully

        System.out.println("names:");
        System.out.println("  realDog.name()   = " + realDog.name());
        System.out.println("  upcastDog.name() = " + upcastDog.name());
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// feed(realDog):
//   feed(Dog)     — dog
// feed(upcastDog):
//   feed(Animal)  — dog          ⭐⭐ THE SURPRISE, ON ONE LINE
// names:
//   realDog.name()   = dog
//   upcastDog.name() = dog
// ──────────────────────────────────────────────────────────────────────
// ⭐⭐ READ THE SECOND LINE TWICE:
//   • `feed(Animal)` was chosen — because OVERLOADING uses the STATIC type
//     of `upcastDog`, which is Animal. Decided at COMPILE time.
//   • `name()` returned "dog"   — because OVERRIDING uses the RUNTIME type
//     of the object, which is Dog. Decided at RUNTIME by invokevirtual.
//   Both mechanisms operated on the same expression, in the same call.
// 🔑 THE INTERVIEW LINE: "Overload resolution is static — compile time, on
//    the declared type. Override dispatch is dynamic — runtime, on the actual
//    class, implemented by invokevirtual and the vtable. The program that
//    proves it passes an Animal-typed reference holding a Dog into overloaded
//    feed(Animal)/feed(Dog): it calls feed(Animal), and inside, a.name()
//    still returns dog."
```

---

<a name="part-10"></a><a name="part-10---pass-by-value"></a>
# PART 10 · ⭐⭐ PASS BY VALUE

> **The most-asked Java fundamentals question.** Get this wrong in an interview and the rest of your OOP answers are discounted, because it is the canary for "has this person actually thought about how the language works?"

## 10.1 The sentence — [MUST KNOW]

> ⭐⭐ **"Java is *always* pass by value. There is no exception for objects. For an object, the value that is passed is a *copy of the reference*."**

Two consequences, and they are the whole of it:

| You can | You cannot |
|---|---|
| ✅ **mutate the object** the copy points at — the caller sees it, because it is the *same object* | ⛔ **rebind the caller's variable** — your copy of the reference is yours alone |

⛔ **"Java is pass by reference for objects" is wrong**, and here is the precise reason: in a pass-by-reference language, a method can assign to its parameter and the caller's variable changes. **Java cannot do that.** Proof 3 below demonstrates it. That single observable difference is the definition.

## 10.2 The four proofs — [MUST KNOW]

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.12 — pass by value, proven four ways
// ══════════════════════════════════════════════════════════════════════
// WHAT   : ① a primitive ② mutating an object ③ REASSIGNING the reference
//          ④ the swap that fails. Run these in order — each builds on the last.
// WHY    : ③ is the decisive proof. Everything else is consistent with both
//          theories; only reassignment distinguishes them.
// OUTPUT : shown below. Type this file yourself; do not paste it.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class PassByValueProofs {

    static class Counter {
        int n = 0;
        @Override public String toString() { return "Counter(" + n + ")"; }
    }

    // ── PROOF ① a PRIMITIVE ────────────────────────────────────────────
    //    the method receives a COPY OF THE VALUE. Changing the copy cannot
    //    affect the caller's variable. Nobody disputes this one.
    static void bumpPrimitive(int x) {
        x = x + 100;
        System.out.println("    inside : x = " + x);
    }

    // ── PROOF ② an OBJECT, MUTATED ─────────────────────────────────────
    //    the method receives a COPY OF THE REFERENCE. That copy points at the
    //    SAME object, so mutating the object IS visible to the caller.
    //    ⭐ THIS IS WHAT FOOLS PEOPLE INTO SAYING "PASS BY REFERENCE".
    static void mutateObject(Counter c) {
        c.n = 999;
        System.out.println("    inside : c = " + c);
    }

    // ── PROOF ③ an OBJECT, REASSIGNED ── ⭐⭐⭐ THE DECISIVE ONE ──────────
    //    the method points ITS OWN COPY of the reference at a NEW object.
    //    The caller's copy still points at the original. Nothing propagates.
    //    ⛔ In a pass-by-reference language, the caller WOULD see the new object.
    static void reassignReference(Counter c) {
        c = new Counter();          // ⭐ rebinding the LOCAL copy only
        c.n = -1;
        System.out.println("    inside : c = " + c + "   (a brand new object)");
    }

    // ── PROOF ④ the swap that fails ────────────────────────────────────
    static void swapPrimitives(int a, int b) {
        int t = a; a = b; b = t;
        System.out.println("    inside : a=" + a + " b=" + b);
    }
    static void swapReferences(Counter a, Counter b) {
        Counter t = a; a = b; b = t;               // ⛔ swaps the LOCAL copies
        System.out.println("    inside : a=" + a + " b=" + b);
    }
    static void swapContents(Counter a, Counter b) {   // ✅ swaps the OBJECTS'
        int t = a.n; a.n = b.n; b.n = t;               //   contents
        System.out.println("    inside : a=" + a + " b=" + b);
    }

    public static void main(String[] args) {
        System.out.println("① PRIMITIVE");
        int i = 1;
        bumpPrimitive(i);
        System.out.println("    outside: i = " + i + "      ⭐ unchanged\n");

        System.out.println("② OBJECT, MUTATED");
        Counter c = new Counter();
        mutateObject(c);
        System.out.println("    outside: c = " + c + "   ⭐ CHANGED — same object\n");

        System.out.println("③ OBJECT, REASSIGNED   ← the decisive proof");
        Counter d = new Counter();
        reassignReference(d);
        System.out.println("    outside: d = " + d + "     ⭐ UNCHANGED\n");

        System.out.println("④ SWAPS");
        int x = 1, y = 2;
        swapPrimitives(x, y);
        System.out.println("    outside: x=" + x + " y=" + y + "     ⛔ not swapped");
        Counter p = new Counter(); p.n = 1;
        Counter q = new Counter(); q.n = 2;
        swapReferences(p, q);
        System.out.println("    outside: p=" + p + " q=" + q + " ⛔ not swapped");
        swapContents(p, q);
        System.out.println("    outside: p=" + p + " q=" + q + " ✅ contents swapped");
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ① PRIMITIVE
//     inside : x = 101
//     outside: i = 1      ⭐ unchanged
//
// ② OBJECT, MUTATED
//     inside : c = Counter(999)
//     outside: c = Counter(999)   ⭐ CHANGED — same object
//
// ③ OBJECT, REASSIGNED   ← the decisive proof
//     inside : c = Counter(-1)   (a brand new object)
//     outside: d = Counter(0)     ⭐ UNCHANGED
//
// ④ SWAPS
//     inside : a=2 b=1
//     outside: x=1 y=2     ⛔ not swapped
//     inside : a=Counter(2) b=Counter(1)
//     outside: p=Counter(1) q=Counter(2) ⛔ not swapped
//     inside : a=Counter(2) b=Counter(1)
//     outside: p=Counter(2) q=Counter(1) ✅ contents swapped
// ──────────────────────────────────────────────────────────────────────
```

## 10.3 The memory picture — [MUST KNOW]

```
   STACK (main's frame)              HEAP
   ─────────────────────             ────────────────────────
   main:
     c  ───────────────────────────▶ ┌─────────────────────┐
                                     │ Counter@1b6d  n = 0 │
   reassignReference's frame:        └─────────────────────┘
     c  ──────────┐                             ▲
                  │  (a COPY of main's c,       │
                  │   pointing at the same      │
                  │   object on entry)          │
                  └─────────────────────────────┘
     then:  c = new Counter()
     c  ───────────────────────────▶ ┌─────────────────────┐
                                     │ Counter@2a13  n = -1│  ← becomes garbage
                                     └─────────────────────┘   when the frame pops
   ⭐⭐ main's `c` was NEVER TOUCHED. It is a different variable, in a
      different stack frame, holding a different copy of the reference.
      When reassignReference's frame pops, its copy simply ceases to exist.
```

## 10.4 How to actually swap — [SHOULD KNOW]

Since you cannot rebind the caller's variable, you must change something *shared*:

```java
// ✅ 1. a holder object (the idiomatic answer)
static class IntHolder { int value; }
static void swap(IntHolder a, IntHolder b) {
    int t = a.value; a.value = b.value; b.value = t;      // mutates shared state
}

// ✅ 2. an array (the quick-and-dirty version)
static void swap(int[] arr, int i, int j) {
    int t = arr[i]; arr[i] = arr[j]; arr[j] = t;
}

// ✅ 3. AtomicReference, when concurrency is involved
static <T> void swap(java.util.concurrent.atomic.AtomicReference<T> a,
                     java.util.concurrent.atomic.AtomicReference<T> b) {
    T t = a.get(); a.set(b.get()); b.set(t);
    // ⚠️ NOT atomic as a PAIR. Two threads can still interleave. For a truly
    //   atomic two-variable swap you need one lock around both, or a single
    //   object holding both values. ⭐ Say this in an interview — noticing
    //   that "atomic twice" ≠ "atomic pair" is a staff-level observation.
}

// ⭐ 4. THE REAL ANSWER: don't. Return the new values instead.
record Swapped(int a, int b) {}
static Swapped swap(int a, int b) { return new Swapped(b, a); }
// ✅ Immutable, no aliasing, no shared mutable state, testable, obvious.
//   Java 16+ records make this idiomatic. This is what you should write.
```

🔑 **The interview line, verbatim:** *"Java is always pass by value — there is no pass-by-reference mode. For a primitive, the value itself is copied. For an object, a copy of the reference is passed, so the method can mutate the shared object but cannot rebind the caller's variable. The proof is that a method which assigns a new object to its parameter has no effect on the caller — a pass-by-reference language would show the new object. The practical consequence is that if you need to 'return' a mutation, you either mutate a shared holder or, better, return an immutable result — which records make idiomatic."*

---

<a name="part-11"></a><a name="part-11--string"></a>
# PART 11 · String

## 11.1 ⭐⭐ Immutability, and the four reasons why — [MUST KNOW]

**WHAT.** A `String`'s contents can never change after construction. Its backing array is `private final byte[]` (since Java 9's *compact strings*; before that, `char[]`), and no method exposes it.

**WHY — the four reasons, in order of importance:**

| # | Reason | The mechanism |
|---|---|---|
| 1 | ⭐ **The String pool** | Because a String cannot change, it is safe to share one instance among many references. `"abc"` appears once in the pool and every literal `"abc"` in the program points at it. Mutability would make sharing impossible |
| 2 | ⭐ **Hash caching / security of data structures** | `String.hashCode()` is computed once and **cached in a field**. That is why Strings are excellent `HashMap` keys — the hash never needs recomputing. It is only safe *because* the value cannot change |
| 3 | ⭐ **Security** | Strings carry file paths, URLs, SQL, usernames, class names. If a String could be mutated after a security check, the check would be meaningless — validate `"safe.txt"`, then mutate it to `"/etc/passwd"`. This is the classic argument |
| 4 | ⭐ **Thread safety** | An immutable object is automatically safe to share across threads with no synchronisation, and — with `final` fields — safely *published* too (the JMM guarantees other threads see a fully-constructed final field). Full treatment in `04-ADVANCED` |

```java
// ⭐ "but I changed it!" — no, you didn't. You made a NEW one.
String s = "hello";
s = s.toUpperCase();          // ⭐ s now points at a DIFFERENT String object.
                              //   The original "hello" is untouched (and, if
                              //   nothing else references it, garbage).
System.out.println(s);        // HELLO
// ⭐⭐ THE MENTAL MODEL: String VARIABLES are mutable (they are references).
//   String OBJECTS are immutable. Confusing the two is the whole difficulty.
```

## 11.2 ⭐ The pool, `intern()`, `==` vs `.equals()` — [MUST KNOW]

```
                      ┌──────────────── STRING POOL ────────────────┐
                      │  (a special region of the heap, GC-managed   │
                      │   since Java 7; before that it was PermGen)  │
                      │                                              │
   "hello"  ─────────▶│   ┌──────────────────┐                      │
   (a literal)        │   │ String "hello"   │◀────── s1            │
                      │   └──────────────────┘◀────── s2 (literal)  │
                      │                          ◀───── s3.intern() │
                      └──────────────────────────────────────────────┘

                      ┌──────────────── REGULAR HEAP ────────────────┐
   new String("hello")│   ┌──────────────────┐                      │
        ─────────────▶│   │ String "hello"   │◀────── s4            │
                      │   └──────────────────┘   (a SEPARATE object) │
                      └──────────────────────────────────────────────┘
```

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.13 — the String pool, ==, equals, and constant folding
// ══════════════════════════════════════════════════════════════════════
// WHAT   : eight comparisons. Predict EVERY one before running.
// WHY    : `==` on Strings compiles, runs, and gives the wrong answer
//          silently. This is the mechanism behind it.
// OUTPUT : shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class StringPool {
    public static void main(String[] args) {
        String s1 = "hello";                       // pooled literal
        String s2 = "hello";                       // ⭐ the SAME pooled object
        String s3 = new String("hello");           // ⛔ a NEW object on the heap
        String s4 = new String("hello").intern();  // ✅ back to the pooled one

        System.out.println("① s1 == s2              : " + (s1 == s2));
        System.out.println("② s1 == s3              : " + (s1 == s3));
        System.out.println("③ s1.equals(s3)         : " + s1.equals(s3));
        System.out.println("④ s1 == s4              : " + (s1 == s4));

        // ⭐⭐ CONSTANT FOLDING — the surprise that fools everyone
        System.out.println("⑤ \"a\"+\"b\" == \"ab\"       : " + ("a" + "b" == "ab"));
        String a = "a";
        System.out.println("⑥ (a+\"b\") == \"ab\"     : " + ((a + "b") == "ab"));
        final String fa = "a";
        System.out.println("⑦ (fa+\"b\") == \"ab\"    : " + ((fa + "b") == "ab"));

        // ⭐ the runtime-built string
        String built = new StringBuilder("he").append("llo").toString();
        System.out.println("⑧ built == s1           : " + (built == s1));
        System.out.println("⑧ built.equals(s1)      : " + built.equals(s1));
        System.out.println("⑧ built.intern() == s1  : " + (built.intern() == s1));
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ① s1 == s2              : true      ⭐ the same pooled object
// ② s1 == s3              : false     ⛔ `new` ALWAYS allocates
// ③ s1.equals(s3)         : true      ✅ equals compares CONTENT
// ④ s1 == s4              : true      ⭐ intern() returns the pooled one
// ⑤ "a"+"b" == "ab"       : true      ⭐⭐ CONSTANT FOLDING at compile time
// ⑥ (a+"b") == "ab"     : false       ⭐ not a constant → runtime concat
// ⑦ (fa+"b") == "ab"    : true        ⭐ `final` → a constant again → folded
// ⑧ built == s1           : false     ⭐ StringBuilder output is never pooled
// ⑧ built.equals(s1)      : true
// ⑧ built.intern() == s1  : true      ⭐ intern() finds the pooled copy
// ──────────────────────────────────────────────────────────────────────
// ⭐⭐ WHY ⑤ IS TRUE: javac evaluates `"a" + "b"` at COMPILE TIME because both
//   operands are compile-time constants. The .class file contains the single
//   literal "ab" — there is no concatenation at runtime at all. Verify with
//   `javap -c`: you will see one `ldc "ab"`, not a StringBuilder.
// ⭐ WHY ⑥ IS FALSE: `a` is a non-final local, so it is not a compile-time
//   constant. javac emits a runtime concatenation (§11.3), which produces a
//   NEW String that is not in the pool.
// ⛔ THE RULE: NEVER use == to compare Strings. Use .equals().
//   The ONLY legitimate use of == on Strings is comparing against a known
//   interned constant as a micro-optimisation in a very hot path — and you
//   must prove it with a benchmark first.
// ⚠️ AND THE DANGER OF intern(): the pool is a GC-managed heap region, but
//   interning millions of DISTINCT strings pins them all → memory blowup.
//   It was a real PermGen OOM pattern before Java 7 moved the pool to the heap.
```

## 11.3 Concatenation — and the `StringBuilder` the compiler inserts — [MUST KNOW]

```java
// ── ONE EXPRESSION: the compiler handles it. Fine. ────────────────────
String s = "a" + x + "b" + y;
// javac (Java 8) turns this into:
//   new StringBuilder().append("a").append(x).append("b").append(y).toString()
// javac (Java 9+) turns it into a SINGLE invokedynamic call to
//   StringConcatFactory.makeConcatWithConstants — ⭐ faster and allocates less,
//   because the recipe is computed once and the exact result size is known.

// ── ⛔ IN A LOOP: the compiler CANNOT help you. This is O(n²). ─────────
String result = "";
for (int i = 0; i < 100_000; i++) {
    result = result + i;
    // ⭐ EACH ITERATION builds a NEW StringBuilder, copies the ENTIRE
    //   accumulated string, appends, and creates a NEW String.
    //   Total characters copied ≈ n²/2 = 5 × 10⁹. It does not finish.
}

// ✅ THE FIX
StringBuilder sb = new StringBuilder(1_000_000);   // ⭐ pre-size it!
for (int i = 0; i < 100_000; i++) sb.append(i);
String result2 = sb.toString();
// ⭐ PRE-SIZING matters: the default capacity is 16, and growing means
//   allocating a new char array and copying — the same O(n²) problem, one
//   level down. StringBuilder grows by (old * 2 + 2).
```

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.14 — measuring the loop-concatenation disaster
// ══════════════════════════════════════════════════════════════════════
// WHAT   : the same 50,000-append job, three ways, timed.
// WHY    : this is the single most common Java performance bug that a junior
//          writes and a senior catches in review.
// OUTPUT : shown below (machine-dependent, but the RATIOS are reliable).
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class ConcatenationCost {
    static final int N = 50_000;

    public static void main(String[] args) {
        long t0 = System.nanoTime();
        String a = "";
        for (int i = 0; i < N; i++) a += i;                  // ⛔ O(n²)
        long t1 = System.nanoTime();

        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < N; i++) sb.append(i);            // ✅ O(n), default size
        String b = sb.toString();
        long t2 = System.nanoTime();

        StringBuilder sb2 = new StringBuilder(N * 6);        // ✅ O(n), pre-sized
        for (int i = 0; i < N; i++) sb2.append(i);
        String c = sb2.toString();
        long t3 = System.nanoTime();

        String d = java.util.stream.IntStream.range(0, N)    // ✅ idiomatic
                .mapToObj(Integer::toString)
                .collect(java.util.stream.Collectors.joining());
        long t4 = System.nanoTime();

        System.out.printf("⛔ += in a loop      : %7d ms   (len=%d)%n", (t1-t0)/1_000_000, a.length());
        System.out.printf("✅ StringBuilder     : %7d ms   (len=%d)%n", (t2-t1)/1_000_000, b.length());
        System.out.printf("✅ pre-sized SB      : %7d ms   (len=%d)%n", (t3-t2)/1_000_000, c.length());
        System.out.printf("✅ stream joining    : %7d ms   (len=%d)%n", (t4-t3)/1_000_000, d.length());
        System.out.printf("%nslowdown: %.0fx%n", (double)(t1-t0)/(t2-t1));
    }
}
// ── OUTPUT (verbatim, Temurin 21.0.12.1 — absolute ms are machine-specific) ─
// ⛔ += in a loop      :     897 ms   (len=238890)
// ✅ StringBuilder     :       3 ms   (len=238890)
// ✅ pre-sized SB      :       2 ms   (len=238890)
// ✅ stream joining    :      16 ms   (len=238890)
//
// slowdown: 280x
// ──────────────────────────────────────────────────────────────────────
// ⚠️ NOT A JMH BENCHMARK. The absolute milliseconds will differ on your
//   machine — possibly by several times — depending on CPU, JIT decisions,
//   heap size and collector. TWO THINGS ARE RELIABLE:
//   • the RATIO is large (here 280x; observed between ~100x and ~500x)
//   • the ratio GROWS WITH N: double N and the `+=` version roughly
//     QUADRUPLES. That growth is the signature of O(n²), and it is the
//     actual claim. The millisecond numbers are illustration, not evidence.
// ⭐ len=238890 is exact and worth checking yourself: concatenating the
//   decimal forms of 0..49999 gives 10×1 + 90×2 + 900×3 + 9000×4 +
//   40000×5 = 238,890 characters. Predicting that before running is a good
//   digit-counting exercise.
// ⭐ THE CODE-REVIEW RULE: `+` on Strings is fine in a single expression,
//   including in a log argument. It is ⛔ forbidden as the accumulator of a
//   loop. And a `String.format` inside a hot loop is worse again.
```

## 11.4 String vs StringBuilder vs StringBuffer — [SHOULD KNOW]

| | `String` | `StringBuilder` | `StringBuffer` |
|---|---|---|---|
| Mutable? | ⛔ no | ✅ yes | ✅ yes |
| Thread-safe? | ✅ (immutable) | ⛔ no | ✅ every method is `synchronized` |
| Speed | — | ⭐ **fastest** | ⛔ slower — synchronises every append |
| Use when | constants, keys, anything shared | ⭐ **almost always** | ⛔ essentially never |

⭐ **The honest answer about `StringBuffer`:** do not use it. The reasoning —

1. A `StringBuilder` is almost always a **local variable** or a field of an object that is not shared. Local variables are confined to one thread's stack, so there is nothing to synchronise.
2. Even when a `StringBuffer` *is* shared, its per-method synchronisation does not make your *usage* atomic. `if (sb.length() > 0) sb.deleteCharAt(0);` is still a race — two synchronised calls, not one atomic operation. So the synchronisation buys you nothing useful and costs you on every append.
3. If you genuinely need thread-safe string building, you need a lock around the *whole operation*, not per-method — at which point `StringBuilder` + an explicit lock is clearer and faster.

🔑 **The interview line:** *"StringBuffer exists for historical reasons and I don't use it. Its synchronisation is per-method, which doesn't make a sequence of operations atomic anyway — so it costs performance without buying the safety people think it does. StringBuilder in a local variable is confined to one thread and needs no synchronisation at all. If I truly needed shared mutable string building, I'd use a StringBuilder with an explicit lock around the whole operation, which is both correct and clearer."*

## 11.5 The methods that matter — [SHOULD KNOW]

| Category | Methods | ⭐ Notes |
|---|---|---|
| length / access | `length()` `charAt(i)` `codePointAt(i)` `codePointCount(a,b)` | ⭐ `length()` counts UTF-16 units, not characters (§3.4) |
| compare | `equals` `equalsIgnoreCase` `compareTo` `compareToIgnoreCase` `contentEquals` | ⭐ `compareTo` is lexicographic by code unit — not locale collation |
| search | `indexOf(c/s)` `indexOf(s, from)` `lastIndexOf` `contains` `startsWith` `endsWith` | `indexOf` returns **−1** when absent — check for that, not for `> 0` |
| substring | `substring(begin)` `substring(begin, end)` | ⭐ `end` is **EXCLUSIVE**. Since Java 7u6 it **copies** — no more shared-backing-array memory leak |
| modify (returns new) | `concat` `replace` `replaceFirst` `replaceAll` `toUpperCase` `toLowerCase` `trim` `strip` | ⭐ `trim` removes `<= ' '`; `strip` (Java 11) removes **Unicode** whitespace — use `strip` |
| split / join | `split(regex)` `split(regex, limit)` `String.join(delim, ...)` | ⛔ `split(".")` matches everything. Escape: `split("\\.")`. ⭐ `split(",")` keeps trailing empties **removed** unless you pass a negative limit |
| convert | `toCharArray` `getBytes(charset)` `valueOf(x)` `toString` | ⛔ **never** call `getBytes()` without a charset — it uses the platform default |
| format | `String.format(fmt, args)` `formatted(args)` (15+) | ⛔ slow in a hot loop — it parses the format string every time |
| check | `isEmpty` `isBlank` (11+) | ⭐ `isEmpty` = length 0; `isBlank` = only whitespace |
| ⭐ modern | `lines()` (11) `repeat(n)` (11) `chars()` `indent(n)` (12) `transform(f)` (12) `describeConstable` (12) `resolveConstantDesc` (12) | `repeat` and `lines` are the two you'll use weekly |

```java
// ⭐ the ones that bite:
System.out.println("a,b,c,".split(",").length);      // ⛔ 3, not 4!
System.out.println("a,b,c,".split(",", -1).length);  // ✅ 4 — negative limit
                                                     //   keeps trailing empties
System.out.println("a.b.c".split(".").length);       // ⛔ 0 — "." matches all
System.out.println("a.b.c".split("\\.").length);     // ✅ 3
System.out.println("  x  ".trim().length());         // 1
System.out.println("\u2000 x".strip().length());     // ✅ 1 — strip knows Unicode
System.out.println("  x".trim().equals("\u2000 x".trim())); // ⛔ trim does NOT
                                                     //   remove U+2000
System.out.println("ab".repeat(3));                  // ababab
System.out.println("line1\nline2".lines().count());  // 2  ⭐ a Stream<String>
System.out.println("x".indent(4).length());          // ⭐ 6 — 3 spaces + 'x' +
                                                     //   newline + 1 = 6
```

## 11.6 Text blocks — [SHOULD KNOW]

```java
// ⭐ since Java 15 (final). Three lines of JSON become readable:
String json = """
        {
          "sku": "SKU-1",
          "name": "Espresso Machine",
          "priceCents": 18999
        }
        """;
// ⭐⭐ THE INCIDENTAL-WHITESPACE RULE, which is the part people get wrong:
//   the compiler finds the MINIMUM indentation across all non-blank lines
//   AND the closing """ — then strips exactly that much from every line.
//   So the closing delimiter's position MATTERS: move it left and you change
//   the result. Move it to the content column and you get zero indentation.
//   A trailing \s preserves spaces that would otherwise be stripped.

String sql = """
        SELECT id, sku, name
          FROM product
         WHERE price_cents > ?
         ORDER BY name
        """;
// ✅ THE USE CASES THAT ARE GENUINELY GOOD: SQL, JSON, HTML, XML, help text,
//   expected-output assertions in tests.
// ⛔ NOT a general string replacement. A one-line string is still "a string".
```

---

<a name="part-12"></a><a name="part-12--static"></a>
# PART 12 · `static`

## 12.1 The four static things — [MUST KNOW]

| | Belongs to | Accessed via | Can use `this`? |
|---|---|---|---|
| **static field** | the CLASS — one copy, shared by all instances | `ClassName.field` ⭐ (not `instance.field`) | n/a |
| **static method** | the CLASS | `ClassName.method()` | ⛔ **no** — there is no instance |
| **static block** | the CLASS — runs **once**, at class initialisation | n/a | ⛔ no |
| **static nested class** | the enclosing class, but is a **normal top-level class** in scope terms | `Outer.Nested` | ⛔ no implicit `Outer.this` |

```java
public class StaticDemo {
    static int counter = 0;               // ONE copy, shared by all instances
    int id;                               // one per instance

    StaticDemo() {
        counter++;                        // ⭐ mutating class state from an
        this.id = counter;                //   instance constructor — legal,
    }                                     //   and a concurrency hazard (§12.4)

    static int howMany() { return counter; }   // ✅ no `this` needed
    // static int myId() { return id; }        // ⛔ COMPILE ERROR:
    //   "non-static variable id cannot be referenced from a static context"

    static class Config {                 // ⭐ STATIC NESTED — the default
        String url;                       //   choice for a nested class.
    }                                     //   It needs NO enclosing instance.
    class Listener {                      // ⛔ INNER (non-static) — holds an
        void onEvent() {                  //   implicit reference to the
            System.out.println(id);       //   enclosing StaticDemo instance.
        }                                 //   ⚠️ That is a MEMORY LEAK if the
    }                                     //   Listener outlives the outer object.

    public static void main(String[] args) {
        new StaticDemo(); new StaticDemo(); new StaticDemo();
        System.out.println("howMany = " + howMany());
        Config c = new Config();                       // ✅ no outer instance
        // Listener l = new Listener();                // ⛔ COMPILE ERROR:
        //   an inner class needs an enclosing instance:
        StaticDemo outer = new StaticDemo();
        Listener l = outer.new Listener();             // ✅ this is the syntax,
        l.onEvent();                                   //   and its ugliness is
    }                                                  //   the argument for
}                                                      //   `static`
// ── OUTPUT ─────────────────────────────────────────────────────────────
// howMany = 3
// 4
// ──────────────────────────────────────────────────────────────────────
// ⭐⭐ THE RULE: make a nested class `static` unless you genuinely need the
//   enclosing instance. Effective Java Item 24. The leak is real: an
//   anonymous inner class registered as a listener keeps the whole enclosing
//   object graph alive for as long as the listener is registered.
```

## 12.2 ⭐⭐ THE INITIALISATION ORDER — [MUST KNOW]

**The complete sequence:**

```
════════════ CLASS LOADING — happens ONCE per classloader ════════════
 1. superclass static field initialisers + static blocks
      (in textual order, interleaved)
 2. this class's static field initialisers + static blocks
      (in textual order, interleaved)

════════════ EVERY `new` — happens once per object ══════════════════
 3. superclass: instance field initialisers + instance blocks
      (in textual order, interleaved)
 4. superclass CONSTRUCTOR BODY  (after its implicit/explicit super())
 5. this class: instance field initialisers + instance blocks
      (in textual order, interleaved)
 6. this class CONSTRUCTOR BODY
```

⭐ **The invariant to remember:** *a superclass is always fully initialised before any subclass field initialiser runs.* That is the reason for the "never call an overridable method from a constructor" rule (`02A` topic 3).

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.15 — the complete initialisation order, printed
// ══════════════════════════════════════════════════════════════════════
// WHAT   : a parent and a child, each with a static field, a static block,
//          an instance field, an instance block and a constructor — all
//          printing. Two objects are created.
// WHY    : ⭐ PREDICT THE FULL OUTPUT BEFORE RUNNING IT. This single program
//          settles the topic permanently. Everything else is a corollary.
// OUTPUT : shown below.
// JAVA   : 8+
// ══════════════════════════════════════════════════════════════════════
public class InitOrder {

    static int trace(String what) {          // returns 0 so it can be used
        System.out.println("   " + what);    //   as a field initialiser
        return 0;
    }

    static class Parent {
        static int sField = trace("1. Parent STATIC field");
        static { trace("2. Parent STATIC block"); }

        int iField = trace("   Parent instance field");
        { trace("   Parent INSTANCE block"); }

        Parent() {
            trace("   Parent CONSTRUCTOR body");
            // ⭐ the implicit super() — Object.<init> — ran BEFORE the line
            //   above, and BEFORE Parent's instance field initialisers.
        }
    }

    static class Child extends Parent {
        static int sField = trace("3. Child STATIC field");
        static { trace("4. Child STATIC block"); }

        int iField = trace("   Child instance field");
        { trace("   Child INSTANCE block"); }

        Child() {
            // ⭐ the implicit super() runs HERE — which is what printed the
            //   Parent instance lines above. It MUST be the first statement.
            trace("   Child CONSTRUCTOR body");
        }
    }

    public static void main(String[] args) {
        System.out.println("── main starts ──");
        System.out.println("── new Child() #1 ──");
        new Child();
        System.out.println("── new Child() #2 ──");
        new Child();
        System.out.println("── done ──");
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ── main starts ──
// ── new Child() #1 ──
//    1. Parent STATIC field        ← class loading begins: Parent first
//    2. Parent STATIC block
//    3. Child STATIC field         ← then Child's statics
//    4. Child STATIC block
//       Parent instance field      ← object #1: Parent's fields/blocks
//       Parent INSTANCE block
//       Parent CONSTRUCTOR body    ← then Parent's constructor BODY
//       Child instance field       ← then Child's fields/blocks
//       Child INSTANCE block
//       Child CONSTRUCTOR body     ← then Child's constructor body
// ── new Child() #2 ──
//       Parent instance field      ← ⭐⭐ NO STATIC LINES AT ALL.
//       Parent INSTANCE block         Static initialisation is ONCE per
//       Parent CONSTRUCTOR body       classloader, ever.
//       Child instance field
//       Child INSTANCE block
//       Child CONSTRUCTOR body
// ── done ──
// ──────────────────────────────────────────────────────────────────────
```

### 12.3 ⭐ The forward-reference rules — [SDE3 DIFFERENTIATOR]

```java
public class ForwardReferences {
    // ⛔ RULE 1: you may not READ a field before its declaration in an
    //   initialiser — "illegal forward reference", a COMPILE ERROR.
    // int a = b;
    // int b = 1;

    // ✅ RULE 2: but you MAY read it through a METHOD. This compiles, and
    //   gives the WRONG answer silently.
    static int a = compute();      // ⭐ runs BEFORE b's initialiser
    static int b = 42;
    static int compute() { return b; }    // reads b while b is still 0

    // ✅ RULE 3: writing is always allowed, even forward.
    // static { c = 7; }           // legal
    // static int c;

    public static void main(String[] args) {
        System.out.println("a = " + a);      // ⛔ 0, NOT 42
        System.out.println("b = " + b);      // 42
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// a = 0
// b = 42
// ──────────────────────────────────────────────────────────────────────
// ⭐ WHY: static initialisers run in TEXTUAL ORDER. `a = compute()` is
//   first, so compute() executes while b still holds its DEFAULT (0).
//   Rule 1 exists precisely to stop the obvious version of this mistake —
//   but it cannot see through a method call.
// ⛔ THE PRODUCTION VERSION: two classes whose static initialisers depend on
//   each other. Class A's static block reads a constant from B, which triggers
//   B's initialisation, which reads from A — which is mid-initialisation and
//   returns defaults (or deadlocks, if on different threads). This is why
//   ⭐ circular static dependencies between classes are genuinely dangerous
//   and why lazy initialisation (a holder class, or a method) is safer.
// 🔑 THE INTERVIEW LINE: "Field initialisers and static blocks run in
//    textual order, so reading a field declared later is an illegal forward
//    reference — but reading it through a method call is legal and silently
//    sees the default value. That's the mechanism behind circular static
//    initialisation bugs, and the reason I prefer lazy initialisation via a
//    holder class for anything with a dependency."
```

### 12.4 Static mutable state — [SDE3 DIFFERENTIATOR, pointer]

⛔ `static int counter` incremented from instance constructors (§12.1) is a **data race**. `counter++` is read-modify-write: three operations, not atomic. Two threads can both read 3 and both write 4.

```java
// the three fixes, best to worst:
static final java.util.concurrent.atomic.AtomicInteger COUNTER =
    new java.util.concurrent.atomic.AtomicInteger();      // ✅ lock-free, correct
static int counter2;
static synchronized void inc() { counter2++; }            // ✅ correct, contended
static int counter3;                                       // ⛔ a race
```

Full treatment — the JMM, `volatile`, happens-before, atomics — in `04-ADVANCED-CORE-JAVA.md`. Plant the seed now: ⭐ **every mutable `static` field is a concurrency question.**

---

<a name="part-13"></a><a name="part-13--jvm-memory-beginner-level"></a>
# PART 13 · JVM memory (beginner level)

## 13.1 The two areas you must picture — [MUST KNOW]

```
┌───────────────────────────── JVM PROCESS ──────────────────────────────┐
│                                                                        │
│  ┌──────────── HEAP (shared by ALL threads) ────────────────────────┐ │
│  │  ⭐ EVERY OBJECT lives here. No exceptions.                       │ │
│  │                                                                   │ │
│  │   ┌──────────────────┐      ┌──────────────────────────────┐    │ │
│  │   │ Counter@1b6d     │◀─────│ int[] {10, 20, 30}           │    │ │
│  │   │   n = 999        │      └──────────────────────────────┘    │ │
│  │   └──────────────────┘                                            │ │
│  │   ┌──────────────────┐                                            │ │
│  │   │ String "hello"   │◀──── from the String pool (also the heap,  │ │
│  │   └──────────────────┘        since Java 7)                       │ │
│  │                                                                   │ │
│  │   ⭐ GC manages this. You never free anything manually.           │ │
│  │   ⭐ sized by -Xms / -Xmx, or MaxRAMPercentage in a container.   │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                        │
│  ┌──── METASPACE (native memory, NOT the heap) ─────────────────────┐ │
│  │  class metadata: the Class objects, method bytecode, the constant │ │
│  │  pool, the vtables. ⭐ Replaced PermGen in Java 8. Grows           │ │
│  │  automatically; limited by -XX:MaxMetaspaceSize.                   │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                        │
│  ┌──── THREAD 1 STACK ────┐   ┌──── THREAD 2 STACK ────┐               │
│  │ ⭐ one per thread,     │   │ each frame holds:      │               │
│  │   private, LIFO        │   │  • local variables     │               │
│  │                        │   │    (primitives BY      │               │
│  │  ┌──────────────────┐  │   │     VALUE)             │               │
│  │  │ frame: main()    │  │   │  • references (POINTERS│               │
│  │  │   int i = 1      │  │   │    INTO THE HEAP)      │               │
│  │  │   Counter c ─────┼──┼───┼──▶ the heap            │               │
│  │  │   operand stack  │  │   │  • the return address  │               │
│  │  └──────────────────┘  │   └────────────────────────┘               │
│  │  ⭐ sized by -Xss      │   ⭐ popped when the method returns        │
│  └────────────────────────┘                                            │
│                                                                        │
│  ┌── CODE CACHE ──┐  JIT-compiled native machine code                  │
│  └────────────────┘                                                    │
└────────────────────────────────────────────────────────────────────────┘
```

## 13.2 What lives where — the table to memorise — [MUST KNOW]

| Thing | Where | Notes |
|---|---|---|
| A **primitive local variable** | ⭐ **stack** (the current frame) | dies when the method returns |
| A **reference local variable** | ⭐ **stack** — but the *object* is on the heap | this is the whole of §10 |
| **Every object** (`new`) | ⭐ **heap** | including arrays (§8.1) |
| An **instance field** | heap — inside the object | |
| A **static field** | heap — reachable from the `Class` object | ⭐ since Java 7; previously PermGen |
| A **String literal** | heap — in the **String pool** | ⭐ since Java 7 |
| **Method parameters** | stack — copies (§10) | |
| **Class metadata, bytecode** | **metaspace** (native memory) | |
| **JIT-compiled code** | code cache | |
| **Thread objects** | heap — but each thread's *stack* is native memory | ⭐ `-Xss` per thread; too many threads = OOM even with a small heap |

## 13.3 ⭐ `StackOverflowError` vs `OutOfMemoryError` — [MUST KNOW]

| | `StackOverflowError` | `OutOfMemoryError` |
|---|---|---|
| What is exhausted | ⭐ **ONE thread's stack** | the **heap** (or metaspace, or thread count) |
| Scope | that thread only | ⭐ **process-wide** |
| Usual cause | unbounded / missing-base-case **recursion** | retention (a leak) or `-Xmx` too small |
| Message | `StackOverflowError` (no detail) | ⭐ several distinct messages — **read them** |
| Is it a `MemoryError`? | both are `Error`, not `Exception` | ⛔ **never catch an Error** to continue |
| Fix | in the **code** (the recursion) | in the code (the leak) **or** the sizing |

⭐ **The five `OutOfMemoryError` messages — they are different failures:**

| Message | Real meaning |
|---|---|
| `Java heap space` | ⭐ the classic. Too much live data, or `-Xmx` too small. Get a heap dump |
| `GC overhead limit exceeded` | the GC spent >98% of time recovering <2% of heap. A slow-motion heap exhaustion |
| `Metaspace` | too many **classes** loaded — dynamic proxies, heavy reflection, classloader leaks (the Tomcat redeploy bug) |
| `unable to create new native thread` | ⛔ **not a heap problem.** You hit the OS thread limit or `-Xss` × threads exceeded native memory |
| `Direct buffer memory` | NIO direct buffers (Netty, Kafka clients) — outside the heap, limited by `-XX:MaxDirectMemorySize` |

```java
// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.16 — cause both Errors, deliberately
// ══════════════════════════════════════════════════════════════════════
// WHAT   : two failure modes, selected by an argument.
// WHY    : ⭐ causing an Error on purpose, once, removes the fear and makes
//          the diagnosis instant when you see it in a real log.
// OUTPUT : a stack trace, and the JVM exits non-zero.
// JAVA   : 8+
// ⚠️  Run each mode in its OWN process. Both terminate the JVM.
// ══════════════════════════════════════════════════════════════════════
public class TwoErrors {

    static void recurse(int depth) {           // no base case, on purpose
        if (depth % 1000 == 0) System.out.println("  depth " + depth);
        recurse(depth + 1);                    // ⭐ each call pushes a frame
    }                                          //   onto THIS thread's stack

    public static void main(String[] args) {
        String mode = args.length > 0 ? args[0] : "stack";

        if (mode.equals("heap")) {
            java.util.List<byte[]> hog = new java.util.ArrayList<>();
            long mb = 0;
            while (true) {
                hog.add(new byte[1024 * 1024]);   // 1 MB per iteration, all
                mb++;                             //   strongly referenced — the
                if (mb % 16 == 0) System.out.println("  retained " + mb + " MB");
            }                                     //   GC cannot reclaim any
        }

        if (mode.equals("threads")) {
            // ⭐ the third failure mode, and the one people misdiagnose:
            java.util.List<Thread> ts = new java.util.ArrayList<>();
            while (true) {
                Thread t = new Thread(() -> { try { Thread.sleep(Long.MAX_VALUE); }
                                              catch (InterruptedException ignored) {} });
                t.start(); ts.add(t);             // held, so they never die
            }
            // → "OutOfMemoryError: unable to create new native thread"
            //   ⭐ NOTHING to do with the heap. Raise the OS limit or lower
            //      -Xss, or (usually) fix the code that creates threads per task.
        }

        recurse(0);
    }
}
```

```bash
# run each mode separately — note the different messages:
java -Xss256k 01-lab/TwoErrors.java            # StackOverflowError
                                               # ⭐ a SMALLER -Xss overflows
                                               #   SOONER. Depth is bounded
                                               #   by the stack SIZE.
java -Xmx32m 01-lab/TwoErrors.java heap        # OutOfMemoryError: Java heap space
java -Xmx32m -XX:+HeapDumpOnOutOfMemoryError \
     -XX:HeapDumpPath=/tmp/heap.hprof \
     01-lab/TwoErrors.java heap                # ⭐ and now you have EVIDENCE
ls -la /tmp/heap.hprof                         # open it in Eclipse MAT

# ⭐ the production settings you should always have:
#   -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/dumps
#   -XX:+ExitOnOutOfMemoryError      ← in a container, RESTART is better
#                                      than limping along in a broken state
```

⭐⭐ **The container note that matters in 2026:** never hard-code `-Xmx` in a container. The JVM must size itself from the cgroup limit, or Kubernetes OOMKills it (exit 137) with no heap dump and no `OutOfMemoryError` — the *kernel* kills the process because RSS exceeded the limit, which the JVM never sees.

```bash
java -XX:MaxRAMPercentage=75.0 -jar app.jar    # ✅ 75% of the container limit
java -Xmx2g -jar app.jar                       # ⛔ if the limit is 2Gi, the
                                               #   heap alone hits it, then
                                               #   metaspace + threads + direct
                                               #   buffers push it over → 137
```

---

<a name="part-14"></a><a name="part-14--console-io"></a>
# PART 14 · Console I/O

## 14.1 Command-line arguments — [MUST KNOW]

```java
public class Args {
    public static void main(String[] args) {
        // ⭐ args is NEVER null. With no arguments it is a zero-length array.
        System.out.println("args.length = " + args.length);
        for (int i = 0; i < args.length; i++) {
            System.out.printf("  args[%d] = \"%s\"%n", i, args[i]);
        }
        // ⭐ ALWAYS as strings. YOU parse them. There is no type conversion.
        if (args.length > 0) {
            int n = Integer.parseInt(args[0]);       // ⛔ throws on bad input
        }
        // ✅ THE DEFENSIVE VERSION — what production code does:
        int port = 8080;                                  // a default
        if (args.length >= 1) {
            try {
                port = Integer.parseInt(args[0].trim());  // ⭐ trim: users type
            } catch (NumberFormatException e) {           //   spaces
                System.err.println("invalid port '" + args[0] + "', using " + port);
            }
        }
        if (port < 1 || port > 65535) {
            System.err.println("port out of range: " + port);
            System.exit(2);                    // ⭐ a non-zero exit code is how
        }                                      //   a program reports failure to
    }                                          //   a shell, Docker, K8s, CI
}
// run:  java Args.java 9090 hello "two words"
// ── OUTPUT ─────────────────────────────────────────────────────────────
// args.length = 3
//   args[0] = "9090"
//   args[1] = "hello"
//   args[2] = "two words"     ← ⭐ the shell split on whitespace; quotes group
// ──────────────────────────────────────────────────────────────────────
```

## 14.2 `Scanner` vs `BufferedReader` — [SHOULD KNOW]

| | `Scanner` | `BufferedReader` |
|---|---|---|
| Package | `java.util` | `java.io` |
| Parses types? | ✅ `nextInt()`, `nextDouble()`, `nextBoolean()` | ⛔ strings only — you parse |
| Speed | ⛔ **slow** — regex-based tokenising | ⭐ fast — buffered character reads |
| Delimiters | configurable | you decide (line, or char) |
| Thread-safe? | ⛔ no | ⛔ no |
| Use when | interactive input, small files, convenience | ⭐ large files, stdin, performance |
| Throws on bad input? | ⛔ `InputMismatchException` | you handle the parse |

```java
// ⭐ THE CORRECT PATTERN — and note the try-with-resources.
// ⛔ THE CLASSIC BUG: closing a Scanner on System.in CLOSES System.in.
//   A second Scanner then fails with "No line found". Full treatment in
//   03-FILE-HANDLING-AND-IO.md; the rule is: never close System.in.

// ── BufferedReader: the fast, explicit way ─────────────────────────────
try (java.io.BufferedReader br = new java.io.BufferedReader(
        new java.io.InputStreamReader(System.in))) {       // ⭐ wrap stdin
    System.out.print("name? ");
    String name = br.readLine();                           // may return null on EOF
    System.out.print("age? ");
    int age = Integer.parseInt(br.readLine().trim());      // ⭐ YOU parse
    System.out.printf("hello %s, you are %d%n", name, age);
} catch (java.io.IOException e) {
    System.err.println("I/O failure: " + e.getMessage());
}

// ── Scanner: the convenient way ────────────────────────────────────────
java.util.Scanner sc = new java.util.Scanner(System.in);   // ⭐ do NOT close it
System.out.print("sku? ");
String sku = sc.nextLine();
System.out.print("price? ");
long price = sc.nextLong();                                // ⭐ parses for you
// ⚠️ THE SCANNER TRAP: nextInt()/nextLong() leave the NEWLINE in the buffer,
//   so a following nextLine() returns "". Fix: an extra nextLine() first.

// ── reading a whole file, the modern way (Java 11+) ────────────────────
String content = java.nio.file.Files.readString(java.nio.file.Path.of("notes.txt"));
java.util.List<String> lines = java.nio.file.Files.readAllLines(java.nio.file.Path.of("notes.txt"));
// ⭐⭐ for a LARGE file, never readAllLines — it loads everything into memory.
//   Stream it instead:
try (java.util.stream.Stream<String> stream =
        java.nio.file.Files.lines(java.nio.file.Path.of("big.log"))) {
    long errors = stream.filter(l -> l.contains("ERROR")).count();   // ⭐ lazy
}   // ✅ Files.lines MUST be closed — it holds an open file descriptor.
    //   ⛔ Not closing it is a file-descriptor leak: "Too many open files".
```

## 14.3 ⭐ `printf` and every format specifier — [SHOULD KNOW]

```java
// the shape:   %[argument_index$][flags][width][.precision]conversion
System.out.printf("%-10s %5d %8.2f %6.1f%% %tc %b %x %h%n",
    "espresso", 12, 189.99, 3.14159, new java.util.Date(), true, 255, "abc");
```

| Conversion | Meaning | Example | Output |
|---|---|---|---|
| `%d` | decimal integer | `%d`, 42 | `42` |
| `%d` with flags | `,` grouping · `+` sign · `0` zero-pad · `-` left-align | `%,d` 1000000 | `1,000,000` |
| | | `%05d` 42 | `00042` |
| | | `%-6d\|` 42 | `42    \|` |
| `%f` | decimal float | `%.2f` 3.14159 | `3.14` |
| `%e` | scientific | `%e` 12345.6 | `1.234560e+04` |
| `%g` | `%f` or `%e`, whichever fits | `%g` 0.0001 | `1.00000e-04` |
| `%s` | string | `%-12s` "ab" | `ab          ` |
| `%c` | character | `%c` 'a' | `a` |
| `%b` | boolean | `%b` true | `true` |
| `%x` / `%X` | hexadecimal | `%x` 255 | `ff` |
| `%o` | octal | `%o` 8 | `10` |
| `%n` | ⭐ **platform line separator** | | `\n` on Linux, `\r\n` on Windows |
| `%tF` | ISO date | `%tF` date | `2026-09-16` |
| `%tT` | time | `%tT` date | `14:32:07` |
| `%tc` | full date-time | | `Tue Sep 16 14:32:07 IST 2026` |
| `%%` | a literal percent | | `%` |
| `%h` | hash code (hex) | `%h` obj | `1b6d3586` |

⭐ **Three `printf` facts worth knowing:**
1. ⭐ **Use `%n`, not `\n`**, inside `printf`. `%n` emits the platform separator. In practice `\n` is fine on Linux containers — but `%n` is correct and costs nothing.
2. ⛔ `printf("%d", "hello")` throws `IllegalFormatConversionException` **at runtime**. Format strings are not type-checked at compile time — a genuine weakness versus Kotlin/Scala string interpolation.
3. ⭐ `String.format(fmt, args)` returns the string; `printf` prints it. And `String.format` is **slow** in a hot loop because it parses the format every call — cache the formatter or use `StringBuilder`.

```java
// ⭐ THE LOGGING TRAP, which is the practical version of #3:
log.debug("order " + order.getId() + " total " + order.getTotal());
// ⛔ the concatenation happens ALWAYS, even when debug logging is OFF.
//   You paid for a String build and a boxing on every call, for nothing.
log.debug("order {} total {}", order.getId(), order.getTotal());
// ✅ SLF4J parameterised form: the concatenation happens ONLY if the level
//   is enabled. This one change is worth several percent of CPU in a
//   chatty service — and it is a real code-review comment.
```

---

<a name="part-15"></a><a name="part-15--packages-imports-javadoc"></a>
# PART 15 · Packages, imports, javadoc

## 15.1 Packages — [MUST KNOW]

| Rule | Detail |
|---|---|
| A package **is** a directory | `package com.shop.demo.basics;` ⇒ the file must be in `com/shop/demo/basics/` relative to a classpath root |
| Naming | ⭐ reverse-domain, all lowercase, no underscores: `com.shop.order.service`. Not `com.shop.OrderService` |
| One `package` statement | must be the **first** statement in the file (comments and the module declaration aside) |
| Default package | no `package` statement. ⛔ **never use it** — classes in it cannot be imported by anything else |
| `java.lang` | ⭐ the only auto-imported package. `String`, `Integer`, `Math`, `System`, `Thread`, `Object`, `Exception` need no import |
| Sealed across packages | a `sealed` class's permitted subclasses must be in the **same module**, or (in an unnamed module) the **same package** — `02A` §19 |

```java
package com.shop.demo.basics;      // ← line 1 (after comments)

import java.util.List;             // ⭐ explicit, single-type import.
import java.util.ArrayList;        //   ALWAYS use this form in teaching and
                                   //   in production code.
// import java.util.*;             // ⛔ wildcard: hides which types you use,
                                   //   can cause ambiguity when two packages
                                   //   define the same simple name, and makes
                                   //   a new class silently change meaning.
import static java.lang.Math.max;  // ⭐ static import — use sparingly.
                                   //   Good for assertions (assertEquals) and
                                   //   Math. Bad when the reader then cannot
                                   //   tell where `max` came from.
```

## 15.2 ⭐ The four access modifiers — preview — [MUST KNOW]

```
                     │ same │ same package │ subclass in │ everywhere
                     │ class│              │ OTHER pkg   │ else
─────────────────────┼──────┼──────────────┼─────────────┼───────────
 private             │  ✅  │      ⛔      │      ⛔      │    ⛔
 package-private     │  ✅  │      ✅      │      ⛔      │    ⛔
   (no modifier)     │      │              │ ⚠️ not even │
                     │      │              │  inherited  │
 protected           │  ✅  │      ✅      │      ✅      │    ⛔
 public              │  ✅  │      ✅      │      ✅      │    ✅
```

⭐ **The two cells everyone gets wrong:**
- `protected` from a subclass **in another package**: accessible **only through inheritance** (`this.field`, `super.m()`) — **not** through a reference to another instance of the base class. `otherBase.field` is a compile error even inside your own subclass.
- `package-private` members are **not inherited across packages at all**.

**The full treatment — encapsulation, Tell-Don't-Ask, defensive copies, and why I default to package-private — is in `02A-CASE-A-oops-complete.md` §9.**

## 15.3 javadoc — [RARELY ASKED, but write it]

```java
/**
 * Calculates the discounted total for an order.
 *
 * <p>Discounts are applied per tier and are NOT cumulative. A negative
 * {@code totalCents} is treated as zero rather than rejected, because
 * credit notes arrive as negative totals from the ERP feed.
 *
 * @param tier       the customer tier; must be one of {@link Tier}'s constants
 * @param totalCents the pre-discount total in minor units, may be negative
 * @return the discounted total in minor units, never negative
 * @throws IllegalArgumentException if {@code tier} is null
 * @see #discountRate(Tier)
 * @since 1.4
 * @deprecated use {@link PricingService#price(Order)} instead — this method
 *             does not honour promotional codes. Removal planned for 2.0.
 */
public long discountedTotal(String tier, long totalCents) { … }
```

| Tag | Purpose |
|---|---|
| `{@code x}` | inline monospace, **without** HTML escaping problems — prefer over `<code>` |
| `{@link C#m}` | a hyperlink to a class/member |
| `@param` `@return` `@throws` | the contract. ⭐ **`@throws` documents the contract**, not the implementation |
| `@see` `@since` `@deprecated` | cross-reference, version, and ⭐ always give a **replacement** and a **removal plan** |
| `{@inheritDoc}` | pull the superclass's doc |

```bash
javadoc -d docs -Xdoclint:all src/com/shop/**/*.java
# ⭐ -Xdoclint:all catches missing @param, bad links, invalid HTML. Turn it on
#   in CI for any library you publish. Java 23+ also supports MARKDOWN doc
#   comments (///) — a genuine readability improvement.
```

---

<a name="part-16"></a><a name="part-16--the-toolchain"></a>
# PART 16 · The toolchain

## 16.1 ⭐ `jshell` — the best Java learning tool nobody uses — [MUST KNOW]

```bash
jshell                     # start
jshell --class-path out    # with your compiled classes
jshell 01-lab/File.java    # ⭐ load a file's definitions at startup
```

| Command | What it does |
|---|---|
| `/vars` `/methods` `/types` | ⭐ what is currently in scope |
| `/list` | the snippets you have entered |
| `/history` | everything you have typed |
| `/edit 3` | open snippet 3 in an editor |
| `/env` | the current classpath and startup |
| `/reload` | re-execute everything (after `/env` changes) |
| `/save file.jsh` `/open file.jsh` | persist and restore a session ⭐ |
| `/reset` | clear all state |
| `/exit` or `Ctrl-D` | leave |
| `Tab` | ⭐ completion. `Shift-Tab` shows the documentation |

```
jshell> int x = 5;
x ==> 5                              ← ⭐ jshell shows the RESULT of every
jshell> x * 2                           statement, and auto-names it $2
$2 ==> 10
jshell> Integer a = 127, b = 127; a == b
$3 ==> true                          ← ⭐ the wrapper cache, in 10 seconds
jshell> Integer c = 128, d = 128; c == d
$4 ==> false
jshell> /vars
|    int x = 5
|    Integer a = 127
|    Integer b = 127
|    Integer c = 128
|    Integer d = 128
jshell> List.of(1,2,3).stream().filter(n -> n > 1).toList()
$5 ==> [2, 3]                        ← ⭐ java.util.* is imported by default
jshell> /exit
```

⭐ **How to use it while reading this folder:** every claim about behaviour, verify it in `jshell` before you believe it. It is faster than creating a file, and it makes you *test* the language instead of *trusting* the documentation. That habit is worth more than any single fact in this file.

## 16.2 The single-file source launcher — [MUST KNOW]

Already covered in §2.3. The summary: `java File.java` compiles in memory and runs. Use it for every example in this folder.

```bash
java 01-lab/PassByValueProofs.java          # ✅ no javac, no .class
java --source 17 01-lab/Old.java            # force an older language level
java -cp libs/gson.jar 01-lab/UsesGson.java # with a dependency
```

## 16.3 `jar` and executable archives — [SHOULD KNOW]

```bash
jar cf app.jar -C out .                            # create from a directory
jar cfe app.jar com.shop.demo.Tiny -C out .        # ⭐ e = entry point
jar tf app.jar | head                              # list contents
jar xf app.jar                                     # extract
unzip -p app.jar META-INF/MANIFEST.MF              # ⭐ read the manifest
java -jar app.jar                                  # run it
```

```text
Manifest-Version: 1.0
Created-By: 21.0.5 (Eclipse Adoptium)
Main-Class: com.shop.demo.Tiny        ← ⭐ what `java -jar` looks for
Class-Path: libs/gson.jar             ← ⭐ relative URLs, space-separated.
                                         ⚠️ NOT the -cp syntax, and a common
                                         source of "NoClassDefFoundError".
```

⭐ **A Spring Boot jar is different.** It is a *fat* jar with a nested layout (`BOOT-INF/classes`, `BOOT-INF/lib`) and its own launcher — `org.springframework.boot.loader.launch.JarLauncher` (Boot 3.2+; before that, `org.springframework.boot.loader.JarLauncher`). That is why you cannot `java -cp bootapp.jar com.shop.Api` — the classes are nested inside the archive. Detail in `07-spring-boot/08-DEPLOYMENT.md`.

## 16.4 The flags cheat-sheet — [SHOULD KNOW]

```bash
# ── COMPILE ────────────────────────────────────────────────────────────
javac -Xlint:all -Werror -d out --release 21 src/**/*.java
#     │          │       │      └── target this Java API AND language level
#     │          │       └───────── output directory, package-correct
#     │          └───────────────── ⭐ warnings are errors. Do this always.
#     └──────────────────────────── every warning category

# ── RUN ────────────────────────────────────────────────────────────────
java -cp out \
     -Xms256m -Xmx1g \                       # initial and max heap
     -XX:MaxRAMPercentage=75.0 \             # ⭐ use THIS in a container,
                                             #   not -Xmx
     -Xss512k \                              # per-thread stack
     -XX:+HeapDumpOnOutOfMemoryError \       # ⭐ evidence on OOM
     -XX:HeapDumpPath=/tmp \
     -XX:+ExitOnOutOfMemoryError \           # ⭐ in K8s: restart > limp
     -Xlog:gc*:file=/tmp/gc.log:time,uptime:filecount=5,filesize=20m \
     -Dshop.env=dev \                        # a system property
     com.shop.demo.Tiny arg1 arg2

# ── INSPECT ────────────────────────────────────────────────────────────
java -version                                # runtime version
java -XshowSettings:properties -version      # every system property
java -XX:+PrintFlagsFinal -version | less    # ⭐ every JVM flag and default
jcmd <pid> help                              # ⭐ the modern diagnostic entry
jcmd <pid> GC.heap_info
jcmd <pid> Thread.print                      # a thread dump
jcmd <pid> JFR.start duration=60s filename=/tmp/rec.jfr   # ⭐ flight recorder
jstat -gcutil <pid> 1000                     # GC statistics, 1/s
jstack <pid>                                 # thread dump (older tool)
jmap -histo:live <pid> | head -30            # what is using the heap
jhsdb jmap --heap --pid <pid>                # heap summary
jinfo -flags <pid>                           # the running JVM's flags
jfr print /tmp/rec.jfr                       # read a flight recording
```

⭐ **`jcmd` is the one to learn.** It subsumes `jstack`, `jmap`, `jinfo` and starts JFR. In a container, `jcmd 1 <command>` (PID 1 is your app).

---

<a name="tasks--answers"></a>
# ⭐ PRACTICE — TASKS AND ANSWERS

> **Everything below is practice.** Attempt first; the answers are underneath, in order. Each answer includes the *why*, not just the *what*.

## Set 1 — Coding tasks (12)

| # | Task |
|---|---|
| **C1** | Write `TemperatureTable` that prints Celsius→Fahrenheit for −40..100 in steps of 10, right-aligned in width 6, with 1 decimal place, using `printf`. Include a header row |
| **C2** | Write `BitFlags` implementing a Unix permission model (`rwxrwxrwx`) as an `int`. Provide `has`, `add`, `remove`, `toggle`, and `toRwxString`. Test all four operations |
| **C3** | Write `PowerOfTwo.isPowerOfTwo(int)` with **no loops and no division**. Then explain in a comment why your expression fails for `0` and for negative numbers without the guard |
| **C4** | Write `Money` as a class holding `long cents`, with `add`, `subtract`, `multiply(int)`, `compareTo`, `equals`, `hashCode`, `toString` (`"$12.34"`), and a static `of(String dollars)` parser. ⛔ No `double` anywhere in the file |
| **C5** | Write `ArrayLab` demonstrating all five copies from §8.4 on an `int[]` **and** on a `Point[]`, printing enough to prove which are shallow |
| **C6** | Write `SwapFourWays` implementing §10.4's four swap approaches, and print the before/after for each |
| **C7** | Write `InitOrder2`: **three** levels of inheritance (Grandparent → Parent → Child), each with a static field, static block, instance field, instance block and constructor. Predict the output on paper, then run it |
| **C8** | Write `StringPoolLab` reproducing all nine comparisons in §11.2 plus three of your own. Predict every one first |
| **C9** | Write `ConcatBench` measuring the four concatenation strategies from §11.3 at N = 10,000 / 100,000 / 1,000,000, printing a table. Then state what the growth pattern tells you about the complexity of each |
| **C10** | Write `ErrorsLab` with three modes (`stack`, `heap`, `threads`) producing the three different failures from §13.3. Run all three and record the exact messages |
| **C11** | Write `ArgsParser`: a real command-line parser supporting `--port=8080`, `--verbose`, `--name "two words"`, and positional arguments. Print a usage message and `System.exit(2)` on bad input |
| **C12** | Write `ShopConsole` — the first version of the `shop` app: a `Product` record (`sku`, `name`, `priceCents`), an array of products, and a menu loop that lists products, searches by SKU, computes a basket total, and applies a tier discount. Pure Core Java, no libraries |

## Set 2 — ⭐ "What does this print?" (22)

Predict every one **before** scrolling to the answers.

```java
// P1
System.out.println(0.1 + 0.2 == 0.3);

// P2
Integer a = 100, b = 100;
Integer c = 200, d = 200;
System.out.println((a == b) + " " + (c == d));

// P3
int i = 0;
i = i++;
System.out.println(i);

// P4
System.out.println('a' + 'b');

// P5
System.out.println("" + 'a' + 'b');

// P6
byte b = 100;
b += 100;
System.out.println(b);

// P7
System.out.println(-7 % 2);

// P8
System.out.println(Math.abs(Integer.MIN_VALUE));

// P9
System.out.println(Integer.MAX_VALUE + 1);

// P10
System.out.println(1 << 33);

// P11
System.out.println(-8 >> 1);
System.out.println(-8 >>> 1);

// P12
int[] arr = new int[3];
System.out.println(arr[2]);

// P13
String[] words = new String[3];
System.out.println(words[2] == null);

// P14
Object[] o = new String[2];
o[0] = Integer.valueOf(1);

// P15
int[] ints = {1, 2, 3};
System.out.println(java.util.Arrays.asList(ints).size());

// P16
System.out.println("a,b,c,".split(",").length);

// P17
String s = "hello";
System.out.println((s.toUpperCase() == "HELLO") + " " + ("a"+"b" == "ab"));

// P18
String x = "he"; String y = "llo";
System.out.println((x + y) == "hello");

// P19
System.out.println(7 / 2 + " " + 7.0 / 2);

// P20  (two parts — predict BOTH)
boolean t = true;
System.out.println(t ? 1 : null);
Integer n = null;
int x = t ? n : 0;
System.out.println(x);

// P21
static void f(int x)    { System.out.print("int "); }
static void f(Integer x){ System.out.print("Integer "); }
static void f(long x)   { System.out.print("long "); }
f(1); f(Integer.valueOf(1)); f((short) 1);

// P22
static class A { String n() { return "A"; } }
static class B extends A { String n() { return "B"; } }
static void show(A a) { System.out.print(a.n() + " "); }
static void show(B b) { System.out.print(b.n() + " "); }
A ref = new B();
show(ref); System.out.print(ref.n());
```

## Set 3 — Find the bug (12)

Each has a symptom. Find the cause, the fix, and the production incident it would cause.

| # | Code | Symptom |
|---|---|---|
| **B1** | `if (user.isAdmin()) System.out.println("admin"); System.out.println("logging in");` | every user sees "logging in" — but admins also see a second line nobody expected |
| **B2** | `double price = 19.99; long total = (long)(price * qty * 100);` | totals are off by one cent, sometimes |
| **B3** | `Map<Integer,String> m; if (m.get(id) == "default") {...}` | the branch never executes, for any id |
| **B4** | `for (Order o : orders) { if (o.isCancelled()) orders.remove(o); }` | `ConcurrentModificationException` — *sometimes* |
| **B5** | `int mid = (lo + hi) / 2;` in a binary search over a large array | intermittent wrong results and `ArrayIndexOutOfBounds` |
| **B6** | `Integer count = repo.findCount(id); if (count > 0) {...}` | `NullPointerException` in production, never in test |
| **B7** | `byte[] buf = new byte[len]; ... return new String(buf);` | mangled non-ASCII characters — on the Windows build server only |
| **B8** | `String csv = ""; for (Row r : rows) csv += r.toCsv() + "\n";` | the report job takes 40 minutes for 200k rows |
| **B9** | `static SimpleDateFormat FMT = new SimpleDateFormat("yyyy-MM-dd");` shared across requests | dates come out wrong, intermittently, under load |
| **B10** | `public static final int MAX = 1000;` in a shared library, changed to `2000` — callers not rebuilt | callers still use 1000 |
| **B11** | `catch (Throwable t) { log(t); }` around a recursive method | the service limps along with a dead thread and no restart |
| **B12** | `System.out.println("order " + order.getId() + " total " + order.getTotal());` inside `log.debug(...)` in a hot path | CPU usage is 15% higher than expected; the profiler shows `StringBuilder` |

## Set 4 — Interview questions (28)

Answer each out loud, in ≤90 seconds. Then read the model answer.

| # | Question |
|---|---|
| 1 | Is Java compiled or interpreted? |
| 2 | What is the difference between the JDK, the JRE and the JVM? |
| 3 | What exactly does `javac` produce, and what does the JVM do with it? |
| 4 | What is the JIT, and why does it matter for a containerised service? |
| 5 | Why is `main` `static`? |
| 6 | Is `String[] args` the only valid `main` signature in Java 25? |
| 7 | Name all eight primitives with their sizes. |
| 8 | Why should you never use `double` for money? What should you use? |
| 9 | What is the difference between `BigDecimal("0.1")` and `BigDecimal.valueOf(0.1)`? |
| 10 | Why does `Integer a = 127, b = 127; a == b` print true but `128` print false? |
| 11 | What happens when you unbox a `null` `Integer`, and where does the exception appear to come from? |
| 12 | What is the difference between `&&` and `&`? Give a case where using the wrong one is a security bug |
| 13 | Why does `HashMap` use `(n-1) & hash` instead of `hash % n`? |
| 14 | What does the ternary operator do when one branch is `int` and the other is `Integer`? |
| 15 | What is the difference between `(int) d` and `Math.round(d)`? |
| 16 | Why does `byte b = 1; b += 1;` compile but `b = b + 1;` not? |
| 17 | What does the enhanced `for` compile to, for an array versus a `List`? |
| 18 | Why can you not remove an element inside an enhanced `for`, and why does the exception sometimes not appear? |
| 19 | Is `arr.length` a field or a method? Why is this confusing? |
| 20 | Name the five ways to copy an array. Which are deep? |
| 21 | What is `ArrayStoreException`, and what does it tell you about arrays versus generics? |
| 22 | Is the return type part of a method's signature? What follows from that? |
| 23 | ⭐ Explain overload resolution. All three phases |
| 24 | ⭐⭐ Is Java pass by value or pass by reference? Prove it |
| 25 | Why is `String` immutable? Give four reasons |
| 26 | Why is `"a"+"b" == "ab"` true but `(s+"b") == "ab"` false? |
| 27 | String vs StringBuilder vs StringBuffer — which do you use and why? |
| 28 | ⭐⭐ What is the exact initialisation order when you call `new Child()`? |

---

# ✅ ANSWERS

## Set 1 — Coding tasks

**C1 — TemperatureTable.** The two things being tested: `printf` width/precision alignment, and the conversion formula.

```java
public class TemperatureTable {
    public static void main(String[] args) {
        System.out.printf("%6s %8s%n", "°C", "°F");       // ⭐ %n, not \n
        System.out.printf("%6s %8s%n", "------", "--------");
        for (int c = -40; c <= 100; c += 10) {
            double f = c * 9.0 / 5.0 + 32;
            //        ⭐ 9.0, NOT 9. With `c * 9 / 5` this is INTEGER
            //           arithmetic: the division truncates BEFORE the
            //           conversion to double, and every result is wrong.
            System.out.printf("%6d %8.1f%n", c, f);       // ⭐ width 6
        }                                                 //   right-aligned,
    }                                                     //   1 decimal
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
//     °C       °F
// ------ --------
//    -40    -40.0
//    -30    -22.0
//    -20     -4.0
//    -10     14.0
//      0     32.0
//     10     50.0
//     20     68.0
//     30     86.0
//     40    104.0
//     50    122.0
//     60    140.0
//     70    158.0
//     80    176.0
//     90    194.0
//    100    212.0
// ──────────────────────────────────────────────────────────────────────
```

**C2 — BitFlags.** The point is the four operations and the string rendering.

```java
public class BitFlags {
    // ⭐ 9 bits: owner rwx (8,7,6), group rwx (5,4,3), other rwx (2,1,0)
    static final int OWNER_R = 1 << 8, OWNER_W = 1 << 7, OWNER_X = 1 << 6;
    static final int GROUP_R = 1 << 5, GROUP_W = 1 << 4, GROUP_X = 1 << 3;
    static final int OTHER_R = 1 << 2, OTHER_W = 1 << 1, OTHER_X = 1;
    static final int ALL     = 0b1_1111_1111;            // 9 bits set

    static boolean has(int p, int flag) { return (p & flag) == flag; }
    static int     add(int p, int flag) { return p | flag; }
    static int     rem(int p, int flag) { return p & ~flag; }
    static int     tog(int p, int flag) { return p ^ flag; }

    // ⭐ iterate high bit → low bit; a triad is r, w, x in that order
    static String toRwx(int p) {
        StringBuilder sb = new StringBuilder(9);
        for (int bit = 8; bit >= 0; bit--) {
            int flag = 1 << bit;
            char c = switch (bit % 3) {                   // ⭐ switch expression
                case 2 -> has(p, flag) ? 'r' : '-';
                case 1 -> has(p, flag) ? 'w' : '-';
                default -> has(p, flag) ? 'x' : '-';
            };
            sb.append(c);
        }
        return sb.toString();
    }

    public static void main(String[] args) {
        int p = 0;
        p = add(p, OWNER_R); p = add(p, OWNER_W); p = add(p, OWNER_X);
        p = add(p, GROUP_R); p = add(p, OTHER_R);
        System.out.println("start      : " + toRwx(p) + "  (" + p + ")");

        p = rem(p, OTHER_R);
        System.out.println("-other_r   : " + toRwx(p));

        p = tog(p, GROUP_W);
        System.out.println("^group_w   : " + toRwx(p));
        p = tog(p, GROUP_W);
        System.out.println("^group_w   : " + toRwx(p) + "   (toggle twice = identity)");

        System.out.println("has owner_x: " + has(p, OWNER_X));
        System.out.println("has other_w: " + has(p, OTHER_W));

        // ⭐ defensive: refuse bits outside the model
        int unmasked = p & ALL;
        System.out.println("masked     : " + toRwx(unmasked));
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// start      : rwxr--r--  (484)   ⭐ 256+128+64+32+4
// -other_r   : rwxr-----
// ^group_w   : rwxrw----
// ^group_w   : rwxr-----   (toggle twice = identity)
// has owner_x: true
// has other_w: false
// masked     : rwxr-----
// ──────────────────────────────────────────────────────────────────────
```

**C3 — isPowerOfTwo.**

```java
public class PowerOfTwo {
    /**
     * A power of two has exactly ONE bit set. Subtracting 1 turns that bit
     * off and turns every lower bit ON, so the AND is zero.
     *
     * ⭐ WHY THE GUARD IS MANDATORY:
     *   x == 0  → 0 & -1 == 0, so the expression alone says TRUE. Wrong:
     *             zero has NO bits set, not exactly one.
     *   x < 0   → the sign bit is set, so `x & (x-1)` is never 0 for a
     *             negative x… except that Integer.MIN_VALUE & (MIN_VALUE-1)
     *             IS 0, because MIN_VALUE is 0x80000000 and subtracting 1
     *             wraps to 0x7FFFFFFF. So MIN_VALUE would report TRUE.
     *             ⭐ That is the single most beautiful edge case in this
     *               whole file — a "power of two" that is negative.
     */
    static boolean isPowerOfTwo(int x) {
        return x > 0 && (x & (x - 1)) == 0;
    }

    public static void main(String[] args) {
        int[] tests = {0, 1, 2, 3, 4, 6, 8, 1024, 1023, -16, Integer.MIN_VALUE};
        for (int t : tests) System.out.printf("  %12d → %b%n", t, isPowerOfTwo(t));
        System.out.println("  without the guard, 0 → " + ((0 & (0 - 1)) == 0));
        System.out.println("  without the guard, MIN_VALUE → "
            + ((Integer.MIN_VALUE & (Integer.MIN_VALUE - 1)) == 0));
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
//              0 → false
//              1 → true
//              2 → true
//              3 → false
//              4 → true
//              6 → false
//              8 → true
//           1024 → true
//           1023 → false
//            -16 → false
//    -2147483648 → false
//   without the guard, 0 → true          ⛔ the expression alone says YES
//   without the guard, MIN_VALUE → true  ⛔ a NEGATIVE "power of two" 
// ──────────────────────────────────────────────────────────────────────
```

**C4 — Money.** The three things being tested: no `double`, correct `equals`/`hashCode`, and formatting from cents.

```java
import java.util.Objects;

public final class Money implements Comparable<Money> {
    private final long cents;                       // ⭐ long minor units

    private Money(long cents) { this.cents = cents; }

    public static Money ofCents(long cents) { return new Money(cents); }

    /** ⭐ Parses "12.34" WITHOUT ever constructing a double. */
    public static Money of(String dollars) {
        Objects.requireNonNull(dollars, "dollars");
        String s = dollars.trim();
        if (s.startsWith("$")) s = s.substring(1);
        boolean negative = s.startsWith("-");
        if (negative || s.startsWith("+")) s = s.substring(1);

        int dot = s.indexOf('.');
        String whole = (dot < 0) ? s : s.substring(0, dot);
        String frac  = (dot < 0) ? ""  : s.substring(dot + 1);
        if (frac.length() > 2) {                       // ⭐ explicit policy,
            throw new IllegalArgumentException(          //   not silent rounding
                "more than 2 decimal places: " + dollars);
        }
        frac = frac + "00";                            // pad to exactly 2
        long value = Long.parseLong(whole.isEmpty() ? "0" : whole) * 100
                   + Long.parseLong(frac.substring(0, 2));
        return new Money(negative ? -value : value);
    }

    public Money add(Money o)      { return new Money(Math.addExact(cents, o.cents)); }
    public Money subtract(Money o) { return new Money(Math.subtractExact(cents, o.cents)); }
    public Money multiply(int q)   { return new Money(Math.multiplyExact(cents, q)); }
    // ⭐ the *Exact methods: overflow THROWS instead of silently wrapping.

    public long cents() { return cents; }

    @Override public String toString() {
        long abs = Math.abs(cents);
        // ⚠️ Math.abs(Long.MIN_VALUE) is negative — but that is −92 quadrillion
        //   cents, which cannot arise from of()/add() without throwing first.
        return (cents < 0 ? "-$" : "$") + (abs / 100) + "."
             + String.format("%02d", abs % 100);
    }

    // ⭐ equals and hashCode use the SAME single field — trivially correct,
    //   and immutable, so it is safe as a HashMap key. That is the whole point
    //   of §11.1's hash-caching argument applied to your own class.
    @Override public boolean equals(Object o) {
        // ⭐ `instanceof Money m` is a PATTERN — since Java 16 (final).
        //   It tests AND binds in one step; no separate cast line.
        return o instanceof Money m && m.cents == cents;
    }
    @Override public int hashCode() { return Long.hashCode(cents); }

    @Override public int compareTo(Money o) { return Long.compare(cents, o.cents); }

    public static void main(String[] args) {
        Money a = Money.of("19.99"), b = Money.of("0.01");
        System.out.println("a            = " + a);
        System.out.println("a × 3        = " + a.multiply(3));
        System.out.println("a + b        = " + a.add(b));
        System.out.println("a == a       = " + a.equals(Money.of("19.99")));
        System.out.println("hash equal   = " + (a.hashCode() == Money.of("19.99").hashCode()));
        System.out.println("a < a+b      = " + (a.compareTo(a.add(b)) < 0));
        System.out.println("negative     = " + Money.of("-5.50"));
        System.out.println("total cents  = " + a.add(b).cents());
        // ⭐ THE PROOF THAT IT IS EXACT:
        Money sum = Money.ofCents(0);
        for (int i = 0; i < 10; i++) sum = sum.add(Money.ofCents(10));
        System.out.println("10 × $0.10   = " + sum + "  ⭐ exactly $1.00");
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// a            = $19.99
// a × 3        = $59.97
// a + b        = $20.00
// a == a       = true
// hash equal   = true
// a < a+b      = true
// negative     = -$5.50
// total cents  = 2000
// 10 × $0.10   = $1.00  ⭐ exactly $1.00
// ──────────────────────────────────────────────────────────────────────
// ⭐ THE MODERN ALTERNATIVE: `record Money(long cents)` gives you equals,
//   hashCode, toString and the accessor for free. You lose: the private
//   constructor (records expose the canonical one — use a COMPACT
//   CONSTRUCTOR to validate) and control of toString's format. For a value
//   type like this, a record with a compact constructor is usually better.
//   See 02A §18.
```

**C5 — ArrayLab.** See §8.4 — PROGRAM 01.09 *is* the answer. Write it from memory rather than copying it; the point is that you can reproduce the five-copy distinction without notes.

**C6 — SwapFourWays.** See §10.4. The key output to produce and explain:

| Approach | Caller's variables swapped? | Why |
|---|---|---|
| `swapPrimitives(int, int)` | ⛔ no | copies of the values |
| `swapReferences(Counter, Counter)` | ⛔ no | copies of the references; rebinding a copy |
| `swapContents(Counter, Counter)` | ✅ yes | mutates the shared objects |
| `swap(IntHolder, IntHolder)` | ✅ yes | mutates a shared holder |
| `swap(int[], i, j)` | ✅ yes | mutates a shared array |
| ⭐ `Swapped swap(int, int)` | ✅ **returns** the answer | no shared mutable state at all — the correct design |

**C7 — InitOrder2.** Three levels produce this order (⭐ predict it on paper first):

```
1. Grandparent STATIC field      ← statics: topmost ancestor first
2. Grandparent STATIC block
3. Parent STATIC field
4. Parent STATIC block
5. Child STATIC field
6. Child STATIC block
── new Child() ──
   Grandparent instance field    ← then per-object, topmost ancestor first
   Grandparent INSTANCE block
   Grandparent CONSTRUCTOR body
   Parent instance field
   Parent INSTANCE block
   Parent CONSTRUCTOR body
   Child instance field
   Child INSTANCE block
   Child CONSTRUCTOR body
```
⭐ **Create a second `Child` and confirm no static lines appear.** Static initialisation is once per classloader, forever.

**C8 — StringPoolLab.** See §11.2 — all nine are printed there with explanations. Three more worth adding, with answers:

| Expression | Result | Why |
|---|---|---|
| `"hello".equals(new String("hello"))` | `true` | `equals` compares content |
| `new String("hello") == new String("hello")` | `false` | two `new`s = two objects |
| `String s = "hel" + "lo"; s == "hello"` | `true` | both constants → folded at compile time |
| `"hel" + new String("lo") == "hello"` | `false` | a `new` is not a constant → runtime concat |
| `s.intern() == s` when `s` came from a literal | `true` | already pooled |
| `s.intern() == s` when `s` came from `new` | `false` | `intern()` returns the pooled one, `s` is the heap copy |

**C9 — ConcatBench.** Expected growth pattern, which is the actual answer to the question:

| N | `+=` in a loop | `StringBuilder` | Ratio |
|---|---|---|---|
| 10,000 | ~15 ms | ~1 ms | 15× |
| 100,000 | ~1,500 ms | ~3 ms | 500× |
| 1,000,000 | ⛔ minutes / OOM | ~40 ms | ~10,000× |

⭐ **The growth pattern is the evidence:** doubling N **quadruples** the `+=` time (that is O(n²) — each iteration copies the whole accumulated string) while the `StringBuilder` time roughly **doubles** (O(n) amortised, plus the occasional resize-and-copy which is also amortised O(1)). Pre-sizing removes the resizes entirely. `Collectors.joining()` is O(n) with a small constant overhead for the stream machinery — slightly slower than a raw StringBuilder at small N, comparable at large N, and more readable.

**C10 — ErrorsLab.** The exact messages you should record:

| Mode | Command | Message |
|---|---|---|
| stack | `java -Xss256k ErrorsLab.java stack` | `Exception in thread "main" java.lang.StackOverflowError` (with a very long, repetitive trace) |
| heap | `java -Xmx32m ErrorsLab.java heap` | `java.lang.OutOfMemoryError: Java heap space` |
| threads | `java ErrorsLab.java threads` | `java.lang.OutOfMemoryError: unable to create new native thread` |

⭐ **The lesson in one line:** the first is per-thread and code-caused; the second is process-wide and retention-or-sizing-caused; the third is **not a heap problem at all** and will send you down the wrong path if you only know "OOM means more memory".

**C11 — ArgsParser.** The structure worth producing:

```java
public final class ArgsParser {
    private final Map<String, String> options = new LinkedHashMap<>();
    private final Set<String> flags   = new LinkedHashSet<>();
    private final List<String> positional = new ArrayList<>();

    public ArgsParser(String[] args) {
        for (int i = 0; i < args.length; i++) {
            String a = args[i];
            if (a.startsWith("--")) {
                String body = a.substring(2);
                int eq = body.indexOf('=');
                if (eq >= 0) {                              // --port=8080
                    options.put(body.substring(0, eq), body.substring(eq + 1));
                } else if (i + 1 < args.length && !args[i+1].startsWith("--")) {
                    options.put(body, args[++i]);           // --name "two words"
                } else {
                    flags.add(body);                        // --verbose
                }
            } else {
                positional.add(a);
            }
        }
    }
    public int port(int dflt) {
        String v = options.get("port");
        if (v == null) return dflt;
        try {
            int p = Integer.parseInt(v.trim());
            if (p < 1 || p > 65535) fail("port out of range: " + p);
            return p;
        } catch (NumberFormatException e) { fail("invalid port: " + v); return dflt; }
    }
    public boolean verbose()       { return flags.contains("verbose"); }
    public String name(String d)   { return options.getOrDefault("name", d); }
    public List<String> positional(){ return List.copyOf(positional); }
    private static void fail(String msg) {
        System.err.println("error: " + msg);
        System.err.println("usage: prog [--port=N] [--name S] [--verbose] [files...]");
        System.exit(2);                       // ⭐ non-zero: the shell, Docker,
    }                                         //   K8s and CI all read this
    // main() omitted for brevity — construct, then query.
}
```
⭐ **The four things that make this production-shaped rather than homework:** `.trim()` before parsing (users type spaces); range validation, not just parse validation; a usage message on **stderr**; and a **non-zero exit code** — which is the only way a shell, a Dockerfile `RUN`, a Kubernetes Job or a CI step can tell that it failed. In a real project you would use picocli instead of writing this; writing it once is why you can evaluate picocli.

**C12 — ShopConsole.** The shape, and the deliberate Core-Java-only constraints:

```java
import java.util.ArrayList;
import java.util.List;
import java.util.Scanner;

public class ShopConsole {
    /** ⭐ a record: immutable, value-based, free equals/hashCode/toString. */
    record Product(String sku, String name, long priceCents) {
        String price() {                                  // ⭐ formatting lives
            return "$" + (priceCents / 100) + "."         //   ON the type, not
                 + String.format("%02d", priceCents % 100); //  scattered in main
        }
    }
    enum Tier { NONE, SILVER, GOLD;
        int discountBps() { return switch (this) {        // ⭐ switch expression
            case NONE -> 0; case SILVER -> 250; case GOLD -> 1000; }; }
            // basis points: 250 = 2.5%, 1000 = 10%. ⭐ NO doubles anywhere.
    }

    static final List<Product> CATALOGUE = List.of(
        new Product("SKU-1", "Espresso Machine", 18999),
        new Product("SKU-2", "Grinder",           7499),
        new Product("SKU-3", "Tamper",            2499));

    public static void main(String[] args) {
        Scanner in = new Scanner(System.in);              // ⭐ do NOT close it
        List<Product> basket = new ArrayList<>();
        while (true) {
            System.out.println("\n[l]ist  [s]earch  [a]dd  [b]asket  [t]otal  [q]uit");
            System.out.print("> ");
            String cmd = in.nextLine().trim().toLowerCase();
            switch (cmd) {                                // ⭐ String switch
                case "l" -> CATALOGUE.forEach(p ->
                    System.out.printf("  %-7s %-18s %8s%n", p.sku(), p.name(), p.price()));
                case "s" -> { System.out.print("sku? "); search(in.nextLine().trim()); }
                case "a" -> { System.out.print("sku? "); addTo(basket, in.nextLine().trim()); }
                case "b" -> basket.forEach(p -> System.out.println("  " + p.name()));
                case "t" -> System.out.println("  total " + total(basket, Tier.GOLD));
                case "q" -> { System.out.println("bye"); return; }   // ✅ exits
                default  -> System.out.println("  unknown command");
            }
        }
    }
    static void search(String sku) {
        // ⭐ findFirst + ifPresentOrElse: no null checks, no index -1 checks
        CATALOGUE.stream().filter(p -> p.sku().equalsIgnoreCase(sku)).findFirst()
            .ifPresentOrElse(
                p -> System.out.println("  found " + p.name() + " " + p.price()),
                () -> System.out.println("  no product with sku " + sku));
    }
    static void addTo(List<Product> basket, String sku) {
        CATALOGUE.stream().filter(p -> p.sku().equalsIgnoreCase(sku)).findFirst()
            .ifPresentOrElse(basket::add,
                () -> System.out.println("  no product with sku " + sku));
    }
    static String total(List<Product> basket, Tier tier) {
        long sub = basket.stream().mapToLong(Product::priceCents).sum();  // ⭐ long
        long disc = sub * tier.discountBps() / 10_000;                    // ⭐ no
        long net = sub - disc;                                            //  double
        return String.format("sub=$%.2f discount=$%.2f total=$%.2f",
            sub / 100.0, disc / 100.0, net / 100.0);
        // ⚠️ HONEST NOTE: the `%.2f` at the END uses doubles — but only for
        //   FORMATTING a value already computed exactly in longs. That is safe:
        //   no arithmetic is done on the double. The rule is "never COMPUTE
        //   money in floating point", not "never print it with %f".
    }
}
```
⭐ **What this small program already demonstrates:** records, enums with behaviour, switch expressions with arrow labels, `List.of` immutability, streams with `mapToLong`, `Optional.ifPresentOrElse`, long-based money, and the Scanner-don't-close rule. That is most of Core Java in 60 lines — which is why it is the last task.

---

## Set 2 — "What does this print?"

| # | Output | ⭐ The why |
|---|---|---|
| **P1** | `false` | `0.1 + 0.2` is `0.30000000000000004`. Binary floating point cannot represent 0.1 exactly. Never `==` on doubles — use a tolerance or `BigDecimal` |
| **P2** | `true false` | `Integer.valueOf` caches −128..127. 100 is inside → the same object. 200 is outside → two objects, and `==` compares identity (§4.2) |
| **P3** | `0` | `i++` yields the OLD value (0) and increments `i` to 1; then the assignment writes 0 back. `x = x++` is always a no-op (§5.1) |
| **P4** | `195` | `'a'`=97, `'b'`=98. Both are **promoted to int** before `+`. 97+98=195 (§6.3) |
| **P5** | `ab` | `""` first makes it string concatenation, so the chars are converted to strings, not numbers. **Left-to-right associativity decides this** |
| **P6** | `-56` | `b += 100` includes an implicit `(byte)` cast (§5.6). 200 = `0b11001000`, whose low 8 bits as a signed byte are −56 |
| **P7** | `-1` | `%` is remainder, not modulus: the sign follows the **dividend**. Use `Math.floorMod(-7, 2)` → 1 (§5.1) |
| **P8** | `-2147483648` | ⭐ `Math.abs(Integer.MIN_VALUE)` is **negative** — there is no +2147483648 in an int. `Math.absExact` throws instead |
| **P9** | `-2147483648` | Overflow wraps silently (§3.5). Use `Math.addExact` to get an exception |
| **P10** | `2` | int shift counts are taken **mod 32**, so `1 << 33` is `1 << 1` (§5.4) |
| **P11** | `-4` then `4294967292` | `>>` sign-extends (stays negative); `>>>` zero-fills, so the result is the unsigned interpretation (§5.5) |
| **P12** | `0` | `new` always zero-fills. There is no uninitialised array element in Java (§8.2) |
| **P13** | `true` | Reference arrays default to `null` (§8.2) |
| **P14** | ⛔ `ArrayStoreException` | Arrays are **covariant**: `String[]` is assignable to `Object[]`. The compiler cannot catch this, so every store is checked at runtime (§8.7) |
| **P15** | `1` | ⭐ `int` is not a valid generic `T`, so `T` binds to `int[]` — a one-element list containing an array. Fix: `Arrays.stream(ints).boxed().toList()` (§8.8) |
| **P16** | `3` | `split(regex)` uses limit 0, which **discards trailing empty strings**. `split(",", -1)` gives 4 (§11.5) |
| **P17** | `false true` | `toUpperCase()` creates a NEW String, so `==` fails. `"a"+"b"` is constant-folded to the literal `"ab"` at compile time, so `==` succeeds (§11.2) |
| **P18** | `false` | `x` and `y` are non-final locals → not compile-time constants → **runtime** concatenation → a new, unpooled String (§11.2 case ⑥) |
| **P19** | `3 3.5` | `7/2` is integer division, truncating. `7.0/2` widens the 2 to double first (§5.1) |
| **P20** | part 1: `1` · part 2: ⛔ `NullPointerException` | Part 1: `int` and the **null literal** make this a *reference* conditional — result type `lub(Integer, null)` = `Integer`, so no unboxing; it prints `1` (and would print `null` if `t` were false). Part 2: `Integer` and `int` make it a *numeric* conditional — result type `int` — and the selected branch holds null, so unboxing throws. ⭐ The lesson: an **unevaluated** branch can never throw; the type is what decides whether unboxing happens (§5.7) |
| **P21** | `int Integer int ` | `f(1)` → phase 1 exact. `f(Integer.valueOf(1))` → phase 1 exact. `f((short)1)` → phase 1 **widening** short→int, which beats phase-2 boxing to `Short` (§9.3) |
| **P22** | `A B` | ⭐⭐ `show(ref)` is an **overload** choice → static type `A` → `show(A)`. Inside it, `a.n()` is an **override** choice → runtime type `B` → `"B"`. Then `ref.n()` → `"B"`. Both mechanisms in one expression (§9.5) |

---

## Set 3 — Find the bug

**B1 — the missing braces.**
- **Cause:** only the first statement belongs to the `if`. Indentation is not syntax.
- **Fix:** braces, always. Enforce with Checkstyle `NeedBraces`.
- **Incident:** ⭐ this is CVE-2014-1266, Apple's `goto fail` — a duplicated line outside the `if` made TLS certificate validation always succeed. A missing-brace bug in security code, live for 18 months.

**B2 — double money, twice over.**
- **Cause:** `price * qty * 100` is double arithmetic, then `(long)` **truncates toward zero**. 19.99 is really 19.989999999999998, so ×100 = 1998.9999… → `(long)` → 1998, one cent short.
- **Fix:** `long total = Math.round(price * qty * 100)` at minimum. Properly: store `priceCents` as a `long` and never involve a double (§3.3, C4).
- **Incident:** systematic undercharging that reconciles to a few cents per order — invisible per transaction, material at volume, and extremely embarrassing in an audit.

**B3 — `==` on Strings.**
- **Cause:** `m.get(id)` returns a String built at runtime (or from the database), so it is not the pooled literal. `==` compares identity → always false. Also `m.get(id)` returns `null` for a missing key, and `null == "default"` is false rather than an NPE — so it fails *silently*.
- **Fix:** `"default".equals(m.get(id))` — ⭐ constant first, which is also null-safe. Or `Objects.equals(...)`, or `getOrDefault(id, "default").equals("default")`.
- **Incident:** a default/fallback branch that never executes. The feature looks implemented, is tested with the literal in unit tests (where it *is* pooled and works!), and silently does nothing in production.

**B4 — removal during iteration.**
- **Cause:** the enhanced `for` uses an `Iterator`; `orders.remove(o)` bumps `modCount`; the next `it.next()` throws (§7.5).
- **Why "sometimes":** ⭐ the check is **best-effort**. Removing the *second-to-last* element often does not throw, because the iterator never calls `next()` again. So it passes on a 3-element test list and fails on a 3000-element production one.
- **Fix:** `orders.removeIf(Order::isCancelled)` — the idiomatic answer. Or `Iterator.remove()`, or filter into a new list.
- **Incident:** an intermittent production exception that cannot be reproduced locally, because the reproduction depends on the *size* of the collection.

**B5 — the overflowing midpoint.**
- **Cause:** `lo + hi` overflows to negative when both are large (§3.5).
- **Fix:** `lo + (hi - lo) / 2`, or `(lo + hi) >>> 1`.
- **Incident:** ⭐ this exact bug was in `java.util.Arrays.binarySearch` and `Collections.binarySearch` for **nine years**, found and written up by Joshua Bloch in 2006. If the JDK shipped it, your code has it.

**B6 — unboxing a null.**
- **Cause:** `count > 0` is a numeric comparison, so `count` is **unboxed** → `intValue()` on null → NPE (§4.4).
- **Why not in test:** the test data always has a row. Production has orders with no matching aggregate, and `COUNT` over an empty set mapped to a nullable wrapper gives null.
- **Fix:** `if (count != null && count > 0)` (short-circuit protects you), or make the repository return `long`/`int` and never null, or `Objects.requireNonNullElse(count, 0)`.
- **Incident:** an NPE whose stack trace points at the comparison, not at the query that returned null — so the fix gets applied in the wrong place.

**B7 — the platform default charset.**
- **Cause:** `new String(buf)` uses `Charset.defaultCharset()`. That was the **platform** default until Java 18 made UTF-8 the default (JEP 400). Windows build servers default to Cp1252.
- **Fix:** `new String(buf, StandardCharsets.UTF_8)` — always, explicitly, everywhere. Same for `getBytes()`.
- **Incident:** "works on my Mac, mangles accented names on the Windows CI agent" — and the corrupt data is then *written to the database*, so it persists after the fix.

**B8 — string concatenation in a loop.**
- **Cause:** `csv +=` creates a new StringBuilder and copies the entire accumulated string every iteration → O(n²) (§11.3). 200k rows ≈ 2×10¹⁰ characters copied.
- **Fix:** one `StringBuilder`, **pre-sized**; or `Collectors.joining("\n")` on a stream; or better, write directly to a `BufferedWriter` so you never hold the whole report in memory.
- **Incident:** a report job that took 4 minutes at 10k rows and 40 minutes at 200k — and then OOMs, because the 2 GB intermediate string is also retained.

**B9 — a shared mutable `SimpleDateFormat`.**
- **Cause:** `SimpleDateFormat` is **not thread-safe** — it holds a `Calendar` internally and mutates it during `format`/`parse`. Concurrent use corrupts it.
- **Why static makes it worse:** one instance shared by every request thread.
- **Fix:** ⭐ `DateTimeFormatter` (Java 8+) — **immutable and thread-safe**, so a `static final` is correct and fast. Or `ThreadLocal<SimpleDateFormat>` if you are stuck on the old API. Or a local instance per call (correct, slower).
- **Incident:** intermittent wrong dates and `NumberFormatException`/`ArrayIndexOutOfBounds` from inside `SimpleDateFormat` — under load only, with stack traces that make no sense. A genuinely famous Java bug.

**B10 — the inlined constant.**
- **Cause:** a `static final` primitive initialised with a constant expression is a **compile-time constant**, and javac **inlines the literal value into the caller's `.class` file** (§3.6). Recompiling the library does not change the callers.
- **Fix:** rebuild every consumer. Or, for values that must change without a full rebuild, do not use a compile-time constant — use a method (`static int max() { return 1000; }`) or configuration.
- **Incident:** a "we changed the limit" release that had no effect on half the services, with no error anywhere. Debugged by decompiling a caller's `.class` and finding the old number baked in.

**B11 — catching `Throwable`.**
- **Cause:** `Throwable` catches `Error` as well as `Exception` — including `StackOverflowError` and `OutOfMemoryError`. Both mean the JVM is in a state you cannot reason about (§13.3).
- **Fix:** catch `Exception` (or something narrower). Never catch `Error` to continue. If you must, rethrow. In a container add `-XX:+ExitOnOutOfMemoryError` so the orchestrator restarts you.
- **Incident:** a thread that "handled" its OOM by logging it, then continued in a heap that is 99% full — the service stays up, passes its health check, and serves errors for hours while nobody is paged. ⛔ This is strictly worse than crashing.

**B12 — concatenating for a disabled log level.**
- **Cause:** `"order " + order.getId() + " total " + order.getTotal()` is evaluated **before** `log.debug` is called, so the concatenation and the boxing happen even when debug is off (§14.3).
- **Fix:** the parameterised form — `log.debug("order {} total {}", order.getId(), order.getTotal())`. SLF4J only builds the string if the level is enabled. Also guard with `isDebugEnabled()` if the *arguments themselves* are expensive.
- **Incident:** a service at 15% extra CPU whose flame graph is dominated by `StringBuilder.append` and `Long.valueOf` — from logging that produces no output at all.

---

## Set 4 — Interview questions

**1 · Compiled or interpreted?** *"Both. `javac` compiles source to platform-neutral bytecode ahead of time. The JVM then interprets that bytecode, and a tiered JIT compiles hot methods to native machine code at runtime, guided by the observed execution profile. So it's compiled twice, and the second compilation is profile-directed — which is why Java warms up and then reaches steady-state throughput comparable to statically compiled languages."*

**2 · JDK vs JRE vs JVM?** *"The JVM is the per-platform execution engine — classloader, verifier, interpreter, JIT, GC. The JRE is the JVM plus the class libraries, enough to run Java. The JDK adds the compiler and tools. Since Java 11 there's no separate JRE distribution: you install a JDK, and if image size matters you use `jlink` to build a minimal runtime containing only the modules you use."*

**3 · What does `javac` produce?** *"A `.class` file: a constant pool plus method bodies as bytecode for a stack machine, with field and method tables. The JVM then loads it through a classloader, **verifies** it — which is the real source of Java's memory safety, since it proves the bytecode can't forge references or overflow the operand stack — prepares and initialises static state, and invokes `main`. Notably, `javac` also **desugars**: generics are erased, the enhanced-for becomes an index or iterator loop, string concatenation becomes an `invokedynamic` to `StringConcatFactory`, and inner classes get synthetic accessors. That's why `javap -c` shows code I didn't write."*

**4 · The JIT, and why it matters in a container?** *"The JVM interprets first and counts executions; hot methods — roughly 1,500 invocations, or 10,000 loop back-edges — get compiled by C1, then very hot ones by C2 with inlining, escape analysis and loop optimisations based on the actual profile. If an assumption breaks, it deoptimises and recompiles. In a container this means three things: a fresh pod has bad p99 latency until it warms up, so I need `minReadySeconds` or a warmup probe before it takes traffic; microbenchmarks without JMH measure the compiler rather than my code; and scale-to-zero workloads pay interpretation on every cold start, which is the real argument for CDS, Leyden's AOT cache, or a GraalVM native image."*

**5 · Why is `main` static?** *"Because the JVM has to call it before any object exists. An instance method needs a receiver, and creating one would require `main` to already have run — circular. So the entry point belongs to the class. It's `public` because the launcher calls it from outside the package, `void` because there's nobody to return to — the exit code is the real result, via `System.exit` — and `String[]` because that's the agreed signature for command-line arguments."*

**6 · Is that the only valid `main` in Java 25?** *"No. `String... args` is equivalent, because varargs desugars to an array. And Java 25 finalised **instance main methods** and **compact source files**, so `void main() { IO.println("hi"); }` with no class declaration at all is now a legal program. The JVM picks the most specific available form. I still write the classic one, because that's what every existing codebase and every interviewer expects — but I can read both."*

**7 · The eight primitives.** *"`byte` 8-bit, `short` 16, `int` 32, `long` 64 — all signed. `float` 32-bit IEEE-754, `double` 64-bit. `char` 16-bit **unsigned**, and it's one UTF-16 code unit, not one character. `boolean`, whose size the spec deliberately leaves unspecified. The two I'd want to recall exactly: `int` is −2³¹ to 2³¹−1 — asymmetric, one more negative than positive, which is why `Math.abs(MIN_VALUE)` is negative — and `long` is ±9.2 × 10¹⁸."*

**8 · Why not `double` for money?** *"Because `double` is a binary fraction and most decimal fractions have no finite binary representation — 0.1 + 0.2 is 0.30000000000000004. Worse, the error accumulates: adding 0.1 ten times gives 0.9999999999999999, and truncating that to cents loses a cent. I use `long` minor units — cents — as the default, because it's exact, fast, and the only risk is forgetting the unit, which I handle by naming the field `priceCents`. I use `BigDecimal` when I need decimal semantics, rounding modes or arbitrary scale, and then I construct it from a **String** and compare with `compareTo`, not `equals`, because `equals` compares scale too."*

**9 · `new BigDecimal("0.1")` vs `valueOf(0.1)`?** *"The constructor from a double captures the double's **exact** value, which is 0.1000000000000000055511151231257827… — the error was already there before BigDecimal saw it. `valueOf(0.1)` goes through `Double.toString`, giving 0.1. So: always construct from a String, or use `valueOf`; never use the double constructor. It's a great example of a fix that contains its own trap."*

**10 · Why `Integer 127 == 127` but not `128`?** *"`Integer.valueOf` caches −128 to 127, so autoboxing inside that range returns the same shared object and `==` on references succeeds. Above 127 you get two distinct objects and `==` compares identity, so it fails. The danger is that it works for every value in your tests and starts failing silently in production once ids pass 128 — no exception, just wrong answers. The rule is never to use `==` on wrapper types; use `equals`, or unbox to a primitive first, which is a numeric comparison."*

**11 · Unboxing a null?** *"NullPointerException — `count > 0` is a numeric comparison so `count` is unboxed, and `intValue()` on null throws. The nasty part is that the stack trace points at the **comparison**, not at the method that returned null, so people fix it in the wrong place. Java 15's helpful NPE messages improved this a lot: 'Cannot invoke Integer.intValue() because \<local3\> is null'. I fix it with a short-circuiting null check, or better, by making the data layer return a primitive and never null."*

**12 · `&&` vs `&`, and a security case?** *"`&&` and `||` short-circuit; `&` and `|` on booleans evaluate both operands. That makes short-circuiting a **correctness** mechanism, not an optimisation: `user != null && user.isAdmin()` only works because `&&` stops at the first false. With a single `&` both sides evaluate and you get an NPE. The security version is worse — a permission check like `isAuthenticated() & hasRole(ADMIN)` would call `hasRole` on a null principal, and depending on how that exception is handled upstream it can fail **open**. Legitimate uses of `&` on booleans are essentially nonexistent, so seeing one in review is a smell."*

**13 · Why `(n-1) & hash` and not `hash % n`?** *"Two reasons, and the second is the important one. Performance: an AND avoids a division, which is roughly ten times slower. Correctness: `%` on a negative hash gives a **negative** index, which would be an `ArrayIndexOutOfBounds`, whereas `(n-1) & hash` is always in `[0, n)`. That only works because the table length is always a power of two — which is why `HashMap` rounds your requested initial capacity up to one. `HashMap` also spreads the hash first with `h ^ (h >>> 16)` so that high bits influence the low-bit index, which matters because the index only looks at the low bits."*

**14 · The ternary with `int` and `Integer` branches?** *"Two separate rules, and conflating them is the common mistake. First, the expression's **type** is decided at compile time from the static types of **both** branches: `int` and `Integer` give a numeric conditional with result type `int`, while `int` and the `null` literal give a reference conditional with result type `Integer`. Second, only the **selected** branch is evaluated at runtime — so an unselected nullable branch can never throw, which is the myth I'd correct if an interviewer stated it. The real hazard is that when the result type is primitive, the selected branch gets unboxed, and a null there throws. So `t ? nullable() : 1` NPEs but `t ? 1 : nullable()` does not. The nastier consequence is refactoring: adding a primitive branch can change the whole expression's type and introduce unboxing that wasn't there, which is source-compatible and invisible in review. My rules are never to mix boxed and unboxed numerics in a ternary, and never to unbox a ternary into a primitive when any path can be null — assign to the wrapper, null-check, then unbox. And a related one I'd volunteer: `getOrDefault` defaults on an **absent key**, not on a **null value**, so a present-but-null mapping still NPEs on unboxing — that's why `ConcurrentHashMap` and `Map.of` reject null values outright."*

**15 · `(int) d` vs `Math.round(d)`?** *"`(int)` truncates toward zero — 2.9 becomes 2 and −2.9 becomes −2. `Math.round` rounds half-up and is defined as `floor(x + 0.5)`, so 2.5 → 3 and −2.5 → −2; note it returns a **long** for a double argument. If I want half-to-even, that's `Math.rint`. And for a narrowing conversion I don't control, I use `Math.toIntExact`, which **throws** on loss instead of silently truncating."*

**16 · Why does `b += 1` compile but `b = b + 1` not?** *"Compound assignment includes an implicit cast — the JLS defines `b += 1` as `b = (byte)(b + 1)`. Plain `b + 1` promotes both operands to `int`, and assigning an `int` to a `byte` needs an explicit cast. The consequence is that compound assignment can **silently narrow and overflow**: `byte b = 100; b += 100;` gives −56 with no warning from `javac -Xlint:all`. That's a genuine argument for ErrorProne in the build, because the standard lint doesn't catch it."*

**17 · What does the enhanced `for` compile to?** *"Two different things. For an **array**, an index loop reading `arr.length` each iteration. For an **Iterable**, an `Iterator` loop — `iterator()`, then `hasNext()`/`next()`. That single fact explains three behaviours: arrays iterate slightly faster; `List<Integer>` unboxes on every `next()`; and removing during iteration throws `ConcurrentModificationException`, because `ArrayList.remove` bumps `modCount` and the iterator's `next()` compares it against `expectedModCount`."*

**18 · Why can't you remove in an enhanced `for`, and why does the exception sometimes not fire?** *"Because it's an iterator loop and the iterator is fail-fast: a structural modification through any other path bumps `modCount`, and the next `next()` throws. The exception is **best-effort** — it's a bug detector, not a guarantee. Removing the second-to-last element often doesn't throw, because the iterator never calls `next()` again to notice. So the code passes on a small test list and corrupts a large production one. The fix is `removeIf`, or `Iterator.remove`, or don't mutate — filter into a new list."*

**19 · Is `arr.length` a field or a method?** *"A field — no parentheses. And `String.length()` is a **method**. The asymmetry exists because an array's length is fixed at creation and stored in the object header, while a String computes it from its backing array. It's a small thing that costs every Java learner ten minutes, and it's a genuine inconsistency in the language. Related: arrays are objects — `a instanceof Object` is true, and `a.getClass().getName()` is `[I`."*

**20 · Five ways to copy an array, and which are deep?** *"`b = a` is not a copy at all — one array, two names. `a.clone()`, `Arrays.copyOf`, `Arrays.copyOfRange` and `System.arraycopy` all create a new array, and **all four are shallow**: the elements are copied by value, so for reference types you get the same objects. None is deep. For a deep copy I copy the elements too, using a copy constructor or a static factory — which is also why `clone()` is generally discouraged. `System.arraycopy` is the fastest and the only one that copies into an existing array, and it handles overlapping regions correctly."*

**21 · `ArrayStoreException`, and what it says about arrays vs generics?** *"Arrays are **covariant and reified**: `String[]` is a subtype of `Object[]`, and the element type is known at runtime. So `Object[] o = new String[2]; o[0] = 1;` compiles and throws `ArrayStoreException` at runtime — with a type check on every store. Generics are **invariant and erased**: `List<Object>` is not a supertype of `List<String>`, so the equivalent mistake is a compile error, at the cost of losing the runtime type. That trade — runtime safety versus compile-time safety — is the whole reason collections replaced arrays in idiomatic Java."*

**22 · Is the return type part of the signature?** *"No. The signature is the method name plus the parameter types — not the return type, not the `throws` clause. Two consequences: you cannot overload on return type alone, `int f()` and `long f()` is a compile error; and you cannot overload on checked exceptions. It also matters for erasure — two methods with the same erasure clash even if their generics differ."*

**23 · ⭐ Overload resolution.** *"Entirely at compile time, on static types, in three phases, stopping at the first phase where any applicable method exists. **Phase 1, strict:** no boxing, no unboxing, no varargs — exact matches and widening primitive conversions. **Phase 2, loose:** boxing and unboxing allowed, still no varargs. **Phase 3:** varargs methods become eligible. Then, among the applicable methods, the **most specific** wins; if two are siblings with neither more specific, it's an ambiguity compile error. The classic demonstrations: `f(1)` picks `f(int)` over `f(Integer)` because phase 1 wins; `f((short)1)` picks `f(int)` because widening beats boxing; `f(null)` picks `f(Integer)` over `f(Number)` and `f(Object)` because Integer is most specific — but `g(null)` with `String` and `StringBuilder` overloads is ambiguous. And the contrast that gets asked next: **overriding** is resolved at runtime by the object's actual class, via `invokevirtual`."*

**24 · ⭐⭐ Pass by value or reference? Prove it.** *"Always pass by value — there is no pass-by-reference mode in Java. For a primitive, the value is copied. For an object, a **copy of the reference** is passed. So a method can mutate the shared object and the caller sees it, but it cannot rebind the caller's variable. The proof is reassignment: if a method does `param = new Thing()`, the caller's variable is completely unaffected. In a genuine pass-by-reference language — C++ references, or C#'s `ref` — the caller would see the new object. It doesn't, so Java is pass by value. The corollary is the failed swap: `swap(a, b)` on two ints does nothing, and to actually swap you either mutate a shared holder or, better, return an immutable result — which records make idiomatic."*

**25 · Why is `String` immutable? Four reasons.** *"One, the **String pool** — sharing one instance among many references is only safe if it can't change, and that sharing is why literals are cheap. Two, **hash caching** — `hashCode` is computed once and stored in a field, which is why Strings are excellent `HashMap` keys; that's only valid if the value can't change. Three, **security** — Strings carry paths, URLs, SQL and usernames; if a String could be mutated after a security check, the check would be meaningless. Four, **thread safety** — an immutable object is automatically safe to share, and with `final` fields it's safely *published* too, because the JMM guarantees other threads see a fully-constructed final field. The mental model that prevents confusion: String *variables* are mutable references; String *objects* are immutable."*

**26 · Why is `"a"+"b" == "ab"` true?** *"Constant folding. Both operands are compile-time constants, so `javac` evaluates the concatenation at compile time and the `.class` file contains a single `ldc "ab"` — there's no runtime concatenation at all, and the result is the pooled literal. `(s+"b") == "ab"` is false because `s` is a non-final local, hence not a compile-time constant, so javac emits a runtime concatenation — an `invokedynamic` to `StringConcatFactory` since Java 9, a `StringBuilder` before that — which produces a **new** String that isn't pooled. Add `final` to `s` and it becomes true again. This is exactly why `==` on Strings is unusable: the answer depends on whether the compiler could fold."*

**27 · String vs StringBuilder vs StringBuffer?** *"`String` for anything constant or shared — it's immutable, so it's automatically thread-safe and hash-cacheable. `StringBuilder` for building, which is almost always: it's unsynchronised and fastest, and it's nearly always a local variable confined to one thread anyway. `StringBuffer` I don't use. Its synchronisation is **per-method**, which doesn't make a *sequence* of operations atomic — `if (sb.length() > 0) sb.deleteCharAt(0)` is still a race — so it costs performance without buying the safety people assume. If I genuinely needed shared mutable string building I'd use a `StringBuilder` with an explicit lock around the whole operation, which is both correct and clearer. And the practical rule that comes up in review: `+` on Strings is fine in a single expression but is O(n²) as a loop accumulator."*

**28 · ⭐⭐ The initialisation order for `new Child()`.** *"Two phases. **Class loading, once per classloader:** the superclass's static field initialisers and static blocks in textual order, then this class's. **Per object:** the superclass's instance field initialisers and instance blocks in textual order, then the superclass constructor *body*, then this class's instance field initialisers and blocks, then this class's constructor body. The invariant is that a superclass is always fully initialised before any subclass field initialiser runs — because the implicit `super()` is the first statement of the subclass constructor. That invariant is exactly why you must never call an overridable method from a constructor: dynamic dispatch will run the subclass override against subclass fields that haven't been assigned yet, so it sees defaults. The fix is a static factory, or making the method `final` or `private`. A second consequence worth mentioning: static initialisation happens **once**, so creating a second `Child` prints no static lines at all — and a static initialiser that throws gives you `ExceptionInInitializerError` the first time and `NoClassDefFoundError` every time after, which is a diagnostic pattern people miss."*

---

## Related files

| File | Why |
|---|---|
| [`README.md`](./README.md) | this folder's index, the reading order, the version anchors, the lab setup |
| [`00-ONE-DAY-MASTER-PLAN.md`](./00-ONE-DAY-MASTER-PLAN.md) | ⭐ how to work through this file in a day (or three, or six) |
| [`02A-CASE-A-oops-complete.md`](./02A-CASE-A-oops-complete.md) | next. Classes, objects, and 100 assignments |
| [`06-COLLECTIONS-MASTERY.md`](./06-COLLECTIONS-MASTERY.md) | where §5.4's `(n-1) & hash` becomes `HashMap` |
| [`03-FILE-HANDLING-AND-IO.md`](./03-FILE-HANDLING-AND-IO.md) | where §14's console I/O becomes real I/O |
| [`04-ADVANCED-CORE-JAVA.md`](./04-ADVANCED-CORE-JAVA.md) | where §12.4 and §13 become concurrency and GC |
| [`08-CHEATSHEET.md`](./08-CHEATSHEET.md) | every table in this file, on one page |
| [`../09-sde3-interview-vault/01-java-deep-dive-300.md`](../09-sde3-interview-vault/01-java-deep-dive-300.md) | ⭐ the interview mirror — open it in week 2 |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Predict every output before you run it. Being wrong is the learning event.*

</div>
