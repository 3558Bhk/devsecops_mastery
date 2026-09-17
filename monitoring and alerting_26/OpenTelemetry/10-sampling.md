# 10 · Sampling

The single highest-leverage cost control in tracing, and the one with the most non-obvious failure modes. Sampling decides **which traces you keep** — get it wrong and you either pay for data nobody reads, or you throw away the exact trace you needed during the incident.

Everything here is verified against **opentelemetry-collector-contrib v0.161.0**, including the `tail_sampling` processor README at that tag.

---

## 10.1 The two decisions

| | **Head sampling** | **Tail sampling** |
|---|---|---|
| **When decided** | At span creation, before anything is known | After the trace completes (or after a wait) |
| **Who decides** | The **SDK** (or the Collector's `probabilistic_sampler`) | The **Collector's `tail_sampling` processor** |
| **Information available** | Trace ID, parent's sampled flag, resource attributes | **The whole trace**: duration, status, all attributes, span count, which services were involved |
| **Can keep "interesting" traces?** | **No** — it can't know a trace will error or be slow | ★ **Yes — this is the entire point** |
| **Consistency across services** | **Automatic** — the root decides, everyone obeys via `traceparent` | Requires **all spans of a trace to reach one Collector instance** |
| **Cost** | Nearly zero | **Memory + latency**: spans are buffered while waiting |
| **Data loss on Collector failure** | None (decision already made) | **Buffered traces are lost** |
| **Cost savings** | Proportional to the sampling rate | Proportional, **but** you can keep 100% of errors and 5% of the boring traffic |

★ **The decisive difference:** head sampling must decide **before it knows whether the trace matters**. It cannot keep 100% of errors and 5% of successes — it can only keep 5% of everything, which means **95% of your errors are gone.**

Tail sampling inverts this: **keep everything interesting, sample the boring remainder.** That's why it's the right answer for almost every production tracing deployment with meaningful volume — and why it's an infrastructure component you have to design for, not a flag you flip.

---

## 10.2 Head sampling

### The samplers
| Sampler | Behaviour |
|---|---|
| `always_on` | Record and sample everything |
| `always_off` | Record nothing |
| `traceidratio` | Sample a percentage, decided by hashing the trace ID |
| **`parentbased_always_on`** | ★ **The default.** If there's a parent, obey its sampled flag; if it's a root, always sample |
| `parentbased_always_off` | Obey parent; roots never sampled |
| **`parentbased_traceidratio`** | ★ **What you actually want.** Obey parent; roots sampled at the ratio |

```bash
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1        # 10%
```

### Why `parentbased` is essential ★
Without it, each service independently decides. Service A samples a trace at 10%; service B, seeing the same trace, independently rolls and drops it 90% of the time. **You get fragments — a trace with the entry span and nothing else.**

`parentbased` makes the decision once, at the root, and propagates it in `traceparent`'s sampled bit. Everyone downstream obeys. **This is what makes head sampling produce complete traces rather than confetti.**

### How the ratio actually works
`traceidratio` hashes the trace ID and compares against the ratio. Because trace IDs are uniformly random, **the same percentage of traces is sampled regardless of traffic** — and critically, **the decision is stable**: the same trace ID always gets the same answer, everywhere, forever.

★ **This stability is why derived counts remain usable.** If you sample 10% of traces, you can multiply your span-derived request counts by 10 to estimate the true total — *provided the sampling is uniform and you know the rate*. Non-uniform sampling (tail sampling by interestingness) breaks that arithmetic, which is a real trade-off you accept deliberately.

### The honest limitations of head sampling
1. **You lose most of your errors.** At 10%, 90% of error traces are gone. Since errors are rare and are exactly what you look at, this is a bad trade.
2. **You lose most of your slow traces.** Same argument.
3. **You can't filter noise selectively.** Health checks and readiness probes get sampled at the same rate as checkout.
4. **A low rate makes exemplars useless** ([`06-metrics.md`](06-metrics.md)) — the `trace_id` on a metric bucket points at a trace you didn't keep.
5. **★ It can't account for what happens later.** A trace that starts fast and then hits a 30-second timeout downstream was sampled as if it were uninteresting.

**Where head sampling is genuinely right:** very high volume with tight budgets, dev/test environments, short-lived processes (Lambda, batch jobs — no Collector to buffer them), and as a **first reduction stage before tail sampling** (see the hybrid pattern in 10.5).

---

## 10.3 Tail sampling — the `tail_sampling` processor

**Stability:** Beta for traces. **Statefulness warning (from the upstream README, verbatim in intent):** *"The processor keeps spans in memory while it waits to make a sampling decision. All spans for a given trace must be sent to the same Collector instance."*

### Configuration, fully annotated

```yaml
processors:
  tail_sampling:
    # ---- decision timing ----
    sampling_strategy: trace-complete   # default. Alternative: span-ingest (see below)
    decision_wait: 10s                  # ★ default is 30s. Time before evaluating a trace
    decision_wait_after_root_received: 0s   # decide earlier once the ROOT span arrives (0 = disabled)

    # ---- memory ----
    num_traces: 100000                  # ★ default 50000. Circular buffer of traces held in memory
    expected_new_traces_per_sec: 1000   # default 0. Pre-sizes data structures
    maximum_trace_size_bytes: 0         # ★ immediately drop oversized traces to protect the system

    # ---- decision caches (both INACTIVE by default) ----
    decision_cache:
      sampled_cache_size: 500000        # remember "keep" decisions after span data is released
      non_sampled_cache_size: 500000    # remember "drop" decisions

    # ---- parallelism ----
    num_shards: 4                       # ★ default 1, max 256. Parallel event loops

    # ---- behaviour ----
    sample_on_first_match: false        # decide as soon as a policy matches
    drop_pending_traces_on_shutdown: false   # false = decide on partial data at shutdown

    # ---- the policies (REQUIRED; no default) ----
    policies:
      - name: keep-errors
        type: status_code
        status_code: {status_codes: [ERROR]}

      - name: keep-slow
        type: latency
        latency: {threshold_ms: 1000}          # upper_threshold_ms also available

      - name: drop-health-checks
        type: drop
        drop:
          drop_sub_policy:
            - name: health-paths
              type: string_attribute
              string_attribute:
                key: url.path
                values: [\/health, \/readyz, \/metrics]
                enabled_regex_matching: true

      - name: keep-critical-tenants
        type: string_attribute
        string_attribute:
          key: tenant.tier
          values: [enterprise, trial]

      - name: sample-the-rest
        type: probabilistic
        probabilistic: {sampling_percentage: 5}
```

### All sixteen policy types (v0.161.0)

| Policy | What it matches | Key config |
|---|---|---|
| **`always_sample`** | Everything | — |
| **`latency`** | Trace duration. ★ Computed as **earliest start → latest end, ignoring what happened in between** | `threshold_ms`, `upper_threshold_ms` |
| **`status_code`** | Span status | `status_codes: [OK, ERROR, UNSET]` |
| **`probabilistic`** | A percentage. **Hashes the trace ID with FNV-1a using `hash_salt`** | `sampling_percentage`, `hash_salt` |
| **`numeric_attribute`** | Numeric attribute in range | `key`, `min_value`, `max_value` |
| **`string_attribute`** | String attribute, exact or regex | `key`, `values`, `enabled_regex_matching`, `cache_max_size` |
| **`boolean_attribute`** | Boolean attribute | `key`, `value` |
| **`span_count`** | Total spans in the trace, inclusive range | `min_spans`, `max_spans` |
| **`rate_limiting`** | **Token bucket** on spans/second (`golang.org/x/time/rate`) | `spans_per_second`, `burst_capacity` |
| **`bytes_limiting`** | **Token bucket** on bytes/second | `bytes_per_second`, `burst_capacity` |
| **`trace_state`** | W3C `tracestate` value matches | `key`, `values` |
| **`trace_flags`** | Whether the sampled flag was set on **any** span in the trace | — |
| **`ottl_condition`** | Arbitrary OTTL boolean expressions over span and span-event contexts | `span: [...]`, `spanevent: [...]`, `error_mode` |
| **`and`** | Logical AND of sub-policies | `and.and_sub_policy: [...]` |
| **`not`** | Negation of one sub-policy | `not.not_sub_policy: {...}` |
| **`drop`** | Explicit drop | `drop.drop_sub_policy: [...]` |
| **`composite`** | ★ **Ordered policies with per-policy rate allocation** | `max_total_spans_per_second`, `policy_order`, `composite_sub_policy`, `rate_allocation` |

**`ottl_condition` note from upstream:** use the **path-based context names** (`span.attributes["http.status_code"]`, `resource.attributes["service.name"]`, `spanevent.name`, `scope.name`) rather than the older shorthand — *"It is highly recommended to use this new syntax to avoid breaking changes in the future."*

### The `composite` policy — budgeted sampling ★

This is the most powerful policy and the least used. It lets you say: *"I have a budget of N spans per second; spend it in this priority order."*

```yaml
- name: budgeted
  type: composite
  composite:
    max_total_spans_per_second: 1000
    policy_order: [errors, slow, enterprise-tenants, everything-else]
    composite_sub_policy:
      - {name: errors, type: status_code, status_code: {status_codes: [ERROR]}}
      - {name: slow, type: latency, latency: {threshold_ms: 2000}}
      - {name: enterprise-tenants, type: string_attribute,
         string_attribute: {key: tenant.tier, values: [enterprise]}}
      - {name: everything-else, type: always_sample}
    rate_allocation:
      - {policy: errors, percent: 40}              # 400 spans/s reserved for errors
      - {policy: slow, percent: 30}                # 300 spans/s for slow traces
      - {policy: enterprise-tenants, percent: 20}  # 200 spans/s for enterprise
      # remaining 10% (100 spans/s) flows to everything-else
```
**Why this matters:** without a budget, "keep 100% of errors" is unbounded — an incident that produces 100,000 errors/second produces 100,000 sampled traces/second and your backend dies **during the incident**, which is precisely when you need it. **`composite` gives you prioritised sampling under a hard ceiling.** That is the single most important tail-sampling feature for production reliability, and it's the answer to "what happens to your tracing during an incident?"

★ **Upstream's own guidance:** *"To ensure remaining capacity is filled use `always_sample` as one of the policies"* — put a catch-all last so unused budget isn't wasted.

### `rate_limiting` and `bytes_limiting` — token buckets
Both use `golang.org/x/time/rate`: a bucket refilled continuously at the configured rate, with `burst_capacity` allowing short bursts above the average. **`bytes_limiting` is the more useful one** because it bounds cost directly rather than count — a trace with 500 spans and a trace with 3 spans cost very differently.

### The policy decision flow ★

Each policy returns a decision, and the processor combines them:

1. **Any `drop` decision → the trace is NOT sampled.**
2. Any "inverted not sample" decision → NOT sampled. ***Deprecated***
3. **Any `sample` decision → the trace IS sampled.**
4. Any "inverted sample" decision with no "not sample" decisions → sampled. ***Deprecated***
5. **In all other cases → the trace is NOT sampled.**

★ **Rule 5 is the one that bites people: the default outcome is DROP.** If your policies don't match a trace, it's discarded. A `tail_sampling` configuration with only `keep-errors` and `keep-slow` policies **keeps nothing else** — no probabilistic baseline, no `always_sample` catch-all. Your "successful, fast" traces all vanish. That's sometimes what you want, but it's rarely what people intend.

**"Inverted" decisions** come from the `invert_match` option on string/numeric/boolean policies. They're **deprecated**; upstream says to use a `drop` policy (to explicitly not sample) or a `not` policy (to invert a decision) instead. There's a `processor.tailsamplingprocessor.disableinvertdecisions` gate to disable them ahead of removal. Exception: inside `and`/`composite`, results are simply sampled or not sampled.

### `sampling_strategy`: `trace-complete` vs `span-ingest`

| | **`trace-complete`** (default) | **`span-ingest`** |
|---|---|---|
| When evaluated | On the timer path, after `decision_wait` (or earlier with `decision_wait_after_root_received`) | **Each incoming batch, at ingest time**, without re-evaluating previous batches |
| Terminal outcomes | After the wait | **Finalise immediately** |
| Non-terminal outcomes | After the wait | Stay pending; finalised as **not sampled** during cleanup, without policy re-evaluation |
| Stateful policies | **Supported** | ★ **Rejected** |
| Memory pressure | Higher | Lower |
| Decision latency | Higher (`decision_wait`) | Lower |

★ **`span-ingest` is the low-latency, low-memory mode — but it rejects stateful policies.** If you need `latency` (which requires knowing the whole trace's duration) or `span_count`, you need `trace-complete`. Choose based on whether your policies need the complete trace.

### `num_shards` — parallelism, and its subtleties

Traces are routed to shards by **a hash of the trace ID**, so all spans of a trace always land on the same shard. Shards run as parallel event loops, reducing contention between ingestion and decision evaluation under high load.

★ **The arithmetic that will surprise you:**
- `num_traces`, `expected_new_traces_per_sec`, `decision_cache` sizes, and **per-second rate limits** in `rate_limiting`, `bytes_limiting` and composite `max_total_spans_per_second` are **divided evenly across shards**.
- **`burst_capacity` is NOT divided** — because it also caps the size of a single trace that can pass a limiter, and each trace is evaluated whole on one shard. **Consequence: aggregate burst allowance scales with `num_shards`.**
- Because each shard enforces its share independently (with a minimum of 1 per shard), **enforcement is approximate: limits smaller than `num_shards` can be exceeded in aggregate**, and a shard can reach its share of `num_traces` before the aggregate does.
- ★ **`num_shards > 1` is not supported together with `tail_storage`.**

**Practical guidance:** shard when `decision_timer_latency` is high (see 10.6) or CPU contention between ingest and evaluation is visible. Don't shard to get a higher rate limit — divide the limit correctly instead, and remember burst scales.

---

## 10.4 Scaling tail sampling across a fleet ★

**The requirement:** all spans of one trace must reach the same Collector instance. Random load balancing breaks this, and the failure is *partial traces and wrong decisions* — not an error.

**The recommended architecture (upstream's own guidance): two layers of Collectors.**

```
      apps ──OTLP──▶ ┌─────────────────────────────────┐
                     │  LAYER 1: agent/gateway          │
                     │  - receives from apps            │
                     │  - basic validation, batching    │
                     │  - load_balancing exporter       │
                     │    routing_key: traceID          │
                     └───────────────┬─────────────────┘
                                     │  consistent hashing by traceID
                     ┌───────────────▼─────────────────┐
                     │  LAYER 2: tail-sampling tier     │
                     │  - tail_sampling processor       │
                     │  - enrichment, redaction         │
                     │  - export to backends            │
                     └─────────────────────────────────┘
```

```yaml
# Layer 1
exporters:
  load_balancing:
    routing_key: "traceID"          # ★ top-level in v0.161.0
    protocol:
      otlp:
        timeout: 1s
        sending_queue: {enabled: true}
    resolver:
      dns: {hostname: otelcol-tailsampling-headless.observability.svc.cluster.local}
      # or k8s: {service: otelcol-tailsampling-headless.observability}
      # or static: {hostnames: [c1:4317, c2:4317, c3:4317]}
      # or aws_cloud_map: {namespace: ..., service_name: ...}
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [load_balancing]
```

★ **Upstream explicitly recommends two layers over one layer with two pipelines:** *"While it's technically possible to have one layer of collectors with two pipelines on each instance, we recommend separating the layers in order to have better failure isolation."* The reasoning: a `tail_sampling` instance that OOMs (it holds traces in memory) shouldn't also be the thing receiving from your applications. Separate the memory-hungry stateful tier from the stateless ingress tier.

**The `k8s` resolver specifics** (from the exporter README):
- Requires the Service to be **headless**, and for `return_hostnames` to work it must point at a **StatefulSet** via `.spec.serviceName`.
- ★ **RBAC: the Collector's service account must be able to `get`, `list`, and `watch` `discovery.k8s.io/v1` `EndpointSlice` objects in the target namespace.** Otherwise the resolver cache stays empty and the exporter logs `couldn't find the exporter for the endpoint ""`.
- Endpoints with `conditions.ready` explicitly `false` are excluded. An endpoint with **no** ready condition is treated as ready (per the API contract). If your Service has `publishNotReadyAddresses: true`, `ready` is forced `true` and this filtering doesn't apply.
- `timeout` defaults to **1m** for k8s, versus **1s** for dns. The k8s resolver updates faster than DNS.

**Topology-change behaviour:** when the backend list changes, roughly **R/N** of routes get rerouted, where R = total routes and N = total backends. **More backends = less disruption.** If routing stability matters and your backend list changes often, add the **`groupbytrace` processor** before `load_balancing` — it dispatches traces atomically, so the same backend decision is made for the trace as a whole.

---

## 10.5 The `probabilistic_sampler` processor vs the `probabilistic` policy ★

Both sample a configured percentage. Upstream gives an explicit rule of thumb — and it's worth following exactly:

| Situation | Use | Why |
|---|---|---|
| **Not already running `tail_sampling`** | The **`probabilistic_sampler` processor** | *"Running the probabilistic sampling processor is more efficient than the tail sampling processor. The probabilistic sampling policy makes decisions based upon the trace ID, so waiting until more spans have arrived will not influence its decision."* — i.e. it's stateless, so don't pay for statefulness you don't need |
| **Already running `tail_sampling`** | The **`probabilistic` policy inside it** | *"You are already incurring the cost of running the tail sampling processor, adding the probabilistic policy will be negligible. Additionally, using the policy within the tail sampling processor will ensure traces that are sampled by other policies will not be dropped."* |

★ **That second reason is the subtle and important one.** If you chain `probabilistic_sampler` → `tail_sampling` as separate processors, the probabilistic processor drops 90% of traces **before** `tail_sampling` ever sees them — **including 90% of your errors.** Your "keep all errors" policy is defeated by an upstream processor. **Put probabilistic sampling inside the tail-sampling policy list so the keep-rules are evaluated first.**

**Stability:** `probabilistic_sampler` is **Beta for traces, Alpha for logs**.

### The hybrid pattern — and how to do it correctly
Reduce volume cheaply before the expensive tier, **without breaking interestingness-based sampling**:

```
apps → SDK head-samples at 100% (no reduction)
     → Layer 1 Collector: memory_limiter, filter out health checks, batch
     → load_balancing by traceID
     → Layer 2 Collector: tail_sampling with composite budget
     → backends
```
★ **Do not head-sample at the SDK if you intend to tail-sample for interestingness** — you'd discard errors before anyone could evaluate them. If you *must* reduce at the SDK (extreme volume, no Collector capacity), sample **high** (50–100%) at the SDK and do the real reduction in `tail_sampling`.

**Where SDK head-sampling IS the right answer:** Lambda and other short-lived processes with no Collector to buffer them; dev/test; and services whose traces you've decided are low-value by policy.

---

## 10.6 Monitoring tail sampling — the metrics you must watch ★

`tail_sampling` drops data by design and by accident. Both look identical unless you measure. Verified metric names from the v0.161.0 README:

| Metric | Meaning | Action |
|---|---|---|
| **`otelcol_processor_tail_sampling_sampling_trace_dropped_too_early`** | A trace was evicted from the `num_traces` circular buffer **before its decision was made** | ★ **Alert on this.** Increase `num_traces` or decrease `decision_wait` (both cost memory) |
| **`otelcol_processor_tail_sampling_sampling_trace_removal_age`** | Histogram of how long traces stay in the buffer | Compute **p1** and compare to `decision_wait`. *"Values close to `decision_wait` are at risk of being dropped if trace volume increases"* — this is your early warning |
| **`otelcol_processor_tail_sampling_sampling_decision_timer_latency`** | Latency of sampling a batch and passing it downstream | ★ *"A latency exceeding 1 second can delay sampling decisions beyond `decision_wait`, increasing the chance of traces being dropped before sampling."* **Upstream therefore recommends consuming this component's output with components that are fast or trigger asynchronous processing** — i.e. don't put a slow exporter directly after `tail_sampling` |
| **`otelcol_processor_tail_sampling_sampling_late_span_age`** | Histogram of spans arriving after their trace's decision | See the late-span analysis below |
| **`otelcol_processor_tail_sampling_global_count_traces_sampled`** | Overall sampled fraction | `{sampled="true"} / total` = your real sampling rate |
| **`otelcol_processor_tail_sampling_count_traces_sampled{decision,policy}`** | Per-policy, per-decision counts | ★ Which policy is doing the work |
| **`sampling_policy_evaluation_error`** | A policy threw an error while evaluating | **Alert on this** — a broken OTTL condition silently changes your sampling |

**Ready-made queries:**
```promql
# Actual sampled fraction
otelcol_processor_tail_sampling_global_count_traces_sampled{sampled="true"}
  / otelcol_processor_tail_sampling_global_count_traces_sampled

# How often each policy votes to sample
sum(otelcol_processor_tail_sampling_count_traces_sampled{decision="sampled"}) by (policy)
  / sum(otelcol_processor_tail_sampling_count_traces_sampled) by (policy)

# How often each drop policy votes to drop
sum(otelcol_processor_tail_sampling_count_traces_sampled{decision="dropped"}) by (policy)
  / sum(otelcol_processor_tail_sampling_count_traces_sampled) by (policy)

# Percentage of spans arriving late (needs the metricstatcountspanssampled gate)
otelcol_processor_tail_sampling_sampling_late_span_age{le="+Inf"}
  / otelcol_processor_tail_sampling_count_spans_sampled
```
★ **Upstream's caveat on per-policy metrics:** *"a policy voting to sample the trace does not guarantee sampling; an 'inverted not sample' or 'drop' decision from another policy would still discard the trace."* So per-policy sample rates don't sum to your actual sampling rate.

### Late-arriving spans — three scenarios ★

A span is "late" if it arrives **after its trace's sampling decision was made**. Late spans can cause **different sampling decisions for different parts of the same trace** — i.e. a partial trace in your backend.

| Scenario | Condition | Behaviour |
|---|---|---|
| **1** | The decision is still in the `num_traces` circular buffer | Late spans **inherit the existing decision** and don't influence it |
| **2** | ★ **Default (no decision cache configured)** — the decision has left the buffer | The processor acts as if it **never saw the trace**: late spans are buffered for `decision_wait` and **a new, independent decision is made** |
| **3** | `decision_cache` is configured | A "keep" decision caches the trace ID, so the processor **remembers** even after releasing the span data — until cache eviction |

★ **Scenario 2 is why `decision_cache` exists and why its defaults are dangerous.** With `sampled_cache_size: 0` (the default), a trace whose spans arrive over more than `decision_wait + buffer-residency` gets **split into two independent sampling decisions** — you may keep part of it and drop the rest. **Configure the decision caches, and set them much larger than `num_traces`**, exactly as upstream advises: *"configure this as much greater than `num_traces` so decisions for trace IDs are kept longer than the span data for the trace."*

**Causes of lateness:** long-running traces exceeding `decision_wait`, clock skew, retries, backpressure upstream, slow exporters, async work (a span emitted minutes after the request completed). **Visualise `late_span_age` as a histogram to see how much lateness you could eliminate by increasing `decision_wait`.**

### Tracking which policy kept a trace
Enable `processor.tailsamplingprocessor.recordpolicy` (**off by default**) and each sampled span gets:

| Attribute | Present when |
|---|---|
| **`tailsampling.policy`** | Always — the configured name of the policy that sampled the trace (unless sampled by the decision cache) |
| **`tailsampling.composite_policy`** | When a composite policy was used — the sub-policy name |
| **`tailsampling.cached_decision`** | When a decision cache was used — whether the trace was sampled from cache |

★ **This is worth enabling in production.** It answers "why do we have this trace?" and "is our error policy actually firing?" — questions that are otherwise unanswerable, and which matter enormously when someone asks why a specific incident trace is missing.

### Feature gates (all verified from v0.161.0 `--help`)

| Gate | Default | Effect |
|---|---|---|
| `processor.tailsamplingprocessor.usetracestate` | **off** | `probabilistic`/`rate_limiting`/`bytes_limiting` consume and rewrite W3C tracestate probability info instead of hashing locally. ★ **Do not combine with `sample_on_first_match`** — stopping at the first match can skip a later policy that would report a less strict threshold, throwing off downstream adjusted counts |
| `processor.tailsamplingprocessor.recordpolicy` | **off** | Adds the `tailsampling.*` attributes above |
| `processor.tailsamplingprocessor.tailstorageextension` | **off** | Use a `TailStorage` extension instead of in-memory. ★ **Under active development; if `tail_storage` is configured while the gate is off, validation fails and the Collector returns an error** |
| `processor.tailsamplingprocessor.metricstatcountspanssampled` | **off** | Enables `count_spans_sampled` (needed for the late-span percentage query) |
| `processor.tailsamplingprocessor.metricstatcountbytessampled` | **off** | Enables bytes-sampled counting |
| `processor.tailsamplingprocessor.disableinvertdecisions` | **off** | Makes `invert_match` produce Sampled/NotSampled instead of the deprecated InvertSampled/InvertNotSampled |

**`tail_storage`** is the direction of travel for the memory problem: spill pending traces to disk instead of RAM. It's experimental, gated, and **incompatible with `num_shards > 1`**.

★ **Schema gotcha — verified against v0.161.0 source and binary.** `tail_storage` takes a **component-ID string naming a storage extension**, *not* a nested map:

```yaml
extensions:
  file_storage:
    directory: /var/lib/otelcol
    create_directory: true        # ★ without this, validate fails if the path is missing
processors:
  tail_sampling:
    tail_storage: file_storage    # ★ correct — an extension ID
    # tail_storage: {kind: file, directory: /tmp/x}   # ✗ WRONG
    policies: [{name: a, type: always_sample}]
service:
  extensions: [file_storage]      # ★ the extension must also be started here
  pipelines:
    traces: {receivers: [otlp], processors: [tail_sampling], exporters: [debug]}
```
Write the map form and you get `'tail_storage' has invalid keys: directory, kind` — **even with the feature gate enabled**, which sends people hunting for the gate when the schema is the actual problem. The source declares it as `TailStorageID *component.ID`.

**The two validation errors, verbatim:**
```
processors::tail_sampling: num_shards greater than 1 is not supported with tail_storage
processors::tail_sampling: num_shards (999) must not exceed 256
```
And the *reason* upstream gives for the shard conflict, which is worth knowing: *"The TailStorage contract makes the caller responsible for serializing access, which multiple shard event loops cannot guarantee for a shared extension instance. **Sharding support belongs in the storage layer.**

---

## 10.7 Sizing tail sampling — the arithmetic

Memory ≈ `num_traces × average_trace_size`. Decide both deliberately.

```
Given:      5,000 traces/sec, average 20 spans/trace, ~500 bytes/span
            → average trace ≈ 10 KB
            → decision_wait 10s → ~50,000 traces in flight
            → memory ≈ 50,000 × 10 KB = 500 MB   (plus caches, plus overhead)

Set:        num_traces: 100000        (2× headroom over the 50k estimate)
            expected_new_traces_per_sec: 5000
            maximum_trace_size_bytes: 5242880   (5 MB — protect against one huge trace)
            decision_cache: {sampled_cache_size: 500000, non_sampled_cache_size: 500000}
                                        ↑ ~10× num_traces, per upstream guidance
            memory_limiter: {limit_percentage: 80, spike_limit_percentage: 25}
            container memory limit: ≥ 2 GB      (buffer + caches + Go runtime + headroom)
```

★ **The three sizing rules:**
1. **`num_traces` ≥ `traces_per_second × decision_wait` × 2.** Below that, you evict before deciding and lose data silently.
2. **`decision_cache` sizes ≫ `num_traces`** (~10×), or late spans trigger independent re-decisions (Scenario 2 above).
3. **`memory_limiter` must be configured and first in the pipeline**, with a container limit that leaves real headroom. A tail-sampling Collector that OOMs loses every buffered trace — **and it will OOM during the incident that generated the traces**, because that's when volume spikes.

**Reducing `decision_wait`** lowers memory and latency but increases the chance that spans of a long trace haven't arrived yet → more late spans → more partial traces. **It's a direct trade between memory and completeness.** For systems with long-running or async work, 10–30 s is common; for request/response services, 5–10 s often suffices.

---

## 10.8 Sampling and cost — what you actually save

| Strategy | Cost | What you lose |
|---|---|---|
| No sampling | 100% | Nothing, and a large bill |
| Head 10% | ~10% | **90% of your errors and slow traces** |
| Tail: 100% errors + 100% slow (>1s) + 5% rest | ~10–20% typically | Most successful fast traces — which you almost never look at |
| Tail with `composite` budget | **Hard ceiling** | Prioritised: errors first, then slow, then the rest |

★ **The key insight:** with tail sampling, **cost and value decouple.** Head sampling ties them together — you pay proportionally and lose proportionally, including the valuable tail. Tail sampling lets you pay ~15% and keep ~100% of what you'd actually look at.

**But you lose uniformity**, which means:
- **Span-derived counts can't simply be multiplied up.** A 5% probabilistic sample of *boring* traces plus 100% of errors is not a uniform sample. **Request-rate metrics must come from metrics, not from counting spans.** This is the strongest argument for emitting real metrics alongside traces rather than deriving everything from `span_metrics`.
- **Alerting on trace-derived signals is unreliable.** Alert on metrics; investigate with traces.

**And the incident-time behaviour:** during a SEV1, error volume explodes. Without a `composite` budget or `bytes_limiting`, your "keep 100% of errors" policy can overwhelm the Collector and the backend **exactly when you need them**. ★ **This is the question to ask in any interview or design review: "what happens to your tracing pipeline during an incident?"** The good answer names a hard ceiling with priorities.

---

## 10.9 Sampling other signals

| Signal | Sampling support | Notes |
|---|---|---|
| **Traces** | Mature | Everything above |
| **Logs** | ★ `probabilistic_sampler` is **Alpha for logs** in v0.161.0 | Sample DEBUG, never ERROR. Prefer filtering by severity and deduplicating (`log_dedup`) over sampling |
| **Metrics** | **Not sampled** — but **cardinality is the equivalent control** | You don't sample a metric; you reduce its attribute dimensions. See [`06-metrics.md`](06-metrics.md) |
| **Profiles** | Sampling is inherent — profiles *are* sampled stacks | Control via sample rate and duration, not a policy |

★ **The category error to avoid:** "we sample metrics at 10%" is meaningless. A metric is an aggregate; sampling aggregates produces wrong aggregates. What you control for metrics is **cardinality** (how many streams) and **interval** (how often). Those are the metrics analogue of a sampling rate, and they behave completely differently.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Head-sampling at 10% with no tail sampling | **90% of your errors are gone** — and errors are the only traces you look at |
| `traceidratio` without `parentbased` | Fragmented traces; each service decides independently |
| `tail_sampling` policies with no catch-all | ★ **Default outcome is DROP.** Everything unmatched vanishes |
| `probabilistic_sampler` chained *before* `tail_sampling` | Drops errors before the keep-rules ever see them. **Put probabilistic inside the policy list** |
| `tail_sampling` on one Collector tier receiving directly from apps | An OOM in the memory-hungry tier takes down your ingestion. **Use two layers** |
| Random load balancing into a tail-sampling fleet | Spans of a trace split across instances → wrong decisions, partial traces |
| Default `decision_cache` (both sizes 0) | **Late spans get a fresh independent decision** → partial traces. Set caches ≫ `num_traces` |
| `num_traces` below `traces/sec × decision_wait` | Silent eviction before decision. Watch `sampling_trace_dropped_too_early` |
| No `maximum_trace_size_bytes` | One enormous trace (a 6-hour batch job) can blow the buffer |
| No `composite` budget | **"Keep 100% of errors" kills your backend during the incident** — exactly when you need it |
| A slow exporter directly after `tail_sampling` | ★ Decision timer latency >1 s pushes decisions past `decision_wait` → more drops |
| `sample_on_first_match` with `usetracestate` | Skips later policies that would report a less strict threshold → wrong adjusted counts downstream |
| `num_shards > 1` with `tail_storage` | Unsupported — validation fails |
| Assuming per-policy sample rates sum to your sampling rate | A `drop` from another policy can still discard a trace a policy voted to keep |
| Deriving request-rate metrics from sampled spans | Non-uniform sampling breaks the arithmetic. **Emit real metrics** |
| "Sampling metrics at 10%" | Category error. Metrics are controlled by **cardinality and interval** |
| No `memory_limiter` first on a tail-sampling Collector | It will OOM, and it will do so during the volume spike that matters |
| Not enabling `recordpolicy` | You can never answer "why do we have this trace?" or "why is this one missing?" |

---

## Rapid recall

1. **Head sampling decides before it knows if the trace matters; tail sampling decides after.** Head can't keep 100% of errors — at 10% you lose 90% of them, and errors are the only traces you look at. **That's the entire argument for tail sampling.**
2. **Always use `parentbased_*` samplers.** The root decides once and propagates via `traceparent`'s sampled bit; without it each service rolls independently and you get fragments.
3. **Head sampling's one real advantage:** uniform sampling means derived counts stay arithmetically valid. Tail sampling breaks that — **so emit real metrics and never derive request rate from sampled spans.**
4. ★ **`tail_sampling`'s default outcome is DROP** ("in all other cases, the trace is NOT sampled"). A policy list of only keep-rules discards everything else. Add a `probabilistic` baseline or `always_sample` catch-all.
5. **Sixteen policy types**: `always_sample`, `latency`, `status_code`, `probabilistic` (FNV-1a hash of trace ID), `numeric_attribute`, `string_attribute` (exact/regex), `boolean_attribute`, `span_count`, `rate_limiting` and `bytes_limiting` (token buckets), `trace_state`, `trace_flags`, `ottl_condition`, and the combinators **`and` / `not` / `drop` / `composite`**.
6. ★ **`composite` is the most important policy for production**: `max_total_spans_per_second` + `policy_order` + `rate_allocation` gives you **prioritised sampling under a hard ceiling**. Without it, "keep 100% of errors" overwhelms your backend *during the incident*. Put a catch-all last to fill unused budget.
7. **Key config:** `sampling_strategy` (`trace-complete` default vs `span-ingest`, which **rejects stateful policies**), `decision_wait` (**default 30 s**), `decision_wait_after_root_received`, `num_traces` (**default 50 000**, circular buffer), `maximum_trace_size_bytes`, `decision_cache` (**both default 0 = inactive**), `num_shards` (default 1, max 256), `sample_on_first_match`, `drop_pending_traces_on_shutdown`.
8. ★ **`num_shards` divides `num_traces`, cache sizes and per-second rate limits evenly — but NOT `burst_capacity`**, so aggregate burst scales with shards. Enforcement is approximate for limits smaller than `num_shards`. **Incompatible with `tail_storage`.**
9. ★ **Two Collector layers is upstream's explicit recommendation**: Layer 1 does ingress + `load_balancing` with `routing_key: "traceID"`; Layer 2 does `tail_sampling`. *"Better failure isolation"* — the memory-hungry stateful tier shouldn't also be your ingestion tier. `k8s` resolver needs a headless Service, **EndpointSlice get/list/watch RBAC** (else `couldn't find the exporter for the endpoint ""`), and `publishNotReadyAddresses` changes ready-filtering. Add `groupbytrace` if the backend list churns.
10. ★ **`probabilistic_sampler` processor vs the `probabilistic` policy — upstream's rule:** not already running `tail_sampling` → use the **processor** (stateless, more efficient). Already running it → use the **policy** (negligible extra cost, **and it guarantees other policies' keeps aren't dropped upstream**).
11. **Metrics you must alert on:** `sampling_trace_dropped_too_early` (evicted before decision), `sampling_trace_removal_age` (**compare p1 to `decision_wait`** — closeness means you're at risk), `sampling_decision_timer_latency` (**>1 s pushes decisions past `decision_wait`; keep what follows `tail_sampling` fast**), `sampling_late_span_age`, `global_count_traces_sampled`, `count_traces_sampled{decision,policy}`, and `sampling_policy_evaluation_error`.
12. ★ **Late spans, three scenarios**: (1) decision still in buffer → inherited; (2) **default, no cache → treated as a brand-new trace, buffered again, and an INDEPENDENT decision made** — this is how traces get split; (3) decision cache → remembered. **Fix: set `decision_cache` sizes ≫ `num_traces`.**
13. **Enable `recordpolicy`** to get `tailsampling.policy`, `tailsampling.composite_policy` and `tailsampling.cached_decision` on sampled spans — the only way to answer "why do we have this trace / why is that one missing?"
14. **Sizing:** `num_traces ≥ traces_per_sec × decision_wait × 2`; caches ~10× `num_traces`; `memory_limiter` first with real container headroom; `maximum_trace_size_bytes` set. **A tail-sampling Collector OOMs during the incident that generated the traces.**
15. **Other signals:** logs sampling is **Alpha** (`probabilistic_sampler`) — prefer severity filtering and `log_dedup`; **metrics are never sampled** — cardinality and interval are the equivalent controls, and "sampling metrics" is a category error.

→ Next: [`11-collector.md`](11-collector.md)
