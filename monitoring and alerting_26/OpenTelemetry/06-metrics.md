# 06 · Metrics

The signal with the most subtle failure modes. Metrics "work" — data arrives, dashboards render — and then a temporality mismatch or one bad label quietly makes them wrong or bankrupts your TSDB. **Nothing else in OTel fails as silently.**

---

## 6.1 The instrument selection table

Pick the instrument by asking two questions: **is this an event or a state?** and **does it only go up?**

| You're measuring | It's a… | Instrument | Example |
|---|---|---|---|
| Events that only accumulate | event, monotonic | **Counter** | requests served, errors, bytes sent, cache hits |
| Events that go both ways | event, non-monotonic | **UpDownCounter** | items added to / removed from a queue |
| Distribution of a value per event | event, distribution | **Histogram** | request duration, payload size |
| Current value, sampled by you on demand | state | **Gauge** | (rare — usually you want an async instrument) |
| Current value, read periodically | state, monotonic | **ObservableCounter** | total bytes read from disk since boot |
| Current value, read periodically | state, fluctuating | **ObservableUpDownCounter** | open file descriptors, goroutines, active connections |
| Current value, read periodically | state, instantaneous | **ObservableGauge** | memory used, disk free, CPU temperature, queue depth |

★ **The single most common mistake: using an `ObservableGauge` for something that's actually a count of events.** If you report "requests so far this minute" as a gauge read every 60 s, you miss everything between reads and you can't compute a rate correctly. **Events → Counter. State → Observable.**

★ **The second most common: `Histogram` for something with one value per interval.** A histogram of "memory usage" sampled every 60 s gives you one observation per bucket-set per minute — meaningless as a distribution. Memory usage is a **gauge**; its histogram over a day is a different (and less useful) question.

### Sync vs Async, and why the distinction is correctness-critical

| | **Sync** (Counter, UpDownCounter, Histogram, Gauge) | **Async** (Observable*) |
|---|---|---|
| Who calls it | Your code, on the request path | The SDK, on the **collection interval** (default **60 s**) |
| What the SDK does | **Aggregates** your calls into data points | **Reads** the current value via your callback |
| Two calls in one interval | Summed into one data point | n/a — you're asked once |
| Cost | Per-call overhead (nanoseconds–microseconds) | Callback overhead, once per interval |
| Failure mode | Overhead if called in a tight loop | **Aliasing** if the value changes faster than the interval; **stalls** if the callback blocks |

★ **Async callback rules:**
1. **Must be cheap and non-blocking.** Callbacks run in the SDK's collection thread. A callback that queries a database, takes a contended lock, or does I/O stalls *all* metric collection and can push the export past its deadline.
2. **Read a cached value; don't compute one.** Keep an `AtomicLong`/`atomic.Int64` updated on the request path; read it in the callback.
3. **Must not throw.** An exception in a callback can abort the collection cycle.
4. **Register once.** Re-registering a callback per request leaks and multiplies.

```java
// Correct pattern: cheap atomic read in the callback
AtomicLong activeConnections = new AtomicLong();
meter.gaugeBuilder("db.pool.active")
     .setDescription("Active connections in use")
     .setUnit("{connection}")
     .ofLongs()
     .buildWithCallback(obs -> obs.record(activeConnections.get()));
```

```python
# Correct pattern: read a cached value
meter.create_observable_gauge(
    "db.pool.active",
    callbacks=[lambda options: [Observation(POOL.active())]],
    description="Active connections in use",
    unit="{connection}",
)
```

### Collection interval and its consequences
- Default **60 s** for the SDK's metric reader. The Collector's `prometheus` exporter and Prometheus itself typically scrape every 15–30 s.
- ★ **A 60 s interval means a 30-second incident may produce zero data points.** For anything you'd alert on at sub-minute resolution, lower the interval — and understand that interval × cardinality = your data volume.
- Interval, cardinality and retention multiply: **10,000 series × 1 point/15 s × 30 days ≈ 1.7 billion points.** That's the number your TSDB has to handle, and it's why cardinality control matters more than interval.

---

## 6.2 Aggregation temporality ★ (the thing that breaks silently)

Covered structurally in [`02-architecture-and-data-model.md`](02-architecture-and-data-model.md); here's the operational treatment.

### The two models, concretely

A service serves 100 requests in minute 1, 200 in minute 2, 50 in minute 3.

| Minute | **Cumulative** reports | **Delta** reports |
|---|---|---|
| 1 | `http.requests = 100` | `http.requests = 100` |
| 2 | `http.requests = 300` | `http.requests = 200` |
| 3 | `http.requests = 350` | `http.requests = 50` |
| Restart at min 4 | `http.requests = 0` (reset) | `http.requests = <next interval>` |

**Prometheus query for "requests per second":**
```promql
# Cumulative data — CORRECT
rate(http_requests_total[5m])

# Delta data — WRONG (rate() of an oscillating series is garbage)
# Correct for delta:
sum_over_time(http_requests[5m]) / 300
```

### Which to use

| Situation | Temporality | Why |
|---|---|---|
| **Exporting to Prometheus / Mimir / Thanos / VictoriaMetrics** | **Cumulative** | It's their native model. `prometheus_remote_write` **requires** cumulative |
| **Exporting to Datadog, CloudWatch, New Relic, most commercial APMs** | **Delta** | Their ingest model. CloudWatch in particular wants deltas |
| **Behind a load balancer with no session affinity** | **Delta** | Cumulative requires each series to be consistently attributed; LB-restarted or multi-instance aggregation gets confusing |
| **Frequently-restarting workloads (Lambda, cron, scale-to-zero)** | **Delta** | Cumulative series reset constantly, producing sawtooth series and confusing `rate()` reset detection |
| **You might drop an export** | **Cumulative** | ★ **Robustness: a missed cumulative export loses nothing** — the next value contains all history. A missed delta export **loses that interval permanently** |
| **Memory-constrained edge** | **Delta** (or `lowmemory`) | Cumulative requires remembering start time and accumulated value per stream |

**`lowmemory` preference** (available via `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=lowmemory`) chooses delta for sync instruments and cumulative for async ones — the cheapest combination that stays correct.

### Converting in the Collector

| Processor | Direction | Notes |
|---|---|---|
| **`cumulativetodelta`** / `cumulative_to_delta` | cumulative → delta | Tracks the previous value per stream and emits the difference. Detects resets |
| **`deltatocumulative`** / `delta_to_cumulative` | delta → cumulative | **Accumulates a running total per stream.** ★ Must see *every* delta for a stream |
| **`deltatorate`** / `delta_to_rate` | delta → rate | Emits a per-second rate instead of a total |

```yaml
processors:
  delta_to_cumulative:
    max_stale: 30m      # how long to remember a stream with no new data
    max_streams: 10000  # ★ bound the state; unbounded = memory leak on high-cardinality input
```

★ **The `max_streams` setting is a memory guard and a correctness trap at once.** Each stream (unique metric + attribute set) holds accumulated state. Set `max_streams` too low and streams get evicted, resetting their accumulation and producing wrong values. Leave it unbounded and a cardinality explosion becomes an OOM. **Set it from your known cardinality, and alert on evictions.**

★ **And the fleet problem:** `delta_to_cumulative` is **stateful**. If you run three Collector replicas and deltas for one stream are split across them, each reconstructs a partial total and the sum is wrong. **You must route consistently:**
```yaml
exporters:
  load_balancing:
    routing_key: "streamID"     # or "metric"
    protocol:
      otlp: {timeout: 1s}
    resolver:
      dns: {hostname: otelcol-metrics-headless.observability.svc.cluster.local}
```
`streamID` is the unique hash of a datapoint's attributes plus its resource, scope and metric identity — exactly the right routing granularity here. `metric` (route by metric name) is coarser and can hotspot; `service` works if all a service's metrics should stay together.

### How to diagnose temporality problems in 60 seconds
```promql
# 1. Plot the raw series (no rate()).
#    Monotonically increasing with resets at restarts  → CUMULATIVE
#    Oscillating around small positive values          → DELTA

# 2. Check start_time behaviour (if your backend exposes it):
#    start_time fixed, time advancing  → CUMULATIVE
#    start_time advancing with time    → DELTA

# 3. Compare rate() against a known-good count:
#    If rate() is ~10x too low or wildly variable, suspect delta-into-rate().
```

---

## 6.3 Histograms in practice

### Explicit buckets: choose them from your SLOs, not from a default
```yaml
# The buckets should let you answer the questions you'll actually be asked.
# If your SLO is "p99 < 500ms" and your error budget conversation is about
# "how many requests exceeded 1s", then 500ms and 1s MUST be bucket boundaries.
histogram:
  explicit:
    buckets: [1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s]
```
★ **Why boundaries must align with your thresholds:** a histogram quantile is **interpolated within a bucket**. With buckets `[..., 250ms, 1s]`, a p99 that lands in that bucket could be anywhere from 250 ms to 1 s — the computed value is a guess. If your SLO threshold is 500 ms and 500 ms isn't a boundary, **you cannot accurately answer "what fraction of requests exceeded our SLO"**, which is the exact question an error-budget policy needs.

**Bucket count is a cost multiplier.** 20 buckets × 10,000 streams = 200,000 series per interval. Every bucket is a series. This is why "just add more buckets for accuracy" is a scaling decision, not a free one.

### Exponential histograms: when the range is unknown
```yaml
# In SDK config / views:
aggregation:
  type: base2_exponential_bucket_histogram
  options:
    max_scale: 20      # higher scale = finer resolution
    max_size: 160      # max buckets; the scale reduces automatically to fit
    record_min_max: true
```
| Property | Value |
|---|---|
| **Error bound** | **Relative**, uniform across magnitudes — set by `max_scale` |
| **No guessing** | Adapts to the observed range automatically |
| **Series cost** | Usually fewer than explicit buckets for wide distributions |
| **Prometheus** | ★ **Not native.** Converted on export (to explicit buckets or to Prometheus native histograms if your stack supports them) |

**Decision rule:** **Prometheus target + known range → explicit buckets aligned to SLO thresholds.** Unknown or very wide range (1 ms to 30 s) → exponential. Both → export explicit for Prometheus and keep exponential for the vendor/APM.

### `record_min_max`
Histograms carry `min` and `max`. ★ **`max` is valuable for detecting outliers that buckets hide** — a 45 s request in a histogram whose top bucket is 10 s shows up only in `max`. But `min`/`max` are **not aggregatable across instances** the way counts and sums are (max of maxes is fine; average of maxes is meaningless).

---

## 6.4 Cardinality — the cost driver, in numbers

**A metric's cost = (number of streams) × (points per stream per interval) × (retention).**

Streams = the **product** of distinct values across all attribute keys:

| Attributes on `http.server.request.duration` | Distinct values | Streams |
|---|---|---|
| `http.request.method` | 5 | 5 |
| `http.route` | 80 | × 80 = 400 |
| `http.response.status_code` | 12 | × 12 = **4,800** |
| `service.name` | 40 | × 40 = **192,000** |
| `k8s.pod.name` | 500 | × 500 = **96,000,000** ← ☠️ |

**Adding `k8s.pod.name` multiplied your cost by 500.** And if you also add `user_id`, you're done — that's unbounded.

★ **The rule that saves you: high-cardinality attributes belong on *spans and logs*, not on *metrics*.** A trace can carry `user_id`, `order_id` and `k8s.pod.name` because traces are indexed per-request and pruned by retention. A metric series with those attributes is a permanent, always-growing index entry.

### Cardinality controls, in order of preference

**1. Allowlist at the SDK via views** — the strongest control:
```yaml
views:
  - instrument: {name: "http.server.request.duration"}
    stream:
      attribute_keys:
        included: [http.request.method, http.route, http.response.status_code, url.scheme]
```
★ **Why an allowlist beats a denylist:** a denylist (`excluded: [user_id, pod_name]`) fails *open* — the next instrumentation upgrade adds `http.request.header.x_session_id` and nobody notices for three weeks. An allowlist fails *closed*.

**2. Cardinality limits in the SDK** — the safety net:
```
OTEL_METRIC_CARDINALITY_LIMIT=2000      # per metric
```
When exceeded, the SDK aggregates the overflow into an `otel.metric.overflow attribute = true` series. **You keep working, you lose detail, and you get a visible signal.** ★ **Alert on the overflow series** — it means your allowlist is wrong or something is leaking.

**3. The Collector's `cardinality_guardian` processor** (present in contrib v0.161.0) — the fleet-level net. It monitors metric cardinality and can shed or aggregate when it grows beyond configured bounds. **This is the right place for a global backstop**, because it protects the backend from every producer at once, including ones you don't control.

**4. `filter` processor** — drop specific streams:
```yaml
processors:
  filter/drop-noise:
    error_mode: ignore
    metrics:
      datapoint:
        - 'attributes["http.route"] == "/healthz"'
        - 'resource.attributes["k8s.namespace.name"] == "kube-system"'
      metric:
        - 'name == "internal.debug.timing"'
```
**Alpha stability for all signals** — test it. ★ **`error_mode` defaults to `ignore`** in v0.161.0: `processor.filter.defaultErrorModeIgnore` is **true / Stable** (verified via `otelcol-contrib featuregate` — the `--help` default string disagrees and is wrong). **Consequence: a malformed OTTL condition is swallowed, not raised.** Set `error_mode: propagate` while developing so typos fail loudly, then decide.

**5. `attributes` processor to reduce a dimension:**
```yaml
processors:
  attributes/cap-status:
    actions:
      # collapse 200/201/202/204 into one bucket; keep 4xx/5xx distinct
      - key: http.response.status_code
        action: update
        value: "2xx"
        # (use `extract` with a regex for real pattern-based mapping)
```

**6. `groupbyattrs`** — promotes attributes and re-groups, useful for consolidating.

### Cardinality debugging
```promql
# Top 10 metrics by series count — run this monthly
topk(10, count by (__name__)({__name__=~".+"}))

# Series count for one metric
count(count by (job, instance) (http_server_request_duration_seconds_count))

# Which label is exploding? Compare counts with and without it
count(http_server_request_duration_seconds_count)
count without (k8s_pod_name) (http_server_request_duration_seconds_count)
```
In the Collector, **internal telemetry tells you what's coming in**: `otelcol_processor_batch_*`, `otelcol_exporter_sent_metric_points`, and per-pipeline metrics under the `telemetry.newPipelineTelemetry` gate (**off by default** in v0.161.0 — enable it for per-pipeline visibility).

---

## 6.5 Exemplars — the metric→trace bridge ★

An **exemplar** is a `trace_id` (and optionally a span_id) attached to a histogram bucket or a sum, recorded when a data point lands there.

```
http_server_request_duration_seconds_bucket{le="1.0"}  42
  └─ exemplar: {trace_id: "4bf92f35...", value: 0.87, time: 1726...}
```

**Why this is the single best observability UX improvement available:** a p99 spike on a dashboard becomes **one click to the exact trace that caused it**. No searching, no guessing which request was slow, no correlating timestamps by hand.

**Requirements for it to work:**
1. The SDK must be configured to record exemplars (`exemplar_filter` — typically `TraceBased`, which records only when the span was sampled).
2. ★ **The trace must actually be sampled**, or the exemplar points at a trace that doesn't exist. **This is the crucial coupling between your sampling policy and your exemplars** — a 1% head sample means 99% of your exemplars are dead links unless you use **tail sampling that keeps slow traces**, which is exactly what `tail_sampling`'s `latency` policy does.
3. The backend must store and render exemplars. **Prometheus supports them** (behind a feature flag historically; check your version — see `../Monitoring and Alerting/`). Grafana renders them as diamonds on graphs. Not all vendors do.

★ **The architecture this implies:** sample traces by *interestingness* (errors, slow, and a small random baseline) rather than uniformly, so that the traces your exemplars point at are the ones you kept. That's the strongest practical argument for tail sampling in a metrics-first shop — see [`10-sampling.md`](10-sampling.md).

---

## 6.6 The Prometheus bridge — three distinct paths

People say "OTel and Prometheus" and mean one of three different things. They are not interchangeable.

### Path A: **Scrape Prometheus targets with the Collector** (pull → OTLP)
```yaml
receivers:
  prometheus:                       # Beta for metrics
    config:
      scrape_configs:
        - job_name: 'app'
          scrape_interval: 15s
          static_configs:
            - targets: ['app:8080']
        # or full service discovery: kubernetes_sd_configs, file_sd_configs, etc.
    # target_allocator: {endpoint: http://ta:8080}   ← see below
```
- **Use when:** you have existing `/metrics` endpoints (Prometheus client libraries, node_exporter, third-party exporters) and want everything to flow through the Collector.
- **Produces cumulative temporality** — correct for Prometheus, and it ingests **`Summary`** types (pre-computed quantiles) that you could not re-aggregate.
- ★ **In Kubernetes, the Target Allocator** replaces static scrape config: it watches `ServiceMonitor`/`PodMonitor`/`ScrapeConfig` CRDs and the K8s service-discovery API, then **distributes targets across Collector replicas** so scraping scales horizontally. Detail in [`12-collector-in-kubernetes.md`](12-collector-in-kubernetes.md).
  - **Gotcha (verified, Operator v0.152.0+):** the Target Allocator requires the receiver to be named **exactly `prometheus`**. A named instance like `prometheus/otelcol` fails, and the error message now lists the instances it found and explains the requirement.

### Path B: **Expose metrics for Prometheus to scrape** (OTLP → pull)
```yaml
exporters:
  prometheus:                       # Beta
    endpoint: 0.0.0.0:8889
    resource_to_telemetry_conversion: {enabled: true}   # resource attrs → labels
    # send_timestamps: true
    # metric_expiration: 5m           # how long to keep a series after it stops updating
    # enable_open_metrics: true
    # without_scope_info / without_units / without_type_suffix — see gates below
```
- **Use when:** you want to keep Prometheus as your metrics backend and use OTel purely for instrumentation. **This is the most common and usually the best starting point.**
- ★ **Name transformation happens here.** Dots → underscores, and **suffixes are added by default** (`_total` for counters, `_seconds`/`_bytes` from the unit, `_bucket`/`_sum`/`_count` for histograms). ★ **But `add_metric_suffixes` is deprecated and IGNORED**: `exporter.prometheusexporter.DisableAddMetricSuffixes` is **true (Beta)**, whose real effect (verified in source) is that *"`translation_strategy` is always used"* — and unset resolves to `UnderscoreEscapingWithSuffixes`. **Set `translation_strategy` explicitly**: `UnderscoreEscapingWithSuffixes` (default) · `UnderscoreEscapingWithoutSuffixes` · ★ `NoUTF8EscapingWithSuffixes` (keeps UTF-8 names — pairs with Prometheus 3.x) · `NoTranslation`.
- **`metric_expiration` matters:** without it, series that stop updating linger and inflate cardinality.
- **`resource_to_telemetry_conversion: enabled`** turns every resource attribute into a label — ★ **convenient and dangerous.** A resource with 25 attributes creates 25 labels on every series. Turn it on for a small resource set; be explicit otherwise.

### Path C: **Remote-write to Prometheus / Mimir / Thanos / VictoriaMetrics** (OTLP → push)
```yaml
exporters:
  prometheus_remote_write:          # old name `prometheusremotewrite` still accepted
    endpoint: http://prometheus:9090/api/v1/write
    # For Mimir/Cortex/Thanos receive: the same shape, different endpoint
    resource_to_telemetry_conversion: {enabled: true}
    tls: {insecure: true}
    external_labels: {cluster: prod-eu-west-1}
    # sending_queue / retry_on_failure / timeout — standard exporterhelper options
```
- **Use when:** pushing to a long-term store, crossing network boundaries, or when you can't scrape (short-lived jobs, Lambda, ephemeral containers).
- ★ **Requires cumulative temporality.** Feed it deltas and you get wrong values. Insert `cumulative_to_delta`— no, the other way: **`delta_to_cumulative`** if your producers send delta.
- Relevant gates (all off by default unless noted): `exporter.prometheusremotewritexporter.EnableMultipleWorkers` (**off** — enable for throughput), `RetryOn429` (**off**), `enableSendingRW2` (**off** — Prometheus Remote-Write 2.0), `removeTopLevelHTTPSettings` (**off**), `exporter.prometheusremotewrite.DisableResourceToTelemetryConversion` (**off**).

### Choosing

| Need | Path |
|---|---|
| Keep Prometheus as-is, just instrument apps with OTel | **B** |
| Existing `/metrics` endpoints must flow through one pipeline | **A** (often A + B or A + C together) |
| Long-term storage, multi-cluster aggregation, short-lived jobs | **C** |
| All three at once | Common and fine — a Collector can scrape (A), expose (B) and remote-write (C) simultaneously |

---

## 6.7 OTel metrics vs the Prometheus data model — the real differences

| Aspect | **Prometheus** | **OTel** |
|---|---|---|
| Delivery | **Pull** (scrape) | **Push** (export); pull available via the `prometheus` receiver |
| Temporality | Cumulative only | **Both**, declared per data point |
| Identity | Metric name + label set | Metric name + **attribute set** + resource + scope |
| Units | Convention (`_seconds`, `_bytes`) | **First-class `unit` field** |
| Description | Help text, optional | **First-class `description`** |
| Quantiles | Computed at query time from `_bucket` | Computed at query time, **or** pre-computed `Summary` |
| Histograms | Explicit buckets only | Explicit **and exponential** |
| Scope/library info | Not modelled | **`InstrumentationScope` with version and `schema_url`** |
| Resource | Some labels on every series | **Structured, batch-level Resource** |
| Start time | Implicit | **Explicit `start_time_unix_nano`** — which is how you detect temporality and handle restarts |
| Target liveness | `up` metric, automatic | ★ **No equivalent** — a push-based producer that dies just stops sending. You must build the check |
| Exemplars | Supported | Supported |

★ **The `up` metric gap is the most under-appreciated difference.** Prometheus's pull model gives you `up == 0` for free the moment a target stops responding — a genuinely excellent failure signal. With push-based OTel, **silence looks identical to "no traffic"**. Compensate with:
- **`absent()` / `absent_over_time()` alerts** on the metrics you expect: `absent(up{job="checkout"})` or `absent_over_time(http_server_request_duration_seconds_count[5m])`.
- **Collector internal telemetry** — `otelcol_receiver_refused_metric_points` and `otelcol_exporter_send_failed_metric_points`.
- **A heartbeat metric** emitted unconditionally every interval, so its absence is meaningful.
- **The `health_check` extension** plus a synthetic probe.

This is a real design trade-off of push vs pull, not an OTel deficiency — but you have to build the thing Prometheus gave you for free.

---

## 6.8 A production metrics pipeline, assembled

```yaml
receivers:
  otlp:
    protocols:
      grpc: {endpoint: 0.0.0.0:4317}
      http: {endpoint: 0.0.0.0:4318}
  prometheus:                                  # scrape existing exporters
    config:
      scrape_configs:
        - job_name: node
          scrape_interval: 30s
          static_configs: [{targets: ['node-exporter:9100']}]
  host_metrics:                                # (old name: hostmetrics)
    collection_interval: 30s
    scrapers: {cpu: , memory: , disk: , filesystem: , network: , load: }

connectors:
  span_metrics:                                # RED metrics from traces
    histogram:
      explicit:
        buckets: [5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s]
    dimensions:
      - {name: http.route}
      - {name: http.response.status_code}
      - {name: deployment.environment.name}
    dimensions_cache_size: 1000
    aggregation_temporality: AGGREGATION_TEMPORALITY_CUMULATIVE

processors:
  memory_limiter:                              # FIRST
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
  resource_detection:
    detectors: [env, system, docker]
    timeout: 5s
    override: false
  cardinality_guardian: {}                     # fleet-level cardinality backstop
  delta_to_cumulative:                         # only if producers send delta
    max_stale: 30m
    max_streams: 50000
  filter/drop-noise:
    error_mode: ignore
    metrics:
      datapoint: ['attributes["http.route"] == "/healthz"']
  batch:                                       # LAST
    send_batch_size: 8192
    timeout: 5s

exporters:
  prometheus_remote_write:
    endpoint: http://mimir:9009/api/v1/push
    external_labels: {cluster: prod-eu-west-1}
    sending_queue: {enabled: true, num_consumers: 10, queue_size: 5000}
    retry_on_failure: {enabled: true, initial_interval: 5s, max_interval: 30s, max_elapsed_time: 300s}
    timeout: 30s

service:
  telemetry:
    metrics:
      level: detailed
      readers:
        - pull:
            exporter:
              prometheus: {host: 0.0.0.0, port: 8888}
  pipelines:
    metrics/spans:
      receivers: [otlp]
      processors: [memory_limiter]
      exporters: [span_metrics]                # connector as exporter
    metrics:
      receivers: [otlp, prometheus, host_metrics, span_metrics]   # connector as receiver
      processors: [memory_limiter, resource_detection, cardinality_guardian, delta_to_cumulative, filter/drop-noise, batch]
      exporters: [prometheus_remote_write]
```

★ **Note the two-pipeline connector pattern.** `span_metrics` appears as an **exporter** in `metrics/spans` (fed from traces) and as a **receiver** in `metrics`. In a real config you'd also have the traces pipeline exporting to `span_metrics`. Get both roles wired or the Collector won't start.

---

## Red flags

| Doing this | Costs you |
|---|---|
| `ObservableGauge` for a count of events | Aliasing; you miss everything between collections and can't compute a rate |
| Blocking work in an async callback | Stalls all metric collection; exports miss deadlines |
| Registering a callback per request | Leaks and multiplies readings |
| Exporting delta to Prometheus remote-write | Silently wrong values |
| `delta_to_cumulative` across multiple Collectors without consistent routing | Partial totals → wrong sums. Route by `streamID` or `metric` |
| `delta_to_cumulative` with unbounded `max_streams` | OOM on a cardinality spike |
| `delta_to_cumulative` with `max_streams` too low | Evictions → accumulation resets → wrong values |
| Histogram buckets not aligned to SLO thresholds | You can't accurately answer "what fraction exceeded the SLO" |
| "Add more buckets for accuracy" | Each bucket is a series. It's a cost decision |
| Averaging p99s across instances | Invalid in any format |
| `k8s.pod.name` / `user_id` / `url.full` as metric attributes | Cardinality multiplication. Those belong on spans and logs |
| Denylist filtering for cardinality | Fails **open** when an upgrade adds an attribute. Use allowlists |
| No cardinality limit set | No safety net; the TSDB finds the limit for you |
| Not alerting on the overflow series | You lose detail silently |
| `resource_to_telemetry_conversion: enabled` with a fat resource | Every resource attribute becomes a label on every series |
| Assuming push gives you an `up` metric | It doesn't. Silence looks like no traffic — build `absent_over_time()` alerts |
| Exemplars enabled with 1% uniform head sampling | 99% of your metric→trace links are dead. Tail-sample slow traces instead |
| No `metric_expiration` on the Prometheus exporter | Dead series linger and inflate cardinality |
| Not checking the unit field on semconv migration | V0 HTTP duration was **ms**, V1 is **s** — a 1000× dashboard error |

---

## Rapid recall

1. **Choose the instrument by two questions: event or state? monotonic or not?** Events → Counter/UpDownCounter/Histogram. State → Observable*. ★ `ObservableGauge` for event counts is the #1 mistake (aliasing).
2. **Async callbacks run in the SDK's collection thread** (default 60 s): cheap, non-blocking, read a cached value, don't throw, register once. A 60 s interval means a 30 s incident can produce **zero points**.
3. **Temporality: cumulative = since start (Prometheus-native, robust to missed exports); delta = since last report (Datadog/CloudWatch, LB-friendly, restart-friendly, loses data if an export drops).** `lowmemory` = delta for sync + cumulative for async.
4. ★ **`prometheus_remote_write` requires cumulative.** Convert with `delta_to_cumulative`, which is **stateful**: bound it with `max_streams`/`max_stale`, alert on evictions, and **route consistently** (`load_balancing` with `routing_key: streamID` or `metric`) across a Collector fleet or the reconstruction is wrong.
5. **Diagnose temporality in 60 s:** plot the raw series. Monotonic with restart resets = cumulative; oscillating small positives = delta. Or check whether `start_time_unix_nano` advances.
6. **Histogram buckets must align to your SLO thresholds** — quantiles are interpolated *within* a bucket, so a 500 ms SLO needs a 500 ms boundary. Every bucket is a series: bucket count is a cost multiplier.
7. **Exponential histograms** give bounded *relative* error with no bucket guessing, but **aren't native to Prometheus**. Known range + Prometheus → explicit; unknown/wide range → exponential.
8. ★ **Cost = streams × points × retention, and streams are the PRODUCT of attribute cardinalities.** Adding `k8s.pod.name` (500 values) multiplies cost by 500. **High-cardinality attributes belong on spans and logs, never metrics.**
9. **Cardinality controls, best first:** SDK **view allowlists** (`attribute_keys.included`, fails *closed*) → `OTEL_METRIC_CARDINALITY_LIMIT` with the overflow series alerted → Collector **`cardinality_guardian`** → `filter`/`attributes` processors.
10. **Exemplars are the metric→trace bridge** and the best UX win available. ★ **They only work if the referenced trace was sampled** — which couples your sampling policy to your metrics: tail-sample slow traces, don't head-sample uniformly at 1%.
11. **Three Prometheus paths:** **A** scrape with the `prometheus` receiver (Target Allocator in K8s; receiver must be named exactly `prometheus`), **B** expose with the `prometheus` exporter (most common; **renames metrics and adds `_total`/`_seconds`/`_bucket` suffixes by default**), **C** remote-write (needs cumulative). Using all three at once is normal.
12. ★ **Push has no `up` metric.** Silence looks like no traffic. Build `absent()`/`absent_over_time()` alerts, watch `otelcol_receiver_refused_metric_points`, emit a heartbeat, and expose `health_check`.
13. **Pipeline order: `memory_limiter` first → `resource_detection` → cardinality guard → temporality conversion → filter → `batch` last.** And expose the Collector's own metrics on `:8888` — you cannot debug a pipeline you can't see.

→ Next: [`07-logs.md`](07-logs.md)
