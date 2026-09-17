# 17 · Migration & Adoption

How to get from wherever you are to OpenTelemetry **without an outage, without a big-bang rewrite, and without losing the ability to roll back.** This is the file that determines whether the other sixteen matter.

*Verified baseline: OTel **graduated from the CNCF on 2026-05-21**; Collector core **v1.67.0** / contrib **v0.161.0** (2026-09-14); OTLP spec **1.11.0**; semconv **v1.44.0**; declarative file-based configuration **stable**; the Jaeger propagator **deprecated** in spec 1.54.0.*

---

## 17.1 What migration actually means

**"Migrating to OpenTelemetry" is four separate projects that people conflate**, and each has a different risk profile. Separate them and the whole thing becomes tractable.

| # | Project | Risk | Can you do it independently? |
|---|---|---|---|
| **1** | **Instrumentation** — replace vendor/legacy agents with OTel SDKs or the OTel auto-instrumentation agent | **Low–medium.** Rollback = redeploy the old agent | ★ **Yes — and you should start here** |
| **2** | **Wire protocol** — send OTLP instead of Jaeger thrift / Zipkin JSON / vendor proprietary | **Low.** The Collector translates | **Yes** — usually simultaneous with #1 |
| **3** | **Pipeline** — insert Collectors for enrichment, sampling, redaction, routing | **Low.** Additive | **Yes** |
| **4** | **Backend** — replace Jaeger/ES/vendor with Tempo/ClickHouse/etc. | ★ **High.** Data migration, dashboard rewrites, alert rewrites, team retraining | **Yes — and you should do it LAST, or never** |

★ **The strategic insight: you can complete projects 1–3 and get most of OpenTelemetry's benefit without touching your backend at all.** OTel is a **producer standard**. Sending OTLP into your existing Jaeger, Elasticsearch, Datadog or Splunk works today, via the Collector's protocol translators.

**This reframes the whole business case.** The pitch is not "replace your observability stack." It's: *"stop writing instrumentation four times, stop being locked into an agent, and gain a place (the Collector) to enforce redaction, sampling and cardinality policy — while keeping every dashboard and alert you already have."* **That's a much easier thing to get approved, and it's true.**

---

## 17.2 Migration paths from specific starting points

### From Jaeger
**The easiest migration there is, because Jaeger already converged on OTel.** Jaeger accepts **OTLP natively** on 4317/4318, and Jaeger's own client libraries have been in maintenance in favour of OTel SDKs for years.

| Step | Action |
|---|---|
| 1 | **Keep the Jaeger backend.** Change nothing there |
| 2 | Insert a Collector in front of it: apps → Collector → `otlp` exporter → Jaeger |
| 3 | Replace `jaeger-client-go`/`jaeger-client-java` with OTel SDKs (or the OTel auto-instrumentation agent) |
| 4 | Switch the propagator from `jaeger` to `tracecontext` ★ **carefully — see the interop note below** |
| 5 | Add `tail_sampling`, `span_metrics`, `k8s_attributes` in the Collector — **you now have capabilities Jaeger's client never gave you** |
| 6 | Optionally, later, move storage. ★ **The Collector's `jaeger` receiver exists for legacy producers still emitting Jaeger thrift/protobuf** — keep it during the transition |

★ **The propagator interop trap.** During rollout, **some services will emit `traceparent` and others `jaeger-ultronid`.** If a mixed chain has only one propagator configured, **the trace breaks at the boundary** — you get two disconnected traces instead of one. Fix: **configure multiple propagators during the transition window**:
```bash
OTEL_PROPAGATORS=tracecontext,baggage,jaeger
```
★ **And note the Jaeger propagator is deprecated in spec 1.54.0.** Use it as a **transition bridge only**, then remove it. Don't build new services on it.

### From Zipkin
| Step | Action |
|---|---|
| 1 | Zipkin ingestion accepts OTLP via a Collector with the `zipkin` exporter — **or send OTLP directly to a modern Zipkin-compatible backend** |
| 2 | Replace Brave / `spring-cloud-sleuth` with the OTel SDK |
| 3 | ★ **Semconv gap:** Zipkin used `http.method`, `http.status_code`, `http.url`. OTel stable uses `http.request.method`, `http.response.status_code`, `url.full`/`url.path`. **Dashboards and searches break unless you translate** |
| 4 | Use the Collector's `pkg.translator.zipkin` gates during transition — ★ **verified in v0.161.0: `DontEmitV0NetworkConventions` and `EmitV1NetworkConventions` are BOTH true (Beta) for network attributes, while `http`, `scope` and `cloud_resource` are still V0-only (Alpha).** **One translator, two conventions simultaneously** |
| 5 | B3 propagation: `OTEL_PROPAGATORS=b3` or `b3multi` — ★ **B3 is not deprecated**, so this is a legitimate long-term choice if your mesh requires it |

### From Spring Cloud Sleuth ★
Very common, and the path is well-trodden: **Sleuth 3.x → Micrometer Tracing → OpenTelemetry bridge.**

| Step | Action |
|---|---|
| 1 | Spring Boot 3.x: replace `spring-cloud-starter-sleuth` with **`micrometer-tracing-bridge-otel`** + `opentelemetry-exporter-otlp` |
| 2 | ★ **Property rename**: `spring.sleuth.*` → `management.tracing.*` and `management.otlp.tracing.*` |
| 3 | Sampling: `management.tracing.sampling.probability` |
| 4 | `@NewSpan`/`@ContinueSpan` annotations → Micrometer's `@NewSpan` (different package) or manual OTel spans |
| 5 | Zipkin reporter → OTLP exporter; **point at the Collector, not the backend** |
| 6 | Spring Boot 2.x is out of OSS support — ★ **if you're still on Sleuth 2/3 with Boot 2, the tracing migration is coupled to a framework upgrade. Plan them together, and don't let the tracing work be the thing that blocks the upgrade** |

### From a vendor agent (Datadog, New Relic, Dynatrace, AppDynamics)
| Step | Action |
|---|---|
| 1 | ★ **Insert a Collector first, keep the vendor.** App → Collector → vendor OTLP/HTTP endpoint. **Zero behaviour change, and you've gained your policy enforcement point** |
| 2 | Add OTel instrumentation **alongside** the vendor agent where they can coexist, or replace service-by-service |
| 3 | **Dual-ship during the comparison window**: `otlp/vendor` + `otlp/newbackend` in parallel. ★ **This is the only way to validate a backend migration against real traffic without risk** |
| 4 | Compare: does the new backend show the same service map? Same p99? Same error rate? **Reconcile differences before cutting over** |
| 5 | Move dashboards and alerts. ★ **This is the real work and the real lock-in — not the data** |
| 6 | Cut the vendor exporter. Keep the Collector. |

★ **Vendor-specific notes:** Datadog accepts OTLP natively (and the Collector has a `datadog` exporter plus a `datadog` connector); most vendors now accept OTLP/HTTP. **Check whether the vendor's OTLP endpoint supports all three signals** — some accept traces via OTLP but still require their own agent for metrics or APM-specific features. **That asymmetry is often the reason a migration stalls at 80%.**

### From Prometheus-only (adding traces and logs)
Not a migration — an **extension**. Your metrics stay in Prometheus.

| Step | Action |
|---|---|
| 1 | Deploy a Collector for traces and logs only. **Prometheus keeps scraping what it scrapes** |
| 2 | Add OTel instrumentation to services for traces |
| 3 | ★ **Optionally let the Collector take over Prometheus scraping** via the Target Allocator — **it consumes your existing ServiceMonitors and PodMonitors**, so you don't rewrite scrape config ([`12-collector-in-kubernetes.md`](12-collector-in-kubernetes.md)) |
| 4 | Add **exemplars** to link Prometheus metrics → traces. **This is the highest-value step in the whole project** — it turns two separate tools into one investigation |
| 5 | Add derived-field links from logs → traces |

★ **Step 4 is the one that changes how on-call feels.** Without exemplars, an engineer sees a latency spike, opens the trace UI, and manually guesses a time window and service. With exemplars, they click a point on the graph and land on a representative trace. **If you do only one thing after deploying OTel, do this.**

### From OpenTracing / OpenCensus
Both are **merged into OpenTelemetry** — that's literally what OTel is. Bridges exist (`opentracing-shim`, `opencensus-shim`), but ★ **at this point the shims are legacy compatibility, not a migration strategy.** Go straight to the OTel SDK; the shim only makes sense for a large codebase you can't touch all at once.

---

## 17.3 The rollout plan

### Phase 0 — Foundation (weeks 1–3)
- [ ] **Write down the answers to §17.6 before touching code.** Ten incident queries, data-flow map, retention requirements, ownership model
- [ ] Deploy a Collector **gateway** (Deployment, 3 replicas) and **agent** (DaemonSet) — contrib image, pinned by digest
- [ ] Configure `memory_limiter`, `batch`, `sending_queue` **enabled**, `retry_on_failure` **enabled** ★ *(both off by default)*
- [ ] Wire it to your **existing backend** — change nothing downstream
- [ ] Scrape the Collector's own `:8888` telemetry and **build the seven alerts** ([`11-collector.md`](11-collector.md), [`16-troubleshooting.md`](16-troubleshooting.md))
- [ ] **Deliverable: a pipeline that works, that you can observe, before a single app uses it**

★ **Do not skip the Collector self-monitoring.** If you onboard 200 services onto a pipeline you can't observe, you will spend the next quarter debugging whether data is missing or whether nobody sent it.

### Phase 1 — Lighthouse (weeks 3–8)
- [ ] Pick **2–3 services**: one high-value, one representative, one owned by an enthusiastic team
- [ ] Instrument with **auto-instrumentation first** — baseline coverage in hours, not weeks
- [ ] ★ **Raise memory limits before enabling** (the Java agent adds tens of MB of heap; OOMKills are the most common auto-instrumentation incident)
- [ ] Add **manual spans** for the 2–3 business operations that matter
- [ ] Add **log correlation** (trace_id/span_id injection)
- [ ] Configure **exemplars** and **derived-field links**
- [ ] **Sit an on-call with the team and use it in a real incident**
- [ ] **Deliverable: a written case study with a real incident where OTel found something the old tooling didn't**

★ **The lighthouse phase's output is a story, not a deployment.** Adoption is a social problem. "We found the deadlock in 4 minutes instead of 2 hours" moves more teams than any architecture diagram. **Budget for writing it down.**

### Phase 2 — Platform (weeks 8–16)
- [ ] Publish **golden-path config**: `Instrumentation` CR, resource attributes, propagator list, sampler, exporter endpoint
- [ ] Publish **a library/starter** per language that does the right thing by default (service name, environment, cardinality-safe views, shutdown flush ★)
- [ ] ★ **Cardinality policy enforced in the pipeline**, not by request: SDK view allowlists + `OTEL_METRIC_CARDINALITY_LIMIT` + `cardinality_guardian` in `tag_only`
- [ ] **Redaction at the gateway** — `redaction` processor, `url_sanitizer` enabled, `summary: silent`
- [ ] **Tail sampling** in the gateway with a `composite` budget policy
- [ ] **Showback dashboard** by service/team
- [ ] **Deliverable: a team can onboard in under a day without talking to you**

★ **"Under a day without talking to you" is the real success criterion for a platform.** If every onboarding needs a review, you are the bottleneck and adoption will plateau at your team's capacity.

### Phase 3 — Scale (weeks 16+)
- [ ] Roll out by **business domain**, not alphabetically — a whole domain at once means complete traces instead of fragments
- [ ] ★ **Auto-instrument everything first, then hand-instrument the services that need business semantics.** Don't wait for perfection on service 40 before starting service 41
- [ ] Migrate dashboards **incrementally** — dual-emit during semconv transitions
- [ ] Retire legacy agents **service by service**, never fleet-wide
- [ ] Review retention and sampling quarterly
- [ ] **Deliverable: legacy instrumentation is an exception that requires justification**

### ★ The rollout rule that matters most
**Migrate by trace, not by service.** A trace that crosses ten services is only useful if **all ten** propagate context. Migrating one service in a chain gives you a truncated trace with a broken parent — which is **worse than not migrating**, because it looks like a bug.

**Practical consequence:** group rollouts by **call graph**, and during the transition **configure multiple propagators everywhere** (`tracecontext,baggage` plus whatever legacy format is still in play) so mixed chains stay connected.

---

## 17.4 Coexistence patterns

You will run old and new side by side for months. Design for it.

| Pattern | How | When |
|---|---|---|
| **Protocol translation at the Collector** | Legacy producers → `jaeger`/`zipkin` receiver → OTLP internally → any exporter | ★ **The default answer.** Legacy apps need no changes |
| **Dual-shipping** | Two exporters in one pipeline (or a `routing`/`round_robin` connector) | Backend comparison windows; gradual cutover |
| **Fan-out to old + new backend** | List both exporters — no connector needed | Keeping the old system live during migration |
| **Dual instrumentation** | Vendor agent + OTel SDK in the same process | ★ **Usually works, but verify** — two agents can double-instrument the same library, doubling overhead and producing duplicate spans. **Test on one service before assuming it's safe** |
| **Multi-propagator** | `OTEL_PROPAGATORS=tracecontext,baggage,jaeger,b3` | Mixed-version call chains |
| **Semconv dual emission** | Feature gates | ★ **But note v0.161.0's real behaviour: most components emit ONE generation, not both** — `k8s_attributes` is V1-only, `host_metrics` is V0-only ([`04-semantic-conventions.md`](04-semantic-conventions.md)). **You migrate dashboards per component, not per switch** |
| **Shadow pipeline** | Route a copy to a candidate backend with no alerting attached | Evaluating a new backend without risk |

★ **The dual-shipping cost warning:** shipping to two backends **doubles your egress and doubles the ingest cost at the second backend.** Set an explicit end date for the comparison window, and put it in the calendar. **Comparison windows that never close are how organisations end up paying for two observability stacks for three years.**

---

## 17.5 The maturity model

Where are you, and what's the next step? Honest self-assessment beats aspiration.

| Level | State | Typical evidence | **Next step** |
|---|---|---|---|
| **0 — None** | No distributed tracing; logs and metrics only | On-call greps logs across services | Deploy a Collector + instrument 2 services |
| **1 — Siloed** | Tracing exists but per-vendor or per-team; no context propagation across boundaries | Traces stop at service boundaries; two tracing systems | ★ **Multi-propagator config; migrate by call graph** |
| **2 — Instrumented** | OTel across most services; traces span boundaries | You can follow a request end to end | **Correlate signals** — exemplars + log trace_id |
| **3 — Correlated** | Metric→trace→log→profile navigation works | ★ **An engineer clicks a graph point and lands on a trace** | **Control cost** — sampling, cardinality policy, showback |
| **4 — Governed** | Cardinality, redaction, retention and sampling are **policy**, enforced in the pipeline | New services can't create a cardinality explosion even by accident | **Automate** — golden-path starters, CI checks, OpAMP fleet management |
| **5 — Optimised** | Continuous cost/quality tuning with data | `cardinality_guardian` savings reported monthly; sampling reviewed with incident response | **Extend** — profiles, eBPF zero-code coverage, GenAI observability |

★ **Most organisations that "adopt OpenTelemetry" stop at level 2.** They get traces, feel done, and never capture the value that makes the platform pay for itself — **correlation (level 3) and governance (level 4)**. Level 3 is what makes on-call faster; level 4 is what makes the bill sustainable. **Both are Collector configuration, not new infrastructure.**

---

## 17.6 The questions to answer before you start

★ **Answering these is the project. Writing code is the easy part.** Teams that skip this end up with instrumentation and no answers.

### About your incidents
1. **Write down the last five incidents.** For each: *what did you look at, in what order, and how long did it take?* **This is your requirements document.**
2. **What are the ten queries you'd run in an incident?** ★ **Check each one is fast on your chosen backend** — not "does it have a query language" but "is *my* query fast" ([`13-backends.md`](13-backends.md))
3. **Which signal was missing each time?** If the answer is "we had the trace but couldn't find the log," your problem is **correlation**, not coverage.

### About your data
4. **What personal data does telemetry capture today?** Run a real trace through and *look*. ★ **Exception messages routinely contain emails, order IDs and addresses that nobody intended to store**
5. **Where does it physically go?** Region, vendor, cross-border. **GDPR transfers and PRC geographic-coordinate export restrictions are architecture constraints**
6. **What retention do you actually need, and why?** Separate *"compliance requires 400 days"* from *"it's the default"*
7. **Who can query traces?** ★ **A trace store is a behavioural record of your users** — often more revealing than your product database, because it captures attempts and errors

### About your estate
8. **How many services, in which languages?** This determines whether auto-instrumentation is viable (Java/Python/Node/.NET: yes; Go: compile-time, needs a build step)
9. **What's already instrumented, and how well?** ★ **Existing vendor agents may already give you 70% of this.** The migration case is then about lock-in and standardisation, not capability — **be honest about that, or you'll oversell and lose credibility**
10. **What's your mesh/sidecar situation?** A service mesh already does L7 telemetry. **Don't build the same thing twice**

### About your organisation
11. **Who owns the platform, and what's their capacity?** ★ **An unowned Collector fleet is an outage waiting to happen**
12. **Who reviews a new metric attribute for cardinality?** If the answer is "nobody," you'll have a cost incident within a quarter
13. **What's the onboarding path for a new service?** Target: **under a day, without talking to your team**
14. **How will you show cost back to teams?** ★ **Visibility alone typically cuts 10–20%**
15. **What's the rollback plan?** For instrumentation (redeploy), for the Collector (previous config/image), for a backend cutover (dual-ship)

---

## 17.7 Anti-patterns

| Anti-pattern | Why it fails | Instead |
|---|---|---|
| **Big-bang migration** | ★ Every service changes at once; every trace breaks; no rollback | Migrate by **call graph**, in domains |
| **Backend-first** | Highest-risk project done first, with no instrumentation to feed it | **Instrumentation and Collector first; backend last, or never** |
| **"Instrument everything manually"** | Months of work for baseline coverage; teams stall | ★ **Auto-instrument for coverage, manual spans for the 2–3 business operations that matter** |
| **Waiting for the perfect golden path** | Nothing ships; the standard keeps moving | Ship a **good** golden path in week 8; iterate |
| **Per-team Collector configs** | 200 Collectors, 200 sampling policies, no central redaction | **Platform-owned gateway; teams own their SDK config** |
| **Skipping the Collector** (SDK → vendor direct) | No redaction, no cardinality control, no dual-ship, and leaving is a code change in every service | ★ **Always deploy a Collector, even for a vendor-only setup** |
| **100% sampling because "storage is cheap"** | Cheap ≠ free; and it isn't cheap at 10× | **Tail sampling with a composite budget** |
| **No self-monitoring of the pipeline** | You can't tell "missing" from "never sent" | ★ **Instrument the Collectors before instrumenting the apps** |
| **Comparison windows that never close** | Paying for two stacks for three years | **Put the end date in the calendar** |
| **Treating it as an infra project** | Adoption is social; teams don't use what they don't believe in | ★ **Lighthouse service + a written incident story** |
| **Migrating a semconv generation without migrating units** | p99 dashboard shows 0.5 instead of 500 | **Check the `unit` field, not just the name** |
| **Assuming dual instrumentation is free** | Two agents may double-instrument the same library | **Test on one service first** |
| **Declaring victory at level 2** | Traces exist; correlation and governance never happen | ★ **Level 3 (exemplars + log links) and level 4 (policy) are where the value is — and both are Collector config, not new infrastructure** |

---

## Red flags

| Doing this | Costs you |
|---|---|
| Conflating instrumentation, protocol, pipeline and backend into one "migration" | ★ **Four projects with different risk profiles.** 1–3 are low-risk and independent; **4 is the hard one** |
| Starting with the backend replacement | Highest risk, and nothing to feed it yet |
| Refusing to consider "keep the existing backend" | ★ **You can get most of OTel's benefit without touching it.** OTel is a producer standard |
| Migrating one service in a ten-service call chain | **Truncated traces with broken parents — worse than not migrating** |
| A single propagator during a mixed-version rollout | Traces break at every old/new boundary |
| Building new services on the Jaeger propagator | ★ **Deprecated in spec 1.54.0.** Transition bridge only |
| Not raising memory limits before enabling auto-instrumentation | **OOMKills** — the most common auto-instrumentation incident |
| Onboarding 200 services before the Collectors are monitored | A quarter spent debugging "missing vs never sent" |
| No explicit end date on dual-shipping | ★ Two stacks, three years |
| Per-team Collector configs | No central redaction, sampling or cardinality policy |
| SDKs pointed straight at a vendor | No policy enforcement point; leaving is a code change everywhere |
| Skipping exemplars and log→trace links | ★ **The single highest-value step after deployment, and it's just configuration** |
| Migrating a semconv name but not its unit | ★ ms→s between V0 and V1: **0.5 instead of 500** |
| Assuming all components emit both semconv generations | ★ **In v0.161.0 most emit ONE** — `k8s_attributes` V1-only, `host_metrics` V0-only. Migrate dashboards **per component** |
| No cardinality reviewer | A cost incident within a quarter |
| No written data-flow map | ★ **You can't govern what you haven't mapped — and it takes an afternoon** |
| Overselling the capability case when vendor agents already deliver 70% | You lose credibility when teams notice |
| Stopping at "we have traces" | ★ **Levels 3 (correlation) and 4 (governance) are where the value and the sustainability live** |

---

## Rapid recall

1. ★ **"Migrating to OpenTelemetry" is FOUR separate projects:** ① **instrumentation** (low–medium risk, rollback = redeploy), ② **wire protocol** (low — the Collector translates), ③ **pipeline** (low — additive), ④ **backend** (★ **high** — data, dashboards, alerts, retraining). **Do 1–3 first; do 4 last, or never.**
2. ★ **You can complete projects 1–3 and get most of OTel's benefit without touching your backend.** OTel is a **producer standard** — OTLP flows into Jaeger, Elasticsearch, Datadog and Splunk today via the Collector's translators. **The pitch is "stop writing instrumentation four times and gain a policy enforcement point," not "replace your stack."**
3. **From Jaeger — easiest of all:** Jaeger **already converged on OTel** and accepts OTLP natively. Keep the backend, insert a Collector, swap client libs, then add `tail_sampling`/`span_metrics`/`k8s_attributes`. ★ **The Collector's `jaeger` receiver exists for legacy producers still emitting thrift/protobuf.**
4. ★ **The propagator interop trap:** during rollout some services emit `traceparent` and others `jaeger-ultronid`. **With one propagator configured, the trace BREAKS at the boundary** — two disconnected traces, which looks like a bug. Use `OTEL_PROPAGATORS=tracecontext,baggage,jaeger` as a **transition bridge** (★ **the Jaeger propagator is deprecated in spec 1.54.0**), and remove it after. **B3 is NOT deprecated** and is a legitimate long-term choice.
5. **From Zipkin:** replace Brave with the OTel SDK; ★ **semconv gap** — `http.method`/`http.status_code`/`http.url` → `http.request.method`/`http.response.status_code`/`url.full`. And note v0.161.0's translator emits **network attributes V1-only while http/scope/cloud_resource are still V0-only** — one translator, two conventions.
6. **From Spring Cloud Sleuth:** Boot 3.x → **`micrometer-tracing-bridge-otel`** + OTLP exporter; ★ `spring.sleuth.*` → `management.tracing.*` / `management.otlp.tracing.*`; annotations change package. **On Boot 2, the tracing migration is coupled to a framework upgrade — plan them together.**
7. **From a vendor agent:** ★ **insert a Collector first and keep the vendor** (zero behaviour change, immediate policy enforcement point) → add OTel instrumentation → **dual-ship** to old + new during a comparison window → **reconcile service map, p99 and error rate before cutting over** → move dashboards and alerts (★ **the real work and the real lock-in**) → cut the vendor exporter, **keep the Collector**. ★ **Check whether the vendor's OTLP endpoint supports all three signals** — that asymmetry is why migrations stall at 80%.
8. **From Prometheus-only:** this is an **extension**, not a migration. Keep Prometheus; add a Collector for traces/logs; ★ the **Target Allocator consumes your existing ServiceMonitors/PodMonitors** so you don't rewrite scrape config; then **add exemplars**. ★ **Exemplars are the highest-value single step in the whole project** — clicking a graph point and landing on a representative trace is what changes how on-call feels.
9. **From OpenTracing/OpenCensus:** both are **merged into OTel**. Shims exist but are ★ **legacy compatibility, not a migration strategy** — go straight to the OTel SDK unless the codebase is too large to touch at once.
10. **Rollout phases:** **0 Foundation** (Collector gateway+agent, `sending_queue` and `retry_on_failure` **enabled** — ★ both off by default — wired to your *existing* backend, ★ **self-monitoring and the seven alerts live before any app uses it**) → **1 Lighthouse** (2–3 services, auto-instrument first, ★ **raise memory limits**, manual spans for 2–3 business ops, log correlation, exemplars, **sit a real on-call**) → **2 Platform** (golden path, per-language starters, cardinality policy **enforced in the pipeline**, gateway redaction, tail sampling, showback) → **3 Scale** (by domain, auto-instrument everything then hand-instrument what needs semantics, retire legacy agents service-by-service).
11. ★ **Phase 1's deliverable is a STORY, not a deployment.** "We found the deadlock in 4 minutes instead of 2 hours" moves more teams than any architecture diagram. **Budget for writing it down.**
12. ★ **Phase 2's success criterion: a team can onboard in under a day without talking to you.** If every onboarding needs a review, **you are the bottleneck and adoption plateaus at your team's capacity.**
13. ★★ **The rollout rule that matters most: migrate by TRACE, not by SERVICE.** A trace crossing ten services is only useful if all ten propagate context. **Group rollouts by call graph**, and run multi-propagator everywhere during transition.
14. **Coexistence patterns:** protocol translation at the Collector (**the default answer**), dual-shipping, fan-out (just list both exporters), multi-propagator, shadow pipelines. ★ **Dual instrumentation usually works but verify** — two agents can double-instrument the same library. ★ **Dual-shipping doubles egress and ingest cost: put the end date in the calendar.**
15. **Semconv dual emission is mostly NOT available in v0.161.0** — most components emit one generation only. **Migrate dashboards per component, not per switch.**
16. **Maturity model:** 0 none → 1 siloed → 2 instrumented → **3 correlated** (★ metric→trace→log→profile navigation works) → **4 governed** (cardinality/redaction/retention/sampling enforced as **pipeline policy**, so a new service can't cause an explosion by accident) → 5 optimised (continuous tuning, profiles, eBPF). ★ **Most organisations stop at 2.** Levels 3 and 4 are where the value and the sustainability live — **and both are Collector configuration, not new infrastructure.**
17. ★ **Answer the fifteen questions in §17.6 before writing code — that IS the project.** The three that matter most: **write down your last five incidents and what you looked at**; **write down your ten incident queries and verify each is fast on your chosen backend**; and **run a real trace through and LOOK at it** — exception messages routinely contain emails and order IDs nobody intended to store.
18. **Be honest about the existing estate.** ★ **If vendor agents already deliver 70%, the case is lock-in and standardisation, not capability.** Overselling costs you credibility the moment teams notice.
19. **Anti-patterns:** big-bang migration; backend-first; "instrument everything manually"; waiting for a perfect golden path; per-team Collector configs; **skipping the Collector entirely**; 100% sampling; no pipeline self-monitoring; comparison windows that never close; treating it as an infra project rather than a social one.
20. ★ **Always deploy a Collector, even in a vendor-only setup.** It's where redaction, cardinality control, sampling and dual-shipping live — **and it's what makes leaving possible later.**

→ Back to the index: [`README.md`](README.md)
