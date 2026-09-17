# Monitoring & Alerting — Mastery Track

> Cloud-native focus: **Prometheus · Alertmanager · Grafana · Kubernetes**, with concepts that transfer to any stack.
> One topic = one folder = one `README.md`. Read them in order, run the labs, tick the self-checks.

---

## How this course is organised

```
Monitoring and Alerting/
├── README.md                          ← you are here (roadmap + index)
├── 00-Start-Here/README.md            How to use this repo, prerequisites, 30-day plan
├── 01-Monitoring-Fundamentals/        What monitoring is, golden signals, USE/RED, anti-patterns
├── 02-Prometheus-Core/         ★      Architecture, TSDB, scraping, service discovery, relabeling
├── 03-Metrics-and-Instrumentation/    Metric types, naming, exporters, instrumenting your own app
├── 04-PromQL/                  ★      Query language from zero to production-grade
├── 05-Alerting-Concepts-and-Best-Practices/ ★  Symptom vs cause alerts, severity, alert fatigue
├── 06-Alertmanager/            ★      Routing, grouping, inhibition, silences, templates, receivers
├── 07-Grafana-Dashboards/      ★      Dashboards, variables, provisioning, alerting UI
├── 08-Kubernetes-Monitoring/   ★      Prometheus Operator, CRDs, kube-state-metrics, cAdvisor
├── 09-SLOs-and-Error-Budgets/  ★      SLI/SLO/SLA, error budgets, multi-window burn-rate alerts
├── 10-Logging-and-Tracing/            Loki, OpenTelemetry, exemplars, metrics↔logs↔traces
├── 11-Scaling-and-Long-Term-Storage/  Thanos/Mimir/VictoriaMetrics, cardinality, HA, cost
├── 12-On-Call-and-Incident-Response/  Rotations, escalation, runbooks, postmortems
├── 13-Alert-Rules-Library/     ★      Copy-paste production rule files (node, k8s, app, SLO)
├── 14-Cheatsheets/                    One-page reference cards
├── 15-Interview-Prep/                 80+ Q&A with model answers
└── 16-Labs/                    ★      Working docker-compose stack + 6 guided labs
```

`★` = deep-dive topic (long README with configs + lab exercises). Everything else is concise but complete.

---

## The 30-day mastery plan

| Week | Focus | Read | Do |
|---|---|---|---|
| **1** | Foundations + the tool | `01`, `02`, `03`, `04` | Labs 1–3 in `16-Labs` |
| **2** | Alerting properly | `05`, `06`, `13` | Labs 4–5, write 5 rules of your own |
| **3** | Dashboards + SLOs | `07`, `09`, `08` | Lab 6, build an SLO dashboard |
| **4** | Production hardening | `10`, `11`, `12`, `14`, `15` | Design doc + mock interview |

**Rule of thumb:** don't move on from a topic until its *Self-check* section at the bottom of the README is 100%. Reading alone does not build this skill — running `promtool`, breaking a service, and watching an alert fire does.

---

## The one-paragraph summary of the whole subject

Monitoring answers *"is my system healthy and what is it doing?"*; alerting answers *"who needs to wake up, right now, and why?"*. You collect three kinds of telemetry — **metrics** (cheap numbers over time, best for alerting), **logs** (expensive discrete events, best for root cause), **traces** (request paths across services, best for latency) — and you turn them into **SLIs** (a measured ratio like "good requests ÷ valid requests"), which you commit to as **SLOs** (e.g. 99.9% over 28 days), whose slack is the **error budget**. You alert on **symptoms users feel** (availability, latency, saturation) rather than on every **cause** (CPU high, a pod restarted), you route alerts through a system that **groups** related alerts, **inhibits** noise, and only **pages a human** when a runbook action is required. Everything else in this folder is detail in service of those two sentences.

---

## Prerequisites

Comfortable with: Linux CLI, YAML, HTTP, and either Docker or Kubernetes basics. No prior observability experience needed.

## Versions used in this material

| Component | Version referenced | Notes |
|---|---|---|
| Prometheus | **3.14** (LTS: 3.13) | First major release since 2.0; UTF-8 names, OTLP receiver, Remote Write 2.0 |
| Alertmanager | **0.34** | `time_intervals` (not `mute_time_intervals`), UTF-8 matchers |
| Grafana | **13.x** | Prometheus data source is now a standalone plugin from 13.2 |
| node_exporter | **1.12** | |
| kube-prometheus-stack | **85.x** | Operator 0.90.x, Prometheus 3.11+ |

Always confirm current versions at [prometheus.io/download](https://prometheus.io/download/) and [grafana.com/docs](https://grafana.com/docs) — the concepts here are version-stable, the flags occasionally are not.

## Canonical sources (bookmark these)

- Prometheus docs & PromQL reference — https://prometheus.io/docs/
- Alertmanager configuration — https://prometheus.io/docs/alerting/latest/configuration/
- Notification template reference — https://prometheus.io/docs/alerting/latest/notifications/
- Google SRE Workbook (alerting + SLO chapters) — https://sre.google/workbook/
- Prometheus Operator API — https://prometheus-operator.dev/docs/api-reference/
- Grafana docs — https://grafana.com/docs/grafana/latest/
- OpenTelemetry — https://opentelemetry.io/docs/

---

*Built as a study workspace. Edit freely, add your own rules to `13-Alert-Rules-Library`, and keep a lab journal in `16-Labs`.*
