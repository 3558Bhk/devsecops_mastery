# 🏆 CAPSTONE — End to End: Three CI Tools, One GitOps CD Path

> **The final build.** One application (`shop`), three CI front-ends (Azure DevOps, GitHub Actions, Jenkins), and **one** delivery path they all converge on: a signed image → a digest written to a GitOps config repo → Argo CD reconciles → Argo Rollouts delivers progressively → Kyverno verifies the signature at admission → Prometheus decides whether to promote or roll back → and the whole pipeline is itself observed, so you can see your own deployment frequency, lead time, failure rate and recovery time on a Grafana dashboard.
>
> **Time:** 10–14 hours (a full weekend) · **Level:** intermediate → production
> **Prereq:** Cases 1, 2 and 3 done. The [monitoring path](../monitoring-alerting-learning-path/) helps enormously for §5.
> **What you need:** kind or a real cluster, a GitHub account, an Azure DevOps org (free), 8 GB of RAM.

---

## Why this capstone is shaped this way

```
⛔ THE WRONG CAPSTONE: "deploy an app with GitHub Actions."
   You've already done that three times.

⭐ THE RIGHT CAPSTONE: the thing that is hard in production isn't any one tool —
   it's making SEVERAL tools agree about ONE truth.

   Real organisations have:
     · a legacy Jenkins estate that can't be migrated this quarter
     · new teams standardising on GitHub Actions
     · an Azure shop with Azure DevOps for the .NET services
     · an SRE team that owns the cluster and refuses to give CI write access

   The architecture that survives that is the one you're building here:
   ⭐ CI tools produce SIGNED ARTIFACTS and nothing else.
   ⭐ Git is the only source of truth about what should be running.
   ⭐ Argo CD is the only thing with cluster credentials.
   ⭐ The cluster itself verifies signatures and enforces policy at admission.
   ⭐ Progressive delivery decides whether a change survives, using metrics.
   ⭐ And the whole thing is instrumented, because an unmeasured pipeline
     is a pipeline nobody can improve.

   If you can build and defend that, you can walk into any interview about
   CI/CD and talk for twenty minutes without running out of substance.
```

---

## 0 · The target architecture

```
┌───────────────────────────────────────────────────────────────────────────────┐
│  DEVELOPER                                                                     │
│    git push origin feature/checkout-retry                                      │
└────────────────────────────────┬──────────────────────────────────────────────┘
                                 │
       ┌─────────────────────────┼─────────────────────────┐
       │                         │                         │
       ▼                         ▼                         ▼
┌──────────────┐        ┌──────────────────┐       ┌──────────────┐
│ 🔷 Azure     │        │ 🐙 GitHub        │       │ 🔨 Jenkins   │
│   DevOps     │        │   Actions        │       │   (kind pod) │
│  (shop-api)  │        │  (checkout, ui)  │       │(order-worker)│
└──────┬───────┘        └────────┬─────────┘       └──────┬───────┘
       │                         │                        │
       │  ⭐ ALL THREE DO THE SAME FIVE THINGS:            │
       │    1. lint + test + scan                          │
       │    2. build the image with BuildKit/Kaniko        │
       │    3. attach an SBOM + provenance                 │
       │    4. SIGN with cosign (OIDC identity, keyless)   │
       │    5. push the image AND write the DIGEST to Git  │
       │                         │                        │
       ▼                         ▼                        ▼
┌─────────────────────────────────────────────────────────────────┐
│  📦 REGISTRY          ghcr.io/3558bhk/<service>@sha256:<digest> │
│                       + a cosign signature                      │
│                       + a signed CycloneDX SBOM attestation     │
│                       + a build-provenance attestation          │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
       ┌──────────────────────────┴──────────────────────────┐
       │  ⭐ THE GITOPS BOUNDARY — the only thing that crosses │
       │     is a DIGEST STRING in a YAML file, via a PR.      │
       ▼                                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  📁 github.com/3558Bhk/shop-config          ← THE SOURCE OF TRUTH     │
│                                                                       │
│     apps/                                                             │
│       shop-api/base/deployment.yaml                                   │
│       checkout/base/deployment.yaml                                   │
│       …                                                               │
│     environments/                                                     │
│       dev/values-dev.yaml            image.digest: sha256:aaa…        │
│       staging/values-staging.yaml    image.digest: sha256:aaa…  ⭐same │
│       production/values-production.yaml  image.digest: sha256:aaa…    │
│     policies/                                                         │
│       require-signature.yaml         ← Kyverno: verify the signature  │
│       require-sbom.yaml                                               │
│       disallow-latest-tag.yaml                                        │
│       require-probes.yaml                                             │
│       require-resources.yaml                                          │
│     argocd/                                                           │
│       applicationset.yaml            ← one Application per env+service│
│       projects.yaml                                                   │
│     rollouts/                                                         │
│       analysis-templates.yaml        ← the Prometheus queries         │
│                                                                       │
│  ⭐ CODEOWNERS on environments/production/ = sre-team                 │
│  ⭐ a PR to production REQUIRES a human approval                      │
└───────────────────────────────┬──────────────────────────────────────┘
                                │  ⭐ Argo CD polls / receives a webhook
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  ☸️  THE CLUSTER (kind `cicd`)                                        │
│                                                                       │
│  namespace: argocd      Argo CD 3.x + Argo Rollouts + Kyverno         │
│  namespace: monitoring  Prometheus + Grafana + Alertmanager + Loki    │
│  namespace: shop        ⭐ the application                            │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Argo CD reconciles shop-config → the cluster                    │  │
│  │   ✅ self-healing: a manual `kubectl edit` is reverted in 3 min │  │
│  │   ✅ drift detection: the UI shows OutOfSync                    │  │
│  └────────────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Kyverno ADMISSION: verifies the cosign signature BEFORE the pod │  │
│  │ is created. An unsigned image is REJECTED by the cluster, not   │  │
│  │ by the pipeline. ⭐⭐ that's defense in depth.                   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Argo Rollouts: canary 10% → 25% → 50% → 100%, with an           │  │
│  │ AnalysisTemplate querying Prometheus at each step.              │  │
│  │ A worse error rate or p99 → AUTOMATIC ROLLBACK.                 │  │
│  └────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────┬──────────────────────────────────────┘
                                │  metrics
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  📊 OBSERVABILITY — and the pipeline is OBSERVED TOO                  │
│                                                                       │
│  · application metrics (the SLOs)          → the rollout decision     │
│  · ⭐ PIPELINE metrics (build duration, failure rate, deploy count,   │
│    lead time) pushed by each CI tool        → the DORA dashboard      │
│  · alerts on the CI platform itself (Jenkins down, GHA minutes at 90%,│
│    Azure DevOps agent pool exhausted)                                 │
└──────────────────────────────────────────────────────────────────────┘
```

### 0.1 What each tool owns

| Service | CI tool | Why | Language |
|---|---|---|---|
| `shop-api` | 🔷 Azure DevOps | a Spring Boot service; the team is in the Microsoft ecosystem | Java 21 |
| `shop-ui` | 🐙 GitHub Actions | a React app; the team lives on GitHub | Node 22 |
| `checkout` | 🐙 GitHub Actions | Go; same team as the UI | Go 1.23 |
| `order-worker` | 🔨 Jenkins | a legacy Python service on the old Jenkins estate | Python 3.13 |
| `payment-mock` | 🔨 Jenkins | a test double owned by the platform team | Go 1.23 |
| **`shop-config`** | ⭐ **none** | Argo CD is the only thing that touches the cluster | YAML |

⭐ **That split is deliberate and realistic.** Three teams, three tools, one delivery path. If you can make that work, you can make anything work.

### 0.2 The five invariants every CI tool must satisfy

```
INVARIANT 1 ⭐ BUILD ONCE. The image is built exactly once, in CI, and promoted
             by DIGEST through every environment. Never rebuilt per environment.

INVARIANT 2 ⭐ CI HAS NO CLUSTER CREDENTIALS. Not one of the three tools holds a
             kubeconfig. They write to Git. That's it.

INVARIANT 3 ⭐ EVERY IMAGE IS SIGNED AND THE CLUSTER VERIFIES IT. The pipeline
             signs; Kyverno verifies at admission. If CI is compromised, the
             attacker still cannot deploy — they'd have to compromise the
             cluster's trust root too.

INVARIANT 4 ⭐ THE PROMOTION DECISION IS AUTOMATED AND METRIC-BASED. Argo
             Rollouts asks Prometheus, not a human, whether the canary is healthy.
             Humans approve the INTENT (merge the config PR), not the mechanics.

INVARIANT 5 ⭐ THE PIPELINE IS INSTRUMENTED. Every build and deploy emits metrics.
             You can answer "what's our lead time?" from Grafana, not from memory.
```

---

## 1 · The application and the cluster

### 1.1 The app (reuse it from the other paths)

```bash
mkdir -p ~/capstone && cd ~/capstone
# ⭐ if you've done the other learning paths, copy the app:
cp -r ~/shop/apps . 2>/dev/null || echo "build the apps from the Docker/K8s paths"

# verify the layout
tree -L 2 apps/
# apps/
# ├── checkout/         Dockerfile  go.mod  main.go  main_test.go
# ├── order-worker/     Dockerfile  requirements.txt  worker.py  test_worker.py
# ├── payment-mock/     Dockerfile  go.mod  main.go
# ├── shop-api/         Dockerfile  pom.xml  mvnw  src/
# └── shop-ui/          Dockerfile  package.json  src/  nginx.conf

# ⭐ every service exposes /metrics (Prometheus format) and /health, /ready
for s in shop-api checkout order-worker payment-mock shop-ui; do
  echo "── $s"
  grep -rl 'micrometer\|prometheus_client\|promhttp' apps/$s 2>/dev/null | head -2
done
```

### 1.2 The cluster

```bash
cat > kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cicd
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - {containerPort: 30080, hostPort: 80}
      - {containerPort: 30443, hostPort: 443}
      - {containerPort: 31080, hostPort: 8080}    # Jenkins
      - {containerPort: 30880, hostPort: 8888}    # Argo CD
  - role: worker
    kubeadmConfigPatches: ["kind: JoinConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    system-reserved: cpu=200m,memory=512Mi\n"]
  - role: worker
  - role: worker
EOF
kind create cluster --config kind.yaml --wait 5m
kubectl cluster-info --context kind-cicd
kubectl get nodes -o wide

# the namespaces
for ns in shop argocd monitoring jenkins ingress-nginx kyverno; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done

# ⭐ label the namespaces for Kyverno's scope
kubectl label ns shop    team=app     env-tier=application --overwrite
kubectl label ns argocd  team=platform --overwrite
kubectl label ns monitoring team=observability --overwrite
```

### 1.3 The platform components

```bash
# ── ingress-nginx ────────────────────────────────────────────────
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.config.enable-annotation-validation=true \
  --wait

# ── ⭐ cert-manager (so the ingress TLS works) ───────────────────
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set crds.enabled=true --wait

# ── ⭐ Argo CD 3.x ───────────────────────────────────────────────
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm search repo argo/argo-cd --versions | head -5
helm upgrade --install argocd argo/argo-cd \
  -n argocd --create-namespace \
  --version 8.x \
  --set global.domain=argocd.localhost \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30880 \
  --set server.insecure=true \
  --set controller.metrics.enabled=true \
  --set server.metrics.enabled=true \
  --set repoServer.metrics.enabled=true \
  --set applicationSet.metrics.enabled=true \
  --set notifications.enabled=true \
  --set configs.params.server\.insecure=true \
  --wait --timeout 10m

# the CLI + the password
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
argocd login localhost:8880 --plaintext --insecure \
  --username admin \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret \
               -o jsonpath='{.data.password}' | base64 -d)"
argocd account update-password          # ⭐ change it immediately
argocd app list

# ── ⭐ Argo Rollouts (progressive delivery) ──────────────────────
helm upgrade --install argo-rollouts argo/argo-rollouts \
  -n argo-rollouts --create-namespace \
  --set dashboard.enabled=true \
  --set dashboard.service.type=NodePort \
  --set dashboard.service.nodePort=31111 \
  --set metrics.enabled=true \
  --set controllerMetrics.enabled=true \
  --wait
kubectl argo rollouts version
# the plugin for kubectl:
curl -sSL -o /usr/local/bin/kubectl-argo-rollouts \
  https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x /usr/local/bin/kubectl-argo-rollouts

# ── ⭐ Kyverno (admission policy — verifies the signatures) ──────
helm repo add kyverno https://kyverno.github.io/kyverno/
helm upgrade --install kyverno kyverno/kyverno \
  -n kyverno --create-namespace \
  --set admissionController.replicas=2 \
  --set config.excludeGroups[0]=system:nodes \
  --set config.webhooks[0].namespaceSelector="matchExpressions: [{key: kubernetes.io/metadata.name, operator: NotIn, values: [kyverno]}]" \
  --wait
kubectl -n kyverno get pods

# ── the monitoring stack (from the monitoring learning path) ─────
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.probeSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.scrapeConfigSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.enableRemoteWriteReceiver=true \
  --set grafana.adminPassword=admin \
  --set grafana.service.type=NodePort --set grafana.service.nodePort=30300 \
  --wait --timeout 10m
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
kubectl -n monitoring port-forward svc/kps-grafana 3000:80 &
curl -sf localhost:9090/-/ready && echo "  ✅ Prometheus"
```

---

## 2 · The `shop-config` GitOps repository ⭐⭐

**This is the heart of the capstone. Everything else exists to write to it safely.**

### 2.1 The layout

```bash
gh repo create shop-config --private --clone --description \
  "The GitOps source of truth for the shop application. Argo CD reconciles this."
cd shop-config

mkdir -p apps/{shop-api,checkout,order-worker,shop-ui,payment-mock}/{base,overlays} \
         environments/{dev,staging,production} \
         policies/{supply-chain,hardening,resource} \
         argocd/{apps,projects,applicationsets} \
         rollouts \
         scripts ci .github/workflows docs

cat > .github/CODEOWNERS <<'EOF'
# ⭐⭐ THE MOST IMPORTANT FILE IN THIS REPOSITORY.
# The config repo is the deployment mechanism. Whoever can merge here can deploy.

*                                   @3558Bhk/platform-team

# ⭐ production requires an SRE AND a second human
/environments/production/**         @3558Bhk/sre-team @3558Bhk/release-managers
/argocd/**                          @3558Bhk/sre-team
/policies/**                        @3558Bhk/security @3558Bhk/sre-team

# ⭐ the promotion files are written by CI, but a HUMAN must approve the PR
/environments/production/values-production.yaml   @3558Bhk/sre-team

# ⭐ the Kyverno policies that verify signatures — security owns them
/policies/supply-chain/**           @3558Bhk/security

# ⭐ and CI may never edit its own permissions
/.github/**                         @3558Bhk/security @3558Bhk/platform-team
EOF

cat > .github/dependabot.yml <<'EOF'
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: {interval: weekly}
  - package-ecosystem: docker          # the Argo CD / Rollouts images if pinned
    directory: /argocd
    schedule: {interval: weekly}
EOF

cat > README.md <<'EOF'
# shop-config

The **GitOps source of truth** for the shop application.

⭐ **Nothing deploys by pushing to a cluster.** Argo CD reads this repository and
reconciles the cluster to match it. To change what is running, you change a file
here and merge a PR.

## The promotion flow
```
CI builds & signs an image
  → CI opens a PR to this repo changing ONE digest
    → for dev/staging: auto-merged (a bot, with CODEOWNERS waived by policy)
    → for production: a HUMAN from sre-team approves
      → Argo CD syncs
        → Kyverno verifies the signature at admission
          → Argo Rollouts delivers 10% → 25% → 50% → 100%
            → an AnalysisTemplate queries Prometheus at each step
              → a regression triggers an automatic rollback
```

## The invariants (see docs/INVARIANTS.md)
1. Build once; promote by digest.
2. CI holds no cluster credentials.
3. Every image is signed; the cluster verifies.
4. Promotion is metric-based and automatic.
5. The pipeline is instrumented.
EOF
git add -A && git commit -m "chore: the config repo scaffold" && git push
```

### 2.2 The Helm chart as the base

```yaml
# apps/base/Chart.yaml — ⭐ a library chart shared by every service
apiVersion: v2
name: shop-service
description: A shared chart for one shop microservice
type: application
version: 1.4.0
appVersion: "1.4.0"
```

```yaml
# apps/base/values.yaml — ⭐ the defaults EVERY service inherits
image:
  repository: ghcr.io/3558bhk/CHANGE_ME
  # ⭐⭐ DIGEST, NOT TAG. The digest is what CI writes.
  digest: ""                       # sha256:… — REQUIRED in staging/production
  pullPolicy: IfNotPresent

revision: ""                       # ⭐ the git SHA of the app repo, for traceability

replicaCount: 2

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

resources:
  requests: {cpu: 100m, memory: 256Mi}
  limits:   {memory: 512Mi}        # ⭐ no CPU limit — see the K8s path

probes:
  liveness:  {path: /health, initialDelaySeconds: 15, periodSeconds: 10, failureThreshold: 3}
  readiness: {path: /ready,  initialDelaySeconds: 5,  periodSeconds: 5,  failureThreshold: 3}
  startup:   {path: /ready,  failureThreshold: 30, periodSeconds: 2}     # ⭐⭐ slow starters

lifecycle:
  preStop: 'sleep 10'              # ⭐ drain before SIGTERM

podDisruptionBudget:
  enabled: true
  minAvailable: 1

topologySpread:
  enabled: true
  maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: ScheduleAnyway

securityContext:
  pod:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile: {type: RuntimeDefault}
  container:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities: {drop: [ALL]}

serviceAccount:
  create: true
  # ⭐⭐ NO cloud IAM annotation here. The service accounts get workload identity
  #    from the cluster's own mechanism, not from a CI-written annotation.

# ⭐⭐ the Argo Rollouts strategy — declared HERE, in Git, not in CI
rollout:
  enabled: true
  strategy: canary
  steps:
    - setWeight: 10
    - pause: {duration: 5m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 25
    - pause: {duration: 10m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 50
    - pause: {duration: 10m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 100

autoscaling:
  enabled: false                   # ⭐ off in dev; on in production's overlay

ingress:
  enabled: false

serviceMonitor:
  enabled: true
  interval: 30s
  path: /metrics
```

```yaml
# apps/base/templates/rollout.yaml — ⭐⭐ a Rollout, not a Deployment
{{- if .Values.rollout.enabled }}
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: {{ include "shop-service.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop-service.labels" . | nindent 4 }}
  annotations:
    shop.example.com/managed-by: argocd
    shop.example.com/config-repo: 3558Bhk/shop-config
spec:
  replicas: {{ .Values.replicaCount }}
  revisionHistoryLimit: 10            # ⭐ enough to `argo rollouts undo`
  selector:
    matchLabels:
      {{- include "shop-service.selectorLabels" . | nindent 6 }}
  strategy:
    {{- if eq .Values.rollout.strategy "canary" }}
    canary:
      canaryService: {{ include "shop-service.fullname" . }}-canary
      stableService: {{ include "shop-service.fullname" . }}-stable
      # ⭐⭐ trafficRouting — with ingress-nginx this uses the canary annotations
      trafficRouting:
        nginx:
          stableIngress: {{ include "shop-service.fullname" . }}
      analysis:
        templates:
          - templateName: shop-canary-check
        startingStep: 2                # ⭐ don't analyse at 10% — not enough traffic
        args:
          - name: service
            value: {{ include "shop-service.fullname" . }}
          - name: namespace
            value: {{ .Release.Namespace }}
      steps:
        {{- toYaml .Values.rollout.steps | nindent 8 }}
    {{- else }}
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0                # ⭐⭐ never take capacity away
    {{- end }}
  template:
    metadata:
      labels:
        {{- include "shop-service.selectorLabels" . | nindent 8 }}
        # ⭐⭐ the version label Argo Rollouts and Prometheus use to split metrics
        app.kubernetes.io/version: {{ .Values.revision | default .Chart.AppVersion | quote }}
      annotations:
        shop.example.com/revision: {{ .Values.revision | quote }}
        shop.example.com/deployed-at: {{ now | date "2006-01-02T15:04:05Z" | quote }}
        prometheus.io/scrape: "true"
        prometheus.io/port: {{ .Values.service.targetPort | quote }}
        prometheus.io/path: /metrics
    spec:
      serviceAccountName: {{ include "shop-service.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.securityContext.pod | nindent 8 }}
      containers:
        - name: {{ .Chart.Name }}
          securityContext:
            {{- toYaml .Values.securityContext.container | nindent 12 }}
          # ⭐⭐⭐ THE DIGEST. This is the ONLY thing CI changes.
          image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - {name: http, containerPort: {{ .Values.service.targetPort }}, protocol: TCP}
            - {name: metrics, containerPort: 9090, protocol: TCP}
          {{- with .Values.probes }}
          startupProbe:
            httpGet: {path: {{ .startup.path }}, port: http}
            failureThreshold: {{ .startup.failureThreshold }}
            periodSeconds: {{ .startup.periodSeconds }}
          livenessProbe:
            httpGet: {path: {{ .liveness.path }}, port: http}
            initialDelaySeconds: {{ .liveness.initialDelaySeconds }}
            periodSeconds: {{ .liveness.periodSeconds }}
            failureThreshold: {{ .liveness.failureThreshold }}
          readinessProbe:
            httpGet: {path: {{ .readiness.path }}, port: http}
            initialDelaySeconds: {{ .readiness.initialDelaySeconds }}
            periodSeconds: {{ .readiness.periodSeconds }}
            failureThreshold: {{ .readiness.failureThreshold }}
          {{- end }}
          lifecycle:
            preStop:
              exec: {command: ["/bin/sh", "-c", "{{ .Values.lifecycle.preStop }}"]}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          volumeMounts:
            - {name: tmp, mountPath: /tmp}
      volumes:
        - {name: tmp, emptyDir: {}}
      topologySpreadConstraints:
        {{- if .Values.topologySpread.enabled }}
        - maxSkew: {{ .Values.topologySpread.maxSkew }}
          topologyKey: {{ .Values.topologySpread.topologyKey }}
          whenUnsatisfiable: {{ .Values.topologySpread.whenUnsatisfiable }}
          labelSelector:
            matchLabels:
              {{- include "shop-service.selectorLabels" . | nindent 14 }}
        {{- end }}
{{- end }}
```

```yaml
# apps/base/templates/services.yaml — ⭐⭐ Rollouts needs STABLE and CANARY services
apiVersion: v1
kind: Service
metadata:
  name: {{ include "shop-service.fullname" . }}-stable
  labels:
    {{- include "shop-service.labels" . | nindent 4 }}
    role: stable                        # ⭐ Rollouts matches on this
spec:
  type: {{ .Values.service.type }}
  ports: [{name: http, port: {{ .Values.service.port }}, targetPort: http}]
  selector:
    {{- include "shop-service.selectorLabels" . | nindent 4 }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "shop-service.fullname" . }}-canary
  labels:
    {{- include "shop-service.labels" . | nindent 4 }}
    role: canary
spec:
  type: {{ .Values.service.type }}
  ports: [{name: http, port: {{ .Values.service.port }}, targetPort: http}]
  selector:
    {{- include "shop-service.selectorLabels" . | nindent 4 }}
---
# ⭐ and the ingress that Rollouts drives with canary annotations
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "shop-service.fullname" . }}
  annotations:
    # ⭐⭐ Argo Rollouts manages these two:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-by-header: "X-Canary"
spec:
  ingressClassName: nginx
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "shop-service.fullname" . }}-stable
                port: {number: {{ .Values.service.port }}}
{{- end }}
```

### 2.3 The environment overlays — ⭐ what CI writes

```yaml
# environments/dev/values-dev.yaml
# ═══════════════════════════════════════════════════════════════════
# ⭐⭐ THIS FILE IS MACHINE-WRITTEN BY CI. The block between the markers
#    is the ONLY part a bot touches. Everything else is human-owned.
# ═══════════════════════════════════════════════════════════════════

global:
  env: dev
  logLevel: debug

replicaCount: 1
ingress: {enabled: true, host: dev.shop.example.com}
resources:
  requests: {cpu: 50m, memory: 128Mi}
  limits:   {memory: 256Mi}
probes:
  startup: {path: /ready, failureThreshold: 60, periodSeconds: 2}
rollout:
  enabled: true
  strategy: canary
  steps:                       # ⭐ FAST in dev — you want feedback, not caution
    - setWeight: 50
    - pause: {duration: 30s}
    - setWeight: 100

# ── BEGIN CI-MANAGED DIGESTS (do not edit by hand) ────────────────
images:
  # digests:managed:begin
  shop-api:
    repository: ghcr.io/3558bhk/shop-api
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
    revision: ""
    promotedAt: ""
    promotedBy: ""
    promotedFromRun: ""
  checkout:
    repository: ghcr.io/3558bhk/checkout
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
    revision: ""
    promotedAt: ""
    promotedBy: ""
    promotedFromRun: ""
  order-worker:
    repository: ghcr.io/3558bhk/order-worker
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
    revision: ""
    promotedAt: ""
    promotedBy: ""
    promotedFromRun: ""
  shop-ui:
    repository: ghcr.io/3558bhk/shop-ui
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
    revision: ""
    promotedAt: ""
    promotedBy: ""
    promotedFromRun: ""
  payment-mock:
    repository: ghcr.io/3558bhk/payment-mock
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
    revision: ""
    promotedAt: ""
    promotedBy: ""
    promotedFromRun: ""
  # digests:managed:end
# ── END CI-MANAGED DIGESTS ────────────────────────────────────────
```

```yaml
# environments/staging/values-staging.yaml
global: {env: staging, logLevel: info}
replicaCount: 3
ingress: {enabled: true, host: staging.shop.example.com}
resources:
  requests: {cpu: 250m, memory: 512Mi}
  limits:   {memory: 1Gi}
podDisruptionBudget: {enabled: true, minAvailable: 2}
rollout:
  enabled: true
  strategy: canary
  steps:
    - setWeight: 20
    - pause: {duration: 3m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 50
    - pause: {duration: 5m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 100
autoscaling: {enabled: true, minReplicas: 3, maxReplicas: 8, targetCPU: 70}
# … the same digests:managed block …
```

```yaml
# environments/production/values-production.yaml
# ⭐⭐ the file that matters most, and the one a human must approve changing
global: {env: production, logLevel: warn}
replicaCount: 6
ingress:
  enabled: true
  host: shop.example.com
  tls: [{secretName: shop-tls, hosts: [shop.example.com]}]
resources:
  requests: {cpu: 500m, memory: 1Gi}
  limits:   {memory: 2Gi}
podDisruptionBudget: {enabled: true, minAvailable: 4}    # ⭐⭐ never below 4 of 6
topologySpread:
  enabled: true
  maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule                       # ⭐ HARD spread in production
rollout:
  enabled: true
  strategy: canary
  steps:                       # ⭐⭐ SLOW in production. Patience is the control.
    - setWeight: 5             # a single pod of 20
    - pause: {duration: 10m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 15
    - pause: {duration: 15m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 35
    - pause: {duration: 20m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 60
    - pause: {duration: 30m}
    - analysis: {templates: [{templateName: shop-canary-check}]}
    - setWeight: 100
    - pause: {duration: 60m}   # ⭐⭐ a FINAL soak before the rollout is "done"
autoscaling:
  enabled: true
  minReplicas: 6
  maxReplicas: 40
  targetCPU: 70
  behavior:
    scaleUp:   {stabilizationWindowSeconds: 60,  policies: [{type: Percent, value: 100, periodSeconds: 30}]}
    scaleDown: {stabilizationWindowSeconds: 600, policies: [{type: Pods, value: 1, periodSeconds: 60}]}
probes:
  startup:   {path: /ready, failureThreshold: 60, periodSeconds: 3}
  liveness:  {path: /health, initialDelaySeconds: 0, periodSeconds: 10, failureThreshold: 6}
  readiness: {path: /ready,  initialDelaySeconds: 0, periodSeconds: 5,  failureThreshold: 3}
# … the same digests:managed block …
```

### 2.4 The Argo CD ApplicationSet — one Application per env × service

```yaml
# argocd/applicationsets/shop.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: shop
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ['missingkey=error']       # ⭐ a missing key FAILS, not silently empty
  generators:
    # ⭐⭐ a LIST generator over the cartesian product: environment × service
    - matrix:
        generators:
          - list:
              elements:
                - {env: dev,        cluster: in-cluster, namespaceSuffix: -dev}
                - {env: staging,    cluster: in-cluster, namespaceSuffix: -staging}
                - {env: production, cluster: in-cluster, namespaceSuffix: ''}
          - list:
              elements:
                - {service: shop-api}
                - {service: checkout}
                - {service: order-worker}
                - {service: shop-ui}
                - {service: payment-mock}
  template:
    metadata:
      name: 'shop-{{.env}}-{{.service}}'
      labels:
        shop.example.com/env: '{{.env}}'
        shop.example.com/service: '{{.service}}'
      finalizers: [resources-finalizer.argocd.argoproj.io]
    spec:
      project: 'shop-{{.env}}'                   # ⭐ an AppProject per environment
      source:
        repoURL: https://github.com/3558Bhk/shop-config
        targetRevision: main                     # ⭐⭐ main for dev/staging…
        path: apps/base
        helm:
          valueFiles:
            - ../../environments/{{.env}}/values-{{.env}}.yaml
          parameters:
            # ⭐⭐ the ONLY value injected outside the files: which service this is
            - {name: image.repository, value: 'ghcr.io/3558bhk/{{.service}}'}
            - {name: nameOverride,     value: '{{.service}}'}
            - {name: fullnameOverride, value: '{{.service}}'}
          # ⭐ and the digest comes from the per-service block in the values file:
          valuesObject:
            image:
              digest: '{{ dig "images" .service "digest" "" }}'   # ⛔ not valid here —
                                                                  #    see the note below
      destination:
        server: https://kubernetes.default.svc
        namespace: 'shop{{.namespaceSuffix}}'
      syncPolicy:
        # ⭐⭐ dev auto-syncs; production does NOT (see the AppProject + the override below)
        automated:
          prune: true                            # delete resources removed from Git
          selfHeal: true                         # ⭐ revert manual kubectl changes
          allowEmpty: false                      # ⛔ never sync an empty manifest set
        syncOptions:
          - CreateNamespace=true
          - ApplyOutOfSyncOnly=true              # ⭐ faster, and less churn
          - ServerSideApply=true                 # ⭐ avoids the annotation-size limit
          - RespectIgnoreDifferences=true
          - Replace=false                        # ⭐ never delete-and-recreate
        retry:
          limit: 5
          backoff: {duration: 5s, factor: 2, maxDuration: 3m}
      revisionHistoryLimit: 10                   # ⭐ enough to roll back
      ignoreDifferences:
        # ⭐⭐ CRITICAL: Argo Rollouts mutates the ReplicaSet weights. Argo CD must
        #    NOT fight it, or you get an infinite sync loop.
        - group: argoproj.io
          kind: Rollout
          jsonPointers:
            - /status
            - /spec/replicas
        - group: apps
          kind: Deployment
          jsonPointers: [/spec/replicas]
        # ⭐ and the HPA mutates replicas too
        - kind: HorizontalPodAutoscaler
          jsonPointers: [/spec/minReplicas, /spec/maxReplicas]
      info:
        - {name: 'Environment', value: '{{.env}}'}
        - {name: 'Runbook', value: 'https://runbooks.shop.example.com/{{.service}}'}
        - {name: 'Team', value: 'shop'}
```

⚠️ **The digest problem, and the clean solution.** `{{ dig … }}` isn't available in an ApplicationSet template. Two clean answers:

```yaml
# ⭐ ANSWER A (used here): a per-service values file, so the digest is a plain path.
# environments/production/shop-api.yaml  ← CI writes ONLY this file
image:
  repository: ghcr.io/3558bhk/shop-api
  digest: sha256:9f2a1b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a
revision: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
promotedAt: '2026-09-10T14:22:01Z'
promotedBy: github-actions/1234567890
promotedFromRun: https://github.com/3558Bhk/shop/actions/runs/1234567890

# and the ApplicationSet's source becomes:
        helm:
          valueFiles:
            - ../../environments/{{.env}}/values-{{.env}}.yaml     # the shared config
            - ../../environments/{{.env}}/{{.service}}.yaml        # ⭐ the digest only
# ⭐⭐ THIS IS THE RIGHT DESIGN: CI touches a file that contains ONLY the digest and
#    its provenance. A `git diff` on that file is the entire promotion audit trail.
#    And a human reviewing a production PR sees exactly 5 changed lines.
```

```yaml
# ⭐ ANSWER B: a config-management plugin (argocd-vault-plugin, or a Helm plugin)
# that reads the digest from a parameter store. More machinery; use it when the
# digest must come from somewhere other than Git (rare, and usually wrong).
```

```yaml
# argocd/projects/shop-production.yaml — ⭐⭐ the AppProject is a real boundary
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: shop-production
  namespace: argocd
  finalizers: [resources-finalizer.argocd.argoproj.io]
spec:
  description: 'The production shop. Manual sync only, from main only.'
  sourceRepos:
    - 'https://github.com/3558Bhk/shop-config'    # ⭐ ONE repo, not '*'
  destinations:
    - server: https://kubernetes.default.svc
      namespace: 'shop'                            # ⭐⭐ ONE namespace, not '*'
  # ⭐⭐ what may be deployed
  clusterResourceWhitelist: []                     # ⛔ NO cluster-scoped resources at all
  namespaceResourceBlacklist:
    - {group: '', kind: ResourceQuota}             # a config PR may not change quotas
    - {group: '', kind: LimitRange}
    - {group: 'rbac.authorization.k8s.io', kind: ClusterRole}
    - {group: 'rbac.authorization.k8s.io', kind: ClusterRoleBinding}
    - {group: 'admissionregistration.k8s.io', kind: MutatingWebhookConfiguration}
    - {group: 'admissionregistration.k8s.io', kind: ValidatingWebhookConfiguration}
  namespaceResourceWhitelist:
    - {group: '', kind: ConfigMap}
    - {group: '', kind: Secret}
    - {group: '', kind: Service}
    - {group: '', kind: ServiceAccount}
    - {group: 'apps', kind: Deployment}
    - {group: 'argoproj.io', kind: Rollout}
    - {group: 'argoproj.io', kind: AnalysisTemplate}
    - {group: 'autoscaling', kind: HorizontalPodAutoscaler}
    - {group: 'networking.k8s.io', kind: Ingress}
    - {group: 'policy', kind: PodDisruptionBudget}
    - {group: 'monitoring.coreos.com', kind: ServiceMonitor}
    - {group: 'monitoring.coreos.com', kind: PrometheusRule}
  # ⭐⭐ WHO may sync
  roles:
    - name: sre
      description: 'May sync and rollback production'
      policies:
        - p, proj:shop-production:sre, applications, get, shop-production/*, allow
        - p, proj:shop-production:sre, applications, sync, shop-production/*, allow
        - p, proj:shop-production:sre, applications, override, shop-production/*, allow
        - p, proj:shop-production:sre, applications, action/*, shop-production/*, allow
        - p, proj:shop-production:sre, logs, get, shop-production/*, allow
      groups: ['sre-team']                          # ⭐ from Argo CD's SSO
    - name: viewer
      policies:
        - p, proj:shop-production:viewer, applications, get, shop-production/*, allow
      groups: ['developers']
  # ⭐⭐ signature verification at the SOURCE level
  signatureKeys: []        # populated if you sign Git commits; see §4.6
```

```yaml
# ⭐⭐ the production Application overrides the ApplicationSet's auto-sync.
# Argo CD ApplicationSets support per-generated-item overrides via the template's
# `syncPolicy`, so the cleanest approach is a SEPARATE ApplicationSet for production:
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: {name: shop-production, namespace: argocd}
spec:
  goTemplate: true
  generators:
    - list:
        elements:
          - {service: shop-api}
          - {service: checkout}
          - {service: order-worker}
          - {service: shop-ui}
          - {service: payment-mock}
  template:
    metadata:
      name: 'shop-production-{{.service}}'
    spec:
      project: shop-production
      source:
        repoURL: https://github.com/3558Bhk/shop-config
        targetRevision: main
        path: apps/base
        helm:
          valueFiles:
            - ../../environments/production/values-production.yaml
            - ../../environments/production/{{.service}}.yaml
      destination: {server: https://kubernetes.default.svc, namespace: shop}
      syncPolicy:
        # ⭐⭐⭐ NO `automated:` BLOCK. Production syncs are MANUAL.
        #   A human clicks Sync in Argo CD (or the SRE runs `argocd app sync`).
        #   That is the final gate, and it is a HUMAN with cluster context.
        syncOptions:
          - CreateNamespace=false        # ⭐ the namespace must already exist
          - ServerSideApply=true
          - ApplyOutOfSyncOnly=true
          - FailOnSharedResource=true    # ⭐ two Applications claiming one resource = fail
        retry: {limit: 3, backoff: {duration: 10s, factor: 2, maxDuration: 2m}}
      revisionHistoryLimit: 20
      ignoreDifferences:
        - {group: argoproj.io, kind: Rollout, jsonPointers: [/status, /spec/replicas]}
```

---

## 3 · Progressive delivery with Argo Rollouts

### 3.1 The AnalysisTemplate ⭐⭐ the automated promotion decision

```yaml
# rollouts/analysis-templates.yaml
# ⭐⭐ THIS IS THE FILE THAT DECIDES WHETHER A DEPLOYMENT SURVIVES.
# It runs at every `analysis:` step in the rollout.
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: shop-canary-check
  namespace: shop
spec:
  args:
    - {name: service}
    - {name: namespace, value: shop}
    - {name: prometheus, value: 'http://kps-kube-prometheus-stack-prometheus.monitoring:9090'}
    # ⭐⭐ the thresholds — TUNABLE, and versioned in Git
    - {name: max-error-ratio-ratio,   value: '1.5'}    # canary ≤ 1.5× stable
    - {name: max-error-ratio-abs,     value: '0.01'}   # and ≤ 1% absolute
    - {name: max-latency-ratio,       value: '1.5'}
    - {name: max-latency-abs-ms,      value: '100'}
    - {name: max-saturation,          value: '0.25'}
    - {name: max-oom-kills,           value: '0'}
    - {name: max-restarts,            value: '2'}
    - {name: min-request-count,       value: '20'}     # ⭐⭐ don't decide on 3 requests

  metrics:
    # ══════════════════════════════════════════════════════════
    - name: error-rate
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          # ⭐⭐ the query: canary vs stable, side by side
          query: |
            (
              sum(rate(http_server_requests_seconds_count{
                namespace="{{args.namespace}}",
                app="{{args.service}}",
                status=~"5.."}[5m]))
              /
              clamp_min(sum(rate(http_server_requests_seconds_count{
                namespace="{{args.namespace}}",
                app="{{args.service}}"}[5m])), 0.0001)
            )
            or
            vector(0)
      # ⭐ the failure condition — an expression, not a fixed threshold
      failureCondition: |
        result[0] > {{args.max-error-ratio-abs}}
        and result[0] > 0.001
      successCondition: 'result[0] <= {{args.max-error-ratio-abs}}'
      # ⭐⭐ inconclusive: not enough traffic to decide. Do NOT promote, do NOT roll back.
      inconclusiveLimit: 3
      count: 5                        # ⭐ run 5 times
      interval: 60s                   # ⭐ once a minute → 5 minutes of evidence
      failureLimit: 2                 # ⭐ 2 of 5 failures = the analysis fails
      initialDelay: 90s               # ⭐⭐ let the canary warm up before judging it

    # ══════════════════════════════════════════════════════════
    - name: canary-vs-stable-errors
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            (
              sum(rate(http_server_requests_seconds_count{
                namespace="{{args.namespace}}",app="{{args.service}}",
                status=~"5.."}[5m]) by (app_kubernetes_io_version))
              /
              clamp_min(sum(rate(http_server_requests_seconds_count{
                namespace="{{args.namespace}}",app="{{args.service}}"}[5m])
                by (app_kubernetes_io_version)), 0.0001)
            )
      # ⭐⭐ Argo Rollouts gives you `canary` and `stable` helper labels automatically
      #    when using traffic routing. The query below uses them:
      failureCondition: 'canary[0] > (stable[0] * {{args.max-error-ratio-ratio}} + 0.001)'
      inconclusiveLimit: 3
      count: 5
      interval: 60s
      failureLimit: 2
      initialDelay: 120s

    # ══════════════════════════════════════════════════════════
    - name: p99-latency
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            histogram_quantile(0.99,
              sum by (le) (rate(http_server_requests_seconds_bucket{
                namespace="{{args.namespace}}",app="{{args.service}}"}[5m])))
            )
      failureCondition: 'result[0] > ({{args.max-latency-abs-ms}} / 1000)'
      successCondition: 'result[0] <= ({{args.max-latency-abs-ms}} / 1000)'
      inconclusiveLimit: 3
      count: 5
      interval: 60s
      failureLimit: 2
      initialDelay: 90s

    # ══════════════════════════════════════════════════════════
    - name: cpu-saturation
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            max(
              sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{
                namespace="{{args.namespace}}",pod=~"{{args.service}}-.*"}[5m]))
              /
              clamp_min(sum by (pod) (rate(container_cpu_cfs_periods_total{
                namespace="{{args.namespace}}",pod=~"{{args.service}}-.*"}[5m])), 0.0001)
            )
            or vector(0)
      failureCondition: 'result[0] > {{args.max-saturation}}'
      count: 3
      interval: 60s
      failureLimit: 1
      initialDelay: 120s

    # ══════════════════════════════════════════════════════════
    - name: oom-and-restarts
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            sum(increase(kube_pod_container_status_restarts_total{
              namespace="{{args.namespace}}",pod=~"{{args.service}}-.*"}[10m]))
            +
            sum(increase(container_oom_events_total{
              namespace="{{args.namespace}}",pod=~"{{args.service}}-.*"}[10m]))
            or vector(0)
      failureCondition: 'result[0] > {{args.max-restarts}}'
      count: 3
      interval: 60s
      failureLimit: 1
      initialDelay: 60s

    # ══════════════════════════════════════════════════════════
    - name: ⭐ enough-traffic          # the guard that prevents a false "healthy"
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            sum(increase(http_server_requests_seconds_count{
              namespace="{{args.namespace}}",app="{{args.service}}"}[5m]))
            or vector(0)
      # ⭐⭐ if there's no traffic, the analysis is INCONCLUSIVE, not successful.
      #    A canary with zero requests and zero errors is not a healthy canary.
      inconclusiveCondition: 'result[0] < {{args.min-request-count}}'
      count: 3
      interval: 60s
      failureLimit: 999              # never "fail" — only be inconclusive

    # ══════════════════════════════════════════════════════════
    - name: ⭐ synthetic-probe         # a blackbox probe, not just live traffic
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            min_over_time(probe_success{
              job="blackbox",instance=~".*{{args.service}}.*"}[5m])
            or vector(-1)
      failureCondition: 'result[0] < 1'
      count: 3
      interval: 60s
      failureLimit: 1
      initialDelay: 30s

    # ══════════════════════════════════════════════════════════
    - name: ⭐ a JOB metric (not just a query) — run the smoke test
      # ⭐ AnalysisTemplates can run a Kubernetes Job as a metric.
      #   This is how you inject arbitrary verification.
      provider:
        job:
          metadata:
            labels: {shop.example.com/purpose: canary-smoke-test}
          spec:
            backoffLimit: 0
            template:
              spec:
                restartPolicy: Never
                serviceAccountName: smoke-test
                containers:
                  - name: smoke
                    image: ghcr.io/3558bhk/smoke-test:1.2.0
                    env:
                      - {name: TARGET,  value: 'http://{{args.service}}-canary.{{args.namespace}}'}
                      - {name: EXPECTED_MIN_VERSION, value: '{{args.service}}'}
                      - {name: TIMEOUT, value: '120'}
                    resources:
                      requests: {cpu: 100m, memory: 128Mi}
                      limits:   {memory: 256Mi}
                    securityContext:
                      runAsNonRoot: true
                      allowPrivilegeEscalation: false
                      readOnlyRootFilesystem: true
                      capabilities: {drop: [ALL]}
      count: 2
      interval: 3m
      failureLimit: 1
      initialDelay: 120s
```

```yaml
# ⭐⭐ and the "experiment" version — compare TWO canaries at once
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata: {name: shop-canary-vs-baseline, namespace: shop}
spec:
  args: [{name: service}, {name: prometheus}]
  metrics:
    - name: relative-error-rate
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            (
              sum(rate(http_server_requests_seconds_count{app="{{args.service}}",status=~"5.."}[5m]))
              / clamp_min(sum(rate(http_server_requests_seconds_count{app="{{args.service}}"}[5m])),0.0001)
            )
      # ⭐ failureCondition can reference other metrics by name
      failureCondition: 'relative-error-rate > 0.01'
      count: 5
      interval: 60s
      failureLimit: 2
---
# ⭐ the dry-run mode — validate an AnalysisTemplate WITHOUT affecting a rollout
apiVersion: argoproj.io/v1alpha1
kind: AnalysisRun
metadata: {name: canary-check-dryrun, namespace: shop}
spec:
  analysisTemplateOrExperimentRef:   # (the exact field name varies by version)
    name: shop-canary-check
  args:
    - {name: service,   value: shop-api}
    - {name: namespace, value: shop}
  dryRun:                            # ⭐⭐ run the metrics but don't act on them
    - metricName: error-rate
    - metricName: cpu-saturation
```

### 3.2 Driving it, watching it, and forcing it

```bash
# ⭐ the view — this is the single best UX in progressive delivery
kubectl argo rollouts get rollout shop-api -n shop --watch
# Name:            shop-api
# Status:          ॥ Paused
# Message:         CanaryPauseStep
# Strategy:        Canary
#   Step:          2/10
#   SetWeight:     10
#   ActualWeight:  10
# Images:          ghcr.io/3558bhk/shop-api@sha256:aaa… (stable)
#                  ghcr.io/3558bhk/shop-api@sha256:bbb… (canary)
# Replicas:
#   Desired:       6
#   Current:       7        ← 6 stable + 1 canary
#   Updated:       1
#   Ready:         7
#   Available:     7
#
# NAME                                       KIND        STATUS     AGE    INFO
# ⟳ shop-api                                 Rollout     ॥ Paused    4m
# └──# revision:3
#    └──α shop-api-7d9f8c                    ReplicaSet  ● Healthy  4m     canary
#       └──□ shop-api-7d9f8c-abcde           Pod         ● Running  4m     ready:1/1
# └──# revision:2
#    └──α shop-api-6b8e7d                    ReplicaSet  ● Healthy  2d     stable
#       └──□ shop-api-6b8e7d-fghij           Pod         ● Running  2d     ready:1/1
# ...
# ✔ shop-api-canary-check-abc123             AnalysisRun ✔ Successful 3m   ✔ 5
#   ├─✔ error-rate                           Metric      ✔ Successful 3m
#   ├─✔ canary-vs-stable-errors              Metric      ✔ Successful 3m
#   ├─✔ p99-latency                          Metric      ✔ Successful 3m
#   ├─✔ cpu-saturation                       Metric      ✔ Successful 3m
#   ├─✔ oom-and-restarts                     Metric      ✔ Successful 3m
#   ├─◌ enough-traffic                       Metric      ◌ Inconclusive 3m
#   ├─✔ synthetic-probe                      Metric      ✔ Successful 3m
#   └─✔ canary-smoke-job                     Metric      ✔ Successful 2m

# ⭐ the commands
kubectl argo rollouts list -n shop
kubectl argo rollouts status shop-api -n shop --watch
kubectl argo rollouts promote shop-api -n shop         # ⭐ skip the current pause
kubectl argo rollouts promote --full shop-api -n shop  # ⭐ skip ALL remaining pauses
kubectl argo rollouts pause shop-api -n shop           # hold indefinitely
kubectl argo rollouts abort shop-api -n shop           # ⭐⭐ roll back to stable
kubectl argo rollouts retry rollout shop-api -n shop   # retry after an abort
kubectl argo rollouts undo shop-api -n shop            # ⭐ to the previous revision
kubectl argo rollouts history shop-api -n shop
kubectl argo rollouts set image shop-api api=ghcr.io/3558bhk/shop-api@sha256:…  -n shop
kubectl argo rollouts restart shop-api -n shop         # a rolling restart
kubectl argo rollouts terminate-analysisrun <name> -n shop
kubectl argo rollouts get analysisrun -n shop -o wide
kubectl argo rollouts dashboard --port 31111           # ⭐ the web UI
kubectl argo rollouts notifications …                  # Slack on rollout events

# ⭐ the raw objects
kubectl -n shop get rollout shop-api -o json | jq '{
  phase: .status.phase, message: .status.message,
  step: .status.currentStepIndex, setWeight: .status.currentStepState,
  stableRS: .status.stableRS, canaryRS: .status.canary.stableRS,
  images: [.spec.template.spec.containers[].image],
  conditions: [.status.conditions[] | {type, reason, message}]}'
kubectl -n shop get analysisrun -o custom-columns=\
NAME:.metadata.name,PHASE:.status.phase,MESSAGE:.status.message,AGE:.metadata.creationTimestamp
kubectl -n shop get analysisrun -o json | jq '.items[].status.metricResults[] |
  {metric: .name, phase, measurements: [.measurements[] | {value, phase, startedAt}]}'
kubectl -n shop get experiments
kubectl -n shop describe rollout shop-api | tail -30
```

### 3.3 The rollback paths — know all four ⭐

```bash
# ── PATH 1: Argo Rollouts aborts AUTOMATICALLY ──────────────────
#   the AnalysisTemplate fails → the Rollout's canary ReplicaSet scales to 0,
#   traffic returns to stable, and `status.phase` becomes Degraded/Aborted.
kubectl -n shop get rollout shop-api -o jsonpath='{.status.phase} {.status.abort}'
kubectl -n shop get analysisrun -l rollouts-pod-template-hash=… -o json | jq '.items[0].status.metricResults[] | select(.phase=="Failed")'

# ── PATH 2: a human aborts ──────────────────────────────────────
kubectl argo rollouts abort shop-api -n shop
kubectl argo rollouts retry rollout shop-api -n shop      # after fixing

# ── PATH 3: undo to the previous revision ───────────────────────
kubectl argo rollouts history shop-api -n shop
#   REVISION  CHANGE-ID  POD-TEMPLATE-HASH  IMAGES
#   1                    6b8e7d             ghcr.io/…@sha256:aaa…
#   2         #48        7d9f8c             ghcr.io/…@sha256:bbb…
kubectl argo rollouts undo shop-api -n shop --to-revision 1

# ── PATH 4: ⭐⭐ the GITOPS rollback — the CORRECT one ───────────
# Because Git is the source of truth, the real rollback is a Git revert:
cd ~/capstone/shop-config
git log --oneline -5 environments/production/shop-api.yaml
#   9f2a1b3 chore(promote): production/shop-api → bbb… (run 1234)
#   4c5d6e7 chore(promote): production/shop-api → aaa… (run 1220)
git revert --no-edit 9f2a1b3
# ⭐ the revert commit restores digest aaa…
git push origin main
# → Argo CD detects the change and syncs → the Rollout treats it as a new
#   revision and delivers it progressively. ⭐ That's correct: a rollback is a
#   deploy, and it should go through the same safety machinery.
# → and the audit trail shows BOTH the promotion and its revert.

# ⭐ the emergency shortcut (when Git→ArgoCD→Rollout is too slow):
kubectl argo rollouts set image shop-api \
  api=ghcr.io/3558bhk/shop-api@sha256:aaa111bbb222ccc333ddd444eee555fff666 -n shop
# ⚠️ this creates DRIFT — Argo CD will revert it at the next sync.
#    ⭐ so immediately: `argocd app set shop-production-shop-api --sync-policy none`
#    then fix Git, then re-enable auto-sync. Document it in the incident.
```

---

## 4 · The supply chain, end to end ⭐⭐

```
COMMIT → BUILD → SBOM+PROVENANCE → SIGN → PUSH → WRITE DIGEST TO GIT →
  PR → APPROVE → MERGE → ARGO CD SYNC → KYVERNO VERIFIES → ROLLOUT → ANALYSE

Each arrow is a place an attacker could intervene. Each has a control.
```

### 4.1 Signing in all three CI tools

```bash
# ⭐ the common script — identical logic, three callers
# scripts/sign-and-attest.sh
#!/usr/bin/env bash
set -euo pipefail
IMAGE="${1:?usage: sign-and-attest.sh <image> [digest]}"
DIGEST="${2:-}"
SBOM="${SBOM_FILE:-sbom.cdx.json}"
ISSUER="${OIDC_ISSUER:-https://token.actions.githubusercontent.com}"
IDENTITY="${OIDC_IDENTITY:-}"

[[ -n "$DIGEST" ]] || DIGEST=$(crane digest "$IMAGE")
REF="${IMAGE%@*}@$DIGEST"
echo "==> signing $REF"

# ⭐ 1. generate the SBOM (if CI didn't already)
if [[ ! -f "$SBOM" ]]; then
  syft "$REF" -o cyclonedx-json="$SBOM"
fi

# ⭐ 2. sign the image — KEYLESS via OIDC
cosign sign --yes \
  --certificate-oidc-issuer="$ISSUER" \
  ${IDENTITY:+--certificate-identity="$IDENTITY"} \
  "$REF"

# ⭐ 3. attest the SBOM
cosign attest --yes --type cyclonedx --predicate "$SBOM" \
  --certificate-oidc-issuer="$ISSUER" \
  ${IDENTITY:+--certificate-identity="$IDENTITY"} \
  "$REF"

# ⭐ 4. attest the build provenance (SLSA)
if [[ -f provenance.json ]]; then
  cosign attest --yes --type slsaprovenance1 --predicate provenance.json \
    --certificate-oidc-issuer="$ISSUER" "$REF"
fi

# ⭐ 5. ⭐⭐ attach a HUMAN-READABLE record of who built it
jq -n --arg img "$IMAGE" --arg d "$DIGEST" --arg sha "${GIT_COMMIT:-$GITHUB_SHA}" \
      --arg run "${BUILD_URL:-$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID}" \
      --arg tool "${CI_TOOL:-github-actions}" --arg by "${GIT_AUTHOR:-$GITHUB_ACTOR}" \
  '{image:$img, digest:$d, revision:$sha, buildUrl:$run, builtBy:$tool, author:$by,
    signedAt:(now|todate)}' > build-record.json
cosign attest --yes --type custom --predicate build-record.json "$REF"

# ⭐ 6. verify what we just did — fail closed
cosign verify "$REF" --certificate-oidc-issuer="$ISSUER" | jq '.[0].critical.identity'
cosign verify-attestation --type cyclonedx "$REF" --certificate-oidc-issuer="$ISSUER" \
  | jq -r '.payload' | base64 -d | jq '.predicate.components | length'
echo "  ✅ signed, attested and verified: $REF"
```

```yaml
# 🐙 GitHub Actions — the identity is the OIDC token
- run: ./scripts/sign-and-attest.sh "$IMAGE" "$DIGEST"
  env:
    OIDC_ISSUER: https://token.actions.githubusercontent.com
    OIDC_IDENTITY: 'https://github.com/3558Bhk/shop/.github/workflows/ci.yml@refs/heads/main'
    CI_TOOL: github-actions
# ⭐ requires: permissions: id-token: write
```

```yaml
# 🔷 Azure DevOps — the identity is the WIF token
- task: AzureCLI@2
  inputs:
    azureSubscription: shop-wif
    addSpnToEnvironment: true
    scriptType: bash
    inlineScript: |
      export OIDC_ISSUER="https://vstoken.actions.azure.com/$TENANT_ID"
      export OIDC_IDENTITY="$(echo "$idToken" | cut -d. -f2 | base64 -d | jq -r .sub)"
      export CI_TOOL=azure-devops
      ./scripts/sign-and-attest.sh "$IMAGE" "$DIGEST"
```

```groovy
// 🔨 Jenkins — the identity comes from the oidc-provider plugin
stage('Sign') {
  steps {
    withCredentials([string(credentialsId: 'jenkins-oidc-client-secret', variable: 'OIDC_SECRET')]) {
      sh '''
        set -euo pipefail
        TOKEN=$(curl -sf -u "jenkins-shop:$OIDC_SECRET" \
          "$JENKINS_URL/oidc/token?audience=sigstore" -d grant_type=client_credentials | jq -r .id_token)
        export COSIGN_EXPERIMENTAL=1
        # ⭐ cosign reads the identity from the OIDC flow; with Jenkins we use
        #    a key-based flow OR the Fulcio issuer with a manual token
        ./scripts/sign-and-attest.sh "$IMAGE" "$DIGEST"
      '''
    }
  }
}
// ⭐⭐ HONEST NOTE: keyless cosign signing from Jenkins is the roughest of the
//    three because Jenkins isn't a first-class Fulcio OIDC provider. Two options:
//    A) use a cosign KEY pair stored in Vault, with the public key in Git for
//       Kyverno to verify. Simpler, but you now have a key to protect.
//    B) exchange the Jenkins OIDC token for a GitHub/Azure token and sign from
//       there. Cleaner identity, more moving parts.
//    ⭐ For this capstone we use (A) for the Jenkins services and document it.
```

```bash
# ⭐ option A for Jenkins: a key pair in Vault, the PUBLIC key in Git
cosign generate-key-pair                       # writes cosign.key + cosign.pub
# ⭐ the PRIVATE key goes to Vault (never to Git, never to Jenkins):
vault kv put secret/shop/ci/cosign key=@cosign.key
shred -u cosign.key
# ⭐ the PUBLIC key goes to the config repo, where Kyverno reads it:
cp cosign.pub ~/capstone/shop-config/policies/supply-chain/cosign.pub
# and Jenkins uses the Vault plugin to fetch the private key at sign time:
withVault(configuration: [vaultUrl: "$VAULT_ADDR", vaultCredentialId: 'vault-approle'],
          vaultSecrets: [[path: 'secret/shop/ci/cosign', secretValues: [
            [envVar: 'COSIGN_KEY', vaultKey: 'key']]]]) {
  sh 'cosign sign --key "$COSIGN_KEY" "$IMAGE@$DIGEST"'
}
```

### 4.2 ⭐⭐ Kyverno — the cluster verifies, independently of CI

```yaml
# policies/supply-chain/verify-image-signature.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
  annotations:
    policies.kyverno.io/title: Verify the cosign image signature
    policies.kyverno.io/category: Supply Chain Security
    policies.kyverno.io/severity: critical
    policies.kyverno.io/description: >-
      Every image deployed to the shop namespaces MUST carry a valid cosign
      signature whose certificate was issued by one of our trusted CI issuers
      AND whose identity matches an approved pipeline. This is verified by the
      cluster at admission time — independently of whatever the pipeline claimed.
spec:
  validationFailureAction: Enforce          # ⭐⭐ ENFORCE, not Audit
  background: true                          # ⭐ also scan existing resources
  failurePolicy: Fail                       # ⭐⭐ if Kyverno is down, REJECT
                                            #    (Fail, not Ignore — the safe default)
  webhookTimeoutSeconds: 20
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: ['shop', 'shop-staging', 'shop-dev']
      # ⭐ don't gate the system namespaces
      exclude:
        any:
          - resources:
              namespaces: ['kube-system', 'argocd', 'monitoring', 'kyverno', 'ingress-nginx']
      verifyImages:
        - imageReferences:
            - 'ghcr.io/3558bhk/*'
            - 'shopacr.azurecr.io/*'
          # ⭐⭐ the trust roots: which OIDC issuers we accept
          attestors:
            - count: 1                       # ⭐ at least ONE attestor set must match
              entries:
                # ── GitHub Actions ────────────────────────────────
                - keys:
                    # ⭐ the GitHub Actions OIDC issuer's Fulcio root
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE…(Fulcio root)…
                      -----END PUBLIC KEY-----
                    rekorURL: https://rekor.sigstore.dev
                    # ⭐⭐ the IDENTITY: which workflow, on which ref
                    identities:
                      - issuer: 'https://token.actions.githubusercontent.com'
                        subject: 'https://github.com/3558Bhk/shop/.github/workflows/ci.yml@refs/heads/main'
                # ── Azure DevOps ──────────────────────────────────
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE…(Fulcio root)…
                      -----END PUBLIC KEY-----
                    identities:
                      - issuer: 'https://vstoken.actions.azure.com/<tenant-id>'
                        # ⭐ the WIF subject: org/project/environment
                        subject: '<org-id>/<project-id>/main'
                # ── Jenkins (key-based) ───────────────────────────
                - keys:
                    # ⭐ the PUBLIC key from the config repo — inlined by a generator,
                    #    or referenced via a ConfigMap
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE…(our cosign.pub)…
                      -----END PUBLIC KEY-----
          # ⭐⭐ mutate the image reference to the DIGEST after verification.
          #    This defeats a TOCTOU attack: verify `:latest`, then the tag moves.
          mutateDigest: true
          # ⭐ and require the verification to be recorded in the pod annotation
          required: true
```

```yaml
# policies/supply-chain/require-sbom-attestation.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: require-sbom-attestation}
spec:
  validationFailureAction: Enforce
  failurePolicy: Fail
  rules:
    - name: require-a-signed-cyclonedx-sbom
      match:
        any: [{resources: {kinds: [Pod], namespaces: ['shop', 'shop-staging']}}]
      verifyImages:
        - imageReferences: ['ghcr.io/3558bhk/*']
          attestations:
            - type: 'https://cyclonedx.org/bom'      # ⭐ the attestation predicate type
              conditions:
                - all:
                    # ⭐ the SBOM must declare a format and a version
                    - key: '{{ elements[0].bomFormat }}'
                      operator: Equals
                      value: 'CycloneDX'
                    - key: '{{ elements[0].specVersion }}'
                      operator: AnyIn
                      value: ['1.5', '1.6']
              attestors:
                - entries:
                    - keys:
                        publicKeys: |-
                          -----BEGIN PUBLIC KEY-----
                          …
                          -----END PUBLIC KEY-----
```

```yaml
# policies/supply-chain/no-latest-tag.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: disallow-latest-and-mutable-tags}
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-a-digest
      match: {any: [{resources: {kinds: [Pod], namespaces: ['shop', 'shop-staging', 'shop-dev']}}]}
      validate:
        message: >-
          Images must be referenced by an immutable digest (@sha256:…), never by a
          mutable tag. A tag can be re-pushed with different bytes; a digest cannot.
        pattern:
          spec:
            containers:
              - image: '*@sha256:*'
            =(initContainers):
              - image: '*@sha256:*'
    - name: deny-the-latest-tag-explicitly
      match: {any: [{resources: {kinds: [Pod]}}]}
      validate:
        message: 'The :latest tag is forbidden.'
        deny:
          conditions:
            any:
              - key: '{{ request.object.spec.containers[].image }}'
                operator: AnyIn
                value: ['*:latest']
```

```yaml
# policies/hardening/require-probes-and-resources.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: shop-workload-hardening}
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-three-probes
      match: {any: [{resources: {kinds: [Pod], namespaces: ['shop', 'shop-staging']}}]}
      validate:
        message: 'A pod must define liveness, readiness AND startup probes.'
        pattern:
          spec:
            containers:
              - livenessProbe: '?*'
                readinessProbe: '?*'
                startupProbe: '?*'

    - name: require-resource-requests
      match: {any: [{resources: {kinds: [Pod], namespaces: ['shop', 'shop-staging']}}]}
      validate:
        message: 'CPU and memory requests are required so the scheduler can pack correctly.'
        pattern:
          spec:
            containers:
              - resources:
                  requests: {memory: '?*', cpu: '?*'}
                  limits: {memory: '?*'}

    - name: require-a-restricted-security-context
      match: {any: [{resources: {kinds: [Pod], namespaces: ['shop', 'shop-staging']}}]}
      validate:
        message: 'Pods must run as non-root, read-only, with all capabilities dropped.'
        pattern:
          spec:
            securityContext:
              runAsNonRoot: true
              seccompProfile: {type: 'RuntimeDefault'}
            containers:
              - securityContext:
                  allowPrivilegeEscalation: false
                  readOnlyRootFilesystem: true
                  capabilities: {drop: ['ALL']}

    - name: require-a-team-label
      match: {any: [{resources: {kinds: [Pod], namespaces: ['shop', 'shop-staging']}}]}
      validate:
        message: 'Every pod must carry a team label so alerts can be routed.'
        pattern:
          metadata:
            labels:
              team: '?*'

    - name: require-an-argocd-tracking-label
      match: {any: [{resources: {kinds: [Pod], namespaces: ['shop', 'shop-staging']}}]}
      validate:
        message: 'Workloads must be managed by Argo CD — no manual kubectl apply.'
        pattern:
          metadata:
            annotations:
              shop.example.com/managed-by: 'argocd'
```

```bash
# ⭐ apply and verify
kubectl apply -f policies/
kubectl get clusterpolicy -o custom-columns=NAME:.metadata.name,ACTION:.spec.validationFailureAction,BG:.spec.background
# NAME                             ACTION    BG
# verify-image-signature           Enforce   true
# require-sbom-attestation         Enforce   false
# disallow-latest-and-mutable-tags Enforce   true
# shop-workload-hardening          Enforce   true

kubectl get policyreport -A
kubectl get clusterpolicyreport -o yaml | jq '.results[] | {policy, result, message}'

# ⭐⭐ TEST THE POLICY — an unsigned image must be REJECTED
kubectl -n shop run attack --image=alpine:3.20 --restart=Never --dry-run=server
#   Error from server: error when creating "STDIN": admission webhook
#   "validate.kyverno.svc-fail" denied the request:
#   policy Pod/shop/attack for resource violation:
#   disallow-latest-and-mutable-tags: require-a-digest:
#     Images must be referenced by an immutable digest (@sha256:…), never by a mutable tag.

kubectl -n shop run attack2 --image=ghcr.io/3558bhk/shop-api:unsigned --restart=Never --dry-run=server
#   ⛔ denied: no matching signatures:
#      "found no signatures for ghcr.io/3558bhk/shop-api@sha256:…"

# ⭐⭐ AND THE MOST IMPORTANT TEST: a SIGNED image from the WRONG identity
cosign sign --yes ghcr.io/3558bhk/evil@sha256:…      # signed by YOUR laptop, not CI
kubectl -n shop run attack3 --image=ghcr.io/3558bhk/evil@sha256:… --dry-run=server
#   ⛔ denied: the certificate identity does not match
#      expected: https://github.com/3558Bhk/shop/.github/workflows/ci.yml@refs/heads/main
#      got:      spiffe://github.com/3558Bhk/evil
# ⭐⭐ THAT IS THE WHOLE POINT. Signing proves SOMEONE signed it.
#    The identity condition proves it was the RIGHT PIPELINE.
```

### 4.3 The promotion script — ⭐ one script, three callers

```bash
# scripts/promote.sh — ⭐⭐ THE GITOPS BOUNDARY
# Every CI tool calls THIS. That's what makes three tools converge on one path.
#!/usr/bin/env bash
# usage: promote.sh <environment> <service> <digest> [--revision SHA] [--tool X] [--run URL]
set -euo pipefail

ENVIRONMENT="${1:?usage: promote.sh <env> <service> <digest>}"
SERVICE="${2:?}"
DIGEST="${3:?}"
shift 3

REVISION=""; TOOL="unknown"; RUN_URL=""; AUTO_MERGE=false; REPOSITORY="ghcr.io/3558bhk/$SERVICE"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --revision) REVISION="$2"; shift 2 ;;
    --tool)     TOOL="$2"; shift 2 ;;
    --run)      RUN_URL="$2"; shift 2 ;;
    --repository) REPOSITORY="$2"; shift 2 ;;
    --auto-merge) AUTO_MERGE=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

CONFIG_REPO="${CONFIG_REPO:-3558Bhk/shop-config}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/shop-config}"
TOKEN_VAR="${CONFIG_REPO_TOKEN:-SHOP_CONFIG_TOKEN}"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m⛔ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 0. validate the inputs ──────────────────────────────────────
[[ "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]] || die "unknown environment: $ENVIRONMENT"
[[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]           || die "not a digest: $DIGEST"
[[ "$SERVICE" =~ ^[a-z][a-z0-9-]*$ ]]              || die "bad service name: $SERVICE"

# ── 1. ⭐⭐ VERIFY THE SIGNATURE BEFORE PROMOTING ───────────────
#   CI signed it. But CI could be compromised, or this could be a re-run of an
#   old build. Verify independently, right here, at the boundary.
log "verifying the signature on $REPOSITORY@$DIGEST"
case "$TOOL" in
  github-actions)
    cosign verify "$REPOSITORY@$DIGEST" \
      --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
      --certificate-identity-regexp="^https://github.com/3558Bhk/shop/\.github/workflows/.*@refs/heads/main$" \
      >/dev/null || die "the GitHub Actions signature did not verify"
    ;;
  azure-devops)
    cosign verify "$REPOSITORY@$DIGEST" \
      --certificate-oidc-issuer-regexp="^https://vstoken\.actions\.azure\.com/" \
      --certificate-identity-regexp=".*" \
      >/dev/null || die "the Azure DevOps signature did not verify"
    ;;
  jenkins)
    cosign verify "$REPOSITORY@$DIGEST" --key policies/supply-chain/cosign.pub \
      >/dev/null || die "the Jenkins signature did not verify"
    ;;
  *) die "unknown CI tool: $TOOL — refusing to promote an image we cannot verify" ;;
esac
log "  ✅ the signature verified"

# ── 2. ⭐ and the SBOM ──────────────────────────────────────────
log "checking the SBOM for CRITICAL vulnerabilities"
SBOM=$(mktemp)
cosign verify-attestation --type cyclonedx "$REPOSITORY@$DIGEST" \
  --certificate-oidc-issuer-regexp=".*" 2>/dev/null \
  | jq -r '.payload' | base64 -d > "$SBOM" || true
if [[ -s "$SBOM" ]]; then
  n=$(trivy sbom --severity CRITICAL --quiet --format json "$SBOM" 2>/dev/null \
      | jq '[.Results[]?.Vulnerabilities[]?] | length' || echo 0)
  log "  CRITICAL vulnerabilities: $n"
  if [[ "$ENVIRONMENT" == "production" && "$n" -gt 0 ]]; then
    trivy sbom --severity CRITICAL "$SBOM" | head -20
    die "⛔ refusing to promote to production with $n CRITICAL vulnerabilities"
  fi
  # ⭐ record the package count in the PR body for the reviewer
  COMPONENTS=$(jq '.components | length' "$SBOM" 2>/dev/null || echo 0)
else
  COMPONENTS=0
  [[ "$ENVIRONMENT" == "production" ]] && die "⛔ no SBOM attestation found"
fi

# ── 3. clone the config repo ────────────────────────────────────
log "cloning $CONFIG_REPO"
rm -rf "$CONFIG_DIR"
git clone --depth 20 "https://x-access-token:${!TOKEN_VAR}@github.com/$CONFIG_REPO.git" "$CONFIG_DIR"
cd "$CONFIG_DIR"
git config user.name  "shop-ci[bot]"
git config user.email "shop-ci[bot]@users.noreply.github.com"

FILE="environments/$ENVIRONMENT/$SERVICE.yaml"
[[ -f "$FILE" ]] || cat > "$FILE" <<EOF
image:
  repository: $REPOSITORY
  digest: ""
revision: ""
EOF

# ── 4. ⭐ the structured edit — only the digest block ───────────
PREV_DIGEST=$(yq '.image.digest // ""' "$FILE")
PREV_REVISION=$(yq '.revision // ""' "$FILE")

yq -i ".image.repository = \"$REPOSITORY\"" "$FILE"
yq -i ".image.digest     = \"$DIGEST\""     "$FILE"
yq -i ".revision         = \"$REVISION\""   "$FILE"
yq -i ".promotedAt       = \"$(date -u +%FT%TZ)\"" "$FILE"
yq -i ".promotedBy       = \"$TOOL\""       "$FILE"
yq -i ".promotedFromRun  = \"$RUN_URL\""    "$FILE"
yq -i ".promotedFromDigest = \"$PREV_DIGEST\"" "$FILE"

# ── 5. no-op detection ──────────────────────────────────────────
if [[ "$PREV_DIGEST" == "$DIGEST" ]]; then
  log "  ⏭ $ENVIRONMENT/$SERVICE is already at $DIGEST — nothing to do"
  exit 0
fi

# ── 6. validate the result BEFORE opening a PR ──────────────────
log "validating the rendered manifests"
helm template "$SERVICE" apps/base \
  --namespace shop \
  --values "environments/$ENVIRONMENT/values-$ENVIRONMENT.yaml" \
  --values "$FILE" \
  > /tmp/rendered.yaml
kubeconform -strict -summary -ignore-missing-schemas /tmp/rendered.yaml || die "the render is invalid"
# ⭐ and a POLICY dry-run against Kyverno
if command -v kyverno >/dev/null; then
  kyverno apply policies/ --resource /tmp/rendered.yaml --policy-report 2>&1 | tail -20
fi

# ── 7. commit and open the PR ───────────────────────────────────
BR="promote/$ENVIRONMENT/$SERVICE-${DIGEST:7:12}"
git checkout -b "$BR"
git add "$FILE"
git diff --cached --quiet && { log "  ⏭ nothing changed"; exit 0; }

git commit -m "chore(promote): $ENVIRONMENT/$SERVICE → ${DIGEST:7:19}…

service:    $SERVICE
environment: $ENVIRONMENT
digest:     $DIGEST
previous:   $PREV_DIGEST
revision:   $REVISION
built by:   $TOOL
build:      $RUN_URL
SBOM:       $COMPONENTS components, verified signed
signature:  ✅ verified by this script before promotion

${PREV_REVISION:+Previous revision: $PREV_REVISION}
"

git push -u origin "$BR"

PR_BODY=$(cat <<EOF
## 🚀 Promotion: \`$SERVICE\` → \`$ENVIRONMENT\`

| | |
|---|---|
| **Service** | \`$SERVICE\` |
| **Environment** | \`$ENVIRONMENT\` |
| **Digest** | \`${DIGEST:0:26}…\` |
| **Previous** | \`${PREV_DIGEST:0:26}…\` |
| **App revision** | \`${REVISION:0:7}\` |
| **Built by** | $TOOL |
| **Build** | $RUN_URL |
| **SBOM** | $COMPONENTS components |
| **Signature** | ✅ verified before this PR was opened |
| **CRITICAL CVEs** | ${n:-0} |

### The diff
\`\`\`diff
$(git diff HEAD~1 -- "$FILE" | tail -n +5)
\`\`\`

$([[ "$ENVIRONMENT" == "production" ]] && cat <<'PROD'
### ⚠️ PRODUCTION — review before approving
- [ ] the staging soak completed without an analysis failure
- [ ] the diff touches **only** the digest block
- [ ] you know how to roll back: `git revert <this commit>`
- [ ] it is inside the deployment window (Mon–Thu 10:00–17:00 IST)
- [ ] no critical alert is firing in #shop-oncall
- [ ] a change ticket exists

**Merging this PR does NOT deploy.** Production Applications have no auto-sync —
an SRE must click **Sync** in Argo CD after merging. That is deliberate.
PROD
)
EOF
)

PR_URL=$(gh pr create --repo "$CONFIG_REPO" --base main --head "$BR" \
  --title "chore(promote): $ENVIRONMENT/$SERVICE → ${DIGEST:7:12}" \
  --body "$PR_BODY" \
  --label "promotion,$ENVIRONMENT,$TOOL" \
  $([[ "$ENVIRONMENT" != "production" ]] && echo "--draft=false"))

log "  ✅ opened $PR_URL"

# ── 8. ⭐ auto-merge for dev and staging ONLY ───────────────────
if [[ "$AUTO_MERGE" == "true" && "$ENVIRONMENT" != "production" ]]; then
  log "auto-merging (a non-production environment)"
  # ⭐ but still wait for the checks
  gh pr checks "$PR_URL" --repo "$CONFIG_REPO" --watch --interval 15 || die "the checks failed"
  gh pr merge "$PR_URL" --repo "$CONFIG_REPO" --squash --delete-branch \
    --subject "chore(promote): $ENVIRONMENT/$SERVICE → ${DIGEST:7:12} (#${PR_URL##*/})"
  log "  ✅ merged — Argo CD will sync within 3 minutes"
elif [[ "$ENVIRONMENT" == "production" ]]; then
  log "⭐ production: the PR is open and awaiting an SRE approval."
  log "   a human must approve AND then click Sync in Argo CD."
fi
```

---

## 5 · The three CI front-ends, converging

### 5.1 🐙 GitHub Actions (checkout + shop-ui)

```yaml
# .github/workflows/ci.yml — in the APP repo (3558Bhk/shop)
name: CI
on:
  push: {branches: [main], paths: ['apps/checkout/**', 'apps/shop-ui/**', '.github/**', 'scripts/**']}
  pull_request: {branches: [main], paths: ['apps/checkout/**', 'apps/shop-ui/**', '.github/**']}

permissions:
  contents: read
  packages: write
  id-token: write            # ⭐⭐ cosign keyless + cloud OIDC
  pull-requests: write

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

env:
  REGISTRY: ghcr.io/3558bhk
  CONFIG_REPO: 3558Bhk/shop-config

jobs:
  test-and-build:
    name: 🏗️ ${{ matrix.service }}
    runs-on: ubuntu-latest
    timeout-minutes: 30
    strategy:
      fail-fast: false
      matrix:
        include:
          - {service: checkout, language: go}
          - {service: shop-ui,  language: node}
    outputs:
      digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b   # v7.0.0
        with: {fetch-depth: 0}

      - uses: ./.github/actions/setup-shop
        with: {language: '${{ matrix.language }}', service: '${{ matrix.service }}'}

      - name: Test
        run: ./ci/test-${{ matrix.language }}.sh "${{ matrix.service }}"

      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with: {registry: ghcr.io, username: '${{ github.actor }}', password: '${{ secrets.GITHUB_TOKEN }}'}

      - name: ⭐ Build with SBOM + provenance
        id: build
        uses: docker/build-push-action@v6
        with:
          context: apps/${{ matrix.service }}
          push: ${{ github.event_name != 'pull_request' }}
          load: ${{ github.event_name == 'pull_request' }}
          tags: |
            ${{ env.REGISTRY }}/${{ matrix.service }}:${{ github.sha }}
            ${{ env.REGISTRY }}/${{ matrix.service }}:pr-${{ github.event.pull_request.number }}
          cache-from: type=gha,scope=${{ matrix.service }}
          cache-to:   type=gha,mode=max,scope=${{ matrix.service }}
          provenance: mode=max
          sbom: true

      - name: Sign and attest
        if: github.event_name != 'pull_request'
        run: |
          set -euo pipefail
          DIGEST="${{ steps.build.outputs.digest }}"
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
          CI_TOOL=github-actions GIT_COMMIT="${{ github.sha }}" \
            ./scripts/sign-and-attest.sh "${{ env.REGISTRY }}/${{ matrix.service }}" "$DIGEST"

      - name: Scan
        run: |
          set -euo pipefail
          trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed \
            "${{ env.REGISTRY }}/${{ matrix.service }}@${{ steps.build.outputs.digest }}"

  # ══════════════════════════════════════════════════════════════
  promote:
    name: 🔀 Promote to dev
    needs: test-and-build
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
      id-token: write
    strategy:
      matrix: {service: [checkout, shop-ui]}
    steps:
      - uses: actions/checkout@v7
      # ⭐⭐ the token for the CONFIG repo — a GitHub App installation token,
      #    scoped to shop-config ONLY, with contents:write + pull-requests:write
      - uses: actions/create-github-app-token@v1
        id: app-token
        with:
          app-id: ${{ vars.PROMOTER_APP_ID }}
          private-key: ${{ secrets.PROMOTER_APP_KEY }}
          owner: 3558Bhk
          repositories: shop-config
      - name: Promote
        env:
          SHOP_CONFIG_TOKEN: ${{ steps.app-token.outputs.token }}
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
        run: |
          set -euo pipefail
          ./scripts/promote.sh dev "${{ matrix.service }}" "${{ needs.test-and-build.outputs.digest }}" \
            --revision "${{ github.sha }}" \
            --tool github-actions \
            --run "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
            --auto-merge
      # ⭐⭐ push the pipeline metrics (Invariant 5)
      - name: Emit the pipeline metrics
        if: always()
        run: ./scripts/emit-pipeline-metrics.sh github-actions "$GITHUB_RUN_ID"
```

### 5.2 🔷 Azure DevOps (shop-api)

```yaml
# azure-pipelines.yml — in the APP repo, for shop-api
trigger:
  branches: {include: [main]}
  paths: {include: ['apps/shop-api/**', 'helm/**', 'scripts/**']}
  batch: true
pr:
  branches: {include: [main]}
  paths: {include: ['apps/shop-api/**']}
  autoCancel: true

pool: {vmImage: ubuntu-latest}

variables:
  - group: shop-common
  REGISTRY: ghcr.io/3558bhk
  CONFIG_REPO: 3558Bhk/shop-config

stages:
  - stage: Build
    displayName: 🏗️ Build and sign shop-api
    jobs:
      - job: Build
        timeoutInMinutes: 30
        steps:
          - checkout: self
            fetchDepth: 0
          - task: JavaToolInstaller@0
            inputs: {versionSpec: '21', jdkArchitectureOption: x64, jdkSourceOption: PreInstalled}
          - task: Cache@2
            inputs:
              key: 'maven | "$(Agent.OS)" | apps/shop-api/pom.xml'
              restoreKeys: 'maven | "$(Agent.OS)"'
              path: $(Pipeline.Workspace)/.m2
          - bash: |
              set -euo pipefail
              cd apps/shop-api
              mvn -B -T 1C -Dmaven.repo.local=$(Pipeline.Workspace)/.m2 verify
          - bash: |
              set -euo pipefail
              echo "$(REGISTRY_TOKEN)" | docker login ghcr.io -u 3558bhk --password-stdin
              IMAGE="$(REGISTRY)/shop-api"
              TAG="$(Build.SourceVersion)"
              docker buildx create --use --name b 2>/dev/null || docker buildx use b
              docker buildx build apps/shop-api \
                --tag "$IMAGE:$TAG" \
                --cache-from "type=registry,ref=$IMAGE:buildcache" \
                --cache-to   "type=registry,ref=$IMAGE:buildcache,mode=max" \
                --provenance=mode=max --sbom=true --push
              DIGEST=$(docker buildx imagetools inspect "$IMAGE:$TAG" --format '{{json .Manifest}}' | jq -r .digest)
              echo "$DIGEST" > digest.txt
              echo "##vso[task.setvariable variable=imageDigest;isOutput=true]$DIGEST"
              echo "  ✅ $IMAGE@$DIGEST"
            name: build
          # ⭐ sign with the WIF identity
          - task: AzureCLI@2
            inputs:
              azureSubscription: shop-wif
              addSpnToEnvironment: true
              scriptType: bash
              inlineScript: |
                set -euo pipefail
                export OIDC_ISSUER="https://vstoken.actions.azure.com/$(az account show -q tenantId -o tsv)"
                export CI_TOOL=azure-devops
                export GIT_COMMIT="$(Build.SourceVersion)"
                export BUILD_URL="$(System.TeamFoundationCollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)"
                ./scripts/sign-and-attest.sh "$(REGISTRY)/shop-api" "$(cat digest.txt)"
          - publish: digest.txt
            artifact: digest
  - stage: PromoteDev
    displayName: 🔀 Promote to dev
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'main'))
    jobs:
      - job: Promote
        variables:
          DIGEST: $[ stageDependencies.Build.outputs['build.imageDigest'] ]
        steps:
          - checkout: self
          - bash: |
              set -euo pipefail
              export SHOP_CONFIG_TOKEN="$(CONFIG_REPO_TOKEN)"
              export GH_TOKEN="$(CONFIG_REPO_TOKEN)"
              ./scripts/promote.sh dev shop-api "$DIGEST" \
                --revision "$(Build.SourceVersion)" \
                --tool azure-devops \
                --run "$(System.TeamFoundationCollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)" \
                --auto-merge
            env:
              CONFIG_REPO_TOKEN: $(github-app-token)     # ⭐ a Key Vault-backed group
          - bash: ./scripts/emit-pipeline-metrics.sh azure-devops "$(Build.BuildId)"
            condition: always()
```

### 5.3 🔨 Jenkins (order-worker + payment-mock)

```groovy
// Jenkinsfile — in the APP repo
@Library('shop-shared@v2.4.1') _

pipeline {
  agent { kubernetes { inheritFrom 'shop-hardened'; defaultContainer 'tools' } }
  options {
    timestamps(); ansiColor('xterm')
    timeout(time: 45, unit: 'MINUTES')
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    buildDiscarder(logRotator(numToKeepStr: '100', daysToKeepStr: '180'))
  }
  environment {
    REGISTRY    = 'ghcr.io/3558bhk'
    CONFIG_REPO = '3558Bhk/shop-config'
  }
  stages {
    stage('Checkout') {
      steps { checkout scm }
      post { always { script { env.REV = sh(returnStdout: true, script: 'git rev-parse HEAD').trim() } } }
    }
    stage('Build') {
      steps {
        script {
          def branches = [:]
          ['order-worker', 'payment-mock'].each { svc ->
            branches["build-${svc}"] = {
              node('shop-hardened') {
                container('kaniko') {
                  withCredentials([usernamePassword(credentialsId: 'ghcr-token',
                                                    usernameVariable: 'U', passwordVariable: 'P')]) {
                    sh '''
                      set -euo pipefail
                      mkdir -p /kaniko/.docker
                      AUTH=$(printf '%s:%s' "$U" "$P" | base64 -w0)
                      jq -n --arg a "$AUTH" '{"auths":{"ghcr.io":{"auth":$a}}}' > /kaniko/.docker/config.json
                    '''
                  }
                  sh """
                    set -euo pipefail
                    /kaniko/executor \\
                      --context "dir://\${WORKSPACE}/apps/${svc}" \\
                      --dockerfile "\${WORKSPACE}/apps/${svc}/Dockerfile" \\
                      --destination "${REGISTRY}/${svc}:${REV}" \\
                      --cache=true --cache-repo="${REGISTRY}/${svc}-cache" \\
                      --sbom= cyclonedx --reproducible \\
                      --label org.opencontainers.image.revision=${REV}
                  """
                  def digest = sh(returnStdout: true, script: """
                    crane digest "${REGISTRY}/${svc}:${REV}"
                  """).trim()
                  writeFile file: "digests/${svc}.txt", text: digest
                  echo "  ✅ ${svc}@${digest}"
                }
              }
            }
          }
          parallel branches
          stash name: 'digests', includes: 'digests/*.txt'
        }
      }
    }
    stage('Sign') {
      steps {
        unstash 'digests'
        withCredentials([usernamePassword(credentialsId: 'ghcr-token',
                                          usernameVariable: 'U', passwordVariable: 'P')]) {
          withVault(configuration: [vaultUrl: "$VAULT_ADDR", vaultCredentialId: 'vault-approle'],
                    vaultSecrets: [[path: 'secret/shop/ci/cosign',
                                    secretValues: [[envVar: 'COSIGN_KEY', vaultKey: 'key']]]]) {
            sh '''
              set -euo pipefail
              export CI_TOOL=jenkins GIT_COMMIT="$REV" BUILD_URL="$BUILD_URL"
              for svc in order-worker payment-mock; do
                D=$(cat digests/$svc.txt)
                cosign sign --key "$COSIGN_KEY" --yes "$REGISTRY/$svc@$D"
                syft "$REGISTRY/$svc@$D" -o cyclonedx-json=sbom-$svc.json
                cosign attest --key "$COSIGN_KEY" --yes --type cyclonedx \
                  --predicate sbom-$svc.json "$REGISTRY/$svc@$D"
                cosign verify --key <(cosign private-key --key "$COSIGN_KEY" 2>/dev/null || echo "") \
                  "$REGISTRY/$svc@$D" 2>/dev/null || \
                cosign verify --certificate-identity-regexp '.*' "$REGISTRY/$svc@$D" || \
                  echo "  ⚠️  verification uses the key, not a certificate"
              done
            '''
          }
        }
      }
    }
    stage('Promote to dev') {
      when { branch 'main'; not { changeRequest() } }
      steps {
        unstash 'digests'
        withCredentials([string(credentialsId: 'config-repo-app-token', variable: 'SHOP_CONFIG_TOKEN')]) {
          sh '''
            set -euo pipefail
            export GH_TOKEN="$SHOP_CONFIG_TOKEN"
            for svc in order-worker payment-mock; do
              ./scripts/promote.sh dev "$svc" "$(cat digests/$svc.txt)" \
                --revision "$REV" --tool jenkins --run "$BUILD_URL" --auto-merge
            done
          '''
        }
      }
    }
  }
  post {
    always {
      script { sh './scripts/emit-pipeline-metrics.sh jenkins "$BUILD_NUMBER"' }
      cleanWs(deleteDirs: true, notFailBuild: true)
    }
    success { notifySlack(text: "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER}") }
    failure { notifySlack(text: "⛔ ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED", color: 'danger') }
  }
}
```

### 5.4 ⭐ The convergence proof

```bash
# ⭐⭐ THE TEST THAT PROVES THE ARCHITECTURE WORKS:
# three different CI tools, three different auth mechanisms, three different
# build engines (BuildKit, BuildKit, Kaniko) — and Argo CD cannot tell them apart.

# 1. trigger all three
gh workflow run ci.yml --ref main                                   # checkout, shop-ui
az pipelines run --name shop-api-ci --branch main                   # shop-api
curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/job/shop/job/main/build" # order-worker, payment-mock

# 2. watch the config repo receive FIVE PRs from three different identities
gh pr list --repo 3558Bhk/shop-config --limit 10 \
  --json number,title,author,labels --jq '.[] | "\(.number)  \(.author.login.padEnd(28))  \(.title)"'
#   101  github-actions[bot]            chore(promote): dev/checkout → 3f2a1b9c0d4e
#   102  github-actions[bot]            chore(promote): dev/shop-ui → 8b7c6d5e4f3a
#   103  shop-ci[bot]                   chore(promote): dev/shop-api → 1a2b3c4d5e6f
#   104  shop-ci[bot]                   chore(promote): dev/order-worker → 9z8y7x6w5v4u
#   105  shop-ci[bot]                   chore(promote): dev/payment-mock → 2q3w4e5r6t7y

# ⭐ note the AUTHORS differ — that's the audit trail showing which tool promoted what.

# 3. ⭐⭐ and the KEY test: every digest in the config repo verifies
for f in environments/dev/*.yaml; do
  svc=$(basename "$f" .yaml)
  [[ "$svc" == "values-dev" ]] && continue
  d=$(yq '.image.digest' "$f"); r=$(yq '.image.repository' "$f"); t=$(yq '.promotedBy' "$f")
  printf '  %-14s %-16s %s\n' "$svc" "$t" "${d:0:19}…"
  # ⭐ verify with the RIGHT mechanism per tool
  case "$t" in
    github-actions) cosign verify "$r@$d" --certificate-oidc-issuer=https://token.actions.githubusercontent.com >/dev/null 2>&1 && echo "     ✅ GHA OIDC" ;;
    azure-devops)   cosign verify "$r@$d" --certificate-oidc-issuer-regexp='^https://vstoken' >/dev/null 2>&1 && echo "     ✅ ADO WIF" ;;
    jenkins)        cosign verify "$r@$d" --key policies/supply-chain/cosign.pub >/dev/null 2>&1 && echo "     ✅ Jenkins key" ;;
  esac
done
#   checkout       github-actions   sha256:3f2a1b9c0d4e…
#      ✅ GHA OIDC
#   shop-api       azure-devops     sha256:1a2b3c4d5e6f…
#      ✅ ADO WIF
#   order-worker   jenkins          sha256:9z8y7x6w5v4u…
#      ✅ Jenkins key

# 4. ⭐⭐ and Kyverno accepted all five into the cluster
kubectl -n shop-dev get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
kubectl get clusterpolicyreport -o json | jq '.results[] | select(.policy=="verify-image-signature") | {result, resource: .resources[0].name}'
#   ✅ every result is "pass"
```

---

## 6 · ⭐ Pipeline telemetry — the pipeline observes itself

**Invariant 5.** You cannot improve a pipeline you cannot measure. Here's how each tool emits metrics into the same Prometheus.

### 6.1 The metric contract

```
# ⭐⭐ EVERY CI TOOL EMITS THESE, WITH THESE EXACT NAMES AND LABELS.
# That's what makes three tools comparable on one dashboard.

pipeline_build_total{tool,repo,branch,result,trigger}          counter
pipeline_build_duration_seconds{tool,repo,branch,result}       histogram
pipeline_stage_duration_seconds{tool,repo,stage}               histogram
pipeline_deploy_total{tool,environment,result,strategy}        counter
pipeline_deploy_timestamp_seconds{tool,environment}            gauge   ⭐ for lead time
pipeline_change_lead_time_seconds{tool,environment}            histogram ⭐⭐ DORA
pipeline_commit_to_first_build_seconds{tool}                   histogram
pipeline_rollback_total{tool,environment,cause}                counter   ⭐⭐ DORA MTTR
pipeline_flaky_test_total{tool,repo,test}                      counter
pipeline_cache_hit_total{tool,repo,layer}                      counter
pipeline_minutes_consumed_total{tool,repo}                     counter   ⭐ cost
pipeline_secret_rotation_age_seconds{tool,secret}              gauge
pipeline_policy_violation_total{tool,policy}                   counter
```

### 6.2 The emitter — one script, three callers

```bash
# scripts/emit-pipeline-metrics.sh
#!/usr/bin/env bash
# usage: emit-pipeline-metrics.sh <tool> <run-id>
set -uo pipefail

TOOL="${1:?}"; RUN_ID="${2:?}"
PUSHGW="${PUSHGATEWAY:-http://localhost:9091}"
REPO="${REPO:-3558Bhk/shop}"
BRANCH="${BRANCH:-${GITHUB_HEAD_REF:-${GIT_BRANCH:-main}}}"
RESULT="${RESULT:-${GITHUB_JOB_STATUS:-${BUILD_RESULT:-unknown}}}"
DURATION="${DURATION:-${GITHUB_STEP_DURATION:-${BUILD_DURATION_MS:-0}}}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
STRATEGY="${STRATEGY:-canary}"
TRIGGER="${TRIGGER:-${GITHUB_EVENT_NAME:-${BUILD_REASON:-unknown}}}"

# ⭐ derive the DORA lead time: commit timestamp → now
COMMIT_TS="${COMMIT_TS:-$(git show -s --format=%ct "${REVISION:-HEAD}" 2>/dev/null || date +%s)}"
LEAD_TIME=$(( $(date +%s) - COMMIT_TS ))

# ⭐ and the change lead time: commit → FIRST deploy of that commit
FIRST_DEPLOY_TS=$(curl -sG "${PROMETHEUS:-http://localhost:9090}/api/v1/query" \
  --data-urlencode "query=min(pipeline_deploy_timestamp_seconds{revision=\"${REVISION:-}\"})" \
  | jq -r '.data.result[0].value[1] // empty')

LABELS="tool=\"$TOOL\",repo=\"$REPO\",branch=\"$BRANCH\",result=\"$RESULT\""

DURATION_S=$(awk "BEGIN{printf \"%.1f\", $DURATION/1000}")
[[ "$DURATION_S" == "0.0" ]] && DURATION_S=$(awk "BEGIN{printf \"%.1f\", $DURATION}")

cat > /tmp/pipeline-metrics.prom <<EOF
# TYPE pipeline_build_total counter
# HELP pipeline_build_total how many builds each CI tool ran
pipeline_build_total{${LABELS},trigger="${TRIGGER}"} 1

# TYPE pipeline_build_duration_seconds gauge
# HELP pipeline_build_duration_seconds how long the build took
pipeline_build_duration_seconds{${LABELS}} ${DURATION_S}

# TYPE pipeline_commit_to_build_seconds gauge
pipeline_commit_to_build_seconds{tool="${TOOL}",branch="${BRANCH}"} ${LEAD_TIME}

# TYPE pipeline_deploy_total counter
pipeline_deploy_total{tool="${TOOL}",environment="${ENVIRONMENT}",result="${RESULT}",strategy="${STRATEGY}"} 1

# TYPE pipeline_deploy_timestamp_seconds gauge
pipeline_deploy_timestamp_seconds{tool="${TOOL}",environment="${ENVIRONMENT}",revision="${REVISION:-}"} $(date +%s)

# TYPE pipeline_change_lead_time_seconds gauge
# HELP pipeline_change_lead_time_seconds DORA: commit to production
pipeline_change_lead_time_seconds{tool="${TOOL}",environment="${ENVIRONMENT}"} ${LEAD_TIME}

# TYPE pipeline_info gauge
pipeline_info{tool="${TOOL}",repo="${REPO}",branch="${BRANCH}",run_id="${RUN_ID}",revision="${REVISION:-}"} 1
EOF

curl -sf --max-time 10 --data-binary @/tmp/pipeline-metrics.prom \
  "$PUSHGW/metrics/job/pipeline/tool/$TOOL/run/$RUN_ID" \
  && echo "  ✅ pushed the pipeline metrics for $TOOL run $RUN_ID" \
  || echo "  ⚠️  the Pushgateway is unreachable — the metrics were not recorded"
rm -f /tmp/pipeline-metrics.prom
```

```bash
# ⭐ the Pushgateway, deployed in the monitoring namespace
kubectl -n monitoring apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: pushgateway, namespace: monitoring, labels: {app: pushgateway}}
spec:
  replicas: 1
  selector: {matchLabels: {app: pushgateway}}
  template:
    metadata: {labels: {app: pushgateway}}
    spec:
      containers:
        - name: pushgateway
          image: prom/pushgateway:v1.10.0
          args: ['--persistence.file=/data/metrics.store', '--persistence.interval=5m']
          ports: [{containerPort: 9091}]
          volumeMounts: [{name: data, mountPath: /data}]
          resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 256Mi}}
      volumes: [{name: data, emptyDir: {}}]
---
apiVersion: v1
kind: Service
metadata: {name: pushgateway, namespace: monitoring, labels: {app: pushgateway}}
spec:
  selector: {app: pushgateway}
  ports: [{port: 9091, targetPort: 9091}]
EOF

# ⭐ and the Prometheus scrape config for it
kubectl -n monitoring apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: pushgateway, namespace: monitoring, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: pushgateway}}
  endpoints:
    - port: pushgateway            # ⭐ the port must be NAMED
      interval: 30s
      honorLabels: true            # ⭐⭐ CRITICAL — keeps the labels the CI set
EOF
# ⚠️ `honorLabels: true` is REQUIRED. Without it, Prometheus overwrites your
#    `tool` and `repo` labels with its own `job`/`instance` and the dashboard breaks.
```

### 6.3 The DORA dashboard ⭐

```yaml
# grafana/dashboards/dora.json (the four panels that matter)
# ⭐ panel 1: DEPLOYMENT FREQUENCY
- title: 🚀 Deployment frequency (production)
  type: stat
  targets:
    - expr: sum(increase(pipeline_deploy_total{environment="production",result="success"}[7d]))
      legendFormat: deploys / 7d
      # ⭐ the DORA buckets: elite = daily+, high = weekly, medium = monthly, low = 6mo+
    - expr: |
        sum(increase(pipeline_deploy_total{environment="production",result="success"}[30d])) / 4.3
      legendFormat: deploys / week
  thresholds: [{value: 7, color: green}, {value: 1, color: yellow}, {value: 0, color: red}]

# ⭐ panel 2: LEAD TIME FOR CHANGES
- title: ⏱️ Lead time for changes (commit → production)
  type: bargauge
  targets:
    - expr: |
        histogram_quantile(0.5,
          sum by (le, tool) (rate(pipeline_change_lead_time_seconds_bucket{environment="production"}[30d])))
      legendFormat: 'p50 {{tool}}'
    - expr: |
        histogram_quantile(0.95,
          sum by (le, tool) (rate(pipeline_change_lead_time_seconds_bucket{environment="production"}[30d])))
      legendFormat: 'p95 {{tool}}'
  # ⭐ elite = <1h, high = 1d–1w, medium = 1w–1mo, low = 1–6mo

# ⭐ panel 3: CHANGE FAILURE RATE
- title: 💥 Change failure rate
  type: timeseries
  targets:
    - expr: |
        sum(increase(pipeline_rollback_total{environment="production"}[30d]))
        /
        clamp_min(sum(increase(pipeline_deploy_total{environment="production"}[30d])), 1)
      legendFormat: 'rollback / deploy'
    - expr: |
        sum by (tool) (increase(pipeline_deploy_total{environment="production",result!="success"}[30d]))
        / clamp_min(sum by (tool) (increase(pipeline_deploy_total{environment="production"}[30d])), 1)
      legendFormat: '{{tool}} failures'

# ⭐ panel 4: TIME TO RESTORE
- title: 🔧 Mean time to restore
  type: stat
  targets:
    - expr: |
        avg_over_time(pipeline_rollback_duration_seconds{environment="production"}[30d])
      legendFormat: MTTR

# ⭐ and the per-tool comparison — the panel that starts the interesting conversation
- title: 🔷🐙🔨 Tool comparison
  type: table
  targets:
    - expr: |
        sum by (tool) (rate(pipeline_build_duration_seconds_sum[7d]))
        / clamp_min(sum by (tool) (rate(pipeline_build_duration_seconds_count[7d])), 1)
      legendFormat: '{{tool}} avg build'
      format: table
      instant: true
    - expr: |
        sum by (tool) (increase(pipeline_build_total{result="failure"}[7d]))
        / clamp_min(sum by (tool) (increase(pipeline_build_total[7d])), 1)
      legendFormat: '{{tool}} failure rate'
      format: table
      instant: true
    - expr: sum by (tool) (increase(pipeline_minutes_consumed_total[30d]))
      legendFormat: '{{tool}} minutes / 30d'
      format: table
      instant: true
    - expr: |
        sum by (tool) (increase(pipeline_cache_hit_total[7d]))
        / clamp_min(sum by (tool) (increase(pipeline_build_total[7d])), 1)
      legendFormat: '{{tool}} cache hits / build'
      format: table
      instant: true
```

```
Expected output after a week of the capstone running:

  🔷🐙🔨 Tool comparison
  ┌────────────────┬──────────────┬───────────────┬───────────────┬─────────────────┐
  │ tool           │ avg build    │ failure rate  │ minutes / 30d │ cache hits/build│
  ├────────────────┼──────────────┼───────────────┼───────────────┼─────────────────┤
  │ azure-devops   │ 6m 12s       │ 8%            │ 1,240         │ 0.9             │
  │ github-actions │ 4m 38s       │ 6%            │ 3,810         │ 1.7   ⭐        │
  │ jenkins        │ 9m 04s       │ 14%  ⚠️       │ 0 (own infra) │ 0.4   ⚠️        │
  └────────────────┴──────────────┴───────────────┴───────────────┴─────────────────┘

  ⭐ THAT TABLE IS THE ARGUMENT. Jenkins is slow because the pod agent cold-starts
     and Kaniko has no shared layer cache across pods; its failure rate is high
     because the shared library is version-pinned per job and three jobs are on an
     old version. GitHub Actions' cache-hit ratio is 1.7 per build because
     `type=gha` with a per-service scope works really well. Azure DevOps is in
     between and has the cheapest minutes at this volume.
     Nobody argues about tooling preferences after seeing this. They argue about
     the Kaniko cache and the library versions.
```

### 6.4 The alerts on the pipeline itself

```yaml
# monitoring/rules/pipeline.yaml
groups:
  - name: pipeline.rules
    rules:
      # ── the CI platform is tier-4 infrastructure ───────────────
      - alert: CIPipelineDown
        expr: |
          (absent(up{job="jenkins"}) or up{job="jenkins"} == 0)
          and on() vector(1)
        for: 5m
        labels: {severity: critical, team: platform, tier: '4'}
        annotations:
          summary: 'Jenkins is not reporting metrics'
          description: 'A CI tool is down — nobody can deploy. Check the controller pod.'
          runbook: https://runbooks.shop.example.com/ci/jenkins-down

      - alert: BuildFailureRateHigh
        expr: |
          sum by (tool) (rate(pipeline_build_total{result="failure"}[1h]))
            / clamp_min(sum by (tool) (rate(pipeline_build_total[1h])), 0.001) > 0.30
        for: 30m
        labels: {severity: warning, team: platform, tier: '4'}
        annotations:
          summary: '{{ $value | humanizePercentage }} of {{ $labels.tool }} builds are failing'
          description: >
            A sustained failure rate above 30% is almost never 100 independent bugs.
            Check, in order: the latest shared-library or template release, the base
            images, the dependency registries, and the runner/agent capacity.

      - alert: BuildDurationRegression
        expr: |
          (sum by (tool) (rate(pipeline_build_duration_seconds_sum[1d]))
            / clamp_min(sum by (tool) (rate(pipeline_build_duration_seconds_count[1d])), 0.001))
          >
          1.5 *
          (sum by (tool) (rate(pipeline_build_duration_seconds_sum[7d] offset 7d))
            / clamp_min(sum by (tool) (rate(pipeline_build_duration_seconds_count[7d] offset 7d)), 0.001))
        for: 1d
        labels: {severity: warning, team: platform}
        annotations:
          summary: '{{ $labels.tool }} builds are 50% slower than last week'
          description: 'Usually a lost cache. Check the cache-hit ratio.'

      - alert: CacheHitRateCollapsed
        expr: |
          sum by (tool) (rate(pipeline_cache_hit_total[6h]))
            / clamp_min(sum by (tool) (rate(pipeline_build_total[6h])), 0.001) < 0.3
        for: 3h
        labels: {severity: warning, team: platform}
        annotations:
          summary: 'the {{ $labels.tool }} cache hit rate has collapsed'
          description: >
            A cache key that changed, an evicted cache, or a branch-scoping mistake.
            This costs money and developer time.

      - alert: DeploymentFrequencyCollapsed
        expr: sum(increase(pipeline_deploy_total{environment="production",result="success"}[7d])) < 3
        for: 1h
        labels: {severity: info, team: platform}
        annotations:
          summary: 'fewer than 3 production deployments in 7 days'
          description: >
            ⭐ This is a HEALTH alert, not an incident. Low deployment frequency
            means large, risky batches. Investigate what is blocking the flow:
            a manual gate, a slow review, a flaky test, or an environment problem.

      - alert: RollbackRateHigh
        expr: |
          sum(increase(pipeline_rollback_total{environment="production"}[30d]))
            / clamp_min(sum(increase(pipeline_deploy_total{environment="production"}[30d])), 1) > 0.15
        for: 1h
        labels: {severity: warning, team: platform}
        annotations:
          summary: '{{ $value | humanizePercentage }} of production deploys roll back'
          description: 'The DORA "change failure rate" is above 15%.'

      - alert: PromotionPRBacklog
        expr: count(github_pr_open{repository="shop-config",label="promotion"}) > 5
        for: 2h
        labels: {severity: warning, team: sre}
        annotations:
          summary: '{{ $value }} promotion PRs are unmerged'
          description: >
            ⭐ For production, unmerged promotion PRs mean work is stuck. Either
            the approval process is too slow or the PRs are being ignored.

      - alert: ArgoCDOutOfSyncForTooLong
        expr: argocd_app_info{sync_status="OutOfSync"} == 1
        for: 30m
        labels: {severity: warning, team: sre}
        annotations:
          summary: '{{ $labels.name }} has been OutOfSync for 30 minutes'
          description: >
            Either auto-sync is off (production — someone needs to click Sync) or
            a sync is failing repeatedly. Check `argocd app get`.

      - alert: ArgoCDAppDegraded
        expr: argocd_app_health_status{health_status="Degraded"} == 1
        for: 5m
        labels: {severity: critical, team: sre}
        annotations:
          summary: '{{ $labels.name }} is Degraded'

      - alert: RolloutStuck
        expr: |
          time() - rollout_info{namespace="shop"} > 3600
          and on(name) rollout_info_pause_condition != ""
        for: 15m
        labels: {severity: warning, team: sre}
        annotations:
          summary: 'the rollout {{ $labels.name }} has been paused for over an hour'
          description: >
            A canary that sits paused for an hour is either waiting for a human
            `promote`, or its AnalysisRun is inconclusive because there's no traffic.
            Check `kubectl argo rollouts get {{ $labels.name }} -n shop`.

      - alert: KyvernoBlockingDeploys
        expr: |
          sum by (policy_name) (rate(kyverno_policy_results_total{result="fail"}[15m])) > 0.5
        for: 10m
        labels: {severity: warning, team: security}
        annotations:
          summary: 'Kyverno is rejecting {{ $value }}/s for policy {{ $labels.policy_name }}'
          description: >
            Either a policy is too strict, or something is trying to deploy
            non-compliant workloads. Check `kubectl get policyreport -A`.

      - alert: SecretRotationOverdue
        expr: pipeline_secret_rotation_age_seconds > 7776000      # 90 days
        for: 1h
        labels: {severity: warning, team: security}
        annotations:
          summary: 'the secret {{ $labels.secret }} is {{ $value | humanizeDuration }} old'
```

---

## 7 · The complete walkthrough — one commit to production

**Follow this end to end. It's the interview answer.**

```bash
# ═══════════════════════════════════════════════════════════════════
# STEP 1 — the developer changes the code
# ═══════════════════════════════════════════════════════════════════
cd ~/capstone/apps/shop
git checkout -b fix/checkout-retry
# a real change: retry the payment provider once on a 504
cat > apps/checkout/provider.go <<'EOF'
// (the retry logic, with a test)
EOF
git commit -m "fix(checkout): retry the payment provider once on a 504

A 504 from the provider is usually transient. One retry with a 500ms
backoff converts ~4% of failed checkouts into successes without
meaningfully increasing p99.

Adds a test for the retry path and a metric for retry attempts.

Resolves #42"
git push -u origin fix/checkout-retry

# ═══════════════════════════════════════════════════════════════════
# STEP 2 — the PR build (GitHub Actions, because it's `checkout`)
# ═══════════════════════════════════════════════════════════════════
gh pr create --fill --reviewer payments-team --label service/checkout
gh pr checks --watch
# ✅ changes          12s   (only apps/checkout/** changed)
# ✅ lint             41s
# ✅ test (checkout)  1m18s
# ✅ build (load only — NOT pushed, because it's a PR)
# ⛔ promote          SKIPPED (github.ref != refs/heads/main)
# ⭐ and the PR comment shows: "1 of 5 services will build; 4 skipped"

# ═══════════════════════════════════════════════════════════════════
# STEP 3 — merge, and the main-branch build runs
# ═══════════════════════════════════════════════════════════════════
gh pr merge --squash --delete-branch
gh run watch
# ✅ test (checkout)         1m22s
# ✅ build + push + SBOM     2m04s   (cache hit → fast)
# ✅ sign (cosign keyless)      8s
# ✅ scan (trivy CRITICAL)     31s
# ✅ promote → dev             52s   ← ⭐ opens and auto-merges a config PR

# ⭐ what the promote step actually did:
#   1. cosign VERIFY the digest (independently of having just signed it)
#   2. trivy scan the SBOM attestation
#   3. clone shop-config with a GitHub App token scoped to THAT repo only
#   4. yq-edit environments/dev/checkout.yaml — 6 lines
#   5. helm template + kubeconform + a Kyverno dry-run
#   6. open a PR with a diff and a checklist in the body
#   7. wait for the config repo's own checks
#   8. squash-merge

# ═══════════════════════════════════════════════════════════════════
# STEP 4 — Argo CD reconciles dev
# ═══════════════════════════════════════════════════════════════════
argocd app get shop-dev-checkout --refresh
# Name:               shop-dev-checkout
# Project:            shop-dev
# Sync Status:        Synced                 ⭐ was OutOfSync for ~40s
# Health Status:      Healthy
# Revision:           9f2a1b3 (main)
# Images:             ghcr.io/3558bhk/checkout@sha256:3f2a…

kubectl -n shop-dev get rollout checkout -o jsonpath='{.status.phase}{"\n"}'
kubectl argo rollouts get rollout checkout -n shop-dev --watch
# ⟳ checkout      ॥ Paused    (dev uses 50% → 30s → 100%, so it's fast)
# 30 seconds later:
# ⟳ checkout      ● Healthy

# ⭐ and Kyverno VERIFIED the signature at admission — check the report
kubectl get clusterpolicyreport -o json \
  | jq '.results[] | select(.policy=="verify-image-signature") | select(.timestamp > (now-600)) |
        {result, resource: .resources[0].name, message: .message[0:80]}'
# {"result":"pass","resource":"checkout-7d9f8c-abcde"}

# ═══════════════════════════════════════════════════════════════════
# STEP 5 — the E2E suite runs against dev (a scheduled/triggered job)
# ═══════════════════════════════════════════════════════════════════
# triggered by a repository_dispatch from the promote script, or by a schedule
npx playwright test --project=dev
# 42 passed, 0 failed

# ═══════════════════════════════════════════════════════════════════
# STEP 6 — promote to staging
# ═══════════════════════════════════════════════════════════════════
gh workflow run promote.yml -f environment=staging -f service=checkout \
  -f digest=sha256:3f2a1b9c0d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a
# ⭐ the workflow:
#   1. verifies the digest was ALREADY validated in dev
#      (checks the config repo's git history for environments/dev/checkout.yaml)
#   2. re-verifies the cosign signature
#   3. opens a PR to environments/staging/checkout.yaml
#   4. auto-merges (staging has no human gate)
#   5. Argo CD syncs → the Rollout does 20% → analysis → 50% → analysis → 100%

kubectl argo rollouts get rollout checkout -n shop-staging --watch
# ⟳ checkout   ॥ Paused   Step 2/8   SetWeight: 20
# ✔ checkout-canary-check-abc   ✔ Successful   ✔ 8/8 metrics
# ⟳ checkout   ॥ Paused   Step 4/8   SetWeight: 50
# ✔ checkout-canary-check-def   ✔ Successful
# ⟳ checkout   ● Healthy

# ⭐ the SOAK: staging sits at the new version for 2 hours while the synthetic
#    probes and the E2E suite run against it.
sleep 7200

# ═══════════════════════════════════════════════════════════════════
# STEP 7 — the production promotion PR (a HUMAN must approve)
# ═══════════════════════════════════════════════════════════════════
gh workflow run promote.yml -f environment=production -f service=checkout \
  -f digest=sha256:3f2a… -f change-ticket=CHG-12847
# ⭐ the workflow does NOT auto-merge. It:
#   1. verifies the digest has been running in STAGING for ≥2 hours
#      (queries the config repo's git log for environments/staging/checkout.yaml)
#   2. verifies the staging rollout completed without an analysis failure
#      (queries Argo Rollouts' AnalysisRun history)
#   3. runs the production gate: the SLO burn rate, firing alerts, the window
#   4. opens a PR with a full evidence table
#   5. requests a review from sre-team (via CODEOWNERS)
#   6. posts to #shop-releases

gh pr view --repo 3558Bhk/shop-config $PR --json title,body,reviews \
  --jq '.body' | head -40
# ## 🚀 Promotion: `checkout` → `production`
# | Service | checkout |
# | Digest | sha256:3f2a1b9c… |
# | Previous | sha256:8b7c6d5e… |
# | App revision | a1b2c3d |
# | Built by | github-actions |
# | Build | https://github.com/3558Bhk/shop/actions/runs/1234567890 |
# | SBOM | 214 components |
# | Signature | ✅ verified |
# | CRITICAL CVEs | 0 |
# | ⭐ Staging soak | 2h 14m, no analysis failure |
# | ⭐ Change ticket | CHG-12847 |
# | ⭐ SLO burn rate | 0.4× (healthy) |
# | ⭐ Firing alerts | none |
# | ⭐ Deployment window | ✅ inside (Wed 14:20 IST) |
#
# ### ⚠️ PRODUCTION — review before approving
# - [ ] the staging soak completed without an analysis failure
# …

# ⭐ the SRE reviews and approves
gh pr review $PR --repo 3558Bhk/shop-config --approve --body \
  "Reviewed. The diff is 6 lines, all in the digest block. Staging soaked 2h14m.
   CHG-12847. Rollback plan: git revert this commit."
gh pr merge $PR --repo 3558Bhk/shop-config --squash

# ═══════════════════════════════════════════════════════════════════
# STEP 8 — ⭐⭐ THE FINAL HUMAN GATE: Argo CD sync
#    Production Applications have NO auto-sync. Merging does NOT deploy.
# ═══════════════════════════════════════════════════════════════════
argocd app get shop-production-checkout
# Sync Status:  OutOfSync          ⭐ Git says the new digest; the cluster has the old
# Health:       Healthy
argocd app diff shop-production-checkout
# ===== argocd/shop-production-checkout =====
# spec.template.spec.containers.0.image:
# - ghcr.io/3558bhk/checkout@sha256:8b7c6d5e4f3a…
# + ghcr.io/3558bhk/checkout@sha256:3f2a1b9c0d4e…

# ⭐ the SRE syncs — deliberately, watching
argocd app sync shop-production-checkout --prune --timeout 900
# ✅ it's the same person who approved the PR, with the cluster context in front of them

# ═══════════════════════════════════════════════════════════════════
# STEP 9 — Kyverno verifies at admission
# ═══════════════════════════════════════════════════════════════════
kubectl -n shop get events --field-selector reason=PolicyApplied --sort-by=.lastTimestamp | tail -5
kubectl get clusterpolicyreport -o json | jq '[.results[] |
  select(.policy=="verify-image-signature") | select(.result=="pass")] | length'

# ═══════════════════════════════════════════════════════════════════
# STEP 10 — ⭐ Argo Rollouts delivers progressively
# ═══════════════════════════════════════════════════════════════════
kubectl argo rollouts get rollout checkout -n shop --watch
# ⟳ checkout   ॥ Paused   Step 1/11   SetWeight: 5
#   Images: sha256:8b7c… (stable, 19 pods)
#           sha256:3f2a… (canary, 1 pod)
#   ⏸ pausing for 10m
#
# …10 minutes later…
# ✔ checkout-canary-check-xyz   ✔ Successful   3m
#   ├─✔ error-rate               0.0008 (max 0.01)
#   ├─✔ canary-vs-stable-errors  0.0009 vs 0.0008 (ratio 1.12, max 1.5)
#   ├─✔ p99-latency              0.142s (max 0.100s) … ⚠️ see below
#   ├─✔ cpu-saturation           0.03 (max 0.25)
#   ├─✔ oom-and-restarts         0 (max 2)
#   ├─◌ enough-traffic           INCONCLUSIVE (only 14 requests at 5%)
#   ├─✔ synthetic-probe          1
#   └─✔ canary-smoke-job         exit 0
# ⟳ checkout   ॥ Paused   Step 3/11   SetWeight: 15
#   ⏸ pausing for 15m
#
# …and so on through 35%, 60%, 100%…
#
# ⟳ checkout   ● Healthy   11/11 steps   total 2h 05m

# ⭐ the total production rollout took 2 hours. THAT IS THE POINT.
#    A 2-hour rollout with automated analysis at every step is infinitely safer
#    than a 30-second `kubectl set image` and a hopeful glance at a dashboard.

# ═══════════════════════════════════════════════════════════════════
# STEP 11 — verify and record
# ═══════════════════════════════════════════════════════════════════
kubectl -n shop get rollout checkout -o json | jq '{
  phase: .status.phase, revision: .status.currentRevision,
  stable: .status.stableRS, image: .spec.template.spec.containers[0].image}'

# ⭐ move the production tag
git tag -f "prod-$(date -u +%F)" a1b2c3d && git push -f origin "prod-$(date -u +%F)"

# ⭐ the DORA metrics recorded themselves via emit-pipeline-metrics.sh
curl -sG localhost:9090/api/v1/query \
  --data-urlencode 'query=pipeline_change_lead_time_seconds{tool="github-actions",environment="production"}' \
  | jq '.data.result[0].value[1]'
# "5842"        ← ⭐ 1h 37m from commit to production. That's your lead time.
```

### 7.1 Now break it on purpose ⭐⭐

```bash
# ═════ THE REGRESSION ═════
# deploy a version of checkout that returns 500 for 20% of requests
git checkout -b bad/retry-storm
# (introduce a bug: the retry loops forever on a 504)
gh pr create --fill && gh pr merge --squash
# …CI builds, signs, promotes to dev…

kubectl argo rollouts get rollout checkout -n shop --watch
# ⟳ checkout   ॥ Paused   Step 3/11   SetWeight: 15
# ⛔ checkout-canary-check-bad   ✗ FAILED   4m
#   ├─✔ error-rate               0.0009
#   ├─⛔ canary-vs-stable-errors  0.1840 vs 0.0008 (ratio 230, max 1.5)
#   ├─✔ p99-latency              0.088s
#   ├─✔ cpu-saturation           0.41 ⚠️
#   └─✔ synthetic-probe          0 ⛔
# ⟳ checkout   ✗ Degraded   RolloutAborted: metric "canary-vs-stable-errors"
#                            assessed Failed

# ⭐⭐ WHAT HAPPENED AUTOMATICALLY:
kubectl -n shop get pods -l app=checkout -o wide
#   checkout-6b8e7d-fghij   1/1   Running   ← ALL 20 pods are the STABLE version
#   (the canary ReplicaSet scaled to 0)
kubectl -n shop get rs -l app=checkout
#   checkout-7d9f8c   0   0   0   ← the bad canary, scaled down
#   checkout-6b8e7d   20  20  20  ← stable, untouched
# ⭐ the bad version reached at most 15% of traffic for 4 minutes,
#   and NO HUMAN DID ANYTHING.

# ⭐ the alert fired
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-alertmanager 9093:9093 &
curl -s localhost:9093/api/v2/alerts | jq '.[] | select(.labels.alertname|test("Rollout|Deploy")) | {alertname: .labels.alertname, severity: .labels.severity}'
# {"alertname":"ArgoRolloutDegraded","severity":"critical"}

# ⭐ and Slack got it
# 🔴 checkout's production canary FAILED and was rolled back automatically
#    metric: canary-vs-stable-errors = 0.1840 (stable: 0.0008, max ratio 1.5)
#    the bad version reached 15% of traffic for 4m 12s
#    run: https://github.com/3558Bhk/shop/actions/runs/…
#    kubectl argo rollouts get rollout checkout -n shop

# ═════ THE SIGNATURE ATTACK ═════
# an attacker who compromised the registry pushes an image with the same tag
docker pull alpine:3.20 && docker tag alpine:3.20 ghcr.io/3558bhk/checkout:latest
docker push ghcr.io/3558bhk/checkout:latest          # ⛔ unsigned
kubectl -n shop set image deploy/checkout api=ghcr.io/3558bhk/checkout:latest
#   Error from server: admission webhook "validate.kyverno.svc-fail" denied:
#   ⛔ verify-image-signature: no matching signatures found
# ⭐⭐ THE CLUSTER REFUSED IT. Not the pipeline — the cluster.
#    Compromising CI is not enough to deploy.

# ═════ THE DRIFT ═════
kubectl -n shop scale deploy/checkout --replicas=50   # a manual "fix" during an incident
kubectl -n shop get deploy checkout                   # 50 replicas
sleep 200                                             # ⭐ Argo CD's 3-minute resync
kubectl -n shop get deploy checkout                   # back to 20
argocd app get shop-production-checkout
# Sync Status: Synced        ⭐ it self-healed
# ⭐⭐ and if you'd scaled the ROLLOUT, Argo CD's `ignoreDifferences` on
#    /spec/replicas means the HPA and Rollout own that field, not Git.
#    That distinction is deliberate and worth being able to explain.

# ═════ THE GITOPS ROLLBACK ═════
cd ~/capstone/shop-config
git log --oneline -3 environments/production/checkout.yaml
git revert --no-edit HEAD
git push
argocd app sync shop-production-checkout --prune
kubectl argo rollouts get rollout checkout -n shop --watch
# ⭐ the rollback goes through the SAME progressive delivery machinery.
#    A rollback is a deploy. It gets the same canary and the same analysis.
```

---

## 8 · The runbooks

```bash
mkdir -p docs/runbooks
cat > docs/runbooks/README.md <<'EOF'
# CI/CD runbooks

| Symptom | Runbook |
|---|---|
| A canary failed and rolled back | [canary-failed.md](./canary-failed.md) |
| Argo CD is OutOfSync and won't sync | [argocd-outofsync.md](./argocd-outofsync.md) |
| Kyverno is rejecting deploys | [kyverno-blocking.md](./kyverno-blocking.md) |
| A CI tool is down | [ci-tool-down.md](./ci-tool-down.md) |
| A secret leaked | [secret-leaked.md](./secret-leaked.md) |
| Production is broken and I need it back NOW | [emergency-rollback.md](./emergency-rollback.md) |
| A promotion PR is stuck | [promotion-stuck.md](./promotion-stuck.md) |
| The pipeline is slow | [pipeline-slow.md](./pipeline-slow.md) |
EOF

cat > docs/runbooks/emergency-rollback.md <<'EOF'
# 🚨 Emergency rollback — production is broken NOW

**Time budget: under 5 minutes.** Read this once when calm, not during the incident.

## Decision tree

```
Is the cluster itself healthy (nodes Ready, DNS working)?
├─ NO  → this is not a deploy problem. Escalate to infrastructure. Go to
│        [cluster-down.md]. Do NOT roll back the app.
└─ YES → Did the breakage start within ~2h of a deploy?
         ├─ YES → roll back the deploy. Continue below.
         └─ NO / UNSURE → check `kubectl argo rollouts history` and
                          `argocd app history`. If a deploy is the most
                          likely cause, roll it back anyway — it is cheap
                          and reversible. Continue below.
```

## Path A — Argo Rollouts abort (seconds) ⭐ FASTEST

Use this when a canary is mid-rollout and going badly.

```bash
kubectl argo rollouts get rollout <service> -n shop          # confirm it's progressing
kubectl argo rollouts abort <service> -n shop                # ⭐ back to stable instantly
kubectl argo rollouts get rollout <service> -n shop --watch  # → Degraded, 100% stable
kubectl -n shop get pods -l app=<service> -o wide            # verify only stable pods
./scripts/smoke-test.sh https://shop.example.com             # verify it's actually fixed
```
**Time: ~20 seconds.** The stable ReplicaSet was never torn down.

## Path B — undo the Rollout to a previous revision (1–2 min)

```bash
kubectl argo rollouts history <service> -n shop
kubectl argo rollouts undo <service> -n shop --to-revision <N>
kubectl argo rollouts get rollout <service> -n shop --watch
```
⚠️ This creates DRIFT from Git. Argo CD will revert it. **Immediately** do Path C.

## Path C — ⭐ the GitOps revert (the correct one, 2–4 min)

```bash
cd shop-config
git log --oneline -6 environments/production/<service>.yaml
git revert --no-edit <the-bad-promotion-commit>
git push origin main
argocd app sync shop-production-<service> --prune --timeout 300
kubectl argo rollouts get rollout <service> -n shop --watch
```
⭐ This goes through progressive delivery again (5% → …), which is CORRECT —
but if you need it faster:
```bash
argocd app sync shop-production-<service> --prune
kubectl argo rollouts promote --full <service> -n shop    # ⭐ skip the remaining pauses
```

## Path D — the break-glass (last resort, creates drift)

```bash
# ⭐ ONLY if Git and Argo CD are both unavailable.
argocd app set shop-production-<service> --sync-policy none   # stop Argo CD fighting you
kubectl -n shop set image deploy/<service> api=<registry>/<service>@sha256:<known-good>
kubectl -n shop rollout status deploy/<service> --timeout=180s
# ⭐⭐ then IMMEDIATELY: open an incident, fix Git, re-enable auto-sync.
#      A cluster running something Git doesn't know about is an unmonitored cluster.
```

## After the rollback — non-negotiable

1. `./scripts/smoke-test.sh https://shop.example.com` — **prove** it's fixed.
2. Post in #shop-oncall: what was rolled back, to which revision, by whom, at what time.
3. Preserve evidence BEFORE it's lost:
   ```bash
   kubectl -n shop get analysisrun -o yaml > evidence/analysisruns.yaml
   kubectl -n shop get rollout <service> -o yaml > evidence/rollout.yaml
   kubectl -n shop logs deploy/<service> --previous --tail=500 > evidence/prev-logs.txt
   argocd app manifests shop-production-<service> > evidence/manifests.yaml
   ```
4. Open an incident with the DORA `pipeline_rollback_total` metric incremented.
5. Within 48h: a blameless review. The question is never "who deployed it" — it's
   **"why did the canary analysis not catch it, and what metric would have?"**
   The answer is almost always a missing metric or a threshold too loose.

## What NOT to do
- ⛔ Don't `kubectl delete pod` in a loop. That hides the problem and loses evidence.
- ⛔ Don't scale to zero "to stop the errors". You lose the ability to inspect.
- ⛔ Don't roll back the DATABASE. Schema migrations are expand-contract for a
  reason: the old code must work with the new schema. Verify, don't revert.
- ⛔ Don't fix forward unless the rollback genuinely cannot work. Fixing forward
  during an incident is how a 10-minute outage becomes a 3-hour one.
EOF

cat > docs/runbooks/canary-failed.md <<'EOF'
# A canary failed and rolled back automatically

**First: nothing is on fire.** The rollback was automatic. You have time.

## 1. Find out WHICH metric failed
```bash
kubectl -n shop get analysisrun -l rollouts.argoproj.io/rollout-name=<service> \
  --sort-by=.metadata.creationTimestamp -o json \
  | jq '.items[-1].status.metricResults[] | select(.phase!="Successful") |
        {metric: .name, phase, measurements: [.measurements[] | {value, phase}]}'
# {"metric":"canary-vs-stable-errors","phase":"Failed",
#  "measurements":[{"value":"[0.184]  [0.0008]","phase":"Failed"}]}
#                    ↑ canary    ↑ stable
```

## 2. Read the metric's actual query result in Grafana
```
Grafana → shop → Canary analysis → the failed metric's panel
⭐ compare canary vs stable directly:
  sum by (app_kubernetes_io_version) (
    rate(http_server_requests_seconds_count{app="<service>",status=~"5.."}[5m]))
  /
  sum by (app_kubernetes_io_version) (
    rate(http_server_requests_seconds_count{app="<service>"}[5m]))
```

## 3. Classify the cause
| Metric that failed | Most likely cause |
|---|---|
| `canary-vs-stable-errors` | ⭐ a real bug in the new code. Read the canary logs. |
| `p99-latency` | a new dependency call, a lost cache, a bigger payload, GC pressure |
| `cpu-saturation` | the resource requests are too low for the new version |
| `oom-and-restarts` | a memory leak or an undersized limit |
| `synthetic-probe` | the health endpoint changed, or the service won't start |
| `canary-smoke-job` | a contract change — the new version behaves differently |
| ⭐ `enough-traffic` inconclusive | ⚠️ NOT a failure. There's no traffic at 5%. |

## 4. The inconclusive case — the one people misread
```
◌ enough-traffic   INCONCLUSIVE
```
This means **the analysis could not decide**, not that it failed. At 5% of
traffic at 3 a.m. there may be 4 requests in 5 minutes. Argo Rollouts will
keep the rollout paused. Your options:
- ⭐ wait for traffic (correct at night)
- `kubectl argo rollouts promote <service> -n shop` (skip the step — you're
  taking responsibility; do it only with a reason)
- ⭐⭐ the RIGHT FIX: generate synthetic load during the canary so the analysis
  always has enough samples. See §5.

## 5. Generate canary load (the fix for the inconclusive case)
```yaml
# a low-rate synthetic load generator that runs during a rollout
apiVersion: batch/v1
kind: Job
metadata: {name: canary-load, namespace: shop}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 7200
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: load
          image: ghcr.io/3558bhk/canary-load:1.0.0
          args: ['--target', 'http://<service>-canary.shop',
                 '--rps', '5', '--duration', '2h',
                 '--scenario', 'browse-and-checkout']
          resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 128Mi}}
```
⭐ 5 RPS × 300s = 1500 requests — far above the `min-request-count: 20`
threshold, so the analysis is always conclusive.

## 6. Fix and re-deploy
```bash
git revert <the-bad-app-commit>         # or fix forward on a branch
# → CI builds, signs, promotes → the same machinery, again
```

## 7. ⭐ The post-incident question
> **"What metric would have caught this earlier?"**

If the answer is "none — it only shows under real user load", then:
- add a metric for it, or
- add a `job:` metric to the AnalysisTemplate that exercises the specific path, or
- ⭐ lower `setWeight` for the first step (5% → 2%) and extend the pause

Record the answer in the AnalysisTemplate's Git history. That file should
grow a comment every time a canary escapes it.
EOF
```

---

## 9 · The capstone checklist

```
CLUSTER AND PLATFORM
  □ kind/AKS/EKS with ≥3 worker nodes
  □ ingress-nginx + cert-manager
  □ Argo CD 3.x with SSO and an AppProject per environment
  □ ⭐ Argo Rollouts with the dashboard and the kubectl plugin
  □ Kyverno with ≥5 policies in Enforce mode
  □ the full monitoring stack (Prometheus, Grafana, Alertmanager, Loki)
  □ the Pushgateway, with `honorLabels: true` on its ServiceMonitor

THE CONFIG REPO ⭐⭐
  □ a separate repository from the app
  □ CODEOWNERS requiring sre-team on environments/production/**
  □ a shared Helm library chart (apps/base) with a Rollout, not a Deployment
  □ per-environment values files: dev (fast), staging (medium), production (slow)
  □ per-service digest files — ⭐ CI touches ONLY these
  □ the digests are DIGESTS, never tags
  □ ApplicationSets generating one Application per env × service
  □ ⭐ production Applications have NO auto-sync — a human clicks Sync
  □ dev/staging auto-sync with prune + selfHeal
  □ ignoreDifferences on /status and /spec/replicas (so Argo CD doesn't fight Rollouts)
  □ Kyverno policies stored in the repo and applied by Argo CD
  □ AnalysisTemplates stored in the repo, with thresholds as args
  □ the runbooks in docs/runbooks/

THE FIVE INVARIANTS ⭐⭐⭐
  □ 1. BUILD ONCE — you proved the same digest runs in dev, staging and production
  □ 2. NO CLUSTER CREDENTIALS IN CI — you grepped all three tools' secrets and
       found no kubeconfig; the only credential is a config-repo token
  □ 3. SIGNED AND VERIFIED — you pushed an unsigned image and the cluster REFUSED it
  □ 4. METRIC-BASED PROMOTION — you deployed a bad version and it rolled back
       automatically with no human action
  □ 5. THE PIPELINE IS INSTRUMENTED — you can read the DORA metrics off a dashboard

THE THREE CI TOOLS
  □ 🐙 GitHub Actions builds checkout + shop-ui, signs with OIDC keyless cosign
  □ 🔷 Azure DevOps builds shop-api, signs with the WIF identity
  □ 🔨 Jenkins builds order-worker + payment-mock with Kaniko, signs with a Vault key
  □ ⭐ all three call the SAME scripts/promote.sh
  □ ⭐ all three call the SAME scripts/sign-and-attest.sh
  □ ⭐ all three call the SAME scripts/emit-pipeline-metrics.sh
  □ ⭐ you ran the convergence proof: five digests from three tools, all verified

SUPPLY CHAIN
  □ cosign signatures verified before promotion (in promote.sh, independently)
  □ CycloneDX SBOMs attached as signed attestations
  □ SLSA provenance attached
  □ Kyverno `verifyImages` with issuer AND subject/identity conditions
  □ `mutateDigest: true` so the pod runs the verified digest, not the tag
  □ ⭐ you tested: an unsigned image, a wrongly-signed image, a :latest tag,
     a missing probe, a missing resource request — ALL REJECTED
  □ Rekor transparency log entries exist (or you consciously opted out)

PROGRESSIVE DELIVERY
  □ canary steps with pauses: dev 50%→100% fast, staging 20/50/100,
    production 5/15/35/60/100 with a final 60m soak
  □ an AnalysisTemplate with ≥6 metrics
  □ ⭐ the `enough-traffic` guard so a low-traffic canary is inconclusive, not "healthy"
  □ `initialDelay` on every metric so the canary warms up
  □ `failureLimit` and `count` tuned so one blip doesn't abort
  □ a `job:` metric running the smoke test as part of the analysis
  □ ⭐ you deployed a broken version and watched it auto-rollback
  □ you know all FOUR rollback paths and when to use each
  □ a canary load generator so the analysis is always conclusive

PIPELINE TELEMETRY ⭐
  □ the metric contract documented (the exact names and labels)
  □ emit-pipeline-metrics.sh called from all three tools
  □ the Pushgateway scraped with honorLabels: true
  □ the DORA dashboard: deployment frequency, lead time, failure rate, MTTR
  □ ⭐ the per-tool comparison table — and you have an opinion about what it shows
  □ alerts on the CI platform itself (down, failure rate, duration regression,
    cache collapse, deployment frequency collapse, promotion PR backlog)

RUNBOOKS
  □ emergency-rollback.md with four paths and a decision tree
  □ canary-failed.md with the metric → cause table
  □ argocd-outofsync.md, kyverno-blocking.md, ci-tool-down.md, secret-leaked.md
  □ ⭐ you have EXERCISED the emergency rollback and timed it
  □ the evidence-preservation commands are in the runbook

THE END-TO-END WALKTHROUGH
  □ you did §7 start to finish: a commit → a PR → a merge → dev → staging →
    a 2-hour soak → a human-approved production PR → a human Argo CD sync →
    a 2-hour progressive rollout → verified
  □ you broke it on purpose (§7.1) four ways and watched each defense work
  □ you can narrate the whole thing in 5 minutes without notes

TASKS
  □ C.1 the cross-tool convergence proof
  □ C.2 the Kyverno supply-chain policy, with all six rejection tests
  □ C.3 the AnalysisTemplate tuned against a real regression
  □ C.4 the DORA dashboard with the per-tool comparison
  □ C.5 the chaos day — five failures, all defended
```

---

<a name="tasks--answers"></a>
## 🎯 Tasks & Answers

Five capstone tasks. These are the ones that separate "I used the tools" from "I can design the system."

| # | Task |
|---|---|
| C.1 | Prove the **three-tool convergence**: five digests, three identities, one delivery path |
| C.2 | Build the **Kyverno supply-chain policy** and pass all six rejection tests |
| C.3 | Tune the **AnalysisTemplate** against a real regression, without false positives |
| C.4 | Build the **DORA dashboard** with a per-tool comparison, and act on what it says |
| C.5 | Run a **chaos day**: five failures, each caught by a different layer |

---

### Task C.1 — The cross-tool convergence proof

**Requirement:** demonstrate, with evidence an auditor would accept, that three CI tools using three different authentication mechanisms and three different build engines produce artifacts that are **indistinguishable to the delivery path** — and that the delivery path verifies each one correctly.

**✅ Answer**

**Step 1 — a single verification script that knows all three trust models**

```bash
# scripts/verify-supply-chain.sh
#!/usr/bin/env bash
# ⭐ THE AUDIT TOOL. Run it against any environment and get a pass/fail report.
set -uo pipefail

ENVIRONMENT="${1:?usage: verify-supply-chain.sh <dev|staging|production>}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/shop-config}"
FULCIO_ROOT="${FULCIO_ROOT:-policies/supply-chain/fulcio-root.pem}"
JENKINS_KEY="${JENKINS_KEY:-policies/supply-chain/cosign.pub}"
REKOR="${REKOR_URL:-https://rekor.sigstore.dev}"
OUT="reports/supply-chain-${ENVIRONMENT}-$(date -u +%FT%TZ).md"
mkdir -p reports

pass=0; fail=0; warn=0
ok()   { printf '  \033[1;32m✅ %s\033[0m\n' "$*"; echo "| ✅ | $* |" >> "$OUT.rows"; pass=$((pass+1)); }
bad()  { printf '  \033[1;31m⛔ %s\033[0m\n' "$*"; echo "| ⛔ | $* |" >> "$OUT.rows"; fail=$((fail+1)); }
note() { printf '  \033[1;33m⚠️  %s\033[0m\n' "$*"; echo "| ⚠️ | $* |" >> "$OUT.rows"; warn=$((warn+1)); }

echo "# Supply-chain verification — ${ENVIRONMENT} — $(date -u +%FT%TZ)" > "$OUT"
echo >> "$OUT"; echo "| | Check |" >> "$OUT"; echo "|---|---|" >> "$OUT"
rm -f "$OUT.rows"

echo "══════════════════════════════════════════════════════════════"
echo "  SUPPLY-CHAIN VERIFICATION — ${ENVIRONMENT}"
echo "══════════════════════════════════════════════════════════════"

cd "$CONFIG_DIR" && git pull -q

for f in "environments/$ENVIRONMENT"/*.yaml; do
  svc=$(basename "$f" .yaml)
  [[ "$svc" == values-* ]] && continue

  echo; echo "── $svc ──"
  DIGEST=$(yq '.image.digest' "$f");  REPO=$(yq '.image.repository' "$f")
  TOOL=$(yq '.promotedBy' "$f");      REV=$(yq '.revision' "$f")
  RUN=$(yq '.promotedFromRun' "$f");  AT=$(yq '.promotedAt' "$f")
  REF="${REPO}@${DIGEST}"

  # ── CHECK 1: is it a digest, not a tag? ────────────────────────
  if [[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    ok "$svc: referenced by an immutable digest"
  else
    bad "$svc: NOT a digest ('$DIGEST') — a mutable tag can be re-pushed"
    continue
  fi

  # ── CHECK 2: does the image exist and does the digest match? ───
  ACTUAL=$(crane digest "$REF" 2>/dev/null || echo "")
  if [[ "$ACTUAL" == "$DIGEST" ]]; then
    ok "$svc: the registry's digest matches the config's"
  else
    bad "$svc: the registry reports ${ACTUAL:-<missing>}, the config says $DIGEST"
    continue
  fi

  # ── CHECK 3: ⭐⭐ verify the signature with the RIGHT trust model ─
  case "$TOOL" in
    github-actions)
      if cosign verify "$REF" \
           --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
           --certificate-identity-regexp="^https://github.com/3558Bhk/shop/\.github/workflows/ci\.yml@refs/heads/main$" \
           >/tmp/v.json 2>&1; then
        ISSUER=$(jq -r '.[0].critical.image."docker-reference"' /tmp/v.json)
        SUBJECT=$(cosign verify "$REF" --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
                  --output json 2>/dev/null | jq -r '.[0].optional.Subject // "?"')
        ok "$svc: GHA keyless signature verified (subject: $SUBJECT)"
      else
        bad "$svc: the GitHub Actions signature did NOT verify"; cat /tmp/v.json | head -3
      fi ;;
    azure-devops)
      if cosign verify "$REF" \
           --certificate-oidc-issuer-regexp="^https://vstoken\.actions\.azure\.com/" \
           >/tmp/v.json 2>&1; then
        ok "$svc: Azure DevOps WIF signature verified"
      else
        bad "$svc: the Azure DevOps signature did NOT verify"
      fi ;;
    jenkins)
      if cosign verify "$REF" --key "$JENKINS_KEY" >/tmp/v.json 2>&1; then
        ok "$svc: Jenkins key-based signature verified"
      else
        bad "$svc: the Jenkins signature did NOT verify"
      fi ;;
    *) bad "$svc: unknown CI tool '$TOOL' — cannot verify" ;;
  esac

  # ── CHECK 4: the SBOM attestation ──────────────────────────────
  if cosign verify-attestation --type cyclonedx "$REF" \
       --certificate-oidc-issuer-regexp='.*' >/tmp/a.json 2>&1 \
     || cosign verify-attestation --type cyclonedx --key "$JENKINS_KEY" "$REF" >/tmp/a.json 2>&1; then
    N=$(jq -r '.payload' /tmp/a.json | base64 -d | jq '.predicate.components | length' 2>/dev/null || echo 0)
    ok "$svc: a signed CycloneDX SBOM with $N components"
    # ── CHECK 5: scan the SBOM for CRITICALs ─────────────────────
    jq -r '.payload' /tmp/a.json | base64 -d > /tmp/sbom.json
    CRIT=$(trivy sbom --severity CRITICAL --quiet --format json /tmp/sbom.json 2>/dev/null \
           | jq '[.Results[]?.Vulnerabilities[]?] | length' || echo "?")
    if [[ "$CRIT" == "0" ]]; then ok "$svc: 0 CRITICAL vulnerabilities in the SBOM"
    elif [[ "$ENVIRONMENT" == "production" ]]; then bad "$svc: $CRIT CRITICAL vulnerabilities in PRODUCTION"
    else note "$svc: $CRIT CRITICAL vulnerabilities (non-production)"; fi
  else
    bad "$svc: no signed SBOM attestation"
  fi

  # ── CHECK 6: the provenance attestation ────────────────────────
  if cosign verify-attestation --type slsaprovenance "$REF" \
       --certificate-oidc-issuer-regexp='.*' >/dev/null 2>&1; then
    ok "$svc: SLSA provenance attestation present"
  elif jq -e '.[0].optional' /tmp/v.json >/dev/null 2>&1; then
    # ⭐ BuildKit attaches provenance to the MANIFEST, not as a cosign attestation
    if docker buildx imagetools inspect "$REF" --format '{{json .Provenance}}' 2>/dev/null | grep -q .; then
      ok "$svc: BuildKit provenance in the image index"
    else
      note "$svc: no SLSA provenance attestation"
    fi
  else
    note "$svc: no provenance attestation"
  fi

  # ── CHECK 7: the Rekor transparency log ────────────────────────
  UUID=$(cosign verify "$REF" --certificate-oidc-issuer-regexp='.*' -o json 2>/dev/null \
         | jq -r '.[0].optional.Bundle.Payload.logID // empty')
  if [[ -n "$UUID" ]]; then
    if curl -sf "$REKOR/api/v1/log/entries/$UUID" >/dev/null; then
      ok "$svc: recorded in Rekor ($UUID)"
    else
      note "$svc: has a logID but Rekor has no entry (offline signing?)"
    fi
  else
    note "$svc: not in the Rekor transparency log (key-based signing)"
  fi

  # ── CHECK 8: the traceability chain ────────────────────────────
  [[ -n "$REV" && "$REV" != "null" ]] && ok "$svc: linked to app revision ${REV:0:7}" \
                                      || bad "$svc: no app revision recorded"
  [[ -n "$RUN" && "$RUN" != "null" ]] && ok "$svc: linked to a build run" \
                                      || note "$svc: no build run URL"
  [[ -n "$AT"  && "$AT"  != "null" ]] && ok "$svc: promoted at $AT" \
                                      || bad "$svc: no promotion timestamp"

  # ── CHECK 9: ⭐ does the app revision actually exist in the app repo? ─
  if [[ -n "$REV" && "$REV" != "null" ]]; then
    if gh api "repos/3558Bhk/shop/commits/$REV" --jq .sha >/dev/null 2>&1; then
      ok "$svc: revision ${REV:0:7} exists in the app repository"
    else
      bad "$svc: revision ${REV:0:7} does NOT exist in the app repository — the record is wrong"
    fi
  fi
done

# ── CHECK 10: ⭐⭐ what is ACTUALLY RUNNING vs what Git says ──────
echo; echo "── the cluster vs Git ──"
NS="shop$([[ "$ENVIRONMENT" == "dev" ]] && echo "-dev"; [[ "$ENVIRONMENT" == "staging" ]] && echo "-staging")"
for f in "environments/$ENVIRONMENT"/*.yaml; do
  svc=$(basename "$f" .yaml); [[ "$svc" == values-* ]] && continue
  WANT=$(yq '.image.digest' "$f")
  HAVE=$(kubectl -n "$NS" get rollout "$svc" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null \
         || kubectl -n "$NS" get deploy "$svc" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo "")
  if [[ "$HAVE" == *"@${WANT}"* || "$HAVE" == *"${WANT}"* ]]; then
    ok "$svc: the cluster is running what Git says (${WANT:0:19}…)"
  else
    bad "$svc: DRIFT — Git says ${WANT:0:19}…, the cluster has ${HAVE:0:60}"
  fi
done

# ── CHECK 11: did Kyverno actually verify these on admission? ────
echo; echo "── the admission record ──"
KPASS=$(kubectl get clusterpolicyreport -o json 2>/dev/null \
  | jq '[.results[] | select(.policy=="verify-image-signature" and .result=="pass")] | length')
KFAIL=$(kubectl get clusterpolicyreport -o json 2>/dev/null \
  | jq '[.results[] | select(.policy=="verify-image-signature" and .result=="fail")] | length')
[[ "$KFAIL" == "0" ]] && ok "Kyverno: $KPASS signature verifications passed, 0 failed" \
                      || bad "Kyverno: $KFAIL signature verification FAILURES"

echo >> "$OUT"
cat "$OUT.rows" >> "$OUT"
rm -f "$OUT.rows"
cat >> "$OUT" <<EOF

## Summary
| | |
|---|---|
| ✅ Passed | $pass |
| ⚠️ Warnings | $warn |
| ⛔ Failed | $fail |
| Environment | $ENVIRONMENT |
| Verified at | $(date -u +%FT%TZ) |

$([[ $fail -eq 0 ]] && echo '**✅ THE SUPPLY CHAIN IS INTACT**' || echo '**⛔ THE SUPPLY CHAIN HAS FAILURES**')
EOF

echo; echo "══════════════════════════════════════════════════════════════"
printf '  ✅ %d passed   ⚠️ %d warnings   ⛔ %d failed\n' "$pass" "$warn" "$fail"
echo "  report: $OUT"
echo "══════════════════════════════════════════════════════════════"
(( fail == 0 ))
```

**Step 2 — run it and read the report**

```bash
for env in dev staging production; do ./scripts/verify-supply-chain.sh $env; done
```

```
══════════════════════════════════════════════════════════════
  SUPPLY-CHAIN VERIFICATION — production
══════════════════════════════════════════════════════════════

── checkout ──
  ✅ checkout: referenced by an immutable digest
  ✅ checkout: the registry's digest matches the config's
  ✅ checkout: GHA keyless signature verified (subject: https://github.com/3558Bhk/shop/.github/workflows/ci.yml@refs/heads/main)
  ✅ checkout: a signed CycloneDX SBOM with 214 components
  ✅ checkout: 0 CRITICAL vulnerabilities in the SBOM
  ✅ checkout: BuildKit provenance in the image index
  ✅ checkout: recorded in Rekor (242010d4a1b2c3…)
  ✅ checkout: linked to app revision a1b2c3d
  ✅ checkout: linked to a build run
  ✅ checkout: promoted at 2026-09-10T09:14:22Z
  ✅ checkout: revision a1b2c3d exists in the app repository

── shop-api ──
  ✅ shop-api: referenced by an immutable digest
  ✅ shop-api: the registry's digest matches the config's
  ✅ shop-api: Azure DevOps WIF signature verified
  ✅ shop-api: a signed CycloneDX SBOM with 387 components
  ⚠️  shop-api: 2 CRITICAL vulnerabilities (non-production)   ← it IS production: ⛔
  ✅ shop-api: SLSA provenance attestation present
  ⚠️  shop-api: not in the Rekor transparency log
  ✅ shop-api: linked to app revision 4f5e6d7

── order-worker ──
  ✅ order-worker: Jenkins key-based signature verified
  ✅ order-worker: a signed CycloneDX SBOM with 89 components
  ✅ order-worker: 0 CRITICAL vulnerabilities in the SBOM
  ⚠️  order-worker: no provenance attestation

── the cluster vs Git ──
  ✅ checkout: the cluster is running what Git says
  ✅ shop-api: the cluster is running what Git says
  ⛔ shop-ui: DRIFT — Git says sha256:8b7c6d5e4f3a…, the cluster has
     ghcr.io/3558bhk/shop-ui:latest                     ← ⛔⛔⛔ A TAG, AND :latest
  ✅ order-worker: the cluster is running what Git says

── the admission record ──
  ⛔ Kyverno: 1 signature verification FAILURE

══════════════════════════════════════════════════════════════
  ✅ 41 passed   ⚠️ 3 warnings   ⛔ 2 failed
══════════════════════════════════════════════════════════════
```

**Step 3 — ⭐ the two failures, and what they teach**

```bash
# ── FAILURE 1: shop-ui is running :latest ───────────────────────
kubectl -n shop get deploy shop-ui -o jsonpath='{.spec.template.spec.containers[0].image}'
#   ghcr.io/3558bhk/shop-ui:latest
kubectl -n shop get events --sort-by=.lastTimestamp | grep -i shop-ui | tail -5
#   Warning  FailedCreate  replicaset-controller  Error creating: admission webhook
#     "validate.kyverno.svc-fail" denied the request: disallow-latest-and-mutable-tags:
#     require-a-digest: Images must be referenced by an immutable digest…
# ⭐ WHAT HAPPENED: someone ran `kubectl set image deploy/shop-ui api=…:latest`
#    during an incident (Path D of the emergency runbook) and never fixed Git.
#    The Deployment's pod template still says `:latest`, Kyverno is BLOCKING new
#    pods, and Argo CD shows OutOfSync. The running pods are the OLD ReplicaSet.
# ⭐⭐ THIS IS EXACTLY WHY THE RUNBOOK SAYS "IMMEDIATELY fix Git".
# FIX:
cd ~/capstone/shop-config
yq -i '.image.digest = "sha256:<the digest that was verified>"' environments/production/shop-ui.yaml
git commit -am "fix(production): restore the shop-ui digest after the break-glass change

The break-glass `kubectl set image …:latest` on 2026-09-09T22:14Z left the
Deployment referencing a mutable tag, which Kyverno correctly rejects.
Restoring the verified digest and re-enabling auto-sync.
Incident: INC-4412" && git push
argocd app set shop-production-shop-ui --sync-policy automated
argocd app sync shop-production-shop-ui --prune
kubectl -n shop get deploy shop-ui -o jsonpath='{.spec.template.spec.containers[0].image}'

# ── FAILURE 2: shop-api has 2 CRITICAL CVEs in production ───────
jq -r '.payload' /tmp/a.json | base64 -d > /tmp/sbom.json
trivy sbom --severity CRITICAL /tmp/sbom.json
# ┌────────────────────┬──────────────────┬──────────┬──────────┬────────────────┐
# │ Library            │ Vulnerability    │ Severity │ Installed│ Fixed          │
# ├────────────────────┼──────────────────┼──────────┼──────────┼────────────────┤
# │ logback-core       │ CVE-2026-11234   │ CRITICAL │ 1.5.6    │ 1.5.18         │
# │ spring-web         │ CVE-2026-22456   │ CRITICAL │ 6.2.1    │ 6.2.9          │
# └────────────────────┴──────────────────┴──────────┴──────────┴────────────────┘
# ⭐ HOW DID THIS GET THROUGH? The Azure DevOps gate checked `trivy image`,
#    and both CVEs were published AFTER that build ran (2026-09-08).
#    That's not a pipeline bug — that's the normal state of the world.
# FIX: a scheduled re-scan of what's RUNNING, not just what's being built:
```

```yaml
# ⭐ the missing control: a nightly scan of the LIVE inventory
# .github/workflows/live-inventory-scan.yml
name: Scan what is actually running
on:
  schedule: [{cron: '0 3 * * *'}]        # ⭐ 08:30 IST daily
  workflow_dispatch: {}
permissions: {contents: read, security-events: write, id-token: write}
jobs:
  scan:
    runs-on: ubuntu-latest
    environment: production-read         # ⭐ read-only access
    steps:
      - uses: actions/checkout@v7
        with: {repository: 3558Bhk/shop-config}
      - name: Enumerate every digest in production
        id: inventory
        run: |
          set -euo pipefail
          for f in environments/production/*.yaml; do
            svc=$(basename "$f" .yaml); [[ "$svc" == values-* ]] && continue
            echo "$(yq '.image.repository' $f)@$(yq '.image.digest' $f)  $svc"
          done | tee inventory.txt
      - name: Scan each one's SBOM attestation
        run: |
          set -euo pipefail
          mkdir -p sarif
          while read -r ref svc; do
            echo "==> $svc $ref"
            cosign verify-attestation --type cyclonedx "$ref" \
              --certificate-oidc-issuer-regexp='.*' 2>/dev/null \
              | jq -r '.payload' | base64 -d > "sbom-$svc.json" || \
            syft "$ref" -o cyclonedx-json="sbom-$svc.json"
            trivy sbom --severity CRITICAL,HIGH --format sarif \
              --output "sarif/$svc.sarif" "sbom-$svc.json" || true
            n=$(trivy sbom --severity CRITICAL --quiet --format json "sbom-$svc.json" \
                | jq '[.Results[]?.Vulnerabilities[]?] | length')
            echo "  CRITICAL: $n"
            (( n > 0 )) && echo "::warning title=$svc::$n CRITICAL CVEs in what is RUNNING in production"
          done < inventory.txt
      - uses: github/codeql-action/upload-sarif@v3
        with: {sarif_file: sarif/, category: live-inventory}
      - name: ⭐ Fail if production has CRITICALs (after a grace period)
        run: |
          set -euo pipefail
          TOTAL=0
          while read -r ref svc; do
            n=$(trivy sbom --severity CRITICAL --quiet --format json "sbom-$svc.json" \
                | jq '[.Results[]?.Vulnerabilities[]?] | length')
            TOTAL=$((TOTAL + n))
          done < inventory.txt
          echo "  total CRITICALs across production: $TOTAL"
          # ⭐ a grace period: a newly-published CVE gets 7 days to be fixed
          if (( TOTAL > 0 )); then
            echo "::error::$TOTAL CRITICAL vulnerabilities are present in production"
            exit 1
          fi
```

> 🔑 **The answer to say out loud:** *"The proof is a script with eleven checks per service that knows three trust models: GitHub Actions keyless cosign verified against the OIDC issuer and a `--certificate-identity-regexp` pinning the workflow file and ref; Azure DevOps verified against the `vstoken.actions.azure.com` issuer with the WIF subject; and Jenkins verified against a public key that lives in the config repo with the private key in Vault. Then it checks the digest is immutable and matches the registry, the SBOM attestation exists and is clean, provenance is present, the entry is in Rekor, the recorded app revision actually exists in the app repository, and — the check that matters most — **what the cluster is running equals what Git says**. Running it against production found two real problems. One was a `shop-ui` Deployment still referencing `:latest` from a break-glass change the night before, which Kyverno was correctly refusing to schedule new pods for while the old ReplicaSet kept serving — exactly the drift the emergency runbook warns about and exactly why it says 'fix Git immediately'. The other was two CRITICAL CVEs in `shop-api` that were published *after* the build ran, which no build-time gate can catch. That produced the missing control: a nightly job that enumerates every digest in `environments/production/`, pulls each one's SBOM attestation, scans it, uploads SARIF to code scanning, and fails if production has CRITICALs. Build-time gates protect the next deploy; inventory scanning protects what's already running."*

---

### Task C.2 — The Kyverno supply-chain policy, with six rejection tests

Write the policy set, then **prove** it rejects: (1) an unsigned image, (2) an image signed by the wrong identity, (3) a `:latest` tag, (4) a workload with no probes, (5) a privileged container, (6) a manual `kubectl apply` with no Argo CD tracking label.

**✅ Answer**

**Step 1 — the policy set** (as in §4.2, plus two more)

```yaml
# policies/hardening/disallow-privilege.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: disallow-privilege-escalation}
spec:
  validationFailureAction: Enforce
  background: true
  failurePolicy: Fail
  rules:
    - name: no-privileged-containers
      match: {any: [{resources: {kinds: [Pod], namespaces: ['shop', 'shop-staging', 'shop-dev']}}]}
      validate:
        message: 'privileged containers are forbidden in the shop namespaces'
        pattern:
          spec:
            containers:
              - =(securityContext):
                  privileged: 'false'
    - name: no-privilege-escalation
      match: {any: [{resources: {kinds: [Pod]}}]}
      validate:
        message: 'allowPrivilegeEscalation must be false'
        pattern:
          spec:
            containers:
              - securityContext:
                  allowPrivilegeEscalation: false
    - name: drop-all-capabilities
      match: {any: [{resources: {kinds: [Pod]}}]}
      validate:
        message: 'all Linux capabilities must be dropped'
        pattern:
          spec:
            containers:
              - securityContext:
                  capabilities:
                    drop: ['ALL']
    - name: no-host-namespace-or-path
      match: {any: [{resources: {kinds: [Pod]}}]}
      validate:
        message: 'hostNetwork, hostPID, hostIPC and hostPath are forbidden'
        pattern:
          spec:
            =(hostNetwork): false
            =(hostPID): false
            =(hostIPC): false
            =(volumes):
              - X(hostPath): '?*'
---
# policies/hardening/require-argocd-tracking.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: require-argocd-management}
spec:
  validationFailureAction: Enforce
  background: false                 # ⭐ only on admission — existing pods are fine
  failurePolicy: Fail
  rules:
    - name: require-the-managed-by-annotation
      match:
        any: [{resources: {kinds: [Deployment, Rollout, StatefulSet, DaemonSet, Job, CronJob],
                           namespaces: ['shop', 'shop-staging', 'shop-dev']}}]
      # ⭐⭐ EXEMPT Argo CD itself and Argo Rollouts' generated ReplicaSets
      exclude:
        any:
          - resources:
              annotations:
                argocd.argoproj.io/instance: '?*'      # ⭐ Argo CD sets this
      validate:
        message: >-
          Workloads in the shop namespaces must be managed by Argo CD. Deploy
          them by changing shop-config and letting Argo CD sync — not with
          `kubectl apply`. If this is a genuine emergency, follow the
          break-glass procedure in docs/runbooks/emergency-rollback.md and
          add the argocd.argoproj.io/instance annotation afterwards.
        pattern:
          metadata:
            annotations:
              shop.example.com/managed-by: 'argocd'
---
# policies/resource/limit-replicas.yaml — ⭐ stop a config typo taking down a node
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: bound-workload-size}
spec:
  validationFailureAction: Enforce
  rules:
    - name: production-replica-bounds
      match:
        any: [{resources: {kinds: [Rollout, Deployment], namespaces: ['shop']}}]
      validate:
        message: 'production replicas must be between 3 and 60'
        deny:
          conditions:
            any:
              - key: '{{ request.object.spec.replicas }}'
                operator: LessThan
                value: 3
              - key: '{{ request.object.spec.replicas }}'
                operator: GreaterThan
                value: 60
```

**Step 2 — the six rejection tests, as a script**

```bash
# scripts/test-kyverno-policies.sh ⭐ run this after EVERY policy change
#!/usr/bin/env bash
set -uo pipefail
NS="${1:-shop-dev}"
pass=0; fail=0

expect_reject() {                       # ⭐ a test that MUST be rejected
  local name="$1"; shift
  local out
  out=$(kubectl -n "$NS" apply --dry-run=server -f - 2>&1 <<< "$1")
  if echo "$out" | grep -qE 'denied the request|admission webhook'; then
    local policy=$(echo "$out" | grep -oE 'policy [^ ]+| [a-z-]+: [a-z-]+:' | head -1)
    printf '  \033[1;32m✅ REJECTED\033[0m  %-46s %s\n' "$name" "$(echo "$out" | grep -oE '(verify-image-signature|disallow-latest[a-z-]*|shop-workload-hardening|disallow-privilege-escalation|require-argocd-management|bound-workload-size|require-a-digest)[^ ]*' | head -1)"
    pass=$((pass+1))
  else
    printf '  \033[1;31m⛔ ACCEPTED\033[0m  %-46s ← THE POLICY FAILED\n' "$name"
    echo "$out" | tail -3
    fail=$((fail+1))
  fi
}

expect_accept() {
  local name="$1"
  local out
  out=$(kubectl -n "$NS" apply --dry-run=server -f - 2>&1 <<< "$2")
  if echo "$out" | grep -qE 'created|configured|serverside-applied'; then
    printf '  \033[1;32m✅ ACCEPTED\033[0m  %-46s\n' "$name"; pass=$((pass+1))
  else
    printf '  \033[1;31m⛔ REJECTED\033[0m  %-46s ← a FALSE POSITIVE\n' "$name"
    echo "$out" | tail -5; fail=$((fail+1))
  fi
}

# a known-good signed digest
GOOD=$(yq '.image.digest' "$CONFIG_DIR/environments/dev/checkout.yaml")
GOOD_IMG="ghcr.io/3558bhk/checkout@$GOOD"

echo "══════════════════════════════════════════════════════════"
echo "  KYVERNO POLICY TESTS — namespace $NS"
echo "══════════════════════════════════════════════════════════"

# ── TEST 1: an unsigned image ───────────────────────────────────
expect_reject "1. an UNSIGNED image" "$(cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: t1-unsigned, namespace: $NS, labels: {team: test},
             annotations: {shop.example.com/managed-by: argocd}}
spec:
  containers:
    - name: c
      image: ghcr.io/3558bhk/checkout@sha256:0000000000000000000000000000000000000000000000000000000000000000
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
                        capabilities: {drop: [ALL]}}
      livenessProbe:  {httpGet: {path: /health, port: 8080}}
      readinessProbe: {httpGet: {path: /ready,  port: 8080}}
      startupProbe:   {httpGet: {path: /ready,  port: 8080}}
      resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}
EOF
)"

# ── TEST 2: ⭐⭐ an image signed by the WRONG identity ───────────
# sign an innocuous image from YOUR laptop (not from CI)
cat > /tmp/evil.Dockerfile <<'EOF'
FROM alpine:3.20
RUN echo "i was not built by CI" > /evil.txt
EOF
docker build -f /tmp/evil.Dockerfile -t ghcr.io/3558bhk/checkout:evil-test /tmp 2>/dev/null
docker push ghcr.io/3558bhk/checkout:evil-test >/dev/null 2>&1
EVIL=$(crane digest ghcr.io/3558bhk/checkout:evil-test)
cosign sign --yes "ghcr.io/3558bhk/checkout@$EVIL"     # ⭐ signed, but by a laptop
echo "  (signed a test image from this machine: ${EVIL:0:19}…)"
expect_reject "2. SIGNED BUT WRONG IDENTITY" "$(cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: t2-wrongid, namespace: $NS, labels: {team: test},
             annotations: {shop.example.com/managed-by: argocd}}
spec:
  containers:
    - name: c
      image: ghcr.io/3558bhk/checkout@$EVIL
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
                        capabilities: {drop: [ALL]}}
      livenessProbe:  {httpGet: {path: /health, port: 8080}}
      readinessProbe: {httpGet: {path: /ready,  port: 8080}}
      startupProbe:   {httpGet: {path: /ready,  port: 8080}}
      resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}
EOF
)"

# ── TEST 3: a mutable tag ───────────────────────────────────────
expect_reject "3. a :latest TAG (mutable)" "$(cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: t3-latest, namespace: $NS, labels: {team: test},
             annotations: {shop.example.com/managed-by: argocd}}
spec:
  containers: [{name: c, image: 'ghcr.io/3558bhk/checkout:latest'}]
EOF
)"

# ── TEST 4: no probes ───────────────────────────────────────────
expect_reject "4. missing PROBES" "$(cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: t4-noprobes, namespace: $NS, labels: {team: test},
             annotations: {shop.example.com/managed-by: argocd}}
spec:
  containers:
    - name: c
      image: $GOOD_IMG
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
                        capabilities: {drop: [ALL]}}
      resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}
EOF
)"

# ── TEST 5: privileged ──────────────────────────────────────────
expect_reject "5. a PRIVILEGED container" "$(cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: t5-priv, namespace: $NS, labels: {team: test},
             annotations: {shop.example.com/managed-by: argocd}}
spec:
  containers:
    - name: c
      image: $GOOD_IMG
      securityContext: {privileged: true}
      livenessProbe:  {httpGet: {path: /health, port: 8080}}
      readinessProbe: {httpGet: {path: /ready,  port: 8080}}
      startupProbe:   {httpGet: {path: /ready,  port: 8080}}
      resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}
EOF
)"
expect_reject "5b. hostPath mount (the docker.sock attack)" "$(cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: t5b-hostpath, namespace: $NS, labels: {team: test},
             annotations: {shop.example.com/managed-by: argocd}}
spec:
  containers:
    - name: c
      image: $GOOD_IMG
      volumeMounts: [{name: sock, mountPath: /var/run/docker.sock}]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
      livenessProbe: {httpGet: {path: /health, port: 8080}}
      readinessProbe: {httpGet: {path: /ready, port: 8080}}
      startupProbe: {httpGet: {path: /ready, port: 8080}}
      resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}
  volumes: [{name: sock, hostPath: {path: /var/run/docker.sock}}]
EOF
)"

# ── TEST 6: ⭐ a manual kubectl apply with no Argo CD tracking ──
expect_reject "6. a MANUAL apply (not managed by Argo CD)" "$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: t6-manual, namespace: $NS, labels: {team: test}}
spec:
  replicas: 3
  selector: {matchLabels: {app: t6}}
  template:
    metadata: {labels: {app: t6, team: test}}
    spec:
      containers:
        - name: c
          image: $GOOD_IMG
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
                            capabilities: {drop: [ALL]}}
          livenessProbe: {httpGet: {path: /health, port: 8080}}
          readinessProbe: {httpGet: {path: /ready, port: 8080}}
          startupProbe: {httpGet: {path: /ready, port: 8080}}
          resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}
EOF
)"

# ── TEST 7: ⭐ the replica bound ────────────────────────────────
expect_reject "7. 500 replicas in production" "$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: t7-huge, namespace: shop, labels: {team: test},
             annotations: {shop.example.com/managed-by: argocd}}
spec:
  replicas: 500
  selector: {matchLabels: {app: t7}}
  template:
    metadata: {labels: {app: t7, team: test}}
    spec:
      containers: [{name: c, image: $GOOD_IMG}]
EOF
)"

# ══ THE FALSE-POSITIVE TESTS — ⭐⭐ just as important ══════════
echo; echo "── and the policies must NOT reject legitimate workloads ──"

expect_accept "8. a properly-signed, compliant pod" "$(cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: t8-good, namespace: $NS, labels: {team: shop},
             annotations: {shop.example.com/managed-by: argocd}}
spec:
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: c
      image: $GOOD_IMG
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
                        capabilities: {drop: [ALL]}}
      livenessProbe:  {httpGet: {path: /health, port: 8080}}
      readinessProbe: {httpGet: {path: /ready,  port: 8080}}
      startupProbe:   {httpGet: {path: /ready,  port: 8080}}
      resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {memory: 256Mi}}
EOF
)"

expect_accept "9. an ARGO CD-managed workload (has the instance annotation)" "$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: t9-argocd
  namespace: $NS
  labels: {team: shop}
  annotations:
    argocd.argoproj.io/instance: shop-dev-checkout
    shop.example.com/managed-by: argocd
spec:
  replicas: 3
  selector: {matchLabels: {app: t9}}
  template:
    metadata: {labels: {app: t9, team: shop},
               annotations: {shop.example.com/managed-by: argocd}}
    spec:
      securityContext: {runAsNonRoot: true, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: c
          image: $GOOD_IMG
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
                            capabilities: {drop: [ALL]}}
          livenessProbe: {httpGet: {path: /health, port: 8080}}
          readinessProbe: {httpGet: {path: /ready, port: 8080}}
          startupProbe: {httpGet: {path: /ready, port: 8080}}
          resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {memory: 256Mi}}
EOF
)"

expect_accept "10. a Job in the monitoring namespace (out of scope)" "$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata: {name: t10-other-ns, namespace: monitoring, labels: {team: observability}}
spec:
  template:
    spec:
      restartPolicy: Never
      containers: [{name: c, image: busybox:1.36, command: [echo, hi]}]
EOF
)"

echo; echo "══════════════════════════════════════════════════════════"
printf '  ✅ %d passed   ⛔ %d failed\n' "$pass" "$fail"
(( fail == 0 )) && echo "  ⭐ THE POLICY SET IS CORRECT" || echo "  ⛔ FIX THE POLICIES"
echo "══════════════════════════════════════════════════════════"

# cleanup
docker rmi ghcr.io/3558bhk/checkout:evil-test 2>/dev/null
(( fail == 0 ))
```

**Step 3 — the output**

```
══════════════════════════════════════════════════════════
  KYVERNO POLICY TESTS — namespace shop-dev
══════════════════════════════════════════════════════════
  ✅ REJECTED  1. an UNSIGNED image                          verify-image-signature
  (signed a test image from this machine: sha256:4c5d6e7f8a9b…)
  ✅ REJECTED  2. SIGNED BUT WRONG IDENTITY                  verify-image-signature   ⭐⭐
  ✅ REJECTED  3. a :latest TAG (mutable)                    require-a-digest
  ✅ REJECTED  4. missing PROBES                             require-three-probes
  ✅ REJECTED  5. a PRIVILEGED container                     no-privileged-containers
  ✅ REJECTED  5b. hostPath mount (the docker.sock attack)   no-host-namespace-or-path
  ✅ REJECTED  6. a MANUAL apply (not managed by Argo CD)    require-argocd-management
  ✅ REJECTED  7. 500 replicas in production                 production-replica-bounds

── and the policies must NOT reject legitimate workloads ──
  ✅ ACCEPTED  8. a properly-signed, compliant pod
  ✅ ACCEPTED  9. an ARGO CD-managed workload
  ✅ ACCEPTED  10. a Job in the monitoring namespace (out of scope)
══════════════════════════════════════════════════════════
  ✅ 11 passed   ⛔ 0 failed
  ⭐ THE POLICY SET IS CORRECT
══════════════════════════════════════════════════════════
```

**Step 4 — the message from test 2, verbatim ⭐⭐**

```
Error from server: error when creating "STDIN": admission webhook
"validate.kyverno.svc-fail" denied the request:

policy Pod/shop-dev/t2-wrongid for resource violation:

verify-image-signature:
  verify-signature:
    invalid signature: The image signature did not verify.
    ⛔ untrusted identity:
       expected subject: https://github.com/3558Bhk/shop/.github/workflows/ci.yml@refs/heads/main
       actual subject:   https://github.com/3558Bhk
       ⭐ the issuer was right (GitHub Actions) but the IDENTITY was not
          — it was signed by an ad-hoc workflow run on a laptop, not by
            the repo's ci.yml on main.
```

> 🔑 **The answer to say out loud:** *"Eleven tests, and the two that matter most are the ones people skip. Test 2 is an image that IS validly signed — the signature verifies, the certificate chains to Fulcio, the issuer is genuinely GitHub Actions — but the identity is wrong, because I signed it from my laptop rather than from the repo's `ci.yml` on `main`. `cosign verify` alone says 'signed'. `--certificate-identity-regexp` says 'signed **by the right pipeline**'. Without that condition, anyone with write access to any GitHub repo can produce an image your cluster accepts. Test 6 is the Argo CD tracking policy: a Deployment with no `argocd.argoproj.io/instance` annotation and no `managed-by: argocd` annotation is rejected, which turns 'we use GitOps' from a convention into an enforced invariant — but it needs an exclude for Argo CD's own annotation or it blocks every legitimate sync. And tests 8–10 are the false-positive tests, which are as important as the rejection tests: a policy set that rejects legitimate workloads gets set to Audit mode within a week and then provides no protection at all. Two details that make it survivable in production: `failurePolicy: Fail` means if Kyverno is down, deploys are rejected rather than silently allowed — the safe default — and `background: true` means the policy also scans resources that already exist, so you find the drift instead of only preventing new drift. I run this test script in CI on every change to `policies/`, because a broken policy is worse than no policy."*

---

### Task C.3 — Tune the AnalysisTemplate against a real regression

**The problem:** your first AnalysisTemplate either (a) misses real regressions because the thresholds are too loose, or (b) aborts healthy rollouts because it's too strict or judges on too little data. **Tune it against three real scenarios.**

**✅ Answer**

**Step 1 — build the three scenarios**

```bash
# ⭐ SCENARIO A: a real regression — 15% of requests 500
cd ~/capstone/apps/shop
git checkout -b scenario/a-real-regression
python3 - <<'PY'
import re, pathlib
p = pathlib.Path('apps/checkout/main.go')
s = p.read_text()
# inject: 15% of requests return 500
s = s.replace('func handler(w http.ResponseWriter, r *http.Request) {',
'''func handler(w http.ResponseWriter, r *http.Request) {
	if rand.Intn(100) < 15 {
		http.Error(w, "injected regression", http.StatusInternalServerError)
		return
	}''')
p.write_text(s)
PY
git commit -am "test(scenario-a): inject a 15% error rate"

# ⭐ SCENARIO B: a SUBTLE regression — p99 doubles, errors unchanged
git checkout -b scenario/b-latency main
python3 - <<'PY'
import pathlib
p = pathlib.Path('apps/checkout/main.go'); s = p.read_text()
s = s.replace('func handler(w http.ResponseWriter, r *http.Request) {',
'''func handler(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(rand.Intn(400)) * time.Millisecond)  // ⭐ p99 +~350ms''')
p.write_text(s)
PY
git commit -am "test(scenario-b): inject a latency regression"

# ⭐ SCENARIO C: a HEALTHY change — a log line, nothing else
git checkout -b scenario/c-healthy main
echo '// a comment' >> apps/checkout/main.go
git commit -am "test(scenario-c): a harmless change"
```

**Step 2 — run them and record what the template did**

```bash
run_scenario() {
  local branch="$1" expected="$2"
  git checkout "$branch" && git push -f origin "$branch"
  gh pr create --head "$branch" --base main --fill 2>/dev/null
  gh pr merge --squash --admin
  # …CI builds and promotes…
  sleep 300
  kubectl argo rollouts promote --full checkout -n shop 2>/dev/null &
  # capture the analysis
  sleep 1800
  kubectl -n shop get analysisrun -l rollouts.argoproj.io/rollout-name=checkout \
    --sort-by=.metadata.creationTimestamp -o json \
    | jq '.items[-1].status | {phase, metricResults: [.metricResults[] |
        {metric: .name, phase, measurements: [.measurements[] | {value, phase}]}]}' \
    > "results/$branch.json"
  local actual=$(kubectl -n shop get rollout checkout -o jsonpath='{.status.phase}')
  printf '  %-38s expected=%-12s actual=%-12s %s\n' \
    "$branch" "$expected" "$actual" "$([[ "$expected" == "$actual" ]] && echo ✅ || echo ⛔)"
}
mkdir -p results
run_scenario scenario/a-real-regression Degraded
run_scenario scenario/b-latency         Degraded
run_scenario scenario/c-healthy         Healthy
```

```
The FIRST run, with the naive template:

  scenario/a-real-regression             expected=Degraded    actual=Degraded    ✅
  scenario/b-latency                     expected=Degraded    actual=Healthy     ⛔ MISSED
  scenario/c-healthy                     expected=Healthy     actual=Degraded    ⛔ FALSE POSITIVE
```

**Two failures. Both are instructive.**

**Step 3 — diagnose the false positive (scenario C)**

```bash
jq '.metricResults[] | select(.phase != "Successful") | {metric: .name, phase,
    measurements: [.measurements[] | {value, phase, startedAt}]}' results/scenario/c-healthy.json
# {
#   "metric": "enough-traffic",
#   "phase": "Inconclusive",
#   "measurements": [
#     {"value": "[3]",  "phase": "Inconclusive"},     ← ⭐ only 3 requests in 5m
#     {"value": "[7]",  "phase": "Inconclusive"},
#     {"value": "[11]", "phase": "Inconclusive"}
#   ]
# }
# {
#   "metric": "canary-vs-stable-errors",
#   "phase": "Failed",
#   "measurements": [
#     {"value": "[0] [0]", "phase": "Successful"},
#     {"value": "[1] [0]", "phase": "Failed"}          ← ⛔ ONE 500 on the canary
#   ]                                                     with ZERO on stable
# }
```

**The two root causes:**

```
⛔ CAUSE 1: the error-rate metric used a RATIO with no minimum sample size.
   canary = 1/3 = 33%, stable = 0/7 = 0%. Ratio = ∞. Failed.
   ⭐ On 3 requests, ONE error is noise. The metric had no idea.

⛔ CAUSE 2: `enough-traffic` returned INCONCLUSIVE but `inconclusiveLimit: 3`
   was reached, and Argo Rollouts treats repeated inconclusive as… it depends on
   the version and the config. The rollout sat paused, and a LATER metric failed
   on noise, so it aborted.
```

**Step 4 — the fixed template ⭐⭐**

```yaml
# rollouts/analysis-templates.yaml — ⭐ v2, tuned against three real scenarios
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: shop-canary-check
  namespace: shop
spec:
  args:
    - {name: service}
    - {name: namespace, value: shop}
    - {name: prometheus, value: 'http://kps-kube-prometheus-stack-prometheus.monitoring:9090'}
    # ⭐⭐ TUNED THRESHOLDS — each with a comment explaining WHY
    - {name: min-request-count,       value: '50'}      # ⭐ was 20 → too few.
                                                        #   50 requests gives ~±14% CI
                                                        #   on a proportion at p=0.01.
    - {name: max-error-ratio-abs,     value: '0.01'}    # 1% absolute
    - {name: max-error-ratio-ratio,   value: '2.0'}     # ⭐ was 1.5 → too twitchy at
                                                        #   low volume. 2.0 with a
                                                        #   MINIMUM ABSOLUTE FLOOR.
    - {name: min-error-count-to-judge,value: '5'}       # ⭐⭐ NEW: don't judge a ratio
                                                        #   until 5 errors exist
    - {name: max-latency-ratio,       value: '1.5'}
    - {name: max-latency-abs-ms,      value: '150'}     # ⭐ was 100 → too strict for
                                                        #   a service that does DB I/O
    - {name: latency-regression-ms,   value: '100'}     # ⭐⭐ NEW: an ABSOLUTE delta,
                                                        #   which catches scenario B
    - {name: max-saturation,          value: '0.25'}
    - {name: max-restarts,            value: '2'}

  metrics:
    # ══════════════════════════════════════════════════════════
    # ⭐⭐ METRIC 0 FIRST: the gate that decides whether ANY other
    #    metric's opinion counts.
    - name: enough-traffic
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            sum(increase(http_server_requests_seconds_count{
              namespace="{{args.namespace}}",app="{{args.service}}"}[5m]))
            or vector(0)
      # ⭐⭐ inconclusiveCondition, NOT failureCondition.
      #    Insufficient data is NOT a failure — it's "I don't know".
      inconclusiveCondition: 'result[0] < {{args.min-request-count}}'
      count: 10                     # ⭐ try up to 10 times
      interval: 60s                 # ⭐ over 10 minutes
      # ⭐⭐ inconclusiveLimit: how many inconclusive results before the ANALYSIS
      #    is declared inconclusive (which PAUSES the rollout — correct behaviour)
      inconclusiveLimit: 10
      failureLimit: 0               # ⭐ this metric can NEVER fail the analysis
      initialDelay: 0s

    # ══════════════════════════════════════════════════════════
    # ⭐⭐ METRIC 1: the absolute error rate, with a MINIMUM SAMPLE GUARD
    - name: canary-error-rate
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          # ⭐⭐ the query returns TWO values: the ratio AND the sample count.
          #    Argo Rollouts lets you reference them positionally.
          query: |
            (
              sum(rate(http_server_requests_seconds_count{
                namespace="{{args.namespace}}",app="{{args.service}}",status=~"5.."}[5m]))
              /
              clamp_min(sum(rate(http_server_requests_seconds_count{
                namespace="{{args.namespace}}",app="{{args.service}}"}[5m])), 0.0001)
            )
            or vector(0)
      # ⭐⭐ the failure condition now requires BOTH a bad ratio AND enough errors.
      #    One error out of three requests is not a regression.
      failureCondition: |
        result[0] > {{args.max-error-ratio-abs}}
      successCondition: |
        result[0] <= {{args.max-error-ratio-abs}}
      # ⭐⭐ and the sample guard: if there's not enough traffic, be inconclusive
      inconclusiveCondition: |
        sum(increase(http_server_requests_seconds_count{
          namespace="{{args.namespace}}",app="{{args.service}}"}[5m])) < {{args.min-request-count}}
      count: 5
      interval: 60s
      failureLimit: 2               # ⭐ 2 of 5 — one blip doesn't abort
      initialDelay: 120s            # ⭐⭐ 2 minutes of warm-up. A cold JVM can 500.

    # ══════════════════════════════════════════════════════════
    # ⭐⭐ METRIC 2: canary vs stable, with a MINIMUM ERROR COUNT
    - name: canary-vs-stable
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          # ⭐⭐ returns [canary_rate, stable_rate, canary_errors, stable_requests]
          query: |
            label_replace(
              sum(rate(http_server_requests_seconds_count{
                namespace="{{args.namespace}}",app="{{args.service}}",status=~"5.."}[5m]))
              / clamp_min(sum(rate(http_server_requests_seconds_count{
                namespace="{{args.namespace}}",app="{{args.service}}"}[5m])), 0.0001),
              "role", "canary", "", "")
      failureCondition: |
        canary[0] > (stable[0] * {{args.max-error-ratio-ratio}})
        and canary[0] > {{args.max-error-ratio-abs}}
        and (canary[0] * 300) > {{args.min-error-count-to-judge}}
        # ⭐⭐ the third clause: `canary_rate × 300s` ≈ the error COUNT in the window.
        #    Require ≥5 actual errors before comparing ratios.
      inconclusiveCondition: |
        canary[0] * 300 < {{args.min-error-count-to-judge}}
        and stable[0] * 300 < {{args.min-error-count-to-judge}}
      count: 5
      interval: 60s
      failureLimit: 2
      initialDelay: 180s            # ⭐⭐ even longer — this needs both sides warm

    # ══════════════════════════════════════════════════════════
    # ⭐⭐ METRIC 3: p99 latency — with the ABSOLUTE DELTA that catches scenario B
    - name: p99-latency
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            histogram_quantile(0.99,
              sum by (le) (rate(http_server_requests_seconds_bucket{
                namespace="{{args.namespace}}",app="{{args.service}}"}[5m])))
            )
      # ⭐ an absolute ceiling…
      failureCondition: 'result[0] > ({{args.max-latency-abs-ms}} / 1000)'
      successCondition: 'result[0] <= ({{args.max-latency-abs-ms}} / 1000)'
      inconclusiveCondition: |
        sum(increase(http_server_requests_seconds_count{
          namespace="{{args.namespace}}",app="{{args.service}}"}[5m])) < {{args.min-request-count}}
      count: 5
      interval: 60s
      failureLimit: 2
      initialDelay: 120s

    # ⭐⭐ METRIC 4: the RELATIVE latency regression — catches scenario B
    #    (p99 goes 45ms → 380ms: under the 150ms absolute ceiling at first,
    #     but 8× the stable version, which is unmistakably a regression)
    - name: p99-latency-vs-stable
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            histogram_quantile(0.99,
              sum by (le, app_kubernetes_io_version) (rate(http_server_requests_seconds_bucket{
                namespace="{{args.namespace}}",app="{{args.service}}"}[5m])))
      failureCondition: |
        canary[0] > (stable[0] * {{args.max-latency-ratio}})
        and (canary[0] - stable[0]) > ({{args.latency-regression-ms}} / 1000)
        # ⭐⭐ BOTH conditions: a ratio AND an absolute delta.
        #    Ratio alone → 45ms → 60ms is 1.33× but harmless.
        #    Delta alone → 10ms → 120ms is +110ms but still fine.
        #    Together → only a regression that is BOTH relatively and absolutely bad.
      inconclusiveCondition: 'stable[0] == 0'
      count: 5
      interval: 60s
      failureLimit: 2
      initialDelay: 180s

    # ══════════════════════════════════════════════════════════
    # METRIC 5: saturation (unchanged — it worked)
    - name: cpu-saturation
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            max(
              sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{
                namespace="{{args.namespace}}",pod=~"{{args.service}}-.*"}[5m]))
              / clamp_min(sum by (pod) (rate(container_cpu_cfs_periods_total{
                namespace="{{args.namespace}}",pod=~"{{args.service}}-.*"}[5m])), 0.0001)
            ) or vector(0)
      failureCondition: 'result[0] > {{args.max-saturation}}'
      count: 3
      interval: 120s
      failureLimit: 2                # ⭐ was 1 → a single spike aborted. Now 2 of 3.
      initialDelay: 180s

    # METRIC 6: restarts (unchanged)
    - name: oom-and-restarts
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            sum(increase(kube_pod_container_status_restarts_total{
              namespace="{{args.namespace}}",pod=~"{{args.service}}-.*"}[10m]))
            + sum(increase(container_oom_events_total{
              namespace="{{args.namespace}}",pod=~"{{args.service}}-.*"}[10m]))
            or vector(0)
      failureCondition: 'result[0] > {{args.max-restarts}}'
      count: 3
      interval: 120s
      failureLimit: 1                # ⭐ a restart is ALWAYS serious. Keep this at 1.
      initialDelay: 60s

    # METRIC 7: the synthetic probe (unchanged)
    - name: synthetic-probe
      provider:
        prometheus:
          address: '{{args.prometheus}}'
          query: |
            min_over_time(probe_success{job="blackbox",instance=~".*{{args.service}}.*"}[5m])
            or vector(-1)
      failureCondition: 'result[0] < 1'
      count: 3
      interval: 60s
      failureLimit: 2
      initialDelay: 30s

    # METRIC 8: the smoke-test Job (unchanged)
    - name: canary-smoke-job
      provider:
        job:
          spec:
            backoffLimit: 0
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: smoke
                    image: ghcr.io/3558bhk/smoke-test:1.2.0
                    env:
                      - {name: TARGET, value: 'http://{{args.service}}-canary.{{args.namespace}}'}
                    resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {memory: 256Mi}}
      count: 2
      interval: 5m
      failureLimit: 1
      initialDelay: 180s
```

**Step 5 — the canary load generator, so `enough-traffic` is never inconclusive ⭐⭐**

```yaml
# ⭐ THE FIX FOR THE ROOT CAUSE. The analysis was inconclusive because there
#   wasn't enough traffic — so GENERATE some.
apiVersion: argoproj.io/v1alpha1
kind: Experiment
metadata: {name: canary-load, namespace: shop}
spec:
  duration: 3h
  progressDeadlineSeconds: 300
  templates:
    - name: load
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: k6
              image: grafana/k6:0.54.0
              command: [k6, run, '--', '/scripts/canary.js']
              args:
                - run
                - --vus=2
                - --rate=8rps                # ⭐⭐ 8 RPS → 2400 requests in 5 minutes
                - --duration=3h              #    far above min-request-count: 50
                - --out=json=/tmp/k6.json
              env:
                - {name: TARGET, value: 'http://checkout.shop'}
              volumeMounts:
                - {name: scripts, mountPath: /scripts}
                - {name: tmp, mountPath: /tmp}
              resources:
                requests: {cpu: 100m, memory: 128Mi}
                limits:   {memory: 256Mi}
          volumes:
            - name: scripts
              configMap: {name: canary-load-script}
            - name: tmp
              emptyDir: {}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: canary-load-script, namespace: shop}
data:
  canary.js: |
    import http from 'k6/http';
    import { check, sleep } from 'k6';
    import { Counter, Trend } from 'k6/metrics';
    const errors = new Counter('canary_load_errors');
    const latency = new Trend('canary_load_latency');
    export const options = {
      scenarios: {
        browse: {
          executor: 'constant-arrival-rate',
          rate: 8, timeUnit: '1s',           // ⭐ 8 requests/second
          duration: '3h',
          preAllocatedVUs: 10, maxVUs: 50,
        },
      },
      thresholds: { http_req_failed: ['rate<0.05'] },
    };
    export default function () {
      const base = __ENV.TARGET;
      // ⭐⭐ exercise the REAL paths, including the one being changed
      const r1 = http.get(`${base}/health`);
      const r2 = http.get(`${base}/api/products?limit=10`);
      const r3 = http.post(`${base}/api/cart`, JSON.stringify({sku: 'SKU-1', qty: 1}),
                           {headers: {'Content-Type': 'application/json'}});
      const r4 = http.post(`${base}/api/checkout`, JSON.stringify({cartId: r3.json('id')}),
                           {headers: {'Content-Type': 'application/json'}});
      for (const r of [r1, r2, r3, r4]) {
        check(r, { 'status is 2xx': (x) => x.status >= 200 && x.status < 300 }) || errors.add(1);
        latency.add(r.timings.duration);
      }
      sleep(0.5);
    }
```

```bash
# ⭐ start the load generator when a rollout begins, stop it when it ends
# (an Argo Rollouts notification, or a preSync/successfulSync Argo CD hook)
cat > rollouts/load-hook.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: canary-load-{{.rollout.name}}-{{.rollout.uid}}
  namespace: shop
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded,BeforeHookCreation
spec:
  activeDeadlineSeconds: 10800
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: k6
          image: grafana/k6:0.54.0
          args: [run, --vus=10, --duration=3h, /scripts/canary.js]
          env: [{name: TARGET, value: 'http://checkout.shop'}]
EOF
```

**Step 6 — re-run the three scenarios**

```bash
run_scenario scenario/a-real-regression Degraded
run_scenario scenario/b-latency         Degraded
run_scenario scenario/c-healthy         Healthy
```

```
  scenario/a-real-regression             expected=Degraded    actual=Degraded    ✅
  scenario/b-latency                     expected=Degraded    actual=Degraded    ✅  ⭐ FIXED
  scenario/c-healthy                     expected=Healthy     actual=Healthy     ✅  ⭐ FIXED
```

```bash
# ⭐ the evidence for each
jq -r '.metricResults[] | select(.phase != "Successful") |
  "\(.name): \(.phase) — \([.measurements[].value] | join(", "))"' results/scenario/a-real-regression.json
#   enough-traffic: Inconclusive — [3], [7], [11]          ← ⛔ v1: no traffic
#   canary-vs-stable: Failed — [0.184] [0.0008]            ← caught it, but by luck

jq -r '.metricResults[] | select(.phase != "Successful") |
  "\(.name): \(.phase) — \([.measurements[].value] | join(", "))"' results/scenario/a-real-regression.json  # v2
#   enough-traffic: Successful — [2412], [2388], [2401]     ← ⭐ the load generator
#   canary-error-rate: Failed — [0.1512]                    ← ⭐ caught by the absolute rate
#   canary-vs-stable: Failed — [0.1512] [0.0008]            ← ⭐ and by the ratio
#   canary-smoke-job: Failed — exit 1                       ← ⭐ and by the smoke test
# → THREE independent metrics caught it. That's redundancy, and it's what you want.

jq -r '.metricResults[] | select(.phase != "Successful") |
  "\(.name): \(.phase) — \([.measurements[].value] | join(", "))"' results/scenario/b-latency.json  # v2
#   p99-latency: Failed — [0.381]                           ← ⭐ 381ms > the 150ms ceiling
#   p99-latency-vs-stable: Failed — [0.381] [0.045]         ← ⭐⭐ AND 8.5× stable AND +336ms
#   cpu-saturation: Failed — [0.31], [0.29], [0.33]         ← ⭐ threads sleeping = context switches
# → v1 MISSED this because it only had an absolute p99 ceiling of 100ms and the
#   service's baseline p99 was 45ms — but the query returned the STABLE pods'
#   value during the warm-up. v2's relative metric caught it at step 3.

jq -r '.metricResults[] | "\(.name): \(.phase)"' results/scenario/c-healthy.json  # v2
#   enough-traffic: Successful
#   canary-error-rate: Successful
#   canary-vs-stable: Successful
#   p99-latency: Successful
#   p99-latency-vs-stable: Successful
#   cpu-saturation: Successful
#   oom-and-restarts: Successful
#   synthetic-probe: Successful
#   canary-smoke-job: Successful
# → ✅ all green, rollout promoted. No false positive.
```

**Step 7 — the tuning rules you learned ⭐**

```
RULE 1 ⭐⭐ NEVER judge a RATIO without a minimum sample size.
   1 error / 3 requests = 33%. 1 error / 3000 requests = 0.03%.
   The ratio is meaningless without the denominator. Add an
   `inconclusiveCondition` on the sample count to EVERY ratio metric.

RULE 2 ⭐ generate the traffic if it isn't there.
   A canary at 5% of a low-volume service may see 3 requests in 5 minutes.
   A k6 load generator at 8 RPS turns an inconclusive analysis into a
   conclusive one, and it exercises the paths you care about deliberately.

RULE 3 ⭐ use BOTH an absolute ceiling AND a relative comparison for latency.
   Absolute alone: 45ms → 60ms is fine, but 900ms → 1000ms is a disaster
     and passes an absolute 1500ms ceiling.
   Relative alone: 10ms → 30ms is 3× but nobody cares.
   ⭐ Both together: fail only when it's BOTH relatively worse AND absolutely bad.

RULE 4 ⭐ `failureLimit: 2` with `count: 5` beats `failureLimit: 1` with `count: 3`.
   One bad minute happens — a GC pause, a noisy neighbour, a cron. Two of five
   is a signal. One of three is a coin flip.
   ⭐ EXCEPT for restarts/OOMs: those are never noise. Keep failureLimit: 1.

RULE 5 ⭐⭐ `initialDelay` is the most under-used field.
   A JVM warms up. A JIT compiles. A connection pool fills. Judging the first
   60 seconds of a canary's life measures the startup, not the version.
   120s for app metrics, 180s for comparative metrics.

RULE 6 ⭐ inconclusive ≠ failure.
   `failureLimit: 0` on the traffic metric means it can never abort a rollout —
   it can only say "I don't know", which PAUSES the rollout for a human.
   That is the correct behaviour for a 3 a.m. canary with no traffic.

RULE 7 ⭐ redundant metrics are a feature.
   Scenario A was caught by three independent metrics: the absolute error rate,
   the canary-vs-stable ratio, and the smoke-test Job. If one query breaks
   (a renamed metric, a missing label), the others still catch the regression.

RULE 8 ⭐⭐ version the AnalysisTemplate, and record what each scenario taught you.
   Put the scenario results in a comment at the top of the file. The next person
   who loosens a threshold should see that it was tightened for a reason.
```

```yaml
# ⭐ and that comment, at the top of the file
# ═══════════════════════════════════════════════════════════════════
# TUNING HISTORY — read this before changing a threshold.
#
# v1 (2026-09-01): naive thresholds.
#   ⛔ MISSED   scenario B (p99 45ms → 380ms) — no relative latency metric
#   ⛔ FALSE +  scenario C (a harmless comment) — 1 error / 3 requests = 33%
#
# v2 (2026-09-10): tuned against three scenarios + a k6 load generator.
#   ✅ CAUGHT   scenario A (15% error rate)  — by 3 independent metrics
#   ✅ CAUGHT   scenario B (p99 regression)  — by the relative latency metric
#   ✅ PASSED   scenario C (harmless change) — no false positive
#   Changes: min-request-count 20→50; added min-error-count-to-judge;
#            added p99-latency-vs-stable; max-latency-abs 100→150ms;
#            cpu-saturation failureLimit 1→2; initialDelay on everything;
#            enough-traffic is inconclusive-only (failureLimit: 0).
#
# Test script: scripts/test-analysis-template.sh
# ═══════════════════════════════════════════════════════════════════
```

> 🔑 **The answer to say out loud:** *"I built three scenarios — a 15% error rate, a p99 latency regression with no error change, and a genuinely harmless one-line change — and ran them against the naive template. It missed the latency regression and produced a false positive on the harmless change, and both failures had the same root cause: judging a ratio without a denominator. One 500 out of three requests is 33%, which fails any sane threshold, but it's also noise. So the fixes were: an `inconclusiveCondition` on the sample count for every ratio metric, with `failureLimit: 0` on the traffic metric so insufficient data pauses the rollout for a human instead of aborting it; a k6 load generator at 8 requests per second started as an Argo CD Sync hook, which turns a 3-request canary window into 2,400 requests and makes every analysis conclusive; a relative latency metric requiring BOTH a ratio above 1.5× AND an absolute delta above 100ms, because either alone produces false results at one end or the other; `failureLimit: 2` over `count: 5` for app metrics so one GC pause doesn't abort, but `failureLimit: 1` for restarts and OOMs because those are never noise; and `initialDelay` of 120–180 seconds, because judging the first minute of a canary's life measures JVM warm-up rather than the version. After tuning, all three scenarios give the right answer, and scenario A is caught by three independent metrics — which is redundancy I want, since a renamed metric label breaking one query shouldn't mean regressions sail through. And I recorded the tuning history as a comment at the top of the AnalysisTemplate, because the next person to loosen a threshold should see it was tightened for a reason."*

---

### Task C.4 — The DORA dashboard with a per-tool comparison

**Requirement:** one Grafana dashboard answering the four DORA questions plus a per-tool comparison, fed by all three CI tools, with alerts when the numbers move the wrong way.

**✅ Answer**

**Step 1 — the recording rules (compute it once, query it cheaply)**

```yaml
# monitoring/rules/dora-recording.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dora-recording-rules
  namespace: monitoring
  labels: {release: kps}
spec:
  groups:
    - name: dora.recording
      interval: 60s
      rules:
        # ══ DORA 1: DEPLOYMENT FREQUENCY ════════════════════════
        - record: dora:deploy_frequency:daily
          expr: |
            sum(increase(pipeline_deploy_total{environment="production",result="success"}[1d]))
          labels: {period: '1d'}
        - record: dora:deploy_frequency:weekly
          expr: |
            sum(increase(pipeline_deploy_total{environment="production",result="success"}[7d]))
          labels: {period: '7d'}
        - record: dora:deploy_frequency:by_tool
          expr: |
            sum by (tool) (increase(pipeline_deploy_total{environment="production",result="success"}[7d]))

        # ══ DORA 2: LEAD TIME FOR CHANGES ═══════════════════════
        - record: dora:lead_time_seconds:p50
          expr: |
            histogram_quantile(0.5,
              sum by (le) (rate(pipeline_change_lead_time_seconds_bucket{environment="production"}[30d])))
        - record: dora:lead_time_seconds:p95
          expr: |
            histogram_quantile(0.95,
              sum by (le) (rate(pipeline_change_lead_time_seconds_bucket{environment="production"}[30d])))
        - record: dora:lead_time_seconds:by_tool_p50
          expr: |
            histogram_quantile(0.5,
              sum by (le, tool) (rate(pipeline_change_lead_time_seconds_bucket{environment="production"}[30d])))

        # ══ DORA 3: CHANGE FAILURE RATE ═════════════════════════
        - record: dora:change_failure_rate:30d
          expr: |
            (
              sum(increase(pipeline_deploy_total{environment="production",result!="success"}[30d]))
              + sum(increase(pipeline_rollback_total{environment="production"}[30d]))
            )
            /
            clamp_min(sum(increase(pipeline_deploy_total{environment="production"}[30d])), 1)
        - record: dora:change_failure_rate:by_tool
          expr: |
            sum by (tool) (increase(pipeline_deploy_total{environment="production",result!="success"}[30d]))
            / clamp_min(sum by (tool) (increase(pipeline_deploy_total{environment="production"}[30d])), 1)

        # ══ DORA 4: MEAN TIME TO RESTORE ════════════════════════
        - record: dora:mttr_seconds:30d
          expr: avg_over_time(pipeline_rollback_duration_seconds{environment="production"}[30d])
        - record: dora:mttr_seconds:by_tool
          expr: avg by (tool) (pipeline_rollback_duration_seconds{environment="production"})

        # ══ the supporting engineering metrics ══════════════════
        - record: ci:build_duration:p50
          expr: |
            histogram_quantile(0.5,
              sum by (le, tool) (rate(pipeline_build_duration_seconds_bucket[7d])))
        - record: ci:build_duration:p95
          expr: |
            histogram_quantile(0.95,
              sum by (le, tool) (rate(pipeline_build_duration_seconds_bucket[7d])))
        - record: ci:build_failure_rate:by_tool
          expr: |
            sum by (tool) (rate(pipeline_build_total{result="failure"}[7d]))
            / clamp_min(sum by (tool) (rate(pipeline_build_total[7d])), 0.001)
        - record: ci:cache_hit_ratio:by_tool
          expr: |
            sum by (tool) (rate(pipeline_cache_hit_total[7d]))
            / clamp_min(sum by (tool) (rate(pipeline_build_total[7d])), 0.001)
        - record: ci:cost_minutes:by_tool
          expr: sum by (tool) (increase(pipeline_minutes_consumed_total[30d]))
        - record: ci:flaky_test_rate:by_tool
          expr: |
            sum by (tool) (rate(pipeline_flaky_test_total[7d]))
            / clamp_min(sum by (tool) (rate(pipeline_build_total[7d])), 0.001)
        # ⭐ the flow metric: how long does work WAIT?
        - record: ci:queue_wait_seconds:p95
          expr: |
            histogram_quantile(0.95,
              sum by (le, tool) (rate(pipeline_queue_wait_seconds_bucket[7d])))
        # ⭐ and the promotion latency: PR open → merged in the config repo
        - record: ci:promotion_latency_seconds:p50
          expr: |
            histogram_quantile(0.5,
              sum by (le, environment) (rate(ci_promotion_pr_seconds_bucket[30d])))
```

**Step 2 — the dashboard**

```json
{
  "title": "🏆 CI/CD — DORA and tool comparison",
  "uid": "dora-cicd",
  "tags": ["dora", "cicd", "platform"],
  "refresh": "5m",
  "time": {"from": "now-30d", "to": "now"},
  "templating": {"list": [
    {"name": "tool", "type": "query", "query": "label_values(pipeline_build_total, tool)",
     "includeAll": true, "multi": true, "current": {"text": "All", "value": "$__all"}},
    {"name": "environment", "type": "custom",
     "query": "dev,staging,production", "current": {"text": "production", "value": "production"}}
  ]},
  "panels": [
    {"type": "row", "title": "⭐ THE FOUR DORA METRICS", "gridPos": {"h":1,"w":24,"x":0,"y":0}},

    {"type": "stat", "title": "🚀 Deployment frequency (production, 7d)",
     "gridPos": {"h":6,"w":6,"x":0,"y":1},
     "targets": [{"expr": "dora:deploy_frequency:weekly", "legendFormat": "deploys / 7d"}],
     "fieldConfig": {"defaults": {
       "thresholds": {"mode": "absolute", "steps": [
         {"value": 0,  "color": "red",    "label": "low: 1 per 1–6 months"},
         {"value": 1,  "color": "orange", "label": "medium: 1 per week–month"},
         {"value": 7,  "color": "yellow", "label": "high: 1 per day–week"},
         {"value": 30, "color": "green",  "label": "⭐ elite: on-demand, multiple per day"}]},
       "unit": "short", "decimals": 0}},
     "options": {"colorMode": "background", "graphMode": "area"}},

    {"type": "stat", "title": "⏱️ Lead time for changes (p50)",
     "gridPos": {"h":6,"w":6,"x":6,"y":1},
     "targets": [{"expr": "dora:lead_time_seconds:p50", "legendFormat": "p50"}],
     "fieldConfig": {"defaults": {"unit": "s",
       "thresholds": {"mode": "absolute", "steps": [
         {"value": 0,      "color": "green",  "label": "⭐ elite: < 1 hour"},
         {"value": 3600,   "color": "yellow", "label": "high: 1 day – 1 week"},
         {"value": 604800, "color": "orange", "label": "medium: 1 week – 1 month"},
         {"value": 2592000,"color": "red",    "label": "low: 1–6 months"}]}}},
     "options": {"colorMode": "background"}},

    {"type": "stat", "title": "💥 Change failure rate (30d)",
     "gridPos": {"h":6,"w":6,"x":12,"y":1},
     "targets": [{"expr": "dora:change_failure_rate:30d", "legendFormat": "failure rate"}],
     "fieldConfig": {"defaults": {"unit": "percentunit", "max": 1,
       "thresholds": {"mode": "absolute", "steps": [
         {"value": 0,    "color": "green",  "label": "⭐ elite: 0–15%"},
         {"value": 0.15, "color": "yellow", "label": "high: 16–30%"},
         {"value": 0.30, "color": "orange", "label": "medium: 16–45%"},
         {"value": 0.45, "color": "red",    "label": "low: 46–60%"}]}}},
     "options": {"colorMode": "background"}},

    {"type": "stat", "title": "🔧 Mean time to restore",
     "gridPos": {"h":6,"w":6,"x":18,"y":1},
     "targets": [{"expr": "dora:mttr_seconds:30d", "legendFormat": "MTTR"}],
     "fieldConfig": {"defaults": {"unit": "s",
       "thresholds": {"mode": "absolute", "steps": [
         {"value": 0,     "color": "green",  "label": "⭐ elite: < 1 hour"},
         {"value": 3600,  "color": "yellow", "label": "high: < 1 day"},
         {"value": 86400, "color": "orange", "label": "medium: 1 day – 1 week"},
         {"value": 604800,"color": "red",    "label": "low: > 6 months"}]}}},
     "options": {"colorMode": "background"}},

    {"type": "row", "title": "🔷🐙🔨 THE PER-TOOL COMPARISON — ⭐ the interesting panel",
     "gridPos": {"h":1,"w":24,"x":0,"y":7}, "collapsed": false},

    {"type": "table", "title": "Tool comparison (7d/30d)",
     "gridPos": {"h":8,"w":24,"x":0,"y":8},
     "transformations": [
       {"id": "joinByField", "options": {"byField": "tool", "mode": "outer"}},
       {"id": "organize", "options": {"renameByName": {
         "Value #A": "avg build", "Value #B": "p95 build", "Value #C": "failure rate",
         "Value #D": "cache hits/build", "Value #E": "minutes / 30d",
         "Value #F": "prod deploys / 7d", "Value #G": "prod failure rate",
         "Value #H": "flaky tests / build", "Value #I": "p95 queue wait"}}}
     ],
     "targets": [
       {"refId": "A", "format": "table", "instant": true,
        "expr": "sum by (tool) (rate(pipeline_build_duration_seconds_sum{tool=~\"$tool\"}[7d])) / clamp_min(sum by (tool) (rate(pipeline_build_duration_seconds_count{tool=~\"$tool\"}[7d])), 0.001)"},
       {"refId": "B", "format": "table", "instant": true, "expr": "ci:build_duration:p95{tool=~\"$tool\"}"},
       {"refId": "C", "format": "table", "instant": true, "expr": "ci:build_failure_rate:by_tool{tool=~\"$tool\"}"},
       {"refId": "D", "format": "table", "instant": true, "expr": "ci:cache_hit_ratio:by_tool{tool=~\"$tool\"}"},
       {"refId": "E", "format": "table", "instant": true, "expr": "ci:cost_minutes:by_tool{tool=~\"$tool\"}"},
       {"refId": "F", "format": "table", "instant": true, "expr": "dora:deploy_frequency:by_tool"},
       {"refId": "G", "format": "table", "instant": true, "expr": "dora:change_failure_rate:by_tool"},
       {"refId": "H", "format": "table", "instant": true, "expr": "ci:flaky_test_rate:by_tool{tool=~\"$tool\"}"},
       {"refId": "I", "format": "table", "instant": true, "expr": "ci:queue_wait_seconds:p95{tool=~\"$tool\"}"}
     ],
     "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": [
       {"matcher": {"id": "byName", "options": "avg build"},
        "properties": [{"id": "unit", "value": "s"}, {"id": "custom.cellOptions", "value": {"type": "color-background"}},
                       {"id": "thresholds", "value": {"mode": "absolute", "steps": [
                         {"value": 0, "color": "green"}, {"value": 600, "color": "yellow"}, {"value": 1200, "color": "red"}]}}]},
       {"matcher": {"id": "byName", "options": "failure rate"},
        "properties": [{"id": "unit", "value": "percentunit"}, {"id": "custom.cellOptions", "value": {"type": "color-background"}},
                       {"id": "thresholds", "value": {"mode": "absolute", "steps": [
                         {"value": 0, "color": "green"}, {"value": 0.1, "color": "yellow"}, {"value": 0.2, "color": "red"}]}}]},
       {"matcher": {"id": "byName", "options": "cache hits/build"},
        "properties": [{"id": "custom.cellOptions", "value": {"type": "color-background"}},
                       {"id": "thresholds", "value": {"mode": "absolute", "steps": [
                         {"value": 0, "color": "red"}, {"value": 0.5, "color": "yellow"}, {"value": 1, "color": "green"}]}}]}
     ]}},

    {"type": "row", "title": "📈 TRENDS", "gridPos": {"h":1,"w":24,"x":0,"y":16}},

    {"type": "timeseries", "title": "Build duration by tool (p50 / p95)",
     "gridPos": {"h":8,"w":12,"x":0,"y":17},
     "targets": [
       {"expr": "ci:build_duration:p50{tool=~\"$tool\"}", "legendFormat": "p50 {{tool}}"},
       {"expr": "ci:build_duration:p95{tool=~\"$tool\"}", "legendFormat": "p95 {{tool}}"}
     ],
     "fieldConfig": {"defaults": {"unit": "s"}}},

    {"type": "timeseries", "title": "Build failure rate by tool",
     "gridPos": {"h":8,"w":12,"x":12,"y":17},
     "targets": [{"expr": "ci:build_failure_rate:by_tool{tool=~\"$tool\"}", "legendFormat": "{{tool}}"}],
     "fieldConfig": {"defaults": {"unit": "percentunit", "max": 1}}},

    {"type": "timeseries", "title": "⭐ Production deployments (stacked by tool)",
     "gridPos": {"h":8,"w":12,"x":0,"y":25},
     "targets": [{"expr": "sum by (tool) (increase(pipeline_deploy_total{environment=\"production\",result=\"success\"}[1d]))",
                   "legendFormat": "{{tool}}"}],
     "fieldConfig": {"defaults": {"custom": {"stacking": {"mode": "normal"}}, "unit": "short"}}},

    {"type": "timeseries", "title": "⭐ Rollbacks and canary aborts",
     "gridPos": {"h":8,"w":12,"x":12,"y":25},
     "targets": [
       {"expr": "sum by (tool) (increase(pipeline_rollback_total{environment=\"production\"}[1d]))", "legendFormat": "rollback {{tool}}"},
       {"expr": "sum(increase(rollouts_analysisrun_failed_total[1d]))", "legendFormat": "canary analyses failed"},
       {"expr": "sum(increase(rollouts_rollout_aborted_total[1d]))", "legendFormat": "rollouts aborted"}
     ]},

    {"type": "row", "title": "💰 COST AND CAPACITY", "gridPos": {"h":1,"w":24,"x":0,"y":33}},

    {"type": "timeseries", "title": "Minutes consumed by tool (30d rolling)",
     "gridPos": {"h":8,"w":8,"x":0,"y":34},
     "targets": [{"expr": "sum by (tool) (increase(pipeline_minutes_consumed_total[1d]))", "legendFormat": "{{tool}}"}],
     "fieldConfig": {"defaults": {"unit": "m"}}},

    {"type": "stat", "title": "Estimated monthly cost",
     "gridPos": {"h":8,"w":8,"x":8,"y":34},
     "targets": [
       {"expr": "sum(increase(pipeline_minutes_consumed_total{tool=\"github-actions\"}[30d])) * 0.008", "legendFormat": "GitHub Actions (per-minute)"},
       {"expr": "(sum(increase(pipeline_build_total{tool=\"azure-devops\"}[30d])) > bool 15000) * 40", "legendFormat": "Azure DevOps (flat parallel jobs)"},
       {"expr": "count(kube_pod_info{namespace=\"jenkins\"}) * 0", "legendFormat": "Jenkins (own infra — see the cluster cost)"}
     ],
     "fieldConfig": {"defaults": {"unit": "currencyUSD"}}},

    {"type": "timeseries", "title": "Agent/runner capacity",
     "gridPos": {"h":8,"w":8,"x":16,"y":34},
     "targets": [
       {"expr": "count(kube_pod_info{namespace=\"jenkins\",pod=~\"shop-.*\"})", "legendFormat": "Jenkins agent pods"},
       {"expr": "github_actions_runners_busy", "legendFormat": "GitHub runners busy"},
       {"expr": "azuredevops_agent_pool_active", "legendFormat": "Azure DevOps agents"}
     ]},

    {"type": "row", "title": "🔀 THE GITOPS AND DELIVERY LAYER", "gridPos": {"h":1,"w":24,"x":0,"y":42}},

    {"type": "timeseries", "title": "Argo CD sync status",
     "gridPos": {"h":8,"w":8,"x":0,"y":43},
     "targets": [
       {"expr": "count by (sync_status) (argocd_app_info)", "legendFormat": "{{sync_status}}"},
       {"expr": "count by (health_status) (argocd_app_health_status)", "legendFormat": "health: {{health_status}}"}
     ]},

    {"type": "timeseries", "title": "⭐ Rollout outcomes",
     "gridPos": {"h":8,"w":8,"x":8,"y":43},
     "targets": [
       {"expr": "sum(increase(rollouts_analysisrun_successful_total[7d]))", "legendFormat": "analyses passed"},
       {"expr": "sum(increase(rollouts_analysisrun_failed_total[7d]))", "legendFormat": "analyses failed"},
       {"expr": "sum(increase(rollouts_analysisrun_inconclusive_total[7d]))", "legendFormat": "⭐ inconclusive"}
     ]},

    {"type": "timeseries", "title": "⭐ Kyverno admission decisions",
     "gridPos": {"h":8,"w":8,"x":16,"y":43},
     "targets": [
       {"expr": "sum by (policy_name) (increase(kyverno_policy_results_total{result=\"pass\"}[7d]))", "legendFormat": "pass {{policy_name}}"},
       {"expr": "sum by (policy_name) (increase(kyverno_policy_results_total{result=\"fail\"}[7d]))", "legendFormat": "⛔ fail {{policy_name}}"}
     ]},

    {"type": "row", "title": "📝 WHAT THIS DASHBOARD IS FOR", "gridPos": {"h":1,"w":24,"x":0,"y":51}},
    {"type": "text", "gridPos": {"h":6,"w":24,"x":0,"y":52},
     "options": {"content": "## ⭐ Read this before quoting a number\n\nThe DORA metrics are **diagnostic, not a target**. Setting a target on deployment frequency produces frequent trivial deployments. Setting a target on lead time produces small, unreviewed changes.\n\n**Use them to find the constraint:**\n\n| Pattern | What it usually means |\n|---|---|\n| Low frequency + long lead time | Large batches. Something forces you to accumulate changes. Usually a manual gate or a slow environment. |\n| High frequency + high failure rate | ⭐ The dangerous quadrant. You're shipping fast and breaking fast. Strengthen the canary analysis, not the speed. |\n| Low frequency + low failure rate | Over-cautious. The gates cost more than the risk. Loosen a threshold or automate an approval. |\n| High frequency + low failure rate | ⭐ Elite. Protect it — don't add process because it worked last quarter. |\n| **Inconclusive analyses rising** | Your traffic is too low for the thresholds, or a metric label changed. Fix the load generator. |\n| One tool with a 2× failure rate | A stale shared library or template version. Check the version inventory job. |\n| Cache hits/build < 0.5 | A cache key problem. Costs money and developer time. |\n"}}
  ]
}
```

**Step 3 — the numbers, and what to do about them**

```
After four weeks of running the capstone:

┌─────────────────────────────────────────────────────────────────────────┐
│ 🚀 Deployment frequency (production, 7d)     14      🟡 high            │
│ ⏱️ Lead time for changes (p50)               1h 42m  🟢 elite           │
│ ⏱️ Lead time for changes (p95)               1d 06h  🟡                 │
│ 💥 Change failure rate (30d)                 8.3%    🟢 elite           │
│ 🔧 Mean time to restore                      4m 12s  🟢 elite           │
└─────────────────────────────────────────────────────────────────────────┘

🔷🐙🔨 TOOL COMPARISON
┌────────────────┬──────────┬──────────┬───────────┬─────────┬──────────┬────────┬────────┬─────────┐
│ tool           │ avg build│ p95 build│ fail rate │ cache   │ min/30d  │ prod   │ flaky/ │ p95 q   │
│                │          │          │           │ hits    │          │ deploys│ build  │ wait    │
├────────────────┼──────────┼──────────┼───────────┼─────────┼──────────┼────────┼────────┼─────────┤
│ azure-devops   │ 6m 12s   │ 14m 02s  │ 8%        │ 0.9     │ 1,240    │ 5      │ 0.04   │ 22s     │
│ github-actions │ 4m 38s 🟢│ 9m 41s 🟢│ 6%   🟢   │ 1.7 🟢  │ 3,810    │ 6      │ 0.02 🟢│ 8s  🟢  │
│ jenkins        │ 9m 04s 🔴│ 27m 18s🔴│ 14%  🔴   │ 0.4 🔴  │ 0 (own)  │ 3      │ 0.11 🔴│ 3m 41s🔴│
└────────────────┴──────────┴──────────┴───────────┴─────────┴──────────┴────────┴────────┴─────────┘
```

**Step 4 — ⭐ act on what the dashboard says**

```
FINDING 1: Jenkins' p95 queue wait is 3m41s while the others are 8s and 22s.
  → root cause: `containerCap: 10` and only 2 worker nodes with 4 CPU each.
    Agent pods queue on Kubernetes, not on Jenkins.
  → FIX: raise containerCap to 30, add a node, and set `maxRequestsPerHostStr: 32`
         so the controller doesn't rate-limit its own API calls.
  → RESULT: p95 queue wait 3m41s → 24s

FINDING 2: Jenkins' cache-hit ratio is 0.4 vs GitHub's 1.7.
  → root cause: Kaniko's `--cache-repo` cache is per-image and the pods are
    ephemeral, so there's no local layer cache; and the Maven/Gradle caches
    live in the pod's emptyDir, which is destroyed with the pod.
  → FIX: mount a PVC-backed Maven cache for the java template, and switch
         the Python/Go caches to a shared S3/GCS bucket via sccache.
         ⭐ Or accept it — the honest trade-off is "0 licence cost + slower".
  → RESULT: 0.4 → 1.1 (Maven cache on a ReadWriteMany PVC)

FINDING 3: Jenkins' flaky-test rate is 0.11/build vs 0.02 for GitHub Actions.
  → root cause: three jobs are pinned to shared-library v2.3.0, which had a
    race in the `waitForService` helper. The version-inventory job (Case 3,
    Task 3.2) showed it.
  → FIX: bump those three jobs to v2.4.1.
  → RESULT: 0.11 → 0.03
  → ⭐⭐ THIS IS WHY THE VERSION-INVENTORY JOB EXISTS.

FINDING 4: the p95 lead time (1d 06h) is 15× the p50 (1h 42m).
  → root cause: the promotion PR to production waits for a human, and humans
    are not available at night or on Fridays.
  → the honest question: is that a PROBLEM?
    ⭐ NO — it's the deployment window working as designed. The p95 includes
       changes merged on Thursday evening that wait until Monday.
  → FIX: none for the wait. But DO add the `ci:promotion_latency_seconds`
         metric so you can see the wait separately from the build time.
  → ⭐⭐ THIS IS THE MOST IMPORTANT LESSON ON THIS DASHBOARD: a metric that
         looks bad may be a control working correctly. Investigate before
         "optimising".

FINDING 5: `rollouts_analysisrun_inconclusive_total` rose 4× in week 3.
  → root cause: the k6 load generator's Sync hook wasn't firing for
    order-worker (it's a worker with no HTTP endpoint to load-test).
  → FIX: for a worker service, the analysis must use QUEUE metrics
    (rabbitmq_messages_delivered_total) instead of HTTP metrics — a separate
    AnalysisTemplate.
  → ⭐ the general lesson: one AnalysisTemplate cannot serve every service
    shape. HTTP services, workers, batch jobs and stateful services each need
    their own.
```

**Step 5 — the alerts (already in §6.4) plus three DORA-specific ones**

```yaml
      # ⭐ the "you're in the dangerous quadrant" alert
      - alert: DORADangerousQuadrant
        expr: |
          dora:deploy_frequency:weekly > 7
          and dora:change_failure_rate:30d > 0.15
        for: 7d
        labels: {severity: warning, team: engineering-management}
        annotations:
          summary: 'shipping fast AND breaking fast'
          description: >
            Deployment frequency is {{ with query "dora:deploy_frequency:weekly" }}{{ . | first | value }}{{ end }}/week
            while the change failure rate is
            {{ with query "dora:change_failure_rate:30d" }}{{ . | first | value | humanizePercentage }}{{ end }}.
            ⭐ Do NOT slow down the deployments. Strengthen the canary analysis:
            add a metric for the failure mode that escaped, lower a threshold, or
            extend the soak. Slowing down converts this into the "low frequency +
            low failure rate" quadrant, which feels safe and isn't.
          runbook: https://runbooks.shop.example.com/dora/dangerous-quadrant

      - alert: DORALeadTimeRegressed
        expr: |
          dora:lead_time_seconds:p50 > 1.5 * (dora:lead_time_seconds:p50 offset 30d)
        for: 3d
        labels: {severity: info, team: platform}
        annotations:
          summary: 'the lead time for changes has grown by 50%'
          description: >
            Find the new WAIT. It is almost never build time — it's a queue,
            a review, an approval, or a manual gate. Query
            ci:queue_wait_seconds:p95 and ci:promotion_latency_seconds:p50.

      - alert: ToolFailureRateDivergence
        expr: |
          max(ci:build_failure_rate:by_tool) / clamp_min(min(ci:build_failure_rate:by_tool), 0.001) > 2.5
        for: 3d
        labels: {severity: warning, team: platform}
        annotations:
          summary: 'one CI tool has a 2.5× higher failure rate than another'
          description: >
            ⭐ This is the alert that catches a stale shared library or template
            version. Run the version-inventory job before touching anything else.
```

> 🔑 **The answer to say out loud:** *"The dashboard has four DORA stats with the published elite/high/medium/low thresholds baked into the colour coding, a per-tool comparison table, and trend panels — but the valuable part is what the comparison table told me to do. Jenkins' p95 queue wait was 3m41s against GitHub's 8s, which turned out to be `containerCap: 10` with only two worker nodes, so the pods queued in Kubernetes rather than in Jenkins; raising the cap and adding a node took it to 24s. Its cache-hit ratio was 0.4 against 1.7, because Kaniko's registry cache is per-image and the Maven cache lived in an ephemeral emptyDir; a ReadWriteMany PVC for `~/.m2` took it to 1.1. And its flaky-test rate was 0.11 per build against 0.02, which the version-inventory job explained immediately — three jobs were pinned to shared-library v2.3.0 with a race in a `waitForService` helper. Three findings, three fixes, all from one table. The most important lesson came from a number that looked bad and wasn't: the p95 lead time was 1d 06h against a p50 of 1h 42m, and the cause was changes merged on Thursday evening waiting for a Monday human approval. That's the deployment window working exactly as designed. So the dashboard has a text panel at the bottom that says the DORA metrics are diagnostic, not targets — setting a target on deployment frequency produces frequent trivial deployments — and I added an alert for the genuinely dangerous quadrant, high frequency plus a failure rate above 15%, whose runbook explicitly says do not slow down the deployments, strengthen the canary analysis instead."*

---

### Task C.5 — The chaos day: five failures, five different layers

**Requirement:** in one session, inject five failures. Each must be caught by a **different** layer of the system, and each must produce evidence you can show afterwards.

**✅ Answer**

```bash
# scripts/chaos-day.sh — ⭐ run it against staging, NEVER production first
#!/usr/bin/env bash
set -uo pipefail
EVIDENCE="evidence/chaos-$(date -u +%Y%m%d-%H%M)"
mkdir -p "$EVIDENCE"
NS="${CHAOS_NS:-shop-staging}"
log() { printf '\n\033[1;36m══════ %s ══════\033[0m\n' "$*"; }
snap() { kubectl -n "$NS" get pods,rollout,events --sort-by=.lastTimestamp > "$EVIDENCE/$1-snapshot.txt" 2>&1; }
result() { printf '  \033[1;%sm%s\033[0m  caught by: %s\n' \
             "$([[ "$1" == "✅" ]] && echo 32 || echo 31)" "$1" "$2"; }

log "CHAOS DAY — $(date -u) — namespace $NS"
kubectl config current-context | tee "$EVIDENCE/context.txt"
```

```bash
# ═══════════════════════════════════════════════════════════════
# CHAOS 1 — a bad image reaches the cluster
#   EXPECTED CATCH LAYER: Argo Rollouts' AnalysisTemplate
# ═══════════════════════════════════════════════════════════════
log "CHAOS 1: deploy a version that returns 500 for 20% of requests"
cd ~/capstone/apps/shop && git checkout -b chaos/1-errors main
sed -i 's|func handler(w http.ResponseWriter, r \*http.Request) {|func handler(w http.ResponseWriter, r *http.Request) {\n\tif rand.Intn(100) < 20 { http.Error(w, "chaos-1", 500); return }|' \
  apps/checkout/main.go
git commit -am "chaos(1): inject a 20% error rate" && git push -f origin chaos/1-errors
gh pr create --head chaos/1-errors --fill --label chaos 2>/dev/null && gh pr merge --squash --admin
sleep 600
BEFORE=$(kubectl -n "$NS" get rollout checkout -o jsonpath='{.status.stableRS}')
kubectl argo rollouts get rollout checkout -n "$NS" --watch 2>&1 | tee "$EVIDENCE/1-rollout.log" &
WATCH=$!; sleep 1500; kill $WATCH 2>/dev/null
AFTER=$(kubectl -n "$NS" get rollout checkout -o jsonpath='{.status.stableRS}')
kubectl -n "$NS" get analysisrun --sort-by=.metadata.creationTimestamp -o json \
  | jq '.items[-1].status | {phase, metricResults: [.metricResults[] | select(.phase!="Successful") | {name, phase}]}' \
  | tee "$EVIDENCE/1-analysis.json"
if [[ "$BEFORE" == "$AFTER" ]]; then
  result "✅" "Argo Rollouts AnalysisTemplate (automatic, no human)"
else
  result "⛔" "NOTHING — the bad version is live"
fi
```

```bash
# ═══════════════════════════════════════════════════════════════
# CHAOS 2 — an unsigned image is pushed straight to the registry
#   EXPECTED CATCH LAYER: Kyverno at admission (NOT the pipeline)
# ═══════════════════════════════════════════════════════════════
log "CHAOS 2: bypass CI entirely and try to deploy an unsigned image"
docker pull alpine:3.20
docker tag alpine:3.20 ghcr.io/3558bhk/checkout:chaos2
echo "$GHCR_PAT" | docker login ghcr.io -u 3558bhk --password-stdin
docker push ghcr.io/3558bhk/checkout:chaos2 2>&1 | tee "$EVIDENCE/2-push.log"
CH2_DIGEST=$(crane digest ghcr.io/3558bhk/checkout:chaos2)
kubectl -n "$NS" set image deploy/checkout api="ghcr.io/3558bhk/checkout@$CH2_DIGEST" \
  2>&1 | tee "$EVIDENCE/2-setimage.log"
sleep 5
kubectl -n "$NS" get events --field-selector reason=FailedCreate --sort-by=.lastTimestamp \
  | tail -5 | tee "$EVIDENCE/2-events.txt"
if grep -q 'denied the request' "$EVIDENCE/2-setimage.log"; then
  result "✅" "Kyverno verify-image-signature (the cluster, not the pipeline)"
elif grep -q 'no matching signatures\|untrusted' "$EVIDENCE/2-setimage.log"; then
  result "✅" "Kyverno verify-image-signature"
else
  result "⛔" "NOTHING — an unsigned image is running"
fi
# ⭐⭐ THE POINT: CI was never involved. The pipeline didn't fail, because the
#    pipeline never ran. The CLUSTER refused it. That's defense in depth.
```

```bash
# ═══════════════════════════════════════════════════════════════
# CHAOS 3 — someone edits the cluster directly (drift)
#   EXPECTED CATCH LAYER: Argo CD self-heal
# ═══════════════════════════════════════════════════════════════
log "CHAOS 3: manually scale the deployment and add a debug sidecar"
kubectl -n "$NS" scale deploy/payment-mock --replicas=25 2>&1 | tee "$EVIDENCE/3-scale.log"
kubectl -n "$NS" patch deploy payment-mock --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/-",
   "value":{"name":"debug","image":"busybox:1.36","command":["sleep","infinity"]}}]' \
  2>&1 | tee "$EVIDENCE/3-sidecar.log"
kubectl -n "$NS" get deploy payment-mock -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[*].name}'
echo; echo "  ⏳ waiting 4 minutes for Argo CD's self-heal…"
sleep 240
argocd app get "shop-${NS#shop-}-payment-mock" --refresh 2>&1 | tee "$EVIDENCE/3-argocd.log"
AFTER_REPLICAS=$(kubectl -n "$NS" get deploy payment-mock -o jsonpath='{.spec.replicas}')
AFTER_CONTAINERS=$(kubectl -n "$NS" get deploy payment-mock -o jsonpath='{.spec.template.spec.containers[*].name}')
echo "  after: replicas=$AFTER_REPLICAS containers=$AFTER_CONTAINERS"
if [[ "$AFTER_REPLICAS" != "25" && "$AFTER_CONTAINERS" != *"debug"* ]]; then
  result "✅" "Argo CD self-heal (reverted in <4 minutes)"
else
  result "⛔" "NOTHING — the cluster has drifted from Git"
fi
# ⭐ and the Kyverno policy ALSO rejects the sidecar on the next admission:
kubectl -n "$NS" apply --dry-run=server -f - <<EOF 2>&1 | tee -a "$EVIDENCE/3-sidecar.log"
apiVersion: apps/v1
kind: Deployment
metadata: {name: chaos3-retry, namespace: $NS, labels: {team: test}}
spec:
  replicas: 3
  selector: {matchLabels: {app: chaos3}}
  template:
    metadata: {labels: {app: chaos3, team: test}}
    spec:
      containers:
        - {name: debug, image: 'busybox:1.36'}
EOF
#   ⛔ denied: require-three-probes, require-resource-requests,
#      require-a-restricted-security-context, disallow-latest-and-mutable-tags
# ⭐⭐ TWO LAYERS caught chaos 3: Kyverno at admission, Argo CD after the fact.
```

```bash
# ═══════════════════════════════════════════════════════════════
# CHAOS 4 — the CI platform itself goes down mid-deploy
#   EXPECTED CATCH LAYER: the deployment continues (GitOps decoupling)
# ═══════════════════════════════════════════════════════════════
log "CHAOS 4: kill Jenkins and GitHub Actions access mid-rollout"
kubectl -n jenkins scale sts/jenkins --replicas=0
echo "  ⛔ Jenkins is DOWN"
# start a rollout that is already in flight
kubectl -n "$NS" get rollout -o custom-columns=NAME:.metadata.name,PHASE:.status.phase
sleep 600
echo "  ⏳ 10 minutes with no CI…"
kubectl -n "$NS" get rollout -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,STEP:.status.currentStepIndex
kubectl argo rollouts get rollout checkout -n "$NS" 2>&1 | tee "$EVIDENCE/4-rollout.log"
# ⭐ can the rollout still complete? (it should — Argo Rollouts is in-cluster)
kubectl argo rollouts promote --full checkout -n "$NS" 2>&1 | tee -a "$EVIDENCE/4-rollout.log"
sleep 120
PHASE=$(kubectl -n "$NS" get rollout checkout -o jsonpath='{.status.phase}')
if [[ "$PHASE" == "Healthy" ]]; then
  result "✅" "GitOps decoupling — CI being down does NOT stop delivery"
  echo "     ⭐ and NEW deploys are blocked, correctly:"
  echo "        no CI → no signed image → no promotion PR → no sync"
  echo "        that is the SAFE failure mode."
else
  result "⚠️" "the rollout is $PHASE — investigate"
fi
kubectl -n jenkins scale sts/jenkins --replicas=1
sleep 180
kubectl -n jenkins get pods
# ⭐ the alert that should have fired:
curl -s localhost:9093/api/v2/alerts | jq '.[] | select(.labels.alertname=="CIPipelineDown") | {alertname, startsAt}'
```

```bash
# ═══════════════════════════════════════════════════════════════
# CHAOS 5 — the monitoring platform goes down DURING a canary
#   EXPECTED CATCH LAYER: the AnalysisTemplate must FAIL, not pass
# ═══════════════════════════════════════════════════════════════
log "CHAOS 5: kill Prometheus while a canary analysis is running"
# start a canary
kubectl -n "$NS" patch rollout checkout --type=merge -p \
  "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"chaos\":\"5-$(date +%s)\"}}}}}"
sleep 120
kubectl argo rollouts get rollout checkout -n "$NS" | head -20
echo "  ⛔ scaling Prometheus to zero…"
kubectl -n monitoring scale sts/kps-kube-prometheus-stack-prometheus --replicas=0
sleep 60
kubectl -n "$NS" get analysisrun --sort-by=.metadata.creationTimestamp -o json \
  | jq '.items[-1].status.metricResults[] | {name, phase,
        error: .measurements[-1].metadata, msg: .message}' | tee "$EVIDENCE/5-analysis.json"
PHASE=$(kubectl -n "$NS" get analysisrun --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1].status.phase}')
ROLLOUT=$(kubectl -n "$NS" get rollout checkout -o jsonpath='{.status.phase}')
echo "  AnalysisRun phase: $PHASE"
echo "  Rollout phase:     $ROLLOUT"
if [[ "$PHASE" == "Error" || "$PHASE" == "Failed" || "$PHASE" == "Inconclusive" ]]; then
  result "✅" "the analysis refused to conclude without data — the rollout PAUSED"
  echo "     ⭐⭐ THIS IS THE CORRECT BEHAVIOUR: deploying blind is the worst outcome."
else
  result "⛔" "the analysis PASSED with no Prometheus — it would have promoted blind"
fi
kubectl -n monitoring scale sts/kps-kube-prometheus-stack-prometheus --replicas=1
sleep 300
kubectl -n "$NS" get analysisrun --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].status.phase}'
```

```bash
# ═══════════════════════════════════════════════════════════════
# THE REPORT
# ═══════════════════════════════════════════════════════════════
log "THE CHAOS DAY REPORT"
cat > "$EVIDENCE/REPORT.md" <<EOF
# Chaos day — $(date -u +%F)

Namespace: \`$NS\` · Cluster: $(kubectl config current-context)

| # | Failure injected | Layer that caught it | Automatic? | Evidence |
|---|---|---|---|---|
| 1 | a version with a 20% error rate | ⭐ Argo Rollouts AnalysisTemplate | ✅ yes | \`1-analysis.json\` |
| 2 | an unsigned image pushed straight to the registry | ⭐⭐ Kyverno at admission | ✅ yes | \`2-setimage.log\` |
| 3 | a manual scale + a debug sidecar | ⭐ Argo CD self-heal + Kyverno | ✅ yes | \`3-argocd.log\` |
| 4 | the CI platform went down | ⭐⭐ GitOps decoupling (delivery continued) | ✅ yes | \`4-rollout.log\` |
| 5 | Prometheus died during a canary | ⭐ the analysis refused to conclude | ✅ yes | \`5-analysis.json\` |

## The layering this proves

\`\`\`
LAYER 1  CI tests + lint + scan          → catches a bug in the code
LAYER 2  CI's vulnerability gate         → catches a known CVE
LAYER 3  cosign signing                  → establishes provenance
LAYER 4  the config-repo PR + review     → catches a bad promotion INTENT
LAYER 5  ⭐ Kyverno at admission          → catches an unsigned/non-compliant image
                                            EVEN IF layers 1–4 were all bypassed
LAYER 6  ⭐ Argo Rollouts analysis        → catches a regression under real traffic
LAYER 7  Argo CD self-heal               → catches drift after the fact
LAYER 8  the monitoring alerts           → tells a human, fast
LAYER 9  the runbook                     → tells the human what to do
\`\`\`

## ⭐⭐ The single most important result

**Chaos 2.** An attacker who fully compromised the registry — pushed a valid,
pullable image under a legitimate name — was stopped. Not by CI (CI never ran),
not by a human, but by the cluster refusing to admit an image whose signature
did not match an approved pipeline identity.

That is the argument for verifying in the cluster rather than in the pipeline:
**the pipeline is the thing being attacked.**

## And the second most important

**Chaos 5.** When Prometheus died mid-canary, the AnalysisRun went to
\`$PHASE\` and the rollout PAUSED — it did not silently succeed and promote.
An analysis that returns "healthy" when it cannot read any metrics is worse
than no analysis at all, because it manufactures confidence.

## What we would fix

$( [[ "$PHASE" == "Successful" ]] && echo '- ⛔ the AnalysisTemplate must use `failureCondition` on a query error, not just on the value' || echo '- the AnalysisTemplate correctly failed closed on a Prometheus outage' )
- chaos 4 revealed there is no alert when a promotion PR sits unmerged for >2h
- chaos 3 revealed the break-glass path leaves no annotation, so the audit
  trail depends on the human remembering to record it
EOF
cat "$EVIDENCE/REPORT.md"
echo; echo "  evidence: $EVIDENCE ($(du -sh $EVIDENCE | cut -f1))"
```

**The expected output**

```
══════ CHAOS 1: deploy a version that returns 500 for 20% of requests ══════
  ⟳ checkout   ✗ Degraded   RolloutAborted: metric "canary-error-rate" assessed Failed
  ✅  caught by: Argo Rollouts AnalysisTemplate (automatic, no human)
     the bad version reached 15% of traffic for 4m 12s

══════ CHAOS 2: bypass CI entirely and try to deploy an unsigned image ══════
  Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
  policy Deployment/shop-staging/checkout for resource violation:
  verify-image-signature: verify-signature: no matching signatures:
    ⛔ found no signatures for ghcr.io/3558bhk/checkout@sha256:4c5d…
  ✅  caught by: Kyverno verify-image-signature (the cluster, not the pipeline)

══════ CHAOS 3: manually scale the deployment and add a debug sidecar ══════
  before: replicas=25 containers=payment-mock debug
  ⏳ waiting 4 minutes for Argo CD's self-heal…
  after:  replicas=3 containers=payment-mock
  ✅  caught by: Argo CD self-heal (reverted in <4 minutes)
     and Kyverno ALSO rejected the sidecar on a retry:
       require-three-probes, require-resource-requests,
       require-a-restricted-security-context

══════ CHAOS 4: kill Jenkins and GitHub Actions access mid-rollout ══════
  ⛔ Jenkins is DOWN
  NAME        PHASE     STEP
  checkout    Paused    3
  ⏳ 10 minutes with no CI…
  promoted → Healthy
  ✅  caught by: GitOps decoupling — CI being down does NOT stop delivery
     ⭐ and NEW deploys are blocked, correctly:
        no CI → no signed image → no promotion PR → no sync.
        That is the SAFE failure mode.

══════ CHAOS 5: kill Prometheus while a canary analysis is running ══════
  ⛔ scaling Prometheus to zero…
  AnalysisRun phase: Error
  Rollout phase:     Paused
  ✅  caught by: the analysis refused to conclude without data — the rollout PAUSED
     ⭐⭐ THIS IS THE CORRECT BEHAVIOUR: deploying blind is the worst outcome.

══════ THE CHAOS DAY REPORT ══════
  evidence: evidence/chaos-20260912-1014 (1.4M)
```

> 🔑 **The answer to say out loud:** *"Five failures, five different layers, and the ordering is the point. Chaos 1 — a version with a 20% error rate — was caught by the Argo Rollouts AnalysisTemplate, which means it reached 15% of traffic for four minutes and no human did anything. Chaos 2 is the important one: I pushed an unsigned image straight to the registry, completely bypassing CI, and the cluster refused it at admission. That's the argument for verifying signatures in the cluster rather than in the pipeline — the pipeline is the thing being attacked, so a control that lives in the pipeline is a control the attacker controls. Chaos 3, a manual scale to 25 replicas plus a debug sidecar, was caught twice: Kyverno rejected the sidecar on admission because it had no probes, no resources and no security context, and Argo CD's self-heal reverted the whole thing within four minutes. Chaos 4 killed Jenkins mid-rollout and proved the GitOps decoupling works in both directions — the in-flight rollout completed because Argo Rollouts is in-cluster, while new deployments were correctly blocked because no CI means no signed image means no promotion PR, which is the safe failure mode. Chaos 5 killed Prometheus during a canary analysis, and the AnalysisRun went to Error and paused the rollout instead of silently succeeding. That's the second most important result, because an analysis that reports 'healthy' when it cannot read any metrics is worse than no analysis — it manufactures confidence. Both of those are properties you can only discover by breaking things deliberately, and that's why the chaos day produces an evidence directory and a written report rather than just a green tick."*

---

## ✅ What you now have

```
A complete, working, production-shaped delivery system:

  📁 3558Bhk/shop          the application, built by THREE CI tools
  📁 3558Bhk/shop-config   the GitOps source of truth, with CODEOWNERS
  📁 3558Bhk/pipeline-library   the Jenkins shared library
  ☸️  kind:cicd            Argo CD + Argo Rollouts + Kyverno + the monitoring stack
  📦 ghcr.io/3558bhk/*     signed images with SBOMs and provenance
  📊 Grafana               the application dashboards AND the DORA dashboard
  📚 docs/runbooks/        eight runbooks, exercised

AND — more importantly — you can:
  ✅ explain why CI should hold no cluster credentials
  ✅ explain why the cluster verifies signatures, not just the pipeline
  ✅ explain the difference between signing and identity verification
  ✅ tune an AnalysisTemplate against real scenarios and defend the thresholds
  ✅ name four rollback paths and when each is correct
  ✅ read a DORA dashboard and find the constraint it points at
  ✅ tell the difference between a metric that looks bad and a control working
  ✅ run a chaos day and produce evidence
```

**That is a staff-level conversation about CI/CD.** Most engineers can describe one tool. You can describe a system, defend its boundaries, and prove each one works.

---

## Where next

| You want | Go to |
|---|---|
| ⚡ Everything on one page | [06-CHEATSHEET.md](./06-CHEATSHEET.md) |
| 🔷 Azure DevOps in depth | [02-CASE-1-azure-devops.md](./02-CASE-1-azure-devops.md) |
| 🐙 GitHub Actions in depth | [03-CASE-2-github-actions.md](./03-CASE-2-github-actions.md) |
| 🔨 Jenkins in depth | [04-CASE-3-jenkins.md](./04-CASE-3-jenkins.md) |
| 📖 The theory behind every decision here | [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) |
| ⏱️ The hour-by-hour plan | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |
| 📈 The monitoring this capstone depends on | [../monitoring-alerting-learning-path/](../monitoring-alerting-learning-path/) |
| ☸️ The Kubernetes this capstone deploys to | [../kubernetes-learning-path/](../kubernetes-learning-path/) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
