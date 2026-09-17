# 04 · ⭐⭐ Install `kube-prometheus-stack` — Step by Step
### From an empty cluster to Grafana dashboards, a working Alertmanager, and Prometheus scraping real targets. Every command, every value, and the nine things that go wrong on a first install.

> **WHAT this file is:** the install guide. Ten steps, in order, each one verified before you move to the next. Copy-pasteable start to finish.
>
> **WHY it is its own file:** because `helm install` on this chart is the step where most people's monitoring journey quietly goes wrong — Prometheus comes up green, Grafana shows dashboards, everything *looks* fine, and three weeks later you discover it has been running with an `emptyDir` and losing all history at every restart, or ignoring every `ServiceMonitor` you ever created. This file makes you verify the things that fail silently.
>
> **TARGET:** you end with a running, persistent, verified stack — and you know exactly what each of the ~10 pods is doing.
>
> **Time:** 3 hours first pass (most of it is waiting for images). ~25 minutes once you have done it before.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--before-you-install--the-five-things-to-verify) | ⭐ Before you install — the five things to verify |
| [2](#2--step-1--add-the-helm-repo-and-pin-the-version) | Step 1 — Add the Helm repo and **pin the version** |
| [3](#3--step-2--read-the-defaults-before-you-change-them) | Step 2 — **Read the defaults** before you change them |
| [4](#4--step-3--write-your-valuesyaml) | Step 3 — Write your `values.yaml` |
| [5](#5--step-4--install) | Step 4 — Install |
| [6](#6--step-5--verify-every-pod-and-know-what-it-is) | Step 5 — ⭐ Verify every pod **and know what it is** |
| [7](#7--step-6---verify-persistence--the-one-that-fails-silently) | Step 6 — ⭐⭐ Verify **persistence** — the one that fails silently |
| [8](#8--step-7--open-prometheus-and-look-at-targets) | Step 7 — Open Prometheus and look at **Targets** |
| [9](#9--step-8--open-grafana) | Step 8 — Open Grafana |
| [10](#10--step-9--open-alertmanager) | Step 9 — Open Alertmanager |
| [11](#11--step-10---prove-it-survives-a-restart) | Step 10 — ⭐ Prove it survives a restart |
| [12](#12---the-nine-things-that-go-wrong-on-a-first-install) | ⭐⭐ The **nine things** that go wrong on a first install |
| [13](#13--low-memory-values-for-kind--minikube--laptops) | Low-memory values for kind / minikube / laptops |
| [14](#14--upgrading-and-uninstalling-safely-crds) | Upgrading and **uninstalling** safely (CRDs!) |
| [15](#15---what-you-have-and-what-is-missing) | ✅ What you have, and what is missing |
| [16](#16---tasks) | 🔨 Tasks — **answers at the END** |

---

## 1 · Before you install — the five things to verify

⭐ **Do not skip this section.** Four of the nine failures in [§12](#12---the-nine-things-that-go-wrong-on-a-first-install) are prevented here, in about three minutes.

### 1.1 You have a cluster, and you are pointed at the right one

```bash
kubectl config current-context
kubectl get nodes -o wide
```

Expected: the context name you *think* it is, and at least one node in `Ready` state.

⛔ **The classic:** you have three contexts (local kind, staging, production) and you install the monitoring stack into the wrong one. `kubectl config current-context` costs one second and has saved more careers than any other command in this file.

### 1.2 Kubernetes version is supported

```bash
kubectl version -o json | jq -r '.serverVersion.gitVersion'
```

Chart **88.1.5** declares `kubeVersion: >=1.25.0-0`. Verify what *your* pinned chart declares rather than trusting this file:

```bash
helm show chart prometheus-community/kube-prometheus-stack --version 88.1.5 | grep -E '^(version|appVersion|kubeVersion):'
```

```
version: 88.1.5
appVersion: v0.93.0
kubeVersion: >=1.25.0-0
```

### 1.3 You have ≥ 4 GB of allocatable memory — and you check *allocatable*, not total

```bash
kubectl describe nodes | grep -A6 'Allocatable:' | grep -E 'cpu|memory'
kubectl top nodes 2>/dev/null || echo "metrics-server not installed — fine, but install it, you'll want it"
```

The default stack requests roughly:

| Component | Request | Why |
|---|---|---|
| `prometheus` | 2 GB RAM · 1 CPU (typical) | the TSDB head block is **in memory** |
| `grafana` | ~256 Mi | |
| `alertmanager` | ~128 Mi | |
| `kube-state-metrics` | ~128 Mi | grows with object count |
| `node-exporter` × N nodes | ~64 Mi each | DaemonSet — one per node |
| `prometheus-operator` | ~200 Mi | |
| **Total, 3-node cluster** | **≈ 3 GB** | |

⭐ **If you have less, go straight to [§13](#13--low-memory-values-for-kind--minikube--laptops).** A Prometheus that gets `OOMKilled` loses its in-memory head block and has to replay the WAL — which looks exactly like "gaps in my graphs".

### 1.4 ⭐⭐ You have a working StorageClass — **the single most important check in this file**

```bash
kubectl get storageclass
```

You need at least one, and ideally one marked `(default)`:

```
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE   ...
standard (default)   rancher.io/local-path   Delete          Immediate           ...
```

**Then prove it actually provisions** — do not trust the list, trust a PVC:

```bash
kubectl create namespace sc-test
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: probe
  namespace: sc-test
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF

kubectl -n sc-test get pvc probe -w     # wait for STATUS: Bound  (Ctrl-C when you see it)
```

- ✅ **`Bound`** → you have real storage. Clean up: `kubectl delete ns sc-test`.
- ⛔ **Stuck in `Pending`** → describe it: `kubectl -n sc-test describe pvc probe`. The event will say why — usually *"no persistent volumes available"* or *"waiting for first consumer"*.

> ⭐⭐ **Why this check is worth three minutes of your life.** If there is **no** StorageClass, the chart's `storageSpec` is silently ignored and Prometheus runs on an **`emptyDir`**. Everything works. Grafana is beautiful. Targets are green. And **every single metric is deleted the moment the pod restarts** — which happens on every node drain, every chart upgrade, every OOMKill. You will not notice for weeks, and then someone will ask "why does our dashboard only ever show the last four hours?" and you will spend a day finding out.
>
> `kubectl -n monitoring get pvc` after install ([§7](#7--step-6---verify-persistence--the-one-that-fails-silently)) is the check that catches it.

**If you are on kind** (the most common local setup) and the PVC stays `Pending`, install the local-path provisioner:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
kubectl get storageclass      # should now show local-path
```

### 1.5 Helm v3 is installed, and you know which version

```bash
helm version
```

Expected: `version.BuildInfo{Version:"v3.21.x", ...}`.

⚠️ **Helm v4 (4.1.x / 4.2.x) now ships in parallel with v3 — it is not a replacement, and both lines are maintained.** Every command in this file is written and tested against **v3**. If `helm version` reports v4, see [`../helm-charts-mastery/02-INSTALL-HELM-AND-FIRST-RELEASE.md`](../helm-charts-mastery/02-INSTALL-HELM-AND-FIRST-RELEASE.md) §"v3 vs v4" for the differences that bite; the two that matter here are CRD handling and `--dry-run` semantics.

If Helm is missing:

```bash
# macOS
brew install helm

# Linux (script — read it before you pipe it to sh, always)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o get_helm.sh
less get_helm.sh          # ⭐ actually look at it
sudo bash get_helm.sh
```

### 1.6 Two plugins that will save you, installed once

```bash
helm plugin install https://github.com/databus23/helm-diff
helm plugin install https://github.com/helm-unittest/helm-unittest   # only if you'll write charts
helm plugin list
```

⭐ **`helm diff` is not optional for a chart this size.** `kube-prometheus-stack` renders **hundreds of objects**. Running `helm upgrade` without diffing it first is how you discover, in production, that a values change you made six weeks ago silently removed your `storageSpec`.

---

## 2 · Step 1 — Add the Helm repo and pin the version

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
```

```
"prometheus-community" has been added to your repositories
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "prometheus-community" chart repository
Update Complete. ⎈Happy Helming!⎈
```

### Confirm the version you intend to install actually exists

```bash
helm search repo prometheus-community/kube-prometheus-stack --versions | head -12
```

```
NAME                                    	CHART VERSION	APP VERSION	DESCRIPTION
prometheus-community/kube-prometheus-st…	88.3.0       	v0.93.0    	kube-prometheus-stack collects Kubernetes manif…
prometheus-community/kube-prometheus-st…	88.2.1       	v0.93.0    	kube-prometheus-stack collects Kubernetes manif…
prometheus-community/kube-prometheus-st…	88.1.5       	v0.93.0    	kube-prometheus-stack collects Kubernetes manif…
…
```

### ⭐ Pin it. In writing. In a file you commit.

```bash
# Create the working directory — everything from here lives in git
mkdir -p ~/monitoring/kube-prometheus-stack && cd ~/monitoring/kube-prometheus-stack

cat > Chart.lock.txt <<'EOF'
chart:     prometheus-community/kube-prometheus-stack
version:   88.1.5
appVersion: v0.93.0
verified:  2026-08-15
reason:    last version whose Chart.yaml was read line-by-line before pinning
EOF
```

> ⭐⭐ **Why pinning a *monitoring* chart matters more than pinning an app chart.** This chart ships **CRDs**, **alert rules**, **Grafana dashboards** and **admission webhooks**. A major-version bump can:
> - change a CRD schema so your existing `PrometheusRule` objects are rejected;
> - rename or re-tune bundled alert rules, so an alert you depend on stops firing;
> - bump the Grafana subchart and orphan your provisioned dashboards.
>
> ⛔ **Never run `helm upgrade` on this chart without `--version`, and never without `helm diff` first.** "It's just monitoring" is the sentence that precedes a three-day outage where nobody noticed.

---

## 3 · Step 2 — **Read the defaults** before you change them

⭐ **This is the habit that separates people who use Helm from people who fight it.**

The chart's `values.yaml` is roughly **9,000 lines**. You will never read it all. But you will download it, and you will `grep` it — because *every value you set must be a real key*, and guessing key names is how you get a values file that Helm accepts and silently ignores.

```bash
helm show values prometheus-community/kube-prometheus-stack --version 88.1.5 > values-default.yaml
wc -l values-default.yaml
```

### The top-level structure — the eight keys you will actually touch

```bash
grep -nE '^[a-zA-Z]' values-default.yaml | head -40
```

| Key | What it controls | Do you touch it? |
|---|---|---|
| `global` | image registry, image pull secrets, storage class | ⭐ yes — one place to set registry + storageClass |
| `crds` | whether the chart installs/upgrades **CRDs** | ⭐⭐ yes — see [§14](#14--upgrading-and-uninstalling-safely-crds) |
| `defaultRules` | the ~200 bundled **alert rules** | yes — to disable noisy ones |
| `kubeControllerManager` / `kubeEtcd` / `kubeScheduler` / `kubeProxy` | scraping control-plane components | ⚠️ often **must be disabled or fixed** on managed Kubernetes (EKS/GKE/AKS) |
| `kubeStateMetrics` | the kube-state-metrics subchart | lightly |
| `prometheus-node-exporter` | the node-exporter subchart | lightly |
| `grafana` | the Grafana subchart — dashboards, admin password, ingress, persistence | ⭐⭐ **yes, heavily** |
| `prometheusOperator` | the Operator itself — admission webhooks, TLS | lightly |
| `prometheus` | ⭐⭐ **the Prometheus CR** — `prometheusSpec` is where retention, storage, resources and selectors live | ⭐⭐ **yes, most of all** |
| `alertmanager` | ⭐ the Alertmanager CR — `alertmanagerSpec` + `config` (the routing tree) | ⭐⭐ yes |
| `thanosRuler` / `prometheusOperator.prometheusConfigReloader` | advanced | file [`12`](12-SCALING-HA-THANOS-MIMIR.md) |

### Read the four values that decide your cost and your data survival

```bash
# 1. retention — how long you keep metrics
grep -n -A2 '^  retention:' values-default.yaml
grep -n -A2 '^  retentionSize:' values-default.yaml

# 2. storage — the PVC template
grep -n -A20 '^  storageSpec:' values-default.yaml | head -30

# 3. resources — what it asks the cluster for
grep -n -A10 'prometheusSpec:' values-default.yaml | grep -A8 'resources:'

# 4. ⭐⭐ the selector behaviour that decides whether YOUR ServiceMonitors are seen
grep -n 'SelectorNilUsesHelmValues' values-default.yaml
```

That last one deserves its own paragraph.

### ⭐⭐ `serviceMonitorSelectorNilUsesHelmValues` — read this, it is the #1 "my ServiceMonitor does nothing" cause

The Prometheus Operator only scrapes `ServiceMonitor` objects that the **Prometheus CR selects**. The chart has a value that controls what happens when no selector is specified:

- **`true`** → the Operator injects `release: <your-release-name>` as a **required** label match. Your hand-written `ServiceMonitor`, which does not carry that label, is **silently ignored**. No error. No event. It just never appears in Targets.
- **`false`** → a `nil` selector means *"select every ServiceMonitor in scope"*. Your hand-written one is picked up.

```bash
grep -n 'serviceMonitorSelectorNilUsesHelmValues' values-default.yaml
```

⭐ **Read the value for the version you pinned — do not trust a blog post, including this one, because the default has changed across chart majors.** Whichever it is, you now have two correct responses:

1. Set it explicitly in your own values so it cannot change under you on the next chart bump:
   ```yaml
   prometheus:
     prometheusSpec:
       serviceMonitorSelectorNilUsesHelmValues: false
   ```
2. **Or** leave it `true` and put `release: <your-release>` on every `ServiceMonitor` you write.

File [`06`](06-SERVICEMONITOR-PODMONITOR.md) covers both, and shows how to prove which one you are in with a single `kubectl` command.

---

## 4 · Step 3 — Write your `values.yaml`

⭐ **Three values files, not one.** This is the pattern you will use for the rest of your career: a **committed base**, plus per-environment overlays. The base goes in git; the secrets never do.

### 4.1 `values.yaml` — the base you commit

```yaml
# ~/monitoring/kube-prometheus-stack/values.yaml
# Base values for kube-prometheus-stack 88.1.5 — committed to git.
# ⛔ NO SECRETS IN THIS FILE. Grafana admin password comes from a Secret (§4.3).

# ── Chart behaviour ────────────────────────────────────────────────────────
# ⭐ CRDs: installed on `helm install`, but ⛔ NEVER upgraded by `helm upgrade`.
#    See §14 — this is the single most expensive Helm gotcha in monitoring.
crds:
  enabled: true

# ── Global: one place for the registry and the storage class ───────────────
global:
  # storageClass: "my-fast-ssd"      # uncomment to force a class everywhere
  imagePullSecrets: []

# ══════════════════════════════════════════════════════════════════════════
#  PROMETHEUS — the part that matters
# ══════════════════════════════════════════════════════════════════════════
prometheus:
  enabled: true

  prometheusSpec:
    # ── ⭐⭐ Pin the server image explicitly. Do not inherit a floating tag ──
    # Read what your chart version defaults to, then decide:
    #   helm show values prometheus-community/kube-prometheus-stack --version 88.1.5 \
    #     | grep -A6 'prometheusSpec:' | grep -A4 'image:'
    image:
      registry: quay.io
      repository: prometheus/prometheus
      # tag: v3.x.y        # ⭐ set this once you have read the default for 88.1.5

    # ── Retention: time AND size. Whichever hits first wins ────────────────
    # ⭐ Always set BOTH. retention alone will let a cardinality explosion
    #    fill the disk and take Prometheus down before 15 days is up.
    retention: 15d
    retentionSize: "45GB"        # leave ~10% headroom under the PVC size below

    # ── Resources: requests are what scheduling uses, limits prevent a
    #    runaway Prometheus from taking the node with it ────────────────────
    resources:
      requests:
        cpu: "1"
        memory: 2Gi
      limits:
        cpu: "2"
        memory: 4Gi

    # ── ⭐⭐ PERSISTENCE. Without this block, Prometheus runs on an emptyDir
    #    and loses every metric on every restart. See §7 ────────────────────
    storageSpec:
      volumeClaimTemplate:
        spec:
          # storageClassName: my-fast-ssd     # omit → use the cluster default
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

    # ── ⭐⭐ Set this EXPLICITLY so a chart upgrade cannot flip it ──────────
    #    false → your hand-written ServiceMonitors are discovered.
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    probeSelectorNilUsesHelmValues: false
    scrapeConfigSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

    # ── Identifies THIS Prometheus when metrics leave the cluster ──────────
    #    ⭐ Non-negotiable the moment you have more than one cluster or you
    #    remote_write anywhere. See file 12.
    externalLabels:
      cluster: local
      environment: dev
      region: ap-south-1

    # ── Scrape tuning — leave defaults until file 11 tells you otherwise ──
    scrapeInterval: 30s
    scrapeTimeout: 10s
    evaluationInterval: 30s

    # ── ⭐ Enable the WAL compression + out-of-order settings only when you
    #    know why. Defaults are correct for a first install.

  # ── The Prometheus Service — how you reach the UI ────────────────────────
  service:
    type: ClusterIP
    port: 9090

  # ⛔ Do NOT expose Prometheus with a plain Ingress here. It has no auth.
  #    See file 13 for the authenticated reverse-proxy pattern.
  ingress:
    enabled: false

# ══════════════════════════════════════════════════════════════════════════
#  GRAFANA
# ══════════════════════════════════════════════════════════════════════════
grafana:
  enabled: true

  # ⭐⭐ The chart's built-in default password is the literal string
  #    "prom-operator". ⛔ Never ship that. Read it from a Secret instead:
  admin:
    existingSecret: grafana-admin          # created in §4.3
    userKey: admin-user
    passwordKey: admin-password

  # ⭐ Persist Grafana's own DB — otherwise your dashboards, users, alert
  #    silences and annotation history vanish on restart.
  #    (Dashboards provisioned FROM GIT survive; ones you click together don't.)
  persistence:
    enabled: true
    size: 10Gi
    # storageClassName: my-fast-ssd

  # ⭐ Keep the sidecars: they watch ConfigMaps labelled for dashboard/datasource
  #    provisioning, which is how dashboards get into Grafana from git.
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      searchNamespace: ALL          # ⭐ find dashboard ConfigMaps in any ns
    datasources:
      enabled: true
      label: grafana_datasource
      searchNamespace: ALL

  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits:   { cpu: 500m, memory: 512Mi }

  ingress:
    enabled: false                  # file 13 does this properly with TLS + auth

# ══════════════════════════════════════════════════════════════════════════
#  ALERTMANAGER
# ══════════════════════════════════════════════════════════════════════════
alertmanager:
  enabled: true

  alertmanagerSpec:
    resources:
      requests: { cpu: 50m,  memory: 64Mi }
      limits:   { cpu: 200m, memory: 256Mi }

    # ⭐ Persist silences and the notification log. Without this, every restart
    #    re-sends alerts that were already silenced, and re-notifies everything.
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi

  # ── A deliberately minimal routing tree so the install is self-contained.
  #    File 09 replaces this with a real one (Slack / PagerDuty / email).
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'namespace', 'severity']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'null'                    # ⭐ safe default: swallow everything
      routes:
        - matchers: [ 'severity = critical' ]
          receiver: 'null'                # file 09 points this at a real receiver
    receivers:
      - name: 'null'
    inhibit_rules:
      - source_matchers: [ 'severity = critical' ]
        target_matchers: [ 'severity = warning' ]
        equal: ['alertname', 'namespace']

# ══════════════════════════════════════════════════════════════════════════
#  EXPORTERS
# ══════════════════════════════════════════════════════════════════════════
kubeStateMetrics:
  enabled: true
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 200m, memory: 256Mi }

prometheus-node-exporter:
  enabled: true
  resources:
    requests: { cpu: 50m, memory: 32Mi }
    limits:   { cpu: 200m, memory: 64Mi }

# ══════════════════════════════════════════════════════════════════════════
#  ⚠️ CONTROL-PLANE SCRAPING — the managed-Kubernetes trap
# ══════════════════════════════════════════════════════════════════════════
# On EKS / GKE / AKS you do NOT have SSH access to the control plane, so the
# chart's default ServiceMonitors for these point at endpoints you cannot
# reach. Result: targets permanently DOWN and a wall of red in Grafana.
#
#   • Self-managed kubeadm  → leave enabled, may need cert path fixes
#   • EKS / GKE / AKS       → disable the ones you cannot reach
#
# ⭐ Find out which by installing once, then reading Status → Targets (§8).
kubeEtcd:
  enabled: false          # set true on kubeadm
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
kubelet:
  enabled: true           # ⭐ always reachable — this is where cAdvisor metrics come from
```

### 4.2 `values-prod.yaml` — the overlay you also commit

```yaml
# Layered on top: helm upgrade --install ... -f values.yaml -f values-prod.yaml
# ⭐ Later files are merged OVER earlier ones. Put environment-specifics last.
prometheus:
  prometheusSpec:
    retention: 30d
    retentionSize: "400GB"
    resources:
      requests: { cpu: "2",  memory: 8Gi }
      limits:   { cpu: "4",  memory: 16Gi }
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3-ssd
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 500Gi
    externalLabels:
      cluster: prod-ap-south-1a
      environment: production
      region: ap-south-1
    # ⭐ Two replicas behind the Operator's dedup, not a bigger single pod.
    replicas: 2

alertmanager:
  alertmanagerSpec:
    replicas: 3                       # ⭐ Alertmanager clusters; Prometheus does not
```

> ⭐ **How the merge actually works** (and the trap): Helm merges values files **map by map**, later file wins per key. But **lists are replaced, not appended.** If `values.yaml` has three `route.routes` entries and `values-prod.yaml` has one, production ends up with **one**. This is the most common values-layering bug and file [`06`](../helm-charts-mastery/06-VALUES-DESIGN-AND-PRECEDENCE.md) in the Helm folder covers it properly.

### 4.3 The Grafana admin Secret — created *outside* git

```bash
kubectl create namespace monitoring

kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"

# ⭐ Write it down NOW. There is no way to read it back cleanly later.
kubectl -n monitoring get secret grafana-admin \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

⛔ **Never put this in `values.yaml`.** A Grafana admin password in git is a leaked credential with a commit history, and `git filter-repo` afterwards is a bad afternoon.

---

## 5 · Step 4 — Install

### 5.1 Render it first — **never** install blind

```bash
helm template kps prometheus-community/kube-prometheus-stack \
  --version 88.1.5 \
  --namespace monitoring \
  -f values.yaml \
  > rendered.yaml

wc -l rendered.yaml
grep -c '^kind:' rendered.yaml
grep '^kind:' rendered.yaml | sort | uniq -c | sort -rn
```

```
    147  CustomResourceDefinition          ← ⭐ installed once, never upgraded
     62  ServiceMonitor
     41  PrometheusRule
     28  ConfigMap                          ← mostly Grafana dashboards
     19  Service
     12  ClusterRole / ClusterRoleBinding
      8  Deployment / DaemonSet / StatefulSet
      ...
```

⭐ **Count the `CustomResourceDefinition` objects and remember that number.** It is the reason upgrades break ([§14](#14--upgrading-and-uninstalling-safely-crds)).

Sanity-check that your persistence actually rendered:

```bash
grep -n -A12 'volumeClaimTemplates:' rendered.yaml | head -30
```

⛔ **If that returns nothing, your `storageSpec` key path is wrong** and you are about to install an `emptyDir` Prometheus. Stop and re-check §4.1 against `values-default.yaml`.

### 5.2 Install

```bash
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --version 88.1.5 \
  --namespace monitoring \
  -f values.yaml \
  --wait \
  --timeout 10m \
  --atomic
```

| Flag | Why |
|---|---|
| `upgrade --install` | ⭐ **Idempotent.** The same command works the first time and every time after. Use this form everywhere, forever |
| `--version 88.1.5` | The pin from §2. ⛔ Without it you get whatever is newest today |
| `--wait` | Blocks until every resource is Ready — so a failure is reported *by this command*, not discovered later |
| `--timeout 10m` | The default is 5 m and image pulls on a cold cluster are slow |
| `--atomic` | ⭐ **If anything fails, roll back automatically.** Without it you are left with a half-installed release in `failed` state that blocks the next attempt |

Expected output tail:

```
Release "kps" has been upgraded. Happy Helming!
NAME: kps
LAST DEPLOYED: ...
NAMESPACE: monitoring
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace monitoring get pods -l "release=kps"
```

### 5.3 Watch it come up

```bash
kubectl -n monitoring get pods -w
```

The order matters, and understanding *why* is the architecture lesson:

```
1. kps-kube-prom-operator-…            ← the Operator starts FIRST
2. kps-kube-state-metrics-…            ← a plain Deployment
3. kps-prometheus-node-exporter-…      ← a DaemonSet, one per node
4. kps-grafana-…                       ← Deployment with sidecars
5. prometheus-kps-kube-prometheus-0    ← ⭐ the Operator created this StatefulSet
6. alertmanager-kps-alertmanager-0     ← ⭐ the Operator created this too
```

⭐ **Steps 5 and 6 are the point of the whole design.** You did not write a StatefulSet for Prometheus. You installed an **Operator**, and then Helm applied a **`Prometheus` custom resource**, and the Operator *reconciled* that CR into a StatefulSet, a Service, a ServiceAccount, a RoleBinding and a generated `prometheus.yaml` Secret. That loop is file [`05`](05-INSIDE-THE-STACK-ARCHITECTURE.md).

---

## 6 · Step 5 — Verify every pod **and know what it is**

```bash
kubectl -n monitoring get pods -o wide
```

```
NAME                                                     READY  STATUS    AGE
kps-kube-prom-operator-6d4b8f9c7d-x2k9m                  1/1    Running   4m
kps-kube-state-metrics-5f8b7c6d9e-q4n2p                  1/1    Running   4m
kps-prometheus-node-exporter-ab3cd                        1/1    Running   4m
kps-prometheus-node-exporter-ef5gh                        1/1    Running   4m
kps-grafana-7b9d6f5c48-m8k3j                             3/3    Running   4m
prometheus-kps-kube-prometheus-0                          2/2    Running   3m
alertmanager-kps-alertmanager-0                           2/2    Running   3m
```

> ⭐ **Names are derived from your release name (`kps`) and the chart's naming templates**, so yours will differ if you chose a different release name or set `fullnameOverride`. **Always verify with `kubectl get pods`, never assume the exact string.** Use labels instead of names in scripts:
> ```bash
> kubectl -n monitoring get pods -l "release=kps"
> kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus
> ```

### What each one is

| Pod | READY | What it actually does |
|---|---|---|
| `…-kube-prom-operator` | 1/1 | **The Operator.** Watches `Prometheus`, `Alertmanager`, `ServiceMonitor`, `PodMonitor`, `Probe`, `ScrapeConfig`, `PrometheusRule`, `AlertmanagerConfig` CRs and reconciles them into real Kubernetes objects + a generated config. ⭐ **If your ServiceMonitor is ignored, this pod's logs are where the answer is** |
| `prometheus-kps-…-prometheus-0` | **2/2** | container 1 = **Prometheus** (the TSDB, the scraper, the rule evaluator, the HTTP API on :9090). container 2 = **`prometheus-config-reloader`** — a sidecar that watches the generated config Secret and `PrometheusRule` objects and hot-reloads Prometheus without a restart. ⭐ `2/2` is correct; `1/2` means the reloader is crash-looping |
| `alertmanager-…-0` | **2/2** | container 1 = **Alertmanager** (dedup, group, inhibit, silence, route to receivers, :9093). container 2 = the config reloader again |
| `…-grafana` | **3/3** | container 1 = **Grafana** (:3000). container 2 = **`sc-dashboard`** sidecar — watches ConfigMaps labelled `grafana_dashboard` and provisions them. container 3 = **`sc-datasource`** sidecar — same for `grafana_datasource`. ⭐ These two sidecars are how dashboards get into Grafana **from git** |
| `…-kube-state-metrics` | 1/1 | Reads the Kubernetes **API** and exposes the *state of objects* as metrics: `kube_pod_status_phase`, `kube_deployment_status_replicas_available`, `kube_node_status_condition`. ⭐ **This is what lets you alert on "pod is CrashLoopBackOff"** — cAdvisor cannot see that |
| `…-node-exporter-xxxxx` | 1/1 | **DaemonSet**, one per node. Exposes *host* metrics: CPU, memory, disk, filesystem, network, load. ⭐ The pod count must equal your node count |
| `…-prometheus-0` (again) | — | also contains the **cAdvisor** scrape, but cAdvisor runs *inside kubelet*, not here — that is why `kubelet.enabled: true` matters |

### The four verification commands

```bash
# 1. Everything Running, nothing CrashLoopBackOff / ImagePullBackOff
kubectl -n monitoring get pods --no-headers | awk '{print $3}' | sort | uniq -c

# 2. node-exporter pod count == node count
echo "nodes:  $(kubectl get nodes --no-headers | wc -l)"
echo "export: $(kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus-node-exporter --no-headers | wc -l)"

# 3. ⭐ The Operator is not erroring on your CRs
kubectl -n monitoring logs deploy/kps-kube-prom-operator --tail=50 | grep -iE 'error|reconcil|invalid' | tail -20

# 4. The Prometheus CR itself reports healthy
kubectl -n monitoring get prometheus -o custom-columns=\
'NAME:.metadata.name,REPLICAS:.status.availableReplicas,CONDITIONS:.status.conditions[*].type'
```

That fourth one is the one people miss. `kubectl get prometheus` shows the **custom resource**, and its `.status` tells you whether the Operator succeeded in reconciling it:

```bash
kubectl -n monitoring describe prometheus | tail -25
```

Look for `Condition: Available  True` and `Condition: Reconciled  True`. ⛔ If `Reconciled` is `False`, the Operator rejected part of your spec and **the pod may still be running with an old config** — the most confusing failure mode in this whole stack.

---

## 7 · Step 6 — ⭐⭐ Verify **persistence** — the one that fails silently

```bash
kubectl -n monitoring get pvc
```

**✅ What you want to see:**

```
NAME                                       STATUS  VOLUME    CAPACITY  ACCESS MODES  STORAGECLASS
prometheus-kps-kube-prometheus-db-data-…   Bound   pvc-8f2…  50Gi      RWO           standard
alertmanager-kps-alertmanager-db-…         Bound   pvc-1a4…  2Gi       RWO           standard
grafana                                    Bound   pvc-7c3…  10Gi      RWO           standard
```

**⛔ What "you skipped §1.4" looks like:**

```
No resources found in monitoring namespace.
```

That is an `emptyDir`. Confirm it:

```bash
kubectl -n monitoring get statefulset prometheus-kps-kube-prometheus \
  -o jsonpath='{.spec.volumeClaimTemplates[*].metadata.name}{"\n"}'
# empty output  →  no PVC  →  ⛔ data dies with the pod

kubectl -n monitoring get pod prometheus-kps-kube-prometheus-0 \
  -o jsonpath='{range .spec.volumes[*]}{.name}{"  →  "}{.emptyDir}{"\n"}{end}' | grep -v '  →  $'
# anything listed here with a non-empty emptyDir is volatile
```

**The fix:** the PVC template lives in `storageSpec`, which is **immutable on an existing StatefulSet**. You cannot just `helm upgrade` it.

```bash
# 1. delete the StatefulSet but KEEP the (empty) PVCs — or delete them too, you have no data yet
kubectl -n monitoring delete statefulset prometheus-kps-kube-prometheus
# 2. fix storageSpec in values.yaml (you already did, §4.1)
# 3. let the Operator recreate it
helm upgrade kps prometheus-community/kube-prometheus-stack --version 88.1.5 \
  -n monitoring -f values.yaml --wait
kubectl -n monitoring get pvc -w
```

> ⭐⭐ **This is why §1.4 exists.** Adding persistence *after* the fact means deleting a StatefulSet in production. Adding it *before* means typing six lines of YAML. Check `kubectl get storageclass` first, every time, on every cluster, forever.

Then prove the size matches what you asked for:

```bash
kubectl -n monitoring get pvc -o custom-columns=\
'CLAIM:.metadata.name,SIZE:.status.capacity.storage,CLASS:.spec.storageClassName,STATUS:.status.phase'
```

---

## 8 · Step 7 — Open Prometheus and look at **Targets**

```bash
kubectl -n monitoring get svc | grep -E 'prometheus|alertmanager|grafana'
```

```
kps-grafana                       ClusterIP   10.43.12.88   <none>   80/TCP
kps-kube-prometheus-alertmanager  ClusterIP   10.43.90.14   <none>   9093/TCP
kps-kube-prometheus-operator      ClusterIP   10.43.55.7    <none>   443/TCP
kps-kube-state-metrics            ClusterIP   10.43.71.22   <none>   8080/TCP
prometheus-operated               ClusterIP   None          <none>   9090/TCP   ← headless
```

⭐ **Note there is no `ClusterIP` Service for Prometheus itself by default** — the Operator creates the headless `prometheus-operated` Service for the StatefulSet. Use `port-forward` against the **pod**, or create your own Service:

```bash
kubectl -n monitoring port-forward pod/prometheus-kps-kube-prometheus-0 9090:9090
```

Then open <http://localhost:9090>.

### 8.1 Status → Targets — the single most important page in Prometheus

Every scrape job appears here with a health state. On a fresh install you should see **~50 jobs**, essentially all `UP`.

```
✅ UP     job="kubelet"                 endpoint="https-metrics"    30s
✅ UP     job="kubelet"                 endpoint="http-metrics"     30s
✅ UP     job="kube-state-metrics"      endpoint="http"             30s
✅ UP     job="node-exporter"           endpoint="https-metrics"    30s
✅ UP     job="apiserver"               endpoint="https"            30s
✅ UP     job="coredns"                 endpoint="http-metrics"     30s
✅ UP     job="operator"                endpoint="https"            30s
✅ UP     job="alertmanager"            endpoint="http-web"         30s
✅ UP     job="prometheus"              endpoint="web"              30s
⛔ DOWN   job="kube-controller-manager" …  connection refused       ← expected if you disabled it
```

**What to click on every single target you care about:**

- **`UP` / `DOWN`** — did the last scrape succeed?
- **Last Scrape** — how long ago? ⭐ If it is more than ~2× the scrape interval, something is slow.
- **Scrape Duration** — ⭐ **the number that predicts your next outage.** A target taking 9 s with a 10 s `scrapeTimeout` is one bad minute away from `DOWN`. And a slow scrape usually means **too many series**.
- **Error** — the exact reason when `DOWN`. Read it verbatim; it is almost always specific enough to fix directly.

### 8.2 Status → TSDB Status — cardinality, in one page

⭐ **Bookmark this.** It answers "why is my Prometheus using 6 GB of RAM?" in ten seconds.

- **Top 10 series count by metric name** — which metric names have the most distinct series
- **Top 10 series count by label name** — which *labels* are exploding (`pod`, `container`, `id`, `trace_id`…)
- **Top 10 series count by label value**
- **Number of Series** — your current total

> ⛔ **A label whose value is unbounded — a request ID, a user ID, a trace ID, a URL with a path parameter — will destroy your Prometheus.** `http_requests_total{path="/users/12345"}` gives you one series per user per endpoint per method. Ten thousand users × 20 endpoints × 4 methods = 800,000 series from *one* metric. File [`11`](11-STORAGE-RETENTION-TSDB.md) is entirely about this, and [`02`](02-PROMQL-FROM-ZERO.md) explains why a series is a label set.

### 8.3 Status → Configuration — see the config the Operator generated

⭐ **You never edit `prometheus.yaml`.** The Operator generates it from your CRs and stores it in a Secret. This page shows the result, and it is how you prove a `ServiceMonitor` was turned into a scrape job:

```bash
kubectl -n monitoring get secret prometheus-kps-kube-prometheus-prometheus \
  -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip > generated-prometheus.yaml
wc -l generated-prometheus.yaml
grep -c 'job_name:' generated-prometheus.yaml
```

If your `ServiceMonitor` is missing here, the Operator did not select it → go back to [§3](#3--step-2--read-the-defaults-before-you-change-them) and the selector values, then read the Operator logs.

### 8.4 Graph — your first four queries

```promql
up                                              # 1 for every reachable target, 0 for every DOWN one
count(up == 1)                                  # how many targets are UP right now
sum(rate(container_cpu_usage_seconds_total{namespace="monitoring"}[5m]))
prometheus_tsdb_head_series                     # ⭐ live series count — your cardinality number
```

⭐ `up` is **synthetic** — Prometheus generates it itself per scrape, it is not exported by the target. That is why it is the one metric that always exists and the basis of the `TargetDown` alert.

---

## 9 · Step 8 — Open Grafana

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```

Open <http://localhost:3000> and log in with the credentials from §4.3.

> If you did **not** use `admin.existingSecret`, the chart default is `admin` / **`prom-operator`** — read it back with:
> ```bash
> kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
> ```
> ⛔ If that prints `prom-operator`, you have shipped the world's most famous monitoring password. Change it now.

### Dashboards you get for free

The chart bundles **~30 dashboards** as ConfigMaps with the `grafana_dashboard: "1"` label, which the `sc-dashboard` sidecar picks up:

| Dashboard | What it is for |
|---|---|
| **Kubernetes / Compute Resources / Cluster** | ⭐ the first one to open — cluster-wide CPU/memory |
| **Kubernetes / Compute Resources / Namespace (Pods)** | per-namespace, per-pod usage |
| **Kubernetes / Compute Resources / Pod** | one pod, its containers |
| **Kubernetes / Nodes** | host-level, from node-exporter |
| **Node Exporter Full** | ⭐ the famous one — every host metric, 20+ panels |
| **Kubernetes / Views / …** | capacity planning |
| **Prometheus / Overview** | ⭐ **Prometheus monitoring itself** — scrape durations, series count, WAL, compaction. This is the dashboard that tells you your monitoring is dying |
| **Alertmanager Overview** | notifications sent, failed, silenced, inhibited |
| **etcd / API Server / Controller Manager / Scheduler / Proxy / CoreDNS** | control plane — ⚠️ blank if you disabled those scrapes in §4.1 |

### Verify the datasource is wired

**Connections → Data sources → Prometheus** should exist, with URL `http://prometheus-operated:9090`. Click **Save & test** → ✅ *"Successfully queried the Prometheus API."*

⭐ If that fails, Grafana can reach nothing, and every dashboard shows **"No data"** — which people misdiagnose as "Prometheus is broken" when Prometheus is fine.

### The two Grafana questions to ask on every install

```
1. Dashboards → are the bundled ones present?  (sidecar working)
2. Alerting → Alert rules → is it empty?       (⭐ yes, on a fresh install)
```

⭐ **Keep Grafana alerting empty.** You are running **Alertmanager**, which is the correct place. Two alerting systems firing on the same metric is how you page someone twice at 3 a.m. File [`10`](10-GRAFANA-DASHBOARDS.md) covers when the exception applies.

---

## 10 · Step 9 — Open Alertmanager

```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-alertmanager 9093:9093
```

Open <http://localhost:9093>. On a fresh install it should be **quiet** — the `null` receiver from §4.1 swallows everything by design.

### Prove alerting actually works, end to end

This is the step everyone skips, and the reason nobody notices their alerting is broken until the outage.

**1. Confirm Prometheus has loaded the rules:**

```bash
curl -s localhost:9090/api/v1/rules | jq '.data.groups | length'
kubectl -n monitoring get prometheusrule
```

**2. Fire a test alert deliberately.** The cleanest way is a rule that is guaranteed to be true:

```yaml
# test-alert-rule.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: install-verification
  namespace: monitoring
  labels:
    release: kps                        # ⭐ only needed if you left the selector on Helm values
spec:
  groups:
    - name: install-verification
      rules:
        - alert: InstallVerificationTest
          expr: vector(1)               # ⭐ always true, fires immediately
          for: 0m
          labels:
            severity: critical
          annotations:
            summary: "If you can read this, Prometheus → Alertmanager works"
            description: "Synthetic alert created during installation verification. Safe to delete."
```

```bash
kubectl apply -f test-alert-rule.yaml
sleep 90                                # evaluationInterval 30s + reloader lag
```

**3. Watch it travel:**

```bash
# in Prometheus UI → Status → Rules → is it FIRING?
curl -s localhost:9090/api/v1/alerts | jq '.data[].labels.alertname'

# in Alertmanager UI → Alerts → is it there?
curl -s localhost:9093/api/v2/alerts | jq '.[].labels.alertname'
```

Both should show `InstallVerificationTest`. ⭐ **If Prometheus shows it FIRING but Alertmanager does not**, the link between them is broken — check `alertmanagerConfiguration` in the Prometheus CR and the Operator logs.

**4. Clean up:**

```bash
kubectl delete -f test-alert-rule.yaml
sleep 60
curl -s localhost:9090/api/v1/alerts | jq '.data | length'   # → 0
```

> ⭐⭐ **Why this exercise is worth five minutes.** You have now proven, with evidence: rules load → rules evaluate → alerts fire → alerts reach Alertmanager → routing works. That is the entire alerting path. File [`08`](08-RECORDING-AND-ALERTING-RULES.md) and [`09`](09-ALERTMANAGER-ROUTING-RECEIVERS.md) build the real thing on top of a path you have already verified.

---

## 11 · Step 10 — ⭐ Prove it survives a restart

**This is the step that turns "I installed Prometheus" into "I know Prometheus works here."**

```bash
# 1. Record something you will recognise later
date -u +%s
kubectl -n monitoring exec prometheus-kps-kube-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series' \
  | jq -r '.data.result[0].value[1]'

# 2. Kill the pod
kubectl -n monitoring delete pod prometheus-kps-kube-prometheus-0

# 3. Watch it come back
kubectl -n monitoring get pod prometheus-kps-kube-prometheus-0 -w
```

Then, in the Prometheus UI → Graph, query over a window that **spans the restart**:

```promql
prometheus_tsdb_head_series[30m]
```

- ✅ **A continuous line with a short gap** → your PVC survived, the WAL replayed, history is intact.
- ⛔ **A line that starts at zero** → `emptyDir`. You are back in §7.

Then confirm the reloader sidecar did not fight you:

```bash
kubectl -n monitoring logs prometheus-kps-kube-prometheus-0 -c config-reloader --tail=20
kubectl -n monitoring logs prometheus-kps-kube-prometheus-0 -c prometheus --tail=30 | grep -iE 'replay|wal|loading|ready'
```

You want to see `Replaying WAL` followed by `WAL replay complete` and then `Server is ready to receive web requests`. ⭐ **WAL replay time is proportional to how much unflushed data there is** — a two-minute replay means your last two minutes of head block had to be rebuilt from the write-ahead log, and that is the gap in your graph.

---

## 12 · ⭐⭐ The **nine things** that go wrong on a first install

Each one: **symptom → cause → exact fix**. All nine are real and all nine are common.

### ① Pod stuck `Pending`, event says *"pod has unbound immediate PersistentVolumeClaims"*
**Cause:** no working StorageClass (§1.4), or the class has `volumeBindingMode: WaitForFirstConsumer` and no node can satisfy it.
```bash
kubectl -n monitoring describe pvc | tail -20
kubectl get storageclass
```
**Fix:** install a provisioner (kind → `local-path-provisioner`), or set `storageClassName` explicitly in `storageSpec`.

### ② `prometheus-…-0` is `CrashLoopBackOff`, log says *"opening storage failed: … no space left on device"*
**Cause:** the PVC is smaller than `retentionSize`, or a cardinality explosion filled it.
**Fix:** you set both in §4.1 — `retentionSize` must be **~10% below** the PVC size so Prometheus stops ingesting before the filesystem does. Then read TSDB Status (§8.2) and find the exploding label. File [`11`](11-STORAGE-RETENTION-TSDB.md).

### ③ Every control-plane target is `DOWN`
**Cause:** you are on EKS/GKE/AKS and left `kubeEtcd`/`kubeControllerManager`/`kubeScheduler`/`kubeProxy` enabled (§4.1).
**Fix:** disable the ones you cannot reach. On managed clusters those components are not yours to scrape. `kubelet` stays on — that is where cAdvisor comes from.

### ④ Your `ServiceMonitor` never appears in Targets, no error anywhere
**Cause:** ⭐ selector mismatch. Either `serviceMonitorSelectorNilUsesHelmValues: true` and your ServiceMonitor lacks `release: kps`, **or** your ServiceMonitor's `selector.matchLabels` does not match the target **Service's** labels (a very common confusion — it selects a *Service*, not a Pod).
```bash
kubectl -n monitoring logs deploy/kps-kube-prom-operator --tail=100 | grep -i servicemonitor
kubectl get servicemonitor -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,LABELS:.metadata.labels'
```
**Fix:** set the five `…SelectorNilUsesHelmValues: false` values explicitly (§4.1), or add the `release` label. Then re-check §8.3 — if the job is not in the generated config, the Operator never selected it. Full treatment in file [`06`](06-SERVICEMONITOR-PODMONITOR.md).

### ⑤ Grafana dashboards all say **"No data"**
**Cause:** the Prometheus datasource is wrong or unreachable (§9). Almost never a Prometheus problem.
```bash
kubectl -n monitoring exec deploy/kps-grafana -c grafana -- \
  wget -qO- http://prometheus-operated:9090/-/ready
```
**Fix:** Connections → Data sources → Prometheus → **Save & test**.

### ⑥ You are logged into Grafana with `admin` / `prom-operator`
**Cause:** you did not set `admin.existingSecret`.
**Fix:** §4.3. ⛔ And rotate it, because that default is published in the chart's source.

### ⑦ `helm upgrade` fails: *"rendered manifests contain a resource that already exists"*
**Cause:** a resource exists in the cluster that Helm has no record of — usually because someone `kubectl apply`'d it by hand, or a previous release was deleted without cleaning up.
**Fix:** read the error, it names the exact object. Then either `helm upgrade` with the object adopted (annotate it with the Helm ownership metadata) or delete it. File [`15`](../helm-charts-mastery/15-TROUBLESHOOTING-PRODUCTION.md) in the Helm folder covers adoption properly.

### ⑧ `OOMKilled` Prometheus, and gaps in every graph
**Cause:** memory limit below what the TSDB head block needs. The head block holds ~2–3 h of **all active series in memory**.
```bash
kubectl -n monitoring describe pod prometheus-kps-kube-prometheus-0 | grep -A5 'Last State'
```
**Fix:** raise the limit, **and** reduce series (§8.2). Raising the limit without fixing cardinality just delays it. Sizing maths in file [`11`](11-STORAGE-RETENTION-TSDB.md).

### ⑨ Everything is fine, but history resets to zero after every upgrade
**Cause:** ⛔ you uninstalled and reinstalled instead of upgrading, **or** the StatefulSet was recreated without `volumeClaimTemplates` (§7).
**Fix:** never `helm uninstall` to "start clean" on a stack with data. `helm upgrade` + `helm diff` (§14). And verify `kubectl get pvc` survives every change you make.

---

## 13 · Low-memory values for kind / minikube / laptops

⭐ If your cluster has **< 4 GB allocatable**, install with this overlay. The full stack will not fit and will spend its life `OOMKilled`.

```yaml
# values-small.yaml — layer AFTER values.yaml
prometheus:
  prometheusSpec:
    retention: 2d
    retentionSize: "3GB"
    scrapeInterval: 60s          # ⭐ halving scrape frequency halves ingest volume
    evaluationInterval: 60s
    resources:
      requests: { cpu: 200m, memory: 512Mi }
      limits:   { cpu: "1",  memory: 1Gi }
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
    # ⭐ Drop the highest-cardinality scrape configs you do not need locally
    additionalArgs:
      - name: storage.tsdb.no-lockfile
        value: "true"

alertmanager:
  alertmanagerSpec:
    resources:
      requests: { cpu: 25m,  memory: 32Mi }
      limits:   { cpu: 100m, memory: 128Mi }
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources: { requests: { storage: 1Gi } }

grafana:
  resources:
    requests: { cpu: 50m,  memory: 128Mi }
    limits:   { cpu: 250m, memory: 256Mi }
  persistence:
    enabled: true
    size: 2Gi

kubeStateMetrics:
  resources:
    requests: { cpu: 25m, memory: 64Mi }
    limits:   { cpu: 100m, memory: 128Mi }

prometheus-node-exporter:
  resources:
    requests: { cpu: 25m, memory: 16Mi }
    limits:   { cpu: 100m, memory: 32Mi }

# ⭐ Turn off the bundled rule groups you will not use locally — they cost
#    evaluation CPU every 30s whether or not you read the alerts.
defaultRules:
  rules:
    etcd: false
    kubeControllerManager: false
    kubeScheduler: false
    kubeProxy: false
    alertmanager: false
```

```bash
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --version 88.1.5 -n monitoring \
  -f values.yaml -f values-small.yaml \
  --wait --timeout 10m --atomic
```

Total footprint: roughly **1.2 GB**. Fits in a 4 GB kind cluster with room for your applications.

---

## 14 · Upgrading and **uninstalling** safely (CRDs!)

### 14.1 ⭐⭐ The CRD rule that costs everyone one bad afternoon

**Helm installs CRDs on `helm install`. Helm will NEVER upgrade them on `helm upgrade`.**

This is deliberate (upgrading a CRD can invalidate existing objects cluster-wide, and Helm has no rollback for a CRD), and it means:

> You upgrade `kube-prometheus-stack` from 88.1.5 → 88.3.0. The new **Prometheus Operator v0.93.x** starts and expects the new CRD schema. The CRDs in your cluster are still the **old** ones. The Operator logs a schema error, or silently drops the new fields, and your `Prometheus` CR does not reconcile.

**The correct upgrade procedure:**

```bash
NEW=88.3.0

# 1. ⭐ DIFF FIRST. Always. Non-negotiable on a chart this size.
helm diff upgrade kps prometheus-community/kube-prometheus-stack \
  --version $NEW -n monitoring -f values.yaml | tee diff-$NEW.txt
wc -l diff-$NEW.txt

# 2. Read the chart's own upgrade notes for every major you are crossing
helm show readme prometheus-community/kube-prometheus-stack --version $NEW \
  | sed -n '/## Upgrading Chart/,/^## /p' | head -80

# 3. Compare CRDs — the current cluster ones vs the ones in the new chart
kubectl get crd -o name | grep coreos.com | sort > crds-cluster.txt
helm template kps prometheus-community/kube-prometheus-stack --version $NEW \
  -f values.yaml | yq '. | select(.kind == "CustomResourceDefinition") | .metadata.name' \
  | sort > crds-new.txt
diff crds-cluster.txt crds-new.txt

# 4. ⭐ Apply the CRDs manually, BEFORE the release upgrade
helm template kps prometheus-community/kube-prometheus-stack --version $NEW \
  -f values.yaml --show-only crds/crd-servicemonitors.yaml | kubectl apply --server-side -f -
# …repeat for each changed CRD. --server-side avoids the
#   "metadata.annotations: Too long: must have at most 262144 bytes" error
#   that kubectl apply hits on these huge CRDs.

# 5. Back up the CRs the Operator will reconcile, so you can restore them
kubectl -n monitoring get prometheus,servicemonitor,podmonitor,prometheusrule,alertmanagerconfig -o yaml > crs-backup.yaml

# 6. Now upgrade the release
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --version $NEW -n monitoring -f values.yaml \
  --wait --timeout 15m --atomic

# 7. Verify
kubectl -n monitoring get prometheus -o jsonpath='{.items[0].status.conditions}' | jq
kubectl -n monitoring logs deploy/kps-kube-prom-operator --tail=100 | grep -i error
```

⭐ **`--server-side` in step 4 is not optional.** These CRDs exceed the 256 KB annotation limit that client-side `kubectl apply` uses to store last-applied-configuration, and it fails with a confusing error about annotation size.

### 14.2 Rollback

```bash
helm history kps -n monitoring
helm rollback kps <REVISION> -n monitoring --wait
```

⛔ **`helm rollback` does NOT roll back CRDs either.** If the new version changed a CRD, rolling the release back leaves the new CRD in place. Usually harmless; occasionally not.

### 14.3 Uninstall — completely

```bash
helm uninstall kps -n monitoring --wait

# ⛔ CRDs SURVIVE `helm uninstall`, BY DESIGN. Your PrometheusRules,
#    ServiceMonitors and the Prometheus/Alertmanager CRs all survive too.
kubectl get crd -o name | grep -E 'coreos\.com|monitoring\.coreos' | xargs -r kubectl delete

# then the namespace
kubectl delete namespace monitoring
```

⭐ **That CRD survival is a feature, not a bug** — it is why `helm uninstall` + `helm install` on a stack with real data does not delete your alert rules. But it is also why people who "clean up" a failed install end up with a cluster that refuses the next one (`rendered manifests contain a resource that already exists`, failure ⑦).

---

## 15 · ✅ What you have, and what is missing

**You have:**

- [x] Prometheus 3.x running as a StatefulSet with a **persistent** 50 Gi volume
- [x] ~50 scrape jobs, all targets `UP` (control-plane ones you deliberately disabled excepted)
- [x] **kube-state-metrics** → Kubernetes object state as metrics
- [x] **node-exporter** on every node → host metrics
- [x] **cAdvisor** via kubelet → per-container CPU/memory/network
- [x] ~200 **bundled alert rules** loaded and evaluating
- [x] **Alertmanager** with persistent silences, and a proven end-to-end alerting path
- [x] **Grafana** with ~30 provisioned dashboards and a working datasource
- [x] The **Operator** reconciling five CRDs — the mechanism file [`06`](06-SERVICEMONITOR-PODMONITOR.md) builds on
- [x] A pinned chart version, a committed values file, and `helm diff` in your muscle memory

**You are missing** — and each is a file:

- [ ] **Your own applications are not scraped.** That is file [`06`](06-SERVICEMONITOR-PODMONITOR.md) (`ServiceMonitor` / `PodMonitor`) and [`07`](07-INSTRUMENTING-THE-SHOP-APPS.md) (actual instrumentation code for Java, Go, Python, Node, React).
- [ ] **The bundled alerts are generic.** Yours will be about *your* SLOs — file [`08`](08-RECORDING-AND-ALERTING-RULES.md).
- [ ] **The `null` receiver means nobody gets paged.** File [`09`](09-ALERTMANAGER-ROUTING-RECEIVERS.md).
- [ ] **No dashboards for your services.** File [`10`](10-GRAFANA-DASHBOARDS.md).
- [ ] **No idea how big this gets.** File [`11`](11-STORAGE-RETENTION-TSDB.md) — the sizing formula and the cardinality workflow.
- [ ] **One replica, one cluster.** File [`12`](12-SCALING-HA-THANOS-MIMIR.md).
- [ ] **Prometheus and Grafana are unauthenticated and reachable by anything in the cluster.** ⛔ File [`13`](13-SECURITY-RBAC-MULTI-TENANCY.md) — do not put an Ingress on them before you read it.

---

## 16 · 🔨 Tasks

> **4.1** Run every check in [§1](#1--before-you-install--the-five-things-to-verify) on your cluster *before* installing, and record the five answers. Then install and prove that the two checks you skipped would have cost you something.

> **4.2** Install the stack with **no** `storageSpec`. Prove Prometheus is running on an `emptyDir`, prove that deleting the pod destroys history, then fix it without losing your release. Record the exact commands that prove each of the three claims.

> **4.3** Explain, with evidence from your own cluster, what the `2/2` in `prometheus-kps-kube-prometheus-0` means — and what breaks if the second container dies but the first keeps running.

> **4.4** Create a `ServiceMonitor` for a service of your choosing **without** reading §3's selector warning. Confirm it is silently ignored. Then find the ignored-ness in two places, and fix it in two different ways.

> **4.5** Prove the alerting path end to end (§10), then break it in one place — between Prometheus and Alertmanager — and describe how you knew which side was broken from the two API endpoints alone.

> **4.6** Use **Status → TSDB Status** to find your cluster's top cardinality contributor. Report the metric, the label, an approximate series count, and whether it is legitimate or a bug.

> **4.7** Upgrade the chart by one minor version following §14.1 exactly. Report how many CRDs differed and what `helm diff` showed that would have surprised you.

> **4.8** Produce a values file that fits the entire stack into **1.5 GB** of total requests and still keeps 7 days of metrics for a 3-node cluster. Justify every number you changed.

> **4.9** ⭐⭐ Your Prometheus pod is `OOMKilled` roughly every six hours. You have 8 Gi of limit available and the team wants you to raise it to 16 Gi. Explain what you do **first**, why raising the limit may be the wrong move, and the two metrics you watch to know whether your fix worked.

> **4.10** ⭐⭐ It is six months later. The chart has moved from 88.x to 95.x, three people have edited `values.yaml`, and nobody remembers what the CRDs were last updated. Write the runbook you would hand to whoever is on call, and name the step that, if skipped, causes the worst failure.

<details>
<summary>👉 Answers</summary>

**4.1** The five answers, with the command that produces each:

| # | Check | Command | What "bad" looks like |
|---|---|---|---|
| 1 | Right cluster | `kubectl config current-context` | a context name you don't recognise, or `kind-cicd` when you meant `eks-prod` |
| 2 | K8s version | `kubectl version -o json \| jq -r '.serverVersion.gitVersion'` | below the chart's `kubeVersion` → `helm install` refuses with *"chart requires Kubernetes version …"* |
| 3 | Allocatable memory | `kubectl describe nodes \| grep -A6 'Allocatable:'` | < 4 GB → the default stack thrashes; use §13 |
| 4 | **Working StorageClass** | `kubectl get storageclass` **then a probe PVC** | listed but the PVC never `Bound` → §12 failure ① |
| 5 | Helm version | `helm version` | v4 when this guide assumes v3 |

⭐ **The two checks people skip, and what each costs.** **(a) The probe PVC** — `kubectl get storageclass` listing a class proves a `StorageClass` *object* exists, not that it can *provision*. On kind with no provisioner installed you will see `standard` or nothing at all, and either way the PVC sits `Pending` forever. Cost: three days later, an install with no persistence (§4.2). **(b) `helm show chart … | grep kubeVersion`** — cost: the install fails at the very end after pulling several hundred MB of images, which is slow enough that people assume the chart is broken and start editing values to "fix" it. Both checks are under ten seconds.

**4.2** Three claims, three proofs.

```bash
# install without storageSpec
grep -v -A6 'storageSpec' values.yaml > values-nostorage.yaml
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --version 88.1.5 -n monitoring -f values-nostorage.yaml --wait --atomic

# CLAIM 1 — Prometheus is on an emptyDir
kubectl -n monitoring get pvc
#   → "No resources found in monitoring namespace."   ← proof, negative form
kubectl -n monitoring get statefulset prometheus-kps-kube-prometheus \
  -o jsonpath='{.spec.volumeClaimTemplates}' ; echo
#   → empty                                            ← proof, positive form
kubectl -n monitoring get pod prometheus-kps-kube-prometheus-0 \
  -o jsonpath='{.spec.volumes[?(@.name=="data")].emptyDir}'
#   → {} (present, so it IS an emptyDir)

# CLAIM 2 — deleting the pod destroys history
kubectl -n monitoring exec prometheus-kps-kube-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=timestamp(up)' | jq -r '.data.result[0].value[1]'
#   → note the earliest timestamp you can query:
kubectl -n monitoring exec prometheus-kps-kube-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_min_time' | jq -r '.data.result[0].value[1]'
kubectl -n monitoring delete pod prometheus-kps-kube-prometheus-0
kubectl -n monitoring wait --for=condition=Ready pod/prometheus-kps-kube-prometheus-0 --timeout=300s
#   → re-query prometheus_tsdb_min_time: it has jumped forward to "now".
#      The old data is gone. Also query something over a window that spans the
#      deletion: `up[30m]` shows a line that STARTS at the restart.

# CLAIM 3 — fix it without losing the release
kubectl -n monitoring delete statefulset prometheus-kps-kube-prometheus
helm upgrade kps prometheus-community/kube-prometheus-stack --version 88.1.5 \
  -n monitoring -f values.yaml --wait --atomic          # ← values.yaml HAS storageSpec
kubectl -n monitoring get pvc -w                        # → Bound
helm history kps -n monitoring                          # → revision 3, not a new release
```

⭐ **The point of "without losing your release":** the naive fix is `helm uninstall` + `helm install`, which throws away the Grafana PVC, the Alertmanager PVC, every `PrometheusRule` you created, and bumps you back to revision 1. The correct fix is to delete only the **StatefulSet** — a Kubernetes object the **Operator** owns and will happily recreate from the CR — and let `helm upgrade` update the release record. `volumeClaimTemplates` is immutable on an existing StatefulSet, which is *why* the StatefulSet has to go; it is not a reason to nuke the release.

**4.3** `2/2` = two containers in the pod, both Ready:

1. **`prometheus`** — the actual server: scraper, TSDB, rule evaluator, HTTP API on `:9090`.
2. **`config-reloader`** — `prometheus-operator`'s `prometheus-config-reloader` sidecar. It watches (a) the generated `prometheus.yaml.gz` Secret and (b) all `PrometheusRule` objects the Prometheus CR selects, and on change it either reloads config via the `/-/reload` endpoint or restarts Prometheus.

**What breaks if the reloader dies but Prometheus keeps running:** ⭐ **Prometheus keeps serving stale configuration forever, silently.** Scraping continues, dashboards keep working, existing alerts keep evaluating — so nothing looks wrong. But every new `ServiceMonitor` you create is ignored, every `PrometheusRule` you edit has no effect, and every alert you *add* never exists. The pod shows `1/2`, and because Prometheus is healthy, nothing pages you. That is the worst failure mode in this stack: **a monitoring system that is confidently wrong**.

```bash
# how you'd catch it
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus \
  -o jsonpath='{range .items[*]}{.metadata.name}{"  ready="}{.status.containerStatuses[?(@.name=="config-reloader")].ready}{"\n"}{end}'
kubectl -n monitoring logs prometheus-kps-kube-prometheus-0 -c config-reloader --tail=50
```

And this is exactly why file [`08`](08-RECORDING-AND-ALERTING-RULES.md) has you alert on `kube_pod_container_status_ready == 0` for the monitoring namespace itself — **you must monitor the monitor.**

**4.4** Creating a `ServiceMonitor` with no labels and no `release: kps`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: checkout
  namespace: shop-production
spec:
  selector:
    matchLabels: { app: checkout }
  endpoints:
    - port: metrics
      interval: 30s
```

It is silently ignored — **no error, no event, no log line about `checkout`**. Find the ignored-ness in **two places**:

```bash
# PLACE 1 — the generated config. If the job isn't here, the Operator never selected it.
kubectl -n monitoring get secret prometheus-kps-kube-prometheus-prometheus \
  -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | grep -c 'checkout'
#   → 0

# PLACE 2 — the Prometheus CR's resolved selectors, and the Operator's own view
kubectl -n monitoring get prometheus -o jsonpath='{.items[0].spec.serviceMonitorSelector}' | jq
kubectl -n monitoring logs deploy/kps-kube-prom-operator --tail=200 | grep -i servicemonitor
# PLACE 2b — the UI, which is where you'd normally notice: Status → Targets, no "checkout" job
```

**Two fixes:**

```yaml
# FIX A — make the Prometheus CR select everything (recommended, §4.1)
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
```

```yaml
# FIX B — leave the selector strict and label the ServiceMonitor to match it
metadata:
  name: checkout
  namespace: shop-production
  labels:
    release: kps            # ⭐ must equal the Helm RELEASE NAME
```

⭐ **Fix A vs Fix B is a real architectural choice, not a preference.** Fix B scopes discovery to one release, which is what you want in **multi-tenant** clusters where teams create their own `ServiceMonitor` objects and you do not want them scraping each other (file [`13`](13-SECURITY-RBAC-MULTI-TENANCY.md)). Fix A is what you want in a **single-team** cluster where the friction is not worth the isolation. Also note Fix B requires the ServiceMonitor to be in a namespace the Prometheus CR is allowed to watch (`serviceMonitorNamespaceSelector`) — the second-most-common reason for silent ignoring, and file [`06`](06-SERVICEMONITOR-PODMONITOR.md) covers it.

**4.5** Break it *between* Prometheus and Alertmanager by removing the alertmanager endpoint from the Prometheus CR (the cleanest single-point break):

```bash
kubectl -n monitoring patch prometheus prometheus-kps-kube-prometheus --type=json \
  -p='[{"op":"replace","path":"/spec/alerting/alertmanagers/0/port","value":"wrong-port"}]'
# ⚠️ the Operator will reconcile this back; for a lasting break, patch the
#    Alertmanager Service port or block it with a NetworkPolicy instead.
```

**How you know which side is broken, from two endpoints alone:**

```bash
# SIDE 1 — is Prometheus FIRING the alert?  (its own view)
curl -s localhost:9090/api/v1/alerts | jq '[.data[].labels.alertname]'

# SIDE 2 — did Alertmanager RECEIVE it?  (its own view)
curl -s localhost:9093/api/v2/alerts | jq '[.[].labels.alertname]'
```

| `api/v1/alerts` | `api/v2/alerts` | Diagnosis |
|---|---|---|
| `["InstallVerificationTest"]` | `["InstallVerificationTest"]` | ✅ path intact |
| `["InstallVerificationTest"]` | `[]` | ⛔ **broken between them.** Prometheus is firing; Alertmanager never got it. Look at the Prometheus CR's `spec.alerting.alertmanagers`, the Alertmanager Service/port, NetworkPolicy, and Prometheus's own log line `Error sending alert` |
| `[]` | anything | ⛔ **broken before Prometheus.** The rule is not loaded or not evaluating. Check `api/v1/rules`, `kubectl get prometheusrule`, the Operator logs, and whether the rule's labels satisfy the Prometheus CR's `ruleSelector` |

⭐ **That two-endpoint test is the entire diagnostic method**, and it generalises: Prometheus's API tells you what Prometheus believes, Alertmanager's API tells you what Alertmanager believes. Never infer one from the other, and never debug by reading Grafana — Grafana is a third opinion downstream of both.

**4.6** Workflow:

```bash
# live total
curl -s localhost:9090/api/v1/status/tsdb | jq '.data'
```

Status → TSDB Status shows four tables. Read them in this order:

1. **Top 10 series count by label name** — ⭐ start here. If one label dominates (commonly `id`, `pod`, `container`, `device`, `image`, or something custom like `user_id`), that label is your cardinality driver.
2. **Top 10 series count by metric name** — which metrics carry them.
3. **Top 10 series count by label value** — is one *value* exploding (e.g. one namespace with 2,000 pods)?
4. **Number of Series** — the total. Rough guide: **< 500 k is comfortable on 2 GB; 1–5 M needs 8 GB+; > 10 M you need sharding (file [`12`](12-SCALING-HA-THANOS-MIMIR.md)).**

**Legitimate vs bug — the test:** a label is **legitimate** if its value set is *bounded by something you control and can enumerate* (pods, nodes, namespaces, endpoints, HTTP methods, status codes). It is a **bug** if the value set is *unbounded and grows with traffic* — a request ID, a trace ID, a user ID, a session token, a full URL with path parameters, an email address, a free-text search query.

Realistic finding on a fresh kube-prometheus-stack: the top contributor is usually **`container_cpu_usage_seconds_total`** / **`container_memory_working_set_bytes`** by `pod` + `container` + `id`, and it is **legitimate** — cAdvisor emits one series per cgroup and you genuinely have that many containers. The **bug** case looks like `http_request_duration_seconds_count{path="/api/orders/a1b2c3d4"}` — an unnormalised URL. Fix is in the instrumentation (use a route template, not the raw path) or in a relabel to drop/replace the label (file [`06`](06-SERVICEMONITOR-PODMONITOR.md) §relabeling).

**4.7** 88.1.5 → 88.3.0 (same minor-line, `appVersion` unchanged at v0.93.0):

```bash
helm diff upgrade kps prometheus-community/kube-prometheus-stack \
  --version 88.3.0 -n monitoring -f values.yaml | tee diff.txt
diff <(kubectl get crd -o name | grep coreos.com | sort) crds-new.txt
```

**Realistic result:** CRDs **do not differ** (appVersion v0.93.0 in both, so the Operator version is identical → the CRD schemas it ships are identical). `helm diff` shows changes confined to the bundled **`ConfigMap` dashboards** and **`PrometheusRule`** objects — i.e. refreshed Grafana JSON and re-tuned alert thresholds.

⭐ **What would have surprised you, and why diffing matters:** the `PrometheusRule` diffs. Bundled alert rules get their **thresholds and `for:` durations tuned between chart versions** — a rule that was `for: 15m` becomes `for: 5m`, or a threshold moves. Nobody expects a chart upgrade to change *when they get paged*, and nobody reads a 4,000-line diff of Grafana JSON to find the two rules that changed. `helm diff` piped through `grep -A20 'kind: PrometheusRule'` finds them in five seconds. **That is the single highest-value use of `helm diff` on this chart.**

Also worth checking every time:
```bash
helm show readme prometheus-community/kube-prometheus-stack --version 88.3.0 \
  | sed -n '/## Upgrading Chart/,/^## /p' | head -40
```
The chart's own README carries explicit "From 88.x to 88.y" notes, and on **major** bumps they describe breaking values changes.

**4.8** 1.5 GB total requests, 7 days, 3 nodes. Budget it first, then set it:

| Component | Request | Share |
|---|---|---|
| `prometheus` | **768 Mi** | 51% |
| `grafana` | 128 Mi | 9% |
| `alertmanager` | 32 Mi | 2% |
| `kube-state-metrics` | 96 Mi | 6% |
| `node-exporter` × 3 | 3 × 24 Mi = 72 Mi | 5% |
| `prometheus-operator` | 128 Mi | 9% |
| 3 × `config-reloader` sidecars | 3 × 16 Mi = 48 Mi | 3% |
| **headroom** | ~256 Mi | 15% |
| **Total** | **≈ 1.5 GB** | |

```yaml
prometheus:
  prometheusSpec:
    replicas: 1                      # ⛔ 1, not 2 — HA doubles this line
    retention: 7d
    retentionSize: "6GB"
    scrapeInterval: 60s              # ⭐ the biggest single lever: halves ingest
    evaluationInterval: 60s
    resources:
      requests: { cpu: 250m, memory: 768Mi }
      limits:   { cpu: "1",  memory: 1536Mi }
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources: { requests: { storage: 8Gi } }
    # ⭐ drop the highest-volume scrape jobs you don't need for 7 days
    scrapeInterval: 60s
defaultRules:
  rules: { etcd: false, kubeControllerManager: false, kubeScheduler: false, kubeProxy: false }
grafana:
  resources: { requests: { cpu: 50m, memory: 128Mi }, limits: { cpu: 250m, memory: 256Mi } }
alertmanager:
  alertmanagerSpec:
    resources: { requests: { cpu: 25m, memory: 32Mi }, limits: { cpu: 100m, memory: 128Mi } }
kubeStateMetrics:
  resources: { requests: { cpu: 50m, memory: 96Mi }, limits: { cpu: 200m, memory: 192Mi } }
prometheus-node-exporter:
  resources: { requests: { cpu: 25m, memory: 24Mi }, limits: { cpu: 100m, memory: 48Mi } }
prometheusOperator:
  resources: { requests: { cpu: 100m, memory: 128Mi }, limits: { cpu: 400m, memory: 256Mi } }
```

**Justification for every number changed:**

- **`scrapeInterval: 60s` (from 30 s)** — ⭐ the dominant lever. Prometheus stores one sample per series per scrape, so doubling the interval **halves samples ingested, halves disk for the same retention, and roughly halves head-block memory**. The cost is resolution: you cannot see a spike shorter than ~2 minutes. For a 3-node dev cluster that is the right trade; for a production latency SLO it is not (file [`11`](11-STORAGE-RETENTION-TSDB.md) §sizing).
- **`retention: 7d` + `retentionSize: 6GB` on an 8 Gi PVC** — set **both**, with `retentionSize` ~25% under the PVC so Prometheus stops ingesting before the filesystem fills. Sizing: at 60 s interval with ~250 k active series, `250000 × 86400/60 × 7 ≈ 2.5 × 10⁸` samples; at ~1.3 bytes/sample compressed that is ~330 MB — so 6 GB is generous, and generous is correct because cardinality is never as stable as you assume.
- **`replicas: 1`** — ⛔ HA doubles Prometheus memory for zero extra capacity (both replicas scrape the same targets; dedup happens downstream). File [`12`](12-SCALING-HA-THANOS-MIMIR.md) covers when it is worth it.
- **`defaultRules` off for etcd / controller-manager / scheduler / proxy** — each rule group is evaluated every `evaluationInterval` whether or not anyone reads it. Disabling four groups you cannot act on locally buys CPU back.
- **Every other component's request** — set to ~50% of its observed steady state (measure with `kubectl top pod -n monitoring` after an hour), and limits at ~2× request. Requests drive scheduling; limits prevent one runaway component from taking the node.

⭐ **The number I did *not* change: `prometheus`'s limit at 1536 Mi.** With a 768 Mi request and an in-memory head block, a limit only 2× the request means a cardinality surprise produces an `OOMKill` (recoverable, WAL replays) rather than node pressure (not recoverable). **Prefer being OOMKilled to being evicted.**

**4.9** ⭐⭐ **Do not raise the limit first.** Here is the order, and the reasoning.

**Step 1 — establish whether this is a *size* problem or a *cardinality* problem.** They have different fixes and raising memory only addresses the first.

```bash
# the OOM evidence: what did it use, and when?
kubectl -n monitoring describe pod prometheus-kps-kube-prometheus-0 | grep -A8 'Last State'
#   Last State: Terminated — Reason: OOMKilled — Exit Code: 137

# the shape of memory over the six hours BEFORE the kill
```
```promql
container_memory_working_set_bytes{namespace="monitoring",pod=~"prometheus-.*"}
rate(prometheus_tsdb_head_series[1h])          # ⭐ is the series count GROWING?
prometheus_tsdb_head_series
```

⭐ **The diagnostic distinction:** if `prometheus_tsdb_head_series` is **flat** and memory still climbs to the limit, that is a genuine sizing shortfall → raise the limit. If series count is **rising** across the six hours, memory is rising *because* series are rising → that is a **cardinality leak** and 16 Gi buys you twelve hours instead of six.

**Step 2 — find the leak.** Status → TSDB Status (§8.2), plus:

```bash
curl -s localhost:9090/api/v1/status/tsdb | jq '.data'
# and per-target cost:
```
```promql
topk(10, count by (__name__)({__name__=~".+"}))
scrape_samples_scraped
topk(10, scrape_samples_scraped)         # ⭐ which target is dumping series on you
```

A target whose `scrape_samples_scraped` jumped yesterday and whose job name is one of *your* `ServiceMonitor`s is the usual culprit — someone added a label with an unbounded value.

**Step 3 — fix the leak at the source**, in preference order:

1. **Fix the instrumentation** — remove the unbounded label, or normalise it (`/orders/:id` not `/orders/a1b2c3`). ⭐ This is the only permanent fix.
2. **Drop it at scrape time** with `metricRelabelings` on the ServiceMonitor (file [`06`](06-SERVICEMONITOR-PODMONITOR.md)) — fast, reversible, no redeploy of the app.
3. **Then**, if series are genuinely that high, raise the limit — and raise it based on measurement, not on doubling:
   ```promql
   max_over_time(container_memory_working_set_bytes{pod=~"prometheus-.*"}[7d])
   ```
   Set the limit to **~1.5× that**, not to a round number.

**Step 4 — add the guardrail so the next one is a page, not a discovery:**

```yaml
- alert: PrometheusMemoryHigh
  expr: |
    container_memory_working_set_bytes{namespace="monitoring",pod=~"prometheus-.*",container="prometheus"}
      /
    kube_pod_container_resource_limits{namespace="monitoring",resource="memory"} > 0.85
  for: 15m
  labels: { severity: warning }
  annotations:
    summary: "Prometheus is above 85% of its memory limit"
    description: "At the current rate this OOMs within hours. Check TSDB Status for cardinality."
- alert: PrometheusSeriesGrowing
  expr: deriv(prometheus_tsdb_head_series[6h]) > 0
  for: 30m
  labels: { severity: warning }
```

**Why raising the limit may be the wrong move — three reasons:**

- **It converts a fast, loud failure into a slow, quiet one.** An OOMKill every six hours gets noticed. One every six days does not, and by then the leak has spread to three services.
- **It does not fix the cost.** Memory is only one axis; the same series count is being written to disk, compacted, queried, and (if you remote_write) shipped. Cardianlity is a *cost* problem, not a memory problem.
- **⛔ It can make the outage worse.** A bigger head block means a **longer WAL replay** after the eventual kill, which means a **longer gap** in your metrics precisely during the incident you are investigating.

**The two metrics that tell you the fix worked:**

```promql
prometheus_tsdb_head_series                                          # must go FLAT and stay flat
max_over_time(container_memory_working_set_bytes{container="prometheus"}[1h])
  / kube_pod_container_resource_limits{resource="memory"}             # must sit below ~0.7
```

Plus one operational check that is not a metric: **no `OOMKilled` in `kubectl describe pod` for 7 days**, and `prometheus_tsdb_wal_replay_duration_seconds` back to a small number (a long replay means you are still carrying too much in the head block).

**4.10** ⭐ The runbook. This is the document that should already exist, in git, next to `values.yaml`.

```markdown
# RUNBOOK — kube-prometheus-stack upgrade
Owner: platform-team@   ·   Last reviewed: <date>   ·   Blast radius: all monitoring, all clusters

## 0. Before you start (read this, do not skip)
- [ ] You know the CURRENT pinned version:  `helm -n monitoring list -o json | jq -r '.[].chart'`
- [ ] You know the TARGET version and have read its release notes
- [ ] You have read the chart README's "Upgrading Chart" section for EVERY major you cross
- [ ] ⛔ CRD drift check done (§1) — this is the step that, skipped, causes the worst failure
- [ ] Change window booked; on-call informed; a second person reachable
- [ ] Backup taken (§2)

## 1. ⛔⛔ CRD DRIFT — the step that causes the worst failure
Nobody has updated the CRDs since <date>. Establish the truth first:

    kubectl get crd -o custom-columns=\
    'NAME:.metadata.name,CREATED:.metadata.creationTimestamp' | grep coreos.com

Compare against what the target chart ships:

    helm template kps prometheus-community/kube-prometheus-stack --version $NEW \
      -f values.yaml --show-only crds/crd-servicemonitors.yaml \
      | yq '.spec.versions[0].name'

    diff <(kubectl get crd -o name | grep coreos.com | sort) crds-new.txt

**Why skipping this is the worst failure:** the new Operator binary expects the new
CRD schema. With old CRDs in place it either (a) refuses to reconcile — your
`Prometheus` CR shows `Reconciled: False` while the OLD StatefulSet keeps running
with OLD config, so **monitoring looks healthy and is silently frozen**, or
(b) reconciles and drops every field the old CRD doesn't know, so your
`storageSpec`, selectors or `externalLabels` **disappear from the spec without
anyone editing values.yaml**. (a) is bad; (b) loses data.
Neither produces an obvious error. Both are found days later.

Apply CRDs **server-side** (they exceed the 256 KB client-side annotation limit):

    helm template ... --show-only crds/<crd>.yaml | kubectl apply --server-side -f -

## 2. Backup
    kubectl -n monitoring get prometheus,servicemonitor,podmonitor,probe,scrapeconfig,\
    prometheusrule,alertmanager,alertmanagerconfig -o yaml > crs-$(date +%F).yaml
    helm get values kps -n monitoring > values-live-$(date +%F).yaml
    helm history kps -n monitoring > history-$(date +%F).txt
    # Grafana: the PVC (dashboards-from-git survive; UI-built ones do not)
    # Prometheus data: NOT backed up by default — see file 11

## 3. Diff — read it, specifically the PrometheusRule section
    helm diff upgrade kps <chart> --version $NEW -n monitoring -f values.yaml > diff.txt
    grep -B2 -A20 'kind: PrometheusRule' diff.txt     # ⭐ threshold/for: changes = paging changes
    grep -B2 -A10 'storageSpec\|retention\|resources' diff.txt

## 4. Upgrade
    helm upgrade kps <chart> --version $NEW -n monitoring -f values.yaml \
      --wait --timeout 15m --atomic
    # ⛔ never omit --version. Never omit --atomic.

## 5. Verify (all five, in order)
    kubectl -n monitoring get pods
    kubectl -n monitoring get prometheus -o jsonpath='{.items[0].status.conditions}' | jq
    kubectl -n monitoring logs deploy/kps-kube-prom-operator --tail=200 | grep -i error
    curl -s localhost:9090/api/v1/targets | jq '[.data.activeTargets[].health] | group_by(.) | map({(.[0]): length})'
    curl -s localhost:9090/api/v1/rules  | jq '.data.groups | length'
    # Grafana: one dashboard renders, datasource test passes
    # Alertmanager: fire the synthetic InstallVerificationTest rule (§10) and see it arrive

## 6. Rollback — know it BEFORE you need it
    helm rollback kps <REVISION> -n monitoring --wait
    ⛔ helm rollback does NOT roll back CRDs. If §1 applied new CRDs, they stay.
       That is usually safe; if it is not, restore from crs-<date>.yaml.

## 7. After
    - Update Chart.lock.txt with the new version and today's date
    - Open a ticket to reconcile CRD drift within 30 days — do not let this recur
    - Record what surprised you. This runbook is only good if it is edited after use.
```

⭐⭐ **The step that, if skipped, causes the worst failure: §1, the CRD drift check.** Every other step either fails loudly (`helm upgrade` errors, pods crash) or is recoverable (`helm rollback`). The CRD mismatch is the only one that produces a **green, healthy-looking cluster that has stopped accepting configuration changes** — and because Prometheus keeps scraping with its last-known config, dashboards keep updating and nobody notices until an alert that should have fired does not. Six months of drift means you are crossing several CRD schema revisions at once, which is precisely when the new fields you depend on are the ones that get dropped.

The second-order lesson: **`Chart.lock.txt` (§2 of this file) exists to prevent §1 from ever being a surprise.** A pinned, dated, committed chart version with a "CRDs last updated" field turns this from an archaeology exercise into a five-minute diff.

</details>

---

## ➡️ Next

**[`05-INSIDE-THE-STACK-ARCHITECTURE.md`](05-INSIDE-THE-STACK-ARCHITECTURE.md)** — you just installed ten pods and five CRDs. File `05` opens the box: what the Operator actually does, how a `ServiceMonitor` becomes a scrape job, how the config-reloader hot-reloads without dropping data, and why this architecture beats a hand-written `prometheus.yaml`.

**If you would rather scrape your own apps first:** jump to [`06-SERVICEMONITOR-PODMONITOR.md`](06-SERVICEMONITOR-PODMONITOR.md), then come back to `05`.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
