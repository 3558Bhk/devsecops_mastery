# 04 · Low-Level Design (LLD) / Object-Oriented Design

Common in SDE III loops (especially at product companies and for platform roles designing SDKs/CLIs/operators). The score is on **clean abstractions, correct concurrency, and extensibility** — not on diagram beauty.

---

## 🟢 Basic

### 1. SOLID, with a real example each
| Principle | Meaning | Violation → fix |
|---|---|---|
| **S**ingle Responsibility | One reason to change | A `UserService` that validates, persists, sends email and formats JSON → split into validator, repository, notifier, presenter. Test: "can I describe this class without using 'and'?" |
| **O**pen/Closed | Open for extension, closed for modification | `if type == "card": ... elif type == "upi": ...` growing forever → strategy/plugin per payment method behind an interface |
| **L**iskov Substitution | Subtypes must be usable wherever the base is | `Square extends Rectangle` where `setWidth` also sets height breaks callers → don't model it that way. Or a subclass that throws `UnsupportedOperationException` |
| **I**nterface Segregation | No client forced to depend on methods it doesn't use | One fat `Repository` with 20 methods → split `Reader`/`Writer`/`BulkLoader` |
| **D**ependency Inversion | Depend on abstractions, not concretions; high-level policy shouldn't import low-level detail | `new SmtpMailer()` inside a class → inject a `Mailer` interface. This is what makes it testable |

**Senior framing:** "SOLID is a means, not an end. The end is: change is local, behaviour is testable, and a new engineer can predict what a class does. I've seen SOLID applied as a way to generate 40 files for a 200-line problem — that's cargo cult, and I'd push back on it."

### 2. Design patterns you should be able to name *and* reject
| Pattern | Use for | When it's wrong |
|---|---|---|
| **Strategy** | Interchangeable algorithms (payment methods, retry policies, compression) | One implementation forever → just a function |
| **Factory / Abstract Factory** | Centralise construction, hide concrete types | Trivial objects → `new` is fine |
| **Builder** | Many optional params, validated construction | < 4 params → constructor/kwargs |
| **Observer / Pub-Sub** | Decouple event producer from N consumers | Simple one-to-one call → direct call |
| **Decorator** | Add behaviour by wrapping (retry, metrics, auth around a handler) | Deep nesting → hard to trace; consider middleware chains |
| **Adapter** | Make an incompatible interface work | — |
| **Facade** | Simplify a subsystem behind one entry point | Hides too much → leaky abstraction |
| **Singleton** | One instance (config, logger, registry) | **Global mutable state**: breaks tests, hides dependencies, concurrency hazards. Prefer DI with a single-scope binding |
| **Repository** | Abstract persistence behind a domain interface | Trivial CRUD app → you've added a passthrough layer |
| **Unit of Work** | Coordinate a transaction across repositories | — |
| **Chain of Responsibility** | Middleware/pipeline (HTTP, validation) | — |
| **State** | Object behaviour varies by state (order lifecycle) | 2-3 states → a switch is clearer |
| **Template Method** | Fixed skeleton, variable steps | Inheritance-heavy; prefer composition/strategy |
| **Flyweight** | Share many fine-grained objects | Rarely needed outside parsers/engines |

**The line that scores:** "I reach for patterns to solve a problem I can name, not to demonstrate I know them. Most 'pattern' codebases are just indirection."

### 3. Composition over inheritance — argue it
Inheritance couples a subclass to its parent's implementation: a parent change can silently break children (the fragile base class problem), you get one axis of variation, and behaviour is spread across a hierarchy that's hard to trace.

Composition gives you N independent axes (a `Handler` with a `RetryPolicy`, a `MetricsRecorder`, and an `AuthChecker` injected separately), each testable alone, each replaceable. This is why Go has no class inheritance at all, and why modern Java/Spring favours composition + interfaces.

**When inheritance is right:** genuine *is-a* with shared invariants and a stable base — e.g. an exception hierarchy, or a template method in a framework where the framework owns the base class and you own the leaf.

### 4. Cohesion and coupling — how would you measure them?
**Coupling** (want low): fan-in/fan-out, the **instability metric** `I = fan_out / (fan_in + fan_out)` (0 = maximally used and stable, 1 = maximally dependent), **afferent/efferent** counts, and the **abstractness** balance (the "main sequence" — concrete-and-depended-upon and abstract-and-depending are both suspicious).

**Cohesion** (want high): **LCOM** (lack of cohesion in methods) — if a class's methods use disjoint sets of its fields, it's really several classes.

**Practical version for an interview:** "I measure coupling by asking how many files change when I change this one, and cohesion by asking whether I can name the class's single job. Tools help (`jdepend`, `pydeps`, `go list -deps`, dependency-cruiser, ArchUnit tests) but the cheapest check is your PR diff size distribution — if changing a config field touches 14 files, coupling is the problem."

**Also mention:** **acyclic dependencies** (a cycle between modules means they're one module pretending to be two — and it breaks builds, testing and versioning), and **stable-dependencies** (depend toward the stable/abstract, never the reverse).

---

## 🔵 Advanced

### 5. Design a thread-safe in-memory LRU cache (with eviction and TTL)
```python
from collections import OrderedDict
from threading import RLock
import time

class TTLCache:
    def __init__(self, capacity: int, default_ttl: float | None = None):
        self._cap = capacity
        self._ttl = default_ttl
        self._data: OrderedDict[str, tuple[float, float]] = OrderedDict()  # key -> (value, expires_at)
        self._lock = RLock()                       # re-entrant: get() calls _evict_if_expired()
        self.hits = self.misses = 0

    def get(self, key: str):
        with self._lock:
            item = self._data.get(key)
            if item is None:
                self.misses += 1
                return None
            value, expires = item
            if expires and expires < time.monotonic():     # monotonic, not wall clock
                del self._data[key]
                self.misses += 1
                return None
            self._data.move_to_end(key)                   # mark as recently used
            self.hits += 1
            return value

    def put(self, key: str, value, ttl: float | None = None) -> None:
        ttl = self._ttl if ttl is None else ttl
        expires = time.monotonic() + ttl if ttl else 0.0
        with self._lock:
            if key in self._data:
                self._data.move_to_end(key)
            self._data[key] = (value, expires)
            while len(self._data) > self._cap:
                self._data.popitem(last=False)            # evict LRU
```

**The discussion points they're actually after:**
- **Data structure:** `OrderedDict` (or HashMap + doubly-linked list) gives O(1) get/put/evict. Explain why a plain dict + sorting is O(n log n).
- **Locking:** one mutex is correct but serialises everything. **Shard by key hash** (N independent caches, each with its own lock) to cut contention ~N× — and immediately name the cost: eviction becomes per-shard, so it's no longer a true global LRU, and a hot shard can evict while others are empty. That trade-off statement is the senior signal.
- **TTL expiry strategy:** lazy (on access — cheap, but expired entries hold memory), eager (a sweeper thread — bounded memory, costs CPU and adds a background lifecycle), or both. Also **TTL jitter** to avoid a mass-expiry stampede.
- **Metrics:** hit ratio, evictions, size — because a cache without metrics is a mystery, and a falling hit ratio is often the first sign of an incident elsewhere.
- **Extensions they may ask for:** `getOrLoad(key, loader)` with **singleflight** (coalesce concurrent loads of the same key — one caller does the work, others wait), negative caching, weight-based eviction (evict by bytes, not count), LFU/ARC/TinyLFU instead of LRU (LRU is badly beaten by scan-resistant policies — Caffeine's W-TinyLFU is why), and persistence/replication.

```go
// singleflight sketch — the piece that stops cache stampedes
type loader struct{ mu sync.Mutex; inflight map[string]*call }
type call struct{ wg sync.WaitGroup; val any; err error }

func (l *loader) Do(key string, fn func() (any, error)) (any, error) {
    l.mu.Lock()
    if c, ok := l.inflight[key]; ok { l.mu.Unlock(); c.wg.Wait(); return c.val, c.err }
    c := &call{}; c.wg.Add(1); l.inflight[key] = c; l.mu.Unlock()
    c.val, c.err = fn(); c.wg.Done()
    l.mu.Lock(); delete(l.inflight, key); l.mu.Unlock()
    return c.val, c.err
}
```

### 6. Design a rate limiter class (token bucket, sliding window)
```python
class SlidingWindowCounter:
    """Approximate sliding window: blends the previous fixed window with the current one."""
    def __init__(self, limit: int, window_s: int, clock=time.monotonic, storage=None):
        self.limit, self.window, self.clock = limit, window_s, clock
        self.storage = storage or {}          # key -> (prev_count, cur_count, cur_window_start)

    def allow(self, key: str, cost: int = 1) -> tuple[bool, dict]:
        now = self.clock()
        wstart = int(now // self.window) * self.window
        prev, cur, cur_start = self.storage.get(key, (0, 0, wstart))
        if cur_start != wstart:
            prev, cur, cur_start = cur, 0, wstart          # roll the window
        elapsed = now - wstart
        weight = (self.window - elapsed) / self.window      # how much of prev still counts
        effective = prev * weight + cur
        if effective + cost > self.limit:
            retry_after = self.window - elapsed
            return False, {"retry_after": retry_after, "remaining": 0}
        self.storage[key] = (prev, cur + cost, cur_start)
        return True, {"remaining": int(self.limit - effective - cost)}
```

**Design conversation:**
- **Which algorithm** and why: token bucket (allows bursts up to capacity, smooth average), leaky bucket (strictly smooth, adds latency), sliding window counter (cheap, approximate — no per-request timestamps), sliding window log (exact, memory per request).
- **State locality**: in-process (fast, but N instances = N× the effective limit), Redis + **Lua script** for atomic check-and-decrement (correct across instances, one hop), or hybrid (local budget with periodic global reconciliation — approximate but fast, and degrades if Redis dies).
- **Atomicity**: `GET` then `INCR` is a race. Use Lua/`WATCH-MULTI-EXEC`/`INCR`+`EXPIRE` carefully (and note the classic bug: if the process dies between `INCR` and `EXPIRE`, the key lives forever → use a single atomic script or `SET ... EX NX` patterns).
- **Key choice**: user ID > API key > IP (NAT/CGNAT makes IP-based limits hurt thousands of real users). Combine: `limit:{tenant}:{endpoint}:{identity}`.
- **Failure policy**: fail open (availability first, protection lost) vs fail closed (protection first, availability lost) — make it **per-rule**, and alert either way.
- **Response contract**: `429` + `Retry-After` + `X-RateLimit-{Limit,Remaining,Reset}` so well-behaved clients back off.
- **Multi-tenancy & fairness**: per-tenant limits plus a global cap so one tenant can't starve the system.

### 7. Design a task/job queue with workers, retries and priorities
**Interfaces:**
```python
class Broker(Protocol):
    def enqueue(self, task: Task) -> None: ...
    def dequeue(self, queues: Sequence[str], timeout: float) -> Task | None: ...
    def ack(self, task: Task) -> None: ...
    def nack(self, task: Task, requeue_after: float | None) -> None: ...

class Task(NamedTuple):
    id: str                 # idempotency key
    name: str
    payload: bytes
    queue: str              # priority lane
    attempts: int
    max_attempts: int
    visible_at: float       # for delayed retry / visibility timeout
    deadline: float         # propagated from the producer
```
**Worker loop:** dequeue (with visibility timeout so a crashed worker's task is redelivered) → check deadline, drop if expired → execute with a timeout and cancellation → ack, or nack with exponential backoff + jitter → after `max_attempts`, route to **DLQ** and emit a metric.

**Design decisions to articulate:**
- **At-least-once** delivery + **idempotent tasks** keyed by `task.id` (dedupe table with TTL, or a natural-key upsert). Exactly-once isn't achievable.
- **Visibility timeout must exceed the task's max runtime**, or the same task runs twice concurrently. Better: lease extension/heartbeat while working (SQS `ChangeMessageVisibility`, Temporal heartbeats).
- **Priorities**: separate queues drained in weighted order (strict priority starves low lanes → use weighted round-robin or aging). Single-queue-with-priority-field is worse: you must scan to find the highest.
- **Backpressure**: bounded queue; when full, reject with 429 or block the producer. Never grow unboundedly — that turns overload into OOM.
- **Concurrency control**: per-worker semaphore; global concurrency via the broker; per-key serialisation when ordering matters (route by hash to a single consumer).
- **Poison messages**: detect by attempt count, quarantine, alert on DLQ depth > 0, keep original metadata for replay.
- **Observability**: queue depth, oldest-message age (the real SLI — depth alone hides a stuck queue), processing rate, failure rate by task type, retry distribution, DLQ depth.
- **Buy vs build**: "I'd use SQS/Celery/Temporal/Sidekiq/RabbitMQ rather than build this. The reason to build is a requirement they can't meet — and if that requirement is 'exactly-once workflow with long-running state', the answer is Temporal, not a hand-rolled queue."

### 8. Design a notification service (email/SMS/push) — the extensibility test
```
Producer ──► API ──► Queue ──► Dispatcher ──► Provider adapters (SES/Twilio/FCM)
                                  │                  │
                             Template engine     Retry/DLQ
                             Preference store    Rate limiting per provider
                             Dedup/throttle      Delivery webhooks
```
**Interfaces:**
```python
class Channel(Protocol):
    name: str
    def send(self, msg: RenderedMessage) -> ProviderResult: ...
    def health(self) -> Health: ...

class Provider(Protocol):            # one channel, many providers → failover
    def send(self, req: ProviderRequest) -> ProviderResult: ...
```
**The abstractions that matter:**
- **`Channel` vs `Provider`** as separate concepts: `email` is a channel; SES, Postmark and SendGrid are providers. That separation gives you **failover and cost routing** for free. Getting this wrong (hardcoding SES) is the classic failure.
- **Template rendering separated from sending** so templates are testable and localisable.
- **Preference/subscription resolution** as its own step (user opted out of marketing but not transactional) — and the distinction between **transactional** (must send, never throttled) and **marketing** (throttled, digestible, opt-out enforced).
- **Deduplication and throttling**: don't send 40 emails about 40 alerts — aggregate (this is exactly Alertmanager's grouping). Key on `(user, template, dedup_key)` with a window.
- **Rate limiting per provider** (they all have quotas) plus **circuit breaking** so a degraded provider doesn't consume your workers.
- **Delivery status is async**: providers call back (webhook) → you must correlate to your message ID, handle out-of-order and duplicate callbacks idempotently, and expose a delivery timeline.
- **Compliance**: consent records, unsubscribe handling (List-Unsubscribe headers, one-click), suppression lists (bounces/complaints must permanently suppress — sending to a hard bounce destroys your sender reputation), quiet hours, GDPR deletion.
- **Testing**: a fake provider that records everything (so CI can assert "exactly one email, correct template, correct recipient"), plus a sandbox mode.

### 9. Design an order/checkout system with inventory (the consistency test)
**Domain model:** `Order`, `OrderItem`, `InventoryReservation`, `Payment`, `Shipment` as aggregates with clear boundaries. **Aggregate roots** own their invariants — don't let a service reach into another aggregate's fields.

**The hard problem:** reserving stock and taking payment span services/stores → no single transaction.

**Saga with an orchestrator:**
```
CreateOrder(pending)
  → ReserveInventory(orderId, items)   [compensate: ReleaseInventory]
  → AuthorisePayment(orderId, amount)  [compensate: VoidPayment]
  → ConfirmOrder(orderId)              → emits OrderConfirmed
  → Fulfil(orderId)
```
Each step is a **local transaction** writing its own state plus an **outbox** row; the orchestrator advances on events. Failure at any step runs compensations in reverse order.

**Must-handle details:**
- **Inventory reservation must expire** (TTL, e.g. 15 min) or abandoned carts hold stock forever. This is a real business bug, not a theoretical one.
- **Overselling under concurrency**: `UPDATE inventory SET qty = qty - ? WHERE sku = ? AND qty >= ?` — the conditional update is the atomic guard. Or a DB constraint, or a serialisable transaction, or a single-writer per SKU. **Never** read-check-write in application code.
- **Payment retries need an idempotency key** (`orderId` works) so a retried saga step doesn't double-charge.
- **Intermediate states are visible** to users (order exists but payment pending) — design the UI and the queries for that, use semantic locks/`status` fields, and never expose a half-applied state as final.
- **Compensation can fail too.** Then you need a reconciliation job and a human queue. Say this — it's the part most candidates skip.
- **Eventual consistency between the order store and the search/analytics stores**: CDC or outbox → Kafka → projections. Reads for the user's own order should go to the **primary** (read-your-writes), not a replica.

### 10. Design a plugin/extension system (very common for platform roles)
```python
class Plugin(Protocol):
    name: str
    version: str
    def on_load(self, ctx: PluginContext) -> None: ...
    def on_unload(self) -> None: ...

class Registry:
    def register(self, entrypoint: str) -> None: ...
    def get(self, name: str) -> Plugin: ...
    def all_for(self, hook: str) -> list[Plugin]: ...
```
**Decisions:**
- **Discovery**: language-native entry points (`importlib.metadata` entry_points, Go `plugin` package or compiled-in registry, Java `ServiceLoader`, K8s CRDs/OLM). Entry points beat hardcoded lists because third parties can add plugins without editing your code — that's the O in SOLID applied to packaging.
- **Contract stability**: the plugin API is a **public interface**. Version it (`apiVersion`), deprecate rather than break, and document the compatibility promise. Once shipped, you can't change it.
- **Isolation & blast radius**: a crashing plugin must not kill the host. Options: in-process with panic recovery (weakest), subprocess (good isolation, IPC cost), WASM sandbox (strong isolation, portable, limited capabilities), container/sidecar (strongest, heaviest). **Say the trade-off curve.**
- **Capabilities/permissions**: what may a plugin do — network? filesystem? secrets? Declare required capabilities in the manifest and enforce them (this is exactly Kubernetes' RBAC/securityContext model, and Backstage/VS Code's permission model).
- **Configuration**: schema-validated config per plugin instance (JSON Schema / CUE), not free-form maps.
- **Lifecycle**: load order, dependency ordering (**topological sort** — and detect cycles), hot reload vs restart-required, graceful unload with draining.
- **Observability**: per-plugin metrics (calls, latency, errors) so a bad plugin is identifiable, and per-plugin rate limits.

**Real examples to cite:** Terraform providers, Kubernetes operators/CRDs + admission webhooks, Backstage plugins, Envoy filters (WASM/Lua), GitHub Actions, Prometheus exporters/SD plugins, Grafana data sources.

---

## 🔴 Scenario

### 11. "Design a parking lot" (the classic — here's how to make it senior)
Most candidates draw classes. Seniors **first ask what the system is for**:

> "Before I model classes, what's the actual requirement set? Is this (a) the physical control system — barriers, slot sensors, display boards; (b) the payment/booking system; or (c) an analytics/optimisation system? They have almost no classes in common. And what's the scale — one lot or 500 lots across cities, because that decides whether 'Lot' is an object or a tenant."

Then, assuming (b) for a chain of lots:

**Domain:** `ParkingLot` → `Floor` → `Section` → `Slot` (with `SlotType`: compact/standard/EV/accessible and `SlotStatus`: free/occupied/reserved/out_of_service). `Vehicle` (type → determines eligible slots and price). `Ticket` (entry time, slot, vehicle, charges). `PricingStrategy` (**strategy pattern** — hourly, flat, peak/off-peak, member discounts, EV subsidy). `Payment` + `PaymentProvider` (channel/provider split). `Reservation` with TTL.

**Behaviour worth getting right:**
- **Allocation policy** is a strategy, not hardcoded: nearest to exit, lowest floor first, group families together, prefer accessible slots only for permitted vehicles. Making it pluggable is the OCP win.
- **Concurrency**: two screens assigning the same slot. Guard with a conditional update (`UPDATE slots SET status='occupied' WHERE id=? AND status='free'` and check rows-affected) or an optimistic version column — **not** read-then-write in code.
- **Slot state is sensor-authoritative**: the software model can disagree with reality (a car parks without a ticket, a sensor fails). Design for reconciliation, and treat the physical sensor as the source of truth with the DB as a cache.
- **Entry/exit flows must work offline**: the barrier can't depend on a cloud round trip. Local decision, sync later — which makes it a distributed-systems problem with conflict resolution.
- **Pricing at exit must be deterministic and reproducible** (disputes!) — store the applied strategy *version* and the inputs on the ticket, don't recompute from current config.

**Non-functional:** availability of the barrier (safety-critical — fail **open** for egress, fail **safe** for ingress), audit trail for payments, PCI scope minimisation (tokenise; never store PANs), multi-tenant isolation for a chain, and analytics as an async projection (never in the entry path).

**What the interviewer is scoring:** did you clarify scope, did you find the concurrency bug, did you separate policy from mechanism, and did you notice the physical/digital divergence. Not how many classes you drew.

### 12. "Design an elevator system" — the state-machine version
Same clarifying move, then focus on **scheduling as the interesting part**.

**State machine per car:** `IDLE → MOVING → DOOR_OPENING → DOOR_OPEN → DOOR_CLOSING → MOVING`, plus `OUT_OF_SERVICE`, `EMERGENCY`, `INSPECTION`. Model it explicitly (`State` pattern or a table-driven FSM) — **never** a pile of booleans (`isMoving && !doorOpen && !isEmergency` is unmaintainable and permits impossible states). Making **illegal states unrepresentable** is the design win to name.

**Dispatch algorithm** (the real design):
- Naive FCFS → terrible (one far call monopolises a car).
- **SCAN / LOOK**: serve requests in the current direction until none remain, then reverse. Simple, big improvement.
- **DESTINATION dispatch** (modern): passengers pick the destination *before* boarding; group same-destination riders into one car. Throughput up ~30%, at the cost of "you can't press your floor inside" — a UX trade-off worth stating.
- Objective function: minimise **average wait**, or **95th-percentile wait** (better — averages hide the person waiting 4 minutes), or energy, or a weighted mix. Peak-hour asymmetry (everyone up at 9:00) needs a different policy than midday → **mode switching**, which is itself a state machine.

**Hard constraints to raise unprompted:** safety interlocks (door cannot open while moving; car cannot move while a door is open — these are *invariants*, enforced in hardware and asserted in software), overload handling, fire/emergency recall (all cars to lobby, ignore calls), power failure (brake engaged, rescue), maintenance mode, and **the software must not be the only safety layer** — that's a regulatory and ethical point, and mentioning it reads as genuine seniority.

**Testing:** simulate thousands of passengers against the FSM, assert invariants hold on every transition (property-based testing), and specifically fuzz out-of-order sensor events — because sensor glitches, not logic bugs, cause real failures.

### 13. "Design a CLI + SDK that 200 engineers will use" (platform-role LLD)
This is where platform-engineering LLD differs from generic OOD: **the API is the product.**

**Layers:**
```
CLI (cobra/click)  ┐
SDK (typed client) ├──► Core logic (pure, no I/O) ──► Transport (HTTP/gRPC, retries, auth)
Terraform provider ┘                                        │
                                                        Config resolution
                                                        (flags > env > project file > user file > defaults)
```
**Decisions that show seniority:**
- **Core logic has no I/O and no global state** so it's unit-testable and reusable by CLI, SDK and provider. The CLI is a *thin* adapter. If your business logic lives in the command handlers, you've built a CLI that can't be a library.
- **Config precedence is explicit and documented**, with a `--debug`/`explain` mode that prints *where each value came from*. This one feature eliminates most support load.
- **Output formats**: `--output json|yaml|table`, with **stable, versioned JSON** (scripts parse it) and pretty tables for humans. Never make people scrape human output. Also: exit codes as a contract (0 success, 1 error, 2 usage, 3 auth…) — document them.
- **Idempotency and dry-run**: `--dry-run` showing a diff before applying (Terraform's core value proposition). For a mutating CLI this is what makes people trust it.
- **Errors are actionable**: not `error: 500` but `error: namespace "prod" not found in cluster X — did you mean "production"? (run `tool context list`)`. Error message quality is the #1 driver of adoption.
- **Auth**: token from env/keyring/SSO, never in flags (visible in `ps` and shell history), short-lived with refresh, and clear diagnostics when it fails.
- **Versioning & deprecation**: semver, a deprecation notice printed once per version with a removal date, and a compatibility promise. Breaking a CLI used by 200 engineers' scripts is an outage.
- **Progress & interactivity**:TTY detection — spinners/colours when interactive, silent machine-readable output when piped or in CI. Long operations need progress + cancel (Ctrl-C handled gracefully, cleaning up partial state).
- **Telemetry**: opt-out, anonymised, and *disclosed* — and use it to find which commands fail most.
- **Distribution**: single static binary or one-line install, checksums/signatures, auto-update with version pinning for CI (a surprise CLI update must not break a pipeline).
- **Testing**: golden-file tests for output, an end-to-end suite against a fake server, and **shell-completion tests**.

### 14. "Design a feature-flag service"
**Domain:** `Flag` (key, type: bool/variant/rollout, enabled, rules), `Rule` (targeting: attribute match, segment membership, percentage rollout), `Segment` (reusable cohort), `Evaluation` context (user/tenant attributes), `AuditEvent`.

**The critical architectural decision: server-side vs client-side evaluation.**
- **Server-side**: every evaluation calls the service. Always fresh, secrets stay server-side, targeting logic can be arbitrarily complex. Cost: a network hop in the hot path → the flag service becomes a **dependency of everything**, so its availability must exceed every consumer's. Mitigate with local caching, and decide behaviour when unreachable (**stale-serve with a max age, then fall back to a compiled-in default** — never crash).
- **Client-side (SDK evaluates locally from a downloaded rule set)**: microsecond evaluations, no runtime dependency. Cost: rules must be serialisable to the client (**so secrets and complex logic can't be used**), rule propagation is eventually consistent (a kill switch takes seconds-to-minutes to reach everyone — that's the dangerous part), and the payload grows with flag count.
- **My answer:** client-side for high-frequency/product flags with a signed, versioned rule bundle and a push channel (SSE/websocket) for urgent updates; server-side for security-sensitive decisions and complex targeting. **And a kill switch must never depend on the slow path** — that's a hard requirement I'd design for first.

**Other senior points:**
- **Evaluation must be deterministic and sticky**: hash `(flag_key, user_id, salt)` into the bucket, so a user doesn't flip between variants on every request. Salt per flag (or per experiment) so flags don't correlate — otherwise every "10% rollout" contains the same 10% of users, which biases every experiment.
- **Percentage rollouts need a stable denominator** and a way to ramp 1% → 5% → 25% → 100% without re-bucketing existing users.
- **Lifecycle is the real problem**: flags accumulate. Every flag needs an owner, an expiry date, and a removal task; you need a report of "flags older than 90 days" and a policy that expired flags fail loudly in CI. Flag debt turns into unreadable code with 40 branches.
- **Audit**: who changed what, when, and what did it do to traffic. Deploy-integration (a flag change is a change — it belongs on the dashboard annotations and in the change log).
- **Testing**: SDK must support forced-variant overrides for tests; a "flag state" API so CI can assert behaviour; and **contract tests** so a rule-schema change doesn't silently break old SDK versions.
- **Blast radius**: a bad flag value is an instant global outage. So: staged rollout of flag *changes*, validation on write (schema + sanity checks like "don't disable checkout"), and instant global revert.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Drawing classes before asking what the system must do | Wastes 10 minutes on the wrong model |
| Singleton for everything | Global state, untestable |
| `if/elif` chains that grow per new type | OCP violation you didn't notice |
| Read-check-write for concurrent allocation | The race they were testing for |
| LRU with no thread-safety discussion | Missed the actual question |
| Interfaces with one implementation and no plan for a second | Speculative generality — as bad as no abstraction |
| No mention of failure/timeout/idempotency in a queue or payment design | Not production-shaped |
| Naming 8 patterns without justifying any | Cargo cult |
| No testability story | "How would you test this?" is coming |
| Ignoring physical/digital divergence in the parking-lot/elevator problems | Missed the interesting part |

## Rapid recall

1. Clarify scope first: control system vs payment vs analytics are different designs.
2. LRU = HashMap + doubly-linked list (or `OrderedDict`); O(1). Shard for concurrency, and say what sharding costs.
3. `time.monotonic()` for durations, never wall clock.
4. Rate limit atomically (Lua/CAS); fail open vs closed is a **per-rule** decision.
5. Queues: at-least-once + idempotent tasks + visibility timeout > max runtime + DLQ + alert on oldest-message age.
6. Notification service: separate **channel** from **provider** → failover for free.
7. Inventory: conditional `UPDATE ... WHERE qty >= ?` is the oversell guard; reservations must expire.
8. Saga compensations can fail → reconciliation job + human queue.
9. FSM: make illegal states unrepresentable; safety invariants are enforced in hardware *and* asserted in software.
10. CLI: thin adapter over pure core; stable JSON output; documented exit codes; actionable errors; `--dry-run`.
11. Feature flags: deterministic sticky bucketing with per-flag salt; kill switch never on the slow path; flags expire or they become debt.
12. Say "how would you test this?" to yourself before they ask.

→ Next: [`05-Programming-Languages`](../05-Programming-Languages/README.md)
