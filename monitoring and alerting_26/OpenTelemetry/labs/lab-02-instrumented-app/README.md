# Lab 02 — Instrumented App → Collector → Tempo + Prometheus + Loki

**Goal:** the **correlation triangle**. Metric → trace → log → back to metric, working end to end across three specialised backends. This is the lab that shows *why* you'd run OpenTelemetry at all.

**Time:** 60–90 minutes (first build ~3 min). **Prerequisites:** Docker, ~4 GB free RAM, Lab 01 concepts.

**Companion reading:** [`../../05-traces.md`](../../05-traces.md) · [`../../06-metrics.md`](../../06-metrics.md) · [`../../07-logs.md`](../../07-logs.md) · [`../../09-sdks-and-instrumentation.md`](../../09-sdks-and-instrumentation.md) · [`../../13-backends.md`](../../13-backends.md)

---

## What's in this lab

| Path | Role |
|---|---|
| `otel-collector-config.yaml` | ★ **Validated against `otelcol-contrib` v0.161.0.** Three signals, redaction, two `span_metrics` connector instances |
| `app/main.py` | FastAPI service with **manual spans**, log correlation, and **two deliberate mistakes** |
| `app/Dockerfile` | ★ `opentelemetry-instrument` zero-code launcher + `opentelemetry-bootstrap` |
| `app/requirements.txt` | Pinned: SDK **1.44.0**, contrib **0.65b0** — ★ versioned on separate tracks |
| `tempo.yaml` | Tempo 3.x single-binary with `metrics_generator` |
| `loki-config.yaml` | Loki 3.x with ★ `allow_structured_metadata` and explicit label promotion |
| `prometheus.yml` | Scrapes the Collector **and** accepts remote-write |
| `grafana/provisioning/` | ★★ **The correlation wiring** + the "Correlation Triangle" dashboard |
| `docker-compose.yml` | 7 services: app, loadgen, collector, tempo, loki, prometheus, grafana |

---

## Run it

```bash
cd labs/lab-02-instrumented-app
docker compose up -d --build
docker compose ps
```

| URL | What |
|---|---|
| **http://localhost:3000** | Grafana (admin/admin) → *OpenTelemetry Labs* → **Lab 02 — The Correlation Triangle** |
| http://localhost:8000/docs | The demo app's OpenAPI UI — poke it directly |
| http://localhost:9090 | Prometheus |
| http://localhost:3200 | Tempo |
| http://localhost:3100/ready | Loki |
| http://localhost:13133 | Collector health |

```bash
docker compose logs -f checkout      # ★ app logs WITH trace_id / span_id inline
docker compose logs -f collector     # debug exporter output
docker compose down -v               # stop and wipe everything
```

---

## Exercise 1 — Prove zero-code instrumentation works

`app/main.py` **never imports the SDK**. It imports `opentelemetry.trace` (the API) and calls `trace.get_tracer(...)`. Everything else — provider, exporter, batching, FastAPI and `requests` instrumentation — is wired by the launcher:

```dockerfile
ENTRYPOINT ["opentelemetry-instrument"]
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Verify the two layers are distinguishable:**
1. In Grafana → **Explore** → Tempo → search `{ }` → open a trace for `checkout-service`.
2. Look at the **instrumentation scope** of each span. You should see:
   - `opentelemetry.instrumentation.fastapi` → the server span, named **`GET /products/{product_id}`** ★ *(a route **template** — bounded cardinality)*
   - `manual.lab` / `checkout-service` → your hand-written `get-product` span, named **`get-product`**
   - `opentelemetry.instrumentation.requests` → the outbound HTTP span

★ **This is the key mental model:** auto-instrumentation gives you the *plumbing* spans for free; manual spans add the *business* meaning. You almost always want both, and they nest correctly without any coordination.

---

## Exercise 2 — ★ The metric → trace hop (exemplars)

Open the **Correlation Triangle** dashboard, panel 1.

You should see small **diamonds** on the request-rate line. **Click one.** It opens the exact trace that produced that sample.

**If no diamonds appear, the link is broken. Check both halves:**
```bash
# 1. Prometheus must RETAIN exemplars (accepted != retained)
docker compose exec prometheus sh -c 'ps -o args= | grep -o exemplar-storage'

# 2. The datasource must know where to send the trace ID
grep -A6 exemplarTraceIdDestinations grafana/provisioning/datasources/datasources.yaml
```
★ **Without `--enable-feature=exemplar-storage`, Prometheus accepts exemplars and silently does not store them.** The link just never appears, with no error anywhere. This is the most common "why doesn't my metric→trace link work" cause.

Also note the datasource lists **both** `traceID` and `trace_id` as destination names — because the label depends on *who attached the exemplar* (Tempo's `metrics_generator` uses `traceID`; the OTel SDK/remote-write path uses `trace_id`). Listing both costs nothing.

---

## Exercise 3 — ★ The trace → log hop

In Grafana → Explore → **Tempo** → open any `checkout` trace → click a span → in the span detail panel click **Logs**.

Grafana runs a Loki query built from `tracesToLogs`:
```
{service_name="checkout-service"} |= "<trace_id>"
```

**Two things make this work, and they're configured in different places:**

1. **The span→label mapping** (`datasources.yaml`):
   ```yaml
   tracesToLogs:
     tags:
       - key: service.name      # span attribute
         value: service_name    # Loki label  ← ★ dots became underscores
   ```
   ★ **Loki promotes `service.name` to the label `service_name`.** Get this mapping wrong and the query returns nothing.

2. **The log → trace hop back** (`derivedFields` on the Loki datasource), which Exercise 4 covers.

---

## Exercise 4 — ★ The log → trace hop, and why Loki 3 changed it

Open the dashboard's logs panel. Every line shows:
```
2026-09-17 10:22:31 INFO [checkout-service][trace_id=5b8efff7... span_id=eee19b7e...] checkout - checkout succeeded order=ord-482913
```

**Where did `trace_id=` come from?** Two independent mechanisms, both configured:

| Mechanism | Configured where | Why it matters |
|---|---|---|
| **App formatter prints it** | `logging.basicConfig(format="...[trace_id=%(otelTraceID)s span_id=%(otelSpanID)s]...")` in `app/main.py` | ★ **The SDK adds the fields to the LogRecord; YOUR FORMATTER decides whether they appear.** Forgetting the format string is the #1 reason log correlation "doesn't work" |
| **OTLP structured metadata** | Loki 3 + `allow_structured_metadata: true` in `loki-config.yaml` | The OTel `traceId` lands in `metadata[trace_id]` **without the app printing anything** — which is how you correlate logs from **libraries you don't control** |

**Try the second path:** comment out the `trace_id=` part of the format string in `app/main.py`, rebuild, and confirm Grafana still offers a trace link — because the derived field now matches structured metadata instead of the line text.

★ **At scale the second mechanism is the one that matters.** You cannot edit every third-party library's log formatter, but you *can* rely on the SDK injecting trace context into the log record. **Prefer it.**

---

## Exercise 5 — ★ Compare two ways of generating span metrics

This lab generates RED metrics from traces **twice**, deliberately:

| Source | Configured in | Metric names |
|---|---|---|
| **Collector `span_metrics` connector** | `otel-collector-config.yaml` | `traces_span_metrics_calls_total`, `traces_span_metrics_duration_milliseconds_bucket` |
| **Tempo `metrics_generator`** | `tempo.yaml` | `traces_span_metrics_*` (Tempo's own naming), remote-written to Prometheus |

Compare them in Prometheus:
```promql
# Collector-generated
sum by (service_name) (rate(traces_span_metrics_calls_total{job="otel-collector-export"}[5m]))

# Everything, by source job — spot the duplicates
count by (__name__, job) ({__name__=~"traces_.*|traces_span.*"})
```

★ **Running both permanently for the same service is a mistake:** you double your ingest, and you get two sets of near-identical series that disagree slightly (different bucket boundaries, different dimension sets, different points in the pipeline). **Pick one.** The Collector connector is the better default because it happens *before* sampling decisions affect your metrics; Tempo's generator is better when you want the backend to own it and you're already paying for Tempo.

**Also verify the unit trap:**
```promql
traces_span_metrics_duration_milliseconds_bucket
```
★ The name says **milliseconds** because `connector.spanmetrics.useSecondAsDefaultMetricsUnit` is **FALSE** by default. If you enable that gate — or migrate a dashboard from a semconv V1 source, which uses seconds — **your p99 shows 0.5 instead of 500.** Always check the metric's `unit`, not just its name.

---

## Exercise 6 — ★ Prove redaction works (and learn why you must derive the metric)

The app deliberately leaks PII:
```python
span.set_attribute("customer.email", "someone@example.com")
span.set_attribute("customer.card",  "4111111111111111")
span.set_attribute("customer.note",  "contact billing@corp.internal for invoices")
```

**First, find out what the processor reports.** ★ **Verified: the `redaction` processor emits NO internal metrics in v0.161.0** — `processor/redactionprocessor/` has no `generated_telemetry.go` and no metrics in `metadata.yaml`. It writes **attributes onto the data**:

| Attribute | With `summary: info` | With `summary: debug` |
|---|:---:|:---:|
| `redaction.masked.count` | ✓ | ✓ |
| `redaction.allowed.count` | ✓ | ✓ |
| `redaction.ignored.count` | ✓ | ✓ |
| `redaction.masked.keys` | | ★ ✓ — **leaks which fields you consider sensitive** |

**So how do you alert on it?** This lab derives a metric from the attribute using a second connector instance:
```yaml
connectors:
  span_metrics/redaction_audit:
    namespace: redaction.audit
    dimensions:
      - name: redaction.masked.count      # ★ the attribute becomes a label
```
→ queryable as `redaction_audit_calls_total{redaction_masked_count="3"}` (dashboard panel 10).

**Verify end to end:**
1. In Tempo, open a `checkout` trace. Find `customer.card`.
   - ★ **Masked to asterisks** — the Visa pattern matched.
2. Find `customer.email` = `someone@example.com` → masked.
3. Find `customer.note` containing `billing@corp.internal` → ★ **the email inside it is masked, but the rest of the note survives.** That's `blocked_values` doing substring masking, not attribute removal — and it's why value patterns and key allowlists are complementary.
4. Check `redaction.masked.count` on the span.

**Then break it on purpose.** Set `allow_all_keys: false` and leave `allowed_keys` empty:
```yaml
  redaction:
    allow_all_keys: false
    allowed_keys: []          # ← ★ FAILS CLOSED: removes EVERY attribute
```
```bash
docker compose restart collector
```
★ **Every span attribute disappears.** `allowed_keys` is designed to fail closed — an empty list means "allow nothing." That's the opposite failure mode from `allow_all_keys: true`, which fails **open**: an attribute name you didn't anticipate passes through unredacted. **Choose deliberately.** See [`../../15-security-and-governance.md`](../../15-security-and-governance.md).

---

## Exercise 7 — ★ Discover that there is no `loki` exporter

If you came from a 2023–2025 tutorial, you probably expected this:
```yaml
exporters:
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
```

**Try it:**
```bash
cp otel-collector-config.yaml /tmp/broken.yaml
# edit /tmp/broken.yaml to use the loki exporter, then:
docker run --rm -v /tmp:/cfg otel/opentelemetry-collector-contrib:0.161.0 \
  validate --config=/cfg/broken.yaml
```
**Verbatim result:**
```
'exporters' unknown type: "loki" for id: "loki" (valid values: [coralogix dataset
sentry ... otlphttp ... prometheus_remote_write ... clickhouse])
```

★ **`loki` exists in v0.161.0 only as a RECEIVER** (to read *from* Loki). The exporter is gone. **The correct path is Loki's native OTLP ingestion:**
```yaml
exporters:
  otlphttp/loki:
    endpoint: http://loki:3100/otlp     # otlphttp appends /v1/logs
```

**Why this is better, not just different:**

| | Old `loki` exporter | ★ Native OTLP (Loki 3+) |
|---|---|---|
| Translation layer | Yes — `otel2loki` conversion | **None** |
| `trace_id` / `span_id` | Fields in a JSON log message | ★ **`metadata[trace_id]`** — structured metadata |
| `severity_number` | **Not available** | `metadata[severity_number]` |
| `observed_timestamp` | **Not available** | `metadata[observed_timestamp]` |
| Attribute `thread.name` | JSON field in the message | `metadata[thread_name]` ★ (dots → underscores) |
| Which attributes become labels | Hints: `loki.resource.labels`, `loki.attribute.labels` | ★ Loki-side `default_resource_attributes_as_index_labels` |
| Cardinality control | Exporter config | **Loki distributor config** |

★ **The design point:** Loki promotes a **fixed, low-cardinality** set of resource attributes to index labels (`service.name`, `service.namespace`, `service.instance.id`, `container.name`, `deployment.environment`, the `k8s.*` family, `cloud.region`) and puts **everything else in structured metadata** — queryable but not indexed. **That's why `trace_id` is metadata and never a label**, which is exactly right: a label per trace would be a cardinality bomb. See `loki-config.yaml`, which lists the promoted set explicitly so the lab is self-documenting about its own index cardinality.

---

## Exercise 8 — See the two deliberate mistakes in the app

`app/main.py` contains mistakes on purpose. Find them in the UI:

### Mistake A — unbounded span names
```python
with tracer.start_as_current_span("get-product") as span:
    span.set_attribute("http.route", "/products/{product_id}")
    span.set_attribute("product.id", product_id)
```
This one is actually **correct** — the span name is bounded and the ID is an attribute. Compare with what happens if you change it to:
```python
with tracer.start_as_current_span(f"get-product-{product_id}") as span:   # ☠️
```
Rebuild, drive traffic with unique IDs, and watch dashboard **panel 7** ("distinct span_name values") climb without bound. **Span name is a primary index in most trace backends.** Unbounded names = unbounded index = a cost explosion that no sampling policy will save you from.

### Mistake B — high-cardinality metric attributes
The load generator hits `/products/nonexistent-$i` with a **unique ID every iteration**. Any metric dimensioned by `product.id` would gain a series per request. Check:
```promql
count(count by (span_name) (traces_span_metrics_calls_total))
```
★ **The rule: high-cardinality identifiers (`user_id`, `order_id`, `product_id`, `trace_id`) belong on SPANS and LOGS, and are prohibited on METRICS.** A span pays for the value once; a metric series pays for it forever. See [`../../14-scale-cost-and-cardinality.md`](../../14-scale-cost-and-cardinality.md).

---

## Exercise 9 — Break the pipeline and watch backpressure

Point the trace exporter somewhere dead:
```yaml
  otlp/tempo:
    endpoint: tempo:9999        # ← nothing listening
```
```bash
docker compose restart collector
```

**Watch, in order:**
1. `otelcol_exporter_send_failed_spans` climbs
2. ★ **Dashboard panel 9 (queue fill ratio) climbs toward 1.0** — this is the **leading** indicator, and it moves *before* the failures become total
3. Once the queue is full, `otelcol_receiver_refused_spans` climbs — **backpressure propagating backwards** through the pipeline to the receiver
4. The SDK starts retrying, then dropping — and **that loss is invisible to the Collector**

```bash
docker compose logs collector | grep -iE "refus|failed|queue" | tail -20
```

★ **Note what makes this survivable:** `sending_queue.storage: file_storage` means the queue is on a **persistent volume**. Restart the Collector mid-outage and the buffered traces are still there:
```bash
docker compose restart collector
docker compose logs collector | grep -i "queue" | tail
```
Without `file_storage`, every restart discards the queue. And ★ **both `sending_queue` and `retry_on_failure` are DISABLED by default** — this lab enables them explicitly, which is why the panels have data at all.

**Revert to `tempo:4317`.**

---

## What you should now be able to answer

1. What's the difference between the auto-instrumentation spans and the manual ones? → **Scope name, and plumbing vs business meaning. Both nest automatically.**
2. Why don't my exemplar diamonds appear? → **`--enable-feature=exemplar-storage` missing, or `exemplarTraceIdDestinations` not configured. Accepting ≠ retaining.**
3. Why does the trace→log link return nothing? → **The `service.name` → `service_name` tag mapping. Loki dots become underscores.**
4. Where does `trace_id=` in my log line come from? → **The SDK injects `otelTraceID` into the LogRecord; YOUR FORMATTER must print it.** Plus Loki 3 structured metadata as the scalable path.
5. Why is there no `loki` exporter? → **Removed. Use native OTLP to `/otlp` — no translation layer, and `trace_id` becomes structured metadata instead of a label.**
6. How do I alert on redaction? → ★ **The processor emits no metrics. Derive one from the `redaction.masked.count` attribute via a `span_metrics` dimension.**
7. Should I run both the Collector connector and Tempo's `metrics_generator`? → **No. Double ingest, disagreeing series. Pick one.**
8. Why is my p99 showing 0.5? → ★ **Milliseconds vs seconds. `useSecondAsDefaultMetricsUnit` is off by default; check the unit, not the name.**

→ Next: [`../lab-03-sampling/`](../lab-03-sampling/) · Back: [`../README.md`](../README.md)
