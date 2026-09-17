# Labs — Runnable OpenTelemetry

Six labs, each a self-contained `docker-compose` stack (Lab 06 is Kubernetes). They build on each other but **any one can be run alone**.

**Everything here is machine-validated.** Not eyeballed — actually checked:

| What | How |
|---|---|
| **Every Collector config** | The real `otelcol-contrib` **v0.161.0** binary, run with `validate` |
| **Every `prometheus.yml`** | **`promtool check config`** (Prometheus 3.14.0) |
| **All 94 dashboard queries** | ★ `promtool check rules` for PromQL, structural checks for LogQL — see [`_tools/check_dashboards.py`](_tools/check_dashboards.py) |
| **All 12 alert rules** | `promtool check rules` |
| **Every dashboard JSON** | Round-trip parse; duplicate panel IDs; datasource UID cross-reference |
| **Shell scripts in compose files** | `busybox ash -n` |
| **Volume ↔ mount consistency** | Scripted cross-reference per workload |
| **ConfigMap ↔ validated source** | Byte-comparison, so the K8s manifests cannot drift |

★ **Validation catches syntax and schema, not semantics.** It will *not* tell you that `memory_limiter` isn't first in your processor list, that a gRPC `endpoint` has a stray `http://` prefix, that a component is defined but never referenced, or that your processor ordering breaks correlation. Those are called out with ★ in the configs themselves — and each lab has exercises that **break things on purpose** so you see the failure mode.

---

## The labs

| # | Lab | What you'll be able to do after | Time | RAM |
|---|---|---|---|---|
| **01** | [`lab-01-collector-fundamentals`](lab-01-collector-fundamentals/) | Read and write a Collector config; know what `validate` does and doesn't catch; scrape internal telemetry | 30 min | 2 GB |
| **02** | [`lab-02-instrumented-app`](lab-02-instrumented-app/) | Instrument an app with **zero code changes**; wire the full correlation triangle; discover the `loki` exporter is gone | 45 min | 4 GB |
| **03** | [`lab-03-sampling`](lab-03-sampling/) | Explain head vs tail with numbers; tune `tail_sampling` without losing data; size the buffer | 45 min | 4 GB |
| **04** | [`lab-04-metrics-and-prometheus`](lab-04-metrics-and-prometheus/) | Predict the OTel→Prometheus name transformation; avoid the **silent** temporality trap; choose pull vs push | 45 min | 4 GB |
| **05** | [`lab-05-logs-and-correlation`](lab-05-logs-and-correlation/) | Get logs into Loki the supported way; correlate an **uninstrumented** service; verify redaction actually works | 60 min | 5 GB |
| **06** | [`lab-06-kubernetes`](lab-06-kubernetes/) | Run a correct two-tier fleet; zero-code inject via the Operator; **monitor the Collector itself** | 90 min | cluster |

---

## Recommended order

**Doing all six?** Go 01 → 06. Each reuses the previous lab's app image, so builds get faster.

**Short on time?**

| You are | Do these | Why |
|---|---|---|
| **A developer** asked to "add tracing" | **02**, then 04 | 02 is zero-code instrumentation end to end; 04 is what your metrics will actually be called |
| **SRE / platform** | **03**, **06**, then 04 | Sampling and Kubernetes are the cost/correctness decisions you own |
| **On-call**, and something's broken | **01**, then **03** | 01 teaches you to read the telemetry that tells you what's wrong; 03 explains "where did my traces go" |
| **Security / compliance** | **05**, then 02 | 05 is PII redaction and how to prove it works |
| **Interview prep** | **03**, **04**, **06** | These three cover the questions that separate "used it" from "understands it" |

---

## The verified environment

Pinned because these labs were built against them on **2026-09-17**:

| Image | Tag |
|---|---|
| `otel/opentelemetry-collector-contrib` | **0.161.0** (core v1.67.0, released 2026-09-14) |
| `grafana/tempo` | 3.0.3 |
| `grafana/loki` | 3.7.7 |
| `grafana/grafana-oss` | 13.0.2 |
| `prom/prometheus` | v3.14.0 |
| `alpine` (traffic generators) | 3.21 |

★ **The Collector ships roughly every two weeks** (v0.162.0 was due 2026-09-28). Bumping the tag is usually fine, but check the three things that have bitten these labs: removed components (`logging`, `lokiexporter`), renamed keys (`dimensions_cache_size` → `aggregation_cardinality_limit`), and feature-gate defaults.

---

## Running a lab

Every compose lab follows the same shape:

```bash
cd labs/lab-02-instrumented-app
docker compose up -d --build
docker compose ps                              # all services should be Up
open http://localhost:3000                     # Grafana — admin / admin
```

**Wait 2–3 minutes** before judging. Batching intervals, `decision_wait`, scrape intervals and Tempo's block flush all mean the first data appears late. Dashboards looking empty at T+30s is normal.

```bash
docker compose logs -f collector               # the most useful window in any lab
docker compose down -v                         # ★ -v removes volumes, else state persists
```

★ **Grafana credentials are `admin` / `admin`** and anonymous admin access is enabled — these are throwaway local stacks. **Never copy the `environment:` blocks into a real deployment.**

★ **Ports 3000 / 9090 / 3100 / 3200 / 4317 / 4318 / 8888 / 8889 must be free.** Only one lab can run at a time on default ports; `docker compose down -v` before switching.

---

## ★★ The gotchas these labs exist to teach

Everything below was hit while building them, and each is reproduced deliberately in an exercise.

### Components that don't exist any more

| You'll try | Reality |
|---|---|
| `exporters: [logging]` | **Removed** → `the logging exporter has been deprecated, use the debug exporter instead` |
| `exporters: [loki]` | ★★ **Removed entirely.** `loki` is a **receiver only**. Use `otlphttp` → `http://loki:3100/otlp` |
| `exporters: [jaeger]` | Gone — Jaeger accepts OTLP natively |

### Keys that silently do nothing

| Key | Reality |
|---|---|
| `prometheus.add_metric_suffixes: false` | ★ **DEPRECATED AND IGNORED.** `translation_strategy` always governs |
| `span_metrics.dimensions_cache_size` | **DEPRECATED** (still parses) → `aggregation_cardinality_limit` |
| `loadbalancing:` | Renamed **`load_balancing`**; old name is a deprecated alias |
| Grafana `derivedFields[].regex` | ★ **Ignored.** The key is **`matcherRegex`** — the link just never appears |
| Grafana `tracesToLogs` | **Legacy V1.** Current is **`tracesToLogsV2`** |
| `k8sattributes.extract.labels[].tag` | ★ **The key is `tag_name`** |

### Types that are surprisingly strict

| Setting | Trap |
|---|---|
| `load_balancing.resolver.dns.port` | ★★ **A STRING** (`"4317"`). Every other port in a Collector config is an int |
| `redaction.hash_function` | ★ Allowed: **`sha1, sha3, md5, hmac-sha256, hmac-sha512`**. Bare `sha256` **fails** |
| `probabilistic_sampler.hash_seed` | **An int**, not a string. `hash_salt` is `tail_sampling`'s — different component |
| `tail_sampling` composite `percent` | ★ Lives **only** in `rate_allocation`, not in `composite_sub_policy` |
| `count` connector `spans`/`logs` | **MAPS, not lists** |

### Defaults that bite

| Default | Consequence |
|---|---|
| ★★ `tail_sampling.decision_cache` sizes = **0** | **Inactive.** Late spans get a **fresh independent decision** → partial traces, no error |
| ★★ No `tail_sampling` policy matches | **The trace is DROPPED.** Always end with a catch-all |
| `health_check` / telemetry bind **localhost** | ★ Kubelet probes the **pod IP** → restart-loops a healthy Collector |
| `filter.error_mode` = **`ignore`** | A malformed OTTL condition is **swallowed**; the filter silently does nothing |
| Prometheus `--enable-feature=exemplar-storage` **off** | Exemplars **accepted but not retained** — silent |
| `resource_to_telemetry_conversion.enabled: true` | Promotes **every** resource attribute to a label on every series |
| Instrumentation `useLabelsForResourceAttributes` **off** | Everything reports as **`unknown_service:python`** |
| Python/.NET SDK protocol | ★★ **HTTP by default → :4318**, not gRPC :4317. Exports nothing, silently |

### Things that emit no telemetry at all

| Component | Reality |
|---|---|
| ★★ `redaction` processor | **NO internal metrics.** Verified: no `generated_telemetry.go`, none in `metadata.yaml`. It writes **attributes** onto the data. To alert on it, derive a metric via a `span_metrics` connector with `redaction.masked.count` as a dimension |
| ★ `load_balancing` | **Exporter only** — cannot bridge pipelines like a connector |
| Defined-but-unreferenced components | ★ **`validate` passes clean.** Dead config rots silently |

### The failure modes that never error

These are the reason to run the labs rather than read the docs:

| Symptom | Cause |
|---|---|
| **`rate()` returns nonsense** | **Delta temporality hitting a cumulative store.** Prometheus accepts it happily |
| **Wrong totals across replicas** | **`delta_to_cumulative` without consistent routing** — each replica sees half a stream |
| **Partial traces** | **Decision caches at 0**, or **routing after sampling** |
| **Metric "missing"** | **Name transformation** — `http.server.request.duration` → `http_server_request_duration_seconds_bucket` |
| **p99 off by 1000×** | ★ `span_metrics` duration is **milliseconds**; `service_graph` latency is **seconds** |
| **"Logs for this span" empty** | **Label name mismatch**, or `filterByTraceID: true` against **structured metadata** |
| **Correlation dead after adding redaction** | **Processor ORDER** — redacting before correlating can mask the trace ID you join on |
| **ConfigMap changed, nothing happened** | **Collectors read config at startup** — need a `checksum/config` annotation |
| **`k8s.*` attributes all absent** | **RBAC.** `k8sattributes` starts fine and enriches nothing |
| **Dashboard green, no data** | **Not alerting on `accepted_spans == 0 and up == 1`** |

★ **Processor ordering, pipeline wiring, and resource sizing are correctness concerns the validator does not model.** That's the gap these labs fill.

---

## How to read the error prefixes

`otelcol-contrib validate` error prefixes tell you **which stage** failed. Learning this halves debugging time:

| Prefix | Stage | Example |
|---|---|---|
| `cannot unmarshal the configuration` | **Schema** — wrong key or wrong type | `'hash_function' unknown HashFunction sha256` |
| `<section>::<component>:` | **`Validate()`** — parsed fine, value rejected | `exporters::otlp/tempo: requires a non-empty "endpoint"` |
| `service::pipelines::X: references ...` | **Wiring** — component not configured | `references processor "batch" which is not configured` |
| `failed to build pipelines:` | **Incompatible combination** at build time | `failed to create "prometheus" exporter for data type "traces"` |

**The blind spots** (all verified — `validate` passes clean):

- `memory_limiter` not first in the processor list (runtime warning only)
- A scheme-prefixed gRPC endpoint (`http://host:4317` — fails at **runtime**)
- Defined-but-unreferenced components
- Processor **ordering** within a pipeline list
- Whether your dashboard metric names actually exist

---

## Tooling

| Path | What |
|---|---|
| [`_tools/check_dashboards.py`](_tools/check_dashboards.py) | ★ Parse-checks every dashboard query. PromQL via `promtool check rules`; LogQL structurally. **Run it after editing any dashboard JSON** |
| `_tools/gen_payloads.py` | Generates synthetic OTLP payloads from `_tools/tpl/*.json` |
| `_tools/tpl/{traces,metrics,logs}.json` | Payload templates — ★ standalone JSON files, because deeply nested brackets get mangled when hand-written inside Python source |
| `_tools/inject_trafficgen.py` | Injects a traffic generator into a compose file |

```bash
python3 labs/_tools/check_dashboards.py
#   OK   lab-01-collector-fundamentals            19 PromQL,  0 LogQL
#   ...
#   94 expressions checked across 5 dashboards; 0 failures
```

**To re-validate a Collector config yourself:**
```bash
BIN=/path/to/otelcol-contrib          # download the release matching your image tag
$BIN validate --config=lab-01-collector-fundamentals/otel-collector-config.yaml
$BIN components                        # what's compiled into THIS binary
$BIN featuregate                       # ★ gate TRUTH — not --help, which is stale
$BIN print-config --config=...         # resolved config, incl. ${env:} substitution
```

★ **`--help`'s feature-gate default string is STALE.** Trust `otelcol-contrib featuregate` output. For several gates it reports the **opposite** value.

★ **There is no `run` subcommand** — just `otelcol-contrib --config=...`.

---

## Docker not available?

The sandbox these were built in had **no Docker daemon**, so:

- Collector configs were validated with the **real binary** — the strongest check available
- Compose files were **syntax- and semantics-checked** (anchors resolved, volume/mount cross-referenced, service dependencies verified)
- Shell scripts were checked with **`busybox ash -n`**
- Kubernetes manifests were cross-referenced for label selectors, RBAC coverage and annotation placement

**What that means for you:** the configs will load. The runtime behaviour — actual sampling rates, real memory pressure, Tempo's block flush timing — is described from the upstream source and docs, and the exercises are designed so you **observe** it rather than trust me.

---

## Companion reading

| Lab | Read first |
|---|---|
| 01 | [`../11-collector.md`](../11-collector.md), [`../16-troubleshooting.md`](../16-troubleshooting.md) |
| 02 | [`../09-sdks-and-instrumentation.md`](../09-sdks-and-instrumentation.md), [`../03-context-and-propagation.md`](../03-context-and-propagation.md), [`../13-backends.md`](../13-backends.md) |
| 03 | [`../10-sampling.md`](../10-sampling.md) |
| 04 | [`../06-metrics.md`](../06-metrics.md), [`../14-scale-cost-and-cardinality.md`](../14-scale-cost-and-cardinality.md) |
| 05 | [`../07-logs.md`](../07-logs.md), [`../05-traces.md`](../05-traces.md) |
| 06 | [`../12-collector-in-kubernetes.md`](../12-collector-in-kubernetes.md) |

Related folders in this workspace: **`../Monitoring and Alerting/`** (Prometheus 3.14 / Alertmanager 0.34 / Grafana 13, with its own runnable labs) and **`../Interview Questions/`** (22 topics at three difficulty levels).

→ Back to [`../README.md`](../README.md)
