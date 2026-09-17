# 12 · The Collector in Kubernetes

Deployment topologies, the Operator, the Target Allocator, and auto-instrumentation injection. Verified against **opentelemetry-operator v0.158.0** (chart **0.122.0**), **Target Allocator v0.158.0** (chart **0.158.0**), **`opentelemetry-collector` chart 0.172.0**, **`opentelemetry-kube-stack` chart 0.20.5**, and Collector **v0.161.0**.

---

## 12.1 The three deployment modes

Every real Kubernetes OTel deployment is some combination of these. **Knowing which to use, and why, is the core platform-engineering decision here.**

| Mode | Topology | Best for | Fails at |
|---|---|---|---|
| **Agent — DaemonSet** | One Collector per **node** | Node/host metrics (`host_metrics`), log file tailing (`file_log` on `/var/log`), eBPF-based receivers, first-hop ingestion | Anything needing a whole-trace view (a trace's spans span many nodes) |
| **Agent — Sidecar** | One Collector per **pod** | Workloads that must not share infrastructure, strong tenant isolation, per-pod config | ★ **Resource overhead × pod count.** 500 pods × 100 MB = 50 GB of Collector |
| **Gateway — Deployment** | A shared, load-balanced fleet | Tail sampling, span metrics, enrichment, redaction, fan-out, vendor egress | Cannot read node-local files or scrape node-local endpoints |

★ **The standard production topology is two tiers**, and it's what upstream recommends for tail sampling:

```
                    ┌──────────────── per node ────────────────┐
 app pods ─OTLP──▶  │  AGENT (DaemonSet)                       │
                    │  - receives OTLP from local pods          │
                    │  - host_metrics, file_log, k8s_events     │
                    │  - k8s_attributes enrichment              │
                    │  - memory_limiter, batch                  │
                    └───────────────┬──────────────────────────┘
                                    │ OTLP (load_balancing, routing_key: traceID)
                    ┌───────────────▼──────────────────────────┐
                    │  GATEWAY (Deployment, N replicas)        │
                    │  - tail_sampling  (stateful, memory-heavy)│
                    │  - span_metrics / service_graph          │
                    │  - redaction / PII scrubbing             │
                    │  - cardinality_guardian                  │
                    │  - export to backends + vendors          │
                    └──────────────────────────────────────────┘
```

**Why separate them** (upstream's stated reason is *"better failure isolation"*):
- The **agent tier is stateless** and cheap. If one dies, only that node's telemetry is affected, and the kubelet restarts it in seconds.
- The **gateway tier is stateful** (`tail_sampling` holds traces in memory). It OOMs under load spikes. **You do not want the thing that receives from 500 application pods to be the thing that OOMs.**
- Scaling is independent: agents scale with nodes, gateways scale with trace volume.
- Config changes to sampling policy don't restart every node agent.

**When one tier is enough:** small clusters (< ~20 nodes), no tail sampling, single backend. A single Deployment gateway with apps pointing straight at it is simpler and legitimate. **Say so rather than building a two-tier fleet you can't staff.**

**When sidecars are worth the cost:** genuinely untrusted or regulated workloads, per-tenant routing at the pod level, or applications that must not depend on node-local infrastructure. ★ Note that a sidecar Collector is *also* what a service mesh proxy is — if you're running both, ask whether the mesh can do the telemetry job.

---

## 12.2 Installing the Operator

```bash
# Cert-manager is a prerequisite for the admission webhooks
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --for=condition=Available deployment/cert-manager-webhook \
  -n cert-manager --timeout=5m

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install otel-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry-operator-system --create-namespace \
  --version 0.122.0 \
  --set manager.collectorImage.repository="otel/opentelemetry-collector-contrib"
```
★ **The default `collectorImage` is the *core* `otelcol`, not contrib.** Most configs assume contrib components (`host_metrics`, `file_log`, `k8s_attributes`, `tail_sampling`). **Set the repository to `otel/opentelemetry-collector-contrib`** or you'll get "unknown receiver/processor" errors on your first CR. This is the single most common Operator mistake.

**Pin the version.** Chart `0.122.0` bundles Operator app version `v0.158.0`.

---

## 12.3 The `OpenTelemetryCollector` CRD

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-agent
  namespace: observability
spec:
  mode: daemonset                  # daemonset | deployment | statefulset | sidecar
  image: otel/opentelemetry-collector-contrib:0.161.0   # ★ pin by digest in production
  replicas: 1                      # ignored for daemonset
  serviceAccount: otel-agent
  # upgradeStrategy: automatic     # automatic | none | (operator-managed)
  resources:
    requests: {cpu: 100m, memory: 256Mi}
    limits:   {cpu: 500m, memory: 512Mi}    # ★ memory_limiter must sit below this
  podAnnotations:
    prometheus.io/scrape: "true"
  env:
    - name: K8S_NODE_NAME
      valueFrom:
        fieldRef: {fieldPath: spec.nodeName}
  volumes:
    - name: varlog
      hostPath: {path: /var/log, type: Directory}
    - name: varlibotel
      hostPath: {path: /var/lib/otelcol, type: DirectoryOrCreate}
  volumeMounts:
    - name: varlog
      mountPath: /var/log
      readOnly: true
    - name: varlibotel
      mountPath: /var/lib/otelcol
  ports:
    - name: otlp-grpc
      port: 4317
      protocol: TCP
    - name: otlp-http
      port: 4318
      protocol: TCP
  config:
    extensions:
      health_check: {endpoint: 0.0.0.0:13133}
    receivers:
      otlp:
        protocols:
          grpc: {endpoint: 0.0.0.0:4317}
          http: {endpoint: 0.0.0.0:4318}
      host_metrics:
        collection_interval: 30s
        scrapers: {cpu: , memory: , disk: , filesystem: , network: , load: }
      file_log:
        include: [/var/log/pods/*/*/*.log]
        start_at: end
        exclude:
          - /var/log/pods/observability_otel-agent-*/*/*.log     # ★ don't ingest your own logs
      k8s_events:
        namespaces: []           # all namespaces
    processors:
      memory_limiter:
        check_interval: 1s
        limit_percentage: 80
        spike_limit_percentage: 25
      k8s_attributes:
        auth_type: serviceAccount
        passthrough: false
        extract:
          metadata:
            - k8s.namespace.name
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.deployment.name
            - k8s.node.name
            - k8s.container.name
        pod_association:
          - sources: [{from: resource_attribute, name: k8s.pod.ip}]
          - sources: [{from: connection}]
      resource_detection:
        detectors: [env, system]
        timeout: 5s
        override: false
      batch:
        send_batch_size: 8192
        timeout: 5s
    exporters:
      load_balancing:
        routing_key: "traceID"
        protocol:
          otlp:
            timeout: 1s
            sending_queue: {enabled: true}
        resolver:
          dns: {hostname: otel-gateway-headless.observability.svc.cluster.local}
      otlp_grpc/gateway:
        endpoint: otel-gateway-collector.observability.svc.cluster.local:4317
        tls: {insecure: true}
    service:
      extensions: [health_check]
      telemetry:
        metrics:
          level: detailed
          readers:
            - pull:
                exporter:
                  prometheus: {host: 0.0.0.0, port: 8888}
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, k8s_attributes, batch]
          exporters: [load_balancing]
        metrics:
          receivers: [otlp, host_metrics]
          processors: [memory_limiter, k8s_attributes, resource_detection, batch]
          exporters: [otlp_grpc/gateway]
        logs:
          receivers: [otlp, file_log, k8s_events]
          processors: [memory_limiter, k8s_attributes, batch]
          exporters: [otlp_grpc/gateway]
```

### The `mode` field
| Mode | What the Operator creates | Notes |
|---|---|---|
| **`daemonset`** | A DaemonSet | One pod per node. Ignores `replicas` |
| **`deployment`** | A Deployment + Service | The gateway pattern. `replicas` honoured |
| **`statefulset`** | A StatefulSet | Stable identity; needed for `load_balancing` with `return_hostnames` |
| **`sidecar`** | Nothing standalone — **injected** into pods | ★ Requires the annotation `sidecar.opentelemetry.io/injected: "<collector-name>"` on the target pod |

★ **Sidecar injection is annotation-driven**, and the Operator's mutating webhook does the injection. If the annotation is present and no sidecar appears, check that the webhook is running and that `admissionWebhooks.failurePolicy` isn't silently failing.

### Gateway CR (paired with the agent above)
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-gateway
  namespace: observability
spec:
  mode: deployment
  replicas: 3
  image: otel/opentelemetry-collector-contrib:0.161.0
  resources:
    requests: {cpu: 500m, memory: 1Gi}
    limits:   {cpu: "2",   memory: 4Gi}     # ★ tail_sampling is memory-hungry
  config:
    receivers:
      otlp:
        protocols: {grpc: {endpoint: 0.0.0.0:4317}, http: {endpoint: 0.0.0.0:4318}}
    processors:
      memory_limiter: {check_interval: 1s, limit_percentage: 80, spike_limit_percentage: 25}
      tail_sampling:
        decision_wait: 10s
        num_traces: 100000
        expected_new_traces_per_sec: 1000
        maximum_trace_size_bytes: 5242880
        decision_cache:
          sampled_cache_size: 1000000
          non_sampled_cache_size: 1000000
        policies:
          - {name: errors, type: status_code, status_code: {status_codes: [ERROR]}}
          - {name: slow,   type: latency, latency: {threshold_ms: 1000}}
          - name: budget
            type: composite
            composite:
              max_total_spans_per_second: 5000
              policy_order: [errors, slow, baseline]
              composite_sub_policy:
                - {name: errors, type: status_code, status_code: {status_codes: [ERROR]}}
                - {name: slow, type: latency, latency: {threshold_ms: 2000}}
                - {name: baseline, type: always_sample}
              rate_allocation:
                - {policy: errors, percent: 40}
                - {policy: slow, percent: 30}
      redaction:
        blocked_values:
          - '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+'
      batch: {send_batch_size: 8192, timeout: 5s}
    connectors:
      span_metrics:
        histogram:
          explicit:
            buckets: [5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s]
        dimensions: [{name: http.route}, {name: http.response.status_code}]
        dimensions_cache_size: 1000
        aggregation_temporality: AGGREGATION_TEMPORALITY_CUMULATIVE
    exporters:
      otlp_grpc/tempo: {endpoint: tempo:4317, tls: {insecure: true}}
      prometheus_remote_write:
        endpoint: http://mimir:9009/api/v1/push
        sending_queue: {enabled: true, queue_size: 5000, num_consumers: 10}
        retry_on_failure: {enabled: true, initial_interval: 5s, max_interval: 30s, max_elapsed_time: 300s}
      # ★ There is NO `loki` exporter in v0.161.0 — `loki` is a RECEIVER only.
      #   Use Loki's native OTLP endpoint; otlphttp appends /v1/logs.
      otlphttp/loki: {endpoint: http://loki:3100/otlp, tls: {insecure: true}}
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, tail_sampling, redaction, batch]
          exporters: [otlp_grpc/tempo, span_metrics]
        metrics:
          receivers: [otlp, span_metrics]
          processors: [memory_limiter, batch]
          exporters: [prometheus_remote_write]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, redaction, batch]
          exporters: [otlphttp/loki]
```

★ **Two details that break this if you miss them:**
1. **`span_metrics` appears in both pipelines** — as an exporter in `traces` and a receiver in `metrics`. Omit either and the Operator's Collector refuses to start.
2. **The agent's `load_balancing` DNS name must resolve to the gateway pods.** A headless Service (`clusterIP: None`) is required for DNS to return individual pod IPs rather than a VIP. With a normal ClusterIP Service, DNS returns one address and **all traces go to one replica** — which defeats the purpose and overloads one pod.

---

## 12.4 The Target Allocator ★

**The problem it solves:** the Collector's `prometheus` receiver scrapes targets. In Kubernetes, targets are dynamic (pods come and go), and a single Collector scraping thousands of targets doesn't scale.

**What it does:** a separate component that watches Kubernetes service discovery and Prometheus-Operator CRDs, then **distributes scrape targets across Collector replicas**, each of which scrapes its assigned subset via the `prometheus` receiver's HTTP-based target allocation.

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-prometheus
spec:
  mode: statefulset
  replicas: 3
  targetAllocator:
    enabled: true
    image: ghcr.io/open-telemetry/opentelemetry-operator/opentelemetry-target-allocator:0.158.0
    serviceAccount: otel-target-allocator
    allocationStrategy: consistent-hashing     # consistent-hashing | per-node | least-weighted
    prometheusCR:
      enabled: true
      serviceMonitorSelector: {}               # all ServiceMonitors
      podMonitorSelector: {}
      scrapeConfigSelector: {}
      probeSelector: {}
      # secretNamespaces: [observability, kube-system]   # ★ where to look for basicAuth secrets
    filterStrategy: relabel-job
    resources:
      requests: {cpu: 100m, memory: 256Mi}
      limits:   {cpu: 500m, memory: 512Mi}
  config:
    receivers:
      prometheus:                       # ★★ MUST be named exactly "prometheus"
        config:
          scrape_configs:
            - job_name: 'otel-collector'
              scrape_interval: 10s
              static_configs: [{targets: ['localhost:8888']}]
        # The Target Allocator injects target allocation automatically
    processors:
      memory_limiter: {check_interval: 1s, limit_percentage: 80, spike_limit_percentage: 25}
      batch: {timeout: 10s}
    exporters:
      prometheus_remote_write:
        endpoint: http://mimir:9009/api/v1/push
    service:
      pipelines:
        metrics:
          receivers: [prometheus]
          processors: [memory_limiter, batch]
          exporters: [prometheus_remote_write]
```

★ **The naming requirement is a hard, verified constraint.** From Operator v0.152.0 onwards, when the Target Allocator is enabled but the Prometheus receiver isn't named exactly `prometheus`, the error message lists the instances it found and explains the requirement:
> *"Improve the error message when the target allocator is enabled but the Prometheus receiver is not named exactly 'prometheus'. When only named instances such as `prometheus/otelcol` are present, the error now lists them and explains that a receiver named exactly `prometheus` is required."*

So `prometheus/otelcol` **will not work**. This costs people hours because the error used to be cryptic and the requirement is counter-intuitive.

### Allocation strategies
| Strategy | Behaviour | Use when |
|---|---|---|
| **`consistent-hashing`** | Hashes target → Collector. **Minimal reshuffling when replicas change** | Default and usually best |
| **`per-node`** | Each Collector scrapes targets on its own node | DaemonSet agents scraping node-local endpoints |
| **`least-weighted`** | Assigns to the least-loaded Collector | ★ **Since v0.145.0 this takes job name into account**, using job name instead of "first match" when target counts are equal — spreading same-job targets across Collectors |

### Operator/TA version notes worth knowing
| Version | Change |
|---|---|
| **v0.152.0** | ★ Auto-instrumentation mutating webhook can run with **static configuration, without CRDs** — deploy the manager as a webhook without installing the `Instrumentation` CRD. Also: TA can drop ServiceMonitor/PodMonitor endpoints referencing arbitrary files (a **security** control), and the `prometheus` receiver naming error message improved |
| **v0.151.0** | `spec.prometheusCR.secretNamespaces` — namespaces watched for `basicAuth`/secret references, instead of hardcoded to the Collector namespace. **If not configured, no namespaces are watched for secrets** |
| **v0.149.0** | Fixed init-container security context for auto-instrumentation; allowed the same container name across different language instrumentations; fixed a shallow-copy bug causing **Target Allocator Deployment infinite reconciliation loops** |
| **v0.147.0** | Fixed ServiceMonitor/PodMonitor not picking up **secret updates** |
| **v0.146.0** | Exposed `podMonitorNamespaceSelector`, `serviceMonitorNamespaceSelector`, `scrapeConfigNamespaceSelector`, `probeNamespaceSelector`, `evaluationInterval`, `scrapeProtocols` in the Operator API |
| **v0.145.0** | Readiness/liveness probes for the TA CRD; `least-weighted` job-name awareness; ★ **TLS certificate hot-reload for mTLS** via fsnotify — cert-manager renewals no longer need a pod restart |

### Target Allocator RBAC
```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: otel-target-allocator, namespace: observability}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: otel-target-allocator}
rules:
  - apiGroups: [""]
    resources: [pods, services, endpoints, nodes, namespaces]
    verbs: [get, list, watch]
  - apiGroups: [monitoring.coreos.com]
    resources: [servicemonitors, podmonitors, scrapeconfigs, probes]
    verbs: [get, list, watch]
  - apiGroups: [discovery.k8s.io]
    resources: [endpointslices]
    verbs: [get, list, watch]
```
★ **Missing `endpointslices` is a silent failure mode for `load_balancing` too** — the exporter's `k8s` resolver needs `get`/`list`/`watch` on `discovery.k8s.io/v1` `EndpointSlice`, and without it the resolver cache stays empty and logs `couldn't find the exporter for the endpoint ""`.

---

## 12.5 Auto-instrumentation via the `Instrumentation` CRD

The Operator injects language-specific instrumentation into pods via a **mutating admission webhook** and an **init container** that copies the agent/library into a shared volume.

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: otel-autoinstrumentation
  namespace: observability
spec:
  exporter:
    endpoint: http://otel-agent-collector.observability.svc.cluster.local:4317
  propagators: [tracecontext, baggage]        # ★ W3C by default — don't add b3/jaeger unless needed
  sampler:
    type: parentbased_traceidratio
    argument: "1.0"                            # ★ sample everything at the SDK; do tail sampling in the gateway
  env:
    - name: OTEL_RESOURCE_ATTRIBUTES
      value: deployment.environment.name=production
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.65b0
    env:
      - name: OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED
        value: "true"
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.31.0
    env:
      - name: OTEL_INSTRUMENTATION_HIBERNATE_ENABLED
        value: "true"
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.220.0
  dotnet:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-dotnet:1.13.0
  go:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-go:1.8.0
```

**Enable per-workload with an annotation:**
```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-python: "observability/otel-autoinstrumentation"
    # or: inject-java, inject-nodejs, inject-dotnet, inject-go
    # or: inject: "true"  → auto-detect / default
```

★ **Go auto-instrumentation is disabled by default in the Operator** and must be enabled with the `operator.autoinstrumentation.go` feature gate:
```bash
helm install otel-operator open-telemetry/opentelemetry-operator \
  --set 'manager.featureGates=operator.autoinstrumentation.go'
```
Go works differently from the others — it's **compile-time** instrumentation ([`09-sdks-and-instrumentation.md`](09-sdks-and-instrumentation.md)), so the Operator injects a build-time toolchain rather than a runtime agent. As of July 2026, Go compile-time instrumentation reached **v1**, which is what makes this viable at all.

### How injection actually works
1. The webhook sees a pod with the annotation.
2. It adds an **init container** carrying the language's instrumentation artefacts.
3. The init container copies them into an **emptyDir** shared with the app container.
4. It injects the launch configuration: `JAVA_TOOL_OPTIONS=-javaagent:...` for Java, `PYTHONPATH` + a wrapper for Python, `NODE_OPTIONS=--require ...` for Node, `CORECLR_ENABLE_PROFILING` for .NET.
5. It injects `OTEL_*` env vars from the `Instrumentation` spec.

### The real-world caveats ★
| Caveat | Detail |
|---|---|
| **Startup latency** | An init container that copies a 30 MB Java agent adds seconds to every pod start. At scale this lengthens deploys and slows scale-up |
| **Memory** | The Java agent adds tens of MB of heap. **If you don't raise the container's memory limit, you get OOMKills after enabling instrumentation** — the most common auto-instrumentation incident |
| **Restart required** | Injection happens at pod creation. Existing pods need a rollout |
| **Webhook availability** | ★ `admissionWebhooks.failurePolicy: Fail` means an Operator outage **blocks pod creation cluster-wide**. Scope the webhook's namespace/object selectors, or accept `Ignore` and lose injection during outages. This is the same trade-off as any mutating webhook |
| **Read-only root filesystems** | The shared emptyDir must be writable. PSA `restricted` namespaces need care |
| **Distortion of "zero-code"** | Your Dockerfile now depends on injected env vars. **Local runs won't have them**, so local vs production telemetry differs |
| **Version skew** | The injected agent version is pinned in the `Instrumentation` CR, not your app's dependency tree. Upgrading it is a platform action affecting every annotated workload — **canary it** |

**Recommendation:** auto-instrumentation is excellent for getting **baseline coverage across an estate fast**. For services where you need business-level spans, combine it with manual instrumentation (the agent and manual spans coexist fine — manual spans just nest inside the auto ones).

---

## 12.6 Kubernetes-specific enrichment

### `k8s_attributes` — the processor that makes K8s telemetry usable

Without it, your spans carry `service.name` and whatever the pod's own environment knows — which, notably, is **not** the Deployment name or the namespace, because a pod can't see those from inside.

```yaml
processors:
  k8s_attributes:
    auth_type: serviceAccount          # or passthrough
    passthrough: false                 # ★ true = only tag with pod IP, do no enrichment
    filter:
      namespace: observability         # restrict the watch — big clusters benefit
      node_from_env_var: K8S_NODE_NAME # DaemonSet: only watch this node's pods
    extract:
      metadata:
        - k8s.namespace.name
        - k8s.pod.name
        - k8s.pod.uid
        - k8s.deployment.name
        - k8s.replicaset.name
        - k8s.statefulset.name
        - k8s.daemonset.name
        - k8s.job.name
        - k8s.cronjob.name
        - k8s.node.name
        - k8s.container.name
        - k8s.cluster.uid
      annotations: [{tag_name: app.tag, key: example.com/tag, from: pod}]
      labels: [{tag_name: app.tier, key: tier, from: namespace}]
    pod_association:
      - sources:
          - {from: resource_attribute, name: k8s.pod.ip}
      - sources: [{from: connection}]
```

★ **`pod_association` is the part that decides whether enrichment works.** The processor must map an incoming telemetry item to a pod. Two mechanisms:
- **`from: connection`** — uses the source IP of the OTLP connection. ★ **Works only if the Collector sees the pod's real IP.** Behind a load balancer, a mesh proxy, or with SNAT enabled, this breaks silently and enrichment just doesn't happen.
- **`from: resource_attribute, name: k8s.pod.ip`** — the application supplies its own pod IP via the downward API:
  ```yaml
  env:
    - name: OTEL_RESOURCE_ATTRIBUTES
      value: "k8s.pod.ip=$(POD_IP)"
    - name: POD_IP
      valueFrom: {fieldRef: {fieldPath: status.podIP}}
  ```
  **This is more reliable and is the recommended path in gateway topologies**, where the agent isn't on the same node as the app.

**Always list `resource_attribute` first** so it's preferred when present, with `connection` as a fallback.

★ **`filter.node_from_env_var` on DaemonSets is a major scalability win.** Without it, **every** node agent watches **every** pod in the cluster — N agents × M pods of API traffic and memory. With it, each agent watches only its own node's pods.

### Semconv V0/V1 and `k8s_attributes` ★
Two feature gates control which Kubernetes attribute names are emitted, and **in v0.161.0 both are ON** (verified via `otelcol-contrib featuregate` — **not** `--help`, whose default string says otherwise and is wrong):
- `processor.k8sattributes.EmitV1K8sConventions` — **true (Beta)**
- `processor.k8sattributes.DontEmitV0K8sConventions` — **true (Beta)**

★ **So `k8s_attributes` emits V1 (new stable) names ONLY — the migration is already complete for this processor.** Practical consequences:

1. **Annotation/label tag names change shape.** From the processor's own config docs: `k8s.pod.annotations.<key>` becomes **`k8s.pod.annotation.<key>`** (*singular*) when `EmitV1K8sConventions` is enabled — ★ **and the same for `k8s.pod.labels.<key>` → `k8s.pod.label.<key>`.** A dashboard querying the plural form returns nothing. This is an easy, silent miss.
2. **To go back to legacy names you must disable BOTH gates** (note the `-` prefixes): `--feature-gates=-processor.k8sattributes.EmitV1K8sConventions,-processor.k8sattributes.DontEmitV0K8sConventions`.
3. ★ **`DontEmitV0` cannot be enabled without `EmitV1`.** The processor validates this and returns: `processor.k8sattributes.DontEmitV0K8sConventions cannot be enabled without enabling processor.k8sattributes.EmitV1K8sConventions`.
4. **Its own internal telemetry is new-format only** too (`telemetry.enableNewFormatMetrics` true, `telemetry.disableOldFormatMetrics` true).
5. ★ **The inconsistency risk is the real one, not volume.** `k8s_attributes` is V1-only while **`host_metrics` and `scraper.process` are still V0-only** (`EmitV1SystemConventions` false, Alpha). So in the same pipeline, Kubernetes attributes arrive under new names and host metrics under legacy ones. **A dashboard written against one convention silently misses the other** — the actual explanation for *"works for some services and not others."*

★ **Scalability note:** `processor.k8sattributes.ShareProcessorBetweenPipelines` is **false (Alpha)** by default. So **using `k8s_attributes` in three pipelines creates three separate Kubernetes API watchers.** On large clusters that's real API-server load and real memory. Enabling the gate shares instances with identical configuration across signal-type pipelines.

See [`04-semantic-conventions.md`](04-semantic-conventions.md) for the full verified gate table across every component.

---

## 12.7 `opentelemetry-kube-stack` — the batteries-included option

Chart **0.20.5**. Installs the Operator, Collectors (agent + gateway), Target Allocator, auto-instrumentation, and wires up dashboards and alerts — a single-chart observability stack for Kubernetes.

**Use it when:** you want a working Kubernetes observability baseline in an afternoon and don't need to hand-tune every component.
**Be careful when:** you have strong opinions about the Collector topology, or you're integrating with an existing Prometheus/Grafana stack that has its own conventions. **Read the values file thoroughly** — a batteries-included chart that you don't understand becomes an unowned system in six months.

---

## 12.8 Operating the fleet

### Resource sizing
| Tier | CPU | Memory | Driver |
|---|---|---|---|
| Agent (DaemonSet) | 100–500m | 256Mi–1Gi | Volume from local pods + file tailing |
| Gateway (Deployment) | 0.5–2 | **2–8Gi** | ★ `tail_sampling` buffer: `num_traces × trace size` + decision caches |
| Target Allocator | 100–500m | 256Mi–1Gi | Target count and churn |

★ **Set the container memory limit and `memory_limiter.limit_percentage` together.** With `limit_percentage: 80` and a 4Gi limit, the limiter fires at 3.2Gi — leaving 800Mi of headroom before the kernel OOMKills. **If you omit `memory_limiter`, the container OOMKills instead of shedding**, which loses all buffered telemetry and restarts cold.

### Autoscaling the gateway
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: otel-gateway, namespace: observability}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: otel-gateway-collector}
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: memory
        target: {type: Utilization, averageUtilization: 70}
    - type: Pods
      pods:
        metric: {name: otelcol_receiver_accepted_spans}
        target: {type: AverageValue, averageValue: "10000"}
```
★ **The scaling trap specific to `tail_sampling`:** scaling changes the `load_balancing` backend list, which **reroutes ~R/N of traces** — and traces mid-decision on a departing replica are lost or re-decided independently. Mitigations: scale in **small increments**, use `consistent-hashing` routing, keep `decision_wait` short relative to scaling events, and prefer **scaling up before load arrives** (predictive/scheduled) over reactive scaling. **A tail-sampling fleet that autoscales aggressively loses data.**

### Rolling deploys
- **`terminationGracePeriodSeconds` must exceed the pipeline drain time.** With `decision_wait: 10s` plus batch timeouts, 30s (the default) is marginal — **use 60s**.
- **`preStop: sleep 10`** lets the Service/EndpointSlice update propagate before the pod stops accepting, so the upstream `load_balancing` resolver stops sending before connections break.
- ★ **`drop_pending_traces_on_shutdown`** (default `false`) means a shutting-down `tail_sampling` **decides on partial data** rather than dropping. That's usually what you want — you get a trace, possibly incomplete, rather than nothing.
- Update the `load_balancing` resolver's view: with `dns`, the interval defaults to **5s**; with `k8s`, `timeout` defaults to **1m** but updates arrive faster via EndpointSlice watches.

### Monitoring the Collector itself
Scrape `:8888` from Prometheus and alert on:
```yaml
groups:
- name: otel-collector
  rules:
  - alert: OTelCollectorRejectingData
    expr: sum(rate(otelcol_receiver_refused_spans[5m])) by (k8s_pod_name) > 0
    for: 5m
    annotations:
      summary: "Collector {{ $labels.k8s_pod_name }} is refusing spans (memory_limiter firing?)"
  - alert: OTelCollectorExportFailing
    expr: sum(rate(otelcol_exporter_send_failed_spans[5m])) by (k8s_pod_name) > 0
    for: 5m
  - alert: OTelCollectorQueueFilling
    expr: otelcol_exporter_queue_size / otelcol_exporter_queue_capacity > 0.8
    for: 5m
    annotations:
      summary: "Export queue >80% full — data loss imminent"
  - alert: OTelTailSamplingDroppingTraces
    expr: rate(otelcol_processor_tail_sampling_sampling_trace_dropped_too_early[5m]) > 0
    for: 5m
    annotations:
      summary: "Traces evicted before their sampling decision — raise num_traces or lower decision_wait"
  - alert: OTelCollectorHighMemory
    expr: container_memory_working_set_bytes{container="otel-collector"}
          / kube_pod_container_resource_limits{resource="memory"} > 0.85
    for: 10m
```
★ **`OTelCollectorQueueFilling` is the highest-value alert in this list.** Queue depth is a **leading** indicator — it rises minutes before `send_failed` does. Everything else is a lagging confirmation that you already lost data.

---

## 12.9 `opentelemetry-kube-stack` vs kube-prometheus-stack

A common question, since most clusters already run the latter.

| | **kube-prometheus-stack** | **opentelemetry-kube-stack** |
|---|---|---|
| Focus | Prometheus + Alertmanager + Grafana + node/kube exporters | OTel Operator + Collectors + TA + dashboards |
| Metrics path | Prometheus scrapes | OTel Collector scrapes/receives, then remote-writes |
| Traces | **None** | Native |
| Logs | **None** | Native (via `file_log`, `k8s_events`) |
| CRDs | ServiceMonitor, PodMonitor, PrometheusRule | OpenTelemetryCollector, Instrumentation, OpAMPBridge (+ can consume ServiceMonitor/PodMonitor via TA) |
| Coexist? | **Yes** — ★ the Target Allocator **reads ServiceMonitor/PodMonitor**, so you keep existing scrape definitions | |

★ **They coexist well, and that's the pragmatic path:** keep kube-prometheus-stack's Alertmanager and Grafana, let the **Target Allocator consume your existing ServiceMonitors and PodMonitors** so you don't rewrite scrape config, and add OTel for traces, logs and profiles. You get OTel's instrumentation model without a rip-and-replace of your alerting.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Not setting `manager.collectorImage.repository` to contrib | ★ "Unknown receiver/processor" on your first CR. The default image is core `otelcol` |
| One Collector tier doing ingress *and* tail sampling | The stateful, memory-hungry tier OOMs and takes your ingestion down with it |
| A ClusterIP Service as the `load_balancing` DNS target | DNS returns one VIP → all traces to one replica. **You need a headless Service** |
| Naming the receiver `prometheus/otelcol` with the Target Allocator | ★ **Must be named exactly `prometheus`.** Fails with a message listing what it found |
| No `memory_limiter` in the Collector CR | Container OOMKills, loses all buffers, restarts cold |
| `memory_limiter.limit_percentage` above the container limit ratio | Limiter never fires; the kernel decides instead |
| Enabling Java auto-instrumentation without raising memory limits | **OOMKills.** The agent adds tens of MB of heap |
| `admissionWebhooks.failurePolicy: Fail` with unscoped selectors | An Operator outage **blocks pod creation cluster-wide** |
| `k8s_attributes` with `from: connection` behind a mesh or LB | SNAT hides the pod IP → enrichment silently doesn't happen |
| DaemonSet agents without `filter.node_from_env_var` | Every agent watches every pod in the cluster |
| Not setting `decision_cache` sizes | Late spans get independent re-decisions → partial traces |
| Aggressive HPA on a tail-sampling gateway | Scaling reroutes ~R/N of traces; in-flight decisions are lost |
| `terminationGracePeriodSeconds: 30` with `decision_wait: 10s` | Marginal. Use 60s and add `preStop: sleep 10` |
| Ingesting the Collector's own logs with `file_log` | Feedback loop. Exclude `/var/log/pods/<ns>_otel-*` |
| No alert on `otelcol_exporter_queue_size` | ★ The leading indicator of data loss. Everything else is lagging confirmation |
| Pinning Collector images to a floating tag | Unreproducible incidents; surprise breaking changes |
| Running full contrib in every agent DaemonSet | 108 receivers × N nodes of attack surface and memory. Use OCB or `otelcol-k8s` for agents |

---

## Rapid recall

1. **Three modes: agent (DaemonSet or sidecar) and gateway (Deployment).** ★ **The standard production topology is two tiers** — stateless agents per node for ingest/enrichment/host-and-file collection, and a stateful gateway fleet for `tail_sampling`, `span_metrics`, redaction and egress. Upstream's reason: **failure isolation** — the thing that OOMs shouldn't also be your ingestion path.
2. **Sidecars cost memory × pod count** (500 pods × 100 MB = 50 GB). Use for tenant isolation or untrusted workloads, not by default.
3. ★ **The Operator's default `collectorImage` is core `otelcol`, not contrib.** Set `manager.collectorImage.repository=otel/opentelemetry-collector-contrib` or your first CR fails with "unknown receiver". **Cert-manager is a prerequisite** for the webhooks. Chart **0.122.0** → Operator **v0.158.0**.
4. **`OpenTelemetryCollector` `mode`**: `daemonset`, `deployment`, `statefulset`, or `sidecar` (★ injected via the `sidecar.opentelemetry.io/injected` annotation).
5. ★ **The Target Allocator requires a receiver named exactly `prometheus`.** `prometheus/otelcol` fails, and since v0.152.0 the error message lists the instances it found. Allocation strategies: **`consistent-hashing`** (minimal reshuffle — default), **`per-node`**, **`least-weighted`** (job-name aware since v0.145.0). TA needs RBAC on pods/services/endpoints/nodes/namespaces, `monitoring.coreos.com` CRDs, and **`discovery.k8s.io/endpointslices`**.
6. **TA consumes your existing ServiceMonitors/PodMonitors/ScrapeConfigs/Probes** — ★ which means **opentelemetry-kube-stack and kube-prometheus-stack coexist well**: keep Alertmanager and Grafana, don't rewrite scrape config, add OTel for traces/logs/profiles.
7. **Auto-instrumentation**: the `Instrumentation` CR + `instrumentation.opentelemetry.io/inject-<lang>` annotations; webhook + init container copies artefacts into a shared emptyDir and injects `JAVA_TOOL_OPTIONS` / `PYTHONPATH` / `NODE_OPTIONS` / `CORECLR_ENABLE_PROFILING`. ★ **Go is disabled by default** — needs the `operator.autoinstrumentation.go` feature gate, and works by compile-time rewriting (v1 since July 2026).
8. ★ **Auto-instrumentation caveats:** startup latency from the init container; **memory growth → OOMKills if you don't raise limits**; pods need a rollout; `failurePolicy: Fail` can block cluster-wide pod creation; local runs won't match production; **the injected agent version is a platform-wide change — canary it.**
9. **`k8s_attributes` is what makes K8s telemetry usable** (pods can't see their own Deployment/namespace). ★ **`pod_association`: prefer `resource_attribute: k8s.pod.ip` via the downward API** — `from: connection` breaks silently behind a mesh, LB or SNAT. Use **`filter.node_from_env_var`** on DaemonSets so each agent watches only its own node.
10. ★ **`k8s_attributes` emits V1 names ONLY in v0.161.0** (both `EmitV1K8sConventions` and `DontEmitV0K8sConventions` are **true/Beta** — verify with the `featuregate` subcommand, since `--help` disagrees). **Watch for `k8s.pod.annotation.<key>` / `k8s.pod.label.<key>` becoming SINGULAR.** `DontEmitV0` can't be enabled without `EmitV1`. **The real risk is inconsistency: `host_metrics` is still V0-only**, so one dashboard can't see both conventions. And ★ `ShareProcessorBetweenPipelines` is off by default — **three pipelines means three Kubernetes API watchers.**
11. **`span_metrics`/`service_graph` connectors must be wired in both pipelines** or the Collector refuses to start.
12. **Sizing:** agent 100–500m / 256Mi–1Gi; **gateway 0.5–2 CPU / 2–8Gi** driven by `num_traces × trace size + decision caches`. ★ **Container limit and `memory_limiter.limit_percentage` must be set together** so the limiter fires before the kernel does.
13. **Scaling a tail-sampling fleet loses data** — a scale event reroutes ~R/N of traces and orphans in-flight decisions. Scale in small increments, use consistent hashing, keep `decision_wait` short, and **prefer scaling before load arrives**.
14. **Rolling deploys: `terminationGracePeriodSeconds: 60`** (not 30) with `decision_wait: 10s`, plus **`preStop: sleep 10`**. `drop_pending_traces_on_shutdown: false` means shutdown decides on partial data rather than dropping — usually what you want.
15. ★ **The highest-value alert is `otelcol_exporter_queue_size / queue_capacity > 0.8`** — a leading indicator that rises minutes before `send_failed`. Also alert on `receiver_refused_*`, `send_failed_*`, and `sampling_trace_dropped_too_early`.
16. **Operator version notes that matter:** v0.152.0 (webhook without CRDs; TA can drop endpoints referencing arbitrary files — a security control), v0.151.0 (`secretNamespaces`; **if unset, no namespaces are watched for secrets**), v0.149.0 (fixed TA infinite reconciliation loop), v0.147.0 (secret updates), v0.145.0 (**mTLS cert hot-reload** — no restart on cert-manager renewal).

→ Next: [`13-backends.md`](13-backends.md)
