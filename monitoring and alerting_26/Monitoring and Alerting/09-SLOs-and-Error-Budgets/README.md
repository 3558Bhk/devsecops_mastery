# 09 · SLOs & Error Budgets  ★ deep dive

**Level:** core · **Time:** ~4 h · **Goal:** define an SLI/SLO, compute an error budget, and build multi-window multi-burn-rate alerts — the alerting system that replaces threshold soup.

---

## 1. SLI · SLO · SLA (get these exactly right)

| Term | Definition | Example |
|---|---|---|
| **SLI** — Service Level **Indicator** | A *measured* ratio: `good events / valid events`, expressed 0–1. Must be computable from telemetry you already have. | `non-5xx responses ÷ all responses` |
| **SLO** — Service Level **Objective** | A *target* on the SLI over a *window*, agreed internally. | "99.9% of requests over a rolling 28 days return non-5xx" |
| **SLA** — Service Level **Agreement** | A *contract* with a customer, with consequences (credits) if breached. Always **looser** than the SLO. | "99.5% monthly availability, else 10% credit" |
| **Error budget** | `1 − SLO`. The amount of unreliability you are *allowed* to spend. | 99.9% over 28 d ⇒ 0.1% ⇒ **40.3 minutes** of total unavailability, or ~1 bad request in 1000 |

**The insight that makes SLOs worth having:** the error budget turns "should we ship or should we stabilise?" from an argument into arithmetic. Budget remaining → ship freely. Budget exhausted → freeze risky changes, fix reliability. It aligns developers (velocity) and operators (stability) on one number.

### Choosing the SLI

Good SLIs are **event-count ratios** measured *where the user is*, not where the code is:

| SLI type | Good events | Valid events | Where measured |
|---|---|---|---|
| **Availability** | non-5xx responses | all responses | Load balancer / edge / API gateway (best), else app |
| **Latency** | requests faster than threshold T | all requests | Same |
| **Quality** | responses without degraded fallback | all responses | App |
| **Freshness** | data newer than X | all data reads | App/DB |
| **Correctness** | successfully processed records | total records ingested | Pipeline |
| **Throughput/Coverage** | messages processed within deadline | messages received | Queue |

Rules of thumb:
- **Measure as close to the user as possible.** An SLI at the app can read 100% while the LB returns 502s because the app is down. If you can, use the edge.
- **Weight by traffic, not by time.** `availability = good requests / total requests`, not `up minutes / total minutes`. A 5-minute outage at peak hurts more than at 3 a.m., and the ratio captures that automatically.
- **Only include what you control.** Exclude client-side errors (4xx) — a user's bad request is not your failure. Exclude 429 if rate limiting is intentional.
- **One or two SLIs per service, maximum.** Availability + latency covers ~90% of what users care about.

### Choosing the target

- **Don't pick 100%.** 100% is the wrong SLO: it's unachievable, gives zero budget for experimentation, and any budget-driven decision collapses.
- **Don't pick 99.999% unless you can actually deliver it.** Five nines = 26 s/month. That requires multi-region active-active, a large team, and a lot of money.
- **Derive it from evidence:** historical SLI percentile (what do you actually deliver?), user expectations, dependency SLOs (your SLO can't be better than your worst dependency's), and cost.
- **Start loose, tighten later.** 99.5% → measure 3 months → tighten to 99.9% if you're consistently better.

| SLO | Allowed downtime / 28 days | Bad requests per million | Realistic for |
|---|---|---|---|
| 99% | 6.7 h | 10,000 | Internal tools, batch |
| 99.5% | 3.4 h | 5,000 | Internal services, staging-like |
| 99.9% | 40.3 min | 1,000 | **Most production web services** |
| 99.95% | 20.2 min | 500 | Important customer-facing |
| 99.99% | 4.03 min | 100 | Revenue-critical, HA architecture |
| 99.999% | 24.2 s | 10 | Payments core, telco |

**Composite vs per-service:** define SLOs per *user journey* ("checkout", "search", "login") rather than per microservice — users experience journeys, not services. A journey SLO may be the product of its services' SLOs: 10 services at 99.9% in series ≈ 99% end-to-end. That math is why you need fewer, better services on the critical path.

---

## 2. Turning an SLI into PromQL

### Availability (ratio-based)

```yaml
groups:
  - name: sli.checkout
    interval: 30s
    rules:
      # Total valid requests per second, per service
      - record: sli:checkout_http_requests:rate5m
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[5m]))

      # Bad events: 5xx (and 429 only if you count it as failure)
      - record: sli:checkout_http_errors:rate5m
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m]))

      # The SLI itself: ratio of GOOD events  (1 - error ratio)
      - record: sli:checkout_availability:ratio_rate5m
        expr: |
          1 - (
            sli:checkout_http_errors:rate5m
              / clamp_min(sli:checkout_http_requests:rate5m, 1e-9)
          )
```
> `clamp_min(..., 1e-9)` prevents `NaN` when traffic is zero. Decide explicitly what an idle service means: `NaN` (no data ⇒ SLO not violated) is usually right, but then your alert must not fire on `NaN`.

### Latency SLI (fraction of requests faster than T)

```yaml
      - record: sli:checkout_latency_good:rate5m
        expr: |
          sum(rate(http_request_duration_seconds_bucket{job="checkout-api",le="0.3"}[5m]))

      - record: sli:checkout_latency_ratio:rate5m
        expr: |
          sum(rate(sli:checkout_latency_good:rate5m[5m]))
            / clamp_min(sum(rate(http_request_duration_seconds_count{job="checkout-api"}[5m])), 1e-9)
```
The histogram bucket boundary **must** be your latency threshold (300 ms here). If you don't have a bucket at exactly T, add one — that's what buckets are for.

### Error budget remaining (for dashboards)

```promql
# Over the last 28 days, with a 99.9% objective
1 - (
  sum(increase(http_requests_total{job="checkout-api",status=~"5.."}[28d]))
    /
  sum(increase(http_requests_total{job="checkout-api",status!~"4.."}[28d]))
) / (1 - 0.999)
# → 1.0 = full budget, 0.0 = exhausted, negative = over budget
```
Better (and cheaper) with recording rules over fixed windows:
```yaml
      - record: slo:checkout_error_budget_remaining:ratio
        expr: |
          1 - (
            sum(increase(http_requests_total{job="checkout-api",status=~"5.."}[28d]))
              / clamp_min(sum(increase(http_requests_total{job="checkout-api",status!~"4.."}[28d])), 1e-9)
          ) / (1 - 0.999)
```

---

## 3. Multi-window, multi-burn-rate alerting (the Google SRE Workbook method)

### Why naive SLO alerts fail

❌ `error_rate > 0.1% for 5m` — pages constantly on tiny blips that don't threaten the budget.
❌ `budget_remaining < 0` — only fires *after* you've already blown the whole month's budget. Useless for prevention.

**The fix: alert on the *rate at which you are consuming the budget*, measured over two windows simultaneously.**

### Burn rate

```
burn rate = observed error rate ÷ SLO-allowed error rate
```
- Burn rate **1** = you will use exactly the budget over the SLO window (perfect pace).
- Burn rate **14.4** = you'll consume **2% of a 30-day budget in 1 hour**.
- Burn rate **6** = 5% of the budget in 6 hours.

Formally, for a window `w` and SLO window `W`:
```
burn_rate = (bad_events(w) / valid_events(w)) / (1 - SLO)
```

### The four canonical rules

| Burn rate | Budget consumed | Long window | Short window | Severity | Intent |
|---|---|---|---|---|---|
| **14.4×** | 2% | **1 h** | **5 m** | `page` | Fast burn — act now |
| **6×** | 5% | **6 h** | **30 m** | `page` | Medium burn |
| **3×** | 10% | **1 d** | **2 h** | `ticket` | Slow burn |
| **1×** | 10% | **3 d** | **6 h** | `ticket` | Drip burn |

**Why two windows?** The long window proves the burn is *sustained* (no false positives from one bad minute). The short window proves it is *still happening now* (no pages for an incident that already resolved 50 minutes ago — the long window alone would keep the ratio high long after recovery). **Both must be burning at once.** That's the `and`.

### The rules, in YAML

```yaml
groups:
  - name: slo.checkout.recording
    interval: 30s
    rules:
      # Per-window bad:good ratios for each of the burn-rate windows.
      # Note: these are RATIOS (bad/valid), not the SLI.
      - record: slo:checkout_http_errors:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m]))
            / clamp_min(sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[5m])), 1e-9)
      - record: slo:checkout_http_errors:ratio_rate30m
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[30m]))
            / clamp_min(sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[30m])), 1e-9)
      - record: slo:checkout_http_errors:ratio_rate1h
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[1h]))
            / clamp_min(sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[1h])), 1e-9)
      - record: slo:checkout_http_errors:ratio_rate2h
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[2h]))
            / clamp_min(sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[2h])), 1e-9)
      - record: slo:checkout_http_errors:ratio_rate6h
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[6h]))
            / clamp_min(sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[6h])), 1e-9)
      - record: slo:checkout_http_errors:ratio_rate1d
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[1d]))
            / clamp_min(sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[1d])), 1e-9)
      - record: slo:checkout_http_errors:ratio_rate3d
        expr: |
          sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[3d]))
            / clamp_min(sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[3d])), 1e-9)

  - name: slo.checkout.alerts
    rules:
      # ── Fast burn: 2% of a 30-day budget in 1 hour ──────────────────────
      - alert: CheckoutSLOFastBurn
        expr: |
          (
            slo:checkout_http_errors:ratio_rate1h  > (14.4 * 0.001)
          and
            slo:checkout_http_errors:ratio_rate5m  > (14.4 * 0.001)
          )
        for: 2m
        labels:
          severity: page
          team: checkout
          slo: checkout-availability
          slo_window: 1h
        annotations:
          summary: "Checkout is burning its error budget 14.4× faster than allowed"
          description: |
            Error ratio over 1h and 5m both exceed 1.44% (14.4 × the 0.1% SLO allowance).
            At this rate 2% of the 28-day budget is gone within an hour.
          runbook: "https://runbooks.example.com/checkout/slo-fast-burn"
          dashboard: "https://grafana.example.com/d/checkout-slo?var-service=checkout-api"

      # ── Medium burn: 5% in 6 hours ──────────────────────────────────────
      - alert: CheckoutSLOMediumBurn
        expr: |
          (
            slo:checkout_http_errors:ratio_rate6h  > (6 * 0.001)
          and
            slo:checkout_http_errors:ratio_rate30m > (6 * 0.001)
          )
        for: 15m
        labels: {severity: page, team: checkout, slo: checkout-availability, slo_window: 6h}
        annotations:
          summary: "Checkout error budget burning 6× too fast (5% in 6h)"
          runbook: "https://runbooks.example.com/checkout/slo-medium-burn"

      # ── Slow burn: 10% in 1 day ─────────────────────────────────────────
      - alert: CheckoutSLOSlowBurn
        expr: |
          (
            slo:checkout_http_errors:ratio_rate1d > (3 * 0.001)
          and
            slo:checkout_http_errors:ratio_rate2h > (3 * 0.001)
          )
        for: 1h
        labels: {severity: ticket, team: checkout, slo: checkout-availability, slo_window: 1d}
        annotations:
          summary: "Checkout error budget burning 3× too fast (10% in 1d)"
          runbook: "https://runbooks.example.com/checkout/slo-slow-burn"

      # ── Drip burn: 10% in 3 days ────────────────────────────────────────
      - alert: CheckoutSLODripBurn
        expr: |
          (
            slo:checkout_http_errors:ratio_rate3d > (1 * 0.001)
          and
            slo:checkout_http_errors:ratio_rate6h > (1 * 0.001)
          )
        for: 3h
        labels: {severity: ticket, team: checkout, slo: checkout-availability, slo_window: 3d}
        annotations:
          summary: "Checkout steadily consuming its error budget (10% in 3d)"
          runbook: "https://runbooks.example.com/checkout/slo-drip-burn"

      # ── Budget nearly exhausted (governance, not incident) ──────────────
      - alert: CheckoutErrorBudgetAlmostExhausted
        expr: slo:checkout_error_budget_remaining:ratio < 0.1
        for: 30m
        labels: {severity: ticket, team: checkout, slo: checkout-availability}
        annotations:
          summary: "Checkout has less than 10% of its 28-day error budget left"
          description: "Consider a release freeze and reliability work per the SLO policy."
```

> `0.001` = `1 − 0.999` (your allowed error ratio). Replace with your own. Keep it in one place — many teams generate these rules with a templating tool (Jsonnet in `kube-prometheus`, Helm templates, or `sloth`/`pyrra`) so the SLO number is defined once.

### Tooling that generates this for you

| Tool | What it does |
|---|---|
| **Sloth** | YAML spec of your SLI/SLO → generates Prometheus recording + multi-window burn-rate rules, and a Grafana dashboard. Easiest on-ramp. |
| **Pyrra** | Same idea, with a UI and Kubernetes operator; produces rules + dashboards. |
| **kube-prometheus (Jsonnet)** | `slo.libsonnet` mixin generating the full rule set from an SLI definition. |
| **Nobl9 / Grafana Cloud SLO / Datadog SLO** | Managed SLO products with their own alerting. |

**Sloth example** (`checkout.yaml`):
```yaml
version: "prometheus/v1"
service: "checkout"
slos:
  - name: "availability"
    objective: 99.9
    description: "99.9% of checkout requests return non-5xx"
    sli:
      events:
        errorQuery: sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[{{.window}}]))
        totalQuery: sum(rate(http_requests_total{job="checkout-api",status!~"4.."}[{{.window}}]))
    alerting:
      name: CheckoutAvailability
      labels: {team: checkout, severity: page}
      annotations:
        runbook: "https://runbooks.example.com/checkout/slo"
      pageAlert:
        labels: {severity: page}
      ticketAlert:
        labels: {severity: ticket}
```
```bash
sloth generate -i checkout.yaml -o rules.yaml && promtool check rules rules.yaml
```

---

## 4. Latency SLOs — two valid formulations

**Formulation A (ratio / "good events"):** *"99% of requests complete in under 300 ms."*
```promql
1 - (
  sum(rate(http_request_duration_seconds_count{job="api"}[5m]))
  - sum(rate(http_request_duration_seconds_bucket{job="api",le="0.3"}[5m]))
) / clamp_min(sum(rate(http_request_duration_seconds_count{job="api"}[5m])), 1e-9)
```
→ plug into the same burn-rate machinery. **Preferred**: it composes with availability and gives a single error-budget model.

**Formulation B (percentile threshold):** *"p99 < 300 ms."*
```promql
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{5m]))) > 0.3
```
→ simpler to explain, but percentiles are **not aggregatable over time** and don't give you a budget. Fine for dashboards and `ticket` alerts; weak as a contractual SLO.

**Combine both:** alert on the budget burn (A) for paging, keep p99/p95/p50 panels (B) for diagnosis.

---

## 5. Error-budget policy — the part that makes SLOs real

An SLO without a policy is a number nobody acts on. Write one page:

```markdown
# Checkout SLO Policy (owner: @checkout-team, reviewed quarterly)

SLO: 99.9% of valid HTTP requests return non-5xx, measured at the ingress,
over a rolling 28-day window. Latency SLO: 99% of requests < 300 ms.

Budget = 40.3 minutes / 0.1% of requests.

| Budget remaining | Action |
|---|---|
| > 50% | Normal velocity. Feature work prioritised. |
| 25–50% | Reliability items moved up the backlog. Postmortem every incident. |
| 10–25% | No risky changes without review. Dedicated reliability sprint item. |
| < 10% | **Release freeze** except security + reliability fixes. All hands on reliability. |
| < 0%  | Freeze continues until budget recovers above 10%. Escalate to engineering leadership. |

Exceptions: security patches, P0 incident fixes, and changes that *improve* the SLI.
Budget resets on the rolling window, not the calendar month.
Measurement is authoritative from Prometheus recording rules (sli:checkout_*),
not from any vendor dashboard.
```

Also decide and document:
- **Window:** rolling 28 days (4 weeks) is the common choice — it smooths weekday/weekend patterns and avoids month-boundary weirdness. Calendar month is easier to explain to customers in an SLA.
- **Who owns the SLO** (a team, not a manager).
- **What counts as a valid event** (do you exclude 4xx? maintenance windows? single-tenant traffic?).
- **Planned maintenance:** usually *excluded* from the SLI (via a maintenance window filter) — otherwise you can never do maintenance. Implement with a recording rule that zeroes the numerator during the window, or by tagging deploys.
- **How the customer-facing SLA relates** (SLA ≤ SLO, always).

---

## 6. SLO dashboard (build this in Grafana)

| Row | Panels |
|---|---|
| **1. The number** | Gauge: SLO attainment over 28d (target line at 99.9%) · Stat: error budget remaining % · Stat: budget burned today · Stat: time-to-exhaustion at current burn |
| **2. Burn rates** | Four stats: current 5m/1h/6h/1d burn rate, coloured against 14.4/6/3/1 |
| **3. Raw SLI** | Time series: good ratio, error ratio, request rate (traffic guard context) |
| **4. Latency** | p50/p95/p99 vs the 300ms threshold line + heatmap |
| **5. Breakdown** | By status code, by endpoint, by region, by version (info-metric join) — *this is where you find the cause* |
| **6. Context** | Deploy annotations, alert list, log panel filtered to 5xx |

Key queries:
```promql
# SLO attainment over the window
1 - (sum(increase(http_requests_total{job="checkout-api",status=~"5.."}[28d]))
      / sum(increase(http_requests_total{job="checkout-api",status!~"4.."}[28d])))

# Current burn rate (1h)
slo:checkout_http_errors:ratio_rate1h / 0.001

# Estimated time to exhaust the budget at the current 1h burn rate
(slo:checkout_error_budget_remaining:ratio * 28 * 24) / clamp_min(slo:checkout_http_errors:ratio_rate1h / 0.001, 1e-9)   # hours
```

---

## 7. Common SLO mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| SLO on the **wrong layer** (app instead of edge) | Reports 100% during a total outage | Measure at LB/ingress; add an external synthetic probe as a cross-check |
| Including **4xx** in bad events | Users' bad input eats your budget | Exclude 4xx (except 429 if you consider it your failure) |
| **100% or 99.999%** targets | No budget → freeze everything, or unreachable → ignored | 99.9% for most services; derive from history |
| Alerting on **budget remaining only** | You learn after the damage | Add multi-window burn rates |
| **No short window** in the burn-rate alert | Pages for hours after recovery | Always `long AND short` |
| **No traffic guard** | One error on an idle service = 100% error ratio = page | `and sli:requests:rate5m > 0.5` |
| Using **percentile-only** latency SLOs | Can't compute a budget, can't aggregate | Use the ratio formulation |
| SLO defined but **no policy** | Number nobody acts on | Write the freeze/thaw table |
| **Every** service gets an SLO | Dilution; nobody maintains them | SLOs for user journeys and critical services only |
| `NaN` during zero traffic | Alerts silently stop working or always fire | `clamp_min` + explicit NaN handling in the alert expr |
| SLO window **shorter than the rule range** | e.g. `[28d]` query but only 15d retention → wrong numbers | Retention ≥ SLO window, or use a long-term store |

---

## 8. Worked example end to end

**Service:** `checkout-api`. **Journey:** user clicks "Pay" → success page.

1. **Pick the SLI.** Valid events = requests to `/checkout/*` excluding 4xx. Good = non-5xx **and** < 500 ms. Measured at the ingress (`nginx_ingress_controller_requests`).
2. **Check history.**
   ```promql
   1 - sum(increase(nginx_ingress_controller_requests{ingress="checkout",status=~"5.."}[28d]))
       / sum(increase(nginx_ingress_controller_requests{ingress="checkout",status!~"4.."}[28d]))
   ```
   → 99.95%. So a 99.9% SLO is achievable with headroom; 99.99% is not.
3. **Set the SLO.** 99.9% availability over rolling 28 days ⇒ budget = 40.3 min.
4. **Write recording rules** for the 7 windows (5m, 30m, 1h, 2h, 6h, 1d, 3d).
5. **Write the four burn-rate alerts** + budget-remaining alert, with `runbook` and `dashboard` annotations.
6. **Route them** in Alertmanager: fast/medium burn → `page` to `checkout-pagerduty`; slow/drip → `ticket` to Jira + `#checkout-alerts`.
7. **Inhibit**: `CheckoutSLOFastBurn` inhibits `HighErrorRate` and `HighLatency` for the same service (they're the same incident).
8. **Build the dashboard** (Row 1–6 above) and link it from the annotation.
9. **Unit-test** the rules with `promtool test rules` — simulate a 30-minute 20% error burst and assert FastBurn fires at minute 32 and MediumBurn does not.
10. **Write the policy** and get the team to agree to the freeze thresholds.
11. **Review monthly**: did any burn-rate alert fire without user impact? Was there user impact without an alert? Adjust thresholds, not the SLO, first.

---

## Lab

1. Pick a service in the lab stack and compute its 28-day (or 1-day, for the lab) availability SLI by hand in Grafana Explore.
2. Write the 7 recording rules and confirm each returns a sane ratio.
3. Write the fast-burn alert. Then generate an error burst with a load tool (`hey -n 5000 -c 20 http://app/fail`) and watch it fire within ~7 minutes.
4. Add the traffic guard and confirm the alert stops firing when traffic drops to zero.
5. Build the SLO dashboard Row 1.
6. Write a `promtool test rules` case asserting the burn alert fires at the expected `eval_time` and not earlier.

---

## Self-check

1. Define SLI, SLO, SLA and error budget in one sentence each, and say which is a contract.
2. Why is 100% the wrong SLO?
3. How much downtime does 99.9% allow over 28 days? Over a 30-day month?
4. What is a burn rate of 14.4 and why that specific number?
5. Why does a burn-rate alert need *two* windows, and what does each protect against?
6. Write the four canonical burn-rate rules' thresholds and severities from memory.
7. Why do you exclude 4xx from the SLI? When would you include 429?
8. Two formulations of a latency SLO — which one gives you an error budget?
9. What goes in an error-budget policy?
10. Your SLO alert fires but users report no problem. Name three possible causes.

→ Next: [`10-Logging-and-Tracing`](../10-Logging-and-Tracing/README.md)
