# ☸️ The Complete Kubernetes Guide — From "What is a Pod?" to Production

> **Audience:** you know Docker (images, containers, `-p`, volumes, compose) and nothing about Kubernetes.
> **Goal:** by the end you understand every object you'll meet in a real cluster and can debug one under pressure.
> **How to read it:** §0–§4 are mandatory. §5–§9 are the daily workhorses. §10–§16 are "read once, refer back forever".

**Table of contents**

- [§0 — Set up your cluster (30 min)](#0--set-up-your-cluster-30-min)
- [§1 — What Kubernetes actually is](#1--what-kubernetes-actually-is)
- [§2 — Cluster architecture (the parts and what they do)](#2--cluster-architecture-the-parts-and-what-they-do)
- [§3 — Anatomy of every Kubernetes object](#3--anatomy-of-every-kubernetes-object)
- [§4 — Pods: the atomic unit](#4--pods-the-atomic-unit)
- [§5 — Workloads: Deployment, ReplicaSet, StatefulSet, DaemonSet, Job, CronJob](#5--workloads)
- [§6 — Services & networking](#6--services--networking)
- [§7 — Configuration: ConfigMaps & Secrets](#7--configuration-configmaps--secrets)
- [§8 — Storage: PV, PVC, StorageClass, CSI](#8--storage-pv-pvc-storageclass-csi)
- [§9 — Health: probes, restart policies, lifecycle hooks](#9--health-probes-restart-policies-lifecycle-hooks)
- [§10 — Scheduling: resources, affinity, taints, topology spread, priority](#10--scheduling)
- [§11 — Namespaces, RBAC, ServiceAccounts, security](#11--namespaces-rbac-serviceaccounts-security)
- [§12 — Ingress, Gateway API, DNS, NetworkPolicy](#12--ingress-gateway-api-dns-networkpolicy)
- [§13 — Autoscaling: HPA, VPA, Cluster Autoscaler, KEDA](#13--autoscaling)
- [§14 — Helm & Kustomize](#14--helm--kustomize)
- [§15 — Observability: logs, events, metrics, tracing](#15--observability)
- [§16 — Troubleshooting: the complete decision tree](#16--troubleshooting-the-complete-decision-tree)
- [§17 — Docker → Kubernetes translation table](#17--docker--kubernetes-translation-table)
- [§18 — Where to go next](#18--where-to-go-next)

---

## §0 — Set up your cluster (30 min)

You cannot learn Kubernetes by reading. You need a cluster in the next 10 minutes.

### 0.1 Install `kubectl`

**macOS**
```bash
brew install kubectl
kubectl version --client        # should print Client Version: v1.3x
```

**Linux**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

**Windows (PowerShell)**
```powershell
winget install Kubernetes.kubectl
kubectl version --client
```

### 0.2 Pick ONE local cluster tool

| Tool | Best for | RAM floor | Multi-node |
|---|---|---|---|
| **kind** | CI, fast resets, learning controllers | 4 GB | ✅ easy |
| **minikube** | Addons (`ingress`, `metrics-server`), driver flexibility | 4 GB | ✅ |
| **k3d** | Weak laptops, k3s internals | 2 GB | ✅ |
| **Docker Desktop** | "I just want it to work" | 6 GB | ❌ single node |

#### Option A — kind (recommended)

```bash
# macOS / Linux
brew install kind        # or: go install sigs.k8s.io/kind@latest
# Linux binary:
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

kind version
```

`kind-config.yaml` — a real 1-control-plane + 2-worker cluster with Ingress ports mapped to your laptop:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: learn
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 8080        # http://localhost:8080  -> Ingress
        protocol: TCP
      - containerPort: 443
        hostPort: 8443        # https://localhost:8443 -> Ingress
        protocol: TCP
  - role: worker
  - role: worker
```

```bash
kind create cluster --config kind-config.yaml
kubectl cluster-info --context kind-learn
kubectl get nodes            # 3 nodes, all Ready
```

> ⚠️ **The #1 kind gotcha:** images you build locally are *not* in the cluster. kind runs its own containerd. Fix: `kind load docker-image myapp:1.0 --name learn` — or set `imagePullPolicy: Never` / `IfNotPresent` and load first.

#### Option B — minikube

```bash
# macOS
brew install minikube
# Linux
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

minikube start --cpus=4 --memory=8192 --driver=docker --kubernetes-version=stable
minikube addons enable metrics-server
minikube addons enable ingress
minikube tunnel             # separate terminal: gives LoadBalancer services a real IP
kubectl get nodes
```

> ⚠️ **The #1 minikube gotcha:** same image problem. Fix: `eval $(minikube docker-env)` **before** `docker build` so the image lands inside minikube's daemon — or `minikube image load myapp:1.0`.

#### 0.3 Verify everything works

```bash
kubectl get nodes -o wide
kubectl get pods -A                       # kube-system pods should be Running
kubectl run test --image=busybox:1.37 --restart=Never -- sleep 30
kubectl get pod test                      # Running
kubectl delete pod test
```

If `kubectl get nodes` says `The connection to the server localhost:8080 was refused`, your kubeconfig is missing → run `kind export kubeconfig --name learn` or `minikube update-context`.

### 0.4 Install the tools you'll actually use daily

```bash
# k9s — terminal UI, the single best quality-of-life install
brew install k9s                 # or download from github.com/derailed/k9s/releases
k9s                              # type :pods, :deploy, :svc; ? for help

# helm
brew install helm                # or: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# stern — multi-pod log tailing (kubectl logs can only do one container at a time)
brew install stern

# kubectx / kubens — instant context & namespace switching
brew install kubectx             # gives you `kubectx` and `kubens`

# kubectl plugins that pay for themselves
kubectl krew install ctx ns resources tree get-all
```

Set up a shell alias so you stop typing `kubectl`:

```bash
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc   # bash completion for the alias
source ~/.bashrc
```

---

## §1 — What Kubernetes actually is

### 1.1 The one-sentence definition

> **Kubernetes is a control loop that keeps the real state of your system equal to the state you declared.**

That's it. Everything else is detail. You write "I want 3 copies of this app, each with 256 MB, behind this hostname." Kubernetes continuously compares *desired* vs *actual* and fixes the difference — forever, without being asked.

### 1.2 Docker vs Kubernetes — the honest comparison

| | Docker (single host) | Kubernetes (cluster) |
|---|---|---|
| Unit of scheduling | Container | **Pod** (1+ containers that share network & storage) |
| "Keep it alive" | `--restart=always` (that one host) | Controllers reconcile across N nodes |
| Scaling | `docker compose up --scale web=3` (one host, manual) | `kubectl scale --replicas=30` (cluster-wide, automatic with HPA) |
| Service discovery | Docker DNS on a user network | CoreDNS + Service objects, cluster-wide |
| Load balancing | Docker's round-robin over a network | kube-proxy rules + Service + Ingress |
| Config | `-e`, `--env-file` | ConfigMap, Secret, downward API |
| Storage | `-v`, named volumes | PV / PVC / StorageClass (network-attached, survives nodes) |
| Health | `HEALTHCHECK` (informational only) | Liveness / readiness / startup probes (**drive restarts and traffic**) |
| Updates | Rebuild + restart, downtime | Rolling update, zero downtime, `kubectl rollout undo` |
| Multi-host | Swarm (limited) | Native, the whole point |
| Self-healing | Restart the container | Reschedule the Pod on a *different node*, replace PVC-backed state, evict under pressure |

**Key mental shift:** with Docker you *run commands*. With Kubernetes you *declare state* and the system converges on it. You almost never say "start this container" — you say "3 of these should exist" and Kubernetes figures out the how.

### 1.3 Imperative vs declarative

```bash
# IMPERATIVE — quick, great for learning & throwaway tests
kubectl create deployment web --image=nginx:1.29-alpine
kubectl expose deployment web --port=80 --type=NodePort
kubectl scale deployment web --replicas=3

# DECLARATIVE — what production uses; the file IS the source of truth
kubectl apply -f deployment.yaml
```

| | `create` | `apply` |
|---|---|---|
| Object exists already? | ❌ Error: AlreadyExists | ✅ Updates it |
| Re-runnable? | No | Yes (idempotent) |
| Tracks last-applied config? | No | Yes (`kubectl.kubernetes.io/last-applied-configuration`) |
| Use for | Experiments, scripts | **Everything in Git** |

> **Rule:** use imperative commands to *learn* and to *generate YAML*, then switch to `apply` forever.
> `kubectl create deployment web --image=nginx --dry-run=client -o yaml > deploy.yaml` is the bridge between the two worlds.

### 1.4 The reconciliation loop (understand this and you understand K8s)

```
   You                API Server              Controller              kubelet              Container
    │  kubectl apply      │                        │                      │                     │
    ├────────────────────>│  store desired state   │                      │                     │
    │                     │  in etcd               │                      │                     │
    │                     │<──── watch ────────────┤                      │                     │
    │                     │                        │ actual(2) != want(3) │                     │
    │                     │                        ├── create ReplicaSet ─>│                     │
    │                     │                        │                      ├── pull image ──────>│
    │                     │                        │                      │                     │ run
    │                     │<───── status ──────────┴──────────────────────┤                     │
```

Every controller does the same thing: **watch → diff → act → repeat**. That's why:

- Deleting a Pod managed by a Deployment makes a *new* Pod appear (the Deployment controller sees actual < desired).
- `kubectl delete pod` on a **bare** Pod makes it gone forever (nothing is watching it).
- Killing a node's kubelet makes those Pods get rescheduled elsewhere after ~40 s (node controller marks it `NotReady`, then evicts).

**Interview answer:** *"Kubernetes is declarative and level-triggered, not edge-triggered. Controllers don't react to events so much as continuously compare desired state in etcd with observed state and act on the difference. That's why missing an event isn't fatal — the next sync fixes it."*

---

## §2 — Cluster architecture (the parts and what they do)

```
┌──────────────────── CONTROL PLANE ────────────────────┐      ┌──────── WORKER NODE(S) ────────┐
│                                                       │      │                                │
│  kube-apiserver ◄──── everything talks to this ────►  │      │   kubelet  ── talks to CRI     │
│      │  (REST, authn, authz, admission, validation)   │      │      │        (containerd)     │
│      ▼                                                │      │      ▼                         │
│    etcd   (the ONLY stateful part; Raft; quorum)      │      │   Pods → containers            │
│      ▲                                                │      │      ▲                         │
│      │                                                │      │      │                         │
│  kube-scheduler      (which node? filtering+scoring)  │      │   kube-proxy                   │
│  kube-controller-mgr (deployment, rs, node, job,      │      │   (Service VIP → Pod IP rules; │
│                       endpoints, namespace…)          │      │    iptables or nftables)       │
│  cloud-controller-mgr (LB, routes, nodes — cloud only)│      │   CoreDNS Pod (cluster DNS)    │
└───────────────────────────────────────────────────────┘      │   CNI plugin (pod networking)  │
                                                               │   CSI plugin (volumes)         │
                                                               └────────────────────────────────┘
```

### 2.1 Control plane components

| Component | Job | If it dies |
|---|---|---|
| **kube-apiserver** | The *only* thing that reads/writes etcd. REST API. Handles authn → authz → admission → validation. Horizontal-scalable, stateless. | Nothing can be created or changed; running Pods keep running |
| **etcd** | Distributed key-value store. All cluster state. Raft consensus; needs odd numbers (3 or 5) for HA. | Total loss of cluster state → cluster is dead. **Back this up.** |
| **kube-scheduler** | Watches for Pods with no `nodeName`, filters feasible nodes, scores them, binds the winner. | New Pods stay `Pending` forever |
| **kube-controller-manager** | Runs ~40 controllers (Deployment, ReplicaSet, Node, Job, EndpointSlice, Namespace, ServiceAccount…). Each is a reconcile loop. | No self-healing, no scaling, no rollout |
| **cloud-controller-manager** | Cloud-specific: LoadBalancers, routes, node lifecycle. Absent in kind/minikube. | `type: LoadBalancer` stuck `<pending>` (this is *normal* locally) |

### 2.2 Node components

| Component | Job | Notes |
|---|---|---|
| **kubelet** | Agent on every node. Receives PodSpecs, talks to the container runtime via **CRI**, runs probes, reports node/Pod status. | The only component that *actually* starts containers |
| **Container runtime** | containerd (default), CRI-O. Docker Engine is **not** supported directly since v1.24 (dockershim removed) — but Docker-built images work fine (OCI standard). | `crictl` is the debugging CLI, not `docker` |
| **kube-proxy** | Maintains the rules that make Service ClusterIPs work. Modes: `iptables` (default historically), `nftables` (default from v1.33+), `ipvs` (large clusters). | It does **not** proxy traffic itself — it writes kernel rules |
| **CNI plugin** | Pod-to-pod networking, IP allocation. Calico, Cilium, Flannel, Weave. | Cilium uses eBPF and can replace kube-proxy entirely |
| **CSI driver** | Attaches/mounts volumes. EBS, PD, Ceph, NFS, local-path. | |

### 2.3 Add-ons (not part of core, but you'll always have them)

CoreDNS (cluster DNS — mandatory in practice), Ingress controller, metrics-server (needed for `kubectl top` and HPA), Dashboard, CNI.

### 2.4 Where your YAML goes

```
kubectl apply -f x.yaml
   → kube-apiserver
       1. Authentication      (who are you? cert / token / OIDC)
       2. Authorization       (RBAC: are you allowed?)
       3. Admission control   (mutating webhooks → e.g. Istio sidecar injection, default SA
                               validating webhooks → e.g. OPA Gatekeeper, Pod Security Admission)
       4. Schema validation
       5. Write to etcd       ← at this point `kubectl get` shows it
   → controller sees it → creates Pod object
   → scheduler binds Pod to node
   → kubelet on that node pulls image, creates containers via containerd
   → kube-proxy / CoreDNS update so traffic can reach it
```

**This ordering explains most "weird" behaviour:** an object can exist in etcd and be visible via `kubectl get` while being completely impossible to run (e.g. references a nonexistent Secret → `CreateContainerConfigError`).

---

## §3 — Anatomy of every Kubernetes object

Every object has the same four top-level keys. Memorise this skeleton — 90% of all YAML you write is this:

```yaml
apiVersion: apps/v1          # WHICH API group + version this schema comes from
kind: Deployment             # WHAT type of object
metadata:                    # identity
  name: web                  #   unique within (namespace, kind)
  namespace: prod            #   defaults to "default" if omitted
  labels:                    #   key=value pairs used for SELECTION (grouping)
    app: web
    tier: frontend
    version: v1
  annotations:               #   free-form text for humans & tools (NOT used for selection)
    description: "Public web tier"
spec:                        # DESIRED STATE — you write this
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:                  #   the Pod template
    metadata:
      labels:
        app: web             #   ⚠️ MUST satisfy spec.selector
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports:
            - containerPort: 80
status:                      # ACTUAL STATE — Kubernetes writes this, you never do
  readyReplicas: 3
  availableReplicas: 3
```

### 3.1 `apiVersion` cheat table

| apiVersion | Kinds | Status |
|---|---|---|
| `v1` (core) | Pod, Service, ConfigMap, Secret, PersistentVolume, PersistentVolumeClaim, Namespace, ServiceAccount, Node | Stable |
| `apps/v1` | Deployment, StatefulSet, DaemonSet, ReplicaSet | Stable |
| `batch/v1` | Job, CronJob | Stable |
| `networking.k8s.io/v1` | Ingress, IngressClass, NetworkPolicy | Stable |
| `autoscaling/v2` | HorizontalPodAutoscaler | Stable (**not** `autoscaling/v1`, that only supports CPU) |
| `policy/v1` | PodDisruptionBudget | Stable |
| `rbac.authorization.k8s.io/v1` | Role, ClusterRole, RoleBinding, ClusterRoleBinding | Stable |
| `storage.k8s.io/v1` | StorageClass, CSIDriver, VolumeAttachment | Stable |
| `scheduling.k8s.io/v1` | PriorityClass | Stable |
| `admissionregistration.k8s.io/v1` | MutatingWebhookConfiguration, ValidatingWebhookConfiguration | Stable |
| `apiextensions.k8s.io/v1` | CustomResourceDefinition | Stable |
| `metrics.k8s.io/v1beta1` | PodMetrics, NodeMetrics (from metrics-server) | Stable in **v1.37** |
| `gateway.networking.k8s.io/v1` | Gateway, HTTPRoute | The Ingress successor |
| `resource.k8s.io/v1beta1` | ResourceClaim, DeviceClass (DRA — GPUs) | Rising fast |

> ⚠️ **Removed and will fail:** `extensions/v1beta1` Ingress, `apps/v1beta1`, `apps/v1beta2`, `autoscaling/v2beta2`, `policy/v1beta1` PodDisruptionBudget, and **PodSecurityPolicy (removed in v1.25)**. If you copy YAML from a pre-2021 tutorial it will not apply. Replace PSP with **Pod Security Admission** (§11.5).

Discover what your cluster supports:

```bash
kubectl api-versions                       # all group/versions
kubectl api-resources                      # all kinds, namespaced or not, short names
kubectl api-resources --namespaced=true -o wide
kubectl explain deployment.spec.strategy   # built-in docs — USE THIS, it's excellent
kubectl explain pod.spec.containers.resources --recursive
```

### 3.2 Labels vs annotations vs names

| | Purpose | Selectable? | Example |
|---|---|---|---|
| `metadata.name` | Unique identity | — | `web-7d9f8b` |
| `metadata.labels` | **Grouping & selection** — how Services find Pods, how you filter | ✅ `-l app=web` | `app=web,tier=fe,env=prod` |
| `metadata.annotations` | Metadata for tools/humans, can be long, can hold JSON | ❌ | `prometheus.io/scrape: "true"` |

**Label rules:** ≤63 chars, alphanumeric with `-_.`, must start/end alphanumeric. Keys may have a DNS prefix: `example.com/team=payments`.

**Recommended standard labels** (used by Helm and most tooling):

```yaml
labels:
  app.kubernetes.io/name: web
  app.kubernetes.io/instance: web-prod
  app.kubernetes.io/version: "1.29.0"
  app.kubernetes.io/component: frontend
  app.kubernetes.io/part-of: shop
  app.kubernetes.io/managed-by: Helm
```

> 🔑 **The single most common beginner bug:** `spec.selector.matchLabels` in the Deployment does **not** match `spec.template.metadata.labels` on the Pod. Kubernetes refuses with:
> `selector does not match template labels`. The selector is *immutable* after creation — to change it you must delete and recreate the Deployment.

### 3.3 Namespaces

Logical partitions inside one cluster. Not security boundaries by themselves (RBAC + NetworkPolicy make them that).

```bash
kubectl get namespaces
# NAME              STATUS   AGE
# default           Active   1d    <- your stuff lands here if you don't say otherwise
# kube-system       Active   1d    <- control plane & addons; DON'T touch
# kube-public       Active   1d
# kube-node-lease   Active   1d    <- node heartbeat Lease objects
```

```bash
kubectl create namespace dev
kubectl get pods -n dev
kubectl get pods -A                       # or --all-namespaces
kubectl config set-context --current --namespace=dev   # make it your default (kubens dev does this)
kubectl delete namespace dev              # ⚠️ deletes EVERYTHING inside, no confirmation
```

Namespace stuck in `Terminating`? Almost always a finalizer on some object, or a dead API service:

```bash
kubectl api-services | grep False         # find broken aggregated APIs
kubectl get all -n stuck-ns               # what's left
kubectl patch ns stuck-ns -p '{"spec":{"finalizers":null}}' --type=merge   # last resort
```

---

## §4 — Pods: the atomic unit

### 4.1 What a Pod is

> A **Pod** is one or more containers that share a **network namespace** (same IP, same ports, `localhost` between them) and can share **volumes**. It is the smallest thing Kubernetes schedules.

Docker has no equivalent. The closest is `docker run --network container:other` plus shared volume mounts.

**95% of Pods have exactly one container.** Use multi-container Pods only for these four recognised patterns:

| Pattern | Second container's job | Example |
|---|---|---|
| **Sidecar** | Augments the main app | Log shipper, Envoy proxy (Istio), config reloader |
| **Ambassador** | Proxies outbound traffic | Local Postgres proxy, retry/circuit-breaker |
| **Adapter** | Normalises output | App → Prometheus-format exporter |
| **Init container** | Runs to completion *before* the app | DB migration, wait-for-dependency, permission fix |

Since **v1.29** (stable **v1.33**) there are *native sidecars*: an init container with `restartPolicy: Always`. It starts before main containers, keeps running, and terminates last — which fixes the classic "my log shipper dies before flushing" problem.

```yaml
spec:
  initContainers:
    - name: log-shipper          # native sidecar
      image: fluent/fluent-bit:3.1
      restartPolicy: Always      # ← THIS line is what makes it a sidecar
      volumeMounts: [{name: logs, mountPath: /var/log/app}]
  containers:
    - name: app
      image: myapp:1.0
      volumeMounts: [{name: logs, mountPath: /var/log/app}]
```

### 4.2 Your first Pod

```yaml
# pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello
  labels:
    app: hello
spec:
  containers:
    - name: hello
      image: nginx:1.29-alpine
      ports:
        - containerPort: 80
```

```bash
kubectl apply -f pod.yaml
kubectl get pods                      # NAME   READY  STATUS   RESTARTS  AGE
kubectl get pod hello -o wide         # adds IP and NODE
kubectl describe pod hello            # events at the bottom — ALWAYS look here
kubectl logs hello                    # stdout of the container
kubectl logs hello -f                 # follow
kubectl exec -it hello -- sh          # shell inside (no bash in alpine!)
kubectl port-forward pod/hello 8080:80
curl localhost:8080
kubectl delete pod hello              # gone forever — nothing recreates it
```

> ⚠️ **Never run bare Pods in production.** No self-healing, no scaling, no rolling updates. A bare Pod on a dying node is a Pod that is simply lost. Use a Deployment (§5).

### 4.3 Pod lifecycle — the states you'll see

```
Pending ──► Running ──► Succeeded
   │            │            
   │            └──────► Failed
   └──► (stuck: Unschedulable / ImagePullBackOff / CreateContainerConfigError)
```

| `STATUS` you see | Actually means | First command to run |
|---|---|---|
| `Pending` | Accepted, but no container running yet — scheduling or image pull | `kubectl describe pod` → look at Events |
| `ContainerCreating` | kubelet is pulling/mounting | `describe` → usually a volume or image issue |
| `Running` | At least one container started | `kubectl logs` |
| `Succeeded` | All containers exited 0 (Jobs) | normal |
| `Failed` | All containers terminated, ≥1 failed | `kubectl logs --previous` |
| `CrashLoopBackOff` | Container keeps dying; kubelet is backing off (10s → 20s → … → 5 min) | `kubectl logs --previous` + `describe` → Last State |
| `ImagePullBackOff` / `ErrImagePull` | Image not found, wrong tag, private registry without `imagePullSecrets` | `describe` → exact error message |
| `CreateContainerConfigError` | References a ConfigMap/Secret/key that doesn't exist | `describe`; then `kubectl get cm,secret` |
| `Evicted` | Node ran out of memory or disk; kubelet killed it | `kubectl describe node` → Conditions |
| `OOMKilled` (in Last State) | Container exceeded its memory limit | `describe pod` → `Reason: OOMKilled`, exit 137 |
| `Terminating` (stuck) | Finalizer blocking, or app ignoring SIGTERM | `kubectl get pod -o yaml | grep finalizers` |
| `Unknown` | kubelet stopped reporting | check the node |

### 4.4 Pod phases vs container states (people conflate these)

- **Pod `.status.phase`**: `Pending | Running | Succeeded | Failed | Unknown` — a coarse summary.
- **Container state**: `Waiting{reason} | Running{startedAt} | Terminated{exitCode,reason}` — the detail you actually debug with.

`READY 0/1` with `STATUS Running` means: the container is running but the **readiness probe is failing** → it gets no traffic. That's not a crash; that's Kubernetes correctly withholding traffic. See §9.

### 4.5 Static Pods

Managed directly by a kubelet via files in `/etc/kubernetes/manifests` — no API server involved. This is how kubeadm runs the control plane. You'll see them named `kube-apiserver-<node>` in `kube-system`. You can't `kubectl delete` them (they come back); you delete the file.

### 4.6 Pod fields you'll use constantly

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: full
spec:
  restartPolicy: Always            # Always | OnFailure | Never  (Jobs use OnFailure/Never)
  serviceAccountName: my-sa        # identity for API calls (§11)
  terminationGracePeriodSeconds: 30   # SIGTERM → wait → SIGKILL
  securityContext:                 # Pod-level
    runAsNonRoot: true
    runAsUser: 10001
    fsGroup: 2000                  # group ownership applied to mounted volumes
    seccompProfile: {type: RuntimeDefault}
  nodeSelector: {disktype: ssd}    # simplest scheduling constraint
  tolerations:
    - {key: "gpu", operator: "Equal", value: "true", effect: "NoSchedule"}
  initContainers:
    - name: wait-db
      image: busybox:1.37
      command: ['sh','-c','until nc -z db 5432; do echo waiting; sleep 2; done']
  containers:
    - name: app
      image: myapp:1.2.3
      imagePullPolicy: IfNotPresent   # Always | IfNotPresent | Never
      command: ["/bin/app"]           # overrides Docker ENTRYPOINT
      args: ["--port=8080"]           # overrides Docker CMD
      workingDir: /srv
      ports:
        - {name: http, containerPort: 8080, protocol: TCP}
      env:
        - {name: LOG_LEVEL, value: "debug"}
        - name: DB_PASSWORD
          valueFrom: {secretKeyRef: {name: db-creds, key: password}}
        - name: MY_POD_IP
          valueFrom: {fieldRef: {fieldPath: status.podIP}}     # downward API
      envFrom:
        - configMapRef: {name: app-config}
        - secretRef: {name: app-secrets}
      resources:
        requests: {cpu: "100m", memory: "128Mi"}    # scheduling guarantee
        limits:   {cpu: "500m", memory: "256Mi"}    # hard ceiling
      livenessProbe:  {httpGet: {path: /healthz, port: http}, initialDelaySeconds: 15, periodSeconds: 20}
      readinessProbe: {httpGet: {path: /ready,   port: http}, periodSeconds: 5,  failureThreshold: 3}
      startupProbe:   {httpGet: {path: /healthz, port: http}, failureThreshold: 30, periodSeconds: 5}
      lifecycle:
        postStart: {exec: {command: ["/bin/sh","-c","echo started > /tmp/ok"]}}
        preStop:   {exec: {command: ["/bin/sh","-c","sleep 5"]}}   # drain traffic before dying
      volumeMounts:
        - {name: data, mountPath: /data}
        - {name: config, mountPath: /etc/app, readOnly: true}
      securityContext:               # container-level (overrides Pod-level)
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: ["ALL"]}
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: app-data}
    - name: config
      configMap: {name: app-config}
    - name: tmp
      emptyDir: {}
```

> 🔑 **`command` / `args` vs Docker:**
> | Dockerfile | Pod spec | Effect |
> |---|---|---|
> | neither set | neither set | image `ENTRYPOINT` + `CMD` |
> | — | `args` only | image `ENTRYPOINT` + your `args` |
> | — | `command` only | your `command`, image `CMD` ignored |
> | — | both | your `command` + your `args` (image fully ignored) |

### 4.7 Everything you can do with a running Pod

```bash
kubectl get pods -o wide
kubectl describe pod hello
kubectl logs hello                          # single container
kubectl logs hello -c sidecar               # pick a container
kubectl logs hello --previous               # THE crash-debugging command
kubectl logs hello -f --tail=50 --timestamps
kubectl logs -l app=hello --all-containers --prefix   # by label
kubectl exec -it hello -- sh
kubectl exec hello -- cat /etc/nginx/nginx.conf       # one-shot command
kubectl cp hello:/var/log/app.log ./app.log           # tar must exist in the image
kubectl port-forward pod/hello 8080:80
kubectl attach -it hello                    # attach to PID 1's stdio
kubectl top pod hello                       # needs metrics-server
kubectl get pod hello -o yaml
kubectl get pod hello -o jsonpath='{.status.containerStatuses[0].state}'
kubectl debug -it hello --image=busybox:1.37 --target=app    # ephemeral debug container
kubectl delete pod hello --grace-period=0 --force            # last resort only
```

---

## §5 — Workloads

### 5.1 Which workload do I use? (decision table)

| Your workload is… | Use | Why |
|---|---|---|
| Stateless app, need N replicas, rolling updates | **Deployment** | The default. 90% of cases. |
| Stateful, needs stable identity + ordered start + per-Pod storage | **StatefulSet** | Databases, Kafka, Elasticsearch |
| One per node, cluster infrastructure | **DaemonSet** | Log agents, node exporters, CNI, CSI |
| Run once to completion | **Job** | Migrations, batch processing, backfills |
| Run on a schedule | **CronJob** | Nightly backups, reports, cleanup |
| A single throwaway thing | **bare Pod** | Debugging only. Never production. |

### 5.2 Deployment

A Deployment manages **ReplicaSets**; a ReplicaSet manages **Pods**. You only ever touch the Deployment.

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: {app: web}
spec:
  replicas: 3
  revisionHistoryLimit: 5            # how many old ReplicaSets to keep for rollback
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                    # how many EXTRA pods during update (count or %)
      maxUnavailable: 0              # how many may be UNAVAILABLE — 0 = zero downtime
  selector:
    matchLabels: {app: web}          # ⚠️ immutable; must match template labels
  template:
    metadata:
      labels: {app: web}
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{containerPort: 80, name: http}]
          resources:
            requests: {cpu: 50m,  memory: 64Mi}
            limits:   {cpu: 200m, memory: 128Mi}
          readinessProbe:
            httpGet: {path: /, port: http}
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet: {path: /, port: http}
            initialDelaySeconds: 15
            periodSeconds: 20
```

```bash
kubectl apply -f deployment.yaml
kubectl get deploy,rs,pods -l app=web          # see all three layers
kubectl rollout status deployment/web          # blocks until done — use in CI
kubectl rollout history deployment/web
kubectl scale deployment/web --replicas=6
kubectl set image deployment/web web=nginx:1.29-alpine   # triggers a rollout
kubectl rollout undo deployment/web                       # previous revision
kubectl rollout undo deployment/web --to-revision=2
kubectl rollout restart deployment/web                    # recycle all pods (no spec change)
kubectl rollout pause deployment/web && kubectl rollout resume deployment/web
kubectl annotate deployment/web kubernetes.io/change-cause="bump to 1.29" # shows in history
kubectl edit deployment/web                               # live edit (don't do this in prod)
kubectl patch deployment/web --type=merge -p '{"spec":{"replicas":5}}'
```

**How a rolling update actually proceeds** (`maxSurge: 1`, `maxUnavailable: 0`, 3 replicas):

```
t0: RS-old=3, RS-new=0        (3 available)
t1: RS-old=3, RS-new=1        (new pod starts, readiness probe passes)   4 available
t2: RS-old=2, RS-new=1        (one old pod terminated)                   3 available
t3: RS-old=2, RS-new=2                                                   4 available
t4: RS-old=1, RS-new=2                                                   3 available
...  until RS-old=0, RS-new=3
```

> 🔑 **Zero downtime requires a working readiness probe.** Without one, Kubernetes considers a Pod "ready" the instant the container *starts* — before your app has bound its port — and kills the old Pod too early. This is the #1 cause of "our rolling update causes 502s".

**Recreate strategy** (for apps that cannot run two versions at once, e.g. single-writer DB tools):

```yaml
strategy:
  type: Recreate        # kills all old pods, THEN starts new ones → downtime
```

### 5.3 ReplicaSet

Created by the Deployment. Don't manage it directly, but *do* understand it, because it's what `kubectl rollout undo` swaps.

```bash
kubectl get rs -o wide      # DESIRED  CURRENT  READY  AGE  CONTAINERS  IMAGES  SELECTOR
```

Each rollout creates a **new** ReplicaSet with a `pod-template-hash` label. Old ones are scaled to 0 but kept (`revisionHistoryLimit`) for rollback.

### 5.4 StatefulSet

For anything with identity or state. Three guarantees Deployments don't give you:

1. **Stable network identity:** Pods are `web-0`, `web-1`, `web-2` — never random hashes. Recreated with the same name.
2. **Stable storage:** each Pod gets its *own* PVC from `volumeClaimTemplates`, and keeps it across rescheduling.
3. **Ordered, graceful deployment & scaling:** `0 → 1 → 2` on the way up, `2 → 1 → 0` on the way down.

```yaml
apiVersion: v1
kind: Service                     # HEADLESS service (clusterIP: None) — required
metadata: {name: db, labels: {app: db}}
spec:
  clusterIP: None                 # ← this makes it headless: DNS returns POD IPs
  selector: {app: db}
  ports: [{name: pg, port: 5432}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: db}
spec:
  serviceName: db                 # ← must point at the headless Service above
  replicas: 3
  podManagementPolicy: OrderedReady   # or Parallel (faster, loses ordering)
  updateStrategy:
    type: RollingUpdate
    rollingUpdate: {partition: 0}     # canary: set to 2 → only pods ≥2 update
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: postgres
          image: postgres:17-alpine
          ports: [{containerPort: 5432, name: pg}]
          env:
            - {name: POSTGRES_PASSWORD, valueFrom: {secretKeyRef: {name: pg, key: password}}}
          volumeMounts: [{name: data, mountPath: /var/lib/postgresql/data}]
  volumeClaimTemplates:               # ← one PVC PER POD, auto-created
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: {requests: {storage: 10Gi}}
```

Resulting DNS names (this is the magic):

```
db-0.db.<namespace>.svc.cluster.local   → Pod IP of db-0
db-1.db.<namespace>.svc.cluster.local   → Pod IP of db-1
db.<namespace>.svc.cluster.local        → all Pod IPs (round-robin)
```

```bash
kubectl get statefulset,pvc,pods -l app=db
kubectl delete statefulset db                       # ⚠️ PVCs SURVIVE (by design)
kubectl delete statefulset db --cascade=foreground
kubectl delete pvc -l app=db                        # ← only THIS frees the storage
```

> ⚠️ **Deleting a StatefulSet does not delete its PVCs.** That's intentional (data safety) and it's why people run out of cloud disks. Delete PVCs explicitly when you really mean it.

### 5.5 DaemonSet

Exactly one Pod per (matching) node — including nodes added later.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: node-exporter, namespace: monitoring}
spec:
  selector: {matchLabels: {app: node-exporter}}
  template:
    metadata: {labels: {app: node-exporter}}
    spec:
      hostNetwork: true                     # common for node-level agents
      hostPID: true
      tolerations:                          # run on control-plane nodes too
        - {key: node-role.kubernetes.io/control-plane, effect: NoSchedule}
      containers:
        - name: node-exporter
          image: quay.io/prometheus/node-exporter:v1.9.1
          args: ["--path.rootfs=/host"]
          ports: [{containerPort: 9100, name: metrics}]
          volumeMounts:
            - {name: rootfs, mountPath: /host, readOnly: true}
      volumes:
        - name: rootfs
          hostPath: {path: /}
```

Uses: log shippers (Fluent Bit), metrics agents (node-exporter), CNI/CSI plugins, security scanners. `kubectl get ds -o wide` shows `DESIRED / CURRENT / READY / UP-TO-DATE / AVAILABLE / NODE SELECTOR`.

> 🔑 DaemonSet Pods are scheduled by the **DaemonSet controller setting `nodeName` directly** (bypassing the default scheduler) in older versions, and via the scheduler with a high-priority toleration now. Either way they ignore most scheduling constraints and tolerate all taints you list.

### 5.6 Job

```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: migrate}
spec:
  backoffLimit: 3                     # retries before marking the Job Failed
  activeDeadlineSeconds: 600          # hard timeout
  ttlSecondsAfterFinished: 300        # auto-cleanup 5 min after success/failure
  completions: 1                      # how many successful runs are needed
  parallelism: 1                      # how many run at once
  template:
    spec:
      restartPolicy: Never            # ⚠️ ONLY Never or OnFailure are valid in a Job
      containers:
        - name: migrate
          image: myapp:1.2.3
          command: ["python", "manage.py", "migrate"]
```

**Work-queue pattern** (N workers pulling from a queue until it's empty):

```yaml
spec:
  completions: 100          # need 100 successes
  parallelism: 10           # 10 at a time
  completionMode: Indexed   # each pod gets JOB_COMPLETION_INDEX=0..99
```

```bash
kubectl create job hello --image=busybox:1.37 -- echo done       # imperative
kubectl get jobs
kubectl wait --for=condition=complete job/migrate --timeout=300s # CI-friendly
kubectl logs job/migrate
kubectl delete job migrate
```

### 5.7 CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: {name: nightly-backup}
spec:
  schedule: "30 2 * * *"              # ⚠️ UTC, not your local timezone. 5 fields, no seconds.
  timeZone: "Asia/Kolkata"            # supported from v1.27 — use it!
  concurrencyPolicy: Forbid           # Allow | Forbid | Replace
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  startingDeadlineSeconds: 300        # skip the run if the controller was down longer than this
  suspend: false                      # true = pause without deleting
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 1800
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: postgres:17-alpine
              command: ["/bin/sh","-c"]
              args:
                - |
                  pg_dump -h db -U postgres app | gzip > /backups/app-$(date +%F).sql.gz
                  ls -lh /backups
              env:
                - {name: PGPASSWORD, valueFrom: {secretKeyRef: {name: pg, key: password}}}
              volumeMounts: [{name: backups, mountPath: /backups}]
          volumes:
            - name: backups
              persistentVolumeClaim: {claimName: db-backups}
```

Cron syntax refresher: `┌ minute (0-59) ┌ hour (0-23) ┌ day-of-month (1-31) ┌ month (1-12) ┌ day-of-week (0-6, Sun=0)`

| Schedule | Meaning |
|---|---|
| `*/5 * * * *` | every 5 minutes |
| `0 * * * *` | top of every hour |
| `30 2 * * *` | 02:30 daily |
| `0 9 * * 1-5` | 09:00 weekdays |
| `0 0 1 * *` | midnight, 1st of month |

```bash
kubectl get cronjobs
kubectl create cronjob ping --image=busybox:1.37 --schedule="*/1 * * * *" -- echo hi
kubectl create job --from=cronjob/nightly-backup manual-run-1   # ← run it NOW, on demand
kubectl logs job/<generated-job-name>
kubectl patch cronjob nightly-backup -p '{"spec":{"suspend":true}}'
```

> ⚠️ **CronJob names must be ≤52 characters**, because generated Job names append an 11-char suffix.

### 5.8 Bare Pod / ReplicaSet / Deployment relationships

```
Deployment  ──owns──►  ReplicaSet  ──owns──►  Pod
   │                       │                   │
   │ .spec (template)      │ .spec (template)  │ .spec (containers)
   │                       │                   │
   └── rollout history     └── pod-template-hash label
```

Verify with `ownerReferences`:

```bash
kubectl get pod web-abc123 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
# ReplicaSet/web-7d9f8b6c5d
kubectl get rs web-7d9f8b6c5d -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
# Deployment/web
```

Garbage collection follows these references. Deleting a Deployment cascades to its ReplicaSets and Pods.

---

## §6 — Services & networking

### 6.1 The problem Services solve

Pod IPs are **ephemeral**. Every reschedule gives a new IP. You cannot hardcode them. A **Service** gives you a stable virtual IP (ClusterIP) and DNS name that load-balances to whatever Pods currently match its selector.

### 6.2 The four Service types

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP                 # ← the type
  selector:
    app: web                      # matches POD labels
  ports:
    - name: http
      port: 80                    # the Service's own port (what clients connect to)
      targetPort: http            # the CONTAINER's port (name or number)
      protocol: TCP
      # nodePort: 30080           # only for NodePort/LoadBalancer; range 30000-32767
```

| Type | Reachable from | Typical use |
|---|---|---|
| **ClusterIP** (default) | Inside the cluster only | Internal microservice-to-microservice |
| **NodePort** | `<any-node-IP>:30000-32767` | Local dev, quick tests, behind an external LB |
| **LoadBalancer** | Public cloud LB IP | One cloud LB per Service — expensive; usually replaced by Ingress |
| **ExternalName** | CNAME to an external DNS name | Pointing in-cluster code at an external DB |
| *(headless)* `clusterIP: None` | Returns **Pod IPs** directly from DNS | StatefulSets, client-side LB, service discovery |

**How the ports relate:**

```
client ──► Service IP : port (80) ──► kube-proxy rules ──► Pod IP : targetPort (8080)
                                                            ▲
                                    NodePort (30080) also maps to port (80)
```

```bash
kubectl get svc
kubectl expose deployment web --port=80 --target-port=8080 --type=ClusterIP
kubectl describe svc web          # shows Endpoints / Selector / Session Affinity
kubectl get endpointslices -l kubernetes.io/service-name=web
```

> 🔑 **`Endpoints`/`EndpointSlice` empty?** Your Service selector does not match any *ready* Pod labels. This is the single most common networking bug.
> ```bash
> kubectl get svc web -o jsonpath='{.spec.selector}'
> kubectl get pods --show-labels
> kubectl get endpointslices -l kubernetes.io/service-name=web    # empty = mismatch or pods not Ready
> ```

### 6.3 DNS — how services find each other

CoreDNS gives every Service a name:

```
<service>.<namespace>.svc.cluster.local
```

| You are in… | You can call it as |
|---|---|
| Same namespace | `web`, `web:80` |
| Different namespace | `web.payments`, `web.payments.svc.cluster.local` |
| Headless Service | `db-0.db.default.svc.cluster.local` (per-Pod) |
| A Pod's `/etc/resolv.conf` | has `search default.svc.cluster.local svc.cluster.local cluster.local` — that's why the short name works |

```bash
kubectl run dns-test --rm -it --image=busybox:1.37 --restart=Never -- sh
# inside:
nslookup kubernetes.default            # the API server's own Service
nslookup web
cat /etc/resolv.conf
wget -qO- http://web/
```

If DNS fails inside Pods but the cluster is otherwise fine → CoreDNS is broken:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

### 6.4 Pod networking model — the three rules

1. Every Pod gets its **own IP** (from the CNI plugin's range).
2. **All Pods can talk to all other Pods directly**, across nodes, without NAT.
3. Nodes can talk to all Pods.

That's the whole contract. CNI plugins implement it (Calico BGP, Cilium eBPF, Flannel VXLAN, cloud VPC CNI).

```
Node A (10.0.0.1)                        Node B (10.0.0.2)
┌──────────────────────┐                 ┌──────────────────────┐
│ Pod web-1  10.244.1.5│◄──── CNI ──────►│ Pod api-1  10.244.2.9│
│ Pod web-2  10.244.1.6│   tunnel/route  │ Pod api-2  10.244.2.10│
└──────────────────────┘                 └──────────────────────┘
```

### 6.5 Getting traffic from your laptop to a Pod

| Method | Command | When |
|---|---|---|
| **port-forward** | `kubectl port-forward svc/web 8080:80` | Debugging. Single connection, no LB, dies with your terminal. |
| **NodePort** | `curl $(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):30080` | kind/minikube quick tests |
| **minikube service** | `minikube service web --url` | minikube only |
| **kind extraPortMappings** | pre-mapped `localhost:8080` | kind + Ingress |
| **Ingress** | `curl -H "Host: shop.local" http://localhost:8080` | The real answer |
| **LoadBalancer** | `kubectl get svc web` → EXTERNAL-IP | Real cloud |

> ⚠️ `port-forward` is **not** a load balancer. It opens one TCP tunnel to *one* Pod. Long-lived connections, gRPC streams, and high throughput behave oddly. Never use it in production paths.

### 6.6 Session affinity

```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP: {timeoutSeconds: 3600}
```

Rarely the right answer — fix your app to be stateless (shared session store) instead.

---

## §7 — Configuration: ConfigMaps & Secrets

### 7.1 ConfigMap

Non-sensitive key/value config, or whole files.

```bash
# from literals
kubectl create configmap app-config \
  --from-literal=LOG_LEVEL=debug \
  --from-literal=FEATURE_FLAGS=beta,dark

# from a file (key = filename by default)
kubectl create configmap nginx-conf --from-file=nginx.conf=./nginx.conf
kubectl create configmap nginx-conf --from-file=MY_NGINX=./nginx.conf   # custom key

# from a whole directory (each file becomes a key)
kubectl create configmap app-files --from-file=./config/

# from env-file
kubectl create configmap app-env --from-env-file=./.env

# from YAML
kubectl create configmap app-config --dry-run=client -o yaml \
  --from-literal=LOG_LEVEL=debug > configmap.yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: app-config}
data:
  LOG_LEVEL: "debug"                  # ⚠️ values MUST be strings — quote numbers/booleans
  MAX_THREADS: "8"
  nginx.conf: |                       # multi-line file
    server {
      listen 80;
      location / { proxy_pass http://api:8080; }
    }
binaryData:
  logo.png: iVBORw0KGgo...            # base64
immutable: true                       # optional: prevents accidental edits (and reduces API load)
```

**Four ways to consume it:**

```yaml
# 1. Single env var
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef: {name: app-config, key: LOG_LEVEL}

# 2. All keys as env vars
envFrom:
  - configMapRef: {name: app-config}
    prefix: APP_                       # optional prefix

# 3. As a file (recommended for config files)
volumeMounts:
  - {name: config, mountPath: /etc/app/nginx.conf, subPath: nginx.conf, readOnly: true}
volumes:
  - name: config
    configMap:
      name: app-config
      items:                             # cherry-pick keys → filenames
        - {key: nginx.conf, path: nginx.conf}
      defaultMode: 0440

# 4. As command args
args: ["--config=/etc/app/nginx.conf"]
```

### 7.2 The update behaviour that bites everyone

| Consumption method | Auto-updates when the ConfigMap changes? |
|---|---|
| `env` / `envFrom` | ❌ **Never.** Pod must be restarted. |
| Volume mount (no `subPath`) | ✅ Yes — files update within ~1 min (kubelet sync + cache TTL) |
| Volume mount **with `subPath`** | ❌ **Never.** subPath mounts are not refreshed. |
| `immutable: true` ConfigMap | ❌ By definition |

> 🔑 So: mounted config files update *on disk*, but **your app must notice** — most don't. Reload it (`nginx -s reload`), or use a sidecar reloader, or just `kubectl rollout restart deployment/web` (the normal, boring, correct answer).

### 7.3 Secrets

Same shape as a ConfigMap, plus: base64 encoding, separate RBAC, encryption-at-rest support, and integration with external stores.

```bash
kubectl create secret generic db-creds \
  --from-literal=username=app \
  --from-literal=password='S3cret!'

kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io \
  --docker-username=harish \
  --docker-password=$GHCR_TOKEN

kubectl create secret tls shop-tls --cert=tls.crt --key=tls.key

kubectl create secret generic app-secrets --from-file=./secrets/   # each file = a key
```

```yaml
apiVersion: v1
kind: Secret
metadata: {name: db-creds}
type: Opaque                       # Opaque | kubernetes.io/tls | kubernetes.io/dockerconfigjson
                                   # kubernetes.io/service-account-token | bootstrap.kubernetes.io/token
stringData:                        # ← plain text, Kubernetes base64-encodes it for you (USE THIS)
  username: app
  password: "S3cret!"
# data:                            # ← or pre-encoded base64
#   password: UzNjcmV0IQ==
```

```bash
# decode one
kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 -d
# decode all
kubectl get secret db-creds -o go-template='{{range $k,$v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'
```

> ⚠️ **base64 is encoding, NOT encryption.** Anyone with `get secret` rights can read them. Real protection = RBAC + etcd encryption at rest (`EncryptionConfiguration`) + an external secret manager:
>
> | Tool | Model |
> |---|---|
> | **External Secrets Operator** | Pulls from Vault / AWS SM / GCP SM / Azure KV into native Secrets |
> | **Sealed Secrets** (Bitnami) | Encrypt with a public key in Git; only the cluster can decrypt |
> | **SOPS + age/PGP** | Encrypt YAML values; commit ciphertext; decrypt at apply time |
> | **HashiCorp Vault Agent Injector** | Sidecar mounts secrets as files, short-lived, auto-rotated |
>
> **Never commit plain Secrets to Git.** `kubectl get secret -o yaml > secret.yaml` in your repo is how breaches start.

**Secrets as files are better than env vars** for three reasons: they don't leak into `kubectl describe pod`, crash dumps, or child process environments; they can be updated in place; and they work with the standard `*_FILE` convention:

```yaml
env:
  - name: DB_PASSWORD_FILE
    value: /run/secrets/db/password
volumeMounts:
  - {name: db, mountPath: /run/secrets/db, readOnly: true}
volumes:
  - name: db
    secret:
      secretName: db-creds
      items: [{key: password, path: password}]
      defaultMode: 0400
```

### 7.4 `imagePullSecrets`

```yaml
spec:
  imagePullSecrets:
    - name: regcred
  containers:
    - {name: app, image: ghcr.io/3558bhk/myapp:1.0.0}
```

Or attach it to the ServiceAccount so every Pod using that SA gets it automatically:

```bash
kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"regcred"}]}'
```

### 7.5 The Downward API — Pod metadata inside the Pod

```yaml
env:
  - name: POD_NAME
    valueFrom: {fieldRef: {fieldPath: metadata.name}}
  - name: POD_NAMESPACE
    valueFrom: {fieldRef: {fieldPath: metadata.namespace}}
  - name: POD_IP
    valueFrom: {fieldPath: status.podIP}
  - name: NODE_NAME
    valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
  - name: CPU_LIMIT
    valueFrom: {resourceFieldRef: {resource: limits.cpu, divisor: "1"}}
volumeMounts: [{name: podinfo, mountPath: /etc/podinfo}]
volumes:
  - name: podinfo
    downwardAPI:
      items:
        - {path: "labels", fieldRef: {fieldPath: metadata.labels}}
        - {path: "annotations", fieldRef: {fieldPath: metadata.annotations}}
```

### 7.6 Config best practices (production checklist)

- [ ] One ConfigMap per app per environment; name it `<app>-config`, not `config`.
- [ ] Config *files* as volumes; simple scalars as env.
- [ ] `immutable: true` in CI-built configs so a bad `kubectl edit` can't happen.
- [ ] Config changes go through Git + `kubectl apply`, and are followed by `rollout restart` if consumed via env.
- [ ] Hash the config into the Pod template annotation so a change *automatically* rolls the Deployment (Helm does this with `checksum/config`):
  ```yaml
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  ```
- [ ] Secrets from a real secret store, never plain YAML in Git.
- [ ] Validate: `kubectl apply --dry-run=server -f .` catches "ConfigMap not found" before you ship.

---

## §8 — Storage: PV, PVC, StorageClass, CSI

### 8.1 The three objects and why there are three

```
   StorageClass  ──"how to make storage"──►  PersistentVolume (PV)  ──"a real disk"──┐
        │                                          ▲                                 │
        │ dynamic provisioning                     │ bound 1:1                       │
        ▼                                          │                                 ▼
   PersistentVolumeClaim (PVC) ──"I want 10Gi RWO"──┘                          Pod mounts it
```

| Object | Written by | Means |
|---|---|---|
| **PV** | Cluster admin *or* the provisioner | An actual piece of storage (EBS volume, NFS export, local disk) |
| **PVC** | Application developer | A *request* for storage: size, access mode, class |
| **StorageClass** | Cluster admin | A *recipe* for making PVs on demand (dynamic provisioning) |

The indirection exists so **app developers never need to know what cloud they're on.** They ask for "10Gi ReadWriteOnce, standard class"; the cluster figures out the rest.

### 8.2 Volume types you'll actually meet

| Type | Lifetime | Use |
|---|---|---|
| `emptyDir` | Dies with the Pod | Scratch space, cache, sharing between containers in a Pod |
| `emptyDir: {medium: Memory}` | Dies with the Pod | tmpfs — fast, counts against memory limit |
| `hostPath` | Node's disk, survives Pod | **Dev only.** Node-level agents. Never for app data. |
| `configMap` / `secret` / `downwardAPI` / `serviceAccountToken` | Object lifetime | Config injection |
| `persistentVolumeClaim` | Independent of Pod | **All real state** |
| `local` | Node's disk, survives Pod | High-perf local SSD with scheduler awareness (better than hostPath) |
| `nfs`, `csi` | Backend-dependent | Shared / cloud storage |

```yaml
# emptyDir with a size cap (protects the node's disk)
volumes:
  - name: scratch
    emptyDir:
      sizeLimit: 1Gi
      # medium: Memory     # tmpfs
```

> ⚠️ `emptyDir` data is **lost when the Pod is deleted or evicted**. It survives *container* restarts inside the same Pod, not Pod replacement. This surprises everyone once.

### 8.3 Dynamic provisioning — the normal path

```bash
kubectl get storageclass
# NAME                 PROVISIONER             RECLAIMPOLICY  VOLUMEBINDINGMODE  ALLOWVOLUMEEXPANSION
# standard (default)   rancher.io/local-path   Delete         WaitForFirstConsumer  false
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: app-data}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: standard          # omit to use the cluster default
  resources:
    requests: {storage: 10Gi}
  volumeMode: Filesystem              # or Block
```

```yaml
# in the Pod / Deployment template
containers:
  - name: app
    volumeMounts: [{name: data, mountPath: /data}]
volumes:
  - name: data
    persistentVolumeClaim: {claimName: app-data}
```

```bash
kubectl apply -f pvc.yaml
kubectl get pvc            # Pending → Bound
kubectl get pv             # shows the provisioned volume
kubectl describe pvc app-data   # events tell you WHY it's pending
```

### 8.4 Access modes — what they really mean

| Mode | Short | Meaning | Typical backing |
|---|---|---|---|
| ReadWriteOnce | **RWO** | Mountable read-write by **one node** | EBS, GCE PD, Azure Disk, local |
| ReadOnlyMany | **ROX** | Read-only by many nodes | NFS, CephFS, EFS |
| ReadWriteMany | **RWX** | Read-write by many nodes | NFS, CephFS, EFS, Azure Files, Longhorn |
| ReadWriteOncePod | **RWOP** | Read-write by **one Pod** (strict, v1.29+ GA) | CSI drivers that support it |

> ⚠️ **RWO = one *node*, not one Pod.** Two Pods on the same node can both mount an RWO volume (on many CSI drivers). Don't rely on that; use RWOP if you need exclusivity.
>
> ⚠️ **Cloud block storage is RWO.** You cannot share an EBS volume across nodes. If your Deployment has 3 replicas on 3 nodes and one shared PVC → 2 Pods stuck in `ContainerCreating` with `Multi-Attach error`. Use a StatefulSet with `volumeClaimTemplates` (one PVC per Pod), or RWX storage.

### 8.5 Reclaim policy & volume binding mode

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: {name: fast-ssd}
provisioner: ebs.csi.aws.com
parameters: {type: gp3, encrypted: "true"}
reclaimPolicy: Delete              # Delete (default!) | Retain
allowVolumeExpansion: true         # lets you grow the PVC later
mountOptions: ["noatime"]
volumeBindingMode: WaitForFirstConsumer   # ← wait until a Pod is scheduled, then provision
                                           #    in the Pod's zone. Avoids cross-AZ disasters.
```

| `reclaimPolicy` | When the PVC is deleted |
|---|---|
| `Delete` | **The PV and the underlying disk are destroyed.** Data gone. Default in most clouds. |
| `Retain` | PV stays `Released`; you must manually clean it and reclaim the data. Safe. |

```bash
kubectl patch storageclass standard -p '{"reclaimPolicy":"Retain"}'   # only affects NEW PVs
```

### 8.6 Expanding a volume

```bash
kubectl get sc standard -o jsonpath='{.allowVolumeExpansion}'   # must be true
kubectl patch pvc app-data -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
kubectl get pvc app-data -w     # may need a Pod restart to grow the FILESYSTEM
```

You can only grow, never shrink. Shrinking = create new, copy data, swap.

### 8.7 PVC stuck in `Pending` — the full answer

```bash
kubectl describe pvc app-data | sed -n '/Events/,$p'
```

| Event / symptom | Cause | Fix |
|---|---|---|
| `no persistent volumes available for this claim and no storage class is set` | No default StorageClass, no PVs | `kubectl get sc`; create one or set a default |
| `storageclass.storage.k8s.io "fast" not found` | Typo in `storageClassName` | `kubectl get sc` and match exactly |
| `waiting for first consumer to be created before binding` | `WaitForFirstConsumer` — **this is normal**, not an error | Create the Pod that uses it |
| `pod has unbound immediate PersistentVolumeClaims` | Same as above | Same |
| Provisioner error: `failed to provision volume` | Cloud creds / quota / AZ | `kubectl logs -n kube-system <provisioner-pod>` |
| `field label not supported: spec.selector` | Using `selector` with dynamic provisioning | Remove the selector or use a static PV |

**Static provisioning** (pre-created PVs, matched by label):

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: {name: legacy-nfs, labels: {tier: archive}}
spec:
  capacity: {storage: 100Gi}
  accessModes: ["ReadWriteMany"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""              # empty = opt out of dynamic provisioning
  nfs: {server: 10.0.0.50, path: /exports/archive}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: archive}
spec:
  accessModes: ["ReadWriteMany"]
  storageClassName: ""
  resources: {requests: {storage: 100Gi}}
  selector:
    matchLabels: {tier: archive}
```

### 8.8 Backup & restore (what production actually does)

```bash
# Quick manual snapshot
kubectl exec -it db-0 -- pg_dump -U postgres app > app.sql
kubectl exec -i db-0 -- psql -U postgres app < app.sql

# Copy data off a PVC via a helper Pod
kubectl run pv-dump --rm -it --image=busybox:1.37 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"pv-dump","image":"busybox:1.37","stdin":true,"tty":true,"command":["sh"],"volumeMounts":[{"name":"d","mountPath":"/data"}]}],"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"app-data"}}]}}'
# then: tar czf - /data > /dev/stdout   (and redirect outside)
```

**Real answer: Velero.**

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero --namespace velero --create-namespace \
  -f values.yaml                       # configure your object storage + cloud creds

velero backup create nightly --include-namespaces prod --ttl 168h
velero backup get
velero restore create --from-backup nightly
velero schedule create nightly --schedule "0 2 * * *" --ttl 168h
```

> 🔑 **Velero backs up objects + PV snapshots. It does not back up etcd's live state or secrets you keep outside the cluster.** Test your restores — an untested backup is a rumour.

---

## §9 — Health: probes, restart policies, lifecycle hooks

### 9.1 The three probes

| Probe | Question it answers | On failure |
|---|---|---|
| **startupProbe** | "Has this app finished starting?" | Kills the container and restarts it. **While it runs, the other two are disabled.** |
| **readinessProbe** | "Can this Pod serve traffic *right now*?" | Removes the Pod from Service endpoints. **Does NOT restart it.** |
| **livenessProbe** | "Is this app deadlocked/broken beyond recovery?" | **Kills and restarts the container.** |

**Getting these wrong causes outages.** The two classic mistakes:

1. **Liveness probe that depends on a downstream service.** Your DB has a 30 s blip → every app Pod's liveness fails → Kubernetes restarts *the entire fleet* → thundering herd → real outage. **Liveness must test only the app itself.**
2. **No readiness probe.** Kubernetes marks the Pod Ready the moment the container process starts, before your JVM/Node/Go app has bound the port → traffic gets `connection refused` during every rollout.

### 9.2 Four probe mechanisms

```yaml
# 1. HTTP GET — 2xx/3xx = success
httpGet:
  path: /healthz
  port: http                  # name or number
  host: 127.0.0.1
  scheme: HTTP                # or HTTPS
  httpHeaders:
    - {name: X-Probe, value: "1"}

# 2. TCP socket — connection accepted = success
tcpSocket: {port: 5432}

# 3. Exec — exit code 0 = success
exec:
  command: ["sh","-c","pg_isready -U postgres -h 127.0.0.1"]

# 4. gRPC (v1.27+ stable) — no grpc_health_probe binary needed
grpc: {port: 50051, service: my.Service}
```

### 9.3 Probe timing parameters — and how to compute them

```yaml
readinessProbe:
  httpGet: {path: /ready, port: http}
  initialDelaySeconds: 5      # wait before the FIRST probe
  periodSeconds: 10           # how often
  timeoutSeconds: 3           # per-probe timeout (must be < periodSeconds)
  successThreshold: 1         # consecutive successes to be considered healthy (MUST be 1 for liveness/startup)
  failureThreshold: 3         # consecutive failures to be considered unhealthy
```

**Time-to-detect a failure** = `initialDelaySeconds + (failureThreshold × periodSeconds)`
**Time-to-recover** = `successThreshold × periodSeconds`

### 9.4 The startupProbe pattern for slow apps (use this for Java)

Instead of a giant `initialDelaySeconds` on liveness (which delays detection of *real* hangs too), use a startup probe:

```yaml
startupProbe:
  httpGet: {path: /healthz, port: 8080}
  periodSeconds: 5
  failureThreshold: 60        # 5s × 60 = up to 5 MINUTES to start
  timeoutSeconds: 3
livenessProbe:                # only begins after startup succeeds
  httpGet: {path: /healthz, port: 8080}
  periodSeconds: 20
  failureThreshold: 3         # dead within 60s of hanging
readinessProbe:
  httpGet: {path: /ready, port: 8080}
  periodSeconds: 5
  failureThreshold: 2         # out of rotation in 10s
  successThreshold: 1
```

### 9.5 What each endpoint should check

| Endpoint | Checks | Used by |
|---|---|---|
| `/healthz` (liveness) | Process alive, no deadlock. **Nothing external.** | livenessProbe |
| `/ready` (readiness) | DB pool available, cache warm, dependencies reachable, not draining | readinessProbe |
| `/startup` | App fully initialised | startupProbe |

Spring Boot Actuator maps perfectly: `/actuator/health/liveness` and `/actuator/health/readiness` (enable with `management.endpoint.health.probes.enabled=true`).

### 9.6 Restart policy & backoff

| `restartPolicy` | Restarts on | Valid for |
|---|---|---|
| `Always` (default) | Any container exit, including 0 | Pod, Deployment, DaemonSet, StatefulSet |
| `OnFailure` | Non-zero exit only | Pod, Job, CronJob |
| `Never` | Nothing | Pod, Job, CronJob |

Backoff for `CrashLoopBackOff`: 10 s → 20 s → 40 s → … capped at **5 minutes**, reset after 10 minutes of successful running.

### 9.7 Graceful termination — the exact sequence

This is worth memorising; it explains most "we drop a few requests on every deploy" complaints.

```
kubectl delete pod web-abc   (or a rollout, or node drain)
  │
  ├─► Pod marked Terminating
  │     ├─► (1) EndpointSlice controller removes it from Service endpoints  ┐ these happen
  │     └─► (2) kubelet runs preStop hook                                   ┘ CONCURRENTLY
  │
  ├─► (3) after preStop finishes, kubelet sends SIGTERM to PID 1
  ├─► (4) app should stop accepting new work, finish in-flight requests, flush, exit
  │
  └─► (5) after terminationGracePeriodSeconds (default 30), SIGKILL
```

**The race:** steps (1) and (2) run in parallel. kube-proxy rules and ingress-controller config can take a few hundred ms to a few seconds to propagate. If your app exits immediately on SIGTERM, in-flight and brand-new requests still being routed to it will fail.

**The fix — a preStop sleep:**

```yaml
lifecycle:
  preStop:
    exec: {command: ["/bin/sh","-c","sleep 5"]}
terminationGracePeriodSeconds: 40      # must exceed preStop + app shutdown time
```

**And your app must handle SIGTERM.** With `ENTRYPOINT ["sh","-c","java -jar app.jar"]` the shell is PID 1 and *does not forward signals* → SIGTERM is ignored → SIGKILL at 30 s → dropped requests. Use exec form, or `tini` / `dumb-init` as PID 1.

### 9.8 Resource-based restarts

- **OOMKilled** — container exceeded `limits.memory`. Exit code **137** (128+9). `Last State: Terminated, Reason: OOMKilled`.
- **CPU throttling** — exceeding `limits.cpu` does *not* kill anything; it just slows you down. Watch `container_cpu_cfs_throttled_periods_total`.
- **Node eviction** — kubelet evicts Pods when the node hits `memory.available < 100Mi` or `nodefs.available < 10%`. Pod shows `Evicted`. Burstable/BestEffort Pods go first (§10.4).

---

## §10 — Scheduling

### 10.1 Requests and limits — the numbers that matter most

```yaml
resources:
  requests:                # RESERVED for scheduling. kubelet guarantees this much.
    cpu: "250m"            # 250 millicores = 0.25 vCPU
    memory: "256Mi"        # Mi = mebibytes (2^20). M = megabytes (10^6). Don't mix them up.
    ephemeral-storage: "1Gi"
    hugepages-2Mi: "64Mi"
  limits:                  # HARD CEILING
    cpu: "1000m"           # exceeding → THROTTLED (not killed)
    memory: "512Mi"        # exceeding → OOMKILLED (exit 137)
    ephemeral-storage: "2Gi"   # exceeding → Pod EVICTED
```

| QoS class | Condition | Eviction priority |
|---|---|---|
| **Guaranteed** | requests == limits for *every* container, cpu & memory both set | Evicted **last** |
| **Burstable** | at least one request set, not Guaranteed | Evicted in the middle |
| **BestEffort** | nothing set at all | Evicted **first** |

```bash
kubectl describe node node1 | sed -n '/Allocatable/,/System Info/p'   # capacity
kubectl describe node node1 | sed -n '/Allocated resources/,/Events/p' # how full it is
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

**How to pick numbers:**
1. Deploy with generous limits, no HPA.
2. Run a realistic load for 10+ minutes.
3. `kubectl top pods` → note peak memory and steady CPU.
4. `requests.memory` = peak × 1.2. `limits.memory` = requests × 1.5–2 (Java: leave real headroom, see below).
5. `requests.cpu` = steady usage (this drives scheduling and HPA). `limits.cpu`: **often best left unset** so the Pod can burst into idle capacity instead of being throttled — but then you lose Guaranteed QoS. Team preference; document it.

> 🔑 **Java:** set `-XX:MaxRAMPercentage=75` (JVM is container-aware since JDK 10) and give the container `limits.memory` ≈ heap × 1.4 (metaspace, thread stacks, direct buffers, GC overhead all live outside the heap). A JVM with `-Xmx512m` in a 512Mi container **will** be OOMKilled.

> 🔑 **Node.js:** `--max-old-space-size` should be ~75% of the memory limit. Default V8 heap is ~1.5–2 GB regardless of your limit, so it will happily get OOMKilled in a 512Mi Pod.

### 10.2 nodeSelector, affinity, anti-affinity

```yaml
# 1. nodeSelector — simplest, AND of all labels, hard requirement
nodeSelector:
  disktype: ssd
  node.kubernetes.io/instance-type: m6i.large

# 2. nodeAffinity — expressive, soft or hard
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:      # HARD
      nodeSelectorTerms:
        - matchExpressions:
            - {key: topology.kubernetes.io/zone, operator: In, values: [ap-south-1a, ap-south-1b]}
            - {key: kubernetes.io/arch, operator: NotIn, values: [arm64]}
    preferredDuringSchedulingIgnoredDuringExecution:     # SOFT (weight 1-100)
      - weight: 80
        preference:
          matchExpressions: [{key: disktype, operator: In, values: [ssd]}]

# 3. podAntiAffinity — spread replicas away from each other
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector: {matchLabels: {app: web}}
        topologyKey: kubernetes.io/hostname        # never 2 web pods on one node
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector: {matchLabels: {app: web}}
          topologyKey: topology.kubernetes.io/zone # prefer different AZs

# 4. podAffinity — co-locate (e.g. cache next to app)
  podAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector: {matchLabels: {app: redis}}
          topologyKey: kubernetes.io/hostname
```

**Operators:** `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt` (numeric, for `matchExpressions` only).

**Well-known labels you should use instead of inventing your own:**

```
kubernetes.io/hostname              node name
kubernetes.io/arch                  amd64 | arm64
kubernetes.io/os                    linux | windows
node.kubernetes.io/instance-type    m6i.large …
topology.kubernetes.io/zone         ap-south-1a
topology.kubernetes.io/region       ap-south-1
node.kubernetes.io/disk-pressure    ← added automatically when a node is low on disk
```

### 10.3 Taints and tolerations

**Taints go on nodes** ("stay away unless you have a reason"). **Tolerations go on Pods** ("I have a reason").

```bash
kubectl taint nodes node1 gpu=true:NoSchedule
kubectl taint nodes node1 gpu=true:NoSchedule-      # remove (trailing -)
kubectl describe node node1 | grep -i taints
```

| Effect | Meaning |
|---|---|
| `NoSchedule` | New Pods without a toleration won't be scheduled here. Existing Pods stay. |
| `PreferNoSchedule` | Soft version — avoid if possible |
| `NoExecute` | Existing Pods without a toleration are **evicted immediately** |

```yaml
tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  - key: "node.kubernetes.io/unreachable"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 300        # stay 5 min after the node goes away, then be evicted
```

**Automatic taints Kubernetes applies** (and you should tolerate for DaemonSets):
`node.kubernetes.io/not-ready`, `unreachable`, `memory-pressure`, `disk-pressure`, `pid-pressure`, `unschedulable`, `network-unavailable`, plus `node-role.kubernetes.io/control-plane:NoSchedule`.

> 🔑 **Taints ≠ anti-affinity.** A taint keeps *other* Pods off a node. Anti-affinity keeps *your* Pods away from each other. You usually want both for GPU/dedicated node pools.

### 10.4 Topology spread constraints — the modern way to spread

```yaml
topologySpreadConstraints:
  - maxSkew: 1                              # max difference in pod count between any two zones
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway       # or DoNotSchedule (hard)
    labelSelector: {matchLabels: {app: web}}
    minDomains: 2                           # treat missing zones as empty, so 1 pod can't be "balanced"
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector: {matchLabels: {app: web}}
```

Prefer this over podAntiAffinity for spreading: it's explicit about skew and behaves predictably as the cluster grows.

### 10.5 Priority and preemption

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: {name: critical-prod}
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority    # or Never
description: "Production tier-1 services"
---
# in the Pod spec
priorityClassName: critical-prod
```

When the cluster is full, a high-priority Pending Pod **evicts lower-priority running Pods** to make room. Kubernetes also has built-in classes: `system-cluster-critical`, `system-node-critical`.

### 10.6 Pod stuck in `Pending` — the complete diagnosis

```bash
kubectl describe pod web-xyz | sed -n '/Events/,$p'
```

| Event message | Cause | Fix |
|---|---|---|
| `0/3 nodes are available: 3 Insufficient cpu` | Not enough *requests* headroom (not actual usage!) | Lower requests, add nodes, check `kubectl describe node` allocations |
| `3 Insufficient memory` | Same, memory | Same |
| `node(s) had untolerated taint {gpu: true}` | Taint | Add a toleration |
| `node(s) didn't match Pod's node affinity/selector` | Wrong labels | `kubectl get nodes --show-labels` |
| `node(s) didn't match pod topology spread constraints` | Spread too strict | Relax `maxSkew` or use `ScheduleAnyway` |
| `pod has unbound immediate PersistentVolumeClaims` | PVC not bound | §8.7 |
| `3 node(s) had volume node affinity conflict` | PV is zoned to a zone with no feasible node | Change zone / use `WaitForFirstConsumer` |
| Nothing at all, no events | Scheduler not running | `kubectl get pods -n kube-system -l component=kube-scheduler` |
| `0/3 nodes are available: 3 node(s) were unschedulable` | Nodes cordoned | `kubectl uncordon <node>` |

---

## §11 — Namespaces, RBAC, ServiceAccounts, security

### 11.1 Three kinds of identity

| Identity | Who | Credential |
|---|---|---|
| **Human / CI** | You, Jenkins, GitHub Actions | kubeconfig: client cert, token, OIDC |
| **ServiceAccount** | A Pod talking to the API server | Projected token at `/var/run/secrets/kubernetes.io/serviceaccount/` |
| **Workload identity (cloud)** | A Pod talking to AWS/GCP/Azure | IRSA / Workload Identity / Azure Workload Identity |

### 11.2 RBAC in four objects

```
    Role / ClusterRole           = a set of PERMISSIONS (verbs on resources)
    RoleBinding / ClusterRoleBinding = who GETS those permissions, in which scope
```

| | Namespaced | Cluster-wide |
|---|---|---|
| Permissions | **Role** | **ClusterRole** |
| Grant | **RoleBinding** | **ClusterRoleBinding** |

A `RoleBinding` can reference a `ClusterRole` — that "instantiates" the cluster-wide permission set *inside one namespace*. This is the pattern you want for "same permissions per namespace".

```yaml
# A role: can read pods and logs in one namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {namespace: dev, name: pod-reader}
rules:
  - apiGroups: [""]                       # "" = core group
    resources: ["pods", "pods/log", "pods/portforward"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {namespace: dev, name: read-pods}
subjects:
  - {kind: User, name: harish@example.com, apiGroup: rbac.authorization.k8s.io}
  - {kind: ServiceAccount, name: ci-bot, namespace: dev}
  - {kind: Group, name: dev-team@example.com, apiGroup: rbac.authorization.k8s.io}
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

**Verbs:** `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`, `deletecollection`, `impersonate`, `bind`, `escalate`, `use` (for PSP-like resources), `*`.

```bash
kubectl get clusterroles | head -30      # view, edit, admin, cluster-admin + system ones
kubectl describe clusterrole edit
kubectl auth can-i delete pods -n prod
kubectl auth can-i --list -n prod
kubectl auth can-i create deployments --as=system:serviceaccount:dev:ci-bot -n dev
kubectl create rolebinding harish-admin --clusterrole=admin --user=harish@example.com -n dev
```

**Built-in user-facing ClusterRoles:**

| Role | Can do |
|---|---|
| `view` | Read everything except Secrets, Roles, RoleBindings |
| `edit` | Read/write most things in a namespace; **not** RBAC, not ResourceQuota |
| `admin` | Everything in a namespace including RBAC |
| `cluster-admin` | Everything everywhere. **Hand this out never.** |

### 11.3 ServiceAccounts

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: app-sa, namespace: prod}
automountServiceAccountToken: false     # ← set false unless the app talks to the API
imagePullSecrets: [{name: regcred}]
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/app-role   # IRSA
```

```bash
kubectl get sa
kubectl describe sa default
```

> 🔑 **Security default:** `automountServiceAccountToken: false` on the SA, then opt in only where needed. Every Pod with a mounted token is a potential cluster takeover if the app is RCE-able.

### 11.4 Pod security context — the hardened baseline

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        privileged: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
          # add: ["NET_BIND_SERVICE"]   # only if you must bind <1024
      volumeMounts:
        - {name: tmp, mountPath: /tmp}          # writable dirs when rootfs is read-only
  volumes:
    - {name: tmp, emptyDir: {}}
```

`privileged: true` = root on the node, full host access, container escape is trivial. Reserve for CNI/CSI DaemonSets, never for apps.

### 11.5 Pod Security Admission (replaces PodSecurityPolicy)

Label a namespace to enforce a standard:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: prod
  labels:
    pod-security.kubernetes.io/enforce: restricted      # privileged | baseline | restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

| Level | Blocks |
|---|---|
| `privileged` | Nothing (unrestricted) |
| `baseline` | Known privilege escalations: `privileged`, `hostPID/IPC/Network`, `hostPath`, most capabilities, `allowPrivilegeEscalation` |
| `restricted` | Hardened best practice: `runAsNonRoot`, `seccompProfile: RuntimeDefault`, `drop ALL` capabilities, read-only rootfs recommended |

```bash
kubectl get ns -L pod-security.kubernetes.io/enforce
```

### 11.6 ResourceQuota & LimitRange — namespace guardrails

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: {name: team-quota, namespace: dev}
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    pods: "40"
    persistentvolumeclaims: "20"
    services.loadbalancers: "1"
    count/deployments.apps: "20"
    configmaps: "50"
---
apiVersion: v1
kind: LimitRange
metadata: {name: defaults, namespace: dev}
spec:
  limits:
    - type: Container
      default: {cpu: 500m, memory: 512Mi}          # applied when the pod sets NO limit
      defaultRequest: {cpu: 100m, memory: 128Mi}    # applied when the pod sets NO request
      max: {cpu: "4", memory: 8Gi}
      min: {cpu: 50m, memory: 64Mi}
      maxLimitRequestRatio:
        cpu: "10"                                    # limit/request ratio cap
```

> ⚠️ **A ResourceQuota with `requests.cpu` set makes requests MANDATORY for every Pod in the namespace.** Pods without resources fail with `FailedCreate … must specify requests.cpu`. That's the confusing part; now you know.

---

## §12 — Ingress, Gateway API, DNS, NetworkPolicy

### 12.1 Why not just `type: LoadBalancer` for everything?

One cloud LoadBalancer **per Service** = one public IP each = expensive and unmanageable. An **Ingress** is a single L7 entry point that routes by **host** and **path** to many Services.

```
Internet ──► Cloud LB ──► Ingress Controller (nginx pod) ──┬─► Service A ─► Pods
                        (rules from Ingress objects)        ├─► Service B ─► Pods
                                                            └─► Service C ─► Pods
```

⚠️ **An `Ingress` resource does nothing without an Ingress *controller* running in the cluster.** This confuses everyone. The controller is a Deployment (nginx, Traefik, HAProxy, Envoy, AWS ALB, GCP GKE) that watches Ingress objects and programs itself.

```bash
# install the reference controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.1/deploy/static/provider/cloud/deploy.yaml
# or on minikube:  minikube addons enable ingress
# or on kind:      kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl get pods -n ingress-nginx
kubectl get ingressclass            # nginx, traefik, alb …
```

### 12.2 A complete Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "20m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx                    # ← always set this explicitly
  tls:
    - hosts: [shop.example.com]
      secretName: shop-tls                   # cert-manager creates this
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service: {name: api, port: {number: 8080}}
          - path: /
            pathType: Prefix
            backend:
              service: {name: web, port: {number: 80}}
    - host: admin.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: {name: admin, port: {number: 80}}
```

| `pathType` | Matching |
|---|---|
| `Exact` | Case-sensitive exact match |
| `Prefix` | Element-wise prefix: `/foo` matches `/foo` and `/foobar`… actually matches on `/`-separated elements, so `/foo` matches `/foo/bar` but *not* `/foobar` |
| `ImplementationSpecific` | Controller decides — required for regex captures like `/api(/|$)(.*)` |

```bash
kubectl get ingress
kubectl describe ingress shop          # shows the resolved rules table + events
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=100
# test with a Host header before you touch DNS:
curl -H "Host: shop.example.com" http://localhost:8080/
curl -kv https://localhost:8443 --resolve shop.example.com:443:127.0.0.1
```

**Common annotations worth knowing (ingress-nginx):**

| Annotation | Effect |
|---|---|
| `nginx.ingress.kubernetes.io/rewrite-target` | URL rewriting (`/$1`, `/$2`) |
| `nginx.ingress.kubernetes.io/ssl-redirect` | Force HTTPS |
| `nginx.ingress.kubernetes.io/backend-protocol` | `GRPC`, `HTTPS`, `AJP` |
| `nginx.ingress.kubernetes.io/proxy-body-size` | Upload limit (default 1 m — the cause of "413 Request Entity Too Large") |
| `nginx.ingress.kubernetes.io/proxy-read-timeout` | 60 s default; raise for long requests |
| `nginx.ingress.kubernetes.io/limit-rps` | Rate limiting |
| `nginx.ingress.kubernetes.io/whitelist-source-range` | CIDR allowlist |
| `nginx.ingress.kubernetes.io/auth-url` | External auth (oauth2-proxy) |
| `nginx.ingress.kubernetes.io/cors-allow-origin` | CORS |
| `nginx.ingress.kubernetes.io/configuration-snippet` | Raw nginx config (often disabled by admins) |
| `cert-manager.io/cluster-issuer` | Auto TLS |

### 12.3 Local development with Ingress (no real DNS)

```bash
# 1. /etc/hosts approach
echo "127.0.0.1 shop.example.com api.example.com" | sudo tee -a /etc/hosts
# kind: also needs extraPortMappings for 80/443 (see §0.2)

# 2. nip.io / sslip.io wildcard DNS — no hosts file editing
#    shop.127-0-0-1.nip.io resolves to 127.0.0.1 automatically
curl http://shop.127-0-0-1.nip.io:8080/

# 3. minikube
minikube tunnel &           # gives LoadBalancer IPs
minikube addons enable ingress-dns
```

### 12.4 cert-manager — real TLS, automated

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl get pods -n cert-manager      # cert-manager, -webhook, -cainjector all Running
```

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: {name: letsencrypt-prod}
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: you@example.com
    privateKeySecretRef: {name: letsencrypt-prod-key}
    solvers:
      - http01:
          ingress: {ingressClassName: nginx}
      # - dns01:                     # for wildcard certs
      #     route53: {region: ap-south-1, hostedZoneID: Z123, role: arn:aws:iam::…:role/dns01}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: {name: shop-tls, namespace: default}
spec:
  secretName: shop-tls                 # ← the Secret the Ingress references
  issuerRef: {name: letsencrypt-prod, kind: ClusterIssuer}
  dnsNames: [shop.example.com, www.shop.example.com]
  duration: 2160h                      # 90d
  renewBefore: 720h                    # renew 30d before expiry
```

> 🔑 With the `cert-manager.io/cluster-issuer` annotation on the Ingress, cert-manager **auto-creates** the Certificate from `spec.tls`. You don't need the Certificate object explicitly. That's the usual setup.

```bash
kubectl get certificates,certificaterequests,orders,challenges
kubectl describe certificate shop-tls      # ← if it's not Ready, this says why
kubectl logs -n cert-manager deploy/cert-manager --tail=100
```

HTTP-01 failure checklist: DNS must already point at the Ingress LB · port 80 reachable from the internet · `ingressClassName` correct · only one Ingress per host/path · Let's Encrypt rate limits (5 duplicate certs/week).

### 12.5 Gateway API — the Ingress successor

Ingress is limited: no traffic splitting, weak typed config, annotations as the extension mechanism. **Gateway API** fixes this with three roles:

| Object | Owned by | Purpose |
|---|---|---|
| `GatewayClass` | Infra provider | Which controller implements this (`istio`, `nginx`, `envoy-gateway`) |
| `Gateway` | Cluster operator | Listener: port, protocol, TLS cert, hostname |
| `HTTPRoute` / `GRPCRoute` / `TCPRoute` | App developer | Routing rules attached to a Gateway |
| `ReferenceGrant` | Namespace owner | Explicitly allows cross-namespace references |

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: shop-gw, namespace: infra}
spec:
  gatewayClassName: istio
  listeners:
    - {name: https, protocol: HTTPS, port: 443, hostname: "*.example.com",
       tls: {mode: Terminate, certificateRefs: [{kind: Secret, name: wildcard-tls}]},
       allowedRoutes: {namespaces: {from: Selector, selector: {matchLabels: {team: shop}}}}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: api, namespace: shop}
spec:
  parentRefs: [{name: shop-gw, namespace: infra}]
  hostnames: ["api.example.com"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /v1}}]
      filters: [{type: RequestHeaderModifier, requestHeaderModifier: {set: [{name: X-Env, value: prod}]}}]
      backendRefs:
        - {name: api-v1, port: 8080, weight: 90}
        - {name: api-v2, port: 8080, weight: 10}   # ← canary! Impossible with plain Ingress
```

**Learn Ingress first** (it's everywhere and is not going away), but know Gateway API is where new features land: canary by weight, header-based routing, traffic mirroring, typed policy attachment.

### 12.6 NetworkPolicy — the firewall

**By default, all Pods can talk to all Pods.** A NetworkPolicy makes a namespace default-deny and then allows only what you specify.

⚠️ **Requires a CNI that enforces NetworkPolicy** (Calico, Cilium, Antrea). Flannel alone does **not** — your policies will silently do nothing.

```yaml
# 1. Default deny ALL ingress in a namespace (apply this first, always)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress, namespace: prod}
spec:
  podSelector: {}                 # empty = ALL pods in this namespace
  policyTypes: ["Ingress"]
---
# 2. Allow only web → api on 8080, from the same namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-web-to-api, namespace: prod}
spec:
  podSelector: {matchLabels: {app: api}}
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: {matchLabels: {app: web}}
      ports: [{protocol: TCP, port: 8080}]
---
# 3. Allow the Ingress controller (different namespace) to reach web
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-ingress, namespace: prod}
spec:
  podSelector: {matchLabels: {app: web}}
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
          podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
      ports: [{protocol: TCP, port: 80}]
---
# 4. Restrict egress: DNS + api only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: web-egress, namespace: prod}
spec:
  podSelector: {matchLabels: {app: web}}
  policyTypes: ["Egress"]
  egress:
    - to: [{podSelector: {matchLabels: {app: api}}}]
      ports: [{protocol: TCP, port: 8080}]
    - to: [{namespaceSelector: {}}]                # kube-system CoreDNS
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
```

**Selector semantics — the tricky bit:**

```yaml
from:
  - podSelector: {matchLabels: {a: b}}        # OR  (separate list items = OR)
  - namespaceSelector: {matchLabels: {c: d}}

  - namespaceSelector: {matchLabels: {c: d}}  # AND (both keys in ONE item = AND)
    podSelector: {matchLabels: {a: b}}
```

Also note: `podSelector` and `namespaceSelector` are always relative to the *NetworkPolicy's own namespace* unless combined with a namespaceSelector. And every namespace automatically carries the label `kubernetes.io/metadata.name: <its own name>` — use that to select by namespace name.

```bash
kubectl get netpol -A
kubectl describe netpol allow-web-to-api
# test:
kubectl run t1 --rm -it --image=nicolaka/netshoot --labels="app=web" --restart=Never -- bash
kubectl run t2 --rm -it --image=nicolaka/netshoot --labels="app=hacker" --restart=Never -- bash
```

### 12.7 Service mesh, briefly

A mesh (Istio, Linkerd, Cilium Service Mesh) injects a sidecar/eBPF proxy per Pod and moves L7 concerns out of your app: mTLS everywhere, retries, timeouts, circuit breaking, traffic splitting, distributed tracing, per-service metrics.

| Need | Solution |
|---|---|
| Route by host/path, TLS termination | Ingress / Gateway API |
| mTLS between services, canary by %, retries, tracing | Service mesh |
| Just "can A talk to B" enforcement | NetworkPolicy |

Start without a mesh. Add one when you have a real L7 problem (mTLS compliance, canary deployments, cross-team observability).

---

## §13 — Autoscaling

### 13.1 HPA — Horizontal Pod Autoscaler

Scales **replica count** based on metrics.

**Prerequisite:** metrics-server must be running, and containers **must set `resources.requests`** — HPA computes `desired = ceil(currentReplicas × currentMetric / targetMetric)`, and the denominator is the *request*, not the limit.

```bash
# metrics-server on kind/minikube (self-signed certs need this flag locally)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl top nodes     # if this works, HPA can work
```

```bash
# imperative
kubectl autoscale deployment web --cpu-percent=70 --min=2 --max=20
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: web}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: web}
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: {type: Utilization, averageUtilization: 70}     # % of REQUESTS
    - type: Resource
      resource:
        name: memory
        target: {type: AverageValue, averageValue: 400Mi}        # absolute, not %
    - type: Pods
      pods:
        metric: {name: http_requests_per_second}                 # custom metric
        target: {type: AverageValue, averageValue: "100"}
    - type: External
      external:
        metric: {name: sqs_queue_length, selector: {matchLabels: {queue: images}}}
        target: {type: AverageValue, averageValue: "50"}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0          # react fast going up
      policies:
        - {type: Percent, value: 100, periodSeconds: 30}      # double every 30s
        - {type: Pods, value: 4, periodSeconds: 30}
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300        # wait 5 min before shrinking (default)
      policies:
        - {type: Percent, value: 25, periodSeconds: 60}       # shed 25%/min max
      selectPolicy: Min
```

```bash
kubectl get hpa
kubectl describe hpa web       # ← shows the metric values and the scaling decisions
kubectl get hpa web -w
```

| `TARGETS` shows | Meaning |
|---|---|
| `12%/70%` | Working correctly |
| `<unknown>/70%` | metrics-server broken, or **no `requests` set**, or the metric name is wrong |
| `0%/70%` and never scales | Load isn't reaching the Pods |

> 🔑 **HPA + `limits.cpu` can fight each other.** If CPU limit == request, utilisation can never exceed 100% and throttling kicks in hard. Common practice: HPA on CPU with only *requests* set, or HPA on custom/request-rate metrics (much more predictable).

### 13.2 VPA — Vertical Pod Autoscaler

Adjusts requests/limits automatically based on history. Modes: `Off` (recommendations only), `Initial` (set at creation), `Auto` (**evicts Pods to apply new values** — needs a PDB!).

Use VPA in `Off` mode to *learn* the right numbers, then bake them into your manifests. Running VPA `Auto` and HPA-on-CPU on the same workload is a known conflict.

### 13.3 Cluster Autoscaler / Karpenter

Adds and removes **nodes** when Pods are Pending for lack of capacity, or nodes are underutilised.

- **Cluster Autoscaler:** works with node groups / ASGs. Slow-ish (minutes), scales by instance group.
- **Karpenter (AWS):** provisioner-driven, picks the right instance type per pending Pod, seconds-fast, consolidates for cost. Now CNCF and multi-cloud-ish.
- **kind/minikube:** `minikube start --nodes 3`; kind has no autoscaler — add nodes by editing the config.

```bash
kubectl get nodes -w
kubectl describe node | grep -A5 "Allocated resources"
```

### 13.4 KEDA — event-driven autoscaling, including to zero

HPA can't scale to 0 (something must be running to report metrics). **KEDA** adds scalers for Kafka lag, SQS, Prometheus queries, cron, Redis lists, HTTP traffic (via an internal router), and more. It installs its own HPA under the hood.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: {name: worker}
spec:
  scaleTargetRef: {name: worker}
  minReplicaCount: 0
  maxReplicaCount: 50
  cooldownPeriod: 300
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus-server.monitoring:9090
        metricName: queue_depth
        query: sum(queue_depth{job="worker"})
        threshold: "10"
```

### 13.5 PodDisruptionBudget — the other half of availability

Limits *voluntary* disruption (node drains, cluster upgrades, `kubectl rollout`). Does **not** protect against node crashes.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: web-pdb, namespace: prod}
spec:
  minAvailable: 2             # OR maxUnavailable: 1 — never both
  selector: {matchLabels: {app: web}}
  unhealthyPodEvictionPolicy: IfHealthyBudget   # v1.27+: can we evict already-broken pods?
```

```bash
kubectl get pdb -A
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data --grace-period=60
# if a PDB blocks it: "error when evicting Pod … Cannot evict pod as it would violate the pod's disruption budget"
kubectl drain node1 --ignore-daemonsets --force   # --force deletes bare pods, does NOT override PDBs
```

> 🔑 **`minAvailable: 1` on a 1-replica Deployment makes the node undrainable.** Set PDBs *after* you have ≥3 replicas, and use `maxUnavailable` (percentage-friendly) rather than absolute `minAvailable` when the replica count varies via HPA.

---

## §14 — Helm & Kustomize

### 14.1 The problem both solve

You have 40 YAML files × 3 environments. Copy-paste-edit is how `image: myapp:latest` ends up in production.

| | **Kustomize** | **Helm** |
|---|---|---|
| Model | Patch/overlay plain YAML — **no templating language** | Templates + values → YAML |
| Built into kubectl? | ✅ `kubectl apply -k` | ❌ separate binary |
| Learning curve | Low | Medium (Go templating) |
| Packaging / versioning / distribution | Weak | ✅ charts, semver, repos, dependencies |
| Hooks, tests, rollback | ❌ (Argo CD adds some) | ✅ `helm rollback`, `pre-install` hooks |
| Best for | Env variants of your own manifests | Distributing software (yours or third-party) |

Many teams use **both**: Helm for third-party (Prometheus, ingress-nginx), Kustomize for their own apps.

### 14.2 Kustomize in 5 minutes

```
base/
  deployment.yaml
  service.yaml
  kustomization.yaml
overlays/
  dev/kustomization.yaml
  prod/kustomization.yaml
```

```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [deployment.yaml, service.yaml]
commonLabels: {app.kubernetes.io/part-of: shop}
images:
  - {name: myapp, newTag: "1.0.0"}
```

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources: [../../base]
namePrefix: prod-
replicas:
  - {name: web, count: 5}
images:
  - {name: myapp, newName: ghcr.io/3558bhk/myapp, newTag: "1.4.2"}
patches:
  - path: hpa.yaml
  - target: {kind: Deployment, name: web}
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 1Gi
configMapGenerator:
  - name: app-config
    literals: [LOG_LEVEL=warn, ENV=prod]
    options: {disableNameSuffixHash: false}   # hash suffix → automatic rollout on change
secretGenerator:
  - name: db-creds
    envs: [.env.prod]                          # ⚠️ gitignored!
```

```bash
kubectl kustomize overlays/prod        # render, don't apply — INSPECT IT
kubectl apply -k overlays/prod
kubectl diff -k overlays/prod          # what would change (great in PR review)
kustomize build overlays/prod | kubeconform -strict -   # validate in CI
```

### 14.3 Helm in 15 minutes

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo redis
helm show values bitnami/redis | head -50

helm install my-redis bitnami/redis -n cache --create-namespace \
  --set auth.password=secret --set architecture=standalone
helm install my-redis bitnami/redis -f values-prod.yaml     # ← prefer files over --set

helm list -A
helm status my-redis -n cache
helm get values my-redis -n cache          # user-supplied values only
helm get manifest my-redis -n cache        # rendered YAML
helm upgrade my-redis bitnami/redis -f values-prod.yaml -n cache --install
helm rollback my-redis 2 -n cache
helm history my-redis -n cache
helm uninstall my-redis -n cache

helm template ./mychart                    # render locally, no cluster
helm template ./mychart --debug            # shows computed values too
helm lint ./mychart
helm install x ./mychart --dry-run=server  # server-side validation
```

**Create your own chart:**

```bash
helm create myapp
```

```
myapp/
├── Chart.yaml            # name, version (chart), appVersion (your app)
├── values.yaml           # DEFAULT values
├── values-dev.yaml       # environment overrides
├── values-prod.yaml
├── charts/               # dependencies
├── templates/
│   ├── _helpers.tpl      # named templates (labels, names)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── serviceaccount.yaml
│   ├── NOTES.txt         # printed after install
│   └── tests/test-connection.yaml
└── .helmignore
```

```yaml
# Chart.yaml
apiVersion: v2
name: myapp
description: Shop frontend
type: application
version: 0.4.1          # chart version — bump on EVERY change
appVersion: "1.4.2"     # the app's version
dependencies:
  - {name: redis, version: "20.x.x", repository: "https://charts.bitnami.com/bitnami", condition: redis.enabled}
```

```yaml
# values.yaml
replicaCount: 2
image:
  repository: ghcr.io/3558bhk/myapp
  tag: ""               # defaults to .Chart.AppVersion
  pullPolicy: IfNotPresent
service: {type: ClusterIP, port: 80}
resources:
  requests: {cpu: 100m, memory: 128Mi}
  limits:   {cpu: 500m, memory: 256Mi}
ingress:
  enabled: false
  className: nginx
  hosts: [{host: myapp.local, paths: [{path: /, pathType: Prefix}]}]
autoscaling: {enabled: false, minReplicas: 2, maxReplicas: 10, targetCPU: 70}
nodeSelector: {}
tolerations: []
affinity: {}
```

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "myapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "myapp.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "myapp.serviceAccountName" . }}
      securityContext:
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports: [{name: http, containerPort: 8080}]
          {{- with .Values.resources }}
          resources: {{ toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.probes }}
          livenessProbe: {{ toYaml .liveness | nindent 12 }}
          readinessProbe: {{ toYaml .readiness | nindent 12 }}
          {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector: {{ toYaml . | nindent 8 }}
      {{- end }}
```

**Template idioms you must know:**

| Idiom | Meaning |
|---|---|
| `{{ .Values.x }}` | Read a value |
| `{{ .Values.x | default "y" }}` | Fallback |
| `{{- if .Values.ingress.enabled }}` / `{{- end }}` | Conditional block (`-` trims whitespace) |
| `{{- range .Values.env }}` | Loop |
| `{{ toYaml .Values.resources | nindent 12 }}` | Dump a map as YAML, indented 12 (**`nindent` = newline + indent; almost always what you want**) |
| `{{ include "myapp.labels" . | nindent 4 }}` | Named template from `_helpers.tpl` |
| `{{ .Release.Name }}` / `{{ .Release.Namespace }}` / `{{ .Release.Revision }}` | Release metadata |
| `{{ .Chart.AppVersion }}` | From Chart.yaml |
| `{{ required "image.tag must be set" .Values.image.tag }}` | Fail the render with a clear message |
| `{{ tpl .Values.someString . }}` | Render a value *as* a template |
| `{{ .Files.Get "config/app.conf" }}` | Embed a file from the chart |

```bash
helm package ./myapp                    # → myapp-0.4.1.tgz
helm push myapp-0.4.1.tgz oci://ghcr.io/3558bhk/charts   # OCI registries are the modern way
helm pull oci://ghcr.io/3558bhk/charts/myapp --version 0.4.1
```

> ⚠️ **Helm gotchas**
> 1. `helm install` with an existing release name fails → use `--install` with `upgrade`, or `helm uninstall` first.
> 2. Helm stores release state in **Secrets** in the release namespace (`sh.helm.release.v1.<name>.v<rev>`). Deleting them corrupts history.
> 3. Resources Helm didn't create can't be adopted → add the right labels/annotations.
> 4. `helm uninstall` deletes everything it created — including PVCs? No, it does **not** delete PVCs created by StatefulSet `volumeClaimTemplates` (they're owned by the StatefulSet). Check for orphans.
> 5. Hooks (`"helm.sh/hook": pre-install`) are not tracked as part of the release unless you add `hook-delete-policy`.

### 14.4 GitOps with Argo CD

Git is the source of truth; a controller continuously syncs the cluster to it. No more `kubectl apply` from laptops.

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
# login: admin / <that password>  →  https://localhost:8080
argocd login localhost:8080 --insecure --username admin --password <pw>
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: shop-prod, namespace: argocd}
spec:
  project: default
  source:
    repoURL: https://github.com/3558Bhk/shop-k8s.git
    targetRevision: main
    path: overlays/prod
    # helm:  {valueFiles: [values-prod.yaml]}
    # kustomize: {images: ["myapp=ghcr.io/3558bhk/myapp:1.4.2"]}
  destination: {server: https://kubernetes.default.svc, namespace: prod}
  syncPolicy:
    automated:
      prune: true          # delete resources removed from Git
      selfHeal: true       # revert manual kubectl edits
    syncOptions: [CreateNamespace=true, ApplyOutOfSyncOnly=true, ServerSideApply=true]
    retry: {limit: 5, backoff: {duration: 5s, factor: 2, maxDuration: 3m}}
  revisionHistoryLimit: 10
```

**The GitOps flow:**

```
git push  →  CI builds image, tags it (git SHA), updates the image tag in the config repo
          →  Argo CD detects drift  →  syncs  →  cluster matches Git
          →  rollback = git revert (and Argo syncs back)
```

**App-of-apps** (one Application that manages other Applications) is how you bootstrap a whole cluster from Git:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: root, namespace: argocd}
spec:
  project: default
  source: {repoURL: https://github.com/3558Bhk/platform.git, targetRevision: main, path: apps}
  destination: {server: https://kubernetes.default.svc, namespace: argocd}
  syncPolicy: {automated: {prune: true, selfHeal: true}}
```

**Argo CD vs Argo Rollouts:** Argo CD = *delivery* (get Git state into the cluster). Argo Rollouts = *progressive delivery* (canary/blue-green with automated analysis). Use both together for real zero-risk deploys.

```bash
argocd app list
argocd app get shop-prod
argocd app sync shop-prod --prune
argocd app diff shop-prod
argocd app history shop-prod && argocd app rollback shop-prod 3
```

> 🔑 **`selfHeal: true` means `kubectl edit` is pointless** — Argo CD reverts it within minutes. That's the point. Change Git.

### 14.5 Progressive delivery patterns

| Pattern | How | Risk |
|---|---|---|
| **Rolling update** | Deployment default (`maxSurge`/`maxUnavailable`) | Low; automatic rollback only on probe failure |
| **Recreate** | `strategy.type: Recreate` | Downtime; use only when required |
| **Blue/Green** | Two Deployments (`-blue`, `-green`), switch the Service selector | Instant rollback; needs 2× resources |
| **Canary** | Two Deployments behind one Service with replica ratio, or Argo Rollouts / Gateway API weights | Best for real traffic-based validation |
| **A/B** | Route by header/cookie at the Ingress/Gateway | Needs L7 routing rules |

```bash
# Blue/green switch in one command
kubectl patch service web -p '{"spec":{"selector":{"version":"green"}}}'
# verify, then rollback
kubectl patch service web -p '{"spec":{"selector":{"version":"blue"}}}'
```

---

## §15 — Observability

### 15.1 Logs

```bash
kubectl logs <pod>                              # current container
kubectl logs <pod> -c <container>               # specific container
kubectl logs <pod> --previous                   # ⭐ the crashed instance — THE debugging command
kubectl logs <pod> -f --tail=100 --timestamps
kubectl logs -l app=web --all-containers --prefix --max-log-requests=10
kubectl logs deploy/web                         # works on any workload
kubectl logs job/migrate
kubectl logs <pod> --since=10m --since-time=2026-09-09T10:00:00Z
kubectl logs <pod> --limit-bytes=1048576
stern web -n prod --tail 50                     # ⭐ multi-pod, colourised, regex on pod name
stern . -n prod --exclude-container istio-proxy
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

**Node-level log locations** (when the API won't give you logs):

```
/var/log/containers/*.log     symlinks to the below
/var/log/pods/<ns>_<pod>_<uid>/<container>/*.log
journalctl -u kubelet -f      kubelet itself
journalctl -u containerd -f   the runtime
crictl logs <container-id>    on the node, bypassing the API
```

**Production logging stack:** DaemonSet collector (Fluent Bit / Vector) → tail `/var/log/containers` → enrich with K8s metadata → ship to Loki / Elasticsearch / OpenSearch → query in Grafana / Kibana. Never `kubectl logs` in an incident; have a log UI.

Loki + Promtail in 3 lines:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack -n logging --create-namespace \
  --set promtail.enabled=true --set grafana.enabled=true
kubectl port-forward -n logging svc/loki-grafana 3000:80   # admin / in the grafana secret
```

### 15.2 Events — the underrated goldmine

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -40
kubectl get events -n prod --field-selector involvedObject.name=web-abc
kubectl get events -A --field-selector type=Warning
kubectl describe pod web-abc | sed -n '/Events/,$p'
kubectl describe node node1 | sed -n '/Conditions/,/Addresses/p'
kubectl describe deployment web
kubectl get events -A -w               # live firehose during a deploy
```

> ⚠️ **Events expire after ~1 hour by default** (`--event-ttl`). If you're debugging something that happened yesterday, they're gone — that's why you ship them (kube-events-exporter → Loki).

Event reasons worth recognising instantly:

| Reason | Meaning |
|---|---|
| `Scheduled` | Scheduler picked a node |
| `Pulling` / `Pulled` | Image pull |
| `Failed to pull image` | Tag wrong, registry auth, network |
| `Created` / `Started` | Container lifecycle |
| `Unhealthy` | A probe failed (message says which) |
| `BackOff` | CrashLoopBackOff |
| `FailedMount` / `FailedAttachVolume` | Volume problem |
| `OOMKilling` | Memory limit exceeded |
| `Evicted` | Node resource pressure |
| `Preempted` | A higher-priority Pod took the slot |
| `FailedScheduling` | No feasible node (message says why) |
| `NetworkNotReady` | CNI hasn't assigned an IP yet |
| `ProbeWarning` | Probe flapping |
| `Unschedulable` | Node cordoned |

### 15.3 Metrics

```bash
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl top pods -n prod --containers
kubectl describe node node1 | grep -A8 "Allocated resources"
```

These come from **metrics-server** (in-memory, ~60 s resolution, 15 min history — *not* a monitoring system).

**Real monitoring = kube-prometheus-stack:**

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f kps-values.yaml

kubectl port-forward -n monitoring svc/kps-grafana 3000:80        # admin / prom-operator
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093
```

That one Helm install gives you: Prometheus, Grafana (with 20+ prebuilt dashboards), Alertmanager, node-exporter (DaemonSet), kube-state-metrics, and ServiceMonitors for all control-plane components.

**Scrape your own app** with a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: api, namespace: prod, labels: {release: kps}}   # ← label MUST match Prometheus's selector
spec:
  selector: {matchLabels: {app: api}}
  namespaceSelector: {matchNames: [prod]}
  endpoints:
    - {port: metrics, interval: 30s, path: /metrics}
```

**Metrics you must know:**

| Metric | From | Tells you |
|---|---|---|
| `container_cpu_usage_seconds_total` | cAdvisor | Real CPU burn |
| `container_cpu_cfs_throttled_periods_total` | cAdvisor | **CPU throttling** — the silent performance killer |
| `container_memory_working_set_bytes` | cAdvisor | What OOMKiller looks at |
| `kube_pod_status_phase` | kube-state-metrics | Pending/Failed counts |
| `kube_pod_container_status_restarts_total` | kube-state-metrics | Crash looping |
| `kube_pod_container_status_last_terminated_reason` | kube-state-metrics | `OOMKilled`, `Error` |
| `kube_deployment_status_replicas_available` | kube-state-metrics | Under-replicated |
| `kube_node_status_condition{condition="Ready"}` | kube-state-metrics | NotReady nodes |
| `node_memory_MemAvailable_bytes` | node-exporter | Node memory pressure |
| `node_filesystem_avail_bytes` | node-exporter | Disk pressure → evictions |
| `apiserver_request_duration_seconds` | API server | Control-plane latency |

**Useful PromQL:**

```promql
# CPU throttling ratio per pod — >0.25 means your limit is too low
rate(container_cpu_cfs_throttled_periods_total[5m])
  / rate(container_cpu_cfs_periods_total[5m])

# Memory usage vs limit
container_memory_working_set_bytes{namespace="prod"}
  / on(pod) kube_pod_container_resource_limits{resource="memory"}

# Pods restarting more than 3 times in 10 min
increase(kube_pod_container_status_restarts_total[10m]) > 3

# Deployment has fewer ready replicas than desired
kube_deployment_status_replicas_available < kube_deployment_spec_replicas
```

**Alerts you should have on day one:** Pod not ready > 5 min · CrashLoop (restarts > 3 in 10 min) · Node NotReady > 2 min · Deployment under-replicated > 5 min · PVC usage > 85% · Node disk > 85% · CPU throttling > 50% sustained · 5xx rate at the Ingress · Certificate expiry < 14 days · etcd leader changes.

### 15.4 Debugging toolkit

```bash
kubectl describe pod/node/svc/deploy <name>       # the #1 tool
kubectl get <x> -o yaml | less                    # full truth, including status
kubectl get pod x -o jsonpath='{.status.conditions}'
kubectl explain deployment.spec.strategy          # built-in documentation
kubectl diff -f file.yaml                         # what would change
kubectl apply -f file.yaml --dry-run=server -o yaml   # full server-side validation
kubectl debug -it web-abc --image=nicolaka/netshoot --target=app   # ephemeral container, shares namespaces
kubectl debug node/node1 -it --image=busybox:1.37                  # shell ON the node (host namespaces)
kubectl get --raw '/api/v1/namespaces/prod/pods/web-abc/proxy/metrics'
kubectl proxy --port=8001 &  curl localhost:8001/api/v1/nodes      # raw API access
kubectl cluster-info dump | less                  # EVERYTHING, for support tickets
```

**`nicolaka/netshoot`** is the debug image to memorise: curl, wget, dig, nslookup, tcpdump, ngrep, iperf3, mtr, nmap, socat, jq, httpie, grpcurl, tshark.

```bash
kubectl run netshoot --rm -it --image=nicolaka/netshoot --restart=Never -- bash
```

**Ephemeral containers** (v1.25+) let you add a debug container to a *running* Pod sharing its namespaces — invaluable when your distroless image has no shell:

```bash
kubectl debug -it myapp-xyz --image=busybox:1.37 --target=app --share-processes
# now `ps aux` shows the app's processes; you can read /proc/<pid>/root/…
```

---

## §16 — Troubleshooting: the complete decision tree

### 16.1 The universal first three commands

```bash
kubectl get pods -o wide                       # STATUS + RESTARTS + NODE + IP
kubectl describe pod <pod> | sed -n '/Events/,$p'
kubectl logs <pod> --previous --tail=100
```

80% of problems are solved by these three. The remaining 20% are below.

### 16.2 Master decision tree

```
Pod not Running?
├── STATUS = Pending
│   └── describe → FailedScheduling?
│       ├── Insufficient cpu/memory      → §10.6 (lower requests / add nodes)
│       ├── untolerated taint            → add toleration
│       ├── node affinity/selector       → check node labels
│       ├── topology spread              → relax maxSkew
│       └── unbound PVC                  → §8.7
│   └── No events at all?                → scheduler down? `kubectl get pods -n kube-system`
│
├── STATUS = ImagePullBackOff / ErrImagePull
│   ├── name/tag typo                    → `docker manifest inspect <img>` locally
│   ├── private registry, no secret      → imagePullSecrets (§7.4)
│   ├── :latest not present on node      → imagePullPolicy + kind load / minikube image load
│   ├── arch mismatch (arm64 vs amd64)   → buildx multi-arch
│   └── rate limit (Docker Hub)          → pull-through cache / mirror
│
├── STATUS = CreateContainerConfigError
│   └── missing ConfigMap/Secret/key     → `kubectl get cm,secret`; check key names EXACTLY
│
├── STATUS = CrashLoopBackOff
│   ├── `logs --previous` shows an error → fix the app
│   ├── Exit 0 but restartPolicy Always  → container exits immediately; wrong command?
│   ├── Exit 1/2                         → app config, missing dependency, DB unreachable
│   ├── Exit 126                         → not executable → check image ENTRYPOINT/permissions
│   ├── Exit 127                         → command not found → typo in `command:`
│   ├── Exit 137                         → OOMKilled (raise limits) OR SIGKILL after grace period
│   ├── Exit 139                         → segfault
│   ├── Exit 143                         → SIGTERM (normal on shutdown; abnormal at startup = something killing it)
│   └── No logs at all                   → wrong `command:`/`args:`, or logging to a file not stdout
│
├── STATUS = Running but READY 0/1
│   └── describe → readiness probe failing
│       ├── wrong path/port              → `kubectl exec -- curl -v localhost:<port><path>`
│       ├── app still starting           → add a startupProbe
│       └── dependency down              → that's the readiness probe WORKING; fix the dependency
│
├── STATUS = Running, READY 1/1, but restarts climbing
│   └── describe → Last State: Terminated, Reason: OOMKilled / Error
│       └── liveness probe too aggressive → raise failureThreshold / fix the endpoint
│
├── Pod Evicted
│   └── `kubectl describe node <node>` → MemoryPressure / DiskPressure / PIDPressure
│       ├── find the hog: `kubectl top pods -A --sort-by=memory`
│       ├── clean images: nodes auto-GC, but check `crictl images` / `df -h /var/lib/containerd`
│       └── delete the Evicted shells: `kubectl delete pods -A --field-selector status.phase=Failed`
│
└── Pod Terminating forever
    ├── finalizers                       → `kubectl get pod x -o yaml | grep -A5 finalizers`
    ├── app ignores SIGTERM              → shell as PID 1? use exec form / tini (§9.7)
    ├── volume detach stuck              → `kubectl get volumeattachment`
    └── force (LAST RESORT, can orphan resources):
        `kubectl delete pod x --grace-period=0 --force`
```

### 16.3 Service returns nothing

```bash
# 1. Are the Pods actually Ready?
kubectl get pods -l app=api
# 2. Does the Service have endpoints?  ← THE key check
kubectl get endpointslices -l kubernetes.io/service-name=api
kubectl describe svc api | grep -i endpoints
# 3. Does the selector match the POD labels (not the deployment labels)?
kubectl get svc api -o jsonpath='{.spec.selector}' && echo
kubectl get pods --show-labels
# 4. Is targetPort the CONTAINER port?
kubectl get svc api -o yaml | grep -A3 ports
kubectl get pod <pod> -o jsonpath='{.spec.containers[0].ports}'
# 5. Test from inside the cluster
kubectl run t --rm -it --image=nicolaka/netshoot --restart=Never -- bash
  curl -v http://api:8080/health
  dig +short api.default.svc.cluster.local
  nc -zv api 8080
# 6. Test the Pod directly, bypassing the Service
kubectl exec <pod> -- curl -s localhost:8080/health
kubectl port-forward pod/<pod> 8080:8080 && curl localhost:8080/health
# 7. kube-proxy healthy?
kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

**Empty endpoints → 99% selector mismatch or Pods not Ready.**

### 16.4 DNS problems

```bash
kubectl run dns --rm -it --image=nicolaka/netshoot --restart=Never -- bash
  dig +short kubernetes.default.svc.cluster.local
  dig +short api
  cat /etc/resolv.conf
  dig @10.96.0.10 api.default.svc.cluster.local    # CoreDNS ClusterIP directly

kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
kubectl get svc kube-dns -n kube-system
kubectl get configmap coredns -n kube-system -o yaml
```

| Symptom | Cause | Fix |
|---|---|---|
| 5 s delays on every lookup | `ndots:5` + external domain → 4 failed cluster searches first | Use FQDN with trailing dot: `api.example.com.` or set `dnsConfig.options: [{name: ndots, value: "2"}]` |
| Intermittent `SERVFAIL` / timeouts | conntrack race on UDP (Linux kernel) | Use TCP DNS, or NodeLocal DNSCache |
| NXDOMAIN for a service that exists | Wrong namespace in the short name | Use `svc.other-ns` |
| All DNS broken | CoreDNS down / no nodes available | Restart CoreDNS, check node capacity |

**NodeLocal DNSCache** fixes both classic problems (UDP conntrack races + per-query load on CoreDNS) by running a caching DNS DaemonSet on every node.

### 16.5 Networking / connectivity

```bash
# Is it DNS, routing, or the app?
kubectl exec <pod> -- getent hosts api           # DNS resolution
kubectl exec <pod> -- nc -zv api 8080            # TCP reachability
kubectl exec <pod> -- curl -sv http://api:8080/  # full HTTP
kubectl exec <pod> -- ip route
kubectl exec <pod> -- cat /etc/resolv.conf

# Node level
kubectl debug node/node1 -it --image=nicolaka/netshoot
  ip a; ip route; iptables-save | grep <clusterip>
  nft list ruleset | head -50                    # nftables mode (default in v1.33+)
  ss -tlnp
  tcpdump -i any port 8080 -nn

# NetworkPolicy blocking you?
kubectl get netpol -A
kubectl describe netpol -n prod
# temporarily test: delete the deny policy in a DEV namespace only
```

### 16.6 Ingress returns 404 / 502 / 503

| Code | Usual cause | Check |
|---|---|---|
| **404** | No Ingress rule matches the Host/path, or `ingressClassName` wrong, or the controller isn't watching this namespace | `kubectl describe ingress`; `curl -H "Host: x"`; controller logs |
| **502** | Backend Pod refused the connection / crashed mid-request / wrong `targetPort` | `kubectl get endpointslices`; Pod logs |
| **503** | No ready endpoints (readiness failing) or all backends down | `kubectl get endpointslices` — empty = readiness |
| **504** | Backend too slow; `proxy-read-timeout` (60 s default) | Raise the annotation; fix the slow endpoint |
| **413** | Body bigger than `proxy-body-size` (1 m default) | Annotation |
| **499** | Client closed early (nginx-specific) | Usually client timeouts; check upstream latency |
| **TLS error** | Wrong/missing Secret, hostname mismatch, cert not Ready | `kubectl get certificate`; `openssl s_client -connect host:443 -servername host` |

```bash
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=200 -f
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -T | grep -A20 'server_name shop'
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- curl -s localhost:10246/healthz
kubectl describe ingress shop
```

### 16.7 Node problems

```bash
kubectl get nodes -o wide
kubectl describe node node1
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[*]}{.type}={.status} {end}{"\n"}{end}'
```

| Condition `True` | Meaning | Action |
|---|---|---|
| `Ready` | Healthy | — |
| `MemoryPressure` | Below eviction threshold | Find hogs, add RAM, set proper limits |
| `DiskPressure` | Rootfs or imagefs low | Clean images/logs, expand disk |
| `PIDPressure` | Too many processes | Check for fork bombs, raise `--pod-max-pids` |
| `NetworkUnavailable` | CNI failed | CNI DaemonSet logs |
| `NotReady` | kubelet not heartbeating (>40 s) | `journalctl -u kubelet`, node reachable? |

```bash
kubectl cordon node1                    # mark unschedulable (existing pods stay)
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data --grace-period=60
kubectl uncordon node1
ssh node1 'sudo systemctl status kubelet; sudo journalctl -u kubelet -n 200 --no-pager'
sudo crictl ps -a ; sudo crictl images ; sudo crictl stats
sudo journalctl -u containerd -n 200
```

### 16.8 Control plane problems

```bash
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
kubectl get componentstatuses           # deprecated but still informative on kubeadm clusters
kubectl get pods -n kube-system
kubectl -n kube-system logs kube-apiserver-node1 --tail=100
kubectl -n kube-system logs etcd-node1 --tail=100
kubectl get apiservices | grep -v True  # broken aggregated API servers (metrics-server, custom metrics)
kubectl get leases -n kube-node-lease   # node heartbeats
```

Slow `kubectl`? Usually API server latency or a huge list response:

```bash
time kubectl get pods -A -o name | wc -l     # how many objects are you asking for?
kubectl get pods -A --chunk-size=500         # server-side pagination
kubectl api-resources --verbs=list -o name | xargs -n1 kubectl get --show-kind --ignore-not-found -A > all.txt
```

### 16.9 etcd & backups

```bash
# kubeadm clusters: etcd runs as a static pod
kubectl -n kube-system exec etcd-master -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table

# snapshot backup (DO THIS ON A SCHEDULE)
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%F).db \
  --endpoints=https://127.0.0.1:2379 --cacert=… --cert=… --key=…
etcdctl snapshot status /backup/etcd-2026-09-09.db --write-out=table

# restore (destroys current data — this is disaster recovery)
etcdctl snapshot restore /backup/etcd-2026-09-09.db --data-dir /var/lib/etcd-restore
```

Also back up: `/etc/kubernetes/` (certs, manifests, admin.conf), your PV data (Velero), and **Git** (which should hold all your manifests).

### 16.10 The 10 real-time scenarios interviewers ask

| # | Scenario | First 3 commands |
|---|---|---|
| 1 | "Pod is CrashLoopBackOff" | `describe pod` → `logs --previous` → check exit code + probe config |
| 2 | "Deployment rolled out and now 502s" | `rollout status` + `rollout history` → `get endpointslices` → readiness probe? → `rollout undo` |
| 3 | "PVC stuck Pending" | `describe pvc` → `get sc` → provisioner logs |
| 4 | "Service works from the Pod but not from another namespace" | `get endpointslices` → FQDN `svc.ns.svc.cluster.local` → NetworkPolicy |
| 5 | "Node went NotReady, what happens to its Pods?" | `describe node` → after ~40 s node controller marks it; after `tolerationSeconds` (default 300) Pods are evicted and rescheduled; StatefulSet Pods **won't** reschedule until the node is confirmed gone (safety) |
| 6 | "App is OOMKilled but `kubectl top` shows low memory" | `top` samples at 60 s; OOM is instantaneous. Check `container_memory_working_set_bytes` max over time, JVM/V8 heap settings, and `limits` vs actual peak |
| 7 | "HPA shows `<unknown>/70%`" | `get apiservices` (metrics-server) → `kubectl top pods` → are `requests` set? |
| 8 | "Can't drain a node" | `get pdb -A` → which Pod is blocking → `kubectl drain --dry-run` |
| 9 | "Ingress returns 404 for a new service" | `describe ingress` → `ingressClassName` → controller watching this namespace? → `get endpointslices` |
| 10 | "Config change didn't take effect" | env vs volume vs subPath (§7.2) → `rollout restart` → `immutable` ConfigMap? |

---

## §17 — Docker → Kubernetes translation table

| You did this in Docker | The Kubernetes equivalent |
|---|---|
| `docker run -d nginx` | Deployment + Pod (never a bare Pod) |
| `docker run -p 8080:80` | Service (`port: 8080, targetPort: 80`) + NodePort/Ingress |
| `docker run -e FOO=bar` | ConfigMap → `envFrom` |
| `docker run --env-file .env` | ConfigMap/Secret → `envFrom` |
| `docker run -v data:/data` | PVC → `volumeMounts` |
| `docker run -v $(pwd)/cfg:/etc/app:ro` | ConfigMap volume, `readOnly: true` (bind mounts ≈ `hostPath`, dev only) |
| `docker run -m 512m --cpus 0.5` | `resources.limits` |
| `docker run --restart=always` | Deployment (implicit) / `restartPolicy: Always` |
| `docker run --name x --network y` | Pod name (generated) + namespace + NetworkPolicy |
| `docker run --user 1000` | `securityContext.runAsUser` |
| `docker run --read-only --tmpfs /tmp` | `readOnlyRootFilesystem: true` + `emptyDir` at `/tmp` |
| `docker exec -it x sh` | `kubectl exec -it pod/x -- sh` |
| `docker logs -f x` | `kubectl logs -f pod/x` |
| `docker inspect x` | `kubectl get pod x -o yaml` / `describe` |
| `docker cp x:/f ./f` | `kubectl cp x:/f ./f` |
| `docker stats` | `kubectl top pods` |
| `docker build -t app:1 .` | Same — build the image, push it, reference it in the manifest |
| `docker compose up` | Many manifests + `kubectl apply -k` / Helm; or **Kompose** to convert |
| `docker compose --scale web=3` | `kubectl scale deploy/web --replicas=3` |
| `docker network create` | Namespace + Service + NetworkPolicy (networks are implicit & flat) |
| `docker system prune` | Nothing equivalent — GC is automatic; you clean up with `kubectl delete` |
| `HEALTHCHECK` | liveness + readiness + startup probes |
| `ENTRYPOINT` / `CMD` | `command` / `args` |
| Swarm `docker service create` | Deployment |
| Swarm `docker stack deploy` | `kubectl apply -f` / `helm install` |
| Swarm secrets | Secrets (with `*_FILE` mount convention) |
| `docker save` / `load` | `kind load docker-image` / `minikube image load` |

**Kompose** converts Compose files to Kubernetes manifests as a starting point (output always needs review):

```bash
brew install kompose
kompose convert -f docker-compose.yaml --out k8s/
kompose convert --controller=statefulset      # for services with volumes
kompose convert --build=local                 # build the images too
```

---

## §18 — Where to go next

You now have the theory. Go break things in a controlled way:

1. **[`04-PROJECT-1-first-pod.md`](04-PROJECT-1-first-pod.md)** — get a cluster, run a Pod, debug it deliberately.
2. **[`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md)** — if you only have one day, follow this instead and skim the rest.
3. **[`02-CAPSTONE-END-TO-END.md`](02-CAPSTONE-END-TO-END.md)** — when Projects 1–7 feel easy.
4. **[`19-KUBECTL-COMPLETE-REFERENCE.md`](19-KUBECTL-COMPLETE-REFERENCE.md)** — keep open in a tab forever.

**Certifications, if that's your goal:**

| Cert | Level | What it proves |
|---|---|---|
| **KCNA** | Associate | Concepts only, multiple choice |
| **CKA** | Administrator | Hands-on, 2 h, build & fix clusters. **The one employers ask for.** |
| **CKAD** | Developer | Hands-on, app-focused: Deployments, probes, Jobs, Services |
| **CKS** | Security | Hands-on, requires CKA first. Hardening, supply chain, runtime security |

CKA/CKAD/CKS are performance-based: you get a terminal and a broken cluster. Reading won't pass them; *these project files will*, if you actually type the commands.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
