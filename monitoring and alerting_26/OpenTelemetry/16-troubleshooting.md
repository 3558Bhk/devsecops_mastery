# 16 · Troubleshooting

A symptom-driven field guide. **Every error message in §16.3 was produced by running `otelcol-contrib v0.161.0 validate` in this workspace** — they're verbatim, not paraphrased. §16.4 lists what `validate` *doesn't* catch, which is where most real debugging time actually goes.

---

## 16.1 The debugging order

Work the pipeline **from the consumer backwards**. Starting at the application is the most common way to waste an hour.

```
1. Is it in the BACKEND?          → query the backend directly. Maybe it is, and your dashboard is wrong.
2. Did the COLLECTOR receive it?  → otelcol_receiver_accepted_* on :8888
3. Did the COLLECTOR export it?   → otelcol_exporter_sent_* vs otelcol_exporter_send_failed_*
4. Did it leave the NETWORK?      → tcpdump / debug exporter / a second Collector
5. Did the SDK SEND it?           → SDK logs + otelcol_sdk_* metrics
6. Did the SDK CREATE it?         → your code, your instrumentation config
```

**Why backwards:** steps 1–3 are checkable in under a minute with metrics you should already have, and they eliminate ~80% of hypotheses. Step 6 is the most expensive to test and the least likely to be the cause once you've confirmed the pipeline works for *other* data.

**The single fastest triage question:** *"Is data missing, or is data wrong?"*
- **Missing** → work the backpressure/drop chain (§16.6).
- **Wrong** (bad values, wrong names, missing attributes) → work naming, temporality, semconv and enrichment (§16.5, and [`04-semantic-conventions.md`](04-semantic-conventions.md)).

★ **These have almost disjoint causes.** Conflating them is why "our traces look broken" tickets take a day.

---

## 16.2 The five diagnostic tools

### 1. `debug` exporter — the universal probe
```yaml
exporters:
  debug:
    verbosity: detailed      # basic | normal | detailed
    sampling_initial: 5      # log the first N
    sampling_thereafter: 200 # then 1 in every N
```
Put it on the pipeline **you're investigating** and read the Collector's stdout. ★ **`detailed` prints full attribute and body content — never leave it on in production** ([`15-security-and-governance.md`](15-security-and-governance.md)).

**Use `sampling_initial`/`sampling_thereafter`** so a busy pipeline doesn't drown you or melt the disk.

### 2. `otelcol-contrib print-config` ★ underrated
```bash
otelcol-contrib print-config --config=config.yaml
```
Prints the **fully resolved configuration**: all `--config` fragments merged, all `${env:VAR}` expanded, all defaults filled in. **This answers three questions that otherwise take an hour:**
- Did my second `--config` fragment actually override the first?
- What default did the component apply that I never wrote?
- Did the env var resolve, or is it empty?

### 3. `otelcol-contrib components`
```bash
otelcol-contrib components | less
```
The authoritative list of what's compiled into **your** binary, with stability levels. When you get `unknown type: "xyz"`, ★ **this tells you whether the component doesn't exist, or exists but isn't in your distribution** — a distinction that matters enormously if you're running a custom OCB build or `otelcol-k8s`.

Counts in `otelcol-contrib v0.161.0`: **108 receivers, 33 processors, 48 exporters, 13 connectors, 40 extensions, 9 providers.**

### 4. `otelcol-contrib featuregate` ★★ the one people skip
```bash
otelcol-contrib featuregate | grep -i redaction
```
Dumps every gate with its **actual current value** and stability stage.

★★ **Verified in this workspace: `otelcol-contrib --help`'s `--feature-gates` default string DISAGREES with `featuregate` for several gates.** Examples where `--help` shows `-` (off) but `featuregate` reports `true`:

| Gate | `--help` | `featuregate` | Confirmed against source |
|---|---|---|---|
| `processor.filter.defaultErrorModeIgnore` | `-` | **true** (Stable) | ★ `createDefaultConfig()` sets `ErrorMode: ottl.IgnoreError`; config doc: *"The default value is `ignore`"* |
| `processor.transform.defaultErrorModeIgnore` | `-` | **true** (Stable) | same pattern |
| `processor.k8sattributes.DontEmitV0K8sConventions` | `-` | **true** (Beta) | ★ code reads the gate; validation forbids it without `EmitV1` |
| `connector.routing.defaultErrorModeIgnore` | `-` | **true** (Beta) | |
| `ottl.set.allowNil` | `-` | **true** (Beta) | |
| `service.partialReloadReceivers` | `-` | **true** (Beta) | |
| `connector.spanmetrics.excludeResourceMetrics` | no prefix | **false** | |
| `ottl.functions.enableLambda` | no prefix | **false** (Alpha) | |

★ **Rule: never read gate state from `--help`. Always use the `featuregate` subcommand.** Believing `--help` inverts your understanding of default error handling and default semconv emission — two of the most consequential defaults there are.

### 5. `zpages` and `pprof` — for the running process
```yaml
extensions:
  zpages: {endpoint: localhost:55679}
service:
  extensions: [zpages]
```
`/debug/tracez` shows in-flight spans by latency bucket; `/debug/servicez` shows pipeline status. **For CPU and memory, `pprof`** (`/debug/pprof/profile`, `/heap`, `/goroutine`). ★ **Bind to localhost and port-forward; never expose these** — they reveal live span data and heap contents.

### Bonus: synthetic traffic
The OTel project ships **`telemetrygen`** for exactly this — generate traces/metrics/logs/profiles at a set rate with controllable attributes. **The fastest way to separate "my app isn't sending" from "my pipeline is broken"** is to point `telemetrygen` at the Collector and see whether the synthetic data arrives. If it does, the pipeline is fine and the problem is upstream.

---

## 16.3 Verified Collector configuration errors

All produced by `otelcol-contrib v0.161.0 validate`. **Read the error, don't guess** — these messages are unusually good.

### Component and wiring errors

| Mistake | Exact error |
|---|---|
| **Typo'd processor type** | `'processors' unknown type: "batchl" for id: "batchl" (valid values: [cumulative_to_delta delta_to_cumulative ... batch memory_limiter ...])` ★ **it lists every valid value — read the list** |
| **Pipeline references an undefined component** | `service::pipelines::traces: references processor "batch" which is not configured` |
| **No pipelines** | `service::pipelines: service must have at least one pipeline` |
| **Wrong signal type for a component** | `failed to build pipelines: failed to create "prometheus" exporter for data type "traces": telemetry type is not supported` |
| **Connector used only as exporter** | `failed to build pipelines: connector "span_metrics" used as exporter in [traces] pipeline but not used in any supported receiver pipeline` |
| **Connector used only as receiver** | `failed to build pipelines: connector "span_metrics" used as receiver in [metrics] pipeline but not used in any supported exporter pipeline` |
| **Connector not declared under `connectors:`** | ★ Appears as `'exporters' unknown type: "span_metrics"` (or `'receivers' unknown type:`) — **confusing, because the name IS valid, just in the wrong section** |
| **Removed `logging` exporter** | `'exporters' the logging exporter has been deprecated, use the debug exporter instead` ★ (removed in v0.111.0, Oct 2024) |
| **Duplicate YAML key** | `yaml: unmarshal errors: line 4: mapping key "batch" already defined at line 3` |
| **Profiles pipeline without the gate** | `service::pipelines: pipeline "profiles": profiling signal support is at alpha level, gated under the "service.profilesSupport" feature gate` |

★ **The connector-not-declared case is a genuine trap.** `span_metrics` is a valid component name, so the error reads like a typo. **Connectors must be declared in their own top-level `connectors:` block** — they are neither receivers nor exporters, they're both.

### Processor-specific errors

| Mistake | Exact error |
|---|---|
| `memory_limiter` with no limit | `processors::memory_limiter: 'limit_mib' or 'limit_percentage' must be greater than zero` |
| `batch` max smaller than size | `processors::batch: send_batch_max_size must be greater or equal to send_batch_size` |
| `tail_sampling` with `num_shards > 256` | `processors::tail_sampling: num_shards (999) must not exceed 256` |
| `tail_sampling` with `num_shards > 1` **and** `tail_storage` | `processors::tail_sampling: num_shards greater than 1 is not supported with tail_storage` |
| ★ `tail_storage` written as a map | `'tail_storage' has invalid keys: directory, kind` — **it takes a component-ID string** (`tail_storage: file_storage`), per source: `TailStorageID *component.ID`. **This error appears even with the feature gate enabled** |
| `tail_storage` set with the gate **off** | Validation fails — enable `processor.tailsamplingprocessor.tailstorageextension` |
| `redaction` with a short HMAC key | `processors::redaction: hmac_key must be at least 32 bytes long for "hmac-sha256", got 6 bytes` (★ **64 bytes for `hmac-sha512`**) |
| `redaction` HMAC key env var unset | `processors::redaction: hmac_key must not be empty when hash_function is "hmac-sha256"` ★ **fail-closed — the Collector won't start** |
| `k8s_attributes` gates mis-set | `processor.k8sattributes.DontEmitV0K8sConventions cannot be enabled without enabling processor.k8sattributes.EmitV1K8sConventions` |

### Exporter / extension errors

| Mistake | Exact error |
|---|---|
| `load_balancing` legacy protocol value | `'protocol' has invalid keys: spanmetrics` ★ (schema changed — `routing_key` is now **top-level**, and `protocol:` accepts only `otlp`) |
| `file_storage` directory missing | `extensions::file_storage: directory must exist: stat /var/lib/otelcol: no such file or directory. You can enable the create_directory option to automatically create it` |
| Unresolved `${env:VAR}` | `cannot resolve the configuration: retrieved value (type=string) cannot be used as a Conf` — ★ usually an **empty env var** or a YAML-parsing collision, not a missing one |
| Prometheus exporter `resource_to_telemetry_conversion` with the disable gate on | `resource_to_telemetry_conversion is disabled by the exporter.prometheus.DisableResourceToTelemetryConversion feature gate; use resource_constant_labels instead` |
| Invalid `translation_strategy` | `invalid translation_strategy: <value>` — valid: `UnderscoreEscapingWithSuffixes`, `UnderscoreEscapingWithoutSuffixes`, `NoUTF8EscapingWithSuffixes`, `NoTranslation` |

### The error-prefix decoder ★
Error messages are prefixed by **which phase failed**, and that tells you where to look:

| Prefix | Phase | Means |
|---|---|---|
| `failed to get config: cannot unmarshal` | **Config decoding** | YAML/schema problem. Wrong keys, wrong types, unknown component |
| `failed to get config: cannot resolve` | **Config resolution** | `${env:}`/confmap provider problem. Secrets, file includes |
| `service::pipelines::X: references ...` | **Wiring** | Component referenced but not defined |
| `failed to build pipelines:` | **Component construction** | Valid config, but incompatible combination (wrong signal type, connector half-wired) |
| `<section>::<component>: <msg>` | **Component `Validate()`** | The component's own semantic validation |

---

## 16.4 ★★ What `validate` does NOT catch

**This is the most valuable section in the file.** `validate` is a config-decoding and wiring check. It runs **no data** and starts **no listeners**. Verified by testing each case against the v0.161.0 binary:

| Silent at `validate` | Why it still breaks you | How to catch it |
|---|---|---|
| **A component defined but never wired into a pipeline** | ★ **No error at all.** Your `redaction` processor sits there doing nothing while you believe PII is being scrubbed | `print-config` + read every pipeline; check the component's own internal metrics are non-zero |
| **`memory_limiter` not first in the processor list** | ★ **No error.** You get a runtime *warning* only, and the limiter protects less than it should | Read startup logs; enforce ordering in config review / CI lint |
| **A gRPC `endpoint` with an `http://` scheme** | ★ **No error** from `validate`. `0.0.0.0:4317` is the expected `host:port` form | Runtime dial errors; use `host:port` only |
| **Wrong temporality for the destination** | No error. Prometheus silently computes garbage from delta data | Compare against a known-good source; check the `prometheus_remote_write` docs and your backend's requirement |
| **OTTL statement that matches nothing** | ★ **No error — and with `error_mode` defaulting to `ignore`, a malformed condition is swallowed too** | Set `error_mode: propagate` while developing; count with `debug` exporter before/after |
| **`filter` that drops everything** | No error. An over-broad condition silently zeroes a pipeline | Diff accepted-vs-sent metrics before and after adding the filter |
| **Semantic mismatches between components** | e.g. `load_balancing` DNS pointing at a **ClusterIP** Service — resolves fine, but returns one VIP so all traces hit one replica | Check `otelcol_exporter_sent_spans` **per backend**; a headless Service is required |
| **Cardinality explosions** | No error until the backend rejects | `cardinality_guardian` in `tag_only` + `processor_cardinality_top.offenders` |
| **Missing RBAC for `k8s_attributes` / `load_balancing` k8s resolver** | No error. Enrichment silently doesn't happen; resolver cache stays empty | Startup logs (`couldn't find the exporter for the endpoint ""`); check that `k8s.*` attributes appear on real data |
| **`pod_association` failing behind SNAT** | No error. Enrichment just doesn't happen | Compare enriched vs total spans |
| **Backend rejecting data (401/413/429)** | No error at config time | `otelcol_exporter_send_failed_*` and the Collector's error logs |
| **Resource exhaustion** | No error. OOMKill, queue full, CPU saturation | Container metrics + `otelcol_exporter_queue_size` |
| **Clock skew** | No error. ★ **Traces look impossible** — negative durations, spans ending before they start, wrong ordering | Compare timestamps across hosts; NTP/chrony |
| **Sampling decisions you didn't intend** | No error. Traces are simply absent | `global_count_traces_sampled`, `count_traces_sampled{decision,policy}` |

★ **The meta-lesson: `validate` passing tells you the Collector will START. It tells you nothing about whether it will do what you meant.** Every item above is a case where a config is syntactically perfect and semantically wrong.

**Therefore the CI check should be two-stage:**
```bash
# 1. will it start?
otelcol-contrib validate --config=config.yaml

# 2. is it what I meant?  — diff against a golden file
otelcol-contrib print-config --config=config.yaml > /tmp/resolved.yaml
diff <(yq '.service.pipelines' golden.yaml) <(yq '.service.pipelines' /tmp/resolved.yaml)
```

---

## 16.5 Symptom → cause → fix

### "No data at all"
| Check | Command / metric | Likely cause |
|---|---|---|
| Is the Collector up? | `kubectl get pods`, `/health` on `:13133` | CrashLoop → read the startup error against §16.3 |
| Is it listening where you think? | `ss -lntp` in the pod | ★ Bound to `localhost` not `0.0.0.0` |
| Did it accept anything? | `otelcol_receiver_accepted_spans` | Zero → SDK/network problem, not Collector |
| Did the SDK export? | SDK logs at debug; `OTEL_EXPORTER_OTLP_ENDPOINT` | ★ **Env var unset, or the endpoint has a wrong scheme/port** |
| Is the port right? | gRPC **4317**, HTTP **4318** | ★ **Mixing them up is the single most common "no data" cause.** HTTP/protobuf to a gRPC port fails |
| NetworkPolicy? | `kubectl describe networkpolicy` | Blocks egress to the Collector |
| Service name resolution? | `nslookup` from the app pod | Wrong namespace suffix |

★ **The 4317/4318 confusion deserves its own line.** OTLP/gRPC and OTLP/HTTP are **different wire protocols on different ports**. Sending OTLP/HTTP to 4317 produces a gRPC framing error; sending gRPC to 4318 produces an HTTP 400. **Both look like "nothing arrives."** Check `OTEL_EXPORTER_OTLP_PROTOCOL` (`grpc` | `http/protobuf` | `http/json`) matches the port.

### "Data arrives but the values are wrong"
| Symptom | Cause | Fix |
|---|---|---|
| Counters look 10× too high or reset randomly | ★ **Delta temporality sent to a cumulative-expecting backend** | `cumulative_to_delta` / `delta_to_cumulative` processor, or set `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` |
| Metric not found in Prometheus | ★ **Name transformation** — dots→underscores + suffixes | Query `http_server_request_duration_seconds_bucket`, not `http.server.request.duration` |
| Metric name has no suffix when you expected one | `translation_strategy` changed | ★ `add_metric_suffixes` is **deprecated and ignored**; set `translation_strategy` |
| Latency shows 0.5 instead of 500 | ★ **Unit change between semconv V0 and V1** (ms → s) | Check the `unit` field, not just the name |
| Dashboard works for some services only | ★ **Mixed semconv generations** — `k8s_attributes` is V1-only, `host_metrics` is V0-only | [`04-semantic-conventions.md`](04-semantic-conventions.md); check `scope.schema_url` |
| `k8s.pod.annotations.x` returns nothing | ★ **V1 uses SINGULAR**: `k8s.pod.annotation.x`, `k8s.pod.label.x` | Rename the query |
| Histogram quantiles disagree with raw data | Exponential vs explicit bucket conversion | Check the exporter's histogram translation |
| Span durations negative or spans out of order | ★ **Clock skew** | NTP/chrony on nodes |
| `service.name` is `unknown_service:java` | Resource detector didn't run, or `OTEL_SERVICE_NAME` unset | Set it explicitly; check resource processor ordering |
| Attributes missing that you set | ★ **A `filter`/`attributes`/`transform` processor dropped them** — and `error_mode: ignore` swallowed the reason | `print-config`, then `debug` exporter before and after each processor |

### "Data is intermittent / partially missing"
| Symptom | Cause | Fix |
|---|---|---|
| Traces have gaps — some spans missing | ★ **Tail sampling without `parentbased`, or spans arriving after `decision_wait`** | Check `sampling_late_span_age` vs `decision_wait`; set `decision_cache` sizes |
| Whole traces missing but no errors | ★ **Default `tail_sampling` outcome is NOT sampled** — no policy matched | Verify a policy actually matches; add an `always_sample` baseline |
| Data loss during deploys | Grace period shorter than drain | ★ `terminationGracePeriodSeconds: 60` + `preStop: sleep 10` |
| Loss during scale events | ★ **Scaling reroutes ~R/N of traces** away from a `tail_sampling` replica | Scale in small increments; consistent hashing; scale before load |
| Loss under load spikes | Queue full → refusal | `otelcol_exporter_queue_size`, raise `queue_size`, add replicas |
| Loss on every restart | In-memory queue | `sending_queue.storage: file_storage` |
| Random gaps, no pattern | ★ **SDK batch processor overflow** (queue full, dropped silently) | Check SDK dropped-count metrics; raise `OTEL_BSP_MAX_QUEUE_SIZE` |
| Only some pods' data missing | `k8s_attributes` `pod_association` failing behind SNAT | Use `resource_attribute: k8s.pod.ip` via the downward API |
| Metrics present, exemplars missing | Exemplars not enabled / trace not sampled | Exemplars need a sampled trace ID |

---

## 16.6 Accounting for data loss — every point where telemetry can vanish

★ **The most useful mental model in this file.** Telemetry can be dropped at **seven** places, and each has its own counter. If you can't say which one dropped it, you can't fix it.

| # | Where | Metric / evidence | Default behaviour |
|---|---|---|---|
| 1 | **SDK batch processor queue overflow** | `otelcol_sdk_*` / SDK logs; span processor dropped count | ★ **Drops silently** once `OTEL_BSP_MAX_QUEUE_SIZE` is hit |
| 2 | **SDK cardinality limit** | Series with `otel.metric.overflow = true` | Aggregates into overflow — **visible if you alert on it** |
| 3 | **Network / exporter retry exhaustion** | SDK export failure logs | ★ **Drops after `max_elapsed_time`** |
| 4 | **Collector receiver refusal** (memory_limiter or downstream) | `otelcol_receiver_refused_spans` / `_metric_points` / `_log_records` | Refuses with an error to the SDK, which retries then drops |
| 5 | **Collector processor drop** (`filter`, `tail_sampling`, `span_pruning`) | `otelcol_processor_dropped_*`, `count_traces_sampled{decision="dropped"}` | ★ **Intentional** — but confirm it's what you meant |
| 6 | **Collector export queue overflow** | `otelcol_exporter_queue_size`, `otelcol_exporter_send_failed_*` | ★ **Drops when the queue is full**; `retry_on_failure` and `sending_queue` are **OFF by default** |
| 7 | **Backend rejection / ingestion limit** | Backend-side metrics, `send_failed_*` with 4xx | Silently from the app's perspective |

★ **Two defaults that make #6 the usual culprit: `sending_queue` and `retry_on_failure` are DISABLED by default on exporters.** Without them, a momentary backend blip drops data immediately with no retry. **Enable both, always.**

★ **And a verified subtlety about #4:** the gate `receiverhelper.newReceiverMetrics` is **false (Alpha)**, whose description states it *"is a breaking change for the semantics of `otelcol_receiver_refused_metric_points`, `otelcol_receiver_refused_log_records` and `otelcol_receiver_refused_spans`."* **So today those counters do NOT distinguish downstream refusals from internal errors.** A rising `refused` count tells you data was rejected, but **not why** — correlate with `memory_limiter` state and exporter errors.

### The backpressure chain, end to end
```
backend slow/unavailable
 → exporter retry_on_failure backs off (if enabled — ★ off by default)
 → sending_queue fills (if enabled — ★ off by default)
 → queue full → exporter refuses to the processor
 → processor refuses to the receiver
 → memory rises → memory_limiter fires → receiver REFUSES (#4)
 → OTLP receiver returns an error to the SDK
 → SDK retries with backoff, then DROPS (#1/#3)
```
★ **This is a feature.** The alternative is unbounded buffering and an OOMKill that loses *everything* in flight plus a cold restart.

**Alert on the leading indicator:** `otelcol_exporter_queue_size / otelcol_exporter_queue_capacity > 0.8` rises **minutes before** `send_failed` does.

---

## 16.7 Performance troubleshooting

### Collector is slow
| Evidence | Likely cause | Fix |
|---|---|---|
| `otelcol_processor_tail_sampling_sampling_decision_timer_latency` > 1s | ★ **Decisions are being made after `decision_wait` has already elapsed** → late/incorrect decisions | Keep downstream fast; raise replicas; lower `decision_wait`; increase `num_shards` |
| High CPU, one core pegged | Single-threaded pipeline bottleneck | ★ **`num_shards`** on `tail_sampling` (divides `num_traces`/caches/rate limits evenly; **not** `burst_capacity`; max 256; **incompatible with `tail_storage`**) |
| Memory climbing steadily | `tail_sampling` buffer or decision caches undersized/oversized | `num_traces × trace size + caches`; raise the limit and `limit_percentage` together |
| `sampling_trace_dropped_too_early` > 0 | ★ **Circular buffer evicting traces before their decision** | Raise `num_traces`, or lower `decision_wait`, or add replicas |
| Queue growing but backend healthy | `num_consumers` too low | Raise it; check `timeout` isn't longer than the drain window |
| Everything slow after adding a processor | ★ **An OTTL `transform` with a regex on every record**, or `IsMatch` in a hot loop | Profile with `pprof`; precompile; move filtering earlier |
| Slow only for one signal | Pipeline-specific processor | Check ordering — a heavy processor before `batch` runs per-item |

### SDK is slow / the app got slower after instrumenting
| Evidence | Likely cause | Fix |
|---|---|---|
| Latency up after enabling the SDK | ★ **Synchronous exporter, or batch size 1** | `BatchSpanProcessor`, not `SimpleSpanProcessor` |
| CPU up in the app | Too-frequent metric collection, or expensive async callbacks | Raise the interval; ★ **verify callbacks are cheap and non-blocking** |
| Periodic latency spikes | Export flush on a request thread | Export on a dedicated goroutine/thread; check `schedule_delay` |
| Memory growth in the app | Batch queue overflow, or unbounded span attributes | `OTEL_BSP_MAX_QUEUE_SIZE`, span limits |
| Startup slow | Resource detectors blocking | ★ Set `timeout` and `override: false` on detectors; the container/cloud detector can take seconds |
| Lost telemetry on every deploy | ★ **Providers never flushed at shutdown** | Call `tp.Shutdown()` / `tracerProvider.Shutdown(ctx)` in a shutdown hook |

★ **That last one is the most common SDK bug in production.** Without an explicit shutdown flush, every rolling deploy drops the last batch of buffered telemetry — and because it happens on *every* deploy, it looks like random data loss rather than a missing line of code.

---

## 16.8 Kubernetes-specific troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ★ `unknown receiver "host_metrics"` on a fresh CR | **The Operator's default image is core `otelcol`, not contrib** | `--set manager.collectorImage.repository=otel/opentelemetry-collector-contrib` |
| Target Allocator error naming the Prometheus receiver | ★ **Receiver must be named exactly `prometheus`** — `prometheus/otelcol` fails. Since v0.152.0 the error **lists the instances it found** | Rename it |
| TA assigns no targets | Missing RBAC (pods/services/endpoints/nodes/namespaces, `monitoring.coreos.com` CRDs) | Add the ClusterRole |
| ★ TA Deployment reconciles forever | A shallow-copy bug **fixed in Operator v0.149.0** | Upgrade |
| ServiceMonitor secret changes not picked up | **Fixed in v0.147.0**; ★ and since v0.151.0 you need `spec.prometheusCR.secretNamespaces` — **if unset, NO namespaces are watched for secrets** | Upgrade + set `secretNamespaces` |
| `load_balancing` k8s resolver finds nothing | ★ Missing `discovery.k8s.io/v1` `endpointslices` get/list/watch → log `couldn't find the exporter for the endpoint ""` | Add RBAC |
| All traces go to one gateway replica | ★ **ClusterIP Service as the DNS target** — DNS returns one VIP | **Use a headless Service (`clusterIP: None`)** |
| `k8s.*` attributes missing | `pod_association` failing behind mesh/LB/SNAT | ★ Use `resource_attribute: k8s.pod.ip` from the downward API |
| Enrichment slow / API server load high | ★ `ShareProcessorBetweenPipelines` is **off by default** — three pipelines = three k8s API watchers; DaemonSets watch all pods | Enable the gate; set `filter.node_from_env_var` on agents |
| Sidecar not injected | Missing `sidecar.opentelemetry.io/injected` annotation, or webhook down | Check the annotation and webhook health |
| ★ **Nothing injects at all, cluster-wide** | `admissionWebhooks.failurePolicy: Fail` + Operator down → **pod creation blocked** | Scope selectors, or accept `Ignore` |
| Auto-instrumented pods OOMKilled | ★ **The Java agent adds tens of MB of heap; limits weren't raised** | Raise memory limits **before** enabling |
| mTLS breaks after cert-manager renewal | ★ **Hot-reload added in Operator v0.145.0** (fsnotify) | Upgrade; before that, restart pods on renewal |
| Collector ingests its own logs in a loop | `file_log` on `/var/log` without excluding itself | ★ Exclude `/var/log/pods/<ns>_otel-*/*/*.log` |
| Data lost on every rollout | Grace period < drain time | `terminationGracePeriodSeconds: 60`, `preStop: sleep 10` |

---

## 16.9 The escalation checklist

When you're stuck, in order:

1. **`otelcol-contrib validate --config=...`** — will it start? Match any error against §16.3.
2. **`otelcol-contrib print-config --config=...`** — is the resolved config what you meant? ★ **Check every pipeline lists every processor you expect.**
3. **`otelcol-contrib components`** — is the component even in your distribution?
4. **`otelcol-contrib featuregate | grep <thing>`** — ★ **is a gate changing the default behaviour you assumed?** (Never use `--help` for this.)
5. **Add `debug` with `sampling_initial: 5`** at the end of the pipeline. Does data arrive?
6. **Move `debug` upstream**, one processor at a time, until the data disappears. **That processor is your bug.**
7. **Set `error_mode: propagate`** on every `filter`/`transform`/`routing`. ★ **The default is `ignore`, which swallows OTTL errors silently.**
8. **Check the seven loss points** (§16.6) via metrics, not guesses.
9. **Generate synthetic traffic** with `telemetrygen` to separate "app isn't sending" from "pipeline is broken."
10. **Read the startup logs in full.** Warnings about processor ordering, deprecated components and gate migrations appear once, at boot, and are easy to scroll past.
11. **Compare against a known-good config.** The validated configs in this folder's `labs/` directory are known-good for v0.161.0.
12. **Check the version.** ★ Collector releases every ~2 weeks (**v0.161.0 → v0.162.0 due 2026-09-28**). Behaviour you read about in a blog post from last year may no longer apply — **`logging` exporter removed in v0.111.0**, `load_balancing` schema changed, components renamed to snake_case in v0.161.0, `LoggingOptions`/`ConfigWatcher` removed.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Starting the investigation at the application code | Steps 1–3 of §16.1 take a minute and eliminate most hypotheses |
| Reading gate defaults from `otelcol-contrib --help` | ★★ **Wrong for several gates.** Believing it inverts your understanding of `error_mode` defaults and semconv emission. **Use `featuregate`** |
| Trusting `validate` passing as "the config is correct" | ★ **It only proves the Collector will START.** It doesn't catch unwired processors, `memory_limiter` ordering, wrong temporality, no-op OTTL, or SNAT-broken enrichment |
| Not diffing `print-config` output in CI | Silent drift between what you wrote and what runs |
| Leaving `error_mode` at its default while debugging OTTL | ★ **Default is `ignore`** — malformed conditions are swallowed, so a broken filter looks like a working one |
| Never checking the component's own internal metrics | `accepted` vs `sent` vs `refused` vs `send_failed` localises the fault in seconds |
| No alert on `otelcol_exporter_queue_size` | ★ The leading indicator; everything else is lagging confirmation |
| Not alerting on the `otel.metric.overflow` series | Silent cardinality aggregation |
| Ignoring startup warnings | Processor-ordering, deprecation and gate-migration warnings print once |
| Debugging with `debug` at `verbosity: detailed` in production | ★ Unredacted span/log content into your log store |
| Exposing `zpages`/`pprof` beyond localhost | Live span data and heap contents |
| Assuming `refused_*` tells you *why* data was refused | ★ `receiverhelper.newReceiverMetrics` is off, so it does **not** distinguish downstream from internal errors |
| Not enabling `sending_queue` and `retry_on_failure` | ★ **Both OFF by default** — a momentary backend blip drops data instantly |
| Debugging missing traces without checking `tail_sampling` policies matched | **Default outcome is NOT sampled** — no match means no trace, with no error |
| Missing shutdown flush in the SDK | Every deploy drops the last batch; looks like random loss |
| Mixing OTLP/gRPC (4317) with OTLP/HTTP (4318) | ★ The most common "no data" cause, and both directions look identical |
| Debugging a ClusterIP Service as a `load_balancing` target | Resolves fine, routes everything to one replica |
| Not checking clock skew when spans look impossible | Negative durations and reordering are almost always NTP |
| Applying a fix found in a year-old blog post | ★ ~2-week release cadence; `logging` removed in v0.111.0, `load_balancing` schema changed, snake_case renames in v0.161.0 |

---

## Rapid recall

1. **Debug backwards from the consumer:** backend → Collector received (`otelcol_receiver_accepted_*`) → Collector exported (`sent_*` vs `send_failed_*`) → network → SDK sent → SDK created. ★ **Steps 1–3 take a minute and eliminate most hypotheses.**
2. **First triage question: is data MISSING or WRONG?** Missing → the drop chain (§16.6). Wrong → naming, temporality, semconv, enrichment. **Nearly disjoint causes.**
3. **Five tools:** `debug` exporter (with `sampling_initial`/`sampling_thereafter`), ★ **`print-config`** (resolved config — answers "did my override apply / what default filled in / did the env var resolve"), `components` (is it in *your* distribution), ★★ **`featuregate`**, and `zpages`/`pprof` on the running process. Plus **`telemetrygen`** for synthetic traffic to separate "app isn't sending" from "pipeline is broken".
4. ★★ **Never read gate state from `--help`.** Verified disagreements in v0.161.0: `processor.filter.defaultErrorModeIgnore`, `processor.transform.defaultErrorModeIgnore`, `processor.k8sattributes.DontEmitV0K8sConventions`, `connector.routing.defaultErrorModeIgnore`, `ottl.set.allowNil`, `service.partialReloadReceivers` all show `-` in `--help` but are **true** in `featuregate` — **confirmed against source** (`createDefaultConfig()` sets `ErrorMode: ottl.IgnoreError`). `ottl.functions.enableLambda` and `connector.spanmetrics.excludeResourceMetrics` are the reverse.
5. **Read the error prefix:** `cannot unmarshal` = schema/YAML; `cannot resolve` = `${env:}`/providers; `service::pipelines::X: references ...` = wiring; `failed to build pipelines:` = valid config, incompatible combination; `<section>::<component>:` = the component's own `Validate()`.
6. **Key verbatim errors:** `unknown type: "batchl" ... (valid values: [...])` ★ **it lists every valid value**; `connector "span_metrics" used as exporter in [traces] pipeline but not used in any supported receiver pipeline`; `failed to create "prometheus" exporter for data type "traces": telemetry type is not supported`; `service must have at least one pipeline`; `pipeline "profiles": profiling signal support is at alpha level, gated under the "service.profilesSupport" feature gate`; `'exporters' the logging exporter has been deprecated, use the debug exporter instead`; `mapping key "batch" already defined at line 3`; `'protocol' has invalid keys: spanmetrics`; `num_shards greater than 1 is not supported with tail_storage`; `hmac_key must be at least 32 bytes long for "hmac-sha256"` (64 for sha512); `directory must exist ... You can enable the create_directory option`.
7. ★ **A connector not declared under `connectors:` reports as `'exporters' unknown type: "span_metrics"`** — reads like a typo but the name is valid, just in the wrong section.
8. ★ **`tail_storage` takes a component-ID string** (`tail_storage: file_storage`), not a map. Writing `{kind: file, directory: ...}` gives `'tail_storage' has invalid keys: directory, kind` — **even with the gate enabled**, sending you hunting for the gate instead of the schema.
9. ★★ **What `validate` does NOT catch — it proves the Collector will START, nothing more:** a component **defined but never wired** (no error at all — your `redaction` processor silently does nothing), **`memory_limiter` not first** (runtime warning only), a gRPC endpoint with an `http://` scheme, **wrong temporality**, **OTTL that matches nothing or errors** (swallowed by `error_mode: ignore`), a filter that drops everything, a ClusterIP `load_balancing` target, cardinality explosions, **missing RBAC** for `k8s_attributes`/the k8s resolver, `pod_association` failing behind SNAT, backend 401/413/429, resource exhaustion, **clock skew**, and unintended sampling decisions. **CI should be two-stage: `validate`, then diff `print-config` against a golden file.**
10. **"No data at all":** Collector up? Listening on `0.0.0.0`? `receiver_accepted_*` non-zero? SDK env vars set? ★ **Port 4317 (gRPC) vs 4318 (HTTP) — mixing them is the single most common cause and both directions look identical**; check `OTEL_EXPORTER_OTLP_PROTOCOL` matches the port. Then NetworkPolicy and DNS.
11. **"Values are wrong":** delta→cumulative mismatch; ★ **Prometheus name transformation** (`_total`/`_seconds`/`_bucket`); `add_metric_suffixes` deprecated and ignored → use `translation_strategy`; **ms→s unit change between semconv V0/V1**; ★ **mixed generations** (`k8s_attributes` V1-only, `host_metrics` V0-only); **`k8s.pod.annotation.<k>` is SINGULAR under V1**; clock skew; `service.name` = `unknown_service:java`.
12. **"Intermittent":** `parentbased` missing in sampling; late spans past `decision_wait` (`sampling_late_span_age`); grace period < drain; ★ **scaling reroutes ~R/N of traces**; queue overflow; in-memory queue lost on restart; **SDK batch queue overflow**; `pod_association` behind SNAT.
13. ★ **Seven loss points, each with its own counter:** ① SDK batch queue overflow (**drops silently**), ② SDK cardinality limit (`otel.metric.overflow`), ③ SDK retry exhaustion, ④ **Collector receiver refusal** (`receiver_refused_*`), ⑤ **intentional processor drop** (`filter`/`tail_sampling`), ⑥ **exporter queue overflow** (`exporter_queue_size`, `send_failed_*`), ⑦ backend rejection. **If you can't say which one dropped it, you can't fix it.**
14. ★ **`sending_queue` and `retry_on_failure` are OFF by default** — a momentary backend blip drops data instantly. Enable both. And `receiverhelper.newReceiverMetrics` is **false**, so **`refused_*` does NOT distinguish downstream refusals from internal errors.**
15. **The backpressure chain is a feature:** backend slow → retries → queue fills → processor refuses → `memory_limiter` refuses → SDK retries then drops (and counts it). **The alternative is an OOMKill that loses everything plus a cold restart.** ★ **Alert on `queue_size / queue_capacity > 0.8`** — the leading indicator, minutes before `send_failed`.
16. **Performance:** `sampling_decision_timer_latency > 1s` means decisions land after `decision_wait` → keep downstream fast; ★ `num_shards` (max 256) relieves single-loop contention but **divides `num_traces`/caches/rate limits evenly, NOT `burst_capacity`, and is incompatible with `tail_storage`**; `sampling_trace_dropped_too_early > 0` = buffer eviction.
17. **SDK performance:** `BatchSpanProcessor` not `Simple`; cheap non-blocking async callbacks; detector `timeout` + `override: false`; ★ **and always flush providers at shutdown (`tp.Shutdown()`) — missing this drops the last batch on every deploy, which looks like random data loss.**
18. ★ **Kubernetes first check: the Operator's default image is core `otelcol`, not contrib** → `unknown receiver "host_metrics"`. Then: receiver must be named exactly **`prometheus`** for the TA; TA infinite reconciliation **fixed in v0.149.0**; ServiceMonitor secret updates **v0.147.0** and **`secretNamespaces` required since v0.151.0** (unset = no namespaces watched); `endpointslices` RBAC for the `load_balancing` k8s resolver; **headless Service** for DNS resolution; `ShareProcessorBetweenPipelines` off by default (3 pipelines = 3 k8s watchers); `failurePolicy: Fail` can block pod creation cluster-wide; **raise memory limits before enabling Java auto-instrumentation**; mTLS hot-reload since **v0.145.0**.
19. **Escalation order:** `validate` → `print-config` → `components` → `featuregate` → `debug` at the end → **move `debug` upstream one processor at a time until data disappears (that processor is your bug)** → `error_mode: propagate` everywhere → check the seven loss points → `telemetrygen` → **read the full startup logs** → compare against a known-good config → **check the version**.
20. ★ **Check the version before applying any fix you read about.** ~2-weekly cadence (**v0.161.0 → v0.162.0 due 2026-09-28**). Recent breaking changes: `logging` exporter removed in **v0.111.0**, `load_balancing` schema changed (`routing_key` top-level, `protocol:` accepts only `otlp`), components renamed to **snake_case** in v0.161.0 (old names still work as deprecated aliases), `LoggingOptions`/`ConfigWatcher` removed.

→ Next: [`17-migration-and-adoption.md`](17-migration-and-adoption.md)
