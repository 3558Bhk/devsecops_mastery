# 09 · SDKs & Instrumentation

How telemetry actually gets produced: the instrumentation taxonomy, the per-language reality, and — as of July 2026 — the arrival of **zero-code instrumentation for Go**, which removes the last big language gap.

Verified versions: **Java v1.66.0** (agent **2.31.x**), **Python 1.44.0/0.65b0**, **Go v1.47.0-rc.1**, **JS 2.9.0** (experimental 0.220.0).

---

## 9.1 The instrumentation taxonomy

Four distinct things get called "instrumentation", and conflating them causes bad decisions.

| Type | Code changes | Deploy needed | Coverage | Control | Examples |
|---|---|---|---|---|---|
| **Zero-code / auto** | **None** | Restart only | Frameworks + libraries the agent knows | Low | Java agent, `opentelemetry-instrument` (Python), `@opentelemetry/auto-instrumentations-node`, **Go compile-time (v1)**, .NET CLR profiler, **eBPF (`obi`)** |
| **Code-based auto** | Add a dependency + init block | Yes | Same libraries, explicit setup | Medium | Go SDK + `otelhttp`/`otelgrpc` handlers |
| **Manual** | Explicit `start_span` calls | Yes | **Your business logic** | **Full** | Any language |
| **Library instrumentation** | Done by the library author | No (upgrade) | The library itself | n/a | A DB driver that ships OTel support |

★ **These are complements, not alternatives.** The correct answer is nearly always **auto for the framework layer + manual for the business layer.** Auto gives you HTTP/gRPC/DB/messaging spans for free; it cannot know that the slow part was "resolving pricing for a backordered item across three suppliers". That's manual, and it's the part that makes traces useful.

**The maturity ordering matters for planning:**

| Language | Traces | Metrics | Logs | Zero-code |
|---|---|---|---|---|
| **Java** | Stable | Stable | Stable | **Excellent** — agent 2.31.x |
| **Python** | Stable | Stable | Stable | **Excellent** — `opentelemetry-instrument` |
| **.NET** | Stable | Stable | Stable | Good — CLR profiler + `AddOpenTelemetry()` |
| **Node/JS** | Stable (SDK 2.x) | Stable | ★ `api-logs` **unstable track** | Good — but requires Node `^18.19.0 \|\| >=20.6.0` |
| **Go** | Stable | Stable | ★ **Release candidate (v1.47.0-rc.1, Aug 2026)** | ★ **v1 as of July 2026** — new |
| Ruby / PHP | Stable | Varies | Varies | Moderate |
| Rust / C++ / Swift / Erlang | Varies | Varies | Early | Limited |

---

## 9.2 Java — the reference implementation

**Versions:** `opentelemetry-java` **v1.66.0** (Sept 2026), `opentelemetry-java-contrib` **v1.55.0**, `opentelemetry-java-instrumentation` (the agent) **2.31.x** on a monthly cadence.

### The agent (zero-code) — use this
```bash
# Download once, mount everywhere
curl -L -O https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar

java -javaagent:/opt/opentelemetry-javaagent.jar \
     -Dotel.service.name=checkout-api \
     -Dotel.exporter.otlp.endpoint=http://otel-collector:4317 \
     -Dotel.resource.attributes=deployment.environment.name=production \
     -jar app.jar
```
```dockerfile
# The container pattern: an init container or a bundled agent jar
FROM eclipse-temurin:21-jre
COPY --from=otel-agent /otel-javaagent.jar /opt/opentelemetry-javaagent.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/opentelemetry-javaagent.jar"
ENV OTEL_SERVICE_NAME=checkout-api
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
```

**What the agent covers** (a partial list — it's very broad): Servlet, Spring Web/WebMVC/WebFlux, Spring Boot, Spring Scheduling, gRPC, JDBC + all major drivers, HikariCP, Hibernate, JPA, Kafka, RabbitMQ, Pulsar, SQS/SNS, Elasticsearch, Redis (Jedis/Lettuce/Redisson), MongoDB, Cassandra, HTTP clients (Apache, OkHttp, JDK), Netty, Undertow, Jetty, Tomcat, Logback, Log4j2, JUL, Jackson, Reactor, RxJava, Kotlin coroutines, `CompletableFuture`, `ExecutorService`, Micrometer bridge, Vert.x, Akka, Quartz, and AWS SDK v1/v2.

★ **The `ExecutorService`/`CompletableFuture`/Reactor instrumentation is the single most valuable thing the agent does that you cannot easily replicate manually.** It solves the thread-pool context-propagation problem ([`03-context-and-propagation.md`](03-context-and-propagation.md)) — the cause of most "my async work starts a new trace" bugs.

### Configuration precedence
1. `-D` system properties
2. `OTEL_*` environment variables
3. `otel.javaagent.configuration-file` properties file
4. Agent defaults

```bash
# Common agent-specific properties
-Dotel.instrumentation.common.default-enabled=false      # start from nothing, enable selectively
-Dotel.instrumentation.jdbc.enabled=false                # disable one instrumentation
-Dotel.javaagent.exclude-classes=com.example.internal.*  # ★ avoid instrumenting your own internals
-Dotel.instrumentation.micrometer.enabled=true           # bridge existing Micrometer metrics
-Dotel.javaagent.extensions=/opt/otel-extension.jar      # custom instrumentation
```
★ **`exclude-classes` matters more than people expect.** The agent instruments by bytecode transformation; on a large application it can transform thousands of classes, adding startup time and occasional conflicts. Excluding your own packages and known-problematic ones is standard hygiene.

**Startup cost:** the agent typically adds **1–5 seconds** of startup and a few tens of MB of heap. For a service with a 30-second startup this is noise; for a scale-from-zero Lambda-like workload it's material. Measure yours.

### Manual instrumentation alongside the agent
```java
private static final Tracer tracer =
    GlobalOpenTelemetry.getTracer("com.example.checkout", "1.4.2");

Span span = tracer.spanBuilder("order.validate-stock").startSpan();
try (Scope scope = span.makeCurrent()) {          // ★ makeCurrent() sets the thread-local
    span.setAttribute("order.items.count", items.size());
    boolean backorder = check(items);
    span.setAttribute("order.requires_backorder", backorder);
    if (backorder) span.addEvent("backorder.required",
        Attributes.of(AttributeKey.stringKey("supplier.id"), supplierId));
} catch (Exception e) {
    span.recordException(e);                       // ★ both of these, always
    span.setStatus(StatusCode.ERROR, e.getMessage());
    throw e;
} finally {
    span.end();                                    // ★ end() in finally, not in the try
}
```
★ **`try (Scope scope = span.makeCurrent())`** — the try-with-resources is what guarantees the thread-local is restored. Omitting it leaks context across pooled threads and produces **spans parented to the wrong request**, which is far harder to diagnose than missing spans.

### The Micrometer bridge
If you have existing Micrometer metrics, `otel.instrumentation.micrometer.enabled=true` routes them into OTel — **no rewrite**. This is the pragmatic migration path for a large Spring estate and one of the best-kept features in the agent.

---

## 9.3 Go — and the compile-time instrumentation milestone ★

**Versions:** `opentelemetry-go` **v1.47.0-rc.1** (Aug 2026). Traces and metrics **stable**; **Logs API+SDK promoted to release candidate** — the final stage before stable v1 guarantees, but **not stable yet**.

### The historical problem
Java, Python, Node and .NET have all had zero-code instrumentation for years: attach an agent, telemetry flows. **Go was the exception**, because a Go program compiles to a single static binary with no bytecode layer to hook and no runtime to attach to. So Go instrumentation meant **code changes in every service** — wrapping every handler, every client, every DB call. That's the reason Go shops adopted OTel more slowly, and it was a real cost.

### The fix: OpenTelemetry Go Compile-Time Instrumentation — **v1, July 2026**
Instead of runtime bytecode manipulation, instrumentation is applied **at build time**. The toolchain rewrites your package during compilation to insert OTel calls around supported functions — so you get agent-like coverage **without editing your source**.

**Practical shape:**
```bash
# Instrument at build time — your source is unchanged
go build -toolexec="otelgo-instrumentation -config ./otel.yaml" ./cmd/server

# The produced binary emits telemetry per the config, driven by standard OTEL_* env vars
OTEL_SERVICE_NAME=checkout-api \
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
./server
```

**What this changes for a Go platform:**
| Before | After |
|---|---|
| Every team wraps handlers/clients manually | Build-flag change in the shared Dockerfile/CI template |
| Coverage varies by team diligence | **Uniform across every Go service** |
| Onboarding a service takes days | Onboarding is a build argument |
| Instrumentation drifts from the framework versions | Tied to the build, so it's versioned and reproducible |

★ **This is arguably the most practically significant OTel release of 2026 for Go-heavy organisations** — bigger than any single feature — because it removes the per-team adoption cost that blocked Go estates from standardising.

**Caveats to check for your stack:**
- **Build-time tooling affects your build pipeline**: CI images need the tool, build times increase, and `-toolexec` interacts with build caching and other toolexec users (e.g. some coverage or codegen tools).
- **Coverage depends on supported libraries** — check that yours are on the list before promising anyone uniform coverage.
- **Debugging an instrumented binary differs from debugging source** — line numbers and stack frames can shift. Worth a trial before you mandate it.
- **Version coupling**: the instrumentation tool, the OTel Go SDK and your framework versions must be compatible. Pin all three.

### Manual / code-based instrumentation in Go
```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/propagation"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/otel/sdk/resource"
    semconv "go.opentelemetry.io/otel/semconv/v1.34.0"
)

func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
    exporter, err := otlptracegrpc.New(ctx)          // reads OTEL_EXPORTER_OTLP_* env vars
    if err != nil { return nil, err }

    res, err := resource.New(ctx,
        resource.WithFromEnv(),                       // OTEL_RESOURCE_ATTRIBUTES / OTEL_SERVICE_NAME
        resource.WithTelemetrySDK(),
        resource.WithHost(),
        resource.WithContainer(),
        resource.WithAttributes(
            semconv.DeploymentEnvironmentName("production"),
        ),
    )
    if err != nil { return nil, err }

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter,
            sdktrace.WithBatchTimeout(5*time.Second),
            sdktrace.WithMaxQueueSize(4096),          // ★ raise from 2048 at high span rates
        ),
        sdktrace.WithResource(res),
        sdktrace.WithSampler(sdktrace.ParentBased(
            sdktrace.TraceIDRatioBased(0.1),
        )),
    )
    otel.SetTracerProvider(tp)                        // ★ ★ THE LINE PEOPLE FORGET
    otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
        propagation.TraceContext{},
        propagation.Baggage{},
    ))
    return tp, nil
}
```
★ **`otel.SetTracerProvider(tp)` is the single most-missed line in Go OTel setup.** Without it, `otel.Tracer(...)` returns a provider backed by the **no-op** implementation, and every span you create is discarded — silently, with no error. Symptom: correct code, zero telemetry, nothing in the logs.

**HTTP server and client:**
```go
// server
mux := http.NewServeMux()
mux.HandleFunc("/checkout", handleCheckout)
handler := otelhttp.NewHandler(mux, "http-server")
http.ListenAndServe(":8080", handler)

// client — ★ you must instrument the client too, or the trace stops at your service boundary
client := &http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport)}
req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)   // ★ WithContext, or no propagation
resp, err := client.Do(req)
```

**gRPC:**
```go
// server
grpc.NewServer(grpc.StatsHandler(otelgrpc.NewStatsHandler()))
// client — ★ the API moved from interceptors to a StatsHandler; older examples are wrong
conn, _ := grpc.NewClient(addr, grpc.WithStatsHandler(otelgrpc.NewStatsHandler()))
```
★ **The gRPC interceptor→StatsHandler migration is a genuine breaking change** that invalidated a large fraction of Go OTel tutorials. If your gRPC spans vanished after an upgrade, this is why.

**Go-specific gotchas:**
| Gotcha | Fix |
|---|---|
| `context.Background()` in a goroutine | Pass the parent `ctx` explicitly — Go has no ambient context |
| `slog.Info` instead of `slog.InfoContext` | No trace correlation in logs. **The #1 Go logs bug** |
| Semconv package version drift | Go's `semconv/vX.Y.Z` is **path-versioned** — multiple versions can coexist. Check which one your instrumentation uses |
| Forgetting `defer span.End()` on an early-return path | Spans never export. Use `defer` immediately after `Start` |
| Not calling `tp.Shutdown(ctx)` at exit | ★ Buffered spans are lost on graceful shutdown. **Register a signal handler and shut down the provider** |
| `GOMEMLIMIT`/`GOMAXPROCS` not set in containers | Unrelated to OTel but changes what your profiles and metrics mean |

```go
// The shutdown pattern people forget — loses buffered spans without it
sigCh := make(chan os.Signal, 1)
signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
<-sigCh
ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
defer cancel()
if err := tp.Shutdown(ctx); err != nil { log.Printf("tracer shutdown: %v", err) }
```

---

## 9.4 Python

**Version:** `opentelemetry-api`/`-sdk` **1.44.0**, `opentelemetry-semantic-conventions` **0.65b0** (★ note the `b0` beta track).

### Zero-code — the recommended default
```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install        # ★ detects your installed libraries and installs matching instrumentation

export OTEL_SERVICE_NAME=checkout-api
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
export OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
opentelemetry-instrument python app.py     # wraps your process; no code changes
```
```dockerfile
# Container: the same thing via env vars
ENV PYTHONPATH=/otel-auto-instrumentation
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp
```
★ **`opentelemetry-bootstrap -a install` is the step people skip**, and then wonder why FastAPI produces no spans. It reads your installed packages and installs the corresponding `opentelemetry-instrumentation-*` packages. Without it you have the SDK and no instrumentation.

**Coverage:** FastAPI, Flask, Django, aiohttp, httpx, requests, urllib3, gRPC, SQLAlchemy, psycopg2/psycopg3, asyncpg, PyMySQL, redis, pymongo, motor, boto3/botocore, kafka-python, confluent-kafka, pika, celery, threading, asyncio, logging, and more.

### Manual
```python
from opentelemetry import trace
from opentelemetry.trace import StatusCode

tracer = trace.get_tracer("checkout", "1.4.2")

with tracer.start_as_current_span("order.validate-stock") as span:
    span.set_attribute("order.items.count", len(items))
    try:
        result = validate(items)
        span.set_attribute("order.requires_backorder", result.backorder)
    except StockUnavailable as exc:
        span.record_exception(exc)                 # ★ both
        span.set_status(StatusCode.ERROR, str(exc))
        raise
    span.add_event("stock.reserved", {"sku": sku, "qty": qty})
```

**Python-specific gotchas:**
| Gotcha | Fix |
|---|---|
| `contextvars` don't cross threads | `attach(ctx)` / `detach(token)` explicitly, or rely on instrumentation that does it |
| Gunicorn/uWSGI worker forking | **Fork after configuring the SDK, or re-initialise in `post_fork`.** A provider created pre-fork is shared across workers and produces corrupt data |
| ★ Gunicorn `post_fork` | The classic fix: `def post_fork(server, worker): init_telemetry()` |
| Async generators and `run_in_executor` | Verify propagation; some need explicit context copying |
| `OTEL_PYTHON_*` variables | Language-specific; ★ **bypassed entirely when `OTEL_CONFIG_FILE` is set** |
| Log correlation | `%(otelTraceID)s` format codes, or the `LoggingHandler` bridge |

★ **The Gunicorn pre-fork problem deserves emphasis** because it fails *silently and partially*: some spans export, some don't, and duplicate/inconsistent resource attributes appear. If you run Gunicorn with `--preload` and configure OTel at import time, you have this bug. Configure **after** the fork.

---

## 9.5 JavaScript / Node

**Version:** SDK **2.9.0**, experimental packages **0.220.0**, `semconv/v1.43.0`.

★ **SDK 2.x is a major version with real breaking changes:**
- Minimum Node: **`^18.19.0 || >=20.6.0`** (Node 14 and 16 dropped)
- Minimum TypeScript: **5.0.4**
- Compile target: **ES2022** (was ES2017)
- Public interface changed — classes and namespaces removed for better minification and tree-shaking
- Stable packages are `>=2.0.0`; unstable packages are `>=0.200.0`
- ★ **The `api` and `semantic-conventions` packages are NOT part of the 2.x major** — they version independently

```javascript
// instrumentation.js — loaded BEFORE anything else
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-grpc');
const { Resource } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: new Resource({ [ATTR_SERVICE_NAME]: 'checkout-api' }),
  traceExporter: new OTLPTraceExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    exportIntervalMillis: 15000,
  }),
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-fs': { enabled: false },   // ★ noisy; usually disable
  })],
});
sdk.start();
process.on('SIGTERM', () => sdk.shutdown().finally(() => process.exit(0)));  // ★ flush
```
```bash
node --require ./instrumentation.js app.js
# or
NODE_OPTIONS="--require ./instrumentation.js" node app.js
```

★ **Two Node specifics that bite:**
1. **`--require ./instrumentation.js` must load before your application code.** If your app imports `http` before the instrumentation patches it, that module is never instrumented. This is the #1 "Node OTel produces no spans" cause.
2. **The `fs` instrumentation is extremely noisy** — it instruments every filesystem call. Disable it unless you specifically need it. Same for some `http` client instrumentation on chatty internal calls.

**Coverage:** Express, Fastify, Koa, Nest, Hapi, Restify, `http`/`https`, gRPC, GraphQL, Apollo, TypeORM, Sequelize, Prisma, Mongoose, ioredis, `pg`, `mysql2`, KafkaJS, amqplib, SQS, Pino, Winston, Bunyan, `node-fetch`, axios, undici.

**Browser/RUM:** client-side instrumentation is maturing but ★ **historically the weakest area of OTel**, and the project itself names it as an active area of work. `@opentelemetry/instrumentation-document-load`, `-user-interaction`, `-fetch`, `-xml-http-request` exist. Treat browser telemetry as less mature than server telemetry.

---

## 9.6 .NET

```csharp
using OpenTelemetry;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r
        .AddService("checkout-api", serviceVersion: "1.4.2")
        .AddAttributes(new Dictionary<string, object>
            { ["deployment.environment.name"] = builder.Environment.EnvironmentName }))
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddSqlClientInstrumentation()
        .AddOtlpExporter())
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddProcessInstrumentation()
        .AddOtlpExporter())
    .WithLogging(l => l.AddOtlpExporter());
```
- .NET's `System.Diagnostics.Activity` is the native carrier; OTel maps onto it, so `async`/`await` flows automatically.
- ★ **.NET 9/10 runtime support is part of the eBPF profiler's coverage** — so profiles are viable for .NET without SDK changes once the ecosystem lands.
- Zero-code via the CLR profiler exists; `AddOpenTelemetry()` is the more common path.
- Declarative configuration support is still landing.

---

## 9.7 The eBPF zero-code path: `obi` ★

Contrib v0.161.0 ships an **`obi` receiver** — eBPF-based auto-instrumentation that observes your processes from the kernel and produces spans and metrics **with no code changes, no restarts, and no language support matrix**.

| Property | Value |
|---|---|
| Code changes | **None** |
| Restart | **Not required** |
| Language coverage | Whatever speaks HTTP/gRPC/SQL/Redis/Kafka on the wire |
| Depth | **Protocol-level only** — no in-process spans, no business context, no custom attributes |
| Deployment | Privileged DaemonSet |
| Best for | **Uninstrumentable workloads**: legacy binaries, third-party software, polyglot estates nobody will instrument, and getting *baseline* coverage on day one |

★ **The honest positioning:** `obi` gives you **service maps and protocol-level latency for everything, immediately** — which is genuinely valuable for discovery and for legacy systems. It gives you **nothing** about your business logic. Use it as a floor, not a ceiling: deploy it for estate-wide visibility, then instrument properly where it matters.

Same underlying technique as the profiles signal ([`08-profiles.md`](08-profiles.md)). **Zero-code eBPF collection is the most consequential direction in OTel** because it attacks the real adoption blocker: *"we have 200 services and nobody will instrument them."*

---

## 9.8 Choosing an approach — the decision table

| Situation | Recommendation |
|---|---|
| New Java/Spring service | **Agent.** Zero code, best coverage, solves executor propagation |
| New Python service | **`opentelemetry-instrument` + `bootstrap`.** Then manual spans for business logic |
| New Go service, 2026 | ★ **Compile-time instrumentation** for uniform coverage + manual `otel` calls for business spans. Verify your libraries are supported and trial the build impact first |
| New Node service | `NodeSDK` + `--require` + auto-instrumentations, **with `fs` disabled** |
| Existing estate of 50 services, nobody will edit code | **`obi` (eBPF) for baseline coverage**, then agent-based for the top 10 by traffic |
| A library you maintain, used by others | Instrument it with the **API only** — no-op without an SDK, zero cost to consumers |
| Need business-level spans | **Manual, always.** No auto tool can know your domain |
| Migrating from Micrometer (Java) | **Micrometer bridge** — no rewrite |
| Migrating from a vendor agent | Dual-ship from the Collector during the cutover ([`17-migration-and-adoption.md`](17-migration-and-adoption.md)) |
| Logs in Go | ★ **`slog`/`zap` → structured JSON → Collector `file_log`.** Don't depend on the RC Logs SDK |

---

## 9.9 Testing instrumentation — the part everyone skips

Instrumentation is code. It breaks silently. Test it.

```yaml
# CI: assert telemetry shape, not just that the app runs
# 1. Run the app against a Collector with a `debug` exporter at verbosity: detailed
# 2. Assert:
#    - service.name is set and correct
#    - spans exist for the expected operations
#    - span names contain no IDs  (grep for /\d+/ in http route spans)
#    - required attributes are present
#    - no dropped-span counters are non-zero
#    - the trace is connected (no unexpected root spans)
```

**Practical checks:**
```bash
# Is the SDK exporting at all? Point at a local Collector with a debug exporter
docker run -p 4317:4317 -v $PWD/config.yaml:/etc/otelcol-contrib/config.yaml \
  otel/opentelemetry-collector-contrib:0.161.0

# Validate your Collector config before you blame the SDK
otelcol-contrib validate --config=config.yaml

# See exactly what config the Collector resolved (defaults included)
otelcol-contrib print-config --config=config.yaml

# Check what components your distribution actually has
otelcol-contrib components | grep -A3 'name: otlp'

# Send a test span without an application
curl -X POST -H "Content-Type: application/json" \
  -d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"smoke-test"}}]},"scopeSpans":[{"spans":[{"traceId":"5b8efff798038103d269b633813fc60c","spanId":"eee19b7ec3c1b174","name":"test-span","kind":2,"startTimeUnixNano":"1726000000000000000","endTimeUnixNano":"1726000001000000000"}]}]}]}' \
  http://localhost:4318/v1/traces
```
★ **That last `curl` is the single most useful OTel debugging command.** It bypasses your application, your SDK, your instrumentation and your config — and tests only the transport and the Collector. If it works and your app doesn't, the problem is in your application. If it fails, the problem is in the pipeline. **It halves the search space in ten seconds.**

**Also worth adding:**
- **A `telemetry.sdk.*` and semconv version inventory** across services, so you know who's behind. Query the resource attributes.
- **An alert on `service.name == "unknown_service"`** — catches services that shipped without configuration.
- **A CI check that no dependency bump changes your semconv package version** without review ([`04-semantic-conventions.md`](04-semantic-conventions.md)).
- **The JetBrains OpenTelemetry plugin** — as of 2026.2 it's available in IntelliJ IDEA, GoLand, PyCharm and WebStorm (previously Rider only). Useful for exploring trace data during development.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Auto-instrumentation only, no manual spans | You get HTTP hops and no business context — traces that show *where* but never *why* |
| Manual instrumentation of framework layers | Wasted effort; the agent does it better and keeps up with versions |
| Forgetting `otel.SetTracerProvider()` in Go | **Silent no-op.** Zero telemetry, zero errors |
| Not calling `tp.Shutdown()` on exit | Buffered spans lost on every deploy |
| `try` without `Scope`/`makeCurrent()` in Java | Context leaks across pooled threads → **spans parented to the wrong request** |
| Skipping `opentelemetry-bootstrap` in Python | SDK installed, no instrumentation, no spans |
| Configuring the Python SDK before Gunicorn forks | Silent partial data loss. Use `post_fork` |
| Loading Node instrumentation after the app imports `http` | That module is never patched. `--require` must come first |
| Leaving `fs` instrumentation on in Node | Enormous noise and overhead |
| Using old Go gRPC interceptor examples | **The API moved to `StatsHandler`**; interceptors are gone |
| Depending on Go's Logs SDK for anything critical | ★ **Release candidate, not stable.** Use `slog` → JSON → `file_log` |
| Not excluding classes from the Java agent | Slower startup, occasional bytecode conflicts |
| Treating `obi`/eBPF as a replacement for instrumentation | Protocol-level only. No business context, ever |
| Never testing instrumentation in CI | It breaks silently, usually during a dependency upgrade |
| Letting a dependency bump the semconv package | Attribute names change with no code change from you |
| No alert on `unknown_service` | Unconfigured services pollute production dashboards undetected |

---

## Rapid recall

1. **Four kinds of instrumentation: zero-code, code-based-auto, manual, and library.** ★ **Auto for the framework layer + manual for the business layer is the right answer nearly always** — they're complements. Auto can't know your domain.
2. **Maturity:** Java/Python/.NET strongest across all signals. **Node's `api-logs` is on the unstable track** and needs **Node ^18.19.0 || >=20.6.0**. **Go's Logs SDK is release candidate (v1.47.0-rc.1, Aug 2026), not stable.**
3. **Java:** use the **agent (2.31.x)** — `-javaagent:`, and its single greatest value is instrumenting **executors, `CompletableFuture`, Reactor and coroutines**, which solves thread-pool context propagation. `try (Scope s = span.makeCurrent())` is mandatory. **Micrometer bridge** avoids a metrics rewrite. Use `exclude-classes`.
4. ★ **Go: compile-time instrumentation reached v1 in July 2026** — `go build -toolexec="otelgo-instrumentation ..."`. Zero source changes, uniform coverage across a Go estate, onboarding becomes a build argument. **The most practically significant Go OTel development in years.** Caveats: build pipeline impact, library coverage, version coupling.
5. **Go's classic failures:** missing **`otel.SetTracerProvider()`** (silent no-op), missing **`tp.Shutdown()`** (lost buffered spans), `context.Background()` in a goroutine (new root), **gRPC interceptors → StatsHandler** (old tutorials are wrong), `slog.Info` instead of `InfoContext` (no log correlation).
6. **Python:** `opentelemetry-bootstrap -a install` (**skipping it is the #1 "no spans" cause**) + `opentelemetry-instrument`. ★ **Gunicorn pre-fork is a silent partial-failure bug — configure in `post_fork`.** `OTEL_PYTHON_*` vars are **bypassed when `OTEL_CONFIG_FILE` is set**.
7. **Node:** `--require ./instrumentation.js` must load **before** app code; **disable `fs` instrumentation**; SDK 2.x dropped Node 14/16, needs TS 5.0.4, targets ES2022, and **`api`/`semantic-conventions` are not part of the 2.x major**. Browser/RUM remains OTel's weakest area.
8. ★ **`obi` (eBPF receiver, in contrib v0.161.0): zero code, zero restart, protocol-level only.** The right *floor* for an estate nobody will instrument and for legacy binaries — never a ceiling. Same technique as the profiles signal.
9. **Test instrumentation in CI**: `debug` exporter at `detailed`, assert `service.name`, no IDs in span names, required attributes present, zero dropped-span counters, connected traces.
10. ★ **The most useful OTel debugging command is a `curl` POST of a hand-built `resourceSpans` JSON to `:4318/v1/traces`.** It bypasses app, SDK and instrumentation and tests only transport + Collector — **halving the search space in ten seconds.**
11. **`otelcol-contrib validate` / `print-config` / `components` / `featuregate`** are the four Collector subcommands worth memorising (there is **no `run`** — you just pass `--config=`).
12. **Alert on `service.name == "unknown_service"`** and keep an inventory of `telemetry.sdk.version` and semconv versions across services.

→ Next: [`10-sampling.md`](10-sampling.md)
