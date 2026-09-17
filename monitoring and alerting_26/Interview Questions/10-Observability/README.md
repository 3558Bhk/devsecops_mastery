# 10 · Observability

> 📚 **This topic has a full deep-dive folder** with runnable labs, rule libraries and cheatsheets: [`Monitoring and Alerting/`](../../Monitoring%20and%20Alerting/README.md) — Prometheus, Grafana, Alertmanager, PromQL, SLOs, dashboards, logging, tracing.
> This file is the **interview-oriented** version: the questions, the answers, and the trade-offs you'll be asked to defend.

---

## 🟢 Basic

### 1. Monitoring vs observability — and the honest take
- **Monitoring** answers *predefined* questions: "is CPU above 80%?" You decide in advance what to check; the system tells you when a known condition occurs. **Known unknowns.**
- **Observability** is a property of the system that lets you ask *arbitrary new* questions about its internal state from its external outputs. **Unknown unknowns.** Borrowed from control theory (Kalman): a system is observable if you can infer any internal state from its outputs.

**The three pillars** (plus the increasingly-accepted fourth and fifth):
| Pillar | Answers | Cost profile | Example |
|---|---|---|---|
| **Metrics** | "How much / how often / what rate?" | Cheap, fixed cardinality, aggregable, retained long | p99 latency = 480 ms, error rate 0.4% |
| **Logs** | "What exactly happened?" | Expensive at volume, high detail, discrete events | `NullPointerException at OrderService.java:142` |
| **Traces** | "Where did the time go across services?" | Medium, per-request, shows causality | 380 ms of the 480 ms was in the inventory RPC |
| **Profiles** (4th) | "Which code consumed CPU/memory?" | Continuous profiling, low overhead | 42% of CPU in `json.Marshal` |
| **Events/changes** (5th) | "What changed?" | Deploys, config changes, feature flags, scaling | Deploy `v2.4.1` at 14:02 |

**The honest senior take:** "The three-pillars framing is marketing that hardened into dogma. In practice: **metrics are for detection and alerting** (cheap, aggregable, always on), **traces are for localisation** (which service/span), **logs are for diagnosis** (the specific error), and **change events are the highest-signal correlation data you have** — most incidents are caused by a change, and a dashboard annotated with deploys solves 'what changed?' instantly. I'd add that observability without *actionability* is just expensive data: if you can't get from an alert to a hypothesis in two minutes, more telemetry won't help."

### 2. The Four Golden Signals (Google SRE) — and RED / USE
**Golden Signals** (service-level, user-facing):
| Signal | What | Example metric |
|---|---|---|
| **Latency** | Time to serve a request — **measure success and failure latency separately** (a failed request that returns in 2 ms skews your p50 and hides a problem) | `histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))` |
| **Traffic** | Demand on the system | `sum(rate(http_requests_total[5m]))` |
| **Errors** | Rate of failed requests — explicit (5xx), implicit (200 but wrong content), or policy-based (SLO breach) | `sum(rate(http_requests_total{code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))` |
| **Saturation** | How "full" the constrained resource is — **the leading indicator**, since it predicts failure before latency does | memory utilisation, queue depth, disk %, thread pool occupancy, connection pool wait |

**RED** (Tom Wilkie — request-driven services): **R**ate, **E**rrors, **D**uration. Essentially the golden signals minus saturation; the natural fit for microservices and the standard for per-service dashboards.

**USE** (Brendan Gregg — resources): **U**tilisation, **S**aturation, **E**rrors, applied to *every resource* (CPU, memory, disk, network, locks, queues). Better for infrastructure and for finding the bottleneck resource.

**When to use which — the answer interviewers want:** "**RED for services** (what users experience), **USE for resources** (why), **golden signals when you need the full picture including saturation**. They're complementary, not competing: RED tells you the checkout API is slow; USE tells you the connection pool is saturated at 100% with a growing wait queue. In practice I build every service dashboard with RED + a saturation row, and every node dashboard with USE."

### 3. Push vs pull metrics
| | **Pull** (Prometheus scrapes) | **Push** (StatsD, OTLP push, Pushgateway) |
|---|---|---|
| Target discovery | Service discovery (K8s, Consul, EC2) — automatic | App must know the destination |
| Health signal | **A failed scrape *is* the "target down" signal** (`up == 0`) | Silence is ambiguous: dead app, dead collector, or network? |
| Short-lived jobs | ❌ Bad — may never be scraped | ✅ Good (Pushgateway, OTLP push) |
| Firewalls/NAT | Server must reach the target | Target reaches out (works behind NAT) |
| Load control | Scraper controls rate | App controls rate (can be a self-DoS) |
| Debugging | Easy: `curl` the `/metrics` endpoint yourself | Harder: you can't see what was sent |
| Duplication/scaling | Scrape each replica | Aggregation layer needed |

**Answer:** "Pull for anything long-lived and discoverable — which in Kubernetes is nearly everything, because service discovery is free. Push for batch jobs, lambdas, client-side/browser telemetry, and anything behind NAT. **Pushgateway is explicitly not a general-purpose push mechanism** — it turns push into pull, loses the `up` signal semantics, keeps stale metrics forever unless you delete them, and is a single point of failure. For short-lived jobs, either have the job push to Pushgateway *and* delete its group on completion, or (better) emit a completion metric and alert on absence."

### 4. Cardinality — the thing that actually kills metrics systems
**Cardinality** = the number of distinct time series = the product of the distinct values of every label on a metric.

`http_requests_total{method, status, path, instance, pod, namespace, region, customer_id}` with 4 × 5 × 50 × 20 × 3 × 10 × 3 × **100,000 customers** = **~9 billion series.** That's not a metrics system, that's a database you built by accident.

**High-cardinality label offenders (memorise these):**
- `user_id`, `customer_id`, `session_id`, `request_id`, `trace_id`, `email`
- Raw `path` (with IDs in it: `/users/12345/orders`) — **use route templates** (`/users/:id/orders`) instead
- `ip_address`, `user_agent`, `query_string`, `error_message` (with interpolated values)
- Unbounded enum-ish fields: `pod_name` on autoscaled workloads (each new pod = new series; this is *tolerable* but multiplies), `container_id`, `node_name` in large fleets
- Kubernetes labels/annotations attached wholesale

**Consequences:** memory explosion in Prometheus/TSDB (each series costs ~2–8 KB of RAM plus index), slow queries, scrape timeouts, TSDB head-block churn, query-frontend OOMs, and cost explosion in vendor platforms (Datadog/New Relic charge per custom metric/series — a single bad label can 100× the bill).

**Controls:**
- **`metric_relabel_configs`** to drop or rewrite offending labels at scrape time:
  ```yaml
  metric_relabel_configs:
    - source_labels: [path]
      regex: "/users/[0-9]+/.*"
      target_label: path
      replacement: "/users/:id"
    - action: labeldrop
      regex: "(container_id|pod_ip|request_id)"
  ```
- Application-side: **never** put unbounded values in labels. Use **exemplars** (link a metric point to a specific trace ID) instead of a `trace_id` label — that's exactly what exemplars are for.
- **`prometheus_tsdb_head_series`** as your capacity alarm; per-job series counts via `count by (job) ({__name__=~".+"})`; **`tsdb-status`** page shows top series/metrics.
- Vendor-side: metric allowlists, custom-metric caps, and alerts on custom-metric count growth.

**The distinguishing insight:** "High cardinality isn't always wrong — it's wrong when it's *unbounded* or *unused*. A `customer_id` label on a business metric used for per-tenant SLOs is legitimate and valuable at 10k series. The same label on every HTTP request metric is a disaster. So the rule is: **bounded, intentional, and queried.** I enforce it with scrape-time relabelling and a cardinality budget per team, not with a ban."

### 5. Log levels and structured logging
| Level | Meaning | Alert on? |
|---|---|---|
| **ERROR** | Action failed; something needs attention. **Must be actionable** — if you wouldn't investigate it, it's a WARN | Yes (rate/burst) |
| **WARN** | Unexpected but handled; degraded; approaching a limit | Trend, not page |
| **INFO** | Normal, meaningful state changes: started, stopped, request completed, config reloaded | No |
| **DEBUG** | Diagnostic detail for developers | No (off in prod; enable dynamically) |
| **TRACE** | Per-step, very verbose | No |

**Structured logging (JSON) is non-negotiable at scale:**
```json
{"time":"2026-09-14T10:23:11.482Z","level":"error","msg":"payment failed",
 "service":"checkout","version":"v2.4.1","trace_id":"4bf92f3577b34da6",
 "span_id":"00f067aa0ba902b7","user_id":"u_8821","order_id":"o_5512",
 "provider":"stripe","status_code":502,"duration_ms":1204,"err":"gateway timeout"}
```
Why: **machine-parseable → queryable → aggregatable.** You can compute error rates per provider from logs, build dashboards, and correlate to traces. Unstructured logs (`fmt.Println`) require regex extraction at query time — slow, brittle, and impossible to aggregate reliably.

**Practices:**
- **Correlation IDs / trace context in every log line** (`trace_id`, `span_id`) — this is what joins logs to traces, and it's the single highest-value logging practice. W3C Trace Context propagation makes it automatic with OpenTelemetry.
- **Consistent field names** across services (`service`, `env`, `version`, `trace_id`) — enforced by a shared logging library, not by convention.
- **Log at the boundary**, not everywhere: one structured line per request/response with duration and status, plus errors with context. A log per function call is noise.
- **Don't log secrets/PII** — redact at the library level (allowlist fields, or a redaction filter), and remember logs are often retained longer and accessible to more people than the database.
- **Sampling for high-volume logs** (keep all errors, sample 1% of successful requests).
- **Log volume is a cost and a reliability problem**: a service that logs 10 GB/hour during an incident can fill the node disk (→ DiskPressure → evictions), saturate the collector, and blow the log budget. **Rate-limit and circuit-break logging**, and set `containerLogMaxSize`/`containerLogMaxFiles` in Kubernetes.

### 6. Sampling for traces
| Type | How | Pros | Cons |
|---|---|---|---|
| **Head sampling** | Decide at trace start (e.g. 1 in 100), propagate the decision | Cheap, predictable, consistent whole traces | **You keep 1% of errors too** — the interesting traces are the ones you dropped |
| **Tail sampling** | Buffer the whole trace, then decide based on the completed trace (had an error? was slow? hit a specific endpoint?) | **Keeps 100% of errors and slow traces**, samples the boring ones | Needs a collector with buffering (memory/disk), adds decision latency, harder at scale |
| **Adaptive/probabilistic-per-service** | Rate adjusted per service to hit a target trace rate | Balances cost across services | Complexity |
| **Rate limiting** | Keep up to N traces/sec per service | Cost ceiling | Loses bursts |

**Answer:** "**Tail sampling on errors and latency outliers, head sampling on the rest.** In practice: OpenTelemetry Collector with a `tailsamplingprocessor` policy set — `always sample if status_code = ERROR`, `always sample if latency > 2s`, `sample 5% otherwise`, `always sample if the trace hits the payment service`. That gets you the traces you'll actually look at for a fraction of the storage. The cost is a stateful collector that buffers spans, so it needs its own capacity planning and HA."

---

## 🔵 Advanced

### 7. Prometheus architecture and the query lifecycle
```
                 ┌── Service Discovery (kubernetes_sd, ec2, consul, file_sd)
                 │
Prometheus ──────┤  scrape (pull, HTTP GET /metrics) → parse → relabel → append
   │             │
   ├─ TSDB (local): head block (2h, in-memory + WAL) → compacted 2h blocks → downsampled/long-term
   ├─ Rule manager: recording rules + alerting rules, evaluated every `evaluation_interval`
   └─ HTTP API (/api/v1/query, /query_range) ──► Grafana, Alertmanager (via alerts), clients
                                    │
                              Alertmanager ── group → inhibit → silence → route → notify
```
**Storage model:** each sample is (series identity, timestamp, value). Series identity = `__name__` + all label pairs. Stored in per-block chunks with an inverted index (label → postings list). **This is why cardinality costs memory** (index + head series) and why **query cost is proportional to the number of series touched, not the number of samples returned.**

**Write path:** scrape → WAL (crash recovery) → head block (in-memory, ~2h) → cut to a persistent block → background compaction. **Remote write** streams samples to a long-term store (Thanos Receive, Cortex/Mimir, VictoriaMetrics, InfluxDB).

**Read path for `rate(http_requests_total[5m])`:**
1. Selector matches series (index lookup on label matchers).
2. For each series, read chunks covering `[now-5m, now]` plus lookback.
3. Apply the function.
4. For a range query, repeat at each step.

**Scaling architecture:**
| Need | Solution |
|---|---|
| Long retention / global view | **Thanos** (sidecar → object storage, or Receive for remote-write), **Cortex/Mimir** (multi-tenant, remote-write native), **VictoriaMetrics** (single-binary or cluster, very efficient) |
| High availability | Two identical Prometheus replicas scraping everything (duplicate data; Thanos dedupes on query), or a remote-write HA pair |
| Multi-tenancy | Mimir/Cortex/Thanos Receive with tenant IDs; or one Prometheus per team |
| Federation | Prometheus→Prometheus scraping of *aggregated* metrics only (**not** a scaling solution — it re-scrapes and loses resolution; use remote write instead) |
| Query scaling | Query-frontend (splits+caches range queries), queriers, index gateway |

**The trade-off to name:** "Two HA replicas is the simplest reliable answer and costs 2× storage with no coordination. Thanos/Mimir is the answer when you need global query, downsampling, retention beyond ~2 months, or multi-tenancy — at the cost of running a distributed system (compactor, store gateway, query frontend, object storage) that itself needs monitoring. **I've seen more teams hurt by adopting Thanos prematurely than by not adopting it.** Start with 2 replicas + 15-day retention; move to Mimir/Thanos when retention, tenancy or global-view requirements actually arrive."

### 8. PromQL — the pieces interviewers test
```promql
# Rate over 5m (always rate() on counters, never the raw counter)
rate(http_requests_total[5m])

# Error ratio (0–1) — the classic, and note the > 0 guard for division by zero
sum(rate(http_requests_total{code=~"5.."}[5m]))
  /
sum(rate(http_requests_total[5m])) > 0

# p99 latency from a histogram — sum the buckets FIRST, then quantile
histogram_quantile(0.99,
  sum by (le) (rate(http_request_duration_seconds_bucket[5m])))

# p99 per service (keep the label you want to group by!)
histogram_quantile(0.99,
  sum by (le, service) (rate(http_request_duration_seconds_bucket[5m])))

# Apdex-ish: fraction of requests faster than 300ms
sum(rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))
  / sum(rate(http_request_duration_seconds_count[5m]))

# CPU utilisation from node_exporter
1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))

# Memory pressure: available / total
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Disk full in 4 hours (predict_linear — the best proactive alert you can write)
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 4*3600) < 0

# Is the target up?
up == 0

# Absent metric (detects a missing exporter / a vanished series)
absent(up{job="api"}) == 1

# Increase over a window (for counters where you want counts, not per-second)
increase(http_requests_total[1h])

# Top 5 pods by memory
topk(5, sum by (pod) (container_memory_working_set_bytes))

# Join: per-pod restart rate annotated with namespace label from another metric
rate(kube_pod_container_status_restarts_total[15m]) * on (namespace, pod) group_left
  (kube_pod_info)

# Aggregation over time vs over series — know the difference
avg_over_time(x[1h])     # over time, per series
avg by (job) (x)         # over series, at an instant

# Offset — compare to last week (seasonality-aware alerting)
rate(http_requests_total[5m]) / rate(http_requests_total[5m] offset 7d)
```
**The traps they test:**
- **`rate()` needs a range ≥ 4× the scrape interval** (else extrapolation is unreliable / returns nothing). With a 15s scrape, use ≥ 1m, preferably 2–5m.
- **`irate()`** uses only the last two samples → spiky, good for zooming into a graph, **bad for alerting** (a single gap creates a false spike).
- **Counter resets** are handled by `rate()`/`increase()` automatically (it assumes a decrease = reset). **Gauges** must use `delta()`/`deriv()`, not `rate()`.
- **`histogram_quantile` must be applied to `sum by (le)`** — averaging quantiles is mathematically meaningless, and forgetting `by (le)` returns nothing or garbage.
- **You cannot average percentiles across instances.** `avg(p99 per pod)` ≠ overall p99. Aggregate the *buckets*, then compute the quantile. **This is the most common PromQL error in production dashboards.**
- **`sum without (x)` vs `sum by (x)`** — pick one; `by` is more explicit and safer when labels change.
- **Staleness**: Prometheus marks a series stale 5 minutes after the last sample; a vanished series stops matching (hence `absent()`).
- **`==`, `>`, `<` are filters, not comparisons** — they return the series that satisfy the condition, dropping the rest. That's how `up == 0` works.
- **Vector matching**: `on()`, `ignoring()`, `group_left`, `group_right` for joins between vectors with different label sets. **A join returns nothing if the label sets don't match exactly** — the #1 "why is my query empty" cause.

### 9. Alerting philosophy — what makes alerting good or bad
**The core principle: every page must require intelligent human action.** If no action is needed, it's a dashboard item or a ticket, not a page.

**Symptom-based vs cause-based:**
| | Cause-based | Symptom-based |
|---|---|---|
| Alert on | CPU > 80%, pod restarted, disk 70% | User-facing: error rate, latency, availability, success rate |
| Pros | Early warning, specific | **Directly measures user pain; low false-positive rate** |
| Cons | **Noisy**: high CPU with happy users isn't an incident; every page is a judgement call | Can be late (users already hurt) |
| Verdict | Tickets + dashboards, or pages only when saturation predicts imminent failure | **Pages** |

**The mature answer:** "Page on symptoms — SLO burn rate and user-visible failure. Ticket or dashboard on causes — resource saturation, restarts, certificate expiry in 30 days. The exception is a cause that *predicts* an unavoidable symptom with lead time to act: disk full in 4 hours, connection pool at 95%, queue depth growing monotonically, replication lag. Those earn a page because acting on them prevents the symptom."

**Multi-window multi-burn-rate SLO alerting** (Google SRE Workbook — the standard, and a strong thing to name):
| Severity | Long window | Short window | Burn rate | Budget consumed |
|---|---|---|---|---|
| **Page** | 1h | 5m | 14.4× | 2% in 1 hour |
| **Page** | 6h | 30m | 6× | 5% in 6 hours |
| **Ticket** | 3d | 6h | 1× | 10% in 3 days |
Both windows must breach — the long window establishes that a real budget burn is happening, the short window ensures it's *still* happening (so the alert auto-resolves promptly).

```yaml
- alert: CheckoutAvailabilityFastBurn
  expr: |
    (
      slo:sli_error:ratio_rate5m{job="checkout"} > 14.4 * (1 - 0.999)
      and
      slo:sli_error:ratio_rate1h{job="checkout"} > 14.4 * (1 - 0.999)
    )
  for: 2m
  labels: { severity: page, slo: checkout-availability, window: fast }
  annotations:
    summary: "Checkout burning error budget 14.4× faster than allowed"
    description: "2% of the 30-day budget will be gone within an hour at this rate. Current error ratio: {{ $value | humanizePercentage }}."
    runbook: "https://runbooks.internal/checkout-availability"
```

**Alert quality practices:**
- **Every alert has a runbook link.** An alert without one is a TODO for whoever is paged at 3am.
- **Actionable wording**: not "HighErrorRate firing" but "Checkout error rate 4.2% (>1%) for 10m — 1,240 failed requests. Runbook: …". Include the current value, the threshold, the duration and the impact.
- **Grouping** (Alertmanager `group_by`) so 50 pod alerts become one notification.
- **Inhibition** so a parent failure suppresses child alerts (cluster down → don't also page for 200 pods).
- **Silences** for maintenance windows, created *before* the work.
- **Alert review cadence**: monthly review of pages fired, false-positive rate, MTTR per alert, and **delete or demote any alert that produced no action**. **Alert fatigue is caused by tolerated noise, and the fix is a deletion policy, not better thresholds.**
- **Track the ratio**: pages per on-call shift, % of pages requiring action. A good target is < 2 pages/shift and > 80% actionable.

### 10. Dashboards — what makes one useful
**The hierarchy (and the mistake most teams make):**
1. **Overview / SLO dashboard** (per service): the four golden signals, SLO status, error budget remaining, deploy annotations, dependency health. **This is what you open during an incident.**
2. **Resource dashboards** (per node/cluster): USE method.
3. **Deep-dive / debug dashboards**: per-endpoint, per-tenant, GC, connection pools, cache hit rates, queue depths.

**Principles:**
- **Answer a question, don't display data.** Every panel should have a purpose you could state aloud. A dashboard with 40 panels answers nothing.
- **Top-left = most important.** Eyes go there first, especially at 3am.
- **Consistent time ranges and variable names** across dashboards; template variables (`$service`, `$namespace`, `$pod`) so one dashboard serves all.
- **Show thresholds and SLO targets on the graph** (visual annotations) so "is this bad?" is answerable without a mental lookup.
- **Annotate deploys and changes.** The single highest-value dashboard feature — most incidents are caused by a change.
- **Rate/percentile over raw counters.** Nobody wants to read a monotonically increasing line.
- **Percentiles, not averages.** Average latency hides the tail; **p50/p95/p99 together** show the shape of the distribution (a widening gap = a subset of requests is suffering).
- **Link panels to logs and traces** (Grafana data links with `$trace_id` / derived fields) — the pivot from "something is wrong" to "here is the request" is what makes an investigation fast.
- **Dashboards as code** (JSON in Git, Grafonnet/jsonnet, or Terraform/Crossplane-managed) so they're reviewed, versioned, reproducible, and don't rot.
- **Accessibility**: colour-blind-safe palettes (don't encode meaning in red/green alone), units on every axis, no rainbow gradients.

**The test to state:** "A good dashboard lets someone who's never seen the service answer 'is it broken, how badly, since when, and what changed?' in under 30 seconds. If a new on-call engineer can't do that, the dashboard is documentation-shaped, not operational."

### 11. OpenTelemetry — why it won, and what it actually is
**The problem it solved:** vendor lock-in and duplicated instrumentation. You instrumented with Jaeger for traces, Prometheus for metrics, Fluentd for logs — three SDKs, three propagation formats, three exporters, and switching vendors meant re-instrumenting everything.

**What OTel is:** a CNCF **standard + SDK + Collector** for telemetry.
- **Specification** and semantic conventions (standard attribute names: `http.request.method`, `service.name`, `k8s.pod.name`) — **this is the most underrated part**, because consistent attribute names are what make cross-service queries possible.
- **APIs and SDKs** per language for traces, metrics, and logs.
- **OTLP** — one wire protocol for all three signals.
- **Collector** — a vendor-agnostic pipeline: **receivers** (OTLP, Prometheus, Jaeger, Zipkin, syslog, filelog) → **processors** (batch, memory-limit, tail-sampling, attributes, resource detection, redaction, transform/OTTL) → **exporters** (Prometheus remote-write, Jaeger, Tempo, Datadog, Loki, S3, Kafka).

**Relationship to Prometheus — the nuanced answer:** "They're converging, not competing. OTel exports Prometheus-compatible metrics (Prometheus receiver scrapes; Prometheus exporter/remote-write exports), and Prometheus 3.x added native **OTLP ingest** and **exemplars**. In practice: OTel is the instrumentation layer and the pipeline; Prometheus (or Mimir/VictoriaMetrics) is the metrics store and query engine; Tempo/Jaeger is the trace store. **The Prometheus data model and PromQL won the metrics war; OTel won the instrumentation war.** Saying that precisely is better than claiming one replaces the other."

**Adoption gotchas worth naming:**
- OTel metrics are newer and less battle-tested than traces; some backends still lack full support.
- **Auto-instrumentation** (Java agent, Python sitecustomize, eBPF-based) is great for coverage but produces generic, high-cardinality telemetry and can't capture business semantics. **Use auto for the baseline, manual for what matters.**
- Collector deployment topology: **agent (DaemonSet/sidecar) → gateway (Deployment)** is the standard two-tier pattern; the gateway does tail sampling, redaction and batching centrally. A sidecar-only setup makes tail sampling impossible (each sidecar sees only its pod's traces).
- Semantic conventions changed names over time (`http.method` → `http.request.method`) — pin SDK versions and expect migration work.

### 12. SLI / SLO / SLA — get the definitions exact
| Term | Definition |
|---|---|
| **SLI** (Indicator) | A **measured** quantity representing service quality. Must be a ratio of good events to total events, ideally. e.g. `successful_requests / total_requests` |
| **SLO** (Objective) | An **internal target** on the SLI. e.g. "99.9% of requests succeed over a rolling 30 days" |
| **SLA** (Agreement) | A **contractual promise with financial/legal consequences**. Always **looser than the SLO** — if your SLO is 99.9%, your SLA might be 99.5%. |
| **Error budget** | `1 - SLO` — the amount of unreliability you're *allowed*. 99.9% over 30 days = **43.2 minutes** |

**Choosing an SLI — the four types:**
| Type | Measures | Example |
|---|---|---|
| **Availability** | Is it up? | `up`, health-check success |
| **Quality** | Is the response correct/complete? | Non-5xx ratio, non-degraded responses |
| **Latency** | Is it fast enough? | Fraction of requests < 300 ms (**better than p99 for SLOs** — it's a ratio, so it composes and it's directly comparable to an error budget) |
| **Freshness/Coverage/Correctness/Throughput/Durability** | Data-specific | Data age < 5 min; % of records processed |

**Where to measure:** as close to the user as possible. Client-side/RUM is truth; server-side is convenient; **synthetic probes** fill the gap when you have no client telemetry. Measuring behind your load balancer hides DNS, TLS and CDN failures — which are real user-facing outages.

**The nines table (memorise the downtime):**
| SLO | Downtime/year | Downtime/30 days | Budget/min per 30d |
|---|---|---|---|
| 99% | 3.65 days | 7.2 h | 432 |
| 99.5% | 1.83 days | 3.6 h | 216 |
| 99.9% | 8.76 h | 43.2 min | 43.2 |
| 99.95% | 4.38 h | 21.6 min | 21.6 |
| 99.99% | 52.6 min | 4.32 min | 4.32 |
| 99.999% | 5.26 min | 26.3 s | 0.44 |

**Senior points on SLOs:**
- **Every 9 costs roughly 10× more** (redundancy, multi-AZ → multi-region, testing, on-call). 99.99% needs automated failover you've actually tested; 99.999% needs multi-region active-active and a team whose job is reliability. **Ask "what does the user actually perceive?"** — a mobile app with offline caching may be fine at 99.5%; a payment API may need 99.99%.
- **The error budget is a governance tool, not just a number.** Budget exhausted → **freeze feature work, fix reliability.** Budget plentiful → ship faster, run game days, take risks. **This is the mechanism that ends the speed-vs-reliability argument** — it converts a values conflict into a data-driven policy. Saying this is worth more than any PromQL.
- **Dependent-service SLOs must be tighter than yours.** If your SLO is 99.9% and you call three services serially each at 99.9%, your composed availability is ~99.7% — you cannot meet your SLO. Either tighten their SLOs, add redundancy/retries/fallbacks, or lower your promise. **Doing this arithmetic in the interview is a strong signal.**
- **SLOs need an owner, a review cadence, and a willingness to be changed.** An SLO nobody looks at is decoration. Review monthly with the actual burn data.
- **Don't SLO everything.** 3–5 SLOs per critical service. An SLO per endpoint per method is unmanageable.

### 13. Logging/tracing pipeline architecture at scale
```
App ──stdout──► Container runtime ──► Node collector (DaemonSet: Vector/Fluent Bit/Promtail/OTel agent)
                                          │  parse, enrich (k8s metadata), filter, sample, redact
                                          ▼
                                   Gateway/aggregator (OTel Collector, Vector, Kafka for buffering)
                                          │  route by type
                        ┌─────────────────┼──────────────────┐
                        ▼                 ▼                  ▼
                  Loki / ES / OS      Tempo / Jaeger     Prometheus (metrics from logs)
                        │                 │
                        └──── Grafana ────┘  (correlated via trace_id)
```
**Design decisions:**
- **Logs to stdout, always.** Let the platform collect them. Writing to files inside containers means sidecars, rotation, and lost logs on crash. (Exception: audit logs with strict durability needs.)
- **Buffer with Kafka** between collection and storage when volume is high or the backend is slow — decouples spikes, allows replay, enables multiple consumers (search, analytics, ML, archival). Adds operational cost; worth it above ~1 TB/day or when the backend has hard ingest limits.
- **Enrich at the edge** with Kubernetes metadata (namespace, pod, labels, node) — the app shouldn't have to know its own pod name.
- **Filter and sample at the edge** — dropping debug logs at the node saves 80% of the cost before it's ever shipped. **The cheapest log is the one you never emit.**
- **Redact at the edge** (PII, tokens) — cheaper and safer than redacting downstream, and it means the sensitive data never lands in a system with broader access.
- **Loki vs Elasticsearch/OpenSearch — the trade-off to state:** Loki indexes **labels only, not log content** → dramatically cheaper storage (object storage, compressed chunks) and fast for "give me all logs for pod X in the last hour", but **slow for full-text search across all logs** (it's brute-force grep over chunks). ES/OpenSearch indexes everything → fast arbitrary search, high cost, and a cluster that needs real operational care. **Rule: Loki if you query by known labels and accept grep-speed for ad-hoc text search; ES/OpenSearch if full-text search across all logs is a primary use case (security, support, compliance).**
- **Retention tiering**: hot (7 days, fast storage, full query) → warm (30 days) → cold/archive (1–7 years, object storage, for compliance). Most logs are never queried after 48 hours; **retention policy should reflect that, not be uniform.**
- **Cost control**: per-namespace/tenant ingest quotas, log-volume dashboards (find the top 10 noisiest services — usually 80% of the cost), drop rules for known-useless high-volume logs (health-check access logs!), and **alert on log volume anomalies** (a 10× jump is often the incident itself).

### 14. Continuous profiling — the fourth pillar
Always-on, low-overhead CPU/memory profiling in production (Parca, Pyroscope/Grafana Phlare, Datadog Continuous Profiler, Google Cloud Profiler, `pprof` endpoints).

**What it answers that nothing else does:** "**Why** is this service using 3 cores?" Metrics say CPU is high; traces say which span is slow; **profiles say which function is burning the CPU.** Common findings: a regex evaluated per request, JSON serialisation of a huge object, an accidental N+1, a lock held too long, GC pressure from allocation churn.

**Overhead:** typically 1–3% CPU for sampling profilers (they sample stacks at ~10–100 Hz rather than instrumenting every call). Low enough to leave on permanently in production — which is the point: **you can't profile an incident that already ended**, and reproducing load in staging rarely matches production.

**The killer feature: diff profiles.** Compare CPU profile during the incident vs baseline → the difference *is* the regression. And **correlate with a deploy**: "what code changed behaviour at 14:02?"

**Mention it as the maturity marker:** "Teams add metrics, logs and traces and stop. Profiling is the fourth pillar and it's the one that answers cost and performance questions — it's how you find that 30% of your cloud bill is one inefficient serialisation path. With eBPF-based profilers you can even do it without instrumenting the application."

---

## 🔴 Scenario

### 15. "Latency spiked from 100ms to 2s. Walk me through the investigation."
**A structured answer beats a lucky guess. Narrate the method:**

**Minute 0–1: Scope.** *Is it actually a problem, and how big?*
- Which service, which endpoint, which percentile? **p99 only, or p50 too?**
  - **p50 up** = everything is slower → a shared dependency, saturation, or a code regression affecting all requests.
  - **p99 up, p50 flat** = a *subset* of requests suffers → one slow downstream, a hot key, GC pauses, lock contention, one bad pod/node/AZ, or large-payload requests.
  - **This distinction halves the search space immediately. Say it out loud.**
- What percentage of traffic? All users or one tenant/region/client?
- Since exactly when? **Check the deploy/change annotations first** — a spike that starts at 14:02 with a deploy at 14:01 is solved.

**Minute 1–3: Correlate with change.**
- Deploys, config changes, feature flags, infra changes, migrations, autoscaling events, certificate rotations, dependency version bumps, traffic changes (a marketing campaign, a crawler, a retry storm).
- **"What changed?" is the highest-yield question in incident response** — most incidents are caused by a change, and the change log is either annotated on the dashboard or it isn't (and if it isn't, that's a post-incident action item).

**Minute 3–6: Localise — which layer?**
Walk the request path top-down and find where time is spent:
```
Client → DNS → CDN/LB → Ingress → Service → App → Cache → DB → 3rd-party
```
- **Traces** are the fastest tool here: open a slow trace and see which span consumes the time. One span at 1.8s = localised. Spans all slightly slower = systemic (GC, CPU throttling, saturation).
- If no traces: compare **per-hop latency metrics** (ingress vs app vs DB), and check whether the app's own measured duration matches what the client sees (a gap = queueing, LB, TLS, network).
- **Queueing is the most-overlooked cause:** app processing time is 100 ms but client-observed latency is 2 s → requests are waiting (thread pool exhausted, connection pool exhausted, CPU throttled, kernel accept queue overflowing). Check pool saturation metrics, `container_cpu_cfs_throttled_*`, and load average vs cores.

**Minute 6–10: The usual suspects, ranked by frequency**
1. **A dependency got slow** (database, cache, third-party API). Check its latency and saturation. **A slow DB shows up as slow app latency** — and the app's own CPU/heap look normal, which is why people miss it.
2. **Saturation** — CPU throttling, memory pressure/GC, connection pool exhaustion, thread pool exhaustion, disk I/O saturation, network bandwidth, conntrack table full.
3. **A bad deploy** — a regression: N+1 queries, a removed cache, a synchronous call added to a hot path, a lock, a serialisation change, a log statement in a loop.
4. **GC pauses / runtime issues** — JVM full GCs, Go allocation churn, Python GC. Check GC pause histograms and frequency.
5. **Lock contention / single hot resource** — one mutex, one hot DB row, one cache key, one partition. Look for a single instance/partition being slow while others are fine.
6. **Traffic change** — a spike, a retry storm (a failing client retrying aggressively amplifies load 10×), a crawler, a batch job, a thundering herd after a cache flush or a mass key expiry.
7. **One bad pod / node / AZ** — check per-instance latency distribution. If p99 is driven by *one* pod, that's the answer: `kubectl get pods -o wide`, node health, noisy neighbour. **Restart it, then investigate the corpse.**
8. **DNS resolution issues** — the `ndots:5` amplification, CoreDNS saturation, conntrack UDP races → 5s timeouts. **A latency spike to exactly ~5s or ~5.0x seconds is a DNS timeout signature.** Recognising that pattern is a strong signal.
9. **TLS** — cert renewal storms, handshake overhead after session-cache loss, an expired intermediate causing revalidation.
10. **Clock skew / NTP** — rarer, but produces bizarre metric artefacts.

**Minute 10+: Mitigate, then root-cause.**
- **Mitigate first** if users are affected: roll back the deploy, restart the bad pod, scale out, shed load, fail over, increase the pool size, disable the feature flag, throttle the offending client.
- **Preserve evidence before restarting**: capture a thread dump / heap dump / profile / `pprof` / `kubectl top` / trace samples. **A restart destroys the crime scene** — and if you don't capture it, you'll be back next week.
- Then root-cause properly, write it up blamelessly, and add the detection that would have caught it earlier (an alert, a dashboard panel, a trace, a test).

**The framing that scores:** "I work in three phases — **scope** (how bad, who, since when), **correlate** (what changed), **localise** (which layer, via traces or per-hop metrics) — and only then hypothesise. The two questions that resolve most incidents in under five minutes are 'what percentile and what proportion?' and 'what changed at that timestamp?' Jumping straight to hypotheses is how you spend an hour restarting things."

### 16. "Design the observability for a new microservice. What do you instrument?"
**A checklist you can recite, then justify:**

**1. Define the SLOs before instrumenting.** "What does 'healthy' mean for this service, from the user's perspective?" → availability SLI (non-5xx ratio), latency SLI (fraction < 300 ms), and possibly correctness/freshness. **Instrument to measure the SLO first.** Everything else is diagnosis.

**2. Request-level metrics (RED) with the right labels:**
```
http_server_request_duration_seconds  (histogram)  {service, version, method, route, status_code}
http_server_requests_total            (counter)    {service, version, method, route, status_code}
```
- **Use the route template, not the raw path** (cardinality).
- **Separate server-side and client-side** metrics: `http_server_*` (what I serve) and `http_client_*` (what I call) — the gap between them is network + queueing.
- **Histograms, not summaries**, if you aggregate across instances (summaries can't be re-aggregated; **a client-side computed p99 summary is a dead end**).
- Sensible buckets (default Prometheus buckets are poor for a 300 ms SLO — use native/exponential histograms or tuned buckets like `0.005,0.01,0.025,0.05,0.1,0.25,0.5,1,2.5,5,10`).

**3. Dependency (client-side) metrics:** per downstream — request count, error count, latency histogram, **and pool state** (connections in use, idle, wait queue length, wait time). Pool saturation is the leading indicator of latency and it's almost never instrumented.

**4. Saturation / resource metrics:** in-flight requests, queue depth and **oldest item age**, thread/goroutine count, GC pauses and heap, open file descriptors, connection counts, memory working set. **`oldest_queue_item_age` is the best saturation SLI** — depth alone hides a stuck queue.

**5. Business/domain metrics:** the thing that makes this service valuable — orders created, payments processed, files ingested, records synced, jobs completed/failed. **These catch "the service is technically healthy but doing nothing"**, which is a real and common outage class (e.g. a consumer connected but not committing).

**6. Logs:** structured JSON, one line per request at the boundary (with duration, status, route, tenant), errors with full context and stack, **`trace_id`/`span_id` in every line**, level appropriate (ERROR only for actionable), sampled for high-volume success paths, secrets redacted.

**7. Traces:** propagate W3C `traceparent` across every outbound call (HTTP, gRPC, queue produce/consume, DB); spans for each dependency call with meaningful attributes (`db.system`, `db.statement` **without** literal values, `http.route`, `peer.service`); **record exceptions on the span**; sample tail-based on error/latency. **Instrument the queue hop** — producer span linked to consumer span — otherwise your trace dies at the broker, which is the most common tracing gap.

**8. Health endpoints:**
- `/livez` — process alive and not deadlocked. **No dependency checks.**
- `/readyz` — can serve traffic; may check critical dependencies (but carefully: a dependency blip shouldn't remove every pod from rotation → cascade).
- `/healthz`/`/metrics`/`/debug/pprof` as appropriate.
- **Three separate endpoints, and knowing why they differ is the test.**

**9. Change visibility:** version label on every metric (`version`, `commit_sha`), deploy annotations into Grafana, feature-flag state queryable.

**10. Dashboards + alerts as part of the definition of done:**
- Service dashboard: SLO status + error budget, RED, saturation, dependency health, deploy annotations, links to logs/traces.
- Alerts: SLO burn-rate (fast/slow), target-down, saturation-predicting alerts (disk full in 4h, pool >90%), business-metric-absent alert (`absent()` — the "it stopped doing anything" detector).
- **Runbooks linked from every alert.**

**11. Cost/cardinality discipline:** a label budget, no unbounded labels, exemplars instead of `trace_id` labels, log volume estimated before launch, retention agreed.

**The closing statement:** "I instrument to answer three questions in order: **is it broken** (SLO), **where** (traces + per-hop metrics + dependency metrics), **why** (logs + profiles + resource metrics). Teams usually do the first badly and the third not at all. And I make observability part of the definition of done — a service without an SLO, a dashboard and a runbook isn't finished, it's just deployed."

### 17. "Our Datadog bill tripled. Find the cause and fix it."
**Diagnose — where is the money going?**
Vendor bills split into: **custom metrics (per series/metric)**, **ingested log GB**, **APM/ingested spans**, **host/container count**, **synthetic tests**, **RUM sessions**, **retention**. Get the usage breakdown first — guessing is expensive.

**The usual culprits, in order of how often they cause a 3× jump:**
1. **Custom metric cardinality explosion.** One new label (`user_id`, `request_id`, `pod_name` on a suddenly-autoscaling workload, a `path` with IDs) multiplies every series. **This is the most common cause of a tripled bill and it's usually invisible until the invoice arrives.** Detect: usage API / metric inventory sorted by series count; look for a step change correlated with a deploy date.
2. **A new service or team onboarded without limits.** 40 new services × default instrumentation × 50 metrics × 20 hosts.
3. **Log volume**: a service started logging at DEBUG in production; a health-check endpoint's access logs are being shipped (these can be 50% of all logs and are worth nothing); an error loop printing a stack trace per request; a retry storm. Detect: per-service/per-index ingest volume, top-N by volume.
4. **APM spans**: sampling raised from 1% to 100%; a chatty service emitting 200 spans per request; traces retained at high resolution.
5. **Retention increased** (30 → 90 days) across all indexes — multiplies stored volume.
6. **Host/container churn**: an autoscaling workload creating and destroying hundreds of containers per day, each billed as a host for the month (a genuinely surprising billing rule). Fix: bill-aware autoscaling, or a metric of container-churn.
7. **Duplicate telemetry**: two agents collecting the same thing (OTel Collector *and* the vendor agent), or metrics scraped from both Prometheus and the vendor's integration.
8. **A migration** — someone flipped from Prometheus self-hosted to the vendor, so the "new" cost is really the cost that was previously hidden in engineering time and infrastructure. Worth saying: **sometimes the bill tripled because it became visible, and that's not necessarily bad.**

**Fix — in priority order:**
1. **Kill the cardinality problem at the source.** Fix the offending label in code; add **ingest-side filtering** (vendor metric allowlists / relabel rules / OTel Collector `filter` + `attributes` processors) so it can't recur; set a per-team custom-metric budget with an alert at 80%.
2. **Filter logs at the edge**, not at the vendor: drop debug, drop health-check access logs, drop known-noisy useless lines — in the DaemonSet collector, before shipping. **This is usually a 40–70% cut for near-zero loss of value.**
3. **Tier retention**: 7 days hot/searchable, 30 days warm, 1 year cold in object storage (or drop entirely where compliance allows). Most logs are never queried after 48 hours.
4. **Sample traces properly**: tail sampling keeping 100% of errors and slow traces, 1–5% of the rest.
5. **Route by value**: not everything belongs in the expensive system. High-volume, low-value logs → Loki/object storage/self-hosted; high-value, query-heavy → the vendor. **Hybrid is the normal end state.**
6. **Governance**: per-team cost dashboards (showback), a monthly review of top-N cost drivers, ingest quotas in the pipeline, and **an alert on cost/usage anomaly** — you want to know on day 2, not on invoice day.
7. **Negotiate/commit** once usage is stable: reserved commitments cut unit cost significantly — but only *after* fixing waste, or you lock in the waste.
8. **Ask what the telemetry is *for*.** The cheapest log is the one nobody reads. Delete dashboards nobody opens, metrics nobody queries (usage APIs can tell you), and alerts nobody acts on. **A 30% reduction in telemetry with no loss of signal is normal.**

**The strategic framing:** "I treat observability spend like any other cloud spend: attribute it to teams, set budgets, alert on anomalies, and review monthly. The failure mode isn't spending money — it's spending it on data nobody queries while the data that would have solved the incident was dropped for cost. So the fix is always *targeting*, not just reduction. And I'd measure success as cost per unit of value: cost per service, and — more honestly — 'did the last 5 incidents get diagnosed faster?'"

### 18. "We have no observability. Build a strategy from zero for a 30-service platform."
**Don't boil the ocean. Sequence by value per unit of effort.**

**Phase 0 — Foundations (week 1–2)**
- **Decide the stack and standardise it**: Prometheus + Grafana + Alertmanager + Loki + Tempo (self-hosted, cheap, no per-series billing), or a vendor (fast, expensive, less work). **Pick one, and pick it for the team's operational capacity, not its features.** A stack nobody can run is worth zero.
- **Naming and labelling conventions**: `service`, `env`, `version`, `team`, `k8s.namespace` on everything. Standard metric names (OTel semantic conventions). **Do this first — retrofitting consistent labels across 30 services is the painful part, and it's what makes cross-service queries possible.**
- **A shared instrumentation library** per language so teams get RED metrics, trace propagation, structured logging and health endpoints by importing one package. **This is the highest-leverage thing you can build** — it turns 30 individual efforts into one.

**Phase 1 — Know if it's broken (week 2–6)**
- Instrument **all 30 services** with the baseline library: RED metrics, `/livez` + `/readyz`, structured JSON logs to stdout, W3C trace propagation.
- Deploy **node/host metrics** (node_exporter) and **Kubernetes metrics** (kube-state-metrics, cAdvisor) — you need the platform layer before the app layer makes sense.
- **Log collection** via a DaemonSet (Vector/Fluent Bit) → Loki, with edge filtering.
- **Deploy annotations** into Grafana from CI. Cheap, and immediately useful.
- One **standard service dashboard** template (variables for service/namespace) applied to all — not 30 hand-built dashboards.
- Alert on: **target down**, **error rate**, **latency**, **restart/CrashLoop**, **node NotReady**, **certificate expiry**, **disk will fill**. Keep it to ~10 alerts cluster-wide initially. **Fewer, better alerts beat 200 noisy ones — you can always add.**

**Phase 2 — Make it actionable (month 2–3)**
- **Define SLOs for the 5–8 critical user journeys** (not all 30 services) and switch alerting to **burn-rate**. Retire the noisy threshold alerts they replace.
- **Tracing** with tail sampling: OTel Collector (agent DaemonSet + gateway Deployment) → Tempo/Jaeger. Prioritise instrumenting the **queue hops and DB calls** — those are where traces are most valuable and most often missing.
- **Distributed trace → log correlation** (`trace_id` in logs, Grafana data links). **This single link transforms investigations.**
- **Runbooks for every alert**, owned by the team that owns the service.
- **On-call rotation** with paging policy, escalation, and a handover ritual.
- **Incident process**: severities, roles (incident commander, comms lead, scribe), a channel template, and blameless post-incident reviews with tracked action items.

**Phase 3 — Depth and maturity (month 3–6)**
- **Continuous profiling** (Parca/Pyroscope) — answers cost and "why is this slow" questions.
- **Business metrics** and per-tenant SLOs.
- **Capacity and saturation forecasting** (`predict_linear`, queue-age alerts).
- **Chaos/game days** to validate that alerts actually fire and dashboards actually help. **Untested observability is unverified.**
- **Cost/cardinality governance**: budgets, ingest filtering, usage dashboards, retention tiers.
- **eBPF-based telemetry** (Cilium Hubble, OTel auto-instrumentation) for services you can't modify.

**Phase 4 — Continuous improvement (ongoing)**
- **Instrument new services by policy**: the service template includes observability; a service without an SLO, dashboard, alerts and runbook cannot be deployed (enforced by admission policy). **This is how you stop the backlog regrowing.**
- **Monthly alert review**: pages fired, % actionable, delete/demote the rest.
- **Measure the outcomes, not the outputs**: MTTD, MTTR, % incidents found by monitoring vs reported by users, change failure rate, alert-to-action ratio. **"% of incidents detected by monitoring before a customer reported it" is the metric that convinces leadership to fund this.**

**The framing that lands:** "I'd sequence by *time-to-value*, not by completeness: baseline instrumentation everywhere first (so you can see anything), then SLOs on the few journeys that matter (so alerts are meaningful), then traces and correlation (so investigations are fast), then profiling and governance (so it's efficient and sustainable). And I'd make observability part of the service template from day one, because retrofitting 30 services twice is how these programmes die. The measure of success isn't 'we have Grafana' — it's 'we find out before our customers do'."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "Average latency is 120ms" | Averages hide the tail; use percentiles |
| Averaging p99s across instances | Mathematically meaningless; aggregate buckets then compute the quantile |
| `histogram_quantile` without `sum by (le)` | Wrong or empty results |
| `irate()` in an alerting rule | False spikes from single gaps |
| `rate()` with a range < 4× scrape interval | Unreliable extrapolation |
| `user_id` / raw `path` / `trace_id` as a metric label | Cardinality explosion → OOM or a 5× bill |
| Alerting on CPU > 80% as a page | Cause-based noise; page on symptoms |
| An alert with no runbook | 3am guessing |
| One dashboard with 40 panels | Answers nothing |
| No deploy annotations | "What changed?" takes 30 minutes |
| SLA tighter than SLO | You're contractually promising more than you target |
| SLO on a service whose dependencies are looser | Arithmetically impossible to meet |
| Logging secrets/PII at INFO | Compliance incident |
| Unbounded log volume, no edge filtering | Node disk pressure + a bill surprise |
| `/healthz` that queries the database and is used for liveness | Mass restarts on a dependency blip |
| Pushgateway as a general push mechanism | Loses `up` semantics, stale metrics forever |
| Federation as a scaling strategy | Loses resolution, re-scrapes; use remote write |
| Adopting Thanos/Mimir before you need it | You now operate a distributed system |
| Traces that stop at the message broker | The most common tracing gap |
| Restarting the pod before capturing a profile/dump | The crime scene is gone |

## Rapid recall

1. Metrics = detection, traces = localisation, logs = diagnosis, profiles = why, change events = correlation.
2. Golden signals: latency (success *and* failure separately), traffic, errors, **saturation** (the leading indicator). RED for services, USE for resources.
3. Pull for long-lived/discoverable; push for short-lived/NAT. A failed scrape *is* the down signal.
4. Cardinality = product of label values. Unbounded labels kill TSDBs and bills. Use route templates, exemplars, scrape-time relabelling, per-team budgets.
5. Structured JSON logs + `trace_id` in every line + redaction + edge filtering.
6. Tail-sample traces: 100% of errors and slow, a few % of the rest.
7. `rate()` needs ≥ 4× scrape interval; counters reset-aware; gauges use `delta()`; `absent()` catches vanished series; `predict_linear()` for proactive alerts.
8. Page on symptoms (SLO burn rate, multi-window multi-burn-rate), ticket on causes — except causes that predict symptoms with lead time.
9. Every alert: actionable wording, current value, threshold, duration, impact, **runbook link**. Delete alerts that produced no action.
10. Dashboards: answer "broken? how badly? since when? what changed?" in 30 seconds. Deploy annotations. Dashboards as code.
11. OTel = instrumentation standard + semantic conventions + Collector pipeline. Prometheus won the metrics data model; OTel won instrumentation.
12. SLI = measured ratio; SLO = internal target; SLA = contract, **looser than the SLO**. Error budget = 1 − SLO, and it's the **governance mechanism** that ends the speed-vs-reliability argument.
13. Composed availability: serial dependencies multiply. Your SLO can't be tighter than your dependencies'.
14. Loki indexes labels (cheap, grep-speed text search); ES/OpenSearch indexes content (fast search, expensive). Buffer with Kafka above ~1 TB/day. Tier retention.
15. Investigation order: **scope (which percentile, what proportion) → correlate (what changed) → localise (traces/per-hop) → hypothesise**. Mitigate first, preserve evidence before restarting.
16. Zero-to-hero sequencing: shared instrumentation library + label conventions first, baseline everywhere, SLOs on the few critical journeys, traces + log correlation, profiling, then governance — and bake it into the service template so the backlog doesn't regrow.

→ Next: [`11-SRE-and-Reliability`](../11-SRE-and-Reliability/README.md)
