# 03 · Metrics & Instrumentation

**Level:** practical · **Time:** ~2.5 h + Lab 3 · **Goal:** expose metrics from your own code, choose the right metric type, name things correctly, and never blow up cardinality.

---

## 1. The exposition format

Prometheus scrapes plain text over HTTP. That's the whole protocol:

```http
GET /metrics HTTP/1.1
200 OK
Content-Type: text/plain; version=0.0.4; charset=utf-8
```
```text
# HELP http_requests_total The total number of HTTP requests.
# TYPE http_requests_total counter
http_requests_total{method="post",code="200"} 1027 1726294800000
http_requests_total{method="post",code="400"} 3 1726294800000

# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{le="0.05"} 24054
http_request_duration_seconds_bucket{le="0.1"}  33444
http_request_duration_seconds_bucket{le="0.5"}  100392
http_request_duration_seconds_bucket{le="+Inf"} 144320
http_request_duration_seconds_sum   53423
http_request_duration_seconds_count 144320

# TYPE node_memory_MemAvailable_bytes gauge
node_memory_MemAvailable_bytes 1.4165835776e+10

# TYPE app_build_info gauge
app_build_info{version="1.4.2",revision="a1b2c3d",go_version="1.23"} 1
```

Formats: **text 0.0.4** (default), **OpenMetrics** (adds `# UNIT`, `_created` timestamps, exemplars), **protobuf** (needed for native histograms). With Prometheus 3 + UTF-8 enabled, `http.server.request.duration` is a legal metric name — quote it when querying: `{"http.server.request.duration"}`.

`HELP` and `TYPE` are comments to the storage engine but documentation to humans — **always emit them**.

---

## 2. Choosing the metric type (decision table)

| You want to record… | Use | Why |
|---|---|---|
| Something that only ever increases (requests, errors, bytes, restarts) | **Counter** | Survives restarts via `rate()`; never query raw |
| Something that goes up and down (queue depth, memory, temperature, connections in use) | **Gauge** | Raw value is meaningful |
| Latency or response size, aggregated across many instances | **Histogram** | Buckets are additive → you can compute a global p99 |
| Latency on a *single* instance, pre-computed quantiles, no aggregation needed | **Summary** | Cheaper on the server, but quantiles are **not** aggregatable |
| Very high-resolution latency at low cardinality | **Native histogram** | Exponential buckets, no fixed boundaries (experimental flag) |
| Version/build/deploy metadata | **Info metric** (constant gauge = 1 with labels) | Join with `group_left` to annotate other series |
| A state out of a fixed set (mode=active/standby) | **Enum gauge** (one series per state, 1 for current) | `sum by (state)` gives transitions |
| A one-shot batch job result | **Pushgateway** + counter/gauge | Job may not live long enough to be scraped |

### Histogram vs Summary — the classic interview question

| | **Histogram** | **Summary** |
|---|---|---|
| Quantiles computed | Server-side (PromQL) at **query time** | Client-side at **collection time** |
| Aggregatable across instances? | ✅ Yes (`histogram_quantile(sum by (le)(rate(...)))) `) | ❌ No — averaging p99s is mathematically wrong |
| Bucket configuration | You choose `le` boundaries up front (or use native histograms) | You choose objectives + max age |
| Cost | More series (one per bucket), cheaper client CPU | Fewer series, expensive client CPU |
| Rule of thumb | **Default choice** | Only when you truly need exact per-instance quantiles and won't aggregate |

**Histogram bucket boundaries matter.** Default buckets (`0.005 … 10`) are useless if your p99 is 300 ms or 30 s. Set them around your SLO:

```python
# Python
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency in seconds",
    ["method", "path", "status"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)
```
Rule of thumb: put a bucket **just above and just below your SLO threshold** so the quantile estimate is accurate where you care.

---

## 3. Naming and labelling conventions

**Naming rules (official conventions):**

- `snake_case`, `[a-zA-Z_:][a-zA-Z0-9_:]*`.
- **Single logical thing per metric.** Never mix counters and gauges in one name.
- **Base unit in the suffix**: `_seconds`, `_bytes`, `_ratio` (0–1), `_total` (counters), `_info`, `_count`.
- Prefix with the **subsystem**: `http_`, `node_`, `kube_`, `myapp_`.
- `_total` suffix is mandatory for counters in OpenMetrics.
- **No label in the name.** ❌ `http_requests_500_total` ✅ `http_requests_total{status="500"}`.

| Good | Bad | Why |
|---|---|---|
| `api_request_duration_seconds` | `api_latency` | No unit |
| `api_requests_total{status="500"}` | `api_5xx_errors_total` | Label belongs in the dimension |
| `queue_depth_messages` | `queue_size` | Ambiguous unit |
| `db_connection_pool_in_use_connections` | `db_pool_used` | Vague |
| `cache_ratio{type="hit"}` 0–1 | `cache_hit_percent` 0–100 | Percentages break aggregation |

**Labels:** use them for dimensions you will *group or filter by* in a query — `method`, `status`, `path`, `queue`, `shard`, `team`, `env`, `region`, `instance`. 

**Never** use as labels: user IDs, session IDs, request/trace IDs, emails, raw URLs with query strings, unbounded enums, timestamps, high-cardinality error messages, Kubernetes UIDs. Each distinct combination is a permanent series in your TSDB.

### The cardinality budget

```
1 metric × N labels →  product of distinct values per label = series count
```
Keep per-metric cardinality in the **hundreds to low thousands**. Budget for the whole Prometheus: 100k series (small) → 1M (large single node) → beyond that, shard or use a long-term store.

```promql
# Find your offenders
topk(10, count by (__name__)({__name__=~".+"}))
count by (__name__)({__name__=~".+"}) > 5000
count by (job)({__name__=~".+"})
```

---

## 4. Instrumenting an application

### Python (`prometheus_client`)

```python
from prometheus_client import Counter, Histogram, Gauge, Info, start_http_server, REGISTRY
import time, random

REQUESTS = Counter(
    "myapp_http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)
LATENCY = Histogram(
    "myapp_http_request_duration_seconds",
    "Request latency",
    ["method", "path"],
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
QUEUE = Gauge("myapp_queue_depth", "Items waiting to be processed")
BUILD = Info("myapp_build", "Build information")
BUILD.info({"version": "1.4.2", "revision": "a1b2c3d"})

start_http_server(8000)          # exposes /metrics on :8000

@app.route("/api/<path>")
def handler(path):
    with LATENCY.labels("GET", f"/api/{path}").time():
        ...
    REQUESTS.labels("GET", f"/api/{path}", "200").inc()
```
Also available: `@LATENCY.labels(...).time()` decorator, `prometheus_client.make_asgi_app()` for FastAPI/ASGI, `process` and `platform` collectors on by default (`process_cpu_seconds_total`, `process_resident_memory_bytes`, `python_gc_*`).

### Go (`prometheus/client_golang`)

```go
package main

import (
    "net/http"
    "strconv"
    "time"

    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    requests = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "myapp_http_requests_total",
        Help: "Total HTTP requests.",
    }, []string{"method", "path", "status"})

    latency = promauto.NewHistogramVec(prometheus.HistogramOpts{
        Name:    "myapp_http_request_duration_seconds",
        Help:    "Request latency in seconds.",
        Buckets: []float64{.01, .05, .1, .25, .5, 1, 2.5, 5, 10},
    }, []string{"method", "path"})

    queueDepth = promauto.NewGauge(prometheus.GaugeOpts{
        Name: "myapp_queue_depth",
        Help: "Items waiting to be processed.",
    })
)

func middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        rw := &statusRecorder{ResponseWriter: w, status: 200}
        next.ServeHTTP(rw, r)
        requests.WithLabelValues(r.Method, r.URL.Path, strconv.Itoa(rw.status)).Inc()
        latency.WithLabelValues(r.Method, r.URL.Path).Observe(time.Since(start).Seconds())
    })
}

func main() {
    http.Handle("/", middleware(mux))
    http.Handle("/metrics", promhttp.Handler())     // add promhttp.InstrumentMetricHandler for scrape self-metrics
    http.ListenAndServe(":8080", nil)
}
```
`promauto` auto-registers — you avoid the classic "forgot to register, metric never appears" bug.

### Java / Micrometer (Spring Boot)

```xml
<dependency><groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-actuator</artifactId></dependency>
<dependency><groupId>io.micrometer</groupId>
  <artifactId>micrometer-registry-prometheus</artifactId></dependency>
```
```yaml
management:
  endpoints.web.exposure.include: health,info,prometheus
  metrics.tags.application: ${spring.application.name}
  metrics.distribution.percentiles-histogram.http.server.requests: true   # histograms, not summaries!
  metrics.distribution.slo.http.server.requests: 100ms,300ms,1s
```
Micrometer normalises `http.server.requests` → `http_server_requests_seconds_*` for Prometheus. Enable `percentiles-histogram` or you'll only get non-aggregatable summaries.

### Node.js (`prom-client`)

```js
const client = require('prom-client');
client.collectDefaultMetrics({ prefix: 'myapp_' });

const httpDuration = new client.Histogram({
  name: 'myapp_http_request_duration_seconds',
  help: 'Request latency',
  labelNames: ['method', 'path', 'status'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

app.use((req, res, next) => {
  const end = httpDuration.startTimer({ method: req.method, path: req.route?.path ?? 'unmatched' });
  res.on('finish', () => end({ status: res.statusCode }));
  next();
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});
```
> Note `req.route?.path ?? 'unmatched'` — using `req.path` raw is the #1 Node.js cardinality explosion.

---

## 5. The standard exporters you must know

| Exporter | Port | Gives you | Notes |
|---|---|---|---|
| **node_exporter** | 9100 | Host CPU, memory, disk, network, filesystem, load | Enable extra collectors: `--collector.textfile.directory=/var/lib/node_exporter`, `--collector.systemd`, `--collector.processes` |
| **blackbox_exporter** | 9115 | Synthetic HTTP/TCP/ICMP/DNS/gRPC probes | `probe_success`, `probe_duration_seconds`, `probe_http_status_code`, TLS expiry |
| **kube-state-metrics** | 8080 | K8s object *state* (deployments, pods, nodes, PVCs) | Not resource usage — that's cAdvisor |
| **cAdvisor** (built into kubelet) | 10250 `/metrics/cadvisor` | Container CPU/memory/network/fs | High cardinality; drop `id`, `image_id` |
| **mysqld / postgres / redis / mongodb / kafka** exporters | varies | DB-specific metrics | Use the official `prometheus/*_exporter` where they exist |
| **Pushgateway** | 9091 | Accepts pushed metrics from short-lived jobs | **Never** use it as a general collector; metrics persist forever until deleted |
| **snmp_exporter / ipmi_exporter / smartctl_exporter** | varies | Network & hardware | Config is generated, don't hand-write it |
| **otel-collector** (`prometheusexporter` / `prometheusremotewrite`) | 8889 | Bridges OTel → Prometheus | Modern path for polyglot estates |

### The textfile collector (custom host metrics without writing an exporter)

```bash
# /etc/cron.d/backup-metrics — every 5 minutes
*/5 * * * * root /usr/local/bin/backup-metrics.sh > /var/lib/node_exporter/backup.prom.$$ \
  && mv /var/lib/node_exporter/backup.prom.$$ /var/lib/node_exporter/backup.prom
```
```text
# backup.prom
# HELP backup_last_success_timestamp_seconds Unix time of last successful backup.
# TYPE backup_last_success_timestamp_seconds gauge
backup_last_success_timestamp_seconds{job_name="db-dump"} 1757800000
# TYPE backup_last_duration_seconds gauge
backup_last_duration_seconds{job_name="db-dump"} 412
# TYPE backup_exit_code gauge
backup_exit_code{job_name="db-dump"} 0
```
Write to a temp file then `mv` — Prometheus may read a half-written file otherwise.

### Pushgateway — the correct (limited) use

```bash
echo "batch_job_records_processed_total 1423" | curl --data-binary @- \
  http://pushgateway:9091/metrics/job/batch_etl/instance/cron-01
# delete when the job instance is gone:
curl -X DELETE http://pushgateway:9091/metrics/job/batch_etl/instance/cron-01
```
```yaml
- job_name: pushgateway
  honor_labels: true
  static_configs: [{targets: ['pushgateway:9091']}]
```
Gotchas: pushed metrics **never expire** (a dead job looks healthy forever) → alert on `push_time_seconds` staleness; no `up` metric semantics; loses the "target is gone" signal. Prefer a long-running exporter or OTLP push where possible.

---

## 6. Batch jobs, cron and "did it run?" monitoring

Three separate questions, three separate metrics:

| Question | Metric | Alert |
|---|---|---|
| Did it **start**? | `cron_last_start_timestamp_seconds` / Pushgateway `push_time_seconds` | `time() - cron_last_start_timestamp_seconds > 2 * schedule_period` |
| Did it **succeed**? | `cron_exit_code` / `job_success_total` | `cron_exit_code != 0` |
| Is it **slow/degraded**? | `job_duration_seconds` histogram | p95 over threshold |

The simplest robust pattern for "this must run every hour": a **heartbeat/dead-man's-switch** — the job curls an external watchdog (Healthchecks.io, Cronitor, or your own `absent()` rule) on success; if the ping stops, you get paged. Missing data is the signal.

---

## 7. OpenTelemetry and the OTel ↔ Prometheus relationship

OTel is a vendor-neutral standard for **instrumentation** (SDKs + Collector) covering metrics, logs and traces. Prometheus is a **metrics backend**. They compose:

```
app (OTel SDK) ──OTLP──► OTel Collector ──┬──► Prometheus (otlphttp exporter → :9090/api/v1/otlp)
                                          ├──► remote_write (Mimir/Thanos)
                                          └──► traces/logs backends
```
Or, since Prometheus 3.0, skip the collector: `--web.enable-otlp-receiver` and point the SDK straight at it.

Translation strategies (config under `otlp:` in `prometheus.yml`):

| Strategy | Behaviour | Use when |
|---|---|---|
| `UnderscoreEscapingWithSuffixes` (**default**) | dots→underscores, adds `_seconds`/`_bytes` | Existing Prometheus-heavy estate |
| `NoUTF8EscapingWithSuffixes` | Keeps `http.server.request.duration`, adds unit suffix | New, OTel-first stacks |
| `UnderscoreEscapingWithoutSuffixes` | No unit suffix | Rare (collision risk) |
| `NoTranslation` | Verbatim OTel names | Max fidelity, max risk |

Promote the resource attributes you actually need as labels:

```yaml
otlp:
  translation_strategy: NoUTF8EscapingWithSuffixes
  promote_resource_attributes:
    - service.name
    - service.namespace
    - service.version
    - deployment.environment
    - k8s.cluster.name
    - k8s.namespace.name
    - k8s.pod.name
```

**When to use which:** OTel SDK when you want one instrumentation across metrics+logs+traces and possibly multiple vendors; native Prometheus client libraries when you only need metrics and want the simplest possible dependency. Both end up in Prometheus.

---

## 8. Instrumentation checklist for a new service

Copy this into your service's PR template:

- [ ] `/metrics` endpoint exists, is not publicly exposed, and is scraped.
- [ ] **RED** metrics present: request rate, errors (by status class), duration histogram with SLO-aligned buckets.
- [ ] **USE**-ish resource metrics: in-flight requests, queue depth, connection-pool in-use/idle/max, goroutines/threads, GC pause.
- [ ] Dependency metrics: DB query duration/errors, cache hit ratio, downstream call duration/errors.
- [ ] Build/version **info metric** with labels `version`, `revision`, `branch`.
- [ ] Business metric(s) that map to the SLO (e.g. `checkout_completed_total`).
- [ ] Metric names follow `<subsystem>_<name>_<unit>`; counters end in `_total`; ratios are 0–1.
- [ ] No unbounded labels (user IDs, raw paths). Paths are normalised to route templates.
- [ ] `HELP` strings on every metric.
- [ ] Dashboard exists (`07-Grafana-Dashboards`) with RED panels.
- [ ] Alert rules exist (`05`, `13`) and are unit-tested with `promtool test rules`.

---

## 9. Mistakes that cost people production incidents

1. **Raw path as a label** → 500k series, Prometheus OOM in a day.
2. **Summary instead of histogram** → global p99 is silently wrong (averaging quantiles).
3. **Histogram buckets from the library default** → p99 estimated as "+Inf bucket boundary".
4. **Gauge used for something monotonic** → `rate()` on a gauge is nonsense; you get negative spikes.
5. **Counter reset not handled** → use `rate()`/`increase()` which handle resets; never `delta()` a counter.
6. **`honor_labels: true` set blindly** → your `job`/`instance` labels get overwritten by the target's.
7. **Pushgateway as the only path for a critical job** → job dies, metric stays at last value forever, nobody notices.
8. **No `_total` suffix / wrong unit** → dashboards and alerts silently use the wrong scale (`ms` vs `seconds`).
9. **Instrumenting in a hot loop without labels bounded** → client-side CPU spike from label hashing.
10. **Not testing rules** → alert ships, never fires, discovered during a real outage.

---

## Lab

In [`16-Labs/app`](../16-Labs/README.md) there is a tiny Flask service with deliberate instrumentation mistakes.

1. Run it, `curl localhost:8000/metrics`, and identify the metric types.
2. Generate traffic, then compute p50/p95/p99 in PromQL from the histogram.
3. Fix the deliberately wrong histogram buckets and re-measure — notice how the p99 estimate changes.
4. Add a new counter for a business event and expose it.
5. Run `topk(5, count by (__name__)({__name__=~".+"}))` and find your own offender.

---

## Self-check

1. Histogram vs summary: which can you aggregate across pods, and why?
2. What four naming conventions does the Prometheus style guide require?
3. Give five label values that are cardinality bombs.
4. Write the exposition-format output for a counter and a histogram by hand.
5. When is Pushgateway the *right* tool, and what signal do you lose by using it?
6. You need an accurate p99 near a 300 ms SLO — where do you put histogram buckets?
7. How does Prometheus 3 accept OpenTelemetry metrics without a collector?
8. What three metrics answer "did my hourly cron job work?"

→ Next: [`04-PromQL`](../04-PromQL/README.md)
