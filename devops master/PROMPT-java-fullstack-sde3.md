# 🎯 THE MASTER PROMPT — Java Full Stack (SDE 3 / MAANG track)

> **How to use this:** paste the whole block below into a fresh conversation as your FIRST message. It is self-contained — it carries the style contract, the folder tree, the per-file spec, the code-comment standard and the acceptance checklist, so the generator does not need to see your previous folders.
>
> Then drive it one file at a time with: **"GENERATE FILE `<name>`"**.
>
> Save this file. You will reuse it for every folder.

---

## 📋 COPY EVERYTHING BELOW THIS LINE

```
You are building me a complete Java Full Stack learning path, in the same house
style as the learning paths you have already built for me (Docker, Kubernetes,
Monitoring & Alerting, CI/CD). I am targeting an SDE 3 role at a MAANG company
or better. I am a COMPLETE BEGINNER in explanation style but I need SDE 3 /
staff-level DEPTH — explain from absolute zero, then go deeper than most
working engineers can.

═══════════════════════════════════════════════════════════════════════════════
PART 1 — THE STYLE CONTRACT (non-negotiable, applies to every file)
═══════════════════════════════════════════════════════════════════════════════

1. BEGINNER-FIRST, SDE3-DEEP.
   Every concept starts at "what is this and why does it exist", then goes to
   internals, then to the production failure mode, then to the interview line.
   The four-beat structure for every topic:
     WHAT  → a plain-English definition and an analogy
     WHY   → the problem it solves; what happens without it
     HOW   → the mechanics, with internals where they matter
     ⭐ TRAP → the mistake everyone makes, and the production incident it causes

2. EVERY FILE IS SELF-CONTAINED.
   No file may require reading another file to make sense. Cross-reference
   freely ("see 04-ADVANCED §3.2") but restate the essentials locally.

3. CODE IS EXPLAINED IN COMMENTS. (I asked for this explicitly — it is a hard
   requirement.) See PART 3 for the exact standard.

4. PRACTICE QUESTIONS AND ANSWERS GO AT THE END OF EACH FILE, never inline.
   The body teaches; the tail tests. An answer must never appear before its
   question. Put an anchor `<a name="tasks--answers"></a>` before the section
   and link it from the file's table of contents.

5. EXPECTED OUTPUT BLOCKS. Every runnable program is followed by its exact
   console output in a comment block, formatted as:
     // ── OUTPUT ─────────────────────────────
     // hello
     // ───────────────────────────────────────
   If the output is nondeterministic (a HashMap iteration, a race), say so
   explicitly and show two possible outputs.

6. VISUAL MARKERS — use these consistently:
   ⭐      an insight worth memorising
   ⭐⭐    a thing that separates a junior from a senior
   ⭐⭐⭐  a thing that separates a senior from an SDE 3 / staff
   ⛔      an anti-pattern — never do this
   ⚠️      a trap; works until it doesn't
   ✅      the correct way
   🔑      "the answer to say out loud in an interview"

7. TABLES OVER PROSE wherever a comparison exists. Complexity tables, decision
   tables, version tables, "when to use which" tables. Tables are scannable
   during revision; prose is not.

8. DIAGRAMS IN ASCII. No external images — I read these as Markdown. Draw the
   memory layout, the class hierarchy, the call sequence, the object graph.
   Use box-drawing characters. Mermaid is acceptable as a SECOND rendering
   after the ASCII one, never instead of it.

9. "THE INTERVIEW LINE" — after every major topic, a 2–4 sentence verbatim
   answer to the question an interviewer would ask about it. Prefixed with 🔑.
   Written in the first person, as I would say it. Not a summary — a script.

10. VERSIONS ARE PINNED AND MARKED.
    Every API is annotated `// since Java N`. Every preview/incubator feature
    is labelled `⚠️ PREVIEW in Java N — needs --enable-preview`. Verify the
    current versions by web search before you start and record them in a
    "version anchors" block in the README of each folder. Do not guess.

11. EVERY FILE ENDS WITH THE FOOTER (exact template in PART 7).

12. LENGTH IS NOT A CONSTRAINT — COMPLETENESS IS THE GOAL.
    A file that covers a topic completely at SDE 3 depth will be long. That is
    correct. Do not summarise to save space. Do not write "and so on" or
    "similarly for the rest". Enumerate. If a file would exceed roughly 8,000
    lines, split it into lettered parts (02A / 02B) and say so in the README —
    never truncate.

13. NO PLACEHOLDER CODE. Every program is complete and compilable: package
    declaration, imports, class, main method. Never `// ... rest of the code`.
    Never `/* similar */`. If it is too long to show fully, show the part that
    teaches and say exactly what was omitted and why.

14. HONESTY ABOUT TRADE-OFFS. For every recommendation, state what it costs
    and when the opposite choice is right. I am interviewing at staff level —
    "it depends, and here is what it depends on" is the answer I need to be
    able to give.

═══════════════════════════════════════════════════════════════════════════════
PART 2 — THE FULL FOLDER AND FILE TREE
═══════════════════════════════════════════════════════════════════════════════

Root: /home/user/java-fullstack-learning-path/

java-fullstack-learning-path/
├── README.md                     ⭐ the master index: one-line explanation
│                                    for EVERY folder and EVERY file, the
│                                    learning order, the time budget, the
│                                    version anchors, the app-continuity note
├── 00-MASTER-ROADMAP.md          the whole-stack plan: week by week, hour by
│                                    hour, with the dependency graph between
│                                    folders and a "what to skip if you're
│                                    short on time" path
│
├── 01-core-java/                 ◀══ BUILD THIS FIRST, IT IS MY CURRENT FOCUS
│   ├── README.md                 one line per file + the reading order
│   ├── 00-ONE-DAY-MASTER-PLAN.md hour-by-hour for all 6 core files
│   ├── 01-BASICS-AND-TOPIC-MAP.md
│   ├── 02A-CASE-A-oops-complete.md
│   ├── 02B-CASE-B-lld-for-sde3.md
│   ├── 03-FILE-HANDLING-AND-IO.md
│   ├── 04-ADVANCED-CORE-JAVA.md
│   ├── 05-JDBC-BASICS-AND-CRUD.md
│   ├── 06-COLLECTIONS-MASTERY.md
│   ├── 07-PROJECTS.md            the Core Java mini-projects
│   └── 08-CHEATSHEET.md          one page, all of Core Java
│
├── 02-frontend/
│   ├── README.md
│   ├── 00-ONE-DAY-MASTER-PLAN.md
│   ├── html/       (10 files: 01-fundamentals … 09-internals, 10-cheatsheet)
│   ├── css/        (13 files: 01-cascade … 12-architecture, 13-cheatsheet)
│   ├── dom/        (10 files: 01-the-tree … 09-internals, 10-cheatsheet)
│   ├── javascript/ (13 files: 01-the-engine … 12-internals, 13-cheatsheet)
│   ├── react/      (19 files: 01-mental-model … 17-internals, 18-cheatsheet,
│   │                          19-projects-index)
│   └── projects/   ⭐ 15 projects, each its own file, each a COMPLETE
│                      scenario — see PART 5 for the list
│
├── 03-jdbc-deep/                 production JDBC: pooling, transactions,
│   │                             isolation anomalies, batch, migrations,
│   │                             Testcontainers, the full repository layer
│   ├── README.md  00-plan  01→08  CHEATSHEET  PROJECTS
│
├── 04-jsp-servlets/              the web tier — learned to UNDERSTAND Spring
│   │                             MVC, not to build new products
│   ├── README.md  00-plan  01-lifecycle  02-request-response  03-session
│   │   04-filters-listeners  05-jsp-el-jstl  06-mvc-model2  07-security
│   │   08-project-shop-storefront  CHEATSHEET
│
├── 05-hibernate-jpa/             JPA + Hibernate + Spring Data JPA
│   ├── README.md  00-plan  01-jpa-vs-hibernate  02-persistence-context ⭐⭐⭐
│   │   03-entity-lifecycle  04-mapping  05-relationships ⭐⭐⭐
│   │   06-fetching-and-the-n-plus-1 ⭐⭐⭐  07-queries  08-transactions-locking
│   │   09-caching  10-performance  11-spring-data-jpa  12-testing
│   │   13-PROJECTS  CHEATSHEET
│
├── 06-spring-core/               IoC, DI, AOP, transactions, Spring MVC
│   ├── README.md  00-plan  01-ioc-di ⭐⭐⭐  02-bean-lifecycle ⭐⭐⭐
│   │   03-scopes-autowiring  04-configuration  05-aop ⭐⭐⭐
│   │   06-transactions ⭐⭐⭐  07-spring-mvc  08-data-access
│   │   09-testing  10-patterns-inside-spring ⭐⭐  11-PROJECTS  CHEATSHEET
│
├── 07-spring-boot/
│   ├── README.md  00-plan  01-what-boot-actually-does ⭐⭐
│   │   02-configuration  03-web-and-rest  04-data  05-security ⭐⭐⭐
│   │   06-actuator-observability ⭐⭐  07-testing  08-deployment ⭐⭐
│   │   09-messaging-caching-batch  10-webflux-vs-virtual-threads ⭐⭐
│   │   11-microservices-honestly  12-PROJECTS  CHEATSHEET
│
├── 08-fullstack-capstone/        ⭐⭐ the centrepiece: React + Spring Boot +
│   │                             PostgreSQL + Redis + RabbitMQ, containerised,
│   │                             on Kubernetes, monitored, in CI/CD —
│   │                             plugging into my four existing paths
│   ├── README.md  00-plan  01-architecture  02-backend  03-frontend
│   │   04-integration  05-security  06-observability  07-deployment
│   │   08-PROJECT-TASKS-AND-ANSWERS  CHEATSHEET
│
└── 09-sde3-interview-vault/      ⭐⭐ the MAANG-specific layer
    ├── README.md
    ├── 01-java-deep-dive-300.md  300 questions with model answers
    ├── 02-lld-question-bank.md   the 25 MAANG LLD problems, timed scripts
    ├── 03-hld-for-java-devs.md   where Java choices meet system design
    ├── 04-concurrency-interviews.md   the hardest round, isolated
    ├── 05-collections-and-internals.md  HashMap/ConcurrentHashMap from memory
    ├── 06-jvm-gc-performance.md  the staff-level round
    ├── 07-spring-interviews.md   framework depth questions
    ├── 08-behavioural-sde3.md    leadership, scope, ambiguity, the SDE3 bar
    ├── 09-what-happens-when.md   the classic openers, end to end
    └── 10-mock-interview-scripts.md  six full 45-minute rounds, scripted

═══════════════════════════════════════════════════════════════════════════════
PART 3 — THE CODE COMMENT STANDARD (you asked for this explicitly)
═══════════════════════════════════════════════════════════════════════════════

EVERY program follows this exact shape:

  // ══════════════════════════════════════════════════════════════════════
  // PROGRAM 02.14 — The equals/hashCode contract, broken on purpose
  // ══════════════════════════════════════════════════════════════════════
  // WHAT   : a mutable object used as a HashMap key, then mutated.
  // WHY    : this is the single most common Java bug in production code,
  //          and the one interviewers use to separate real from rehearsed.
  // OUTPUT : shown at the bottom. Run it before you read the explanation.
  // JAVA   : 21+ (uses records for the contrast case at the end)
  // ══════════════════════════════════════════════════════════════════════

  package com.shop.demo.oop;                     // ← every program has one

  import java.util.HashMap;                      // ← explicit, never wildcard
  import java.util.Map;                          //   in teaching code
  import java.util.Objects;

  /**
   * A class that violates the equals/hashCode contract by being mutable
   * while it is used as a key.
   *
   * ⭐ THE RULE: an object's hashCode must not change while it is in a
   *    HashMap/HashSet. If it does, the map can no longer find it — the
   *    entry is not deleted, it is ORPHANED. That is a memory leak that
   *    also loses data.
   */
  public final class BrokenKey {                 // final: no subclass can
                                                 //   break equals by adding
                                                 //   a field (the Liskov trap)
      private String name;                       // ⛔ NOT final — that's the bug
      private final int id;

      public BrokenKey(int id, String name) {
          this.id = id;                          // `this.` disambiguates the
                                                 //   field from the parameter
          this.name = name;
      }

      // ⭐ equals() must be: reflexive, symmetric, transitive, consistent,
      //   and null-hostile. The instanceof pattern (Java 16+) gives all five.
      @Override                                  // ← ALWAYS present. Without it
      public boolean equals(Object o) {          //   a typo silently OVERLOADS
          if (this == o) return true;            //   instead of overriding.
          if (!(o instanceof BrokenKey other))   // ⭐ pattern matching: one
              return false;                      //   expression does the null
                                                 //   check, the type check and
                                                 //   the cast.
          return id == other.id                  // primitives: ==
              && Objects.equals(name, other.name); // objects: Objects.equals,
      }                                          //   which is null-safe

      // ⭐ hashCode() must use the SAME fields as equals(). Not a subset.
      //   Not a superset. Objects.hash boxes every argument — fine for
      //   teaching, measurable overhead in a hot path (see 06 §11).
      @Override
      public int hashCode() {
          return Objects.hash(id, name);         // ⛔ name is mutable → the
      }                                          //   hash changes → the bug

      public void rename(String newName) {       // ⛔ the mutation that
          this.name = newName;                   //   orphans the map entry
      }

      @Override
      public String toString() {                 // ⭐ always override this.
          return "BrokenKey[id=" + id + ", name=" + name + "]";
      }  //   The default is ClassName@1b6d3586 — useless in a log line.
  }

  // ... then the driver class with main(), equally commented ...

  // ── OUTPUT ──────────────────────────────────────────────────────────────
  // before mutation : map.get(key) = Order#42      ✅ found
  // after  mutation : map.get(key) = null          ⛔ LOST
  // map.size()      : 1                            ⭐ still there, unreachable
  // map.containsKey(key) : false                   ⛔ it lies to you
  // ────────────────────────────────────────────────────────────────────────
  //
  // WHY: HashMap computes index = (n - 1) & hash. After rename() the hash
  // changed, so get() looks in a DIFFERENT bucket, finds nothing, returns
  // null. The entry is still in the old bucket. size() counts entries, not
  // reachable keys — so the map grows forever.
  //
  // 🔑 THE INTERVIEW LINE: "equals and hashCode must agree, and both must be
  //    computed from immutable state. A mutable key doesn't just fail a
  //    lookup — it orphans the entry, so the map leaks memory while
  //    reporting a smaller contents than it holds. That's why records, and
  //    final fields, are the default for anything that goes in a Set or Map."

COMMENT RULES:
  · Explain WHY, not WHAT — except the first time a construct appears, where
    you explain BOTH.
  · Comment the non-obvious line, not the obvious one. `i++` needs no comment.
    `map.computeIfAbsent(k, x -> new ArrayList<>())` does.
  · Mark every trap with ⚠️ and every insight with ⭐ inline.
  · Align trailing comments in a column where it aids reading.
  · Number programs `<file>.<n>` (PROGRAM 06.23) so I can reference them.
  · Group related programs in one file where they build on each other, and say
    "run these in order — each assumes the last".

═══════════════════════════════════════════════════════════════════════════════
PART 4 — THE ASSIGNMENT AND PRACTICE STANDARD
═══════════════════════════════════════════════════════════════════════════════

A. IN-TOPIC ASSIGNMENTS (File 02A specifically: FIVE PER TOPIC — I asked for
   this by name). Every OOP topic gets exactly 5 assignments, graduated:
     A1 — reproduce: use the feature exactly as taught
     A2 — vary: the same feature in a different shape
     A3 — combine: this feature plus two earlier ones
     A4 — break: find or create the failure mode; explain it
     A5 — ⭐ design: a small real-world modelling problem that forces a choice
   Each assignment states: the problem, the constraints, the expected output
   or behaviour, ONE hint (not the answer).
   The FULL SOLUTIONS with line-by-line comments go in the answers section at
   the END of the file, keyed by number.

B. END-OF-FILE PRACTICE — every file ends with all four of these sets:
   1. CODING TASKS (8–15) — build something. Solutions at the end.
   2. "WHAT DOES THIS PRINT?" (15–25) — ⭐ the highest-value Java interview
      format. Short programs with a subtle behaviour. Answer + the WHY.
   3. FIND THE BUG (10–15) — broken code, the symptom, the fix, and the
      production incident it would cause.
   4. INTERVIEW QUESTIONS (20–40) — with 🔑 model answers at SDE 3 depth,
      including the follow-up the interviewer will ask and its answer.

C. Answers are ALWAYS at the end, always complete, always commented to the
   same standard as the teaching code.

═══════════════════════════════════════════════════════════════════════════════
PART 5 — THE PER-FILE CONTENT SPECIFICATION
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
FOLDER 1 — 01-core-java  (BUILD THIS FIRST)
───────────────────────────────────────────────────────────────────────────────

FILE 01 — 01-BASICS-AND-TOPIC-MAP.md
  ONE-LINE: the complete map of Core Java with a mastery level per topic, then
            the fundamentals from zero — how Java actually runs.
  · ⭐ THE MAP FIRST: a full tree of every Core Java topic, each marked
    [MUST KNOW] / [SHOULD KNOW] / [SDE3 DIFFERENTIATOR] / [RARELY ASKED],
    with the file in this folder that covers it. This is my revision index.
  · The Java story: JDK / JRE / JVM, what javac produces, bytecode, the JIT,
    "write once run anywhere" and what it actually costs.
  · Running a program end to end: javac → .class → java → classloader →
    main. Show the .class file with javap. Explain the classpath.
  · The main method signature — every modifier, why each is there, and what
    breaks if you change it (⭐ `String[] args` vs `String... args`).
  · Primitives: all 8, sizes, ranges, default values, why float/double are
    imprecise (⭐ and why money is never a double), char and Unicode.
  · Wrappers: the cache ranges (⭐ Integer.valueOf caches -128..127 — the
    `==` trap that fails only sometimes), autoboxing/unboxing, the NPE on
    unboxing a null Integer, the boxing cost in loops.
  · Literals, underscores in numbers, binary/hex/octal, the final keyword.
  · Operators: arithmetic, relational, logical (&& vs &, || vs | — the
    short-circuit difference with a side-effect proof), bitwise (every one,
    with the use cases: flags, masks, the HashMap index trick), assignment,
    the ternary (⭐ and its numeric-promotion NPE trap), instanceof.
  · Precedence and associativity — the full table, plus "just use parentheses".
  · Type casting: widening vs narrowing, the data loss, (int) vs Math.round,
    the char/int arithmetic surprise.
  · Control flow: if/else, switch (old and new — the expression form, arrow
    labels, exhaustiveness with sealed types, `yield`), for, enhanced for
    (⭐ what it compiles to for arrays vs Iterables), while, do-while,
    break/continue with labels, the infinite-loop idioms.
  · Arrays: 1D, 2D, jagged, the fact that they are OBJECTS, `length` is a
    field not a method, default initialisation, copying (shallow vs deep,
    Arrays.copyOf/copyOfRange/System.arraycopy), sorting, searching, the
    varargs-is-an-array connection, ArrayIndexOutOfBounds vs
    NegativeArraySizeException.
  · Methods: signature, overloading resolution rules (⭐ the exact order the
    compiler tries: exact → widening → boxing → varargs, with the ambiguity
    traps), return, the `void`, method resolution at compile time vs runtime.
  · ⭐⭐ PASS BY VALUE — the most-asked Java question. Prove it with four
    programs: a primitive, an object reference, a reference reassigned inside
    the method, and a swap that fails. Then explain why "Java is pass by
    reference for objects" is wrong and what the correct sentence is.
  · String: immutability and WHY (security, hashing, the pool, thread safety),
    the String pool and `intern()`, `==` vs `.equals()` (⭐ with the compile-
    time-constant folding surprise), concatenation and the StringBuilder the
    compiler inserts, when it does NOT (loops), String vs StringBuilder vs
    StringBuffer (⭐ the honest answer: never use StringBuffer), the useful
    methods, the new ones since Java 11/12/15/20/21.
  · static: fields, methods, blocks, nested classes, imports. The
    initialisation order — ⭐ prove it with a program that prints from a
    static block, an instance block, a constructor, and a field initialiser,
    in a parent and a child.
  · JVM memory areas at beginner level: stack vs heap, what lives where, a
    diagram, and the StackOverflowError vs OutOfMemoryError distinction.
  · Command-line args, Scanner and BufferedReader for input, printf and the
    format specifiers, the console.
  · Packages, imports, the access-modifier preview, javadoc.
  · The toolchain: javac flags that matter (-Xlint:all, -Werror, -g, -d),
    java flags (--enable-preview, -Xmx, -XX:+PrintFlagsFinal), jshell as a
    learning tool ⭐, the single-file source launcher (`java Foo.java`),
    the jar tool, the module system preview pointer.
  · THEN: the four practice sets from PART 4.

FILE 02A — 02A-CASE-A-oops-complete.md
  ONE-LINE: every OOP topic in Java, completely, with 5 graduated assignments
            per topic and full solutions at the end.
  ⭐ NOTHING IS SKIPPED. This is the file I will re-read for the rest of my
  career. Cover, in this order:
  1.  Class and object — anatomy, the blueprint analogy that isn't quite
      right, instantiation, what `new` actually does (allocate → zero →
      set the header → run the constructor), reference vs object, null,
      the `this` reference, object identity vs equality.
  2.  Fields and methods — instance vs class(static) vs local, the four
      kinds of variable, default values (⭐ locals have none — the
      "variable might not have been initialised" error), shadowing,
      the `this` and `ClassName.` disambiguation.
  3.  Constructors — default (and when you DON'T get one), parameterised,
      copy (⭐ Java has no real copy constructor; you write one, and here
      is the shallow-vs-deep decision), private (⭐ the singleton and the
      static-factory reasons), `this()` chaining, `super()`, the implicit
      super call, constructor overloading, ⭐ the "do not call an
      overridable method from a constructor" rule with the proof program.
  4.  Initialisation order — the complete sequence with a proof program:
      static fields/blocks of the parent, then the child; then per-instance:
      parent field initialisers and instance blocks, parent constructor,
      child field initialisers and blocks, child constructor. ⭐ And the
      forward-reference rules that surprise everyone.
  5.  Inheritance — single, multilevel, hierarchical, and ⭐ why Java has no
      multiple inheritance of STATE (the diamond problem, drawn), and how
      interfaces with default methods reintroduce it and how Java resolves
      it (the "you must override" rule). extends, the Object root, IS-A vs
      HAS-A (⭐ with the test: "can you say X is a Y in the domain, not in
      the implementation?"), what is inherited and what isn't (private
      members, constructors, static members are hidden not overridden).
  6.  Method overriding — the rules (same signature, covariant return ⭐,
      access can widen not narrow, cannot throw a broader checked exception
      ⭐ with the exact reasoning), @Override and what it catches, hiding
      vs overriding (static methods), ⭐ the dynamic dispatch proof: which
      method runs is decided by the RUNTIME type, which overload is decided
      by the COMPILE-TIME type — with the program that mixes both and
      surprises everyone.
  7.  Overloading vs overriding — the full comparison table, resolution,
      the `null` argument ambiguity, the autoboxing-vs-widening ordering.
  8.  Polymorphism — compile-time (static) vs runtime (dynamic), upcasting
      and downcasting, ClassCastException, instanceof, ⭐ pattern matching
      for instanceof (Java 16+) and for switch (Java 21+), how the JVM
      implements it (invokevirtual / invokespecial / invokestatic /
      invokeinterface / invokedynamic — the five bytecodes and which is
      used for what), the vtable and itable conceptually, ⭐ why private,
      static and final methods are not polymorphic.
  9.  Encapsulation — the access modifier matrix (⭐⭐ the 4×4 table:
      private / package-private / protected / public × same class / same
      package / subclass in another package / everywhere else), getters and
      setters and when NOT to write them, information hiding, the
      Tell-Don't-Ask principle, the cost of leaking internals (returning a
      mutable collection or a Date — ⭐ with the defensive-copy fix).
  10. Abstraction — abstract classes and methods, when abstract beats
      interface, the abstract-class-with-only-static-methods anti-pattern.
  11. Interfaces — the full evolution (Java 8 default/static, Java 9
      private, Java 21+ nothing new but the sealed interaction), multiple
      inheritance of TYPE, the diamond resolution rules, functional
      interfaces and @FunctionalInterface, marker interfaces (Serializable,
      Cloneable — ⭐ and why both are considered mistakes, with the
      alternatives), interface constants (⛔ the constant-interface
      anti-pattern), the interface-vs-abstract-class decision table (⭐⭐
      12 rows, and the modern default answer).
  12. final — on a variable (primitive vs reference ⭐ the reference is
      final not the object), on a method, on a class, on a method
      parameter, the blank final and its initialisation rules, final and
      the JMM (⭐ final-field safe publication — this is a real
      concurrency guarantee, cross-reference 04).
  13. The Object class — every method, and how to override each correctly:
      toString (⭐ the format convention, why it matters in logs),
      equals (⭐⭐ the 5 contract rules, the Liskov/"cannot subclass and add
      a field" impossibility proof, the record alternative), hashCode
      (⭐⭐ the contract with equals, the 31 multiplier, the Objects.hash
      boxing cost, the HashMap-orphaning proof program), clone (⛔ why it
      is broken, CloneNotSupportedException, the copy-constructor and
      static-factory alternatives), getClass, wait/notify/notifyAll (the
      monitor, cross-reference 04), finalize (⛔ deprecated for removal,
      why, and what to use instead: Cleaner, try-with-resources).
  14. Immutability ⭐⭐ — the 9 rules for a truly immutable class, a full
      worked example, defensive copies on the way IN and OUT, the final
      class or private constructor decision, why immutable objects are
      automatically thread-safe and hash-safe, the builder pattern as the
      ergonomics fix, records as the language-level answer and their limits
      (⭐ a record is shallowly immutable only — the components can still
      be mutable).
  15. Composition over inheritance ⭐⭐ — the case, the real examples,
      delegation, the Decorator pattern as composition (java.io is the
      canonical example — cross-reference 03), Strategy as composition,
      when inheritance IS right (framework extension points, template
      method), aggregation vs composition vs association with UML arrows.
  16. Inner and nested classes ⭐ — member inner (the implicit
      Outer.this, the memory leak it causes with handlers and listeners,
      when it is genuinely right), static nested (⭐ the default choice,
      and why), local (rare, but the effectively-final capture rule),
      anonymous (⭐ and how a lambda differs from one — cross-reference
      04), the shadowing rules, serialisation of inner classes (⛔ don't).
  17. enum ⭐⭐ — the full power: constants with fields and constructors,
      constant-specific bodies (abstract methods per constant ⭐ the
      strategy pattern without a map), values()/valueOf() and their costs,
      EnumMap (the array internals) and EnumSet (the bit vector — ⭐ why
      they are absurdly fast), Comparable by declaration order, switch
      exhaustiveness, ⭐ the enum singleton (why it beats every other
      approach — reflection-proof and serialisation-proof), the
      enum-as-state-machine pattern.
  18. record ⭐⭐ — the canonical constructor, the compact constructor
      (validation and normalisation), the auto-generated members, the
      restrictions (implicitly final, no field declarations, cannot extend
      a class, can implement interfaces), local records ⭐ (the killer use
      case: tuple returns and stream pipelines), records and pattern
      matching (deconstruction patterns, Java 21+), sealed records as
      algebraic data types ⭐⭐⭐ (with a worked Either/Result example),
      records vs Lombok @Value, when NOT to use a record (JPA entities —
      ⭐ the reason is Hibernate needs a no-arg constructor and mutable
      fields).
  19. sealed classes and interfaces ⭐⭐ — sealed/permits/non-sealed, the
      same-module-or-package rule, exhaustiveness in switch without a
      default ⭐⭐ (and why omitting `default` is the point), the
      modelling power: a closed hierarchy the compiler can reason about,
      the ADT pattern with records, the comparison with enums and with
      visitor.
  20. Annotations — the built-ins (@Override, @Deprecated with since/forRemoval,
      @SuppressWarnings and its valid values, @FunctionalInterface,
      @SafeVarargs), the meta-annotations (@Retention and the three
      policies, @Target, @Documented, @Inherited and its surprise,
      @Repeatable), writing a custom annotation, reading one with
      reflection, ⭐ how frameworks use them (Spring, JPA, JUnit) and the
      compile-time alternative (annotation processors — Lombok, MapStruct).
  21. Exceptions in the OOP context ⭐⭐ — the full hierarchy drawn,
      Error vs Exception, checked vs unchecked (⭐⭐ the real debate, what
      each camp argues, and the modern consensus: unchecked by default,
      with the reasoning), throws vs throw, the checked-exception problems
      (the interface evolution problem, the lambda problem, the
      try/catch-everything boilerplate), custom exceptions (the base
      exception, the error-code carrying exception, checked vs unchecked
      choice), try-with-resources ⭐⭐ (the AutoCloseable contract, the
      suppressed-exception mechanism and how to read a stack trace with
      "Suppressed:", the effectively-final requirement, multiple
      resources and close order), multi-catch and the precise rethrow,
      finally ⭐ (and the three traps: a return in finally swallowing an
      exception, an exception in finally masking one, closing a null
      resource), exception propagation and the stack trace anatomy,
      wrapping vs rethrowing (⭐ and preserving the cause), the try/catch
      performance myth, ⛔ catching Throwable, ⛔ empty catch blocks,
      ⛔ using exceptions for control flow, and the fail-fast principle.
  22. The four pillars summary — one page, one table, the interview answer.
  ⭐ 5 ASSIGNMENTS PER TOPIC for topics 1–21 (PART 4A), solutions at the end.
  ⭐ THEN the four practice sets.
  ⭐ This file will be very long. That is correct. Split into 02A-1 / 02A-2
     only if you exceed ~8,000 lines, and say so.

FILE 02B — 02B-CASE-B-lld-for-sde3.md
  ONE-LINE: Low-Level Design for the SDE 3 interview — SOLID, every design
            pattern, UML, and 25 fully worked MAANG design problems in Java.
  · ⭐ WHAT THE LLD ROUND ACTUALLY TESTS at MAANG. The 45-minute structure,
    what the interviewer scores you on (requirements clarity, modelling,
    extensibility, naming, trade-off articulation, code that compiles), and
    the five mistakes that cost the level.
  · The requirements-gathering framework: functional → non-functional →
    scale numbers → the API surface → the data model → the classes → the
    patterns → the extension points. With a filled-in example.
  · UML: class diagrams (all the arrows and what each MEANS — association,
    aggregation, composition, inheritance, implementation, dependency),
    sequence, state, activity, use-case. ASCII AND Mermaid. Plus "how to
    draw these on a whiteboard in 3 minutes".
  · SOLID ⭐⭐⭐ — each principle: the definition, a violating example, the
    symptom you notice in production, the fixed version, the pattern that
    implements it, and 🔑 the interview line.
      S — Single Responsibility (⭐ and the "reasons to change" framing;
          cohesion measurement; the God class)
      O — Open/Closed (⭐ the hard truth: you cannot design for every
          extension, so where do you spend it?)
      L — Liskov Substitution (⭐⭐ the formal statement, the Square/
          Rectangle violation, the equals/hashCode violation, the
          "preconditions cannot be strengthened" rule, and the design
          consequence: inheritance is for IS-A behaviour, not code reuse)
      I — Interface Segregation (the fat interface, the adapter smell)
      D — Dependency Inversion (⭐⭐ the most misunderstood: it is NOT
          "use interfaces", it is "high-level policy must not depend on
          low-level detail; both depend on abstraction", and it is what
          makes DI possible — cross-reference Spring)
  · The other principles that come up: DRY (⭐ and its limit — duplicated
      code is cheaper than the wrong abstraction), KISS, YAGNI, the Law of
      Demeter (⭐ the train wreck, and the honest counter-argument),
      Tell-Don't-Ask, Composition over Inheritance, Separation of Concerns,
      cohesion (the 6 types) and coupling (the 8 types, ranked worst to
      best — ⭐⭐ content/common coupling at the bottom, data coupling at
      the top), the Principle of Least Astonishment, Fail Fast, the
      Boy Scout Rule.
  · ⭐⭐⭐ ALL 23 GoF PATTERNS. For EACH: intent, the problem, the UML, the
    minimal complete Java code with comments, a REAL example from the JDK
    or Spring (⭐ with the actual class name), when NOT to use it, the
    modern alternative (lambdas/streams/records often replace a pattern),
    and the interview trap.
      Creational (5): Singleton (⭐⭐ all 6 implementations — eager, lazy,
        synchronized, ⭐ double-checked locking with volatile and WHY
        volatile is required, static holder/Bill Pugh ⭐ the best one,
        enum ⭐ the reflection-proof one — plus how reflection and
        serialisation break the others and the fixes), Factory Method,
        Abstract Factory, Builder (⭐ the telescoping-constructor problem,
        the fluent builder, the immutable build(), the Lombok/record
        alternatives, the director), Prototype (⭐ and why clone() is a
        trap; the copy-constructor version).
      Structural (7): Adapter (⭐ the JDK example: Arrays.asList, the
        InputStreamReader; the interface adapter), Bridge, Composite
        (⭐ the file system, the UI tree, the expression tree), Decorator
        (⭐⭐ java.io — BufferedInputStream(new FileInputStream(...)) is
        the canonical example; the Wrapper class explosion problem),
        Facade (⭐ the SLF4J facade; the service layer as a facade),
        Flyweight (⭐ Integer.valueOf's cache, String pool, the game
        example), Proxy (⭐⭐ the JDK dynamic proxy, Spring AOP, the
        lazy-loading Hibernate proxy, the remote proxy, the protection
        proxy — this pattern carries three later folders).
      Behavioural (11): Chain of Responsibility (⭐ Servlet filters,
        Spring Security's filter chain, Netty pipelines), Command (⭐
        the undo stack, Runnable as a command, the transaction script),
        Interpreter, Iterator (⭐ java.util.Iterator, the fail-fast
        mechanism, the Spliterator), Mediator (⭐ the message broker, the
        controller in MVC), Memento (⭐ the undo/redo, the snapshot,
        serialisation as memento), Observer (⭐⭐ java.util.Observable
        is dead; the PropertyChangeListener, the event bus, the reactive
        stream, and how the Observer pattern became an entire paradigm),
        State (⭐⭐ the order-state machine, the enum-with-abstract-
        methods implementation, the State pattern vs the switch — and
        how sealed types + pattern matching changed the answer), Strategy
        (⭐⭐ lambdas replaced the class hierarchy; the payment gateway,
        the sort comparator, the eviction policy), Template Method
        (⭐ AbstractList, JdbcTemplate — the name is literal), Visitor
        (⭐⭐ the double dispatch, the expression-tree example, why it
        breaks the Open/Closed principle, and how sealed types + pattern
        matching made it mostly obsolete — ⭐⭐⭐ that is a staff-level
        observation), Null Object.
  · Beyond GoF — the patterns you actually see in enterprise Java:
    Repository, DAO (⭐ DAO vs Repository vs DTO vs VO vs Entity vs POJO vs
    JavaBean — the exact distinctions, with a table), Service Layer,
    Dependency Injection / IoC (⭐ constructor vs field vs setter, and the
    four reasons constructor wins), Service Locator (⛔ and why), Provider,
    Unit of Work, Identity Map, Lazy Load, Specification, CQRS (conceptual),
    Event Sourcing (conceptual), Saga (conceptual), Circuit Breaker, Retry
    with backoff, Bulkhead, Rate Limiter (⭐⭐ token bucket, leaky bucket,
    sliding window — all three implemented), Object Pool, Double-Buffering,
    Producer-Consumer, Blackboard, Hexagonal / Ports-and-Adapters ⭐⭐,
    Clean Architecture ⭐⭐ (the dependency rule, drawn), Onion, Layered
    (⭐ and its limits), Feature-Sliced.
  · ⭐⭐⭐ 25 FULLY WORKED LLD PROBLEMS at SDE 3 depth. For EACH: the prompt
    as an interviewer would give it, my clarifying questions, the functional
    and non-functional requirements, the scale numbers, the UML, the complete
    compilable Java code with comments, the design decisions with the
    alternatives I rejected and why, the thread-safety analysis, the
    extension points, and "what the interviewer will push back on and the
    answer".
      1 Parking Lot · 2 BookMyShow / ticket booking · 3 Elevator system
      4 Snake & Ladder · 5 Deck of cards / Blackjack · 6 Chess
      7 Library management · 8 ATM · 9 Vending machine · 10 Coffee machine
      11 ⭐ Cache with pluggable eviction (LRU + LFU, generics, thread-safe)
      12 ⭐ Rate limiter (three algorithms) · 13 Splitwise
      14 Ride sharing (Uber) · 15 Food delivery (Swiggy)
      16 Notification service (multi-channel, retry, dedup)
      17 Task scheduler (cron-like, thread pool, cancellation)
      18 Online shopping (Amazon: catalogue, cart, order, inventory)
      19 Movie ticket booking · 20 Music streaming (playlist, queue, shuffle)
      21 Tic-tac-toe with a minimax AI · 22 Inventory management
      23 ⭐ Double-entry digital wallet / ledger (the money-correctness one)
      24 URL shortener (LLD flavour) · 25 Hotel management
  · ⭐ Thread-safe LLD — the round where they ask "now make it concurrent".
    The thread-safe singleton, the concurrent cache, the producer-consumer,
    the thread-safe rate limiter, and the vocabulary: which lock, why, what
    the contention profile is.
  · Designing for testability — seams, dependency injection as a testing
    tool, what makes a class hard to test and what that says about the design.
  · The naming discipline — ⭐ SDE 3 candidates are judged on names. The
    rules, the anti-patterns (Manager, Handler, Util, Processor, Impl), and
    how to name a class so the responsibility is obvious.
  · THEN the four practice sets, plus a set of 10 "design this in 20 minutes"
    speed drills with the model answer structure.

FILE 03 — 03-FILE-HANDLING-AND-IO.md
  ONE-LINE: every way Java touches bytes and files — java.io, NIO, NIO.2,
            serialisation, encodings, and the large-file questions.
  · The three APIs and when each is right: java.io (streams, the classic),
    java.nio (buffers/channels/selectors, the non-blocking one),
    java.nio.file (NIO.2, the modern file API). ⭐ Decision table.
  · ⭐⭐ THE DECORATOR PATTERN IS java.io. Draw the hierarchy. Show that
    `new BufferedReader(new InputStreamReader(new FileInputStream(f), UTF_8))`
    is four decorators on a base stream, and that this is the single best
    real-world pattern example in the JDK. Cross-reference 02B.
  · Byte streams vs character streams — the encoding boundary, and why mixing
    them is the source of every mojibake bug.
  · The class map: InputStream/OutputStream/Reader/Writer and every important
    subclass, with the one-line purpose of each.
  · Reading and writing — every idiom: read(), read(byte[]), readAllBytes,
    readLine (⭐ BufferedReader only), readAllLines, transferTo, lines(),
    the Scanner (⭐ and why it's slow and for teaching only), the char-by-char
    loop, the buffered loop, and the performance comparison with numbers.
  · try-with-resources ⭐⭐ — the mechanics, the close order (reverse of
    declaration), the suppressed exception mechanism, reading a stack trace
    with "Suppressed:", and what happens if close() throws.
  · Character encodings ⭐⭐ — ASCII/Unicode/UTF-8/UTF-16/UTF-32, the byte
    layouts, Charset, the default-charset trap, ⭐ Java 18 made UTF-8 the
    default (JEP 400) and what that broke, the BOM, why
    `new String(bytes)` without a charset is a bug, the CharsetEncoder/Decoder
    and malformed-input handling.
  · Serialisation ⭐⭐ — Serializable, the mechanism, serialVersionUID (⭐
    what happens when it changes and when it's auto-generated), transient,
    static is not serialised, the object graph and reference preservation,
    the readObject/writeObject hooks, readResolve (⭐ the singleton defence),
    readObjectNoData, Externalizable (⭐ and why it's usually worse),
    ⛔⛔ THE SECURITY PROBLEM: Java deserialisation is a remote-code-execution
    vector; the gadget chain, the ysoserial toolkit, the real CVEs, the
    ObjectInputFilter defence (JEP 290), and ⭐ what to use instead: JSON
    (Jackson), Protobuf, Avro. This is an SDE 3 conversation.
  · RandomAccessFile — the seek/getFilePointer, the modes, the record-based
    access pattern.
  · java.nio — Buffer (capacity/limit/position/mark, flip/clear/rewind/compact
    ⭐ with diagrams), Channel (FileChannel, SocketChannel, the gather/scatter
    I/O), Selector and the Reactor pattern ⭐⭐ (this is Netty's foundation),
    direct vs heap buffers (⭐ the allocation cost, the zero-copy win, the
    OutOfMemoryError: Direct buffer memory), memory-mapped files (⭐
    FileChannel.map, when it wins, the unmap problem), FileLock.
  · java.nio.file (NIO.2) ⭐ — Path/Paths/Path.of, the resolve/relativize/
    normalize semantics, Files (every useful method: read/write/copy/move/
    delete/exists/isReadable/createFile/createDirectories/createTempFile/
    newBufferedReader/newInputStream/lines/walk/find/newDirectoryStream/
    walkFileTree/getAttribute/setAttribute/getPosixFilePermissions),
    the WatchService (⭐ and its platform-dependent latency), the
    SimpleFileVisitor, the atomic move (ATOMIC_MOVE) and why it matters for
    config reloads, the StandardCopyOption/StandardOpenOption enums, the
    symbolic-link handling, the temp-file security (⭐ TOCTOU).
  · The File vs Path migration table.
  · Working with real formats: properties (Properties + load/store + the
    ordering surprise), CSV (the parsing pitfalls — quoted fields, embedded
    commas, newlines), JSON with Jackson (⭐ the ObjectMapper, the
    annotations, the tree vs databind vs streaming APIs, the performance
    difference), XML (DOM vs SAX vs StAX ⭐ the three models), YAML.
  · ⭐⭐ LARGE FILES — the SDE 3 question set: "read a 10 GB file with 1 GB
    of heap" (streaming, never readAllLines), "count the words in a 100 GB
    file" (external sort, MapReduce), "find duplicates across a TB" (hashing,
    Bloom filters), "tail a growing log" (the WatchService + position
    tracking), the memory-mapped approach and its limits, the chunked
    processing pattern with numbers.
  · Performance ⭐ — the buffering benchmark (unbuffered vs 8 KB vs 64 KB vs
    1 MB, with real numbers), why BufferedWriter matters, the FileChannel.
    transferTo zero-copy, the sendfile syscall, the page cache and why your
    Java benchmark is measuring the OS.
  · Exception handling in I/O — the IOException hierarchy,
    FileNotFoundException vs NoSuchFileException ⭐ (one is java.io, one is
    nio, and they are NOT related), the FileNotFoundException-on-a-directory
    surprise, AccessDeniedException, the retry-and-backoff discipline.
  · 10 REAL PROGRAMS, fully commented: a log rotator, a directory tree
    printer (recursive + Files.walk), a duplicate-file finder (size-then-hash),
    a CSV→JDBC loader, a `tail -f` in Java, a file watcher that reacts to
    config changes, a word counter with the external-sort approach, a
    Markdown→HTML converter, a secure temp-file utility, an LRU disk cache.
  · THEN the four practice sets.

FILE 04 — 04-ADVANCED-CORE-JAVA.md
  ONE-LINE: the SDE 3 differentiators — concurrency, the memory model,
            generics, reflection, streams and lambdas, and JVM internals.
  ⭐⭐ THIS IS THE FILE THAT GETS THE LEVEL. Budget the most depth here.
  A. CONCURRENCY AND MULTITHREADING ⭐⭐⭐
     · Why concurrency, and the three reasons (throughput, responsiveness,
       modelling). The cost: complexity, and every bug class that follows.
     · Process vs thread, the OS view, the JVM view, the thread's memory
       (stack per thread, shared heap).
     · Creating threads: Thread subclass ⛔, Runnable ✅, Callable + Future,
       CompletableFuture ⭐, the ExecutorService ✅✅, virtual threads ⭐⭐⭐.
       The comparison table and why the answer changed in Java 21.
     · The Thread lifecycle ⭐ — NEW/RUNNABLE/BLOCKED/WAITING/TIMED_WAITING/
       TERMINATED with the transition diagram and the exact trigger for each.
       ⭐ RUNNABLE includes "waiting for the OS scheduler" — everyone gets
       this wrong.
     · start() vs run() (⭐ calling run() is just a method call — no thread).
     · Daemon threads, priority (⭐ mostly a lie), join (and its overloads),
       sleep vs wait ⭐⭐ (the 5-row table: monitor released? called on?
       wakes how? interruptible?), yield (⭐ a hint, ignore it),
       setUncaughtExceptionHandler ⭐ (and the default handler, and why
       your thread dying silently is the worst failure mode).
     · ⭐⭐ INTERRUPTION DONE RIGHT. The cooperative model, isInterrupted vs
       Thread.interrupted() (⭐ one clears the flag), InterruptedException
       and the two correct responses (propagate, or restore the flag and
       exit), ⛔ never swallow it, the interruptible vs non-interruptible
       operations, how to interrupt a thread blocked on I/O (you mostly
       can't — close the channel), and how to interrupt a virtual thread.
     · synchronized ⭐⭐ — on an instance method (locks `this`), on a static
       method (locks the Class object ⭐ the classic "two locks, no mutual
       exclusion" bug), on a block (locks whatever you name — and why
       `synchronized(this)` in a library is a leak), the monitor, reentrancy,
       the bytecode (monitorenter/monitorexit, and the exception-table
       guarantee), the lock states in the mark word ⭐⭐⭐ (biased → thin →
       fat, and biased locking's removal in Java 15+), what synchronized
       costs and when the JIT elides it (escape analysis + lock elision).
     · ⭐⭐⭐ THE JAVA MEMORY MODEL. This is the staff-level topic.
       - The problem: visibility, atomicity, ordering. With the counter
         program that never terminates, and the one that prints a half-
         constructed object.
       - happens-before ⭐⭐ the rule set, verbatim, with an example each:
         program order, monitor lock, volatile, thread start, thread join,
         interruption, final fields, transitivity.
       - volatile ⭐⭐⭐ what it guarantees (visibility + ordering, NOT
         atomicity), the memory-barrier implementation, the classic
         `volatile boolean running` flag, why `volatile int i; i++` is still
         broken, the double-checked locking proof (⭐⭐ why it fails without
         volatile — instruction reordering can expose a non-null reference to
         a half-constructed object), and the static-holder alternative that
         avoids the question entirely.
       - final fields and safe publication ⭐⭐ (JLS 17.5 — the guarantee
         that makes immutable objects safe to share without synchronisation).
       - The publication patterns: unsafe, race-free via synchronisation,
         immutable-object, effectively-immutable with volatile, thread-confined.
       - False sharing ⭐⭐ (the cache-line mechanism, the benchmark showing
         a 10× difference, @Contended, the padding trick).
       - ⛔ The data races you can still write after reading all this — the
         check-then-act, the read-modify-write, the compound invariant.
     · wait/notify/notifyAll ⭐⭐ — the mechanics, WHY it must be in a loop
       (spurious wakeups AND the lost-wakeup problem AND the multi-condition
       problem — three separate reasons), notifyAll vs notify (⭐ notify is
       a liveness bug waiting to happen), the bounded-buffer implementation
       from scratch, IllegalMonitorStateException.
     · java.util.concurrent ⭐⭐⭐
       - Executor/ExecutorService/ThreadPoolExecutor/ScheduledExecutorService
       - ⭐⭐ WHY Executors.newFixedThreadPool IS BANNED at serious shops:
         it uses an unbounded LinkedBlockingQueue, so a slow consumer grows
         the queue until OOM. Build a ThreadPoolExecutor yourself.
       - The 7 ThreadPoolExecutor constructor parameters, each explained,
         with the sizing decision for each.
       - ⭐⭐⭐ THE EXECUTION ALGORITHM: core threads → queue → max threads
         → rejection. Everyone gets the order wrong: the queue fills BEFORE
         the pool grows past core. Diagram it.
       - The 4 rejection policies + writing your own.
       - Pool sizing: CPU-bound (N+1), IO-bound (the formula, and why it
         needs measurement), ⭐ Little's Law, and the honest answer: measure.
       - ⭐⭐⭐ ThreadPoolExecutor INTERNALS: the single AtomicInteger `ctl`
         packing runState in the high 3 bits and workerCount in the low 29,
         the CAS transitions, the Worker class extending
         AbstractQueuedSynchronizer, why a Worker locks itself during task
         execution (so interruptIdleWorkers can tell idle from busy). This
         is a genuine staff-level flex and it's real.
       - Future (⭐ the get() blocking, the cancellation semantics, isDone
         vs isCancelled), CompletableFuture ⭐⭐⭐ (the full combinator set:
         thenApply/thenAccept/thenCompose/thenCombine, the Async variants and
         which executor they use ⭐ the default is the common ForkJoinPool
         and that is a problem, allOf/anyOf, exceptionally/handle/whenComplete
         and the difference, the timeout methods since Java 9, ⛔ the
         silent-exception-swallowing trap).
       - ForkJoinPool ⭐⭐ (divide and conquer, work stealing, the deque per
         worker, RecursiveTask/RecursiveAction, the join threshold, ⭐⭐ why
         BLOCKING inside the common pool is a disaster and how to see it,
         ManagedBlocker, the parallelStream connection).
       - The synchronisers ⭐⭐: ReentrantLock (vs synchronized — the 8
         differences in a table: interruptible, timed tryLock, fairness,
         multiple Conditions, ⛔ must unlock in finally), ReadWriteLock (and
         the writer-starvation and lock-downgrading subtleties), StampedLock
         (⭐ optimistic reads, and why it's not reentrant and not
         interruptible), Condition (the await/signal, the multiple-condition
         win over notifyAll), Semaphore (the permit model, the rate-limiting
         use), CountDownLatch (one-shot, the await-with-timeout),
         CyclicBarrier (reusable, the barrier action, the broken state),
         Phaser (⭐ the multi-phase barrier, when it's worth it), Exchanger.
       - Atomics ⭐⭐⭐: the CAS operation, Atomic* classes, the ABA problem
         (⭐ and AtomicStampedReference), the VarHandle (the modern
         replacement for Unsafe, the access modes: plain/opaque/
         release-acquire/volatile), ⭐⭐ LongAdder and LongAccumulator and
         WHY they beat AtomicLong under contention (the cell striping, the
         contention-based expansion, the sum() that is not atomic — and when
         that's acceptable).
     · ⭐⭐⭐ VIRTUAL THREADS (Project Loom) — the 2026 answer to "how do you
       scale a Java service".
       - The problem they solve: thread-per-request doesn't scale because
         platform threads are 1 MB of stack and an OS resource.
       - What they are: a JVM-scheduled thread multiplexed onto carrier
         platform threads, with a growable segmented stack on the heap.
       - Continuations: the freeze/thaw mechanism, drawn.
       - The API: Thread.ofVirtual(), Executors.newVirtualThreadPerTaskExecutor(),
         the ThreadFactory, the structured-task scope.
       - ⭐⭐ PINNING: synchronized blocks (⭐ and the fix — use ReentrantLock,
         or Java 24's JEP 491 which fixed it) and native frames/JNI. How to
         detect it (-Djdk.tracePinnedThreads, JFR events).
       - ⭐⭐ WHAT THEY DON'T DO: they do not make CPU-bound work faster.
         They do not remove the need for a bounded resource pool — you still
         need a Semaphore to limit DB connections. Pooling virtual threads is
         an anti-pattern.
       - ThreadLocal: works but is expensive at a million threads; ScopedValue
         (⭐ preview → final) is the replacement.
       - Structured Concurrency (⭐ preview): StructuredTaskScope, the
         ShutdownOnFailure/ShutdownOnSuccess policies, why it fixes the
         thread-leak and cancellation problems.
       - The migration story: what changes in a Spring Boot app (very little),
         what breaks (ThreadLocal-heavy code, synchronized-heavy code, code
         that assumes a bounded thread pool).
       - 🔑 The interview answer: "virtual threads vs reactive" — ⭐⭐ they
         solve the same scaling problem with opposite programming models.
         Virtual threads keep the blocking style and make blocking cheap;
         reactive keeps the cheap resource use and forces a non-blocking
         style. In 2026, virtual threads win for most services because the
         code stays readable and the stack traces stay useful. Reactive wins
         when you genuinely need backpressure and stream composition.
     · Concurrent collections (the deep dive lives in FILE 06 — cross-ref).
     · The classic concurrency programs, all implemented and commented:
       producer-consumer (3 ways: wait/notify, BlockingQueue, Semaphore),
       the dining philosophers (and the deadlock, and the four fixes),
       a thread-safe bounded buffer, a read-write cache, a blocking queue
       implemented from scratch, a parallel merge sort, a rate limiter.
     · ⭐⭐ DEADLOCK, LIVELOCK, STARVATION — the definitions, the four
       Coffman conditions, how to detect a deadlock (jstack output, read it
       line by line; ThreadMXBean.findDeadlockedThreads), the prevention
       strategies (lock ordering ⭐ with a comparable-key ordering trick,
       tryLock with timeout, avoiding nested locks), and the honest truth:
       most production "deadlocks" are actually starvation or a leaked lock.
  B. GENERICS ⭐⭐
     · Why generics exist (the pre-generics List of Object, the cast, the
       ClassCastException at the wrong place and time).
     · Type parameters, the naming convention, generic classes/methods/
       interfaces, the diamond, multi-bound (`<T extends A & B>`).
     · ⭐⭐⭐ TYPE ERASURE — what it actually erases, and the SEVEN
       consequences: no `new T()`, no `T.class`, no `instanceof List<String>`,
       no generic arrays (`new T[]`), no static type parameters, overloads
       that clash after erasure, and the bridge methods the compiler inserts.
       Each with the workaround.
     · Reifiable vs non-reifiable types, the raw type (⭐ what it actually
       does to checking — it disables generics for the whole expression).
     · ⭐⭐⭐ BOUNDED WILDCARDS AND PECS. `List<? extends T>` (producer — you
       can read T, you cannot write), `List<? super T>` (consumer — you can
       write T, you read Object), the mnemonic, the PROOF programs, the
       capture conversion, why `List<String>` is not a `List<Object>` (the
       soundness proof), why arrays ARE covariant and why that is unsound
       (⭐ the ArrayStoreException — arrays are covariant AND reified, which
       is exactly the combination generics avoided).
     · The `Collections.copy(List<? super T>, List<? extends T>)` signature
       read out loud — ⭐ the canonical PECS example, and why it's right.
     · Generic methods and the inference algorithm, the target typing,
       the explicit witness `Collections.<String>emptyList()`.
     · Heap pollution, @SafeVarargs ⭐ (what it promises and when that
       promise is a lie — the varargs-array-is-reified problem).
     · Type tokens ⭐ (the `Class<T>` pattern, the super-type-token trick
       with an anonymous subclass, how Jackson's TypeReference works).
     · Generics and the JVM: the erasure means one class file, and the
       performance implication (no per-instantiation cost, but bridge
       methods and boxing).
  C. REFLECTION, DYNAMIC PROXIES, METHOD HANDLES ⭐⭐
     · Class objects, the three ways to get one, `Class<?>` vs `Class<T>`.
     · The API: getDeclaredConstructors/Methods/Fields vs the non-Declared
       versions (⭐ the difference matters), setAccessible(true) and ⭐⭐ the
       module system's fight with it (InaccessibleObjectException, --add-opens,
       why frameworks need it and why that's a smell).
     · Creating instances, reading/writing private fields, invoking private
       methods — and the legitimate uses (frameworks, mappers, test tools) vs
       the anti-pattern (breaking encapsulation in your own code).
     · The COST ⭐ — reflection was slow; since Java 7 it's mostly the
       access check and the boxing. Numbers, and the inflation threshold
       where the JVM generates a bytecode accessor.
     · ⭐⭐⭐ DYNAMIC PROXIES — InvocationHandler, Proxy.newProxyInstance,
       the generated $Proxy0 class, the constraints (interfaces only), and
       WHAT THIS POWERS: Spring AOP, Spring Data JPA repositories, MyBatis
       mappers, Mockito mocks, the @Transactional proxy. Show a 40-line
       program that implements a mini-Spring: an interface, a proxy that logs
       and times every call. ⭐ This single concept explains three folders.
     · CGLIB/ByteBuddy subclass proxies — the alternative for classes, the
       final-method limitation, why Spring picks one or the other.
     · MethodHandle and VarHandle ⭐ — invokedynamic, the constant vs
       variable handle, the performance vs reflection (⭐ the honest answer:
       it's about constant-folding at the call site, not raw speed),
       LambdaMetafactory (cross-ref to lambdas).
     · The class loading deep dive ⭐⭐⭐ — load → link (verify → prepare →
       resolve) → initialise, the three built-in classloaders (bootstrap/
       platform/application) and the delegation model, WHY delegation is
       parent-first (security: you cannot replace java.lang.String), how to
       break it (Tomcat's webapp classloader is child-first — ⭐ and why),
       writing a custom classloader, the Class.forName vs
       ClassLoader.loadClass difference (initialisation!), the classloader
       leak ⭐⭐⭐ (the ThreadLocal + pool + webapp redeploy mechanism that
       causes PermGen/Metaspace OOM — this is a real production incident).
  D. LAMBDAS, FUNCTIONAL INTERFACES, STREAMS ⭐⭐⭐
     · The lambda syntax, the target type, the functional interface, the
       four forms, the effectively-final capture rule (⭐ and WHY — the
       capture is a copy, so mutation would be invisible).
     · ⭐⭐⭐ WHAT A LAMBDA ACTUALLY COMPILES TO — invokedynamic +
       LambdaMetafactory, NOT an anonymous class. The consequences: no extra
       .class file per lambda, the instance is created at first call and
       possibly cached, ⭐ `this` inside a lambda is the enclosing instance
       (unlike an anonymous class, where it's the anonymous object). Proof
       program for both.
     · Lambda vs anonymous class — the full table (this, memory, class file,
       performance, statefulness).
     · java.util.function ⭐ — all 43 interfaces, grouped and tabulated:
       the 6 base shapes (Function/Predicate/Consumer/Supplier/UnaryOperator/
       BinaryOperator) × the primitive specialisations (Int/Long/Double) ×
       the Bi- variants, plus Runnable/Callable and why they're not in the
       package. ⭐ Why the primitive specialisations exist (boxing).
     · Method references — the 4 kinds (static, bound instance, unbound
       instance, constructor, plus the array constructor), when each applies,
       and ⭐ the unbound-instance one (`String::length`) which confuses
       everyone.
     · Default methods ⭐⭐ — the motivation (interface evolution, the
       Collection.stream() problem), the resolution rules (class wins →
       most specific interface wins → you must override), the diamond problem
       and the compile error it produces.
     · ⭐⭐⭐ STREAM INTERNALS — the pipeline: source → intermediate (lazy)
       → terminal (triggers). The Spliterator (characteristics, tryAdvance,
       trySplit, estimateSize) and how it drives both sequential and parallel.
       The stage chain and the Sink. WHY laziness matters (short-circuiting,
       infinite streams, fusion of operations into one pass). The
       short-circuiting operations. The stateful operations and why sorted/
       distinct/limit are expensive. The encounter order and whether the
       source preserves it.
     · Stream operations, complete: every intermediate (map/flatMap/filter/
       peek⭐the-debugging-tool-not-a-feature/takeWhile/dropWhile/sorted/
       distinct/limit/skip/mapMulti) and every terminal (forEach/forEachOrdered/
       toArray/reduce⭐the-three-forms/collect/min/max/count/anyMatch/allMatch/
       noneMatch/findFirst/findAny/iterator), each with complexity, laziness,
       statefulness, and ordering behaviour in a table.
     · flatMap ⭐⭐ — the three uses (flatten nested collections, the
       Optional/Stream interop, the cross product), and the "one to many"
       mental model.
     · reduce ⭐⭐ — the identity/accumulator/combiner contract, why the
       identity must be an identity for the accumulator (⭐ the parallel
       bug when it isn't), the three overloads, and when collect is the
       better tool.
     · Collectors ⭐⭐⭐ — toList/toUnmodifiableList/toSet/toMap ⭐ (and the
       duplicate-key IllegalStateException, and the merge function that fixes
       it, and the null-value NPE that doesn't), groupingBy (the three
       overloads, the downstream collector, the classification function),
       partitioningBy (⭐ and why it's better than two filters), counting/
       summing/averaging/mapping/flatMapping/reducing/collectingAndThen/
       teeing ⭐/joining, toConcurrentMap, the Collector interface and
       writing a custom one (characteristics: CONCURRENT/UNORDERED/IDENTITY_FINISH).
     · ⭐⭐ PARALLEL STREAMS — the common ForkJoinPool (⭐⭐ ONE pool for the
       whole JVM, and what happens when you block in it), when parallel wins
       (large N, CPU-bound, splittable source, no shared state) and when it
       loses (small N, IO-bound, LinkedList/iterate/limit, boxing, side
       effects), the benchmark with real numbers, the custom-pool trick and
       ⭐ why it doesn't reliably work, the ordering guarantees, the
       thread-safety requirements, and 🔑 the honest answer: "almost never,
       and measure when you think you need it".
     · Optional ⭐⭐ — what it's for (a return type that says "maybe none"),
       ⛔ the four misuses (a field, a method parameter, a collection
       element, a nullable replacement everywhere), the methods
       (map/flatMap/filter/or/ifPresent/ifPresentOrElse/orElse/orElseGet ⭐
       the difference/orElseThrow/stream/isEmpty), the orElse-vs-orElseGet
       evaluation trap, and 🔑 the "should I use Optional at all" debate.
     · The Stream anti-patterns ⭐ — the side effect in a forEach, the
       stateful lambda, the nested streams that should be a flatMap, the
       stream that should be a loop (⭐ and the readability argument, which
       is legitimate).
     · java.time ⭐⭐ — why java.util.Date/Calendar are broken (mutable,
       not thread-safe, month 0-indexed, the timezone confusion), the
       model (Instant/LocalDate/LocalTime/LocalDateTime/OffsetDateTime/
       ZonedDateTime/Duration/Period/ZoneId/ZoneOffset), the immutability,
       the TemporalAdjusters, formatting/parsing (DateTimeFormatter, the
       thread-safety vs SimpleDateFormat ⭐), the timezone rules and DST
       (⭐ the "never store local time for an event" rule), the JDBC mapping.
     · The HTTP Client (java.net.http) ⭐ — the synchronous and async
       (CompletableFuture) APIs, the request builder, the BodyHandlers,
       HTTP/2 and the version negotiation, timeouts, the redirect policy,
       ⭐ and why it replaced HttpURLConnection and most third-party clients.
  E. JVM INTERNALS AND PERFORMANCE ⭐⭐⭐ (the staff-level section)
     · The runtime data areas, drawn precisely: the heap (generations,
       Eden/Survivor/Old, the TLABs ⭐ and why they exist), the stacks (per
       thread, frames, the operand stack, the local variable array), the
       metaspace (⭐ native memory, not heap; what replaced PermGen and why),
       the PC register, the native method stacks, the code cache.
     · Object layout ⭐⭐ — the mark word (64 bits, and what's in it in each
       lock state), the klass pointer, ⭐ compressed oops and the 32 GB
       boundary (why a 31 GB heap is faster than a 33 GB heap — a genuinely
       impressive interview fact), field ordering and padding, the alignment
       to 8 bytes, the array layout, the size of an Object (16 bytes), the
       size of an Integer (16), the size of a HashMap.Entry (~32-48) — ⭐
       cross-reference FILE 06 for the collection memory maths.
     · The JIT ⭐⭐ — interpretation first, the tiered compilation levels
       (0 interpreter, 1-3 C1 with profiling, 4 C2), the invocation and
       backedge counters, the compile thresholds, Graal, the AOT options
       (CDS/AppCDS ⭐, Leyden, CRaC ⭐⭐ the checkpoint-restore that fixes
       JVM startup for serverless), ⭐ WARM-UP and why your benchmark and
       your load test both lie if you skip it.
     · The optimisations ⭐⭐ — inlining (and the 325-byte threshold, and why
       small methods are fast), escape analysis (scalar replacement, stack
       allocation, ⭐ lock elision — the reason `new StringBuffer` in a
       method is nearly free), dead code elimination, constant folding,
       deoptimisation (⭐ the triggers: a new subclass appears, an
       uncommon trap fires; and how to see it with -XX:+PrintCompilation),
       profile-guided speculation and the monomorphic/bimorphic/megamorphic
       call sites ⭐⭐⭐ (why a hot interface with 3 implementations is
       slower than one with 1, and what that means for plugin architectures).
     · ⭐⭐⭐ GARBAGE COLLECTION.
       - The algorithm: reachability from GC roots (⭐ enumerate the roots:
         stack locals, static fields, JNI references, held locks, the
         constant pool), NOT reference counting (⭐ and the cycle problem
         that kills refcounting).
       - Generational hypothesis, the minor/major/full distinction, the
         promotion, the survivor spaces and the tenuring threshold, the
         write barrier and the card table ⭐⭐ (how the young GC finds old→
         young references without scanning the old gen — a real staff-level
         detail).
       - The collectors, each with: algorithm, pause characteristics, heap
         size sweet spot, throughput vs latency, the flags, and when to
         choose it:
           Serial, Parallel (⭐ the default for throughput),
           G1 ⭐⭐ (regions, the collection set, the SATB barrier, the pause
             target and why it's a target not a promise, humongous objects
             and the problem they cause, the mixed GC),
           ZGC ⭐⭐⭐ (coloured pointers, load barriers, sub-millisecond
             pauses, generational since Java 21, the throughput cost),
           Shenandoah (the Brooks pointer, the comparison with ZGC).
       - ⭐ How to choose: a decision tree on heap size, latency SLO,
         throughput requirement. And the honest default: G1 unless you have
         a >32 GB heap and a p99.9 latency SLO, then ZGC.
       - GC logs ⭐⭐ — the unified logging flags (-Xlog:gc*), reading a G1
         log line by line, reading a ZGC log, the GCeasy/GCeasier workflow,
         the metrics that matter (throughput %, max pause, allocation rate,
         promotion rate, the heap-after-GC trend).
       - Tuning ⭐ — the knobs that matter and the 90% that don't. -Xms=-Xmx
         (why), the metaspace sizing, the GC pause target, ⛔ don't set the
         young gen size with G1, ⛔ don't tune before you measure.
     · ⭐⭐⭐ MEMORY LEAKS IN JAVA — they exist, and here are the seven:
       1 static collections that grow · 2 unclosed resources ·
       3 ⭐ ThreadLocal in a thread pool (the exact mechanism: the
         ThreadLocalMap holds a WEAK key and a STRONG value, so when the
         ThreadLocal is collected the value is orphaned under a null key
         until the thread dies — and a pooled thread never dies) ·
       4 unregistered listeners/observers · 5 the inner class holding the
       enclosing instance · 6 classloader leaks on redeploy (⭐ cross-ref
       the classloader section) · 7 String.intern() abuse and cache without
       eviction.
       For each: the symptom, the detection, the fix, the code.
     · The tooling ⭐⭐ — jcmd (the Swiss army knife, every subcommand),
       jmap (the heap dump, the histogram), jstack (⭐ read a thread dump
       properly — the states, the lock owners, finding the deadlock),
       jstat (the GC counters, reading -gcutil), jinfo, jhsdb,
       JFR + JMC ⭐⭐⭐ (the flight recorder: how to start it, the events
       that matter, the allocation profiling, the lock profiling, the
       low-overhead claim and what it actually costs), async-profiler ⭐
       (the flame graph, the allocation and lock modes, why it beats
       sampling profilers for Java), heap dump analysis in Eclipse MAT
       (the dominator tree, the leak suspects report, the path-to-GC-roots),
       the NMT (Native Memory Tracking) for the off-heap mystery.
     · A full worked investigation ⭐⭐ — "the service's p99 doubled after 3
       days" — from the alert, through the GC log, to the heap dump, to the
       dominator tree, to the ThreadLocal in a connection pool, to the fix.
       Narrated. This is the single most valuable section in the folder for
       an SDE 3 interview.
     · Benchmarking ⭐⭐ — why your loop with System.nanoTime() is wrong,
       JMH (the annotations, the warmup/measurement iterations, the forks,
       ⭐ the Blackhole and why dead-code elimination eats your benchmark,
       the state scopes, the compiler-assisted pitfalls), the numbers that
       matter (ns/op, the allocation rate), the microbenchmark that
       misleads.
     · The flags cheat sheet — the 40 that matter, grouped, with what each
       does and its risk.
  F. MODULES, TOOLING, MODERN FEATURES
     · JPMS — module-info.java, requires/transitive/exports/opens/uses/
       provides, the three module types, the unnamed and automatic modules,
       ⭐ why most applications still don't modularise and when libraries
       should, --add-opens/--add-exports and the reflection fight, jlink ⭐
       (the custom runtime image, and the Docker image size payoff).
     · jshell as a learning and debugging tool.
     · The build tools: Maven (the POM, the lifecycle, the scopes ⭐ and the
       classpath each produces, the dependency mediation rules ⭐⭐ nearest-
       wins then declaration-order, the exclusions, the BOM, the parent,
       the profiles, the enforcer plugin) and Gradle (the build script, the
       configuration vs execution phase ⭐⭐ the thing everyone gets wrong,
       the task avoidance, the dependency configurations). Both with the
       commands that matter.
     · The feature timeline Java 8 → 25 ⭐ — a table of every notable
       feature, its version, its status (final/preview/removed), and the one
       file in this folder that covers it. Plus ⭐ the LTS lines (8, 11, 17,
       21, 25) and what production is actually running.
     · The removals and deprecations you must know: finalize, the Security
       Manager (⭐⭐ deprecated for removal, JEP 411 — and what that means
       for sandboxing), Thread.stop/suspend/resume, the applet API, the
       Nashorn engine, biased locking, the Constable/ConstantDesc oddities.
  · THEN the four practice sets — with the "what does this print?" set being
    HEAVILY concurrency-flavoured (the memory-model questions are the hardest
    and most asked).

FILE 05 — 05-JDBC-BASICS-AND-CRUD.md
  ONE-LINE: JDBC from zero — the architecture, the connection steps, and
            complete CRUD with the DAO pattern.
  · What JDBC is and isn't ⭐ (a specification; the driver is the
    implementation; the JDK ships no driver).
  · The architecture diagram ⭐ — the Application → DriverManager → Driver →
    Database, and the modern version: Application → DataSource → Pool →
    Driver → Database.
  · The interfaces: Driver, Connection, Statement, PreparedStatement,
    CallableStatement, ResultSet, ResultSetMetaData, DatabaseMetaData,
    DataSource, RowId, Blob, Clob, SQLXML, Savepoint. One line each.
  · ⭐ THE CONNECTION STEPS — the 7 steps, in order, each explained, then
    the modern version of each:
      1 Load the driver — and ⭐ why Class.forName() is no longer needed
        (JDBC 4.0 + the ServiceLoader mechanism via META-INF/services).
        Show both, explain the SPI.
      2 The URL — the anatomy `jdbc:<vendor>://<host>:<port>/<db>?<params>`,
        the params that matter per vendor (⭐ useSSL, serverTimezone,
        rewriteBatchedStatements, characterEncoding).
      3 DriverManager.getConnection vs ⭐⭐ DataSource (and why every real
        application uses a DataSource — pooling, JNDI, configuration
        externalisation).
      4 Create the Statement — and why you almost never want a plain one.
      5 Execute — execute vs executeQuery vs executeUpdate vs executeLargeUpdate,
        and what each returns.
      6 Process the ResultSet — the cursor model (⭐ it starts BEFORE the
        first row), next(), the typed getters, ⭐ getString vs getObject,
        handling NULL (⭐ wasNull() because getObject returns null AND
        getInt returns 0), the date/time mapping, reading by index vs label.
      7 Close — ⭐⭐ the ORDER matters: ResultSet → Statement → Connection,
        and why (and why try-with-resources makes this moot). And what
        "closing" a pooled connection actually does (returns it).
  · ⭐⭐⭐ Statement vs PreparedStatement vs CallableStatement.
    - SQL injection: build a VULNERABLE login, exploit it with
      `' OR '1'='1' --`, show the data exfiltration, then fix it. This is
      the demo that makes the lesson permanent.
    - ⭐ the SECOND reason PreparedStatement wins, which everyone forgets:
      the database caches the execution plan. Show the vendor's plan cache.
    - The third: type safety and the setX methods, the date handling, the
      binary data.
    - The limit: ⛔ you cannot parameterise an identifier (a table or column
      name) — and what to do instead (a whitelist).
    - CallableStatement and stored procedures — the syntax, the OUT
      parameters, and 🔑 the honest debate about stored procedures.
  · ⭐⭐⭐ CRUD, COMPLETE — for each of Create/Read/Update/Delete:
    - the plain version, then the PreparedStatement version, then the DAO
      version, then the generic DAO version.
    - CREATE: insert with parameters, ⭐ getGeneratedKeys and the
      RETURNING clause alternative, the batch insert (addBatch/executeBatch)
      and ⭐⭐ the MySQL `rewriteBatchedStatements=true` that turns 1000
      round trips into 1 (with the benchmark numbers), the upsert
      (ON DUPLICATE KEY / ON CONFLICT).
    - READ: single row, list, the ResultSet → object mapping (⭐ the RowMapper
      functional interface, hand-written before you meet Spring's), the
      projection to a DTO ⭐ (never return the entity), the pagination
      (⭐⭐ OFFSET vs keyset/seek — with the numbers that show OFFSET
      degrading linearly and keyset staying flat), the N+1 problem
      introduced here and deferred to Hibernate.
    - UPDATE: by id, by condition, the optimistic-locking version column
      ⭐⭐ (`UPDATE ... SET v=v+1 WHERE id=? AND version=?` and check the
      row count — the whole of optimistic concurrency in 4 lines), the
      partial update and the dynamic-SQL problem.
    - DELETE: by id, soft delete ⭐⭐ (and the trade-offs — every query now
      needs a predicate, unique constraints break, the table grows), the
      cascade and the FK constraint.
  · Transactions ⭐⭐ — setAutoCommit(false), commit, rollback, the
    try/catch/finally pattern, ⭐ what auto-commit actually costs (a flush
    and an fsync per statement), savepoints, the isolation levels with the
    three anomalies (dirty read, non-repeatable read, phantom) — ⭐ and a
    RUNNABLE two-connection demo of each, because reading about isolation
    levels never works. setTransactionIsolation, the vendor defaults
    (MySQL REPEATABLE_READ ⭐ not READ_COMMITTED, PostgreSQL READ_COMMITTED),
    read-only transactions and the optimisation.
  · The SQLException hierarchy ⭐ — SQLState (the classes: 23 integrity, 40
    transaction rollback, 08 connection), getErrorCode (the vendor codes
    that matter: 1062 duplicate, 1213 deadlock, 1205 lock wait), ⭐⭐
    getNextException (batch failures hide the real error in the chain — a
    genuine production debugging story), the transient vs non-transient
    distinction and what it tells you about retrying.
  · DatabaseMetaData and ResultSetMetaData ⭐ — introspection, and the
    metadata-driven mapper that writes itself.
  · ResultSet types and concurrency ⭐ — TYPE_FORWARD_ONLY/SCROLL_INSENSITIVE/
    SCROLL_SENSITIVE, CONCUR_READ_ONLY/UPDATABLE, the fetch size and ⭐⭐ the
    MySQL trap: the default fetches the ENTIRE ResultSet into memory, and
    `setFetchSize(Integer.MIN_VALUE)` switches to streaming — with the
    consequence that the connection is locked until you close it. The
    PostgreSQL version (`setAutoCommit(false)` + a positive fetch size).
  · The connection pool — introduced here (⭐ why a TCP + TLS + auth
    handshake per query is a disaster), HikariCP configured, the pool size
    formula ⭐ (`connections = cores × 2 + effective_spindles`) and ⭐⭐ the
    counter-intuitive truth that a SMALLER pool is usually faster (the
    queueing theory, the contention at the DB), the leak detection setting,
    what "connection is not available, request timed out after 30000ms"
    actually means. Full treatment deferred to folder 03.
  · ⭐ THE DAO PATTERN, COMPLETE — the interface, the implementation, the
    generic BaseDAO<T, ID>, the row mapper, the exception translation
    (⭐ SQLException → a domain exception, which is what Spring's
    DataAccessException hierarchy does), the transaction boundary at the
    service layer not the DAO layer, and the full compilable shop example
    (Product, Customer, Order, OrderItem).
  · The test setup ⭐ — H2 in-memory (and ⭐⭐ why H2 lies to you: the SQL
    dialect differs, so a green H2 test does not mean a green MySQL
    deployment), Testcontainers with the real database (the right answer),
    the @Sql-style schema/data setup, the test-per-class vs test-per-method
    isolation question.
  · Schema and migrations — the DDL, the naming conventions, the types that
    matter (⭐ DECIMAL for money, never FLOAT; TIMESTAMPTZ never TIMESTAMP;
    the VARCHAR(255) cargo cult), Flyway and Liquibase conceptually, the
    expand-contract migration pattern ⭐⭐ (how to change a column in a
    zero-downtime deployment — this is an SDE 3 topic that lives in JDBC).
  · The mini-project: a complete CLI shop backend — schema, DAOs, a service
    layer, transactions, a test suite with Testcontainers, and a benchmark
    that measures insert throughput with and without batching.
  · THEN the four practice sets.

FILE 06 — 06-COLLECTIONS-MASTERY.md
  ONE-LINE: every collection, its internals, its complexity, its memory cost,
            and the interview traps — mastered, including writing three of
            them from scratch.
  · ⭐⭐ THE MAP — the full hierarchy drawn in ASCII: Iterable → Collection →
    {List, Set, Queue} with every implementation, and Map separately. Plus
    ⭐ WHY Map is not a Collection (no `V` in the value position of the
    Collection contract; the entrySet/keySet/values views are the bridge).
  · ⭐⭐⭐ THE COMPLEXITY TABLE — every implementation × every operation
    (get/set/add-at-end/add-at-index/remove/contains/iterate), average AND
    worst case. This is the thing to memorise. Then the WHY for each cell.
  · ⭐⭐ THE MEMORY TABLE — bytes per entry for each implementation at 1M
    elements, with the arithmetic shown (object header 16 + fields +
    padding + the node object + the reference). ArrayList vs LinkedList vs
    HashMap vs TreeMap. ⭐ The number that shocks people: 1M Integers in an
    ArrayList ≈ 20 MB; 1M entries in a HashMap ≈ 48-80 MB.
  · LIST
    - ArrayList ⭐⭐⭐ the internals from the source: DEFAULT_CAPACITY = 10
      (and the EMPTY_ELEMENTDATA vs DEFAULTCAPACITY_EMPTY_ELEMENTDATA
      distinction that delays allocation to the first add), the growth
      formula `oldCapacity + (oldCapacity >> 1)` = 1.5× (⭐ and why 1.5 and
      not 2 — the reuse-of-freed-memory argument), Arrays.copyOf, size vs
      capacity vs the array length, the modCount and fail-fast, why
      remove(int) is O(n) (System.arraycopy), why remove(Object) is O(n)
      twice, the trimToSize, the iterator (the Itr inner class and its
      expectedModCount check), ⭐ the subList view and the
      ConcurrentModificationException it causes, the serialisation (it writes
      size, not capacity).
    - ⭐⭐⭐ ArrayList vs LinkedList — THE HONEST ANSWER, with a benchmark.
      LinkedList almost always loses: 24 bytes of node overhead per element,
      pointer chasing that defeats the CPU cache, and the "O(1) insert in the
      middle" claim is false because you must first traverse to the middle
      (O(n)). Show the numbers. Then the three cases LinkedList genuinely
      wins (as a Deque — and ArrayDeque still beats it; when you hold the
      iterator and insert there; almost never).
    - LinkedList — the doubly-linked structure, first/last, the node, the
      Deque implementation, the ListIterator optimisation.
    - Vector ⛔ (synchronised on every method, the 2× growth, why it's dead)
      and Stack ⛔ (extends Vector so it's synchronised AND it exposes the
      inherited random access that breaks the LIFO contract — use ArrayDeque).
    - CopyOnWriteArrayList ⭐⭐ (the copy-on-write mechanism, the snapshot
      iterator that never throws CME, the write cost, ⭐ when it's right:
      many readers, rare writers, small collections — a listener list; when
      it's catastrophic: a large frequently-modified list).
    - The unmodifiable/synchronized/immutable wrappers ⭐⭐ — Collections.
      unmodifiableList (a VIEW, not a copy — ⭐ mutate the backing list and
      the "unmodifiable" one changes), Collections.synchronizedList (⛔ still
      needs manual synchronisation when iterating — the exact code),
      List.of/List.copyOf (⭐ truly immutable, NULL-HOSTILE, and ⭐⭐
      List.of's iteration order is deliberately randomised per JVM run —
      don't depend on it).
  · SET
    - HashSet ⭐⭐⭐ — the reveal: it is a HashMap with a single static
      `PRESENT` Object as every value. So everything about HashMap applies.
      The initial capacity 16, the load factor 0.75, and ⭐ the resize
      threshold arithmetic.
    - LinkedHashSet — the LinkedHashMap underneath, the insertion order, the
      cost.
    - TreeSet ⭐⭐ — the TreeMap underneath, the NavigableSet API
      (floor/ceiling/higher/lower/subSet/headSet/tailSet — ⭐ the inclusive/
      exclusive flags), ⭐⭐⭐ THE COMPARATOR-VS-EQUALS INCONSISTENCY TRAP:
      TreeSet uses compare()/compareTo() for membership, NOT equals(). Two
      objects that are equals() but compare()==0... or NOT equals() but
      compare()==0 — the second is the bug: a TreeSet of BigDecimal where
      1.0 and 1.00 are the SAME element. With the proof program.
    - EnumSet ⭐⭐⭐ — the bit vector (a long[] where bit i = the i-th
      constant), why it's faster than HashSet by an order of magnitude, why
      iteration is in declaration order, the noneOf/allOf/of/range factories,
      the RegularEnumSet vs JumboEnumSet split at 64.
    - CopyOnWriteArraySet, ConcurrentSkipListSet (the skip list, cross-ref).
  · QUEUE AND DEQUE
    - PriorityQueue ⭐⭐⭐ — the binary heap in an array (⭐ the parent/child
      index arithmetic: parent = (i-1)>>>1, children = 2i+1, 2i+2), the
      siftUp and siftDown with diagrams, why offer is O(log n) and peek is
      O(1) and poll is O(log n), ⭐⭐ WHY ITERATION IS NOT SORTED (it's a
      heap, not a sorted array — the toArray() surprise), the comparator and
      the natural ordering, the unbounded growth ⛔ (it's an
      PriorityQueue(int) capacity but grows), the thread-safety (none — use
      PriorityBlockingQueue), ⭐ the top-K pattern (a bounded max-heap of
      size K, inverted), and the lazy-deletion trick for Dijkstra.
    - ArrayDeque ⭐⭐⭐ — the circular array, the head and tail pointers, the
      wraparound arithmetic (⭐ `(p + 1) & (elements.length - 1)` — the same
      power-of-two trick as HashMap), the doubling growth and the
      doubleCapacity, ⭐⭐ WHY IT BEATS BOTH Stack AND LinkedList (no node
      allocation, cache-friendly, no synchronisation), the null-hostility
      (⭐ addLast(null) throws — because null is the "empty slot" sentinel),
      the fail-fast iterator, the Deque API (addFirst/Last, offerFirst/Last,
      pollFirst/Last, peekFirst/Last — ⭐ and the add/offer, remove/poll,
      element/peek triple-distinction: throws vs returns-false/null).
    - The BlockingQueue family ⭐⭐⭐ — the interface contract (the four
      method flavours: throws / returns-special / blocks / times-out, in a
      table), ArrayBlockingQueue (one lock, two Conditions — notFull and
      notEmpty ⭐ the two-condition win), LinkedBlockingQueue ⭐⭐ (the
      TWO-LOCK queue algorithm — putLock and takeLock, so producers and
      consumers don't contend; and the AtomicInteger count that makes it
      possible; ⛔ and the unbounded default that OOMs you),
      PriorityBlockingQueue, DelayQueue (the Delayed interface, the
      leader-follower pattern ⭐), SynchronousQueue (⭐ zero capacity, the
      handoff, and why Executors.newCachedThreadPool uses it),
      LinkedTransferQueue (the TRANSFER semantics), the ConcurrentLinkedQueue
      (⭐⭐ the Michael-Scott lock-free queue, the CAS on head/tail, the
      weakly-consistent size() that is O(n) — ⛔ never call size() on it in
      a hot path).
    - Deque as a stack and as a queue — the method table.
  · MAP ⭐⭐⭐ THE CENTREPIECE
    - HashMap — the deepest treatment in the whole folder. From the source:
      ⭐ the hash spreading: `hash(key) = (h = key.hashCode()) ^ (h >>> 16)`
        — WHY (the index uses only the low bits, so the high bits are folded
        down to reduce collisions; one XOR is nearly free).
      ⭐ the index: `(n - 1) & hash` — WHY the capacity must be a power of
        two (so the mask equals a modulo, but as one AND instruction), and
        what happens if you pass a non-power-of-two to the constructor (it
        rounds up via tableSizeFor — show the bit-twiddling).
      ⭐⭐⭐ put() step by step, with the source annotated: the null-table
        resize, the empty-bin CAS-free assign, the first-node equals check,
        the TreeNode branch, the linked-list walk with the binCount, the
        TREEIFY_BIN = 8 threshold, the MIN_TREEIFY_CAPACITY = 64 rule
        (⭐⭐ below 64 it RESIZES instead of treeifying — everyone misses
        this), the modCount++ and the size++, the resize-threshold check.
      ⭐⭐⭐ resize() — the doubling, the new threshold, and THE HIGH/LOW
        SPLIT TRICK: because the capacity doubles, an element's new index is
        either its old index or its old index + oldCap, decided by a single
        bit test `(e.hash & oldCap) == 0`. ⭐⭐ So resize does NOT rehash.
        This is a genuinely impressive thing to explain in an interview.
      ⭐⭐ the Java 7 → Java 8 changes: head insertion → tail insertion, and
        the Java 7 concurrent-resize INFINITE LOOP (the list reversal under
        contention created a cycle; two threads spinning at 100% CPU forever).
        The treeify addition. ⭐⭐⭐ This is a famous bug and a great story.
      ⭐ TreeNode and the red-black tree inside HashMap — when it converts,
      when it UNTREEIFIES (6, on resize), and ⭐ the guard: a key must
      implement Comparable or the tree falls back to identity-hash ordering
      (tieBreakOrder).
      ⭐ the null key (bucket 0, hash 0) and null values (and why
      containsValue is O(n) and get() can't distinguish "absent" from
      "present with null" — hence containsKey).
      ⭐ the load factor — the maths of the Poisson distribution that gives
        0.75 and the treeify-at-8 (⭐⭐ the source comment literally contains
        the Poisson table showing a 0.00000006 chance of 8 at LF 0.75 — so
        treeification should never happen with a good hashCode, and if it
        does your hashCode is broken).
      ⭐⭐⭐ the sizing formula: `new HashMap<>((int)(expected / 0.75f) + 1)`
        — and the Guava `Maps.newHashMapWithExpectedSize` that does it for you.
      ⭐ the fail-fast iterator, the entrySet/keySet/values VIEWS (not
        copies), the entrySet iteration being the fast path.
      ⭐⭐ the ConcurrentHashMap preview (full treatment below).
      ⭐ the HashMap-based LRU in 6 lines with LinkedHashMap.
      ⭐ the 12 "what's wrong with this" programs: mutable key, no hashCode
        override, hashCode returning a constant, a hashCode built from a
        mutable field, iterating and removing, a HashMap shared between
        threads, the identity-vs-equality confusion, the enum key that should
        be an EnumMap, the Boolean key, the array key ⛔ (arrays use
        identity hashCode), the record key ⭐ (works perfectly), the
        BigDecimal key.
    - LinkedHashMap ⭐⭐ — the doubly-linked list threaded through the
      HashMap entries, insertion vs ACCESS order (⭐⭐ accessOrder=true
      reorders on get, which means get() is a MUTATING operation — so it is
      not safe to share, and it's the LRU mechanism), removeEldestEntry
      (⭐ override it and you have an LRU cache), the iteration-order
      guarantee that HashSet lacks.
    - TreeMap ⭐⭐⭐ — the red-black tree, the five invariants (drawn), the
      O(log n) get/put/remove, the NavigableMap API (floorKey/ceilingKey/
      higherKey/lowerKey, firstKey/lastKey, subMap/headMap/tailMap with the
      inclusive flags, ⭐ the descendingMap VIEW, the navigableKeySet),
      ⭐⭐ the comparator-vs-equals inconsistency again (a TreeMap with a
      case-insensitive comparator treats "A" and "a" as the SAME KEY), the
      natural-ordering requirement (Comparable or a Comparator, and the
      ClassCastException otherwise), the memory cost per entry (~40 bytes:
      the Entry has parent/left/right/color), and when it beats HashMap
      (ordered iteration, range queries — ⭐ the range query is the real
      reason, because HashMap can't do one at all).
    - EnumMap ⭐⭐ — the array indexed by ordinal, why it's the fastest Map
      there is, the values() and keySet() backed by the array, the null
      value allowed but not the null key, ⭐ and the rule: if your key is an
      enum, use EnumMap, always.
    - WeakHashMap ⭐⭐⭐ — the WeakReference keys, the ReferenceQueue, the
      expungeStaleEntries mechanism, ⭐ the use case (a cache whose entries
      should vanish when nobody else holds the key), ⭐⭐ the trap (a value
      that strongly references its own key keeps the entry alive forever —
      and the ThreadLocal-style leak that follows), and IdentityHashMap
      (⭐ reference equality via System.identityHashCode, the linear probing,
      the use case: object graphs and serialisation where you must not
      collapse equal-but-distinct objects).
    - Hashtable ⛔ (synchronised on every method, no null keys or values,
      dead — and the Properties subclass that survives).
    - Map.of / Map.copyOf ⭐⭐ — immutable, NULL-HOSTILE (throws NPE, unlike
      HashMap), duplicate-hostile (throws IllegalArgumentException), and
      ⭐⭐⭐ the iteration order is DELIBERATELY RANDOMISED (SALT) so you
      cannot depend on it — the reason is to stop order-dependence bugs
      becoming load-bearing. ImmutableCollections internals.
    - Collections.unmodifiableMap / synchronizedMap — the view trap and the
      iteration trap, again.
    - ⭐⭐⭐ ConcurrentHashMap — the full internals:
      Java 7: the Segment array (default 16), each a ReentrantLock, so 16
        concurrent writers. ⭐ The "concurrencyLevel" parameter.
      Java 8+: NO SEGMENTS. CAS for the empty-bin insert, `synchronized` on
        the BIN HEAD NODE for the collision case. ⭐⭐⭐ So the lock
        granularity is the bucket, not a segment — and with a good hash,
        contention is nearly zero.
      The size() problem ⭐⭐ — you cannot count without stopping the world,
        so: baseCount + a CounterCell[] striping (the LongAdder mechanism),
        and size() returns an ESTIMATE. mappingCount() returns a long.
        ⭐ Neither is exact under concurrency, and that's correct.
      putVal annotated, the helpTransfer mechanism (⭐⭐ concurrent threads
        HELP with the resize — the ForwardingNode), the treeify, the
        MIN_TREEIFY_CAPACITY, the null-hostility ⭐ (ConcurrentHashMap
        forbids null keys AND values — because get() returning null would be
        ambiguous under concurrency; HashMap allows both).
      The weakly-consistent iterator (⭐ no ConcurrentModificationException,
        but it may or may not reflect concurrent changes), the atomic
        compound operations ⭐⭐⭐ (computeIfAbsent, compute, merge, putIfAbsent
        — and WHY `if (!map.containsKey(k)) map.put(k,v)` is a race even here,
        and why computeIfAbsent's mapping function must not modify the map
        ⛔ (the IllegalStateException / the deadlock in Java 8)), the
        ⭐ computeIfAbsent-is-atomic-but-slow caveat (it locks the bin, so a
        slow mapping function blocks the bin — the Java 9 improvement).
      The read path has NO LOCKING AT ALL — the `val` and `next` fields of
        Node are `volatile`. ⭐⭐ That's the whole trick, and it's the answer
        to "how does ConcurrentHashMap read without locking".
    - ConcurrentSkipListMap ⭐⭐ — the skip list (drawn, with levels), the
      CAS-based lock-free insertion, why a skip list and not a red-black
      tree (⭐ rebalancing a tree requires a global rotation lock; a skip
      list is local), the O(log n) with a worse constant than TreeMap, the
      weakly-consistent iterators, the NavigableMap API concurrently.
    - ConcurrentSkipListMap vs ConcurrentHashMap vs TreeMap vs HashMap — the
      decision table.
  · ITERATION ⭐⭐
    - The Iterator contract, the remove() semantics, the ListIterator (both
      directions, set, add, the index).
    - ⭐⭐⭐ FAIL-FAST vs FAIL-SAFE — modCount and expectedModCount, exactly
      where the check happens (next() and remove(), NOT add()), why it's a
      best-effort detection and NOT a guarantee (⭐ a fail-fast iterator can
      miss a concurrent modification — so never write a program that depends
      on CME for correctness), the concurrent collections' snapshot/weakly-
      consistent iterators.
    - ⭐⭐ ConcurrentModificationException — the SIX ways people try to fix
      it and which are right:
      ⛔ catch it · ⛔ use a synchronized collection (doesn't help) ·
      ⛔ CopyOnWrite for everything · ✅ Iterator.remove() ·
      ✅ removeIf (⭐ which uses Iterator.remove internally) ·
      ✅ collect a to-remove list and removeAll after ·
      ✅ a concurrent collection.
      With the proof program for each.
    - The 5 ways to iterate a Map and their costs ⭐ (entrySet, keySet+get,
      forEach, the streams, the iterator with remove) — with the numbers.
    - Spliterator ⭐⭐ — the contract, the characteristics (ORDERED/DISTINCT/
      SORTED/SIZED/NONNULL/IMMUTABLE/CONCURRENT/SUBSIZED), tryAdvance/
      forEachRemaining/trySplit, how parallel streams use it, and writing one.
    - Iterable vs Iterator, the for-each desugaring (⭐ an array compiles to
      an index loop; an Iterable compiles to an Iterator — so for-each over
      an array is faster and allocates nothing).
  · SORTING AND COMPARISON ⭐⭐⭐
    - Comparable vs Comparator — the contracts, when each, the
      Comparator.comparing/thenComparing/reversed/nullsFirst/nullsLast/
      naturalOrder composition chain.
    - ⛔ THE SUBTRACTION COMPARATOR BUG: `(a, b) -> a - b` overflows for
      large ints. `Integer.compare(a, b)` is the answer. Proof program.
    - ⭐⭐⭐ THE COMPARATOR CONTRACT VIOLATION: "Comparison method violates
      its general contract!" — the TimSort IllegalArgumentException. The
      causes: non-transitive comparison, a comparator that depends on
      mutable state, the `a > b ? 1 : -1` that forgets equality, a
      comparator over doubles with NaN. The diagnosis and the fix. This is a
      REAL production exception and a great interview story.
    - ⭐⭐ TimSort — the merge-insertion hybrid, the run detection, the
      minrun, the galloping mode, the merge stack and the invariants it
      maintains, why it's O(n) on partially-sorted data (⭐ and why that
      makes it the right default for real data), the stability guarantee and
      why stability matters (the multi-key sort by sorting on the secondary
      key first, then the primary).
    - Arrays.sort: ⭐⭐ dual-pivot quicksort for PRIMITIVES (not stable, and
      stability is meaningless for primitives) vs TimSort for OBJECTS
      (stable). The reason for the difference is a great interview answer.
    - Collections.sort vs List.sort vs Arrays.sort vs the stream sorted()
      (⭐ sorted() is stable for ordered streams and NOT guaranteed for
      parallel unordered ones).
  · equals AND hashCode ⭐⭐⭐ (revisited at depth)
    - The 5 rules of equals, the impossibility theorem (⭐ you cannot add a
      value component in a subclass and keep symmetry — the proof), the
      record solution.
    - The hashCode contract, the 31 multiplier (⭐ prime, and 31 lets the
      JIT turn it into a shift-and-subtract), the Objects.hash boxing cost
      and the hand-rolled alternative.
    - The HashMap-orphaning proof program (the mutable key).
    - The HashSet-contains-lies program.
    - Lombok @EqualsAndHashCode (⭐ and the callSuper default warning), the
      IDE generators, records.
    - The JPA entity equals/hashCode problem ⭐⭐ (never use all fields;
      never use a generated id before persist; the business-key or
      UUID-assigned-on-creation solutions) — deferred to folder 05.
  · MEMORY AND PERFORMANCE ⭐⭐
    - The per-element overhead arithmetic, shown for each collection.
    - Autoboxing ⭐⭐ — the Integer cache, the boxing in a loop (with the
      allocation numbers), the `Long sum = 0L; sum += i;` disaster, the
      primitive collections (Eclipse Collections, fastutil, Koloboke,
      HPPC) and when they're worth the dependency.
    - Presizing ⭐ — ArrayList(int), HashMap(int) with the load-factor
      maths, the StringBuilder(int).
    - The unmodifiable-view vs copy decision, and the memory difference.
    - Iteration cost and the CPU cache — why ArrayList iteration is 10×
      LinkedList iteration for a sum.
    - The GC pressure of collections — allocation rate, the young-gen
      churn, and how to see it with JFR.
    - ⭐ WHEN TO USE A PLAIN ARRAY. The honest answer: for a fixed-size,
      primitive, hot-path structure, an array beats every collection.
  · ⭐⭐⭐ THE DECISION TREE + THE MASTER TABLE — "which collection do I use?"
    as a flowchart, then a 20-row table: need, best choice, runner-up,
    avoid, and why.
  · WRITE THEM FROM SCRATCH ⭐⭐⭐ — the single best way to master this:
    a complete MyArrayList (grow, shrink, iterator, fail-fast),
    a complete MyLinkedList (doubly-linked, Deque API),
    a complete MyHashMap (buckets, resize, the spreading hash, the iterator,
      treeify optional),
    a complete MyPriorityQueue (the heap, siftUp/siftDown),
    each with a test suite that runs the same tests as the JDK class.
  · 12 REAL PROGRAMS: an LRU cache (LinkedHashMap + a hand-rolled doubly-
    linked version), an LFU cache, a thread-safe rate limiter, a word-
    frequency counter with a top-K, a graph with adjacency lists (and the
    BFS/DFS), an event bus, an object pool, an interval scheduler, a
    multi-level cache, an in-memory index for search, a topological sort,
    a disjoint-set union.
  · THEN the four practice sets — with the "what does this print?" set
    heavily focused on iteration order, the comparator traps, and the
    concurrent modification cases.

FILE 07 — 07-PROJECTS.md
  ONE-LINE: ten Core Java projects, each complete and runnable, each teaching
            a specific set of concepts.
  ⭐ Every project: the brief, the requirements, the design (UML), the full
  commented source, the tests, the "what I learned" list, the extensions, and
  the interview line ("I built X, which taught me Y").
  P1  A console library management system — OOP, collections, file I/O, the
      DAO pattern, exception design. (The classic, done properly.)
  P2  An in-memory key-value store with TTL and eviction — ⭐ the LRU/LFU,
      the concurrent map, the scheduled expiry, the persistence to disk.
      The single best collections + concurrency project.
  P3  A multi-threaded web crawler — the executor, the blocking queue, the
      politeness delay, the dedup with a Bloom filter, the shutdown.
  P4  A JSON parser and object mapper from scratch — ⭐⭐ recursion, the
      state machine, reflection, generics, the type tokens. Teaches more
      about Java than any tutorial.
  P5  A log framework — the levels, the appenders, the formatters, the async
      appender with a ring buffer, the config file, ⭐ the Decorator and
      Strategy patterns in anger.
  P6  A build tool (a mini-Maven) — the dependency graph, the topological
      sort, the cycle detection, the classpath construction, invoking javac.
  P7  A chat server — ⭐⭐ NIO selectors, the Reactor pattern, the protocol,
      the broadcast, the backpressure, then a virtual-threads rewrite and a
      comparison of the two. THE best I/O + concurrency project.
  P8  A task scheduler (a mini-Quartz) — the cron expression parser, the
      priority queue, the thread pool, the persistence, the misfire handling.
  P9  A database connection pool from scratch — ⭐⭐⭐ the blocking queue, the
      borrow/return, the validation, the leak detection, the max-wait, the
      metrics. Then compare it to HikariCP's design and explain the
      differences. This one gets asked about in interviews.
  P10 ⭐ A trading order-matching engine — the limit order book with two
      TreeMaps (bids descending, asks ascending), the matching algorithm,
      the LMAX-style single-threaded design with a disruptor ring buffer,
      the snapshot/restore, the latency measurement with JMH. The SDE 3
      showcase project.

FILE 08 — 08-CHEATSHEET.md
  ONE-LINE: all of Core Java on one page — the tables, the flags, the traps.
  · The complexity table · the memory table · the collection decision tree
  · the String methods · the Stream operations · the Collectors
  · the java.util.function matrix · the concurrency tool selector
  · the JMM rules · the volatile/synchronized/final cheat
  · the JVM flags that matter · the jcmd/jstack/jmap/jstat commands
  · the GC selection table · the Java 8→25 feature timeline
  · the exceptions hierarchy · the access modifier matrix
  · the PECS rule · the equals/hashCode rules · the 30 interview one-liners
  · the "what does this print" top 20 with answers

───────────────────────────────────────────────────────────────────────────────
FOLDER 2 — 02-frontend  (MULTIPLE SUB-FOLDERS, MULTIPLE FILES EACH)
───────────────────────────────────────────────────────────────────────────────
Same conventions. Every file gets a one-line explanation in the folder README.
Every code sample is complete, runnable, and commented to the PART 3 standard
— for HTML/CSS/JS that means commented markup, commented styles explaining the
cascade decision, and commented JS explaining the execution order.

html/ — 10 files
  01-html-fundamentals.md   what HTML is, the document, doctype, the parse
                            model, elements/tags/attributes, nesting rules,
                            void elements, entities, the DOM preview
  02-text-and-semantics.md  headings and the hierarchy, paragraphs, lists,
                            emphasis (em vs i, strong vs b ⭐), quotes, code,
                            the semantic inline elements, why semantics matter
                            for a11y and SEO
  03-links-images-media.md  anchors (href/target/rel ⭐ noopener noreferrer
                            and the reverse-tabnabbing attack), images
                            (src/srcset/sizes/picture/lazy/decoding ⭐⭐ the
                            responsive-image decision), audio, video, iframe
                            (sandbox, the security model), figure, embed/object
  04-forms.md               ⭐ every input type and what it does on mobile,
                            label and the for/id binding, fieldset/legend,
                            the validation attributes and the Constraint
                            Validation API, FormData, autocomplete (⭐ the
                            privacy and the UX), the accessible form, the
                            method/action, the GET vs POST semantics, file
                            uploads, the output element
  05-tables.md              thead/tbody/tfoot, caption, colspan/rowspan, the
                            scope attribute ⭐ (a11y), responsive tables (the
                            4 techniques), ⛔ tables for layout, when a table
                            is the RIGHT semantic choice (data, always)
  06-document-structure.md  header/nav/main/article/section/aside/footer, the
                            landmark roles, the heading-hierarchy discipline,
                            ⭐ the outline algorithm myth (it was never
                            implemented), the address/time/details elements,
                            the sectioning content rules
  07-accessibility.md       ⭐⭐ WCAG 2.2 POUR, the ARIA first rule (don't),
                            roles/states/properties, keyboard navigation and
                            the focus order, focus management on route change,
                            skip links, screen readers (NVDA/VoiceOver), colour
                            contrast (the ratios), the a11y tree, live regions
                            (aria-live polite/assertive), the testing tools
                            (axe, Lighthouse), the top 20 real failures
  08-seo-and-metadata.md    the head, title, meta (description/robots/viewport/
                            charset ⭐ why charset comes first), Open Graph and
                            Twitter cards, the canonical URL, JSON-LD
                            structured data, sitemap.xml, robots.txt, ⭐ Core
                            Web Vitals and what HTML can do about them, the
                            hreflang, the SPA SEO problem and its fixes
  09-html-internals.md      ⭐⭐ the parsing algorithm (tokenise → tree
                            construction, the misnesting error recovery), the
                            critical rendering path, reflow vs repaint,
                            defer vs async ⭐⭐ (with the timing diagram),
                            preload/prefetch/preconnect/dns-prefetch/modulepreload,
                            Web Components (custom elements, Shadow DOM ⭐,
                            templates, slots), the browser's speculative parser
  10-cheatsheet.md          the element reference, the attribute reference,
                            the a11y mapping table, the head checklist

css/ — 13 files
  01-the-cascade.md         ⭐⭐⭐ how CSS actually resolves a declaration:
                            origin & importance → scope → the layer → specificity
                            → order of appearance. The specificity arithmetic
                            (and why "1,0,0,0" is a bad model), the !important
                            and when it's legitimate, inheritance and the
                            inherit/initial/unset/revert keywords, the
                            initial/computed/used/specified value pipeline
  02-selectors.md           every selector with a specificity score, the
                            combinators, the attribute selectors and their
                            operators, the pseudo-classes (structural, the
                            form ones, :is/:where/:not/:has ⭐⭐ and the
                            specificity difference between :is and :where),
                            the pseudo-elements, ⭐ the selector performance
                            myth and the real cost, the :has() parent selector
                            and what it unlocked
  03-the-box-model.md       content/padding/border/margin, ⭐ box-sizing and
                            the universal reset, margin collapsing ⭐⭐ (the
                            rules, the siblings, the parent-child, the empty
                            element, and the four ways to prevent it), the
                            display types (block/inline/inline-block/flow-root
                            ⭐/contents/none), the Block Formatting Context and
                            what creates one, the width/height resolution,
                            the min/max constraints
  04-units-and-values.md    every unit, ⭐ px vs rem vs em and the
                            accessibility argument for rem, the viewport units
                            and ⭐⭐ the dynamic/small/large variants (dvh/svh/
                            lvh) that fixed the mobile browser chrome problem,
                            ch and ex, percentages and what they're relative
                            to (⭐ different for every property), calc(),
                            ⭐⭐ clamp() and the fluid-typography formula,
                            ⭐⭐⭐ custom properties (they are NOT variables —
                            they are inherited, cascading, live, readable from
                            JS, and usable in media queries via a trick; the
                            invalid-at-computed-value-time behaviour; the
                            @property registration and what it enables)
  05-positioning-and-flow.md the normal flow, static/relative/absolute/fixed/
                            sticky ⭐⭐ (sticky's containment trap — it only
                            sticks within its parent, and overflow:hidden on an
                            ancestor breaks it), the containing block for each
                            (⭐ absolute positions against the nearest
                            POSITIONED ancestor, not the nearest parent),
                            ⭐⭐⭐ z-index and STACKING CONTEXTS (the seven
                            things that create one, why z-index:9999 doesn't
                            work, the isolation property, the debugging
                            technique), float and clear and why we don't
                            layout with them any more
  06-flexbox.md             ⭐⭐ the model (main axis, cross axis, the flex
                            container vs item), every property on both sides,
                            ⭐⭐⭐ the flex-grow/shrink/basis ARITHMETIC (the
                            free-space distribution formula, worked examples
                            with numbers, the flex:1 shorthand and what it
                            really means, the min-width:auto trap that breaks
                            text truncation and needs min-width:0), the align
                            vs justify distinction, flex-wrap, order, the
                            align-self, ⭐ the 10 recipes (holy grail, sticky
                            footer, centring — all three ways, equal-height
                            cards, the navbar, the media object), when flexbox
                            is the wrong tool (2D, and ⭐ the wrap-based grid
                            anti-pattern)
  07-grid.md                ⭐⭐ the model, the template properties, fr and how
                            it distributes (⭐ after the fixed tracks, and the
                            min-content floor), ⭐⭐⭐ minmax() and the
                            auto-fill vs auto-fit difference (with the visual
                            that finally makes it click), the implicit tracks
                            and grid-auto-flow (⭐ the dense option), the
                            placement (line numbers, names, areas), ⭐ the
                            12-column pattern, subgrid ⭐⭐ and the alignment
                            problem it solves, the named grid areas and the
                            responsive-layout-without-media-queries trick,
                            the grid vs flexbox decision table
  08-responsive-design.md   ⭐ mobile-first and why, media queries (the
                            features that matter, the ranges syntax since
                            Media Queries 4), ⭐⭐⭐ CONTAINER QUERIES (the
                            container-type, the cqi/cqb units, why this is the
                            biggest change in a decade — components respond to
                            their container, not the viewport), fluid type with
                            clamp(), responsive images, ⭐ the "breakpoints
                            are a smell" argument, the responsive without
                            media queries techniques (grid auto-fit, flexbox
                            wrap, the ch unit), the testing workflow
  09-colour-type-background.md ⭐ colour spaces (sRGB, Display P3, and
                            ⭐⭐ OKLCH — perceptually uniform, and why
                            color-mix() in OKLCH is the right way to build a
                            palette), gradients (linear/radial/conic, the
                            repeating variants, the hard-stop technique),
                            shadows (and the layered-shadow technique),
                            ⭐ typography (the font stack and why the order
                            matters, @font-face and the FOIT/FOUT, the
                            font-display values, variable fonts and the
                            axes, the measure/line-height/vertical-rhythm,
                            the text-wrap:balance and pretty ⭐), backgrounds
                            (the multiple-background, the size/position/origin/
                            clip, the pattern techniques), filters and
                            backdrop-filter, blend modes, the accent-color and
                            color-scheme
  10-motion.md              ⭐⭐ the rendering pipeline and WHY transform and
                            opacity are free (they composite, they don't layout
                            or paint) and everything else isn't, transitions
                            (the properties, the timing functions and the
                            cubic-bezier, the transition-delay, ⛔
                            transition:all), keyframe animations (the
                            fill-mode, the iteration, the direction, the
                            composition), the FLIP technique ⭐⭐, will-change
                            (⭐ and why it's usually harmful), the
                            prefers-reduced-motion query ⭐ (accessibility,
                            not optional), the View Transitions API ⭐⭐
  11-modern-css.md          ⭐⭐⭐ the 2026 feature set: native nesting (and
                            the & selector, and how it differs from Sass),
                            :has(), ⭐ cascade layers @layer (the specificity
                            escape hatch that fixes design-system wars),
                            @scope, @container, subgrid, ⭐ anchor positioning
                            (the tooltip/popover problem solved in CSS),
                            @layer and the framework-override problem, the
                            popover attribute and the top layer, logical
                            properties (⭐ the RTL story), color-mix(),
                            oklch(), the light-dark() function, the
                            text-wrap values, the scroll-driven animations ⭐⭐,
                            @starting-style, the field-sizing, the
                            appearance and the form control styling, what's
                            baseline-widely-available today
  12-architecture.md        ⭐⭐ the methodologies (BEM and its verbosity,
                            SMACSS, ITCSS, utility-first), Tailwind ⭐⭐ (the
                            honest trade-off analysis: what it fixes, what it
                            costs, when it's wrong), vanilla-extract and the
                            zero-runtime approach, CSS Modules, preprocessors
                            (Sass and what native CSS has made redundant),
                            PostCSS and Autoprefixer, design tokens ⭐⭐ (the
                            three-tier model, the W3C Design Tokens spec,
                            multi-platform tokens), the reset vs normalize vs
                            preflight, the specificity management strategy,
                            the file organisation, the performance budget
  13-cheatsheet.md          the selector table, the specificity table, the
                            flexbox table, the grid table, the unit table, the
                            stacking-context triggers, the a11y checklist

dom/ — 10 files
  01-the-tree.md            ⭐ what the DOM IS (an API over the parsed
                            document, a tree of nodes, an object model), the
                            Node hierarchy (Node → Element/Text/Comment/
                            DocumentFragment/Document), the interface members,
                            ⭐⭐ live vs static collections (getElementsBy*
                            is LIVE and updates as the DOM changes;
                            querySelectorAll is a STATIC snapshot — with the
                            proof program that shows the live one shrinking
                            while you iterate it), the nodeType constants,
                            the Document object, the window relationship
  02-selecting-traversing.md every selector method, the traversal properties
                            (parentNode/parentElement ⭐ the difference,
                            childNodes vs children ⭐ the difference,
                            firstChild vs firstElementChild, nextSibling vs
                            nextElementSibling), closest() ⭐, matches(), the
                            ⭐ caching-references performance rule, the cost
                            of each selector, the querySelector scoping,
                            the Shadow DOM piercing question
  03-creating-modifying.md  createElement/createTextNode, ⭐⭐ textContent vs
                            innerText vs innerHTML (the XSS in innerHTML, the
                            performance difference, the innerText reflow
                            cost), insertAdjacentHTML and its four positions,
                            append/prepend/before/after/replaceWith/remove
                            (⭐ the modern API vs appendChild/insertBefore/
                            removeChild), cloneNode (⭐ deep vs shallow and
                            the duplicate-ID bug it creates),
                            ⭐⭐⭐ DocumentFragment (the batch-mutation pattern,
                            the numbers: 1000 appends with and without),
                            replaceChildren, the innerHTML sanitisation
                            (DOMPurify and why you need it), the table/
                            select/option special cases
  04-attributes-props-styles.md ⭐⭐⭐ ATTRIBUTE vs PROPERTY — the distinction
                            that confuses everyone: the HTML attribute is the
                            INITIAL value, the DOM property is the CURRENT
                            value; changing the property doesn't change the
                            attribute and vice versa (with the input value
                            proof, and the checkbox checked proof); the
                            getAttribute/setAttribute vs el.prop decision;
                            dataset and data-* ⭐ (the camelCase conversion),
                            classList (add/remove/toggle/replace/contains and
                            the multi-argument forms), style vs cssText vs
                            ⭐ getComputedStyle (and why reading it forces a
                            reflow), setting CSS custom properties from JS,
                            the boolean attributes
  05-events.md              ⭐⭐⭐ THE EVENT MODEL — the three phases (capture
                            → target → bubble) with the diagram, addEventListener
                            and its options (capture, once, passive ⭐ and the
                            scroll-jank problem it solves, signal ⭐ the
                            AbortController removal pattern), the Event object
                            and its members (target vs currentTarget ⭐⭐ the
                            distinction that breaks delegation, the composed
                            path, the isTrusted), preventDefault vs
                            stopPropagation vs stopImmediatePropagation ⭐⭐
                            (and return false, which only works inline),
                            ⭐⭐⭐ EVENT DELEGATION (the pattern, why it works,
                            the closest() idiom, the performance and memory
                            win, the caveats — some events don't bubble:
                            focus/blur/mouseenter/mouseleave/load, and the
                            focusin/focusout replacements), dispatchEvent and
                            CustomEvent ⭐⭐ (the component communication
                            pattern, the detail payload), the event loop and
                            dispatch timing, the pointer/touch/mouse event
                            families and the pointer-events unification, the
                            key events and the key vs code, the form events,
                            the scroll/resize/wheel events and the throttling
                            discipline, the load/DOMContentLoaded/
                            readystatechange distinction ⭐⭐ (with the timing
                            diagram), the inline handler problems
  06-forms-and-input.md     FormData ⭐ (the constructor from a form, the
                            append, the multipart encoding, the file access),
                            the Constraint Validation API (checkValidity,
                            setCustomValidity ⭐⭐ the pattern, the validity
                            state object, the :invalid/:valid pseudo-classes
                            and the premature-error UX problem), the input/
                            change/submit events (⭐ input fires per keystroke,
                            change on commit — and the submit-button-vs-enter
                            difference), focus control (focus/blur, the
                            focus({preventScroll}), the autofocus problems),
                            the file input and the FileList/File/FileReader,
                            ⭐⭐ drag and drop (the events, the dataTransfer,
                            the dropzone, why it's painful, and the modern
                            alternative), the autocomplete/autofill model,
                            the FormData-to-JSON conversion
  07-performance.md         ⭐⭐⭐ THE RENDERING PIPELINE — JS → style →
                            layout → paint → composite, and what triggers each.
                            Reflow vs repaint vs composite-only, ⭐⭐ LAYOUT
                            THRASHING (reading a layout property after writing
                            a style forces a synchronous reflow — the proof,
                            the numbers, and the batch-reads-then-batch-writes
                            fix), requestAnimationFrame ⭐⭐ (why it beats
                            setTimeout for animation, the timestamp argument,
                            the frame budget of 16.7ms), the observers
                            (IntersectionObserver ⭐ for lazy loading and
                            infinite scroll, ResizeObserver, MutationObserver
                            ⭐ and why it beats the deprecated MutationEvents),
                            ⭐⭐ virtual scrolling / windowing (the technique,
                            the maths, when you need it — >1000 rows), the
                            content-visibility CSS property, Web Workers ⭐⭐
                            (the postMessage, the transferable objects, the
                            worker types, when to offload), ⭐⭐⭐ DOM MEMORY
                            LEAKS (detached nodes held by JS closures,
                            unremoved listeners, the setInterval that outlives
                            the component, the WeakMap/WeakRef solution, the
                            DevTools memory panel workflow), the DevTools
                            Performance panel and how to read a flame chart
  08-storage-navigation.md  ⭐⭐ localStorage vs sessionStorage vs cookies vs
                            IndexedDB — the full comparison table (capacity,
                            lifetime, scope, sent to server, sync/async, API).
                            The cookie attributes ⭐⭐ (HttpOnly, Secure,
                            SameSite and the CSRF story, Domain, Path,
                            Max-Age, Partitioned ⭐ the CHIPS change), the
                            StorageEvent for cross-tab sync, IndexedDB ⭐⭐
                            (the object store, the transactions, the cursors,
                            the async wrapper libraries and why you need one),
                            the Cache API and the Service Worker storage
                            model, ⭐⭐⭐ THE HISTORY API (pushState/
                            replaceState/popstate, the state object, the
                            same-origin restriction, ⭐ how SPA routing
                            actually works underneath, the scroll restoration,
                            the back-button contract), the Navigation API ⭐
                            (the modern replacement), BroadcastChannel
  09-internals.md           ⭐⭐⭐ the HTML parser and how the DOM is built
                            (tokenisation, tree construction, the insertion
                            modes, ⭐ the misnesting error recovery and why
                            `<p><div>` produces something you didn't write),
                            the speculative/preview parser and why it makes
                            script placement less critical than it was,
                            ⭐⭐⭐ the three task queues and the execution
                            order: the call stack → microtasks (Promise
                            callbacks, queueMicrotask, MutationObserver) →
                            the macrotask (setTimeout, I/O) → rAF → style/
                            layout/paint. With the ordering proof that prints
                            in the sequence nobody predicts. The main thread,
                            the compositor thread, the render-blocking
                            resources, the critical rendering path
                            optimisation
  10-cheatsheet.md          the selector table, the traversal table, the
                            event table, the attribute-vs-property table, the
                            storage table, the reflow-trigger list, the
                            leak checklist

javascript/ — 13 files
  01-the-language.md        what JavaScript is (⭐ ECMAScript the spec,
                            JavaScript the implementation), the engine
                            landscape (V8/SpiderMonkey/JavaScriptCore), the
                            TC39 process and the stages ⭐ (how a feature
                            gets in, and what "stage 3" means for you), the
                            transpilation question, ⭐ the browser JS vs the
                            Node.js JS (the same language, different host
                            APIs — and what that means for a Java developer),
                            the "JS is weird because the spec is weird and
                            the web can't break" framing, ⭐⭐ the Java →
                            JavaScript translation table (types, classes,
                            packages/modules, null, exceptions, collections,
                            concurrency)
  02-values-types.md        ⭐⭐ the 8 types (7 primitives + Object), the
                            primitive immutability, typeof and its THREE BUGS
                            (typeof null === 'object', typeof function ===
                            'function' though a function is an object, the
                            undeclared-variable no-throw), null vs undefined
                            (⭐ and nullish coalescing ?? vs ||), NaN and its
                            reflexivity (NaN !== NaN, use Number.isNaN),
                            ⭐⭐⭐ === vs == AND THE FULL COERCION TABLE (the
                            ToPrimitive algorithm, valueOf vs toString, the
                            [] + [] === '' and [] + {} === '[object Object]'
                            classics, why you should use === always and what
                            the one legitimate == null use is), truthiness
                            (⭐ the exact falsy list — there are 7... 8 with
                            document.all), the number type and IEEE 754
                            (0.1 + 0.2, the safe integer range, BigInt ⭐),
                            operator precedence and the associativity table,
                            ⭐ the + operator's dual behaviour and the
                            disaster it causes, the comparison operators and
                            string coercion, Symbol ⭐⭐ (the unique key, the
                            well-known symbols, the registry, why it exists)
  03-scope-closures.md      ⭐⭐⭐ var/let/const — the real differences
                            (function vs block scope, hoisting, the TDZ, the
                            redeclaration, the global-object property), the
                            Temporal Dead Zone with the proof, ⭐ HOISTING
                            (what actually moves — the declaration, not the
                            initialisation; function declarations fully
                            hoist, function expressions don't), the scope
                            chain and the lexical (static) scoping model,
                            ⭐⭐⭐ CLOSURES — the real definition (a function
                            bundled with its lexical environment), what they
                            capture (⭐ the VARIABLE, not the value — the
                            classic counter proof), ⭐⭐⭐ THE LOOP VARIABLE
                            BUG (`for (var i...)` with setTimeout — all
                            callbacks print 5) and its FOUR fixes (let, an
                            IIFE, forEach, a factory function), the memory
                            implications (⭐ a closure keeps the whole scope
                            alive — the leak), the module pattern, the IIFE
                            and its history, the private-field alternative,
                            the practical uses (partial application, memoisation,
                            the once function, the event handler with state)
  04-functions.md           ⭐⭐ declarations vs expressions vs ARROW
                            FUNCTIONS — the four differences that matter:
                            `this` (⭐⭐⭐ arrow has no own this, it inherits
                            lexically — the object-method-with-arrow bug and
                            the class-callback-with-function bug), arguments,
                            prototype, and constructability. The `this`
                            ⭐⭐⭐ FIVE RULES (default, implicit, explicit via
                            call/apply/bind, new, arrow/lexical) with a proof
                            program for each and the precedence order, the
                            lost-this problem (`const f = obj.method; f()`),
                            parameters (defaults and their evaluation timing,
                            rest, destructuring in parameters ⭐), the
                            arguments object (⭐ deprecated in arrow, and the
                            array-ness lie), call/apply/bind (⭐ bind's
                            partial application, the once-bound rule),
                            higher-order functions, callbacks and the
                            callback-hell preview, currying and partial
                            application, ⭐ pure functions and why they
                            matter for testing and for React, the function as
                            an object (name, length, the properties you can
                            attach)
  05-objects-prototypes.md  ⭐⭐⭐ object literals, the property shorthand,
                            the computed keys, the spread, the destructuring
                            (nested, defaults, rename, the rest, ⭐ the
                            function-parameter destructuring and its
                            default-parameter interaction), property
                            descriptors (writable/enumerable/configurable/
                            value, get/set, Object.defineProperty and why
                            you'd use it, the frozen/sealed/extensible
                            states), the Object static methods (keys/values/
                            entries/fromEntries/assign ⭐ and its shallow
                            copy, create, getPrototypeOf, groupBy ⭐),
                            ⭐⭐⭐ THE PROTOTYPE CHAIN — the model, __proto__
                            vs prototype vs constructor (⭐⭐ the diagram that
                            finally makes it clear), Object.getPrototypeOf,
                            the chain walk on property access, the shadowing,
                            Object.create, the delegation model, ⭐⭐⭐ CLASS
                            SYNTAX IS SUGAR (what it compiles to, the
                            differences from the function form — classes
                            don't hoist the same way, they're always strict,
                            they're not callable), the constructor, methods
                            on the prototype, static methods and fields,
                            ⭐ private fields (#x) and private methods and
                            the real encapsulation they give, the getters/
                            setters, extends and super (⭐⭐ super in the
                            constructor must come before this — and why),
                            the instanceof algorithm, the field-initialisation
                            order ⭐ (the class-fields-vs-constructor
                            assignment difference that breaks subclass
                            overrides — a genuinely subtle bug), the
                            mixin patterns, ⭐ PROTOTYPAL vs CLASSICAL
                            inheritance and the honest debate, the "favour
                            composition" conclusion
  06-arrays-iteration.md    ⭐⭐⭐ EVERY ARRAY METHOD, in a master table with:
                            mutates? / returns / complexity / ES version /
                            the trap. Then the deep treatment of each: the
                            iteration methods (forEach ⭐ and why you can't
                            break out of it, map, filter, find, findIndex,
                            findLast, some, every ⭐ and its short-circuit),
                            ⭐⭐⭐ reduce (the accumulator, the initial value
                            and why omitting it is a bug on an empty array,
                            the 8 patterns: sum, group, flatten, pipe, count,
                            unique, to-object, min/max), the mutation methods
                            (push/pop/shift/unshift ⭐ O(n), splice ⭐⭐ the
                            most-misused method, sort ⭐⭐⭐ the default
                            STRING sort of numbers, the comparator, the
                            stability guarantee since ES2019, reverse, fill,
                            copyWithin), the non-mutating (slice ⭐ vs splice,
                            concat ⭐ and its shallow flatten, join, at ⭐
                            the negative index, includes vs indexOf ⭐ and
                            NaN), flat/flatMap, the static (Array.of,
                            Array.from ⭐ with the map function, Array.isArray
                            ⭐ and why instanceof fails across realms),
                            ⭐⭐ destructuring (the swap, the skip, the rest,
                            the nested, the default), the spread, the
                            iteration protocols ⭐⭐ (Symbol.iterator, the
                            iterable vs array-like, writing your own
                            iterable, the generator function), for-of vs
                            for-in ⭐⭐⭐ (for-in is for OBJECT KEYS and
                            iterates the prototype chain and has no order
                            guarantee — using it on an array is a bug), the
                            generators (yield, the lazy sequence, the
                            delegation with yield*, the infinite sequence,
                            the use in async), ⭐ when to use a Map or Set
                            instead of an Array or Object (the key type, the
                            ordering, the size, the performance)
  07-async.md               ⭐⭐⭐ THE BIGGEST FILE IN THE FRONTEND FOLDER.
                            The event loop and the call stack (⭐ the single-
                            threaded model and why it's not a limitation),
                            ⭐⭐⭐ MACROTASKS vs MICROTASKS — the two queues,
                            the drain rule (ALL microtasks before the next
                            macrotask), and the ordering proof program that
                            prints in the sequence that surprises everyone
                            (setTimeout vs Promise.then vs queueMicrotask vs
                            process.nextTick vs rAF). Callbacks and the
                            pyramid of doom, the error-first callback
                            convention, ⭐⭐⭐ PROMISES — the three states, the
                            immutability of the resolution, the constructor
                            and the executor's synchronous execution ⭐ (the
                            trap), then/catch/finally and the chaining (⭐⭐
                            then RETURNS A PROMISE, which is why you can
                            chain; and the value-vs-promise flattening), the
                            error propagation (⭐ a catch returns a resolved
                            promise unless you rethrow — the silent-recovery
                            bug), the static combinators ⭐⭐⭐ (all / allSettled
                            / race / any — the semantics table, when each, and
                            the all-fails-fast problem with the fix),
                            ⭐⭐⭐ ASYNC/AWAIT — what it desugars to (a
                            generator + a promise runner), the sequential-
                            await-in-a-loop performance bug and the
                            Promise.all fix (with the numbers), the try/catch
                            and the error-handling patterns (the tuple
                            pattern, the wrapper function), the top-level
                            await, ⛔ the async-in-forEach bug (forEach
                            doesn't await), the unhandled rejection and the
                            global handlers, AbortController ⭐⭐ (cancelling
                            fetch, the signal propagation, the timeout
                            pattern), ⭐⭐⭐ FETCH — the API, the response
                            object (⭐ res.ok vs res.status, and the fact
                            that a 404 RESOLVES the promise), the body
                            methods (json/text/blob/arrayBuffer/formData/
                            stream), the request init, the headers, the CORS
                            preview and the modes, the timeout (there isn't
                            one — you build it), the retry with backoff, the
                            streaming response, ⭐ the fetch-vs-XHR history.
                            Concurrency control (⭐ the pool-of-N pattern, the
                            p-limit implementation), the async iteration
                            (for await...of, the async generator), the
                            Web Worker offload, ⭐ how all this maps to
                            Java's CompletableFuture and virtual threads —
                            the translation table for me
  08-modules-tooling.md     ⭐⭐⭐ ESM vs COMMONJS — the differences that
                            matter (static vs dynamic, the top-level await,
                            the this, the live bindings ⭐⭐ ESM exports are
                            LIVE READ-ONLY VIEWS, not copies — with the proof,
                            the circular-dependency behaviour in each), the
                            import/export forms (named, default ⭐ and why
                            default exports are controversial, namespace,
                            side-effect, re-export, the export-from), the
                            dynamic import() ⭐⭐ (code splitting, the lazy
                            load, the conditional load), the module graph and
                            the evaluation order, ⭐ the resolution algorithm
                            (the bare specifier, the node_modules walk, the
                            exports field and the subpath patterns), the
                            package.json (⭐ the fields that matter: type,
                            main, module, exports, sideEffects ⭐ and tree
                            shaking, dependencies vs devDependencies vs
                            peerDependencies ⭐⭐ and the versioning
                            semantics ^ ~ *), npm/pnpm/yarn (⭐ the
                            node_modules problem and how pnpm's symlink farm
                            fixes it), the lockfile, ⭐⭐ TREE SHAKING (what
                            it needs: ESM, no side effects, no dynamic
                            access; and what defeats it), the bundlers
                            (Vite ⭐⭐ the dev-server-with-esbuild-and-
                            Rollup model, esbuild, webpack and its config,
                            Rollup, Turbopack), TypeScript's place, the
                            monorepo (workspaces, Turborepo/Nx), the
                            environment variables (⭐ and why they're baked
                            into the bundle — the security consequence)
  09-errors-debug-testing.md the Error types (⭐ the full list and when each
                            is thrown), throwing properly (⭐ throw an Error,
                            not a string — the stack trace), the custom error
                            class, the error cause option ⭐, try/catch/
                            finally and the optional catch binding, the async
                            error handling, the unhandledrejection and
                            uncaughtexception handlers, ⭐⭐⭐ DEVTOOLS
                            MASTERY — the Sources panel (breakpoints, the
                            conditional breakpoint, the logpoint, the
                            debugger statement, the call stack, the scope
                            inspection, the closures view), the Network panel
                            (the waterfall, the request/response inspection,
                            the throttling, the HAR), the Performance panel
                            (the recording, the flame chart, the main-thread
                            breakdown), the Memory panel (the heap snapshot,
                            the comparison view, the detached-element hunt),
                            the Application panel, the Console beyond log
                            (table, dir, group, time, trace, count, the $ and
                            $$ helpers), source maps ⭐, ⭐⭐ TESTING — Vitest
                            (the API, the config, the watch mode), the test
                            types (unit, integration, E2E), mocking (the vi.fn,
                            the module mock, the timer mock, the fetch mock),
                            ⭐ MSW for API mocking, the coverage, the
                            testing philosophy (test behaviour not
                            implementation), Playwright for E2E, the test
                            pyramid for a frontend
  10-typescript.md          ⭐⭐ THE JAVA DEVELOPER'S BRIDGE — this file is
                            written for me specifically. The structural vs
                            nominal typing difference ⭐⭐⭐ (the biggest
                            mental shift: in Java a class IS a type; in TS a
                            type is a SHAPE and anything matching it
                            qualifies — with the duck-typing proof), the
                            primitives and their TS types (⭐ string not
                            String, the any/unknown/never/void/null/undefined
                            distinctions ⭐⭐⭐ and when each), the interface
                            vs type alias (⭐ the declaration merging, the
                            extends vs intersection, the honest answer:
                            interface for objects, type for everything else),
                            ⭐⭐⭐ GENERICS (the syntax, the constraints, the
                            defaults, the inference, the variance and the
                            in/out modifiers ⭐, the comparison with Java's
                            erasure — ⭐⭐ TS erases too, but at compile time,
                            and has NO runtime type information at all, so no
                            reflection and no `instanceof T`), the union and
                            intersection types, ⭐⭐ NARROWING (the type
                            guards, the typeof/instanceof/in guards, the
                            user-defined predicates with the `is` syntax, the
                            assertion functions, the discriminated unions
                            ⭐⭐⭐ and how they replace the Visitor pattern,
                            exhaustiveness checking with never), the utility
                            types (Partial/Required/Readonly/Record/Pick/Omit/
                            Exclude/Extract/ReturnType/Parameters/Awaited and
                            how each is implemented), the mapped types and the
                            conditional types ⭐⭐ (the `infer` keyword, the
                            distributive behaviour), the strict mode and every
                            flag in it (⭐⭐ strictNullChecks is the one that
                            matters), the enum ⛔ (and the const-object
                            alternative), the class features (the visibility
                            modifiers, the readonly, the abstract, the
                            implements, the parameter properties), the module
                            system, the declaration files and the @types,
                            ⭐ the tsconfig that matters, the migration path
                            from JS, the `any` escape hatches and their cost,
                            the type-safe API layer pattern
  11-the-platform.md        ⭐ the Web APIs a full-stack dev must know:
                            the WebSocket (the lifecycle, the message
                            framing, the heartbeat, the reconnection with
                            backoff, the vs SSE decision ⭐⭐), Server-Sent
                            Events (the EventSource, the auto-reconnect, the
                            one-way limitation, when it beats WebSocket), the
                            Service Worker ⭐⭐ (the lifecycle, the
                            registration, the fetch interception, the cache
                            strategies — cache-first/network-first/stale-
                            while-revalidate, the PWA manifest, the offline
                            model), Web Workers (the dedicated/shared/
                            service, the postMessage and the structured clone,
                            the transferable objects, the OffscreenCanvas),
                            IndexedDB (the wrapper libraries), the Streams
                            API ⭐ (the ReadableStream, the piping, the
                            streaming-response consumption), the Clipboard/
                            Geolocation/Notification/Intersection-Observer
                            APIs, the Web Crypto (the subtle API, the hashing,
                            the JWT verification in the browser ⭐), the
                            import maps, the Beacon API, the Page Visibility,
                            the BroadcastChannel, ⭐ the TC39 stage-3 features
                            of 2026 and what's landing
  12-internals.md           ⭐⭐⭐ HOW THE ENGINE RUNS YOUR CODE — for the
                            interview round. The pipeline: source → parse →
                            AST → the bytecode (Ignition) → the interpreter
                            → the profiling → the optimising compiler
                            (TurboFan) → the machine code → ⭐ DEOPTIMISATION
                            (the triggers: a hidden-class mismatch, a
                            polymorphic call site, an unexpected type — and
                            how to see it with --trace-deopt). ⭐⭐⭐ HIDDEN
                            CLASSES (the shape/structure/map, the transition
                            tree, WHY you should always initialise properties
                            in the same order in the constructor, the
                            delete-operator problem, the dynamic-property
                            problem). The inline caches (the monomorphic →
                            polymorphic → megamorphic degradation, and the
                            performance cliff — ⭐ the same story as the JVM's
                            megamorphic call site, and I should be able to say
                            that in an interview). The V8 GC (the generational
                            scavenger for the young generation, the mark-
                            sweep-compact for the old, the incremental and
                            concurrent marking, the ⭐ comparison with the
                            JVM's G1 — same ideas, different scale). The
                            memory model (the heap structure, the external
                            strings, the ArrayBuffer backing store). The
                            event loop internals (⭐ the libuv thread pool in
                            Node, the browser's equivalent). The number
                            representation (the SMI and the double, the
                            boxed heap number). The string internalisation.
                            ⭐ The Java-vs-JS runtime comparison table — this
                            is my interview superpower: I can compare a JIT to
                            a JIT.
  13-cheatsheet.md          the type coercion table, the this rules, the array
                            method table, the promise combinator table, the
                            event-loop ordering, the ESM/CJS table, the TS
                            utility types, the debugging checklist

react/ — 19 files
  01-the-mental-model.md    ⭐⭐⭐ WHY REACT AND WHAT IT ACTUALLY DOES. The
                            imperative → declarative shift, the UI = f(state)
                            equation, ⭐ the honest truth about the virtual
                            DOM (it's not a performance trick, it's a
                            programming-model trick — a batchable, declarative
                            description of the UI; Svelte and Solid prove you
                            don't need it for speed), the reconciliation and
                            the diffing heuristic (⭐ the three assumptions:
                            different types → different trees, keys stabilise
                            siblings, same type → update in place), the
                            component tree and the element tree (⭐ a React
                            element is an immutable description, NOT an
                            instance), the render phase vs the commit phase
                            ⭐⭐, the unidirectional data flow, ⭐ the
                            comparison with the DOM manipulation I learned in
                            folder dom/ — and why the mental model shift is
                            the hard part
  02-setup-structure.md     ⭐ Vite (and why Create React App is dead —
                            officially deprecated), the create commands, the
                            project anatomy, ⭐⭐ the folder structure that
                            scales (⭐ feature-based / feature-sliced vs the
                            type-based, the barrel-file problem and the
                            circular-import trap), the path aliases, the
                            environment variables (⭐ the VITE_ prefix and
                            the bundle-baking security consequence), ESLint
                            (⭐ the react-hooks plugin and why its rules are
                            correctness rules not style rules), Prettier, the
                            TypeScript setup, the absolute imports, when to
                            reach for Next.js instead
  03-jsx-components.md      ⭐⭐ JSX — what it is (syntax sugar for
                            createElement / the jsx runtime), what it compiles
                            to (show the output), the rules (one root, the
                            fragment, the closing tag, the camelCase
                            attributes, the {} expression slots and what's
                            allowed in them, ⛔ no statements — and the
                            IIFE/ternary/&& workarounds), the className and
                            htmlFor (⭐ why not class and for), the style
                            object, the boolean/null/undefined rendering
                            behaviour ⭐⭐ (false renders nothing — which is
                            why `{count && <X/>}` prints `0`), the spread
                            props ⭐ (and the ordering, and the security
                            implication), components (⭐ the capitalisation
                            rule and why lowercase is parsed as a DOM tag),
                            the props (⭐ read-only, the single-object
                            argument, the destructuring with defaults, the
                            children prop, ⭐⭐ the props-drilling smell and
                            its three fixes), composing components, the
                            component as a function of props, the TypeScript
                            props typing (⭐ the PropsWithChildren debate, the
                            FC type and why it fell out of favour)
  04-state-and-props.md     ⭐⭐⭐ useState — the anatomy, the setter (⭐ it
                            does NOT mutate, it schedules a re-render),
                            ⭐⭐⭐ THE STALE CLOSURE (three setState in a row
                            don't add up — because they all read the same
                            render's state; the functional-update fix; the
                            proof program), ⭐⭐ BATCHING (React 18 batches
                            EVERYTHING including promises and timeouts — what
                            changed and why), the state update as a
                            transaction, the immutability requirement ⭐⭐⭐
                            (why mutation doesn't trigger a re-render —
                            Object.is comparison; the correct update patterns
                            for objects, arrays, and nested structures; the
                            Immer option and its trade-off), ⭐ the state
                            design questions (what should be state at all?
                            the derived-state anti-pattern ⭐⭐ — if you can
                            compute it from props and state, don't store it;
                            the redundant-state and the duplicate-state
                            smells), ⭐⭐ LIFTING STATE UP (the technique, the
                            single source of truth, when it goes too far and
                            you need context or a store), controlled vs
                            uncontrolled components ⭐⭐ (the value/
                            defaultValue distinction, the ref escape hatch,
                            when each is right), the state colocation
                            principle ⭐⭐⭐ (keep state as close to where it's
                            used as possible — this is BOTH the readability
                            and the performance answer), the key as state
                            reset ⭐⭐ (remounting by changing the key — the
                            trick everyone learns too late), the initialiser
                            function form (⭐ lazy initial state for an
                            expensive computation), the useReducer preview
  05-rendering-lists.md     conditional rendering — the five ways (if/early
                            return ⭐ the recommended, the ternary, the &&
                            ⭐⭐ and its falsy-value trap with 0 and NaN, the
                            variable assignment, the object/switch map), and
                            ⛔ the `if` inside JSX which doesn't work.
                            ⭐⭐⭐ LISTS AND KEYS — why a key exists (the
                            reconciliation identity across renders), the
                            rules (stable, unique among siblings, NOT the
                            array index ⭐⭐⭐ and the three concrete bugs the
                            index causes: reordering breaks state, insertion
                            at the start breaks state, and the input-focus/
                            animation corruption — with the demo), the
                            legitimate index cases, the key from the data (an
                            id), the key-scope (siblings only), ⭐ the
                            key-as-remount trick. Rendering nothing (null,
                            the fragment, the early return), the list
                            performance (⭐ React does NOT virtualise — the
                            long-list problem and the windowing solution),
                            the render output rules
  06-events-forms.md        ⭐ the synthetic event system (React's own event
                            layer, the pooling that was removed in 17, the
                            delegation to the root ⭐⭐ and why e.stopPropagation
                            behaves differently than you expect, the native
                            event escape hatch), the handler naming, passing
                            arguments (⭐ the arrow-wrapper and the re-creation
                            cost, the data-attribute alternative, the curried
                            handler), the event object and its lifecycle,
                            ⭐⭐ FORMS — the controlled inputs (the value +
                            onChange contract, the single handler with the name
                            attribute, the state shape), the uncontrolled with
                            refs, the validation (⭐ the inline vs the
                            on-submit, the error state shape, the touched
                            tracking), the submit handling and the
                            preventDefault, the async submit and the pending
                            state, ⭐⭐⭐ the form architecture at scale (why
                            you reach for react-hook-form or Formik: the
                            re-render cost of a fully controlled large form,
                            the uncontrolled-with-validation model, the
                            schema validation with Zod/Yup, the field-level
                            subscription), the file input, the select and the
                            multi-select, the checkbox/radio groups, the
                            accessible form (the label, the aria-describedby,
                            the error announcement)
  07-hooks-deep.md          ⭐⭐⭐ THE DEEPEST FILE IN THE FRONTEND FOLDER.
                            ⭐⭐⭐ THE RULES OF HOOKS AND WHY THEY EXIST — the
                            linked-list-of-hook-state implementation, the
                            call-order dependence, the two rules (top level
                            only, only in components/custom hooks), the ESLint
                            enforcement, what breaks if you violate them.
                            useState (deep, cross-ref 04), ⭐ useReducer (the
                            dispatch, the reducer purity, the action typing,
                            WHEN it beats useState ⭐⭐ — complex state logic,
                            multiple sub-values, the next state depending on
                            the previous, the testability win, the Redux
                            preview), ⭐⭐⭐ useEffect — the big one. The
                            mental model correction: it is NOT
                            componentDidMount/DidUpdate/WillUnmount, it is
                            "synchronise with an external system after the
                            commit". The dependency array ⭐⭐⭐ (the three
                            cases: omitted = every render, [] = once, [deps] =
                            when they change; the exhaustive-deps rule and why
                            it's a CORRECTNESS lint not a style lint; the
                            stale-closure bug from a missing dep, with the
                            interval-counter proof), the cleanup function
                            (⭐⭐ the timing: cleanup of render N runs before
                            the effect of render N+1; the unsubscribe/abort/
                            clearTimeout uses; the unmount cleanup), ⭐⭐⭐ THE
                            "YOU MIGHT NOT NEED AN EFFECT" DOCTRINE — the
                            derived-state-in-an-effect anti-pattern, the
                            fetching-in-an-effect anti-pattern (cross-ref 08),
                            the responding-to-user-input-in-an-effect
                            anti-pattern, the notifying-parent-in-an-effect
                            anti-pattern, the chains-of-effects smell, and
                            what to do instead (compute during render, handle
                            in the event handler, lift it up). The
                            StrictMode double-invocation ⭐⭐ (why it happens,
                            what it's testing, and the "my effect runs twice"
                            question that is really "my effect isn't
                            idempotent"). useRef ⭐⭐ (the mutable box that
                            doesn't trigger a render, the DOM node access, the
                            previous-value pattern, the interval-id holder,
                            ⛔ don't use it for render-affecting state),
                            useMemo/useCallback ⭐⭐⭐ (what they do, ⭐⭐ WHEN
                            THEY HURT — the memoisation cost itself, the
                            dependency array cost, the memory cost; the three
                            legitimate uses: an expensive computation, a
                            referentially-stable value passed to a memo'd
                            child, a referentially-stable dependency of
                            another hook; ⛔ the "add memo everywhere" cargo
                            cult), useContext ⭐⭐ (the API, the re-render
                            problem — ⭐⭐ EVERY consumer re-renders when the
                            value changes, the splitting-context fix, the
                            state+dispatch split), useId, useTransition ⭐⭐
                            (the urgent vs non-urgent update, the isPending,
                            the Suspense interaction, the real use cases),
                            useDeferredValue ⭐⭐ (and how it differs from
                            transition), useSyncExternalStore ⭐⭐ (the
                            external-store subscription, the getSnapshot
                            contract, the tearing problem it solves, why every
                            state library uses it), useOptimistic, use()
                            ⭐⭐ (the promise and context reading, the Suspense
                            integration), ⭐⭐⭐ CUSTOM HOOKS — the real reuse
                            mechanism, the naming, the rules (a hook can call
                            hooks), the return shape, the 10 custom hooks
                            every app needs (useDebounce, useLocalStorage,
                            useFetch, useMediaQuery, useOnClickOutside,
                            usePrevious, useInterval, useEventListener,
                            useToggle, useAsync) — each fully implemented and
                            commented, ⭐ the custom hook vs the utility
                            function vs the component decision
  08-data-fetching.md       ⭐⭐⭐ WHY fetch-IN-useEffect IS THE WRONG
                            DEFAULT — the race condition (two requests, the
                            slower one wins, the wrong data renders — the
                            proof), the waterfall (⭐⭐ the component-fetches-
                            on-mount cascade and why it's the biggest
                            performance problem in React apps), the missing
                            cache, the missing deduplication, the missing
                            retry, the missing loading/error state
                            discipline, the AbortController cleanup. The
                            correct primitives: ⭐⭐⭐ TanStack Query (the
                            useQuery/useMutation, the queryKey as the cache
                            key ⭐⭐ and the key-design discipline, the
                            staleTime vs cacheTime/gcTime ⭐⭐⭐ the two timers
                            everyone confuses, the invalidation, the
                            optimistic updates with rollback, the pagination
                            and the infinite query, the prefetch, the
                            devtools), SWR (the revalidate-on-focus model),
                            the RTK Query alternative, ⭐⭐⭐ SERVER STATE vs
                            CLIENT STATE — the distinction that reorganises
                            your whole app: server state is a CACHE OF SOMEONE
                            ELSE'S TRUTH (it can go stale, you don't own it,
                            it needs synchronisation), client state is yours
                            (the theme, the form draft, the UI panel). Most
                            "state management" problems are server-state
                            problems in a client-state tool. Then ⭐⭐ React
                            Server Components and the framework shift (the
                            data-fetching-in-the-component model, the
                            loader/action pattern in React Router v7 and
                            Next.js, the streaming, and the honest "is this
                            the right architecture for my app" analysis)
  09-state-management.md    ⭐⭐⭐ THE DECISION FILE. The prop-drilling
                            problem and its real cost, Context ⭐⭐ (the API,
                            the Provider, ⭐⭐⭐ THE RE-RENDER PROBLEM — the
                            context value's referential identity, every
                            consumer re-renders on every provider render, the
                            memo-the-value fix, the split-context fix, the
                            selector pattern that Context can't do), when
                            Context IS right (low-frequency, app-wide,
                            read-mostly: theme, auth, locale, feature flags),
                            when it ISN'T (high-frequency state, per-item
                            state, anything with selectors), ⭐ useReducer +
                            Context (the poor-man's Redux, the dispatch-
                            stability trick, the limits), ⭐⭐⭐ THE LIBRARY
                            LANDSCAPE with an honest comparison table: Redux
                            Toolkit (the store, the slice, the immer
                            integration, the thunk, the RTK Query, ⭐ when it
                            is still the right answer: large teams, complex
                            cross-cutting state, the devtools and time-travel,
                            the audit trail), Zustand (⭐ the simplicity, the
                            selectors, the middleware, why it won the 2024-
                            2026 default), Jotai (the atomic model, the
                            derived atoms), Valtio (the proxy model), MobX
                            (the observable model, ⭐ and the Java-developer
                            familiarity), XState (⭐⭐ the state machine — and
                            why an LLD person should love it: it makes the
                            state model explicit and the impossible
                            transitions unrepresentable), Signals (⭐ the
                            2026 direction, the fine-grained reactivity, the
                            TC39 proposal, the Solid/Preact/Angular
                            convergence), ⭐⭐⭐ THE DECISION TREE: server
                            state → TanStack Query. URL state → the router.
                            Form state → the form library. Local UI state →
                            useState/useReducer. Cross-cutting app state →
                            Context. Complex shared client state → Zustand or
                            RTK. Stateful workflows → XState. ⭐ AND THE
                            SDE 3 ANSWER: "most apps need less state
                            management than they think — the problem is
                            usually state that shouldn't exist."
  10-routing.md             ⭐⭐ React Router v7 (the framework mode and the
                            library mode ⭐ and what changed from v6), the
                            route configuration (the JSX and the data-API
                            object forms), the nested routes and the Outlet
                            ⭐⭐ (the layout route pattern), the dynamic
                            segments and the useParams, the splat routes, the
                            route ranking (⭐ how RR picks the best match —
                            it's not first-match), the Link/NavLink (⭐ the
                            active class, the prefetch), the programmatic
                            navigation (useNavigate, ⭐ and the navigate-in-
                            an-effect anti-pattern), the search params ⭐⭐⭐
                            (useSearchParams and the "URL as state" pattern —
                            filters, pagination, sort, and the modal state all
                            belong in the URL; the shareable-bookmarkable-
                            back-button-correct argument), the loaders and
                            actions ⭐⭐ (the data router, the deferred data,
                            the errorElement, the pending states), the
                            protected route (⭐ the auth guard, the redirect,
                            the token refresh interplay), the lazy route and
                            the code splitting, the 404, the scroll
                            restoration, ⭐ the SPA-routing vs the framework-
                            routing decision, the Next.js App Router
                            comparison (the file-system routes, the server
                            components, the layouts, the loading.js and
                            error.js conventions)
  11-styling.md             ⭐⭐ the options and the honest trade-offs: plain
                            CSS (the global namespace problem), CSS Modules
                            ⭐ (the scoping, the composition, the naming,
                            when it's the right default), ⭐⭐⭐ Tailwind (the
                            utility model, the JIT, the design-token
                            constraint, the honest cost analysis: the HTML
                            noise, the learning curve, the design-system
                            enforcement, the purge/content config, the
                            @apply and when it's a smell, the component
                            extraction debate, ⭐ WHY IT WON and why some
                            teams correctly refuse it), CSS-in-JS ⭐⭐ (the
                            runtime model and its cost, styled-components/
                            Emotion, ⭐⭐ the death of runtime CSS-in-JS in
                            the RSC era and why — you can't run a runtime
                            library on the server component), the zero-runtime
                            alternatives (vanilla-extract ⭐, Panda CSS,
                            Linaria), the component libraries (shadcn/ui ⭐⭐
                            the copy-the-source model and why it's clever,
                            MUI, Ant Design, Chakra, Radix and the headless
                            model ⭐), the design system approach (⭐ the
                            tokens, the theming, the dark mode with the
                            CSS custom property swap and the class strategy,
                            the responsive discipline), the CSS architecture
                            for a React app (⭐ the layering: reset → tokens
                            → base → components → utilities), the animation
                            libraries (Framer Motion ⭐, the CSS-first
                            argument), the styling performance (⭐ the
                            critical CSS, the FOUC, the CLS metric)
  12-performance.md         ⭐⭐⭐ THE MEASUREMENT-FIRST FILE. WHY A COMPONENT
                            RE-RENDERS — the three and only three triggers
                            (its own state changed, its parent re-rendered ⭐⭐
                            and this is the one everyone misses, its context
                            changed), the render ≠ DOM update distinction
                            (⭐ React re-renders, then reconciles, then maybe
                            commits — a re-render is often free), ⭐⭐ THE
                            PROFILER — the React DevTools Profiler, the
                            "record why each component rendered" setting, the
                            flamegraph and the ranked view, the commit
                            inspection, how to actually find the problem
                            instead of guessing. The tools and their real
                            limits: React.memo ⭐⭐ (the shallow prop
                            comparison, the referential-equality trap — a new
                            object/array/function prop defeats it, which is
                            why useCallback/useMemo exist, ⛔ the
                            memo-everywhere cargo cult and its cost),
                            useMemo/useCallback (cross-ref 07), ⭐⭐⭐ STATE
                            COLOCATION AND COMPOSITION — the best performance
                            tools in React and they're not APIs: move the
                            state down, move the children up (⭐ the
                            children-as-props trick that stops a subtree
                            re-rendering, with the proof), the content
                            projection pattern. ⭐⭐ LIST VIRTUALISATION (the
                            windowing, react-window/TanStack Virtual, the
                            measurement, the dynamic-height problem, when you
                            need it: >1000 rows or expensive rows), ⭐ CODE
                            SPLITTING (React.lazy + Suspense, the route-level
                            split, the component-level split, the
                            preload-on-hover, the bundle analysis with
                            rollup-plugin-visualizer), the image and asset
                            optimisation, ⭐⭐ SUSPENSE (what it actually is —
                            a declaration that a subtree isn't ready, the
                            fallback, the nested Suspense boundaries and the
                            reveal strategy, the error boundary interaction),
                            ⭐⭐⭐ THE REACT COMPILER (what it does — automatic
                            memoisation via compilation, the rules it requires,
                            the migration, whether you still need useMemo),
                            the reconciliation cost and how to reduce it (the
                            key stability, the tree shape), the bundle size
                            budget, ⭐ THE MEASUREMENT WORKFLOW (the
                            Lighthouse, the Web Vitals library, the RUM, the
                            LCP/INP/CLS ⭐⭐ and the 2024 INP replacement of
                            FID), the before/after case study with real
                            numbers, ⭐ the honest conclusion: most React
                            performance problems are (1) too much state too
                            high up, (2) fetching waterfalls, (3) unvirtualised
                            lists — not missing memos
  13-errors-testing.md      ⭐⭐ ERROR HANDLING — the error boundary (the
                            class component requirement and why ⭐, the
                            getDerivedStateFromError vs componentDidCatch, what
                            it CATCHES ⭐⭐ — render/lifecycle/constructor of
                            the tree below, and what it DOESN'T — event
                            handlers, async code, SSR, itself), the
                            boundary placement strategy (⭐ per-route,
                            per-widget, the graceful-degradation design), the
                            fallback UI, the react-error-boundary library, the
                            reset-on-navigation, ⭐ the Suspense boundary
                            placement, the async error handling (the event
                            handler try/catch, the query error state, the
                            router errorElement), the global handler, the
                            error reporting (Sentry and the sourcemap upload),
                            ⭐⭐ THE FOUR UI STATES — loading, error, empty,
                            success. The discipline that separates a junior
                            app from a senior one. The skeleton, the retry,
                            the empty-state design, the partial failure.
                            ⭐⭐⭐ TESTING — the philosophy (test BEHAVIOUR
                            that a user can observe, not implementation
                            details — ⭐ the "if you refactor the internals
                            without changing behaviour, your tests must still
                            pass" rule), React Testing Library (the queries
                            and their priority order ⭐⭐ getByRole first, and
                            why; the user-event over fireEvent ⭐ and the
                            realistic-event argument; the async utilities
                            findBy/waitFor and ⛔ the arbitrary-timeout
                            waitFor), the render and the screen, the mocking
                            (⭐⭐ MSW for the network — the handler, the
                            request matching, the browser vs the Node
                            integration, and why it beats mocking fetch),
                            the test patterns (the form submission, the
                            navigation, the error state, the loading state,
                            the auth flow), the hook testing
                            (renderHook), the context testing, the snapshot
                            test ⛔ (and why it's mostly useless), the
                            coverage and its limits, ⭐ the E2E with Playwright
                            (the page object, the auth state reuse, the
                            network interception, the visual regression), the
                            test pyramid for a React app, the CI integration
  14-patterns-architecture.md ⭐⭐⭐ THE SDE 3 FILE — the patterns and the
                            architecture, not the API. THE COMPONENT PATTERNS:
                            the container/presentational split (⭐ its history
                            and its modern replacement — hooks did the job),
                            the compound components ⭐⭐ (the Select/Option,
                            the Tabs/TabList/Tab pattern, the implicit state
                            sharing via context, the API design lesson), the
                            render props (⭐ its history, and where it
                            survives: the headless component), the HOC (⛔
                            legacy, and the props-collision and the
                            composition problems that killed it), the
                            controlled/uncontrolled duality ⭐⭐ (and the
                            `value ?? defaultValue` API design), the headless
                            component ⭐⭐ (the logic-without-markup, the
                            render-prop or the hook API, Radix/React Aria and
                            why this is the a11y-correct architecture), the
                            slot/children-projection pattern, the polymorphic
                            component ⭐ (the `as` prop and its TypeScript),
                            the recursive component (the tree, the comment
                            thread), the portal ⭐ (createPortal, the modal
                            and the tooltip, the event bubbling through the
                            React tree not the DOM tree ⭐⭐). THE ARCHITECTURE:
                            ⭐⭐⭐ the folder structure at scale (the
                            feature-sliced design, the layers: app/pages/
                            widgets/features/entities/shared, the dependency
                            rule — ⭐ it's Clean Architecture applied to a
                            frontend, and I should be able to say that), the
                            barrel files and the circular-dependency trap,
                            ⭐⭐ the API layer abstraction (the client, the
                            interceptors, the error normalisation, the types
                            generation from the OpenAPI spec ⭐, the
                            repository pattern in the frontend), the
                            dependency injection in React (context as a
                            container, the composition-root, why you'd bother),
                            the error/loading/empty/success state architecture,
                            ⭐ the optimistic UI pattern (the mutation, the
                            rollback, the reconciliation), the infinite scroll
                            and the cursor pagination, the undo/redo, the
                            feature flags, the i18n (the message extraction,
                            the pluralisation, the ICU syntax, the
                            react-intl vs i18next decision), the theming
                            architecture, the form architecture at scale,
                            ⭐⭐ the state-machine approach to complex flows
                            (the checkout, the onboarding — and how XState
                            makes impossible states unrepresentable, which is
                            the LLD argument applied to a frontend), the
                            monorepo and the shared packages, the micro-
                            frontend question ⭐ (and the honest "usually
                            don't"), the design-system package, ⭐⭐ THE
                            NAMING AND THE ABSTRACTION DISCIPLINE — the same
                            SDE 3 judgement as in the Java LLD file
  15-accessibility.md       ⭐⭐ a11y in React specifically: the JSX
                            attribute mapping (htmlFor, aria-*), the
                            keyboard handling (⭐ the onKeyDown, the roving
                            tabindex, the focus trap for modals, the
                            focus restore on close), the focus management on
                            route change ⭐⭐ (the SPA problem, the
                            scroll-restoration, the heading announcement),
                            the aria-live for the async updates ⭐ (the
                            "results updated" announcement), the
                            accessible naming (the label, the
                            aria-labelledby, the accessible-name computation),
                            the icon-button problem, the form error
                            association, the ⭐ react-hooks for a11y
                            (the useFocusTrap, the useAnnounce), the testing
                            (axe-core, the jest-axe, the keyboard-only manual
                            test, the screen-reader test), the WCAG conformance
                            and the legal reality, the top-20 React a11y bugs
  16-server-rendering.md    ⭐⭐⭐ the rendering strategies and the decision:
                            CSR (the SPA, the blank page, the JS cost), SSR
                            (the server renders HTML per request, the
                            hydration, the TTFB cost), SSG (build time, the
                            staleness), ISR (the revalidation, the stale-while-
                            revalidate), streaming SSR (the Suspense
                            boundaries on the server, the progressive
                            reveal), ⭐⭐⭐ REACT SERVER COMPONENTS — the model
                            (a component that runs ONLY on the server, sends
                            a serialised element tree, ships zero JS), what it
                            fixes (the bundle size, the data access, the
                            waterfall), what it costs (the mental model, the
                            "use client" boundary discipline ⭐⭐ and where
                            the boundary goes, the ecosystem compatibility),
                            the RSC + hooks rules (⭐ no state, no effects, no
                            browser APIs in a server component), the
                            async component, the server actions ⭐⭐ (the
                            form mutation, the progressive enhancement),
                            ⭐⭐ HYDRATION — what it is, the cost, the
                            hydration mismatch error and its causes, the
                            selective/progressive/islands hydration, the
                            resumability idea (Qwik) and why it matters, the
                            framework landscape (Next.js App Router, Remix/
                            React Router v7, Astro ⭐ the islands, Vite SSR),
                            🔑 the honest SDE 3 answer: "do you need SSR?
                            Only if you need SEO, or a fast first paint on a
                            slow device, or a large bundle. An internal
                            dashboard doesn't."
  17-react-internals.md     ⭐⭐⭐ THE INTERVIEW-EDGE FILE. FIBER — the
                            architecture, the work-in-progress tree, the fiber
                            node structure (the child/sibling/return pointers,
                            the stateNode, the flags), WHY React rewrote the
                            stack reconciler (⭐ the synchronous recursion
                            couldn't be interrupted — and interruptibility is
                            the whole point of concurrent React), the
                            reconciliation as a unit-of-work loop, the render
                            phase (⭐ interruptible, no side effects) vs the
                            commit phase (⭐ synchronous, three sub-phases:
                            before mutation, mutation, layout), the effect list
                            and the passive effects (⭐ why useEffect runs
                            AFTER the paint, and useLayoutEffect before it —
                            and the flicker consequence), the double-buffering
                            of the tree, the alternate pointers. THE SCHEDULER
                            — the lanes ⭐⭐ (the priority model, the
                            bit-flag lanes, the batching per lane, the
                            starvation and the lane promotion), the
                            time-slicing, the MessageChannel-based scheduler
                            (⭐ why not setTimeout — the 4ms clamp), the
                            concurrent features and what they're built on
                            (useTransition = a low-lane update, Suspense = a
                            thrown promise, the offscreen/Activity API).
                            ⭐ HOW SUSPENSE ACTUALLY WORKS — the thrown
                            promise, the boundary's catch, the retry on
                            resolution, the `use()` hook and the React Cache,
                            the "it's an exception, not a state" revelation.
                            THE HOOKS IMPLEMENTATION ⭐⭐ — the memoizedState
                            linked list, the dispatch queue, why the order
                            matters (and the rules of hooks are not arbitrary),
                            the mount vs update dispatchers, the
                            useState/useReducer shared implementation.
                            THE SYNTHETIC EVENT SYSTEM (the delegation to the
                            root container, the plugin system, the event
                            priority mapping to lanes). THE JSX RUNTIME (the
                            automatic runtime, the React.element structure,
                            the key/ref extraction, the freezing in dev).
                            ⭐⭐⭐ THE COMPARISON TABLE — React vs Vue vs
                            Svelte vs Solid: the reactivity model, the
                            granularity, the compilation strategy, the
                            performance profile, the mental model. And the
                            SDE 3 answer to "why React": the ecosystem, the
                            hiring pool, the maturity of the concurrent model,
                            the RSC bet — and the honest counter-arguments.
  18-cheatsheet.md          the hooks table (signature, deps, when, trap), the
                            re-render triggers, the performance checklist, the
                            state-management decision tree, the query keys,
                            the a11y checklist, the JSX gotchas, the
                            useEffect decision flowchart, the testing query
                            priority, the error-boundary matrix
  19-projects-index.md      the index of the 15 projects with the concepts
                            each teaches and the order to build them in

frontend/projects/ — ⭐⭐ 15 PROJECTS, EACH ITS OWN FILE
  ONE-LINE each. Every project: the brief, the requirements (functional +
  non-functional), the UML/component tree, the folder structure, the FULL
  commented source, the tests, the accessibility checklist, the Lighthouse
  target, the "what this taught me", the extensions, and the interview line.
  F1  01-landing-page.md — HTML+CSS only. Responsive, accessible, semantic,
      Lighthouse 95+. Teaches: the document, the cascade, flexbox, grid, the
      a11y tree, the responsive images.
  F2  02-dashboard-layout.md — CSS Grid + Flexbox, a full admin shell with a
      sidebar, a header, a widget grid, dark mode, container queries.
      Teaches: grid, custom properties, the layer architecture.
  F3  03-vanilla-todo.md — no framework. The DOM, events, delegation,
      localStorage, the render function, the state object. ⭐ The point:
      understand what React does for you by doing it once by hand.
  F4  04-vanilla-gallery.md — fetch, the IntersectionObserver infinite scroll,
      the modal with a focus trap, the URL state, the AbortController.
      Teaches: async JS, the platform APIs, the a11y modal.
  F5  05-react-counter-to-cart.md — the first React apps: state, props,
      events, lists, lifting state. Ten small apps in one file, each 30-80
      lines. Teaches: the mental model shift.
  F6  06-react-shop-storefront.md ⭐⭐ — THE BIG ONE, PART 1. The product
      list with filters, search, sort, and pagination — all in the URL.
      TanStack Query against the Spring Boot shop-api. Teaches: data
      fetching, the URL as state, the four UI states, the loading skeletons.
  F7  07-react-admin-panel.md ⭐⭐ — the CRUD admin: a data table with
      sorting/pagination/selection, a create/edit form with Zod validation,
      optimistic updates with rollback, bulk actions, the role-based UI.
      Teaches: forms at scale, mutations, the optimistic pattern.
  F8  08-react-realtime-tracker.md ⭐⭐ — the live order tracker: WebSocket
      and SSE, the reconnection with backoff, the live status timeline, the
      toasts, the presence. Teaches: real-time, the external store, the
      useSyncExternalStore.
  F9  09-react-checkout-wizard.md ⭐⭐ — the multi-step checkout: the complex
      form state with react-hook-form, the cross-step validation, the
      persistence, the back/forward, the payment step, the order
      confirmation, the XState state machine version and the comparison.
      Teaches: complex state, the state machine, the flow architecture.
  F10 10-react-analytics-dashboard.md ⭐⭐ — charts and filters: the chart
      library, the date-range picker, the filter panel, the TanStack Query
      caching and the staleTime strategy, the export, the responsive chart.
      Teaches: server state, the derived state, the visualisation.
  F11 11-react-kanban.md ⭐⭐ — the drag-and-drop board: the DnD library, the
      optimistic reorder, the undo, the column virtualisation, the
      collaborative presence. Teaches: the optimistic UI, the complex
      interaction, the undo/redo.
  F12 12-react-nested-comments.md — the recursive comment tree: the recursive
      component, the infinite depth, the collapse, the reply form, the
      optimistic insert, the virtualisation of a tree. Teaches: recursion,
      the tree data structure in the UI.
  F13 13-react-auth-flow.md ⭐⭐ — the complete auth: login, register, the
      password reset, the JWT and the refresh token rotation ⭐⭐ (and the
      storage question: httpOnly cookie vs localStorage — the XSS vs CSRF
      trade-off, an SDE 3 conversation), the protected routes, the role-based
      UI, the session expiry, the "remember me". Teaches: security, the
      routing guard, the token lifecycle.
  F14 14-react-performance-case-study.md ⭐⭐⭐ — take a deliberately slow app
      (10,000-row table, no memo, state at the root, an unsplit bundle, a
      fetch waterfall) and make it fast, MEASURING EACH STEP with the Profiler
      and Lighthouse. Teaches: performance as a discipline, the measurement
      workflow, the honest cost/benefit of each optimisation.
  F15 15-react-full-shop-frontend.md ⭐⭐⭐ — THE CAPSTONE. The production
      shop frontend: routing, auth, catalogue, search with debounce and
      suggestions, cart with persistence, checkout, order history, the user
      account, the admin panel, the error boundaries, the a11y pass, the test
      suite (unit + integration + E2E), the Dockerfile, the CI, Lighthouse
      95+, connected to the Spring Boot backend from folder 07. This is the
      project I put on my resume and talk about for 20 minutes.

───────────────────────────────────────────────────────────────────────────────
FOLDERS 3–7 — SAME TREATMENT, DEEP SPEC
───────────────────────────────────────────────────────────────────────────────
For each of these folders: a README with a one-line explanation per file, a
00-ONE-DAY-MASTER-PLAN, the numbered files, a PROJECTS file, a CHEATSHEET, and
the four practice sets in every file. Depth to the same standard as Folder 1.

FOLDER 03 — 03-jdbc-deep (production JDBC)
  01-the-jdbc-architecture-deep  the SPI, the DriverManager internals, the
      DataSource, the driver's actual work, the wire protocol preview
      (⭐ the MySQL/PostgreSQL protocol and what a round trip costs — the
      number that explains connection pooling)
  02-connection-pooling ⭐⭐⭐  HikariCP internals (the ConcurrentBag ⭐⭐⭐ —
      the thread-local fast path, the handoff queue, the why-it's-fastest
      analysis), the pool sizing mathematics (⭐⭐ the queueing theory, why a
      smaller pool is faster, the Little's Law derivation), the config that
      matters (maximumPoolSize, minimumIdle, connectionTimeout,
      maxLifetime ⭐ and the DB-side timeout interaction, keepaliveTime, the
      leakDetectionThreshold), ⭐ the exhausted-pool incident walkthrough
      ("Connection is not available, request timed out after 30000ms" — the
      seven causes and the diagnosis for each), the alternatives (DBCP2,
      c3p0, the Tomcat pool) and the comparison
  03-transactions-and-isolation ⭐⭐⭐  the ACID mechanics, the isolation
      levels and the anomalies — ⭐⭐ with RUNNABLE TWO-CONNECTION DEMOS of a
      dirty read, a non-repeatable read, and a phantom read, the vendor
      defaults and the SI (snapshot isolation) that PostgreSQL and MySQL
      InnoDB actually implement, ⭐ SERIALIZABLE and its cost, the
      optimistic vs pessimistic locking (SELECT FOR UPDATE, the NOWAIT and
      SKIP LOCKED ⭐⭐ and the queue-table pattern), the deadlock (the
      detection, the retry, the lock ordering), the distributed transaction
      and the 2PC/XA (⭐ and why nobody does it — the Saga alternative), the
      transaction boundary design ⭐⭐ (where does @Transactional go and why
      not on the controller)
  04-batch-and-bulk ⭐⭐  the JDBC batch, the rewriteBatchedStatements
      benchmark, the COPY protocol in PostgreSQL ⭐⭐ (the 100× path), the
      bulk update strategies, the upsert, the pagination at scale, the
      streaming ResultSet, the memory profile of each
  05-schema-and-migrations ⭐⭐  Flyway and Liquibase (the comparison, the
      versioned vs repeatable migrations, the checksum validation, the
      baseline), ⭐⭐⭐ THE EXPAND-CONTRACT PATTERN (add the column →
      dual-write → backfill → switch reads → drop the old — the zero-downtime
      migration, drawn and scheduled), the locking DDL takes (⭐ ALTER TABLE
      and the metadata lock that blocks your whole table), the online schema
      change tools (gh-ost, pt-online-schema-change), the migration testing
  06-error-handling-and-resilience ⭐⭐  the SQLException hierarchy and the
      SQLState classes, the retryable vs fatal classification, the retry with
      exponential backoff and jitter ⭐, the idempotency key ⭐⭐⭐ (the
      pattern, the storage, the dedup window), the circuit breaker, the
      timeout discipline (⭐⭐ the four timeouts: connect, socket, statement,
      transaction — and the one everyone forgets), the graceful degradation
  07-the-repository-layer ⭐⭐⭐  the full architecture: the domain model vs
      the persistence model, the mapper, the repository interface, the
      implementation, the unit-of-work, the transaction script vs the domain
      model, the generic repository, the specification pattern, ⭐ the
      hexagonal architecture placement (the repository is a PORT; JDBC is the
      ADAPTER — cross-reference 02B), the complete shop persistence layer
  08-testing-and-observability ⭐⭐  Testcontainers ⭐⭐⭐ (the lifecycle, the
      singleton-container pattern, the @ServiceConnection, the reuse, the
      startup cost and how to amortise it), the test data strategy (the
      builder, the fixture, the factory), the transactional test and the
      rollback, the database assertion (AssertJ, the DBUnit alternative), the
      JDBC metrics with Micrometer ⭐ (the pool metrics, the query timings,
      the slow-query log), the query plan reading (EXPLAIN ANALYZE ⭐⭐ — read
      a plan properly: the seq scan, the index scan, the nested loop, the
      hash join, the rows estimate vs actual), the p6spy/datasource-proxy
      logging
  09-PROJECTS  5 projects: a connection pool from scratch (expanded from
      Core Java P9), a migration runner, a read-replica router, a
      multi-tenant data layer (⭐ the three isolation strategies), a
      high-throughput ingest pipeline
  10-CHEATSHEET

FOLDER 04 — 04-jsp-servlets
  Framing ⭐: you learn this to UNDERSTAND what Spring MVC automates, and to
  maintain the estate you'll meet. Be explicit that nobody builds new JSP.
  01-the-servlet-lifecycle ⭐⭐  the container, the Servlet interface, init/
      service/destroy, the load-on-startup, the single-instance-multi-thread
      model ⭐⭐⭐ (ONE servlet instance, MANY threads — so instance fields are
      shared state, and that's the bug), the GenericServlet, the
      HttpServlet's service dispatch, the ServletConfig vs ServletContext,
      the thread-safety rules (⛔ never an instance field for request data),
      the SingleThreadModel and why it was deprecated
  02-request-and-response  the HttpServletRequest (every getter, the
      parameters vs attributes ⭐⭐ the distinction everyone misses, the
      headers, the cookies, the pathInfo/queryString decomposition), the
      HttpServletResponse (the status codes, the headers, the writer vs the
      output stream ⭐ and the can't-use-both rule, the redirect, the
      buffering and the commit point ⭐⭐ IllegalStateException after commit),
      the encoding, the async servlet ⭐⭐ (startAsync, the AsyncContext, the
      non-blocking I/O, and how this became the foundation of reactive
      servlets and the CompletableFuture integration)
  03-session-management ⭐⭐⭐  HttpSession, the session creation and the
      invalidation, the session id, ⭐⭐ THE FOUR TRACKING MECHANISMS (the
      cookie JSESSIONID, URL rewriting, SSL session id, the hidden form
      field) and the encodeURL, the session timeout and the listener, the
      session fixation attack ⭐⭐ and the defence (change the id on login),
      the distributed session (the sticky session, the session replication,
      the external store — Redis/Spring Session ⭐ and the cross-reference to
      folder 07), the session-scoped attribute memory leak, the cookie
      attributes ⭐⭐ (HttpOnly, Secure, SameSite — the CSRF defence)
  04-filters-and-listeners ⭐⭐⭐  the Filter interface, the FilterChain ⭐⭐
      (this IS the Chain of Responsibility pattern — cross-reference 02B, and
      it IS what Spring Security is), the filter ordering, the
      dispatcherTypes, the real filters (the encoding filter, the CORS
      filter, the logging/MDC filter, the auth filter, the compression
      filter, the rate-limit filter — ⭐ write each one), the listeners (the
      8 types: context/attribute/session/request listeners), the
      ServletContextListener and the bootstrap use, the @WebFilter/@WebListener
      annotations vs the web.xml
  05-jsp-el-jstl  the JSP lifecycle ⭐⭐ (the translation to a servlet, the
      compilation, the _jspService, show the generated Java — ⭐ this is the
      lesson: a JSP IS a servlet), the scriptlets ⛔ and why they died, the
      declarations, the directives (page/include/taglib), the EL (the ${} and
      the implicit objects, the resolution order ⭐ pageScope→requestScope→
      sessionScope→applicationScope), the JSTL core/fmt/fn/sql tags, the
      custom tags and the TagHandler (⭐ and why nobody writes them now), the
      expression language injection risk, the JSP include vs the
      jsp:include (⭐ static vs dynamic)
  06-mvc-model2 ⭐⭐  the Model 1 vs Model 2, the Front Controller pattern
      ⭐⭐ (and how it becomes the DispatcherServlet), the request-scoped
      model, the view resolution, the PRG pattern ⭐⭐ (Post-Redirect-Get and
      the double-submit problem it solves), the flash attributes, the full
      worked example, ⭐ THEN: put the DispatcherServlet flow next to it and
      show the 1:1 correspondence — that's the point of the whole folder
  07-web-security ⭐⭐⭐  the OWASP Top 10 in a servlet app: the SQL injection
      (cross-ref), the XSS (⭐ the output encoding, the Content-Security-Policy,
      the HtmlUtils), the CSRF (⭐⭐ the synchroniser token pattern, the
      SameSite cookie, the double-submit cookie), the session fixation, the
      path traversal, the insecure deserialisation, the SSRF, the security
      headers (the full list with what each does), the auth vs authz, the
      container-managed security (the web.xml security-constraint ⭐ and why
      nobody uses it), the file upload security
  08-PROJECT-shop-storefront ⭐⭐  the complete shop storefront in pure
      Servlets + JSP + JDBC: the DAO layer, the service layer, the servlets,
      the JSPs, the filters (auth, encoding, MDC, CSRF), the session cart,
      the PRG flow. ⭐ THEN a section: "here is every line Spring Boot
      deletes" — the side-by-side. That's the payoff.
  09-CHEATSHEET

FOLDER 05 — 05-hibernate-jpa
  01-jpa-vs-hibernate ⭐  the spec vs the implementation, the EntityManager
      vs the Session, the JPQL vs the HQL, the other providers (EclipseLink,
      OpenJPA), the Jakarta Persistence rename ⭐ (javax → jakarta and the
      Spring Boot 3 migration), the ORM promise and its cost ⭐⭐ (the
      impedance mismatch, what it actually solves, what it doesn't)
  02-the-persistence-context ⭐⭐⭐  THE MOST IMPORTANT FILE. The first-level
      cache, the MANAGED state, what "attached" means, the EntityManager
      lifecycle (the container-managed vs the application-managed ⭐⭐ and why
      Spring's is neither exactly), the transaction-scoped vs the extended
      persistence context, the flush ⭐⭐⭐ (the FlushMode, WHEN it happens —
      before a query, at commit, on demand — and the AutoFlush surprise where
      a query triggers a write), the dirty checking ⭐⭐⭐ (how Hibernate knows
      what changed: the snapshot, the field-by-field comparison, and the cost),
      the detach, the clear, the merge ⭐⭐⭐ (what it actually does and why
      it returns a DIFFERENT instance — the most misunderstood method in JPA),
      the contains, the identity map
  03-the-entity-lifecycle ⭐⭐⭐  transient → managed → detached → removed,
      the transition diagram, the trigger for each, the identifier's role in
      determining the state ⭐⭐ (and the generated-vs-assigned-id difference
      that changes everything about merge/save), the cascade, the
      orphanRemoval ⭐⭐ (vs CascadeType.REMOVE — the difference and the bug),
      the @PrePersist/@PostPersist/@PreUpdate/@PostUpdate/@PreRemove/
      @PostRemove/@PostLoad callbacks (⭐ and the EntityListener alternative,
      and the "no dependency injection in a callback" trap), the version
      field and the optimistic lock
  04-mapping ⭐⭐  @Entity (the rules: a no-arg constructor ⭐ non-private,
      not final, no final fields — and WHY Hibernate needs each), @Table,
      @Id and ⭐⭐⭐ THE IDENTIFIER GENERATORS (AUTO ⛔ and what it silently
      becomes per vendor, IDENTITY ⭐⭐ and the batching it disables, SEQUENCE
      ⭐ and the allocationSize=50 default that everyone gets wrong — the
      off-by-50 bug, TABLE ⛔, UUID ⭐ the assigned-id pattern), @Column and
      every attribute, @Enumerated ⭐⭐ (ORDINAL ⛔ and the reorder disaster,
      STRING ✅, and the converter alternative), @Temporal and the java.time
      mapping ⭐, the @Lob, the @Transient, @Embedded/@Embeddable ⭐⭐ (the
      value-object pattern, the AttributeOverride, the null-embeddable
      problem), @Convert and the AttributeConverter ⭐ (the encrypted field,
      the JSON column, the enum mapping), the inheritance strategies ⭐⭐⭐
      (SINGLE_TABLE — one table, the discriminator, the nullable columns, the
      fastest reads; JOINED — normalised, the join cost; TABLE_PER_CLASS —
      the union query, ⛔ the polymorphic-query disaster; the decision table
      and the "favour composition over inheritance" advice), @MappedSuperclass,
      the naming strategies (⭐ the ImplicitNamingStrategy and the
      PhysicalNamingStrategy and why your column is called shop_id not shopId)
  05-relationships ⭐⭐⭐  THE HARDEST FILE. @OneToMany/@ManyToOne/
      @OneToOne/@ManyToMany, ⭐⭐⭐ THE OWNING SIDE AND mappedBy (the rule: the
      side with the foreign key column owns the relationship; mappedBy means
      "the other side owns it, go look there"; ⛔ the bidirectional mistake
      where you set only one side and the FK is null — the fix: the helper
      methods that set BOTH sides), the cascade types ⭐⭐ (each one, what it
      does, and ⛔ CascadeType.ALL being almost always wrong), the
      FetchType ⭐⭐⭐ (LAZY vs EAGER, the DEFAULTS THAT BITE — @ManyToOne and
      @OneToOne default to EAGER ⛔ and that's your N+1 before you wrote a
      query; how LAZY works — the bytecode-enhanced proxy, the
      HibernateProxy, ⭐⭐⭐ THE LazyInitializationException: the cause (the
      session closed), the FOUR fixes (the transaction boundary ⭐ the right
      one, the JOIN FETCH, the EntityGraph, the DTO projection ⭐⭐ the best
      one), and ⛔ the OpenSessionInView "fix" that hides the design problem
      and costs you a connection for the whole request), @ManyToMany ⛔⭐⭐
      (why it's almost always wrong: no place for the join-table's own
      attributes, the cascade surprise, the delete semantics — and the
      @OneToMany-to-a-link-entity refactor, drawn), the bidirectional
      consistency problem, the equals/hashCode for entities ⭐⭐⭐ (never all
      fields; never the generated id before persist; the business key, the
      UUID-assigned-in-the-constructor, the null-id guard, and the mutable-
      HashSet-of-entities disaster), the association override, the
      @JoinColumn vs the @JoinTable, the unidirectional vs bidirectional
      trade-off ⭐ (unidirectional @OneToMany creates a join table — the
      surprise)
  06-fetching-and-n-plus-one ⭐⭐⭐  THE PERFORMANCE FILE. What the N+1 is,
      ⭐ HOW TO SEE IT (the log with show_sql, the query count assertion in a
      test ⭐⭐, the datasource-proxy, the Hibernate Statistics), the FIVE
      fixes with the trade-offs: (1) JOIN FETCH ⭐⭐ (the query, the
      Cartesian-product warning with two collections, the pagination problem
      ⭐⭐⭐ — HHH000104 "firstResult/maxResults specified with collection
      fetch; applying in memory" and what it means), (2) @EntityGraph ⭐⭐
      (the named vs the ad-hoc, the attributePaths), (3) ⭐⭐⭐ DTO PROJECTION
      (the interface-based, the class-based, the JPQL constructor expression,
      the native query with a result-set mapping — THE right answer for a
      read-heavy path, and the "why are you loading entities to render a list"
      question), (4) @BatchSize (the secondary-query batching, the size
      tuning), (5) the two-query approach. ⭐ THE READ MODEL vs THE WRITE
      MODEL — the CQRS insight applied to JPA, and the honest recommendation:
      use entities for writes, projections for reads. The lazy-loading
      outside-a-transaction patterns. The multiple-bag problem. The
      fetch-profile. The @Where/@SQLRestriction filters
  07-queries ⭐⭐  JPQL/HQL (the entity-not-table model, the joins, the
      fetch join, the named parameters ⭐ vs positional, the named queries
      and @NamedQuery, the aggregation, the subqueries, the ⛔ string-
      concatenation injection), the Criteria API ⭐⭐ (the type-safe metamodel,
      the CriteriaBuilder, the verbosity and when it's justified, the dynamic-
      query use case), the Specification pattern ⭐⭐⭐ (the composable
      predicate, the Specification.and/or, the search-filter implementation —
      a genuinely elegant pattern and an LLD showcase), the native query
      (createNativeQuery, the result-set mapping ⭐⭐ the @SqlResultSetMapping,
      the entity vs the scalar), the projections (the interface-based ⭐ and
      the closed/open projection, the DTO), the query plan cache ⭐⭐ (and the
      parameter-padding problem with IN clauses that blows it up), the
      pagination, the streaming result ⭐ (the Stream<Entity> and the
      cursor), the second-level cache query
  08-transactions-and-locking ⭐⭐⭐  the JTA vs the resource-local, the
      @Transactional interaction ⭐⭐ (Spring owns the transaction; JPA joins
      it; the EntityManager-per-transaction), the flush and the commit order,
      ⭐⭐⭐ OPTIMISTIC LOCKING (@Version, the OptimisticLockException, the
      retry strategy, the version-less optimistic lock with all columns, the
      @OptimisticLocking type), ⭐⭐ PESSIMISTIC LOCKING (the LockModeType,
      the SELECT FOR UPDATE, the PESSIMISTIC_WRITE and the timeout, the
      deadlock), the locking and the detached-entity merge (⭐ the
      StaleObjectStateException), the read-only transaction optimisation
      ⭐⭐ (the flush-mode MANUAL, the dirty-checking skip, the real
      performance win), the transaction propagation cross-ref to Spring
  09-caching ⭐⭐⭐  the first-level cache (the persistence context, why it's
      not a cache you configure), ⭐⭐⭐ THE SECOND-LEVEL CACHE (the
      entity/collection/query regions, the @Cacheable, the CacheConcurrencyStrategy
      ⭐⭐ the five strategies and when each — READ_ONLY, NONSTRICT_READ_WRITE,
      READ_WRITE, the transactional one; the eviction, the invalidation), the
      providers (Caffeine ⭐ the local default, Ehcache, Hazelcast/Infinispan
      ⭐ the distributed case and the invalidation problem in a cluster ⭐⭐),
      the query cache ⛔ (why it's usually a net loss: the timestamp-based
      invalidation, the region granularity, the honest recommendation), the
      cache statistics and the hit-rate measurement, the natural-id cache,
      ⭐ the caching architecture question: L2 vs Redis vs the application
      cache — when each, and why they're not interchangeable
  10-performance ⭐⭐⭐  the batch inserts (⭐⭐ the jdbc-batch_size AND the
      IDENTITY-generator conflict that disables batching — the fix: SEQUENCE
      with allocationSize), the batch updates, the stateless session ⭐ (the
      bulk-load escape hatch), the dirty-checking cost and the read-only
      entity, the bytecode enhancement (the lazy attribute loading), the
      entity size (⭐ the fewer-the-columns argument, the @Basic(FetchType.LAZY)
      for the LOB), the connection pool interaction, the query plan cache,
      the Hibernate Statistics and the metrics to watch, the JFR integration,
      ⭐⭐ THE TUNING WORKFLOW: measure → find the N+1 → find the over-
      fetching → find the flush storm → batch → cache. With a worked example
      and the numbers. The schema-generation debate ⭐⭐ (hbm2ddl.auto: none
      in production, validate in CI, the Flyway ownership)
  11-spring-data-jpa ⭐⭐⭐  the repository abstraction ⭐⭐ (the
      JpaRepository hierarchy, ⭐ HOW IT WORKS: the dynamic proxy from
      folder 04's reflection section — the same mechanism, and I should be
      able to say so), the derived query methods ⭐⭐ (the parsing, the
      keywords, the PropertyExpression limit, ⛔ when the method name becomes
      unreadable use @Query), the @Query (the JPQL, the native, the SpEL, the
      named parameters), the projections ⭐⭐ (the interface, the DTO, the
      closed vs open, the dynamic), the Specification and the
      JpaSpecificationExecutor ⭐⭐⭐ (the dynamic search filter — the full
      implementation), the pagination and sorting (the Pageable, the
      Page vs Slice ⭐⭐ the count-query difference and when Slice is the
      right choice), the auditing ⭐ (@CreatedDate, the AuditorAware, the
      @MappedSuperclass), the @Modifying and the clearAutomatically ⭐ the
      trap, the entity graph attribute, the transactional repository ⭐ (the
      default @Transactional on SimpleJpaRepository and why your service
      should own the boundary), the custom repository implementation (the
      fragment pattern ⭐⭐), the @EntityListeners and the Spring bean access,
      the multiple datasources ⭐⭐ (the configuration, the package-based
      split, the transaction manager per datasource), the testing (@DataJpaTest
      ⭐⭐ and the embedded-database substitution problem, the
      @AutoConfigureTestDatabase, Testcontainers), the performance traps
      (⭐⭐⭐ the findAll() that loads everything, the save() that does a
      select-then-update, the open-in-view default ⛔ and how to turn it off,
      the lazy-loading-in-the-view)
  12-testing  the test pyramid for persistence, Testcontainers ⭐⭐⭐, the
      schema management in tests, the data setup (the builder, the
      ObjectMother, the fixture), the query-count assertion ⭐⭐ (the
      Hibernate Statistics counter in a test — how you catch an N+1 in CI),
      the transactional test and its limitation ⭐⭐ (the rollback hides the
      flush behaviour — so some tests must NOT be @Transactional), the
      repository test vs the integration test, the ArchUnit rules for the
      persistence layer
  13-PROJECTS  5 projects: the complete shop persistence layer (the write
      model), the shop read model with projections (⭐ the CQRS split), a
      multi-tenant SaaS data layer, an event-sourced order aggregate, a
      high-volume ingest with batching and the stateless session
  14-CHEATSHEET

FOLDER 06 — 06-spring-core
  01-ioc-and-di ⭐⭐⭐  the problem DI solves (⭐ the hard-coded dependency,
      the test double impossibility), IoC and the Hollywood Principle, the
      container (the BeanFactory vs the ApplicationContext ⭐⭐ and the five
      things the AC adds), ⭐⭐⭐ THE DI TYPES (constructor ⭐⭐⭐ and the four
      reasons it wins: immutability, the required-dependency guarantee, the
      no-partial-construction, the testability without a container; field
      injection ⛔ and the three problems; setter injection and the optional-
      dependency case), the @Component/@Service/@Repository/@Controller
      stereotypes (⭐ what each actually adds — the Repository's exception
      translation), @Autowired (the resolution algorithm, the required=false,
      the multiple-candidates and @Primary/@Qualifier ⭐⭐, the collection
      injection ⭐ and the Strategy pattern it enables), @Bean and
      @Configuration ⭐⭐⭐ (the proxyBeanMethods and the CGLIB proxy — why
      calling a @Bean method from another @Bean method returns the singleton,
      and the "lite mode" when proxyBeanMethods=false, and the startup-time
      trade-off), the component scan (the base packages, the filters, ⛔ the
      scan-everything performance and correctness problem), the bean naming,
      the BeanDefinition, the programmatic registration, ⭐ THE PATTERNS:
      the Factory, the Singleton (⭐ and how Spring's singleton differs from
      the GoF one — per-container, not per-JVM), the Proxy, the Template
      Method, the Observer (the ApplicationEvent), the Adapter, the Decorator
  02-the-bean-lifecycle ⭐⭐⭐  THE INTERVIEW FILE. The full sequence, drawn
      and numbered: instantiate → populate properties (the dependency
      injection) → BeanNameAware → BeanFactoryAware → ApplicationContextAware
      → BeanPostProcessor.postProcessBeforeInitialization ⭐⭐ (this is where
      @PostConstruct is processed, by the CommonAnnotationBeanPostProcessor)
      → InitializingBean.afterPropertiesSet → the custom init-method →
      BeanPostProcessor.postProcessAfterInitialization ⭐⭐⭐ (THIS IS WHERE
      THE AOP PROXY IS CREATED — the reason @Transactional works, and the
      reason self-invocation doesn't) → the bean is ready → ... →
      @PreDestroy → DisposableBean.destroy → the custom destroy-method.
      ⭐⭐ THE EXTENSION POINTS and what each is for: the BeanPostProcessor
      (write one that logs every bean), the BeanFactoryPostProcessor (modify
      the definitions before instantiation — this is where
      @ConfigurationClassPostProcessor lives), the InstantiationAwareBPP,
      the FactoryBean ⭐⭐ (the getObject, the &-prefix, and what MyBatis and
      Spring Data use it for), the SmartInitializingSingleton, the
      ApplicationListener, the ImportBeanDefinitionRegistrar ⭐ (what
      @EnableAutoConfiguration uses). The circular dependency ⭐⭐⭐ (the
      three-way resolution: the singletonObjects / earlySingletonObjects /
      singletonFactories maps, the three-level cache and the early reference
      exposure, ⛔ WHY IT FAILS WITH CONSTRUCTOR INJECTION — you cannot
      expose an early reference to an object that doesn't exist yet, and why
      that's a FEATURE, the @Lazy workaround, and the honest advice: fix the
      design), the scope-aware proxy, the destruction ordering
  03-scopes-and-autowiring ⭐⭐  the singleton, the prototype ⭐⭐ (and the
      singleton-holding-a-prototype trap and the three fixes: ObjectFactory/
      ObjectProvider, @Lookup, the scoped proxy), the request/session/
      application/websocket scopes ⭐⭐ (and the scoped-proxy mode that makes
      them injectable into a singleton), the custom scope, the @Profile ⭐⭐
      (the activation, the profile groups, the profile-specific beans and
      config files, ⛔ the "default" profile misunderstanding), the
      Environment and the PropertySource hierarchy ⭐⭐⭐ (the full ordered
      list — command line, JNDI, system properties, env vars, application.yml,
      the @PropertySource, the default properties — and the override rule),
      the @Value ⭐⭐ (the SpEL, the type conversion, the default value
      syntax, ⛔ and why @ConfigurationProperties is better), the
      @ConfigurationProperties ⭐⭐⭐ (the relaxed binding rules, the
      constructor binding and the immutability ⭐, the validation with
      @Validated, the nested types, the metadata generation for IDE support,
      the prefix discipline), the type conversion and the Converter/
      ConversionService, the SpEL (the syntax, the operators, the bean
      reference, the collection selection and projection, ⛔ the injection
      risk when it evaluates user input)
  04-aop ⭐⭐⭐  the cross-cutting concern problem, the AOP vocabulary
      (aspect, advice, pointcut, join point, target, proxy, weaving ⭐ and
      the compile/load/runtime distinctions), ⭐⭐⭐ THE PROXY MECHANISMS: the
      JDK dynamic proxy (interfaces only — cross-ref Core Java 04C) vs CGLIB
      (subclassing, the final-class and final-method limits ⭐⭐), how Spring
      chooses (the proxyTargetClass flag, the Boot default of CGLIB since 2.0),
      ⭐⭐⭐ THE SELF-INVOCATION PROBLEM — `this.otherTransactionalMethod()`
      bypasses the proxy entirely, so no advice runs. The proof program, the
      four fixes (inject self, split the bean, use AspectJ weaving, use the
      AopContext.currentProxy() with exposeProxy), and why this is THE most
      common Spring bug in production. The advice types (@Before, @After,
      @AfterReturning, @AfterThrowing, @Around ⭐⭐ and the proceed() control),
      the pointcut expressions ⭐⭐ (the designators: execution within
      @annotation args bean this target — with the syntax and the examples),
      the advice ordering (@Order ⭐ and the onion model), the aspect
      scoping, ⭐ WHAT SPRING USES AOP FOR: @Transactional, @Cacheable,
      @Async, @Retryable, security, the audit log. The limitations (the
      private method, the final method, the self-call, the non-bean), the
      AspectJ comparison (the full weaving, the compile-time cost, when you
      need it), ⭐ THE PERFORMANCE (the proxy call overhead, the pointcut
      evaluation caching, the startup cost of a broad pointcut)
  05-transactions ⭐⭐⭐  THE HARDEST SPRING FILE. The abstraction (the
      PlatformTransactionManager, the TransactionDefinition, the
      TransactionStatus, ⭐ why the abstraction matters — the same code on
      JDBC, JPA, JTA, R2DBC), @Transactional ⭐⭐⭐ (every attribute:
      propagation, isolation, timeout, readOnly, rollbackFor, noRollbackFor,
      transactionManager), ⭐⭐⭐ THE SEVEN PROPAGATIONS with a runnable demo
      and a nested-call diagram for each: REQUIRED (the default, joins or
      creates), REQUIRES_NEW (⭐⭐ suspends the outer — the two connections,
      the deadlock risk if the inner needs the outer's lock, and the audit-
      log-that-must-survive-a-rollback use case), SUPPORTS, NOT_SUPPORTED,
      MANDATORY, NEVER, NESTED (⭐⭐ the savepoint, the partial rollback, and
      why it's rarely right), ⭐⭐⭐ THE ROLLBACK RULE AND THE TRAP: Spring
      rolls back on RuntimeException and Error ONLY — a checked exception
      COMMITS by default. The proof, the fix (rollbackFor), and the
      architectural argument for unchecked exceptions (cross-ref OOP 02A.21).
      The readOnly optimisation ⭐⭐ (what it actually does per provider).
      ⭐⭐⭐ THE FIVE WAYS @TRANSACTIONAL SILENTLY DOES NOTHING: (1) the
      self-invocation, (2) the method isn't public (⭐ and the CGLIB/
      interface difference), (3) the class isn't a Spring bean, (4) the
      exception is caught inside the method, (5) the exception is checked.
      Plus: the transaction and the lazy loading (the OpenSessionInView ⛔),
      the transaction boundary design ⭐⭐ (the service layer, the
      use-case-as-a-transaction, ⛔ the transaction-per-repository, the
      long-transaction problem and the connection hold), the programmatic
      transactions (the TransactionTemplate ⭐ and when it's better), the
      distributed transactions and the Saga ⭐⭐ (the orchestration vs the
      choreography, the compensating action, the idempotency requirement —
      cross-ref 03-jdbc-deep), the transaction testing ⭐⭐ (the
      @Transactional test rollback and why it hides bugs, the Testcontainers
      commit test)
  06-spring-mvc ⭐⭐⭐  ⭐⭐⭐ THE DISPATCHSERVLET REQUEST FLOW — the 10 steps,
      drawn: the request → the DispatcherServlet → the HandlerMapping (find
      the handler + the interceptor chain) → the HandlerAdapter (invoke the
      controller) → the argument resolvers → the controller method → the
      return value handlers → the ViewResolver OR the HttpMessageConverter →
      the response. ⭐ THEN the Servlet equivalent from folder 04 side by
      side — that's the payoff of learning the servlets. The @Controller vs
      @RestController ⭐ (the @ResponseBody difference), @RequestMapping and
      its specialisations, the path patterns (⭐ the AntPathMatcher vs the
      PathPatternParser and the Boot 2.6+ default change), the path variables
      and the regex constraint, the request params (the required, the
      defaultValue, the ⭐ binding to an object), the request body and the
      message converters ⭐⭐ (the Jackson integration, the content
      negotiation, the Accept/Content-Type resolution), the argument
      resolvers ⭐ (the full list, and how to write one), the return types
      (ResponseEntity ⭐⭐ and when it beats a bare object, the
      ProblemDetail ⭐ the RFC 7807 error response, the StreamingResponseBody,
      the DeferredResult and the Callable ⭐ the async MVC), ⭐⭐ VALIDATION
      (the Bean Validation, the @Valid vs @Validated ⭐ the difference, the
      constraints, the nested validation, the groups, the BindingResult and
      the error handling, the custom constraint validator), the exception
      handling ⭐⭐⭐ (@ExceptionHandler, the @ControllerAdvice ⭐ and its
      ordering, the ResponseEntityExceptionHandler, the
      ResponseStatusException, the error-handling architecture), the
      interceptors vs the filters ⭐⭐ (the table: where they sit, what they
      can see, when each), the CORS configuration ⭐⭐ (the three ways, the
      preflight, the security implications, ⛔ the allowed-origins-with-
      credentials wildcard), the static resources, the WebMvcConfigurer, the
      MultipartFile, the HATEOAS (⭐ and the honest "usually don't"), the
      content negotiation and the API versioning strategies ⭐⭐ (URI vs
      header vs parameter — the trade-offs)
  07-data-access  the JdbcTemplate ⭐⭐ (the callback model, the RowMapper,
      the NamedParameterJdbcTemplate, the SqlParameterSource), ⭐⭐⭐ THE
      EXCEPTION TRANSLATION (the SQLException → DataAccessException
      hierarchy, the SQLExceptionTranslator, WHY it matters — the portable
      unchecked exception, and how @Repository enables it via the
      PersistenceExceptionTranslationPostProcessor), the data access
      exceptions hierarchy, the TransactionTemplate, the R2DBC and the
      reactive data access ⭐ (and when), the Spring Data commons (the
      Repository abstraction, the CrudRepository/PagingAndSortingRepository
      hierarchy, the @NoRepositoryBean)
  08-testing ⭐⭐⭐  the TestContext framework ⭐⭐ (the context caching ⭐⭐⭐
      and the @DirtiesContext cost, the context-configuration keys, the
      TestExecutionListeners), the test annotations (@SpringBootTest ⭐⭐ and
      the webEnvironment modes, @WebMvcTest, @DataJpaTest, @JsonTest,
      @RestClientTest ⭐ the slice tests and WHY they're fast), the MockMvc
      ⭐⭐ (the perform/andExpect, the request builders, the result matchers,
      the jsonPath, the standalone vs the web-app-context setup), the
      @MockBean ⛔⭐ (deprecated in Boot 3.4+, replaced by @MockitoBean — the
      context-cache-busting problem it causes and why), TestRestTemplate and
      the WebTestClient, Testcontainers ⭐⭐⭐ (@ServiceConnection ⭐ the
      Boot 3.1 feature that removed all the config, the singleton pattern,
      the @Testcontainers lifecycle), the test slices decision table ⭐⭐,
      the ArchUnit tests ⭐⭐ (the layer-dependency rules, the naming rules,
      the annotation rules — the architecture-as-code idea), the
      @TestPropertySource and the test profiles, the assertion libraries, the
      test data builders, ⭐ THE TESTING PHILOSOPHY for a Spring app (the
      pyramid, what to unit test vs integration test, the "test the seam"
      principle, the speed budget)
  09-the-patterns-inside-spring ⭐⭐⭐  THE FILE THAT CONNECTS FOLDER 02B TO
      REALITY. Every GoF pattern with the EXACT Spring class that implements
      it: the Factory (BeanFactory), the Abstract Factory
      (FactoryBeanRegistrySupport), the Builder (the BeanDefinitionBuilder,
      the ResponseEntity.Builder), the Singleton (the bean scope), the
      Prototype, the Adapter (the HandlerAdapter ⭐⭐ — the reason Spring can
      invoke any controller style), the Decorator (the
      HttpServletRequestWrapper, the BeanDefinitionDecorator), the Proxy
      (⭐⭐⭐ the AOP infrastructure, the TransactionInterceptor, the
      LazyInitialization), the Chain of Responsibility (⭐⭐ the
      HandlerInterceptor chain, the Filter chain, the Security filter chain),
      the Observer (⭐⭐ the ApplicationEventPublisher and the
      ApplicationListener — the full event model, the @EventListener, the
      @TransactionalEventListener ⭐⭐ and the AFTER_COMMIT phase that solves
      the "publish before the transaction commits" bug, the async events),
      the Strategy (⭐ the injected List<Strategy> and the runtime selection),
      the Template Method (⭐⭐⭐ JdbcTemplate, RestTemplate,
      TransactionTemplate — the name is literal), the Composite (the
      CompositeCacheManager), the Facade (the JdbcTemplate over raw JDBC),
      the MVC (the whole web layer). ⭐ THEN the Spring-specific patterns:
      the post-processor, the aware interfaces, the lifecycle callbacks, the
      scope proxy, the transaction proxy, the repository proxy. 🔑 AND THE
      INTERVIEW LINE: "Spring is a patterns textbook that runs."
  10-caching-scheduling-async ⭐⭐  the caching abstraction (@Cacheable/
      @CachePut/@CacheEvict ⭐⭐ and the key generation, the SpEL, the
      condition/unless, the cache-aside pattern it implements, ⛔ the
      self-invocation problem again, the cache manager, the providers
      (Caffeine ⭐, Redis ⭐⭐ and the serialisation question, the JCache),
      the TTL and the eviction, the cache- stampede problem ⭐⭐ and the
      fixes, the two-level cache), the scheduling (@Scheduled ⭐⭐ the cron
      syntax and the fixedDelay vs fixedRate distinction, the single-threaded
      scheduler by default ⛔ and the pool config, the distributed-scheduler
      problem and ShedLock/Quartz ⭐), the async (@Async ⭐⭐ the proxy again,
      the executor config ⛔ NEVER the default SimpleAsyncTaskExecutor, the
      exception handling in an async method ⭐⭐ the AsyncUncaughtExceptionHandler,
      the CompletableFuture return, ⭐⭐ AND THE VIRTUAL THREADS REPLACEMENT —
      in Java 21+ you often don't need @Async at all), the retry (@Retryable,
      the backoff, the idempotency requirement), the Resilience4j integration
  11-PROJECTS  5 projects: a custom BeanPostProcessor that times every bean
      method (⭐ AOP + the lifecycle), a multi-datasource routing setup (⭐
      the AbstractRoutingDataSource, the read-replica pattern), a custom
      scope, an event-driven order flow (⭐ the ApplicationEvent architecture,
      the transactional event, the outbox pattern), a mini-framework (⭐
      build a 300-line Spring: the component scan, the DI, the lifecycle, the
      AOP proxy — THE single best way to understand it)
  12-CHEATSHEET

FOLDER 07 — 07-spring-boot
  01-what-boot-actually-does ⭐⭐⭐  THE MYTH-BUSTING FILE. Boot is not a
      framework, it's a convention + autoconfiguration layer over Spring.
      ⭐⭐⭐ THE STARTUP SEQUENCE, step by step: SpringApplication.run → the
      ApplicationContext type inference (servlet vs reactive vs none) → the
      ApplicationContextInitializers → the Environment preparation (⭐ the
      config data loading, the profiles) → the banner → the context creation
      → ⭐⭐⭐ THE AUTO-CONFIGURATION: @EnableAutoConfiguration → the
      AutoConfigurationImportSelector → the
      META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
      file (⭐ and the old spring.factories it replaced in 2.7) → the
      @Conditional evaluation ⭐⭐⭐ (the full condition family:
      @ConditionalOnClass/OnMissingClass/OnBean/OnMissingBean ⭐⭐ THE ONE
      THAT MATTERS — your bean wins because the auto-config is conditional on
      its absence/OnProperty/OnWebApplication/OnResource/OnExpression — and
      the ORDER in which they're evaluated, which is why some conditions
      surprise you) → the bean registration → the runners (the
      ApplicationRunner/CommandLineRunner ⭐ and the ordering) → the
      ApplicationReadyEvent. ⭐ HOW TO SEE IT: the --debug condition
      evaluation report, the actuator /conditions endpoint, the
      startup-tracking. THE STARTER POMS ⭐ (the dependency management, the
      BOM, the version alignment, ⛔ the starter that pulls in 200 jars you
      didn't want and how to find it — the dependency:tree), the
      spring-boot-dependencies BOM, the parent POM vs the BOM import ⭐, the
      Boot version → Spring Framework version → Java version compatibility
      matrix ⭐⭐
  02-configuration ⭐⭐⭐  the application.yml/properties ⭐ (the YAML
      gotchas: the indentation, the list syntax, the multi-document with ---,
      the profile-specific document ⭐⭐), ⭐⭐⭐ THE PROPERTY SOURCE HIERARCHY
      (the full 17-level ordered list — devtools, @TestPropertySource,
      command-line args, SPRING_APPLICATION_JSON, servlet params, JNDI,
      System.getProperties, env vars, RandomValuePropertySource, the profile-
      specific outside the jar, the profile-specific inside the jar, the
      application.yml outside, inside, the @PropertySource, the default
      properties — and the override rule: later wins, and the profile-specific
      beats the non-profile), the property placeholder, the relaxed binding
      ⭐⭐ (the rules for @ConfigurationProperties vs the exact match for
      @Value), ⭐⭐ @ConfigurationProperties deep (the constructor binding
      and the @DefaultValue, the validation with @Validated and the JSR-380
      constraints, the nested and the list and the map binding, the duration
      and DataSize types ⭐, the metadata generation with the annotation
      processor, the @ConfigurationPropertiesScan, the immutable-config
      pattern ⭐⭐⭐ which is the SDE 3 answer), the profiles ⭐⭐ (the
      activation, the groups, the profile-specific files AND the
      profile-specific documents, ⛔ the profile-per-environment anti-pattern
      and the externalised-config answer), the environment variables and the
      12-factor config ⭐⭐⭐ (the SPRING_DATASOURCE_URL convention, the
      Kubernetes ConfigMap/Secret mounting, the Vault integration, ⛔ secrets
      in application.yml committed to Git), the external configuration in a
      container (⭐ cross-ref the CI/CD path), the config server and the
      refresh (the @RefreshScope and its proxy, the actuator /refresh), the
      structured logging config
  03-web-and-rest ⭐⭐⭐  the REST API design ⭐⭐⭐ (the resource modelling,
      the URL conventions, the HTTP method semantics ⭐ the full table
      including the idempotency and safety columns, the status codes ⭐⭐ the
      ones you actually use and the ones you're using wrong — 201 with a
      Location header, 204, 400 vs 422, 401 vs 403 ⭐⭐, 409, 412, 415, 429
      with a Retry-After, 503), the ResponseEntity and the ProblemBuilder,
      ⭐⭐⭐ ERROR HANDLING THE RIGHT WAY (the ProblemDetail / RFC 9457, the
      @RestControllerAdvice architecture, the domain-exception → HTTP-status
      mapping layer ⭐⭐ the ErrorResponse enum pattern, the validation-error
      shape, the correlation id ⭐⭐ and the MDC, the error-response
      consistency, ⛔ the stack trace in production), the API versioning ⭐⭐
      (the strategies and the honest recommendation), the pagination ⭐⭐⭐
      (the Pageable, the Page vs Slice, the cursor pagination for large
      offsets — cross-ref 03-jdbc-deep, the HATEOAS links), the request
      validation, the OpenAPI/Swagger ⭐⭐ (the springdoc, the annotations,
      the generated spec, the contract-first alternative with the code
      generation ⭐⭐ and why contract-first is the SDE 3 answer), the CORS
      ⭐⭐, the content negotiation, the HATEOAS honestly, the WebFlux
      functional endpoints, the RestClient ⭐ (the Boot 3.2 replacement for
      RestTemplate) and the RestTemplate and the WebClient comparison ⭐⭐,
      the HTTP interface declarative client ⭐⭐ (the @HttpExchange — the
      Feign-like interface), the retry and the circuit breaker on a client
      call, the request/response logging (⭐ and the PII problem), the
      idempotency key ⭐⭐⭐ (the header, the store, the dedup window, the
      exactly-once illusion), the async endpoints (the DeferredResult, the
      Callable, the SseEmitter ⭐, the StreamingResponseBody), the file
      upload/download, the graceful shutdown ⭐⭐ (the server.shutdown=graceful,
      the timeout, what it does and doesn't wait for)
  04-data ⭐⭐  the datasource auto-configuration ⭐ (what it does, the
      HikariCP default, the properties), the Spring Data JPA integration
      (cross-ref folder 05), the Flyway/Liquibase auto-config ⭐⭐ (the
      ordering, the baseline-on-migrate, the validation), the multiple
      datasources ⭐⭐ (the manual config, the routing datasource, the
      read/write split), the Redis integration ⭐⭐ (the RedisTemplate, the
      serialisation ⛔ the JDK serialiser default and the JSON fix, the
      Lettuce vs Jedis, the connection factory, the cache manager, the
      Redisson alternative), the MongoDB/Neo4j/Elasticsearch starters, the
      transaction management (cross-ref folder 06), the connection-pool
      tuning ⭐⭐ (the HikariCP settings that matter, the metrics, the
      exhausted-pool diagnosis), the testcontainers integration ⭐⭐⭐
      (@ServiceConnection — the feature that deleted 40 lines of config per
      test class), the database initialization (the schema.sql/data.sql ⛔
      and why migrations win)
  05-security ⭐⭐⭐  THE BIGGEST FILE IN THE FOLDER. ⭐⭐⭐ THE FILTER CHAIN —
      the SecurityFilterChain bean, the 15 filters IN ORDER with what each
      does (the SecurityContextHolderFilter, the HeaderWriterFilter, the
      CorsFilter, the CsrfFilter, the LogoutFilter, the
      UsernamePasswordAuthenticationFilter, the BearerTokenAuthenticationFilter,
      the RequestCacheAwareFilter, the SecurityContextHolderAwareRequestFilter,
      the AnonymousAuthenticationFilter, the SessionManagementFilter, the
      ExceptionTranslationFilter ⭐⭐, the AuthorizationFilter ⭐⭐), and ⭐⭐
      THE SECURITYCONTEXT AND THE THREADLOCAL (how the authentication travels,
      ⛔ why it's lost in an async thread, the DelegatingSecurityContextExecutor
      fix, the SecurityContextHolder modes), authentication vs authorization
      ⭐⭐, the Authentication object (the principal, the credentials, the
      authorities, the authenticated flag ⭐ and the pre/post-authentication
      distinction), the AuthenticationManager → ProviderManager →
      AuthenticationProvider chain ⭐⭐, the UserDetailsService ⭐⭐ (the
      loadUserByUsername, the UserDetails, the JdbcUserDetailsManager, the
      JPA implementation, the caching), ⭐⭐⭐ PASSWORD STORAGE (the
      PasswordEncoder, the BCrypt ⭐⭐ the work factor and the salt, the
      Argon2id, the DelegatingPasswordEncoder ⭐ and the {bcrypt} prefix and
      the migration path, ⛔ never MD5/SHA/plaintext, the password-upgrade-on-
      login pattern), the JWT ⭐⭐⭐ (the structure, the signing (HS256 vs
      RS256/ES256 ⭐⭐ and the algorithm-confusion attack), the claims, the
      validation, the expiry and the refresh token ⭐⭐⭐ the rotation, the
      reuse detection, the storage question — ⛔ localStorage and the XSS,
      ⭐ the httpOnly cookie and the CSRF trade-off, the stateless session
      policy, the token revocation problem and the denylist/short-expiry
      answers), ⭐⭐⭐ OAuth2 (the four grants and which are still alive —
      ⛔ the implicit and the password grants are dead, ✅ the authorization
      code with PKCE, ✅ the client credentials; the roles: resource server,
      client, authorization server; the scopes; the token introspection vs
      the local JWT validation; the Spring Authorization Server), the method
      security ⭐⭐ (@PreAuthorize/@PostAuthorize, the SpEL, the
      @PreFilter/@PostFilter, the @Secured, the JSR-250, the PermissionEvaluator),
      the URL-based authorization ⭐⭐ (the requestMatchers, the ordering ⛔
      THE MOST COMMON BUG — a permissive rule before a restrictive one makes
      the restrictive one dead, the anyRequest().authenticated() default), the
      CSRF ⭐⭐⭐ (what it is, the synchroniser token, ⭐ the SameSite cookie
      defence and why it isn't sufficient alone, WHEN TO DISABLE IT ⭐⭐ —
      stateless JWT APIs, and the reasoning, and when NOT to — cookie-session
      apps), the CORS ⭐⭐ (the preflight, the configuration, ⛔ the
      wildcard-with-credentials), the session management (the concurrent-
      session control, the session fixation protection ⭐, the
      invalidate-session-on-login), the logout, the remember-me ⛔ (and the
      security cost), the exception handling (the AuthenticationEntryPoint
      401 vs the AccessDeniedHandler 403 ⭐⭐), the security headers ⭐⭐
      (the full set: the CSP ⭐⭐⭐ and how to write one that doesn't break
      everything, the HSTS, the X-Content-Type-Options, the frame-options, the
      referrer-policy, the permissions-policy), the actuator security ⭐⭐ (the
      exposure default, the separate management port, ⛔ the exposed /env and
      /heapdump incidents — REAL breaches), the OAuth2 resource server config,
      the security testing ⭐⭐ (@WithMockUser, the SecurityMockMvcRequestPostProcessors,
      the TestSecurityContextHolder), ⭐⭐⭐ THE COMMON MISCONFIGURATIONS
      (the permitAll() that leaked an endpoint, the disabled CSRF on a
      session app, the exposed actuator, the JWT without signature validation,
      the algorithm confusion, the IDOR that no framework prevents ⭐⭐⭐ —
      "Spring Security authorises the URL, not the object; the ownership
      check is YOUR code" — that is the SDE 3 line)
  06-actuator-and-observability ⭐⭐⭐  the actuator endpoints ⭐⭐ (the
      exposure config, ⛔ the security, the useful ones: health ⭐⭐⭐ the
      HealthIndicator and the custom one and the details-visibility, info,
      metrics ⭐⭐⭐, prometheus, env, loggers ⭐⭐ the runtime log-level change,
      threaddump ⭐⭐, heapdump ⛔, mappings, conditions ⭐, configprops,
      beans, scheduledtasks, httpexchanges, startup ⭐ the startup-cost
      analysis, shutdown ⛔, the custom endpoint ⭐⭐), ⭐⭐⭐ MICROMETER (the
      facade, the MeterRegistry, the four meter types — Counter/Gauge/
      Timer/DistributionSummary — and when each, the tags ⭐⭐ and the
      cardinality explosion ⛔ THE MOST COMMON METRICS MISTAKE — never tag
      with a user id or a URL path, the percentile and the histogram config,
      the Timer and the @Timed, the common tags, the LongTaskTimer, the
      custom binder), the Prometheus integration ⭐⭐ (the endpoint, the
      scrape config, the ServiceMonitor for Kubernetes — ⭐ cross-ref the
      monitoring path), ⭐⭐⭐ DISTRIBUTED TRACING (the Micrometer Tracing,
      the OpenTelemetry integration, the trace id and the span id, the
      context propagation ⭐⭐⭐ and the ThreadLocal problem with async and
      virtual threads and the fix, the baggage, the sampling strategies, the
      export to Tempo/Zipkin/Jaeger, ⭐ cross-ref the monitoring path's
      OpenTelemetry case), the structured logging ⭐⭐ (the MDC ⭐⭐⭐ and the
      correlation id, the logstash-encoder, the JSON logs, the log levels and
      the runtime change, ⛔ the log-injection vulnerability and the fix),
      the health-check design ⭐⭐⭐ (the liveness vs readiness distinction
      ⭐⭐⭐ and the Kubernetes probe mapping — cross-ref the K8s path, the
      dependency health and the "don't fail readiness on a degraded
      downstream" rule, the AvailabilityState), the metrics that matter for a
      Java service ⭐⭐ (the JVM: heap, GC pauses ⭐⭐⭐, threads, the
      classloader; the HTTP: the request rate, the error rate, the latency
      percentiles ⭐⭐⭐ p50/p95/p99/p99.9 and why the average lies; the pool:
      the HikariCP active/idle/pending/waiting; the cache: the hit rate; the
      business metrics), the SLO from these metrics ⭐ (cross-ref the
      monitoring path), the alerting rules, the Grafana dashboard for a Spring
      Boot service ⭐⭐, the profiling in production (the JFR, the async-
      profiler, the continuous profiling with Pyroscope/Parca)
  07-testing ⭐⭐  (the Boot-specific layer over folder 06's Spring testing)
      the @SpringBootTest webEnvironment modes ⭐⭐ (MOCK vs RANDOM_PORT vs
      DEFINED_PORT vs NONE and when each), the slice-test decision table ⭐⭐⭐,
      the Testcontainers ⭐⭐⭐ (@ServiceConnection, the singleton container,
      the @Testcontainers(disabledWithoutDocker), the startup-time
      amortisation, the reuse with the Ryuk), the WireMock and the
      @MockRestServiceServer, the JsonTest and the serialisation assertions,
      the MockMvc deep, the test properties and the profiles, the
      ⭐⭐ MUTATION TESTING note, the CI integration and the testcontainers-
      in-CI setup (cross-ref the CI/CD path), the load testing (Gatling/k6)
      and the performance budget, ⭐ the test-architecture: what to test at
      which layer, the seam discipline, the "don't mock what you don't own"
      rule
  08-deployment ⭐⭐⭐  THE FILE THAT CONNECTS TO MY FOUR EXISTING PATHS.
      ⭐⭐ THE FAT JAR (the structure, the nested jars, the JarLauncher ⭐ and
      the Boot 3.2+ class rename org.springframework.boot.loader.launch.JarLauncher,
      the classpath index, the startup cost), ⭐⭐⭐ THE LAYERED JAR (the four
      layers — dependencies, spring-boot-loader, snapshot-dependencies,
      application — and WHY: the Docker layer cache, so a code change doesn't
      re-pull 200 MB), the Dockerfile ⭐⭐⭐ (the multi-stage build, the
      layered-jar extraction, the non-root user ⭐⭐, the JVM container flags
      ⭐⭐⭐ — the MaxRAMPercentage vs -Xmx and the container-memory
      awareness, the UseContainerSupport, the cgroup v2, the OOMKilled
      diagnosis, ⛔ the -Xmx larger than the container limit, the CDS/AppCDS
      ⭐⭐ the startup-time win, the CRaC ⭐⭐ the checkpoint-restore and the
      serverless case, the JLink custom runtime ⭐ and the image-size win,
      the distroless and the Alpine base images ⭐⭐ and the musl-vs-glibc
      DNS problem), the Buildpacks ⭐ (the pack CLI, the Cloud Native
      Buildpacks, when they beat a Dockerfile), the Kubernetes deployment
      ⭐⭐⭐ (cross-ref the K8s path: the Deployment, the readiness/liveness/
      startup probes ⭐⭐⭐ mapped from the actuator health groups, the
      resource requests/limits ⭐⭐ and the JVM heap sizing within them, the
      graceful shutdown ⭐⭐⭐ the preStop hook + the SIGTERM handling + the
      terminationGracePeriodSeconds arithmetic, the HPA ⭐⭐ and the JVM-metric-
      based scaling problem, the ConfigMap/Secret, the rolling update and the
      maxUnavailable:0), the CI/CD ⭐⭐ (cross-ref the CI/CD path: the
      build-once-promote-by-digest, the signed image, the GitOps config), the
      observability ⭐⭐ (cross-ref the monitoring path), the Helm chart, the
      the startup-time optimisation ⭐⭐ (the CDS, the lazy initialisation
      ⛔ and its trade-off, the component-scan narrowing, the
      spring-context-indexer), the memory footprint (⭐ the heap vs the RSS
      and the metaspace and the direct buffers and the thread stacks and the
      code cache — the full accounting, and why your 512 MB heap uses 900 MB),
      the graceful degradation, the blue-green and the canary (cross-ref the
      CI/CD capstone), the config externalisation in production, the secret
      management ⭐⭐ (⛔ never in the image or the ConfigMap, the Vault, the
      sealed secrets, the cloud KMS), the multi-environment strategy, the
      serverless (the cold start ⭐⭐⭐ and the CRaC/GraalVM native answers)
  09-messaging-caching-batch ⭐⭐  the messaging (the JMS, the RabbitMQ ⭐⭐
      the AMQP template, the exchange/queue/binding, the @RabbitListener, the
      message conversion, the ack/nack and the DLQ ⭐⭐⭐ the reliability
      design, the retry and the poison message, the ordering guarantee and
      why you don't have one, the Kafka ⭐⭐⭐ the topic/partition/offset/
      consumer-group model, the producer acks ⭐⭐ the delivery semantics, the
      consumer rebalance, the exactly-once claim and the honest answer, the
      Spring for Apache Kafka, the schema registry, the event-driven
      architecture ⭐⭐ and the outbox pattern ⭐⭐⭐ — the reliable
      database-plus-message publish, drawn and implemented), the caching
      (cross-ref folder 06, the Redis deep), the batch (Spring Batch ⭐⭐ the
      job/step/chunk model, the ItemReader/Processor/Writer, the chunk size
      tuning, the restart and the skip and the retry, the JobRepository, the
      partitioning ⭐ and the parallel step, the real use case: the nightly
      reconciliation), the scheduled tasks (cross-ref)
  10-webflux-vs-virtual-threads ⭐⭐⭐  THE 2026 ARCHITECTURE QUESTION. The
      reactive model (the Reactor/Flux/Mono, the backpressure ⭐⭐ the
      strategies, the non-blocking I/O, the Netty, the event loop ⛔ and the
      blocking-call-in-the-event-loop disaster, the reactive streams spec),
      ⭐⭐⭐ THE HONEST COMPARISON: reactive gives you non-blocking
      composition and backpressure and costs you the readability, the stack
      traces ⛔, the debugging, the ecosystem compatibility (JDBC is
      blocking; R2DBC exists but is limited), the learning curve, and the
      ThreadLocal-dependent libraries (security contexts, MDC, transactions).
      Virtual threads give you the blocking style with the scalability, at
      the cost of no backpressure and the pinning caveats. ⭐⭐⭐ THE
      DECISION: for a typical CRUD service in 2026, virtual threads win —
      keep the blocking code, get the throughput. Reactive wins when you
      genuinely need stream composition and backpressure (a gateway, a
      streaming pipeline, a proxy). The migration path from WebFlux to
      virtual threads (⭐ it's just deleting code), the benchmark with real
      numbers, 🔑 THE INTERVIEW ANSWER — this question is asked constantly in
      2026 and most candidates answer it with dogma instead of trade-offs
  11-microservices-honestly ⭐⭐⭐  the distributed monolith ⛔, when to
      split (⭐ the real triggers: independent deployability, independent
      scaling, team ownership — NOT "it's big"), the domain-driven boundaries
      ⭐⭐ (the bounded context, the aggregate, the ubiquitous language — and
      how the LLD skill applies), the service communication (the sync REST/
      gRPC ⭐⭐ and the protobuf, the async messaging ⭐⭐⭐ and the
      event-driven design), ⭐⭐⭐ THE HARD PROBLEMS: the distributed
      transaction and the Saga ⭐⭐⭐ (the orchestration vs choreography, the
      compensating action, the idempotency, the exactly-once illusion), the
      data consistency ⭐⭐ (the eventual consistency and what it costs your
      UX, the CQRS, the outbox), the service discovery (the client-side vs
      the server-side, Eureka/Consul/the Kubernetes Service ⭐⭐ and why K8s
      made Eureka mostly redundant), the API gateway ⭐⭐ (the Spring Cloud
      Gateway, the routing, the rate limiting, the auth aggregation, the
      BFF pattern), the circuit breaker (Resilience4j ⭐⭐ the states, the
      sliding window, the half-open, the bulkhead, the rate limiter, the
      retry and the retry-storm ⛔), the configuration (the config server vs
      the Kubernetes ConfigMap), the observability ⭐⭐⭐ (the tracing across
      services, the correlation id, the log aggregation, the RED/USE metrics
      — cross-ref the monitoring path), the testing (the contract testing ⭐⭐
      with Pact/Spring Cloud Contract, the consumer-driven contract, the
      integration test with Testcontainers, ⛔ the end-to-end test suite that
      takes 40 minutes and nobody trusts), the deployment (cross-ref the
      CI/CD path), the data ownership ⭐⭐⭐ (the database-per-service and the
      shared-database anti-pattern, the migration strategy), 🔑 AND THE
      SDE 3 ANSWER: "most teams should not build microservices; the
      modular monolith with clear boundaries gives you 80% of the benefit at
      10% of the cost, and you can extract a service later when you have a
      real reason."
  12-PROJECTS  5 projects: the complete shop-api (⭐⭐⭐ the Spring Boot
      backend for the capstone: the REST API, the JPA persistence, the
      security with JWT, the Redis cache, the RabbitMQ order events, the
      actuator + Micrometer + tracing, the Testcontainers suite, the layered
      Dockerfile, the Helm chart), a notification service (the event-driven
      consumer, the retry, the DLQ, the templating), an API gateway (the
      routing, the rate limiting, the auth, the aggregation), a batch
      reconciliation job (Spring Batch, the partitioning, the reporting), a
      feature-flag service (the config, the evaluation, the cache)
  13-CHEATSHEET

───────────────────────────────────────────────────────────────────────────────
FOLDER 08 — 08-fullstack-capstone
───────────────────────────────────────────────────────────────────────────────
  ONE-LINE: the complete shop — React + Spring Boot + PostgreSQL + Redis +
            RabbitMQ, containerised, on Kubernetes, monitored, in CI/CD.
  ⭐⭐ THIS IS THE CENTREPIECE AND IT MUST PLUG INTO MY FOUR EXISTING PATHS:
     ../docker-learning-path/          the images and the Dockerfiles
     ../kubernetes-learning-path/      the manifests, the cluster (kind `learn`)
     ../monitoring-alerting-learning-path/  Prometheus + Grafana + OTel (namespace `obs`)
     ../cicd-learning-path/            the pipelines (Azure DevOps + GitHub Actions + Jenkins)
  Use the SAME app name (`shop`), the SAME services (shop-ui, shop-api,
  checkout, order-worker, payment-mock), the SAME namespace (`shop`), the SAME
  registry (ghcr.io/3558bhk). Continuity is the point.
  01-the-architecture      the C4 diagrams, the bounded contexts, the data
      flow, the synchronous and asynchronous paths, the ADRs ⭐⭐ (write real
      Architecture Decision Records for every significant choice, with the
      alternatives and the trade-offs — this is the SDE 3 artefact)
  02-the-backend           the Spring Boot services, end to end, with the
      domain model, the API contract (OpenAPI), the persistence, the events,
      the security, the observability
  03-the-frontend          the React app, end to end, with the API client
      generated from the OpenAPI spec ⭐, the state architecture, the four UI
      states, the tests, the a11y
  04-the-integration       the contract testing ⭐⭐, the CORS, the auth flow
      end to end (the token, the refresh, the propagation), the error contract,
      the API versioning, the local development environment (docker compose
      ⭐ with everything), the seed data
  05-the-security          the threat model ⭐⭐⭐ (STRIDE on the real system),
      the authN/authZ end to end, the secrets, the dependency scanning, the
      SAST/DAST, the OWASP ASVS checklist, the penetration-test findings and
      the fixes
  06-the-observability     the metrics (the RED for the API, the USE for the
      resources), the traces across the frontend→backend→database→queue, the
      structured logs with the correlation id, the dashboards, the SLOs and
      the error budget, the alerts ⭐⭐ (cross-ref the monitoring path, and
      extend it)
  07-the-deployment        the Dockerfiles (the layered jar, the multi-stage
      React build with nginx ⭐⭐), the Helm charts, the Kubernetes manifests,
      the CI/CD pipelines in all three tools (cross-ref the CI/CD path), the
      GitOps config repo, the progressive delivery, the rollback drill
  08-THE-CAPSTONE-TASKS    ⭐⭐ 8 tasks with full answers at the END:
      T1 add a new feature end to end (a product review) across both stacks
      T2 make the checkout resilient (the circuit breaker, the retry, the
         idempotency, the saga, the DLQ) and prove it with a chaos test
      T3 ⭐ cut the p99 latency in half — measure, find the bottleneck (it's
         an N+1 and a missing index and a chatty frontend), fix, re-measure
      T4 ⭐⭐ add a second region and make the data layer multi-region aware
         (the consistency model, the routing, the failover) — a design task
         with a written answer, not code
      T5 the security review — find and fix 10 real vulnerabilities in a
         deliberately vulnerable version
      T6 ⭐ the incident — a scripted production failure, from the alert to
         the diagnosis to the fix to the post-mortem
      T7 the cost review — the resource requests, the rightsizing, the
         autoscaling policy, the bill
      T8 ⭐⭐ the interview walkthrough — narrate the whole system in 20
         minutes, with the 30 follow-up questions and the answers

───────────────────────────────────────────────────────────────────────────────
FOLDER 09 — 09-sde3-interview-vault
───────────────────────────────────────────────────────────────────────────────
  ONE-LINE: the MAANG SDE 3 layer — the question banks and the model answers.
  01-java-deep-dive-300.md      300 questions grouped by topic, each with a
      🔑 model answer at SDE 3 depth INCLUDING the follow-up and its answer.
      Not one-liners — the answer you'd give over 3 minutes.
  02-lld-question-bank.md       the 25 LLD problems as TIMED SCRIPTS: the
      minute-by-minute plan for a 45-minute round, what to say at each
      minute, where to spend the time, the pushback and the response.
      (Cross-reference 02B for the full solutions.)
  03-hld-for-java-devs.md       where the Java choices meet the system design:
      the JVM in a distributed system, the GC pause and the tail latency, the
      thread model and the scaling unit, the connection pool and the
      downstream saturation, the caching layers, the idempotency, the
      consistency models in JPA terms
  04-concurrency-interviews.md  the hardest round, isolated: the JMM
      questions, the lock-free questions, the "find the race" code reviews,
      the virtual threads questions, the executor sizing questions, the
      deadlock diagnosis from a thread dump (⭐ with real jstack output to
      read)
  05-collections-internals.md   the HashMap/ConcurrentHashMap from memory, the
      "implement an LRU" whiteboard, the "what does this print" set, the
      complexity questions, the choose-the-right-collection scenarios
  06-jvm-gc-performance.md      the staff-level round: the GC selection, the
      tuning, the memory-leak hunt, the latency investigation, the flame
      graph, the benchmark critique (⭐ "here is a benchmark, tell me what's
      wrong with it")
  07-spring-interviews.md       the framework depth: the bean lifecycle from
      memory, the AOP proxy and self-invocation, the transaction propagation
      scenarios, the auto-configuration mechanism, the security filter chain,
      "your @Transactional isn't working — list every reason"
  08-behavioural-sde3.md        ⭐⭐ the SDE 3 bar is not the code. The
      leadership and scope questions, the STAR structure, the Amazon LP and
      the Google Googleyness mapping, the "tell me about a time you disagreed
      with a senior engineer", the "tell me about a technical decision you
      got wrong", the ambiguity and the influence-without-authority
      questions, the 12 stories I need prepared and how to structure each,
      the "what does an SDE 3 do that an SDE 2 doesn't" answer
  09-what-happens-when.md       the classic openers end to end: "what happens
      when you type a URL and press enter" ⭐⭐⭐ (the DNS, the TCP, the TLS,
      the CDN, the load balancer, the servlet container, the DispatcherServlet,
      the controller, the JPA, the pool, the database, the query plan, the
      response, the render, the hydration — the FULL stack I'm learning),
      "what happens when you run java Foo", "what happens when a Spring Boot
      app starts", "what happens when you call a method on a @Transactional
      bean", "what happens when a HashMap resizes", "what happens when the GC
      runs", "what happens when a request hits your Kubernetes service"
  10-mock-interview-scripts.md  six complete 45-minute rounds, scripted with
      both sides: a coding round, an LLD round, an HLD round, a Java-deep-
      dive round, a debugging/incident round, a behavioural round. With the
      interviewer's internal scoring notes ⭐⭐ so I can see what "meets the
      bar" sounds like versus "exceeds it".

═══════════════════════════════════════════════════════════════════════════════
PART 6 — VERSION ANCHORS (verify by web search before you start)
═══════════════════════════════════════════════════════════════════════════════

Do NOT guess versions. Search for the current ones and record them in each
folder's README in a "🔖 Version anchors" block with the date you checked.
The things to verify:

  · the current Java LTS and the current GA release, and which features are
    PREVIEW vs FINAL in each (⭐ this changes every six months — do not rely
    on training data)
  · the JDK distribution to use (Temurin) and its version
  · Maven and Gradle current versions
  · JUnit 5, Mockito, AssertJ, Testcontainers versions
  · the Spring Framework and Spring Boot current GA and supported lines
    (⭐ and which Spring Boot version requires which Java minimum)
  · Hibernate ORM and the Jakarta Persistence version
  · HikariCP, Flyway, Lombok, MapStruct, Jackson versions
  · Node.js LTS, npm/pnpm, Vite, TypeScript, React (⭐ and the React Compiler
    status), TanStack Query, React Router, Tailwind, Vitest, Playwright
  · PostgreSQL and MySQL current versions
  · Redis, RabbitMQ/Kafka current versions
  · the browser baseline (⭐ what is Baseline Widely Available today — the
    "modern CSS" file must reflect reality, not 2020)

Baseline for teaching: Java 21 as the PRIMARY (it matches the shop-api in my
existing Kubernetes/Monitoring/CI-CD paths), with every newer feature marked
`// since Java N` and a clearly separated "Java 25 LTS and beyond" section.
Say explicitly when a feature is preview and needs --enable-preview.

═══════════════════════════════════════════════════════════════════════════════
PART 7 — THE FOOTER (every single file, exactly this)
═══════════════════════════════════════════════════════════════════════════════

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*<a tagline specific to this file — one line, about what this file is for>*

</div>

═══════════════════════════════════════════════════════════════════════════════
PART 8 — DELIVERY MECHANICS
═══════════════════════════════════════════════════════════════════════════════

1. START BY VERIFYING THE VERSIONS (PART 6) with web searches, and tell me
   what you found before you write anything.

2. CREATE THE ROOT FIRST: /home/user/java-fullstack-learning-path/README.md
   and 00-MASTER-ROADMAP.md. The README must contain the full tree with a
   ONE-LINE EXPLANATION for every folder and every file (I asked for this
   explicitly), the reading order, the total time budget, and the version
   anchors.

3. THEN FOLDER 1, FILE BY FILE, IN ORDER. Generate ONE FILE PER RESPONSE.
   Do not summarise a file to fit — write it completely. If a file is too
   large for one response, write it in sequential appends within the same
   turn and confirm the final line count.

4. AFTER EACH FILE, report: the path, the line count, and confirm the footer
   is present.

5. DO NOT ASK ME CLARIFYING QUESTIONS. Where a choice exists, make the
   sensible one, state it, and move on. I prefer things built over things
   discussed.

6. WHEN A FILE WOULD EXCEED ~8,000 LINES, split it (02A-1/02A-2) and update
   the README index. Never truncate content to fit.

7. EVERY file: the table of contents at the top with the anchor link to the
   tasks-and-answers section, and the footer at the bottom.

8. CROSS-REFERENCE FREELY between folders — the value of this path is that
   the same concept (the Proxy pattern, the fail-fast iterator, the N+1, the
   event loop vs the JVM's threads) shows up in Java, in the frontend, in
   Spring, and in the interview vault. Say "⭐ you have seen this before, in
   04-ADVANCED §C — here it is again wearing a different hat."

═══════════════════════════════════════════════════════════════════════════════
PART 9 — THE ACCEPTANCE CHECKLIST (verify before you say a file is done)
═══════════════════════════════════════════════════════════════════════════════

□ the footer is present and exact
□ the table of contents has an anchor link to the tasks-and-answers section
□ every program is complete and compilable — no `// ...` elisions
□ every program has the header block (WHAT / WHY / OUTPUT / JAVA version)
□ every program's comments explain WHY, and every new construct is explained
□ every program has its exact expected output in a comment block
□ every program is numbered PROGRAM <file>.<n>
□ all practice questions AND all answers are at the END, never inline
□ File 02A has exactly 5 assignments for each of its 21 topics, with solutions
□ every major topic has a 🔑 interview line
□ every comparison is a table
□ every hierarchy, memory layout and flow is an ASCII diagram
□ every feature is marked `// since Java N`, and every preview feature is
  labelled ⚠️ PREVIEW
□ every recommendation states its cost and when the opposite choice is right
□ the version anchors were verified by web search, not guessed
□ nothing is summarised to save space — completeness over brevity
□ the file cross-references the other folders where the concept recurs
□ ⭐ and the SDE 3 depth is actually there: internals, failure modes,
  trade-offs, and the thing a senior engineer would push back on
```

## 📋 STOP COPYING HERE

---

## How to drive it

| You say | You get |
|---|---|
| *(paste the whole block above)* | The version anchors + the root `README.md` + `00-MASTER-ROADMAP.md` |
| `GENERATE 01-core-java/01-BASICS-AND-TOPIC-MAP.md` | File 1 |
| `GENERATE 01-core-java/02A-CASE-A-oops-complete.md` | File 2 Case A — the big one |
| `GENERATE 01-core-java/02B-CASE-B-lld-for-sde3.md` | File 2 Case B |
| `GENERATE 01-core-java/03-FILE-HANDLING-AND-IO.md` | File 3 |
| `GENERATE 01-core-java/04-ADVANCED-CORE-JAVA.md` | File 4 — the SDE 3 differentiator |
| `GENERATE 01-core-java/05-JDBC-BASICS-AND-CRUD.md` | File 5 |
| `GENERATE 01-core-java/06-COLLECTIONS-MASTERY.md` | File 6 |
| `GENERATE 01-core-java/07-PROJECTS.md` then `08-CHEATSHEET.md` | Folder 1 complete |
| `NOW FOLDER 2 — generate 02-frontend/README.md and html/ file by file` | The frontend |
| `CONTINUE — css/ file by file` … `react/ file by file` … `projects/` | etc. |

**Two useful recovery commands:**
- `REGENERATE SECTION <n> OF <file> — IT WAS TOO SHALLOW`
- `VERIFY <folder>: list every file, its line count, and confirm each has the footer and the tasks-and-answers anchor`

---

## What this prompt encodes that a plain request wouldn't

| Requirement of yours | Where it's enforced |
|---|---|
| *"EXPLAIN THE CODE IN COMMENTS FOR EACH PROGRAM"* | PART 3 — a literal template with the header block, the WHY-not-WHAT rule, the program numbering and the expected-output block |
| *"5 ASSIGNMENT FOR EACH TOPIC"* (OOPS) | PART 4A — five, graduated reproduce→vary→combine→break→design, and File 02A is spec'd with 21 topics so that's 105 assignments |
| *"ONE LINE EXPLANATION FOR EACH FILE"* | PART 5 gives every file a `ONE-LINE:` header; PART 8 step 2 makes the root README carry them all |
| *"LIST ALL TOPICS"* (File 1) | File 01 spec — the topic map with a mastery level per topic, as your revision index |
| *"DON'T LEAVE ANYTHING"* (OOPS) | File 02A — 22 enumerated sections, and PART 1 rule 12 forbids "and so on" |
| *"LLD OOPS COMPLETE FOR SDE 3"* | File 02B — SOLID + all 23 GoF + 12 beyond-GoF + 25 worked MAANG problems |
| *"COLLECTIONS — I NEED TO MASTER EACH"* | File 06 — internals from the JDK source, complexity AND memory tables, and writing four collections from scratch |
| *"BASIC PROJECTS AS WELL"* | File 07 (10 Core Java) + 15 frontend + 5 per backend folder + the capstone |
| *"FRONTEND → MULTIPLE SUB FOLDERS, MULTIPLE FILES"* | Folder 2 — html/10, css/13, dom/10, javascript/13, react/19, projects/15 |
| *"SAME WAY FOR JDBC, JSP, SERVLETS, HIBERNATE, SPRING, SPRING BOOT"* | Folders 3–7, each to Folder 1's depth |
| *"SAME WAY LIKE PREVIOUS PROJECT"* | PART 1 (the 14 style rules), PART 7 (the exact footer), PART 4 (tasks + answers at END), and the app continuity with your Docker/K8s/Monitoring/CI-CD paths |
| *"SDE 3 FOR MAANG"* | Folder 9 + the ⭐⭐⭐ markers throughout + PART 1 rules 9 and 14 (the interview line, and the trade-off honesty) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*The prompt that builds the path.*

</div>
