# ☕ `01-core-java/` — FOLDER 1 · THE LANGUAGE

> **Build this first. Nothing else in this path works without it.**
>
> 11 files · 55–70 hours · ~100 assignments · the whole of Core Java from "what is a variable?" to "draw `ConcurrentHashMap` from memory".
>
> ⭐ This folder is roughly **60% of a Java interview** and **100% of the prerequisite** for the other eight folders.

---

## 📇 The files, one line each

| # | File | One line | Hours |
|---|---|---|---|
| — | **`README.md`** | This page: the index, the reading order, the Core Java version anchors, and the lab setup | — |
| ⏰ | **`00-ONE-DAY-MASTER-PLAN.md`** | Hour-by-hour for all six core files, plus the 3-day and 6-day versions, the "if the day goes wrong" table, and the end-of-day checklist | — |
| 1 | **`01-BASICS-AND-TOPIC-MAP.md`** | ⭐ **THE MAP FIRST** — every Core Java topic tagged `[MUST KNOW]` / `[SHOULD KNOW]` / `[SDE3 DIFFERENTIATOR]` / `[RARELY ASKED]` with the file that covers it; then the fundamentals from absolute zero: JDK/JRE/JVM, bytecode and the JIT, `javac`→`.class`→`java`, `javap`, the classpath, the `main` signature deconstructed, all 8 primitives, wrapper caches and the `Integer ==` trap, every operator including all the bitwise ones, precedence, casting, control flow (old and new `switch`), arrays, overloading resolution, ⭐⭐ **pass-by-value proven four ways**, `String` immutability and the pool, `static` and initialisation order, stack vs heap, I/O, the toolchain and `jshell` | 10–12 |
| 2A | **`02A-CASE-A-oops-complete.md`** | ⭐ **CASE A — every OOP topic, nothing skipped, exactly FIVE graduated assignments per topic** (A1 reproduce → A2 vary → A3 combine → A4 break → A5 design) with full commented solutions at the END. 20 topics: classes & objects · fields & methods · constructors · initialisation order · inheritance · overriding · overloading vs overriding · polymorphism and the five `invoke` bytecodes · encapsulation and the 4×4 access matrix · abstraction · interfaces and the diamond · `final` · every `Object` method · immutability · composition over inheritance · inner & nested classes · `enum` · `record` · `sealed` · annotations | 18–22 |
| 2B | **`02B-CASE-B-lld-for-sde3.md`** | ⭐ **CASE B — LLD + OOP at the SDE 3 bar.** The 25 MAANG LLD problems with timed 45-minute scripts: requirement gathering, the object model, SOLID with a violation and a fix per principle, the 12 patterns you actually use, class-diagram notation, extensibility vs simplicity, and how to drive the round without being told what to do | 8–10 |
| 3 | **`03-FILE-HANDLING-AND-IO.md`** | Everything about moving bytes: `File` vs `Path`, NIO.2, streams vs readers vs channels, byte vs character and why encodings bite, buffering (measured), `try-with-resources` and `AutoCloseable`, serialisation and why `ObjectInputStream` is a security hole, ZIP/GZIP, file watching, memory-mapped files, and `java.io` as the canonical Decorator pattern | 6–8 |
| 4 | **`04-ADVANCED-CORE-JAVA.md`** | The SDE 3 differentiators: ⭐⭐⭐ **concurrency** (threads, the JMM, `volatile`, `synchronized`, atomics, `java.util.concurrent`, executors, `CompletableFuture`, **virtual threads**), ⭐⭐ **generics** (erasure, wildcards, PECS), reflection & dynamic proxies, lambdas & the Stream API (laziness, short-circuiting, parallel traps), exceptions honestly, `Optional`, **the JVM** (classloading, memory areas, GC algorithms and tuning), date/time, and **what Java 22→26 changed** | 12–15 |
| 5 | **`05-JDBC-BASICS-AND-CRUD.md`** | JDBC from zero: the driver, the `Connection`, `Statement` vs ⭐ `PreparedStatement` with the SQL-injection proof, `ResultSet` and its types, **complete CRUD against the `shop` schema**, transactions and `commit`/`rollback`, batch inserts with the benchmark, and the 8 mistakes everyone makes | 5–6 |
| 6 | **`06-COLLECTIONS-MASTERY.md`** | ⭐ **"master each"** — every collection with its internals, complexity table and failure mode: the hierarchy · `List` (`ArrayList`/`LinkedList`/`CopyOnWriteArrayList`) · `Set` (`HashSet`/`LinkedHashSet`/`TreeSet`/`EnumSet`) · `Map` with ⭐⭐⭐ **`HashMap` from memory** (the hash function, `(n-1) & hash`, treeify at 8/64, resize, the mutable-key orphaning bug) · `LinkedHashMap` and LRU · `TreeMap` · ⭐⭐⭐ **`ConcurrentHashMap`** (lock-free reads, CAS + `synchronized` bins, the size lie) · `Queue`/`Deque`/`PriorityQueue`/`BlockingQueue` · `Iterator` and fail-fast · `Comparable` vs `Comparator` · `Spliterator` · TimSort · unmodifiable vs immutable · and choosing a collection in 10 seconds | 8–10 |
| 7 | **`07-PROJECTS.md`** | The Core Java mini-projects, each with 3–5 tasks and answers at the END: console shop · CSV/JSON persistence · a thread-safe in-memory cache · a log analyser · a mini test framework via reflection · a producer/consumer order queue · a rate limiter · an LRU cache from `LinkedHashMap` | 6–8 |
| 8 | **`08-CHEATSHEET.md`** | All of Core Java on one page: every complexity table, every trap, every `// since Java N`, every 🔑 interview line | — |

---

## 🧭 The reading order

⭐ **Not the same as the file numbering.** The numbers are for reference; this is the order that actually works.

```
        00-ONE-DAY-MASTER-PLAN     ← read this first, 20 minutes
                 │
                 ▼
        01-BASICS-AND-TOPIC-MAP    ← the map, then the fundamentals
                 │                   ⭐ do not skip the map. It is your
                 │                     revision index for the next 6 weeks
                 ▼
        02A-CASE-A-oops-complete   ← the big one. 20 topics × 5 assignments
                 │                   ⚠️ this is 18–22 h. Do NOT rush it.
                 ▼
        06-COLLECTIONS-MASTERY     ← ⭐ deliberately EARLY, not last.
                 │                   OOP → collections is one idea:
                 │                   equals/hashCode/Comparable drive
                 │                   every Set and Map. The gap between
                 │                   them should be days, not weeks.
                 ▼
        03-FILE-HANDLING-AND-IO    ← smaller, and it uses collections
                 │                   and the Decorator pattern you just met
                 ▼
        05-JDBC-BASICS-AND-CRUD    ← now you can persist `shop` for real
                 │
                 ▼
        04-ADVANCED-CORE-JAVA      ← ⭐ LAST, on purpose. Concurrency,
                 │                   generics and the JVM all assume you
                 │                   own everything above. Reading this
                 │                   first is why people think Java is hard.
                 ▼
        02B-CASE-B-lld-for-sde3    ← now that you know the language,
                 │                   design with it
                 ▼
        07-PROJECTS                ← build things. This is where it sticks
                 │
                 ▼
        08-CHEATSHEET              ← keep open forever
```

**Why `06` collections comes third and not seventh:** `HashSet` and `HashMap` *are* `equals`/`hashCode`. `TreeSet` and `TreeMap` *are* `Comparable`/`Comparator`. If you study collections three weeks after OOP, you relearn OOP inside collections. Adjacency is worth more than numbering.

**Why `04` advanced comes last:** every topic in it — the JMM, generics erasure, GC, streams — is a statement about *objects you already understand*. Read first, it is a wall of jargon. Read last, it is a set of "oh, *that's* why" moments.

---

## 🔢 Core Java version anchors — verified **16 September 2026**

| | Version | Note |
|---|---|---|
| ⭐ **Teaching baseline** | **Java 21 LTS** | Released 19 Sept 2023. Support to Sept 2031 (Temurin). Every program in this folder compiles and runs on 21. **This is what your interviewer is running** |
| **Current LTS** | **Java 25 LTS** | GA 16 Sept 2025; latest update **25.0.4.1** (18 Aug 2026). Support to Sept 2033 |
| **Current non-LTS** | **Java 26** | GA 17 Mar 2026, **EOL Sept 2026** |
| **Next** | Java 27 | Due Sept 2026 (RC available now) |
| Build | Maven **3.9.9** / Gradle **8.10** | `./mvnw` is used in all samples |
| Test | JUnit **5.11** | Jupiter API throughout |
| REPL | `jshell` | ⭐ the best Java learning tool that almost nobody uses |

### What each version added, and where this folder covers it

| Since | Feature | Status in Java 21 | Covered in |
|---|---|---|---|
| Java 8 | lambdas, Streams, `Optional`, default methods | final | `04`, `02A` §11 |
| Java 9 | modules, `List.of`/`Map.of`, collection factories, private interface methods, JShell | final | `01`, `06`, `02A` §11 |
| Java 10 | `var` (local type inference) | final | `01` |
| Java 11 | HTTP Client, `String` helpers, single-file source launcher (`java Foo.java`) | final | `01`, `03` |
| Java 14 | `switch` expressions, helpful NPE messages | final | `01` |
| Java 15 | text blocks | final | `01`, `03` |
| Java 16 | ⭐ `record`, `instanceof` pattern matching | final | `02A` §18, §8 |
| Java 17 LTS | ⭐ `sealed` classes | final | `02A` §19 |
| Java 21 LTS | ⭐⭐⭐ **virtual threads**, ⭐ **pattern matching for `switch`**, **record patterns**, sequenced collections | final | `04`, `02A` §18 |
| Java 22 | unnamed variables `_`, stream gatherers (preview) | — | `04` §"what changed" |
| Java 23 | markdown doc comments, primitive patterns (preview) | — | `04` §"what changed" |
| Java 24 | ⭐ stream gatherers (final), class-file API, ZGC generational by default | — | `04` §"what changed" |
| **Java 25 LTS** | ⭐ **instance `main` methods**, **compact source files**, **module import declarations**, **flexible constructor bodies**, **scoped values** (all final); compact object headers, AOT method profiling, generational Shenandoah | — | `01` §main, `04` §"what changed" |
| Java 26 | HTTP/3 in `HttpClient`; *Primitive Types in Patterns* (4th preview, JEP 530) | ⚠️ EOL Sept 2026 | `04` §"what changed" |

⭐ **Two Java 25 features change how you write teaching examples — and you should know both:**

```java
// ── Java 21 and earlier: what every existing codebase looks like ──────────
public class Hello {
    public static void main(String[] args) {      // 4 modifiers, all meaningful
        System.out.println("hello");
    }
}

// ── Java 25+: compact source file + instance main method ─────────────────
// ⚠️ FINAL in Java 25. No `class`, no `static`, no `public`, no `String[]`.
void main() {                                     // an INSTANCE method, no args
    IO.println("hello");                          // java.lang.IO — auto-imported
}                                                 //   in a compact source file
// Run with:  java Hello.java
```

**The teaching decision, stated honestly:** this folder teaches the **Java 21 form** and shows the Java 25 form beside it. Reason — you will be interviewed on a 21 (or 17) codebase, and 99% of the Java you read in the wild uses `public static void main(String[] args)`. But you should be able to say *"that's the Java 25 compact form; we're on 21"* — which is itself a senior signal.

⚠️ **PREVIEW features** appear in this folder exactly twice (primitive patterns, and the gatherer APIs where relevant) and are always labelled:

```text
⚠️ PREVIEW in Java 26 — needs:  javac --release 26 --enable-preview
                                java  --enable-preview
```

---

## 🧰 The lab — set this up once, 10 minutes

```bash
# 1. Java 21 (Temurin, not Oracle — Oracle's JDK has licence terms)
#    macOS:   brew install --cask temurin@21
#    Ubuntu:  sudo apt install -y temurin-21-jdk
#    Windows: winget install EclipseAdoptium.Temurin.21.JDK
#    or hold several with SDKMAN:
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 21.0.5-tem
sdk install maven 3.9.9

java -version          # ✅ VERIFY: openjdk version "21.x"
javac -version
jshell --version

# 2. the lab directory
mkdir -p ~/java-fullstack/01-core-java-lab/{basics,oop,collections,io,jdbc,advanced,projects}
cd ~/java-fullstack/01-core-java-lab

# 3. ⭐ THE POSTGRES FOR FILE 05 (you already know Docker)
docker run -d --name shop-pg \
  -e POSTGRES_PASSWORD=shop -e POSTGRES_DB=shop \
  -p 5432:5432 postgres:17
docker exec -it shop-pg psql -U shop -d shop -c 'select 1'   # ✅ VERIFY

# 4. the shop schema — used by files 05, 06 and 07
docker exec -i shop-pg psql -U shop -d shop <<'SQL'
create table product (
  id          bigserial primary key,
  sku         varchar(32)  not null unique,
  name        varchar(120) not null,
  price_cents bigint       not null check (price_cents >= 0),  -- ⭐ NEVER a
  stock       int          not null default 0,                 --   double for
  created_at  timestamptz  not null default now()              --   money
);
create table customer (
  id    bigserial primary key,
  email varchar(255) not null unique,
  name  varchar(120) not null
);
create table orders (                    -- ⭐ `order` is a SQL keyword
  id           bigserial primary key,
  customer_id  bigint not null references customer(id),
  status       varchar(20) not null default 'NEW',
  total_cents  bigint not null default 0,
  created_at   timestamptz not null default now()
);
create table order_line (
  id         bigserial primary key,
  order_id   bigint not null references orders(id) on delete cascade,
  product_id bigint not null references product(id),
  qty        int    not null check (qty > 0),
  unit_price_cents bigint not null
);
insert into product (sku, name, price_cents, stock) values
  ('SKU-1','Espresso Machine',18999,12),
  ('SKU-2','Grinder',7499,30),
  ('SKU-3','Tamper',2499,100);
SQL

# 5. confirm
docker exec -it shop-pg psql -U shop -d shop -c 'select * from product'
```

### ⭐ How to run every program in this folder

**No IDE. No build file. One command.**

```bash
# Java 11+ single-file source launcher: compiles in memory, runs, no .class file
java basics/PassByValue.java

# when a program spans several files, or you want the .class:
javac -d out -Xlint:all -Werror basics/*.java      # ⭐ -Xlint:all -Werror:
java -cp out com.shop.demo.basics.PassByValue      #   treat warnings as errors.
                                                   #   Java's warnings are real
                                                   #   bugs 40% of the time.

# inspect what javac produced — do this at least once per file
javap -c -p out/com/shop/demo/basics/PassByValue.class
#     │  └─ private members too
#     └─── disassemble to bytecode

# experiment interactively — ⭐ faster than any file
jshell
#   jshell> Integer a = 127, b = 127; a == b
#   $1 ==> true
#   jshell> Integer c = 128, d = 128; c == d
#   $2 ==> false          ← ⭐ the wrapper-cache trap, seen in 10 seconds
#   jshell> /vars         ← what's in scope
#   jshell> /exit
```

⭐⭐ **Three rules for the lab, and they are why this folder works:**

| Rule | Why |
|---|---|
| **Type every program. Never paste.** | Pasting produces recognition. Typing produces recall. The typo you make and fix teaches you more than the ten lines you pasted |
| **Predict the output before you run it.** Say it out loud or write it down. Then compare | ⭐ This one habit is the difference between reading about Java and knowing Java. Being *wrong* is the learning event |
| **When something surprises you, `javap -c` it.** | The bytecode never lies. Every "but why does it do that?" in this folder has a bytecode-level answer |

**IDE note:** IntelliJ IDEA Community is free and is the industry standard — install it, you will need it from folder 5 onwards. But ⭐ **do not let it write your code in this folder.** Auto-import, live templates and inline hints hide exactly the mechanics file 01 is trying to teach you. Use a plain editor plus `java File.java` for folders 1–2, then move to the IDE.

---

## 📐 What every file in this folder obeys

| Rule | What it means for you |
|---|---|
| **Every program has a header block** | `PROGRAM <file>.<n>` with `WHAT / WHY / OUTPUT / JAVA` — so you can reference any program by number |
| **Comments explain WHY, not WHAT** | except the first time a construct appears, where you get both |
| **Every runnable program shows its exact output** | in an `── OUTPUT ──` comment block. If the output is nondeterministic, the file says so and shows two possible results |
| ⭐ **Five assignments per OOP topic** | A1 reproduce · A2 vary · A3 combine · A4 break · A5 design — with **full commented solutions at the END of `02A`** |
| **Four practice sets at the end of every file** | ① coding tasks ② "what does this print?" ③ find the bug ④ interview questions — **answers always after the questions, never before** |
| **Markers** | ⭐ insight · ⭐⭐ junior↔senior · ⭐⭐⭐ senior↔staff · ⛔ anti-pattern · ⚠️ trap · ✅ correct · 🔑 say this in the interview |
| **No placeholder code** | package, imports, class, `main` — complete and compilable. Never `// ... rest of the code` |
| **Every file ends with the footer** | — |

⭐ **How to work through an assignment.** A1–A3 are for confidence; **A4 and A5 are where the SDE 3 material is.** A4 asks you to *break* something — to find or create the failure mode and explain it. A5 asks you to *design* — a small modelling problem that forces a real choice with no obviously correct answer. If you are short on time, do A1, A4 and A5 and skip A2/A3. That is a better trade than doing A1–A3 and skipping the hard two.

⛔ **Never read an assignment's solution before attempting it.** Reading a solution feels like learning and produces nothing. Attempt it, get it wrong, *then* read — the wrong attempt is what makes the solution stick.

---

## ✅ Checkpoint A — how you know you may leave this folder

Ten tests, from memory, no notes. **Pass = 9/10.** Full detail in [`../00-MASTER-ROADMAP.md`](../00-MASTER-ROADMAP.md) §10.

1. Say the pass-by-value sentence, then write the swap that fails.
2. Draw a `HashMap`: array, bucket, list, treeify at 8/64, resize.
3. Explain why `equals` and `hashCode` must agree — and write the mutable-key orphaning bug.
4. Write a truly immutable class (all 9 rules), then convert it to a `record` and say what you lost.
5. Write the initialisation-order proof program and **predict its output before running it**.
6. State the 4×4 access-modifier matrix without hesitating.
7. Explain `sealed` + `record` + pattern-matching `switch` as an algebraic data type, and write one.
8. Cause a deadlock with two threads, then fix it two different ways.
9. Say what a virtual thread is, what it costs, and when it does **not** help.
10. Choose a collection for five scenarios in under 10 seconds each, with the reason.

⭐ Take this test **now**, before you start, and record the score. Expect 1–3/10. Retake it when you finish. The gap between those two numbers is the most motivating thing in this folder.

---

## 🔗 Related

| Where | Why |
|---|---|
| [`../README.md`](../README.md) | the master index — all 184 files, one line each |
| [`../00-MASTER-ROADMAP.md`](../00-MASTER-ROADMAP.md) | the week-by-week plan; this folder is weeks 1–8 |
| [`../09-sde3-interview-vault/`](../09-sde3-interview-vault/) | ⭐ open it in week 2 and keep it open. `01`, `04`, `05` are this folder's interview mirror |
| [`../03-jdbc-deep/`](../03-jdbc-deep/) | where file `05` goes to become production-grade |
| [`../PROMPT-java-fullstack-sde3.md`](../PROMPT-java-fullstack-sde3.md) | the prompt that generates this folder |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Type every program. Predict every output. Ten files from here, you'll know why.*

</div>
