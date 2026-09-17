# Cheatsheet · SLOs, error budgets & burn rates

## Definitions

| Term | Formula / meaning |
|---|---|
| **SLI** | `good_events / valid_events`, a ratio 0–1, measured as close to the user as possible |
| **SLO** | Target on the SLI over a window: "≥ 99.9% over rolling 28 days" |
| **SLA** | Contract with consequences; always **looser** than the SLO |
| **Error budget** | `1 − SLO` |
| **Burn rate** | `observed_error_ratio / (1 − SLO)` |
| **Budget remaining** | `1 − (errors(W) / valid(W)) / (1 − SLO)` |

## Budget tables

**Downtime allowed**

| SLO | / 28 days | / 30 days | / 1 day | / 1 hour |
|---|---|---|---|---|
| 99% | 6.72 h | 7.20 h | 14.4 m | 36 s |
| 99.5% | 3.36 h | 3.60 h | 7.2 m | 18 s |
| 99.9% | 40.3 m | 43.2 m | 1.44 m | 3.6 s |
| 99.95% | 20.2 m | 21.6 m | 43.2 s | 1.8 s |
| 99.99% | 4.03 m | 4.32 m | 8.6 s | 360 ms |
| 99.999% | 24.2 s | 25.9 s | 864 ms | 36 ms |

**Bad events allowed per million**

| SLO | bad / 1M |
|---|---|
| 99% | 10,000 |
| 99.5% | 5,000 |
| 99.9% | 1,000 |
| 99.95% | 500 |
| 99.99% | 100 |

**Error ratio allowed** = `1 − SLO` → 99.9% ⇒ `0.001` ⇒ 0.1%.

## The four canonical burn-rate rules

| Burn rate | Budget burned | Long window | Short window | Severity | `for:` |
|---|---|---|---|---|---|
| **14.4×** | 2% / 30d | `1h` | `5m` | page | 2m |
| **6×** | 5% / 30d | `6h` | `30m` | page | 15m |
| **3×** | 10% / 30d | `1d` | `2h` | ticket | 1h |
| **1×** | 10% / 30d | `3d` | `6h` | ticket | 3h |

Threshold expression: `error_ratio > (burn_rate × (1 − SLO))`, e.g. `> 14.4 * 0.001 = 0.0144`.

**Both windows must be exceeded simultaneously** (`and`):
- long window ⇒ the burn is *sustained* (no false positives from one bad minute)
- short window ⇒ the burn is *still happening* (no pages for already-recovered incidents)

## Copy-paste rule template

Replace `SERVICE`, `SELECTOR`, `ALLOWED` (= 1 − SLO), and the recording-rule prefix.

```yaml
groups:
  - name: slo.SERVICE.recording
    interval: 30s
    rules:
      - record: slo:SERVICE_errors:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{SELECTOR,status=~"5.."}[5m]))
            / clamp_min(sum(rate(http_requests_total{SELECTOR,status!~"4.."}[5m])), 1e-9)
      - record: slo:SERVICE_errors:ratio_rate30m
        expr: |
          sum(rate(http_requests_total{SELECTOR,status=~"5.."}[30m]))
            / clamp_min(sum(rate(http_requests_total{SELECTOR,status!~"4.."}[30m])), 1e-9)
      - record: slo:SERVICE_errors:ratio_rate1h
        expr: |
          sum(rate(http_requests_total{SELECTOR,status=~"5.."}[1h]))
            / clamp_min(sum(rate(http_requests_total{SELECTOR,status!~"4.."}[1h])), 1e-9)
      - record: slo:SERVICE_errors:ratio_rate2h
        expr: |
          sum(rate(http_requests_total{SELECTOR,status=~"5.."}[2h]))
            / clamp_min(sum(rate(http_requests_total{SELECTOR,status!~"4.."}[2h])), 1e-9)
      - record: slo:SERVICE_errors:ratio_rate6h
        expr: |
          sum(rate(http_requests_total{SELECTOR,status=~"5.."}[6h]))
            / clamp_min(sum(rate(http_requests_total{SELECTOR,status!~"4.."}[6h])), 1e-9)
      - record: slo:SERVICE_errors:ratio_rate1d
        expr: |
          sum(rate(http_requests_total{SELECTOR,status=~"5.."}[1d]))
            / clamp_min(sum(rate(http_requests_total{SELECTOR,status!~"4.."}[1d])), 1e-9)
      - record: slo:SERVICE_errors:ratio_rate3d
        expr: |
          sum(rate(http_requests_total{SELECTOR,status=~"5.."}[3d]))
            / clamp_min(sum(rate(http_requests_total{SELECTOR,status!~"4.."}[3d])), 1e-9)

      - record: slo:SERVICE_burn_rate:1h
        expr: slo:SERVICE_errors:ratio_rate1h / ALLOWED
      - record: sli:SERVICE_availability:ratio_rate5m
        expr: 1 - slo:SERVICE_errors:ratio_rate5m
      - record: slo:SERVICE_error_budget_remaining:ratio
        expr: |
          1 - (
            sum(increase(http_requests_total{SELECTOR,status=~"5.."}[28d]))
              / clamp_min(sum(increase(http_requests_total{SELECTOR,status!~"4.."}[28d])), 1e-9)
          ) / ALLOWED

  - name: slo.SERVICE.alerts
    rules:
      - alert: SERVICESLOFastBurn
        expr: (slo:SERVICE_errors:ratio_rate1h > (14.4 * ALLOWED)) and (slo:SERVICE_errors:ratio_rate5m > (14.4 * ALLOWED))
        for: 2m
        labels: {severity: page, slo: SERVICE-availability}
        annotations:
          summary: "SERVICE burning its error budget 14.4x too fast (2%/1h)"
          runbook: "https://runbooks.example.com/SERVICE/slo-fast-burn"
      - alert: SERVICESLOMediumBurn
        expr: (slo:SERVICE_errors:ratio_rate6h > (6 * ALLOWED)) and (slo:SERVICE_errors:ratio_rate30m > (6 * ALLOWED))
        for: 15m
        labels: {severity: page, slo: SERVICE-availability}
        annotations:
          summary: "SERVICE burning its error budget 6x too fast (5%/6h)"
      - alert: SERVICESLOSlowBurn
        expr: (slo:SERVICE_errors:ratio_rate1d > (3 * ALLOWED)) and (slo:SERVICE_errors:ratio_rate2h > (3 * ALLOWED))
        for: 1h
        labels: {severity: ticket, slo: SERVICE-availability}
        annotations:
          summary: "SERVICE burning its error budget 3x too fast (10%/1d)"
      - alert: SERVICESLODripBurn
        expr: (slo:SERVICE_errors:ratio_rate3d > (1 * ALLOWED)) and (slo:SERVICE_errors:ratio_rate6h > (1 * ALLOWED))
        for: 3h
        labels: {severity: ticket, slo: SERVICE-availability}
        annotations:
          summary: "SERVICE steadily consuming its error budget (10%/3d)"
      - alert: SERVICEErrorBudgetAlmostExhausted
        expr: slo:SERVICE_error_budget_remaining:ratio < 0.10
        for: 30m
        labels: {severity: ticket, slo: SERVICE-availability}
        annotations:
          summary: "SERVICE has <10% of its 28-day error budget left"
      - alert: SERVICESLIMissing
        expr: absent(slo:SERVICE_errors:ratio_rate5m)
        for: 10m
        labels: {severity: page}
        annotations:
          summary: "The SERVICE SLI recording rule produces no data — all SLO alerts are blind"
```

## Latency SLO (ratio formulation, threshold T = 0.3s)

```promql
# good ratio = fraction of requests faster than T
1 - (
  sum(rate(http_request_duration_seconds_count{SELECTOR}[5m]))
    - sum(rate(http_request_duration_seconds_bucket{SELECTOR,le="T"}[5m]))
) / clamp_min(sum(rate(http_request_duration_seconds_count{SELECTOR}[5m])), 1e-9)
```
⇒ plug the error side `(count − bucket_le_T) / count` into the same burn-rate table with `ALLOWED = 1 − 0.99 = 0.01`.
**Requires a histogram bucket boundary at exactly T.**

## Dashboard queries

```promql
sli:SERVICE_availability:ratio_rate5m                       # current SLI
slo:SERVICE_burn_rate:1h                                    # current burn rate
slo:SERVICE_error_budget_remaining:ratio                    # 1.0 → 0.0
1 - (sum(increase(errors[28d])) / sum(increase(valid[28d]))) # attainment over window
# hours until the budget is exhausted at the current 1h burn rate:
(slo:SERVICE_error_budget_remaining:ratio * 28 * 24) / clamp_min(slo:SERVICE_burn_rate:1h, 1e-9)
```

## Generators

| Tool | Input | Output |
|---|---|---|
| **Sloth** | `sloth` YAML spec | Prometheus rules + Grafana dashboard + unit tests |
| **Pyrra** | YAML / UI / operator | Rules + dashboards |
| **kube-prometheus `slo.libsonnet`** | Jsonnet | Full rule set |
| Nobl9 / Grafana Cloud SLO / Datadog | UI/API | Managed |

```bash
sloth generate -i slo.yaml -o rules.yaml --dashboard-out dash.json
sloth verify  -i slo.yaml
promtool check rules rules.yaml && promtool test rules rules-test.yaml
```

## Error-budget policy template

```markdown
SLO: <ratio> of <valid events> are <good>, measured at <layer>, rolling 28 days.
Budget: <minutes> of unavailability / <n> bad events per million.

| Budget remaining | Action |
|---|---|
| > 50%   | Normal velocity |
| 25–50%  | Reliability items prioritised |
| 10–25%  | No risky changes without review |
| < 10%   | Release freeze (security + reliability only) |
| < 0%    | Freeze until back above 10%; escalate |

Exceptions: security patches, incident fixes, changes that improve the SLI.
Planned maintenance is excluded from the SLI.
Authoritative source: Prometheus recording rules sli:SERVICE_*.
Owner: @team · Reviewed: <date> · Next review: <date+90d>
```

## Checklist for a new SLO

- [ ] SLI measured at the layer closest to the user (LB/ingress preferred)
- [ ] Valid events defined; 4xx excluded; maintenance excluded
- [ ] Target derived from ≥ 30 days of history, not from aspiration
- [ ] Histogram bucket at exactly the latency threshold (if a latency SLO)
- [ ] 7 recording rules (5m/30m/1h/2h/6h/1d/3d) + budget-remaining
- [ ] 4 burn-rate alerts + budget-exhausted + `absent()` companion
- [ ] Traffic guard so idle services don't page
- [ ] `runbook` + `dashboard` annotations on every alert
- [ ] `promtool test rules` covering: fires at the right time, doesn't fire early, doesn't fire on idle traffic
- [ ] Dashboard Row 1: SLI gauge, budget stat, burn-rate stats
- [ ] Error-budget policy agreed by the team
- [ ] Retention ≥ SLO window (or a long-term store)
