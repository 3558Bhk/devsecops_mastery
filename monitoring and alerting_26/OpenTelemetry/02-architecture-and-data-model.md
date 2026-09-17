# 02 · Architecture & Data Model

The shape of the data, end to end. Knowing this model precisely is what lets you answer "where did my span go?" in four steps instead of forty — because every stage of the pipeline is either preserving, transforming or dropping a well-defined object.

---

## 2.1 The end-to-end path of one span

```
 your code: tracer.start("checkout")
      │
      ▼
 ┌─ API ────────────────────────────────────────────────┐
 │ Span interface. If no SDK registered → NoOpSpan,      │
 │ all calls discarded, ~zero cost.                      │
 └──────────────────────┬───────────────────────────────┘
                        ▼
 ┌─ SDK: Sampler ───────────────────────────────────────┐
 │ DECIDES AT CREATION (head sampling). If DROP →        │
 │ returns a non-recording span; attributes are no-ops.  │
 └──────────────────────┬───────────────────────────────┘
                        ▼
 ┌─ SDK: Span (recording) ──────────────────────────────┐
 │ Accumulates attributes, events, links, status in      │
 │ memory. Bounded by span limits (see 05).              │
 └──────────────────────┬───────────────────────────────┘
              span.end() │
                        ▼
 ┌─ SDK: SpanProcessor ─────────────────────────────────┐
 │ SimpleSpanProcessor  → export immediately (dev only)  │
 │ BatchSpanProcessor   → ring buffer, flush on          │
 │   size(512) / time(5s) / shutdown                     │
 │   ★ Queue full (2048) → span DROPPED, counted in      │
 │     otelcol/sdk spans-dropped metric                  │
 └──────────────────────┬───────────────────────────────┘
                        ▼
 ┌─ SDK: Exporter (OTLP) ───────────────────────────────┐
 │ Wraps into ResourceSpans{Resource, ScopeSpans{Scope,  │
 │   []Span}}, serialises to protobuf, sends.            │
 │ Retry on 429/5xx with backoff+jitter. Timeout 30s.    │
 └──────────────────────┬───────────────────────────────┘
                        │ OTLP/gRPC :4317 or OTLP/HTTP :4318
                        ▼
 ┌─ Collector (optional) ───────────────────────────────┐
 │ otlp receiver → [processors] → exporter               │
 │ Each processor can mutate, enrich, filter, sample,    │
 │ redact. Each exporter has its own queue + retry.      │
 └──────────────────────┬───────────────────────────────┘
                        ▼
 ┌─ Backend ────────────────────────────────────────────┐
 │ Ingest → index → store → query. Retention, sampling,  │
 │ and cardinality limits live here too.                 │
 └──────────────────────────────────────────────────────┘
```

★ **Count the places your span can be dropped:** the sampler, the processor queue, the exporter's retry exhaustion, the Collector's `memory_limiter`, any `filter`/`tail_sampling` processor, the `load_balancing` exporter's sub-queues, the backend's rate limit, and the backend's retention. **Eight independent drop points.** That's why "no data" debugging is a decision tree, not a guess — and why you need drop metrics at each stage ([`16-troubleshooting.md`](16-troubleshooting.md)).

---

## 2.2 Resource

**The Resource describes the entity producing telemetry.** It's resolved once at SDK startup, then attached to every batch.

### Standard resource attributes (semconv v1.44.0)

| Attribute | Example | Why it matters |
|---|---|---|
| **`service.name`** | `checkout-api` | **The primary key of observability.** Every dashboard, alert and service map groups on it |
| `service.version` | `1.4.2` | Lets you split error rate by version — the basis of canary analysis |
| `service.namespace` / `service.instance.id` | `payments` / `pod-abc123` | Groups related services; identifies a single process |
| **`deployment.environment.name`** | `production` | ★ **Renamed from `deployment.environment`** in the V0→V1 semconv migration. Old name still seen everywhere |
| `telemetry.sdk.{name,version,language}` | `opentelemetry` / `1.66.0` / `java` | Auto-added; useful for finding un-upgraded services |
| `host.{name,id}`, `os.{type,version}`, `process.{pid,executable.name,runtime.*}` | | Host-level correlation |
| `k8s.{namespace.name,pod.name,deployment.name,node.name,container.name,cluster.name}` | | ★ Core Kubernetes + container-registry attributes **graduated to stable in semconv v1.43.0** |
| `cloud.{provider,account.id,region,availability_zone,platform}` | `aws` / `eu-west-1a` | Multi-account and multi-region attribution |
| `container.{id,name,image.name,image.tag}` | | |
| `server.{address,port}` / `client.{address,port}` | | Network peer identification |

### Resource detectors

Detectors populate resource attributes automatically. Enable them explicitly — **the default set varies by language, and the most useful ones are usually off by default.**

| Detector | Source | Availability |
|---|---|---|
| `env` | `OTEL_RESOURCE_ATTRIBUTES` | Always — **and it should win over everything else** |
| `system` / `host` | Hostname, OS, CPU, memory | All platforms |
| `process` | PID, executable, runtime | All platforms |
| `container` | cgroup/`/proc/self/mountinfo` | Containers |
| `docker` | Docker socket metadata | Containers |
| **`eks` / `ecs` / `ec2` / `elastic_beanstalk`** | Instance metadata service | AWS |
| **`gke` / `gce` / `cloud_run`** | GCP metadata | GCP |
| **`azure_vm` / `azure_app_service` / `aks`** | Azure IMDS | Azure |
| **`k8s` / `k8snode`** | Kubernetes API + downward API | Any K8s |

★ **Detector ordering and `override` matter.** In the Collector's `resource_detection` processor:
```yaml
processors:
  resource_detection:
    detectors: [env, system, docker, ec2, eks]   # order = precedence for `override: true`
    timeout: 5s          # detectors can hang on an unreachable metadata service — always set this
    override: false      # false = do NOT overwrite attributes the SDK already set (usually what you want)
```
- **Always put `env` first** so explicit config wins.
- **Always set `timeout`.** The EC2/ECS/GCP/Azure detectors call a metadata endpoint; if that endpoint is unreachable (common in non-cloud or restricted networks) the detector can block startup. A 5 s timeout turns a hang into a warning.
- **`override: false` by default.** With `true`, the detector clobbers what your application set — which is how `service.name` mysteriously becomes the container ID.

In Kubernetes, prefer the **`k8sattributes` processor** over resource detectors for pod metadata — it watches the API server and enriches by pod IP, which detectors inside the pod can't reliably do (they can't see the Deployment name or the pod's labels).

### Entities (newer concept)

Recent specification work adds **Entities** — a first-class notion of the things your telemetry describes (a service, a host, a container, a database), with identity and relationships, rather than just a flat attribute bag. There's an `OTEL_ENTITIES` environment variable and an Entities SDK. **Practical status: emerging.** Worth knowing it exists, because it's the direction resource modelling is heading and it's what makes "entity-centric" observability UIs possible. Don't build on it yet.

---

## 2.3 InstrumentationScope

Each Scope carries:

| Field | Purpose |
|---|---|
| `name` | Usually the instrumentation library's package name — `io.opentelemetry.spring-webmvc-6.0`, `opentelemetry.fastapi.0.25.0` |
| `version` | The **instrumentation** version, not your app's |
| `schema_url` | **The semconv version this data was emitted against** — e.g. `https://opentelemetry.io/schemas/1.34.0` |
| `attributes` | Scope-level attributes (rare, but available) |

★ **`schema_url` is the mechanism that makes semconv migration survivable.** It tells the consumer *which version of the naming conventions* produced this data, so a backend or a Collector `transform`/`schema` processor can translate old names to new ones on the way in. When you see a query that works for some services and not others, `schema_url` is usually why — they were instrumented against different semconv versions. See [`04-semantic-conventions.md`](04-semantic-conventions.md).

**Practical uses of Scope:**
- **Filter out noisy instrumentation**: drop spans where `scope.name == "opentelemetry.instrumentation.urllib3"` if that library generates 10× your traffic.
- **Attribute cost**: which instrumentation library is generating the most spans? That's a Scope-level aggregation.
- **Version drift detection**: alert when two versions of the same instrumentation library are in production.

---

## 2.4 The Span data model

```protobuf
message Span {
  bytes trace_id = 1;        // 16 bytes, 128-bit. Must be non-zero
  bytes span_id = 2;         // 8 bytes, 64-bit. Must be non-zero
  string trace_state = 3;    // W3C tracestate — vendor-specific k=v list, opaque passthrough
  bytes parent_span_id = 4;  // empty for a root span
  fixed32 flags = 16;        // trace flags (sampled bit) + random trace id flag
  string name = 5;           // ★ LOW CARDINALITY. "GET /users/:id", never "GET /users/12345"
  SpanKind kind = 6;         // INTERNAL | SERVER | CLIENT | PRODUCER | CONSUMER
  fixed64 start_time_unix_nano = 7;
  fixed64 end_time_unix_nano = 8;
  repeated KeyValue attributes = 9;      // bounded (default 128)
  repeated Event events = 10;            // timestamped annotations inside the span
  repeated Link links = 11;              // links to OTHER traces (batch parents, etc.)
  Status status = 12;                    // UNSET | OK | ERROR (+ message)
}
```

### Span kinds — and why backends care

| Kind | Meaning | Who sets it |
|---|---|---|
| **SERVER** | Handling an inbound request. The span's duration covers the whole server-side handling | Server framework instrumentation |
| **CLIENT** | Making an outbound call. Duration includes network time | Client library instrumentation |
| **PRODUCER** | Sending an async message. **Short** — just the send | Messaging instrumentation |
| **CONSUMER** | Processing a received message. May start long after the producer ended | Messaging instrumentation |
| **INTERNAL** | Everything else — in-process work | Your manual instrumentation |

★ **The two things SpanKind is used for:**
1. **Service maps.** A CLIENT span in service A pointing at a SERVER span in service B is how every service-graph is drawn. Get the kinds wrong and your service map is wrong.
2. **Latency attribution.** `SERVER.duration` is *your* latency; `CLIENT.duration` is *your dependency's* latency plus the network. **The difference between them is network + serialization time** — a genuinely useful derived metric, and the only way to separate "we're slow" from "our dependency is slow".

**PRODUCER/CONSUMER asymmetry:** the consumer span may start minutes or hours after the producer span ends. That's why messaging traces use **links** and why trace-based latency SLOs need care across async boundaries.

### Events, Links, Status

- **Events** are timestamped annotations *inside* a span: `{name, time_unix_nano, attributes}`. Exceptions are conventionally recorded as an event named `exception` with `exception.type`, `exception.message`, `exception.stacktrace`, `exception.escaped`, `exception.thread.name`. ★ **Stacktraces are large.** A span limit or a redaction rule on `exception.stacktrace` is often necessary — see [`14-scale-cost-and-cardinality.md`](14-scale-cost-and-cardinality.md).
- **Links** connect a span to spans in *other* traces. The canonical use is a batch job: one processing span links to the N originating request traces. Also used for fan-in/fan-out and for retries.
- **Status**: `UNSET` is the default and means "no explicit signal" — **not** success. `OK` means explicitly successful (and per spec should be used sparingly, mainly to override an earlier error). `ERROR` means the operation failed. ★ **Backends differ:** many treat `UNSET` as success for error-rate calculations, which is correct in practice but worth knowing when your error rate looks suspiciously clean.

### Trace and Span IDs
- **trace_id: 16 bytes**, **span_id: 8 bytes**, both must be non-zero (all-zero is invalid and gets dropped).
- **64-bit trace IDs are supported for legacy compatibility** (Zipkin/Jaeger origins) by left-padding to 128 bits. There's a feature gate in the Datadog receiver (`receiver.datadogreceiver.Enable128BitTraceID`) dealing with exactly this.
- IDs are random, which is what makes **probabilistic sampling by trace ID** work uniformly.

---

## 2.5 The Metric data model ★

This is the most subtle part of OTel and the source of most metric-related surprises.

### The three-level structure

```
Metric
├── name              "http.server.request.duration"
├── description
├── unit              "s"          ← REQUIRED by convention; Prometheus needs it for suffixing
└── data (ONE of):
    ├── Gauge
    ├── Sum                    → monotonic: true|false, aggregation_temporality
    ├── Histogram              → aggregation_temporality
    ├── ExponentialHistogram   → aggregation_temporality
    └── Summary                → legacy, for Prometheus/OpenMetrics ingestion only
```

Each data type contains **data points**, and each data point carries: `attributes`, `start_time_unix_nano`, `time_unix_nano`, `value`/`bucket counts`, plus optional **exemplars**.

### The instrument types

| Instrument | Sync/Async | Monotonic | Use for | Prometheus equivalent |
|---|---|---|---|---|
| **Counter** | Sync | **Yes** | Things that only increase: requests, errors, bytes | `_total` counter |
| **UpDownCounter** | Sync | No | Things that go both ways: queue depth, active connections, cache size | gauge (but you do the arithmetic) |
| **Histogram** | Sync | — | Distributions: latency, request size, response size | `_bucket`/`_sum`/`_count` |
| **Gauge** | Sync | No | A value at a moment, not aggregated: temperature, current CPU | gauge |
| **ObservableCounter** | **Async** | Yes | Read a monotonic value on callback: total bytes read from a file | counter you scrape |
| **ObservableUpDownCounter** | **Async** | No | Read a fluctuating value on callback: open FDs, goroutines | gauge you scrape |
| **ObservableGauge** | **Async** | No | Read an instantaneous value on callback: memory usage, disk free | gauge you scrape |

### Sync vs Async — the distinction that determines correctness

- **Sync instruments** are called from your code path. The SDK **aggregates** them: two `counter.add(1)` calls in one interval become one data point with value 2.
- **Async instruments** are called by the SDK on a **collection interval** (default 60 s) via a callback you register. The SDK **reads** the current value.

★ **The trap:** if you use an **async** instrument to report something that changes faster than the collection interval, you get aliasing — you'll miss spikes entirely. A queue that empties and refills between scrapes looks flat. **Use sync instruments for events; async for state.**

★ **The second trap:** async callbacks run **in the SDK's collection thread**. A callback that blocks on I/O, takes a lock, or queries a database stalls the whole metric collection and can push the export past its deadline. Callbacks must be cheap and non-blocking — read a cached value, don't compute one.

### Aggregation temporality — the single most important OTel metrics concept

**Temporality describes whether a reported value is "since the beginning of time" or "since the last report."**

| | **Cumulative** | **Delta** |
|---|---|---|
| Semantics | Value since process start | Value since the last export |
| What the backend sees | A monotonically increasing series | A per-interval increment |
| Query pattern | `rate(x[5m])` — take the derivative | `sum_over_time(x[5m])` — just add them up |
| Who prefers it | **Prometheus** (it's the native model) | **Datadog, CloudWatch, most commercial APMs**, and anything behind a load balancer |
| Restart behaviour | Counter resets to 0 → Prometheus `rate()` handles it correctly | No reset artefact at all |
| Missing-data behaviour | **Robust.** If you miss one scrape, the next value still contains all history | **Fragile.** A dropped delta export loses that interval permanently |
| Collector/SDK cost | Needs to remember the start time and the accumulated value **per stream** | Lower memory, but needs the interval boundaries to align |

**Defaults:** the OTel spec default is **cumulative**. But:
- The `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` env var / SDK config sets `cumulative`, `delta`, or `lowmemory`.
- The Collector's `prometheus` exporter (for scraping) **produces cumulative**, because that's what Prometheus is.
- The Collector's `prometheusremotewrite` / `prometheus_remote_write` exporter **requires cumulative** — if you feed it delta data, you get wrong numbers silently or an error. There's a `cumulative_to_delta` and a **`delta_to_cumulative`** processor to convert.

★ **The failure mode that costs people days:** a service exports **delta** to a Collector that remote-writes to **Prometheus**. Prometheus sees values that jump around instead of increasing, `rate()` produces garbage or nothing, and everyone concludes OTel metrics are broken. **Diagnosis is one query:** plot the raw series. If it's monotonically increasing with resets at restarts, it's cumulative. If it oscillates around a small positive value, it's delta.

★ **`start_time_unix_nano` is how you detect it programmatically.** In cumulative temporality, `start_time` stays fixed (process start) while `time` advances. In delta, `start_time` advances with each interval to equal the previous `time`. The Collector's `delta_to_cumulative` processor reconstructs the running total by tracking streams — and it **must see every delta** for a stream, which is exactly why you need the `load_balancing` exporter with `routing_key: streamID` or `metric` when running more than one Collector instance. Split deltas across instances and the reconstruction is wrong.

### Exponential histograms ★

Two histogram types exist:

| | **Explicit-bucket Histogram** | **Exponential Histogram** |
|---|---|---|
| Buckets | Fixed boundaries you define (`[1ms, 5ms, 10ms, ..., 10s]`) | Auto-scaled powers of a base, computed at runtime |
| Configuration | You must guess the range in advance | You set a `max_scale` and `max_size`; it adapts |
| Accuracy | Poor outside your chosen range; quantile error at bucket edges | **Bounded relative error**, uniform across magnitudes |
| Series cost | One series per bucket (20 buckets = 20 series per stream) | Scales with the observed range, often fewer |
| Prometheus support | **Native** | Not native — converted on export |
| Use when | You need Prometheus compatibility, or you know your distribution | You don't know the range, or the range is wide (1 ms to 30 s) |

**Why explicit buckets are a problem:** if your latency distribution is bimodal (mostly 5 ms, some 5 s) and your buckets are `[10ms, 50ms, 100ms, 500ms, 1s]`, the p99 computed from those buckets is a **guess interpolated within the 1s+ bucket** — potentially wildly wrong. Exponential histograms don't have this problem.

**Practical recommendation:** use **explicit buckets matching your SLO thresholds** if you're targeting Prometheus (you need the buckets to compute PromQL quantiles and to alert on "fraction of requests over 500 ms"); use **exponential histograms** when the range is unknown or very wide, and accept the conversion step at the backend.

### Summary (the legacy type)

`Summary` exists in the OTLP data model **only for ingesting pre-aggregated quantiles from Prometheus/OpenMetrics**. It carries already-computed quantiles, which means:
- **You cannot re-aggregate them.** Averaging p99s across instances is mathematically meaningless — and that's exactly what a Summary forces you to do.
- **You cannot change the quantile set later.**

★ **Rule: never emit a Summary from your own instrumentation.** Use a Histogram (or ExponentialHistogram) and let the backend compute quantiles from the buckets. If you see Summaries in your pipeline, they came in through a Prometheus receiver scraping an existing `/metrics` endpoint — which is legitimate and expected during migration.

### Views

Views let you **reconfigure how an instrument is aggregated** without changing the code that emits it:

- rename a metric, change its description or unit
- change the aggregation (Histogram → explicit buckets you choose, or → ExponentialHistogram)
- **filter attribute keys** — the primary cardinality control at the SDK level
- set explicit bucket boundaries

```
# Conceptually (declarative config):
views:
  - instrument: {name: "http.server.request.duration"}
    stream:
      aggregation:
        type: explicit_bucket_histogram
        options: {boundaries: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]}
      attribute_keys:            # ← ALLOWLIST: everything else is dropped
        included: [http.request.method, http.route, http.response.status_code, url.scheme]
```
★ **`attribute_keys.included` is the highest-leverage cardinality control in the whole SDK.** An allowlist means a new attribute added by an instrumentation upgrade **cannot** silently explode your series count. Prefer allowlists over denylists for anything exported to a metrics backend.

---

## 2.6 The Log Record data model

```protobuf
message LogRecord {
  fixed64 time_unix_nano = 1;          // when the event occurred
  fixed64 observed_time_unix_nano = 11;// when the SDK saw it (matters for file tailing)
  SeverityNumber severity_number = 2;  // 1..24, normalised across languages
  string severity_text = 3;            // "INFO", "WARN", "Error" — the source's own word
  string body = 5;                     // AnyValue: string, bool, int, double, bytes, array, kvlist
  repeated KeyValue attributes = 6;
  fixed32 flags = 7;
  bytes trace_id = 8;                  // ← the correlation fields
  bytes span_id = 9;
  uint32 event_name = 12;              // for structured "events" rather than free logs
}
```

### SeverityNumber — the normalisation table

| Range | Level | Typical strings |
|---|---|---|
| 1–4 | TRACE | `TRACE`, `FINEST` |
| 5–8 | DEBUG | `DEBUG`, `FINE` |
| **9–12** | **INFO** | `INFO`, `INFORMATION`, `NOTE` |
| **13–16** | **WARN** | `WARN`, `WARNING` |
| **17–20** | **ERROR** | `ERROR`, `ERR`, `SEVERE` |
| 21–24 | FATAL | `FATAL`, `CRITICAL`, `EMERGENCY` |

★ **Why this exists:** every language and logging library has different level names and numbers. A single numeric scale means one alert rule ("severity_number >= 17") works across Java, Python, Go and Node. **Alert on `severity_number`, display `severity_text`.**

### `time_unix_nano` vs `observed_time_unix_nano`
- `time_unix_nano` = when the event actually happened.
- `observed_time_unix_nano` = when the collector/SDK first saw it.
These differ when you're tailing a historical log file, replaying a backlog, or when clock skew is involved. **Backends index on `time_unix_nano` by default**, which means backfilling an old log file writes records with old timestamps — and they may fall outside your retention/index window and vanish. If that happens, this is why.

### Body is `AnyValue`, not string
This is a real design difference from most log formats. A body can be a string, a bool, an int, a double, bytes, an array, or a **key-value list**. That means structured JSON logs can be ingested as structured OTel data rather than flattened into a string that has to be re-parsed at query time. The Collector's `file_log` receiver with stanza operators, and the JSON parsers (`logs.jsonParserArray`, `logs.assignKeys` feature gates), exploit this.

---

## 2.7 The Profile data model (alpha)

Since profiles are **public alpha (March 2026)** and gated behind the Collector's `service.profilesSupport` feature gate, treat the shape as indicative rather than contractual. Full treatment in [`08-profiles.md`](08-profiles.md); the data-model points:

- A profile is a **stream of sampled stack traces** with associated CPU/memory cost, attached to the same Resource and Scope model as everything else — which is what makes correlation with traces possible.
- **The OTLP profiles encoding uses a shared string dictionary.** Function names, file paths and other repeated strings are interned once per request rather than repeated per sample. That's roughly a **40% wire-size reduction** versus a naive encoding.
- The Collector has a `pkg/pprofile` package and the v0.161.0 release notes include a fix to *"reference resource and scope attribute strings via the ProfilesDictionary string table when marshaling and unmarshaling OTLP profiles export requests"* — i.e. the string-table design is still being worked on. **Expect breaking changes.**
- **The SIG dropped the goal of strict pprof wire compatibility** in favour of *convertibility* — profiles round-trip to pprof but aren't byte-identical to it.

---

## 2.8 How OTLP differs from the formats it sits beside

| | **OTLP** | **Prometheus exposition** | **Jaeger/Zipkin** |
|---|---|---|---|
| Signals | All four | Metrics only | Traces only |
| Encoding | protobuf (or JSON over HTTP) | Text/protobuf, pull-scraped | Thrift/JSON, push |
| Resource/tags | **Attached once per batch** | Repeated on every series | Per span |
| Quantiles | Backend computes from buckets | Backend computes from `_bucket` | n/a |
| Temporality | **Both delta and cumulative, declared per data point** | Cumulative only | n/a |
| Partial failure | **First-class `partial_success` with rejected counts** | None | None |
| Delivery | Push (with retry/backoff specified) | Pull | Push |

★ **The batch-level Resource is OTLP's biggest efficiency win** and the reason it handles high-volume telemetry better than tag-per-record formats. It's also why a Collector that *strips and re-adds* resource attributes per span is doing something expensive — prefer resource-level processing.

**Pull vs push is a genuine philosophical difference, and OTel supports both.** The Collector's `prometheus` receiver **pulls** (scrapes `/metrics` endpoints, using ServiceMonitor/PodMonitor discovery via the Target Allocator). The SDK **pushes** to a Collector or backend. Short-lived jobs can't be pulled reliably — which is why the SDK push path exists and why the Prometheus Pushgateway pattern maps onto "SDK → Collector → remote write". See [`13-backends.md`](13-backends.md).

---

## 2.9 The Collector's internal pipeline model

Detail lives in [`11-collector.md`](11-collector.md); the data-model-relevant parts:

- **Pipelines are per-signal and independent.** `traces`, `metrics`, `logs`, `profiles` (gated). A pipeline is `receivers → processors → exporters`.
- **Processors within a pipeline run in the order listed** — and order matters enormously. `memory_limiter` first, then enrichment, then filtering, then `batch` last.
- **The same data can go to multiple pipelines** by listing a receiver in several.
- **Connectors terminate one pipeline and start another, across signals.** A `span_metrics` connector is an *exporter* in the traces pipeline and a *receiver* in the metrics pipeline.
  ★ **Rule enforced at startup:** a connector must be used in **both** roles or the Collector refuses to start:
  ```
  connector "servicegraph" used as receiver in [metrics] pipeline but not used in any supported exporter pipeline
  connector "spanmetrics"  used as exporter in [traces] pipeline but not used in any supported receiver pipeline
  ```
  Both of those messages are verified against v0.161.0. If you see one, you've wired a connector into only half of its required pair.
- **Each exporter has its own sending queue and retry settings**, independent of the pipeline. `sending_queue`, `retry_on_failure` and `timeout` are standard exporter options (`exporterhelper`), and there's a `pkg.exporterhelper.queueBatchEnabled` feature gate (off by default in v0.161.0) for the newer queue+batch implementation.
- **`pdata` is the in-memory representation.** It's a Go library that backs every component; the v0.161.0 notes mention `pdata` optimisations and there's a `-pdata.useProtoPooling` feature gate (disabled). This is why Collector performance work tends to be about allocation, not I/O.

---

## Red flags

| Believing / doing this | Reality |
|---|---|
| Setting `service.name` from the pod name | You get one "service" per pod; service maps and dashboards shatter. `service.instance.id` is the per-pod field |
| Span names containing IDs (`GET /users/12345`) | Unbounded span-name cardinality → backend index explosion. Use `http.route` (`GET /users/:id`) as the name and the ID as an attribute |
| Async instruments for fast-changing values | Aliasing: you miss every spike between collections |
| Blocking work in an async callback | Stalls the whole metric collection; exports miss their deadline |
| Exporting delta to Prometheus remote-write | Silent garbage. Convert with `delta_to_cumulative` first, or export cumulative |
| Running >1 Collector with `delta_to_cumulative` and no consistent routing | Deltas split across instances → reconstruction is wrong. Use `load_balancing` with `routing_key: streamID` or `metric` |
| Emitting `Summary` from your own code | Un-reaggregatable quantiles. Use Histogram/ExponentialHistogram |
| Averaging p99s across instances | Mathematically invalid, whatever the format |
| Denylist filtering for cardinality control | The next instrumentation upgrade adds an attribute you didn't deny. **Allowlists only** for metrics |
| Resource detectors with no `timeout` | Startup hangs when a cloud metadata endpoint is unreachable |
| `resource_detection` with `override: true` by default | Detectors clobber your application's attributes |
| Treating `UNSET` status as an explicit success | It means "no signal". Some backends count it as success; know which |
| Not checking `schema_url` when a query works for some services only | Different semconv versions in the same pipeline |

---

## Rapid recall

1. **Eight independent places a span can be dropped**: sampler, processor queue, exporter retry exhaustion, Collector `memory_limiter`, filter/tail_sampling, `load_balancing` sub-queues, backend rate limit, backend retention. Debugging "no data" means walking them in order.
2. **Resource → Scope → Data**, with the Resource attached **once per batch**. Resource = the producer (`service.name` lives here, constant per process). Scope = the instrumentation library, and carries **`schema_url`** — the semconv version, which is what makes migrations survivable.
3. **`deployment.environment.name`** is the V1 name (was `deployment.environment`). **K8s + container-registry resource attributes graduated to stable in semconv v1.43.0.** Entities (`OTEL_ENTITIES`) are emerging — know they exist, don't build on them.
4. **Resource detectors:** put `env` first, **always set `timeout: 5s`** (metadata endpoints hang), and leave **`override: false`** unless you want detectors clobbering app config. In K8s prefer `k8sattributes` over in-pod detectors for Deployment/pod-label metadata.
5. **SpanKind drives service maps and latency attribution.** `SERVER.duration` = your latency; `CLIENT.duration` = dependency + network. PRODUCER/CONSUMER spans can be arbitrarily far apart in time — use links.
6. **Status `UNSET` ≠ `OK`.** Exceptions are span *events* named `exception`; **stacktraces are large** and often need truncation.
7. **Sync instruments aggregate your calls; async instruments are read on a callback** (default 60 s). Events → sync, state → async. Callbacks must be cheap and non-blocking.
8. **Temporality: cumulative = since start (Prometheus, robust to missed scrapes); delta = since last report (Datadog/CloudWatch, loses data if an export drops).** Detect it by plotting the raw series or by inspecting `start_time_unix_nano`. `prometheus_remote_write` **requires cumulative**; convert with `delta_to_cumulative`.
9. **Explicit-bucket vs exponential histograms:** explicit needs Prometheus and pre-chosen boundaries (align them to your SLO thresholds); exponential adapts with bounded relative error and no bucket guessing. **Never emit `Summary`** — it's for ingesting Prometheus pre-computed quantiles only, and can't be re-aggregated.
10. **Views are the SDK-side cardinality control** — `attribute_keys.included` as an **allowlist** is the single highest-leverage setting, because it makes new attributes unable to explode your series count.
11. **Log records carry `trace_id`/`span_id`** (that's the correlation), a normalised **`severity_number` 1–24** (alert on this, display `severity_text`), and two timestamps — `time_unix_nano` (when it happened) vs `observed_time_unix_nano` (when seen). Backends index on the former, so backfilling old files can silently fall outside retention.
12. **Profiles (alpha):** same Resource/Scope model, **shared string dictionary** for ~40% wire reduction, pprof *convertible* rather than wire-compatible. Gated behind `service.profilesSupport`.
13. **Connectors must be wired in both roles** or the Collector refuses to start — the error message names the connector and the pipeline.

→ Next: [`03-context-and-propagation.md`](03-context-and-propagation.md)
