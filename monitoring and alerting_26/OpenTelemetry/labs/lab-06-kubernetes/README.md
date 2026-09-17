# Lab 06 — OpenTelemetry on Kubernetes

**Goal:** run a correct two-tier Collector fleet on Kubernetes, instrument workloads with zero code changes, and — the part everyone skips — **monitor the Collector itself**.

**Time:** 60–90 minutes. **Prerequisites:** a Kubernetes cluster (kind/minikube/Docker Desktop, ≥3 nodes for the anti-affinity exercise), `kubectl`, `helm`.

**Read [`../../12-collector-in-kubernetes.md`](../../12-collector-in-kubernetes.md) first.** It covers the deployment modes, the Target Allocator, and the RBAC model; this lab makes them concrete.

> ★ **No cluster? Read it anyway.** Every config in `collector-configs/` is machine-validated against `otelcol-contrib` v0.161.0, and the manifests encode decisions you'll make regardless of platform. The verification notes are the valuable part.

---

## Files

| File | What |
|---|---|
| `collector-configs/agent-config.yaml` | ★ **validated** — the DaemonSet tier: enrich, detect, filter, **route** |
| `collector-configs/gateway-config.yaml` | ★ **validated** — the StatefulSet tier: **tail sample**, fan out |
| `manifests/00-namespace.yaml` | Namespace, ServiceAccount, RBAC, PriorityClass |
| `manifests/01-agent-daemonset.yaml` | Agent DaemonSet + Service |
| `manifests/02-gateway-statefulset.yaml` | Gateway StatefulSet + headless/ClusterIP Services + PDB + HPA |
| `manifests/03-configmaps.yaml` | ★ **generated from the validated configs, byte-identical** |
| `manifests/04-operator-crs.yaml` | Operator alternative: `OpenTelemetryCollector` (v1beta1), `TargetAllocator`, `Instrumentation` |
| `manifests/05-workload-and-monitoring.yaml` | Instrumented Deployment, ServiceMonitors, and **12 alerts** |

★ **`04-operator-crs.yaml` is an ALTERNATIVE to `01`+`02`+`03`, not an addition.** The Operator renders those workloads for you. Applying both means two Collectors fighting over `:4317`.

---

## The architecture, and why it's shaped this way

```
   pods (zero-code instrumented via Operator webhook)
        │  OTLP
        ▼
 ┌─────────────────────────────────────────────────┐
 │  AGENT TIER — DaemonSet, one per node           │
 │  k8sattributes · resourcedetection · filter     │
 │  batch · load_balancing(routing_key: traceID)   │  ◀── routes consistently
 └─────────────────────────────────────────────────┘
        │  DNS resolver over the HEADLESS Service
        ├──────────────┬──────────────┐
        ▼              ▼              ▼
   gateway-0      gateway-1      gateway-2      ◀── StatefulSet, stable identity
   ┌──────────────────────────────────────────┐
   │  GATEWAY TIER                            │
   │  tail_sampling (sees the WHOLE trace)    │
   │  span_metrics · cardinality control      │
   └──────────────────────────────────────────┘
        │              │              │
        ▼              ▼              ▼
      Tempo          Loki        Prometheus
```

### ★★ Why the agent can't tail-sample

A trace's spans are spread across pods on **different nodes**, so they reach **different agent replicas**. Each agent sees a **fragment**. A tail-sampling decision made on a fragment is a decision made on partial data — **worse than no decision, because it looks authoritative.**

### ★★ Why the gateway can't be a Deployment

`tail_sampling` needs every span of a trace in **one process**, and `load_balancing` with `routing_key: traceID` must send a given trace to the **same replica** every time. A Deployment gives interchangeable pods with random names; when one is replaced, every trace it was buffering is lost. A StatefulSet gives **stable network identities** (`gateway-0`, `-1`, `-2`) plus **per-replica PVCs** via `volumeClaimTemplates`.

★ **If you're not tail-sampling or trace-ID routing, use a Deployment.** Don't pay for stability you don't need.

### ★★ Why routing must happen *before* sampling

With N gateway replicas behind an ordinary Kubernetes Service, round-robin spreads one trace's spans across all N. Each replica sees a fragment and makes a **different** decision. You get partial traces and a sample rate that means nothing — **with no errors anywhere**.

**Consistent traceID routing from the agent tier is a correctness requirement, not an optimisation.** And it needs no coordination: every agent independently hashes the same trace ID with the same algorithm, so they all agree on the owner.

---

## Run it (manifests path)

```bash
cd labs/lab-06-kubernetes
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/03-configmaps.yaml
kubectl apply -f manifests/02-gateway-statefulset.yaml
kubectl apply -f manifests/01-agent-daemonset.yaml
kubectl -n otel-lab rollout status statefulset/otel-collector-gateway
kubectl -n otel-lab rollout status daemonset/otel-collector-agent
kubectl -n otel-lab get pods -o wide
```

**Verify the headless Service returns one record per pod** — this is what makes `load_balancing` work:
```bash
kubectl -n otel-lab run dns --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup otel-collector-gateway-headless.otel-lab.svc.cluster.local
```
★ **You must see THREE A records.** One virtual IP means the Service isn't headless and routing has silently degenerated into a no-op.

---

## Exercise 1 — ★★ `load_balancing` is an exporter, not a connector

The obvious design is wrong. You might write, inside the gateway:

```yaml
    traces/lb:      # receivers: [otlp]                  exporters: [load_balancing/traces]
    traces/sample:  # receivers: [load_balancing/traces] exporters: [otlp/tempo]
```

— treating `load_balancing` as a connector that bridges two pipelines, the way `span_metrics` does. **`validate` rejects it:**

```
service::pipelines::logs: references receiver "load_balancing/logs" which is not configured
```

★ **Verified against `components-0.161.0.yaml`:** `load_balancing` appears **only** under `exporters` (stability: traces **Beta**, metrics **Alpha**, logs Beta). It is in **neither** `connectors` **nor** `receivers`.

**So routing belongs on the tier that routes — the agent.** That's where these configs put it.

**Compare with `span_metrics`,** which *is* a connector and therefore legitimately appears as an exporter in `traces` and a receiver in `metrics`. ★ Connectors bridge pipelines; exporters don't. That asymmetry is the whole lesson.

---

## Exercise 2 — ★ The `load_balancing` schema traps

All verified in this lab:

| Setting | Fact |
|---|---|
| **Component name** | Renamed `loadbalancing` → **`load_balancing`** for lower_snake_case. Old name still parses as a **deprecated alias** |
| **`routing_key` position** | ★ **TOP-LEVEL**, not nested under `protocol` |
| **`protocol`** | Supports **only `otlp`** |
| **`resolver.dns.port`** | ★★ **A STRING** (`"4317"`), not an int. Every other port in a Collector config is an int |
| **`resolver.dns.hostname`** | Must be a **headless** Service or DNS returns one IP |

**The port trap fails like this:**
```
'resolver.dns' decoding failed due to the following error(s):
'port' expected type 'string', got unconvertible type 'int'
```

**Verified `routing_key` values and which signals they're valid for:**

| `routing_key` | Valid for | Notes |
|---|---|---|
| `service` | spans, logs, metrics | Hashes `service.name`. ★ **A hot service pins ALL its traffic to ONE replica** |
| `traceID` | spans, logs | ★ **INVALID for metrics** |
| `resource` | logs, metrics | Hash of ALL resource attributes — finer than `service` |
| `metric` | **metrics only** | By metric name |
| `streamID` | **metrics only** | ★ What `delta_to_cumulative` needs: same series → same replica |
| `attributes` | spans, logs, metrics | Requires `routing_attributes`; use to split an overwhelming service |

**Defaults when unset:** `traceID` for traces, `service` for logs **and** metrics.

★ **And the thing the README says plainly:**
> *"either the Trace ID or Service name is used for the decision on which backend to use: **the actual backend load isn't taken into consideration**."*

**This is consistent hashing, not least-connections.** Load distribution is good (README claims stddev under 5%) but a single hot key is a single hot replica.

---

## Exercise 3 — ★ You cannot fully validate an in-cluster config locally

Try it:
```bash
K8S_NODE_NAME=x GATEWAY_ENDPOINT=g:4317 \
  otelcol-contrib validate --config=collector-configs/agent-config.yaml
```

**It fails in three layers**, each revealing something:

```
# Layer 1 — no env vars at all
exporters::otlp/gateway: requires a non-empty "endpoint"
processors::k8sattributes::filter: `node_from_env_var` is configured but
  envvar "K8S_NODE_NAME" is not set

# Layer 2 — set those two
failed creating k8snode detector: failed to create K8s API client:
  KUBERNETES_SERVICE_HOST and KUBERNETES_SERVICE_PORT must be defined

# Layer 3 — set those too
failed to create K8s API client: open
  /var/run/secrets/kubernetes.io/serviceaccount/token: no such file or directory
```

★ **Layer 3's path is a CONSTANT — not configurable.** There's no way to satisfy it without a real mounted service-account token.

**The asymmetry worth knowing:** `k8sattributes` with `auth_type: serviceAccount` **validates fine** outside a cluster (it defers client creation), but `resourcedetection`'s `k8snode` detector **does not**.

**The CI workaround** (verified — this is how these configs were checked):
```bash
sed 's/detectors: \[env, k8snode, system\]/detectors: [env, system]/' \
  agent-config.yaml > /tmp/agent-ci.yaml
K8S_NODE_NAME=x GATEWAY_ENDPOINT=g:4317 otelcol-contrib validate --config=/tmp/agent-ci.yaml
# → VALIDATES CLEAN
```

★ **Validate a cluster-free variant in CI; let a canary verify the real one in-cluster.**

**Also note the error prefixes** — they tell you which stage failed:

| Prefix | Stage |
|---|---|
| `cannot unmarshal the configuration` | **schema** — wrong key or type |
| `<section>::<component>:` | **`Validate()`** — parsed fine, value rejected |
| `service::pipelines::X: references ...` | **wiring** — component not configured |
| `failed to build pipelines:` | **incompatible combination** at build time |

---

## Exercise 4 — ★★ `k8sattributes` fails silently without RBAC

Delete the ClusterRoleBinding:
```bash
kubectl delete clusterrolebinding otel-collector-k8sattributes
kubectl -n otel-lab rollout restart daemonset/otel-collector-agent
```

**The agent starts fine. It enriches NOTHING. No error.** Your spans lose `k8s.namespace.name`, `k8s.deployment.name`, `k8s.pod.name` — and every dashboard grouped by namespace goes blank.

Restore:
```bash
kubectl apply -f manifests/00-namespace.yaml
```

**Two more verified `k8sattributes` facts:**

1. ★ **The extractor key is `tag_name`, NOT `tag`:**
   ```
   'extract.labels[0]' has invalid keys: tag
   ```
   `FieldExtractionRule` fields are `tag_name`, `key`, `from`, `regex`. `tag_name` = the attribute to **emit**; `key` = the label to **read**; `from` ∈ `pod|namespace|node`.

2. ★ **Gates `k8sattributes.DontEmitV0K8sConventions` and `...EmitV1K8sConventions` are both TRUE.** You get v1 semconv names (`k8s.namespace.name`, `k8s.deployment.name`) and **not** the old v0 names (`k8s.namespace`, `k8s.deployment`). Dashboards written against the old names silently return nothing.

**And the DaemonSet-specific one:**
```yaml
    filter:
      node_from_env_var: K8S_NODE_NAME     # ★ scope the watch to THIS node
```
Without it, **every agent watches every pod in the cluster** — N agents × full-cluster watch = N× the API server load and memory.

---

## Exercise 5 — ★★ Changing a ConfigMap does not restart the pods

```bash
kubectl -n otel-lab edit configmap otel-collector-gateway-config
# change decision_wait: 10s -> 20s, save
kubectl -n otel-lab get pods     # ★ nothing happened
```

Kubernetes propagates the new content to the mounted file (eventually, up to ~1 minute), but **the Collector reads its config once at startup.** Your `apply` succeeded, the ConfigMap updated, and the running Collectors keep the old config **indefinitely**.

**Three ways to actually roll:**

| Method | Survives `git pull && kubectl apply`? |
|---|---|
| ★ **`checksum/config` annotation** on the pod template | **Yes** — content hash changes → pod template changes → rollout |
| `kubectl rollout restart statefulset/...` | No — manual |
| Collector `confmap` HTTP provider + partial reload (gate `service.partialReloadReceivers` TRUE/Beta) | Reloads **receivers only**, not the whole config |

Helm's idiom: `{{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}`. Kustomize's `configMapGenerator` does it automatically by appending a content hash to the ConfigMap **name**.

---

## Exercise 6 — ★ The distroless image breaks your probes

```bash
kubectl -n otel-lab exec deploy/otel-collector-agent -- sh
# OCI runtime exec failed: unable to start container process:
# exec: "sh": executable file not found in $PATH
```

★ **`otel/opentelemetry-collector-contrib` has NO shell, NO curl, NO wget, NO apk.** So:

| Doesn't work | Use instead |
|---|---|
| `exec` probes | **`httpGet`** against the `health_check` extension |
| Dockerfile `HEALTHCHECK CMD ...` | Probe from **outside** the container |
| `kubectl exec ... -- curl localhost:13133` | `kubectl port-forward` + curl from your host |
| Debugging with a shell | ★ **`debug` exporter** with `verbosity: detailed`, or ephemeral containers |

**And the binding trap:**
```yaml
  health_check:
    endpoint: 0.0.0.0:13133    # ★ NOT localhost
```
★ **The default is localhost.** The kubelet probes the **pod IP**, which is not localhost from its perspective — so a default binding makes every probe fail and Kubernetes **restart-loops a perfectly healthy Collector.** Same trap applies to `service.telemetry.metrics.readers[].pull.exporter.prometheus.host`.

---

## Exercise 7 — ★ Memory sizing for tail sampling

The gateway requests **2Gi**, and the agent only **512Mi**. That gap is not arbitrary:

```
tail_sampling memory ≈ num_traces × avg_trace_size + decision caches
                      ≈ 50,000 × ~10KB          + 2 × 500,000 entries
                      ≈ 500MB of BUFFER ALONE
```

**512Mi would OOMKill.** And ★ `memory_limiter.limit_percentage: 80` is relative to the **container limit**, so it fires at ~1.6Gi. **These two numbers must be set together** — raising one without the other does nothing.

**Now break it:**
```bash
kubectl -n otel-lab patch statefulset otel-collector-gateway --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"512Mi"}]'
kubectl -n otel-lab get pods -w
```

Watch for **OOMKilled**. ★ Note the difference: with `memory_limiter` the Collector **sheds data and stays up**; without it (or when the limit is too low to leave headroom) the **kernel kills the container** and you lose every buffered trace plus a cold restart.

Also note:
```yaml
          resources:
            requests:
              cpu: 500m
              memory: 2Gi
            limits:
              memory: 2Gi       # ★ memory limit only — CPU left Burstable
```
★ **`requests == limits` for memory ⇒ Guaranteed QoS ⇒ evicted LAST.** CPU is deliberately left as a request only, so an agent can **burst during an incident** instead of being throttled at exactly the wrong moment.

---

## Exercise 8 — ★ HPA on queue saturation, not CPU

```yaml
    - type: Pods
      pods:
        metric:
          name: otelcol_exporter_queue_size_ratio
        target:
          type: AverageValue
          averageValue: "600m"     # ★ scale at 60% queue fill
```

★ **A Collector's CPU is a poor scaling signal.** It's dominated by batching and compression, and it stays flat **while the export queue fills up.** The metric that actually predicts data loss is **queue saturation.**

Note the asymmetric scaling behaviour:
```yaml
    scaleUp:
      stabilizationWindowSeconds: 60     # ★ FAST — telemetry loss is unrecoverable
    scaleDown:
      stabilizationWindowSeconds: 600    # ★ SLOW — each removed replica discards its buffer
```

★ **And `maxReplicas` interacts with `load_balancing`:** more replicas means more backend endpoints, and a rebalance re-routes traces mid-flight. Scale in small steps.

**Requires** the Prometheus Adapter exposing `otelcol_exporter_queue_size / queue_capacity` as a custom metric.

---

## Exercise 9 — ★ Anti-affinity: `preferred`, not `required`

```yaml
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:   # ★ NOT `required`
            - weight: 100
              podAffinityTerm:
                topologyKey: kubernetes.io/hostname
```

Spreading replicas across nodes means one node failure loses **at most one** replica's buffered traces. Without it the scheduler happily stacks all three on one node.

★ **Why `preferred`:** `required` makes the StatefulSet **unable to schedule** when you have fewer nodes than replicas — which in a dev cluster means pods stuck **Pending forever** with a confusing event.

Test on a single-node cluster:
```bash
kubectl -n otel-lab get pods -o wide      # all three on the same node — fine, preferred
kubectl -n otel-lab describe pod otel-collector-gateway-2 | tail -5
```

---

## Exercise 10 — ★★ Zero-code injection: the annotation must be on the POD TEMPLATE

```yaml
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-python: "true"   # ★ HERE
```

**The most common failure:** putting it on `metadata.annotations` (the Deployment) instead of `spec.template.metadata.annotations` (the pod template). **Nothing happens, nothing errors, and no init container appears** — the webhook watches **pods**.

**Verify injection worked:**
```bash
kubectl -n otel-lab get pod -l app=checkout -o jsonpath='{.items[0].spec.initContainers[*].name}'
# expect something like: opentelemetry-auto-instrumentation-python
kubectl -n otel-lab exec deploy/checkout -- env | grep OTEL_
```

**Other verified injection facts:**

| Fact | Detail |
|---|---|
| Language-specific keys | `inject-python`, `inject-java`, `inject-nodejs`, `inject-dotnet`, `inject-go`, `inject-nginx`, `inject-apache-httpd`, `inject-sdk` |
| Value | `"true"` (namespace default CR) or the **name** of a specific `Instrumentation` CR |
| ★ Multi-container pods | `instrumentation.opentelemetry.io/container-names: "a,b"` — else injection targets are ambiguous |
| ★ Init containers | Must be named explicitly: `container-names: "my-init-job,myapp"` |
| ★ **Sidecar is a DIFFERENT annotation** | `sidecar.opentelemetry.io/inject` adds a Collector **container**; `instrumentation.../inject-*` adds an **agent to your container** |
| ★★ **Python/.NET default to HTTP** | They must point at **:4318**, not :4317 — see below |

### ★★ The Python port asymmetry

```yaml
  python:
    env:
      - name: OTEL_EXPORTER_OTLP_ENDPOINT
        value: http://otel-collector-agent.otel-lab.svc.cluster.local:4318   # ★ 4318
  java:
    env:
      - name: OTEL_EXPORTER_OTLP_ENDPOINT
        value: http://otel-collector-agent.otel-lab.svc.cluster.local:4317   # ★ 4317
```

★ **Python (and .NET) auto-instrumentation uses HTTP/protobuf by default, not gRPC.** Point it at 4317 and the Python service **silently exports nothing while every other language works.** A maddening asymmetry to debug, because nothing logs an error — it just retries against a port that isn't listening for that protocol.

### ★★ `unknown_service` — the label opt-in

```yaml
  defaults:
    useLabelsForResourceAttributes: true
```

★ **Off by default.** Without it the Operator does **not** derive resource attributes from the recommended Kubernetes labels, so every service reports as `unknown_service:python` and all your dashboards collapse into one bucket. With it:

| Kubernetes label | → Resource attribute |
|---|---|
| `app.kubernetes.io/name` | `service.name` |
| `app.kubernetes.io/version` | `service.version` |
| `app.kubernetes.io/instance` | `service.instance.id` |

---

## Exercise 11 — ★★ Three v1alpha1 → v1beta1 changes that break old manifests

Verified against the Operator's own `crd-changelog.md`:

### 1. `spec.config` became a STRUCTURED OBJECT

```yaml
# v1alpha1                              # v1beta1
config: |                               config:
  receivers:                              receivers:
    otlp:                                   otlp:
      protocols:                              protocols:
        grpc:                                   grpc: {}      # ★ explicit empty map
```
★ **A bare `grpc:` yields null and fails.** With a structured object an empty mapping must be written `{}`.

### 2. Label selectors gained `matchLabels`

```yaml
# v1alpha1                              # v1beta1
serviceMonitorSelector:                 serviceMonitorSelector:
  key: value                              matchLabels:
                                            key: value
```

### 3. ★★ `targetAllocator` became a SEPARATE CRD

```yaml
# v1alpha1 — nested on the Collector
spec:
  targetAllocator:
    enabled: true
    prometheusCR: {enabled: true}

# v1beta1 — its own CR, linked by a LABEL
metadata:
  labels:
    opentelemetry.io/target-allocator: otel-ta
---
apiVersion: opentelemetry.io/v1alpha1
kind: TargetAllocator
metadata: {name: otel-ta}
spec:
  prometheusCR: {enabled: true}
```
★ **The old nested form is silently ignored** — your scrape targets just vanish.

★ **And `Instrumentation` did NOT move.** It's still `opentelemetry.io/v1alpha1`. Mixing the two API versions in one file is correct, not a typo.

### ★★ The Operator does not validate your config

Two verified surprises:

**a)** A Collector CR whose `prometheus` receiver has empty `scrape_configs` **does not validate standalone:**
```
receivers::prometheus: no Prometheus scrape_configs or target_allocator set
```
The receiver's rule (v0.161.0 README, verbatim): *"At least one of `config.scrape_configs`, `config.scrape_config_files`, or `target_allocator` must be set."* **The Operator injects `target_allocator` when it renders the ConfigMap.** Inject it yourself and you get a *second* error before it passes:
```
target_allocator: {endpoint: ...}
  -> receivers::prometheus::target_allocator: CollectorID is not a valid ID
target_allocator: {endpoint, interval, collector_id}
  -> VALIDATES CLEAN
```
So the rendered block is:
```yaml
prometheus:
  target_allocator:
    endpoint: http://otel-ta:8080
    interval: 30s
    collector_id: <pod name>       # ★ per-replica, so the TA can shard targets
```

**b)** ★ **The TA requires the receiver be named EXACTLY `prometheus`.** `prometheus/gateway` does not work — the TA looks it up by that literal name. (Lab 04 used suffixed names deliberately, because there's no TA there.)

★ **The lesson: you cannot fully CI-validate an Operator-managed Collector config**, because part of it doesn't exist until the Operator renders it. Validate a variant with the injected block added, and treat the CR alone as **not self-sufficient**.

---

## Exercise 12 — ★★ Monitor the Collector itself

**The thing people forget:** the Collector is infrastructure, so it needs the same SLOs as anything else. **If it dies silently you get a GREEN dashboard and NO DATA — which reads as "everything is fine."**

Apply the 12 alerts:
```bash
kubectl apply -f manifests/05-workload-and-monitoring.yaml
kubectl -n otel-lab get prometheusrule otel-collector -o jsonpath='{.spec.groups[*].name}'
```

**The four questions they answer:**

| Question | Metrics | Alerts |
|---|---|---|
| **Is it alive?** | `up`, `otelcol_process_uptime` | `CollectorDown` |
| **Is it receiving?** | ★ `otelcol_receiver_accepted_spans` | **`CollectorReceivingNoData`** |
| **Is it LOSING data?** | `refused` / `dropped` / `send_failed` / `enqueue_failed` | 4 alerts |
| **Is it about to fail?** | queue ratio, `memory_rss`, tail-sampling internals | 5 alerts |

★ **The single most important one:**
```promql
sum(rate(otelcol_receiver_accepted_spans[5m])) by (job) == 0 and on(job) up == 1
```
**Up but accepting nothing.** Without this, a broken pipeline presents as a dashboard with no data — indistinguishable from a quiet system at 3am.

**The loss ladder, in the order data dies:**

| Stage | Metric | Meaning |
|---|---|---|
| 1 | `otelcol_exporter_queue_size` / `queue_capacity` > 0.8 | ★ **Leading indicator** — scale now |
| 2 | `otelcol_exporter_send_failed_*` | Backend rejecting/unreachable; retry is masking it |
| 3 | `otelcol_receiver_refused_*` | ★ `memory_limiter` shedding — you're undersized |
| 4 | `otelcol_exporter_enqueue_failed_*` | ★★ Queue **FULL**, discarding before queueing |

★ **Do not "fix" stage 1 by raising `queue_size`.** A bigger queue delays the failure and makes the eventual loss **larger**.

**And for tail sampling specifically** (see [Lab 03](../lab-03-sampling/)):

| Alert | Why |
|---|---|
| `TailSamplingBufferEvicting` | ★ `sampling_trace_dropped_too_early > 0` = **eviction, not sampling** |
| `TailSamplingRemovalAgeNearDecisionWait` | ★ **Leading** indicator — p1 removal age approaching `decision_wait` |
| `TailSamplingDecisionTooSlow` | p99 > 1s ⇒ decisions land after `decision_wait`; usually a **slow exporter** |
| `TailSamplingPolicyEvaluationError` | ★ A policy that errors is **silently doing nothing** — usually a typo'd attribute key |

---

## The red flags

| Symptom | ★ Cause |
|---|---|
| **`references receiver "load_balancing/x" which is not configured`** | **It's an EXPORTER only** — not a connector, not a receiver. Route from the agent tier |
| **`'resolver.dns' ... 'port' expected type 'string', got int`** | ★ **`port: "4317"`** — the one string port in a Collector config |
| **Partial traces in a multi-replica gateway** | **No consistent traceID routing.** Spans spread across replicas; each decides on a fragment |
| **`load_balancing` sees one backend** | **Service isn't headless.** Need `clusterIP: None` for per-pod DNS records |
| **`k8s.*` attributes all missing, no errors** | ★ **RBAC.** `k8sattributes` needs LIST/WATCH on pods |
| **`'extract.labels[0]' has invalid keys: tag`** | ★ **The key is `tag_name`**, not `tag` |
| **Old `k8s.namespace` names missing** | **Gates emit v1 semconv** (`k8s.namespace.name`) |
| **ConfigMap changed, nothing happened** | ★ **Collectors read config at startup.** Need the `checksum/config` annotation |
| **CrashLoopBackOff, probe failing, app looks healthy** | ★ **`health_check` bound to localhost.** The kubelet probes the pod IP |
| **`exec: "sh": not found`** | ★ **Distroless image.** Use `httpGet` probes, `debug` exporter |
| **Gateway OOMKilled** | **512Mi can't hold `num_traces: 50000`.** Buffer alone ≈ 500MB |
| **`limit_percentage` seems ignored** | **It's relative to the CONTAINER limit.** Set both together |
| **Injection annotation does nothing** | ★ **On the Deployment instead of the POD TEMPLATE** |
| **Python exports nothing, Java works** | ★★ **Python/.NET default to HTTP → :4318, not :4317** |
| **Everything is `unknown_service:python`** | ★ **`defaults.useLabelsForResourceAttributes` is off by default** |
| **TA finds no targets** | **Receiver not named exactly `prometheus`**, or ServiceMonitor missing the TA selector label |
| **`no Prometheus scrape_configs or target_allocator set`** | **Operator injects `target_allocator` at render time** — the CR isn't self-sufficient |
| **Old nested `targetAllocator:` ignored** | ★ **It's a separate CRD in v1beta1**, linked by a label |
| **`spec.config` string rejected** | **v1beta1 wants a structured object**; empty maps need `{}` |
| **Dashboard green but no data** | ★ **You're not alerting on `accepted_spans == 0 and up == 1`** |

## Rapid recall

- **Agent = DaemonSet = enrich + filter + ROUTE. Gateway = StatefulSet = SAMPLE + fan out.**
- **Routing before sampling is a CORRECTNESS requirement**, not an optimisation.
- `load_balancing` is **exporter-only**; `routing_key` is **top-level**; `resolver.dns.port` is a **STRING**.
- `routing_key`: `traceID` invalid for metrics; **`streamID`** is what `delta_to_cumulative` needs; metrics routing is **Alpha**.
- Gateway needs a **headless Service** for per-pod DNS.
- **You cannot fully validate an in-cluster config locally** — `k8snode` needs a real SA token at a **constant** path.
- `k8sattributes` extractor key is **`tag_name`**; needs **RBAC**; emits **v1 semconv** names.
- **ConfigMap changes don't restart pods** — use the **`checksum/config`** annotation.
- **Distroless** ⇒ `httpGet` probes, and `health_check` must bind **0.0.0.0**.
- **`requests == limits` for memory** ⇒ Guaranteed QoS ⇒ evicted last. **CPU left Burstable** on purpose.
- **HPA on queue saturation, not CPU.** Scale **up fast, down slow**.
- v1beta1: **structured `config`**, **`matchLabels`** selectors, **`TargetAllocator` is a separate CRD**. `Instrumentation` stays **v1alpha1**.
- **TA requires the receiver be named exactly `prometheus`**; it injects `endpoint` + `interval` + `collector_id`.
- Python/.NET default to **HTTP :4318**; Java/Node to **gRPC :4317**.
- ★ **Alert on `accepted_spans == 0 and up == 1`** or a dead pipeline looks like a quiet system.

---

## What you should now be able to answer

1. Agent or gateway for tail sampling? → ★ **Gateway. An agent sees only fragments of a trace, so its decision is made on partial data — worse than no decision.**
2. Why a StatefulSet? → **Stable identities + per-replica PVCs, so `load_balancing` can route by trace ID and a restart doesn't discard the queue.**
3. Where does `load_balancing` go? → ★ **The routing tier (agent). It's an exporter only — it cannot bridge pipelines in one process.**
4. Why can't I validate my config in CI? → **`resourcedetection`'s `k8snode` builds a real API client needing an SA token at a constant path. Validate a cluster-free variant; canary the real one.**
5. Why are my `k8s.*` attributes empty? → **RBAC. `k8sattributes` starts fine and enriches nothing.**
6. I changed the ConfigMap and nothing happened. → ★ **Collectors read config at startup. Add the `checksum/config` pod-template annotation.**
7. My Collector is crash-looping but looks healthy. → **`health_check` bound to localhost; the kubelet probes the pod IP.**
8. Python services export nothing. → ★★ **They default to HTTP/protobuf → :4318, not :4317.**
9. Everything is `unknown_service`. → **`defaults.useLabelsForResourceAttributes` is off; enable it and set the `app.kubernetes.io/*` labels.**
10. What's the one alert I must not skip? → ★ **`accepted_spans == 0 and up == 1`. Otherwise a dead pipeline looks like a quiet system.**

→ Back: [`../README.md`](../README.md) · Topic: [`../../12-collector-in-kubernetes.md`](../../12-collector-in-kubernetes.md)
