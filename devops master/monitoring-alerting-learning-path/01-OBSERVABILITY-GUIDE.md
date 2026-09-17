# 📖 The Observability Guide — From Zero to Production

> **The foundation for both cases.** Everything you need to understand *why* Prometheus, Grafana and OpenTelemetry work the way they do — before you type a single command.
>
> Written for a **complete beginner**. No prior knowledge of metrics, tracing or PromQL assumed.

---

## Contents

| § | Topic |
|---|---|
| [0](#0-why-observability-is-not-monitoring) | Why observability is not monitoring |
| [1](#1-the-three-pillars) | The three pillars: metrics, logs, traces |
| [2](#2-metrics-from-absolute-zero) | Metrics from absolute zero |
| [3](#3-the-four-metric-types) | The four metric types — Counter, Gauge, Histogram, Summary |
| [4](#4-histograms-are-the-most-important-thing-in-this-document) | ⭐ Histograms, buckets, percentiles |
| [5](#5-labels-and-the-cardinality-bomb) | Labels and the cardinality bomb |
| [6](#6-prometheus-architecture) | Prometheus architecture |
| [7](#7-promql--the-language) | PromQL — the language |
| [8](#8-the-red-and-use-methods) | The RED and USE methods |
| [9](#9--alerting-theory--how-to-not-hate-your-pager) | ⭐ Alerting theory — how to not hate your pager |
| [10](#10-slis-slos-and-error-budgets) | SLIs, SLOs and error budgets |
| [11](#11-grafana--dashboards-that-answer-questions) | Grafana — dashboards that answer questions |
| [12](#12--opentelemetry--what-it-actually-is) | ⭐ OpenTelemetry — what it actually is |
| [13](#13-tracing-in-depth) | Tracing in depth: spans, context, propagation, sampling |
| [14](#14-the-landscape-what-replaces-what) | The landscape: what replaces what |
| [15](#15-the-incident-workflow) | The incident workflow |
| [16](#16-twenty-common-beginner-mistakes) | 20 common beginner mistakes |

---

<a name="0-why-observability-is-not-monitoring"></a>
## 0. Why observability is not monitoring

**Monitoring** answers questions you thought to ask in advance:
> "Is the CPU above 90%?" · "Is the API returning 500s?" · "Is the disk full?"

You define the questions. The system says yes or no. It works beautifully — **for failures you predicted.**

**Observability** lets you ask questions you have *never asked before*, about a failure you have *never seen*:
> "Why did the 99th-percentile latency for `POST /api/orders` triple at 14:32, only for users in the Mumbai region, only when the cart contained more than four items?"

Nobody wrote that dashboard. Nobody set that alert. But if your system is observable, you can answer it in five minutes.

### The control-theory origin

The word comes from Rudolf Kálmán (1960): *a system is observable if you can infer its internal state from its external outputs.*

```
              ┌───────────────────┐
   inputs ──► │                   │ ──► outputs
              │   THE SYSTEM      │
              │   (internal       │
              │    state)         │
              └───────────────────┘

  OBSERVABLE     = you can deduce the internal state from the outputs alone
  NOT OBSERVABLE = a black box; when it breaks you can only guess or add prints
```

### Why microservices made this hard

In a monolith on one VM, "what happened" was answerable: read the log file, run `top`, attach a debugger. The internal state was **one process on one machine**.

```
MONOLITH                            MICROSERVICES
┌──────────────────────┐            ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
│  one process         │            │ ui  ├──►│ api ├──►│auth ├──►│ db  │
│  one machine         │            └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
│  one log file        │               │         │         │         │
│  read it, done       │            ┌──▼──┐   ┌──▼──┐   ┌──▼──┐   ┌──▼──┐
└──────────────────────┘            │cache│   │queue│   │3rd  │   │replica│
                                    └─────┘   └─────┘   │party│   └─────┘
                                                        └─────┘
        one request now touches 8 processes on 8 machines.
        You cannot SSH your way to an answer.
```

A single user click may touch eight services, three databases, a queue, a cache and two third-party APIs — on machines that **did not exist ten minutes ago** (Kubernetes reschedules Pods constantly). You can't `tail -f` your way through that. You need the system to **emit structured evidence about itself**, continuously, whether or not anything is wrong.

That evidence is telemetry: **metrics, logs, traces** (and increasingly, **profiles**).

### The practical difference

| | Monitoring | Observability |
|---|---|---|
| Questions | Pre-defined | **Ad hoc** |
| Failure modes | Known-unknowns | **Unknown-unknowns** |
| Output | Alert: yes/no | Evidence: enough to form a new hypothesis |
| Best for | Infra with stable failure modes (disk full, node down) | Distributed systems with emergent failure modes |
| Tools | Nagios, Zabbix, CloudWatch alarms | Prometheus + Grafana + OTel + Tempo + Loki |

> 🔑 **You need both.** Monitoring catches the 95% of incidents that look like last week's. Observability is how you survive the 5% that don't. This path builds both.

---

<a name="1-the-three-pillars"></a>
## 1. The three pillars

### Metrics — *what* is happening, cheaply, always

A **metric** is a numeric measurement, aggregated, at a point in time, with labels.

```
http_server_requests_seconds_count{method="POST",uri="/api/orders",status="200"}  184322
│                                        │                                          │
the metric name                          the LABELS (dimensions)                    the VALUE
```

| Property | Reality |
|---|---|
| Size | ~1–2 bytes per sample once compressed (Prometheus's XOR+delta encoding) |
| Cost | **Cheap.** You can keep 15 days of everything for pennies. |
| Retention | Weeks to months (years with Thanos/Mimir/Cortex) |
| Question answered | "How much? How fast? How often? Is it trending up?" |
| Aggregated? | ✅ **Always.** You cannot recover an individual request from a metric. |
| Cardinality limit | **This is the constraint.** See §5. |

```bash
# a real scrape — this is literally all a metric is: text
curl -s http://localhost:8080/actuator/prometheus | head -20
# HELP jvm_memory_used_bytes The amount of used memory
# TYPE jvm_memory_used_bytes gauge
# jvm_memory_used_bytes{area="heap",id="G1 Eden Space"} 4.194304E8
# jvm_memory_used_bytes{area="heap",id="G1 Old Gen"} 1.2834E7
# jvm_memory_used_bytes{area="nonheap",id="Metaspace"} 8.912E7
# HELP http_server_requests_seconds_count
# TYPE http_server_requests_seconds_count counter
# http_server_requests_seconds_count{method="GET",status="200",uri="/api/items"} 4821.0
```

### Logs — *why* it happened, expensively, in detail

A **log** is a timestamped, discrete record of an event, usually text or structured JSON.

```json
{"timestamp":"2026-09-09T14:32:11.482Z","level":"ERROR","logger":"c.s.OrderService",
 "thread":"http-nio-8080-exec-14","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736",
 "span_id":"00f067aa0ba902b7","message":"Payment declined",
 "orderId":"ord_9f2a1b","customer":"cus_8821","amount":14500,"reason":"insufficient_funds"}
```

| Property | Reality |
|---|---|
| Size | 100 bytes – 10 KB **per event** |
| Cost | **Expensive.** 100–1000× metrics per unit of information. |
| Retention | Days to weeks (cost-driven) |
| Question answered | "What exactly went wrong in this one case?" |
| Aggregated? | ❌ Individual events |
| Cardinality limit | None — you can log a unique order ID every time |

> 🔑 **The `trace_id` in that log line is the whole point of modern observability.** It's what turns three separate tools into one. Without it, you're grepping by timestamp and praying.

### Traces — *where* the time went, across services

A **trace** is the journey of one request through the whole system. It's made of **spans**.

```
Trace 4bf92f3577b34da6a3ce929d0e0e4736      total 842 ms
│
├─ shop-ui      GET /checkout                    842 ms
│  └─ shop-api  POST /api/orders                 831 ms
│     ├─ auth    verify-token                     12 ms
│     ├─ postgres SELECT inventory                48 ms
│     ├─ redis   GET cart:8821                     2 ms
│     ├─ payment POST /v1/charge                 712 ms   ◄── ⭐ THE BOTTLENECK
│     └─ rabbitmq publish order.created            4 ms
```

| Property | Reality |
|---|---|
| Size | ~200 bytes – 2 KB per span; a trace has 5–500 spans |
| Cost | Medium — controlled by **sampling** |
| Retention | Days |
| Question answered | "**Which** service/step was slow? What was the causal chain?" |
| Aggregated? | ❌ Per-request (but you can aggregate spans into metrics — RED from traces) |
| The killer feature | **Causality.** You see the parent-child chain, not a pile of events. |

### The fourth pillar: profiles

Continuous profiling (Pyroscope, Parca, Elastic) answers "**which line of code** is burning the CPU/memory?" — a flame graph of your production process, always on, at ~1% overhead.

```
shop-api  CPU profile, 14:30–14:35
  42.3%  com.fasterxml.jackson.databind.ObjectMapper.writeValueAsString
  18.1%  org.postgresql.core.v3.QueryExecutorImpl.execute
   9.7%  java.util.regex.Pattern.matcher          ← ⭐ regex in a hot loop
   6.2%  GC
```

It's newer and not in the classic "three pillars", but it closes the last gap: metrics tell you *that* CPU is high, profiles tell you *which function*.

### How the pillars fit together

```
        ┌─────────────────────────────────────────────────────────┐
        │  1. METRICS tell you SOMETHING IS WRONG                 │
        │     "p99 latency on /api/orders is 842ms, was 120ms"    │
        │     → an alert fires at 14:32                           │
        └──────────────────────┬──────────────────────────────────┘
                               │ click the exemplar on the graph
                               ▼
        ┌─────────────────────────────────────────────────────────┐
        │  2. TRACES tell you WHERE                               │
        │     "842ms, and 712ms of it is the payment-service span"│
        │     → the third-party payment API is slow               │
        └──────────────────────┬──────────────────────────────────┘
                               │ click "Logs for this span"
                               ▼
        ┌─────────────────────────────────────────────────────────┐
        │  3. LOGS tell you WHY                                   │
        │     "WARN  payment client: retry 3/3 after timeout,     │
        │      falling back to secondary endpoint"                │
        └──────────────────────┬──────────────────────────────────┘
                               │ click the flame graph
                               ▼
        ┌─────────────────────────────────────────────────────────┐
        │  4. PROFILES tell you WHICH CODE (when it's your code)  │
        └─────────────────────────────────────────────────────────┘
```

**metrics → traces → logs** is the incident workflow. Learn it as one motion. Every tool choice in this path exists to make that motion one click instead of three tabs.

### Signals compared

| | Metrics | Logs | Traces | Profiles |
|---|---|---|---|---|
| Unit | A number over time | An event | A request's journey | A stack sample |
| Cost to store | 💚 | 🔴 | 🟡 | 🟡 |
| Can you alert on it? | ✅ Best | ⚠️ Slow, fuzzy | ✅ (derived metrics) | ❌ |
| Can you find a needle? | ❌ | ✅ | ✅ | ✅ |
| Retention you can afford | Months | Days | Days | Hours–days |
| Cardinality | **Must be bounded** | Unbounded | Unbounded | Unbounded |
| Tool in this path | Prometheus | Loki | Tempo / Jaeger | Pyroscope |
| Query language | **PromQL** | **LogQL** | **TraceQL** | — |

---

<a name="2-metrics-from-absolute-zero"></a>
## 2. Metrics from absolute zero

### What is a metric, concretely?

A metric is **one line of text** served over HTTP:

```
# HELP http_requests_total The total number of HTTP requests.
# TYPE http_requests_total counter
http_requests_total{method="post",path="/api/orders",status="200"} 1027
http_requests_total{method="post",path="/api/orders",status="500"} 3
http_requests_total{method="get",path="/api/items",status="200"} 8912
```

Three parts:

| Part | Example | Rules |
|---|---|---|
| **Metric name** | `http_requests_total` | `[a-zA-Z_:][a-zA-Z0-9_:]*`. Should say *what* and *what unit*. |
| **Labels** | `{method="post",status="200"}` | Key-value pairs. Each unique combination is a separate **time series**. |
| **Value** | `1027` | Always a `float64`. |

Plus two optional comment lines (`# HELP` for humans, `# TYPE` for parsers).

### The naming convention (follow it, or your team will hate you)

```
<namespace>_<name>_<unit>_<aggregation>

  ✅ http_requests_total              counter → suffix _total
  ✅ http_request_duration_seconds    base unit = seconds (not ms!)
  ✅ node_memory_MemAvailable_bytes   base unit = bytes
  ✅ jvm_gc_pause_seconds_sum         histogram/summary component
  ✅ process_cpu_seconds_total

  ⛔ httpRequestCount                camelCase, no unit, no _total
  ⛔ latency                         what latency? whose? what unit?
  ⛔ response_time_ms                not a base unit (use seconds)
  ⛔ user_email_count                a PII label — see §5
```

| Rule | Why |
|---|---|
| **Base units only**: seconds, bytes, ratio (0–1) | So `rate(x[5m])` composes; ms/KB force mental conversion |
| **Counters end in `_total`** | Prometheus convention; Grafana & tooling expect it |
| **One metric name = one thing measured** | Never reuse a name with a `type` label to mean different things |
| **`snake_case`** | Universally accepted |
| **Prefix with the subsystem**: `jvm_`, `node_`, `http_`, `shop_` | Groups related metrics |

### How an app exposes metrics

There are exactly two mechanisms, and you should know both:

```
MECHANISM 1 — PULL (Prometheus's model) ⭐
┌──────────┐   GET /metrics every 15s    ┌──────────┐
│Prometheus│ ──────────────────────────► │   APP    │
│          │ ◄────────────────────────── │ :9090    │
└──────────┘   200 OK  text/plain        └──────────┘

MECHANISM 2 — PUSH
┌──────────┐                             ┌────────────┐        ┌──────────┐
│   APP    │ ── POST /metrics/job/x ───► │ Pushgateway│ ◄───── │Prometheus│
└──────────┘   (short-lived job)         └────────────┘  pull  └──────────┘
```

| | Pull | Push |
|---|---|---|
| Who controls frequency | The monitoring system | The app |
| Liveness detection | ⭐ **Free** — if the scrape fails, `up == 0` | ❌ You can't tell "no data yet" from "dead" |
| Service discovery | ✅ Prometheus finds targets itself | ❌ |
| Debuggability | ⭐ `curl localhost:9090/metrics` shows you everything | You have to intercept the push |
| Network direction | Monitoring → app | App → monitoring |
| Behind NAT / ephemeral | ❌ | ✅ |
| Used by | **Prometheus**, most of the OSS world | StatsD, CloudWatch, Datadog agents |

> 🔑 **Pushgateway is for batch jobs that finish before a scrape can happen** — a nightly CronJob, a CI step. It is **NOT** a way to make your long-running service work with Prometheus. Pushing a service's metrics to Pushgateway throws away liveness detection and service discovery, and the value stays forever after the job dies. This is the #1 Pushgateway misuse.

### The exposition format

```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 3.8e-05
go_gc_duration_seconds{quantile="0.25"} 5.1e-05
go_gc_duration_seconds{quantile="0.5"} 7.2e-05
go_gc_duration_seconds_sum 0.00412
go_gc_duration_seconds_count 89

# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{le="0.005"} 24054
http_request_duration_seconds_bucket{le="0.01"}  33444
http_request_duration_seconds_bucket{le="0.025"} 100392
http_request_duration_seconds_bucket{le="0.05"}  129389
http_request_duration_seconds_bucket{le="0.1"}   133988
http_request_duration_seconds_bucket{le="+Inf"}  144320
http_request_duration_seconds_sum   53423.21
http_request_duration_seconds_count 144320

# TYPE up gauge
up 1
```

Prometheus 3.x also supports **OpenMetrics** (a superset with `_created` timestamps and exemplars) and **native/exponential histograms** (a compact binary encoding — see §4.6).

### `up` — the most important metric in Prometheus

```
up{job="shop-api",instance="10.244.2.19:9090"} 1
```

Prometheus **synthesizes** `up` for every scrape target: `1` if the scrape succeeded, `0` if it failed. It is the single best liveness signal you have, and it exists for every target without any code from you.

```promql
up == 0                                          # every target that's down
sum(up) by (job) / count(up) by (job)            # availability per job, 0–1
up{job="shop-api"} == 0                          # is YOUR app being scraped?
```

> 🔑 **Your first alert should always be `up == 0`.** Before you write a single clever SLO alert, make sure you know when scraping breaks — because if scraping breaks, every other alert silently goes quiet, and silence looks exactly like health.

---

<a name="3-the-four-metric-types"></a>
## 3. The four metric types

### 3.1 Counter — only goes up

A monotonically increasing number that **only resets to zero on restart**.

```
http_requests_total  1027 → 1028 → 1029 → … → 48211 → 0 (restart) → 1 → 2
```

**Use for:** anything you count — requests, errors, bytes sent, jobs completed, cache hits.

```promql
http_requests_total                          # ⛔ USELESS on its own — an ever-growing number
rate(http_requests_total[5m])                # ⭐ requests per second, averaged over 5m
increase(http_requests_total[1h])            # how many in the last hour
irate(http_requests_total[5m])               # the instantaneous rate (last 2 samples) — spiky
```

> 🔑 **You almost never query a counter directly.** A counter's raw value is meaningless — what matters is *how fast it's growing*. `rate()` computes that, **and it automatically handles restarts**: when Prometheus sees the value decrease, it assumes a reset and adds the pre-reset value. That's why `rate()` works across deploys and `x[5m]` doesn't.

**Rules:**
- Never use a counter for something that can go down (use a gauge).
- Never reset a counter yourself.
- Always name it `*_total`.
- Always wrap it in `rate()` / `increase()` / `irate()`.

### 3.2 Gauge — goes up and down

A number that can rise and fall: the current value of something.

```
node_memory_MemAvailable_bytes  8.2e9 → 7.9e9 → 8.1e9 → 6.2e9 → …
```

**Use for:** temperature, memory in use, queue depth, number of active connections, disk free, replicas running.

```promql
node_memory_MemAvailable_bytes                      # ✅ query directly — this IS meaningful
avg_over_time(node_load1[1h])                       # the average over an hour
max_over_time(shop_queue_depth[24h])                # the peak in a day
min_over_time(node_memory_MemAvailable_bytes[1h])   # the trough
delta(node_temperature_celsius[1h])                 # how much it changed
predict_linear(node_filesystem_avail_bytes[6h], 4*3600)   # ⭐ where will it be in 4h?
```

> 🔑 **Never use `rate()` on a gauge.** `rate()` assumes monotonic increase and treats any decrease as a reset — on a gauge that produces garbage. Use `delta()` (the raw change) or `deriv()` (the slope) instead.

### 3.3 Histogram — the distribution, in buckets

⭐ **The most important and most misunderstood type.** See §4 for the full treatment.

A histogram counts observations into **buckets**:

```
http_request_duration_seconds_bucket{le="0.005"}  24054     ← 24054 requests took ≤ 5ms
http_request_duration_seconds_bucket{le="0.01"}   33444     ← 33444 took ≤ 10ms (CUMULATIVE)
http_request_duration_seconds_bucket{le="0.025"} 100392
http_request_duration_seconds_bucket{le="+Inf"}  144320     ← everything (== _count)
http_request_duration_seconds_sum   53423.21                ← the sum of all observed values
http_request_duration_seconds_count 144320                  ← how many observations
```

Three series per bucket set: `_bucket` (one per `le`), `_sum`, `_count`. All three are **counters**.

```promql
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
# → the 99th percentile latency, computed across ALL instances
```

### 3.4 Summary — a pre-computed quantile

```
go_gc_duration_seconds{quantile="0.5"}   7.2e-05
go_gc_duration_seconds{quantile="0.99"}  1.8e-04
go_gc_duration_seconds_sum   0.00412
go_gc_duration_seconds_count 89
```

A summary computes the quantile **in the client** and exposes it directly.

### Histogram vs Summary — the decision that matters

| | **Histogram** | **Summary** |
|---|---|---|
| Quantiles computed | **Server-side**, at query time | **Client-side**, at observation time |
| Can you aggregate across instances? | ✅ **Yes** — sum the buckets, then compute | ⛔ **NO. Mathematically invalid.** |
| Can you change the quantile later? | ✅ Any quantile, any time | ❌ Only the ones you pre-configured |
| Can you re-bucket historical data? | ✅ | ❌ |
| Client CPU cost | Low (a bucket increment) | **High** (a sliding-window quantile estimate) |
| Storage | One series per bucket (10–20) | One series per quantile (3–5) |
| Accuracy | Bounded by bucket edges | Exact-ish (configurable) |
| **Use when** | ⭐ **Almost always** | Single-instance, known fixed quantiles, tight buckets known in advance (e.g. Go's GC pause) |

> 🔑 **The aggregation problem is why summaries are usually wrong.** You cannot average percentiles. If instance A has p99 = 100ms and instance B has p99 = 400ms, the p99 of the *combined* population is **not** 250ms — it could be anything from 100ms to 400ms depending on the distributions. Summaries throw away the distribution; histograms keep it. **Default to histograms.**

```
The math, briefly:
  A: 100 requests, p99 = 100ms   → the slowest is 100ms
  B: 100 requests, p99 = 400ms   → the slowest is 400ms
  Combined: 200 requests. The 198th slowest (p99) is somewhere in B's fast range.
  avg(100, 400) = 250ms  ← ⛔ WRONG, and possibly wildly wrong
```

### Type reference card

| Type | Direction | Query it with | Classic mistake |
|---|---|---|---|
| **Counter** | Only up | `rate()`, `increase()`, `irate()` | Querying the raw value |
| **Gauge** | Up and down | Directly, `avg_over_time`, `delta` | Using `rate()` |
| **Histogram** | Buckets, up | `histogram_quantile(φ, rate(_bucket[..]))` | Forgetting `by (le)` |
| **Summary** | Quantiles | Directly | Aggregating across instances |

---

<a name="4-histograms-are-the-most-important-thing-in-this-document"></a>
## 4. Histograms are the most important thing in this document

If you learn one section deeply, make it this one. Percentiles are how you measure user experience, and histograms are how you compute them correctly.

### 4.1 Why averages lie

```
10 requests. Nine took 10ms. One took 10,000ms (a GC pause + a cold DB connection).

  average = (9 × 10 + 10000) / 10 = 1009 ms     ← "our API takes one second"
  median  = 10 ms                                ← "our API is fast"
  p99     = 10000 ms                             ← "one user had a terrible time"
```

An average is a **single number that hides the shape of the distribution**. In a system with tail latency — and every real system has tail latency — the average tells you almost nothing about what your users experience.

Worse, the average is **the wrong thing to scale on**. If you autoscale on average CPU, you'll add capacity while your p99 is already unacceptable.

### 4.2 What a histogram actually stores

```
http_request_duration_seconds_bucket{le="0.005"}   24054
http_request_duration_seconds_bucket{le="0.01"}    33444
http_request_duration_seconds_bucket{le="0.025"}  100392
http_request_duration_seconds_bucket{le="0.05"}   129389
http_request_duration_seconds_bucket{le="0.1"}    133988
http_request_duration_seconds_bucket{le="0.25"}   140221
http_request_duration_seconds_bucket{le="0.5"}    143100
http_request_duration_seconds_bucket{le="1"}      144200
http_request_duration_seconds_bucket{le="2.5"}    144318
http_request_duration_seconds_bucket{le="5"}      144320
http_request_duration_seconds_bucket{le="10"}     144320
http_request_duration_seconds_bucket{le="+Inf"}   144320
http_request_duration_seconds_sum     53423.21
http_request_duration_seconds_count   144320
```

**`le` means "less than or equal to".** Each bucket counts every observation ≤ its bound, so buckets are **cumulative**:

```
count ≤ 0.005s   = 24054
count ≤ 0.01s    = 33444   → so 33444 - 24054 = 9390 requests took between 5ms and 10ms
count ≤ 0.025s   = 100392  → 66948 requests took between 10ms and 25ms
...
count ≤ +Inf     = 144320  = _count
```

The **distribution** is recoverable:

| Range | Count | % |
|---|---|---|
| ≤ 5 ms | 24,054 | 16.7% |
| 5–10 ms | 9,390 | 6.5% |
| 10–25 ms | 66,948 | 46.4% |
| 25–50 ms | 28,997 | 20.1% |
| 50–100 ms | 4,599 | 3.2% |
| 100–250 ms | 6,233 | 4.3% |
| 250–500 ms | 2,879 | 2.0% |
| 500 ms – 1 s | 1,100 | 0.8% |
| 1–2.5 s | 118 | 0.08% |
| > 2.5 s | 2 | 0.001% |

### 4.3 How `histogram_quantile` computes a percentile

```promql
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

Step by step:

1. `rate(..._bucket[5m])` → per-second rate for **each bucket** (still cumulative).
2. `sum(...) by (le)` → **collapse all instances/labels**, keeping only `le`. This is the aggregation that summaries can't do.
3. `histogram_quantile(0.99, …)` → find the bucket where the cumulative count crosses 99%, then **linearly interpolate** within that bucket.

```
total = 144320.  99% of that = 142876.8
Which bucket does 142876.8 fall in?
  le="0.5"  → 143100   ✅ first bucket ≥ 142876.8
  le="0.25" → 140221   ← the previous bucket

Interpolate between 0.25 and 0.5:
  fraction = (142876.8 - 140221) / (143100 - 140221) = 2655.8 / 2879 = 0.9225
  p99 = 0.25 + 0.9225 × (0.5 - 0.25) = 0.25 + 0.2306 = 0.4806 s
```

> ⚠️ **The answer is bounded by your bucket edges.** With buckets at 0.25 and 0.5, the computed p99 can never be outside [0.25, 0.5] — the true value could have been 0.26 or 0.49 and you can't tell. **Your bucket configuration determines your accuracy.**

**The three failure modes:**

```promql
# 1. ⛔ Forgetting `by (le)` — the most common PromQL bug
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
# → returns a per-instance p99 for EVERY series. In Grafana you get 40 lines, or NaN.
# The `le` label MUST survive the aggregation for histogram_quantile to work.

# 2. ⛔ Aggregating a pre-computed quantile
avg(http_request_duration_seconds{quantile="0.99"})    # ⛔ mathematically meaningless

# 3. ⛔ Wrong grouping — losing a dimension you wanted
histogram_quantile(0.99, sum(rate(..._bucket[5m])) by (le, uri))   # ✅ per-URI
histogram_quantile(0.99, sum(rate(..._bucket[5m])) by (uri))       # ⛔ NaN — no `le`
```

### 4.4 Choosing buckets — a real engineering decision

**The default buckets are wrong for most apps.** Prometheus's defaults:

```
.005 .01 .025 .05 .075 .1 .25 .5 .75 1 2.5 5 7.5 10     (seconds)
```

Those are reasonable for a fast HTTP API. They are terrible for a nightly batch job, and wasteful for a 1ms in-memory cache lookup.

**How to pick them:**

1. **Know your SLO.** If your SLO is "p99 < 300ms", you need bucket edges **densely around 300ms** — e.g. 0.2, 0.25, 0.3, 0.35, 0.4. Otherwise the interpolated p99 has an error bar wider than your SLO.
2. **Cover the full range.** Include a bucket above your worst case, or everything lands in `+Inf` and `histogram_quantile` returns `+Inf`.
3. **Roughly geometric spacing.** ~1.5–2× between adjacent bounds gives uniform *relative* accuracy across the range.
4. **10–20 buckets.** Each bucket is a separate time series **per label combination**. 20 buckets × 10 URIs × 5 statuses × 20 instances = **20,000 series for one metric.** That's the cardinality cost.

```yaml
# Spring Boot — application.yaml
management:
  metrics:
    distribution:
      percentiles-histogram:
        http.server.requests: true
      slo:
        http.server.requests: 50ms,100ms,200ms,300ms,500ms,1s,2s   # ⭐ SLO-aligned buckets
      minimum-expected-value: 10ms
      maximum-expected-value: 5s
```

```go
// Go — promhttp
httpDur := prometheus.NewHistogramVec(prometheus.HistogramOpts{
    Name:    "http_request_duration_seconds",
    Help:    "HTTP request latency in seconds.",
    Buckets: []float64{.01, .025, .05, .1, .2, .3, .5, 1, 2, 5},   // ⭐ your own
}, []string{"method", "uri", "status"})
```

```python
# Python — prometheus_client
from prometheus_client import Histogram
HTTP_DUR = Histogram(
    "http_request_duration_seconds", "HTTP request latency",
    ["method", "uri", "status"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.0, 5.0),
)
```

**How to tell if your buckets are wrong:**

```promql
# 1. Is everything in the top bucket? → your buckets are too small
sum(rate(x_bucket{le="+Inf"}[5m])) - sum(rate(x_bucket{le="10"}[5m]))
  / sum(rate(x_count[5m]))
# > 0.05 → ⛔ more than 5% of requests are above your largest finite bucket

# 2. Is everything in the bottom bucket? → your buckets are too large
sum(rate(x_bucket{le="0.005"}[5m])) / sum(rate(x_count[5m]))
# > 0.9 → ⛔ your resolution is wasted

# 3. Is the p99 stuck at a bucket edge? → the interpolation is pinned
histogram_quantile(0.99, sum(rate(x_bucket[5m])) by (le))
# a value exactly == 0.5, or exactly == +Inf, is suspicious
```

### 4.5 The three useful histogram queries

```promql
# 1. ⭐ THE PERCENTILE
histogram_quantile(0.99,
  sum(rate(http_server_requests_seconds_bucket{job="shop-api"}[5m])) by (le))

# per-endpoint
histogram_quantile(0.95,
  sum(rate(http_server_requests_seconds_bucket[job="shop-api"}[5m])) by (le, uri))

# ⚠️ the error bar — how wide is the bucket the answer landed in?
histogram_quantile(0.99, sum(rate(x_bucket[5m])) by (le))          # the estimate
histogram_count / histogram_sum → the mean (a sanity check)

# 2. THE AVERAGE (exact, not interpolated — from _sum and _count)
sum(rate(http_server_requests_seconds_sum[5m]))
  / sum(rate(http_server_requests_seconds_count[5m]))
# ⭐ this is EXACT. Unlike histogram_quantile, no interpolation error.

# 3. THE APDEX / SLO ATTAINMENT — what fraction of requests beat the target?
sum(rate(http_server_requests_seconds_bucket{le="0.3"}[5m]))
  / sum(rate(http_server_requests_seconds_count[5m]))
# → 0.9982 = 99.82% of requests were faster than 300ms  ← ⭐ THIS is your SLO
```

> 🔑 **Query 3 is more useful than query 1 for SLOs.** `histogram_quantile` gives an *interpolated estimate* with bucket-bound error. `bucket{le="target"} / count` gives an **exact** ratio. If your SLO is "99.9% of requests under 300ms", measure exactly that — don't estimate a p99 and hope.

### 4.6 Native (exponential) histograms — Prometheus 3.x

Classic histograms make you choose buckets **in advance**. Get it wrong and your percentiles are wrong forever, and you pay for 20 series per label set.

**Native histograms** (stable in Prometheus 3.x) use a **single series** with exponentially-spaced buckets computed dynamically:

```yaml
# prometheus.yml — enable it
scrape_configs:
  - job_name: shop-api
    scrape_native_histograms: true        # ⭐ accept native histograms
    scrape_classic_histograms: false      # optional: stop storing the classic ones too
```

```promql
# the queries are the SAME — histogram_quantile works on both
histogram_quantile(0.99, sum(rate(http_server_requests_seconds[5m])) by (le))
# note: a native histogram series has NO _bucket suffix
```

| | Classic | Native |
|---|---|---|
| Series per metric | One per bucket (10–20) | **1** |
| Bucket choice | **At instrumentation time** | Dynamic, exponential |
| Accuracy | Bounded by your buckets | Configurable **schema** (resolution), typically far better |
| Storage | High | **~90% less** |
| Grafana support | Full | v10.4+ |
| Client support | Universal | Go 1.24+, Java (Micrometer 1.13+), .NET, Rust |

**Use classic histograms if you're on older clients or need max compatibility. Use native if you control the stack — the storage and accuracy win is large.**

---

<a name="5-labels-and-cardinality"></a>
## 5. Labels and the cardinality bomb

### 5.1 What a label does

A label is a **dimension**. Each unique combination of labels creates a separate **time series** stored in the TSDB.

```
http_requests_total{method="get",  path="/api/items",  status="200"}   ← one series
http_requests_total{method="get",  path="/api/items",  status="404"}   ← another series
http_requests_total{method="post", path="/api/items",  status="200"}   ← another
http_requests_total{method="post", path="/api/orders", status="200"}   ← another
```

**Series count = product of the cardinality of each label:**

```
method: 4 values  ×  path: 20 values  ×  status: 5 values  ×  instance: 10 pods
= 4 × 20 × 5 × 10 = 40,000 time series, from ONE metric
```

### 5.2 The bomb

Now someone adds a label:

```
+ user_id:    500,000 customers
  → 40,000 × 500,000 = 20 BILLION series        ⛔⛔⛔

+ request_id: unique per request
  → unbounded. Prometheus dies in minutes.      ⛔⛔⛔⛔
```

```bash
# the symptoms
# 1. Prometheus memory climbs until OOMKill
kubectl top pod -n monitoring prometheus-kps-0 --containers
# prometheus   320m   31Gi        ← ⛔

# 2. queries time out
curl -s 'localhost:9090/api/v1/query?query=up' -m 30
# {"status":"error","errorType":"timeout","message":"query timed out"}

# 3. the logs
kubectl logs -n monitoring prometheus-kps-0 -c prometheus --tail=100 | grep -iE 'series|memory|too many'
# level=warn msg="Head GC failed, memory pressure" …
# level=error msg="Error scraping target" err="context deadline exceeded"

# 4. the WAL grows, restarts take 20 minutes
kubectl logs -n monitoring prometheus-kps-0 -c prometheus | grep -i 'replay'
```

### 5.3 Diagnosing cardinality

```bash
# ⭐ the TSDB status page — the single best cardinality tool
# in the browser: http://localhost:9090/tsdb-status
# Top 10 series count by metric name
# Top 10 label names with high overall label values
# Top 10 high cardinality label values

# via the API
curl -s localhost:9090/api/v1/status/tsdb | jq '.data'
# {
#   "headStats": {"numSeries": 1842033, "numLabelPairs": 4821, ...},
#   "seriesCountByMetricName": [
#     {"name":"kube_pod_container_resource_limits","value":184203},   ← ⛔
#     {"name":"container_memory_working_set_bytes","value":142881},
#   ],
#   "labelValueCountByLabelName": [
#     {"name":"pod","value":12480},
#     {"name":"container_id","value":98211},                          ← ⛔⛔ THE CULPRIT
#   ],
#   "memoryInBytesByLabelName": [...]
# }

# how many series does one metric have?
curl -s 'localhost:9090/api/v1/query' --data-urlencode 'query=count({__name__="kube_pod_container_resource_limits"})' | jq .

# which label is exploding?
curl -s 'localhost:9090/api/v1/label/pod/values' | jq 'length'
curl -s 'localhost:9090/api/v1/label/container_id/values' | jq 'length'   # ⛔ unbounded

# the cardinality explorer (much nicer)
# https://grafana.com/oss/prometheus/  →  or the krew plugin
```

### 5.4 The rules

| ✅ Good label | ⛔ Bad label |
|---|---|
| `method`, `status`, `uri` (templated!) | `user_id`, `customer_email` |
| `namespace`, `pod`, `node`, `container` | `request_id`, `trace_id`, `session_id` |
| `env`, `team`, `service`, `version` | `ip_address` (of a client), `user_agent` |
| `queue`, `topic`, `shard` | `file_path`, `sql_query` (raw), `error_message` |
| `le` (histogram buckets) | `timestamp`, `uuid`, anything unique |

**The test:** *is the set of possible values **bounded and small** (tens, not millions)?* If a label could have a new value for every request, it must not be a label.

### 5.5 The templated-URI trap

```
# ⛔ a REST API with path parameters
http_requests_total{path="/api/orders/ord_9f2a1b"}   ← a new series per order!
http_requests_total{path="/api/orders/ord_1c3d5e"}   ← another
http_requests_total{path="/api/users/usr_8821"}      ← another
# 500,000 orders = 500,000 series

# ✅ use the ROUTE TEMPLATE
http_requests_total{uri="/api/orders/{id}"}          ← ONE series
http_requests_total{uri="/api/users/{id}"}           ← ONE series
```

Spring Boot does this correctly by default (`http_server_requests_seconds{uri="/api/orders/{id}"}`). Express and Flask do **not** — you must use the matched route, not `req.path`:

```javascript
// ⛔ Express — req.path is the raw URL
app.use((req, res, next) => { metrics.observe(req.path); next(); });

// ✅ Express — use the matched route pattern
app.use((req, res, next) => {
  res.on('finish', () => {
    const route = req.route?.path ?? req.baseUrl + '/unmatched';   // ⭐ templated
    httpRequestTotal.labels(req.method, route, res.statusCode).inc();
  });
  next();
});
```

```python
# ⛔ Flask
label = request.path
# ✅ Flask — the rule, not the path
label = request.url_rule.rule if request.url_rule else "unmatched"
```

### 5.6 Controlling cardinality with relabeling

```yaml
scrape_configs:
  - job_name: shop-api
    kubernetes_sd_configs: [{role: pod}]
    relabel_configs:
      # keep only pods with the annotation prometheus.io/scrape=true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      # ⭐ DROP the high-cardinality labels before they're stored
      - action: labeldrop
        regex: 'container_id|uid|pod_template_hash|image_id'
      # ⭐ keep only the labels you want
      - action: labelkeep
        regex: 'job|instance|namespace|pod|container|node|method|uri|status|le'
    metric_relabel_configs:
      # ⭐ drop entire metric families you don't need
      - source_labels: [__name__]
        regex: 'go_gc_duration_seconds.*|etcd_disk_.*'
        action: drop
      # replace a high-cardinality label value with a bucketed one
      - source_labels: [customer_tier]
        regex: '.*'
        target_label: customer_tier
        replacement: 'all'
      # ⭐ the nuclear option for one bad metric
      - source_labels: [__name__]
        regex: 'some_terrible_metric'
        action: drop
```

| Action | Effect |
|---|---|
| `keep` | Drop the target unless the regex matches |
| `drop` | Drop the target if the regex matches |
| `replace` | Rewrite a label from source labels |
| `labelmap` | Create labels from a regex over existing label names |
| `labeldrop` | ⭐ Remove label **names** matching the regex |
| `labelkeep` | ⭐ Keep only label **names** matching the regex |
| `hashmod` | Shard targets by hash |
| `lowercase` / `uppercase` | Change label value case |

`relabel_configs` runs **before** the scrape (it decides *what to scrape and which target labels to keep*). `metric_relabel_configs` runs **after** the scrape (it decides *which metrics and labels to store*). Use the latter to trim cardinality.

### 5.7 Real numbers

| Cluster size | Typical active series | Prometheus RAM |
|---|---|---|
| kind, 3 nodes, a few apps | 50k – 150k | 1–2 GB |
| Small prod, 20 nodes | 500k – 1.5M | 4–8 GB |
| Medium prod, 100 nodes | 3M – 8M | 16–32 GB |
| Large, 1000 nodes | 20M – 100M+ | ⛔ Single Prometheus can't — you need **Mimir / Thanos / VictoriaMetrics** |

```promql
# how many series do YOU have?
prometheus_tsdb_head_series
# and the growth rate
rate(prometheus_tsdb_head_series[1h])
# ⭐ if this is steadily climbing and never plateaus, something has unbounded labels
```

---

<a name="6-prometheus-architecture"></a>
## 6. Prometheus architecture

### 6.1 The components

```
                                 ┌──────────────────────┐
                                 │   ALERTMANAGER       │
                                 │  dedup · group ·     │
                    alerts       │  route · silence ·   │  ──► Slack / email /
              ┌────────────────►│  inhibit · notify    │      PagerDuty / Opsgenie
              │                  └──────────────────────┘
              │
   ┌──────────┴───────────┐         ┌──────────────────────┐
   │    PROMETHEUS        │         │      GRAFANA         │
   │                      │◄────────│  dashboards +        │
   │  ┌────────────────┐  │  query  │  (its own alerting)  │
   │  │ Service        │  │         └──────────────────────┘
   │  │ Discovery      │  │
   │  └───────┬────────┘  │         ┌──────────────────────┐
   │  ┌───────▼────────┐  │  pull   │  REMOTE STORAGE      │
   │  │ Scraper        │──┼────────►│  Thanos / Mimir /    │
   │  │ (every 15s)    │  │         │  VictoriaMetrics     │
   │  └────────────────┘  │         │  (long-term, global) │
   │  ┌────────────────┐  │         └──────────────────────┘
   │  │ TSDB (local)   │  │
   │  │ WAL + blocks   │  │
   │  └────────────────┘  │
   │  ┌────────────────┐  │
   │  │ Rule evaluator │  │   recording rules → new series
   │  │ (every 15s)    │  │   alerting rules  → Alertmanager
   │  └────────────────┘  │
   └──────────┬───────────┘
              │ HTTP GET /metrics
   ┌──────────▼──────────────────────────────────────────────┐
   │  TARGETS                                                │
   │  app:9090/metrics · node_exporter:9100 · kube-state:8080│
   │  blackbox:9115 · mysqld_exporter:9104 · Pushgateway:9091│
   └─────────────────────────────────────────────────────────┘
```

| Component | Job | Runs as |
|---|---|---|
| **Prometheus server** | Scrapes targets, stores the TSDB, evaluates rules | A StatefulSet (needs a PVC) |
| **Alertmanager** | Receives alerts, dedups, groups, routes, silences, notifies | A StatefulSet (gossip cluster for HA) |
| **Exporters** | Turn a third-party system's state into metrics | Deployments/DaemonSets |
| **Pushgateway** | Holds metrics from short-lived jobs | A Deployment |
| **Service discovery** | Finds targets automatically (Kubernetes, EC2, Consul, files) | Built in |
| **Grafana** | Dashboards (and its own alerting engine) | A Deployment |
| **Thanos / Mimir / Cortex** | Long-term storage, global query, deduplication, downsampling | A whole subsystem |

### 6.2 Exporters you'll meet

| Exporter | Metrics from | Port |
|---|---|---|
| `node_exporter` | The host: CPU, memory, disk, network, filesystem, load | 9100 |
| `kube-state-metrics` | Kubernetes object **state**: Deployments, Pods, nodes, quotas | 8080 |
| `blackbox_exporter` | Probing endpoints: HTTP, TCP, DNS, ICMP, TLS expiry | 9115 |
| `mysqld_exporter` | MySQL/MariaDB | 9104 |
| `postgres_exporter` | PostgreSQL | 9187 |
| `redis_exporter` | Redis | 9121 |
| `mongodb_exporter` | MongoDB | 9216 |
| `nginx-prometheus-exporter` | nginx stub_status | 9113 |
| `kafka_exporter` | Kafka topics, consumer lag | 9308 |
| `rabbitmq` (built-in) | RabbitMQ 3.8+ has a Prometheus plugin | 15692 |
| `elasticsearch_exporter` | Elasticsearch | 9114 |
| `jmx_exporter` | **Any JVM app** via JMX | 9404 |
| `process-exporter` | Named processes | 9256 |
| `cAdvisor` | **Container** metrics — built into the kubelet | 10250 |
| `windows_exporter` | Windows hosts | 9182 |

> 🔑 **kube-state-metrics vs cAdvisor vs node_exporter** — the three everyone confuses:
> - **node_exporter** = the **machine** (CPU, RAM, disk, network of the node)
> - **cAdvisor** (in the kubelet) = the **container** (per-container CPU, memory, fs, network)
> - **kube-state-metrics** = the **Kubernetes API objects** (`kube_deployment_status_replicas_available`, `kube_pod_status_phase`, `kube_node_status_condition`) — it doesn't measure performance, it reports **declared and observed state**.

### 6.3 Service discovery on Kubernetes

```yaml
scrape_configs:
  - job_name: kube-pods
    kubernetes_sd_configs: [{role: pod}]        # ⭐ role: pod|service|endpoints|node|ingress|endpointslice
    relabel_configs:
      # only scrape pods that opted in
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      # use the annotation's path
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      # use the annotation's port
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      # ⭐ the useful labels
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_container_name]
        target_label: container
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
      - source_labels: [__meta_kubernetes_pod_phase]
        action: keep
        regex: Running                          # ⭐ don't scrape Pending pods
```

**The `__meta_*` labels** exist only during relabeling and are dropped afterwards. Common ones:

| Meta label | Value |
|---|---|
| `__meta_kubernetes_namespace` | The namespace |
| `__meta_kubernetes_pod_name` | The Pod name |
| `__meta_kubernetes_pod_ip` | The Pod IP |
| `__meta_kubernetes_pod_label_<name>` | Each Pod label |
| `__meta_kubernetes_pod_annotation_<name>` | Each Pod annotation |
| `__meta_kubernetes_pod_container_name` | The container name |
| `__meta_kubernetes_pod_container_port_number` | The port |
| `__meta_kubernetes_pod_ready` | `true`/`false` |
| `__meta_kubernetes_pod_phase` | Pending/Running/Succeeded/Failed/Unknown |
| `__meta_kubernetes_service_name` | The Service name |
| `__meta_kubernetes_endpoints_name` | The EndpointSlice's parent |
| `__meta_kubernetes_node_name` | The node |
| `__meta_kubernetes_node_label_<name>` | Each node label |

⭐ **The Prometheus Operator replaces all of this with CRDs** — `ServiceMonitor`, `PodMonitor`, `Probe`, `ScrapeConfig` — which is what kube-prometheus-stack installs. You declare *what* to scrape in Kubernetes-native YAML, and the Operator generates the `prometheus.yml`. That's what Case 1 uses.

### 6.4 The scrape lifecycle

```
Every `scrape_interval` (default 1m; kube-prometheus-stack uses 30s):

  1. Prometheus resolves targets via service discovery
  2. Applies relabel_configs
  3. GET http://<target><metrics_path>
       Accept: application/openmetrics-text;version=1.0.0,
               application/openmetrics-text;version=0.0.1;q=0.75,
               text/plain;version=0.0.4;q=0.5,*/*;q=0.1
  4. Parses the exposition format
  5. Applies metric_relabel_configs
  6. Enforces limits: sample_limit, label_limit, body_size_limit, target_limit
  7. Appends samples to the head block (in-memory) + the WAL (on disk)
  8. Sets `up` = 1 (or 0 on any failure)
  9. Sets `scrape_duration_seconds`, `scrape_samples_scraped`, `scrape_samples_post_metric_relabeling`
```

```bash
# ⭐ the per-target diagnostic metrics
up{job="shop-api"}
scrape_duration_seconds{job="shop-api"}              # should be << scrape_interval
scrape_samples_scraped{job="shop-api"}               # how many series this target exposes
scrape_samples_post_metric_relabeling{job="shop-api"}# how many survived relabeling
scrape_series_added{job="shop-api"}                  # NEW series this scrape (cardinality churn!)

# the scrape that's about to blow up your TSDB
topk(10, scrape_samples_scraped)
topk(10, scrape_series_added)          # ⭐ churn — series created and abandoned
```

### 6.5 Storage: the TSDB

```
/data
├── wal/                          ← the Write-Ahead Log (crash recovery)
│   ├── 000123
│   ├── 000124
│   └── checkpoint.000122/
├── chunks_head/                  ← the in-memory "head" block's chunks
├── 01HXYZ…/                      ← a 2-hour block, compacted & closed
│   ├── chunks/000001
│   ├── index
│   ├── meta.json
│   └── tombstones
└── 01HXYZ…/                      ← older blocks, progressively compacted
```

| Stage | Duration | Where |
|---|---|---|
| **Head block** | The last 2–3 hours | In memory + WAL on disk |
| **Compaction** | Every 2h the head is cut into an immutable block | Background |
| **Vertical compaction** | 2h blocks → 6h → 18h → … | Background |
| **Downsampling** (Thanos/Mimir only) | 5m and 1h resolutions for long ranges | The compactor |
| **Retention** | `--storage.tsdb.retention.time=15d` (default) | Blocks deleted |

```bash
# the flags that matter
--storage.tsdb.path=/prometheus
--storage.tsdb.retention.time=15d            # ⭐ default. Raise it deliberately.
--storage.tsdb.retention.size=50GB           # whichever comes first
--storage.tsdb.wal-compression=true
--storage.tsdb.no-lockfile=false
--web.enable-lifecycle                       # ⭐ allows POST /-/reload and /-/quit
--web.enable-remote-write-receiver           # to receive remote_write
--enable-feature=native-histogram            # ⭐ Prometheus 3.x
--enable-feature=otlp-write-receiver         # ⭐ accept OTLP directly (no Collector needed!)
--query.max-samples=50000000
--query.timeout=2m
--rules.alert.for-outage-tolerance=1h        # ⭐ don't fire "down" during a planned restart
--rules.alert.for-grace-period=10m
--rules.alert.resend-delay=1m
```

```bash
# reload config without a restart (needs --web.enable-lifecycle)
curl -X POST http://localhost:9090/-/reload
# or send SIGHUP
kubectl exec -n monitoring prometheus-kps-0 -c prometheus -- kill -HUP 1

# the admin API
curl -s localhost:9090/api/v1/status/config | jq -r '.data.yaml'      # the running config
curl -s localhost:9090/api/v1/status/flags  | jq '.data'              # the flags
curl -s localhost:9090/api/v1/status/runtimeinfo | jq '.data'         # uptime, series, storage
curl -s localhost:9090/api/v1/status/tsdb | jq '.data.headStats'      # ⭐ cardinality
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health, lastError, scrapeDuration}'
curl -s localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {name, health, lastError}'
curl -s localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state}'
```

### 6.6 High availability, and the dedup problem

```
             ┌──────────────┐        ┌──────────────┐
             │ Prometheus A │        │ Prometheus B │     ← identical config,
             └──────┬───────┘        └──────┬───────┘        different external_labels
                    │                       │
                    └───────────┬───────────┘
                                │  remote_write
                    ┌───────────▼───────────┐
                    │  Thanos Receive /     │   ← dedupes using the replica label
                    │  Mimir / VictoriaM.   │
                    └───────────────────────┘
```

Both replicas scrape the same targets, so you get **two copies of every sample**. Grafana querying both would show doubled counts. The fix:

```yaml
# prometheus A
external_labels:
  replica: prom-a
  cluster: learn
# prometheus B
external_labels:
  replica: prom-b
  cluster: learn
```

The long-term store dedupes on `replica` and keeps one. In kube-prometheus-stack this is set automatically (`prometheusReplica`).

⚠️ **Alertmanager also needs dedup.** Both Promethei send the same alert; Alertmanager's gossip cluster groups them by label set and notifies once. That's why Alertmanager runs 3 replicas in a mesh.

---

<a name="7-promql"></a>
## 7. PromQL — the language

### 7.1 The four things a query can return

| Type | Example | What it is |
|---|---|---|
| **Instant vector** | `up` | One value per series, right now |
| **Range vector** | `up[5m]` | Many values per series over a window — **not plottable directly** |
| **Scalar** | `time()` | A single number |
| **String** | `"hello"` | Rarely used |

```promql
up                        # instant vector — 40 series, one value each
up[5m]                    # range vector — 40 series, ~20 samples each
sum(up)                   # scalar-ish — an instant vector with ONE series
rate(up[5m])              # ⛔ rate() of a gauge is wrong, but syntactically valid
```

### 7.2 Selectors

```promql
http_requests_total                                     # everything
http_requests_total{job="shop-api"}                     # one label
http_requests_total{job!="shop-api"}                    # not equal
http_requests_total{uri=~"/api/.*"}                     # ⭐ regex match
http_requests_total{uri!~"/health|/metrics"}            # ⭐ regex NOT match
http_requests_total{status=~"5.."}                      # all 5xx
{__name__=~"http_.*"}                                   # by metric name pattern
{__name__=~".+", namespace="shop"}                      # ⛔ EVERY series in a namespace — expensive!

# a range
http_requests_total{job="shop-api"}[5m]
http_requests_total{job="shop-api"}[5m] offset 1h       # ⭐ the same window, one hour ago
http_requests_total @ 1757412345                        # at a specific unix timestamp
```

**Regex matching in PromQL is FULLY ANCHORED.** `uri=~"/api"` matches only exactly `/api`, not `/api/orders`. To match a prefix you must write `/api.*`.

### 7.3 The operators

```promql
# arithmetic (per-series, matching labels)
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes
http_requests_total / 1000
rate(x[5m]) * 60                        # per-minute instead of per-second

# comparison — FILTERS by default (keeps matching series)
up == 0
http_requests_total > 1000
node_load5 > bool 4                     # ⭐ `bool` → returns 1/0 instead of filtering

# logical/set — only between instant vectors
vector_a and vector_b                   # series in a with a match in b
vector_a or vector_b                    # union
vector_a unless vector_b                # in a but not in b

# ⭐ many-to-one / one-to-many joins
method_code:http_errors:rate5m / ignoring(code) group_left sum by (method) (rate(x[5m]))
```

**Vector matching — the part that confuses everyone:**

```promql
a + b            # matches series where ALL labels are identical
```

If the labels differ, you get an empty result. Then you use:

| Keyword | Meaning |
|---|---|
| `on(a, b)` | Match **only** on labels `a` and `b` |
| `ignoring(a, b)` | Match on everything **except** `a` and `b` |
| `group_left(x)` | Many-to-one; the left side is the "many"; copy label `x` from the right |
| `group_right(x)` | One-to-many |

```promql
# the classic: divide a per-pod metric by a per-pod limit
container_memory_working_set_bytes{namespace="shop"}
  / on(namespace, pod) group_left
kube_pod_container_resource_limits{resource="memory", namespace="shop"}
# ⭐ the left has labels {container, endpoint, instance, job, …} that the right lacks,
#   so you match ONLY on namespace+pod
```

### 7.4 Aggregation operators

```promql
sum(x)                    # total
min(x) max(x) avg(x)
count(x)                  # ⭐ how many SERIES (not how many events!)
count_values("v", x)      # group by value
group(x)                  # 1 for every series (existence check)
stddev(x) stdvar(x)
topk(5, x)                # ⭐ the 5 highest series
bottomk(5, x)
quantile(0.95, x)         # ⚠️ a quantile ACROSS SERIES, not across time — rarely what you want

# with grouping
sum by (namespace) (x)            # group by these labels
sum without (instance, pod) (x)   # group by everything EXCEPT these (equivalent)
sum by (le) (x_bucket)            # ⭐ required for histogram_quantile
```

> ⚠️ `quantile()` ≠ `histogram_quantile()`.
> - `quantile(0.95, x)` — the 95th percentile **of the values of the series in the vector**. If you have 10 pods each reporting their own latency, this gives you the 95th percentile *pod*, which is nonsense.
> - `histogram_quantile(0.95, x_bucket)` — the 95th percentile **of the observed events**, using bucket counts. This is what you want.

### 7.5 The rate family

```promql
rate(counter[5m])         # ⭐ per-second average over 5m. Handles resets. USE THIS.
irate(counter[5m])        # the instantaneous rate from the LAST TWO samples. Spiky.
increase(counter[1h])     # ≈ rate × window. The total growth. Also handles resets.
delta(gauge[1h])          # the raw change in a GAUGE (no reset handling)
deriv(gauge[1h])          # the slope (per second) of a gauge, by linear regression
idelta(counter[5m])       # the change between the last two samples
resets(counter[1h])       # ⭐ how many times it reset (= how many restarts)
changes(gauge[1h])        # how many times the value changed
```

| Function | For | Smooth? | Use in |
|---|---|---|---|
| `rate` | Counters | ✅ Smooth | **Alerts and dashboards** |
| `irate` | Counters | ❌ Very spiky | Zooming into a 2-minute incident window only |
| `increase` | Counters | ✅ | "How many in the last hour?" |
| `delta` | Gauges | ✅ | "How much did memory grow?" |
| `deriv` | Gauges | ✅ | Trend lines |

**Rules for `rate()`:**

```promql
# 1. ⭐ the window must be ≥ 4× the scrape interval
#    scrape_interval = 15s → minimum sensible window = 60s. Use 2m–5m.
rate(x[15s])      # ⛔ often has fewer than 2 samples → returns nothing
rate(x[1m])       # ⚠️ works but noisy
rate(x[5m])       # ✅ the default
rate(x[1h])       # ✅ smooth, good for alerts with long `for:`

# 2. ⭐ rate() INSIDE, aggregation OUTSIDE — never the reverse
sum(rate(http_requests_total[5m]))               # ✅ correct
rate(sum(http_requests_total)[5m:])              # ⛔ a subquery, and semantically wrong
sum(http_requests_total)[5m]                     # ⛔ syntax error

# 3. never rate() a gauge
rate(node_memory_MemAvailable_bytes[5m])         # ⛔ garbage — memory goes DOWN too

# 4. rate() over a window shorter than 2 scrapes returns nothing
# 5. rate() handles counter resets automatically — you don't need to
```

**Why `rate()` handles resets:**

```
samples: 100, 105, 110, 3, 8, 13          ← restart between 110 and 3
rate sees 110 → 3, a DECREASE, so it assumes a reset and computes:
   (110 - 110) + 3 = 3 additional during the reset, then 3→8→13 = 10 more
   total growth = 13 over the window, not -97
```

⚠️ **This breaks if a counter legitimately decreases.** Which is why counters must never decrease — that's the definition.

### 7.6 The `_over_time` family

```promql
avg_over_time(x[1h])        # the mean over the window
min_over_time(x[1h])
max_over_time(x[1h])        # ⭐ "what was the peak?"
sum_over_time(x[1h])
count_over_time(x[1h])      # how many samples
quantile_over_time(0.95, x[1h])
stddev_over_time(x[1h])
last_over_time(x[1h])       # ⭐ the last known value — great for stale series
present_over_time(x[1h])    # 1 if any sample exists in the window
absent_over_time(x[1h])     # ⭐ 1 if NO samples — the "did it stop reporting?" alert
```

### 7.7 The functions you'll actually use

```promql
# math
abs(x) ceil(x) floor(x) round(x) sqrt(x) exp(x) ln(x) log2(x) log10(x) sgn(x)
clamp_max(x, 100) clamp_min(x, 0)

# time
time()                          # the current unix time
timestamp(x)                    # the timestamp of the sample
hour() minute() month() year() day_of_week() day_of_month() days_in_month()

# ⭐ "how long ago was this?"
time() - timestamp(kube_pod_created)                       # the pod's age in seconds
(time() - kube_node_created) / 86400                       # the node's age in days

# labels
label_replace(x, "dst", "$1-suffix", "src", "(.*)")       # create a label from another
label_join(x, "dst", "-", "a", "b")                       # concatenate labels
label_replace(up, "short_pod", "$1", "pod", "(.*)-[a-z0-9]{5}$")   # strip the RS hash

# absent — the "is this thing even reporting?" function ⭐
absent(up{job="shop-api"})                    # 1 if NO series matches → your target vanished
absent(kube_pod_info{namespace="shop"})       # 1 if the whole namespace stopped reporting

# sorting
topk(5, sum by (pod) (rate(x[5m])))
bottomk(3, up)
sort(x) sort_desc(x)                          # only for instant queries via the API

# histogram
histogram_quantile(0.99, sum by (le) (rate(x_bucket[5m])))
histogram_avg(x_sum, x_count)                 # Prometheus 3.x
histogram_fraction(0, 0.3, x)                 # ⭐ the fraction of observations in [0, 0.3]
histogram_count(x) histogram_sum(x)

# prediction ⭐
predict_linear(node_filesystem_avail_bytes[6h], 4*3600)    # the value in 4 hours
predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0   # will it fill within a day?
```

### 7.8 The 20 queries you should know cold

```promql
# ── availability ────────────────────────────────────────────────────
up == 0                                                   # what's down
sum(up) by (job) / count(up) by (job)                     # availability ratio per job
avg_over_time(up{job="shop-api"}[30d])                    # 30-day availability

# ── RED: Rate, Errors, Duration ─────────────────────────────────────
sum(rate(http_server_requests_seconds_count[5m]))                            # R: req/s
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
  / sum(rate(http_server_requests_seconds_count[5m]))                        # E: error ratio
histogram_quantile(0.99,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le))                # D: p99

# per-endpoint RED
topk(5, sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) by (uri))

# ── USE: Utilization, Saturation, Errors (for resources) ────────────
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))                       # U: CPU
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)            # U: memory
node_load15 / count(node_cpu_seconds_total{mode="idle"}) without (cpu, mode) # S: load per core
rate(node_disk_io_time_seconds_total[5m])                                    # S: disk busy
node_filesystem_avail_bytes / node_filesystem_size_bytes                     # disk free ratio
rate(node_network_receive_bytes_total[5m]) * 8                               # network in, bits/s

# ── Kubernetes ──────────────────────────────────────────────────────
kube_pod_status_phase{phase!="Running",phase!="Succeeded"} == 1              # stuck pods
kube_pod_container_status_restarts_total > 5                                 # crashloopers
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}         # OOMs
kube_deployment_status_replicas_available / kube_deployment_spec_replicas    # readiness
kube_node_status_condition{condition="Ready",status!="true"} == 1            # bad nodes
kubelet_pod_start_duration_seconds_bucket                                    # slow pod starts

# ⭐ CPU throttling — the latency killer nobody checks
sum(rate(container_cpu_cfs_throttled_periods_total[5m]))
  / sum(rate(container_cpu_cfs_periods_total[5m]))

# ⭐ memory as a fraction of the limit
container_memory_working_set_bytes
  / on(namespace,pod,container) group_left
kube_pod_container_resource_limits{resource="memory"}

# ── capacity planning ───────────────────────────────────────────────
predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0                # fills within 24h
predict_linear(container_memory_working_set_bytes[6h], 4*3600)               # memory in 4h

# ── the "is my monitoring working?" meta-queries ────────────────────
prometheus_tsdb_head_series                                                  # cardinality
rate(prometheus_target_interval_length_seconds_count[5m])                    # are scrapes on time?
scrape_duration_seconds > 10                                                 # slow targets
absent(up{job="shop-api"})                                                   # target vanished
prometheus_rule_evaluation_failures_total > 0                                # broken rules
prometheus_notifications_queue_length{job="prometheus"} > 0                  # Alertmanager unreachable
```

### 7.9 Debugging a PromQL query

```bash
# the instant-query API — your REPL
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=up' | jq '.data.result | length'
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=sum(rate(x[5m])) by (job)' | jq .

# the range-query API — what Grafana uses
curl -sG localhost:9090/api/v1/query_range \
  --data-urlencode 'query=up' \
  --data-urlencode "start=$(date -d '-1 hour' +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode 'step=60s' | jq '.data.result[0].values | length'

# label values
curl -s localhost:9090/api/v1/label/job/values | jq .
curl -s localhost:9090/api/v1/series --data-urlencode 'match[]={job="shop-api"}' | jq '.data[0]'

# the rule test framework ⭐ — unit tests for your PromQL
cat > rules_test.yaml <<'EOF'
rule_files: [alerts.yaml]
evaluation_interval: 1m
tests:
  - interval: 1m
    input_series:
      - series: 'up{job="shop-api",instance="10.0.0.1:9090"}'
        values: '1 1 1 0 0 0 0 0'
    alert_rule_test:
      - eval_time: 4m
        alertname: TargetDown
        exp_alerts:
          - exp_labels: {severity: critical, job: shop-api, instance: "10.0.0.1:9090"}
            exp_annotations:
              summary: "shop-api target 10.0.0.1:9090 is down"
EOF
promtool test rules rules_test.yaml
promtool check rules alerts.yaml                # syntax + lint
promtool check config prometheus.yml
promtool query instant http://localhost:9090 'up'
promtool query series --match='{job="x"}' http://localhost:9090
```

**The five PromQL errors you'll hit:**

| Error | Cause |
|---|---|
| `vector cannot contain metrics with the same labelset` | An aggregation collided — you dropped a distinguishing label |
| `found duplicate series for the match group … on the left side` | A many-to-one join needs `group_left` |
| `many-to-one matching must be explicit` | Same |
| `expected type range vector, got instant vector` | You passed `x` where `x[5m]` was needed (e.g. to `rate`) |
| `parse error: unknown function "rate_x"` | Typo |
| `NaN` in the output | Division by zero, or `histogram_quantile` without `by (le)` |

---

<a name="8-the-red-and-use-methods"></a>
## 8. The RED and USE methods

You cannot instrument everything. These two frameworks tell you **what to instrument first**.

### RED — for services (Tom Wilkie / Weaveworks)

| Letter | Metric | Answers | Example |
|---|---|---|---|
| **R**ate | Requests per second | How busy is it? | `sum(rate(http_server_requests_seconds_count[5m]))` |
| **E**rrors | Failed requests per second (or ratio) | Is it working? | `sum(rate(..._count{status=~"5.."}[5m]))` |
| **D**uration | Distribution of request times | How fast is it? | `histogram_quantile(0.99, sum by (le) (rate(..._bucket[5m])))` |

**RED is user-facing.** It's what you put on the dashboard an exec looks at. Every service gets the same three panels, so a 40-service system has a consistent shape.

```
┌─────────────────────────────────────────────────────────────┐
│  shop-api                          [5m] [15m] [1h] [6h] [24h]│
├──────────────────┬──────────────────┬───────────────────────┤
│  RATE            │  ERRORS          │  DURATION             │
│  ████▓▓▓▓ 240/s  │  ▁▁▂▁▁█▁▁ 0.4%   │  ▁▁▁▂▁▁▁  p50  18ms  │
│                  │                  │                 p95  94ms│
│  by endpoint:    │  by status:      │                 p99 412ms│
│   /api/orders 60 │   500  0.3%      │                       │
│   /api/items  170│   503  0.1%      │  ⭐ p99 spiked at 14:32 │
│   /api/users  10 │   404  1.2% (ok) │                       │
└──────────────────┴──────────────────┴───────────────────────┘
```

### USE — for resources (Brendan Gregg)

| Letter | Metric | Answers | Example (CPU) |
|---|---|---|---|
| **U**tilization | % of time busy, or % of capacity used | Is it full? | `1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))` |
| **S**aturation | Work queued that can't be served yet | Is it **waiting**? | `node_load15 / cores`, or `rate(node_procs_blocked[5m])` |
| **E**rrors | Error events | Is it broken? | `rate(node_cpu_machine_check_exception[5m])` |

**USE is for every RESOURCE**: CPU, memory, disk, network, and also queues, thread pools, connection pools, file descriptors.

| Resource | Utilization | Saturation | Errors |
|---|---|---|---|
| **CPU** | `1 - rate(node_cpu_seconds_total{mode="idle"}[5m])` | `node_load15 / cores`; **`cpu_cfs_throttled_periods`** | machine-check exceptions |
| **Memory** | `1 - MemAvailable/MemTotal` | `node_vmstat_pgmajfault`; swap in/out; **OOMKills** | ECC errors |
| **Disk I/O** | `rate(node_disk_io_time_seconds_total[5m])` | `node_disk_io_time_weighted_seconds_total` (avg queue) | `node_disk_io_now` errors |
| **Disk space** | `1 - avail/size` | — | read-only remount |
| **Network** | `rate(node_network_receive_bytes_total[5m]) / link_speed` | `node_netstat_Tcp_RetransSegs`; drops | `node_network_receive_errs_total` |
| **Connection pool** | `active / max` | `pending_requests` | `acquire_timeouts` |
| **Thread pool** | `busy / max` | `queue_size` | `rejected_count` |
| **Kafka consumer** | `messages_consumed/s` | ⭐ **`consumer_lag`** | rebalance count |
| **Queue (RabbitMQ)** | `messages / capacity` | ⭐ **`messages_ready` (depth)** | `unacked` growth |

> 🔑 **Saturation is the signal that predicts failure.** Utilization at 80% is fine *if nothing is waiting*. Saturation > 0 means requests are already queuing — the user is already suffering. **Alert on saturation, capacity-plan on utilization.**

### The Four Golden Signals (Google SRE)

Latency · Traffic · Errors · Saturation. Essentially RED + the S from USE. If you can only track four things per service, track those.

**The trap in Latency:** *you must separate the latency of successful requests from failed ones.* A request that fails in 1ms makes your p50 look amazing while your users are getting errors.

```promql
# ⛔ conflates fast failures with slow successes
histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket[5m])) by (le))

# ✅ successful requests only
histogram_quantile(0.99,
  sum(rate(http_server_requests_seconds_bucket{status!~"5.."}[5m])) by (le))

# ✅ and separately, how long failures take
histogram_quantile(0.99,
  sum(rate(http_server_requests_seconds_bucket{status=~"5.."}[5m])) by (le))
```

### Putting it together: the instrumentation checklist

```
FOR EVERY SERVICE (RED):
  □ http_server_requests_seconds      (histogram, labelled: method, uri, status)
  □ or: total requests, error count, duration histogram
  □ up                                 (automatic)
  □ the app's own health: is the DB pool exhausted, is the cache warm

FOR EVERY RESOURCE (USE):
  □ CPU: utilization, throttling, load
  □ Memory: working set vs limit, OOM kills, swap
  □ Disk: utilization, queue, space, inode
  □ Network: bytes, packets, errors, drops, retransmits
  □ Every pool: active/max, waiting, timeouts

FOR EVERY DEPENDENCY (client-side RED):
  □ outbound calls: rate, errors, duration histogram, labelled by target
  □ ⭐ this is how you tell "we're slow" from "they're slow"

FOR EVERY QUEUE / STREAM:
  □ depth, publish rate, consume rate, LAG, oldest-message age
```

---

<a name="9-alerting-theory"></a>
## 9. ⭐ Alerting theory — how to not hate your pager

> This section matters more than any tool. A badly designed alerting system destroys a team: alert fatigue, ignored pages, burnout, and the real incident that slips through because 400 notifications were firing.

### 9.1 The two kinds of alert, and only one deserves to page

| | **Cause-based** (⛔ mostly bad) | **Symptom-based** (✅ good) |
|---|---|---|
| Fires when | A component metric crosses a threshold | **A user is affected** |
| Examples | "CPU > 80%", "memory > 90%", "pod restarted", "disk > 75%" | "p99 latency > 500ms for 5m", "error rate > 1% for 5m", "checkout success < 99%" |
| Actionable? | Often not — high CPU can be fine | **Always** — someone is suffering |
| False positives | Constant | Rare |
| Covers unknown causes? | ❌ Only the causes you predicted | ✅ **Any** cause that produces the symptom |

```
⛔ THE CLASSIC BAD ALERT SET
  CPU > 80%          → fires during a legitimate traffic peak. Not an incident.
  Memory > 85%       → fires constantly on a JVM. Not an incident.
  Pod restarted      → fires on every deploy. Not an incident.
  Disk > 75%         → fires for weeks before it matters.
  → 40 pages a night, all noise. The team mutes the channel.

✅ THE SYMPTOM-BASED EQUIVALENT
  "checkout error rate > 1% for 5 minutes"        → PAGE. Users can't buy.
  "checkout p99 > 2s for 10 minutes"              → PAGE. Users are waiting.
  "shop-api has 0 ready replicas for 2 minutes"   → PAGE. The service is down.
  CPU/memory/disk → a TICKET, or a dashboard panel. Never a page.
```

> 🔑 **Google's rule (SRE Workbook): every page must be about a novel problem requiring intelligent action.** If the response is automated, or the action is always the same, it shouldn't page — it should be a ticket or a self-healing controller.

### 9.2 The four properties of a good alert

1. **Actionable** — there is something a human should do, now.
2. **Urgent** — it degrades if not addressed promptly.
3. **Novel** — it isn't the same thing that fired yesterday.
4. **True** — when it fires, users really are affected.

If any one is missing, demote it to a dashboard panel or a ticket.

### 9.3 The anatomy of a Prometheus alerting rule

```yaml
groups:
  - name: shop-api.rules
    interval: 30s                      # how often this group is evaluated
    rules:
      - alert: ShopApiHighErrorRate           # ⭐ the alert NAME (becomes the `alertname` label)
        expr: |                               # ⭐ the CONDITION — any PromQL returning a vector
          sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[5m]))
            /
          sum(rate(http_server_requests_seconds_count{job="shop-api"}[5m]))
            > 0.01
        for: 5m                               # ⭐ must be true continuously for 5m before firing
        labels:
          severity: critical                  # routing key
          team: platform
          slo: availability
        annotations:
          summary: "shop-api error rate is {{ $value | humanizePercentage }}"
          description: |
            {{ $labels.job }} is returning 5xx for more than 1% of requests.
            Current: {{ $value | humanizePercentage }}. Threshold: 1%.
          dashboard: "https://grafana.example.com/d/shop-api?var-namespace=shop"
          runbook: "https://wiki.example.com/runbooks/shop-api-errors"    # ⭐⭐ MANDATORY
```

**The lifecycle:**

```
   expr is FALSE  ─────────►  INACTIVE
                                   │ expr becomes TRUE
                                   ▼
                              PENDING  (the `for:` clock starts)
                                   │ still true after `for:`
                                   ▼
                              FIRING ──► sent to Alertmanager
                                   │ expr becomes FALSE
                                   ▼
                              RESOLVED ──► sent to Alertmanager
```

```bash
# see the states
curl -s localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.type=="alerting") |
  {name, state, health, lastEvaluation, evaluationTime}'
# {"name":"ShopApiHighErrorRate","state":"pending","health":"ok",…}

curl -s localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state, activeAt}'
```

### 9.4 `for:` — the debounce

Without `for:`, an alert fires the instant a single evaluation crosses the threshold. One GC pause, one bad scrape → a page.

| Scenario | `for:` |
|---|---|
| Transient spikes are normal (CPU, latency) | **5m–15m** |
| A genuine outage | **1m–2m** (fast) |
| Capacity/trend predictions (`predict_linear`) | **30m–1h** |
| `up == 0` | **2m–5m** (a single missed scrape can be a network blip) |
| A cert about to expire | **1h** (it's not going to un-expire) |

⚠️ **`for:` interacts with the evaluation interval and the range window.** With `interval: 30s`, `for: 5m` means ~10 consecutive evaluations must all be true. If the underlying `rate()` window is also `[5m]`, your *real* detection latency is closer to 10 minutes. That's fine for most things and terrible for a total outage — which is why outage alerts use a shorter window *and* a shorter `for:`.

### 9.5 The multi-window, multi-burn-rate pattern (Google SRE)

A single `for: 5m` on an error budget is either too sensitive or too slow. The SRE Workbook's answer: **evaluate the burn rate over two windows at once.**

**Burn rate** = how fast you're consuming your error budget relative to an even pace.

```
SLO: 99.9% success over 30 days → the budget is 0.1% of requests = 43.2 minutes
burn rate 1  = using the budget exactly evenly (it lasts exactly 30 days)
burn rate 2  = using it twice as fast (gone in 15 days)
burn rate 14 = gone in ~2 days
burn rate 1000 = gone in 43 minutes        ← ⛔ a full outage
```

| Severity | Long window | Short window | Burn rate | Budget exhausted in | Action |
|---|---|---|---|---|---|
| **Page** | 1h | 5m | **14.4** | ~2 days | Wake someone up |
| **Page** | 6h | 30m | **6** | ~5 days | Wake someone up |
| **Ticket** | 3d | 6h | **1** | 30 days | Next business day |

```yaml
groups:
  - name: shop-slo.rules
    rules:
      # ⭐ FAST BURN — page
      - alert: ShopApiAvailabilityFastBurn
        expr: |
          (
            slo:sli_error:ratio_rate5m{job="shop-api"} > 14.4 * (1 - 0.999)
            and
            slo:sli_error:ratio_rate1h{job="shop-api"} > 14.4 * (1 - 0.999)
          )
        for: 2m
        labels: {severity: critical, slo: shop-api-availability, window: fast}
        annotations:
          summary: "shop-api is burning its error budget 14× too fast"
          runbook: "https://wiki/runbooks/shop-api-availability"

      # ⭐ SLOW BURN — ticket
      - alert: ShopApiAvailabilitySlowBurn
        expr: |
          (
            slo:sli_error:ratio_rate30m{job="shop-api"} > 6 * (1 - 0.999)
            and
            slo:sli_error:ratio_rate6h{job="shop-api"} > 6 * (1 - 0.999)
          )
        for: 15m
        labels: {severity: warning, slo: shop-api-availability, window: slow}
```

**Why two windows?** The long window prevents firing on a brief blip that already recovered; the short window makes the alert **responsive** — without it, a 1-hour window means you'd wait an hour to notice an outage. Requiring *both* gives you fast **and** accurate.

### 9.6 Alertmanager: dedup, group, inhibit, route

Prometheus **evaluates** alerts. Alertmanager **decides what to do about them.**

```
Prometheus ──► Alertmanager ──► [grouping] ──► [inhibition] ──► [silences] ──► [routing] ──► receivers
                                                                                  ├─ Slack #alerts-critical
                                                                                  ├─ PagerDuty
                                                                                  ├─ email
                                                                                  └─ webhook
```

```yaml
global:
  resolve_timeout: 5m                    # how long until an un-refreshed alert is called resolved
  slack_api_url: 'https://hooks.slack.com/services/T00/B00/XXXX'
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: alerts
  smtp_auth_password: '…'
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'

route:
  receiver: default-slack                # the fallback
  group_by: ['alertname', 'namespace']   # ⭐ ONE notification per group, not per alert
  group_wait: 30s                        # ⭐ wait 30s to collect siblings before the first send
  group_interval: 5m                     # wait 5m before sending about NEW alerts in the same group
  repeat_interval: 4h                    # ⭐ re-send an unresolved alert every 4h
  routes:
    # ⭐ the most specific match wins; evaluation is top-down and STOPS at the first match
    - matchers: [ 'severity="critical"', 'team="platform"' ]
      receiver: pagerduty-platform
      group_by: ['alertname']
      repeat_interval: 15m
      continue: false                    # ⭐ default: stop here. true = keep evaluating siblings
    - matchers: [ 'severity="critical"' ]
      receiver: pagerduty-oncall
      repeat_interval: 30m
    - matchers: [ 'severity="warning"' ]
      receiver: slack-warnings
      group_by: ['namespace', 'alertname']
      repeat_interval: 24h               # ⭐ warnings: once a day, not every 4 hours
    - matchers: [ 'alertname=~".*FastBurn"' ]
      receiver: pagerduty-slo
    - matchers: [ 'slo=~".+"' ]
      receiver: slack-slo

receivers:
  - name: default-slack
    slack_configs:
      - channel: '#alerts'
        send_resolved: true
        title: '{{ .CommonLabels.alertname }} ({{ .Status }})'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
  - name: pagerduty-oncall
    pagerduty_configs:
      - service_key: '<from a secret>'
        severity: '{{ .CommonLabels.severity }}'
        description: '{{ .CommonAnnotations.summary }}'
        details:
          runbook: '{{ .CommonAnnotations.runbook }}'
          dashboard: '{{ .CommonAnnotations.dashboard }}'
          firing: '{{ .Alerts.Firing | len }}'
  - name: slack-warnings
    slack_configs: [{channel: '#alerts-warning', send_resolved: true}]
  - name: slack-slo
    slack_configs: [{channel: '#slo-review', send_resolved: false}]   # ⭐ no resolved spam

inhibit_rules:
  # ⭐⭐ THE MOST IMPORTANT PART OF THE CONFIG
  # if the whole cluster is down, don't also page about every individual service
  - source_matchers: [ 'alertname="ClusterDown"' ]
    target_matchers: [ 'severity="critical"' ]
    equal: []
  # if the service is fully down, don't also fire "high latency"
  - source_matchers: [ 'alertname="ShopApiDown"' ]
    target_matchers: [ 'alertname=~"ShopApi.*(Latency|ErrorRate)"' ]
    equal: ['namespace']
  # if the node is down, suppress every pod alert on that node
  - source_matchers: [ 'alertname="KubeNodeNotReady"' ]
    target_matchers: [ 'severity=~"warning|critical"' ]
    equal: ['node']

time_intervals:
  - name: business-hours
    time_intervals:
      - weekdays: ['monday:friday']
        times: [{start_time: '09:00', end_time: '18:00'}]
        location: 'Asia/Kolkata'

mute_time_intervals:
  - name: maintenance-window
    time_intervals:
      - times: [{start_time: '02:00', end_time: '04:00'}]
        weekdays: ['sunday']
```

| Knob | What it does | Typical value |
|---|---|---|
| `group_by` | Bundles alerts into ONE notification | `['alertname','namespace']` |
| `group_wait` | How long to wait for siblings before the **first** send | 30s |
| `group_interval` | How long before sending about **new** alerts in a sent group | 5m |
| `repeat_interval` | How often to **re-send** an unresolved alert | 4h critical / 24h warning |
| `inhibit_rules` | Suppress target alerts when a source alert is firing | ⭐ essential |
| `silences` | Manual, time-boxed suppression (via the UI/API) | During deploys |
| `continue` | Keep matching sibling routes after this one | Rarely |

```bash
# the Alertmanager API
curl -s localhost:9093/api/v2/alerts | jq 'length'
curl -s localhost:9093/api/v2/alerts | jq '.[] | {name: .labels.alertname, sev: .labels.severity, starts: .startsAt}'
curl -s localhost:9093/api/v2/alerts/groups | jq '.data[].labels'
curl -s localhost:9093/api/v2/silences | jq '.[] | {id, status: .status.state, matchers, endsAt}'

# ⭐ create a silence during a deploy
curl -s -XPOST localhost:9093/api/v2/silences -H 'Content-Type: application/json' -d '{
  "matchers": [{"name":"namespace","value":"shop","isRegex":false,"isEqual":true}],
  "startsAt": "2026-09-09T14:00:00Z",
  "endsAt":   "2026-09-09T15:00:00Z",
  "createdBy": "harish@example.com",
  "comment":   "Planned release v1.3.0"
}' | jq .silenceID

# with amtool (much nicer)
amtool silence add namespace="shop" --duration=1h --author=harish --comment="release v1.3.0" \
  --alertmanager.url=http://localhost:9093
amtool silence query --alertmanager.url=http://localhost:9093
amtool check-config /etc/alertmanager/alertmanager.yml
amtool config routes test --alertmanager.url=http://localhost:9093 \
  --verify.receivers=pagerduty-oncall severity=critical team=platform
```

### 9.7 The alerting anti-patterns

| Anti-pattern | Why it's bad | Fix |
|---|---|---|
| **Alerting on causes** (CPU > 80%) | Not actionable; fires constantly | Alert on symptoms; put causes on dashboards |
| **No `for:`** | A single blip pages someone | Always `for:`, sized to the signal |
| **No runbook link** | The person paged at 3am doesn't know what to do | ⭐ Every alert gets `runbook_url` |
| **`repeat_interval: 5m`** | 288 notifications a day | 4h for critical, 24h for warning |
| **No inhibition** | One node failure = 200 pages | Inhibit pod alerts on node alerts |
| **Alerts with no owner** | Nobody fixes them | A `team` label routing to a real on-call |
| **Threshold alerts on gauges** ("queue > 100") | The right threshold changes with traffic | Alert on **saturation ratio** or on the SLO |
| **Alerting on `rate()` with a window < 4× scrape interval** | Flaky, sometimes empty | `[5m]` minimum |
| **One giant rule file** | Unreviewable | One file per team/service |
| **No tests** | You find out the rule is broken during the incident | ⭐ `promtool test rules` in CI |
| **`severity: critical` on everything** | Nothing is critical | Two levels max: `critical` (page) and `warning` (ticket) |
| **Never reviewing alerts** | Noise accumulates | Monthly: delete anything nobody acted on |

> 🔑 **The monthly alert review.** Look at every alert that fired in the last 30 days. For each, ask: *did a human take an action because of it?* If the answer is no — **delete it or demote it to a dashboard**. An alert that has never caused an action is pure cost.

### 9.8 On-call hygiene

```
THE RULES
1. A page means: a user is affected, AND a human must act, AND it can't wait until morning.
2. Every page has a runbook. If it doesn't, that's the first thing you fix.
3. Target: < 2 pages per on-call shift. More than that = the system is broken, not the people.
4. After every page: was it actionable? If not, file a ticket to fix or delete the alert.
5. During a deploy: silence the affected namespace, don't just ignore the noise.
6. Alerts are code. They live in Git. They're reviewed. They're tested.
```

---

<a name="10-slis-slos-and-error-budgets"></a>
## 10. SLIs, SLOs and error budgets

### 10.1 The definitions

| Term | Meaning | Example |
|---|---|---|
| **SLI** — Service Level *Indicator* | The **measured** quantity | "The proportion of HTTP requests to `/api/*` that return a non-5xx status within 300ms" |
| **SLO** — Service Level *Objective* | The **target** for the SLI | "99.9% over a rolling 30 days" |
| **SLA** — Service Level *Agreement* | The **contract**, with penalties | "99.5%, or the customer gets 10% of the monthly fee back" |
| **Error budget** | `1 − SLO` | 0.1% of requests may fail |

> 🔑 **The SLA is always looser than the SLO.** If your SLA is 99.5% and your SLO is 99.9%, you have a 0.4% buffer to react before you owe anyone money. Never make them equal.

### 10.2 Choosing an SLI

The SLI must be measured **from the user's perspective**, not the server's.

| Service type | Good SLI |
|---|---|
| **A web API** | Proportion of requests returning non-5xx **within** the latency target |
| **A UI** | Page load time / interaction latency, measured in the browser (RUM) |
| **A batch pipeline** | Did it complete successfully **and on time**? |
| **A storage system** | Proportion of reads/writes that succeeded within N ms; durability |
| **A queue/stream** | End-to-end delivery latency; consumer lag |
| **A login system** | Proportion of successful authentications (⚠️ exclude wrong-password!) |

**The two SLIs almost every service needs:**

```
1. AVAILABILITY  = good events / total events
   good = not a 5xx (4xx are the client's fault, not yours)

2. LATENCY       = events faster than T / total events
   T = your threshold (e.g. 300ms)
   ⭐ this is a RATIO, not a percentile — it composes into an error budget
```

⚠️ **A percentile is not an SLI.** "p99 < 300ms" cannot be averaged across windows or aggregated into a monthly budget. "**99% of requests are faster than 300ms**" can. Same information, composable form.

### 10.3 Implementing an SLO in Prometheus

**Step 1 — recording rules for the SLI.** Recording rules pre-compute expensive queries into cheap new series.

```yaml
groups:
  - name: shop-sli.rules
    interval: 30s
    rules:
      # ⭐ naming convention:  level:metric:operations
      - record: slo:shop_api:http_requests_total:rate5m
        expr: sum(rate(http_server_requests_seconds_count{job="shop-api"}[5m]))

      - record: slo:shop_api:http_errors_total:rate5m
        expr: sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[5m]))

      # the error RATIO (the SLI)
      - record: slo:sli_error:ratio_rate5m
        expr: |
          sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[5m]))
            /
          sum(rate(http_server_requests_seconds_count{job="shop-api"}[5m]))

      - record: slo:sli_error:ratio_rate30m
        expr: |
          sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[30m]))
            /
          sum(rate(http_server_requests_seconds_count{job="shop-api"}[30m]))

      - record: slo:sli_error:ratio_rate1h
        expr: |
          sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[1h]))
            /
          sum(rate(http_server_requests_seconds_count{job="shop-api"}[1h]))

      - record: slo:sli_error:ratio_rate6h
        expr: |
          sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[6h]))
            /
          sum(rate(http_server_requests_seconds_count{job="shop-api"}[6h]))

      # latency SLI: the fraction FASTER THAN 300ms
      - record: slo:shop_api:latency_good:ratio_rate5m
        expr: |
          sum(rate(http_server_requests_seconds_bucket{job="shop-api",le="0.3"}[5m]))
            /
          sum(rate(http_server_requests_seconds_count{job="shop-api"}[5m]))
```

**Step 2 — the error budget, two ways.**

```promql
# METHOD A: the ratio over the window (simple, needs a long range query)
1 - (
  sum(increase(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[30d]))
    /
  sum(increase(http_server_requests_seconds_count{job="shop-api"}[30d]))
)
# → 0.99942 = 99.942% availability over 30 days. SLO 99.9% → ✅ within budget.

# the budget CONSUMED (0 = none used, 1 = exhausted, >1 = breaching)
  sum(increase(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[30d]))
    /
  (sum(increase(http_server_requests_seconds_count{job="shop-api"}[30d])) * (1 - 0.999))
# → 0.58 = 58% of the 30-day budget consumed

# METHOD B ⭐: a counter-based budget that survives restarts and is cheap to query
# (this is what sloth generates)
```

**Step 3 — let [sloth](https://sloth.dev) generate it all.** Writing multi-window burn-rate rules by hand is error-prone.

```yaml
# slo.yaml
version: "prometheus/v1"
service: "shop"
slos:
  - name: "availability"
    objective: 99.9
    description: "99.9% of shop-api requests must not be 5xx"
    sli:
      events:
        errorQuery: sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[{{.window}}]))
        totalQuery: sum(rate(http_server_requests_seconds_count{job="shop-api"}[{{.window}}]))
    alerting:
      name: ShopApiAvailability
      labels: {team: platform, tier: "1"}
      annotations:
        runbook_url: "https://wiki/runbooks/shop-api-availability"
      page_alert:
        labels: {severity: critical}
      ticket_alert:
        labels: {severity: warning}
  - name: "latency"
    objective: 99.0
    description: "99% of shop-api requests must be faster than 300ms"
    sli:
      events:
        errorQuery: |
          sum(rate(http_server_requests_seconds_count{job="shop-api"}[{{.window}}]))
          - sum(rate(http_server_requests_seconds_bucket{job="shop-api",le="0.3"}[{{.window}}]))
        totalQuery: sum(rate(http_server_requests_seconds_count{job="shop-api"}[{{.window}}]))
```

```bash
sloth generate -i slo.yaml -o slo-generated.yaml
# ⭐ generates: SLI recording rules for 5m/30m/1h/2h/6h/1d/3d/5m-window pairs,
#   multi-window multi-burn-rate alerts (14.4×/2m + 6×/15m + 3×/30m + 1×/2h),
#   and the error-budget-remaining recording rules
promtool check rules slo-generated.yaml
kubectl create configmap shop-slo-rules --from-file=slo-generated.yaml -n monitoring
# then reference it in a PrometheusRule, or mount it
```

**Step 4 — the dashboard.**

```promql
# the SLO gauge panel
1 - (
  sum(increase(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[30d]))
  / sum(increase(http_server_requests_seconds_count{job="shop-api"}[30d]))
)

# the error budget remaining, as a percentage (100% = untouched, 0% = exhausted)
100 * (1 - (
  sum(increase(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[30d]))
  / (sum(increase(http_server_requests_seconds_count{job="shop-api"}[30d])) * 0.001)
))

# ⭐ the burn rate right now
  sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[5m]))
  /
  (sum(rate(http_server_requests_seconds_count{job="shop-api"}[5m])) * 0.001)

# minutes of budget left at the current rate
(0.001 * sum(increase(http_server_requests_seconds_count{job="shop-api"}[30d]))
 - sum(increase(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[30d])))
/ sum(rate(http_server_requests_seconds_count{job="shop-api",status=~"5.."}[5m])) / 60
```

### 10.4 What the error budget is *for*

This is the part teams miss. The error budget is a **negotiated agreement between engineering and product** about how much unreliability is acceptable in exchange for velocity.

```
BUDGET REMAINING  →  SHIP FAST
  90% left          deploy daily, run chaos experiments, try the risky migration
  50% left          normal pace
  20% left          feature freeze; only reliability work
  0%  left          ⛔ NO FEATURE RELEASES until the budget recovers.
                    All engineering effort goes to reliability.
```

> 🔑 **This is what turns reliability from an argument into arithmetic.** "We need two weeks to fix the flaky checkout" loses to "we need two weeks for the new feature." "We have consumed 140% of our error budget and the policy says no feature releases" doesn't lose — it's a pre-agreed rule.

### 10.5 Realistic SLO targets

| Service | Availability SLO | Latency SLO |
|---|---|---|
| Public e-commerce checkout | **99.95%** (21.6 min/month) | 99% < 500ms |
| Internal API | 99.9% (43 min/month) | 95% < 300ms |
| Batch reporting | 99% (7.2 h/month) | Completes by 06:00 |
| Dev/staging | **99%** or none | none |
| A database | 99.99% | 99% < 10ms |

**Five nines (99.999%) = 5.26 minutes of downtime per *year*.** That requires multi-region active-active, a dedicated SRE team, and a large budget. **Don't promise it.** 99.9% is a sensible, achievable target for most services and is what this path uses.

---

<a name="11-grafana"></a>
## 11. Grafana — dashboards that answer questions

### 11.1 The one rule

> **A dashboard is not a wall of graphs. It's an answer to a question, in a specific order.**

Bad dashboards are built **bottom-up**: "here's every metric we have." Good dashboards are built **top-down**: "here's the question an on-call engineer asks at 3am, and here's the path to the answer."

```
THE ON-CALL DASHBOARD LAYOUT (top to bottom)

  ROW 1  ── IS IT BROKEN?        the SLO gauges. Red/green. 3 panels max.
              Availability 99.94%  │  Latency SLO 99.2%  │  Error budget 62% left

  ROW 2  ── HOW BROKEN?          the RED panels. Rate · Errors · Duration.
              240 req/s           │  0.4% errors          │  p99 412ms

  ROW 3  ── WHERE?              broken down by endpoint, by pod, by node, by region
              top-5 erroring URIs │  per-pod error rate    │  per-node CPU

  ROW 4  ── WHY?                saturation & dependencies
              CPU throttling      │  DB pool usage         │  payment API latency
              memory vs limit     │  cache hit rate        │  queue depth

  ROW 5  ── EVIDENCE            the links out
              Exemplars on the latency graph → click a point → the exact trace
              A Logs panel filtered to the trace_id
              Links to the runbook, to Kubernetes, to the deploy timeline
```

### 11.2 Panel types and when to use each

| Panel | Use for | Don't use for |
|---|---|---|
| **Time series** | ⭐ 90% of things. Trends over time. | A single number |
| **Stat** | One big number now (availability, error budget %) | Anything with history |
| **Gauge** | A value against a threshold (disk 78% of 90%) | Trend |
| **Bar gauge** | Several values against thresholds | Trend |
| **Table** | Top-N with several columns (top erroring endpoints) | Anything time-based |
| **Heatmap** | ⭐ **Latency distributions** — the single best way to see a tail | Counts |
| **Histogram** | A distribution at one moment | Time |
| **State timeline** | Status over time (was it up? when did the deploy happen?) | Numbers |
| **Bar chart** | Categorical comparison | Time series |
| **Pie chart** | ⛔ Almost never — humans can't compare angles | Percentages over time |
| **Logs** | Live Loki/Elasticsearch logs | Aggregation |
| **Traces** | A trace waterfall (Tempo/Jaeger/Zipkin) | Anything else |
| **Flame graph** | Profiles (Pyroscope) | |
| **Node graph** | Service dependency maps | |
| **Alert list** | What's firing right now | |
| **Text/HTML** | Runbook links, context, instructions | |
| **Dashboard list** | Navigation | |
| **Candlestick** | Financial / OHLC | |

> 🔑 **The heatmap for latency is the killer panel.** A p99 line hides the shape. A heatmap shows the whole distribution over time, so you can *see* "a second mode appeared at 14:32 and the tail fattened" — which a p99 line shows as a bump, and an average shows as nothing.

### 11.3 Variables — one dashboard, every service

```
Dashboard settings → Variables → New

  Name:  namespace
  Type:  Query
  Data source: Prometheus
  Query: label_values(kube_pod_info, namespace)
  Refresh: On time range change
  Multi-value: ✅      Include All option: ✅
  Sort: Alphabetical (asc)

  Name:  service
  Type:  Query
  Query: label_values(kube_pod_info{namespace="$namespace"}, pod)
  Regex: /(.+?)-[a-z0-9]+-[a-z0-9]+$/         ← ⭐ strip the ReplicaSet + Pod hash
  Refresh: On dashboard load
```

Then in panels: `sum(rate(http_server_requests_seconds_count{namespace=~"$namespace", pod=~"$service"}[5m]))`

| Variable type | Use for |
|---|---|
| **Query** | ⭐ Anything from a data source (namespaces, services, nodes) |
| **Custom** | A fixed list (`prod,staging,dev`) |
| **Constant** | A hidden fixed value |
| **Text box** | Free input (a search filter) |
| **Interval** | A time-window selector (`1m,5m,15m,1h`) |
| **Data source** | Let the user pick which Prometheus |
| **Chained** | A variable whose query uses another variable |
| **Ad hoc** | ⭐ Apply arbitrary label filters to every panel at once |

```promql
# the Interval variable is how you make the rate window user-selectable
sum(rate(http_server_requests_seconds_count[$__interval]))
# $__interval = Grafana's auto-computed step based on the time range and panel width

# other built-in macros
$__rate_interval      # ⭐ max($__interval + scrape_interval, 4×scrape_interval) — USE THIS for rate()
$__range              # the whole dashboard time range
$__range_s / _ms      # the range in seconds/ms
$__from / $__to       # the range bounds
$__interval_ms
```

> 🔑 **Always use `$__rate_interval` inside `rate()` in Grafana**, not `$__interval` and never a hard-coded `[5m]`. Grafana computes it so that the window is always at least 4× the step *and* at least 4× the scrape interval — which prevents the gaps and spikes you get when zoomed in on a 15s-scraped metric.

### 11.4 Dashboards as code

```bash
# ⭐ NEVER click-build a dashboard in production and leave it there.
# Export it, commit it, deploy it.

# export from the UI:  Dashboard settings → JSON Model → copy
# or via the API
curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
  http://localhost:3000/api/dashboards/uid/shop-api-red | jq '.dashboard' > shop-api-red.json

# ⭐ scrub it before committing (remove the ids and the folder uid)
jq 'del(.id, .uid, .version, .iteration) | .panels[].id = null' shop-api-red.json > clean.json
```

Three ways to deploy dashboards into kube-prometheus-stack:

```yaml
# METHOD 1 ⭐ — the sidecar. Drop a ConfigMap with the label, and it appears.
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-shop-api
  namespace: monitoring
  labels:
    grafana_dashboard: "1"          # ⭐ the label the sidecar watches
data:
  shop-api-red.json: |-
    { "dashboard": … }
```

```yaml
# METHOD 2 — inline in the Helm values
# values.yaml
grafana:
  dashboards:
    default:
      shop-api-red:
        json: |
          { … }
      node-exporter:
        gnetId: 1860           # ⭐ pull from grafana.com by ID
        revision: 34
        datasource: Prometheus
```

```yaml
# METHOD 3 — the Grafana Dashboard provider CRD (Grafana Operator)
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata: {name: shop-api-red, labels: {dashboards: "shop"}}
spec:
  folder: Shop
  instanceSelector: {matchLabels: {dashboards: "grafana"}}
  json: { … }
  # or: url: https://raw.githubusercontent.com/…/dashboard.json
  # or: configMapRef: {name: shop-api-dash, key: dashboard.json}
  datasources: [{inputName: "DS_PROMETHEUS", datasourceName: "Prometheus"}]
```

**The dashboards worth importing from grafana.com:**

| ID | Name | Why |
|---|---|---|
| **1860** | Node Exporter Full | ⭐ The definitive host dashboard |
| **315** | Kubernetes / Compute Resources / Cluster | The cluster overview |
| **6417** | Kubernetes / Compute Resources / Namespace (Pods) | Per-namespace |
| **6581** | Kubernetes / Compute Resources / Namespace | |
| **6781** | Kubernetes / Compute Resources / Pod | Per-pod |
| **13105** | Kubernetes / Views / Nodes | |
| **15757** | Kubernetes / Views / Pods | |
| **7587** | Kubernetes / Networking / Cluster | |
| **12006** | Kubernetes / Networking / Namespace | |
| **13946** | Kubernetes / Networking / Pod | |
| **3662** | Kubernetes / Storage / Volumes | ⭐ PVC usage |
| **14837** | Kubernetes / Storage / Persistent Volumes | |
| **7589** | Kubernetes / API Server | |
| **6911** | etcd by Prometheus | ⭐ etcd health |
| **7549** | CoreDNS | DNS latency & errors |
| **15760** | kubelet | |
| **13332** | kube-proxy | |
| **14845** | Alertmanager | |
| **3681** | Prometheus 2.0 overview | ⭐ is Prometheus itself healthy |
| **4701** | Kubernetes cluster monitoring (via cAdvisor) | |
| **11835** | NGINX ingress controller | |
| **13946** | Kubernetes networking pod | |
| **763** | MySQL overview | |
| **9628** | PostgreSQL Database | |
| **11835** | Redis Dashboard for Prometheus | |
| **12433** | RabbitMQ | |
| **11955** | Spring Boot 2.1 Statistics | ⭐ JVM + Micrometer |
| **19004** | Spring Boot HikariCP | Connection pool |
| **14845** | OpenTelemetry Collector | ⭐ Collector self-monitoring |

```bash
kubectl exec -n monitoring deploy/kps-grafana -c grafana -- \
  grafana-cli --pluginsDir /var/lib/grafana/plugins plugins ls
# or import from the UI: Dashboards → New → Import → paste the ID
```

### 11.5 Grafana alerting vs Prometheus alerting

| | Prometheus + Alertmanager | Grafana Alerting |
|---|---|---|
| Rules live in | YAML in Git (PrometheusRule CRD) | The Grafana DB, or as code via Terraform/API |
| Data sources | Prometheus only | **Any** (Prometheus, Loki, MySQL, CloudWatch, …) |
| Evaluation | In Prometheus | In Grafana |
| Routing | Alertmanager | Grafana's own Alertmanager (or an external one) |
| Best for | ⭐ **Infrastructure and SLO alerts** | Cross-data-source alerts; logs-based alerts; business KPIs |
| Reviewable in PRs | ✅ Excellent | ⚠️ Needs Terraform/provisioning |

> 🔑 **The common production split:** Prometheus/Alertmanager for everything infrastructural and SLO-related (it's code, it's tested with `promtool`, it survives Grafana being down). Grafana alerting for Loki log-based alerts ("count of `FATAL` in the last 5m > 0") and for business dashboards. **Never rely on Grafana being up to tell you Grafana is down.**

### 11.6 Grafana operations

```bash
# provisioning — datasources as code ⭐
apiVersion: v1
kind: ConfigMap
metadata: {name: grafana-datasources, namespace: monitoring, labels: {grafana_datasource: "1"}}
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        uid: prometheus               # ⭐ a stable uid so dashboards can reference it
        type: prometheus
        access: proxy
        url: http://kps-kube-prometheus-stack-prometheus.monitoring:9090
        isDefault: true
        jsonData:
          timeInterval: "30s"          # ⭐ MUST match your scrape interval for $__interval to work
          httpMethod: POST
          exemplarTraceIdDestinations:
            - name: traceID
              datasourceUid: tempo     # ⭐ click an exemplar → jump to Tempo
          manageAlerts: false
      - name: Loki
        uid: loki
        type: loki
        access: proxy
        url: http://kps-loki:3100
        jsonData:
          derivedFields:               # ⭐⭐ THE LOG↔TRACE LINK
            - name: TraceID
              matcherRegex: '"trace_id":"(\w+)"'
              url: '$${__value.raw}'
              datasourceUid: tempo
            - name: SpanID
              matcherRegex: '"span_id":"(\w+)"'
              url: '$${__value.raw}'
              datasourceUid: tempo

# users, teams, folders, permissions via the API
curl -s -H "Authorization: Bearer $TOKEN" localhost:3000/api/org/users | jq
curl -s -XPOST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  localhost:3000/api/admin/users -d '{"name":"harish","login":"harish","password":"…","OrgId":1}'
curl -s -H "Authorization: Bearer $TOKEN" localhost:3000/api/folders | jq '.[].title'
curl -s -H "Authorization: Bearer $TOKEN" localhost:3000/api/dashboards/db | jq
curl -s -H "Authorization: Bearer $TOKEN" localhost:3000/api/health | jq

# the Grafana config
kubectl get cm -n monitoring kps-grafana -o jsonpath='{.data.grafana\.ini}' | head -60
```

---

<a name="12-opentelemetry"></a>
## 12. ⭐ OpenTelemetry — what it actually is

### 12.1 The problem it solved

Before OpenTelemetry (roughly pre-2019) you had to **choose a vendor and a standard**:

```
Zipkin      → the Zipkin format, the Zipkin SDK, the Zipkin collector
Jaeger      → the Jaeger format, the Jaeger SDK (and it also spoke Zipkin)
OpenTracing → an API standard with NO implementation — you still needed Jaeger/Zipkin
OpenCensus  → Google's SDK + collector, its own format
Datadog     → the Datadog agent, the Datadog SDK, the Datadog format
New Relic   → …
```

Switching vendor meant **re-instrumenting your entire codebase.** That lock-in was the point.

**OpenTelemetry merged OpenTracing + OpenCensus into one CNCF project** (the second most active after Kubernetes) that provides:

| Layer | What it is | Vendor-neutral? |
|---|---|---|
| **Specification** | The data model: what a span, metric, log record is | ✅ |
| **APIs** | Interfaces your code calls (`tracer.startSpan(...)`) | ✅ |
| **SDKs** | The implementations (sampling, batching, exporting) per language | ✅ |
| **Instrumentation libraries** | Auto-instrumentation for 100+ frameworks/libraries | ✅ |
| **OTLP** | The wire protocol (gRPC :4317, HTTP :4318) | ✅ |
| **The Collector** | A standalone pipeline: receive → process → export | ✅ |
| **The Operator** | Kubernetes auto-instrumentation and Collector management | ✅ |
| *(Semantic conventions)* | The agreed names for attributes: `http.request.method`, `db.system` | ✅ |

**The result:** instrument once, with OTel; send OTLP; and point the exporter at **anything** — Jaeger, Tempo, Datadog, Honeycomb, New Relic, CloudWatch, Lightstep. Switching backend is a config change in the Collector, not a rewrite of your app.

### 12.2 The architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│ YOUR APPLICATION                                                       │
│                                                                        │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐              │
│   │  OTel API    │   │  OTel API    │   │  OTel API    │   ← your code │
│   │  (traces)    │   │  (metrics)   │   │  (logs)      │     calls this│
│   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘              │
│          │                  │                  │                      │
│   ┌──────▼──────────────────▼──────────────────▼───────┐              │
│   │              OTel SDK  (per language)              │              │
│   │  sampler → processor (batch) → exporter            │              │
│   │  + auto-instrumentation for HTTP/gRPC/JDBC/…       │              │
│   └──────────────────────┬─────────────────────────────┘              │
└──────────────────────────┼─────────────────────────────────────────────┘
                           │ OTLP  (gRPC :4317 or HTTP :4318)
                           ▼
       ┌───────────────────────────────────────────┐
       │       OPENTELEMETRY COLLECTOR             │   ← deployed as an AGENT (per node)
       │                                           │     and/or a GATEWAY (central)
       │   RECEIVERS   →  PROCESSORS  →  EXPORTERS │
       │   otlp, jaeger,   batch, memory_   otlp, prometheus,
       │   prometheus,     limiter, attri-  loki, jaeger,
       │   kafka, filelog, butes, tail_     debug, file,
       │   hostmetrics,    sampling, trans- kafka, datadog,
       │   kubeletstats,   form, redacti-   awsxray, …
       │   docker_stats    on, resourcede-
       │                   tection, k8sat-
       │                   tributes
       │            connected by PIPELINES         │
       └──────┬──────────┬──────────┬──────────────┘
              │          │          │
         ┌────▼───┐  ┌───▼───┐  ┌───▼────┐
         │ Tempo  │  │ Loki  │  │Prometh.│      or Datadog / Honeycomb / …
         │/Jaeger │  │       │  │/Mimir  │
         └────┬───┘  └───┬───┘  └───┬────┘
              └──────────┴──────────┘
                         │
                    ┌────▼────┐
                    │ Grafana │   ← one pane of glass, correlated
                    └─────────┘
```

### 12.3 The three deployment modes

| Mode | What it is | Overhead in the app | Best for |
|---|---|---|---|
| **Direct export** | The SDK sends OTLP straight to the backend | Highest (retries, batching in the app) | Simple setups, a single backend |
| **Agent** | ⭐ A Collector per node (DaemonSet) or per Pod (sidecar). The app sends to `localhost`/the node. | Low | Production. Decouples the app from backend availability. |
| **Gateway** | ⭐ A central Collector Deployment/StatefulSet. Agents (or apps) send to it; it fans out to backends. | Lowest | Tail sampling, PII redaction, multi-backend routing |

**The recommended production topology — Agent + Gateway:**

```
app ──OTLP──► node agent (DaemonSet) ──OTLP──► gateway (Deployment, 3 replicas)
                · k8s attributes                · tail sampling ⭐ (needs ALL spans of a trace)
                · resource detection            · PII redaction
                · batch (small)                 · batch (large)
                · localhost, so no network      · retry, load balancing
                  risk for the app              · fan out to Tempo + Datadog + …
```

> 🔑 **Tail-based sampling MUST happen in a gateway**, because it needs to see every span of a trace before deciding. If spans from one trace arrive at three different agent instances, no single agent can make the decision. That's the whole reason the two-tier topology exists.

### 12.4 Instrumentation: zero-code vs code-based

| | **Zero-code / auto** | **Code-based / manual** |
|---|---|---|
| How | A Java agent JAR; Python's `opentelemetry-instrument`; Node's `--require`; the **OTel Operator** injecting them | You import the SDK and write `tracer.startSpan(...)` |
| Coverage | HTTP servers/clients, gRPC, JDBC/SQLAlchemy/pgx, Kafka, RabbitMQ, Redis, MongoDB, logging frameworks | **Your business logic** |
| Effort | ~Zero | Real |
| What you get | A complete distributed trace of the request path, automatically | Domain spans: "validate cart", "apply discount", "reserve inventory" |
| Do you need it? | ⭐ **Start here.** It's 90% of the value for 1% of the effort. | Add later, where the auto-instrumentation can't see |

**The right answer is both:** auto-instrumentation for the plumbing, manual spans for your domain logic, and manual **attributes** (`order.id`, `customer.tier`) that make traces searchable.

| Language | Zero-code mechanism |
|---|---|
| **Java** | `-javaagent:/otel/opentelemetry-javaagent.jar` — the most complete by far |
| **Python** | `opentelemetry-instrument python app.py`, or set env vars |
| **Node.js** | `node --require @opentelemetry/auto-instrumentations-node/register app.js` |
| **Go** | ❌ **No zero-code** (it's statically compiled). Use `otel-go-instrumentation` (eBPF, experimental) or instrument manually. |
| **.NET** | `dotnet --add-package` + env vars, or the `DOTNET_STARTUP_HOOKS` mechanism |
| **Ruby / PHP** | Gem / extension based |
| **Rust** | Manual, or eBPF |

### 12.5 OTLP — the protocol

| Transport | Port | Content type | Notes |
|---|---|---|---|
| **OTLP/gRPC** | **4317** | protobuf | ⭐ The default; efficient, streaming |
| **OTLP/HTTP** | **4318** | protobuf or JSON | Easier through proxies/firewalls; paths `/v1/traces`, `/v1/metrics`, `/v1/logs` |

```bash
# the env vars the SDKs read (they're standardised — the same in every language) ⭐
OTEL_SERVICE_NAME=shop-api
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=prod,service.version=1.2.0,team=platform
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.monitoring:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc            # or http/protobuf
OTEL_TRACES_EXPORTER=otlp                   # otlp | jaeger | zipkin | console | none
OTEL_METRICS_EXPORTER=otlp                  # otlp | prometheus | console | none
OTEL_LOGS_EXPORTER=otlp
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
OTEL_EXPORTER_OTLP_HEADERS=x-api-key=secret
OTEL_PROPAGATORS=tracecontext,baggage
OTEL_METRIC_EXPORT_INTERVAL=60000
OTEL_BSP_SCHEDULE_DELAY=5000                # the batch span processor's delay
OTEL_JAVAAGENT_EXTENSIONS=…
OTEL_INSTRUMENTATION_HIBERNATE_ENABLED=false
```

> 🔑 **`OTEL_SERVICE_NAME` is the single most important variable.** It becomes `service.name`, which is the primary key in every trace UI. If you don't set it you get `unknown_service:java` and your traces are useless.

```bash
# send a trace by hand, to prove the pipeline works ⭐
curl -XPOST http://localhost:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d '{
  "resourceSpans": [{
    "resource": {"attributes": [{"key":"service.name","value":{"stringValue":"manual-test"}}]},
    "scopeSpans": [{
      "spans": [{
        "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
        "spanId":  "051581bf3cb55c13",
        "name": "test-span",
        "kind": 1,
        "startTimeUnixNano": "1757412345000000000",
        "endTimeUnixNano":   "1757412345500000000",
        "attributes": [{"key":"http.request.method","value":{"stringValue":"GET"}}],
        "status": {"code": 1}
      }]
    }]
  }]
}'
# {"partialSuccess":{}}     ← ✅ accepted
```

### 12.6 Semantic conventions — why attribute names matter

OpenTelemetry defines **standard attribute names** so a trace from a Java service and a trace from a Go service mean the same thing, and so tooling can build generic dashboards.

| Area | Attribute | Old (deprecated) name |
|---|---|---|
| HTTP | `http.request.method` | `http.method` |
| HTTP | `http.response.status_code` | `http.status_code` |
| HTTP | `url.full`, `url.path`, `url.scheme` | `http.url`, `http.target` |
| HTTP | `server.address`, `server.port` | `net.peer.name`, `net.peer.port` |
| HTTP | `client.address` | `net.peer.ip` |
| HTTP | `network.protocol.version` | `http.flavor` |
| RPC | `rpc.system`, `rpc.service`, `rpc.method` | |
| DB | `db.system` (`postgresql`, `mysql`, `redis`), `db.namespace`, `db.operation.name`, `db.query.text` | `db.statement` |
| Messaging | `messaging.system`, `messaging.destination.name`, `messaging.operation.name`, `messaging.message.id` | |
| FaaS | `faas.trigger`, `faas.name` | |
| Service | `service.name`, `service.version`, `service.namespace`, `service.instance.id` | |
| Deployment | `deployment.environment` (`prod`/`staging`) | `deployment.environment.name` |
| K8s | `k8s.namespace.name`, `k8s.pod.name`, `k8s.deployment.name`, `k8s.node.name`, `k8s.cluster.name` | |
| Host | `host.name`, `host.id`, `os.type` | |
| Exception | `exception.type`, `exception.message`, `exception.stacktrace` | |

⚠️ **The conventions were renamed in 2023–2024** (the "stable HTTP semconv" migration). Old and new names coexist in the wild. If your Tempo query for `http.method` returns nothing, try `http.request.method`.

### 12.7 What OTel does for each signal

| Signal | Maturity in OTel | Notes |
|---|---|---|
| **Traces** | ⭐ **Stable, excellent** | This is OTel's origin and strongest area |
| **Metrics** | Stable | Can replace Prometheus client libraries, but most teams still expose `/metrics` and let Prometheus scrape |
| **Logs** | Stable-ish | The bridge: OTel doesn't replace your logging framework, it **transforms** existing logs (Log4j, Logback, Python logging, zap) into OTLP log records **with trace context injected** |
| **Profiles** | In development (OTEP) | Pyroscope/Parca speak their own protocols for now |
| **Baggage** | Stable | Propagate business context (tenant ID) across services — ⚠️ it's visible to every hop, so no secrets |

**The most valuable thing OTel does for logs is not collecting them — it's correlation:**

```
BEFORE (Loki, no trace context):
  {"level":"ERROR","msg":"Payment declined","orderId":"ord_9f2a"}
  → you see an error. Which request? Which user? You grep by timestamp.

AFTER (OTel Logback appender, same log line):
  {"level":"ERROR","msg":"Payment declined","orderId":"ord_9f2a",
   "trace_id":"4bf92f3577b34da6a3ce929d0e0e4736",
   "span_id":"00f067aa0ba902b7",
   "service.name":"shop-api","k8s.pod.name":"shop-api-7d4f8c9b6-abcde"}
  → click the trace_id in Grafana → the exact waterfall → every other log line
    from every service in that request.
```

That single `trace_id` field is worth more than any dashboard.

---

<a name="13-tracing-in-depth"></a>
## 13. Tracing in depth

### 13.1 Spans

A **span** is one unit of work, with a start, an end, and a parent.

```json
{
  "trace_id":  "4bf92f3577b34da6a3ce929d0e0e4736",   // 16 bytes / 32 hex chars — the whole request
  "span_id":   "00f067aa0ba902b7",                   // 8 bytes / 16 hex chars — this unit of work
  "parent_span_id": "a2fb4a1d1a96d312",              // who created me (absent for the root)
  "name": "POST /api/orders",                        // ⭐ low-cardinality! Not "order ord_9f2a"
  "kind": "SERVER",                                  // SERVER | CLIENT | PRODUCER | CONSUMER | INTERNAL
  "start_time": 1757412345000000000,                 // nanoseconds
  "end_time":   1757412345831000000,
  "status": {"code": "ERROR", "message": "payment declined"},
  "attributes": {
    "http.request.method": "POST",
    "url.path": "/api/orders",
    "http.response.status_code": 402,
    "order.id": "ord_9f2a1b",                        // ⭐ searchable business context
    "customer.tier": "gold",
    "db.system": "postgresql",
    "k8s.namespace.name": "shop",
    "k8s.pod.name": "shop-api-7d4f8c9b6-abcde",
    "service.name": "shop-api",
    "service.version": "1.2.0",
    "deployment.environment": "prod"
  },
  "events": [                                        // timestamped points INSIDE the span
    {"time": 1757412345120000000, "name": "cache.miss", "attributes": {"key": "cart:8821"}},
    {"time": 1757412345700000000, "name": "retry", "attributes": {"attempt": 2}}
  ],
  "links": [                                         // ⭐ causal links to OTHER traces
    {"trace_id": "…", "span_id": "…", "attributes": {"reason": "batch-item"}}
  ],
  "resource": { … }                                  // the entity that produced it (the service, the host)
}
```

**Span kinds** matter because they tell the backend how to draw the waterfall and how to compute service-to-service latency:

| Kind | Meaning | Example |
|---|---|---|
| `SERVER` | Handling an inbound request | An HTTP handler |
| `CLIENT` | Making an outbound call | An HTTP client, a DB driver |
| `PRODUCER` | Sending a message (async) | Publishing to Kafka |
| `CONSUMER` | Receiving a message (async) | A Kafka consumer |
| `INTERNAL` | An in-process operation | "validate cart" |

**A `PRODUCER`→`CONSUMER` pair is how you trace across a queue**, where there's no synchronous parent-child relationship. The consumer span *links* to the producer span.

### 13.2 Context propagation — the hard part

For a trace to span services, the `trace_id` and `parent_span_id` must **travel with the request**. That's context propagation.

```
shop-ui                          shop-api                        payment-svc
   │                                │                                │
   │ traceparent: 00-4bf9…-00f0…-01 │                                │
   ├───────────────────────────────►│  extract the context           │
   │                                │  create a child span           │
   │                                │  traceparent: 00-4bf9…-a2fb…-01│
   │                                ├───────────────────────────────►│
   │                                │                                │  same trace_id!
```

**W3C Trace Context** — the standard, and the default:

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             │  │                                │                │
             │  │                                │                └─ flags (01 = sampled)
             │  │                                └─ parent span id (16 hex)
             │  └─ trace id (32 hex)
             └─ version
tracestate: vendor1=xxx,vendor2=yyy           ← vendor-specific extra data
```

| Propagator | Header | Used by |
|---|---|---|
| **`tracecontext`** (W3C) | `traceparent`, `tracestate` | ⭐ The default and the standard |
| `baggage` (W3C) | `baggage` | Business context across hops |
| `b3` / `b3multi` | `X-B3-TraceId`, `X-B3-SpanId`, … or a single `b3` header | Zipkin, older Istio/Envoy |
| `jaeger` | `uber-trace-id` | Legacy Jaeger |
| `aws` | `X-Amzn-Trace-Id` | AWS ALB, X-Ray |
| `ottrace` | `ot-tracer-*` | OpenTracing |

```bash
# ⭐ configure the propagators
OTEL_PROPAGATORS=tracecontext,baggage           # the default
OTEL_PROPAGATORS=tracecontext,b3                # to interoperate with a Zipkin/Istio system
OTEL_PROPAGATORS=tracecontext,baggage,b3,jaeger # talk to everything

# verify propagation works
curl -sv http://shop-api/api/orders -H 'traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'
# then search Tempo for trace_id 4bf92f3577b34da6a3ce929d0e0e4736 — your curl should be the root
```

**Where propagation breaks (the classic failures):**

| Break | Why | Fix |
|---|---|---|
| A thread pool / `CompletableFuture` | The context is thread-local; a new thread has none | Wrap the executor: `Context.taskWrapping(executor)`, or the OTel Java agent does it for common pools |
| Kotlin coroutines | Same | `opentelemetry-context` + `asContextElement()` |
| React/Node async hooks | Needs `AsyncLocalStorage` | The Node SDK handles it if you use the standard http modules |
| A message queue | No HTTP headers | Put the context in the message headers; use a PRODUCER/CONSUMER pair |
| A cron job | Nothing to extract from | Start a new root span |
| A load balancer that strips headers | `traceparent` isn't forwarded | Configure the LB to pass it |
| A gRPC call without the interceptor | The metadata isn't injected | Add the OTel gRPC interceptor |
| **Two services with different propagators** | One sends `b3`, the other reads `tracecontext` | ⭐ Set the same `OTEL_PROPAGATORS` everywhere |
| A mobile/browser client | No SDK | Inject `traceparent` from the frontend SDK, or accept a broken chain at the edge |

### 13.3 Sampling — the cost control

At 10,000 req/s, tracing everything is impossible. You sample.

| Strategy | When the decision is made | Pros | Cons |
|---|---|---|---|
| **Head-based** | ⭐ At the **root span**, before anything happens | Cheap, simple, consistent across the whole trace (the decision propagates in `traceparent`) | **You can't know if the trace is interesting yet.** You throw away 90% including 90% of the errors. |
| **Tail-based** | In the **Collector**, after all spans arrive | ⭐ Keep 100% of errors and slow traces, sample the boring ones | Needs a buffering Collector that sees every span of a trace; memory-heavy |
| **Adaptive / probabilistic** | Per-service, adjusting rates | Balanced | Complex |

```bash
# HEAD-BASED sampling — in the app
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1                  # 10%
```

| Sampler | Behaviour |
|---|---|
| `always_on` | Trace everything |
| `always_off` | Trace nothing |
| `traceidratio` | A deterministic % based on the trace ID |
| `parentbased_always_on` | ⭐ Follow the parent's decision; if no parent, sample |
| **`parentbased_traceidratio`** | ⭐⭐ **The default and the right choice.** Follows the parent, so a whole trace is consistently in or out |
| `parentbased_always_off` | |

> 🔑 **Why `parentbased_*` matters:** without it, service A might sample a trace and service B might not — you get a trace with holes. `parentbased` means the root's decision propagates in the `traceparent` flags and **every downstream service honours it.** One trace is either fully present or fully absent.

```yaml
# TAIL-BASED sampling — in the Collector ⭐⭐
processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
  tail_sampling:
    decision_wait: 10s                # ⭐ how long to buffer spans waiting for the rest of the trace
    num_traces: 100000                # how many traces to hold in memory
    expected_new_traces_per_sec: 1000
    policies:
      - name: keep-all-errors         # ⭐⭐ NEVER drop an error
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: keep-slow-traces
        type: latency
        latency: {threshold_ms: 1000}          # anything over 1s
      - name: keep-5xx
        type: numeric_attribute
        numeric_attribute: {key: http.response.status_code, min_value: 500}
      - name: keep-checkout           # a whole business flow, always
        type: string_attribute
        string_attribute: {key: url.path, values: [/api/checkout, /api/orders], invert_match: false}
      - name: sample-the-rest
        type: probabilistic
        probabilistic: {sampling_percentage: 10}
      - name: keep-new-versions       # 100% of a canary
        type: string_attribute
        string_attribute: {key: service.version, values: ["1.3.0-rc1"]}
```

```yaml
# the classic production policy: 100% of errors and slow traces, 10% of the rest
# ⭐ order matters — the first matching policy wins (unless `and` composition is used)
```

| Setting | Guidance |
|---|---|
| `decision_wait` | Longer = more complete traces, more memory. 10s for a web app; 30s+ if you have long async chains |
| `num_traces` | `expected_new_traces_per_sec × decision_wait × 1.5` |
| Where it runs | ⭐ **The gateway Collector only** — it must see every span |
| Memory | Tail sampling is the Collector's biggest memory consumer. Give it real limits and `memory_limiter` first in the chain |

### 13.4 TraceQL — querying traces (Tempo)

```
{}                                                      # everything (don't)
{ .service.name = "shop-api" }                          # by service
{ .duration > 1s }                                      # ⭐ slow traces
{ status = error }                                      # ⭐ failed traces
{ .http.response.status_code = 500 }
{ .http.request.method = "POST" && .url.path = "/api/orders" }
{ resource.k8s.namespace.name = "shop" && .duration > 500ms }
{ span.http.status_code = 500 || span.status = error }
{ .order.id = "ord_9f2a1b" }                            # ⭐ by a business attribute
{ .customer.tier = "gold" && .duration > 2s }

# the structural queries — TraceQL's killer feature
{ .service.name = "shop-api" && .service.name = "payment-svc" }   # traces touching BOTH
{ span.service.name = "shop-api" } >> { span.service.name = "postgres" }   # descendant
{ .service.name = "shop-api" } | rate() by (.http.response.status_code)    # aggregate!
{ .duration > 1s } | count_over_time()
{ .service.name = "shop-api" } | avg(.duration) by (.url.path)
```

```bash
# the Tempo HTTP API
curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name="shop-api" && .duration > 1s }' \
  --data-urlencode 'limit=20' | jq '.traces[] | {traceID, rootServiceName, durationNanos, startTime}'

curl -s localhost:3200/api/traces/4bf92f3577b34da6a3ce929d0e0e4736 | jq .
curl -s localhost:3200/api/search/tags | jq .
curl -s 'localhost:3200/api/search/tag/service.name/values' | jq .
```

### 13.5 What a good trace looks like — and a bad one

```
✅ GOOD
Trace 4bf9…  total 842ms  status=ERROR
├─ shop-ui      GET /checkout                      842ms   SERVER
│  └─ shop-api  POST /api/orders                   831ms   SERVER   [order.id=ord_9f2a]
│     ├─ auth    verify-token                       12ms   CLIENT
│     ├─ postgres SELECT inventory                  48ms   CLIENT   [db.query.text=…]
│     ├─ redis   GET cart:8821                       2ms   CLIENT
│     ├─ payment POST /v1/charge                   712ms   CLIENT   ← the bottleneck is obvious
│     │  └─ stripe-svc  (external, linked)         700ms
│     └─ rabbitmq publish order.created              4ms   PRODUCER
│        └─ order-worker  consume order.created    180ms   CONSUMER  (linked, async)

⛔ BAD
├─ HTTP GET                                           1ms        ← no service name
├─ HTTP GET                                           1ms        ← which one?
├─ internal operation                                 842ms      ← what operation?
├─ SELECT * FROM orders WHERE id = 'ord_9f2a1b'       48ms       ← ⛔ the span NAME is the query
└─ order ord_9f2a1b for customer cus_8821            712ms       ← ⛔ unbounded cardinality
```

**Span naming rules:**

1. **Low cardinality.** `/api/orders/{id}`, never `/api/orders/ord_9f2a1b`.
2. **Meaningful.** `POST /api/orders`, not `HTTP POST` or `internal`.
3. **Business context goes in ATTRIBUTES**, not the name: `order.id=ord_9f2a1b`.
4. **One span per meaningful unit of work**, not per function call (that's profiling's job).
5. **Set the status.** `span.setStatus(ERROR)` on failure, or your error-rate metrics from traces will be zero.
6. **Record exceptions as events** — `span.recordException(e)` gives you the stack trace in the UI.

---

<a name="14-the-observability-landscape"></a>
## 14. The landscape: what replaces what

### The OSS stack in this path

| Concern | Tool | Alternative |
|---|---|---|
| Metrics storage/query | **Prometheus** | VictoriaMetrics (cheaper, faster, PromQL-compatible), Thanos, Mimir |
| Metrics at global scale | **Mimir / Thanos / VictoriaMetrics** | Cortex (Mimir's predecessor) |
| Dashboards | **Grafana** | Perses, OpenObserve |
| Alerting | **Alertmanager** | Grafana Alerting, Robusta |
| Host metrics | **node_exporter** | Grafana Alloy, Datadog agent |
| K8s object state | **kube-state-metrics** | — |
| Probing | **blackbox_exporter** | Grafana Synthetic Monitoring |
| Logs | **Loki** | Elasticsearch/OpenSearch (heavier, full-text), VictoriaLogs, ClickHouse |
| Log collection | **Alloy / Promtail / Fluent Bit / Vector** | Fluentd, Logstash |
| Traces | **Tempo** | Jaeger, Sigv4, Zipkin, ClickHouse |
| Instrumentation | **OpenTelemetry** | Vendor SDKs (avoid) |
| Collector | **OTel Collector** | Grafana Alloy (a distribution of it), Vector |
| Profiling | **Pyroscope** | Parca, Elastic Universal Profiling |
| SLO tooling | **sloth**, Nobl9 | Grafana SLO, Datadog SLOs |
| K8s observability | **Coroot**, Robusta, k8sgpt | |
| Cost | **OpenCost** | Kubecost |

### LGTM = Loki, Grafana, Tempo, Mimir

Grafana Labs' stack. All four speak the same query patterns and integrate in Grafana with one click between signals. **This is the most coherent OSS option today** and what the capstone uses.

| Component | Signal | Query language |
|---|---|---|
| **L**oki | Logs | LogQL |
| **G**rafana | Dashboards | — |
| **T**empo | Traces | TraceQL |
| **M**imir | Metrics | PromQL |

### The cloud vendors, translated

| Concept | AWS | Azure | GCP | Datadog |
|---|---|---|---|---|
| Metrics | CloudWatch Metrics | Azure Monitor / Metrics | Cloud Monitoring | Metrics |
| Logs | CloudWatch Logs | Log Analytics | Cloud Logging | Log Management |
| Traces | X-Ray | Application Insights | Cloud Trace | APM |
| Instrumentation | ADOT (an OTel distro) | Azure Monitor OTel Distro | Cloud Trace/OTel | dd-trace-* |
| Dashboards | CloudWatch Dashboards / Grafana AMG | Azure Workbooks / Managed Grafana | Looker Studio / Managed Grafana | Dashboards |
| Alerting | CloudWatch Alarms | Action Groups / Alert Rules | Alerting Policies | Monitors |
| SLOs | CloudWatch Application Signals | Service Level Objectives | SLOs | SLOs |
| Profiling | CodeGuru Profiler | — | Cloud Profiler | Continuous Profiler |
| Synthetic | CloudWatch Synthetics | Availability Tests | Uptime Checks | Synthetic Monitoring |
| Kubernetes | Container Insights / EKS | Container Insights / AKS | GKE Observability | Kubernetes |

> 🔑 **The interview line:** *"We used OTel for instrumentation so the backend is a config decision. Locally we run the LGTM stack — Prometheus/Mimir, Loki, Tempo, Grafana. On AWS the same OTLP goes to ADOT and lands in X-Ray and CloudWatch; nothing in the application changes."* That's the correct answer, and it's true.

### Prometheus vs VictoriaMetrics vs Mimir vs Thanos

| | Prometheus | VictoriaMetrics | Mimir | Thanos |
|---|---|---|---|---|
| Model | Single server, local TSDB | Single or cluster | Microservices (Cortex lineage) | Sidecar + object storage |
| Scale | ~5–10M active series | ~50M+ per node | Billions | Billions |
| Query language | PromQL | **MetricsQL** (a PromQL superset — mostly compatible) | PromQL | PromQL |
| Storage | Local disk | Local disk | **Object storage (S3)** | **Object storage (S3)** |
| Downsampling | ❌ | ✅ | ✅ | ✅ |
| Deduplication | ❌ | ✅ | ✅ | ✅ |
| Global view | ❌ | ✅ | ✅ | ✅ |
| Complexity | ⭐ **Lowest** | Low | High | High |
| Best for | < ~5M series, one cluster | A drop-in that's cheaper and faster | Huge multi-tenant | Large, already Prometheus-native |

**Start with Prometheus. Move to VictoriaMetrics if you hit scale or cost and want minimal change; to Mimir if you need multi-tenancy; to Thanos if you're deeply Prometheus-native and want object storage.**

---

<a name="15-the-incident-workflow"></a>
## 15. The incident workflow

The drill you should be able to run in your sleep:

```
T+0:00   The page arrives
         "ShopApiHighErrorRate — 4.2% of requests are 5xx, sustained 5 minutes"
         → click the RUNBOOK link in the annotation (this is why it's mandatory)

T+0:30   ORIENT — is this real, and how big?
         Open the SLO dashboard.
         · Error budget burn rate = 42× → this is a fast burn, real incident
         · Which endpoints?  → the RED table: /api/orders 8.1%, /api/items 0.2%
         · Which pods?       → all 6, evenly → NOT one bad pod
         · Did we deploy?    → the annotation timeline on the dashboard: v1.3.0 at 14:28
                                ⭐ THE DEPLOY IS 4 MINUTES BEFORE THE SPIKE

T+1:30   LOCALIZE — where in the request is the time/error?
         Click an EXEMPLAR on the error-rate graph → a real trace → Tempo
         The waterfall shows:
           POST /api/orders                       842ms  ERROR
             ├─ auth verify-token                  12ms  OK
             ├─ postgres SELECT inventory          48ms  OK
             ├─ payment POST /v1/charge           712ms  ERROR ← ⭐
             │    attributes: http.response.status_code=503
             │                 error.type=PaymentProviderUnavailable
             └─ rabbitmq publish                    4ms  OK

T+3:00   EXPLAIN — why?
         Click "Logs for this span" (the trace_id join) → Loki
         shop-api  14:32:11 ERROR PaymentClient — provider returned 503, retry 3/3 exhausted
         shop-api  14:32:11 WARN  CircuitBreaker — opening circuit for payment-svc
         → It's the payment provider. But WHY did it start at 14:28?

T+4:00   CONFIRM — was it us or them?
         Check the client-side vs server-side duration for payment-svc:
           our CLIENT span = 712ms   their SERVER span = 8ms
         → THEY are fast; WE are slow. So it's not their latency.
         Check the deploy diff: v1.3.0 changed the payment client's timeout from 5s to 500ms.
         ⭐ ROOT CAUSE: our new timeout is shorter than the provider's normal p99.
                    Every request now times out and retries 3×, tripping the circuit breaker.

T+6:00   MITIGATE
         kubectl rollout undo deploy/shop-api -n shop     (or: Argo CD → revert the commit)
         kubectl rollout status deploy/shop-api -n shop
         Watch the error-rate panel → drops to 0.2% in 90 seconds.
         Resolve the alert. Post in #incident-1234.

T+1 day  LEARN
         · Why did the timeout change not get caught?  → no load test with realistic latency
         · Why did the alert take 5 minutes?           → `for: 5m` on a total outage; add a
                                                          fast-burn 14.4×/2m SLO alert
         · Why did we have to click through 3 tools?   → the exemplar link worked; good
         · Action items with owners and dates.
```

**The tooling decisions that make this possible:**

| Step | Requires |
|---|---|
| Orient | An SLO dashboard + a **deploy annotation** on every graph |
| Localize | **Exemplars** — metrics linked to traces |
| Explain | **trace_id in the logs** — logs linked to traces |
| Confirm | Client-side *and* server-side spans (so you can tell who's slow) |
| Mitigate | `kubectl rollout undo` that works, i.e. revision history and a tested rollback |

**Build the links before you need them.** Every one of them is a Case 1 / Case 2 / Capstone exercise.

---

<a name="16-common-beginner-mistakes"></a>
## 16. Twenty common beginner mistakes

| # | Mistake | Why it hurts | Do this instead |
|---|---|---|---|
| 1 | Using a **Summary** instead of a Histogram | Can't aggregate percentiles across pods | Histograms, always |
| 2 | `histogram_quantile` without `by (le)` | Returns NaN or one line per pod | Always `sum(rate(x_bucket[..])) by (le)` |
| 3 | `rate()` on a gauge | Silent garbage | `delta()` / `deriv()` |
| 4 | A `rate()` window < 4× the scrape interval | Gaps and spikes | `[5m]`, or `$__rate_interval` in Grafana |
| 5 | A **high-cardinality label** (user_id, request_id, raw URI) | Prometheus OOMs | Bounded labels only; templated URIs |
| 6 | Alerting on **causes** (CPU > 80%) | Alert fatigue; pages for non-incidents | Alert on symptoms (RED, SLO burn rate) |
| 7 | No `for:` on an alert | A single blip pages someone | Always `for:`, sized to the signal |
| 8 | No **runbook** link | The 3am responder guesses | `annotations.runbook_url` on every alert |
| 9 | `repeat_interval: 5m` | 288 pages/day | 4h critical, 24h warning |
| 10 | No **inhibition** rules | One node failure = 200 alerts | Inhibit pod alerts on node alerts |
| 11 | A liveness-style alert on every metric | Noise | Two severities: `critical` pages, `warning` tickets |
| 12 | Pushing a long-running service's metrics to **Pushgateway** | Loses `up`, loses discovery, stale values forever | Let Prometheus scrape it |
| 13 | Not setting `OTEL_SERVICE_NAME` | Traces show `unknown_service:java` | Set it explicitly, everywhere |
| 14 | **Head sampling at 1%** with no tail sampling | You lose 99% of your errors | Head 10–100% + **tail** sampling in the Collector |
| 15 | Tail sampling in the **agent** instead of the gateway | No single agent sees the whole trace | A central gateway Collector |
| 16 | Span names with IDs (`/api/orders/ord_123`) | Trace-backend cardinality explosion | The route template; IDs go in attributes |
| 17 | Forgetting to **set the span status** on error | Error-rate-from-traces is always 0% | `span.setStatus(ERROR)` + `recordException` |
| 18 | No `memory_limiter` as the **first** Collector processor | The Collector OOMs and drops everything | `memory_limiter` first, `batch` last |
| 19 | Building dashboards by **clicking** and never committing them | Lost on the next redeploy; unreviewable | Dashboards as code (ConfigMaps / Grafana Operator / Terraform) |
| 20 | No **correlation**: metrics, logs and traces in three unlinked tools | The 3-tool-tab dance during an incident | Exemplars + `trace_id` in logs + derived fields in Grafana |

**Bonus, the three architecture mistakes:**

| Mistake | Consequence |
|---|---|
| One Prometheus for the whole company, no federation | A single point of failure; unqueryable at scale |
| Long-term retention in Prometheus's local TSDB | The node's disk fills; restarts take an hour |
| Logging *everything* at INFO in production | Loki costs more than the cluster; the useful lines are unfindable |

---

## Where to go next

| You want | Read |
|---|---|
| ⭐ **CASE 1** — build Prometheus + Grafana + Alertmanager | [02-CASE-1-prometheus-grafana.md](./02-CASE-1-prometheus-grafana.md) |
| ⭐ **CASE 2** — build the OpenTelemetry pipeline | [03-CASE-2-telemetry.md](./03-CASE-2-telemetry.md) |
| The whole thing unified, with tasks + answers | [04-CAPSTONE-END-TO-END.md](./04-CAPSTONE-END-TO-END.md) |
| PromQL / Grafana / Alertmanager / OTel on one page | [05-CHEATSHEET.md](./05-CHEATSHEET.md) |
| Do it all in one day | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
