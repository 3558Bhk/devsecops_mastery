# 11 · The Collector

The component you'll actually operate. Everything in here is verified against **`otelcol-contrib` v0.161.0** — component lists and feature gates read directly from the binary, configs passed through `otelcol-contrib validate`.

---

## 11.1 What the Collector is

**A single, vendor-agnostic binary that receives telemetry, transforms it, and exports it somewhere else.** Written in Go, stateless by default (except for specific stateful components), and configured entirely by one YAML file.

**Why run one at all** — five reasons, in order of value:

| Reason | What it buys you |
|---|---|
| **Sampling that needs the whole trace** | `tail_sampling` can only work where all spans of a trace meet. That's the Collector ([`10-sampling.md`](10-sampling.md)) |
| **PII redaction before data leaves your infrastructure** | Once a secret or an email reaches a vendor, it's subject to their retention, backups and replication. Redacting at the edge is a materially different compliance posture |
| **Cardinality control** | One place to protect the backend from every producer, including ones you don't control |
| **Fan-out and migration** | Send the same telemetry to two backends during a migration; switch vendors with a config change, not a code change |
| **Keeping vendor endpoints out of application config** | Applications point at `otel-collector:4317` forever. Endpoint, credentials and routing change underneath them |

**When not to run one:** a handful of services going to one vendor with no compliance requirement and no sampling need. The SDK can export directly, and one less critical component to operate is a real win. Say so rather than running a Collector because it's fashionable.

---

## 11.2 The six component types

Verified counts from `otelcol-contrib v0.161.0 components`:
**108 receivers · 33 processors · 48 exporters · 13 connectors · 40 extensions · 9 providers.**

| Type | Role | Direction | Examples |
|---|---|---|---|
| **Receiver** | Gets data **in** | Push or pull | `otlp`, `prometheus`, `file_log`, `host_metrics`, `kafka`, `jaeger`, `zipkin`, `pprof`, `obi`, `k8s_cluster`, `k8s_events` |
| **Processor** | Transforms data **in flight** | In-pipeline | `batch`, `memory_limiter`, `attributes`, `transform`, `filter`, `tail_sampling`, `k8s_attributes`, `resource_detection`, `cardinality_guardian` |
| **Exporter** | Sends data **out** | Push or expose | `otlp_grpc`, `otlp_http`, `prometheus`, `prometheus_remote_write`, `load_balancing`, `debug`, `file`, `kafka`, `clickhouse`, `elasticsearch` |
| **Connector** | **Terminates one pipeline and starts another**, possibly across signals | Both | `span_metrics`, `service_graph`, `count`, `exceptions`, `forward`, `routing`, `failover`, `sum`, `signal_to_metrics` |
| **Extension** | Background capability, **not in the data path** | Neither | `health_check`, `zpages`, `pprof`, `basicauth`, `oidc`, `bearertokenauth`, `oauth2client`, `file_storage`, `opamp`, `sigv4auth`, `jaegerremotesampling` |
| **Provider** | A config source for `--config` | n/a | `file`, `env`, `yaml`, `http`, `https`, and vault-style providers |

★ **Connectors vs processors is the distinction people get wrong.** A processor sits *inside* a pipeline and cannot change the signal type. A connector is an **exporter in one pipeline and a receiver in another**, which is what allows spans to become metrics. If you want "generate RED metrics from traces", that's a connector, and it must be wired into both pipelines.

---

## 11.3 The configuration file

```yaml
# Top-level sections. Order doesn't matter; `service` is where it all gets wired.
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: 0.0.0.0:1777
  zpages:
    endpoint: 0.0.0.0:55679

receivers:
  otlp:
    protocols:
      grpc: {endpoint: 0.0.0.0:4317}
      http: {endpoint: 0.0.0.0:4318}

processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
  batch:
    send_batch_size: 8192
    timeout: 5s

exporters:
  otlp_grpc/backend:
    endpoint: tempo:4317
    tls: {insecure: true}

connectors:
  span_metrics:
    dimensions: [{name: http.route}]

service:
  extensions: [health_check, pprof, zpages]
  telemetry:
    logs: {level: info}
    metrics:
      level: detailed
      readers:
        - pull:
            exporter:
              prometheus: {host: 0.0.0.0, port: 8888}
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp_grpc/backend, span_metrics]
    metrics:
      receivers: [otlp, span_metrics]
      processors: [memory_limiter, batch]
      exporters: [otlp_grpc/backend]
```

### Four rules that explain most config errors

1. **Defining a component does nothing.** `exporters: {debug: }` with `debug` absent from every pipeline's `exporters:` list means it never runs. ★ This is a real gotcha — you'll configure a debug exporter, see nothing, and conclude the pipeline is broken.
2. **Component names support a `/name` suffix** for multiple instances: `otlp_grpc/tempo`, `otlp_grpc/vendor-b`, `filter/drop-noise`. The part before `/` selects the type.
3. **Pipelines are per-signal.** A `traces` pipeline can only contain components that support traces. Putting a metrics-only exporter in a traces pipeline is a startup error.
4. **Every pipeline needs at least one receiver and one exporter.** Processors are optional.

### Config loading and composition

```bash
otelcol-contrib --config=/etc/otel/config.yaml                    # single file
otelcol-contrib --config=file:/etc/otel/base.yaml \
                --config=file:/etc/otel/override.yaml             # merged, later wins
otelcol-contrib --config=/etc/otel/config.yaml \
                --set=processors.batch.timeout=2s                 # ★ override any property from CLI
otelcol-contrib --config='env:OTEL_CONFIG_YAML'                   # from an environment variable
```
★ **`--config` accepts only ONE location per flag entry.** Repeated flags, not comma-separated values. Getting this wrong produces a confusing parse error.

**In-file expansion** — genuinely useful for splitting large configs:
```yaml
exporters: ${file:exporters.yaml}          # whole section from another file
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: ${env:OTLP_ENDPOINT}     # single value from an env var
```
Providers available (9 in v0.161.0): `file`, `env`, `yaml`, `http`, `https`, plus others. **`--set` has the highest precedence**, which makes it the right tool for per-environment overrides without duplicating files.

### The four subcommands ★

```bash
otelcol-contrib validate      --config=c.yaml    # check config without running — USE THIS IN CI
otelcol-contrib components                       # list every component in this distribution + stability
otelcol-contrib featuregate                      # list every feature gate and its current state
otelcol-contrib print-config  --config=c.yaml    # the fully resolved config with ALL defaults filled in
```
★ **There is no `run` subcommand.** You start the Collector with `otelcol-contrib --config=...` directly. Running `otelcol-contrib run --config=...` gives `Error: unknown command "run"`. This trips up everyone who's used to `docker run` or `kubectl run`.

**`print-config` is the most underrated command.** It shows what the Collector *actually* resolved, including every default you didn't write. When behaviour doesn't match your mental model, diff your config against `print-config` output — the answer is nearly always a default you didn't know about.

**`validate` belongs in CI:**
```yaml
# GitHub Actions
- run: |
    curl -sSL -o otelcol.tar.gz \
      https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.161.0/otelcol-contrib_0.161.0_linux_amd64.tar.gz
    tar xzf otelcol.tar.gz otelcol-contrib
    ./otelcol-contrib validate --config=deploy/otel-collector-config.yaml
```
★ **This catches more real bugs than any linter**, because it's the actual binary applying the actual schema — including the connector-wiring rule and feature-gate requirements.

---

## 11.4 Pipelines: semantics that matter

- **Receivers can feed multiple pipelines.** Listing `otlp` in `traces`, `metrics` and `logs` is normal and correct.
- **Processors run in the order listed**, and each instance is **per-pipeline**. ★ Putting `attributes` in two pipelines creates two independent processor instances — configuration is shared, state is not. That matters for anything stateful (`tail_sampling`, `delta_to_cumulative`, `groupbytrace`).
- **Exporters fan out.** Listing three exporters means all three receive a copy. This is how dual-shipping works.
- **A pipeline failure is a startup failure.** The Collector refuses to start on an invalid pipeline — which is good, and the reason `validate` in CI is so valuable.
- **`service.AllowNoPipelines` is a feature gate, off by default** — you can't start a Collector with no pipelines.

### The connector wiring rule ★ (verified error messages)

A connector **must** appear as an exporter in a supported pipeline **and** as a receiver in a supported pipeline. Get it wrong and the Collector won't start:

```
Error: failed to build pipelines: connector "spanmetrics" used as exporter in [traces] pipeline
       but not used in any supported receiver pipeline

Error: failed to build pipelines: connector "servicegraph" used as receiver in [metrics] pipeline
       but not used in any supported exporter pipeline
```
Both messages verified against v0.161.0. Note they name the connector *and* the pipeline, which makes them easy to act on — if you know what they mean.

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp_grpc/tempo, span_metrics]   # ← connector as EXPORTER
    metrics:
      receivers: [otlp, span_metrics]              # ← connector as RECEIVER
      exporters: [prometheus_remote_write]
```

---

## 11.5 Processor ordering ★

**Order is a correctness decision, not a style preference.**

```yaml
processors: [memory_limiter, resource_detection, k8s_attributes, attributes, transform, filter, batch]
```

| Position | Processor | Why here |
|---|---|---|
| **1st** | **`memory_limiter`** | If you must shed load, do it **before** spending CPU on enrichment. Upstream documentation states this explicitly |
| 2nd | `resource_detection`, `k8s_attributes` | Enrichment. Filters often depend on enriched attributes |
| 3rd | `attributes`, `transform` | Reshape, rename, redact |
| 4th | `filter` | Drop what you don't want — **after** enrichment so filters can use enriched fields, **before** batch so you don't batch garbage |
| 5th | `tail_sampling` | **Tension:** needs enriched attributes, but sampling early saves work on everything downstream. If policies use `k8s.namespace.name`, it must come after `k8s_attributes` |
| **Last** | **`batch`** | Batch only what survives. Batching before filtering means you batch data you then discard |

★ **Two real conflicts to resolve deliberately:**
1. **Sample early vs sample after enrichment.** Sampling early saves CPU and memory on everything downstream; sampling late lets policies use enriched attributes. If your policies only use raw span attributes, sample early. If they filter by namespace or tenant tier, enrichment must come first.
2. **`batch` before or after a slow exporter.** ★ Upstream warns that `tail_sampling`'s `sampling_decision_timer_latency` **exceeding 1 second can delay decisions past `decision_wait` and cause drops**, and therefore recommends *"consuming this component's output with components that are fast or trigger asynchronous processing."* So: don't put a slow, synchronous exporter immediately after `tail_sampling` without a queue.

---

## 11.6 Reliability primitives: queues, retries, timeouts

Every exporter built on `exporterhelper` (nearly all of them) supports the same three blocks:

```yaml
exporters:
  otlp_grpc/backend:
    endpoint: tempo:4317
    timeout: 30s                       # per-request deadline
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s           # ★ 0 = retry forever
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 5000
      # storage: file_storage/otc      # ← persistent queue; requires the extension
```

### The defaults are the surprise ★

**In the Collector, `sending_queue` and `retry_on_failure` are OFF by default for most exporters** — unlike SDK exporters, which retry. So a bare `otlp_grpc: {endpoint: ...}` **drops data on the first transient failure.**

This is the single most common production Collector mistake. Enable both explicitly, and size them:

| Setting | Guidance |
|---|---|
| `queue_size` | ≥ (throughput × expected outage duration). 5000 batches at 8192 items is a lot; 200 is nothing |
| `num_consumers` | Parallelism of the export workers. Raise for high throughput, watch backend rate limits |
| `timeout` | Must be shorter than `queue_size / num_consumers` drain time, or the queue grows faster than it drains |
| `max_elapsed_time` | ★ **Set it.** `0` retries forever, which means a permanently-down backend fills the queue and then blocks the pipeline. 300 s with a `file_storage` queue is usually right |

### Persistent queues — surviving a Collector restart
```yaml
extensions:
  file_storage/otc:
    directory: /var/lib/otelcol/storage     # ★ needs a real volume, not ephemeral container storage
    timeout: 10s

exporters:
  otlp_grpc/backend:
    sending_queue:
      enabled: true
      queue_size: 10000
      storage: file_storage/otc             # ← the queue survives restarts
service:
  extensions: [file_storage/otc]
```
**Without `storage`, the queue is in memory and a Collector restart loses everything buffered.** During a rolling deploy under load, that's a real data gap. ★ In Kubernetes this means a `PersistentVolumeClaim` — and the I/O characteristics of that volume now affect your telemetry pipeline.

**`load_balancing` caveat:** ★ persistent queues are **NOT supported for its sub-exporters**, because all sub-exporters share one `sending_queue` configuration including `storage`. Use the exporter-level (option 1) queue for elasticity, and the `otlp` sub-exporter queue (option 2) for per-backend network blips.

### `pkg.exporterhelper.queueBatchEnabled`
Feature gate, **off by default** in v0.161.0 — the newer unified queue+batch implementation. Worth testing before it becomes default.

---

## 11.7 `memory_limiter` — the component that keeps you alive

```yaml
processors:
  memory_limiter:
    check_interval: 1s            # ★ how often to check; 0 disables the processor entirely
    limit_percentage: 80          # hard limit as % of total memory
    spike_limit_percentage: 25    # soft limit = limit - spike
    # OR absolute values:
    # limit_mib: 2048
    # spike_limit_mib: 512
```

**Behaviour:** above the **soft limit** (`limit − spike`), the processor starts **refusing data** — receivers return errors, and well-behaved senders back off. Above the **hard limit**, it refuses everything until memory recovers.

★ **Three things that make or break this:**
1. **It must be the FIRST processor in EVERY pipeline.** A pipeline without it can OOM the process, taking all other pipelines down with it.
2. **`limit_percentage` is computed against memory the Collector can see.** In a container with a limit, it should read the cgroup limit — verify with `print-config` and test, because getting this wrong means the limiter never fires and the container OOMKills instead.
3. **Refusing data is a *good* outcome.** It produces backpressure the SDK can respond to (retry, then drop) instead of an OOMKill that loses everything buffered and restarts the Collector cold. **Alert on refusal, but never remove the limiter to stop the alerts.**

**Memory consumers to know about:**
| Component | Memory driver |
|---|---|
| `tail_sampling` | `num_traces` × trace size + decision caches |
| `groupbytrace` | Buffered incomplete traces |
| `delta_to_cumulative` | Per-stream accumulated state (`max_streams`) |
| `batch` | Queued batches × pipelines |
| `sending_queue` | `queue_size` × batch size × exporters |
| `prometheus` receiver | Scrape target count × series per target |
| `k8s_attributes` | Cached pod metadata for the whole cluster |
| `span_metrics` | `dimensions_cache_size` × dimension cardinality |

---

## 11.8 Internal telemetry — you cannot debug what you can't see ★

The Collector instruments itself, and **this is the primary debugging tool.**

```yaml
service:
  telemetry:
    logs:
      level: info                       # debug | info | warn | error
      # output_paths: [stdout, /var/log/otelcol.log]
    metrics:
      level: detailed                   # none | basic | normal | detailed | complete
      readers:
        - pull:
            exporter:
              prometheus:
                host: 0.0.0.0
                port: 8888              # ★ default is localhost:8888 — bind 0.0.0.0 in containers
    # traces:                           # the Collector can trace itself
    #   processors: [...]
```

★ **Default bind is `localhost:8888`.** In a container that means nothing outside can scrape it. Verified failure mode: two Collectors on one host both fail with
`failed to create meter provider: binding address localhost:8888 for Prometheus exporter: listen tcp 127.0.0.1:8888: bind: address already in use`.

**Metric levels:** `basic` → `normal` → `detailed` → `complete`. Each adds cardinality and cost. **`detailed` is the right production default**; `complete` when debugging. Note `telemetry.newPipelineTelemetry` (off by default) enables **per-pipeline** metrics — worth turning on when you need to know which pipeline is misbehaving.

★ `service.telemetry.logs` — the deprecated top-level `LoggingOptions` config was **removed in v0.161.0**. Configs carrying it now fail.

### The metrics that matter

**Throughput and loss — the ones to alert on:**
| Metric | Meaning |
|---|---|
| **`otelcol_receiver_accepted_spans`** / `_metric_points` / `_log_records` | Data successfully received |
| **`otelcol_receiver_refused_spans`** / `_metric_points` / `_log_records` | ★ **Data rejected on ingest** — memory_limiter firing, or a decode failure. **Alert on > 0** |
| **`otelcol_exporter_sent_spans`** / `_metric_points` / `_log_records` | Data successfully exported |
| **`otelcol_exporter_send_failed_spans`** / `_metric_points` / `_log_records` | ★ **Export failures after retries. Alert on > 0** |
| **`otelcol_exporter_queue_size`** | Current queue depth. **The leading indicator** — it rises before you lose data |
| **`otelcol_exporter_queue_capacity`** | Configured capacity. Alert on `queue_size / queue_capacity > 0.8` |
| **`otelcol_processor_dropped_spans`** | Dropped by a processor |
| **`otelcol_processor_refused_spans`** | Refused (memory_limiter) |
| **`otelcol_processor_batch_*`** | Batch processor behaviour, including timeout-triggered flushes |

★ **The two ratios that tell you whether your pipeline is healthy:**
```promql
# Acceptance ratio — should be 1.0
sum(rate(otelcol_receiver_accepted_spans[5m]))
  / (sum(rate(otelcol_receiver_accepted_spans[5m])) + sum(rate(otelcol_receiver_refused_spans[5m])))

# Export success ratio — should be 1.0
sum(rate(otelcol_exporter_sent_spans[5m]))
  / (sum(rate(otelcol_exporter_sent_spans[5m])) + sum(rate(otelcol_exporter_send_failed_spans[5m])))
```
**If accepted ≫ sent, you're losing data between the two, and the queue metrics will tell you where.**

**Plus the tail-sampling metrics** from [`10-sampling.md`](10-sampling.md) — `sampling_trace_dropped_too_early`, `sampling_trace_removal_age`, `sampling_decision_timer_latency`.

### `zpages` — live pipeline introspection
```yaml
extensions:
  zpages: {endpoint: 0.0.0.0:55679}
service:
  extensions: [zpages]
```
`http://localhost:55679/debug/tracez` shows in-flight spans by pipeline stage; `/debug/servicez` lists services and uptime; `/debug/pipelinez` shows pipeline structure; `/debug/extensionz` shows extensions. ★ **`tracez` is the fastest way to confirm data is flowing and to see exactly which stage it's stuck at** — no backend required.

### `pprof`
```yaml
extensions:
  pprof: {endpoint: 0.0.0.0:1777}
```
`go tool pprof http://collector:1777/debug/pprof/heap` (or `profile`, `goroutine`). **When a Collector's memory grows unexpectedly, a heap profile answers it in minutes** and is otherwise unanswerable.

### `health_check`
```yaml
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
```
Use for liveness/readiness probes. ★ Note `extension.healthcheck.useComponentStatus` (**off by default**) — enabling it makes health reflect **component** status, not just process liveness, which is what you usually want for a readiness probe.

---

## 11.9 Resilience patterns with connectors

Three connectors exist purely for reliability, and they're underused:

```yaml
connectors:
  failover:                          # primary/backup ordering
  routing:                           # conditional routing by attribute
  round_robin:                       # distribute across pipelines
```

```yaml
# FAILOVER — export to the primary; fall back to a secondary on failure
connectors:
  failover:
    # (see the connector README at your tag for the exact retry/backoff shape)
exporters:
  otlp_grpc/primary: {endpoint: vendor-a:4317}
  otlp_grpc/backup:  {endpoint: vendor-b:4317}
service:
  pipelines:
    traces/out1: {receivers: [otlp], exporters: [failover]}
    traces/out2: {receivers: [failover], exporters: [otlp_grpc/primary]}
    traces/out3: {receivers: [failover], exporters: [otlp_grpc/backup]}
```

```yaml
# ROUTING — send different tenants/teams to different backends
connectors:
  routing:
    default_pipelines: [traces/default]
    error_mode: ignore
    from_attribute: ["X-Tenant"]
    attribute_source: context
    table:
      - value: acme
        exporters: [otlp_grpc/acme]
      - value: globex
        exporters: [otlp_grpc/globex]
```
★ `connector.routing.defaultErrorModeIgnore` is **true / Beta** in v0.161.0 (verified via the `featuregate` subcommand — the `--help` default string says otherwise and is **wrong**). **So routing errors ARE ignored by default: an item that matches no route is silently dropped.** ★ **Set `error_mode: propagate` while building the routing table**, and always define a catch-all route in production so an unmatched item is handled deliberately rather than vanishing.

**Fan-out to multiple backends** doesn't need a connector at all — just list the exporters:
```yaml
    traces:
      exporters: [otlp_grpc/tempo, otlp_http/vendor, file/archive]
```

---

## 11.10 Distribution choice and custom builds

| Distribution | Size | Use |
|---|---|---|
| `otelcol` (core) | Smallest | OTLP→OTLP only; minimal attack surface |
| **`otelcol-contrib`** | Largest (~108 receivers) | Default for almost everyone |
| `otelcol-k8s` | Medium | Kubernetes-focused subset |
| `otelcol-otlp` | Small | Edge/gateway OTLP relay |
| Vendor distros | contrib+ | ADOT, Azure Monitor, GCP — supported defaults for one cloud |
| **OCB custom** | **Whatever you list** | Auditable, minimal, faster startup |

**Building a custom distribution:**
```yaml
# builder-config.yaml
dist:
  name: otelcol-custom
  output_path: ./dist
  version: 1.0.0
receivers:
  - gomod: go.opentelemetry.io/collector/receiver/otlpreceiver v0.161.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/receiver/prometheusreceiver v0.161.0
processors:
  - gomod: go.opentelemetry.io/collector/processor/batchprocessor v0.161.0
  - gomod: go.opentelemetry.io/collector/processor/memorylimiterprocessor v0.161.0
exporters:
  - gomod: go.opentelemetry.io/collector/exporter/otlpexporter v0.161.0
  - gomod: go.opentelemetry.io/collector/exporter/debugexporter v0.161.0
extensions:
  - gomod: go.opentelemetry.io/collector/extension/zpagesextension v0.161.0
```
```bash
ocb --config builder-config.yaml
./dist/otelcol-custom components       # verify exactly what's in your binary
```
★ **Custom builds are a security control, not just an optimisation.** `otelcol-contrib` has 108 receivers — most of which you'll never use, each of which is attack surface and CVE exposure. A 6-component custom build has a fraction of the vulnerability surface and starts faster. See [`15-security-and-governance.md`](15-security-and-governance.md).

**Note:** the `logging` exporter was **removed in v0.111.0** — an OCB manifest referencing it fails to build. Use `debugexporter`.

---

## 11.11 Upgrading the Collector

Biweekly minor releases with a documented breaking-change section. A safe process:

1. **Read the release notes' "🛑 Breaking changes" section.** v0.161.0's included: removal of the deprecated `LoggingOptions` config option, removal of `extensioncapabilities.ConfigWatcher` / `Extensions.NotifyConfig` / `service.Settings.CollectorConf` (deprecated since v0.155.0 — use `ConfigSnapshotWatcher`, `NotifyConfigSnapshot`, `Settings.ConfigSnapshot`), and removal of `mdatagen`'s `DefaultMetricsBuilderConfig`.
2. **Check `featuregate` before and after.** Gate defaults change, and several semconv `EmitV1*` gates are mid-migration ([`04-semantic-conventions.md`](04-semantic-conventions.md)).
3. **Run `validate` on the new binary against your existing config** — in CI, before deploying.
4. **Diff `print-config` between versions.** This surfaces every default that changed, including ones not mentioned in the notes. ★ Highest-value, least-used upgrade check.
5. **Canary one instance**, watch `receiver_refused_*`, `exporter_send_failed_*`, queue depth and memory for a day.
6. **Pin the image tag by digest** in production, not `:latest` and not a floating minor.

**Versioning reality:** core is `v1.67.0` (stable API surface) while the distribution is `v0.161.0`. ★ **The `v0.x` on contrib does not mean unstable in the colloquial sense** — it reflects that individual components carry their own stability levels (`Alpha`/`Beta`/`Stable`), which `components` reports per component per signal. Read the component's stability, not the distribution's version number.

---

## Red flags

| Doing this | Costs you |
|---|---|
| `sending_queue` / `retry_on_failure` left at defaults | ★ **Off by default.** A single transient failure drops data |
| `max_elapsed_time: 0` | Retries forever → queue fills → pipeline blocks |
| In-memory queue only | Every Collector restart loses buffered data. Use `file_storage` + a real volume |
| `memory_limiter` missing, or not first | OOMKill takes down all pipelines at once |
| `memory_limiter` removed to stop refusal alerts | You traded backpressure for crashes |
| Internal telemetry on `localhost:8888` in a container | Nothing can scrape it; you're flying blind |
| Telemetry `level: none` | No way to diagnose loss |
| No `receiver_refused_*` / `exporter_send_failed_*` alerts | Silent data loss, discovered during an incident |
| `debug` exporter left on at `verbosity: detailed` in production | ★ Enormous log volume and real CPU cost. Use `basic`, or remove it |
| Configuring a component but not listing it in a pipeline | It never runs, and you debug the wrong thing |
| `--config=a.yaml,b.yaml` | One location per flag entry. Use repeated `--config` flags |
| Running `otelcol-contrib run` | No such subcommand |
| Not running `validate` in CI | Config errors become production outages |
| Not diffing `print-config` on upgrade | Changed defaults silently alter behaviour |
| Wiring a connector into one pipeline only | Collector refuses to start |
| A slow exporter directly after `tail_sampling` | Decision latency >1 s → decisions pushed past `decision_wait` → dropped traces |
| Running full `otelcol-contrib` when you use 5 components | Attack surface, CVE exposure, slow startup |
| `:latest` image tags | Unreproducible incidents and surprise breaking changes |
| No `routing.error_mode` set | Unroutable items can stall a pipeline |

---

## Rapid recall

1. **Six component types: receivers, processors, exporters, connectors, extensions, providers** — in contrib v0.161.0: **108/33/48/13/40/9**. ★ **Connectors differ from processors** by terminating one pipeline and starting another (possibly across signals), which is what allows spans → metrics.
2. **Four rules of config:** defining a component does nothing until it's in a pipeline; `type/name` suffixes create instances; pipelines are per-signal; every pipeline needs ≥1 receiver and ≥1 exporter.
3. **Four subcommands: `validate`, `components`, `featuregate`, `print-config`. There is no `run`** — start with `--config=` directly. ★ **`print-config` shows every resolved default** and is the fastest way to explain surprising behaviour; **`validate` belongs in CI**.
4. **`--config` takes ONE location per flag** (repeat the flag). In-file `${file:...}` and `${env:...}` expansion works; **`--set` overrides anything from the CLI with highest precedence.**
5. **Connector wiring is enforced at startup** — must be an exporter in one supported pipeline and a receiver in another, or you get `connector "X" used as Y in [pipeline] but not used in any supported Z pipeline`.
6. **Processor order: `memory_limiter` FIRST → enrich (`resource_detection`, `k8s_attributes`) → reshape (`attributes`, `transform`) → `filter` → `tail_sampling` → `batch` LAST.** Two deliberate conflicts: sample-early vs sample-after-enrichment, and keeping what follows `tail_sampling` fast.
7. ★ **`sending_queue` and `retry_on_failure` are OFF by default** in most Collector exporters — unlike SDK exporters. A bare exporter config **drops data on the first transient failure**. Enable both, size the queue from throughput × outage duration, and **set `max_elapsed_time`** (0 = retry forever = blocked pipeline).
8. **Persistent queues need `file_storage` + a real volume** or a restart loses everything buffered. ★ **Not supported for `load_balancing` sub-exporters** (shared queue config).
9. **`memory_limiter` must be first in every pipeline.** Refusing data is *good* — it's backpressure instead of an OOMKill that loses all buffers. Never remove it to silence alerts. Memory hogs: `tail_sampling`, `groupbytrace`, `delta_to_cumulative`, `sending_queue`, `prometheus` receiver, `k8s_attributes`, `span_metrics`.
10. ★ **Internal telemetry binds `localhost:8888` by default** — set `host: 0.0.0.0` in containers, or nothing can scrape it (verified: two Collectors on one host fail with `address already in use`). Use `level: detailed`. Enable `telemetry.newPipelineTelemetry` for per-pipeline metrics.
11. **Alert on: `otelcol_receiver_refused_*`, `otelcol_exporter_send_failed_*`, and `queue_size / queue_capacity > 0.8`.** The two health ratios are accepted/(accepted+refused) and sent/(sent+failed) — both must be 1.0. **If accepted ≫ sent you're losing data in between.**
12. **`zpages` `/debug/tracez`** shows in-flight data by pipeline stage with no backend needed — the fastest "is it flowing, and where is it stuck?" check. **`pprof` :1777** answers memory questions. **`health_check` :13133** for probes (`useComponentStatus` gate makes it reflect component health).
13. **Reliability connectors:** `failover` (primary/backup), `routing` (per-tenant/attribute — ★ **its `defaultErrorModeIgnore` gate is TRUE/Beta, so unmatched items are silently dropped**; set `error_mode: propagate` while building and always define a catch-all), `round_robin`. Plain fan-out needs no connector: just list the exporters.
14. **Custom OCB builds are a security control** — contrib's 108 receivers are mostly attack surface you'll never use. ★ An OCB manifest referencing the removed `logging` exporter fails to build.
15. **Upgrades: read 🛑 Breaking changes, diff `featuregate` and `print-config`, `validate` in CI, canary one instance, pin by digest.** v0.161.0 removed `LoggingOptions` and `ConfigWatcher`. ★ **`v0.x` on contrib ≠ unstable** — read each component's own stability level via `components`.

→ Next: [`12-collector-in-kubernetes.md`](12-collector-in-kubernetes.md)
