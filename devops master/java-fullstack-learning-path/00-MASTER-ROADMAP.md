# 🗺️ 00 — THE MASTER ROADMAP

### The whole Java Full Stack path, week by week and hour by hour — with the dependency graph, the critical path, the express lane, and an honest answer to "what can I skip?"

> **Read this once, properly, before you open any teaching file.** It takes 20 minutes and it is the difference between *finishing* this path and *abandoning it in week 4*.
>
> The single most common failure mode in a 184-file curriculum is not difficulty — it is **sequencing**. People read folder 5 before folder 1, hit a wall, conclude they are not smart enough, and quit. They were not unsmart. They were out of order.

---

## 📇 Contents

- [1 · The two clocks](#1--the-two-clocks)
- [2 · The phase map](#2--the-phase-map)
- [3 · Choose your schedule](#3--choose-your-schedule)
- [4 · Week by week (the 20 h/week default)](#4--week-by-week-the-20-hweek-default)
- [5 · ⏰ Hour by hour — Week 1](#5---hour-by-hour--week-1)
- [6 · The dependency graph and the critical path](#6--the-dependency-graph-and-the-critical-path)
- [7 · The parallel track: the interview vault from week 2](#7--the-parallel-track-the-interview-vault-from-week-2)
- [8 · ⚡ The express path — 6 weeks](#8---the-express-path--6-weeks)
- [9 · What you can skip without breaking anything later](#9--what-you-can-skip-without-breaking-anything-later)
- [10 · Milestone checkpoints — how to know you may move on](#10--milestone-checkpoints--how-to-know-you-may-move-on)
- [11 · The daily ritual](#11--the-daily-ritual)
- [12 · When the plan goes wrong](#12--when-the-plan-goes-wrong)
- [13 · The definition of done](#13--the-definition-of-done)
- [14 · Tasks and answers — at the END](#tasks--answers)

---

## 1 · The two clocks

There are two different numbers and confusing them is what makes people quit.

| Clock | What it measures | Value |
|---|---|---|
| ⏱️ **Reading clock** | Time to read the files once, carefully, running every program | **≈ 320–400 h** |
| 🔁 **Mastery clock** | Reading clock + the second pass + the tasks you got wrong + the spaced repetition until it is recall-able in an interview | **≈ 600–750 h** |

⭐ **The reading clock is not optional. The mastery clock is what gets you the job.** Nobody passes an SDE 3 loop having read a book once. You are aiming for *recall under pressure*, which requires retrieval practice over weeks — not more reading.

**Per-folder breakdown of the reading clock:**

| Folder | Hours (min–max) | Files | What drives the time |
|---|---|---|---|
| `01-core-java` | **55–70** | 11 | ⭐ 02A has 100 assignments (20 topics × 5). That is the bulk |
| `02-frontend` | **85–110** | 82 | 15 complete projects. This is the biggest folder by volume |
| `03-jdbc-deep` | 14–18 | 11 | Transactions and pooling need lab time, not reading time |
| `04-jsp-servlets` | 12–16 | 11 | Deliberately short. Do not over-invest here |
| `05-hibernate-jpa` | 28–35 | 16 | The persistence context and N+1 need repetition |
| `06-spring-core` | 22–28 | 14 | AOP and transactions are conceptually dense |
| `07-spring-boot` | 28–35 | 15 | Security alone is 8 hours |
| `08-fullstack-capstone` | 35–45 | 11 | ⭐ Building, not reading. Budget lab time |
| `09-sde3-interview-vault` | 35–45 | 11 | Spreads across the whole path, not one block |
| **Total** | **314–402** | **184** | |

---

## 2 · The phase map

Nine folders collapse into **five phases**. Each phase has one job, and the phases must not be interleaved randomly.

```
PHASE 1 ─ THE LANGUAGE              weeks 1–4      55–70 h
  01-core-java
  ⭐ Goal: you can read and write Java without looking anything up,
     and you can explain HashMap, equals/hashCode, pass-by-value,
     immutability, and the JMM out loud, unprompted.
  Exit test: §10 checkpoint A.

PHASE 2 ─ THE FRONTEND              weeks 4–9      85–110 h
  02-frontend (html → css → dom → javascript → react → projects)
  ⭐ Goal: you can build a credible React SPA that talks to an API,
     and you can explain the event loop, closures, and reconciliation.
  Exit test: §10 checkpoint B.
  ⚠️  This phase OVERLAPS phase 1 by design — see §6.

PHASE 3 ─ THE PERSISTENCE & WEB     weeks 9–13     54–69 h
  03-jdbc-deep → 04-jsp-servlets → 05-hibernate-jpa
  ⭐ Goal: you understand what your ORM is doing, and you can find
     and fix an N+1 without being told there is one.
  Exit test: §10 checkpoint C.

PHASE 4 ─ THE FRAMEWORK             weeks 13–17    50–63 h
  06-spring-core → 07-spring-boot
  ⭐ Goal: Spring is not magic. You can explain the proxy, the bean
     lifecycle, auto-configuration, and why @Transactional silently
     does nothing on a self-invocation.
  Exit test: §10 checkpoint D.

PHASE 5 ─ THE SYSTEM                weeks 17–22    70–90 h
  08-fullstack-capstone  +  the Docker / K8s / Monitoring / CI-CD paths
  ⭐ Goal: one system you built end to end that you can whiteboard
     for 20 minutes and defend under follow-up questions.
  Exit test: §10 checkpoint E.

RUNNING THROUGH ALL OF IT ─ weeks 2–22              35–45 h
  09-sde3-interview-vault
  ⭐ Not a phase. A PARALLEL TRACK, 3 h per week, from week 2.
```

⭐⭐ **Why phase 2 overlaps phase 1.** Frontend learning has a long latency — you read CSS on Monday and it clicks on Thursday. Running it *alongside* Core Java rather than strictly after it means the "waiting for it to click" time is filled with productive Java work instead of frustration. It also prevents the classic collapse: six weeks of pure Java with nothing visual, then quitting.

---

## 3 · Choose your schedule

Three honest schedules. Pick one and **write the end date down**.

| | 🚀 Full-time | 📅 Serious part-time ⭐ *the default in §4* | 🐢 Realistic |
|---|---|---|---|
| Hours per week | 40 | 20 | 10 |
| Hours per day | 8 × 5 days | ~3 h × 5 days + 2.5 h × 2 days | 1 h weekdays + 2.5 h weekend |
| Reading-clock duration | **9–10 weeks** | **17–19 weeks** | **34–38 weeks** |
| Mastery-clock duration | 16–18 weeks | 30–36 weeks | 60–72 weeks |
| Who this is for | between jobs, or on leave | ⭐ a full-time job + this | a full-time job + a life |
| Risk | ⛔ burnout by week 5 | manageable | losing momentum; needs §11 |
| Interview-ready at | week 12–14 | week 24–28 | week 45–55 |

⭐ **Which to pick.** If you have an interview in under 3 months, take the express path in §8 rather than compressing the full path — compressing produces people who have *seen* everything and can *recall* nothing. If you have 6+ months, take the serious part-time schedule; it is the one that actually completes.

⛔ **The schedule that does not exist:** "I'll do it when I have time." Nobody has time. It is created, in 1-hour blocks, at the same hour, on the same days, or it does not happen.

---

## 4 · Week by week (the 20 h/week default)

19 weeks. Each row is a commitment you can check off. **Vault** = `09-sde3-interview-vault/`, 3 h every week from week 2, always.

| Wk | Hours | Primary | Files | Vault (3 h) | Milestone |
|---|---|---|---|---|---|
| **1** | 20 | Core Java | `01/00`, `01/01` (map + basics) | `01` Q1–40 skim | ⭐ you can run `java File.java` and explain the JVM in 60 s |
| **2** | 20 | Core Java | `01/02A` topics 1–10 (50 assignments) | `01` Q41–80 | classes, constructors, inheritance, overriding, polymorphism done |
| **3** | 20 | Core Java | `01/02A` topics 11–20 (50 assignments) | `01` Q81–120 | ⭐ Object methods, immutability, enum, record, sealed done |
| **4** | 20 | Core Java | `01/02B` (LLD) + `01/06` (collections) start | `02` problems 1–3 | the 4×4 access matrix and HashMap internals from memory |
| **5** | 20 | Core Java + FE start | `01/06` finish, `01/03` (IO) | `02` problems 4–6 | ⭐ **Checkpoint A** · HTML `01`,`02`,`03` |
| **6** | 20 | Core Java | `01/05` (JDBC basics), `01/04` (advanced) start | `04` problems 1–4 | generics, reflection, streams |
| **7** | 20 | Core Java + FE | `01/04` finish (⭐ concurrency), `01/07` projects | `05` Q1–20 | virtual threads, the JMM, `CompletableFuture` |
| **8** | 20 | Core Java + FE | `01/08` cheatsheet, `01` second pass · CSS `01`,`02`,`03` | `05` Q21–40 | ⭐ **Core Java complete** |
| **9** | 20 | Frontend | CSS `04`–`07` (flexbox, grid, positioning, responsive) | `02` problems 7–9 | you can build any layout from a screenshot |
| **10** | 20 | Frontend | CSS `08`–`13` · DOM `01`–`05` | `06` round 1 | ⭐ **Checkpoint B** (CSS half) |
| **11** | 20 | Frontend | DOM `06`–`10` · JS `01`–`04` | `06` round 2 | closures, prototypes, the event model |
| **12** | 20 | Frontend | JS `05`–`09` (⭐ `06`,`07` async + event loop) | `06` round 3 | ⭐ you can solve any "what does this print?" ordering problem |
| **13** | 20 | Frontend | JS `10`–`13` · React `01`–`05` | `01` Q121–160 | UI = f(state), keys, reconciliation |
| **14** | 20 | Frontend | React `06`–`10` (⭐ `06` hooks deep) | `02` problems 10–12 | effects you can defend, routing |
| **15** | 20 | Frontend | React `11`–`17` · Projects P01, P02 | `07` Q1–20 | data fetching, forms, performance |
| **16** | 20 | Frontend | Projects P03–P08 | `02` problems 13–15 | ⭐ **Checkpoint B** · frontend complete |
| **17** | 20 | Frontend + Persistence | Projects P09–P15 · `03/01`,`02` | `09` URL-shortener | pooling, isolation |
| **18** | 20 | Persistence | `03/03`–`10` | `09` news-feed | ⭐ transactions and the anomalies, demonstrated |
| **19** | 20 | Persistence | `04/01`–`09` (servlets) | `09` chat | the servlet lifecycle; Spring MVC is no longer magic |
| **20** | 20 | Persistence | `05/01`–`07` (⭐ `02`, `05`, `06`) | `07` Q21–40 | persistence context, relationships, **N+1** |
| **21** | 20 | Persistence | `05/08`–`14` | `03` round 1 | ⭐ **Checkpoint C** |
| **22** | 20 | Framework | `06/01`–`06` (⭐ `01`,`02`,`05`,`06`) | `03` round 2 | IoC/DI, bean lifecycle, AOP, transactions |
| **23** | 20 | Framework | `06/07`–`12` | `06` GC round | Spring MVC, `JdbcTemplate`, patterns in Spring |
| **24** | 20 | Framework | `07/01`–`05` (⭐ `05` security) | `08` Q1–10 | auto-configuration deconstructed; JWT done properly |
| **25** | 20 | Framework | `07/06`–`11` | `08` Q11–20 | actuator, testing, deployment, virtual threads vs WebFlux |
| **26** | 20 | Framework | `07/12`,`13` + second pass | `08` Q21–30 | ⭐ **Checkpoint D** · `shop-api` exists |
| **27** | 20 | System | `08/01`–`03` | `10` mock round 1 | the architecture, ADRs, backend and frontend built |
| **28** | 20 | System | `08/04`–`07` | `10` mock round 2 | integration, security, observability, deployment |
| **29** | 20 | System | `08/08`,`09` + the Docker/K8s paths | `10` mock round 3 | ⭐ containerised, orchestrated, shipped |
| **30** | 20 | System | Monitoring + CI/CD paths against `shop` | `10` mock rounds 4–6 | ⭐⭐ **Checkpoint E — you are interview-ready** |

⭐ **Weeks 29–30 plug into your four existing paths.** You already have Docker (19 files), Kubernetes (20), Monitoring (7) and CI/CD (9). The capstone is the *application* those paths needed. That is why the last two weeks are cheap for you and expensive for everyone else.

---

## 5 · ⏰ Hour by hour — Week 1

The most detailed schedule in this file, because week 1 is where the habit is formed. 20 hours: five 3-hour weekday blocks and one 2.5-hour weekend block ×2.

> **Assumes:** Java 21 installed (README §Setup), a terminal, and `~/java-fullstack/01-core-java-lab/` created.

### Day 1 — Monday · 3 h · *"What is Java, actually?"*

| Time | Do | File | ✅ Verify |
|---|---|---|---|
| 0:00–0:20 | Read this roadmap. Write your end date down. Put it somewhere visible | this file | a date on paper |
| 0:20–0:40 | Install Java 21 + Maven. Run `java -version`, `jshell`, `java Hello.java` | README §Setup | three commands work |
| 0:40–1:20 | Read the **topic map** — every Core Java topic with its mastery tag. Do not learn anything yet; just see the territory | `01/01` §map | you can name the 4 mastery levels |
| 1:20–2:00 | JDK / JRE / JVM, bytecode, the JIT, "write once run anywhere" and what it costs | `01/01` §1 | ⭐ explain the JIT in 60 s, out loud |
| 2:00–2:30 | ⭐ **Lab:** write `Hello.java`, `javac` it, `java` it, then `javap -c Hello.class` and *read the bytecode* | `01/01` §2 | you have seen `invokevirtual` |
| 2:30–3:00 | Write the four practice-set answers you can already do. Log what you could not | `01/01` §tasks | 3 things you don't know yet |

### Day 2 — Tuesday · 3 h · *Primitives, wrappers, operators*

| Time | Do | ✅ Verify |
|---|---|---|
| 0:00–0:45 | All 8 primitives: sizes, ranges, defaults. Why `float`/`double` are imprecise, and ⭐ why money is never a `double` | you can state `int`'s range from memory |
| 0:45–1:15 | ⭐ **Lab:** print `0.1 + 0.2`, then `new BigDecimal("0.1").add(...)`. See the difference | you have seen `0.30000000000000004` |
| 1:15–2:00 | Wrappers, autoboxing, ⭐ **the `Integer.valueOf` cache** (−128..127) and the `==` trap that fails only sometimes | ⭐ **Lab:** `Integer a=127,b=127; a==b` → true. `128,128` → false |
| 2:00–2:30 | Operators: `&&` vs `&`, `\|\|` vs `\|` with a side-effect proof; every bitwise operator and its use case | you have written the short-circuit proof |
| 2:30–3:00 | The HashMap index trick `(n-1) & hash` — just see it now; it returns in `01/06` | you know where it is used |

### Day 3 — Wednesday · 3 h · *Control flow, arrays, methods*

| Time | Do | ✅ Verify |
|---|---|---|
| 0:00–0:40 | Casting: widening vs narrowing, `(int)` vs `Math.round`, the `char`/`int` arithmetic surprise | you can predict `'a' + 1` |
| 0:40–1:20 | Control flow: old `switch` vs ⭐ the new expression form, arrow labels, `yield`, exhaustiveness with sealed types | **Lab:** write both forms of the same switch |
| 1:20–2:00 | Arrays: they are **objects**, `length` is a field, jagged arrays, shallow vs deep copy, `Arrays.copyOf` vs `System.arraycopy` | you know the difference between the three copies |
| 2:00–2:40 | ⭐ **Method overloading resolution** — the exact order: exact → widening → boxing → varargs, plus the ambiguity traps | **Lab:** write the 3-arg `f(int, long, Long)` ambiguity |
| 2:40–3:00 | Practice sets 1–2 for today's material | 80%+ correct |

### Day 4 — Thursday · 3 h · ⭐⭐ *Pass by value. The most-asked question in Java.*

| Time | Do | ✅ Verify |
|---|---|---|
| 0:00–0:30 | Read the section. Do not write code yet | — |
| 0:30–1:30 | ⭐ **Write all four proof programs yourself, from memory:** a primitive, an object reference, a reference reassigned inside the method, and a swap that fails | four programs, four outputs |
| 1:30–2:00 | Say out loud, twice: *"Java is always pass by value. For objects, the value that is passed is a copy of the reference."* Then explain why "pass by reference for objects" is wrong | 🔑 you can say it without notes |
| 2:00–2:30 | Write the wrong version out loud too, and identify precisely where it goes wrong (the reassignment is not visible to the caller) | you can catch someone else saying it |
| 2:30–3:00 | `String`: immutability and the four reasons why; the pool; `==` vs `.equals()`; ⭐ the compile-time-constant folding surprise | **Lab:** prove `"a"+"b" == "ab"` is `true` |

### Day 5 — Friday · 3 h · *StringBuilder, static, memory*

| Time | Do | ✅ Verify |
|---|---|---|
| 0:00–0:45 | Concatenation and the `StringBuilder` the compiler inserts — and when it does **not** (loops). String vs StringBuilder vs StringBuffer, and ⭐ the honest answer about StringBuffer | **Lab:** measure 100k concatenations both ways |
| 0:45–1:30 | `static`: fields, methods, blocks, nested classes. ⭐ **The initialisation order proof program** — static block, instance block, constructor, field initialiser, in a parent and a child | one program, and you can predict its output before running |
| 1:30–2:15 | JVM memory at beginner level: stack vs heap, what lives where, the diagram. ⭐ `StackOverflowError` vs `OutOfMemoryError` | **Lab:** cause both, on purpose |
| 2:15–3:00 | The toolchain: `javac -Xlint:all -Werror`, `java --enable-preview`, `jshell`, the single-file launcher, `jar` | you have compiled with `-Xlint:all` and read a warning |

### Day 6 — Saturday · 2.5 h · *Consolidate*

| Time | Do |
|---|---|
| 0:00–0:45 | ⭐ **Retrieval practice, no notes.** On paper: the 8 primitives with ranges; the overloading resolution order; the `main` signature with a reason for each modifier; the initialisation order |
| 0:45–1:30 | Mark it against the file. Everything wrong goes on a card (Anki, paper, whatever — §11) |
| 1:30–2:30 | Do the `01/01` practice sets you skipped. Answers at the END of the file |

### Day 7 — Sunday · 2.5 h · *Vault + the week's gaps*

| Time | Do |
|---|---|
| 0:00–1:00 | 🔁 **Vault track starts:** `09/01-JAVA-DEEP-DIVE-300.md`, questions 1–40. ⭐ **Read them before you can answer them.** That is the point — it shows you what "done" looks like |
| 1:00–1:45 | Write down which of the 40 you could already answer. That number is your baseline. Track it weekly |
| 1:45–2:30 | Plan week 2 against §4. Identify the one thing from week 1 that is still fuzzy and put it first on Monday |

⭐ **The week-1 success criterion is not "I read the file."** It is: *you ran at least 15 programs, you caused a `StackOverflowError` and an `OutOfMemoryError` on purpose, and you can say the pass-by-value sentence without notes.*

---

## 6 · The dependency graph and the critical path

### 6.1 What depends on what

```
                            ┌──────────────────┐
                            │ 01-core-java     │
                            │  01 basics       │
                            └────────┬─────────┘
                                     │ HARD dependency for everything below
        ┌────────────────┬───────────┼───────────────┬──────────────────┐
        ▼                ▼           ▼               ▼                  ▼
 ┌────────────┐  ┌──────────────┐ ┌──────────┐ ┌──────────────┐ ┌──────────────┐
 │01/02A OOP  │  │01/06 collect.│ │01/03 IO  │ │02-frontend   │ │09-vault      │
 │  ⭐⭐⭐     │  │  ⭐⭐⭐       │ │          │ │ (SOFT dep:   │ │ (NO dep —    │
 └─────┬──────┘  └──────┬───────┘ └────┬─────┘ │  needs 01/01 │ │  start wk 2) │
       │                │              │       │  only)       │ └──────────────┘
       │                │              │       └──────┬───────┘
       ▼                │              ▼              ▼
 ┌────────────┐         │       ┌────────────┐  ┌──────────────┐
 │01/02B LLD  │         │       │03-jdbc-deep│  │02/projects   │
 └─────┬──────┘         │       └─────┬──────┘  │ P02 shop-ui  │
       │                │             │         └──────┬───────┘
       │                │             ▼                │
       │                │       ┌────────────┐         │
       │                │       │04-servlets │         │
       │                │       └─────┬──────┘         │
       │                │             │                │
       │                │             ▼                │
       │                └──────▶┌────────────┐         │
       │                        │05-hibernate│         │
       │                        └─────┬──────┘         │
       │                              │                │
       │                              ▼                │
       │                        ┌────────────┐         │
       └───────────────────────▶│06-spring   │         │
                                └─────┬──────┘         │
                                      │                │
                                      ▼                │
                                ┌────────────┐         │
                                │07-spring-  │◀────────┘
                                │   boot     │   (needs the FE to be full stack)
                                └─────┬──────┘
                                      │
                                      ▼
                          ┌────────────────────────┐
                          │08-fullstack-capstone   │
                          │  + Docker + K8s +      │
                          │    Monitoring + CI/CD  │
                          └────────────────────────┘
```

### 6.2 The critical path — the longest chain of hard dependencies

```
01/01 basics → 01/02A OOP → 01/06 collections → 03-jdbc-deep → 05-hibernate-jpa
             → 06-spring-core → 07-spring-boot → 08-capstone
```

⭐⭐ **This is 8 links and about 175 hours.** Everything else can be moved, parallelised, or skipped. Nothing on this chain can.

**Corollaries worth internalising:**

| Insight | Consequence for your plan |
|---|---|
| `01-core-java` is on the critical path for everything | ⛔ never "skim it and come back". You will not come back |
| `02-frontend` is a **soft** dependency of `07-spring-boot` only | ⭐ you can reach Spring without any frontend at all — which is why backend-focused candidates defer it |
| `04-jsp-servlets` is a soft dependency of `06-spring-core` | you can skip it, but Spring MVC stays magical. 12–16 h is cheap for that |
| `09-vault` has **no** dependencies | ⭐ start it in week 2 and never stop. It is the only folder that can be read out of order |
| `03-jdbc-deep` precedes `05-hibernate-jpa` | ⭐⭐ non-negotiable. Hibernate without JDBC is a black box you cannot debug |

### 6.3 Where people get stuck, and the actual cause

| Symptom | Real cause | Fix |
|---|---|---|
| "Hibernate makes no sense" | skipped `03-jdbc-deep`, or `01/06` collections | go back. Two days, and the folder unlocks |
| "Spring annotations are magic" | skipped `04/01` lifecycle and `06/02` bean lifecycle | read those two files. That is the whole cure |
| "React keeps re-rendering and I don't know why" | skipped `javascript/03` closures and `04` prototypes | `useState`'s stale-closure bug *is* a closures bug |
| "I can read Java but can't write it" | read the programs instead of typing them | ⭐ type every program. Every one. No exceptions |
| "I understood it last week and not now" | no retrieval practice | §11. Reading is not learning; recalling is |
| "The interview questions look nothing like the files" | never opened the vault | §7 |

---

## 7 · The parallel track: the interview vault from week 2

⭐⭐⭐ **This is the single highest-leverage piece of advice in this file.**

Most candidates prepare for interviews *after* they finish learning. That is backwards, for three reasons:

1. **You cannot hit a target you cannot see.** `09/01-JAVA-DEEP-DIVE-300.md` tells you precisely what depth is expected. Reading question 47 about the JMM *before* you study the JMM changes how you study it.
2. **Spaced retrieval is the only thing that produces recall under pressure.** Cramming in week 20 produces recognition, not recall. Recognition fails in an interview.
3. **The behavioural and LLD rounds need reps, not knowledge.** `09/02` (25 LLD problems) and `09/08` (behavioural) improve only with repeated timed attempts. Six reps over four months beats sixty reps in one weekend.

### The 3-hours-a-week vault schedule

| Weeks | File | Reps | Goal |
|---|---|---|---|
| 2–4 | `01-JAVA-DEEP-DIVE-300.md` Q1–120 | 40/wk | read them, mark ✅ / ❌. Do not answer yet |
| 5–8 | `05-COLLECTIONS-AND-INTERNALS.md` + `01` Q121–200 | — | ⭐ draw `HashMap` from memory, once a week, until it takes 90 s |
| 7–10 | `04-CONCURRENCY-INTERVIEWS.md` | 2 problems/wk | timed, 20 min each, on paper |
| 9–14 | `02-LLD-QUESTION-BANK.md` | 1 problem/wk | ⭐ **timed 45 min, out loud, whiteboard or paper.** Record yourself once |
| 13–18 | `06-JVM-GC-PERFORMANCE.md` + `07-SPRING-INTERVIEWS.md` | — | the staff-level round |
| 16–22 | `03-HLD-FOR-JAVA-DEVS.md` | 1/fortnight | after the capstone, so you have a real system to reference |
| 18–24 | `08-BEHAVIOURAL-SDE3.md` | 2 stories/wk | ⭐ write 12 stories once, reuse them forever |
| 24–30 | `09-WHAT-HAPPENS-WHEN.md` + `10-MOCK-INTERVIEW-SCRIPTS.md` | 1 mock/wk | six full 45-minute rounds |

⭐ **The ✅/❌ ledger.** Keep one file:

```
# vault-ledger.md — update weekly, 5 minutes
week  2 | 01/Q1-40    | 11 ✅ | 29 ❌
week  3 | 01/Q41-80   |  6 ✅ | 34 ❌
week  6 | 01/Q1-40    | 31 ✅ |  9 ❌   ← ⭐ the re-test is the point
week  9 | 01/Q41-80   | 27 ✅ | 13 ❌
week 12 | HashMap     | 90 s from memory, no notes   ← ⭐ a timed skill check
```

The ❌ count going **up** in week 3 is normal and good — it means you are now able to recognise how much you don't know. The number that matters is week-over-week *on the same questions*.

🔑 **The interview line this produces:** by week 20 you have answered 300 Java questions out loud, drawn `HashMap` twenty times, and run twenty timed LLD rounds. When an interviewer asks you to design a parking lot, you are not thinking — you are *remembering*. That is the entire difference between a candidate who prepared and one who studied.

---

## 8 · ⚡ The express path — 6 weeks

For an interview in 6–8 weeks. **120 hours.** This is triage, not a shortcut: it deliberately abandons breadth to buy depth on the seven things that decide Java interviews.

```
WEEK 1 (20 h) ─ CORE JAVA, THE CRITICAL HALF
  01/01 basics + topic map .................. 4 h
  01/02A OOP topics 1–13 .................... 8 h  (skip 16 inner classes,
  01/06 collections: HashMap, CHM, ArrayList   20 annotations for now)
     + the complexity tables ................ 6 h
  09/01 vault Q1–60 (read only) ............. 2 h

WEEK 2 (20 h) ─ OOP COMPLETE + LLD
  01/02A topics 14–20 (records, sealed,
     immutability, composition) ............. 5 h
  01/02B LLD for SDE3 ....................... 8 h  ⭐ do not compress this
  09/02 LLD bank, problems 1–3, TIMED ....... 5 h
  01/04 concurrency: threads, JMM,
     synchronized, executors ................ 2 h

WEEK 3 (20 h) ─ CONCURRENCY + INTERNALS
  01/04 advanced: virtual threads,
     CompletableFuture, atomics ............. 6 h
  09/04 concurrency interviews, 6 problems... 5 h
  09/05 collections internals + 40 prints ... 5 h
  09/06 JVM & GC ............................ 4 h

WEEK 4 (20 h) ─ PERSISTENCE + SPRING, THE FOUR FILES
  03/02 connections & pooling ............... 2 h
  03/05 transactions & isolation ............ 4 h
  05/02 persistence context ................. 3 h
  05/06 ⭐ the N+1 .......................... 3 h
  06/01 IoC & DI ............................ 2 h
  06/06 ⭐ @Transactional ................... 3 h
  07/05 ⭐ Spring Security ................... 3 h

WEEK 5 (20 h) ─ THE PROJECT + THE SYSTEM
  07/01 what Boot actually does ............. 2 h
  07/03 web & REST .......................... 3 h
  07/08 deployment .......................... 2 h
  08/01 architecture (read, don't build) .... 3 h
  Build ONE service end to end: shop-api with
     2 entities, security, tests, Dockerfile. 8 h  ⭐ TALKING > READING
  09/03 HLD: URL shortener + news feed ...... 2 h

WEEK 6 (20 h) ─ MOCK INTERVIEWS
  09/10 six scripted rounds, 1 per day ...... 6 h
  09/08 behavioural: write 12 stories ....... 5 h
  09/09 what-happens-when, all four ......... 3 h
  Re-test the week-1 ❌ ledger .............. 3 h
  Buffer / your weakest area ................ 3 h
```

### What the express path abandons — and the cost

| Skipped | Cost | Mitigation |
|---|---|---|
| `02-frontend` entirely | You cannot claim "full stack" | ⭐ Say "backend-focused, working frontend knowledge". Never overclaim — it is tested in 90 seconds |
| `04-jsp-servlets` | Spring MVC stays partly magical | read `04/01` lifecycle only, 90 minutes |
| `03-jdbc-deep` beyond 2 files | shallow persistence answers | the 2 chosen files are the 2 that get asked |
| `05-hibernate-jpa` beyond 2 files | mapping/caching gaps | memorise the lifecycle diagram from `05/14` cheatsheet |
| `06-spring-core` beyond 2 files | bean lifecycle gaps | memorise the lifecycle from `06/12` cheatsheet |
| `08-capstone` (build only 1 service) | a thinner project story | ⭐ **one service you understand deeply beats five you copied** |
| The mastery clock | recall is shallow | ⭐ the week-6 re-test is the only thing standing between you and blanking |

⭐⭐ **The honest verdict on the express path:** it prepares you to *pass* a Java SDE interview. It does not prepare you to *be* an SDE 3. If you have the choice, take the 19-week path — and use the express path's file list as your "if I get an unexpected interview next month" fallback.

---

## 9 · What you can skip without breaking anything later

⭐ Ranked by how safe they are to skip. "Safe" means: no later file assumes it, and no common interview question requires it.

| Skip | Files | Safe? | What you lose |
|---|---|---|---|
| `04/05-JSP-EL-JSTL.md` | 1 | ✅ very safe | You cannot maintain a JSP codebase. Almost nobody can, or needs to |
| `02/html/07-SEO-AND-METADATA.md` | 1 | ✅ very safe | SEO knowledge — a different job |
| `02/projects/P11-OFFLINE-FIRST-PWA.md` | 1 | ✅ very safe | Service workers. Rarely asked of a Java SDE |
| `02/projects/P15-MICRO-FRONTEND.md` | 1 | ✅ very safe | Module federation. Niche |
| `02/css/08-TYPOGRAPHY-AND-COLOR.md` | 1 | ✅ safe | Design polish |
| `05/09-CACHING.md` (L2 cache) | 1 | ✅ safe | ⭐ L2 caching is rarely used in production anyway |
| `03/06-METADATA-AND-DYNAMIC-SQL.md` | 1 | ✅ safe | Tooling/codegen |
| `07/09-MESSAGING-CACHING-BATCH.md` | 1 | ⚠️ mostly safe | Kafka/RabbitMQ. **Skip only if your target team is not event-driven** |
| `02/dom/09-INTERNALS.md`, `html/09`, `js/12`, `react/17` | 4 | ⚠️ conditional | ⭐ These are the ⭐⭐⭐ differentiators for a **frontend** role and near-irrelevant for backend. Skip for backend, never for frontend |
| `06/10-PATTERNS-INSIDE-SPRING.md` | 1 | ⚠️ conditional | It is the best "design patterns" revision you will get. Skip only if you know GoF cold |
| `02-frontend` (whole folder) | 82 | ⚠️ conditional | Safe **only** for a pure backend role. ⛔ Never skip it and still say "full stack" |
| `01/02A` topics 16, 20 (inner classes, annotations) | part | ⛔ **not safe** | Annotations are how all of Spring works. Inner classes cause real memory leaks |
| `01/06` collections | 1 | ⛔ **never** | Asked in essentially every Java interview |
| `01/04` concurrency | 1 | ⛔ **never** | The hardest round, and the SDE 3 differentiator |
| `05/06` the N+1 | 1 | ⛔ **never** | The most-asked Hibernate question, full stop |
| `06/06` transactions | 1 | ⛔ **never** | "Why did my `@Transactional` not work?" is a filter question |
| `01/02B` LLD | 1 | ⛔ **never** | It is a whole interview round at every MAANG company |

---

## 10 · Milestone checkpoints — how to know you may move on

⭐ **Do not move on until you pass the checkpoint.** "I read it" is not a pass. Each of these is a *performance* test, not a recognition test.

### ✅ Checkpoint A — Core Java (end of week 8)

Do all ten, from memory, out loud or on paper, no notes:

1. Say the pass-by-value sentence, then write the failing swap.
2. Draw a `HashMap`: the array, the bucket, the linked list, the treeify threshold (8/64), and the resize.
3. Explain why `equals` and `hashCode` must agree, and write the mutable-key orphaning bug.
4. Write a truly immutable class — all 9 rules — then convert it to a `record` and say what you lost.
5. Write the initialisation-order proof program and **predict its output before running it**.
6. State the 4×4 access-modifier matrix without hesitating.
7. Explain `sealed` + `record` + pattern-matching `switch` as an algebraic data type, and write one.
8. Cause a deadlock with two threads, then fix it two different ways.
9. Say what a virtual thread is, what it costs, and when it does **not** help.
10. Choose a collection for five scenarios in under 10 seconds each, with the reason.

**Pass = 9/10.** Below that, re-read the specific section — do not re-read the folder.

### ✅ Checkpoint B — Frontend (end of week 16)

1. Build a responsive 3-column layout from a screenshot, flexbox or grid, in 15 minutes, without looking anything up.
2. Explain specificity arithmetic and compute it for three selectors.
3. Explain what a stacking context is and why `z-index: 99999` sometimes loses.
4. Say the exact output of five event-loop ordering problems (`setTimeout` / promise / `queueMicrotask` / `await`).
5. Explain closures to a Java developer in 90 seconds, using a Java analogy that is *correct*.
6. Explain what a React `key` does and why index-as-key breaks with insertion at the top.
7. Build a data-fetching hook with caching, deduplication and error state — then say why `useEffect` alone was the wrong tool.
8. Find and fix a stale-closure bug in a `useEffect`.
9. Name three things `useMemo` makes *slower*, and why.
10. Make a component accessible: keyboard-operable, correctly labelled, focus-managed.

### ✅ Checkpoint C — Persistence & web (end of week 21)

1. Explain what a connection pool is for, and size one for a given workload with the arithmetic.
2. Demonstrate a phantom read with two real connections, then say which isolation level prevents it and what it costs.
3. Explain the servlet lifecycle and why instance fields are a concurrency bug.
4. Forward vs redirect — the six differences.
5. Explain the persistence context, and what `detach` does and when you need it.
6. ⭐ Produce an N+1 from a naive mapping, detect it in the SQL log, and fix it three ways.
7. Explain why `@Transactional` does nothing on a self-invocation, and give two fixes.
8. Say why a `record` cannot be a JPA entity.
9. Write an expand/contract migration for adding a non-null column to a table with 400 M rows.
10. Explain what `IDENTITY` generation costs you (batch inserts) and what to use instead.

### ✅ Checkpoint D — Framework (end of week 26)

1. Explain IoC/DI to someone who has only used `new`, and say what it buys you.
2. Recite the bean lifecycle in order, including both `BeanPostProcessor` calls.
3. Explain full vs lite `@Configuration` mode and what CGLIB is doing.
4. Explain JDK dynamic proxy vs CGLIB and when Spring picks each.
5. Recite all seven propagation levels with a scenario each.
6. Deconstruct `@SpringBootApplication` into its three annotations and explain `AutoConfiguration.imports`.
7. List the externalised-configuration order well enough to say which of two sources wins.
8. Build a JWT-authenticated endpoint and say where the token is stored on the client, with the trade-off.
9. Name the three things Spring Boot actually does — and nothing else.
10. Answer "when would you *not* use Spring Boot?" with two real reasons.

### ✅ Checkpoint E — The system (end of week 30)

1. Whiteboard `shop` end to end in 8 minutes: FE, API, DB, cache, queue, worker, and the failure modes.
2. Defend every service boundary against "why isn't that one service?"
3. Explain the auth flow from browser click to database row.
4. Show the trace of one request across three services, with the correlation ID.
5. Explain the deploy: image → digest → GitOps PR → Argo sync → canary → analysis → promote.
6. Roll it back, live, and say how long it took.
7. State your SLO, your error budget, and what happens when the budget is exhausted.
8. Answer "what would you do differently?" with three specific, non-defensive answers. ⭐ **This is the SDE 3 question.**
9. Answer "how would this behave at 100× the traffic?" with the first three things that break.
10. Answer "what is the worst production incident in this system's design?" honestly.

⭐⭐ **Checkpoint E #8–#10 are the L5→L6 discriminator.** An SDE 2 describes what they built. An SDE 3 describes what they would change, what breaks at scale, and where the design is weakest — unprompted, specifically, and without defensiveness. Practise those three answers as hard as the code.

---

## 11 · The daily ritual

20 minutes a day, non-negotiable, on top of the study hours. This is what converts reading into recall.

| When | Minutes | Do |
|---|---|---|
| Start of session | 5 | ⭐ **Blank-page recall.** Before opening any file, write down everything you remember from yesterday. Then open the file and mark the gaps. Retrieval *before* review is what makes it stick |
| During session | — | Every program: **type it, don't paste it.** Predict the output before running it. If you were wrong, write down why |
| End of session | 5 | Write 1–3 cards for anything you got wrong or had to look up |
| Daily | 5 | Review cards due today (Anki / paper box / whatever you'll actually use) |
| Weekly (Sun) | 30 | ⭐ Re-test last week's cards *and* the vault ledger. Anything you failed twice gets re-read at source |

**The card format that works for Java:**

```
FRONT: What does this print?
       Integer a = 127, b = 127;
       Integer c = 128, d = 128;
       System.out.println((a == b) + " " + (c == d));

BACK:  true false
       ⭐ Integer.valueOf caches -128..127 (IntegerCache). Inside that
       range autoboxing returns the SAME object, so == compares identity
       and succeeds. Outside it, two distinct objects → false.
       🔑 never use == on boxed types. Use .equals(), or unbox first.
       → 01-BASICS §wrappers
```

⭐ **"What does this print?" is the highest-value card type in Java.** It is the most common interview format, it is self-marking, and it exposes gaps that prose reading hides. Every file in this path has a set of them — turn every one you get wrong into a card.

---

## 12 · When the plan goes wrong

| Situation | What to do | What NOT to do |
|---|---|---|
| You missed 3 days | Resume at the next block. Do not "catch up" | ⛔ Doubling your hours for a week. That ends in quitting |
| You missed 2 weeks | Re-baseline: pick a new end date, keep the order | ⛔ Skipping ahead to "get back on schedule" |
| A file makes no sense | Check §6.3 — it is almost always a missing prerequisite | ⛔ Re-reading the same file five times |
| You are bored | ⭐ Good — move faster, or start the vault track harder. Boredom means the material is below your level | ⛔ Treating boredom as a reason to skip. Skipped "easy" material is where the interview gaps are |
| You are overwhelmed | Drop to the express path (§8) for two weeks, then reassess | ⛔ Quitting. The express path exists precisely for this |
| The tasks are too hard | Do A1–A3, skip A4–A5, return in a week | ⛔ Reading the answers first. That converts practice into reading |
| The tasks are too easy | Do A4–A5, then explain the topic out loud to nobody for 5 minutes | ⛔ Moving on without the ⭐⭐⭐ material — that is the SDE 3 part |
| You have an interview next week | §8 express path, weeks 5 and 6 only | ⛔ Starting folder 1. You do not have time and it will not help |
| You cannot finish frontend | Do `javascript/02,03,06,07` + `react/01,03,05,06,11`, then P02 | ⛔ Claiming full stack without it |
| Life happened for 2 months | The files do not expire. Restart at §10's checkpoint for the folder you reached | ⛔ Restarting from the beginning — you will remember more than you think |

⭐⭐ **The meta-rule:** *the plan serves you, not the reverse.* A plan you follow at 70% for six months beats a plan you follow at 100% for three weeks. Adjust the dates; never adjust the **order**.

---

## 13 · The definition of done

You have finished this learning path when all of these are true:

- [ ] ⭐ You have **typed and run** every program in `01-core-java` — not read, typed
- [ ] You have completed at least **80 of the 100 OOP assignments** in `01/02A`, including all the A4 (break) and A5 (design) ones
- [ ] You can draw `HashMap` and `ConcurrentHashMap` from memory in under 2 minutes
- [ ] You have written **15 React projects' worth** of frontend, or at minimum P01, P02, P03 and P14
- [ ] You have **caused and fixed** an N+1 in a real Hibernate app
- [ ] You have built `shop-api` with security, tests, actuator metrics, and a Dockerfile
- [ ] ⭐⭐ **`shop` runs end to end**: React UI → Spring Boot API → PostgreSQL, with Redis caching and a RabbitMQ worker, containerised, on Kubernetes, scraped by Prometheus, deployed by a CI/CD pipeline
- [ ] You have **drilled the rollback** and know your recovery time in seconds
- [ ] You have answered all **300 vault questions** out loud at least twice
- [ ] You have run **25 timed LLD rounds** and **6 scripted mock interviews**
- [ ] You have **12 behavioural stories** written in STAR-plus-impact form
- [ ] ⭐⭐⭐ You can talk about `shop` for **20 minutes** — architecture, trade-offs, what broke, what you would change, what fails at 100× — without notes and without defensiveness

That last line is the real deliverable. Everything else exists to produce it.

---

<a name="tasks--answers"></a>
## 14 · Tasks and answers — at the END

### Tasks

| # | Task |
|---|---|
| **R1** | Pick your schedule from §3, compute your end date, and write it somewhere you will see it daily |
| **R2** | Do §5's Day 1 completely — including `javap -c` on your own `Hello.class` |
| **R3** | Create `vault-ledger.md` (§7) and enter your week-1 baseline from `09/01` Q1–40 |
| **R4** | Draw the critical path from §6.2 **from memory**, then check it |
| **R5** | Write your own express-path variant of §8 for the specific company you are targeting, using §9's skip table |
| **R6** | Set up the card system from §11 and make your first 10 cards during week 1 |
| **R7** | Take checkpoint A (§10) right now, before you have studied. Record the score. Retake it at the end of week 8 |
| **R8** | Identify the one folder you are most tempted to skip, and use §9 to decide whether that is safe. Write down your decision and your reason |

### Answers

**R1.** Three inputs: your weekly hours from §3, the reading clock (314–402 h), and the mastery multiplier (~1.8×). At 20 h/week: 402 ÷ 20 ≈ 20 weeks reading, ≈ 34 weeks to mastery — which is why §4 shows interview-readiness at week 24–28 rather than week 19. ⭐ **Write the *interview-ready* date, not the *finished-reading* date.** Planning against the wrong number is how people schedule an interview they are not ready for.

**R2.** The point of `javap -c` is not to learn bytecode. It is to make the abstraction *physical*: you see `getstatic`, `ldc`, `invokevirtual`, `return`, and the JVM stops being a black box that "runs your code". Every later claim in this path about method dispatch (`invokevirtual` vs `invokeinterface`), the JIT, or `String` constant folding is verifiable with this one command. ⭐ Habit: whenever a file asserts something about how Java behaves, verify it with `javap -c` or `jshell` rather than believing it.

**R3.** The baseline is almost always 8–15 ✅ out of 40. That number is not a judgement; it is a **measurement**, and it is the only way to prove progress to yourself in week 12 when it feels like nothing is happening. ⭐ Re-test the *same* questions in weeks 6, 12 and 20. The slope of that line is your real progress metric — far more reliable than "how many files have I read".

**R4.** Eight links: `01/01 → 01/02A → 01/06 → 03-jdbc-deep → 05-hibernate-jpa → 06-spring-core → 07-spring-boot → 08-capstone`, ~175 h. The insight worth drawing yourself is what is **not** on it: `02-frontend` (soft dependency of `07` only) and `09-vault` (no dependency at all). ⭐ Those two facts are what make the express path possible, and what let a backend-focused candidate defer eight weeks of frontend without blocking anything.

**R5.** The method, not an answer: (1) find three real job descriptions for the target role, (2) list every technology named, (3) map each to a file in §9's table, (4) anything named in 2+ descriptions that you planned to skip → **unskip it**, (5) anything named in 0 descriptions → skip it without guilt. ⭐ Then apply §9's ⛔ never-skip list as a floor regardless of the job description — collections, concurrency, LLD, N+1 and transactions are asked everywhere, including by companies whose JD never mentions them.

**R6.** The system matters less than the habit. The two rules that make any system work: (a) **a card is created only for something you got wrong or had to look up** — cards for things you already know are wasted review time; (b) **every card carries a file+section reference** — so a failed card sends you back to the source instead of to another card. ⭐ Cap it at ~10 new cards a day. More than that and the review queue becomes the reason you quit.

**R7.** Expect 1–3 out of 10 right now, and that is correct and useful: it tells you which of the ten are your personal weak spots, which then become the things you listen for during weeks 1–8. The re-test at week 8 should be 9/10 to pass. ⭐⭐ The gap between your pre-score and your post-score is the most motivating number in this entire path — record both, in the same file, where you can see them.

**R8.** The decision procedure: a folder is safe to skip **only if** (a) §9 rates it ✅ safe, **and** (b) no file on the critical path (§6.2) depends on it, **and** (c) no job description you care about names it. If you skip something that fails any of those three, you must write down the *specific* consequence — "I will not be able to explain the servlet lifecycle, so Spring MVC questions will be shallow" — rather than a vague "I'll come back to it". ⛔ "I'll come back to it" has a completion rate of approximately zero. Decide consciously, or don't skip.

---

## Related files

| File | Why |
|---|---|
| [README.md](./README.md) | ⭐ the master index — one line for all 184 files, plus the version anchors and setup |
| [`01-core-java/`](./01-core-java/) | Phase 1. Start here |
| [`01-core-java/00-ONE-DAY-MASTER-PLAN.md`](./01-core-java/00-ONE-DAY-MASTER-PLAN.md) | The hour-by-hour plan for Core Java specifically |
| [`09-sde3-interview-vault/`](./09-sde3-interview-vault/) | ⭐ the parallel track — open it in week 2 |
| [`../PROMPT-java-fullstack-sde3.md`](../PROMPT-java-fullstack-sde3.md) | The self-contained prompt that generates this path, folder by folder |
| [`../docker-learning-path/`](../docker-learning-path/) · [`../kubernetes-learning-path/`](../kubernetes-learning-path/) · [`../monitoring-alerting-learning-path/`](../monitoring-alerting-learning-path/) · [`../cicd-learning-path/`](../cicd-learning-path/) | Phase 5 — the capstone plugs `shop` into all four |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Adjust the dates. Never adjust the order.*

</div>
