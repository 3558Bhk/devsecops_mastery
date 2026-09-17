# 🛰️ CASE 2 — Telemetry: OpenTelemetry, Traces, Logs & Correlation

> **Build the second and third pillars.** Distributed traces across five services, structured logs with trace context, and the one thing that makes observability actually usable: **clicking from a metric spike to the exact trace to the exact log line.**
>
> **Time:** 6–8 hours · **Level:** beginner → confident
> **Prereq:** [Case 1](./02-CASE-1-prometheus-grafana.md) completed (Prometheus + Grafana running), and [Guide §12–§13](./01-OBSERVABILITY-GUIDE.md) read.

---

## What you'll have at the end

```
✅ OpenTelemetry Collector deployed BOTH as a node agent (DaemonSet) and a central gateway
✅ Tempo storing traces, queried with TraceQL from Grafana
✅ Loki storing logs, with trace_id and span_id extracted automatically
✅ Zero-code instrumentation of Spring Boot (Java agent) and Python
✅ Manual instrumentation of a Go service — spans, attributes, events, links
✅ Browser instrumentation of the React UI, propagating context into the backend
✅ Context propagation across HTTP, PostgreSQL, Redis and RabbitMQ
✅ Tail-based sampling: 100% of errors and slow traces, 10% of the rest
✅ OTel Operator auto-instrumentation via a single `instrumentation` annotation
✅ Metrics exemplars: click a point on a latency graph → the exact trace
✅ Log-derived fields: click a trace_id in Loki → the trace waterfall
✅ Trace-to-logs and trace-to-metrics links working in both directions
✅ The Collector monitoring itself — you'll know when telemetry is being dropped
```

---

## 0. Workspace and prerequisites

```bash
mkdir -p ~/observability-learn/case2/{collector,tempo,loki,app,manifests,dashboards}
cd ~/observability-learn/case2

# ⭐ Case 1 must be running
kubectl get pods -n monitoring | grep -c Running       # ≥ 8
kubectl get pods -n shop
curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.health!="up") | .labels.job'
# (empty = healthy)

kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
```

### The target architecture

```
┌─ shop namespace ─────────────────────────────────────────────────────────────┐
│                                                                              │
│  shop-ui (React)     shop-api (Java)      checkout (Go)    order-worker (Py) │
│  ├ web SDK           ├ javaagent          ├ otel SDK       ├ auto-instrument │
│  └ OTLP/HTTP :4318   └ OTLP/gRPC :4317    └ OTLP/gRPC      └ OTLP/gRPC       │
│         │                    │                  │                │           │
└─────────┼────────────────────┼──────────────────┼────────────────┼───────────┘
          │                    │                  │                │
          │      OTEL_EXPORTER_OTLP_ENDPOINT = the NODE agent (hostIP:4317)
          ▼                    ▼                  ▼                ▼
┌─ otel namespace ─────────────────────────────────────────────────────────────┐
│                                                                              │
│   ┌────────────────────────────────────────────────────────┐                 │
│   │  AGENT  (DaemonSet, one per node)                      │                 │
│   │  receivers: otlp                                       │                 │
│   │  processors: memory_limiter, k8sattributes,            │                 │
│   │              resourcedetection, batch(small)           │                 │
│   │  exporters: otlp/gateway                               │                 │
│   └──────────────────────┬─────────────────────────────────┘                 │
│                          │                                                   │
│   ┌──────────────────────▼─────────────────────────────────┐                 │
│   │  GATEWAY (Deployment, 3 replicas, behind a Service)    │                 │
│   │  receivers: otlp, prometheus, filelog                  │                 │
│   │  processors: memory_limiter, ⭐tail_sampling,          │                 │
│   │              attributes(redact PII), batch(large)      │                 │
│   │  exporters:                                            │                 │
│   │     traces  ──► otlp/tempo                             │                 │
│   │     logs    ──► loki                                   │                 │
│   │     metrics ──► prometheus (OTLP receiver, 3.x)        │                 │
│   │     all     ──► debug (sampled, for learning)          │                 │
│   └───┬──────────────┬──────────────┬──────────────────────┘                 │
└───────┼──────────────┼──────────────┼────────────────────────────────────────┘
        ▼              ▼              ▼
   ┌─────────┐    ┌─────────┐   ┌──────────────┐
   │  TEMPO  │    │  LOKI   │   │  PROMETHEUS  │  (from Case 1)
   │  traces │    │  logs   │   │  metrics     │
   └────┬────┘    └────┬────┘   └──────┬───────┘
        └──────────────┴───────────────┘
                       ▼
                 ┌──────────┐
                 │ GRAFANA  │  ← one pane of glass, everything linked
                 └──────────┘
```

---

## 1. Step 1 — Deploy the trace and log backends

### 1.1 Tempo (traces)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

cat > tempo-values.yaml <<'EOF'
# Grafana Tempo — single-binary mode (right for learning and small prod)
tempo:
  enabled: true
  tempo:
    image:
      repository: grafana/tempo
      tag: 2.6.1                      # ⭐ pin it
    resources:
      requests: {cpu: 250m, memory: 1Gi}
      limits:   {memory: 3Gi}
    retention: 72h                    # ⭐ traces are big; 3 days is normal
    storage:
      trace:
        backend: local                # in production: s3 / gcs / azure
        block:
          bloom_filter_false_positive: .05
          version: vParquet4          # ⭐ the modern columnar format — enables TraceQL well
        wal:
          path: /var/tempo/wal
        local:
          path: /var/tempo/blocks
    # ⭐ the distributors — they receive OTLP
    distributors:
      enabled: true
    # ⭐ search must be on for TraceQL and the Grafana trace explorer
    searchEnabled: true
    querier:
      maxConcurrentQueries: 20
    queryFrontend:
      search:
        durationSlo: 5s
        throughputSlo: 1000
    # ⭐ THE SERVICE GRAPH — Grafana draws your architecture map from traces
    metricsGenerator:
      enabled: true
      remoteWriteUrl: http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/write
      tracesStorage:
        path: /var/tempo/generator
      processor:
        serviceGraphs:
          dimensions:
            - k8s.namespace.name
            - deployment.environment
        spanMetrics:
          dimensions:
            - http.route
            - http.response.status_code
            - url.path
          intrinsicDimensions:
            service: true
            span: true
      registry:
        collection_interval: 15s
    # ⭐ receivers — this is how data gets in
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      zipkin:
        endpoint: 0.0.0.0:9411
      jaeger:
        thrift_http:
          endpoint: 0.0.0.0:14268
  # ⭐ expose the ports
  service:
    type: ClusterIP
  persistence:
    enabled: true
    size: 20Gi
    accessModes: [ReadWriteOnce]
  # Grafana datasource auto-provisioning
  grafana:
    dataSource:
      enabled: false          # we'll add it ourselves with the right UID
EOF

# ⭐ the modern chart name is tempo (single-binary). For distributed: tempo-distributed.
helm install tempo grafana/tempo -n monitoring -f tempo-values.yaml --wait --timeout 8m

kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
kubectl get svc -n monitoring | grep tempo
# tempo            ClusterIP   10.96.x.x   <none>   3200/TCP,4317/TCP,4318/TCP,9411/TCP   2m
```

### 1.2 Loki (logs)

```bash
cat > loki-values.yaml <<'EOF'
# Grafana Loki — single-binary (monolithic) mode
deploymentMode: SingleBinary
singleBinary:
  replicas: 1
  image:
    repository: grafana/loki
    tag: 3.7.5                       # ⭐ pin it
  resources:
    requests: {cpu: 250m, memory: 1Gi}
    limits:   {memory: 3Gi}
  persistence:
    enabled: true
    size: 20Gi

# ⭐ the schema and storage
loki:
  auth_enabled: false                 # single tenant for learning
  schemaConfig:
    configs:
      - from: "2026-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
  storageConfig:
    filesystem:
      directory: /var/loki/chunks
  storage:
    type: filesystem
  limits_config:
    retention_period: 168h            # ⭐ 7 days
    ingestion_rate_mb: 16
    ingestion_burst_size_mb: 32
    max_query_series: 5000
    max_query_parallelism: 16
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    allow_structured_metadata: true   # ⭐ v3 structured metadata
    volume_enabled: true              # ⭐ enables the Grafana log-volume panel
  compactor:
    working_directory: /var/loki/compactor
    retention_enabled: true           # ⭐ required for retention to actually work
    delete_request_store: filesystem
  query_range:
    align_queries_with_step: true
    cache_results: true

# ⭐ don't install the test/promtail/gateway sub-charts — the OTel Collector will ship logs
promtail:
  enabled: false
gateway:
  enabled: false
test:
  enabled: false

# ⭐ monitoring for Loki itself
monitoring:
  selfMonitoring: {enabled: false, grafanaAgent: {installOperator: false}}
  lokiCanary: {enabled: false}
  serviceMonitor:
    enabled: true
    labels: {release: kps}
EOF

helm install loki grafana/loki -n monitoring -f loki-values.yaml --wait --timeout 8m

kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl get svc -n monitoring | grep loki
# loki   ClusterIP   10.96.x.x   <none>   3100/TCP,9095/TCP   3m
```

### 1.3 Register both in Grafana, with the correlation wiring ⭐⭐

This is the step that turns three tools into one. **The `uid` values must be exactly these** — the dashboards and derived fields reference them.

```bash
cat > manifests/grafana-datasources.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources-observability
  namespace: monitoring
  labels:
    grafana_datasource: "1"          # ⭐ the sidecar's label
data:
  observability-datasources.yaml: |
    apiVersion: 1
    datasources:
      # ── PROMETHEUS (already exists from kube-prometheus-stack; we redefine it
      #    to add the EXEMPLAR link to Tempo) ⭐⭐
      - name: Prometheus
        uid: prometheus
        type: prometheus
        access: proxy
        url: http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090
        isDefault: true
        jsonData:
          timeInterval: "30s"                       # ⭐ MUST equal scrapeInterval
          httpMethod: POST
          manageAlerts: false
          prometheusType: Prometheus
          prometheusVersion: 3.13.2
          exemplarTraceIdDestinations:              # ⭐⭐ CLICK A METRIC POINT → THE TRACE
            - name: traceID
              datasourceUid: tempo
              urlDisplayLabel: "View trace"
            - name: trace_id
              datasourceUid: tempo
          customQueryParameters: ""
        editable: true

      # ── TEMPO (traces) ⭐
      - name: Tempo
        uid: tempo
        type: tempo
        access: proxy
        url: http://tempo.monitoring.svc:3200
        isDefault: false
        jsonData:
          httpMethod: GET
          serviceMap:
            datasourceUid: prometheus               # ⭐ the service-graph panel
          nodeGraph:
            enabled: true                           # ⭐ draw upstream/downstream from a span
          search:
            hide: false
          traceQuery:
            timeShiftEnabled: true
            spanStartTimeShift: "-1h"
          tracesToLogs:                             # ⭐⭐ TRACE → LOGS
            datasourceUid: loki
            spanStartTimeShift: "-1h"
            filterByTraceID: true
            filterBySpanID: true
            customQuery: true
            query: '{namespace="$${__tags.k8s.namespace.name}", pod=~"$${__span.tags.service.name}.*"} | trace_id="$${__trace.traceId}"'
            tags:
              - {key: "service.name", value: "app"}
              - {key: "k8s.namespace.name", value: "namespace"}
              - {key: "k8s.pod.name", value: "pod"}
          tracesToMetrics:                          # ⭐⭐ TRACE → METRICS
            datasourceUid: prometheus
            spanStartTimeShift: "-1h"
            spanEndTimeShift: "1h"
            tags:
              - {key: "service.name", value: "application"}
              - {key: "k8s.namespace.name", value: "namespace"}
              - {key: "k8s.pod.name", value: "pod"}
            queries:
              - name: "Request rate"
                query: 'sum(rate(http_server_requests_seconds_count{application="$${__span.tags[service.name]}"}[$$__interval]))'
              - name: "p99 latency"
                query: 'histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket{application="$${__span.tags[service.name]}"}[$$__interval])) by (le))'
              - name: "Error rate"
                query: 'sum(rate(http_server_requests_seconds_count{application="$${__span.tags[service.name]}",status=~"5.."}[$$__interval])) / sum(rate(http_server_requests_seconds_count{application="$${__span.tags[service.name]}"}[$$__interval]))'
          lokiSearch:
            datasourceUid: loki                     # ⭐ search Loki from the trace view
        editable: true

      # ── LOKI (logs) ⭐
      - name: Loki
        uid: loki
        type: loki
        access: proxy
        url: http://loki.monitoring.svc:3100
        isDefault: false
        jsonData:
          maxLines: 5000
          timeout: 60
          derivedFields:                            # ⭐⭐ THE LOG → TRACE LINK
            - name: TraceID
              matcherRegex: '"trace_id"\s*:\s*"(\w+)"'
              url: '$${__value.raw}'
              urlDisplayLabel: "View trace for $${__value.raw}"
              datasourceUid: tempo
            - name: TraceID-plain
              matcherRegex: 'trace_id=(\w+)'
              url: '$${__value.raw}'
              urlDisplayLabel: "View trace"
              datasourceUid: tempo
            - name: SpanID
              matcherRegex: '"span_id"\s*:\s*"(\w+)"'
              url: '$${__value.raw}'
              datasourceUid: tempo
            - name: OrderID
              matcherRegex: '"order_id"\s*:\s*"(\w+)"'
              url: '/explore?left={"queries":[{"refId":"A","datasource":{"uid":"loki"},"expr":"{namespace=\"shop\"} |= \"$${__value.raw}\""}]}'
              urlDisplayLabel: "All logs for order $${__value.raw}"
        editable: true

      # ── PYROSCOPE (profiles, bonus) ──
      # - name: Pyroscope
      #   uid: pyroscope
      #   type: grafana-pyroscope-datasource
      #   url: http://pyroscope.monitoring.svc:4040
      #   jsonData:
      #     tracesToProfiles:
      #       datasourceUid: tempo
      #       profileTypeId: "process_cpu:cpu:nanoseconds:cpu:nanoseconds"
EOF

kubectl apply -f manifests/grafana-datasources.yaml
sleep 25
kubectl logs -n monitoring deploy/kps-grafana -c grafana-sc-datasources --tail=10
# ✅ "Successfully added datasource" / "Datasource provisioned"
```

**Verify the links work:**

```bash
# Grafana → Connections → Data sources → Prometheus → check "Exemplar trace ID destination"
# Grafana → Explore → Loki → any log line with a trace_id → a "View trace" button appears
# Grafana → Explore → Tempo → Search → open a trace → a "Logs for this span" button appears
```

> 🔑 **These three `jsonData` blocks (`exemplarTraceIdDestinations`, `tracesToLogs`, `derivedFields`) are the entire reason the LGTM stack feels like one product.** Set them once, and every future dashboard inherits the correlation. Forget them, and you have three disconnected tools and a very slow incident response.

---

## 2. Step 2 — The OpenTelemetry Collector

### 2.1 The Agent (DaemonSet, one per node)

The agent's job: receive OTLP from apps on its own node, enrich with Kubernetes metadata, and forward to the gateway. **Apps talk to the agent, never to the gateway directly** — so a gateway outage can't take down your app.

```bash
cat > collector/agent-config.yaml <<'EOF'
# ═══════════════════════════════════════════════════════════════
# OTel Collector — AGENT (DaemonSet). Runs on every node.
# ⭐ The FIRST processor must be memory_limiter and the LAST must be batch.
# ═══════════════════════════════════════════════════════════════
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 16
        keepalive:
          server_parameters: {max_connection_age: 30s, max_connection_age_grace: 10s}
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins: ["http://localhost:*", "https://shop.example.com"]   # ⭐ the browser SDK needs this

  # ⭐ host + container metrics for the node itself (a node_exporter alternative)
  hostmetrics:
    collection_interval: 30s
    root_path: /hostfs              # ⭐ the node's filesystem, mounted into the pod
    scrapers:
      cpu:      {metrics: {system.cpu.utilization: {enabled: true}}}
      memory:   {metrics: {system.memory.utilization: {enabled: true}}}
      disk:     {}
      filesystem:
        metrics: {system.filesystem.utilization: {enabled: true}}
        exclude_mount_points:
          mount_points: ["/dev/*", "/proc/*", "/sys/*", "/var/lib/docker/*", "/var/lib/kubelet/*"]
          match_type: regexp
      load:     {}
      network:  {}
      processes: {}

processors:
  # ⭐⭐ MUST BE FIRST. Without it the Collector OOMs and drops everything.
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80            # refuse data above 80% of the container limit
    spike_limit_percentage: 25      # start refusing 25% before the hard limit

  # ⭐⭐ add Kubernetes context to EVERY span/log/metric — this is what makes
  #    "show me all traces from namespace shop" possible
  k8sattributes:
    auth_type: serviceAccount
    passthrough: false
    extract:
      metadata:                     # the pod metadata to attach
        - k8s.namespace.name
        - k8s.pod.name
        - k8s.pod.uid
        - k8s.pod.start_time
        - k8s.deployment.name
        - k8s.replicaset.name
        - k8s.statefulset.name
        - k8s.daemonset.name
        - k8s.job.name
        - k8s.cronjob.name
        - k8s.node.name
        - k8s.cluster.uid
      labels:                       # pull specific POD LABELS into attributes
        - tag_name: app
          key: app
          from: pod
        - tag_name: team
          key: team
          from: pod
        - tag_name: service.version
          key: app.kubernetes.io/version
          from: pod
      annotations:
        - tag_name: deployment.environment
          key: deploy-env
          from: pod
    pod_association:                # ⭐ how to match telemetry to a pod
      - sources:
          - from: resource_attribute
            name: k8s.pod.ip
      - sources:
          - from: resource_attribute
            name: k8s.pod.uid
      - sources:
          - from: connection        # fall back to the source IP of the OTLP connection

  # ⭐ detect the environment (the node, the cloud, the cluster)
  resourcedetection:
    detectors: [env, system, docker, ec2, gcp, azure]
    timeout: 5s
    override: false                 # ⭐ don't overwrite what the SDK already set
    system:
      hostname_sources: [os]

  # normalise the service name
  transform/servicename:
    error_mode: ignore
    trace_statements:
      - context: resource
        statements:
          - set(attributes["service.name"], attributes["service.name"] ?? "unknown")
          - set(attributes["k8s.cluster.name"], "learn")

  # ⭐ small batch here; the gateway does the big one
  batch:
    send_batch_size: 1024
    send_batch_max_size: 2048
    timeout: 2s

exporters:
  # forward everything to the gateway
  otlp/gateway:
    endpoint: otel-collector-gateway.otel.svc.cluster.local:4317
    tls: {insecure: true}
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 5000              # ⭐ buffer during a gateway restart
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s
    timeout: 10s

  # ⭐ the Collector's OWN telemetry → Prometheus, so you can see drops
  prometheus:
    endpoint: 0.0.0.0:8888

  debug:
    verbosity: basic                # basic | normal | detailed. NEVER detailed in prod.

service:
  telemetry:
    logs:
      level: info
      encoding: json                # ⭐ structured logs from the Collector itself
    metrics:
      level: detailed
      readers:
        - pull:
            exporter:
              prometheus:
                host: 0.0.0.0
                port: 8888
    resource:
      service.name: otel-agent
      service.version: "0.158.0"

  # ⭐⭐ PIPELINES — which receivers feed which processors feed which exporters
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, resourcedetection, transform/servicename, batch]
      exporters: [otlp/gateway]
    metrics:
      receivers: [otlp, hostmetrics]
      processors: [memory_limiter, k8sattributes, resourcedetection, batch]
      exporters: [otlp/gateway]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, resourcedetection, batch]
      exporters: [otlp/gateway]
EOF
```

### 2.2 The Gateway (Deployment, the smart one)

```bash
cat > collector/gateway-config.yaml <<'EOF'
# ═══════════════════════════════════════════════════════════════
# OTel Collector — GATEWAY. Central, stateless, replicated.
# ⭐ This is where TAIL SAMPLING must live (it needs every span of a trace).
# ═══════════════════════════════════════════════════════════════
receivers:
  otlp:
    protocols:
      grpc: {endpoint: 0.0.0.0:4317, max_recv_msg_size_mib: 32}
      http: {endpoint: 0.0.0.0:4318}

  # ⭐ collect Kubernetes container logs straight from the node's /var/log/pods
  filelog:
    include: [/var/log/pods/*/*/*.log]
    exclude: [/var/log/pods/otel_*/*/*.log, /var/log/pods/monitoring_*/*/*.log]
    include_file_path: true
    include_file_name: false
    operators:
      # the container-runtime log line is JSON wrapping your line
      - type: json_parser
        id: crio-parser
        parse_from: body
        parse_to: attributes
        json:
          time_format: ''
        timestamp:
          parse_from: attributes.time
          layout: '%Y-%m-%dT%H:%M:%S.%fZ'
        on_error: send
      # ⭐ promote the fields you'll filter on to Loki labels / structured metadata
      - type: regex_parser
        id: extract-k8s
        parse_from: attributes["log.file.path"]
        regex: '^/var/log/pods/(?P<k8s_namespace>[^_]+)_(?P<k8s_pod_name>[^_]+)_(?P<k8s_pod_uid>[^/]+)/(?P<k8s_container_name>[^/]+)/'
        on_error: send
      - type: move
        from: attributes.k8s_namespace
        to: resource["k8s.namespace.name"]
        on_error: send
      - type: move
        from: attributes.k8s_pod_name
        to: resource["k8s.pod.name"]
        on_error: send
      - type: move
        from: attributes.k8s_container_name
        to: resource["k8s.container.name"]
        on_error: send
      - type: move
        from: attributes.stream
        to: attributes["log.iostream"]
        on_error: send
      # ⭐⭐ extract trace_id / span_id from JSON app logs
      - type: json_parser
        id: extract-trace-context
        parse_from: body
        on_error: send
      - type: move
        from: attributes.trace_id
        to: attributes["trace.id"]
        on_error: send
      - type: move
        from: attributes.traceId
        to: attributes["trace.id"]
        on_error: send
      - type: move
        from: attributes.span_id
        to: attributes["span.id"]
        on_error: send

  # ⭐ scrape Prometheus targets too (a full Prometheus replacement, if you wanted)
  prometheus:
    config:
      scrape_configs: []

processors:
  memory_limiter:                    # ⭐ FIRST
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25

  # ⭐⭐ TAIL SAMPLING — the money processor
  tail_sampling:
    decision_wait: 10s               # buffer spans this long waiting for the rest of the trace
    num_traces: 200000               # hold this many traces in memory
    expected_new_traces_per_sec: 2000
    decision_cache:
      sampled_cache_size: 100000
    policies:
      # 1. NEVER drop an error
      - name: keep-errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      # 2. NEVER drop a 5xx
      - name: keep-5xx
        type: numeric_attribute
        numeric_attribute: {key: http.response.status_code, min_value: 500, max_value: 599}
      # 3. NEVER drop a slow trace
      - name: keep-slow
        type: latency
        latency: {threshold_ms: 1000}
      # 4. ALWAYS keep the money path
      - name: keep-checkout
        type: string_attribute
        string_attribute:
          key: url.path
          values: [/api/orders, /api/checkout, /api/payment]
      # 5. ALWAYS keep the canary at 100%
      - name: keep-canary
        type: string_attribute
        string_attribute: {key: service.version, values: ["1.3.0-rc1", "canary"]}
      # 6. ALWAYS keep health-check noise OUT (invert_match)
      - name: drop-health-probes
        type: string_attribute
        string_attribute:
          key: url.path
          values: [/actuator/health, /healthz, /health, /readyz, /livez, /metrics]
          invert_match: true          # ⭐ keep only if the path is NOT one of these
      # 7. keep 10% of everything else
      - name: sample-the-rest
        type: probabilistic
        probabilistic: {sampling_percentage: 10}

  # ⭐ redact PII before it reaches storage
  attributes/redact:
    actions:
      - key: db.query.text
        action: hash                       # keep it searchable-ish, lose the values
      - key: http.request.header.authorization
        action: delete
      - key: http.request.header.cookie
        action: delete
      - key: user.email
        action: hash
      - key: customer.name
        action: delete
      - key: http.url
        action: update
        value: "<redacted>"
        # ⚠️ use with care — better to redact via a regex on query params:
      - key: url.query
        action: hash

  # add a cluster-level attribute to everything
  resource:
    attributes:
      - {key: k8s.cluster.name, value: learn, action: upsert}
      - {key: collector.tier,   value: gateway, action: upsert}

  # ⭐ reduce log volume: drop noisy loggers
  filter/logs:
    error_mode: ignore
    logs:
      log_record:
        - 'IsMatch(body, ".*health.*check.*") and attributes["log.severity"] == "DEBUG"'
        - 'attributes["k8s.container.name"] == "POD"'
        - 'resource.attributes["k8s.namespace.name"] == "kube-system" and severity_number < 9'

  batch:                              # ⭐ LAST
    send_batch_size: 8192
    send_batch_max_size: 16384
    timeout: 5s

exporters:
  # traces → Tempo
  otlp/tempo:
    endpoint: tempo.monitoring.svc:4317
    tls: {insecure: true}
    sending_queue: {enabled: true, num_consumers: 10, queue_size: 10000}
    retry_on_failure: {enabled: true, initial_interval: 5s, max_interval: 30s, max_elapsed_time: 300s}

  # logs → Loki (via the native Loki exporter)
  loki:
    endpoint: http://loki.monitoring.svc:3100/loki/api/v1/push
    default_labels_enabled:
      exporter: true
      job: true
      instance: false
      level: true
    tenant_id: ""

  # ⭐ metrics → Prometheus 3.x, which has a native OTLP receiver
  #    (Case 1 enabled `otlp-write-receiver` as a feature flag)
  prometheusremotewrite:
    endpoint: http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/write
    resource_to_telemetry_conversion: {enabled: true}
    send_metadata: true

  # ⭐ self-monitoring
  prometheus:
    endpoint: 0.0.0.0:8888
    resource_to_telemetry_conversion: {enabled: true}

  debug:
    verbosity: basic

service:
  telemetry:
    logs: {level: info, encoding: json}
    metrics:
      level: detailed
      readers:
        - pull: {exporter: {prometheus: {host: 0.0.0.0, port: 8888}}}
    resource:
      service.name: otel-gateway
      service.version: "0.158.0"

  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, tail_sampling, attributes/redact, resource, batch]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, resource, batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp, filelog]
      processors: [memory_limiter, filter/logs, resource, batch]
      exporters: [loki]
EOF
```

### 2.3 Deploy both

```bash
kubectl create namespace otel
kubectl label ns otel team=platform

cat > manifests/otel-agent.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: otel-agent-config, namespace: otel}
data: {}          # ← populated by kubectl create below
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: otel-agent, namespace: otel}
---
# ⭐ k8sattributes needs these cluster-wide read permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: otel-agent-k8sattributes}
rules:
  - apiGroups: [""]
    resources: [pods, namespaces, nodes]
    verbs: [get, list, watch]
  - apiGroups: ["apps"]
    resources: [replicasets, deployments, statefulsets, daemonsets]
    verbs: [get, list, watch]
  - apiGroups: ["batch"]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch]
  - apiGroups: ["extensions"]
    resources: [replicasets]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: otel-agent-k8sattributes}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: otel-agent-k8sattributes}
subjects: [{kind: ServiceAccount, name: otel-agent, namespace: otel}]
---
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: otel-agent, namespace: otel, labels: {app: otel-agent}}
spec:
  selector: {matchLabels: {app: otel-agent}}
  updateStrategy: {type: RollingUpdate, rollingUpdate: {maxUnavailable: 1}}
  template:
    metadata:
      labels: {app: otel-agent}
      annotations:
        checksum/config: "REPLACE"        # ⭐ roll pods when the config changes
    spec:
      serviceAccountName: otel-agent
      hostNetwork: false                  # ⭐ true would let apps reach it via the node IP
      dnsPolicy: ClusterFirst
      priorityClassName: system-node-critical
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsUser: 0                      # needs to read /var/log/pods
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: collector
          image: otel/opentelemetry-collector-contrib:0.158.0   # ⭐ contrib has k8sattributes
          args: ["--config=/etc/otel/config.yaml", "--feature-gates=otelcol.printSchema"]
          ports:
            - {name: otlp-grpc, containerPort: 4317, protocol: TCP}
            - {name: otlp-http, containerPort: 4318, protocol: TCP}
            - {name: metrics,   containerPort: 8888, protocol: TCP}
          env:
            - {name: MY_NODE_NAME, valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}
            - {name: MY_NODE_IP,   valueFrom: {fieldRef: {fieldPath: status.hostIP}}}
            - {name: GOMEMLIMIT,   value: "1400MiB"}       # ⭐ match the memory limit
            - {name: GOMAXPROCS,   value: "2"}
          resources:
            requests: {cpu: 200m, memory: 512Mi}
            limits:   {memory: 1536Mi}                       # ⭐ memory_limiter uses this
          readinessProbe:
            httpGet: {path: /, port: 13133}
            periodSeconds: 10
          livenessProbe:
            httpGet: {path: /, port: 13133}
            initialDelaySeconds: 15
            periodSeconds: 20
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"], add: ["DAC_READ_SEARCH"]}
          volumeMounts:
            - {name: config, mountPath: /etc/otel}
            - {name: varlogpods, mountPath: /var/log/pods, readOnly: true}
            - {name: hostfs, mountPath: /hostfs, readOnly: true}
      volumes:
        - {name: config, configMap: {name: otel-agent-config}}
        - {name: varlogpods, hostPath: {path: /var/log/pods, type: Directory}}
        - {name: hostfs, hostPath: {path: /, type: Directory}}
---
apiVersion: v1
kind: Service
metadata:
  name: otel-collector-agent
  namespace: otel
  labels: {app: otel-agent}
spec:
  selector: {app: otel-agent}
  ports:
    - {name: otlp-grpc, port: 4317, targetPort: otlp-grpc}
    - {name: otlp-http, port: 4318, targetPort: otlp-http}
EOF

# load the config into the ConfigMap
kubectl create configmap otel-agent-config -n otel \
  --from-file=config.yaml=collector/agent-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

# ⭐ stamp the config checksum so pods roll on config change
HASH=$(sha256sum collector/agent-config.yaml | cut -c1-16)
sed -i "s/checksum\/config: \"REPLACE\"/checksum\/config: \"$HASH\"/" manifests/otel-agent.yaml

kubectl apply -f manifests/otel-agent.yaml
kubectl rollout status ds/otel-agent -n otel --timeout=180s
kubectl get pods -n otel -o wide                     # ⭐ one per node
kubectl logs -n otel -l app=otel-agent --tail=30 | grep -iE 'error|started|listening'
# {"level":"info","msg":"Everything is ready. Begin running and processing data."}
```

```bash
cat > manifests/otel-gateway.yaml <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: {name: otel-gateway, namespace: otel}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: otel-gateway-k8sattributes}
rules:
  - {apiGroups: [""], resources: [pods, namespaces, nodes], verbs: [get, list, watch]}
  - {apiGroups: ["apps"], resources: [replicasets, deployments], verbs: [get, list, watch]}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: otel-gateway-k8sattributes}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: otel-gateway-k8sattributes}
subjects: [{kind: ServiceAccount, name: otel-gateway, namespace: otel}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: otel-collector-gateway, namespace: otel, labels: {app: otel-gateway}}
spec:
  replicas: 2                       # ⭐ ≥2 so tail_sampling survives a restart
  strategy: {rollingUpdate: {maxSurge: 1, maxUnavailable: 0}}
  selector: {matchLabels: {app: otel-gateway}}
  template:
    metadata:
      labels: {app: otel-gateway}
      annotations:
        checksum/config: "REPLACE"
        prometheus.io/scrape: "true"
        prometheus.io/port: "8888"
    spec:
      serviceAccountName: otel-gateway
      securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
      terminationGracePeriodSeconds: 60      # ⭐ let it flush the sampling buffer
      topologySpreadConstraints:
        - {maxSkew: 1, topologyKey: kubernetes.io/hostname, whenUnsatisfiable: ScheduleAnyway,
           labelSelector: {matchLabels: {app: otel-gateway}}}
      containers:
        - name: collector
          image: otel/opentelemetry-collector-contrib:0.158.0
          args: ["--config=/etc/otel/config.yaml"]
          ports:
            - {name: otlp-grpc, containerPort: 4317}
            - {name: otlp-http, containerPort: 4318}
            - {name: metrics,   containerPort: 8888}
          env:
            - {name: GOMEMLIMIT, value: "3500MiB"}     # ⭐ ~90% of the limit
            - {name: GOMAXPROCS, value: "4"}
          resources:
            requests: {cpu: 500m, memory: 2Gi}
            limits:   {memory: 4Gi}                      # ⭐ tail_sampling needs RAM
          readinessProbe: {httpGet: {path: /, port: 13133}, periodSeconds: 10}
          livenessProbe:  {httpGet: {path: /, port: 13133}, initialDelaySeconds: 20, periodSeconds: 20}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
          volumeMounts:
            - {name: config, mountPath: /etc/otel}
            - {name: tmp, mountPath: /tmp}
      volumes:
        - {name: config, configMap: {name: otel-gateway-config}}
        - {name: tmp, emptyDir: {sizeLimit: 512Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: otel-collector-gateway, namespace: otel, labels: {app: otel-gateway}}
spec:
  selector: {app: otel-gateway}
  ports:
    - {name: otlp-grpc, port: 4317, targetPort: otlp-grpc}
    - {name: otlp-http, port: 4318, targetPort: otlp-http}
    - {name: metrics,   port: 8888, targetPort: metrics}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: otel-collector-gateway, namespace: otel}
spec:
  minAvailable: 1
  selector: {matchLabels: {app: otel-gateway}}
---
# ⭐ scrape the Collector's own metrics
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: otel-collector, namespace: otel, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: otel-gateway}}
  endpoints:
    - {port: metrics, path: /metrics, interval: 30s}
EOF

kubectl create configmap otel-gateway-config -n otel \
  --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

HASH=$(sha256sum collector/gateway-config.yaml | cut -c1-16)
sed -i "s/checksum\/config: \"REPLACE\"/checksum\/config: \"$HASH\"/" manifests/otel-gateway.yaml

kubectl apply -f manifests/otel-gateway.yaml
kubectl rollout status deploy/otel-collector-gateway -n otel --timeout=180s
```

### 2.4 Validate the Collector before you instrument anything ⭐

```bash
# 1. is the config valid? The Collector refuses to start on a bad config — check the logs.
kubectl logs -n otel deploy/otel-collector-gateway --tail=50
# ✅ {"level":"info","msg":"Everything is ready. Begin running and processing data."}
# ⛔ {"level":"error","msg":"Cannot start pipelines","error":"failed to create \"tail_sampling\" …"}

# 2. validate the config file offline
docker run --rm -v "$PWD/collector:/cfg" otel/opentelemetry-collector-contrib:0.158.0 \
  --config=/cfg/gateway-config.yaml --dry-run 2>&1 | tail -5

# 3. ⭐ send a hand-crafted trace and see it arrive
kubectl port-forward -n otel svc/otel-collector-gateway 4317:4317 4318:4318 &
sleep 3

TRACE_ID=$(openssl rand -hex 16)
SPAN_ID=$(openssl rand -hex 8)
NOW_NS=$(date +%s%N)
END_NS=$((NOW_NS + 250000000))

curl -s -XPOST http://localhost:4318/v1/traces \
  -H 'Content-Type: application/json' -d '{
  "resourceSpans": [{
    "resource": {"attributes": [
      {"key":"service.name","value":{"stringValue":"manual-test"}},
      {"key":"deployment.environment","value":{"stringValue":"dev"}}
    ]},
    "scopeSpans": [{
      "scope": {"name":"manual-test","version":"1.0.0"},
      "spans": [{
        "traceId": "'"$TRACE_ID"'",
        "spanId":  "'"$SPAN_ID"'",
        "name": "manual-test-span",
        "kind": 2,
        "startTimeUnixNano": "'"$NOW_NS"'",
        "endTimeUnixNano":   "'"$END_NS"'",
        "attributes": [
          {"key":"http.request.method","value":{"stringValue":"GET"}},
          {"key":"url.path","value":{"stringValue":"/api/orders"}},
          {"key":"http.response.status_code","value":{"intValue":"200"}}
        ],
        "status": {"code": 1}
      }]
    }]
  }]
}'
# {"partialSuccess":{}}     ← ✅ accepted (an empty object also means success)

echo "trace id: $TRACE_ID"

# 4. find it in Tempo
kubectl port-forward -n monitoring svc/tempo 3200:3200 &
sleep 3
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq '.batches[0].scopeSpans[0].spans[0] | {name, attributes}'
# ⭐ if this returns the span, the ENTIRE pipeline works: app → agent → gateway → Tempo

# 5. search for it by service
curl -sG 'localhost:3200/api/search' \
  --data-urlencode 'q={ .service.name = "manual-test" }' \
  --data-urlencode 'limit=5' | jq '.traces'

# 6. is the gateway dropping anything?
kubectl port-forward -n otel svc/otel-collector-gateway 8888:8888 &
sleep 2
curl -s localhost:8888/metrics | grep -E '^otelcol_(receiver_accepted|exporter_sent|processor_dropped|exporter_send_failed)' | grep -v '#'
# otelcol_receiver_accepted_spans{receiver="otlp",transport="http"}  1
# otelcol_exporter_sent_spans{exporter="otlp/tempo"}                 1
# otelcol_processor_dropped_spans{processor="tail_sampling"}         0   ← ⭐ must be ~0
# otelcol_exporter_send_failed_spans{exporter="otlp/tempo"}          0   ← ⭐ must be 0
```

> 🔑 **Always validate the pipeline with a manual span before you spend an hour instrumenting an app.** If step 4 fails, nothing else will work, and the failure will be much harder to find buried inside a real service.

---

## 3. Step 3 — Instrument the Java app (zero-code)

The OpenTelemetry Java agent is the most complete auto-instrumentation in existence. **You change no code.** You add one JVM flag.

### 3.1 What it instruments automatically

| Library | What you get |
|---|---|
| Servlet (Tomcat/Jetty/Undertow), Spring WebMVC, Spring WebFlux | A SERVER span per HTTP request, with the **templated** route |
| Apache HttpClient, OkHttp, `java.net.http`, RestTemplate, WebClient, Feign | CLIENT spans + **context propagation into the headers** |
| JDBC, HikariCP, Hibernate, JPA, Spring Data | CLIENT spans with `db.system`, `db.query.text`, connection-pool metrics |
| Lettuce, Jedis, Spring Data Redis | CLIENT spans |
| RabbitMQ, Kafka, JMS, SQS | PRODUCER + CONSUMER spans with **header propagation** |
| gRPC, Dubbo | Spans + metadata propagation |
| Logback, Log4j2, JUL | ⭐ **`trace_id` and `span_id` injected into every log line** |
| Executors, CompletableFuture, Kotlin coroutines, Reactor | ⭐ **Context propagation across threads** |
| JVM | Metrics: heap, GC, threads, classes, CPU |
| Tomcat | Metrics: threads, sessions, request count |

```bash
cd ~/observability-learn/case2/app
mkdir -p shop-api-traced/src/main/java/com/shop/{controller,service} shop-api-traced/src/main/resources
```

**The only change to `application.yaml`** — enable JSON logs with trace context:

```yaml
# src/main/resources/application.yaml
server:
  port: 8080
  shutdown: graceful

spring:
  application:
    name: shop-api
  lifecycle: {timeout-per-shutdown-phase: 30s}

management:
  server: {port: 9090}
  endpoints.web.exposure.include: health,info,prometheus
  endpoint.health.probes.enabled: true
  prometheus.metrics.export.enabled: true
  metrics:
    tags: {application: shop-api, env: dev, team: platform}
    distribution:
      percentiles-histogram: {http.server.requests: true}
      slo: {http.server.requests: 50ms,100ms,200ms,300ms,500ms,1s,2s}

# ⭐⭐ JSON LOGS WITH TRACE CONTEXT — this is what makes Loki→Tempo work
logging:
  pattern:
    console: '{"timestamp":"%d{yyyy-MM-dd''T''HH:mm:ss.SSSXXX}","level":"%p","logger":"%logger{36}","thread":"%t","trace_id":"%X{trace_id}","span_id":"%X{span_id}","trace_flags":"%X{trace_flags}","service":"shop-api","message":"%m","exception":"%ex"}%n'
  level:
    root: INFO
    com.shop: DEBUG
    org.springframework.web: INFO
```

> 🔑 **`%X{trace_id}` reads from the MDC (Mapped Diagnostic Context).** The OTel Java agent puts `trace_id`, `span_id` and `trace_flags` into the MDC automatically for every span — so your *existing* logging code emits trace context with no changes. The same works for Log4j2 (`%X{trace_id}`) and for JSON encoders (`logstash-logback-encoder` with `<includeMdcKeyName>trace_id</includeMdcKeyName>`).

**`OrderController.java`** — the same as Case 1, plus one manual span to show the pattern:

```java
package com.shop.controller;

import com.shop.service.OrderService;
import com.shop.service.OrderService.OrderResult;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class OrderController {

    private static final Logger log = LoggerFactory.getLogger(OrderController.class);
    // ⭐ the API is a no-op if the agent isn't attached — safe to leave in the code
    private static final Tracer tracer = GlobalOpenTelemetry.getTracer("com.shop.orders", "1.0.0");

    private final OrderService orders;

    public OrderController(OrderService orders) { this.orders = orders; }

    @PostMapping("/orders")
    public ResponseEntity<?> createOrder(@RequestBody(required = false) Map<String, Object> body) {
        int items = body == null ? 1 : ((Number) body.getOrDefault("items", 1)).intValue();
        String tier = body == null ? "standard" : String.valueOf(body.getOrDefault("tier", "standard"));

        // ⭐⭐ A MANUAL, DOMAIN-LEVEL SPAN — the agent can't know what "validate cart" means
        Span span = tracer.spanBuilder("validate-and-price-cart")
                .setAttribute("cart.items", items)
                .setAttribute("customer.tier", tier)
                .setAttribute("cart.channel", "web")
                .startSpan();

        try (Scope scope = span.makeCurrent()) {         // ⭐ make it the current span for children
            if (items <= 0 || items > 50) {
                span.setStatus(StatusCode.ERROR, "invalid item count");   // ⭐ SET THE STATUS
                span.addEvent("validation.failed", io.opentelemetry.api.common.Attributes.of(
                        io.opentelemetry.api.common.AttributeKey.longKey("cart.items"), (long) items));
                return ResponseEntity.badRequest().body(Map.of("error", "invalid_items"));
            }

            OrderResult r = orders.createOrderWithTags(tier, items);

            // ⭐⭐ business attributes that make traces SEARCHABLE in Tempo
            span.setAttribute("order.id", r.orderId() == null ? "rejected" : r.orderId());
            span.setAttribute("order.amount_cents", r.amountCents());
            span.setAttribute("order.status", r.status());

            log.info("order processed tier={} items={} status={} amount={}",
                    tier, items, r.status(), r.amountCents());

            if ("rejected".equals(r.status())) {
                span.setStatus(StatusCode.ERROR, "payment declined");
                return ResponseEntity.status(402).body(Map.of("error", "payment_declined"));
            }
            return ResponseEntity.status(201).body(r);

        } catch (RuntimeException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);                     // ⭐ the stack trace becomes a span event
            log.error("order failed", e);
            throw e;
        } finally {
            span.end();                                  // ⭐ ALWAYS end it, in a finally
        }
    }

    @GetMapping("/items")
    public ResponseEntity<?> items() { return ResponseEntity.ok(orders.getItems()); }

    @GetMapping("/flaky")
    public ResponseEntity<?> flaky() {
        Span span = tracer.spanBuilder("flaky-operation").startSpan();
        try (Scope s = span.makeCurrent()) {
            int n = java.util.concurrent.ThreadLocalRandom.current().nextInt(100);
            if (n < 20) {
                span.setStatus(StatusCode.ERROR, "simulated internal error");
                log.error("simulated internal error, n={}", n);
                return ResponseEntity.internalServerError().body(Map.of("error", "simulated"));
            }
            if (n < 30) {
                Thread.sleep(2500);                       // a slow path for tail sampling to catch
                span.addEvent("slow.path.taken");
                return ResponseEntity.ok(Map.of("slow", true));
            }
            return ResponseEntity.ok(Map.of("ok", true));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.status(500).build();
        } finally {
            span.end();
        }
    }

    @GetMapping("/health")
    public ResponseEntity<?> health() { return ResponseEntity.ok(Map.of("status", "UP")); }
}
```

### 3.2 Build it with the agent baked in

```bash
cd ~/observability-learn/case2/app/shop-api-traced

cat > Dockerfile <<'EOF'
# ── build ─────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY . .
RUN mvn -q -B -DskipTests package

# ── runtime ───────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
WORKDIR /app

# ⭐⭐ download the OTel Java agent at build time and pin the version
ARG OTEL_AGENT_VERSION=2.11.0
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VERSION}/opentelemetry-javaagent.jar \
    /opt/otel/opentelemetry-javaagent.jar
RUN chmod 644 /opt/otel/opentelemetry-javaagent.jar

COPY --from=build /src/target/shop-api.jar app.jar

# ⭐ extension jar for anything the agent doesn't cover (optional)
# COPY extensions/*.jar /opt/otel/extensions/

USER 10001
EXPOSE 8080 9090

# ⭐⭐ THE ONLY THING THAT TURNS ON TRACING
ENV JAVA_TOOL_OPTIONS="\
-javaagent:/opt/otel/opentelemetry-javaagent.jar \
-Dotel.javaagent.debug=false \
-XX:MaxRAMPercentage=65.0 \
-XX:+UseG1GC \
-XX:+ExitOnOutOfMemoryError"

# ⭐ everything else comes from the Deployment env (see below), but set sane defaults
ENV OTEL_SERVICE_NAME=shop-api \
    OTEL_RESOURCE_ATTRIBUTES=deployment.environment=dev,service.version=1.0.0,team=platform \
    OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_METRICS_EXPORTER=otlp \
    OTEL_LOGS_EXPORTER=none \
    OTEL_TRACES_SAMPLER=parentbased_traceidratio \
    OTEL_TRACES_SAMPLER_ARG=1.0 \
    OTEL_PROPAGATORS=tracecontext,baggage \
    OTEL_INSTRUMENTATION_HIBERNATE_ENABLED=true \
    OTEL_METRIC_EXPORT_INTERVAL=30000

ENTRYPOINT ["java","-jar","/app/app.jar"]
EOF

docker build --build-arg OTEL_AGENT_VERSION=2.11.0 -t ghcr.io/3558bhk/shop-api-traced:1.0.0 .
kind load docker-image ghcr.io/3558bhk/shop-api-traced:1.0.0 --name obs

# run it locally first — you should see the agent banner
docker run --rm -p 8080:8080 -p 9090:9090 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4317 \
  -e OTEL_TRACES_EXPORTER=otlp -e OTEL_LOGS_EXPORTER=console \
  ghcr.io/3558bhk/shop-api-traced:1.0.0 &
sleep 30
# [otel.javaagent 2026-09-09 …] INFO io.opentelemetry.javaagent.tooling.VersionLogger -
#   opentelemetry-javaagent - version: 2.11.0
curl -s -XPOST localhost:8080/api/orders -H 'Content-Type: application/json' -d '{"items":3,"tier":"gold"}'
# ⭐ look at the log line — it has trace_id and span_id:
# {"timestamp":"2026-09-09T16:12:44.182+05:30","level":"INFO","logger":"c.s.c.OrderController",
#  "thread":"http-nio-8080-exec-3",
#  "trace_id":"4bf92f3577b34da6a3ce929d0e0e4736",
#  "span_id":"00f067aa0ba902b7",
#  "trace_flags":"01","service":"shop-api",
#  "message":"order processed tier=gold items=3 status=created amount=4497","exception":""}
kill %1
```

### 3.3 Deploy it, pointed at the node agent

```bash
cd ~/observability-learn/case2

cat > manifests/shop-api-traced.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop-api, namespace: shop, labels: {app: shop-api}}
spec:
  replicas: 3
  strategy: {rollingUpdate: {maxSurge: 1, maxUnavailable: 0}}
  minReadySeconds: 15
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata:
      labels: {app: shop-api, team: platform}
    spec:
      securityContext: {runAsNonRoot: true, runAsUser: 10001, fsGroup: 10001, seccompProfile: {type: RuntimeDefault}}
      terminationGracePeriodSeconds: 45
      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api-traced:1.0.0
          ports:
            - {name: http,    containerPort: 8080}
            - {name: metrics, containerPort: 9090}
          env:
            # ⭐⭐ the OTel configuration — all of it, in one place
            - {name: OTEL_SERVICE_NAME, value: "shop-api"}
            - {name: OTEL_RESOURCE_ATTRIBUTES, value: "deployment.environment=dev,service.version=1.0.0,team=platform"}
            - {name: OTEL_PROPAGATORS, value: "tracecontext,baggage"}
            - {name: OTEL_TRACES_SAMPLER, value: "parentbased_traceidratio"}
            - {name: OTEL_TRACES_SAMPLER_ARG, value: "1.0"}        # ⭐ sample everything at the head;
                                                                   #   the GATEWAY does tail sampling
            - {name: OTEL_TRACES_EXPORTER, value: "otlp"}
            - {name: OTEL_METRICS_EXPORTER, value: "otlp"}
            - {name: OTEL_LOGS_EXPORTER, value: "none"}            # ⭐ logs go to stdout → filelog → Loki
            - {name: OTEL_EXPORTER_OTLP_PROTOCOL, value: "grpc"}
            # ⭐⭐ send to the AGENT ON THIS NODE, via the node IP and the DaemonSet's hostPort
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              valueFrom: {fieldRef: {fieldPath: status.hostIP}}
            - {name: OTEL_EXPORTER_OTLP_TIMEOUT, value: "10000"}
            - {name: OTEL_BSP_SCHEDULE_DELAY, value: "2000"}
            - {name: OTEL_BSP_MAX_QUEUE_SIZE, value: "4096"}
            - {name: DEPLOY_ENV, value: "dev"}
            - name: POD_NAME
              valueFrom: {fieldRef: {fieldPath: metadata.name}}
            - name: POD_IP
              valueFrom: {fieldRef: {fieldPath: status.podIP}}
          resources:
            requests: {cpu: 500m, memory: 1536Mi}     # ⭐ the agent adds ~150–250 MB
            limits:   {memory: 1536Mi}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          startupProbe:  {httpGet: {path: /actuator/health/liveness, port: 9090}, failureThreshold: 30, periodSeconds: 5}
          readinessProbe:{httpGet: {path: /actuator/health/readiness, port: 9090}, periodSeconds: 10, timeoutSeconds: 3}
          livenessProbe: {httpGet: {path: /actuator/health/liveness, port: 9090}, periodSeconds: 20, timeoutSeconds: 5}
          lifecycle: {preStop: {exec: {command: ["sh","-c","sleep 10"]}}}
          volumeMounts: [{name: tmp, mountPath: /tmp}]
      volumes: [{name: tmp, emptyDir: {sizeLimit: 256Mi}}]
EOF
```

⚠️ **The `status.hostIP` trick needs the agent DaemonSet to bind a `hostPort`**, so that `<nodeIP>:4317` reaches the agent on that node. Patch the DaemonSet:

```bash
kubectl patch ds otel-agent -n otel --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/ports/0/hostPort","value":4317},
  {"op":"add","path":"/spec/template/spec/containers/0/ports/1/hostPort","value":4318},
  {"op":"replace","path":"/spec/template/spec/hostNetwork","value":false}
]'
kubectl rollout status ds/otel-agent -n otel

# ⭐ the simpler and more common alternative: send to the agent SERVICE by DNS
kubectl patch deploy shop-api -n shop --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/env/8",
   "value":{"name":"OTEL_EXPORTER_OTLP_ENDPOINT",
            "value":"http://otel-collector-agent.otel.svc.cluster.local:4317"}}]'
```

> 🔑 **Two valid patterns, and you should know both:**
> - **`status.hostIP` + `hostPort`** → the app talks to the agent on *its own node* over the node network. Lowest latency, no cross-node traffic, works even if cluster DNS is broken. Requires `hostPort`, which limits one agent per node per port (fine for a DaemonSet).
> - **The agent Service by DNS** → simpler, no hostPort, but kube-proxy may route you to an agent on *another* node. Still fine, and easier to operate.
>
> Most production setups use the DNS form. Use `hostIP` when you want to guarantee node-local telemetry.

```bash
kubectl apply -f manifests/shop-api-traced.yaml
kubectl rollout status deploy/shop-api -n shop --timeout=300s

# generate traffic
kubectl run loadgen --image=curlimages/curl:8.10.1 -n shop --restart=Never \
  --command -- sh -c 'while true; do for i in $(seq 1 20); do
    curl -s -o /dev/null -XPOST http://shop-api/api/orders -H "Content-Type: application/json" -d "{\"items\":$((i%5+1)),\"tier\":\"gold\"}" &
    curl -s -o /dev/null http://shop-api/api/flaky &
    curl -s -o /dev/null http://shop-api/api/items &
  done; wait; sleep 1; done'

# ⭐ did the spans arrive?
sleep 60
kubectl port-forward -n monitoring svc/tempo 3200:3200 &
sleep 3
curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "shop-api" }' \
  --data-urlencode 'limit=5' | jq '.traces[] | {traceID, rootServiceName, rootTraceName, durationNanos, startTime}'
# {"traceID":"4bf92f…","rootServiceName":"shop-api","rootTraceName":"POST /api/orders",
#  "durationNanos":842000000,"startTime":"…"}
```

---

## 4. Step 4 — Instrument Python (zero-code)

```bash
mkdir -p app/order-worker && cd app/order-worker

cat > requirements.txt <<'EOF'
opentelemetry-distro==0.51b0
opentelemetry-exporter-otlp==1.30.0
opentelemetry-instrumentation-requests==0.51b0
opentelemetry-instrumentation-logging==0.51b0
opentelemetry-instrumentation-threading==0.51b0
prometheus-client==0.21.1
requests==2.32.3
EOF

cat > worker.py <<'EOF'
#!/usr/bin/env python3
"""A queue-consuming worker, instrumented with OpenTelemetry."""
import logging, os, random, signal, threading, time

import requests
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
from prometheus_client import Counter, Gauge, Histogram, start_http_server

# ⭐ the tracer — the SDK is configured by opentelemetry-instrument / env vars
tracer = trace.get_tracer("shop.order-worker", "1.0.0")

# ── structured logging WITH trace context ─────────────────────────
class TraceContextFilter(logging.Filter):
    """Inject trace_id / span_id into every log record."""
    def filter(self, record: logging.LogRecord) -> bool:
        span = trace.get_current_span()
        ctx = span.get_span_context()
        record.trace_id = format(ctx.trace_id, "032x") if ctx and ctx.trace_id else "-"
        record.span_id = format(ctx.span_id, "016x") if ctx and ctx.span_id else "-"
        return True

logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s",'
           '"trace_id":"%(trace_id)s","span_id":"%(span_id)s","message":"%(message)s"}',
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
logging.getLogger().addFilter(TraceContextFilter())
log = logging.getLogger("order-worker")

# ── metrics (unchanged from Case 1) ───────────────────────────────
JOBS = Counter("worker_jobs_processed_total", "Jobs processed", ["queue", "outcome"])
JOB_DURATION = Histogram("worker_job_duration_seconds", "Job duration", ["queue"],
                         buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10))
QUEUE_DEPTH = Gauge("worker_queue_depth", "Messages waiting", ["queue"])
IN_FLIGHT = Gauge("worker_jobs_in_flight", "Jobs in flight")

SHUTDOWN = threading.Event()
def _sigterm(signum, frame):
    log.info("SIGTERM received, draining…")
    SHUTDOWN.set()
signal.signal(signal.SIGTERM, _sigterm)
signal.signal(signal.SIGINT, _sigterm)


def call_payment_api(order_id: str) -> bool:
    """⭐ an OUTBOUND call — the requests instrumentation creates a CLIENT span
          and injects `traceparent` into the HTTP headers automatically."""
    url = os.environ.get("PAYMENT_URL", "http://shop-api.shop.svc.cluster.local/api/health")
    try:
        r = requests.get(url, timeout=5, headers={"X-Order-Id": order_id})
        return r.status_code < 500
    except requests.RequestException as exc:
        log.error("payment call failed order=%s: %s", order_id, exc)
        return False


def process_job(queue: str, batch: int) -> str:
    """⭐ a manual INTERNAL span for the domain work the auto-instrumentation can't see."""
    order_id = f"ord_{random.getrandbits(48):012x}"

    with tracer.start_as_current_span("process-order") as span:
        # ⭐⭐ searchable business attributes
        span.set_attribute("order.id", order_id)
        span.set_attribute("queue.name", queue)
        span.set_attribute("batch.size", batch)
        span.set_attribute("customer.tier", random.choice(["standard", "gold", "platinum"]))

        start = time.perf_counter()
        outcome = "success"
        try:
            span.add_event("validation.started")
            time.sleep(random.uniform(0.005, 0.05))
            span.add_event("validation.completed")

            # the outbound call becomes a CHILD span, automatically
            with tracer.start_as_current_span("reserve-inventory") as inv:
                inv.set_attribute("inventory.items", batch)
                time.sleep(random.uniform(0.01, 0.1))

            ok = call_payment_api(order_id)
            if not ok:
                outcome = "payment_failed"
                span.set_status(Status(StatusCode.ERROR, "payment provider unavailable"))
                span.add_event("payment.declined", {"reason": "provider_unavailable"})
                log.error("payment declined order=%s", order_id)

            if random.random() < 0.03:
                raise RuntimeError("simulated processing failure")

        except Exception as exc:                       # noqa: BLE001
            outcome = "error"
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            span.record_exception(exc)                 # ⭐ the stack trace becomes a span event
            log.exception("job failed order=%s", order_id)
        finally:
            elapsed = time.perf_counter() - start
            span.set_attribute("job.duration_seconds", elapsed)
            JOB_DURATION.labels(queue=queue).observe(elapsed)
            JOBS.labels(queue=queue, outcome=outcome).inc()

    # ⭐ the log line emitted INSIDE the span carries the same trace_id
    log.info("job processed queue=%s order=%s outcome=%s duration_ms=%.1f",
             queue, order_id, outcome, elapsed * 1000)
    return outcome


def main() -> None:
    start_http_server(int(os.environ.get("METRICS_PORT", "9092")))
    log.info("worker started metrics_port=%s", os.environ.get("METRICS_PORT", "9092"))

    while not SHUTDOWN.is_set():
        for queue in ("orders", "emails"):
            depth = random.randint(0, 250)
            QUEUE_DEPTH.labels(queue=queue).set(depth)

            while depth > 0 and not SHUTDOWN.is_set():
                batch = min(depth, random.randint(1, 20))
                IN_FLIGHT.inc()
                try:
                    # ⭐ the CONSUMER span — this is the trace's root for async work
                    with tracer.start_as_current_span(f"{queue}.consume") as consumer:
                        consumer.set_attribute("messaging.system", "rabbitmq")
                        consumer.set_attribute("messaging.destination.name", queue)
                        consumer.set_attribute("messaging.operation.name", "process")
                        consumer.set_attribute("messaging.batch.message_count", batch)
                        consumer.set_span_kind(trace.SpanKind.CONSUMER)
                        process_job(queue, batch)
                finally:
                    IN_FLIGHT.dec()
                    depth -= batch

        SHUTDOWN.wait(timeout=5)

    log.info("shutdown complete")
    # ⭐ flush before exit, or you lose the last spans
    trace.get_tracer_provider().force_flush(timeout_millis=10000)


if __name__ == "__main__":
    main()
EOF

cat > Dockerfile <<'EOF'
FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 10001 app && useradd -u 10001 -g app -s /bin/bash app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && opentelemetry-bootstrap -a install          # ⭐ installs instrumentation for detected libs
COPY worker.py .
USER 10001
ENV METRICS_PORT=9092 \
    PYTHONUNBUFFERED=1 \
    OTEL_SERVICE_NAME=order-worker \
    OTEL_RESOURCE_ATTRIBUTES=deployment.environment=dev,service.version=1.0.0 \
    OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_METRICS_EXPORTER=otlp \
    OTEL_LOGS_EXPORTER=none \
    OTEL_TRACES_SAMPLER=parentbased_traceidratio \
    OTEL_TRACES_SAMPLER_ARG=1.0 \
    OTEL_PROPAGATORS=tracecontext,baggage
EXPOSE 9092
# ⭐⭐ opentelemetry-instrument wraps the process and applies ALL the auto-instrumentation
ENTRYPOINT ["opentelemetry-instrument", "python", "worker.py"]
EOF

docker build -t ghcr.io/3558bhk/order-worker-traced:1.0.0 .
kind load docker-image ghcr.io/3558bhk/order-worker-traced:1.0.0 --name obs
cd ../..
```

```bash
# test locally — console exporter so you SEE the spans
docker run --rm -e OTEL_TRACES_EXPORTER=console -e OTEL_METRICS_EXPORTER=none \
  -e OTEL_LOGS_EXPORTER=none -p 9092:9092 ghcr.io/3558bhk/order-worker-traced:1.0.0 2>&1 | head -60
# {"name": "orders.consume", "context": {"trace_id": "0x4bf9…", "span_id": "0x00f0…", …},
#  "kind": "SpanKind.CONSUMER", "start_time": "…", "end_time": "…",
#  "attributes": {"messaging.system": "rabbitmq", "messaging.destination.name": "orders", …},
#  "events": [{"name": "validation.started", …}], "status": {"status_code": "UNSET"}}
#   {"name": "process-order", …  "parent_id": "0x00f0…"}      ← ⭐ a child span
#     {"name": "GET", …        "parent_id": "…"}              ← ⭐ the requests CLIENT span
```

---

## 5. Step 5 — Instrument Go (manual — there is no zero-code for Go)

Go is statically compiled, so there's no agent. You instrument explicitly. The upside: total control and near-zero overhead.

```bash
mkdir -p app/checkout && cd app/checkout
cat > go.mod <<'EOF'
module github.com/3558bhk/checkout

go 1.23

require (
	github.com/prometheus/client_golang v1.20.5
	go.opentelemetry.io/otel v1.33.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.33.0
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc v1.33.0
	go.opentelemetry.io/otel/sdk v1.33.0
	go.opentelemetry.io/otel/sdk/metric v1.33.0
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.58.0
	go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc v0.58.0
)
EOF
```

**`otel.go`** — the one-time setup:

```go
package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// InitTelemetry sets up the global TracerProvider and MeterProvider.
// ⭐ Call ONCE at startup; hold the returned shutdown func and call it on exit.
func InitTelemetry(ctx context.Context, serviceName, version, env string) (func(context.Context) error, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-collector-agent.otel.svc.cluster.local:4317"
	}

	// ── the resource: WHO is producing this telemetry ────────────
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),                       // ⭐⭐ THE most important attribute
			semconv.ServiceVersion(version),
			semconv.ServiceNamespace("shop"),
			semconv.ServiceInstanceID(os.Getenv("HOSTNAME")),       // the pod name
			semconv.DeploymentEnvironmentName(env),
			attribute.String("team", "platform"),
		),
		resource.WithHost(),        // host.name, host.arch
		resource.WithOS(),          // os.type, os.description
		resource.WithProcess(),     // process.pid, process.executable.name
		resource.WithContainer(),   // container.id
		resource.WithFromEnv(),     // ⭐ merges OTEL_RESOURCE_ATTRIBUTES
	)
	if err != nil {
		return nil, fmt.Errorf("resource: %w", err)
	}

	// ── the trace exporter ───────────────────────────────────────
	traceExp, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(stripScheme(endpoint)),
		otlptracegrpc.WithInsecure(),
		otlptracegrpc.WithDialOption(),
		otlptracegrpc.WithCompressor("gzip"),
		otlptracegrpc.WithRetry(otlptracegrpc.RetryConfig{
			Enabled:         true,
			InitialInterval: 5 * time.Second,
			MaxInterval:     30 * time.Second,
			MaxElapsedTime:  5 * time.Minute,
		}),
	)
	if err != nil {
		return nil, fmt.Errorf("trace exporter: %w", err)
	}

	// ── the TracerProvider ───────────────────────────────────────
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithResource(res),
		sdktrace.WithBatcher(traceExp,
			sdktrace.WithBatchTimeout(2*time.Second),
			sdktrace.WithMaxExportBatchSize(2048),
			sdktrace.WithMaxQueueSize(8192),
			sdktrace.WithExportTimeout(10*time.Second),
		),
		// ⭐ head sampling. The GATEWAY does tail sampling, so keep 100% here.
		sdktrace.WithSampler(sdktrace.ParentBased(
			sdktrace.TraceIDRatioBased(1.0),
		)),
		sdktrace.WithSpanLimits(sdktrace.SpanLimits{
			AttributeValueLengthLimit:   1024,   // ⭐ bound attribute size
			AttributeCountLimit:           64,
			EventCountLimit:               64,
			LinkCountLimit:                32,
			MaxEventsPerSpan:              64,
		}),
	)
	otel.SetTracerProvider(tp)

	// ⭐⭐ THE PROPAGATORS. Without this, traces don't cross service boundaries.
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},   // W3C traceparent
		propagation.Baggage{},        // W3C baggage
	))

	// ── the metric exporter (optional; Prometheus scraping also works) ──
	metricExp, err := otlpmetricgrpc.New(ctx,
		otlpmetricgrpc.WithEndpoint(stripScheme(endpoint)),
		otlpmetricgrpc.WithInsecure(),
	)
	if err != nil {
		return nil, fmt.Errorf("metric exporter: %w", err)
	}
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExp,
			sdkmetric.WithInterval(30*time.Second))),
		// ⭐ exponential histograms = OTel's native histograms
		sdkmetric.WithView(sdkmetric.NewView(
			sdkmetric.Instrument{Name: "shop.checkout.duration"},
			sdkmetric.Stream{Aggregation: sdkmetric.AggregationBase2ExponentialHistogram{
				MaxSize:  160,
				MaxScale: 20,
				NoMinMax: false,
			}},
		)),
	)
	otel.SetMeterProvider(mp)

	shutdown := func(ctx context.Context) error {
		var errs []error
		if err := tp.Shutdown(ctx); err != nil {
			errs = append(errs, err)
		}
		if err := mp.Shutdown(ctx); err != nil {
			errs = append(errs, err)
		}
		if len(errs) > 0 {
			return fmt.Errorf("shutdown: %v", errs)
		}
		return nil
	}
	return shutdown, nil
}

func stripScheme(ep string) string {
	for _, p := range []string{"http://", "https://"} {
		if len(ep) > len(p) && ep[:len(p)] == p {
			return ep[len(p):]
		}
	}
	return ep
}
```

**`main.go`**

```go
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

var tracer = otel.Tracer("shop.checkout")

var (
	checkouts = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "shop_checkouts_total", Help: "Checkout attempts.",
	}, []string{"method", "status"})
	checkoutDur = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name: "shop_checkout_duration_seconds", Help: "Checkout latency.",
		Buckets: []float64{.01, .025, .05, .1, .2, .3, .5, 1, 2, 5},
	}, []string{"method", "status"})
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// ⭐ 1. initialise telemetry FIRST
	shutdown, err := InitTelemetry(ctx, "checkout", "1.0.0",
		os.Getenv("DEPLOY_ENV"))
	if err != nil {
		slog.Error("telemetry init failed", "err", err)
		os.Exit(1)
	}
	defer func() {
		sctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := shutdown(sctx); err != nil {   // ⭐ 4. FLUSH before exiting
			slog.Error("telemetry shutdown failed", "err", err)
		}
	}()

	// ⭐ structured logging that includes trace_id
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			return a
		},
	}))
	slog.SetDefault(logger)

	// ⭐ 2. the app handler, wrapped so every request gets a SERVER span
	mux := http.NewServeMux()
	mux.HandleFunc("POST /checkout", handleCheckout)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })

	appServer := &http.Server{
		Addr:              ":8080",
		Handler:           otelhttp.NewHandler(mux, "checkout"),   // ⭐ SERVER spans
		ReadHeaderTimeout: 5 * time.Second,
	}

	// ⭐ 3. metrics on a separate server, NOT instrumented (or it traces its own scrapes)
	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.Handler())
	metricsMux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
	metricsServer := &http.Server{Addr: ":9091", Handler: metricsMux, ReadHeaderTimeout: 5 * time.Second}

	go func() { _ = metricsServer.ListenAndServe() }()
	go func() {
		if err := appServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server failed", "err", err)
		}
	}()

	slog.Info("checkout listening", "app", ":8080", "metrics", ":9091")
	<-ctx.Done()
	slog.Info("shutting down")
	sctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	_ = appServer.Shutdown(sctx)
	_ = metricsServer.Shutdown(sctx)
}

func handleCheckout(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	ctx := r.Context()

	// ⭐ the otelhttp wrapper already created a SERVER span; get it
	span := trace.SpanFromContext(ctx)

	orderID := fmt.Sprintf("ord_%d", rand.Int63n(1<<40))
	items := 1 + rand.Intn(5)
	customerTier := r.Header.Get("X-Customer-Tier")
	if customerTier == "" {
		customerTier = "standard"
	}

	// ⭐⭐ BUSINESS ATTRIBUTES — these make traces searchable in TraceQL
	span.SetAttributes(
		attribute.String("order.id", orderID),
		attribute.Int("cart.items", items),
		attribute.String("customer.tier", customerTier),
		attribute.String("url.path", "/checkout"),
	)

	// ── a manual child span for a domain operation ────────────────
	status := http.StatusCreated
	var reserveErr error

	_, reserveSpan := tracer.Start(ctx, "reserve-inventory",
		trace.WithSpanKind(trace.SpanKindInternal),
		trace.WithAttributes(
			attribute.String("order.id", orderID),
			attribute.Int("inventory.items", items),
		))
	time.Sleep(time.Duration(10+rand.Intn(90)) * time.Millisecond)
	if rand.Intn(100) < 3 {
		reserveErr = errors.New("inventory unavailable")
		reserveSpan.SetStatus(codes.Error, reserveErr.Error())
		reserveSpan.RecordError(reserveErr)              // ⭐ the error becomes a span event
		reserveSpan.AddEvent("inventory.shortfall", trace.WithAttributes(
			attribute.Int("inventory.requested", items),
			attribute.Int("inventory.available", rand.Intn(items)),
		))
	}
	reserveSpan.End()

	// ── an OUTBOUND call: propagate the context into the headers ──
	if reserveErr == nil {
		payCtx, paySpan := tracer.Start(ctx, "POST /api/payment",
			trace.WithSpanKind(trace.SpanKindClient),
			trace.WithAttributes(
				attribute.String("server.address", "shop-api.shop.svc.cluster.local"),
				attribute.Int("server.port", 80),
				attribute.String("order.id", orderID),
			))

		req, _ := http.NewRequestWithContext(payCtx, http.MethodPost,
			"http://shop-api.shop.svc.cluster.local/api/orders",
			http.NoBody)

		// ⭐⭐ INJECT the traceparent header — this is what links the two services
		otel.GetTextMapPropagator().Inject(payCtx, propagation.HeaderCarrier(req.Header))

		client := &http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport), Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			paySpan.RecordError(err)
			paySpan.SetStatus(codes.Error, err.Error())
			status = http.StatusBadGateway
		} else {
			paySpan.SetAttributes(attribute.Int("http.response.status_code", resp.StatusCode))
			if resp.StatusCode >= 500 {
				paySpan.SetStatus(codes.Error, fmt.Sprintf("upstream %d", resp.StatusCode))
				status = http.StatusBadGateway
			}
			resp.Body.Close()
		}
		paySpan.End()
	} else {
		status = http.StatusConflict
	}

	if reserveErr != nil {
		span.SetStatus(codes.Error, reserveErr.Error())
		span.SetAttributes(attribute.String("error.type", "inventory_unavailable"))
	}

	elapsed := time.Since(start).Seconds()
	st := strconv.Itoa(status)
	checkoutDur.WithLabelValues(r.Method, st).Observe(elapsed)
	checkouts.WithLabelValues(r.Method, st).Inc()

	// ⭐ the log line, carrying the trace_id
	sc := span.SpanContext()
	slog.InfoContext(ctx, "checkout completed",
		"order_id", orderID,
		"status", status,
		"duration_ms", int(elapsed*1000),
		"trace_id", sc.TraceID().String(),      // ⭐⭐ THE LOG↔TRACE LINK
		"span_id", sc.SpanID().String(),
		"customer_tier", customerTier,
	)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write([]byte(fmt.Sprintf(
		`{"order_id":%q,"status":%d,"duration_ms":%d,"trace_id":%q}`,
		orderID, status, int(elapsed*1000), sc.TraceID().String())))
}
```

```bash
go mod tidy
cat > Dockerfile <<'EOF'
FROM golang:1.23-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/checkout .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/checkout /checkout
USER nonroot:nonroot
EXPOSE 8080 9091
ENV OTEL_SERVICE_NAME=checkout \
    OTEL_RESOURCE_ATTRIBUTES=deployment.environment=dev,service.version=1.0.0 \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-agent.otel.svc.cluster.local:4317 \
    OTEL_PROPAGATORS=tracecontext,baggage
ENTRYPOINT ["/checkout"]
EOF

docker build -t ghcr.io/3558bhk/checkout-traced:1.0.0 .
kind load docker-image ghcr.io/3558bhk/checkout-traced:1.0.0 --name obs
cd ../..
```

> 🔑 **The four things you must not forget in Go:**
> 1. `otel.SetTextMapPropagator(propagation.TraceContext{})` — **without this, no propagation.**
> 2. `otelhttp.NewHandler(mux, …)` on the server — creates SERVER spans.
> 3. `otel.GetTextMapPropagator().Inject(ctx, carrier)` on outbound calls — writes `traceparent`.
> 4. `provider.Shutdown(ctx)` before exit — **flushes the batch queue.** Skip it and you lose the last few seconds of spans on every deploy.

---

## 6. Step 6 — Instrument the browser (React)

Real-user monitoring: the trace **starts in the browser**, so you see the network time, the backend time, and the user's actual experience in one waterfall.

```bash
mkdir -p app/shop-ui && cd app/shop-ui
```

**`src/otel.js`**

```javascript
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { DocumentLoadInstrumentation } from '@opentelemetry/instrumentation-document-load';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { XMLHttpRequestInstrumentation } from '@opentelemetry/instrumentation-xml-http-request';
import { UserInteractionInstrumentation } from '@opentelemetry/instrumentation-user-interaction';
import { Resource } from '@opentelemetry/resources';
import {
  SEMRESATTRS_SERVICE_NAME,
  SEMRESATTRS_SERVICE_VERSION,
  SEMRESATTRS_DEPLOYMENT_ENVIRONMENT,
} from '@opentelemetry/semantic-conventions';
import { W3CTraceContextPropagator, W3CBaggagePropagator } from '@opentelemetry/core';
import { CompositePropagator } from '@opentelemetry/api';

export function initOtel() {
  const resource = new Resource({
    [SEMRESATTRS_SERVICE_NAME]: 'shop-ui',                 // ⭐⭐ the service name in Tempo
    [SEMRESATTRS_SERVICE_VERSION]: process.env.REACT_APP_VERSION || '1.0.0',
    [SEMRESATTRS_DEPLOYMENT_ENVIRONMENT]: process.env.REACT_APP_ENV || 'dev',
    'browser.platform': navigator.platform,
  });

  const provider = new WebTracerProvider({ resource });

  provider.addSpanProcessor(
    new BatchSpanProcessor(
      // ⭐ OTLP/HTTP straight to the Collector. CORS must allow your origin!
      new OTLPTraceExporter({
        url: `${process.env.REACT_APP_OTLP_ENDPOINT || 'http://localhost:4318'}/v1/traces`,
        // headers: { 'x-api-key': '…' },
      }),
      { scheduledDelayMillis: 3000, maxQueueSize: 2048, maxExportBatchSize: 512 },
    ),
  );

  provider.register({
    propagator: new CompositePropagator({
      propagators: [new W3CTraceContextPropagator(), new W3CBaggagePropagator()],
    }),
  });

  registerInstrumentations({
    instrumentations: [
      new DocumentLoadInstrumentation(),          // ⭐ navigation timing: DNS, TCP, TLS, TTFB, paint
      new FetchInstrumentation({
        propagateTraceHeaderCorsUrls: [           // ⭐⭐ WITHOUT THIS, the trace stops at the browser
          /localhost:8080/,
          /shop\.example\.com/,
          /api\.shop\.example\.com/,
        ],
        ignoreUrls: [/\/metrics$/, /\/health$/, /google-analytics/],
        clearTimingResources: true,
      }),
      new XMLHttpRequestInstrumentation({
        propagateTraceHeaderCorsUrls: [/shop\.example\.com/],
      }),
      new UserInteractionInstrumentation(),       // ⭐ clicks as spans
    ],
  });

  return provider;
}
```

**`src/index.js`**

```javascript
import { initOtel } from './otel';
initOtel();                              // ⭐ BEFORE React renders
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
createRoot(document.getElementById('root')).render(<React.StrictMode><App /></React.StrictMode>);
```

**`src/api.js`** — adding business attributes to your own spans:

```javascript
import { trace, SpanStatusCode, SpanKind } from '@opentelemetry/api';
import { propagation, context } from '@opentelemetry/api';

const tracer = trace.getTracer('shop-ui.checkout', '1.0.0');

export async function placeOrder(cart, customerTier) {
  // ⭐ a manual span around the whole user-facing operation
  return tracer.startActiveSpan(
    'checkout.placeOrder',
    { kind: SpanKind.CLIENT, attributes: {
        'cart.items': cart.length,
        'cart.total_cents': cart.reduce((s, i) => s + i.priceCents, 0),
        'customer.tier': customerTier,
        'ui.flow': 'checkout',
    }},
    async (span) => {
      try {
        // the FetchInstrumentation creates a CHILD span and injects traceparent automatically
        const res = await fetch('/api/orders', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Customer-Tier': customerTier },
          body: JSON.stringify({ items: cart.length, tier: customerTier }),
        });

        span.setAttribute('http.response.status_code', res.status);

        if (!res.ok) {
          span.setStatus({ code: SpanStatusCode.ERROR, message: `HTTP ${res.status}` });
          span.addEvent('order.rejected', { 'http.response.status_code': res.status });
        }
        const body = await res.json();
        span.setAttribute('order.id', body.orderId ?? 'rejected');
        return body;
      } catch (err) {
        span.recordException(err);
        span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
        throw err;
      } finally {
        span.end();                        // ⭐ always end it
      }
    },
  );
}
```

**CORS on the Collector** — the browser enforces CORS, so the OTLP/HTTP receiver must allow your origin:

```yaml
# in collector/agent-config.yaml — already set above ⭐
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins: ["http://localhost:3001", "https://shop.example.com"]
          allowed_headers: ["*"]
          max_age: 7200
```

⚠️ **Never expose :4318 to the public internet.** Put it behind your Ingress with an allowlist, a separate hostname (`otel.shop.example.com`), rate limiting, and an API key — or use the OTLP/HTTP endpoint on a gateway with authentication. An open OTLP endpoint is a free telemetry-injection and cost-amplification vector.

```bash
# build and deploy
cat > Dockerfile <<'EOF'
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG REACT_APP_OTLP_ENDPOINT=https://otel.shop.example.com
ARG REACT_APP_VERSION=1.0.0
ENV REACT_APP_OTLP_ENDPOINT=$REACT_APP_OTLP_ENDPOINT REACT_APP_VERSION=$REACT_APP_VERSION
RUN npm run build

FROM nginx:1.29-alpine
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
USER 10001
EXPOSE 8080
EOF
docker build -t ghcr.io/3558bhk/shop-ui:1.0.0 .
kind load docker-image ghcr.io/3558bhk/shop-ui:1.0.0 --name obs
cd ../..
```

---

## 7. Step 7 — Deploy everything and watch a full trace

```bash
cat > manifests/shop-services.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: checkout, namespace: shop, labels: {app: checkout}}
spec:
  replicas: 2
  selector: {matchLabels: {app: checkout}}
  template:
    metadata: {labels: {app: checkout, team: platform}}
    spec:
      containers:
        - name: checkout
          image: ghcr.io/3558bhk/checkout-traced:1.0.0
          ports: [{name: http, containerPort: 8080}, {name: metrics, containerPort: 9091}]
          env:
            - {name: OTEL_EXPORTER_OTLP_ENDPOINT, value: "http://otel-collector-agent.otel.svc.cluster.local:4317"}
            - {name: DEPLOY_ENV, value: "dev"}
          resources: {requests: {cpu: 100m, memory: 64Mi}, limits: {memory: 128Mi}}
          readinessProbe: {httpGet: {path: /healthz, port: 9091}}
---
apiVersion: v1
kind: Service
metadata: {name: checkout, namespace: shop, labels: {app: checkout}}
spec:
  selector: {app: checkout}
  ports: [{name: http, port: 80, targetPort: 8080}, {name: metrics, port: 9091, targetPort: 9091}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: order-worker, namespace: shop, labels: {app: order-worker}}
spec:
  replicas: 2
  selector: {matchLabels: {app: order-worker}}
  template:
    metadata: {labels: {app: order-worker}}
    spec:
      containers:
        - name: worker
          image: ghcr.io/3558bhk/order-worker-traced:1.0.0
          ports: [{name: metrics, containerPort: 9092}]
          env:
            - {name: OTEL_EXPORTER_OTLP_ENDPOINT, value: "http://otel-collector-agent.otel.svc.cluster.local:4317"}
          resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {memory: 256Mi}}
EOF
kubectl apply -f manifests/shop-services.yaml
kubectl rollout status deploy/checkout -n shop
kubectl rollout status deploy/order-worker -n shop
```

### The end-to-end propagation test ⭐

```bash
# send ONE request with a traceparent we chose, then find it
TRACE_ID=$(openssl rand -hex 16)
PARENT=$(openssl rand -hex 8)
echo "our trace id: $TRACE_ID"

kubectl exec -n shop deploy/checkout -- wget -qO- \
  --header="traceparent: 00-$TRACE_ID-$PARENT-01" \
  --header="X-Customer-Tier: gold" \
  --post-data='' http://localhost:8080/checkout
# {"order_id":"ord_123456","status":201,"duration_ms":184,"trace_id":"<our trace id>"}
#                                                                    ↑ ⭐ IT PROPAGATED

# now fetch the whole trace
sleep 15
kubectl port-forward -n monitoring svc/tempo 3200:3200 &
sleep 3
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq -r '
  .batches[] | .resource.attributes[] as $a | select($a.key=="service.name") | $a.value.stringValue' | sort -u
# checkout
# shop-api          ← ⭐ TWO SERVICES IN ONE TRACE

curl -s "localhost:3200/api/traces/$TRACE_ID" | jq '
  [.batches[].scopeSpans[].spans[] | {
     name,
     kind,
     parentSpanId,
     start: (.startTimeUnixNano|tonumber/1e6|floor),
     dur_ms: (((.endTimeUnixNano|tonumber) - (.startTimeUnixNano|tonumber))/1e6|floor),
     status: .status.code,
     attrs: (.attributes // [] | map({(.key): .value}) | add)
   }] | sort_by(.start)'
```

You should see something like:

```json
[
  {"name":"POST /checkout",        "kind":"SERVER", "parentSpanId":"a2fb4a1d1a96d312", "dur_ms":184,
   "attrs":{"order.id":"ord_…","cart.items":3,"customer.tier":"gold","url.path":"/checkout"}},
  {"name":"reserve-inventory",     "kind":"INTERNAL","parentSpanId":"<POST /checkout>", "dur_ms":62,
   "attrs":{"inventory.items":3,"order.id":"ord_…"}},
  {"name":"POST /api/payment",     "kind":"CLIENT", "parentSpanId":"<POST /checkout>", "dur_ms":110},
  {"name":"POST /api/orders",      "kind":"SERVER", "parentSpanId":"<POST /api/payment>","dur_ms":104,
   "attrs":{"http.route":"/api/orders","http.response.status_code":201}},
  {"name":"validate-and-price-cart","kind":"INTERNAL","parentSpanId":"<POST /api/orders>","dur_ms":41},
  {"name":"SELECT shop.inventory", "kind":"CLIENT", "parentSpanId":"<POST /api/orders>","dur_ms":18,
   "attrs":{"db.system":"postgresql","db.namespace":"shop"}}
]
```

**That is a distributed trace: two services, five spans, one causal chain, from a single curl.**

---

## 8. Step 8 — Logs into Loki

Two ways. Do the second one; it's the production answer.

### 8.1 Way A — the Collector's `filelog` receiver (already configured)

The gateway config in §2.2 has a `filelog` receiver reading `/var/log/pods/*/*/*.log` and extracting `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name`, `trace.id` and `span.id`. **Any app that writes JSON to stdout gets into Loki with trace context for free — no app changes.**

```bash
# it needs to run where the logs are. Add a DaemonSet variant, or mount /var/log/pods
# into the gateway. The clean way is a dedicated DaemonSet:
cat > manifests/otel-logs-agent.yaml <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: otel-logs-agent, namespace: otel, labels: {app: otel-logs-agent}}
spec:
  selector: {matchLabels: {app: otel-logs-agent}}
  template:
    metadata: {labels: {app: otel-logs-agent}}
    spec:
      serviceAccountName: otel-agent
      priorityClassName: system-node-critical
      containers:
        - name: collector
          image: otel/opentelemetry-collector-contrib:0.158.0
          args: ["--config=/etc/otel/config.yaml"]
          env:
            - {name: MY_NODE_NAME, valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}
            - {name: GOMEMLIMIT, value: "450MiB"}
          resources: {requests: {cpu: 100m, memory: 256Mi}, limits: {memory: 512Mi}}
          volumeMounts:
            - {name: config, mountPath: /etc/otel}
            - {name: varlogpods, mountPath: /var/log/pods, readOnly: true}
            - {name: varlogcontainers, mountPath: /var/log/containers, readOnly: true}
      volumes:
        - {name: config, configMap: {name: otel-logs-config}}
        - {name: varlogpods, hostPath: {path: /var/log/pods, type: Directory}}
        - {name: varlogcontainers, hostPath: {path: /var/log/containers, type: Directory}}
EOF

cat > collector/logs-config.yaml <<'EOF'
receivers:
  filelog:
    include: [/var/log/pods/*/*/*.log]
    exclude:
      - /var/log/pods/otel_*/otel-logs-agent-*/*.log
      - /var/log/pods/kube-system_*/kube-apiserver-*/*.log
    include_file_path: true
    start_at: end
    operators:
      - type: json_parser
        parse_from: body
        parse_to: attributes
        timestamp: {parse_from: attributes.time, layout: '%Y-%m-%dT%H:%M:%S.%fZ'}
        on_error: send
      - type: regex_parser
        parse_from: attributes["log.file.path"]
        regex: '^/var/log/pods/(?P<ns>[^_]+)_(?P<pod>[^_]+)_(?P<uid>[^/]+)/(?P<container>[^/]+)/'
        on_error: send
      - {type: move, from: attributes.ns,        to: resource["k8s.namespace.name"],   on_error: send}
      - {type: move, from: attributes.pod,       to: resource["k8s.pod.name"],         on_error: send}
      - {type: move, from: attributes.container, to: resource["k8s.container.name"],   on_error: send}
      - {type: move, from: attributes.stream,    to: attributes["log.iostream"],       on_error: send}
      # ⭐ trace context, if the app emitted it
      - {type: move, from: attributes.trace_id,  to: attributes["trace.id"],           on_error: send}
      - {type: move, from: attributes.span_id,   to: attributes["span.id"],            on_error: send}
      # ⭐ promote the level to severity so Loki can filter on it
      - type: severity_parser
        parse_from: attributes.level
        preset: none
        mapping:
          trace:  [TRACE]
          debug:  [DEBUG]
          info:   [INFO]
          warn:   [WARN, WARNING]
          error:  [ERROR]
          fatal:  [FATAL]
        on_error: send

processors:
  memory_limiter: {check_interval: 1s, limit_percentage: 80, spike_limit_percentage: 25}
  resource:
    attributes:
      - {key: k8s.cluster.name, value: learn, action: upsert}
      - {key: k8s.node.name,    value: "${env:MY_NODE_NAME}", action: upsert}
  batch: {send_batch_size: 4096, timeout: 3s}

exporters:
  loki:
    endpoint: http://loki.monitoring.svc:3100/loki/api/v1/push
    default_labels_enabled: {exporter: false, job: false, instance: false, level: true}
  prometheus: {endpoint: 0.0.0.0:8888}

service:
  telemetry: {logs: {level: info}, metrics: {level: normal, readers: [{pull: {exporter: {prometheus: {host: 0.0.0.0, port: 8888}}}}]}}
  pipelines:
    logs:
      receivers: [filelog]
      processors: [memory_limiter, resource, batch]
      exporters: [loki]
EOF

kubectl create configmap otel-logs-config -n otel --from-file=config.yaml=collector/logs-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f manifests/otel-logs-agent.yaml
kubectl rollout status ds/otel-logs-agent -n otel

# verify
kubectl port-forward -n monitoring svc/loki 3100:3100 &
sleep 3
curl -sG 'localhost:3100/loki/api/v1/labels' | jq .
# {"status":"success","data":["cluster","container","exporter","level","namespace","pod","service_name"]}
curl -sG 'localhost:3100/loki/api/v1/label/namespace/values' | jq .
curl -sG 'localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="shop"}' \
  --data-urlencode "start=$(date -d '-10 min' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" --data-urlencode 'limit=5' \
  | jq -r '.data.result[].values[][1]' | head -5
# {"timestamp":"…","level":"INFO","logger":"c.s.c.OrderController","thread":"http-nio-8080-exec-3",
#  "trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","span_id":"00f067aa0ba902b7", …}
```

### 8.2 Way B — ship logs from the app over OTLP (better for correlation)

Set `OTEL_LOGS_EXPORTER=otlp` and let the SDK's log appender push structured logs directly. The advantage: **trace context is attached by the SDK, not parsed back out with a regex.**

```xml
<!-- Java: the Logback OTLP appender -->
<dependency>
  <groupId>io.opentelemetry.instrumentation</groupId>
  <artifactId>opentelemetry-logback-appender-1.0</artifactId>
  <version>2.11.0-alpha</version>
</dependency>
```
```xml
<!-- logback-spring.xml -->
<configuration>
  <appender name="OTLP" class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
    <captureExperimentalAttributes>true</captureExperimentalAttributes>
    <captureKeyValuePairAttributes>true</captureKeyValuePairAttributes>
  </appender>
  <root level="INFO"><appender-ref ref="OTLP"/></root>
</configuration>
```

```bash
# Python: the LoggingHandler
export OTEL_LOGS_EXPORTER=otlp
# and in code:
```
```python
from opentelemetry.instrumentation.logging import LoggingInstrumentor
LoggingInstrumentor().instrument(set_logging_format=True)
# → %(otelTraceID)s %(otelSpanID)s %(otelServiceName)s are now available in the format string
```

> 🔑 **Which to choose?** Way A (`filelog`) is **zero app changes** and works for every container in the cluster — that's why it's the default. Way B (OTLP logs) gives **exact** correlation and structured attributes, at the cost of an app dependency and more egress. Most teams run **both**: `filelog` for everything, OTLP logs for the services where correlation matters most.

### 8.3 LogQL — the queries you'll actually use

```bash
kubectl port-forward -n monitoring svc/loki 3100:3100 &
```

```logql
# ── selectors ────────────────────────────────────────────────────
{namespace="shop"}                                  # a stream selector (labels only)
{namespace="shop", app="shop-api"}
{namespace="shop", level="ERROR"}                   # ⭐ if `level` is a Loki label
{namespace=~"shop|checkout"}
{namespace="shop"} != "health"                      # line filters (cheap, run first)
{namespace="shop"} |= "error"                       # contains
{namespace="shop"} |~ "(?i)timeout|refused"         # regex contains
{namespace="shop"} != ""

# ── parsing ──────────────────────────────────────────────────────
{namespace="shop"} | json                           # ⭐ parse JSON lines into labels
{namespace="shop"} | json | level="ERROR"
{namespace="shop"} | json | line_format "{{.message}} ({{.trace_id}})"
{namespace="shop"} | json | unwrap duration_ms > 500
{namespace="shop"} | logfmt                          # key=value lines
{namespace="shop"} | pattern `<_> <level> <_> - <message>`
{namespace="shop"} | regexp `trace_id=(?P<tid>[a-f0-9]{32})`

# ── THE correlation queries ⭐⭐ ──────────────────────────────────
# all logs for one trace
{namespace="shop"} | json | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"

# all logs for one order, across every service
{namespace="shop"} | json | order_id="ord_9f2a1b3c"

# ── aggregation ──────────────────────────────────────────────────
sum by (app) (count_over_time({namespace="shop", level="ERROR"}[5m]))
sum by (namespace) (rate({namespace=~".+"} |~ "(?i)error|exception" [5m]))
topk(5, sum by (pod) (count_over_time({namespace="shop"} |= "ERROR" [1h])))

# ⭐ the error rate as a ratio (for an SLO from logs)
sum(rate({namespace="shop"} | json | level="ERROR" [5m]))
  / sum(rate({namespace="shop"} | json [5m]))

# the p99 of a parsed duration field
quantile_over_time(0.99,
  {namespace="shop", app="shop-api"} | json | unwrap duration_ms [5m]) by (uri)

# how many distinct orders failed?
count(sum by (order_id) (count_over_time({namespace="shop"} | json | level="ERROR" [1h])))
```

```bash
# query Loki from the CLI
curl -sG 'localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query=sum by (level) (count_over_time({namespace="shop"} | json [5m]))' \
  --data-urlencode "start=$(date -d '-1 hour' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'step=60' | jq '.data.result[].metric'
```

> ⚠️ **Loki labels are Prometheus labels — the same cardinality rules apply.** `namespace`, `app`, `level`, `container` are fine. **Never** make `trace_id`, `order_id`, `user_id` or `request_path` a *label*; keep them in the log line and filter with `| json | trace_id="…"`. A Loki instance with unbounded labels becomes unqueryable exactly like an over-cardinal Prometheus.

---

## 9. Step 9 — Correlation: the payoff

### 9.1 Metrics → traces (exemplars)

An **exemplar** is a single trace ID attached to a histogram bucket, so you can click a spike on a latency graph and land on a real example.

```bash
# 1. Prometheus must accept exemplars (enabled by default in 3.x with native/OTLP)
kubectl patch prometheus kps-kube-prometheus-stack-prometheus -n monitoring --type=merge \
  -p '{"spec":{"enableFeatures":["exemplar-storage","native-histogram","otlp-write-receiver"]}}'

# 2. ⭐ the app must EXPOSE exemplars in its /metrics output.
#    Micrometer does this when a Tracer is present:
kubectl exec -n shop deploy/shop-api -- wget -qO- http://localhost:9090/prometheus \
  | grep -A2 '^http_server_requests_seconds_bucket' | head -10
# http_server_requests_seconds_bucket{...,le="0.5"} 1243 # {trace_id="4bf92f3577b34da6a3ce929d0e0e4736"} 0.412 1757412345.123
#                                                              ↑ ⭐ the exemplar, in OpenMetrics format
#    Go: use promhttp.HandlerOpts{EnableOpenMetrics: true} and record exemplars via
#        prometheus.NewHistogramVec(...).(prometheus.ExemplarObserver).ObserveWithExemplar(v, labels)
```

```bash
# 3. Grafana must scrape with OpenMetrics enabled — the Prometheus datasource does this
#    automatically when jsonData.prometheusType = Prometheus and the version is 3.x.

# 4. verify exemplars reached Prometheus
curl -sG 'localhost:9090/api/v1/query' \
  --data-urlencode 'query=http_server_requests_seconds_count{application="shop-api"}' | jq '.data.result[0]'
```

**In Grafana:** open the shop-api latency panel → hover over a spike → a small **green diamond** appears on the point → click it → **the exact trace opens in Tempo.** That's the whole incident workflow in one click.

### 9.2 Traces → logs (derived fields)

Already wired in §1.3: `derivedFields` on the Loki datasource matches `"trace_id"\s*:\s*"(\w+)"` and renders a **View trace** link on every log line.

And on the Tempo datasource, `tracesToLogs` adds a **Logs for this span** button in the trace view.

### 9.3 The full loop, demonstrated

```bash
# 1. generate an incident
kubectl exec -n shop deploy/loadgen -- sh -c 'for i in $(seq 1 300); do curl -s -o /dev/null http://shop-api/api/flaky; done'

# 2. in Grafana → Dashboards → shop-api RED
#    the p99 panel spikes. Hover → a green diamond → click → Tempo opens a 2.5s trace.
# 3. in the trace waterfall, the slow span is highlighted.
#    Click "Logs for this span" → Loki, filtered to that trace_id.
# 4. the log line reads: ERROR simulated internal error, n=17
# 5. Click the "Request rate" trace-to-metrics query → back to Prometheus.
# Total: metric → trace → log → metric, in four clicks.
```

### 9.4 The service graph

Tempo's `metricsGenerator` (enabled in §1.1) produces `traces_service_graph_*` metrics from your spans. Grafana draws your **actual runtime architecture** — including services you forgot about.

```promql
# who calls whom, and how often
sum by (client, server) (rate(traces_service_graph_request_total[5m]))
# the p99 of each edge
histogram_quantile(0.99, sum by (client, server, le) (rate(traces_service_graph_request_seconds_bucket[5m])))
# the error rate of each edge
sum by (client, server) (rate(traces_service_graph_request_failed_total[5m]))
  / sum by (client, server) (rate(traces_service_graph_request_total[5m]))
# unconnected spans (a propagation bug!)
traces_service_graph_request_server_seconds_count
```

**In Grafana:** Explore → Tempo → **Service graph** button → your architecture map, with latency and error rate colouring each edge. Clicking a node runs a TraceQL search.

### 9.5 Span metrics — RED from traces, for free

```promql
# Tempo's metricsGenerator also emits per-span metrics
traces_span_metrics_calls_total{service="shop-api"}
traces_span_metrics_duration_milliseconds_bucket{service="shop-api"}
histogram_quantile(0.99, sum by (le, span_name) (rate(traces_span_metrics_duration_milliseconds_bucket{service="shop-api"}[5m])))
traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}
```

> 🔑 **This is genuinely useful:** services that expose *no* `/metrics` endpoint still get RED metrics, derived from their spans. It's a great way to get baseline coverage of a legacy system before you instrument it properly.

---

## 10. Step 10 — Auto-instrumentation with the OTel Operator

Instead of adding `-javaagent` and env vars to every Deployment by hand, the Operator **injects them for you** via an annotation.

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  -n otel --create-namespace \
  --set manager.collectorImage.repository=otel/opentelemetry-collector-contrib \
  --set manager.image.tag=0.90.0 \
  --wait --timeout 5m

kubectl get pods -n otel
kubectl get crds | grep opentelemetry
# instrumentations.opentelemetry.io
# opentelemetrycollectors.opentelemetry.io
# opampbridges.opentelemetry.io
```

### The Instrumentation resource

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: shop-instrumentation
  namespace: shop
spec:
  exporter:
    endpoint: http://otel-collector-agent.otel.svc.cluster.local:4317   # ⭐ the agent
  propagators: [tracecontext, baggage, b3]          # ⭐ include b3 to interoperate
  sampler:
    type: parentbased_traceidratio
    argument: "1.0"                                  # ⭐ head=100%, tail-sampled at the gateway
  env:
    - {name: OTEL_RESOURCE_ATTRIBUTES, value: "deployment.environment=dev"}
    - {name: OTEL_EXPORTER_OTLP_TIMEOUT, value: "10000"}

  # ⭐ per-language injection configuration
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.11.0
    env:
      - {name: OTEL_JAVAAGENT_EXTENSIONS, value: ""}
      - {name: OTEL_INSTRUMENTATION_HIBERNATE_ENABLED, value: "true"}
      - {name: OTEL_INSTRUMENTATION_COMMON_PEER_SERVICE_MAPPING,
         value: "postgresql=db-service,redis=cache-service"}
    resources: {limits: {memory: 256Mi}, requests: {cpu: 50m, memory: 64Mi}}

  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.51b0
    env:
      - {name: OTEL_METRICS_EXPORTER, value: "otlp"}

  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.55.0
    env:
      - {name: OTEL_METRICS_EXPORTER, value: "otlp"}

  dotnet:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-dotnet:1.9.0

  apacheHttpd:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-apache-httpd:1.0.4

  nginx:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nginx:1.0.5
```

### Turn it on with ONE annotation ⭐

```bash
kubectl apply -f instrumentation.yaml

# ⭐⭐ that's it. Annotate the pod template:
kubectl patch deploy shop-api -n shop --type=merge -p '
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-java: "shop/shop-instrumentation"
'
kubectl rollout status deploy/shop-api -n shop

# the other languages
# instrumentation.opentelemetry.io/inject-python: "shop/shop-instrumentation"
# instrumentation.opentelemetry.io/inject-nodejs: "shop/shop-instrumentation"
# instrumentation.opentelemetry.io/inject-dotnet: "shop/shop-instrumentation"
# instrumentation.opentelemetry.io/inject-nginx:  "shop/shop-instrumentation"
# instrumentation.opentelemetry.io/inject-sdk:    "shop/shop-instrumentation"   ← env vars only

# ⭐ what did the Operator actually do?
kubectl get pod -n shop -l app=shop-api -o json | jq '.items[0].spec |
  {initContainers: [.initContainers[]? | {name, image, volumeMounts}],
   volumes: [.volumes[]? | select(.name|test("otel"))],
   env: [.containers[0].env[]? | select(.name|startswith("OTEL"))]}'
# initContainers: [{"name":"opentelemetry-auto-instrumentation-java",
#                   "image":"…autoinstrumentation-java:2.11.0",
#                   "volumeMounts":[{"name":"opentelemetry-auto-instrumentation-java","mountPath":"/otel-auto-instrumentation-java"}]}]
# volumes: [{"name":"opentelemetry-auto-instrumentation-java","emptyDir":{}}]
# env: [{"name":"JAVA_TOOL_OPTIONS","value":" -javaagent:/otel-auto-instrumentation-java/javaagent.jar"},
#       {"name":"OTEL_SERVICE_NAME","value":"shop-api"},
#       {"name":"OTEL_EXPORTER_OTLP_ENDPOINT","value":"http://otel-collector-agent…:4317"},
#       {"name":"OTEL_TRACES_SAMPLER","value":"parentbased_traceidratio"}, …]

# the Operator's own view
kubectl get instrumentation -A
kubectl describe instrumentation shop-instrumentation -n shop
kubectl logs -n otel deploy/opentelemetry-operator-controller-manager --tail=50
```

| Injection annotation | Mechanism |
|---|---|
| `inject-java` | An **init container** copies the agent JAR into a shared `emptyDir`; `JAVA_TOOL_OPTIONS=-javaagent:…` is added |
| `inject-python` | An init container creates a venv; `PYTHONPATH` + `sitecustomize.py` are added |
| `inject-nodejs` | An init container copies the SDK; `NODE_OPTIONS=--require …` is added |
| `inject-dotnet` | An init container; `CORECLR_ENABLE_PROFILING` + the profiler path |
| `inject-nginx` | A sidecar/injected module |
| `inject-sdk` | ⭐ **Env vars only** — for apps that already have the SDK compiled in (Go!) |

> 🔑 **`inject-sdk` is the one to use for Go.** Go has no agent, but the Operator can still inject `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_RESOURCE_ATTRIBUTES` and `OTEL_PROPAGATORS` consistently across every service — which is exactly what you want, since a mismatched `OTEL_PROPAGATORS` is the #1 cause of broken traces.

⚠️ **The Operator can't inject into a Pod with `readOnlyRootFilesystem: true` unless the `emptyDir` is mounted at a writable path**, and it can't inject into `hostNetwork` pods reliably. Test it on one Deployment before rolling it out.

---

## 11. Step 11 — Monitoring the Collector itself

If the Collector drops your telemetry, you have no telemetry to tell you. **Monitor it with Prometheus.**

```promql
# ⭐ THROUGHPUT
sum(rate(otelcol_receiver_accepted_spans[5m]))                     # spans/s in
sum(rate(otelcol_exporter_sent_spans[5m]))                         # spans/s out
sum(rate(otelcol_receiver_accepted_log_records[5m]))
sum(rate(otelcol_exporter_sent_log_records[5m]))
sum(rate(otelcol_receiver_accepted_metric_points[5m]))

# ⭐⭐ DROPS — the numbers that must be zero
sum(rate(otelcol_processor_dropped_spans[5m]))
sum(rate(otelcol_processor_dropped_log_records[5m]))
sum(rate(otelcol_exporter_send_failed_spans[5m]))
sum(rate(otelcol_receiver_refused_spans[5m]))                      # refused by the processor (memory_limiter!)
sum(rate(otelcol_exporter_enqueue_failed_spans[5m]))               # the sending queue is full

# ⭐ the memory limiter firing = you're shedding load
sum(rate(otelcol_processor_refused_spans{processor="memory_limiter"}[5m]))

# the sampling decision breakdown
sum by (policy) (rate(otelcol_processor_tail_sampling_sampling_decision_timer_sum[5m]))
sum(rate(otelcol_processor_tail_sampling_sampling_trace_dropped_too_early[5m]))
sum(rate(otelcol_processor_tail_sampling_sampling_policy_evaluation_error[5m]))
otelcol_processor_tail_sampling_sampling_traces_received

# the batch queue
otelcol_processor_batch_batch_send_size_bytes
otelcol_processor_batch_timeout_trigger_send_total
otelcol_processor_batch_metadata_cardinality        # ⭐ a cardinality leak in the batch processor

# the export queue
otelcol_exporter_queue_size
otelcol_exporter_queue_capacity

# resources
container_memory_working_set_bytes{namespace="otel"}
  / on(pod) group_left kube_pod_container_resource_limits{resource="memory"}
rate(container_cpu_usage_seconds_total{namespace="otel"}[5m])
otelcol_process_uptime
otelcol_process_runtime_total_sys_memory_bytes
go_goroutines{namespace="otel"}
```

**The essential Collector alerts:**

```yaml
- alert: OtelCollectorDroppingSpans
  expr: sum(rate(otelcol_processor_dropped_spans[5m])) > 0
  for: 2m
  labels: {severity: critical, team: platform}
  annotations:
    summary: "the OTel Collector is dropping {{ $value }} spans/s — traces are incomplete"
    runbook_url: https://wiki.example.com/runbooks/otel-drops

- alert: OtelCollectorMemoryLimiterRefusing
  expr: sum(rate(otelcol_processor_refused_spans{processor="memory_limiter"}[5m])) > 0
  for: 2m
  labels: {severity: critical, team: platform}
  annotations:
    summary: "the Collector's memory_limiter is refusing data — raise its memory limit or add replicas"

- alert: OtelCollectorExportFailing
  expr: |
    sum(rate(otelcol_exporter_send_failed_spans[5m]))
      / sum(rate(otelcol_exporter_sent_spans[5m])) > 0.01
  for: 5m
  labels: {severity: critical, team: platform}
  annotations:
    summary: "the Collector can't reach a backend (Tempo/Loki/Prometheus)"

- alert: OtelCollectorQueueFull
  expr: otelcol_exporter_queue_size / otelcol_exporter_queue_capacity > 0.9
  for: 5m
  labels: {severity: warning, team: platform}

- alert: OtelCollectorDown
  expr: up{namespace="otel"} == 0
  for: 2m
  labels: {severity: critical, team: platform}

- alert: TempoIngestFailing
  expr: sum(rate(tempo_discarded_spans_total[5m])) > 0
  for: 5m
  labels: {severity: critical, team: platform}

- alert: LokiIngestFailing
  expr: sum(rate(loki_discarded_samples_total[5m])) > 0
  for: 5m
  labels: {severity: warning, team: platform}
```

```bash
# ⭐ the Collector's own health endpoint (13133)
kubectl exec -n otel deploy/otel-collector-gateway -- wget -qO- http://localhost:13133/
# Collector server is running.

# validate the config against the running instance
kubectl exec -n otel deploy/otel-collector-gateway -- otelcol-contrib validate --config=/etc/otel/config.yaml
# ⛔ on older versions there's no `validate`; use --dry-run at startup

# the component graph (which processors are in which pipeline)
kubectl exec -n otel deploy/otel-collector-gateway -- wget -qO- http://localhost:13133/debug/tracez 2>/dev/null | head
kubectl exec -n otel deploy/otel-collector-gateway -- wget -qO- http://localhost:55679/debug/tracez 2>/dev/null | head
```

---

## 12. Step 12 — Break it on purpose

### 12.1 Break propagation and see the trace split

```bash
# remove the propagator from the Go service
kubectl set env deploy/checkout -n shop OTEL_PROPAGATORS=none
kubectl rollout status deploy/checkout -n shop

# send a request and look at Tempo
TRACE_ID=$(openssl rand -hex 16); PARENT=$(openssl rand -hex 8)
kubectl exec -n shop deploy/checkout -- wget -qO- \
  --header="traceparent: 00-$TRACE_ID-$PARENT-01" --post-data='' http://localhost:8080/checkout

sleep 15
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq '.batches[].scopeSpans[].spans[].name'
# ⛔ only "POST /api/orders" — the checkout spans are in a DIFFERENT trace

# and the checkout's own trace is orphaned:
curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "checkout" && .duration > 100ms }' \
  --data-urlencode 'limit=3' | jq '.traces[].rootTraceName'
# "POST /checkout"     ← it started a NEW trace because it couldn't extract the parent

# fix
kubectl set env deploy/checkout -n shop OTEL_PROPAGATORS=tracecontext,baggage
kubectl rollout restart deploy/checkout -n shop
```

**How to spot a propagation bug in Tempo:** look at `traces_service_graph_request_total` for edges that should exist but don't, or find services whose traces all have `parentSpanId = ""` (they're all roots). Also: **`span_kind=SERVER` spans with no parent are suspicious** — a server span should almost always have a client-span parent.

### 12.2 Overwhelm the Collector and watch it shed load

```bash
# remove the memory_limiter and set a tiny limit
kubectl patch cm otel-gateway-config -n otel --type=merge -p "$(
  yq '.data["config.yaml"] |= (sub("limit_percentage: 80", "limit_percentage: 5"))' \
    | yq '{"data":{"config.yaml": .}}' -o=json)" 2>/dev/null || \
  sed -i 's/limit_percentage: 80/limit_percentage: 5/' collector/gateway-config.yaml
kubectl create cm otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/otel-collector-gateway -n otel

# watch it refuse data
kubectl logs -n otel deploy/otel-collector-gateway -f | grep -iE 'refus|memory|dropp'
# {"level":"warn","msg":"Memory usage is above hard limit. Dropping data.",
#  "component":"processor/memory_limiter","cur_mem_mib":1842}

curl -s localhost:8888/metrics | grep otelcol_processor_refused_spans
# otelcol_processor_refused_spans{processor="memory_limiter",service_instance_id="…",service_name="otel-gateway",service_version="0.158.0"} 48211

# ⭐ THE LESSON: with memory_limiter, the Collector sheds load and STAYS UP.
#    Without it, it OOMKills, restarts, and drops EVERYTHING in the batch queue.
#    memory_limiter is the difference between "some traces missing" and "an outage".

# restore
sed -i 's/limit_percentage: 5/limit_percentage: 80/' collector/gateway-config.yaml
kubectl create cm otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/otel-collector-gateway -n otel
```

### 12.3 Prove tail sampling is working

```bash
# turn tail sampling to 0% for non-error, non-slow traces
sed -i 's/sampling_percentage: 10/sampling_percentage: 0/' collector/gateway-config.yaml
kubectl create cm otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/otel-collector-gateway -n otel && kubectl rollout status deploy/otel-collector-gateway -n otel

# generate a mix: fast OK requests, slow requests, errors
for i in $(seq 1 200); do
  kubectl exec -n shop deploy/checkout -- wget -qO- --post-data='' http://localhost:8080/checkout >/dev/null
done

sleep 20
curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "checkout" }' \
  --data-urlencode 'limit=100' | jq '.traces | length'
# ~30 out of 200 — only the slow ones and the errors survived

curl -sG localhost:3200/api/search --data-urlencode 'q={ status = error }' --data-urlencode 'limit=100' \
  | jq '.traces | length'
# ALL of the errors are there ✅

curl -sG localhost:3200/api/search --data-urlencode 'q={ duration > 1s }' --data-urlencode 'limit=100' \
  | jq '.traces | length'
# ALL of the slow ones are there ✅

# ⭐⭐ THE LESSON: you cut trace volume by 85% and kept 100% of the interesting traces.
#    That's the entire business case for tail sampling.

sed -i 's/sampling_percentage: 0/sampling_percentage: 10/' collector/gateway-config.yaml
kubectl create cm otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/otel-collector-gateway -n otel
```

### 12.4 Send traces to the wrong place and watch the SDK behave

```bash
kubectl set env deploy/shop-api -n shop OTEL_EXPORTER_OTLP_ENDPOINT=http://does-not-exist:4317
kubectl rollout status deploy/shop-api -n shop
kubectl logs -n shop deploy/shop-api --tail=30 | grep -i otel
# [otel.javaagent …] WARN io.opentelemetry.exporter.internal.grpc.OkHttpGrpcExporter -
#   Failed to export spans. The request could not be executed. Full error message: does-not-exist
# ⭐ note: the app KEEPS RUNNING. The SDK buffers, retries, then DROPS. It never crashes your app.
# ⭐ but it DOES log, and the batch queue fills — watch for memory growth in a bad config.

kubectl set env deploy/shop-api -n shop \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-agent.otel.svc.cluster.local:4317
kubectl rollout restart deploy/shop-api -n shop
```

> 🔑 **This is why an OTel outage is never an application outage** — and also why you must monitor the Collector: a silent OTLP failure means you have *no traces at all* while everything looks healthy.

---

## 13. Troubleshooting telemetry

### 13.1 No traces in Tempo

```bash
# work outward from the app
# 1. is the app even instrumented?
kubectl exec -n shop deploy/shop-api -- printenv | grep -i otel
# OTEL_SERVICE_NAME=shop-api
# OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-agent.otel.svc.cluster.local:4317
# ⛔ if OTEL_TRACES_EXPORTER=none or OTEL_SDK_DISABLED=true, nothing is sent
kubectl exec -n shop deploy/shop-api -- printenv | grep -E 'OTEL_SDK_DISABLED|OTEL_TRACES_EXPORTER'

# 2. is the javaagent attached? (Java)
kubectl exec -n shop deploy/shop-api -- printenv JAVA_TOOL_OPTIONS
# -javaagent:/opt/otel/opentelemetry-javaagent.jar
kubectl logs -n shop deploy/shop-api | grep -i 'opentelemetry-javaagent'
# [otel.javaagent …] INFO … VersionLogger - opentelemetry-javaagent - version: 2.11.0
# ⛔ no such line = the agent didn't load

# 3. turn on SDK debug logging temporarily ⭐
kubectl set env deploy/shop-api -n shop OTEL_JAVAAGENT_DEBUG=true OTEL_LOG_LEVEL=debug
kubectl rollout restart deploy/shop-api -n shop
kubectl logs -n shop deploy/shop-api --tail=200 | grep -iE 'otel|export|span' | head -40
# look for: "Failed to export spans", "Connection refused", "span dropped"

# 4. can the app reach the Collector?
kubectl exec -n shop deploy/shop-api -- sh -c 'wget -qO- --timeout=5 http://otel-collector-agent.otel.svc.cluster.local:13133/ || echo UNREACHABLE'
kubectl run t --image=nicolaka/netshoot -n shop --rm -it --restart=Never -- \
  bash -c 'nc -zv otel-collector-agent.otel.svc.cluster.local 4317; dig +short otel-collector-agent.otel.svc.cluster.local'
# ⛔ timeout = a NetworkPolicy is blocking egress

# 5. did the Collector receive anything?
kubectl port-forward -n otel svc/otel-collector-gateway 8888:8888 &
curl -s localhost:8888/metrics | grep -E 'otelcol_receiver_accepted_spans|otelcol_exporter_sent_spans'
# otelcol_receiver_accepted_spans{receiver="otlp",transport="grpc"} 0     ← ⛔ nothing arrived

# 6. did the gateway send to Tempo successfully?
curl -s localhost:8888/metrics | grep -E 'otelcol_exporter_send_failed|otelcol_exporter_queue_size'
kubectl logs -n otel deploy/otel-collector-gateway --tail=100 | grep -iE 'error|fail|refus'

# 7. did Tempo store it?
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo --tail=100 | grep -iE 'error|discard'
kubectl port-forward -n monitoring svc/tempo 3200:3200 &
curl -sG localhost:3200/api/search --data-urlencode 'q={}' --data-urlencode 'limit=5' | jq '.traces'
curl -s localhost:3200/api/search/tags | jq .
# ⛔ if the tags list is empty, Tempo has received nothing at all
curl -s localhost:3200/ready
```

**The ten causes, in order of frequency:**

| # | Cause | The tell |
|---|---|---|
| 1 | `OTEL_SERVICE_NAME` not set | Traces appear as `unknown_service:java` |
| 2 | The endpoint is wrong or unreachable | `Failed to export spans … Connection refused` |
| 3 | The agent/SDK isn't attached | No `opentelemetry-javaagent` line in the logs |
| 4 | `OTEL_TRACES_EXPORTER=none` | Nothing sent, no errors |
| 5 | A **NetworkPolicy** blocks egress to :4317 | `nc -zv` times out |
| 6 | The Collector's `memory_limiter` is refusing | `otelcol_processor_refused_spans` > 0 |
| 7 | Tail sampling dropped it | The policy didn't match; check `decision_wait` |
| 8 | The exporter failed to Tempo | `otelcol_exporter_send_failed_spans` > 0 |
| 9 | Tempo's `searchEnabled` is false | Traces exist by ID but search returns nothing |
| 10 | The Grafana datasource URL is wrong | "Tempo: request failed" in Explore |

### 13.2 Traces exist but are split across services

```bash
# the diagnostic: look for SERVER spans with no parent
curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "shop-api" }' --data-urlencode 'limit=20' \
  | jq -r '.traces[].traceID' | while read t; do
      curl -s "localhost:3200/api/traces/$t" | jq -r --arg t "$t" '
        [.batches[].scopeSpans[].spans[]] as $spans |
        ($spans | map(select(.parentSpanId == null or .parentSpanId == "")) | length) as $roots |
        "\($t)  spans=\($spans|length)  roots=\($roots)"'
    done | sort -t= -k3 -rn | head
# a trace with roots > 1 means the chain BROKE somewhere

# the causes:
# 1. different OTEL_PROPAGATORS on different services ⭐ the #1 cause
for d in $(kubectl get deploy -n shop -o name); do
  printf '%-28s %s\n' "$d" "$(kubectl get $d -n shop -o jsonpath='{.spec.template.spec.containers[0].env}' \
    | jq -r '.[] | select(.name=="OTEL_PROPAGATORS") | .value' 2>/dev/null)"
done
# ⛔ if any is empty or "b3" while the others are "tracecontext", that's it

# 2. a thread pool / async boundary losing the context
#    Java: the agent handles ExecutorService/CompletableFuture/Reactor, but NOT
#          a hand-rolled thread or a raw `new Thread()`. Wrap it:
#          Context.taskWrapping(executor)
#    Go: you must pass ctx explicitly — never context.Background() in a handler chain

# 3. a message queue without header propagation
#    the producer must inject into the message headers; the consumer must extract
#    and start a span with SpanKind.CONSUMER plus a LINK to the producer span

# 4. a load balancer / API gateway stripping the traceparent header
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- \
  nginx -T 2>/dev/null | grep -i 'proxy_set_header\|underscores_in_headers'
# ⭐ nginx passes unknown headers by default, but some configs whitelist them

# 5. a third-party API that doesn't echo the header → the chain legitimately ends there
```

### 13.3 Logs in Loki but no trace_id

```bash
# 1. does the log line actually contain it?
curl -sG 'localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="shop",app="shop-api"}' \
  --data-urlencode "start=$(date -d '-5 min' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" --data-urlencode 'limit=3' \
  | jq -r '.data.result[].values[][1]'
# {"trace_id":"-","span_id":"-"}   ← ⛔ a dash = no active span when the log was written

# causes:
#   a. the logging pattern has %X{trace_id} but nothing put it in the MDC
#      → the OTel agent isn't attached, or you're using a custom ThreadFactory
#   b. the log is written OUTSIDE a span (a scheduled task, a startup message)
#      → expected and fine
#   c. the app uses a JSON encoder that doesn't include MDC keys
#      → logstash-logback-encoder needs <includeMdcKeyName>trace_id</includeMdcKeyName>

# 2. is the Collector's regex matching your format?
kubectl logs -n otel ds/otel-logs-agent --tail=50 | grep -iE 'error|regex|parse'
# test the regex against a real line:
echo '{"trace_id":"4bf9…","span_id":"00f0…"}' | grep -oP '"trace_id"\s*:\s*"(\w+)"'

# 3. is the Grafana derivedFields regex right?
#    Grafana → Connections → Data sources → Loki → Derived fields
#    matcherRegex: '"trace_id"\s*:\s*"(\w+)"'
#    ⚠️ in the YAML ConfigMap you must ESCAPE the backslashes for YAML:
#       matcherRegex: '"trace_id"\\s*:\\s*"(\\w+)"'   inside a |- block it's literal, so no
#    Test it in Explore: click a log line → is there a "View trace" link?
```

### 13.4 The Collector keeps restarting

```bash
kubectl get pods -n otel
kubectl describe pod -n otel -l app=otel-gateway | grep -A6 'Last State'
# Reason: OOMKilled, Exit Code: 137

# ⭐ tail_sampling is almost always the cause — it buffers traces in memory
kubectl logs -n otel deploy/otel-collector-gateway --previous --tail=100 | grep -iE 'memory|limit'

# the fixes:
# 1. GOMEMLIMIT must be ~90% of the container memory limit
kubectl set env deploy/otel-collector-gateway -n otel GOMEMLIMIT=3500MiB
# 2. memory_limiter must be the FIRST processor
# 3. lower num_traces and decision_wait
#    num_traces: 200000 → 50000
#    decision_wait: 10s → 5s
# 4. raise the memory limit
kubectl patch deploy otel-collector-gateway -n otel --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"8Gi"}]'
# 5. add replicas (tail sampling is per-instance, so more replicas = smaller per-instance buffers,
#    but ALSO = a trace may be split across instances unless you use a load-balancing exporter)
```

> 🔑 **The multi-replica tail-sampling problem:** with 2 gateway replicas and round-robin load balancing, the spans of one trace can land on different replicas, and neither sees the whole trace. The fix is the **`loadbalancing` exporter** on the agent tier, which routes by trace ID:

```yaml
exporters:
  loadbalancing:
    protocol:
      otlp: {tls: {insecure: true}, timeout: 10s}
    resolver:
      k8s:
        service: otel-collector-gateway.otel.svc.cluster.local
        namespaces: [otel]
        port: 4317
    # ⭐ consistent hashing on traceID → every span of a trace goes to the SAME gateway
```
Put `loadbalancing` in the **agent** pipeline (exporting to the gateways) and let the **gateway** do tail sampling. That's the reference architecture.

### 13.5 Tempo/Loki are slow or full

```bash
kubectl exec -n monitoring sts/tempo -- df -h /var/tempo 2>/dev/null || \
  kubectl exec -n monitoring deploy/tempo -- df -h /var/tempo
kubectl get pvc -n monitoring
kubectl df-pv -n monitoring

# Tempo
curl -sG 'localhost:3200/api/search' --data-urlencode 'q={}' --data-urlencode 'limit=1' -m 30
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo --tail=100 | grep -iE 'error|too many|limit'
# "max concurrent queries exceeded" → raise maxConcurrentQueries
# "block retention" → the retention job is deleting old blocks (normal)

# Loki
curl -s localhost:3100/ready
curl -sG localhost:3100/loki/api/v1/label/namespace/values -m 10
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=100 | grep -iE 'error|limit|reject'
# "per_stream_rate_limit exceeded"     → raise ingestion_rate_mb / add more streams
# "max_query_series exceeded"         → your label cardinality is too high ⭐
curl -sG localhost:3100/loki/api/v1/index/stats --data-urlencode 'query={namespace=~".+"}' | jq .
# {"streams":4821,"chunks":184203,"bytes":…,"entries":…}
```

---

## 14. Production checklist

```
COLLECTOR
  □ memory_limiter is the FIRST processor in EVERY pipeline
  □ batch is the LAST processor in every pipeline
  □ GOMEMLIMIT ≈ 90% of the container memory limit (Go's GC needs to know)
  □ GOMAXPROCS set, or automaxprocs used
  □ the AGENT (DaemonSet) and GATEWAY (Deployment) are separate tiers
  □ apps export to the AGENT, never to a remote gateway or a SaaS vendor
  □ sending_queue + retry_on_failure on every remote exporter
  □ tail_sampling ONLY on the gateway, with a loadbalancing exporter upstream
  □ decision_wait and num_traces sized from expected_new_traces_per_sec
  □ ≥2 gateway replicas + a PDB + topology spread
  □ a checksum/config annotation so config changes roll the pods
  □ the Collector's own metrics scraped by Prometheus (ServiceMonitor)
  □ alerts on dropped_spans, refused_spans, send_failed_spans, queue_size
  □ PII redaction in the attributes processor
  □ debug exporter verbosity=basic (NEVER detailed in prod)

INSTRUMENTATION
  □ OTEL_SERVICE_NAME set explicitly on every service
  □ OTEL_PROPAGATORS identical across every language (tracecontext,baggage)
  □ OTEL_RESOURCE_ATTRIBUTES includes deployment.environment and service.version
  □ head sampling = 100% (parentbased_traceidratio 1.0); the gateway tail-samples
  □ span.end() / defer span.End() in a finally block, always
  □ span.SetStatus(Error) + RecordException on every failure path
  □ business attributes (order.id, customer.tier) on the domain spans
  □ span NAMES are low-cardinality (route templates, not IDs)
  □ the SDK is flushed on shutdown (Java agent does it; Go needs provider.Shutdown)
  □ the metrics endpoint is NOT instrumented (it would trace its own scrapes)

LOGS
  □ every service emits structured JSON to stdout with trace_id and span_id
  □ the OTel Collector filelog receiver (or a Loki shipper) reads /var/log/pods
  □ namespace, pod, container, level are LABELS; trace_id/order_id are FIELDS
  □ no unbounded label (never trace_id, request_id, user_id, raw path)
  □ retention_period set AND compactor.retention_enabled: true
  □ the app's log level is INFO in production, DEBUG on demand

GRAFANA CORRELATION ⭐⭐
  □ the Prometheus datasource has exemplarTraceIdDestinations → Tempo
  □ the Tempo datasource has tracesToLogs → Loki (filterByTraceID: true)
  □ the Tempo datasource has tracesToMetrics → Prometheus
  □ the Loki datasource has derivedFields → Tempo, with a matcher for YOUR format
  □ the Tempo metricsGenerator is on (service graph + span metrics)
  □ the datasource UIDs are stable ("prometheus", "tempo", "loki")
  □ dashboards are provisioned as code, not click-built

SAMPLING
  □ you know the volume: spans/s in, spans/s kept, bytes/day
  □ errors are kept at 100%
  □ slow traces (> your p99 SLO) are kept at 100%
  □ the money path (checkout, payment, login) is kept at 100%
  □ health checks and /metrics are dropped
  □ the canary version is kept at 100%
  □ you have measured the cost saving and the completeness loss

SECURITY
  □ the OTLP endpoints are not exposed to the public internet without auth
  □ CORS on the OTLP/HTTP receiver allows ONLY your origins
  □ db.query.text is hashed or redacted (it contains user data)
  □ authorization/cookie headers are deleted
  □ the Collector's ServiceAccount has read-only RBAC for k8sattributes
  □ trace retention is short (72h) — traces contain more PII than logs
```

---

<a name="tasks--answers"></a>
## 🎯 Tasks & Answers

---

### Task 2.1 — Trace a request across THREE services and a message queue

You have `shop-ui` (browser) → `checkout` (Go) → `shop-api` (Java). Now add an **asynchronous** hop: after `shop-api` creates an order, it publishes `order.created` to RabbitMQ, and `order-worker` (Python) consumes it and emails the customer.

**Make the trace span all five hops**, with the async hop visible in the waterfall, and prove it works.

<details>
<summary><b>💡 Hints</b></summary>

1. A queue has no HTTP headers — the context travels in the **message properties/headers**.
2. The producer creates a `PRODUCER` span; the consumer creates a `CONSUMER` span that is **not** a child of it (the parent request may have finished long ago). They're connected with a **span link**.
3. The Java agent instruments RabbitMQ automatically. In Python you need `opentelemetry-instrumentation-pika` (or manual propagation).
</details>

**✅ Answer**

**Producer (Java, `shop-api`)** — the agent handles most of this, but the span kind matters:

```java
package com.shop.service;

import com.rabbitmq.client.*;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapSetter;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;

@Service
public class OrderEventPublisher {

    private static final Tracer tracer = GlobalOpenTelemetry.getTracer("com.shop.events");
    private final Channel channel;

    // ⭐ how OTel writes the context INTO a carrier
    private static final TextMapSetter<Map<String, String>> MAP_SETTER =
            (carrier, key, value) -> { if (carrier != null) carrier.put(key, value); };

    public OrderEventPublisher(Channel channel) { this.channel = channel; }

    public void publishOrderCreated(String orderId, long amountCents) throws Exception {
        // ⭐ a PRODUCER span — the OTel Java agent creates one automatically for
        //   channel.basicPublish, but doing it manually shows the mechanism
        Span span = tracer.spanBuilder("order.created publish")
                .setSpanKind(SpanKind.PRODUCER)
                .setAttribute("messaging.system", "rabbitmq")
                .setAttribute("messaging.destination.name", "order.created")
                .setAttribute("messaging.operation.name", "publish")
                .setAttribute("messaging.rabbitmq.destination.routing_key", "orders")
                .setAttribute("order.id", orderId)
                .setAttribute("order.amount_cents", amountCents)
                .startSpan();

        try (var scope = span.makeCurrent()) {
            Map<String, String> headers = new HashMap<>();

            // ⭐⭐ INJECT the trace context into the message headers
            GlobalOpenTelemetry.getPropagators().getTextMapPropagator()
                    .inject(Context.current(), headers, MAP_SETTER);
            // headers now contains: {traceparent=00-4bf9…-00f0…-01, tracestate=…}

            AMQP.BasicProperties props = new AMQP.BasicProperties.Builder()
                    .contentType("application/json")
                    .deliveryMode(2)                       // persistent
                    .messageId(orderId)
                    .headers(new HashMap<>(headers))       // ⭐ as AMQP headers
                    .timestamp(new java.util.Date())
                    .build();

            String body = """
                {"order_id":"%s","amount_cents":%d,"event":"order.created"}
                """.formatted(orderId, amountCents);

            channel.basicPublish("shop.events", "orders", props, body.getBytes());
            span.addEvent("message.published", io.opentelemetry.api.common.Attributes.of(
                    io.opentelemetry.api.common.AttributeKey.longKey("messaging.message.body.size"),
                    (long) body.length()));
        } catch (Exception e) {
            span.setStatus(io.opentelemetry.api.trace.StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }
}
```

**Consumer (Python, `order-worker`)** — extract, create a CONSUMER span, **link** it:

```python
import json, pika
from opentelemetry import trace, context, propagate
from opentelemetry.trace import SpanKind, Status, StatusCode, Link
from opentelemetry.propagate import extract

tracer = trace.get_tracer("shop.order-worker", "1.0.0")

# ⭐ how OTel reads the context OUT OF a carrier
def _getter(carrier, key):
    v = carrier.get(key)
    if isinstance(v, bytes):
        return [v.decode()]
    return [v] if v else []


def on_message(ch, method, properties, body):
    headers = dict(properties.headers or {})

    # ⭐⭐ EXTRACT the parent context from the message headers
    ctx = extract(headers, getter=_getter)
    parent_span_ctx = trace.get_current_span(ctx).get_span_context()

    # ⭐⭐ a CONSUMER span, LINKED (not parented) to the producer span.
    #    A link says "this work was caused by that span" without making it a child —
    #    which is correct, because the consumer may run hours later.
    links = []
    if parent_span_ctx and parent_span_ctx.is_valid:
        links.append(Link(parent_span_ctx, {"link.type": "messaging.producer"}))

    with tracer.start_as_current_span(
        f"{method.routing_key}.process",
        kind=SpanKind.CONSUMER,
        context=ctx,                      # ⭐ still honour the extracted context
        links=links,
        attributes={
            "messaging.system": "rabbitmq",
            "messaging.destination.name": method.routing_key,
            "messaging.operation.name": "process",
            "messaging.message.id": properties.message_id or "",
            "messaging.rabbitmq.delivery_tag": method.delivery_tag,
        },
    ) as span:
        try:
            event = json.loads(body)
            order_id = event.get("order_id", "unknown")
            span.set_attribute("order.id", order_id)          # ⭐ searchable
            span.set_attribute("order.amount_cents", event.get("amount_cents", 0))

            send_receipt_email(order_id, event)

            span.add_event("email.sent", {"email.provider": "ses"})
            log.info("order email sent", extra={"order_id": order_id})
            ch.basic_ack(delivery_tag=method.delivery_tag)

        except Exception as exc:                              # noqa: BLE001
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            span.record_exception(exc)
            log.exception("failed to process order event")
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)


def send_receipt_email(order_id: str, event: dict) -> None:
    """⭐ a nested CLIENT span — the email provider call."""
    with tracer.start_as_current_span(
        "POST /v1/email",
        kind=SpanKind.CLIENT,
        attributes={
            "server.address": "email.internal",
            "server.port": 443,
            "order.id": order_id,
        },
    ) as span:
        # … the actual call …
        span.set_attribute("http.response.status_code", 202)


def main():
    conn = pika.BlockingConnection(pika.URLParameters(os.environ["RABBITMQ_URL"]))
    ch = conn.channel()
    ch.queue_declare(queue="order_emails", durable=True)
    ch.queue_bind(queue="order_emails", exchange="shop.events", routing_key="orders")
    ch.basic_qos(prefetch_count=10)
    ch.basic_consume(queue="order_emails", on_message_callback=on_message)
    ch.start_consuming()
```

**Prove it:**

```bash
# publish a message with a known trace id, then consume it
TRACE_ID=$(openssl rand -hex 16); PARENT=$(openssl rand -hex 8)
kubectl exec -n shop deploy/shop-api -- sh -c "
  wget -qO- --header='traceparent: 00-$TRACE_ID-$PARENT-01' \
    --post-data='{\"items\":2,\"tier\":\"gold\"}' \
    --header='Content-Type: application/json' \
    http://localhost:8080/api/orders"
# {"orderId":"ord_9f2a…","status":"created",…}

sleep 30
# ⭐ the trace should now contain BOTH the sync chain and the async consumer
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq -r '
  [.batches[] | (.resource.attributes[] | select(.key=="service.name") | .value.stringValue) as $svc
   | .scopeSpans[].spans[] | "\($svc)\t\(.name)\t\(.kind)"] | sort | .[]'
# checkout      POST /checkout                        SPAN_KIND_SERVER
# shop-api      POST /api/orders                      SPAN_KIND_SERVER
# shop-api      order.created publish                 SPAN_KIND_PRODUCER
# shop-api      SELECT shop.inventory                 SPAN_KIND_CLIENT
# order-worker  orders.process                        SPAN_KIND_CONSUMER     ← ⭐ THE ASYNC HOP
# order-worker  POST /v1/email                        SPAN_KIND_CLIENT

# and the link:
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq '
  .batches[].scopeSpans[].spans[] | select(.name=="orders.process") |
  {name, kind, links, parentSpanId}'
# {"name":"orders.process","kind":"SPAN_KIND_CONSUMER",
#  "links":[{"traceId":"4bf9…","spanId":"00f0…","attributes":[{"key":"link.type",…}]}],
#  "parentSpanId":""}          ← ⭐ no parent, but LINKED. Exactly right for async.
```

**Why a link and not a parent?**

| | Parent-child | Link |
|---|---|---|
| Meaning | "This happened **inside** that" | "This was **caused by** that" |
| Timing | Overlapping | Arbitrary — could be hours later |
| Waterfall | Nested, indented | Shown as a clickable reference |
| Use for | Synchronous calls | ⭐ **Queues, batch jobs, fan-out** |

If you made the consumer span a *child* of the producer, a message consumed three hours later would appear as a 3-hour-long span, destroying the trace's readability. **Links are the correct semantic for async.**

---

### Task 2.2 — Cut trace storage by 90% while keeping every error

You're storing 40 GB of traces per day at 100% head sampling. The bill is unacceptable, but you refuse to lose a single error or slow trace. Design the sampling configuration and **measure** the result.

**✅ Answer**

**The design: head-sample 100%, tail-sample at the gateway.**

```yaml
# apps: OTEL_TRACES_SAMPLER=parentbased_traceidratio, OTEL_TRACES_SAMPLER_ARG=1.0
# ⭐ keep everything at the source so the gateway can make an INFORMED decision

processors:
  tail_sampling:
    decision_wait: 15s              # long enough for the slowest async hop
    num_traces: 300000
    expected_new_traces_per_sec: 3000
    decision_cache:
      sampled_cache_size: 200000
      non_sampled_cache_size: 200000
    policies:
      # ── keep 100% of anything interesting ────────────────────────
      - {name: errors, type: status_code, status_code: {status_codes: [ERROR]}}
      - name: http-5xx
        type: numeric_attribute
        numeric_attribute: {key: http.response.status_code, min_value: 500}
      - name: http-4xx-non404                 # 404s are usually bots; 401/403/429 are not
        type: numeric_attribute
        numeric_attribute: {key: http.response.status_code, min_value: 400, max_value: 499}
      - {name: slow-traces, type: latency, latency: {threshold_ms: 800}}   # ⭐ > your p95 SLO
      - name: money-path
        type: string_attribute
        string_attribute:
          key: url.path
          values: [/api/orders, /api/checkout, /api/payment, /api/login]
      - name: canary
        type: string_attribute
        string_attribute: {key: service.version, values: ["1.3.0-rc1"]}
      - name: specific-customer-debugging      # a temporary, targeted 100%
        type: string_attribute
        string_attribute: {key: customer.id, values: ["cus_debug_8821"]}

      # ── drop the noise explicitly ────────────────────────────────
      - name: drop-health-checks
        type: and
        and:
          and_sub_policy:
            - name: is-health
              type: string_attribute
              string_attribute:
                key: url.path
                values: [/actuator/health, /healthz, /health, /readyz, /livez, /metrics, /favicon.ico]
            - name: is-ok
              type: numeric_attribute
              numeric_attribute: {key: http.response.status_code, max_value: 399}

      # ── and sample the rest ──────────────────────────────────────
      - {name: base-sample, type: probabilistic, probabilistic: {sampling_percentage: 8}}
```

**Measure it:**

```bash
# BEFORE
curl -s localhost:8888/metrics | grep '^otelcol_receiver_accepted_spans'
# otelcol_receiver_accepted_spans{…} 8.42e6        (over the collector's uptime)
kubectl exec -n monitoring deploy/tempo -- du -sh /var/tempo/blocks
# 41G

# apply the policy, wait 24h, then:
curl -s localhost:8888/metrics | grep -E '^otelcol_(receiver_accepted|exporter_sent|processor_dropped)_spans'
# otelcol_receiver_accepted_spans{…}   8420311
# otelcol_exporter_sent_spans{…}        742118       ← ⭐ 8.8% of what came in
# otelcol_processor_dropped_spans{processor="tail_sampling"} 7678193

# did we keep every error?
curl -sG localhost:3200/api/search --data-urlencode 'q={ status = error }' \
  --data-urlencode "start=$(date -d '-24 hours' +%s)" --data-urlencode 'limit=1000' | jq '.traces | length'
# 4821
# cross-check against the metric:
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=sum(increase(traces_service_graph_request_failed_total[24h]))' | jq -r '.data.result[0].value[1]'
# 4830   ← ✅ within noise; the tiny gap is traces whose failure was at the edge

# did we keep every slow trace?
curl -sG localhost:3200/api/search --data-urlencode 'q={ duration > 800ms }' \
  --data-urlencode 'limit=1000' | jq '.traces | length'
# 2148
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=sum(increase(traces_span_metrics_duration_milliseconds_count{le!~".+"}[24h]))' | jq .

# the storage result
kubectl exec -n monitoring deploy/tempo -- du -sh /var/tempo/blocks
# 4.2G          ← ⭐ 90% reduction

# and the memory cost of tail sampling
kubectl top pod -n otel -l app=otel-gateway
# otel-collector-gateway-…   820m   3120Mi      ← ⭐ the buffer costs ~3 GB
```

**The trade-offs you must state out loud:**

| Cost | Detail |
|---|---|
| **Memory** | `num_traces × decision_wait × avg spans × ~500 bytes`. 300k traces × 15s ≈ 3 GB. Give the gateway real RAM. |
| **Latency** | A trace isn't queryable until `decision_wait` expires — ~15s after the last span. |
| **Gateway availability** | If the gateway restarts, the buffered traces in memory are **lost**. Run ≥2 replicas with a `loadbalancing` exporter upstream so a restart loses only one replica's buffer. |
| **Completeness of aggregates** | If you compute a metric from traces (span metrics), it's now based on the **sampled** subset. Use Prometheus-scraped metrics for counts, not trace-derived ones. |
| **Debugging a specific user** | Their traces may be sampled out. Mitigate with a temporary `customer.id` policy (in the config above). |

> 🔑 **The interview answer:** *"Head sampling at 100% into a gateway that tail-samples. Keep 100% of errors, 5xx, traces slower than our p95 SLO, and the money path; drop health checks; sample the remainder at 8%. That cut storage 90% with zero loss of actionable traces. The cost is gateway memory proportional to `num_traces × decision_wait`, a ~15s delay before a trace is queryable, and the requirement that trace-derived aggregates not be used for exact counts."*

---

### Task 2.3 — Find the root cause using ONLY the trace view

**Scenario given to you:** *"Checkout p99 went from 200ms to 3.1s at 17:04. The error rate is still 0%. Go find out why. You may not use `kubectl` or the logs — Tempo and Grafana only."*

**✅ Answer — the exact click path and reasoning**

```
STEP 1 — Grafana → Dashboards → shop-api RED → the p99 panel.
         Confirm: p50 is 22ms (fine), p95 is 240ms (fine), p99 is 3.1s.
         ⭐ A p99-only spike with a normal p50 means a TAIL problem:
            a subset of requests is slow, not all of them.
         That rules out "the whole service is overloaded".

STEP 2 — Hover the p99 spike → click the exemplar diamond → Tempo.
         (If exemplars aren't wired, go to Explore → Tempo → Search:
           { .service.name = "shop-api" && .url.path = "/api/orders" && duration > 2s })

STEP 3 — Open 4–5 slow traces. Compare their waterfalls to a fast one.
         FAST (180ms):
           POST /api/orders                       180ms
             ├─ auth verify-token                   8ms
             ├─ SELECT inventory                   22ms
             ├─ redis GET cart                      1ms
             └─ POST /v1/charge                   140ms
         SLOW (3.1s):
           POST /api/orders                      3104ms
             ├─ auth verify-token                   9ms
             ├─ SELECT inventory                   24ms
             ├─ redis GET cart                      1ms
             ├─ POST /v1/charge                   3050ms   ← ⭐ 98% of the time
             │    attributes:
             │      http.response.status_code = 200        ← ⭐ it SUCCEEDED
             │      peer.service = payment-provider
             │      http.resend_count = 2                  ← ⭐⭐ RETRIED TWICE
             │    events:
             │      {name: "retry", time: +1010ms, attributes: {attempt: 1, reason: "timeout"}}
             │      {name: "retry", time: +2020ms, attributes: {attempt: 2, reason: "timeout"}}

STEP 4 — The diagnosis, from the span alone:
         · The payment provider call succeeded (200) — so it's not an error path.
         · It was RETRIED twice, each after a ~1s timeout.
         · 3 × ~1s = 3.05s. That's the entire latency.
         ⭐ ROOT CAUSE: the HTTP client's read timeout is ~1s, and the payment
            provider's p99 has drifted above it. Requests that hit the slow tail
            time out, retry, and eventually succeed — so latency triples with
            ZERO errors.

STEP 5 — Confirm it's not us, using the client-vs-server span comparison.
         In the same trace, look for the provider's own span (if it reports back):
           our CLIENT span   POST /v1/charge   3050ms
           their SERVER span POST /v1/charge      8ms   ← they're fast
         ⭐ If their server span is fast, the time is in OUR retries + network.
            If their server span is also 3s, it's THEM.

STEP 6 — Why only p99? Check the distribution via span metrics:
         histogram_quantile(0.5,  sum by (le) (rate(traces_span_metrics_duration_milliseconds_bucket{span_name="POST /v1/charge"}[10m])))  → 95ms
         histogram_quantile(0.99, …)                                                                              → 3040ms
         ⭐ a BIMODAL distribution: most calls are 95ms, a tail is 3.04s.
            That's the signature of a timeout-and-retry pattern, not of gradual degradation.

STEP 7 — What changed at 17:04? Service graph → the checkout→shop-api edge is fine.
         Tempo Search → { .service.name="shop-api" && .http.resend_count > 0 } | count_over_time()
         The retry count jumps from ~0 to ~40/min exactly at 17:04.
         Either the provider got slower, or OUR timeout got shorter.
         traces_to_metrics → the "p99 latency" query, split by service.version:
         ⭐ service.version="1.3.0" appears at 17:02. We deployed.
```

**Conclusion:** release 1.3.0 at 17:02 lowered the payment client's read timeout from 5s to 1s. The provider's normal p99 is ~1.2s, so a fraction of calls now time out and retry twice — tripling latency while still returning 200. **Fix: revert, or raise the timeout to 3s with 1 retry and a circuit breaker.**

**The technique this task teaches:**

| Observation | Inference |
|---|---|
| p99 up, p50 flat | A tail problem, not global overload |
| A slow span with `status_code=200` | Slow, not failing — look at retries, not errors |
| `http.resend_count > 0` / `retry` events | ⭐ Timeout + retry: latency = N × timeout |
| Client span ≫ server span | The time is in the network or in our retries |
| A bimodal span duration histogram | Two distinct code paths (fast path + retry path) |
| A new `service.version` attribute | We deployed |

---

### Task 2.4 — Instrument a service you don't own, without touching its code

A third-party internal service `legacy-billing` (a Java WAR on Tomcat, no OTel, no source access, deployed as a Deployment in namespace `billing`) must appear in your traces. **Add it to the trace without rebuilding its image.**

**✅ Answer — three options, in order of preference**

**Option A ⭐ — the OTel Operator with a custom init-container image.**

You can't change the image, but you **can** change the Deployment spec:

```bash
kubectl -n billing patch deploy legacy-billing --type=json -p='[
  {"op":"add","path":"/spec/template/metadata/annotations",
   "value":{"instrumentation.opentelemetry.io/inject-java":"otel/shop-instrumentation"}}
]'
```

The Operator adds an init container that copies the agent JAR into an `emptyDir`, and sets `JAVA_TOOL_OPTIONS=-javaagent:/otel-auto-instrumentation-java/javaagent.jar`. **The app image is untouched.**

```bash
kubectl rollout status deploy/legacy-billing -n billing
kubectl get pod -n billing -l app=legacy-billing -o json | jq '.items[0].spec |
  {initContainers: [.initContainers[].image], env: [.containers[0].env[] | select(.name|startswith(("OTEL","JAVA")))]}'
# initContainers: ["ghcr.io/open-telemetry/…/autoinstrumentation-java:2.11.0"]
# env: [{"name":"JAVA_TOOL_OPTIONS","value":" -javaagent:/otel-auto-instrumentation-java/javaagent.jar"},
#       {"name":"OTEL_SERVICE_NAME","value":"legacy-billing"}, …]
```

⚠️ **Gotchas:** the pod must not have `readOnlyRootFilesystem: true` without a writable `emptyDir`; it must have ≥200 MB extra memory for the agent; and if it sets `JAVA_TOOL_OPTIONS` itself, the Operator's value is **appended** — check the effective value with `kubectl exec … -- printenv JAVA_TOOL_OPTIONS`.

**Option B — eBPF, zero changes to anything (Grafana Beyla / Odigos / Coroot).**

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install beyla grafana/beyla -n otel --create-namespace \
  --set beyla.config.discovery.instrument=redis,sqs,sql,http \
  --set beyla.config.attributes.select.include='["k8s","service","tracing"]' \
  --set beyla.config.export.otlp_traces.endpoint='http://otel-collector-agent.otel.svc:4317'
```

Beyla attaches eBPF probes to the process and synthesises HTTP/SQL/Redis spans **from the kernel**, with no code and no JVM agent. Trade-offs: it sees network-level spans only (no domain attributes, no in-process child spans), needs `privileged` or specific capabilities, and requires kernel ≥ 5.8. **Excellent for coverage of systems you can't touch; not a substitute for real instrumentation.**

**Option C — a proxy sidecar that terminates and re-originates the trace.**

Put Envoy/nginx in front of `legacy-billing`. Envoy generates a SERVER span for the inbound request (extracting `traceparent`), and a CLIENT span for the call to the legacy app (injecting `traceparent`, which the app ignores). The result: **the legacy service appears as a single opaque span** in your trace, with correct timing, but no internals.

```yaml
# Istio does this automatically — annotate the namespace:
kubectl label ns billing istio-injection=enabled
# or add an Envoy sidecar manually with the tracing provider configured:
```
```yaml
tracing:
  provider: opentelemetry
  default_config:
    custom_tags: {service.name: {literal: {value: legacy-billing}}}
```

**Recommendation:** **Option A** if you can patch the Deployment (you get full JVM instrumentation, including JDBC and HTTP client spans). **Option B** if you can't touch the workload at all and just need it to *appear*. **Option C** if you already run a service mesh.

```bash
# verify whichever you chose
TRACE_ID=$(openssl rand -hex 16); PARENT=$(openssl rand -hex 8)
kubectl exec -n shop deploy/checkout -- wget -qO- \
  --header="traceparent: 00-$TRACE_ID-$PARENT-01" \
  http://legacy-billing.billing.svc.cluster.local/api/invoices/1
sleep 20
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq -r '
  [.batches[] | (.resource.attributes[] | select(.key=="service.name") | .value.stringValue)] | unique | .[]'
# checkout
# legacy-billing        ← ⭐ it's in the trace
# shop-api
```

---

### Task 2.5 — Build the "one-click incident" dashboard

Create a single Grafana dashboard where an on-call engineer can go from *"something is wrong"* to *"here is the trace and the log line"* without typing a query or switching tabs. It must contain at least: a service-map, a RED row per service, a latency heatmap with exemplars, a live error-log stream, a firing-alerts list, and working links between all of them.

**✅ Answer — the layout and every query**

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  🔥 SHOP — INCIDENT VIEW          [namespace: shop ▾] [service: all ▾] [15m ▾]│
├──────────────────────────────────────────────────────────────────────────────┤
│ ROW 0 — IS IT BROKEN?                                                        │
│  ┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐│
│  │ Availability │ Latency SLO  │ Error budget │ Burn rate    │ ALERTS FIRING││
│  │  99.942%     │  99.21%      │  58% left    │  1.2×  🟢    │   2 🔴       ││
│  └──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘│
├──────────────────────────────────────────────────────────────────────────────┤
│ ROW 1 — WHERE? (the service graph, live from traces)                         │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Node graph panel, datasource = Tempo, query = (service graph)         │  │
│  │  shop-ui ──► shop-api ──► postgres                                    │  │
│  │                 │        └► redis                                     │  │
│  │                 └──► payment  (edge coloured RED: p99 3.05s)          │  │
│  │                 └──RabbitMQ──► order-worker ──► email                 │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────────────────┤
│ ROW 2 — RED, per service (repeat for $service)                               │
│  ┌───────────────────┬───────────────────┬─────────────────────────────────┐ │
│  │ RATE              │ ERRORS            │ DURATION (with EXEMPLARS ⭐)     │ │
│  │ time series       │ time series       │ time series, 3 queries:         │ │
│  │                   │                   │  p50 / p95 / p99                │ │
│  │                   │                   │ + a heatmap below it            │ │
│  └───────────────────┴───────────────────┴─────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────────────────────┤
│ ROW 3 — SATURATION (the leading indicators)                                  │
│  ┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐│
│  │ CPU throttle │ Mem vs limit │ Tomcat busy  │ Hikari pend  │ Queue depth  ││
│  └──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘│
├──────────────────────────────────────────────────────────────────────────────┤
│ ROW 4 — THE EVIDENCE (split view)                                            │
│  ┌──────────────────────────────────────┬───────────────────────────────────┐│
│  │ ERROR LOGS (live)                    │ SLOWEST TRACES (last 15m)         ││
│  │ Logs panel, Loki:                    │ Table, Tempo:                     ││
│  │ {namespace="$namespace"} |= "ERROR"  │ { .service.name=~"$service"       ││
│  │ ⭐ trace_id is clickable             │   && duration > 1s }              ││
│  └──────────────────────────────────────┴───────────────────────────────────┘│
├──────────────────────────────────────────────────────────────────────────────┤
│ ROW 5 — ESCAPE HATCHES                                                       │
│  [Runbook: errors] [Runbook: latency] [Kubernetes] [Argo CD] [Deploys ▸]     │
└──────────────────────────────────────────────────────────────────────────────┘
```

**The queries:**

```promql
# ROW 0
# availability (30d)
1 - (sum(increase(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[30d]))
   / sum(increase(http_server_requests_seconds_count{namespace="$namespace"}[30d])))

# latency SLO attainment
sum(rate(http_server_requests_seconds_bucket{namespace="$namespace",le="0.3"}[$__rate_interval]))
 / sum(rate(http_server_requests_seconds_count{namespace="$namespace"}[$__rate_interval]))

# error budget remaining %
100 * (1 - (sum(increase(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[30d]))
   / (0.001 * sum(increase(http_server_requests_seconds_count{namespace="$namespace"}[30d])))))

# burn rate now
sum(rate(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[$__rate_interval]))
 / (0.001 * sum(rate(http_server_requests_seconds_count{namespace="$namespace"}[$__rate_interval])))
```

```promql
# ROW 2 — RATE
sum by (application) (rate(http_server_requests_seconds_count{namespace="$namespace",application=~"$service"}[$__rate_interval]))

# ROW 2 — ERRORS (ratio)
sum by (application) (rate(http_server_requests_seconds_count{namespace="$namespace",application=~"$service",status=~"5.."}[$__rate_interval]))
 / sum by (application) (rate(http_server_requests_seconds_count{namespace="$namespace",application=~"$service"}[$__rate_interval]))

# ROW 2 — DURATION (three queries in ONE panel, so exemplars appear on all of them)
histogram_quantile(0.50, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="$namespace",application=~"$service"}[$__rate_interval])))
histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="$namespace",application=~"$service"}[$__rate_interval])))
histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="$namespace",application=~"$service"}[$__rate_interval])))
# ⭐ Panel options → Exemplars → enable. The green diamonds appear automatically.

# ROW 2 — HEATMAP (the shape of the distribution)
sum by (le) (increase(http_server_requests_seconds_bucket{namespace="$namespace",application=~"$service"}[$__rate_interval]))
# Panel type: Heatmap. Query options → Format: Heatmap.
# ⭐ enable "Exemplars" on a heatmap too — you can click a cell and get a trace from THAT bucket
```

```promql
# ROW 3 — SATURATION
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="$namespace"}[$__rate_interval]))
 / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="$namespace"}[$__rate_interval]))

sum by (pod, container) (container_memory_working_set_bytes{namespace="$namespace"})
 / on(namespace,pod,container) group_left
kube_pod_container_resource_limits{namespace="$namespace",resource="memory"}

tomcat_threads_busy_threads{namespace="$namespace"} / tomcat_threads_config_max_threads{namespace="$namespace"}
hikaricp_connections_pending{namespace="$namespace"}
worker_queue_depth{namespace="$namespace"}
```

```logql
# ROW 4 — LIVE ERROR LOGS
{namespace="$namespace"} | json | level =~ "(?i)error|fatal|exception"
# Panel type: Logs. Options → "Show time", "Wrap lines", "Deduplicate".
# ⭐ the derived fields on the Loki datasource make trace_id a clickable link automatically.

# ROW 4 — error count by app, for a bar chart
sum by (app) (count_over_time({namespace="$namespace"} | json | level="ERROR" [$__range]))
```

```traceql
# ROW 4 — SLOWEST TRACES
{ .service.name =~ "$service" && duration > 1s } | select(status, .url.path, .order.id)
# Panel type: Table, datasource Tempo, query type "Search".
# ⭐ clicking any row opens the trace waterfall.

# and the errors
{ .service.name =~ "$service" && status = error }
```

**The variables:**

```
namespace : Query  label_values(kube_pod_info, namespace)                              refresh=onTimeRange
service   : Query  label_values(http_server_requests_seconds_count{namespace="$namespace"}, application)
                   Multi-value ✅  Include All ✅  All value = .*
```

**The links (the part that makes it one-click):**

| Panel | Link | Target |
|---|---|---|
| Service graph node | Data link → `Explore` | Tempo, `q={ .service.name = "${__data.fields.id}" }` |
| p99 exemplar | Built-in | Tempo trace view (via `exemplarTraceIdDestinations`) |
| Error log line | Built-in derived field | Tempo trace view (via `derivedFields`) |
| Slow-trace table row | Built-in | Tempo trace view |
| Any trace span | Built-in `tracesToLogs` | Loki, filtered to that trace_id |
| Any trace span | Built-in `tracesToMetrics` | Prometheus, filtered by service and time |
| "Runbook" text panel | HTML links | Your wiki |
| "Kubernetes" link | `https://grafana/d/k8s-views-pods?var-namespace=$namespace` | The k8s dashboard |

**Deploy it as code:**

```bash
# build it in the UI once, then export and commit
curl -s -H "Authorization: Bearer $TOKEN" localhost:3000/api/dashboards/uid/shop-incident \
  | jq '.dashboard | del(.id,.version,.iteration)' > dashboards/shop-incident.json

# scrub and provision
jq 'del(.id,.uid,.version,.iteration) | .panels[].id = null' \
  dashboards/shop-incident.json > dashboards/shop-incident.clean.json

kubectl create configmap grafana-dashboard-shop-incident -n monitoring \
  --from-file=shop-incident.json=dashboards/shop-incident.clean.json \
  --dry-run=client -o yaml \
  | yq '.metadata.labels."grafana_dashboard" = "1" | .metadata.annotations."grafana_folder" = "Shop"' \
  | kubectl apply -f -

kubectl logs -n monitoring deploy/kps-grafana -c grafana-sc-dashboard --tail=5
```

**The test that proves it works:**

```bash
# 1. cause an incident
kubectl set env deploy/shop-api -n shop PAYMENT_TIMEOUT_MS=100
kubectl rollout status deploy/shop-api -n shop
kubectl exec -n shop deploy/loadgen -- sh -c 'for i in $(seq 1 500); do
  curl -s -o /dev/null -XPOST http://shop-api/api/orders -H "Content-Type: application/json" -d "{\"items\":3}"; done'

# 2. open ONLY the incident dashboard. Without typing anything, you should be able to:
#    □ see the burn rate turn red
#    □ see the p99 line climb and the heatmap grow a second mode
#    □ see the payment edge in the service graph turn red
#    □ click an exemplar and land on a trace showing the retries
#    □ click "Logs for this span" and see the payment-client warning
#    □ click the runbook link
#    If any of those needs a tab switch or a typed query, the dashboard isn't finished.

# 3. revert
kubectl set env deploy/shop-api -n shop PAYMENT_TIMEOUT_MS-
kubectl rollout restart deploy/shop-api -n shop
```

---

## ✅ Completion checklist

```
CASE 2 — TELEMETRY

BACKENDS
  □ Tempo installed, searchEnabled, metricsGenerator on (service graph + span metrics)
  □ Loki installed, retention configured, compactor retention_enabled: true
  □ both reachable from the Collector and from Grafana

GRAFANA CORRELATION ⭐⭐ (the whole point)
  □ Prometheus datasource: exemplarTraceIdDestinations → tempo
  □ Tempo datasource: tracesToLogs → loki (filterByTraceID + filterBySpanID)
  □ Tempo datasource: tracesToMetrics → prometheus, with 3 useful queries
  □ Loki datasource: derivedFields matching YOUR log format → tempo
  □ stable datasource UIDs: prometheus / tempo / loki
  □ you have clicked metric → trace → log → metric without typing a query

COLLECTOR
  □ the AGENT DaemonSet: otlp receiver, k8sattributes, resourcedetection, batch
  □ the GATEWAY Deployment: tail_sampling, attributes/redact, batch, 3 exporters
  □ memory_limiter FIRST, batch LAST, in every pipeline
  □ GOMEMLIMIT ≈ 90% of the memory limit
  □ you validated the pipeline with a hand-crafted curl span BEFORE instrumenting
  □ the Collector's own metrics are scraped and alerted on
  □ you have proven drops = 0 under load

INSTRUMENTATION
  □ Java: zero-code via the agent (or the Operator), 4000+ spans/min
  □ Python: zero-code via opentelemetry-instrument
  □ Go: manual — TracerProvider, propagators, otelhttp, Inject, Shutdown
  □ Browser: WebTracerProvider, DocumentLoad, Fetch with propagateTraceHeaderCorsUrls
  □ OTEL_SERVICE_NAME set on every service
  □ OTEL_PROPAGATORS identical everywhere
  □ manual domain spans with business attributes (order.id, customer.tier)
  □ span.SetStatus(ERROR) + RecordException on every failure path
  □ low-cardinality span names (route templates, never IDs)

PROPAGATION
  □ a single request produces ONE trace across shop-ui → checkout → shop-api
  □ PostgreSQL/Redis calls appear as CLIENT spans automatically
  □ the async RabbitMQ hop appears as a PRODUCER + CONSUMER pair with a LINK
  □ you have deliberately broken propagation and recognised the symptom
  □ you can find a propagation bug from "SERVER spans with no parent"

SAMPLING
  □ head sampling = parentbased_traceidratio at 100%
  □ tail sampling at the gateway: errors, 5xx, slow, money path, canary = 100%
  □ health checks dropped; the rest sampled at ~10%
  □ you MEASURED the storage reduction and confirmed zero error loss

LOGS
  □ JSON logs with trace_id and span_id from Java, Python and Go
  □ filelog receiver shipping /var/log/pods to Loki with k8s metadata
  □ LogQL: you can filter by namespace, level, and trace_id
  □ no unbounded Loki labels

OPERATOR
  □ the OTel Operator installed, an Instrumentation resource defined
  □ injection via ONE annotation on a Deployment you didn't build
  □ you can explain what the init container does and the inject-sdk option for Go

BREAKING THINGS
  □ you broke propagation and saw the trace split
  □ you starved the Collector and watched memory_limiter shed load (not crash)
  □ you proved tail sampling keeps 100% of errors at 10% of the volume
  □ you pointed the SDK at a dead endpoint and confirmed the app kept running
  □ you instrumented a service you don't own (Operator / eBPF / sidecar)

TASKS
  □ 2.1 a five-hop trace including an async link
  □ 2.2 a measured 90% trace-storage reduction
  □ 2.3 a root cause found from the trace view alone
  □ 2.4 instrumenting a service you can't rebuild
  □ 2.5 the one-click incident dashboard
```

---

## Where next

| You want | Go to |
|---|---|
| Both cases unified: the full LGTM stack on one app | [04-CAPSTONE-END-TO-END.md](./04-CAPSTONE-END-TO-END.md) |
| PromQL / LogQL / TraceQL / Collector config on one page | [05-CHEATSHEET.md](./05-CHEATSHEET.md) |
| The theory (pillars, cardinality, sampling, SLOs) | [01-OBSERVABILITY-GUIDE.md](./01-OBSERVABILITY-GUIDE.md) |
| Metrics, dashboards and alerting | [02-CASE-1-prometheus-grafana.md](./02-CASE-1-prometheus-grafana.md) |
| An hour-by-hour plan | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
