# ⏱️ The One-Day Master Plan — Monitoring & Alerting

> **Both cases in one day.** Prometheus + Grafana in the morning, OpenTelemetry in the afternoon, correlation wired by dinner.
>
> This is an **aggressive but achievable** plan for someone who has read [01-OBSERVABILITY-GUIDE.md](./01-OBSERVABILITY-GUIDE.md) and is comfortable with `kubectl`. Every hour has an exact deliverable and an exact command. If an hour overruns, the **`⏭ SKIP` markers** tell you what to drop without breaking the chain.
>
> **Total: 14 hours** (06:00 → 22:00, with meals). Prefer two days? Use the [2-day split](#the-2-day-split-recommended) at the bottom.

---

## Before you start (do this the night before — 20 minutes)

```bash
# 1. the tools
brew install kubectl helm kind prometheus sloth jq yq wget curl    # macOS
# or:
sudo apt-get install -y curl jq wget && \
  curl -LO "https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl" && sudo install -m755 kubectl /usr/local/bin/ && \
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
  go install sigs.k8s.io/kind@latest && \
  curl -sL https://github.com/prometheus/prometheus/releases/download/v3.13.2/prometheus-3.13.2.linux-amd64.tar.gz | tar xz && \
  sudo install -m755 prometheus-*/promtool /usr/local/bin/ && \
  curl -sL https://github.com/prometheus/alertmanager/releases/download/v0.28.1/alertmanager-0.28.1.linux-amd64.tar.gz | tar xz && \
  sudo install -m755 alertmanager-*/amtool /usr/local/bin/ && \
  go install github.com/slok/sloth/cmd/sloth@latest

# 2. verify
kubectl version --client && helm version && kind version && promtool --version && amtool --version && sloth version

# 3. the resources (a laptop needs ≥16 GB free for Docker; 8 CPUs helps)
docker info | grep -E 'CPUs|Total Memory'
#  CPUs: 8   Total Memory: 14.8GiB    ← the minimum comfortable

# 4. pull the images NOW so the install isn't waiting on downloads
for img in \
  quay.io/prometheus/prometheus:v3.13.2 \
  quay.io/prometheus/alertmanager:v0.28.1 \
  grafana/grafana:12.3.1 \
  grafana/tempo:2.6.1 \
  grafana/loki:3.7.5 \
  otel/opentelemetry-collector-contrib:0.158.0 \
  quay.io/prometheus/node-exporter:v1.9.1 \
  registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0 \
  prom/blackbox-exporter:v0.26.0 \
  registry.k8s.io/prometheus-adapter/prometheus-adapter:v0.12.0 \
  ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.11.0 \
  curlimages/curl:8.10.1 nicolaka/netshoot:latest ; do
  docker pull "$img" >/dev/null 2>&1 && echo "  ✅ $img" || echo "  ⏭  $img"
done

# 5. the workspace
mkdir -p ~/observability-learn/{case1,case2,capstone}
cd ~/observability-learn && git init -b main

# 6. open the three files you'll be copying from, side by side
#    02-CASE-1-prometheus-grafana.md   03-CASE-2-telemetry.md   05-CHEATSHEET.md
```

**The kind cluster** (create it once, in the night-before step):

```bash
cat > ~/observability-learn/kind-obs.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: obs
nodes:
  - role: control-plane
    kubeadmConfigPatches: ["|\nkind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: ingress-ready=true\n"]
    extraPortMappings:
      - {containerPort: 30080, hostPort: 80}
      - {containerPort: 30443, hostPort: 443}
  - role: worker
  - role: worker
  - role: worker          # ⭐ 3 workers: the DaemonSet story only makes sense with >1 node
EOF
kind create cluster --config ~/observability-learn/kind-obs.yaml --wait 5m
kubectl get nodes
```

---

## The day at a glance

```
06:00 ─ 07:00   H1   The cluster, the apps, and traffic                    CASE 1
07:00 ─ 08:00   H2   kube-prometheus-stack: install and verify             CASE 1
08:00 ─ 09:00   H3   PromQL by hand — the 20 queries                       CASE 1
09:00 ─ 09:30        ☕ breakfast
09:30 ─ 10:30   H4   Instrument the apps: Java, Go, Python                 CASE 1
10:30 ─ 11:30   H5   ServiceMonitors, recording rules                      CASE 1
11:30 ─ 12:30   H6   Alerting rules + Alertmanager routing                 CASE 1
12:30 ─ 13:15        🍛 lunch
13:15 ─ 14:00   H7   Dashboards-as-code + the RED dashboard                CASE 1
14:00 ─ 15:00   H8   SLOs with sloth + custom-metric HPA                   CASE 1
15:00 ─ 16:00   H9   Break it: 5 failures, watch the alerts                CASE 1
16:00 ─ 16:15        ☕ tea
16:15 ─ 17:15   H10  Tempo + Loki + the Collector (agent + gateway)        CASE 2
17:15 ─ 18:15   H11  Instrument for traces: Java agent, Go SDK             CASE 2
18:15 ─ 19:00        🍽️ dinner
19:00 ─ 20:00   H12  The correlation wiring + the four-click loop          CASE 2
20:00 ─ 21:00   H13  Tail sampling + the Collector's self-monitoring       CASE 2
21:00 ─ 22:00   H14  The incident dashboard + the final smoke test         BOTH
```

---

# ☀️ MORNING — CASE 1: Prometheus & Grafana

## H1 · 06:00–07:00 — The cluster, the apps, and traffic

**Deliverable:** 5 services running in namespace `shop`, with a load generator producing traffic you can watch.

```bash
# 1. namespaces (5 min)
kubectl create namespace shop monitoring otel --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns shop team=payments --overwrite
kubectl get ns

# 2. the data stores (10 min)
kubectl -n shop apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: redis, namespace: shop}
spec:
  replicas: 1
  selector: {matchLabels: {app: redis}}
  template:
    metadata: {labels: {app: redis}}
    spec:
      containers: [{name: redis, image: redis:7.4-alpine, ports: [{containerPort: 6379}],
                    resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 128Mi}}}]
---
apiVersion: v1
kind: Service
metadata: {name: redis, namespace: shop}
spec: {selector: {app: redis}, ports: [{port: 6379}]}
---
apiVersion: v1
kind: Secret
metadata: {name: postgres, namespace: shop}
type: Opaque
stringData: {POSTGRES_USER: shop, POSTGRES_PASSWORD: shop, POSTGRES_DB: shop}
---
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: postgres, namespace: shop}
spec:
  serviceName: postgres
  replicas: 1
  selector: {matchLabels: {app: postgres}}
  template:
    metadata: {labels: {app: postgres}}
    spec:
      containers:
        - name: postgres
          image: postgres:17-alpine
          envFrom: [{secretRef: {name: postgres}}]
          ports: [{containerPort: 5432}]
          volumeMounts: [{name: data, mountPath: /var/lib/postgresql/data}]
          resources: {requests: {cpu: 200m, memory: 256Mi}, limits: {memory: 512Mi}}
  volumeClaimTemplates:
    - metadata: {name: data}
      spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 2Gi}}}
---
apiVersion: v1
kind: Service
metadata: {name: postgres, namespace: shop}
spec: {selector: {app: postgres}, ports: [{port: 5432}]}
EOF

kubectl -n shop rollout status deploy/redis --timeout=180s
kubectl -n shop rollout status sts/postgres --timeout=180s

# 3. ⏭ SKIP the real apps for now — use a metrics-emitting stand-in (10 min)
#    The point of the morning is the PLATFORM. Real instrumentation is H4.
kubectl -n shop apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop-api, namespace: shop, labels: {app: shop-api}}
spec:
  replicas: 3
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata: {labels: {app: shop-api, team: payments}, annotations: {prometheus.io/scrape: "true"}}
    spec:
      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api-traced:1.0.0   # from Case 2 — or build it in H4
          ports: [{name: http, containerPort: 8080}, {name: metrics, containerPort: 9090}]
          resources: {requests: {cpu: 250m, memory: 768Mi}, limits: {memory: 1Gi}}
          readinessProbe: {httpGet: {path: /actuator/health/readiness, port: 9090}}
---
apiVersion: v1
kind: Service
metadata: {name: shop-api, namespace: shop, labels: {app: shop-api}}
spec:
  selector: {app: shop-api}
  ports: [{name: http, port: 80, targetPort: 8080}, {name: metrics, port: 9090, targetPort: 9090}]
EOF
kubectl -n shop rollout status deploy/shop-api --timeout=300s

# 4. traffic (5 min)
kubectl -n shop apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: loadgen, namespace: shop}
spec:
  replicas: 1
  selector: {matchLabels: {app: loadgen}}
  template:
    metadata: {labels: {app: loadgen}}
    spec:
      containers:
        - name: curl
          image: curlimages/curl:8.10.1
          command: ["sh","-c"]
          args:
            - |
              while true; do
                for i in $(seq 1 15); do
                  curl -s -o /dev/null -m 5 -XPOST http://shop-api/api/orders \
                    -H 'Content-Type: application/json' -d "{\"items\":$((i%5+1)),\"tier\":\"gold\"}" &
                  curl -s -o /dev/null -m 5 http://shop-api/api/flaky &
                  curl -s -o /dev/null -m 5 http://shop-api/api/items &
                done
                wait; sleep 1
              done
          resources: {requests: {cpu: 100m, memory: 32Mi}, limits: {memory: 64Mi}}
EOF

# ✅ VERIFY — the checkpoint you must hit before moving on
kubectl -n shop get pods -o wide
# NAME                        READY   STATUS    RESTARTS   AGE   NODE
# loadgen-…                   1/1     Running   0          2m
# postgres-0                  1/1     Running   0          5m
# redis-…                     1/1     Running   0          6m
# shop-api-…                  1/1     Running   0          3m   obs-worker
# shop-api-…                  1/1     Running   0          3m   obs-worker2
# shop-api-…                  1/1     Running   0          3m   obs-worker3
kubectl -n shop exec deploy/shop-api -- wget -qO- localhost:9090/prometheus | grep -c http_server_requests
# a number > 0   ✅
```

**If you're stuck:** the image doesn't exist yet → build it now, or use any image with a `/metrics` endpoint. `prom/pushgateway` works as a stand-in.

---

## H2 · 07:00–08:00 — kube-prometheus-stack: install and verify

**Deliverable:** Prometheus, Grafana, Alertmanager, node_exporter, kube-state-metrics, blackbox_exporter and prometheus-adapter all Running, with Grafana showing real cluster data.

```bash
# 1. the repos (2 min)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm search repo kube-prometheus-stack --versions | head -3

# 2. ⭐ write the values file (15 min) — copy from Case 1 §2, and change ONLY these:
cd ~/observability-learn/case1
#    fullnameOverride: kps
#    prometheus.prometheusSpec.image.tag: v3.13.2
#    prometheus.prometheusSpec.replicas: 1
#    prometheus.prometheusSpec.retention: 15d
#    prometheus.prometheusSpec.storageSpec → 20Gi (a laptop, not production)
#    prometheus.prometheusSpec.resources.limits.memory: 4Gi
#    prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false   ⭐⭐ CRITICAL
#    grafana.adminPassword: admin
#    grafana.sidecar.dashboards.enabled: true, label: grafana_dashboard
#    grafana.sidecar.datasources.enabled: true, label: grafana_datasource
#    kube-state-metrics.metricLabelsAllowlist: [pods=[app,team],deployments=[app,team]]  ⭐
#    prometheus-blackbox-exporter.enabled: true

# 3. install (15 min — it pulls a lot)
helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring -f kps-values.yaml --wait --timeout 10m

# 4. ⏭ if it fails, this is the diagnostic (5 min)
kubectl get pods -n monitoring
kubectl describe pod -n monitoring <the stuck one> | grep -A10 Events
helm get notes kps -n monitoring

# 5. port-forward and log in (3 min)
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 >/dev/null 2>&1 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9090 >/dev/null 2>&1 &
sleep 5

# ✅ VERIFY — all five must pass
curl -sf localhost:9090/-/ready && echo " ✅ Prometheus ready"
curl -sf localhost:9093/-/ready && echo " ✅ Alertmanager ready"
curl -sf localhost:3000/api/health | jq -r '.database' && echo " ✅ Grafana healthy"
curl -s localhost:9090/api/v1/targets | jq -r '[.data.activeTargets[] | select(.health=="up")] | length'
#   30+   ✅
curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.health!="up") | "\(.labels.job): \(.lastError)"'
#   (empty) ✅
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=count(up)' | jq -r '.data.result[0].value[1]'
#   30+   ✅
```

**Then, in the browser (10 min):**
```
http://localhost:3000   (admin / admin)
  → Dashboards → "Kubernetes / Compute Resources / Cluster"
     ⭐ you should see live CPU and memory for your 3 worker nodes
  → Dashboards → "Prometheus / Overview"
     ⭐ you should see the scrape rate climbing
  → Explore → Prometheus → type:  count by (job) (up)
     ⭐ every job, and its target count
```

**The one thing to internalise this hour:** `serviceMonitorSelectorNilUsesHelmValues: false`. Without it, your ServiceMonitors are silently ignored unless they carry `release: kps`, and you will spend an hour finding out why.

---

## H3 · 08:00–09:00 — PromQL by hand

**Deliverable:** you have typed all 20 essential queries and can predict what each returns. **Do not skip this hour.** Everything after it is easier because of it.

Open `http://localhost:9090/graph` and type each of these. Read the result, don't just paste it.

```promql
# ── 1. the model ──────────────────────────────────────────────────
up                                                    # 1 = scraping fine, 0 = down
count(up)                                             # how many targets
count by (job) (up)                                   # per job
up == 0                                               # ⭐ FILTER: only the broken ones
up == bool 0                                          # ⭐ BOOL: all of them, valued 0/1

# ── 2. the node ───────────────────────────────────────────────────
node_load1
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 4*3600)   # ⭐ < 0 = fills in 4h

# ── 3. the containers ─────────────────────────────────────────────
sum by (namespace) (rate(container_cpu_usage_seconds_total[5m]))
topk(5, sum by (pod) (container_memory_working_set_bytes{namespace="shop"}))
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="shop"}[5m]))
  / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="shop"}[5m]))     # ⭐ throttling

# ── 4. the Kubernetes objects ─────────────────────────────────────
kube_pod_status_phase{namespace="shop"} == 1
kube_pod_container_status_restarts_total{namespace="shop"} > 0
kube_deployment_status_replicas_available{namespace="shop"}
  != kube_deployment_spec_replicas{namespace="shop"}
count by (label_team) (kube_pod_labels{label_team!=""})          # ⭐ needs metricLabelsAllowlist

# ── 5. the counters and the rate family ───────────────────────────
http_server_requests_seconds_count                                # ⛔ a staircase
rate(http_server_requests_seconds_count[5m])                      # ✅ per second
irate(http_server_requests_seconds_count[5m])                     # ✅ spiky
increase(http_server_requests_seconds_count[1h])                  # ✅ the total over 1h
rate(http_server_requests_seconds_count[30s])                     # ⛔ TOO SHORT — gaps

# ── 6. the histogram ⭐⭐ the most important three ────────────────
histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket[5m])))
histogram_quantile(0.99, sum by (le, uri) (rate(http_server_requests_seconds_bucket[5m])))
sum(rate(http_server_requests_seconds_sum[5m])) / sum(rate(http_server_requests_seconds_count[5m]))
sum(rate(http_server_requests_seconds_bucket{le="0.3"}[5m]))
  / sum(rate(http_server_requests_seconds_count[5m]))              # ⭐ your latency SLI

# ── 7. the error ratio, with clamp_min ⭐ ─────────────────────────
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
  / clamp_min(sum(rate(http_server_requests_seconds_count[5m])), 0.001)

# ── 8. the join ───────────────────────────────────────────────────
container_memory_working_set_bytes{namespace="shop"}
  / on(namespace, pod, container) group_left
    kube_pod_container_resource_limits{namespace="shop", resource="memory"}
rate(container_cpu_usage_seconds_total[5m])
  * on(namespace, pod) group_left(label_app, label_team) kube_pod_labels

# ── 9. absence and presence ───────────────────────────────────────
absent(up{job="shop-api"})
absent_over_time(http_server_requests_seconds_count[5m])
count(up) or vector(0)

# ── 10. the time-travel queries ───────────────────────────────────
rate(http_server_requests_seconds_count[5m] offset 1h)
rate(http_server_requests_seconds_count[5m])
  / rate(http_server_requests_seconds_count[5m] offset 7d)          # ⭐ vs a week ago

# ── 11. the aggregation-over-time family ──────────────────────────
max_over_time(container_memory_working_set_bytes{namespace="shop"}[1h])
min_over_time(jvm_memory_used_bytes{area="heap"}[10m])               # ⭐ the leak detector
avg_over_time(node_load1[1h])
quantile_over_time(0.99, node_load1[1h])
deriv(prometheus_tsdb_head_series[1h])                               # ⭐ the cardinality trend

# ── 12. topk / count_values ───────────────────────────────────────
topk(5, sum by (pod) (container_memory_working_set_bytes))
count_values("version", node_exporter_build_info)

# ── 13. Prometheus monitoring itself ──────────────────────────────
prometheus_tsdb_head_series                                          # ⭐ your cardinality
rate(prometheus_tsdb_head_samples_appended_total[5m])
topk(10, scrape_samples_scraped)
topk(10, scrape_duration_seconds)
increase(prometheus_rule_evaluation_failures_total[10m])
time() - prometheus_tsdb_head_time_seconds                           # ⭐ > 900 = stopped ingesting
```

```bash
# and from the CLI, so you can script it
promtool query instant localhost:9090 'count(up)'
promtool query instant localhost:9090 'prometheus_tsdb_head_series' --format=json | jq .
promtool query range localhost:9090 'node_load1' \
  --start="$(date -d '-1 hour' -Iseconds)" --end="$(date -Iseconds)" --step=60s
curl -s localhost:9090/api/v1/status/tsdb | jq '.data.headStats'
```

**The three lessons of this hour:**
1. **Counters need `rate()`.** A raw counter is meaningless.
2. **Histograms need `sum by (le)`.** Forget `le` and you get nothing.
3. **Divisions need `clamp_min`.** Forget it and low traffic gives you NaN panels.

---

## ☕ 09:00–09:30 — Breakfast. Do not skip. Your brain consolidates PromQL while you eat.

---

## H4 · 09:30–10:30 — Instrument the apps

**Deliverable:** three real services exposing custom metrics — Spring Boot (Micrometer), Go (`promhttp`), Python (`prometheus_client`) — with histograms enabled and SLO-aligned buckets.

```bash
# ⭐ the FASTEST path: copy the complete code from Case 1 §4–§6. Don't type it.
#    Case 1 has the full pom.xml, application.yaml, OrderService.java, OrderController.java,
#    main.go, Dockerfile, worker.py, Dockerfile.

cd ~/observability-learn/case1

# ── 1. Spring Boot (25 min) ───────────────────────────────────────
mkdir -p shop-api && cd shop-api
# copy from Case 1: pom.xml, application.yaml, OrderService.java, OrderController.java, Dockerfile
# ⭐ the four things that must be right:
#   management.server.port: 9090                              (metrics on a separate port)
#   management.prometheus.metrics.export.enabled: true
#   management.metrics.distribution.percentiles-histogram.http.server.requests: true   ⭐⭐
#   management.metrics.distribution.slo.http.server.requests: 50ms,100ms,...,2s        ⭐
docker build -t ghcr.io/3558bhk/shop-api:1.0.0 .
kind load docker-image ghcr.io/3558bhk/shop-api:1.0.0 --name obs

# ⭐ test it LOCALLY before Kubernetes — saves 20 minutes of debugging
docker run --rm -p 8080:8080 -p 9090:9090 ghcr.io/3558bhk/shop-api:1.0.0 &
sleep 35
curl -s localhost:9090/prometheus | grep -E '^http_server_requests_seconds_(count|bucket)' | head -5
curl -s -XPOST localhost:8080/api/orders -H 'Content-Type: application/json' -d '{"items":3}'
curl -s localhost:9090/prometheus | grep -E '^shop_orders_created_total|^shop_orders_pending'
kill %1
cd ..

# ── 2. Go (20 min) ────────────────────────────────────────────────
mkdir -p checkout && cd checkout
# copy from Case 1: go.mod, main.go, Dockerfile
go mod tidy
docker build -t ghcr.io/3558bhk/checkout:1.0.0 .
kind load docker-image ghcr.io/3558bhk/checkout:1.0.0 --name obs
docker run --rm -p 8081:8080 -p 9091:9091 ghcr.io/3558bhk/checkout:1.0.0 &
sleep 10
curl -s localhost:9091/metrics | grep -E '^shop_checkout_(duration_seconds|total)' | head -5
kill %1
cd ..

# ── 3. Python (15 min) ────────────────────────────────────────────
mkdir -p order-worker && cd order-worker
# copy from Case 1: requirements.txt, worker.py, Dockerfile
docker build -t ghcr.io/3558bhk/order-worker:1.0.0 .
kind load docker-image ghcr.io/3558bhk/order-worker:1.0.0 --name obs
docker run --rm -p 9092:9092 ghcr.io/3558bhk/order-worker:1.0.0 &
sleep 10
curl -s localhost:9092/metrics | grep -E '^worker_(jobs_processed|job_duration|queue_depth)' | head -8
kill %1
cd ..

# ── 4. deploy all three ───────────────────────────────────────────
kubectl -n shop apply -f - <<'EOF'
# (copy the three Deployments + Services from Case 1 §4.4, §5.3, §6.3)
EOF
kubectl -n shop rollout status deploy/shop-api   --timeout=300s
kubectl -n shop rollout status deploy/checkout   --timeout=180s
kubectl -n shop rollout status deploy/order-worker --timeout=180s

# ✅ VERIFY
kubectl -n shop exec deploy/shop-api     -- wget -qO- localhost:9090/prometheus | grep -c '^shop_'
kubectl -n shop exec deploy/checkout     -- wget -qO- localhost:9091/metrics     | grep -c '^shop_'
kubectl -n shop exec deploy/order-worker -- wget -qO- localhost:9092/metrics     | grep -c '^worker_'
# all > 0   ✅
```

**The one thing to internalise:** `percentiles-histogram: true`. Without it, Micrometer emits only `_count` and `_sum` — **no buckets** — and every `histogram_quantile` you write returns nothing. This is the #1 Spring Boot observability mistake.

---

## H5 · 10:30–11:30 — ServiceMonitors and recording rules

**Deliverable:** all three services scraped by Prometheus; 12 recording rules computing RED, saturation and business metrics; all of them queryable.

```bash
cd ~/observability-learn/case1

# ── 1. ServiceMonitors + PodMonitor + Probe (15 min) ──────────────
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: shop-api, namespace: shop, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: shop-api}}
  namespaceSelector: {matchNames: [shop]}
  endpoints:
    - port: metrics                              # ⭐ the Service PORT NAME, not the number
      path: /prometheus                          # ⭐ Spring Boot uses /prometheus, not /metrics
      interval: 30s
      scrapeTimeout: 10s
      relabelings:
        - {sourceLabels: [__meta_kubernetes_pod_name], targetLabel: pod}
        - {sourceLabels: [__meta_kubernetes_namespace], targetLabel: namespace}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: checkout, namespace: shop, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: checkout}}
  endpoints: [{port: metrics, path: /metrics, interval: 30s}]
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: order-worker, namespace: shop, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: order-worker}}
  endpoints: [{port: metrics, path: /metrics, interval: 30s}]
EOF

# ⭐ wait and verify — this is where people get stuck
sleep 40
curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.namespace=="shop") | "\(.labels.job)\t\(.health)\t\(.lastError)"'
# shop/shop-api     up
# shop/checkout     up
# shop/order-worker up

# ⛔ if they're missing:
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'; echo
kubectl get servicemonitor -n shop -o jsonpath='{.items[*].metadata.labels}'; echo
# the labels MUST match the selector (or the selector must be {} — which is what
# serviceMonitorSelectorNilUsesHelmValues: false gives you)
kubectl describe servicemonitor -n shop shop-api | grep -i error
kubectl logs -n monitoring sts/kps-kube-prometheus-stack-prometheus -c prometheus --tail=50 | grep -i 'serviceMonitor\|error'

# ── 2. the blackbox Probe (10 min) ───────────────────────────────
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata: {name: shop-http, namespace: shop, labels: {release: kps}}
spec:
  interval: 30s
  module: http_2xx
  prober: {url: kps-kube-prometheus-stack-blackbox-exporter.monitoring.svc:9115, scheme: http, path: /probe}
  targets:
    staticConfig:
      static:
        - http://shop-api.shop.svc/actuator/health
        - http://checkout.shop.svc/healthz
        - http://shop-ui.shop.svc/
      labels: {group: shop-http}
      relabelingConfigs:
        - {sourceLabels: [__address__], targetLabel: __param_target}
        - {sourceLabels: [__param_target], targetLabel: instance}
EOF
sleep 40
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=probe_success' \
  | jq -r '.data.result[] | "\(.metric.instance)\t\(.value[1])"'
# http://shop-api.shop.svc/actuator/health     1     ✅

# ── 3. the recording rules (25 min) ──────────────────────────────
# copy the three PrometheusRule CRs from Case 1 §8 (RED, saturation, business)
kubectl apply -f recording-rules.yaml
sleep 60

# ✅ VERIFY — every recording rule produces a series
for r in \
  'namespace_job:http_server_requests:rate5m' \
  'namespace_job:http_server_requests_errors:rate5m' \
  'namespace_job:http_server_requests:p99_5m' \
  'namespace_job:http_server_requests:p95_5m' \
  'namespace_job:http_server_latency_sli:ratio_rate5m' \
  'namespace_pod:container_cpu_throttling:ratio_rate5m' \
  'namespace_pod:container_memory_utilisation:ratio' \
  'shop:orders_created:rate5m' \
  'shop:orders_rejected:rate5m' ; do
  v=$(curl -sG localhost:9090/api/v1/query --data-urlencode "query=$r" | jq -r '.data.result | length')
  printf '  %-55s %s series\n' "$r" "$v"
done
# every line must show ≥1 series. A 0 means the rule didn't evaluate — check:
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[] | select(.type=="recording") | "\(.health)\t\(.name)\t\(.lastError // "")"'
```

**The one thing to internalise:** the ServiceMonitor's `endpoints[].port` is the **name of the port on the Service**, not the number. If your Service port is named `http` and you write `port: metrics`, the ServiceMonitor is accepted but matches nothing — silently.

---

## H6 · 11:30–12:30 — Alerting rules and Alertmanager routing

**Deliverable:** 18 alerting rules across 4 tiers loaded; Alertmanager routing by team and severity; a test alert delivered to a webhook receiver; a silence created and removed.

```bash
cd ~/observability-learn/case1

# ── 1. ⭐ LINT BEFORE YOU APPLY (5 min) — this saves 30 minutes ──
promtool check rules alerting-rules.yaml
# Checking 'alerting-rules.yaml'
#   SUCCESS: 18 rules found
# ⛔ on failure, the error names the exact line. Fix it here, not in the cluster.

# ── 2. apply (5 min) ─────────────────────────────────────────────
kubectl apply -f alerting-rules.yaml
sleep 60
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[] | select(.type=="alerting") | "\(.health)\t\(.state)\t\(.name)"'
# ok    inactive   CheckoutErrorRatioHigh
# ok    inactive   KubePodNotReady
# ok    firing     Watchdog                 ← ⭐ this one SHOULD always fire
# ⛔ any health="err" → read .lastError. A typo disables the WHOLE group.

# ── 3. the Alertmanager config (20 min) ──────────────────────────
# copy Case 1 §10: the webhook echo receiver, the routing tree, inhibit_rules
kubectl apply -f alertmanager-config.yaml
sleep 30
curl -s localhost:9093/api/v2/status | jq -r '.config.original' | head -40
amtool check-config alertmanager-config.yaml
amtool config routes --alertmanager.url=http://localhost:9093 --tree
# ⭐ read the tree. Does severity=critical really go where you think?

# ── 4. ⭐ TEST THE ROUTING before you trust it (10 min) ──────────
amtool config routes test --alertmanager.url=http://localhost:9093 \
  --labels alertname=CheckoutErrorRatioHigh severity=critical team=payments tier=symptom --tree
# → payments-page     ✅
amtool config routes test --alertmanager.url=http://localhost:9093 \
  --labels alertname=ServiceCpuThrottled severity=warning team=platform tier=saturation --tree
# → slack-team        ✅

# ── 5. fire a real alert through the whole chain (15 min) ────────
# start a webhook receiver so you can SEE the payload
kubectl -n monitoring run webhook-echo --image=mendhak/http-https-echo:35 --port=8080 \
  --restart=Never --labels="app=webhook-echo" 2>/dev/null || true
kubectl -n monitoring port-forward svc/webhook-echo 8080:8080 >/dev/null 2>&1 &
sleep 5

amtool alert add CheckoutErrorRatioHigh severity=critical team=payments tier=symptom namespace=shop \
  --alertmanager.url=http://localhost:9093 \
  --annotation=summary="1 in 100 checkouts is failing (MANUAL TEST)" \
  --annotation=runbook_url="https://git.example.com/runbooks/symptom-http-5xx.md" \
  --annotation=trace_query='{ .service.name = "shop-api" && status = error }' \
  --expires=10m
sleep 40
amtool alert query --alertmanager.url=http://localhost:9093 | head
curl -s localhost:9093/api/v2/alerts | jq '.[].labels'
# ✅ and check the webhook receiver logged the full JSON payload

# ── 6. silences (5 min) ──────────────────────────────────────────
amtool silence add --alertmanager.url=http://localhost:9093 \
  alertname=CheckoutErrorRatioHigh --duration=15m --comment="testing silences" --author="harish"
amtool silence query --alertmanager.url=http://localhost:9093
curl -s localhost:9093/api/v2/alerts | jq '.[].status'
# {"state":"suppressed","silencedBy":["<id>"],"inhibitedBy":[]}   ⭐ THAT's what a silence looks like
amtool silence expire --alertmanager.url=http://localhost:9093 <id>

# ✅ THE FINAL CHECK FOR THIS HOUR
amtool alert expire --alertmanager.url=http://localhost:9093 alertname=CheckoutErrorRatioHigh
curl -s localhost:9093/api/v2/silences | jq '[.[] | select(.status.state=="active")] | length'
# 0   ✅
```

**The one thing to internalise:** `amtool config routes test --labels …`. It answers "which receiver will THIS alert hit?" in one second, without firing anything. Use it every time you change routing.

---

## 🍛 12:30–13:15 — Lunch. Stand up. Walk. Look at something more than 24 inches away.

---

## H7 · 13:15–14:00 — Dashboards-as-code

**Deliverable:** a RED dashboard for `shop-api` provisioned from a ConfigMap, with deployment annotations, variables for namespace and service, and exemplars enabled on the latency panel.

```bash
cd ~/observability-learn/case1

# ── 1. build the dashboard ONCE in the UI, then export it (20 min) ─
# http://localhost:3000 → Dashboards → New → New dashboard
#   Panel 1: Rate       sum by (application) (rate(http_server_requests_seconds_count{namespace="$namespace"}[$__rate_interval]))
#   Panel 2: Errors     the ratio query with clamp_min
#   Panel 3: Duration   THREE queries in ONE panel: p50, p95, p99, unit=seconds
#                       ⭐ Panel options → Exemplars → enable
#   Panel 4: Heatmap    sum by (le) (increase(http_server_requests_seconds_bucket[$__rate_interval]))
#                       ⭐ Query options → Format: Heatmap
#   Variables: namespace (label_values(kube_pod_info, namespace), single)
#              service   (label_values(http_server_requests_seconds_count{namespace="$namespace"}, application), multi + All, custom all value = .*)
#   Settings → Annotations → add the deployment annotation query
#   Settings → set the UID explicitly: 10-shop-api-red    ⭐⭐
#   Save

# ── 2. export and scrub (5 min) ──────────────────────────────────
curl -s -u admin:admin 'localhost:3000/api/dashboards/uid/10-shop-api-red' \
  | jq '.dashboard | del(.id,.version,.iteration)' > dash-shop-api-red.json
jq 'del(.id,.version,.iteration) | .panels[].id = null' dash-shop-api-red.json > dash.clean.json
jq '.uid' dash.clean.json           # "10-shop-api-red"  ⭐ must be present
jq '.panels | length' dash.clean.json

# ── 3. provision it (5 min) ──────────────────────────────────────
kubectl -n monitoring create configmap grafana-dashboard-shop-api-red \
  --from-file=shop-api-red.json=dash.clean.json \
  --dry-run=client -o yaml \
  | yq '.metadata.labels."grafana_dashboard" = "1" | .metadata.annotations."grafana_folder" = "Shop"' \
  | kubectl apply -f -
sleep 30
kubectl logs -n monitoring deploy/kps-grafana -c grafana-sc-dashboard --tail=10
# ✅ "found 1 dashboard" / "adding dashboard to provider"
curl -s -u admin:admin 'localhost:3000/api/search?type=dash-db' | jq '.[] | {uid, title, folderTitle}'

# ── 4. the deployment annotation (5 min) ⭐ ──────────────────────
kubectl -n shop annotate deploy/shop-api \
  kubernetes.io/change-cause="manual: testing deploy annotations @ $(date +%H:%M)" --overwrite
# → in Grafana, the dashboard now shows a blue vertical line at the deploy time.
#    Put this in your CI deploy step and every incident starts with "did we deploy?"
#    answered visually.

# ── 5. import the classics (5 min) ───────────────────────────────
for id in 1860 4701 13186 14055 3146; do
  curl -s -u admin:admin -XPOST localhost:3000/api/dashboards/db -H 'Content-Type: application/json' \
    -d "$(curl -s "https://grafana.com/api/dashboards/$id/revisions/latest/download" \
      | jq '{dashboard: ., overwrite: true, folderUid: "platform",
             inputs: [{name:"DS_PROMETHEUS",type:"datasource",pluginId:"prometheus",value:"prometheus"}]}')" \
    | jq -r '"  \(.status // .message)  id=\(.id // "?")  slug=\(.slug // "?")"'
done
# 1860  Node Exporter Full       ⭐ the definitive node dashboard
# 4701  JVM (Micrometer)         ⭐ for shop-api
# 13186 Loki / Logs              (needs the Loki datasource — H12)
# 14055 OTel Collector           (needs the Collector metrics — H13)
# 3146  Kubernetes / Views / Pods

# ✅ VERIFY
open http://localhost:3000/d/10-shop-api-red
# 4 panels, all with data, the service variable switches between shop-api/checkout,
# and hovering the p99 line shows… (nothing yet — exemplars come in H12)
```

---

## H8 · 14:00–15:00 — SLOs with sloth, and custom-metric HPA

**Deliverable:** 2 SLOs (availability 99.9%, latency 99% < 300 ms) generated as multi-window multi-burn-rate alerts by sloth; an SLO dashboard; an HPA scaling `shop-api` on a custom Prometheus metric.

```bash
cd ~/observability-learn/case1

# ── 1. write the SLO spec (15 min) ───────────────────────────────
cat > slos.yaml <<'EOF'
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata: {name: checkout, namespace: monitoring}
spec:
  service: shop
  slos:
    - name: checkout-availability
      objective: 99.9
      description: "99.9% of checkout requests must not return a server error."
      owner: payments-team
      sli:
        events:
          errorQuery: |
            sum(rate(http_server_requests_seconds_count{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout",status=~"5..|503|504"}[{{.window}}]))
          totalQuery: |
            sum(rate(http_server_requests_seconds_count{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[{{.window}}]))
      alerting:
        name: CheckoutAvailability
        labels: {team: payments, tier: symptom}
        pageAlert:   {labels: {severity: critical}, annotations: {runbook_url: "https://git.example.com/runbooks/slo-checkout.md"}}
        ticketAlert: {labels: {severity: warning}}

    - name: checkout-latency
      objective: 99
      description: "99% of checkout requests must complete in under 300ms."
      owner: payments-team
      sli:
        events:
          errorQuery: |
            sum(rate(http_server_requests_seconds_count{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[{{.window}}]))
            -
            sum(rate(http_server_requests_seconds_bucket{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout",le="0.3"}[{{.window}}]))
          totalQuery: |
            sum(rate(http_server_requests_seconds_count{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[{{.window}}]))
      alerting:
        name: CheckoutLatency
        labels: {team: payments, tier: symptom}
        pageAlert:   {labels: {severity: critical}}
        ticketAlert: {labels: {severity: warning}}
EOF

# ── 2. generate and validate (10 min) ⭐ ─────────────────────────
sloth generate -i slos.yaml -o slo-rules.yaml
promtool check rules slo-rules.yaml
# SUCCESS: 16 rules found      ← 2 SLOs × (2 recording + 4 burn-rate + 2 SLI) roughly
grep -E '^\s+- (alert|record):' slo-rules.yaml
#   - record: slo:sli_error:ratio_rate5m
#   - record: slo:sli_error:ratio_rate1h
#   - alert: CheckoutAvailabilityBurnRateFast
#   - alert: CheckoutAvailabilityBurnRateSlow
#   - alert: CheckoutAvailabilityBurnRateMedium
#   - alert: CheckoutAvailabilityBurnRateSlowest
#   … and the same four for latency

kubectl apply -f slos.yaml
kubectl apply -f slo-rules.yaml
sleep 60

# ✅ VERIFY — the SLI is being computed
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=slo:sli_error:ratio_rate5m' | jq '.data.result'
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=sloth_slo_sli' | jq '.data.result'
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=sloth_slo_error_budget_ratio' | jq '.data.result[].value[1]'
# "0.03"  → 3% of the budget consumed

# ── 3. ⭐ BREAK THE SLO AND WATCH THE BURN RATE (10 min) ─────────
kubectl -n shop scale deploy/loadgen --replicas=3
kubectl -n shop exec deploy/loadgen -- sh -c 'for i in $(seq 1 500); do curl -s -o /dev/null http://shop-api/api/flaky; done'
# watch the burn rate climb
for i in $(seq 1 12); do
  curl -sG localhost:9090/api/v1/query --data-urlencode \
    'query=sum(rate(http_server_requests_seconds_count{namespace="shop",status=~"5.."}[5m])) / (0.001 * sum(rate(http_server_requests_seconds_count{namespace="shop"}[5m])))' \
    | jq -r '.data.result[0].value[1] // "0"' | xargs -I{} echo "  burn rate: {}×"
  sleep 15
done
# when it crosses 14.4× AND stays there for 2m:
curl -s localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | select(.labels.alertname|test("BurnRate")) | "\(.state)\t\(.labels.alertname)"'
# firing   CheckoutAvailabilityBurnRateFast      ✅
kubectl -n shop scale deploy/loadgen --replicas=1

# ── 4. the HPA on a custom metric (25 min) ───────────────────────
# prometheus-adapter is already installed by the chart. Verify the custom metrics API:
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq -r '.resources[].name' | head -20
# ⛔ empty → the adapter needs rules. Add them:
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: adapter-config, namespace: monitoring}
data:
  config.yaml: |
    rules:
      - seriesQuery: 'http_server_requests_seconds_count{namespace!="",pod!=""}'
        seriesFilters: []
        resources: {overrides: {namespace: {resource: "namespace"}, pod: {resource: "pod"}}}
        name: {matches: "^(.*)_count$", as: "requests_per_second"}
        metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)'
      - seriesQuery: 'shop_checkout_duration_seconds_count{namespace!="",pod!=""}'
        resources: {overrides: {namespace: {resource: "namespace"}, pod: {resource: "pod"}}}
        name: {as: "checkouts_per_second"}
        metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)'
EOF
kubectl -n monitoring patch deploy kps-kube-prometheus-stack-prometheus-adapter --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"config","configMap":{"name":"adapter-config"}}},
       {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"config","mountPath":"/etc/adapter"}}]' 2>/dev/null || \
  echo "  (patch the adapter Deployment to mount the ConfigMap — see Case 1 §12)"
kubectl -n monitoring rollout restart deploy/kps-kube-prometheus-stack-prometheus-adapter
kubectl -n monitoring rollout status deploy/kps-kube-prometheus-stack-prometheus-adapter

sleep 30
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/shop/pods/*/requests_per_second" | jq '.items[] | {name: .describedObject.name, value}'
# ⭐ if this returns values, the HPA will work

kubectl apply -f - <<'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: shop-api, namespace: shop}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-api}
  minReplicas: 3
  maxReplicas: 10
  behavior:
    scaleUp:   {stabilizationWindowSeconds: 30,  policies: [{type: Percent, value: 100, periodSeconds: 30}]}
    scaleDown: {stabilizationWindowSeconds: 300, policies: [{type: Percent, value: 25,  periodSeconds: 60}]}
  metrics:
    - type: Pods
      pods:
        metric: {name: requests_per_second}
        target: {type: AverageValue, averageValue: "50"}     # ⭐ 50 rps per pod
EOF
kubectl -n shop get hpa -w &
HPA_WATCH=$!
kubectl -n shop scale deploy/loadgen --replicas=6
sleep 120
kubectl -n shop get hpa shop-api
# NAME       REFERENCE             TARGETS      MINPODS MAXPODS REPLICAS AGE
# shop-api   Deployment/shop-api   118/50       3       10      7        5m   ✅ IT SCALED
kubectl -n shop scale deploy/loadgen --replicas=1
sleep 300
kubectl -n shop get hpa shop-api          # scales back down to 3
kill $HPA_WATCH
```

**The one thing to internalise:** the latency SLI is `count − bucket{le=threshold}`, not `1 − bucket/total`. sloth wants the *bad events* count, so you subtract the good ones from the total. Getting this backwards gives you an SLO that's always 100% or always 0%.

---

## H9 · 15:00–16:00 — Break it on purpose

**Deliverable:** five injected failures, each detected by an alert you can name, each with the detection time recorded. This is the hour that turns "I installed a chart" into "I have a monitoring system."

```bash
cd ~/observability-learn/case1
cat > watch.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ the alert watcher — run it in a second terminal all day
start=$(date +%s); seen=""
while true; do
  now=$(curl -s localhost:9090/api/v1/alerts 2>/dev/null | jq -r '
    [.data.alerts[] | select(.state=="firing") | "\(.labels.alertname)[\(.labels.severity)]"] | sort | join(" ")')
  [[ "$now" != "$seen" ]] && { printf '%+5ds  %s\n' "$(( $(date +%s) - start ))" "${now:-<none>}"; seen="$now"; }
  sleep 2
done
EOF
chmod +x watch.sh
./watch.sh &        # leave this running
```

```bash
# ══ FAILURE 1: scale to zero — the service simply disappears (10 min) ══
echo "T+0  scaling shop-api to 0"
kubectl -n shop scale deploy/shop-api --replicas=0
# EXPECTED:
#   T+ ~0m   kube_deployment_status_replicas_available drops to 0
#   T+ ~1m   TargetDown / PrometheusTargetDown fires (the metrics endpoint is gone)
#   T+ ~2m   KubeDeploymentReplicasMismatch fires
#   T+ ~5m   ShopFrontendUnreachable fires (the blackbox probe)
#   T+ ~5m   absent(http_server_requests_seconds_count{application="shop-api"}) → MetricsMissing
# ⭐ OBSERVE: which fired FIRST, and was it a SYMPTOM or a CAUSE?
kubectl -n shop scale deploy/shop-api --replicas=3

# ══ FAILURE 2: OOMKill (15 min) ══
echo "T+0  capping memory to 256Mi"
kubectl -n shop patch deploy shop-api --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"256Mi"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"256Mi"}]'
kubectl -n shop rollout status deploy/shop-api
# EXPECTED:
#   T+ ~2m   ServiceMemoryNearLimit (working_set / limit > 0.9)
#   T+ ~4m   OOMKilled, exit 137 → KubeContainerOOMKilled + PodRestartingFrequently
#   T+ ~5m   KubePodNotReady, then TargetDown, then the symptom alerts
# ⭐ THE DIAGNOSTIC QUERIES — type all three:
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=kube_pod_container_status_last_terminated_reason{namespace="shop"}' | jq '.data.result[].metric.reason'
# "OOMKilled"
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=min_over_time(jvm_memory_used_bytes{namespace="shop",area="heap"}[10m])' | jq .
# ⭐ is the sawtooth FLOOR rising? That's a leak. A stable floor = normal.
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=predict_linear(container_memory_working_set_bytes{namespace="shop"}[30m], 3600)' | jq .
kubectl -n shop patch deploy shop-api --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1Gi"}]'
kubectl -n shop rollout restart deploy/shop-api

# ══ FAILURE 3: CPU throttling (10 min) ══
echo "T+0  capping CPU to 100m under load"
kubectl -n shop patch deploy/shop-api --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"100m"}]'
kubectl -n shop rollout status deploy/shop-api
kubectl -n shop scale deploy/loadgen --replicas=4
# EXPECTED:
#   T+ ~3m   ServiceCpuThrottled (throttled_periods / cfs_periods > 0.25)
#   T+ ~8m   CheckoutLatencyP99High (throttling adds latency without adding errors!)
# ⭐⭐ THE LESSON: throttling is the classic "slow but not erroring" cause.
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="shop"}[5m])) / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="shop"}[5m]))' \
  | jq -r '.data.result[] | "\(.metric.pod)\t\(.value[1])"'
# shop-api-7d9…   0.87      ← 87% of periods throttled
kubectl -n shop patch deploy shop-api --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"1"}]'
kubectl -n shop scale deploy/loadgen --replicas=1
kubectl -n shop rollout restart deploy/shop-api

# ══ FAILURE 4: the cardinality bomb (15 min) ⭐⭐ the scariest ══
BEFORE=$(curl -sG localhost:9090/api/v1/query --data-urlencode 'query=prometheus_tsdb_head_series' | jq -r '.data.result[0].value[1]')
echo "T+0  series count BEFORE: $BEFORE"
kubectl -n shop set env deploy/shop-api MANAGEMENT_METRICS_TAGS_REQUEST_ID=enabled
kubectl -n shop rollout status deploy/shop-api
kubectl -n shop scale deploy/loadgen --replicas=6
for i in $(seq 1 10); do
  NOW=$(curl -sG localhost:9090/api/v1/query --data-urlencode 'query=prometheus_tsdb_head_series' | jq -r '.data.result[0].value[1]')
  printf '  T+%2dm  series: %s  (+%s)\n' "$i" "$NOW" "$((NOW - BEFORE))"
  sleep 60
done
# ⭐ THE SMOKING GUN: the series count climbs LINEARLY WITH TRAFFIC.
#    A healthy system's series count is FLAT regardless of traffic.
# EXPECTED: PrometheusCardinalityBudgetExceeded fires
# THE DIAGNOSIS, in three commands:
curl -s localhost:9090/api/v1/status/tsdb | jq '.data.top10SeriesCountByMetricName'
curl -sG localhost:9090/api/v1/label/request_id/values | jq '.data | length'
# 48213     ← ⛔ THERE IT IS
promtool query analyze localhost:9090 'http_server_requests_seconds_count' --limit=10
# THE FIX:
kubectl -n shop set env deploy/shop-api MANAGEMENT_METRICS_TAGS_REQUEST_ID-
kubectl -n shop rollout restart deploy/shop-api
kubectl -n shop scale deploy/loadgen --replicas=1
kubectl -n monitoring rollout restart sts/kps-kube-prometheus-stack-prometheus   # reclaim the head block

# ══ FAILURE 5: break the monitoring itself (10 min) ⭐⭐ ══
echo "T+0  introducing a syntax error into a rule group"
cp alerting-rules.yaml /tmp/alerting-rules.yaml.bak
sed -i '0,/sum by (le)/s//sum by (le]/' alerting-rules.yaml
kubectl apply -f alerting-rules.yaml 2>&1 | head -3
sleep 40
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[] | select(.health!="ok") | "\(.name)\t\(.lastError)"'
# ⭐ PrometheusRuleEvaluationFailures should be firing.
# ⭐⭐ THE POINT: the entire rule GROUP is rejected. Every alert in it silently stops.
#    Without a self-monitoring alert on rule failures, you'd never know.
cp /tmp/alerting-rules.yaml.bak alerting-rules.yaml
kubectl apply -f alerting-rules.yaml
promtool check rules alerting-rules.yaml     # ✅ SUCCESS again

# ── FILL IN THE SCORECARD (this is the deliverable) ──────────────
cat > SCORECARD.md <<'EOF'
| # | Failure | Expected alert | Fired at | Correct tier? | Notes |
|---|---|---|---|---|---|
| 1 | scale to 0 | TargetDown / KubeDeploymentReplicasMismatch | T+___ | ☐ | |
| 2 | OOMKill | ServiceMemoryNearLimit BEFORE the kill | T+___ | ☐ | |
| 3 | CPU throttle | ServiceCpuThrottled | T+___ | ☐ | latency rose, errors did not |
| 4 | cardinality bomb | PrometheusCardinalityBudgetExceeded | T+___ | ☐ | series grew with traffic |
| 5 | broken rule | PrometheusRuleEvaluationFailures | T+___ | ☐ | the whole group was rejected |

FALSE POSITIVES (alerts that fired but shouldn't have): ___
MISSED DETECTIONS (failures with no alert): ___
EOF
```

## ☕ 16:00–16:15 — Tea. You've earned it. The morning is done and you have a working metrics platform.

---

# 🌙 AFTERNOON — CASE 2: Telemetry

## H10 · 16:15–17:15 — Tempo, Loki, and the Collector

**Deliverable:** Tempo and Loki installed; the OTel Collector deployed as an agent DaemonSet and a gateway Deployment; a hand-crafted span successfully retrieved from Tempo.

```bash
cd ~/observability-learn/case2

# ── 1. Tempo (12 min) ────────────────────────────────────────────
# copy tempo-values.yaml from Case 2 §1.1 — the essentials:
#   tempo.tempo.image.tag: 2.6.1
#   tempo.tempo.searchEnabled: true            ⭐ required for TraceQL
#   tempo.tempo.metricsGenerator.enabled: true ⭐ the service graph
#   tempo.tempo.storage.trace.backend: local
#   tempo.tempo.retention: 72h
#   tempo.persistence.size: 10Gi
helm install tempo grafana/tempo -n monitoring -f tempo-values.yaml --wait --timeout 8m
kubectl -n monitoring get pods -l app.kubernetes.io/name=tempo
kubectl port-forward -n monitoring svc/tempo 3200:3200 >/dev/null 2>&1 &
sleep 5
curl -s localhost:3200/ready
curl -s localhost:3200/api/search/tags | jq .    # ⛔ empty is normal — nothing has arrived yet

# ── 2. Loki (12 min) ─────────────────────────────────────────────
# copy loki-values.yaml from Case 2 §1.2 — the essentials:
#   deploymentMode: SingleBinary
#   loki.schemaConfig → tsdb + v13
#   loki.limits_config.retention_period: 168h
#   loki.compactor.retention_enabled: true     ⭐ without this, retention does nothing
#   promtail.enabled: false, gateway.enabled: false   ⭐ the Collector ships logs
helm install loki grafana/loki -n monitoring -f loki-values.yaml --wait --timeout 8m
kubectl port-forward -n monitoring svc/loki 3100:3100 >/dev/null 2>&1 &
sleep 5
curl -s localhost:3100/ready
curl -s localhost:3100/loki/api/v1/labels | jq .

# ── 3. the Collector: agent + gateway (25 min) ───────────────────
# copy from Case 2 §2.1 and §2.2 — DO NOT SKIP THE memory_limiter AND k8sattributes
kubectl create namespace otel --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns otel team=platform --overwrite

# the RBAC for k8sattributes (Case 2 §2.3)
kubectl apply -f otel-rbac.yaml

# the agent DaemonSet
kubectl create configmap otel-agent-config -n otel --from-file=config.yaml=collector/agent-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f otel-agent.yaml
kubectl -n otel rollout status ds/otel-agent --timeout=180s
kubectl -n otel get pods -o wide | grep otel-agent     # ⭐ one per node = 3 pods

# the gateway Deployment
kubectl create configmap otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f otel-gateway.yaml
kubectl -n otel rollout status deploy/otel-collector-gateway --timeout=180s

# ⛔ if either is CrashLoopBackOff, it's the config:
kubectl -n otel logs deploy/otel-collector-gateway --tail=50 | grep -iE 'error|cannot|failed'
# "failed to create \"tail_sampling\" processor" → a typo in the policy
# "unknown receiver" → you're using the non-contrib image

# ── 4. ⭐⭐ THE MANUAL-SPAN PROBE — do this before instrumenting anything (10 min)
kubectl port-forward -n otel svc/otel-collector-gateway 4317:4317 4318:4318 8888:8888 >/dev/null 2>&1 &
sleep 4
TRACE_ID=$(openssl rand -hex 16); SPAN_ID=$(openssl rand -hex 8)
NOW=$(date +%s%N); END=$((NOW + 250000000))
curl -s -XPOST localhost:4318/v1/traces -H 'Content-Type: application/json' -d '{
  "resourceSpans":[{"resource":{"attributes":[
      {"key":"service.name","value":{"stringValue":"manual-test"}},
      {"key":"deployment.environment","value":{"stringValue":"dev"}}]},
    "scopeSpans":[{"scope":{"name":"manual-test"},
      "spans":[{"traceId":"'"$TRACE_ID"'","spanId":"'"$SPAN_ID"'","name":"manual-test-span","kind":2,
        "startTimeUnixNano":"'"$NOW"'","endTimeUnixNano":"'"$END"'",
        "attributes":[{"key":"url.path","value":{"stringValue":"/api/orders"}},
                      {"key":"http.response.status_code","value":{"intValue":"200"}}],
        "status":{"code":1}}]}]}]}'
# {"partialSuccess":{}}     ✅
echo "trace id: $TRACE_ID"
sleep 20
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq -r '.batches[0].scopeSpans[0].spans[0].name'
# manual-test-span     ⭐⭐ THE ENTIRE PIPELINE WORKS: curl → gateway → Tempo

curl -s localhost:8888/metrics | grep -E '^otelcol_(receiver_accepted|exporter_sent|processor_dropped)_spans'
# otelcol_receiver_accepted_spans{receiver="otlp",transport="http"}  1
# otelcol_exporter_sent_spans{exporter="otlp/tempo"}                 1
# otelcol_processor_dropped_spans{processor="tail_sampling"}         0   ✅
```

**The one thing to internalise:** validate the pipeline with a hand-crafted span **before** you spend an hour instrumenting an app. If the manual span doesn't reach Tempo, nothing else will, and the failure will be far harder to find buried inside a real service.

---

## H11 · 17:15–18:15 — Instrument for traces

**Deliverable:** Java instrumented by the agent (zero code change), Go instrumented manually, and a single request producing ONE trace across both services.

```bash
cd ~/observability-learn/case2

# ── 1. Java: the zero-code agent (20 min) ────────────────────────
# copy from Case 2 §3:
#   application.yaml  ⭐ add the JSON logging pattern with %X{trace_id}
#   OrderController.java  ⭐ the manual domain span + business attributes
#   Dockerfile  ⭐ the ADD of opentelemetry-javaagent.jar + JAVA_TOOL_OPTIONS
docker build --build-arg OTEL_AGENT_VERSION=2.11.0 -t ghcr.io/3558bhk/shop-api-traced:1.0.0 app/shop-api-traced
kind load docker-image ghcr.io/3558bhk/shop-api-traced:1.0.0 --name obs

# ⭐ test LOCALLY with the console exporter — you SEE the spans
docker run --rm -p 8080:8080 -p 9090:9090 \
  -e OTEL_TRACES_EXPORTER=console -e OTEL_METRICS_EXPORTER=none -e OTEL_LOGS_EXPORTER=none \
  ghcr.io/3558bhk/shop-api-traced:1.0.0 2>&1 | grep -A20 '"name"' | head -40 &
sleep 40
curl -s -XPOST localhost:8080/api/orders -H 'Content-Type: application/json' -d '{"items":3,"tier":"gold"}'
# you should see: {"name":"POST /api/orders", "kind":"SERVER", "attributes":{"http.route":"/api/orders",…},
#                  "children":[{"name":"validate-and-price-cart",…}]}
kill %1 2>/dev/null

# ⭐ and the LOG LINE must carry the trace_id
docker run --rm -p 8080:8080 -p 9090:9090 -e OTEL_SDK_DISABLED=true \
  ghcr.io/3558bhk/shop-api-traced:1.0.0 2>&1 | grep -m1 'order processed' &
sleep 40; curl -s -XPOST localhost:8080/api/orders -d '{"items":2}' -H 'Content-Type: application/json' >/dev/null
# {"timestamp":"…","level":"INFO","trace_id":"-","span_id":"-",…}   ← a dash when the SDK is off
kill %1 2>/dev/null

# deploy
kubectl apply -f manifests/shop-api-traced.yaml
kubectl -n shop rollout status deploy/shop-api --timeout=300s

# ── 2. Go: manual instrumentation (25 min) ───────────────────────
# copy from Case 2 §5: otel.go (the TracerProvider setup) and main.go
cd app/checkout && go mod tidy && cd ../..
docker build -t ghcr.io/3558bhk/checkout-traced:1.0.0 app/checkout
kind load docker-image ghcr.io/3558bhk/checkout-traced:1.0.0 --name obs
kubectl apply -f manifests/shop-services.yaml
kubectl -n shop rollout status deploy/checkout --timeout=180s

# ── 3. Python (10 min) — the entrypoint wrapper does it all ──────
docker build -t ghcr.io/3558bhk/order-worker-traced:1.0.0 app/order-worker
kind load docker-image ghcr.io/3558bhk/order-worker-traced:1.0.0 --name obs
kubectl -n shop rollout status deploy/order-worker --timeout=180s

# ── 4. ⭐⭐ THE PROPAGATION TEST (5 min) — the moment it all connects
kubectl -n shop scale deploy/loadgen --replicas=3
sleep 90
curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "shop-api" }' \
  --data-urlencode 'limit=3' | jq -r '.traces[] | "\(.traceID)\t\(.rootTraceName)\t\(.durationNanos/1e6|floor)ms"'

# pick one and inspect the whole chain
TID=$(curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "shop-api" }' \
      --data-urlencode 'limit=1' | jq -r '.traces[0].traceID')
curl -s "localhost:3200/api/traces/$TID" | jq -r '
  [.batches[] | (.resource.attributes[] | select(.key=="service.name") | .value.stringValue) as $s
   | .scopeSpans[].spans[] | "\($s)\t\(.name)\t\(.kind)"] | sort | .[]'
# shop-api    POST /api/orders                 SPAN_KIND_SERVER
# shop-api    validate-and-price-cart          SPAN_KIND_INTERNAL
# shop-api    SELECT shop.inventory            SPAN_KIND_CLIENT     ⭐ the JDBC span, free

# and the cross-service one, with an explicit traceparent:
TRACE_ID=$(openssl rand -hex 16); PARENT=$(openssl rand -hex 8); echo "$TRACE_ID"
kubectl -n shop exec deploy/checkout -- wget -qO- \
  --header="traceparent: 00-$TRACE_ID-$PARENT-01" --header="X-Customer-Tier: gold" \
  --post-data='' http://localhost:8080/checkout
sleep 20
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq -r '
  [.batches[].resource.attributes[] | select(.key=="service.name") | .value.stringValue] | unique | .[]'
# checkout
# shop-api      ⭐⭐ TWO SERVICES, ONE TRACE. PROPAGATION WORKS.
```

**The four Go things you must not forget** (and the ones people always do):
1. `otel.SetTextMapPropagator(propagation.TraceContext{})` — without it, **no propagation at all**.
2. `otelhttp.NewHandler(mux, …)` — creates the SERVER spans.
3. `propagator.Inject(ctx, HeaderCarrier(req.Header))` — writes `traceparent` outbound.
4. `provider.Shutdown(ctx)` before exit — **flushes the batch queue**. Skip it and you lose the last seconds of spans on every deploy.

---

## 🍽️ 18:15–19:00 — Dinner.

---

## H12 · 19:00–20:00 — The correlation wiring ⭐⭐ the payoff hour

**Deliverable:** metric → trace → log → metric in four clicks, no typing. Exemplars visible on the p99 panel. Trace IDs clickable in Loki logs.

```bash
cd ~/observability-learn/case2

# ── 1. the datasources with all three correlation blocks (25 min) ─
# copy Case 2 §1.3 VERBATIM. The three blocks that matter:
#   Prometheus → jsonData.exemplarTraceIdDestinations → datasourceUid: tempo
#   Tempo      → jsonData.tracesToLogs     → datasourceUid: loki, filterByTraceID: true
#   Tempo      → jsonData.tracesToMetrics  → datasourceUid: prometheus, with 3 queries
#   Loki       → jsonData.derivedFields    → matcherRegex: '"trace_id"\s*:\s*"(\w+)"' → tempo
kubectl apply -f manifests/grafana-datasources.yaml
sleep 30
kubectl logs -n monitoring deploy/kps-grafana -c grafana-sc-datasources --tail=10

# ⭐⭐ VERIFY THE WIRING FROM THE API — don't just look at the UI
curl -s -u admin:admin localhost:3000/api/datasources | jq '.[] | {uid, name, type}'
curl -s -u admin:admin localhost:3000/api/datasources/uid/prometheus \
  | jq '.jsonData.exemplarTraceIdDestinations'
# [{"name":"traceID","datasourceUid":"tempo","urlDisplayLabel":"View trace"}]   ✅
curl -s -u admin:admin localhost:3000/api/datasources/uid/tempo \
  | jq '.jsonData | {toLogs: .tracesToLogs.datasourceUid, toMetrics: .tracesToMetrics.datasourceUid, serviceMap: .serviceMap.datasourceUid}'
# {"toLogs":"loki","toMetrics":"prometheus","serviceMap":"prometheus"}   ✅
curl -s -u admin:admin localhost:3000/api/datasources/uid/loki \
  | jq '.jsonData.derivedFields[] | {name, matcherRegex, datasourceUid}'
# {"name":"TraceID","matcherRegex":"\"trace_id\"\\s*:\\s*\"(\\w+)\"","datasourceUid":"tempo"}   ✅

# ── 2. logs into Loki (15 min) ───────────────────────────────────
# copy Case 2 §8.1: the logs-config.yaml + the otel-logs-agent DaemonSet
kubectl create configmap otel-logs-config -n otel --from-file=config.yaml=collector/logs-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f manifests/otel-logs-agent.yaml
kubectl -n otel rollout status ds/otel-logs-agent --timeout=180s
sleep 90
curl -sG localhost:3100/loki/api/v1/labels | jq .
curl -sG localhost:3100/loki/api/v1/label/namespace/values | jq .
curl -sG localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="shop"} | json | trace_id != "-"' \
  --data-urlencode "start=$(date -d '-10 min' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" --data-urlencode 'limit=3' \
  | jq -r '.data.result[].values[][1]' | head -3
# {"timestamp":"…","level":"INFO","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736",…}
#                                       ⭐⭐ THE CORRELATION KEY IS IN YOUR LOGS

# ── 3. exemplars (10 min) ⭐ ─────────────────────────────────────
kubectl patch prometheus kps-kube-prometheus-stack-prometheus -n monitoring --type=merge \
  -p '{"spec":{"enableFeatures":["exemplar-storage","native-histogram","otlp-write-receiver"]}}'
kubectl -n monitoring rollout status sts/kps-kube-prometheus-stack-prometheus --timeout=300s
sleep 60
# does the app EMIT exemplars? (OpenMetrics format)
kubectl -n shop exec deploy/shop-api -- wget -qO- localhost:9090/prometheus \
  | grep -A3 '^http_server_requests_seconds_bucket' | grep '#' | head -3
# http_server_requests_seconds_bucket{…,le="0.5"} 1243 # {trace_id="4bf9…"} 0.412 1757412345.123
#                                                            ⭐ THE EXEMPLAR
curl -sG localhost:9090/api/v1/query_exemplars \
  --data-urlencode 'query=http_server_requests_seconds_count{namespace="shop"}' \
  --data-urlencode "start=$(date -d '-30 min' +%s)" --data-urlencode "end=$(date +%s)" | jq '.data | length'
# > 0   ✅

# ── 4. ⭐⭐ THE FOUR-CLICK LOOP (10 min) — DO THIS IN THE BROWSER ──
cat <<'MSG'
  1. open http://localhost:3000/d/10-shop-api-red
  2. hover the p99 line → a small GREEN DIAMOND appears on a data point
  3. CLICK IT → Tempo opens with that exact trace          ← click 1 and 2
  4. in the waterfall, click a span → "Logs for this span" ← click 3
  5. Loki opens, filtered to that trace_id                 ← click 4
  6. click any trace_id in a log line → back to Tempo
  7. click "Request rate" in the trace view → back to Prometheus

  ⭐ You have gone metric → trace → log → metric with ZERO typed queries.
     If any step needs a tab switch or a typed query, the wiring is incomplete.
     Go back to step 1 of this hour and check the three jsonData blocks.
MSG
```

---

## H13 · 20:00–21:00 — Tail sampling, self-monitoring, and breaking the Collector

**Deliverable:** tail sampling proven to keep 100% of errors at 10% of the volume; the Collector's own metrics scraped and alerted on; propagation deliberately broken and diagnosed.

```bash
cd ~/observability-learn/case2

# ── 1. prove tail sampling works (20 min) ⭐⭐ ────────────────────
sed -i 's/sampling_percentage: 10/sampling_percentage: 0/' collector/gateway-config.yaml
kubectl create cm otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n otel rollout restart deploy/otel-collector-gateway
kubectl -n otel rollout status deploy/otel-collector-gateway
kubectl -n shop scale deploy/loadgen --replicas=4
sleep 180

SENT=$(curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "checkout" }' --data-urlencode 'limit=1000' | jq '.traces | length')
ERR=$(curl -sG localhost:3200/api/search --data-urlencode 'q={ status = error }' --data-urlencode 'limit=1000' | jq '.traces | length')
SLOW=$(curl -sG localhost:3200/api/search --data-urlencode 'q={ duration > 1s }' --data-urlencode 'limit=1000' | jq '.traces | length')
ACC=$(curl -s localhost:8888/metrics | awk '/^otelcol_receiver_accepted_spans/{s+=$2}END{print s}')
DROPPED=$(curl -s localhost:8888/metrics | awk '/^otelcol_processor_dropped_spans/{s+=$2}END{print s}')
echo "  traces kept:      $SENT"
echo "  error traces:     $ERR   ⭐ must be ALL of them"
echo "  slow traces:      $SLOW  ⭐ must be ALL of them"
echo "  spans accepted:   $ACC"
echo "  spans dropped:    $DROPPED"
awk "BEGIN{printf \"  reduction:        %.1f%%\n\", 100*$DROPPED/$ACC}"
# ⭐⭐ THAT NUMBER IS THE BUSINESS CASE FOR TAIL SAMPLING.

sed -i 's/sampling_percentage: 0/sampling_percentage: 10/' collector/gateway-config.yaml
kubectl create cm otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n otel rollout restart deploy/otel-collector-gateway
kubectl -n shop scale deploy/loadgen --replicas=1

# ── 2. self-monitoring the Collector (15 min) ────────────────────
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: otel-collector, namespace: otel, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: otel-gateway}}
  endpoints: [{port: metrics, path: /metrics, interval: 30s}]
EOF
sleep 60
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=sum(rate(otelcol_receiver_accepted_spans[5m]))' | jq .
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=sum(rate(otelcol_processor_dropped_spans[5m]))' | jq .
kubectl apply -f otel-self-alerts.yaml          # Case 2 §11 — the 7 Collector alerts
promtool check rules otel-self-alerts.yaml

# ── 3. break propagation and diagnose it (15 min) ⭐⭐ ────────────
kubectl -n shop set env deploy/checkout OTEL_PROPAGATORS=none
kubectl -n shop rollout status deploy/checkout
sleep 30
TRACE_ID=$(openssl rand -hex 16); PARENT=$(openssl rand -hex 8)
kubectl -n shop exec deploy/checkout -- wget -qO- \
  --header="traceparent: 00-$TRACE_ID-$PARENT-01" --post-data='' http://localhost:8080/checkout
sleep 25
curl -s "localhost:3200/api/traces/$TRACE_ID" | jq -r '.batches[].scopeSpans[].spans[].name'
# ⛔ only "POST /api/orders" — the checkout spans are in a DIFFERENT trace

# ⭐ THE DIAGNOSTIC TECHNIQUE — find SERVER spans with no parent
curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "checkout" }' \
  --data-urlencode 'limit=5' | jq -r '.traces[].traceID' | while read t; do
    curl -s "localhost:3200/api/traces/$t" | jq -r --arg t "$t" '
      [.batches[].scopeSpans[].spans[]] as $s |
      "\($t)  spans=\($s|length)  roots=\([$s[] | select(.parentSpanId==null or .parentSpanId=="")] | length)"'
  done
# roots=1 for EVERY trace from checkout  ⭐ they're all orphan roots

# and check the propagator consistency across every service
for d in $(kubectl -n shop get deploy -o name); do
  printf '  %-30s %s\n' "$d" "$(kubectl -n shop get $d -o jsonpath='{.spec.template.spec.containers[0].env}' \
    | jq -r '.[] | select(.name=="OTEL_PROPAGATORS") | .value' 2>/dev/null)"
done
# ⛔ deploy.apps/checkout     none       ← the odd one out

kubectl -n shop set env deploy/checkout OTEL_PROPAGATORS=tracecontext,baggage
kubectl -n shop rollout restart deploy/checkout

# ── 4. starve the Collector (10 min) ─────────────────────────────
sed -i 's/limit_percentage: 80/limit_percentage: 5/' collector/gateway-config.yaml
kubectl create cm otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n otel rollout restart deploy/otel-collector-gateway && sleep 40
kubectl -n otel logs deploy/otel-collector-gateway --tail=30 | grep -iE 'refus|memory|dropp'
# {"level":"warn","msg":"Memory usage is above hard limit. Dropping data.","cur_mem_mib":…}
curl -s localhost:8888/metrics | grep otelcol_processor_refused_spans
# ⭐⭐ THE LESSON: WITH memory_limiter, the Collector sheds load and STAYS UP.
#    WITHOUT it, it OOMKills, restarts, and drops everything in the batch queue.
sed -i 's/limit_percentage: 5/limit_percentage: 80/' collector/gateway-config.yaml
kubectl create cm otel-gateway-config -n otel --from-file=config.yaml=collector/gateway-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n otel rollout restart deploy/otel-collector-gateway
```

---

## H14 · 21:00–22:00 — The incident dashboard and the final smoke test

**Deliverable:** the one-click incident dashboard deployed; the 8-check pipeline smoke test passing; everything committed to Git.

```bash
cd ~/observability-learn

# ── 1. generate the incident + observability-health dashboards (20 min) ─
# copy scripts/generate-dashboards.py from Capstone Phase 4 §4.2
mkdir -p platform/grafana/dashboards
python3 scripts/generate-dashboards.py
#   ✅ 99-incident.json  (28 panels)
#   ✅ 40-observability-health.json  (24 panels)
#   ✅ 30-slo.json  (8 panels)

# provision them
for f in platform/grafana/dashboards/*.json; do
  name=$(basename "$f" .json)
  kubectl -n monitoring create configmap "grafana-dashboard-$name" --from-file="$name.json=$f" \
    --dry-run=client -o yaml \
    | yq '.metadata.labels."grafana_dashboard" = "1" | .metadata.annotations."grafana_folder" = "Shop"' \
    | kubectl apply -f -
done
sleep 40
kubectl logs -n monitoring deploy/kps-grafana -c grafana-sc-dashboard --tail=10
curl -s -u admin:admin 'localhost:3000/api/search?type=dash-db' | jq -r '.[] | "\(.uid)\t\(.title)"'

# ── 2. ⭐ THE FINAL SMOKE TEST (20 min) ──────────────────────────
# copy scripts/validate-trace-pipeline.sh from Capstone Phase 5 §5.2
chmod +x scripts/validate-trace-pipeline.sh
./scripts/validate-trace-pipeline.sh
```

**The output you're aiming for:**

```
==> 1. platform components
  ✅ monitoring/kps-kube-prometheus-stack-prometheus: 1 running
  ✅ monitoring/kps-grafana: 1 running
  ✅ monitoring/tempo: 1 running
  ✅ monitoring/loki: 1 running
  ✅ otel/otel-agent: 3 running
  ✅ otel/otel-collector-gateway: 2 running
==> 2. Prometheus targets
  ✅ all targets up
==> 3. the manual-span probe
  ✅ the Collector accepted a span (…)
  ✅ the span reached Tempo
==> 4. Tempo search
  ✅ TraceQL search works (1 results)
==> 5. Loki logs with trace context
  ✅ 5 log lines carry a trace_id
==> 6. exemplars in Prometheus
  ✅ the exemplar query returned (12 series with exemplars)
==> 7. the Collector is not dropping anything
  ✅ zero dropped, zero failed spans
==> 8. cross-service propagation
  ✅ at least one trace spans 3 services — propagation works

8 passed, 0 failed
✅ the telemetry pipeline is healthy
```

```bash
# ── 3. the demo run — rehearse it, you'll be asked to show it (10 min) ──
kubectl -n shop scale deploy/loadgen --replicas=4
kubectl -n shop exec deploy/loadgen -- sh -c 'for i in $(seq 1 300); do curl -s -o /dev/null http://shop-api/api/flaky; done' &
sleep 60
# NOW, IN THE BROWSER, WITHOUT TYPING A SINGLE QUERY:
#   1. http://localhost:3000/d/99-incident
#   2. ROW 0: the burn rate has moved. ROW 1: the service graph shows a red edge.
#   3. ROW 2: the error panel spiked; hover the p99 → green diamond → click
#   4. Tempo waterfall: the slow span. Click "Logs for this span"
#   5. Loki: the ERROR line with the trace_id
#   6. ROW 4: the error-trace table — click a row
#   ⏱️ TIME IT. Under 90 seconds from "something is wrong" to "here is the log line".
kubectl -n shop scale deploy/loadgen --replicas=1

# ── 4. commit everything (10 min) ────────────────────────────────
cd ~/observability-learn
git add -A
git status --short | head -30
git commit -m "observability platform: Prometheus+Grafana (case 1), OpenTelemetry (case 2)

- kube-prometheus-stack 72.x: Prometheus v3.13.2, Grafana 12.3.1, Alertmanager 0.28.1
- Tempo 2.6.1 (search + metricsGenerator), Loki 3.7.5
- OTel Collector 0.158.0: agent DaemonSet + gateway Deployment, tail sampling
- 3 instrumented services: Spring Boot (Micrometer + Java agent), Go (manual SDK),
  Python (opentelemetry-instrument)
- 12 recording rules, 25 alerting rules across 4 tiers, 2 sloth SLOs (16 generated rules)
- full Grafana correlation: exemplars, tracesToLogs, tracesToMetrics, derivedFields
- 4 dashboards generated from a script and provisioned via the sidecar
- scripts/validate-trace-pipeline.sh: the 8-check smoke test, passing 8/8"
# ⭐ push it somewhere public. It's the artefact you show in interviews.
```

---

## ✅ End-of-day checklist

```
MORNING — CASE 1
  □ H1  5 services running in namespace `shop` with live traffic
  □ H2  kube-prometheus-stack installed; 30+ targets up; Grafana showing cluster data
  □ H3  all 20 PromQL query families typed by hand and understood
  □ H4  3 services instrumented: Java/Go/Python, histograms on, SLO-aligned buckets
  □ H5  3 ServiceMonitors + 1 Probe up; 12 recording rules producing series
  □ H6  18+ alerting rules healthy; routing tested with `amtool config routes test`;
        a test alert delivered to a webhook; a silence created and removed
  □ H7  the RED dashboard provisioned from a ConfigMap; deploy annotations visible;
        5 classic dashboards imported
  □ H8  2 SLOs generating 16 multi-window burn-rate rules; the burn rate observed
        crossing 14.4×; an HPA scaling on a custom Prometheus metric
  □ H9  5 failures injected; the SCORECARD.md filled in with detection times;
        false positives and missed detections recorded

AFTERNOON — CASE 2
  □ H10 Tempo + Loki installed; the Collector as agent AND gateway;
        ⭐ a hand-crafted span retrieved from Tempo by ID
  □ H11 Java zero-code agent; Go manual SDK; a single request producing ONE trace
        across two services, verified with an explicit traceparent
  □ H12 all three correlation blocks verified from the Grafana API; logs in Loki
        carrying trace_id; exemplars present in the /metrics output;
        ⭐⭐ the four-click loop performed in the browser
  □ H13 tail sampling measured (error/slow traces 100% preserved, ~90% volume cut);
        the Collector's metrics scraped and alerted on; propagation broken and
        diagnosed via "SERVER spans with no parent"; memory_limiter proven
  □ H14 the incident + observability-health dashboards provisioned;
        validate-trace-pipeline.sh passing 8/8; everything committed to Git

THE ONE SENTENCE TEST
  □ you can explain, out loud, in 90 seconds, how a request becomes a metric,
    a trace and a log, and how clicking one takes you to the other two
```

---

## If the day goes wrong

| Symptom | The fix | Time cost |
|---|---|---|
| The kind cluster won't start | `docker system prune -af && kind delete cluster --name obs && kind create cluster …` | 10 min |
| A Helm install times out | `helm uninstall X -n monitoring` then reinstall; check `kubectl describe pod` for ImagePullBackOff | 15 min |
| Targets are all down | The ServiceMonitor's `port:` must be the Service's port **name**; Spring Boot's path is `/prometheus` | 20 min |
| No histogram data | `percentiles-histogram: true` is missing, or you forgot `sum by (le)` | 10 min |
| Grafana shows "Datasource not found" | The datasource `uid` in the dashboard JSON doesn't match the provisioned one | 10 min |
| No traces | Run the manual-span probe from H10 step 4. If that fails, it's the Collector, not your app | 20 min |
| Traces exist but are split | `OTEL_PROPAGATORS` differs between services | 10 min |
| No exemplar diamonds | `exemplar-storage` isn't enabled, or the app doesn't emit OpenMetrics | 15 min |
| The Collector is CrashLooping | `kubectl logs --previous`; it's almost always a config typo or `memory_limiter` not first | 15 min |
| Loki shows nothing | `compactor.retention_enabled`, the `filelog` include path, or the container can't read `/var/log/pods` | 20 min |

**Total worst-case slippage: ~3 hours.** That's why the `⏭ SKIP` markers exist. If you're behind at 13:00, drop H7 step 5 (the imported dashboards) and H8 step 4 (the HPA) — they're the least load-bearing. **Never drop H3 (PromQL), H9 (break it), H10 step 4 (the manual span probe) or H12 (correlation).** Those four hours are the difference between "I installed something" and "I understand this."

---

## The 2-day split (recommended)

If you have two days, this is a much better use of them — the same hours, with the space to actually understand:

| | Day 1 (7 h) | Day 2 (7 h) |
|---|---|---|
| Morning | H1 cluster + apps · H2 kube-prometheus-stack · H3 PromQL by hand | H10 Tempo + Loki + Collector · H11 instrument for traces |
| Afternoon | H4 instrument the apps · H5 ServiceMonitors + recording rules | H12 correlation wiring · H13 tail sampling + self-monitoring |
| Evening | H6 alerting + Alertmanager · **write up what you learned** | H14 incident dashboard + smoke test · **the game day (Capstone Phase 7)** |

And then a **day 3** for the [Capstone](./04-CAPSTONE-END-TO-END.md): the GitOps repo, the CI validation, the five game-day scenarios, and the five capstone tasks. That's the version that gets you the job.

---

## Related files

| File | What's in it |
|---|---|
| [README.md](./README.md) | The index and the learning path |
| [01-OBSERVABILITY-GUIDE.md](./01-OBSERVABILITY-GUIDE.md) | **Read this first** — all the theory |
| [02-CASE-1-prometheus-grafana.md](./02-CASE-1-prometheus-grafana.md) | The morning, in full detail |
| [03-CASE-2-telemetry.md](./03-CASE-2-telemetry.md) | The afternoon, in full detail |
| [04-CAPSTONE-END-TO-END.md](./04-CAPSTONE-END-TO-END.md) | Day 3: the GitOps platform, CI, the game day |
| [05-CHEATSHEET.md](./05-CHEATSHEET.md) | Keep it open all day |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
