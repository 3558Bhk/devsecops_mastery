# RTIQ — AWS Other Services (Real-Time Interview Questions)

> **Cloud:** AWS · **Domain:** API Gateway, CloudFront, ECS, EKS, ElastiCache, KMS, Lambda, Route 53, Secrets Manager, SNS, SQS, Systems Manager · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~65 min

**How this file is used live:** these are the services that show up in *architecture* rounds. The interviewer's real question is never "what is SQS" — it's "design a system that does X, and defend your choices under load, failure, and cost". Be ready to name limits, failure modes, and what you'd monitor.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. API Gateway — `api-gateway.md`

**⚡ Rapid**
1. **Q:** REST vs HTTP API — which do you pick?
**A.** HTTP API: cheaper (~70%), lower latency, simpler — JWT auth, Lambda/HTTP proxies. REST API: API keys, usage plans, request/response transforms, WAF integration, private endpoints, more auth options (IAM, custom authorizers). Default to HTTP; REST when you need the extras.
2. **Q:** Where do you put rate limiting?
**A.** Usage plans + API keys (REST) for per-customer quotas, WAF rate-based rules at the edge for abuse, and Lambda/customer-level throttling in the backend. Say all three layers; the answer is "defence in depth, not one knob".
3. **Q:** What's the max integration timeout, and why does that matter?
**A.** REST: 29 s. HTTP API: 30 s. Anything longer must be asynchronous (`202` + polling/webhook/WebSocket) — knowing this unprompted shows you've hit it in production.
4. **Q:** How do you authenticate APIs at the gateway?
**A.** Cognito/JWT (authorizer or native JWT for HTTP APIs), Lambda authorizer for custom logic, IAM SigV4 for internal service-to-service, and mTLS for partner integrations. Keep business authorization in the service — the gateway proves identity, not entitlement.
5. **Q:** What is the payload limit?
**A.** 10 MB. Beyond that, use S3 presigned URLs (upload directly to S3, pass the key to the API) — the standard pattern for media.

**🔍 Deep dive**
6. **Q:** Design a public API for 10k req/s with per-tenant throttling and abuse protection.
**A.** CloudFront + WAF (rate rules, bot control, geo) → API Gateway with usage plans/API keys per tenant tier → Lambda or ECS behind a VPC → throttling and quotas enforced both at the gateway and in the service → caching at the gateway for idempotent GETs → structured access logs to CloudWatch/S3 → alarms on 4xx/5xx/latency p99 and per-tenant error spikes.
7. **Q:** How do you version and deprecate an API without breaking customers?
**A.** Path/base-path versioning (`/v1`, `/v2`), parallel running with a documented deprecation window, sunset headers, monitoring per-version usage so you know who's still on v1, and a staged rollout (canary) of breaking changes. Never break a published contract silently.
8. **Q:** Why use a private API Gateway / VPC endpoint instead of public?
**A.** Internal-only services shouldn't be internet-reachable: private REST API with an interface VPC endpoint + resource policy restricting `aws:SourceVpce`, or keep it fully internal behind an ALB. This comes up in "how do you secure internal APIs" questions.
9. **Q:** How do you debug a 502/504 from API Gateway?
**A.** 502 usually = malformed Lambda response (missing `statusCode`), Lambda crashing, or an integration permission/format error. 504 = backend exceeded the 29 s integration timeout (ALB/Lambda too slow, or a connection to a private resource hanging). Check execution logs and Lambda logs — the gateway tells you almost nothing on its own.
10. **Q:** How do you handle retries and idempotency for POSTs?
**A.** Clients send an idempotency key; the backend stores it with the result and returns the cached response for a repeat (DynamoDB TTL is the usual store). Combine with jittered backoff, and only retry idempotent operations from the gateway/client side.

**🚨 War room**
11. **Q:** Sudden 429s across all tenants at peak. What happened and what do you do?
**A.** Check account-level API Gateway throttling limits, per-tenant usage plan quotas, and downstream Lambda concurrency (a Lambda throttle surfaces as 429/502). Mitigate by raising the account limit / requesting a quota increase, adding a queue in front for burst absorption, and enabling gateway caching. Then fix capacity planning with load tests at expected peak ×2.
12. **Q:** A tenant is hammering your API and degrading everyone. Response?
**A.** Per-tenant throttling/quota at the gateway (usage plan), WAF rate rule as the blunt instrument, and if they're a customer, contract-level rate limits plus alerting. The senior point: you need per-tenant *attribution* (API keys/tenant ID in logs) before you can do anything.
13. **Q:** Latency jumped 300 ms after enabling a Lambda authorizer. Why, and is it fixable?
**A.** Authorizers are a synchronous hop on every request and often do a cold-start DB/HTTP call. Fix: cache authorizer results (`authorizerResultTtlInSeconds`), keep authorizer dependencies warm/connection-pooled, and prefer native JWT verification (HTTP APIs) when the logic allows.

**⚖️ Trade-off**
14. **Q:** API Gateway vs ALB for an HTTP service?
**A.** ALB is cheaper per request at high steady volume with full control, but lacks usage plans, request validation, API keys, and rich auth. API Gateway gives API-management features at a cost premium (and Lambda-friendly integration). Public API with tiers → gateway; internal high-volume service → ALB.
15. **Q:** WebSocket API vs polling vs SNS push?
**A.** WebSocket for real-time bidirectional (chat, live dashboards) but you own connection state and scaling; polling is simple but wasteful; SNS/mobile push for notifications to devices. Frequently the pragmatic answer is "webhooks + polling fallback".
16. **Q:** Should the gateway do response transformation?
**A.** Prefer minimal transformation — mapping templates are hard to test and version. Do shaping in the service (or a BFF), keep the gateway for routing, auth, throttling, and observability.

**🎯 Senior**
17. **Q:** How do you run an API platform for 40 teams?
**A.** Golden templates (gateway + authorizer + WAF + logging + alarms) published as IaC modules; centralised Cognito/JWT; per-team usage plans; a shared developer portal and OpenAPI-first contract; standard observability (trace IDs end-to-end); and a deprecation policy. Governance without a bottleneck is the actual deliverable.

**🎯 Senior signal:** quoting the 29 s integration timeout, the 10 MB payload limit, and the idempotency-key pattern instantly signals real production API ownership.

---

## 2. CloudFront — `cloudfront.md`

**⚡ Rapid**
1. **Q:** What can't CloudFront cache, and what do you do about it?
**A.** Anything with `Cache-Control: no-store`/`private`, POST/PUT/DELETE, and responses varying by auth. Use signed URLs/cookies for private content, Lambda@Edge/CloudFront Functions for per-request logic, and accept origin fetches for dynamic paths.
2. **Q:** Explain TTLs.
**A.** `DefaultTTL` applies when the origin gives no caching header; `MinTTL` prevents shorter caching; `MaxTTL` caps longer. Origin `Cache-Control` wins in the middle. Getting this wrong = either stale content or no cache hits.
3. **Q:** How do you invalidate, and what does it cost?
**A.** `CreateInvalidation` with paths (`/*` is allowed but blunt); first 1,000 paths/month free, then per-path cost, and invalidation takes time. Better: versioned filenames (`app.abc123.js`) or `no-cache` on the HTML entry point so you never need to invalidate.
4. **Q:** How do you restrict access to an S3 origin?
**A.** Origin Access Control (OAC, current) — S3 bucket policy allows only the distribution, bucket stays private. Origin Access Identity (OAI) is legacy. Never expose the bucket as a website endpoint for private content.
5. **Q:** What is a cache key, and how do you change it?
**A.** The combination of path + query strings + headers + cookies you choose to forward/policy-include. Fewer dimensions = higher hit ratio; keep host/path always, add only the query params/headers that truly vary the response.

**🔍 Deep dive**
6. **Q:** Design a global static + API architecture with CloudFront.
**A.** S3 + OAC for static assets (immutable, hashed filenames, long TTL), a second behaviour `/api/*` forwarded to an ALB or API Gateway with caching disabled and `Authorization` in the cache key (or bypassed), WAF attached, ACM cert in `us-east-1` (the classic gotcha), and a CloudFront Function for redirects/header normalisation. Add access logging to S3 and real-time metrics/alarms.
7. **Q:** Cache hit ratio is 40%; how do you get it to 90%?
**A.** Look at the top cache keys and forwarded headers/cookies (often an over-broad policy or a session cookie forcing uniqueness), check `Vary` headers from the origin, normalise query strings (strip tracking params, sort order), separate static/dynamic behaviours, increase TTLs, and cache HTML with short TTL + stale-while-revalidate. Then re-measure — hit ratio is a design output, not a switch.
8. **Q:** How do you serve authenticated, personalized content efficiently?
**A.** Two-tier: cache shared/public assets aggressively; personalize via edge functions that inject per-user data, or serve personalized fragments from the API with `private, no-store`. Signed cookies/URLs for premium content. Avoid putting user identity in the cache key for everything.
9. **Q:** What is Lambda@Edge vs CloudFront Functions?
**A.** CloudFront Functions: ultra-light, sub-ms, viewer request/response only, JS only — perfect for header manipulation/redirects. Lambda@Edge: heavier, Node/Python, runs at viewer and origin request/response — needed for auth checks, origin selection, and network calls. Cost/latency difference is significant.
10. **Q:** How do you protect the origin from direct access and abuse?
**A.** OAC for S3; for ALB/API origins, a shared secret header validated at the origin plus WAF at CloudFront, and ideally restrict origin ingress to CloudFront IP ranges (or use a custom header + SG/ALB rule). Direct-to-origin access bypasses your WAF — a favourite security question.

**🚨 War room**
11. **Q:** Users on one continent see errors while others are fine. Diagnose.
**A.** Check per-edge/per-region metrics in CloudFront, origin health (an origin in a failed AZ/region), DNS and any geo restrictions, a WAF rule blocking that geography, or an expired/mismatched certificate. Also check if a recent deployment broke a behaviour and only the misconfigured path is affected.
12. **Q:** After a deploy, users are getting old JavaScript. Fix immediately, then permanently.
**A.** Immediate: invalidate the HTML and JS paths (accept the cost and TTL). Permanent: hashed filenames with immutable caching + `index.html` served with `no-cache`/short TTL. Also check whether a service worker or browser cache is the real caching layer.
13. **Q:** CloudFront bill tripled. Where do you look?
**A.** Requests by path (cache misses hitting origin repeatedly), origin data transfer out (large uncached assets, video), invalidation volume, real-time logs, and any new behaviour accidentally forwarding all headers (killing caching). Fix: cache policy review, compress (Brotli/gzip), move video to a streaming service, and set `MinTTL` floors to stop churn.
14. **Q:** Origin is healthy but CloudFront returns 502/503. What now?
**A.** SSL/TLS mismatch to the origin (SNI, cert chain, protocol version), origin timeouts (`OriginReadTimeout` 30 s default), origin not in the allowed protocol/port, or the origin SG blocking CloudFront IPs. Test the exact Host/SNI combination the distribution uses, not just a browser request.

**⚖️ Trade-off**
15. **Q:** CloudFront vs Global Accelerator for a dynamic API?
**A.** CloudFront for cacheable HTTP and edge logic; GA for TCP/UDP, non-HTTP, or when you need static anycast IPs and the AWS backbone path without caching. Many run both.
16. **Q:** S3 static website hosting vs S3 + CloudFront?
**A.** CloudFront gives TLS, WAF, caching, custom domains, and private buckets. Direct website hosting is HTTP-only, requires a public bucket, and can't do these — use it only for quick tests.
17. **Q:** Signed URLs vs signed cookies?
**A.** Signed URLs for a single object/one-off (downloads); signed cookies for many objects (a whole HLS stream or gated site section) without rewriting every URL.

**🎯 Senior**
18. **Q:** How do you roll out a frontend with zero user-visible downtime and instant rollback?
**A.** Immutable versioned assets in S3 (never overwritten), deploy new assets first, then flip the HTML entry point (a small, uncached object) to the new version, keep the previous version online for rollback (flip back = seconds), monitor RUM/error rates per version, and clean up old assets on a retention policy.

**🎯 Senior signal:** "ACM cert must be in us-east-1", OAC over OAI, and versioned filenames instead of invalidations — three details that reveal real CloudFront ownership.

---

## 3. ECS — `ecs.md`

**⚡ Rapid**
1. **Q:** Fargate vs EC2 launch type?
**A.** Fargate: no instance management, per-task billing, slower scaling granularity, limits (no GPU, no privileged/daemon containers, more $/vCPU-hour at steady high utilisation). EC2: cheaper at high sustained utilisation, full control, but you own capacity, patching, and bin-packing. Crew-size and utilisation decide.
2. **Q:** What is a task definition key field set?
**A.** Image + tag, CPU/memory, port mappings, environment/secrets, log configuration, IAM task role, execution role, health check, and volumes. Versioned — deploy = new revision.
3. **Q:** Service vs task?
**A.** A service keeps N tasks running, registers them with a target group, and handles rolling deployments and autoscaling. A standalone task is one-off/batch.
4. **Q:** How do containers get AWS permissions?
**A.** Task role (what the app can do — prefer this) vs execution role (what the agent needs to pull images/write logs). Giving app permissions to the execution role is a common mistake, as is using the instance role for everything.
5. **Q:** How do you get secrets into a container?
**A.** `secrets` in the task definition referencing Secrets Manager/SSM — injected at start, and you should rotate without redeploying where possible. Never bake secrets into images or plaintext env vars.

**🔍 Deep dive**
6. **Q:** Design a zero-downtime deployment for an ECS service.
**A.** Rolling: `minimumHealthyPercent`/`maximumPercent` tuned (e.g. 100/200), deployment circuit breaker with rollback, ALB health check grace period, connection draining, and a `/ready` endpoint that's only healthy when deps are up. CodeDeploy blue/green when you need instant rollback and traffic shifting with tests.
**↳ Follow-up:** "Deploy got stuck at 50% forever — why?"
**A.** New tasks never became healthy: health check path/port wrong, SG not allowing the ALB, image pull failing (ECR permissions/region), or the circuit breaker wasn't enabled so it just sat there. Always enable the deployment circuit breaker with rollback.
7. **Q:** How do you scale ECS tasks correctly?
**A.** Target tracking on ALB request-count-per-target or CPU; for queue workers scale on SQS backlog per task (custom metric); scale-in protection/long drain for long tasks; and remember the "scale up fast, down slow" asymmetry. Also align the scaling metric with the actual bottleneck.
8. **Q:** How do you reduce ECS cost without hurting reliability?
**A.** Right-size task CPU/memory from actual usage (CloudWatch Container Insights), consolidate onto EC2 with Spot for interruptible workloads, use Fargate Spot for batch/CI, avoid over-provisioned memory reservations, enable Fargate's `capacity provider` with a base of on-demand + Spot weight, and set autoscaling minimums realistically.
9. **Q:** How do service discovery and inter-service communication work?
**A.** ECS Service Connect / Cloud Map for DNS-based discovery; ALB for north-south; avoid tasks calling each other by IP (they change). For east-west with mTLS, Service Connect or a service mesh (App Mesh) — decide based on whether you need encryption/observability between services.
10. **Q:** What breaks when a database connection pool sits in front of autoscaled tasks?
**A.** Each task holds its own pool, so scaling × pool size exhausts DB connections. Fix: use RDS Proxy, reduce per-task pool size, and align application concurrency with the pool. This is one of the most common real-world ECS/RDS incidents.

**🚨 War room**
11. **Q:** Tasks are being killed and restarted constantly. Triage.
**A.** `StoppedReason` in the service events (OOM? health check? image pull? out-of-memory of the container vs the host in EC2 mode?), container exit codes, memory utilisation vs reservation, and whether the ALB health check is failing while the app logs say it's fine. Then check for dependency timeouts causing readiness failure.
12. **Q:** A deployment failed at 2 a.m. and nobody noticed until customers complained. Fix the process.
**A.** Deployment circuit breaker with automatic rollback, alarms on `5xx`/healthy-host count/deployment failure, deploy-time canary analysis, deploy freeze windows for risky periods, and notification to the on-call channel on every deployment state change. Deploys should be observable events, not silent ones.
13. **Q:** ECR image pulls are failing intermittently in one AZ. Why?
**A.** ECR interface endpoint not present/healthy in that AZ (private subnets with no NAT), or the endpoint SG/NACL issue. Also check the execution role's `ecr:GetAuthorizationToken`/pull permissions and the token's 12-hour expiry affecting long-lived agents.
14. **Q:** CPU is low, latency is high. What do you investigate?
**A.** Memory pressure and swap, thread/connection pool exhaustion, downstream dependency latency (DB, cache), task-level network/storage, or the ALB/target-group connection limits. Low CPU with high latency means the bottleneck isn't CPU — check Container Insights memory and the dependency call graph (X-Ray).

**⚖️ Trade-off**
15. **Q:** ECS, EKS, or Lambda?
**A.** Lambda: event-driven, spiky, low-ops, but cold starts/concurrency/time limits. ECS: containerised services with less Kubernetes overhead — the pragmatic default for most teams. EKS: when you need the K8s ecosystem, multi-cloud portability, or platform standardisation across many teams (and you have the team to run it).
16. **Q:** Fargate vs EC2 for a steady-state API?
**A.** At high sustained utilisation EC2 (with reserved/SP) is significantly cheaper and gives you instance-level control; Fargate wins for variable workloads and small teams. Model cost per vCPU-hour at your actual utilisation — the answer flips around 50–70%.
17. **Q:** One cluster for all environments vs cluster per environment?
**A.** Cluster per environment for isolation and simpler IAM/monitoring, unless cost/simplicity dominates in small setups. Namespace-per-env on one cluster is a K8s habit that mostly creates blast-radius risk in ECS.
18. **Q:** Blue/green always, or rolling?
**A.** Rolling is simpler and adequate for most stateless services with good health checks; blue/green when rollback speed, no mixed-version traffic, or compliance-driven "test before switch" matters. Cost: blue/green needs double capacity briefly.

**🎯 Senior**
19. **Q:** You're the platform owner for 30 ECS services. What's standard?
**A.** Golden task-definition modules (logging, secrets, health checks, resource limits), per-service target tracking + alarms, Container Insights on, deployment circuit breakers mandatory, image signing/scanning in the pipeline, Service Connect for east-west, standard log format with trace IDs, and a shared runbook for "service degraded" that any on-call can execute.

**🎯 Senior signal:** mentioning the deployment circuit breaker, per-task DB pool exhaustion, and the execution-role-vs-task-role distinction shows you've run ECS in production, not just completed a tutorial.

---

## 4. EKS — `eks.md`

**⚡ Rapid**
1. **Q:** Managed node groups vs self-managed vs Fargate?
**A.** Managed node groups (AWS handles AMI/patching/lifecycle) are the default. Self-managed for custom AMIs/daemons you can't express otherwise. Fargate profiles for isolation and no-node workloads (with limits: no DaemonSets, no privileged, slower starts).
2. **Q:** How do pods get AWS permissions?
**A.** IRSA (IAM Roles for Service Accounts via OIDC) or the newer EKS Pod Identity. Not the node role — using the node role for pod permissions means every pod shares the node's privileges.
3. **Q:** What controls your pod network?
**A.** The CNI — VPC CNI assigns real VPC IPs (check ENI/IP limits per instance type!). Exhausting IPs is the most common "nodes can't start pods" failure.
4. **Q:** What is Karpenter and why does it matter?
**A.** Just-in-time node provisioning based on pod requirements — replaces cluster-autoscaler + ASG for most cases, with faster scaling, better bin-packing, and spot diversity. It's the modern default answer for node scaling.
5. **Q:** Where do you put cluster-level guardrails?
**A.** Admission control (Kyverno/Gatekeeper/OPA), Pod Security Standards/Admission, network policies, resource requests/limits (LimitRange/ResourceQuota), and RBAC mapped from IAM via EKS access entries.

**🔍 Deep dive**
6. **Q:** Design a multi-tenant EKS cluster for 20 teams.
**A.** Namespaces per team with ResourceQuota/LimitRange, RBAC + IAM access entries per namespace, NetworkPolicies default-deny with explicit allows, Pod Security Admission at `restricted`, Kyverno policies (no `latest` tag, required labels/probes/limits), per-namespace cost allocation via labels + Kubecost, cluster add-ons managed as IaC, and a hard rule that team deploys go through CI with a signed image and a GitOps PR.
7. **Q:** How do you upgrade Kubernetes without downtime?
**A.** Check deprecated APIs first (`pluto`/`kubent`), upgrade the control plane (minor by minor), then node groups/Karpenter nodes with surge/parallelism controls and PDBs, drain one node at a time, validate workloads, and keep the previous AMI for rollback. Control plane can't be downgraded — rehearse in staging on the same version path.
8. **Q:** Pods can't get an IP. Explain.
**A.** VPC CNI IP exhaustion: each ENI has a fixed IP count per instance type, and `WARM_ENI_TARGET`/`WARM_IP_TARGET` prefetch IPs. Fixes: larger/more instance types, subnet CIDR expansion (or custom networking with a separate pod CIDR), prefix delegation to raise IP density per ENI, and lowering warm IP targets. Also check subnet IP availability in the AZ.
9. **Q:** How do you do zero-downtime deploys in Kubernetes?
**A.** Readiness probes that reflect dependencies, `maxSurge`/`maxUnavailable` tuned, PodDisruptionBudgets so drains don't break availability, `preStop` sleep + graceful shutdown to let the ALB deregister, `terminationGracePeriodSeconds` long enough for in-flight requests, and rolling updates gated by CI checks. Argo Rollouts/Flagger for canary analysis.
10. **Q:** How do you observe and secure the cluster?
**A.** Control plane logs (audit, api, authenticator) to CloudWatch/S3, Container Insights or Prometheus (AMP) + Grafana, GuardDuty EKS protection + Runtime Monitoring (eBPF), image scanning (ECR/Trivy), admission policies blocking privileged/hostPath pods, secrets encrypted with KMS, and no cluster-admin for humans (break-glass only, alarmed).
11. **Q:** How do you handle stateful workloads (databases) on EKS?
**A.** Prefer managed services. If you must: StatefulSets with EBS/EFS via CSI, topology-aware scheduling, anti-affinity across AZs, PDBs, Velero for backups, and a strong story for failover. Be explicit that running production databases on EKS is a deliberate cost/vendor trade, not a default.

**🚨 War room**
12. **Q:** `kubectl` works for you but the app is down; nodes show `NotReady`. Triage order?
**A.** Node conditions (`kubelet` stopped? disk/memory pressure? CNI failure?), `kube-system` pods (aws-node, coredns, kube-proxy dependent on the CNI), control-plane health, then recent changes (node group AMI update, subnet/IP exhaustion, IAM policy change breaking the CNI). Most clusters-wide breakage traces back to the CNI or DNS.
13. **Q:** DNS resolution fails inside the cluster intermittently.
**A.** CoreDNS: too few replicas vs query volume, hitting the node's conntrack table (`nf_conntrack`), `ndots:5` causing excessive lookups, or CoreDNS starved of CPU/on the same nodes as the busiest pods. Fix: scale CoreDNS (and use NodeLocal DNSCache), raise conntrack limits, and reduce pointless search-path lookups.
14. **Q:** A runaway pod is OOM-killing neighbours. What do you do?
**A.** Triage: identify the offender (`kubectl top`, node dmesg for OOM events), apply limits/requests, and quarantine (cordon/taint or evict). Structurally: mandatory requests/limits via LimitRange, QoS class awareness, separate node pools for noisy/batch workloads, and admission policies that reject unlimited pods.
15. **Q:** After a spot interruption, some pods took 5 extra minutes to come back. Why?
**A.** No PodDisruptionBudgets + slow image pulls (large images, no pre-pull/caching) + readiness probes with long initial delays + the scheduler waiting on PV attachment (EBS is AZ-bound). Fixes: diversify instance types, image caching/smaller images, faster readiness, and `topologySpreadConstraints` for even distribution.
16. **Q:** Cost doubled after a migration into EKS. Where does it go?
**A.** Idle nodes (requests far above usage), no bin-packing/high request settings, over-provisioned memory requests, NAT/data transfer for image pulls, over-scaled control plane + observability stacks, and orphaned PVCs/EBS volumes. Showback per namespace drives the fix; Karpenter consolidation plus right-sizing gets most of it back.

**⚖️ Trade-off**
17. **Q:** EKS vs ECS — honest answer for a 15-service company?
**A.** EKS if you need the ecosystem (Helm/operators/CRDs), multi-cloud portability, or you already have platform engineers. ECS if you want containers with far less operational surface and a smaller team. Many companies pay a large cognitive tax for Kubernetes features they never use — say that out loud.
18. **Q:** Two big clusters vs many small ones?
**A.** Fewer, bigger clusters cost less and simplify platform tooling, but widen blast radius for control-plane/upgrade issues; many small clusters isolate teams and versions but multiply add-on management and cost. Segregate by environment and by compliance boundary, not per team.
19. **Q:** Managed add-ons vs self-managed Helm charts for CoreDNS/CNI/monitoring?
**A.** Managed add-ons reduce upgrade toil and match AWS-tested versions; self-managed gives version control and customisation. Default to managed for networking/DNS-critical components; self-managed for observability stacks with specific needs.
20. **Q:** Serverless Kubernetes (Fargate profiles) vs managed nodes?
**A.** Fargate removes node ops and gives strong isolation per pod, but higher cost per vCPU at steady load, no DaemonSets/privileged pods, and slower cold starts. Use for isolated/irregular workloads, nodes for the steady core.

**🎯 Senior**
21. **Q:** What does "production-ready" mean for a new EKS cluster? Give me the checklist.
**A.** Private endpoints + bastion/SSM access, control plane logs + audit enabled, KMS envelope encryption for secrets, Pod Identity/IRSA per workload, default-deny NetworkPolicies, PSA restricted + Kyverno guardrails, resource quotas per namespace, Karpenter with spot diversity + consolidation, GitOps (Argo CD/Flux) with signed images, observability (metrics/logs/traces) + SLO alerting, backup/DR (Velero) tested, and upgrade automation with a documented version cadence.

**🎯 Senior signal:** Pod Identity vs IRSA, CNI IP exhaustion, `terminationGracePeriodSeconds` + `preStop` for ALB deregistration, and PDBs. Those four answers separate "I have a CKA" from "I run clusters".

---

## 5. ElastiCache — `elasticache.md`

**⚡ Rapid**
1. **Q:** Redis vs Memcached?
**A.** Redis: persistence, replication, Sentinel/cluster, pub/sub, sorted sets, Lua, streams. Memcached: simple multi-threaded cache, no persistence/replication. Redis covers nearly all cases; Memcached only for a pure, simple, multi-threaded cache.
2. **Q:** Where do you put a cache in the architecture?
**A.** In front of the DB for read-heavy hot data, for session storage (stateless app tier), for rate limiting/counters, and for leaderboards/queues where Redis structures fit. Not as the source of truth unless you've designed durability deliberately.
3. **Q:** What is the 1 MB limit, and why care?
**A.** Redis values ≤512 MB, but you should stay far below (~100 KB) and ElastiCache has a practical 1 MB limit on some operations; large values hurt latency and network. Chunk or restructure large objects.
4. **Q:** What's a hot key and how do you detect it?
**A.** One key receiving disproportionate traffic (a global config, a viral item) pinning one shard. Detect with `--hotkeys`/slow log/CloudWatch per-node CPU variance; fix with client-side caching, replication of the key, key splitting, or a local cache tier.
5. **Q:** How do you connect securely?
**A.** In-transit encryption (TLS) + at-rest encryption + auth token (AUTH/ACL), subnet group in private subnets, SG limited to app SGs, and no public access. Never expose Redis to 0.0.0.0/0 — that's how breaches happen.

**🔍 Deep dive**
6. **Q:** Cluster mode vs non-cluster mode?
**A.** Non-cluster: one shard, replicas for HA, single endpoint, all data in memory of that node — vertical scaling only. Cluster mode: sharded across nodes with multi-key constraints (same slot for multi-key ops, hash tags), auto-failover, horizontal scale, and more complexity. Start non-cluster; go cluster when a single node can't hold the working set or throughput.
7. **Q:** How do you size a cache and pick an eviction policy?
**A.** Estimate working-set size + growth, then pick a node with headroom (70–80% max memory) and set `maxmemory-policy`: `allkeys-lru` for a pure cache, `volatile-lru` when some keys must persist, `noeviction` only for data you can't lose. Alert on `Evictions` and `DatabaseMemoryUsagePercentage` — evictions spiking means you're undersized or caching too much junk.
8. **Q:** Explain cache stampede and how you prevent it.
**A.** Many clients miss the same key simultaneously and hammer the DB. Fixes: request coalescing/single-flight in the app, probabilistic early expiration (refresh before TTL), jittered TTLs, warm the cache after deploys, and lock-based rebuild with a short TTL placeholder. Add DB-level protection (RDS Proxy, rate limiting) as a backstop.
9. **Q:** How do you handle failover and what happens to your app?
**A.** Multi-AZ with automatic failover (~30–60 s, DNS/endpoint update). The app must handle connection errors with retries/backoff and short timeouts, and must not treat a cache outage as a fatal dependency for reads (graceful degradation to the DB with rate limiting). Test failover in staging.
10. **Q:** Redis-based rate limiting — how?
**A.** Atomic INCR+EXPIRE (or a Lua script for token bucket/sliding window) per key (user/IP/tenant), with TTL = window. Watch hot keys at scale (shard the key by bucket), and remember correctness under failover — losing the counter means briefly allowing extra requests, which may or may not be acceptable.
11. **Q:** How do you do queue-like work with Redis vs SQS?
**A.** Redis lists/streams are fast but lack SQS's at-least-once guarantees visibility timeouts, DLQs, and managed scaling; you'd be building reliability yourself. Use SQS for real work queues, Redis for lightweight/short-lived in-memory tasks where loss is tolerable.

**🚨 War room**
12. **Q:** Latency spikes every few minutes with CPU low. What's happening?
**A.** Common causes: fork-based snapshotting (RDB/AOF rewrite) on a large dataset causing copy-on-write stalls, big-key operations (`KEYS`, `SMEMBERS` on huge sets, `FLUSHALL`), memory pressure/swap, or network blips on failover. Check `save` schedule, `latest_fork_usec`, slow log, and dataset size — then reduce snapshot frequency, use replicas for backups, and split big keys.
13. **Q:** Cache hit ratio dropped from 95% to 40% overnight. Investigate.
**A.** A deploy changed key names/TTLs, `maxmemory` reached so eviction started thrashing, a config/policy change introduced per-user keys, or a bulk job flushed/repopulated. Check `Evictions`, `CacheHits/Misses`, key count, and recent code changes; fix by restoring key design/sizing and warming.
14. **Q:** An app's Redis client holds thousands of connections and the node is unhappy.
**A.** Each app instance opens a pool of connections; autoscaling multiplies them. Fix: connection pooling limits, a proxy (Envoy/cluster-mode-aware client), reduce pool size to match concurrency, and check for connection leaks on error paths. `CurrConnections` vs `maxclients` is the metric pair.
15. **Q:** Someone ran `FLUSHALL` in production. Recovery?
**A.** Immediate: accept a cold-cache period, protect the DB (rate limiting/queueing) while it warms, and confirm no data-loss beyond cache (if Redis was used as a data store, restore from snapshot/backup). Then: rename/disable dangerous commands (`FLUSHALL`, `KEYS`, `CONFIG`), ACL-restrict admin commands to a break-glass user, and alarm on their usage.

**⚖️ Trade-off**
16. **Q:** ElastiCache Redis vs DynamoDB DAX vs application-local cache vs CloudFront?
**A.** CloudFront for HTTP-edge caching; local in-process cache for tiny hot data (fast but inconsistent across instances); DAX only if you're already on DynamoDB and need microsecond reads; ElastiCache for general shared caching/sessions/rate limits. Most systems end up with edge + ElastiCache + a small local tier.
17. **Q:** Is caching always worth it?
**A.** No — it adds a consistency surface and an operational dependency. Justify with measured DB load/latency, and make sure the app degrades gracefully. Caching to "make things fast" without metrics is how you get stale-data bugs.
18. **Q:** Multi-AZ replica vs cluster mode for scaling reads?
**A.** Replicas offload reads but a single shard still owns the write path and dataset size; cluster mode scales both. If you're read-dominated with a working set that fits one node, replicas are simpler and cheaper.
19. **Q:** Global Datastore / cross-region replication — when?
**A.** When you need low-latency reads in another region and acceptable async replication lag. Remember failover to a secondary region is manual/promotion-based, and writes go to the primary.

**🎯 Senior**
20. **Q:** Tell me about a caching incident you fixed.
**A.** Ideal shape: cache stampede after a deploy (or eviction storm after resizing) → DB overload → mitigation (single-flight + warm-up + bigger node) → permanent fix (jittered TTLs, pre-warm step in the deploy pipeline, alarms on hit ratio and evictions, and a documented degradation path).

**🎯 Senior signal:** stampede/thundering-herd, big-key latency, and fork-induced stalls are the answers that prove you've owned a cache in production. "We set a TTL" is not.

---

## 6. KMS — `kms.md`

**⚡ Rapid**
1. **Q:** How do KMS keys actually work for data at rest?
**A.** Envelope encryption: KMS generates a data key, encrypts the object with it, and stores the wrapped data key alongside; KMS itself never sees your data and only handles keys (so KMS limits are about key operations, not data volume).
2. **Q:** What are the KMS request limits and what happens when you exceed them?
**A.** Per-region quotas (e.g. ~5,500–10,000+ requests/s for symmetric ops, plus shared crypto throughput). You get `ThrottlingException` — which is why you use data keys/S3 bucket keys rather than calling KMS per object read.
3. **Q:** AWS-managed vs customer-managed keys?
**A.** AWS-managed (`aws/s3`, rotated yearly, key policy not editable) is easy but you can't control policy, grants, or cross-account usage. Customer-managed gives you key policy, rotation, cross-account access, and auditability — the right answer for regulated or multi-account workloads.
4. **Q:** What does key rotation do (and not do)?
**A.** Annual automatic rotation (or manual) creates new backing key material for the same key ID; old data stays decryptable. It does *not* re-encrypt existing data — that's a separate re-encrypt job if policy demands it.
5. **Q:** What is a key policy vs an IAM policy vs a grant?
**A.** The key policy is the root authority (must allow IAM/other accounts to manage the key at all); IAM policies grant principals access subject to that; grants give temporary/programmatic access, often used by AWS services. All three must line up — the classic "KMS access denied" triage.

**🔍 Deep dive**
6. **Q:** A cross-account S3 read fails with KMS AccessDenied. Debug it completely.
**A.** (1) Key policy must allow the external account/principal (`kms:Decrypt`, `DescribeKey`); (2) the caller's IAM must allow `kms:Decrypt`; (3) the bucket policy must allow the S3 object read; (4) the role must not also need `s3:GetObject` on the bucket with `aws:SourceVpce` or region conditions unmet; (5) for services, a grant may be required. Then check `ViaService` condition mismatches — the classic AWS-service-vs-direct-API discrepancy.
7. **Q:** How do you design an encryption strategy across a 60-account org?
**A.** Centralised key management account (or per-domain keys with cross-account grants), customer-managed keys per data classification/environment, CloudTrail data events for KMS (`Decrypt` monitoring), tag-based key policies, automated rotation, and SCPs preventing use of unapproved keys. Document who can decrypt what — that matrix is the actual deliverable.
8. **Q:** Encrypting S3: SSE-S3 vs SSE-KMS vs SSE-C vs client-side?
**A.** SSE-S3: AWS-managed key, no per-request KMS cost, no audit of decrypts. SSE-KMS: your key, CloudTrail audit, fine-grained control, per-object (or bucket-key-reduced) KMS calls. SSE-C: you manage keys entirely (no AWS storage of them) — rare. Client-side: you encrypt before upload (maximum control, most work). Compliance requirements decide.
9. **Q:** What is S3 Bucket Keys and why enable it?
**A.** It caches a short-lived bucket-level data key, cutting KMS requests (and cost) by up to ~99% while keeping KMS-based encryption and auditability. Default-enable it and drop a line about KMS throttling in the same breath.
10. **Q:** How do you protect against accidental key deletion / lockout?
**A.** Separate key-admin and key-user permissions, MFA-protected deletion where possible, don't schedule deletion without a documented approval, alarm on `ScheduleKeyDeletion`/`DisableKey`, and for maximum assurance use an external/HSM-backed key store (CloudHSM/XKS, key material you control — accepting that losing it means losing the data).
11. **Q:** Where do KMS keys not encrypt your data?
**A.** AWS-managed-service-side keys you don't control (some services use their own keys), fields the app handles unencrypted, secrets in environment variables/logs, and data in transit (that's TLS). Be precise: KMS covers encryption at rest for the services you configure, not "everything".

**🚨 War room**
12. **Q:** Your app is throwing KMS `ThrottlingException` at peak. Fix now and later.
**A.** Now: enable/verify S3 Bucket Keys, add exponential backoff with jitter on KMS calls, and reduce per-request decrypts via local caching of data keys with proper TTLs. Later: request a quota increase, shard KMS usage across multiple keys (per-tenant/per-shard), and re-architect to data-key-based envelope encryption (AWS Encryption SDK) so the hot path doesn't call KMS.
13. **Q:** Someone disabled the KMS key encrypting production EBS volumes. What happens?
**A.** Any volume/object encrypted with it becomes inaccessible (you cannot decrypt), effectively an outage — and EBS snapshots/attached volumes may fail. Recovery: re-enable the key (fast, if it wasn't deleted), then rotate and audit; if deletion was scheduled and completed, data is unrecoverable. Hence the alarms and separation of duties.
14. **Q:** An auditor asks "prove nobody decrypted customer data last month". Can you?
**A.** Only if CloudTrail data events for KMS are enabled and shipped to the immutable log archive, with an Athena query by key ID/principal. If they're not enabled, the honest answer is "we don't have that evidence — here's the change to enable it", plus compensating controls.
15. **Q:** After migrating an S3 bucket to a new key, some objects 403 in backup restores.
**A.** Objects encrypted with the *old* key can't be read under the new key policy/permissions; you need the old key still enabled and grants intact during transition. Best practice: keep old keys enabled and audited for the retention period, or re-encrypt objects before retiring the key.

**⚖️ Trade-off**
16. **Q:** One key for everything vs per-service/per-tenant keys?
**A.** One key simplifies management but creates a single blast radius and no per-tenant isolation; per-domain keys give isolation and clearer audit but more policy surface and more throttling headroom to manage. Typical: per environment + per data classification, with per-tenant keys only for strong isolation requirements.
17. **Q:** KMS vs CloudHSM vs external key store?
**A.** KMS for ~everything (managed, integrated, cheap). CloudHSM when a control requires dedicated HSMs/FIPS-validated single-tenant hardware or custom crypto. XKS when regulation demands your keys never leave your infrastructure (with real availability trade-offs).
18. **Q:** Encryption at rest with KMS — is data safe from your own admins?
**A.** Only if key access is separated from data access. If the same admin can use the key and read the bucket, KMS is an audit control, not an access boundary. Say that — it's the difference between checkbox encryption and real data protection.

**🎯 Senior**
19. **Q:** Design encryption and key management for a multi-tenant SaaS on AWS.
**A.** Per-tenant data keys via envelope encryption (AWS Encryption SDK), KMS customer-managed keys per tenant tier (or per tenant for gold tier), tenant keys provisioned by a control-plane service with automatic rotation, decrypts logged via CloudTrail data events, break-glass key access with MFA + approval + alarms, and a documented crypto-shredding path (delete the key = destroy the data) for GDPR erasure requests.

**🎯 Senior signal:** envelope encryption, S3 Bucket Keys for throttling/cost, and the "same admin = no real boundary" nuance are what a security-minded panel wants to hear.

---

## 7. Lambda — `lambda.md`

**⚡ Rapid**
1. **Q:** What is a cold start, roughly, and how do you reduce it?
**A.** New execution environment: initialise runtime + your code + SDK clients = tens of ms (Node/Python) to seconds (JVM/.NET or heavy VPC/init). Reduce with provisioned concurrency (paid), snapStart (Java), lighter dependencies, lazy init of SDK clients outside the handler, and smaller packages.
2. **Q:** What's the timeout and memory limit?
**A.** 15-minute timeout, 128 MB–10 GB memory (CPU scales with memory), 512 MB–10 GB ephemeral `/tmp`, 250 MB unzipped deployment (or container images up to 10 GB). Know the 15-minute cap — it forces async patterns.
3. **Q:** How does concurrency work, and what causes throttling?
**A.** Default 1,000 concurrent executions per region (shared across functions unless reserved concurrency is set). Beyond that you get `TooManyRequestsException` (429) — reserve concurrency per function so one function can't starve the account, and use SQS/EventBridge for buffering.
4. **Q:** How do you handle retries and idempotency?
**A.** Async invocations retry twice, then go to a DLQ/on-failure destination; SQS with partial batch failures; app-level idempotency keys for anything that mutates state. Assume at-least-once delivery, always.
5. **Q:** When is VPC-attached Lambda a mistake?
**A.** When it doesn't need private resources — VPC lambdas (post-Hyperplane) still consume ENIs/IPs and had a bad historical reputation; more importantly, if it's VPC-attached but needs internet access, it needs a NAT gateway (cost) or endpoints. Decide deliberately.

**🔍 Deep dive**
6. **Q:** Design an event-driven order pipeline with Lambda.
**A.** API Gateway → write to DynamoDB (with idempotency) → Streams → Lambda for projections → SNS for fan-out → SQS per consumer for retries/DLQs → EventBridge for cross-service events; each consumer idempotent, with alarms per stage on DLQ depth, error rate, and iterator age. Mention ordering (Kinesis/SQS FIFO by partition key) if the domain needs it.
7. **Q:** Lambda + RDS: how do you avoid killing the database?
**A.** RDS Proxy (multiplexes thousands of "connections" into a small pool), reserved concurrency to cap simultaneity, short pool sizes per lambda, and timeouts/backoff. Without this, a burst of lambdas opens hundreds of connections and the DB falls over — a very common real incident.
8. **Q:** How do you handle a 20-minute job that must run in Lambda-based architecture?
**A.** Break it into steps: Step Functions with a Lambda per step, checkpointing and state in DynamoDB, or hand the long part to ECS/Batch/Glue. Never try to stretch the 15-minute limit with hacks.
9. **Q:** What are reserved vs provisioned concurrency, and when do you use each?
**A.** Reserved = a concurrency ceiling AND guarantee (and it throttles beyond it) — use to protect downstreams and guarantee capacity for critical paths. Provisioned = pre-initialised environments to eliminate cold starts and cap latency — use for latency-sensitive functions, in combination with a reserved limit to control cost.
10. **Q:** How do you do "unit tests + observability" for lambdas?
**A.** Powertools-style structured logging with correlation IDs, X-Ray/OTel tracing with context propagation, metrics via EMF, alarm on `Errors`, `Throttles`, `Duration` p99, iterator age, and DLQ depth; local testing via SAM/containers or unit tests with mocked AWS SDK v3 clients. Observability is harder in serverless, so make it explicit.
11. **Q:** Lambda packaging: zip vs container image, and monorepo implications?
**A.** Zip for small, fast cold starts (keep dependencies minimal, tree-shake, use Lambda layers carefully — layers can add cold-start cost/size). Container images for large/consistent toolchains or GPU-less custom runtimes (up to 10 GB). For monorepos, build and deploy per function, not one giant package.

**🚨 War room**
12. **Q:** Lambda is throttling at peak and users get 429s. Fix now and properly.
**A.** Now: check whether it's account-level concurrency (other functions consuming it) or reserved-concurrency limits; raise/remove the cap on the critical function, and add buffering (SQS) in front so bursts are absorbed. Properly: reserve concurrency per critical function, use SQS/async patterns with DLQs, scale downstreams (RDS Proxy), and load-test to set the limits deliberately.
13. **Q:** DLQ is filling with order-processing failures. How do you handle it?
**A.** Sample the messages + correlate logs/trace IDs to find the failure class (dependency timeout, schema change, poison message), pause consumption if needed to protect downstreams, fix the handler, then replay from the DLQ with a controlled, idempotent reprocessor. Also add an alarm on DLQ depth so it's never a surprise again.
14. **Q:** Function latency is fine but `p99` is 8 seconds. Why?
**A.** Cold starts (check for init duration spikes + concurrency patterns), VPC ENI setup, a downstream dependency's p99 (usually the real cause — trace it), SDK retries masking errors, or memory-starved CPU (increase memory to get more vCPU). Compare cold vs warm and external vs internal time.
15. **Q:** After a dependency outage, Lambda retries created a thundering herd and cost spike. Prevent it.
**A.** Exponential backoff with jitter in the SDK/code, circuit breakers on the dependency, SQS buffering with a dead-letter path, reserved concurrency as a rate limiter, and alarms/cost budgets on invocation counts. Retries without backoff are a self-inflicted DDoS.
16. **Q:** A function has 3 GB of `/tmp` used for downloads and now fails intermittently. Diagnose and fix.
**A.** `/tmp` is per-execution-environment and not guaranteed to persist or be empty (concurrent invocations reuse environments). Fix: use S3 for artefacts, unique file names, stream instead of download, clean up, or move the workload to ECS/Step Functions. Relying on `/tmp` state between invocations is a classic serverless bug.

**⚖️ Trade-off**
17. **Q:** Lambda vs ECS/Fargate vs EKS for a new service?
**A.** Lambda for event-driven/spiky/low-ops and short tasks; Fargate for long-running services or steady load where per-request pricing is worse; EKS when you need the K8s ecosystem and have platform staff. Also consider team skills and the cost of operational ownership, not just the bill.
18. **Q:** Serverless means less to manage — agree?
**A.** Partially. You trade server ops for distributed-systems ops: concurrency limits, cold starts, event ordering, idempotency, per-service observability, and harder local testing. Say this; it differentiates the person who's run serverless at scale from the one who's read the marketing.
19. **Q:** Monolith Lambda (fat function) vs many small functions?
**A.** Small functions isolate failures/scaling but multiply IAM, deploys, and cold-start surface; a slightly larger "lambda-lith" per bounded context is often the pragmatic middle. Optimise for deployability and ownership boundaries, not function count.
20. **Q:** Reserved concurrency on everything — safe?
**A.** It's a cap; over-reserving wastes account concurrency and can starve other functions, under-reserving throttles your own. Reserve for critical paths and downstream protection, then monitor `Throttles` and adjust.

**🎯 Senior**
21. **Q:** You're asked to cut Lambda spend by 30% with no latency regression.
**A.** Right-size memory using Lambda Power Tuning (memory/CPU trade-off — often cheaper *and* faster at higher memory), remove pointless invocations (polling → events), batch SQS/Kinesis records (bigger batches = fewer invocations), cut log volume (CloudWatch Logs is often the hidden cost), use Graviton (arm64, ~20% cheaper), and delete zombie functions/schedules.

**🎯 Senior signal:** RDS Proxy for connection storms, reserved concurrency for downstream protection, idempotency by default, and "you trade server ops for distributed-systems ops" — that's senior serverless.

---

## 8. Route 53 — `route-53.md`

**⚡ Rapid**
1. **Q:** Failover vs weighted vs latency vs geoproximity?
**A.** Failover: active-passive with health checks. Weighted: gradual/canary traffic shifting. Latency: route to the lowest-latency region for the user. Geoproximity: bias by geography with a `bias` value — better control than plain latency. Multivalue: multiple healthy records returned for client-side failover.
2. **Q:** Does DNS failover happen instantly?
**A.** No — it's bounded by the record's TTL and client resolver behaviour. Keep TTLs low (30–60 s) for failover records, and don't rely on DNS alone for sub-second failover (that's Global Accelerator/anycast territory).
3. **Q:** What is an alias record and why prefer it?
**A.** An A/AAAA alias to an AWS resource (ALB, CloudFront, S3) — resolves to AWS-managed IPs, free of charge for queries, and follows the resource if its IPs change. Use alias, not CNAME, for AWS endpoints.
4. **Q:** What's the difference between a public and private hosted zone?
**A.** Public zones answer internet queries; private zones are attached to VPCs and answer internal names — and can be associated across accounts/VPcs (that's how internal service discovery works).
5. **Q:** How do health checks work with private resources?
**A.** Health checks run from AWS's public network, so they can't reach private endpoints directly — use a CloudWatch alarm-driven health check, or a public "canary" that reflects the private service's health.

**🔍 Deep dive**
6. **Q:** Design multi-region active-active DNS with fast failover.
**A.** Latency/geoproximity records per region with health checks, low TTLs (30–60 s), app-level readiness that makes a region's health check fail fast when it's degraded, DNS plus Global Accelerator (for instant path failover), data replication with documented consistency/RPO, and periodic failover game days to validate the whole chain. Mention that DNS caching in ISPs/JVMs is the usual suspect when "failover didn't work".
7. **Q:** A failover didn't trigger during an incident. Debug.
**A.** Health check was checking a URL that stayed healthy (e.g. served by a CDN or LB that returned 200 while the app was broken), the check ran from the wrong region(s), the record wasn't actually failover type, TTL/caching pinned clients, or the standby wasn't healthy so nothing to fail to. Triage each in that order — it's nearly always a bad health check definition.
8. **Q:** How do you migrate a domain into Route 53 with zero downtime?
**A.** Create the zone in Route 53 with identical records first, verify with the Route 53 name servers via `dig @ns` queries, then change the registrar's NS delegation (it propagates gradually), keep the old zone live until TTLs expire, and monitor query logs. Never flip NS and records at once.
9. **Q:** How do you do internal DNS with hybrid (on-prem + AWS) resolution?
**A.** Route 53 Resolver inbound endpoints (on-prem → AWS), outbound endpoints + forwarding rules (AWS → on-prem), and a forwarding rule for on-prem domains with a failover target. Also make sure your private zones are associated with the right VPCs — hybrid DNS is where "it resolves in one VPC but not another" comes from.
10. **Q:** What are the routing-policy limits/traps in a big setup?
**A.** 100 records per hosted zone won't apply, but you have limits on alias targets, health checks (and their cost), record sets per zone, and query pricing. Reusable delegation sets and zones-per-account limits matter in large orgs — plan the zone structure (central vs per-account registration zones).
11. **Q:** How do you deal with a DDoS on your DNS layer?
**A.** Route 53 is anycast and highly resilient; use Shield Advanced (which covers Route 53), keep tight record TTLs and clean record sets, avoid expensive/misconfigured setups (e.g. excessive health checks), and monitor query volume anomalies. Also consider whether your *registrar* and authoritative setup are exposed.

**🚨 War room**
12. **Q:** A typo in a record took the site offline for 20 minutes. Fix the process.
**A.** Immediate revert (records are versioned in IaC — `terraform apply` of the previous state), then prevent: Route 53 changes only via PR-reviewed IaC, staged in a test zone, with automated post-change validation (synthetic checks for the exact record), and a short TTL so rollback is fast. Manual console DNS edits in production should be forbidden outright.
13. **Q:** Users in one country can't resolve your domain; globally it's fine.
**A.** A geo-based routing policy or geoproximity bias change, a resolver/ISP-level cache issue, a DNSSEC/validation problem for that resolver, or a delegation/NS mismatch for a regional subdomain. Test with public resolvers in that region (`dig @8.8.8.8`, plus regional tools) and check recent policy/record changes.
14. **Q:** Your zone was deleted (or records vanished). Recovery?
**A.** Restore from IaC immediately (best case), otherwise from a zone export/backup — this is why you keep a versioned export of the zone and alert on hosted-zone deletion. Registrar NS records are usually still fine, so restoring the records brings the name back as soon as the previous TTLs expire.
15. **Q:** Latency-based routing sends everyone to one region, which then gets overloaded.
**A.** Latency routing doesn't balance load — it optimises per-user latency and can concentrate traffic if one region is "closest" to a huge population. Fix with weighted records across regions, capacity-aware steering (see CloudFront/GA), or Global Accelerator endpoint dials. Good senior insight: DNS steering is not load balancing.

**⚖️ Trade-off**
16. **Q:** Route 53 failover vs Global Accelerator for DR?
**A.** DNS failover is cheap and works for minutes-scale RTOs but is TTL/cache bound; GA gives static IPs and seconds-scale path failover at higher cost. Real-time paying services → GA; internal/less latency-critical → Route 53.
17. **Q:** Multivalue vs latency routing?
**A.** Multivalue returns several healthy IPs for client-side selection (simple HA/reliability, no latency awareness); latency routes users to the fastest region (performance, not load distribution). Different goals — don't confuse them in a design answer.
18. **Q:** Where should zones live in a multi-account org?
**A.** A dedicated DNS/network account owning public zones (registered domains centralised), with private zones per workload account associated to their VPCs; use reusable delegation sets and strict IAM. Decentralised public zones cause collisions and orphaned records nobody owns.

**🎯 Senior**
19. **Q:** How do you validate that DR actually works before you need it?
**A.** Scheduled failover game days: force the health check to fail in a controlled window, measure detection + propagation + client recovery time, verify data RPO, then write down what broke (usually caching, hardcoded endpoints, or an unmonitored standby). Automate the failover and record the runbook.

**🎯 Senior signal:** "DNS failover is bounded by TTL and resolver caching, and DNS is not load balancing" — those two statements immediately tell a panel you've operated multi-region systems.

---

## 9. Secrets Manager — `secrets-manager.md`

**⚡ Rapid**
1. **Q:** Secrets Manager vs SSM Parameter Store?
**A.** Secrets Manager: rotation (native for RDS/Redshift/DocumentDB + custom Lambdas), replication, versioning, per-secret resource policies, cost per secret. Parameter Store: cheaper (free tier), good for config and simple secrets, no native rotation. Rotation requirement decides.
2. **Q:** How do you rotate a database password without downtime?
**A.** Secrets Manager's alternating `AWSCURRENT`/`AWSPREVIOUS` versions + a rotation Lambda: it creates a new password, updates the DB user, then the secret; consumers fetch latest and handle the transition window. Multi-user rotation is the pattern that avoids downtime.
3. **Q:** Where should apps *not* get secrets from?
**A.** Environment variables baked at deploy, config files in images, code, or `.env` in Git. Fetch at runtime via SDK, referencing the secret ARN as config.
4. **Q:** How do you control who can read a secret?
**A.** IAM identity policies + optional resource policy on the secret, scoped to specific principals (preferably role-based, not users), and KMS key permissions (the secret's CMK). KMS is the second lock people forget.
5. **Q:** What does caching cost you?
**A.** SDK caching (Secrets Manager caching library) reduces API calls/cost/latency but means a rotated secret may be briefly stale — set `max_cache_size` and a TTL aligned with your rotation window.

**🔍 Deep dive**
6. **Q:** Design secret management for 50 microservices and 200 secrets.
**A.** Naming/tagging convention (`app/env/type`), per-app IAM policy patterns generated from tags (ABAC) rather than 200 bespoke policies, rotation where supported, secrets referenced by ARN in IaC (not values), centralised CloudTrail data-event auditing of `GetSecretValue`, replication for multi-region, and a break-glass read path with alarms. Values never live in Git or in Terraform state.
7. **Q:** How do you keep secrets out of Terraform state?
**A.** Don't manage the *value* in Terraform. Create the secret with a placeholder (or use `ignore_changes` on `secret_string`), and let rotation/a bootstrap step set the value. Where you must, use ephemeral/write-only arguments, mark sensitive, and protect state (encrypted backend, restricted access, no local state).
8. **Q:** What's the DB-connection-string vs credentials trade-off in the app?
**A.** Store host/port/database as *config* (Parameter Store), credentials as *secrets*; the app composes the connection string at runtime. This makes environment promotion trivial (same secret ARN pattern, different values) and avoids storing connection strings with embedded passwords.
9. **Q:** How do you detect and respond to secret leakage?
**A.** Controls: `git-secrets`/gitleaks + GitHub push protection in CI, CloudTrail alarms on unexpected `GetSecretValue` callers, and periodic scans of repos/S3/logs for patterns. Response: rotate immediately (never just delete the repo file), check usage in CloudTrail, and assume it was used.
10. **Q:** How do you handle secrets for third-party SaaS vendors (API keys you can't rotate programmatically)?
**A.** Store in Secrets Manager with a documented manual rotation runbook and a calendar reminder (or tickets), monitor for exposure, and prefer OAuth/short-lived tokens where vendors support them. Say out loud that unrotatable keys are the risk that vendors, not tooling, constrain.
11. **Q:** Custom rotation Lambda — what does it actually do?
**A.** Implements four steps: `createSecret` (generate new value + set as `AWSPENDING`), `setSecret` (update the target system — DB/API), `testSecret` (verify the new credential works), `finishSecret` (promote `AWSPENDING` to `AWSCURRENT`). Errors at each stage are logged and retried/alarmed — and it must be idempotent.

**🚨 War room**
12. **Q:** Rotation broke production: the app can't connect after the password changed.
**A.** Almost always one of: the app cached the old credential and didn't refresh (fix the caching TTL/fetch-on-failure path), the rotation Lambda updated the DB but not the secret (or vice versa) leaving them out of sync, a second user/consumer wasn't updated (multi-user rotation handles this), or the DB user was reused by a job reading env vars from deploy time. Immediate fix is `AWSPREVIOUS` if it still works; then correct the pattern.
13. **Q:** A secret was committed to a public repo 3 weeks ago. Act.
**A.** Treat as compromised: rotate now, search CloudTrail for `GetSecretValue` and any API activity by the exposed credential, assess the blast radius (what could it reach?), check for downstream data access, then fix the pipeline (secret scanning + push protection, pre-commit hooks) and do a short blameless review. Never just delete the commit.
14. **Q:** `AccessDenied` on GetSecretValue for a Lambda that used to work.
**A.** Check: the KMS key policy/grants (did the key rotate/policy change?), the IAM policy (was the secret ARN updated after a re-create with a new suffix?), region mismatch (secret in a different region), resource policy on the secret, and VPC endpoint policy if fetching through a VPC endpoint. The secret ARN's random suffix is a very common cause after recreation.
15. **Q:** Someone deleted a production secret. Recovery?
**A.** Secrets have a recovery window (7–30 days) — restore it (`restore-secret`). If it's past that or was force-deleted, you must recreate the secret and rotate the underlying credential (assume the value is gone). Prevention: deletion protection isn't free here — use resource policies and alarms on `DeleteSecret`.
16. **Q:** A third-party integration started logging the secret value in its debug logs. Response?
**A.** Stop the log pipeline (disable verbose logging at the integration), rotate the secret immediately, purge exposed logs per policy (S3 lifecycle + restricted access may not be enough — the value is compromised regardless), then restrict which systems can read the secret so an integration can't log it in the first place.

**⚖️ Trade-off**
17. **Q:** Secrets Manager vs Parameter Store (SecureString) — cost vs capability?
**A.** Parameter Store is ~free at low volume with no rotation; Secrets Manager costs per secret + API calls but gives rotation, replication, and resource policies. A hybrid is common: config and low-risk values in Parameter Store, true credentials in Secrets Manager.
18. **Q:** Centralise all secrets in one account vs per-workload account?
**A.** Central account gives one audit point and uniform policy but creates a high-value target and cross-account access complexity; per-workload keeps blast radius small and ownership clear. Most regulated setups: per-workload (or per-domain), with a central audit pipeline.
19. **Q:** Rotate every 30 days by policy, or risk-based?
**A.** Rotation cadence should follow risk and blast radius (short for high-privilege, longer for low-risk) — but never leave secrets unrotated for years. Automate what you can; document the rest; monitor for age. Compliance often fixes a cadence — then meet it with automation, not tickets.

**🎯 Senior**
20. **Q:** How would you build a secrets platform for a regulated org?
**A.** Mandatory Secrets Manager with CMK per domain, rotation enforced (native where possible, custom Lambdas otherwise), values injected only at runtime via SDK/IRSA, no secret values in IaC state, CloudTrail data events on all `GetSecretValue`, KMS-grant-based break-glass with approval and alarms, leak detection in CI + runtime, quarterly access reviews, and a self-service "rotate now" path so developers never store anything outside the platform.

**🎯 Senior signal:** knowing the rotation Lambda's four steps, the `AWSPENDING`/`AWSCURRENT` promotion, and "we never put secret values in Terraform state" is what a DevSecOps panel is testing for.

---

## 10. SNS — `sns.md`

**⚡ Rapid**
1. **Q:** What delivery protocols does SNS support?
**A.** SQS, Lambda, HTTP/S, email, SMS, and push (mobile). Plus SNS FIFO topics → SQS FIFO queues for ordered, deduplicated fan-out.
2. **Q:** Standard vs FIFO topic?
**A.** Standard: at-least-once, best-effort ordering, huge throughput. FIFO: strict per-message-group ordering with dedup IDs, lower throughput, and only SQS FIFO subscribers. Choose by whether ordering matters to the domain.
3. **Q:** How do you handle failures in delivery?
**A.** Each subscription can have a dead-letter queue on delivery policy failures/retries; configure retry policies and DLQs per protocol (HTTP endpoints especially). Without a DLQ you lose failures silently.
4. **Q:** What is raw message delivery?
**A.** For SQS subscriptions, it forwards the payload directly (with message attributes) instead of wrapping it in the SNS envelope — simpler consumers, cleaner schemas.
5. **Q:** Message size limit?
**A.** 256 KB, like SQS. Bigger payloads: store in S3 and send a reference (the claimed "extended client" pattern lives in the SDKs/libs, not the service).

**🔍 Deep dive**
6. **Q:** Design fan-out for an order event consumed by 6 services.
**A.** SNS topic (or EventBridge) → SQS queue per consumer (each with its own DLQ, retry policy, and scaling) → Lambda/ECS consumers. The queue-per-consumer is what gives independent retries and backpressure; SNS-direct-to-Lambda loses the buffer and makes retries brittle. Add idempotency keys since delivery is at-least-once.
7. **Q:** When SNS vs EventBridge vs SQS?
**A.** SNS: high-throughput pub/sub fan-out with multiple protocols. SQS: point-to-point work queue with buffering. EventBridge: event routing with content-based rules, schema registry, many SaaS/AWS sources, and archive/replay. Modern event-driven designs often use EventBridge for routing (richer matching) and SNS for massive fan-out or non-AWS targets.
8. **Q:** How do you secure an SNS topic?
**A.** Topic resource policy (which accounts/principals can publish/subscribe), encryption with KMS (SSE), SQS subscription policies allowing the topic (`aws:SourceArn` condition), and private access via VPC endpoints. `aws:SourceArn`/`aws:SourceAccount` conditions prevent the confused-deputy problem.
9. **Q:** How do you implement mobile push and email notifications reliably?
**A.** Separate topics/channels per use case, platform applications for push (APNs/FCM), SMS with spend limits and opt-out handling (compliance!), email/SES for production mail, and delivery-status logging for bounce/complaint handling. Also: don't send email from SNS in production — use SES with proper feedback loops.
10. **Q:** How do you handle the "subscription confirmed" flow for HTTP endpoints?
**A.** SNS sends a `SubscriptionConfirmation` you must confirm by calling the `SubscribeURL` (or use `auto confirm` with a Lambda). Monitoring must alert on unconfirmed subscriptions — a subtle production trap where notifications silently stop.

**🚨 War room**
11. **Q:** A downstream service didn't process events for 4 hours. How could that happen with SNS fan-out?
**A.** Its subscription's endpoint failed and messages went to the subscription DLQ (or were dropped if no DLQ), the SQS queue filled and its consumer was throttled/dead, or a policy change silently removed the subscription. Check subscription status, DLQ depth, queue depth, and the consumer's alarms — then replay from the DLQ and fix the missing alarm.
12. **Q:** A retry storm from a failing HTTP subscriber amplified traffic 10×.
**A.** SNS retries with a delivery policy; without backoff caps and a DLQ, a broken subscriber gets hammered and can take down neighbours. Fix the delivery policy (backoff function, max retries), enable the DLQ, and put SQS in front of HTTP consumers so retries are buffered and throttled.
13. **Q:** Duplicate SMS/push notifications to customers. Why?
**A.** At-least-once delivery plus a producer that retried on a timeout (message was actually published), or dedup missing on FIFO. Fix: producer-side idempotency (message dedup IDs/keys) and a notification service that de-duplicates before sending. Customer-visible duplicates are a reputation issue — treat it as a sev-2.
14. **Q:** Costs spiked on a topic that sends mostly to Lambda. Look at what?
**A.** Fan-out to SQS+Lambda invocations (each message = an invocation), unexpected high-volume publishers, no filtering so every subscriber gets every event, SMS/push costs, and retries. Fix with subscription filter policies (cut needless invocations), batching at the SQS+Lambda layer, and rate limits at publishers.

**⚖️ Trade-off**
15. **Q:** SNS fan-out vs direct API calls between services?
**A.** SNS decouples producers from consumers (independent deploys, resilience, fan-out) but loses request/response semantics, adds eventual consistency, and complicates debugging. Use async for events and sync for queries — and say why: "commands vs events".
16. **Q:** SNS+filter policies vs separate topics per event type?
**A.** One topic + filters reduces topic sprawl and subscriber management; separate topics give cleaner IAM boundaries and simpler reasoning per consumer. For a small set of related events, filters; for distinct security domains, separate topics.
17. **Q:** Is SNS the right tool for durable event sourcing?
**A.** No — no replay, no durable log, at-least-once with no ordering guarantee. Use Kinesis/EventBridge archive, Kafka/MSK, or a database-backed outbox pattern. Say this clearly; using SNS as a system of record is a common architecture mistake.
18. **Q:** SNS vs SES for email?
**A.** SNS for internal, low-volume ops alerts; SES for transactional/marketing email with templates, reputation management, bounce/complaint handling, and higher deliverability requirements. Mixing them up hurts deliverability.

**🎯 Senior**
19. **Q:** Design an event notification system for a platform with 30 publishers and 100 consumers.
**A.** EventBridge as the bus (schema registry, rule-based routing, archive/replay) with SNS topics only where massive fan-out or non-AWS protocols are needed, SQS per consumer for buffering + DLQs, idempotent consumers with dedup keys, a self-service subscription model with least-privilege topic policies, end-to-end trace IDs, and platform-level dashboards on DLQ depth, event age, and delivery failures.

**🎯 Senior signal:** "queue per consumer, never SNS straight to Lambda for critical work", `aws:SourceArn` conditions, and knowing SNS has no replay — three answers that mark an event-driven practitioner.

---

## 11. SQS — `sqs.md`

**⚡ Rapid**
1. **Q:** Standard vs FIFO?
**A.** Standard: at-least-once, best-effort ordering, virtually unlimited throughput. FIFO: exactly-once processing (with dedup) and strict ordering per message group, up to ~3,000 msg/s with batching (per-queue/per-region limits). Ordering requirements drive the choice.
2. **Q:** Key queue settings you always tune?
**A.** Visibility timeout ≥ processing time (and extended heartbeats for long jobs), `maxReceiveCount` before DLQ, redrive policy, long polling (`WaitTimeSeconds=20`) to cut empty receives, message retention, and encryption.
3. **Q:** Why is long polling important?
**A.** Short polling returns immediately with empty responses — you pay for empty receives and hammer the API. Long polling waits up to 20 s and reduces cost+latency. It's a cheap signal of real experience.
4. **Q:** When does a message go to the DLQ?
**A.** After `maxReceiveCount` failed receives (redrive policy). It must be monitored and replayed; a DLQ nobody watches is a silent data-loss path.
5. **Q:** What's the max message size, and how do you send something bigger?
**A.** 256 KB — store the payload in S3 and send a pointer (the "claim check" pattern), or compress.

**🔍 Deep dive**
6. **Q:** Design a reliable job queue with retries, DLQ, and scaling.
**A.** Producer → standard/FIFO queue with redrive to a DLQ, consumers with idempotent handlers (dedup table in DynamoDB), visibility timeout > p99 processing time with `ChangeMessageVisibility` heartbeats, autoscaling on `ApproximateNumberOfMessagesVisible` per consumer (backlog-per-instance), DLQ alarms + a replay tool, and CloudWatch on age-of-oldest-message (the metric that actually predicts SLA breaches).
7. **Q:** Explain visibility timeout and the classic bug it causes.
**A.** A message is hidden while a consumer processes it; if the consumer takes longer than the timeout, the message becomes visible again and a second consumer processes it → duplicate work and possible double side effects. Fix: longer timeout, heartbeats, and idempotent handlers. Interviewers love this one.
8. **Q:** How do you scale consumers on queue depth?
**A.** Target tracking on a custom metric (visible messages ÷ instances, i.e. backlog per instance) — not raw queue depth, which tells you nothing about per-consumer load. Use `ApproximateNumberOfMessagesVisible` and `ApproximateAgeOfOldestMessage` for SLO-based scaling and alerting.
9. **Q:** FIFO ordering — what actually guarantees it?
**A.** `MessageGroupId`: messages within a group are delivered in order to one consumer at a time; different groups process in parallel. Choose the group key (e.g. order ID, tenant) carefully — too coarse = no parallelism, too fine = no ordering guarantee for the entity.
10. **Q:** How do you protect downstream systems from a message flood?
**A.** Bounded consumer concurrency, queue-level backpressure, SQS buffering (that's the point), rate limiting in the consumer, and *not* auto-scaling blindly — sometimes you want the queue to grow and drain at a safe rate. Explicitly choose SLA-driven drain speed vs protection.
11. **Q:** How do you do poison-message analysis?
**A.** Inspect DLQ messages, group by error signature, correlate with a correlation ID in logs, then fix the handler or the payload contract; add schema validation/versioning at the producer so malformed messages fail fast. Keep DLQ messages long enough (retention) to analyse.

**🚨 War room**
12. **Q:** Queue depth is growing steadily and the business says jobs are hours late. Walk through it.
**A.** Compare arrival rate vs processing rate (message age is the KPI), check consumer health (throttles, errors, crashes), whether consumers are scaling (permission to scale? cap hit? scaling metric wrong?), downstream latency (DB/third-party), and poison messages clogging consumers. Immediate levers: raise consumer concurrency/capacity, temporarily batch more aggressively, move poison messages aside, and communicate the backlog ETA.
13. **Q:** The same job ran twice and charged a customer twice. Root cause and fix?
**A.** At-least-once delivery + a consumer without idempotency, often triggered by visibility timeout being shorter than processing time (or a Lambda timeout < visibility). Fix: idempotency key stored transactionally with the side effect, and set the visibility timeout > function timeout.
14. **Q:** Messages went to the DLQ after a downstream outage and nobody noticed for a day.
**A.** Missing alarms on `ApproximateNumberOfMessagesVisible` for the DLQ + no `ApproximateAgeOfOldestMessage` alarm on the main queue. Add both, plus a consumer error-rate alarm, and build a replay procedure (redrive from DLQ after fixing the cause). Also decide alert thresholds from business impact, not vibes.
15. **Q:** Lambda-based SQS consumer is fine at low load but throttles under bursts.
**A.** Lambda scales SQS consumers aggressively (up to hundreds/thousands of concurrent invocations) which can overwhelm the DB or hit account concurrency limits. Fix: reserved concurrency (a deliberate cap), batch size/window tuning, partial batch responses (`ReportBatchItemFailures`) so one bad message doesn't retry the whole batch, and RDS Proxy downstream.
16. **Q:** Some messages are never processed and never appear in the DLQ. How?
**A.** They're still in the queue being retried (check receive counts), were deleted by a buggy consumer, exceeded retention and expired (messages expire if not processed within the retention window — silently), or visibility/redrive policy isn't actually attached. Retention expiry with a big backlog is a real, easy-to-miss data-loss mode.

**⚖️ Trade-off**
17. **Q:** SQS vs Kinesis vs MSK?
**A.** SQS: work queues, per-message ack, no replay, scale on consumer count. Kinesis: ordered streams with replay, shards, multiple consumers at their own pace, higher cost/complexity. MSK/Kafka: full log semantics, ecosystem, retention and rewind, but you operate it. "Do consumers need to re-read or replay?" is the deciding question.
18. **Q:** FIFO everywhere for safety?
**A.** No — FIFO caps throughput, adds dedup config, and can create head-of-line blocking. Only use it where ordering is a business requirement (payments, state transitions), and use message groups so parallelism survives.
19. **Q:** Batch size vs latency?
**A.** Larger batches = fewer API calls/invocations and better throughput, but higher per-message latency and bigger blast radius for partial failures. Tune with `MaxNumberOfMessages`/`WaitTimeSeconds`/`BatchWindow`, and always implement partial batch failure handling.
20. **Q:** Should the DLQ have a DLQ?
**A.** Not literally, but it needs equivalent handling: an alarm, a documented triage/replay runbook with a retention policy, and — for critical flows — an automated pipeline that replays repaired messages. Unbounded DLQ growth is a backlog you've just renamed.

**🎯 Senior**
21. **Q:** How do you guarantee no message loss end to end for a critical flow?
**A.** Producer durability (transactional outbox or SQS in the same transaction semantics as the DB write where possible), queue encryption + retention aligned with worst-case downtime, consumer ack only after the side effect commits, DLQ + alarms + replay tooling, idempotency to survive duplicates, and a periodic reconciliation job that compares source of truth vs processed records. Say the reconciler — it catches everything else.

**🎯 Senior signal:** visibility-timeout duplication, backlog-per-instance scaling, partial batch failures in Lambda, and retention-expiry as a silent loss mode. Those four say "I've run queues at scale".

---

## 12. Systems Manager — `systems-manager.md`

**⚡ Rapid**
1. **Q:** What problem does Session Manager solve?
**A.** Shell access to instances without SSH keys, open ports, or a bastion — access goes through the SSM agent to AWS APIs, with IAM authorization, session logging, and full audit in CloudTrail. No inbound 22/3389 at all.
2. **Q:** What are the main SSM capabilities you actually use?
**A.** Session Manager (access), Run Command (fleet-wide execution), Patch Manager (baseline compliance), Parameter Store (config/secrets), State Manager (drift/associations), Automation (runbooks), Inventory (asset data), and Fleet Manager.
3. **Q:** What's required for an instance to be managed?
**A.** SSM agent installed/running, an instance profile with `AmazonSSMManagedInstanceCore`, network access to SSM endpoints (via public internet, interface endpoints, or a NAT), and a supported OS. Missing one → the instance shows as unmanaged, silently.
4. **Q:** Parameter Store Standard vs Advanced vs SecureString?
**A.** Standard: 4 KB, free tier. Advanced: 8 KB, policies, sharing, cost. SecureString: encrypted with KMS. Use SecureString for anything sensitive, Advanced for larger configs, and Secrets Manager for true secrets with rotation.
5. **Q:** How do you run a command across 500 instances safely?
**A.** Run Command with a tag-based target, `MaxConcurrency` and `MaxErrors` set conservatively (e.g. 10%/1%), rate control for staged rollout, output to S3/CloudWatch, and a rollback/stop mechanism. Never "all at once" in production.

**🔍 Deep dive**
6. **Q:** Design patching for 600 instances across 3 accounts.
**A.** Patch Manager baselines per OS/severity with scheduled windows via State Manager associations, tag-based groups (prod vs non-prod, OS), staged rollout with concurrency limits, a pre-patch snapshot where feasible, post-patch compliance reporting aggregated to a central account, exceptions/alarms for non-compliant nodes, and rollback via AMI/instance refresh for immutable fleets. Report compliance weekly; automate the mundane.
7. **Q:** How do you do secrets and config distribution at scale?
**A.** Parameter Store with hierarchy (`/app/env/db/host`), path-based IAM policies, versioning, and app-side caching (the Parameter Store caching library). Config as parameters, secrets in Secrets Manager/SecureString, and change notifications via EventBridge so apps can hot-reload instead of redeploying.
8. **Q:** How does Session Manager logging/auditing work?
**A.** Session preferences configure S3 (with KMS) and/or CloudWatch Logs destinations, and you can require encryption/allow KMS key choice and disable the "start session with no logging" option. CloudTrail records `StartSession`, and IAM policies can require specific tags (`ssm:SessionDocumentAccessCheck`/resource tags) to constrain who can reach which instances.
9. **Q:** How do you run maintenance/automation tasks without humans logging in?
**A.** SSM Automation documents (runbooks) triggered by EventBridge schedules or alarms: rotate credentials, snapshot/verify backups, restart services, remediate Config noncompliance, patch instances. Runbook steps use IAM roles and produce an execution history — that's your evidence.
10. **Q:** What breaks SSM connectivity, and how do you debug it?
**A.** Missing instance profile/`AmazonSSMManagedInstanceCore`, no route to `ssm.*.amazonaws.com` (and `ssmmessages.*`, `ec2messages.*`), NAT missing/endpoint policy too restrictive, agent stopped/crashed, clock skew breaking TLS, or a proxy/firewall blocking 443. Check agent logs (`/var/log/amazon/ssm/`), the instance's `PingStatus` in `describe-instance-information`, and the VPC endpoints available.
11. **Q:** How do you enforce that nobody uses SSH anymore?
**A.** Security groups with no 22/3389 ingress (org-wide via SCP/Config), no key pairs on instances, Session Manager as the only path, alarms on any SSH attempts (flow logs), and a short exception process with expiry. Then remove the bastion.

**🚨 War room**
12. **Q:** A Run Command patched 40 production nodes and broke the app. What now?
**A.** Stop the execution (SSM can stop in-flight commands), identify affected instances via the command's invocation results, roll back (restore snapshot/regenerate instances from the previous AMI/instance refresh), then fix the process: smaller concurrency, a canary group patched first with validation, maintenance window with a rollback plan, and app-level smoke tests before proceeding. Report the impact honestly.
13. **Q:** Session Manager stopped working for the whole fleet after a network change. Diagnose.
**A.** Check VPC endpoint policies/route tables for the three SSM endpoints, whether the centralised endpoint VPC is still reachable from the spokes, NACLs, and whether a security-group change removed endpoint access. There's also the classic: someone removed the instance profile's SSM policy, or changed the endpoint policy to allow only certain accounts/roles.
14. **Q:** Compliance flags 15% of instances as unpatched every month. Approach?
**A.** Break it down: unsupported OS versions/end-of-life, instances that are stopped (no agent heartbeat), instances whose baseline doesn't apply, patching windows missed due to long-running jobs, or genuinely failing patches. Then fix per class — for immutable fleets, rebuild with the patched AMI instead of patching in place.
15. **Q:** A contractor needs temporary access to 3 instances for 4 hours. How do you grant it, safely?
**A.** IAM (or Identity Center) permission set for Session Manager scoped by resource tags to exactly those instances, time-boxed via SSO session duration or an expiry-tagged group, session logging to S3/CloudWatch with key-holder separation, and an alarm on session start. Access reviewed automatically afterwards.

**⚖️ Trade-off**
16. **Q:** Patching in place vs immutable rebuild?
**A.** In-place is faster and fine for legacy/stateful; rebuild-from-AMI gives reproducibility, rollback, and no drift. For autoscaling fleets, rebuild is almost always the right answer; use Patch Manager for the stragglers and for instance types you can't rebuild yet.
17. **Q:** Session Manager vs bastion host vs VPN?
**A.** Session Manager: no inbound ports, per-session audit, IAM-controlled — the modern default. Bastion: legacy, needs hardening/HA, and still needs SSH keys. VPN: good for network-level access for many users/apps, heavier to manage for occasional shell access. Best answer: SSM for human access, VPN/DX for network paths.
18. **Q:** Parameter Store vs Secrets Manager vs config in Git?
**A.** Git for non-secret config that must be versioned/reviewed; Parameter Store for app config and simple values (per environment); Secrets Manager for credentials needing rotation. Mixing secrets into Git or general config into secrets both create problems.
19. **Q:** Automating remediation — how far do you go?
**A.** Auto-remediate deterministic, low-blast-radius findings (public S3 access, unencrypted volumes where possible, missing tags, stopped agents). Anything with data-loss or availability risk gets an alert + runbook + human. Explicitly state your boundary; unrestrained auto-remediation causes its own outages.

**🎯 Senior**
20. **Q:** You're asked to remove all standing SSH access from 800 instances and prove it. Plan?
**A.** Inventory access paths (SGs, key pairs, bastions, VPN rules), enable Session Manager everywhere (profile + endpoints + logging), pilot on one tier, remove 22/3389 ingress org-wide (SCP/Config enforcement), delete key pairs, decommission bastions, alert on any SSH attempt, document break-glass, and report: zero public admin ports, 100% session logging, and a compliance query as evidence.

**🎯 Senior signal:** Session Manager for access + no inbound SSH + automation documents as evidence + tagging-based IAM for who-can-reach-what. That's the platform/SRE answer.
