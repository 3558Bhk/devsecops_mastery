# 📊 Monitoring & Alerting — Complete Learning Path

> **Two cases. One production-grade observability platform.** Built from scratch on Kubernetes, with the same "shop" application used across the Docker and Kubernetes paths so everything connects.
>
> - **CASE 1 — Prometheus + Grafana** → metrics, dashboards, alerting, SLOs
> - **CASE 2 — Telemetry (OpenTelemetry)** → traces, logs, the Collector, correlation, auto-instrumentation

---

## Who this is for

You're a **complete beginner** to observability. You may have heard "we use Prometheus" and "we have Grafana dashboards" but never built any of it. This path assumes **zero** prior knowledge of metrics, PromQL, tracing, or OpenTelemetry.

By the end you will be able to:

- Instrument an application so it **exposes its own metrics** (and know why that beats scraping logs)
- Deploy and operate **Prometheus, Alertmanager, Grafana, node_exporter, blackbox_exporter**
- Write **PromQL** confidently — rates, percentiles, histograms, recording rules
- Design **alerts that don't wake people up for nothing** (symptom-based, multi-window, burn-rate)
- Define and measure **SLIs, SLOs and error budgets**
- Instrument an app with **OpenTelemetry** in Java, Python, Go and JavaScript
- Run the **OpenTelemetry Collector** — receivers, processors, exporters, pipelines
- Ship traces to **Jaeger/Tempo** and logs to **Loki**, and **correlate all three signals**
- Auto-instrument a whole namespace with the **OpenTelemetry Operator**
- Debug a real production incident using metrics → traces → logs in that order

---

## 📁 What's in this folder

| # | File | What you get | Time |
|---|---|---|---|
| 00 | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) | ⏰ Hour-by-hour plan to do BOTH cases in one day | — |
| 01 | [01-OBSERVABILITY-GUIDE.md](./01-OBSERVABILITY-GUIDE.md) | 📖 The foundation guide — every concept from zero | 3–4 h read |
| 02 | [02-CASE-1-prometheus-grafana.md](./02-CASE-1-prometheus-grafana.md) | 🔥 **CASE 1** — Prometheus + Grafana + Alertmanager, end to end | 6–8 h |
| 03 | [03-CASE-2-telemetry.md](./03-CASE-2-telemetry.md) | 🛰️ **CASE 2** — OpenTelemetry: traces, logs, the Collector | 6–8 h |
| 04 | [04-CAPSTONE-END-TO-END.md](./04-CAPSTONE-END-TO-END.md) | 🏆 The capstone — both cases unified on one app, tasks + answers at the END | 4–6 h |
| 05 | [05-CHEATSHEET.md](./05-CHEATSHEET.md) | ⚡ PromQL + Grafana + Alertmanager + OTel on one page | reference |

**Every file ends with the same footer and is self-contained** — you can read any one of them alone.

---

## 🔀 The order to read them

```
        ┌──────────────────────────────────────────┐
        │  01 — OBSERVABILITY GUIDE                │  ← read this FIRST
        │  the three pillars · metrics types ·     │     (or skim, then come back)
        │  PromQL · alerting theory · SLOs · OTel  │
        └───────────────────┬──────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
   ┌────────────────────┐      ┌────────────────────┐
   │ CASE 1             │      │ CASE 2             │
   │ Prometheus+Grafana │      │ Telemetry / OTel   │
   │ 02-…               │      │ 03-…               │
   │                    │      │                    │
   │ metrics · scrape   │      │ traces · spans     │
   │ PromQL · dashboards│      │ Collector · OTLP   │
   │ alerts · SLOs      │      │ Jaeger/Tempo·Loki  │
   └─────────┬──────────┘      └─────────┬──────────┘
             │                           │
             └─────────────┬─────────────┘
                           ▼
              ┌────────────────────────┐
              │ 04 — CAPSTONE          │
              │ both, unified          │
              │ exemplar correlation   │
              │ on-call runbook        │
              └────────────┬───────────┘
                           ▼
                   ┌───────────────┐
                   │ 05 CHEATSHEET │  ← keep open forever
                   └───────────────┘
```

**If you only have one day:** follow [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md).
**If you only have two hours:** Case 1, Steps 1–5.
**If you're preparing for an interview:** the Guide's §10–§12 plus each Case's Tasks & Answers.

---

## 🧰 Tools & versions used

Everything below is what this path was written against. Later patch versions are fine; a different **major** version may need small changes.

| Tool | Version | What it does | Where |
|---|---|---|---|
| **Kubernetes** | v1.35 – v1.37 | The platform | Case 1 & 2 |
| **kind** | v0.29+ | The local cluster (recommended) | Case 1 & 2 |
| **Helm** | v3.17 | Package manager | Case 1 & 2 |
| **Prometheus** | **v3.13** | Metrics TSDB + scraper + alert evaluator | Case 1 |
| **kube-prometheus-stack** | chart 72.x | Prometheus + Grafana + Alertmanager + exporters, in one Helm release | Case 1 |
| **Grafana** | **v12.3+** | Dashboards & alerting UI | Case 1 & 2 |
| **Alertmanager** | v0.28 | Dedup, group, route, silence, notify | Case 1 |
| **node_exporter** | v1.9 | Host metrics (CPU, memory, disk, net) | Case 1 |
| **kube-state-metrics** | v2.15 | Kubernetes object state as metrics | Case 1 |
| **blackbox_exporter** | v0.26 | Probe an endpoint from outside | Case 1 |
| **prometheus-adapter** | v0.12 | Serves custom metrics to the HPA | Case 1 |
| **OpenTelemetry Collector** | **v0.158.0** | The telemetry pipeline | Case 2 |
| **OpenTelemetry Operator** | v0.9x | Auto-instrumentation + Collector CRDs | Case 2 |
| **Grafana Alloy** | **v1.19** | Grafana's OTel Collector distribution | Case 2 (optional) |
| **Grafana Tempo** | v2.6 | Trace storage | Case 2 |
| **Jaeger** | v2.x | Trace storage + UI (alternative to Tempo) | Case 2 |
| **Grafana Loki** | **v3.7** | Log storage | Case 2 |
| **OTel SDKs** | Java 2.x agent, Python 1.3x, Go 1.5x, JS 1.3x | Instrumentation | Case 2 |
| **Pyroscope** | v1.1x | Continuous profiling (bonus) | Capstone |
| **sloth** | v0.13 | Generate SLO recording rules + alerts from YAML | Case 1 |

```bash
# verify your toolchain
kubectl version --short 2>/dev/null || kubectl version
helm version --short
kind version
docker version --format '{{.Server.Version}}'
java -version 2>&1 | head -1        # for the Java auto-instrumentation demo
python3 --version                   # for the Python demo
go version                          # for the Go demo
node --version                      # for the JS demo
```

---

## 🎯 The application you'll observe

Both cases use the same three-service app, so the concepts land on something realistic:

```
                        ┌──────────────┐
       browser ───────► │  shop-ui     │  React (nginx)          port 80
                        └──────┬───────┘
                               │ /api/*
                        ┌──────▼───────┐
                        │  shop-api    │  Spring Boot (Java 21)  port 8080
                        │              │  /metrics  port 9090  ◄── Prometheus scrapes
                        │              │  OTLP    :4317/4318   ──► Collector
                        └───┬──────┬───┘
                            │      │
                  ┌─────────▼─┐  ┌─▼──────────┐
                  │ postgres  │  │ redis      │   port 5432 / 6379
                  │ (exporter)│  │ (exporter) │   ◄── Prometheus scrapes
                  └───────────┘  └────────────┘
```

| Service | Language | Metrics endpoint | Trace instrumentation |
|---|---|---|---|
| `shop-ui` | React / nginx | nginx-prometheus-exporter | OTel JS auto-instrumentation |
| `shop-api` | Spring Boot 3 / Java 21 | `/actuator/prometheus` | **OTel Java agent** (zero-code) |
| `order-worker` | Python 3.13 | `/metrics` (prometheus-client) | **OTel Python auto-instrumentation** |
| `checkout` | Go 1.23 | `/metrics` (promhttp) | OTel Go SDK (manual) |

**You don't have to write these apps** — each Case file gives you complete, copy-pasteable source and manifests. If you've done the [Kubernetes path](../kubernetes-learning-path/README.md) you can reuse your `shop-api` from Projects 9–12.

---

## 📈 What "done" looks like

At the end of Case 1 you will have, running locally:

```
✅ Prometheus scraping 12+ targets, 15-second intervals
✅ Grafana with 8 dashboards: Kubernetes / compute / pods, API server, etcd,
   kubelet, node exporter, your app's RED metrics, and a custom SLO dashboard
✅ Alertmanager routing to Slack + email + PagerDuty-style receivers,
   with inhibition, silences and 5 alert groups
✅ 23 alert rules: symptom-based, multi-window burn-rate for SLOs
✅ Recording rules pre-computing your RED and USE metrics
✅ A working HPA driven by a custom metric from prometheus-adapter
✅ You can answer "what is the p99 latency of POST /api/orders over the last hour"
   from memory, in PromQL, without looking it up
```

At the end of Case 2 you will have:

```
✅ The OTel Collector deployed as a Gateway AND as a DaemonSet agent
✅ Zero-code auto-instrumentation of Java, Python and Node via the OTel Operator
✅ Manual instrumentation of a Go service (spans, attributes, events, links)
✅ Trace propagation across HTTP, a message queue and a database call
✅ Traces in Tempo/Jaeger, queryable from Grafana with TraceQL
✅ Logs in Loki with trace_id and span_id injected — click a log, jump to the trace
✅ Metrics exemplars — click a point on a latency graph, jump to the exact trace
✅ Tail-based sampling: keep 100% of errors and slow traces, 10% of the rest
✅ A single dashboard where all three signals are one click apart
```

At the end of the capstone you'll be able to run this drill and win:

> *"Checkout latency spiked at 14:32. Find the root cause in under 5 minutes using only dashboards."*

---

## ⚠️ Before you start

| Thing | Detail |
|---|---|
| **RAM** | The full stack (Prometheus + Grafana + Alertmanager + Tempo + Loki + Collector + app) needs **8 GB free**. Give Docker Desktop / kind at least 10 GB. |
| **Disk** | Prometheus + Loki + Tempo will write several GB. `kind` stores it inside the node container. |
| **Ports** | 3000 (Grafana), 9090 (Prometheus), 9093 (Alertmanager), 3100 (Loki), 3200 (Tempo), 16686 (Jaeger), 4317/4318 (OTLP) — all via `kubectl port-forward`. |
| **Time** | Case 1 ≈ 6–8 h, Case 2 ≈ 6–8 h, Capstone ≈ 4–6 h. The one-day plan compresses this to ~12 focused hours. |
| **Not runnable in a browser** | Everything runs on **your machine**. You need Docker, kind (or minikube), kubectl and Helm installed. |
| **Cost** | $0. Every tool here is open source. The cloud-vendor equivalents (CloudWatch, Azure Monitor, Datadog, New Relic) are mapped in Guide §14 so you can translate. |

```bash
# give kind enough room
docker info | grep -i 'total memory'
# and if you use Docker Desktop: Settings → Resources → Memory → 10 GB+
```

---

## 🔗 Related paths

| Path | Folder |
|---|---|
| 🐳 Docker — the complete learning path | `../docker-learning-path/` |
| ☸️ Kubernetes — the complete learning path | `../kubernetes-learning-path/` |
| 🚦 CI/CD — Azure DevOps, GitHub Actions, Jenkins | `../cicd-learning-path/` |

The observability stack you build here is deployed by the pipelines in the CI/CD path, and observes the containers from the Docker path running on the cluster from the Kubernetes path. **They're one system.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
