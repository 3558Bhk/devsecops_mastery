# 08 · Profiles — the Fourth Signal

**Status, verified:** OTLP marks profiles as **development**; the signal reached **public alpha in March 2026**; the Collector gates profiles pipelines behind the **`service.profilesSupport`** feature gate, which is **off by default in v0.161.0**. The Profiling SIG **advises against critical production workloads**, and production-ready backends have not yet emerged.

**So: evaluate it, don't depend on it.** This file tells you what's real today, what the design is, and how to trial it safely.

---

## 8.1 Why a profiles signal exists

The gap in the other three signals:

| Signal | Tells you | Does not tell you |
|---|---|---|
| Metrics | CPU is at 92%, p99 latency is 1.8 s | **Which function** is burning it |
| Traces | Request `abc123` spent 1.4 s in `inventory-service` | **What code** ran during those 1.4 s |
| Logs | Something threw an exception | Whether you have a silent CPU regression with no errors at all |
| **Profiles** | **`(*Store).resolvePricing` is 38% of on-CPU time, up from 4%** | — |

★ **The specific problem profiles solve that nothing else does:** a service that got **30% slower with no error, no new dependency, and no metric anomaly other than CPU**. That's a code-level regression — an accidental O(n²), a new serialization in a hot path, a lock held too long. Traces show *where in the call graph*; profiles show *which line of code*.

**The second thing it solves: cost attribution.** "Which service, endpoint or tenant is actually consuming our compute?" is answerable from profiles in a way that CPU-per-pod metrics never are, because profiles attribute CPU to **functions and call paths**, not to containers.

**The third: diff profiles.** Compare a profile before and after a deploy, and the regression is highlighted directly. This is the workflow that makes continuous profiling worth operating — it turns "we think this release is slower" into "this function is 9× hotter".

---

## 8.2 What shipped in the March 2026 alpha

Three artefacts:

### 1. The OTLP profiles data format
- A **deduplicated stack representation**. Function names, file paths and other repeated strings are **interned into a shared string dictionary per request** rather than repeated on every sample. That's roughly a **40% wire-size reduction** versus a naive encoding — significant, because profiles are sampled continuously across every process on a host.
- **Round-trips with pprof**, but ★ the SIG **deliberately abandoned the original goal of strict pprof wire compatibility** in favour of **convertibility** — the same approach used for the other signals. This has caused repeated breaking changes to the profiles section of the protocol, **while leaving the stable sections (traces, metrics, logs, resources) untouched**.
- OTLP 1.11.0 puts the HTTP path at literally **`/v1development/profiles`** and the request body at `ExportProfilesServiceRequest`. **The path name is the stability signal** — don't build a production dependency on it.
- `partial_success` includes **`rejected_profiles`**, consistent with the other signals.

### 2. Collector pipeline support
- Profiles have been receivable/processable/exportable since **v0.112.0**, behind the `service.profilesSupport` gate.
- **From v0.148.0**: a **`pprof` receiver** (confirmed present in v0.161.0), **Kubernetes metadata enrichment via the `k8sattributes` processor**, and **OTTL transforms for profile data** — meaning the `transform` processor's `profile` context works, so you can add `k8s.namespace.name`, redact, or drop profile data with the same tooling you use for everything else.
- v0.161.0 includes a fix to *"reference resource and scope attribute strings via the ProfilesDictionary string table when marshaling and unmarshaling OTLP profiles export requests"* — i.e. **the string-table implementation is still being actively worked on**.

### 3. The whole-system eBPF profiler ★
- **Donated by Elastic**, now ships as an **official Collector component**.
- **Zero-code and zero-redeploy**: it samples stacks **from the kernel side**, across **every process on the host**, with no SDK changes and no application cooperation.
- **Runtime support work** landed for **Go, Node.js (V8), Ruby, .NET 9 and 10**, and **initial BEAM (Erlang/Elixir)** coverage.

★ **This is the most important design property in the whole signal.** Compare with in-process profiling:

| | **In-process (SDK) profiler** | **Whole-system eBPF profiler** |
|---|---|---|
| Code changes | Required per application | **None** |
| Deploy | Required | **Not required** |
| Coverage | Only instrumented apps | **Every process on the host**, including third-party and system components |
| Overhead | In your app's runtime | Kernel-side sampling, isolated from the app |
| Language support | Per-language SDK maturity | Requires per-runtime unwinding support |
| Failure mode | Can affect your app | Runs outside; a profiler crash doesn't crash the app |
| Maturity | **SDK-level APIs are still ahead** (not shipped) | **Usable for evaluation today** |

**Practical consequence:** you can start evaluating profiles **without touching a single application**. Deploy the profiler on a non-critical Linux node, ship through a Collector, inspect locally. That's a genuinely low-risk trial, and it's why the SIG's recommended starting point is exactly that.

---

## 8.3 The data model

Profiles attach to the same **Resource → Scope → data** hierarchy as everything else (see [`02-architecture-and-data-model.md`](02-architecture-and-data-model.md)) — **which is what makes correlation with traces possible.** A profile sample carries the same `service.name`, `k8s.pod.name` and resource attributes as the spans from that process.

Conceptually, a profile contains:
- **Sampled stack traces** — the call path observed at each sample
- **Value types and values** — what's being measured: `cpu` (samples/nanoseconds), `alloc_space`/`alloc_objects` (bytes/count), `goroutines`, `mutex`, `block`
- **Time window** — the profile covers an interval, unlike a span which is an event
- **String dictionary** — interned names, the compression mechanism
- **Links to traces/spans** — so a hot function can be tied to the request that invoked it

**Correlation is the payoff.** A profile that says "`resolvePricing` is 38% of CPU" is useful. A profile where you can click that function and land on the traces that were in flight while it was hot, with the same `service.name` and `deployment.environment.name`, is a different class of tool.

**OTTL on profiles** means you can enrich and control them like any other signal:
```yaml
processors:
  transform/profiles:
    error_mode: ignore
    profile_statements:
      - context: resource
        statements:
          - set(attributes["deployment.environment.name"], attributes["env"]) where attributes["env"] != nil
      - context: profile
        statements:
          # example: drop profiles from test namespaces
          - delete_matching_keys(attributes, "^debug\\..*")
```

---

## 8.4 Configuring a profiles pipeline (validated against v0.161.0)

★ **The gate is mandatory.** Without it, the Collector refuses to start:
```
Error: service::pipelines: pipeline "profiles": profiling signal support is at alpha level,
gated under the "service.profilesSupport" feature gate
```
Verified message from `otelcol-contrib validate` in v0.161.0.

```yaml
receivers:
  otlp:
    protocols:
      grpc: {endpoint: 0.0.0.0:4317}
      http: {endpoint: 0.0.0.0:4318}
  pprof:                       # present in v0.161.0 — ingests pprof-format profiles
    # see the receiver README at your tag for collection settings

processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
  k8s_attributes:              # K8s metadata enrichment works for profiles (v0.148.0+)
    auth_type: serviceAccount
    extract:
      metadata: [k8s.namespace.name, k8s.pod.name, k8s.deployment.name, k8s.node.name]
  batch:
    timeout: 5s

exporters:
  otlp_http/profiles:
    endpoint: http://profiles-backend:4318
  debug:
    verbosity: basic           # ★ confirmed: `debug` accepts profiles
  file:
    path: /var/lib/otelcol/profiles.json   # ★ confirmed: `file` accepts profiles

service:
  pipelines:
    profiles:
      receivers: [otlp, pprof]
      processors: [memory_limiter, k8s_attributes, batch]
      exporters: [otlp_http/profiles]
```
```bash
# The gate must be enabled on the command line (or via the Helm chart's featureGates)
otelcol-contrib --config=/etc/otelcol/config.yaml --feature-gates=service.profilesSupport
```

**Which exporters accept profiles** — verified in v0.161.0 by `validate`:

| Exporter | Accepts profiles | Note |
|---|---|---|
| **`debug`** | ✅ | Confirmed valid — your first debugging tool |
| **`nop`** | ✅ | Confirmed valid. (v1.49.0 release notes explicitly added profiles support to `nop`) |
| **`file`** | ✅ | Confirmed valid with `path` set. **Best option for a trial** — inspect locally, no backend dependency |
| **`otlp` / `otlp_grpc`** | ✅ | Confirmed valid with `endpoint` set |
| **`otlp_http`** | ✅ | Confirmed valid with `endpoint` set |
| **`otelarrow`** | Present as receiver and exporter | The high-throughput Arrow encoding; ~80% compression claims |

★ **The trial pattern that costs nothing:** run the eBPF profiler on one non-critical node → Collector with `--feature-gates=service.profilesSupport` → **`file` exporter to a JSON file** → inspect. No backend, no cost, no production risk, and you learn what the data actually looks like before committing to a storage decision.

---

## 8.5 The honest assessment — what to do and when

### What's real today
- **The signal model and OTLP encoding exist and work.** You can receive, process (including K8s enrichment and OTTL), and export profiles in v0.161.0.
- **The eBPF profiler is zero-code and runs outside your applications.** Low-risk to trial.
- **Language coverage is meaningful**: Go, Node.js, Ruby, .NET 9/10, initial BEAM.
- **Correlation with the other signals works** because profiles share the Resource/Scope model.

### What is not ready
| Gap | Consequence |
|---|---|
| **SIG advises against critical production workloads** | Don't put it on the path that decides an incident |
| **No production-ready backends yet** | ★ **The real blocker.** You can produce profiles; storing, indexing, querying and diffing them at scale is where the ecosystem is still building. `file` export is a trial tool, not an answer |
| **OTLP profiles format is still changing** | Breaking changes have already happened (the pprof-compatibility reversal). Expect more |
| **SDK-level in-process profiling APIs are still ahead** | You can't yet instrument a specific code region on demand from application code the way you can with spans |
| **eBPF requires Linux, privileged access, and kernel version support** | A DaemonSet with elevated capabilities — a security review in its own right (see [`15-security-and-governance.md`](15-security-and-governance.md)) |
| **Symbol resolution for stripped/optimised binaries is imperfect** | Inlined functions and JIT'd code can produce confusing stacks. Go's compile-time instrumentation and .NET/JVM symbol handling differ |

### Recommended posture (2026)
1. **Trial it on non-critical nodes** with the `file` exporter. Cost: a few hours. Value: you'll know whether your stack's symbols resolve well enough to be useful — **which varies enormously by language and build flags, and which nobody can tell you in advance.**
2. **Do not make it a dependency.** No alerts, no incident-response steps, no capacity decisions based on profile data yet.
3. **Watch the backend story.** The gating factor is storage/query, not collection. When a backend you already run (Grafana Phlare/Pyroscope, Parca, ClickHouse-based stores, or your vendor) has credible OTLP profiles ingestion and diff views, that's when to reconsider.
4. **Budget for a security review** of the eBPF DaemonSet before promising anyone profiles. Kernel-level access is a bigger ask than an OTLP endpoint.
5. **If you need production profiling today**, use the mature per-runtime tools (Go `net/http/pprof`, JVM async-profiler, `py-spy`, Pyroscope/Parca agents) and plan to converge on OTLP profiles when the ecosystem lands. **Don't stall on the standard when a working tool exists.**

---

## 8.6 The overhead question

Continuous profiling's entire value proposition depends on overhead being low enough to leave on permanently.

| Mechanism | Typical overhead | Notes |
|---|---|---|
| **eBPF whole-system sampling** | **~1–3% CPU** | Kernel-side, fixed sampling rate, independent of app behaviour |
| JVM async-profiler | ~1–2% | Mature, well-understood |
| Go `runtime/pprof` CPU profile | ~1–5% | Higher if you also profile memory/allocations |
| `py-spy` | ~1–3% | Out-of-process, sampling |
| **Allocation/memory profiling** | ★ **Much higher** — 5–20%+ | Instrumenting every allocation is expensive. Sample it aggressively or leave it off |

★ **The asymmetry worth knowing: on-CPU sampling is cheap; allocation profiling is not.** A CPU profile at 100 Hz samples a fixed number of times per second regardless of what your app does. An allocation profile hooks allocation events, so its cost scales with your allocation rate — and allocation-heavy services (Go with lots of small objects, JVM with heavy GC) are exactly the ones where it hurts.

**Cost driver for storage:** sample rate × duration × number of processes × symbol-table size. The string dictionary helps a lot, but a host with 200 processes profiled continuously is still real volume. **Scope the trial to a few nodes and measure the actual bytes before extrapolating.**

---

## 8.7 Where this is heading

- **Beta, then GA** — the SIG frames 2026 as the **evaluation window**.
- **SDK-level in-process profiling APIs** — the ability to profile a chosen region on demand, from application code.
- **Backend implementations** — the gating factor. Teams building telemetry backends are explicitly encouraged to start implementing OTLP profiles ingestion now.
- **Better symbol resolution** across runtimes, particularly for JIT'd and heavily-inlined code.
- **Convergence with the eBPF instrumentation trend** — note that contrib v0.161.0 also ships an **`obi` receiver** (eBPF-based auto-instrumentation), which produces spans/metrics from kernel observation with zero code. Profiles and OBI share the same underlying technique, and together they point at a future where **a large fraction of telemetry requires no application changes at all**.

★ **The strategic read:** eBPF-based zero-code collection is the most consequential direction in OTel right now. It removes the adoption blocker — "we have 200 services and nobody will instrument them" — for a meaningful subset of telemetry. Profiles is the first signal to be built that way from the start; `obi` applies it to traces and metrics. Worth tracking even if you don't deploy either yet.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Building alerts or incident steps on profile data | **Alpha; SIG advises against critical production use** |
| Assuming a backend exists | ★ **Production-ready OTLP-profiles backends have not emerged.** Collection works; storage/query is the gap |
| Configuring a `profiles` pipeline without the feature gate | Collector refuses to start with a message naming the gate |
| Assuming pprof wire compatibility | **Deliberately abandoned** in favour of convertibility; the format has broken repeatedly |
| Deploying the eBPF profiler without a security review | It's a privileged kernel-level DaemonSet. That's a bigger ask than an OTLP port |
| Leaving allocation profiling on everywhere | 5–20%+ overhead, scaling with allocation rate. On-CPU sampling is cheap; allocation profiling isn't |
| Extrapolating storage cost from one node | Sample rate × duration × process count × symbol tables. Measure before scaling |
| Waiting for the standard instead of using working tools | Go `pprof`, async-profiler, `py-spy`, Pyroscope all work today |
| Ignoring symbol quality in your own builds | Stripped/optimised/inlined binaries produce confusing stacks. **Test your actual build, not a demo app** |

---

## Rapid recall

1. **Status: OTLP `development`; public alpha since March 2026; Collector gate `service.profilesSupport` OFF by default** (verified v0.161.0). SIG advises against critical production workloads. **Evaluate, don't depend.**
2. **The gap it fills:** metrics say CPU is high, traces say which request was slow, **neither says which function is responsible.** Also: cost attribution to functions rather than containers, and **diff profiles** across a deploy.
3. **Three artefacts shipped:** the OTLP profiles format (**shared string dictionary, ~40% wire reduction**, pprof-*convertible* not wire-compatible, HTTP path `/v1development/profiles`), Collector pipeline support (**v0.148.0+**: `pprof` receiver, `k8sattributes` enrichment, **OTTL on profiles**), and the **whole-system eBPF profiler donated by Elastic**.
4. ★ **The eBPF profiler is zero-code and zero-redeploy** — kernel-side sampling across **every process on the host**, outside your application. Runtimes covered: **Go, Node.js (V8), Ruby, .NET 9/10, initial BEAM.** That's why you can trial profiles **without touching an application**.
5. **Same Resource → Scope model as every other signal** — which is exactly what makes profile↔trace correlation work.
6. **Verified exporters accepting profiles:** `debug`, `nop`, `file`, `otlp`/`otlp_grpc`, `otlp_http`; `otelarrow` present. ★ **`file` export is the right trial pattern**: profiler on one non-critical node → Collector with the gate → JSON on disk. No backend, no cost, no risk.
7. **The real blocker is backends, not collection.** You can produce profiles today; storing, querying and diffing them at scale is where the ecosystem is still building. Watch for credible OTLP-profiles ingestion in the store you already run.
8. **Overhead: on-CPU sampling ~1–3%; allocation profiling 5–20%+** and scales with allocation rate. Leave CPU on, scope allocation profiling deliberately.
9. **If you need production profiling now**, use the mature per-runtime tools (Go `net/http/pprof`, async-profiler, `py-spy`, Pyroscope/Parca) and plan to converge. **Don't stall on a standard when a working tool exists.**
10. **Strategic direction:** zero-code eBPF collection is the most consequential trend in OTel — contrib v0.161.0 also ships the **`obi` receiver** (eBPF auto-instrumentation producing spans/metrics). Together they attack the real adoption blocker: "nobody will instrument 200 services".

→ Next: [`09-sdks-and-instrumentation.md`](09-sdks-and-instrumentation.md)
