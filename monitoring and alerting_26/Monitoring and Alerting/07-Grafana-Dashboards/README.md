# 07 · Grafana Dashboards  ★ deep dive

**Level:** core · **Time:** ~3 h + Lab 6 · **Goal:** build dashboards that answer questions during an incident in under 30 seconds, managed as code.

**Version referenced:** Grafana **13.x** (from 13.2 the Prometheus data source ships as a standalone plugin; bundled versions ≤13.1 behave the same for our purposes).

---

## 1. Grafana's role in the stack

Grafana **does not store data**. It queries backends (Prometheus, Loki, Tempo, CloudWatch, Elasticsearch, MySQL, 100+ sources) and renders panels. It also has its own alerting engine — which in a Kubernetes/Prometheus shop you should usually keep **secondary** to Prometheus rules + Alertmanager (see [`06-Alertmanager` §12](../06-Alertmanager/README.md)).

```
Prometheus ◄──query── Grafana ──► browser
Loki       ◄──query──   │
Tempo      ◄──query──   └──► unified alerting (optional)
```

---

## 2. Provisioning everything as code (do this from day one)

Dashboards created in the UI live in Grafana's database and are lost when the pod restarts. **Provision** instead.

### Directory layout
```
grafana/
├── provisioning/
│   ├── datasources/datasources.yaml
│   ├── dashboards/dashboards.yaml
│   ├── alerting/rules.yaml          # optional, if you use Grafana alerting
│   └── notifiers/                   # legacy contact points
└── dashboards/
    ├── node-exporter.json
    ├── kubernetes-cluster.json
    └── service-checkout.json
```

### Data source
```yaml
# provisioning/datasources/datasources.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus                 # FIXED uid → dashboards referencing it are portable
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: 15s             # must match your scrape_interval (avoids gaps)
      httpMethod: POST              # GET breaks on long queries (URL length limits)
      manageAlerts: false           # let Alertmanager own alerting
      prometheusType: Prometheus
      prometheusVersion: 3.14.0
      incrementalQuerying: true
      cacheLevel: 'High'
      exemplarTraceIdDestinations:
        - name: traceID
          datasourceUid: tempo
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      derivedFields:
        - name: traceID
          matcherRegex: 'traceID=(\w+)'
          url: '$${__value.raw}'
          datasourceUid: tempo
```

### Dashboard provider
```yaml
# provisioning/dashboards/dashboards.yaml
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: Services
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30        # hot reload
    allowUiUpdates: true             # let people experiment; changes are NOT saved back
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

> `allowUiUpdates: true` means users can edit provisioned dashboards in the UI, but a file update overwrites their changes. For real change control: `allowUiUpdates: false` + all edits via PR.

### Docker / Helm wiring
```yaml
# docker-compose
services:
  grafana:
    image: grafana/grafana:13.1.0
    ports: ["3000:3000"]
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_DASHBOARDS_MIN_REFRESH_INTERVAL: 5s
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
```
```bash
# kube-prometheus-stack: Grafana sidecar auto-discovers ConfigMaps with these labels
kubectl create configmap checkout-dashboard \
  --from-file=checkout.json \
  -l grafana_dashboard=1 -n monitoring
```
In `kube-prometheus-stack`, `grafana.sidecar.dashboards.enabled=true` and the label `grafana_dashboard: "1"` (configurable) turn any ConfigMap into a provisioned dashboard. Same for `grafana_datasource: "1"`.

---

## 3. Panel types and what each is for

| Panel | Use for | Don't use for |
|---|---|---|
| **Time series** | Anything over time (the default) | Single values |
| **Stat** | One big number: current error rate, uptime | Trends |
| **Gauge** | Value against thresholds (disk %, SLO attainment) | Many series |
| **Bar gauge** | Horizontal comparison (top 10 tenants by requests) | Time |
| **Table** | Tabular listing (targets, versions, per-pod memory) | Time series |
| **Heatmap** | Latency distribution over time (`*_bucket`), density | Simple trends |
| **Histogram** | Distribution at a point in time | Time |
| **State timeline** | Up/down, deployment status, feature flags over time | Continuous values |
| **Status history** | Categorical state changes per entity | |
| **Pie / Donut** | Proportions ≤ 6 slices | Anything time-based (almost never useful) |
| **Bar chart** | Categorical comparison | Time series with many points |
| **Logs** | Loki log lines | |
| **Traces** | Tempo/Jaeger trace view | |
| **Node graph** | Service dependencies, k8s topology | |
| **Canvas** | Freeform architecture diagram with live values | |
| **Flame graph** | Continuous profiling (Pyroscope) | |
| **Alert list** | Currently firing alerts on this dashboard | |
| **Annotations** | Deploy markers, incident windows | |

**Prometheus-specific query formats** (the `Format` dropdown): `Time series` (default), `Table` (instant query, for tables), `Heatmap`, `Logs`, `Trace`, `Exemplars` (scatter points from native histograms/exemplar storage).

---

## 4. Query options that make dashboards fast and correct

| Option | Set it to | Why |
|---|---|---|
| **Min step** / **Min interval** | your scrape interval (e.g. `15s`) | Stops Grafana requesting sub-scrape resolution → gaps and huge queries |
| **Resolution / Max data points** | panel width in px (default ~800) | Controls `step` in `query_range` |
| **Relative time** | `now-6h` etc. | Panel-level override |
| **Time shift** | `1d` | Compare with yesterday on the same panel |
| **Cache duration** | 5m for expensive panels | |
| **Instant vs Range** | Instant for Stat/Table | Faster, single value |
| **Legend** | `{{job}} {{instance}}` | Human-readable series names |
| **Transformations** | `Organize fields`, `Merge`, `Reduce`, `Group by`, `Add field from calculation`, `Config from query results` | Fix data shape without touching PromQL |

`$__interval` and `$__rate_interval` are the two variables you must know:

```promql
rate(http_requests_total[$__rate_interval])
```
- `$__interval` = (time range) / (max data points), bounded below by `Min step`.
- **`$__rate_interval` = max(4 × scrape interval, `$__interval`)** — this is the **correct** choice for `rate()` in Grafana, and it eliminates the "gaps and dips when I zoom out" bug. Use `$__rate_interval` for every `rate`/`increase`/`irate` in a panel.

Also useful: `$__range`, `$__from`, `$__to`, `$__interval_ms`, `$__auto_interval_<var>`.

---

## 5. Variables (templating) — one dashboard, every service

Dashboard → Settings → Variables. Types: **Query** (from the data source), **Custom** (hardcoded list), **Text box**, **Constant**, **Data source**, **Interval**, **Ad hoc filters** (Prometheus/Loki only).

```yaml
# Common pattern (expressed as it appears in dashboard JSON)
templating:
  list:
    - name: datasource
      type: datasource
      query: prometheus

    - name: cluster
      type: query
      datasource: {uid: '${datasource}'}
      query: label_values(kube_node_info, cluster)
      refresh: 2                      # on time range change

    - name: namespace
      type: query
      query: label_values(kube_pod_info{cluster="$cluster"}, namespace)
      refresh: 2
      includeAll: true
      multi: true
      sort: 1

    - name: service
      type: query
      query: label_values(kube_service_info{namespace=~"$namespace"}, service)
      refresh: 2
      multi: true
      includeAll: true

    - name: pod
      type: query
      query: label_values(kube_pod_info{namespace=~"$namespace", service=~"$service"}, pod)
      refresh: 2
      multi: true
      allValue: ".*"

    - name: interval
      type: interval
      query: 1m,5m,10m,30m,1h
      current: {text: 5m, value: 5m}
```

Then every query uses them:
```promql
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=~"$namespace", pod=~"$pod"}[$__rate_interval]))
```

Rules for variables:
- Use **`multi` + `includeAll`** and write matchers as `=~"$var"` (never `="$var"`), or multi-select breaks.
- Set **`allValue: ".*"`** explicitly — otherwise "All" can produce an empty regex.
- **Chain variables** (cluster → namespace → service → pod) so the lists stay short.
- Use **`label_values(metric, label)`** not `label_values(label)` — scoping to a metric is far faster.
- Add an **Ad hoc filters** variable for ad-hoc debugging without editing panels.
- Expose variables in the URL (`?var-namespace=prod&var-service=checkout`) — this is how your **alert annotations deep-link** into the right view.

---

## 6. Designing dashboards people actually use

### The standard three-tier structure

| Tier | Name | Audience | Content |
|---|---|---|---|
| 1 | **Overview / Fleet** | On-call, managers | One row per service: availability, error rate, p99, saturation. Traffic-light stats. 12 panels max. |
| 2 | **Service** | The owning team | RED at the top, dependencies in the middle, resources at the bottom, logs/traces links. |
| 3 | **Debug / Deep dive** | Engineer in an incident | Per-pod, per-endpoint, per-status breakdowns; ad hoc filters; histograms; flame graphs. |

### The layout rule that matters most

> **Top of the dashboard = most important, most recent, most actionable.**

Put **symptoms** at the top (what users feel), **causes** below (why). During an incident nobody scrolls to panel 27. Concretely, a service dashboard:

```
Row 1  ── SLO burn (gauge) │ Availability % (stat) │ Error rate (ts) │ p99 latency (ts) │ QPS (ts)
Row 2  ── Status code breakdown (stacked) │ Latency heatmap │ Apdex │ Slowest endpoints (bar gauge)
Row 3  ── Dependency: DB latency/errors │ Cache hit ratio │ Downstream API errors │ Queue depth
Row 4  ── Resources: CPU │ Memory vs limit │ Replicas (state timeline) │ Restarts │ Network
Row 5  ── Logs (Loki, filtered by $service) │ Traces link │ Currently firing alerts (alert list)
```

### Practical rules

- **Every panel has a description** explaining what it shows and what "bad" looks like. Future-you at 3 a.m. is a stranger.
- **Set thresholds and colour** so a glance tells you red/green. Use shared threshold constants.
- **Units!** Set `seconds`, `bytes`, `percent (0.0–1.0)`, `reqps`, `bits/sec`. Unlabelled axes cause real misdiagnosis.
- **One question per panel.** "Latency" is not a question; "p99 latency per endpoint vs SLO" is.
- **Avoid more than ~8 series** on a time series panel; use `topk()` and a legend table.
- **Use `topk(10, ...)` in a table/bar gauge** rather than plotting everything.
- **Annotations for deploys** — the single most valuable context on any graph:
  ```promql
  changes(kube_deployment_status_observed_generation{namespace="$namespace"}[5m]) > 0
  ```
  or a Loki query on your CI log stream, rendered as a vertical line.
- **Data links**: make a panel clickable → drill into logs (`/d/logs?var-pod=${__field.labels.pod}&from=${__from}&to=${__to}`) or traces.
- **Refresh interval**: 30s default; 5s only on a NOC wall display (it costs Prometheus CPU).
- **Time picker default**: `now-6h` for service dashboards; `now-30d` for SLO/capacity.
- **Dashboard as code**: JSON in Git, reviewed by PR, deployed by provisioning. Add a lint step (`grafana-dashboard-cli`, `grizzly`/`grr`, or `jq` sanity checks).
- **Folders + permissions** mirror team ownership; enable `GF_USERS_DEFAULT_THEME` and organisation-level defaults for consistency.

### Importing community dashboards

The best starting points (paste the ID into Dashboards → New → Import):

| ID | Dashboard |
|---|---|
| **1860** | Node Exporter Full (the canonical host dashboard) |
| **315** | Kubernetes cluster monitoring (via Prometheus) |
| **13105** | Kubernetes / Compute Resources / Cluster |
| **6781** | Kubernetes All-in-one Cluster Monitoring |
| **763** | Kubernetes pods |
| **13946** | Alertmanager |
| **3662** | Prometheus 2.0 Overview and Stats |
| **9578** | MySQL Overview |
| **7353** | Redis Dashboard |
| **15172** | Thanos / global view |

Then **fork and trim** them — a 200-panel imported dashboard nobody reads is worse than a 12-panel one they do.

---

## 7. Ten panels you should be able to build from scratch

```promql
# 1. Availability over the selected range (stat, unit percentunit, thresholds 0.99/0.999)
avg_over_time(up{job="$service"}[$__range])

# 2. Error rate ratio (time series, percentunit)
sum(rate(http_requests_total{service=~"$service",status=~"5.."}[$__rate_interval]))
  / sum(rate(http_requests_total{service=~"$service"}[$__rate_interval]))

# 3. p99 / p95 / p50 latency (three queries, one panel, unit s)
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{service=~"$service"}[$__rate_interval])))

# 4. QPS by status class (stacked bars)
sum by (status_class) (rate(http_requests_total{service=~"$service"}[$__rate_interval]))

# 5. Latency heatmap — query type "Heatmap", format Heatmap
sum by (le) (rate(http_request_duration_seconds_bucket{service=~"$service"}[$__rate_interval]))

# 6. Top 10 slowest endpoints (bar gauge / table, instant)
topk(10, histogram_quantile(0.99,
  sum by (le, path) (rate(http_request_duration_seconds_bucket{service=~"$service"}[$__rate_interval]))))

# 7. Memory vs limit (time series with two queries + threshold line)
sum by (pod) (container_memory_working_set_bytes{namespace="$namespace", pod=~"$pod"})
sum by (pod) (kube_pod_container_resource_limits{namespace="$namespace", resource="memory"})

# 8. CPU throttling (time series, percentunit) — explains "slow but not busy"
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="$namespace"}[$__rate_interval]))
  / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="$namespace"}[$__rate_interval]))

# 9. Disk full ETA (table, unit s, transform to date)
(node_filesystem_avail_bytes{instance=~"$node"} / deriv(node_filesystem_avail_bytes{instance=~"$node"}[6h]))

# 10. SLO error budget remaining (gauge, percentunit)
1 - (
  sum(increase(http_requests_total{status=~"5.."}[$__range]))
    / sum(increase(http_requests_total[$__range]))
) / (1 - 0.999)     # clamp to [0,1] with a transformation if needed
```

---

## 8. Grafana alerting (know it, use it deliberately)

If you do use it: **Alerting → Contact points / Notification policies / Alert rules**, provisioned via `provisioning/alerting/rules.yaml`:

```yaml
apiVersion: 1
groups:
  - orgId: 1
    name: business-alerts
    folder: Business
    interval: 1m
    rules:
      - uid: checkout-success-rate
        title: Checkout success rate below 95%
        condition: C
        data:
          - refId: A
            relativeTimeRange: {from: 900, to: 0}
            datasourceUid: prometheus
            model:
              expr: |
                sum(rate(checkout_completed_total[$__rate_interval]))
                  / sum(rate(checkout_started_total[$__rate_interval]))
              refId: A
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              expression: A
              conditions:
                - evaluator: {type: lt, params: [0.95]}
                  operator: {type: and}
              refId: C
        for: 10m
        labels: {severity: page, team: checkout}
        annotations:
          summary: "Checkout success rate {{ $values.A.Value.String }} < 95%"
          runbook: "https://runbooks.example.com/checkout"
```

Use Grafana alerting when the signal lives in **a non-Prometheus data source** (CloudWatch billing, MySQL business tables, Loki log patterns). Otherwise keep rules in Prometheus so they're GitOps'd, `promtool`-tested and version-controlled next to your scrape config.

---

## 9. Performance and cost

- **Query concurrency matters**: a dashboard with 40 panels × 5 viewers refreshing every 10 s = sustained load on Prometheus. Watch `prometheus_engine_query_duration_seconds` and Grafana's own `grafana_http_request_duration_seconds`.
- **Provisioning + `timeInterval`** aligned to the scrape interval avoids Grafana generating impossible resolutions.
- Use **recording rules** for any panel query that takes > 500 ms.
- Enable **data source caching** (`cacheLevel: High`) and **incremental querying**.
- Consider **Grafana's Prometheus query sharding / `prometheusType`** and, at scale, an **enterprise/caching layer** (Mimir's query-frontend caches and splits queries — big win).
- Set **`GF_DASHBOARDS_MIN_REFRESH_INTERVAL`** to stop wall displays hammering.
- Prune: Grafana's **"Recently viewed"** and dashboard usage analytics tell you which dashboards nobody opens. Delete them.

---

## Lab

1. Provision the data source and one dashboard from files; restart Grafana and confirm they survive.
2. Import dashboard **1860** (Node Exporter Full) and trim it to 10 panels you'd actually read.
3. Build a service dashboard with the Row-1 layout above, using `$service` and `$namespace` variables and `$__rate_interval` everywhere.
4. Add a deploy annotation and a data link from the latency panel to a logs view.
5. Deliberately set `Min step` to `1s` on one panel, zoom to 30 days, and watch Prometheus's query duration metric spike. Fix it.
6. Export your dashboard JSON to `grafana/dashboards/` and commit it.

---

## Self-check

1. Why must dashboard JSON live in Git rather than the Grafana database?
2. `$__interval` vs `$__rate_interval` — which do you use in `rate()` and why?
3. What does `timeInterval` in the data source config do, and what breaks if it's wrong?
4. How do you make one dashboard serve 40 services?
5. Why should symptoms be at the top of a dashboard and causes below?
6. Give three panels that belong on a service dashboard's first row.
7. How do you turn a latency histogram into a heatmap panel?
8. Your panel shows gaps when zoomed out to 7 days. Two likely causes?
9. When is Grafana alerting the right choice over Prometheus rules?
10. What makes a deploy annotation so valuable during an incident?

→ Next: [`08-Kubernetes-Monitoring`](../08-Kubernetes-Monitoring/README.md)
