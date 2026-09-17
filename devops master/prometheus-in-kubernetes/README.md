# 📈 Prometheus in Kubernetes — From `helm install` to Mastery

### The complete, hands-on path: install Prometheus on Kubernetes with Helm charts, understand every component it deploys, instrument your own applications, write PromQL that answers real questions, build alerts people actually act on, and then keep it alive at production scale.

> **WHAT this folder is:** a self-contained course. Eighteen files, read in order, each one building on the last. You start with an empty cluster and finish with a highly-available, secured, multi-tenant Prometheus platform monitoring a real microservice estate — and you will be able to explain every single line of configuration that got you there.
>
> **WHY it exists separately from [`../monitoring-alerting-learning-path/`](../monitoring-alerting-learning-path/README.md):** that folder answers *"which observability case fits my deployment model?"* — Case 1 (Prometheus + Grafana) vs Case 2 (OpenTelemetry), in **7 files**. This folder answers *"I have chosen Prometheus; now make me dangerous with it."* It is **18 files deep** on Prometheus alone, and it assumes nothing.
>
> **TARGET:** a complete beginner who can run `kubectl get pods`. By the end you should be able to hold a **Staff/SRE-level monitoring interview** and, more importantly, debug a Prometheus that has stopped scraping at 3 a.m. without guessing.

---

## 🔒 Version anchors — pinned and verified

Every command, values file and manifest in this folder is written against these exact versions. When you copy something, copy the version too — **monitoring stacks break on silent upgrades more than almost any other tool**, because a chart bump can change CRD schemas, deprecate alert rules, and rewire Grafana datasources all at once.

| Component | Version | Verified | Notes |
|---|---|---|---|
| **`kube-prometheus-stack` (Helm chart)** | **88.1.5** | 2026-08-15 | ⭐ Pin this exact version. `appVersion: v0.93.0`, `kubeVersion: >=1.25.0-0`. A newer tag (88.3.0) exists — run `helm show chart prometheus-community/kube-prometheus-stack --version 88.3.0` yourself before switching |
| **Prometheus Operator** | **v0.93.0** | 2026-08-15 | set by the chart's `appVersion` |
| **Prometheus** | **3.x** | 2026-08 | ⚠️ The exact patch is set by `prometheus.prometheusSpec.image.tag` in the pinned chart's `values.yaml`. **Confirm it for your version** with `helm show values prometheus-community/kube-prometheus-stack --version 88.1.5 \| grep -A4 'prometheusSpec'`. Never assume a number |
| **Alertmanager** | **0.34.0** | 2026-08-16 | |
| **Grafana** | bundled as a subchart | 2026-08 | `grafana.*` values; pin via the parent chart |
| **kube-state-metrics** | bundled subchart | 2026-08 | `kube-state-metrics.*` |
| **prometheus-node-exporter** | bundled subchart | 2026-08 | `prometheus-node-exporter.*` |
| **Helm** | **v3.21.x** | 2026-08-15 | ⭐ Helm v4 (4.1.x/4.2.x) now ships **in parallel**, not as a replacement. This folder is written and tested against **v3**. See [`../helm-charts-mastery/`](../helm-charts-mastery/README.md) for the v3→v4 differences |
| **Kubernetes** | **1.34+** | 2026-08-15 | chart requires `>=1.25.0-0` |
| **`promtool`** | matches your Prometheus | — | ⭐ Always use the `promtool` from the **same** image as your server, or rule validation lies to you |

⭐ **The habit this table is teaching:** a pinned chart version, plus `helm show values` to read what that version actually contains, plus `promtool` from the same image. Three habits that between them eliminate most "it worked yesterday" incidents in monitoring.

---

## 📇 The 18 files — one line each

| # | File | What you learn | Time |
|---|---|---|---|
| `00` | [`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md) | **Empty cluster → working alerts in one day**, hour by hour. The fastest route if you have an interview tomorrow or a deadline today | 8 h |
| `01` | [`01-METRICS-FROM-ZERO.md`](01-METRICS-FROM-ZERO.md) | What a metric actually *is*. The four types (counter · gauge · histogram · summary), pull vs push, labels, cardinality and why cardinality is the number that decides whether your Prometheus survives | 2 h |
| `02` | [`02-PROMQL-FROM-ZERO.md`](02-PROMQL-FROM-ZERO.md) | The query language from `up` to `histogram_quantile`. Instant vs range vectors, `rate` vs `irate` vs `increase`, aggregation operators, `by`/`without`, vector matching, and the ten queries you will use every day | 4 h |
| `03` | [`03-HELM-MINIMUM-YOU-NEED.md`](03-HELM-MINIMUM-YOU-NEED.md) | **Just enough Helm** to install and customise a large chart safely: `repo add`, `show values`, `template`, `diff`, `upgrade --install`, `--atomic`, `rollback`. Everything beyond this lives in the Helm folder | 1.5 h |
| `04` | [`04-INSTALL-KUBE-PROMETHEUS-STACK.md`](04-INSTALL-KUBE-PROMETHEUS-STACK.md) | ⭐⭐ **THE file.** Step-by-step installation of `kube-prometheus-stack` — namespace, values file, install, verify every pod, `port-forward`, read your first dashboard, and the 9 things that go wrong on a first install | 3 h |
| `05` | [`05-INSIDE-THE-STACK-ARCHITECTURE.md`](05-INSIDE-THE-STACK-ARCHITECTURE.md) | Every component the chart deploys and *why*: Operator, Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, blackbox, admission webhooks — plus the **five CRDs** and how the Operator turns them into a real `prometheus.yaml` | 3 h |
| `06` | [`06-SERVICEMONITOR-PODMONITOR.md`](06-SERVICEMONITOR-PODMONITOR.md) | Scrape **your own** applications: `ServiceMonitor`, `PodMonitor`, `Probe`, `ScrapeConfig`, `PrometheusAgent`. Label selectors, relabeling (the thing everyone gets wrong), TLS, bearer tokens, and when to use which CRD | 4 h |
| `07` | [`07-INSTRUMENTING-THE-SHOP-APPS.md`](07-INSTRUMENTING-THE-SHOP-APPS.md) | ⭐ **Real instrumentation code** for every app in this workspace: Java/Micrometer (`shop-api`), Go (`checkout`, `payment-mock`), Python (`order-worker`), Node/Express (`mern-api`), and browser RUM for React (`shop-ui`, `mern-web`) | 5 h |
| `08` | [`08-RECORDING-AND-ALERTING-RULES.md`](08-RECORDING-AND-ALERTING-RULES.md) | `PrometheusRule` objects, rule groups, `for:` durations, labels and annotations, **recording rules** and why they are the fix for slow dashboards, and the four-question test for whether an alert is worth paging anyone | 3 h |
| `09` | [`09-ALERTMANAGER-ROUTING-RECEIVERS.md`](09-ALERTMANAGER-ROUTING-RECEIVERS.md) | The routing tree, matchers, `group_by`/`group_wait`/`group_interval`/`repeat_interval`, **inhibition**, silences, `AlertmanagerConfig` per-namespace, and real Slack / PagerDuty / email / webhook receivers | 3 h |
| `10` | [`10-GRAFANA-DASHBOARDS.md`](10-GRAFANA-DASHBOARDS.md) | Datasources, the dashboard sidecar, provisioning dashboards from git, template variables, mixed datasources, and building an **SLO dashboard** with error budgets rather than a wall of CPU graphs | 3 h |
| `11` | [`11-STORAGE-RETENTION-TSDB.md`](11-STORAGE-RETENTION-TSDB.md) | How the TSDB actually stores data: head block, WAL, compaction, 2-hour blocks. Retention vs retentionSize, **the sizing formula**, PVCs, and the complete cardinality-explosion debugging workflow | 3 h |
| `12` | [`12-SCALING-HA-THANOS-MIMIR.md`](12-SCALING-HA-THANOS-MIMIR.md) | When one Prometheus stops being enough: **HA replica pairs** and deduplication, sharding, federation, remote_write, and Thanos vs Cortex vs Mimir — with the decision matrix and the object-storage layout | 4 h |
| `13` | [`13-SECURITY-RBAC-MULTI-TENANCY.md`](13-SECURITY-RBAC-MULTI-TENANCY.md) | TLS between components, authenticating scrapes, ServiceAccount minimisation, **RBAC for the Operator**, NetworkPolicy, securing Grafana and the Prometheus UI, and multi-tenancy (per-team isolation, `external_labels`, enforced limits) | 3 h |
| `14` | [`14-PRODUCTION-TROUBLESHOOTING.md`](14-PRODUCTION-TROUBLESHOOTING.md) | ⭐⭐ **The 15 failures you will actually have**, each with symptoms → cause → exact fix: targets DOWN, duplicate series, `out-of-order sample`, OOMKilled Prometheus, gaps in graphs, alerts that never fire, alerts that never stop, and the debugging ladder that finds any of them in under ten minutes | 3 h |
| `15` | [`15-CAPSTONE-END-TO-END.md`](15-CAPSTONE-END-TO-END.md) | Build the whole thing for the `shop` platform: HA Prometheus, persistent storage, every app instrumented, SLO alerts, Grafana provisioned from git, Thanos for long-term storage, locked down with NetworkPolicy — on a cluster you create from nothing | 6 h |
| `16` | [`16-TASKS-AND-INTERVIEW.md`](16-TASKS-AND-INTERVIEW.md) | **40 hands-on tasks with full answers at the END**, plus 30 interview questions with the answers a 3+ YOE candidate gives — including the ones designed to catch people who have only ever run `helm install` | 6 h |
| `17` | [`17-PROMQL-COMPLETE-REFERENCE.md`](17-PROMQL-COMPLETE-REFERENCE.md) | ⭐ **One single reference file.** Every PromQL function, operator and aggregation; every `kubectl` command for the stack; every `promtool`/`amtool` subcommand; the HTTP API; and a copy-paste query library for the 25 questions you ask most | reference |

**Total: ~62 hours of focused work.** You do not need all of it to be useful — `04` alone gets you a working install in three hours.

---

## 🚦 Three reading orders, depending on why you are here

### ⏱️ "I need it running today"
```
03 (Helm minimum)  →  04 (install)  →  05 (architecture, skim)  →  06 (scrape your app)
```
**~7 hours.** You will have Prometheus scraping your own services with dashboards. Come back for the rest.

### 🎯 "I have an interview this week"
```
00 (one-day plan)  →  01 (metric types + cardinality)  →  02 (PromQL)  →  14 (troubleshooting)  →  16 (interview Q&A)
```
**~19 hours.** This is the order that survives "explain how Prometheus works" followed by "your dashboard has gaps — what do you check?"

### 🏗️ "I own monitoring for a real platform"
```
Read all 18 in order. Do not skip 11, 12 or 13 —
they are the three files that separate "installed Prometheus" from "runs Prometheus".
```
**~62 hours.** Build the capstone (`15`) on a throwaway cluster as you go; it is the file that turns reading into skill.

---

## 🧭 Where this folder sits in the whole workspace

```
docker-learning-path/            ← containers (do this first if you haven't)
        ↓
kubernetes-learning-path/        ← 18-PROJECT-15-mern-stack.md is the last project
        ↓  ⭐ P14-helm-gitops.md gives you Helm basics; P7-observability gives you the "why"
        ↓
helm-charts-mastery/             ← ⭐ the tool this folder installs with (sibling)
        ↓
prometheus-in-kubernetes/        ← 👈 YOU ARE HERE
        ↓
monitoring-alerting-learning-path/  ← Case 1 vs Case 2, and OpenTelemetry
        ↓
security-tools/                  ← Trivy · SonarQube · Checkov (sibling)
        ↓
cicd-learning-path/              ← pipelines that ship all of the above
```

**Continuity contract — the same `shop` application everywhere.** This folder instruments the exact apps you already built:

| Service | Stack | Port | Metrics endpoint |
|---|---|---|---|
| `shop-ui` | React 19 + nginx | 80 | ⭐ no server metrics — **browser RUM** instead |
| `shop-api` | Java 21 + Spring Boot 4.1 | 8080 | `/actuator/prometheus` (Micrometer) |
| `checkout` | Go 1.23 | 9091 | `/metrics` (`prometheus/client_golang`) |
| `order-worker` | Python 3.13 | 9092 | ⭐ **no HTTP surface** — heartbeat + pushgateway or a sidecar |
| `payment-mock` | Go 1.23 | 9093 | `/metrics` — the ideal canary target |
| `mern-web` | React 19 + nginx | 80 | browser RUM |
| `mern-api` | Node 24 + Express 5 | 4000 | `/metrics` (`prom-client`) |
| `mern-mongo` | MongoDB 8.0 (replica set ×3) | 27017 | ⭐ `mongodb_exporter` — third-party exporter |

Images live at `ghcr.io/3558bhk/<svc>`. Namespaces: `shop-dev`, `shop-staging`, `shop-production`, `shop-canary`. This folder installs into **`monitoring`**.

---

## 📋 Prerequisites

| You need | Check it with | If not |
|---|---|---|
| A Kubernetes cluster ≥ 1.34 | `kubectl version` | `kind create cluster --name prom` (free, local) |
| `kubectl` configured | `kubectl get nodes` → a Ready node | [`../kubernetes-learning-path/`](../kubernetes-learning-path/README.md) files 04–07 |
| **Helm v3.21+** | `helm version` | [`03-HELM-MINIMUM-YOU-NEED.md`](03-HELM-MINIMUM-YOU-NEED.md) installs it |
| ≥ 4 GB free RAM on the cluster | `kubectl top nodes` | ⭐ The default stack needs ~2 GB. File `04` shows the low-memory values |
| A `StorageClass` that provisions PVCs | `kubectl get storageclass` | kind: install `local-path-provisioner`; cloud: it exists by default |
| Comfortable with `rate()` | — | [`02-PROMQL-FROM-ZERO.md`](02-PROMQL-FROM-ZERO.md) |

⭐ **The one people skip and regret:** a `StorageClass`. Without it, Prometheus silently runs with an `emptyDir` and **loses every metric on every pod restart** — which looks identical to "Prometheus keeps forgetting history". File `04` step 2 makes you verify this before you install.

---

## ⭐ The six ideas this folder keeps returning to

Learn these and the rest is detail.

1. **Prometheus pulls; it does not receive.** Every consequence — service discovery, relabeling, short-lived jobs being awkward, pushgateway existing at all — follows from this one design choice.
2. **A metric is a *time series*, and a time series is a name plus a label set.** Two series differing by one label value are two series. That is why **cardinality** — the count of distinct label combinations — is the number that decides whether your Prometheus costs 2 GB or 200 GB.
3. **You almost never want the raw value.** Counters only make sense as `rate()`. Histograms only make sense as `histogram_quantile()`. Gauges only make sense with `avg_over_time()` or a comparison. File `02` is entirely about this.
4. **An alert should describe a symptom a user would notice, not a cause.** `CPU > 90%` is not an alert; `checkout p99 latency above SLO for 5 minutes` is. File `08` gives you the four-question test.
5. **Configuration in Kubernetes is a CRD, not a file.** You never edit `prometheus.yaml`. You create a `ServiceMonitor` and the Operator writes the file for you. Understanding *that reconciliation loop* is the difference between using the stack and fighting it (file `05`).
6. **Monitoring is a production system.** It needs storage sizing, retention policy, HA, RBAC, NetworkPolicy, backup of its own state, and an upgrade plan. Files `11`–`13` are why this folder is 18 files long and not 4.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
