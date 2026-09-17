# 11 · Scaling & Long-Term Storage

**Level:** production · **Time:** ~2 h · **Goal:** know when a single Prometheus stops being enough, which architecture to pick, and how to control cardinality and cost.

---

## 1. When does one Prometheus stop working?

| Symptom | Threshold of concern | Meaning |
|---|---|---|
| Active series | > ~1–2 M on one node | Memory-bound; head block + index too large |
| RAM | Sustained > 70% of limit, OOMKills | Reduce series or add RAM/shards |
| Ingest | > ~1 M samples/sec per node | CPU/network-bound writes |
| Query latency | p99 > 5–10 s for dashboards | Needs a query frontend with caching/splitting |
| Retention needed | > 15–30 days of raw data | Local disk becomes absurd; you need downsampling |
| Targets | Tens of thousands per server | Scrape scheduling and SD overhead |
| Global view | Multiple clusters/regions | One server can't scrape everywhere |
| HA | Requirement for no monitoring gaps | Single Prometheus is a SPOF |

Rule of thumb: **a well-tuned single Prometheus comfortably handles 500k–1M active series at 15–30 s intervals with 8–32 GB RAM.** Beyond that, choose an architecture.

---

## 2. The five architectures

| # | Pattern | Components | Use when |
|---|---|---|---|
| 1 | **Replicated pair** | 2× identical Prometheus + 2–3× Alertmanager cluster | HA for a single cluster/region. Cheapest real HA. |
| 2 | **Sharding** | N Prometheus, targets split by `hashmod` on `__address__` | One region, too many targets/series for one node |
| 3 | **Thanos** | Sidecar or Receive + Store Gateway + Query + Compactor + object storage | Long retention, downsampling, global view over many clusters |
| 4 | **Grafana Mimir / Cortex** | Prometheus `remote_write` → distributor/ingester → object storage; query-frontend | Very large scale, multi-tenant, best query performance/caching |
| 5 | **VictoriaMetrics** | vmagent → vminsert/vmstorage/vmselect (cluster) or single-node | Highest compression, simplest ops, MetricsQL (PromQL superset) |
| — | **Managed** | Amazon Managed Prometheus, Google Managed Prometheus, Grafana Cloud, Datadog | You don't want to run a TSDB; check per-sample pricing |

### Thanos layout
```
Prometheus ── Sidecar ──(uploads 2h blocks)──► S3/GCS
     │                                            ▲
     └── remote_write ──► Receive ────────────────┘
                                                   │
                             Store Gateway ────────┤
                                                   ▼
                                             Query (frontend) ──► Grafana
                                             Ruler (alerts on global data)
                                             Compactor (downsample 5m/1h, retention)
```
- **Sidecar** = per-Prometheus, object storage, keeps local 2h blocks available. Good when you already run Prometheis.
- **Receive** = push-based (`remote_write`), multi-tenant, better for many small clusters/edge.
- **Compactor** does **downsampling**: raw → 5m → 1h. Query automatically picks the best resolution for the range (`max_source_resolution=auto`).
- **Query** dedupes replicas using `--query.replica-label=replica`.
- **Ruler** evaluates recording/alerting rules against the *global* data (so cluster-wide SLOs work) and remote-writes its results back.

### Mimir layout
```
Prometheus/agent ──remote_write──► Distributor ─► Ingester ─► Object storage
                                                            ▲
Grafana ──► Query-frontend (split+cache) ─► Querier ─► Store gateway/Index
                                       Ruler (managed alerting rules)
```
Multi-tenant via `X-Scope-OrgID`. The query-frontend's **query splitting + results caching** is the big operational win — dashboards become cheap after first load.

---

## 3. Remote write tuning (where most people lose data)

```yaml
remote_write:
  - url: https://mimir.example.com/api/v1/push
    # Remote Write 2.0 is negotiated automatically with Prometheus 3.x senders
    send_native_histograms: true
    metadata_config: {send: true, send_interval: 1m}
    basic_auth:
      username: mimir
      password_file: /etc/prometheus/secrets/mimir-pass
    queue_config:
      capacity: 20000              # per-shard buffer
      max_shards: 100              # ↑ if you see a growing backlog
      min_shards: 1
      max_samples_per_send: 2000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 5s
    write_relabel_configs:         # cut cost BEFORE it leaves the building
      - source_labels: [__name__]
        action: drop
        regex: 'go_gc_.*|go_memstats_.*|container_blkio_.*'
      - source_labels: [namespace]
        action: keep
        regex: 'prod|staging'
```

**Watch these metrics — a silent remote-write backlog means silent data loss:**
```promql
prometheus_remote_storage_samples_pending            # queue depth (should hover near 0)
prometheus_remote_storage_shards                     # auto-scaling shard count (pegged at max = problem)
rate(prometheus_remote_storage_samples_dropped_total[5m])    # ⚠️ data being LOST
rate(prometheus_remote_storage_samples_failed_total[5m])
rate(prometheus_remote_storage_retries_total[5m])
prometheus_remote_storage_highest_timestamp_in_seconds - prometheus_remote_storage_queue_highest_sent_timestamp_seconds  # lag
```
Alert on `samples_dropped_total > 0` and on lag > 5 minutes.

**WAL-based durability:** with `--storage.tsdb.retention.time` ≥ a few hours, Prometheus replays the WAL on restart and can resend queued samples — but only if the remote endpoint comes back before the WAL is truncated. Keep enough local retention to survive a backend outage.

---

## 4. Cardinality governance (the skill that saves the most money)

### Find the problem
```bash
promtool tsdb analyze /prometheus                        # top 10 metrics by series, label pairs
promtool tsdb analyze --help
```
```promql
prometheus_tsdb_head_series
rate(prometheus_tsdb_head_series_created_total[5m])      # churn
topk(10, count by (__name__)({__name__=~".+"}))
topk(10, count by (job, __name__)({__name__=~".+"}))
count by (pod)(container_cpu_usage_seconds_total)        # is one pod producing 5k series?
```
Grafana dashboard IDs: **3662** (Prometheus 2.0 Overview), **16380** / **16355** (cardinality explorer), and the Prometheus UI **Status → TSDB Status** page (`/api/v1/status/tsdb`) which lists top series by label.

### Fix it, in this order
1. **Drop unused metrics** with `metric_relabel_configs` / `write_relabel_configs`. Highest ROI, lowest risk.
2. **Drop high-cardinality labels** with `labeldrop` (`id`, `uid`, `image_id`, `device`, `endpoint_id`).
3. **Normalise unbounded values** (`/users/12345` → `/users/:id`) via `replace`.
4. **Bucket identifiers** with `hashmod` (tenant/user id → 1024 buckets) when you need distribution, not identity.
5. **Reduce scrape interval** for low-value jobs (30s → 60s halves samples).
6. **Restrict KSM/exporters** to the metric families you actually use.
7. **Shorten raw retention** and rely on downsampled data for long ranges.
8. **Shard or migrate** to a scalable backend if the data is genuinely needed.
9. **Institute a review**: monthly top-10 cardinality report to each team, with a budget per namespace (`kube_resourcequota`-style governance for series).

### Prevent it
- **CI check** on new alert rules / dashboards: reject `{__name__=~".+"}`, reject new labels without a cardinality note.
- **Ingest-time limits**: Mimir/VictoriaMetrics/Thanos support per-tenant series limits; Prometheus 3 rule groups support `limit:` for alert counts.
- **Naming policy**: label allowlists per team in the instrumentation guidelines (`03-Metrics-and-Instrumentation`).

---

## 5. High availability patterns compared

| Pattern | Monitoring gaps | Duplicate alerts | Query view | Ops cost |
|---|---|---|---|---|
| Single Prometheus | Yes (SPOF) | No | Local only | Low |
| **2 replicas, same config** | No | **Yes** — must dedupe in Alertmanager cluster | Local only | Low |
| 2 replicas + Thanos/Mimir | No | Deduped at query layer via replica label | Global | Medium |
| Sharding (N nodes) | Partial during rebalance | No | Needs federation/global query | Medium |
| Managed service | No | Vendor handles | Global | Low ops, high $ |
| **Watchdog + external dead-man's switch** | Detects all of the above | — | — | **Essential** |

Always add the **Watchdog** alert (`expr: vector(1)`) routed to an *external* service that pages when it stops arriving. HA designs still fail silently; the watchdog catches that.

---

## 6. Capacity, retention and cost maths

```
disk        ≈ samples/sec × retention_sec × ~1.5 bytes/sample  (Prometheus, compressed)
samples/sec ≈ active_series / scrape_interval
VictoriaMetrics typically ≈ 0.3–0.8 bytes/sample  (2–4× better compression)
Mimir/Thanos in object storage ≈ similar per-sample, but far cheaper per GB + downsampled tiers
```

Retention tiers that work in practice:

| Tier | Resolution | Retention | Answers |
|---|---|---|---|
| Hot / local | raw (15–30s) | 2–15 days | Incidents, debugging |
| Warm / object store | raw | 30–90 days | Recent trends, postmortems |
| Cold / downsampled | 5m | 1–2 years | Capacity planning, YoY |
| Archive | 1h | 3–7 years | Compliance, long-term modelling |

Cost drivers, in order: **active series count** (biggest), **scrape interval**, **retention**, **query volume** (managed services often charge per query too), **log/trace volume** (usually larger than metrics — see topic 10).

---

## 7. Query performance at scale

| Technique | Effect |
|---|---|
| **Recording rules** for every repeated/expensive query | Compute once, read many |
| **Query frontend splitting** (Mimir/Thanos) | A 30-day query becomes 30 parallel 1-day queries, cached individually |
| **Results cache** | Repeat dashboard loads near-instant |
| **`max_source_resolution=auto`** | Uses 5m/1h downsampled data for long ranges instead of raw |
| **Grafana `Min step` / `$__rate_interval`** | Stops requesting absurd resolutions |
| **Downsampling** | 30-day dashboards go from minutes to seconds |
| **Query limits** (`--query.timeout`, `--query.max-samples`, `--query.max-concurrency`) | Protects the store from one bad panel |
| **Avoid `{__name__=~".+"}` and wide regexes** | Full TSDB scans |
| **Tenant/label-based sharding at query time** | Smaller working set |

---

## 8. Upgrading and operating Prometheus

- Prometheus 3.x is largely config-compatible with 2.x, but check: removed feature flags (`remote-write-receiver`, `promql-at-modifier`, `promql-negative-offset`, `no-scrape-default-port`, `new-service-discovery-manager`), log field names (`ts`/`caller` → `time`/`source`), left-open range selectors, and any UTF-8 escaping assumptions.
- **Always** `promtool check config` before rollout; roll out to one replica first.
- TSDB format changes rarely, but **never downgrade** across a major version without testing on a copy of the data dir.
- Take a snapshot before upgrades: `curl -XPOST localhost:9090/api/v1/admin/tsdb/snapshot` (hard-links blocks under `snapshots/`).
- Use the **LTS release** (3.13.x) for production if you don't need new features.
- In Kubernetes, upgrade **CRDs before the Helm chart**, and one minor version at a time.

---

## 9. Self-check

1. At roughly what active-series count does a single Prometheus need help, and what's the first symptom?
2. Compare Thanos Sidecar vs Thanos Receive — when do you pick each?
3. What does the Thanos/Mimir compactor's downsampling buy you, and at what cost?
4. Which two remote-write metrics tell you that you are silently losing data?
5. List six cardinality-reduction techniques in order of ROI.
6. Why does running two Prometheus replicas create duplicate notifications, and where is that solved?
7. Estimate disk for 800k series at a 30s scrape interval with 60 days raw retention.
8. What is a query frontend and why does it make 90-day dashboards usable?
9. Why is a Watchdog alert still needed in an HA architecture?
10. What four things do you check before upgrading Prometheus across a major version?

→ Next: [`12-On-Call-and-Incident-Response`](../12-On-Call-and-Incident-Response/README.md)
