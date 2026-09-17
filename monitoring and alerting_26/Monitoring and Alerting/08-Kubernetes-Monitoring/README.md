# 08 · Kubernetes Monitoring  ★ deep dive

**Level:** core · **Time:** ~3.5 h · **Goal:** run Prometheus on Kubernetes the Operator way, understand the four metric sources, and control the cardinality that k8s monitoring inevitably creates.

---

## 1. The four sources of Kubernetes metrics

| Source | What it reports | Endpoint | Cardinality |
|---|---|---|---|
| **kube-state-metrics (KSM)** | The **state of k8s objects** as declared in the API: deployments, replicas, pod phases, node conditions, PVC status, job status, HPA | `:8080/metrics` | Medium — grows with object count, not traffic |
| **cAdvisor** (in kubelet) | **Resource usage of containers**: CPU, memory, network, filesystem | kubelet `:10250/metrics/cadvisor` | **High** — grows with pods × containers × metrics |
| **kubelet /metrics & /metrics/probes** | Kubelet's own health, runtime operations, probe results | `:10250/metrics` | Medium |
| **node_exporter** (DaemonSet) | The **host**: CPU, memory, disk, network, filesystem, load | `:9100` | Low — one series set per node |
| **Your apps** | Business + RED metrics | whatever port you expose | Your problem |

**The distinction people get wrong:** KSM tells you *what Kubernetes thinks* ("2 of 3 replicas available", "pod is Pending", "PVC is Bound"). cAdvisor tells you *what the containers actually did* ("used 400m CPU", "working set 512Mi"). You need both.

KSM metric families worth memorising:
```
kube_pod_status_phase{phase="Pending|Running|Succeeded|Failed|Unknown"}
kube_pod_status_ready{condition="true|false|unknown"}
kube_pod_container_status_restarts_total
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff|ImagePullBackOff|..."}
kube_pod_container_status_terminated_reason{reason="OOMKilled|Error|..."}
kube_pod_container_resource_requests{resource="cpu|memory"}
kube_pod_container_resource_limits{resource="cpu|memory"}
kube_deployment_status_replicas_available / _unavailable / _updated
kube_deployment_spec_replicas
kube_node_status_condition{condition="Ready|MemoryPressure|DiskPressure|PIDPressure",status="true"}
kube_node_status_allocatable{resource=...} / kube_node_status_capacity{resource=...}
kube_persistentvolumeclaim_status_phase
kube_job_status_failed / kube_job_status_succeeded / kube_job_status_start_time
kube_hpa_status_current_replicas / kube_hpa_spec_max_replicas
kube_configmap_info / kube_secret_info   (metadata only, no values)
kubelet_volume_stats_available_bytes / _capacity_bytes / _used_bytes
```

---

## 2. Deploying: kube-prometheus-stack (the standard)

The `kube-prometheus-stack` Helm chart installs **Prometheus Operator + Prometheus + Alertmanager + Grafana + node_exporter + kube-state-metrics + a curated rule set + dashboards**.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

cat > kps-values.yaml <<'EOF'
prometheus:
  prometheusSpec:
    replicas: 2
    retention: 15d
    retentionSize: 80GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources: {requests: {storage: 100Gi}}
    resources:
      requests: {cpu: "1",  memory: 4Gi}
      limits:   {cpu: "4",  memory: 16Gi}
    serviceMonitorSelectorNilUsesHelmValues: false   # ⚠️ see gotcha below
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    probeSelectorNilUsesHelmValues: false
    scrapeInterval: 30s
    evaluationInterval: 30s
    enableFeatures:
      - exemplar-storage
      - native-histograms
    externalLabels:
      cluster: ap-south-1-prod
      region: ap-south-1
    additionalScrapeConfigs:
      name: extra-scrape-configs
      key: prometheus-additional.yaml
    remoteWrite:
      - url: https://mimir.example.com/api/v1/push
        basicAuth:
          username: {name: mimir-creds, key: user}
          password: {name: mimir-creds, key: pass}
        queueConfig: {maxShards: 50, capacity: 20000}

alertmanager:
  alertmanagerSpec:
    replicas: 3
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources: {requests: {storage: 5Gi}}
  config:
    global:
      resolve_timeout: 5m
      slack_api_url_file: /etc/alertmanager/secrets/slack-url
    route:
      receiver: default
      group_by: [alertname, namespace]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - matchers: [severity = "page"]
          receiver: pagerduty-critical
    receivers:
      - name: default
      - name: pagerduty-critical
        pagerduty_configs:
          - routing_key_file: /etc/alertmanager/secrets/pd-key
    templates:
      - /etc/alertmanager/templates/*.tmpl

grafana:
  adminPassword: ""        # use grafana.ingress + auth, or an existing secret
  grafana.ini:
    server: {root_url: "https://grafana.example.com"}
  sidecar:
    dashboards: {enabled: true, label: grafana_dashboard}
    datasources: {enabled: true, label: grafana_datasource}
  additionalDataSources:
    - name: Loki
      type: loki
      uid: loki
      url: http://loki:3100
      access: proxy

kube-state-metrics:
  metricLabelsAllowlist: ["pods=[app.kubernetes.io/name]", "deployments=[team]"]
  metricAnnotationsAllowList: ["pods=[description]"]

prometheus-node-exporter:
  extraArgs:
    - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+)($|/)
    - --collector.netclass.ignored-devices=^(veth.*|cali.*|flannel.*|cni.*|docker.*)$
    - --collector.textfile.directory=/host/var/lib/node_exporter
  hostRootFsMount: {enabled: true, mountPropagation: HostToContainer}

defaultRules:
  rules:
    alertmanager: true
    etcd: true
    configReloaders: true
    general: true
    k8sContainerCpuUsageSecondsTotal: true
    kubeApiserverAvailability: true
    kubelet: true
    node: true
    prometheus: true
    time: true
EOF

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f kps-values.yaml --version 85.2.0

kubectl -n monitoring get pods
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
kubectl -n monitoring port-forward svc/kps-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kps-kube-prometheus-alertmanager 9093:9093
```

> **The `*SelectorNilUsesHelmValues: false` flags are the single most common cause of "my ServiceMonitor isn't working".** By default the chart only selects monitors carrying the chart's own `release` label. Setting them to `false` means *any* ServiceMonitor/PodMonitor/PrometheusRule in scope is picked up.

---

## 3. The Operator and its CRDs

The **Prometheus Operator** reconciles Kubernetes Custom Resources into running Prometheus/Alertmanager/ThanosRuler instances and generates their config for you.

| CRD | Creates / does |
|---|---|
| **`Prometheus`** | A Prometheus StatefulSet (replicas, retention, storage, resources, selectors) |
| **`Alertmanager`** | An Alertmanager StatefulSet (clustered by replicas) |
| **`ThanosRuler`** | A ruler for remote-write/Thanos setups |
| **`ServiceMonitor`** | "Scrape this Service's endpoints" |
| **`PodMonitor`** | "Scrape these Pods directly" (no Service needed) |
| **`Probe`** | "Run blackbox probes against these targets" |
| **`ScrapeConfig`** | Arbitrary native `scrape_config` (0.70+) — for things the other CRDs can't express |
| **`PrometheusRule`** | Recording + alerting rule groups |
| **`PrometheusAgent`** | Agent-mode Prometheus (scrape + remote-write only) |
| **`AlertmanagerConfig`** | Namespaced routing/receiver config that merges into the root AM config |
| **`PodMetricsEndpoint`** | (newer) endpoint-level scrape definition |

```bash
kubectl get crd | grep coreos.com
kubectl -n monitoring get prometheus,servicemonitor,podmonitor,prometheusrule,probe,alertmanager
kubectl -n monitoring describe prometheus kps-kube-prometheus-prometheus
```

### ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: checkout-api
  namespace: monitoring            # or the app's namespace, if namespaceSelector allows
  labels:
    release: kps                   # only needed if *SelectorNilUsesHelmValues is left true
spec:
  namespaceSelector:
    matchNames: [checkout]         # or: any: true
  selector:
    matchLabels:
      app.kubernetes.io/name: checkout-api     # matches the Service's labels
  endpoints:
    - port: metrics                # the Service PORT NAME (not number)
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
      honorLabels: false
      scheme: http
      # basicAuth:
      #   username: {name: metrics-creds, key: user}
      #   password: {name: metrics-creds, key: pass}
      # tlsConfig:
      #   ca:   {secret: {name: metrics-tls, key: ca.crt}}
      #   cert: {secret: {name: metrics-tls, key: tls.crt}}
      #   key:  {secret: {name: metrics-tls, key: tls.key}}
      #   serverName: checkout-api
      # bearerTokenSecret: {name: sa-token, key: token}
      metricRelabelings:
        - action: drop
          sourceLabels: [__name__]
          regex: 'go_gc_.*|go_memstats_.*'
        - action: labeldrop
          regex: 'container_id|image_id|uid'
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_label_app_kubernetes_io_instance]
          targetLabel: instance
```

### PodMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata: {name: workers, namespace: monitoring}
spec:
  namespaceSelector: {matchNames: [jobs]}
  selector: {matchLabels: {app: batch-worker}}
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```
Use **PodMonitor** when there's no Service (StatefulSets scraped per-pod, DaemonSets, jobs) and **ServiceMonitor** when there is.

### Probe (blackbox)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata: {name: external-sites, namespace: monitoring}
spec:
  interval: 60s
  module: http_2xx
  prober:
    url: blackbox-exporter.monitoring:9115
    scheme: http
    path: /probe
  targets:
    staticConfig:
      static:
        - https://example.com/healthz
        - https://api.example.com/v1/ping
      labels: {env: prod, team: platform}
  # or:
  # ingress:
  #   selector: {matchLabels: {tier: frontend}}
```

### PrometheusRule

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-slo
  namespace: monitoring
  labels: {release: kps, app: kube-prometheus-stack}
spec:
  groups:
    - name: checkout.recording
      interval: 30s
      rules:
        - record: job:http_requests:rate5m
          expr: sum by (job, namespace) (rate(http_requests_total{namespace="checkout"}[5m]))
        - record: job:http_errors:ratio_rate5m
          expr: |
            sum by (job, namespace) (rate(http_requests_total{namespace="checkout",status=~"5.."}[5m]))
              / clamp_min(sum by (job, namespace) (rate(http_requests_total{namespace="checkout"}[5m])), 1e-9)
    - name: checkout.alerts
      rules:
        - alert: CheckoutHighErrorRate
          expr: job:http_errors:ratio_rate5m{namespace="checkout"} > 0.02
          for: 10m
          labels: {severity: page, team: checkout, service: checkout-api}
          annotations:
            summary: "Checkout error rate {{ $value | humanizePercentage }}"
            runbook: "https://runbooks.example.com/checkout/high-error-rate"
            dashboard: "https://grafana.example.com/d/checkout?var-namespace=checkout&from=now-1h"
```
Validate before applying — this is the fastest way to catch a broken rule:
```bash
kubectl get prometheusrule checkout-slo -n monitoring -o json \
  | jq '.spec' > rules.json
promtool check rules rules.json          # the spec is exactly a rule-file body
```
Even better: keep rules as plain `rules/*.yaml` in Git, `promtool check` + `promtool test` them in CI, then generate the `PrometheusRule` CRD with Helm/Kustomize.

### AlertmanagerConfig (namespaced routing)

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: checkout
  namespace: checkout
  labels: {alertmanagerConfig: enabled}
spec:
  route:
    receiver: checkout-slack
    groupBy: [alertname, namespace]
    groupWait: 30s
    groupInterval: 5m
    repeatInterval: 4h
    matchers:
      - {name: team, value: checkout, matchType: "="}
  receivers:
    - name: checkout-slack
      slackConfigs:
        - apiURL:
            name: slack-webhook
            key: url
          channel: '#checkout-alerts'
          sendResolved: true
```
The parent `Alertmanager` CR must opt in:
```yaml
spec:
  alertmanagerConfigMatcherStrategy:
    type: OnNamespace            # or Label with alertmanagerConfigSelector
```
Namespaced configs become **sub-routes** under the root route; their receivers are prefixed with the namespace (`checkout-checkout-slack`). Great for team self-service; dangerous if you let every namespace define its own page routes without review.

---

## 4. RBAC, and the errors it causes

Prometheus needs cluster-wide read access for service discovery:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: prometheus-discovery}
rules:
  - apiGroups: [""]
    resources: [nodes, nodes/metrics, nodes/proxy, services, endpoints, pods]
    verbs: [get, list, watch]
  - apiGroups: ["networking.k8s.io"]
    resources: [ingresses]
    verbs: [get, list, watch]
  - apiGroups: ["discovery.k8s.io"]
    resources: [endpointslices]
    verbs: [get, list, watch]
  - nonResourceURLs: ["/metrics", "/metrics/cadvisor"]
    verbs: [get]
```
Symptoms of missing RBAC: targets red with `403 Forbidden`, or discovery returns nothing. Check `kubectl -n monitoring logs prometheus-... -c prometheus | grep -i forbidden`.

For kubelet/cAdvisor scraping specifically, the Operator creates a `kubelet` Service in the kube-system namespace and needs `nodes/proxy` permission plus kubelet authn (bearer token from the ServiceAccount, or TLS client certs).

---

## 5. The cardinality problem in Kubernetes (and how to win it)

Kubernetes monitoring generates far more series than VM monitoring because **every pod, container, namespace and label combination is a dimension**, and pods are ephemeral (series churn).

Diagnose:
```bash
kubectl -n monitoring exec -it prometheus-kps-0 -c prometheus -- \
  promtool tsdb analyze /prometheus
```
```promql
prometheus_tsdb_head_series                          # total active series
rate(prometheus_tsdb_head_series_created_total[5m])  # churn rate — high churn is as bad as high count
topk(10, count by (__name__)({__name__=~".+"}))
topk(10, count by (job)(up))
count by (namespace)({__name__=~"container_.+"})
```

Controls, in order of impact:

| # | Control | Example |
|---|---|---|
| 1 | **Drop cAdvisor noise** | `container_cpu_cfs_throttled_periods_total`, `container_blkio_*`, per-cgroup `id` labels |
| 2 | **Drop unused kubelet metrics** | `kubelet_pod_worker_duration_microseconds`, `rest_client_*` |
| 3 | **Restrict KSM to what you use** | `--metric-allowlist`, `--metric-denylist`, or per-family disable flags |
| 4 | **Drop Go runtime metrics** | `go_gc_.*`, `go_memstats_.*` (keep `go_goroutines`, `go_memstats_heap_inuse_bytes`) |
| 5 | **Reduce scrape interval** for low-value jobs | 30 s → 60 s halves the samples |
| 6 | **Shorter retention of raw data + downsample** | Thanos/Mimir compactor: 5m/1h resolution for old data |
| 7 | **Shard by namespace/team** | Multiple `Prometheus` CRs, each with a `namespaceSelector` |
| 8 | **`metricLabelsAllowlist` discipline in KSM** | Never allowlist high-cardinality annotations |
| 9 | **`honorLabels` care** | Duplicate/conflicting labels multiply series |
| 10 | **Drop ephemeral label churn** | Don't scrape pod names for short-lived jobs; aggregate to `deployment` |

```yaml
# A production-grade metricRelabelings block for cAdvisor endpoints
metricRelabelings:
  - sourceLabels: [__name__]
    action: drop
    regex: 'container_blkio_device_usage_total|container_cpu_cfs_throttled_seconds_total|container_tasks_state'
  - sourceLabels: [__name__]
    action: drop
    regex: 'go_gc_.*|go_memstats_(?!heap_inuse_bytes|alloc_bytes).*'
  - action: labeldrop
    regex: 'id|image_id|uid|name|device'
  - sourceLabels: [container]
    action: drop
    regex: 'POD|'                    # pause containers + empty
```

**Rule of thumb budget:** < 100k series per node for a comfortable single Prometheus; 100k–1M needs tuning + real RAM (8–32 GB); > 1M series ⇒ shard or move to a remote-write backend.

---

## 6. The alert set you should have on Kubernetes

Full YAML in [`13-Alert-Rules-Library`](../13-Alert-Rules-Library/README.md). Summary:

| Alert | Expression sketch | Severity |
|---|---|---|
| `KubeNodeNotReady` | `kube_node_status_condition{condition="Ready",status="true"} == 0` for 5m | page |
| `KubeNodeUnreachable` | `kube_node_spec_taint{key="node.kubernetes.io/unreachable"} == 1` for 5m | page |
| `KubePodNotReady` | `kube_pod_status_ready{condition="false"} == 1` for 15m (excluding Succeeded/Failed) | ticket |
| `KubePodCrashLooping` | `rate(kube_pod_container_status_restarts_total[15m]) * 900 > 3` | ticket |
| `KubeContainerOOMKilled` | `increase(kube_pod_container_status_terminated_reason{reason="OOMKilled"}[10m]) > 0` | ticket |
| `KubeDeploymentReplicasMismatch` | `kube_deployment_spec_replicas != kube_deployment_status_replicas_available` for 15m | page if 0 available |
| `KubeStatefulSetReplicasMismatch` | same for statefulsets, `for: 15m` | ticket |
| `KubeJobFailed` | `kube_job_status_failed > 0` and job age > 1h | ticket |
| `KubePersistentVolumeFillingUp` | `kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.1` or `predict_linear(...[6h], 4*3600) < 0` | page |
| `KubeHPAAtMaxReplicas` | `kube_hpa_status_current_replicas == kube_hpa_spec_max_replicas` for 15m | ticket |
| `KubePodPendingTooLong` | `kube_pod_status_phase{phase="Pending"} == 1` for 20m | ticket |
| `KubeletTooManyPodStarts` / `PLEG unhealthy` | `rate(kubelet_pod_start_duration_seconds_count[5m])`, `kubelet_pleg_relist_duration_seconds` p99 | page |
| `KubeAPIServerLatency` | `histogram_quantile(0.99, sum by(le)(rate(apiserver_request_duration_seconds_bucket{verb!~"WATCH|LIST"}[5m]))) > 1` | page |
| `KubeAPIServerErrorRate` | `sum(rate(apiserver_request_total{code=~"5.."}[5m])) / sum(rate(apiserver_request_total[5m])) > 0.03` | page |
| `KubeClientCertificateExpiresIn7Days` | `apiserver_client_certificate_expiration_seconds_count > 0 and histogram_quantile(0.01, ...) < 7*86400` | page |
| `KubeQuotaAlmostFull` | `kube_resourcequota{type="used"} / on(...) kube_resourcequota{type="hard"} > 0.9` | ticket |
| `ContainerCPUThrottlingHigh` | throttled ratio > 0.5 for 15m | ticket |
| `ContainerMemoryNearLimit` | working_set / limit > 0.9 for 10m | ticket |

Also: **`up == 0`** for `kubelet`, `kube-state-metrics`, `node-exporter`, `apiserver`, `coredns`, `etcd`, and the **kube-prometheus-stack default rule set** (`kubernetes-apps`, `kubernetes-resources`, `kubernetes-storage`, `node-exporter`, `prometheus`, `alertmanager`, `general`, `kube-apiserver-*`, `etcd`, `kubelet`) — read them once; they're an excellent reference implementation.

```bash
kubectl -n monitoring get prometheusrule -o custom-columns=NAME:.metadata.name,GROUPS:.spec.groups[*].name
kubectl -n monitoring get prometheusrule kps-kube-prometheus-k8s -o yaml | less
```

---

## 7. Multi-cluster and long-term storage

| Pattern | When | How |
|---|---|---|
| **One Prometheus per cluster + remote write to a central store** | Most common, recommended | Mimir / Thanos Receive / VictoriaMetrics / Grafana Cloud / AMP. Add `cluster` external label. |
| **Thanos sidecar per Prometheus** | You want object-storage-backed long retention + a global query view | Sidecar uploads 2h blocks to S3; Store Gateway reads them; Query frontend dedupes by `replica` |
| **Thanos Receive** | Push-based central store for many clusters | Prometheus `remote_write` → Receive → Store |
| **Federation** | Few clusters, small metric sets, no object storage | Pull `/federate` with `match[]` for **recording rules only** |
| **PrometheusAgent CRD** | Edge/small clusters that only need to ship data | Scrape + remote-write, no local query/rules |
| **Managed (AMP / GMP / Azure Monitor managed Prometheus)** | You don't want to run the TSDB | Remote-write compatible; check cost per sample |

**Global dashboards require consistent labels.** Decide your canonical label set once (`cluster`, `region`, `env`, `team`, `namespace`, `service`, `workload`) and enforce it via `external_labels` + relabeling in every cluster. Inconsistent labels are why global views fail.

**Deduplication:** with 2 replicas per cluster, mark one label as the replica label (`external_labels: {replica: prom-0}`) and have the query layer dedupe on it (Thanos `--query.replica-label=replica`, Mimir automatically drops `__name__`-duplicate samples from HA pairs when configured with `ha_tracker`).

---

## 8. Operational tips that save you

```bash
# What did the Operator actually generate?
kubectl -n monitoring get secret prometheus-kps-kube-prometheus-prometheus -o jsonpath='{.data.prometheus\.yaml\.gz}' \
  | base64 -d | gunzip | less           # the final prometheus.yml

# Live config + targets from inside the pod
kubectl -n monitoring exec prometheus-kps-0 -c prometheus -- \
  wget -qO- localhost:9090/api/v1/targets?state=active | jq '.data.activeTargets[].health'

# Rules as Prometheus sees them
kubectl -n monitoring exec prometheus-kps-0 -c prometheus -- \
  wget -qO- localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {name,health,lastError}'

# Force a config reload (the Operator usually does it for you)
kubectl -n monitoring exec prometheus-kps-0 -c config-reloader -- wget -qO- --post-data='' localhost:9090/-/reload

# Logs
kubectl -n monitoring logs prometheus-kps-0 -c prometheus --tail=200
kubectl -n monitoring logs prometheus-kps-0 -c config-reloader --tail=50
kubectl -n monitoring logs -l app.kubernetes.io/name=kube-state-metrics --tail=100
```

Other habits:
- **PodDisruptionBudgets** for Prometheus and Alertmanager (replicas ≥ 2 / 3).
- **Anti-affinity** so replicas land on different nodes/zones.
- **Persistent volumes** for both — losing the WAL means losing recent data and all silences.
- **Resource requests AND limits**; Prometheus is memory-hungry and CPU-spiky. Set `GOMEMLIMIT` if available.
- **NetworkPolicy** to lock down `:9090` (Prometheus has no auth by default!). Put Grafana behind SSO/OAuth proxy; never expose Prometheus publicly without a reverse proxy adding authn/authz.
- **Upgrade CRDs before the chart**: `helm upgrade` does not update CRDs.
  ```bash
  kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.90.1/example/prometheus-operator-crd/
  ```
- **Back up your `values.yaml`** — it *is* your monitoring architecture document.

---

## Lab

1. Install `kube-prometheus-stack` on kind/minikube/EKS.
2. Deploy a small app with a `/metrics` port and a `Service`; write a `ServiceMonitor`; confirm it appears in Prometheus `/targets`.
3. Break it three ways and observe: wrong port name, wrong namespace selector, missing RBAC.
4. Add a `PrometheusRule` with a `for: 1m` alert; `kubectl scale --replicas=0` the app; watch it fire and route.
5. Run `promtool tsdb analyze` inside the Prometheus pod; find your top 3 metrics by cardinality and drop one.
6. Create a `Probe` for an external URL and alert on `probe_success == 0`.

---

## Self-check

1. KSM vs cAdvisor vs node_exporter — one sentence each on what they report.
2. Why is `serviceMonitorSelectorNilUsesHelmValues: false` so commonly needed?
3. ServiceMonitor vs PodMonitor vs Probe vs ScrapeConfig — when do you use each?
4. What RBAC verbs does Prometheus need and over which resources?
5. Name four concrete ways to cut cAdvisor cardinality.
6. Why is series *churn* as damaging as series *count*?
7. How do you see the actual `prometheus.yml` the Operator generated?
8. What is `AlertmanagerConfig` and what must the parent `Alertmanager` CR do for it to apply?
9. Describe a 20-cluster monitoring architecture and how you deduplicate replicas.
10. Why must Prometheus never be exposed to the internet without a proxy?

→ Next: [`09-SLOs-and-Error-Budgets`](../09-SLOs-and-Error-Budgets/README.md)
