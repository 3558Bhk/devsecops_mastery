# 03 · Context & Propagation

The mechanism that turns "a bunch of spans" into "a trace". Also the mechanism behind the most silently damaging OTel failure there is: **a trace that splits into two disconnected trees and tells you nothing is wrong.**

---

## 3.1 What "context" actually is

**Context is a key-value map that travels with the execution of a request.** OTel uses it to carry:

| Context key | Carries |
|---|---|
| **Span context** | `trace_id`, `span_id`, `trace_flags` (sampled bit), `trace_state`, `is_remote` |
| **Baggage** | Arbitrary application key-value pairs that propagate downstream |
| The current `Span` | So `tracer.current_span()` works |

Two separate problems have to be solved, and conflating them is where confusion starts:

1. **In-process propagation** — how the context follows execution *within* one process, across function calls, goroutines, threads, async tasks and thread pools.
2. **Cross-process propagation** — how the context is *serialised into a wire format* and injected into a request, then extracted on the far side. This is what a **Propagator** does.

---

## 3.2 In-process propagation, per language

★ **This is the most common cause of broken parent-child relationships**, and it looks different in every language.

### Go — explicit context passing
```go
ctx := context.Background()
ctx, span := tracer.Start(ctx, "handle-checkout")   // span is stored IN ctx
defer span.End()

// child span: pass ctx, get correct parent automatically
ctx2, child := tracer.Start(ctx, "charge-card")
defer child.End()

// CRITICAL: cross a goroutine boundary by passing ctx explicitly
go func(ctx context.Context) {
    _, s := tracer.Start(ctx, "async-work")   // parent preserved
    defer s.End()
}(ctx)

// WRONG — this creates a NEW ROOT span:
go func() {
    _, s := tracer.Start(context.Background(), "async-work")
    defer s.End()
}()
```
**Rule:** `context.Context` is the carrier. If you drop it, you break the trace. Go has no ambient/thread-local context by design, so the discipline is visible and greppable — which is an advantage.

**Gotcha:** `context.WithoutCancel` / `context.WithoutDeadline` preserve values (including spans) while detaching cancellation — useful for background work triggered by a request that must not die with it. `context.Background()` throws the span away too.

### Java — implicit Context + the agent
```java
// With the javaagent, Context is stored in a thread-local and
// framework instrumentation moves it for you. Without it:
Context parent = Context.current();
Span span = tracer.spanBuilder("work").setParent(parent).startSpan();
try (Scope scope = span.makeCurrent()) {   // ★ makeCurrent() is what sets the thread-local
    doWork();
} finally {
    span.end();
}
```
★ **The Java trap is executors and thread pools.** A thread-local does not follow a `Runnable` onto a pool thread. Solutions, in order of preference:
1. **Use the javaagent** — it instruments `Executor`, `ExecutorService`, `CompletableFuture`, `ForkJoinPool`, Reactor, RxJava, Akka, Kotlin coroutines and `@Async` automatically. This is by far the best answer and the reason the agent exists.
2. `io.opentelemetry.context.Context.current().wrap(runnable)` — manual, per task.
3. Agent extension for executors not covered out of the box.

**If you see a Java service where spans are correctly parented inside a request but every `CompletableFuture`/`@Async` operation starts a new root trace, this is it.**

### Python — `contextvars`
```python
from opentelemetry import trace, context
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("handle") as span:
    do_work()                     # child spans nest automatically

# asyncio: contextvars are copied per-task automatically. Safe.
async def handler():
    with tracer.start_as_current_span("async-work"):  # correctly parented
        await something()

# threads: contextvars do NOT propagate automatically
from opentelemetry.context import attach, detach
ctx = context.get_current()
def worker():
    token = attach(ctx)           # ★ explicit attach required
    try:
        with tracer.start_as_current_span("threaded-work"):
            ...
    finally:
        detach(token)
threading.Thread(target=worker).start()
```
`ThreadPoolExecutor` and `run_in_executor` are the usual culprits. Python's auto-instrumentation covers many of them, but custom threading needs manual `attach`/`detach`.

### JavaScript/Node — `AsyncLocalStorage`
Node's `AsyncLocalStorage` (from `async_hooks`) carries context across `await` points and callbacks. The JS SDK sets it up for you.
```javascript
const span = tracer.startSpan('work', {}, context.active());
await context.with(trace.setSpan(context.active(), span), async () => {
  await doWork();          // nested spans parent correctly
});
span.end();
```
★ **The JS trap:** anything that escapes the async context — a raw `setTimeout` in old Node, an EventEmitter fired outside the async scope, a worker thread, or a native addon callback. Also **SDK 2.x requires Node `^18.19.0 || >=20.6.0`**; older runtimes don't have reliable `AsyncLocalStorage` behaviour.

### .NET — `Activity` + `AsyncLocal`
.NET's `System.Diagnostics.Activity` is the native carrier and OTel maps onto it. `async`/`await` flows automatically. The trap is `ThreadPool.QueueUserWorkItem` and fire-and-forget `Task.Run` in older patterns.

---

## 3.3 Cross-process propagation: Propagators

A **Propagator** serialises context into a carrier (HTTP headers, message properties, gRPC metadata) and deserialises it back.

```
   Service A                                          Service B
 ┌──────────────┐   inject(ctx, headers)   ┌──────────┐   extract(headers)  ┌──────────────┐
 │ SpanContext  │ ───────────────────────▶ │  wire    │ ─────────────────▶ │ SpanContext  │
 │ trace_id     │                          │  headers │                    │ is_remote=   │
 │ span_id      │                          │          │                    │   true       │
 │ trace_flags  │                          └──────────┘                    └──────────────┘
 └──────────────┘
```

### The propagators you'll meet

| Propagator | Header(s) | Status |
|---|---|---|
| **W3C Trace Context** | `traceparent`, `tracestate` | **The default and the standard.** Stable |
| **W3C Baggage** | `baggage` | Stable |
| **B3 (single)** | `b3: {traceId}-{spanId}-{sampled}-{parentSpanId}` | Widely used in Spring Cloud Sleuth / Zipkin / Istio ecosystems |
| **B3 (multi)** | `X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`, `X-B3-ParentSpanId`, `X-B3-Flags` | Legacy form of the above |
| **Jaeger** | `uber-trace-id`, `uberctx-*` | ★ **Deprecated in specification 1.54.0 (Feb 2026), and propagator implementations are now optional.** Migrate to W3C |
| **AWS X-Ray** | `X-Amzn-Trace-Id` | Needed when integrating with X-Ray / ALB request tracing |
| **OT Trace** | `ot-tracer-*` | Legacy OpenTracing |

**Defaults:** `OTEL_PROPAGATORS=tracecontext,baggage`. Comma-separated, and per spec the values **must be deduplicated** so a propagator is registered only once.

### The `traceparent` header, byte for byte

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             │  │                                │                │
        version   trace-id (32 hex = 16 bytes)    parent-id        trace-flags
                                                          (16 hex = 8 bytes)   (2 hex)
```

| Field | Rules |
|---|---|
| **version** | `00` today. **If version is `ff` it's invalid.** A version higher than what you understand means you must parse only the fields you know and ignore the rest — forward compatibility by design |
| **trace-id** | 16 bytes, lowercase hex, **must not be all zeros** |
| **parent-id / span-id** | 8 bytes, lowercase hex, **must not be all zeros** |
| **trace-flags** | Bit 0 (`01`) = **sampled**. Bit 1 (`02`) = **random trace ID**. Other bits reserved and must be passed through unchanged |

★ **The `random` flag (bit 1) matters more than people expect.** A trace ID that is *not* randomly generated (e.g. derived from a business key) breaks probabilistic sampling, because sampling decisions assume uniform distribution over the ID space. Setting this flag tells downstream samplers "don't treat this ID as random".

### `tracestate` — the vendor escape hatch

```
tracestate: rojo=00f067aa0ba902b7,congo=t61rcWkgMzE
```
- A list of `key=value` pairs, **opaque to OTel** — it's carried through unchanged so vendors can attach their own sampling decisions, priorities or routing hints.
- **Max 32 entries** per the W3C spec; implementations must drop or truncate beyond that.
- **Order matters to vendors**: the leftmost entry is from the most recent upstream participant.
- ★ **In the Collector, `tracestate` handling is behind a feature gate:** `processor.tailsamplingprocessor.usetracestate` is **disabled by default** in v0.161.0. So `tail_sampling` ignores `tracestate` unless you enable it. The processor README has a dedicated "Tracestate handling" section — worth reading if you rely on vendor priority hints surviving your Collector.

---

## 3.4 The failure that costs the most: propagator mismatch ★

**Scenario:** Service A (Java, agent default) → Service B (Go, explicitly configured with B3 because a Zipkin-based tracing system came first).

- A injects `traceparent: 00-<trace1>-<spanA>-01`.
- B's propagator is B3-only, so it **ignores** `traceparent`.
- B starts a **new root span** with a fresh `trace_id`.
- A's trace shows a CLIENT span to B that never returns a child. B's trace shows a complete, healthy-looking trace of its own.

**Nothing errors. Nothing warns. Both traces look fine in isolation.** You have two half-traces and a service map with a missing edge.

**How to detect it:**
1. **Service map has a gap** between two services that definitely talk.
2. Query the backend for A's span: it has a CLIENT span with a duration but **no child SERVER span** in the same trace.
3. Query B's spans: they have `parent_span_id` empty (root spans) at a rate far higher than legitimate entry points would produce. **A service where 90% of spans are root spans is either an entry point or has broken propagation.**
4. Check the raw request headers — `curl -v` the call and look at what's actually being sent.

**How to fix it:**
- **Standardise on W3C Trace Context everywhere.** It's the default in every SDK and the only one you should be choosing in 2026.
- During a migration, configure **multiple propagators** so both formats are injected and either can be extracted:
  ```bash
  OTEL_PROPAGATORS=tracecontext,baggage,b3
  ```
  ★ Note the asymmetry: **injection typically uses the first/primary propagator, extraction tries all of them.** So listing `tracecontext` first means you send `traceparent` but can still *receive* `b3`. Verify the behaviour in your specific SDK — this is one of the places implementations genuinely differ.
- **Service meshes help and hurt.** Istio/Linkerd propagate B3 *and* W3C at the mesh layer, but **only for traffic that goes through the proxy**. If your app makes a connection the sidecar doesn't intercept (a raw TCP socket, a connection pool established before the sidecar, `localhost` traffic), propagation is yours to handle.
- **Watch for header stripping.** Some ingress controllers, WAFs, API gateways and CDN configurations drop unknown headers. `traceparent` is now on most allowlists, but `tracestate` and `baggage` sometimes aren't. If traces break only when crossing the public edge, check the proxy config.

---

## 3.5 Baggage — propagating application context

**Baggage carries your own key-value pairs downstream**, not just trace identity.

```
baggage: userId=alice,tenantId=acme,region=eu-west-1
```

```python
# Python
from opentelemetry import baggage, context
ctx = baggage.set_baggage("tenant.id", "acme")
context.attach(ctx)

# downstream, any service can read it
tenant = baggage.get_baggage("tenant.id")
```
```java
// Java
Context ctx = Baggage.current().toBuilder()
    .put("tenant.id", "acme").build().storeInContext(Context.current());
try (Scope s = ctx.makeCurrent()) { /* calls downstream carry it */ }
```

**What baggage is genuinely good for:**
- **Multi-tenant attribution** without threading a tenant ID through every function signature.
- **Routing / canary decisions** downstream ("this request is in the beta cohort").
- **Debug flags** — set `debug=true` for one user session and have every downstream service log verbosely. **This is one of the most useful and least-used OTel features.**
- Feeding attributes into spans and logs at every hop automatically (via the Collector's `transform` processor reading `baggage["tenant.id"]`).

**What baggage is dangerous for** ★ — read this before using it:

| Risk | Why |
|---|---|
| **Security: it crosses trust boundaries** | Baggage is sent to *every* downstream service, including third parties. **Never put secrets, tokens, PII, or anything a customer shouldn't see.** A `userId` sent to your payment processor's analytics is a data-sharing decision you probably didn't make deliberately |
| **Header size** | Every hop pays for it in bytes. Large baggage inflates every request. Some proxies reject headers over 8 KB |
| **It's mutable by anyone** | A malicious or buggy downstream can rewrite it. Treat baggage as **untrusted input** on the receiving side — validate before using it in an authorisation decision. **Never make a security decision based on baggage** |
| **Silent cardinality** | If a Collector processor copies `baggage["request.id"]` onto every span, you've just created unbounded attribute cardinality |
| **Not automatically on your spans** | Setting baggage doesn't add it to spans. You need explicit code, or a Collector processor, to materialise it |

**Rule of thumb:** baggage is for **low-cardinality, non-sensitive, cross-cutting context**. Tenant ID: yes. Session ID: usually. User email: never. Request ID: only if you understand the cardinality cost.

---

## 3.6 Propagation across asynchronous boundaries

Synchronous HTTP is easy. These cases are where traces break.

### Message queues
The pattern is **PRODUCER span → link/child → CONSUMER span**.

| | Behaviour |
|---|---|
| **Inject at send** | Producer instrumentation calls `inject(ctx, message_headers)` |
| **Extract at receive** | Consumer instrumentation calls `extract(headers)` and creates a CONSUMER span |
| **The parent/link choice** | Per semconv, a consumer processing **one** message typically creates a span **linked** to the producer span rather than parented, because the causal relationship isn't a call stack. Batch consumers link to *many* producers |

★ **Where it breaks:** the carrier isn't HTTP headers — it's message properties/attributes. Every broker has its own mechanism:
- **Kafka**: message headers (`traceparent` as a header). Works well.
- **SQS**: message attributes. **SQS attribute names have restrictions** and there's a size limit; some SDKs base64-encode.
- **RabbitMQ**: basic properties headers.
- **Pub/Sub**: message attributes.
- **Redis Streams / List**: you have to do it yourself — serialise `traceparent` into the payload.

**If your queue client isn't instrumented, propagation stops at the queue** and every consumer span is a root. Check the instrumentation coverage list for your specific library before assuming it works.

**Batch consumption** is genuinely hard: one consumer span processing 50 messages from 50 different traces. **Use links** (one per source trace) — that's exactly what they're for. Backends render links differently; some don't render them at all, which is a real limitation when you're trying to trace a batch job backwards.

### Scheduled jobs / cron
No inbound request, so there's nothing to extract. The job is legitimately a **root trace**. What you should do:
- Start a root span named after the job (`nightly-reconciliation`), so all its work is one trace.
- Add a **`link`** to any triggering entity if there is one.
- Emit the schedule/correlation ID as an attribute.
★ **A cron job that produces 10,000 spans in one trace will hit span limits and backend per-trace limits.** Chunk the work: one root span per batch, linked to a job-level span. See [`05-traces.md`](05-traces.md) on span limits.

### Server-sent streams, WebSockets, gRPC streaming
One connection, many logical requests. The connection-level span is long-lived and not useful for per-request tracing. Instrument **per message**, and link each message span to the connection span.

### Database and cache calls
These are CLIENT spans from your service to the datastore. Propagation *into* the database generally doesn't happen (the DB doesn't run OTel) — **except** semconv now defines **context propagation via SQL comment injection** (added in semconv v1.39.0: `db: Add context propagation via SQL commenter`). That embeds the trace context in a SQL comment so the database's own logs and slow-query log can be correlated back to the trace. **Powerful for diagnosing "which request caused this slow query" — and a mild information-disclosure consideration**, since the comment travels to the DB and appears in its logs.

---

## 3.7 Propagation through the Collector

The Collector doesn't just pass context through — it can be where propagation gets fixed or broken.

| Mechanism | Effect on context |
|---|---|
| **`otlp` receiver** | Preserves `trace_id`/`span_id`/`tracestate`/`trace_flags` exactly |
| **`transform` / `attributes` processors** | Can read `trace_id`, `span_id`, `trace_state` and rewrite attributes based on them; can also **drop** attributes |
| **`probabilistic_sampler` processor** | Re-decides sampling and **rewrites `trace_flags`**. ★ If you sample at the SDK *and* at the Collector you get compounded sampling — see [`10-sampling.md`](10-sampling.md) |
| **`tail_sampling` processor** | Decides after the fact; sets `tracestate` entries when `processor.tailsamplingprocessor.usetracestate` is enabled, and can `recordpolicy` to note which policy kept the trace (both gates off by default) |
| **`load_balancing` exporter** | Routes by `traceID` by default, so all spans of a trace reach the same backend instance — **essential for tail sampling to work across a Collector fleet** |
| **`groupbytrace` processor** | Buffers spans to assemble whole traces before dispatch. Use with `load_balancing` when the backend list changes frequently and routing stability matters |
| **`jaeger`/`zipkin` receivers** | **Translate** B3/Jaeger headers into OTLP context. This is how you ingest legacy producers |
| **`zipkin` exporter** | Translates back out. Useful during a migration |

---

## 3.8 Verifying propagation works — a practical checklist

```bash
# 1. Is the header actually being sent? (the single most useful check)
curl -sv http://service-a/call-b 2>&1 | grep -iE 'traceparent|tracestate|baggage|b3|uber-trace'

# 2. Is the receiving service extracting it? Look for is_remote in debug output,
#    or just check whether the child span shares the trace_id.

# 3. Do the two services agree on trace_id?
#    Query your backend for the trace_id from step 1's response headers and
#    confirm BOTH services' spans appear in it.

# 4. Root-span ratio per service (the aggregate check)
#    In PromQL against span metrics, or in your trace backend:
#      count(spans where parent_span_id is empty) / count(all spans)
#    A non-entry-point service with a high ratio has broken propagation.

# 5. Collector side: is anything stripping it?
otelcol-contrib print-config --config=/etc/otel/config.yaml | grep -A5 -iE 'attributes|transform|filter'
```

**The `traceparent` echo trick:** if you control the edge, return the received `traceparent` in a response header. Then a single `curl` tells you both what was sent and what was received, and you can paste the trace ID straight into your UI.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Dropping `ctx` when crossing a goroutine/thread/task boundary | New root span; the trace silently splits |
| Java executors without the agent or `Context.wrap()` | Every async operation starts a new trace |
| Python `ThreadPoolExecutor` without `attach`/`detach` | Same |
| Mixing W3C and B3 across services | Two half-traces, no error, missing service-map edge |
| Keeping the Jaeger propagator because "it works" | **Deprecated in spec 1.54.0**; implementations are now optional and will disappear |
| All-zero trace/span IDs | Rejected by the spec and silently dropped |
| Deriving trace IDs from business keys | Breaks probabilistic sampling's uniformity assumption. Set the `random` trace-flag bit honestly |
| Putting secrets or PII in baggage | It crosses every trust boundary downstream, including third parties |
| Making an authorisation decision from baggage | Anyone downstream can rewrite it. Untrusted input |
| Copying high-cardinality baggage onto spans | Attribute cardinality explosion at every hop |
| Assuming the mesh propagates for you | Only for traffic the sidecar intercepts; connection pools and `localhost` bypass it |
| Not checking header stripping at the ingress/WAF/CDN | Traces break only at the public edge — the hardest case to diagnose |
| Parenting batch-consumer spans to one producer | Wrong causal model. Use **links** |
| One giant span for a 10,000-item cron job | Hits span limits and backend per-trace limits; chunk and link |
| Sampling at both the SDK and the Collector without thinking | Compounded sampling; your "10%" is 1% |

---

## Rapid recall

1. **Two distinct problems:** in-process propagation (context following execution — language-specific discipline) and cross-process propagation (serialisation into headers — **Propagators**).
2. **In-process, per language:** Go = pass `ctx` explicitly (drop it → new root). Java = thread-local, **breaks on executors** unless the agent instruments them or you `Context.wrap()`. Python = `contextvars`, auto for asyncio, **manual `attach`/`detach` for threads**. Node = `AsyncLocalStorage`, requires **Node ^18.19.0 || >=20.6.0** on SDK 2.x. .NET = `Activity`/`AsyncLocal`.
3. **Default propagators:** `tracecontext,baggage`. **Jaeger propagator deprecated in spec 1.54.0 (Feb 2026)** — migrate to W3C.
4. **`traceparent: version-traceid-parentid-flags`** — version `00` (`ff` invalid; higher versions must be parsed leniently), 32-hex trace ID and 16-hex span ID that **must not be all zeros**, flags bit 0 = sampled, **bit 1 = random trace ID** (matters because non-random IDs break probabilistic sampling).
5. **`tracestate`** is an opaque vendor list, max 32 entries, leftmost = most recent. ★ The Collector's `tail_sampling` **ignores it by default** — `processor.tailsamplingprocessor.usetracestate` is off in v0.161.0.
6. **Propagator mismatch is the worst failure mode:** no error, no warning, two half-traces. **Detect via root-span ratio** — a non-entry-point service with mostly root spans is broken. **Fix by standardising on W3C**, or list multiple propagators during migration (injection typically uses the first, extraction tries all — **verify per SDK**).
7. **Baggage: low-cardinality, non-sensitive, cross-cutting only.** It crosses every trust boundary, is mutable by anyone (untrusted input — never an authz decision), costs bytes at every hop, and is *not* automatically on your spans. Best use: **a `debug=true` flag for one user session.**
8. **Async boundaries:** queues need the context in *message properties*, not headers — Kafka headers work well, SQS/Pub-Sub have their own restrictions, Redis Streams is DIY. **Batch consumers should use links, not parenting.** Cron jobs are legitimate roots; chunk large ones.
9. **SQL comment propagation** (semconv v1.39.0) can carry trace context into database logs — powerful for "which request caused this slow query", with a mild disclosure caveat.
10. **Collector-side context handling:** `probabilistic_sampler` **rewrites `trace_flags`**; `load_balancing` routes by `traceID` (required for fleet-wide tail sampling); `groupbytrace` assembles whole traces for routing stability; `jaeger`/`zipkin` receivers translate legacy formats in.
11. **First diagnostic command, always:** `curl -sv` and grep for `traceparent`. If the header isn't on the wire, nothing downstream can work.

→ Next: [`04-semantic-conventions.md`](04-semantic-conventions.md)
