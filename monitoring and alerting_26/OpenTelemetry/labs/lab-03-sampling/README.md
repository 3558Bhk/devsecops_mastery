# Lab 03 — Head vs Tail Sampling, Side by Side

**Goal:** see, with numbers, why tail sampling is worth a stateful Collector fleet. **Two apps run identical code and generate identical traffic.** The only difference is which sampling path they take.

**Time:** 45–60 minutes. **Prerequisites:** Docker, ~4 GB RAM. Lab 02 (this lab reuses its app image).

**Read [`../../10-sampling.md`](../../10-sampling.md) first.** It explains every number in the config; this lab shows you what happens when you get them wrong.

---

## The experiment

```
                 ┌─── :4317 ──▶ traces/head ──▶ probabilistic_sampler (10%) ──┐
  app-head ──────┤                                                            │
  (identical     └─── :4318 ──▶                        ┌──────────────────────┤
    code,                                                     span_metrics    ├──▶ SAME Tempo
    identical    ┌─── :4417 ──▶ traces/tail ──▶ tail_sampling (policies) ─────┤
    traffic) ────┤                                                            │
  app-tail ──────┴─── :4418 ──▶                        └──────────────────────┘
```

| | **Head path** | **Tail path** |
|---|---|---|
| Decision point | Before the trace is complete | After `decision_wait` (10 s) |
| Information available | **Nothing but the trace ID** | Errors, latency, attributes, span count |
| Keeps errors | ★ **~10% of them** | **100%** |
| Keeps slow traces | ★ **~10% of them** | **100%** |
| Cost | Near zero | Memory + CPU + a stateful fleet |
| Can express "keep if tenant == acme-debug" | **No** | **Yes** |

---

## Run it

```bash
cd labs/lab-03-sampling
docker compose up -d --build
docker compose ps
```

| URL | What |
|---|---|
| **http://localhost:3000** | Grafana → *OpenTelemetry Labs* → **Lab 03 — Head vs Tail Sampling** |
| http://localhost:3200 | Tempo |
| http://localhost:9090 | Prometheus |
| http://localhost:8888/metrics | ★ Collector sampling telemetry (`level: detailed` is required) |

```bash
docker compose logs -f collector | grep -i sampl
docker compose down -v
```

---

## Exercise 1 — The headline comparison

Wait ~3 minutes for data, then look at dashboard **panel 1: ERROR traces kept, by sampling path**.

Both apps produce the same errors (404s from `nonexistent-N`, 503s from `checkout` 1-in-5). **The tail line should be roughly 10× the head line.**

★ **That gap is every error you would have been unable to investigate.** Head sampling didn't choose to drop your errors — it *couldn't see them*. It decided at the root span, before any child had failed.

Confirm it directly in Tempo → Explore → search:
```
{ resource.service.name = "tail-sampled-service" && status = error }
{ resource.service.name = "head-sampled-service" && status = error }
```

**Now answer the question that actually matters:** in your estate, what fraction of incidents start with "show me an error trace"? That fraction is how much of your incident-response capability head sampling throws away.

---

## Exercise 2 — ★ Discover the default outcome is DROP

This is the single most dangerous default in the Collector.

Remove the `composite` policy (which contains the probabilistic baseline), keeping only `errors-status`, `slow`, `force-keep` and `tenant-debug`:

```bash
cp otel-collector-config.yaml /tmp/noBaseline.yaml
# delete the entire `- name: budget / type: composite` block from /tmp/noBaseline.yaml
docker run --rm -v /tmp:/cfg otel/opentelemetry-collector-contrib:0.161.0 \
  validate --config=/cfg/noBaseline.yaml && echo "VALIDATES CLEAN"
```

**It validates clean.** There is no warning. Now point a Collector at it and drive traffic:

★ **Every ordinary trace is dropped.** Not sampled-down — *dropped entirely*. Your error and slow-trace policies keep working perfectly, your dashboards look healthy, and you have lost 100% of your baseline visibility.

**Why:** from the README, the decision flow is that a policy returns sampled / not-sampled / inverted variants, and **"in all other cases" the trace is not sampled.** There is no implicit "keep the rest."

**The rule: a `tail_sampling` policy list must always end with a catch-all** — either `always_sample` (keep everything not otherwise handled) or a `composite` with a `probabilistic` baseline (keep a bounded share). This lab uses the second, which is what you want in production because it also enforces a budget.

---

## Exercise 3 — ★ Both decision caches default to 0 (inactive)

Set them to zero and watch partial traces appear:

```yaml
    decision_cache:
      sampled_cache_size: 0
      non_sampled_cache_size: 0
```
```bash
docker compose restart collector
```

**What happens, from the README's three late-span scenarios:**

| Scenario | Condition | Behaviour |
|---|---|---|
| **1** | Decision still in the `num_traces` buffer | Late spans **inherit** the decision — harmless |
| **2** | ★ **Default, no decision cache** | The component behaves as if it has **never seen the trace**. Late spans are buffered for `decision_wait` and get a **fresh, independent decision** |
| **3** | Decision cache configured | A "keep" trace ID is **cached**, so the decision is remembered even after span data is released |

★ **Scenario 2 is how you end up with partial traces and no explanation.** A trace's early spans were dropped by one decision; its late spans were kept by a *different* decision made minutes later. Tempo shows you a trace with a missing beginning, and nothing in your metrics says why.

**The fix is two integers.** Set both caches **well above `num_traces`** (this lab: `num_traces: 50000`, caches `500000` = 10×).

**Measure it** with dashboard panel 8 (`sampling_late_span_age`). Upstream's suggested ratio:
```promql
otelcol_processor_tail_sampling_sampling_late_span_age{le="+Inf"}
  / otelcol_processor_tail_sampling_count_spans_sampled
```
★ **`count_spans_sampled` requires the `processor.tailsamplingprocessor.metricstatcountspanssampled` feature gate**, which is off by default — so that ratio is unavailable until you enable it:
```bash
--feature-gates=processor.tailsamplingprocessor.metricstatcountspanssampled
```

---

## Exercise 4 — Watch the buffer evict traces

The buffer holds `num_traces: 50000`. Shrink it drastically and generate load:

```yaml
    num_traces: 200
    decision_wait: 10s
```
```bash
docker compose restart collector
```

**Watch dashboard panel 5** — `sampling_trace_dropped_too_early` climbs above zero.

★ **What that metric means:** the circular buffer evicted the **oldest** trace to make room for a new one, **before its `decision_wait` elapsed.** That trace never got a decision. It wasn't sampled out — it was **lost to undersizing**.

**Then look at panel 6** — `sampling_trace_removal_age`. Upstream's guidance:
> *"Calculate latency percentiles like **p1** and compare that value to `decision_wait`. Values close to `decision_wait` are at risk of being dropped if trace volume increases."*

★ **Panel 6 is the LEADING indicator and panel 5 is the LAGGING one.** When p1 removal age approaches `decision_wait`, eviction is *about* to start. Alert on p1, not on the drop counter.

**Two fixes, both of which cost memory:** raise `num_traces`, or lower `decision_wait`. Restore `num_traces: 50000`.

---

## Exercise 5 — ★ `num_shards` is not free

`num_shards` runs parallel event loops routed by trace-ID hash. It helps when `decision_timer_latency` (panel 7) exceeds ~1 s. But read the source comment:

> *"NumTraces, [decision cache sizes] and per-second rate limits (`max_total_spans_per_second`) are divided evenly across shards so aggregate behavior matches the configured values. **Limiter burst capacities are not divided** so single large traces stay admissible regardless of the shard count."*

Try it:
```yaml
    num_shards: 8
    num_traces: 50000          # ★ now 6,250 PER SHARD
```

**Consequences to reason about before you do this in production:**

| Setting | Effective value with `num_shards: 8` |
|---|---|
| `num_traces: 50000` | ★ **6,250 per shard** — eviction arrives 8× sooner |
| `decision_cache: 500000` | **62,500 per shard** |
| `composite.max_total_spans_per_second: 2000` | ★ **250 per shard** — and rate limiting becomes **approximate** |
| `burst_capacity` | **NOT divided** — aggregate burst scales with shard count |

★ **And enforcement becomes approximate for any limit smaller than `num_shards`.** A rate limit of 5 spans/s across 8 shards isn't meaningfully enforceable.

★ **`num_shards > 1` is incompatible with `tail_storage`.** Verbatim error:
```
processors::tail_sampling: num_shards greater than 1 is not supported with tail_storage
```
Upstream's reason: *"The TailStorage contract makes the caller responsible for serializing access, which multiple shard event loops cannot guarantee for a shared extension instance. **Sharding support belongs in the storage layer.**"*

Restore `num_shards: 1`.

---

## Exercise 6 — ★ `tail_storage` takes an extension ID, not a map

The obvious guess fails, **even with the feature gate enabled**:

```yaml
    tail_storage:
      kind: file
      directory: /tmp/x
```
```
'processors' error reading configuration for "tail_sampling":
'tail_storage' has invalid keys: directory, kind
```

The source declares `TailStorageID *component.ID`, so it names a **storage extension**:
```yaml
extensions:
  file_storage:
    directory: /var/lib/otelcol
    create_directory: true
processors:
  tail_sampling:
    tail_storage: file_storage      # ★ just the extension ID
service:
  extensions: [health_check, file_storage]
```
and you must enable the gate:
```bash
--feature-gates=processor.tailsamplingprocessor.tailstorageextension
```

★ **This is why the error sends you hunting for the gate when the schema is the actual problem.** `tail_storage` is the direction of travel for the memory problem — spill pending traces to disk instead of RAM — but it's experimental, gated, and incompatible with `num_shards > 1`.

---

## Exercise 7 — Which policy actually decided?

Dashboard panel 4 shows per-policy vote share, using upstream's formula:
```promql
sum(otelcol_processor_tail_sampling_count_traces_sampled{decision="sampled"}) by (policy)
  / sum(otelcol_processor_tail_sampling_count_traces_sampled) by (policy)
```

★ **But read the README's caveat:**
> *"A policy voting to sample the trace **does not guarantee sampling**; an 'inverted not sample' or 'drop' decision from another policy would still discard the trace."*

**To learn which policy actually decided**, enable the gate:
```bash
--feature-gates=processor.tailsamplingprocessor.recordpolicy
```
It adds attributes to each sampled span:

| Attribute | Description | Present? |
|---|---|---|
| `tailsampling.policy` | Name of the policy that sampled the trace | Always, **unless sampled by the decision cache** |
| `tailsampling.composite_policy` | Name of the composite **sub**-policy | When a composite policy was used |
| `tailsampling.cached_decision` | Whether the decision came from the cache | When a decision cache is used |

Then query in Tempo:
```
{ resource.service.name = "tail-sampled-service" && span.tailsampling.policy = "slow" }
```
★ **This is the difference between "I configured 5 policies" and "I know which one is keeping my traces."** Without it, debugging a sampling config is guesswork.

---

## Exercise 8 — `parentbased` is not optional

In `docker-compose.yml`, both apps set:
```
OTEL_TRACES_SAMPLER: parentbased_always_on
```

Change it to a bare ratio sampler and observe fragmentation:
```
OTEL_TRACES_SAMPLER: traceidratio
OTEL_TRACES_SAMPLER_ARG: "0.5"
```
```bash
docker compose up -d --force-recreate app-tail
```

★ **A bare `traceidratio` re-rolls the dice per span rather than propagating the root decision.** In a single-service app the effect is subtle; across a call chain you get **traces with missing spans** — a parent kept, a child dropped. The trace still exists in Tempo, it's just wrong, and **nothing errors**.

`parentbased_*` is what makes a distributed trace coherent. The available samplers are `always_on`, `always_off`, `traceidratio`, `parentbased_always_on`, `parentbased_always_off`, `parentbased_traceidratio`. ★ **In practice you almost always want a `parentbased_` variant.**

---

## The seven metrics to alert on

All from the v0.161.0 README, all on the dashboard:

| Metric | Why it matters | Threshold |
|---|---|---|
| ★ `sampling_trace_dropped_too_early` | **Buffer eviction = data loss, not sampling** | **> 0** |
| ★ `sampling_trace_removal_age` (p1) | **Leading** indicator of eviction | approaching `decision_wait` |
| ★ `sampling_decision_timer_latency` | **> 1 s means decisions land after `decision_wait`** | p99 > 1 s |
| `sampling_late_span_age` | Partial traces from late spans | p99 rising |
| `global_count_traces_sampled{sampled="true"}` | Your actual sample rate | far from expectation |
| `count_traces_sampled{decision,policy}` | Which policies are working | any policy at 0 |
| ★ `sampling_policy_evaluation_error` | **A policy that errors is a policy silently doing nothing** — usually a typo'd attribute key | **> 0** |

---

## What you should now be able to answer

1. Why does head sampling lose 90% of errors? → **It decides at the root span, before any child has failed. It cannot see the error.**
2. What happens if no `tail_sampling` policy matches? → ★ **The trace is DROPPED. Always end with a catch-all.**
3. Why do I have partial traces? → ★ **`decision_cache` sizes default to 0 (inactive); late spans get a fresh independent decision.** Set them ≫ `num_traces`.
4. What does `sampling_trace_dropped_too_early > 0` mean? → **Buffer eviction from undersized `num_traces` or too-long `decision_wait`. Not sampling — loss.**
5. What's the leading indicator for that? → ★ **p1 of `sampling_trace_removal_age` approaching `decision_wait`.**
6. What does `num_shards: 8` really do? → **Divides `num_traces`, caches and per-second limits by 8; does NOT divide `burst_capacity`; makes enforcement approximate; incompatible with `tail_storage`.**
7. How do I know which policy kept a trace? → **`processor.tailsamplingprocessor.recordpolicy` gate → `tailsampling.policy` attribute.**
8. Why `parentbased_`? → **A bare ratio sampler re-rolls per span and fragments traces across service boundaries, silently.**
9. Why is head sampling in the SDK and tail sampling in the Collector? → **Head is cheaper before serialisation; tail needs the whole trace, so it needs a stateful aggregation point.**

→ Next: [`../lab-04-metrics-and-prometheus/`](../lab-04-metrics-and-prometheus/) · Back: [`../README.md`](../README.md)
