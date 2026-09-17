# 14 · Scale, Cost & Cardinality

The file that decides whether your observability platform is an asset or a line item nobody can explain. **Everything here is verified against `otelcol-contrib` v0.161.0**, including the full `cardinality_guardian` configuration passed through `validate`.

---

## 14.1 The cost model — get this right and everything else follows

Each signal is dominated by a different variable. **Optimising the wrong one is the most common waste in observability.**

| Signal | Cost driver | The lever | The anti-pattern |
|---|---|---|---|
| **Metrics** | ★ **Cardinality** (distinct series) | Attribute allowlists, cardinality limits, `cardinality_guardian`, downsampling | Adding "just one more label" |
| **Traces** | **Volume** (spans × bytes/span) | Sampling, span-name normalisation, attribute trimming, dropping health checks | Keeping 100% because storage is cheap |
| **Logs** | ★ **Volume × retention** | Filtering at the edge, severity gating, dedup, tiered retention | DEBUG in production, 400-day hot retention |
| **Profiles** | Sample rate × duration × process count | Sampling rate, scoping to specific nodes | Leaving allocation profiling on everywhere |

### The metrics arithmetic, concretely

**Series count = the product of distinct values across every attribute.**

| Attributes on `http.server.request.duration` | Distinct | Cumulative series |
|---|---|---|
| `http.request.method` | 5 | 5 |
| `http.route` | 80 | 400 |
| `http.response.status_code` | 12 | 4,800 |
| `service.name` | 40 | 192,000 |
| `deployment.environment.name` | 3 | 576,000 |
| **`k8s.pod.name`** | **500** | **288,000,000** ☠️ |

**One label multiplied your cost by 500.** At 15 s resolution and $0.05 per 1,000 series-month, that's the difference between $29k/month and $14.4M/month. The numbers are extreme to make the point, but the *shape* is real and it is why metric cardinality is treated as a first-class engineering risk.

**Points, not just series:** `288M series × 4 points/min × 43,200 min/month` — the ingest rate matters too, but **series count drives index size and query cost**, which is what your bill reflects.

### The logs arithmetic
```
500 services × 200 lines/sec × 500 bytes/line
  = 50 MB/s = 4.3 TB/day = 130 TB/month
At $0.50/GB ingested:      $65,000/month ingest
At $0.03/GB/month stored:  $3,900/month storage (30 days)
```
★ **Filtering out health-check and readiness access logs — typically 40–70% of that volume — is a $25k–45k/month change and costs one Collector processor.** That's the highest-yield single action available in most observability estates, and it loses *zero* information value.

### The traces arithmetic
```
10,000 traces/sec × 20 spans × 500 bytes = 100 MB/s = 8.6 TB/day
Tail sampling keeping 100% errors + 100% slow + 5% rest ≈ 10–15% retained
→ ~1 TB/day
```
★ **Note that tail sampling here saves ~85% while keeping ~100% of what anyone would look at.** That decoupling of cost from value is the entire argument for tail sampling ([`10-sampling.md`](10-sampling.md)).

---

## 14.2 Cardinality control — the layered defence

Five layers. **Use several; any one alone fails eventually.**

### Layer 1 — SDK view allowlists ★ (strongest, earliest)
```yaml
views:
  - instrument: {name: "http.server.request.duration"}
    stream:
      attribute_keys:
        included: [http.request.method, http.route, http.response.status_code, url.scheme]
```
★ **Why allowlists beat denylists:** a denylist (`excluded: [user_id]`) fails **open**. The next instrumentation upgrade adds `http.request.header.x_session_id` and nobody notices for three weeks — until the bill arrives. An allowlist fails **closed**: new attributes are dropped until someone deliberately adds them.

**Cost:** it lives in application configuration, so it's per-service and requires a deploy to change. That's the price of the strongest guarantee.

### Layer 2 — SDK cardinality limits (the safety net)
```bash
OTEL_METRIC_CARDINALITY_LIMIT=2000
```
When exceeded, the SDK aggregates overflow into a series carrying **`otel.metric.overflow = true`**. You keep working, lose detail, and get a visible signal.

★ **Alert on the overflow series.** It means your allowlist is wrong or something is leaking. Silent aggregation is much better than silent rejection, but it's still lost information.

### Layer 3 — Collector `filter` processor (drop known noise)
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
        - 'type == METRIC_TYPE_SUM and IsMatch(name, "^go_gc_")'
```
**Alpha stability for all signals** in v0.161.0. ★ **`error_mode` defaults to `ignore`** (`processor.filter.defaultErrorModeIgnore` is **true / Stable** — verified via `otelcol-contrib featuregate`; the `--help` default string is wrong). **A malformed OTTL condition is therefore swallowed silently**, so a filter that looks like it's working may be doing nothing. Set `error_mode: propagate` while developing.

### Layer 4 — Collector `attributes` / `transform` (reduce a dimension)
```yaml
processors:
  transform/reduce-dimensions:
    error_mode: ignore
    metric_statements:
      - context: datapoint
        statements:
          # collapse the pod dimension — keep the deployment
          - delete_key(attributes, "k8s.pod.name")
          # bucket status codes: 200/201/204 → 2xx
          - replace_pattern(attributes["http.response.status_code"], "^2\\d\\d", "2xx")
          - replace_pattern(attributes["http.response.status_code"], "^4\\d\\d", "4xx")
          - replace_pattern(attributes["http.response.status_code"], "^5\\d\\d", "5xx")
      - context: resource
        statements:
          # drop resource attributes that would become labels in Prometheus
          - delete_matching_keys(attributes, "^process\\.")
```
★ **Careful with `resource_to_telemetry_conversion: enabled` on the Prometheus exporters** — it turns **every** resource attribute into a label on **every** series. A resource with 25 attributes creates 25 labels. Convenient, and a cardinality multiplier you didn't choose deliberately.

### Layer 5 — Collector `cardinality_guardian` ★ (the dynamic, fleet-wide backstop)

This is the newest and most interesting control, and it does something the others can't: **it detects cardinality explosions you didn't predict.**

**Stability: Alpha, metrics only, contrib distribution.**

**The problem it solves, in the upstream's own framing:**
> *"A code change introduces raw exception strings into `error.type`. Yesterday that label had 5 unique values. Today it has 50,000 and climbing. Your TSDB bill noticed before you did."*

Layers 1–4 are all **configuration-driven**: you tell them what to drop. `cardinality_guardian` is **data-driven**: it figures out what to drop from observed behaviour. ★ **The use cases are complementary, not competing.**

#### How it works
```
Metric arrives → hash metric name → select 1 of 256 shards
   → for each label: hash the value, insert into an HLL++ sketch
   → is the DELTA > threshold?
        no  → pass through
        yes → apply enforcement mode
```

**Four design decisions worth understanding:**

1. ★ **Delta-based detection, not absolute thresholds.** It measures **new unique values per epoch**, not total cardinality. *"A label with 50K stable values is fine. A label that grew by 100 in the last epoch is a problem."* It tracks growth rate using **dual-epoch HyperLogLog++ sketches**, so legitimately high-cardinality metrics aren't penalised. **This is why it has no false positives on stable high-cardinality data** — which `filter` and `metrics_transform` both do.

2. **256-way sharding**, each with its own `RWMutex`. Shard selection is `hash & 0xFF` — one CPU cycle. With 50 concurrent goroutines across 256 shards, average occupancy is ~0.4 per shard, so contention is near zero.

3. **HLL++ at ~2 KB per tracker**, 1–2% accuracy, estimating cardinality identically whether 100 or 100M unique values have been observed. Uses `axiomhq/hyperloglog`'s `InsertHash(uint64)` path to avoid allocation on the hot path.

4. **Stale eviction** — trackers unseen for two epochs are cleaned up, so **memory stays bounded**.

#### Configuration (verified valid on v0.161.0)
```yaml
processors:
  cardinality_guardian:
    # Max NEW unique values per (metric, attribute) per epoch
    max_cardinality_delta_per_epoch: 100

    # Epoch rotation interval in seconds (★ minimum 10)
    epoch_duration_seconds: 300

    # tag_only | overflow_attribute | strip_and_reaggregate
    enforcement_mode: tag_only

    # Labels never stripped regardless of cardinality
    never_drop_labels:
      - region
      - environment
      - service.name

    # Per-metric threshold overrides (falls back to the global value)
    metric_overrides:
      http.server.request.duration: 5000
      db.query.duration: 50

    # Emit a gauge with the top N highest-delta trackers
    top_offenders_count: 10

    # Max tracked metric+label pairs (0 = unlimited)
    max_tracker_count: 100000

    # Dollar value per series prevented — for ROI dashboards
    estimated_cost_per_metric_month: 0.05

    # Cap enforcement Warn logs per epoch (0 = unlimited)
    drop_log_max_per_epoch: 10
```

#### The three enforcement modes ★

| Mode | Behaviour | Protects your TSDB? |
|---|---|---|
| **`tag_only`** | Preserves all attributes, injects **`otel.metric.overflow: true`** on exceeding data points. Nothing modified. *"The safest mode and recommended for initial deployment"* | ★ **NO — not on its own.** High-cardinality labels still reach the backend unchanged. **You must pair it with a downstream `routing` connector** to split tagged metrics to cheap storage |
| **`overflow_attribute`** | Replaces the offending value with the sentinel **`otel.cardinality_overflow`**, then performs **inline spatial reaggregation** to merge data points that now share that identity — resolving the Single-Writer violation. Aligned with the OTel SDK cardinality-overflow convention | **Yes**, for supported metric types |
| **`strip_and_reaggregate`** | **Removes the attribute entirely**, then reaggregates. ★ *"The metric stays intact — only the bad label is removed."* | **Yes**, for supported metric types |

**The upstream's illustrative example of `strip_and_reaggregate`:**
```
Before:  {region="us-east", status="200", error.type="Lock wait timeout; txn=a3f9c..."}
After:   {region="us-east", status="200"}
```
*"`region` and `status` survive. Your latency dashboards keep working. The 50,000 unique exception strings are gone."*

★ **This is the key property: it strips the exploding label, not the data point.** Compare `filter`, which drops the entire metric.

#### Reaggregation support — the honest limitation ★

Both `strip_and_reaggregate` and `overflow_attribute` rely on inline spatial reaggregation, which is **only safe for some metric types**:

| Metric type | Reaggregation | Merge semantics |
|---|---|---|
| **Delta Sum** | ✅ Supported | Values summed; timestamps span the union |
| **Gauge** | ✅ Supported | Last-value-wins by timestamp |
| **Cumulative Sum** | ⚠️ **Falls back to `tag_only`** | Requires stateful tracking (not yet supported) |
| **Histogram** | ⚠️ **Falls back to `tag_only`** | Bucket merging needs careful alignment |
| **ExponentialHistogram** | ⚠️ **Falls back to `tag_only`** | Scale alignment not implemented |
| **Summary** | ⚠️ **Falls back to `tag_only`** | Quantile merging is mathematically invalid |

★ **Read that table before you deploy it.** If your exploding label is on a **histogram** — which is exactly where `http.server.request.duration` lives, and exactly where `error.type` explosions happen — **the processor falls back to `tag_only` and does not protect your backend.** You get a tag and an alert, not enforcement.

Upstream is explicit about why: *"collapsing multiple cumulative streams (or merging histogram buckets across mis-aligned scales) is what reaggregation has to solve in the first place"* — so `overflow_attribute` is not a valid fallback for those types either. The fallback is `tag_only` **with an `otel.metric.overflow` tag, ensuring no data corruption.**

**Practical consequence:** for histograms, `cardinality_guardian` in `tag_only` + a **`routing` connector** sending tagged data to cheap storage is the working pattern today. Support for cumulative sums and histogram bucket-aligned merging is tracked as future work.

#### Why the Single-Writer warning matters
> *"Both intentionally cause attribute identity collisions and rely on inline spatial reaggregation to merge them."*

★ **OTel's metrics model assumes one writer per stream.** Stripping an attribute makes two previously-distinct streams collide into one identity. If you don't merge them correctly, the backend sees two writers for one series — which for cumulative counters produces corruption, not just noise. That's precisely why cumulative/histogram types fall back rather than risk it. **This is a well-designed safety choice, not a bug.**

Also noted upstream: identity hashing uses **`xxhash`** with per-`pcommon.ValueType` dispatch and a multiplicative key/value mix to stay **order-independent**. Theoretical collisions are possible but vanishingly rare.

#### Its internal metrics — how you operate it

| Metric | Type | Description |
|---|---|---|
| **`processor_cardinality_trackers.active`** | Gauge | Tracked metric+label pairs across all shards |
| **`processor_cardinality_labels.stripped`** | Counter | Attributes stripped or tagged per data point. ★ **Use `rate()` for spike detection** |
| **`processor_cardinality_top.offenders`** | Gauge | ★ **Top N highest-delta trackers, with `metric_name` and `label_key` attributes** — this tells you *which* label is exploding |
| **`processor_cardinality_trackers.rejected`** | Counter | Trackers rejected after hitting `max_tracker_count` |
| **`processor_cardinality_savings.estimated`** | Counter | **Dollar value of series prevented from reaching your TSDB** |

★ **`processor_cardinality_top.offenders` on the Collector's `/metrics` endpoint is the answer to "what is exploding right now?"** — a question that otherwise requires querying your TSDB for top-N series counts, which is slow exactly when cardinality is high. And `savings.estimated` gives you a **number to put in a cost review**, which is how this work gets funded.

#### Versus the alternatives

| | **`cardinality_guardian`** | `filter` | `metrics_transform` |
|---|---|---|---|
| Detection | ★ **Dynamic (growth rate)** | Static allow/deny lists | Static rules |
| Granularity | ★ **Per-label** | Per-metric (**drops the entire metric**) | Per-metric |
| False positives on stable high-cardinality | ★ **No** (delta-based) | Yes | Yes |
| Tag-only mode | **Yes** | No | No |
| Per-metric overrides | **Yes** | N/A | N/A |
| Top-N offender reporting | ★ **Yes** | No | No |
| Memory per tracker | ~2 KB (HLL++) | N/A | N/A |

#### Recommended deployment sequence
1. **`tag_only`** with `top_offenders_count: 10` and `estimated_cost_per_metric_month` set to your real number. Watch `top.offenders` for a week. **Zero risk, full visibility.**
2. Populate `never_drop_labels` with your genuine identity dimensions (`service.name`, `deployment.environment.name`, region).
3. Add `metric_overrides` for metrics you know are legitimately high-delta.
4. Add a **`routing` connector** sending `otel.metric.overflow == true` data to cheap storage or a dead-letter.
5. **Only then** consider `strip_and_reaggregate` — and only for Delta Sums and Gauges, since histograms fall back anyway.
6. Dashboard `labels.stripped` rate and `savings.estimated`, and review monthly.

---

## 14.3 Volume reduction — the levers that aren't cardinality

### Traces
| Lever | Yield | Where |
|---|---|---|
| **Tail sampling** | ★ 80–90% while keeping ~100% of interesting traces | Gateway |
| **Drop health checks and readiness probes** | 5–30% | Agent, `filter` processor |
| **Normalise span names** | Prevents index explosion (not bytes) | `transform` / `span` processor |
| **Trim `exception.stacktrace`** | 10–40% of error-heavy traces | `transform` |
| **Cap attributes per span** | Bounded | SDK span limits |
| **Drop noisy instrumentation scopes** | Variable | `filter` on `scope.name` |
| **`span_pruning` processor** | Variable | Newer contrib component |
| **OTel Arrow (`otelarrow`)** | ★ **~80% wire compression** | Exporter/receiver pair, both ends |

```yaml
processors:
  filter/edge-noise:
    error_mode: ignore
    traces:
      span:
        - 'attributes["url.path"] == "/healthz"'
        - 'attributes["url.path"] == "/readyz"'
        - 'attributes["http.route"] == "/metrics"'
        - 'scope.name == "opentelemetry.instrumentation.urllib3" and attributes["http.status_code"] == 200'
```

### Logs
| Lever | Yield | Where |
|---|---|---|
| **Don't emit it** | Highest | Application code / log level |
| ★ **Filter health-check access logs at the edge** | **40–70%** | Agent DaemonSet, **before data leaves the node** |
| **Severity gating** (`severity_number < 9` for noisy services) | 20–50% | `filter` |
| **`log_dedup` processor** | High during retry/crash storms | Collector — collapses repeated identical records with a count |
| **Truncate long messages** | Variable | `transform` |
| **Sample DEBUG only** | Variable | `probabilistic_sampler` (**Alpha for logs**) |
| **Tiered retention** | Large | Backend lifecycle policies |

★ **Filter at the edge, not at the backend.** Dropping at the vendor's ingest still pays egress and still costs you the ingestion CPU. Dropping in the node agent means the bytes never leave the machine.

### Metrics
| Lever | Yield | Where |
|---|---|---|
| **Cardinality control** (above) | ★ Largest by far | SDK views → limits → Collector |
| **Drop unused metrics entirely** | Variable | `filter` |
| **Increase the collection interval** | Proportional | SDK / `prometheus` receiver `scrape_interval` |
| **Downsample on retention** | ★ Large for long retention | Backend (Thanos/Mimir compactor) |
| **Fewer histogram buckets** | Proportional to buckets removed | Views / `span_metrics` config |

---

## 14.4 Scaling the Collector fleet

### Horizontal scaling — what scales and what doesn't

| Component | Scales horizontally? | Why |
|---|---|---|
| Stateless receivers/processors/exporters | ✅ **Yes** | Any instance can handle any data |
| **`tail_sampling`** | ⚠️ **Only with consistent routing** | All spans of a trace must reach one instance → `load_balancing` with `routing_key: traceID` ([`10-sampling.md`](10-sampling.md)) |
| **`delta_to_cumulative`** | ⚠️ **Only with consistent routing** | Stateful per-stream accumulation → route by `streamID` or `metric` |
| **`groupbytrace`** | ⚠️ Same constraint | Buffers incomplete traces |
| **`span_metrics`** | ⚠️ **Route by `service`** | Otherwise multiple instances emit conflicting series for the same `service+operation` → **Prometheus label collisions** |
| **`prometheus` receiver** | ✅ **Via the Target Allocator** | Distributes scrape targets across replicas |
| **`cardinality_guardian`** | ⚠️ Per-instance sketches | Each instance sees only its share, so deltas are per-instance. Route consistently or accept approximate detection |

★ **The rule: stateful components require consistent routing, and the routing key differs per component.** `traceID` for tail sampling, `streamID`/`metric` for temporality conversion, `service` for span metrics. **Getting this wrong produces subtly incorrect data rather than errors** — which is the worst failure class.

### Vertical limits and where they hit
| Limit | Symptom | Fix |
|---|---|---|
| **Memory** | `memory_limiter` refusing, then OOMKill | Raise limits, lower `num_traces`, shorten `decision_wait`, add replicas |
| **CPU** | Export queue rising, `decision_timer_latency` climbing | More replicas, fewer processors, cheaper policies |
| **Single goroutine bottlenecks** | One pipeline hot while others idle | ★ **`num_shards`** on `tail_sampling` (up to 256); multiple pipeline instances |
| **Network / backend rate limits** | `send_failed_*` with 429s | Backoff, `num_consumers`, more backend capacity |
| **Disk** (persistent queues) | Queue not draining across restarts | Faster volume, larger queue, or accept in-memory |

★ **The `tail_sampling` CPU subtlety:** `num_shards` runs parallel event loops, routed by trace-ID hash. It reduces contention between ingestion and decision evaluation. But remember: **`num_traces`, cache sizes and per-second rate limits are divided evenly across shards; `burst_capacity` is not** (so aggregate burst scales with shard count), enforcement is approximate for limits smaller than `num_shards`, and **`num_shards > 1` is incompatible with `tail_storage`**.

### Backpressure — how the pipeline protects itself

```
backend slow/unavailable
   → exporter retry_on_failure backs off
   → sending_queue fills
   → queue full → exporter refuses data from the processor
   → processor refuses to the receiver
   → memory rises → memory_limiter fires → receiver REFUSES
   → OTLP receiver returns an error to the SDK
   → SDK retries with backoff, then DROPS (and counts it)
```

★ **This chain is a feature, and the alternative is worse.** Without it, the Collector buffers unboundedly and OOMKills — losing *everything* in flight plus a restart. With it, you shed load progressively and the loss is counted at every stage.

**The consequence for your design:** the SDK's queue and the Collector's queue are **both** loss points, and you should size both. And **alert on the leading indicator** — `otelcol_exporter_queue_size / queue_capacity > 0.8` rises minutes before `send_failed` does.

### Sizing worked example
```
Load:     50,000 spans/sec, 200,000 metric points/sec, 500,000 log records/sec
Traces:   tail_sampling, decision_wait 10s, avg trace 20 spans @ 500 B = 10 KB
          → 5,000 traces/sec in flight × 10s = 50,000 traces buffered
          → 50,000 × 10 KB = 500 MB buffer
          → num_traces: 100,000 (2× headroom), decision_cache 10× that
          → gateway memory limit: 4 Gi (buffer + caches + Go runtime + headroom)
          → memory_limiter limit_percentage: 80  (fires at 3.2 Gi)
Gateway replicas: 3 minimum (N+1 for a rolling deploy), HPA to 8 on memory 70%
Agent DaemonSet:  1 per node, 512Mi–1Gi, no stateful processors
```
★ **Never run a gateway fleet at exactly the replica count you need.** A rolling deploy of a 3-replica fleet with `tail_sampling` means one replica at a time is draining buffered traces. **N+1 is the minimum**, and during deploys you lose the traces buffered on the terminating replica unless `terminationGracePeriodSeconds` covers the drain.

---

## 14.5 Cost attribution and governance

**You cannot control what you cannot attribute.** The sequence that works:

1. **Tag everything with an owner.** `service.name` → team, via the service catalogue. Resource attributes carry `deployment.environment.name`, `k8s.namespace.name`, and (deliberately, at low cardinality) a cost centre.
2. **Measure per-service ingest.** Query the backend for series count / span count / log bytes grouped by `service.name`. Most backends expose this; if yours doesn't, that's a selection criterion you missed ([`13-backends.md`](13-backends.md)).
3. **Publish a monthly showback.** ★ **Visibility alone typically cuts 10–20%** — teams that see their own number behave differently. This is the highest-leverage, lowest-engineering-cost intervention available.
4. **Set per-team budgets with forecast alerts.** Alert at 50/80/100% of a forecast, not of a historical average — the point is to catch growth before the invoice.
5. **Put cost in code review.** A dashboard showing "this PR adds a `user_id` label to a metric with 200k series" changes behaviour at the moment the decision is made.
6. **Track unit economics, not totals.** **Cost per request, per user, per job, per GB processed.** ★ A total that grows with traffic is fine; a *unit* cost that grows is a defect. This is the metric that lets you say "we're 40% more expensive but 3× more efficient" — which is a good outcome and unreportable without unit economics.
7. **Report savings with a number.** `processor_cardinality_savings.estimated` exists precisely for this. So does knowing your $/series-month and $/GB.

### The governance rules worth writing down
- **Metrics get allowlists; traces and logs get volume controls.** Different signals, different levers — don't apply one policy to all three.
- **No new metric attribute without a cardinality estimate.** "How many distinct values, and does that number grow with users?" is the whole review.
- **High-cardinality identifiers (`user_id`, `order_id`, `trace_id`, `session_id`) are permitted on spans and logs, prohibited on metrics.**
- **Every alert must have a runbook, and every dashboard an owner.** Unowned dashboards are unowned cost.
- **Quarterly review of retention.** The cheapest byte is the one you delete — but check compliance first ([`13-backends.md`](13-backends.md)).
- **Sampling policy is a reliability decision, not a cost decision.** Review it with whoever owns incident response, because they're the ones who'll discover the trace they needed was sampled away.

---

## 14.6 Performance tuning checklist

**Collector:**
- [ ] `memory_limiter` first in every pipeline, `check_interval: 1s`, `limit_percentage` consistent with the container limit
- [ ] `batch` last; `send_batch_size` 4096–16384, `timeout` 5–10 s
- [ ] `sending_queue` **enabled** with sized `queue_size`, `num_consumers` ≥ 4, `max_elapsed_time` set
- [ ] `file_storage` extension on a real volume for queues that must survive restarts
- [ ] Internal telemetry `level: detailed`, bound to `0.0.0.0:8888`, scraped and alerted on
- [ ] `timeout` on exporters shorter than the queue drain time
- [ ] No `debug` exporter at `verbosity: detailed` in production
- [ ] `num_shards` on `tail_sampling` if `decision_timer_latency` exceeds ~1 s
- [ ] Custom OCB build or `otelcol-k8s` instead of full contrib where the component set is small

**SDK:**
- [ ] Batch processors with queue sized from `rate × schedule_delay`
- [ ] Span limits set explicitly, with dropped-count metrics alerted on
- [ ] Resource detectors with `timeout` and `override: false`
- [ ] Metric collection interval matched to alerting needs (not blindly 60 s, not blindly 5 s)
- [ ] Views with attribute allowlists for every exported metric
- [ ] `OTEL_METRIC_CARDINALITY_LIMIT` set, overflow series alerted on
- [ ] Async callbacks verified cheap and non-blocking
- [ ] Graceful shutdown flushes providers (★ `tp.Shutdown()` — otherwise every deploy loses buffered telemetry)

**Backend:**
- [ ] Ingest rate, series count and bytes per service measured and published
- [ ] Cardinality limits known and alerted on *before* they're hit
- [ ] Retention tiered, with the compliance reason for each tier written down
- [ ] Downsampling configured for long-retention metrics
- [ ] Cost modelled at 3× and 10× current volume

---

## Red flags

| Doing this | Costs you |
|---|---|
| Optimising trace volume when metrics cardinality is the bill | Wrong lever entirely |
| Denylists for metric attributes | ★ **Fails open** on the next instrumentation upgrade. Use allowlists |
| No `OTEL_METRIC_CARDINALITY_LIMIT` | No safety net; the TSDB finds the limit for you |
| Not alerting on the overflow series | Silent detail loss |
| `resource_to_telemetry_conversion: enabled` with a fat resource | Every resource attribute becomes a label on every series |
| Deploying `cardinality_guardian` in `tag_only` and believing you're protected | ★ **It doesn't protect the TSDB alone** — pair it with a `routing` connector |
| Expecting `cardinality_guardian` to strip histogram labels | ★ **Histograms, cumulative sums, exponential histograms and summaries all fall back to `tag_only`** |
| Filtering logs at the backend instead of the edge | You already paid for egress and ingest CPU |
| DEBUG logging in production | Usually the single largest observability line item |
| No `log_dedup` for retry/crash storms | The same line 100,000× |
| Running gateway replicas at exactly the number you need | A rolling deploy drains one at a time; **N+1 is the minimum** |
| `terminationGracePeriodSeconds` shorter than the drain | Losing buffered traces on every deploy |
| Scaling `tail_sampling` horizontally without consistent routing | Partial traces, wrong decisions — and no errors |
| Multiple `span_metrics` instances routed by `traceID` | **Prometheus label collisions** |
| Multiple `delta_to_cumulative` instances without routing by `streamID` | Wrong cumulative totals, silently |
| Alerting only on `send_failed` | ★ Lagging. `queue_size / queue_capacity > 0.8` is the leading indicator |
| Tracking total cost but not unit cost | Can't distinguish healthy growth from a defect |
| No showback | ★ Visibility alone typically cuts 10–20%, for near-zero engineering effort |
| Treating sampling as a cost decision only | It's a reliability decision — the on-call team discovers what you dropped |

---

## Rapid recall

1. **Each signal has a different cost driver:** metrics → ★ **cardinality**; traces → **volume** (spans × bytes); logs → **volume × retention**; profiles → sample rate × duration × process count. **Optimising the wrong one is the most common waste.**
2. **Metrics cost is the PRODUCT of attribute cardinalities.** Adding `k8s.pod.name` (500 values) to a 576k-series metric makes it 288M. **High-cardinality identifiers belong on spans and logs, never on metrics.**
3. **Logs: filtering health-check/readiness access logs at the edge typically removes 40–70% of volume** — usually a $25k–45k/month change for one Collector processor, at zero information loss. ★ **Filter at the edge, not the backend**: bytes dropped at the vendor still cost egress and ingest CPU.
4. **Traces: tail sampling saves ~85% while keeping ~100% of what anyone would look at.** ★ That decoupling of cost from value is the entire argument for it. Also: drop health checks, trim `exception.stacktrace`, cap span attributes, and consider **OTel Arrow (~80% wire compression)**.
5. **Five cardinality layers, use several:** ① SDK **view allowlists** (fails *closed* — strongest), ② `OTEL_METRIC_CARDINALITY_LIMIT` + **alert on the overflow series**, ③ Collector `filter` (Alpha; ★ `error_mode` **defaults to `ignore`**, so malformed conditions are swallowed — use `propagate` while developing), ④ `attributes`/`transform` to reduce a dimension, ⑤ **`cardinality_guardian`**.
6. ★ **`cardinality_guardian` (Alpha, metrics-only) is data-driven, not config-driven.** It detects **delta** (new unique values per epoch) via **dual-epoch HyperLogLog++** sketches, so stable high-cardinality labels are never penalised — **no false positives**, unlike `filter` and `metrics_transform`. 256-way sharded, ~2 KB per tracker, stale-evicted, bounded memory.
7. **It strips the exploding LABEL, not the data point** — `{region, status, error.type}` → `{region, status}`. Your dashboards keep working.
8. ★ **Three enforcement modes:** `tag_only` (adds `otel.metric.overflow: true`; **does NOT protect your TSDB alone — pair with a `routing` connector**), `overflow_attribute` (sentinel `otel.cardinality_overflow` + reaggregation), `strip_and_reaggregate` (removes the attribute + reaggregation).
9. ★ **Reaggregation works only for Delta Sum and Gauge.** **Cumulative Sum, Histogram, ExponentialHistogram and Summary all fall back to `tag_only`** — because collapsing cumulative streams or merging misaligned histogram buckets is exactly the Single-Writer problem it would have to solve. **If your explosion is on a histogram, you get a tag and an alert, not enforcement.** The fallback prevents data corruption, which is the right call.
10. **Operate it via its own metrics:** `processor_cardinality_top.offenders` (**tells you which label is exploding, right now**), `labels.stripped` (rate for spikes), `trackers.active`, `trackers.rejected`, and ★ **`savings.estimated` — a dollar figure for your cost review.** Rollout order: `tag_only` → learn → `never_drop_labels` → `metric_overrides` → `routing` for tagged data → only then consider stripping.
11. ★ **Stateful Collector components require consistent routing, and the key differs per component:** `tail_sampling` → **`traceID`**; `delta_to_cumulative` → **`streamID`/`metric`**; `span_metrics` → **`service`** (else Prometheus label collisions). Wrong routing produces **subtly incorrect data with no errors** — the worst failure class.
12. **Backpressure chain: backend slow → retries → queue fills → processor refuses → `memory_limiter` refuses → SDK retries then drops (and counts it).** ★ **This is a feature**; the alternative is an OOMKill that loses everything. Size both the SDK and Collector queues.
13. **N+1 gateway replicas minimum.** A rolling deploy drains one `tail_sampling` replica at a time, and `terminationGracePeriodSeconds` must exceed the drain.
14. **`num_shards` (max 256) on `tail_sampling`** relieves single-loop contention — but it **divides `num_traces`, cache sizes and per-second rate limits evenly, does NOT divide `burst_capacity`**, makes enforcement approximate for limits smaller than the shard count, and is **incompatible with `tail_storage`**.
15. ★ **The leading alert is `otelcol_exporter_queue_size / queue_capacity > 0.8`** — it rises minutes before `send_failed`. Everything else is lagging confirmation you already lost data.
16. **Governance that works:** tag owners → measure per-service ingest → **publish a monthly showback (typically cuts 10–20% for near-zero effort)** → forecast-based budgets → cost in code review → ★ **track unit economics (cost per request/user/job), not totals** → report savings as a number.
17. **Write down:** metrics get allowlists, traces and logs get volume controls; no new metric attribute without a cardinality estimate; identifiers allowed on spans/logs and prohibited on metrics; every alert has a runbook and every dashboard an owner; retention reviewed quarterly **against compliance requirements**; **sampling is a reliability decision, reviewed with whoever owns incident response.**

→ Next: [`15-security-and-governance.md`](15-security-and-governance.md)
