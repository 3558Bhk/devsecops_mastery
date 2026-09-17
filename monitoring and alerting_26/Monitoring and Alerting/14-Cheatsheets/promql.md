# Cheatsheet · PromQL

## Types

| Type | Example | Graphable? |
|---|---|---|
| Instant vector | `up` | ✅ |
| Range vector | `up[5m]` | ❌ — must pass through a function |
| Scalar | `time()` | ✅ |
| String | `"x"` | ❌ |

## Selectors

```promql
metric_name
{__name__="metric_name"}
{__name__=~"api_.*"}
{"http.server.request.duration"}      # UTF-8 name (Prometheus 3)
metric{label="v"}        # =   exact
metric{label!="v"}       # !=
metric{label=~"a|b"}     # =~  regex (fully anchored: implicit ^...$)
metric{label!~"a.*"}     # !~
metric[5m]               # range window  (must be >= 2x scrape_interval)
metric[5m] offset 1d     # time-shifted
metric[5m] @ 1726294800  # pinned evaluation time; @ start() / @ end()
```
Prometheus 3 range selectors are **left-open, right-closed**: `(t-d, t]`.

## Operators

```
+  -  *  /  %  ^
==  !=  >  <  >=  <=        # comparison FILTERS by default
expr < bool 0.1             # returns 0/1 for ALL series instead of filtering
and   or   unless           # set ops on instant vectors
```

**Vector matching**
```promql
a / ignoring(label) b
a / on(label1, label2) b
a / ignoring(code) group_left(extra_label) b    # many-to-one, keep left's labels
a / on(version) group_right(revision) b         # one-to-many from the right
```

## Aggregation

```
sum  min  max  avg  count  group  stddev  stdvar
topk(k, v)  bottomk(k, v)  quantile(q, v)  count_values("name", v)
limitk(k, v)  limit_ratio(r, v)
```
```promql
sum by (job) (expr)          # keep ONLY these labels  (preferred)
sum without (instance) (expr) # keep everything EXCEPT these
```
**Order rule:** `sum(rate(x[5m]))` ✅ · `rate(sum(x)[5m])` ❌ (counter resets across instances wreck it).

## Functions

### Counters
| Function | Meaning |
|---|---|
| `rate(v[d])` | per-second average, handles resets — **default for everything** |
| `irate(v[d])` | per-second from last 2 samples — spiky graphs, **never alerts** |
| `increase(v[d])` | extrapolated count over the window |
| `resets(v[d])` | number of counter resets (≈ restarts) |
| `changes(v[d])` | number of value changes (state flips) |

### Gauges
`delta(v[d])` · `idelta(v[d])` · `deriv(v[d])` · `predict_linear(v[d], t)`

### Over-time (any series)
`avg_over_time` `min_over_time` `max_over_time` `sum_over_time` `count_over_time` `quantile_over_time(q, v[d])` `last_over_time` `present_over_time` `absent_over_time` `stddev_over_time` `stdvar_over_time` `mad_over_time` (3.5+)

### Latency
```promql
histogram_quantile(0.99, sum by (le) (rate(x_bucket[5m])))
histogram_quantile(0.99, sum by (le, job) (rate(x_bucket[5m])))
rate(x_sum[5m]) / rate(x_count[5m])                       # exact mean
sum(rate(x_bucket{le="0.25"}[5m])) / sum(rate(x_count[5m])) # fraction under 250ms
```

### Existence
```promql
absent(v)              # 1 if the instant vector is EMPTY
absent_over_time(v[d]) # 1 if no samples in the window
vector(1)              # constant 1 (used by Watchdog)
```

### Labels
```promql
label_replace(v, "dst", "$1", "src", "(.*):.*")
label_join(v, "dst", "-", "src1", "src2")
```

### Time & maths
`time()` `timestamp(v)` `hour()` `minute()` `day_of_week()` `day_of_month()` `days_in_month()` `month()` `year()` — all UTC unless given a tz: `hour("Asia/Kolkata")`

`abs` `ceil` `floor` `round` `exp` `ln` `log2` `log10` `sqrt` `sgn` `clamp` `clamp_min` `clamp_max` `deg` `rad` `sin` `cos` `tan` `asin` `acos` `atan` `sinh` `cosh` `tanh` `sort` `sort_desc` `scalar` `vector` `pi()`

### Smoothing (Prometheus 3.5+)
`double_exponential_smoothing(v[d], alpha, beta)` · `anchored_vwap(v[d])`

## Subqueries

```promql
max_over_time(rate(x[5m])[1h:1m])
```
Expensive. Prefer a recording rule for the inner expression.

## The 25 essential queries

```promql
up == 0
avg_over_time(up[5m])
count(up == 1) by (job) / count(up) by (job)

sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
sum by (job) (rate(http_requests_total{status=~"5.."}[5m])) / sum by (job) (rate(http_requests_total[5m]))
sum(increase(http_requests_total{status=~"5.."}[1h]))

histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.99, sum by (le, job) (rate(http_request_duration_seconds_bucket[5m])))
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

sum(rate(http_requests_total[5m]))
sum(increase(http_requests_total[1h]))
topk(5, sum by (path) (rate(http_requests_total[5m])))

1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
node_load5 / count by (instance) (node_cpu_seconds_total{mode="idle"})
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes
predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0
rate(node_network_receive_bytes_total[5m]) * 8

kube_pod_status_phase{phase="Pending"} == 1
increase(kube_pod_container_status_restarts_total[15m]) > 3
kube_deployment_status_replicas_available / kube_deployment_status_replicas < 0.9

absent(up{job="payments"})
time() - backup_last_success_timestamp_seconds > 7200
topk(10, count by (__name__)({__name__=~".+"}))
```

## Grafana-specific variables

| Variable | Value |
|---|---|
| `$__rate_interval` | `max(4 × scrape interval, $__interval)` — **use this in every `rate()`** |
| `$__interval` | range / max data points, floored by Min step |
| `$__range` | full selected time range (e.g. `6h`) |
| `$__from` / `$__to` | epoch ms bounds |
| `$__interval_ms` | interval in milliseconds |
| `${var_name}` | dashboard variable |
| `$__field.labels.x` | current series' label (data links) |

## Debugging flow

```
1. Run the bare metric name.        Empty? → data problem, not query problem.
2. Add rate()/the inner function.   Empty? → range window < 2x scrape interval.
3. Add sum by (...).                Empty? → grouping label doesn't exist on the series.
4. Add the division / and.          Empty? → label sets don't match → use on()/ignoring()/group_left.
5. NaN?                             → 0/0, or histogram_quantile on an empty/+Inf-only bucket set.
6. Duplicate lines in Grafana?      → a label you didn't aggregate away (instance, pod).
7. Values look wrong by ~1e-17?     → rate() extrapolation. Normal. Don't "fix" it.
```

## Performance rules

- Always include a metric name; never `{__name__=~".+"}` in panels/rules.
- `sum by (...)` early to shrink the working set.
- Recording rules for anything repeated or expensive.
- `--query.timeout`, `--query.max-concurrency`, `--query.max-samples` (default 50M) protect the server.
- Grafana: `Min step` = scrape interval; `$__rate_interval` in every rate.
- Diagnose with `--query.log-file` and `prometheus_engine_query_duration_seconds`.
