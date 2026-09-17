# 04 · PromQL  ★ deep dive

**Level:** core · **Time:** ~4 h + daily practice · **Goal:** read, write and *debug* PromQL fluently — this is the language of Prometheus, Grafana panels and every alert rule you will ever write.

> PromQL is the single highest-leverage skill in this folder. Everything else is configuration; this is thinking.

---

## 1. The type system (4 types — know these cold)

| Type | What it is | Example |
|---|---|---|
| **Instant vector** | A set of series, each with **one** sample "now" | `http_requests_total` |
| **Range vector** | A set of series, each with a **window** of samples | `http_requests_total[5m]` |
| **Scalar** | A single float | `2.5`, `time()` |
| **String** | A quoted literal (rarely used) | `"foo"` |

Everything in PromQL is about converting between these. **Range vectors cannot be graphed or returned directly** — you must apply a function (`rate`, `avg_over_time`, …) to turn them back into an instant vector. That single rule explains most "parse error" confusion.

```promql
http_requests_total                 # instant vector  ✅ graphable
http_requests_total[5m]             # range vector    ❌ not graphable
rate(http_requests_total[5m])       # instant vector  ✅ graphable
```

---

## 2. Selectors, matchers, offsets

```promql
# Metric name is itself a matcher on __name__
http_requests_total
{__name__="http_requests_total"}                       # identical
{__name__=~"http_.*_total"}                            # regex on names
{"http.server.request.duration_seconds"}               # UTF-8 name (Prometheus 3)

# Matchers:  =   !=   =~   !~
http_requests_total{job="api", status=~"5.."}
http_requests_total{status!~"2..|3.."}
http_requests_total{namespace="prod", pod!~".*canary.*"}
http_requests_total{path=~"/api/v[12]/.*"}             # regex is FULLY ANCHORED (implicit ^...$)

# Offset — compare to the past
rate(http_requests_total[5m] offset 1d)                # same query yesterday
http_requests_total offset 1w

# @ modifier — pin evaluation time
rate(http_requests_total[5m] @ 1726294800)
rate(http_requests_total[5m] @ start())                # value at the start of the range
```

**Range window sizing — the rule that prevents empty graphs:**

> The range must be at least **2× the scrape interval** (ideally 4×) or you'll get gaps because a single missed scrape empties the window.

Scrape interval 15 s → minimum useful range is `[1m]`; `[5m]` is the standard default. Scrape interval 60 s → use `[5m]` minimum.

Prometheus 3 note: range selections are **left-open, right-closed** `(t-d, t]`, so a window contains samples strictly after `t-d` and up to `t`.

**Staleness:** when a target disappears or a series stops being exported, Prometheus marks it stale after ~5 minutes (or immediately on target loss since 2.x). Series don't linger forever — but they do linger for up to 5 minutes, which is why `absent()` alerts use a `for:`.

---

## 3. Operators

### Arithmetic & comparison
`+ - * / % ^`

Comparison: `== != > < >= <=`, with optional **`bool`** modifier to return 0/1 instead of filtering:

```promql
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.1   # returns only series below 10%
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < bool 0.1   # returns 1 or 0 for all series
```
> **This is the #1 alerting gotcha.** In an alert rule, a comparison *without* `bool` filters — the alert fires only for series that satisfy it (usually what you want). With `bool`, it never filters — everything is returned as 0/1, and you must then compare (`== 1`). Mixing them up produces alerts that never fire or always fire.

### Logical/set operators (instant vectors only)
| Operator | Meaning |
|---|---|
| `and` | LHS series that **have a match** on RHS (keeps LHS values) |
| `or` | LHS series, plus RHS series that had **no match** in LHS |
| `unless` | LHS series that have **no match** on RHS |

```promql
# Fire only if the SLO is burning AND traffic is non-trivial
(slo:burn_rate > 14) and (sum(rate(http_requests_total[5m])) > 10)

# Alert on pods that are not ready, unless they're being deleted
(kube_pod_status_ready{condition="false"} == 0)
  unless on(namespace, pod) (kube_pod_deletion_timestamp > 0)
```

### Vector matching (when label sets differ)

Binary ops match series **one-to-one on identical label sets**. When they differ you must tell PromQL how:

```promql
# ignoring / on  — choose which labels define the match
rate(errors_total[5m]) / ignoring(status) group_left rate(requests_total[5m])

# group_left / group_right — one-to-many (the "many" side supplies extra labels)
method_code:http_errors:rate5m
  / ignoring(code) group_left sum by (method) (method:http_requests:rate5m)

# Attach build info as labels to another metric
api_requests_total * on(version) group_left(revision) api_build_info
```
Mnemonic: `group_left` = "the left side is the many side, keep its labels and copy from the right".

---

## 4. Aggregation operators

`sum` `min` `max` `avg` `group` `stddev` `stdvar` `count` `count_values` `bottomk` `topk` `quantile` `limitk` `limit_ratio`

```promql
sum(rate(http_requests_total[5m]))                          # total QPS
sum by (job) (rate(http_requests_total[5m]))                # per job
sum without (instance, pod) (rate(http_requests_total[5m])) # everything except these
count(count by (pod) (up))                                  # number of pods
topk(3, sum by (namespace) (container_memory_working_set_bytes))
count_values("version", node_exporter_build_info)           # histogram of label values
quantile(0.95, sum by (instance) (rate(errors_total[5m])))  # ⚠️ quantile of *rates*, not of latencies
limitk(5, sum by (tenant) (requests_total))                 # deterministic subset (Prometheus 3.x)
```

**Critical ordering rule:**

> **Aggregate first, then apply `rate`-derived math — but always `rate()` before `sum()`.**
> `sum(rate(x[5m]))` ✅ — sums per-series rates.
> `rate(sum(x)[5m])` ❌ — sums counters from different instances, so every pod restart looks like a negative reset and wrecks the result.

For latency percentiles it's the reverse order of operations but the same principle:
```promql
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
```
`rate` per bucket series → `sum by (le)` across instances → `histogram_quantile` last.

`by` vs `without`:
```promql
sum by (job, instance) (x)     # keep ONLY these labels
sum without (instance) (x)     # keep everything EXCEPT this
```
Prefer `by` — it's explicit and safe when new labels appear.

---

## 5. Functions you'll use weekly

### Rate family (counters only)

| Function | Behaviour | Use for |
|---|---|---|
| `rate(v[d])` | Per-second average over the window, **handles counter resets** | Almost everything: alerting, dashboards |
| `irate(v[d])` | Per-second rate from the **last two samples** only | Spiky, volatile graphs. **Never in alerts** (too noisy). Range still ≥2× scrape interval |
| `increase(v[d])` | `rate × window seconds` — extrapolated count over the window | "How many errors in the last hour" |
| `delta(v[d])` | Difference for **gauges** | Temperature, disk used |
| `idelta(v[d])` | Last-two-sample delta for gauges | Rare |
| `deriv(v[d])` | Least-squares slope for gauges | Trend lines |

```promql
increase(http_requests_total{status=~"5.."}[1h])     # errors in the last hour
rate(node_network_receive_bytes_total[5m]) * 8       # bits/sec
```
`increase()` **extrapolates** — you can see `4.98` for a window where exactly 5 events happened. That's expected, not a bug. To force integers, round, or use `changes()` for state flips.

### Over-time aggregators (any series)

```promql
avg_over_time(cpu_usage[1h])
min_over_time(node_memory_MemAvailable_bytes[15m])
max_over_time(container_memory_working_set_bytes[1d])
sum_over_time(events[1h])
count_over_time(up[1h])                     # how many samples existed → detects flapping
quantile_over_time(0.95, latency_gauge[1h])
last_over_time(x[1h])                       # most recent sample in the window
present_over_time(x[1h])                    # 1 if any sample exists → good for "did it report?"
stddev_over_time(x[1h])
```
> **Anti-pattern:** `avg_over_time(rate(x[5m])[1h:1m])` — a subquery. Works, but expensive; prefer a **recording rule** that stores `rate(x[5m])` and average that.

### Latency & histograms

```promql
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.99, sum by (le, job) (rate(http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.5,  sum by (le) (rate(http_request_duration_seconds_bucket[5m] offset 1d)))

# Mean latency (exact, from sum/count)
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# Apdex-style: fraction of requests under 250ms
sum(rate(http_request_duration_seconds_bucket{le="0.25"}[5m]))
  / sum(rate(http_request_duration_seconds_count[5m]))

# Native histograms (Prometheus 3, --enable-feature=native-histograms)
histogram_quantile(0.99, sum(rate(http_request_duration_seconds[5m])))
```

**Why `histogram_quantile` is an estimate:** it interpolates *linearly within a bucket*. If all your requests fall in the `(10s, +Inf]` bucket, the result is `NaN`/`+Inf` — you learn nothing. Fix the buckets, not the query.

### Predicting the future

```promql
# Disk full in how many seconds? (4h trend, linear)
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[4h], 4*3600) < 0

# Growth rate per second
deriv(node_filesystem_avail_bytes[1h])
```
`predict_linear` does least-squares linear regression — perfect for "will fill in N hours" alerts, useless for spiky or seasonal data.

### Label manipulation

```promql
label_replace(up, "host", "$1", "instance", "(.*):.*")        # instance="10.0.0.1:9100" → host="10.0.0.1"
label_join(up, "combo", "-", "job", "instance")               # concatenate labels
```
Both operate per-sample at query time and are relatively expensive. Prefer doing this in `relabel_configs` at scrape time.

### Absence, existence, resets, changes

```promql
absent(up{job="api"})                    # 1 if the vector is EMPTY (metric/target gone)
absent_over_time(up{job="api"}[5m])      # 1 if no samples in the window
count(changes(kube_pod_status_phase[1h])) # how many state flips
resets(http_requests_total[1h])          # number of counter resets (restarts!) in the window
```
`absent()` is how you alert on **"the metric I depend on stopped existing"** — essential, because an alert on a missing series can never fire by itself.

### Time & math helpers

`time()` (current unix seconds) · `timestamp(v)` (sample's timestamp) · `hour()/minute()/day_of_week()/day_of_month()/days_in_month()/month()/year()` (UTC, or with a timezone argument: `hour("Asia/Kolkata")`) · `round()/floor()/ceil()/abs()/exp()/ln()/log2()/log10()/sqrt()/sgn()/clamp()/clamp_min()/clamp_max()/deg()/rad()/acos()/acosh()/asin()/atan()/cos()/sin()/tan()/vector()/scalar()/sort()/sort_desc()/sgn()`

```promql
time() - backup_last_success_timestamp_seconds > 7200    # backup older than 2h
clamp_min(rate(x[5m]), 0)                                # avoid divide-by-zero blowups
```

### Smoothing (Prometheus 3.5+)

```promql
double_exponential_smoothing(rate(x[5m]), 0.3, 0.3)   # Holt linear trend smoothing
anchored_vwap(x[1h])                                  # anchored volume-weighted average
```
Useful for de-noising alerting inputs; still niche.

---

## 6. Subqueries

`<instant vector expression>[<range>:<step>]` — evaluate an expression over time.

```promql
max_over_time(rate(http_requests_total[5m])[1h:1m])     # peak 5m-rate over the last hour
avg_over_time(histogram_quantile(0.99, sum by (le)(rate(lat_bucket[5m])))[30m:1m])
```
**Cost warning:** a subquery is a *query inside a query*, evaluated at every step. On a wide series set this is the most common cause of a Prometheus CPU spike. Prefer a **recording rule** that materialises the inner expression, then aggregate the rule's output.

---

## 7. The 25 queries you should be able to write from memory

```promql
# ---- Availability -------------------------------------------------------
up == 0
avg_over_time(up[5m])                                          # 1 = always up, 0.98 = flapping
count(up == 1) by (job) / count(up) by (job)                   # % of targets healthy

# ---- Error rate ---------------------------------------------------------
sum(rate(http_requests_total{status=~"5.."}[5m]))
  / sum(rate(http_requests_total[5m]))                         # global 5xx ratio
sum by (job) (rate(http_requests_total{status=~"5.."}[5m]))
  / sum by (job) (rate(http_requests_total[5m]))

# ---- Latency ------------------------------------------------------------
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.99, sum by (le, job) (rate(http_request_duration_seconds_bucket[5m])))
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# ---- Traffic ------------------------------------------------------------
sum(rate(http_requests_total[5m]))                             # QPS
sum(increase(http_requests_total[1h]))                         # requests last hour
topk(5, sum by (path) (rate(http_requests_total[5m])))         # hottest endpoints

# ---- Saturation / resources --------------------------------------------
1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))   # CPU utilisation
node_load1 / count by (instance) (node_cpu_seconds_total{mode="idle"})  # normalised load
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)       # memory used %
(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes
predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0            # disk full within 24h
rate(node_network_receive_bytes_total[5m]) * 8                          # inbound bits/s
container_memory_working_set_bytes / on(pod) kube_pod_container_resource_limits_memory_bytes

# ---- Kubernetes ---------------------------------------------------------
kube_pod_status_phase{phase="Pending"} == 1
increase(kube_pod_container_status_restarts_total[15m]) > 3
kube_deployment_status_replicas_available / kube_deployment_status_replicas < 0.9
sum by (node) (kube_pod_container_resource_requests_cpu_cores) / sum by (node) (kube_node_status_capacity_cpu_cores)

# ---- Meta / debugging ---------------------------------------------------
absent(up{job="payments"})
count by (__name__)({__name__=~".+"}) > 1000                   # cardinality offenders
prometheus_rule_evaluation_duration_seconds
scrape_duration_seconds
```

---

## 8. Performance: how to write PromQL that doesn't hurt

| Rule | Why |
|---|---|
| Put the **most selective matcher first** and always include a metric name | `{__name__=~".+"}` scans the entire TSDB — never do this in a panel or rule |
| Use `sum by (...)` to **shrink early** | Fewer series downstream = less work |
| **Prefer recording rules** over repeated expensive queries | Compute once per evaluation interval, read cheaply many times |
| Avoid **subqueries** on wide series | Nested evaluation multiplies cost |
| Avoid `irate` in **alerts** | Volatile → flapping; fine for graphs |
| Keep **range windows tight** but ≥ 2× scrape interval | Wider = more samples scanned |
| Set Grafana panel **Min step** = scrape interval | Stops Grafana asking for 1 s resolution over 30 days |
| Watch `prometheus_engine_query_duration_seconds` and the **query log** | `--query.log-file` shows the actual cost of every query |
| Limit concurrency: `--query.max-concurrency`, `--query.timeout`, `--query.max-samples` (default 50M) | Protects the server from one bad dashboard |

```promql
# ❌ Expensive: scans everything
count({__name__=~".+"}) by (job)

# ✅ Cheap: named metric
count(up) by (job)
```

---

## 9. Debugging PromQL like a professional

1. **Start from the metric, not the expression.** Run `up`, `http_requests_total` alone. If empty, you have a data problem, not a query problem.
2. **Peel one layer at a time** and check the series count at each step:
   ```promql
   http_requests_total                                    # how many series?
   rate(http_requests_total[5m])                          # did rate empty it? (window too small)
   sum by (job) (rate(http_requests_total[5m]))           # did the grouping key exist?
   sum by (job)(rate(x[5m])) / sum by (job)(rate(y[5m]))  # did vector matching fail? (empty result)
   ```
3. **Empty result on a division or `and`** ⇒ label sets don't match. Use `on(...)`/`ignoring(...)`, or check for an extra label like `pod`/`container`.
4. **`NaN`** ⇒ 0/0, or `histogram_quantile` on an empty/`+Inf`-only bucket set.
5. **Duplicated lines in Grafana** ⇒ a label you didn't group away (`instance`, `pod`).
6. **Use the Prometheus 3 UI's query tree view** (PromLens-style) — it explains exactly which node produced what.
7. **Test through the API** to remove Grafana from the equation:
   ```bash
   curl -sG localhost:9090/api/v1/query --data-urlencode 'query=sum(rate(http_requests_total[5m]))' | jq
   ```
8. **Write it as a `promtool test rules` unit test** so it can't silently break later.

### Unit-testing rules (do this in CI)

`tests/error_rate_test.yaml`:
```yaml
rule_files:
  - ../rules/api.yaml

evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      - series: 'http_requests_total{job="api",status="200"}'
        values: '0+100x60'          # +100 per minute for 60 minutes
      - series: 'http_requests_total{job="api",status="500"}'
        values: '0+0x20 0+50x40'    # clean for 20m, then 50/min
    alert_rule_test:
      - eval_time: 30m
        alertname: HighErrorRate
        exp_alerts:
          - exp_labels: {job: api, severity: page}
            exp_annotations:
              summary: "Error rate 33% for job api"
    promql_expr_test:
      - expr: job:http_requests:rate5m{job="api"}
        eval_time: 30m
        exp_samples:
          - labels: 'job:http_requests:rate5m{job="api"}'
            value: 2.5
```
```bash
promtool test rules tests/error_rate_test.yaml
```
Value syntax cheatsheet: `0+100x60` = start 0, add 100 each step, 60 steps · `0 5 10 20` = explicit values · `_` = gap (no sample) · `stale` = staleness marker · `0+1x10 _ 0+1x10` = series disappears then returns.

---

## 10. Quick reference card

| Need | Expression |
|---|---|
| Per-second rate | `rate(counter[5m])` |
| Count in window | `increase(counter[1h])` |
| Gauge change | `delta(gauge[1h])` |
| P99 latency | `histogram_quantile(0.99, sum by (le) (rate(hist_bucket[5m])))` |
| Mean latency | `rate(hist_sum[5m]) / rate(hist_count[5m])` |
| Error ratio | `sum(rate(err[5m])) / sum(rate(all[5m]))` |
| CPU % | `1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))` |
| Disk full ETA | `predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0` |
| Missing metric | `absent(up{job="x"})` |
| Flapping | `avg_over_time(up[30m]) < 1` |
| Restarts | `increase(kube_pod_container_status_restarts_total[15m]) > 3` |
| Top N | `topk(5, sum by (x) (rate(y[5m])))` |
| Ratio as 0/1 | `expr < bool 0.1` |
| Yesterday | `expr offset 1d` |
| Join info metric | `metric * on(label) group_left(extra) info_metric` |

---

## Self-check

Write the query, then verify it in the lab:

1. Global p99 request latency across all instances of the `api` job.
2. Percentage of requests returning 5xx, per namespace, over 10 minutes.
3. Alert expression for "disk will be full within 6 hours".
4. "Was this job up at all during the last 30 minutes?" (a value between 0 and 1)
5. Detect that a required metric has stopped being exported.
6. Mean request duration without using a histogram.
7. Why does `rate(sum(x)[5m])` give wrong answers, and what do you write instead?
8. What does `< bool` change in an alert rule?
9. When would you use `irate`, and why never in an alert?
10. Your division returns an empty vector — list three causes.

→ Next: [`05-Alerting-Concepts-and-Best-Practices`](../05-Alerting-Concepts-and-Best-Practices/README.md)
