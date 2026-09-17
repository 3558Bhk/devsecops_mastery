# 📊 Project 7 — Observability: Metrics, Logs, Events & Alerts

> **Time:** 3 hours · **Prereq:** [Project 6](09-PROJECT-6-ingress-tls.md)
>
> **What you'll learn:** `kubectl top`, metrics-server, a full Prometheus + Grafana + Alertmanager stack, how to scrape your own app, the metrics that actually matter, a logging pipeline, and the alerts you should have on day one.
>
> **Why this project exists:** "it's slow" is not a debuggable statement. After this you can say "p99 latency is 1.8 s because CPU is throttled at 78% on 3 of 5 Pods".

---

## 7.1 The three pillars, Kubernetes edition

| Pillar | Question | Tools |
|---|---|---|
| **Metrics** | "How much / how fast / how many, right now and over time?" | metrics-server, Prometheus, Grafana |
| **Logs** | "What exactly happened, in the app's own words?" | `kubectl logs`, Loki/ELK, Fluent Bit |
| **Traces** | "Where did this one request spend its 2 seconds?" | OpenTelemetry, Jaeger, Tempo |

Plus the Kubernetes-specific fourth pillar: **Events & object state** (`kubectl describe`, `kubectl get events`, kube-state-metrics). Nothing else tells you *why* a Pod is Pending.

```
        ┌──► metrics-server ──► kubectl top, HPA           (in-memory, 15 min history)
Pods ───┤
        └──► Prometheus ──► Grafana, Alertmanager          (persistent, queryable, alerting)
              ▲    ▲    ▲
              │    │    └── kube-state-metrics  (K8s OBJECT state: deployments, pods, quotas)
              │    └────── node-exporter        (NODE state: cpu, mem, disk, network)
              └─────────── cAdvisor             (CONTAINER state: inside kubelet, always on)
```

> 🔑 **cAdvisor is built into the kubelet.** You already have container metrics — you just need something to scrape and store them.

---

## 7.2 Step 1 — metrics-server: `kubectl top`

```bash
kubectl top nodes
# Error from server (ServiceUnavailable): the server could not find the requested resource
```

That error means metrics-server isn't installed. Fix it:

```bash
# minikube
minikube addons enable metrics-server

# kind / generic
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# ⚠️ on kind/minikube/k3d the kubelet uses a self-signed cert, so metrics-server refuses to
#    connect. Patch it to allow that (LOCAL CLUSTERS ONLY — never in production):
kubectl patch deployment metrics-server -n kube-system --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}
]'
kubectl rollout status deploy/metrics-server -n kube-system
```

Verify:

```bash
kubectl get apiservices | grep metrics
# v1beta1.metrics.k8s.io   kube-system/metrics-server   True   2m    ← MUST be True

kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq .
kubectl top nodes
```

```
NAME                CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
learn-control-plane 180m         9%     1450Mi          42%
learn-worker        95m          4%     620Mi           18%
learn-worker2       110m         5%     705Mi           20%
```

```bash
kubectl top pods -A
kubectl top pods -n default --sort-by=memory
kubectl top pods -n default --sort-by=cpu
kubectl top pods -l app=web --containers
kubectl top pod web-abc123 --containers
```

```
POD          NAME        CPU(cores)   MEMORY(bytes)
web-abc123   web         1m           8Mi
```

**What metrics-server is NOT:**

| | metrics-server | Prometheus |
|---|---|---|
| Storage | In-memory only | Disk, configurable retention |
| History | ~15 min (last few scrapes) | Months |
| Resolution | 15–60 s | configurable |
| Querying | `kubectl top` only | PromQL |
| Alerts | ❌ | ✅ |
| Dashboards | ❌ | ✅ Grafana |
| Purpose | HPA + `kubectl top` | Real monitoring |

**Do not scale metrics-server to "keep more history".** Install Prometheus.

### Debugging a broken metrics-server

```bash
kubectl get pods -n kube-system -l k8s-app=metrics-server
kubectl logs -n kube-system deploy/metrics-server --tail=50
```

| Log line | Cause | Fix |
|---|---|---|
| `x509: cannot validate certificate for 10.x.x.x because it doesn't contain any IP SANs` | Self-signed kubelet cert | `--kubelet-insecure-tls` (local only) or fix kubelet serving certs |
| `unable to fully scrape metrics: source kubelet … connection refused` | kubelet port 10250 blocked | Open 10250 between control plane and nodes |
| `no such host` for node names | Node DNS unresolvable | `--kubelet-preferred-address-types=InternalIP` |
| APIService shows `False` with `MissingEndpoints` | metrics-server pods not Ready | Fix the above |
| `kubectl top` works for nodes but not pods | Pod metrics need the kubelet's `/stats/summary` | Same fixes |

---

## 7.3 Step 2 — Generate some load (you need data to look at)

Deploy a small app with a real `/metrics` endpoint, plus a load generator. This is the fixture for the rest of the project.

```bash
mkdir -p ~/k8s-learn/p7/app && cd ~/k8s-learn/p7
```

`app/main.py`:

```python
#!/usr/bin/env python3
"""A tiny HTTP app with a real Prometheus /metrics endpoint, deliberate latency,
   and a failure rate you can dial up. Built for learning observability."""
import http.server
import os
import random
import socket
import threading
import time
from collections import Counter

PORT = int(os.environ.get("PORT", "8080"))
FAIL_RATE = float(os.environ.get("FAIL_RATE", "0.05"))
LATENCY_MAX = float(os.environ.get("LATENCY_MAX", "0.4"))
VERSION = os.environ.get("VERSION", "1.0.0")
HOST = socket.gethostname()

REQUESTS = Counter()
LATENCY = Counter()          # crude histogram via fixed buckets
BUCKETS = [0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
BUCKET_COUNTS = {b: 0 for b in BUCKETS}
LATENCY_SUM = 0.0
LATENCY_COUNT = 0
IN_FLIGHT = 0
START_TIME = time.time()
WORK = []                    # deliberately leaky: demonstrates memory growth


def render_metrics():
    lines = [
        "# HELP demo_http_requests_total Total HTTP requests by path and status.",
        "# TYPE demo_http_requests_total counter",
    ]
    for (path, status), n in sorted(REQUESTS.items()):
        lines.append(f'demo_http_requests_total{{path="{path}",status="{status}",version="{VERSION}",pod="{HOST}"}} {n}')
    lines += [
        "# HELP demo_http_request_duration_seconds Request latency histogram.",
        "# TYPE demo_http_request_duration_seconds histogram",
    ]
    for b in BUCKETS:
        lines.append(f'demo_http_request_duration_seconds_bucket{{le="{b}",version="{VERSION}",pod="{HOST}"}} {BUCKET_COUNTS[b]}')
    lines.append(f'demo_http_request_duration_seconds_bucket{{le="+Inf",version="{VERSION}",pod="{HOST}"}} {LATENCY_COUNT}')
    lines.append(f'demo_http_request_duration_seconds_sum{{version="{VERSION}",pod="{HOST}"}} {LATENCY_SUM:.6f}')
    lines.append(f'demo_http_request_duration_seconds_count{{version="{VERSION}",pod="{HOST}"}} {LATENCY_COUNT}')
    lines += [
        "# HELP demo_inflight_requests Requests currently being served.",
        "# TYPE demo_inflight_requests gauge",
        f'demo_inflight_requests{{pod="{HOST}"}} {IN_FLIGHT}',
        "# HELP demo_allocated_items Deliberately growing counter (memory leak demo).",
        "# TYPE demo_allocated_items gauge",
        f'demo_allocated_items{{pod="{HOST}"}} {len(WORK)}',
        "# HELP demo_process_uptime_seconds Seconds since start.",
        "# TYPE demo_process_uptime_seconds gauge",
        f'demo_process_uptime_seconds{{pod="{HOST}"}} {time.time() - START_TIME:.0f}',
    ]
    return "\n".join(lines) + "\n"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass                                  # keep stdout clean; logs go through /logs

    def _respond(self, code, body, ctype="text/plain"):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        global IN_FLIGHT, LATENCY_SUM, LATENCY_COUNT
        IN_FLIGHT += 1
        t0 = time.time()
        path = self.path.split("?")[0]
        try:
            if path == "/metrics":
                self._respond(200, render_metrics(), "text/plain; version=0.0.4")
                status = 200
            elif path in ("/healthz", "/live"):
                # LIVENESS: only checks this process. Never touch a dependency here.
                self._respond(200, "ok\n")
                status = 200
            elif path in ("/ready", "/readyz"):
                # READINESS: would check dependencies. Fail if overloaded.
                if IN_FLIGHT > 50:
                    self._respond(503, "too busy\n")
                    status = 503
                else:
                    self._respond(200, "ready\n")
                    status = 200
            elif path == "/":
                time.sleep(random.random() * LATENCY_MAX)
                # deliberately grow memory: one 4 KiB object per ~20 requests
                if random.random() < 0.05:
                    WORK.append(os.urandom(4096))
                if random.random() < FAIL_RATE:
                    self._respond(500, '{"error":"simulated failure"}\n', "application/json")
                    status = 500
                else:
                    self._respond(200, f"hello from {HOST} v{VERSION}\n")
                    status = 200
            elif path == "/slow":
                time.sleep(float(self.path.split("s=")[-1]) if "s=" in self.path else 3.0)
                self._respond(200, "slow done\n")
                status = 200
            elif path == "/logs":
                print(f"{time.strftime('%FT%TZ', time.gmtime())} INFO  serving /logs from {HOST}", flush=True)
                self._respond(200, "check kubectl logs\n")
                status = 200
            else:
                self._respond(404, "not found\n")
                status = 404
        finally:
            dt = time.time() - t0
            REQUESTS[(path, str(status))] += 1
            LATENCY_SUM += dt
            LATENCY_COUNT += 1
            for b in BUCKETS:
                if dt <= b:
                    BUCKET_COUNTS[b] += 1
            IN_FLIGHT -= 1


class ThreadedServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    print(f"demo app {VERSION} starting on :{PORT} (pod {HOST})", flush=True)
    ThreadedServer(("0.0.0.0", PORT), Handler).serve_forever()
```

`app/Dockerfile`:

```dockerfile
FROM python:3.13-alpine
WORKDIR /app
RUN addgroup -g 10001 app && adduser -D -u 10001 -G app app
COPY main.py .
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=2s CMD wget -qO- http://localhost:8080/healthz || exit 1
ENTRYPOINT ["python", "main.py"]
```

```bash
docker build -t demo-app:1.0.0 app/
kind load docker-image demo-app:1.0.0 --name learn      # or: minikube image load demo-app:1.0.0
```

`app/deploy.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
  labels: {app: demo}
spec:
  replicas: 3
  selector: {matchLabels: {app: demo}}
  strategy:
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  template:
    metadata:
      labels: {app: demo, version: v1}
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: demo
          image: demo-app:1.0.0
          imagePullPolicy: IfNotPresent
          ports:
            - {name: http,    containerPort: 8080}
            - {name: metrics, containerPort: 8080}     # same port; Prometheus scrapes /metrics
          env:
            - {name: PORT, value: "8080"}
            - {name: VERSION, value: "1.0.0"}
            - {name: FAIL_RATE, value: "0.05"}
            - {name: LATENCY_MAX, value: "0.4"}
          resources:
            requests: {cpu: 100m, memory: 128Mi}
            limits:   {cpu: 250m, memory: 192Mi}       # deliberately tight → throttling to observe
          startupProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 2
            failureThreshold: 30
          readinessProbe:
            httpGet: {path: /ready, port: http}
            periodSeconds: 5
            failureThreshold: 2
          livenessProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 20
            failureThreshold: 3
          lifecycle:
            preStop: {exec: {command: ["/bin/sh","-c","sleep 5"]}}
---
apiVersion: v1
kind: Service
metadata:
  name: demo
  labels: {app: demo}
spec:
  selector: {app: demo}
  ports:
    - {name: http, port: 8080, targetPort: http}
---
# ── load generator: keeps hammering demo so we always have data ──
apiVersion: apps/v1
kind: Deployment
metadata: {name: load-gen}
spec:
  replicas: 1
  selector: {matchLabels: {app: load-gen}}
  template:
    metadata: {labels: {app: load-gen}}
    spec:
      containers:
        - name: load
          image: curlimages/curl:8.10.1
          command:
            - sh
            - -c
            - |
              echo "load generator starting"
              while true; do
                for i in $(seq 1 20); do
                  curl -s -o /dev/null -m 3 http://demo:8080/ &
                done
                wait
                curl -s -o /dev/null -m 5 http://demo:8080/slow?s=1 || true
                sleep 1
              done
          resources:
            requests: {cpu: 50m, memory: 32Mi}
            limits:   {cpu: 200m, memory: 64Mi}
```

```bash
kubectl apply -f app/deploy.yaml
kubectl rollout status deploy/demo
kubectl get pods -o wide
kubectl top pods -l app=demo
```

Confirm the metrics endpoint:

```bash
kubectl port-forward svc/demo 8080:8080 &
sleep 2
curl -s localhost:8080/metrics | head -20
curl -s localhost:8080/
kill %1
```

---

## 7.4 Step 3 — Prometheus + Grafana in one Helm install

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo kube-prometheus-stack
```

Inspect the values before installing — this is a big chart:

```bash
helm show values prometheus-community/kube-prometheus-stack > kps-values.yaml
grep -nE '^\s{0,4}(grafana|prometheus|alertmanager|nodeExporter|kubeStateMetrics|defaultRules|prometheusOperator):' kps-values.yaml
```

`kps-values.yaml` (the parts worth changing for a local cluster):

```yaml
# ── Grafana ──
grafana:
  enabled: true
  adminPassword: "learn-grafana"           # change in real life; use a Secret
  service:
    type: ClusterIP
    port: 80
  grafana.ini:
    server: {root_url: "http://localhost:3000"}
    auth.anonymous: {enabled: false}
    dashboards: {default_home_dashboard_path: "/var/lib/grafana/dashboards/default/grafana-k8s-cluster.json"}
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      searchNamespace: ALL
    datasources:
      enabled: true
      label: grafana_datasource
  resources:
    requests: {cpu: 100m, memory: 256Mi}
    limits:   {cpu: "1",   memory: 1Gi}
  persistence:
    enabled: true
    size: 5Gi

# ── Prometheus ──
prometheus:
  enabled: true
  prometheusSpec:
    replicas: 1
    retention: 7d                           # 10d default; local disk is small
    retentionSize: "4GB"
    scrapeInterval: 30s
    evaluationInterval: 30s
    resources:
      requests: {cpu: 250m, memory: 1Gi}
      limits:   {cpu: "1",   memory: 2Gi}
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources: {requests: {storage: 10Gi}}
    # discover ServiceMonitors/PodMonitors regardless of their labels (handy while learning)
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {}
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorSelector: {}
    probeSelectorNilUsesHelmValues: false
    probeSelector: {}
    ruleSelectorNilUsesHelmValues: false
    ruleSelector: {}
    # useful extra config
    additionalScrapeConfigs: []
  service:
    type: ClusterIP
    port: 9090

# ── Alertmanager ──
alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources: {requests: {storage: 2Gi}}
    resources:
      requests: {cpu: 50m, memory: 128Mi}

# ── exporters ──
nodeExporter: {enabled: true}
kubeStateMetrics: {enabled: true}
kubelet:
  enabled: true
  serviceMonitor:
    metricRelabelings: []
kubeApiServer: {enabled: true}
kubeControllerManager: {enabled: true}
kubeScheduler: {enabled: true}
kubeEtcd: {enabled: true}
kubeProxy: {enabled: true}

# ── bundled alerts; we'll add our own in §7.7 ──
defaultRules:
  create: true
  rules:
    alertmanager: true
    etcd: true
    configReloaders: true
    general: true
    k8sContainerCpuUsageSecondsTotal: true
    k8sContainerMemoryCache: true
    k8sContainerRss: true
    k8sContainerWss: true
    kubeApiserverAvailability: true
    kubeApiserverSlos: true
    kubelet: true
    kubeProxy: true
    kubernetesApps: true
    kubernetesResources: true
    kubernetesStorage: true
    kubernetesSystem: true
    kubeSchedulerAlerting: true
    kubeSchedulerRecording: true
    network: true
    node: true
    nodeExporterAlerting: true
    nodeExporterRecording: true
    prometheus: true
    prometheusOperator: true
```

```bash
helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f kps-values.yaml --timeout 10m

kubectl get pods -n monitoring -w
```

```
NAME                                                   READY   STATUS    AGE
alertmanager-kps-kube-prometheus-stack-alertmanager-0  2/2     Running   2m
kps-grafana-7d9f8b6c5d-x2k4j                           3/3     Running   2m
kps-kube-prometheus-stack-operator-6c5d4b3a2f-mn3p8    1/1     Running   2m
kps-kube-state-metrics-5b4c3d2e1f-qw7rt                1/1     Running   2m
prometheus-kps-kube-prometheus-stack-prometheus-0      2/2     Running   2m
```

> ⚠️ On **kind**, `kubeEtcd`/`kubeScheduler`/`kubeControllerManager` monitors often fail because the control-plane static pods don't expose metrics on the pod network. That produces harmless `target down` entries. Set those to `enabled: false` if the noise bothers you.

### Get in

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093 &
sleep 3
```

- **Grafana:** <http://localhost:3000> — `admin` / `learn-grafana`
- **Prometheus:** <http://localhost:9090>
- **Alertmanager:** <http://localhost:9093>

**Grafana dashboards to open first** (Dashboards → browse):

| Dashboard | What it shows |
|---|---|
| `Kubernetes / Compute Resources / Namespace (Pods)` | CPU/memory per Pod in a namespace |
| `Kubernetes / Compute Resources / Pod` | Per-container breakdown, **throttling** |
| `Kubernetes / Compute Resources / Cluster` | Cluster-wide capacity vs requests |
| `Node Exporter Full` | Every node metric imaginable |
| `Kubernetes / Networking / Pod` | Pod network throughput |
| `Kubernetes / Persistent Volumes` | PVC usage % |
| `Prometheus` | Prometheus's own health: scrape targets, TSDB size |

---

## 7.5 Step 4 — Scrape your own app

Three mechanisms. Pick based on what your app exposes.

### ServiceMonitor (the standard — you have a Service)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo
  namespace: monitoring              # or the app's namespace; must be selected by Prometheus
  labels:
    release: kps                     # ⭐ must match Prometheus's serviceMonitorSelector
spec:
  namespaceSelector:
    matchNames: [default]            # where the Service lives
  selector:
    matchLabels:
      app: demo                      # matches the SERVICE's labels
  endpoints:
    - port: http                     # ⭐ the Service PORT NAME, not the number
      path: /metrics
      interval: 15s
      scrapeTimeout: 10s
      honorLabels: true
      # basicAuth: {username: {name: metrics-creds, key: user}, password: {name: metrics-creds, key: pass}}
      # bearerTokenSecret: {name: metrics-token, key: token}
      # tlsConfig: {insecureSkipVerify: true}
      metricRelabelings:
        # drop high-cardinality metrics that will blow up your TSDB
        - sourceLabels: [__name__]
          regex: 'go_gc_.*'
          action: drop
        - sourceLabels: [__name__]
          regex: 'demo_http_requests_total'
          action: keep
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_node_name]
          targetLabel: node
```

```bash
kubectl apply -f servicemonitor.yaml

# did Prometheus pick it up?
kubectl -n monitoring exec prometheus-kps-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'localhost:9090/api/v1/targets?state=active' | jq -r '.data.activeTargets[] | "\(.health)\t\(.labels.job)"' | sort | uniq -c | sort -rn | head -20
```

Or in the browser: Prometheus UI → Status → Targets → search for `serviceMonitor/monitoring/demo/0`. It should be **UP**.

Then query it:

```promql
demo_http_requests_total
rate(demo_http_requests_total[1m])
sum by (status) (rate(demo_http_requests_total[1m]))
```

> 🔑 **The two most common ServiceMonitor mistakes:**
> 1. `spec.endpoints[].port` is the **Service port NAME**, not a number. If your Service has unnamed ports, name them.
> 2. The `release: kps` label must match the Prometheus CR's `serviceMonitorSelector`. If you set `serviceMonitorSelector: {}` in values (as above), any label works.

### PodMonitor (no Service)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata: {name: demo-pods, namespace: monitoring, labels: {release: kps}}
spec:
  namespaceSelector: {matchNames: [default]}
  selector: {matchLabels: {app: demo}}
  podMetricsEndpoints:
    - port: metrics
      path: /metrics
      interval: 15s
```

### Probe (scrape an external HTTP endpoint)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata: {name: external-sites, namespace: monitoring, labels: {release: kps}}
spec:
  interval: 60s
  module: http_2xx
  prober:
    url: blackbox-exporter.monitoring:9115
  targets:
    staticConfig:
      static:
        - https://kubernetes.io
        - https://prometheus.io
      labels: {kind: external}
```

### Annotation-based scraping (the "poor man's" way)

If your Prometheus has the annotation discovery job enabled:

```yaml
template:
  metadata:
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "8080"
      prometheus.io/path: "/metrics"
```

kube-prometheus-stack does **not** enable this by default (ServiceMonitors are preferred). It's fine for a quick test but gives you no relabeling control.

### Verify end to end

```bash
# 1. is the app actually serving metrics?
kubectl exec deploy/demo -- wget -qO- localhost:8080/metrics | head -5

# 2. is the Service named correctly?
kubectl get svc demo -o jsonpath='{.spec.ports[*].name}'; echo      # http

# 3. is the ServiceMonitor matched?
kubectl get servicemonitor -A
kubectl -n monitoring get prometheus -o jsonpath='{.items[0].spec.serviceMonitorSelector}'; echo

# 4. is the target UP?
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
sleep 2 && curl -s 'localhost:9090/api/v1/targets' | jq -r '.data.activeTargets[] | select(.labels.job|test("demo")) | "\(.health) \(.scrapeUrl) \(.lastError)"'
kill %1

# 5. is the data queryable?
curl -s 'localhost:9090/api/v1/query?query=demo_http_requests_total' | jq '.data.result | length'
```

---

## 7.6 Step 5 — The metrics that actually matter, and the PromQL to read them

### 7.6.1 CPU throttling — the silent performance killer

Exceeding `limits.cpu` doesn't kill your Pod; it **throttles** it. Latency spikes, and nothing looks wrong in `kubectl top`.

```promql
# throttling ratio per container — >0.25 sustained means your CPU limit is too low
sum by (namespace, pod, container) (
  rate(container_cpu_cfs_throttled_periods_total{namespace="default"}[5m])
)
/
sum by (namespace, pod, container) (
  rate(container_cpu_cfs_periods_total{namespace="default"}[5m])
) > 0.1
```

```promql
# actual CPU usage vs request vs limit
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="default",pod=~"demo.*"}[5m])) * 1000
kube_pod_container_resource_requests{namespace="default",resource="cpu",pod=~"demo.*"} * 1000
kube_pod_container_resource_limits{namespace="default",resource="cpu",pod=~"demo.*"} * 1000
```

Run this now — the demo app has a 250m limit under load, so you should see throttling:

```bash
curl -s 'localhost:9090/api/v1/query' --data-urlencode \
  'query=sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{pod=~"demo.*"}[5m])) / sum by (pod) (rate(container_cpu_cfs_periods_total{pod=~"demo.*"}[5m]))' | jq -r '.data.result[] | "\(.metric.pod): \(.value[1] | tonumber * 100 | round)%"'
```

Fix it and re-measure:

```bash
kubectl patch deploy demo --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"1"}]'
kubectl rollout status deploy/demo
```

### 7.6.2 Memory — what the OOM killer actually looks at

```promql
# working set = what cgroups/OOM use. NOT container_memory_usage_bytes (which includes cache)
container_memory_working_set_bytes{namespace="default",pod=~"demo.*"} / (1024*1024)

# usage as a fraction of the limit → alert at >0.9
container_memory_working_set_bytes{namespace="default"}
/ on(namespace, pod, container)
kube_pod_container_resource_limits{resource="memory"}

# RSS vs cache breakdown
container_memory_rss{pod=~"demo.*"}
container_memory_cache{pod=~"demo.*"}

# OOMKills in the last hour
increase(kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}[1h]) > 0
```

Watch the demo app's deliberate leak:

```bash
curl -s 'localhost:9090/api/v1/query' --data-urlencode 'query=demo_allocated_items' \
  | jq -r '.data.result[] | "\(.metric.pod): \(.value[1]) items"'
```

It grows forever. In ~30 minutes it'll be OOMKilled — and you'll see exit code 137 and `reason="OOMKilled"` in kube-state-metrics. That's a real memory-leak drill.

### 7.6.3 Latency — histograms done right

```promql
# p99 latency per pod, from a histogram
histogram_quantile(0.99,
  sum by (le, pod) (rate(demo_http_request_duration_seconds_bucket{namespace="default"}[5m]))
)

# p50 and p95 side by side
histogram_quantile(0.50, sum by (le) (rate(demo_http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.95, sum by (le) (rate(demo_http_request_duration_seconds_bucket[5m])))

# mean latency
rate(demo_http_request_duration_seconds_sum[5m]) / rate(demo_http_request_duration_seconds_count[5m])

# request rate (RPS)
sum(rate(demo_http_requests_total[1m]))

# error rate (%)
100 * sum(rate(demo_http_requests_total{status=~"5.."}[5m]))
    / sum(rate(demo_http_requests_total[5m]))
```

> 🔑 **Never average a histogram's `_sum/_count` for a p99.** Averages hide tails. Use `histogram_quantile` over `_bucket`. And never average p99s across pods — aggregate the *buckets* first, then compute the quantile:
> ```promql
> # WRONG
> avg(histogram_quantile(0.99, sum by (le,pod) (rate(x_bucket[5m]))))
> # RIGHT
> histogram_quantile(0.99, sum by (le) (rate(x_bucket[5m])))
> ```

### 7.6.4 Kubernetes object state (kube-state-metrics)

```promql
# pods not Running
kube_pod_status_phase{phase!~"Running|Succeeded"} == 1

# pods restarting
increase(kube_pod_container_status_restarts_total[10m]) > 3

# under-replicated deployments
kube_deployment_status_replicas_available < kube_deployment_spec_replicas

# pods stuck Pending > 5 min
kube_pod_status_phase{phase="Pending"} == 1
  and on(pod) (time() - kube_pod_created > 300)

# nodes NotReady
kube_node_status_condition{condition="Ready",status="true"} == 0

# PVCs nearly full
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85

# container waiting reasons — a goldmine
kube_pod_container_status_waiting_reason > 0

# who has no resource requests?
kube_pod_container_resource_requests{resource="cpu"} == 0

# HPA at max (can't scale further)
kube_horizontalpodautoscaler_status_current_replicas >= kube_horizontalpodautoscaler_spec_max_replicas
```

### 7.6.5 Node health (node-exporter)

```promql
# CPU utilisation per node
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# memory available
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# disk will fill in 4 hours (predictive!)
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[1h], 4*3600) < 0

# network saturation
rate(node_network_receive_bytes_total[5m]) * 8
rate(node_network_transmit_bytes_total[5m]) * 8

# file descriptor exhaustion
node_filefd_allocated / node_filefd_maximum * 100

# conntrack table filling (causes bizarre connection drops)
node_nf_conntrack_entries / node_nf_conntrack_entries_limit > 0.8
```

### 7.6.6 Control plane

```promql
# API server p99 latency
histogram_quantile(0.99, sum by (le,verb,resource) (rate(apiserver_request_duration_seconds_bucket{verb!~"WATCH|LIST"}[5m])))

# API server 5xx rate
sum(rate(apiserver_request_total{code=~"5.."}[5m])) / sum(rate(apiserver_request_total[5m]))

# etcd leader changes (should be ~0)
increase(etcd_server_leader_changes_seen_total[1h])

# etcd fsync latency — >10ms means slow disk
histogram_quantile(0.99, sum by (le) (rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])))

# scheduler latency
histogram_quantile(0.99, sum by (le) (rate(scheduler_e2e_scheduling_duration_seconds_bucket[5m])))

# workqueue depth (controllers falling behind)
workqueue_depth{namespace="kube-system"} > 100
```

### 7.6.7 The USE and RED methods

| | **USE** (resources) | **RED** (services) |
|---|---|---|
| U | **U**tilisation — `rate(container_cpu_usage_seconds_total)` | **R**ate — `rate(demo_http_requests_total[1m])` |
| S/E/R | **S**aturation — `container_cpu_cfs_throttled_periods_total`<br>**E**rrors — `kube_pod_container_status_restarts_total` | **E**rrors — `rate(requests_total{status=~"5.."})`<br>**D**uration — `histogram_quantile(0.99, …)` |
| Use for | Nodes, disks, memory, CPU | Every user-facing service |

**Your four golden dashboards:** RED per service, USE per node, Kubernetes object state, and one "on-call overview" with the alerts.

---

## 7.7 Step 6 — Alerting

### PrometheusRule (native)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: demo-app-rules
  namespace: monitoring
  labels: {release: kps}           # ⭐ must match Prometheus's ruleSelector
spec:
  groups:
    - name: demo-app.rules
      interval: 30s
      rules:
        # ── RECORDING RULES: pre-compute the expensive stuff ──
        - record: job:demo_http_requests:rate5m
          expr: sum by (job, version) (rate(demo_http_requests_total[5m]))
        - record: job:demo_http_error_ratio:rate5m
          expr: |
            sum by (job) (rate(demo_http_requests_total{status=~"5.."}[5m]))
            /
            sum by (job) (rate(demo_http_requests_total[5m]))
        - record: job:demo_http_latency_p99:rate5m
          expr: |
            histogram_quantile(0.99,
              sum by (job, le) (rate(demo_http_request_duration_seconds_bucket[5m])))

        # ── ALERTS ──
        - alert: DemoHighErrorRate
          expr: job:demo_http_error_ratio:rate5m > 0.05
          for: 5m
          labels: {severity: critical, team: shop}
          annotations:
            summary: "demo error rate is {{ $value | humanizePercentage }}"
            description: "Job {{ $labels.job }} has been returning >5% 5xx for 5 minutes."
            runbook_url: "https://wiki.internal/runbooks/demo-errors"
            dashboard: "http://grafana:3000/d/demo/demo-app"

        - alert: DemoHighLatency
          expr: job:demo_http_latency_p99:rate5m > 1
          for: 10m
          labels: {severity: warning}
          annotations:
            summary: "demo p99 latency {{ $value | humanizeDuration }}"

        - alert: DemoPodCrashLooping
          expr: |
            increase(kube_pod_container_status_restarts_total{pod=~"demo.*"}[10m]) > 3
          for: 0m
          labels: {severity: critical}
          annotations:
            summary: "{{ $labels.pod }} restarted {{ $value }} times in 10m"
            description: "Run: kubectl logs {{ $labels.pod }} --previous"

        - alert: DemoPodNotReady
          expr: |
            sum by (pod) (kube_pod_status_ready{condition="true", pod=~"demo.*"} == 0)
          for: 5m
          labels: {severity: warning}
          annotations:
            summary: "{{ $labels.pod }} has been not-ready for 5m"

        - alert: ContainerOOMKilled
          expr: |
            increase(kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}[15m]) > 0
          labels: {severity: critical}
          annotations:
            summary: "{{ $labels.pod }}/{{ $labels.container }} was OOMKilled"
            description: "Raise limits.memory or fix the leak. Check demo_allocated_items."

        - alert: ContainerCpuThrottlingHigh
          expr: |
            sum by (namespace, pod, container) (rate(container_cpu_cfs_throttled_periods_total[5m]))
            /
            sum by (namespace, pod, container) (rate(container_cpu_cfs_periods_total[5m]))
            > 0.5
          for: 15m
          labels: {severity: warning}
          annotations:
            summary: "{{ $labels.pod }}/{{ $labels.container }} throttled {{ $value | humanizePercentage }}"

        - alert: DeploymentUnderReplicated
          expr: |
            kube_deployment_status_replicas_available < kube_deployment_spec_replicas
          for: 10m
          labels: {severity: critical}
          annotations:
            summary: "{{ $labels.deployment }} has {{ $value }} available, wants {{ with query \"kube_deployment_spec_replicas\" }}{{ . | first | value }}{{ end }}"

        - alert: NodeNotReady
          expr: kube_node_status_condition{condition="Ready",status="true"} == 0
          for: 2m
          labels: {severity: critical}
          annotations:
            summary: "Node {{ $labels.node }} is NotReady"

        - alert: PVCNearlyFull
          expr: |
            kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85
          for: 10m
          labels: {severity: warning}
          annotations:
            summary: "{{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is {{ $value | humanizePercentage }} full"

        - alert: HPAAtMaxReplicas
          expr: |
            kube_horizontalpodautoscaler_status_current_replicas
            >= kube_horizontalpodautoscaler_spec_max_replicas
          for: 15m
          labels: {severity: warning}
          annotations:
            summary: "{{ $labels.horizontalpodautoscaler }} is pinned at max replicas"

        - alert: CertExpiresIn14Days
          expr: |
            (probe_ssl_earliest_cert_expiry - time()) / 86400 < 14
          labels: {severity: warning}
          annotations:
            summary: "TLS cert for {{ $labels.instance }} expires in {{ $value }} days"
```

```bash
kubectl apply -f prometheusrule.yaml
kubectl -n monitoring get prometheusrule
kubectl -n monitoring describe prometheusrule demo-app-rules | head -40

# are the rules loaded?
curl -s 'localhost:9090/api/v1/rules' | jq -r '.data.groups[].rules[] | select(.type=="alerting") | "\(.state)\t\(.name)"' | sort | uniq -c
```

### Alertmanager routing

```yaml
# alertmanager-config.yaml — merge into the AlertmanagerConfig CRD or the helm values
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: demo-routing
  namespace: monitoring
  labels: {release: kps}
spec:
  route:
    receiver: slack-shop
    groupBy: ['alertname', 'namespace']
    groupWait: 30s
    groupInterval: 5m
    repeatInterval: 4h
    routes:
      - matchers: [{name: severity, value: critical}]
        receiver: pagerduty-oncall
        repeatInterval: 1h
        continue: true                    # also notify slack
      - matchers: [{name: severity, value: warning}]
        receiver: slack-shop
        repeatInterval: 12h
      - matchers: [{name: team, value: shop}]
        receiver: slack-shop
  receivers:
    - name: slack-shop
      slackConfigs:
        - apiURL:
            name: slack-webhook
            key: url
          channel: '#shop-alerts'
          sendResolved: true
          title: '{{ .CommonLabels.alertname }} [{{ .CommonLabels.severity }}]'
          text: |-
            {{ range .Alerts }}
            *{{ .Annotations.summary }}*
            {{ .Annotations.description }}
            {{ if .Annotations.runbook_url }}Runbook: {{ .Annotations.runbook_url }}{{ end }}
            {{ end }}
    - name: pagerduty-oncall
      pagerdutyConfigs:
        - routingKey:
            name: pagerduty-key
            key: key
          severity: critical
  inhibitRules:
    # if a node is NotReady, silence the pod-level alerts on that node
    - sourceMatch: {alertname: NodeNotReady}
      targetMatchRe: {alertname: 'DemoPod.*'}
      equal: ['node']
```

The plain-YAML version (`alertmanager.yaml`) for reference — this is what you'd write if not using the Operator:

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/T000/B000/XXXX'

route:
  receiver: slack-shop
  group_by: ['alertname', 'namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers: [severity="critical"]
      receiver: pagerduty-oncall
      repeat_interval: 1h
      continue: true

receivers:
  - name: slack-shop
    slack_configs:
      - channel: '#shop-alerts'
        send_resolved: true
        title: '{{ .CommonLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
  - name: pagerduty-oncall
    pagerduty_configs:
      - service_key: '<from a secret>'

inhibit_rules:
  - source_matchers: [severity="critical"]
    target_matchers: [severity="warning"]
    equal: ['alertname', 'namespace']
```

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093 &
sleep 2
curl -s localhost:9093/api/v2/alerts | jq -r '.[] | "\(.status.state)\t\(.labels.alertname)\t\(.labels.severity)"'
curl -s localhost:9093/api/v2/status | jq -r '.config.original' | head -40
kill %1
```

### Test an alert end to end

```bash
# trigger high error rate by dialing FAIL_RATE up
kubectl set env deploy/demo FAIL_RATE=0.9
kubectl rollout status deploy/demo

# wait ~5 min, then:
curl -s 'localhost:9090/api/v1/alerts' | jq -r '.data.alerts[] | "\(.state)\t\(.labels.alertname)"'
curl -s localhost:9093/api/v2/alerts | jq -r '.[] | "\(.status.state)\t\(.labels.alertname)"'

# and a test alert straight into Alertmanager
curl -s -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {"alertname":"TestAlert","severity":"critical","namespace":"default"},
  "annotations": {"summary":"This is a test","description":"If you got this in Slack, routing works"},
  "startsAt": "'"$(date -u +%FT%TZ)"'",
  "generatorURL": "http://prometheus:9090"
}]'

# put it back
kubectl set env deploy/demo FAIL_RATE=0.05
```

### Alert design rules (learn these the hard way or here)

1. **Alert on symptoms, not causes.** "Users see errors" pages someone. "CPU is 80%" doesn't — it's a dashboard item.
2. **Every alert must be actionable.** If nobody would do anything, delete it.
3. **Every page needs a runbook link.** `runbook_url` in the annotation, always.
4. **Use `for:` to kill flapping.** A 30-second blip shouldn't page at 3am.
5. **Two severity levels is enough:** `critical` = page now, `warning` = ticket/business hours.
6. **Inhibit cascades.** One dead node shouldn't produce 40 pages.
7. **`repeat_interval` matters more than you think.** 4 h for critical, 12–24 h for warnings.
8. **Alert on SLO burn rate, not raw thresholds** once you have SLOs:
   ```promql
   # multi-window multi-burn-rate (Google SRE Workbook)
   (
     job:demo_http_error_ratio:rate1h{job="demo"} > (14.4 * 0.001)
     and
     job:demo_http_error_ratio:rate5m{job="demo"} > (14.4 * 0.001)
   )
   ```

---

## 7.8 Step 7 — Logging

### 7.8.1 `kubectl logs` mastery

```bash
kubectl logs deploy/demo                              # any pod of the deployment
kubectl logs -l app=demo --prefix --tail=20            # ALL pods, labelled
kubectl logs -l app=demo --all-containers -f           # follow everything
kubectl logs pod/demo-abc -c demo                      # specific container
kubectl logs pod/demo-abc --previous                   # ⭐ the crashed instance
kubectl logs pod/demo-abc --since=10m --timestamps
kubectl logs pod/demo-abc --since-time=2026-09-09T10:00:00Z
kubectl logs pod/demo-abc --limit-bytes=1048576        # cap the output
kubectl logs job/migrate
kubectl logs -f -l job-name=migrate --max-log-requests=20
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=100 | jq -c 'select(.status>=500)'
```

**stern** — the multi-pod tail that should be your default:

```bash
brew install stern
stern demo                                  # all pods matching "demo"
stern demo -n default --tail 50 --since 5m
stern . -n prod                             # EVERYTHING in a namespace
stern --exclude-container istio-proxy demo
stern -l app=demo --output json | jq .
stern demo --template '{{.PodName}} {{.Message}}'
stern 'demo-[a-z0-9]+' --color always
```

### 7.8.2 Where logs live on the node

```bash
kubectl debug node/learn-worker -it --image=busybox:1.37
```

```sh
# inside (host is at /host)
ls -la /host/var/log/containers/
# demo-abc123_default_demo-9f8e7d.log -> /host/var/log/pods/default_demo-abc123_<uid>/demo/0.log

ls -la /host/var/log/pods/default_demo-abc123_*/demo/
# 0.log   1.log   2.log        ← one file per container RESTART

cat /host/var/log/pods/default_demo-abc123_*/demo/0.log
# 2026-09-09T12:00:01.123456789Z stdout F demo app 1.0.0 starting on :8080

df -h /host/var/lib/containerd /host/var/log
du -sh /host/var/log/pods/* | sort -h | tail -10
```

> 🔑 **`1.log`, `2.log` …** are previous container instances — the same data `--previous` gives you, but all of them.

### 7.8.3 Log rotation (why the node doesn't fill up)

kubelet rotates container logs:

```
--container-log-max-files=5        (default 5)
--container-log-max-size=10Mi      (default 10Mi)
```

Change them in the KubeletConfiguration:

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
containerLogMaxSize: "50Mi"
containerLogMaxFiles: 10
evictionHard:
  nodefs.available: "10%"
  imagefs.available: "15%"
  memory.available: "100Mi"
systemReserved: {cpu: "500m", memory: "1Gi"}
kubeReserved:   {cpu: "500m", memory: "1Gi"}
```

If a Pod logs 1 GB/min and rotation is 5×10 Mi, **you lose history fast** — which is exactly why you ship logs off-node.

### 7.8.4 Loki — the log aggregation stack

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki -n logging --create-namespace -f - <<'EOF'
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
  limits_config:
    retention_period: 168h          # 7 days
    max_query_series: 5000
    ingestion_rate_mb: 8
    ingestion_burst_size_mb: 16
  compactor:
    working_directory: /var/loki/compactor
    retention_enabled: true
    delete_request_store: filesystem

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 20Gi
  resources:
    requests: {cpu: 200m, memory: 512Mi}
    limits:   {cpu: "1",   memory: 2Gi}

chunksCache:
  enabled: true
  allocatedMemory: 512

gateway:
  enabled: true
  replicas: 1

# ── the log collector ──
alloy:
  enabled: true                       # Grafana Alloy replaced Promtail in 2025
  alloy:
    config: |
      discovery.kubernetes "pods" { role = "pod" }
      local.file_match "logs" {
        path_targets = discovery.kubernetes.pods.targets
      }
      loki.source.file "pods" {
        targets    = local.file_match.logs.targets
        forward_to = [loki.process.pods.receiver]
      }
      loki.process "pods" {
        stage.docker {}
        forward_to = [loki.write.local.receiver]
      }
      loki.write "local" {
        endpoint { url = "http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push" }
      }

# if you prefer the classic Promtail DaemonSet:
promtail:
  enabled: false

grafana:
  enabled: false                      # reuse the kube-prometheus-stack Grafana
EOF

kubectl get pods -n logging
```

Add Loki as a Grafana datasource:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-loki
  namespace: monitoring
  labels:
    grafana_datasource: "1"        # ⭐ the grafana sidecar watches this label
data:
  loki.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki-gateway.logging.svc.cluster.local
        isDefault: false
        jsonData:
          maxLines: 1000
          derivedFields:
            - datasourceUid: prometheus
              matcherRegex: '"pod":"([^"]+)"'
              name: PodMetrics
              url: '${__value.raw}'
EOF
```

### 7.8.5 LogQL — the queries you need

```logql
# everything from the demo app
{app="demo"}

# just errors
{app="demo"} |= "ERROR"
{app="demo"} |~ "(?i)error|exception|traceback"

# exclude noise
{namespace="prod"} != "healthcheck" |~ "5[0-9]{2}"

# parse structured logs into labels
{app="demo"} | json | status >= 500 | line_format "{{.msg}}"

# rate of 5xx per pod
sum by (pod) (rate({app="demo"} | json | status =~ "5.." [5m]))

# top error messages over an hour
topk(10, sum by (msg) (count_over_time({app="demo"} |= "ERROR" [1h])))

# extract a latency field and get the p99
quantile_over_time(0.99, {app="demo"} | json | unwrap duration_ms [5m]) by (pod)

# which pod logged the most in the last hour
topk(5, sum by (pod) (count_over_time({namespace="default"}[1h])))

# follow a specific pod
{app="demo", pod=~"demo-7d9f8b.*"} | logfmt
```

```bash
# query from the CLI
kubectl port-forward -n logging svc/loki-gateway 3100:80 &
sleep 2
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={app="demo"} |= "ERROR"' \
  --data-urlencode "start=$(date -u -d '-1 hour' +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000" \
  --data-urlencode 'limit=20' | jq -r '.data.result[].values[][1]'
kill %1
```

### 7.8.6 Structured logging — do this from day one

Unstructured:
```
2026-09-09 12:00:01 ERROR something went wrong
```

Structured (JSON):
```json
{"ts":"2026-09-09T12:00:01Z","level":"error","msg":"db query failed","service":"api","version":"1.4.2","pod":"api-7d9f-x2k","trace_id":"4bf92f3577b34da6","latency_ms":1203,"error":"connection refused"}
```

Why: `{app="api"} | json | level="error" | latency_ms > 1000` is possible. Grep isn't.

```python
# Python — structlog or plain logging with a JSON formatter
import json, logging, os, time

class JsonFormatter(logging.Formatter):
    def format(self, record):
        d = {
            "ts": time.strftime("%FT%TZ", time.gmtime(record.created)),
            "level": record.levelname.lower(),
            "msg": record.getMessage(),
            "logger": record.name,
            "service": os.environ.get("SERVICE", "api"),
            "version": os.environ.get("VERSION", "dev"),
            "pod": os.environ.get("HOSTNAME", "local"),
            "namespace": os.environ.get("POD_NAMESPACE", "local"),
        }
        if record.exc_info:
            d["exception"] = self.formatException(record.exc_info)
        for k, v in getattr(record, "extra_fields", {}).items():
            d[k] = v
        return json.dumps(d, default=str)

h = logging.StreamHandler(); h.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[h])
```

```go
// Go — log/slog (stdlib since 1.21)
slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})))
slog.Info("request served", "method", r.Method, "path", r.URL.Path, "latency_ms", ms, "status", code, "trace_id", tid)
```

```java
// Java — logstash-logback-encoder
// <dependency>net.logstash.logback:logstash-logback-encoder:7.4</dependency>
```

**Rules:**
- Log to **stdout/stderr**, never to files. Kubernetes collects stdout.
- One JSON object per line. No multi-line stack traces if you can avoid them (or use Loki's `multiline` stage).
- Include `trace_id` in every log line — that's what makes traces and logs join.
- **Never log secrets.** Add a scrubber and a CI check.
- Set the level from an env var (`LOG_LEVEL`) so you can turn on debug without redeploying.

---

## 7.9 Step 8 — Build an on-call dashboard

Grafana → Dashboards → New → Import → paste this JSON.

`dashboard.json` (a focused, useful starting point):

```json
{
  "annotations": {"list": []},
  "editable": true,
  "graphTooltip": 1,
  "refresh": "30s",
  "schemaVersion": 39,
  "tags": ["kubernetes", "on-call"],
  "time": {"from": "now-1h", "to": "now"},
  "title": "☸️ On-Call Overview",
  "uid": "oncall-overview",
  "templating": {
    "list": [
      {
        "name": "namespace",
        "type": "query",
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "query": "label_values(kube_namespace_created, namespace)",
        "refresh": 2,
        "includeAll": true,
        "multi": true
      }
    ]
  },
  "panels": [
    {
      "type": "stat",
      "title": "Nodes NotReady",
      "gridPos": {"h": 4, "w": 4, "x": 0, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "count(kube_node_status_condition{condition=\"Ready\",status=\"true\"} == 0) or vector(0)", "refId": "A"}],
      "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}},
      "options": {"colorMode": "background", "graphMode": "none"}
    },
    {
      "type": "stat",
      "title": "Pods Not Running",
      "gridPos": {"h": 4, "w": 4, "x": 4, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "count(kube_pod_status_phase{namespace=~\"$namespace\",phase!~\"Running|Succeeded\"} == 1) or vector(0)", "refId": "A"}],
      "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 1}, {"color": "red", "value": 5}]}}},
      "options": {"colorMode": "background"}
    },
    {
      "type": "stat",
      "title": "Restarts (1h)",
      "gridPos": {"h": 4, "w": 4, "x": 8, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "sum(increase(kube_pod_container_status_restarts_total{namespace=~\"$namespace\"}[1h])) or vector(0)", "refId": "A"}],
      "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 10}, {"color": "red", "value": 50}]}}},
      "options": {"colorMode": "background"}
    },
    {
      "type": "stat",
      "title": "OOMKilled (1h)",
      "gridPos": {"h": 4, "w": 4, "x": 12, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "sum(increase(kube_pod_container_status_last_terminated_reason{namespace=~\"$namespace\",reason=\"OOMKilled\"}[1h])) or vector(0)", "refId": "A"}],
      "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}},
      "options": {"colorMode": "background"}
    },
    {
      "type": "stat",
      "title": "Firing Alerts",
      "gridPos": {"h": 4, "w": 4, "x": 16, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "count(ALERTS{alertstate=\"firing\"}) or vector(0)", "refId": "A"}],
      "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "orange", "value": 1}, {"color": "red", "value": 5}]}}},
      "options": {"colorMode": "background"}
    },
    {
      "type": "timeseries",
      "title": "Request rate by status",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "sum by (status) (rate(demo_http_requests_total{namespace=~\"$namespace\"}[5m]))", "legendFormat": "{{status}}", "refId": "A"}]
    },
    {
      "type": "timeseries",
      "title": "Latency percentiles",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [
        {"expr": "histogram_quantile(0.50, sum by (le) (rate(demo_http_request_duration_seconds_bucket{namespace=~\"$namespace\"}[5m])))", "legendFormat": "p50", "refId": "A"},
        {"expr": "histogram_quantile(0.95, sum by (le) (rate(demo_http_request_duration_seconds_bucket{namespace=~\"$namespace\"}[5m])))", "legendFormat": "p95", "refId": "B"},
        {"expr": "histogram_quantile(0.99, sum by (le) (rate(demo_http_request_duration_seconds_bucket{namespace=~\"$namespace\"}[5m])))", "legendFormat": "p99", "refId": "C"}
      ],
      "fieldConfig": {"defaults": {"unit": "s"}}
    },
    {
      "type": "timeseries",
      "title": "CPU usage vs limit (throttling risk)",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [
        {"expr": "sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=~\"$namespace\",pod=~\"demo.*\"}[5m])) * 1000", "legendFormat": "usage {{pod}}", "refId": "A"},
        {"expr": "sum by (pod) (kube_pod_container_resource_limits{namespace=~\"$namespace\",resource=\"cpu\",pod=~\"demo.*\"}) * 1000", "legendFormat": "limit {{pod}}", "refId": "B"}
      ],
      "fieldConfig": {"defaults": {"unit": "m"}}
    },
    {
      "type": "timeseries",
      "title": "CPU throttling ratio",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 12},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace=~\"$namespace\",pod=~\"demo.*\"}[5m])) / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace=~\"$namespace\",pod=~\"demo.*\"}[5m]))", "legendFormat": "{{pod}}", "refId": "A"}],
      "fieldConfig": {"defaults": {"unit": "percentunit", "max": 1}}
    },
    {
      "type": "timeseries",
      "title": "Memory working set vs limit",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 20},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [
        {"expr": "container_memory_working_set_bytes{namespace=~\"$namespace\",pod=~\"demo.*\"}", "legendFormat": "{{pod}}", "refId": "A"},
        {"expr": "kube_pod_container_resource_limits{namespace=~\"$namespace\",resource=\"memory\",pod=~\"demo.*\"}", "legendFormat": "limit {{pod}}", "refId": "B"}
      ],
      "fieldConfig": {"defaults": {"unit": "bytes"}}
    },
    {
      "type": "table",
      "title": "Pods with problems",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 20},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"expr": "kube_pod_container_status_waiting_reason{namespace=~\"$namespace\"} > 0", "format": "table", "instant": true, "refId": "A"}],
      "transformations": [{"id": "organize", "options": {"excludeByName": {"Time": true, "Value": true, "__name__": true, "job": true, "instance": true}}}]
    }
  ]
}
```

```bash
# import via the API
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
sleep 2
curl -s -u admin:learn-grafana -XPOST http://localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d "{\"dashboard\": $(cat dashboard.json | jq -c '. + {id: null}"), \"overwrite\": true}" | jq .
kill %1
```

Or: Grafana UI → Dashboards → New → Import → paste the JSON.

**Other dashboards worth importing** (Grafana → Import → enter ID):

| ID | Name |
|---|---|
| 315 | Kubernetes cluster monitoring |
| 6417 | Kubernetes / Pods |
| 13105 | Kubernetes / Views / Namespaces |
| 1860 | Node Exporter Full |
| 12740 | Kubernetes / Compute Resources / Cluster |
| 7587 | Kubernetes Deployment Statefulset Daemonset metrics |
| 13946 | ingress-nginx (the official one) |
| 3662 | Prometheus 2.0 Overview |
| 14055 | Loki / Log storage |

---

## 7.10 Step 9 — Tracing, in 5 minutes

Metrics tell you *that* it's slow. Traces tell you *where*.

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install otel open-telemetry/opentelemetry-collector -n tracing --create-namespace -f - <<'EOF'
mode: deployment
config:
  receivers:
    otlp:
      protocols: {grpc: {endpoint: 0.0.0.0:4317}, http: {endpoint: 0.0.0.0:4318}}
  exporters:
    debug: {verbosity: basic}
    otlp/jaeger:
      endpoint: jaeger-collector.tracing:4317
      tls: {insecure: true}
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [debug, otlp/jaeger]
EOF

helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm install jaeger jaegertracing/jaeger -n tracing --set provisionDataStore.cassandra=false --set allInOne.enabled=true
kubectl port-forward -n tracing svc/jaeger-query 16686:16686
# http://localhost:16686
```

Instrument your app with OpenTelemetry:

```python
pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp \
            opentelemetry-instrumentation-logging
```

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

trace.set_tracer_provider(TracerProvider(resource=Resource.create({
    "service.name": os.environ.get("SERVICE", "api"),
    "service.version": VERSION,
    "k8s.pod.name": HOST,
    "k8s.namespace.name": os.environ.get("POD_NAMESPACE", "default"),
})))
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT",
                                     "http://otel-collector.tracing:4317"), insecure=True)))
tracer = trace.get_tracer(__name__)

# then in the handler:
with tracer.start_as_current_span("GET /", attributes={"http.route": "/"}) as span:
    span.set_attribute("http.status_code", status)
    span.set_attribute("enduser.tier", tier)
```

Or, with zero code changes, use the **OpenTelemetry Operator's auto-instrumentation**:

```bash
helm install otel-operator open-telemetry/opentelemetry-operator -n opentelemetry --create-namespace
kubectl apply -f - <<'EOF'
apiVersion: opentelemetry.io/v1beta1
kind: Instrumentation
metadata: {name: auto, namespace: default}
spec:
  exporter: {endpoint: http://otel-collector.tracing:4317}
  propagators: [tracecontext, baggage]
  sampler: {type: parentbased_traceidratio, argument: "0.1"}
  python: {image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:latest}
  env: [{name: OTEL_TRACES_EXPORTER, value: otlp}]
EOF
# then annotate the Deployment:
kubectl patch deploy demo --type=merge -p '{"spec":{"template":{"metadata":{"annotations":{
  "instrumentation.opentelemetry.io/inject-python": "default/auto"}}}}}'
kubectl rollout status deploy/demo
```

The operator injects an init container that copies the OTel SDK in and sets `PYTHONPATH` + `OTEL_*` env vars. **Zero code changes.** Same trick exists for Java, Node.js, .NET and Go.

---

## 7.11 Extra Tasks

### Task 7.1 — Diagnose a slow app with only metrics

"Users say the checkout API is slow." No error logs, nothing crashing. Find the cause.

<details>
<summary>Show answer</summary>

The systematic ladder. Each step narrows it; stop as soon as one is conclusive.

```bash
NS=prod; APP=checkout
```

**Step 1 — Is it slow, or is it failing?**

```promql
# latency percentiles, 1h
histogram_quantile(0.50, sum by (le) (rate(http_request_duration_seconds_bucket{job="checkout"}[5m])))
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="checkout"}[5m])))
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{job="checkout"}[5m])))
```

| Pattern | Meaning |
|---|---|
| p50, p95, p99 all up | Uniformly slow → CPU throttling, dependency slow, saturation |
| p50 fine, p99 spiked | Tail latency → GC pauses, one bad Pod, lock contention, cold cache |
| Latency up AND error rate up | Failing fast/slow, dependency down |
| Latency up, request rate down | Something upstream is backing off (client timeouts!) |

**Step 2 — CPU throttling (the #1 hidden cause)**

```promql
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{pod=~"checkout.*"}[5m]))
/
sum by (pod) (rate(container_cpu_cfs_periods_total{pod=~"checkout.*"}[5m]))
```

`> 0.25` → **you are being throttled**. The container hit its CPU limit and got frozen for the rest of each 100 ms CFS period. Fix:

```bash
kubectl get deploy checkout -o jsonpath='{.spec.template.spec.containers[0].resources}'; echo
kubectl patch deploy checkout --type=json -p='[{"op":"remove","path":"/spec/template/spec/containers/0/resources/limits/cpu"}]'
# or raise it: {"op":"replace","path":".../limits/cpu","value":"2"}
```

**Step 3 — Memory pressure / GC**

```promql
container_memory_working_set_bytes{pod=~"checkout.*"} / on(pod) kube_pod_container_resource_limits{resource="memory",pod=~"checkout.*"}
increase(kube_pod_container_status_restarts_total{pod=~"checkout.*"}[1h])
```

`> 0.9` → close to OOM. For a JVM, high heap occupancy means long GC pauses → p99 spikes:

```promql
rate(jvm_gc_pause_seconds_sum[5m]) / rate(jvm_gc_pause_seconds_count[5m])   # avg GC pause
jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}
```

**Step 4 — Saturation: are we at capacity?**

```promql
# in-flight vs capacity
demo_inflight_requests{pod=~"checkout.*"}
# queue depth (if you expose it)
sum by (queue) (queue_depth)
# HPA pinned at max?
kube_horizontalpodautoscaler_status_current_replicas{horizontalpodautoscaler="checkout"}
  >= kube_horizontalpodautoscaler_spec_max_replicas{horizontalpodautoscaler="checkout"}
# node pressure
kube_node_status_condition{condition="Ready",status="true"} == 0
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

If the HPA is pinned, it can't scale → requests queue → latency grows. Raise `maxReplicas`.

**Step 5 — Is it a dependency?**

```promql
# outbound call latency, if instrumented
histogram_quantile(0.99, sum by (le, target) (rate(http_client_duration_seconds_bucket{job="checkout"}[5m])))
# database
pg_stat_activity_count{state="active"}
pg_stat_database_deadlocks
redis_commands_duration_seconds_total
# connection pool exhaustion — the classic
hikaricp_connections_pending > 0
hikaricp_connections_active / hikaricp_connections_max
```

Pool exhaustion produces exactly this symptom: p50 fine, p99 enormous, no errors. Threads wait for a connection.

**Step 6 — One bad Pod?**

```promql
# per-pod latency spread
histogram_quantile(0.99, sum by (le, pod) (rate(http_request_duration_seconds_bucket{job="checkout"}[5m])))
```

If one Pod is 10× the others: bad node, noisy neighbour, stuck GC, or a stale cache. Test:

```bash
kubectl get pods -l app=checkout -o wide          # same node?
kubectl describe node <that-node> | grep -A5 Conditions
kubectl delete pod <the-slow-one>                  # does the replacement behave?
```

**Step 7 — Kernel-level weirdness**

```promql
node_nf_conntrack_entries / node_nf_conntrack_entries_limit > 0.8     # conntrack full → dropped conns
node_sockstat_TCP_tw                                                   # TIME_WAIT explosion
rate(node_netstat_Tcp_RetransSegs[5m]) / rate(node_netstat_Tcp_OutSegs[5m])   # retransmit ratio > 1% = network trouble
node_disk_io_time_weighted_seconds_total                               # disk saturation
```

**Step 8 — DNS**

```promql
# CoreDNS latency
histogram_quantile(0.99, sum by (le) (rate(coredns_dns_request_duration_seconds_bucket[5m])))
```

A 5-second-per-request stall with `ndots:5` and external hostnames is a *very* common "slow app" that has nothing to do with the app. Fix with FQDNs (`api.vendor.com.`) or `dnsConfig.options: [{name: ndots, value: "2"}]`.

**Step 9 — Reproduce with a trace**

```bash
# find a slow request in Grafana/Loki, grab its trace_id, open it in Jaeger
{app="checkout"} | json | duration_ms > 2000 | line_format "{{.trace_id}}"
```

A trace shows the span breakdown: 1.8 s in `SELECT … FROM inventory` → it was the database, all along.

**Summary table — what to look at first, in order:**

| Rank | Cause | Metric | Share of "slow app" tickets |
|---|---|---|---|
| 1 | CPU throttling | `container_cpu_cfs_throttled_periods_total` | ~30% |
| 2 | Dependency latency | client-side duration histogram | ~25% |
| 3 | Connection pool exhaustion | `hikaricp_connections_pending` | ~15% |
| 4 | GC / memory pressure | `jvm_gc_pause_seconds`, working set | ~10% |
| 5 | Saturation (HPA at max) | `kube_horizontalpodautoscaler_status_current_replicas` | ~10% |
| 6 | DNS (ndots, conntrack) | `coredns_dns_request_duration_seconds` | ~5% |
| 7 | One bad node/Pod | per-pod latency spread | ~5% |

</details>

---

### Task 7.2 — Find what's eating your cluster's resources

`kubectl top nodes` shows 95% CPU on every node. Find the culprit and fix it properly.

<details>
<summary>Show answer</summary>

```bash
# ── 1. Node level: is it CPU, memory, disk, or PID pressure? ──
kubectl get nodes
kubectl describe node learn-worker | sed -n '/Conditions:/,/Addresses:/p'
kubectl top nodes
kubectl top pods -A --sort-by=cpu | head -20
kubectl top pods -A --sort-by=memory | head -20
```

**Critical distinction:** `kubectl top` shows **actual usage**. The scheduler cares about **requests**. A node can be at 20% CPU usage and still refuse to schedule anything, because requests are exhausted.

```bash
kubectl describe node learn-worker | sed -n '/Allocated resources/,/Events/p'
```

```
Allocated resources:
  Resource           Requests      Limits
  cpu                3850m (96%)   9200m (230%)
  memory             6200Mi (78%)  14Gi (179%)
  ephemeral-storage  0             0
Events:              <none>
```

**96% of CPU is REQUESTED.** That's why nothing schedules. Two different problems, two different fixes.

```bash
# ── 2. Per-namespace attribution ──
kubectl get pods -A -o json | jq -r '
  .items[] | .metadata.namespace as $ns | .spec.containers[] |
  "\($ns)\t\(.resources.requests.cpu // "none")\t\(.resources.limits.cpu // "none")\t\(.image)"' \
  | sort | column -t

# ── 3. Aggregate requests by namespace ──
kubectl describe nodes | grep -A5 "Allocated resources"
kubectl top pods -A --containers --sort-by=cpu | awk 'NR>1{sum[$1]+=$3} END{for(n in sum) print n, sum[n]"m"}' | sort -k2 -rn

# ── 4. Find the real hogs with PromQL (much better) ──
```

```promql
# actual CPU by namespace, top 10
topk(10, sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m])))

# actual memory by namespace
topk(10, sum by (namespace) (container_memory_working_set_bytes{container!=""}))

# REQUESTED cpu by namespace (what blocks scheduling)
topk(10, sum by (namespace) (kube_pod_container_resource_requests{resource="cpu"}))

# pods requesting far more than they use → right-size these first
sum by (namespace, pod) (kube_pod_container_resource_requests{resource="cpu"})
/
sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
> 10

# BestEffort pods (no requests at all) — they get evicted first AND destabilise scheduling
kube_pod_container_resource_requests{resource="cpu"} == 0
```

**The fix ladder, in order of leverage:**

```bash
# A. Right-size over-requesting workloads (biggest win, zero risk)
kubectl get deploy -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CPU_REQ:.spec.template.spec.containers[0].resources.requests.cpu,CPU_LIM:.spec.template.spec.containers[0].resources.limits.cpu,MEM_REQ:.spec.template.spec.containers[0].resources.requests.memory'
# for each wildly-over-requesting app:
kubectl patch deploy <name> -n <ns> --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"200m"}]'

# B. Kill runaway/debug workloads someone forgot
kubectl get pods -A --sort-by=.metadata.creationTimestamp | head -20      # ancient pods
kubectl get pods -A -l 'purpose in (test,debug,load)' -o wide
kubectl delete ns harish-scratch --wait=false

# C. Add quotas so this can't happen again
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata: {name: team-quota, namespace: dev}
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    pods: "50"
---
apiVersion: v1
kind: LimitRange
metadata: {name: defaults, namespace: dev}
spec:
  limits:
    - type: Container
      default: {cpu: 500m, memory: 512Mi}
      defaultRequest: {cpu: 100m, memory: 128Mi}
      max: {cpu: "4", memory: 8Gi}
EOF

# D. Use VPA in recommendation mode to get the right numbers automatically
kubectl apply -f - <<'EOF'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: {name: demo, namespace: default}
spec:
  targetRef: {apiVersion: apps/v1, kind: Deployment, name: demo}
  updatePolicy: {updateMode: "Off"}       # ⭐ recommend only, don't touch pods
EOF
sleep 3600
kubectl get vpa demo -o jsonpath='{.status.recommendation}'; echo | jq .
# {"containerRecommendations":[{"containerName":"demo","lowerBound":{"cpu":"85m","memory":"140Mi"},
#   "target":{"cpu":"120m","memory":"180Mi"},"upperBound":{"cpu":"900m","memory":"1300Mi"}}]}

# E. Descheduler — evict over-committed / badly-placed pods so they reschedule sanely
helm install descheduler descheduler/descheduler -n kube-system -f descheduler-values.yaml

# F. Node autoscaling, if you're genuinely out of capacity
#    EKS: Karpenter / Cluster Autoscaler. GKE: node auto-provisioning.
kubectl get pods -A --field-selector status.phase=Pending
kubectl describe pod <pending-pod> | grep FailedScheduling
```

**Prevention:**
1. `LimitRange` with defaults in every namespace → no BestEffort Pods.
2. `ResourceQuota` per team → nobody can eat the cluster.
3. VPA in `Off` mode + a monthly right-sizing review.
4. OpenCost / kube-cost for per-namespace spend visibility:
   ```bash
   helm install opencost opencost/opencost -n opencost --create-namespace
   kubectl port-forward -n opencost svc/opencost 9090:9003
   ```
5. An alert on `kube_pod_container_resource_requests{resource="cpu"} == 0` (a new BestEffort Pod).

</details>

---

### Task 7.3 — Ship logs from a namespace to Loki and query them like a pro

<details>
<summary>Show answer</summary>

**1. Verify the collector is seeing the Pods:**

```bash
kubectl get ds -n logging
kubectl logs -n logging ds/loki-alloy --tail=30
kubectl get pods -n logging

# is it reading the right paths?
kubectl debug node/learn-worker -it --image=busybox:1.37
  ls -la /host/var/log/containers/ | grep demo
  head -2 /host/var/log/pods/default_demo-*/demo/0.log
```

Container log format on the node:

```
2026-09-09T12:00:01.123456789Z stdout F {"ts":"...","level":"info","msg":"..."}
└── timestamp ──────────────┘ └─ stream ┘ │└── actual log line
                                          └── F=full, P=partial (line was split)
```

**2. Add Kubernetes metadata as labels.** In Alloy:

```hcl
loki.process "pods" {
  stage.docker {}                       // parse the CRI/docker wrapper

  stage.match {
    selector = '{job="kubernetes-pods"}'
    stage.labels {
      values = { namespace = "kubernetes_namespace_name",
                 pod       = "kubernetes_pod_name",
                 container = "kubernetes_container_name" }
    }
  }

  // derive an `app` label from the pod's own labels via relabeling at discovery time
  forward_to = [loki.write.local.receiver]
}
```

⚠️ **Cardinality warning:** never label on `pod_name`, `trace_id`, `user_id`, or `request_id`. Loki indexes every label combination. Use **structured log fields** for high-cardinality data and query them with `| json`.

**3. Query it:**

```bash
kubectl port-forward -n logging svc/loki-gateway 3100:80 &
sleep 2

# labels available
curl -s 'http://localhost:3100/loki/api/v1/labels' | jq .
curl -s 'http://localhost:3100/loki/api/v1/label/namespace/values' | jq .

# last hour of errors
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="default",app="demo"} |= "ERROR"' \
  --data-urlencode "start=$(date -u -d '-1h' +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000" \
  --data-urlencode 'limit=50' | jq -r '.data.result[].values[][1]'

# error rate over time (for a Grafana panel)
curl -sG 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query=sum(rate({namespace="default",app="demo"} |= "ERROR" [5m]))' | jq .

kill %1
```

**4. Grafana Explore → Loki.** The queries that matter:

```logql
# the incident timeline
{namespace="prod",app="checkout"} | json | level =~ "error|fatal"

# one trace across services
{namespace="prod"} | json | trace_id = "4bf92f3577b34da6"

# rate of 5xx from the access log
sum by (pod) (rate({namespace="prod",container="nginx"} | json | status =~ "5.." [5m]))

# slowest requests
topk(20, {namespace="prod",app="checkout"} | json | unwrap duration_ms | duration_ms > 2000)

# what changed around the deploy?
{namespace="prod"} |~ "(?i)reload|restart|starting|shutdown|config"

# exclude the health-check spam
{namespace="prod"} != "/healthz" != "kube-probe"

# count by error message over a day
sum by (msg) (count_over_time({namespace="prod"} | json | level="error" | line_format "{{.msg}}" [24h]))
```

**5. Alert on logs** (Loki Ruler):

```yaml
groups:
  - name: log-alerts
    interval: 1m
    rules:
      - alert: HighErrorLogRate
        expr: sum(rate({namespace="prod"} |= "ERROR" [5m])) by (app) > 5
        for: 5m
        labels: {severity: critical}
        annotations:
          summary: "{{ $labels.app }} is logging {{ $value }} errors/sec"
      - alert: NewExceptionType
        expr: sum by (exception) (count_over_time({namespace="prod"} | json | exception != "" [10m])) > 0
        labels: {severity: warning}
```

**6. Log hygiene checklist:**
- [ ] Structured JSON, one line per event
- [ ] `service`, `version`, `pod`, `namespace`, `trace_id` on every line
- [ ] Level settable via env var without a redeploy
- [ ] No secrets, no PII (add a scrubber + a pre-commit check)
- [ ] Retention set (`retention_period` in Loki) — logs are cheap for 7 days, expensive for 2 years
- [ ] A dashboard per service, not per node
- [ ] Log volume alert: `sum by (namespace) (rate(loki_distributor_bytes_received_total[5m])) > 10MB` — a runaway logger will fill your disk faster than anything else

</details>

---

### Task 7.4 — Instrument an app that has no metrics endpoint

You have a legacy app that only serves HTTP. Add Prometheus metrics without touching its code.

<details>
<summary>Show answer</summary>

Four approaches, in order of preference.

**A. Scrape the ingress/service mesh instead (zero changes to the app)**

If the app sits behind ingress-nginx, you already have RPS, latency percentiles and status codes per backend:

```promql
# request rate per upstream
sum by (proxy_upstream_name) (rate(nginx_ingress_controller_requests[5m]))

# p99 latency per upstream
histogram_quantile(0.99,
  sum by (le, proxy_upstream_name) (rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])))

# 5xx ratio per upstream
sum by (proxy_upstream_name) (rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
/
sum by (proxy_upstream_name) (rate(nginx_ingress_controller_requests[5m]))
```

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: ingress-nginx, namespace: monitoring, labels: {release: kps}}
spec:
  namespaceSelector: {matchNames: [ingress-nginx]}
  selector: {matchLabels: {app.kubernetes.io/name: ingress-nginx, app.kubernetes.io/component: controller}}
  endpoints: [{port: metrics, interval: 15s}]
```

This gives you RED metrics for free. It doesn't give you *business* metrics (orders created, payments failed).

**B. An exporter sidecar (the classic)**

Run a small container next to the app that produces metrics from something the app already exposes — a log file, a stats endpoint, a JMX port, a database.

```yaml
spec:
  containers:
    - name: legacy
      image: legacy-app:2.1
      ports: [{containerPort: 8080}]
      volumeMounts: [{name: logs, mountPath: /var/log/legacy}]
    - name: grok-exporter                 # tail the log → metrics
      image: pbhogan/grok_exporter:latest
      ports: [{name: metrics, containerPort: 9144}]
      args: ["-config", "/etc/grok/config.yml"]
      volumeMounts:
        - {name: logs, mountPath: /var/log/legacy, readOnly: true}
        - {name: grok-config, mountPath: /etc/grok, readOnly: true}
  volumes:
    - {name: logs, emptyDir: {}}
    - name: grok-config
      configMap: {name: grok-config}
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: grok-config}
data:
  config.yml: |
    global:
      config_version: 3
    input:
      type: file
      file: /var/log/legacy/app.log
      start_position: end
    imports:
      - type: grok_patterns
        dir: ./patterns
    metrics:
      - type: counter
        name: legacy_requests_total
        help: Requests seen in the log
        match: '%{COMBINEDAPACHELOG}'
        labels:
          status: '{{.status}}'
          method: '{{.verb}}'
      - type: histogram
        name: legacy_response_bytes
        help: Response size
        match: '%{COMBINEDAPACHELOG}'
        value: '{{.bytes}}'
        buckets: [100, 1000, 10000, 100000, 1000000]
```

Other ready-made exporters: `mysqld_exporter`, `postgres_exporter`, `redis_exporter`, `blackbox_exporter` (probe an endpoint), `jmx_exporter` (any JVM), `nginx-prometheus-exporter`, `process-exporter`, `snmp_exporter`.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install pg-exporter prometheus-community/prometheus-postgres-exporter \
  --set config.datasource.uri="postgres://monitor:secret@db:5432/app?sslmode=disable"
```

**C. A blackbox probe (health + latency, no app changes at all)**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata: {name: legacy-blackbox, namespace: monitoring, labels: {release: kps}}
spec:
  interval: 30s
  module: http_2xx
  prober: {url: blackbox-exporter.monitoring:9115}
  targets:
    staticConfig:
      static: ["http://legacy.default.svc.cluster.local:8080/", "http://legacy.default.svc.cluster.local/health"]
      labels: {app: legacy}
```

Gives you `probe_success`, `probe_duration_seconds`, `probe_http_status_code`, TLS expiry. Deploy the blackbox exporter first:

```bash
helm install blackbox prometheus-community/prometheus-blackbox-exporter -n monitoring
```

**D. eBPF (kernel-level, truly zero-touch)**

Cilium Hubble, Grafana Beyla, Pixie, Coroot — they observe syscalls/network in the kernel and produce RED metrics for *any* workload, in any language, with no code and no sidecar.

```bash
helm repo add coroot https://coroot.github.io/coroot
helm install coroot coroot/coroot -n coroot --create-namespace
kubectl port-forward -n coroot svc/coroot 8080:8080
```

Best when you have hundreds of uninstrumented services. Costs CPU and needs privileged DaemonSets (a security conversation).

**What I'd actually do:** start with **A** (you get RED metrics today, zero work), add **C** for health and TLS, then instrument the app properly with the OpenTelemetry SDK when you next touch its code. Skip the log-scraping sidecar unless the app is truly frozen — it's fragile.

</details>

---

### Task 7.5 — Set up an SLO with error budget alerts

Define a 99.9% availability SLO for the demo app and alert on burn rate, not raw error rate.

<details>
<summary>Show answer</summary>

**1. Define the SLI.** Pick something you can measure and that maps to user experience.

```
SLI = successful requests / total requests
    = 1 - (rate(5xx) / rate(all))
SLO = 99.9% over a 28-day rolling window
Error budget = 0.1% = 43.2 minutes of failures per 28 days
```

**2. Recording rules (compute these once, reuse everywhere):**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: demo-slo, namespace: monitoring, labels: {release: kps}}
spec:
  groups:
    - name: slo:demo:recording
      interval: 30s
      rules:
        - record: sli:demo_http:availability
          expr: |
            1 - (
              sum(rate(demo_http_requests_total{job="demo",status=~"5.."}[5m]))
              /
              sum(rate(demo_http_requests_total{job="demo"}[5m]))
            )
        # one metric per window, so multi-window burn rate is cheap
        - record: sli:demo_http:error_ratio_5m
          expr: sum(rate(demo_http_requests_total{job="demo",status=~"5.."}[5m])) / sum(rate(demo_http_requests_total{job="demo"}[5m]))
        - record: sli:demo_http:error_ratio_1h
          expr: sum(rate(demo_http_requests_total{job="demo",status=~"5.."}[1h])) / sum(rate(demo_http_requests_total{job="demo"}[1h]))
        - record: sli:demo_http:error_ratio_6h
          expr: sum(rate(demo_http_requests_total{job="demo",status=~"5.."}[6h])) / sum(rate(demo_http_requests_total{job="demo",status=~"5.."}[6h]) or rate(demo_http_requests_total{job="demo"}[6h]))
        - record: sli:demo_http:error_ratio_3d
          expr: sum(increase(demo_http_requests_total{job="demo",status=~"5.."}[3d])) / sum(increase(demo_http_requests_total{job="demo"}[3d]))
```

**3. Multi-window, multi-burn-rate alerts** (Google SRE Workbook, Table 5-2). The whole point: **fast burn → page; slow burn → ticket.** A single threshold either pages constantly or misses real incidents.

| Burn rate | Budget consumed | Windows | Severity | Action |
|---|---|---|---|---|
| 14.4× | 2% in 1 hour | 1h + 5m | **Page** | Immediate |
| 6× | 5% in 6 hours | 6h + 30m | **Page** | Immediate |
| 3× | 10% in 3 days | 3d + 6h | Ticket | Business hours |
| 1× | 100% in 28 days | 28d + — | Dashboard only | Trend |

```yaml
    - name: slo:demo:alerts
      rules:
        - alert: DemoFastBudgetBurn
          expr: |
            (
              sli:demo_http:error_ratio_1h > (14.4 * 0.001)
              and
              sli:demo_http:error_ratio_5m > (14.4 * 0.001)
            )
          for: 2m
          labels: {severity: critical, slo: demo-availability}
          annotations:
            summary: "demo is burning its error budget 14.4× too fast"
            description: "At this rate 2% of the 28-day budget will be gone in 1 hour. Current error ratio: {{ with query \"sli:demo_http:error_ratio_5m\" }}{{ . | first | value | humanizePercentage }}{{ end }}."
            runbook_url: "https://wiki.internal/runbooks/demo-availability"
            dashboard: "http://grafana:3000/d/demo-slo"

        - alert: DemoSlowBudgetBurn
          expr: |
            (
              sli:demo_http:error_ratio_6h > (6 * 0.001)
              and
              sli:demo_http:error_ratio_30m > (6 * 0.001)
            )
          for: 15m
          labels: {severity: critical, slo: demo-availability}
          annotations:
            summary: "demo burning budget 6× too fast"

        - alert: DemoBudgetBurnTicket
          expr: |
            (
              sli:demo_http:error_ratio_3d > (1 * 0.001)
              and
              sli:demo_http:error_ratio_6h > (1 * 0.001)
            )
          for: 1h
          labels: {severity: warning, slo: demo-availability}
          annotations:
            summary: "demo will exhaust its 28-day budget at this rate"
```

> 🔑 **Both windows must fire.** The short window prevents stale data from keeping an alert firing after recovery; the long window prevents a 30-second blip from paging anyone.

**4. Error budget remaining (the dashboard panel everyone cares about):**

```promql
# SLO over a 28-day window
1 - (
  sum(increase(demo_http_requests_total{job="demo",status=~"5.."}[28d]))
  /
  sum(increase(demo_http_requests_total{job="demo"}[28d]))
)
# → 0.9993 = 99.93% achieved, budget remaining = (0.9993 - 0.999) / 0.001 = 30%

# budget consumed as a percentage
(
  sum(increase(demo_http_requests_total{job="demo",status=~"5.."}[28d]))
  /
  sum(increase(demo_http_requests_total{job="demo"}[28d]))
) / 0.001 * 100
```

**5. Latency SLO too** (availability alone is a lie if everything takes 30 s):

```yaml
- record: sli:demo_http:good_latency_ratio_5m
  expr: |
    sum(rate(demo_http_request_duration_seconds_bucket{job="demo",le="0.5"}[5m]))
    /
    sum(rate(demo_http_request_duration_seconds_count{job="demo"}[5m]))
```

SLO: 95% of requests under 500 ms. Alert the same way with `(1 - good_ratio)`.

**6. The policy that makes SLOs useful:**

> **If the error budget is exhausted, the team stops shipping features until reliability recovers.**
>
> That's the whole point. Without this rule, an SLO is a dashboard decoration. Write it into your team's operating agreement *before* you build the alerts.

```bash
kubectl apply -f prometheusrule-slo.yaml
curl -s 'localhost:9090/api/v1/rules' | jq -r '.data.groups[] | select(.name|test("slo")) | .rules[] | "\(.type)\t\(.name // .record)"'
```

Useful tooling: **sloth** (generates multi-burn-rate rules from a simple SLO spec), **OpenSLO** (a vendor-neutral SLO spec), **Grafana Adaptive Metrics**, **Pyrra**.

```yaml
# sloth spec — much less YAML for the same result
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata: {name: demo-availability}
spec:
  service: demo
  slos:
    - name: availability
      objective: 99.9
      description: 99.9% of demo requests succeed
      sli:
        events:
          errorQuery: sum(rate(demo_http_requests_total{job="demo",status=~"5.."}[{{.window}}]))
          totalQuery: sum(rate(demo_http_requests_total{job="demo"}[{{.window}}]))
      alerting:
        name: DemoAvailability
        pageAlert:   {labels: {severity: critical, channel: oncall}}
        ticketAlert: {labels: {severity: warning,  channel: team}}
```

```bash
sloth generate -i slo.yaml -o generated-rules.yaml
kubectl apply -f generated-rules.yaml
```

</details>

---

## 7.12 Checklist

- [ ] Install metrics-server and explain why `kubectl top` needs it
- [ ] Explain what metrics-server is *not* and why you still need Prometheus
- [ ] Deploy kube-prometheus-stack and reach Grafana, Prometheus and Alertmanager
- [ ] Write a ServiceMonitor and prove the target is UP
- [ ] Explain the difference between cAdvisor, node-exporter and kube-state-metrics
- [ ] Compute a p99 from a histogram correctly (aggregate buckets, then quantile)
- [ ] Detect CPU throttling with `container_cpu_cfs_throttled_periods_total`
- [ ] Write the RED queries for any service and the USE queries for any node
- [ ] Write a PrometheusRule with recording rules and multi-window alerts
- [ ] Configure Alertmanager routing, inhibition and Slack/PagerDuty receivers
- [ ] Explain the difference between alerting on symptoms vs causes
- [ ] Tail multi-pod logs with stern and query them in Loki with LogQL
- [ ] Explain why you must never label on high-cardinality fields in Loki
- [ ] Add tracing with zero code changes via the OpenTelemetry Operator
- [ ] Define an SLO and alert on burn rate instead of raw error rate

**Next → [`11-PROJECT-8-react-frontend.md`](11-PROJECT-8-react-frontend.md)** — a real React SPA on Kubernetes, simple and production-grade.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
