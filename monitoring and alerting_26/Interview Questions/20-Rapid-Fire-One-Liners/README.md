# 20 · Rapid-Fire One-Liners

**The night-before file.** ~250 questions with 1–3 sentence answers. Designed for scanning, not studying — the deep versions live in the topic files.

**How to use it:** read a section, cover the answers, recite aloud. Anything you stumble on, follow the link and read the full treatment. **Answers here are deliberately compressed — in a real interview, expand with an example and a trade-off.**

---

## 🔥 Linux & OS

1. **Process vs thread?** A process is an isolated execution environment with its own address space; threads share one process's address space and file descriptors but have their own stack and registers. Threads are cheaper to create and switch, and a crash in one usually takes down the process.
2. **What's a context switch?** Saving one execution context's registers/stack pointer and restoring another's. Process switches also swap page tables (TLB flush), which is why thread switches are cheaper.
3. **What is `fork()` + `exec()`?** `fork` clones the process (copy-on-write, so it's cheap), `exec` replaces its image. That's how every shell runs a command.
4. **Zombie vs orphan process?** A **zombie** has exited but its parent hasn't `wait()`ed, so its exit status lingers in the process table. An **orphan**'s parent died, so it's reparented to init/PID 1, which reaps it.
5. **Why does PID 1 matter in containers?** It ignores signals it has no handler for and must reap orphaned children — so a shell-form `CMD` or an app without signal handling causes hard kills and zombie accumulation. Fix: `--init` (tini).
6. **What is a file descriptor?** An integer handle to an open file, socket, or pipe, tracked per process. Exhaustion gives `too many open files` and usually means a leak (unclosed responses, connections) — check `/proc/<pid>/fd`.
7. **Hard link vs symlink?** A hard link is another directory entry pointing at the same inode (same filesystem only, survives the original's deletion); a symlink is a special file containing a path (cross-filesystem, breaks if the target moves).
8. **What is `inode` exhaustion?** Running out of filesystem metadata entries — usually millions of tiny files (sessions, cache, mail queues). `df -h` shows free space, `df -i` shows free inodes; the second one is the surprise.
9. **Buffered vs unbuffered I/O?** Buffered writes go to the page cache and are flushed later by the kernel; `fsync` forces them to durable storage. Unbuffered I/O (O_DIRECT) bypasses the page cache entirely.
10. **What does `vm.swappiness` do?** Biases the kernel between reclaiming page cache and swapping anonymous pages. Low (1–10) for database servers; high for workloads with cold anonymous memory.
11. **Load average: what is it really?** The exponentially-decayed average count of runnable **plus uninterruptible-sleeping (D state)** tasks over 1/5/15 minutes. High load with low CPU usually means **I/O wait**, not compute.
12. **What is D state?** Uninterruptible sleep — typically blocked on I/O. Processes in D state can't be killed (even with SIGKILL) until the I/O completes; a pile of them means a storage or NFS problem.
13. **`strace` vs `ltrace`?** `strace` traces syscalls (kernel boundary — the useful one); `ltrace` traces library calls. `strace -c` gives a syscall histogram, which localises most I/O problems fast.
14. **How do you find what's using CPU?** `top`/`htop` for the process, `pidstat 1` per process, `perf top` for kernel/user symbols, and a **flame graph** (perf/async-profiler/py-spy) for the actual function.
15. **`ps` vs `top` vs `pidstat`?** `ps` is a snapshot, `top` is a live view, `pidstat` is per-process time series (scriptable). For an investigation, `pidstat 1` and `/proc/<pid>/stat` are the reliable ones.
16. **What is the OOM killer?** When the kernel can't satisfy an allocation, it scores processes (`oom_score`, based on memory use and `oom_score_adj`) and SIGKILLs the worst. Check `dmesg -T | grep -i oom`. In containers the **cgroup** OOM fires at the limit even when the node has free memory.
17. **How do you protect a process from the OOM killer?** `oom_score_adj = -1000` (or a low value), plus Guaranteed QoS in Kubernetes. Better: fix the leak and set correct limits.
18. **What's in `/proc`?** A virtual filesystem exposing kernel and per-process state: `/proc/meminfo`, `/proc/cpuinfo`, `/proc/loadavg`, `/proc/net/{tcp,sockstat,snmp}`, `/proc/<pid>/{status,limits,fd,stat,cmdline,environ}`. It's the ground truth behind every monitoring tool.
19. **What is PSI?** Pressure Stall Information (`/proc/pressure/{cpu,memory,io}`) — the percentage of time tasks were stalled waiting for a resource. It's a far better saturation signal than utilisation, and it's what cgroup v2 exposes.
20. **`ulimit` vs cgroups?** `ulimit` sets per-process resource limits (fds, processes, memory) enforced by the kernel at the process level; cgroups limit and account a whole process *tree*. Containers use both.
21. **What is a race condition vs a data race?** A **race condition** is a correctness bug from timing/ordering (two operations interleave badly). A **data race** is the specific case of unsynchronised concurrent access to the same memory with at least one write — in Go/C++/Java it's undefined behaviour.
22. **Mutex vs semaphore?** A mutex is an ownership-based lock (one holder, unlocked by the owner); a counting semaphore is a permit pool (N holders, released by anyone). Use a mutex for state, a semaphore for bounding concurrency.
23. **What is `epoll`?** Linux's scalable I/O readiness notification: register fds once, get told which are ready — O(ready) instead of O(all fds) like `select`/`poll`. Level-triggered by default; edge-triggered is faster and easier to get wrong.
24. **How does a TCP server accept connections?** `socket` → `bind` → `listen(backlog)` → `accept` in a loop. Two queues: the SYN queue (half-open) and the accept queue (completed, awaiting accept). Overflowing the accept queue causes resets/timeouts under load.
25. **What is `TIME_WAIT` and is it bad?** A normal TCP state (2×MSL) on the side that closed first, ensuring delayed packets aren't misinterpreted. It only hurts at high connection churn, where it exhausts ephemeral ports — the fix is connection reuse, not `tcp_tw_recycle` (removed in Linux 4.12).
26. **What does `SO_REUSEADDR` do?** Lets you bind to a port in TIME_WAIT — essential for fast server restarts. `SO_REUSEPORT` lets multiple sockets bind the same port for kernel-level load balancing.
27. **How do you debug "connection refused" vs "connection reset" vs "timeout"?** **Refused** = nothing listening (or an RST from the stack). **Reset** = a connection existed and was torn down abnormally (LB drain, accept-queue overflow with abort, app crash, firewall RST). **Timeout** = packets silently dropped (conntrack full, MTU blackhole, security group, saturation, DNS).

---

## 🔥 Networking

28. **What happens when you type a URL?** DNS resolution → TCP handshake (or QUIC) → TLS handshake → HTTP request → server processing → response → rendering. Each step is a separate failure domain with its own diagnostic.
29. **TCP vs UDP?** TCP is connection-oriented, ordered, reliable, congestion-controlled; UDP is a datagram with no ordering, no retransmission, and no congestion control. TCP for correctness, UDP for latency/loss-tolerance/streaming — and QUIC builds TCP-like reliability on UDP to escape head-of-line blocking.
30. **What is head-of-line blocking?** One lost packet stalls everything queued behind it because TCP delivers bytes in order. It's the reason HTTP/2 over TCP still has a latency problem, and the reason HTTP/3 uses QUIC's independent streams.
31. **What is congestion control?** The sender inferring network capacity (`cwnd`) to avoid overrunning it: slow start, congestion avoidance, fast retransmit/recovery. CUBIC is loss-based (the Linux default); BBR models bandwidth and RTT and does better on lossy high-bandwidth paths.
32. **What is the bandwidth-delay product?** Bandwidth × RTT — the amount of data "in flight" needed to fill the pipe. It determines the socket buffer sizes you need; a small buffer on a high-BDP path caps your throughput regardless of bandwidth.
33. **Symmetric vs asymmetric encryption?** Symmetric (AES) uses one shared key and is fast; asymmetric (RSA/ECDSA) uses a public/private pair and is slow, so it's used for key exchange and signatures. TLS uses asymmetric to establish a symmetric session key.
34. **What is forward secrecy?** Session keys derived from an ephemeral exchange (ECDHE), so compromising the server's long-term private key doesn't decrypt previously captured traffic. TLS 1.3 makes it mandatory by removing static RSA key exchange.
35. **What is mTLS?** Both peers present and validate certificates — mutual authentication plus encryption, without relying on network position. It's the basis of service-mesh and zero-trust service-to-service security.
36. **What is SNI?** Server Name Indication — the hostname in the TLS ClientHello, letting one IP serve many certificates. It's plaintext (unless ECH), and a load balancer terminating TLS must handle it.
37. **What is ALPN?** Application-Layer Protocol Negotiation, in the TLS handshake — how HTTP/2 vs HTTP/1.1 is chosen without an extra round trip.
38. **What is OCSP stapling?** The server fetches and attaches a signed certificate-status response, so the client doesn't make a slow, privacy-leaking call to the CA. Without it, OCSP timeouts cause mysterious handshake latency.
39. **What's the difference between a CNAME and an alias record?** A CNAME points a name at another name and **cannot coexist with other records at the same name, so it can't be used at the zone apex**. Alias/ANAME records (provider-specific) resolve to A records server-side and work at the apex.
40. **What is a DNS TTL and why doesn't it work as expected?** It tells resolvers how long to cache. Resolvers ignore or extend it, clients cache independently, and JVMs historically cached forever — so TTL is a **floor on failover time, not a promise**.
41. **What is split-horizon DNS?** Serving different answers depending on where the query comes from (inside vs outside the VPC). Powerful, and a debugging trap: "it resolves to the wrong IP" is often correct behaviour from the wrong vantage point.
42. **What is Anycast?** Many nodes advertising the same IP; the network routes you to the nearest. Used by DNS root servers, CDNs, and global load balancers. Trade-off: routing is out of your control and can shift mid-session.
43. **What is BGP?** The inter-domain routing protocol — ASes exchanging reachability with path attributes and local policy. It's trust-based, which is why hijacks and leaks happen, and why RPKI/ROAs exist.
44. **What is NAT?** Rewriting IP addresses/ports at a boundary — SNAT for egress (many private IPs behind one public IP), DNAT for ingress (a public port to a private host). It's how `docker -p` and Kubernetes Services work.
45. **What is conntrack and why does it hurt?** The kernel's connection-tracking table, used by NAT and stateful firewalls. It has a fixed size (`nf_conntrack_max`); under high connection churn it fills and **drops packets** with `nf_conntrack: table full` — an intermittent, miserable failure.
46. **What is a VXLAN?** L2-over-L3 encapsulation (UDP port 4789) that extends a network across a routed fabric — the basis of most Kubernetes overlay CNIs. Cost: ~50 bytes of overhead, hence the MTU reduction.
47. **What is the MTU blackhole problem?** When Path MTU Discovery fails (ICMP type 3 code 4 blocked), large packets are silently dropped. Signature: **handshakes and small requests work, large transfers hang.** Test with `ping -M do -s 1472`.
48. **What is MSS clamping?** Rewriting the TCP MSS option in SYN packets so both ends use a segment size that fits the path MTU. The standard fix for overlay/VPN MTU problems.
49. **What is a veth pair?** A virtual Ethernet cable: two interfaces where whatever enters one exits the other. It's how a container's `eth0` connects to the host bridge.
50. **What is IPVS?** A kernel L4 load balancer using hash tables — O(1) lookup with real algorithms (rr, lc, sh), versus iptables' O(n) rule walk. `kube-proxy` uses it in large clusters.
51. **What is DSR (direct server return)?** The load balancer sends requests to the backend but the backend replies directly to the client — avoiding the LB on the return path. Big win for asymmetric traffic (downloads, video).
52. **What is the Proxy Protocol?** A small header prepended by an L4 load balancer carrying the original client IP/port, since NAT loses it. Both ends must agree, or you get garbage.
53. **L4 vs L7 load balancing?** L4 balances **connections** using the 5-tuple; L7 terminates and balances **requests** using host/path/headers. L7 enables retries, routing and observability; L4 is faster and protocol-agnostic.
54. **Why does HTTP/2 break L4 load balancing?** H2 multiplexes many requests over one long-lived connection, so an L4 LB pins a client to one backend indefinitely. Fix: L7 LB, a mesh, client-side LB, or `max_connection_age` with jitter.
55. **What is a CDN and what does it actually do?** Caches content at edge PoPs close to users, absorbing traffic and reducing origin load and latency. It also terminates TLS, provides WAF/DDoS protection, and — critically — a **cache-hit-ratio drop turns into an origin overload incident**.
56. **What are the security headers that matter?** `Content-Security-Policy` (the real XSS mitigation), `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, `Permissions-Policy`, `Cross-Origin-Opener-Policy`/`Resource-Policy`. Cheap, and they're a common audit finding.
57. **What is CORS?** A browser-enforced policy where the server declares which origins may read its responses via `Access-Control-Allow-*` headers. It's a *browser* mechanism — server-to-server calls ignore it entirely.
58. **What is a WebSocket?** An HTTP upgrade to a full-duplex persistent connection. Consequences: long-lived connections defeat per-connection LB, need idle timeouts tuned, and need explicit reconnection logic on the client.

---

## 🔥 Kubernetes

59. **What is a pod?** The smallest schedulable unit: one or more containers sharing a **network namespace** (one IP, `localhost` works between them), IPC namespace, and volumes. The **pause container** holds the namespaces.
60. **What is the pause container?** A tiny process that owns the pod's network/IPC namespaces so application containers can restart without losing them. It's why `localhost` works between containers in a pod.
61. **Deployment vs StatefulSet vs DaemonSet vs Job?** **Deployment** for stateless replicas (interchangeable, random names). **StatefulSet** for stable identity and storage (ordered, `pod-0/1/2`, PVC per replica). **DaemonSet** for one pod per node (log collectors, CNI, monitoring agents). **Job/CronJob** for run-to-completion work.
62. **What is a ReplicaSet and why don't you edit it?** It maintains N pod replicas for a Deployment. Editing it directly gets reverted by the Deployment controller — you change the Deployment's pod template.
63. **What is an EndpointSlice?** The list of ready pod IPs/ports for a Service, sharded for scale (it replaced Endpoints). kube-proxy watches it to program the DNAT rules.
64. **What is a headless Service?** `clusterIP: None` — DNS returns all pod IPs instead of a virtual IP. Used for StatefulSets and for client-side load balancing (gRPC).
65. **What does a ClusterIP actually exist as?** Nowhere. It's a virtual IP that only exists as a DNAT target in every node's iptables/IPVS/eBPF rules.
66. **Requests vs limits?** **Requests** drive scheduling and are the guaranteed share; **limits** cap usage. CPU limits throttle (CFS quota per 100ms period); memory limits OOMKill.
67. **Why is CPU compressible and memory not?** CPU can be throttled — the workload slows down. Memory can't be taken back, so exceeding the limit means the kernel kills the process.
68. **QoS classes?** **Guaranteed** (requests == limits for CPU and memory on every container), **Burstable** (some requests set), **BestEffort** (nothing set). Eviction order is BestEffort → Burstable → Guaranteed.
69. **Why do people remove CPU limits?** Because CFS throttling is enforced per 100ms period: a burst to 2 cores for 20ms gets throttled even if the average is under quota, producing **p99 latency spikes with healthy-looking average CPU**.
70. **What is CPU throttling and how do you detect it?** `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total`. Above a few percent with latency problems means the limit is too tight or the workload is bursty.
71. **What are taints and tolerations?** A taint makes a **node repel** pods; a toleration lets a pod **be scheduled there** (it doesn't attract). Effects: `NoSchedule`, `PreferNoSchedule`, `NoExecute` (evicts running pods).
72. **What is node affinity?** Scheduling constraints on node labels — `requiredDuringScheduling...` (hard) and `preferredDuringScheduling...` (soft). Attraction, versus taints' repulsion.
73. **What is topologySpreadConstraints?** Even distribution across a topology key (zone, node) with `maxSkew`. `DoNotSchedule` is a hard guarantee that can strand pods; `ScheduleAnyway` is soft.
74. **What is a PodDisruptionBudget?** A guarantee about voluntary disruptions (drains, upgrades): `minAvailable` or `maxUnavailable`. **`maxUnavailable: 0` with one replica blocks drains forever.**
75. **What is a PriorityClass?** Scheduling priority plus preemption rights. Higher-priority pods can evict lower-priority ones when resources are short.
76. **What is preemption?** The scheduler evicting lower-priority pods to place a higher-priority pending pod. It respects PDBs where possible, which can block it.
77. **The three probes?** **startupProbe** (has it finished starting — disables the others until it succeeds), **livenessProbe** (is it deadlocked — **restarts** the container), **readinessProbe** (can it serve — **removes from endpoints**).
78. **What's the classic liveness-probe mistake?** Having liveness check a dependency. The dependency blips, every pod fails liveness, the whole Deployment restarts at once, and the probe caused the outage.
79. **What is `terminationGracePeriodSeconds`?** The window from the start of **preStop** until SIGKILL. Default 30s. It must cover preStop + drain + LB deregistration.
80. **Why `preStop: sleep 10`?** Endpoint removal and kube-proxy/ingress/LB propagation are eventually consistent. Sleeping before SIGTERM lets propagation finish while the app is still serving — otherwise you get 502s on every deploy.
81. **What is an init container?** A container that runs to completion before the app containers start, sequentially. Used for setup, waiting on dependencies, and loading config.
82. **What is a sidecar container (native)?** Since 1.28+, an init container with `restartPolicy: Always` — starts before app containers, stays alive for the pod's lifetime, and terminates last. The correct way to run proxies and log shippers.
83. **What is a ConfigMap's update behaviour?** **Env vars never update. Volume mounts update after up to ~1 minute — except `subPath` mounts, which never update.** And changing a ConfigMap doesn't restart pods; you need a rollout or a checksum annotation.
84. **How do you make a config change restart a Deployment?** A checksum annotation on the pod template (`checksum/config: {{ ... | sha256sum }}`), or `kubectl rollout restart`, or Reloader.
85. **Are Kubernetes Secrets encrypted?** No — base64-encoded. Real protection is RBAC, **etcd encryption at rest**, an external secret store (Vault/External Secrets Operator), and short-lived workload identity.
86. **What is `automountServiceAccountToken: false`?** Stops the pod getting an API token it doesn't need. Every automounted token is an apiserver credential an attacker can use.
87. **What is a ServiceAccount vs a user?** ServiceAccounts are in-cluster identities for workloads (Kubernetes-native, token-based). "Users" are external identities managed by your IdP and mapped in via OIDC/webhook — Kubernetes has no user object.
88. **What is RBAC's four-object model?** `Role`/`ClusterRole` (rules) and `RoleBinding`/`ClusterRoleBinding` (who gets them, at what scope). A ClusterRole can be bound by a RoleBinding to grant cluster-wide verbs in one namespace.
89. **Which RBAC grants are effectively cluster-admin?** `get/list` on **secrets**, `create` on **pods/exec**, and `create` on **ClusterRoleBindings**. Audit those three first.
90. **What is Pod Security Admission?** The PSP replacement: three fixed standards (`privileged`, `baseline`, `restricted`) enforced per namespace in `audit`/`warn`/`enforce` modes. Use `restricted` for app namespaces.
91. **What is a mutating vs validating admission webhook?** Mutating runs first and can change the object; validating runs after (in parallel) and can only accept/reject. `failurePolicy: Fail` on a broken webhook is a cluster-wide outage — exclude `kube-system`.
92. **What is ValidatingAdmissionPolicy?** In-tree CEL-based admission validation — **no webhook, no extra latency, no availability risk**. GA in recent versions; the direction of travel.
93. **What is a CRD?** A custom API type registered with the apiserver, so you can `kubectl get` your own objects. Paired with a controller, it's the operator pattern.
94. **What is an operator?** A CRD plus a custom controller that encodes operational knowledge — promotion, backup, scaling, certificate rotation. Use it for stateful decision-heavy operations, not for "run this container".
95. **What is a finalizer?** A marker in `metadata.finalizers` that blocks deletion until the controller removes it — used to clean up external resources. A stuck finalizer means the object can't be deleted; the escape hatch is patching it to `[]`.
96. **What are owner references?** Parent-child links enabling cascading garbage collection. Deleting the parent deletes the children (foreground or background policy).
97. **What is the status subresource?** A separate API endpoint for status updates, so `kubectl apply` doesn't clobber controller-written status and controllers don't fight users over spec.
98. **What is a reconcile loop?** A controller reading desired `spec`, observing actual state, and acting to reduce the difference — repeatedly and **level-triggered**, so missed events self-heal on resync.
99. **Why must reconcile be idempotent?** Because the workqueue deduplicates keys and a reconcile can run many times for the same change. Same input → same result, safe to repeat.
100. **What is `kubectl diff`?** Shows what an apply would change against the live cluster. Cheap, and it catches more mistakes than reading YAML.
101. **What is an ephemeral container?** `kubectl debug --image=... --target=<container>` — a debug container sharing the target's namespaces. The way to debug a distroless/scratch image.
102. **What is `kubectl top` measuring?** metrics-server's working-set memory and CPU rate — not real-time, ~15s resolution, and it doesn't see throttling or PSI.
103. **What does `Pending` almost always mean?** A scheduling failure about **requests**, not usage: insufficient CPU/memory/ephemeral-storage, an unsatisfiable taint/affinity, a PVC that can't bind, or a ResourceQuota. Read `kubectl describe pod` events.
104. **What does `ImagePullBackOff` mean?** The image can't be pulled: wrong name/tag/digest, private registry auth (`imagePullSecrets`), a missing architecture in the manifest, or registry rate limits.
105. **What does `CrashLoopBackOff` mean?** The container keeps exiting; Kubernetes backs off exponentially before restarting. Read `kubectl logs --previous` and the exit code from `describe`.
106. **Exit codes 137 / 143 / 126 / 127?** 137 = SIGKILL (usually OOMKilled or a liveness kill), 143 = SIGTERM, 126 = not executable, 127 = command not found. Check `lastState.terminated.reason`.
107. **What is `WaitForFirstConsumer`?** A StorageClass volume-binding mode that delays provisioning until the pod is scheduled — **required for zonal disks**, or you get a PVC in one AZ and a pod that can only run in another.
108. **What does ReadWriteOnce actually mean?** One **node**, not one pod. Two replicas on the same node can both mount it and corrupt a database. Use `ReadWriteOncePod` when you mean it.
109. **What is HPA scaling relative to?** `averageUtilization` is relative to the CPU/memory **request**, not the limit. Wrong requests → wrong autoscaling.
110. **Why is CPU a bad HPA metric for I/O-bound services?** CPU stays low while the service is blocked on a downstream dependency, so HPA scales *down* while latency explodes. Scale on request rate, queue depth, or concurrency instead.
111. **What is VPA's problem?** `updateMode: Recreate` restarts pods, and it **conflicts with HPA on CPU/memory** (they fight). Use `Off` mode for recommendations only.
112. **What is KEDA?** Event-driven autoscaling from 60+ sources (queue depth, Kafka lag, cron, Prometheus) — and the standard way to scale to zero.
113. **What is Karpenter?** A Kubernetes node autoscaler that provisions the right instance type directly from pending pod requirements, with no node groups, plus consolidation. Faster and cheaper than the Cluster Autoscaler.
114. **How long does the autoscaling cascade take?** HPA adds pods → Pending → cluster autoscaler/Karpenter adds a node → boot → CNI → image pull: **5–10 minutes.** For spiky traffic you need over-provisioning, prediction, or warm pools.
115. **What is etcd's role and its limits?** The cluster's only state store (Raft, odd member count, quorum required). Default quota 2 GB → `NOSPACE` alarm → read-only cluster. `etcd_disk_wal_fsync_duration_seconds` p99 < 10ms is the health metric.
116. **What is API Priority and Fairness?** The apiserver's queueing system that replaces max-inflight, so one runaway controller can't starve the kubelets. Check APF rejections when the apiserver is degraded.
117. **What is a Node lease?** A lightweight heartbeat (every ~10s) separate from the full node status, reducing apiserver load. `NotReady` means leases stopped within the monitor grace period.
118. **What does `NotReady` mean?** The kubelet stopped reporting or the node is unhealthy. Then `node.kubernetes.io/unreachable` (NoExecute) evicts pods after `tolerationSeconds` (default 300s).
119. **What causes intermittent NotReady?** Disk/PID/memory pressure, an unhealthy container runtime, a network partition to the apiserver, kubelet CPU starvation, clock skew or **kubelet certificate expiry**, and CNI failures.
120. **What is `ndots:5`?** The pod DNS search-domain threshold: names with fewer than 5 dots are tried against every search domain first. External lookups get 4–5× amplified; fix with trailing dots, `ndots: 2`, or NodeLocal DNSCache.
121. **Why do DNS lookups sometimes take exactly 5 seconds?** A UDP conntrack insert race drops the parallel A/AAAA queries; the resolver retries after 5s. **NodeLocal DNSCache** fixes it.
122. **What is a NetworkPolicy's default behaviour?** Default-allow. Once any policy selects a pod, that pod becomes default-deny for the declared `policyTypes`. Omitting `Egress` from `policyTypes` leaves egress wide open.
123. **What must you always allow in a default-deny NetworkPolicy?** DNS (port 53 to the CoreDNS pods), or everything breaks confusingly.
124. **What is a RuntimeClass?** Selects an alternative container runtime (gVisor's `runsc`, Kata's microVM) and its node pool. The answer for untrusted workloads.
125. **What are user namespaces in Kubernetes?** Mapping container UID 0 to an unprivileged host UID (`hostUsers: false`), so an escape doesn't yield host root. GA in 1.36; the strongest single escape mitigation.
126. **What is Ingress vs Gateway API?** Ingress is a minimal L7 HTTP routing API driven by controller-specific annotations (not portable). Gateway API is the successor: role-oriented (`GatewayClass`/`Gateway`/`HTTPRoute`), expressive (weights, header matching, mirroring), and extensible.
127. **What is a service mesh?** An infrastructure layer (usually sidecar proxies) providing mTLS, retries, circuit breaking, traffic splitting, and L7 telemetry outside the application. Costs ~0.5–2 ms and 50–100 MB per pod, plus a control plane to run.
128. **What is Istio ambient mode?** Sidecar-less: a per-node **ztunnel** handles L4 mTLS, and optional **waypoint proxies** add L7 features per namespace. The answer to sidecar overhead.
129. **What is the Gateway API's actual design win?** Separating ownership: platform teams own `Gateway`s (listeners, TLS), application teams own `HTTPRoute`s. That's an organisational improvement, not just a YAML change.
130. **What is `kubectl drain` doing?** Cordoning the node and evicting pods, respecting PDBs. A `maxUnavailable: 0` PDB on a single-replica Deployment blocks it indefinitely.

---

## 🔥 Containers & Docker

131. **What is a container?** A normal process with **namespaces** (what it can see), **cgroups** (what it can use), and a layered root filesystem, plus capabilities/seccomp/LSM restrictions. One kernel, no hypervisor.
132. **Name the namespaces.** PID, mount, network, UTS, IPC, user, cgroup, time. Check with `ls -l /proc/<pid>/ns/`.
133. **cgroups v1 vs v2?** v1 has a separate hierarchy per controller; v2 has one unified tree, adds PSI pressure metrics, `memory.high` throttling, safe delegation, and correct memory+IO interaction. Modern Kubernetes features require v2.
134. **What is overlayfs?** The union filesystem: read-only `lowerdir` layers + a writable `upperdir` + a `workdir`. Copy-on-write: modifying a file copies it up; deleting creates a **whiteout**.
135. **Why doesn't deleting a file in a later layer shrink the image?** Because deletion is a whiteout in a *new* layer; the original bytes remain in the earlier layer. Install and remove in the same `RUN`.
136. **How does Docker layer caching work?** BuildKit reuses a layer if the instruction string matches exactly (`RUN`) or the copied content checksums match (`COPY`), **and all preceding layers are cached**. Cache invalidation runs forward.
137. **Why copy `package.json` before the source?** So a code-only change doesn't invalidate the dependency-install layer. The single most valuable Dockerfile ordering trick.
138. **What are BuildKit cache/secret/ssh mounts?** `--mount=type=cache` persists dependency caches across builds without baking them into a layer; `type=secret` passes credentials that never land in a layer; `type=ssh` gives private-repo access. These are the correct answers to build-time secrets.
139. **ENTRYPOINT vs CMD?** `ENTRYPOINT` is the fixed executable and `CMD` supplies default arguments that `docker run` args replace. Use **exec form** for both — shell form makes `/bin/sh` PID 1 and breaks signal handling.
140. **What is a multi-stage build?** Building in a fat stage and copying only the artifact into a minimal runtime stage. 1.8 GB → 10 MB, fewer CVEs, no shell for an attacker.
141. **Alpine's caveat?** **musl libc, not glibc**: no prebuilt wheels for many Python C extensions, different DNS resolver behaviour, and subtle differences for JVM/Go. Smaller isn't free.
142. **Distroless's caveat?** No shell and no coreutils, so you can't `exec` in to debug. Use `kubectl debug` ephemeral containers or a separate debug build target.
143. **What is `.dockerignore` for?** Keeping `node_modules`, `.git`, build output and secrets out of the build context — for cache stability, build speed, and leak prevention.
144. **runc vs containerd vs CRI-O vs dockershim?** **runc** is the OCI low-level runtime that actually creates the namespaces/cgroups; **containerd**/**CRI-O** are high-level runtimes managing images and lifecycle; **dockershim** was kubelet's adapter to Docker, removed in 1.24.
145. **What is gVisor / Kata?** gVisor (`runsc`) is a user-space kernel intercepting syscalls — strong isolation with syscall overhead and compatibility gaps. Kata runs a lightweight VM per pod — hardware isolation with seconds of startup. Both for untrusted code.
146. **What does `docker run -p 8080:80` actually do?** Creates a veth pair to a bridge, assigns an IP, and installs iptables DNAT + MASQUERADE rules mapping host:8080 to container:80.
147. **Container network modes?** `bridge` (default), custom bridge (**DNS by container name** — always prefer), `host` (shares the host netns, no NAT), `none` (loopback only), `container:<id>` (**exactly what a Kubernetes pod does**), `overlay`, `macvlan`.
148. **Volumes vs bind mounts vs tmpfs?** Named volumes are Docker-managed persistent storage; bind mounts expose an arbitrary host path (fast, bypasses CoW, permission headaches); tmpfs is RAM-backed and counts against the memory limit.
149. **Why is `VOLUME` in a Dockerfile usually a mistake?** It creates anonymous volumes that are hard to clean, and any later `RUN` writing to that path is silently discarded.
150. **What does `depends_on: condition: service_healthy` fix?** Plain `depends_on` only orders startup, not readiness — so your app connects before Postgres accepts connections and crash-loops. The most common Compose bug.
151. **How do you make an image reproducible?** Pinned base digest, locked dependencies, `SOURCE_DATE_EPOCH` for timestamps, sorted file order, no build-time-injected dates, no ambient credentials.
152. **What is lazy image pulling?** Stargz/eSOCI/SOCI snapshotters fetch only the blocks needed to start, so cold starts drop from minutes to seconds even for large images. The modern answer for scale-from-zero.
153. **How do you find where image size went?** `docker history --no-trunc --human`, `dive` (per-layer file analysis), and `docker buildx build --progress=plain` for step timings.

---

## 🔥 CI/CD & GitOps

154. **CI vs CDelivery vs CDeployment?** CI = integrate and test on every commit. Continuous **Delivery** = always deployable, human presses the button. Continuous **Deployment** = every passing change goes to production automatically.
155. **What are the DORA four keys?** Lead time for changes, deployment frequency, change failure rate, and time to restore from a failed deployment. Outcome metrics, not activity metrics.
156. **What is the GitOps model?** Declarative desired state in Git, pulled by an in-cluster agent, continuously reconciled. Four principles: declarative, versioned/immutable, pulled automatically, continuously reconciled.
157. **Why is pull better than push?** The agent runs **inside** the cluster with scoped RBAC, so CI never holds cluster credentials — and you get drift detection, `git revert` rollback, and free audit.
158. **What are GitOps's real limitations?** Git doesn't hold secrets; imperative work (migrations, one-off jobs) doesn't fit; emergency access needs a break-glass path; and thousands of Applications create apiserver load and sync storms.
159. **Argo CD vs Flux?** Argo CD: excellent UI, ApplicationSets, AppProject multi-tenancy, sync waves/hooks, deep Argo Rollouts integration. Flux: composable controllers, built-in image automation, API-first, no UI. Both CNCF-graduated.
160. **What are Argo CD sync waves and hooks?** Waves (`sync-wave: "-1"`) order resource application (CRDs → namespaces → config → workloads). Hooks (`PreSync`/`Sync`/`PostSync`/`SyncFail`) run Jobs at those points — **`PreSync` is where database migrations go**.
161. **What do `selfHeal` and `prune` do?** `selfHeal` reverts manual drift; `prune` deletes resources removed from Git. **Prune on a bad merge can delete production** — scope it deliberately.
162. **What is an ApplicationSet?** One template generating many Applications from a generator (Git directory, cluster list, matrix, pull request). The fleet-management primitive.
163. **What is progressive delivery?** Canary or blue/green with **automated metric analysis and automatic rollback** (Argo Rollouts, Flagger). A canary with a human watching a dashboard is just a slow rolling update.
164. **What is the difference between deploy and release?** **Deploy** puts code in production; **release** exposes it to users. **Feature flags decouple them**, which is why flag-off is the fastest rollback that exists.
165. **What does "build once, promote the artifact" mean?** One immutable artifact (image digest) moves through dev/staging/prod; only configuration varies. Building per environment means you tested something you didn't ship.
166. **What are the CI security essentials?** Least-privilege `GITHUB_TOKEN` (`permissions: {}`), **OIDC federation instead of stored cloud keys**, no secrets to fork PRs, actions **pinned by commit SHA**, images by digest, signed artifacts + SBOM + provenance, ephemeral isolated runners, and verification at admission.
167. **What is SLSA?** A build-integrity framework with levels: provenance exists (L1), signed and tamper-resistant (L2), hardened isolated builds with non-falsifiable provenance (L3). The vocabulary for "how much can I trust this artifact?"
168. **What is an SBOM and what is it for?** A Software Bill of Materials (SPDX/CycloneDX) listing components. Its real value is the **reverse lookup**: CVE → affected images → which environments run them, in minutes.
169. **What is VEX?** Vulnerability Exploitability eXchange — an assertion of whether a CVE actually affects you (`not_affected`, `affected`, `fixed`). It's what turns 4,000 scanner findings into 3 tasks.
170. **Why is a slow pipeline a reliability problem?** Slow feedback makes developers batch changes, and larger batches are harder to bisect and riskier. Pipeline duration is a first-class engineering metric.
171. **How do you fix flaky tests?** Classify failures for two weeks, fix the top causes (shared fixtures, port collisions, `sleep`-based waits, execution-order dependence, unmocked network), isolate test resources, quarantine with alerts, and track a flake-rate SLO. **Silent retries hide failures.**
172. **What do you test about infrastructure in CI?** `kubeconform`/`kubeval` on manifests, `conftest`/Kyverno policies, `helm lint` + `helm template --validate`, `promtool check rules`, `terraform validate` + `tflint` + `checkov`, `hadolint` on Dockerfiles, `oasdiff` for API breaks, and `pluto`/`kubent` for deprecated APIs.
173. **What is the emergency deploy path supposed to look like?** Faster, not lawless: keep the 3-minute checks (lint, unit, policy, rendered diff), skip the 40-minute ones with a logged override, require one human reviewer, canary anyway, and **reconcile Git afterwards**.

---

## 🔥 Observability & SRE

174. **Monitoring vs observability?** Monitoring answers predefined questions (known unknowns); observability lets you ask new questions of a system from its outputs (unknown unknowns).
175. **The three pillars?** Metrics (how much/how often), logs (what exactly happened), traces (where the time went). Plus profiles (which code) and change events (what changed) — the two people forget.
176. **The four golden signals?** Latency (measure success and failure separately), traffic, errors, and **saturation** — the leading indicator.
177. **RED vs USE?** RED (Rate, Errors, Duration) for **services**; USE (Utilisation, Saturation, Errors) for **resources**. Complementary: RED says the API is slow, USE says the connection pool is saturated.
178. **What is cardinality and why does it matter?** The number of distinct time series = the product of label values. Unbounded labels (`user_id`, raw `path`, `trace_id`) explode the index, OOM the TSDB, and multiply vendor bills.
179. **Pull vs push metrics?** Pull gives you service discovery and a real "target down" signal (`up == 0`); push works for short-lived jobs and behind NAT. Pushgateway is explicitly not a general push mechanism.
180. **Why can't you average percentiles?** Percentiles aren't additive. You must aggregate the **histogram buckets** across instances and compute the quantile from the sum. `avg(p99 per pod)` is meaningless.
181. **`rate()` vs `irate()`?** `rate` averages over the whole range (smooth, use for alerting); `irate` uses only the last two samples (spiky, use for zooming). `rate` needs a range ≥ 4× the scrape interval.
182. **What is `predict_linear` for?** Projecting a trend — `predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0` alerts "disk full in 4 hours". The best proactive alert you can write.
183. **What is `absent()` for?** Detecting a vanished series — an exporter that stopped, or a service that stopped producing its business metric. Catches "it's not failing, it's doing nothing".
184. **Head vs tail sampling?** Head decides at trace start (cheap, but you keep only 1% of errors too); tail buffers the whole trace and decides based on outcome (keeps 100% of errors and slow traces, needs a stateful collector).
185. **What is an exemplar?** A metric data point linked to a specific trace ID — the correct way to pivot from "p99 is high" to "here's a slow request", without a `trace_id` label.
186. **What is OpenTelemetry?** The vendor-neutral standard + SDKs + Collector for traces, metrics and logs over OTLP, plus **semantic conventions** (standard attribute names). Prometheus won the metrics data model; OTel won instrumentation.
187. **What is the OTel Collector's two-tier pattern?** An agent (DaemonSet/sidecar) for local collection, and a gateway (Deployment) for central tail sampling, redaction, batching and export. Sidecar-only can't do tail sampling.
188. **SLI vs SLO vs SLA?** **SLI** = the measured ratio; **SLO** = the internal target; **SLA** = the contractual promise with consequences, and it's always **looser** than the SLO.
189. **What is an error budget?** `1 − SLO` over a window. 99.9% over 30 days = 43.2 minutes. It's the governance mechanism that ends the reliability-vs-velocity argument.
190. **What is the error budget policy?** Budget plentiful → ship fast, take risks, run game days. Budget exhausted → **feature freeze**, all capacity to reliability. Agreed in advance, with leadership sign-off, or it's decoration.
191. **What is multi-window multi-burn-rate alerting?** Two windows (e.g. 1h and 5m) both exceeding a burn-rate multiple (e.g. 14.4×). The long window proves real budget loss, the short one proves it's still happening so the alert resolves promptly.
192. **Symptom-based vs cause-based alerting?** Page on symptoms (user-facing error rate, latency, SLO burn); ticket or dashboard on causes (CPU, restarts) — except causes that predict a symptom with lead time (disk full in 4h, pool at 95%).
193. **What makes an alert good?** Every page requires intelligent human action; it names the current value, threshold, duration, impact and a **runbook link**; and it gets deleted or demoted if it produced no action.
194. **What causes alert fatigue?** Tolerated noise. The fix is a deletion policy and a monthly triage, not better thresholds.
195. **What is toil?** Manual, repetitive, automatable, tactical work with no enduring value that scales linearly with growth. Cap it at 50% of an SRE's time or the team spirals.
196. **What are the incident roles?** **IC** (coordinates, **does not debug**), ops/tech lead (executes), comms lead (status page, stakeholders), scribe (timeline). One IC at a time, with explicit handover.
197. **What's the first rule of incident response?** **Mitigate before you root-cause.** Restore service with the cheapest reversible lever; investigate the preserved evidence afterwards.
198. **What does "blameless" actually mean and why?** A technique, not a kindness: people act on the information available to them, and punishing them gets you less information next time. Ask "how did the system make this reasonable?"
199. **Why is "human error" not a root cause?** Because it stops one layer too early. Ask why the error was possible, why validation/review/canary didn't catch it, and why detection was slow — each is a changeable system property.
200. **What is MTTR made of?** MTTD (detect) + MTTA (acknowledge) + MTTI (identify) + MTTM (mitigate) + MTTV (verify). Measure the decomposition; fix the largest component, usually detection or localisation.
201. **Availability math?** Serial: multiply. Parallel: `1 − Π(1−A)`. **But real failures are correlated** (shared AZ, config, library, provider), so redundancy underdelivers the arithmetic.
202. **Why is retrying dangerous?** Load multiplies by `(1 + retries) × callers` at every layer — a **retry storm** turns a partial failure into a total outage. Use exponential backoff with **jitter** and a retry budget, and retry at one layer only.
203. **What is a thundering herd?** Many clients retrying or reconnecting simultaneously — after an outage, a cache flush, or a mass key/cert expiry. Jitter, staggering and rate-limited warm-up are the fixes.
204. **What is a circuit breaker's half-open state for?** Allowing a limited number of probe requests to test recovery. **You must cap concurrency there**, or the whole flood hits the recovering service and kills it again.
205. **What is load shedding?** Deliberately rejecting low-priority work to survive overload. It must happen **early and at the edge** — shedding after resources are exhausted is too late.
206. **What is backpressure?** Propagating congestion upstream (bounded queues, 429/503 with `Retry-After`) instead of buffering until you OOM.
207. **Why are unbounded queues dangerous?** They convert overload into memory exhaustion and unbounded latency. A bounded queue with rejection fails cleanly and recovers.
208. **What is RTO vs RPO?** RTO = how long you can be down; RPO = how much data you can lose. Set by the business, and they determine the architecture: a 5-minute RPO needs continuous replication, not nightly backups.
209. **Why is a replica not a backup?** Replication faithfully and instantly replicates `DROP TABLE`, a bad migration, ransomware, and application bugs. You need PITR with immutable, access-controlled, cross-account copies — and tested restores.
210. **What is the DR failure that surprises people?** The standby is **cold**: empty caches, cold JIT, unwarmed pools, unscaled capacity — so failing over to 100% traffic causes a second outage. Keep it warm and ramp traffic.
211. **What is chaos engineering?** A disciplined experiment: define steady state, hypothesise it holds, introduce a real-world fault, minimise blast radius, measure, fix, repeat. Without a hypothesis it's just breaking things.
212. **What is a game day?** A scheduled, facilitated practice of a failure scenario. It validates runbooks, finds undocumented dependencies, trains new on-call engineers, and tests escalation — things no design review finds.
213. **What makes on-call sustainable?** ≥ 6–8 people in the rotation, ≤ 2 pages per shift, ≤ 25% of time on-call, compensation and time off in lieu, runbooks for every alert, escalation without stigma, a handover ritual, and weekly triage that deletes non-actionable alerts.
214. **What is queueing theory's practical lesson?** Wait time grows as ρ/(1−ρ), so latency explodes near 100% utilisation. **That's the mathematical justification for headroom**, and why you scale at 60–70%.
215. **What is continuous profiling and why add it?** Always-on, ~1–3% overhead sampling of CPU/memory in production. It's the only thing that answers "**why** is this using 3 cores", and diff profiles against a deploy find regressions directly.
216. **Loki vs Elasticsearch?** Loki indexes **labels only** (cheap, object-storage-backed, grep-speed full-text search); ES/OpenSearch indexes **content** (fast arbitrary search, expensive, operationally heavy). Choose by whether full-text search across all logs is a primary use case.
217. **What is the cheapest log?** The one you never emit. Filter at the edge (node collector), not at the vendor — dropping debug and health-check access logs typically cuts 40–70% for no loss of value.
218. **What are the three health endpoints?** `/livez` (process alive, **no dependency checks**), `/readyz` (can serve traffic, may check critical dependencies), and `/metrics`. Confusing them causes mass restarts or traffic to a broken pod.

---

## 🔥 Cloud, IaC & Security

219. **What is a VPC's public vs private subnet defined by?** The **route table**, not the name. Public = a route to an internet gateway (plus public IPs); private = a route to a NAT gateway or nothing.
220. **Why is a NAT Gateway expensive and risky?** ~$0.045/hr + $0.045/GB, per AZ. One NAT for a whole VPC is a cross-AZ dependency and a SPOF; and routing S3 traffic through it is paying twice — **S3/DynamoDB gateway endpoints are free**.
221. **Security groups vs NACLs?** SGs are stateful, allow-only, attached to ENIs, and can reference other SGs. NACLs are stateless (need explicit ephemeral-port rules), support deny, per-subnet, and evaluated by rule number.
222. **ALB vs NLB?** ALB is L7 (host/path routing, no static IP, WAF-capable). NLB is L4 (static/Elastic IP, ultra-high performance, preserves client IP natively, **cross-zone balancing off by default**).
223. **What does an ALB idle timeout of 60s explain?** Connections resetting at exactly 60 seconds on long requests or idle websockets. Raise it, or send keepalives.
224. **What is IMDSv2 and why enforce it?** IMDSv1 is a plain GET, so an SSRF becomes credential theft. IMDSv2 requires a PUT-issued session token, and **hop limit 1** stops containers reaching it. Enforce `HttpTokens: required`.
225. **What is the confused deputy problem?** A privileged service is tricked into acting for an unauthorised principal. Prevented with `aws:SourceArn`/`aws:SourceAccount` conditions on service roles.
226. **Permission boundary vs SCP?** A **permission boundary** caps what an IAM principal *can be granted* (delegation within an account); an **SCP** caps what anyone in an account/OU can do (org-level deny, even for root). Neither grants permissions.
227. **How do you revoke already-issued AWS STS sessions?** Attach a deny policy conditioned on `aws:TokenIssueTime` before now — otherwise sessions stay valid up to 12 hours.
228. **IRSA vs EKS Pod Identity?** Both give pods IAM roles. IRSA uses an OIDC provider with per-role trust policies naming the SA subject; Pod Identity uses the EKS Auth API, needs no OIDC provider, works across clusters, and supports session tags.
229. **What is Azure's resource hierarchy?** Tenant → Management Groups → **Subscriptions** (billing/quota boundary) → **Resource Groups** (lifecycle boundary) → Resources. Put resources with the same lifecycle in the same RG.
230. **What can Azure Policy do that AWS Config can't?** Effects including `Modify` (mutate a resource to compliance) and `DeployIfNotExists` (provision a companion resource) — in-band admission control, not just detection and remediation.
231. **What is a Managed Identity?** Azure's workload identity — no secrets, tokens from IMDS for Entra ID. System-assigned (per-resource lifecycle) or user-assigned (shareable).
232. **What is GCP's project?** The unit of everything: billing, API enablement, quotas, IAM and resources. Closer to an AWS account than to a resource group.
233. **What are VPC Service Controls?** A GCP perimeter that blocks access from outside **even with valid credentials** — the strongest data-exfiltration control of the three clouds.
234. **Why is GCP's VPC different?** It's **global** with regional subnets, and external load balancing is **global anycast** — one IP, multi-region backends, no per-AZ LB nodes.
235. **Cosmos DB's five consistency levels?** Strong, Bounded Staleness, **Session (the default)**, Consistent Prefix, Eventual — selectable per request. Strong forfeits multi-master, so consistency and multi-region writes are coupled.
236. **What is Terraform state and why is it sensitive?** The mapping from config to real resource IDs and attributes — and it contains **plaintext secrets**. So: remote, encrypted (OpenTofu does it client-side), versioned, locked, and with the tightest IAM in the org.
237. **What is the most dangerous thing in a Terraform plan?** `-/+ destroy and then create replacement` — a `ForceNew` attribute change. Scan for it before anything else.
238. **`count` vs `for_each`?** `for_each` uses stable keys; `count` uses indexes, so **removing an item from the middle destroys and recreates everything after it**. `for_each` needs keys known at plan time.
239. **Why pin provider versions and commit the lock file?** An unpinned provider can break your plan on a major release with no code change; `.terraform.lock.hcl` with multi-platform hashes stops macOS devs and Linux CI disagreeing.
240. **What is `prevent_destroy` and why isn't it enough?** A plan-time guardrail on stateful resources. It lives in the same file as the destroy, so a determined change removes both. The control that holds is an **SCP/IAM deny on the destructive API call**.
241. **What is Terraform drift and how do you handle it?** Reality differing from config. Detect on a schedule with `plan -detailed-exitcode`; then **codify** intentional changes and **revert** unintentional ones. Prevent with console write-deny and a fast IaC path.
242. **Why not use `terraform workspace` for environments?** Environments differ in resource *shape*, not just variable values — workspaces force `count = var.env == "prod" ? 3 : 1` everywhere. Use directories with shared modules.
243. **How do you handle secrets in Terraform?** Manage the **container and the permissions**, not the value: create the secret in Secrets Manager/Key Vault, grant the consumer a scoped role, and resolve at runtime. Or Vault dynamic secrets — the best secret is one that doesn't exist.
244. **Why is a slow Terraform plan an architecture problem?** It means the state is too big: every plan refreshes every resource. Splitting by lifecycle/blast-radius/ownership fixes speed *and* locking, blast radius and secret exposure.
245. **STRIDE?** Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege — applied to each element and each **trust-boundary crossing** in a data-flow diagram.
246. **OWASP Top 10's #1?** Broken Access Control — IDOR, missing function-level auth, path traversal, unverified JWTs. Prevention: deny by default, authorise server-side on every request, test authorisation as thoroughly as functionality.
247. **What is SSRF and why is it a cloud problem?** The server fetches an attacker-supplied URL, reaching internal services or the **metadata endpoint** → credential theft. Fix: allowlist destinations, block private/link-local ranges, IMDSv2 with hop limit 1, egress filtering.
248. **What is envelope encryption?** A data key encrypts the data; a KMS/HSM key encrypts the data key. HSM-grade root protection without sending all your data through the HSM, plus a smaller blast radius per key.
249. **What is the secrets hierarchy?** Hardcoded → env → Kubernetes Secret → cloud secret manager → External Secrets/SOPS → **dynamic short-lived credentials** → **no secret at all** (workload identity, mTLS). Every step down reduces blast radius.
250. **What is zero trust, operationally?** Never trust network position; verify every request with identity + device + context; least privilege with short-lived scoped credentials; micro-segment; assume breach and detect continuously. The order of work: kill static creds → phishing-resistant MFA → workload mTLS → segmentation → device posture.
251. **How do you actually prioritise vulnerabilities?** Exploited in the wild (KEV/EPSS) → reachable (VEX) → exposure (internet-facing?) → impact (what does the asset hold?) → compensating controls → **CVSS last**.
252. **What is defence in depth?** Layered independent controls so no single failure is a compromise: identity, network segmentation, workload hardening, runtime detection, immutable audit logs, and org-level policy denies.
253. **What should you do first when a credential leaks?** **Deactivate (don't delete), revoke active sessions, and assume the attacker had the maximum the policy allowed** — then hunt for persistence (new users/roles/keys, mining instances, externally-shared snapshots) before cleaning up. Rotate everything in scope.
254. **Why is a GitOps config repo a security target?** Write access to it *is* production access — and it often has weaker controls than the code repo. CODEOWNERS, branch protection, required reviews, signed commits, and audit.
255. **What is the shared responsibility model?** The provider secures the cloud *of* (physical, hypervisor, managed-service internals); you secure the cloud *in* (your config, identity, data, code). Nearly every cloud breach is a customer-side misconfiguration.

---

## 🔥 Architecture & Design

256. **CAP theorem?** In a network partition you must choose consistency or availability. **PACELC** is more useful: else (no partition) you still trade **latency vs consistency**.
257. **What is eventual consistency?** Replicas converge without coordination, so a read may return stale data. Fine for feeds and metrics; unacceptable for balances and inventory.
258. **What is idempotency and why is it mandatory?** An operation applied twice has the same effect as once. Required because retries, at-least-once queues, and failovers all duplicate work. Implement with an idempotency key and a dedupe store.
259. **Why is exactly-once delivery impossible?** A producer can't know whether its message was received before it crashed, so it must retry — the receiver may process twice. What you can build is exactly-once **processing** via deduplication.
260. **What is the outbox pattern?** Write business data and an event in the **same local transaction**, then a relay publishes the event. Solves the dual-write problem (database + broker can't be one transaction).
261. **What is a saga?** A long-running transaction as a sequence of local transactions, each with a **compensating action** run in reverse on failure. Orchestration (a coordinator) or choreography (events).
262. **What happens when a compensation fails?** You need a reconciliation job and a human queue. **This is the part most candidates skip** — sagas don't roll back cleanly in reality.
263. **What is CDC?** Change Data Capture — streaming a database's write log (Debezium + Kafka) to keep other systems in sync. Better than dual-write and better than polling.
264. **Consistent hashing?** Hash keys onto a ring with virtual nodes so adding/removing a node moves only ~1/N of the keys. Used for sharding, cache routing, and load balancing.
265. **What is a hot shard and how do you fix it?** One partition receiving disproportionate traffic (a celebrity key, a timestamp-based key). Fix: better key design, write sharding with a suffix, caching, or per-key rate limiting.
266. **Cache-aside vs write-through vs write-behind?** **Cache-aside**: the app reads/writes the cache explicitly (most common, most failure modes). **Write-through**: writes go to cache and store together. **Write-behind**: writes go to cache and are flushed later (fast, lossy).
267. **What is a cache stampede and how do you stop it?** Many clients miss simultaneously and all hit the origin. Fixes: **singleflight** (coalesce concurrent loads for the same key), jittered TTLs, stale-while-revalidate, and pre-warming.
268. **What is cache penetration vs avalanche?** **Penetration**: queries for keys that don't exist bypass the cache every time (fix: negative caching, bloom filters). **Avalanche**: many keys expire at once (fix: TTL jitter).
269. **Write-around vs write-back?** Write-around goes to the store, bypassing the cache (good for one-time-read data); write-back goes to the cache first (fast, risks loss).
270. **What is CQRS?** Separate write and read models — a normalised write side preserving invariants, and denormalised read models optimised per query, synced via events. Powerful and a lot of machinery; don't reach for it by default.
271. **What is event sourcing?** Storing state as an append-only sequence of events, with projections derived from them. Great auditability and replay; hard to query, hard to change event schemas, and snapshots are mandatory.
272. **Queue vs stream?** A **queue** is work to be consumed once (SQS: visibility timeout, DLQ, retention). A **stream** is a replayable log with multiple independent consumer groups (Kafka/Kinesis: partitions, offsets, replay).
273. **What determines Kafka's ordering guarantee?** Ordering is guaranteed **within a partition**, so your partition key defines the ordering scope. More partitions = more parallelism but different key distribution semantics (and you can't reduce partitions cleanly).
274. **What is a DLQ and what do you do with it?** Where messages go after max retries. Alert on depth > 0, keep original metadata, provide a replay tool, and treat every entry as a bug report.
275. **What is a visibility timeout?** How long a consumer has to process and delete a message before it becomes visible again. **It must exceed the max processing time**, or you get duplicate concurrent processing — better still, extend the lease with a heartbeat.
276. **Rate limiting algorithms?** **Token bucket** (bursts allowed, smooth average), **leaky bucket** (strictly smooth, adds latency), **fixed window** (cheap, boundary spike), **sliding window log** (exact, memory per request), **sliding window counter** (cheap, approximate — the practical default).
277. **Where should rate limiting live?** At the edge (protects everything), per-service (protects the dependency), and per-tenant (fairness). Key on identity, not IP — NAT means thousands of users share one IP.
278. **Fail open or fail closed on a rate limiter?** A per-rule decision: fail open for availability-critical paths, fail closed for abuse-critical ones. Either way, **alert** when the limiter is degraded.
279. **What is backpressure in a stream pipeline?** Consumers signalling they can't keep up so producers slow down, rather than buffers growing until something OOMs. In Kafka it's lag; in reactive systems it's explicit.
280. **What is a bulkhead?** Isolating resources (thread pools, connection pools, tenants, cells) so one slow dependency or noisy tenant can't consume everything.
281. **What is cell-based architecture?** Sharding the system into independent "cells" each serving N tenants, so a failure affects one cell. Bounds blast radius at the cost of routing complexity.
282. **What is graceful degradation?** Serving a reduced but useful response when a dependency fails: cached/stale data, defaults, hidden features. Requires knowing which dependencies are optional — **decide before the incident**.
283. **What is the retry-at-one-layer rule?** Retrying at every layer multiplies: 3 layers × 3 retries = 27 attempts. Pick one layer (usually the outermost or the client) and make the others non-retrying.
284. **What is deadline propagation?** Passing the remaining time budget downstream so a callee doesn't do work the caller has already abandoned. Without it, cancelled requests keep burning resources.
285. **Latency numbers everyone should know?** L1 cache ~1ns, branch mispredict ~5ns, L2 ~7ns, mutex lock/unlock ~25ns, 1KB from memory ~100ns, 1Gbps NIC round trip ~500ns–2µs, SSD random read ~50–150µs, disk seek ~1–10ms, read 1MB sequentially from disk ~20–40ms, **intra-datacenter round trip ~0.5ms, cross-region ~30–100ms, cross-continent ~150–300ms**.
286. **Why does "one more network hop" matter?** At 0.5ms intra-DC and 100ms cross-region, a chatty design's latency is dominated by round trips, not compute. **Round trips are the unit of distributed-systems cost.**
287. **What is the two-generals / consensus problem?** You can't guarantee agreement over an unreliable channel. Paxos/Raft solve consensus for a *quorum* of a known membership, which is why they need an odd number of nodes and a majority.
288. **What is Raft in one sentence?** A consensus algorithm where a leader replicates a log to a majority of followers, with terms and elections guaranteeing safety — used by etcd, Consul, CockroachDB, TiKV.
289. **What is a split brain and how do you prevent it?** Two partitions each believing they're the primary. Prevented by quorum (a minority partition can't elect a leader) and **fencing tokens** (a monotonically increasing number the storage rejects if stale).
290. **What is a fencing token?** A monotonic counter issued with a lease; the resource rejects writes with an older token. Without it, a paused leader whose lease expired can corrupt data on resume.
291. **SQL vs NoSQL default?** Postgres until a measured requirement says otherwise — it does relational, JSON, geo, time-series, vectors and queues well enough that you avoid operating four extra systems.
292. **B+tree vs LSM?** B+trees do in-place writes with predictable reads (Postgres, MySQL); LSM-trees turn random writes into sequential ones via memtable → SSTables, paying with read amplification and **compaction** (Cassandra, RocksDB, DynamoDB).
293. **What is a clustered index?** The primary key index whose leaves contain the actual rows, so the PK determines physical order. In MySQL every secondary index stores the PK — **which is why a wide PK bloats everything**.
294. **What is table bloat in Postgres?** MVCC keeps old row versions in the heap until **autovacuum** reclaims them. **Long-running transactions hold back the xmin horizon and prevent vacuum**, causing progressive slowdown.
295. **Keyset pagination?** `WHERE (created_at, id) < ($1, $2) ORDER BY created_at DESC, id DESC LIMIT 20` instead of `OFFSET 100000`, which scans and discards 100k rows. The fix for deep pagination.
296. **What is an N+1 query?** One query for the list plus one per item. The #1 ORM performance bug; fix with a join, batched `IN`, eager loading, or a dataloader.
297. **Why do connection pools matter?** Each Postgres connection is a process (~5–10 MB); 50 pods × 20 connections kills a database with `max_connections=100`. Use PgBouncer/RDS Proxy in transaction mode — and know it breaks prepared statements and session state.
298. **Why are smaller connection pools faster?** Beyond ~2–4× cores, extra connections add context switching, lock contention and cache thrashing rather than throughput. Scale by making queries faster, not by adding connections.
299. **What is `EXPLAIN (ANALYZE, BUFFERS)` for?** ANALYZE executes and gives real timings/rows; BUFFERS shows cache hits vs disk reads. **Comparing estimated vs actual rows finds stale statistics**, the most common cause of a suddenly-bad plan.
300. **What is the DDL locking trap?** `ALTER TABLE` needs `ACCESS EXCLUSIVE`, which conflicts with plain SELECTs — so it queues behind a long read and blocks everything behind it. **Always `SET lock_timeout` and retry.**
301. **Expand–contract migration?** Add the new column (nullable/defaulted, `CREATE INDEX CONCURRENTLY`) → dual-write → backfill in batches → switch reads → later release drops the old. Keeps old and new code working simultaneously, so rollback is safe.
302. **What is a distributed-SQL database?** Sharded SQL with distributed ACID transactions and automatic rebalancing — Spanner (TrueTime, external consistency), CockroachDB and YugabyteDB (HLC, serializable). Cross-region strong writes pay a consensus round trip, so **place the leader near the writers**.
303. **What is TrueTime?** Google's bounded-uncertainty clock (GPS + atomic) that lets Spanner **commit-wait** through the uncertainty interval, giving globally consistent transaction ordering with real time.
304. **What is Cassandra's tombstone problem?** Deletes leave markers that must be read and filtered until compaction clears them, so a mass delete makes queries dramatically slower. The Cassandra shibboleth.
305. **What is a CRDT and when is it wrong?** A data structure that converges under concurrent updates without coordination (G-Counter, PN-Counter, LWW-Register). Wrong for inventory: it converges, but it doesn't prevent going below zero.
306. **What is the global counter answer?** Single-writer region or quorum consensus for correctness; **shard + sum** for throughput; **regional stock allocation** for inventory; CRDTs only where convergence beats linearisability. Always an atomic conditional update or CAS.
307. **What is 12-factor, briefly?** Codebase, dependencies, config in the environment, backing services as attached resources, strict build/release/run separation, stateless processes, port binding, concurrency via processes, fast graceful startup/shutdown, dev/prod parity, logs to stdout, and admin tasks as code. **The parts that matter for infra: config, statelessness, graceful shutdown, logs to stdout, and dev/prod parity.**

---

## 🔥 The meta-questions

308. **What's your greatest strength?** Pick one, tie it to the role, and give evidence: "I'm good at making unreliable systems boring — I took a team's on-call from 40 pages a week to 8 by deleting non-actionable alerts and fixing the top three causes, and the same approach is why I care about guardrails over documentation."
309. **What's your greatest weakness?** A real one, with the mechanism and the mitigation: "I under-delegate because doing it myself is faster — which capped my last project. I now write the runbook and hand it over with pairing, and I track whether I'm the only person who can do a thing."
310. **Where do you see yourself in 3–5 years?** Scope, not title: owning reliability/platform strategy for an org, growing people, accountable for outcomes rather than writing most of the code. Tie it to *this* role.
311. **Why do you want to leave?** Toward, not away: what you've built is in steady state, and you're looking for a specific challenge this role has. Never badmouth.
312. **Why this company?** Something specific you researched — a blog post, an architecture decision, a product, a scale problem. This is the cheapest way to stand out and almost nobody does it.
313. **How do you handle pressure?** Separate scope, quality and time; make the trade-off explicit rather than absorbing it; keep the non-negotiables (security, data integrity, rollback, observability); write down what you deferred with a date; and don't rely on sustained overtime.
314. **How do you prioritise?** Reversibility and blast radius → who's blocked → value/effort last. Then **make the trade-off visible** so it becomes a shared decision rather than a private one.
315. **How do you handle conflict?** Seek to understand first; bring evidence, not seniority; concede the part they're right about; aim for a decision the team can execute. **Most technical disagreements are unshared context or an unmet requirement.**
316. **How do you deal with an unclear requirement?** Write down your interpretation and the options with trade-offs, then get a decision from whoever owns the outcome. Ambiguity resolved in writing beats ambiguity resolved in code.
317. **What's a technical decision you regret?** A real one, with the reasoning at the time, what you'd do now, and the mechanism you've since added so it can't recur.
318. **How do you keep current?** Name a specific, credible habit: reading release notes and post-mortems (public incident write-ups are the best learning material), a home lab, contributing to an OSS project, and rebuilding something you use. **Then give an example of something you recently changed your mind about** — that's the real answer.
319. **What do you look for in a team?** Blameless post-mortems that produce completed action items, on-call that isn't brutal, deploy frequency, and whether the platform/tooling investment is funded. **These are the observable signs of an engineering org that learns.**
320. **Do you have questions for us?** Always yes. See [`21-Questions-To-Ask-Them`](../21-Questions-To-Ask-Them/README.md).

---

## Red flags

| Saying this | Costs you |
|---|---|
| Anything you can't back with an example | Recited, not known |
| "We" for every accomplishment | They're hiring you |
| Certainty with no trade-off named | Junior signal |
| "It depends" with no criteria | Useless — always say what it depends **on** |
| A one-word answer to a one-line question | Missed the chance to show depth |
| Guessing a fact rather than saying "I'd check X" | Wrong confidently is worse than honest |
| Tool names without the mechanism they implement | Cargo-cult knowledge |
| Never mentioning cost, team size, or maintenance | Not production-shaped thinking |

## How to use this file

1. **Two passes, out loud.** Read a section, cover the answers, recite. Speaking is a different skill from recognising.
2. **Expand the ones you'll actually be asked.** For your target role, pick 30 of these and add: a concrete example from your experience, and one trade-off.
3. **Turn the ones you stumble on into flashcards** and drill them the morning of.
4. **Don't memorise sentences.** Memorise the *shape*: mechanism → why it matters → the trade-off → an example. Interviewers forgive imprecise wording and never forgive a missing trade-off.

→ Next: [`21-Questions-To-Ask-Them`](../21-Questions-To-Ask-Them/README.md)
