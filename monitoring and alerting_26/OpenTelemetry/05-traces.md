# 05 · Traces

The most mature OTel signal — stable in every major language, stable in OTLP 1.11.0, and the one where correct configuration pays off most visibly. Also the one where **span limits** and **span-name cardinality** silently destroy your data if you don't set them.

---

## 5.1 The span lifecycle, precisely

```
1. tracer.start(name, opts)
      │  ├─ Sampler.shouldSample() → RECORD_AND_SAMPLE / RECORD_ONLY / DROP
      │  ├─ If DROP: returns a non-recording Span. All setters are no-ops.
      │  │           ★ It still has a valid trace_id/span_id and still propagates!
      │  └─ start_time recorded
      ▼
2. span.setAttributes(...) / addEvent(...) / addLink(...) / setStatus(...)
      │  Accumulated in memory, bounded by span limits (5.4)
      ▼
3. span.end()
      │  end_time recorded; span handed to SpanProcessor.onStart→onEnd
      ▼
4. BatchSpanProcessor queue (default max 2048)
      │  ★ Queue full → span DROPPED, counter incremented
      ▼
5. Flush trigger: size ≥ 512, or 5s elapsed, or shutdown/forceFlush
      ▼
6. OTLP exporter: wrap in ResourceSpans → protobuf → send
      │  Retry on 429/5xx with exponential backoff + jitter
      │  Timeout 30s; after retries exhausted → DROPPED
      ▼
7. Backend
```

### The three sampling decisions
`shouldSample()` returns one of:

| Decision | Span recorded? | Attributes kept? | `trace_flags` sampled bit | Propagated downstream? |
|---|---|---|---|---|
| **RECORD_AND_SAMPLE** | Yes | Yes | **1** | Yes |
| **RECORD_ONLY** | Yes | Yes | **0** | **Yes** — ★ see below |
| **DROP** | No | No | 0 | **Yes** |

★ **The non-obvious and important part:** a **DROP**ped span still produces a valid `SpanContext` that gets propagated. The trace continues downstream; you just don't record *this* span. That's what makes head sampling consistent across services — the decision is made once at the root and everyone obeys it via `traceparent`'s sampled bit.

And **RECORD_ONLY** is the mechanism behind a genuinely useful pattern: record the span locally (so you have it if you need it) but don't mark it sampled, so downstream services don't record. Rarely used, occasionally powerful.

---

## 5.2 Span processors

| Processor | Behaviour | Use |
|---|---|---|
| **SimpleSpanProcessor** | Exports synchronously on every `end()` | **Development only.** Latency per span, one export per span, no batching |
| **BatchSpanProcessor** | Ring buffer, flushes on size/time/shutdown | **Always, in production** |

**BatchSpanProcessor tuning** (env vars, or declarative config):

| Setting | Default | Tuning notes |
|---|---|---|
| `OTEL_BSP_MAX_QUEUE_SIZE` | **2048** | ★ Raise under high span volume **or** when the exporter is slow. A full queue drops spans. Watch `otelcol_sdk_processor_batch_dropped` / the SDK's dropped counter |
| `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` | **512** | Must be ≤ queue size. Larger batches = fewer requests, more memory, longer latency |
| `OTEL_BSP_SCHEDULE_DELAY` | **5000 ms** | ★ The reason "I see nothing" during testing. Lower to 1000 ms in dev |
| `OTEL_BSP_EXPORT_TIMEOUT` | **30000 ms** | If exports routinely take this long, you have a backend or network problem — lowering the timeout just loses data faster |

★ **The relationship that matters:** throughput ≥ span_rate, and queue_size ≥ span_rate × schedule_delay, or you drop. If you emit 2000 spans/s with a 5 s delay and a 2048 queue, the queue is full in one second. **Size the queue from your span rate, not from a default.**

**Multiple processors are allowed** — a common pattern is `BatchSpanProcessor` for normal export plus a `SimpleSpanProcessor` writing to a local debug exporter, or two batch processors to two different exporters (dual-shipping during a migration, see [`17-migration-and-adoption.md`](17-migration-and-adoption.md)).

---

## 5.3 Manual instrumentation that's actually worth doing

Auto-instrumentation gives you the framework layer. **Manual instrumentation gives you the business layer**, which is the part that answers "why was this slow" rather than "which hop was slow".

### The high-value patterns

**1. Name the operation after the business step, not the function.**
```python
# Not great — mirrors your code structure, tells you nothing new
with tracer.start_as_current_span("process_order_internal"):

# Good — names the business operation
with tracer.start_as_current_span("order.validate-stock") as span:
    span.set_attribute("order.items.count", len(items))
    span.set_attribute("order.requires_backorder", needs_backorder)
```

**2. Add the attributes you'd want to filter by during an incident.**
```java
Span span = tracer.spanBuilder("payment.authorize").startSpan();
span.setAttribute("payment.provider", "stripe");
span.setAttribute("payment.amount.currency", "EUR");
span.setAttribute("payment.amount.value", 4250L);     // minor units, integer
span.setAttribute("payment.retry.attempt", attempt);
span.setAttribute("tenant.id", tenantId);             // ★ low cardinality, high value
```
★ **The test for whether an attribute is worth adding:** *"during an incident, would I want to filter or group by this?"* `tenant.id`, `payment.provider`, `order.requires_backorder` — yes. `function.line_number` — no, that's what `code.*` attributes and stack traces are for.

**3. Record exceptions properly.**
```python
try:
    await charge()
except Exception as exc:
    span.record_exception(exc)          # creates an "exception" event with
                                        # exception.type/message/stacktrace
    span.set_status(StatusCode.ERROR, str(exc))
    raise                               # ★ re-raise; don't swallow
```
```java
try { charge(); }
catch (Exception e) {
    span.recordException(e);
    span.setStatus(StatusCode.ERROR, e.getMessage());
    throw e;
}
```
★ **Two common mistakes:** calling `record_exception` without `set_status` (so error-rate queries that look at status miss it), and setting status without recording the exception (so you know it failed but not why). **Do both.**

★ **And the expensive one: `exception.stacktrace` is large.** A 40-frame Java stacktrace is 3–6 KB. At 100 errors/s that's 0.5 MB/s of stacktraces. Options: truncate in the Collector, drop stacktraces for known-benign exception types, or capture them only for non-4xx errors:
```yaml
processors:
  transform/stacktraces:
    error_mode: ignore
    trace_statements:
      - context: spanevent
        statements:
          - truncate_left(attributes["exception.stacktrace"], 2000) where name == "exception"
          # drop stacktraces for expected client errors entirely
          - delete_key(attributes, "exception.stacktrace") where name == "exception" and attributes["exception.type"] == "ValidationException"
```

**4. Use span events for progress within a long operation.**
```go
span.AddEvent("cache.miss", trace.WithAttributes(attribute.String("cache.key", key)))
span.AddEvent("retry", trace.WithAttributes(attribute.Int("attempt", 2)))
```
Events are cheaper than child spans and show up on the span's timeline. Good for: cache hit/miss, retry attempts, queue enqueue/dequeue, feature-flag evaluations, "entered the slow path".

**5. Use links when causality isn't a call stack.**
```java
Span span = tracer.spanBuilder("batch.process")
    .addLink(SpanContext.createFromRemoteParent(traceId, spanId, flags, state))
    .startSpan();
```
Canonical uses: **batch jobs** (one processing span linking to the N originating request traces), **fan-in** (an aggregation linking to its sources), **retries** (attempt 2 linking to attempt 1), **scheduled work** triggered by an earlier request.

**6. Propagate context across your own async boundaries.** Covered in detail in [`03-context-and-propagation.md`](03-context-and-propagation.md) — this is where traces break most often, and it's not an instrumentation-API question.

### What *not* to instrument
- **Trivial in-process functions.** A span per getter costs more than it tells you. Rule of thumb: instrument operations that take **>1 ms** or that **cross a boundary** (network, disk, queue, thread, subprocess).
- **Anything inside a tight loop**, unless you use a link/event to summarise the loop.
- **Health check and readiness endpoints** — filter them out at the Collector instead ([`11-collector.md`](11-collector.md)), or you'll pay to store spans nobody reads.

---

## 5.4 Span limits — the setting nobody configures and everybody needs ★

The SDK bounds what a single span can hold. **Defaults exist, they're generous, and exceeding them silently truncates.**

| Limit | Typical default | What happens when exceeded |
|---|---|---|
| **Attribute count per span** | 128 | Extra attributes **dropped** |
| **Attribute value length** | unlimited in some SDKs, bounded in others | Truncated |
| **Events per span** | 128 | Extra events dropped |
| **Attributes per event** | 128 | Extra attributes dropped |
| **Links per span** | 128 | Extra links dropped |
| **Attributes per link** | 128 | |
| **Total spans per trace** | **Not an SDK limit** — a *backend* limit | Backends cap spans per trace (often 10k–100k) and truncate or reject |

Configurable via `OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT`, `OTEL_SPAN_EVENT_COUNT_LIMIT`, `OTEL_SPAN_LINK_COUNT_LIMIT`, `OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT`, and in declarative config under the SDK's span limits.

**Why this matters in practice:**
- A span with 500 attributes silently keeps 128. **The 372 you lose are not random** — they're whichever the SDK drops, which is usually the later ones, which is usually *yours* rather than the framework's.
- **The dropped-attribute counter is a real signal.** SDKs export metrics like `otelcol_sdk_span_dropped_count` / dropped-attribute counts. **Alert on them.** Silent truncation is much worse than an error.
- Long-running spans (a 6-hour batch job as one span) accumulate events and can hit every limit.

★ **Design rule:** prefer **many short spans** over **one long span with many attributes**. A span per operation, with a few attributes each, is more useful, more robust to limits, and renders better in every UI.

---

## 5.5 Trace-based metrics: getting RED metrics from spans

You often want request-rate/error-rate/duration metrics **without** adding manual metric instrumentation. The Collector generates them from spans.

### The `span_metrics` connector ★
```yaml
connectors:
  span_metrics:                        # (old name `spanmetrics` still accepted)
    histogram:
      explicit:
        buckets: [1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s]
    dimensions:
      - name: http.response.status_code
      - name: http.route
      - name: deployment.environment.name
    dimensions_cache_size: 1000
    aggregation_temporality: AGGREGATION_TEMPORALITY_CUMULATIVE
    # exclude_dimensions / include_dimensions also available
```
Wiring — **remember the connector rule: it must appear in both roles or the Collector won't start:**
```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo, span_metrics]     # ← as an EXPORTER
    metrics:
      receivers: [otlp, span_metrics]           # ← as a RECEIVER
      processors: [memory_limiter, batch]
      exporters: [prometheus_remote_write]
```
Verified error messages when you get this wrong (v0.161.0):
```
connector "spanmetrics" used as exporter in [traces] pipeline but not used in any supported receiver pipeline
connector "spanmetrics" used as receiver in [metrics] pipeline but not used in any supported exporter pipeline
```

**Produces:** `traces_span_metrics_duration_milliseconds_bucket/_sum/_count`, `traces_span_metrics_calls_total`. Exact names depend on `connector.spanmetrics.legacyMetricNames` (**off by default** → new names) and `connector.spanmetrics.statusCodeConvention.useOtelPrefix` (**off**).

★ **`dimensions` is a cardinality decision.** Every dimension multiplies your series count by its distinct-value count. `http.route` (dozens) is fine; `http.url` (unbounded) will destroy your TSDB. **`dimensions_cache_size` bounds the internal cache** — set it deliberately; a too-small cache causes churn and a too-large one uses memory.

**Feature gates:** `connector.spanmetrics.excludeResourceMetrics` (**on** — resource attributes are excluded from the metric dimensions), `connector.spanmetrics.includeCollectorInstanceID` (**off** — turn on if multiple Collectors emit the same series and your backend can't handle collisions).

### ★ The multi-Collector collision problem
If three Collector replicas each run `span_metrics`, each sees only *part* of the traffic — and if they route by `traceID`, **the same `service+operation` combination is counted on all three**, producing conflicting cumulative series in Prometheus.

**Fix:** put a `load_balancing` exporter **before** the `span_metrics` connector with `routing_key: "service"`. Then each service's spans all land on one Collector, and that Collector is the sole emitter of that service's span metrics.

```yaml
exporters:
  load_balancing:
    routing_key: "service"           # ★ top-level in v0.161.0
    protocol:
      otlp:
        timeout: 1s
        sending_queue: {enabled: true}
    resolver:
      dns: {hostname: otelcol-metrics-headless.observability.svc.cluster.local}
```
This is documented explicitly in the upstream README: *"there is a high chance of facing label collisions on prometheus if the routing is based on `traceID` because every collector sees the `service+operation` label."*

### The `service_graph` connector
Builds service-to-service edge metrics (`traces_service_graph_request_total`, `_request_duration_seconds_bucket`, `_request_failed_total`, `_untyped_call_total`) from CLIENT/SERVER span pairs.
```yaml
connectors:
  service_graph:
    dimensions: [http.route]
```
Feature gates: `connector.servicegraph.legacyLatencyMetricNames` (**off**), `legacyLatencyUnitMs` (**off** — so latency is in **seconds**, not ms), `connector.servicegraph.virtualNode` (**on**).

**Caveat:** it needs **both** sides of a call to build an edge, so it requires trace-complete routing (again: `load_balancing` by `service` or `traceID`) and it tolerates partial traces poorly. If your service map has missing edges, check propagation first ([`03`](03-context-and-propagation.md)).

### Other relevant connectors (v0.161.0)
| Connector | Direction | Use |
|---|---|---|
| **`count`** | traces/metrics/logs → metrics | Count spans, span events, log records, datapoints — with conditions and attribute grouping |
| **`exceptions`** | traces → logs **and** traces → metrics | Turn exception span events into log records / metrics |
| **`signal_to_metrics`** | any → metrics | Newer general-purpose signal-to-metric conversion |
| **`sum`** | metrics → metrics | Aggregate series |
| **`forward`** | any → same | Pass-through, for pipeline fan-out |
| **`routing`** | any → same | Conditional routing by attribute |
| **`failover`** | any → same | Primary/backup exporter ordering |
| **`round_robin`** | any → same | Distribute across pipelines |
| **`grafanacloud`** | traces → metrics | Grafana Cloud-specific host/edge metrics |
| **`otlp_json`** | any → same | OTLP JSON conversion |

The `count` connector's schema — note the **map** form, not a list:
```yaml
connectors:
  count:
    spans:
      error.span.count:
        description: Number of spans with an error status
        conditions: ['status.code == 2']       # conditions are ORed
    logs:
      log.record.count.by.service:
        attributes:
          - key: service.name
            default_value: unknown             # counts records missing the attribute
```
Default metric names when unconfigured: `trace.span.count`, `trace.span.event.count`, `metric.count`, `metric.datapoint.count`, `log.record.count`. **If you define any custom metric for a data type, the default for that type is not emitted.**

---

## 5.6 Trace-specific processors worth knowing

| Processor | What it does | Notes |
|---|---|---|
| **`tail_sampling`** | Keeps whole traces matching policies | **Requires all spans of a trace to reach one instance** → pair with `load_balancing`. Beta for traces. Detail in [`10-sampling.md`](10-sampling.md) |
| **`probabilistic_sampler`** | Head-style sampling in the Collector | Beta for traces, **Alpha for logs**. Rewrites `trace_flags` |
| **`groupbytrace`** | Buffers to assemble complete traces | Use before `load_balancing` when the backend list changes often |
| **`span`** | Rename spans, extract attributes from the name | Alpha. Useful for fixing bad span names from third-party instrumentation |
| **`span_pruning`** | Drop spans by criteria | Newer — reduces volume at the edge |
| **`filter`** | Drop spans/logs/metrics by OTTL condition | **Alpha for all signals.** Drop health checks here |
| **`attributes`** | insert/update/upsert/delete/hash/extract | Beta. The workhorse for enrichment and PII |
| **`transform`** | Full OTTL expressions | Beta |
| **`redaction`** | Allow/deny-list based redaction with regex | **Beta for traces, Alpha for logs/metrics** |
| **`k8sattributes`** | Enrich with pod/namespace/deployment from the K8s API | Not in the core binary; contrib only. Needs RBAC |
| **`resource_detection`** | Detect cloud/host/container resource attributes | Always set `timeout` |
| **`memory_limiter`** | Shed load under memory pressure | ★ **Must be the first processor** |
| **`batch`** | Batch before export | ★ **Must be the last processor** |
| **`drain`** | Drain pipelines gracefully | Newer |
| **`geoip`** | Add geo attributes from IPs | Newer |

### The processor ordering rule ★
```yaml
processors: [memory_limiter, k8sattributes, attributes, transform, filter, batch]
#            ↑ FIRST: shed load before doing any work      ↑ LAST: batch what survives
```
- **`memory_limiter` first** — if you're going to drop data under memory pressure, drop it before spending CPU enriching it.
- **`batch` last** — batching before filtering means you filter across batches inconsistently; enriching after batching means you re-do work per batch.
- **Enrich before filter** — filters often depend on enriched attributes (e.g. drop spans where `k8s.namespace.name == "kube-system"`, which requires `k8sattributes` to have run).
- **Sample before enrich** if sampling is aggressive — no point enriching spans you'll drop. But **tail_sampling must come after enrichment** if its policies use enriched attributes. There's a real tension here; resolve it by deciding whether your sampling policies need the enriched attributes.

---

## 5.7 Storage characteristics of traces (why backends differ)

Understanding this explains the whole tracing-backend market.

| Property | Consequence |
|---|---|
| **Traces are append-only, immutable, per-request** | No aggregation on write; you store raw events |
| **Access pattern is "find by trace_id" or "find traces matching X in a time window"** | Two very different index requirements |
| **Most traces are never read** | ★ The entire economics of tracing is "store cheaply, search a subset" |
| **Traces have a natural parent-child tree** | Needs reconstruction at read or write time |
| **Cardinality is driven by span names and attributes** | Unbounded span names = unbounded index |

**How the main backends respond:**

| Backend | Strategy | Trade-off |
|---|---|---|
| **Grafana Tempo** | Object storage (S3/GCS) + a compact index of trace_id → block. **Search via brute-force scan of recent blocks** | Extremely cheap per GB; search is slower than a full index. Best price/performance for "we mostly look up by trace ID from a log or metric" |
| **Jaeger** | Pluggable: Cassandra, Elasticsearch/OpenSearch, or Badger | Full search index; operationally heavier and much more expensive per GB |
| **Vendor APMs** | Proprietary, often with pre-aggregation into service maps and metrics | Great UX, expensive per span, and the aggregation is the product |
| **ClickHouse-based** (SigNoz, Uptrace, HyperDX) | Columnar storage, SQL queries | Cheap, fast analytical queries, and you can join traces with logs in SQL. Growing fast |

★ **The practical insight:** if 95% of your trace lookups start from a **log line or a metric spike** and then jump to the trace ID, you don't need a full-text trace search index — you need cheap storage and good exemplars. That's Tempo's entire argument, and it's why "OTel + Tempo + Loki + Grafana" became the default open-source stack.

**Exemplars** are the mechanism: a metric histogram bucket carries a sample `trace_id`. Click a spike on a latency graph, land on the exact trace that caused it. See [`06-metrics.md`](06-metrics.md).

---

## Red flags

| Doing this | Costs you |
|---|---|
| `SimpleSpanProcessor` in production | One export per span; latency and backend load |
| Default BSP queue at high span volume | Silent drops. Size the queue from `span_rate × schedule_delay` |
| Not setting span limits | Silent truncation at 128 attributes/events — and the ones dropped are usually yours, not the framework's |
| One giant span for a long job | Hits every span limit and backend per-trace caps. Chunk and link |
| `record_exception` without `set_status` (or vice versa) | Error-rate queries miss it, or you know it failed but not why |
| Storing full stacktraces on every error | Kilobytes per error; a real bill and a real index cost |
| IDs in span names | Unbounded cardinality; the classic Express/Flask failure |
| Attributes you'd never filter by during an incident | Cost with no benefit |
| Running `span_metrics` on multiple Collector replicas routed by `traceID` | **Label collisions in Prometheus.** Route by `service` |
| Wiring a connector into only one pipeline | Collector refuses to start, with a message naming the connector |
| `batch` before `filter`/enrichment | Inconsistent filtering, wasted work |
| `memory_limiter` not first | You spend CPU enriching data you're about to drop |
| Assuming `tail_sampling` works on one Collector in a fleet | Spans of a trace land on different instances; policies see partial traces. **You need `load_balancing`** |
| Never alerting on dropped-span counters | Silent data loss, discovered during the incident that mattered |
| Keeping health-check spans | You pay to store spans nobody reads |

---

## Rapid recall

1. **A dropped span still propagates.** DROP produces a non-recording span with a valid context — that's what makes head sampling consistent across services via the `traceparent` sampled bit.
2. **BatchSpanProcessor defaults: queue 2048, batch 512, delay 5 s, timeout 30 s.** Size the queue from `span_rate × schedule_delay`. Lower the delay in dev; **alert on dropped-span counters.**
3. **Manual instrumentation = the business layer.** Name operations after business steps; add attributes you'd *filter by during an incident* (`tenant.id`, `provider`, `retry.attempt`); **always do `record_exception` + `set_status` together**; use **events** for in-span progress and **links** for non-call-stack causality (batches, fan-in, retries).
4. ★ **Span limits silently truncate** — typically 128 attributes/events/links per span, with dropped-attribute counters you should alert on. Prefer **many short spans** over one long span with many attributes.
5. **`stacktrace` is the expensive attribute.** Truncate or drop by exception type in a `transform` processor.
6. **`span_metrics` connector** gives RED metrics from spans: configure `histogram.explicit.buckets` to match your SLO thresholds, and treat **`dimensions` as a cardinality decision** (`http.route` yes, `http.url` never). Set `dimensions_cache_size`.
7. ★ **Multi-Collector + `span_metrics` + `traceID` routing = Prometheus label collisions.** Fix with a `load_balancing` exporter using **`routing_key: "service"`** upstream of the connector.
8. **Connectors must be wired in both roles** — exporter in a supported pipeline *and* receiver in a supported pipeline — or the Collector refuses to start with a message naming the connector and pipeline.
9. **`count` connector uses a map** (`spans: {metric.name: {conditions, attributes}}`), conditions are ORed, and defining a custom metric **suppresses the default** for that type.
10. **Processor order: `memory_limiter` first, enrich, filter, sample, `batch` last.** Tension: sample-before-enrich saves work, but `tail_sampling` policies that use enriched attributes need enrichment first.
11. **Trace storage economics: most traces are never read.** If your lookups start from a log or metric and jump to a trace ID, you need cheap object storage plus **exemplars**, not a full search index — that's Tempo's argument, and why OTel+Tempo+Loki+Grafana is the default OSS stack.
12. **`service_graph`** builds edge metrics from CLIENT/SERVER pairs and needs trace-complete routing; **missing edges usually mean broken propagation**, not a connector bug.

→ Next: [`06-metrics.md`](06-metrics.md)
