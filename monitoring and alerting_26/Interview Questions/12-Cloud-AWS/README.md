# 12 · Cloud — AWS (deep)

The default cloud for interviews. Depth here matters more than breadth across clouds; [`13-Cloud-Multi-Azure-GCP`](../13-Cloud-Multi-Azure-GCP/README.md) covers the comparison and the other two.

---

## 🟢 Compute

### 1. EC2 — instance families, purchasing, and the choices that matter
**Families:** `m` (general), `c` (compute-optimised), `r`/`x`/`z` (memory-optimised, `z` = highest per-core), `i`/`d`/`im` (storage/NVMe), `g`/`p`/`trn`/`inf` (accelerated: GPU/ML/inference), `t` (burstable), `mac`, `u` (bare metal-ish high memory), `a`/`graviton` variants (Arm).

**Burstable (`t`) — the mechanism everyone misuses:** a `t` instance earns **CPU credits** when below its baseline and spends them when above. When credits run out, **performance is capped at the baseline** (e.g. 20% of a vCPU on `t3.micro`). `unlimited` mode lets it burst beyond credits **at an extra per-CPU-hour charge**. **A production service on `t3.small` in `standard` mode will mysteriously slow down after a busy morning** — that's credit exhaustion, and it's a real incident pattern. Use `t` for dev/test and low-utilisation workloads; use `m`/`c` for steady production.

**Arm/Graviton:** typically 20–40% better price-performance for JVM, Go, Node, Python and containerised workloads. **The migration blocker is architecture-specific binaries** — multi-arch container images (buildx), native deps, and any closed-source binary. **Worth naming as a default cost lever**, plus the caveat that you must test, not assume.

**Purchasing models:**
| Model | Discount | Commitment | Notes |
|---|---|---|---|
| **On-demand** | — | None | Baseline; also **Capacity Blocks** for GPU reservations |
| **Savings Plans — Compute** | Up to ~66% | $/hour for 1 or 3 years | **Most flexible**: applies across instance families, sizes, regions, OS, and **Fargate/Lambda**. The default recommendation |
| **Savings Plans — EC2 Instance** | Up to ~72% | $/hour in a specific region + family | Less flexible (locked to family/region), no size flexibility beyond the family |
| **Savings Plans — SageMaker** | Varies | $/hour | |
| **Reserved Instances (legacy)** | Up to ~72% | Instance-based | Still exists for RDS/Redshift/ElastiCache/DynamoDB/OpenSearch; EC2 RIs are effectively replaced by SPs |
| **Spot** | Up to ~90% | None — **can be reclaimed with 2 minutes' notice** | Stateless, fault-tolerant, interruptible work; use **capacity-rebalanced** recommendations, diversified instance pools, and checkpointing |

**Spot in practice (a frequent deep-dive):** interruption notice via the **instance metadata service (IMDS)** and **EventBridge**; ~2 minutes to drain. Design: multiple instance types + multiple AZs (diversification), ASG with mixed instances policy (`OnDemandBaseCapacity`, `OnDemandPercentageAboveBaseCapacity`, `SpotAllocationStrategy: capacity-optimized` or `price-capacity-optimized`), **Capacity Rebalancing signal** (fires *before* the interruption notice), graceful draining (deregister from the LB, finish in-flight work, checkpoint), and **never** run stateful or long-transaction workloads on Spot without checkpointing. Karpenter handles this well automatically.

**IMDS — the security-critical detail:** the metadata service at `169.254.169.254` serves instance identity and **temporary role credentials**. **IMDSv1** is a plain `GET` → an SSRF vulnerability in your app becomes full credential theft (the Capital One breach). **IMDSv2** requires a `PUT` to get a session token with a hop limit → blocks most SSRF and container-escape paths. **Enforce IMDSv2-only (`HttpTokens: required`) and set `HttpPutResponseHopLimit: 1`** so containers can't reach it. Also: don't put secrets in user data (visible in the console/API to anyone with `ec2:DescribeInstanceAttribute`).

### 2. Auto Scaling Groups — the settings that decide whether it works
```
Launch Template (AMI, instance type, IAM role, user data, security groups, EBS, IMDS config)
   └─► ASG: min / desired / max, VPC + subnets (multi-AZ!), health check type + grace period,
              mixed instances policy (On-Demand + Spot), scaling policies, cooldowns,
              instance refresh (rolling replacement), lifecycle hooks, termination policies
```
**Health checks:** `EC2` (instance status) vs `ELB` (load balancer health check — **the one you want for a web fleet**, since a running instance serving 500s is not healthy). `HealthCheckGracePeriod` must exceed your app's startup time or new instances get terminated during boot → a scaling death loop.

**Scaling policies:**
| Type | Signal | Notes |
|---|---|---|
| **Target tracking** | Keep a metric at a target (e.g. avg CPU 50%) | Simplest and usually best; scales out and in automatically |
| **Step scaling** | Different increments per alarm breach magnitude | More control, more config |
| **Simple scaling** | One increment per alarm | **Legacy — has a cooldown problem** (waits for the cooldown after each action, so it reacts slowly to a fast spike) |
| **Predictive scaling** | ML on historical seasonality | Pre-scales ahead of known peaks |
| **Scheduled** | Cron | Known events (Black Friday, Monday 9am) |

**The details that break people:**
- **Cooldown periods**: after a scale-out, ASG waits (default 300s) before scaling again — prevents thrashing but slows reaction. **With target tracking you generally don't need manual cooldowns** (the policy handles it); the metric itself must be a good load proxy (CPU is often not — see below).
- **Scaling on the wrong metric**: CPU is a poor signal for I/O-bound services. Use ALB `RequestCountPerTarget`, a custom CloudWatch metric, or queue depth. **Scaling on CPU while latency explodes is a classic.**
- **Instance warm-up time** for custom metrics: new instances report low utilisation during boot, which can trigger an immediate scale-in. Set `--instance-warmup-time`.
- **Scale-in protection** and **termination policies** (`OldestLaunchTemplate`, `AllocationStrategy`, `OldestInstance`…) matter when you have stateful or uneven instances.
- **The ASG doesn't scale the database.** Compute is elastic; state isn't. Most "autoscaling failure" stories are actually database bottlenecks.
- **Lifecycle hooks** let you run actions on launch/terminate (install config, drain connections, deregister from service discovery) with a heartbeat — essential for graceful scale-in.
- **Instance Refresh** = managed rolling replacement when the launch template changes (health-checked, with rollback). The right way to roll an AMI change.

### 3. Lambda — the model, the limits, and when not to use it
**Model:** event-driven functions, per-invocation billing (per GB-second, 1 ms granularity, rounded up), 128 MB–10 GB memory (**CPU scales proportionally with memory** — you often increase memory to get CPU, not because you need the RAM), configurable timeout up to **15 minutes**, ephemeral `/tmp` (512 MB–10 GB), up to 10 GB container images.

**Concurrency model — the part interviews probe:**
- **Reserved concurrency** (per function) — guarantees capacity, but **also caps it**, and can starve the account.
- **Provisioned concurrency** — pre-initialised execution environments → **eliminates cold starts**, costs money whether used or not.
- **Account concurrency limit** (default ~1,000 concurrent executions per region, soft limit) — **a burst can exhaust the whole region's Lambda capacity for every function**. Reserve/cap noisy functions.
- **Cold starts**: init phase (download code, start runtime, run global initialisation) + invoke. Worse for large deployment packages, JVM/.NET runtimes, provisioned VPC networking (**Hyperplane ENI creation** — largely fixed, but VPC Lambdas still init slower), and after a scaling spike. **Mitigate:** smaller packages, avoid heavy global initialisation, keep dependencies lazy, use provisioned concurrency for latency-sensitive paths, prefer interpreted/native runtimes (or SnapStart for Java, which snapshots the initialised runtime).
- **Async vs sync invocation**: sync (API Gateway, ALB, Lambda URL) → the caller waits, retries are the caller's problem; **async (S3, SNS, EventBridge, SQS-via-trigger)** → Lambda retries twice, then sends to a **DLQ / on-failure destination**. **Unhandled async failures silently disappear if you don't configure a destination** — a very common production gap.
- **Event source mappings** (SQS, Kinesis, DynamoDB Streams): Lambda *polls*, batching and scaling with the queue. Config: `BatchSize`, `MaximumBatchingWindowInSeconds`, `MaximumConcurrency` (per event source — prevents one function from saturating a stream), retry/`MaximumRetryAttempts`, `BisectBatchOnFunctionError` (split a failing batch to isolate the poison record), DLQ.

**When Lambda is the wrong answer:** workloads > 15 min, sustained high-throughput compute (cost per hour beats Lambda above ~a certain utilisation — model it), latency-critical with no provisioned concurrency, heavy local state, or anything with a large always-on footprint. **Also: distributed monolith risk** — splitting a service into 40 functions creates 40 network hops, 40 cold starts, and a debugging nightmare. **"Serverless" is an architecture style, not just a billing model.**

**Lambda + VPC**: the function gets a **Hyperplane ENI** in your subnets (fast now, but consumes IP addresses — **a Lambda scaling to 1,000 concurrent in a /24 will exhaust the subnet**; plan IP capacity and use multiple subnets/AZs).

### 4. ECS vs EKS vs Lambda vs App Runner — how to choose
| | **Lambda** | **ECS (Fargate/EC2)** | **EKS** | **App Runner** |
|---|---|---|---|---|
| Model | Function, event-driven | Container service | Container orchestration platform | PaaS for containers |
| Ops burden | None | Low | **High** (control plane is managed; everything else is yours) | None |
| Startup | Cold start (ms–s) | Seconds | Seconds (+image pull) | Seconds |
| Max duration | 15 min | Unlimited | Unlimited | Unlimited |
| Scaling | Per-request, very fast, to zero | ASG/service autoscaling, minutes | HPA/KEDA/Cluster Autoscaler/Karpenter | Automatic |
| Cost model | Per invocation — **cheap at low/spiky volume, expensive at steady high volume** | Per vCPU/GB-second | Same + control plane $/hr + node overhead | Per vCPU/GB-second |
| Best for | Events, glue, spiky/stateless APIs, cron, stream processing | Long-running services, teams that want containers without K8s | Large fleets, multi-team platforms, complex scheduling, operators, service mesh | Simple web services/APIs, minimal config |
| Networking | VPC via Hyperplane ENI; NAT/endpoint considerations | awsvpc/host/bridge modes; Service Connect | CNI, CNI, NetworkPolicy, Ingress/Gateway API | VPC connector |
| Multi-tenancy/governance | Weak | Moderate (namespaces via IAM/tags) | **Strong** (namespaces, RBAC, quotas, policies) | Weak |

**The decision framing that scores:** "I choose by **operational capacity first, workload shape second**. If the team is 4 engineers and the workload is 6 services, ECS Fargate is almost certainly right — EKS is a platform you must staff. If you have 60 services, 15 teams, need per-team isolation, operators, and progressive delivery, EKS earns its complexity. Lambda for event-driven glue and genuinely spiky work where scale-to-zero pays. **The most common mistake I see is adopting Kubernetes because it's the industry default, then spending 40% of engineering time on the platform.**"

---

## 🟢 Networking

### 5. VPC — subnets, routing, and the pieces people get wrong
```
VPC (CIDR, e.g. 10.0.0.0/16)
 ├─ Public subnet   (route table: 0.0.0.0/0 → Internet Gateway)   ← ALB, NAT GW, bastion
 ├─ Private subnet  (route table: 0.0.0.0/0 → NAT GW / Transit GW) ← app tiers, no public IP
 ├─ Isolated subnet (no default route at all)                       ← databases
 ├─ Route tables (one per subnet class; main RT is a foot-gun)
 ├─ Internet Gateway (IGW)          — public ingress/egress
 ├─ NAT Gateway                     — private → internet egress (per-AZ, HA, ~$0.045/hr + $0.045/GB)
 ├─ VPC Endpoints (Gateway: S3/DynamoDB, free; Interface: PrivateLink, per-hour + per-GB)
 ├─ Transit Gateway / VPC Peering   — inter-VPC
 ├─ Security Groups (stateful, allow-only, per-ENI)
 └─ NACLs (stateless, allow+deny, per-subnet, evaluated in rule-number order)
```
**What actually differentiates a good answer:**
- **Public vs private is defined by the route table, not by the subnet name.** A subnet with a route to an IGW and instances with public IPs is public. A "public" subnet with no IGW route is just a mislabelled private subnet.
- **NAT Gateway is per-AZ and costs real money** (~$0.045/hr each + $0.045/GB). One NAT for the whole VPC = a cross-AZ dependency + a single point of failure + cross-AZ data charges. **One per AZ** is the standard, and it also keeps traffic local. **A NAT Gateway outage or a mis-set route table = every private subnet loses internet egress**, which breaks package installs, API calls, cert validation and image pulls — a common incident.
- **NAT Gateway supports ~55,000 concurrent connections per source IP:port:destination tuple** — a real limit for high-fanout workloads (crawlers, high-concurrency outbound). Mitigate with more private IPs per NAT (up to 32 secondary IPs) or reduce connection churn.
- **VPC Endpoints (PrivateLink) are both a security and a cost win**: S3/DynamoDB **gateway endpoints are free** and keep traffic off the internet path; **interface endpoints** (~$0.01/hr per AZ + $0.01/GB) avoid NAT charges for AWS APIs. **If your private subnets call S3 through a NAT Gateway, you're paying twice and adding latency** — this is one of the most common AWS cost findings.
- **IP exhaustion**: /24 subnets give ~251 usable IPs; Lambda ENIs, EKS pods (VPC CNI), and NAT/Fargate consume many. **Plan the CIDR up front** — you cannot resize a VPC or subnet in place. EKS with VPC CNI is the notorious consumer (each pod takes a VPC IP).
- **Security Groups vs NACLs**: SGs are **stateful** (return traffic allowed automatically), **allow-only**, attached to ENIs, and can **reference other SGs** (the single best practice — `source_security_group_id` instead of CIDRs). NACLs are **stateless** (need explicit ephemeral-port rules — the classic "it works with SG but not NACL" bug), support **deny**, are per-subnet, and evaluated by rule number. **Use SGs for nearly everything; NACLs only for broad subnet-level denies.**
- **DNS**: `enableDnsSupport` + `enableDnsHostnames` must both be on for private hosted zones and instance DNS names to work. The VPC resolver is at `<VPC CIDR base + 2>` (e.g. `10.0.0.2`). **Route 53 Resolver endpoints** for hybrid DNS forwarding.
- **Reachability Analyzer / Network Access Analyzer** for verifying paths and finding unintended public reachability.

### 6. Load balancing — ALB vs NLB vs GLB vs CLB
| | **ALB** (L7) | **NLB** (L4) | **GLB** (L3) | **CLB** (legacy) |
|---|---|---|---|---|
| Layer | HTTP/HTTPS/gRPC/QUIC | TCP/UDP/TLS | Geneve encapsulation | L4/L7, deprecated |
| Routing | Host/path/header/method/query-based, weighted target groups, redirects, rewrites | Flow-based (5-tuple hash) | Transparent appliance insertion | Basic |
| Performance | Very high, scales automatically | **Ultra-high (tens of millions of rps), static IP / Elastic IP, sub-ms latency** | High | Lower |
| TLS | Terminates; ACM certs; mTLS (now supported); TLS policies | Terminates TCP/TLS or passthrough | Passthrough | Yes |
| Client IP | `X-Forwarded-For` | **Preserved natively** | Preserved | Depends |
| Sticky sessions | Cookie-based | Source IP | — | Cookie |
| Health checks | HTTP-aware (path, status code matcher) | TCP/HTTP | — | Basic |
| Websockets/gRPC | ✅ | ✅ (TCP) | — | Partial |
| Use for | Web/API/microservices, ingress | Non-HTTP, ultra-low latency, static IP requirement, PrivateLink service front | Third-party appliances (firewalls, IDS) in the traffic path | Never for new work |

**The details that matter:**
- **NLB has a static IP / Elastic IP per subnet** — required when a client allowlists your IP. ALB doesn't (DNS names only, IPs change). **This is the usual reason to pick NLB over ALB for a public endpoint.**
- **ALB target types**: `instance` (routes to the instance IP, works with any port), **`ip`** (routes to arbitrary IPs — **this is how you target Fargate tasks and EKS pods directly**, bypassing NodePort and getting better performance and correct client IPs), `lambda`, `alb` (chaining).
- **Cross-zone load balancing**: **ALB has it on by default; NLB has it OFF by default**, meaning each NLB node only sends to targets in its own AZ → **uneven distribution and, worse, cross-AZ charges and failure-domain coupling when you enable it**. Know which you want and why.
- **Connection draining / deregistration delay** (default 300s) — combined with a 30s pod grace period, this mismatch is a source of 502s during deploys (see [`07-Kubernetes`](../07-Kubernetes/README.md#13-why-do-we-get-502504s-during-rolling-deploys-the-most-common-senior-question)).
- **Idle timeout** (default 60s) — long-running requests and websockets need it raised, or clients see connection resets at exactly 60s. **A "fails at exactly 60 seconds" symptom is an ALB idle timeout.**
- **Health check at the target group**, and the target must be healthy in the *target group's* AZ.
- **WAF** attaches to ALB/CloudFront/API Gateway (not NLB) — an architectural constraint that surprises people.
- **Slow start** (gradually ramp traffic to new targets) prevents a cold JVM/container from being crushed the moment it passes its health check.

### 7. Route 53 — routing policies and the DNS-failure scenarios
**Policies:** **Simple**, **Weighted** (canary, blue/green), **Latency-based** (route to the region with lowest latency to the user), **Geolocation** (by user geography), **Geoproximity** (by lat/long + bias, requires Traffic Flow), **Failover** (active-passive with health checks), **Multivalue answer** (return up to 8 healthy records, client-side random), **IP-based** (by client CIDR).

**Health checks** can monitor an endpoint, another health check (**calculated/combined**), or a CloudWatch alarm. **This is how you build automated regional failover.**

**DNS failure scenarios worth knowing:**
- **TTL is a lie.** Resolvers cache longer than the TTL, some ignore it entirely, and ISPs have their own policies. **A 300s TTL does not mean failover in 300s.** For critical failover records use 30–60s and *still* plan for minutes.
- **Negative caching**: an NXDOMAIN response is cached for the SOA minimum (often minutes) — so a record that briefly doesn't exist can stay broken.
- **The Route 53 2025 outage lesson**: DNS is a **single logical dependency for everything**. Best practice: **multi-provider DNS** (dual-hosted zones with a failover), monitoring from outside your own stack, and avoiding a dependency on a single resolver path. **Also: your own services should not depend on DNS resolution succeeding during an incident** — cache resolution results, and have IP-based fallbacks for the most critical path.
- **Private hosted zones + split-horizon DNS** for internal names; **Resolver rules/endpoints** for hybrid forwarding; the resolver's own availability is an in-VPC dependency.
- **Alias records** (Route 53-specific, free, always returns healthy targets) vs **CNAME** (costs a query, can't be used at the zone apex). **Zone apex + a load balancer = alias record**, never a CNAME.

---

## 🟢 Storage & Databases

### 8. S3 — storage classes, consistency, security, and the cost levers
**Consistency:** S3 has been **strongly read-after-write consistent for all operations since December 2020** (new objects, overwrites, and deletes are immediately visible). **Knowing that the old "eventual consistency" answer is outdated is a credibility marker** — but also know the nuance: consistency is per-object; **`ListObjects` is strongly consistent too now**, but applications that assume "I wrote it, so a list will show it in the same millisecond across all replicas" can still see surprises with multi-part uploads completing asynchronously.

**Storage classes:**
| Class | Durability | Availability (SLA) | Min size / duration | Retrieval cost | Use |
|---|---|---|---|---|---|
| **Standard** | 11×9s | 99.99% | — | — | Hot, frequent access |
| **Intelligent-Tiering** | 11×9s | 99.9% | — | Monitoring fee $0.0025/1k objects | **Unknown/changing access patterns — the safe default** |
| **Standard-IA** | 11×9s | 99.9% | 128 KB / 30 days | Per-GB retrieval | Infrequent but immediate |
| **One Zone-IA** | 11×9s (one AZ) | 99.5% | 128 KB / 30 days | Per-GB | Reproducible data, non-critical |
| **Glacier Instant Retrieval** | 11×9s | 99.9% | 128 KB / 90 days | Higher per-GB | Archive you might need now |
| **Glacier Flexible Retrieval** | 11×9s | — (async) | 40 days | Expedited/standard/bulk (mins–hours) | Archive |
| **Glacier Deep Archive** | 11×9s | — | 180 days | Bulk (12–48 h) | Compliance, cheapest |
| **Express One Zone** | — | 99.99% (single AZ) | — | — | Sub-millisecond, high-throughput single-AZ (directory bucket) |

**Durability ≠ availability.** 11 nines of durability (never lose an object) with 99.5% availability (One Zone-IA) is a real combination. **Also: durability is about object loss, not about deletion** — a `DeleteObject` from a compromised credential is not a durability failure. Hence **versioning + object lock + MFA delete + restricted delete permissions**.

**Security checklist (this is the #1 AWS interview topic):**
- **Block Public Access** at **account and bucket** level — the four settings (`BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, `RestrictPublicBuckets`). Turn them all on unless there's a documented reason.
- **Bucket policies** (resource-centric, can grant cross-account, can enforce TLS/`aws:SecureTransport`, IP ranges, VPC endpoints, MFA) + **IAM** (identity-centric) — **an explicit deny anywhere wins**.
- **Encryption**: SSE-S3 (default, always on now), **SSE-KMS** (per-key control, CloudTrail logging of key use — **but adds a KMS API call per object, which has cost and quota implications**), **DSSE-KMS** (dual-layer). **SSE-C** (customer-provided keys). TLS in transit enforced via bucket policy `aws:SecureTransport: false` deny.
- **Versioning** + **Object Lock (WORM)** in compliance/governance mode for ransomware and accidental-deletion protection.
- **Access logging / S3 Storage Lens / CloudTrail data events** — know what each gives you (Storage Lens = usage/cost analytics; server access logs = per-request; CloudTrail data events = API calls, and they're expensive at scale so scope them).
- **Presigned URLs** with short expiry for direct upload/download (never make a bucket public to serve one user their file).
- **Access Points** for large-scale access management with per-application policies.
- **Cross-region replication** needs versioning on both sides and doesn't replicate existing objects automatically unless you run a batch replication job.

**Cost levers (very commonly asked):**
1. **Lifecycle policies** transitioning to IA/Glacier and **expiring** old versions/incomplete multipart uploads. **Incomplete multipart uploads are invisible in the console and accrue cost forever** — a lifecycle rule for `AbortIncompleteMultipartUpload` is free money.
2. **Non-current version expiry** — with versioning on, every overwrite keeps the old object and you pay for it. This is a top-3 surprise bill.
3. **Request costs**: PUT/GET/LIST are billed per request. A workload doing 100M small GETs pays more in requests than storage. **Glacier retrieval fees can exceed storage costs** for wrongly-tiered data.
4. **Data transfer**: out to the internet (~$0.09/GB, tiered), **cross-AZ ($0.01/GB each way)**, cross-region. **Use S3 Gateway Endpoints from VPCs — free, and it eliminates NAT Gateway data charges for S3.** This is the single most common cost fix I'd look for.
5. **Storage Lens / Cost Explorer** to attribute by prefix/account, then set per-team budgets.

### 9. EBS vs EFS vs FSx vs instance store
| | **EBS** | **Instance store (NVMe)** | **EFS** | **FSx for NetApp ONTAP / Lustre / Windows** |
|---|---|---|---|---|
| Type | Block, network-attached | Local physical disk | Managed NFS (POSIX file) | Managed NAS/HPC/Windows file |
| Persistence | **Survives instance stop/terminate** (if `DeleteOnTermination=false`) | **Lost on stop/terminate/failure** | Persistent | Persistent |
| Sharing | **One instance at a time** (except **Multi-Attach** on io2 Block Express, and only within an AZ, with a cluster-aware filesystem) | One instance | **Hundreds/thousands of clients, multi-AZ** | Many clients |
| Performance | gp3: 3,000 IOPS/125 MB/s baseline, up to 16k IOPS/1000 MB/s; io2 Block Express: up to 256k IOPS, 4 GB/s, sub-ms | **Highest IOPS/lowest latency** (local NVMe) | Elastic throughput; latency higher than EBS (network file protocol) | Very high (Lustre for HPC/ML) |
| AZ-bound | **Yes** — a volume lives in one AZ; snapshot to move | Yes | **No — regional, multi-AZ** | Depends |
| Use for | Databases, boot volumes, anything stateful per instance | Caches, scratch, buffers, temp/shuffle data, Hadoop/Spark | Shared file storage, content, home dirs, multi-instance apps | Enterprise NAS, HPC/ML training, Windows workloads |

**The traps:**
- **`DeleteOnTermination` defaults to `true` for the root volume** — terminating an instance destroys the data. For anything valuable: `false`, plus snapshots, plus the app shouldn't rely on instance-local state.
- **EBS is AZ-bound.** You cannot attach a volume in `us-east-1a` to an instance in `us-east-1b`. Moving requires snapshot → restore in the target AZ. **This constrains DR design and is a common failover blocker.**
- **gp3 is almost always better than gp2**: gp2's performance scales with volume size (3 IOPS/GB, so a 100 GB gp2 = 300 IOPS), which perversely forces people to provision huge volumes for IOPS. **gp3 decouples capacity from performance** — 3,000 IOPS/125 MB/s at any size, and you can raise IOPS/throughput independently. **Migrating gp2 → gp3 is a routine, in-place, no-downtime cost+performance win.**
- **Snapshots are incremental** (only changed blocks), stored in S3 (but not in your buckets), and **restore lazily** — a restored volume serves data on demand while loading in the background, which means **first-access latency is high unless you use Fast Snapshot Restore (FSR)** or `fio`/`dd` pre-warming. **A database restored from snapshot and immediately put under load can appear broken for hours.** This is an excellent, specific thing to know.
- **io2 Block Express Multi-Attach** requires a cluster filesystem (OCFS2/GFS2) — you can't just attach ext4 to two instances and expect it to work.

### 10. RDS / Aurora — the operational knowledge that matters
**RDS**: managed instances of Postgres, MySQL, MariaDB, Oracle, SQL Server. You get provisioning, patching, backups, failover; **you don't get OS access**, and you're responsible for schema, query performance, indexes and connection management.

**Aurora** (MySQL/PostgreSQL-compatible):
- **Storage is a distributed, 6-way-replicated-across-3-AZs log-structured service** that grows automatically to 128 TB, self-heals, and is decoupled from compute. **Only 4 of 6 copies are needed for writes, 3 of 6 for reads** → tolerates an AZ loss and even 2 disk failures without losing write availability. **That's the architecture to describe.**
- **Aurora Serverless v2**: capacity in ACUs, scales in seconds with load, down to 0 ACUs (with `min_capacity=0`) for true scale-to-zero. Good for spiky/unpredictable workloads.
- **Aurora Global Database**: cross-region replication with typically < 1s lag, and a secondary region that can be promoted (RTO ~1 min, RPO seconds). The answer for regional DR.
- **Aurora Limitless / distributed** for sharding beyond a single writer.

**Multi-AZ deployments:**
| Type | Mechanism | Failover |
|---|---|---|
| **Multi-AZ instance** | Synchronous standby in another AZ | **DNS-based failover**, typically 60–120s; **your app must reconnect** |
| **Multi-AZ DB cluster** (RDS) | Two readable standbys in different AZs | Faster (~35s), standbys serve reads |
| **Aurora** | Shared storage + up to 15 replicas across AZs | Typically 15–30s (or faster with reader endpoints) |

**The operational details that separate experienced candidates:**
- **Failover is a DNS change.** Your app's connection pool holds stale connections → **you must configure a JDBC/pool TTL or connection validation**, or you get errors for minutes after a successful failover. **A "RDS failed over but the app never recovered" incident is almost always connection pooling.** Also: JVM DNS caching (`networkaddress.cache.ttl`) defaults to caching forever in some setups → set it to 30–60s.
- **Connections are the bottleneck.** Postgres has ~100 max_connections by default, each consuming memory. **50 pods × 20 connections = 1,000 → the database is down.** Use **RDS Proxy** (pools and multiplexes, handles failover connection draining) or PgBouncer in transaction mode. **Naming this is a strong signal.**
- **Backups**: automated (retention 1–35 days, transaction-log-based **point-in-time recovery** to any second within the window) + manual snapshots (kept forever until deleted). **Backups are in-region**; **cross-region automated backup replication** or manual snapshot copying for DR. **Test restores.**
- **Read replicas**: async, so **replication lag is normal and unbounded under write load**. Queries that must see their own writes go to the primary. Replicas can be promoted, can be cross-region, and can have their own replicas. **Monitor `ReplicaLag` / `AuroraReplicaLag` and alert** — silent lag breaks read-your-writes and reporting.
- **Storage autoscaling** (RDS) prevents "disk full" outages but also prevents cost surprises from being noticed — set a **maximum storage threshold** and alert on growth.
- **Parameter groups / option groups** are the config mechanism; some changes require a reboot, and **applying a parameter group change to a production instance reboots it** — schedule it.
- **Minor version auto-upgrade** is convenient and occasionally catastrophic (a behaviour change). **Control the upgrade window and test minor upgrades in staging.**
- **Performance Insights** (DB load, top SQL, wait events) is the right diagnostic tool — much better than CloudWatch alone for "why is the DB slow". **Enhanced Monitoring** gives OS-level metrics.
- **IAM database authentication** (short-lived tokens) removes stored passwords for supported engines — worth naming as a security improvement.

### 11. DynamoDB — when it's right and the traps
**Model:** key-value + document, partition key (+ optional sort key), single-digit-ms latency, serverless scaling, **no joins, no ad-hoc queries, no transactions across partitions (except limited TransactWriteItems)**.

**Capacity modes:**
- **On-demand**: pay per request unit, auto-scales instantly. Great for unknown/spiky traffic. **Expensive at sustained high volume.**
- **Provisioned + Auto Scaling**: set RCU/WCU, scale on schedule/target-tracking. **Cheaper for predictable load.**
- **Reserved capacity** for steady baseline.

**The traps (this is what they ask):**
1. **Hot partitions.** Throughput is distributed **per partition key**, and a single partition has a hard throughput ceiling (~3,000 RCU / 1,000 WCU). **A partition key like `status` or `date` or one celebrity user's ID concentrates all traffic on one partition → `ProvisionedThroughputExceededException` even though the table is at 5% utilisation.** Fix: high-cardinality keys, write sharding (`user#1`, `user#2`, … with a random suffix), or composite keys. **Adaptive capacity** helps but doesn't fix a bad key design.
2. **Item size limit 400 KB**; and **LSIs must be created at table creation** (GSIs can be added later).
3. **GSIs are eventually consistent** — you cannot read-your-writes through a GSI. **Designing a workflow that writes then immediately queries a GSI is a classic bug.**
4. **Sparse GSIs**: items without the GSI key don't appear in the index — useful deliberately, surprising accidentally.
5. **Queries need a partition key equality** (`Query`) — anything else is a `Scan` (reads the whole table, expensive and slow). **Secondary access patterns must be designed as GSIs or separate tables.**
6. **Single-table design**: the "put everything in one table with generic `PK`/`SK` prefixes" pattern. **Powerful and genuinely efficient, but it makes the schema invisible, migrations painful, and onboarding hard.** My position: it's the right answer for access-pattern-heavy, high-scale apps with experienced teams; for most teams, a few well-named tables with GSIs are more maintainable. **Being able to argue both sides is the win.**
7. **DAX** (in-memory cache) for read-heavy; **DynamoDB Streams** + Lambda for CDC/event-driven; **TTL** for expiring items (**background, best-effort, can lag hours** — don't rely on it for exact-time deletion, and know that expired-but-not-yet-deleted items can still be returned unless you filter on the TTL attribute).
8. **Global Tables** = multi-region active-active with **last-writer-wins conflict resolution** and no cross-region transactions. Fine for many workloads, dangerous for money movement.
9. **Cost model**: on-demand pricing per million RRU/WRU + storage + GSI storage/writes (each GSI multiplies write cost) + streams + backups. **A table with 4 GSIs costs 5× on writes.** Model it before building.
10. **`TransactWriteItems`** gives 2-phase-commit semantics across up to 100 items (2× cost) — real transactions, but scoped and expensive.

### 12. Caching, queues, streams — picking the right primitive
| Service | Model | Use | Key limits/gotchas |
|---|---|---|---|
| **ElastiCache (Redis/Valkey/Memcached)** | In-memory | Cache, sessions, leaderboards, pub/sub, rate limiting, distributed locks | Redis: persistence (RDB/AOF), replication, failover; **Memcached: no persistence, no replication, multi-threaded, simpler**. **Serverless Redis** now exists. A cache that's treated as a source of truth is an incident |
| **MemoryDB** | Redis-compatible, **Multi-AZ durable** | When you need Redis semantics *and* durability as a primary store | More expensive; real persistence |
| **SQS** | Managed queue, at-least-once | Decoupling, buffering, fan-out, work queues | **Standard** (unlimited throughput, best-effort ordering, ≥1x delivery) vs **FIFO** (exactly-once processing, strict order, 3,000 TPS or 30,000 with batching, needs a dedup ID). **Visibility timeout must exceed processing time** or you get duplicates. **Max retention 14 days.** No push (long-poll instead). **DLQ + redrive policy is mandatory** |
| **SNS** | Pub/sub, fan-out, push | Notifications, fan-out to many SQS queues/Lambda/HTTP/email/SMS | Fire-and-forget (**no retention** — if the subscriber is down, the message is gone unless you fan out to SQS). **SNS→SQS is the standard reliable fan-out pattern.** Message size 256 KB (large payloads → S3 + a pointer) |
| **Kinesis Data Streams** | Real-time stream, shards, replay | High-throughput ingestion, event sourcing, replay, multiple independent consumers | **Shards** = 1 MB/s in, 2 MB/s out each; ordering **per partition key**; retention 24h–365 days; **replayable** (unlike SQS); consumer scaling requires shard scaling or enhanced fan-out; **shard splits don't rebalance existing data** |
| **Kinesis Data Firehose** | Near-real-time delivery to S3/Redshift/OpenSearch | Bulk analytics ingestion | No replay; batching/transform via Lambda |
| **MSK** | Managed Kafka | Kafka-native workloads, exactly-once semantics, KRaft, huge ecosystem | You manage topics, partitions, consumer groups, retention — **it's Kafka, not serverless Kafka**. **MSK Serverless** exists for simpler cases |
| **EventBridge** | Event bus, rules, schemas, archive/replay | Cross-service and cross-account event routing, SaaS integration, scheduled events | Content-based filtering rules; **archive + replay is a genuinely useful feature**; 256 KB payload; schema registry |
| **Step Functions** | State machine orchestration (ASL) | Sagas, workflows, retries, human approval, parallel branches, long-running processes | **Standard** (exactly-once, up to 1 year, per-state-transition cost — expensive at high volume) vs **Express** (at-least-once, 5 min max, per-duration cost — cheap at high volume). **Visualises the whole workflow, which is the actual selling point over hand-rolled orchestration** |

**SQS vs Kinesis vs SNS — the standard question:**
- **SNS** for *notification fan-out* (many subscribers, no persistence).
- **SQS** for *work queues* (one consumer group, persistence, visibility timeout, DLQ, simple).
- **Kinesis/MSK** for *streams* (replay, multiple independent consumer groups, ordering by partition key, high throughput, event sourcing).
- **The deciding question:** "Do I need to **replay** the data, or do multiple independent consumers each need the full stream?" Yes → Kinesis/MSK. No → SQS.

**Step Functions vs rolling your own orchestration:** Step Functions gives you durable state, visualisation, retries with backoff, parallelism, error handling and a 1-year execution window — for a price per state transition. **Hand-rolled orchestration in code is cheaper per execution but you reimplement durability, retries and observability, and you'll get the edge cases wrong.** For high-volume simple flows, Express mode or code + SQS may be cheaper; for complex business workflows, Standard is worth it.

---

## 🔵 Advanced

### 13. IAM — the model, and how to get it right
```
Principal (IAM user / role / federated identity / service)
   │  assumes (STS AssumeRole → temporary credentials)
   ▼
Identity-based policy (attached to the principal)     ┐
Resource-based policy (attached to the resource: S3,   ├─► evaluation
  KMS, SQS, Secrets Manager, Lambda)                   │   explicit DENY wins;
Permission boundary (max permissions a role can have)  │   else ALLOW required from
SCP (org-level max permissions, doesn't grant)         │   identity AND resource (cross-account)
Session policy (further restricts an assumed session)  ┘
```
**Key mechanics:**
- **Policies are evaluated**: an explicit `Deny` anywhere always wins; otherwise an `Allow` is required. **Cross-account access requires an Allow in *both* the identity policy and the resource policy** (except for some services).
- **Roles, not users, for workloads.** EC2 instance profiles, ECS task roles, **EKS Pod Identity / IRSA** (IAM Roles for Service Accounts), Lambda execution roles. **Long-lived IAM user access keys are a liability** — they can't be rotated automatically, they leak, and they're the #1 cause of AWS compromise.
- **IRSA vs EKS Pod Identity**: IRSA uses an **OIDC provider + a projected service account token** and requires per-role trust policies naming the OIDC subject (`system:serviceaccount:ns:sa`) — precise but verbose, one OIDC provider per cluster. **EKS Pod Identity** (newer, simpler) uses the **EKS Auth API**, doesn't need an OIDC provider, works across clusters, and supports session tags — but doesn't do cross-account the same way. **Knowing both and the migration direction is current.**
- **STS temporary credentials** everywhere: `AssumeRole` (cross-account, privilege elevation, federation), `AssumeRoleWithWebIdentity` (OIDC — **this is how GitHub Actions/GitLab CI get AWS creds without stored keys**), `AssumeRoleWithSAML`, `GetFederationToken`, `GetSessionToken`. Default 1 hour (configurable to 12h for roles).
- **Permission boundaries**: an IAM policy that caps what a role *can* be granted — lets you delegate role creation to teams without letting them grant themselves admin. **Underrated and rarely used; naming it is a strong signal.**
- **SCPs** (Service Control Policies, in Organizations): **deny-list guardrails at the org level that even the root user can't exceed**. E.g. deny disabling CloudTrail, deny leaving the org's approved regions, deny `s3:DeleteBucket` on tagged-critical buckets, deny root actions, require IMDSv2. **SCPs don't grant — they only restrict.** This is the layer that survives a Terraform mistake (see [`09-IaC-Terraform`](../09-IaC-Terraform/README.md#13-a-terraform-apply-destroyed-a-production-database-what-happened-and-how-do-you-prevent-it)).
- **IAM Access Analyzer**: finds externally-shared resources and generates least-privilege policies from CloudTrail activity. **`iam:GenerateServiceLastAccessedDetails` / Access Advisor** show what permissions a role *actually used* — the practical path to least privilege.
- **Condition keys** are where real policy precision lives: `aws:SecureTransport`, `aws:SourceIp`, `aws:PrincipalOrgID`, `aws:ResourceTag/x`, `s3:prefix`, `ec2:MetadataOptions`, `aws:RequestedRegion`, `aws:PrincipalIsAWSService`. **Requiring `aws:PrincipalOrgID` on resource policies prevents the confused-deputy problem.**
- **The confused deputy**: a service with broad permissions is tricked into acting on behalf of an unauthorised principal. Prevented by `aws:SourceArn`/`aws:SourceAccount` conditions on service roles (Lambda, CloudFormation, EventBridge, S3 replication).

### 14. Multi-account architecture and landing zones
**Why multiple accounts (not multiple VPCs or tags):**
- **Hard security boundary**: IAM in one account cannot grant access to another account's resources without explicit cross-account policy. A compromised workload account can't touch the security account.
- **Blast radius containment**: quotas, service limits, and incidents are per-account.
- **Billing attribution**: per-account bills, no tag hygiene required.
- **Independent lifecycles**: a sandbox account can be nuked and rebuilt.
- **Compliance scoping**: PCI-scope only the accounts that need it.

**Standard AWS Organizations layout (Control Tower / AWS Landing Zone):**
```
Root (Organization)
├─ Management/Payer account        ← billing only, MFA'd, no workloads, minimal users
├─ Log Archive account             ← centralised, immutable CloudTrail/Config/VPC flow logs (cross-org write, nobody can delete)
├─ Audit/Security account          ← Security Hub, GuardDuty delegated admin, IAM Access Analyzer, Detective
├─ Shared Services / Network       ← Transit Gateway, DNS (Route 53 Resolver), AD, artifact registry, CI/CD
├─ Sandbox OU                      ← permissive SCPs, auto-expiry, easy creation
├─ Workloads OU
│   ├─ Prod OU    ← strict SCPs, no console write, break-glass only
│   └─ NonProd OU ← moderate SCPs
├─ Suspended OU                    ← quarantined accounts
└─ Policy OU (management-only)
```
**Mechanisms:** **Organizations** (OUs, SCPs, consolidated billing, delegated administrators), **Control Tower** (automated landing zone + guardrails/controls), **Transit Gateway** (hub-and-spoke network with centralised inspection VPC — the standard for east-west control), **RAM** (share subnets/TGW/resolver rules across accounts without duplication), **SSO / IAM Identity Center** (one identity store, permission sets mapped to accounts, **no IAM users at all**), **CloudFormation StackSets** / **Terraform** for account vending.

**The pattern to describe:** "**Account vending** — a team requests an account through a self-service pipeline; Terraform/Control Tower creates it in the right OU with the right SCPs, network attachment (TGW + shared subnets), identity (SSO permission set), baseline security (GuardDuty, CloudTrail to the log archive, Security Hub), billing tags, and a bootstrap of the platform components. **The account is born compliant.** That's the difference between a landing zone and a pile of accounts."

### 15. CloudTrail, Config, GuardDuty, Security Hub — the detection stack
| Service | What it records | Notes |
|---|---|---|
| **CloudTrail** | **API calls** (management events; optionally data events for S3/Lambda/DynamoDB/KMS; and **insights** for anomalous write activity) | **The audit record.** Multi-region, log-file validation (tamper detection), delivered to the log-archive S3 bucket with object lock. **Data events are expensive — scope them.** |
| **AWS Config** | **Resource configuration state + change history + compliance rules** | Answers "what did this security group look like last Tuesday?" and "which resources are non-compliant with our policy?" via Config Rules (managed or custom Lambda). **Also expensive at scale — record only what you need.** |
| **GuardDuty** | **Threat detection** from CloudTrail, VPC Flow Logs, DNS logs, EKS audit logs, S3 data events, and malware scanning | Findings like "credentials used from outside AWS", "IAM user recon", "Bitcoin mining", "container spawned a shell". **Enable org-wide with delegated admin.** |
| **Security Hub** | **Aggregation + normalisation (ASFF)** of GuardDuty, Inspector, Config, IAM Access Analyzer, Macie, partner findings + CIS/AWS Foundational Standards posture | The single pane. **Cross-region aggregation.** |
| **Inspector** | **CVE scanning** for EC2 (via SSM), ECR images (continuous), and Lambda (code + dependencies) | Continuous, not on-demand |
| **Macie** | **Sensitive data discovery** in S3 (PII, credentials) | Cost-driven: scope to the buckets that matter |
| **IAM Access Analyzer** | External access paths + unused permissions + policy generation | |
| **Detective** | Investigation graph built from logs | For deep forensics |

**The answer shape:** "CloudTrail is *what was done*, Config is *what things are*, GuardDuty is *what looks malicious*, Security Hub is *the roll-up*. You need all four to answer an incident, and they're cheap relative to the alternative. The two things I'd insist on: **CloudTrail and Config logs go to a separate log-archive account that no workload account can write-delete**, with object lock and a retention policy; and **GuardDuty/Security Hub are enabled org-wide automatically for new accounts**, not per-account by choice."

**VPC Flow Logs** deserve a separate mention: per-ENI/subnet/VPC, capturing 5-tuple + action + bytes, to S3/CloudWatch. **Essential for "who talked to whom" questions, Security Group/NACL debugging, and detecting lateral movement.** They're voluminous and cost real money → sample, aggregate, and retain in tiers.

### 16. Cost management — the systematic approach
1. **Attribute first.** You can't optimise what you can't allocate: **mandatory tags** (team, environment, cost centre, application) enforced by SCP (`aws:RequestTag`) and by IaC; **cost allocation tags** activated; **CUR (Cost and Usage Report)** to S3 + Athena/QuickSight or a third-party (Vantage, CloudHealth, Spot.io). **Untagged spend is unmanageable spend.**
2. **Find the top 10 line items.** Pareto always applies — usually EC2, RDS, data transfer, S3 storage+requests, NAT Gateway, EBS, snapshots, CloudWatch, Lambda, and one surprise.
3. **The highest-yield levers, roughly in order:**
   - **Right-sizing** using observed utilisation (Compute Optimizer, CloudWatch p95). Most fleets are 30–50% over-provisioned. **But right-size against the SLO, not against the peak** — headroom is a reliability requirement.
   - **Commitment coverage**: Compute Savings Plans for the stable baseline (target 70–80% coverage), on-demand for the elastic top. **Buy after right-sizing, or you commit to waste.**
   - **Spot** for stateless, interruptible, and batch/container workloads (EKS managed node groups, ASG mixed instances, EMR, CI runners, batch jobs). Typically the biggest single saving available.
   - **Data transfer**: **S3/DynamoDB Gateway Endpoints** (free) instead of NAT; **interface endpoints** for other AWS APIs; reduce cross-AZ chatter (co-locate, use single-AZ where safe); CDN/cache to reduce origin egress; check for chatty inter-service calls.
   - **NAT Gateway**: $/hour + $/GB is a common top-5 surprise. Endpoints fix the S3 part; a **central egress VPC** can consolidate; or move egress-heavy work to a NAT instance for non-critical traffic (with the reliability trade-off).
   - **Storage**: S3 lifecycle + non-current version expiry + abort incomplete multipart uploads; EBS gp2→gp3; snapshot lifecycle policies (old snapshots accumulate forever); **delete unattached EBS volumes and unused AMIs/Elastic IPs** (a classic waste source — an unattached EIP costs money).
   - **Zombie resources**: idle load balancers, empty EKS clusters, unattached volumes, orphaned snapshots, forgotten dev environments running 24/7 (**schedule non-prod shutdowns — 65% saving on dev/test**), over-provisioned Reserved capacity.
   - **CloudWatch**: custom metrics, log ingestion/retention, and **high-resolution alarms** are quietly expensive. Set log retention (default is *forever*), drop useless logs at the source, and reduce metric cardinality.
   - **Databases**: Aurora Serverless v2 min capacity → 0 for spiky work; RDS instance right-sizing; **DynamoDB GSI count** (each multiplies write cost); reserved capacity for steady RDS/DynamoDB.
4. **Governance**: per-team budgets with **actual *and* forecasted** alerts at 50/80/100%; **anomaly detection** (AWS Cost Anomaly Detection) — catches the runaway job on day 2 instead of invoice day; **showback/chargeback dashboards** so teams see their own spend (visibility alone typically cuts 10–20%); **cost review in the same meeting as reliability**; **Infracost on Terraform PRs** so cost is a review-time decision.
5. **The maturity statement:** "Cost work has two phases: a one-off cleanup (right-sizing, commitments, endpoints, lifecycle policies, zombies) that typically finds 20–40%, and then a **durable operating model** — tagging enforced by policy, budgets owned by teams, anomaly alerts, cost in PR reviews, and architecture standards that are cheap by default (Graviton, gp3, endpoints, spot-friendly design). Without the second phase the savings decay within two quarters."

### 17. Well-Architected — the six pillars and how to use the framework
| Pillar | Core questions |
|---|---|
| **Operational Excellence** | Do you run workloads as code? Can you observe them? Do you learn from failure? Are runbooks and on-call real? (`Well-Architected Ops review`, game days, alerting quality) |
| **Security** | Identity as the perimeter (least privilege, no long-lived keys), traceability, defence in depth, data protection (encryption everywhere, key management), automated security (SCP, Config rules, GuardDuty), incident response readiness |
| **Reliability** | Recovery objectives (RTO/RPO) defined and **tested**, horizontal scaling, no single points of failure (AZ/region/service), automated recovery, capacity planning, chaos/game days |
| **Performance Efficiency** | Right compute (Graviton, serverless where it fits), storage class matching access patterns, global edge (CloudFront), architecture for scale (offload, cache, async), and **measuring rather than guessing** |
| **Cost Optimisation** | Expenditure awareness (attribution, budgets, anomaly detection), cost-efficient resources, matching supply to demand, **removing undifferentiated heavy lifting** (managed services) |
| **Sustainability** | Efficient compute/storage, reduced data movement, region selection for carbon intensity, right-sized usage, and the observation that most sustainability work *is* cost work |

**How to use it in an interview:** "I use it as a **review checklist and a shared vocabulary**, not a compliance badge. The value is that it forces the questions you'd otherwise skip — 'what's your RTO and when did you last test it?', 'who can read this state file?', 'what happens when this AZ dies?' — and produces prioritised findings with owners. The failure mode is doing a review, writing 80 recommendations, and implementing none; so I'd cap it at the top 5 per workload with owners and dates, and re-review on a cadence. And the **Well-Architected Tool / Lens** for your specific workload type (SaaS, Data Analytics, ML) is more useful than the generic pillars."

---

## 🔴 Scenario

### 18. "Design a highly available, multi-region e-commerce platform on AWS."
**Start with the requirements, out loud:** "What are the RTO and RPO? Is this active-active or active-passive? What's the budget multiplier for the second region — multi-region typically doubles infra cost plus engineering effort? And which parts of the system *must* be global versus which can be regional?" **Because the answer is completely different for RTO=minutes/RPO=0 versus RTO=4h/RPO=5min, and most teams don't know their own numbers.**

**Assume: RTO < 15 min, RPO < 1 min for orders, global customer base, ~50k rps peak.**

**The architecture:**
```
                       Route 53 (latency + health-checked failover, TTL 30s)
                                 │
              ┌──────────────────┴──────────────────┐
        Region A (primary)                     Region B (warm/active)
        ┌────────────────────┐                ┌────────────────────┐
CloudFront (global edge, origin failover, OAC)  ── shared, global
        │
   WAF ─► ALB (multi-AZ) ─► ECS/EKS across 3 AZs
        │                        │
        │              ┌─────────┼──────────┐
        │          API/cache   Workers    Search
        │          ElastiCache (global     OpenSearch
        │          datastore optional)     cross-region repl.
        │                        │
        ├─ Aurora Global Database (writer in A, read replicas in B; promote B on failover)
        ├─ DynamoDB Global Tables (active-active, last-writer-wins)
        ├─ S3 Cross-Region Replication (media, backups; + Object Lock)
        ├─ Kinesis/MSK MirrorMaker (event replication)
        └─ SQS/SNS (regional; DLQs regional)
        │
   Transit Gateway ─► shared services VPC (CI/CD, artefacts, DNS resolver, egress)
   CloudTrail/Config/GuardDuty → Log Archive account (org-wide, immutable)
```

**The decisions to articulate (this is where the score is):**

1. **Data is the hard part; compute is easy.** Stateless compute replicates trivially (deploy the same containers to both regions, point DNS). **The database is where multi-region actually costs you.** Options:
   - **Aurora Global Database**: single writer region, read replicas elsewhere, < 1s typical lag, promote the secondary in ~1 min. **RPO = seconds (async), RTO ≈ minutes.** **This is the pragmatic answer for most e-commerce** — you accept a single-writer region and a small data-loss window.
   - **DynamoDB Global Tables**: true multi-active, no promotion step, **but last-writer-wins conflict resolution and no cross-region transactions** → fine for carts/sessions/catalogue, dangerous for inventory counters and money.
   - **Sharded by region with single-writer per shard** (users in region A write to A): strongest consistency, hardest routing, and users who travel break it.
   - **My answer:** Aurora Global for orders/payments (single writer, controlled failover, small RPO), DynamoDB Global Tables for sessions/cart/catalogue (multi-active is fine there), S3 CRR for media. **Different data classes get different consistency/availability trade-offs — a uniform answer is a wrong answer.**
2. **Inventory overselling under multi-region.** If both regions can decrement stock, you get oversells. Solutions: single-writer for inventory (route those writes to the primary region — adds latency but is correct), reservation-based allocation (partition inventory by region), or a strongly consistent counter in one place. **Naming this trade-off is the strongest signal in the whole answer.**
3. **DNS failover is not instant.** TTL 30s is a floor, not a promise: resolvers ignore TTLs, clients cache, and long-lived connections don't re-resolve. **So plan for minutes, and design clients to reconnect and retry with backoff** (not to hold a dead connection). Health-checked Route 53 failover plus **CloudFront origin failover** gives faster, more reliable切换 than DNS alone for HTTP.
4. **The standby region must be warm.** Cold caches, cold JITs, cold connection pools, and un-scaled capacity mean failover *causes* an outage. Keep real (or shadow) traffic flowing, keep capacity at a meaningful fraction (or autoscale aggressively with pre-warmed pools), and **fail over gradually** rather than flipping 100%.
5. **Failover must be a tested, documented, low-decision procedure.** Which checks trigger it, who decides, what order (DNS → verify → ramp → monitor), what breaks (in-flight orders, idempotency keys, session affinity), and **how you fail back** (the harder half: reconciling writes made in region B). **Run it quarterly. An untested multi-region architecture is a marketing claim.**
6. **Dependencies define your real availability.** A single-region third-party payment provider, one DNS provider, one auth SaaS, or a global service with a regional dependency (some AWS services are region-scoped; IAM/Route 53/CloudFront are global but **STS is regional with a global endpoint**, and a region-wide AWS event can affect multiple services at once). **Map them; the weakest link is your SLO.**
7. **Statelessness is a prerequisite.** No local session state (externalise to DynamoDB/ElastiCache), no local file uploads (S3), no sticky in-memory caches that can't be rebuilt, no long-lived in-process jobs (use a durable queue/workflow with visibility into region).
8. **Idempotency everywhere.** Failover means retries, and retries mean duplicates. **Idempotency keys on every mutation** (order creation, payment) with a durable dedupe store, or you double-charge during every failover.
9. **Security and governance must be global too**: org-wide SCPs, a central log-archive account receiving CloudTrail/Config from *both* regions, GuardDuty/Security Hub aggregated cross-region and cross-account, KMS keys per region (with a key-replication strategy — **KMS keys are regional**, and an app that can't decrypt in region B can't serve there), and secrets replicated (Secrets Manager multi-region replication).
10. **Observability must be global**: cross-region dashboards, a single pane showing both regions' SLOs, and **per-region SLOs plus a global user-facing SLO** (because a user in region B experiencing degradation is a real degradation even if region A is perfect).
11. **Cost honesty**: "This is roughly 1.8–2.2× the infra cost of single-region plus meaningful engineering and testing cost, and it buys you an RTO of minutes instead of hours. If the business can tolerate a 2-hour outage twice a decade, a well-tested single-region multi-AZ architecture with fast restore is far cheaper and often *more* reliable in practice, because it's simpler. **I'd push back on multi-region unless there's a real requirement** — a latency requirement for a distant user base, a regulatory data-residency requirement, or a demonstrated availability need that multi-AZ can't meet."

### 19. "An engineer's AWS access keys were committed to a public GitHub repo. Respond."
**This is a live security incident. Order matters — speed on containment, not on forensics.**

**Minute 0–15: Contain (assume compromised, do not investigate first)**
1. **Disable the credentials immediately.** IAM console/CLI: `aws iam update-access-key --status Inactive`, or **deactivate the user**, or if it's a role/temporary credential, tighten the role policy / add an explicit deny. **Do not delete first** — deleting removes your ability to see which user it was and can break audit correlation. **Deactivate, then investigate, then delete.**
2. **Revoke active sessions**: `aws iam update-role --max-session-duration` won't do it; for roles, add a **deny policy with a `aws:TokenIssueTime` condition** (denies all sessions issued before now) — **the standard technique for invalidating STS sessions**, which otherwise remain valid up to 12 hours.
3. **Assess the blast radius from the policy**: what could these keys do? `aws iam list-attached-user-policies`, `get-user-policy`, `iam-simulator`. **Assume the attacker had the *maximum* the credentials allowed.**
4. **Check for attacker activity — the four things they do first, in order of frequency:**
   - **Create new IAM users/roles/keys** for persistence → `aws iam list-users`, compare to your inventory; check CloudTrail for `CreateUser`, `CreateAccessKey`, `AttachUserPolicy`, `CreateLoginProfile`.
   - **Launch GPU/large instances for crypto mining** → `ec2 DescribeInstances` filtered by state=running, unexpected instance types/regions; a **huge spike in EC2 costs in an unusual region is the classic signature**.
   - **Exfiltrate S3 data** → CloudTrail **S3 data events** (if enabled — **if not, you have a visibility gap, which is itself a finding**), `GetObject` volume anomalies, unusual source IPs.
   - **Enumerate** → GuardDuty findings (`Recon:IAMUser/*`, `UnauthorizedAccess:IAMUser/*`, `PenTest:*`), CloudTrail for `GetUser`, `ListRoles`, `ListBuckets`, `DescribeInstances` from a foreign IP.
5. **Contain the infrastructure**: stop/terminate unexpected instances, revoke unexpected security group rules (miners often open ports), suspend unexpected Lambda functions, block the attacker IPs at the perimeter (**but don't rely on IP blocking — they'll rotate**).
6. **Rotate everything else those keys could reach**: database passwords in Secrets Manager, third-party API tokens stored there, SSH keys, signing keys. **If the credentials had `secretsmanager:GetSecretValue` on a broad resource, assume every secret in it is compromised.**

**Minute 15–60: Eradicate and preserve**
7. **Preserve evidence**: export the relevant CloudTrail window, GuardDuty findings, VPC Flow Logs, and the GitHub commit history (including the fact it was **force-pushed** — deleting the commit doesn't remove it from history or from the scrapers that already have it). **Do not force-push the repo to "clean" it as your first action** — you lose the audit trail, and the keys are already harvested (automated scanners find public keys in **seconds to minutes**).
8. **Delete the attacker's artifacts**: rogue users, roles, keys, instances, Lambda functions, snapshots they created (check for **snapshots shared externally** — a classic exfil path: `ModifySnapshotAttribute` with `createVolumePermission`).
9. **Delete the leaked credentials** and remove them from Git history (`git filter-repo`/BFG) *after* evidence is captured — and understand this is hygiene, not remediation.
10. **Check for lateral movement**: was the key able to assume roles? Did it access EKS (`aws-auth`/Pod Identity mappings)? Any cross-account access?

**Hour 1–24: Notify and recover**
11. **Legal/compliance notification path**: if customer data was exfiltrated → GDPR (72 hours to the regulator), and other regimes as applicable. Involve legal and the DPO **early**, not after you've finished the technical work.
12. **Customer/stakeholder communication** per your incident comms plan.
13. **Verify recovery**: no unexpected resources, no unexpected access, credentials rotated, monitoring clean for 24–72 hours.

**Then: fix the system (the part that determines whether it recurs)**
14. **Prevent**:
    - **Eliminate long-lived keys entirely.** OIDC federation for CI (GitHub Actions → `AssumeRoleWithWebIdentity`), instance profiles / task roles / IRSA-Pod Identity for workloads, **IAM Identity Center for humans** (no IAM users, temporary credentials, MFA enforced). **This is the real fix — a key that doesn't exist can't leak.**
    - **Secret scanning**: GitHub push protection (blocks known AWS keys at push time), pre-commit hooks (gitleaks/trufflehog), and CI scanning of history.
    - **Least privilege + permission boundaries + SCPs**: a leaked key with `ReadOnlyAccess` is an information incident; one with `AdministratorAccess` is an existential one. **SCP-deny the most damaging actions** (disabling CloudTrail, leaving approved regions, deleting backups, sharing snapshots externally).
    - **Guardrails that detect instantly**: GuardDuty (org-wide), CloudTrail (multi-region + data events on sensitive buckets), Security Hub, **Cost Anomaly Detection** (a mining workload shows up as a cost spike within hours), and an alert on **new IAM user/key creation** — that one alert catches most persistence attempts.
    - **Credential rotation policy** and short STS session durations (1 hour default, not 12).
15. **Post-incident review**, blameless: how did it get committed, why wasn't it caught, how fast was detection, how fast was containment, what was missing in visibility. **Action items with owners**, including "add the CI check that would have caught this".

**The framing that scores:** "The technical steps are quick and well-known: deactivate, revoke sessions with a token-issue-time deny, hunt for persistence and mining, rotate, preserve evidence. The part that actually matters is that **this incident was caused by an architecture that allowed a long-lived static credential with broad permissions to exist**. So my remediation is mostly deletion: no IAM users for humans, no access keys for machines, OIDC everywhere, SCPs denying the damaging actions, and an alert on IAM creation events. If I only rotate the key, I'll be back here in six months."

### 20. "Our AWS bill jumped 40% month-over-month with no obvious change. Investigate."
**Method: decompose, then compare, then attribute.**

1. **Get the breakdown before hypothesising.** Cost Explorer grouped by **service**, then by **region**, then by **usage type**, then by **account**, then by **tag**, comparing this month to last. **Enable/consult the CUR for the granular view.** Look for the single biggest delta — it's usually 60–80% of the increase.
2. **Check for the non-obvious drivers first:**
   - **A new region or account** appeared (someone enabled a service, ran a migration, or a sandbox went unsupervised).
   - **Data transfer**: the most common silent killer. Cross-AZ (inter-service chatter, a new chatty integration), cross-region (replication turned on, DR test left running), internet egress (a new public API, a crawler, a CDN misconfiguration with low cache-hit ratio, an S3 bucket being read directly instead of through CloudFront).
   - **NAT Gateway**: $/hour per gateway + $/GB. **A new NAT Gateway per AZ across 6 regions, or a workload suddenly routing lots of traffic through NAT instead of a Gateway Endpoint, is a classic 40% jump.**
   - **S3**: storage growth (versioning turned on → every overwrite retained; **incomplete multipart uploads**; lifecycle policy removed), **request counts** (a new job doing 100M LIST/GET), retrieval fees (data moved to Glacier and then queried), or replication (S3 CRR enabled → double storage + transfer).
   - **Snapshots and AMIs**: automatic snapshot policies with no retention limit; EBS snapshots accumulating forever; cross-region snapshot copies; **unattached EBS volumes still billed**.
   - **CloudWatch**: log ingestion and retention (**a service started logging 10× more, or retention is unlimited**), custom metrics (a cardinality explosion in `PutMetricData` — the AWS equivalent of the Prometheus cardinality problem), high-resolution alarms, dashboards.
   - **EKS/Kubernetes**: **an autoscaler that scaled up and never scaled down** (a very common cause: a broken HPA, a stuck Cluster Autoscaler, or nodes orphaned by a failed scale-down); control-plane hours across multiple new clusters; **unterminated nodes from a botched node-group rollout**.
   - **Lambda**: an event loop (S3 event → Lambda → writes to the same bucket → re-triggers itself: **an infinite loop that can burn thousands of dollars in hours**); increased invocation or duration; **provisioned concurrency** left on after a test.
   - **Databases**: RDS/Aurora storage **auto-scaling** kicked in and never came back down; a new read replica left running; **DynamoDB switched from provisioned to on-demand** during a traffic spike (on-demand can be 2–7× provisioned for steady load); new GSIs multiplying write costs.
   - **Reserved/Savings Plan expiry**: an RI or SP lapsed, so the same usage moved to on-demand pricing. **Check the coverage report — this looks like "no change" in usage but a big change in cost.**
   - **Price changes / new service usage**: AWS price reductions are rare but list-price changes, and a new service (e.g. someone enabled Macie, Inspector, Detective, or a GuardDuty feature across all accounts) adds cost without anyone deploying anything.
   - **Support plan or Marketplace subscriptions**.
3. **Correlate with the change log**: deploys, Terraform applies, account creations, feature launches, traffic growth (marketing campaign, viral event, a bot, a retry storm). **A cost spike usually has a timestamp; find what happened at it.**
4. **Rule out the legitimate causes**: real traffic growth (cost per request stable → not a problem), a planned migration mid-flight, seasonal peak. **Sometimes the answer is "we grew 40%" and that's good news.**
5. **Use the tools**: **Cost Anomaly Detection** (ML-based, should have alerted you — if it didn't, that's a finding), **Compute Optimizer**, **Storage Lens**, **Trusted Storage/Trusted Advisor**, **VPC Flow Logs + Athena** for transfer analysis, **CloudTrail** for who enabled what, and **AWS Budgets** with forecast alerts.

**Then fix and prevent:**
- Fix the specific driver (delete the loop, add the Gateway Endpoint, set snapshot retention, downgrade the log retention, cap DynamoDB, fix the autoscaler).
- **Prevent recurrence**: budgets with **forecasted** alerts at 50/80/100% per account and per team; Cost Anomaly Detection with a real notification path (not a dashboard nobody reads); tagging enforced by SCP; **an architecture review gate for new services** ("what does this cost at 10× traffic?"); monthly cost review with owners; Infracost on IaC PRs; **a Lambda concurrency/reserved-capacity cap and an S3 event-loop guard** (the two runaway-cost patterns); default lifecycle policies on every new bucket and snapshot schedule.
- **The framing:** "A 40% jump with no deploy is almost always one of four things: data transfer, retention that never expires, an autoscaling or event loop, or a commitment that lapsed. I'd check those four first because together they're ~80% of cases, and I'd insist on **forecasted** budget alerts afterwards, because 'we noticed on the invoice' means the detection failed regardless of what the cause was."

### 21. "Design the AWS network for 40 microservices across 3 environments with strict isolation."
**Requirements to pin down:** east-west isolation model, egress control, hybrid connectivity, inspection requirements, IP budget, and who owns what.

**The design:**
```
Organization
├─ Network account (shared services)
│   ├─ Inspection VPC:  Transit Gateway (hub) + central egress VPC + IDS/IPS appliances
│   ├─ DNS: Route 53 Resolver (inbound + outbound endpoints), private hosted zones shared via RAM
│   └─ Artefacts: ECR (VPC endpoints), CI/CD runners
├─ Prod account     → VPC 10.0.0.0/16   (3 AZs)
├─ Staging account  → VPC 10.1.0.0/16   (3 AZs)
├─ Dev account      → VPC 10.2.0.0/16   (2 AZs)
└─ Sandbox account  → VPC 10.3.0.0/16
      each attached to the TGW, in separate TGW route tables (isolation at the hub)

Per-VPC subnet layout (10.x.0.0/16):
  10.x.0.0/20   public   (ALB, NAT GW per AZ, bastion/SSM endpoints)
  10.x.16.0/20  private-app  (ECS/EKS workloads)
  10.x.32.0/20  private-data (RDS, ElastiCache, OpenSearch) — NO default route at all
  10.x.48.0/20  reserved for growth / EKS pod CIDR (VPC CNI needs a lot of IPs)
```
**Isolation, layer by layer (defence in depth is the answer):**
1. **Account isolation** — the hardest boundary. Prod/staging/dev/sandbox in separate accounts. A compromise in dev cannot reach prod without an explicit cross-account grant.
2. **TGW route-table isolation** — separate TGW route tables per environment with **no cross-environment routes**. Dev cannot reach prod at L3, period. This is stronger and simpler than trying to do it with NACLs.
3. **VPC/subnet tiering** — public (ingress/egress only), private-app, private-data (no internet route, reachable only from private-app via SG). **Databases in a subnet with no default route** is the single most valuable network control.
4. **Security Groups as the primary control** — **reference other SGs, not CIDRs** (`source_security_group_id: sg-app`), least-privilege ports, one SG per service role (alb-sg, app-sg, db-sg), no `0.0.0.0/0` except on the ALB's 443. **SG chaining** (alb-sg → app-sg → db-sg) gives you a readable, auditable flow.
5. **NACLs for coarse subnet-level deny** — e.g. deny the data subnet from initiating outbound, or block known-bad ranges at the perimeter. Stateless, so remember ephemeral ports.
6. **Egress control** — **centralised egress VPC** with an inspection appliance (or AWS Network Firewall / a firewall Gateway Load Balancer endpoint) so all outbound traffic is inspected and domain-filtered. **Default-deny egress with an allowlist** is the goal; NAT-only egress with no filtering is what most teams actually have, and it's how data exfiltration happens.
7. **East-west inspection** — TGW with an **inspection VPC** in the path (route traffic through the firewall GWLB endpoint) for inter-VPC inspection, if required. **Cost and latency trade-off**: full mesh inspection is expensive; scope it to sensitive flows.
8. **In-cluster isolation** (EKS/ECS) — **NetworkPolicy** (Cilium/Calico) per namespace, one namespace per service or team, PSA `restricted`, and **per-pod IAM (IRSA/Pod Identity)** so a compromised pod can't use the node role.
9. **VPC Endpoints for AWS APIs** — interface endpoints for SSM/ECR/STS/KMS/Secrets Manager/CloudWatch Logs/SQS, gateway endpoints for S3/DynamoDB. **This removes the need for internet egress entirely for AWS API traffic** — a big security *and* cost win, and it means your private subnets don't need a NAT Gateway for normal operation.
10. **DNS** — private hosted zones per environment, **split-horizon** (same name, different records per VPC via Resolver rules), Resolver inbound endpoint for hybrid, outbound endpoint for on-prem forwarding. **DNS is the service-discovery layer; keep it inside the VPC.**
11. **Hybrid connectivity** — Direct Connect (with a hosted connection from a partner, or two connections for redundancy) into the network account, VPN as backup, ** Transit Gateway with a VPN/DX attachment**. Multi-region: TGW peering or a mesh.
12. **Access to instances** — **no SSH from the internet, no bastion hosts**. **SSM Session Manager** with IAM-based auth, CloudTrail-logged sessions, and no inbound ports at all. **This is the modern answer and saying "no bastion" is a marker.**
13. **IP budget discipline** — a documented CIDR plan (RFC1918 allocation per account/env/region), because **you cannot resize a VPC**, and EKS with the VPC CNI consumes an IP per pod (a /24 per node group vanishes fast). Consider **secondary CIDRs** and custom pod CIDRs, or a non-VPC-CNI datapath (Cilium in native routing/overlay mode) if IP exhaustion is a concern.
14. **Observability of the network** — VPC Flow Logs to the central log account, **Network Access Analyzer** (finds unintended reachability paths automatically), Reachability Analyzer for specific questions, and **flow-log-based alerting** on unexpected cross-environment or egress traffic.
15. **Everything as code** — the whole topology in Terraform with the account-vending pipeline, so a new environment is a PR. **Manual VPC changes are how isolation quietly erodes.**

**The trade-offs to state:** "Full inspection of all east-west traffic is what security teams ask for and what latency and cost often forbid — so I'd inspect north-south and cross-environment flows by default, and only sensitive east-west flows on request. And I'd accept some duplication (endpoints per VPC, NAT per AZ) because the isolation and failure-domain benefits outweigh the cost; consolidating those into a single shared path creates the coupling the design is trying to remove."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| Long-lived IAM user access keys for workloads | The #1 AWS compromise vector; use roles/OIDC |
| IMDSv1 enabled / hop limit > 1 | SSRF → credential theft (the Capital One pattern) |
| `t3` instances for steady production load | CPU credit exhaustion → mystery slowdowns |
| Public subnets defined by name, not by route table | You don't know what's actually public |
| S3 access from private subnets via NAT Gateway | Paying twice; use the free Gateway Endpoint |
| No Block Public Access at the account level | One bad bucket policy = a public data breach |
| No versioning/object lock on critical buckets | Ransomware and accidental deletion |
| No lifecycle rule for incomplete multipart uploads / non-current versions | Invisible, permanent cost |
| Security groups with CIDRs instead of SG references | Unmaintainable, breaks on scaling |
| NLB with cross-zone balancing left at default | Uneven distribution, cross-AZ charges |
| `DeleteOnTermination=true` on a data volume | Data gone when the instance dies |
| gp2 when gp3 is available | Paying more for less; size-coupled IOPS |
| Restoring an EBS snapshot and applying load immediately | Lazy loading → hours of terrible latency (use FSR/pre-warm) |
| No connection pool TTL / RDS Proxy with Multi-AZ RDS | Failover succeeds, app never recovers |
| 50 pods × 20 connections straight to Postgres | You took down your own database |
| DynamoDB partition key like `date` or `status` | Hot partition → throttling at 5% table utilisation |
| Reading your own write through a GSI | GSIs are eventually consistent |
| SNS as a durable queue | No retention — dropped messages when the subscriber is down |
| SQS visibility timeout < processing time | Duplicate processing |
| No DLQ + redrive on SQS | Poison messages silently retried forever or lost |
| Lambda async failures with no DLQ/destination | Silent data loss |
| Unbounded Lambda concurrency / no S3 event-loop guard | A runaway bill in hours |
| Deleting the leaked key before investigating | You lose attribution and audit correlation |
| Force-pushing to "clean" the leaked key from Git | Evidence gone; the key was harvested in seconds anyway |
| Cost alerts on actuals only, not forecasts | You find out on the invoice |
| Bastion hosts with SSH from the internet | Use SSM Session Manager |
| Untested multi-region failover | A marketing claim, not an architecture |

## Rapid recall

**Compute:** EC2 families (`m/c/r/i/g/t`); **`t` = CPU credits → exhaustion caps you**; Graviton for price-performance; **Compute Savings Plans for the baseline, Spot for stateless/interruptible** (2-min notice, capacity-optimized, diversify, rebalancing signal); ASG with **ELB health checks** + grace period + target tracking on the *right* metric; **IMDSv2 required + hop limit 1**.

**Serverless:** Lambda = per-GB-second, CPU scales with memory, 15-min max, account concurrency ~1,000 (soft), **cold starts** (provisioned concurrency/SnapStart), **async failures need a DLQ/destination**; **VPC Lambdas consume subnet IPs**.

**Containers:** Lambda for events/spiky; **ECS Fargate for teams that don't want to run K8s**; **EKS for large multi-team platforms** (and it's a platform you must staff); App Runner for simple services.

**Networking:** public/private is defined by the **route table**; **NAT GW is per-AZ, $/hr + $/GB**; **S3/DynamoDB Gateway Endpoints are free**; SGs are **stateful, allow-only, reference other SGs**; NACLs are **stateless, allow+deny, per-subnet, rule-number ordered**; ALB (L7, no static IP) vs **NLB (L4, static IP, cross-zone OFF by default)**; **ALB idle timeout 60s** explains "fails at exactly 60s"; Route 53 **alias records at the zone apex**; **TTL is a floor, not a promise**.

**Storage/DB:** S3 is **strongly consistent since Dec 2020**; 11×9s durability ≠ availability; **Block Public Access + versioning + object lock + SSE-KMS**; lifecycle for **non-current versions and incomplete multipart uploads**. EBS is **AZ-bound**, gp3 > gp2, snapshots **restore lazily** (FSR). RDS Multi-AZ = **DNS failover → your pool must reconnect** (RDS Proxy / pool TTL / JVM DNS TTL); **connections are the bottleneck**; **read replicas lag**. Aurora = **6 copies/3 AZs, 4/6 write, 3/6 read**, Global Database for cross-region. DynamoDB: **hot partitions**, GSI eventual consistency, 400 KB items, **each GSI multiplies write cost**, TTL is best-effort.

**Async primitives:** SNS = fan-out notification (**no retention**); SQS = work queue (**standard vs FIFO**, visibility timeout, DLQ); Kinesis/MSK = replayable streams (shards = 1 MB/s in, 2 MB/s out, ordering per partition key); **EventBridge** = event bus with archive/replay; **Step Functions** = durable orchestration (Standard = per-transition/expensive, Express = per-duration/cheap).

**Security:** roles not users; **OIDC/IRSA/EKS Pod Identity**; **STS sessions revoked with a `aws:TokenIssueTime` deny**; **permission boundaries** cap delegation; **SCPs** are org-level denies that survive Terraform mistakes; **confused deputy** → `aws:SourceArn`/`aws:SourceAccount` conditions; CloudTrail (what was done) + Config (what things are) + GuardDuty (what looks malicious) + Security Hub (roll-up), all shipping to an **immutable log-archive account**.

**Architecture:** multi-account landing zone (management/log-archive/audit/shared-services/sandbox/prod/nonprod OUs) + **account vending** so accounts are born compliant; TGW hub-and-spoke with **per-environment route tables**; **central egress with inspection**; **SSM Session Manager, no bastions**; **VPC endpoints so private subnets need no NAT**; IP budget planned up front (VPCs can't be resized; VPC CNI eats IPs).

**Cost:** tag + attribute → find the top-10 delta → the four usual jumpers are **data transfer, retention that never expires, an autoscaling/event loop, and a lapsed commitment** → then a durable model (forecast budgets, anomaly detection, Infracost on PRs, cheap-by-default standards).

**Multi-region:** compute is easy, **data is the hard part**; Aurora Global (single writer, RPO seconds) for orders, DynamoDB Global Tables (multi-active, LWW) for sessions/cart; **inventory needs a single writer or you oversell**; keep the standby **warm**; **fail over gradually**; **failback is harder**; **idempotency keys everywhere**; and **push back unless there's a real requirement**.

→ Next: [`13-Cloud-Multi-Azure-GCP`](../13-Cloud-Multi-Azure-GCP/README.md)
