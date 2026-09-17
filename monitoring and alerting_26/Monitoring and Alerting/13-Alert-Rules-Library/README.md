# Alert Rules Library

**Level:** reference · **Goal:** copy-paste, production-shaped Prometheus rule files. Each file below is valid `rule_files:` content — drop it in, run `promtool check rules`, and adapt thresholds/labels to your estate.

---

## How to use this library

```bash
# 1. Copy the file(s) you need
cp rules/prometheus-self-monitoring.yaml /etc/prometheus/rules/

# 2. Validate
promtool check rules /etc/prometheus/rules/*.yaml

# 3. Wire it into prometheus.yml
#    rule_files:
#      - /etc/prometheus/rules/*.yaml

# 4. Unit-test anything you change
promtool test rules tests/*.yaml

# 5. In Kubernetes, wrap the `groups:` body in a PrometheusRule CRD
#    (see 08-Kubernetes-Monitoring) — `spec:` is exactly this file's content.
```

**Before you deploy, change these three things in every rule:**
1. **Thresholds** — the numbers here are sane defaults, not your numbers. Derive them from your own history (`quantile_over_time`, or just look at a 30-day graph).
2. **Labels** — `severity` (`page`/`ticket`), `team`, `service` must match your Alertmanager routing tree.
3. **Annotations** — `runbook` and `dashboard` URLs must be real. An alert with a dead runbook link is worse than none, because it trains people to distrust them.

Convention used throughout:
- `severity: page` → routes to a human 24/7 · `severity: ticket` → business hours / issue tracker · `severity: none` → internal (Watchdog).
- Recording-rule names follow `level:metric:operations` (e.g. `job:http_error_ratio:rate5m`).
- Every rule that can suffer from zero traffic has a guard.

---

## Contents

| File | What it covers | Rules |
|---|---|---|
| [`rules/prometheus-self-monitoring.yaml`](rules/prometheus-self-monitoring.yaml) | **Monitor the monitoring**: Prometheus, Alertmanager, targets, config reloads, cardinality, remote_write, Watchdog | 22 |
| [`rules/node-and-host.yaml`](rules/node-and-host.yaml) | Linux hosts via node_exporter: CPU, memory, disk space/inodes/health/IO, network, clock, conntrack, file descriptors | 21 |
| [`rules/kubernetes.yaml`](rules/kubernetes.yaml) | Nodes, workloads, pods, jobs, HPA, quota, PVCs, API server, kubelet, cAdvisor throttling/memory | 38 |
| [`rules/application-red.yaml`](rules/application-red.yaml) | Generic RED/service-level rules for any instrumented app: errors, latency, traffic anomalies, runtime, pools, queues | 14 |
| [`rules/slo-burn-rates.yaml`](rules/slo-burn-rates.yaml) | Multi-window multi-burn-rate SLO alerting (template for a 99.9% objective) — 12 recording + 8 alert rules | 20 |
| [`rules/blackbox-probes.yaml`](rules/blackbox-probes.yaml) | Synthetic probes: HTTP, TCP, DNS, TLS certificate expiry and chain verification | 13 |
| [`rules/recording-rules-base.yaml`](rules/recording-rules-base.yaml) | The recording rules the other files depend on (`job:http_*`, `instance:node_*`) | 13 |
| [`tests/example_test.yaml`](tests/example_test.yaml) | `promtool test rules` example — 3 cases incl. the traffic-guard and all-instances-down tests | — |

**141 rules total.** All files validated with `promtool check rules` (Prometheus 3.14) and the test file passes with `promtool test rules`.

**Suggested install order:** `recording-rules-base` → `prometheus-self-monitoring` → `node-and-host` → `blackbox-probes` → `kubernetes` → `application-red` → `slo-burn-rates`.

> ⚠️ `kubernetes.yaml` and `slo-burn-rates.yaml` depend on `kube-state-metrics` and on the recording rules. Install the dependencies first or the rules will evaluate to empty and never fire.

---

## The absolute minimum set (if you only do five things)

1. **`Watchdog`** — `vector(1)`, always firing, routed to an external dead-man's-switch. Without this, a dead Prometheus is invisible.
2. **`TargetDown` / `up == 0`** — for every job that matters.
3. **`PrometheusConfigReloadFailed`** — a typo silently disables all your alerting.
4. **One symptom alert per critical service** — error-ratio burn rate.
5. **`HostDiskWillFillIn24Hours`** — the classic "we had 4 hours of warning and ignored it".

Everything else in this library is refinement.

---

## Reviewing your rules (do this quarterly)

```promql
# Which alerts actually fire? (Alertmanager metrics)
topk(20, sum by (alertname) (increase(alertmanager_alerts_received_total[7d])))

# Which alerts never fire? Compare against your rule inventory:
count by (alertname) (ALERTS{alertstate="firing"})     # over a 30d range in Grafana
```

For each alert in the inventory, ask:
- Did it fire in the last 90 days? If not → is that because the problem didn't happen, or because the rule is broken? **Test it.**
- When it fired, did someone take an action? If not → demote to `ticket` or delete.
- Does it have a runbook, an owner, and a reviewed date?
- Is its threshold still right given current traffic?

Delete aggressively. A rule set nobody trusts protects nobody.

---

## Self-check

1. Which rule file would you install first, and why?
2. What three things must you change in every copied rule before it goes to production?
3. How do you turn one of these files into a Kubernetes `PrometheusRule`?
4. Name the five minimum rules.
5. How do you find an alert rule that has been silently broken for six months?
