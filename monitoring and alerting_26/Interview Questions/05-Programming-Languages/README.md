# 05 · Programming Languages

Go, Python and Java dominate these roles. Interviewers use language questions to test **depth over breadth** — knowing one language's memory model properly beats naming five.

---

## 🟢 Go (the default for infra/DevOps/SRE/platform)

### 1. Goroutines vs OS threads — what makes them cheap?
Goroutines are user-space tasks multiplexed by the Go runtime onto a small pool of OS threads (the **GMP model**: **G**oroutine, **M**achine/OS thread, **P**rocessor/logical context holding a run queue).

| | Goroutine | OS thread |
|---|---|---|
| Initial stack | ~2–8 KB, **growable/shrinkable** (segmented→contiguous with copy) | 1–8 MB reserved, fixed |
| Creation cost | ~hundreds of ns | ~10–100 µs + kernel work |
| Context switch | User-space: save a few registers, no syscall, no TLB flush | Kernel: full register save, possible page-table switch |
| Scheduling | Runtime, work-stealing across Ps | Kernel, preemptive |
| Practical scale | 100k–1M+ per process | 1k–10k |

**Blocking syscalls:** when a goroutine makes a blocking syscall, the runtime **detaches the M from the P** and hands the P to another M, so other goroutines keep running. Network I/O doesn't even block — the **netpoller** (epoll/kqueue/IOCP) parks the goroutine and reschedules it when the fd is ready. That's why Go gives async economics with synchronous-looking code.

**Preemption:** cooperative at function calls historically; **asynchronous preemption since 1.14** (signal-based) so a tight loop with no function calls can no longer starve other goroutines.

### 2. Channels vs mutexes — when each?
**Go proverb:** "Don't communicate by sharing memory; share memory by communicating." But the honest engineering answer:

- **Use channels** for: transferring **ownership** of data (producer→consumer), signalling/pipelines, fan-out/fan-in, cancellation (`done` channels, though `context.Context` is the idiomatic form), and bounding concurrency (`sem := make(chan struct{}, N)`).
- **Use mutexes** for: guarding a **shared data structure** (a cache, a counter, a map). Wrapping every field access in a channel is slower, more code, and easy to deadlock.
- **Rule of thumb:** channels for *flow of data*, mutexes for *state*. `sync.Mutex`/`RWMutex` for the latter; `sync/atomic` for single scalars; `sync.Map` only for the specific read-mostly/key-stable case it's optimised for (otherwise a `RWMutex` + map wins).

**Channel gotchas they'll probe:**
```go
var c chan int            // nil channel: send AND receive block forever
close(c); close(c)        // panic: close of closed channel
c <- 1                    // on a closed channel: panic
v, ok := <-c              // ok == false ⇒ channel closed and drained
```
- **Only the sender closes.** Never the receiver, never multiple senders (use `sync.Once`, a done-channel, or a coordinating goroutine).
- Receiving from a closed channel yields the zero value immediately — so a `for range ch` loop exits cleanly, but a bare `v := <-ch` can silently produce zeros. **That's a real bug class.**
- Unbuffered channel = synchronisation point (rendezvous, handoff guaranteed). Buffered = decoupling, but the buffer only delays backpressure; it doesn't remove it.

### 3. `select` — the multiplexer
```go
select {
case v := <-in:            handle(v)
case out <- result:        // ready to send
case <-ctx.Done():         return ctx.Err()      // cancellation — always include this
case <-time.After(5*time.Second): return ErrTimeout
default:                   // non-blocking poll
}
```
- Multiple ready cases → **chosen at random** (prevents starvation; don't rely on order).
- `default` makes it non-blocking.
- **Every blocking `select` in a long-running goroutine should include `<-ctx.Done()`** — otherwise it leaks when the request is cancelled. This is the most common Go bug in production services.

### 4. `context.Context` — what it actually does
Carries **cancellation**, **deadlines**, and **request-scoped values** across API boundaries and goroutines.

```go
ctx, cancel := context.WithTimeout(parent, 2*time.Second)
defer cancel()                                  // ALWAYS — else you leak the timer/goroutine
req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
```
Rules:
- Pass `ctx` as the **first parameter**, never store it in a struct field.
- Always `defer cancel()` — even on the timeout variant, or resources leak until the deadline.
- `context.Background()` at the root (main, request handlers); `context.TODO()` where you haven't plumbed it yet.
- **Values are for request-scoped metadata only** (trace ID, auth principal) — never for passing optional parameters; they're untyped and invisible in the signature.
- **Propagate deadlines downstream.** A caller with a 2s budget calling a callee with a 30s timeout will have abandoned the work but the callee keeps burning resources. Nested timeouts must shrink, never grow.

### 5. Go's GC and the settings you must know in containers
Concurrent, tri-colour **mark-and-sweep** with write barriers. No compaction (relies on size classes/spans). Sub-millisecond pauses; the cost is CPU (~25% of a core by default during marking).

- **`GOGC`** (default 100): next GC triggers when the heap grows by 100% of the live heap. Lower = more frequent GC = less memory, more CPU. Higher = the reverse.
- **`GOMEMLIMIT`** (1.19+): a **soft memory ceiling**. This is the one that matters in Kubernetes — without it, Go sizes the heap from the *node's* memory, not the container limit, and gets OOMKilled. Set it to ~80–90% of the container memory limit.
- **`GOMAXPROCS`**: defaults to the number of *host* CPUs, not the container's CPU limit. On a 64-core node with a 2-CPU limit, Go spawns 64 OS threads competing for 2 CPUs → throttling and latency spikes. Fix with `automaxprocs` (Uber) or set it explicitly from the cgroup quota.
- **`GODEBUG=gctrace=1`** to observe.
- **Escape analysis** decides stack vs heap: `go build -gcflags='-m'`. Returning a pointer to a local, or storing into an interface, typically forces a heap allocation. Reducing heap allocations is the highest-leverage Go performance work — more than any micro-optimisation.

**The pairing to remember: `GOMEMLIMIT` + `GOMAXPROCS`.** Naming both, and the failure each prevents, is an instant credibility marker for infra roles.

### 6. Errors, `panic`, and the error-handling debate
```go
if err != nil {
    return fmt.Errorf("loading config %s: %w", path, err)   // %w wraps → errors.Is/As work
}
```
- **Wrap with context, don't replace.** `errors.Is(err, os.ErrNotExist)` for sentinel comparison; `errors.As(err, &target)` for typed errors. Never `err.Error() == "not found"` — string matching breaks silently.
- **`panic`** is for unrecoverable programmer errors (invariant violations), not for error flow. `recover` only inside a deferred function, and idiomatically only at a **goroutine boundary** (an HTTP middleware recovering so one panic doesn't kill the process) or in library cleanup.
- **A panic in any goroutine crashes the whole program.** So every long-running goroutine you spawn in a server needs a deferred recover, or you've built a self-DoS.
- Sentinels (`io.EOF`, `sql.ErrNoRows`) vs typed errors vs opaque wrapping: sentinels for well-known cross-package conditions, typed when the caller needs fields, opaque otherwise.
- **The criticism of `if err != nil`:** verbose and easy to ignore (a missing check compiles fine — hence `errcheck`/`golangci-lint`). Go 1.13's `%w` + `errors.Is/As` improved composition; there's still no `try`. Know the trade-off and don't be defensive about it.

### 7. Interfaces are implicit — why does that matter?
```go
type Reader interface { Read(p []byte) (int, error) }
```
Any type with that method satisfies it, **no declaration needed**. Consequences:
- **Accept interfaces, return structs.** Functions take the narrowest interface they need (`io.Reader`, not `*os.File`); return concrete types so callers get full behaviour and you stay free to change internals.
- **Define interfaces where they're *used***, not where they're implemented (consumer-side interfaces). This inverts the usual Java habit and keeps packages decoupled — you don't need to import the implementation's package to define what you need.
- **Small interfaces** (`io.Reader`, `io.Writer`, `fmt.Stringer`, one or two methods) compose into powerful ones (`io.ReadWriter`, `io.ReadCloser`). Go's standard library is built almost entirely from these.
- An interface value is a **(type, pointer) pair**. The famous bug: a `nil` concrete pointer stored in an interface is **not** a nil interface — `if err != nil` can be true even when the underlying error pointer is nil. Return a bare `nil` from error-returning functions, never a typed nil.

### 8. Go memory model / data races
A **data race** (two goroutines, same memory, at least one write, no synchronisation) is **undefined behaviour** in Go's memory model — not just "wrong answer", but the compiler and runtime are permitted to do anything.

- Detect with `go test -race` / `go run -race`. **Run it in CI and in a staging soak test** — races are timing-dependent and often absent from short test runs.
- Synchronise with `sync.Mutex`/`RWMutex`, channels, `sync/atomic`, or `sync.Once`/`WaitGroup`/`errgroup`.
- **Happens-before** is the model: synchronisation operations create ordering; without them, no ordering is guaranteed.
- The classic leaks: appending to a shared slice from multiple goroutines (both a race *and* a lost-update), writing to a shared map (**fatal error: concurrent map writes** — this one crashes the program, not just corrupts it), and capturing a loop variable in a closure (**fixed in Go 1.22**: loop vars are per-iteration; before that you needed `v := v` inside the loop — worth knowing because legacy codebases are full of it).

---

## 🟢 Python (glue, automation, data, ML, scripting)

### 9. GIL — the precise answer
See [`01-CS-Fundamentals`](../01-CS-Fundamentals/README.md#14-what-is-the-gil-and-does-it-mean-python-cant-do-concurrency) for the full treatment. Interview-ready summary:

"The GIL is a mutex protecting CPython's interpreter state, mainly because reference counting isn't thread-safe. It blocks **parallelism**, not **concurrency**: I/O-bound threads work fine because the GIL is released during blocking syscalls, and asyncio works because it's single-threaded and cooperative. CPU-bound work needs `multiprocessing` (separate interpreters), native extensions that release the GIL (NumPy), or a different runtime. CPython 3.13+ offers free-threaded builds and per-interpreter GILs (PEP 703/684), but the C-extension ecosystem is still catching up, so I wouldn't bet production on it yet."

| Workload | Right tool |
|---|---|
| CPU-bound parallel | `multiprocessing`, `ProcessPoolExecutor`, or push into C/Rust |
| I/O-bound, many connections | `asyncio` (aiohttp/httpx) or threads |
| I/O-bound, few connections, simple | threads / `ThreadPoolExecutor` |
| Subprocess orchestration | `asyncio.create_subprocess_exec` |
| Numerical/array | NumPy/polars — releases the GIL inside C loops |

### 10. asyncio — what people get wrong
```python
async def fetch_all(urls):
    sem = asyncio.Semaphore(10)                     # BOUND concurrency — the critical bit
    async with aiohttp.ClientSession() as s:        # one session, pooled connections
        async def one(u):
            async with sem:
                async with s.get(u) as r:           # context managers, or you leak
                    return await r.text()
        return await asyncio.gather(*(one(u) for u in urls), return_exceptions=True)
```
Mistakes that reveal inexperience:
- **Calling blocking code inside `async def`** — one `time.sleep()` or `requests.get()` stalls the entire loop. Use `loop.run_in_executor()` for unavoidable blocking calls.
- **Unbounded task creation** — `gather` over 100k URLs creates 100k connections and gets you rate-limited or OOMs. Always a semaphore.
- **`asyncio.gather` without `return_exceptions=True`** — the first exception propagates and the other tasks are left running (and in older versions, silently).
- **Not closing sessions/connections** — leaks file descriptors and sockets.
- **Colour blindness**: async infects the whole call stack; you can't call async from sync without `run`/`run_until_complete`. Decide the model at the project level.
- **`asyncio` isn't faster for CPU work** — it's concurrency, not parallelism.

### 11. Decorators, context managers, generators
```python
import functools, time
def retry(times=3, backoff=0.5, exceptions=(Exception,)):
    def deco(fn):
        @functools.wraps(fn)                       # preserves __name__/docstring — don't forget
        def wrapper(*a, **kw):
            for i in range(times):
                try: return fn(*a, **kw)
                except exceptions:
                    if i == times - 1: raise
                    time.sleep(backoff * 2**i + random.uniform(0, backoff))
        return wrapper
    return deco

@contextlib.contextmanager
def timed(label):
    t0 = time.monotonic()
    try: yield
    finally: print(f"{label}: {time.monotonic()-t0:.3f}s")   # finally ⇒ runs on exception too
```
- **Generators** (`yield`) give lazy, O(1)-memory iteration — the right way to process a 10 GB log file. `yield from` delegates. Generator expressions `(x*2 for x in huge)` avoid materialising a list.
- **Context managers** guarantee cleanup even on exceptions (`__enter__`/`__exit__`, or `contextlib.contextmanager`). `finally` inside is the belt-and-braces form.
- **Decorators** are cross-cutting concerns without inheritance: retry, timing, caching (`functools.lru_cache`/`cache`), auth, rate limiting, metrics. Always `functools.wraps`.
- Know `@property`, `@staticmethod`, `@classmethod`, `__slots__` (memory for many small objects), `dataclasses`/`attrs`/`pydantic` (validation), and `functools.partial`.

### 12. Packaging, typing, testing — the "do you write real Python" questions
- **Virtualenvs / uv / poetry / pdm**: isolated dependency resolution. `requirements.txt` pins for reproducibility; `pyproject.toml` is the modern standard (PEP 621).
- **Type hints** are not enforced at runtime — **mypy/pyright** enforce them in CI. `from __future__ import annotations`, `Protocol` for structural typing (duck-typed interfaces), `TypedDict`, generics. For infra code, typing catches a large class of bugs cheaply; say you run it in CI.
- **pytest**: fixtures (dependency injection for tests), `parametrize`, `tmp_path`, `monkeypatch`, markers, `conftest.py`. Mock at the **boundary** (`responses`/`respx` for HTTP, `freezegun` for time), not internal functions — mocking internals makes tests brittle and refactor-hostile.
- **Time**: freeze it in tests. Never call `time.time()` directly in logic; inject a clock so tests are deterministic.
- **`__main__` guard**, `argparse`/`typer`/`click` for CLIs, `logging` (not `print`) with structured formatters, `if TYPE_CHECKING` to avoid runtime import cycles.

---

## 🟢 Java (still common for backend/enterprise SDE III)

### 13. JVM memory model and GC — the parts that matter operationally
**Memory areas:** heap (young gen: Eden + 2 survivors; old gen), metaspace (class metadata, off-heap since Java 8 — replaced PermGen, and **it can still OOM** with dynamic class generation), thread stacks (off-heap, `-Xss`), code cache, direct byte buffers (`-XX:MaxDirectMemorySize` — a common container OOM source that heap dumps won't show).

**Collectors:**
| Collector | Character | Use when |
|---|---|---|
| **Serial** | Single-threaded, stop-the-world | Tiny containers |
| **Parallel** | Throughput-oriented, multi-thread STW | Batch, latency-insensitive |
| **G1** | Region-based, incremental, predictable pause targets (`-XX:MaxGCPauseMillis`), **default since 9** | General-purpose servers |
| **ZGC** | Concurrent, coloured pointers + load barriers, **sub-millisecond pauses** at multi-hundred-GB heaps | Large heaps, latency-critical |
| **Shenandoah** | Concurrent compaction, similar goals to ZGC | Same |

**Container awareness — the classic production bug:** before JDK 8u191/10, the JVM read **host** memory and CPU, so a 32 GB node with a 2 GB container limit → JVM sizes the heap for 32 GB → **OOMKilled by the cgroup**, with a perfectly healthy-looking heap dump. Fix: `-XX:MaxRAMPercentage=75` (not a hardcoded `-Xmx`) and `-XX:ActiveProcessorCount` / rely on cgroup detection. **Name this failure mode — it's a very common interview scenario.**

**Tuning that matters:** `-XX:+UseG1GC -XX:MaxGCPauseMillis=200`, `MaxRAMPercentage`, `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=`, GC logging (`-Xlog:gc*:file=...`), and **always set requests=limits for memory** in Kubernetes so the JVM's view matches reality.

**Diagnostics:** `jcmd`, `jstat -gcutil <pid> 1s` (GC frequency/cause), `jmap -histo`, `jstack` (thread dumps — the answer to "it's hung"), `jfr`/JMC (flight recorder, low-overhead continuous profiling), async-profiler (flame graphs), `arthas`.

### 14. `equals`/`hashCode`, immutability, `Optional`
- **The contract:** equal objects must have equal hash codes. Override one, override the other — otherwise your object misbehaves in `HashMap`/`HashSet` (silently: you put it in, you can't get it out). Use `Objects.equals`/`Objects.hash` or records.
- **Records** (16+) give you immutable data carriers with correct `equals`/`hashCode`/`toString` for free — use them for DTOs and value types.
- **Immutability**: final fields, no setters, defensive copies of mutable inputs/outputs (`List.copyOf`), thread-safe by construction. Prefer `List`/`Map`/`Set` immutable factories.
- **`Optional`** is a **return type** signalling "may be absent". Never a field, never a parameter, never in a collection. Don't `.get()` without checking (that's the NPE you were avoiding). Prefer `.map()/.orElse()/.orElseGet()/.ifPresent()`. Note `orElseGet` for expensive defaults — `orElse` evaluates eagerly.
- **Collections:** `ArrayList` (random access, amortised O(1) append) vs `LinkedList` (rarely correct — cache-hostile) vs `CopyOnWriteArrayList` (read-mostly, writes copy the whole array) ; `HashMap` (O(1), treeifies buckets at 8 collisions) vs `LinkedHashMap` (insertion/LRU order) vs `TreeMap` (sorted, O(log n)) vs `ConcurrentHashMap` (segmented/CAS locking — **never** `Hashtable` or `Collections.synchronizedMap` for concurrent use).

### 15. Concurrency: `synchronized` vs `java.util.concurrent`
```java
var pool = new ThreadPoolExecutor(4, 16, 60, SECONDS,
        new ArrayBlockingQueue<>(1000),          // BOUNDED queue — unbounded = OOM under load
        new ThreadFactoryBuilder().setNameFormat("worker-%d").build(),
        new ThreadPoolExecutor.CallerRunsPolicy());   // backpressure, not silent drop
```
- **`synchronized`** is simple and correct (reentrant, monitor per object; biased/thin/fat lock escalation makes uncontended cases cheap). **`ReentrantLock`** adds tryLock, timeouts, fairness, and multiple `Condition`s — use it only when you need those.
- **`volatile`** gives visibility and ordering, **not atomicity** (`count++` is still a race). Use `AtomicInteger`/`LongAdder` (LongAdder is far better under high contention — it shards counters).
- **Executors**: know why `Executors.newFixedThreadPool` is dangerous in production (unbounded `LinkedBlockingQueue` → OOM). Build `ThreadPoolExecutor` explicitly with a bounded queue and a named rejection policy. **Named threads** are a small thing that makes `jstack` output readable during an incident.
- **`CompletableFuture`** for async composition (`.thenCompose` vs `.thenApply` — flatMap vs map), **always with an explicit executor** (the default `ForkJoinPool.commonPool()` is shared JVM-wide and blocking it stalls everything — a classic bug).
- **Virtual threads (Project Loom, GA in 21)**: JVM-managed lightweight threads; a blocking call unmounts the carrier thread. Makes thread-per-request scale to millions — the "Go model" in Java. Caveats to name: **pinning** (synchronized blocks and some native calls pin the carrier — largely fixed in JDK 24), no benefit for CPU-bound work, and thread-local memory blowups when you have a million threads.
- **Memory model / happens-before:** `final` fields safely published, `volatile` writes happen-before subsequent reads, lock release happens-before acquisition. Without one of these, reordering is permitted and other threads may never see your write.

---

## 🔵 Advanced (cross-language)

### 16. Compare the three for a CLI tool, a high-throughput service, and a data pipeline
| | **Go** | **Python** | **Java** |
|---|---|---|---|
| **CLI tool** | ✅ Best: static binary, no runtime, fast startup (~5 ms), cross-compile trivially | Weak: needs an interpreter, packaging/distribution pain (PyInstaller is fragile), ~50–100 ms startup | Weak: JVM startup ~200 ms+ (unless GraalVM native-image, which is slow to build and has reflection caveats) |
| **High-throughput network service** | ✅ Excellent: goroutines, low footprint, predictable GC pauses, fast | Poor for CPU; fine for I/O-bound glue with asyncio | ✅ Excellent: mature concurrency, JIT peak throughput often higher than Go, best-in-class GC (ZGC), huge ecosystem |
| **Data/ML pipeline** | Poor ecosystem | ✅ Dominant: pandas/polars/NumPy/scikit/torch | Good for big-data JVM stack (Spark, Flink, Kafka) |
| **Kubernetes operator** | ✅ The ecosystem *is* Go (controller-runtime, kubebuilder) | Possible but unusual | Possible (java-operator-sdk) but unusual |
| **Latency predictability** | Good (sub-ms GC, but no compaction) | N/A (GIL) | Best with ZGC (sub-ms at huge heaps); G1 needs tuning |
| **Hiring/team** | Infra teams | Everywhere | Enterprise/backend |

**Answer shape:** "Go for anything that ships as a binary or talks to Kubernetes; Python for glue, automation and data; Java for large long-lived services where peak throughput and mature tooling matter. The deciding factor is usually not performance — it's distribution model and ecosystem."

### 17. How would you debug a memory leak in each?
- **Go:** `runtime.MemStats`, `GODEBUG=gctrace=1`, then **pprof heap profiles** (`go tool pprof http://.../debug/pprof/heap`), and `inuse_space` vs `alloc_space` (in-use = leak; alloc = churn). Also check `goroutine` profile — **goroutine leaks are the most common Go "memory leak"**: a goroutine blocked forever on a channel or a missing `ctx.Done()` holds its stack and everything it references. `goleak` in tests catches them.
- **Python:** `tracemalloc`, `objgraph`, `gc.get_objects()`, `memory_profiler`, `fil-profiler`. Real causes: module-level caches growing unboundedly, `lru_cache` without `maxsize`, reference cycles with `__del__`, closures holding large frames, and **global lists you append to and never clear**.
- **Java:** `jmap -histo:live`, heap dump + **Eclipse MAT** (dominator tree → retention path is the actual answer), JFR allocation profiling, `jcmd GC.class_histogram`. Real causes: static collections, unclosed resources, `ThreadLocal` on pooled threads (classic — the thread survives, the value doesn't get collected), listeners never deregistered, classloader leaks in app servers.
- **Container-level first:** "Before language tooling I'd check whether it's actually the heap. In containers the usual suspects are **off-heap**: JVM direct buffers/metaspace, Go's `GOMEMLIMIT` not set, malloc arena fragmentation (glibc `MALLOC_ARENA_MAX`), page cache counted in cgroup memory, or the process is fine and the *limit* is too low." That answer is worth more than any profiler command.

### 18. Dependency injection — why bother, and how much is too much?
DI's real value is **testability and the dependency inversion principle**: a class that constructs its collaborators can't be tested with fakes, and can't be reused with different ones.

- **Manual DI** (constructor parameters, wired in `main`) is explicit, debuggable, and enough for most Go/Python codebases. Go has no standard DI framework for exactly this reason.
- **Framework DI** (Spring, Guice, FastAPI's `Depends`) pays off at scale: lifecycle management, configuration binding, AOP, consistent wiring across hundreds of classes.
- **Costs:** magic (behaviour not visible in the code), startup coupling, harder stack traces, and — in Spring — the temptation to inject 12 beans into one service, which is a cohesion problem the framework hid from you.
- **Senior position:** "Constructor injection always; a framework when the wiring complexity exceeds what a `main()` can express readably. The smell to watch for is a class with many injected dependencies — that's not a DI problem, it's a single-responsibility problem."

### 19. How do you handle versioning and backwards compatibility in a library/SDK others depend on?
- **Semver** and honest adherence: breaking change = major. In Go, major ≥ 2 requires a module path change (`/v2`) — an intentional friction that prevents accidental breaks.
- **Additive evolution:** new optional fields, new methods on interfaces (in Go, adding a method to a public interface **is** a breaking change for external implementers — so don't export small interfaces you expect others to implement, or provide an embedded default).
- **Deprecation with a timeline:** annotate/document, warn at runtime once per process (not per call — log spam), keep it working for at least one major cycle, then remove.
- **Wire compatibility is separate from API compatibility:** protobuf/gRPC field numbers must never be reused; JSON should ignore unknown fields (be liberal in what you accept, strict in what you emit); enums need an `UNSPECIFIED`/unknown variant or old clients break on new values.
- **Contract tests** on both sides (consumer-driven, e.g. Pact) catch breaks that unit tests can't.
- **The killer detail:** "I'd also version the *behaviour*, not just the shape — a flag or config to opt into new semantics, so consumers can migrate on their schedule rather than yours."

---

## 🔴 Scenario

### 20. "A Go service's p99 latency spikes every few minutes. Investigate."
Ranked hypotheses with the check for each:

1. **GC.** `GODEBUG=gctrace=1` → look at pause times and frequency. If GC CPU is high, you have allocation churn. Check pprof `alloc_space` (not `inuse_space`) — high allocation rate = GC pressure. Fixes: reduce allocations (reuse buffers via `sync.Pool`, avoid `interface{}` boxing, preallocate slices with `make([]T, 0, n)`, avoid string concatenation in loops), tune `GOGC` up, set `GOMEMLIMIT`.
2. **CPU throttling (in Kubernetes).** Not a Go problem at all — `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total > 0`. Caused by bursty work hitting the 100ms CFS quota, or **`GOMAXPROCS` set to the node's CPU count** instead of the container limit → too many runnable threads. Fix: raise/remove CPU limits (keep requests), `automaxprocs`.
3. **Goroutine leaks.** `debug/pprof/goroutine` count growing monotonically. Each leaked goroutine holds memory and eventually slows scheduling. Cause: missing `<-ctx.Done()` in a `select`, a channel send with no reader, an un-cancelled context.
4. **Lock contention.** pprof `mutex` and `block` profiles (enable with `runtime.SetMutexProfileFraction`). One hot mutex serialises everything. Fix: shard the lock, use `RWMutex` for read-mostly, `atomic` for scalars, or restructure to per-goroutine state with channels.
5. **Syscall/blocking work on the critical path.** DNS lookups without a caching resolver, `cgo` calls (which pin an OS thread), file I/O (not handled by the netpoller — it blocks an M). Check `strace -c` or the trace viewer.
6. **Downstream dependency.** p99 spikes may be imported. Check per-dependency latency histograms and correlate timestamps.
7. **Something periodic and external.** Cron jobs, log rotation, a sidecar's scrape interval, autoscaling events, node-level noisy neighbours, TLS session/cert refresh, connection pool churn (all connections expiring at once → thundering reconnect). **Correlate the spike timestamps with `date` math** — if it's exactly every 60s or every 5m, it's a timer, and finding which one is the whole job.

**Tool to mention:** `go tool trace` — the execution tracer shows goroutine scheduling, GC, syscalls and blocking on a timeline, and it's the fastest way to see *why* latency spiked rather than guessing.

**Answer shape:** "I'd start by asking whether the spikes are periodic, because periodic means a timer and that narrows it to five candidates immediately. Then GC vs throttling — in Kubernetes, throttling is more common and it isn't a Go problem at all. gctrace and the throttling ratio settle it in two minutes."

### 21. "Write code that fetches 10,000 URLs with a concurrency limit, per-request timeout, retries and partial-failure tolerance." (Go)
```go
package fetcher

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"golang.org/x/sync/errgroup"
)

type Result struct {
	URL  string
	Code int
	Body []byte
	Err  error
}

type Fetcher struct {
	client      *http.Client
	concurrency int
	attempts    int
}

func New(concurrency int, perRequest time.Duration, attempts int) *Fetcher {
	return &Fetcher{
		// ONE client: connection pooling is the whole point.
		// A client per request leaks sockets and disables keep-alive.
		client: &http.Client{
			Timeout: perRequest,                 // overall, including body read
			Transport: &http.Transport{
				MaxIdleConns:        concurrency * 2,
				MaxIdleConnsPerHost: concurrency * 2,
				IdleConnTimeout:     90 * time.Second,
				// DialContext timeout + TLSHandshakeTimeout for finer control
			},
		},
		concurrency: concurrency,
		attempts:    attempts,
	}
}

// FetchAll never returns an error for individual URLs: failures are per-result.
// It returns an error only if the whole operation is cancelled.
func (f *Fetcher) FetchAll(ctx context.Context, urls []string) []Result {
	results := make([]Result, len(urls))   // pre-sized: index writes need no mutex
	g, ctx := errgroup.WithContext(ctx)
	g.SetLimit(f.concurrency)              // bounded concurrency — the critical line

	for i, u := range urls {
		i, u := i, u                        // pre-1.22 loop-var capture safety
		g.Go(func() error {
			body, code, err := f.fetchWithRetry(ctx, u)
			results[i] = Result{URL: u, Code: code, Body: body, Err: err}
			return nil                      // DON'T fail the group on one bad URL
		})
	}
	if err := g.Wait(); err != nil {       // only ctx cancellation lands here
		// mark unfinished slots
		for i := range results {
			if results[i].URL == "" { results[i] = Result{URL: urls[i], Err: err} }
		}
	}
	return results
}

func (f *Fetcher) fetchWithRetry(ctx context.Context, url string) ([]byte, int, error) {
	var lastErr error
	for attempt := 0; attempt < f.attempts; attempt++ {
		if attempt > 0 {
			// exponential backoff with equal jitter; respect Retry-After if present
			backoff := min(30*time.Second, time.Duration(1<<uint(attempt-1))*500*time.Millisecond)
			select {
			case <-ctx.Done():
				return nil, 0, ctx.Err()
			case <-time.After(backoff/2 + time.Duration(rand.Int63n(int64(backoff/2)+1))):
			}
		}
		body, code, err := f.fetchOnce(ctx, url)
		if err == nil && code < 500 && code != 429 {
			return body, code, nil                 // success, or a client error not worth retrying
		}
		lastErr = err
		if lastErr == nil { lastErr = fmt.Errorf("http %d", code) }
		if !retryable(code, err) || ctx.Err() != nil { break }
	}
	return nil, 0, fmt.Errorf("fetch %s after %d attempts: %w", url, f.attempts, lastErr)
}

func (f *Fetcher) fetchOnce(ctx context.Context, url string) ([]byte, int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil { return nil, 0, err }
	resp, err := f.client.Do(req)
	if err != nil { return nil, 0, err }
	defer resp.Body.Close()                        // ALWAYS — else fd/connection leak
	body, err := io.ReadAll(io.LimitReader(resp.Body, 10<<20))  // cap: don't OOM on a huge body
	if err != nil { return nil, resp.StatusCode, err }
	return body, resp.StatusCode, nil
}

func retryable(code int, err error) bool {
	if err != nil {
		var te interface{ Timeout() bool }
		if errors.As(err, &te) && te.Timeout() { return true }
		return true                              // network errors: assume transient
	}
	return code >= 500 || code == 429 || code == 408
}

func min(a, b time.Duration) time.Duration { if a < b { return a }; return b }
```

**What the interviewer is checking — say these out loud:**
- **One shared `http.Client`** with tuned `Transport` → connection reuse. A client per request is the #1 Go HTTP mistake (socket exhaustion, no keep-alive).
- **Bounded concurrency** (`g.SetLimit`) — 10k goroutines is fine memory-wise, but 10k simultaneous connections is a self-inflicted DDoS and will exhaust fds and get you rate-limited.
- **Context everywhere**: cancellation propagates, so Ctrl-C or a deadline actually stops the work.
- **Partial failure**: results are indexed, so writes need no mutex; individual failures are values, not errors. Only cancellation fails the batch. **`return nil` inside `g.Go` is deliberate** — a common bug is returning the error and aborting all 10k fetches because one URL 404'd.
- **Retries with jitter**, only for retryable conditions (5xx, 429, timeouts, network errors) — **not** for 4xx, which will fail identically forever.
- **`defer resp.Body.Close()`** and **`io.LimitReader`** — fd leaks and unbounded memory are both real production incidents.
- Pre-1.22 loop-variable capture (`i, u := i, u`).

**Follow-ups to pre-empt:** "How would you stream results instead of collecting them?" (return a channel or accept a callback; then backpressure matters). "How would you add a per-host limit?" (a second semaphore keyed by host, or `MaxConnsPerHost`). "How would you make it resumable?" (persist completed URLs; the work is idempotent). "How would you measure it?" (per-attempt histogram, success rate, wall time, and a metric for concurrency actually achieved — which tells you if the limit or the network is the constraint).

### 22. "Refactor this 800-line function." (they show you spaghetti)
Don't start typing. Narrate a plan:

1. **Understand before changing.** What does it do end to end? Any tests? If not, **write characterisation tests first** — capture current behaviour (inputs → outputs, including the weird edge cases) so you can prove the refactor didn't change semantics. This is the single most important sentence in the whole answer.
2. **Find the seams.** Usually: input parsing/validation, the core decision logic, the I/O, and output formatting. Those become separate functions with explicit inputs and outputs.
3. **Extract, don't rewrite.** Mechanical steps: extract method, replace temp with query, introduce parameter object, replace conditionals with polymorphism/strategy where the `if/elif` chain is growing.
4. **Push I/O to the edges.** Core logic becomes pure (no network, no clock, no globals) → trivially testable. Inject the clock and the clients.
5. **Make illegal states unrepresentable.** Replace string status fields with enums/sum types; validate once at the boundary and pass a parsed type inward, so the core can't see invalid input.
6. **Reduce nesting** with guard clauses (early return) instead of `else` pyramids.
7. **Re-run the characterisation tests** after each small step. Small commits, each green.
8. **Then, and only then,** improve: better names, remove dead branches, add the missing error handling you noticed.

**Say the constraint you'd negotiate:** "If this is on a critical path and I can't get test coverage, I'd do a strangler-fig: build the new implementation alongside, shadow-run both and compare outputs in production, then cut over. Slower, but it doesn't require trusting my reading of 800 lines."

That last paragraph is what makes it an SDE III answer rather than an SDE II answer.

---

## Red flags

| Saying this | Costs you |
|---|---|
| "Go has no data races because of the scheduler" | Race detector exists for a reason |
| Creating an `http.Client` per request | Socket exhaustion; the classic Go HTTP bug |
| Unbounded goroutines/tasks | You designed a self-DoS |
| `select` without `ctx.Done()` | Goroutine leak |
| Missing `defer cancel()` | Timer/goroutine leak |
| Forgetting `resp.Body.Close()` | fd leak — see the file-descriptor scenario in topic 01 |
| `Executors.newFixedThreadPool` in production Java | Unbounded queue → OOM |
| Hardcoded `-Xmx` in a container | Ignoring cgroup limits → OOMKilled |
| "The GIL means Python can't do concurrency" | Imprecise; blocks parallelism only |
| Blocking calls inside `async def` | Stalls the entire event loop |
| Overriding `equals` without `hashCode` | Silent map/set corruption |
| String-comparing errors (`err.Error() == "..."`) | Breaks silently on message changes |
| Refactoring without characterisation tests | "How do you know you didn't break it?" |

## Rapid recall

**Go:** GMP scheduler, netpoller, async preemption (1.14) · channels for flow, mutexes for state · only senders close · `<-ctx.Done()` in every select · `defer cancel()` always · **`GOMEMLIMIT` + `GOMAXPROCS`/automaxprocs** in containers · `%w` + `errors.Is/As` · accept interfaces, return structs · goroutine leaks are the common "memory leak" · one shared `http.Client`.

**Python:** GIL blocks parallelism not concurrency · `multiprocessing` for CPU, asyncio/threads for I/O · never block in `async def` · bound concurrency with a semaphore · generators for streaming · `functools.wraps` on decorators · `time.monotonic()` · mypy + pytest in CI, mock at boundaries.

**Java:** heap/metaspace/direct-buffers are separate OOM sources · G1 default, ZGC for sub-ms at large heaps · **container awareness: `MaxRAMPercentage`, not `-Xmx`** · bounded `ThreadPoolExecutor` + named threads + rejection policy · `CompletableFuture` with an explicit executor · virtual threads (21+) for thread-per-request at scale, watch pinning · equals/hashCode together · `Optional` as a return type only.

**Cross-language:** characterisation tests before refactoring · profile before optimising (`inuse` vs `alloc`) · version wire format separately from API · DI for testability, not for magic.

→ Next: [`06-Docker-and-Containers`](../06-Docker-and-Containers/README.md)
