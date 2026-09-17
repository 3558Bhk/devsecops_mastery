# Cheatsheet · Kubernetes monitoring

## Install / upgrade kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm show values prometheus-community/kube-prometheus-stack > values-reference.yaml

# CRDs FIRST — helm upgrade does not touch them
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.90.1/example/prometheus-operator-crd/

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f kps-values.yaml
```

## The five values that trip everyone up

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false   # accept ANY ServiceMonitor
    podMonitorSelectorNilUsesHelmValues: false
    probeSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    scrapeConfigSelectorNilUsesHelmValues: false
```
Leave them `true` (the default) and your monitors are ignored unless they carry the chart's `release`/`app.kubernetes.io/instance` label.

## Essential values

```yaml
prometheus:
  prometheusSpec:
    replicas: 2
    retention: 15d
    retentionSize: 80GB
    scrapeInterval: 30s
    evaluationInterval: 30s
    externalLabels: {cluster: prod-1, region: ap-south-1}
    enableFeatures: [exemplar-storage, native-histograms]
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources: {requests: {storage: 100Gi}}
    resources:
      requests: {cpu: "1", memory: 4Gi}
      limits:   {cpu: "4", memory: 16Gi}
    additionalScrapeConfigs: {name: extra-scrape-configs, key: prometheus-additional.yaml}
    remoteWrite:
      - url: https://mimir/api/v1/push
        basicAuth:
          username: {name: mimir-creds, key: user}
          password: {name: mimir-creds, key: pass}
alertmanager:
  alertmanagerSpec: {replicas: 3}
  config: { ... }                       # or use AlertmanagerConfig CRDs
grafana:
  sidecar:
    dashboards:  {enabled: true, label: grafana_dashboard}
    datasources: {enabled: true, label: grafana_datasource}
kube-state-metrics:
  metricLabelsAllowlist: ["pods=[app.kubernetes.io/name]"]
prometheus-node-exporter:
  extraArgs:
    - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+)($|/)
    - --collector.netclass.ignored-devices=^(veth.*|cali.*|cni.*|docker.*)$
```

## CRDs at a glance

| CRD | apiVersion | Purpose |
|---|---|---|
| `Prometheus` | `monitoring.coreos.com/v1` | The Prometheus StatefulSet |
| `Alertmanager` | `monitoring.coreos.com/v1` | The Alertmanager StatefulSet |
| `ThanosRuler` | `monitoring.coreos.com/v1` | Rules against remote/Thanos data |
| `PrometheusAgent` | `monitoring.coreos.com/v1alpha1` | Agent mode (scrape + remote-write) |
| `ServiceMonitor` | `monitoring.coreos.com/v1` | Scrape a Service's endpoints |
| `PodMonitor` | `monitoring.coreos.com/v1` | Scrape Pods directly |
| `Probe` | `monitoring.coreos.com/v1` | Blackbox probes |
| `ScrapeConfig` | `monitoring.coreos.com/v1alpha1` | Raw `scrape_config` escape hatch |
| `PrometheusRule` | `monitoring.coreos.com/v1` | Recording + alerting rules |
| `AlertmanagerConfig` | `monitoring.coreos.com/v1alpha1` | Namespaced routing/receivers |

## ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: myapp, namespace: monitoring}
spec:
  namespaceSelector: {matchNames: [myapp-ns]}   # or {any: true}
  selector: {matchLabels: {app.kubernetes.io/name: myapp}}
  endpoints:
    - port: metrics          # the Service PORT NAME
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
      scheme: http
      # basicAuth: {username: {name: s, key: u}, password: {name: s, key: p}}
      # bearerTokenSecret: {name: s, key: token}
      # tlsConfig: {ca: {secret: {name: s, key: ca.crt}}, serverName: myapp}
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_label_app_kubernetes_io_instance]
          targetLabel: instance
      metricRelabelings:
        - action: drop
          sourceLabels: [__name__]
          regex: 'go_gc_.*|go_memstats_.*'
```

## PodMonitor / Probe

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata: {name: workers, namespace: monitoring}
spec:
  namespaceSelector: {matchNames: [jobs]}
  selector: {matchLabels: {app: worker}}
  podMetricsEndpoints: [{port: metrics, interval: 30s}]
---
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata: {name: external, namespace: monitoring}
spec:
  interval: 60s
  module: http_2xx
  prober: {url: blackbox-exporter.monitoring:9115, path: /probe}
  targets:
    staticConfig:
      static: ['https://example.com/healthz']
      labels: {env: prod}
```

## PrometheusRule

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: myapp-alerts
  namespace: monitoring
  labels: {release: kps}
spec:
  groups:
    - name: myapp.alerts
      rules:
        - alert: MyAppHighErrorRate
          expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
                  / sum(rate(http_requests_total[5m])) by (service) > 0.05
          for: 10m
          labels: {severity: page, team: myteam, service: myapp}
          annotations:
            summary: "myapp error rate {{ $value | humanizePercentage }}"
            runbook: "https://runbooks.example.com/myapp/errors"
```
Validate: `kubectl get prometheusrule X -o jsonpath='{.spec}' > /tmp/r.yaml && promtool check rules /tmp/r.yaml`
(or `kubectl get prometheusrule X -o json | jq .spec > /tmp/rules.json && promtool check rules /tmp/rules.json`)

## AlertmanagerConfig (namespaced)

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata: {name: team-a, namespace: team-a, labels: {alertmanagerConfig: enabled}}
spec:
  route:
    receiver: team-a-slack
    groupBy: [alertname]
    matchers: [{name: team, value: team-a, matchType: "="}]
  receivers:
    - name: team-a-slack
      slackConfigs:
        - apiURL: {name: slack-secret, key: url}
          channel: '#team-a-alerts'
          sendResolved: true
```
Parent must opt in:
```yaml
spec:
  alertmanagerConfigMatcherStrategy: {type: OnNamespace}   # or Label + selector
  alertmanagerConfigNamespaceSelector: {matchLabels: {monitoring: enabled}}
```

## RBAC for discovery

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
  - apiGroups: ["apps"]
    resources: [statefulsets, deployments]
    verbs: [get, list, watch]
  - nonResourceURLs: ["/metrics", "/metrics/cadvisor"]
    verbs: [get]
```

## Metric sources & ports

| Source | Endpoint | Content |
|---|---|---|
| kube-state-metrics | `:8080/metrics` | k8s object state (`kube_*`) |
| kube-state-metrics self | `:8081/metrics` | KSM's own health |
| cAdvisor (kubelet) | `:10250/metrics/cadvisor` | container resource usage (`container_*`) |
| kubelet | `:10250/metrics` | kubelet internals (`kubelet_*`) |
| kubelet probes | `:10250/metrics/probes` | probe results (`prober_probe_total`) |
| node_exporter | `:9100/metrics` | host (`node_*`) |
| API server | `:6443/metrics` | `apiserver_*`, `etcd_*`, `workqueue_*` |
| CoreDNS | `:9153/metrics` | `coredns_*` |

## Cardinality controls

```yaml
metricRelabelings:
  - sourceLabels: [__name__]
    action: drop
    regex: 'container_blkio_.*|container_cpu_cfs_throttled_seconds_total|go_gc_.*|go_memstats_.*'
  - action: labeldrop
    regex: 'id|image_id|uid|name|device|controller_revision_hash|pod_template_hash'
  - sourceLabels: [container]
    action: drop
    regex: 'POD|'
```
```yaml
kube-state-metrics:
  metricAllowlist: ["kube_pod_*", "kube_deployment_*", "kube_node_*"]
  metricDenylist: ["kube_secret_*", "kube_configmap_*"]
```

## Debug commands

```bash
kubectl -n monitoring get prometheus,servicemonitor,podmonitor,probe,prometheusrule,alertmanager,alertmanagerconfig
kubectl -n monitoring describe prometheus kps-kube-prometheus-prometheus
kubectl -n monitoring logs prometheus-kps-0 -c prometheus --tail=200
kubectl -n monitoring logs prometheus-kps-0 -c config-reloader --tail=50
kubectl -n monitoring logs -l app.kubernetes.io/name=kube-state-metrics --tail=100

# the final generated config
kubectl -n monitoring get secret prometheus-kps-kube-prometheus-prometheus \
  -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | less

# from inside the pod
kubectl -n monitoring exec prometheus-kps-0 -c prometheus -- \
  wget -qO- localhost:9090/api/v1/targets?state=active | jq '.data.activeTargets[]|{job:.labels.job,health:.health,lastError:.lastError}'
kubectl -n monitoring exec prometheus-kps-0 -c prometheus -- \
  wget -qO- localhost:9090/api/v1/rules | jq '.data.groups[].rules[]|select(.health!="ok")'
kubectl -n monitoring exec prometheus-kps-0 -c prometheus -- promtool tsdb analyze /prometheus
kubectl -n monitoring exec prometheus-kps-0 -c config-reloader -- wget -qO- --post-data='' localhost:9090/-/reload

kubectl -n monitoring port-forward svc/kps-grafana 3000:80
kubectl -n monitoring port-forward svc/kps-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kps-kube-prometheus-alertmanager 9093:9093

# dashboards as ConfigMaps (Grafana sidecar)
kubectl -n monitoring create configmap my-dash --from-file=my.json -l grafana_dashboard=1
```

## Key k8s metric families (memorise the useful ones)

```
kube_pod_status_phase{phase="Pending|Running|Succeeded|Failed|Unknown"}
kube_pod_status_ready{condition="true|false|unknown"}
kube_pod_status_unschedulable
kube_pod_container_status_restarts_total
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff|ImagePullBackOff|ContainerCreating"}
kube_pod_container_status_terminated_reason{reason="OOMKilled|Error|Completed"}
kube_pod_container_resource_requests{resource="cpu|memory"}
kube_pod_container_resource_limits{resource="cpu|memory"}
kube_deployment_spec_replicas / _status_replicas_available / _unavailable / _updated
kube_statefulset_status_replicas_ready / _status_observed_generation
kube_node_status_condition{condition="Ready|MemoryPressure|DiskPressure|PIDPressure|NetworkUnavailable"}
kube_node_spec_taint{key=...,effect=...}
kube_node_status_allocatable / kube_node_status_capacity
kube_persistentvolumeclaim_status_phase / kube_persistentvolume_status_phase
kubelet_volume_stats_available_bytes / _capacity_bytes / _used_bytes / _inodes / _inodes_used
kube_job_status_failed / _succeeded / kube_job_spec_completions / kube_job_status_start_time
kube_horizontalpodautoscaler_status_current_replicas / _spec_max_replicas / _status_condition
kube_resourcequota{type="hard|used"}
kube_namespace_labels / kube_pod_labels / kube_pod_info
container_cpu_usage_seconds_total / container_memory_working_set_bytes / container_memory_rss
container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total
container_network_receive_bytes_total / container_fs_usage_bytes
apiserver_request_total{code,verb,resource} / apiserver_request_duration_seconds_bucket
kubelet_pleg_relist_duration_seconds_bucket / kubelet_pod_start_duration_seconds_bucket
kubelet_runtime_operations_errors_total
coredns_dns_responses_total / coredns_dns_request_duration_seconds
```

## Community dashboards

| ID | Name |
|---|---|
| 1860 | Node Exporter Full |
| 315 | Kubernetes cluster monitoring |
| 13105 | Kubernetes / Compute Resources / Cluster |
| 6781 | Kubernetes All-in-one |
| 763 | Kubernetes pods |
| 13946 | Alertmanager |
| 3662 | Prometheus 2.0 Overview |
| 16380 / 16355 | Prometheus cardinality explorer |
| 9578 / 7353 | MySQL / Redis |
| 15172 | Thanos global view |
