# 07 · Kubernetes

The highest-weight topic for DevOps/SRE/Platform roles. Expect **architecture**, **workload controllers**, **networking**, **scheduling**, **storage**, **security**, **operators**, and at least one long troubleshooting scenario.

*Versions referenced: Kubernetes 1.37 (Aug 2026); supported window is 1.35 / 1.36 / 1.37. Notable recent graduations: **User Namespaces** and **Mutating Admission Policies** (GA in 1.36 "Haru"), in-place pod resize, Dynamic Resource Allocation, and continued cgroup v1 deprecation.*

---

## 🟢 Basic

### 1. Architecture — control plane and node components
**Control plane:**
| Component | Role | Failure symptom |
|---|---|---|
| **kube-apiserver** | The *only* component that talks to etcd. REST front-end: authn → authz → admission → validation → etcd. Horizontally scalable, stateless | Everything stops. `kubectl` times out, controllers can't reconcile |
| **etcd** | Distributed KV store (Raft), the entire cluster state | Read-only or unavailable cluster; needs odd member count (3/5) |
| **kube-scheduler** | Watches unscheduled pods, filters + scores nodes, writes `spec.nodeName` | Pods stuck `Pending` |
| **kube-controller-manager** | All the core controllers (Deployment, ReplicaSet, Node, Job, EndpointSlice, Namespace, ServiceAccount…) | Workloads stop self-healing; scale changes not applied |
| **cloud-controller-manager** | Cloud-specific: LoadBalancer provisioning, node lifecycle, routes | `Service type=LoadBalancer` stuck `<pending>` |

**Node:**
| Component | Role |
|---|---|
| **kubelet** | Agent: talks to the CRI runtime, manages pod lifecycle, probes, volumes, reports node/pod status |
| **Container runtime** | containerd or CRI-O → runc (see topic 06) |
| **kube-proxy** | Implements Services: programs iptables/IPVS/nftables rules (or nothing, with an eBPF datapath like Cilium) |
| **CNI plugin** | Pod networking: IPAM, veth setup, network policy (Calico/Cilium/Flannel/Weave/vendor CNI) |
| **CSI driver** | Storage: attach/mount volumes |

**The declarative loop — say this explicitly:**
> "Kubernetes is a set of **reconciliation loops**. You declare desired state in an object's `spec`; a controller observes actual `status` and acts to reduce the difference, forever, level-triggered. The apiserver is the only writer to etcd, and every component watches it via **list-watch** (with a local informer cache) rather than polling. That's why you don't write imperative 'start 3 containers' — you write 'I want 3' and the system converges."

**Level-triggered vs edge-triggered** is the deep point: controllers act on the *current* difference, not on *events they might have missed*. Missed events self-heal on the next resync. That's what makes the system robust — and it's why writing an operator that only reacts to watch events (without a periodic resync) is a bug.

### 2. Pod lifecycle and container states
```
Pending ──► Running ──► Succeeded
   │           │  └───► Failed
   │           └──► (crash) ──► CrashLoopBackOff (a *waiting reason*, not a phase)
   └──► (unschedulable / pulling image)
Unknown ── node stopped reporting
```
**Startup sequence for one container:**
1. Scheduled (`spec.nodeName` set by the scheduler).
2. kubelet creates the **pause/sandbox** container → holds the network namespace (all containers in the pod share it).
3. CNI assigns an IP, sets up veth/routes/policy.
4. Volumes attached + mounted (CSI).
5. Secrets/ConfigMaps projected into the pod (as tmpfs mounts).
6. **Init containers run sequentially**, each to completion. Sidecar containers (native, 1.28+) start before regular containers and are kept alive for the pod's lifetime.
7. `postStart` hook (async, no ordering guarantee vs the entrypoint).
8. Containers start; **`startupProbe`** runs until it succeeds (or the pod is killed), then liveness+readiness begin.
9. Endpoint added to the Service/EndpointSlice **only when Ready**.

**Termination sequence — the most-asked detail:**
1. Pod marked `Terminating`; **removed from EndpointSlices immediately** (so new traffic stops — but propagation is asynchronous, see Q13).
2. `preStop` hook runs (e.g. `sleep 5`, or an HTTP call to drain).
3. **SIGTERM** sent to PID 1 of each container.
4. Grace period (`terminationGracePeriodSeconds`, default **30s**) counts **from the start of preStop**, not from SIGTERM — a common misunderstanding.
5. If still running at expiry → **SIGKILL** (exit 137).
6. Volumes unmounted, sandbox torn down, finalizers run.

**Why the `preStop: sleep 5` idiom exists:** endpoint removal and kube-proxy rule updates are *eventually* consistent. If the app exits the instant SIGTERM arrives, in-flight and newly-routed requests can hit a dead pod. Sleeping before SIGTERM lets the propagation finish while the app is still serving. **That is the correct answer to "why do we get 502s during rolling deploys?"**

### 3. Probes — the three types and how to configure them correctly
| Probe | Purpose | On failure |
|---|---|---|
| **startupProbe** | "Has it finished starting?" | Kills the pod after `failureThreshold × periodSeconds`. **Disables liveness/readiness until it succeeds** — this is how you protect slow-starting apps |
| **livenessProbe** | "Is it deadlocked/unrecoverable?" | **Restarts the container.** Never removes it from traffic |
| **readinessProbe** | "Can it serve traffic?" | Removes from EndpointSlices. **Does not restart** |

```yaml
startupProbe:
  httpGet: { path: /healthz, port: 8080 }
  failureThreshold: 30          # 30 × 5s = up to 150s to start
  periodSeconds: 5
livenessProbe:
  httpGet: { path: /healthz, port: 8080 }
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3           # 30s of failure before restart
readinessProbe:
  httpGet: { path: /ready, port: 8080 }
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 2
  successThreshold: 1
```
**The mistakes that get you:**
- **Liveness checking a dependency.** `liveness: /health` that queries Postgres → Postgres blips → *every* pod fails liveness → the Deployment restarts all pods at once → full outage caused by the probe. **Liveness must test only the process's own health** (deadlock, event loop stalled). Readiness may check dependencies.
- **No startupProbe for a slow app.** A JVM taking 90s to start gets killed by liveness at 30s, restarts, gets killed again → permanent CrashLoopBackOff. StartupProbe is the fix (not a huge `initialDelaySeconds`, which then delays real failure detection).
- **Readiness == liveness.** Different questions, different endpoints. Readiness should fail when the pod is overloaded or its dependencies are down, so traffic shifts away *without* restarting.
- **`timeoutSeconds: 1` default** is too tight under load → false failures. Set 2–5s.
- **Probes run from the kubelet**, not from other pods — so a NetworkPolicy blocking kubelet access breaks probes. And they count against the container's CPU; a heavy `/health` endpoint that queries the DB on every probe is a self-inflicted load source.
- **No probe at all** means "always ready" → traffic to a starting pod → 502s.

### 4. Deployments, ReplicaSets, and rollout strategies
```
Deployment ──owns──► ReplicaSet (new) ──owns──► Pods
             └─owns──► ReplicaSet (old, scaled to 0, kept for rollback)
```
You **never edit a ReplicaSet**. The Deployment controller creates a new RS when `spec.template` changes, and scales old→new according to the strategy.

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 25%     # or 0 — the safe choice
    maxSurge: 25%           # extra pods above the desired count
```
- **`maxUnavailable: 0` + `maxSurge: 1`** = never below desired capacity; requires headroom. The safe default for anything customer-facing.
- **`maxUnavailable: 1` + `maxSurge: 0`** = no extra capacity needed, but capacity dips during rollout.
- Rollout proceeds only when new pods are **Ready** — so readiness gates the rollout, and a broken image stalls the deployment rather than taking everything down (`progressDeadlineSeconds` marks it failed).

**Other strategies:**
| Strategy | How | When |
|---|---|---|
| **Rolling update** | Native | Default; schema-compatible changes |
| **Recreate** | `strategy: {type: Recreate}` — kill all, then start all | Single-instance stateful apps, or when old+new can't coexist. **Downtime** |
| **Blue/green** | Two Deployments + switch a Service selector (or an Ingress/LB) | Instant rollback, needs 2× capacity, full-environment validation |
| **Canary** | Second Deployment at low replica count; split traffic with a Service mesh / Ingress weights / Argo Rollouts / Flagger | Progressive delivery with metric-based auto-promotion or auto-rollback |
| **A/B** | Route by header/cookie/user segment (mesh or ingress annotations) | Feature testing |
| **Shadow/mirror** | Duplicate live traffic to the new version, discard responses | Validating against real traffic with zero user risk |

**Rollback:** `kubectl rollout undo deploy/x` (reverts to the previous RS's template), `--to-revision=N`. **Keep `revisionHistoryLimit` sensible** (default 10). And note: rollback restores the *pod template*, not the ConfigMap/Secret/database schema it depended on — **that's why backwards-compatible schema changes matter** (see Q22).

### 5. Services — the four types and how traffic actually flows
| Type | Behaviour | Use |
|---|---|---|
| **ClusterIP** (default) | Virtual IP inside the cluster; kube-proxy DNATs to pod IPs | Internal service discovery |
| **NodePort** | Opens a port (30000–32767) on **every** node, forwarding to the ClusterIP | Exposing without an LB; debugging; often the backend for an external LB |
| **LoadBalancer** | Asks the cloud controller to provision an external LB pointing at NodePorts (or directly at pods) | Public/private cloud exposure — one LB per Service, which gets expensive |
| **ExternalName** | A **CNAME** — no proxying, no ClusterIP | Referencing an external DNS name as if it were in-cluster. Careful: no policy, and it bypasses NetworkPolicy |
| **(Headless)** `clusterIP: None` | DNS returns **all pod IPs** (A records), no virtual IP | StatefulSets, client-side load balancing, when you need per-pod addressing |

**The mechanics:**
1. A Service gets a **ClusterIP** from the service CIDR — an IP that exists nowhere as an interface. It's purely a DNAT target.
2. **EndpointSlices** (replaced Endpoints for scale) hold the list of ready pod IPs+ports for that Service.
3. kube-proxy watches EndpointSlices and programs **iptables/IPVS/nftables** rules on every node. iptables mode is O(n) rule traversal — slow past a few thousand services; **IPVS** is a hash table (O(1)) with real LB algorithms (rr, lc, sh); **eBPF (Cilium)** replaces kube-proxy entirely.
4. **DNS**: CoreDNS serves `<svc>.<ns>.svc.cluster.local` → ClusterIP. Same-namespace lookups can use the short name (`db`), which is why `DATABASE_HOST=db` works. Search domains in `/etc/resolv.conf` (`ndots:5` default) cause a well-known performance problem — see Q14.
5. **`sessionAffinity: ClientIP`** exists but is coarse; prefer application-level session state or consistent hashing at the ingress.

**Critical caveat:** **`kube-proxy` load-balances per-connection, not per-request.** With keep-alive HTTP connections, one client can pin to one backend pod for a long time → uneven load. This is a real production issue and the answer is: shorter idle timeouts, L7 load balancing (mesh/ingress), or connection recycling. Naming it is a strong signal.

### 6. ConfigMaps and Secrets
```yaml
# As env
envFrom: [{ configMapRef: { name: app-config } }]
env: [{ name: DB_HOST, valueFrom: { configMapKeyRef: { name: db, key: host } } }]
# As files
volumes: [{ name: cfg, configMap: { name: app-config } }]
volumeMounts: [{ name: cfg, mountPath: /etc/app, readOnly: true }]
```
**What everyone gets wrong:**
- **Env vars do NOT update** when the ConfigMap changes. **Volume mounts DO** update — but only after kubelet's sync period (up to ~1 minute, plus cache TTL), and **not at all for `subPath` mounts**. So "hot reload" requires the app to watch its config files.
- **Changing a ConfigMap does not restart pods.** You must trigger a rollout: `kubectl rollout restart deploy/x`, or (much better) put a **checksum annotation** on the pod template so a config change automatically changes the template hash:
  ```yaml
  annotations:
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  ```
  Or use **Reloader** / **configmap-reload** sidecars.
- **Secrets are base64, not encrypted.** Anyone with `get secret` can read them. Real protection = **RBAC** (nobody should list secrets cluster-wide), **encryption at rest** (`EncryptionConfiguration` with KMS v2), **external secrets** (Vault, AWS Secrets Manager, External Secrets Operator, Sealed Secrets, SOPS+age), and **short-lived credentials** (IRSA/workload identity, Vault dynamic secrets).
- Secrets mounted as files land on **tmpfs** (not written to disk on the node) — better than env vars, which leak into `/proc/<pid>/environ`, child processes, crash dumps and `kubectl describe`.
- **Immutable ConfigMaps/Secrets** (`immutable: true`) reduce apiserver watch load significantly at scale — worth naming for large clusters.

### 7. Namespaces, RBAC, ServiceAccounts
**Namespaces** scope *names* and are the unit for ResourceQuotas, LimitRanges, NetworkPolicies and RBAC. **Not** an isolation boundary by themselves — pods in different namespaces on the same node share the kernel, and a namespace doesn't imply a network boundary. **Cluster-scoped resources** (Nodes, PVs, ClusterRoles, StorageClasses, Namespaces themselves, CRDs) ignore namespaces entirely.

**RBAC = four objects:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role                              # namespaced (ClusterRole = cluster-wide or reusable)
metadata: { name: deployer, namespace: team-a }
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get","list","watch","create","update","patch"]
  # resourceNames: ["my-app"]           # restrict to specific objects — very powerful, underused
---
kind: RoleBinding                       # ClusterRoleBinding for cluster scope
metadata: { name: ci-deployer, namespace: team-a }
subjects: [{ kind: ServiceAccount, name: ci, namespace: team-a }]
roleRef: { kind: Role, name: deployer, apiGroup: rbac.authorization.k8s.io }
```
**The rules of thumb:**
- **Least privilege**, namespaced `Role` over `ClusterRole` wherever possible.
- A **`ClusterRole` can be bound by a `RoleBinding`** to grant cluster-wide *verbs* within one namespace — the pattern for reusable permission sets.
- **`resourceNames`** restricts to specific objects — the difference between "can edit any deployment" and "can edit this deployment". Most teams skip it and shouldn't.
- Dangerous grants to recognise on sight: `secrets` get/list (≈ cluster admin, because you can read any SA token), `pods/exec` (arbitrary code in any pod), `create` on `ClusterRoleBinding` (privilege escalation), `*` on `*`, and `patch` on `deployments` (you can inject any image/command).
- **`kubectl auth can-i --list`**, `kubectl auth can-i create pods --as=system:serviceaccount:team-a:ci`, and **rbac-lookup/rbac-police/kube-bench** for auditing.
- **`automountServiceAccountToken: false`** for pods that don't need the API — otherwise every pod has a token to the apiserver, which is the first thing an attacker uses after a compromise.
- **BoundServiceAccountTokenVolume** (default now): tokens are short-lived, audience-scoped, projected — much better than the old non-expiring secrets.

### 8. Resource requests, limits, and QoS
- **Requests** = scheduling input *and* the guaranteed share. The scheduler places pods based on **requests only, never limits** — so a node can be scheduled to 100% of requests while actual usage exceeds capacity.
- **Limits** = the ceiling. CPU limit → **throttling** (CFS quota, enforced per 100ms period). Memory limit → **OOMKill**.
- **CPU is compressible** (throttle, slow down); **memory is incompressible** (kill). This asymmetry drives every recommendation.

**QoS classes (assigned automatically, used for eviction order):**
| Class | Requirement | Eviction priority |
|---|---|---|
| **Guaranteed** | Every container has requests **== limits** for both CPU and memory | Last |
| **Burstable** | At least one request set, not all limits equal | Middle |
| **BestEffort** | No requests or limits at all | **First** |

**The opinionated, defensible position (say it as a position, with reasoning):**
- **Memory: always set requests == limits.** Memory can't be throttled; a pod that exceeds its request gets the node into MemoryPressure and can trigger eviction of *other* pods. Guaranteed QoS also protects your critical workloads. Downside: less bin-packing efficiency, and you must size correctly (use VPA recommendations / actual usage percentiles).
- **CPU: set requests, be cautious with limits.** A CPU limit causes throttling at the 100ms period granularity — a burst to 2 cores for 20ms within a 1-core limit gets throttled even though it used less CPU than the quota allows *on average*. This produces **p99 latency spikes with healthy-looking average CPU**. Many platform teams remove CPU limits entirely (keep requests) — Google/GKE and others recommend this. If you keep limits, ensure `limit ≥ 2× request` and monitor `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total`.
- **Always set something.** BestEffort pods on a shared node are the first evicted and will make your service disappear during any pressure event.
- **LimitRange** for namespace defaults, **ResourceQuota** for namespace totals (also `count/*`, PVCs, and LB services — quotas prevent one team exhausting the cluster).

### 9. Scheduling — how a pod lands on a node
**Two phases:**
1. **Filtering (predicates)** — which nodes are *possible*: enough unallocated requests (`Fit`), matching `nodeSelector`/`nodeAffinity` required terms, no conflicting taints (unless tolerated), port availability (`hostPort`), volume topology constraints, pod affinity/anti-affinity feasibility, `PodFitsResources`, node unschedulable/NotReady exclusion.
2. **Scoring (priorities)** — rank survivors: `LeastAllocated`/`MostAllocated` (bin-packing), `BalancedResourceAllocation`, image locality (node already has the image → faster start), affinity preferences, `PodTopologySpread` scoring, taint tolerations preference. Highest score wins; ties broken randomly.

**The tools:**
| Mechanism | Direction | Example |
|---|---|---|
| **nodeSelector** | Node labels; simple equality | `nodeSelector: {disktype: ssd}` |
| **nodeAffinity** | Node labels; rich expressions; `requiredDuringScheduling...` (hard) / `preferred...` (soft) | `topology.kubernetes.io/zone In [us-east-1a, us-east-1b]` |
| **taints** | **Node repels pods** | `kubectl taint nodes n1 gpu=true:NoSchedule` |
| **tolerations** | Pod *permits* (doesn't require) a tainted node | `tolerations: [{key: gpu, operator: Equal, value: "true", effect: NoSchedule}]` |
| **podAffinity** | Co-locate with matching pods | Put the cache next to the app |
| **podAntiAffinity** | Spread away from matching pods | **Never put two replicas on one node** |
| **topologySpreadConstraints** | Even distribution across a topology key | Max skew 1 across zones |
| **priorityClass** | Preemption order | System > production > batch |
| **RuntimeClass** | Which runtime + which nodes | gVisor for untrusted workloads |

**Taint effects:** `NoSchedule` (new pods rejected), `PreferNoSchedule` (soft), `NoExecute` (**evicts running pods** — this is what `node.kubernetes.io/unreachable` uses, with `tolerationSeconds` controlling how fast).

**Key insight to state:** "**Tolerations don't attract, they permit.** A common bug is tolerating a GPU taint and expecting to land on GPU nodes — you also need `nodeSelector`/affinity. Taints+tolerations are for *exclusion*; affinity is for *attraction*."

**Topology spread — the production-grade form of anti-affinity:**
```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: ScheduleAnyway        # DoNotSchedule = hard
  labelSelector: { matchLabels: { app: api } }
```
`DoNotSchedule` with `maxSkew: 1` across zones means the pod stays `Pending` if a zone is full — a **hard availability guarantee that can become an availability problem** during node failures. Use `ScheduleAnyway` for soft spreading, or combine with cluster autoscaler headroom. Naming this tension is a senior signal.

---

## 🔵 Advanced

### 10. Controllers, informers, and the operator pattern
**How a controller actually works (the mechanism interviewers want):**
```
apiserver ──list-watch──► Reflector ──► DeltaFIFO ──► Indexer (thread-safe local cache)
                                                          │
                                        Workqueue (rate-limited, deduplicating)
                                                          │
                                                     Reconcile(key)
                                                          │
                                        read from cache ──┴── write via apiserver
```
- **Informers** maintain a local cache via an initial `LIST` + ongoing `WATCH`, with **resync** (periodic re-queue of everything, so missed events self-heal).
- **Workqueue** deduplicates keys (namespace/name, not full objects) and rate-limits retries with exponential backoff. **Dedup means: if the same object changes 100 times while you're processing, you reconcile once more** — so reconcile must be **level-triggered**: read current state, compute the diff, act. Never "handle the event".
- **Reconcile must be idempotent and re-entrant.** Same input → same result, safe to run twice concurrently-ish.

**Operator = CRD + custom controller.** Use it when you're encoding **operational knowledge** that a human would otherwise apply: "when the primary Postgres dies, promote the replica with the highest LSN, then re-point the Service." That's not a Deployment.

**When NOT to write an operator (the senior answer):**
> "An operator is a permanent maintenance liability: it must track Kubernetes API deprecations, handle every partial-failure state, and be tested against upgrades. If the problem is 'run this container with these settings', use a Deployment + Helm. If it's 'I need a workflow', use a Job or Argo Workflows. I'd write an operator when there's stateful, decision-heavy operational logic that would otherwise require a human on call — databases, certificate rotation, cluster lifecycle, backup/restore. And I'd use **kubebuilder/operator-sdk** with **controller-runtime**, never hand-rolled informers."

**Operator design must-haves:**
- **Status subresource** (`/status`) so spec and status updates don't fight (and so `kubectl apply` doesn't clobber status).
- **Finalizers** for external resource cleanup (a cloud LB, an S3 bucket) — but **always handle the case where cleanup fails**; a stuck finalizer means the object can never be deleted, and `kubectl patch --type=merge -p '{"metadata":{"finalizers":[]}}'` is the emergency escape hatch you should know about.
- **Owner references + garbage collection** (cascading delete) instead of manual child cleanup.
- **Optimistic concurrency**: `resourceVersion` conflicts → requeue, don't retry blindly. Never `Update` a whole object you read a while ago; `Patch` the fields you own (**server-side apply** with a field manager is the modern answer, and it makes multi-controller field ownership explicit).
- **Requeue with backoff**, and **don't hot-loop**: a reconcile that always returns `Requeue: true` with no delay burns the apiserver.
- **Metrics**: `controller_runtime_reconcile_total{result=}`, `reconcile_time_seconds`, workqueue depth/latency. An operator without reconcile-latency metrics is undebuggable.
- **Webhook validation** for the CRD schema (`+kubebuilder:validation` markers → OpenAPI v3 schema, plus CEL rules via `x-kubernetes-validations`).
- **Leader election** so only one replica reconciles (controller-runtime gives it to you).
- **Conversion webhooks** for CRD version migration.

### 11. Admission control — webhooks, policies, and the request path
```
request → authn → authz → MUTATING admission → object schema validation
        → VALIDATING admission → persist to etcd
```
**Built-in admission plugins** (a subset that matters): `NamespaceLifecycle`, `LimitRanger`, `ResourceQuota`, `PodSecurity` (the replacement for the deprecated PodSecurityPolicy), `NodeRestriction` (prevents a kubelet modifying other nodes), `ServiceAccount` (auto-mounts tokens), `DefaultStorageClass`, `MutatingAdmissionPolicy`/`ValidatingAdmissionPolicy` (CEL-based, **in-cluster**, GA in 1.36 for mutating).

**Webhooks:**
- **Mutating** first (can change the object — inject sidecars, set defaults, add labels), then **Validating** (can only accept/reject; run in parallel).
- **Failure policy is a critical decision:** `failurePolicy: Fail` blocks all matching requests if your webhook is down (**you've built a cluster-wide outage trigger**); `Ignore` lets non-compliant objects through. My answer: `Fail` for security-critical policies, with `namespaceSelector` excluding `kube-system` (otherwise a broken webhook can prevent the webhook's own pods from being repaired — **the classic self-lockout**), short `timeoutSeconds` (2–5s, default 10s is far too long in a request path), and a **circuit-breaker/alert on webhook latency**.
- **Reinvocation**: a mutating webhook may be called again if a later webhook changes the object → **it must be idempotent**.
- Webhooks add latency to *every* matching request; measure `apiserver_admission_webhook_admission_duration_seconds`.

**Policy engines instead of hand-written webhooks:**
| Tool | Language | Mutating? | Notes |
|---|---|---|---|
| **Kyverno** | YAML (Kubernetes-native) | ✅ | Easiest for platform teams; generate/clone resources, cleanup jobs |
| **OPA Gatekeeper** | Rego | ✅ (via mutation) | Most expressive; steep learning curve; `ConstraintTemplate` + `Constraint` |
| **ValidatingAdmissionPolicy (VAP)** | **CEL** | ❌ (MAP does mutate) | **In-tree, no webhook, no extra latency, no availability risk** — the direction of travel. GA for validating; mutating (MAP) GA in 1.36 |
| **Pod Security Admission** | Fixed standards | ❌ | `privileged` / `baseline` / `restricted` per namespace — the PSP replacement. **Enforce `restricted` on app namespaces** |

**Senior framing:** "I'd use PSA for the baseline, VAP/CEL for simple cluster-wide invariants (no webhook = no availability risk), and Kyverno or Gatekeeper only where I need mutation, generation, or complex cross-object logic. Every webhook is a potential cluster-wide outage, so the bar for adding one should be high."

### 12. Networking deep dive — pod-to-pod, ingress, and NetworkPolicy
**The three IP spaces:** pod IPs (from the CNI, routable cluster-wide, ephemeral), service ClusterIPs (virtual, DNAT only), node IPs. **Every pod can reach every other pod without NAT** — that's the CNI contract.

**Pod-to-pod across nodes (typical implementations):**
- **Overlay (VXLAN/IPIP)** — Flannel, Calico in overlay mode, Cilium overlay. Encapsulates pod packets in node packets. Works on any network, no infrastructure config. Cost: encapsulation overhead (~50 bytes), **MTU reduction**, slightly worse throughput.
- **Native routing (BGP)** — Calico BGP, cloud VPC CNI. Pod IPs are real VPC IPs, routed by the fabric. Best performance, no MTU loss. Cost: needs infrastructure cooperation (BGP peering, or the cloud's ENI/IP quota model).
- **eBPF (Cilium)** — replaces iptables/kube-proxy with BPF programs: O(1) service lookup, no conntrack for services, kernel-level policy enforcement, full observability (Hubble). The modern default for performance-minded platforms.
- **VPC CNI (EKS)** — pods get real VPC IPs from ENIs. Simplifies security groups and VPC reachability; constrained by **ENI/IP quotas per instance type** (a real capacity planning issue: a `m5.large` supports only ~29 pods).

**Ingress / Gateway API:**
- **Ingress** is an L7 HTTP(S) routing API — but it's minimal, and every controller (nginx-ingress, Traefik, HAProxy, ALB, GCE) adds **its own annotations**, so manifests aren't portable.
- **Gateway API** is the successor: `GatewayClass` (implementation) → `Gateway` (listener, ports, TLS, owned by the platform team) → `HTTPRoute` (routing rules, owned by app teams). **Role-oriented, expressive, portable, and extensible via `ExtensionRef` filters.** It supports traffic splitting, header matching, mirroring, and cross-namespace references with `ReferenceGrant`.
- **Answer for interviews:** "Gateway API is where the ecosystem is going; Ingress is stable but limited and annotation-driven. For a new platform I'd standardise on Gateway API, and I'd treat the *routing policy* as an application-team-owned resource with platform-owned Gateways — that separation is the actual design win, not the YAML syntax."
- **In every case the Ingress/Gateway controller is itself a Deployment behind a Service type=LoadBalancer**, and it's a single point of failure unless it's multi-replica, multi-zone, with a PDB and anti-affinity. **Ask "what happens when the ingress controller dies?"**

**NetworkPolicy:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: db-allow-only-api, namespace: prod }
spec:
  podSelector: { matchLabels: { app: db } }        # who this applies to
  policyTypes: [Ingress, Egress]                    # MUST declare both, or egress is unrestricted
  ingress:
  - from:
    - podSelector: { matchLabels: { app: api } }    # same namespace
    - namespaceSelector:                            # cross-namespace
        matchLabels: { kubernetes.io/metadata.name: monitoring }
    ports: [{ protocol: TCP, port: 5432 }]
  egress:
  - to: [{ ipBlock: { cidr: 10.0.0.0/8 } }]
    ports: [{ protocol: TCP, port: 443 }]
  - to: [{ namespaceSelector: {} }]                  # DNS!
    ports: [{ protocol: UDP, port: 53 }, { protocol: TCP, port: 53 }]
```
**The gotchas:**
- **Requires a CNI that implements it.** Flannel alone does **not** — policies are silently ignored. Verify with a test, not with `kubectl get netpol`.
- **Default-allow until a policy selects a pod.** One policy selecting a pod flips it to **default-deny for the declared policyTypes**. So `podSelector: {}` with `policyTypes: [Ingress]` = deny all ingress in the namespace — the standard starting point.
- **`policyTypes` omission** is the #1 bug: declaring only `Ingress` leaves Egress wide open.
- **You must allow DNS** (port 53 to the kube-system CoreDNS pods) or everything breaks in a confusing way.
- **Labels are the identity.** A workload that can set its own labels can escape a label-based policy — so restrict pod-label mutation via RBAC/OPA (`Restricted` PSA doesn't cover this; a policy engine does).
- **Egress to the cloud metadata endpoint (169.254.169.254)** should be explicitly denied for untrusted workloads — NetworkPolicy can do this with an `ipBlock` deny (`except`).

### 13. Why do we get 502/504s during rolling deploys? (The most common senior question)
There are **five independent races**, and a good answer names several:

1. **Endpoint removal lags pod readiness.** The new pod passes its readiness probe and is added to the EndpointSlice, but **kube-proxy / the ingress controller / the cloud LB hasn't programmed the rule yet** → traffic arrives before the pod is actually listening. Fix: `startupProbe` + a readiness check that verifies the server is *actually accepting connections*, and a small `postStart` delay if needed.
2. **Terminating pods still receive traffic.** Pod marked Terminating → removed from EndpointSlices → but propagation to every node's iptables, the ingress controller's config reload, and the cloud LB's target deregistration takes **seconds**. Meanwhile the app has already exited on SIGTERM. **Fix: `preStop: sleep 5–15s`** (or an HTTP drain call), so the app keeps serving while propagation completes.
3. **The cloud LB deregistration delay.** ALB/NLB target groups have a deregistration delay (default 300s for ALB) and connection draining; if the pod dies in 30s but the LB keeps sending for longer, you get 502s. Fix: match grace period to LB draining, or use **target-type: ip with proper health checks**, or an ingress controller that reacts faster.
4. **Ingress controller config reload.** nginx-ingress reloads on endpoint changes; a large cluster can take seconds, and a reload can drop long-lived connections. Fix: newer controllers use dynamic config (no reload), or Lua-based backends.
5. **Long-lived connections (websockets/gRPC/HTTP2).** kube-proxy balances per-connection, so existing connections aren't rebalanced when a pod goes away — they just break. Fix: client-side retries with backoff, `max_connection_duration` on the server, graceful drain that waits for connections to close, and **connection lifetime limits** so load rebalances naturally.

**The complete answer:**
> "Five separate eventually-consistent systems have to agree: the endpoint controller, kube-proxy on every node, the ingress controller, the cloud LB, and the client's connection pool. Rolling updates are safe only if the pod outlives the propagation. So: readiness probe that tests real serving capability, startupProbe for slow starts, `preStop` sleep longer than the propagation delay, `terminationGracePeriodSeconds` covering preStop + drain + LB deregistration, `maxUnavailable: 0`, PodDisruptionBudget to prevent concurrent voluntary disruptions, and client-side retries for idempotent requests. Then verify with a load test *during* a rollout — that's the only way to know."

### 14. DNS in Kubernetes — CoreDNS, ndots, and the latency trap
**Resolution path:** pod `/etc/resolv.conf` →
```
nameserver 10.96.0.10          # CoreDNS ClusterIP
search <ns>.svc.cluster.local svc.cluster.local cluster.local <node-domain>
options ndots:5
```
`ndots:5` means: **any name with fewer than 5 dots is tried against every search domain first.** So resolving `api.github.com` (2 dots) issues up to 4 failed cluster-local queries (`api.github.com.prod.svc.cluster.local`, `.svc.cluster.local`, `.cluster.local`, …) before the real one. On a chatty service that's a **4–5× DNS amplification** and a visible latency tax.

**Fixes:**
- Append a trailing dot: `api.github.com.` → FQDN, no search expansion.
- Lower `ndots` per pod: `dnsConfig: { options: [{ name: ndots, value: "2" }] }`.
- **`dnsPolicy: Default`** to use the node's resolver (loses in-cluster service discovery).
- **NodeLocal DNSCache** — a DaemonSet caching resolver on each node, reached over a link-local address. Fixes the biggest problem: **conntrack races on UDP DNS**, which cause the infamous intermittent **5-second DNS timeouts** (the kernel's UDP conntrack insert race → dropped packet → glibc/musl resolver retries after 5s). **Naming the 5s timeout and its conntrack cause is a very strong signal.**
- CoreDNS tuning: replicas ≥ 2 with anti-affinity (it's a cluster-wide SPOF), `autoscaler` (cluster-proportional-autoscaler), reasonable cache TTL, and forward with health checks.
- glibc vs musl: musl (Alpine) doesn't do parallel A/AAAA queries the same way and has different search-domain behaviour — a source of "works on Debian, times out on Alpine".
- Prefer `single-request-reopen` / disabling AAAA lookups if you see the classic dual-query problem.

### 15. Storage — PV, PVC, StorageClass, CSI
```
StorageClass (provisioner + parameters)
      │ dynamic provisioning
PersistentVolumeClaim (user's request: size, access mode, class)
      │ bound to
PersistentVolume (the actual storage: cloud disk, NFS, local)
      │ mounted into
Pod (via volumeMounts)
```
- **Access modes:** `ReadWriteOnce` (RWO — one *node*, not one pod; multiple pods on that node can share), `ReadOnlyMany` (ROX), `ReadWriteMany` (RWX — needs NFS/CephFS/EFS/Azure Files/GCS Fuse), `ReadWriteOncePod` (RWOP — genuine single-pod, 1.27+).
- **The RWO misunderstanding is a classic:** "RWO means one pod" is **wrong** — it means one node. Two replicas of a Deployment on the same node can both mount an RWO volume, which then corrupts a database. Use `ReadWriteOncePod` when you mean it.
- **Reclaim policy:** `Delete` (default for dynamic — **the data goes away when the PVC is deleted**) vs `Retain` (PV kept, must be reclaimed manually — the safe choice for anything valuable).
- **Volume binding mode:** `Immediate` (provision now) vs **`WaitForFirstConsumer`** (provision in the zone where the pod actually gets scheduled). **For zonal disks you must use `WaitForFirstConsumer`** or you get a PVC in zone A and a pod that can only schedule in zone B → permanently `Pending`. Very common.
- **Volume expansion:** `allowVolumeExpansion: true` in the StorageClass; grow the PVC, and the filesystem resizes (online for most CSI drivers).
- **`volumeSnapshotClass` / VolumeSnapshot / VolumeSnapshotContent** for backups and cloning.
- **ephemeral volumes:** `emptyDir` (node-local, dies with the pod, `sizeLimit` to prevent node disk exhaustion, `medium: Memory` for tmpfs — **counts against the container's memory limit and can OOMKill**), CSI **ephemeral** volumes for secrets (Vault, cloud KMS), `generic` inline volumes.
- **`local` PVs** for high-performance node-local storage (databases): no network hop, but the pod is pinned to the node and data doesn't survive node loss.
- **fsGroup / fsGroupChangePolicy:** the ownership-remap mechanism for volumes; on huge volumes the recursive chown at mount time can take minutes and block startup → `fsGroupChangePolicy: OnRootMismatch`.

### 16. HPA, VPA, KEDA, Cluster Autoscaler — and how they conflict
| Autoscaler | Scales | Signal | Notes |
|---|---|---|---|
| **HPA** | Replica count | CPU/memory (from metrics-server) or **custom/external metrics** (Prometheus Adapter, KEDA) | `behavior` block controls scale-up/down rates and stabilization windows |
| **VPA** | Requests/limits | Historical usage | **`updateMode: Recreate` restarts pods**; **conflicts with HPA on CPU/memory** (they fight); use `Off` mode for *recommendations only* — the pragmatic choice |
| **KEDA** | Replica count (0→N) | 60+ external sources: queue depth, Kafka lag, cron, Prometheus query, cloud metrics | **Scale-to-zero** is the killer feature; drives HPA under the hood |
| **Cluster Autoscaler** | Node count | Pending pods that don't fit | Slow (minutes: instance launch + node ready + image pull); needs headroom strategy |
| **Karpenter** | Nodes | Pending pods, directly | **Provisions the right instance type from the pod's requirements**, no node groups; consolidates for cost; much faster and more cost-efficient than CA. The modern default on AWS |
| **In-place pod resize** (1.27+ beta, maturing) | Container resources **without restart** | — | Removes the VPA/HPA conflict for memory; still evolving |

**HPA that's actually production-grade:**
```yaml
spec:
  minReplicas: 3
  maxReplicas: 50
  metrics:
  - type: Resource
    resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
  - type: Pods
    pods: { metric: { name: http_requests_per_second }, target: { type: AverageValue, averageValue: "100" } }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0            # react fast to load
      policies: [{ type: Percent, value: 100, periodSeconds: 30 }]   # double at most every 30s
    scaleDown:
      stabilizationWindowSeconds: 300          # don't flap on a traffic dip
      policies: [{ type: Percent, value: 25, periodSeconds: 60 }]
```
**The insights that separate seniors:**
- **CPU utilisation is a poor scaling signal for I/O-bound services** — scale on request rate, queue depth, or concurrency instead. CPU-based HPA on a service blocked on a downstream dependency scales *down* while latency explodes.
- **`averageUtilization` is relative to the CPU *request*,** not the limit. If requests are wrong, HPA is wrong. This is why "set accurate requests" is a prerequisite for autoscaling.
- **Scale-down stabilisation prevents flapping**; scale-up should be fast. Asymmetric behaviour blocks are not optional in production.
- **HPA + Cluster Autoscaler cascade latency** can be 5–10 minutes: HPA adds pods → Pending → CA adds a node → boot → CNI → image pull. For spiky traffic you need **Karpenter**, over-provisioning (pause pods with negative priority that get preempted — buys instant headroom), or predictive scaling.
- **HPA + PDB interaction:** if a PDB blocks evictions and the autoscaler wants to consolidate, you can deadlock. And **a PDB with `maxUnavailable: 0` on a single replica blocks node drains forever** — the classic "cluster upgrade stuck" incident.
- **`minReplicas` must exceed 1** for anything customer-facing; `maxReplicas` protects the downstream (scaling to 500 pods and taking out your database is worse than shedding load).

### 17. etcd, the apiserver, and scale limits
- **etcd is the cluster's only state.** Raft consensus, needs odd members (3 or 5), **quorum = majority**. Losing quorum = read-only/unavailable cluster. Default DB size limit **2 GB** (quota, then `NOSPACE` alarm → cluster goes read-only until defrag + alarm disarm).
- **Performance killers:** large objects (a ConfigMap/Secret near 1 MB), **huge numbers of EndpointSlices** for a service with thousands of pods, frequent list-all operations without resourceVersion (bypasses the watch cache → hits etcd), and expensive CRDs with high-churn status updates.
- **etcd maintenance:** `etcdctl defrag` (blocks the member during defrag — do one at a time), snapshot + restore drills (**untested backups aren't backups**), `--quota-backend-bytes`, alarm watch, disk latency (`etcd_disk_wal_fsync_duration_seconds` p99 < 10ms — **SSD/NVMe is mandatory; this single metric predicts cluster health**).
- **apiserver scale levers:** watch cache size, `--max-requests-inflight`, APF (**API Priority and Fairness** — replaces max-in-flight with per-priority-flow queues, so a runaway controller can't starve the kubelets), horizontal apiserver replicas behind a load balancer, and **immutable ConfigMaps/Secrets** to cut watch traffic.
- **Practical limits:** the often-quoted guidance is ~5,000 nodes / 150,000 pods, but real limits come from etcd write throughput, watch fan-out, and object churn — not a hard number. **The honest answer:** "Scale limits are workload-shaped. A cluster with 500 chatty operators hits problems before a cluster with 2,000 quiet Deployments. I'd watch apiserver request latency, etcd fsync/commit duration, watch cache efficiency, and APF rejections."
- **Large-cluster techniques:** sharding into multiple clusters (per region/tenant/BU) with a fleet manager, reducing informer scope (label selectors, field selectors), avoiding `list` on huge collections, and keeping CRD status updates rate-limited.

### 18. Multi-tenancy — how much isolation can Kubernetes actually give?
| Layer | Mechanism | Strength |
|---|---|---|
| **Namespace** | Names, quotas, RBAC scope | Weak alone — not a security boundary |
| **RBAC** | Per-tenant roles/bindings | Strong for API access; needs discipline |
| **ResourceQuota / LimitRange** | CPU, memory, storage, object counts, LB services | Prevents resource monopolisation |
| **NetworkPolicy** | Pod/namespace/label selectors + IP blocks | Good, CNI-dependent |
| **Pod Security Admission** | `restricted` per namespace | Baseline hardening |
| **RuntimeClass** | gVisor/Kata for untrusted tenants | **Real isolation** |
| **User namespaces** | Container root → unprivileged host UID (GA 1.36) | Blocks the most escape paths |
| **Node isolation** | Taints + tolerations + dedicated node pools | Noisy-neighbour + kernel-exploit containment |
| **Hierarchical namespaces (HNC)** | Namespace trees with inherited policy | Enterprise structure |
| **Separate clusters** | Per tenant/BU | **Strongest**; the right answer for hostile tenants |

**The honest conclusion to state:** "Soft multi-tenancy — teams that trust each other — works well with namespaces + RBAC + quotas + policies. **Hard multi-tenancy with mutually untrusting tenants is not safe on a shared kernel with runc alone.** You need user namespaces + gVisor/Kata + dedicated node pools + strict egress control, and even then I'd recommend separate clusters for genuinely adversarial tenants, because a kernel 0-day collapses the whole model. The cost question is real: separate clusters multiply operational overhead, so the decision is about the *threat model*, not the tooling."

---

## 🔴 Scenario

### 19. "A pod is stuck in `Pending`. Walk me through it."
```bash
kubectl describe pod <pod>          # Events at the bottom = the answer 90% of the time
```
**Ranked causes with the exact event text:**
| Event / symptom | Cause | Fix |
|---|---|---|
| `0/12 nodes are available: 8 Insufficient cpu, 4 Insufficient memory` | Not enough **requests** headroom (not actual usage!) | Lower requests (if over-set), scale out nodes, check Cluster Autoscaler/Karpenter is working, check for BestEffort pods hogging |
| `... 3 node(s) had untolerated taint {gpu: true}` | Taint without toleration | Add toleration (and nodeSelector if you *want* those nodes) |
| `... 5 node(s) didn't match Pod's node affinity/selector` | Label mismatch | `kubectl get nodes --show-labels`; fix the selector (typos in `topology.kubernetes.io/zone` are common) |
| `... 2 node(s) had volume node affinity conflict` | Zonal PV in a different zone than schedulable nodes | StorageClass `volumeBindingMode: WaitForFirstConsumer`; or the node in that zone is gone |
| `... 4 Insufficient ephemeral-storage` | Requests exceed node allocatable | Right-size; check for nodes with small disks |
| `... 1 node(s) didn't have free ports for the requested hostPorts` | `hostPort` collision | Only one pod per node per hostPort — reconsider using hostPort at all |
| `pod has unbound immediate PersistentVolumeClaims` | PVC not provisioned | `kubectl describe pvc` → provisioner errors, quota, missing StorageClass, access mode unsupported (RWX needs NFS/EFS) |
| No events at all, `spec.nodeName` empty | Scheduler not running, or an admission webhook hanging | Check kube-scheduler health; `apiserver_admission_webhook_admission_duration_seconds` |
| Quota exceeded | `ResourceQuota` on the namespace | `kubectl describe resourcequota -n <ns>` |
| Priority/preemption not happening | No PriorityClass, or lower-priority pods have PDBs blocking preemption | Add PriorityClass; check PDBs |

**Then the systematic checks:**
```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl describe node | grep -A6 "Allocated resources"     # requests vs allocatable, per node
kubectl get resourcequota,limitrange -n <ns> -o yaml
kubectl get pvc -n <ns>
kubectl get nodes -o wide                                  # Ready? SchedulingDisabled?
kubectl get --raw='/api/v1/nodes/<node>/proxy/stats/summary'   # real usage
```
**The differentiating insight:** "**Pending is almost always about requests, not usage.** A node at 20% CPU can refuse a pod because 95% of its CPU is already *requested*. So I look at `Allocated resources` in `kubectl describe node`, not at monitoring. And the second thing I check is whether the cluster autoscaler is *able* to help — if every node group is at max, or the pod has an unsatisfiable affinity, autoscaling won't save you."

### 20. "`kubectl get pods` shows CrashLoopBackOff everywhere after a deploy. What do you do?"
**Step 1 — Stop the bleeding.** If this is production and a rollout caused it:
```bash
kubectl rollout undo deploy/<name>          # or: kubectl rollout pause
```
**Roll back first, diagnose second** — unless the rollback also fails (which means the problem is a shared dependency: config, schema, secret, downstream). Say this trade-off explicitly: "I'd roll back immediately if customers are affected, because MTTR matters more than root cause in the moment. But I'd capture evidence first — `kubectl logs --previous`, describe output, and the current ReplicaSet state — because a rollback destroys the failing pods."

**Step 2 — Read the actual error:**
```bash
kubectl logs <pod> --previous                # the PREVIOUS container's logs — the one that crashed
kubectl describe pod <pod>                   # exit code + reason + events
kubectl get events --sort-by=.lastTimestamp
```
| Exit code | Meaning | Common cause |
|---|---|---|
| 1 / 2 | App error | Bad config, missing env var, schema mismatch, unhandled exception |
| **137** | SIGKILL | **OOMKilled** (check `lastState.terminated.reason`) or liveness probe killed it |
| **143** | SIGTERM | Killed by probe or rollout |
| 126 / 127 | Not executable / not found | Wrong entrypoint, missing binary, wrong arch, bad `command:` override |
| 0 | Clean exit | Container isn't a long-running process; entrypoint script finished |

**Step 3 — The classic causes of "everywhere, right after a deploy":**
1. **Bad ConfigMap/Secret change** — a typo'd key, a renamed key, or a config change that wasn't rolled out atomically with the code. `kubectl get cm <name> -o yaml` and diff against the previous version (`kubectl rollout history` doesn't cover ConfigMaps → **this is why config should be versioned in git and applied with the app**).
2. **Database migration ran ahead of / behind the code** — the new code expects a column that doesn't exist, or the migration removed a column the old code needs. **This is the #1 cause of unrecoverable rollbacks** and the reason for expand/contract migrations (see Q22).
3. **Image problem** — wrong tag, `latest` mutated, multi-arch manifest missing the node's architecture, a broken build. `kubectl describe` → `ImagePullBackOff` vs crash; check the digest actually deployed.
4. **Liveness probe too aggressive** — the new version starts slower (a new dependency, a bigger cache warm-up) and gets killed before it's up. `describe` shows `Liveness probe failed` + exit 137. Fix: `startupProbe`.
5. **Dependency unavailable** — the new version calls a service that's down, or a new DNS name that doesn't resolve, or a TLS cert mismatch. Logs show connection errors at startup.
6. **Permission change** — a new ServiceAccount/RBAC need, or `readOnlyRootFilesystem` now breaking a write the app always did (works locally, fails in the hardened environment).
7. **Resource limit change** — someone lowered the memory limit; the app now OOMs at its normal working set.
8. **Init container / sidecar failure** — the main container never starts. Check `initContainerStatuses`.

**Step 4 — Contain and verify:**
- Check the blast radius: is it one Deployment or everything? If everything → suspect a **cluster-level** cause (admission webhook broken, CoreDNS down, CNI failure, apiserver degraded, node pool rollout, certificate expiry — **the kubelet/apiserver serving cert expiry is a famous total-outage cause**).
- Verify the fix on one replica before full rollout: `kubectl scale` a canary, or `kubectl rollout pause` + patch one pod.
- Add the missing guardrail afterwards: a canary/progressive delivery, a startupProbe, config checksums, a migration compatibility check, or a pre-deploy smoke test.

### 21. "Nodes are going `NotReady` intermittently. Investigate."
`NotReady` means **the kubelet stopped posting status** to the apiserver within `node-monitor-grace-period` (default 40s), or reported itself unhealthy.

**Ranked hypotheses:**
1. **Node resource exhaustion — PID pressure or disk pressure.**
   ```bash
   kubectl describe node <n> | grep -A10 Conditions      # MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable
   ```
   `DiskPressure` (imagefs/nodefs below eviction thresholds) and `PIDPressure` (`pids.max` or fork bombs) are extremely common and cause kubelet eviction + NotReady. Check `/var/lib/docker` and `/var/lib/containerd` disk usage, and log volume. **A container writing unbounded logs to the node filesystem is a self-inflicted NotReady** — hence `containerLogMaxSize`/`containerLogMaxFiles`.
2. **Container runtime unhealthy.** containerd hung or OOMKilled → kubelet can't create pods → NotReady.
   ```bash
   journalctl -u containerd -u kubelet --since "-30m"
   crictl ps ; crictl info
   ```
   Classic causes: runtime deadlock under load, snapshotter disk issues, too many concurrent image pulls, containerd OOM (its own memory limit too low).
3. **Network partition between node and apiserver.** The kubelet is fine, but it can't reach the apiserver → status stops → NotReady → **`node.kubernetes.io/unreachable` taint with `NoExecute`** → pods evicted after `tolerationSeconds` (default 300s). If it's a *false* partition (kubelet is healthy, workload is fine), you've just caused an unnecessary mass rescheduling. Check apiserver LB health, DNS for the apiserver endpoint, conntrack table full, and MTU issues.
4. **Kernel/hardware.** `dmesg -T` for OOM killer, hung tasks, disk I/O errors, NIC resets, NTP jumps. A node with a failing disk shows up as intermittent NotReady before it dies. Also **kernel deadlock under memory pressure** and **transparent huge pages** compaction stalls.
5. **CPU starvation of the kubelet itself.** If the node's CPU is saturated by workloads and the kubelet isn't in a protected cgroup, it can't post status. Fix: **kube/system-reserved** configuration and `--kube-reserved`, plus CPU manager static policy for critical pods. Check `node_cpu_saturation` and PSI (`/proc/pressure/cpu`).
6. **Clock skew / certificate expiry.** The kubelet's client cert rotation failed (a well-known total-outage pattern) → apiserver rejects it → NotReady. Check `kubelet_certificate_manager_*` metrics and expiry dates.
7. **Node autoscaler churn.** The cluster autoscaler or Karpenter is terminating/replacing nodes; what looks like "intermittent NotReady" is really node recycling. Check cloud provider events.
8. **CNI plugin failure.** `NetworkUnavailable` condition, or the CNI agent crashing on that node → pods can't get IPs → node marked unhealthy.

**Immediate mitigations:**
- `kubectl cordon <node>` to stop new scheduling, then decide: `kubectl drain --ignore-daemonsets --delete-emptydir-data` (respecting PDBs) or leave it if the workloads are actually healthy and it's a false partition.
- **Check PDBs before draining** — a `maxUnavailable: 0` PDB on a single-replica Deployment blocks the drain indefinitely (`--disable-eviction` is the escape hatch, with the risk that implies).
- Tune `node-monitor-grace-period` and `tolerationSeconds` deliberately: shorter = faster failover but more false evictions; longer = the reverse. **Node lease** (heartbeats every 10s, cheap) already reduced apiserver load versus full status updates.
- Add alerting on `kube_node_status_condition{condition="Ready",status="true"} == 0` and on PSI/disk/PID pressure *before* NotReady — you want to catch the cause, not the symptom.

### 22. "Design a zero-downtime deployment process for a service with a PostgreSQL database."
**The core constraint:** during a rollout, **old and new code run simultaneously**, and a rollback may happen at any point. So every change must be compatible with both.

**Expand–contract (parallel change) for schema:**
| Step | What | Why |
|---|---|---|
| 1. **Expand** | Add the new column (nullable or with a default), add the new table, add the new index **`CONCURRENTLY`** | Old code ignores it; no lock, no downtime |
| 2. **Dual write** | New code writes to both old and new columns; old code keeps writing the old one | Both versions stay correct |
| 3. **Backfill** | Batched migration job copying old → new, idempotent, resumable, rate-limited | Avoids a long lock and replica lag |
| 4. **Dual read / switch reads** | New code reads the new column, verifying parity (shadow read + compare + alert on mismatch) | Detects bugs before they matter |
| 5. **Contract** | Only after all old code is gone: drop the old column, remove dual writes | Irreversible — do it in a *later* release, not the same one |

**Hard rules:**
- **Never rename a column or table in one step.** Add new, dual-write, migrate, drop old.
- **Never add `NOT NULL` without a default to a large table** (full rewrite/lock in Postgres < 11; even later, validate constraints take locks). Add nullable → backfill → `ADD CONSTRAINT ... NOT NULL VALIDATE` in a separate transaction.
- **`CREATE INDEX CONCURRENTLY`** — cannot run inside a transaction block, so your migration tool must support non-transactional migrations (Flyway/Liquibase config, or Alembic with `autocommit`).
- **Never drop a column that old code still selects.** Old pods will error for the whole rollout window.
- **Migrations run as a separate Job/hook *before* the app rollout**, never inside the app's startup (N replicas racing to migrate is a disaster). Use advisory locks if it must be in-process, and make migrations **idempotent**.
- **Test the rollback path.** Migrations must be backward-compatible so a `rollout undo` works. If a migration isn't reversible, you need a forward-fix plan and the deploy is not zero-downtime in practice.

**The Kubernetes side:**
```yaml
spec:
  replicas: 6
  strategy:
    rollingUpdate: { maxUnavailable: 0, maxSurge: 2 }
  minReadySeconds: 10                    # pod must stay Ready 10s before counting as available
  progressDeadlineSeconds: 600
  template:
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: app
        lifecycle:
          preStop: { exec: { command: ["sleep","10"] } }   # let endpoints propagate
        startupProbe:  { httpGet: {path: /healthz, port: 8080}, failureThreshold: 30, periodSeconds: 5 }
        readinessProbe:{ httpGet: {path: /ready,   port: 8080}, periodSeconds: 5, timeoutSeconds: 3 }
        livenessProbe: { httpGet: {path: /healthz, port: 8080}, periodSeconds: 10, timeoutSeconds: 3, failureThreshold: 3 }
```
Plus:
- **PodDisruptionBudget**: `minAvailable: n-1` (or `maxUnavailable: 1`) so node drains and autoscaler consolidation don't take out too many at once. **Never `maxUnavailable: 0` with `minReplicas: 1`.**
- **Anti-affinity / topology spread** across zones so a rollout doesn't concentrate new pods in one zone.
- **Connection pooling**: Postgres has a hard connection limit (~100 by default) and each connection costs memory. **Scaling to 50 pods × 20 connections = 1000 connections = database down.** Use **PgBouncer/pgcat in transaction mode**, or a driver pool sized deliberately. **This is the failure mode that catches teams who add HPA without thinking about the database** — and mentioning it unprompted is a strong signal.
- **Client-side retries with backoff** for idempotent requests, plus **idempotency keys** for mutations — because even a perfect rollout has a window where a connection is dropped.
- **Progressive delivery**: canary at 5% with automated metric analysis (Argo Rollouts / Flagger: error rate, p99 latency, saturation) and automatic rollback. Blue/green for changes that can't be dual-run.
- **Feature flags** decouple *deployment* from *release*: ship dark code, enable progressively, kill instantly without a redeploy. **This is the single highest-leverage practice** and pairs with the expand-contract schema work.
- **Migration + deploy ordering**: migration job → wait for completion → rollout app → verify → (later release) contract migration. Automate this in the pipeline (Argo CD sync waves / Helm hooks with `pre-upgrade`, or an Argo Workflow).
- **Verification**: post-deploy smoke tests against the live endpoint, error-rate and latency SLO gates, and dashboards annotated with the deploy event so correlation is instant.

**The closing statement:** "Zero downtime isn't a Kubernetes feature — it's a property of the whole change: compatible schema, graceful shutdown, correct probes, connection-pool limits respected, progressive rollout with automatic rollback, and feature flags so release is decoupled from deploy. Any one of those missing shows up as a 502 during the deploy."

### 23. "One tenant's workload is degrading the whole cluster. Diagnose and fix."
**Diagnose — find the noisy neighbour:**
```bash
kubectl top pods -A --sort-by=cpu | head -20
kubectl top nodes
# Real usage per pod:
kubectl get --raw "/api/v1/nodes/<n>/proxy/stats/summary" | jq '.pod[] | {name:.podRef.name, cpu:.cpu.usageNanoCores, mem:.memory.workingSetBytes}'
```
Then check for the specific mechanisms:
- **CPU**: pods with no CPU requests (BestEffort) consuming everything → other pods throttled. Check `container_cpu_cfs_throttled_periods_total`, node PSI (`/proc/pressure/cpu`), and `Allocated resources` per node.
- **Memory**: a pod approaching the node's capacity → `MemoryPressure` → **kubelet evicts other pods by QoS order** (BestEffort first, then Burstable over their requests, then Guaranteed). Evictions look like random pod deaths to the victim teams.
- **Disk/IO**: `emptyDir` or container logs filling the node's `imagefs`/`nodefs` → `DiskPressure` → eviction of everything. Also **IO saturation** starving other pods' reads (check `node_disk_io_time_weighted_seconds_total`, and whether `io.weight`/blkio limits are set at all — they rarely are).
- **Network bandwidth**: no CNI enforces bandwidth by default (some support `kubernetes.io/ingress-bandwidth` annotations). One pod can saturate a node's NIC.
- **Conntrack/PID/socket exhaustion**: node-level `nf_conntrack` table full, `pids.max` reached, fd exhaustion → failures cluster-wide.
- **Apiserver abuse**: a controller hot-looping `LIST` on a large collection → apiserver latency for *everyone*. Check `apiserver_request_total` by client (`user-agent` label — **the single best way to find the culprit**), APF rejections, and `apiserver_request_duration_seconds`.
- **etcd write amplification**: a CRD with high-frequency status updates.

**Fix — layered:**
1. **Immediate**: `kubectl cordon` + drain the offending workloads, or scale the tenant down; apply a temporary `ResourceQuota`/`LimitRange` to the namespace; throttle via APF FlowSchema for apiserver abuse.
2. **Requests/limits enforced**: no BestEffort pods in shared namespaces (LimitRange defaults + a policy engine rule rejecting pods without requests). Memory requests == limits for Guaranteed QoS on critical workloads.
3. **Node isolation**: dedicated node pools with taints/tolerations per tenant or per workload class (batch vs latency-sensitive). **This is the most reliable fix** — a shared node is a shared kernel and a shared IO/network path.
4. **Namespace quotas**: `ResourceQuota` for CPU/memory/storage/object counts/LB services, so one tenant can't exhaust the cluster or the cloud quota.
5. **`pids.max`, ephemeral-storage limits, `io.weight`** — the limits everyone forgets.
6. **APF FlowSchemas + PriorityLevels** so a runaway controller can't starve kubelets and system components (this is exactly what APF was built for).
7. **PriorityClasses**: system-critical > production > batch. Preemption then does the right thing automatically.
8. **RuntimeClass** for untrusted tenants; **user namespaces** to limit escape damage.
9. **Observability**: per-tenant cost/usage dashboards (namespace labels on all metrics), node PSI alerts, eviction alerts, apiserver-abuse alerts by user-agent. **Show tenants their own usage** — most noisy-neighbour problems are solved socially once the data is visible.
10. **Governance**: a documented "you get X" contract, an admission policy that enforces it, and a chargeback/showback loop.

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "Liveness probe checks the database" | Restarts the whole fleet on a dependency blip |
| No `startupProbe` on a slow-starting app | CrashLoopBackOff forever |
| `maxUnavailable: 1` with no `preStop` | 502s on every deploy |
| "RWO means one pod" | It means one **node** — two replicas can corrupt a DB volume |
| NetworkPolicy without `policyTypes: [Ingress, Egress]` | Egress silently unrestricted |
| NetworkPolicy without allowing DNS | Everything breaks mysteriously |
| `failurePolicy: Fail` webhook without excluding `kube-system` | You built a cluster-wide self-lockout |
| Memory limits unset | BestEffort → first evicted under pressure |
| CPU limits set tightly | p99 spikes from CFS throttling with healthy average CPU |
| Editing a ReplicaSet directly | The Deployment controller undoes it |
| HPA on CPU for an I/O-bound service | Scales down while latency explodes |
| PDB `maxUnavailable: 0` with 1 replica | Node drains and cluster upgrades hang forever |
| 50 pods × 20 DB connections, no pooler | You DDoS'd your own database |
| Running migrations inside app startup | N replicas racing |
| Writing an operator for "run this container with these settings" | Unnecessary permanent liability |
| Ignoring `kubectl describe` events in troubleshooting | The answer is usually right there |

## Rapid recall

1. Declarative reconciliation loops; apiserver is the only etcd writer; everything else list-watches with an informer cache; **level-triggered, not edge-triggered**.
2. Pod start: sandbox/pause → CNI → volumes → init containers → postStart → startupProbe → liveness+readiness → EndpointSlice.
3. Pod stop: Terminating → removed from endpoints → **preStop** → SIGTERM → grace period (from preStop start) → SIGKILL.
4. Liveness = restart (test only self); readiness = traffic (may test deps); startup = protect slow starts.
5. Deployments own ReplicaSets; `maxUnavailable: 0` + `maxSurge`; readiness gates the rollout.
6. ClusterIP is a DNAT target; EndpointSlices hold ready pods; kube-proxy programs iptables/IPVS; **LB is per-connection, not per-request**.
7. ConfigMap env vars never update; volume mounts update slowly and not with `subPath`; **changing config doesn't restart pods** → checksum annotation or Reloader.
8. Secrets are base64 → RBAC + encryption at rest + external store + short-lived workload identity.
9. **Requests schedule, limits cap.** CPU compressible (throttle), memory incompressible (OOMKill). Guaranteed/Burstable/BestEffort = eviction order.
10. Taints repel, tolerations permit, affinity attracts. `topologySpreadConstraints` for even spread; `DoNotSchedule` can strand pods.
11. Operators: CRD + controller with informers/workqueue; idempotent level-triggered reconcile; status subresource, finalizers, owner refs, leader election, reconcile metrics.
12. Admission order: mutating → validation → validating. Webhooks = availability risk; prefer PSA + VAP/CEL where possible.
13. `ndots:5` amplifies DNS; NodeLocal DNSCache fixes the conntrack UDP race causing 5s timeouts.
14. `WaitForFirstConsumer` for zonal disks; `Delete` reclaim destroys data; RWX needs NFS/EFS/CephFS.
15. Autoscaling cascade (HPA → CA) takes minutes → Karpenter, over-provisioning, or KEDA scale-from-zero; **VPA and HPA fight on CPU/memory**.
16. etcd: quorum, 2 GB quota, `wal_fsync` p99 < 10ms, defrag one member at a time, **test your restores**.
17. Pending = requests/taints/affinity/PVC/quota — read `describe` events.
18. Zero-downtime = expand-contract schema + preStop + probes + PDB + connection pooler + progressive delivery + feature flags.

→ Next: [`08-CI-CD-and-GitOps`](../08-CI-CD-and-GitOps/README.md)
