# 01 · Fundamentals

What OpenTelemetry actually is, what it isn't, and the four structural facts that explain most of the confusion people have about it.

---

## 1.1 What OpenTelemetry is

**OpenTelemetry is a vendor-neutral standard, a set of SDKs, and a Collector for producing, collecting and exporting telemetry — traces, metrics, logs and (in alpha) profiles.**

It is **not**:
- a **backend** — it does not store, query, visualise or alert. That's Prometheus, Tempo, Jaeger, Datadog, Honeycomb.
- a **replacement for your logging framework** — it bridges your existing logger (see [`07-logs.md`](07-logs.md)).
- a **replacement for Prometheus** — it complements it. Prometheus won the metrics *data model and query language*; OTel won *instrumentation*. They meet at the Collector.
- an **APM product** — no dashboards, no anomaly detection, no service maps out of the box.

**The one-sentence value proposition:** instrument your code once, against a stable API, and send the output to whatever backend you have today *and* whatever backend you have in three years — without touching the application again.

### Why that's credible rather than aspirational
- **CNCF Graduated, 21 May 2026.** That tier required an independent security audit, a governance review and demonstrated production adoption at scale — the same bar Kubernetes and Prometheus cleared.
- **OTLP is the native ingestion format of essentially every vendor.** Datadog, Honeycomb, New Relic, Grafana Cloud, Splunk, Dynatrace, Elastic, AWS, Azure and GCP all accept OTLP. The "we might want to switch vendors" risk that OTLP addresses is now a live option rather than a theory.
- **Every major cloud has an OTel distribution**: AWS Distro for OpenTelemetry (2.x only since March 2026 — 1.x is unsupported), Azure Monitor OpenTelemetry Distro, Google Cloud OpenTelemetry operations.

---

## 1.2 The four structural facts

These explain nearly every "why is OTel confusing?" question.

### Fact 1 — The API and the SDK are separate packages, on purpose

| Layer | Package (Go/Python/Java/JS) | Who depends on it | What it does |
|---|---|---|---|
| **API** | `opentelemetry-api` | **Library and framework authors** | Defines `Tracer`, `Meter`, `Logger`, `Span`, `Counter`. Ships a **no-op implementation** by default |
| **SDK** | `opentelemetry-sdk` | **Application owners / operators** | Implements the API: sampling, span processors, aggregation, batching, export |
| **Exporter** | `opentelemetry-exporter-otlp` | Application owners | Serialises SDK output to OTLP and sends it |
| **Instrumentation** | `opentelemetry-instrumentation-<lib>` | Whoever enables it | Hooks into FastAPI/gRPC/JDBC/HTTPX and emits API calls |

**The consequence that matters:** a library can call `tracer.start_span(...)` and if the application never installs an SDK, that call is a **no-op costing nanoseconds**. This is why it is safe for library authors to instrument, and why "we instrumented 40 libraries and nothing changed" is the *correct* outcome when no SDK is configured.

**The debugging consequence:** *"I added spans and see nothing"* is almost always **no SDK registered**, or the SDK registered but no exporter configured. In Go this is the classic `otel.SetTracerProvider()` omission. In Java with the agent, it's `-javaagent` missing from the launch command.

### Fact 2 — Telemetry has a three-level nesting: Resource → Scope → Data

Every span, metric data point, log record and profile sits inside:

```
ResourceSpans / ResourceMetrics / ResourceLogs
└── Resource: {service.name, service.version, k8s.pod.name, host.name, deployment.environment.name, ...}
    └── ScopeSpans / ScopeMetrics / ScopeLogs
        └── InstrumentationScope: {name, version, schema_url, attributes}
            └── Span / Metric / LogRecord
                └── its own attributes
```

- **Resource** = *what produced this telemetry* — the service, the pod, the host, the environment. **Constant for the life of the process.** This is where `service.name` lives, and getting it right is the single highest-value thing in an OTel deployment.
- **InstrumentationScope** = *which library produced it* — e.g. `io.opentelemetry.spring-webmvc-6.0` version `2.31.0`. Lets you attribute telemetry to the instrumentation that made it, and to filter it.
- **Attributes** = the per-item detail.

**Why this nesting matters operationally:** the Resource is attached **once per batch**, not per span. That's what makes OTLP far more compact than a format where every record carries its own tags — and it's why cardinality explosions in *resource* attributes are so much more expensive than they look. See [`14-scale-cost-and-cardinality.md`](14-scale-cost-and-cardinality.md).

### Fact 3 — Configuration is converging on declarative files, and that changes behaviour

Historically: dozens of `OTEL_*` environment variables. **As of March 2026, declarative configuration is stable** (`opentelemetry-configuration` v1.0.0).

```bash
OTEL_CONFIG_FILE=/etc/otel/sdk-config.yaml     # the standard env var
OTEL_EXPERIMENTAL_CONFIG_FILE=...              # deprecated alias — still works
```

★ **The behaviour change that will bite you:** when `OTEL_CONFIG_FILE` is set, **all other `OTEL_*` environment variables are ignored** — except where the YAML file explicitly references them via `${env:VAR}` substitution. There is no merging, because there's no intuitive way to merge a flat env-var scheme into a structured tree.

```yaml
# otel-sdk-config.yaml — a single structured file replaces scattered env vars
file_format: "0.6"
resource:
  attributes:
    service.name: ${env:OTEL_SERVICE_NAME}      # ← explicit substitution still works
    deployment.environment.name: ${env:ENVIRONMENT}
tracer_provider:
  processors:
    - batch:
        exporter:
          otlp:
            protocol: grpc
            endpoint: ${env:OTEL_EXPORTER_OTLP_ENDPOINT}
```

Upstream ships two reference starting points: **`otel-sdk-config.yaml`** (plain) and **`otel-sdk-migration-config.yaml`** (with env-var substitution, for migrating off env vars). **Maturity varies by language: Java is furthest along, JavaScript next, Python and .NET still landing.** Validate against the published JSON schema in CI — that's the cheap win here.

### Fact 4 — There are several Collector distributions, and they are not the same

| Distribution | Contains | Use when |
|---|---|---|
| **`otelcol`** (core) | Only core components: `otlp`/`otlp_grpc`/`otlp_http` receivers & exporters, `batch`, `memory_limiter`, `debug`, `file`, `nop`, `forward` connector, `health_check`/`pprof`/`zpages` extensions | You only move OTLP → OTLP and want the smallest attack surface |
| **`otelcol-contrib`** | **108 receivers, 33 processors, 48 exporters, 13 connectors, 40 extensions, 9 providers** (counted from the v0.161.0 binary) | Almost always. This is what every tutorial assumes |
| **`otelcol-k8s`** | A curated Kubernetes-oriented subset of contrib | K8s deployments where you want smaller than contrib |
| **`otelcol-otlp`** | OTLP-only, minimal | Edge/gateway use |
| **Vendor distros** (ADOT, Azure Monitor, GCP) | contrib + vendor exporters + vendor defaults | You're committed to one cloud/vendor and want supported defaults |
| **Custom (OCB)** | Whatever you list in a builder manifest | You want a minimal, auditable binary. See [`15-security-and-governance.md`](15-security-and-governance.md) |

★ **Practical consequence:** if your config says `receivers: [hostmetrics]` and you run plain `otelcol`, you get *"unknown receiver"*. That's a distribution problem, not a config typo. **Always check which binary you're running.** In this folder every config is validated against `otelcol-contrib` v0.161.0.

Build your own with the **OpenTelemetry Collector Builder (OCB)**:
```bash
# builder-config.yaml lists exactly the components you want
ocb --config builder-config.yaml --output-path ./otelcol-custom
./otelcol-custom components        # confirm what's actually in your binary
```

---

## 1.3 The repository layout

OTel is ~40 repositories, not one. Knowing which is which saves a lot of searching.

| Repository | What lives there |
|---|---|
| `opentelemetry-specification` | The normative spec. Releases ~monthly (1.54.0 Feb 2026, 1.55.0 Mar, 1.56.0 Apr) |
| `opentelemetry-proto` | The protobuf definitions behind OTLP (v1.10.0, Mar 2026) |
| `semantic-conventions` | Attribute/metric naming standards (**v1.44.0**) |
| `opentelemetry-configuration` | The declarative config schema (**v1.0.0, stable Mar 2026**) |
| `opentelemetry-collector` | The Collector core, plus `pdata`, `confmap`, `consumer`, `exporterhelper` |
| `opentelemetry-collector-contrib` | Everything community-maintained — most components |
| `opentelemetry-collector-releases` | The release pipeline that produces `otelcol`, `otelcol-contrib`, `otelcol-k8s`, `otelcol-otlp` binaries and images |
| `opentelemetry-operator` | The Kubernetes Operator, **including the Target Allocator** (v0.158.0) |
| `opentelemetry-helm-charts` | `opentelemetry-collector`, `opentelemetry-operator`, `opentelemetry-target-allocator`, `opentelemetry-kube-stack` charts |
| `opentelemetry-{go,python,java,js,dotnet,ruby,php,rust,cpp,swift,erlang}` | Language SDKs |
| `opentelemetry-{lang}-instrumentation` | Auto/manual instrumentation per language |
| `opentelemetry-collector-builder` (`ocb`) | Custom distribution builder |
| **GenAI semantic conventions repo** | ★ As of semconv **v1.42.0**, all `gen_ai.*` moved here out of the main repo |

**Where the actual docs live:** `opentelemetry.io/docs` — and note that the component-level README in `opentelemetry-collector-contrib` at the *tag matching your version* is the authoritative source for that component's config schema. Blog posts are not.

---

## 1.4 Signals: what each one answers

| Signal | Question it answers | Stability (v0.161.0 / OTLP 1.11.0) | Cost driver |
|---|---|---|---|
| **Traces** | *Where did the time go in this one request?* | **Stable** everywhere | Span volume × attributes per span |
| **Metrics** | *How is the system doing over time? Is it trending badly?* | **Stable** everywhere | **Cardinality** (series count), not volume |
| **Logs** | *What exactly happened, in the system's own words?* | **Stable** in OTLP; SDK maturity varies by language | Volume + retention |
| **Profiles** | *Which function is burning the CPU/memory?* | **Development in OTLP; public alpha (Mar 2026); gated in the Collector** | Sample rate × duration |

★ **The asymmetry that trips people up:** traces and logs cost money proportional to **volume**; metrics cost money proportional to **distinct label combinations**. One noisy metric label (`user_id`, raw `url.path`) can cost more than a million spans. This is why [`14-scale-cost-and-cardinality.md`](14-scale-cost-and-cardinality.md) exists as its own file.

### Why the fourth signal matters
Metrics tell you CPU is at 90%. Traces tell you *which request* was slow. **Neither tells you which function is responsible.** Profiles answer that directly with continuously sampled stack traces.

The interesting property of OTel's implementation: **it's zero-code.** The whole-system eBPF profiler (donated by Elastic, now an official Collector component) samples stacks from the kernel across every process on a Linux host — no SDK changes, no redeploys. Details and honest caveats in [`08-profiles.md`](08-profiles.md).

---

## 1.5 OTLP: the wire protocol

**OTLP** (OpenTelemetry Protocol) defines the encoding, transport and delivery of telemetry between sources, intermediate nodes (Collectors) and backends. Spec version **1.11.0**.

| | OTLP/gRPC | OTLP/HTTP |
|---|---|---|
| Default port | **4317** | **4318** |
| Encoding | protobuf | protobuf (default) or JSON |
| Paths | service methods (`opentelemetry.proto.collector.trace.v1.TraceService/Export`) | `/v1/traces`, `/v1/metrics`, `/v1/logs`, and **`/v1development/profiles`** for profiles |
| Throughput | Higher (HTTP/2 multiplexing, persistent streams) | Slightly lower |
| Firewall/proxy friendliness | Worse — many L7 proxies, WAFs and service meshes mangle gRPC | **Much better.** This is why most vendor endpoints are HTTP |
| Load balancing | Needs an L7/gRPC-aware LB; an L4 LB pins one connection to one backend | Works with any HTTP LB |

**Which to choose:** gRPC between your own components inside a cluster (higher throughput, and you control the LB); **HTTP at the edge and to any vendor** (proxies, WAFs, ingress controllers and service meshes all handle it correctly). ★ If you're seeing intermittent gRPC failures through an ingress or mesh, switch to `otlp_http` before you debug the mesh.

### Things worth knowing about OTLP
- **Partial success is a first-class concept.** A backend can accept some data and reject some, responding with `partial_success` and `rejected_spans` / `rejected_data_points` / `rejected_log_records` / `rejected_profiles`. **SDKs and Collectors surface this as metrics** — if you're losing data silently, this is where you'd see it.
- **Retry semantics are specified.** 429 and 5xx are retryable; 400 (bad request) is not. The exponential backoff and jitter behaviour is in the spec, so every implementation agrees.
- **`OTel Arrow`** is an alternative high-throughput encoding — roughly **80% compression** for high-volume telemetry, with a receiver and exporter (`otelarrow`) in contrib. Worth evaluating at scale; not the default.
- **Profiles are explicitly marked development** in OTLP 1.11.0 and the HTTP path is literally `/v1development/profiles`. That naming is a deliberate signal: don't build a production dependency on it yet.

---

## 1.6 The standard environment variables (the ones you'll actually use)

Defaults below are from the stable environment-variable specification.

| Variable | Default | Notes |
|---|---|---|
| `OTEL_SERVICE_NAME` | `unknown_service` (+ process name) | **Set this. Always.** It takes precedence over `service.name` in `OTEL_RESOURCE_ATTRIBUTES` |
| `OTEL_RESOURCE_ATTRIBUTES` | — | Comma-separated `k=v` pairs added to the Resource |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | Base endpoint. gRPC wants `host:4317`; HTTP wants `http://host:4318`. **Mixing these up is the #1 "no data" cause** |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `protobuf` (HTTP) / gRPC | `grpc`, `http/protobuf`, `http/json` |
| `OTEL_EXPORTER_OTLP_HEADERS` | — | `k=v,k=v` — how vendor API keys get passed |
| `OTEL_PROPAGATORS` | **`tracecontext,baggage`** | Comma-separated, deduplicated |
| `OTEL_TRACES_SAMPLER` | **`parentbased_always_on`** | See [`10-sampling.md`](10-sampling.md) |
| `OTEL_TRACES_SAMPLER_ARG` | — | Only used if `OTEL_TRACES_SAMPLER` is set |
| `OTEL_SDK_DISABLED` | `false` | `true` → no-op SDK for all signals |
| `OTEL_LOG_LEVEL` | `info` | The SDK's *internal* logger, not your app's |
| `OTEL_ENTITIES` | — | **Newer:** entity information associated with the resource (Entities SDK) |
| `OTEL_CONFIG_FILE` | — | ★ When set, **all other `OTEL_*` vars are ignored** except via `${env:VAR}` in the file |

**Batch span processor defaults** (worth memorising — they explain a lot of latency and loss behaviour):

| Variable | Default |
|---|---|
| `OTEL_BSP_SCHEDULE_DELAY` | **5000 ms** |
| `OTEL_BSP_EXPORT_TIMEOUT` | **30000 ms** |
| `OTEL_BSP_MAX_QUEUE_SIZE` | **2048** |
| `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` | **512** |

★ **Consequence:** with defaults, a span can take up to 5 seconds to appear. If you're testing interactively and see nothing, **wait 5 seconds before you start debugging.** And `MAX_EXPORT_BATCH_SIZE` must be ≤ `MAX_QUEUE_SIZE` or the SDK rejects it.

Language-specific variables follow the convention `OTEL_{LANGUAGE}_{FEATURE}` — e.g. Python's `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED`. Note that when `OTEL_CONFIG_FILE` is set, these are bypassed too.

---

## 1.7 What "instrument once, export anywhere" actually buys you

A concrete cost comparison, because this is the argument you'll need to make internally.

**Vendor-agent world:**
- Instrument with vendor A's agent. Migrate to vendor B: re-instrument, or run a translation layer.
- Vendor A's agent version is coupled to vendor A's backend release cadence.
- Sampling policy, redaction and enrichment are configured in the vendor's UI — not in code review, not in Git.
- Two vendors (say, APM plus a log platform) means **two agents in the same process**, which is a real source of overhead and incompatibility.

**OTel world:**
- Instrument against the API. Switch backends by changing the Collector's exporter block — a config change, in Git, reviewed, reversible in one `git revert`.
- Sampling, redaction and enrichment move into the Collector: **infrastructure concerns, owned by the platform team, not embedded in application code.**
- One agent/SDK per language regardless of how many backends consume the data.
- You can **dual-ship during a migration** (see [`17-migration-and-adoption.md`](17-migration-and-adoption.md)) — send to the old vendor and the new one simultaneously from the Collector, compare, then cut over.

**The honest cost:**
- **You now operate the Collector.** It's a stateful-ish, critical-path component. If it OOMs or falls over, you lose telemetry — and during an incident, that's exactly when you need it. It needs resource limits, memory_limiter, HA, and its own monitoring.
- **You own the semantic conventions.** A vendor agent gives you a curated dashboard out of the box. With OTel you build the dashboards, and you must keep them working across semconv versions.
- **Signal maturity varies by language.** Tracing is solid nearly everywhere; metrics are stable in the major languages; **logging is the least mature**; **Go's Logs API+SDK only reached release candidate in v1.47.0-rc.1 (Aug 2026)**.
- **More moving parts to reason about.** "Why is this span missing?" now has four candidate answers (SDK sampler, span processor queue, Collector processor, backend retention) instead of one.

★ **The decision rule:** if you have more than one backend, more than one language, any compliance/PII requirement, or any expectation of changing vendors, the Collector pays for itself. If you have five services in one language going to one vendor and no plans to change, a vendor agent is legitimately less work — and saying so is the senior answer.

---

## 1.8 The five mistakes that cause 90% of "OTel isn't working"

1. **No SDK registered.** API calls are no-ops. Symptom: zero spans, zero errors, nothing in logs. Check: is there an explicit `TracerProvider`/`SdkTracerProvider` setup, or the agent/auto-instrumentation enabled?
2. **Wrong endpoint format.** `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` against a gRPC exporter, or `localhost:4317` (no scheme) against an HTTP exporter. gRPC = `host:4317`, HTTP = `http://host:4318`.
3. **`service.name` missing**, so everything lands as `unknown_service` and you can't find your data among everyone else's. Or worse: `service.name` is set per-developer-laptop so local data pollutes production dashboards.
4. **Propagator mismatch across services.** Service A sends W3C `traceparent`, service B expects B3 → the trace silently splits into two disconnected trees. See [`03-context-and-propagation.md`](03-context-and-propagation.md).
5. **Batching delay mistaken for data loss.** Default `OTEL_BSP_SCHEDULE_DELAY` is 5 s. People restart the app, check the backend, see nothing, and conclude it's broken.

Full decision tree in [`16-troubleshooting.md`](16-troubleshooting.md).

---

## Red flags

| Believing / saying this | Reality |
|---|---|
| "OpenTelemetry is our observability platform" | It's instrumentation + transport. You still need a backend, dashboards and alerting |
| "We'll just point the SDK at the vendor" | Works, but you lose sampling, redaction, cardinality control and fan-out. Fine for small; wrong at scale |
| "Adding OTel can't hurt performance" | It can — badly-configured batching, unbounded attributes, and high-cardinality metrics all hurt. It's cheap when configured, not cheap by nature |
| "Auto-instrumentation means we're done" | Auto gives you the framework layer. Business context (which tenant, which order, which step) needs manual spans |
| "Semconv is stable so names won't change" | **Only the parts marked stable.** V0→V1 migrations are happening now, via Collector feature gates. Pin and plan |
| "Profiles are ready" | **Public alpha, gated behind `service.profilesSupport`, SIG advises against critical production workloads** |
| "The old component names are fine" | They work today as deprecated aliases. `components` no longer lists them, and they will be removed |
| "Copy the config from that blog post" | If it's older than ~6 months it may use `logging:` (removed) or `protocol: spanmetrics:` (removed). **Validate it** |

---

## Rapid recall

1. **OTel = standard + SDKs + Collector.** Not a backend. Graduated CNCF **21 May 2026**.
2. **API vs SDK split is deliberate:** libraries depend on the API (no-op without an SDK); apps install the SDK. Explains both "safe to instrument" and "I added spans and see nothing".
3. **Nesting is Resource → Scope → Data.** Resource = the producer (constant per process, where `service.name` lives); Scope = the instrumentation library; attributes = per-item. Resource is attached once per batch — which is why resource-attribute cardinality is disproportionately expensive.
4. **Declarative config is stable (Mar 2026), `OTEL_CONFIG_FILE`.** ★ When set, **all other `OTEL_*` env vars are ignored** except `${env:VAR}` substitution. Java most mature, JS next.
5. **Distributions differ.** `otelcol` (core only) vs `otelcol-contrib` (108/33/48/13/40/9 components in v0.161.0) vs `otelcol-k8s` vs vendor distros vs OCB custom. "Unknown receiver" is often a distribution mismatch.
6. **Four signals, uneven maturity.** Traces/metrics/logs **stable** in OTLP 1.11.0; **profiles development/alpha** (HTTP path `/v1development/profiles`), Collector-gated behind `service.profilesSupport`.
7. **OTLP: gRPC :4317, HTTP :4318.** gRPC faster in-cluster; **HTTP through proxies, meshes, WAFs and to vendors**. Partial success + rejected counts are first-class — check them when data is missing.
8. **Defaults that explain behaviour:** propagators `tracecontext,baggage`; sampler `parentbased_always_on`; BSP delay **5 s**, timeout 30 s, queue 2048, batch 512.
9. **Cost asymmetry:** traces/logs scale with **volume**; metrics scale with **cardinality**. One bad label beats a million spans.
10. **v0.161.0 renames** to `lower_snake_case` (old names still alias); **`logging` exporter removed** (use `debug`); **`load_balancing.routing_key` is top-level** and `protocol:` accepts only `otlp`.

→ Next: [`02-architecture-and-data-model.md`](02-architecture-and-data-model.md)
