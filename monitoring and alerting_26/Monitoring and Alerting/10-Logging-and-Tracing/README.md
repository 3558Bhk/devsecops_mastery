# 10 · Logging & Tracing

**Level:** complementary · **Time:** ~2 h · **Goal:** know how logs and traces fit next to metrics, how to correlate the three, and when to reach for each during an incident.

---

## 1. Where each pillar earns its keep

| Incident phase | Reach for | Why |
|---|---|---|
| **Detect** ("something is wrong") | **Metrics** (SLO burn, `up`, error ratio) | Cheap, always-on, aggregatable, fast to alert |
| **Triage** ("how bad, which service?") | **Metrics** dashboards (RED by service/version/region) | Slices the impact instantly |
| **Localise** ("which request path is slow?") | **Traces** | Shows the cross-service span tree and where time went |
| **Diagnose** ("why did it fail?") | **Logs** | Stack traces, error messages, business context |
| **Confirm fix** | **Metrics** again | The SLI recovers |

Corollary: **alert on metrics, investigate with traces and logs.** Alerting on logs is possible (Loki ruler, CloudWatch metric filters) but expensive and laggy — use it only for events with no metric equivalent (`panic`, `FATAL`, audit lines, a specific exception class).

---

## 2. Logging

### Structured logs are the whole game

```json
{"time":"2026-09-14T12:03:11.482+05:30","level":"error","msg":"payment declined",
 "service":"checkout-api","version":"1.4.2","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736",
 "span_id":"00f067aa0ba902b7","user_tier":"gold","provider":"stripe","status_code":502,
 "duration_ms":412,"err":"upstream timeout"}
```
Why: fields are **queryable and aggregatable** without regex, and `trace_id` is the join key to traces. Unstructured logs force you to write brittle regex parsers at query time.

Rules:
- **JSON** (or logfmt) in production; pretty-print locally.
- **One log line per meaningful event**, at the right level.
- **Levels mean things:** `debug` (off in prod), `info` (state changes, request completed), `warn` (recoverable anomaly), `error` (this request failed), `fatal` (process will exit).
- **Never log secrets**, tokens, full card numbers, or PII beyond what policy allows. Add a redaction layer if you can't trust authors.
- **Always include** `service`, `version`, `env`, `trace_id`, `span_id`, and a correlation/request ID.
- **Cardinality discipline applies to logs too**: don't put unbounded IDs in fields you intend to index as labels in Loki (see below).

### Log pipelines

```
app stdout ──► collector ──► store ──► query UI
             (Promtail/Alloy,          (Loki / OpenSearch /
              Fluent Bit, Vector,       Elasticsearch / CloudWatch
              OTel Collector,            Logs)
              Filebeat)
```

| Option | Model | Good at | Watch out for |
|---|---|---|---|
| **Grafana Loki** | Indexes **labels only**, stores compressed log lines | Cheap, Grafana-native, LogQL, `derived fields` → traces | Label cardinality explosions; slow full-text scans over huge ranges |
| **Elasticsearch / OpenSearch** | Full-text inverted index | Powerful search, aggregations, Kibana/OpenSearch Dashboards | Expensive at scale; JVM ops burden |
| **CloudWatch Logs** | AWS-managed | Zero ops, IAM-integrated, metric filters + alarms | Cost per GB ingested/stored; weak query language |
| **ClickHouse-based (SigNoz, Uptrace, HyperDX)** | Columnar | Very fast, cheap, SQL | Newer ecosystem |
| **Vector / Fluent Bit** | Pipeline (transform/route/sample) | Sampling, redaction, fan-out, cost control | Another component to run |

**Loki label rule (the equivalent of Prometheus cardinality):** index only low-cardinality fields as **labels** (`service`, `env`, `level`, `namespace`); everything else stays in the **log line** and is queried with LogQL parsers. Putting `user_id` or `trace_id` in a Loki label will destroy your cluster.

```logql
# Loki LogQL essentials
{namespace="checkout", app="checkout-api"} |= "payment declined"
{app="checkout-api"} | json | status_code >= 500 | line_format "{{.msg}} trace={{.trace_id}}"
sum by (app) (rate({level="error"}[5m]))                                  # metric query from logs
count_over_time({app="checkout-api"} |~ "(?i)timeout" [1h])
{app="checkout-api"} | json | duration_ms > 1000 | unwrap duration_ms | quantile_over_time(0.99, ...)
# Alerting on logs (Loki ruler)
sum by (app) (rate({level="error"}[5m])) > 0.5
```

### Kubernetes logging specifics

- Containers write to **stdout/stderr**; the kubelet stores them in `/var/log/pods/<ns>_<pod>_<uid>/<container>/*.log` and symlinks `/var/log/containers/`.
- **Rotated and deleted when the pod dies** — so shipping must be continuous (DaemonSet collector reading the host path).
- Add metadata via the collector's k8s discovery (namespace, pod, labels) rather than making the app do it.
- Consider **`kubectl logs --previous`** for crashlooping containers, and sidecar vs DaemonSet collection (DaemonSet is the default; sidecars for per-pod isolation/multi-tenant).

---

## 3. Tracing

### Concepts

| Term | Meaning |
|---|---|
| **Span** | One unit of work: name, start, duration, attributes, events, parent span, status |
| **Trace** | A tree of spans sharing one `trace_id`, representing one request end to end |
| **Context propagation** | Carrying `traceparent` (W3C Trace Context) across process boundaries — HTTP headers, gRPC metadata, queue message attributes |
| **Root span** | The entry point (the ingress/LB or first service) |
| **Sampling** | Deciding which traces to record: head-based (decide at trace start) vs tail-based (decide after seeing the whole trace) |
| **Baggage** | Extra key-values propagated alongside the trace context (use sparingly) |

### Backends

| Backend | Notes |
|---|---|
| **Grafana Tempo** | Object-storage backed, cheap, TraceQL, integrates with Loki/Grafana exemplars |
| **Jaeger** | CNCF, mature UI, supports OTLP natively |
| **OpenTelemetry Collector → any** | The collector is vendor-neutral; swap backends freely |
| **AWS X-Ray / GCP Cloud Trace / Azure App Insights** | Managed, tight cloud integration |
| **SigNoz / Uptrace / HyperDX / Grafana Cloud Traces** | OSS or SaaS all-in-one |

**TraceQL (Tempo)** is worth knowing:
```traceql
{ .service.name = "checkout-api" && duration > 1s }
{ span.http.status_code = 502 && resource.cluster = "prod-2" }
{ .service.name = "checkout-api" } >> { .service.name = "payments" }    # parent → child
{ status = error && .http.route = "/checkout/complete" }
```

### Sampling strategy (this is the cost lever)

| Strategy | How | When |
|---|---|---|
| **Head-based, probabilistic** | SDK decides at trace start (`ParentBased(TraceIDRatioBased(0.1))`) | High-volume, cheap, may miss the failing request |
| **Head-based, rate-limiting** | N traces/sec per process | Predictable cost |
| **Tail-based (in the Collector)** | Collector buffers spans, then keeps traces matching rules: errors, latency > X, specific attributes | **Best signal per dollar**: keep 100% of errors and slow traces, 1% of the rest |
| **Always-on** | 100% | Dev/staging only |

```yaml
# OTel Collector tail sampling
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - {name: errors,  type: status_code, status_code: {status_codes: [ERROR]}}
      - {name: slow,    type: latency,     latency: {threshold_ms: 1000}}
      - {name: normal,  type: probabilistic, probabilistic: {sampling_percentage: 5}}
```

---

## 4. Correlating the three pillars (the payoff)

### Metrics → Traces: **exemplars**

An **exemplar** attaches a `trace_id` to a specific histogram bucket sample. In Grafana, exemplars render as **clickable dots** on a time series/heatmap; clicking one opens the trace. This turns "p99 spiked at 14:02" into "here is the actual slow request" in one click.

Enable in Prometheus:
```bash
prometheus --enable-feature=exemplar-storage
```
```yaml
# scrape_config
    - job_name: checkout-api
      # OTel SDKs expose exemplars on the OpenMetrics endpoint automatically
      # when the metric is scraped as OpenMetrics (Content-Type negotiation)
```
Grafana data source:
```yaml
jsonData:
  exemplarTraceIdDestinations:
    - name: traceID
      datasourceUid: tempo
```

### Traces → Logs: `trace_id` in both

Every log line carries `trace_id`; every span carries it. In Grafana, a **derived field** on the Loki data source turns `trace_id` into a link:
```yaml
jsonData:
  derivedFields:
    - name: traceID
      matcherRegex: '"trace_id":"(\w+)"'
      url: '$${__value.raw}'
      datasourceUid: tempo
```
And from a trace view, Grafana's "Logs for this span" button queries Loki with the same `trace_id`.

### Logs → Metrics

Promote a log pattern into a metric (Loki ruler recording rule, `count_over_time`), then alert on the metric. Cheap and effective for "this exception should never happen".

### The standard correlation label set

Make these **identical** in metrics labels, log fields and span resource attributes:

```
service.name / job / app
service.version / version
deployment.environment / env
k8s.namespace.name / namespace
k8s.pod.name / pod
host.name / instance
cloud.region / region
cluster
trace_id  (logs + spans; metrics via exemplars)
```
The OpenTelemetry **semantic conventions** define these names; the OTel Collector's `resource` processor or Prometheus's `promote_resource_attributes` maps them into labels. **Do this once, at the collector**, not per-team.

---

## 5. OpenTelemetry as the unifying layer

```
        ┌── metrics ──┐
app ────┤             ├──► OTel Collector ──┬──► Prometheus (OTLP receiver or remote_write)
SDK     ├── traces  ──┤   (batch, tail-     ├──► Tempo / Jaeger / vendor
(auto + ├── logs    ──┘    sample, enrich,  ├──► Loki / vendor logs
 manual)                   redact)         └──► second vendor (dual shipping)
```

Value: **one instrumentation, any backend.** Auto-instrumentation exists for Java (agent), Python, Node, .NET, Go (mostly manual), and via OTel Operator for Kubernetes (injects agents by annotation).

```bash
# Kubernetes auto-instrumentation (OTel Operator)
kubectl apply -f - <<'YAML'
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata: {name: otel-auto, namespace: checkout}
spec:
  exporter: {endpoint: http://otel-collector.observability:4317}
  propagators: [tracecontext, baggage]
  sampler: {type: parentbased_traceidratio, argument: "0.1"}
  python:   {image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:latest}
  nodejs:   {image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:latest}
YAML
# then annotate the workload
kubectl -n checkout patch deployment checkout-api -p \
 '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-python":"otel-auto"}}}}}'
```

**Pragmatic guidance:** if you only need metrics and run Prometheus, a native Prometheus client library is simpler and has fewer moving parts. Adopt OTel when you also need traces/logs, when you're multi-language, or when you want backend portability. Both paths land in the same Prometheus.

---

## 6. Cost control (logs and traces are where the money goes)

| Lever | Effect |
|---|---|
| **Sample traces** (tail-based) | 5–20× cost reduction while keeping all errors |
| **Log levels by service** (`debug` off in prod) | Often 3–10× |
| **Drop noisy log lines at the collector** (`filter` processor) | Cheap win |
| **Shorten retention tiers** | 7d hot / 30d warm / 1y cold object storage |
| **Loki label discipline** | Prevents index blowup |
| **Aggregate logs into metrics** where you only need counts | 100× cheaper to alert on |
| **Ship only what's queried** — review the top-N log streams monthly | |
| **Compress + object storage** for traces (Tempo) instead of an index | |

---

## 7. Self-check

1. Which pillar do you alert on, and why not the other two?
2. Name the fields every production log line must carry.
3. Why is `trace_id` a bad Loki *label* but a great log *field*?
4. What is an exemplar and what does it let a user do in Grafana?
5. Head-based vs tail-based sampling — which guarantees you keep the failing request, and what does it cost?
6. What is W3C Trace Context and what header carries it?
7. Give the label/attribute set that must be identical across all three pillars.
8. Write a LogQL query that counts 5xx logs per app over 5 minutes.
9. When would you use a sidecar log collector instead of a DaemonSet?
10. Name four cost levers for traces.

→ Next: [`11-Scaling-and-Long-Term-Storage`](../11-Scaling-and-Long-Term-Storage/README.md)
