# 01 · Monitoring Fundamentals

**Level:** foundational · **Time:** ~1.5 h · **Goal:** be able to walk into any system and know *what* to measure, *why*, and what *not* to measure.

---

## 1. The purpose of monitoring

There are exactly four reasons to collect telemetry. Every dashboard, metric and alert you build should map to one of them:

| Reason | Question it answers | Example |
|---|---|---|
| **Debugging / root cause** | Why did this break? | Error rate spiked after deploy → logs + traces |
| **Alerting** | Does a human need to act now? | SLO burn rate > 14 → page on-call |
| **Trending / capacity** | When will we run out? | Disk growth → 80% in 11 days |
| **Business / product insight** | How are users behaving? | Checkout conversion, requests per tenant |

If a metric serves none of these, it is **cost, not signal**. Deleting metrics is a legitimate engineering activity.

---

## 2. The Three Pillars

| Pillar | Shape | Cost | Best for | Weakness |
|---|---|---|---|---|
| **Metrics** | Aggregated numbers over time (`http_requests_total{status="500"}`) | Low (fixed size per series) | **Alerting**, dashboards, trends, SLOs | Cannot tell you *why* |
| **Logs** | Discrete, timestamped events with arbitrary text | High (grows with traffic) | Root cause, audit, forensics | Terrible for alerting (expensive to aggregate), unbounded cardinality |
| **Traces** | A tree of spans showing one request across services | Medium | Latency attribution, distributed debugging | Sampled → you may miss the failing request; needs instrumentation everywhere |

Plus increasingly: **profiles** (continuous CPU/memory profiling — the fourth pillar) and **events/changes** (deploys, config changes, feature flags — the thing that most often *causes* the other three to move).

> **The correlation trick that makes observability real:** exemplars attach a trace ID to a metric data point, so you can click a latency spike on a Grafana panel and land directly in the trace. See `10-Logging-and-Tracing`.

### Push vs pull

| | **Pull** (Prometheus scrapes `/metrics`) | **Push** (app sends to collector/gateway) |
|---|---|---|
| Target discovery | Centralised — you know what *should* exist, so a missing target is itself an alert (`up == 0`) | You only know what reported in |
| Ephemeral jobs | Bad (job may finish before scrape) → use **Pushgateway** | Natural |
| Network direction | Server → target (needs reachability; awkward across firewalls/NAT) | Target → server (works through NAT, good for agents/laptops) |
| Load control | Collector controls scrape rate | App controls (can flood you) |
| Typical | Prometheus, node_exporter | StatsD, OTLP, CloudWatch agent, Datadog |

Prometheus is pull-first and that is a **design opinion with a big consequence**: *absence of data is a first-class signal*. `up == 0` and `absent()` are among your most valuable alerts.

---

## 3. What to measure: the three classic frameworks

### The Four Golden Signals (Google SRE) — *service-facing, use this by default*

| Signal | Meaning | Example SLI/metric |
|---|---|---|
| **Latency** | Time to serve a request. **Measure successful and failed latency separately** — a fast 500 is not a good user experience. | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` |
| **Traffic** | Demand on the system. | `rate(http_requests_total[5m])`, concurrent streams, IOPS |
| **Errors** | Rate of failed requests — explicit (5xx), implicit (200 but wrong body), policy-based (slower than SLO). | `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])` |
| **Saturation** | How "full" the most constrained resource is, and its **trend**. | CPU utilisation, memory vs limit, queue depth, disk % used, thread pool utilisation |

### RED — *request-driven services (microservices, APIs)*
**R**ate · **E**rrors · **D**uration. It's the Golden Signals specialised per-service, and it is what you should put on every service dashboard.

### USE — *resources (hosts, disks, CPUs, memory, network)*
For every resource: **U**tilisation (busy time %) · **S**aturation (queue/backlog) · **E**rrors (failure count). USE is the checklist that stops you missing a bottleneck — walk every resource, ask all three.

**How to use them together:** RED/Golden Signals at the *service* edge (what users feel), USE on the *resources* underneath (why it happened). Symptom alerts come from the first, cause dashboards from the second.

---

## 4. Levels of monitoring (build bottom-up)

| Layer | What you watch | Typical source |
|---|---|---|
| **Synthetic / external** | "Can a user in Mumbai reach the site?" | blackbox_exporter, Pingdom, CloudWatch Synthetics |
| **Application** | Requests, errors, latency, business events | Your instrumented code, OTel SDK |
| **Runtime / platform** | JVM/Goroutines/GC, container restarts, OOMKills | cAdvisor, kube-state-metrics, runtime exporters |
| **Infrastructure** | CPU, memory, disk, network, clocks | node_exporter, cloud metrics |
| **Dependency** | DB connections, cache hit ratio, third-party API errors | DB exporters, client libraries |
| **The monitoring system itself** | Is Prometheus up? Are scrapes failing? Are alerts being delivered? | Prometheus self-metrics, Alertmanager self-metrics, dead-man's switch |

**The last row is the one everyone forgets.** If the monitoring dies silently, you have no monitoring. Always deploy a **dead-man's switch** (`Watchdog` alert that must *always* be firing; if it stops, an external system pages you).

---

## 5. Alerting philosophy (the part that decides whether you sleep)

The single most important idea in this entire folder:

> **Page a human only when the alert is (a) urgent, (b) actionable, and (c) about a symptom a user would notice.**

Everything else is a dashboard item, a ticket, or a metric that should be deleted.

Consequences:

- **Alert on symptoms, not causes.** "Error budget burning" pages. "CPU at 85%" is a dashboard panel — high CPU with happy users is *success*, not an incident. (Cause alerts are still useful for **tickets** and for **inhibiting** other alerts.)
- **Every page needs a runbook link.** An alert without a documented first action is an alert you haven't finished writing.
- **Alert fatigue is a failure mode with a metric.** If on-call ignores >20% of pages, the system is broken. Review monthly; delete or demote offenders.
- **Every alert must be able to resolve.** An alert that cannot auto-resolve trains people to ignore alerts.
- **Aim for a signal ratio:** a healthy team pages on-call a handful of times per week, not per hour.

Common anti-patterns to recognise on sight:

| Anti-pattern | Why it's bad | Fix |
|---|---|---|
| Alerting on **every** cause | 400 alerts per incident, all noise | One symptom page + a dashboard |
| **Threshold on a raw gauge** (`cpu > 80`) | Flaps, no user impact | Alert on trend/saturation *with* user impact, or `predict_linear` |
| **No `for:` clause** | Fires on a single scrape blip | Add `for:` and check scrape interval |
| Alert on **averages** | Averages hide the tail; 5% of users on 4 s looks fine in the mean | Percentiles from histograms (p95/p99) |
| **Copy-pasted rules** with wrong labels | Alert fires for the wrong team | `promtool test rules` + code review |
| **Duplicate alerts** (Prometheus *and* Grafana alerting) | Two sources of truth, double pages | Pick one. In k8s: Prometheus rules → Alertmanager |
| Alerting on **metrics that don't exist yet** | Silently never fires | `absent()` companion alert + a test |
| **Silences that never expire** | Permanent blind spot | Mandate expiry + comment + owner |

---

## 6. Metric design principles (preview of topic 03)

- Use **histograms**, not summaries, when you need to aggregate across instances.
- Keep **cardinality bounded**: never put user IDs, request IDs, emails, IPs, or unbounded path strings in labels.
- **Name = what it is, unit in the suffix**: `http_request_duration_seconds`, `node_memory_MemAvailable_bytes`. Base units: seconds, bytes, ratio (0–1), total (counters).
- **Labels = dimensions you will slice by**, not metadata.
- `rate()` on counters, never on gauges.

---

## 7. Monitoring maturity model (where are you?)

| Level | Looks like | Gap to close |
|---|---|---|
| 0 — Blind | Users report outages | Get an `up` metric and one external probe |
| 1 — Dashboards | Pretty graphs, alerts by email to a team alias | Add paging, severity, runbooks |
| 2 — Alerting | Symptom alerts page a rotation | Add grouping/inhibition to cut noise |
| 3 — SLO-driven | Error budgets govern alerting and release velocity | Multi-window burn rates |
| 4 — Predictive/automated | Capacity forecasting, auto-remediation, alert reviews as a ritual | Continuous tuning, cost governance |

Most teams are at 1 and believe they are at 3.

---

## Self-check

Answer aloud, no scrolling:

1. Name the Four Golden Signals and give a PromQL sketch for two of them.
2. Why is pull-based collection better at detecting a *dead* target than push?
3. Which pillar would you use to alert on user-facing availability, and which to find the root cause? Why not the other way round?
4. Give three examples of a label that would cause a cardinality explosion.
5. What's the difference between an alert and a notification?
6. Your team gets 60 pages a night. Name four concrete changes you'd make this week.
7. What is a dead-man's switch and why is it non-negotiable?
8. USE vs RED — which applies to a disk, which to a checkout API?

If any answer was shaky, re-read §3–§5, then go to [`02-Prometheus-Core`](../02-Prometheus-Core/README.md).
