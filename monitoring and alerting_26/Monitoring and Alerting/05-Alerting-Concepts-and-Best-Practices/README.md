# 05 · Alerting Concepts & Best Practices  ★ deep dive

**Level:** core · **Time:** ~4 h + Lab 4 · **Goal:** write alert rules that page the right person at the right time, and never again ship an alert you can't explain.

---

## 1. The alerting pipeline end to end

```
   metrics ──► Prometheus rule manager ──► alert states ──► Alertmanager ──► notification ──► human
                (evaluation_interval)      PENDING→FIRING     group/route        Slack/PagerDuty
                                           →RESOLVED          inhibit/silence    + runbook link
```

| Stage | Owned by | Configured in | Failure mode |
|---|---|---|---|
| Evaluate expression | Prometheus | `rules/*.yaml` → `expr` | Wrong query, missing metric |
| Decide "is it firing" | Prometheus | `expr` + `for` + labels | Flapping, never fires |
| Attach context | Prometheus | `labels`, `annotations` | No severity, no runbook |
| Group / dedupe / route | Alertmanager | `route`, `receivers` | Wrong team, alert storm |
| Suppress noise | Alertmanager | `inhibit_rules`, `time_intervals`, silences | Over-suppression → blind spots |
| Deliver | Alertmanager | notifier configs | Silent delivery failure |
| Act | Human | Runbook | Page with no next step |

**Every stage is a separate place to get it wrong, and you must be able to say which stage broke.** "The alert didn't fire" is not a diagnosis.

---

## 2. Alert lifecycle and states

```
              expr becomes true
   INACTIVE ────────────────────► PENDING ────── for: elapsed ──────► FIRING
      ▲                              │                                    │
      │                              │ expr false                         │ expr false
      └──────────────────────────────┴────────────────────────────────────┘
                                   (→ RESOLVED notification)
```

- **`for:`** is a *hysteresis* timer. The expression must be **continuously** true for that duration. If it flickers false once, the timer resets.
- `for: 0m` (or omitted) = fire on the very first evaluation. Only correct for instant, unambiguous conditions (e.g. `up == 0` with a long scrape interval, or a dead-man's switch).
- **`keep_firing_for:`** (Prometheus 2.42+) — the inverse: stay firing for at least this long after the expression goes false. Prevents flapping resolution notifications during a rolling recovery.

```yaml
- alert: HighErrorRate
  expr: job:http_error_ratio:rate5m > 0.05
  for: 10m
  keep_firing_for: 5m          # don't resolve on the first good minute
  labels: {severity: page}
  annotations:
    summary: "Error rate {{ $value | humanizePercentage }} on {{ $labels.job }}"
```

### How to size `for:`
| Condition | `for:` |
|---|---|
| Target completely down (`up == 0`) | 2–5 m (≥ 3 scrape intervals) |
| Error rate / latency SLO burn | 2–15 m (the burn-rate windows already provide smoothing) |
| Disk filling (`predict_linear`) | 15–30 m (avoid transient fs noise) |
| Cert expiry | hours — it changes slowly |
| Crashloop / OOMKilled | 5–10 m |
| Dead-man's switch | 5–10 m |
| Business KPI | 15–60 m |

**Never** use `for:` shorter than your `evaluation_interval`, and never shorter than 2–3 scrape intervals, or you're alerting on sampling noise.

---

## 3. Symptom vs cause alerting (the central doctrine)

| | **Symptom alert** | **Cause alert** |
|---|---|---|
| Measures | What the **user** experiences | A **component**'s internal state |
| Examples | Error ratio, latency p99, availability, checkout success, queue age | CPU %, memory %, disk %, pod restart, replica count, GC pause |
| Pages a human? | **Yes** | **No** (usually) |
| Goes where | Page → on-call | Dashboard, ticket, or **inhibition rule** |
| False positives | Low — if users hurt, users hurt | High — a healthy busy system has high CPU |

Google's SRE Workbook formulation: *"alert on symptoms, use causes for diagnosis."*

**The practical rule:**

> A page must satisfy all three: **urgent** (needs action within minutes), **actionable** (a human can do something), **rare** (not routine). If any is false → dashboard panel or ticket.

**But** you still need cause alerts in three cases:
1. **The symptom can't be measured yet** (new service, batch job, background worker with no user-facing metric).
2. **Imminent failure with lead time** — disk full in 4 h, certificate expiry in 7 days, connection pool exhaustion. These are *symptoms of a future outage* and are legitimately pageable because the action (add capacity/renew cert) is clear and time-boxed.
3. **Your monitoring stack itself** (Prometheus down, Alertmanager down, Watchdog stopped) — meta-alerts must page.

### Building the alert set for a service (the layered approach)

| Layer | Alert | Severity | Type |
|---|---|---|---|
| 1. SLO | Fast error-budget burn (2%/1h) | `page` | symptom |
| 1. SLO | Slow error-budget burn (5%/6h) | `ticket` | symptom |
| 2. Availability | `up == 0` for all instances of a service | `page` | symptom |
| 3. Latency | p99 > SLO threshold for 10m | `page`/`ticket` | symptom |
| 4. Saturation w/ impact | Disk will fill in 24h; queue age > 5m; pool exhausted | `page` | leading symptom |
| 5. Cause | High CPU/memory, replica deficit, restarts, GC | `ticket`/none | cause |
| 6. Meta | Prometheus/Alertmanager/Watchdog | `page` | meta |

Most teams have 40 alerts in layer 5 and 2 in layer 1. Invert that.

---

## 4. Severity model

Define **exactly** what each severity means in terms of *human response*, not in terms of the metric. If severity doesn't change behaviour, it's decoration.

| Severity | Meaning | Route to | Response time | Repeat interval |
|---|---|---|---|---|
| `page` / `critical` | Users are impacted now, or will be within the hour. Wake someone up. | PagerDuty/phone + Slack `#incidents` | 5–15 min | 4 h |
| `ticket` / `warning` | Real problem, not urgent. Fix during business hours. | Jira/GitHub issue + Slack `#alerts` | 1–3 days | 24 h |
| `info` | FYI, trend, capacity planning. | Slack `#monitoring` or dashboard only | none | never |

Rules:
- **Severity is a label set on the rule** in Prometheus, and it drives routing in Alertmanager. Don't infer severity from the alert name.
- Add `team`/`service` labels so routing doesn't depend on a name-matching regex that will break.
- Add `escalation: "true"` only for the alerts that should escalate if unacknowledged.
- Keep the set **small** (2–4 values). Ten severities is zero severities.

---

## 5. Anatomy of a good alert rule

```yaml
groups:
  - name: checkout-api.slo
    interval: 30s                 # optional per-group evaluation interval
    limit: 20                     # optional: max alerts this group may produce (Prometheus 3)
    rules:
      - alert: CheckoutHighErrorRate
        # 1. EXPR: a symptom, precomputed by a recording rule where possible
        expr: |
          (
            slo:checkout_http_errors:ratio_rate5m > 0.02
          and
            slo:checkout_http_requests:rate5m > 1
          )
        # 2. FOR: long enough to be real, short enough to matter
        for: 10m
        keep_firing_for: 5m
        # 3. LABELS: machine-readable, drive routing
        labels:
          severity: page
          team: checkout
          service: checkout-api
          slo: checkout-availability
        # 4. ANNOTATIONS: human-readable, drive action
        annotations:
          summary: "Checkout error rate is {{ $value | humanizePercentage }} (>2%) for 10m"
          description: |
            {{ $labels.service }} in {{ $labels.namespace }} is returning
            {{ $value | humanizePercentage }} errors. Traffic is
            {{ with query "slo:checkout_http_requests:rate5m" }}{{ . | first | value }}{{ end }} req/s.
          dashboard: "https://grafana.example.com/d/checkout/checkout?var-service={{ $labels.service }}"
          runbook: "https://runbooks.example.com/checkout/high-error-rate"
          # Grafana/AM will render these; also useful:
          # trace: "https://tempo.example.com/search?service={{ $labels.service }}&status=error"
```

### The five things every alert must have
1. **A name that describes the user impact**, not the metric. ✅ `CheckoutHighErrorRate` ❌ `Metric5xxAboveThreshold`.
2. **`severity`** + **`team`/`service`** labels (for routing).
3. **`summary`** — one line, includes the current value.
4. **`runbook`** annotation — a URL with the first three diagnostic steps.
5. **`dashboard`** annotation — a deep link with variables pre-filled (`?var-x={{ $labels.x }}`).

**Annotations vs labels — the rule that trips everyone up:**

> Anything that **distinguishes one alert from another** (and therefore changes its identity/fingerprint) must be a **label**. Anything that is **descriptive text** must be an **annotation**.

Consequences:
- Adding a label **creates a new alert series** → can multiply alert volume (e.g. don't put `pod` in labels if you want one alert per service).
- Adding an annotation does **not** affect identity → safe for values, links, descriptions.
- The alert **fingerprint** = hash of all labels. Change a label, and Alertmanager treats it as a brand-new alert (breaking grouping and re-notifying).
- Annotations are available in notification templates as `.Annotations`; labels as `.Labels` and `.CommonLabels`.

### Templating in rules
Go templates with `{{ $value }}` (the expression's value) and `{{ $labels.x }}`. Functions include `humanize`, `humanizePercentage`, `humanizeDuration`, `humanizeTimestamp`, `printf`, `reReplaceAll`, `toUpper`, plus `query`/`first`/`value` for querying other series.

```yaml
annotations:
  summary: '{{ $labels.instance }} has been down for {{ $value | humanizeDuration }}'
  value_pct: '{{ printf "%.2f" (mulf $value 100) }}%'
```
> `$value` is the value of the alert expression at evaluation time. For `up == 0` style alerts it may be `0` or `1` and not meaningful — compute what you need in the expression instead, e.g. `expr: time() - last_seen_timestamp` so `$value` is the age in seconds.

---

## 6. Recording rules — the foundation of good alerting

A recording rule precomputes an expression and stores it as a **new series**. Name convention: `level:metric:operations` (e.g. `job:http_requests:rate5m`).

```yaml
groups:
  - name: http.recording
    interval: 30s
    rules:
      - record: job:http_requests:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))

      - record: job:http_errors:rate5m
        expr: sum by (job) (rate(http_requests_total{status=~"5.."}[5m]))

      - record: job:http_error_ratio:rate5m
        expr: |
          job:http_errors:rate5m
            /
          clamp_min(job:http_requests:rate5m, 1e-9)     # avoid divide-by-zero → NaN

      - record: job:http_request_duration_seconds:p99_5m
        expr: |
          histogram_quantile(0.99,
            sum by (job, le) (rate(http_request_duration_seconds_bucket[5m])))
```

Why you want them:
- **Alerts become trivial and cheap** (`job:http_error_ratio:rate5m > 0.02`).
- **Dashboards and alerts use exactly the same numbers** — no more "the graph says 3% but the alert said fine".
- **Expensive PromQL is computed once**, not once per panel per user.
- **Historical backfill**: the rule's output is stored, so you can trend your SLI over months even if the raw data is downsampled away.

Gotchas:
- The `:` in the name is a **convention**, and matters for federation (`match[]={__name__=~".+:.+"}`).
- Rules evaluate in dependency order **within a group**, but groups run in parallel — so a rule depending on another group's output can lag one evaluation interval. Put dependent rules in the same group, in order.
- A broken rule logs `Rule evaluation failed` and increments `prometheus_rule_evaluation_failures_total` — alert on that.
- Deleting/renaming a recording rule breaks every dashboard and alert referencing it. Grep first.

---

## 7. Reducing alert fatigue — the practical playbook

Alert fatigue = on-call has learned that pages don't matter. Symptoms: pages ignored, alerts closed without action, "oh that's just X again".

**Measure it first:**
```promql
# alerts fired per day by alertname (from Alertmanager metrics)
topk(15, sum by (alertname) (increase(alertmanager_alerts_received_total[24h])))
sum by (alertname) (increase(alertmanager_notifications_total[7d]))
# how often do alerts resolve within 5 minutes (= flapping/noise)
```
Then run the weekly **"top 5 noisy alerts"** review: for each, decide **fix / demote / delete**.

| Tactic | How |
|---|---|
| **Add/increase `for:`** | Kills single-scrape blips |
| **Add a traffic guard** | `and sum(rate(requests[5m])) > 1` — don't page for 1 error at 3 a.m. on an idle service |
| **Use `keep_firing_for:`** | Stops resolve/refire ping-pong |
| **Group in Alertmanager** | 400 pod alerts → 1 grouped notification |
| **Inhibit** | Node down ⇒ suppress all pod alerts on that node |
| **Multi-window burn rate** | Requires both a short and a long window → no pages for 30-second blips (see topic 09) |
| **Demote cause alerts** | Move CPU/memory alerts to `ticket` or delete |
| **Mute time intervals** | Non-urgent routes muted overnight/weekends |
| **Business-hours-only routes** | `active_time_intervals` for `ticket` severity |
| **Delete** | Any alert that produced no action in 90 days |
| **Alert review ritual** | Monthly: every alert must have an owner, a runbook, and a reason to exist |

**Targets worth defending:** < 5 pages per on-call shift for a mature service; > 90% of pages result in a human action; 100% of pages have a runbook; median time-to-ack < 5 min.

---

## 8. Flapping, thresholds and hysteresis

**Flapping** = alert oscillating between firing and resolved. Causes and fixes:

| Cause | Fix |
|---|---|
| `for:` too short | Increase it |
| Threshold right at the operating point | Add hysteresis: fire at 80%, resolve at 70% (two rules, or use `keep_firing_for`) |
| Spiky metric | Use `avg_over_time()`/`rate()` with a longer window, or `irate`→`rate` |
| Scrape interval ≈ range window | Widen the range to ≥ 4× scrape interval |
| Autoscaling changing denominators | Aggregate consistently (`sum by (job)` not `by (pod)`) |
| Two Prometheus replicas both alerting | Deduplicate in Alertmanager cluster / use ruler dedup |

**Threshold design:**
- Prefer **relative to a baseline** (`> 2× offset 7d`) over absolute where the workload is seasonal.
- Prefer **rates/ratios** over raw counters.
- Prefer **percentiles** over averages for latency.
- Prefer **trend prediction** (`predict_linear`) for capacity.
- **Two-tier thresholds** are almost always right: `warning` at 70%, `critical` at 90% — with inhibition so only the critical pages.
- Every threshold must be **justified in a comment**: `# 80% = 2h of headroom at current growth (2026-09 review)`.

---

## 9. Testing alerts before they page you at 3 a.m.

Three levels, in order of value:

**Level 1 — unit tests** (`promtool test rules`): synthetic input series, assert which alerts fire at which time with which labels/annotations. This belongs in CI. Example in [`04-PromQL`](../04-PromQL/README.md#unit-testing-rules-do-this-in-ci).

**Level 2 — query validation**: paste `expr` into Grafana Explore over the last 7 days and confirm it *would have* fired exactly when you wanted, and not at other times. This is where you discover your threshold is wrong.

**Level 3 — end-to-end**: point a rule at a lab Alertmanager with a webhook receiver (`webhook.site`, `nc -l 9999`, or a local HTTP server) and watch the JSON arrive. Verify grouping, routing, templates, resolution.

**Level 4 — chaos**: in staging, actually break the thing. `docker stop`, `kubectl delete pod`, inject 500s, fill the disk. If the alert doesn't fire, you don't have monitoring — you have decoration.

```bash
# Validate everything before merging
promtool check config prometheus.yml
promtool check rules rules/*.yaml
promtool test rules tests/*.yaml
amtool check-config alertmanager.yml
```

Also useful: **`promtool query series/instant`** and the Prometheus UI **Rules** page, which shows each rule's last evaluation, duration, health and the current state of every alert.

---

## 10. Alert rule anti-pattern catalogue

| Anti-pattern | Example | Why it hurts | Instead |
|---|---|---|---|
| **Cause alerting as pages** | `node_cpu_usage > 80` → page | Busy healthy systems page you | Symptom page + cause dashboard |
| **Alerting on averages** | `avg(latency) > 500ms` | Tail users suffer invisibly | `histogram_quantile(0.99, ...)` |
| **Alerting on a counter value** | `errors_total > 1000` | Meaningless — counters only grow | `rate()` / `increase()` |
| **`rate()` over a window < 2× scrape interval** | `rate(x[15s])` at 15s scrape | Gaps and zeros | `rate(x[1m])` or more |
| **No `for:`** | fires on one blip | Noise | `for: 5m` |
| **Alert with no labels** | no `severity`, no `team` | Can't route | Add routing labels |
| **Alert with no runbook** | — | Page with no next action | Runbook URL mandatory |
| **Dynamic labels in alert identity** | `annotations` promoted to labels, or `pod` in labels for a service-level alert | Alert storm, broken grouping | Aggregate away volatile labels |
| **Duplicated alerting systems** | Prometheus rules *and* Grafana unified alerting *and* cloud alarms | Two truths, double pages, unclear ownership | One authority per domain; document it |
| **Alerts on data that doesn't exist** | rule references a metric nobody exports | Silent no-op forever | `absent()` companion alert + CI test |
| **Overly broad regex rules** | `{__name__=~".+"}` | Kills Prometheus | Named metrics only |
| **One alert named `SomethingBad`** | catches 12 different conditions | Unactionable, untriageable | One alert per distinct action |
| **Silencing instead of fixing** | permanent silence | Blind spot | Fix the rule; silences expire |
| **`for:` longer than the incident** | `for: 2h` on an availability alert | You learn about the outage after it ends | Multi-window burn rate instead |

---

## 11. What to alert on, by domain (starter set)

Copy and adapt; full YAML in [`13-Alert-Rules-Library`](../13-Alert-Rules-Library/README.md).

| Domain | Page | Ticket |
|---|---|---|
| **Availability** | `up == 0` for a service (5m); external probe failing (5m) | Single instance down in a multi-replica service |
| **SLO** | Fast burn (2% budget in 1h) | Slow burn (5% in 6h); budget < 20% remaining |
| **Latency** | p99 > SLO for 10m with traffic | p95 trending up 30% week over week |
| **Saturation** | Disk full in 24h; memory OOM imminent; connection pool exhausted; queue age > 5m | Disk full in 7 days; CPU > 80% sustained 1h |
| **Kubernetes** | Node NotReady (5m); >10% pods pending (10m); PVC almost full; deployment at 0 available replicas | Pod crashlooping; container waiting > 15m; HPA at max replicas |
| **Certificates/TLS** | Cert expires < 7 days (probe) | Cert expires < 30 days |
| **Databases** | Replication lag > 60s; connections > 90% of max; deadlocks spike | Slow query rate up; table size growth |
| **Monitoring itself** | Prometheus down; Alertmanager down; Watchdog not firing; config reload failed; WAL corruption; scrape duration > 80% timeout; high cardinality | TSDB disk 70%; target count growth |
| **Business** | Checkout success < 95% for 15m; signups = 0 for 1h in business hours | Conversion down 20% vs same hour last week |

---

## Lab

1. In the lab stack, create `HighRequestLatency` with `for: 0m`, then with `for: 5m`. Generate load and watch the state transitions in the Prometheus **Alerts** UI (`INACTIVE → PENDING → FIRING`).
2. Add `keep_firing_for: 2m`, stop the load, and observe the delayed resolution.
3. Add a traffic guard with `and`; verify the alert no longer fires when idle.
4. Convert your `expr` into a recording rule and rewrite the alert to use it.
5. Write a `promtool test rules` unit test that asserts the alert fires at minute 10 and not at minute 5.
6. Break one of the five things in the rule and confirm your test catches it.

---

## Self-check

1. What are the three alert states and what triggers each transition?
2. What does `for:` do, and what happens if the expression flickers false?
3. Symptom vs cause: give two of each for a web API, and say which pages.
4. Label vs annotation — the deciding question you ask for each.
5. Why does adding `pod` to an alert's labels sometimes cause an alert storm?
6. Name four ways to reduce alert fatigue without deleting the alert.
7. Why are recording rules a prerequisite for good SLO alerting?
8. What four validation steps do you run before merging an alert rule?
9. Write from memory an alert rule with severity, team, summary, description, runbook and dashboard annotations.
10. When *is* a cause alert legitimately pageable? Give three cases.

→ Next: [`06-Alertmanager`](../06-Alertmanager/README.md)
