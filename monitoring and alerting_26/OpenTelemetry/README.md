# OpenTelemetry — the complete working folder

Everything here is written against **OpenTelemetry Collector `v0.161.0` (core `v1.67.0`, released 2026-09-14)**, verified by downloading the real `otelcol-contrib` binary and running `validate` against every configuration in this folder. **Every YAML config in `labs/` has been machine-validated** — see [`labs/README.md`](labs/README.md).

> **Why that matters:** OpenTelemetry ships a minor release every two weeks, and v0.161.0 contains a **component rename to `lower_snake_case`** that breaks configs copy-pasted from 2023–2025 blog posts. Stale snippets are the #1 reason people's Collector won't start. This folder uses names verified against the actual binary.

---

## Versions verified for this folder

| Component | Version | Notes |
|---|---|---|
| **opentelemetry-collector (core)** | **v1.67.0** | Stable surface. Released 2026-09-14 |
| **opentelemetry-collector-contrib** | **v0.161.0** | Biweekly; next is v0.162.0 on 2026-09-28 |
| **OTLP specification** | **1.11.0** | Stable for traces/metrics/logs; **development** for profiles |
| **Semantic conventions** | **v1.44.0** | v1.42.0 moved `gen_ai.*` to its own repo; v1.43.0 graduated K8s + container-registry resource attributes to stable |
| **Specification** | 1.5x series | 1.54.0 (Feb 2026) **deprecated the Jaeger propagator** and made propagator implementation optional |
| **Declarative configuration** | **v1.0.0 — stable (Mar 2026)** | `OTEL_CONFIG_FILE` replaces `OTEL_EXPERIMENTAL_CONFIG_FILE` |
| **Profiles signal** | **Public alpha (Mar 2026)** | Collector pipelines gated behind `service.profilesSupport` |
| **CNCF status** | **Graduated — 21 May 2026** | Same tier as Kubernetes and Prometheus |
| opentelemetry-java | v1.66.0 | java-contrib v1.55.0 |
| opentelemetry-java-instrumentation (agent) | **2.31.x** | Monthly releases |
| opentelemetry-python | **1.44.0 / 0.65b0** | Stable / experimental tracks |
| opentelemetry-go | **v1.47.0-rc.1** | **Logs API+SDK at release candidate** — traces & metrics stable, logs not yet |
| opentelemetry-js | **2.9.0** (+ experimental 0.220.0) | SDK 2.x: stable ≥2.0.0, unstable ≥0.200.0 |
| Go compile-time instrumentation | **v1 (Jul 2026)** | Zero-code Go instrumentation finally exists |
| Helm: `opentelemetry-collector` | chart 0.172.0 | |
| Helm: `opentelemetry-operator` | chart 0.122.0 / app v0.158.0 | |
| Helm: `opentelemetry-target-allocator` | chart 0.158.0 | Part of the Operator project |
| Helm: `opentelemetry-kube-stack` | chart 0.20.5 | The batteries-included distribution |

**What's actually inside `otelcol-contrib` v0.161.0** (counted from the binary's own `components` output):
**108 receivers · 33 processors · 48 exporters · 13 connectors · 40 extensions · 9 config providers.**

---

## ⚠️ The v0.161.0 component rename — read this first

Collector components were renamed to consistent `lower_snake_case`. **The old names still work as deprecated aliases**, so existing configs don't break — but new configs should use the new names, and the `components` command now *only* lists the new ones. This is the single most confusing thing about upgrading right now.

| Old name (still accepted, deprecated) | New canonical name |
|---|---|
| `loadbalancing` | **`load_balancing`** |
| `filelog` | **`file_log`** |
| `hostmetrics` | **`host_metrics`** |
| `kubeletstats` | **`kubelet_stats`** |
| `k8sobjects` | **`k8s_objects`** |
| `k8sattributes` | **`k8s_attributes`** |
| `resourcedetection` | **`resource_detection`** |
| `metricstransform` | **`metrics_transform`** |
| `cumulativetodelta` | **`cumulative_to_delta`** |
| `prometheusremotewrite` | **`prometheus_remote_write`** |
| `spanmetrics` (connector) | **`span_metrics`** |
| `servicegraph` (connector) | **`service_graph`** |
| `sqlquery` | **`sql_query`** |
| `tcplog` / `udplog` | **`tcp_log`** / **`udp_log`** |
| `otlpjson` | **`otlp_json_file`** |
| `fluentforward` | **`fluent_forward`** |
| `otlp` (exporter) | **`otlp_grpc`** |
| `otlphttp` (exporter) | **`otlp_http`** |

Two more that are **hard** breaks, not aliases:
- **`logging` exporter was removed in v0.111.0** (Oct 2024). Use **`debug`**. Any config or tutorial with `logging:` will not start.
- **`load_balancing` schema changed**: `routing_key` moved to the **top level**, and `protocol:` now accepts **only** `otlp` (the old `protocol: spanmetrics:` form is gone — it fails with `'protocol' has invalid keys: spanmetrics`).

```yaml
# WRONG (2023–2025 shape — fails on v0.161.0)
loadbalancing:
  protocol:
    spanmetrics:
      routing_key: traceID

# RIGHT (v0.161.0)
load_balancing:
  routing_key: "traceID"
  protocol:
    otlp:
      timeout: 1s          # NOTE: never set `endpoint` here — it's overridden
  resolver:
    dns: {hostname: otelcol-backend.observability.svc.cluster.local}
```

---

## Index

### Foundations
| # | File | Covers |
|---|---|---|
| 01 | [`01-fundamentals.md`](01-fundamentals.md) | What OTel actually is, project layout, the API/SDK/Collector split, distributions, why "instrument once export anywhere" is real |
| 02 | [`02-architecture-and-data-model.md`](02-architecture-and-data-model.md) | Resource, Scope, the three (four) data models, OTLP encoding, entities, and what makes OTLP different from Prometheus/Jaeger formats |
| 03 | [`03-context-and-propagation.md`](03-context-and-propagation.md) | Context propagation, propagators, W3C Trace Context, Baggage, cross-service and cross-language pitfalls |
| 04 | [`04-semantic-conventions.md`](04-semantic-conventions.md) | Semconv: stability levels, the V0→V1 migration, GenAI conventions, and how to not get broken by renames |

### The signals
| # | File | Covers |
|---|---|---|
| 05 | [`05-traces.md`](05-traces.md) | Spans, kinds, attributes, events, links, status, processors, exporters, span limits |
| 06 | [`06-metrics.md`](06-metrics.md) | Instruments, sync vs async, **delta vs cumulative temporality**, views, histograms, cardinality limits, exemplars |
| 07 | [`07-logs.md`](07-logs.md) | The logs bridge, log record model, trace correlation, why OTel doesn't replace your logger |
| 08 | [`08-profiles.md`](08-profiles.md) | The fourth signal: eBPF continuous profiling, alpha status, what works today and what doesn't |

### Instrumentation
| # | File | Covers |
|---|---|---|
| 09 | [`09-sdks-and-instrumentation.md`](09-sdks-and-instrumentation.md) | Auto vs manual, zero-code vs code-based, per-language deep dives (Go/Python/Java/JS/.NET), Go compile-time instrumentation |
| 10 | [`10-sampling.md`](10-sampling.md) | Head vs tail, parent-based, ratio, Collector `tail_sampling` policies, `load_balancing`, and the trade-offs that decide your cost |

### The Collector
| # | File | Covers |
|---|---|---|
| 11 | [`11-collector.md`](11-collector.md) | Receivers/processors/exporters/connectors/extensions/providers, pipelines, config loading, queues, retries, internal telemetry |
| 12 | [`12-collector-in-kubernetes.md`](12-collector-in-kubernetes.md) | Agent vs gateway, DaemonSet/Deployment/sidecar, the Operator, `Instrumentation` CRD, Target Allocator, RBAC |
| 13 | [`13-backends.md`](13-backends.md) | Prometheus/Tempo/Loki/Mimir, Jaeger, vendor OTLP endpoints, what each signal needs from storage |
| 14 | [`14-scale-cost-and-cardinality.md`](14-scale-cost-and-cardinality.md) | Cardinality control, `cardinality_guardian`, filtering, batching, memory limits, backpressure, cost modelling |
| 15 | [`15-security-and-governance.md`](15-security-and-governance.md) | TLS, auth extensions, PII redaction, the Collector as an attack surface, ownership and policy |
| 16 | [`16-troubleshooting.md`](16-troubleshooting.md) | "No data" decision tree, internal telemetry, `zpages`, `print-config`, dropped-data diagnosis |
| 17 | [`17-migration-and-adoption.md`](17-migration-and-adoption.md) | Migrating from Jaeger/Zipkin/Prometheus/Datadog, dual-shipping, rollout plans, org adoption |

### Labs
Six runnable labs — five `docker-compose` stacks plus one Kubernetes set. **Start at [`labs/README.md`](labs/README.md)**, which has the ordering guide by role, the verified image tags, and the consolidated list of gotchas every lab reproduces on purpose.

| Lab | What you build |
|---|---|
| [`labs/lab-01-collector-fundamentals`](labs/lab-01-collector-fundamentals/) | A running Collector: OTLP in, `debug` out, `span_metrics` + `count` connectors, internal telemetry scraped by Prometheus |
| [`labs/lab-02-instrumented-app`](labs/lab-02-instrumented-app/) | A FastAPI app instrumented with **zero code changes** → Collector → Tempo + Prometheus + Loki + Grafana, with working trace↔log↔metric links |
| [`labs/lab-03-sampling`](labs/lab-03-sampling/) | Head vs tail sampling **side by side, same code, same traffic**: keep 100% of errors and slow traces inside a bounded spans/s budget |
| [`labs/lab-04-metrics-and-prometheus`](labs/lab-04-metrics-and-prometheus/) | All four ingest paths (OTLP push, scrape, remote-write, Prometheus's own OTLP receiver), `delta_to_cumulative`, the name transformation, `span_metrics` vs Tempo's generator |
| [`labs/lab-05-logs-and-correlation`](labs/lab-05-logs-and-correlation/) | `filelog` receiver + stanza operators for an **uninstrumented** service, PII redaction you can verify, labels vs structured metadata, the full correlation triangle |
| [`labs/lab-06-kubernetes`](labs/lab-06-kubernetes/) | Two-tier fleet (agent DaemonSet + gateway StatefulSet), Operator `OpenTelemetryCollector`/`TargetAllocator`/`Instrumentation` CRs, `load_balancing` with the DNS resolver, and **12 alerts for the Collector itself** |

---

## The mental model (if you read nothing else)

```
┌─────────────────────────── your application ───────────────────────────┐
│  API (opentelemetry-api)          ← stable interfaces, no-op by default │
│  Instrumentation libs             ← HTTP/gRPC/DB/framework hooks        │
│  SDK  (opentelemetry-sdk)         ← sampling, batching, processors      │
│  Exporter (OTLP)                  ← serialises to protobuf, sends       │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │ OTLP/gRPC :4317  or  OTLP/HTTP :4318
                                   ▼
┌──────────────────────── OTel Collector (optional but recommended) ─────┐
│  receivers → processors → exporters          (pipelines per signal)     │
│  connectors let one pipeline feed another (spans → metrics)             │
│  extensions: health_check, zpages, pprof, auth, storage                 │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   ▼
        Prometheus / Tempo / Loki / Jaeger / Datadog / Honeycomb / …
```

**Four things people get wrong about this diagram:**

1. **The Collector is optional.** An SDK can export straight to a backend. You add a Collector for: sampling decisions that need the whole trace, PII redaction, fan-out to multiple backends, cardinality control, and to keep vendor endpoints out of application config.
2. **The API is separate from the SDK, deliberately.** A library author depends on `opentelemetry-api` only; if no SDK is installed it's a **no-op with near-zero cost**. That's why instrumenting libraries is safe.
3. **OTel is not a backend.** It produces and moves telemetry. It does not store, query, or alert. "We're using OpenTelemetry" and "we can see our traces" are two different statements.
4. **Instrumentation ≠ configuration.** Half of all OTel problems are configuration: wrong endpoint, wrong service name, propagator mismatch, temporality mismatch, missing resource detector.

---

## Learning paths

**I'm a backend developer (2 hours).** [`01`](01-fundamentals.md) → [`05`](05-traces.md) → [`09`](09-sdks-and-instrumentation.md) → [`04`](04-semantic-conventions.md) → [`labs/lab-02`](labs/lab-02-instrumented-app/).
You'll be able to instrument a service, name it correctly, and find its traces.

**I'm SRE / platform (6 hours).** [`01`](01-fundamentals.md) → [`11`](11-collector.md) → [`12`](12-collector-in-kubernetes.md) → [`10`](10-sampling.md) → [`14`](14-scale-cost-and-cardinality.md) → [`16`](16-troubleshooting.md) → labs 01, 03, 04, 06.
You'll be able to design, deploy, scale and debug a Collector fleet.

**I'm DevSecOps (3 hours).** [`15`](15-security-and-governance.md) → [`04`](04-semantic-conventions.md) → [`11`](11-collector.md) (auth extensions, queues) → [`14`](14-scale-cost-and-cardinality.md) → [`labs/lab-05`](labs/lab-05-logs-and-correlation/) (redaction).

**I'm preparing for interviews.** Read [`10`](10-sampling.md), [`06`](06-metrics.md) (temporality), [`11`](11-collector.md) (connectors, queues) and [`14`](14-scale-cost-and-cardinality.md) — these are where the senior-level trade-off questions live. Then cross-reference `../Interview Questions/10-Observability/README.md`.

---

## Conventions used in this folder

- **Configs are written for v0.161.0** with the new `lower_snake_case` component names. Where an old name still works, it's noted.
- `★` marks a section worth re-reading — it's where people lose hours.
- **"Verified"** means it was checked against the downloaded binary or an upstream release note, not recalled.
- Trade-offs are stated as *"X costs you Y; choose it when Z."* If a recommendation has no stated cost, treat it as opinion.

---

## Companion folders in this workspace

- **`../Monitoring and Alerting/`** — Prometheus 3.14 / Alertmanager 0.34 / Grafana 13 with runnable labs. This folder's [`13-backends.md`](13-backends.md) and [`labs/lab-04`](labs/lab-04-metrics-and-prometheus/) assume you can run those.
- **`../Interview Questions/10-Observability/`** — the interview-prep treatment of the same material.

---

*Verified 2026-09-17 against `otelcol-contrib v0.161.0` (downloaded from `opentelemetry-collector-releases`), upstream READMEs at tag `v0.161.0`, `opentelemetry.io/docs/specs/otlp` (1.11.0), and the `open-telemetry/semantic-conventions` release list (v1.44.0).*
