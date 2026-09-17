# 13 · Backends & Storage

OTel produces and moves telemetry; **something else has to store, query and alert on it.** Choosing that something is an architecture decision with cost and operational consequences that outlast the choice of instrumentation.

*Versions cross-checked in this workspace's `Monitoring and Alerting/` folder: **Prometheus 3.14.0** (LTS 3.13.3), **Alertmanager 0.34.0**, **Grafana 13.x**. Trace/log backend versions move fast — check current releases before committing.*

---

## 13.1 What each signal actually needs from storage

The three signals have genuinely different access patterns, which is why no single store does all three well.

| | **Metrics** | **Traces** | **Logs** | **Profiles** |
|---|---|---|---|---|
| Shape | Numeric time series | Trees of spans | Append-only records | Sampled stacks over a window |
| Write pattern | Regular intervals, aggregates | Bursts per request | High volume, bursty | Regular sampling |
| Cardinality driver | ★ **Label combinations** | ★ **Span names + attributes** | Volume × retention | Sample rate × process count |
| Primary query | Range queries, aggregation over time | **Point lookup by `trace_id`**, then search by attribute | Full-text or field search, time-bounded | Function-level aggregation, **diff between two windows** |
| Secondary query | Instant lookup | Service map, dependency analysis | Context around a known time | Flame graph |
| Data lifecycle | Downsample over time | Short retention; **most never read** | Tiered hot→cold | Short; aggregate to trends |
| Compression | Excellent (delta-of-delta, XOR) | Good | Good | ★ **Very good — shared string dictionary** |
| What breaks it | Cardinality explosion | Unbounded span names, huge traces | DEBUG in production, no dedup | Symbol resolution quality |

★ **The single most useful insight for backend selection:** *"most traces are never read."* You store thousands of traces a second and a human looks at maybe ten a day — almost always reached **from** a log line or a metric spike. That means the economically correct trace store optimises for **cheap bulk storage plus fast point lookup by ID**, not for full-text search across all attributes. Everything else is a luxury you pay for whether or not you use it.

---

## 13.2 Metrics backends

### Prometheus (and the long-term-store family)
**Versions verified: Prometheus 3.14.0, LTS 3.13.3, Alertmanager 0.34.0.**

| Property | Detail |
|---|---|
| Ingest from OTel | ★ **Three paths** — see [`06-metrics.md`](06-metrics.md): scrape the Collector's `prometheus` exporter, remote-write from `prometheus_remote_write`, or have the Collector scrape with the `prometheus` receiver |
| Temporality | **Cumulative only.** Feed it delta and you get silently wrong values |
| Naming | ★ **Transforms your metric names**: dots → underscores, and **suffixes added by default** (`_total`, `_seconds`, `_bucket`). `http.server.request.duration` becomes `http_server_request_duration_seconds_bucket` |
| Exponential histograms | Not native — converted on export |
| Exemplars | Supported — **the metric→trace bridge** |
| Query | PromQL |
| Alerting | Alertmanager (not Prometheus itself) |

**Long-term / horizontal-scale options:**
| System | Model | Choose when |
|---|---|---|
| **Mimir** | Remote-write target, horizontally scalable, multi-tenant | You want Prometheus-compatible PromQL at scale with tenant isolation |
| **Thanos** | Sidecar + object storage over existing Prometheus | You already run Prometheus and want global query + long retention |
| **VictoriaMetrics** | Own storage engine, PromQL-compatible | Best raw price/performance for very high series counts; less ecosystem-standard |
| **Cortex** | Mimir's predecessor | Legacy |
| **CloudWatch / Azure Monitor / Cloud Monitoring** | Native cloud | Committed to one cloud; ★ **these want delta temporality** |

★ **The Prometheus `up` metric gap, again:** pull gives you `up == 0` for free when a target dies. **Push-based OTel gives you silence, which is indistinguishable from "no traffic."** Compensate with `absent()`/`absent_over_time()` alerts on the metrics you expect, a heartbeat metric, and `otelcol_receiver_refused_*` / `otelcol_exporter_send_failed_*`. This is a real design consequence of choosing push, not a deficiency to work around carelessly.

### The metrics-backend decision
| Need | Answer |
|---|---|
| Single cluster, < ~1M active series | **Prometheus alone.** Don't add complexity |
| Multi-cluster, global query, long retention | **Thanos** (if Prometheus-first) or **Mimir** (if remote-write-first) |
| Very high cardinality, cost-sensitive | **VictoriaMetrics** |
| Multi-tenant SaaS-style isolation | **Mimir** |
| Already all-in on one cloud | Its native metrics service — but check temporality |

---

## 13.3 Trace backends

### Grafana Tempo
| Property | Detail |
|---|---|
| Storage | **Object storage** (S3, GCS, Azure Blob) + a compact index of `trace_id → block` |
| Search | ★ **Brute-force scan of recent blocks** for attribute-based search; point lookup by ID is index-fast |
| Dependencies | Object store, plus a distributor/ingester/compactor/query-frontend topology |
| Cost per GB | **Dramatically lower** than index-everything systems |
| Query language | TraceQL |
| Service map | Derived; can also come from the Collector's `service_graph` connector |

★ **Tempo's entire design bet is the "most traces are never read" insight.** It refuses to build a full secondary index, which is why it's cheap. **The trade-off you accept:** attribute search over a wide time range is slower than Elasticsearch-backed Jaeger, and expensive searches can be rate-limited. If your workflow is "click from a log or metric exemplar to a trace ID" — which is the overwhelmingly common workflow — **you never notice**.

**Choose Tempo when:** you're on Grafana, cost matters, and your trace lookups are ID-driven.
**Don't when:** your primary workflow is complex multi-attribute trace search across weeks of data.

### Jaeger
| Property | Detail |
|---|---|
| Storage | **Pluggable**: Cassandra, Elasticsearch/OpenSearch, Badger (local) |
| Ingest | ★ **Native OTLP** — Jaeger accepts OTLP directly on 4317/4318. Jaeger's own protocols are legacy; **the project has converged on OTel** |
| Search | Full index → **fast arbitrary attribute search** |
| Cost | Higher per GB than Tempo; Elasticsearch/Cassandra is operationally heavy |
| Sampling | Built-in **adaptive sampling** (the Collector's `jaegerremotesampling` extension can serve these strategies) |

★ **The historically important fact:** Jaeger and OTel merged efforts. Jaeger now uses OTLP as its primary ingest and OTel SDKs for its own instrumentation. **"Jaeger vs OpenTelemetry" is a stale framing** — Jaeger is a *backend*, OTel is the *producer*, and they're designed to work together. The Collector's `jaeger` receiver exists mainly for **legacy producers** still emitting Jaeger thrift/protobuf.

**Choose Jaeger when:** you need fast arbitrary trace search, you already operate Cassandra or Elasticsearch, or you want adaptive sampling.

### ClickHouse-based (SigNoz, Uptrace, HyperDX, and DIY)
| Property | Detail |
|---|---|
| Storage | **Columnar** — excellent compression, excellent analytical queries |
| Query | **SQL** |
| Killer feature | ★ **Traces, logs and metrics in one engine, joinable with SQL** |
| Cost | Very competitive per GB |
| Maturity | Growing fast; several credible products |

★ **The argument for ClickHouse:** if you want to answer *"show me all traces from tenant X where the DB call exceeded 200 ms and the log contains 'deadlock', in the last hour"* — that's a **join across signals**, and a single columnar engine does it far more naturally than three specialised stores. The argument against: you now operate ClickHouse, and you lose the best-of-breed tooling per signal.

### Vendor APMs
Every major vendor accepts OTLP now — **Datadog, Honeycomb, New Relic, Dynatrace, Elastic, Splunk, Grafana Cloud, AWS X-Ray, Azure Monitor, Google Cloud Trace**.

| Property | Detail |
|---|---|
| Ingest | OTLP/HTTP is the common path (★ **HTTP, not gRPC** — proxies, WAFs and LBs handle it correctly) |
| Auth | API key in a header, via the Collector's `basicauth`/`bearertokenauth`/`headers_setter` extensions |
| Value added | **Pre-aggregated service maps, anomaly detection, retention tiers, dashboards, alerting, support** |
| Cost model | ★ **Per-span / per-GB / per-host, and it compounds.** Ingest-based pricing means your sampling policy *is* your budget |
| Lock-in | Low at the protocol level (OTLP), **high at the query and dashboard level** |

★ **The honest vendor trade-off:** you pay several times the self-hosted cost, and you get back **operational capacity**. A team that would spend 0.5 FTE running Tempo/Mimir/Loki may come out ahead paying a vendor. A team with a strong platform function usually comes out ahead self-hosting. **The decision should be made on engineer-time, not on licence price.**

**The second honest point:** vendor dashboards and query languages are the actual lock-in. OTLP means your *data* is portable; your *queries, alerts and muscle memory* are not. **Budget for that in any migration.**

---

## 13.4 Log backends

### Grafana Loki
| Property | Detail |
|---|---|
| Indexing | ★ **Labels only, not log content.** Content is compressed into object storage and grepped |
| Ingest from OTel | ★ **Native OTLP** — POST to `/otlp/v1/logs`. **There is no `loki` exporter in Collector v0.161.0** (`loki` is a *receiver* only); use the `otlphttp` exporter with `endpoint: http://loki:3100/otlp` |
| Query | LogQL — label selectors + line filters + parsed-field extraction at query time |
| Cost | **Low**, driven by volume and label cardinality |
| Full-text search | ★ **Slow at scale** — it's a scan, not an index lookup |

★ **The Loki design bet mirrors Tempo's:** don't index content. It's cheap and fast for *"show me ERROR logs from service X in namespace Y in the last 15 minutes"* — because those are **label** queries. It's slow for *"find every log in 30 days containing this order ID"* — because that's a **content scan**.

**The practical consequence for design:** put your high-value query dimensions in **labels** (`service.name`, `deployment.environment.name`, `k8s.namespace.name`, `severity`), and accept that anything else is a scan. ★ **And never put high-cardinality values in labels** — Loki's cardinality limits are real and a single bad label (`trace_id`, `user_id`) can destabilise the whole store. **`trace_id` belongs in the log line as a parsed field, not as a label.**

### Elasticsearch / OpenSearch
| Property | Detail |
|---|---|
| Indexing | **Full inverted index on content** |
| Query | Arbitrary full-text and field search, fast, at any scale |
| Cost | ★ **High** — index size often exceeds raw log size; hot storage on fast disks |
| Operations | Cluster management, shard sizing, index lifecycle, JVM tuning. **A real operational discipline** |

**Choose it when:** arbitrary full-text search across all logs is a **primary** use case — security investigation, compliance search, support teams searching by customer email. **Don't when:** you mostly search by service and time window, which is what most engineering teams actually do.

### ClickHouse / object storage / cloud log services
ClickHouse gives you SQL over logs cheaply (and joins with traces). Raw object storage with Athena/BigQuery gives you the cheapest possible cold-tier search. CloudWatch Logs / Azure Monitor Logs / Cloud Logging are the zero-operations options with per-GB pricing that gets expensive at volume.

---

## 13.5 The three reference architectures

### A. The Grafana OSS stack (most common self-hosted choice)
```
apps → Collector (agent DaemonSet) → Collector (gateway) →
        ├── traces   → Tempo        → object storage
        ├── metrics  → Mimir/Prom   → object storage / local TSDB
        └── logs     → Loki         → object storage
                              Grafana (datasources wired for exemplars + derived fields)
```
| Pros | Cons |
|---|---|
| ★ **One object-storage bill**, one query UI, one alerting path | You operate Tempo + Mimir + Loki + Grafana |
| **Exemplars and derived-field linking work out of the box** once configured | Search is scan-based — slower for arbitrary queries |
| Cheapest per GB of any credible option | No anomaly detection, no pre-built service insights |
| Every component is CNCF/AGPL, no licence risk | Requires real platform engineering capacity |

★ **This stack's coherence is its main selling point**: one mental model (object storage + a query layer per signal), one UI, and — critically — **the metric→trace→log triangle is a first-class design goal** rather than an integration project.

### B. The vendor stack
```
apps → Collector (gateway) → vendor OTLP/HTTP endpoint
```
| Pros | Cons |
|---|---|
| Zero storage operations | ★ **Cost compounds with volume**; sampling policy = budget |
| Dashboards, service maps, anomaly detection on day one | Query/dashboard lock-in even with OTLP ingest |
| Support and SLAs | Egress charges if crossing clouds/regions |
| Fastest time to value | Feature requests go on someone else's roadmap |

**Still run a Collector**, even here. It's where redaction, cardinality control, sampling and dual-shipping live — and it's what makes leaving possible later.

### C. The hybrid (what most mature organisations converge on)
```
apps → Collector agent → Collector gateway →
        ├── traces  → vendor APM      (for the UX + on-call experience)
        ├── metrics → Prometheus/Mimir (for alerting you control)
        └── logs    → Loki + object storage archive (cheap retention, vendor for search)
```
★ **The logic:** each signal goes where it's cheapest *for its access pattern*. Metrics you alert on must be in a system you control (a vendor outage shouldn't blind your alerting). Traces benefit most from vendor UX during incidents. Logs are volume-dominated, so cheap storage wins, with a vendor for the occasional deep search.

**The cost of hybrid:** three systems, three query languages, and **cross-signal linking becomes your job**. Budget for it.

---

## 13.6 Retention, tiering and lifecycle

| Signal | Typical hot | Warm | Cold / archive | Notes |
|---|---|---|---|---|
| **Metrics** | 2–15 days at full resolution | 90 days downsampled (5m→1h) | 1–7 years | ★ **Downsampling is the biggest metric cost lever** — 15s resolution for a year is almost never what you need |
| **Traces** | **3–14 days** | — | Rare | Most traces are never read. Long retention is usually waste |
| **Logs** | 7–30 days searchable | 90 days | **400 days – 7 years** in object storage | Driven by compliance, not by engineering need |
| **Profiles** | Days | — | — | Aggregate into trends rather than retaining raw |

★ **Retention questions that are actually compliance questions:** "why do we keep logs for 400 days?" almost always has an answer like PCI-DSS, SOC 2, HIPAA or a customer contract. **Find out before you optimise** — cutting retention that a control depends on is a finding, not a saving. And the reverse: **retention "because it's the default" is the most common waste in observability.**

**Object storage is the answer for cold tiers**, and it's why Tempo/Loki/Thanos/Mimir all use it. `s3://bucket/prefix` at ~$0.023/GB/month versus EBS at ~$0.08–0.10 changes the economics by 4×, and lifecycle policies (Glacier/Deep Archive) take it lower still. ★ **Make cold-tier data actually retrievable** — an archive nobody can query is just a bill.

---

## 13.7 What to check before committing

A pre-decision checklist, because these are expensive to change:

1. **Ingest protocol and auth.** Does it accept OTLP natively, gRPC or HTTP or both? How do credentials get in — Collector extension, header injection, mTLS?
2. **Temporality requirement.** Cumulative or delta? ★ **Mismatch here is silent and total.**
3. **Name transformation.** Will it rename your metrics? Add suffixes? Strip resource attributes? **Write down the mapping before you build dashboards.**
4. **Cardinality limits.** Hard per-tenant limits, per-metric limits, or none? What happens when you hit them — reject, drop, or aggregate into an overflow bucket? ★ **A backend that silently rejects high-cardinality data will look like data loss.**
5. **Per-trace and per-request size limits.** Maximum spans per trace, maximum attribute length, maximum request body. **A 6-hour batch job as one span will hit these.**
6. **Retention configurability.** Per-signal? Per-tenant? Can you tier?
7. **Query capability for your actual questions.** Write down the ten queries you'll run in an incident and check each one is fast. ★ **Not "does it have a query language" but "is *my* query fast."**
8. **Cross-signal linking.** Exemplars (metric→trace), derived fields (log→trace), trace→logs. **If you have to build this yourself, cost it in.**
9. **Multi-tenancy.** Namespace/team isolation, per-tenant quotas and cost attribution.
10. **Egress and data-residency.** Where does the data physically live? Does it cross borders? ★ **A compliance question that becomes an architecture constraint.**
11. **Economics at 3× volume.** Every backend is affordable at your current volume. **Model the cost at 3× and 10×** — that's where the design breaks.
12. **Exit cost.** If you leave in two years, what do you lose? Data export? Dashboards? Alerts? Query muscle memory?
13. **Operational load, honestly.** Who runs it at 3am? What's the upgrade cadence? Is there anyone on your team who has done it before?
14. **Vendor viability / project health.** For OSS: commit activity, release cadence, CNCF status. For vendors: funding, direction, pricing history.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Choosing a backend before writing down your ten incident queries | You optimise for a workflow you don't have |
| Feeding delta temporality to Prometheus | Silently wrong values |
| Building dashboards before learning the name transformation | `_total`/`_seconds`/`_bucket` suffixes mean your queries return nothing |
| Full-text-indexing all logs "because we might search them" | ★ Usually the largest line item in the observability bill, for searches that never happen |
| `trace_id` as a Loki/label value | Cardinality explosion in a store designed for low-cardinality labels |
| Long trace retention because it's cheap | Cheap ≠ free, and most traces are never read |
| Retention defaults nobody reviewed | Paying for data with no owner and no requirement |
| Cutting retention without checking compliance | An audit finding, not a saving |
| Skipping the Collector and pointing SDKs at a vendor | No redaction, no cardinality control, no dual-shipping, and leaving is a code change in every service |
| Choosing per-GB pricing without modelling 3× volume | The design breaks at the first growth spurt |
| Assuming OTLP means zero lock-in | **Data** is portable; queries, dashboards, alerts and muscle memory are not |
| Putting vendor-only alerting on the critical path | A vendor outage blinds your incident detection |
| Archiving to object storage with no retrieval path | A bill, not a capability |
| Running full contrib Collectors to feed a vendor that only needs OTLP | Attack surface and cost for nothing — use `otelcol` core or an OCB build |

---

## Rapid recall

1. **Each signal needs different storage.** Metrics: cardinality-bound aggregates queried over time ranges. Traces: **point lookup by `trace_id`** with most data never read. Logs: volume-bound records searched by label + time. Profiles: sampled stacks aggregated and **diffed** between windows. **No single store does all three well.**
2. ★ **The governing insight: most traces are never read.** They're reached from a log line or a metric exemplar. So the economically correct trace store optimises for **cheap bulk storage + fast ID lookup**, not full-text search.
3. **Metrics: Prometheus 3.14.0 / LTS 3.13.3 / Alertmanager 0.34.0** for a single cluster (< ~1M series). Scale out with **Mimir** (remote-write-first, multi-tenant), **Thanos** (Prometheus-first + object storage), or **VictoriaMetrics** (best raw price/performance at very high cardinality). Cloud natives want **delta**.
4. ★ **Prometheus transforms your metric names** (dots→underscores, `_total`/`_seconds`/`_bucket` suffixes added by default) and **requires cumulative**. Push has **no `up` metric** — build `absent_over_time()` alerts.
5. **Tempo**: object storage + `trace_id→block` index, **search by brute-force scan**. Cheapest credible option; slow for wide arbitrary attribute search. **The right choice when lookups are ID-driven** (i.e. almost always).
6. **Jaeger**: pluggable storage (Cassandra/ES/OpenSearch/Badger), **full index → fast arbitrary search**, higher cost and heavier operations. ★ **Jaeger now ingests OTLP natively and has converged on OTel — "Jaeger vs OpenTelemetry" is a stale framing.** Its `jaeger` receiver in the Collector is for legacy producers.
7. **ClickHouse-based** (SigNoz, Uptrace, HyperDX): columnar, SQL, and ★ **traces+logs+metrics joinable in one engine** — the best answer when your real questions cross signals. Cost: you operate ClickHouse.
8. **Vendor APMs**: all accept OTLP (**HTTP, not gRPC** — proxies handle it). You pay several times self-hosted cost and get back **operational capacity**. ★ **Decide on engineer-time, not licence price.** The real lock-in is queries/dashboards/muscle memory, not data. **Run a Collector anyway** — it's your redaction, cardinality and exit path.
9. **Loki indexes labels only, not content** — cheap, fast for `service + severity + time` queries, slow for arbitrary content scans. ★ Put query dimensions in labels; **never `trace_id` or `user_id`** (cardinality). **Elasticsearch/OpenSearch** index content: fast arbitrary search, high cost, real operational discipline. Choose by whether full-text search across all logs is a *primary* use case.
10. **Three reference architectures:** **A** Grafana OSS (Tempo+Mimir+Loki+Grafana on object storage — one bill, one UI, the metric→trace→log triangle as a design goal); **B** vendor (fastest to value, cost compounds); **C** ★ **hybrid — each signal to the store that's cheapest for its access pattern** (metrics you alert on in a system you control, traces to a vendor for incident UX, logs to cheap storage). Hybrid costs you three query languages and cross-signal linking becomes your job.
11. **Retention:** metrics 2–15 d hot + downsampled warm (**downsampling is the biggest metric cost lever**); **traces 3–14 d** (long retention is usually waste); logs 7–30 d searchable + **400 d–7 y** in object storage driven by **compliance, not engineering need**. ★ Ask *why* before you cut — and review the defaults, because "retention because it's the default" is the most common waste.
12. **Object storage is the cold-tier answer** (~4× cheaper than block, lower still with Glacier tiers) — which is why Tempo/Loki/Thanos/Mimir all use it. **Make archives retrievable or they're just a bill.**
13. **Before committing, check:** ingest protocol and auth, **temporality**, **name transformation**, **cardinality limits and what happens when you hit them**, per-trace/per-request size limits, retention configurability, **your ten incident queries**, cross-signal linking, multi-tenancy, egress/residency, ★ **cost at 3× and 10×**, exit cost, and honest operational load.

→ Next: [`14-scale-cost-and-cardinality.md`](14-scale-cost-and-cardinality.md)
