# 📋 Monitoring & Alerting — The Complete Cheatsheet

> **One file. Everything you type.** PromQL · LogQL · TraceQL · Prometheus CLI · Alertmanager · Grafana · OpenTelemetry Collector · OTel SDKs (Java/Go/Python/JS) · sloth · exporters · troubleshooting.
>
> Print it. Keep it open in a second monitor. It is the companion to [Case 1](./02-CASE-1-prometheus-grafana.md), [Case 2](./03-CASE-2-telemetry.md) and the [Capstone](./04-CAPSTONE-END-TO-END.md).

---

## Table of contents

| # | Section |
|---|---|
| [1](#1--promql--the-complete-reference) | **PromQL** — the complete reference |
| [2](#2--the-30-queries-you-actually-use) | The 30 queries you actually use |
| [3](#3--logql--loki) | **LogQL** — Loki |
| [4](#4--traceql--tempo) | **TraceQL** — Tempo |
| [5](#5--prometheus-cli--http-apis) | Prometheus CLI & HTTP APIs |
| [6](#6--alertmanager--amtool) | Alertmanager & `amtool` |
| [7](#7--grafana) | Grafana — panels, variables, provisioning, APIs |
| [8](#8--opentelemetry-collector) | OpenTelemetry Collector — config, processors, pipelines |
| [9](#9--otel-sdks--env-vars-per-language) | OTel SDKs — env vars per language |
| [10](#10--instrumentation-recipes) | Instrumentation recipes (Java / Go / Python / JS) |
| [11](#11--slos--sloth) | SLOs & sloth |
| [12](#12--exporters--the-reference-table) | Exporters — ports, flags, key metrics |
| [13](#13--kubernetes-observability-commands) | Kubernetes observability commands |
| [14](#14--cardinality--the-audit-toolkit) | Cardinality — the audit toolkit |
| [15](#15--ci-validation-commands) | CI validation commands |
| [16](#16--the-troubleshooting-decision-trees) | The troubleshooting decision trees |
| [17](#17--helm-commands) | Helm commands |
| [18](#18--interview-quick-fire--60-questions-60-answers) | Interview quick-fire — 60 questions, 60 answers |

---

<a name="1--promql--the-complete-reference"></a>
## 1 · PromQL — the complete reference

### 1.1 The data model

```
metric_name{label1="value1", label2="value2"}   →  a TIME SERIES
                                                   (a unique set of label values)

  http_server_requests_seconds_count{application="shop-api", uri="/api/orders", status="200"}
  └──────────────┬──────────────┘ └──────────────────────────┬─────────────────────────────┘
            metric name                            the label set = the series identity

  ⭐ EVERY DISTINCT COMBINATION OF LABEL VALUES IS A SEPARATE SERIES, stored separately.
     That is why cardinality is the thing that kills Prometheus.
```

### 1.2 The four data types

| Type | What | Example |
|---|---|---|
| **Instant vector** | A set of series, each with ONE value at ONE timestamp | `up`, `node_load1` |
| **Range vector** | A set of series, each with a RANGE of values over time | `up[5m]`, `rate(x[1h])` — wait, `rate` returns an instant vector |
| **Scalar** | A single float | `time()`, `2 + 3` |
| **String** | Rarely used | `"hello"` |

```promql
up              # instant vector — one value per series, right now
up[5m]          # ⭐ range vector — 5 minutes of samples per series
                #   ONLY valid as the argument to a function (rate, increase, …)
rate(up[5m])    # instant vector again
time()          # scalar
```

### 1.3 Selectors

```promql
# ── exact ────────────────────────────────────────────────────────
node_cpu_seconds_total
node_cpu_seconds_total{mode="idle"}
node_cpu_seconds_total{mode="idle", cpu="0"}

# ── the four matchers ────────────────────────────────────────────
{job="prometheus"}              # =   equal
{job!="prometheus"}             # !=  not equal
{job=~"prom.*|alert.*"}         # =~  regex match (FULLY anchored — no .* needed at the ends)
{job!~"test.*"}                 # !~  regex NOT match

# ┭ regexes are ANCHORED. {job=~"prom"} matches ONLY "prom", not "prometheus".
#    Use {job=~"prom.*"} or {job=~".*prom.*"} for a substring.

# ── the special __name__ label ───────────────────────────────────
{__name__="up"}                             # identical to: up
{__name__=~"container_.*"}                  # every metric starting with container_
{__name__=~".+", namespace="shop"}          # ⭐ EVERY series in a namespace (expensive!)

# ── time range on a selector ─────────────────────────────────────
http_requests_total[5m]                     # the last 5 minutes
http_requests_total{job="api"}[5m]          # ⭐ the selector comes BEFORE the range
http_requests_total[5m] offset 1h           # the same window, one hour ago
http_requests_total offset 1d               # the instant value, one day ago

# ── @ modifier (Prometheus 2.33+) ────────────────────────────────
http_requests_total @ 1609746000            # the value at a Unix timestamp
http_requests_total @ start()               # the value at the start of the query range
rate(http_requests_total[5m] @ end())       # at the end of the range
```

### 1.4 The metric type determines the query ⭐⭐

| Type | Behaviour | ⚠️ The rule | Correct query |
|---|---|---|---|
| **Counter** | Only ever increases; resets to 0 on restart | **NEVER plot raw.** Always `rate()` / `increase()` | `rate(http_requests_total[5m])` |
| **Gauge** | Goes up and down | Plot raw. Use `min/max/avg_over_time` for windows | `node_memory_MemAvailable_bytes` |
| **Histogram** | Cumulative `_bucket{le=…}`, plus `_sum` and `_count` | `histogram_quantile()` over `sum by (le) (rate(…_bucket[…]))` | see §1.8 |
| **Summary** | Pre-computed quantiles `{quantile="0.99"}` | **CANNOT be aggregated across instances.** ⛔ never `sum()` them | `api_request_duration_seconds{quantile="0.99"}` |

```promql
# ⭐ COUNTER — the reset is handled FOR YOU by rate()
http_requests_total                     # ⛔ a staircase, meaningless, and huge after a restart
rate(http_requests_total[5m])           # ✅ per second, averaged over 5m
irate(http_requests_total[5m])          # ✅ the last two points — spiky, for zoomed-in views
increase(http_requests_total[1h])       # ✅ the total increase over 1h (extrapolated!)

# ⭐ GAUGE
node_memory_MemAvailable_bytes          # ✅ raw
avg_over_time(node_load1[1h])           # ✅ smoothed
max_over_time(container_memory_working_set_bytes[1d])
min_over_time(jvm_memory_used_bytes{area="heap"}[10m])   # ⭐ the sawtooth FLOOR = leak detector
delta(node_disk_io_time_seconds_total[1h])               # for gauges, not counters
deriv(prometheus_tsdb_head_series[1h])                   # ⭐ the rate of change of a gauge

# ⭐ predict_linear — "when will this break?"
predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0     # fills within 4 hours
predict_linear(container_memory_working_set_bytes[2h], 3600)    # where will it be in 1h
```

### 1.5 Operators

```promql
# ── arithmetic (between two instant vectors, matched ON THEIR LABELS) ──
a + b     a - b     a * b     a / b     a % b     a ^ b

node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes     # used memory
rate(errors[5m]) / rate(total[5m])                              # ⚠️ division by zero → NaN

# ── comparison (filter, or bool) ────────────────────────────────
a == b    a != b    a > b    a < b    a >= b    a <= b

up == 0                                    # FILTER: returns only the series where up==0
up == bool 0                               # BOOL: returns ALL series, with value 0 or 1
node_load1 > 4                             # the loaded nodes
http_requests_total > bool 0               # 1 for every series with any traffic

# ── logical/set (only between instant vectors) ──────────────────
a and b          # series in a that ALSO have a matching series in b (returns a's values)
a or b           # series in a, plus series in b that aren't in a
a unless b       # series in a that have NO match in b

up == 0 and on(instance) node_uname_info   # a target that's down AND a known node
(method_code:http_errors:rate1m{code="500"} unless method_code:http_errors:rate1m{code="404"})

# ── aggregation operators ───────────────────────────────────────
sum     min     max     avg     group     stddev     stdvar
count   count_values    bottomk    topk    quantile    limitk    limit_ratio

sum(rate(http_requests_total[5m]))                      # one number
sum by (job) (rate(http_requests_total[5m]))            # ⭐ one number per job
sum without (instance) (rate(http_requests_total[5m]))  # ⭐ everything except instance
count by (namespace) (up)                               # how many targets per namespace
topk(5, sum by (pod) (container_memory_working_set_bytes))
bottomk(3, node_filesystem_avail_bytes)
count_values("version", build_info)                     # ⭐ groups by VALUE into a new label
quantile(0.95, sum by (le) (rate(x_bucket[5m])))        # ⚠️ NOT for histograms — see §1.8
stddev(rate(http_requests_total[5m]))

# ┭ by vs without — the one people get wrong
sum by (job) (x)         # keep ONLY job      → group everything else together
sum without (instance) (x)  # keep EVERYTHING EXCEPT instance
# `by` is safer: you know exactly what you'll get.

# ── aggregation over time (the _over_time family) ───────────────
avg_over_time(metric[5m])        max_over_time(metric[5m])
min_over_time(metric[5m])        sum_over_time(metric[5m])
count_over_time(metric[5m])      quantile_over_time(0.95, metric[5m])
stddev_over_time(metric[5m])     last_over_time(metric[5m])
present_over_time(metric[5m])    absent_over_time(metric[5m])
mad_over_time(metric[5m])        # median absolute deviation (Prometheus 2.45+)
```

### 1.6 Vector matching ⭐ the hardest part of PromQL

Two vectors only combine if their **label sets match**. When they don't, you must tell Prometheus how.

```promql
# ── the default: match on ALL labels ────────────────────────────
method_code:http_errors:rate1m / method_code:http_requests:rate1m    # works: identical labels

# ── ignoring / on ───────────────────────────────────────────────
a / ignoring(status_code) b        # match on everything EXCEPT status_code
a / on(job, instance) b            # match on ONLY job and instance

# ── the many-to-one problem (the one that always bites) ─────────
container_memory_working_set_bytes{namespace="shop"}
  / kube_pod_container_resource_limits{resource="memory"}
# ⛔ "many-to-many matching not allowed" — the label sets differ

# ⭐ group_left / group_right: "the LEFT side has many, the RIGHT has one"
container_memory_working_set_bytes
  / on(namespace, pod, container) group_left
    kube_pod_container_resource_limits{resource="memory"}

# ── and the classic: joining Kubernetes labels onto a metric ────
rate(container_cpu_usage_seconds_total[5m])
  * on(namespace, pod) group_left(label_team, label_tier)
    kube_pod_labels

# ── copying a label FROM the right side ─────────────────────────
node_load5 * on(instance) group_left(nodename) node_uname_info
# ⭐ now every series has a `nodename` label taken from node_uname_info

# ── label_replace: synthesise a label to make a join work ───────
label_replace(up{job="api"}, "host", "$1", "instance", "(.*):.*")
# ⭐ extracts "api-1" from "api-1:9090" into a new label `host`
label_replace(v, dst_label, replacement, src_label, regex)

# ── label_join: concatenate labels ──────────────────────────────
label_join(up, "combined", "-", "job", "instance")
```

**The four join patterns you'll use 95% of the time:**

```promql
# 1. RATIO with different label sets
sum by (pod) (a) / on(pod) group_left sum by (pod) (b)

# 2. ADD KUBERNETES LABELS to a cAdvisor metric
rate(container_cpu_usage_seconds_total[5m])
  * on(namespace, pod) group_left(label_app, label_team) kube_pod_labels

# 3. FILTER by a Kubernetes predicate
kube_pod_status_phase{phase="Running"} == 1
  and on(namespace, pod) container_memory_working_set_bytes

# 4. THE "is this pod over its limit" pattern
sum by (namespace, pod, container) (container_memory_working_set_bytes{namespace="shop"})
  / on(namespace, pod, container) group_left
    kube_pod_container_resource_limits{namespace="shop", resource="memory"}
```

### 1.7 The rate family, precisely

| Function | What it does | When to use | Gotcha |
|---|---|---|---|
| `rate(v[5m])` | Per-second average over the window | ⭐ **Dashboards and alerts** | Extrapolates at the window edges; not exact |
| `irate(v[5m])` | Per-second, using only the **last two** points | Zoomed-in, spiky debugging | ⛔ **Never in alerts** — too volatile |
| `increase(v[1h])` | Total increase over the window | "How many in the last hour?" | Extrapolated — can be fractional |
| `delta(v[1h])` | Difference for **gauges** | Gauge change over time | ⛔ not for counters (no reset handling) |
| `idelta(v[1h])` | The last-two-point delta for gauges | Rare | |
| `deriv(v[1h])` | Per-second slope via linear regression | ⭐ Trend detection on gauges | |
| `predict_linear(v[6h], 4*3600)` | Linear extrapolation | ⭐ "Disk fills in 4h" alerts | Assumes linearity |
| `resets(v[1h])` | Number of counter resets | Detecting restarts | |
| `changes(v[1h])` | Number of value changes | Config/deploy detection | |

```promql
# ⭐ THE RANGE WINDOW RULE — get this wrong and your graphs are wrong
#    range ≥ 4× the scrape interval. At a 30s scrape, use ≥ 2m; 5m is the norm.
rate(x[30s])    # ⛔ at a 30s scrape you often have only ONE sample → no rate at all
rate(x[2m])     # ⚠️ the minimum that works
rate(x[5m])     # ✅ the standard

# ⭐ in Grafana, ALWAYS use $__rate_interval — it auto-sizes to the panel width
rate(http_requests_total[$__rate_interval])
# $__rate_interval = max($__interval + scrape_interval, 4 × scrape_interval)
# $__interval     = the panel width / max data points  (use for increase, delta)
```

### 1.8 Histograms — the exact patterns ⭐⭐

```promql
# A histogram exposes three things:
#   x_bucket{le="0.1"}   cumulative count of observations ≤ 0.1
#   x_bucket{le="+Inf"}  == x_count (all observations)
#   x_sum                the sum of all observed values
#   x_count              the number of observations

# ── 1. THE QUANTILE (p50/p95/p99) ───────────────────────────────
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
# ⭐⭐ sum by (le) — you MUST keep `le`. Any other label you add splits the result.
histogram_quantile(0.99, sum by (le, uri) (rate(x_bucket[5m])))       # p99 per route
histogram_quantile(0.5,  sum by (le, instance) (rate(x_bucket[5m])))  # p50 per instance

# ── 2. THE MEAN ─────────────────────────────────────────────────
rate(http_request_duration_seconds_sum[5m])
  / rate(http_request_duration_seconds_count[5m])
# ⭐ this is EXACT. The quantile above is an INTERPOLATED ESTIMATE.

# ── 3. THE APDEX / SLI ("what fraction is under 300ms?") ────────
sum(rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))
  / sum(rate(http_request_duration_seconds_count[5m]))
# ⭐⭐ THIS is your latency SLO SLI. Exact, no interpolation error.

# ── 4. SLO with a per-route breakdown ───────────────────────────
sum by (uri) (rate(x_bucket{le="0.3"}[5m])) / sum by (uri) (rate(x_count[5m]))

# ── 5. the error ratio ──────────────────────────────────────────
sum(rate(x_count{status=~"5.."}[5m])) / clamp_min(sum(rate(x_count[5m])), 0.001)
# ⭐ clamp_min, ALWAYS. Otherwise zero traffic = NaN = a blank panel.

# ── 6. request rate ─────────────────────────────────────────────
sum(rate(x_count[5m]))                     # total rps
sum by (uri, method) (rate(x_count[5m]))   # rps per route

# ── 7. a heat-map query (Grafana format: Heatmap) ───────────────
sum by (le) (increase(x_bucket[$__rate_interval]))

# ⚠️ THE FOUR HISTOGRAM TRAPS
# 1. histogram_quantile INTERPOLATES within a bucket. If your bucket boundary is
#    at 1s and the true p99 is 1.05s, you get ~1s. CHOOSE BUCKETS AT YOUR SLO.
# 2. ⛔ NEVER average quantiles: avg(histogram_quantile(0.99, …)) is mathematically
#    meaningless. Always quantile-of-sums: histogram_quantile(0.99, sum by (le) (…))
# 3. ⛔ NEVER sum a summary's quantiles across instances.
# 4. histogram_quantile returns NaN if there are no samples → wrap in clamp_min
#    or add `or vector(0)`.
```

### 1.9 The functions you'll actually use

```promql
# ── absence and presence ⭐ (the "is it broken or is it missing?" pair)
absent(up{job="api"})                    # returns 1 if NO series matches; {} otherwise
absent_over_time(up{job="api"}[5m])      # returns 1 if no SAMPLES in the window
present_over_time(x[5m])

- alert: ApiMetricsMissing
  expr: absent(up{job="api"} == 1)
  for: 5m
  # ⭐ this fires when the metric disappears — which `up == 0` does NOT cover
  #   if the target itself is removed from the config.

# ── time
time()                                   # the current Unix time (a scalar)
timestamp(vector(1))
time() - process_start_time_seconds      # uptime
(time() - node_boot_time_seconds) / 86400  # uptime in days

# ── rounding and maths
round(x, 0.1)      floor(x)      ceil(x)      abs(x)      sgn(x)
clamp_min(x, 0)    clamp_max(x, 100)    clamp(x, 0, 100)
sqrt(x)  exp(x)  ln(x)  log2(x)  log10(x)
sgn(x)   # -1, 0 or 1

# ── sorting and limiting
topk(5, x)    bottomk(5, x)
limitk(5, x)               # ⭐ returns AT MOST 5 series, unsorted (cheaper than topk)
limit_ratio(0.1, x)        # ⭐ a deterministic 10% sample

# ── label manipulation
label_replace(v, "dst", "$1", "src", "(regex)")
label_join(v, "dst", ",", "src1", "src2")

# ── sorting in Grafana: sort_desc(x) is a UI thing, not PromQL

# ── vector / scalar helpers
vector(1)                                # a single series with value 1, no labels
scalar(x)                                # an instant vector with ONE series → a scalar

# ── the "sum of something that may not exist" trick
sum(x) or vector(0)                      # ⭐ returns 0 instead of an empty result
count(y) or vector(1)

# ── Holt-Winters / double exponential smoothing
double_exponential_smoothing(x[1h], 0.3, 0.3)    # Prometheus 3.x
holt_winters(x[1h], 0.3, 0.3)                     # Prometheus 2.x (renamed in 3.x)

# ── the aggregation-over-time you'll use most
count_over_time({__name__=~".+"}[1h])    # ⛔ DON'T. This is a cardinality weapon.
```

### 1.10 Native histograms (Prometheus 3.x) ⭐

```promql
# a native histogram is ONE series carrying the whole distribution — no le buckets.
# Enabled with --enable-feature=native-histogram and an SDK that emits them.

rate(http_request_duration_seconds[5m])          # returns a HISTOGRAM, not a float
histogram_quantile(0.99, sum(rate(x[5m])))       # ⭐ no `sum by (le)` — there is no le
histogram_avg(rate(x[5m]))                        # the mean
histogram_count(rate(x[5m]))                      # the count
histogram_sum(rate(x[5m]))                        # the sum
histogram_fraction(0, 0.3, rate(x[5m]))           # ⭐ the fraction in [0, 0.3] = your SLI
histogram_stddev(rate(x[5m]))
histogram_ratio(x, 0.3)                           # the quantile at a value

# converting between the two
histogram_quantile(0.99, histogram_normalize(rate(x[5m])))

# ⭐ WHY IT MATTERS: 20 classic buckets = 22 series. A native histogram = 1 series
#    with ~30–50% better accuracy and no bucket-boundary guessing.
#    At 1,000 endpoints that's 22,000 series → 1,000.
```

### 1.11 Recording rules — the naming convention ⭐

```
level:metric:operations
  │      │        └─ what was done: rate5m, sum, avg, p99, ratio, by_uri
  │      └────────── the metric name (keep the original suffix: _seconds, _total, _bytes)
  └───────────────── the aggregation level: instance, pod, job, namespace, cluster

✅ job:http_requests:rate5m
✅ job:http_requests:sum_rate5m
✅ instance:node_cpu_utilisation:rate5m
✅ namespace:shop_checkout_error_ratio:rate5m
✅ cluster:node_memory_utilisation:ratio

⛔ http_requests_rate          (no level, no operations)
⛔ job:http_requests:rate5m:sum_by_uri   (too long — put `by_uri` in the labels, not the name)
```

```yaml
groups:
  - name: my-recording-rules
    interval: 30s                    # ⭐ align with the evaluation interval
    limit: 1000                      # ⭐ max series this group may produce (a guard)
    query_offset: 0s
    rules:
      - record: job:http_requests:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))
        labels: {tier: recording}
      - record: job:http_request_duration_seconds:p99
        expr: histogram_quantile(0.99, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m])))
```

```bash
promtool check rules my-rules.yaml
promtool query instant http://localhost:9090 'job:http_requests:rate5m'
```

---

<a name="2--the-30-queries-you-actually-use"></a>
## 2 · The 30 queries you actually use

### Availability and errors

```promql
# 1. the error ratio (THE query)
sum(rate(http_server_requests_seconds_count{namespace="shop",status=~"5.."}[5m]))
  / clamp_min(sum(rate(http_server_requests_seconds_count{namespace="shop"}[5m])), 0.001)

# 2. availability over 30 days (the SLO)
1 - (sum(increase(http_server_requests_seconds_count{namespace="shop",status=~"5.."}[30d]))
   / clamp_min(sum(increase(http_server_requests_seconds_count{namespace="shop"}[30d])), 1))

# 3. the error budget remaining, as a percentage
100 * (1 - (sum(increase(x_count{status=~"5.."}[30d]))
          / (0.001 * clamp_min(sum(increase(x_count[30d])), 1))))

# 4. the burn rate right now
sum(rate(x_count{status=~"5.."}[$__rate_interval]))
  / (0.001 * clamp_min(sum(rate(x_count[$__rate_interval])), 0.001))

# 5. the multi-window multi-burn-rate (14.4× = 2% of budget in 1h)
(
  sum(rate(x_count{status=~"5.."}[1h])) / clamp_min(sum(rate(x_count[1h])), 0.001) > 14.4 * 0.001
  and
  sum(rate(x_count{status=~"5.."}[5m])) / clamp_min(sum(rate(x_count[5m])), 0.001) > 14.4 * 0.001
)

# 6. errors by route, worst first
topk(10,
  sum by (uri) (rate(x_count{status=~"5.."}[5m]))
    / clamp_min(sum by (uri) (rate(x_count[5m])), 0.001))
```

### Latency

```promql
# 7. p50 / p95 / p99 (three queries in one panel)
histogram_quantile(0.50, sum by (le) (rate(x_bucket[$__rate_interval])))
histogram_quantile(0.95, sum by (le) (rate(x_bucket[$__rate_interval])))
histogram_quantile(0.99, sum by (le) (rate(x_bucket[$__rate_interval])))

# 8. p99 per route
histogram_quantile(0.99, sum by (le, uri) (rate(x_bucket[$__rate_interval])))

# 9. the mean latency (exact, unlike the quantile)
sum(rate(x_sum[$__rate_interval])) / clamp_min(sum(rate(x_count[$__rate_interval])), 0.001)

# 10. the latency SLO attainment ("fraction under 300ms")
sum(rate(x_bucket{le="0.3"}[$__rate_interval]))
  / clamp_min(sum(rate(x_count[$__rate_interval])), 0.001)

# 11. ⭐ IS IT A TAIL PROBLEM OR A GLOBAL ONE? (the diagnostic)
histogram_quantile(0.50, sum by (le) (rate(x_bucket[5m])))   # p50 normal + p99 high = TAIL
```

### Traffic

```promql
# 12. requests per second, by service
sum by (application) (rate(http_server_requests_seconds_count{namespace="shop"}[$__rate_interval]))

# 13. the total today
sum(increase(http_server_requests_seconds_count{namespace="shop"}[24h]))

# 14. traffic vs a week ago (the "is this normal?" query)
sum(rate(x_count[$__rate_interval]))
  / sum(rate(x_count[$__rate_interval] offset 7d))

# 15. the busiest routes
topk(10, sum by (uri) (rate(x_count[$__rate_interval])))
```

### Kubernetes saturation ⭐ the USE method

```promql
# 16. CPU throttling — the #1 cause of "slow but not erroring"
sum by (namespace, pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="shop"}[5m]))
  / clamp_min(sum by (namespace, pod) (rate(container_cpu_cfs_periods_total{namespace="shop"}[5m])), 0.001)

# 17. CPU usage vs request vs limit
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="shop"}[5m]))
sum by (pod) (kube_pod_container_resource_requests{namespace="shop",resource="cpu"})
sum by (pod) (kube_pod_container_resource_limits{namespace="shop",resource="cpu"})

# 18. memory vs limit (the OOM predictor)
sum by (namespace, pod, container) (container_memory_working_set_bytes{namespace="shop"})
  / on(namespace, pod, container) group_left
    kube_pod_container_resource_limits{namespace="shop",resource="memory"}

# 19. ⭐ the memory-leak detector: is the SAWTOOTH FLOOR rising?
min_over_time(jvm_memory_used_bytes{area="heap",namespace="shop"}[10m])
deriv(container_memory_working_set_bytes{namespace="shop"}[30m])

# 20. OOMKills and restarts
sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total[1h]))
kube_pod_container_status_last_terminated_reason{namespace="shop"}
sum by (pod) (rate(container_oom_events_total[5m]))

# 21. pods by phase
count by (phase) (kube_pod_status_phase{namespace="shop"} == 1)

# 22. deployments not at the desired replica count
kube_deployment_status_replicas_available{namespace="shop"}
  != kube_deployment_spec_replicas{namespace="shop"}

# 23. node capacity vs allocation (the "can we schedule more?" query)
sum by (node) (kube_pod_container_resource_requests{resource="cpu"})
  / sum by (node) (kube_node_status_capacity{resource="cpu"})

# 24. disk will fill within 4 hours
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 4*3600) < 0
kubelet_volume_stats_available_bytes{namespace="monitoring"}
  / clamp_min(kubelet_volume_stats_capacity_bytes{namespace="monitoring"}, 1)

# 25. HPA state
kube_horizontalpodautoscaler_status_current_replicas
  == kube_horizontalpodautoscaler_spec_max_replicas     # pinned at max
```

### JVM / runtime

```promql
# 26. GC pause impact
rate(jvm_gc_pause_seconds_sum[5m]) / clamp_min(rate(jvm_gc_pause_seconds_count[5m]), 0.001)
jvm_gc_pause_seconds_max
rate(jvm_gc_pause_seconds_count{action="end of major GC"}[5m])   # ⭐ full GCs

# 27. heap pressure
jvm_memory_used_bytes{area="heap"} / clamp_min(jvm_memory_max_bytes{area="heap"}, 1)

# 28. thread and pool exhaustion
tomcat_threads_busy_threads / clamp_min(tomcat_threads_config_max_threads, 1)
hikaricp_connections_active / clamp_min(hikaricp_connections_max, 1)
hikaricp_connections_pending
hikaricp_connections_timeout_total       # ⭐ a counter of acquisition timeouts — always alert on this
```

### Monitoring itself ⭐ tier 4

```promql
# 29. is my monitoring working?
sum(up) / count(up)                                                    # fraction of targets up
count(up == 0)                                                          # how many are down
increase(prometheus_rule_evaluation_failures_total[10m])                # broken rules
time() - prometheus_tsdb_head_time_seconds > 900                        # stopped ingesting
prometheus_tsdb_head_series                                             # cardinality
sum(rate(otelcol_processor_dropped_spans[5m]))                          # ⭐ the Collector losing traces
sum(rate(otelcol_exporter_send_failed_spans[5m]))
sum(rate(otelcol_processor_refused_spans{processor="memory_limiter"}[5m]))
otelcol_exporter_queue_size / clamp_min(otelcol_exporter_queue_capacity, 1)

# 30. how expensive is each scrape?
topk(10, scrape_samples_scraped)
topk(10, scrape_duration_seconds)
scrape_samples_scraped / clamp_min(scrape_samples_post_metric_relabeling, 1)   # ⭐ relabeling efficiency
```

---

<a name="3--logql--loki"></a>
## 3 · LogQL — Loki

### 3.1 The model

```
{namespace="shop", app="shop-api"} |= "error" | json | level="ERROR" | line_format "{{.message}}"
└──────────────┬────────────────┘ └───┬───────┘ └─┬──┘ └──────┬───────┘ └────────┬──────────┘
      STREAM SELECTOR            LINE FILTER   PARSER     LABEL FILTER      LINE FORMAT
   (labels only — indexed)    (cheap, first)  (expensive)  (after parsing)   (output)

  ⭐ RULE 1: the stream selector uses LABELS ONLY. Keep labels few and bounded.
  ⭐ RULE 2: filter with |= and |~ BEFORE parsing — it's 100× cheaper.
  ⭐ RULE 3: anything unbounded (trace_id, order_id, user_id, path) is a FIELD, never a LABEL.
```

### 3.2 Stream selectors and filters

```logql
{namespace="shop"}                              # one label
{namespace="shop", app="shop-api"}              # several
{namespace=~"shop|storefront"}                  # regex
{namespace!="kube-system"}
{app=~".+"}                                     # everything with an app label

{namespace="shop"} |= "error"                   # contains (case-sensitive)
{namespace="shop"} != "health"                  # does not contain
{namespace="shop"} |~ "(?i)error|exception"     # regex contains
{namespace="shop"} !~ "debug|trace"             # regex NOT contains
{namespace="shop"} |= "error" != "timeout"      # chained: contains error but not timeout

# ⭐ the JSON-line filter shortcut (Loki 3.x)
{namespace="shop"} | level="ERROR"              # only if `level` is a LABEL
{namespace="shop"} | json | level="ERROR"       # if it's inside the line
```

### 3.3 Parsers

```logql
| json                                          # ⭐ parse a JSON line into labels
| json level="severity"                         # rename while parsing
| json level="severity" |= "error"              # chained
| logfmt                                        # key=value pairs
| pattern `<ip> - <user> [<ts>] "<method> <path> <proto>" <status> <size>`
| regexp `(?P<ip>\d+\.\d+\.\d+\.\d+).*status=(?P<status>\d+)`
| unpack                                        # base64-decode a field
| label_format pod_upper=`{{upper .pod}}`       # ⭐ create/rename labels from templates
| line_format "{{.ts}} {{.level}} {{.msg}}"     # ⭐ rewrite the displayed line
| drop level="DEBUG"                            # ⭐ drop lines at the pipeline stage
| keep level=~"ERROR|WARN"
```

### 3.4 Metric queries (LogQL → a time series)

```logql
# count
count_over_time({namespace="shop"} |= "error" [5m])
sum by (app) (count_over_time({namespace="shop"} | json | level="ERROR" [5m]))
sum by (namespace) (rate({namespace=~".+"} |~ "(?i)error|exception" [5m]))

# top offenders
topk(5, sum by (pod) (count_over_time({namespace="shop"} |= "ERROR" [1h])))

# ⭐ unwrap: turn a parsed FIELD into a number you can aggregate
quantile_over_time(0.99,
  {namespace="shop", app="shop-api"} | json | unwrap duration_ms [5m]) by (uri)
avg_over_time({namespace="shop"} | json | unwrap duration_ms [5m])
max_over_time({namespace="shop"} | json | unwrap response_bytes [1h])
sum_over_time({namespace="shop"} | json | status="500" | unwrap bytes_sent [1h])

# ⭐ an error RATIO from logs (an SLO without metrics)
sum(rate({namespace="shop"} | json | level="ERROR" [5m]))
  / sum(rate({namespace="shop"} | json [5m]))

# ⭐ COUNT DISTINCT — the "how many customers were affected?" query
count(sum by (customer_id) (count_over_time({namespace="shop"} | json | level="ERROR" [1h])))

# the volume panel (Loki 3.x, needs volume_enabled: true)
sum by (namespace) (count_over_time({namespace=~".+"} [$__interval]))
```

### 3.5 The correlation queries ⭐

```logql
# every log line for one trace
{namespace="shop"} | json | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"

# every log line for one order, across every service
{namespace="shop"} | json | order_id="ord_9f2a1b3c"

# the logs around a span, ±1 minute
{namespace="shop"} | json | span_id="00f067aa0ba902b7"

# ⭐ the "what changed at 17:04?" query
{namespace="shop"} | json | timestamp >= "2026-09-09T17:00:00" | timestamp <= "2026-09-09T17:10:00"

# the first occurrence of a new error
first_over_time({namespace="shop"} | json | level="ERROR" | line_format "{{.message}}" [1h])
```

### 3.6 The Loki HTTP API

```bash
LOKI=localhost:3100
START=$(date -d '-1 hour' +%s)000000000    # ⭐ NANOSECONDS
END=$(date +%s)000000000

curl -sG "$LOKI/loki/api/v1/labels" | jq .
curl -sG "$LOKI/loki/api/v1/label/namespace/values" | jq .
curl -sG "$LOKI/loki/api/v1/query"        --data-urlencode 'query=sum(count_over_time({namespace="shop"}[5m]))' | jq .
curl -sG "$LOKI/loki/api/v1/query_range"  --data-urlencode 'query={namespace="shop"} |= "ERROR"' \
     --data-urlencode "start=$START" --data-urlencode "end=$END" --data-urlencode 'limit=100' \
     --data-urlencode 'direction=backward' | jq -r '.data.result[].values[][1]'
curl -sG "$LOKI/loki/api/v1/series"       --data-urlencode 'match[]={namespace="shop"}' | jq .
curl -sG "$LOKI/loki/api/v1/index/stats"  --data-urlencode 'query={namespace="shop"}' | jq .
# {"streams":4821,"chunks":184203,"bytes":…,"entries":…}   ⭐ the cardinality check
curl -s "$LOKI/ready"; curl -s "$LOKI/metrics" | grep loki_
logcli query '{namespace="shop"} |= "error"' --since=1h --limit=50      # ⭐ the CLI
logcli labels; logcli series '{namespace="shop"}'
```

---

<a name="4--traceql--tempo"></a>
## 4 · TraceQL — Tempo

### 4.1 The model

```
{ .service.name = "shop-api" && duration > 1s && status = error }
  └────────────────┬───────────────────────┘
       the TRACE-LEVEL query (spans, resources, scoped attributes)

{ .service.name = "shop-api" } >> { .db.system = "postgresql" }
                                └─ ⭐ the DESCENDANT operator

{ .service.name="a" } && { .service.name="b" }
                       └─ ⭐ the AND (both in the same trace)

| select(.order.id, .customer.tier)     ← project attributes
| count_over_time()                     ← aggregate
| rate() by (.url.path)                 ← group
```

### 4.2 The intrinsic fields

| Field | Values | Example |
|---|---|---|
| `duration` | `100ms`, `1.5s`, `2m` | `duration > 2s` |
| `name` | the span name | `name = "POST /api/orders"` |
| `status` | `ok`, `error`, `unset` | `status = error` |
| `statusMessage` | the status description | `statusMessage =~ "timeout.*"` |
| `kind` | `client`, `server`, `producer`, `consumer`, `internal`, `unspecified` | `kind = server` |
| `startTime` | `2026-09-09T17:00:00Z` | `startTime > "…"` |
| `endTime` | | |
| `traceID` | a hex string | `traceID = "4bf9…"` |
| `trace:duration` | the whole trace's duration | `trace:duration > 5s` |
| `trace:rootName` | the root span's name | `trace:rootName = "GET /"` |
| `trace:rootService` | | `trace:rootService = "shop-ui"` |
| `trace:serviceCount` | ⭐ how many services a trace touches | `trace:serviceCount > 3` |
| `trace:tagCount` | | |
| `span:…` | any span in the trace | |

### 4.3 The attribute scopes

```traceql
{ .service.name = "x" }              # SPAN scope (the default) — attributes on the span
{ resource.service.name = "x" }      # RESOURCE scope — attributes on the resource
{ scope.span.library = "x" }         # the instrumentation scope (the library)
{ .http.route = "/api/orders" }      # shorthand for span.http.route
{ resource.k8s.namespace.name = "shop" }
```

### 4.4 The queries you'll actually run

```traceql
# ── the basics ───────────────────────────────────────────────────
{ .service.name = "shop-api" }
{ .service.name =~ "shop-.*" }
{ resource.k8s.namespace.name = "shop" }
{ .service.name = "shop-api" && .url.path = "/api/orders" }
{ .service.name = "shop-api" || .service.name = "checkout" }

# ── the incident queries ⭐⭐ ─────────────────────────────────────
{ .service.name = "shop-api" && status = error }
{ .service.name = "shop-api" && duration > 2s }
{ .service.name = "shop-api" && .http.response.status_code >= 500 }
{ duration > 5s && status = error }
{ .service.name = "shop-api" && kind = server && .http.route = "/api/orders" && duration > 1s }

# ── ⭐ the SEGMENT query (Task C3 — find the hidden subset)
{ .service.name = "shop-api" && .customer.tier = "platinum" && status = error }

# ── ⭐ the BUSINESS query (order IDs live on spans, not metrics)
{ .order.id = "ord_9f2a1b3c" }
{ .service.name = "shop-api" && .search.results = 0 }

# ── retries and timeouts ─────────────────────────────────────────
{ .http.resend_count > 0 }
{ .service.name = "shop-api" && .error.type = "SocketTimeoutException" }

# ── the propagation-bug detector ⭐ ──────────────────────────────
{ kind = server && .parentSpanId = "" }        # a SERVER span with no parent = broken propagation

# ── the async/queue queries ──────────────────────────────────────
{ kind = consumer && .messaging.system = "rabbitmq" }
{ kind = producer && .messaging.destination.name = "order.created" }
{ .messaging.destination.name = "orders" && duration > 60s }

# ── database spans ───────────────────────────────────────────────
{ .db.system = "postgresql" && duration > 500ms }
{ .db.system = "redis" && status = error }
{ .db.query.text =~ ".*SELECT.*FROM orders.*" }

# ── the structural operators ⭐ ──────────────────────────────────
# a slow checkout WITH a slow database call beneath it
{ .url.path = "/api/orders" && duration > 1s } >> { .db.system = "postgresql" && duration > 500ms }

# two services in the same trace
{ .service.name = "shop-ui" } && { .service.name = "shop-api" }

# a trace that touched at least 4 services
{ trace:serviceCount >= 4 }

# any span matching, anywhere in the trace
{ span:http.response.status_code = 504 }

# ── projection and aggregation ───────────────────────────────────
{ .service.name = "shop-api" && status = error }
  | select(.order.id, .customer.tier, .url.path, .http.response.status_code)

{ .service.name = "shop-api" && duration > 1s } | rate() by (.url.path)
{ .service.name = "shop-api" } | count_over_time() by (.http.route)
{ resource.k8s.namespace.name = "shop" } | rate() by (.service.name)

# ── the "what changed?" query ────────────────────────────────────
{ .service.name = "shop-api" && resource.service.version = "1.4.2" && status = error }
  | rate() by (.url.path)
```

### 4.5 The Tempo HTTP API

```bash
T=localhost:3200
TID=4bf92f3577b34da6a3ce929d0e0e4736

curl -s "$T/api/traces/$TID" | jq '.batches[].scopeSpans[].spans[] | {name, kind, duration: ((.endTimeUnixNano|tonumber - .startTimeUnixNano|tonumber)/1e6)}'
curl -s "$T/api/traces/$TID" | jq -r '[.batches[].resource.attributes[] | select(.key=="service.name") | .value.stringValue] | unique | .[]'
# ⭐ which services are in this trace

curl -sG "$T/api/search" --data-urlencode 'q={ .service.name = "shop-api" && status = error }' \
     --data-urlencode 'limit=20' --data-urlencode "start=$(date -d '-1 hour' +%s)" | jq '.traces'
curl -sG "$T/api/search/tags"    | jq .              # ⭐ every searchable tag
curl -sG "$T/api/search/tag/service.name/values" | jq .
curl -sG "$T/api/search/tag/.http.route/values"  | jq .
curl -s "$T/api/echo" ; curl -s "$T/ready" ; curl -s "$T/status" | jq .
curl -sG "$T/api/v2/search" --data-urlencode 'q={ .service.name="shop-api" } | rate()' | jq .
curl -s "$T/metrics" | grep tempo_
```

---

<a name="5--prometheus-cli--apis"></a>
## 5 · Prometheus CLI & HTTP APIs

### 5.1 `promtool` — every subcommand

```bash
# ── check ────────────────────────────────────────────────────────
promtool check config prometheus.yml
promtool check rules alerting-rules/*.yaml
promtool check metrics < metrics.txt           # ⭐ validates metric/label names
promtool check service-discovery prometheus.yml kubernetes-pods
promtool check web-config web.yml
promtool tsdb create-blocks-from openmetrics data.txt out/

# ── query (against a live Prometheus) ────────────────────────────
promtool query instant  http://localhost:9090 'up'
promtool query instant  http://localhost:9090 'up' --format=json
promtool query range    http://localhost:9090 'rate(node_cpu_seconds_total[5m])' \
                        --start=2026-09-09T10:00:00Z --end=2026-09-09T11:00:00Z --step=60s
promtool query series   http://localhost:9090 'up{job="api"}'
promtool query labels   http://localhost:9090 job
promtool query analyze  http://localhost:9090 'up' --limit=10   # ⭐ cardinality of one query

# ── test (the unit tests for alerting rules) ⭐⭐ ─────────────────
promtool test rules test.yaml
promtool test rules --diff test.yaml           # ⭐ shows what changed vs the golden output

# ── debug (capture a full support bundle) ────────────────────────
promtool debug all http://localhost:9090        # ⭐ metrics, config, rules, TSDB stats, pprof
promtool debug metrics http://localhost:9090
promtool debug pprof   http://localhost:9090

# ── tsdb (offline analysis of the data directory) ────────────────
promtool tsdb list /var/lib/prometheus/data/
promtool tsdb analyze /var/lib/prometheus/data/ 01J8ZK… --limit=20   # ⭐ block-level cardinality
```

**The `promtool test rules` file format:**

```yaml
rule_files: [alerting-rules.yaml]
evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      - series: 'up{job="api", instance="a:9090"}'
        values: "1x10 0x20"                # ⭐ the value language:
        # 0          → a single value 0
        # 0+1x10     → 0, then +1 each step, 10 times  (0,1,2,…,10)
        # 1x10 0x20  → 1 for 10 steps, then 0 for 20 steps
        # _          → a gap (no sample)
        # 0.5+0.1x5  → floats work
        # stale      → an explicit stale marker
      - series: 'up{job="api", instance="b:9090"}'
        values: "1x30"

    # assert on ALERTS
    alert_rule_test:
      - eval_time: 15m
        alertname: TargetDown
        exp_alerts:
          - exp_labels: {alertname: TargetDown, job: api, instance: "a:9090", severity: critical}
            exp_annotations: {summary: "api/a:9090 is down"}
      - eval_time: 8m                      # ⭐ the "must NOT fire yet" assertion
        alertname: TargetDown
        exp_alerts: []

    # assert on RECORDING RULES
    promql_expr_test:
      - expr: job:up:ratio
        eval_time: 10m
        exp_samples:
          - labels: 'job:up:ratio{job="api"}'
            value: 1
```

### 5.2 The HTTP API

```bash
P=localhost:9090

# ── querying ─────────────────────────────────────────────────────
curl -sG "$P/api/v1/query"        --data-urlencode 'query=up'                    --data-urlencode 'time=1757412345'
curl -sG "$P/api/v1/query_range"  --data-urlencode 'query=rate(x[5m])' \
     --data-urlencode "start=$(date -d '-1 hour' +%s)" --data-urlencode "end=$(date +%s)" --data-urlencode 'step=60'
curl -sG "$P/api/v1/series"       --data-urlencode 'match[]={job="api"}'
curl -sG "$P/api/v1/labels"
curl -sG "$P/api/v1/label/job/values"
curl -sG "$P/api/v1/label/instance/values" | jq '.data | length'   # ⭐ cardinality of one label
curl -sG "$P/api/v1/query_exemplars" --data-urlencode 'query=x_count' --data-urlencode 'start=…' --data-urlencode 'end=…'

# ── targets and rules ────────────────────────────────────────────
curl -s "$P/api/v1/targets"                | jq '.data.activeTargets[] | {job: .labels.job, health, lastError, scrapeUrl}'
curl -s "$P/api/v1/targets?state=active"   | jq -r '.data.activeTargets[] | select(.health!="up") | .labels.job'
curl -s "$P/api/v1/targets/metadata"       | jq .
curl -s "$P/api/v1/rules"                  | jq '.data.groups[].rules[] | {name, type, health, lastError}'
curl -s "$P/api/v1/rules?type=alert"       | jq '.data.groups[].rules[] | select(.health!="ok")'
curl -s "$P/api/v1/alerts"                 | jq '.data.alerts[] | {name: .labels.alertname, state, activeAt}'
curl -s "$P/api/v1/alertmanagers"          | jq .

# ── ⭐ the TSDB status endpoint — the cardinality goldmine ────────
curl -s "$P/api/v1/status/tsdb" | jq '.data.headStats'
# {"numSeries":2412880,"numLabelPairs":4821,"chunkCount":1842034,"minTime":…,"maxTime":…}
curl -s "$P/api/v1/status/tsdb" | jq '.data.top10CountByMetricName'
curl -s "$P/api/v1/status/tsdb" | jq '.data.top10SeriesCountByMetricName'
curl -s "$P/api/v1/status/tsdb" | jq '.data.top10LabelNames'
curl -s "$P/api/v1/status/tsdb" | jq '.data.top10LabelValues'
curl -s "$P/api/v1/status/tsdb?limit=1000" | jq '.data.top10SeriesCountByMetricName | length'

# ── build info, config, flags ────────────────────────────────────
curl -s "$P/api/v1/status/config"   | jq -r '.data.yaml'
curl -s "$P/api/v1/status/flags"    | jq .
curl -s "$P/api/v1/status/runtimeinfo" | jq .
curl -s "$P/api/v1/status/buildinfo"   | jq '.data.version'
curl -s "$P/api/v1/status/walreplay"   | jq .

# ── health and admin ─────────────────────────────────────────────
curl -s "$P/-/healthy" ; curl -s "$P/-/ready"
curl -sX POST "$P/-/reload"                        # ⭐ needs --web.enable-lifecycle
curl -sX POST "$P/api/v1/admin/tsdb/snapshot"      # ⭐ needs --enable-feature=admin-api
curl -sX POST "$P/api/v1/admin/tsdb/delete_series?match[]=go_gc_duration_seconds&start=…&end=…"
curl -sX POST "$P/api/v1/admin/tsdb/clean_tombstones"

# ── the raw scrape of a target (what Prometheus actually sees) ───
curl -s "$P/targets" ; kubectl exec -n shop deploy/shop-api -- wget -qO- localhost:9090/prometheus | head -40
```

### 5.3 The essential Prometheus flags

```bash
--config.file=/etc/prometheus/prometheus.yml
--storage.tsdb.path=/prometheus
--storage.tsdb.retention.time=15d              # ⭐ default 15d
--storage.tsdb.retention.size=45GB             # whichever comes first
--storage.tsdb.wal-compression                 # ⭐ ~30% smaller WAL
--storage.tsdb.head-chunks-write-queue-size=16384
--storage.tsdb.max-block-chunk-segment-size=512
--storage.tsdb.no-lockfile                     # ⭐ on a PV, avoid the lock
--web.enable-lifecycle                         # ⭐ enables POST /-/reload
--web.enable-admin-api                         # ⛔ DANGEROUS — enables series deletion
--web.external-url=https://prom.example.com
--web.cors.origin=https://grafana.example.com
--query.timeout=2m
--query.max-concurrency=20
--query.max-samples=50000000                   # ⭐ protects against a query OOMing Prometheus
--query.lookback-delta=5m
--rules.alert.for-outage-tolerance=1h          # ⭐ survives a Prometheus restart without re-firing
--rules.alert.for-grace-period=10m
--rules.alert.resend-delay=1m
--enable-feature=native-histogram
--enable-feature=exemplar-storage
--enable-feature=otlp-write-receiver           # ⭐ accept OTLP metrics on /api/v1/otlp
--enable-feature=auto-gomemlimit
--enable-feature=auto-gomaxprocs
--enable-feature=delayed-name-removal
--enable-feature=promql-experimental-functions
```

---

<a name="6--alertmanager--amtool"></a>
## 6 · Alertmanager & `amtool`

### 6.1 `amtool`

```bash
export AM_URL=http://localhost:9093

# ── config ───────────────────────────────────────────────────────
amtool check-config alertmanager.yml
amtool check-config --config.check=false alertmanager.yml
amtool config routes --alertmanager.url=$AM_URL          # ⭐ shows the routing tree
amtool config routes test --alertmanager.url=$AM_URL \
  --config.routes --tree --labels alertname=X severity=critical team=payments
# ⭐⭐ WHICH RECEIVER WILL THIS ALERT HIT? The single most useful amtool command.
amtool config show --alertmanager.url=$AM_URL

# ── alerts ───────────────────────────────────────────────────────
amtool alert --alertmanager.url=$AM_URL
amtool alert query --alertmanager.url=$AM_URL
amtool alert query --alertmanager.url=$AM_URL alertname=KubePodNotReady
amtool alert query --alertmanager.url=$AM_URL severity=critical --expired
amtool alert query --alertmanager.url=$AM_URL -o simple -q
amtool alert add TestAlert severity=critical team=payments \
  --alertmanager.url=$AM_URL --annotation=summary="a test" --annotation=runbook_url="https://…"
amtool alert add InstanceDown instance=web1 severity=critical \
  --alertmanager.url=$AM_URL --expires=1h
amtool alert expire --alertmanager.url=$AM_URL alertname=TestAlert

# ── silences ⭐ ──────────────────────────────────────────────────
amtool silence --alertmanager.url=$AM_URL
amtool silence add --alertmanager.url=$AM_URL alertname=KubePodNotReady namespace=shop \
  --duration=2h --comment="planned deploy" --author="harish"
amtool silence add --alertmanager.url=$AM_URL instance=~"web.*" --start="2026-09-10T22:00:00Z" \
  --end="2026-09-10T23:00:00Z" --comment="maintenance"
amtool silence expire --alertmanager.url=$AM_URL <silence-id>
amtool silence query --alertmanager.url=$AM_URL --expired
amtool silence import --alertmanager.url=$AM_URL silences.json
amtool silence export --alertmanager.url=$AM_URL > silences.json

# ── the HTTP API directly ────────────────────────────────────────
curl -s $AM_URL/api/v2/alerts | jq '.[].labels'
curl -s $AM_URL/api/v2/alerts/groups | jq .
curl -s $AM_URL/api/v2/silences | jq '.[].matchers'
curl -s $AM_URL/api/v2/status | jq -r '.config.original'
curl -s $AM_URL/api/v2/receivers | jq .
curl -s $AM_URL/api/v2/alerts -XPOST -H 'Content-Type: application/json' -d '[
  {"labels":{"alertname":"ManualTest","severity":"critical","team":"payments"},
   "annotations":{"summary":"sent by hand"},
   "startsAt":"2026-09-09T17:00:00Z","generatorURL":"http://localhost:9090/graph"}]'
curl -s $AM_URL/metrics | grep alertmanager_
```

### 6.2 The Alertmanager config skeleton

```yaml
global:
  resolve_timeout: 5m                       # ⭐ after this, an unreceived alert is "resolved"
  smtp_smarthost: smtp.example.com:587
  smtp_from: alerts@example.com
  smtp_auth_username: alerts
  smtp_auth_password: …                      # ⭐ use smtp_auth_password_file in production
  slack_api_url_file: /etc/alertmanager/secrets/slack-webhook-url
  pagerduty_url: https://events.pagerduty.com/v2/enqueue
  opsgenie_api_key: …
  victorops_api_key: …

# ⭐ templates — load them BEFORE the route
templates:
  - /etc/alertmanager/templates/*.tmpl

route:
  receiver: default
  group_by: [alertname, namespace, team]     # ⭐ what makes alerts share a notification
  group_wait: 30s                            # ⭐ wait this long to batch the first notification
  group_interval: 5m                         # ⭐ wait between notifications for the SAME group
  repeat_interval: 4h                        # ⭐ re-send an unresolved alert this often
  continue: false
  routes:
    - receiver: page
      matchers: [severity=critical, tier=symptom]
      group_wait: 10s
      repeat_interval: 30m
      continue: true                          # ⭐ also fall through to the next route
      routes:
        - receiver: payments-page
          matchers: [team=payments]
        - receiver: storefront-page
          matchers: [team=storefront]
    - receiver: ticket
      matchers: [severity=warning]
      repeat_interval: 12h
    - receiver: heartbeat-external            # ⭐ the dead-man's switch
      matchers: [alertname=Watchdog]
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1m

inhibit_rules:
  - source_matchers: [alertname=KubeNodeNotReady]
    target_matchers: [tier=cause]
    equal: [node]                             # ⭐ only inhibit when `node` matches
  - source_matchers: [tier=symptom]
    target_matchers: [tier=saturation]
    equal: [namespace, team]

receivers:
  - name: default
  - name: page
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/pd-key
        severity: critical
        class: '{{ .CommonLabels.tier }}'
        component: '{{ .CommonLabels.alertname }}'
        group: '{{ .CommonLabels.team }}'
        details:
          firing: '{{ .Alerts.Firing | len }}'
          resolved: '{{ .Alerts.Resolved | len }}'
          runbook: '{{ (index .Alerts 0).Annotations.runbook_url }}'
    slack_configs:
      - channel: '#oncall'
        send_resolved: true
        title: '{{ template "slack.title" . }}'
        text:  '{{ template "slack.text" . }}'
        api_url_file: /etc/alertmanager/secrets/slack-url
  - name: ticket
    email_configs:
      - to: team@example.com
        send_resolved: true
        headers: {Subject: '{{ template "email.subject" . }}'}
  - name: heartbeat-external
    webhook_configs:
      - url: https://hc-ping.com/YOUR-UUID
        send_resolved: false
        max_alerts: 1

# ⭐ time-based muting
time_intervals:
  - name: business-hours
    time_intervals:
      - {weekdays: [monday:friday], times: [{start_time: "09:00", end_time: "18:00"}]}
  - name: out-of-hours
    time_intervals:
      - {weekdays: [saturday, sunday]}
      - {weekdays: [monday:friday], times: [{start_time: "18:00", end_time: "09:00"}]}

mute_time_intervals:
  - name: weekend-maintenance
    time_intervals: [{weekdays: [saturday], times: [{start_time: "02:00", end_time: "06:00"}]}]

# ⭐ the matcher syntax (v0.22+)
#   severity="critical"    severity=~"critical|warning"
#   severity!="info"       severity!~"debug|info"
#   team=""  (isRegex:false, isEqual:false)  → "the label exists and is non-empty"
```

### 6.3 The four timing parameters, precisely ⭐

```
an alert starts firing at T
        │
        ├─ group_wait: 30s ────► the FIRST notification is sent at T+30s
        │                        (waiting to batch other alerts into the same group)
        │
        ├─ new alerts join the group…
        │
        ├─ group_interval: 5m ─► the NEXT notification for that group at T+5m
        │                        (only if something changed in the group)
        │
        ├─ repeat_interval: 4h ► the alert is STILL firing → re-send at T+4h, T+8h, …
        │
        └─ resolve_timeout: 5m ► Prometheus stops sending the alert; Alertmanager
                                 marks it resolved 5m later and sends `send_resolved`
```

---

<a name="7--grafana"></a>
## 7 · Grafana

### 7.1 Panel types

| Panel | For | Key options |
|---|---|---|
| **Time series** | ⭐ the default. Any metric over time | drawStyle (line/bars/points), fillOpacity, **exemplars**, thresholds, transformations |
| **Stat** | One big number | reduceOptions.calcs (lastNotNull/max/mean), colorMode (value/background), graphMode (area/none) |
| **Gauge** | A number against thresholds | min/max, thresholds |
| **Bar gauge** | Several numbers against thresholds | orientation, displayMode (basic/lcd/gradient) |
| **Table** | Many rows/columns | transformations (organize, join, group), cell options (color background), sorting |
| **Heatmap** | ⭐ a distribution over time — reveals bimodality | **Format: Heatmap**, calculate=off (pre-bucketed), color scheme |
| **Histogram** | A distribution at one moment | bucket size |
| **State timeline** | Discrete states over time | merge consecutive, value mappings |
| **Logs** | Loki log lines | showTime, wrapLogMessage, dedupStrategy, enableLogDetails |
| **Traces** | Tempo/Jaeger waterfall | nodeGraph, spanSearch |
| **Node graph** | ⭐ the service map | requires Tempo `serviceMap` datasource config |
| **Bar chart** | Categorical | |
| **Candlestick** | Financial | |
| **Pie chart** | ⚠️ almost never the right choice | |
| **Text** | Runbook links, HTML, Markdown | mode: html/markdown/text |
| **Dashboard list** | A landing page | |
| **News** | | |
| **Getting started** | delete it | |

### 7.2 Variables

| Type | Example |
|---|---|
| **Query** | `label_values(http_server_requests_seconds_count{namespace="$namespace"}, application)` |
| **Custom** | `standard,gold,platinum` |
| **Constant** | `production` (hidden, for provisioning) |
| **Data source** | lets the user pick the datasource |
| **Interval** | `1m,5m,15m,1h` |
| **Text box** | free text |
| **Ad hoc filters** | ⭐ user-built label filters — Prometheus/Loki/Tempo only |
| **Chained** | a variable whose query uses another variable |

```
# the multi-value + All pattern (the one you want on almost every dashboard)
Name:        service
Type:        Query
Data source: Prometheus
Query:       label_values(http_server_requests_seconds_count{namespace="$namespace"}, application)
Refresh:     On time range change
Multi-value: ✅
Include All: ✅
Custom all value:  .*        ⭐⭐ CRITICAL. Without this, "All" expands to
                                {a,b,c} which breaks `=~` in some contexts.
Sort:        Alphabetical (asc)
Regex:       /(.*)/           (to extract from a composite value)

# then use it as:   application=~"$service"
```

### 7.3 The dashboard JSON essentials

```json
{
  "uid": "99-incident",                  // ⭐⭐ SET IT EXPLICITLY. Otherwise Grafana
                                         //    generates one and provisioning breaks.
  "title": "🔥 Shop — Incident View",
  "tags": ["shop", "oncall"],
  "timezone": "browser",
  "schemaVersion": 39,
  "editable": true,
  "graphTooltip": 1,                     // ⭐ 0=off, 1=shared crosshair, 2=shared tooltip
  "refresh": "30s",
  "time": {"from": "now-1h", "to": "now"},
  "templating": {"list": [ /* variables */ ]},
  "annotations": {"list": [
    {"name": "Deployments", "datasource": {"type":"prometheus","uid":"prometheus"},
     "enable": true,
     "expr": "changes(kube_deployment_status_replicas_updated{namespace=\"$namespace\"}[1m]) > 0",
     "titleFormat": "{{deployment}} updated", "iconColor": "blue"}
  ]},
  "panels": [
    {"id": 1, "type": "timeseries", "title": "p99",
     "gridPos": {"x": 0, "y": 0, "w": 8, "h": 8},     // ⭐ 24 columns wide
     "datasource": {"type": "prometheus", "uid": "prometheus"},
     "targets": [{"refId": "A", "expr": "histogram_quantile(0.99, sum by (le) (rate(x_bucket[$__rate_interval])))",
                  "legendFormat": "p99", "editorMode": "code", "range": true}],
     "fieldConfig": {"defaults": {
        "unit": "s",
        "custom": {"drawStyle": "line", "lineInterpolation": "smooth", "fillOpacity": 8,
                   "showPoints": "never", "spanNulls": false,
                   "exemplars": true},                      // ⭐⭐ THE GREEN DIAMONDS
        "thresholds": {"mode": "absolute", "steps": [
          {"color": "green", "value": null}, {"color": "red", "value": 1}]}},
        "overrides": []},
     "options": {"legend": {"displayMode": "table", "placement": "bottom",
                            "calcs": ["mean","max","lastNotNull"]},
                 "tooltip": {"mode": "multi", "sort": "desc"}}}
  ]
}
```

### 7.4 Units (the ones you'll use)

| Unit id | Meaning |
|---|---|
| `short`, `none` | plain number |
| `percent` (0–100), `percentunit` (0–1) | ⭐ know which your query returns |
| `s`, `ms`, `µs`, `ns`, `m`, `h`, `d` | time |
| `bytes`, `decbytes`, `bits`, `Bps`, `binBps`, `reqps`, `ops`, `cps` | data/rate |
| `dateTimeAsIso`, `dateTimeFromNow` | timestamps |
| `currencyUSD`, `currencyINR`, `currencyEUR` | money |
| `bool`, `bool_yes_no` | 0/1 |

### 7.5 The Grafana HTTP API

```bash
G=localhost:3000; AUTH="admin:admin"; T="Bearer $GRAFANA_TOKEN"

# ── dashboards ───────────────────────────────────────────────────
curl -s -u $AUTH "$G/api/search?type=dash-db" | jq '.[] | {uid, title, folderTitle}'
curl -s -u $AUTH "$G/api/dashboards/uid/99-incident" | jq '.dashboard | {title, panels: (.panels|length)}'
curl -s -u $AUTH "$G/api/dashboards/uid/99-incident" | jq '.dashboard' > dash.json   # ⭐ export
curl -s -u $AUTH -XPOST "$G/api/dashboards/db" -H 'Content-Type: application/json' \
  -d '{"dashboard": '"$(jq 'del(.id,.version)' dash.json)"', "folderUid":"shop", "overwrite":true, "message":"from CI"}'
curl -s -u $AUTH "$G/api/dashboards/uid/99-incident/versions" | jq .

# ── datasources ──────────────────────────────────────────────────
curl -s -u $AUTH "$G/api/datasources" | jq '.[] | {uid, name, type}'
curl -s -u $AUTH "$G/api/datasources/uid/tempo" | jq '.jsonData'
curl -s -u $AUTH "$G/api/datasources/uid/loki/health" | jq .       # ⭐ is it reachable?
curl -s -u $AUTH "$G/api/frontend/settings" | jq '.datasources'

# ── provisioning ─────────────────────────────────────────────────
curl -s -u $AUTH "$G/api/provisioning/dashboards"    | jq .
curl -s -u $AUTH "$G/api/provisioning/folders"       | jq .
curl -s -u $AUTH -XPOST "$G/api/admin/provisioning/dashboards/reload"
curl -s -u $AUTH -XPOST "$G/api/admin/provisioning/datasources/reload"

# ── folders, users, alerts ───────────────────────────────────────
curl -s -u $AUTH "$G/api/folders" | jq '.[] | {uid, title}'
curl -s -u $AUTH -XPOST "$G/api/folders" -d '{"uid":"shop","title":"Shop"}'
curl -s -u $AUTH "$G/api/org/users" | jq .
curl -s -u $AUTH "$G/api/v1/provisioning/alert-rules" | jq '.[].title'
curl -s -u $AUTH "$G/api/alertmanager/grafana/api/v2/alerts" | jq .

# ── rendering a panel to PNG (for CI screenshots) ────────────────
curl -s -u $AUTH "$G/render/d-solo/99-incident?panelId=3&width=1600&height=900&theme=light&from=now-1h&to=now" -o panel.png

# ── the sidecar's logs (why isn't my dashboard appearing?) ───────
kubectl logs -n monitoring deploy/kps-grafana -c grafana-sc-dashboard --tail=50
kubectl logs -n monitoring deploy/kps-grafana -c grafana-sc-datasources --tail=50
```

### 7.6 The imported dashboard IDs you'll actually use

| ID | Name | For |
|---|---|---|
| **315** | Kubernetes cluster monitoring | the whole cluster |
| **3146** | Kubernetes / Views / Pods | pod-level detail |
| **13105** | Kubernetes / Views / Namespaces | per-namespace |
| **8588** | Kubernetes Deployment Statefulset CronJob | workloads |
| **1860** | ⭐ Node Exporter Full | the definitive node dashboard |
| **3662** | Prometheus 2.0 Overview | Prometheus self-monitoring |
| **15983** | ⭐ kube-state-metrics v2 | K8s object state |
| **13946** | Kubernetes Storage | PVs |
| **6671** | RabbitMQ (management plugin) | queues |
| **9628** | PostgreSQL Database | postgres_exporter |
| **11835** | Redis Dashboard | redis_exporter |
| **4701** | JVM (Micrometer) | ⭐ Spring Boot apps |
| **12900** | Spring Boot HikariCP | DB pools |
| **14430** | Tempo / TraceQL | traces |
| **13186** | ⭐ Loki / Logs | logs |
| **14055** | OTel Collector | ⭐ the Collector's own metrics |
| **12583** | Alertmanager | notifications |
| **7589** | Kubernetes / Compute Resources / Pod | CPU/memory per pod |
| **6781** | Kubernetes / Compute Resources / Namespace | |

```bash
# import one via the API
curl -s -u admin:admin -XPOST localhost:3000/api/dashboards/db -H 'Content-Type: application/json' \
  -d "$(curl -s https://grafana.com/api/dashboards/1860/revisions/latest/download \
       | jq '{dashboard: ., overwrite: true, folderUid: "platform", inputs: [{name:"DS_PROMETHEUS",type:"datasource",pluginId:"prometheus",value:"prometheus"}]}')"
```

---

<a name="8--opentelemetry-collector"></a>
## 8 · OpenTelemetry Collector

### 8.1 The structure — always in this order

```yaml
receivers:    {}      # where data comes IN     (otlp, prometheus, filelog, hostmetrics, jaeger, zipkin)
processors:   {}      # what happens to it      (memory_limiter, k8sattributes, batch, tail_sampling, …)
exporters:    {}      # where it goes OUT       (otlp, prometheusremotewrite, loki, debug, datadog)
connectors:   {}      # a receiver AND exporter (spanmetrics, count, exceptions, routing)
extensions:   {}      # not in a pipeline       (health_check, pprof, zpages, basicauth)
service:
  extensions: []
  pipelines:
    <name>:
      receivers:  []
      processors: []     # ⭐ ORDERED. memory_limiter FIRST, batch LAST.
      exporters:  []
  telemetry: {}          # the Collector's OWN metrics and logs
```

### 8.2 The receivers

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 16
        keepalive: {server_parameters: {max_connection_age: 30s}}
        tls: {cert_file: …, key_file: …}
      http:
        endpoint: 0.0.0.0:4318           # ⭐ paths: /v1/traces /v1/metrics /v1/logs
        cors: {allowed_origins: ["https://shop.example.com"], allowed_headers: ["*"]}
        tls: {}

  prometheus:                            # ⭐ a full Prometheus scraper
    config:
      scrape_configs:
        - job_name: k8s
          kubernetes_sd_configs: [{role: pod}]
          scrape_interval: 30s

  filelog:                               # ⭐ container logs from /var/log/pods
    include: [/var/log/pods/*/*/*.log]
    exclude: [/var/log/pods/kube-system_*/kube-apiserver-*/*.log]
    include_file_path: true
    start_at: end
    operators:
      - {type: json_parser, parse_from: body, parse_to: attributes, on_error: send}
      - {type: regex_parser, parse_from: attributes["log.file.path"],
         regex: '^/var/log/pods/(?P<ns>[^_]+)_(?P<pod>[^_]+)_(?P<uid>[^/]+)/(?P<container>[^/]+)/'}
      - {type: move, from: attributes.ns, to: resource["k8s.namespace.name"]}
      - {type: severity_parser, parse_from: attributes.level, preset: none,
         mapping: {info: [INFO], warn: [WARN,WARNING], error: [ERROR], fatal: [FATAL]}}

  hostmetrics:                           # ⭐ node metrics (a node_exporter alternative)
    collection_interval: 30s
    root_path: /hostfs
    scrapers: {cpu: {}, memory: {}, disk: {}, filesystem: {}, load: {}, network: {}, processes: {}, paging: {}}

  kubeletstats:                          # ⭐ pod/container metrics from the kubelet
    auth_type: serviceAccount
    endpoint: ${env:K8S_NODE_NAME}:10250
    insecure_skip_verify: true
    collection_interval: 30s
    extra_metadata_labels: [container.id, k8s.volume.type]
    metric_groups: [container, pod, node, volume]

  k8s_cluster:                           # ⭐ cluster-level metrics via the API server
    auth_type: serviceAccount
    collection_interval: 30s
    node_conditions_to_report: [Ready, MemoryPressure, DiskPressure, PIDPressure]
    allocatable_types: [cpu, memory, storage]

  k8s_events:                            # ⭐ Kubernetes events as logs
    auth_type: serviceAccount
    namespaces: [shop, monitoring, otel]

  jaeger:   {protocols: {grpc: {endpoint: 0.0.0.0:14250}, thrift_http: {endpoint: 0.0.0.0:14268}}}
  zipkin:   {endpoint: 0.0.0.0:9411}
  statsd:   {endpoint: 0.0.0.0:8125}
  fluentforward: {endpoint: 0.0.0.0:8006}
```

### 8.3 The processors ⭐ the order matters

```yaml
processors:
  # 1. ⭐⭐ ALWAYS FIRST
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80            # OR limit_mib / soft_limit_mib
    spike_limit_percentage: 25

  # 2. Kubernetes metadata enrichment
  k8sattributes:
    auth_type: serviceAccount
    passthrough: false
    extract:
      metadata: [k8s.namespace.name, k8s.pod.name, k8s.pod.uid, k8s.deployment.name,
                 k8s.replicaset.name, k8s.statefulset.name, k8s.daemonset.name,
                 k8s.job.name, k8s.node.name, k8s.pod.start_time]
      labels:  [{tag_name: team, key: team, from: pod},
                {tag_name: service.version, key: app.kubernetes.io/version, from: pod}]
      annotations: [{tag_name: deployment.environment, key: deploy-env, from: pod}]
    pod_association:
      - sources: [{from: resource_attribute, name: k8s.pod.ip}]
      - sources: [{from: resource_attribute, name: k8s.pod.uid}]
      - sources: [{from: connection}]

  # 3. environment detection
  resourcedetection:
    detectors: [env, system, docker, ec2, gcp, azure, k8snode]
    timeout: 5s
    override: false                 # ⭐ don't overwrite what the SDK set

  # 4. add/remove/rename attributes
  resource:
    attributes:
      - {key: k8s.cluster.name, value: learn, action: upsert}
      - {key: team, action: delete}
  attributes/redact:
    actions:
      - {key: db.query.text, action: hash}
      - {key: http.request.header.authorization, action: delete}
      - {key: http.request.header.cookie, action: delete}
      - {key: user.email, action: hash}
      - {key: url.query, action: hash}
      - {key: http.url, action: update, value: "<redacted>"}

  # 5. filtering (reduce volume)
  filter/traces:
    error_mode: ignore
    traces:
      span:
        - 'attributes["url.path"] == "/healthz"'
        - 'attributes["url.path"] == "/metrics"'
        - 'name == "HTTP GET" and attributes["http.route"] == "/favicon.ico"'
  filter/metrics:
    error_mode: ignore
    metrics:
      metric:
        - 'IsMatch(name, "go_.*")'
        - 'IsMatch(name, "process_.*")'
        - 'type == METRIC_TYPE_SUM'
  filter/logs:
    error_mode: ignore
    logs:
      log_record:
        - 'severity_number < 9'                                  # below INFO
        - 'IsMatch(body, ".*health.*check.*")'
        - 'resource.attributes["k8s.namespace.name"] == "kube-system"'

  # 6. ⭐ TAIL SAMPLING (gateway tier only)
  tail_sampling:
    decision_wait: 10s
    num_traces: 200000
    expected_new_traces_per_sec: 2000
    decision_cache: {sampled_cache_size: 100000}
    policies:
      - {name: errors, type: status_code, status_code: {status_codes: [ERROR]}}
      - {name: http-5xx, type: numeric_attribute,
         numeric_attribute: {key: http.response.status_code, min_value: 500}}
      - {name: slow, type: latency, latency: {threshold_ms: 1000}}
      - {name: money-path, type: string_attribute,
         string_attribute: {key: url.path, values: [/api/orders, /api/checkout]}}
      - {name: not-health, type: string_attribute,
         string_attribute: {key: url.path, values: [/healthz, /metrics], invert_match: true}}
      - {name: base, type: probabilistic, probabilistic: {sampling_percentage: 10}}
      # composite policies:
      - name: and-example
        type: and
        and: {and_sub_policy: [ {name: a, type: latency, latency: {threshold_ms: 500}},
                                {name: b, type: status_code, status_code: {status_codes: [ERROR]}} ]}
      - name: or-example
        type: composite
        composite: {max_total_spans_per_second: 1000, policy_order: [a, b],
                    composite_sub_policy: [ {name: a, type: probabilistic, probabilistic: {sampling_percentage: 20}},
                                            {name: b, type: probabilistic, probabilistic: {sampling_percentage: 5}} ],
                    rate_allocation: [ {percent: 50, policy: a}, {percent: 50, policy: b} ]}

  # 7. ⭐ HEAD SAMPLING (the probabilistic one — cheap, but blind)
  probabilistic_sampler:
    sampling_percentage: 10
    sampler_mode: equalizing     # or hash_seed
    attribute_source: context
    sampling_hash_seed: "abc123"

  # 8. transform (OTTL) — the most powerful processor
  transform:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          - set(attributes["http.route"], attributes["url.path"]) where attributes["http.route"] == nil
          - delete_key(attributes, "db.statement")
          - replace_pattern(attributes["url.full"], "\\?.*$", "?<redacted>")
          - set(status.code, 2) where attributes["http.response.status_code"] >= 500
      - context: resource
        statements:
          - set(attributes["service.name"], attributes["service.name"] ?? "unknown")
          - merge_maps(cache(), resource.attributes, "upsert")
    log_statements:
      - context: log
        statements:
          - set(severity_number, 17) where IsMatch(body, "(?i)fatal")
    metric_statements:
      - context: datapoint
        statements:
          - delete_key(attributes, "request_id")

  # 9. batching — ⭐⭐ ALWAYS LAST
  batch:
    send_batch_size: 8192
    send_batch_max_size: 16384
    timeout: 5s
    metadata_keys: [tenant_id]     # ⭐ batch per tenant (required for multi-tenancy)

  # 10. others you'll meet
  groupbyattrs: {keys: [k8s.namespace.name, k8s.pod.name]}
  metricstransform:
    transforms:
      - {include: http_request_duration_seconds, action: update, new_name: http_request_duration_seconds_new}
      - {include: x, action: insert, label: env, new_value: prod}
  transform/metrics-to-histogram: {}
  cumulativetodelta: {}          # ⭐ required when sending cumulative metrics to some vendors
  deltatorate: {}
  span:                          # rename spans, extract attributes from names
    name: {from_attributes: [http.route], separator: " "}
  routing: {from_attribute: team, default_exporters: [otlp/default], error_mode: ignore,
            attribute_source: resource, table: [{value: payments, exporters: [otlp/payments]}]}
```

### 8.4 The exporters

```yaml
exporters:
  otlp:                                   # → another Collector, Tempo, Jaeger, a vendor
    endpoint: tempo.monitoring.svc:4317
    tls: {insecure: true}                 # or {cert_file, key_file, ca_file}
    compression: gzip
    sending_queue: {enabled: true, num_consumers: 10, queue_size: 10000}
    retry_on_failure: {enabled: true, initial_interval: 5s, max_interval: 30s, max_elapsed_time: 300s}
    timeout: 10s
    headers: {X-Scope-OrgID: payments}

  otlphttp:                               # → OTLP over HTTP
    endpoint: https://otlp.example.com
    headers: {Authorization: "Bearer ${env:TOKEN}"}
    compression: gzip

  prometheusremotewrite:                  # ⭐ → Prometheus / Mimir / Cortex / Thanos
    endpoint: http://prometheus.monitoring.svc:9090/api/v1/write
    resource_to_telemetry_conversion: {enabled: true}    # ⭐ resource attrs → labels
    send_metadata: true
    external_labels: {cluster: learn}
    target_info: {enabled: true}
    max_batch_size_bytes: 3000000
    remote_write_queue: {enabled: true, queue_size: 10000, num_consumers: 10}
    # ⚠️ the metric names get mangled: http.server.duration → http_server_duration_seconds

  prometheus:                             # ⭐ expose /metrics for Prometheus to SCRAPE
    endpoint: 0.0.0.0:8888
    namespace: otel
    const_labels: {cluster: learn}
    resource_to_telemetry_conversion: {enabled: true}
    send_timestamps: true
    enable_open_metrics: true
    metric_expiration: 10m
    target_info: {enabled: true}

  loki:                                   # ⭐ → Loki
    endpoint: http://loki.monitoring.svc:3100/loki/api/v1/push
    default_labels_enabled: {exporter: true, job: true, instance: false, level: true}
    tenant_id: ""
    headers: {X-Scope-OrgID: "${tenant_id}"}

  datadog:
    api: {site: datadoghq.com, key: ${env:DD_API_KEY}}
    traces: {endpoint: https://trace.agent.datadoghq.com, ignore_resources: ["GET /health"]}
    metrics: {delta_ttl: 300, resource_attributes_as_tags: [team, tier], summarize_when_max_duplicates: true}
    logs: {use_compression: true, compression_level: 6, batch_wait: 10}
    host_metadata: {enabled: true, hostname_source: first_tag}
    only: ["team:payments"]               # ⭐ phase in by team

  debug:                                  # ⭐ THE learning exporter
    verbosity: basic                      # basic | normal | detailed
    sampling_initial: 5
    sampling_thereafter: 200

  file:                                   # archive to disk
    path: /var/log/otel/archive.json
    format: json
    compression: gzip
    rotation: {max_megabytes: 100, max_days: 7, max_backups: 5}

  loadbalancing:                          # ⭐⭐ route by trace ID for tail sampling
    protocol:
      otlp: {tls: {insecure: true}, timeout: 10s}
    resolver:
      k8s: {service: otel-gateway.otel.svc.cluster.local, namespaces: [otel], port: 4317}
      # or: dns: {hostname: otel-gateway.otel.svc.cluster.local, port: 4317}
      # or: static: {hostnames: [gw-1:4317, gw-2:4317]}

  nop: {}                                 # discard (for benchmarking)
```

### 8.5 Connectors ⭐ the elegant pattern

A **connector** is simultaneously an exporter (in pipeline A) and a receiver (in pipeline B). It turns one signal into another.

```yaml
connectors:
  spanmetrics:                            # ⭐ traces → RED metrics, automatically
    histogram:
      explicit: {buckets: [10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2s, 5s, 10s]}
    dimensions:
      - {name: http.route}
      - {name: http.response.status_code}
      - {name: customer.tier}             # ⭐ business dimensions!
    dimensions_cache_size: 1000
    aggregation_temporality: 2
    exemplars: {enabled: true}            # ⭐⭐ metrics WITH trace IDs = exemplars for free

  exceptions:                             # ⭐ span events with exception.* → a metric
    dimensions: [exception.type, exception.message]

  count:                                  # count spans/logs/metrics
    logs:
      error.count: {conditions: [severity = SEVERITY_NUMBER_ERROR]}
    spans:
      error.span.count: {conditions: [status = STATUS_CODE_ERROR]}

  routing:                                # route by a resource attribute
    from_attribute: team
    default_pipelines: [otlp/default]
    table: [{value: payments, pipelines: [otlp/payments]}]

  servicegraph:                           # ⭐ the service map, as metrics
    dimensions: [k8s.namespace.name]

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, tail_sampling, batch]
      exporters: [otlp/tempo, spanmetrics, exceptions, servicegraph]   # ⭐ a connector as an exporter
    metrics/spanmetrics:                                                  # ⭐ and as a receiver
      receivers: [spanmetrics, exceptions, servicegraph]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]
    logs/count:
      receivers: [count]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]
```

> 🔑 **`spanmetrics` + `exemplars: enabled` is the single best connector.** It gives you RED metrics *derived from traces* (so services with no `/metrics` still get them), **with exemplars attached** — meaning your metric→trace correlation works even for services that don't emit Prometheus exemplars natively.

### 8.6 The service telemetry (monitoring the Collector)

```yaml
service:
  telemetry:
    logs:
      level: info                      # debug | info | warn | error
      encoding: json                   # ⭐ structured, so you can query it in Loki
      output_paths: [stdout]
      initial_fields: {environment: production}
    metrics:
      level: detailed                  # basic | normal | detailed
      readers:
        - pull: {exporter: {prometheus: {host: 0.0.0.0, port: 8888}}}
    resource:
      service.name: otel-gateway
      service.version: "0.158.0"
      service.instance.id: ${env:MY_POD_NAME}
    traces:                            # the Collector's OWN traces (rarely enabled)
      processors: [{batch: {}}]
      propagators: [b3, tracecontext]
```

### 8.7 The Collector metrics that matter ⭐

```promql
# throughput
sum(rate(otelcol_receiver_accepted_spans[5m]))
sum(rate(otelcol_exporter_sent_spans[5m]))
sum(rate(otelcol_receiver_accepted_log_records[5m]))
sum(rate(otelcol_receiver_accepted_metric_points[5m]))

# ⭐⭐ drops and refusals — must be zero
sum(rate(otelcol_processor_dropped_spans[5m]))
sum(rate(otelcol_processor_refused_spans[5m]))
sum(rate(otelcol_exporter_send_failed_spans[5m]))
sum(rate(otelcol_exporter_enqueue_failed_spans[5m]))
sum(rate(otelcol_receiver_refused_spans[5m]))

# tail sampling
sum(rate(otelcol_processor_tail_sampling_sampling_decision_timer_sum[5m]))
sum(rate(otelcol_processor_tail_sampling_sampling_trace_dropped_too_early[5m]))
sum(rate(otelcol_processor_tail_sampling_sampling_policy_evaluation_error[5m]))
otelcol_processor_tail_sampling_sampling_traces_received

# batching
otelcol_processor_batch_batch_send_size_bytes
otelcol_processor_batch_timeout_trigger_send_total
otelcol_processor_batch_metadata_cardinality       # ⭐ a leak here = too many metadata_keys

# the export queue
otelcol_exporter_queue_size / clamp_min(otelcol_exporter_queue_capacity, 1)

# resources
otelcol_process_uptime
otelcol_process_runtime_total_sys_memory_bytes
otelcol_process_memory_rss
```

### 8.8 CLI

```bash
otelcol-contrib --version
otelcol-contrib --config=config.yaml --dry-run          # ⭐ validate without running
otelcol-contrib validate --config=config.yaml
otelcol-contrib components --config=config.yaml         # ⭐ what's compiled in
otelcol-contrib expand --config=config.yaml             # resolve env vars and !include
otelcol-contrib --config=config.yaml --feature-gates=…
otelcol-contrib --set=processors.batch.timeout=10s --config=config.yaml   # ⭐ override from the CLI

# env-var substitution and includes in the config
#   endpoint: ${env:OTLP_ENDPOINT}
#   endpoint: ${OTLP_ENDPOINT:-localhost:4317}
#   endpoint: ${file:/etc/otel/endpoint.txt}
#   exporters: !include ./exporters.yaml

# the built-in endpoints
curl -s localhost:13133/           # health_check extension → "Collector server is running."
curl -s localhost:55679/debug/tracez    # zpages
curl -s localhost:1777/            # pprof extension (if enabled)
curl -s localhost:8888/metrics     # the Collector's own telemetry
```

---

<a name="9--otel-sdks--per-language"></a>
## 9 · OTel SDKs — env vars per language

### 9.1 The universal spec variables ⭐ (these work everywhere)

```bash
# ── identity ─────────────────────────────────────────────────────
OTEL_SERVICE_NAME=shop-api                       # ⭐⭐ THE most important one
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.version=1.4.2,team=payments
OTEL_SERVICE_NAMESPACE=shop
OTEL_SERVICE_INSTANCE_ID=${POD_NAME}

# ── where to send ────────────────────────────────────────────────
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-agent.otel.svc:4317     # ⭐ the default for ALL signals
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://…:4317/v1/traces                # per-signal override
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=…
OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=…
OTEL_EXPORTER_OTLP_PROTOCOL=grpc                 # grpc | http/protobuf | http/json
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer xxx,tenant=payments
OTEL_EXPORTER_OTLP_TIMEOUT=10000                 # ms
OTEL_EXPORTER_OTLP_COMPRESSION=gzip
OTEL_EXPORTER_OTLP_CERTIFICATE=/path/ca.pem
OTEL_EXPORTER_OTLP_INSECURE=true

# ── which exporters (per signal) ─────────────────────────────────
OTEL_TRACES_EXPORTER=otlp                        # otlp | jaeger | zipkin | console | none
OTEL_METRICS_EXPORTER=otlp                       # otlp | prometheus | console | none
OTEL_LOGS_EXPORTER=otlp                          # otlp | console | none
OTEL_SDK_DISABLED=false                          # ⭐ the kill switch — one env var, zero traces

# ── propagation ──────────────────────────────────────────────────
OTEL_PROPAGATORS=tracecontext,baggage            # ⭐⭐ must be IDENTICAL across every language
                                                 # options: tracecontext, baggage, b3, b3multi,
                                                 #          jaeger, xray, ottrace, none

# ── sampling ─────────────────────────────────────────────────────
OTEL_TRACES_SAMPLER=parentbased_traceidratio     # always_on | always_off | traceidratio |
                                                 # parentbased_always_on | parentbased_always_off |
                                                 # parentbased_traceidratio |
                                                 # jaeger_remote | parentbased_jaeger_remote
OTEL_TRACES_SAMPLER_ARG=1.0                      # ⭐ 1.0 when the gateway tail-samples
OTEL_TRACES_SAMPLER_REMOTE_ENDPOINT=…            # for jaeger_remote

# ── batching (the BatchSpanProcessor) ────────────────────────────
OTEL_BSP_SCHEDULE_DELAY=2000                     # ms between exports
OTEL_BSP_EXPORT_TIMEOUT=10000
OTEL_BSP_MAX_QUEUE_SIZE=4096                     # ⭐ spans buffered before dropping
OTEL_BSP_MAX_EXPORT_BATCH_SIZE=1024

# ── limits ───────────────────────────────────────────────────────
OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT=1024
OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT=64
OTEL_SPAN_EVENT_COUNT_LIMIT=64
OTEL_SPAN_LINK_COUNT_LIMIT=32
OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT=1024
OTEL_BAGGAGE_VALUE_LENGTH_LIMIT=8192
```

### 9.2 Java — the agent

```bash
# ⭐ the agent flag
JAVA_TOOL_OPTIONS="-javaagent:/opt/otel/opentelemetry-javaagent.jar"

# download
curl -LO https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.11.0/opentelemetry-javaagent.jar

# the Java-specific variables
OTEL_JAVAAGENT_DEBUG=true                        # ⭐ the diagnostic switch
OTEL_JAVAAGENT_EXTENSIONS=/opt/otel/extensions/  # custom instrumentation JARs
OTEL_JAVAAGENT_EXCLUDE_CLASSES=com.foo.Bar,com.baz.*
OTEL_JAVAAGENT_EXCLUDE_CLASS_LOADERS=
OTEL_JAVA_GLOBAL_AUTOCONFIGURE_ENABLED=true
OTEL_JAVA_DISABLED_RESOURCE_PROVIDERS=

# per-library instrumentation toggles
OTEL_INSTRUMENTATION_HIBERNATE_ENABLED=true
OTEL_INSTRUMENTATION_JDBC_ENABLED=true
OTEL_INSTRUMENTATION_SPRING_SCHEDULER_ENABLED=false
OTEL_INSTRUMENTATION_COMMON_DEFAULT_ENABLED=true
OTEL_INSTRUMENTATION_COMMON_PEER_SERVICE_MAPPING=postgresql=db-service,redis=cache
OTEL_INSTRUMENTATION_METHODS_INCLUDE=com.myco.MyClass[myMethod1,myMethod2]   # ⭐ manual spans via config
OTEL_INSTRUMENTATION_RUNTIME_TELEMETRY_JAVA8_ENABLED=true

# logging: the agent injects trace_id/span_id/trace_flags into the MDC
# ⭐ so %X{trace_id} in your logback pattern just works. No config needed.
OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_LOG_ATTRIBUTES=true
OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_CAPTURE_CODE_ATTRIBUTES=true

# verify it loaded
java -jar app.jar 2>&1 | grep opentelemetry-javaagent
# [otel.javaagent …] INFO io.opentelemetry.javaagent.tooling.VersionLogger -
#   opentelemetry-javaagent - version: 2.11.0

# ⭐ the Spring Boot Starter (an ALTERNATIVE to the agent — compile-time instrumentation)
# <dependency>
#   <groupId>io.opentelemetry.instrumentation</groupId>
#   <artifactId>opentelemetry-spring-boot-starter</artifactId>
# </dependency>
```

### 9.3 Go

```go
// ⭐ Go has NO auto-instrumentation (statically compiled). Everything is explicit.
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/propagation"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/otel/sdk/resource"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
    "go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
    "go.opentelemetry.io/contrib/propagators/b3"
)

// the 5 things you MUST do:
otel.SetTracerProvider(tp)                                                    // 1
otel.SetMeterProvider(mp)                                                     // 2
otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(          // 3 ⭐⭐
    propagation.TraceContext{}, propagation.Baggage{}))
httpServer.Handler = otelhttp.NewHandler(mux, "service")                      // 4 (server spans)
defer tp.Shutdown(ctx)                                                        // 5 ⭐ FLUSH

// outbound: inject
otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))
// or just wrap the transport:
client := &http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport)}

// inbound: extract
ctx = otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))

// spans
ctx, span := tracer.Start(ctx, "operation-name",
    trace.WithSpanKind(trace.SpanKindClient),
    trace.WithAttributes(attribute.String("order.id", id)))
defer span.End()
span.SetStatus(codes.Error, "failed")
span.RecordError(err)
span.AddEvent("something.happened", trace.WithAttributes(attribute.Int("n", 3)))
span.SetName("a-better-name")
trace.SpanFromContext(ctx)               // get the current span
span.SpanContext().TraceID().String()    // ⭐ for the log line
```

```bash
go get go.opentelemetry.io/otel@v1.33.0 \
       go.opentelemetry.io/otel/sdk@v1.33.0 \
       go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc@v1.33.0 \
       go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp@v0.58.0
```

### 9.4 Python

```bash
# ⭐ the distro + bootstrap pattern — zero code changes
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install              # ⭐ detects YOUR libraries and installs their instrumentation
opentelemetry-instrument python app.py          # ⭐ wraps the process

# what it installed
pip list | grep opentelemetry-instrumentation
# opentelemetry-instrumentation-flask, -requests, -sqlalchemy, -psycopg2, -redis, -pika, -logging, …

# Dockerfile
ENTRYPOINT ["opentelemetry-instrument", "python", "app.py"]
```

```python
# the manual API
from opentelemetry import trace, context, propagate, baggage
from opentelemetry.trace import SpanKind, Status, StatusCode, Link

tracer = trace.get_tracer("my.module", "1.0.0")

with tracer.start_as_current_span("operation", kind=SpanKind.SERVER,
                                  attributes={"order.id": oid}) as span:
    span.set_attribute("cart.items", 3)
    span.add_event("validated")
    span.set_status(Status(StatusCode.OK))
    try:
        …
    except Exception as e:
        span.set_status(Status(StatusCode.ERROR, str(e)))
        span.record_exception(e)
        raise

trace.get_current_span().get_span_context().trace_id       # ⭐ for the log line
propagate.inject(headers)                                   # outbound
ctx = propagate.extract(carrier=request.headers)            # inbound
baggage.set_baggage("tenant", "acme")                       # ⭐ cross-service key/values
trace.get_tracer_provider().force_flush(timeout_millis=10000)   # ⭐ FLUSH before exit

# logging integration ⭐
from opentelemetry.instrumentation.logging import LoggingInstrumentor
LoggingInstrumentor().instrument(set_logging_format=True)
# → %(otelTraceID)s %(otelSpanID)s %(otelServiceName)s become available
```

### 9.5 JavaScript / Node / Browser

```bash
npm i @opentelemetry/api @opentelemetry/sdk-trace-web @opentelemetry/sdk-trace-base \
      @opentelemetry/exporter-trace-otlp-http @opentelemetry/resources \
      @opentelemetry/instrumentation @opentelemetry/instrumentation-document-load \
      @opentelemetry/instrumentation-fetch @opentelemetry/instrumentation-xml-http-request \
      @opentelemetry/instrumentation-user-interaction @opentelemetry/semantic-conventions
# Node instead:
npm i @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node \
      @opentelemetry/exporter-trace-otlp-grpc
```

```javascript
// ── Node: the one-liner ─────────────────────────────────────────
// otel.js — MUST be required FIRST, before any other import
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-fs': {enabled: false},   // ⭐ noisy — disable it
  })],
});
sdk.start();
process.on('SIGTERM', () => sdk.shutdown().finally(() => process.exit(0)));   // ⭐ FLUSH
// node -r ./otel.js app.js

// ── the browser ─────────────────────────────────────────────────
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { DocumentLoadInstrumentation } from '@opentelemetry/instrumentation-document-load';

const provider = new WebTracerProvider({resource});
provider.addSpanProcessor(new BatchSpanProcessor(
  new OTLPTraceExporter({url: 'https://otel.example.com/v1/traces'})));
provider.register();
registerInstrumentations({instrumentations: [
  new DocumentLoadInstrumentation(),
  new FetchInstrumentation({
    propagateTraceHeaderCorsUrls: [/api\.example\.com/],   // ⭐⭐ WITHOUT THIS, NO PROPAGATION
    ignoreUrls: [/\/metrics$/, /google-analytics/],
  }),
]});
// ⚠️ CORS must allow your origin on the Collector's OTLP/HTTP receiver.
```

### 9.6 The semantic conventions you must use ⭐

```
# ── resource (WHO) ──────────────────────────────────────────────
service.name              ⭐⭐ required. The K8s Deployment name.
service.version           the semver / image tag
service.namespace         shop
service.instance.id       the pod name
deployment.environment.name   development | staging | production
telemetry.sdk.name / .language / .version    (set by the SDK)
host.name / host.id / host.arch
os.type / os.description
container.id / container.name / container.image.name
k8s.namespace.name / k8s.pod.name / k8s.deployment.name / k8s.node.name
k8s.cluster.name
process.pid / process.executable.name / process.runtime.name / .version
cloud.provider / cloud.region / cloud.account.id

# ── HTTP ────────────────────────────────────────────────────────
http.request.method        GET | POST           (was http.method)
http.response.status_code  200                  (was http.status_code)
http.route                 /api/orders/{id}     ⭐ THE TEMPLATE, never the raw path
url.scheme / url.full / url.path / url.query
server.address / server.port
client.address / user_agent.original
network.protocol.version / network.transport

# ── database ────────────────────────────────────────────────────
db.system                  postgresql | mysql | redis | mongodb
db.namespace               the database/schema name
db.query.text              ⭐ the query — HASH OR REDACT IT
db.operation.name          SELECT | INSERT
db.collection.name / db.sql.table
server.address / server.port

# ── messaging ⭐ (queues) ───────────────────────────────────────
messaging.system           rabbitmq | kafka | sqs
messaging.destination.name the queue/topic
messaging.operation.name   publish | receive | process
messaging.message.id / .conversation_id
messaging.batch.message_count
messaging.rabbitmq.destination.routing_key
messaging.kafka.message.key / .destination.partition
messaging.kafka.offset

# ── RPC / exceptions / genai ────────────────────────────────────
rpc.system / rpc.service / rpc.method
exception.type / exception.message / exception.stacktrace / exception.escaped
gen_ai.system / gen_ai.request.model / gen_ai.usage.input_tokens / .output_tokens
```

---

<a name="10--instrumentation-recipes"></a>
## 10 · Instrumentation recipes

### 10.1 Spring Boot — the complete setup

```xml
<!-- ⭐ Micrometer → Prometheus (metrics) -->
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
<dependency><groupId>io.micrometer</groupId><artifactId>micrometer-registry-prometheus</artifactId></dependency>
<!-- ⭐ Micrometer TRACING → OTLP (spans, WITHOUT the agent) -->
<dependency><groupId>io.micrometer</groupId><artifactId>micrometer-tracing-bridge-otel</artifactId></dependency>
<dependency><groupId>io.opentelemetry</groupId><artifactId>opentelemetry-exporter-otlp</artifactId></dependency>
<!-- ⭐ OR: the whole thing in one starter -->
<dependency><groupId>io.opentelemetry.instrumentation</groupId>
            <artifactId>opentelemetry-spring-boot-starter</artifactId></dependency>
```

```yaml
management:
  server: {port: 9090}                     # ⭐ metrics on a SEPARATE port
  endpoints:
    web: {exposure: {include: health,info,prometheus,metrics}}
  endpoint: {health: {probes: {enabled: true}, show-details: when_authorized}}
  prometheus.metrics.export.enabled: true
  metrics:
    tags: {application: shop-api, env: prod, team: payments}   # ⭐ on EVERY metric
    distribution:
      percentiles-histogram:
        http.server.requests: true          # ⭐⭐ required for histogram_quantile
      slo:
        http.server.requests: 50ms,100ms,200ms,300ms,500ms,1s,2s   # ⭐ aligned to your SLO
      minimum-expected-value:
        http.server.requests: 10ms
      maximum-expected-value:
        http.server.requests: 5s
    enable:
      jvm: true
      tomcat: true
      hikaricp: true
      logback: true
      processor: true
      disk: false                           # ⭐ off — high cardinality, low value

spring:
  application: {name: shop-api}

logging:
  pattern:
    console: '{"timestamp":"%d{yyyy-MM-dd''T''HH:mm:ss.SSSXXX}","level":"%p","logger":"%logger{36}","thread":"%t","trace_id":"%X{trace_id}","span_id":"%X{span_id}","service":"shop-api","message":"%m","exception":"%ex"}%n'
    # ⭐ %X{trace_id} is populated by the OTel agent's MDC injection
```

```java
// the four metric types
Counter   counter   = Counter.builder("shop.orders").tag("tier", tier).register(registry);
Gauge     gauge     = Gauge.builder("shop.orders.pending", state, State::pending).register(registry);
Timer     timer     = Timer.builder("shop.order.processing").publishPercentileHistogram().register(registry);
DistributionSummary ds = DistributionSummary.builder("shop.cart.size").register(registry);

counter.increment();
timer.record(() -> doWork());
Timer.Sample s = Timer.start(registry); … s.stop(timer);

// ⭐ with Micrometer Tracing (no agent)
Observation obs = Observation.createNotStarted("checkout", registry)
    .lowCardinalityKeyValue("tier", tier)          // ⭐ becomes a metric tag
    .highCardinalityKeyValue("order.id", oid)      // ⭐ becomes a span attribute ONLY
    .contextualName("checkout")
    .start();
try (Observation.Scope sc = obs.openScope()) { doWork(); }
catch (Exception e) { obs.error(e); throw e; }
finally { obs.stop(); }
// ⭐⭐ lowCardinality = metric + span. highCardinality = span ONLY. Get this backwards
//    and you have a cardinality bomb.
```

### 10.2 Go — the four metric types

```go
import "github.com/prometheus/client_golang/prometheus"
import "github.com/prometheus/client_golang/prometheus/promauto"
import "github.com/prometheus/client_golang/prometheus/promhttp"

var (
    requests = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "shop_requests_total", Help: "Requests served."},
        []string{"method", "path", "status"})

    inflight = promauto.NewGauge(prometheus.GaugeOpts{
        Name: "shop_requests_in_flight", Help: "Requests being served."})

    duration = promauto.NewHistogramVec(prometheus.HistogramOpts{
        Name: "shop_request_duration_seconds", Help: "Request latency.",
        Buckets: []float64{.01,.025,.05,.1,.25,.5,1,2,5},   // ⭐ aligned to your SLO
        // or native/exponential: NativeHistogramBucketFactor: 1.1,
    }, []string{"method", "path"})

    summary = promauto.NewSummaryVec(prometheus.SummaryOpts{
        Name: "shop_summary_seconds", Help: "…",
        Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001}},
        []string{"method"})
)

requests.WithLabelValues("GET", "/api/items", "200").Inc()
inflight.Inc(); defer inflight.Dec()
duration.WithLabelValues("GET", "/api/items").Observe(elapsed.Seconds())
duration.ObserveWithExemplar(v, prometheus.Labels{"trace_id": tid})   // ⭐ EXEMPLARS

// a gauge computed on demand
promauto.NewGaugeFunc(prometheus.GaugeOpts{Name: "shop_config_max_conns"},
    func() float64 { return float64(cfg.MaxConns) })

// serving
mux.Handle("/metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{
    EnableOpenMetrics: true,            // ⭐⭐ required for exemplars
    Registry: reg,
    ErrorHandling: promhttp.ContinueOnError,
}))
```

### 10.3 Python

```python
from prometheus_client import Counter, Gauge, Histogram, Summary, start_http_server, \
                              generate_latest, CONTENT_TYPE_LATEST, CollectorRegistry, multiprocess

REQUESTS = Counter("shop_requests_total", "Requests.", ["method", "path", "status"])
INFLIGHT = Gauge("shop_in_flight", "In flight.")
DURATION = Histogram("shop_request_duration_seconds", "Latency.", ["method", "path"],
                     buckets=(.01,.025,.05,.1,.25,.5,1,2,5))
SUMMARY  = Summary("shop_summary_seconds", "…", ["method"],
                   # ⚠️ quantiles are EXPENSIVE and NOT aggregatable
                   )

REQUESTS.labels("GET", "/api/items", "200").inc()
INFLIGHT.inc(); INFLIGHT.dec(); INFLIGHT.set(5)
with DURATION.labels("GET", "/api/items").time():
    do_work()
DURATION.labels("GET", "/api/items").observe(0.42)

start_http_server(9092)                          # ⭐ the simplest server
# or in Flask:
from prometheus_flask_exporter import PrometheusMetrics
PrometheusMetrics(app)
# or in FastAPI:
from prometheus_fastapi_instrumentator import Instrumentator
Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)
```

### 10.4 The custom metrics you should always have

```
# ── RED, per endpoint (usually free from the framework) ──────────
http_server_requests_seconds_{count,sum,bucket}

# ── the FUNNEL ⭐⭐ the business SLO (Task C3) ────────────────────
shop_checkout_sessions_total{outcome="started"}
shop_checkout_sessions_total{outcome="completed"}
shop_checkout_sessions_total{outcome="abandoned",reason="payment_failed"}

# ── the SATURATION of every finite resource you hold ─────────────
hikaricp_connections_{active,idle,pending,max,timeout_total}
tomcat_threads_{busy,current,config_max}
worker_jobs_in_flight
worker_queue_depth{queue="orders"}
jvm_memory_used_bytes{area="heap",id="…"}

# ── the DEPENDENCY health, split by dependency ───────────────────
payment_charges_total{provider="stripe",status="200"}
payment_charge_duration_seconds_bucket{provider="stripe"}
elasticsearch_query_duration_seconds_bucket{index="products"}

# ── the BUSINESS events (bounded cardinality only!) ──────────────
shop_orders_created_total{tier="gold",channel="web"}
shop_orders_rejected_total{reason="payment_declined"}
shop_revenue_cents_total{currency="USD"}

# ── the CORRECTNESS invariants ⭐ (things that should never happen)
shop_cart_cleared_on_failed_checkout_total     # ⭐ must be ZERO
shop_order_created_without_payment_total       # ⭐ must be ZERO
shop_duplicate_order_id_total                  # ⭐ must be ZERO

# ── the freshness of every background job ────────────────────────
shop_search_index_lag_seconds
shop_price_sync_last_success_timestamp_seconds
time() - shop_price_sync_last_success_timestamp_seconds > 600
```

---

<a name="11--slos--sloth"></a>
## 11 · SLOs & sloth

### 11.1 The concepts

```
SLI   a Service Level INDICATOR — a measured ratio:  good events / total events
SLO   a Service Level OBJECTIVE — a target on the SLI: "99.9% over 30 days"
SLA   a Service Level AGREEMENT — an SLO with a CONTRACT and a PENALTY. External.
Error budget = 100% − SLO. 99.9% over 30d = 43.2 minutes of allowed failure.
Burn rate = the rate you're consuming the budget, as a multiple of the SLO allowance.
          14.4× = you'll exhaust 30 days of budget in 2.08 days.
```

### 11.2 The multi-window multi-burn-rate matrix ⭐

| Severity | Long window | Short window | Burn rate | Budget consumed | Time to exhaust | Action |
|---|---|---|---|---|---|---|
| **Page** | 1h | 5m | 14.4× | 2% | 2.08 days | wake someone |
| **Page** | 6h | 30m | 6× | 5% | 5 days | wake someone |
| **Ticket** | 1d (24h) | 2h | 3× | 10% | 10 days | next business day |
| **Ticket** | 3d | 6h | 1× | 10% | 30 days | next business day |

**Why two windows?** The long window prevents firing on a stale burn; the short window ensures the problem is *still happening now*. A 14.4× burn measured over 1h that stopped 5 minutes ago must not page.

```promql
# the generated rule, verbatim
- alert: MySLOBurnRateFast
  expr: |
    (
      slo:sli_error:ratio_rate5m   > (14.4 * 0.001)
      and
      slo:sli_error:ratio_rate1h   > (14.4 * 0.001)
    )
  for: 2m
  labels: {severity: critical}
```

### 11.3 sloth CLI

```bash
go install github.com/slok/sloth/cmd/sloth@latest      # ⭐ v0.13.x

sloth generate -i slos/ -o rules.yaml                  # a directory of specs
sloth generate -i slos/checkout.yaml -o checkout-rules.yaml
sloth generate -i slos/ --out-prometheus               # ⭐ the MWMBR alert set
sloth generate -i slos/ --check-rules                  # ⭐ validate after generating
sloth generate -i slos/ --labels "team=payments,tier=backend"
sloth generate -i slos/ --extra-labels "slo_source=sloth"
sloth generate -i slos/ --dry-run                      # print to stdout
sloth version
sloth help generate

# the spec (PrometheusServiceLevel)
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata: {name: checkout, namespace: monitoring}
spec:
  service: shop
  labels: {team: payments}
  slos:
    - name: checkout-availability
      objective: 99.9                       # ⭐ a float, 0–100
      description: "…"
      owner: payments-team
      labels: {tier: critical}
      sli:
        events:
          errorQuery: sum(rate(x_count{status=~"5.."}[{{.window}}]))
          totalQuery: sum(rate(x_count[{{.window}}]))
        raw:
          errorRatioQuery: "…"              # ⭐ alternative: supply the ratio directly
      alerting:
        name: CheckoutAvailability          # the alert-name prefix
        labels: {team: payments}
        annotations: {dashboard: "…"}
        pageAlert:   {labels: {severity: critical}, annotations: {runbook_url: "…"}}
        ticketAlert: {labels: {severity: warning}}
        disable: false                      # ⭐ generate the SLI but no alerts

# ⭐ the metrics sloth emits, for your own dashboards:
sloth_slo_sli{service, slo}                          # the current SLI ratio
sloth_slo_error_budget_ratio{service, slo}           # budget consumed, 0–1+
sloth_slo_error_budget_remaining_ratio{service, slo} # budget left
sloth_slo_objective_ratio{service, slo}              # the target
```

### 11.4 The error-budget math

```
SLO 99.9% over 30 days:
  total minutes          = 30 × 24 × 60      = 43,200
  allowed bad minutes    = 43,200 × 0.001    =     43.2 min
  burn rate 1×           = 43.2 min / 30d    → exhausts in 30 days
  burn rate 14.4×        =                     → exhausts in 2.08 days
  burn rate 100×         =                     → exhausts in 7.2 hours

SLO 99% over 30 days:
  allowed bad minutes    = 43,200 × 0.01     =    432 min = 7.2 h

SLO 99.99% over 30 days:
  allowed bad minutes    = 43,200 × 0.0001   =   4.32 min     ⭐ four minutes a MONTH

requests-based (not time-based):
  1M requests/day × 30d = 30M requests
  SLO 99.9%             → 30,000 allowed failures per month
  a burn rate of 14.4×  → 30,000 exhausted in 2.08 days = 14,400 failures/day
```

---

<a name="12--exporters--the-reference-table"></a>
## 12 · Exporters — the reference table

| Exporter | Image / binary | Port | The key metrics |
|---|---|---|---|
| **node_exporter** | `quay.io/prometheus/node-exporter:v1.9.1` | 9100 | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes`, `node_disk_io_time_seconds_total`, `node_load1`, `node_network_receive_bytes_total` |
| **kube-state-metrics** | `registry.k8s.io/kube-state-metrics:v2.14.0` | 8080 | `kube_pod_status_phase`, `kube_pod_container_status_restarts_total`, `kube_pod_container_resource_limits`, `kube_deployment_status_replicas_available`, `kube_node_status_condition`, `kube_pod_labels` ⭐ |
| **cAdvisor** | built into the kubelet | 10250 | `container_cpu_usage_seconds_total`, `container_cpu_cfs_throttled_periods_total`, `container_memory_working_set_bytes`, `container_network_receive_bytes_total`, `container_fs_writes_bytes_total` |
| **blackbox_exporter** | `prom/blackbox-exporter:v0.26.0` | 9115 | `probe_success`, `probe_duration_seconds`, `probe_http_status_code`, `probe_http_duration_seconds`, `probe_ssl_earliest_cert_expiry`, `probe_dns_lookup_time_seconds` |
| **postgres_exporter** | `quay.io/prometheuscommunity/postgres-exporter:v0.16.0` | 9187 | `pg_up`, `pg_stat_activity_count`, `pg_stat_database_blks_hit`, `pg_stat_replication_pg_wal_lsn_diff`, `pg_settings_max_connections` |
| **mysql_exporter** | `prom/mysqld-exporter:v0.15.1` | 9104 | `mysql_up`, `mysql_global_status_threads_connected`, `mysql_global_status_slow_queries`, `mysql_slave_status_seconds_behind_master` |
| **redis_exporter** | `oliver006/redis_exporter:v1.66.0` | 9121 | `redis_up`, `redis_memory_used_bytes`, `redis_keyspace_hits_total`, `redis_connected_clients`, `redis_evicted_keys_total`, `redis_commands_processed_total` |
| **mongodb_exporter** | `percona/mongodb_exporter:0.43` | 9216 | `mongodb_up`, `mongodb_ss_connections`, `mongodb_ss_opcounters`, `mongodb_ss_wt_cache_bytes_currently_in_the_cache` |
| **nginx-prometheus-exporter** | `nginx/nginx-prometheus-exporter:1.3` | 9113 | `nginx_connections_active`, `nginx_http_requests_total` |
| **haproxy** | built in (`stats` module) | 9101 | `haproxy_server_status`, `haproxy_frontend_http_requests_total`, `haproxy_backend_connection_errors_total` |
| **kafka_exporter** | `danielqsj/kafka-exporter:v1.7.0` | 9308 | `kafka_consumergroup_lag` ⭐, `kafka_topic_partitions`, `kafka_consumergroup_current_offset` |
| **RabbitMQ** | the `rabbitmq_prometheus` plugin | 15692 | `rabbitmq_queue_messages_ready`, `rabbitmq_queue_messages_unacked`, `rabbitmq_channel_messages_published_total`, `rabbitmq_connections`, `rabbitmq_process_resident_memory_bytes` |
| **elasticsearch_exporter** | `prometheuscommunity/elasticsearch-exporter:1.8.0` | 9114 | `elasticsearch_cluster_health_status`, `elasticsearch_clusterinfo_up`, `elasticsearch_indices_docs`, `elasticsearch_jvm_memory_used_bytes` |
| **cert-manager** | built in | 9402 | `certmanager_certificate_expiration_timestamp_seconds` ⭐ |
| **CoreDNS** | built in | 9153 | `coredns_dns_requests_total`, `coredns_dns_responses_total`, `coredns_cache_entries` |
| **etcd** | built in | 2379 | `etcd_server_has_leader`, `etcd_disk_wal_fsync_duration_seconds`, `etcd_network_peer_round_trip_time_seconds` |
| **JMX (Kafka/Cassandra/etc.)** | `ghcr.io/prometheus/jmx-exporter:1.0.1` | configurable | via a JMX config YAML |
| **process-exporter** | `ncabatoff/process-exporter:0.8.3` | 9256 | `namedprocess_namegroup_cpu_seconds_total`, `namedprocess_namegroup_memory_bytes` |
| **snmp_exporter** | `prom/snmp-exporter:v0.26.0` | 9116 | switches, UPSes, printers |
| **smokeping_prober** | `ghcr.io/superq/smokeping-prober:v0.9.0` | 9374 | `smokeping_response_duration_seconds` |
| **Prometheus itself** | — | 9090 | `up`, `scrape_duration_seconds`, `scrape_samples_scraped`, `prometheus_tsdb_head_series`, `prometheus_rule_evaluation_failures_total`, `prometheus_target_scrapes_exceeded_scrape_timeout_total` |
| **Alertmanager** | — | 9093 | `alertmanager_alerts`, `alertmanager_notifications_total`, `alertmanager_notifications_failed_total`, `alertmanager_silences`, `alertmanager_config_last_reload_successful` |
| **Grafana** | — | 3000 | `grafana_http_request_duration_seconds`, `grafana_datasource_health_status`, `grafana_alerting_active_alerts`, `grafana_api_response_status_total` |
| **OTel Collector** | `otel/opentelemetry-collector-contrib:0.158.0` | 8888 | see §8.7 |
| **Tempo** | `grafana/tempo:2.6.1` | 3200 | `tempo_ingester_traces_created_total`, `tempo_discarded_spans_total`, `tempo_query_frontend_query_seconds` |
| **Loki** | `grafana/loki:3.7.5` | 3100 | `loki_distributor_bytes_received_total`, `loki_discarded_samples_total`, `loki_request_duration_seconds`, `loki_ingester_memory_streams` |

```bash
# ── the generic exporter Dockerfile pattern ──────────────────────
docker run -d --name node-exporter -p 9100:9100 \
  -v /proc:/host/proc:ro -v /sys:/host/sys:ro -v /:/rootfs:ro \
  quay.io/prometheus/node-exporter:v1.9.1 \
  --path.procfs=/host/proc --path.sysfs=/host/sys --path.rootfs=/rootfs \
  --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)($|/)'

# blackbox: probe a target ad hoc from the CLI
curl -sG localhost:9115/probe --data-urlencode 'target=https://example.com' \
     --data-urlencode 'module=http_2xx' | grep -E 'probe_success|probe_duration|probe_http_status'
```

---

<a name="13--kubernetes-observability-commands"></a>
## 13 · Kubernetes observability commands

```bash
# ── what's wrong, in order ───────────────────────────────────────
kubectl get pods -A -o wide | grep -vE 'Running|Completed'
kubectl get pods -n shop -o wide
kubectl describe pod -n shop -l app=shop-api | grep -A12 'Last State'
kubectl describe pod -n shop <pod> | grep -A20 Events:
kubectl get events -n shop --sort-by=.lastTimestamp | tail -30
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -30

# ── logs ⭐ ──────────────────────────────────────────────────────
kubectl logs -n shop deploy/shop-api --tail=200
kubectl logs -n shop deploy/shop-api -f                       # follow
kubectl logs -n shop deploy/shop-api --previous               # ⭐⭐ the CRASHED container's logs
kubectl logs -n shop deploy/shop-api -c api                   # a specific container
kubectl logs -n shop deploy/shop-api --all-containers=true --prefix
kubectl logs -n shop deploy/shop-api --since=10m
kubectl logs -n shop deploy/shop-api --since-time=2026-09-09T17:00:00Z
kubectl logs -n shop -l app=shop-api --max-log-requests=20    # ⭐ all pods of a Deployment
kubectl logs -n shop deploy/shop-api --timestamps
kubectl logs node/<node>                                      # the node's system logs

# ── resources ────────────────────────────────────────────────────
kubectl top pods -n shop --sort-by=memory
kubectl top pods -n shop --sort-by=cpu
kubectl top pods -n shop --containers
kubectl top nodes
kubectl describe node <node> | grep -A8 'Allocated resources'

# ── ⭐ exec into a pod and query its own metrics endpoint ────────
kubectl exec -n shop deploy/shop-api -- wget -qO- localhost:9090/prometheus | head -50
kubectl exec -n shop deploy/shop-api -- curl -s localhost:9090/prometheus | grep http_server_requests_seconds_count
kubectl exec -n shop deploy/checkout -- wget -qO- localhost:9091/metrics | head

# ── the monitoring CRDs ──────────────────────────────────────────
kubectl get servicemonitor,podmonitor,probe,scrapeconfig -A
kubectl get prometheusrule -A
kubectl get prometheus,alertmanager,alertmanagerconfig,thanosruler -A
kubectl describe servicemonitor -n shop shop-api
kubectl get prometheusrule -n monitoring -o json | jq -r '.items[] | "\(.metadata.name)\t\([.spec.groups[].name] | join(","))"'

# ⭐ why is my ServiceMonitor ignored?
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'
kubectl get servicemonitor -n shop -o jsonpath='{.items[*].metadata.labels}'
# the labels MUST match the selector. Also check the port NAME matches.

# ── port-forwarding ──────────────────────────────────────────────
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9090 &
kubectl port-forward -n monitoring svc/tempo 3200:3200 &
kubectl port-forward -n monitoring svc/loki 3100:3100 &
kubectl port-forward -n otel svc/otel-collector-gateway 4317:4317 4318:4318 8888:8888 &
kubectl port-forward -n shop deploy/shop-api 8080:8080 9090:9090 &

# ── debugging tools on demand ────────────────────────────────────
kubectl run netshoot --image=nicolaka/netshoot -n shop --rm -it --restart=Never -- bash
kubectl run curl --image=curlimages/curl:8.10.1 -n shop --rm -it --restart=Never -- sh
kubectl run busybox --image=busybox:1.37 -n shop --rm -it --restart=Never -- sh
kubectl debug -n shop deploy/shop-api --image=nicolaka/netshoot -it --target=api   # ⭐ an ephemeral container
kubectl debug -n shop <pod> --image=openjdk:21 -it --target=api -- jcmd 1 Thread.print
kubectl debug node/<node> -it --image=busybox                                      # ⭐ debug a NODE

# ── JVM diagnostics inside a pod ⭐ ──────────────────────────────
kubectl exec -n shop deploy/shop-api -- jcmd 1 GC.heap_info
kubectl exec -n shop deploy/shop-api -- jcmd 1 Thread.print | head -100
kubectl exec -n shop deploy/shop-api -- jcmd 1 VM.flags
kubectl exec -n shop deploy/shop-api -- jcmd 1 GC.class_histogram | head -30   # ⭐ leak hunting
kubectl exec -n shop deploy/shop-api -- jcmd 1 GC.heap_dump /tmp/heap.hprof
kubectl cp shop/<pod>:/tmp/heap.hprof ./heap.hprof
kubectl exec -n shop deploy/shop-api -- jstat -gcutil 1 1000 10

# ── Go diagnostics ───────────────────────────────────────────────
curl -s localhost:6060/debug/pprof/goroutine?debug=1 | head -50
curl -s localhost:6060/debug/pprof/heap > heap.pprof
curl -s "localhost:6060/debug/pprof/profile?seconds=30" > cpu.pprof
go tool pprof -top cpu.pprof

# ── Python diagnostics ───────────────────────────────────────────
kubectl exec -n shop deploy/order-worker -- py-spy dump --pid 1
kubectl exec -n shop deploy/order-worker -- py-spy top --pid 1
kubectl exec -n shop deploy/order-worker -- py-spy record -o profile.svg --pid 1 --duration 30

# ── NetworkPolicy debugging ⭐ (silent telemetry loss) ───────────
kubectl get networkpolicy -A
kubectl describe networkpolicy -n shop
kubectl run t --image=nicolaka/netshoot -n shop --rm -it --restart=Never -- \
  bash -c 'nc -zv -w5 otel-collector-agent.otel.svc.cluster.local 4317 && echo OK || echo BLOCKED'

# ── the OTel Operator ────────────────────────────────────────────
kubectl get instrumentation -A
kubectl describe instrumentation -n shop shop-instrumentation
kubectl get opentelemetrycollectors -A
kubectl get pod -n shop -l app=shop-api -o json | jq '.items[0].spec.initContainers'
kubectl logs -n otel deploy/opentelemetry-operator-controller-manager --tail=50
```

---

<a name="14--cardinality--the-audit-toolkit"></a>
## 14 · Cardinality — the audit toolkit

```bash
# ── 1. the headline numbers ──────────────────────────────────────
curl -s localhost:9090/api/v1/status/tsdb | jq '.data.headStats'
# {"numSeries":2412880,"numLabelPairs":4821,"chunkCount":1842034,…}
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=prometheus_tsdb_head_series' | jq .
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=count({__name__=~".+"})' | jq .
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=count(count by (__name__)({__name__=~".+"}))' | jq .

# ── 2. the top metrics by series count ⭐ ────────────────────────
curl -s localhost:9090/api/v1/status/tsdb | jq -r '.data.top10SeriesCountByMetricName[] | "\(.value)\t\(.name)"'
curl -sG localhost:9090/api/v1/query \
  --data-urlencode 'query=topk(25, count by (__name__) ({__name__=~".+"}))' \
  | jq -r '.data.result[] | "\(.value)\t\(.metric.__name__)"'

# ── 3. the top metrics by SAMPLE volume (the expensive ones) ─────
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=topk(25, sum by (__name__) (scrape_samples_scraped))' | jq .
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=topk(25, scrape_samples_scraped)' | jq .

# ── 4. the cardinality of ONE metric ─────────────────────────────
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=count(container_cpu_usage_seconds_total)' | jq .
promtool query analyze http://localhost:9090 'container_cpu_usage_seconds_total' --limit=20   # ⭐

# ── 5. the cardinality of ONE label ⭐ ───────────────────────────
curl -sG localhost:9090/api/v1/label/instance/values  | jq '.data | length'
curl -sG localhost:9090/api/v1/label/pod/values       | jq '.data | length'
curl -sG localhost:9090/api/v1/label/request_id/values| jq '.data | length'   # ⛔ if >1000, that's your bomb
for l in $(curl -s localhost:9090/api/v1/labels | jq -r '.data[]'); do
  printf '%-30s %s\n' "$l" "$(curl -s localhost:9090/api/v1/label/$l/values | jq '.data | length')"
done | sort -k2 -rn | head -20

# ── 6. which LABEL drives a metric's cardinality? ────────────────
curl -sG localhost:9090/api/v1/query \
  --data-urlencode 'query=count(count by (le) (http_request_duration_seconds_bucket))' | jq .
# for each label:
for l in job instance uri method status exception outcome; do
  echo -n "$l: "; curl -sG localhost:9090/api/v1/query \
    --data-urlencode "query=count(count by ($l) (http_request_duration_seconds_count))" \
    | jq -r '.data.result[0].value[1] // 0'
done

# ── 7. CHURN — series created over time ⭐ the leak detector ─────
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=deriv(prometheus_tsdb_head_series_created_total[1h]) * 3600' | jq .
# a FLAT rate = healthy. A rate that grows with traffic = a churn leak
# (short-lived series: pod IPs, container IDs, request IDs, session IDs)

# ── 8. what does a target actually expose? ───────────────────────
curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | .scrapeUrl' | while read u; do
  n=$(curl -s "$u" | grep -c '^[a-z]' || echo 0)
  printf '%-70s %s lines\n' "$u" "$n"
done | sort -k2 -rn | head
# ⭐ and the sample count Prometheus recorded per target:
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=topk(10, scrape_samples_scraped)' \
  | jq -r '.data.result[] | "\(.value)\t\(.metric.job)/\(.metric.instance)"'

# ── 9. the relabeling efficiency ─────────────────────────────────
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=scrape_samples_scraped / clamp_min(scrape_samples_post_metric_relabeling, 1)' | jq .
# ⭐ a high ratio = your metricRelabelings are working hard. A ratio of 1 = you're
#   keeping everything, which is usually wrong for kube-state-metrics.

# ── 10. offline analysis of a TSDB block ─────────────────────────
promtool tsdb list /var/lib/prometheus/data/
promtool tsdb analyze /var/lib/prometheus/data/ <block-id> --limit=25
# prints: total series, total chunks, total samples, and the top metrics/labels in that block
```

**The cardinality rules, on one screen:**

```
✅ SAFE as a label:  job, instance, namespace, pod (bounded by replica count),
                     container, node, method (5 values), status (a dozen),
                     uri/route (TEMPLATED — a few dozen), le (your buckets),
                     queue (3 values), outcome (4 values), tier (3 values), team (4 values)

⛔ NEVER a label:    trace_id, span_id, request_id, session_id, correlation_id,
                     user_id, customer_id, email, order_id, cart_id,
                     raw URL path (with IDs in it), query strings,
                     container_id (churns on every restart), pod_ip (churns),
                     error messages, stack traces, timestamps

✅ SAFE on a SPAN or in a LOG: everything above marked ⛔.
   Spans and log lines are not aggregated, so unbounded values are a FEATURE there.
   That's the whole point of having three signals.

THE TEST: "How many distinct values will this label have in 30 days?"
   < 100     → fine
   100–1000  → watch it
   1000–10k  → you need a reason
   > 10k     → ⛔ it's a bomb. Move it to a log or a span.
```

---

<a name="15--ci-validation-commands"></a>
## 15 · CI validation commands

```bash
# ── Prometheus ───────────────────────────────────────────────────
promtool check config prometheus.yml
promtool check rules platform/prometheus/**/*.yaml
promtool test rules ci/promtool-tests/*.yaml
promtool check metrics < <(kubectl exec -n shop deploy/shop-api -- wget -qO- localhost:9090/prometheus)
promtool tsdb analyze /data <block>

# ── Alertmanager ─────────────────────────────────────────────────
amtool check-config alertmanager.yml
amtool config routes --alertmanager.url=http://localhost:9093
amtool config routes test --alertmanager.url=http://localhost:9093 \
  --labels alertname=X severity=critical team=payments --tree

# ── OTel Collector ───────────────────────────────────────────────
docker run --rm -v "$PWD:/cfg" otel/opentelemetry-collector-contrib:0.158.0 --config=/cfg/config.yaml --dry-run
otelcol-contrib validate --config=config.yaml
otelcol-contrib components --config=config.yaml | jq '.receivers, .processors, .exporters'

# ── sloth ────────────────────────────────────────────────────────
sloth generate -i platform/prometheus/slos/ --check-rules
sloth generate -i platform/prometheus/slos/ -o /tmp/out.yaml && promtool check rules /tmp/out.yaml

# ── Grafana ──────────────────────────────────────────────────────
# 1. valid JSON
for f in platform/grafana/dashboards/*.json; do jq empty "$f" || echo "✖ $f"; done
# 2. a UID exists and is unique
for f in platform/grafana/dashboards/*.json; do jq -r '.uid // "⛔ NO UID"' "$f"; done | sort | uniq -d
# 3. the datasource UIDs are ones we provision
jq -r '.. | .datasource?.uid? // empty' platform/grafana/dashboards/*.json | sort -u
# 4. every variable used is declared
# 5. import it into a throwaway Grafana and screenshot it
docker run -d --name gf -p 3001:3000 \
  -v "$PWD/platform/grafana/dashboards:/var/lib/grafana/dashboards" \
  -e GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/99-incident.json \
  grafana/grafana:12.3.1
sleep 20 && curl -sf localhost:3001/api/health

# grafana-dashboard-linter (a real tool)
go install github.com/perses/percli@latest    # or:
pip install grafana-dashboard-linter 2>/dev/null || true

# ── Kubernetes manifests ─────────────────────────────────────────
kubectl apply --dry-run=server -f platform/ -R
kubeconform -strict -summary platform/**/*.yaml
kubeval --strict platform/**/*.yaml
kube-linter lint platform/
helm lint platform/helm/
helm template kps prometheus-community/kube-prometheus-stack -f values.yaml | kubeconform -strict -summary -

# ── YAML ─────────────────────────────────────────────────────────
find platform -name '*.yaml' -exec python3 -c "import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))" {} \;
yamllint -d "{extends: relaxed, rules: {line-length: disable}}" platform/

# ── the end-to-end assertion ─────────────────────────────────────
./scripts/validate-trace-pipeline.sh           # ⭐ 8 checks, see the Capstone Phase 5
./scripts/game-day.sh status
```

**A ready-to-paste GitHub Actions job:**

```yaml
jobs:
  validate-observability:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: install promtool + amtool
        run: |
          V=3.13.2
          curl -sL "https://github.com/prometheus/prometheus/releases/download/v${V}/prometheus-${V}.linux-amd64.tar.gz" | tar xz
          sudo install -m755 "prometheus-${V}.linux-amd64/promtool" /usr/local/bin/
          curl -sL "https://github.com/prometheus/alertmanager/releases/download/v0.28.1/alertmanager-0.28.1.linux-amd64.tar.gz" | tar xz
          sudo install -m755 "alertmanager-0.28.1.linux-amd64/amtool" /usr/local/bin/
      - uses: actions/setup-python@v5
        with: {python-version: "3.13"}
      - run: pip install pyyaml
      - run: promtool check config platform/prometheus/prometheus.yml
      - run: promtool check rules platform/prometheus/recording-rules/*.yaml platform/prometheus/alerting-rules/*.yaml
      - run: promtool test rules ci/promtool-tests/*.yaml          # ⭐⭐ THE GATE
      - run: amtool check-config platform/alertmanager/alertmanager.yaml
      - run: ci/otel-collector-validate.sh
      - run: ci/validate.sh dashboards
      - run: ci/check-conventions.sh && ci/check-ownership.sh
```

---

<a name="16--the-troubleshooting-decision-trees"></a>
## 16 · The troubleshooting decision trees

### 16.1 A Prometheus target is down

```
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health!="up")'
  │
  ├─ lastError = "connection refused"
  │    → the port isn't listening. Check the Service's targetPort and the container's port.
  │    → kubectl exec deploy/x -- wget -qO- localhost:<port>/metrics
  │    → a NetworkPolicy is blocking it. kubectl run netshoot … nc -zv
  │
  ├─ lastError = "no such host" / "server misbehaving"
  │    → DNS. Is the Service name right? Is CoreDNS up?
  │    → kubectl get endpoints -n shop <svc>   ⭐ EMPTY endpoints = a selector mismatch
  │
  ├─ lastError = "context deadline exceeded"
  │    → the scrape is too slow. Compare scrape_duration_seconds to scrape_timeout.
  │    → the response is enormous: curl the endpoint and count the lines
  │    → raise scrape_timeout OR cut the metric count with metricRelabelings
  │
  ├─ lastError = "server returned HTTP status 401/403"
  │    → auth. Check the bearerTokenSecret / basicAuth on the ServiceMonitor.
  │
  ├─ lastError = "x509: certificate signed by unknown authority"
  │    → TLS. Set tlsConfig.insecureSkipVerify or supply the ca.
  │
  ├─ the target isn't in the list at all
  │    → the ServiceMonitor/PodMonitor isn't selected. Compare labels to
  │      .spec.serviceMonitorSelector on the Prometheus CR.
  │    → the ServiceMonitor's namespace isn't in serviceMonitorNamespaceSelector
  │    → the endpoint's `port` NAME doesn't match the Service's port name ⭐ classic
  │
  └─ the target is up but has no metrics
       → the /metrics path is wrong (path: /prometheus for Spring Boot!)
       → the app's management port isn't the one being scraped
```

### 16.2 A dashboard panel says "No data"

```
1. is the query valid?        → paste it into Prometheus /graph directly
2. does it return anything?   → curl -sG localhost:9090/api/v1/query --data-urlencode 'query=…'
3. is the time range wrong?   → the data exists but not in the last 15m
4. is the variable empty?     → Grafana → the panel → Inspect → Query → check the expanded query
5. does the datasource UID match? → jq '.panels[].datasource.uid' dash.json vs /api/datasources
6. is the panel's datasource overridden? → check fieldConfig and target-level datasources
7. NaN?                       → a division by zero. Add clamp_min(). Check with:
                                 curl -sG … 'query=<your expr>' | jq '.data.result[].value[1]'
                                 → "NaN" means the denominator was 0
8. is it a counter without rate()? → a monotonically increasing line, or nothing after a reset
9. did the metric NAME change? → curl -s localhost:9090/api/v1/label/__name__/values | grep …
10. is Prometheus itself down? → curl -s localhost:9090/-/ready
```

### 16.3 An alert isn't firing (but should)

```
1. does the RULE exist?
   curl -s localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.name=="X")'
   → missing: the PrometheusRule isn't selected. Check .spec.ruleSelector.
   → present but health="err": read .lastError ⭐ a typo in the expr disables the whole group

2. does the EXPRESSION return anything right now?
   curl -sG localhost:9090/api/v1/query --data-urlencode 'query=<the expr>' | jq .
   → empty: the expression is wrong, or the data isn't there, or a label doesn't match

3. is it firing in PROMETHEUS?
   curl -s localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="X")'
   → state="pending": still inside the `for:` duration
   → state="firing": it IS firing — the problem is downstream

4. did it reach ALERTMANAGER?
   curl -s localhost:9093/api/v2/alerts | jq '.[].labels'
   → missing: check Prometheus's alertmanager discovery
     curl -s localhost:9090/api/v1/alertmanagers | jq .
   → ⛔ activeAlertmanagers: [] = Prometheus can't find Alertmanager

5. is it SILENCED or INHIBITED?
   curl -s localhost:9093/api/v2/alerts | jq '.[].status'
   → {"state":"suppressed","silencedBy":["abc"],"inhibitedBy":[]}   ⭐ THERE IT IS
   curl -s localhost:9093/api/v2/silences | jq '.[] | {matchers, status, comment, endsAt}'

6. which RECEIVER did it hit?
   amtool config routes test --alertmanager.url=http://localhost:9093 \
     --labels alertname=X severity=critical team=payments --tree

7. did the NOTIFICATION succeed?
   curl -s localhost:9093/metrics | grep -E 'alertmanager_notifications_(total|failed)'
   kubectl logs -n monitoring sts/alertmanager-… --tail=100 | grep -iE 'error|fail|notify'

8. did Prometheus reload the rules?
   curl -s localhost:9090/api/v1/status/config | jq -r '.data.yaml' | grep -c rule_files
   prometheus_config_last_reload_successful   ⭐ must be 1
```

### 16.4 No traces

See [Case 2 §13.1](./03-CASE-2-telemetry.md) for the full 10-cause table. The short version:

```bash
# 1. is the app configured?
kubectl exec -n shop deploy/x -- printenv | grep -i otel
# ⛔ OTEL_SDK_DISABLED=true, OTEL_TRACES_EXPORTER=none, or a missing OTEL_SERVICE_NAME

# 2. is the agent attached? (Java)
kubectl logs -n shop deploy/x | grep -i 'opentelemetry-javaagent - version'

# 3. debug mode
kubectl set env deploy/x -n shop OTEL_JAVAAGENT_DEBUG=true && kubectl rollout restart deploy/x -n shop
kubectl logs -n shop deploy/x --tail=200 | grep -iE 'otel|export|failed'

# 4. can it reach the Collector?
kubectl exec -n shop deploy/x -- wget -qO- --timeout=5 http://otel-collector-agent.otel.svc:13133/

# 5. did the Collector receive it?
curl -s localhost:8888/metrics | grep -E 'otelcol_(receiver_accepted|exporter_sent|processor_dropped)_spans'

# 6. did Tempo store it?
curl -s localhost:3200/api/search/tags | jq .        # ⛔ empty = nothing has ever arrived
curl -s localhost:3200/ready

# 7. send a manual span and trace the whole path (see Case 2 §2.4)
```

### 16.5 The Collector keeps restarting

```bash
kubectl describe pod -n otel -l app=otel-gateway | grep -A6 'Last State'
# Reason: OOMKilled, Exit Code: 137  → memory
# Reason: Error,   Exit Code: 1      → a bad config

kubectl logs -n otel deploy/otel-collector-gateway --previous --tail=200
# "failed to create \"tail_sampling\" processor"     → a config error
# "Memory usage is above hard limit. Dropping data." → memory_limiter is working; raise the limit

# the fixes, in order:
kubectl set env deploy/otel-collector-gateway -n otel GOMEMLIMIT=3500MiB   # ⭐ ~90% of the limit
# lower tail_sampling: num_traces 200000→50000, decision_wait 10s→5s
# raise the memory limit
# add replicas + a loadbalancing exporter upstream (consistent hashing on traceID)
```

### 16.6 Loki isn't showing logs

```bash
curl -s localhost:3100/ready
curl -s localhost:3100/loki/api/v1/labels | jq .              # ⛔ empty = nothing has arrived
curl -sG localhost:3100/loki/api/v1/label/namespace/values | jq .
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=100 | grep -iE 'error|reject|limit'
kubectl logs -n otel ds/otel-logs-agent --tail=100 | grep -iE 'error|reject'

# the usual causes:
# 1. the filelog receiver's `include` path doesn't match (it's /var/log/pods/*/*/*.log)
# 2. the container can't read /var/log/pods (needs the hostPath mount + runAsUser: 0)
# 3. Loki's `auth_enabled: true` but the Collector isn't sending X-Scope-OrgID
# 4. per_stream_rate_limit exceeded → too few streams (a label problem)
# 5. `reject_old_samples_max_age` → the timestamps are being parsed wrong
# 6. the JSON parser's on_error is `send_error` instead of `send` → lines are dropped
```

### 16.7 "Everything looks fine but users are complaining"

**This is Task C3 in the Capstone.** The four blind spots: subsets hidden by aggregation, business outcomes not measured, bimodal distributions hidden by percentiles, and state correctness. Go read it.

---

<a name="17--helm-commands"></a>
## 17 · Helm commands

```bash
# ── repos ────────────────────────────────────────────────────────
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana              https://grafana.github.io/helm-charts
helm repo add open-telemetry       https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add jaegertracing        https://jaegertracing.github.io/helm-charts
helm repo update
helm search repo kube-prometheus-stack --versions | head
helm search repo tempo --versions | head

# ── inspect before you install ⭐ ────────────────────────────────
helm show values prometheus-community/kube-prometheus-stack > values-default.yaml
helm show chart  prometheus-community/kube-prometheus-stack
helm show readme prometheus-community/kube-prometheus-stack | less

# ── install / upgrade ────────────────────────────────────────────
helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f values.yaml --wait --timeout 10m
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring -f values.yaml --atomic --timeout 10m     # ⭐ --atomic rolls back on failure
helm upgrade kps … --reset-values                          # ⭐ ignore the previous release's values
helm upgrade kps … --reuse-values                          # merge with the previous values (careful)
helm upgrade kps … --dry-run --debug                       # ⭐ render without applying
helm upgrade kps … --set prometheus.prometheusSpec.retention=30d
helm upgrade kps … -f values.yaml -f values-prod.yaml      # later files win

# ── inspect a release ────────────────────────────────────────────
helm list -A
helm list -n monitoring -o json | jq .
helm status kps -n monitoring
helm get values kps -n monitoring                          # ⭐ the USER-supplied values
helm get values kps -n monitoring --all                    # the computed values
helm get manifest kps -n monitoring | less                 # ⭐ the rendered YAML
helm get hooks kps -n monitoring
helm get notes kps -n monitoring
helm history kps -n monitoring
helm diff upgrade kps prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml
# ⭐ requires: helm plugin install https://github.com/databus23/helm-diff

# ── roll back ⭐ ─────────────────────────────────────────────────
helm rollback kps 3 -n monitoring                          # to revision 3
helm rollback kps -n monitoring --wait                     # to the previous revision

# ── uninstall ────────────────────────────────────────────────────
helm uninstall kps -n monitoring
helm uninstall kps -n monitoring --keep-history
helm uninstall kps -n monitoring --dry-run
# ⭐ PVCs are NOT deleted. Clean them up:
kubectl delete pvc -n monitoring -l app.kubernetes.io/instance=kps

# ── the kube-prometheus-stack specifics ──────────────────────────
kubectl get secret -n monitoring | grep grafana
kubectl get secret -n monitoring kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d
helm template kps prometheus-community/kube-prometheus-stack -f values.yaml -s templates/prometheus/prometheus.yaml
```

---

<a name="18--interview-quick-fire"></a>
## 18 · Interview quick-fire — 60 questions, 60 answers

**Metrics & Prometheus**

1. **Counter vs gauge?** A counter only increases (resets to 0 on restart) — always `rate()` it. A gauge goes up and down — plot it raw.
2. **Why never plot a raw counter?** It's a monotonically increasing staircase that resets arbitrarily; the value is meaningless, only the *rate* is.
3. **`rate` vs `irate`?** `rate` averages over the whole window (smooth, right for alerts). `irate` uses the last two points (spiky, right for zoomed-in debugging). **Never alert on `irate`.**
4. **Why must the range be ≥ 4× the scrape interval?** `rate` needs at least two samples. At a 30s scrape, `[30s]` often contains one sample → no rate. Use `[$__rate_interval]` in Grafana.
5. **Histogram vs summary?** A histogram ships buckets and lets you compute **any** quantile server-side, and is **aggregatable** across instances. A summary computes quantiles client-side, is cheaper on the wire, but **cannot be aggregated** — `avg()` of p99s is meaningless.
6. **Why is `avg(p99)` wrong?** Percentiles aren't linear. The average of two groups' p99s is not the p99 of the combined group. Always `histogram_quantile(0.99, sum by (le) (rate(...)))`.
7. **What does `histogram_quantile` actually do?** Linear interpolation *within* the bucket that contains the target rank. So the answer is bounded by your bucket boundaries — put a boundary at your SLO.
8. **What is cardinality, and why does it matter?** Every distinct combination of label values is a separate stored time series. Unbounded labels (request_id, user_id, raw paths) explode the series count, which explodes memory, disk and query time.
9. **The cardinality test?** "How many distinct values will this label have in 30 days?" Under 100 is fine; over 10,000 is a bomb.
10. **Where do unbounded values belong?** In **spans and log lines**, which aren't aggregated. An `order_id` is a cardinality bomb as a metric label and a superpower as a span attribute.
11. **`sum by` vs `sum without`?** `by` keeps only the listed labels; `without` keeps everything except them. `by` is safer — you know exactly what you'll get.
12. **`group_left` vs `group_right`?** For a many-to-one join. `group_left` means the LEFT side has many series matching one on the right. You can also copy labels: `group_left(label_team)`.
13. **`absent()` vs `up == 0`?** `up == 0` fires when a configured target is unreachable. `absent(x)` fires when **no series matches at all** — which covers the target being removed from the config, or a metric disappearing.
14. **What is a recording rule, and why use one?** A pre-computed query stored as a new series. Use them for expensive aggregations used in several dashboards/alerts, and for SLO SLIs. Naming: `level:metric:operations`.
15. **What is an exemplar?** A single trace ID attached to a histogram bucket, so you can click a point on a latency graph and land on a real trace. Requires OpenMetrics output and `--enable-feature=exemplar-storage`.
16. **Native histograms?** One series carrying the whole distribution instead of N bucket series. 22 series → 1, with better accuracy. Prometheus 3.x.
17. **How does Prometheus handle a counter reset?** `rate`, `increase` and `irate` detect a decrease and assume a reset, compensating automatically.
18. **Push vs pull?** Pull (scraping) means Prometheus controls the schedule, discovers targets automatically, and knows when something disappears (no scrape = down). Push requires a Pushgateway and loses liveness detection. **Pull is why `up` exists.**
19. **When IS a Pushgateway appropriate?** For short-lived batch jobs that finish before they can be scraped. Never as a general replacement for scraping — the Pushgateway never forgets a series, which is a cardinality leak.
20. **What is the Pushgateway's biggest trap?** Metrics stay forever. A job that ran once leaves a stale series that alerts on it forever. Use `push_time_seconds` and alert on staleness.

**Alerting & SLOs**

21. **Symptom vs cause alerting?** Symptoms measure user impact (error rate, latency, availability) and should page. Causes measure internals (CPU, restarts, pool depth) and should be tickets or diagnostic context. **Paging on CPU trains people to ignore pages.**
22. **What is an SLO?** A target on a measured SLI over a window — "99.9% of checkout requests succeed over a rolling 30 days."
23. **SLI vs SLO vs SLA?** The SLI is the *measurement*, the SLO is the *internal target*, the SLA is the *contract with a penalty*. An SLA is always looser than the SLO.
24. **What is an error budget?** `100% − SLO`. At 99.9% over 30 days that's 43.2 minutes of allowed failure. It's the governor on release velocity: burn it too fast and you freeze deploys; have it left over and you can ship faster.
25. **What is a burn rate?** The rate you're consuming the budget, as a multiple of the allowed rate. 14.4× means you'll exhaust 30 days of budget in 2.08 days.
26. **Why multi-window multi-burn-rate?** A single window either pages too late (long window) or too often (short window). Requiring BOTH a long window (1h) and a short window (5m) to exceed the threshold means the burn is both *significant* and *happening now*.
27. **The four standard burn-rate pairs?** 14.4×/1h+5m (page), 6×/6h+30m (page), 3×/1d+2h (ticket), 1×/3d+6h (ticket).
28. **What should a latency SLI be?** The fraction of requests **under a threshold**, from the histogram bucket: `sum(rate(x_bucket{le="0.3"}[w])) / sum(rate(x_count[w]))`. Exact, no interpolation.
29. **Why is a latency SLO not optional?** A service can be 100% available and completely unusable. The payment-timeout scenario: latency triples, the error rate stays at zero, availability never breaches.
30. **What is `resolve_timeout`?** How long Alertmanager waits after Prometheus stops sending an alert before declaring it resolved. Default 5m.
31. **`group_wait` vs `group_interval` vs `repeat_interval`?** `group_wait` is the initial batching delay before the FIRST notification (30s). `group_interval` is the wait before sending an update about the SAME group (5m). `repeat_interval` is how often to re-send an unresolved alert (4h).
32. **What do inhibit rules do?** Suppress one alert when another is firing, matched on shared labels. "A node is down" should suppress 40 pod alerts. Without them, one node failure pages you 41 times.
33. **What is the Watchdog / dead-man's switch?** An always-firing alert routed to an **external** service that pages you when it *stops* arriving. The only defence against the monitoring platform itself dying.
34. **Why should every alert have a `runbook_url`?** Because an alert at 3 a.m. with no instructions costs 30 extra minutes and a worse decision. Better: put the diagnostic TraceQL/LogQL query in the annotation so it renders in the notification.
35. **How do you test an alert?** `promtool test rules` — feed synthetic series with the `0+1x10` value language and assert on `exp_alerts` at specific `eval_time`s. **Include the false-positive tests**: a 2-minute blip must not page.
36. **What's the worst alerting anti-pattern?** An alert with no `for:` on a spiky metric. Second worst: alerting on a cause with `severity: critical`.
37. **Alert fatigue — how do you fix it?** Count alerts per week per engineer (target <2 actionable pages/night). Delete or downgrade anything not acted on. Merge duplicates with `group_by`. Fix the `for:` durations. Then re-measure.
38. **Can a 402 be an SLO breach?** Usually no — a declined card is correct behaviour, not a system failure. Including it would make a 40% decline rate look like an outage. But it IS a **business-outcome** breach: measure `started → completed`, not HTTP status.

**Dashboards & Grafana**

39. **RED vs USE?** RED is for **requests**: Rate, Errors, Duration — for services. USE is for **resources**: Utilisation, Saturation, Errors — for CPUs, disks, pools. You need both; RED tells you users are hurt, USE tells you why.
40. **The Four Golden Signals?** Latency, traffic, errors, saturation. Google's SRE formulation; RED is the request-oriented subset, USE the resource-oriented subset.
41. **Why does a p99 line hide a bimodal distribution?** A percentile is one number. Two modes (200 ms and 31 s) with 3% in the slow mode produce a p99 that looks mildly elevated. A **heatmap** shows both blobs immediately.
42. **What is `$__rate_interval`?** A Grafana macro = `max($__interval + scrape_interval, 4 × scrape_interval)`. It auto-sizes the rate window to the panel width so zooming out doesn't produce gaps.
43. **Why set the dashboard `uid` explicitly?** Grafana generates one if you don't, and provisioning then creates a duplicate on every reload. Explicit UIDs also let you deep-link (`/d/99-incident`).
44. **Dashboards-as-code — why?** Version control, review, diff, rollback, reproducibility across environments, and no "who deleted the panel?" The Grafana sidecar watches labelled ConfigMaps.
45. **What are Grafana derived fields?** A regex on a log line that turns a captured value (a `trace_id`) into a clickable link to another datasource. **This is the log→trace link.**
46. **What are the three correlation wirings?** Prometheus `exemplarTraceIdDestinations` → Tempo; Tempo `tracesToLogs`/`tracesToMetrics` → Loki/Prometheus; Loki `derivedFields` → Tempo.
47. **What is a Grafana data link?** A per-panel/per-field URL template that lets you click a value and jump anywhere — another dashboard with variables pre-filled, Explore, or an external runbook.

**OpenTelemetry & tracing**

48. **What are the three pillars?** Metrics (aggregates, cheap, for alerting), traces (causal chains, sampled, for diagnosis), logs (discrete events, expensive, for evidence). Each has different retention, cost and cardinality rules.
49. **What is OTLP?** The OpenTelemetry Protocol — gRPC (:4317) or HTTP (:4318), carrying traces, metrics and logs with protobuf. The single wire format that decouples apps from backends.
50. **What is the OTel Collector, and why an agent AND a gateway?** The agent (DaemonSet) receives locally, enriches with k8s metadata, and buffers — so a gateway outage can't take down an app. The gateway is central, replicated, and does the expensive global work (tail sampling) that requires seeing every span of a trace.
51. **Why must `memory_limiter` be first and `batch` last?** `memory_limiter` first so it can refuse data *before* anything else allocates. `batch` last so batching happens after all attribute changes (a batch key changes invalidate batches).
52. **Head vs tail sampling?** Head sampling decides at span creation, cheaply, blind to what happens later (parentbased_traceidratio). Tail sampling buffers the whole trace and decides with full knowledge — so it can keep 100% of errors and slow traces. Tail needs the gateway tier and real memory.
53. **Why does tail sampling need multiple replicas + a load-balancing exporter?** Spans of one trace arrive at different replicas via round-robin, so no replica sees the whole trace. A `loadbalancing` exporter with consistent hashing on traceID routes every span of a trace to the same replica.
54. **What is context propagation?** Carrying the `traceparent` header (`00-<32hex traceid>-<16hex spanid>-<flags>`) across a service boundary. `OTEL_PROPAGATORS` must be **identical** across every language or traces split.
55. **How do you find a propagation bug?** Look for `kind = server` spans with no parent — a server span should almost always have a client-span parent. Also: `traces_service_graph` edges that should exist but don't, and traces with more than one root.
56. **Why a span LINK and not a parent for a message queue?** The consumer may run hours later. Making it a child creates an hours-long span. A link says "this was caused by that" without nesting — the correct async semantic.
57. **What makes a good span name?** Low-cardinality and reusable: the **route template** (`POST /api/orders/{id}`), never the concrete path. High-cardinality values go in **attributes**, which are searchable but don't create new span names.
58. **What is `spanmetrics`?** A Collector connector that generates RED metrics from spans, with exemplars. It gives you metrics for services that expose no `/metrics` endpoint — great for legacy coverage.
59. **The Collector's own metrics you must alert on?** `otelcol_processor_dropped_spans`, `otelcol_processor_refused_spans` (memory_limiter shedding), `otelcol_exporter_send_failed_spans`, `otelcol_exporter_queue_size / capacity`. If the Collector drops telemetry, you have no telemetry to tell you.
60. **Why is the Collector the vendor-abstraction boundary?** Because no app has a vendor SDK. Migrating to Datadog is adding an exporter block and dual-writing for two weeks — not re-instrumenting twelve services in four languages. **It's the single most valuable architectural decision in an observability platform.**

---

## The one-page summary

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  1. THREE SIGNALS, THREE RULES                                              ║
║     metrics = aggregates, cheap, 15-month retention → ALERT on these        ║
║     traces  = causal, sampled, 72-hour retention    → DIAGNOSE with these   ║
║     logs    = discrete, expensive, tiered retention → PROVE with these      ║
║     cardinality: bounded in metrics, unbounded in traces/logs               ║
║                                                                              ║
║  2. THE FOUR TIERS                                                          ║
║     symptom    → PAGE     (users are hurt: SLO burn, blackbox, error ratio) ║
║     saturation → TICKET   (about to hurt: throttling, pools, queue depth)   ║
║     cause      → context  (why: OOMKill, restarts, replicas) — inhibit it   ║
║     self       → PAGE     (we are blind: targets, rules, Collector drops)   ║
║                                                                              ║
║  3. THE QUERIES YOU MUST KNOW BY HEART                                      ║
║     error ratio:   sum(rate(x{status=~"5.."}[5m])) / clamp_min(sum(rate(x[5m])),0.001)
║     p99:           histogram_quantile(0.99, sum by (le) (rate(x_bucket[$__rate_interval])))
║     SLI:           sum(rate(x_bucket{le="0.3"}[5m])) / sum(rate(x_count[5m]))
║     throttling:    rate(throttled_periods[5m]) / rate(cfs_periods[5m])
║     mem vs limit:  working_set / on(ns,pod,container) group_left limits
║     leak:          min_over_time(heap_used[10m])   ← the sawtooth FLOOR
║     disk death:    predict_linear(avail[6h], 4*3600) < 0
║     blind?:        sum(up)/count(up), otelcol_processor_dropped_spans
║                                                                              ║
║  4. THE FOUR-CLICK LOOP (wire this or you have three tools, not a platform) ║
║     Prometheus exemplarTraceIdDestinations → Tempo                          ║
║     Tempo tracesToLogs / tracesToMetrics   → Loki / Prometheus              ║
║     Loki derivedFields (regex on trace_id) → Tempo                          ║
║     metric spike → green diamond → waterfall → "logs for this span" → root  ║
║                                                                              ║
║  5. THE COLLECTOR INVARIANTS                                                ║
║     memory_limiter FIRST · batch LAST · agent + gateway tiers               ║
║     GOMEMLIMIT ≈ 90% of the container limit                                 ║
║     tail sampling ONLY on the gateway, with loadbalancing upstream          ║
║     keep 100% of: errors, 5xx, slow, the money path, the canary             ║
║     OTEL_PROPAGATORS identical in every language, or traces split           ║
║     the Collector is the vendor boundary — no vendor SDK in any app         ║
║                                                                              ║
║  6. THE FIVE THINGS THAT WILL BITE YOU                                      ║
║     a label with unbounded values      → Prometheus OOMs, everything dark   ║
║     a counter plotted without rate()   → a meaningless staircase            ║
║     division without clamp_min         → NaN panels                         ║
║     an alert without `for:`            → pages on every deploy blip         ║
║     an aggregate SLO with no segments  → 41% failure in 3% of traffic, green║
║                                                                              ║
║  7. THE VALIDATION DISCIPLINE                                               ║
║     promtool check rules · promtool test rules (INCLUDING must-NOT-fire)    ║
║     amtool config routes test · otelcol --dry-run · dashboard lint          ║
║     the cardinality budget as a CI gate                                     ║
║     an ephemeral cluster that ASSERTS telemetry flows and alerts route      ║
║     ⭐ the game day: inject 5 failures monthly, score detection time,       ║
║        and re-run it after every cost cut to prove nothing broke            ║
║                                                                              ║
║  8. THE SENTENCE THAT GETS YOU HIRED                                        ║
║     "The most dangerous incident is the one where every dashboard is green: ║
║      a segment-level failure hidden inside an aggregate, a cart cleared on  ║
║      a failed payment, a search returning 200 with zero results. That's why ║
║      I have per-segment SLOs, a business-outcome SLI, and a synthetic       ║
║      journey that asserts post-conditions — none of which any RED dashboard ║
║      would ever show."                                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## Related files

| File | What's in it |
|---|---|
| [README.md](./README.md) | The index and the learning path |
| [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) | The hour-by-hour plan |
| [01-OBSERVABILITY-GUIDE.md](./01-OBSERVABILITY-GUIDE.md) | All the theory |
| [02-CASE-1-prometheus-grafana.md](./02-CASE-1-prometheus-grafana.md) | Metrics, dashboards, alerts |
| [03-CASE-2-telemetry.md](./03-CASE-2-telemetry.md) | Traces, logs, correlation |
| [04-CAPSTONE-END-TO-END.md](./04-CAPSTONE-END-TO-END.md) | The full platform + 5 capstone tasks |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
