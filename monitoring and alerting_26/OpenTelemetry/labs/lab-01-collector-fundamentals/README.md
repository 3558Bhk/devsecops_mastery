# Lab 01 — Collector Fundamentals

**Goal:** prove you can see *inside* the Collector before you trust it with application data. OTLP in → `debug` out, with the Collector's own internal telemetry scraped by Prometheus and visualised in Grafana.

**Time:** 30–45 minutes. **Prerequisites:** Docker + Docker Compose. Nothing else.

**Companion reading:** [`../../11-collector.md`](../../11-collector.md), [`../../16-troubleshooting.md`](../../16-troubleshooting.md), [`../../02-architecture-and-data-model.md`](../../02-architecture-and-data-model.md)

---

## What's in this lab

| File | Role |
|---|---|
| `otel-collector-config.yaml` | ★ The main artefact — **validated against `otelcol-contrib` v0.161.0** |
| `docker-compose.yml` | Collector + Prometheus + Grafana + a synthetic OTLP traffic generator |
| `prometheus.yml` | Scrapes both the Collector's `prometheus` exporter **and** its internal telemetry |
| `grafana/provisioning/` | Datasource + a "Collector Health" dashboard, auto-provisioned |

---

## Run it

```bash
cd labs/lab-01-collector-fundamentals
docker compose up -d
docker compose ps
```

| URL | What |
|---|---|
| http://localhost:3000 | **Grafana** (admin/admin) → *OpenTelemetry Labs* → **Lab 01 — Collector Health** |
| http://localhost:9090 | Prometheus |
| http://localhost:13133 | Collector `health_check` |
| http://localhost:8888/metrics | ★ Collector's **own** internal telemetry |
| http://localhost:8889/metrics | The `prometheus` **exporter** (your app + connector metrics) |
| http://localhost:55679/debug/tracez | `zpages` — live spans by latency bucket |

```bash
docker compose logs -f collector     # the debug exporter prints what it receives
docker compose down                  # stop
docker compose down -v               # stop and wipe Prometheus/Grafana data
```

---

## Exercise 1 — Watch data flow end to end

```bash
docker compose logs -f collector | head -60
```
You should see `TracesExporter`, `MetricsExporter` and `LogsExporter` entries within ~5 s. The `trafficgen` service posts OTLP/HTTP to `:4318` every 3 s, and **every 7th iteration is an ERROR** so there's always something interesting.

**Questions to answer from the Grafana dashboard:**
1. What is the `otelcol_receiver_accepted_spans` rate? Does it match the generator's rate (≈1 span / 3 s)?
2. What is the accept/export ratio? **It should be ≈1.0.**
3. Is `otelcol_exporter_queue_size` empty? ★ **Yes — and that's expected**, because `sending_queue` is **disabled by default** in v0.161.0. Enable it in Exercise 5 and watch the panel come alive.

---

## Exercise 2 — ★ Discover that internal telemetry defaults to `localhost`

This is the single most common "Prometheus shows nothing" problem with a containerised Collector.

```bash
# Inside the container, localhost works:
docker compose exec collector sh -c 'echo no shell here' 2>/dev/null || echo "(minimal image, no shell — expected)"

# From the host it works ONLY because we bound 0.0.0.0 in service.telemetry:
curl -s localhost:8888/metrics | grep -c otelcol_
```

Now **break it deliberately** and observe the failure mode. Edit `otel-collector-config.yaml`:

```yaml
service:
  telemetry:
    metrics:
      readers:
        - pull:
            exporter:
              prometheus:
                host: localhost      # ← was 0.0.0.0
                port: 8888
```

```bash
docker compose restart collector
curl -s localhost:9090/api/v1/query?query=up | python3 -m json.tool
```

**Observe:** the `otel-collector` target goes to `up == 0` in Prometheus, and the dashboard's panel 5 ("Is the scrape working at all?") shows it. **The Collector is perfectly healthy and processing data — it's just invisible.**

★ **This is why "no metrics" almost never means "no telemetry."** Revert to `0.0.0.0`.

---

## Exercise 3 — Prove a connector must be wired in *both* roles

Connectors are the part of the model people get wrong most often.

```bash
# Baseline: validates clean
docker run --rm -v "$PWD:/cfg" otel/opentelemetry-collector-contrib:0.161.0 \
  validate --config=/cfg/otel-collector-config.yaml && echo "BASELINE OK"
```

Now break the `span_metrics` connector by removing it from the **metrics** pipeline's receivers:

```yaml
    metrics:
      receivers: [otlp, prometheus/self, count]     # ← span_metrics removed
```

```bash
docker run --rm -v "$PWD:/cfg" otel/opentelemetry-collector-contrib:0.161.0 \
  validate --config=/cfg/otel-collector-config.yaml
```

**Expected — verbatim error from v0.161.0:**
```
Error: failed to build pipelines: connector "span_metrics" used as exporter in
[traces] pipeline but not used in any supported receiver pipeline
```

Try the mirror image (remove it from the traces pipeline's exporters):
```
Error: failed to build pipelines: connector "span_metrics" used as receiver in
[metrics] pipeline but not used in any supported exporter pipeline
```

And if you move it out of `connectors:` into `exporters:` entirely, you get the **confusing** one:
```
'exporters' unknown type: "span_metrics" for id: "span_metrics" (valid values: [...])
```
★ The name is valid — it's just declared in the wrong **section**. Read the error prefix, not the message body.

**Revert.**

---

## Exercise 4 — ★ Discover a validation rule by breaking it

`span_metrics` has default dimensions. Add `service.name` to the list:

```yaml
  span_metrics:
    dimensions:
      - name: service.name        # ← add this
      - name: http.route
```

```bash
docker run --rm -v "$PWD:/cfg" otel/opentelemetry-collector-contrib:0.161.0 \
  validate --config=/cfg/otel-collector-config.yaml
```

**Expected:**
```
Error: connectors::span_metrics: failed validating dimensions: duplicate dimension name "service.name"
```

★ **`service.name` and `service.instance.id` are already default dimensions.** This is exactly the kind of thing `validate` is for — and exactly the kind of thing you'd otherwise discover as a confusing startup failure in a Deployment. **Revert.**

---

## Exercise 5 — Enable the reliability defaults that are OFF

`sending_queue` and `retry_on_failure` are **both disabled by default**. Turn them on for the `prometheus` exporter:

```yaml
exporters:
  prometheus:
    endpoint: 0.0.0.0:8889
    # ...existing settings...
```

★ **Note:** the `prometheus` *exporter* is a **pull** endpoint — it serves `/metrics`, so queueing doesn't apply. Queueing matters for **push** exporters. Add one to see it:

```yaml
exporters:
  otlphttp/blackhole:
    endpoint: http://localhost:9999      # nothing listening — forces failures
    sending_queue:
      enabled: true
      queue_size: 1000
      num_consumers: 4
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 0                # 0 = retry forever; ★ set a real value in prod
```
```yaml
    traces:
      exporters: [debug, span_metrics, count, otlphttp/blackhole]
```

```bash
docker run --rm -v "$PWD:/cfg" otel/opentelemetry-collector-contrib:0.161.0 \
  validate --config=/cfg/otel-collector-config.yaml
docker compose up -d --force-recreate collector
```

**Watch in Grafana:**
- `otelcol_exporter_send_failed_spans` for `otlphttp/blackhole` climbs
- ★ **`otelcol_exporter_queue_size` / `queue_capacity` fills toward 1.0** — this is the **leading** indicator, and it rises *before* the failures become total
- `otelcol_receiver_refused_spans` eventually rises once the queue is full — **backpressure propagating backwards through the pipeline**, exactly as designed

**Then fix it** by pointing the exporter somewhere real, or remove it. ★ **This exercise is the whole backpressure story in [`../../14-scale-cost-and-cardinality.md`](../../14-scale-cost-and-cardinality.md), demonstrated in two minutes.**

---

## Exercise 6 — Use the CLI as a debugging tool

These three subcommands are the fastest debugging tools you have, and almost nobody uses them.

```bash
BIN=otel/opentelemetry-collector-contrib:0.161.0
docker run --rm -v "$PWD:/cfg" $BIN print-config --config=/cfg/otel-collector-config.yaml | head -40
docker run --rm -v "$PWD:/cfg" $BIN components | head -30
docker run --rm $BIN featuregate | grep -E 'defaultErrorModeIgnore|DisableAddMetricSuffixes|profilesSupport'
```

**What to notice in `featuregate`:**
```
processor.filter.defaultErrorModeIgnore         true   Stable
processor.transform.defaultErrorModeIgnore      true   Stable
exporter.prometheusexporter.DisableAddMetricSuffixes  true  Beta
service.profilesSupport                        false  Alpha
```

★★ **Compare with `--help`:**
```bash
docker run --rm $BIN --help | grep -o -- '-processor.filter.defaultErrorModeIgnore'
```
**`--help` shows it prefixed with `-` (disabled). `featuregate` says `true` (enabled).** Verified against source: `createDefaultConfig()` sets `ErrorMode: ottl.IgnoreError`, and the config doc reads *"The default value is `ignore`"*.

★ **Never read gate state from `--help`. Always use the `featuregate` subcommand.** Believing `--help` inverts your understanding of whether malformed OTTL is silently swallowed — one of the most consequential defaults in the whole system.

---

## Exercise 7 — See what `validate` does NOT catch ★★

This is the most important exercise in the lab.

Add a `redaction` processor but **forget to wire it into any pipeline**:

```yaml
processors:
  redaction:
    allow_all_keys: true
    blocked_values:
      - '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'
```

```bash
docker run --rm -v "$PWD:/cfg" otel/opentelemetry-collector-contrib:0.161.0 \
  validate --config=/cfg/otel-collector-config.yaml && echo "VALIDATES CLEAN"
```

**It validates clean.** ★ **A component that is defined but never referenced by a pipeline produces NO error whatsoever.** In production this looks like: your `redaction` processor sits in the config, code review approves it, the compliance ticket is closed — and **nothing is being redacted.**

Same for `memory_limiter` ordering — move it after `batch`:
```yaml
      processors: [batch, memory_limiter, resource/lab]
```
`validate` passes. The Collector logs a **warning at runtime**, not an error.

**How to catch both:**
```bash
# 1. will it start?
docker run --rm -v "$PWD:/cfg" otel/opentelemetry-collector-contrib:0.161.0 \
  validate --config=/cfg/otel-collector-config.yaml

# 2. is it what I MEANT? — resolve, then inspect the pipelines
docker run --rm -v "$PWD:/cfg" otel/opentelemetry-collector-contrib:0.161.0 \
  print-config --config=/cfg/otel-collector-config.yaml \
  | python3 -c "import sys,yaml; c=yaml.safe_load(sys.stdin);
import json; print(json.dumps(c['service']['pipelines'], indent=2))"
```
★ **Every processor you expect must appear in that output.** Put this in CI.

---

## What you should now be able to answer

1. Why does `curl localhost:8888/metrics` work but Prometheus sees nothing? → **`service.telemetry` binds `localhost` by default.**
2. What are the four error prefixes and what does each mean? → `cannot unmarshal` (schema), `cannot resolve` (`${env:}`/providers), `service::pipelines::X: references...` (wiring), `failed to build pipelines:` (valid config, incompatible combination).
3. Why did `span_metrics` fail with `unknown type`? → **declared under `exporters:` instead of `connectors:`**
4. What does `validate` passing actually guarantee? → **that the Collector will START. Nothing more.**
5. Which reliability settings are off by default? → **`sending_queue` and `retry_on_failure`.**
6. Why is queue fill a better alert than send failures? → **it's a leading indicator; failures are lagging confirmation you already lost data.**

→ Next: [`../lab-02-instrumented-app/`](../lab-02-instrumented-app/) · Back: [`../README.md`](../README.md)
