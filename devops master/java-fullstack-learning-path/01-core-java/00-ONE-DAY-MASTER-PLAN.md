# ⏰ `01-core-java/00` — THE ONE-DAY MASTER PLAN

### Twelve hours. The **spine** of Core Java — from "what does `javac` actually produce?" to drawing `HashMap` from memory.

> **Read this before you start, and read the honesty note first.**

---

## ⭐ The honesty note

Core Java is **55–70 hours** of material across ten files. Nobody learns it in one day, and any plan that claims otherwise is selling you something.

What one day *can* do — and what this plan is actually for:

| This plan gives you | This plan does not give you |
|---|---|
| ⭐ The **complete map** — you will know every topic that exists and how deep it goes | The depth. That is the 6-day version below |
| The **spine**: the ten ideas that everything else hangs off | The 100 assignments |
| Enough to **read the other nine files fast**, because nothing will be unfamiliar | Interview-level recall — that needs the retrieval practice in [`../00-MASTER-ROADMAP.md`](../00-MASTER-ROADMAP.md) §11 |
| A **measured baseline**: you will score checkpoint A before and after | Concurrency, generics, streams, the JVM — all in `04`, which is deliberately *not* in this day |

**Use it three ways:**
1. **As a day** — if you have one free day and want the shape of the whole language.
2. ⭐ **As the first day of the 6-day plan** (below) — the recommended use.
3. **As a revision day** — after you finish the folder, run it again cold. Anything you cannot do is what you re-read.

---

## 📇 Contents

- [The day at a glance](#the-day-at-a-glance)
- [Before you start — 20 minutes of setup](#before-you-start--20-minutes-of-setup)
- [H1–H10, hour by hour](#-h1--05000600--️-setup-and-the-map)
- [If the day goes wrong](#if-the-day-goes-wrong)
- [End-of-day checklist](#end-of-day-checklist)
- [⭐ The 3-day split (recommended minimum)](#-the-3-day-split-recommended-minimum)
- [⭐⭐ The 6-day split (the real plan)](#-the-6-day-split-the-real-plan)
- [The assignment map](#the-assignment-map)
- [Related files](#related-files)

---

## The day at a glance

```
05:00 ┃ H1  ⚙️  setup + THE MAP (every topic, tagged by importance)
06:00 ┃ H2  🧠 how Java actually runs: javac → bytecode → JVM → JIT
07:30 ┃ H3  🔢 primitives, wrappers, the Integer cache trap, operators
      ┃        ☕ 09:00–09:30 BREAK
09:30 ┃ H4  🔀 control flow, arrays, methods, overloading resolution
11:00 ┃ H5  ⭐⭐ PASS BY VALUE (four proofs) + String and the pool
      ┃        🍽️ 12:30–13:15 LUNCH
13:15 ┃ H6  📦 static, initialisation ORDER, stack vs heap, the two Errors
15:00 ┃ H7  🏛️ OOP core I: classes, constructors, inheritance, overriding
      ┃        ☕ 16:30–17:00 BREAK
17:00 ┃ H8  🎭 OOP core II: polymorphism, encapsulation, interfaces, abstract
19:15 ┃ H9  ⭐ Object methods, immutability, record + sealed = ADTs
      ┃        🍽️ 21:00 dinner
21:00 ┃ H10 ⭐⭐⭐ COLLECTIONS: HashMap from memory, ArrayList, choosing fast
23:00 ┃ ✅ end-of-day checklist + checkpoint A re-test
```

| Marker | Meaning |
|---|---|
| ✅ **VERIFY** | a command to run or a sentence to say out loud. **Do not skip these** — they are how you know the hour landed |
| ⏭ **SKIP** | genuinely skippable if you are behind, with what it costs you |
| ⭐ | worth memorising |
| ⭐⭐ | separates a junior from a senior |
| ⭐⭐⭐ | separates a senior from an SDE 3 |
| 🧪 **LAB** | type it, run it, predict the output first |

---

## Before you start — 20 minutes of setup

```bash
# ⭐ Java 21 (the baseline for this whole folder)
java -version         # ✅ VERIFY: openjdk 21.x — if not, see README §the lab
javac -version
jshell --version

# the lab
mkdir -p ~/java-fullstack/01-core-java-lab/{basics,oop,collections}
cd ~/java-fullstack/01-core-java-lab

# ⭐ the single-file launcher — this is how you'll run everything today
cat > basics/Hello.java <<'EOF'
package com.shop.demo.basics;

// ══════════════════════════════════════════════════════════════════════
// PROGRAM 01.01 — the smallest real Java program
// ══════════════════════════════════════════════════════════════════════
// WHAT   : prints one line.
// WHY    : every modifier in `main` is load-bearing. H1 asks you to justify
//          each one; H2 shows you the bytecode it becomes.
// OUTPUT : shown below.
// JAVA   : 8+ (but see the Java 25 compact form at the bottom)
// ══════════════════════════════════════════════════════════════════════
public class Hello {                 // `public`: the launcher must be able to
                                     //   find this class from outside its
                                     //   package. Remove it → still runs with
                                     //   `java Hello.java`, fails with
                                     //   `java -cp out com.shop.demo.Hello`
    public static void main(String[] args) {
        //        │      │    └─ the command-line arguments, never null
        //        │      └────── no return value
        //        └───────────── belongs to the CLASS, not an instance.
        //                      The JVM must call it before any object exists,
        //                      so it cannot be an instance method.
        //                      ⭐ Java 25 finalised an instance `main()` —
        //                        the JVM now creates the object for you.
        // ───────────────────── the launcher looks up exactly this signature
        System.out.println("hello");
        //     │    └────────── a PrintStream that is auto-flushed on newline
        //     └─────────────── a static field on java.lang.System,
        //                       initialised before main runs
        // ──────────────────── java.lang: the only package auto-imported
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// hello
// ──────────────────────────────────────────────────────────────────────
//
// ⭐ The Java 25 equivalent (compact source file + instance main):
//      void main() { IO.println("hello"); }
//    No class, no static, no public, no String[]. Run the same way.
EOF

java basics/Hello.java                  # ✅ VERIFY: prints "hello"

# ⭐ now look at what javac actually produced
javac -d out basics/Hello.java
javap -c -p out/com/shop/demo/basics/Hello.class
# ✅ VERIFY: you can see `public static void main`, `getstatic`, `ldc`,
#            `invokevirtual`, `return`. You have now seen bytecode. That is
#            the whole point of this command — the JVM stops being magic.

ls -la out/com/shop/demo/basics/        # ✅ VERIFY: a .class file, ~500 bytes
```

⛔ **If `java basics/Hello.java` fails:** you are on Java 10 or older. The single-file source launcher needs Java 11+. Fix Java before continuing — everything today assumes it.

---

# 🌅 H1 · 05:00–06:00 — ⚙️ Setup and THE MAP

**File:** `01-BASICS-AND-TOPIC-MAP.md` — the map section only.
**Goal:** know the entire territory before you walk into it.

| Time | Do |
|---|---|
| 0:00–0:15 | Finish the setup above if you have not. Confirm all three ✅ VERIFYs |
| 0:15–0:45 | ⭐ **Read the topic map.** Do not learn anything. Just read every topic and its tag: `[MUST KNOW]` · `[SHOULD KNOW]` · `[SDE3 DIFFERENTIATOR]` · `[RARELY ASKED]`, and the file that covers it |
| 0:45–1:00 | On paper: write the four tags, and under each, the topics you can already name. This is your map of the map |

⭐ **Why the map comes first, every time.** You retain information dramatically better when you already know where it goes. Reading the map is 30 minutes that makes the next 60 hours roughly 20% more effective. It is the highest-return half hour in this folder.

✅ **VERIFY:** say out loud — *"Core Java is N topics. About a third are MUST KNOW, and they are: …"* and name at least ten.

⏭ **SKIP:** nothing. This is the cheapest, highest-leverage hour of the day.

---

# 🧠 H2 · 06:00–07:30 — How Java actually runs

**File:** `01-BASICS-AND-TOPIC-MAP.md` §1–§2.

| Time | Do |
|---|---|
| 0:00–0:20 | JDK vs JRE vs JVM — what each contains and which one you need to *run* vs *build*. What `javac` is and what it produces |
| 0:20–0:40 | Bytecode. Why it exists. **"Write once, run anywhere" — and what it actually costs** (the JVM per platform, the lowest-common-denominator API, JIT warmup) |
| 0:40–1:05 | 🧪 **LAB — the whole pipeline by hand:** `javac Hello.java` → `javap -c` → read the bytecode → `java Hello` → then break it three ways (wrong classpath, no `main`, `main` not `static`) and read each error |
| 1:05–1:20 | The classpath. `-cp`, `CLASSPATH`, the default `.`, why "class not found" is *almost always* a classpath or package-directory mismatch |
| 1:20–1:30 | ⭐ The **JIT**: interpreted first, then C1/C2 compile hot methods. Why Java is "slow to start, fast to run", and what that means for a container that scales to zero |

🧪 **LAB — the three ways to break `main`:**

```bash
# 1. remove `static`
sed 's/public static void main/public void main/' basics/Hello.java > /tmp/Bad1.java
java /tmp/Bad1.java
# ⛔ "An instance method cannot be referenced from a static context" —
#    actually: the launcher cannot find a MAIN method. Note the message.

# 2. change `String[] args` to `String args`
# 3. rename `main` to `Main`
# ✅ VERIFY: you have seen all three errors and know what each means.
#    ⭐ These three are 90% of "my Java program doesn't run" questions.
```

✅ **VERIFY — say out loud, in order:** *"javac turns `.java` into `.class` bytecode. The `java` launcher starts a JVM, which loads the class through a classloader, verifies the bytecode, and invokes `public static void main(String[] args)`. Methods start interpreted; the JIT compiles the hot ones to machine code, which is why Java warms up."*

🔑 **The interview line:** *"Java is compiled twice — once ahead-of-time to platform-neutral bytecode, then at runtime by the JIT to machine code guided by the actual execution profile. That's why it starts slower than Go but reaches comparable steady-state throughput, and it's why JVM tuning is about warmup and heap, not about 'making it compile faster'."*

⏭ **SKIP:** the classloader hierarchy detail (parent delegation, `URLClassLoader`) — it returns properly in `04-ADVANCED-CORE-JAVA.md`.

---

# 🔢 H3 · 07:30–09:00 — Primitives, wrappers, operators

**File:** `01-BASICS-AND-TOPIC-MAP.md` §3–§5.

| Time | Do |
|---|---|
| 0:00–0:20 | All 8 primitives: sizes, ranges, defaults. Say `int`'s range from memory. Why there is no unsigned anything |
| 0:20–0:35 | ⭐ `float`/`double` are binary fractions. 🧪 **LAB:** print `0.1 + 0.2`. Then `BigDecimal("0.1").add(BigDecimal("0.2"))`. ⭐ **Money is never a `double`** — it is a `long` of cents or a `BigDecimal` |
| 0:35–0:55 | Wrappers, autoboxing/unboxing, and ⭐⭐ **the cache**: `Integer.valueOf` caches −128..127. 🧪 **LAB** below. Then: the NPE on unboxing a `null` `Integer`, and the boxing cost in a tight loop |
| 0:55–1:15 | Operators. `&&` vs `&`, `\|\|` vs `\|` — 🧪 **prove short-circuiting with a side effect**. Then every bitwise operator with its use case: flags, masks, and ⭐ `(n-1) & hash` (which returns in H10) |
| 1:15–1:30 | Precedence and associativity — skim the table, then accept the rule: ⭐ **just use parentheses.** Casting: widening vs narrowing, `(int)` truncates, `Math.round` rounds, and `'a' + 1` is an `int` |

🧪 **LAB — the wrapper cache, in `jshell` (2 minutes, unforgettable):**

```
jshell> Integer a = 127, b = 127; a == b
$1 ==> true                       ← same cached object

jshell> Integer c = 128, d = 128; c == d
$2 ==> false                      ← ⭐ two distinct objects

jshell> c.equals(d)
$3 ==> true                       ← ✅ the only correct comparison

jshell> System.identityHashCode(a) == System.identityHashCode(b)
$4 ==> true                       ← proof they are literally the same object

jshell> Integer e = null; int x = e;
$5 ==> NullPointerException       ← ⛔ unboxing a null. This is a real,
                                       common production NPE.
```

🧪 **LAB — short-circuit, proven:**

```java
// PROGRAM 01.02 — && versus &, with a side effect that proves the difference
public class ShortCircuit {
    static boolean touch(String label) {         // a method with a visible
        System.out.println("  evaluated " + label);   // side effect
        return false;                            // returns false so the
    }                                            // second operand is always
    public static void main(String[] args) {     // *eligible* to be skipped
        System.out.println("a && b:");
        System.out.println("  -> " + (touch("a") && touch("b")));
        System.out.println("a & b:");
        System.out.println("  -> " + (touch("a") &  touch("b")));
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// a && b:
//   evaluated a
//   -> false            ⭐ b was NEVER evaluated — short-circuit
// a & b:
//   evaluated a
//   evaluated b         ⭐ b WAS evaluated — single & does not short-circuit
//   -> false
// ──────────────────────────────────────────────────────────────────────
// 🔑 THE INTERVIEW LINE: "&& and || short-circuit; & and | on booleans do
//    not. In practice that means & is only correct when the second operand
//    has a side effect you NEED — which is almost never, so & on booleans
//    in real code is usually a bug where someone typed one character."
```

✅ **VERIFY:** you have seen `0.30000000000000004` with your own eyes; you can state why `Integer 127 == 127` but `128 != 128`; you can name the two errors a missing short-circuit causes (an NPE on `s != null && s.length() > 0`, and an unnecessary expensive call).

⏭ **SKIP:** the full precedence table (memorise 4 rows: `()` → unary → `* / %` → `+ -` → relational → equality → `&&` → `||` → ternary → assignment; use parentheses for the rest). Octal/hex literal syntax beyond `0x`.

☕ **09:00–09:30 BREAK.** Stand up. Do not read Java.

---

# 🔀 H4 · 09:30–11:00 — Control flow, arrays, methods

**File:** `01-BASICS-AND-TOPIC-MAP.md` §6–§8.

| Time | Do |
|---|---|
| 0:00–0:25 | `if`/`else`, the ternary (⭐ and its numeric-promotion NPE trap), `for`, ⭐ the **enhanced `for`** and what it compiles to for arrays vs `Iterable`s, `while`, `do-while`, `break`/`continue` **with labels** |
| 0:25–0:50 | `switch`: the old statement form, ⭐ the new **expression form** (Java 14), arrow labels (no fall-through!), `yield`, and **exhaustiveness with sealed types** (Java 21) — write the same logic all three ways |
| 0:50–1:15 | Arrays. ⭐ They are **objects**. `length` is a **field**, not a method (and `String.length()` *is* a method — the classic mix-up). 1D/2D/jagged. Default initialisation. Shallow vs deep copy. `Arrays.copyOf` vs `copyOfRange` vs `System.arraycopy` |
| 1:15–1:30 | Methods, and ⭐⭐ **overloading resolution — the exact order the compiler tries**: exact match → widening primitive → boxing/unboxing → varargs. Plus the ambiguity traps and the `null` argument problem |

🧪 **LAB — the same switch, three ways:**

```java
// PROGRAM 01.03 — switch: 1995, 2019, 2023
public class SwitchThreeWays {
    enum Status { NEW, PAID, SHIPPED, CANCELLED }

    // ── 1. the old statement form. ⛔ fall-through is the default and
    //        forgetting `break` is a real, common, silent bug.
    static int rankOld(Status s) {
        int r;
        switch (s) {
            case NEW:       r = 1; break;
            case PAID:      r = 2; break;
            case SHIPPED:   r = 3; break;
            case CANCELLED: r = 0; break;
            default:        r = -1;
        }
        return r;
    }

    // ── 2. the expression form (Java 14+). Arrow labels NEVER fall through,
    //        and it is an EXPRESSION — it produces a value.
    static int rankNew(Status s) {
        return switch (s) {
            case NEW       -> 1;
            case PAID      -> 2;
            case SHIPPED   -> 3;
            case CANCELLED -> 0;
            // ⭐ no `default` needed: the compiler knows every Status is
            //    covered. If you add a constant to the enum, EVERY switch
            //    like this fails to compile. That is the feature.
        };
    }

    // ── 3. yield, when a branch needs more than one statement (Java 14+)
    static String describe(Status s) {
        return switch (s) {
            case NEW       -> "awaiting payment";
            case PAID, SHIPPED -> {          // ⭐ multiple labels, one branch
                String base = s == Status.PAID ? "paid" : "in transit";
                yield base + " — do not cancel";   // ⭐ `yield` returns from
            }                                      //    the switch block
            case CANCELLED -> "cancelled";
        };
    }

    public static void main(String[] args) {
        for (Status s : Status.values()) {
            System.out.printf("%-10s old=%d new=%d  %s%n",
                s, rankOld(s), rankNew(s), describe(s));
        }
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// NEW        old=1 new=1  awaiting payment
// PAID       old=2 new=2  paid — do not cancel
// SHIPPED    old=3 new=3  in transit — do not cancel
// CANCELLED  old=0 new=0  cancelled
// ──────────────────────────────────────────────────────────────────────
// 🔑 THE INTERVIEW LINE: "I use the arrow form and omit `default` whenever
//    the subject is an enum or a sealed type. Omitting default is deliberate:
//    it turns 'someone added a case' from a silent behavioural change into a
//    compile error. Adding a default to an exhaustive switch is a small
//    anti-pattern that costs you that guarantee."
```

🧪 **LAB — overloading resolution, the surprise:**

```java
// PROGRAM 01.04 — which overload is chosen? Predict BEFORE you run it.
public class OverloadResolution {
    static void f(int x)     { System.out.println("f(int)"); }
    static void f(long x)    { System.out.println("f(long)"); }
    static void f(Integer x) { System.out.println("f(Integer)"); }
    static void f(Number x)  { System.out.println("f(Number)"); }
    static void f(Object x)  { System.out.println("f(Object)"); }
    static void f(int... x)  { System.out.println("f(int...)"); }

    public static void main(String[] args) {
        f(1);                        // predict: ?
        f(Integer.valueOf(1));       // predict: ?
        f(null);                     // predict: ?  ⭐ this one is subtle
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// f(int)          ← phase 1: exact match, no boxing, no varargs
// f(Integer)      ← phase 1: exact match again
// f(Integer)      ← ⭐ phase 2 (boxing allowed). Among the reference-type
//                   candidates, Integer is the MOST SPECIFIC, so it wins
//                   over Number and Object.
// ──────────────────────────────────────────────────────────────────────
// ⭐ THE ORDER THE COMPILER TRIES, and it will not move to a later phase
//    until every candidate in the current phase fails:
//      Phase 1 — no boxing, no varargs   (exact + widening primitives)
//      Phase 2 — boxing/unboxing allowed, still no varargs
//      Phase 3 — varargs allowed
// ⚠️ If two candidates in the winning phase are equally specific →
//    "reference to f is ambiguous" — a COMPILE error, not a runtime surprise.
// 🔑 THE INTERVIEW LINE: "Overload resolution happens entirely at COMPILE
//    time, on the STATIC type of the argument. That's why a List<String>
//    passed as a List calls the List overload even though the runtime object
//    is an ArrayList — and it's exactly the contrast with overriding, which
//    is decided at runtime."
```

✅ **VERIFY:** you predicted all three `f(...)` outputs **before** running, and you can state the three phases in order. You can explain why `arr.length` has no parentheses and `str.length()` does.

⏭ **SKIP:** labelled `break`/`continue` beyond seeing one example (rarely used, rarely asked). `Arrays.parallelSort` internals.

---

# ⭐⭐ H5 · 11:00–12:30 — PASS BY VALUE, and String

**File:** `01-BASICS-AND-TOPIC-MAP.md` §9–§10.
**Goal:** the most-asked Java question, answered so well it ends the topic.

| Time | Do |
|---|---|
| 0:00–0:15 | Read the section. Do not write code yet |
| 0:15–0:50 | 🧪 **Write all four proof programs yourself, from memory:** ① a primitive ② an object reference whose *contents* are mutated ③ a reference **reassigned** inside the method ④ a `swap` that fails |
| 0:50–1:05 | ⭐ Say it out loud, twice: **"Java is always pass by value. For objects, the value passed is a copy of the reference."** Then explain precisely why "Java is pass by reference for objects" is wrong |
| 1:05–1:30 | `String`: immutability and the **four reasons** (security, hashing/caching, the pool, thread safety). The pool and `intern()`. `==` vs `.equals()`. ⭐ The compile-time-constant folding surprise. Concatenation and the `StringBuilder` the compiler inserts — and when it does **not** (loops). String vs StringBuilder vs StringBuffer, and ⭐ the honest answer about StringBuffer |

🧪 **LAB — the four proofs (write these yourself; this is the reference shape):**

```java
// PROGRAM 01.05 — pass by value, proven four ways. Run these in order.
public class PassByValue {

    static class Counter { int n = 0; }

    // ① a PRIMITIVE: the method gets a COPY of the value
    static void bump(int x) { x = x + 100; }

    // ② an OBJECT: the method gets a COPY OF THE REFERENCE — which points
    //    at the SAME object, so mutating the object IS visible outside
    static void mutate(Counter c) { c.n = 999; }

    // ③ REASSIGNMENT: the method points its own copy of the reference at a
    //    NEW object. The caller's reference never hears about it.
    static void reassign(Counter c) { c = new Counter(); c.n = -1; }

    // ④ the swap that fails — the canonical interview version
    static void swap(int a, int b) { int t = a; a = b; b = t; }

    public static void main(String[] args) {
        int i = 1;
        bump(i);
        System.out.println("① primitive          : i = " + i + "   (expected 1)");

        Counter c = new Counter();
        mutate(c);
        System.out.println("② object mutated     : c.n = " + c.n + " (expected 999)");

        Counter d = new Counter();
        reassign(d);
        System.out.println("③ reference reassigned: d.n = " + d.n + "  (expected 0)");

        int x = 1, y = 2;
        swap(x, y);
        System.out.println("④ swap               : x=" + x + " y=" + y + " (expected 1,2)");
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ① primitive          : i = 1     (expected 1)
// ② object mutated     : c.n = 999 (expected 999)
// ③ reference reassigned: d.n = 0  (expected 0)
// ④ swap               : x=1 y=2   (expected 1,2)
// ──────────────────────────────────────────────────────────────────────
// WHY ② and ③ differ, and this is the whole answer:
//   the parameter is a COPY of the reference. Through that copy you can
//   reach the object (②) — but you cannot change what the CALLER'S copy
//   points at (③). If Java were pass-by-reference, ③ would print -1.
//   It prints 0. QED.
// 🔑 THE INTERVIEW LINE: "Java is pass by value, always — there is no
//    exception for objects. What is passed for an object is a copy of the
//    reference, so you can mutate the shared object but you cannot rebind
//    the caller's variable. The proof is that a method which reassigns its
//    parameter has no effect on the caller, which pass-by-reference would
//    not allow."
```

🧪 **LAB — the String pool, in `jshell`:**

```
jshell> "a" + "b" == "ab"
$1 ==> true          ← ⭐ CONSTANT FOLDING. Both operands are compile-time
                        constants, so javac folds it to "ab" at compile time
                        and it lands in the pool as the SAME object.

jshell> String s = "a"; (s + "b") == "ab"
$2 ==> false         ← ⭐ `s` is not a compile-time constant, so this is a
                        RUNTIME StringBuilder concatenation → a NEW object.

jshell> final String t = "a"; (t + "b") == "ab"
$3 ==> true          ← ⭐ `final` makes it a compile-time constant again.

jshell> new String("ab") == "ab"
$4 ==> false         ← `new` always allocates, pool or not.

jshell> new String("ab").intern() == "ab"
$5 ==> true          ← intern() returns the pooled canonical instance.
```

✅ **VERIFY:** four programs written, run and predicted. You can say the pass-by-value sentence with no notes. You can explain why `"a"+"b" == "ab"` is `true` but `(s+"b") == "ab"` is `false`.

⛔ **Do not leave this hour until ① ② ③ ④ all make sense.** This is the single most-asked Java fundamentals question. Everything else in the day can be recovered; this one cannot be faked.

🍽️ **12:30–13:15 LUNCH.** Away from the screen.

---

# 📦 H6 · 13:15–15:00 — static, initialisation order, memory

**File:** `01-BASICS-AND-TOPIC-MAP.md` §11–§13.

| Time | Do |
|---|---|
| 0:00–0:25 | `static`: fields, methods, blocks, nested classes, imports. What belongs to the class vs the instance, and why a static method cannot use `this` |
| 0:25–1:00 | ⭐⭐ **THE INITIALISATION ORDER.** 🧪 Write the proof program: a parent and a child, each with a static field, a static block, an instance field initialiser, an instance block, and a constructor — all printing. **Predict the full output before running it** |
| 1:00–1:20 | JVM memory at beginner level: **stack vs heap**, what lives where (primitives and references on the stack frame; objects on the heap; statics in the class data), the diagram |
| 1:20–1:45 | ⭐ `StackOverflowError` vs `OutOfMemoryError` — 🧪 **cause both, on purpose.** Then: packages, imports, access modifiers (preview — the 4×4 matrix is H8), javadoc |
| 1:45–2:00 | The toolchain: `javac -Xlint:all -Werror`, `-g`, `-d`; `java --enable-preview`, `-Xmx`; the `jar` tool; ⭐ `jshell` as a daily tool |

🧪 **LAB — initialisation order (the output is the lesson):**

```java
// PROGRAM 01.06 — the complete Java initialisation order, printed.
// ⭐ Predict the output BEFORE running. Then explain every line.
public class InitOrder {
    static class Parent {
        static int sp = trace("Parent static field");
        static { trace("Parent STATIC block"); }
        int ip = trace("Parent instance field");
        { trace("Parent INSTANCE block"); }
        Parent() { trace("Parent CONSTRUCTOR"); }
    }
    static class Child extends Parent {
        static int sc = trace("Child static field");
        static { trace("Child STATIC block"); }
        int ic = trace("Child instance field");
        { trace("Child INSTANCE block"); }
        Child() { trace("Child CONSTRUCTOR"); }
    }
    static int trace(String what) { System.out.println("  " + what); return 0; }

    public static void main(String[] args) {
        System.out.println("── first Child ──");
        new Child();
        System.out.println("── second Child ──");
        new Child();
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ── first Child ──
//   Parent static field       ← 1. the class is LOADED: statics of the
//   Parent STATIC block          superclass first, in declaration order
//   Child static field        ← 2. then statics of the subclass
//   Child STATIC block
//   Parent instance field     ← 3. per-instance: superclass fields and
//   Parent INSTANCE block        instance blocks, in declaration order
//   Parent CONSTRUCTOR        ← 4. then the superclass constructor BODY
//   Child instance field      ← 5. then subclass fields and blocks
//   Child INSTANCE block
//   Child CONSTRUCTOR         ← 6. then the subclass constructor body
// ── second Child ──
//   Parent instance field     ← ⭐⭐ NO static lines at all. Static
//   Parent INSTANCE block        initialisation happens ONCE per
//   Parent CONSTRUCTOR           classloader, ever.
//   Child instance field
//   Child INSTANCE block
//   Child CONSTRUCTOR
// ──────────────────────────────────────────────────────────────────────
// ⭐ THE RULE, in one breath: statics once (super → sub); then per object,
//    interleave fields/blocks with the constructor chain so that every
//    superclass is FULLY initialised before any subclass field is touched.
// ⚠️ THE FORWARD-REFERENCE TRAP: `int a = b; int b = 1;` is a COMPILE
//    error, but `int a = f(); int f(){ return b; } int b = 1;` compiles and
//    gives a == 0 — because f() runs before b's initialiser.
// 🔑 THE INTERVIEW LINE: "Static initialisation is per classloader and
//    happens once, superclass first. Instance initialisation interleaves
//    field initialisers and instance blocks with the constructor chain,
//    so a superclass is always fully built before a subclass field is set.
//    The practical consequence is the rule about not calling an overridable
//    method from a constructor — the subclass fields aren't assigned yet,
//    so the override sees default values."
```

🧪 **LAB — cause both Errors on purpose:**

```java
// PROGRAM 01.07 — StackOverflowError and OutOfMemoryError, deliberately.
// ⚠️ Run each in a SEPARATE process. Both terminate the JVM.
public class TwoErrors {
    static void recurse(int depth) {          // no base case on purpose
        recurse(depth + 1);                   // ⭐ each call pushes a frame
    }                                         //   onto the thread's stack
    public static void main(String[] args) {
        if (args.length > 0 && args[0].equals("heap")) {
            java.util.List<byte[]> hog = new java.util.ArrayList<>();
            while (true) hog.add(new byte[1024 * 1024]);   // 1 MB at a time
        }
        recurse(0);
    }
}
// run with a SMALL heap so the OOM is fast and safe:
//   java -Xmx32m TwoErrors.java heap   → java.lang.OutOfMemoryError: Java heap space
//   java TwoErrors.java                → java.lang.StackOverflowError
// ──────────────────────────────────────────────────────────────────────
// ⭐ THE DISTINCTION THAT MATTERS:
//   StackOverflowError  — ONE thread's stack is exhausted. Per-thread.
//                         Almost always unbounded/missing-base-case
//                         recursion. Does NOT necessarily mean low memory.
//   OutOfMemoryError    — the HEAP (or metaspace, or "unable to create
//                         native thread") is exhausted. Process-wide.
//                         Means you retained too much, or -Xmx is too small.
// 🔑 THE INTERVIEW LINE: "They're different failures. A StackOverflowError
//    is a per-thread recursion bug and the fix is in the code. An OOM is a
//    retention or sizing problem and the fix is either a leak — something
//    holding a reference it shouldn't — or the heap limit. In production
//    I'd add -XX:+HeapDumpOnOutOfMemoryError so the OOM leaves evidence."
```

✅ **VERIFY:** you predicted the init-order output correctly (or can now explain every line you got wrong). You have caused both Errors and can state the difference in one sentence each.

⏭ **SKIP:** `jar` flags beyond `jar cf`/`jar xf`; javadoc tag syntax; the module system (there is a pointer in `04`).

☕ **15:00–15:30 — this is a real break. The next four hours are the hard ones.**

---

# 🏛️ H7 · 15:30–17:00 — OOP core I

**File:** `02A-CASE-A-oops-complete.md` topics 1–7.
**Goal:** classes, constructors, inheritance, overriding — the mechanics.

| Time | Do |
|---|---|
| 0:00–0:20 | Classes and objects. What `new` actually does: **allocate → zero the memory → set the object header → run the constructor**. Reference vs object. `null`. `this`. Identity (`==`) vs equality (`.equals()`) |
| 0:20–0:35 | Fields and methods: instance vs class(static) vs local. The four kinds of variable and their defaults — ⭐ **locals have NO default**, which is why "variable might not have been initialised" exists. Shadowing |
| 0:35–0:55 | Constructors: default (and when you do **not** get one), parameterised, copy (⭐ Java has no real copy constructor — you write one, and shallow-vs-deep is your decision), `private` (the singleton and the static-factory reasons), `this()` chaining, the implicit `super()`, overloading. ⭐⭐ **"Do not call an overridable method from a constructor"** — with the proof |
| 0:55–1:15 | Inheritance: single, multilevel, hierarchical. ⭐ **Why Java has no multiple inheritance of STATE** — draw the diamond. IS-A vs HAS-A, with the test: *"can you say X is a Y in the DOMAIN, not in the implementation?"* What is inherited and what is not (private members, constructors; statics are **hidden**, not overridden) |
| 1:15–1:30 | Overriding: the rules — same signature, ⭐ covariant return, access can **widen not narrow**, ⭐ cannot throw a **broader checked** exception (and the exact reasoning). `@Override` and what it catches. Hiding vs overriding |

🧪 **LAB — the constructor/overridable-method trap (predict first!):**

```java
// PROGRAM 02.01 — why you must never call an overridable method from a
//                 constructor. Predict the output BEFORE running.
public class ConstructorCallsOverride {
    static class Base {
        Base() {
            System.out.println("  Base() calling describe()");
            describe();          // ⛔ virtual dispatch: the SUBCLASS method
        }                        //   runs — before the subclass fields exist
        void describe() { System.out.println("  Base.describe"); }
    }
    static class Sub extends Base {
        private final String name;
        Sub(String name) {
            // ⭐ the implicit super() runs HERE, first — before `name` is
            //   assigned. So describe() below sees name == null.
            this.name = name;
            System.out.println("  Sub() finished, name=" + name);
        }
        @Override
        void describe() {
            System.out.println("  Sub.describe: name=" + name + " len="
                + (name == null ? "n/a" : name.length()));   // ⛔ NPE risk
        }
    }
    public static void main(String[] args) {
        new Sub("espresso");
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
//   Base() calling describe()
//   Sub.describe: name=null len=n/a     ← ⛔ the subclass override ran,
//   Sub() finished, name=espresso           with an uninitialised field
// ──────────────────────────────────────────────────────────────────────
// WHY: initialisation order (H6). super() completes BEFORE the subclass
//   field initialisers and constructor body. Dynamic dispatch does not care
//   that the object is half-built — it calls the most-derived override.
// ⚠️ In production this is a NullPointerException, or worse: silent wrong
//   values that pass review because the code "looks fine".
// ✅ THE FIXES, best first:
//   1. make the method `private` or `final` — no override is possible
//   2. don't call it: move the work to a static factory that constructs,
//      THEN initialises
//   3. make the class `final`
// 🔑 THE INTERVIEW LINE: "Never call an overridable method from a
//    constructor. Virtual dispatch will run the subclass override against
//    fields that haven't been assigned yet, because super() completes before
//    the subclass initialisers. The fix is a static factory, or making the
//    method final or private. It's the same reason `Object.clone` and
//    frameworks that reflectively instantiate are so careful about
//    construction order."
```

✅ **VERIFY:** you predicted `name=null` before running. You can state the four constructor facts (default only when you declare none; `this()` and `super()` must be the first statement; you cannot have both; the implicit `super()` is inserted). You can give the IS-A/HAS-A domain test.

⏭ **SKIP:** the A1–A5 assignments for topics 1–7 (they are in the 6-day plan). Today is spine only.

---

# 🎭 H8 · 17:00–18:30 — OOP core II

**File:** `02A-CASE-A-oops-complete.md` topics 8–11.
**Goal:** polymorphism, encapsulation, interfaces, abstraction.

| Time | Do |
|---|---|
| 0:00–0:30 | ⭐⭐ **Polymorphism.** Compile-time (overloading) vs runtime (overriding). Up/downcasting, `ClassCastException`, `instanceof`, ⭐ pattern matching for `instanceof` (16+) and for `switch` (21+). **How the JVM implements it: the five `invoke` bytecodes** and which is used for what. The vtable and itable conceptually. ⭐ Why `private`, `static` and `final` methods are not polymorphic |
| 0:30–0:50 | ⭐⭐ **Encapsulation.** The **4×4 access-modifier matrix** — memorise it. Getters/setters and when NOT to write them. Information hiding. Tell-Don't-Ask. The cost of leaking internals: ⭐ returning a mutable collection or a `Date` — and the defensive-copy fix |
| 0:50–1:10 | **Abstraction and interfaces.** Abstract classes and methods; when abstract beats interface. The full interface evolution: Java 8 `default`/`static`, Java 9 `private`. ⭐ **Multiple inheritance of TYPE, and how the diamond comes back** — plus Java's resolution rule ("you must override it yourself"). Functional interfaces and `@FunctionalInterface`. Marker interfaces (`Serializable`, `Cloneable`) and ⭐ why both are considered mistakes |
| 1:10–1:30 | ⭐⭐ The **interface vs abstract class decision table** (12 rows) and the modern default answer. ⛔ The constant-interface anti-pattern. `final` on a variable (⭐ the reference is final, not the object), on a method, on a class, and the blank final |

🧪 **LAB — the 4×4 access matrix, as a program:**

```
                     │ same │ same package │ subclass in │ everywhere
                     │ class│              │ OTHER pkg   │ else
─────────────────────┼──────┼──────────────┼─────────────┼───────────
 private             │  ✅  │      ⛔      │      ⛔      │    ⛔
 package-private     │  ✅  │      ✅      │      ⛔      │    ⛔
   (no modifier)     │      │              │  ⚠️ not even│
                     │      │              │  inherited  │
 protected           │  ✅  │      ✅      │      ✅      │    ⛔
 public              │  ✅  │      ✅      │      ✅      │    ✅
─────────────────────┴──────┴──────────────┴─────────────┴───────────
⭐ THE TWO CELLS PEOPLE GET WRONG:
   • protected from a subclass in ANOTHER package: only through
     INHERITANCE (`this.field`, or `super.m()`) — NOT through a reference
     to another instance of the base class. `otherBase.field` is a compile
     error even inside your subclass.
   • package-private members are NOT inherited across packages at all.
🔑 THE INTERVIEW LINE: "I default to package-private, not private. Private
   makes a class untestable in isolation and unextendable without
   reflection; package-private lets a test in the same package see it while
   keeping it out of the public API. Public is a promise of compatibility
   forever, so I only make things public when I mean that."
```

🧪 **LAB — the diamond, and Java's answer:**

```java
// PROGRAM 02.02 — default methods reintroduce the diamond. This does NOT
//                 compile until you override `hello()`. That is the feature.
interface A { default String hello() { return "A"; } }
interface B { default String hello() { return "B"; } }

public class Diamond implements A, B {
    // ⛔ without this override: "class Diamond inherits unrelated defaults
    //    for hello() from types A and B" — a COMPILE error.
    @Override
    public String hello() {
        return A.super.hello() + B.super.hello();   // ⭐ pick explicitly
    }
    public static void main(String[] args) {
        System.out.println(new Diamond().hello());
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// AB
// ──────────────────────────────────────────────────────────────────────
// ⭐ WHY JAVA IS STILL "NO MULTIPLE INHERITANCE OF STATE": interfaces have
//    no FIELDS (only `public static final` constants). Two defaults can
//    collide, and Java forces YOU to resolve it. But no object can ever
//    inherit two conflicting pieces of mutable state — the diamond problem
//    that C++ has is structurally impossible.
```

✅ **VERIFY:** you can write the 4×4 matrix from memory, including the two surprising cells. You can name the five `invoke` bytecodes and say which one an interface call uses. You can state why Java forbids multiple inheritance of state but allows it of type.

⏭ **SKIP:** the A1–A5 assignments. `Serializable`'s `serialVersionUID` mechanics (returns in `03-FILE-HANDLING-AND-IO.md`).

---

# ⭐ H9 · 19:15–21:00 — Object methods, immutability, record + sealed

**File:** `02A-CASE-A-oops-complete.md` topics 13–15, 18–19.
**Goal:** the material that separates a Java developer from a Java *engineer*.

| Time | Do |
|---|---|
| 0:00–0:35 | ⭐⭐ **`equals` and `hashCode`.** The 5 contract rules (reflexive, symmetric, transitive, consistent, null-hostile). ⭐⭐ **The Liskov impossibility proof** — you cannot subclass and add a field without breaking symmetry. ⭐⭐ The mutable-key orphaning bug, with the program. The `31` multiplier. `Objects.hash` and its boxing cost |
| 0:35–0:50 | `toString` (⭐ why it matters in a log line), `clone` (⛔ why it is broken and what to use instead: a copy constructor or a static factory), `getClass`, `finalize` (⛔ deprecated for removal — use `Cleaner` or try-with-resources) |
| 0:50–1:15 | ⭐⭐ **Immutability.** The 9 rules for a truly immutable class. A full worked example. Defensive copies **in and out**. `final class` vs private constructor. Why immutable objects are automatically thread-safe and hash-safe. The builder as the ergonomics fix |
| 1:15–1:45 | ⭐⭐ **`record` and `sealed`.** The canonical and **compact constructor** (validation and normalisation). What is auto-generated. The restrictions. ⭐ **Local records** — the killer use case. ⭐⭐⭐ `sealed` + `record` + pattern-matching `switch` = **algebraic data types**, with a worked `Result`/`Either`. And ⭐ **a record is only SHALLOWLY immutable** — its components can still be mutable |
| 1:45–2:00 | Composition over inheritance ⭐⭐: delegation, Decorator (⭐ `java.io` is the canonical example), Strategy, and when inheritance *is* right (framework extension points, template method). Aggregation vs composition vs association |

🧪 **LAB — the mutable-key orphaning bug (the most common Java bug in production):**

```java
// PROGRAM 02.03 — mutate a HashMap key and watch the entry become
//                 unreachable WITHOUT being removed. Predict first.
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

public class MutableKey {
    record Order(long id, String item) {}              // ✅ immutable key

    static final class Key {                           // ⛔ mutable key
        private String name;                           // ⛔ NOT final
        private final int id;
        Key(int id, String name) { this.id = id; this.name = name; }
        void rename(String n) { this.name = n; }       // ⛔ the mutation

        @Override public boolean equals(Object o) {
            if (this == o) return true;
            if (!(o instanceof Key other)) return false;
            return id == other.id && Objects.equals(name, other.name);
        }
        @Override public int hashCode() { return Objects.hash(id, name); }
        // ⛔ hashCode uses `name`, which can change. That is the whole bug.
        @Override public String toString() { return "Key[" + id + "," + name + "]"; }
    }

    public static void main(String[] args) {
        Map<Key, Order> map = new HashMap<>();
        Key k = new Key(1, "espresso");
        map.put(k, new Order(42, "espresso machine"));

        System.out.println("before : " + map.get(k));
        k.rename("latte");                               // ⛔ the mutation
        System.out.println("after  : " + map.get(k));
        System.out.println("size   : " + map.size());
        System.out.println("hasKey : " + map.containsKey(k));

        Map<Order, String> ok = new HashMap<>();
        Order o = new Order(42, "espresso machine");
        ok.put(o, "paid");
        System.out.println("record : " + ok.get(new Order(42, "espresso machine")));
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// before : Order[id=42, item=espresso machine]     ✅ found
// after  : null                                    ⛔ LOST
// size   : 1                                       ⭐ still there!
// hasKey : false                                   ⛔ it lies to you
// record : paid                                    ✅ records can't do this
// ──────────────────────────────────────────────────────────────────────
// WHY: HashMap computes index = (n - 1) & hash. After rename() the hash
//   changed, so get() looks in a DIFFERENT bucket, finds nothing, returns
//   null. The entry is still sitting in the OLD bucket. size() counts
//   entries, not reachable keys — so the map grows forever.
// ⛔ THE PRODUCTION INCIDENT: a cache keyed on a mutable object. Hit rate
//   decays to zero over hours while memory grows, and nothing logs an error.
//   It looks like a memory leak AND a cache miss problem at the same time,
//   because it is both.
// 🔑 THE INTERVIEW LINE: "equals and hashCode must agree, and both must be
//   computed from IMMUTABLE state. A mutable key doesn't just fail a lookup
//   — it orphans the entry, so the map leaks memory while reporting fewer
//   contents than it holds. That's why records, and final fields, are the
//   default for anything that goes into a Set or a Map."
```

✅ **VERIFY:** you have seen `size()==1` with `get()==null` and can explain it in terms of buckets. You can state the 5 `equals` rules and sketch the Liskov impossibility argument. You can write a compact record constructor from memory. You can explain what `sealed` + `record` buys you that an `enum` does not.

⏭ **SKIP:** `Cloneable`'s full mechanics (know *that* it is broken and *why*; do not learn to use it). The visitor pattern (it is in `02B`).

🍽️ **21:00 — dinner. The last hour is the most valuable one of the day.**

---

# ⭐⭐⭐ H10 · 21:00–23:00 — COLLECTIONS

**File:** `06-COLLECTIONS-MASTERY.md` — the `Map`, `List` and "choosing" sections.
**Goal:** `HashMap` from memory. This is the most-asked internals question in Java.

| Time | Do |
|---|---|
| 0:00–0:15 | The `Collection` hierarchy — draw it. `Iterable` vs `Collection`. Where `Map` sits (⭐ it does **not** extend `Collection`) |
| 0:15–0:55 | ⭐⭐⭐ **`HashMap` from memory.** The array of buckets. `hash(key)` and the spread function `(h = key.hashCode()) ^ (h >>> 16)`. `index = (n - 1) & hash` and why `n` is a power of two. The linked list in a bucket. ⭐ **Treeify at 8 elements, untreeify at 6, but only if the table is ≥ 64** — otherwise it resizes. Resize at load factor 0.75, doubling, and the rehash |
| 0:55–1:20 | `LinkedHashMap` (insertion vs access order → ⭐ **an LRU cache in 6 lines**), `TreeMap` (red-black tree, O(log n), sorted), `EnumMap` (⭐ an array indexed by ordinal — absurdly fast), the `Map` methods: `getOrDefault`, `computeIfAbsent`, `merge`, `putIfAbsent` |
| 1:20–1:40 | `List`: `ArrayList` (the array, growth by 1.5×, ⭐ O(1) amortised append, O(n) middle insert) vs `LinkedList` (⭐ almost never the right answer — pointer chasing defeats the CPU cache) vs `CopyOnWriteArrayList`. `Set`: `HashSet` **is** a `HashMap`. `TreeSet`. `EnumSet` (⭐ a bit vector) |
| 1:40–2:00 | ⭐⭐ `Iterator` and **fail-fast** (`modCount`, `ConcurrentModificationException`, and why removing in an enhanced-for is a bug). `Comparable` vs `Comparator`. Unmodifiable (`Collections.unmodifiableList` — a *view*) vs **immutable** (`List.of` — real). ⭐ **Choose a collection in 10 seconds** |

🧪 **LAB — the LRU cache in six lines (the interview classic):**

```java
// PROGRAM 06.01 — an LRU cache, using LinkedHashMap's access-order mode.
import java.util.LinkedHashMap;
import java.util.Map;

public class LruCache<K, V> extends LinkedHashMap<K, V> {
    private final int capacity;

    // ⭐ the third constructor argument — `accessOrder=true` — is the whole
    //   trick. It makes the map reorder itself on every get()/put(), moving
    //   the touched entry to the TAIL. So the HEAD is always the least
    //   recently used.
    public LruCache(int capacity) {
        super(capacity, 0.75f, true);
        this.capacity = capacity;
    }

    // ⭐ called by put() AFTER an entry is added. Return true → the eldest
    //   (least recently used) entry is removed. Six lines, a real LRU.
    @Override
    protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
        return size() > capacity;
    }

    public static void main(String[] args) {
        LruCache<String, Integer> c = new LruCache<>(3);
        c.put("a", 1); c.put("b", 2); c.put("c", 3);
        System.out.println("start     : " + c.keySet());
        c.get("a");                                  // ⭐ touch a → a moves
        System.out.println("after get : " + c.keySet() + "   (a moved to tail)");
        c.put("d", 4);                               // ⛔ evicts the eldest
        System.out.println("after put : " + c.keySet() + "   (b evicted)");
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// start     : [a, b, c]
// after get : [b, c, a]   (a moved to tail)
// after put : [c, a, d]   (b evicted)
// ──────────────────────────────────────────────────────────────────────
// ⚠️ NOT THREAD SAFE. For a concurrent LRU: synchronise the whole thing
//   (a bottleneck) or use Caffeine, which is what you'd use in production.
// 🔑 THE INTERVIEW LINE: "LinkedHashMap in access-order mode plus an
//    override of removeEldestEntry gives you an LRU in about six lines, and
//    it's the standard answer. In production I'd use Caffeine, because it
//    adds concurrency, size/time-based eviction, and hit-rate metrics —
//    but knowing the LinkedHashMap version matters because it shows you
//    understand what the library is doing for you."
```

🧪 **LAB — fail-fast, and the correct removal:**

```java
// PROGRAM 06.02 — three ways to remove from a list while iterating.
import java.util.*;

public class RemovingWhileIterating {
    public static void main(String[] args) {
        List<Integer> a = new ArrayList<>(List.of(1, 2, 3, 4, 5, 6));
        // ⛔ 1. THE BUG — enhanced for + remove()
        try {
            for (int n : a) if (n % 2 == 0) a.remove(Integer.valueOf(n));
        } catch (ConcurrentModificationException e) {
            System.out.println("① enhanced-for + remove → " + e.getClass().getSimpleName());
        }
        // ⭐ WHY: the enhanced for compiles to an Iterator. ArrayList.remove()
        //   bumps modCount; the Iterator's next() compares its expectedModCount
        //   against modCount and throws. It is "fail-fast" — a best-effort
        //   bug detector, NOT a guarantee.

        List<Integer> b = new ArrayList<>(List.of(1, 2, 3, 4, 5, 6));
        // ✅ 2. Iterator.remove() — the only correct manual way
        for (Iterator<Integer> it = b.iterator(); it.hasNext(); ) {
            if (it.next() % 2 == 0) it.remove();     // removes via the iterator
        }
        System.out.println("② iterator.remove  → " + b);

        List<Integer> c = new ArrayList<>(List.of(1, 2, 3, 4, 5, 6));
        // ✅ 3. removeIf — the modern answer (Java 8+)
        c.removeIf(n -> n % 2 == 0);
        System.out.println("③ removeIf         → " + c);

        List<Integer> d = List.of(1, 2, 3, 4, 5, 6);
        // ✅ 4. or don't mutate at all — filter into a new list
        List<Integer> e = d.stream().filter(n -> n % 2 != 0).toList();
        System.out.println("④ stream filter    → " + e);
    }
}
// ── OUTPUT ─────────────────────────────────────────────────────────────
// ① enhanced-for + remove → ConcurrentModificationException
// ② iterator.remove  → [1, 3, 5]
// ③ removeIf         → [1, 3, 5]
// ④ stream filter    → [1, 3, 5]
// ──────────────────────────────────────────────────────────────────────
// ⚠️ THE TRAP THAT MAKES THIS DANGEROUS: the exception is BEST EFFORT.
//   Removing the SECOND-TO-LAST element in an ArrayList often does NOT
//   throw — it silently succeeds. So the bug ships, works in testing on a
//   3-element list, and corrupts data on a 3000-element one.
```

**The complexity table — know these cold:**

| Operation | `ArrayList` | `LinkedList` | `HashMap` | `LinkedHashMap` | `TreeMap` | `HashSet` | `ArrayDeque` |
|---|---|---|---|---|---|---|---|
| get by index | **O(1)** | O(n) | — | — | — | — | — |
| get by key | — | — | **O(1)** | **O(1)** | O(log n) | **O(1)** contains | — |
| add at end | **O(1)** amort. | **O(1)** | **O(1)** | **O(1)** | O(log n) | **O(1)** | **O(1)** |
| add at front | O(n) | **O(1)** | — | — | O(log n) | — | **O(1)** |
| add in middle | O(n) | O(n) ⭐ *after* the O(n) walk | — | — | O(log n) | — | — |
| remove by key | — | — | **O(1)** | **O(1)** | O(log n) | **O(1)** | — |
| iteration order | insertion | insertion | ⛔ **unspecified** | insertion *or* access | ⭐ **sorted** | ⛔ unspecified | FIFO/LIFO |
| memory per element | ⭐ low (1 ref) | ⛔ high (2 refs + node) | moderate | moderate | ⛔ high | moderate | low |

⭐ **Choosing a collection in 10 seconds:**

```
Need key → value?
├─ yes ─┬─ need it sorted?              → TreeMap
│       ├─ keys are an enum?            → EnumMap      ⭐ 10× faster
│       ├─ need insertion/access order? → LinkedHashMap
│       ├─ concurrent?                  → ConcurrentHashMap
│       └─ otherwise                    → HashMap      ⭐ the default
└─ no ──┬─ unique elements?             → HashSet (LinkedHashSet for order,
        │                                  TreeSet for sorted)
        ├─ a queue / stack / deque?     → ArrayDeque   ⭐ NOT LinkedList,
        │                                  NOT Stack (Stack is legacy: it
        │                                  extends Vector, so it's
        │                                  synchronised and slow)
        ├─ concurrent + blocking?       → LinkedBlockingQueue / ArrayBlockingQueue
        ├─ read-mostly + concurrent?    → CopyOnWriteArrayList
        └─ otherwise                    → ArrayList    ⭐ the default
```

✅ **VERIFY — the hour's real test.** On a blank page, from memory, in under 5 minutes:
1. Draw `HashMap`: the table array, a bucket with a linked list, a bucket with a red-black tree, and the resize.
2. Write the spread function and the index computation.
3. State the treeify thresholds (**8** to treeify, **6** to untreeify, **64** minimum table size before it treeifies instead of resizing) and the load factor (**0.75**).
4. Write the complexity table for `ArrayList`, `HashMap`, `TreeMap`.
5. Choose a collection for: a cache · a sorted report · a work queue · a set of enabled flags · a read-mostly listener list.

**If you can do all five, you have had a good day.** If not, this is the hour to repeat first tomorrow.

⏭ **SKIP:** `ConcurrentHashMap` internals (CAS + `synchronized` bins), `Spliterator`, TimSort's merge details, `PriorityQueue`'s heap array. ⭐ All of these are in `06` and all are ⭐⭐⭐ material — but they are **day 5–6** material, not hour 12 of day 1.

---

## If the day goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| Setup ate an hour | Java version, PATH, or a Windows/WSL mismatch | ⭐ Install with SDKMAN and stop fighting the OS. Then restart at H1 |
| `javap` output is gibberish | You have never read bytecode | That is normal. You only need to *recognise* `invokevirtual`, `getstatic`, `ldc`. Do not decode the whole thing |
| H5 pass-by-value still does not click | You read the four proofs instead of typing them | ⛔ Stop the day. Type all four programs. This one concept is worth more than H6–H10 combined |
| H7/H8 feel abstract | You have not written enough classes | Write the `shop` domain: `Product`, `Customer`, `Order`, `OrderLine`. Real classes, real relationships, in the lab directory |
| H9 equals/hashCode is confusing | You skipped H7's identity-vs-equality | Go back 20 minutes. `==` on references vs `.equals()` is the prerequisite |
| H10 is too much | It is. ⭐ This hour is 8–10 h of real material compressed | Do only the "HashMap from memory" and the complexity table. Everything else moves to day 5 |
| You are exhausted by 19:00 | 12 hours is too long for new material | Stop. Do the end-of-day checklist, then run the **3-day split** instead |
| You finished with 3 hours to spare | You skipped the LABs | ⛔ Go back and type them. Reading is not doing |

---

## End-of-day checklist

Tick every one. Anything unticked is the top of tomorrow's list.

**Ran and understood**
- [ ] `java Hello.java`, `javac -d out`, `javap -c` — I have read real bytecode
- [ ] `0.1 + 0.2` printed `0.30000000000000004`
- [ ] `Integer 127 == 127` true, `128 == 128` false — in `jshell`, with my own eyes
- [ ] The `&&` vs `&` side-effect proof
- [ ] All three `switch` forms written and run
- [ ] The four overloading-resolution predictions, made **before** running
- [ ] ⭐ All **four** pass-by-value proofs, typed by me
- [ ] The `String` pool `jshell` session, including the `final` surprise
- [ ] The initialisation-order program — **output predicted before running**
- [ ] I caused a `StackOverflowError` **and** an `OutOfMemoryError`
- [ ] The constructor-calls-override trap — predicted `name=null`
- [ ] The diamond default-method compile error, and its fix
- [ ] The mutable-key orphaning bug — I saw `size()==1` with `get()==null`
- [ ] The LRU cache, and the four ways to remove while iterating

**Can say out loud, no notes**
- [ ] "Java is always pass by value; for objects the value is a copy of the reference"
- [ ] The initialisation order, start to finish
- [ ] The 4×4 access-modifier matrix, including the two surprising cells
- [ ] Why `equals` and `hashCode` must agree, and what breaks if they don't
- [ ] `StackOverflowError` vs `OutOfMemoryError` in one sentence each
- [ ] Why Java has no multiple inheritance of state but does of type
- [ ] ⭐ The `HashMap` internals: spread, `(n-1) & hash`, treeify 8/6/64, load factor 0.75
- [ ] The overloading resolution phases, in order

**Scored**
- [ ] Checkpoint A, before: ____ / 10
- [ ] Checkpoint A, after: ____ / 10  ⭐ (target after one day: 4–6)

---

## ⭐ The 3-day split (recommended minimum)

Same content, three days of 6–7 hours. **This is the version that actually produces recall** rather than recognition.

| | Hours | Content | Exit test |
|---|---|---|---|
| **Day 1** | 6–7 | H1 map · H2 how Java runs · H3 primitives/wrappers/operators · H4 control flow/arrays/methods | the four `jshell` sessions, the `switch` three-ways, the overloading predictions |
| **Day 2** | 6–7 | H5 pass-by-value + String · H6 static/init-order/memory · H7 OOP I | ⭐ all four pass-by-value proofs typed; both Errors caused; init order predicted correctly |
| **Day 3** | 7 | H8 OOP II · H9 Object/immutability/record/sealed · H10 collections | the 4×4 matrix from memory; the orphaning bug explained; ⭐ **HashMap drawn in under 5 minutes** |

⭐ **Between days, 15 minutes:** blank-page recall of yesterday, *before* looking at anything. Then mark the gaps. That 15 minutes is worth more than an extra hour of reading.

---

## ⭐⭐ The 6-day split (the real plan)

This is the one that matches the folder's 55–70 hours at ~10 h/day, and it is what [`../00-MASTER-ROADMAP.md`](../00-MASTER-ROADMAP.md) weeks 1–8 spread out at 20 h/week.

| Day | Hours | Files | What is different from the one-day version |
|---|---|---|---|
| **1** | 10 | `00` · `01` (map + §1–§5) | + all practice sets for §1–§5, + A1–A5 for the basics topics, + `08-CHEATSHEET` §primitives |
| **2** | 10 | `01` §6–§13 | + control flow/arrays/methods **assignments**, + the init-order program written twice (once predicted, once explained), + I/O and the toolchain lab |
| **3** | 11 | `02A` topics 1–7 | ⭐ + **35 assignments** (topics 1–7 × 5), including every A4 (break) and A5 (design) |
| **4** | 11 | `02A` topics 8–15 | ⭐ + **40 assignments**, + the 4×4 matrix memorised, + immutability worked example written from scratch |
| **5** | 11 | `02A` topics 16–20 + `02B` start | ⭐ + **25 assignments**, + sealed/record ADTs, + the first 3 LLD problems **timed at 45 min** |
| **6** | 11 | `06` collections in full | ⭐⭐ + `ConcurrentHashMap` internals, `Spliterator`, TimSort, the projects in `07`, + checkpoint A retake (target 9/10) |
| *(then)* | | `03` IO → `05` JDBC → `04` advanced → `02B` LLD → `07` projects | per [`README.md`](./README.md) §the reading order |

---

## The assignment map

`02A-CASE-A-oops-complete.md` has **20 topics × 5 assignments = 100**. Each topic's five are graduated the same way:

| | Name | What it asks | Difficulty |
|---|---|---|---|
| **A1** | reproduce | use the feature exactly as taught | ⭐ |
| **A2** | vary | the same feature in a different shape | ⭐ |
| **A3** | combine | this feature plus two earlier ones | ⭐⭐ |
| **A4** | **break** | find or create the failure mode, and explain it | ⭐⭐ |
| **A5** | **design** | a small real-world modelling problem that forces a choice | ⭐⭐⭐ |

| Day (6-day plan) | Topics | Assignments | IDs |
|---|---|---|---|
| 3 | 1–7 | 35 | `1.1`–`1.5` … `7.1`–`7.5` |
| 4 | 8–15 | 40 | `8.1`–`8.5` … `15.1`–`15.5` |
| 5 | 16–20 | 25 | `16.1`–`16.5` … `20.1`–`20.5` |
| 6 | collections | the `06` practice sets | — |

⭐ **Short on time?** Do **A1, A4, A5** and skip A2/A3. A4 and A5 are where the SDE 3 material lives; A2/A3 are consolidation. That is a far better trade than doing A1–A3 and never reaching the hard ones.

⛔ **Never read a solution before attempting it.** Attempt → get it wrong → *then* read. The wrong attempt is what makes the solution stick. Answers are at the END of `02A`, keyed by number.

---

## Related files

| File | Why |
|---|---|
| [`README.md`](./README.md) | ⭐ this folder's index: one line per file, the reading order, the version anchors, the lab setup |
| [`01-BASICS-AND-TOPIC-MAP.md`](./01-BASICS-AND-TOPIC-MAP.md) | H1–H6 |
| [`02A-CASE-A-oops-complete.md`](./02A-CASE-A-oops-complete.md) | H7–H9, and all 100 assignments |
| [`06-COLLECTIONS-MASTERY.md`](./06-COLLECTIONS-MASTERY.md) | H10 |
| [`02B-CASE-B-lld-for-sde3.md`](./02B-CASE-B-lld-for-sde3.md) | day 5 of the 6-day plan |
| [`08-CHEATSHEET.md`](./08-CHEATSHEET.md) | keep open all day |
| [`../00-MASTER-ROADMAP.md`](../00-MASTER-ROADMAP.md) | where this folder sits in the 19-week plan, and checkpoint A in full |
| [`../09-sde3-interview-vault/01-java-deep-dive-300.md`](../09-sde3-interview-vault/01-java-deep-dive-300.md) | ⭐ open it in week 2 — the interview mirror of everything above |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Twelve hours for the spine. Six days for the muscle. Predict every output before you run it.*

</div>
