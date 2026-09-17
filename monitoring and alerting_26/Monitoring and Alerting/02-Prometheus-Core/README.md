# 02 · Prometheus Core  ★ deep dive

**Level:** core · **Time:** ~4 h + Lab 1–2 · **Goal:** run, configure, tune and debug Prometheus; understand its data model and storage well enough to reason about performance.

---

## 1. What Prometheus is (and isn't)

Prometheus is an open-source **systems monitoring and alerting toolkit**: it scrapes HTTP endpoints that expose metrics, stores them in a local time-series database, queries them with PromQL, evaluates alerting rules, and hands firing alerts to Alertmanager. CNCF graduated (second project after Kubernetes). Current line: **3.x** (3.14 at time of writing, 3.13 LTS).

**Design choices that shape everything:**

| Choice | Consequence |
|---|---|
| **Pull** model over HTTP | You must be able to reach targets; a missing target is a signal (`up == 0`) |
| **Single-node, self-contained** | No external dependencies → extremely reliable; but no built-in clustering → HA means two replicas, long-term storage means Thanos/Mimir/VictoriaMetrics |
| **Multi-dimensional data model** (name + labels) | Labels are the query axis and the cardinality risk |
| **PromQL** | Powerful, but easy to write expensive queries |
| **Local TSDB, 2 h blocks** | Fast writes/reads; retention & disk are your problem |
| **Not for logs/traces** | Use Loki/Tempo; Prometheus stores numbers |

**Prometheus is not:** a message queue, a log store, a business-intelligence tool, or a highly-available database. It is also *not* designed for very high-cardinality data (millions of series) on one node.

---

## 2. Architecture

```
                    ┌────────────────────────── Prometheus server ──────────────────────────┐
  scrape targets    │  ┌──────────┐   ┌─────────────┐   ┌──────────┐   ┌────────────────┐  │
 ┌──────────────┐   │  │ Service  │──►│   Scrape    │──►│  TSDB    │◄──│   PromQL       │  │
 │ node_exporter│◄──┼──│ Discovery│   │   loop      │   │ (WAL +   │   │   engine       │  │
 │ app /metrics │   │  └──────────┘   └─────────────┘   │  blocks) │   └───────┬────────┘  │
 │ blackbox     │   │                                   └──────────┘           │           │
 └──────────────┘   │  ┌──────────────────────────────┐              ┌─────────▼────────┐  │
                    │  │ relabel_configs (pre-scrape) │              │  Rule manager    │  │
                    │  │ metric_relabel_configs (post)│              │ recording+alerting│ │
                    └──┴──────────────────────────────┴──────────────┴─────────┬────────┘  │
                                                                               │           │
   HTTP API :9090/api/v1/{query,query_range,series,labels,targets}◄────────────┼───────────┘
                                                                               ▼
                                                                 alerts ──► Alertmanager
                                                                 reads  ◄── Grafana
```

**The lifecycle of one sample:**
1. Service discovery produces a list of *potential* targets.
2. `relabel_configs` filters/relabels them → the final target list (`/targets` UI).
3. Every `scrape_interval`, Prometheus GETs `/metrics`, parses the exposition format.
4. `metric_relabel_configs` runs per-sample (keep/drop/rewrite) → this is where you fight cardinality.
5. Samples are written to the **WAL** (write-ahead log) and the in-memory **head block**.
6. Every 2 h the head is cut into an immutable, compacted **block** on disk; old blocks are compacted further and eventually deleted at retention.
7. Rule manager evaluates recording and alerting rules on the same interval; alerts go to Alertmanager.

### Prometheus 3.x — what changed (interview favourite)
- **New UI** with a PromLens-style query tree.
- **UTF-8 metric and label names** — `http.server.request.duration` is legal without escaping (OTel-friendly). Query such names with `{"http.server.request.duration"}` syntax.
- **Native OTLP receiver**: `--web.enable-otlp-receiver` exposes `/api/v1/otlp/v1/metrics` so an OTel Collector/SDK can push directly. Off by default (no auth) — put it behind a proxy.
- **Remote Write 2.0**: metadata, exemplars, created timestamps, native histograms in one payload + string interning (smaller, cheaper). Negotiated automatically, falls back to 1.0.
- **Agent mode is stable** and has its own flag: `--agent.mode` (scrape + remote-write only, no query/rules UI).
- Feature flags removed (now default): `promql-at-modifier`, `promql-negative-offset`, `remote-write-receiver` (use `--web.enable-remote-write-receiver`), `no-scrape-default-port`, `new-service-discovery-manager`.
- **Range selectors are now left-open, right-closed** `(t-d, t]` — occasionally changes how many samples land in a window.
- Logs use `slog` (`time`, `source`) instead of go-kit (`ts`, `caller`).
- **Native histograms** still experimental (`--enable-feature=native-histograms`): exponential, self-adjusting buckets → far better resolution at much lower cardinality than classic histograms.

---

## 3. The data model

A **time series** is uniquely identified by a metric name plus a set of label key/value pairs:

```
http_requests_total{job="api-server", instance="10.0.0.7:8080", method="POST", status="500"}
└────── name ──────┘└────────────────────────── label set ──────────────────────────────────┘
```

The **series identifier** is the whole thing. Two samples with different label sets are two different series, each costing memory and disk.

**Cardinality** = number of distinct series. It is *multiplicative across labels*:

```
series ≈ |instances| × |paths| × |methods| × |status codes| × ...
        50 pods    ×  400 paths ×   5      ×     10        = 1,000,000 series  ← from ONE metric
```

That single metric can OOM your Prometheus. **Cardinality control is the #1 Prometheus production skill** (see `11-Scaling-and-Long-Term-Storage`).

### Metric types (the exposition format)

| Type | Semantics | Client behaviour | Query with |
|---|---|---|---|
| **Counter** | Monotonic, only increases (resets to 0 on restart) | `# TYPE x counter` | `rate()`, `increase()`, `irate()` — **never** raw value |
| **Gauge** | Goes up and down | `# TYPE x gauge` | raw value, `delta()`, `avg_over_time()`, `min/max_over_time()` |
| **Histogram** | Client-side buckets → `_bucket{le=...}`, `_sum`, `_count` | `# TYPE x histogram` | `histogram_quantile()`, `rate(_sum)/rate(_count)` |
| **Summary** | Client-side precomputed quantiles | `# TYPE x summary` | quantiles already there but **cannot be aggregated across instances** |
| **Native/Exponential histogram** | Server-friendly sparse buckets | — | `histogram_quantile()` works too; experimental |
| **Info / State set** | Constant `1` with labels; used via `* on(...) group_left` joins | — | join pattern |
| **Enum gauge** | `1` for the current state, `0` otherwise | — | `sum by(state)` / `== 1` |

Full treatment in [`03-Metrics-and-Instrumentation`](../03-Metrics-and-Instrumentation/README.md).

---

## 4. Configuration

One YAML file, reloaded via `SIGHUP` or `POST /-/reload` (needs `--web.enable-lifecycle`). Always validate first:

```bash
promtool check config prometheus.yml     # also checks referenced rule files
promtool check rules rules/*.yaml
promtool query instant http://localhost:9090 'up'
```

### A realistic `prometheus.yml`

```yaml
global:
  scrape_interval: 15s          # default; per-job override below
  scrape_timeout: 10s           # MUST be <= scrape_interval
  evaluation_interval: 15s      # how often rules are evaluated
  external_labels:              # added to everything leaving this server
    cluster: ap-south-1-prod
    replica: prom-0
    region: ap-south-1

# Rule files (recording + alerting). Globs allowed.
rule_files:
  - /etc/prometheus/rules/*.yaml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
      # scheme: https
      # basic_auth: { username: prom, password_file: /etc/prometheus/secrets/am-pass }
      timeout: 10s
      api_version: v2

scrape_configs:
  # ---- Prometheus monitors itself -------------------------------------
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']

  # ---- Linux hosts -----------------------------------------------------
  - job_name: node
    scrape_interval: 30s
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          env: prod
          team: platform
    relabel_configs: []

  # ---- Kubernetes service discovery (see topic 08) ---------------------
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        target_label: app

  # ---- Blackbox probes: one target = many probe modules ----------------
  - job_name: blackbox-http
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://example.com/healthz
          - https://api.example.com/
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115

  # ---- Federation / scraping another Prometheus ------------------------
  - job_name: federate-edge
    scrape_interval: 60s
    honor_labels: true
    metrics_path: /federate
    params:
      'match[]':
        - '{job="node"}'
        - '{__name__=~"up|.*:.*"}'   # recording rules by convention contain ':'
    static_configs:
      - targets: ['prometheus-edge-1:9090']

# ---- Long-term / central storage ---------------------------------------
remote_write:
  - url: https://mimir.example.com/api/v1/push
    # send_native_histograms: true
    basic_auth:
      username: mimir
      password_file: /etc/prometheus/secrets/mimir-pass
    queue_config:
      capacity: 10000
      max_shards: 50
      min_shards: 1
      max_samples_per_send: 2000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 5s
    write_relabel_configs:            # drop junk before it costs money
      - source_labels: [__name__]
        regex: 'go_.*|promhttp_.*'
        action: drop

# ---- Receive remote_write (turns this Prometheus into a sink) -----------
# enable with: --web.enable-remote-write-receiver
```

### Key CLI flags

```bash
prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=15d \
  --storage.tsdb.retention.size=80GB \        # whichever hits first wins
  --storage.tsdb.wal-compression=true \
  --web.enable-lifecycle \                    # allows POST /-/reload
  --web.enable-admin-api \                    # allows snapshots, delete-series (careful)
  --web.external-url=https://prom.example.com \
  --web.listen-address=0.0.0.0:9090 \
  --enable-feature=native-histograms \
  --enable-feature=exemplar-storage \
  --agent.mode                                # scrape + remote-write only (edge nodes)
```

Retention defaults: `--storage.tsdb.retention.time=15d` and `retention.size` unlimited. Set **both** in production.

---

## 5. Service discovery

Prometheus finds targets dynamically instead of a static list. Each SD provides `__meta_*` labels; `relabel_configs` turns those into real labels and the real `__address__`.

| SD | Config key | Typical use |
|---|---|---|
| `static_configs` | fixed list | Labs, VMs, single hosts |
| `kubernetes_sd_configs` | `role: node/pod/service/endpoints/endpointslice/ingress` | The default in k8s |
| `ec2_sd_configs` / `azure_sd_configs` / `gce_sd_configs` | cloud VMs | Auto-scaling groups |
| `consul_sd_configs`, `eureka_sd_configs` | registries | Legacy service meshes |
| `dns_sd_configs` | SRV/A/AAAA records | Simple, no API needed |
| `file_sd_configs` | JSON/YAML files, hot-reloaded | Air-gapped, GitOps-generated target lists |
| `openstack_sd_configs`, `hetzner_sd_configs`, `uyuni_sd_configs`, … | | |

**`file_sd_configs` is underrated:** a controller writes a JSON file, Prometheus picks it up within seconds, no restart:

```yaml
- job_name: file-targets
  file_sd_configs:
    - files: ['/etc/prometheus/targets/*.json']
      refresh_interval: 30s
```
```json
[{"targets": ["10.0.0.5:9100"], "labels": {"team": "payments", "env": "prod"}}]
```

Useful `__meta_kubernetes_*` labels: `__meta_kubernetes_namespace`, `__meta_kubernetes_pod_name`, `__meta_kubernetes_pod_label_<label>`, `__meta_kubernetes_pod_annotation_<ann>`, `__meta_kubernetes_service_name`, `__meta_kubernetes_endpoints_name`, `__meta_kubernetes_node_name`, `__meta_kubernetes_pod_container_port_number`, `__meta_kubernetes_pod_phase`, `__meta_kubernetes_pod_controller_kind`.

Inspect everything at `http://localhost:9090/service-discovery`, and see the *before/after* label sets at `/targets`.

---

## 6. Relabeling — the most misunderstood feature

Two separate stages:

| | `relabel_configs` | `metric_relabel_configs` |
|---|---|---|
| Where | under a **scrape_config** (target level) | under a **scrape_config** (sample level) |
| When | **before** scraping — decides targets, address, path, params, labels | **after** scraping — per sample, before storage |
| Sees | `__meta_*` + `__address__`, `__metrics_path__`, `__scheme__`, `__param_*` | the actual metric name and labels |
| Used for | discovery filtering, label promotion, blackbox rewriting | **dropping high-cardinality metrics**, renaming, hashing IDs |

**Actions:** `replace` (default), `keep`, `drop`, `hashmod`, `labelmap`, `labeldrop`, `labelkeep`, `lowercase`, `uppercase`, `keepequal`, `dropequal`.

`replace` semantics: `source_labels` are joined with `separator` (default `;`), matched against `regex` (default `(.*)`, fully anchored), and the capture groups substituted into `replacement` (default `$1`) and written to `target_label`.

```yaml
# 1) Only scrape pods annotated prometheus.io/scrape=true
relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: "true"

# 2) Promote a label from the pod to the series
  - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
    action: replace
    target_label: app

# 3) Hash a user id down to 1024 buckets to bound cardinality
  - source_labels: [user_id]
    action: hashmod
    modulus: 1024
    target_label: user_bucket

# 4) Copy all labels starting with "meta_" onto the target
  - regex: meta_(.+)
    action: labelmap
    replacement: $1

# 5) Drop noisy internal labels
  - regex: '__meta_kubernetes_pod_annotation_kubectl.*'
    action: labeldrop
```

```yaml
# Cardinality control after the scrape — the single highest-value config block
metric_relabel_configs:
  - source_labels: [__name__]
    action: drop
    regex: 'container_cpu_cfs_throttled_periods_total|go_gc_.*'
  - source_labels: [__name__]
    action: drop
    regex: '.*_bucket'          # if you never use histogram_quantile on it
  - action: labeldrop
    regex: 'id|container_id|image_id|uid'
  - source_labels: [path]       # collapse /users/12345 -> /users/:id
    action: replace
    regex: '/users/\d+'
    replacement: '/users/:id'
    target_label: path
```

> **Debugging tip:** in Prometheus 3's UI, the *Targets* page shows a "before/after" diff of relabeling. In Grafana, use the "Relabeling" debug view. When a target is missing, 90% of the time a `keep` action dropped it.

---

## 7. Storage, memory and capacity planning

- **WAL** → replayed on restart. Deleting it loses recent data.
- **Head block** in memory holds ~2–3 h of samples: roughly **1–3 KB per active series** (more with churn).
- **On-disk blocks**: 2 h chunks, compacted to larger blocks. Empirically **~1–2 bytes per sample** after compression.

**Back-of-envelope sizing:**

```
samples/sec  = active_series × (1 / scrape_interval)
disk         = samples/sec × retention_seconds × ~1.5 bytes
memory(head) = active_series × ~2 KB   (plus query overhead)

Example: 500k series, 15s scrape, 30d retention
  samples/sec = 500000 / 15 ≈ 33.3k
  disk        = 33.3k × 2.592e6 × 1.5 B ≈ 130 GB
  head RAM    ≈ 500k × 2 KB ≈ 1 GB (add 3–8 GB total for queries/GC)
```

**Inspect reality, don't guess:**

```bash
promtool tsdb analyze /prometheus                     # top series by label, cardinality report
promtool tsdb list /prometheus
promtool tsdb create-blocks-from openmetrics in.txt out/
```
```promql
prometheus_tsdb_head_series                            # active series
prometheus_tsdb_head_samples_appended_total
prometheus_engine_query_duration_seconds{quantile="0.9"}
prometheus_target_interval_length_seconds{quantile="0.99"} / on(job) ... # scrape health
rate(prometheus_tsdb_compactions_failed_total[5m])
```

---

## 8. HTTP API (script everything with this)

```bash
# instant query
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=up' --data-urlencode 'time=2026-09-14T10:00:00Z' | jq

# range query
curl -sG http://localhost:9090/api/v1/query_range \
  --data-urlencode 'query=rate(http_requests_total[5m])' \
  --data-urlencode 'start=2026-09-14T00:00:00Z' \
  --data-urlencode 'end=2026-09-14T12:00:00Z' \
  --data-urlencode 'step=60s' | jq '.data.result | length'

# metadata
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | jq '.data | length'
curl -s 'http://localhost:9090/api/v1/series?match[]=up'
curl -s  http://localhost:9090/api/v1/targets?state=active | jq '.data.activeTargets[].health'
curl -s  http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[].name'
curl -s  http://localhost:9090/api/v1/alerts
curl -s  http://localhost:9090/api/v1/status/tsdb | jq '.data.headStats'
curl -s  http://localhost:9090/api/v1/status/buildinfo

# admin (needs --web.enable-admin-api)
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot
curl -XPOST 'http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]=old_metric&start=..&end=..'
# lifecycle (needs --web.enable-lifecycle)
curl -XPOST http://localhost:9090/-/reload
kill -HUP $(pgrep prometheus)
```

---

## 9. High availability and federation (no clustering built in)

| Pattern | How | Trade-offs |
|---|---|---|
| **Two identical replicas** | Same config, different `external_labels.replica` | Both page → **dedupe** downstream (Alertmanager cluster gossip, or Thanos/Mimir ruler dedup). Simple, robust. |
| **Alertmanager HA cluster** | 3+ AMs with `--cluster.peer` (gossip/memberlist); each gets all alerts, they dedupe & elect a notifier | Notifications deduplicated; needs odd number ≥3 |
| **Federation** | A global Prometheus scrapes `/federate` from regional ones with `match[]` selectors | Only pull **recording rules** and aggregates, never raw series; it's a hierarchy, not a database |
| **Sharding** | Split targets by `hashmod` on `__address__` across N Prometheis | Standard horizontal scale-out; each shard has a partial view |
| **Remote write to a central store** | Thanos Receive / Mimir / VictoriaMetrics / Cortex | The modern answer for scale + long retention |
| **Agent mode** | `--agent.mode` on edge nodes, remote-write to centre | Tiny footprint, no local queries |

```yaml
# Sharding with hashmod: 4 shards, this is shard 2
relabel_configs:
  - source_labels: [__address__]
    modulus: 4
    action: hashmod
    target_label: __tmp_hash
  - source_labels: [__tmp_hash]
    regex: "2"
    action: keep
```

---

## 10. Operations: the checks you run weekly

```promql
# Targets down
up == 0

# Scrape duration creeping toward the timeout
scrape_duration_seconds > 0.8 * scrape_timeout_seconds   # (or compare per job)

# Prometheus's own health
prometheus_config_last_reload_successful == 0            # bad config reload
prometheus_rule_evaluation_failures_total                # broken rules
rate(prometheus_notifications_errors_total[5m])          # can't reach Alertmanager
prometheus_notifications_queue_length                    # backlog
prometheus_tsdb_wal_corruptions_total
prometheus_tsdb_head_series                              # cardinality trend
topk(5, count by (__name__)({__name__=~".+"}))           # noisiest metrics
```

**Self-monitoring alerts you must have:** `PrometheusDown` (external), `TargetDown`, `ConfigReloadFailure`, `RuleEvaluationFailure`, `AlertmanagerDown`, `Watchdog` (dead-man's switch), `PrometheusHighCardinality`, `PrometheusDiskWillFillIn4Days`. Ready-made versions in [`13-Alert-Rules-Library`](../13-Alert-Rules-Library/README.md).

---

## 11. Common failure modes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| OOMKilled | Too many active series / expensive queries / head too large | `promtool tsdb analyze`, add `metric_relabel_configs` drops, limit `--storage.tsdb.max-block-chunk-segment-size`, shard, raise memory, reduce retention of raw data |
| CPU pinned | Frequent expensive queries, no recording rules, `irate` over long ranges | Precompute with recording rules; check Grafana refresh intervals and `min step` |
| Disk full | Retention not set / WAL grew / blocks not compacted | Set `retention.time` **and** `retention.size`; check `promtool tsdb list` |
| Target missing | A `keep` relabel dropped it; wrong port; SD role wrong | `/targets` before/after view; `/service-discovery` |
| Alerts never fire | Rule file not matched by `rule_files`, wrong label matchers, `for:` too long, metric absent | `promtool check rules`, `promtool test rules`, `absent()` companion |
| `up == 1` but no data | `honor_labels` conflicts; metric dropped by `metric_relabel_configs` | Check `/targets` sample counts |
| Stale data after restart | WAL replay in progress | Wait; check `prometheus_tsdb_wal_replay_duration_seconds` |
| Duplicate series in Grafana | Two replicas remote-writing without dedup | Enable deduplication (Thanos Query `--query.replica-label`, Mimir, or drop `replica` label in Grafana) |

---

## Lab

1. Start the stack in [`16-Labs`](../16-Labs/README.md), open `http://localhost:9090`.
2. **Targets:** make `node-exporter` disappear (stop the container). Confirm `up == 0` and see the target turn red. Restart it.
3. **Relabeling:** add a `keep` action requiring `env="prod"`; watch the target vanish; then add the label to the target and watch it return.
4. **Cardinality:** run `topk(10, count by (__name__)({__name__=~".+"}))`. Add a `metric_relabel_configs` drop for the top offender and confirm the series count falls after a reload.
5. **Hot reload:** `curl -XPOST localhost:9090/-/reload`, then `promtool check config` on a deliberately broken config and observe the reload failure metric.
6. **TSDB:** run `promtool tsdb analyze` against the lab's data directory.

---

## Self-check

1. Draw the path of a sample from service discovery to disk. Where can it be dropped?
2. `relabel_configs` vs `metric_relabel_configs` — when does each run, and which one do you use to fight cardinality?
3. Why is `scrape_timeout` required to be ≤ `scrape_interval`?
4. How does Prometheus achieve HA without clustering? What problem does that create for alerting, and how is it solved?
5. Estimate disk for 1M series at a 30 s scrape interval and 15 days retention.
6. Name three Prometheus 3.0 features and what each is for.
7. Which two CLI flags make Prometheus an edge collector that can't be queried locally?
8. A target is missing from `/targets`. List four things you check, in order.

→ Next: [`03-Metrics-and-Instrumentation`](../03-Metrics-and-Instrumentation/README.md)
