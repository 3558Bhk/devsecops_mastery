# Lab 04 — Metrics into Prometheus: Temporality, Naming, and the Three Paths

**Goal:** make the four ways OTel metrics reach Prometheus concrete, then break the two that fail **silently** — temporality and name transformation.

**Time:** 45–60 minutes. **Prerequisites:** Docker, ~4 GB RAM.

**Read [`../../06-metrics.md`](../../06-metrics.md) first** (instruments, aggregation temporality, cardinality), and skim [`../../14-scale-cost-and-cardinality.md`](../../14-scale-cost-and-cardinality.md) for the cost consequences of every choice here.

---

## The four paths

| # | Path | Direction | Where configured | In this lab |
|---|---|---|---|---|
| **A** | App → Collector (OTLP) | push | app env + `otlp` receiver | ✅ always on |
| **B** | Collector → Prometheus via `prometheus` **exporter** | **pull** (Prometheus scrapes `:8889`) | `prometheus.yml` job `otel-collector-export` | ✅ always on |
| **B'** | Collector → Prometheus via `prometheus_remote_write` | **push** | collector `exporters` | ✅ always on |
| **C** | Collector **scrapes** Prometheus-format targets | pull | `prometheus/self`, `prometheus/app` receivers | ✅ always on |
| **D** | App → Prometheus **directly** (OTLP receiver) | push | `--web.enable-otlp-receiver` | 🔧 Exercise 7 |

```
                    ┌── PATH B  (pull) ──▶ prometheus exporter :8889 ──┐
  checkout ──OTLP──▶│                                                   │
   (app)            ├── PATH B' (push) ─▶ prometheus_remote_write ──────┼──▶ Prometheus
                    │                                                   │      :9090
                    └── PATH C  (pull) ──▶ prometheus/* receivers ──────┘
```

---

## Run it

```bash
cd labs/lab-04-metrics-and-prometheus
docker compose up -d --build
docker compose ps
```

| URL | What |
|---|---|
| **http://localhost:3000** | Grafana → *OpenTelemetry Labs* → **Lab 04 — Metrics & Prometheus** |
| **http://localhost:9090** | Prometheus (Explore → try the queries below) |
| http://localhost:8000 | Demo app |
| **http://localhost:8889/metrics** | ★ Path B endpoint — **the naming transformation, live** |
| http://localhost:8888/metrics | Collector internal telemetry |
| http://localhost:3200 | Tempo |

```bash
docker compose down -v
```

---

## Exercise 1 — ★ The naming transformation (do this first, it explains most "missing metric" tickets)

Open **http://localhost:8889/metrics** and search. Your OTel metric did not keep its name:

| OTel name (what the SDK emits) | Prometheus name (what you must query) | Why |
|---|---|---|
| `http.server.request.duration` | `http_server_request_duration_seconds_bucket` | dots→underscores, `_bucket` histogram suffix, **`_seconds` unit suffix** |
| `traces.span.metrics.calls` | `traces_span_metrics_calls_total` | connector namespace + **`_total` counter suffix** |
| `traces.span.metrics.duration` | ★ `traces_span_metrics_duration_milliseconds_bucket` | **unit is `ms`**, so `_milliseconds` |
| `trace.span.count` | `trace_span_count` | connector default name |
| `otelcol_receiver_accepted_spans` | unchanged | internal telemetry is already Prometheus-shaped |

**The rule:** the Prometheus exporter appends **`_total`** (counters), **`_bucket`/`_sum`/`_count`** (histograms) and a **unit suffix** derived from the OTel instrument's unit.

**Then try to disable it** — edit the collector config:
```yaml
  prometheus:
    endpoint: 0.0.0.0:8889
    add_metric_suffixes: false      # ★ DEPRECATED AND IGNORED
```
```bash
docker compose restart collector
curl -s localhost:8889/metrics | grep -c '_total'
```

★ **The suffixes are still there.** `add_metric_suffixes` has been **deprecated and IGNORED** — setting it to `false` does nothing. The gate `exporter.prometheusexporter.DisableAddMetricSuffixes` is TRUE, whose real effect (verified in source) is that **`translation_strategy` always governs**: unset resolves to `UnderscoreEscapingWithSuffixes`.

To actually change naming you must set the strategy explicitly:
```yaml
    translation_strategy: UnderscoreEscapingWithoutSuffixes
```
★ **Never do this in production** — it produces non-conforming Prometheus names that break `rate()` conventions and PromQL style guides. But knowing the knob exists is what stops you fighting `add_metric_suffixes` forever.

---

## Exercise 2 — ★★ Temporality: the silent correctness trap

Set the app to emit **delta**:
```bash
# in docker-compose.yml, on the checkout service:
OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE: delta
docker compose up -d --force-recreate checkout
```

**Now watch what does NOT happen: nothing errors.** Prometheus happily accepts it. Grafana renders a chart. The Collector logs are clean.

**But look at a counter:**
```promql
increase(traces_span_metrics_calls_total{service_name="checkout-service"}[5m])
```

Compare against cumulative. ★ **With delta data arriving at a cumulative-expecting store, counters appear to reset constantly and `rate()`/`increase()` return nonsense** — usually *lower* than reality, sometimes wildly so. **This is the worst failure class in observability: wrong numbers, no error.**

**The fix lives in the Collector**, and it's already in this lab's config:
```yaml
processors:
  delta_to_cumulative:
    max_stale: 5m      # ★ bounded so a churny stream set can't grow memory forever
```

**Comment out `delta_to_cumulative` from the `metrics` pipeline processors list**, restart, and compare again. Then restore it.

**Now the scaling consequence.** `delta_to_cumulative` is **stateful** — it must see every datapoint of a stream in order:

> ★ In a multi-replica fleet it requires **consistent routing** — `load_balancing` with `routing_key: streamID` or `metric`. Get the routing wrong and you get **wrong totals with NO errors**.

If two replicas each see half a stream's deltas, neither can reconstruct the cumulative value. Both emit plausible-looking, wrong numbers. **You cannot detect this from the data.** You can only prevent it from the architecture.

**Decision table:**

| Backend wants | SDK/producer emits | Action |
|---|---|---|
| Cumulative (Prometheus) | Cumulative | nothing |
| Cumulative (Prometheus) | **Delta** | ★ `delta_to_cumulative` **with consistent routing** |
| Delta (many cloud backends) | Delta | nothing |
| Delta (many cloud backends) | Cumulative | usually the backend converts; check first |

Restore `cumulative` and the processor.

---

## Exercise 3 — `span_metrics` vs Tempo's `metrics_generator` (the duplicate-metrics trap)

**Both are running in this lab at the same time**, which is deliberate.

| | Collector `span_metrics` | Tempo `metrics_generator` |
|---|---|---|
| Runs where | Collector | Tempo |
| Metric names | `traces.span.metrics.calls` → `traces_span_metrics_calls_total` | `traces_spanmetrics_calls_total`, `traces_service_graph_*` |
| Duration unit | ★ **milliseconds** (`useSecondAsDefaultMetricsUnit` = FALSE) | **seconds** (gate `connector.servicegraph.legacyLatencyUnitMs` = FALSE) |
| Exemplars | via remote-write `send_exemplars` | ★ `send_exemplars: true` in tempo.yaml |
| Cost | Collector CPU/memory | Tempo CPU/memory |

**Find the discrepancy yourself:**
```promql
histogram_quantile(0.99, sum by (le) (rate(traces_span_metrics_duration_milliseconds_bucket{service_name="checkout-service"}[5m])))
```
vs. the `traces_service_graph_request_duration_seconds_bucket` series from Tempo.

★ **Two connectors in one pipeline report latency in DIFFERENT UNITS.** `span_metrics` → milliseconds. `service_graph` → seconds (because `legacyLatencyUnitMs` is FALSE). Any dashboard that assumes one unit for both is off by 1000×.

**Then decide which to keep.** Running both doubles your metric ingest for overlapping information.

| Keep Collector `span_metrics` when | Keep Tempo `metrics_generator` when |
|---|---|
| You need custom dimensions / OTTL enrichment | You want metrics with zero Collector cost |
| Multiple backends need the metrics | Tempo is your only trace store |
| You want to filter before exporting | You want service graphs without extra config |

---

## Exercise 4 — The two cardinality limits that are not the same thing

This config sets **both**, at 1000 each:

```yaml
  # Layer 2 — global, per-signal, all processors
  view:
    - name: '*'
      aggregation_cardinality_limit: 1000
```
```yaml
  # Layer 1 — per-connector
  span_metrics:
    aggregation_cardinality_limit: 1000
```

**Break them one at a time.** Set the `view` limit to `10` and restart:
```bash
docker compose restart collector
```

★ **`view`'s limit applies to ALL metrics in ALL pipelines** — it's a blunt global cap. You'll see unrelated metrics start dropping datapoints. That's the difference: the connector's limit only bounds *that connector's* output.

**Note also:** `dimensions_cache_size` still parses but is **DEPRECATED** — `aggregation_cardinality_limit` is the replacement. Both are in the source `Config` struct, which is why the old one doesn't error.

**And the layering, from [`../../14-scale-cost-and-cardinality.md`](../../14-scale-cost-and-cardinality.md):**

| Layer | Mechanism | Scope |
|---|---|---|
| 1 | `span_metrics.aggregation_cardinality_limit` | one connector |
| 2 | `view` / `aggregation_cardinality_limit` | ★ all metrics, all pipelines |
| 3 | `filter` / `transform` | drop or reduce dimensions |
| 4 | `cardinality_guardian` (Alpha) | HLL++ delta estimation, metrics-only |
| 5 | Backend limits | last resort |

**Dropping at layer 5 is the most expensive possible place to discover the problem.**

---

## Exercise 5 — ★ Point the Collector's scraper at something that doesn't exist

`prometheus/app` currently scrapes `prometheus:9090`, which works. Repoint it at the app:

```yaml
  prometheus/app:
    config:
      scrape_configs:
        - job_name: scraped-by-collector
          scrape_interval: 10s
          static_configs:
            - targets: ["checkout:8000"]     # ★ FastAPI has no /metrics endpoint
```
```bash
docker compose restart collector
docker compose logs -f collector | grep -i -E "scrape|error"
```

**The FastAPI app does not expose `/metrics`** — zero-code instrumentation sends OTLP, it doesn't serve a Prometheus endpoint. So the scrape fails.

**Then check:**
```promql
otelcol_receiver_refused_metric_points
up{job="otel-collector"}
```

**Two things worth internalising:**
1. ★ **A failed scrape is noisy; a silently-misnamed metric is not.** Prefer failures that announce themselves.
2. **If you need a Prometheus endpoint from a Python app**, add `opentelemetry-exporter-prometheus` and mount its handler — or keep using OTLP push, which is what zero-code gives you.

Restore `prometheus:9090`.

---

## Exercise 6 — The double-ingest problem (and how to see it)

Paths **B** (pull) and **B'** (push) are both on, so the same series exists twice, distinguished by job label:

```promql
count(count by (__name__, job) ({job=~"otel-collector-export|scraped-by-collector"}))
```

**Look at what `scraped-by-collector` produces.** Prometheus scrapes itself directly (job `prometheus`) *and* the Collector scrapes `prometheus:9090` and remote-writes it back. Same target, two owners, two series sets with different labels.

**This is the mistake this lab exists to surface:**
> ★ Running both permanently for the same data **doubles your ingest** and gives you two sets of series that **disagree slightly** (different scrape times, different relabelling, one has exemplars and one doesn't). Pick one.

**How to pick:**

| Choose PULL (`prometheus` exporter) when | Choose PUSH (`prometheus_remote_write`) when |
|---|---|
| Prometheus lives in the same network | The backend is remote / managed / behind NAT |
| You want Prometheus to own scraping & relabelling | You want the Collector to own routing & enrichment |
| You need `up` and scrape health for free | ★ You need **exemplars** (metric→trace) |
| Simple single-destination | Fan-out to several backends |

★ **The exemplar asymmetry matters:** remote-write with `send_exemplars: true` carries exemplars; a scrape of the exporter endpoint does not preserve them the same way. If you want metric→trace clickthrough on backend-generated series, push is the path.

**Then disable one** and confirm your dashboards still work with the other.

---

## Exercise 7 — Path D: Prometheus's own OTLP receiver

Already enabled (`--web.enable-otlp-receiver`), so no restart needed. Point the app straight at Prometheus, bypassing the Collector entirely:

```bash
# add to the checkout environment in docker-compose.yml:
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT: http://prometheus:9090/api/v1/otlp/v1/metrics
docker compose up -d --force-recreate checkout
```

```promql
count({job="otlp"})
```

**It works.** Which raises the real question:

★ **If Prometheus can ingest OTLP directly, why run a Collector at all?**

| You still need the Collector for | You don't, if |
|---|---|
| Tail sampling (stateful, needs all spans) | Single backend, push-only |
| Fan-out to multiple backends | No enrichment needed |
| Redaction / PII scrubbing | Trust your SDKs completely |
| `filter` / `transform` / cardinality control | Volume is low and stable |
| Batching, queuing, retry at the edge | Apps can afford it |
| Zero-code instrumentation of third-party services | You own every service |

**Honest answer for a small estate:** you may not need one for metrics. **You almost always need one for traces** — because tail sampling and cardinality control have nowhere else to live.

---

## Exercise 8 — Native histograms and exponential buckets

`span_metrics` uses **explicit** buckets here:
```yaml
    histogram:
      explicit:
        buckets: [5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s]
```

★ **Eleven fixed boundaries.** If your real latency is 3s, every request lands in the last bucket and your p99 is *wrong* — you get an interpolated guess from an empty range. If it's 200µs, everything lands in the first bucket.

Switch to **exponential**, which adapts:
```yaml
    histogram:
      exponential:
        max_size: 160      # ★ bucket count; higher = more resolution, more series
```

Then enable native histograms in Prometheus (uncomment in `docker-compose.yml`):
```
- --enable-feature=native-histograms
```
```bash
docker compose up -d --force-recreate prometheus collector
```

**Compare resolution and cost.** ★ **Exponential histograms trade a fixed bucket list for a scale + bucket counts, so they resolve any latency range — but each is its own series and native-histogram support in your backend is not universal.** Check before you commit.

| | Explicit | Exponential |
|---|---|---|
| Buckets | Fixed list you choose | Adaptive (scale-based) |
| Wrong-range risk | ★ **High** — pick badly, get nonsense percentiles | Low |
| Series cost | `len(buckets)+3` per dimension set | Bounded by `max_size` |
| Backend support | Universal | ★ Check first |

Restore explicit buckets.

---

## The red flags

| Symptom | ★ Cause |
|---|---|
| **`rate()` returns nonsense, no errors anywhere** | **Delta temporality hitting a cumulative store** — add `delta_to_cumulative` |
| **Wrong totals in a multi-replica fleet, no errors** | **`delta_to_cumulative` without consistent routing** — `load_balancing` `routing_key: streamID`/`metric` |
| **Metric "missing" in Prometheus** | **Name transformation** — dots→underscores + `_total`/`_seconds`/`_bucket` suffixes |
| **`add_metric_suffixes: false` has no effect** | **DEPRECATED AND IGNORED** — use `translation_strategy` |
| **`span_metrics` p99 is 1000× off** | **Unit is milliseconds**, not seconds (`useSecondAsDefaultMetricsUnit` = FALSE) |
| **Two connectors disagree on latency** | **`span_metrics` = ms, `service_graph` = s** (`legacyLatencyUnitMs` = FALSE) |
| **`duplicate dimension name "service.name"`** | **It's already a default dimension** — don't re-list it |
| **Metric counts double after a change** | **Both pull and push paths on** — pick one |
| **Filter silently does nothing** | **`error_mode` defaults to `ignore`** (gate TRUE/Stable) — use `propagate` while developing |
| **Series count explodes** | **`resource_to_telemetry_conversion.enabled: true`** promotes every resource attr to a label |
| **`num_shards`-style division surprise** | Rate limits divide across shards; **`burst_capacity` does not** |

## Rapid recall

- OTel `http.server.request.duration` → Prometheus **`http_server_request_duration_seconds_bucket`**.
- `add_metric_suffixes` is **DEPRECATED AND IGNORED**; **`translation_strategy`** governs.
- Prometheus needs **CUMULATIVE**. Delta → `delta_to_cumulative`, which is **STATEFUL** and needs **consistent routing**.
- `span_metrics` duration = **milliseconds**; `service_graph` latency = **seconds**.
- `service.name` / `service.instance.id` are **default dimensions** — re-listing them fails validation.
- `dimensions_cache_size` is **DEPRECATED** → `aggregation_cardinality_limit`.
- Prometheus **has an OTLP receiver** (`--web.enable-otlp-receiver`, `/api/v1/otlp/v1/metrics`) — Path D.
- ★ **Don't run pull and push for the same data permanently.**
- The five cardinality layers, cheapest first: **connector limit → `view` limit → `filter`/`transform` → `cardinality_guardian` → backend**.

---

## What you should now be able to answer

1. Why is my metric missing from Prometheus? → **Name transformation. Query `http_server_request_duration_seconds_bucket`, not `http.server.request.duration`.**
2. What breaks if delta temporality reaches Prometheus? → ★ **Nothing errors. Counters look reset; `rate()` is wrong. Silent.**
3. What makes `delta_to_cumulative` dangerous at scale? → ★ **It's stateful. Without consistent routing across replicas you get wrong totals and no errors.**
4. Can I disable Prometheus name suffixes? → **`add_metric_suffixes` is ignored. `translation_strategy` can, but don't.**
5. Should I use the Collector's `span_metrics` or Tempo's `metrics_generator`? → **Pick one. Both = double ingest, different units, slight disagreement.**
6. Does Prometheus need a Collector? → **For metrics, maybe not — it has an OTLP receiver. ★ For traces, yes: tail sampling and cardinality control live nowhere else.**
7. Explicit or exponential buckets? → **Exponential adapts to any range; explicit fails silently if you pick boundaries badly.**

→ Next: [`../lab-05-logs-and-correlation/`](../lab-05-logs-and-correlation/) · Back: [`../README.md`](../README.md)
