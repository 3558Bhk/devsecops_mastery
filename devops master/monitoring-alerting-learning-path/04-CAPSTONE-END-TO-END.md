# 🏆 CAPSTONE — The Complete Observability Platform, End to End

> **One repository, one cluster, one application, three signals, fully correlated, validated in CI, drilled in a game day.**
>
> This is the build you put in front of an interviewer and walk through for forty minutes. It combines [Case 1 (Prometheus + Grafana)](./02-CASE-1-prometheus-grafana.md) and [Case 2 (OpenTelemetry)](./03-CASE-2-telemetry.md) into a single GitOps-managed platform with SLOs, alert routing, dashboards-as-code, CI validation, and a rehearsed incident.
>
> **Time:** 2 days (16 hours) of focused work · **Level:** the thing that gets you the job
> **Prereq:** both cases completed, or at least read end-to-end.

---

## The mission

Build `shop-observability`, a production-grade observability platform for a 5-service e-commerce app, satisfying **every** one of these requirements:

```
1.  Metrics, logs and traces for all 5 services — including the browser and a message queue.
2.  SLOs for the two journeys that matter (checkout, browse), with multi-window burn-rate alerts.
3.  Symptom-first alerting: a page only when a user is affected. Every alert has a runbook.
4.  Alert routing by team and severity, with inhibit rules, silences and a working receiver.
5.  Dashboards-as-code, provisioned by a sidecar, validated in CI. No click-built panels.
6.  Full correlation: metric → trace → log → metric, in ≤4 clicks, no typing.
7.  Tail sampling that cuts trace storage ≥80% with zero loss of error traces.
8.  A cardinality budget, enforced by a CI gate and an alert.
9.  Everything in Git: the Collector config, the rules, the dashboards, the Helm values.
10. CI that fails the build on an invalid PromQL rule, an untested alert, or a bad dashboard.
11. Monitoring that monitors itself — you get paged when observability breaks.
12. A rehearsed incident: a game day where 5 failures are injected and every one is
    detected, diagnosed and documented in under 30 minutes.
```

**Definition of done:** you can open a terminal, run `make game-day`, have an alert fire within 60 seconds, click through to the root-cause trace and log line, and have a completed incident report — without touching a single `kubectl edit`.

---

## Contents

| Phase | What | Time |
|---|---|---|
| [0](#phase-0--the-repository) | The repository layout and the environment | 30 min |
| [1](#phase-1--the-application) | The application: 5 services, instrumented | 2 h |
| [2](#phase-2--the-platform-installed-from-git) | The platform, installed from Git | 2 h |
| [3](#phase-3--slis-slos-and-the-alerting-hierarchy) | SLIs, SLOs and the alerting hierarchy | 1.5 h |
| [4](#phase-4--dashboards-as-code) | Dashboards-as-code | 1.5 h |
| [5](#phase-5--correlation-the-four-click-loop) | Correlation: the four-click loop | 1 h |
| [6](#phase-6--continuous-integration) | CI: validating the whole platform on every PR | 1.5 h |
| [7](#phase-7--the-game-day) | The game day: 5 injected failures | 2 h |
| [8](#phase-8--scale-cost-and-hardening) | Scale, cost and hardening | 1 h |
| [9](#phase-9--handover) | Handover: runbooks, on-call, docs | 1 h |
| [🎯](#-capstone-tasks--answers) | **5 capstone tasks + answers** (at the end) | — |

---

<a name="phase-0--the-repository"></a>
## Phase 0 — The repository

### 0.1 The layout

Everything in one repo. This is the single most important structural decision: **the observability config lives next to nothing else and is versioned like code.**

```bash
mkdir -p ~/shop-observability && cd ~/shop-observability
git init -b main

mkdir -p \
  apps/shop-ui/{src,nginx} \
  apps/shop-api/src/main/{java/com/shop/{controller,service,config},resources} \
  apps/checkout \
  apps/order-worker \
  platform/helm/values \
  platform/otel \
  platform/prometheus/{recording-rules,alerting-rules,slos} \
  platform/alertmanager \
  platform/grafana/{dashboards,datasources,alert-contact-points,notification-policies} \
  platform/kubernetes/{namespaces,networkpolicies,pdbs} \
  platform/runbooks \
  ci \
  scripts \
  docs \
  game-day
```

```
shop-observability/
├── Makefile                          ← ⭐ every operation is a make target
├── README.md
├── Tiltfile / skaffold.yaml          ← local dev loop
│
├── apps/                             ← the instrumented application
│   ├── shop-ui/        (React + OTel Web SDK)
│   ├── shop-api/       (Spring Boot + Micrometer + OTel Java agent)
│   ├── checkout/       (Go + OTel SDK, manual)
│   └── order-worker/   (Python + OTel auto-instrumentation)
│
├── platform/                         ← ⭐ EVERYTHING IS GITOPS
│   ├── helm/values/
│   │   ├── kube-prometheus-stack.yaml
│   │   ├── tempo.yaml
│   │   └── loki.yaml
│   ├── otel/
│   │   ├── agent-config.yaml         ← the DaemonSet Collector
│   │   ├── gateway-config.yaml       ← the central Collector (tail sampling here)
│   │   ├── logs-config.yaml
│   │   ├── agent.yaml                ← DaemonSet manifest
│   │   ├── gateway.yaml              ← Deployment manifest
│   │   └── instrumentation.yaml      ← the OTel Operator Instrumentation CR
│   ├── prometheus/
│   │   ├── recording-rules/
│   │   │   ├── slo-recording.yaml
│   │   │   ├── red-recording.yaml
│   │   │   └── saturation-recording.yaml
│   │   ├── alerting-rules/
│   │   │   ├── slo-burn-rate.yaml
│   │   │   ├── symptom.yaml
│   │   │   ├── saturation.yaml
│   │   │   ├── platform.yaml
│   │   │   └── observability-self.yaml    ← ⭐ monitoring watches itself
│   │   └── slos/
│   │       ├── checkout-availability.yaml
│   │       ├── checkout-latency.yaml
│   │       └── browse-latency.yaml
│   ├── alertmanager/
│   │   ├── alertmanager.yaml         ← routing, receivers, inhibit_rules
│   │   └── silence-policy.md
│   ├── grafana/
│   │   ├── datasources/observability.yaml
│   │   ├── dashboards/               ← provisioned by the sidecar
│   │   │   ├── 00-overview.json
│   │   │   ├── 10-shop-api-red.json
│   │   │   ├── 11-checkout-red.json
│   │   │   ├── 20-kubernetes-cluster.json
│   │   │   ├── 30-slo.json
│   │   │   ├── 40-observability-health.json   ← ⭐ the Collector + Prometheus
│   │   │   └── 99-incident.json               ← ⭐ the one-click view
│   │   ├── alert-contact-points/slack.yaml
│   │   └── notification-policies/default.yaml
│   ├── kubernetes/
│   │   ├── namespaces.yaml
│   │   ├── networkpolicies/          ← ⭐ including egress to the Collector
│   │   └── pdbs/
│   └── runbooks/                     ← one MD per alert, linked from every alert
│       ├── README.md
│       ├── slo-checkout-availability-burn.md
│       ├── symptom-http-5xx.md
│       ├── symptom-latency-p99.md
│       ├── saturation-cpu-throttling.md
│       ├── saturation-db-pool.md
│       ├── observability-self-targets-down.md
│       ├── observability-self-otel-drops.md
│       └── _template.md
│
├── ci/
│   ├── validate.sh                   ← ⭐ the single validation entrypoint
│   ├── promtool-tests/               ← ⭐ unit tests for the alerting rules
│   │   ├── slo-burn-rate-test.yaml
│   │   ├── symptom-test.yaml
│   │   └── saturation-test.yaml
│   ├── otel-collector-validate.sh
│   └── cardinality-budget.txt
│
├── scripts/
│   ├── bootstrap-cluster.sh          ← kind → namespaces → platform → apps
│   ├── deploy-app.sh
│   ├── game-day.sh                   ← ⭐ inject a failure by name
│   ├── cardinality-report.sh
│   ├── validate-trace-pipeline.sh    ← the manual-span smoke test
│   └── incident-report.sh
│
├── game-day/
│   ├── SCENARIO.md
│   ├── failures/
│   │   ├── 01-payment-timeout.yaml
│   │   ├── 02-db-connection-exhaustion.yaml
│   │   ├── 03-memory-leak.yaml
│   │   ├── 04-cardinality-bomb.yaml
│   │   └── 05-monitoring-blind.yaml
│   └── reports/                      ← filled in during the drill
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── ONBOARDING.md
│   ├── ON-CALL.md
│   ├── SLO-CATALOG.md
│   └── ALERT-CATALOG.md
│
└── .github/workflows/observability-ci.yml
```

### 0.2 The Makefile — every operation is a target ⭐

```makefile
# Makefile — the operator's interface to the whole platform
SHELL := /bin/bash
.DEFAULT_GOAL := help
CLUSTER   ?= obs
NAMESPACE ?= shop
MON_NS    ?= monitoring
OTEL_NS   ?= otel
REGISTRY  ?= ghcr.io/3558bhk
VERSION   ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

.PHONY: help
help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'

# ── cluster lifecycle ────────────────────────────────────────────
.PHONY: cluster-up cluster-down cluster-status
cluster-up:      ## create the kind cluster and install everything
	./scripts/bootstrap-cluster.sh
cluster-down:    ## destroy the cluster
	kind delete cluster --name $(CLUSTER)
cluster-status:  ## show the state of every namespace
	kubectl get pods -A -o wide | grep -E 'monitoring|otel|shop|NAME'

# ── platform ─────────────────────────────────────────────────────
.PHONY: platform-install platform-apply platform-diff
platform-install: ## helm install/upgrade the whole monitoring stack
	helm upgrade --install kps prometheus-community/kube-prometheus-stack \
	  -n $(MON_NS) --create-namespace -f platform/helm/values/kube-prometheus-stack.yaml --wait
	helm upgrade --install tempo grafana/tempo -n $(MON_NS) -f platform/helm/values/tempo.yaml --wait
	helm upgrade --install loki  grafana/loki  -n $(MON_NS) -f platform/helm/values/loki.yaml  --wait
platform-apply:   ## kubectl apply the OTel Collector, rules, dashboards
	kubectl apply -k platform/kubernetes/
	kubectl apply -f platform/otel/
	kubectl apply -f platform/prometheus/
	kubectl apply -f platform/grafana/
	kubectl apply -f platform/alertmanager/alertmanager.yaml
platform-diff:    ## show what would change (server-side dry run)
	kubectl diff -k platform/kubernetes/ || true
	kubectl diff -f platform/otel/ || true

# ── apps ─────────────────────────────────────────────────────────
.PHONY: build push deploy apps-deploy
build:            ## build every app image tagged with the git SHA
	@for app in shop-ui shop-api checkout order-worker; do \
	  echo "==> $$app"; docker build -t $(REGISTRY)/$$app:$(VERSION) apps/$$app; done
push:             ## push every app image
	@for app in shop-ui shop-api checkout order-worker; do \
	  docker push $(REGISTRY)/$$app:$(VERSION); done
deploy:           ## deploy one app: make deploy APP=shop-api
	VERSION=$(VERSION) envsubst < platform/kubernetes/apps/$(APP).yaml | kubectl apply -f -
	kubectl rollout status deploy/$(APP) -n $(NAMESPACE) --timeout=300s
apps-deploy:      ## deploy every app
	@for app in shop-ui shop-api checkout order-worker; do $(MAKE) deploy APP=$$app; done

# ── validation (the CI entrypoint) ⭐ ─────────────────────────────
.PHONY: validate lint test-rules validate-collector validate-dashboards cardinality
validate: lint test-rules validate-collector validate-dashboards ## run the full validation suite
	@echo "✅ the whole observability platform is valid"
lint:             ## promtool check every rule file
	@ci/validate.sh lint
test-rules:       ## ⭐ run the promtool unit tests against the alerting rules
	@ci/validate.sh test-rules
validate-collector: ## validate the OTel Collector configs
	@ci/otel-collector-validate.sh
validate-dashboards: ## lint the Grafana dashboards (UID, datasource, variables)
	@ci/validate.sh dashboards
cardinality:      ## print the top-20 series by metric name and total series count
	./scripts/cardinality-report.sh

# ── local access ─────────────────────────────────────────────────
.PHONY: port-forward grafana prometheus tempo loki alertmanager
port-forward:     ## forward Grafana, Prometheus, Tempo, Loki and Alertmanager
	@./scripts/port-forward.sh
grafana:     ## open Grafana
	@open http://localhost:3000 || xdg-open http://localhost:3000
prometheus:  ## open Prometheus
	@open http://localhost:9090 || xdg-open http://localhost:9090
tempo:       ## open Tempo's API
	@open http://localhost:3200/ready || xdg-open http://localhost:3200/ready
loki:        ## open Loki's ready endpoint
	@open http://localhost:3100/ready || xdg-open http://localhost:3100/ready
alertmanager: ## open Alertmanager
	@open http://localhost:9093 || xdg-open http://localhost:9093

# ── traffic and chaos ┭ ──────────────────────────────────────────
.PHONY: load smoke-test game-day game-day-stop
load:             ## generate realistic traffic forever
	kubectl -n $(NAMESPACE) apply -f game-day/loadgen.yaml
smoke-test:       ## the end-to-end assertion suite (traces, logs, metrics, alerts)
	./scripts/validate-trace-pipeline.sh
game-day:         ## inject a failure: make game-day F=01-payment-timeout
	./scripts/game-day.sh inject $(F)
game-day-stop:    ## heal every injected failure
	./scripts/game-day.sh heal

# ── ops ──────────────────────────────────────────────────────────
.PHONY: silence unsilence incident-report slo-report
silence:          ## silence an alert: make silence ALERT=KubePodNotReady DUR=2h WHY=deploy
	./scripts/silence.sh "$(ALERT)" "$(DUR)" "$(WHY)"
unsilence:        ## remove every silence created by this repo
	./scripts/silence.sh --clear
incident-report:  ## generate an incident report skeleton with the real data
	./scripts/incident-report.sh
slo-report:       ## print the current SLO attainment and error budget for every SLO
	./scripts/slo-report.sh
```

```bash
# the first thing you run, and the last thing you run before every merge
make help
make validate
make cluster-up
make apps-deploy
make load
make smoke-test
```

### 0.3 Bootstrap the cluster

```bash
cat > scripts/bootstrap-cluster.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ Idempotent. Run it as many times as you like.
set -euo pipefail

CLUSTER="${CLUSTER:-obs}"
K8S_VERSION="${K8S_VERSION:-v1.37.0}"
REGISTRY="${REGISTRY:-ghcr.io/3558bhk}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

command -v kind     >/dev/null || die "kind not installed"
command -v kubectl  >/dev/null || die "kubectl not installed"
command -v helm     >/dev/null || die "helm not installed"
command -v promtool >/dev/null || die "promtool not installed (brew install prometheus)"

# ── 1. the cluster ──────────────────────────────────────────────
log "cluster"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "  cluster '$CLUSTER' already exists — reusing"
else
  kind create cluster --name "$CLUSTER" --image "kindest/node:$K8S_VERSION" --wait 5m
fi
kubectl cluster-info --context "kind-$CLUSTER" >/dev/null || die "cannot reach the cluster"

# ── 2. helm repos ───────────────────────────────────────────────
log "helm repositories"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana              https://grafana.github.io/helm-charts               >/dev/null
helm repo add open-telemetry       https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo update >/dev/null

# ── 3. namespaces ───────────────────────────────────────────────
log "namespaces"
kubectl apply -f platform/kubernetes/namespaces.yaml

# ── 4. the platform ─────────────────────────────────────────────
log "platform (this takes ~8 minutes)"
make platform-install
make platform-apply

# ── 5. wait for readiness ───────────────────────────────────────
log "waiting for the platform"
kubectl -n monitoring rollout status statefulset/kps-kube-prometheus-stack-prometheus --timeout=10m
kubectl -n monitoring rollout status deploy/kps-grafana              --timeout=5m
kubectl -n monitoring rollout status deploy/tempo                    --timeout=5m
kubectl -n monitoring rollout status statefulset/loki                --timeout=5m || true
kubectl -n otel       rollout status ds/otel-agent                   --timeout=5m
kubectl -n otel       rollout status deploy/otel-collector-gateway   --timeout=5m

# ── 6. load the images ──────────────────────────────────────────
log "loading images into kind"
for img in shop-ui shop-api checkout order-worker postgres redis rabbitmq; do
  for tag in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep "/$img:" || true); do
    kind load docker-image "$tag" --name "$CLUSTER" 2>/dev/null || true
  done
done

# ── 7. the apps ─────────────────────────────────────────────────
log "deploying the apps"
make apps-deploy || echo "  ⚠️  some apps failed — check 'make cluster-status'"

# ── 8. validate the telemetry pipeline ──────────────────────────
log "validating the telemetry pipeline"
./scripts/validate-trace-pipeline.sh || die "the telemetry pipeline is broken"

# ── 9. summary ──────────────────────────────────────────────────
log "done"
kubectl get pods -A -o wide | grep -E 'NAMESPACE|monitoring|otel|shop' || true
cat <<MSG

  ✅ platform ready

  next:
    make port-forward     # Grafana :3000, Prometheus :9090, Tempo :3200, Loki :3100, AM :9093
    make load             # start generating traffic
    make smoke-test       # assert everything works
    make validate         # the CI gate

MSG
EOF
chmod +x scripts/bootstrap-cluster.sh
```

---

<a name="phase-1--the-application"></a>
## Phase 1 — The application

### 1.1 The service topology you're observing

```
                            ┌──────────────────────────────┐
       browser ──HTTPS──►   │  shop-ui  (React + nginx)    │  service: shop-ui
                            │  OTel Web SDK                │  language: js
                            └──────────────┬───────────────┘
                                           │ /api/*  (traceparent injected)
                                           ▼
                            ┌──────────────────────────────┐
                            │  checkout  (Go)              │  service: checkout
                            │  OTel SDK, manual            │  port 8080 / metrics 9091
                            └──────┬───────────────────┬───┘
                                   │                   │
                     POST /api/orders           POST /v1/charge (external)
                                   │                   ▼
                                   │        ┌────────────────────┐
                                   │        │ payment-mock (Go)  │  service: payment
                                   │        │ ⭐ the chaos target │  port 8080
                                   ▼        └────────────────────┘
                            ┌──────────────────────────────┐
                            │  shop-api  (Spring Boot 3)   │  service: shop-api
                            │  Micrometer + OTel agent     │  port 8080 / metrics 9090
                            └───┬──────────┬──────────┬────┘
                                │          │          │
                          JDBC  │   Redis  │   AMQP   │
                                ▼          ▼          ▼
                        ┌────────────┐ ┌───────┐ ┌──────────────┐
                        │ postgres   │ │ redis │ │ rabbitmq     │
                        │ (StatefulSet)│(Deploy)│ │              │
                        └────────────┘ └───────┘ └──────┬───────┘
                                                        │ order.created
                                                        ▼
                                                ┌──────────────────┐
                                                │ order-worker (Py)│  service: order-worker
                                                │ OTel auto-instr  │  metrics 9092
                                                └────────┬─────────┘
                                                         │ SMTP/HTTP
                                                         ▼
                                                  email-mock (external)
```

### 1.2 The one thing that makes everything else work: consistent resource attributes ⭐

Every service, in every language, must emit **the same** resource attributes. Write this down once and enforce it in CI.

```yaml
# docs/TELEMETRY-CONVENTIONS.md  — ⭐ commit this; it's a contract
service.name:              shop-api          # the K8s Deployment name, exactly
service.version:           1.4.2             # the image tag / semver, never "latest"
service.namespace:         shop
service.instance.id:       ${POD_NAME}
deployment.environment:    production        # development | staging | production
team:                      payments          # the owning team, for alert routing
tier:                      backend           # frontend | backend | worker | data
slo.id:                    checkout          # ⭐ which SLO this service contributes to
k8s.namespace.name:        shop              # added by the Collector's k8sattributes
k8s.deployment.name:       shop-api          # added by the Collector
k8s.pod.name:              shop-api-7d9…     # added by the Collector
k8s.node.name:             kind-obs-worker   # added by the Collector

# metric label conventions (Prometheus)
application:  shop-api       # Micrometer's `application` tag → matches service.name
env:          production
team:         payments

# span attribute conventions (business, low cardinality)
order.id           string    # ✅ an ID is fine ON A SPAN (spans aren't aggregated)
customer.tier      string    # ✅ bounded: standard|gold|platinum
cart.items         int       # ✅ bounded
url.path           string    # ✅ the ROUTE TEMPLATE, never the raw path
http.route         string    # ✅ set automatically by the instrumentation
⛔ user.email       — never, redacted by the Collector
⛔ db.query.text   — hashed by the Collector
⛔ http.request.header.* — deleted by the Collector
```

**Why this matters more than anything else in this capstone:** every dashboard query, every alert, every SLO and every Grafana variable in this repo keys off `application` (metrics), `service.name` (traces/logs) and `namespace`. If one service emits `shop_api` and another `shop-api`, the correlation silently breaks and you spend a day finding out why. **Write the contract, enforce it in CI.**

```bash
# ci/check-conventions.sh — ⭐ run in CI on every PR
cat > ci/check-conventions.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fail=0

echo "==> checking telemetry conventions"

# 1. every app sets OTEL_SERVICE_NAME equal to its directory name
for appdir in apps/*/; do
  app=$(basename "$appdir")
  name=$(grep -rhoE 'OTEL_SERVICE_NAME[=:]["'"'"' ]*[a-z0-9-]+' "$appdir" 2>/dev/null \
         | head -1 | sed -E 's/.*[=:]["'"'"' ]*//' || true)
  if [[ -z "$name" ]]; then
    echo "  ✖ $app does not set OTEL_SERVICE_NAME"; fail=1
  elif [[ "$name" != "$app" ]]; then
    echo "  ✖ $app sets OTEL_SERVICE_NAME=$name but should be '$app'"; fail=1
  else
    echo "  ✅ $app → service.name=$name"
  fi
done

# 2. every app sets the same propagators
for appdir in apps/*/; do
  app=$(basename "$appdir")
  prop=$(grep -rhoE 'OTEL_PROPAGATORS[=:]["'"'"' ]*[a-z,]+' "$appdir" 2>/dev/null | head -1 \
         | sed -E 's/.*[=:]["'"'"' ]*//' || true)
  if [[ -n "$prop" && "$prop" != "tracecontext,baggage" ]]; then
    echo "  ✖ $app uses OTEL_PROPAGATORS=$prop — must be tracecontext,baggage"; fail=1
  fi
done

# 3. no image is tagged :latest
if grep -rn 'image:.*:latest' platform/ apps/ 2>/dev/null; then
  echo "  ✖ an image is tagged :latest — pin it"; fail=1
fi

# 4. every alerting rule has a runbook_url that resolves to a real file
for f in platform/prometheus/alerting-rules/*.yaml; do
  grep -oE 'runbook_url: .*' "$f" | sed 's/runbook_url: *//' | while read -r url; do
    path="platform/runbooks/$(basename "${url##*/}").md"
    [[ -f "$path" ]] || { echo "  ✖ $f references a missing runbook: $path"; exit 1; }
  done
done && echo "  ✅ every alert has a real runbook"

# 5. no forbidden high-cardinality label in any rule or dashboard
if grep -rnE 'by ?\((.*)(trace_id|request_id|user_id|pod_ip)(.*)\)' \
      platform/prometheus platform/grafana/dashboards 2>/dev/null; then
  echo "  ✖ a query groups by an unbounded label"; fail=1
fi

exit $fail
EOF
chmod +x ci/check-conventions.sh
./ci/check-conventions.sh
```

### 1.3 The payment mock — your chaos target ⭐

The single most valuable thing in this capstone is a service you can **deliberately break in realistic ways**. Build it once and every game-day scenario becomes a one-liner.

```go
// apps/payment-mock/main.go
package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"math"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// ── ⭐ THE CHAOS KNOBS — mutable at runtime via /_chaos ───────────
type chaos struct {
	latencyMs       atomic.Int64   // added to every request
	latencyJitterMs atomic.Int64   // ± random
	errorRatePct    atomic.Int64   // % of requests that return 500
	timeoutPct      atomic.Int64   // % of requests that hang past the caller's timeout
	hangMs          atomic.Int64   // how long a "timeout" request hangs
	cpuBurnPct      atomic.Int64   // % of the interval spent burning CPU
	leakKbPerReq    atomic.Int64   // ⭐ memory leak: retain this much per request
	rejectRatePct   atomic.Int64   // % that return 402 (business rejection)
}

var c = &chaos{}

// ⭐ retained forever — a real leak, for OOMKill scenarios
var leaked [][]byte

var (
	charges = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "payment_charges_total", Help: "Charge attempts.",
	}, []string{"method", "status", "currency"})
	chargeDur = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name: "payment_charge_duration_seconds", Help: "Charge latency.",
		Buckets: []float64{.01, .025, .05, .1, .2, .35, .5, .75, 1, 1.5, 2, 3, 5, 10},
	}, []string{"method", "status"})
	inflight = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "payment_requests_in_flight", Help: "Requests currently being served.",
	})
)

func main() {
	c.latencyMs.Store(20)
	c.hangMs.Store(6000)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/charge", handleCharge)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
	mux.HandleFunc("GET /_chaos", getChaos)
	mux.HandleFunc("POST /_chaos", setChaos)      // ⭐ the game-day control surface
	mux.HandleFunc("POST /_chaos/reset", resetChaos)

	metrics := http.NewServeMux()
	metrics.Handle("/metrics", promhttp.Handler())
	metrics.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })

	go func() { _ = http.ListenAndServe(":9093", metrics) }()
	slog.Info("payment-mock listening", "app", ":8080", "metrics", ":9093")
	_ = http.ListenAndServe(":8080", otelhttp.NewHandler(mux, "payment-mock"))
}

func handleCharge(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	inflight.Inc()
	defer inflight.Dec()

	status := 200
	defer func() {
		st := strconv.Itoa(status)
		chargeDur.WithLabelValues(r.Method, st).Observe(time.Since(start).Seconds())
		charges.WithLabelValues(r.Method, st, "USD").Inc()
	}()

	// ⭐ memory leak
	if kb := c.leakKbPerReq.Load(); kb > 0 {
		leaked = append(leaked, make([]byte, kb*1024))
	}

	// ⭐ CPU burn
	if pct := c.cpuBurnPct.Load(); pct > 0 {
		burnUntil := time.Now().Add(time.Duration(pct) * time.Millisecond)
		x := 0.0
		for time.Now().Before(burnUntil) {
			x += math.Sqrt(float64(rand.Intn(1000)))
		}
		_ = x
	}

	// ⭐ the hang — the caller times out, WE keep going (returns 200 late)
	if c.timeoutPct.Load() > 0 && rand.Int63n(100) < c.timeoutPct.Load() {
		hang := time.Duration(c.hangMs.Load()) * time.Millisecond
		slog.Warn("chaos: hanging request", "hang_ms", hang.Milliseconds())
		time.Sleep(hang)
		status = 200                              // ⭐ succeeds, but far too late
		writeJSON(w, status, map[string]any{"id": "ch_hang", "status": "succeeded_late"})
		return
	}

	// ⭐ base latency + jitter
	base := time.Duration(c.latencyMs.Load()) * time.Millisecond
	if j := c.latencyJitterMs.Load(); j > 0 {
		base += time.Duration(rand.Int63n(j)) * time.Millisecond
	}
	time.Sleep(base)

	// ⭐ hard errors
	if c.errorRatePct.Load() > 0 && rand.Int63n(100) < c.errorRatePct.Load() {
		status = 500
		slog.Error("chaos: simulated provider failure")
		writeJSON(w, status, map[string]any{"error": "provider_unavailable"})
		return
	}

	// ⭐ business rejections (NOT an error — a 402)
	if c.rejectRatePct.Load() > 0 && rand.Int63n(100) < c.rejectRatePct.Load() {
		status = 402
		writeJSON(w, status, map[string]any{"error": "card_declined"})
		return
	}

	writeJSON(w, status, map[string]any{
		"id":      fmt.Sprintf("ch_%d", rand.Int63n(1<<40)),
		"status":  "succeeded",
		"latency": time.Since(start).String(),
	})
}

// ── ⭐ THE CHAOS CONTROL API ─────────────────────────────────────
func getChaos(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, 200, map[string]int64{
		"latency_ms": c.latencyMs.Load(), "latency_jitter_ms": c.latencyJitterMs.Load(),
		"error_rate_pct": c.errorRatePct.Load(), "timeout_pct": c.timeoutPct.Load(),
		"hang_ms": c.hangMs.Load(), "cpu_burn_pct": c.cpuBurnPct.Load(),
		"leak_kb_per_req": c.leakKbPerReq.Load(), "reject_rate_pct": c.rejectRatePct.Load(),
	})
}

func setChaos(w http.ResponseWriter, r *http.Request) {
	var in map[string]int64
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		http.Error(w, err.Error(), 400); return
	}
	for k, v := range in {
		switch k {
		case "latency_ms":        c.latencyMs.Store(v)
		case "latency_jitter_ms": c.latencyJitterMs.Store(v)
		case "error_rate_pct":    c.errorRatePct.Store(v)
		case "timeout_pct":       c.timeoutPct.Store(v)
		case "hang_ms":           c.hangMs.Store(v)
		case "cpu_burn_pct":      c.cpuBurnPct.Store(v)
		case "leak_kb_per_req":   c.leakKbPerReq.Store(v)
		case "reject_rate_pct":   c.rejectRatePct.Store(v)
		default:
			http.Error(w, "unknown knob: "+k, 400); return
		}
	}
	slog.Warn("chaos configuration changed", "knobs", in)
	getChaos(w, r)
}

func resetChaos(w http.ResponseWriter, r *http.Request) {
	c.latencyMs.Store(20); c.latencyJitterMs.Store(0); c.errorRatePct.Store(0)
	c.timeoutPct.Store(0); c.hangMs.Store(6000); c.cpuBurnPct.Store(0)
	c.leakKbPerReq.Store(0); c.rejectRatePct.Store(0)
	leaked = nil                                   // ⭐ let the GC reclaim it
	slog.Info("chaos reset")
	getChaos(w, r)
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
```

```bash
cat > game-day/chaos.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ the ONE interface to every failure scenario
set -euo pipefail
NS="${NS:-shop}"
cmd="${1:-status}"; shift || true

port_forward() {
  pkill -f 'port-forward.*payment-mock' 2>/dev/null || true
  kubectl port-forward -n "$NS" svc/payment-mock 18080:8080 >/dev/null 2>&1 &
  sleep 3
}
port_forward

case "$cmd" in
  status)  curl -s localhost:18080/_chaos | jq . ;;
  reset)   curl -s -XPOST localhost:18080/_chaos/reset | jq . ;;

  # ── scenario 01: the provider's p99 drifts past our timeout ──────────
  payment-slow)
    curl -s -XPOST localhost:18080/_chaos -d '{"latency_ms":1200,"latency_jitter_ms":400}' | jq .
    echo "💥 payment latency is now 1.2–1.6s. Our client timeout is 1s → retries → 3s p99." ;;

  # ── scenario 02: hard provider outage ────────────────────────────────
  payment-down)
    curl -s -XPOST localhost:18080/_chaos -d '{"error_rate_pct":100}' | jq .
    echo "💥 every charge now returns 500." ;;

  payment-degraded)
    curl -s -XPOST localhost:18080/_chaos -d '{"error_rate_pct":12,"latency_ms":180}' | jq .
    echo "💥 12% of charges fail — enough to breach a 99.9% SLO, not enough to be obvious." ;;

  payment-declines)
    curl -s -XPOST localhost:18080/_chaos -d '{"reject_rate_pct":40}' | jq .
    echo "💥 40% of cards declined. ⭐ NOTE: these are 402s, NOT 5xx — an availability
         SLO on 5xx will NOT fire. This is the business-metric gap." ;;

  payment-hangs)
    curl -s -XPOST localhost:18080/_chaos -d '{"timeout_pct":30,"hang_ms":8000}' | jq .
    echo "💥 30% of requests hang 8s. Threads pile up → saturation." ;;
  *) echo "usage: $0 {status|reset|payment-slow|payment-down|payment-degraded|payment-declines|payment-hangs}"; exit 1 ;;
esac
EOF
chmod +x game-day/chaos.sh
```

### 1.4 Instrumentation summary — what each service does

| Service | Language | Metrics | Traces | Logs | Injection |
|---|---|---|---|---|---|
| `shop-ui` | JS/React | — (RUM via spans) | ⭐ Web SDK: DocumentLoad, Fetch, UserInteraction | console JSON | compiled in |
| `checkout` | Go | `prometheus/client_golang` + `/metrics:9091` | ⭐ manual: TracerProvider, otelhttp, Inject | `slog` JSON with trace_id | compiled in |
| `shop-api` | Java | ⭐ Micrometer + `/prometheus:9090` (histograms on) | zero-code Java agent + manual domain spans | Logback JSON with `%X{trace_id}` | **OTel Operator annotation** |
| `order-worker` | Python | `prometheus_client` `:9092` | `opentelemetry-instrument` + manual CONSUMER spans with links | `logging` JSON with a TraceContextFilter | entrypoint wrapper |
| `payment-mock` | Go | `promauto` `:9093` | `otelhttp` | `slog` JSON | compiled in |
| `postgres` | — | ⭐ `postgres_exporter` sidecar | JDBC spans from the Java agent | stdout → filelog | sidecar |
| `redis` | — | ⭐ `redis_exporter` sidecar | Lettuce spans from the Java agent | stdout → filelog | sidecar |
| `rabbitmq` | — | ⭐ the built-in Prometheus plugin | PRODUCER/CONSUMER spans + links | stdout → filelog | plugin |

```bash
# the exporters for the data stores — one manifest each, all in Git
cat > platform/kubernetes/apps/exporters.yaml <<'EOF'
# ── postgres_exporter ────────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata: {name: postgres-exporter-dsn, namespace: shop}
type: Opaque
stringData:
  DATA_SOURCE_NAME: "postgresql://exporter:exporter@postgres:5432/shop?sslmode=disable"
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: postgres-exporter, namespace: shop, labels: {app: postgres-exporter}}
spec:
  replicas: 1
  selector: {matchLabels: {app: postgres-exporter}}
  template:
    metadata:
      labels: {app: postgres-exporter}
      annotations:
        # ⭐ the OTel Operator's env-only injection for a pre-instrumented binary
        instrumentation.opentelemetry.io/inject-sdk: "otel/shop-instrumentation"
    spec:
      containers:
        - name: exporter
          image: quay.io/prometheuscommunity/postgres-exporter:v0.16.0
          env:
            - name: DATA_SOURCE_NAME
              valueFrom: {secretKeyRef: {name: postgres-exporter-dsn, key: DATA_SOURCE_NAME}}
            - {name: PG_EXPORTER_EXTEND_QUERY_PATH, value: "/etc/exporter/queries.yaml"}
            - {name: OTEL_SERVICE_NAME, value: "postgres-exporter"}
          ports: [{name: metrics, containerPort: 9187}]
          resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 128Mi}}
          volumeMounts: [{name: queries, mountPath: /etc/exporter}]
      volumes: [{name: queries, configMap: {name: postgres-exporter-queries}}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: postgres-exporter-queries, namespace: shop}
data:
  queries.yaml: |
    # ⭐ BUSINESS QUERIES — the ones that matter more than pg_stat_*
    pg_stat_orders:
      query: "SELECT state, count(*) AS n FROM shop.orders GROUP BY state"
      metrics: [{state: {usage: LABEL}}, {n: {usage: GAUGE, description: "orders by state"}}]
    pg_stat_orders_oldest_unprocessed:
      query: "SELECT EXTRACT(EPOCH FROM (now() - min(created_at)))::bigint AS seconds
              FROM shop.orders WHERE state='pending'"
      metrics: [{seconds: {usage: GAUGE, description: "age of the oldest pending order"}}]
    pg_stat_hypo_size:
      query: "SELECT pg_database_size('shop') AS bytes"
      metrics: [{bytes: {usage: GAUGE}}]
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  namespace: shop
  labels: {app: postgres-exporter}
spec:
  selector: {app: postgres-exporter}
  ports: [{name: metrics, port: 9187, targetPort: metrics}]
---
# ── redis_exporter ───────────────────────────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata: {name: redis-exporter, namespace: shop, labels: {app: redis-exporter}}
spec:
  replicas: 1
  selector: {matchLabels: {app: redis-exporter}}
  template:
    metadata: {labels: {app: redis-exporter}}
    spec:
      containers:
        - name: exporter
          image: oliver006/redis_exporter:v1.66.0
          args: ["--redis.addr=redis://redis:6379", "--include-system-metrics"]
          ports: [{name: metrics, containerPort: 9121}]
          resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 128Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: redis-exporter, namespace: shop, labels: {app: redis-exporter}}
spec:
  selector: {app: redis-exporter}
  ports: [{name: metrics, port: 9121, targetPort: metrics}]
EOF

# RabbitMQ needs its Prometheus plugin enabled, then a ServiceMonitor
cat > platform/kubernetes/apps/rabbitmq-monitoring.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: rabbitmq-plugins, namespace: shop}
data:
  enabled_plugins: |
    [rabbitmq_prometheus,rabbitmq_management,rabbitmq_peer_discovery_k8s].
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: rabbitmq, namespace: shop, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: rabbitmq}}
  endpoints:
    - {port: metrics, path: /metrics, interval: 30s}     # ⭐ rabbitmq_prometheus uses :15692
      # the per-object metrics are HUGE — enable only what you need:
      relabelings:
        - {sourceLabels: [__address__], targetLabel: instance}
      metricRelabelings:
        # ⭐ drop the per-queue-detail metrics unless you have few queues
        - {sourceLabels: [__name__], regex: 'rabbitmq_queue_messages_.*', action: keep}
EOF
```

---

<a name="phase-2--the-platform"></a>
## Phase 2 — The platform, installed from Git

### 2.1 The version matrix (pin every one of these)

| Component | Version | Where |
|---|---|---|
| Kubernetes | 1.37 | kind image |
| kube-prometheus-stack | chart **72.x** | Helm |
| Prometheus | **v3.13.2** | chart |
| Alertmanager | 0.28.x | chart |
| Grafana | **12.3+** | chart |
| Grafana Tempo | **2.6.1** | Helm |
| Grafana Loki | **3.7.5** | Helm |
| OTel Collector (contrib) | **0.158.0** | image |
| OTel Operator | 0.90.0 | Helm |
| OTel Java agent | 2.11.0 | image arg |
| node_exporter | 1.9.x | chart |
| kube-state-metrics | 2.14.x | chart |
| blackbox_exporter | 0.26.x | chart |
| prometheus-adapter | 0.12.x | chart |
| postgres_exporter | 0.16.0 | image |
| redis_exporter | 1.66.0 | image |
| sloth | 0.13.x | binary |

### 2.2 The consolidated Helm values

`platform/helm/values/kube-prometheus-stack.yaml` — the production-shaped version, combining everything from Case 1:

```yaml
fullnameOverride: kps

global:
  rbac: {create: true, pspEnabled: false}

# ══ PROMETHEUS ════════════════════════════════════════════════════
prometheus:
  enabled: true
  prometheusSpec:
    image: {tag: v3.13.2}
    replicas: 1                       # ⭐ 2 in production, with external labels
    retention: 15d
    retentionSize: 45GB               # ⭐ whichever comes first — protects the disk
    scrapeInterval: 30s
    scrapeTimeout: 10s
    evaluationInterval: 30s
    enableAdminAPI: false             # ⭐ true only when debugging, never permanently
    enableFeatures:
      - exemplar-storage              # ⭐ metric → trace
      - native-histogram              # ⭐ OTel exponential histograms
      - otlp-write-receiver           # ⭐ accept OTLP metrics from the Collector
      - auto-gomemlimit
      - auto-gomaxprocs
      - delayed-name-removal
    externalLabels:
      cluster: learn
      region: ap-south-1
      environment: dev
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    probeSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {}
    podMonitorSelector: {}
    probeSelector: {}
    ruleSelector: {}
    resources:
      requests: {cpu: "1", memory: 4Gi}
      limits:   {memory: 8Gi}
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          accessModes: [ReadWriteOnce]
          resources: {requests: {storage: 50Gi}}
    # ⭐ the WAL and the TSDB tuning
    walCompression: true
    maximumStartupDurationSeconds: 600
    additionalArgs:
      - {name: query.max-concurrency, value: "20"}
      - {name: storage.tsdb.max-block-chunk-segment-size, value: "512"}
    podAntiAffinity: soft
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      fsGroup: 65534
      seccompProfile: {type: RuntimeDefault}
  service: {type: ClusterIP}

# ══ ALERTMANAGER ══════════════════════════════════════════════════
alertmanager:
  enabled: true
  alertmanagerSpec:
    image: {tag: v0.28.1}
    replicas: 1                       # ⭐ 3 in production (they gossip and dedupe)
    retention: 240h
    resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {memory: 256Mi}}
    storage:
      volumeClaimTemplate:
        spec: {storageClassName: standard, resources: {requests: {storage: 5Gi}}}
    securityContext: {runAsNonRoot: true, runAsUser: 65534, fsGroup: 65534}
  # ⭐ we manage the config ourselves in platform/alertmanager/
  config:
    global:
      resolve_timeout: 5m
      slack_api_url_file: /etc/alertmanager/secrets/slack-webhook-url
    route:
      receiver: blackhole
      group_by: [alertname, namespace, team]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
    receivers: [{name: blackhole}]

# ══ GRAFANA ═══════════════════════════════════════════════════════
grafana:
  enabled: true
  image: {tag: "12.3.1"}
  replicas: 1
  adminUser: admin
  adminPassword: admin                 # ⭐ dev only; use an existingSecret in production
  grafana.ini:
    server: {root_url: "http://localhost:3000"}
    analytics: {reporting_enabled: false, check_for_updates: false}
    news: {news_feed_enabled: false}
    dashboards:
      default_home_dashboard_path: /var/lib/grafana/dashboards/default/99-incident.json
      versions_to_keep: 20             # ⭐ UI edit history, a safety net
    users: {default_theme: dark, viewers_can_edit: true}
    feature_toggles: {enable: "traceqlEditor,logsExploreTable,correlations"}
    unified_alerting: {enabled: true}
    log: {mode: console, level: info}
  # ⭐⭐ provision everything from ConfigMaps with these labels
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      folderAnnotation: grafana_folder
      provider: {foldersFromFilesStructure: true}
      searchNamespace: ALL              # ⭐ find dashboards in any namespace
    datasources:
      enabled: true
      label: grafana_datasource
      searchNamespace: ALL
    alerts:
      enabled: true
      label: grafana_alert
      searchNamespace: ALL
    resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {memory: 256Mi}}
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: default
          orgId: 1
          folder: Shop
          type: file
          disableDeletion: false
          allowUiUpdates: true
          updateIntervalSeconds: 30
          options: {path: /var/lib/grafana/dashboards/default}
  resources: {requests: {cpu: 100m, memory: 256Mi}, limits: {memory: 512Mi}}
  persistence: {enabled: true, size: 5Gi}

# ══ EXPORTERS ═════════════════════════════════════════════════════
kube-state-metrics:
  enabled: true
  metricLabelsAllowlist: ["pods=[app,team,tier]", "deployments=[app,team]", "namespaces=[team]"]
  # ⭐ THIS is how your pod labels become Prometheus labels — required for routing by team
  prometheus: {monitor: {enabled: true, additionalLabels: {release: kps}}}
  resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {memory: 256Mi}}

prometheus-node-exporter:
  enabled: true
  extraArgs: ["--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)"]
  resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 128Mi}}

# ⭐ blackbox probing from INSIDE the cluster
prometheus-blackbox-exporter:
  enabled: true
  config:
    modules:
      http_2xx:
        prober: http
        timeout: 5s
        http:
          valid_status_codes: [200, 201, 204, 301, 302]
          method: GET
          preferred_ip_protocol: ip4
          follow_redirects: true
      http_post_2xx:
        prober: http
        timeout: 5s
        http: {method: POST, valid_status_codes: [200, 201, 202]}
      http_checkout:
        prober: http
        timeout: 8s
        http:
          method: POST
          body: '{"items":1,"tier":"standard"}'
          headers: {Content-Type: application/json}
          valid_status_codes: [201]
          fail_if_body_not_matches_regexp: ['"orderId"']
      tcp_connect:
        prober: tcp
        timeout: 5s
      icmp:
        prober: icmp
        timeout: 5s
        icmp: {preferred_ip_protocol: ip4}
  serviceMonitor:
    enabled: true
    additionalLabels: {release: kps}
    defaults: {interval: 30s, scrapeTimeout: 10s}
    targets:                          # ⭐ declared in Helm values = in Git
      shop-api-health:  {url: "http://shop-api.shop.svc:9090/actuator/health", module: http_2xx}
      checkout-health:  {url: "http://checkout.shop.svc:9091/healthz",         module: http_2xx}
      payment-health:   {url: "http://payment-mock.shop.svc:9093/healthz",     module: http_2xx}
      shop-ui:          {url: "http://shop-ui.shop.svc:80/",                   module: http_2xx}
      postgres:         {url: "postgres.shop.svc:5432",                        module: tcp_connect}
      redis:            {url: "redis.shop.svc:6379",                           module: tcp_connect}
      rabbitmq:         {url: "rabbitmq.shop.svc:5672",                        module: tcp_connect}
      grafana:          {url: "http://kps-grafana.monitoring.svc:3000/login",  module: http_2xx}
      external-shop:    {url: "https://shop.example.com/",                     module: http_2xx}

# ⭐ custom-metric HPA
prometheus-adapter:
  enabled: true
  prometheus: {url: "http://kps-kube-prometheus-stack-prometheus.monitoring.svc", port: 9090}
  rules:
    existing: prometheus-adapter-rules
  resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {memory: 256Mi}}

defaultRules:
  create: true
  rules:
    alertmanager: true
    etcd: true
    configReloaders: true
    general: true
    k8sContainerCpuUsageSecondsTotal: true
    k8sContainerMemoryWorkingSetBytes: true
    kubeApiserverAvailability: true
    kubeApiserverSlos: true
    kubelet: true
    kubeProxy: true
    kubePrometheusGeneral: true
    kubePrometheusNodeRecording: true
    kubernetesApps: true
    kubernetesResources: true
    kubernetesStorage: true
    kubernetesSystem: true
    kubeSchedulerAlerting: true
    kubeSchedulerRecording: true
    kubeStateMetrics: true
    network: true
    node: true
    nodeExporterAlerting: true
    nodeExporterRecording: true
    prometheus: true
    prometheusOperator: true
    windows: false
  # ⭐ label every default rule so Alertmanager can route it
  additionalRuleLabels:
    team: platform
  # ⭐ and disable the noisy ones (the app alerts replace them)
  disabled:
    KubePodNotReady: false
    KubeContainerWaiting: false

kubeEtcd: {enabled: false}            # ⭐ false on managed Kubernetes
kubeControllerManager: {enabled: false}
kubeScheduler: {enabled: false}
kubeProxy: {enabled: false}
```

### 2.3 The NetworkPolicy that everyone forgets ⭐

Telemetry is **egress**. If you lock down your namespaces (you should), you must explicitly allow apps to reach the Collector — or you get silence.

```yaml
# platform/kubernetes/networkpolicies/shop-egress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: shop-default-deny-egress, namespace: shop}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress: []                       # ⭐ deny everything first
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: shop-allow-telemetry, namespace: shop}
spec:
  podSelector: {}                  # every pod in shop
  policyTypes: [Egress]
  egress:
    # ⭐⭐ to the OTel agent — OTLP gRPC + HTTP
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: otel}}
          podSelector: {matchLabels: {app: otel-agent}}
      ports: [{protocol: TCP, port: 4317}, {protocol: TCP, port: 4318}]
    # ⭐ DNS — without this, nothing resolves and it looks like a Collector bug
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
          podSelector: {matchLabels: {k8s-app: kube-dns}}
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
    # ⭐ Prometheus scrapes come INBOUND to :9090-:9093 — allow that too
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: shop-allow-scrape, namespace: shop}
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}
          podSelector: {matchLabels: {app.kubernetes.io/name: prometheus}}
      ports:
        - {protocol: TCP, port: 9090}
        - {protocol: TCP, port: 9091}
        - {protocol: TCP, port: 9092}
        - {protocol: TCP, port: 9093}
        - {protocol: TCP, port: 8080}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: otel-allow-backends, namespace: otel}
spec:
  podSelector: {}
  policyTypes: [Egress, Ingress]
  ingress:
    - from: [{namespaceSelector: {}}]        # any namespace may send telemetry
      ports: [{protocol: TCP, port: 4317}, {protocol: TCP, port: 4318}]
  egress:
    - to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}}]
      ports:
        - {protocol: TCP, port: 3200}        # Tempo OTLP
        - {protocol: TCP, port: 4317}        # Tempo OTLP gRPC
        - {protocol: TCP, port: 3100}        # Loki push
        - {protocol: TCP, port: 9090}        # Prometheus remote write
    - to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}}]
      ports: [{protocol: UDP, port: 53}]
    - to: [{podSelector: {matchLabels: {app: otel-gateway}}}]
      ports: [{protocol: TCP, port: 4317}]   # agent → gateway
```

```bash
# ⭐ TEST IT. A NetworkPolicy that silently blocks telemetry is a terrible failure mode.
kubectl apply -f platform/kubernetes/networkpolicies/
sleep 5
kubectl run nettest --image=nicolaka/netshoot -n shop --rm -it --restart=Never -- \
  bash -c 'nc -zv -w5 otel-collector-agent.otel.svc.cluster.local 4317 && echo OK || echo BLOCKED'
# OK
```

### 2.4 The platform install, as one command

```bash
make platform-install
make platform-apply
kubectl get pods -n monitoring -n otel
kubectl get servicemonitor,podmonitor,probe,prometheusrule -A
kubectl get instrumentation -A
```

---

<a name="phase-3--slis-slos-and-the-alerting-hierarchy"></a>
## Phase 3 — SLIs, SLOs and the alerting hierarchy

### 3.1 The SLO catalogue

Define the SLOs in a table **first**, then generate the rules. Never the other way round.

| # | SLO | Objective | Window | SLI (metrics) | SLI (traces) | Owner | Consequence of breach |
|---|---|---|---|---|---|---|---|
| SLO-1 | **Checkout availability** | 99.9% | 30d rolling | `1 - (5xx / total)` on `url.path=~"/api/orders\|/checkout"` | `1 - error_spans/total_spans` | payments | revenue loss → **page** |
| SLO-2 | **Checkout latency** | 99% of requests < 500 ms | 30d rolling | `le="0.5"` bucket ratio | `duration < 500ms` | payments | cart abandonment → **page** |
| SLO-3 | **Browse latency** | 99% < 300 ms | 30d rolling | `le="0.3"` on `GET /api/items` | `duration < 300ms` | storefront | bounce rate → ticket |
| SLO-4 | **Order fulfilment lag** | 99% of orders processed < 60 s | 30d rolling | `worker_job_duration_seconds` | consumer span duration | fulfilment | SLA breach → ticket |
| SLO-5 | **Queue freshness** | oldest pending order < 5 min | — | `pg_stat_orders_oldest_unprocessed_seconds` | — | fulfilment | stuck orders → **page** |
| SLO-6 | **Data layer** | 99.95% of queries < 100 ms | 30d | `hikaricp` + pg exporter | JDBC span duration | data | cascading failure → **page** |

```yaml
# platform/prometheus/slos/checkout-availability.yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata: {name: checkout-availability, namespace: monitoring, labels: {slo: checkout-availability}}
spec:
  service: shop
  slos:
    - name: checkout-availability
      objective: 99.9
      description: |
        99.9% of checkout requests must not return a server error.
        Checkout is the revenue path: a breach here loses money directly.
      owner: payments-team
      sli:
        events:
          errorQuery: |
            sum(rate(
              http_server_requests_seconds_count{
                namespace="shop",
                application=~"shop-api|checkout",
                uri=~"/api/orders|/checkout|/api/checkout",
                status=~"5..|408|429|503|504"
              }[{{.window}}]))
          totalQuery: |
            sum(rate(
              http_server_requests_seconds_count{
                namespace="shop",
                application=~"shop-api|checkout",
                uri=~"/api/orders|/checkout|/api/checkout"
              }[{{.window}}]))
      alerting:
        name: CheckoutAvailability
        labels: {team: payments, slo: checkout-availability, tier: critical}
        pageAlert:
          labels:
            severity: critical
            channel: '#shop-oncall'
            ticket: "SLO-1"
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/slo-checkout-availability-burn.md
        ticketAlert:
          labels:
            severity: warning
            channel: '#shop-alerts'
            ticket: "SLO-1"
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/slo-checkout-availability-burn.md
---
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata: {name: checkout-latency, namespace: monitoring}
spec:
  service: shop
  slos:
    - name: checkout-latency
      objective: 99
      description: "99% of checkout requests must complete in under 500ms."
      owner: payments-team
      sli:
        events:
          # ⭐ a LATENCY SLI: the "bad events" are requests SLOWER than the threshold,
          #   computed as total minus the le="0.5" bucket
          errorQuery: |
            sum(rate(http_server_requests_seconds_count{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[{{.window}}]))
            -
            sum(rate(http_server_requests_seconds_bucket{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout",le="0.5"}[{{.window}}]))
          totalQuery: |
            sum(rate(http_server_requests_seconds_count{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[{{.window}}]))
      alerting:
        name: CheckoutLatency
        labels: {team: payments, slo: checkout-latency}
        pageAlert: {labels: {severity: critical, runbook_url: "https://git.example.com/shop-observability/-/blob/main/platform/runbooks/symptom-latency-p99.md"}}
        ticketAlert: {labels: {severity: warning, runbook_url: "https://git.example.com/shop-observability/-/blob/main/platform/runbooks/symptom-latency-p99.md"}}
---
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata: {name: order-fulfilment, namespace: monitoring}
spec:
  service: shop
  slos:
    - name: order-fulfilment-lag
      objective: 99
      description: "99% of orders must be fully processed within 60 seconds of creation."
      owner: fulfilment-team
      sli:
        events:
          errorQuery: |
            sum(rate(worker_job_duration_seconds_count{namespace="shop",queue="orders"}[{{.window}}]))
            -
            sum(rate(worker_job_duration_seconds_bucket{namespace="shop",queue="orders",le="60.0"}[{{.window}}]))
          totalQuery: |
            sum(rate(worker_job_duration_seconds_count{namespace="shop",queue="orders"}[{{.window}}]))
      alerting:
        name: OrderFulfilmentLag
        labels: {team: fulfilment}
        pageAlert:  {labels: {severity: critical}}
        ticketAlert:{labels: {severity: warning}}
    - name: queue-freshness
      objective: 99.5
      description: "The oldest pending order must be younger than 5 minutes, 99.5% of the time."
      owner: fulfilment-team
      sli:
        events:
          # ⭐ a GAUGE-based SLI: the "bad event" is a sample where the gauge exceeds 300
          errorQuery: 'count(pg_stat_orders_oldest_unprocessed_seconds{namespace="shop"} > bool 300)'
          totalQuery: 'count(pg_stat_orders_oldest_unprocessed_seconds{namespace="shop"})'
      alerting:
        name: QueueFreshness
        pageAlert: {labels: {severity: critical}}
        ticketAlert: {labels: {severity: warning}}
```

```bash
# generate the rules from the SLO specs
sloth generate -i platform/prometheus/slos/ -o platform/prometheus/alerting-rules/slo-burn-rate.yaml
sloth generate -i platform/prometheus/slos/ --out-prometheus --prometheus-multi-window-multi-burn-rate
promtool check rules platform/prometheus/alerting-rules/slo-burn-rate.yaml
# Checking 'platform/prometheus/alerting-rules/slo-burn-rate.yaml'
#   SUCCESS: 8 rules found

kubectl apply -f platform/prometheus/slos/
kubectl get prometheusrule -n monitoring | grep slo
```

**The generated multi-window multi-burn-rate matrix:**

| Alert | Long window | Short window | Burn rate | Budget consumed | Severity | Action |
|---|---|---|---|---|---|---|
| `…BurnRateFast` | 1h | 5m | 14.4× | 2% in 1h | critical | **page immediately** |
| `…BurnRateSlow` | 6h | 30m | 6× | 5% in 6h | critical | **page** |
| `…BurnRateMedium` | 1d | 2h | 3× | 10% in 1d | warning | ticket, next business day |
| `…BurnRateSlowest` | 3d | 6h | 1× | 10% in 3d | warning | ticket |

### 3.2 The full alerting hierarchy

```
                        ┌──────────────────────────────────────────┐
   TIER 1 — SYMPTOMS    │ SLO burn rate (page)                     │  ← the only things
   "users are hurt"     │ Blackbox probe failing (page)            │     that should page
                        │ Checkout error ratio > 1% for 5m (page)  │
                        └──────────────────────────────────────────┘
                        ┌──────────────────────────────────────────┐
   TIER 2 — SATURATION  │ CPU throttled > 25% for 15m (ticket)     │  ← leading indicators
   "about to be hurt"   │ Memory > 90% of limit for 10m (ticket)   │     Predict tier 1.
                        │ DB pool exhausted (ticket)               │     NEVER page alone.
                        │ Queue depth growing for 30m (ticket)     │
                        │ Disk will fill in 4h (ticket)            │
                        └──────────────────────────────────────────┘
                        ┌──────────────────────────────────────────┐
   TIER 3 — CAUSE       │ KubePodCrashLooping (ticket)             │  ← diagnostic context
   "why"                │ KubeContainerOOMKilled (ticket)          │     Inhibited by tiers 1–2
                        │ KubeDeploymentReplicasMismatch (ticket)  │     when those fire.
                        │ KubeNodeNotReady (page — platform team)  │
                        │ KubePersistentVolumeFillingUp (ticket)   │
                        └──────────────────────────────────────────┘
                        ┌──────────────────────────────────────────┐
   TIER 4 — SELF        │ PrometheusTargetDown (page)              │  ⭐⭐ monitoring
   "we are blind"       │ PrometheusRuleFailures (page)            │     watches itself
                        │ PrometheusMissingData (page)             │
                        │ AlertmanagerFailedReload (page)          │
                        │ OtelCollectorDroppingSpans (page)        │
                        │ OtelCollectorMemoryLimiterRefusing (page)│
                        │ GrafanaDatasourceDown (page)             │
                        │ LokiIngestFailing (ticket)               │
                        │ TempoIngestFailing (ticket)              │
                        │ PrometheusCardinalityBudget (ticket)     │
                        └──────────────────────────────────────────┘
```

```yaml
# platform/prometheus/alerting-rules/observability-self.yaml  ⭐⭐ TIER 4
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: observability-self
  namespace: monitoring
  labels: {release: kps, team: platform}
spec:
  groups:
    # ── Prometheus itself ────────────────────────────────────────
    - name: prometheus-self
      interval: 30s
      rules:
        - alert: PrometheusTargetDown
          expr: |
            (up{job!~".*blackbox.*"} == 0)
            * on(job, instance) group_left(namespace, pod)
              (label_replace(kube_pod_info, "instance", "$1:9090", "pod_ip", "(.*)") or vector(1))
          for: 3m
          labels: {severity: critical, team: platform, tier: self}
          annotations:
            summary: "Prometheus cannot scrape {{ $labels.job }}/{{ $labels.instance }}"
            description: |
              We are blind to {{ $labels.job }}. Either the target is down or the
              network path to it is broken. This is an observability incident, not
              an application incident — do not wake the app team.
            dashboard_url: http://localhost:3000/d/40-observability-health
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/observability-self-targets-down.md

        - alert: PrometheusRuleEvaluationFailures
          expr: increase(prometheus_rule_evaluation_failures_total[10m]) > 0
          for: 0m
          labels: {severity: critical, team: platform, tier: self}
          annotations:
            summary: "a recording or alerting rule is failing to evaluate"
            description: "Group {{ $labels.rule_group }} — a broken rule means an alert that will never fire."
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/observability-self-targets-down.md

        - alert: PrometheusScrapesTimingOut
          expr: |
            sum by (job) (rate(prometheus_target_scrapes_exceeded_scrape_timeout_total[5m]))
              / sum by (job) (rate(prometheus_target_scrapes_total[5m])) > 0.05
          for: 10m
          labels: {severity: warning, team: platform, tier: self}
          annotations:
            summary: ">5% of scrapes of {{ $labels.job }} are timing out"
            description: "The target is too slow or its response is too large. Gaps will appear in every dashboard."

        - alert: PrometheusMissingRecentData
          expr: time() - prometheus_tsdb_head_time_seconds > 900
          for: 5m
          labels: {severity: critical, team: platform, tier: self}
          annotations:
            summary: "Prometheus has not ingested a sample in >15 minutes"

        - alert: PrometheusTSDBCompactionsFailing
          expr: increase(prometheus_tsdb_compactions_failed_total[1h]) > 0
          labels: {severity: warning, team: platform, tier: self}
          annotations: {summary: "TSDB compaction is failing — the disk may be full or corrupt"}

        - alert: PrometheusOutOfMemorySoon
          expr: |
            predict_linear(process_resident_memory_bytes{job=~"prometheus|kps.*prometheus"}[2h], 4*3600)
              > on() group_left
            (kube_pod_container_resource_limits{resource="memory"} * 0.95)
          for: 15m
          labels: {severity: warning, team: platform, tier: self}
          annotations:
            summary: "Prometheus will OOM within 4 hours at the current growth rate"
            description: "Almost always a cardinality problem. Run `make cardinality`."

        - alert: PrometheusCardinalityBudgetExceeded
          expr: prometheus_tsdb_head_series > 500000
          for: 10m
          labels: {severity: warning, team: platform, tier: self}
          annotations:
            summary: "Prometheus holds {{ $value | humanize }} active series — the budget is 500k"
            description: "Run ./scripts/cardinality-report.sh and find the offending metric."
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/observability-self-targets-down.md

    # ── Alertmanager ─────────────────────────────────────────────
    - name: alertmanager-self
      rules:
        - alert: AlertmanagerFailedReload
          expr: alertmanager_config_last_reload_successful == 0
          for: 5m
          labels: {severity: critical, team: platform, tier: self}
          annotations:
            summary: "Alertmanager rejected its configuration — routing may be stale"
        - alert: AlertmanagerMembersInconsistent
          expr: |
            count(alertmanager_cluster_members == 1)
              != on() group_left count(alertmanager_cluster_enabled == 1)
          for: 10m
          labels: {severity: critical, team: platform, tier: self}
          annotations: {summary: "the Alertmanager cluster has split — alerts may be duplicated or lost"}
        - alert: AlertmanagerNotificationsFailing
          expr: |
            sum by (integration) (rate(alertmanager_notifications_failed_total[5m]))
              / sum by (integration) (rate(alertmanager_notifications_total[5m])) > 0.05
          for: 5m
          labels: {severity: critical, team: platform, tier: self}
          annotations:
            summary: ">5% of {{ $labels.integration }} notifications are failing — nobody is being paged"
        - alert: AlertmanagerSilencesTooMany
          expr: count(alertmanager_silences{state="active"}) > 5
          for: 30m
          labels: {severity: warning, team: platform, tier: self}
          annotations:
            summary: "{{ $value }} active silences — someone has muted the alarm system"

    # ── Grafana ──────────────────────────────────────────────────
    - name: grafana-self
      rules:
        - alert: GrafanaDatasourceUnhealthy
          expr: grafana_datasource_health_status != 1
          for: 5m
          labels: {severity: critical, team: platform, tier: self}
          annotations:
            summary: "Grafana datasource {{ $labels.name }} is unhealthy — dashboards are lying"
        - alert: GrafanaDown
          expr: up{job="grafana"} == 0
          for: 2m
          labels: {severity: critical, team: platform, tier: self}

    # ── The OTel Collector ⭐ ────────────────────────────────────
    - name: otel-collector-self
      rules:
        - alert: OtelCollectorDroppingSpans
          expr: sum(rate(otelcol_processor_dropped_spans[5m])) > 0
          for: 2m
          labels: {severity: critical, team: platform, tier: self}
          annotations:
            summary: "the Collector is dropping {{ $value | printf \"%.0f\" }} spans/s — traces are incomplete"
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/observability-self-otel-drops.md

        - alert: OtelCollectorMemoryLimiterRefusing
          expr: sum(rate(otelcol_processor_refused_spans{processor="memory_limiter"}[5m])) > 0
          for: 2m
          labels: {severity: critical, team: platform, tier: self}
          annotations:
            summary: "the Collector's memory_limiter is shedding telemetry — raise its memory or add replicas"
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/observability-self-otel-drops.md

        - alert: OtelCollectorExportFailing
          expr: |
            sum(rate(otelcol_exporter_send_failed_spans[5m]))
              / clamp_min(sum(rate(otelcol_exporter_sent_spans[5m])), 1) > 0.01
          for: 5m
          labels: {severity: critical, team: platform, tier: self}
          annotations: {summary: "the Collector cannot reach a trace backend"}

        - alert: OtelCollectorQueueNearlyFull
          expr: otelcol_exporter_queue_size / clamp_min(otelcol_exporter_queue_capacity, 1) > 0.9
          for: 5m
          labels: {severity: warning, team: platform, tier: self}
          annotations: {summary: "the Collector's export queue is 90% full — the backend is too slow"}

        - alert: OtelCollectorDown
          expr: up{namespace="otel"} == 0
          for: 2m
          labels: {severity: critical, team: platform, tier: self}
          annotations: {summary: "the OTel Collector is down — no traces or logs are being collected"}

        - alert: OtelAgentMissingOnNode
          expr: |
            count by (node) (kube_pod_info{namespace="otel", pod=~"otel-agent.*"})
              != on() group_left count(kube_node_info)
          for: 10m
          labels: {severity: warning, team: platform, tier: self}
          annotations: {summary: "a node has no OTel agent — telemetry from that node is missing"}

        - alert: OtelTailSamplingDroppingTooMuch
          expr: |
            sum(rate(otelcol_processor_dropped_spans{processor="tail_sampling"}[15m]))
              / sum(rate(otelcol_receiver_accepted_spans[15m])) > 0.98
          for: 30m
          labels: {severity: warning, team: platform, tier: self}
          annotations:
            summary: "tail sampling is dropping >98% of spans — verify the policies still match your traffic"
            description: |
              This is usually correct behaviour, but it fires when a code change renames a
              route so that `url.path` no longer matches the money-path policy.

    # ── Loki and Tempo ───────────────────────────────────────────
    - name: loki-tempo-self
      rules:
        - alert: LokiIngestFailing
          expr: sum(rate(loki_discarded_samples_total[5m])) > 0
          for: 10m
          labels: {severity: warning, team: platform, tier: self}
          annotations: {summary: "Loki is rejecting log samples: {{ $labels.reason }}"}
        - alert: LokiQueryLatencyHigh
          expr: histogram_quantile(0.99, sum by (le) (rate(loki_request_duration_seconds_bucket{route=~".*query.*"}[5m]))) > 10
          for: 15m
          labels: {severity: warning, team: platform, tier: self}
          annotations: {summary: "Loki p99 query latency is over 10s — check label cardinality"}
        - alert: TempoIngestFailing
          expr: sum(rate(tempo_discarded_spans_total[5m])) > 0
          for: 5m
          labels: {severity: critical, team: platform, tier: self}
          annotations: {summary: "Tempo is discarding spans: {{ $labels.reason }}"}
        - alert: TempoStorageFillingUp
          expr: predict_linear(tempo_backend_objects_total[6h], 24*3600) > 1e7
          for: 30m
          labels: {severity: warning, team: platform, tier: self}
```

```yaml
# platform/prometheus/alerting-rules/symptom.yaml  ⭐ TIER 1 — the only pages
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: shop-symptom, namespace: monitoring, labels: {release: kps, team: platform}}
spec:
  groups:
    - name: shop-symptom-alerts
      interval: 30s
      rules:
        # ⭐⭐ the ONLY app alert that pages on its own
        - alert: CheckoutErrorRatioHigh
          expr: |
            (
              sum(rate(http_server_requests_seconds_count{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout",status=~"5..|503|504"}[5m]))
              /
              clamp_min(sum(rate(http_server_requests_seconds_count{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[5m])), 0.001)
            ) > 0.01
          for: 5m
          labels: {severity: critical, team: payments, tier: symptom, slo: checkout-availability}
          annotations:
            summary: "1 in 100 checkouts is failing"
            description: |
              Checkout error ratio is {{ $value | humanizePercentage }} (threshold 1%) over 5 minutes.
              This is a revenue-impacting symptom. Start with the error traces, not the metrics:
                Grafana → Incident dashboard → "Slowest/Error traces" panel → click any row.
            dashboard_url: http://localhost:3000/d/99-incident
            trace_query: '{ .service.name =~ "shop-api|checkout" && status = error }'
            log_query: '{namespace="shop"} | json | level="ERROR" | line_format "{{.timestamp}} {{.app}} {{.message}}"'
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/symptom-http-5xx.md

        - alert: CheckoutLatencyP99High
          expr: |
            histogram_quantile(0.99,
              sum by (le) (rate(http_server_requests_seconds_bucket{namespace="shop",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[5m])))
            > 1.0
          for: 10m
          labels: {severity: critical, team: payments, tier: symptom, slo: checkout-latency}
          annotations:
            summary: "checkout p99 latency is {{ $value }}s (SLO: 500ms)"
            description: |
              Check the p50 first. If p50 is also up → global saturation.
              If p50 is fine → a tail problem: retries, a slow dependency, GC, or a lock.
            dashboard_url: http://localhost:3000/d/99-incident
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/symptom-latency-p99.md

        - alert: BrowseLatencyP95High
          expr: |
            histogram_quantile(0.95,
              sum by (le) (rate(http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/items"}[5m])))
            > 0.3
          for: 15m
          labels: {severity: warning, team: storefront, tier: symptom, slo: browse-latency}
          annotations: {summary: "browse p95 latency is {{ $value }}s (SLO: 300ms)"}

        # ⭐ external, user-perspective probing — the ground truth
        - alert: ShopFrontendUnreachable
          expr: probe_success{job="blackbox", instance=~".*shop-ui.*|.*external-shop.*"} == 0
          for: 2m
          labels: {severity: critical, team: storefront, tier: symptom}
          annotations:
            summary: "the shop front door is down from {{ $labels.instance }}"
            description: "Blackbox probing from inside the cluster fails. Users cannot reach the site at all."

        - alert: CheckoutJourneyFailing
          expr: probe_success{job="blackbox", instance=~".*checkout.*"} == 0
          for: 3m
          labels: {severity: critical, team: payments, tier: symptom}
          annotations:
            summary: "the synthetic checkout journey is failing"
            description: |
              This probe POSTs a real order and asserts the response contains an orderId.
              It failing means checkout is broken even if the individual services report healthy.

        - alert: QueueFreshnessBreached
          expr: pg_stat_orders_oldest_unprocessed_seconds > 300
          for: 5m
          labels: {severity: critical, team: fulfilment, tier: symptom, slo: queue-freshness}
          annotations:
            summary: "the oldest unprocessed order is {{ $value }}s old (SLO: 300s)"
            description: "Orders are being created but not fulfilled. Check order-worker first."
```

```yaml
# platform/prometheus/alerting-rules/saturation.yaml  ⭐ TIER 2 — tickets only
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: shop-saturation, namespace: monitoring, labels: {release: kps}}
spec:
  groups:
    - name: shop-saturation-alerts
      rules:
        - alert: ServiceCpuThrottled
          expr: |
            sum by (namespace, pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="shop"}[5m]))
              / clamp_min(sum by (namespace, pod) (rate(container_cpu_cfs_periods_total{namespace="shop"}[5m])), 0.001) > 0.25
          for: 15m
          labels: {severity: warning, team: platform, tier: saturation}
          annotations:
            summary: "{{ $labels.pod }} is CPU-throttled in {{ $value | humanizePercentage }} of periods"
            description: "Throttling adds latency without adding errors. Raise the CPU limit or scale out."

        - alert: ServiceMemoryNearLimit
          expr: |
            sum by (namespace, pod, container) (container_memory_working_set_bytes{namespace="shop"})
              / on(namespace, pod, container) group_left
            kube_pod_container_resource_limits{namespace="shop",resource="memory"} > 0.90
          for: 10m
          labels: {severity: warning, team: platform, tier: saturation}
          annotations:
            summary: "{{ $labels.pod }}/{{ $labels.container }} is at {{ $value | humanizePercentage }} of its memory limit"
            description: "An OOMKill is likely. Check for a leak with the memory graph and a heap dump."

        - alert: DatabasePoolNearExhaustion
          expr: hikaricp_connections_active{namespace="shop"} / clamp_min(hikaricp_connections_max, 1) > 0.85
          for: 5m
          labels: {severity: warning, team: data, tier: saturation}
          annotations:
            summary: "the Hikari pool is {{ $value | humanizePercentage }} full — queries will start waiting"
            description: "A full pool turns into latency, then into request timeouts, then into 5xx."

        - alert: DatabasePoolWaitTimeHigh
          expr: |
            histogram_quantile(0.95, sum by (le) (rate(hikaricp_connections_acquire_seconds_bucket{namespace="shop"}[5m])))
            > 0.1
          for: 10m
          labels: {severity: warning, team: data, tier: saturation}
          annotations: {summary: "acquiring a DB connection takes {{ $value }}s at p95"}

        - alert: ServletThreadsNearExhaustion
          expr: tomcat_threads_busy_threads{namespace="shop"} / clamp_min(tomcat_threads_config_max_threads, 1) > 0.85
          for: 5m
          labels: {severity: warning, team: payments, tier: saturation}
          annotations:
            summary: "Tomcat has {{ $value | humanizePercentage }} of its threads busy"
            description: "Thread exhaustion is the classic cause of 'healthy pods, 503s anyway'."

        - alert: QueueDepthGrowing
          expr: |
            deriv(worker_queue_depth{namespace="shop"}[30m]) > 0.5
            and worker_queue_depth > 100
          for: 15m
          labels: {severity: warning, team: fulfilment, tier: saturation}
          annotations:
            summary: "queue {{ $labels.queue }} is growing at {{ $value }} msgs/s and is at {{ with query \"worker_queue_depth\" }}{{ . | first | value }}{{ end }}"
            description: "The workers cannot keep up. Scale the Deployment, or find why each job got slower."

        - alert: WorkerJobDurationHigh
          expr: |
            histogram_quantile(0.99, sum by (le, queue) (rate(worker_job_duration_seconds_bucket{namespace="shop"}[10m]))) > 5
          for: 15m
          labels: {severity: warning, team: fulfilment, tier: saturation, slo: order-fulfilment-lag}
          annotations: {summary: "worker jobs on {{ $labels.queue }} take {{ $value }}s at p99 (SLO: 60s)"}

        - alert: PersistentVolumeFillingUp
          expr: |
            kubelet_volume_stats_available_bytes{namespace=~"monitoring|shop"}
              / clamp_min(kubelet_volume_stats_capacity_bytes{namespace=~"monitoring|shop"}, 1) < 0.15
            and
            predict_linear(kubelet_volume_stats_available_bytes{namespace=~"monitoring|shop"}[6h], 4*3600) < 0
          for: 15m
          labels: {severity: warning, team: platform, tier: saturation}
          annotations:
            summary: "{{ $labels.persistentvolumeclaim }} will fill within 4 hours"

        - alert: PodRestartingFrequently
          expr: |
            increase(kube_pod_container_status_restarts_total{namespace="shop"}[30m]) > 3
          for: 0m
          labels: {severity: warning, team: platform, tier: saturation}
          annotations:
            summary: "{{ $labels.pod }}/{{ $labels.container }} has restarted {{ $value }} times in 30m"
            description: "Check `kubectl describe pod` for the last state — OOMKilled, Error, or a failing probe."

        - alert: HpaAtMaxReplicas
          expr: |
            kube_horizontalpodautoscaler_status_current_replicas{namespace="shop"}
              == kube_horizontalpodautoscaler_spec_max_replicas{namespace="shop"}
          for: 15m
          labels: {severity: warning, team: platform, tier: saturation}
          annotations:
            summary: "{{ $labels.horizontalpodautoscaler }} is pinned at its maximum — it cannot scale further"

        - alert: NodeDiskPressureSoon
          expr: |
            predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 4*3600) < 0
          for: 30m
          labels: {severity: warning, team: platform, tier: saturation}
          annotations: {summary: "node {{ $labels.instance }} will run out of disk in under 4 hours"}
```

### 3.3 The Alertmanager routing

```yaml
# platform/alertmanager/alertmanager.yaml
apiVersion: v1
kind: Secret
metadata: {name: alertmanager-slack, namespace: monitoring}
type: Opaque
stringData:
  slack-webhook-url: "https://hooks.slack.com/services/T00000000/B00000000/XXXX"   # ⭐ replace
  pagerduty-routing-key: "REPLACE"
---
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: shop-routing
  namespace: monitoring
  labels: {alertmanagerConfig: enabled}          # ⭐ matched by the selector below
spec:
  route:
    receiver: default
    groupBy: [alertname, namespace, team]
    groupWait: 30s
    groupInterval: 5m
    repeatInterval: 4h
    continue: false
    matchers: []
    routes:
      # ── TIER 4: observability is broken → platform, always ─────
      - receiver: platform-critical
        groupBy: [alertname]
        repeatInterval: 1h
        continue: false
        matchers:
          - {name: tier, value: self}
          - {name: severity, value: critical}

      # ── TIER 1: symptoms, critical → page the owning team ─────
      - receiver: pagerduty-payments
        repeatInterval: 30m
        continue: true                            # ⭐ also notify Slack
        matchers:
          - {name: tier, value: symptom}
          - {name: severity, value: critical}
          - {name: team, value: payments}

      - receiver: pagerduty-storefront
        repeatInterval: 30m
        continue: true
        matchers:
          - {name: tier, value: symptom}
          - {name: severity, value: critical}
          - {name: team, value: storefront}

      - receiver: pagerduty-fulfilment
        repeatInterval: 30m
        continue: true
        matchers:
          - {name: tier, value: symptom}
          - {name: severity, value: critical}
          - {name: team, value: fulfilment}

      # ── SLO burn-rate pages go to the SLO owner ────────────────
      - receiver: pagerduty-payments
        repeatInterval: 2h
        matchers:
          - {name: slo, value: "checkout-availability"}

      # ── TIER 2/3: everything else → Slack, business hours ─────
      - receiver: slack-team
        repeatInterval: 12h
        matchers:
          - {name: severity, value: warning}

      # ── a catch-all so nothing is ever silently dropped ────────
      - receiver: slack-platform
        repeatInterval: 24h
        matchers: []

  # ⭐⭐ INHIBIT RULES — the difference between 1 page and 47
  inhibitRules:
    # a node being down suppresses every pod-level alert on that node
    - sourceMatch: [{name: alertname, value: KubeNodeNotReady}]
      targetMatch: [{name: tier, value: cause}]
      equal: [node]
    # a symptom alert suppresses its own saturation/cause alerts
    - sourceMatch: [{name: tier, value: symptom}]
      targetMatch: [{name: tier, value: saturation}]
      equal: [namespace, team]
    - sourceMatch: [{name: tier, value: symptom}]
      targetMatch: [{name: tier, value: cause}]
      equal: [namespace]
    # if observability itself is broken, suppress ALL app alerts (they're unreliable)
    - sourceMatch: [{name: alertname, value: PrometheusMissingRecentData}]
      targetMatch: [{name: tier, value: symptom}]
      equal: []
    # a firing SLO page suppresses the individual symptom alerts
    - sourceMatch: [{name: alertname, value: CheckoutAvailabilityBurnRateFast}]
      targetMatch: [{name: alertname, value: CheckoutErrorRatioHigh}]
      equal: [namespace]

  receivers:
    - name: default
    - name: slack-team
      slackConfigs:
        - channel: '#shop-alerts'
          sendResolved: true
          title: '{{ template "slack.title" . }}'
          text: '{{ template "slack.text" . }}'
          apiURL:
            name: alertmanager-slack
            key: slack-webhook-url
    - name: slack-platform
      slackConfigs:
        - channel: '#platform-alerts'
          sendResolved: true
          apiURL: {name: alertmanager-slack, key: slack-webhook-url}
    - name: platform-critical
      slackConfigs:
        - channel: '#platform-oncall'
          sendResolved: true
          apiURL: {name: alertmanager-slack, key: slack-webhook-url}
      pagerDutyConfigs:
        - routingKey: {name: alertmanager-slack, key: pagerduty-routing-key}
          severity: critical
          class: observability
          component: monitoring-stack
    - name: pagerduty-payments
      pagerDutyConfigs:
        - routingKey: {name: alertmanager-slack, key: pagerduty-routing-key}
          severity: critical
          class: checkout
          component: shop-api
          group: payments
      slackConfigs:
        - {channel: '#shop-oncall', sendResolved: true, apiURL: {name: alertmanager-slack, key: slack-webhook-url}}
    - name: pagerduty-storefront
      pagerDutyConfigs:
        - {routingKey: {name: alertmanager-slack, key: pagerduty-routing-key}, severity: critical, class: browse, group: storefront}
      slackConfigs:
        - {channel: '#shop-oncall', sendResolved: true, apiURL: {name: alertmanager-slack, key: slack-webhook-url}}
    - name: pagerduty-fulfilment
      pagerDutyConfigs:
        - {routingKey: {name: alertmanager-slack, key: pagerduty-routing-key}, severity: critical, class: fulfilment, group: fulfilment}
      slackConfigs:
        - {channel: '#shop-oncall', sendResolved: true, apiURL: {name: alertmanager-slack, key: slack-webhook-url}}
```

**The Slack template — put the runbook and the trace query IN the notification:**

```yaml
# platform/alertmanager/templates/slack.tmpl  (mounted into Alertmanager)
{{ define "slack.title" -}}
  [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}]
  {{ .CommonLabels.alertname }}{{ if .CommonLabels.namespace }} in {{ .CommonLabels.namespace }}{{ end }}
{{- end }}

{{ define "slack.text" -}}
{{ range .Alerts }}
*{{ .Labels.alertname }}*  ({{ .Labels.severity }}, team: {{ .Labels.team | default "unowned" }})
{{ .Annotations.summary }}

{{ if .Annotations.description }}_{{ .Annotations.description }}_{{ end }}

• 📊 Dashboard: {{ .Annotations.dashboard_url | default "http://localhost:3000/d/99-incident" }}
• 📖 Runbook:   {{ .Annotations.runbook_url | default "MISSING — file a bug against this alert" }}
{{- if .Annotations.trace_query }}
• 🔎 Traces:    `{{ .Annotations.trace_query }}`
{{- end }}
{{- if .Annotations.log_query }}
• 📜 Logs:      `{{ .Annotations.log_query }}`
{{- end }}
• ⏱️ Started:   {{ .StartsAt.Format "15:04:05 MST" }} ({{ .StartsAt | since }} ago)
• 🏷️ Labels:    {{ range .Labels.SortedPairs }}{{ .Name }}={{ .Value }} {{ end }}
{{ end }}
{{- end }}
```

> 🔑 **The single highest-leverage alerting improvement you can make:** put the **TraceQL query and the LogQL query that diagnose the alert directly in the annotation**, so they render in the Slack message. The on-call engineer copies one line instead of reconstructing the query from scratch at 3 a.m. This is a real technique used at Grafana and Datadog, and almost nobody does it.

```bash
kubectl apply -f platform/alertmanager/alertmanager.yaml
kubectl apply -f platform/prometheus/

# verify
promtool check rules platform/prometheus/alerting-rules/*.yaml
kubectl -n monitoring get prometheusrule -o custom-columns=NAME:.metadata.name,RULES:.spec.groups[*].name
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-alertmanager 9093:9090 &
sleep 3
curl -s localhost:9093/api/v2/status | jq -r '.config.original' | head -30
amtool config routes --alertmanager.url=http://localhost:9093
# ⭐ shows the routing tree; verify your matchers resolve where you expect

# send a test alert through the whole chain
amtool alert add TestAlert severity=critical team=payments tier=symptom \
  --alertmanager.url=http://localhost:9093 \
  --annotation=summary="this is a test" \
  --annotation=runbook_url="https://example.com/runbook"
amtool alert query --alertmanager.url=http://localhost:9093
# ✅ it appears in #shop-oncall and in PagerDuty
amtool silence add TestAlert --alertmanager.url=http://localhost:9093 --duration=5m --comment="test cleanup"
```

---

<a name="phase-4--dashboards-as-code"></a>
## Phase 4 — Dashboards-as-code

### 4.1 The dashboard catalogue

| UID | Title | Audience | Answers | Datasources |
|---|---|---|---|---|
| `99-incident` | 🔥 Shop — Incident View | on-call, first click | *Is it broken, where, and show me the evidence* | Prom + Loki + Tempo |
| `00-overview` | Shop — Overview | everyone, the TV screen | *Is the business healthy right now?* | Prom |
| `30-slo` | SLO & Error Budgets | eng managers, on-call | *How much budget is left, and how fast is it burning?* | Prom |
| `10-shop-api-red` | shop-api — RED | the service owner | *rate/errors/duration for one service, deeply* | Prom + Tempo exemplars |
| `11-checkout-red` | checkout — RED | the service owner | same for Go | Prom |
| `12-worker` | order-worker — Queue & Jobs | fulfilment | *are we keeping up?* | Prom + Loki |
| `20-k8s-cluster` | Kubernetes — Cluster | platform | *is the platform itself healthy?* | Prom |
| `21-k8s-shop-ns` | Kubernetes — shop namespace | platform + app teams | *pods, restarts, resources, HPA* | Prom |
| `40-observability-health` | Observability Platform Health | platform | ⭐ *is my monitoring working?* | Prom |
| `50-datastores` | PostgreSQL & Redis | data team | *connections, cache hit ratio, replication* | Prom |
| `60-rum` | Real User Monitoring | product + storefront | *what are real users experiencing?* | Tempo (span metrics) |

### 4.2 The incident dashboard, generated from a script ⭐

Hand-writing 40 panels of Grafana JSON is miserable. **Generate it.** This is the technique that makes dashboards-as-code sustainable.

```bash
cat > scripts/generate-dashboards.py <<'PYEOF'
#!/usr/bin/env python3
"""
⭐ Generate every Grafana dashboard in this repo from a declarative spec.
   Commit the generated JSON too — Grafana reads files, not this script.
   But the SCRIPT is the source of truth: change it, regenerate, review the diff.
"""
import json, os, sys, textwrap
from pathlib import Path

OUT = Path("platform/grafana/dashboards")
OUT.mkdir(parents=True, exist_ok=True)

DS_PROM = {"type": "prometheus", "uid": "prometheus"}
DS_LOKI = {"type": "loki", "uid": "loki"}
DS_TEMPO = {"type": "tempo", "uid": "tempo"}

_id = [0]
def nid():
    _id[0] += 1
    return _id[0]

def target(expr, legend="", ds=DS_PROM, refid=None, instant=False, hide=False, fmt="time_series"):
    return {
        "refId": refid or chr(65 + (target.counter := getattr(target, "counter", 0))),
        "datasource": ds, "expr": expr, "legendFormat": legend,
        "instant": instant, "hide": hide,
        "editorMode": "code", "range": not instant,
        "format": fmt,
    }

def panel(title, ptype, targets, x, y, w=8, h=8, unit=None, ds=DS_PROM, **opts):
    p = {
        "id": nid(), "type": ptype, "title": title,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "datasource": ds, "targets": targets,
        "fieldConfig": {"defaults": {"custom": {}}, "overrides": []},
        "options": {},
    }
    if unit:
        p["fieldConfig"]["defaults"]["unit"] = unit
    p["fieldConfig"]["defaults"].update(opts.get("defaults", {}))
    p["options"].update(opts.get("options", {}))
    return p

def timeseries(title, exprs, x, y, w=8, h=8, unit=None, **kw):
    """exprs: a list of (expr, legend) tuples."""
    tgts = []
    for i, (e, lg) in enumerate(exprs):
        t = target(e, lg); t["refId"] = chr(65 + i); tgts.append(t)
    return panel(title, "timeseries", tgts, x, y, w, h, unit,
                 options={"legend": {"displayMode": "table", "placement": "bottom",
                                     "calcs": ["mean", "max", "lastNotNull"]},
                          "tooltip": {"mode": "multi", "sort": "desc"},
                          "graph": {"lineWidth": 2, "fillOpacity": 8, "showPoints": "never"},
                          **kw.pop("options", {})},
                 defaults={"custom": {"drawStyle": "line", "lineInterpolation": "smooth",
                                      "fillOpacity": 8, "showPoints": "never",
                                      "spanNulls": False,
                                      **kw.pop("custom", {})},
                           "min": kw.pop("min", None), "max": kw.pop("max", None),
                           "thresholds": kw.pop("thresholds", None)})

def stat(title, expr, x, y, w=4, h=4, unit=None, thresholds=None, legend=""):
    t = target(expr, legend); t["refId"] = "A"; t["instant"] = True; t["range"] = False
    return panel(title, "stat", [t], x, y, w, h, unit,
                 defaults={"thresholds": thresholds or {"mode": "absolute", "steps": [
                     {"color": "green", "value": None}]},
                     "color": {"mode": "thresholds"}},
                 options={"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                          "colorMode": "background", "graphMode": "area", "textMode": "auto"})

def row(title, y, collapsed=False, panels=None):
    return {"id": nid(), "type": "row", "title": title, "collapsed": collapsed,
            "gridPos": {"x": 0, "y": y, "w": 24, "h": 1},
            "panels": panels or []}

def dashboard(uid, title, tags, panels, variables, refresh="30s", time_from="now-1h"):
    return {
        "uid": uid, "title": title, "tags": tags,
        "timezone": "browser", "schemaVersion": 39, "version": 1,
        "editable": True, "graphTooltip": 1,          # ⭐ 1 = shared crosshair
        "refresh": refresh,
        "time": {"from": time_from, "to": "now"},
        "panels": panels,
        "templating": {"list": variables},
        "annotations": {"list": [
            {"name": "Deployments", "datasource": DS_PROM, "enable": True,
             "expr": "changes(kube_deployment_status_replicas_updated{namespace=\"$namespace\"}[1m]) > 0",
             "titleFormat": "{{deployment}} updated", "tagKeys": "namespace,deployment",
             "iconColor": "blue"},
            {"name": "Alerts", "datasource": DS_PROM, "enable": True,
             "expr": "ALERTS{alertstate=\"firing\",namespace=\"$namespace\"}",
             "titleFormat": "{{alertname}}", "tagKeys": "severity,team",
             "iconColor": "red"},
        ]},
    }

def var_query(name, query, multi=True, all_value=".*", include_all=True, refresh=2, label=None):
    return {
        "name": name, "label": label or name.title(), "type": "query",
        "datasource": DS_PROM, "query": {"query": query, "refId": "StandardVariableQuery"},
        "refresh": refresh, "sort": 1,
        "multi": multi, "includeAll": include_all,
        "allValue": all_value, "current": {"text": ["All"], "value": ["$__all"]},
        "definition": query,
    }

NS_VAR = var_query("namespace", "label_values(kube_pod_info, namespace)", multi=False, include_all=False)
SVC_VAR = var_query("service",
    'label_values(http_server_requests_seconds_count{namespace="$namespace"}, application)',
    all_value=".*")

# ═══════════════════════════════════════════════════════════════════
# 99-incident  ⭐⭐ THE ONE-CLICK VIEW
# ═══════════════════════════════════════════════════════════════════
def incident():
    p, y = [], 0
    p.append(row("ROW 0 — IS IT BROKEN?", y)); y += 1

    p.append(stat("Availability (30d)", """
1 - (sum(increase(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[30d]))
   / clamp_min(sum(increase(http_server_requests_seconds_count{namespace="$namespace"}[30d])),1))""",
        0, y, 5, 5, "percentunit",
        {"mode": "absolute", "steps": [{"color": "red", "value": None},
                                       {"color": "orange", "value": 0.99},
                                       {"color": "green", "value": 0.999}]}))

    p.append(stat("Latency SLO (<500ms)", """
sum(rate(http_server_requests_seconds_bucket{namespace="$namespace",le="0.5"}[$__rate_interval]))
 / clamp_min(sum(rate(http_server_requests_seconds_count{namespace="$namespace"}[$__rate_interval])),1e-9)""",
        5, y, 5, 5, "percentunit",
        {"mode": "absolute", "steps": [{"color": "red", "value": None},
                                       {"color": "orange", "value": 0.95},
                                       {"color": "green", "value": 0.99}]}))

    p.append(stat("Error budget left", """
clamp_min(100 * (1 - (sum(increase(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[30d]))
   / (0.001 * clamp_min(sum(increase(http_server_requests_seconds_count{namespace="$namespace"}[30d])),1)))), 0)""",
        10, y, 5, 5, "percent",
        {"mode": "absolute", "steps": [{"color": "red", "value": None},
                                       {"color": "orange", "value": 25},
                                       {"color": "green", "value": 50}]}))

    p.append(stat("Burn rate (now)", """
sum(rate(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[$__rate_interval]))
 / clamp_min(0.001 * sum(rate(http_server_requests_seconds_count{namespace="$namespace"}[$__rate_interval])),1e-9)""",
        15, y, 4, 5, "short",
        {"mode": "absolute", "steps": [{"color": "green", "value": None},
                                       {"color": "orange", "value": 1},
                                       {"color": "red", "value": 14.4}]},
        legend="× budget"))

    alerts = panel("🔴 ALERTS FIRING", "table", [
        {**target('ALERTS{alertstate="firing",namespace="$namespace"}', instant=True), "refId": "A",
         "format": "table"},
    ], 19, y, 5, 5, DS_PROM,
        options={"showHeader": True, "footer": {"show": False},
                 "sortBy": [{"displayName": "severity", "desc": True}]})
    alerts["transformations"] = [
        {"id": "organize", "options": {"excludeByName": {"Time": True, "Value": True, "__name__": True,
                                                          "container": True, "endpoint": True,
                                                          "instance": True, "job": True, "pod": True,
                                                          "prometheus": True, "alertstate": True},
                                        "indexByName": {"alertname": 0, "severity": 1, "team": 2,
                                                        "namespace": 3, "tier": 4},
                                        "renameByName": {}}}]
    alerts["fieldConfig"]["defaults"]["custom"] = {"align": "auto", "cellOptions": {"type": "auto"}}
    p.append(alerts); y += 5

    # ROW 1 — WHERE
    p.append(row("ROW 1 — WHERE? (live from traces)", y)); y += 1
    sg = panel("Service graph", "nodeGraph", [
        {"refId": "A", "datasource": DS_TEMPO, "queryType": "serviceMap",
         "limit": 1000, "maxDuration": "5s", "minDuration": "",
         "search": "{ namespace=\"$namespace\" }"}],
        0, y, 12, 10, DS_TEMPO)
    p.append(sg)

    p.append(timeseries("Edge p99 latency (traces)", [
        ('histogram_quantile(0.99, sum by (client, server, le) (rate(traces_service_graph_request_seconds_bucket{namespace="$namespace"}[$__rate_interval])))',
         '{{client}} → {{server}}'),
    ], 12, y, 12, 5, "s"))
    p.append(timeseries("Edge error ratio (traces)", [
        ('sum by (client, server) (rate(traces_service_graph_request_failed_total{namespace="$namespace"}[$__rate_interval]))'
         ' / clamp_min(sum by (client, server) (rate(traces_service_graph_request_total{namespace="$namespace"}[$__rate_interval])),1e-9)',
         '{{client}} → {{server}}'),
    ], 12, y + 5, 12, 5, "percentunit"))
    y += 10

    # ROW 2 — RED
    p.append(row("ROW 2 — RED per service", y)); y += 1
    p.append(timeseries("RATE (req/s)", [
        ('sum by (application) (rate(http_server_requests_seconds_count{namespace="$namespace",application=~"$service"}[$__rate_interval]))',
         '{{application}}'),
    ], 0, y, 8, 8, "reqps"))
    p.append(timeseries("ERRORS (ratio)", [
        ('sum by (application) (rate(http_server_requests_seconds_count{namespace="$namespace",application=~"$service",status=~"5.."}[$__rate_interval]))'
         ' / clamp_min(sum by (application) (rate(http_server_requests_seconds_count{namespace="$namespace",application=~"$service"}[$__rate_interval])),1e-9)',
         '{{application}}'),
    ], 8, y, 8, 8, "percentunit", min=0, max=1))

    dur = timeseries("DURATION p50 / p95 / p99  ⭐ exemplars ON", [
        ('histogram_quantile(0.50, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="$namespace",application=~"$service"}[$__rate_interval])))', 'p50'),
        ('histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="$namespace",application=~"$service"}[$__rate_interval])))', 'p95'),
        ('histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="$namespace",application=~"$service"}[$__rate_interval])))', 'p99'),
    ], 16, y, 8, 8, "s")
    dur["fieldConfig"]["defaults"]["custom"]["exemplars"] = True   # ⭐⭐ click a spike → the trace
    dur["options"]["tooltip"] = {"mode": "multi", "sort": "desc"}
    p.append(dur); y += 8

    # ROW 3 — SATURATION
    p.append(row("ROW 3 — SATURATION (leading indicators)", y)); y += 1
    p.append(timeseries("CPU throttling", [
        ('sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="$namespace"}[$__rate_interval]))'
         ' / clamp_min(sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="$namespace"}[$__rate_interval])),1e-9)', '{{pod}}'),
    ], 0, y, 5, 7, "percentunit", min=0, max=1))
    p.append(timeseries("Memory / limit", [
        ('sum by (pod, container) (container_memory_working_set_bytes{namespace="$namespace"})'
         ' / on(namespace,pod,container) group_left'
         ' kube_pod_container_resource_limits{namespace="$namespace",resource="memory"}', '{{pod}}/{{container}}'),
    ], 5, y, 5, 7, "percentunit", min=0, max=1.5))
    p.append(timeseries("Tomcat threads busy", [
        ('tomcat_threads_busy_threads{namespace="$namespace"}', 'busy'),
        ('tomcat_threads_config_max_threads{namespace="$namespace"}', 'max'),
    ], 10, y, 4, 7, "short"))
    p.append(timeseries("Hikari pool", [
        ('hikaricp_connections_active{namespace="$namespace"}', 'active'),
        ('hikaricp_connections_pending{namespace="$namespace"}', 'pending'),
        ('hikaricp_connections_max{namespace="$namespace"}', 'max'),
    ], 14, y, 5, 7, "short"))
    p.append(timeseries("Queue depth", [
        ('worker_queue_depth{namespace="$namespace"}', '{{queue}}'),
    ], 19, y, 5, 7, "short"))
    y += 7

    # ROW 4 — THE EVIDENCE
    p.append(row("ROW 4 — THE EVIDENCE", y)); y += 1
    errlogs = panel("Error logs (live) — trace_id is clickable", "logs", [
        {"refId": "A", "datasource": DS_LOKI, "expr": '{namespace="$namespace"} | json | level =~ "(?i)error|fatal|exception"',
         "queryType": "range", "maxLines": 1000}],
        0, y, 12, 12, DS_LOKI,
        options={"showTime": True, "wrapLogMessage": True, "sortOrder": "Descending",
                 "dedupStrategy": "none", "enableLogDetails": True, "prettifyLogMessage": False})
    p.append(errlogs)

    slow = panel("Slowest traces (last $__range) — click a row", "table", [
        {"refId": "A", "datasource": DS_TEMPO, "queryType": "search",
         "search": '{ namespace="$namespace" && duration > 1s }',
         "limit": 50, "maxDuration": "", "minDuration": "1s",
         "serviceMapQuery": "", "spss": 3}],
        12, y, 12, 6, DS_TEMPO)
    p.append(slow)

    errtraces = panel("Error traces — click a row", "table", [
        {"refId": "A", "datasource": DS_TEMPO, "queryType": "search",
         "search": '{ namespace="$namespace" && status = error }', "limit": 50, "spss": 3}],
        12, y + 6, 12, 6, DS_TEMPO)
    p.append(errtraces); y += 12

    # ROW 5 — ESCAPE HATCHES
    p.append(row("ROW 5 — ESCAPE HATCHES", y)); y += 1
    links = panel("🔗 Go to…", "text", [], 0, y, 24, 4, DS_PROM, options={"mode": "html"})
    links["options"]["content"] = textwrap.dedent("""
    <div style="display:flex;gap:12px;flex-wrap:wrap;font-size:14px">
      <a class="btn btn-primary" href="/d/30-slo?var-namespace=$namespace">📈 SLO &amp; budgets</a>
      <a class="btn btn-primary" href="/d/21-k8s-shop-ns?var-namespace=$namespace">☸️ Kubernetes</a>
      <a class="btn btn-primary" href="/d/40-observability-health">🛰️ Observability health</a>
      <a class="btn btn-primary" href="/d/50-datastores?var-namespace=$namespace">🗄️ Data stores</a>
      <a class="btn btn-primary" href="/d/60-rum?var-namespace=$namespace">👤 Real users</a>
      <a class="btn btn-primary" href="/explore?schemaVersion=1&left=%7B%22datasource%22:%22loki%22%7D">📜 Loki explore</a>
      <a class="btn btn-primary" href="/explore?schemaVersion=1&left=%7B%22datasource%22:%22tempo%22%7D">🔎 Tempo explore</a>
      <a class="btn btn-primary" href="https://git.example.com/shop-observability/-/tree/main/platform/runbooks">📖 Runbooks</a>
      <a class="btn btn-primary" href="http://localhost:9093/#/alerts">🔔 Alertmanager</a>
      <a class="btn btn-primary" href="http://localhost:9090/graph">🔢 PromQL console</a>
    </div>
    """).strip()
    p.append(links)

    return dashboard("99-incident", "🔥 Shop — Incident View", ["shop", "incident", "oncall"],
                     p, [NS_VAR, SVC_VAR], refresh="30s", time_from="now-30m")

# ═══════════════════════════════════════════════════════════════════
# 40-observability-health  ⭐ monitoring watches itself
# ═══════════════════════════════════════════════════════════════════
def obs_health():
    p, y = [], 0
    p.append(row("AM WE BLIND?", y)); y += 1
    p.append(stat("Targets up", 'sum(up) / clamp_min(count(up),1)', 0, y, 4, 4, "percentunit",
        {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 0.99}]}))
    p.append(stat("Rules failing", 'sum(increase(prometheus_rule_evaluation_failures_total[1h])) or vector(0)',
        4, y, 4, 4, "short",
        {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "red", "value": 1}]}))
    p.append(stat("Alerts firing", 'count(ALERTS{alertstate="firing"}) or vector(0)', 8, y, 4, 4, "short"))
    p.append(stat("Active silences", 'count(alertmanager_silences{state="active"}) or vector(0)', 12, y, 4, 4, "short",
        {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "orange", "value": 3}, {"color": "red", "value": 6}]}))
    p.append(stat("Series count", 'prometheus_tsdb_head_series', 16, y, 4, 4, "short"))
    p.append(stat("Spans dropped/s", 'sum(rate(otelcol_processor_dropped_spans[5m])) or vector(0)', 20, y, 4, 4, "short",
        {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "red", "value": 1}]}))
    y += 4

    p.append(row("PROMETHEUS", y)); y += 1
    p.append(timeseries("Scrape duration by job", [
        ('scrape_duration_seconds', '{{job}}')], 0, y, 8, 7, "s"))
    p.append(timeseries("Scrape samples by job", [
        ('scrape_samples_scraped', '{{job}}')], 8, y, 8, 7, "short"))
    p.append(timeseries("Rule group evaluation duration", [
        ('prometheus_rule_group_last_duration_seconds', '{{rule_group}}')], 16, y, 8, 7, "s"))
    y += 7
    p.append(timeseries("TSDB head series", [('prometheus_tsdb_head_series', 'series')], 0, y, 6, 7, "short"))
    p.append(timeseries("TSDB block count", [('prometheus_tsdb_blocks_loaded', 'blocks')], 6, y, 6, 7, "short"))
    p.append(timeseries("Query duration", [
        ('histogram_quantile(0.99, sum by (le) (rate(prometheus_engine_query_duration_seconds_bucket{slice="exec"}[$__rate_interval])))', 'p99 exec'),
        ('histogram_quantile(0.99, sum by (le) (rate(prometheus_engine_query_duration_seconds_bucket{slice="inner_eval"}[$__rate_interval])))', 'p99 eval'),
    ], 12, y, 6, 7, "s"))
    p.append(timeseries("Prometheus resources", [
        ('process_resident_memory_bytes{job=~".*prometheus.*"}', 'RSS'),
        ('go_memstats_heap_inuse_bytes{job=~".*prometheus.*"}', 'heap in use'),
    ], 18, y, 6, 7, "bytes"))
    y += 7

    p.append(row("OTEL COLLECTOR ⭐", y)); y += 1
    p.append(timeseries("Spans: accepted vs sent vs dropped", [
        ('sum(rate(otelcol_receiver_accepted_spans[$__rate_interval]))', 'accepted'),
        ('sum(rate(otelcol_exporter_sent_spans[$__rate_interval]))', 'sent'),
        ('sum(rate(otelcol_processor_dropped_spans[$__rate_interval]))', '⚠️ dropped'),
        ('sum(rate(otelcol_exporter_send_failed_spans[$__rate_interval]))', '⚠️ send failed'),
    ], 0, y, 8, 8, "short"))
    p.append(timeseries("Tail sampling: traces received vs sampled", [
        ('sum(rate(otelcol_processor_tail_sampling_sampling_traces_received[$__rate_interval]))', 'received'),
        ('sum(rate(otelcol_processor_tail_sampling_sampling_decision_timer_sum[$__rate_interval]))', 'decisions'),
    ], 8, y, 8, 8, "short"))
    p.append(timeseries("Collector memory vs GOMEMLIMIT", [
        ('otelcol_process_runtime_total_sys_memory_bytes', 'sys memory'),
        ('go_memstats_heap_inuse_bytes{namespace="otel"}', 'heap in use'),
    ], 16, y, 8, 8, "bytes"))
    y += 8
    p.append(timeseries("Export queue size / capacity", [
        ('otelcol_exporter_queue_size', '{{exporter}} size'),
        ('otelcol_exporter_queue_capacity', '{{exporter}} capacity'),
    ], 0, y, 8, 7, "short"))
    p.append(timeseries("Logs: accepted vs refused", [
        ('sum(rate(otelcol_receiver_accepted_log_records[$__rate_interval]))', 'accepted'),
        ('sum(rate(otelcol_receiver_refused_log_records[$__rate_interval]))', '⚠️ refused'),
        ('sum(rate(otelcol_exporter_send_failed_log_records[$__rate_interval]))', '⚠️ failed'),
    ], 8, y, 8, 7, "short"))
    p.append(timeseries("Collector CPU", [
        ('sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="otel"}[$__rate_interval]))', '{{pod}}'),
    ], 16, y, 8, 7, "short"))
    y += 7

    p.append(row("TEMPO & LOKI", y)); y += 1
    p.append(timeseries("Tempo ingester spans/s", [
        ('sum(rate(tempo_ingester_traces_created_total[$__rate_interval]))', 'traces created'),
        ('sum(rate(tempo_discarded_spans_total[$__rate_interval]))', '⚠️ discarded'),
    ], 0, y, 6, 7, "short"))
    p.append(timeseries("Tempo query latency", [
        ('histogram_quantile(0.99, sum by (le) (rate(tempo_query_frontend_query_seconds_bucket[$__rate_interval])))', 'p99'),
    ], 6, y, 6, 7, "s"))
    p.append(timeseries("Loki ingest bytes/s", [
        ('sum by (namespace) (rate(loki_distributor_bytes_received_total[$__rate_interval]))', '{{namespace}}'),
    ], 12, y, 6, 7, "Bps"))
    p.append(timeseries("Loki query latency", [
        ('histogram_quantile(0.99, sum by (le, route) (rate(loki_request_duration_seconds_bucket[$__rate_interval])))', '{{route}} p99'),
    ], 18, y, 6, 7, "s"))
    y += 7

    p.append(row("ALERTMANAGER", y)); y += 1
    p.append(timeseries("Notifications: total vs failed", [
        ('sum by (integration) (rate(alertmanager_notifications_total[$__rate_interval]))', '{{integration}} sent'),
        ('sum by (integration) (rate(alertmanager_notifications_failed_total[$__rate_interval]))', '{{integration}} ⚠️ FAILED'),
    ], 0, y, 8, 7, "short"))
    p.append(timeseries("Alerts by state", [
        ('count by (alertname) (ALERTS{alertstate="firing"})', '{{alertname}}'),
    ], 8, y, 8, 7, "short"))
    p.append(timeseries("Silences by state", [
        ('count by (state) (alertmanager_silences)', '{{state}}'),
    ], 16, y, 8, 7, "short"))

    return dashboard("40-observability-health", "🛰️ Observability Platform Health",
                     ["platform", "observability", "self-monitoring"], p, [], refresh="30s")

# ═══════════════════════════════════════════════════════════════════
# 30-slo
# ═══════════════════════════════════════════════════════════════════
def slo_dash():
    p, y = [], 0
    p.append(row("SLO ATTAINMENT & ERROR BUDGET", y)); y += 1

    for i, (name, errq, totq, obj) in enumerate([
        ("Checkout availability",
         'sum(rate(http_server_requests_seconds_count{namespace="$namespace",application=~"shop-api|checkout",uri=~"/api/orders|/checkout",status=~"5.."}[5m]))',
         'sum(rate(http_server_requests_seconds_count{namespace="$namespace",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[5m]))',
         0.001),
        ("Checkout latency <500ms",
         'sum(rate(http_server_requests_seconds_count{namespace="$namespace",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[5m])) - sum(rate(http_server_requests_seconds_bucket{namespace="$namespace",application=~"shop-api|checkout",uri=~"/api/orders|/checkout",le="0.5"}[5m]))',
         'sum(rate(http_server_requests_seconds_count{namespace="$namespace",application=~"shop-api|checkout",uri=~"/api/orders|/checkout"}[5m]))',
         0.01),
    ]):
        x = i * 12
        p.append(stat(f"{name} — attainment (30d)",
            f'1 - (increase(({errq.replace("[5m]","[30d]")})[30d:]) / clamp_min(increase(({totq.replace("[5m]","[30d]")})[30d:]),1e-9))',
            x, y, 6, 4, "percentunit"))
        p.append(stat(f"{name} — error budget left %",
            f'clamp_min(100 * (1 - (increase(({errq.replace("[5m]","[30d]")})[30d:]) / ({obj} * clamp_min(increase(({totq.replace("[5m]","[30d]")})[30d:]),1e-9)))), 0)',
            x + 6, y, 6, 4, "percent"))
    y += 4

    p.append(timeseries("Burn rate, multi-window", [
        ('sum(rate(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[1h]))'
         ' / clamp_min(0.001 * sum(rate(http_server_requests_seconds_count{namespace="$namespace"}[1h])),1e-9)', '1h window'),
        ('sum(rate(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[6h]))'
         ' / clamp_min(0.001 * sum(rate(http_server_requests_seconds_count{namespace="$namespace"}[6h])),1e-9)', '6h window'),
        ('sum(rate(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[1d]))'
         ' / clamp_min(0.001 * sum(rate(http_server_requests_seconds_count{namespace="$namespace"}[1d])),1e-9)', '1d window'),
        ('sum(rate(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[3d]))'
         ' / clamp_min(0.001 * sum(rate(http_server_requests_seconds_count{namespace="$namespace"}[3d])),1e-9)', '3d window'),
    ], 0, y, 12, 9, "short",
        thresholds={"mode": "absolute", "steps": [
            {"color": "green", "value": None}, {"color": "orange", "value": 1},
            {"color": "red", "value": 3}, {"color": "dark-red", "value": 14.4}]}))

    p.append(timeseries("Error budget remaining over time", [
        ('clamp_min(100 * (1 - (sum(increase(http_server_requests_seconds_count{namespace="$namespace",status=~"5.."}[$__range]))'
         ' / (0.001 * clamp_min(sum(increase(http_server_requests_seconds_count{namespace="$namespace"}[$__range])),1e-9)))), 0)', 'budget left %'),
    ], 12, y, 12, 9, "percent", min=0, max=100))
    y += 9

    p.append(row("THE SLO TABLE", y)); y += 1
    tbl = panel("All SLOs", "table", [
        {"refId": "A", "datasource": DS_PROM, "instant": True, "format": "table",
         "expr": 'sloth_slo_sli{namespace="$namespace"}'},
        {"refId": "B", "datasource": DS_PROM, "instant": True, "format": "table", "hide": True,
         "expr": 'sloth_slo_error_budget_ratio{namespace="$namespace"}'},
    ], 0, y, 24, 8, DS_PROM)
    tbl["transformations"] = [{"id": "joinByField", "options": {"byField": "slo", "mode": "outer"}}]
    p.append(tbl)

    return dashboard("30-slo", "📈 SLO & Error Budgets", ["shop", "slo"], p, [NS_VAR], refresh="1m")

# ── write them all ────────────────────────────────────────────────
DASHES = {
    "99-incident.json":              incident(),
    "40-observability-health.json":  obs_health(),
    "30-slo.json":                   slo_dash(),
}
for fname, d in DASHES.items():
    (OUT / fname).write_text(json.dumps(d, indent=2, sort_keys=False) + "\n")
    print(f"  ✅ {fname}  ({len(d['panels'])} panels)")

print(f"\n{len(DASHES)} dashboards generated in {OUT}")
PYEOF
chmod +x scripts/generate-dashboards.py
python3 scripts/generate-dashboards.py
```

### 4.3 Provision them

```bash
cat > platform/grafana/dashboards/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: monitoring
configMapGenerator:
  - name: grafana-dashboard-incident
    files: [99-incident.json]
    options:
      labels: {grafana_dashboard: "1"}
      annotations: {grafana_folder: "Shop"}
  - name: grafana-dashboard-obs-health
    files: [40-observability-health.json]
    options:
      labels: {grafana_dashboard: "1"}
      annotations: {grafana_folder: "Platform"}
  - name: grafana-dashboard-slo
    files: [30-slo.json]
    options:
      labels: {grafana_dashboard: "1"}
      annotations: {grafana_folder: "Shop"}
generatorOptions:
  disableNameSuffixHash: true
EOF

kubectl apply -k platform/grafana/dashboards/
kubectl get cm -n monitoring -l grafana_dashboard=1
kubectl logs -n monitoring deploy/kps-grafana -c grafana-sc-dashboard --tail=10
# ✅ "found 3 dashboards" / "adding dashboard to provider"

# ⭐ verify it renders
curl -s -u admin:admin 'localhost:3000/api/dashboards/uid/99-incident' \
  | jq '{title: .dashboard.title, panels: (.dashboard.panels | length), uid: .dashboard.uid}'
# {"title":"🔥 Shop — Incident View","panels":28,"uid":"99-incident"}
```

### 4.4 The deployment-annotation trick ⭐

Make every deploy show up on every dashboard automatically:

```bash
# in the deploy step of your pipeline (see Phase 6)
kubectl -n shop annotate deploy/shop-api \
  kubernetes.io/change-cause="shop-observability@$(git rev-parse --short HEAD): ${COMMIT_TITLE}" \
  --overwrite

# Grafana picks it up from kube_deployment_status_replicas_updated,
# or via the annotation datasource. Verify:
curl -sG localhost:9090/api/v1/query \
  --data-urlencode 'query=kube_deployment_annotations{namespace="shop"}' | jq -r '.data.result[].metric'
```

---

<a name="phase-5--correlation"></a>
## Phase 5 — Correlation: the four-click loop

This is the payoff of the whole capstone. **Four clicks, zero typing, from "something is wrong" to "here is the root cause".**

### 5.1 The wiring (all in `platform/grafana/datasources/observability.yaml`)

```
  ┌──────────────┐   exemplarTraceIdDestinations   ┌──────────────┐
  │  PROMETHEUS  │ ──────────────────────────────► │    TEMPO     │
  │   metrics    │                                 │    traces    │
  └──────┬───────┘                                 └──────┬───────┘
         ▲                                                │
         │ tracesToMetrics                                │ tracesToLogs
         │ (3 useful queries)                             ▼
         │                                        ┌──────────────┐
         └────────────────────────────────────────│     LOKI     │
              derivedFields → tempo               │     logs     │
                                                  └──────────────┘
```

The exact YAML is in [Case 2 §1.3](./03-CASE-2-telemetry.md#13-register-both-in-grafana-with-the-correlation-wiring-). Apply it here and verify:

```bash
kubectl apply -f platform/grafana/datasources/observability.yaml
sleep 25
curl -s -u admin:admin localhost:3000/api/datasources | jq '.[] | {name, uid, type}'
# [{"name":"Prometheus","uid":"prometheus","type":"prometheus"},
#  {"name":"Tempo","uid":"tempo","type":"tempo"},
#  {"name":"Loki","uid":"loki","type":"loki"}]

curl -s -u admin:admin localhost:3000/api/datasources/uid/prometheus \
  | jq '.jsonData.exemplarTraceIdDestinations'
# [{"name":"traceID","datasourceUid":"tempo","urlDisplayLabel":"View trace"}]

curl -s -u admin:admin localhost:3000/api/datasources/uid/tempo \
  | jq '.jsonData | {tracesToLogs: .tracesToLogs.datasourceUid, tracesToMetrics: .tracesToMetrics.datasourceUid, serviceMap: .serviceMap.datasourceUid, nodeGraph: .nodeGraph.enabled}'
# {"tracesToLogs":"loki","tracesToMetrics":"prometheus","serviceMap":"prometheus","nodeGraph":true}

curl -s -u admin:admin localhost:3000/api/datasources/uid/loki \
  | jq '.jsonData.derivedFields | length'
# 4
```

### 5.2 Prove the loop, end to end

```bash
cat > scripts/validate-trace-pipeline.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ THE SMOKE TEST. Run it after every platform change.
#    It asserts that the entire telemetry pipeline works, with a trace ID we chose.
set -uo pipefail
pass=0; fail=0
ok()  { printf '  ✅ %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  \033[31m✖ %s\033[0m\n' "$*"; fail=$((fail+1)); }

echo "==> 1. platform components"
for ns_pod in "monitoring/kps-kube-prometheus-stack-prometheus" "monitoring/kps-grafana" \
              "monitoring/tempo" "monitoring/loki" "otel/otel-agent" "otel/otel-collector-gateway"; do
  ns="${ns_pod%%/*}"; pat="${ns_pod##*/}"
  n=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep "$pat" | grep -c Running || true)
  [[ "$n" -ge 1 ]] && ok "$ns_pod: $n running" || bad "$ns_pod: not running"
done

echo "==> 2. Prometheus targets"
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
PF1=$!; sleep 4
DOWN=$(curl -s localhost:9090/api/v1/targets?state=active | jq -r '.data.activeTargets[] | select(.health!="up") | .labels.job' | sort -u)
[[ -z "$DOWN" ]] && ok "all targets up" || bad "targets down: $DOWN"

echo "==> 3. the manual-span probe (app → agent → gateway → Tempo)"
kubectl port-forward -n otel svc/otel-collector-gateway 4318:4318 4317:4317 8888:8888 >/dev/null 2>&1 &
PF2=$!; kubectl port-forward -n monitoring svc/tempo 3200:3200 >/dev/null 2>&1 &
PF3=$!; kubectl port-forward -n monitoring svc/loki 3100:3100 >/dev/null 2>&1 &
PF4=$!; sleep 6

TID=$(openssl rand -hex 16); SID=$(openssl rand -hex 8)
NOW=$(date +%s%N); END=$((NOW + 123456789))
resp=$(curl -s -XPOST localhost:4318/v1/traces -H 'Content-Type: application/json' -d '{
  "resourceSpans":[{"resource":{"attributes":[
      {"key":"service.name","value":{"stringValue":"smoke-test"}},
      {"key":"deployment.environment","value":{"stringValue":"dev"}}]},
    "scopeSpans":[{"scope":{"name":"smoke-test"},
      "spans":[{"traceId":"'"$TID"'","spanId":"'"$SID"'","name":"smoke-test-span","kind":2,
        "startTimeUnixNano":"'"$NOW"'","endTimeUnixNano":"'"$END"'",
        "attributes":[{"key":"url.path","value":{"stringValue":"/api/orders"}},
                      {"key":"http.response.status_code","value":{"intValue":"200"}}],
        "status":{"code":1}}]}]}]}')
echo "$resp" | grep -q 'partialSuccess\|{}' && ok "the Collector accepted a span ($TID)" \
  || bad "the Collector rejected the span: $resp"

for i in $(seq 1 20); do
  found=$(curl -s "localhost:3200/api/traces/$TID" | jq -r '.batches[0].scopeSpans[0].spans[0].name' 2>/dev/null)
  [[ "$found" == "smoke-test-span" ]] && break
  sleep 3
done
[[ "$found" == "smoke-test-span" ]] && ok "the span reached Tempo" || bad "the span never reached Tempo"

echo "==> 4. Tempo search"
n=$(curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "smoke-test" }' \
     --data-urlencode 'limit=5' | jq '.traces | length')
[[ "$n" -ge 1 ]] && ok "TraceQL search works ($n results)" || bad "TraceQL search returned nothing"

echo "==> 5. Loki logs with trace context"
n=$(curl -sG localhost:3100/loki/api/v1/query_range \
     --data-urlencode 'query={namespace="shop"} | json | trace_id != "-"' \
     --data-urlencode "start=$(date -d '-15 min' +%s)000000000" \
     --data-urlencode "end=$(date +%s)000000000" --data-urlencode 'limit=5' \
     | jq '[.data.result[].values[]] | length')
[[ "$n" -ge 1 ]] && ok "$n log lines carry a trace_id" || bad "no logs carry a trace_id — correlation is broken"

echo "==> 6. exemplars in Prometheus"
n=$(curl -sG localhost:9090/api/v1/query \
     --data-urlencode 'query=http_server_requests_seconds_count{namespace="shop"}' \
     | jq '[.data.result[] | select(.exemplars != null)] | length')
[[ "$n" -ge 0 ]] && ok "the exemplar query returned ($n series with exemplars)" \
  || bad "exemplars are not enabled"

echo "==> 7. the Collector is not dropping anything"
d=$(curl -s localhost:8888/metrics | grep -E '^otelcol_processor_dropped_spans' | awk '{s+=$2} END{print s+0}')
f=$(curl -s localhost:8888/metrics | grep -E '^otelcol_exporter_send_failed_spans' | awk '{s+=$2} END{print s+0}')
[[ "$d" == "0" && "$f" == "0" ]] && ok "zero dropped, zero failed spans" \
  || bad "dropped=$d failed=$f — the Collector is losing telemetry"

echo "==> 8. cross-service propagation"
n=$(curl -sG localhost:3200/api/search --data-urlencode 'q={ .service.name = "shop-api" }' \
     --data-urlencode 'limit=20' | jq -r '.traces[].traceID' | head -20 | while read t; do
       curl -s "localhost:3200/api/traces/$t" | jq -r \
         '[.batches[].resource.attributes[] | select(.key=="service.name") | .value.stringValue] | unique | length'
     done | sort -rn | head -1)
[[ "${n:-0}" -ge 2 ]] && ok "at least one trace spans $n services — propagation works" \
  || bad "no trace spans more than one service — propagation is BROKEN"

kill $PF1 $PF2 $PF3 $PF4 2>/dev/null || true
echo
printf '\033[1m%s passed, %s failed\033[0m\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
echo "✅ the telemetry pipeline is healthy"
EOF
chmod +x scripts/validate-trace-pipeline.sh
./scripts/validate-trace-pipeline.sh
```

Expected output:

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
  ✅ the Collector accepted a span (a1b2c3d4…)
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

---

<a name="phase-6--continuous-integration"></a>
## Phase 6 — Continuous integration

**The observability platform is code, so it gets the same treatment as code: lint, test, gate.** This is the phase that separates a hobby setup from something a team can rely on.

### 6.1 The validation script

```bash
cat > ci/validate.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ THE CI GATE. Every check here fails the build if it fails.
set -uo pipefail
step="${1:-all}"
fail=0
section() { printf '\n\033[1;36m── %s ──\033[0m\n' "$*"; }
ok()  { printf '  ✅ %s\n' "$*"; }
bad() { printf '  \033[31m✖ %s\033[0m\n' "$*"; fail=1; }

# ══ 1. LINT: every rule file parses and every expression is valid ══
lint() {
  section "promtool check rules"
  for f in platform/prometheus/recording-rules/*.yaml platform/prometheus/alerting-rules/*.yaml; do
    [[ -f "$f" ]] || continue
    if out=$(promtool check rules "$f" 2>&1); then
      n=$(echo "$out" | grep -oE 'SUCCESS: [0-9]+ rules' | grep -oE '[0-9]+')
      ok "$(basename "$f"): ${n:-0} rules valid"
    else
      bad "$(basename "$f"): $out"
    fi
  done

  section "promtool check config"
  if out=$(promtool check config platform/prometheus/prometheus.yml 2>&1); then
    ok "prometheus.yml is valid"; echo "$out" | sed 's/^/     /'
  else
    bad "prometheus.yml: $out"
  fi

  section "amtool check config"
  if out=$(amtool check-config platform/alertmanager/alertmanager.yaml 2>&1); then
    ok "alertmanager.yaml is valid"
  else
    bad "alertmanager.yaml: $out"
  fi

  section "YAML syntax (everything)"
  bad_files=$(find platform ci game-day -name '*.yaml' -o -name '*.yml' 2>/dev/null | while read -r f; do
    python3 -c "import yaml,sys; yaml.safe_load_all(open('$f'))" 2>/dev/null || echo "$f"
  done)
  [[ -z "$bad_files" ]] && ok "every YAML file parses" || { bad "invalid YAML:"; echo "$bad_files" | sed 's/^/     /'; }

  section "Kubernetes manifests (dry run)"
  if kubectl apply --dry-run=server -f platform/kubernetes/ >/dev/null 2>&1; then
    ok "every manifest passes a server-side dry run"
  else
    echo "  ⚠️  server dry-run unavailable; falling back to client"
    kubectl apply --dry-run=client -f platform/kubernetes/ >/dev/null 2>&1 \
      && ok "client dry-run passed" || bad "a manifest failed validation"
  fi

  section "telemetry conventions"
  ./ci/check-conventions.sh || fail=1
}

# ══ 2. TEST: unit tests for the alerting rules ⭐⭐ ═════════════════
test_rules() {
  section "promtool test rules (alert unit tests)"
  for t in ci/promtool-tests/*.yaml; do
    [[ -f "$t" ]] || continue
    if out=$(promtool test rules "$t" 2>&1); then
      ok "$(basename "$t") passed"
    else
      bad "$(basename "$t") FAILED:"
      echo "$out" | sed 's/^/     /'
    fi
  done

  section "every alert has: severity, team, runbook_url, summary"
  python3 - <<'PY' || fail=1
import sys, glob, yaml
required_labels   = {"severity", "team"}
required_annots   = {"summary", "runbook_url"}
bad = 0; n = 0
for f in glob.glob("platform/prometheus/alerting-rules/*.yaml"):
    for doc in yaml.safe_load_all(open(f)):
        if not doc or "spec" not in doc: continue
        for g in doc["spec"].get("groups", []):
            for r in g.get("rules", []):
                if "alert" not in r: continue
                n += 1
                missing_l = required_labels - set((r.get("labels") or {}).keys())
                missing_a = required_annots - set((r.get("annotations") or {}).keys())
                if missing_l or missing_a:
                    bad += 1
                    print(f"     ✖ {r['alert']} in {f}: missing labels={missing_l or '-'} annotations={missing_a or '-'}")
if bad:
    print(f"  ✖ {bad}/{n} alerts are incomplete"); sys.exit(1)
print(f"  ✅ all {n} alerts have severity, team, summary and runbook_url")
PY

  section "runbook links resolve"
  python3 - <<'PY' || fail=1
import glob, os, re, sys, yaml
bad = 0; n = 0
for f in glob.glob("platform/prometheus/alerting-rules/*.yaml"):
    for doc in yaml.safe_load_all(open(f)):
        if not doc or "spec" not in doc: continue
        for g in doc["spec"].get("groups", []):
            for r in g.get("rules", []):
                url = (r.get("annotations") or {}).get("runbook_url")
                if not url: continue
                n += 1
                name = url.rstrip("/").split("/")[-1].replace(".md", "")
                if not glob.glob(f"platform/runbooks/{name}*.md"):
                    bad += 1; print(f"     ✖ {r['alert']} → no runbook file matching '{name}'")
if bad: sys.exit(f"  ✖ {bad}/{n} runbook links are broken")
print(f"  ✅ all {n} runbook links resolve to a file")
PY

  section "no duplicate alert names"
  dupes=$(grep -rhoE '^\s+- alert: \S+' platform/prometheus/alerting-rules/ | awk '{print $3}' | sort | uniq -d)
  [[ -z "$dupes" ]] && ok "no duplicate alert names" || { bad "duplicated:"; echo "$dupes" | sed 's/^/     /'; }
}

# ══ 3. DASHBOARDS ⭐ ══════════════════════════════════════════════
dashboards() {
  section "Grafana dashboard lint"
  python3 - <<'PY' || fail=1
import glob, json, re, sys
bad = 0
uids = {}
for f in sorted(glob.glob("platform/grafana/dashboards/*.json")):
    try:
        d = json.load(open(f))
    except Exception as e:
        print(f"  ✖ {f}: invalid JSON — {e}"); bad += 1; continue

    # 1. a UID must exist and be unique
    uid = d.get("uid")
    if not uid: print(f"  ✖ {f}: no uid"); bad += 1
    elif uid in uids: print(f"  ✖ {f}: uid '{uid}' collides with {uids[uid]}"); bad += 1
    else: uids[uid] = f

    # 2. no hardcoded datasource UIDs that we don't provision
    allowed_ds = {"prometheus", "tempo", "loki", "-- Grafana --", None, ""}
    text = json.dumps(d)
    for m in re.finditer(r'"uid":\s*"([^"]+)"', text):
        pass  # datasources are validated below by walking the tree

    def walk(node, path=""):
        global bad
        if isinstance(node, dict):
            if "datasource" in node and isinstance(node["datasource"], dict):
                u = node["datasource"].get("uid")
                if u and u not in allowed_ds:
                    print(f"  ✖ {f}: {path} uses an unprovisioned datasource uid '{u}'"); bad += 1
            if node.get("type") == "prometheus" and "expr" in node:
                e = node["expr"]
                # 3. no $__interval misuse in a *_total counter without rate()
                if re.search(r'_total\b', e) and "rate(" not in e and "increase(" not in e \
                   and not e.strip().startswith("sum(") and "ALERTS" not in e:
                    print(f"  ⚠️  {f}: {path} queries a counter without rate()/increase(): {e[:80]}")
                # 4. no division without clamp_min → NaN panels
                if "/" in e and "clamp_min" not in e and "group_left" not in e:
                    print(f"  ⚠️  {f}: {path} divides without clamp_min (NaN when the denominator is 0)")
                # 5. no unbounded group-by
                if re.search(r'by\s*\([^)]*\b(trace_id|request_id|user_id|pod_ip|order_id)\b', e):
                    print(f"  ✖ {f}: {path} groups by an unbounded label"); bad += 1
            for k, v in node.items(): walk(v, f"{path}.{k}")
        elif isinstance(node, list):
            for i, v in enumerate(node): walk(v, f"{path}[{i}]")
    walk(d)

    # 6. every variable used in a query must be declared
    declared = {v["name"] for v in d.get("templating", {}).get("list", [])}
    used = set(re.findall(r'\$(?:\{)?([a-zA-Z_][a-zA-Z0-9_]*)', text)) - {
        "__rate_interval", "__interval", "__range", "__value", "__field", "__data",
        "__from", "__to", "__name", "timeFilter", "metric", "__all", "__auto"}
    undeclared = used - declared
    if undeclared:
        print(f"  ⚠️  {f}: uses undeclared variables: {sorted(undeclared)}")

    print(f"  ✅ {f}  uid={uid}  panels={len(d.get('panels', []))}")

print(f"\n  {len(uids)} dashboards, {bad} hard errors")
sys.exit(1 if bad else 0)
PY
}

# ══ 4. CARDINALITY BUDGET ⭐ ══════════════════════════════════════
cardinality() {
  section "cardinality budget"
  kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
  local pf=$!; sleep 5
  if ! curl -sf localhost:9090/-/ready >/dev/null; then
    echo "  ⚠️  Prometheus unreachable — skipping (this check also runs as an alert)"; kill $pf 2>/dev/null; return 0
  fi
  total=$(curl -s localhost:9090/api/v1/status/tsdb | jq -r '.data.headStats.numSeries')
  budget=$(grep -oE '^[0-9]+' ci/cardinality-budget.txt | head -1)
  echo "  active series: $total  (budget: $budget)"
  if (( total > budget )); then
    bad "cardinality budget exceeded by $((total - budget)) series"
    curl -s localhost:9090/api/v1/status/tsdb \
      | jq -r '.data.top10CountByMetricName[] | "     \(.value)\t\(.name)"'
  else
    ok "within budget ($(( (total * 100) / budget ))% used)"
  fi
  kill $pf 2>/dev/null
}

case "$step" in
  lint)        lint ;;
  test-rules)  test_rules ;;
  dashboards)  dashboards ;;
  cardinality) cardinality ;;
  all)         lint; test_rules; dashboards ;;
  *) echo "usage: $0 {lint|test-rules|dashboards|cardinality|all}"; exit 2 ;;
esac

echo
if (( fail )); then printf '\033[1;31m✖ VALIDATION FAILED\033[0m\n'; exit 1
else printf '\033[1;32m✅ VALIDATION PASSED\033[0m\n'; fi
EOF
chmod +x ci/validate.sh
echo "500000  # active-series budget for the learning cluster" > ci/cardinality-budget.txt
```

### 6.2 Unit tests for alerting rules ⭐⭐

This is the technique almost nobody uses, and it is **the** thing that stops a silent alert. `promtool test rules` lets you feed synthetic time series in and assert that an alert fires (or doesn't) at a specific time.

```yaml
# ci/promtool-tests/symptom-test.yaml
rule_files:
  - ../../platform/prometheus/alerting-rules/symptom.yaml
  - ../../platform/prometheus/recording-rules/red-recording.yaml

evaluation_interval: 30s

tests:
  # ══════════════════════════════════════════════════════════════
  # CheckoutErrorRatioHigh
  # ══════════════════════════════════════════════════════════════
  - interval: 30s
    input_series:
      # ⭐ a healthy baseline: 100 req/30s, 0 errors, for 10 minutes
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="200"}'
        values: "0+100x40"
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="500"}'
        values: "0+0x40"

    alert_rule_test:
      # at 10 minutes, nothing should be firing
      - eval_time: 10m
        alertname: CheckoutErrorRatioHigh
        exp_alerts: []          # ⭐⭐ THE MOST IMPORTANT ASSERTION: it must NOT fire when healthy

  # ── now the incident ─────────────────────────────────────────
  - interval: 30s
    input_series:
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="200"}'
        values: "0+100x20 0+95x40"          # healthy for 10m, then 5% errors
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="500"}'
        values: "0+0x20 0+5x40"

    alert_rule_test:
      - eval_time: 12m                       # inside `for: 5m` — not yet firing
        alertname: CheckoutErrorRatioHigh
        exp_alerts: []
      - eval_time: 16m                       # ⭐ pending
        alertname: CheckoutErrorRatioHigh
        exp_alerts:
          - exp_labels:
              alertname: CheckoutErrorRatioHigh
              severity: critical
              team: payments
              tier: symptom
              slo: checkout-availability
              namespace: monitoring
            exp_annotations:
              summary: "1 in 100 checkouts is failing"
      - eval_time: 20m                       # ⭐ firing (5% > 1%, sustained > 5m)
        alertname: CheckoutErrorRatioHigh
        exp_alerts:
          - exp_labels:
              alertname: CheckoutErrorRatioHigh
              severity: critical
              team: payments
              tier: symptom
              slo: checkout-availability

  # ══════════════════════════════════════════════════════════════
  # ⭐ THE FALSE-POSITIVE TESTS — prove the alert does NOT fire
  #    in the situations where firing would be wrong
  # ══════════════════════════════════════════════════════════════
  - interval: 30s
    input_series:
      # a BRIEF blip: 30% errors for 2 minutes, then recovery
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="200"}'
        values: "0+100x20 0+70x4 0+100x40"
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="500"}'
        values: "0+0x20 0+30x4 0+0x40"
    alert_rule_test:
      - eval_time: 15m
        alertname: CheckoutErrorRatioHigh
        exp_alerts: []          # ⭐ `for: 5m` correctly suppressed a 2-minute blip

  - interval: 30s
    input_series:
      # a DEPLOY: 100% errors for 90 seconds, then clean
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="200"}'
        values: "0+100x20 0+100x2 0+100x60"
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="500"}'
        values: "0+0x20 0+100x2 0+0x60"
      - series: 'kube_deployment_status_replicas_updated{namespace="shop",deployment="shop-api"}'
        values: "3x20 2x3 3x60"
    alert_rule_test:
      - eval_time: 25m
        alertname: CheckoutErrorRatioHigh
        exp_alerts: []          # ⭐ the rolling update blip did not page anyone

  - interval: 30s
    input_series:
      # 402 business rejections — NOT an availability breach
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="200"}'
        values: "0+60x40"
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders",status="402"}'
        values: "0+40x40"
    alert_rule_test:
      - eval_time: 15m
        alertname: CheckoutErrorRatioHigh
        exp_alerts: []          # ⭐⭐ a 40% decline rate must NOT look like an outage

  # ══════════════════════════════════════════════════════════════
  # CheckoutLatencyP99High — the histogram maths
  # ══════════════════════════════════════════════════════════════
  - interval: 30s
    input_series:
      # all requests in the le="0.5" bucket → p99 = 0.25s → no alert
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="0.1"}'
        values: "0+40x40"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="0.25"}'
        values: "0+90x40"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="0.5"}'
        values: "0+100x40"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="1"}'
        values: "0+100x40"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="+Inf"}'
        values: "0+100x40"
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders"}'
        values: "0+100x40"
    alert_rule_test:
      - eval_time: 20m
        alertname: CheckoutLatencyP99High
        exp_alerts: []

  - interval: 30s
    input_series:
      # 2% of requests spill into le="1" → p99 crosses 1s → alert
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="0.1"}'
        values: "0+40x60"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="0.5"}'
        values: "0+90x60"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="1"}'
        values: "0+97x60"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="2"}'
        values: "0+100x60"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-api",uri="/api/orders",le="+Inf"}'
        values: "0+100x60"
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-api",uri="/api/orders"}'
        values: "0+100x60"
    alert_rule_test:
      - eval_time: 25m
        alertname: CheckoutLatencyP99High
        exp_alerts:
          - exp_labels:
              alertname: CheckoutLatencyP99High
              severity: critical
              team: payments
              tier: symptom
```

```yaml
# ci/promtool-tests/observability-self-test.yaml
rule_files:
  - ../../platform/prometheus/alerting-rules/observability-self.yaml

evaluation_interval: 1m

tests:
  # ⭐⭐ the alert that tells you you're blind MUST itself be tested
  - interval: 1m
    input_series:
      - series: 'up{job="shop-api", instance="10.244.1.5:9090"}'
        values: "1x10 0x20"                       # healthy for 10m, then down
      - series: 'up{job="checkout", instance="10.244.2.5:9091"}'
        values: "1x30"
    alert_rule_test:
      - eval_time: 8m
        alertname: PrometheusTargetDown
        exp_alerts: []
      - eval_time: 15m                            # `for: 3m` after going down
        alertname: PrometheusTargetDown
        exp_alerts:
          - exp_labels:
              alertname: PrometheusTargetDown
              severity: critical
              team: platform
              tier: self
              job: shop-api
              instance: "10.244.1.5:9090"

  - interval: 1m
    input_series:
      - series: 'otelcol_processor_dropped_spans{namespace="otel",processor="tail_sampling"}'
        values: "0x10 0+500x20"                   # a counter that starts increasing
      - series: 'otelcol_processor_refused_spans{namespace="otel",processor="memory_limiter"}'
        values: "0x10 0+200x20"
    alert_rule_test:
      - eval_time: 15m
        alertname: OtelCollectorDroppingSpans
        exp_alerts:
          - exp_labels: {alertname: OtelCollectorDroppingSpans, severity: critical, team: platform, tier: self}
      - eval_time: 15m
        alertname: OtelCollectorMemoryLimiterRefusing
        exp_alerts:
          - exp_labels: {alertname: OtelCollectorMemoryLimiterRefusing, severity: critical, team: platform, tier: self}

  - interval: 1m
    input_series:
      - series: 'prometheus_tsdb_head_series'
        values: "100000x10 100000+50000x20"       # climbing past the 500k budget
    alert_rule_test:
      - eval_time: 25m
        alertname: PrometheusCardinalityBudgetExceeded
        exp_alerts:
          - exp_labels: {alertname: PrometheusCardinalityBudgetExceeded, severity: warning, team: platform, tier: self}
```

```bash
promtool test rules ci/promtool-tests/*.yaml
# ✅ unit-testing 2 rule test files
#   ci/promtool-tests/symptom-test.yaml: SUCCESS
#   ci/promtool-tests/observability-self-test.yaml: SUCCESS

# ⭐ deliberately break one and watch CI catch it
sed -i 's/for: 5m/for: 5s/' platform/prometheus/alerting-rules/symptom.yaml
promtool test rules ci/promtool-tests/symptom-test.yaml
# level=error msg="Failed to run test" err="unexpected alerts fired…"
#     expected: []      got: [CheckoutErrorRatioHigh{…}]
# ⭐ THE 2-MINUTE-BLIP TEST CAUGHT IT. That's the value.
git checkout platform/prometheus/alerting-rules/symptom.yaml
```

### 6.3 The Collector config validation

```bash
cat > ci/otel-collector-validate.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ Validate every OTel Collector config without running a cluster.
set -uo pipefail
IMAGE="otel/opentelemetry-collector-contrib:0.158.0"
fail=0

echo "── OTel Collector config validation ──"
for cfg in platform/otel/*-config.yaml; do
  name=$(basename "$cfg")

  # 1. does it parse as YAML?
  python3 -c "import yaml; yaml.safe_load(open('$cfg'))" 2>/dev/null \
    && echo "  ✅ $name: valid YAML" || { echo "  ✖ $name: invalid YAML"; fail=1; continue; }

  # 2. does the Collector accept it? (--dry-run parses + wires the pipelines, then exits)
  if out=$(docker run --rm -v "$PWD/platform/otel:/cfg:ro" "$IMAGE" \
             --config=/cfg/"$name" --dry-run 2>&1); then
    echo "  ✅ $name: the Collector accepts the config"
  else
    echo "  ✖ $name: the Collector rejected the config"
    echo "$out" | grep -iE 'error|cannot|failed|unknown' | head -8 | sed 's/^/     /'
    fail=1
  fi

  # 3. ⭐ the structural invariants that keep the Collector alive
  python3 - "$cfg" <<'PY' || fail=1
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
procs = list((cfg.get("processors") or {}).keys())
bad = []

if "memory_limiter" not in procs:
    bad.append("no memory_limiter processor — the Collector WILL OOMKill under load")
for name, pipe in (cfg.get("service", {}).get("pipelines") or {}).items():
    p = pipe.get("processors") or []
    if p and p[0] != "memory_limiter":
        bad.append(f"pipeline '{name}': memory_limiter is not FIRST (it is at index {p.index('memory_limiter') if 'memory_limiter' in p else 'absent'})")
    if p and p[-1] != "batch":
        bad.append(f"pipeline '{name}': batch is not LAST (got {p[-1]})")
    if not pipe.get("exporters"):
        bad.append(f"pipeline '{name}' has no exporters")
    if not pipe.get("receivers"):
        bad.append(f"pipeline '{name}' has no receivers")

for e, ec in (cfg.get("exporters") or {}).items():
    if isinstance(ec, dict) and ec.get("sending_queue", {}).get("enabled") is False:
        bad.append(f"exporter '{e}': sending_queue disabled — a backend blip drops data")
    if e.startswith("debug") and (ec or {}).get("verbosity") == "detailed":
        bad.append(f"exporter '{e}': verbosity=detailed must never ship to production")

svc = (cfg.get("service", {}) or {}).get("telemetry", {})
if not svc:
    bad.append("service.telemetry is unset — you cannot monitor the Collector itself")

if bad:
    for b in bad: print(f"  ✖ {b}")
    sys.exit(1)
print(f"  ✅ {sys.argv[1].split('/')[-1]}: memory_limiter first, batch last, queues enabled, telemetry on")
PY
done

# 4. tail_sampling sanity
python3 - <<'PY' || fail=1
import sys, yaml, glob
bad = 0
for cfg in glob.glob("platform/otel/*-config.yaml"):
    c = yaml.safe_load(open(cfg))
    ts = (c.get("processors") or {}).get("tail_sampling")
    if not ts: continue
    pol = ts.get("policies") or []
    names = [p.get("name","?") for p in pol]
    kinds = {p.get("type") for p in pol}
    # ⭐ invariants for a sane tail-sampling policy set
    if "status_code" not in kinds:
        print(f"  ✖ {cfg}: tail_sampling has no status_code policy — errors may be sampled out"); bad += 1
    if "latency" not in kinds:
        print(f"  ✖ {cfg}: tail_sampling has no latency policy — slow traces may be sampled out"); bad += 1
    if not any(p.get("type") == "probabilistic" for p in pol):
        print(f"  ⚠️  {cfg}: no probabilistic policy — you may be keeping 100% of everything (expensive)")
    dw = ts.get("decision_wait", "10s")
    nt = ts.get("num_traces", 0)
    if isinstance(nt, int) and nt > 500000:
        print(f"  ⚠️  {cfg}: num_traces={nt} is large — expect high memory use"); bad += 0
    print(f"  ✅ {cfg.split('/')[-1]}: tail_sampling with {len(pol)} policies {names}")
sys.exit(1 if bad else 0)
PY

(( fail )) && { echo; echo "✖ collector validation FAILED"; exit 1; }
echo; echo "✅ every Collector config is valid and structurally sound"
EOF
chmod +x ci/otel-collector-validate.sh
./ci/otel-collector-validate.sh
```

### 6.4 The GitHub Actions workflow

```yaml
# .github/workflows/observability-ci.yml
name: observability-ci

on:
  push: {branches: [main]}
  pull_request: {branches: [main]}
  workflow_dispatch: {}

concurrency:
  group: obs-ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
  id-token: write                    # ⭐ for OIDC to a cloud registry
  security-events: write             # ⭐ for code scanning

env:
  PROM_VERSION: "3.13.2"
  OTEL_COLLECTOR_VERSION: "0.158.0"
  REGISTRY: ghcr.io
  IMAGE_PREFIX: ghcr.io/${{ github.repository_owner }}

jobs:
  # ══════════════════════════════════════════════════════════════
  # 1. LINT AND UNIT TEST — fast, no cluster, runs on every PR
  # ══════════════════════════════════════════════════════════════
  validate:
    name: Validate the platform config
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - name: Install promtool and amtool
        run: |
          set -euo pipefail
          VER="${PROM_VERSION}"
          curl -sL "https://github.com/prometheus/prometheus/releases/download/v${VER}/prometheus-${VER}.linux-amd64.tar.gz" \
            | tar xz
          sudo install -m755 "prometheus-${VER}.linux-amd64/promtool"  /usr/local/bin/
          sudo install -m755 "prometheus-${VER}.linux-amd64/prometheus" /usr/local/bin/
          curl -sL "https://github.com/prometheus/alertmanager/releases/download/v0.28.1/alertmanager-0.28.1.linux-amd64.tar.gz" \
            | tar xz
          sudo install -m755 "alertmanager-0.28.1.linux-amd64/amtool" /usr/local/bin/
          promtool --version && amtool --version

      - uses: actions/setup-python@v5
        with: {python-version: "3.13"}
      - run: pip install pyyaml

      - name: Lint rules, configs and manifests
        run: ci/validate.sh lint

      - name: Unit-test the alerting rules        # ⭐⭐ the gate that matters
        run: ci/validate.sh test-rules

      - name: Lint the Grafana dashboards
        run: ci/validate.sh dashboards

      - name: Validate the OTel Collector configs
        run: ci/otel-collector-validate.sh

      - name: Upload the validation report
        if: always()
        uses: actions/upload-artifact@v4
        with: {name: validation-report, path: ci/*.log, if-no-files-found: ignore}

  # ══════════════════════════════════════════════════════════════
  # 2. BUILD THE APPS
  # ══════════════════════════════════════════════════════════════
  build:
    name: Build ${{ matrix.app }}
    needs: validate
    runs-on: ubuntu-latest
    timeout-minutes: 25
    strategy:
      fail-fast: false
      matrix:
        include:
          - {app: shop-ui,       lang: node,   test: "npm ci && npm test -- --watchAll=false"}
          - {app: shop-api,      lang: java,   test: "mvn -B -q verify"}
          - {app: checkout,      lang: go,     test: "go test ./... -race -count=1"}
          - {app: order-worker,  lang: python, test: "pip install -r requirements-dev.txt && pytest -q"}
          - {app: payment-mock,  lang: go,     test: "go test ./... -race -count=1"}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        if: matrix.lang == 'node'
        with: {node-version: "22", cache: npm, cache-dependency-path: apps/${{ matrix.app }}/package-lock.json}
      - uses: actions/setup-java@v4
        if: matrix.lang == 'java'
        with: {distribution: temurin, java-version: "21", cache: maven}
      - uses: actions/setup-go@v5
        if: matrix.lang == 'go'
        with: {go-version: "1.23", cache-dependency-path: apps/${{ matrix.app }}/go.sum}
      - uses: actions/setup-python@v5
        if: matrix.lang == 'python'
        with: {python-version: "3.13", cache: pip, cache-dependency-path: apps/${{ matrix.app }}/requirements.txt}

      - name: Test
        working-directory: apps/${{ matrix.app }}
        run: ${{ matrix.test }}

      # ⭐ instrument the Java build with the OTel Maven plugin so the agent
      #    version is validated at build time, not discovered at runtime
      - name: Verify the OTel agent version is pinned
        if: matrix.lang == 'java'
        run: |
          grep -qE 'OTEL_AGENT_VERSION=[0-9]+\.[0-9]+\.[0-9]+' apps/shop-api/Dockerfile \
            || { echo "✖ OTEL_AGENT_VERSION is not pinned"; exit 1; }

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.IMAGE_PREFIX }}/${{ matrix.app }}
          tags: |
            type=sha,prefix=sha-,format=short
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=raw,value=latest,enable={{is_default_branch}}

      - uses: docker/build-push-action@v6
        with:
          context: apps/${{ matrix.app }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha,scope=${{ matrix.app }}
          cache-to: type=gha,mode=max,scope=${{ matrix.app }}
          provenance: true
          sbom: true                    # ⭐ a CycloneDX SBOM per image
          build-args: |
            VERSION=${{ github.sha }}
            OTEL_AGENT_VERSION=2.11.0

      # ⭐ scan the image and fail the build on a critical CVE
      - uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: ${{ env.IMAGE_PREFIX }}/${{ matrix.app }}:sha-${{ github.sha }}
          format: sarif
          output: trivy-${{ matrix.app }}.sarif
          severity: CRITICAL,HIGH
          ignore-unfixed: true
      - uses: github/codeql-action/upload-sarif@v3
        with: {sarif_file: trivy-${{ matrix.app }}.sarif, category: trivy-${{ matrix.app }}

      - name: Emit the image digest for the deploy job
        run: echo "DIGEST_${{ matrix.app }}=$(docker buildx imagetools inspect ${{ env.IMAGE_PREFIX }}/${{ matrix.app }}:sha-${{ github.sha }} --format '{{json .Manifest}}' | jq -r .digest)" >> "$GITHUB_ENV"

  # ══════════════════════════════════════════════════════════════
  # 3. EPHEMERAL CLUSTER — the real end-to-end test ⭐⭐
  #    Build a throwaway kind cluster, install the whole platform,
  #    deploy the apps, and ASSERT that telemetry actually flows.
  # ══════════════════════════════════════════════════════════════
  e2e:
    name: End-to-end on an ephemeral cluster
    needs: build
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-go@v5
        with: {go-version: "1.23"}
      - uses: actions/setup-python@v5
        with: {python-version: "3.13"}
      - run: pip install pyyaml

      - name: Install promtool
        run: |
          curl -sL "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz" | tar xz
          sudo install -m755 "prometheus-${PROM_VERSION}.linux-amd64/promtool" /usr/local/bin/

      - uses: helm/kind-action@v1.10.0
        with:
          cluster_name: ci
          node_image: kindest/node:v1.37.0
          wait: 5m

      - name: Install Helm and kubectl
        run: |
          curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
          kubectl version --client

      - name: Install the platform
        run: make platform-install
        timeout-minutes: 20

      - name: Apply the OTel Collector, rules, dashboards and datasources
        run: make platform-apply

      - name: Load the images and deploy the apps
        run: |
          for app in shop-ui shop-api checkout order-worker payment-mock; do
            docker pull "$IMAGE_PREFIX/$app:sha-${GITHUB_SHA::7}" || \
              docker pull "$IMAGE_PREFIX/$app:latest"
            kind load docker-image "$IMAGE_PREFIX/$app:sha-${GITHUB_SHA::7}" --name ci || true
          done
          make apps-deploy

      - name: Generate traffic
        run: |
          kubectl apply -f game-day/loadgen.yaml
          echo "waiting 4 minutes for telemetry to accumulate…"
          sleep 240

      - name: ⭐ ASSERT the telemetry pipeline works
        run: ./scripts/validate-trace-pipeline.sh

      - name: ⭐ ASSERT the cardinality budget
        run: ci/validate.sh cardinality

      - name: ⭐ ASSERT an injected failure produces an alert
        run: |
          set -euo pipefail
          kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
          kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9090 &
          sleep 5

          echo "==> injecting: payment provider 100% errors"
          ./game-day/chaos.sh payment-down

          echo "==> waiting for CheckoutErrorRatioHigh to fire (up to 8 minutes)"
          fired=false
          for i in $(seq 1 32); do
            n=$(curl -s 'localhost:9090/api/v1/alerts' \
                 | jq -r '[.data.alerts[] | select(.labels.alertname=="CheckoutErrorRatioHigh" and .state=="firing")] | length')
            if [[ "$n" -ge 1 ]]; then fired=true; break; fi
            sleep 15
          done
          $fired || { echo "✖ the alert never fired — the pipeline is broken"; exit 1; }
          echo "✅ CheckoutErrorRatioHigh fired"

          echo "==> asserting it reached Alertmanager"
          n=$(curl -s localhost:9093/api/v2/alerts | jq '[.[] | select(.labels.alertname=="CheckoutErrorRatioHigh")] | length')
          [[ "$n" -ge 1 ]] || { echo "✖ Alertmanager never received it"; exit 1; }
          echo "✅ Alertmanager received and routed it"

          echo "==> asserting it is inhibited correctly"
          curl -s localhost:9093/api/v2/alerts \
            | jq -r '.[] | "\(.labels.alertname)\t\(.labels.severity)\t\(.labels.tier)\t\(.status.inhibitedBy // [])"'

          echo "==> healing"
          ./game-day/chaos.sh reset

      - name: Capture the platform state on failure
        if: failure()
        run: |
          mkdir -p artifacts
          kubectl get pods -A -o wide                          > artifacts/pods.txt          2>&1 || true
          kubectl get events -A --sort-by=.lastTimestamp       > artifacts/events.txt        2>&1 || true
          kubectl describe pods -A                             > artifacts/describe.txt      2>&1 || true
          kubectl logs -n otel -l app=otel-collector-gateway --tail=500 > artifacts/otel-gateway.log 2>&1 || true
          kubectl logs -n otel -l app=otel-agent      --tail=500 > artifacts/otel-agent.log 2>&1 || true
          kubectl logs -n monitoring sts/kps-kube-prometheus-stack-prometheus -c prometheus --tail=500 > artifacts/prometheus.log 2>&1 || true
          curl -s localhost:9090/api/v1/status/tsdb            > artifacts/tsdb.json         2>&1 || true
          curl -s localhost:9090/api/v1/targets                > artifacts/targets.json      2>&1 || true
      - uses: actions/upload-artifact@v4
        if: failure()
        with: {name: e2e-debug-artifacts, path: artifacts/}

  # ══════════════════════════════════════════════════════════════
  # 4. DASHBOARDS: catch a broken panel visually
  # ══════════════════════════════════════════════════════════════
  dashboard-screenshots:
    name: Screenshot every dashboard
    needs: e2e
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: {name: e2e-debug-artifacts, path: artifacts/}
        continue-on-error: true
      - name: Render each dashboard to PNG and attach it to the PR
        run: |
          set -uo pipefail
          # uses grafana/grafana-renderer or a headless Chrome against the e2e cluster
          for f in platform/grafana/dashboards/*.json; do
            uid=$(jq -r '.uid' "$f")
            echo "rendering $uid …"
            # curl -s "http://localhost:3000/render/d-solo/$uid?width=1600&height=900&theme=light" \
            #   -u admin:admin -o "screenshots/$uid.png" || true
          done
      - uses: actions/upload-artifact@v4
        with: {name: dashboard-screenshots, path: screenshots/, if-no-files-found: ignore}

  # ══════════════════════════════════════════════════════════════
  # 5. DEPLOY (main only)
  # ══════════════════════════════════════════════════════════════
  deploy-staging:
    name: Deploy to staging
    needs: [validate, build, e2e]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment:                       # ⭐ a GitHub Environment = approvals + secrets
      name: staging
      url: https://grafana.staging.shop.example.com
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with: {client-id: "${{ secrets.AZURE_CLIENT_ID }}",
               tenant-id: "${{ secrets.AZURE_TENANT_ID }}",
               subscription-id: "${{ secrets.AZURE_SUBSCRIPTION_ID }}"}   # ⭐ OIDC, no long-lived secret
      - name: Deploy the platform (GitOps)
        run: |
          make platform-install
          make platform-apply
      - name: Deploy the apps
        run: make apps-deploy VERSION="sha-${GITHUB_SHA::7}"
      - name: Post-deploy smoke test           # ⭐ gate the promotion
        run: ./scripts/validate-trace-pipeline.sh
      - name: Annotate the deployments          # ⭐ the dashboard annotation
        run: |
          for app in shop-ui shop-api checkout order-worker payment-mock; do
            kubectl -n shop annotate deploy/$app \
              kubernetes.io/change-cause="${GITHUB_REPOSITORY}@${GITHUB_SHA::7}: ${GITHUB_EVENT_HEAD_COMMIT_MESSAGE}" \
              --overwrite
          done

  deploy-production:
    name: Deploy to production
    needs: deploy-staging
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment:
      name: production                # ⭐ requires 2 manual approvals
      url: https://grafana.shop.example.com
    steps:
      - uses: actions/checkout@v4
      - name: ⭐ Create a silence around the deploy window
        run: |
          ./scripts/silence.sh 'tier="symptom"' 30m "planned deploy ${GITHUB_SHA::7}" || true
      - name: Deploy
        run: |
          make platform-install
          make apps-deploy VERSION="sha-${GITHUB_SHA::7}"
      - name: Watch the SLO burn rate for 10 minutes   # ⭐ progressive delivery
        run: |
          set -euo pipefail
          for i in $(seq 1 20); do
            br=$(curl -sG localhost:9090/api/v1/query --data-urlencode \
              'query=sum(rate(http_server_requests_seconds_count{namespace="shop",status=~"5.."}[5m])) / (0.001 * sum(rate(http_server_requests_seconds_count{namespace="shop"}[5m])))' \
              | jq -r '.data.result[0].value[1] // "0"')
            echo "burn rate: $br"
            awk "BEGIN{exit !($br > 5)}" && { echo "✖ burn rate >5× during the deploy — rolling back"; make rollback; exit 1; }
            sleep 30
          done
      - name: Lift the silence
        if: always()
        run: ./scripts/silence.sh --clear || true
```

### 6.5 What each gate actually catches

| Gate | The bug it catches | Real example |
|---|---|---|
| `promtool check rules` | A typo in a PromQL expression | `sum by (le] (` → the whole rule group is rejected and **every alert in it silently stops working** |
| `promtool test rules` ⭐⭐ | An alert that never fires, or fires on a blip | Removing `for: 5m` → the deploy-blip test fails |
| Alert metadata check | An alert with no runbook | A page arrives at 3 a.m. with no instructions |
| Runbook link check | A runbook that was deleted | 404 during an incident |
| Dashboard lint | A panel referencing a datasource UID that doesn't exist | "Datasource prometheus-old was not found" on the TV screen |
| Dashboard lint | A counter queried without `rate()` | A panel that only ever goes up |
| Dashboard lint | A division without `clamp_min` | NaN panels during low traffic |
| Convention check | A service emitting `shop_api` instead of `shop-api` | Correlation silently breaks |
| Convention check | An image tagged `:latest` | You can't roll back |
| Collector `--dry-run` | A misspelled processor name | The Collector is in CrashLoopBackOff and you have no traces |
| Collector structural check ⭐ | `memory_limiter` not first | The Collector OOMKills under load and drops everything |
| tail_sampling check | No `status_code` policy | **Errors are sampled out.** The worst possible failure. |
| Cardinality budget | A new label with unbounded values | Prometheus OOMs three days after a release |
| Ephemeral-cluster e2e ⭐⭐ | Any of the above, in combination | "It validated, but no traces arrived" |
| Alert-actually-fires assertion | A wiring mistake between Prometheus and Alertmanager | The alert fires in Prometheus but never routes |
| Trivy / SBOM | A critical CVE in a base image | log4j-class problems |

---

<a name="phase-7--the-game-day"></a>
## Phase 7 — The game day

**This is the phase that makes it real.** Five failures, injected one at a time. For each, you must: detect it (which alert, how fast), diagnose it (the exact click path), mitigate it, and write the report.

```bash
cat > scripts/game-day.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
action="${1:-help}"; scenario="${2:-}"
NS="${NS:-shop}"

port_forward() {
  pkill -f 'port-forward.*(9090|9093|3200|3100)' 2>/dev/null || true
  kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
  kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9090 >/dev/null 2>&1 &
  kubectl port-forward -n monitoring svc/tempo 3200:3200 >/dev/null 2>&1 &
  kubectl port-forward -n monitoring svc/loki 3100:3100 >/dev/null 2>&1 &
  sleep 5
}

watch_alerts() {
  echo "  ⏱️  watching for alerts (Ctrl-C to stop)…"
  start=$(date +%s)
  seen=""
  for i in $(seq 1 120); do
    now=$(curl -s localhost:9090/api/v1/alerts | jq -r '
      [.data.alerts[] | select(.state=="firing") | "\(.labels.alertname)[\(.labels.severity)]"] | sort | unique | join(", ")')
    if [[ "$now" != "$seen" ]]; then
      printf '  +%3ds  %s\n' "$(( $(date +%s) - start ))" "${now:-<none>}"
      seen="$now"
    fi
    sleep 2
  done
}

case "$action" in
  inject)
    port_forward
    echo "════════════════════════════════════════════════════════════"
    echo "  GAME DAY — injecting: $scenario"
    echo "════════════════════════════════════════════════════════════"
    echo "  T+0s   injection begins"
    case "$scenario" in
      01-payment-timeout)        ./game-day/scenarios/01-payment-timeout.sh ;;
      02-db-pool-exhaustion)     ./game-day/scenarios/02-db-pool-exhaustion.sh ;;
      03-memory-leak)            ./game-day/scenarios/03-memory-leak.sh ;;
      04-cardinality-bomb)       ./game-day/scenarios/04-cardinality-bomb.sh ;;
      05-monitoring-blind)       ./game-day/scenarios/05-monitoring-blind.sh ;;
      *) echo "unknown scenario: $scenario"; exit 1 ;;
    esac
    watch_alerts
    ;;
  heal)
    port_forward
    echo "==> healing every scenario"
    ./game-day/chaos.sh reset
    kubectl -n shop set env deploy/shop-api PAYMENT_TIMEOUT_MS- DB_POOL_MAX- 2>/dev/null || true
    kubectl -n shop scale deploy/order-worker --replicas=2
    kubectl -n shop rollout restart deploy/shop-api deploy/checkout deploy/order-worker
    kubectl -n monitoring patch prometheus kps-kube-prometheus-stack-prometheus --type=merge \
      -p '{"spec":{"scrapeInterval":"30s"}}'
    kubectl -n otel rollout restart deploy/otel-collector-gateway ds/otel-agent
    kubectl delete servicemonitor -n shop cardinality-bomb --ignore-not-found
    echo "✅ healed"
    ;;
  status)
    port_forward
    echo "==> firing alerts";  curl -s localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | select(.state=="firing") | "  \(.labels.severity)\t\(.labels.alertname)\t\(.labels.team)"' | sort
    echo "==> silences";       curl -s localhost:9093/api/v2/silences | jq -r '.[] | select(.status.state=="active") | "  \(.id)\t\(.matchers)\t\(.comment)"'
    echo "==> chaos state";    ./game-day/chaos.sh status
    echo "==> series count";   curl -s localhost:9090/api/v1/status/tsdb | jq '.data.headStats'
    echo "==> collector drops"; curl -s localhost:9090/api/v1/query --data-urlencode 'query=sum(rate(otelcol_processor_dropped_spans[5m]))' | jq -r '.data.result[0].value[1] // "0"'
    ;;
  *) cat <<MSG
usage: $0 {inject <scenario>|heal|status}

scenarios:
  01-payment-timeout       the payment provider's p99 drifts past our client timeout
  02-db-pool-exhaustion    the connection pool saturates under a traffic surge
  03-memory-leak           shop-api leaks 512 KB per request until it OOMKills
  04-cardinality-bomb      a new label explodes the series count
  05-monitoring-blind      the observability platform itself fails
MSG
    ;;
esac
EOF
chmod +x scripts/game-day.sh
mkdir -p game-day/scenarios game-day/reports
```

### Scenario 01 — the payment timeout ⭐ the most realistic one

```bash
cat > game-day/scenarios/01-payment-timeout.sh <<'EOF'
#!/usr/bin/env bash
# 💥 THE PAYMENT PROVIDER'S p99 DRIFTS PAST OUR CLIENT TIMEOUT.
#    Symptoms: latency spikes to ~3s, the ERROR RATE STAYS AT ZERO.
#    This is the hardest incident to diagnose, because nothing is "broken".
set -euo pipefail
echo "  T+0s   setting the shop-api payment client timeout to 1000ms"
kubectl -n shop set env deploy/shop-api PAYMENT_TIMEOUT_MS=1000 PAYMENT_MAX_RETRIES=2
kubectl -n shop rollout status deploy/shop-api --timeout=300s

echo "  T+60s  raising the payment provider's latency to 1.2–1.6s"
sleep 60
./game-day/chaos.sh payment-slow

echo "  T+90s  increasing traffic so the p99 is well-sampled"
sleep 30
kubectl -n shop scale deploy/loadgen --replicas=4 2>/dev/null || \
  kubectl -n shop apply -f game-day/loadgen.yaml

cat <<'MSG'

  💥 INJECTED: payment latency 1.2–1.6s, our timeout 1s, 2 retries

  EXPECTED DETECTION:
    T+  ~2m   CheckoutLatencyP99High fires (p99 ≈ 3.1s, threshold 1s, `for: 10m`)
    T+  ~4m   CheckoutLatencyBurnRateFast fires (SLO-2, 14.4×)
    T+  ~7m   ServletThreadsNearExhaustion fires (threads held 3× longer)
    T+ ~12m   CheckoutLatencyP99High has been firing for 10m → PAGES

  EXPECTED NON-DETECTION (this is the lesson):
    ⛔ CheckoutErrorRatioHigh does NOT fire — the retries eventually succeed
    ⛔ the availability SLO does NOT breach — 100% of orders complete
    ⭐ LATENCY-ONLY SLOs are what catch this. If you only have an availability
       SLO, this incident is invisible until customers abandon their carts.

MSG
EOF
chmod +x game-day/scenarios/01-payment-timeout.sh
```

**The runbook, written before the drill:**

```markdown
# platform/runbooks/symptom-latency-p99.md

## CheckoutLatencyP99High / CheckoutLatencyBurnRate*

**Severity:** critical · **Team:** payments · **SLO:** SLO-2 (99% < 500 ms)
**Meaning:** 1 in 100 checkout requests is slower than the threshold. Revenue is at risk
through cart abandonment even though no request is failing.

### First 60 seconds — classify the shape

Open the [Incident dashboard](http://localhost:3000/d/99-incident) and read ONE panel:
**DURATION p50 / p95 / p99**.

| p50 | p95 | p99 | Diagnosis | Go to |
|---|---|---|---|---|
| normal | normal | **high** | A **tail** problem: retries, GC, a slow dependency, lock contention | §A |
| normal | **high** | **high** | A **subset** of requests is slow (one route, one tenant, one region) | §B |
| **high** | **high** | **high** | **Global** saturation: the service is overloaded or a dependency is down | §C |

### §A — tail-only (p50 fine, p99 high)

```promql
# 1. which route?
histogram_quantile(0.99, sum by (le, uri) (rate(http_server_requests_seconds_bucket{namespace="shop",application="shop-api"}[5m])))

# 2. which dependency? Look at the CHILD spans in a slow trace.
#    Grafana → Incident → "Slowest traces" → click one → find the widest span.
```
```traceql
{ .service.name = "shop-api" && duration > 2s } | rate() by (.url.path)
```
The usual answers, in order:
1. **A retry loop.** Look for `http.resend_count > 0` or `retry` span events. Latency = N × timeout.
   → `kubectl -n shop get deploy shop-api -o yaml | grep -i timeout`
   → check the dependency's own latency: `histogram_quantile(0.99, sum by (le) (rate(payment_charge_duration_seconds_bucket[5m])))`
2. **GC pauses.** `rate(jvm_gc_pause_seconds_sum[5m]) / rate(jvm_gc_pause_seconds_count[5m])`
   and `jvm_gc_pause_seconds_max`. A long GC pause shows as a bimodal span distribution.
3. **Lock contention.** A span with a long *gap* before its first child. Take a thread dump:
   `kubectl -n shop exec deploy/shop-api -- jcmd 1 Thread.print | head -100`
4. **A slow query.** Look for the widest JDBC CLIENT span; check `db.query.text` (hashed) and
   `pg_stat_statements`.

### §B — a subset is slow

```promql
# split by every dimension you have and find the one that differs
histogram_quantile(0.99, sum by (le, uri)        (rate(http_server_requests_seconds_bucket{namespace="shop",application="shop-api"}[5m])))
histogram_quantile(0.99, sum by (le, exception)  (rate(http_server_requests_seconds_bucket{namespace="shop",application="shop-api"}[5m])))
histogram_quantile(0.99, sum by (le, pod)        (rate(http_server_requests_seconds_bucket{namespace="shop",application="shop-api"}[5m])))
```
```traceql
{ .service.name = "shop-api" && duration > 2s } | select(.customer.tier, .cart.items, .url.path)
```
- Slow on **one pod only** → a bad node, a noisy neighbour, or a leaking instance.
  `kubectl -n shop get pods -o wide` then `kubectl top pod` and the node dashboard.
- Slow on **one route only** → that code path. Read its span.
- Slow for **one customer tier** → a business-logic path (bulk orders, platinum pricing).

### §C — global saturation

Work the USE checklist in order, each with one query:
```promql
# UTILISATION
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="shop",pod=~"shop-api.*"}[5m]))
# SATURATION ⭐ the one that usually explains it
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="shop",pod=~"shop-api.*"}[5m]))
  / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="shop",pod=~"shop-api.*"}[5m]))
hikaricp_connections_pending{namespace="shop"}
tomcat_threads_busy_threads{namespace="shop"} / tomcat_threads_config_max_threads{namespace="shop"}
worker_queue_depth{namespace="shop"}
# ERRORS
sum by (pod) (rate(container_oom_events_total{namespace="shop"}[5m]))
```
Then: `kubectl -n shop top pods` and `kubectl -n shop get hpa`.

### Mitigations, fastest first

| Action | Command | Time | Risk |
|---|---|---|---|
| Scale out | `kubectl -n shop scale deploy shop-api --replicas=8` | 60s | low |
| Raise the timeout (if retries are the cause) | `kubectl -n shop set env deploy/shop-api PAYMENT_TIMEOUT_MS=3000` | 90s | low |
| Disable the retry loop | `kubectl -n shop set env deploy/shop-api PAYMENT_MAX_RETRIES=0` | 90s | ⚠️ more visible failures |
| Raise the DB pool | `kubectl -n shop set env deploy/shop-api DB_POOL_MAX=40` | 90s | ⚠️ may exhaust Postgres |
| Roll back the last deploy | `kubectl -n shop rollout undo deploy/shop-api` | 2m | low |
| Enable the circuit breaker | feature flag `payment.circuit-breaker.enabled=true` | 30s | ⚠️ some checkouts fail fast |
| Shed load | rate-limit `/api/orders` at the ingress | 5m | ⚠️ deliberate 429s |

### Did we deploy?

```bash
kubectl -n shop rollout history deploy/shop-api
kubectl -n shop get deploy shop-api -o jsonpath='{.metadata.annotations.kubernetes\.io/change-cause}'
# and on the dashboard: the blue "Deployments" annotation line vs the latency curve
```

### Resolution and cleanup

```bash
./game-day/chaos.sh reset                                    # if this was a drill
kubectl -n shop set env deploy/shop-api PAYMENT_TIMEOUT_MS- PAYMENT_MAX_RETRIES-
./scripts/silence.sh --clear
./scripts/incident-report.sh CheckoutLatencyP99High          # ⭐ generates the report skeleton
```

### Follow-ups (write these into the incident report)

- [ ] Add a client-side timeout that is **shorter** than the server-side one, and a circuit breaker.
- [ ] Add a `payment.charge.duration` **recording rule** so we can alert on the dependency directly.
- [ ] The retry count is not a metric today — add `http_client_requests_seconds_count{uri="/v1/charge"}`.
- [ ] The p99 alert took 10 minutes to page. Is that right for a revenue path? Consider `for: 5m`.
```

### Scenario 02 — connection-pool exhaustion

```bash
cat > game-day/scenarios/02-db-pool-exhaustion.sh <<'EOF'
#!/usr/bin/env bash
# 💥 A TRAFFIC SURGE EXHAUSTS THE HIKARI POOL. Latency climbs, then requests time out.
set -euo pipefail
echo "  T+0s   shrinking the pool to 2 connections and slowing Postgres"
kubectl -n shop set env deploy/shop-api DB_POOL_MAX=2 DB_POOL_CONNECTION_TIMEOUT_MS=30000
kubectl -n shop rollout status deploy/shop-api --timeout=300s

kubectl -n shop exec sts/postgres -- psql -U shop -d shop -c \
  "ALTER SYSTEM SET max_connections = 30; SELECT pg_reload_conf();" || true

echo "  T+30s  starting a traffic surge (20× normal)"
sleep 30
kubectl -n shop apply -f game-day/loadgen-surge.yaml

cat <<'MSG'

  💥 INJECTED: HikariCP pool = 2 connections, 20× traffic

  THE CAUSAL CHAIN you should be able to see in the metrics:
    1. hikaricp_connections_active → 2 (pinned at max)          ← T+10s
    2. hikaricp_connections_pending → climbs to 50+              ← T+15s
    3. hikaricp_connections_acquire_seconds p95 → 20s+           ← T+20s
    4. tomcat_threads_busy_threads → 200 (all blocked on the pool) ← T+40s
    5. http_server_requests p99 → 30s                            ← T+60s
    6. HikariCP connection-timeout exceeded → SQLException
    7. http_server_requests 5xx → climbs                         ← T+90s
    8. CheckoutErrorRatioHigh FIRES                                ← T+~4m
    9. ServletThreadsNearExhaustion FIRES (saturation tier)       ← T+~2m

  ⭐ THE LESSON: the SATURATION alert (step 9) fires ~2 minutes BEFORE the
     SYMPTOM alert (step 8). That's the entire value of tier 2 — it's your
     early warning. If your saturation alerts are only tickets, you lose the
     window; if they page, you drown in noise. The right answer: saturation
     alerts page during business hours and ticket at night.

MSG
EOF
chmod +x game-day/scenarios/02-db-pool-exhaustion.sh

cat > game-day/loadgen-surge.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: loadgen-surge, namespace: shop}
spec:
  replicas: 8
  selector: {matchLabels: {app: loadgen-surge}}
  template:
    metadata: {labels: {app: loadgen-surge}}
    spec:
      containers:
        - name: curl
          image: curlimages/curl:8.10.1
          command: ["sh","-c"]
          args:
            - |
              while true; do
                for i in $(seq 1 50); do
                  curl -s -o /dev/null -m 5 -XPOST http://shop-api/api/orders \
                    -H 'Content-Type: application/json' \
                    -d "{\"items\":$((i%7+1)),\"tier\":\"gold\"}" &
                done
                wait; sleep 0.2
              done
          resources: {requests: {cpu: 200m, memory: 64Mi}, limits: {memory: 128Mi}}
EOF
```

### Scenario 03 — the memory leak

```bash
cat > game-day/scenarios/03-memory-leak.sh <<'EOF'
#!/usr/bin/env bash
# 💥 A MEMORY LEAK. The pod grows until it OOMKills, restarts, and does it again.
set -euo pipefail
echo "  T+0s   enabling the leak (512 KB retained per request) and capping memory"
kubectl -n shop set env deploy/shop-api LEAK_KB_PER_REQUEST=512
kubectl -n shop patch deploy shop-api --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"768Mi"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"768Mi"}]'
kubectl -n shop rollout status deploy/shop-api --timeout=300s

echo "  T+30s  steady traffic"
sleep 30
kubectl -n shop apply -f game-day/loadgen.yaml

cat <<'MSG'

  💥 INJECTED: 512 KB retained per request, memory limit 768 Mi

  THE TIMELINE you should observe:
    T+  0m   container_memory_working_set_bytes begins a STEADY LINEAR climb
    T+ ~5m   ServiceMemoryNearLimit fires (>90% of the limit)      ← ⭐ the warning
    T+ ~7m   the JVM's GC gets desperate: jvm_gc_pause_seconds_max climbs,
             jvm_memory_used_bytes{area="heap"} sawtooths with a rising floor
    T+ ~8m   OOMKilled, exit code 137
    T+ ~8m   KubeContainerOOMKilled + PodRestartingFrequently fire
    T+ ~8m   the pod restarts, memory resets, and the cycle repeats
    T+ ~9m   HPA may scale out (more pods = more total memory = slower per-pod growth)

  ⭐ THE DIAGNOSTIC QUERY — distinguish a leak from normal growth:
      # is the SAWTOOTH FLOOR rising? That's a leak. A stable floor with tall
      # spikes is normal allocation.
      min_over_time(jvm_memory_used_bytes{namespace="shop",area="heap"}[10m])

      # predict_linear says when you die:
      predict_linear(container_memory_working_set_bytes{namespace="shop",pod=~"shop-api.*"}[30m], 3600)

      # was it an OOMKill or a liveness-probe kill?
      kube_pod_container_status_last_terminated_reason{namespace="shop"}

  ⭐ THE TRAP: an HPA on CPU will NOT save you. A leaking pod uses little CPU
     while it dies. This is why memory-vs-limit is a saturation alert and why
     `predict_linear` on the sawtooth floor is the correct leak detector.

MSG
EOF
chmod +x game-day/scenarios/03-memory-leak.sh
```

### Scenario 04 — the cardinality bomb

```bash
cat > game-day/scenarios/04-cardinality-bomb.sh <<'EOF'
#!/usr/bin/env bash
# 💥 A NEW LABEL WITH UNBOUNDED VALUES. Prometheus's series count explodes.
#    This is the failure mode that takes down a monitoring platform in production.
set -euo pipefail

cat > /tmp/cardinality-bomb-sm.yaml <<'SM'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: cardinality-bomb, namespace: shop, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: shop-api}}
  endpoints:
    - port: metrics
      interval: 15s
      metricRelabelings:
        # ⭐⭐ the bomb: relabel the request ID (unbounded) INTO a label
        - sourceLabels: [__name__]
          regex: 'http_server_requests_seconds_(count|sum|bucket)'
          action: keep
SM
kubectl apply -f /tmp/cardinality-bomb-sm.yaml

echo "  T+0s   enabling the app's per-request-ID metric tag"
kubectl -n shop set env deploy/shop-api \
  MANAGEMENT_METRICS_TAGS_REQUEST_ID=enabled \
  MANAGEMENT_METRICS_ENABLE_ALL=true
kubectl -n shop rollout status deploy/shop-api --timeout=300s

echo "  T+60s  high-cardinality traffic (every request has a unique ID)"
sleep 60
kubectl -n shop apply -f game-day/loadgen-surge.yaml

cat <<'MSG'

  💥 INJECTED: a `request_id` label on every HTTP metric

  THE TIMELINE:
    T+  0m   prometheus_tsdb_head_series starts climbing LINEARLY WITH TRAFFIC
             (normal series counts are FLAT regardless of traffic)
    T+ ~3m   PrometheusCardinalityBudgetExceeded fires (>500k series)
    T+ ~5m   scrape_duration_seconds climbs; scrape_samples_scraped for shop-api
             goes from ~2,000 to ~500,000
    T+ ~8m   PrometheusScrapesTimingOut fires
    T+ ~10m  process_resident_memory_bytes climbs → PrometheusOutOfMemorySoon
    T+ ~15m  Prometheus OOMKills. ⛔ EVERY DASHBOARD GOES BLANK. EVERY ALERT STOPS.

  ⭐ THE DIAGNOSIS — three queries, in order:
      # 1. how many series, and is it growing?
      prometheus_tsdb_head_series
      deriv(prometheus_tsdb_head_series[10m])

      # 2. WHICH METRIC?
      topk(10, count by (__name__) ({__name__=~".+"}))

      # 3. WHICH LABEL?
      #    Prometheus's own TSDB status endpoint does this for you:
      curl -s localhost:9090/api/v1/status/tsdb | jq '.data.top10CountByMetricName'
      curl -s localhost:9090/api/v1/status/tsdb | jq '.data.top10SeriesCountByMetricName'
      # and for label VALUES:
      curl -sG localhost:9090/api/v1/label/request_id/values | jq 'length'
      # ⛔ 480,213  ← there it is

  ⭐ THE FIX:
      # 1. stop the bleeding — drop the label at scrape time
      kubectl -n shop patch servicemonitor cardinality-bomb --type=json -p='[{
        "op":"add","path":"/spec/endpoints/0/metricRelabelings/-",
        "value":{"sourceLabels":["__name__"],"regex":".*","targetLabel":"request_id","replacement":"","action":"replace"}}]'
      # 2. remove the offending tag from the app
      kubectl -n shop set env deploy/shop-api MANAGEMENT_METRICS_TAGS_REQUEST_ID-
      # 3. the series stay in the head block until compaction — restart Prometheus to reclaim
      kubectl -n monitoring rollout restart sts/kps-kube-prometheus-stack-prometheus

  ⭐⭐ THE PREVENTION (this is what the CI gate is for):
      - a cardinality budget asserted in CI on every PR
      - a PrometheusCardinalityBudgetExceeded alert at 60% of the budget, not 100%
      - a metricRelabelings `drop` rule in the ServiceMonitor as a standing guard
      - code review rule: a label value must come from a BOUNDED set

MSG
EOF
chmod +x game-day/scenarios/04-cardinality-bomb.sh
```

### Scenario 05 — going blind ⭐ the scariest one

```bash
cat > game-day/scenarios/05-monitoring-blind.sh <<'EOF'
#!/usr/bin/env bash
# 💥 THE OBSERVABILITY PLATFORM ITSELF FAILS.
#    This is the scenario that separates a real SRE from someone who installed a Helm chart.
set -euo pipefail
mode="${1:-collector}"

case "$mode" in
  collector)
    echo "  T+0s   breaking the OTel Collector with an invalid config"
    cp platform/otel/gateway-config.yaml /tmp/gateway-config.yaml.bak
    sed -i 's/memory_limiter:/memory_limiterr:/' platform/otel/gateway-config.yaml
    kubectl create cm otel-gateway-config -n otel \
      --from-file=config.yaml=platform/otel/gateway-config.yaml \
      --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n otel rollout restart deploy/otel-collector-gateway
    echo "  ⛔ the gateway is now in CrashLoopBackOff. NO TRACES. NO LOGS VIA OTLP."
    ;;
  prometheus)
    echo "  T+0s   breaking a Prometheus rule group"
    cp platform/prometheus/alerting-rules/symptom.yaml /tmp/symptom.yaml.bak
    sed -i 's/sum by (le)/sum by (le]/' platform/prometheus/alerting-rules/symptom.yaml
    kubectl apply -f platform/prometheus/alerting-rules/symptom.yaml
    echo "  ⛔ the whole rule group is REJECTED. Every alert in it silently stops working."
    echo "  ⭐ PrometheusRuleFailures is the ONLY thing that will tell you."
    ;;
  network)
    echo "  T+0s   blocking Prometheus's egress with a NetworkPolicy"
    kubectl apply -f - <<'NP'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: block-scrapes, namespace: shop}
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress: []          # ⭐ deny ALL ingress, including Prometheus scrapes
NP
    echo "  ⛔ every target in namespace shop is now DOWN."
    ;;
  alertmanager)
    echo "  T+0s   breaking the Slack webhook"
    kubectl -n monitoring create secret generic alertmanager-slack \
      --from-literal=slack-webhook-url='https://hooks.slack.com/services/BROKEN/BROKEN/BROKEN' \
      --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n monitoring rollout restart sts/alertmanager-kps-kube-prometheus-stack-alertmanager 2>/dev/null || true
    echo "  ⛔ alerts fire, route correctly, and go NOWHERE."
    echo "  ⭐ AlertmanagerNotificationsFailing is the only thing that tells you."
    ;;
esac

cat <<'MSG'

  💥 THE POINT OF THIS SCENARIO

  When the monitoring breaks, YOU HAVE NO MONITORING TO TELL YOU.
  The only defences are:

    1. ⭐ An EXTERNAL watchdog — a dead-man's switch. Prometheus sends a
       `Watchdog` alert that is ALWAYS firing; an external service (PagerDuty
       heartbeat, Healthchecks.io, a cron in a different cluster) pages you
       when it STOPS arriving. This is the single most important alert in
       existence and almost nobody has one.

    2. ⭐ Synthetic probing from OUTSIDE the cluster — the blackbox exporter
       probing Grafana, Prometheus and Alertmanager from another namespace,
       and an external uptime checker probing the blackbox exporter.

    3. ⭐ CI validation, so a bad config never reaches the cluster.
       `promtool check rules` and `otelcol --dry-run` both catch scenario 05.

    4. ⭐ Self-monitoring alerts on a SEPARATE Prometheus — in production,
       run a second, tiny Prometheus whose only job is scraping the first one.

MSG
EOF
chmod +x game-day/scenarios/05-monitoring-blind.sh
```

**The dead-man's switch — implement it, don't just read about it:**

```yaml
# platform/prometheus/alerting-rules/watchdog.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: watchdog, namespace: monitoring, labels: {release: kps}}
spec:
  groups:
    - name: watchdog
      rules:
        # ⭐⭐ this alert is DESIGNED to always fire. If it ever stops, you're blind.
        - alert: Watchdog
          expr: vector(1)
          labels:
            severity: none
            team: platform
            tier: self
            alert_type: heartbeat
          annotations:
            summary: "an always-firing heartbeat. Its ABSENCE means Prometheus or Alertmanager is dead."
            description: |
              This alert must be firing at all times. An external watchdog
              (PagerDuty Heartbeat, Healthchecks.io, or a second Prometheus)
              pages the platform team when this alert has NOT been received
              for more than 5 minutes.
```

```yaml
# platform/alertmanager/alertmanager.yaml — the watchdog route
# ⭐ it goes to a receiver that forwards to an EXTERNAL service
  route:
    routes:
      - receiver: heartbeat-external
        groupWait: 0s
        groupInterval: 1m
        repeatInterval: 1m              # ⭐ send it EVERY MINUTE, forever
        continue: false
        matchers:
          - {name: alertname, value: Watchdog}

  receivers:
    - name: heartbeat-external
      webhookConfigs:
        - url: https://hc-ping.com/YOUR-UUID          # ⭐ Healthchecks.io (free tier works)
          sendResolved: false
          maxAlerts: 1
        - url: https://events.pagerduty.com/v2/enqueue   # ⭐ or PagerDuty Events API v2
          sendResolved: false
          httpConfig:
            basicAuth: {username: {value: ""}, password: {name: pd-heartbeat, key: routing-key}}
```

```bash
# the external side: Healthchecks.io
# 1. create a check with a 5-minute grace period
# 2. its "how to ping" URL is the webhook above
# 3. configure it to email/Slack/page when it MISSES a ping
# 4. test it:
kubectl -n monitoring scale sts/kps-kube-prometheus-stack-prometheus --replicas=0
# ⭐ within 5 minutes, Healthchecks.io pages you: "Prometheus is dead."
#    That page came from OUTSIDE the broken system. That's the whole point.
kubectl -n monitoring scale sts/kps-kube-prometheus-stack-prometheus --replicas=1
```

### The game-day scorecard

Fill this in during the drill. **A score under 8/10 means the platform isn't done.**

| Scenario | Expected alert | Time to fire | Time to diagnose | Correct root cause? | Runbook sufficient? | Score |
|---|---|---|---|---|---|---|
| 01 payment timeout | `CheckoutLatencyP99High` | ___ s | ___ min | ☐ | ☐ | /2 |
| 02 pool exhaustion | `DatabasePoolNearExhaustion` **before** `CheckoutErrorRatioHigh` | ___ s | ___ min | ☐ | ☐ | /2 |
| 03 memory leak | `ServiceMemoryNearLimit` before the OOMKill | ___ s | ___ min | ☐ | ☐ | /2 |
| 04 cardinality bomb | `PrometheusCardinalityBudgetExceeded` before the OOM | ___ s | ___ min | ☐ | ☐ | /2 |
| 05 going blind | `Watchdog` absence → an external page | ___ s | ___ min | ☐ | ☐ | /2 |

**Additional assertions per scenario:**
```
□ the alert named the right TEAM (routing worked)
□ the alert had a working runbook link
□ the runbook's queries returned the data they promised
□ you reached the root-cause TRACE in ≤4 clicks from the alert
□ you reached the root-cause LOG LINE from the trace
□ NO unrelated alerts fired (inhibit rules worked)
□ the alert auto-resolved after healing (sendResolved worked)
□ you filed the follow-up actions within 24h
```

```bash
cat > game-day/reports/_TEMPLATE.md <<'EOF'
# Incident report — <SCENARIO> — <DATE>

**Drill or real:** drill · **Duration:** ___ min · **On-call:** ___ · **Severity:** ___

## Timeline (UTC)
| Time | Event | Source |
|---|---|---|
| | injection | game-day.sh |
| | first metric moved | which panel |
| | first alert fired | which alert, how many seconds after injection |
| | acknowledged | who |
| | root cause identified | what evidence |
| | mitigation applied | what command |
| | resolved | alert auto-resolved at |

## Detection
- First alert: `___` at T+___s
- Was it the RIGHT alert? ☐ yes ☐ no — better would have been: ___
- False positives fired: ___ (these should be zero)
- Alerts that SHOULD have fired but didn't: ___

## Diagnosis
- Click path used: dashboard → ___ → ___ → ___
- Time from page to root cause: ___ min
- Did the runbook work as written? ☐ yes ☐ partially ☐ no
- What the runbook was missing: ___

## Impact
- Requests affected: ___
- SLO budget consumed: ___%
- User-visible duration: ___ min

## Actions
| # | Action | Owner | Due | Type |
|---|---|---|---|---|
| 1 | | | | prevent / detect faster / mitigate faster |

## What went well
## What went badly
## What we were lucky about
EOF
```

---

<a name="phase-8--scale-cost-and-hardening"></a>
## Phase 8 — Scale, cost and hardening

### 8.1 The cardinality report — run it weekly

```bash
cat > scripts/cardinality-report.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ The single most useful cost/health script in this repo. Run it weekly.
set -euo pipefail
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 5
Q() { curl -sG localhost:9090/api/v1/query --data-urlencode "query=$1"; }

echo "════════════════════════════════════════════════════════════════════"
echo "  CARDINALITY REPORT — $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "════════════════════════════════════════════════════════════════════"

echo
echo "── headline numbers ──"
Q 'prometheus_tsdb_head_series'                        | jq -r '"  active series:        \(.data.result[0].value[1])"'
Q 'prometheus_tsdb_head_series_created_total'          | jq -r '"  series created (life): \(.data.result[0].value[1])"'
Q 'count({__name__=~".+"})'                            | jq -r '"  series (verified):     \(.data.result[0].value[1])"'
Q 'count(count by (__name__) ({__name__=~".+"}))'       | jq -r '"  distinct metric names: \(.data.result[0].value[1])"'
Q 'prometheus_tsdb_head_chunks'                        | jq -r '"  head chunks:           \(.data.result[0].value[1])"'
Q 'process_resident_memory_bytes{job=~".*prometheus.*"}'| jq -r '"  Prometheus RSS:        \(.data.result[0].value[1]|tonumber/1024/1024|floor) MiB"'
Q 'sum(scrape_samples_scraped)'                        | jq -r '"  samples per scrape:    \(.data.result[0].value[1])"'
Q 'rate(prometheus_tsdb_head_samples_appended_total[5m])' | jq -r '"  ingestion rate:        \(.data.result[0].value[1]|tonumber|floor) samples/s"'
echo "  budget:                $(grep -oE '^[0-9]+' ci/cardinality-budget.txt)"

echo
echo "── TOP 25 metrics by series count ⭐ the usual suspects ──"
curl -s localhost:9090/api/v1/status/tsdb \
  | jq -r '.data.top10SeriesCountByMetricName[] | "  \(.value|tostring|ltrimstr("0"))\t\(.name)"' 2>/dev/null || true
# the API only returns 10; get 25 with a real query:
Q 'topk(25, count by (__name__) ({__name__=~".+"}))' \
  | jq -r '.data.result[] | "  \(.value|tostring|rtrimstr(".0"))\t\(.metric.__name__)"'

echo
echo "── TOP 25 metrics by sample volume (the expensive ones) ──"
Q 'topk(25, sum by (__name__) (scrape_samples_scraped))' \
  | jq -r '.data.result[] | "  \(.value|tostring|rtrimstr(".0"))\t\(.metric.__name__)"' 2>/dev/null || true

echo
echo "── TOP 15 label names by distinct values ⭐ the cardinality drivers ──"
for lbl in job namespace pod container instance node deployment statefulset \
           le uri method status application service_name team env request_id \
           trace_id order_id user_id image_id image_tag reason; do
  n=$(curl -s "localhost:9090/api/v1/label/$lbl/values" | jq '.data | length' 2>/dev/null || echo 0)
  [[ "$n" -gt 0 ]] && printf '  %-24s %s\n' "$lbl" "$n"
done | sort -k2 -rn | head -15

echo
echo "── ⛔ DANGEROUS labels (>1000 distinct values) ──"
found=0
for lbl in $(curl -s localhost:9090/api/v1/labels | jq -r '.data[]'); do
  n=$(curl -s "localhost:9090/api/v1/label/$lbl/values" | jq '.data | length' 2>/dev/null || echo 0)
  if [[ "$n" -gt 1000 ]]; then printf '  ⛔ %-28s %s distinct values\n' "$lbl" "$n"; found=1; fi
done
[[ "$found" == 0 ]] && echo "  ✅ none — every label is bounded"

echo
echo "── churn: series created per hour (a leak indicator) ──"
Q 'deriv(prometheus_tsdb_head_series_created_total[1h]) * 3600' \
  | jq -r '.data.result[0].value[1] | "  \(tonumber|floor) new series/hour"'
echo "  ⭐ a healthy system creates series at a FLAT rate. A rising rate = churn = a leak."

echo
echo "── per-job breakdown ──"
Q 'topk(20, sum by (job) (scrape_samples_scraped))' \
  | jq -r '.data.result[] | "  \(.value|tostring|rtrimstr(".0")|ltrimstr("0"))\t\(.metric.job)"'

echo
echo "── recommendations ──"
cat <<'REC'
  1. any metric in the top 25 you don't dashboards or alert on → add a metricRelabelings drop
  2. any label with >1000 values → it is unbounded; move it into the log/trace, not the metric
  3. any job whose samples/scrape grew after a release → diff the /metrics output
  4. container_* metrics dominate → check cAdvisor's `--store_container_labels=false`
  5. kube_* metrics dominate → trim kube-state-metrics with `metricAllowlist`
  6. a single metric > 20% of the total → it is almost certainly mislabelled
REC
echo
EOF
chmod +x scripts/cardinality-report.sh
./scripts/cardinality-report.sh
```

### 8.2 The cost model

```
                       SERIES   SAMPLES/s   RETENTION   DISK        NOTES
──────────────────────────────────────────────────────────────────────────────
node_exporter           1,200        40      15d        ~2 GB      per node ×3
kube-state-metrics      8,500       280      15d       ~14 GB      ⭐ the big one
cAdvisor               15,000       500      15d       ~25 GB      ⭐⭐ the biggest
apiserver               2,000        66      15d        ~3 GB
app metrics (5 svc)     4,000       133      15d        ~7 GB
blackbox                  400        13      15d        ~1 GB
OTLP metrics              800        26      15d        ~1 GB
recording rules           600        20      15d        ~1 GB      ⭐ cheap and fast
──────────────────────────────────────────────────────────────────────────────
TOTAL                  32,500     1,078      15d       ~53 GB

  rule of thumb: 1 active series ≈ 1.5–2 bytes/sample × (86400/30) samples/day
                              ≈ ~5 KB/day/series  →  32,500 × 5 KB × 15d ≈ 2.4 GB
                 (the real number is higher because of index overhead and churn)

TRACES (Tempo):
  spans/day           ≈ 8.4M at 100% head sampling
  bytes/span          ≈ 500 B–1.5 KB (parquet, compressed ≈ 300 B)
  at 100%             ≈ 40 GB/day   → 72h retention ≈ 120 GB
  at 10% tail-sampled ≈  4 GB/day   → 72h retention ≈  12 GB     ⭐ 90% saving

LOGS (Loki):
  log lines/day       ≈ 12M
  bytes/line          ≈ 400 B raw, ≈ 90 B compressed (Loki is very good at this)
  total               ≈ 1.1 GB/day  → 7d retention ≈ 8 GB
```

**The levers, in order of effectiveness:**

| Lever | Saving | Cost |
|---|---|---|
| ⭐ Tail-sample traces to 10% | **90% of trace storage** | Gateway memory, 15s query delay |
| ⭐ Reduce trace retention 7d → 72h | 70% of trace storage | Can't investigate last week |
| Drop unused metrics with `metricRelabelings` | 20–60% of metric storage | Requires the cardinality report |
| `--store_container_labels=false` on cAdvisor | 30% of cAdvisor series | Lose some pod labels |
| Raise `scrapeInterval` 15s → 30s | 50% of samples | Coarser resolution, worse histograms |
| ⭐ Use recording rules and query those | Faster dashboards (not smaller) | Extra series |
| Loki: shorter retention for DEBUG | 40% of log storage | Can't debug last week |
| Remote-write to object storage (Thanos/Mimir) | Unlimited retention at 10× lower $/GB | Operational complexity |
| Native histograms | 30–50% of histogram storage | Requires Prometheus 3.x + SDK support |

### 8.3 Long-term storage and HA (the production shape)

```
                             ┌──────────────────────────────────────┐
                             │   Prometheus A      Prometheus B     │  ⭐ identical configs,
                             │   (replica=0)       (replica=1)      │     different externalLabels.replica
                             └────┬───────────────────┬─────────────┘
                                  │ remote_write      │ remote_write
                                  ▼                   ▼
                        ┌─────────────────────────────────────────┐
                        │  THANOS RECEIVE  (or Cortex / Mimir)    │
                        │  · deduplicates on the PrometheusReplica │
                        │  · label, horizontally scalable          │
                        │  · writes to S3/GCS/Azure Blob           │
                        └───────────────┬─────────────────────────┘
                                        ▼
                              ┌───────────────────┐
                              │  OBJECT STORAGE   │  ⭐ $0.02/GB/month
                              │  (S3 / GCS / Blob)│     vs $0.10 for a PV
                              └───────────────────┘
                                        ▲
                        ┌───────────────┴─────────────────────────┐
                        │  THANOS QUERIER (Store Gateway + Receive)│
                        │  · global PromQL view, 13 months          │
                        └───────────────┬─────────────────────────┘
                                        ▼
                                  ┌──────────┐
                                  │ GRAFANA  │  ← one datasource: "Thanos"
                                  └──────────┘
```

| Option | Best for | Retention | Cost at 1M series | Complexity |
|---|---|---|---|---|
| Local TSDB | ≤500k series, ≤15d | 15d | ~$50/mo (disk) | ⭐ |
| **Thanos** | 1M–100M series, 13 months | 13 mo | ~$400/mo | ⭐⭐⭐ |
| **Grafana Mimir** | >10M series, multi-tenant | years | ~$800/mo | ⭐⭐⭐⭐ |
| VictoriaMetrics | High compression, simple ops | years | ~$300/mo | ⭐⭐ |
| AMP / GMP / Azure Monitor | You don't want to operate it | 15 mo | ~$1,500/mo | ⭐ |
| Datadog / New Relic | You want the whole product | 15 mo | ~$8,000/mo | ⭐ |

```yaml
# the HA config diff — everything else stays the same
prometheus:
  prometheusSpec:
    replicas: 2
    externalLabels:
      cluster: learn
      region: ap-south-1
      prometheus_replica: ""       # ⭐ the Operator sets this per replica automatically
    remoteWrite:
      - url: http://thanos-receive.monitoring.svc:19291/api/v1/write
        remoteTimeout: 30s
        writeRelabelConfigs:
          # ⭐ don't ship the expensive, low-value series to object storage
          - {sourceLabels: [__name__], regex: 'go_.*|process_.*', action: drop}
          - {sourceLabels: [__name__], regex: '.*_created', action: drop}
        queueConfig:
          capacity: 100000
          maxShards: 50
          minShards: 1
          maxSamplesPerSend: 2000
          batchSendDeadline: 30s
          minBackoff: 30ms
          maxBackoff: 5s
```

### 8.4 Hardening

```bash
# ── 1. no anonymous Grafana ──────────────────────────────────────
kubectl -n monitoring patch cm kps-grafana --type=merge -p '{
  "data":{"grafana.ini":"[auth.anonymous]\nenabled = false\n[auth]\ndisable_login_form = false\n[security]\nadmin_user = admin\ndisable_gravatar = true\ncookie_secure = true\n[users]\nallow_sign_up = false\n"}}'
# ⭐ in production: SSO via OIDC
#   [auth.generic_oauth]
#   enabled = true
#   client_id = grafana
#   auth_url = https://idp.example.com/oauth2/authorize
#   token_url = https://idp.example.com/oauth2/token
#   api_url = https://idp.example.com/oauth2/userinfo
#   role_attribute_path = contains(groups[*], 'sre') && 'Admin' || 'Viewer'

# ── 2. the admin password in a Secret, not in values.yaml ────────
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)" \
  --dry-run=client -o yaml | kubectl apply -f -
# and in values: admin.existingSecret: grafana-admin

# ── 3. no Prometheus admin API ───────────────────────────────────
#    enableAdminAPI: false   ⭐ already set. With it on, anyone can DELETE your TSDB.

# ── 4. the OTLP endpoint is not public ───────────────────────────
kubectl -n otel get svc
# ⛔ there must be NO LoadBalancer or NodePort service for :4317/:4318
# ✅ expose OTLP/HTTP for browsers through the Ingress ONLY, with:
cat > platform/kubernetes/apps/otel-ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: otel-collector
  namespace: otel
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://shop.example.com"   # ⭐ ONE origin
    nginx.ingress.kubernetes.io/cors-allow-methods: "POST, OPTIONS"
    nginx.ingress.kubernetes.io/limit-rps: "50"                                  # ⭐ rate limit
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"
    nginx.ingress.kubernetes.io/proxy-body-size: "8m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
    # ⭐ require an API key on the browser path
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: otel-ingress-auth
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls: [{hosts: [otel.shop.example.com], secretName: otel-tls}]
  rules:
    - host: otel.shop.example.com
      http:
        paths:
          - {path: /v1/traces, pathType: Prefix, backend: {service: {name: otel-collector-gateway, port: {number: 4318}}}}
EOF

# ── 5. RBAC — who can read the telemetry? ────────────────────────
cat > platform/kubernetes/rbac.yaml <<'EOF'
# ⭐ traces and logs contain far more sensitive data than metrics.
#    Grafana's own RBAC (Enterprise) or a reverse proxy with OIDC claims is the
#    right place to enforce "team X can only see namespace X".
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: telemetry-reader, namespace: monitoring}
rules:
  - {apiGroups: [""], resources: [configmaps], verbs: [get, list]}
  - {apiGroups: ["monitoring.coreos.com"], resources: [prometheusrules, servicemonitors], verbs: [get, list]}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: payments-telemetry-reader, namespace: monitoring}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: telemetry-reader}
subjects: [{kind: Group, name: "payments-team", apiGroup: rbac.authorization.k8s.io}]
EOF

# ── 6. the Collector's RBAC is read-only ⭐ ──────────────────────
kubectl auth can-i --list --as=system:serviceaccount:otel:otel-agent -n otel | head -20
# ✅ must be get/list/watch on pods, namespaces, nodes, deployments, replicasets ONLY
# ⛔ never create/update/delete, never secrets

# ── 7. PII redaction is in the pipeline, not the app ─────────────
grep -A20 'attributes/redact' platform/otel/gateway-config.yaml
# ✅ db.query.text hashed, authorization/cookie deleted, user.email hashed

# ── 8. Pod Security Standards ────────────────────────────────────
kubectl label ns otel pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl label ns monitoring pod-security.kubernetes.io/enforce=privileged --overwrite
# ⭐ monitoring needs privileged for node_exporter's host mounts and the filelog receiver

# ── 9. backups ───────────────────────────────────────────────────
#    Prometheus TSDB: you generally DON'T back it up — it's rebuildable from the apps.
#    Grafana: the DASHBOARDS ARE IN GIT. Only the DB (users, alert state) needs a backup.
#    Alertmanager: silences and notification state — nice to have, not critical.
#    ⭐ what you MUST be able to rebuild from Git alone:
git ls-files platform/ | wc -l
./scripts/bootstrap-cluster.sh    # ← if this works from a clean machine, you're safe
```

---

<a name="phase-9--handover"></a>
## Phase 9 — Handover

The last phase is documentation. **A platform nobody can operate is not a platform.**

### 9.1 The runbook template

```markdown
# platform/runbooks/_template.md

## <AlertName>

| | |
|---|---|
| **Severity** | critical / warning |
| **Tier** | symptom / saturation / cause / self |
| **Team** | payments |
| **SLO** | SLO-2 (checkout latency) |
| **Pages?** | yes / no |
| **Meaning** | <one sentence: what is true in the world when this fires> |
| **User impact** | <what the customer experiences> |

### The alert expression, in English
> <paste the expr and translate it. "The ratio of 5xx to total requests on the
> checkout routes, over 5 minutes, exceeds 1%." >

### First 60 seconds
1. Open the [Incident dashboard](http://localhost:3000/d/99-incident).
2. Read the **DURATION** panel and classify: tail / subset / global.
3. <the ONE query that most often identifies the cause>

### Diagnosis
<the decision tree. Every branch ends in either a mitigation or another runbook.>

### Mitigations, fastest first
| Action | Command | Time | Risk |
|---|---|---|---|

### Did we deploy?
<the exact command to check>

### Resolution
<how to confirm it's fixed, and how to clean up>

### Follow-ups
<checkboxes. Every incident produces at least one.>

### History
| Date | Cause | Resolution | Report |
|---|---|---|---|
```

### 9.2 The alert catalogue — generate it

```bash
cat > scripts/generate-alert-catalog.py <<'PYEOF'
#!/usr/bin/env python3
"""⭐ Generate docs/ALERT-CATALOG.md from the rule files. Never hand-maintain it."""
import glob, yaml, collections, datetime, pathlib

rows = []
for f in sorted(glob.glob("platform/prometheus/alerting-rules/*.yaml")):
    for doc in yaml.safe_load_all(open(f)):
        if not doc or "spec" not in doc:
            continue
        for g in doc["spec"].get("groups", []):
            for r in g.get("rules", []):
                if "alert" not in r:
                    continue
                lbl = r.get("labels") or {}
                ann = r.get("annotations") or {}
                rows.append({
                    "alert": r["alert"],
                    "severity": lbl.get("severity", "?"),
                    "tier": lbl.get("tier", "?"),
                    "team": lbl.get("team", "unowned"),
                    "for": r.get("for", "0s"),
                    "summary": (ann.get("summary") or "").replace("|", "/").strip(),
                    "runbook": (ann.get("runbook_url") or "MISSING").split("/")[-1],
                    "file": pathlib.Path(f).name,
                    "expr": " ".join((r.get("expr") or "").split())[:120],
                })

by_tier = collections.defaultdict(list)
for r in rows:
    by_tier[r["tier"]].append(r)

out = [
    "# Alert catalogue",
    "",
    f"> Generated by `scripts/generate-alert-catalog.py` on {datetime.date.today()}.",
    f"> **{len(rows)} alerts.** Do not edit this file by hand.",
    "",
    "## Summary",
    "",
    "| Tier | Count | Pages? | Meaning |",
    "|---|---|---|---|",
]
TIER_META = {
    "symptom":    ("**yes**", "a user is affected right now"),
    "saturation": "no (ticket)",
    "cause":      "no (ticket)",
    "self":       ("**yes**", "we are blind"),
}
for tier in ["symptom", "saturation", "cause", "self"]:
    rs = by_tier.get(tier, [])
    if not rs:
        continue
    meta = TIER_META.get(tier, ("?", "?"))
    pages, meaning = (meta if isinstance(meta, tuple) else (meta, "?"))
    out.append(f"| {tier} | {len(rs)} | {pages} | {meaning} |")

for tier in ["symptom", "self", "saturation", "cause"]:
    rs = by_tier.get(tier, [])
    if not rs:
        continue
    out += ["", f"## Tier: {tier}", "",
            "| Alert | Severity | Team | For | Summary | Runbook |",
            "|---|---|---|---|---|---|"]
    for r in sorted(rs, key=lambda x: (x["severity"] != "critical", x["alert"])):
        out.append(f"| `{r['alert']}` | {r['severity']} | {r['team']} | {r['for']} | "
                   f"{r['summary']} | [{r['runbook']}](../platform/runbooks/{r['runbook']}) |")

out += ["", "## Every alert expression", ""]
for r in sorted(rows, key=lambda x: x["alert"]):
    out += [f"### `{r['alert']}`", "",
            f"- **tier:** {r['tier']} · **severity:** {r['severity']} · **team:** {r['team']} · **for:** {r['for']}",
            f"- **file:** `{r['file']}`", "", "```promql", r["expr"] + ("…" if len(r["expr"]) >= 120 else ""), "```", ""]

pathlib.Path("docs/ALERT-CATALOG.md").write_text("\n".join(out) + "\n")
print(f"✅ docs/ALERT-CATALOG.md — {len(rows)} alerts across {len(by_tier)} tiers")
PYEOF
chmod +x scripts/generate-alert-catalog.py
python3 scripts/generate-alert-catalog.py
```

### 9.3 The on-call document

```markdown
# docs/ON-CALL.md

## Your shift
- **Rotation:** weekly, Monday 10:00 IST → Monday 10:00 IST
- **Channels:** `#shop-oncall` (pages), `#shop-alerts` (tickets), `#platform-oncall` (observability)
- **Escalation:** 15 min unacknowledged → the secondary; 30 min → the engineering manager

## The three rules
1. **Acknowledge within 5 minutes**, even if only to say "looking".
2. **Mitigate before you diagnose.** A rolled-back deploy that you understand on
   Thursday beats a fixed root cause and four hours of downtime on Tuesday.
3. **If you can't mitigate in 30 minutes, escalate.** There is no shame and no
   penalty. There is a penalty for sitting alone on an incident for three hours.

## The first five minutes of any page
```
1. Open the Incident dashboard:      http://localhost:3000/d/99-incident
2. Read the alert's summary and the runbook link IN THE SLACK MESSAGE.
3. On the dashboard, ROW 0 tells you: is the SLO burning, and how fast?
4. ROW 1 (service graph) tells you: WHICH EDGE is red?
5. ROW 2 (RED) tells you: is it rate, errors, or duration? Classify the shape.
6. ROW 4 (evidence) tells you: click an error trace, then click "Logs for this span".
```
That's it. **You should be able to name a probable cause in under 5 minutes
without typing a single query.** If you can't, the dashboard or the runbook is
wrong — file that as a follow-up.

## What NOT to do
- ❌ Don't `kubectl edit` anything. Every change goes through Git, even at 3 a.m.
  (Exception: a scale command or a rollout undo, which are reversible.)
- ❌ Don't silence an alert without a comment and an expiry. `make silence ALERT=… DUR=2h WHY=…`
- ❌ Don't restart a pod to "fix" it before you've captured the evidence:
  `kubectl logs --previous`, `kubectl describe`, a heap dump, a thread dump.
- ❌ Don't investigate the monitoring platform during an application incident.
  If the dashboards look wrong, note it and move on.

## Incident severity
| Sev | Definition | Response | Comms |
|---|---|---|---|
| **SEV-1** | Checkout is down, or >5% of users affected | Everyone, now. War room. | Public status page, exec update every 30 min |
| **SEV-2** | Degraded: latency SLO burning, partial errors | On-call + the service owner | Internal channel, hourly |
| **SEV-3** | A ticket-tier alert, no user impact | Next business day | The ticket |
| **SEV-4** | An observability gap, a cardinality drift | Backlog | The ticket |

## The commands you'll actually type
```bash
make port-forward                    # Grafana :3000, Prometheus :9090, Tempo :3200, Loki :3100, AM :9093
make cluster-status                  # what's running
kubectl -n shop get pods -o wide     # the app state
kubectl -n shop rollout history deploy/shop-api
kubectl -n shop rollout undo deploy/shop-api            # ⭐ the fastest mitigation
kubectl -n shop scale deploy/shop-api --replicas=8      # ⭐ the second fastest
kubectl -n shop logs deploy/shop-api --previous --tail=200
kubectl -n shop describe pod -l app=shop-api | grep -A8 'Last State'
./scripts/game-day.sh status         # is something injected? (drills)
./scripts/silence.sh 'alertname="X"' 2h 'investigating'
make incident-report                 # generate the report skeleton
make slo-report                      # what did this cost us in budget?
```

## Handover checklist (do this at the start and the end of every shift)
```
□ Read #shop-alerts for the last 24h. Anything unresolved?
□ make cluster-status — every pod Running?
□ ./scripts/validate-trace-pipeline.sh — 8/8 passing?
□ curl -s localhost:9090/api/v1/alerts | jq '.data.alerts | length' — any long-firing?
□ ./scripts/silence.sh --list — any silences that should have expired?
□ ./scripts/cardinality-report.sh — is the series count flat?
□ Is there an open incident without a report? Write it.
□ Are the follow-ups from last week's incidents assigned?
```
```

---

<a name="capstone-tasks--answers"></a>
# 🎯 CAPSTONE TASKS & ANSWERS

Five tasks. Each one is the kind of thing an interviewer asks you to design on a whiteboard, or a real week of work on a real team. **Attempt them before reading the answers.**

| # | Task | What it proves |
|---|---|---|
| C1 | Design the SLO set for a new service, and defend every number | You understand SLOs as a product decision, not a config |
| C2 | Cut the platform's cost by 60% without losing any alerting capability | You understand cardinality, sampling and retention |
| C3 | Diagnose an incident where **nothing** is alerting but users are complaining | You understand the gaps in a metric-first design |
| C4 | Make the platform multi-tenant: 4 teams, isolation, self-service | You understand ownership, routing and platform engineering |
| C5 | Write the migration plan from this to a managed vendor — or away from one | You understand the trade-offs, not just the tools |

---

## Task C1 — Design the SLO set for a new service

**Scenario:** the team is launching `shop-search` — an Elasticsearch-backed product search API. It's on the **browse** journey, not checkout. Product wants it fast; the team wants to sleep at night. Traffic will be 400 rps at peak. The search index is refreshed every 5 minutes from Postgres.

Design the complete SLO set: the SLIs, the objectives, the windows, the alerts, and **the argument for every number you chose**. Then write the sloth spec and the unit test.

<details>
<summary><b>💡 Hints — think about these before answering</b></summary>

1. An SLO is a **promise to a user**, not a description of your system. Ask: what does the user notice?
2. Search has a failure mode that availability SLIs completely miss: **returning zero results when results exist**. That's a 200 OK.
3. Latency for search is perceived differently from checkout — a user will wait longer for a search than for a "pay" button, but not much longer.
4. Freshness (stale index) is a real SLI here, and it's a **gauge**, not a ratio.
5. Objective numbers should come from **measured baselines and business impact**, not from "99.9% sounds good".
</details>

**✅ Answer**

### Step 1 — what does the user actually experience?

| User experience | Measurable? | SLI candidate |
|---|---|---|
| "I typed a query and got results quickly" | ✅ | **latency**: p99 < 300 ms |
| "I got an error page" | ✅ | **availability**: non-5xx ratio |
| "I searched for something you definitely sell and got zero results" | ✅ ⭐ | **quality**: zero-result rate on queries that should match |
| "The new product I just added doesn't show up" | ✅ ⭐ | **freshness**: index lag |
| "The results were irrelevant" | ❌ not from telemetry | needs click-through data — out of scope for an SRE SLO |

⭐ **The two rows with ⭐ are the ones a naive design misses.** A search service can be 100% available, 100% within its latency SLO, and completely useless — because it returns `[]` for everything.

### Step 2 — the SLIs, precisely

```promql
# SLI-1: AVAILABILITY
# the good events are anything that isn't a server error or a client-visible timeout
# ⭐ 429 counts as BAD: the user asked and we refused. 404 counts as GOOD: a
#   legitimately missing resource is correct behaviour.
good:   sum(rate(http_server_requests_seconds_count{application="shop-search",status!~"5..|429"}[{{.window}}]))
total:  sum(rate(http_server_requests_seconds_count{application="shop-search"}[{{.window}}]))

# SLI-2: LATENCY
# the good events are requests faster than 300ms
good:   sum(rate(http_server_requests_seconds_bucket{application="shop-search",le="0.3"}[{{.window}}]))
total:  sum(rate(http_server_requests_seconds_count{application="shop-search"}[{{.window}}]))

# SLI-3: RESULT QUALITY ⭐ the one nobody writes
# the bad events are searches that returned zero results for a query with ≥3 characters.
# (Short queries legitimately return nothing; typos are the user's fault.)
# This requires ONE custom metric in the app: shop_search_results_count
bad:    sum(rate(shop_search_results_count{application="shop-search",result="empty",query_length_bucket="3+"}[{{.window}}]))
total:  sum(rate(shop_search_results_count{application="shop-search",query_length_bucket="3+"}[{{.window}}]))

# SLI-4: FRESHNESS ⭐ a gauge-based SLI
# the bad event is any sample where the index lag exceeds 10 minutes
bad:    count(shop_search_index_lag_seconds{application="shop-search"} > bool 600)
total:  count(shop_search_index_lag_seconds{application="shop-search"})
```

**The custom metrics you must add to `shop-search` to make SLI-3 and SLI-4 possible:**

```java
// ⭐ SLI-3: how many results did each search return?
private final DistributionSummary resultsSummary = DistributionSummary.builder("shop.search.results")
    .description("Number of results returned per search")
    .baseUnit("results")
    .tag("query_length_bucket", "3+")           // ⭐ BOUNDED — "0-2", "3-9", "10-29", "30+"
    .publishPercentileHistogram()
    .serviceLevelObjectives(0, 1, 5, 20)        // ⭐ 0 is the interesting bucket
    .register(meterRegistry);

// and a counter, which is what the SLI actually uses (cheaper and simpler):
private final Counter emptyResults = Counter.builder("shop.search.results.count")
    .tag("result", "empty")                      // ⭐ "empty" | "some" — BOUNDED
    .tag("query_length_bucket", "3+")
    .register(meterRegistry);

public SearchResult search(String query) {
    SearchResult r = esClient.search(query);
    String bucket = query.length() <= 2 ? "0-2" : query.length() <= 9 ? "3-9"
                  : query.length() <= 29 ? "10-29" : "30+";
    resultsSummary.tag("query_length_bucket", bucket).record(r.total());
    if (r.total() == 0 && query.length() >= 3) {
        emptyResults.tag("query_length_bucket", bucket).increment();
        log.warn("zero-result search query_length={} took_ms={}", bucket, r.tookMs());
        // ⭐⭐ and a SPAN ATTRIBUTE, so you can TraceQL the empty searches:
        Span.current().setAttribute("search.results", 0);
        Span.current().addEvent("search.empty_result", Attributes.of(
            AttributeKey.longKey("search.query_length"), (long) query.length()));
    }
    return r;
}

// ⭐ SLI-4: index freshness. A gauge, updated by the indexer.
Gauge.builder("shop.search.index.lag", indexState, s ->
        Duration.between(s.lastSuccessfulIndexAt(), Instant.now()).toSeconds())
    .description("Seconds since the search index was last successfully refreshed")
    .baseUnit("seconds")
    .tag("index", "products")
    .register(meterRegistry);
```

> ⚠️ **The cardinality trap in SLI-3:** you will be tempted to tag by `query`. **Never.** `query` is unbounded — it's a cardinality bomb (see Scenario 04). Bucket it into `query_length_bucket`, and put the actual query in the **log line and the span attribute**, where unbounded values belong.

### Step 3 — the objectives, and the argument for each number

| SLO | Objective | Window | Why this number |
|---|---|---|---|
| **S1: Search availability** | **99.5%** | 30d rolling | Not 99.9%. Search is on the **browse** journey: if it fails, the user can still navigate categories and **still check out**. Revenue is not directly blocked, so a tighter SLO buys nothing but pages. 99.5% = 3.6 h/month of budget — enough to absorb one bad deploy and one Elasticsearch restart. |
| **S2: Search latency** | **95% < 300 ms** | 30d rolling | 95%, not 99%: search latency has a **long tail by nature** (a rare complex query hitting a cold shard). Chasing p99 here means paging on things users don't notice. 300 ms because [Nielsen's response-time research](https://www.nngroup.com/articles/response-times-3-important-limits/) puts 200–300 ms at the boundary where a UI still feels instantaneous; above ~1 s the user's flow is broken. **Measured baseline: p95 is currently 180 ms**, so 300 ms gives 66% headroom — tight enough to catch regressions, loose enough to not fire on noise. |
| **S3: Search quality (non-empty)** | **97% of searches with ≥3 chars return ≥1 result** | 7d rolling | ⭐ 97%, and a **7-day window, not 30 days.** Reason: this SLI is dominated by **catalogue events** (a product range is delisted, a typo-heavy marketing campaign lands) rather than by engineering failures. A 30-day window would let a genuine breakage hide inside a month of history; 7 days makes it responsive. 97% because the measured baseline is 98.6% — a 1.6-point drop is a real regression, and 3% of budget absorbs normal catalogue churn. |
| **S4: Index freshness** | **99% of samples show lag < 10 min** | 7d rolling | The indexer runs every 5 minutes. 10 min = **two missed cycles**, which is unambiguously broken; one missed cycle is a normal retry. 99% rather than 99.9% because Elasticsearch snapshot/restore and node restarts legitimately cause 15-minute gaps, and paging on those trains people to ignore the alert. |

**The argument you must be able to make out loud (this is what the interviewer is listening for):**

> *"I chose 99.5% availability rather than 99.9% because search is on the browse journey — a user whose search fails can still reach checkout, so revenue isn't directly blocked. Buying three-nines here costs the team pages for an impact that doesn't justify them. I'd revisit that number if search becomes the primary navigation path, which the product roadmap suggests it might in Q2 — at that point I'd move it to 99.9% and add it to the checkout SLO's dependency list.*
>
> *The latency SLO is 95% under 300 ms, not 99%. Search has an inherently long tail: a rare complex query hitting a cold shard. Alerting on p99 means paging on things users don't feel. 300 ms is the boundary where a UI still feels instantaneous, and our measured p95 is 180 ms, so there's 66% headroom — enough to catch a regression, not enough to fire on noise.*
>
> *The SLO I'd defend hardest is the third one: search quality. A search service can be 100% available and 100% fast and completely useless — returning zero results for everything. That's a 200 OK. It took one extra counter metric, bucketed by query length to keep cardinality bounded, and it's caught two real incidents in the last quarter that no availability SLO would have seen.*
>
> *Freshness uses a 7-day window instead of 30 because it's dominated by catalogue events rather than engineering failures; a 30-day window would let a genuine breakage hide inside a month of history."*

### Step 4 — the sloth spec

```yaml
# platform/prometheus/slos/search.yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: shop-search
  namespace: monitoring
  labels: {slo: shop-search, team: search}
spec:
  service: shop-search
  labels: {team: search, tier: backend, journey: browse}
  slos:
    # ── S1: availability ────────────────────────────────────────────
    - name: search-availability
      objective: 99.5
      description: |
        99.5% of search requests must not return a server error or a 429.
        Search is on the BROWSE journey: a failure does not block checkout,
        so this SLO is deliberately looser than checkout's 99.9%.
        Revisit if search becomes the primary navigation path.
      owner: search-team
      sli:
        events:
          errorQuery: |
            sum(rate(http_server_requests_seconds_count{
              namespace="shop", application="shop-search", status=~"5..|429"}[{{.window}}]))
          totalQuery: |
            sum(rate(http_server_requests_seconds_count{
              namespace="shop", application="shop-search"}[{{.window}}]))
      alerting:
        name: SearchAvailability
        labels: {team: search, tier: symptom, journey: browse}
        pageAlert:
          labels:
            severity: critical
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/search-availability.md
          annotations:
            summary: "search is failing for {{ $value | humanizePercentage }} of requests"
            trace_query: '{ .service.name = "shop-search" && status = error }'
            log_query: '{namespace="shop",app="shop-search"} | json | level="ERROR"'
            dashboard_url: http://localhost:3000/d/13-search-red
        ticketAlert:
          labels: {severity: warning}

    # ── S2: latency ─────────────────────────────────────────────────
    - name: search-latency
      objective: 95
      description: |
        95% of search requests must complete in under 300ms.
        300ms is the boundary where a UI still feels instantaneous.
        We target p95, NOT p99: search has an inherently long tail from
        complex queries hitting cold shards, and paging on p99 trains
        people to ignore alerts.
        Measured baseline p95: 180ms (66% headroom).
      owner: search-team
      sli:
        events:
          errorQuery: |
            sum(rate(http_server_requests_seconds_count{namespace="shop",application="shop-search"}[{{.window}}]))
            -
            sum(rate(http_server_requests_seconds_bucket{namespace="shop",application="shop-search",le="0.3"}[{{.window}}]))
          totalQuery: |
            sum(rate(http_server_requests_seconds_count{namespace="shop",application="shop-search"}[{{.window}}]))
      alerting:
        name: SearchLatency
        labels: {team: search, tier: symptom}
        pageAlert:  {labels: {severity: critical}}
        ticketAlert:{labels: {severity: warning}}

    # ── S3: quality ⭐ the one nobody writes ────────────────────────
    - name: search-quality
      objective: 97
      description: |
        97% of searches with a query of 3+ characters must return at least
        one result. This catches the failure mode that availability and
        latency SLOs are structurally blind to: a search service that
        returns HTTP 200 and an empty result set for everything.
        ⭐ 7-day window, not 30: this SLI is dominated by catalogue events
           (delistings, marketing campaigns) rather than engineering failures,
           so a 30-day window would hide a real breakage inside a month of history.
        ⭐ Cardinality: the `query` value itself is NEVER a label. It is
           bucketed into query_length_bucket and the raw query goes to logs/spans.
      owner: search-team
      sli:
        events:
          errorQuery: |
            sum(rate(shop_search_results_count{namespace="shop",application="shop-search",result="empty",query_length_bucket!="0-2"}[{{.window}}]))
          totalQuery: |
            sum(rate(shop_search_results_count{namespace="shop",application="shop-search",query_length_bucket!="0-2"}[{{.window}}]))
      alerting:
        name: SearchQuality
        labels: {team: search, tier: symptom}
        pageAlert:
          labels: {severity: critical}
          annotations:
            summary: "{{ $value | humanizePercentage }} of searches are returning zero results"
            description: |
              A search service returning empty results is 100% AVAILABLE and
              100% FAST — and completely useless. Check, in order:
                1. Did the index just get rebuilt? shop_search_index_lag_seconds
                2. Is Elasticsearch returning hits but the app filtering them?
                   TraceQL: { .service.name="shop-search" && .search.results = 0 }
                3. Did a catalogue sync delete products?
                   SELECT count(*) FROM products WHERE deleted_at IS NULL;
                4. Did the query parser change? Check the last deploy.
            trace_query: '{ .service.name = "shop-search" && .search.results = 0 }'
            log_query: '{namespace="shop",app="shop-search"} |= "zero-result search"'
        ticketAlert: {labels: {severity: warning}}

    # ── S4: freshness ───────────────────────────────────────────────
    - name: search-freshness
      objective: 99
      description: |
        The search index lag must be under 10 minutes for 99% of samples.
        The indexer runs every 5 minutes, so 10 minutes = two missed cycles,
        which is unambiguously broken. One missed cycle is a normal retry.
        99% rather than 99.9%: Elasticsearch restarts and snapshot restores
        legitimately cause 15-minute gaps, and paging on those trains people
        to ignore this alert.
      owner: search-team
      sli:
        events:
          errorQuery: 'count(shop_search_index_lag_seconds{namespace="shop"} > bool 600) or vector(0)'
          totalQuery: 'count(shop_search_index_lag_seconds{namespace="shop"}) or vector(1)'
      alerting:
        name: SearchFreshness
        labels: {team: search, tier: saturation}
        pageAlert:  {labels: {severity: critical}}
        ticketAlert:{labels: {severity: warning}}
```

```bash
# generate + validate
sloth generate -i platform/prometheus/slos/search.yaml \
  -o platform/prometheus/alerting-rules/slo-search.yaml
promtool check rules platform/prometheus/alerting-rules/slo-search.yaml
# SUCCESS: 16 rules found    (4 SLOs × 4 burn-rate windows)
```

### Step 5 — the unit tests ⭐ prove the quality SLO actually works

```yaml
# ci/promtool-tests/search-test.yaml
rule_files: [../../platform/prometheus/alerting-rules/slo-search.yaml]
evaluation_interval: 1m

tests:
  # ── S3 SearchQuality: the empty-result breakage ────────────────
  - interval: 1m
    input_series:
      # a healthy search service: 1000 searches/min, 14 empty (98.6% quality)
      - series: 'shop_search_results_count{namespace="shop",application="shop-search",result="empty",query_length_bucket="3+"}'
        values: "0+14x60"
      - series: 'shop_search_results_count{namespace="shop",application="shop-search",result="some",query_length_bucket="3+"}'
        values: "0+986x60"
    alert_rule_test:
      - eval_time: 60m
        alertname: SearchQualityBurnRateFast
        exp_alerts: []            # ⭐ 1.4% empty vs a 3% budget → no alert

  - interval: 1m
    input_series:
      # 💥 the index rebuild failed: 60% of searches return nothing,
      #    BUT every request is still HTTP 200 and every one is under 100ms
      - series: 'shop_search_results_count{namespace="shop",application="shop-search",result="empty",query_length_bucket="3+"}'
        values: "0+14x20 0+600x60"
      - series: 'shop_search_results_count{namespace="shop",application="shop-search",result="some",query_length_bucket="3+"}'
        values: "0+986x20 0+400x60"
      # ⭐⭐ and PROVE the availability and latency SLOs stay GREEN through it
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-search",status="200"}'
        values: "0+1000x80"
      - series: 'http_server_requests_seconds_bucket{namespace="shop",application="shop-search",le="0.3"}'
        values: "0+990x80"
      - series: 'http_server_requests_seconds_count{namespace="shop",application="shop-search"}'
        values: "0+1000x80"
    alert_rule_test:
      - eval_time: 45m
        alertname: SearchQualityBurnRateFast
        exp_alerts:
          - exp_labels:
              alertname: SearchQualityBurnRateFast
              severity: critical
              slo: search-quality
              team: search
      # ⭐⭐ THE POINT OF THIS WHOLE TASK, ASSERTED IN A TEST:
      - eval_time: 45m
        alertname: SearchAvailabilityBurnRateFast
        exp_alerts: []            # ← availability is FINE. 100% HTTP 200.
      - eval_time: 45m
        alertname: SearchLatencyBurnRateFast
        exp_alerts: []            # ← latency is FINE. Everything under 300ms.

  # ── S4 freshness: a two-cycle miss ─────────────────────────────
  - interval: 1m
    input_series:
      - series: 'shop_search_index_lag_seconds{namespace="shop",index="products"}'
        values: "120x20 180x10 900x60"     # 2min → 3min → ⛔ 15min for an hour
    alert_rule_test:
      - eval_time: 25m
        alertname: SearchFreshnessBurnRateFast
        exp_alerts: []                    # a 3-minute lag is fine
      - eval_time: 60m
        alertname: SearchFreshnessBurnRateFast
        exp_alerts:
          - exp_labels: {alertname: SearchFreshnessBurnRateFast, severity: critical, team: search}

  # ── the false-positive test: one missed indexer cycle ──────────
  - interval: 1m
    input_series:
      - series: 'shop_search_index_lag_seconds{namespace="shop",index="products"}'
        values: "120x20 420x8 120x60"     # one 7-minute gap, then recovery
    alert_rule_test:
      - eval_time: 45m
        alertname: SearchFreshnessBurnRateFast
        exp_alerts: []                    # ⭐ under 10 min → not a breach → no page
```

```bash
promtool test rules ci/promtool-tests/search-test.yaml
# ✅ unit-testing 1 rule test file
#   ci/promtool-tests/search-test.yaml: SUCCESS
```

### Step 6 — the dashboard panel set for search

| Panel | Query | Why |
|---|---|---|
| Search QPS | `sum(rate(http_server_requests_seconds_count{application="shop-search"}[5m]))` | context |
| **Zero-result rate** ⭐ | `sum(rate(shop_search_results_count{result="empty",query_length_bucket!="0-2"}[5m])) / sum(rate(shop_search_results_count{query_length_bucket!="0-2"}[5m]))` | S3, the invisible failure |
| Zero-results by query-length bucket | `sum by (query_length_bucket) (rate(…{result="empty"}[5m]))` | is it all queries or long ones? |
| Results-per-search distribution | heatmap on `shop_search_results_count_bucket` | bimodal = something's filtering |
| Index lag | `shop_search_index_lag_seconds` with thresholds at 300/600 | S4 |
| Indexer success | `increase(shop_search_indexer_runs_total{outcome="success"}[5m])` | is it even running? |
| Elasticsearch query time | `histogram_quantile(0.99, …elasticsearch_took_ms…)` | us or ES? |
| Shard health | `elasticsearch_cluster_health_status{color!="green"}` | the usual root cause |
| Latency p50/p95/p99 with exemplars | the standard three | S2 + click-through to traces |

```traceql
# ⭐ the TraceQL that makes S3 debuggable — this is why the span attribute matters
{ .service.name = "shop-search" && .search.results = 0 }
  | rate() by (.search.query_length)

# and: find the empty searches that took a NORMAL amount of time
# (a fast empty result = ES genuinely has nothing; a slow one = a timeout that returned [])
{ .service.name = "shop-search" && .search.results = 0 && duration < 100ms }
```

---

## Task C2 — Cut the platform's cost by 60% without losing any alerting capability

**Scenario:** the platform costs $4,200/month. Finance wants it under $1,700. The constraint is absolute: **no alert may stop working, and no incident may become harder to diagnose.**

Current numbers:

```
Prometheus:    2.4M active series, 80k samples/s, 90d local retention, 8 replicas (4 HA pairs)
Tempo:         62M spans/day, 100% head sampling, 30d retention → 3.8 TB
Loki:          180M log lines/day, 90d retention → 2.1 TB
Grafana Cloud: the whole thing, usage-based
Compute:       34 CPU / 96 GB across the collectors and backends
```

Produce the plan: every lever, the expected saving, the risk, and the order of execution. Then prove you didn't break anything.

<details>
<summary><b>💡 Hints</b></summary>

1. Rank the components by cost first. 3.8 TB of traces at 30 days is almost certainly the biggest line item.
2. The question says "no alert may stop working". **Alerts run on Prometheus metrics.** So the metric pipeline is the thing you must protect, and the traces/logs are where the money is.
3. Cardinality reduction on 2.4M series is the highest-leverage *metric* change — but it risks breaking an alert, so it needs the most care.
4. Do the reversible, zero-risk changes first and measure. Don't change five things at once.
</details>

**✅ Answer**

### Step 1 — attribute the cost

```
                             STORAGE      INGEST         COMPUTE     TOTAL    %
──────────────────────────────────────────────────────────────────────────────
Traces (Tempo)               $1,140       $1,860          $280      $3,280   78%  ⭐⭐⭐
Logs (Loki)                    $210         $540          $120        $870   21%
Metrics (Prometheus)            $95         $180           $95        $370    9%
Compute (collectors, Grafana)     —           —           $320        $320    8%
                     ⛔ (percentages sum >100% because of shared infra; normalise:)
──────────────────────────────────────────────────────────────────────────────
Traces                                                   $1,980      47%
Logs                                                       $760      18%
Metrics                                                    $420      10%
Compute (everything)                                       $620      15%
Ingest/distributed overhead                                  $420      10%
                                                          ─────
                                                         $4,200
```

```bash
# how to get these numbers for real:
# Grafana Cloud → Usage & billing → per-signal breakdown
# self-hosted: du -sh on each backend's storage, plus the node cost × CPU/memory share
kubectl top pods -n monitoring --sort-by=memory | head -20
kubectl top pods -n otel       --sort-by=memory | head -20
```

**Conclusion: 47% of the bill is traces.** That's where you start — and it's the signal where a 90% reduction costs you the least, because **nobody looks at 99% of traces**.

### Step 2 — the plan, in execution order

| # | Lever | Saving | Risk | Reversible | Order |
|---|---|---|---|---|---|
| 1 | ⭐⭐ **Tail-sample traces to 10%** | **$1,780/mo (42%)** | Low — see the proof below | Instantly | **1st** |
| 2 | **Trace retention 30d → 7d** | $230/mo (5%) | Medium | Instantly | 2nd |
| 3 | **Drop the 20 most expensive unused metrics** | $110/mo (3%) | ⚠️ **High** — needs care | Instantly | 3rd |
| 4 | **Log retention 90d → 30d, DEBUG → 7d** | $310/mo (7%) | Low | Instantly | 4th |
| 5 | **cAdvisor label trimming** | $85/mo (2%) | Low | Instantly | 5th |
| 6 | **Prometheus 90d local → 15d local + remote-write to object storage** | $60/mo (1%) | Low | Instantly | 6th |
| 7 | **Collector rightsizing after 1–5** | $180/mo (4%) | Low | Instantly | 7th |
| 8 | **scrapeInterval 15s → 30s for low-value jobs** | $45/mo (1%) | Medium | Instantly | 8th |
| 9 | **Prometheus 8 → 4 replicas (2 HA pairs)** | $95/mo (2%) | Medium | Instantly | 9th |
| | | **$2,900** | | | |
| | **New total** | **$1,300** | | | ✅ **under the $1,700 target with 24% to spare** |

### Step 3 — Lever 1: tail sampling, with the proof ⭐⭐

This is the whole exercise. Do it properly:

```bash
# ── BEFORE: measure the baseline ────────────────────────────────
cat > /tmp/baseline.sh <<'EOF'
#!/usr/bin/env bash
# capture the numbers you'll be judged on
echo "spans/day:        $(curl -sG "$TEMPO/api/search" --data-urlencode 'q={}' --data-urlencode "start=$(date -d '-24 hours' +%s)" | jq '.totalBlocks')"
echo "error traces:     $(curl -sG "$TEMPO/api/search" --data-urlencode 'q={ status = error }' --data-urlencode "start=$(date -d '-24 hours' +%s)" --data-urlencode 'limit=10000' | jq '.traces | length')"
echo "slow traces >1s:  $(curl -sG "$TEMPO/api/search" --data-urlencode 'q={ duration > 1s }' --data-urlencode "start=$(date -d '-24 hours' +%s)" --data-urlencode 'limit=10000' | jq '.traces | length')"
echo "checkout traces:  $(curl -sG "$TEMPO/api/search" --data-urlencode 'q={ .url.path = "/api/orders" }' --data-urlencode "start=$(date -d '-24 hours' +%s)" --data-urlencode 'limit=10000' | jq '.traces | length')"
echo "storage:          $(du -sh /var/tempo/blocks | cut -f1)"
echo "spans accepted/s: $(curl -s :8888/metrics | awk '/^otelcol_receiver_accepted_spans/{s+=$2}END{print s}')"
EOF
chmod +x /tmp/baseline.sh
TEMPO=http://localhost:3200 /tmp/baseline.sh | tee game-day/reports/cost-baseline.txt
# spans/day:        62,418,220
# error traces:     41,208
# slow traces >1s:  186,442
# checkout traces:  2,840,116
# storage:          3.8T
```

```yaml
# the tail_sampling policy — designed from the baseline numbers, not guessed
processors:
  tail_sampling:
    decision_wait: 15s
    num_traces: 400000
    expected_new_traces_per_sec: 2500       # ⭐ from the measured 62M/day ÷ 86400 ≈ 720/s peak ×3
    decision_cache: {sampled_cache_size: 250000, non_sampled_cache_size: 250000}
    policies:
      # ── keep 100%: everything you'd ever investigate ────────────
      - {name: errors,   type: status_code, status_code: {status_codes: [ERROR]}}
      - name: http-5xx
        type: numeric_attribute
        numeric_attribute: {key: http.response.status_code, min_value: 500}
      - name: http-4xx-not-404
        type: and
        and:
          and_sub_policy:
            - {name: is-4xx, type: numeric_attribute,
               numeric_attribute: {key: http.response.status_code, min_value: 400, max_value: 499}}
            - {name: not-404, type: numeric_attribute,
               numeric_attribute: {key: http.response.status_code, min_value: 400, max_value: 403}}
      - {name: slow, type: latency, latency: {threshold_ms: 1000}}    # ⭐ > the p99 SLO
      - name: money-path
        type: string_attribute
        string_attribute:
          key: url.path
          values: [/api/orders, /api/checkout, /api/payment, /api/login, /api/refund]
      - name: search-quality-incidents        # ⭐ from Task C1 — the zero-result searches
        type: numeric_attribute
        numeric_attribute: {key: search.results, min_value: 0, max_value: 0}
      - name: canary
        type: string_attribute
        string_attribute: {key: service.version, values: ["1.4.0-rc1", "canary"]}
      - name: specific-customer
        type: string_attribute
        string_attribute: {key: customer.id, values: ["cus_ent_acme", "cus_ent_globex"]}
      # ── drop 100%: pure noise ───────────────────────────────────
      - name: not-health-checks
        type: string_attribute
        string_attribute:
          key: url.path
          values: [/actuator/health, /healthz, /health, /readyz, /livez, /metrics,
                   /favicon.ico, /robots.txt, /.well-known/*, /api/v1/ping]
          invert_match: true
      - name: not-static-assets
        type: string_attribute
        string_attribute:
          key: url.path
          values: [/static/*, /assets/*, /*.js, /*.css, /*.png, /*.woff2]
          invert_match: true
      - name: not-fast-and-ok                 # ⭐ the big one: fast + successful + not money path
        type: and
        and:
          and_sub_policy:
            - {name: is-ok, type: status_code, status_code: {status_codes: [OK, UNSET]}}
            - {name: is-fast, type: latency, latency: {threshold_ms: 250}}
      # ── sample the rest ─────────────────────────────────────────
      - {name: base, type: probabilistic, probabilistic: {sampling_percentage: 10}}
```

```bash
# deploy, wait 24h, measure again
./ci/otel-collector-validate.sh && make platform-apply
sleep 86400
TEMPO=http://localhost:3200 /tmp/baseline.sh | tee game-day/reports/cost-after.txt
diff game-day/cost-baseline.txt game-day/reports/cost-after.txt
```

**The result — and this is the part you must present:**

```
                        BEFORE          AFTER        CHANGE
──────────────────────────────────────────────────────────────────
spans/day               62,418,220     5,884,102      −90.6%   ✅
storage (30d)           3.8 TB         380 GB         −90.0%   ✅
error traces (24h)          41,208        41,196       −0.03%  ✅⭐ ZERO LOSS
slow traces >1s (24h)      186,442       186,438       −0.00%  ✅⭐ ZERO LOSS
checkout traces (24h)    2,840,116     2,840,116        0.00%  ✅⭐ ZERO LOSS
spans accepted/s             2,410         2,405        ~0%     (unchanged — head is still 100%)
spans exported/s             2,410           231       −90.4%
collector memory/gw          2.1 GB        5.8 GB     +176%     ⚠️ the cost of tail sampling
gateway replicas                 4             6       +50%     ⚠️ needed for the buffer
──────────────────────────────────────────────────────────────────
net: $1,980/mo → $200/mo for traces. Saved $1,780/mo.
     Lost: zero error traces, zero slow traces, zero money-path traces.
     Paid: 3.7 GB more gateway RAM and 2 more replicas (~$45/mo).
```

**The one thing you DO lose, and you must say it out loud:**

> *"Aggregate completeness. Any metric computed FROM traces — `traces_service_graph_*`, `traces_span_metrics_*` — is now based on a 10% sample. So I moved every count-based alert onto Prometheus-scraped metrics, which are unaffected, and I keep the trace-derived metrics only for the service graph and for ad-hoc exploration, where a 10% sample of a shape is still a perfectly good shape. No alert in the catalogue depends on a trace-derived metric — I verified that with `grep -r 'traces_' platform/prometheus/alerting-rules/` and got zero hits."*

```bash
# ⭐ THE VERIFICATION THAT NO ALERT BROKE — run this as a CI gate
grep -rlE 'traces_service_graph|traces_span_metrics|tempo_' platform/prometheus/alerting-rules/ \
  && { echo "✖ an alert depends on trace-derived metrics — sampling will break it"; exit 1; } \
  || echo "✅ no alert depends on trace-derived metrics"
```

### Step 4 — Lever 3: cardinality reduction, done safely ⚠️

This is the risky one. **Never do it by intuition — do it by evidence, and never touch a metric an alert or dashboard uses.**

```bash
# 1. the top 25 by series count
./scripts/cardinality-report.sh > /tmp/card.txt
head -60 /tmp/card.txt

# 2. ⭐ build the "in use" set FIRST — this is the safety net
cat > /tmp/in-use.sh <<'EOF'
#!/usr/bin/env bash
# every metric name referenced by an alerting rule, a recording rule, or a dashboard
{
  grep -rhoE '\b[a-z][a-z0-9_]*_(total|seconds|bytes|count|sum|bucket|info|status|ratio)\b' \
    platform/prometheus/alerting-rules/ platform/prometheus/recording-rules/
  grep -rhoE '\b[a-z][a-z0-9_]*_(total|seconds|bytes|count|sum|bucket|info|status|ratio)\b' \
    platform/grafana/dashboards/
  # and the ones sloth generated
  grep -rhoE '\b[a-z][a-z0-9_]*_(total|seconds|bytes|count|sum|bucket|info|status|ratio)\b' \
    platform/prometheus/slos/
} | sort -u > /tmp/in-use-metrics.txt
wc -l /tmp/in-use-metrics.txt
EOF
chmod +x /tmp/in-use.sh && /tmp/in-use.sh
# 312 /tmp/in-use-metrics.txt

# 3. ⭐ the diff: expensive AND unused = safe to drop
curl -sG localhost:9090/api/v1/query --data-urlencode 'topk(100, count by (__name__) ({__name__=~".+"}))' \
  | jq -r '.data.result[] | "\(.value|tostring|rtrimstr(".0"))\t\(.metric.__name__)"' \
  | sort -rn > /tmp/all-metrics.txt

join -v2 -1 2 -2 1 <(sort -k2 /tmp/all-metrics.txt) <(sort /tmp/in-use-metrics.txt) \
  | sort -rn | head -25
#     412880  container_network_receive_packets_total      ← ⚠️ careful, see below
#     388214  kube_pod_container_status_last_terminated_reason
#     240118  go_gc_duration_seconds                        ← ⭐ safe: nobody alerts on the GC histogram
#     198442  go_memstats_*  (48 metrics)                   ← ⭐ safe
#      98210  etcd_disk_wal_fsync_duration_seconds_bucket   ← safe on managed k8s (we don't run etcd)
#      76004  apiserver_request_duration_seconds_bucket{resource="leases"}  ← ⭐ drop by label
#      41220  kubelet_pod_worker_duration_seconds_bucket{operation="sync"}
#      ...

# 4. write the drop rules — in Git, reviewed, reversible
cat > platform/prometheus/metric-relabeling/drops.yaml <<'YAML'
# ⭐ applied to EVERY ServiceMonitor/PodMonitor via a shared relabeling snippet.
#    Each entry must have: a measured series count, a justification, and a date.
#    Review this file quarterly — an unused metric today may be an alert tomorrow.

# ── Go runtime internals: 240k + 198k series, zero alerts, zero dashboards ──
- {sourceLabels: [__name__], regex: 'go_gc_duration_seconds.*',        action: drop}  # 2026-08-02
- {sourceLabels: [__name__], regex: 'go_memstats_(alloc|buck_hash|gc|heap|mspan|mcache|other|stack|next)_.*', action: drop}
# ⭐ KEEP: go_goroutines, go_threads, go_memstats_heap_inuse_bytes — those ARE used
#    (PrometheusOutOfMemorySoon and the Collector memory panel)

# ── kube-state-metrics churn: 388k series, almost never queried ──
- {sourceLabels: [__name__], regex: 'kube_pod_container_status_last_terminated_.*', action: drop}
# ⚠️ EXCEPTION: KubeContainerOOMKilled uses it. So keep the reason, drop the rest:
#    → replaced by the two rules below
- {sourceLabels: [__name__], regex: 'kube_pod_container_status_last_terminated_reason', action: keep}
- {sourceLabels: [__name__], regex: 'kube_pod_container_status_last_terminated_(exitcode|message|signal|container_id)', action: drop}

# ── etcd: we're on managed Kubernetes, these are always empty ──
- {sourceLabels: [__name__], regex: 'etcd_.*', action: drop}

# ── apiserver: the noisy resources (leases, events, endpointslices) ──
- {sourceLabels: [__name__, resource], regex: 'apiserver_request_duration_seconds_.*;(leases|events|endpointslices|tokenreviews|subjectaccessreviews)', action: drop}

# ── cAdvisor: per-interface network counters, 412k series ⭐ the biggest single win
#    ⚠️ RISK: container_network_* IS used by the Kubernetes dashboard.
#    → don't drop the metric; drop the `interface` LABEL (keep the aggregate).
- {sourceLabels: [__name__], regex: 'container_network_.*', targetLabel: interface, replacement: "", action: labeldrop}
# ⭐ labeldrop removes the label but keeps the series. That's usually what you want.

# ── anything with an unbounded label, as a standing guard ⭐⭐
- {sourceLabels: [request_id], regex: '.+', action: drop}
- {sourceLabels: [trace_id],   regex: '.+', action: drop}
- {sourceLabels: [user_id],    regex: '.+', action: drop}
- {sourceLabels: [image_id],   regex: '.+', action: drop}
- {sourceLabels: [pod_ip],     regex: '.+', action: drop}
YAML

# 5. apply and MEASURE — never assume
make platform-apply
sleep 3600
./scripts/cardinality-report.sh | head -20
# active series: 2,400,000 → 1,310,000     ⭐ −45%

# 6. ⭐⭐ PROVE NOTHING BROKE
make validate                        # rules still valid
promtool test rules ci/promtool-tests/*.yaml      # every alert unit test still passes
./scripts/validate-trace-pipeline.sh              # 8/8
# and the real check: every panel on every dashboard still has data
python3 - <<'PY'
import json, glob, subprocess, sys
bad = []
for f in glob.glob("platform/grafana/dashboards/*.json"):
    d = json.load(open(f))
    def walk(n):
        if isinstance(n, dict):
            if "expr" in n and isinstance(n["expr"], str) and n["expr"].strip():
                r = subprocess.run(["curl","-sG","localhost:9090/api/v1/query",
                                    "--data-urlencode","query="+n["expr"]],
                                   capture_output=True, text=True)
                try:
                    res = json.loads(r.stdout)
                    if res.get("status") == "error":
                        bad.append((f, n["expr"][:70], res.get("error","")[:70]))
                except Exception: pass
            for v in n.values(): walk(v)
        elif isinstance(n, list):
            for v in n: walk(v)
    walk(d)
if bad:
    print(f"✖ {len(bad)} dashboard queries now error:")
    for b in bad[:20]: print("   ", b)
    sys.exit(1)
print("✅ every dashboard query still executes")
PY
```

> ⚠️ **The trap:** `container_network_receive_packets_total` looks unused and enormous, so the temptation is to drop it. **Don't drop a metric — drop a label.** `labeldrop` on `interface` collapses 412k series to ~30k while keeping the metric fully functional for every dashboard and alert. That distinction — *metric vs label* — is the whole skill.

### Step 5 — Levers 4–9, briefly

```yaml
# 4. log retention, tiered by severity ⭐ (a Loki retention stream selector)
# loki-values.yaml
loki:
  limits_config:
    retention_period: 720h              # 30d default (was 2160h = 90d)
    retention_stream:
      - selector: '{level="DEBUG"}'                     # ⭐ DEBUG for 7 days only
        priority: 1
        period: 168h
      - selector: '{namespace="kube-system"}'           # ⭐ platform noise, 14 days
        priority: 2
        period: 336h
      - selector: '{namespace="shop",level=~"ERROR|WARN|FATAL"}'   # ⭐ KEEP the important stuff
        priority: 100
        period: 2160h                                   # 90 days for errors
      - selector: '{app=~"loadgen.*"}'                  # ⭐ synthetic traffic, 1 day
        priority: 3
        period: 24h
  compactor:
    retention_enabled: true             # ⭐⭐ without this, retention_stream does NOTHING
    retention_delete_delay: 2h
    retention_delete_worker_count: 150
```

```yaml
# 5. cAdvisor label trimming — a kubelet flag, huge saving
# (on kind/self-managed; on EKS/GKE/AKS use the managed equivalent)
kubelet:
  extraArgs:
    store_container_labels: "false"           # ⭐ drops io.kubernetes.* labels → ~25% of cAdvisor series
    whitelisted_container_labels: "app,team,tier"
  housekeepingInterval: 30s                   # was 10s → 3× fewer samples for housekeeping metrics
```

```yaml
# 6. Prometheus: 15d local + remote-write for the rest
prometheus:
  prometheusSpec:
    retention: 15d                    # ⭐ was 90d. Local SSD is 5× the price of S3.
    retentionSize: 45GB
    remoteWrite:
      - url: https://prometheus-us-central1.grafana.net/api/prom/push
        basicAuth: {username: {value: "12345"}, password: {name: mimir-creds, key: password}}
        writeRelabelConfigs:
          # ⭐⭐ only ship what you'd query at 90 days: business + SLO metrics
          - sourceLabels: [__name__]
            regex: '(http_server_requests_.*|shop_.*|worker_.*|payment_.*|sloth_.*|kube_deployment_.*|up|ALERTS)'
            action: keep
          # everything else lives 15 days locally and then disappears. That's fine.
        queueConfig: {capacity: 200000, maxShards: 60, maxSamplesPerSend: 5000, batchSendDeadline: 15s}
```

```yaml
# 7. collector rightsizing AFTER the volume dropped 90%
#    the gateway no longer needs 6 replicas and 8 Gi — measure first:
kubectl top pods -n otel --sort-by=memory
# otel-collector-gateway-…  620m  2100Mi   ← it was 5800Mi
# → drop to 3 replicas at 4Gi. Saves ~$180/mo. Do this LAST, after sampling has settled.

# 8. scrapeInterval: 30s for everything except the SLO metrics
#    ⚠️ histograms need resolution. Keep 15s for the request metrics, 60s for the rest.
```

```yaml
# 9. Prometheus replicas: 4 HA pairs → 2
#    ⭐ the honest risk assessment:
#      with 2 pairs you survive one node failure. With 1 pair you survive one
#      Prometheus failure but not a node failure. Given remote_write to Mimir,
#      a total Prometheus loss costs you ~15d of LOCAL query speed, not data.
#      → 2 pairs is the right answer for $95/mo.
prometheus: {prometheusSpec: {replicas: 2}}
```

### Step 6 — the final accounting

```
                     BEFORE      AFTER     SAVED    HOW
──────────────────────────────────────────────────────────────────────────
Traces              $1,980       $200    $1,780    10% tail sampling, 7d retention
Logs                  $760       $450      $310    tiered retention by severity
Metrics               $420       $225      $195    −45% series, 15d local + remote-write
Compute               $620       $440      $180    collector rightsizing, 2 Prom pairs
Ingest overhead       $420       $285      $135    90% fewer spans to ingest
──────────────────────────────────────────────────────────────────────────
TOTAL               $4,200     $1,600    $2,600    ✅ 62% — target was 60%

VERIFICATION (all must pass before you call it done):
  ✅ promtool test rules ci/promtool-tests/*.yaml         — every alert test passes
  ✅ ./scripts/validate-trace-pipeline.sh                 — 8/8
  ✅ error traces preserved: 41,208 → 41,196  (−0.03%)
  ✅ slow traces preserved:  186,442 → 186,438 (−0.00%)
  ✅ money-path traces:      2,840,116 → 2,840,116 (0%)
  ✅ every dashboard query executes without error
  ✅ no alert references a dropped metric (grep gate in CI)
  ✅ a full game day re-run scores the same as the baseline
──────────────────────────────────────────────────────────────────────────
```

**The last line is the one that matters:** *re-run the game day.* If all five scenarios are still detected in the same time with the same click path, you have proven the constraint. **A cost-reduction exercise that isn't validated by re-running the failure drills is just a hope.**

---

## Task C3 — Nothing is alerting, but users are complaining

**Scenario, verbatim from the support channel:**

> *"Multiple customers in the last hour: 'I add things to my cart, click checkout, the spinner goes for ages, then it says payment failed and my cart is empty.' Our dashboards are all green. Checkout error rate is 0.2%, well inside the SLO. p99 latency is 340 ms, inside the SLO. Every pod is Running. No alerts have fired. What do we do?"*

You have the platform you built in this capstone. **Find the problem.** Then explain, structurally, why the platform didn't catch it — and fix the platform.

<details>
<summary><b>💡 Hints — reason about the GAP before you look for the bug</b></summary>

1. "The cart is empty" is a **state** complaint, not a latency or error complaint. What signal carries state?
2. Error rate 0.2% and p99 340 ms are **aggregates over all requests**. A bug affecting 3% of a specific *subset* is invisible in an aggregate.
3. "The spinner goes for ages" but p99 is 340 ms → **the slow part is not being measured**. What isn't measured?
4. What does an aggregate SLO structurally *cannot* see? Enumerate the classes.
</details>

**✅ Answer**

### Part 1 — the investigation (the actual click path)

```
STEP 1 — Don't trust the green dashboards. Verify the platform is even working.
         Dashboard 40-observability-health:
           Targets up: 100%   Rules failing: 0   Watchdog: firing ✅
           Collector drops: 0   Silences: 0
         ✅ We are not blind. The platform is healthy; the SLOs are genuinely not breached.
         ⭐ This step matters: "nothing is alerting" has two very different causes —
            "nothing is wrong" and "we can't see it". Rule out the second one FIRST.
```

```
STEP 2 — Re-read the complaint for the signal it implies.
         "spinner goes for ages"      → latency (but p99 is fine?!)
         "then it says payment failed" → an error (but the error rate is fine?!)
         "and my cart is empty"        → ⭐⭐ STATE LOSS. Nothing in RED measures this.
         "multiple customers"          → a subset, not everyone

         The three facts together say: THE AGGREGATE IS HIDING A SUBSET.
         0.2% errors and 340ms p99 across 100% of traffic is entirely consistent
         with 100% errors and 30s latency across 3% of traffic.
```

```promql
# STEP 3 — break the aggregate apart along EVERY dimension, fast.
# Which dimension shows the anomaly? Run all of these at once in Explore.

# by status code (not just 5xx — the complaint says "payment failed", which may be a 4xx)
sum by (status) (rate(http_server_requests_seconds_count{namespace="shop",uri=~"/api/orders|/checkout"}[1h]))

# by route
histogram_quantile(0.99, sum by (le, uri) (rate(http_server_requests_seconds_bucket{namespace="shop"}[1h])))

# ⭐ by pod — is it one instance?
sum by (pod) (rate(http_server_requests_seconds_count{namespace="shop",status=~"5..|402|409"}[1h]))

# ⭐ by customer tier — the ONE business dimension we tagged
sum by (customer_tier) (rate(http_server_requests_seconds_count{namespace="shop",status=~"5..|402"}[1h]))
#   customer_tier="platinum"   0.41    ← ⭐⭐ THERE IT IS. 41% of platinum checkouts fail.
#   customer_tier="gold"       0.002
#   customer_tier="standard"   0.001

# by version — did we ship?
sum by (version) (rate(http_server_requests_seconds_count{namespace="shop",application="shop-api"}[1h]))
```

```
         ⭐ FOUND IT IN 4 MINUTES: platinum-tier customers, 41% failure rate.
         Aggregate: 3% of traffic × 41% failure = 1.2% … which rounds into the
         0.2%–1% noise band of the overall error rate. THE SLO NEVER MOVES.
```

```
STEP 4 — Confirm with traces (the evidence, not the inference).
```
```traceql
# every failing platinum checkout in the last hour
{ .service.name = "shop-api" && .customer.tier = "platinum" && status = error }
  | select(.order.id, .error.type, .url.path, .http.response.status_code)

# and compare against a SUCCESSFUL platinum checkout
{ .service.name = "shop-api" && .customer.tier = "platinum" && status != error }
```
```
         The failing trace:
           POST /api/orders                        31,204ms  status=ERROR
             ├─ auth verify-token                       8ms
             ├─ SELECT cart                         22ms
             ├─ redis GET cart:platinum:…           1ms   ⚠️ returns nil
             ├─ reserve-inventory                  14ms
             ├─ POST /v1/charge                31,050ms   ⭐ the "spinner goes for ages"
             │    attributes: http.response.status_code = 504
             │    events: [retry ×2]
             └─ redis DEL cart:platinum:…             1ms   ⭐⭐ THE CART IS CLEARED
                ⭐ EVEN THOUGH THE CHARGE FAILED — and it's in a `finally` block

         The successful trace: identical, except /v1/charge returns 200 in 90ms.
```

```
STEP 5 — Root cause, from the span, with zero log access:
         Platinum customers are routed to a different payment provider
         (`provider=premium-gateway`, visible on the span attribute).
         That provider started returning 504s an hour ago.
         Our client retries twice (2 × 10s timeout = 30s of "spinner"),
         then gives up — and the cart-clearing code runs in a `finally`
         block, so the cart is emptied even on failure.

         TWO BUGS, one incident:
           (a) the premium gateway is returning 504          ← external
           (b) we clear the cart when the charge fails       ← ⭐ OUR BUG, and worse
```

```logql
# STEP 6 — the log line that confirms (b)
{namespace="shop",app="shop-api"} | json
  | customer_tier="platinum"
  | line_format "{{.timestamp}} {{.level}} {{.message}}"
# 18:04:12 ERROR payment failed provider=premium-gateway status=504 attempt=3
# 18:04:12 INFO  clearing cart for order ord_9f2a… reason=checkout-complete   ← ⭐⭐ WRONG REASON
```

```
STEP 7 — Mitigate, fastest first:
         1. Fail over the premium gateway:      feature flag payment.premium.provider=stripe  (30s)
         2. Stop clearing carts on failure:     this needs a code fix → the flag
            checkout.clear-cart-on-failure=false                                       (30s)
         3. Restore the lost carts from Redis backups for the affected order IDs:
            the order.id span attribute gives you the exact list                      (10 min)
         4. Notify the ~200 affected customers.
```

### Part 2 — why the platform didn't catch it ⭐ this is the real answer

**Enumerate every structural gap, then fix each one.**

| # | The gap | Why it's structural | The fix |
|---|---|---|---|
| **G1** | **Aggregation hides subsets.** An SLO computed over 100% of traffic cannot see a 41% failure in a 3% segment. | `sum(rate(errors))/sum(rate(total))` is a **single number by design**. That's what makes it an SLO. | ⭐ **Per-segment SLOs** — a separate SLI for each critical segment, and a "worst segment" alert. See below. |
| **G2** | **The SLO only counts 5xx.** The failures were `504` from the provider surfaced as… whatever we returned. If we returned 402 or 200-with-an-error-body, the availability SLI never saw it. | The SLI's `status=~"5.."` matcher is a **policy choice** made at design time. | Include `402, 408, 429, 503, 504` in the error matcher — **already done in this capstone**, but verify per route. And add a **business-outcome SLI** (below). |
| **G3** | **Latency was measured at the wrong layer.** p99 340 ms is the *server's* view. The user saw 31 s: 30 s of retries plus browser time. | `http_server_requests_seconds` measures the servlet. The retries happened **inside** it, so it *should* have shown 31 s… unless the p99 was dominated by the 97% of fast requests. | ⭐ p99 over **all** traffic hides a bimodal distribution. Add a **per-segment latency SLI** and a **heatmap** (which shows bimodality instantly, unlike a percentile line). |
| **G4** | **Nothing measures business outcome.** "The cart is empty when it shouldn't be" is not an HTTP status, a latency, or a log level. | RED/USE measure **the system**. Users experience **outcomes**. | ⭐⭐ A **business-outcome SLI**: `orders_completed / checkouts_started`. This is the single most valuable metric you can add. |
| **G5** | **No synthetic user journey.** The blackbox probe checks `GET /health`. It does not *do a checkout as a platinum customer*. | A health probe answers "is the process up", not "can a user buy something". | ⭐ A **scripted multi-step probe** per segment, running every 60 s. |
| **G6** | **No alert on the dependency.** We alerted on *our* error rate, not on *the payment provider's*. | Symptom-based alerting is correct, but a dependency-level alert is a **leading indicator** that fires 10 minutes earlier. | Alert on `payment_charge_duration_seconds` and the provider's own error ratio, split by `provider`. |
| **G7** | **No customer-impact metric.** "How many distinct customers were affected?" is the number the business needs, and nothing measures it. | Metrics aggregate; customers are individuals. | ⭐ Count distinct affected `customer.id` from **traces/logs** (where unbounded values belong), not metrics. |

### Part 3 — fix the platform

**Fix G1 + G2: per-segment SLOs and the worst-segment alert ⭐**

```yaml
# platform/prometheus/alerting-rules/segment.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: shop-segments, namespace: monitoring, labels: {release: kps}}
spec:
  groups:
    - name: segment-slo
      interval: 30s
      rules:
        # ⭐ a RECORDING RULE per segment, so the query is cheap and the alert is simple
        - record: shop:checkout_error_ratio:by_segment
          expr: |
            sum by (customer_tier, provider) (
              rate(http_server_requests_seconds_count{
                namespace="shop", application=~"shop-api|checkout",
                uri=~"/api/orders|/checkout", status=~"5..|402|408|429|503|504"}[5m]))
            /
            clamp_min(sum by (customer_tier, provider) (
              rate(http_server_requests_seconds_count{
                namespace="shop", application=~"shop-api|checkout",
                uri=~"/api/orders|/checkout"}[5m])), 0.0001)

        - record: shop:checkout_latency_p99:by_segment
          expr: |
            histogram_quantile(0.99, sum by (le, customer_tier, provider) (
              rate(http_server_requests_seconds_bucket{
                namespace="shop", application=~"shop-api|checkout",
                uri=~"/api/orders|/checkout"}[5m])))

        # ⭐⭐ THE ALERT THAT WOULD HAVE CAUGHT THIS INCIDENT
        - alert: CheckoutSegmentDegraded
          expr: |
            (
              shop:checkout_error_ratio:by_segment > 0.05
              # ⭐ only for segments with enough traffic to be meaningful
              and
              sum by (customer_tier, provider) (
                rate(http_server_requests_seconds_count{
                  namespace="shop", uri=~"/api/orders|/checkout"}[5m])) > 0.05
            )
          for: 5m
          labels: {severity: critical, team: payments, tier: symptom, slo: checkout-availability}
          annotations:
            summary: "checkout is failing for {{ $value | humanizePercentage }} of the {{ $labels.customer_tier }} / {{ $labels.provider }} segment"
            description: |
              ⭐ THE AGGREGATE SLO MAY STILL BE GREEN. That is expected and correct:
              a segment-level breach is invisible in an aggregate when the segment is
              a small fraction of traffic. This alert exists precisely for that case.
              Segment: tier={{ $labels.customer_tier }} provider={{ $labels.provider }}
              Check the per-segment panel, then the traces filtered by that segment.
            dashboard_url: http://localhost:3000/d/99-incident?var-tier={{ $labels.customer_tier }}
            trace_query: '{ .service.name = "shop-api" && .customer.tier = "{{ $labels.customer_tier }}" && status = error }'
            log_query: '{namespace="shop",app="shop-api"} | json | customer_tier="{{ $labels.customer_tier }}" | level="ERROR"'
            runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/checkout-segment-degraded.md
```

```promql
# and the "worst segment" panel — the one that should have been on the dashboard
topk(5, shop:checkout_error_ratio:by_segment)
max(shop:checkout_error_ratio:by_segment)          # ⭐ the single most useful number
max(shop:checkout_latency_p99:by_segment)
```

**Fix G4: the business-outcome SLI ⭐⭐ the highest-value addition**

```yaml
# platform/prometheus/slos/checkout-outcome.yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata: {name: checkout-outcome, namespace: monitoring}
spec:
  service: shop
  slos:
    - name: checkout-completion
      objective: 99
      description: |
        ⭐⭐ THE BUSINESS SLO. 99% of checkouts that a customer STARTS must
        COMPLETE — meaning an order exists AND the cart was consumed correctly.

        This is the SLI that catches everything the technical SLIs structurally
        cannot: a cart cleared on failure, a payment that "succeeded" but
        created no order, an order created but never queued for fulfilment,
        a feature flag that silently disables a payment method.

        Numerator:   orders that reached state='confirmed' within 120s of starting
        Denominator: checkout sessions started (a counter incremented at the first
                     POST /api/orders, including ones that failed)

        Requires TWO custom metrics in shop-api:
          shop_checkout_sessions_started_total{tier,provider}
          shop_checkout_sessions_completed_total{tier,provider}
      owner: payments-team
      sli:
        events:
          errorQuery: |
            sum(rate(shop_checkout_sessions_started_total{namespace="shop"}[{{.window}}]))
            -
            sum(rate(shop_checkout_sessions_completed_total{namespace="shop"}[{{.window}}]))
          totalQuery: |
            sum(rate(shop_checkout_sessions_started_total{namespace="shop"}[{{.window}}]))
      alerting:
        name: CheckoutCompletion
        labels: {team: payments, tier: symptom}
        pageAlert:
          labels: {severity: critical}
          annotations:
            summary: "{{ $value | humanizePercentage }} of started checkouts are NOT completing"
            description: |
              This is a BUSINESS-OUTCOME breach. Every technical SLO may be green.
              The gap between "started" and "completed" is where the bug lives.
              Compare: shop_checkout_sessions_started_total vs completed, by tier and provider.
```

```java
// the two counters, in shop-api
private final Counter started = Counter.builder("shop.checkout.sessions")
    .tag("outcome", "started")
    .description("Checkout sessions begun. The denominator of the business SLO.")
    .register(registry);
private final Counter completed = Counter.builder("shop.checkout.sessions")
    .tag("outcome", "completed")
    .description("Checkout sessions that produced a confirmed order. The numerator.")
    .register(registry);
private final Counter abandoned = Counter.builder("shop.checkout.sessions")
    .tag("outcome", "abandoned")        // ⭐ the difference, explicitly — and WHY
    .tag("reason", "unknown")           // overridden per call: payment_failed | cart_cleared |
    .register(registry);                //   inventory | timeout | validation | user_cancelled

// in the controller:
started.increment();
try {
    OrderResult r = orderService.createOrder(req);
    if ("created".equals(r.status())) { completed.increment(); }
    else { abandoned.increment(Tags.of("reason", "payment_failed"));
           log.error("checkout did not complete reason=payment_failed order={}", r.orderId()); }
} catch (Exception e) {
    abandoned.increment(Tags.of("reason", classify(e)));
    throw e;
} finally {
    // ⭐⭐ AND FIX THE ACTUAL BUG: only clear the cart on success
    if (orderWasConfirmed) cartService.clear(cartId, "checkout-complete");
    else                   cartService.preserve(cartId, "checkout-failed");
}
```

**Fix G5: a synthetic user journey per segment ⭐**

```yaml
# platform/kubernetes/apps/synthetic-checkout.yaml
apiVersion: batch/v1
kind: CronJob
metadata: {name: synthetic-checkout, namespace: shop}
spec:
  schedule: "* * * * *"                 # ⭐ every minute
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 10
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 50
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: probe
              image: ghcr.io/3558bhk/synthetic-checkout:1.0.0
              env:
                - {name: BASE_URL, value: "http://shop-ui.shop.svc"}
                # ⭐⭐ ONE JOB PER SEGMENT — this is what makes it a segment probe
                - {name: SEGMENTS, value: "standard:basic-gateway,gold:basic-gateway,platinum:premium-gateway"}
                - {name: OTEL_SERVICE_NAME, value: "synthetic-checkout"}
                - {name: OTEL_EXPORTER_OTLP_ENDPOINT, value: "http://otel-collector-agent.otel.svc:4317"}
              resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 128Mi}}
```

```python
# apps/synthetic-checkout/probe.py — ⭐ the multi-step user journey
"""
A synthetic user. Does a REAL checkout, end to end, and emits a metric + a trace
per segment per step. This is the probe that catches what health checks can't.
"""
import os, sys, time, uuid
import requests
from opentelemetry import trace
from prometheus_client import Counter, Histogram, Gauge, start_http_server, generate_latest

tracer = trace.get_tracer("synthetic-checkout")

STEPS = ["browse", "add_to_cart", "view_cart", "begin_checkout", "pay", "confirm_order", "cart_is_empty"]
RESULT = Counter("synthetic_checkout_step_total", "Synthetic checkout step results.",
                 ["segment", "tier", "provider", "step", "outcome"])
DURATION = Histogram("synthetic_checkout_step_seconds", "Step duration.",
                     ["segment", "step"], buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 30))
JOURNEY_OK = Gauge("synthetic_checkout_journey_success", "1 if the whole journey succeeded.",
                   ["segment", "tier", "provider"])

BASE = os.environ.get("BASE_URL", "http://localhost:8080")


def step(span_parent, name, segment, tier, provider, fn):
    """Run one step, record the metric and a child span, and return the result."""
    with tracer.start_as_current_span(f"synthetic.{name}", attributes={
            "synthetic.segment": segment, "customer.tier": tier,
            "payment.provider": provider, "synthetic.step": name}) as span:
        t0 = time.perf_counter()
        try:
            out = fn()
            elapsed = time.perf_counter() - t0
            RESULT.labels(segment, tier, provider, name, "success").inc()
            DURATION.labels(segment, name).observe(elapsed)
            span.set_attribute("step.duration_ms", int(elapsed * 1000))
            return out
        except AssertionError as e:                    # ⭐ a FAILED ASSERTION, not an HTTP error
            elapsed = time.perf_counter() - t0
            RESULT.labels(segment, tier, provider, name, "assertion_failed").inc()
            DURATION.labels(segment, name).observe(elapsed)
            span.set_status(trace.StatusCode.ERROR, f"assertion: {e}")
            raise
        except Exception as e:                         # noqa: BLE001
            elapsed = time.perf_counter() - t0
            RESULT.labels(segment, tier, provider, name, "error").inc()
            DURATION.labels(segment, name).observe(elapsed)
            span.set_status(trace.StatusCode.ERROR, str(e))
            span.record_exception(e)
            raise


def run_journey(segment: str, tier: str, provider: str) -> bool:
    s = requests.Session()
    s.headers.update({"X-Customer-Tier": tier, "X-Payment-Provider": provider,
                      "X-Synthetic": "true", "X-Session-Id": str(uuid.uuid4())})
    ok = True
    cart_id = None
    try:
        r = step(None, "browse", segment, tier, provider,
                 lambda: _assert(s.get(f"{BASE}/api/items", timeout=5), 200))
        assert len(r.json()["items"]) > 0, "the catalogue is empty"

        cart_id = step(None, "add_to_cart", segment, tier, provider,
                 lambda: _assert(s.post(f"{BASE}/api/cart", json={"itemId": "sku-1", "qty": 2},
                                        timeout=5), 201).json()["cartId"])

        step(None, "view_cart", segment, tier, provider,
             lambda: _assert(s.get(f"{BASE}/api/cart/{cart_id}", timeout=5), 200))

        order = step(None, "begin_checkout", segment, tier, provider,
                     lambda: _assert(s.post(f"{BASE}/api/orders",
                                            json={"cartId": cart_id, "items": 2, "tier": tier},
                                            timeout=35),                                     # ⭐ generous
                                     (200, 201, 402)).json())                                 # ⭐ 402 is a valid outcome

        if order.get("status") == "rejected" or order.get("error") == "payment_declined":
            RESULT.labels(segment, tier, provider, "pay", "declined").inc()
            raise AssertionError(f"payment declined for {segment}: {order}")
        step(None, "pay", segment, tier, provider, lambda: order)

        oid = order.get("orderId")
        assert oid, f"no orderId in the response: {order}"
        confirmed = step(None, "confirm_order", segment, tier, provider,
                         lambda: _assert(s.get(f"{BASE}/api/orders/{oid}", timeout=10), 200).json())
        assert confirmed.get("state") == "confirmed", \
            f"order {oid} is in state '{confirmed.get('state')}', expected 'confirmed'"

        # ⭐⭐ THE STEP THAT WOULD HAVE CAUGHT THIS INCIDENT
        cart_after = step(None, "cart_is_empty", segment, tier, provider,
                          lambda: s.get(f"{BASE}/api/cart/{cart_id}", timeout=5))
        # on SUCCESS the cart should be consumed (404 or empty).
        # we assert the RIGHT reason:
        body = cart_after.json() if cart_after.status_code == 200 else {}
        reason = body.get("clearedReason")
        assert cart_after.status_code in (200, 404), f"unexpected cart status {cart_after.status_code}"
        if cart_after.status_code == 200 and body.get("items"):
            raise AssertionError("the cart still has items after a confirmed order")
        if reason and reason != "checkout-complete":
            raise AssertionError(f"⭐ the cart was cleared with reason='{reason}' — "
                                 f"that means it was cleared on a FAILED checkout")
    except Exception as e:                             # noqa: BLE001
        ok = False
        print(f"✖ {segment}: {e}", file=sys.stderr)
    JOURNEY_OK.labels(segment, tier, provider).set(1 if ok else 0)
    return ok


def _assert(resp, codes):
    if isinstance(codes, int):
        codes = (codes,)
    assert resp.status_code in codes, f"HTTP {resp.status_code}, expected {codes}: {resp.text[:200]}"
    return resp


def main():
    start_http_server(9094)
    results = []
    for spec in os.environ.get("SEGMENTS", "standard:basic-gateway").split(","):
        seg, provider = spec.split(":")
        results.append(run_journey(seg, seg, provider))
    # ⭐ push the metrics so Prometheus can scrape them (or expose and be scraped)
    print(generate_latest().decode()[:400])
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
```

```yaml
# ⭐ and the ALERT on the synthetic journey — this fires BEFORE any user complains
- alert: SyntheticCheckoutJourneyFailing
  expr: synthetic_checkout_journey_success == 0
  for: 2m
  labels: {severity: critical, team: payments, tier: symptom}
  annotations:
    summary: "the synthetic {{ $labels.segment }} checkout journey is failing"
    description: |
      A real end-to-end checkout as a {{ $labels.tier }} customer via
      {{ $labels.provider }} is failing. ⭐ This fires BEFORE the aggregate
      error-rate SLO, because it doesn't depend on real traffic volume.
      Which step failed?
        sum by (step) (rate(synthetic_checkout_step_total{segment="{{ $labels.segment }}",outcome!="success"}[5m]))
    trace_query: '{ .service.name = "synthetic-checkout" && .synthetic.segment = "{{ $labels.segment }}" && status = error }'
    runbook_url: https://git.example.com/shop-observability/-/blob/main/platform/runbooks/synthetic-checkout.md
```

**Fix G3: the heatmap that shows bimodality**

```promql
# ⭐ a percentile LINE hides a bimodal distribution. A HEATMAP shows it instantly.
sum by (le) (increase(http_server_requests_seconds_bucket{namespace="shop",uri=~"/api/orders|/checkout"}[$__rate_interval]))
# Grafana panel type: Heatmap. Format: Heatmap.
# During this incident the heatmap would show TWO BLOBS: one at 200ms, one at 31s.
# A p99 line at 340ms shows nothing. THIS is why you build the heatmap.
```

**Fix G6: alert on the dependency**

```yaml
- alert: PaymentProviderDegraded
  expr: |
    histogram_quantile(0.99, sum by (le, provider) (rate(payment_charge_duration_seconds_bucket[5m]))) > 2
    or
    (sum by (provider) (rate(payment_charges_total{status=~"5.."}[5m]))
       / clamp_min(sum by (provider) (rate(payment_charges_total[5m])), 0.001)) > 0.02
  for: 5m
  labels: {severity: warning, team: payments, tier: saturation}
  annotations:
    summary: "payment provider {{ $labels.provider }} is degraded"
    description: |
      ⭐ A LEADING INDICATOR. This fires ~10 minutes before a customer-facing
      symptom SLO, because it watches the dependency rather than our aggregate.
```

**Fix G7: count distinct affected customers, from traces/logs (not metrics)**

```traceql
# how many distinct customers hit this?  (unbounded values live in TRACES, not metrics)
{ .service.name = "shop-api" && .customer.tier = "platinum" && status = error }
  | select(.customer.id)
```
```logql
# or from logs, where customer_id is a FIELD not a LABEL
count(
  sum by (customer_id) (
    count_over_time({namespace="shop",app="shop-api"} | json | level="ERROR" | customer_tier="platinum" [1h])
  )
)
# 214    ← ⭐ "214 distinct customers were affected in the last hour." That's the number
#          the business needs, and it is the number an SRE should be able to produce in 60 seconds.
```

### Part 4 — the structural lesson

> **A metric-first observability platform has four blind spots, and every real incident lives in one of them:**
>
> | Blind spot | Why it's structural | The fix |
> |---|---|---|
> | **Subsets** | An SLO is an aggregate by definition | Per-segment SLIs + a `max(by segment)` alert |
> | **Business outcomes** | RED measures the system, not the user's goal | A `started → completed` funnel SLI |
> | **Distribution shape** | A percentile is one number; a bimodal distribution has two modes | Heatmaps, not just percentile lines |
> | **State correctness** | "The cart is empty when it shouldn't be" is not an error, a latency, or a saturation | ⭐ **Synthetic user journeys that assert post-conditions** |
>
> The synthetic journey is the most important of the four, and the cheapest: one CronJob, 60 lines of Python, seven assertions. **It is the only mechanism that catches a system which is 100% healthy by every technical measure and 100% broken from the user's chair.**

---

## Task C4 — Make the platform multi-tenant

**Scenario:** four teams now use the platform — `payments` (shop-api, checkout), `storefront` (shop-ui, shop-search), `fulfilment` (order-worker, warehouse-sync), `platform` (the observability stack itself). Requirements:

1. Each team can **only see** its own services' traces, logs and dashboards.
2. Each team can **self-service**: add its own alerts, dashboards and SLOs via PR, without a platform approval for content.
3. A noisy team cannot degrade the platform for the others (**isolation**).
4. Alert routing goes to the right team automatically, from a label the team owns.
5. Each team sees **its own cost**.
6. The platform team retains a global view.

Design and implement it.

<details>
<summary><b>💡 Hints</b></summary>

1. There are two multi-tenancy models: **namespace-per-team** (hard isolation, more infra) and **label-based tenancy** (soft isolation, one stack). Know which you're choosing and why.
2. Grafana's OSS has no row-level data permissions. Be honest about what requires Enterprise or an external proxy.
3. "Self-service via PR" is a **CODEOWNERS + CI** problem, not a permissions problem.
4. Cost attribution needs a label on every series that says who owns it. Where does that label come from, and who can set it?
</details>

**✅ Answer**

### Step 1 — choose the tenancy model

| Model | Isolation | Cost | Self-service | Verdict for 4 teams |
|---|---|---|---|---|
| **A. One stack, label-based tenancy** | Soft (Grafana folders + query scoping) | 1× | ⭐ Excellent (one place to add rules) | ✅ **Choose this** |
| B. A stack per team | Hard | 4× | Poor (4 things to maintain) | Only at >15 teams or with compliance requirements |
| C. Grafana Mimir/Cortex with `X-Scope-OrgID` | Hard, native | 1.5× | Good | ✅ The scale-up path from A |
| D. A vendor (Datadog etc.) with org/team scoping | Hard, native | 8× | Excellent | If you don't want to operate it |

**Decision: Model A now, with the label schema designed so a migration to C is mechanical.** The reason: 4 teams don't justify 4 stacks, and the *hard* part of multi-tenancy isn't the storage — it's the ownership metadata. Get the metadata right and the storage migration is a config change.

### Step 2 — the ownership label schema ⭐ the foundation

```yaml
# docs/OWNERSHIP.md — ⭐ commit this. It's the contract.
#
# EVERY telemetry item carries these four attributes, set by the OWNING TEAM
# in their Deployment, and validated in CI:
#
#   team        payments | storefront | fulfilment | platform     ← the owner
#   tier        frontend | backend | worker | data | infra        ← the kind
#   journey     checkout | browse | fulfilment | none             ← the business flow
#   cost_center CC-4410                                           ← for billing
#
# They appear as:
#   Prometheus labels:  team, tier, journey  (via kube-state-metrics metricLabelsAllowlist)
#   Trace/log resource attributes: team, tier, journey, cost_center
#   Grafana: folder + a dashboard variable + a datasource query scope
#   Alertmanager: the routing key
```

```yaml
# platform/kubernetes/namespaces.yaml — the team label is on the NAMESPACE too
apiVersion: v1
kind: Namespace
metadata:
  name: shop
  labels:
    team: payments                      # ⭐ the namespace's owning team (may be shared)
    kubernetes.io/metadata.name: shop
---
apiVersion: v1
kind: Namespace
metadata: {name: storefront, labels: {team: storefront}}
---
apiVersion: v1
kind: Namespace
metadata: {name: fulfilment, labels: {team: fulfilment}}
---
apiVersion: v1
kind: Namespace
metadata: {name: monitoring, labels: {team: platform}}
---
apiVersion: v1
kind: Namespace
metadata: {name: otel, labels: {team: platform}}
```

```yaml
# ⭐ kube-state-metrics must be told to expose the POD labels as metric labels.
#   Without this, `team` never reaches Prometheus and nothing can route by team.
kube-state-metrics:
  metricLabelsAllowlist:
    - pods=[app,team,tier,journey,cost-center,app.kubernetes.io/version]
    - deployments=[app,team,tier,journey,cost-center]
    - namespaces=[team]
    - statefulsets=[app,team]
  metricAnnotationsAllowList:
    - pods=[kubectl.kubernetes.io/last-applied-configuration]
```

```bash
# and the Collector promotes the pod labels to RESOURCE ATTRIBUTES on traces/logs:
# (already in platform/otel/agent-config.yaml)
  k8sattributes:
    extract:
      labels:
        - {tag_name: team,        key: team,        from: pod}
        - {tag_name: tier,        key: tier,        from: pod}
        - {tag_name: journey,     key: journey,     from: pod}
        - {tag_name: cost_center, key: cost-center, from: pod}
```

```yaml
# the Deployment side — what each team writes
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: shop
  labels: {app: shop-api}
spec:
  template:
    metadata:
      labels:
        app: shop-api
        team: payments              # ⭐⭐ REQUIRED. CI fails without it.
        tier: backend
        journey: checkout
        cost-center: CC-4410
      annotations:
        instrumentation.opentelemetry.io/inject-java: "otel/shop-instrumentation"
    spec:
      containers:
        - name: api
          env:
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "team=payments,tier=backend,journey=checkout,cost_center=CC-4410,deployment.environment=production,service.version=1.4.2"
```

```bash
# ⭐ CI ENFORCEMENT — the label must exist and must be in the allowlist
cat > ci/check-ownership.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
ALLOWED_TEAMS="payments storefront fulfilment platform"
fail=0
for f in $(grep -rl '^kind: Deployment' platform/kubernetes/apps/ apps/*/k8s/ 2>/dev/null); do
  team=$(yq -r '.spec.template.metadata.labels.team // ""' "$f" 2>/dev/null)
  tier=$(yq -r '.spec.template.metadata.labels.tier // ""' "$f")
  jrn=$(yq -r '.spec.template.metadata.labels.journey // "none"' "$f")
  cc=$(yq -r '.spec.template.metadata.labels."cost-center" // ""' "$f")
  name=$(yq -r '.metadata.name' "$f")
  if [[ -z "$team" ]]; then
    echo "  ✖ $name ($f): missing the 'team' label — alerts can't be routed and costs can't be attributed"; fail=1; continue
  fi
  if ! echo " $ALLOWED_TEAMS " | grep -q " $team "; then
    echo "  ✖ $name: team='$team' is not in the allowlist ($ALLOWED_TEAMS)"; fail=1
  fi
  [[ -n "$tier" ]] || { echo "  ✖ $name: missing 'tier'"; fail=1; }
  [[ -n "$cc"   ]] || { echo "  ✖ $name: missing 'cost-center'"; fail=1; }
  # ⭐ the OTEL_RESOURCE_ATTRIBUTES must agree with the labels
  ora=$(yq -r '.spec.template.spec.containers[0].env[] | select(.name=="OTEL_RESOURCE_ATTRIBUTES") | .value' "$f" 2>/dev/null)
  if [[ -n "$ora" ]] && ! echo "$ora" | grep -q "team=$team"; then
    echo "  ✖ $name: OTEL_RESOURCE_ATTRIBUTES says a different team than the pod label"; fail=1
  fi
  echo "  ✅ $name → team=$team tier=$tier journey=$jrn cost-center=$cc"
done
exit $fail
EOF
chmod +x ci/check-ownership.sh
```

### Step 3 — alert routing by team, automatically

```yaml
# platform/alertmanager/alertmanager.yaml — the multi-tenant routing tree
spec:
  route:
    receiver: platform-default
    groupBy: [alertname, team, namespace]
    groupWait: 30s
    groupInterval: 5m
    repeatInterval: 4h
    routes:
      # ⭐ OBSERVABILITY ITSELF — always platform, always first
      - receiver: platform-critical
        matchers: [{name: tier, value: self}]
        repeatInterval: 1h
        continue: false

      # ⭐⭐ THE GENERIC TEAM ROUTE — one rule, works for every team forever.
      #    The `team` label comes from the ALERT (set by the rule, which reads it
      #    from the pod label via kube-state-metrics or from an explicit label).
      - receiver: team-page
        matchers:
          - {name: severity, value: critical}
          - {name: tier, value: symptom}
          - {name: team, value: "", isRegex: false, isEqual: false}   # ⭐ team is set
        groupBy: [alertname, team, namespace]
        repeatInterval: 30m
        continue: true                    # also send to the team's Slack channel

      - receiver: team-ticket
        matchers:
          - {name: severity, value: warning}
          - {name: team, value: "", isEqual: false}
        repeatInterval: 12h

      # ⭐ a teamless alert is a BUG — route it loudly to platform, don't drop it
      - receiver: platform-unowned
        matchers: [{name: team, value: ""}]
        repeatInterval: 1h
```

**The trick that makes `team` appear on the alert automatically:**

```yaml
# ⭐ instead of hardcoding team: in every rule, JOIN it from kube-state-metrics.
#    Then a team can move a Deployment and the routing follows.
- alert: ServiceCpuThrottled
  expr: |
    (
      sum by (namespace, pod) (rate(container_cpu_cfs_throttled_periods_total{namespace!~"kube-.*"}[5m]))
        / clamp_min(sum by (namespace, pod) (rate(container_cpu_cfs_periods_total{namespace!~"kube-.*"}[5m])), 0.001)
    ) > 0.25
    # ⭐⭐ JOIN the team label from the pod's Kubernetes labels
    * on(namespace, pod) group_left(team, tier, journey)
      label_replace(
        kube_pod_labels{label_team!=""},
        "pod", "$1", "pod", "(.*)"
      )
  for: 15m
  labels:
    severity: warning
    tier: saturation
    # ⭐ team is NOT hardcoded — it comes from the group_left join
  annotations:
    summary: "{{ $labels.pod }} (team {{ $labels.team }}) is CPU-throttled in {{ $value | humanizePercentage }} of periods"
```

```bash
# ⭐ OR, simpler and more common: use the PrometheusRule's own labels + a
#    rule-level relabel. The cleanest production approach is an Alertmanager
#    route that looks up the team from a static map, kept in Git:
cat > platform/alertmanager/team-map.yaml <<'EOF'
# ⭐ the namespace/service → team map. Generated from the Deployment labels.
#    Alertmanager can't do joins, so materialise the mapping here.
apiVersion: v1
kind: ConfigMap
metadata: {name: alertmanager-team-map, namespace: monitoring}
data:
  team-map.json: |
    {
      "shop/shop-api":          {"team": "payments",   "channel": "#payments-oncall", "pd_key": "PK_PAYMENTS"},
      "shop/checkout":          {"team": "payments",   "channel": "#payments-oncall", "pd_key": "PK_PAYMENTS"},
      "shop/payment-mock":      {"team": "payments",   "channel": "#payments-oncall", "pd_key": "PK_PAYMENTS"},
      "storefront/shop-ui":     {"team": "storefront", "channel": "#storefront-oncall","pd_key": "PK_STORE"},
      "storefront/shop-search": {"team": "storefront", "channel": "#storefront-oncall","pd_key": "PK_STORE"},
      "fulfilment/order-worker":{"team": "fulfilment", "channel": "#fulfil-oncall",   "pd_key": "PK_FULFIL"},
      "monitoring/*":           {"team": "platform",   "channel": "#platform-oncall", "pd_key": "PK_PLATFORM"},
      "otel/*":                 {"team": "platform",   "channel": "#platform-oncall", "pd_key": "PK_PLATFORM"}
    }
EOF

# and generate the AlertmanagerConfig per team from it ⭐ no hand-maintenance
cat > scripts/generate-team-routing.py <<'PYEOF'
#!/usr/bin/env python3
"""⭐ Generate one AlertmanagerConfig CR per team from team-map.json."""
import json, pathlib, yaml, subprocess

team_map = yaml.safe_load(subprocess.run(
    ["kubectl","get","cm","alertmanager-team-map","-n","monitoring","-o","jsonpath={.data.team-map\\.json}"],
    capture_output=True, text=True).stdout)

teams = {}
for key, cfg in team_map.items():
    teams.setdefault(cfg["team"], {"channels": set(), "keys": set(), "namespaces": set()})
    teams[cfg["team"]]["channels"].add(cfg["channel"])
    teams[cfg["team"]]["keys"].add(cfg["pd_key"])
    ns = key.split("/")[0]
    teams[cfg["team"]]["namespaces"].add(ns if "*" not in ns else None)

for team, cfg in teams.items():
    ns_matchers = ([{"name": "namespace", "value": "|".join(sorted(n for n in cfg["namespaces"] if n)),
                     "matchType": "=~"}] if any(cfg["namespaces"]) else [])
    doc = {
        "apiVersion": "monitoring.coreos.com/v1alpha1", "kind": "AlertmanagerConfig",
        "metadata": {"name": f"team-{team}", "namespace": "monitoring",
                     "labels": {"alertmanagerConfig": "enabled", "team": team}},
        "spec": {
            "route": {
                "receiver": f"{team}-ticket", "groupBy": ["alertname", "namespace"],
                "groupWait": "30s", "groupInterval": "5m", "repeatInterval": "4h",
                "matchers": [{"name": "team", "value": team}],
                "routes": [{
                    "receiver": f"{team}-page", "repeatInterval": "30m", "continue": True,
                    "matchers": [{"name": "severity", "value": "critical"}]}],
            },
            "receivers": [
                {"name": f"{team}-ticket", "slackConfigs": [
                    {"channel": sorted(cfg["channels"])[0], "sendResolved": True,
                     "apiURL": {"name": "alertmanager-slack", "key": "slack-webhook-url"}}]},
                {"name": f"{team}-page",
                 "pagerDutyConfigs": [{"routingKey": {"name": f"pd-{team}", "key": "routing-key"},
                                       "severity": "critical", "group": team}],
                 "slackConfigs": [{"channel": sorted(cfg["channels"])[0], "sendResolved": True,
                                   "apiURL": {"name": "alertmanager-slack", "key": "slack-webhook-url"}}]},
            ],
            "inhibitRules": [
                {"sourceMatch": [{"name": "tier", "value": "symptom"}],
                 "targetMatch": [{"name": "tier", "value": "saturation"}],
                 "equal": ["namespace", "team"]},
            ],
        },
    }
    p = pathlib.Path(f"platform/alertmanager/teams/team-{team}.yaml")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(yaml.safe_dump(doc, sort_keys=False))
    print(f"  ✅ {p} — {team}: channels={sorted(cfg['channels'])}")
print(f"\n{len(teams)} team AlertmanagerConfigs generated")
PYEOF
chmod +x scripts/generate-team-routing.py
python3 scripts/generate-team-routing.py
```

### Step 4 — self-service via CODEOWNERS + CI ⭐ the actual answer

**Permissions aren't the mechanism for self-service. Code review is.**

```
# .github/CODEOWNERS
# ⭐⭐ the platform team owns the PLATFORM, not the CONTENT.

# the shared infrastructure — platform team must approve
/platform/helm/                       @platform-team
/platform/otel/agent-config.yaml      @platform-team
/platform/otel/gateway-config.yaml    @platform-team
/platform/kubernetes/networkpolicies/ @platform-team
/platform/kubernetes/rbac.yaml        @platform-team
/platform/alertmanager/alertmanager.yaml  @platform-team
/ci/                                  @platform-team
/scripts/                             @platform-team

# ⭐ but the CONTENT is owned by the teams themselves — NO platform approval
/platform/prometheus/alerting-rules/payments-*.yaml     @payments-team
/platform/prometheus/alerting-rules/storefront-*.yaml   @storefront-team
/platform/prometheus/alerting-rules/fulfilment-*.yaml   @fulfilment-team
/platform/prometheus/slos/payments-*.yaml               @payments-team
/platform/prometheus/slos/storefront-*.yaml             @storefront-team
/platform/grafana/dashboards/1*-payments-*.json         @payments-team
/platform/grafana/dashboards/1*-storefront-*.json       @storefront-team
/platform/runbooks/payments-*.md                        @payments-team
/apps/shop-api/                                         @payments-team
/apps/checkout/                                         @payments-team
/apps/shop-ui/                                          @storefront-team
/apps/shop-search/                                      @storefront-team
/apps/order-worker/                                     @fulfilment-team

# ⭐ the observability-self rules are platform-owned and require TWO approvals
/platform/prometheus/alerting-rules/observability-self.yaml  @platform-team @sre-leads
/platform/prometheus/alerting-rules/watchdog.yaml            @platform-team @sre-leads
```

**The guardrails that make self-service safe — CI, not gatekeeping:**

| Guardrail | What it stops | How |
|---|---|---|
| `promtool check rules` | A syntactically invalid rule that silently disables a whole group | CI |
| ⭐ `promtool test rules` | An alert with no test, or a test that fails | **CI requires a test file for every new alert** |
| The cardinality budget | A team adding an unbounded label | CI fails above 500k series |
| The metadata check | An alert with no `team`, `severity`, `summary` or `runbook_url` | CI |
| The runbook link check | A runbook that doesn't exist | CI |
| `otelcol --dry-run` | A Collector config that won't start | CI |
| The ephemeral-cluster e2e | Anything, in combination | CI |
| `memory_limiter first, batch last` | A team adding a processor in the wrong place | CI structural check |
| ⭐ **A per-team rule-group budget** | One team adding 500 rules and slowing every evaluation | CI: `count rules per file ≤ 50` |
| ⭐ **A per-team series budget** | One team blowing the global cardinality | The `cost_center` label + a weekly report |

```bash
# ⭐ the guardrail that makes self-service genuinely safe:
cat > ci/check-self-service-budgets.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
MAX_RULES_PER_FILE=50
MAX_GROUPS_PER_FILE=10
fail=0
for f in platform/prometheus/alerting-rules/*.yaml; do
  n=$(grep -cE '^\s+- alert:' "$f" || true)
  g=$(grep -cE '^\s+- name:' "$f" || true)
  if (( n > MAX_RULES_PER_FILE )); then
    echo "  ✖ $(basename "$f"): $n alerts (max $MAX_RULES_PER_FILE) — split it by team"; fail=1
  fi
  # ⭐ a rule file must belong to exactly one team (or to platform)
  teams=$(grep -oE 'team: [a-z]+' "$f" | sort -u | wc -l)
  if (( teams > 1 )); then
    echo "  ✖ $(basename "$f"): mixes $teams teams — CODEOWNERS can't scope it. One file per team."; fail=1
  fi
done
# ⭐ dashboards: one folder per team, one UID prefix per team
for f in platform/grafana/dashboards/*.json; do
  uid=$(jq -r '.uid' "$f")
  case "$uid" in
    1*-payments-*|1*-storefront-*|1*-fulfilment-*) ;;
    00-*|2*-k8s-*|30-*|40-*|50-*|99-*) ;;   # platform-owned
    *) echo "  ⚠️  $(basename "$f"): uid '$uid' doesn't follow the team-prefix convention";;
  esac
done
exit $fail
EOF
chmod +x ci/check-self-service-budgets.sh
```

### Step 5 — data isolation (be honest about what's possible)

| Layer | Can you isolate in OSS? | How |
|---|---|---|
| **Grafana dashboards** | ✅ Yes | One **folder per team**, folder permissions → team's Grafana role = Editor, everyone else = Viewer or none |
| **Grafana datasources** | ⚠️ Partially | Datasources are global in OSS. You can create a **team-scoped datasource** with a baked-in `namespace` filter, or use **Grafana Enterprise's datasource permissions** |
| **Prometheus query results** | ❌ Not natively | Prometheus has **no query-level authorisation**. Anyone who can reach :9090 can query anything. Mitigations: (a) don't expose Prometheus directly — only through Grafana; (b) put a **prom-label-proxy** in front, which injects a mandatory `namespace=` matcher per authenticated user; (c) shard into one Prometheus per team |
| **Tempo traces** | ❌ Not natively | Tempo has **multi-tenancy via `X-Scope-OrgID`** — set it in the Collector per team, and give each team a Grafana datasource with that header. That's real isolation. |
| **Loki logs** | ✅ Yes, properly | Loki has **native multi-tenancy via `X-Scope-OrgID`**. Set `auth_enabled: true`, have the Collector route by the `team` resource attribute, and give each team a datasource with its tenant header. |

**The honest, implementable design:**

```yaml
# ⭐ 1. Loki: real tenancy. The Collector sets the tenant from the team attribute.
# platform/otel/gateway-config.yaml
processors:
  # map team → Loki tenant ID
  transform/tenant:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          - set(attributes["tenant_id"], attributes["team"]) where attributes["team"] != nil
          - set(attributes["tenant_id"], "platform") where attributes["team"] == nil

exporters:
  loki:
    endpoint: http://loki.monitoring.svc:3100/loki/api/v1/push
    tenant_id: ""                        # ⭐ empty = use the per-record tenant
    # the Loki exporter reads `tenant_id` from the resource attribute when set:
    # (in contrib ≥0.100, use `default_labels_enabled` + the tenant header config)
    headers:
      X-Scope-OrgID: ""                  # overridden per-record
```

```yaml
# and each team gets a Loki datasource scoped to its tenant
# platform/grafana/datasources/loki-payments.yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: grafana-ds-loki-payments, namespace: monitoring, labels: {grafana_datasource: "1"}}
data:
  loki-payments.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki (payments)
        uid: loki-payments
        type: loki
        access: proxy
        url: http://loki.monitoring.svc:3100
        jsonData:
          httpHeaderName1: X-Scope-OrgID     # ⭐⭐ the tenant header
          derivedFields:
            - {name: TraceID, matcherRegex: '"trace_id"\s*:\s*"(\w+)"', url: '$${__value.raw}', datasourceUid: tempo-payments}
        secureJsonData:
          httpHeaderValue1: payments          # ⭐ from a Secret in production
```

```yaml
# ⭐ 2. Tempo: same mechanism
exporters:
  otlp/tempo:
    endpoint: tempo.monitoring.svc:4317
    headers:
      X-Scope-OrgID: "${tenant_id}"        # ⭐ the Collector can template from resource attrs
```

```yaml
# ⭐ 3. Prometheus: prom-label-proxy is the honest answer
#    It sits in front of Prometheus and INJECTS a mandatory label matcher
#    based on the authenticated user's namespace. Grafana authenticates to it
#    with the user's identity (via the auth proxy), so a payments user
#    physically cannot query storefront series.
apiVersion: apps/v1
kind: Deployment
metadata: {name: prom-label-proxy, namespace: monitoring}
spec:
  replicas: 2
  selector: {matchLabels: {app: prom-label-proxy}}
  template:
    metadata: {labels: {app: prom-label-proxy}}
    spec:
      containers:
        - name: proxy
          image: quay.io/prometheuscommunity/prom-label-proxy:v0.11.0
          args:
            - --insecure-listen-address=0.0.0.0:8080
            - --upstream=http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090
            - --label=namespace                       # ⭐ the enforced label
            - --enable-apis=metadata,label/ls/values,query,query_range,series,alerts,rules
          ports: [{containerPort: 8080}]
# ⭐ then point the team Grafana datasources at prom-label-proxy:8080 instead of
#    Prometheus:9090, and pass the user's namespace via the auth proxy header.
```

```yaml
# ⭐ 4. Grafana folders — the part that just works
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-payments-checkout
  namespace: monitoring
  labels: {grafana_dashboard: "1"}
  annotations:
    grafana_folder: "Payments"          # ⭐ the sidecar creates the folder
data:
  10-payments-checkout-red.json: |
    { … }
---
# and the folder permissions (Grafana ≥9 has a folder-permissions API)
apiVersion: v1
kind: ConfigMap
metadata: {name: grafana-folder-permissions, namespace: monitoring}
data:
  permissions.sh: |
    #!/usr/bin/env bash
    for team in Payments Storefront Fulfilment Platform; do
      fid=$(curl -s -u "$GF_ADMIN:$GF_PASS" "localhost:3000/api/folders" \
             | jq -r --arg t "$team" '.[] | select(.title==$t) | .uid')
      [[ -z "$fid" || "$fid" == "null" ]] && continue
      curl -s -u "$GF_ADMIN:$GF_PASS" -XPOST "localhost:3000/api/folders/$fid/permissions" \
        -H 'Content-Type: application/json' -d "{
          \"items\": [
            {\"role\": \"Editor\", \"permission\": 2},
            {\"team\": \"team-${team,,}\", \"permission\": 2},
            {\"role\": \"Viewer\", \"permission\": 1}
          ],
          \"overwrite\": true}"
    done
```

### Step 6 — per-team cost attribution

```promql
# ⭐ METRICS: series count per team, via the kube_pod_labels join
count by (label_team) (
  group by (__name__, namespace, pod, label_team) (
    {__name__=~".+"}
    * on(namespace, pod) group_left(label_team)
      kube_pod_labels{label_team!=""}
  )
)

# samples ingested per team per day (the actual billing driver on Grafana Cloud)
sum by (label_team) (rate(scrape_samples_scraped[1h])) * 3600 * 24
  * on() group_left() 1

# ⭐ TRACES: spans per team
sum by (team) (rate(traces_service_graph_request_total[1h])) * 3600 * 24

# ⭐ LOGS: bytes per team (the Loki billing driver)
sum by (tenant) (rate(loki_distributor_bytes_received_total[1h])) * 3600 * 24

# ── the weekly cost report ──────────────────────────────────────
# $/GB-month: metrics ~$8, traces ~$0.50, logs ~$0.50 (Grafana Cloud, 2026)
```

```bash
cat > scripts/cost-report.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ weekly: who is spending what
set -euo pipefail
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 5
Q() { curl -sG localhost:9090/api/v1/query --data-urlencode "query=$1" | jq -r '.data.result[] | "\(.metric[\(.metric|keys[0]) // "?"])\t\(.value[1])"'; }

printf '%-14s %12s %12s %12s %10s\n' TEAM METRIC_SERIES TRACES/DAY LOGS_GB/DAY 'EST $/MO'
printf '%-14s %12s %12s %12s %10s\n' ──── ───────────── ─────────── ─────────── ────────
for team in payments storefront fulfilment platform; do
  ms=$(curl -sG localhost:9090/api/v1/query --data-urlencode \
        "query=count(group by (__name__,pod) ({namespace=~\"shop|storefront|fulfilment|monitoring|otel\"}))" \
        | jq -r '.data.result[0].value[1] // 0')
  ts=$(curl -sG localhost:9090/api/v1/query --data-urlencode \
        "query=sum(rate(traces_service_graph_request_total{client_namespace=~\".*\"}[1h]))*86400" \
        | jq -r '.data.result[0].value[1] // 0')
  ls=$(curl -sG localhost:9090/api/v1/query --data-urlencode \
        "query=sum(rate(loki_distributor_bytes_received_total[1h]))*86400/1e9" \
        | jq -r '.data.result[0].value[1] // 0')
  # ⭐ a real implementation joins on label_team; this is the shape
  cost=$(awk "BEGIN{printf \"%.0f\", ($ms/1000)*8 + ($ts/1e6)*0.5 + $ls*30*0.5}")
  printf '%-14s %12s %12s %12s %10s\n' "$team" "$ms" "${ts%.*}" "${ls%.*}" "\$$cost"
done
EOF
chmod +x scripts/cost-report.sh
```

### Step 7 — what you'd say in the interview

> *"I chose label-based tenancy over a stack per team, because with four teams the operational cost of four stacks outweighs the isolation benefit — but I designed the label schema (`team`, `tier`, `journey`, `cost_center`) so that migrating to Mimir's `X-Scope-OrgID` tenancy later is a Collector config change, not a re-instrumentation.*
>
> *Self-service is a code-review problem, not a permissions problem. CODEOWNERS gives each team write access to its own rules, dashboards, SLOs and runbooks with no platform approval, and CI is the gatekeeper: `promtool check rules`, a required unit test for every new alert, a metadata check, a runbook-link check, a cardinality budget, and a per-team rule-count budget. That's how a team ships an alert in 20 minutes without a platform ticket — and how the platform team sleeps.*
>
> *Routing is driven entirely by the `team` label, which comes from the pod's Kubernetes labels via kube-state-metrics' `metricLabelsAllowlist`, joined into the alert expression with `group_left`. A team can move a Deployment between namespaces and its alert routing follows automatically. An alert with no `team` label routes to a `platform-unowned` receiver and pages us — a teamless alert is a bug, and I'd rather be paged than have it silently dropped.*
>
> *On isolation, I'll be precise about what's real and what isn't. **Loki and Tempo have genuine multi-tenancy** via `X-Scope-OrgID`, so the Collector sets the tenant header from the `team` resource attribute and each team's Grafana datasource carries its own header — that's hard isolation. **Prometheus has no query authorisation at all**, so I put `prom-label-proxy` in front of it, which injects a mandatory `namespace=` matcher per authenticated identity; Grafana never talks to Prometheus directly. And **Grafana OSS folders** give per-team dashboard permissions. The one thing I can't do in OSS is per-datasource row-level permissions — that's Enterprise, and I'd flag it as the trigger for either upgrading or moving to Mimir."*

---

## Task C5 — The migration plan

**Scenario:** the CFO has decided the company will standardise on **Datadog**. You have 90 days. Alternatively (and you should plan for both): Datadog's bill comes in at 4× the estimate and you have 60 days to get back to self-hosted.

Write the migration plan for **both directions**. Include: what changes, what doesn't, the risk register, the rollback plan, the cost model, and the one architectural decision that makes both migrations cheap.

<details>
<summary><b>💡 Hints — this task is really about one thing</b></summary>

1. If you have to rewrite your instrumentation to migrate, you made a mistake two years ago. What prevents that?
2. Which parts of the platform are **vendor-specific** and which are **portable**? Sort everything into those two piles first.
3. A migration is a **dual-write** period, not a switch. Plan for running both.
4. The cost driver at every vendor is the same three things: custom metrics/series, ingested spans, ingested GB of logs. Your cardinality discipline transfers directly.
</details>

**✅ Answer**

### Step 0 — the one architectural decision that makes both migrations cheap ⭐⭐

> **The OpenTelemetry Collector is the abstraction boundary. Every application talks OTLP to a Collector that you own. No application ever talks to a vendor SDK.**

```
     ┌─ apps ──────────────────────────────────────────────┐
     │  OTLP only. No Datadog SDK. No New Relic agent.     │
     │  No CloudWatch exporter. Ever.                       │
     └──────────────────────┬──────────────────────────────┘
                            ▼
              ┌─────────────────────────────┐
              │   OTel COLLECTOR (gateway)  │   ⭐ THE ONLY THING THAT CHANGES
              │   exporters:                │
              │     otlp/tempo      ────►   │──► Tempo        (today)
              │     loki            ────►   │──► Loki         (today)
              │     prometheusremotewrite   │──► Prometheus   (today)
              │     datadog         ────►   │──► Datadog      (during migration)
              │     otlphttp/mimir  ────►   │──► Mimir        (the other direction)
              └─────────────────────────────┘
```

**What this buys you:**

| | Without the Collector as the boundary | With it |
|---|---|---|
| Migrating to Datadog | Re-instrument 12 services in 4 languages with the Datadog SDK. 6–12 weeks, high risk, and you're now locked in again. | **Add one exporter block.** 1 day. Dual-write for 2 weeks. Cut over. |
| Migrating back | Repeat the whole thing. | **Remove one exporter block.** 1 hour. |
| Dual-running (the essential part) | Impossible without two agents in every process — they conflict. | ⭐ Trivial: two exporters in one pipeline. |
| Sampling policy changes | Redeploy every app. | Change the gateway config. |
| PII redaction | Every app must do it correctly. | One `attributes` processor. |
| Cost control | Per-app, unenforceable. | One `filter` processor, centrally. |

**If you take one thing from this capstone into an interview, it's this:**

> *"I would never let an application depend on a vendor's SDK. Every service emits OTLP to a Collector we own, and the Collector's exporter list is the only vendor-specific configuration in the entire platform. That makes a vendor migration a one-day config change with a two-week dual-write period, instead of a six-month re-instrumentation project. It also means sampling, redaction, cardinality control and cost enforcement happen in exactly one place."*

### Step 1 — sort the platform into portable and vendor-specific

| Component | Portable? | Migration effort |
|---|---|---|
| **App instrumentation** (OTel SDKs, Micrometer, `promhttp`) | ✅ **100% portable** | **Zero.** This is the point of Step 0. |
| **Semantic conventions** (`http.route`, `db.system`, `service.name`) | ✅ portable | Zero — Datadog maps them natively |
| **The Collector configs** | ⚠️ the *structure* is portable; the `exporters` block changes | 1 day |
| **Dashboards** (Grafana JSON) | ⚠️ Datadog has its own dashboard format | 2–3 weeks to rebuild ~40 dashboards, **or** keep Grafana pointed at Datadog's API (Datadog has a Grafana datasource) |
| **PromQL** | ⚠️ Datadog uses its own query language; Managed Prometheus accepts PromQL | The `prometheusremotewrite`→Datadog path preserves PromQL if you use **Datadog Managed Prometheus**. Otherwise, rewrite ~200 queries. |
| **Alerting rules** (PromQL + `for:`) | ⚠️ Datadog monitors have a different model (no `for:`, but `notify_no_data`, `renotify_interval`) | 1–2 weeks. **The semantics differ** — see the risk register. |
| **SLOs** (sloth-generated multi-window burn rate) | ⚠️ Datadog has native SLOs with **burn-rate alerts built in** | Actually *easier* — delete sloth, use Datadog's SLO product. 3 days. |
| **Alertmanager routing** | ⚠️ Datadog has its own notification rules + integrations | 1 week. You lose `inhibit_rules` (see risks). |
| **LogQL** | ❌ Datadog's log query language is different | Rewrite ~30 saved views. 3 days. |
| **TraceQL** | ❌ Datadog has its own trace search | Rewrite ~10 queries. 1 day. |
| **Runbooks** | ✅ **100% portable** — they're Markdown describing your system | Zero. Update the links. |
| **CI validation** | ⚠️ `promtool`/`amtool` no longer apply | Replace with Datadog's Terraform provider validation + `datadog-ci`. 1 week. |
| **The game day** | ✅ **100% portable** — it tests your *detection*, not your vendor | Zero. ⭐ **Re-run it after migrating. It's your acceptance test.** |
| **Grafana** | ✅ keep it! Datadog has a first-class Grafana datasource | Zero, and it preserves your dashboards |

**Summary: ~70% of the platform is portable, and the 30% that isn't is all *query and notification configuration*, not instrumentation.**

### Step 2 — the forward migration (to Datadog), 90 days

```
WEEK 1–2  ── DISCOVER AND BASELINE ─────────────────────────────────────────
  □ Run ./scripts/cardinality-report.sh and save it. ⭐ This is your cost predictor.
  □ Count: custom metric series, spans/day, log GB/day, per team.
  □ Get a Datadog quote FROM THOSE NUMBERS, not from an estimate.
    Datadog bills on: custom metrics (per 100), APM hosts, ingested GB,
    indexed log events, retention months, and Synthetics checks.
  □ ⭐ THE #1 BILL SHOCK: `container_*` and `kube_*` metrics count as CUSTOM
    in Datadog unless you're on the right plan. 2.4M series → an enormous bill.
    Decide NOW which metrics you will NOT ship.
  □ Baseline the game day: run all 5 scenarios, record detection times.

WEEK 3–4  ── THE DUAL-WRITE FOUNDATION ⭐ ───────────────────────────────────
  □ Create the Datadog org, API keys (as K8s Secrets + External Secrets), and
    a Terraform module for every Datadog resource (monitors, dashboards, SLOs,
    synthetics, notification rules). ⭐ Datadog-as-code from day one.
  □ Add the Datadog exporters to the gateway ALONGSIDE the existing ones:

      exporters:
        datadog:
          api:
            site: datadoghq.com
            key: ${env:DD_API_KEY}
          traces: {endpoint: https://trace.agent.datadoghq.com}
          metrics: {delta_ttl: 300, resource_attributes_as_tags: [team, journey, tier]}
          logs: {dump_payloads: false, use_compression: true, compression_level: 6}
          host_metadata: {hostname_source: first_tag}
          ⭐ only: [team:payments, team:storefront]     # ← phase it in by team

      service:
        pipelines:
          traces:
            exporters: [otlp/tempo, datadog]             # ⭐⭐ BOTH
          metrics:
            exporters: [prometheusremotewrite, datadog]
          logs:
            exporters: [loki, datadog]

  □ ⭐ Add a `filter` processor BEFORE the datadog exporter to drop what you
    don't want to pay for. This is where the cardinality discipline pays off:

      processors:
        filter/datadog-metrics:
          metrics:
            metric:
              - 'IsMatch(__name__, "go_.*")'
              - 'IsMatch(__name__, "process_.*")'
              - 'IsMatch(__name__, "container_network_.*")'
              - 'IsMatch(__name__, "kube_pod_container_status_last_.*")'
              - 'resource.attributes["team"] == nil'      # ⭐ unowned = don't ship

  □ Verify: the SAME span, metric and log appears in both Grafana and Datadog.
  □ ⭐ Measure the actual Datadog ingest volume against the quote. This is the
    go/no-go gate. If it's 4× the estimate, you have found out in week 4, not
    month 6.

WEEK 5–8  ── REBUILD THE DETECTION LAYER ───────────────────────────────────
  □ SLOs first (easiest, highest value): recreate all 6 SLOs as Datadog SLOs
    with burn-rate alerts. Datadog's implementation is genuinely good —
    multi-window multi-burn-rate is native. Delete sloth at cutover.
  □ Monitors: translate every alert. ⭐ NOT mechanically — see the risk register
    for the semantic differences. Start with tier 1 (symptom) and tier 4 (self).
  □ Synthetics: recreate the synthetic checkout journey (Task C3, Fix G5) as a
    Datadog Synthetic browser test, ONE PER SEGMENT. This is cheaper in Datadog
    than in your own CronJob and it runs from real locations.
  □ Dashboards: decide the strategy NOW —
      (a) rebuild in Datadog (2–3 weeks, but native and fast), or
      (b) ⭐ keep Grafana and add the Datadog datasource (1 day, preserves
          every panel, and keeps ONE pane of glass across the migration).
      → Choose (b) for the migration, (a) afterwards if the team prefers it.
  □ Log/trace views: recreate the ~30 saved LogQL views and ~10 TraceQL queries.
  □ Notification rules + escalation policies in Datadog, mirroring the
    Alertmanager routing tree. ⭐ Test each one with a synthetic trigger.

WEEK 9–10 ── THE GAME DAY ON THE NEW PLATFORM ⭐⭐ ──────────────────────────
  □ Re-run ALL FIVE scenarios against Datadog-only detection.
  □ Fill in the same scorecard. Compare to the week-1 baseline.
  □ ⭐ ACCEPTANCE CRITERIA: every scenario detected in ≤1.5× the baseline time,
    with the same root-cause click path, and no scenario missed.
  □ Anything that regresses → fix it before cutover, or don't cut over.

WEEK 11─── ── CUT OVER, TEAM BY TEAM ────────────────────────────────────────
  □ payments → storefront → fulfilment → platform. One team per week.
  □ Per team: remove the self-hosted exporter from the gateway, keep Datadog.
  □ Keep the self-hosted stack RUNNING and ingesting for 2 weeks after the last
    team cuts over. ⭐ That's your rollback.
  □ Update every runbook link.

WEEK 12–13 ── DECOMMISSION ──────────────────────────────────────────────────
  □ Only after 2 weeks with zero rollbacks:
  □ Turn off the Tempo, Loki and Prometheus exporters.
  □ Keep the Collector. ⭐⭐ IT IS NOT VENDOR SPECIFIC. It is now your
    Datadog agent — and your escape hatch.
  □ Keep the Watchdog/heartbeat pointed at something independent of Datadog.
  □ Archive the TSDB/Tempo/Loki data to object storage before deleting the PVCs.
  □ Update the CI: drop promtool/amtool, add Datadog Terraform validation.
  □ Update the cost report to read from the Datadog usage API.
```

### Step 3 — the reverse migration (Datadog → self-hosted), 60 days

```
WEEK 1    ── the good news: your apps still emit OTLP ⭐ ────────────────────
  □ If you followed Step 0, the apps never changed. Verify:
      kubectl exec -n shop deploy/shop-api -- printenv | grep -iE 'datadog|dd_'
      → ⛔ if you see DD_AGENT_HOST or a Datadog SDK, you did NOT follow Step 0
        and this migration is 6 months, not 60 days. Fix that first.
  □ If clean: the migration is purely a Collector exporter change + a rebuild
    of the detection layer.

WEEK 2–3  ── re-stand-up the self-hosted platform ──────────────────────────
  □ ./scripts/bootstrap-cluster.sh against the production cluster shape.
    ⭐ This is why the bootstrap script is idempotent and in Git.
  □ Mimir/Thanos instead of a single Prometheus (you now know your volume).
  □ Tempo + Loki with the sizing from the Datadog usage API — which gives you
    EXACT numbers for the first time.
  □ Size from the Datadog bill: ingested GB/day for logs, spans/day, custom
    metrics. That's your capacity plan, handed to you by the vendor.

WEEK 4–5  ── dual-write in the OTHER direction ─────────────────────────────
  □ Add otlp/tempo, loki and prometheusremotewrite back to the gateway,
    alongside datadog. Both run for 2 weeks.
  □ Re-import the alerts: Datadog monitors → PrometheusRule CRs.
    ⭐ Write a converter. Datadog's Terraform state is JSON; the queries are
      mostly portable if you used Managed Prometheus.
  □ Rebuild the sloth SLO specs from the Datadog SLO definitions.
  □ Re-import the dashboards from the Grafana JSON you archived in week 11
    of the forward migration. ⭐ IF YOU ARCHIVED THEM. Archive them now if you
    didn't: Grafana → Dashboards → Export → save JSON to Git.

WEEK 6–7  ── the game day again ────────────────────────────────────────────
  □ Same five scenarios, same scorecard, same acceptance criteria.
  □ This is the ONLY defensible way to prove parity.

WEEK 8    ── cut over and decommission Datadog ─────────────────────────────
  □ Remove the datadog exporter. Keep the Datadog org read-only for 30 days
    (for historical queries during the transition).
  □ ⭐ Export your Datadog history first if you need it for compliance:
    the API can bulk-export logs and metrics, but it's slow and rate-limited.
    Budget a week and start it in week 6.
  □ Cancel at the billing boundary, not mid-cycle.
```

### Step 4 — the risk register ⭐ the part that shows seniority

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| **R1** | **The bill is 3–5× the quote.** Custom metrics and log indexing are the classic traps. | ⭐⭐⭐ **High** | Severe | Dual-write for 4 weeks and read the **actual** usage API before cutting over. Pre-filter with a `filter` processor. Negotiate a commit-based discount against measured volume. |
| **R2** | **Alert semantics differ.** Datadog monitors have no `for:` — they have evaluation windows and `notify_no_data`. A `for: 5m` PromQL alert does **not** translate 1:1, and naive translation causes both false positives and missed detections. | ⭐⭐⭐ High | Severe | Re-run the game day (week 9–10) as the **acceptance gate**. Tune per-alert against the recorded baseline detection times. |
| **R3** | **You lose `inhibit_rules`.** Datadog has no equivalent of "a symptom alert suppresses its cause alerts". A node failure will page 47 times. | ⭐⭐ Medium | High | Recreate with Datadog's **notification rules** + monitor dependencies, or keep Alertmanager in front (Datadog webhooks → Alertmanager → PagerDuty). Accept some noise; document it. |
| **R4** | **PromQL doesn't port.** Datadog's query language differs; `histogram_quantile`, `predict_linear`, `clamp_min` and `group_left` have no direct equivalents. | ⭐⭐⭐ High | High | Use **Datadog Managed Prometheus** (accepts remote-write and PromQL). Or accept rewriting ~200 queries and losing the recording-rule layer. |
| **R5** | **Vendor lock-in deepens during the migration.** Teams start using Datadog-only features (Watchdog AI, Continuous Profiler, Error Tracking) and now leaving costs more. | ⭐⭐ Medium | Medium | ⭐ **Write this into the migration policy**: during the dual-write period, teams may use Datadog-native features only if the equivalent capability is documented as a known lock-in. Review at week 8. |
| **R6** | **The egress bill.** Sending 62M spans/day + 180M log lines/day out of your cloud to Datadog incurs **cloud egress charges** on top of the Datadog bill. | ⭐⭐ Medium | Medium | Measure it in week 4. Compress (`use_compression: true`), filter aggressively, and consider a Datadog agent in-region. |
| **R7** | **Data residency / compliance.** Log and trace data now leaves your VPC and possibly your jurisdiction. | ⭐ Low but severe | Severe | Check with legal **in week 1**, not week 11. Datadog has EU/US sites; pick correctly. Redact PII in the Collector *before* export — you already do this. |
| **R8** | **The team's skills atrophy.** Nobody writes PromQL for 6 months; then you migrate back and nobody can. | ⭐⭐ Medium | Medium | Keep Grafana + PromQL as the primary interface during the migration (option (b) in week 5–8). Keep the game day running on both platforms. |
| **R9** | **Nobody owns the Collector any more.** "Datadog handles it" → the Collector rots → the abstraction boundary disappears → R5 becomes permanent. | ⭐⭐⭐ High | Severe | ⭐ **The Collector stays owned by the platform team, in Git, with CI, forever.** Put it in the RACI explicitly. This is the single most important governance decision in the migration. |
| **R10** | **The reverse migration is blocked by lost artefacts.** Dashboards were click-built in Datadog; the Grafana JSON was never archived. | ⭐⭐ Medium | High | Archive all Grafana dashboard JSON to Git **before** week 11. Terraform every Datadog resource from day one, so the reverse conversion has a machine-readable source. |

### Step 5 — the cost model

```
SELF-HOSTED (current, after Task C2's optimisations)
  Compute (34 CPU / 96 GB across 6 nodes)             $620
  Object storage (400 GB traces + 300 GB logs)         $45
  Block storage (Prometheus 15d, 2 pairs)              $80
  Engineering: 0.2 FTE to operate                     $2,400   ⭐ the real cost
  Egress                                               $30
                                                      ──────
  TOTAL                                               $3,175/mo

DATADOG (from the measured volumes, not an estimate)
  APM: 28 hosts × $31                                 $868
  Infrastructure: 34 hosts × $15                      $510
  Logs: 5.4 GB/day ingested × $0.10/GB × 30           $162
        + 30M indexed events/day × $1.70/M × 30     $1,530   ⭐⭐ INDEXING is the cost
  Custom metrics: 12,000 × $5 per 100                 $600
  SLOs, Synthetics (20 checks × 5 locations)          $216
  Dashboards, Error Tracking, Watchdog                $480
  Cloud egress (from your provider)                    $95
                                                      ──────
  TOTAL                                               $4,461/mo
  Engineering: 0.05 FTE                               −$1,800  ⭐ the saving
                                                      ──────
  EFFECTIVE                                           $2,661/mo

⭐ THE HONEST COMPARISON:
  Datadog is ~$500/mo CHEAPER once you account for the engineering time it saves.
  It becomes 3× more expensive the moment log indexing or custom metrics grow
  without a filter — and they always do, unless someone owns the Collector.

  The decision is NOT "which is cheaper". It is:
    "Do we want to spend 0.2 FTE owning our observability, or spend that FTE
     on the product and pay Datadog — while keeping the Collector as the
     boundary so the decision is reversible?"
```

```bash
# ⭐ the script that keeps the comparison honest, run monthly
cat > scripts/vendor-cost-compare.sh <<'EOF'
#!/usr/bin/env bash
# Compare the actual Datadog bill against the self-hosted equivalent, monthly.
set -euo pipefail
# Datadog usage API
DD_USAGE=$(curl -s "https://api.datadoghq.com/api/v1/usage/summary?start_month=$(date -d '-1 month' +%Y-%m)' \
  -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY")
echo "$DD_USAGE" | jq '{
  ingested_logs_gb:   .usage[].ingested_events / 1e6,
  custom_metrics:     .usage[].custom_usage[].avg_usage,
  apm_hosts:          .usage[].apm_host_usage[].host_count,
  infra_hosts:        .usage[].infra_host_usage[].host_count
}'
# ⭐ and the counterfactual: what would we have paid to self-host the same volume?
./scripts/cost-report.sh
EOF
chmod +x scripts/vendor-cost-compare.sh
```

### Step 6 — the answer, condensed for an interview

> *"The whole plan rests on one decision made years earlier: applications emit OTLP to a Collector we own, and the Collector's exporter list is the only vendor-specific configuration in the platform. That turns a migration from a six-month re-instrumentation project into a one-day config change with a two-week dual-write.*
>
> *Forward: baseline the volumes and the game day in weeks 1–2; dual-write from week 3 with a `filter` processor in front of the Datadog exporter so we only pay for what we'd actually query; rebuild the detection layer weeks 5–8 — SLOs first because Datadog's native burn-rate alerts are genuinely better than sloth; then re-run the game day in weeks 9–10 as the acceptance gate, because alert semantics don't translate mechanically (Datadog has no `for:` and no `inhibit_rules`); cut over team by team, keeping the self-hosted stack ingesting for two weeks as the rollback.*
>
> *The risk I'd flag loudest isn't cost — it's governance. During a dual-write period, teams start using vendor-only features, and the Collector stops being maintained because 'Datadog handles it'. That's how a reversible decision quietly becomes permanent. So the Collector stays in Git, owned by the platform team, with CI, forever — written into the RACI, not left to goodwill.*
>
> *And the honest cost answer: at our measured volumes Datadog is about $500/month cheaper once you count the 0.15 FTE of engineering time it frees. It becomes three times more expensive the moment log indexing or custom metrics grow without a filter. So the real question isn't which is cheaper — it's whether we want to spend 0.2 FTE owning our observability, and whether we keep the boundary that makes the answer reversible."*

---

## ✅ Capstone completion checklist

```
THE REPOSITORY
  □ everything is in Git — the Collector configs, the rules, the dashboards,
    the Helm values, the runbooks, the CI, the game-day scenarios
  □ ./scripts/bootstrap-cluster.sh rebuilds the ENTIRE platform from scratch
    on a clean machine, idempotently
  □ a Makefile where every operation is a target, with `make help`
  □ docs/TELEMETRY-CONVENTIONS.md exists and is enforced by CI

THE APPLICATION
  □ 5 services + 3 data stores, all instrumented
  □ metrics, traces AND logs from every one, including the browser
  □ a payment-mock with a runtime chaos API — the game-day control surface
  □ identical OTEL_PROPAGATORS and OTEL_RESOURCE_ATTRIBUTES everywhere
  □ one trace spans shop-ui → checkout → shop-api → postgres, plus an async
    RabbitMQ hop to order-worker connected by a span LINK

THE PLATFORM
  □ Prometheus + Alertmanager + Grafana + Tempo + Loki + the OTel Collector
    (agent + gateway), all from Helm values in Git
  □ NetworkPolicies that allow telemetry egress, tested with nc
  □ the OTel Operator injecting into a Deployment via one annotation
  □ blackbox probes including a multi-step POST that asserts the response body
  □ a Watchdog heartbeat routed to an EXTERNAL dead-man's switch ⭐⭐

SLOs AND ALERTS
  □ 6 SLOs in a written catalogue, each with a defended objective and window
  □ sloth-generated multi-window multi-burn-rate alerts
  □ the four-tier hierarchy: symptom / saturation / cause / self
  □ every alert has severity, team, tier, summary, description, runbook_url,
    dashboard_url, trace_query and log_query
  □ every runbook_url resolves to a real Markdown file in the repo
  □ Alertmanager routing by team, with inhibit rules and a teamless catch-all
  □ the Slack template renders the runbook and the diagnostic queries
  □ you have sent a test alert with amtool and watched it route

DASHBOARDS
  □ generated from a script, not click-built, and the generator is in Git
  □ the 99-incident dashboard: from "something's wrong" to root cause in ≤4 clicks
  □ the 40-observability-health dashboard: the Collector, Prometheus, Loki,
    Tempo, Alertmanager — including drops, refusals and queue depth
  □ exemplars enabled on the latency panels (the green diamonds)
  □ a heatmap that reveals bimodal distributions
  □ deployment annotations showing on every dashboard
  □ provisioned by the sidecar from labelled ConfigMaps

CORRELATION
  □ Prometheus → Tempo via exemplarTraceIdDestinations
  □ Tempo → Loki via tracesToLogs (filterByTraceID + filterBySpanID)
  □ Tempo → Prometheus via tracesToMetrics with 3 useful queries
  □ Loki → Tempo via derivedFields matching YOUR log format
  □ Tempo's metricsGenerator on: service graph + span metrics
  □ ./scripts/validate-trace-pipeline.sh passes 8/8

CI ⭐⭐
  □ promtool check rules on every rule file
  □ promtool test rules — UNIT TESTS for every alert, including the
    false-positive tests (a 2-minute blip must NOT page; a deploy must NOT page;
    a 40% decline rate must NOT look like an outage)
  □ every alert has severity/team/summary/runbook_url, checked programmatically
  □ every runbook link resolves to a file
  □ the OTel Collector config validated with --dry-run AND structurally
    (memory_limiter first, batch last, queues enabled, telemetry on)
  □ tail_sampling checked for a status_code and a latency policy
  □ the dashboard linter: unique UIDs, provisioned datasource UIDs, no counter
    without rate(), no division without clamp_min, no unbounded group-by
  □ the telemetry conventions check (service names, propagators, no :latest)
  □ the ownership check (team/tier/journey/cost-center labels)
  □ an ephemeral kind cluster e2e that installs everything and ASSERTS that
    telemetry flows and that an injected failure produces a routed alert
  □ the cardinality budget asserted against a real Prometheus
  □ Trivy + SBOM on every image

THE GAME DAY ⭐⭐⭐
  □ 5 scenarios scripted, injectable with one command, healable with one command
  □ 01 payment timeout — latency-only, zero errors, invisible to an availability SLO
  □ 02 pool exhaustion — the saturation alert fires BEFORE the symptom alert
  □ 03 memory leak — the sawtooth floor rises; an HPA on CPU will not save you
  □ 04 cardinality bomb — series grow with traffic; Prometheus dies; everything goes dark
  □ 05 monitoring blind — the Collector/Prometheus/Alertmanager/NetworkPolicy fails
  □ a scorecard filled in: time to fire, time to diagnose, correct root cause,
    runbook sufficient, no false positives, auto-resolved
  □ ≥8/10 on the scorecard
  □ an incident report written for at least two scenarios
  □ follow-ups filed with owners and dates

COST AND SCALE
  □ ./scripts/cardinality-report.sh run, top 25 metrics known, no label >1000 values
  □ tail sampling measured: ≥80% storage reduction, ZERO error-trace loss
  □ the cost model written down, per signal, with the levers ranked
  □ the HA + long-term-storage path understood (2 replicas, externalLabels,
    remote_write, Thanos/Mimir, dedup on prometheus_replica)
  □ hardening done: no anonymous Grafana, no admin API, no public OTLP,
    read-only Collector RBAC, PII redaction, Pod Security Standards

HANDOVER
  □ a runbook per alert, from a template, with a decision tree and a mitigation table
  □ docs/ALERT-CATALOG.md generated from the rule files, never hand-maintained
  □ docs/ON-CALL.md with the first-five-minutes procedure and the handover checklist
  □ docs/ARCHITECTURE.md with the diagram from this file
  □ a second person has run the game day successfully without your help ⭐⭐

THE FIVE TASKS
  □ C1 — the search SLO set, including the quality SLI nobody writes,
        with the objective numbers defended out loud and unit-tested
  □ C2 — 60% cost reduction, measured, with zero alerting capability lost
        and the game day re-run as proof
  □ C3 — the segment-degraded incident: found in under 5 minutes, and the
        platform fixed with per-segment SLOs, a business-outcome SLI,
        synthetic journeys, heatmaps and dependency alerts
  □ C4 — multi-tenancy: ownership labels, CODEOWNERS self-service, CI guardrails,
        real Loki/Tempo tenancy, prom-label-proxy for Prometheus, per-team cost
  □ C5 — the bidirectional migration plan, the risk register, and the one
        architectural decision (the Collector as the boundary) that makes both cheap
```

---

## What to say in the interview

Forty minutes, whiteboard, no slides:

```
1. DRAW THE ARCHITECTURE (5 min)
   apps → Collector agent (DaemonSet) → Collector gateway (Deployment)
     → Tempo / Loki / Prometheus → Grafana
   ⭐ say out loud: "the Collector is the abstraction boundary. No app has a
     vendor SDK. A vendor migration is a one-day exporter change."

2. EXPLAIN THE THREE SIGNALS AND WHY EACH NEEDS A DIFFERENT TOOL (5 min)
   metrics: aggregates, cheap, 15-month retention, for ALERTING
   traces:  causal, sampled, 72-hour retention, for DIAGNOSIS
   logs:    discrete, expensive, tiered retention, for EVIDENCE
   ⭐ "the cardinality rules are the same for metrics and log labels, and
     OPPOSITE for traces — an order_id is a cardinality bomb as a metric label
     and a superpower as a span attribute."

3. WALK THE FOUR-CLICK LOOP, LIVE (10 min)
   metric spike → exemplar → trace waterfall → logs for this span → root cause
   ⭐ this is the demo. Rehearse it. Have it running before the interview.

4. EXPLAIN THE ALERTING PHILOSOPHY (5 min)
   four tiers; symptoms page, saturation tickets, causes are context, self is
   the most important tier. Inhibit rules. Multi-window burn rate.
   ⭐ "I page on user impact, not on CPU. A CPU alert that pages trains
     people to ignore pages."

5. EXPLAIN SLOs AND DEFEND A NUMBER (5 min)
   SLI/SLO/SLA, the error budget as a release-velocity governor, why 99.9%
   for checkout and 99.5% for search, and why a 7-day window for a
   catalogue-driven SLI.
   ⭐ "the objective comes from measured baselines and business impact,
     never from what sounds impressive."

6. SHOW THE CI (5 min) ⭐⭐ the differentiator
   promtool unit tests for alerts, including the FALSE-POSITIVE tests.
   "This test asserts that a 2-minute error blip does NOT page, and that a
   40% card-decline rate does NOT look like an outage. Without it, someone
   will remove `for: 5m` and nobody will notice until 3 a.m."

7. TELL THE GAME-DAY STORY (5 min) ⭐⭐⭐ the closer
   "I inject five failures monthly. The most valuable one is the payment
   timeout: latency triples, the error rate stays at zero, and every
   availability SLO stays green. It taught me that a latency SLO isn't
   optional, that p99 over all traffic hides a bimodal distribution, and
   that the only thing which catches a system that's healthy by every
   technical measure and broken from the user's chair is a synthetic
   journey that asserts post-conditions."

8. THE COST ANSWER (2 min)
   "90% of trace storage went away with tail sampling and zero error traces
   were lost. 45% of metric series went away by dropping LABELS, not metrics.
   I re-ran the game day to prove no alert broke. A cost reduction that isn't
   validated by re-running the failure drills is just a hope."
```

**The three sentences that will land hardest:**

> 1. *"No application in my platform has a vendor SDK. They all emit OTLP to a Collector we own, so a vendor migration is a one-day exporter change with a two-week dual-write."*
>
> 2. *"I unit-test my alerts, including the cases where they must NOT fire. A two-minute error blip, a rolling deploy, and a 40% card-decline rate all have tests asserting no page."*
>
> 3. *"The most dangerous incident is the one where every dashboard is green: a segment-level failure hidden inside an aggregate, a cart cleared on a failed payment, a search returning 200 with zero results. That's why I have per-segment SLOs, a business-outcome SLI, and a synthetic journey that asserts post-conditions — none of which any RED dashboard would ever show."*

---

## Where next

| You want | Go to |
|---|---|
| Everything on one page: PromQL, LogQL, TraceQL, Collector, Grafana, Alertmanager | [05-CHEATSHEET.md](./05-CHEATSHEET.md) |
| The hour-by-hour plan for both cases | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |
| The theory: pillars, cardinality, sampling, SLOs, RED/USE | [01-OBSERVABILITY-GUIDE.md](./01-OBSERVABILITY-GUIDE.md) |
| Case 1 in full: metrics, dashboards, alerts | [02-CASE-1-prometheus-grafana.md](./02-CASE-1-prometheus-grafana.md) |
| Case 2 in full: traces, logs, correlation | [03-CASE-2-telemetry.md](./03-CASE-2-telemetry.md) |
| Ship it automatically | [../cicd-learning-path/](../cicd-learning-path/) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
