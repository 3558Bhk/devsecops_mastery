# 🎯 CASE 2 · THE DEPLOYMENT TARGETS — PROGRESSIVE DELIVERY
### Argo Rollouts canary and blue-green on Kubernetes, `AnalysisTemplate`s that actually decide, and the honest limits of Docker as a Case 2 target.

> **The three tool files in this folder answer *what decides*. This file answers *what the target does*.** In Case 1 the target's job was "switch and verify". In Case 2 the target has to **run two versions at once and shift traffic between them** — which is a cluster capability, not a pipeline capability.
>
> **Tool version anchors:** Kubernetes v1.37 · **Argo Rollouts v1.8** · `kubectl-argo-rollouts` v1.8 · Argo CD 3.x (for the GitOps end-state) · NGINX Ingress Controller · Istio/Linkerd optional.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---why-the-target-changes-in-case-2) | ⭐ Why the target changes in Case 2 — a Deployment cannot do this |
| [2](#2--argo-rollouts--the-four-core-objects) | Argo Rollouts — install and the four core objects |
| [3](#3---canary--the-full-manifest-set-for-checkout) | ⭐ Canary — the full manifest set for `checkout` |
| [4](#4---analysistemplate--the-thing-that-decides) | ⭐⭐ `AnalysisTemplate` — the thing that decides |
| [5](#5---blue-green--when-canary-is-the-wrong-tool) | ⭐ Blue-green — when canary is the wrong tool |
| [6](#6---traffic-routing--the-part-everyone-skips) | ⭐⭐ Traffic routing — the part everyone skips |
| [7](#7--per-app-shape-on-a-progressive-target) | Per app shape on a progressive target |
| [8](#8---target-docker--the-honest-limits) | 🐳 Target: Docker — the honest limits |
| [9](#9---rollback-on-a-progressive-target) | ⭐ Rollback on a progressive target — why `abort` is seconds |
| [10](#10--️-run-it-and-prove-it--the-case-2-target-acceptance-checks) | ▶️ Run it and prove it — the Case 2 target acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ Why the target changes in Case 2

```
CASE 1 — a Deployment is enough
   kubectl set image → Kubernetes replaces pods gradually → verify → done
   ⭐ traffic shifts IMPLICITLY, as pods become Ready.
   You cannot STOP at 10%. You cannot measure 10%. You cannot go back
   in seconds — the old pods are already gone.

CASE 2 — a Deployment CANNOT do it
   You need:  90% of traffic on the OLD version
              10% of traffic on the NEW version
              SIMULTANEOUSLY, for N minutes
              then a decision, then either 100% or 0%
   ⛔ A Deployment has ONE pod template. It cannot run two versions
      at a controlled traffic split. That is the whole problem.
```

| Capability | `Deployment` | ⭐ `Rollout` (Argo) |
|---|---|---|
| Rolling update | ✅ | ✅ |
| Run two versions at once | ⛔ only transiently, uncontrolled | ✅ **stable + canary ReplicaSets** |
| Control the traffic percentage | ⛔ no (it follows pod count) | ✅ **steps** |
| Pause indefinitely at a step | ⛔ no | ✅ `pause: {}` |
| ⭐ Run an analysis and decide | ⛔ no | ✅ **`AnalysisTemplate`** |
| Rollback in seconds | ⛔ no — pods must be recreated | ✅ **`abort`** — stable pods never left |
| Blue-green | ⛔ hand-rolled | ✅ built in |

⭐⭐ **The `abort` property is the one that changes your risk posture.** During a canary, the **stable ReplicaSet stays at full size** — Argo shifts *traffic weight*, not pod count. So `abort` is not "roll back a deployment"; it is "set the canary's weight to 0". The stable pods are already running, already warm, already in the endpoint list. Recovery is **seconds**, not minutes. That is what makes prerequisite 1 ("reversible in < 15 min") trivially satisfied rather than aspirational.

```bash
kubectl argo rollouts install     # ⭐ installs the CRDs + controller
kubectl argo rollouts version
# kubectl-argo-rollouts: v1.8.2
```

---

## 2 · Argo Rollouts — the four core objects

| Object | Kind | ⭐ What it is |
|---|---|---|
| **Rollout** | `argoproj.io/v1alpha1 Rollout` | ⭐ replaces your `Deployment`. Same `spec.template`, plus `strategy.canary`/`blueGreen` |
| **AnalysisTemplate** | `argoproj.io/v1alpha1 AnalysisTemplate` | ⭐ a **namespaced**, reusable measurement: queries + thresholds + interval/count |
| **ClusterAnalysisTemplate** | same, cluster-scoped | shared across namespaces |
| **Experiment** | `argoproj.io/v1alpha1 Experiment` | run several variants at once (A/B) — beyond CD's needs |

```
        ┌────────────── Rollout: checkout ──────────────┐
        │  strategy.canary.steps:                       │
        │    setWeight 10 → analysis → pause → setWeight│
        │    25 → analysis → setWeight 50 → analysis →  │
        │    (promote)                                  │
        └──────┬──────────────────────────┬─────────────┘
               │                          │
      ReplicaSet STABLE            ReplicaSet CANARY
      (old digest, 3 pods)         (new digest, 1 pod)
               │                          │
               └──────────┬───────────────┘
                          ▼
                ⭐ TRAFFIC ROUTING (§6)
             nginx / Istio / Linkerd / SMI
                    90% ┊ 10%
```

---

## 3 · ⭐ Canary — the full manifest set for `checkout`

`k8s/checkout/rollout.yaml`

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : an Argo Rollout replacing the Deployment for `checkout` (Go).
#  WHY  : Case 2 needs a controlled traffic split, a pause point, and an
#         automated analysis. A Deployment can do none of the three.
# ═══════════════════════════════════════════════════════════════════════
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: checkout
  namespace: shop-production
spec:
  replicas: 3
  revisionHistoryLimit: 5               # ⭐ how many old ReplicaSets are kept
                                        #   = how far back `undo` can go
  selector:
    matchLabels: { app: checkout }
  template:
    metadata:
      labels: { app: checkout, tier: backend }
    spec:
      imagePullSecrets: [{ name: acr-pull }]
      terminationGracePeriodSeconds: 60
      containers:
        - name: checkout                # ⭐⭐ the name CD's `set image` must match
          image: shopacr.azurecr.io/checkout@sha256:PLACEHOLDER
          ports: [{ containerPort: 9091, name: http }]
          envFrom: [{ configMapRef: { name: checkout-config } }]
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits:   { cpu: 500m, memory: 256Mi }
          startupProbe:                 # Go starts fast — but keep it explicit
            httpGet: { path: /healthz, port: http }
            failureThreshold: 10
            periodSeconds: 2
          readinessProbe:               # ⭐ GATES TRAFFIC
            httpGet: { path: /readyz, port: http }
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet: { path: /healthz, port: http }
            periodSeconds: 15
            failureThreshold: 3
          lifecycle:
            preStop:
              exec: { command: ["/bin/sh","-c","sleep 5"] }
              # ⭐ endpoint removal is ASYNCHRONOUS. Without this a terminating
              #   pod still receives requests → a burst of 502s on every step.

  # ── ⭐⭐ THE CANARY STRATEGY ─────────────────────────────────────────
  strategy:
    canary:
      canaryService:   checkout-canary    # ⭐ points ONLY at canary pods
      stableService:   checkout-stable    # ⭐ points ONLY at stable pods
      trafficRouting:
        plugins:
          argoproj-labs/gatewayAPI:        # or nginx / istio / smi — §6
            httpRoute: checkout-http-route
            namespace: shop-production
      # ⭐ the analysis runs automatically at each `analysis` step
      analysis:
        templates:
          - templateName: checkout-success-rate     # §4
        startingStep: 1                             # ⭐ skip step 0 (setWeight)
        args:
          - name: service-name
            value: checkout
      steps:
        - setWeight: 10                    # ⭐ 10% of traffic to the new digest
        - analysis: {}                     # measure for `interval × count`
        - pause: { duration: 5m }          # ⭐ a soak the pipeline cannot skip
        - setWeight: 25
        - analysis: {}
        - pause: {}                        # ⭐⭐ INDEFINITE PAUSE — this is
                                           #   "pattern 3": canary automatic,
                                           #   full rollout needs a click.
                                           #   DELETE this line for full Case 2.
        - setWeight: 50
        - analysis: {}
        - setWeight: 100                   # promote
      # ── what happens when an analysis FAILS ──────────────────────────
      # ⭐ nothing extra: Argo ABORTS the rollout itself and returns traffic
      #   to stable. That is the rollback — it is built into the target.
```

`k8s/checkout/services.yaml` — ⭐ **two Services, and this is the part everyone gets wrong**

```yaml
# ── the ROOT service — what clients and the Ingress use ────────────────
apiVersion: v1
kind: Service
metadata:
  name: checkout
  namespace: shop-production
spec:
  selector:
    app: checkout            # ⭐ matches BOTH cohorts. Traffic routing (§6)
                             #   decides the split; this Service is the
                             #   fallback if routing is not configured.
  ports: [{ name: http, port: 9091, targetPort: http }]
---
# ── ⭐ STABLE — only the pods serving production traffic ───────────────
apiVersion: v1
kind: Service
metadata:
  name: checkout-stable
  namespace: shop-production
spec:
  selector:
    app: checkout
    # ⭐⭐ Argo injects `rollouts-pod-template-hash` into every pod.
    #   The stable Service selects the STABLE hash automatically — Argo
    #   manages this label. You do NOT hardcode a hash here.
  ports: [{ name: http, port: 9091, targetPort: http }]
---
# ── ⭐ CANARY — only the new pods ──────────────────────────────────────
apiVersion: v1
kind: Service
metadata:
  name: checkout-canary
  namespace: shop-production
spec:
  selector:
    app: checkout
  ports: [{ name: http, port: 9091, targetPort: http }]
```

⭐⭐ **Why two Services matter even with an ingress doing the split:** the `AnalysisTemplate` needs to measure the canary cohort **separately** from the stable cohort. If both cohorts sit behind one Service with one set of metrics labels, you cannot compute `canary error rate − stable error rate` — the strongest signal available (§4). The two Services give your metrics a cohort dimension.

---

## 4 · ⭐⭐ `AnalysisTemplate` — the thing that decides

**This is where Case 2's judgement lives.** Not in the pipeline — in the cluster.

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : the automated verdict for a checkout canary.
#  WHY  : in Case 1 a human looked at a dashboard. This IS that look,
#         encoded. Every threshold here replaced a judgement.
# ═══════════════════════════════════════════════════════════════════════
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: checkout-success-rate
  namespace: shop-production
spec:
  args:
    - name: service-name
      value: checkout
    - name: prometheus-address
      value: http://prometheus.monitoring.svc.cluster.local:9090

  metrics:
    # ── M1 · ⭐⭐ CANARY vs STABLE ERROR RATE — the primary signal ─────
    - name: error-rate-delta
      interval: 60s                  # ⭐ how often to sample
      count: 10                      # ⭐ how many samples → 10 minutes total
      failureLimit: 2                # ⭐⭐ how many FAILED samples abort
                                     #   (count=10, failureLimit=2 → 8 of 10
                                     #    must pass. This is the noise filter.)
      successCondition: result[0] < 0.005      # ⭐ the DELTA, not a rate
      provider:
        prometheus:
          address: "{{args.prometheus-address}}"
          query: |
            (
              sum(rate(http_requests_total{
                namespace="shop-production",
                service="{{args.service-name}}-canary",
                code=~"5.."}[2m]))
              /
              clamp_min(sum(rate(http_requests_total{
                namespace="shop-production",
                service="{{args.service-name}}-canary"}[2m])), 0.0001)
            )
            -
            (
              sum(rate(http_requests_total{
                namespace="shop-production",
                service="{{args.service-name}}-stable",
                code=~"5.."}[2m]))
              /
              clamp_min(sum(rate(http_requests_total{
                namespace="shop-production",
                service="{{args.service-name}}-stable"}[2m])), 0.0001)
            )
            # ⭐⭐ WHY A DELTA AGAINST `stable` RATHER THAN A FIXED THRESHOLD:
            #   both cohorts see the SAME hour, day, traffic mix and
            #   dependencies. The only difference is the code.
            #   A fixed "error rate < 1%" pages on Monday morning traffic
            #   and sleeps through a 3 a.m. regression — both in one week.
            # ⭐ clamp_min avoids divide-by-zero when a cohort is idle.

    # ── M2 · ⭐ p99 LATENCY, AS A RATIO ───────────────────────────────
    - name: latency-ratio
      interval: 60s
      count: 10
      failureLimit: 2
      successCondition: result[0] < 1.5        # ⭐ RATIO, not milliseconds
      provider:
        prometheus:
          address: "{{args.prometheus-address}}"
          query: |
            histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{
              namespace="shop-production",
              service="{{args.service-name}}-canary"}[2m])) by (le))
            /
            clamp_min(histogram_quantile(0.99, sum(rate(
              http_request_duration_seconds_bucket{
              namespace="shop-production",
              service="{{args.service-name}}-stable"}[2m])) by (le)), 0.001)
            # ⭐ ratios survive load changes; absolute milliseconds do not.

    # ── M3 · ⭐⭐ IS THERE ENOUGH SIGNAL? (the gate people forget) ─────
    - name: minimum-volume
      interval: 60s
      count: 3
      failureLimit: 3                # ⛔ fail CLOSED — no volume, no promotion
      successCondition: result[0] >= 200
      provider:
        prometheus:
          address: "{{args.prometheus-address}}"
          query: |
            sum(increase(http_requests_total{
              namespace="shop-production",
              service="{{args.service-name}}-canary"}[2m]))
            # ⭐⭐ WITHOUT THIS, a service with 4 requests/minute "passes"
            #   every analysis, because 0 errors out of 40 requests looks
            #   perfect. The analysis is not weak — it is MEANINGLESS.
            #   Failing closed means low-traffic services cannot be Case 2,
            #   which is the correct answer.

    # ── M4 · SATURATION (a memory leak shows here first) ──────────────
    - name: memory-growth
      interval: 120s
      count: 5
      failureLimit: 1
      successCondition: result[0] < 0.9
      provider:
        prometheus:
          address: "{{args.prometheus-address}}"
          query: |
            max(container_memory_working_set_bytes{
              namespace="shop-production",
              pod=~"{{args.service-name}}-.*"})
            /
            max(kube_pod_container_resource_limits{
              namespace="shop-production",
              pod=~"{{args.service-name}}-.*", resource="memory"})
            # ⭐ > 90% of the limit = about to be OOMKilled

    # ── M5 · ⭐ A REAL BUSINESS ENDPOINT, not just /healthz ───────────
    - name: smoke-business-endpoint
      interval: 60s
      count: 5
      failureLimit: 0                # ⛔ ZERO tolerance — this is a probe
      successCondition: result[0] == 200
      provider:
        job:
          metadata:
            labels: { app: canary-smoke }
          spec:
            backoffLimit: 0
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: smoke
                    image: curlimages/curl:8.17.0
                    command:
                      - sh
                      - -c
                      - |
                        code=$(curl -fsS -o /dev/null -w '%{http_code}' \
                          -X POST "http://checkout-canary.shop-production.svc:9091/checkout" \
                          -H 'content-type: application/json' \
                          -d '{"sku":"SMOKE-1","quantity":1}')
                        echo "$code" > /tmp/result
                        # ⭐⭐ /readyz returning 200 while every business route
                        #   500s is the failure mode that defeats canaries.
                        #   Probe the thing users actually call.
```

### 4.1 ⭐ The five `AnalysisTemplate` settings that decide whether it works

| Setting | ⭐ Meaning | Getting it wrong |
|---|---|---|
| `interval` | how often to sample | too short → correlated samples, no independence |
| `count` | how many samples | `count: 1` = a single coin flip |
| ⭐⭐ `failureLimit` | how many samples may fail before the metric fails | `failureLimit: 0` with `count: 10` → one blip aborts a good release. ⭐ `failureLimit: 2` of 10 is the usual balance |
| ⭐ `successCondition` | the pass rule, evaluated on `result[0]` | a PromQL returning **no rows** makes `result[0]` absent → the metric **errors**, it does not pass |
| `inconclusiveLimit` | how many runs may be inconclusive | ⭐ the "not enough data" escape hatch |

```
⭐⭐ THE `failureLimit` INTUITION:
   count: 10, failureLimit: 0  → 10 of 10 must pass. One transient blip
                                  aborts a perfectly good release.
                                  → people disable the analysis.
   count: 10, failureLimit: 2  → 8 of 10 must pass. Absorbs noise, still
                                  catches a real 20%-error regression within
                                  2–3 minutes.                    ← ⭐ START HERE
   count: 10, failureLimit: 9  → the analysis never fails. Decorative.
```

### 4.2 Reading the result

```bash
kubectl argo rollouts get rollout checkout -n shop-production --watch
# Name:            checkout
# Status:          ✗ Degraded
# Message:         RolloutAborted: metric 'error-rate-delta' assessed Failed
# Strategy:        Canary
#   Step:          Paused at 1/8 (canaryAnalysis)
# Images:          shopacr.azurecr.io/checkout@sha256:OLD (stable)
#                  shopacr.azurecr.io/checkout@sha256:NEW (canary)  ← weight 10%
# Replicas:        Stable: 3  Canary: 1

# ⭐ the actual numbers behind the verdict
kubectl -n shop-production get analysisrun -l rollouts.argoproj.io/rollout-name=checkout \
  -o jsonpath='{.items[-1:].metadata.name}'
kubectl -n shop-production get analysisrun <NAME> -o yaml | \
  yq '.status.metricResults[] | {name, measurements: [.measurements[] | {value, phase}]}'
# ⭐⭐ THIS is the record of the machine's decision — the Case 2 equivalent
#   of Case 1's approval log. Archive it.
```

---

## 5 · ⭐ Blue-green — when canary is the wrong tool

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata: { name: shop-api, namespace: shop-production }
spec:
  replicas: 3
  strategy:
    blueGreen:
      activeService:  shop-api-active     # ⭐ what the Ingress points at
      previewService: shop-api-preview    # ⭐ the new version, testable
      autoPromotionEnabled: false         # ⭐⭐ PAUSE before switching
      autoPromotionSeconds: 300           # (or promote after 5m automatically)
      scaleDownDelaySeconds: 600          # ⭐ keep the OLD pods 10 min after
                                          #   the switch — instant rollback
      prePromotionAnalysis:               # ⭐ analyse BEFORE the switch
        templates: [{ templateName: shop-api-readiness }]
      postPromotionAnalysis:              # ⭐ and AFTER
        templates: [{ templateName: shop-api-success-rate }]
```

| | Canary | ⭐ Blue-green |
|---|---|---|
| Traffic split | gradual, by weight | ⛔ **all at once** |
| Two versions running | yes, both serving | yes, but only one **serving** |
| Resource cost | ⭐ ~1 extra pod | ⛔ **2× the fleet** |
| Blast radius if wrong | 10% | ⛔ **100%** |
| Rollback speed | ⭐ seconds (`abort`) | ⭐ seconds (re-point the Service) |
| Best for | stateless HTTP services with measurable per-request outcomes | ⭐ **schema/state coupling, long warm-up, "must verify the whole fleet before any user sees it"** |

⭐ **When blue-green is the right answer:**
- **JVM services with a long warm-up** (`shop-api`): JIT compilation, connection pools and caches mean the first 60 s are unrepresentative. A canary measures a *cold* cohort against a *warm* one and concludes the new version is slower — a false negative. Blue-green's `prePromotionAnalysis` measures the **whole** new fleet while it is still taking no traffic.
- ⭐ **Anything where a partial fleet is inconsistent** — in-memory session state, a leader election, a single-writer queue consumer.
- When you need to run the **full integration suite** against the new version before any user touches it — `previewService` exists for exactly that.

⭐ **When canary is the right answer:** stateless HTTP services with real traffic volume, where a 10% cohort produces enough samples in 10 minutes to be statistically meaningful. `checkout`, `payment-mock`.

---

## 6 · ⭐⭐ Traffic routing — the part everyone skips

**Argo Rollouts shifts traffic through a router. Without one configured, `setWeight: 10` does nothing** — the canary pods simply join the Service's endpoint list and receive traffic **proportional to pod count**, which at 1 canary / 3 stable is 25%, not 10%, and changes as pods churn.

| Router | Mechanism | ⭐ Verdict |
|---|---|---|
| **None** | pod-count proportion | ⛔ not a canary. Do not pretend it is |
| ⭐ **NGINX Ingress** (`argoproj-labs/gatewayAPI` or the nginx plugin) | `canary-weight` annotation | ✅ simplest thing that genuinely works |
| **Istio** | `VirtualService` weights | ✅ the most precise; adds a mesh |
| **Linkerd** | `TrafficSplit` (SMI) | ✅ lighter than Istio |
| **SMI** | `TrafficSplit` CRD | ✅ provider-neutral |
| **AWS ALB / GCP / Azure AGC** | cloud LB weights | ✅ if you are on that cloud |

```yaml
# ⭐ NGINX Ingress — the minimum real traffic routing
apiVersion: argoproj.io/v1alpha1
kind: Rollout
spec:
  strategy:
    canary:
      trafficRouting:
        nginx:
          stableIngress: checkout-ingress       # ⭐ your existing Ingress
          additionalIngressAnnotations:
            canary-by-header: X-Canary          # ⭐ opt-in header routing too
```

```
⭐ WHAT ARGO DOES FOR YOU:
   it sets `nginx.ingress.kubernetes.io/canary: "true"` and
   `nginx.ingress.kubernetes.io/canary-weight: "10"` on a SECOND ingress
   pointing at checkout-canary, and updates the weight at each step.
   You never edit those annotations yourself.

⭐ VERIFY IT ACTUALLY HAPPENED:
   kubectl -n shop-production get ingress -o custom-columns=\
   'NAME:.metadata.name,CANARY:.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary,WEIGHT:.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight'
```

```bash
# ⭐ PROVE THE SPLIT with 100 requests — the check that ends arguments
for i in $(seq 1 100); do
  curl -fsS -o /dev/null -w '%{header_json}' https://checkout.shop/healthz 2>/dev/null
done | grep -c NEW_DIGEST_MARKER
# better: have each version emit its digest in a response header
#   X-App-Digest: sha256:41ab…
# then:  for i in $(seq 1 200); do curl -sI https://checkout.shop/healthz \
#          | awk '/x-app-digest/{print $2}'; done | sort | uniq -c
# ⭐ expect roughly 180 OLD / 20 NEW at a 10% weight.
#   If you see 150/50, your "10% canary" is really a pod-count split (§6).
```

⭐⭐ **Add `X-App-Digest` to every service's responses.** It is three lines of middleware, and it turns "which version served this request?" from a log-correlation exercise into a `curl -I`. During a canary it is the only way to attribute an error to a cohort from outside the cluster.

---

## 7 · Per app shape on a progressive target

| Shape | App | ⭐ Strategy | Why |
|---|---|---|---|
| 🔵 **FE only** | `shop-ui` | **canary** *or* plain rolling | ⭐ static files — no per-request state. The risk is browser caching, not the server. A canary works if the ingress sets `X-App-Digest` |
| 🟢 **BE, Go** | `checkout`, `payment-mock` | ⭐ **canary** | stateless, fast start-up, measurable per-request |
| 🟢 **BE, Java** | `shop-api` | ⭐ **blue-green** | JVM warm-up makes a canary cohort unrepresentative; plus a schema |
| 🟢 **BE, worker** | `order-worker` | ⛔ **neither — plain rolling** | a queue consumer cannot take 10% of *traffic*. It takes 10% of *messages*, which you cannot route |
| 🟡 **FE + BE** | P10 | BE blue-green **then** FE canary | ⭐ backend first, and the pair verified end to end |
| 🟠 **Polyglot** | P11/P12 | per-service, as above | each service gets the strategy its failure mode needs |
| 🗄️ **Data tier** | P13 | ⛔ **StatefulSet, `OnDelete`, manual** | 🔒 Case 1 permanently — a data directory upgrade is not reversible |

### 7.1 ⭐ The worker problem — why `order-worker` cannot be canaried

```
⛔ A CANARY WORKS BY ROUTING 10% OF REQUESTS TO THE NEW VERSION.
   A queue consumer does not receive routed requests. It COMPETES for
   messages. Run 1 new + 3 old consumers and the new one gets ~25% of
   MESSAGES — but you cannot choose which, you cannot route by header,
   and a bad message is consumed ONCE and may be unrecoverable.

✅ WHAT WORKS INSTEAD:
   1. a separate CONSUMER GROUP / queue for the canary, fed by a copy of
      production traffic (shadow traffic)
   2. ⭐ a feature flag inside the new version, so both versions consume
      but only one acts
   3. plain rolling update + idempotent handlers + a strong post-deploy
      watch on queue depth and DLQ count
   4. 🔒 or just Case 1 — a human approves, and the human is the analysis
```

⭐ **The honest conclusion:** `order-worker` belongs in Case 1, and the reason is *structural*, not cultural. This is exactly the "prerequisite 3 fails" case from [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) §6 — you cannot detect a regression from metrics within a canary window because there is no canary window.

### 7.2 Shape C — the pair, on a progressive target

```
1. shop-api  (blue-green)  → prePromotionAnalysis → SWITCH → postPromotionAnalysis
                                    ⛔ fail → auto-promotion is off, old fleet
                                       is still active. Nothing happened.
2. ⭐ verify the PAIR — curl the FE, have it call the BE
3. shop-ui   (canary 10%)  → analysis → 100%
                                    ⛔ fail → abort. The FE returns to stable
                                       in seconds. The BE stays new — which
                                       is SAFE, because expand/contract means
                                       the new BE serves the old FE.
```

⭐⭐ **That last line is why expand/contract is a prerequisite for progressive delivery, not just for rollback.** If the backend removed `/api/v1/orders` in the same release, aborting the frontend canary would leave new frontends... no — it would leave **old** frontends against a **new** backend that no longer serves them. The abort would be worse than the failure.

---

## 8 · 🐳 Target: Docker — the honest limits

⭐ **Docker on a single host is a poor Case 2 target.** Not because it cannot work, but because three of Case 2's requirements are structurally hard:

| Case 2 requirement | On Kubernetes | 🐳 On a single Docker host |
|---|---|---|
| Run two versions at a controlled traffic split | ⭐ Argo Rollouts + an ingress | ⛔ hand-rolled: two Compose projects + nginx `split_clients` |
| Measure cohorts separately | cohort labels in metrics | ⭐ container-name labels — works, but you build it |
| Rollback in seconds | `abort` | ✅ actually fine — the old container is still running |
| Enough replicas for a 10% cohort | trivial | ⛔ at 1 replica, 10% is impossible |

```nginx
# ⭐ the Docker-host equivalent of a canary — nginx split_clients
http {
  map $request_uri $backend {
    default "stable";
  }
  split_clients "${remote_addr}${request_uri}" $variant {
    10%       "canary";      # ⭐ 10% of requests
    *         "stable";
  }
  upstream stable { server 127.0.0.1:9091; }
  upstream canary { server 127.0.0.1:9191; }   # the new container
  server {
    location / { proxy_pass http://$variant; }
  }
}
```

```bash
#!/usr/bin/env bash
# canary-docker.sh — ⭐ the honest, working Docker-host canary
set -euo pipefail
NEW="${1:?digest}"

# 1 · start the canary ALONGSIDE the stable container, on a different port
docker run -d --name checkout-canary --network shop-net -p 9191:9091 \
  -e APP_ENV=production "$NEW"

# 2 · wait for readiness — `--wait` does not exist for `docker run`, so poll
for i in $(seq 1 30); do
  curl -fsS http://localhost:9191/readyz && break; sleep 2
done

# 3 · ⭐ shift 10% of traffic (nginx split_clients reads a reloaded config)
sed -i 's/^\s*10%/    10%/' /etc/nginx/conf.d/shop.conf && nginx -t && nginx -s reload

# 4 · soak, measuring BOTH cohorts
sleep 600
CANARY_ERR=$(docker logs checkout-canary --since 10m 2>&1 | grep -c ' 5[0-9][0-9] ' || true)
STABLE_ERR=$(docker logs checkout-stable --since 10m 2>&1 | grep -c ' 5[0-9][0-9] ' || true)
CANARY_TOT=$(docker logs checkout-canary --since 10m 2>&1 | grep -cE ' [0-9]{3} ' || true)
echo "canary: $CANARY_ERR/$CANARY_TOT   stable: $STABLE_ERR"

# 5 · decide
if [ "$CANARY_TOT" -lt 200 ]; then
  echo "⛔ INCONCLUSIVE — only $CANARY_TOT requests. Failing CLOSED."
  docker rm -f checkout-canary; exit 1
fi
if [ $(( CANARY_ERR * 100 / CANARY_TOT )) -gt 1 ]; then
  echo "⛔ canary error rate too high — removing it"
  docker rm -f checkout-canary          # ⭐ rollback = seconds, it never left
  exit 1
fi

# 6 · promote: the canary BECOMES stable
docker rm -f checkout-stable
docker rename checkout-canary checkout-stable
nginx -s reload
echo "✅ promoted $NEW"
```

⭐ **The verdict to state out loud:** if you are doing canary analysis seriously, you are re-implementing a small Argo Rollouts in bash. **That is a signal to move to Kubernetes** — or, if the estate genuinely is one host and three services, to accept **Case 1** and let a human be the analysis. Both are defensible; a half-built bash canary is not.

---

## 9 · ⭐ Rollback on a progressive target

| Situation | ⭐ Command | Time | What happens |
|---|---|---|---|
| Analysis failed mid-canary | `kubectl argo rollouts abort <r> -n <ns>` | **seconds** | canary weight → 0; stable pods never left |
| You want the previous version back | `kubectl argo rollouts undo <r> -n <ns>` | ~30 s | a new step back in history |
| Explicit known-good digest | `kubectl argo rollouts set image <r> <c>=<prev-digest>` | ~60 s | ⭐ **unambiguous** — prefer this |
| Blue-green, after the switch | re-point `activeService`, or `undo` | seconds | ⭐ `scaleDownDelaySeconds` kept the old fleet alive |
| ⛔ `kubectl rollout undo` | — | — | **does not apply to a Rollout.** It is a Deployment verb |

```bash
# ⭐⭐ THE ORDER THAT MATTERS
kubectl argo rollouts abort  checkout -n shop-production   # 1 · stop the bleeding
kubectl argo rollouts get rollout checkout -n shop-production   # 2 · confirm Stable
# 3 · THEN investigate. Not before.
kubectl -n shop-production get analysisrun -o yaml | yq '.items[-1].status.metricResults'
```

| Rule | ⭐ Why |
|---|---|
| `abort` before `undo` | `abort` restores traffic instantly; `undo` starts a new rollout |
| ⭐ `revisionHistoryLimit: 5` on the Rollout | bounds how far `undo` can go — with `1`, one bad release erases the good one |
| ⭐ `scaleDownDelaySeconds: 600` on blue-green | keeps the old fleet warm for 10 min = instant rollback |
| ⛔ Never `kubectl delete rollout` | deletes the pods too |
| ⭐ Record the analysisrun | it is the Case 2 audit artifact |

---

## 10 · ▶️ Run it and prove it — the Case 2 target acceptance checks

```bash
NS=shop-production; R=checkout

# 1 · Argo Rollouts is installed
kubectl argo rollouts version && kubectl get crd rollouts.argoproj.io

# 2 · the Rollout replaced the Deployment
kubectl -n $NS get rollout $R -o jsonpath='{.spec.strategy.canary.steps}{"\n"}'
kubectl -n $NS get deploy $R 2>&1 | grep -q NotFound && echo "✅ no Deployment"

# 3 · ⭐⭐ TRAFFIC ROUTING IS ACTUALLY CONFIGURED
kubectl -n $NS get rollout $R -o jsonpath='{.spec.strategy.canary.trafficRouting}{"\n"}'
# ⛔ if this is EMPTY, `setWeight: 10` does nothing and you have no canary

# 4 · both Services exist and select different cohorts
kubectl -n $NS get svc ${R}-stable ${R}-canary

# 5 · the AnalysisTemplate exists and has the volume gate
kubectl -n $NS get analysistemplate ${R}-success-rate \
  -o jsonpath='{.spec.metrics[*].name}{"\n"}'
# ⭐ must include: error-rate-delta latency-ratio minimum-volume

# 6 · ⭐ PROVE THE SPLIT — 200 requests, count the digests
for i in $(seq 1 200); do
  curl -sI https://checkout.shop/healthz | awk '/x-app-digest/{print $2}'
done | sort | uniq -c
# ⭐ expect ~180 stable / ~20 canary at weight 10

# 7 · ⭐⭐ THE DRILL — a bad digest, end to end
#    build a checkout whose /readyz is 200 but whose /checkout 500s 20% of
#    the time, publish it, let CD set the image, and watch:
kubectl argo rollouts get rollout $R -n $NS --watch
#    expect: Status ✗ Degraded
#            Message: RolloutAborted: metric 'error-rate-delta' assessed Failed
#            Replicas: Stable 3, Canary 0     ← ⭐ traffic restored

# 8 · the analysisrun records WHY
kubectl -n $NS get analysisrun -l rollouts.argoproj.io/rollout-name=$R \
  -o jsonpath='{.items[-1:].metadata.name}{"\n"}'
kubectl -n $NS describe analysisrun <NAME> | grep -A3 'error-rate-delta'

# 9 · rollback took seconds, not minutes
kubectl -n $NS get rollout $R -o jsonpath='{.status.abortedAt}{"\n"}'

# 10 · ⭐ what is running, one command
kubectl -n $NS get rollout $R \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="checkout")].image}{"\n"}'
```

⭐⭐ **Checks 3 and 6 are the two that catch the most common lie in Case 2.** A pipeline can report "canary at 10% analysed and promoted" while `trafficRouting` is empty and the real split was a 25% pod-count accident. **If you cannot measure the split from outside the cluster, you do not have a canary.**

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⭐ `setWeight` has no effect | `trafficRouting` is not configured | §6 |
| The canary gets ~25%, not 10% | pod-count proportion, no router | §6 |
| The analysis errors immediately | ⛔ the PromQL returned **no rows** → `result[0]` is absent | add `clamp_min(...)`, or a `or vector(0)` fallback |
| The analysis always passes | `failureLimit` too high, or `successCondition` compares the wrong direction | §4.1 |
| ⭐ Good releases are aborted | `failureLimit: 0` with `count: 10` — one blip kills it | `failureLimit: 2` |
| The analysis never fails | `count: 1` — a single sample | `count: 10`, `interval: 60s` |
| `INCONCLUSIVE` forever | traffic below `minimum-volume`'s threshold | ⭐ extend the window, or **move the service to Case 1** |
| The canary cohort is slower and fails latency | ⭐ JVM warm-up — a cold cohort vs a warm one | blue-green (§5), or exclude the first 2 minutes |
| `abort` leaves canary pods running | they scale down on their own, over ~30 s | watch `kubectl argo rollouts get rollout --watch` |
| ⛔ `kubectl rollout undo` says "not found" | it is a **Rollout**, not a Deployment | `kubectl argo rollouts undo` (§9) |
| `undo` cannot reach the good version | `revisionHistoryLimit` too low | set it to 5 (§9) |
| The Rollout is stuck `Progressing` | a `pause: {}` with no duration — ⭐ that is an **indefinite** pause | `kubectl argo rollouts promote` (pattern 3), or remove the step for full Case 2 |
| The stable Service selects canary pods | the selector lacks the hash label Argo manages | ⭐ do **not** hardcode `rollouts-pod-template-hash`; let Argo manage it (§3) |
| Metrics have no `service=` label | the ServiceMonitor/scrape config does not relabel by Service | fix the scrape config — the whole analysis depends on the cohort dimension |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Convert `checkout`'s Deployment into a Rollout with a 10→25→50→100 canary, and explain what you lose by keeping the Deployment |
| **T2** | Create the `-stable` and `-canary` Services and prove that your metrics can tell the cohorts apart |
| **T3** | Write an `AnalysisTemplate` with a canary-vs-stable error-rate **delta** and a p99 **ratio** — not fixed thresholds |
| **T4** | Add the `minimum-volume` metric and justify `failureLimit: 3` with `count: 3` |
| **T5** | Tune `interval` / `count` / `failureLimit` and explain what each wrong value produces |
| **T6** | Configure NGINX traffic routing and **prove** the 10% split from outside the cluster |
| **T7** | Convert `shop-api` to blue-green and justify it against canary |
| **T8** | Explain why `order-worker` cannot be canaried, and give the three things that work instead |
| **T9** | Implement the Docker-host canary (§8) and state honestly when you would use it |
| **T10** | ⭐⭐ Run the drill: a `/checkout` handler that 500s on 20% of requests while `/readyz` stays 200. Report the Rollout status, the analysisrun verdict, the time from breach to traffic restored, and what `revisionHistoryLimit` did |

---

# ✅ ANSWERS

**T1.** §3. Change `apiVersion` to `argoproj.io/v1alpha1`, `kind` to `Rollout`, add `strategy.canary` with `canaryService`/`stableService`, `trafficRouting`, `analysis`, and the `steps` list; keep `spec.template` **exactly as it was** — ⭐ a Rollout is a Deployment plus a strategy, so the pod spec, probes, resources and `preStop` all carry over unchanged. Then `kubectl apply` and delete the old Deployment (⭐ not the other way round — applying a Rollout with the same name as an existing Deployment fails, because the kinds differ). **What you lose by keeping the Deployment:** the ability to run two versions at a **controlled** traffic split; the ability to **pause** at 10% and measure; the ability to have the cluster **decide** via an `AnalysisTemplate`; and — the property that changes your risk posture — **rollback in seconds**. With a Deployment, `rollout undo` recreates pods: scheduling, image pull, start-up, warm-up, readiness. With a Rollout, `abort` sets a weight to 0 on pods that are *already running and already warm*, because the stable ReplicaSet never scaled down. ⭐ That is the difference between "reversible in ~2 minutes, hopefully" and "reversible in ~5 seconds, always" — and prerequisite 1 in [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) is written in those terms.

**T2.** §3's `services.yaml`: the root `checkout` Service selects `app: checkout` (both cohorts — it is the fallback if routing is unconfigured), and `checkout-stable` / `checkout-canary` are declared with `spec.selector: {app: checkout}`. ⭐ **Do not hardcode `rollouts-pod-template-hash`** — Argo injects that label into every pod and manages the stable/canary Service selectors itself; a hardcoded hash breaks on the next release. **Proving the metrics can tell the cohorts apart** is the actual test, and it is where most attempts fail:

```bash
curl -s 'http://prometheus.monitoring.svc:9090/api/v1/query' \
  --data-urlencode 'query=sum by (service) (rate(http_requests_total{namespace="shop-production"}[2m]))' \
  | jq '.data.result[] | {service: .metric.service, rps: .value[1]}'
# ⭐ you must see BOTH "checkout-stable" and "checkout-canary" as separate
#   series. If you see only "checkout", your scrape config relabels by the
#   root Service and the AnalysisTemplate's queries will return NO ROWS —
#   which makes the metric ERROR rather than pass (§11).
```

The scrape config needs `kubernetes_sd_configs` on **endpoints** with a relabel keeping `__meta_kubernetes_endpoint_service_name` as `service`. Without that cohort dimension, canary-vs-stable comparison is impossible and you are back to fixed thresholds — which is what §4 exists to avoid.

**T3.** §4, metrics M1 and M2. **M1 — error-rate delta:** `(canary 5xx rate) − (stable 5xx rate)`, with `successCondition: result[0] < 0.005`. **M2 — p99 ratio:** `canary p99 / stable p99`, with `successCondition: result[0] < 1.5`. ⭐ **Why these two forms specifically:** both cohorts see the same hour, day-of-week, traffic mix and downstream dependencies — the *only* difference is the code — so a delta isolates the change. A fixed `error rate < 1%` fails in both directions within the same week: Monday 09:00 traffic is 8× normal so 1% of it is 8× the errors (rejects good code), and Tuesday 03:00 traffic is 1/20th so a full outage of one endpoint is 0.2% overall (accepts bad code). **Latency must be a ratio rather than milliseconds** for the same reason: p99 varies with load, so an absolute threshold is really a load threshold. Two implementation details that decide whether it works: `clamp_min(denominator, 0.0001)` so an idle cohort does not divide by zero, and the metric label must be the **cohort Service** name (`checkout-canary` / `checkout-stable`) — which is what T2 established.

**T4.** §4, metric M3: `sum(increase(http_requests_total{service="checkout-canary"}[2m]))` with `successCondition: result[0] >= 200`, `count: 3`, `interval: 60s`, ⭐ `failureLimit: 3`. **`failureLimit: 3` with `count: 3` means all three samples must pass — i.e. the metric never tolerates a failure.** That is deliberate and it is the opposite of the tuning you want for M1/M2: **for a noise-filter metric you want tolerance; for a "is there any signal at all" metric you want none.** If two of three samples show fewer than 200 requests, the analysis genuinely does not have data, and averaging that away would let a service with no traffic "pass" — which is Case 2 in name only. ⭐ **Why the gate exists at all:** without it, a service handling 4 requests/minute produces `0 errors out of 40`, which satisfies `error-rate-delta < 0.005` perfectly and promotes every time. The analysis is not weak in that situation — it is **meaningless**, because one failure is 2.5% and two is 5%. Failing closed means such a service *cannot* be Case 2, which is the correct answer, and it is the signal to move it back to [`../case-1-continuous-delivery/README.md`](../case-1-continuous-delivery/README.md). **The one exception worth trying first:** extend the window to 60 minutes (~240 requests) and switch M1 from a *rate* rule to a *count* rule ("any 5xx in the canary cohort fails") — a real gate at low volume, just a slower one.

**T5.** §4.1. The three settings and what each wrong value produces:
- **`interval`** — sampling period. ⛔ Too short (5 s) and successive samples are **correlated**: they measure the same requests, so `count: 10` gives you one observation wearing ten hats, and `failureLimit` loses its meaning as a noise filter. ⛔ Too long (10 m) and a regression runs for ten minutes before the first sample. ✅ 60 s is right for a 2-minute PromQL window.
- **`count`** — number of samples. ⛔ `count: 1` is a single coin flip: one transient blip aborts a good release, and you learn nothing about variance. ✅ `count: 10` at 60 s = a 10-minute analysis with ten independent-ish observations.
- ⭐⭐ **`failureLimit`** — how many samples may fail. `count: 10, failureLimit: 0` → 10 of 10 must pass → **one blip aborts a good release** → people disable the analysis, which is worse than no analysis. `count: 10, failureLimit: 2` → 8 of 10 → absorbs noise but still catches a real 20%-error regression within 2–3 minutes. **Start here.** `count: 10, failureLimit: 9` → the analysis never fails → decorative.
- ⭐ Plus two that are easy to miss: **`successCondition` evaluates `result[0]`**, so a PromQL returning **no rows** makes the metric **error** rather than pass (§11) — always add `clamp_min` or `or vector(0)`; and **`inconclusiveLimit`** is the "not enough data" escape hatch, distinct from failure — a metric returning no value N times is inconclusive, not failed, and you decide what inconclusive means (⭐ for M3 it should mean *fail*).

**T6.** §6. Add `trafficRouting.nginx.stableIngress: checkout-ingress` to the Rollout's canary strategy; Argo then creates a **second** Ingress with `nginx.ingress.kubernetes.io/canary: "true"` and `canary-weight: "10"` pointing at `checkout-canary`, and updates the weight at each step — ⭐ you never edit those annotations yourself. **Proving it from outside the cluster** requires the app to emit its own digest, so first add three lines of middleware setting `X-App-Digest: sha256:…` on every response. Then:

```bash
for i in $(seq 1 200); do curl -sI https://checkout.shop/healthz \
  | awk 'tolower($1)=="x-app-digest:"{print $2}'; done | sort | uniq -c
# ⭐ expect ~180 stable / ~20 canary
```

**If you see ~150/~50, your "10% canary" is a pod-count accident**: with `trafficRouting` empty, the canary pod simply joins the Service's endpoint list and receives 1 of 4 requests = 25%. ⭐⭐ **That is the most common lie in Case 2** — the pipeline logs "canary at 10%, analysed, promoted" while the real split was 25% and varied with pod churn. Two checks expose it: `kubectl get rollout -o jsonpath='{.spec.strategy.canary.trafficRouting}'` must be **non-empty**, and the 200-request count must match the configured weight. **If you cannot measure the split from outside the cluster, you do not have a canary.**

**T7.** §5. `strategy.blueGreen` with `activeService: shop-api-active`, `previewService: shop-api-preview`, ⭐ `autoPromotionEnabled: false`, `scaleDownDelaySeconds: 600`, and both `prePromotionAnalysis` and `postPromotionAnalysis`. **Justification against canary, three reasons:**
1. ⭐ **JVM warm-up makes a canary cohort unrepresentative.** JIT compilation, connection-pool establishment and cache filling mean the first 60 s of a Java pod are its slowest. A canary measures a **cold** cohort against a **warm** stable cohort and concludes the new version is slower — a false negative that aborts good releases, which is how analyses get disabled. Blue-green's `prePromotionAnalysis` measures the **whole new fleet** while it takes no traffic, so warm-up is complete before the verdict.
2. ⭐ **A partial Java fleet can be inconsistent** — in-memory caches, `@Scheduled` leaders, Flyway locks. Two versions running simultaneously against one database is a state you must reason about; blue-green makes only one fleet active at a time.
3. ⭐ **The preview Service is a real test target.** You can run the full integration suite against `shop-api-preview` before any user touches it — which is the closest thing to Case 1's "verify in staging" that Case 2 can offer, inside production.

**The cost, stated honestly:** blue-green needs **2× the fleet** during the switch, and if the analysis is wrong the blast radius is **100%**, not 10%. That is why `autoPromotionEnabled: false` matters — it is *pattern 3* from [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) §7 (canary/pre-prod automatic, full rollout needs a click), and it is the right default for a stateful Java service. `scaleDownDelaySeconds: 600` is what makes rollback instant: the old fleet stays warm for ten minutes after the switch.

**T8.** §7.1. ⛔ **A canary works by routing 10% of *requests* to the new version. A queue consumer does not receive routed requests — it competes for messages.** Run one new and three old consumers and the new one gets roughly 25% of *messages*, but you cannot choose which, cannot route by header, cannot make the split stable, and — the decisive problem — **a bad message is consumed once and may be unrecoverable**. There is also no per-cohort HTTP metric to analyse, so prerequisite 3 ("detect a regression from metrics within the canary window") fails structurally: there is no canary window.

**Three things that work instead:**
1. ⭐ **Shadow traffic** — a separate consumer group / queue fed by a *copy* of production messages. The canary processes them and its outcomes are compared, but never committed. Real coverage, zero user risk; the cost is building the copy path and making side effects suppressible.
2. ⭐ **A feature flag inside the new version** — both versions consume, but only one *acts*. This makes the rollout a config change rather than a deployment, so rollback is instant and per-message rather than per-pod.
3. **Plain rolling update + idempotent handlers + a strong post-deploy watch** on queue depth, consumer lag and DLQ count. ⭐ Note that idempotency is a *deploy* requirement regardless: a rolling update redelivers some messages, so non-idempotent handlers corrupt data on every deploy, canary or not.
4. 🔒 **Or Case 1** — a human approves, and the human *is* the analysis.

**The honest conclusion:** `order-worker` belongs in Case 1, and the reason is structural, not cultural. Saying so is a stronger answer than describing a canary you cannot actually route traffic to.

**T9.** §8. The bash canary: start the new digest as `checkout-canary` on port 9191 **alongside** the running stable container, poll `/readyz` (`docker run` has no `--wait`), shift 10% via nginx `split_clients` + `nginx -s reload`, soak 10 minutes counting 5xx **per container** from `docker logs --since 10m`, apply the `minimum-volume` rule (⛔ `CANARY_TOT < 200` → INCONCLUSIVE → fail closed), and promote by `docker rm -f checkout-stable && docker rename checkout-canary checkout-stable`. Rollback is genuinely fast — `docker rm -f checkout-canary` — because the stable container never stopped.

**When I would use it, honestly:** a single-host internal tool, an edge device, a homelab, a dev/staging box, or an estate of one to three services where the operational cost of a cluster exceeds the value of progressive delivery. ⭐ **When I would not:** as soon as you find yourself writing cohort-aware metric collection, weighted routing, analysis thresholds and abort logic in bash, **you are re-implementing a small Argo Rollouts by hand** — without its CRDs, its status reporting, its `revisionHistoryLimit`, or anyone else's ability to read it. That is the signal to move to Kubernetes. **And the third option, which is the right one most often:** if the estate really is one host and three services, accept **Case 1** and let a human be the analysis. A person reading `docker stats` and an error log is a better gate than 80 lines of untested bash. Both "move to Kubernetes" and "stay in Case 1" are defensible; a half-built bash canary is not, because it produces the *appearance* of automated safety with none of the verification.

**T10.** ⭐⭐ **The drill:** build `checkout` so `/readyz` returns 200 unconditionally while `/checkout` returns 500 on 20% of calls; publish it through CI; let CD run `kubectl argo rollouts set image`.

- **Rollout status:** `kubectl argo rollouts get rollout checkout --watch` shows `Status: ✗ Degraded`, `Message: RolloutAborted: metric 'error-rate-delta' assessed Failed`, `Step: Paused at 1/8 (canaryAnalysis)`, and — the important line — `Replicas: Stable: 3  Canary: 0`. ⭐ Note what did **not** catch it: the `startupProbe`, the `readinessProbe` and the CD pipeline's `/readyz` smoke test all passed, because they probe a path that lies. **This is the failure mode that defeats most canaries** — the fix is M5 in §4, a `job` provider that POSTs to the real `/checkout` endpoint with `failureLimit: 0`.
- **The analysisrun verdict:** `kubectl -n shop-production get analysisrun -l rollouts.argoproj.io/rollout-name=checkout` → `describe` shows `error-rate-delta` with ten measurements, `value` ≈ `0.2` against `successCondition: result[0] < 0.005`, `phase: Failed`, and `failureLimit: 2` exceeded by the third sample. `minimum-volume` passed (there was traffic); `latency-ratio` may also have failed. ⭐⭐ **This YAML is the Case 2 audit artifact** — the machine's decision with its evidence, the equivalent of Case 1's approval record. Archive it.
- **Time from breach to traffic restored:** roughly **2–3 minutes to detect** (the `failureLimit: 2` of `interval: 60s` means two failed samples, so ~2 minutes minimum) and **under 10 seconds to restore**, because `abort` sets the canary weight to 0 on pods that were already running while the **stable ReplicaSet never scaled down**. No scheduling, no image pull, no start-up, no warm-up. ⭐ Compare with a Deployment's `rollout undo`: ~60–120 s including pod recreation. That gap — seconds versus minutes — is the entire operational argument for progressive delivery, and it is what makes prerequisite 1 trivially true.
- **What `revisionHistoryLimit` did:** it kept the previous five ReplicaSets, so `kubectl argo rollouts undo` had a good version to return to. ⛔ **With `revisionHistoryLimit: 1`, one bad release garbage-collects the last good ReplicaSet** and `undo` has nowhere to go — you would be forced to `set image` to a digest you had to look up in the audit log, during an incident. Set it to 5 and check that the registry's retention policy also keeps those digests, because a ReplicaSet pointing at a garbage-collected image cannot scale.
- **The aftermath:** CD's `post { failure }` sets the halt flag, so the next five commits produce `NOT_BUILT` runs and **one** page rather than five. A human reads the archived `analysisrun`, adds the business-endpoint probe to CI (⭐ the real fix — a container whose business routes 500 should never have been published), clears the halt, and CD resumes.

⭐ **The lesson to state:** the canary caught a failure that CI, the probes and the smoke test all missed — which is exactly what it is for. But every failure caught at step 1 costs seconds, and this one cost a canary window, a page and a halt. **Case 2's analysis is a safety net, not a substitute for a smoke test that exercises real code. A canary that rarely fires is a canary nobody has tested.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*If you cannot measure the split from outside the cluster, you do not have a canary.*

</div>
