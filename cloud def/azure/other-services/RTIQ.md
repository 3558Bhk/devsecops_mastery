# RTIQ — Azure Other Services (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** AKS, Azure DevOps, Functions, Cosmos DB, Defender for Cloud, Key Vault, Logic Apps, Service Bus · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~61 min

**How this file is used live:** these are the services that appear in *design and incident* rounds. The interviewer's real question is "can you choose the right one and then defend it under failure, scale, and cost?". Have a story ready for each, and know at least one hard limit per service.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. AKS — `aks.md`

**⚡ Rapid**
1. **Q:** What does AKS manage for you, and what doesn't it?
**A.** Control plane (API server, etcd, patching, SLA — free tier without SLA) and node agent updates; you own node pool sizing, upgrades of the data plane, networking (CNI), ingress, security policy, and workload config.
2. **Q:** How do pods get Azure permissions?
**A.** Workload identity (federated identity credential to a user-assigned managed identity) or the older pod-managed identity/AAD pod identity. Never mount secrets or use the node identity for pods.
3. **Q:** Which CNI, and why does it matter?
**A.** Azure CNI (pods get VNet IPs — IP planning required) vs kubenet (nodes get VNet IPs, pods NAT'd — fewer IPs, more hops) vs Azure CNI Overlay (pods on a private overlay, conserving VNet address space, with Cilium for network policy). Modern default for large clusters: overlay + network policy.
4. **Q:** How do you do zero-downtime upgrades?
**A.** Plan a version path (can't skip minors), check deprecated APIs (`pluto`/`kubent`), upgrade the control plane then node pools with surge settings and drain, use PodDisruptionBudgets and readiness probes, and keep the previous node image for rollback. Rehearse in a non-prod cluster on the same version.
5. **Q:** What's a common cause of "pods stuck in Pending"?
**A.** Insufficient CPU/memory requests, node pool at max/taints+matching not satisfied, unschedulable nodes, PVC in another zone/region, or IP exhaustion with Azure CNI (per-node IP limits). `kubectl describe pod` events name the reason — check those first.
6. **Q:** How do you secure AKS?
**A.** Private API server endpoint, RBAC with Entra ID + Kubernetes local accounts disabled, workload identity for Azure access, Azure Policy for Kubernetes (PSP replacement)/OPA-Gatekeeper, network policies, Defender for Containers, image scanning + admission control, node OS patching + auto-upgrade channel, and audit logs to a central workspace.
7. **Q:** Cost levers?
**A.** Right-size node pools, use spot pools for interruptible work (with taints/tolerations), cluster autoscaler/KEDA, vertical and horizontal pod autoscaling, system/user pool separation, uptime SLA tier choice (free vs paid), and reviewing idle/over-requested workloads. Container Insights shows the over-request pattern.

**🔍 Deep dive**
8. **Q:** Design a multi-tenant AKS platform for 15 teams.
**A.** Separate node pools per workload class (system, general, memory-optimised, spot), namespaces per team with resource quotas/limit ranges, Entra ID groups → Kubernetes RBAC, network policies default-deny with explicit allows, Azure Policy guardrails (no privileged/hostPath, required labels/probes/limits), workload identity per app, GitOps (Flux/Argo CD) with a PR-based deploy path, ingress via App Gateway/AGIC or NGINX + Front Door, and per-namespace cost allocation via labels/Container Insights.
**↳ Follow-up:** "One team's pod saturates the cluster. How do you prevent that?"
**A.** ResourceQuota + LimitRange per namespace, requests=limits for critical pods, node-pool isolation for noisy workloads, priority classes for critical services, PDBs for safe eviction, and admission policies that reject pods without limits.
9. **Q:** How do you do autoscaling at three levels?
**A.** HPA (pod replicas on CPU/memory/custom metrics), KEDA/queue-driven (event sources like Service Bus queues), and cluster autoscaler/Karpenter-style node scaling. Order matters: pods must scale before nodes, and nodes must have headroom for surge — otherwise pods sit Pending while nodes provision.
10. **Q:** How do you handle secrets in AKS?
**A.** Prefer workload identity + Key Vault (CSI Secrets Store driver) so secrets aren't stored in etcd; if Kubernetes Secrets are used, enable etcd encryption with a Key Vault key (KMS plugin), restrict RBAC, and rotate. Never commit manifests with secrets.
11. **Q:** How do you debug a pod crash-looping in production?
**A.** `kubectl describe pod` (events/exit codes) → `logs --previous` → probe config (liveness too aggressive causing restart loops) → resource limits/OOMKilled → missing config/secrets or failing dependency at startup. Then check whether it's one pod or all (config vs infrastructure).
12. **Q:** How would you cut an AKS bill by 40%?
**A.** Measure requests vs usage via Container Insights/Kubecost, right-size requests (huge win), enable cluster autoscaler scale-down and Karpenter-style consolidation, use spot for stateless/batch, reduce over-provisioned system pools, remove idle dev clusters (schedule shutdown), tune observability ingestion (a hidden cost), and move rarely used workloads to Container Apps/Functions.
13. **Q:** How do you do ingress with WAF for AKS?
**A.** AGIC (Application Gateway Ingress Controller) or an internal NGINX behind App Gateway/Front Door; TLS via cert-manager/Key Vault; WAF at App Gateway or Front Door; network policies to restrict traffic to ingress; and health/readiness probes on the Service so the ingress doesn't route to unhealthy pods.

**🚨 War room**
14. **Q:** The cluster API server is unreachable and everyone's deploys are failing. What do you do?
**A.** Check Azure Service Health/region status, the control plane's diagnostic logs, whether the API server is throttled (a runaway controller/CI hammering it), and any recent private-endpoint/DNS changes. If it's a service incident, communicate and rely on running workloads (they continue); if it's throttling, stop the offending controller. Contain first, don't troubleshoot blind.
15. **Q:** After a node pool upgrade, 20% of pods stay Pending.
**A.** Nodes with insufficient allocatable capacity (bigger/cordoned pods), taints from the new pool not tolerated, PVC affinity to the old zone, or IP exhaustion on the new nodes with Azure CNI. Check pod events + node allocatable vs requests; fix with pool sizing/labels/taints or CNI overlay.
16. **Q:** A compromised container is running in production. Contain and investigate.
**A.** Isolate the node (cordon + network policy/quarantine), preserve evidence (pod spec, node disk snapshot, logs), identify how it got in (image with vulnerability, exposed service, compromised workload identity), then rotate the workload identity's credentials and any secrets it could read. Use Defender for Containers alerts for the scope, and rebuild nodes rather than "cleaning" them.
17. **Q:** Deployments are slow and CI times out waiting for rollout.
**A.** Image pull times (registry distance/size), aggressive probes with long initial delays, resource requests causing scheduling waits, PDB blocking evictions during rollout, or the ingress/ALB health check not matching the pod's readiness. Fix the slowest stage first — measure with `kubectl rollout status` timing and node events.
18. **Q:** DNS resolution fails intermittently inside the cluster.
**A.** CoreDNS scaling (too few replicas for query volume), the conntrack table on nodes, `ndots:5` causing excessive lookups, or CoreDNS pods being evicted/starved. Fix: scale CoreDNS with HPA, raise conntrack limits, add NodeLocal DNSCache, and tune search domains.
19. **Q:** Certificates for ingress expired and the site is down. Prevention?
**A.** Check cert-manager/Key Vault renewal and its issuer (DNS challenge failures are common), set expiry alerts 30/14/7 days out, monitor the cert in synthetic checks, and prefer Key Vault-issued certs with automatic renewal via the CSI driver. Then add an alert on `NotAfter` for all ingress certs as a fleet-wide control.

**⚖️ Trade-off**
20. **Q:** AKS vs Container Apps vs App Service vs Functions?
**A.** AKS for platform standardisation, the K8s ecosystem, and complex workloads (with a real ops cost). Container Apps for containers without cluster ops (KEDA scaling, Dapr). App Service for standard web/API workloads with least effort. Functions for event-driven/short tasks. Choose by team capability and operational budget, not by capability checklists.
21. **Q:** One big cluster vs many?
**A.** Bigger clusters amortise system pods and cost less, but widen blast radius and slow upgrades; many clusters isolate but multiply control planes, ingress, and monitoring. Segment by environment, region, and compliance boundary — not by team.
22. **Q:** Azure CNI vs Overlay?
**A.** Azure CNI gives pods VNet IPs (integrated with NSGs/UDRs, simple security model, but IP-hungry for large clusters); Overlay conserves VNet IP space and is better for large clusters and scale, at the cost of some direct-IP integration and different policy tooling (Cilium recommended).
23. **Q:** Spot node pools — when?
**A.** Stateless/batch/CI workloads that tolerate eviction, with taints/tolerations, PDBs, graceful shutdown handling, and diversity across VM sizes/zones. Not for stateful/single-replica services or anything with paid SLAs on latency.
24. **Q:** Should you run databases on AKS?
**A.** Generally no — managed Azure SQL/Cosmos/PostgreSQL/MySQL remove patching, backup, HA, and failover work you'd otherwise reinvent. Run them in Kubernetes only when portability/on-prem parity is a hard requirement and you accept the operational burden.
25. **Q:** Hub for platform services — one ingress controller per cluster or shared?
**A.** Per-cluster ingress is simpler and isolates blast radius; shared/centralised ingress saves cost and centralises WAF/TLS but becomes a shared failure domain and a change bottleneck. Common compromise: App Gateway per environment with Front Door as the global edge.

**🎯 Senior**
26. **Q:** What does production-ready mean for an AKS cluster?
**A.** Private API server + no local accounts, Entra-integrated RBAC with least privilege, workload identity everywhere, network policies default-deny, Azure Policy admission guardrails, node pools sized by workload class with autoscaling, auto-upgrade channel + maintenance windows + tested upgrades, image scanning/signing and registry restrictions, Container Insights + Prometheus metrics + audit logs centralised, backup/DR (Velero/BCDR) tested, and a documented runbook for the five common failure modes.

**🎯 Senior signal:** workload identity over pod identity, IP-exhaustion/CNI trade-offs, and "scale pods before nodes". That's the platform-engineer bar.

---

## 2. Azure DevOps — `azure-devops.md`

**⚡ Rapid**
1. **Q:** What are the parts of Azure DevOps?
**A.** Azure Repos (Git), Pipelines (YAML builds/releases), Boards (work tracking), Artifacts (packages), Test Plans — plus the supporting glue: service connections, environments, approvals, and self-hosted agents.
2. **Q:** How do you authenticate a pipeline to Azure without secrets?
**A.** Workload identity federation on the service connection (or a managed identity on the agent) — no PATs/client secrets, with a federated credential scoped by the pipeline. This is the expected modern answer.
3. **Q:** Build vs release pipeline (classic) vs multi-stage YAML?
**A.** Classic release pipelines are UI-driven and legacy; multi-stage YAML keeps everything in code with environments/approvals and is the standard. Say "YAML in the repo, environments and approvals for gates".
4. **Q:** Microsoft-hosted vs self-hosted agents?
**A.** Microsoft-hosted: zero maintenance, fresh VM per job, slower starts, limited private access (needs self-hosted or network integration for private resources). Self-hosted: access to VNets, caching, custom tooling, more cost/ops (and a security surface if shared with untrusted PRs).
5. **Q:** How do you handle environments and approvals?
**A.** Environments (with checks: approvals, business hours, exclusive lock, required template, branch control) gate deployments to prod; approvals can be assigned to groups. Combine with a manual validation step for high-risk changes.
6. **Q:** How do you manage secrets in pipelines?
**A.** Variable groups backed by Key Vault, secret variables/`$(secret)` marked secret (masked in logs — but not bulletproof), or better: workload identity to fetch at runtime. Never echo secrets, never store them in the repo, and rotate anything exposed by a debug log.
7. **Q:** What is a self-hosted agent security concern?
**A.** PRs from forks or untrusted branches running on the same agent can steal credentials/tokens present on the machine. Mitigate with dedicated agent pools per trust level, no PR-triggered jobs with secret access, and ephemeral/containerised agents. This is a favourite DevSecOps question.

**🔍 Deep dive**
8. **Q:** Design a CI/CD pipeline for a 20-team platform.
**A.** Reusable YAML templates (one repo of templates consumed via `extends`), a standard pipeline: lint → build → unit test → SAST/secret scan/image scan → publish artifact with provenance (SBOM, signed) → deploy to dev (auto) → staging (auto with tests) → prod (gated with approvals + progressive rollout). Environments with checks, workload identity service connections, per-team agent pools, branch policies with required reviewers on protected branches, and metrics: lead time, change-failure rate, MTTR, deploy frequency. Governance through templates + Policy, not manual reviews.
**↳ Follow-up:** "How do you stop a team from bypassing the security gates?"
**A.** Required templates (`extends` from a mandatory template) enforce the sequence — you can't skip the steps, only add to them; combined with branch policies, environment checks requiring the template, and Policy on the resources. Make the secure path the easy path.
9. **Q:** How do you do progressive delivery (canary/blue-green) in Azure DevOps?
**A.** Deploy to a canary slot/stage set with a percentage of traffic (App Service slots, VMSS/App Gateway weighted backends, or Kubernetes with Argo Rollouts/Flagger), run automated verification (synthetic + error-rate gates), then promote. Rollback is a slot swap or a weight reset — practice it.
10. **Q:** How do you handle multi-region deployments?
**A.** Parametrised stage templates per region, deploy to a primary/staging region first with validation, then fan out to remaining regions in parallel, with health gates between regions and the ability to halt. Keep configuration/environment parameters in variable groups or per-region parameter files, not duplicated YAML.
11. **Q:** What does pipeline observability look like?
**A.** Run duration/flakiness trends, failure reasons by stage, test flake rate, deployment success/lead time dashboards, and alerts on repeated failures of the default branch. Add deployment annotations to monitoring (release markers) so incidents can be tied to a build. "Deploys are visible events" is the standard.
12. **Q:** How do you make a pipeline fast?
**A.** Cache dependencies (npm/NuGet/pip/maven via Cache task), parallel jobs, incremental builds, reuse artifacts between stages (build once, deploy many), split long test suites (unit in PR, integration/e2e post-merge or nightly), and avoid reinstalling toolchains with a custom agent image. Measure stage durations before optimising — usually one test suite dominates.
13. **Q:** How do you do IaC in the pipeline safely?
**A.** `terraform plan`/`what-if` in the PR as an artifact + comment, approval on the apply stage, state locking and a single writer, environment-specific variable files/backends, drift detection on a schedule, and guardrails (Policy/policy-as-code scans on the plan output). Never apply from a laptop.

**🚨 War room**
14. **Q:** A pipeline leaked a secret into its logs. Response?
**A.** Rotate the secret immediately (it's compromised regardless of masking), purge/restrict the log where possible, audit who accessed the build and any downstream usage of the credential, then fix: use workload identity/Key Vault, remove the debug/echo, and enable a secret-scanning check on logs/build output. Treat it as an incident with a timeline.
15. **Q:** Deployments are failing with authorisation errors after a service connection change.
**A.** The federated credential subject or the service connection's role assignment changed (check the connection's permissions, the app registration's federated credentials, and whether the resource/subscription moved). Also verify the agent's network access for private endpoints and firewall rules (a common "it's auth" that's actually networking).
16. **Q:** A release deployed to prod without approval. How?
**A.** Environment checks were bypassed (wrong environment name, a pipeline without the required template, or a pipeline using a different service connection), or someone with permission edited the checks. Investigate via the pipeline's audit logs, then enforce: required templates, exclusive locks, approval groups independent of the deploying team, and alerts on environment-permission changes.
17. **Q:** Builds are queued for an hour during peak. Fix.
**A.** Agent capacity (add self-hosted agents or more parallel jobs), long-running tests saturating the pool, or a stuck job holding an exclusive lock. Separate PR-validation pools from release pools, set job timeouts, and autoscale self-hosted agents (VMSS agents) so capacity follows demand.
18. **Q:** A third-party dependency was compromised and your build pulled the malicious version. Response and prevention.
**A.** Identify affected builds/artifacts (dependency lock files + SBOM), rebuild from a known-good pinned version, redeploy anything shipped, and rotate any credentials the pipeline had access to. Prevention: pin versions with lock files/hashes, use a private package feed (Artifacts) with allow-listing, scan dependencies, and sign/verify artifacts with provenance.

**⚖️ Trade-off**
19. **Q:** Azure DevOps vs GitHub Actions?
**A.** Azure DevOps integrates deeply with Azure (environments/approvals, service connections, Boards) and suits large enterprise governance; GitHub Actions has a bigger ecosystem, better developer UX, and OIDC-native Azure deployment. Many organisations run both (Azure DevOps for legacy/enterprise, GitHub for new) — be opinionated but pragmatic.
20. **Q:** Microsoft-hosted vs self-hosted agents?
**A.** Microsoft-hosted for simplicity/security with public builds; self-hosted when you need private network access, caching, custom tooling, or cost control at scale — accepting patch/security responsibility. Hybrid: hosted for PR validation, self-hosted for deployment stages with network access.
21. **Q:** One big release pipeline vs many small ones?
**A.** Many small pipelines per service give ownership, faster feedback, and smaller blast radius; one monolith pipeline is easier to enforce but becomes a bottleneck and a single point of failure. Standard: templates (shared) + one pipeline per deployable unit (owned).
22. **Q:** Trunk-based vs GitFlow?
**A.** Trunk-based with short-lived branches and feature flags gives fast feedback and smaller changes — the right default for CD. GitFlow's long-lived branches delay integration and create merge pain; keep release branches only where you genuinely need to patch older versions.
23. **Q:** Gates (approvals) everywhere vs automate the checks?
**A.** Approvals are humans as a control; automated gates (tests, scans, SLO checks, canary analysis) scale and are consistent. Use approvals where judgement/accountability matters (prod, destructive changes) and automate everything else; an approval that people rubber-stamp is worse than a real check.

**🎯 Senior**
24. **Q:** How would you measure and improve delivery performance?
**A.** DORA metrics per team (lead time, deploy frequency, change failure rate, MTTR), plus pipeline reliability/flake rate. Improve by: reducing batch size, catching failures earlier (fail fast in PR), making deploys boring (automation + progressive rollout), improving observability for MTTR, and removing handoffs. Publish trends, not vanity numbers.

**🎯 Senior signal:** workload identity federation over secrets, required templates to make the secure path mandatory, and DORA-based measurement. That's platform/DevOps leadership.

---

## 3. Azure Functions — `azure-functions.md`

**⚡ Rapid**
1. **Q:** Hosting plans?
**A.** Consumption (scale to zero, per-execution, cold starts, 5/10-min timeout default), Flex Consumption (modern, faster scaling, VNet, instance sizes), Premium (pre-warmed instances, VNet, longer timeouts, no cold start), Dedicated/App Service plan (predictable, always-on, container-friendly). Choose by latency tolerance and network requirements.
2. **Q:** What triggers/bindings do you use most?
**A.** HTTP, Timer, Service Bus/Event Hub/Event Grid, Blob/Queue/Storage, Cosmos DB change feed. Bindings remove boilerplate — but over-using them couples the function to the platform, so keep business logic separate.
3. **Q:** How do you avoid duplicates and retries causing double work?
**A.** Idempotent handlers with an idempotency key, Service Bus with dedup/sessions where needed, Poison queue/DLQ handling, and `maxAutoRenewDuration`/lock settings matched to execution time. Assume at-least-once.
4. **Q:** Where do secrets live?
**A.** Managed identity + Key Vault references (app settings like `@Microsoft.KeyVault(...)`), never in `local.settings.json` or source. Use identity-based connections for storage/service bus where available.
5. **Q:** How do you call Azure services from a function?
**A.** Managed identity + SDK with identity-based connections (best), or connection strings in app settings via Key Vault. Prefer the identity path so nothing rotates by hand.
6. **Q:** What is Durable Functions for?
**A.** Long-running/stateful orchestrations (chaining, fan-out/fan-in, human interaction, timers) using an orchestration/activity pattern with automatic state persistence. For very long or high-throughput workflows consider Logic Apps/Service Bus + containers.
7. **Q:** Cold start — how bad and how do you handle it?
**A.** Hundreds of ms to seconds depending on runtime, dependency size, and VNet integration. Mitigations: Premium plan (pre-warmed), fewer/lighter dependencies, avoid VNet integration on latency-critical paths if possible (or use Flex with VNet), and keep initialisation lazy.

**🔍 Deep dive**
8. **Q:** Design an event-driven order pipeline with Functions.
**A.** Orders → Service Bus topic/queue (with sessions per order for ordering) → Functions consumers with idempotency store (Cosmos/Redis) and DLQ → Cosmos DB/SQL for state → Event Grid for downstream notifications → Application Insights with correlation IDs into queues (W3C trace context propagation). Throttle downstream with `maxConcurrentCalls`/prefetch settings and monitor DLQ depth + e2e lag.
9. **Q:** A function is scaling out of control and hammering downstream. Fix.
**A.** Set `maxConcurrentCalls`/`maxConcurrentSessions` on the Service Bus trigger and `maxOutstandingRequests`, use host-level concurrency controls, and for HTTP add API Management in front with rate limits. Optionally cap via a Premium plan's instance count. Scaling is the platform's job — bounding the blast radius is yours.
10. **Q:** How do you do VNet integration and private endpoints for Functions?
**A.** Outbound VNet integration (subnet delegation, requires Premium/Flex for full features), private endpoints for inbound (no public access), private DNS zones, and storage/Key Vault access via private endpoints + managed identity. Watch subnet sizing — it's a scaling constraint.
11. **Q:** How do you test and deploy Functions safely?
**A.** Unit-test the logic outside the runtime, integration-test with the real trigger locally (Azurite/emulators), use deployment slots for zero-downtime swap (Premium/App Service), and gate on smoke tests. Keep function apps small and separate per concern so blast radius and scaling stay sane.
12. **Q:** How do you monitor Functions?
**A.** Application Insights with distributed tracing, dependency tracking, and structured logs; alert on failures, error rate, execution duration p95, instances, and queue/DLQ depth; dashboard e2e latency from trigger to completion. Remember ephemeral instances make host-level debugging useless — telemetry must be the primary tool.
13. **Q:** What are the limits you plan around?
**A.** Max execution time (Consumption default 5 min, max 10; Premium/App Service up to unbounded on the plan), payload sizes (HTTP ~100 MB), storage account dependency (Functions need a storage account for state/keys — a common single point of failure), and concurrency/scale limits per plan. Also: premium/Dedicated needed for always-on, VNet, bigger SKUs.

**🚨 War room**
14. **Q:** All functions in a region fail simultaneously. Where do you look?
**A.** The shared storage account (a deleted/firewalled storage account breaks all functions that use it for state/keys), the runtime version/plan platform incident, or a shared Key Vault/identity failure. Check the storage account firewall/network rules first — "everything failed at once" usually means a shared dependency, not the code.
15. **Q:** The function on the storage queue trigger stopped processing, queue is growing.
**A.** Check whether the trigger's storage account/connection is valid (keys rotated — a very common cause), the function's scaling/instance metrics, poison messages blocking the batch, and whether `maxDequeueCount` moved them to the poison queue (check its depth). Then fix the cause and replay the poison queue deliberately.
16. **Q:** After enabling private endpoints, the function can't reach storage.
**A.** Missing private DNS record (functions resolve the public FQDN to a public IP which is now blocked), missing private endpoint on the client side, or the subnet/NAT path missing. Fix DNS first (the usual culprit), then verify with `nslookup`/`curl` from a debug function or the Kudu console.
17. **Q:** Costs spiked 4× with no traffic growth.
**A.** Check executions + GB-seconds (a loop/polling trigger), the storage account transactions (chatty blob polls, diagnostics logging to the same account), App Insights ingestion (a very common silent cost), and Premium instance counts sitting idle (needs a minimum-instance review). Fix the noisiest source and add a budget alert.
18. **Q:** A function that processes once a day now runs multiple times.
**A.** Timer triggers run per instance when `isPastDue`/multiple instances exist or the schedule expression changed; ensure the function is idempotent, set a single-instance pattern (e.g. `WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT = 1` for that app, or a distributed lock), and verify the timer config (NCRONTAB) — a common `*` mistake.
19. **Q:** Logs are missing for a failing execution. Why and how do you fix it?
**A.** The function failed before telemetry initialised (missing App Insights connection string), the execution was killed (timeout/OOM), the logging category is filtered, or the app is using sampling. Verify the App Insights key/connection, enable `Host.Results` logging, and add a startup log line — plus local debugging via `func start` to reproduce.

**⚖️ Trade-off**
20. **Q:** Functions vs Container Apps vs AKS vs Logic Apps?
**A.** Functions for event-driven/glue/short tasks; Container Apps for containerised services with KEDA scaling and no cluster ops; AKS for platform standardisation and complex workloads; Logic Apps for low-code integration/workflows with many SaaS connectors. Match to the team's ops capacity.
21. **Q:** Consumption vs Premium plan?
**A.** Consumption: cheapest for spiky/low volume, scale to zero, cold starts, limited timeout/VNet features. Premium: pre-warmed instances (no cold start), VNet integration, longer duration, higher scale — costs even when idle. Latency-critical or network-integrated → Premium/Flex.
22. **Q:** Functions vs WebJobs/App Service?
**A.** Functions give triggers/bindings, per-execution scaling, and less boilerplate; WebJobs run continuously in an App Service with predictable cost. For continuous high-throughput processing, App Service/Container Apps can be cheaper and simpler than Functions scaling.
23. **Q:** Durable Functions vs a state machine (Logic Apps/Step Functions equivalent)?
**A.** Durable Functions for code-centric orchestration at scale with fine control; Logic Apps for visual/low-code integration with SaaS connectors and a lower learning curve. Choose by who maintains it and the connector ecosystem needed.
24. **Q:** Should each function be its own app?
**A.** Group by scaling/security/lifecycle profile: functions that scale together with the same identity and permissions can share an app; different scaling needs, network requirements, or privilege levels should be split. Over-splitting creates deployment and cost sprawl; under-splitting couples everyone to one scale decision.

**🎯 Senior**
25. **Q:** How do you run Functions at scale without creating a distributed-systems mess?
**A.** Idempotent handlers as a rule, ordering handled explicitly (sessions/partition keys) rather than assumed, DLQs with alarms and replay tooling, concurrency bounded to protect downstreams, correlation IDs propagated across triggers, shared code in libraries rather than copy-paste, and a standard template (identity, Key Vault, telemetry, retry policy) enforced by the deployment pipeline.

**🎯 Senior signal:** "a function's storage account is a shared dependency — everything fails together", downstream protection via concurrency limits, and DLQ alarms/replay. Those three show real serverless operations.

---

## 4. Cosmos DB — `cosmos-db.md`

**⚡ Rapid**
1. **Q:** What APIs does Cosmos DB offer?
**A.** NoSQL (Core/SQL) for document workloads, MongoDB, Cassandra, Gremlin (graph), Table, and PostgreSQL (separate flavour). The NoSQL API is the default for new projects unless you need compatibility.
2. **Q:** How does partitioning work and how do you choose a key?
**A.** Data is split by a partition key into logical/physical partitions; choose a high-cardinality, evenly distributed key aligned with query patterns (and for multi-tenant, often the tenant ID). A bad key creates hot partitions that throttle regardless of provisioned throughput.
3. **Q:** What are the consistency levels?
**A.** Strong, Bounded Staleness, Session (most common default), Consistent Prefix, Eventual — trading latency/availability against staleness. Session gives read-your-writes within a session with good performance.
4. **Q:** RU/s — what does it mean?
**A.** Request Units per second: normalised cost of reads/writes/query work. You provision (or autoscale) RU/s per container (or shared at database level), and exceeding it gives HTTP 429s which clients must retry with backoff.
5. **Q:** Partition key immutability — what does it mean for design?
**A.** You can't change a container's partition key in place — you must create a new container and migrate data. Getting it right up front (or using a synthetic key) matters enormously; this is the single most common design regret.
6. **Q:** Global distribution basics?
**A.** Add regions to the account (single or multi-write), with conflict resolution policies for multi-write (last-writer-wins or custom stored procedure), and a per-region write/read model. Be honest about cost of additional read regions and multi-write complexity.
7. **Q:** How do you query efficiently?
**A.** Point reads by ID+partition key (cheapest), then single-partition queries, then cross-partition (expensive, fan-out). Enable/design appropriate indexes (default policy indexes everything — customise to exclude unused paths), avoid full scans, and use the query stats (`x-ms-request-charge`) to measure RU cost per query.

**🔍 Deep dive**
8. **Q:** Design a globally distributed, multi-tenant app on Cosmos DB.
**A.** Per-tenant partition strategy (tenant ID as partition key, hierarchical keys with synthetic prefixes for hot tenants), autoscale RU/s or serverless for variable tenants, multi-region reads and selective multi-write where writes are regional, session consistency with session tokens where read-your-writes matters, conflict resolution for multi-write, TTL for ephemeral data, and monitoring of normalised RU consumption + 429s per partition key range. Add a per-tenant cost/usage dashboard — that's what makes it operable.
9. **Q:** Your app gets 429s under load. Fix.
**A.** Check RU consumption vs provisioned per partition (hot key!), increase RU/s or enable autoscale, add retry with backoff honouring the server's retry-after, reduce query cost (avoid cross-partition fan-out/point reads), and check the SDK's connection mode/direct mode and connection reuse. If one key is hot, fix the key design — more RUs won't save you.
10. **Q:** How do you use the change feed?
**A.** As an event source for projections, search indexing, cache invalidation, materialised views, and cross-region fan-out; consumed by Functions/Spark or the change feed processor with lease collections. Note ordering per partition key and that you can't filter/threshold it — design for full change streams.
11. **Q:** How do you do transactional consistency with Cosmos DB?
**A.** Transactions exist within a single logical partition (batch operations); across partitions you need sagas/compensation or a different service. Say this clearly — teams often assume distributed transactions and get bitten.
12. **Q:** How do you control cost?
**A.** Autoscale or serverless for variable load, share throughput at the database level for many small containers, TTL for ephemeral data, custom indexing policy to cut write cost, avoid unnecessary cross-partition queries and analytics on the transactional store (use Synapse Link/analytical store), and monitor RU consumption per partition/operation. Cost = RU × operations, so query design is the main lever.
13. **Q:** How do you do backup/restore and DR?
**A.** Continuous backup with point-in-time restore (recommended, per-container granularity and varied windows) vs periodic; plus multi-region replication with automatic/manual failover. Test a restore and a regional failover — multi-region reads are not a DR plan by themselves.
14. **Q:** How do you secure Cosmos DB?
**A.** Disable key-based access in favour of Entra ID + RBAC (built-in/custom data-plane roles), private endpoints with public access disabled, firewall rules, CMK encryption if required, Monitor logs/diagnostics to a central workspace, and least-privilege role assignments per application. Rotating keys is the old model — move off it.

**🚨 War room**
15. **Q:** A single tenant's traffic threatens to throttle the whole account. What do you do?
**A.** Confirm whether it's a hot partition (per-partition metrics) or overall RU saturation; immediate mitigations: raise RU/s/autoscale max, add synthetic-key sharding for that tenant, and rate-limit that tenant at the API layer. Structural: per-tenant throughput isolation (separate accounts/containers for large tenants) or partition-key redesign with a migration.
16. **Q:** Latency jumped from 5 ms to 80 ms. Diagnose.
**A.** Check whether traffic is going cross-region (SDK region preference/outage), the query changed (cross-partition fan-out, missing index), RU saturation causing throttling + retries (retries look like latency!), or the account's provisioned throughput dropped. Then look at RU charge per operation and the SDK diagnostics log.
17. **Q:** Failover happened and writes went to a different region, but the app behaves oddly.
**A.** Session consistency tokens aren't being honoured across regions (clients need to send the session token), the app is pinned to the old write region (SDK should discover the new one; hardcoded endpoints break), or conflict resolution rules let both regions write. Fix by using the SDK's dynamic region discovery and propagating session tokens, and validate conflict resolution behaviour explicitly.
18. **Q:** Restore is needed for a single container to a point 6 hours ago.
**A.** Use continuous backup point-in-time restore to a target account/container within the retention window, validate the data, then reconcile with production (or swap reads to the restored container). If continuous backup wasn't enabled, you're limited by the periodic backups (and their snapshot granularity) — say so and fix the setting.
19. **Q:** RU cost per request is 10× what you expected. Why?
**A.** Query is doing a cross-partition scan (large fan-out), the index policy is missing a needed path (or indexing everything and paying for writes), documents are large (RU scales with size), or the operation returns many items. Use query stats and the SDK diagnostics, then add the right indexes, project fewer fields, and switch to point reads.
20. **Q:** Someone shared the account key and it leaked. Response?
**A.** Rotate keys immediately (`regenerateKey`) with a dual-key strategy (rotate secondary, update apps, rotate primary) or better, move apps to Entra ID auth and disable key access; audit what was accessed (diagnostics logs), check for unauthorised containers/data changes, and restrict network access (private endpoints/firewall) to shrink the exposure window.

**⚖️ Trade-off**
21. **Q:** Cosmos DB vs Azure SQL vs PostgreSQL Flexible Server?
**A.** Cosmos for globally distributed, low-latency, high-scale, document/key-based access with known patterns; Azure SQL for relational/T-SQL/enterprise apps; PostgreSQL Flexible for open-source ecosystems with control. The data model and query patterns decide — pick the database for your access patterns, not the brand.
22. **Q:** Provisioned vs autoscale vs serverless?
**A.** Provisioned for steady, predictable load (with the option of 10% of max as a floor); autoscale for variable load (scales between 10% and max, at a slightly higher per-RU rate); serverless for intermittent/low-volume (no minimum, instant). Use the metrics — over-provisioned steady load is the most common waste.
23. **Q:** Single-partition vs cross-partition queries — when is cross-partition okay?
**A.** Fine for occasional admin/reporting queries or low-volume operations; dangerous for hot paths because the RU cost multiplies (fan-out to every partition) and it can't be served efficiently. If you need cross-partition queries in the hot path, the partition key is wrong.
24. **Q:** Multi-region writes vs single write region?
**A.** Multi-write reduces write latency and improves regional resilience but requires conflict resolution design, higher cost, and careful idempotency/testing. Start single-write with multi-read unless write latency/RTO demand otherwise.
25. **Q:** Cosmos DB vs Table Storage for a simple key-value store?
**A.** Table Storage is far cheaper for simple high-volume key-value with basic queries; Cosmos gives global distribution, richer querying, consistency options, and SLAs at a much higher price. Don't pay for Cosmos if a simple lookup is all you need.
26. **Q:** Should analytics run on the transactional container?
**A.** No — use the Synapse Link analytical store (or export to a lake) instead of heavy cross-partition aggregations on RU-metered storage. Analytics on the transactional store is the fastest way to burn RU budget and throttle production.

**🎯 Senior**
27. **Q:** What does "production-ready Cosmos DB" look like?
**A.** Partition key validated against real query patterns and load-tested for hot partitions, autoscale/provisioned sized from measured RU per operation, 429 retry policy with jittered backoff in every client, Entra-ID auth + private endpoints, continuous backup with PITR verified, multi-region read with a tested failover, diagnostics to a central workspace with RU/429/latency alerts, TTL for ephemeral data, and a per-tenant cost/usage dashboard so noisy tenants are visible before they throttle everyone.

**🎯 Senior signal:** "429s must be retried with backoff in the client", "the partition key can't be changed later", and "transactions only within a partition". Those three facts show real Cosmos design experience.

---

## 5. Defender for Cloud — `defender-for-cloud.md`

**⚡ Rapid**
1. **Q:** What is Defender for Cloud?
**A.** Azure's CSPM (secure score, recommendations, regulatory compliance dashboards) plus CWPP workload protection plans (servers, containers, storage, SQL, App Service, Key Vault, DNS, ARM, AI) with Defender for Servers, and integrations with Sentinel/Security Hub. It aggregates findings from agent/agentless scanning and cloud configuration.
2. **Q:** What is secure score?
**A.** A weighted score of your posture based on implemented recommendations — useful as a trend and prioritisation tool, but don't chase it blindly; fix high-impact controls rather than easy score wins.
3. **Q:** What is the difference between Defender plans?
**A.** The free-foundational CSPM gives recommendations/secure score; paid plans (Servers P1/P2, Containers, Storage, SQL, App Service, Key Vault, DNS, Resource Manager) add threat detection, vulnerability assessment, just-in-time access, and file integrity monitoring. You enable per workload type — usually you start with Servers and Containers.
4. **Q:** How does Defender for Servers find vulnerabilities?
**A.** Integrated vulnerability assessment (agent-based via Microsoft Defender for Endpoint or Qualys, and agentless scanning in P2) producing CVEs per VM with remediation guidance and recommendations. Pair with a patching process (Update Manager) — detection without remediation is theatre.
5. **Q:** What is JIT VM access?
**A.** Just-in-time: Defender opens temporary NSG rules for management ports on request with approval and time limits, instead of standing open rules. Replaces permanent 22/3389 exposure (or use Bastion instead).
6. **Q:** What is adaptive application control / adaptive network hardening?
**A.** ML-driven recommendations to restrict which applications run on VMs (allow-listing) and to tighten NSG rules based on observed traffic. Reduce attack surface using observed behaviour as evidence.
7. **Q:** How do findings get to your SOC?
**A.** Continuous export to Log Analytics/Sentinel/Event Hubs, alert routing by severity and resource tag, workbooks/dashboards, and (ideally) ticket creation + auto-remediation for deterministic findings via Logic Apps/Automation.

**🔍 Deep dive**
8. **Q:** Design a cloud-security posture programme on Azure with Defender for Cloud.
**A.** Enable CSPM at the tenant root with all paid plans for the workloads you run, enforce via Policy (assign Defender plans, auto-provision agents, enforce diagnostics), set security contacts + alert severity routing, continuous export to a Sentinel-enabled workspace, auto-remediation for deterministic controls (public storage, open management ports, missing encryption), an exception register with expiry and owners, secure score trend reviews by team, and quarterly regulatory dashboards (CIS/PCI/ISO) mapped to real controls with evidence. Governance: recommendations become backlog items with owners, not a dashboard nobody opens.
**↳ Follow-up:** "Secure score is 85% — are you secure?"
**A.** No: score measures implemented controls, not exposure or exploitability. You need to look at high-severity *alerts*, exposure paths (attack path analysis), and business-critical resource coverage gaps. "Score is a hygiene indicator, alerts and attack paths are the risk signal" is the senior answer.
9. **Q:** How do you handle alert fatigue from Defender?
**A.** Tune severity routing (high → page, medium → ticket, low → dashboard), suppress known-safe patterns with documented exceptions, use attack path analysis to prioritise, and correlate with your own telemetry. Also review the alert *types* you never action and either automate them or remove them from the pipeline.
10. **Q:** How do you do attack-path analysis and exposure management?
**A.** Use the attack path view (Defender's cloud security explorer/attack path analysis) to find internet-exposed workloads with vulnerable software, over-privileged identities, and lateral movement routes; remediate the *path* (close the exposure or break the path) rather than individual findings. Prioritise paths that reach data (Key Vault/SQL/storage).
11. **Q:** How does Defender integrate with Sentinel?
**A.** Alerts and findings are exported to a Sentinel workspace where analytics rules create incidents with entity mapping; playbooks (Logic Apps) automate enrichment/response (isolate VM, disable user, notify team). This is the SOC layer: Defender is detection on cloud workloads, Sentinel is correlation and response.
12. **Q:** How do you cover containers and Kubernetes?
**A.** Defender for Containers (image scanning in registry + at runtime, Kubernetes control-plane audit, admission control recommendations, vulnerability assessment), plus Azure Policy for AKS guardrails, private registries, and image signing. Map findings to the pipeline so vulnerable images never reach production.
13. **Q:** How do you handle multi-subscription/multi-tenant governance?
**A.** Enable Defender at management-group scope with Policy inheritance, use delegated administration for Sentinel/Log Analytics, standard alert routing per environment, and a central security team owning the tenant-level config while teams own remediation in their subscriptions (with SLA tracking).
14. **Q:** What about non-Azure workloads (AWS/GCP/on-prem)?
**A.** Defender for Cloud supports multi-cloud connectors (AWS/GCP) and Arc-enabled servers, giving one posture view — useful, but expect differences in coverage depth and require the right IAM roles on the other clouds. For a multi-cloud reality, say the limitation out loud.

**🚨 War room**
15. **Q:** Defender raises "crypto-mining activity" on a VM. Response?
**A.** Isolate the VM (NSG deny-all/quarantine, keep it alive for forensics), snapshot the disk for evidence, identify the entry vector (exposed port, weak credentials, vulnerable app), check for lateral movement and persistence (new users, scheduled tasks, keys), rotate credentials the VM could access, and rebuild from a clean image. Then fix the exposure permanently (JIT/Bastion, patching, firewall) and add the detection to a runbook.
16. **Q:** High-severity alert: "suspicious IP communicating with your Key Vault".
**A.** Check Key Vault diagnostics for what was accessed and by which identity/IP, determine whether the identity is compromised (sign-in logs for the principal, risks), revoke/rotate as needed (keys, secrets, role assignments), and consider restricting the vault to private endpoints only. Also check for other resources from the same source — one alert is often one breadcrumb of many.
17. **Q:** Secure score dropped 20 points overnight. Why?
**A.** A Policy/Defender plan change, a new subscription with many findings onboarded, an agent provisioning failure (agentless/AMA disconnected), or genuinely a new deployment that added public endpoints. Break down by recommendation and resource to see whether it's coverage (agent missing) or configuration (real regression) — and check onboarding state first.
18. **Q:** The security team is drowning in "public storage" findings across 40 subscriptions. Approach?
**A.** Classify (genuinely public vs intended static hosting with justification), remediate in bulk via Policy/script for the unintended ones, apply auto-remediation going forward (deployIfNotExists for public access block), and create an exception register for the intended cases with expiry and owner. Bulk fixes need validation to avoid breaking live static sites — do it per resource group with the owner notified.
19. **Q:** Defender shows a critical vulnerability on 200 servers. How do you triage?
**A.** Prioritise by exploitability (known-exploited/published exploit, CVSS + context), whether the service is internet-facing, and whether the path reaches sensitive data; then patch in waves (canary → non-prod → prod) using Update Manager, with a compensating control (network restriction) for anything you can't patch immediately. Track remediation SLA by severity and report percentages.
20. **Q:** Your agent coverage is 70% — how does that affect decisions?
**A.** It invalidates "we're clean" conclusions: 30% of your estate is unmeasured. Fix coverage first (Policy auto-provision, agent health monitoring, network path to the agent's endpoints — VNet/private endpoint issues are the usual cause) and dashboards showing coverage by subscription/resource type before discussing posture.

**⚖️ Trade-off**
21. **Q:** Defender for Cloud vs a third-party CSPM/CNAPP?
**A.** Defender is native, integrated with Azure/AKS/SQL, and cheaper for Azure-only estates; third-party CNAPPs often have deeper multi-cloud, code-to-cloud context, and workflow integrations. Many orgs run Defender for Azure and a third party for multi-cloud/k8s depth — pick based on where your risk and skills actually are.
22. **Q:** Auto-remediation vs alert-only?
**A.** Auto-remediate deterministic, low-risk, reversible findings (public blob access, missing diagnostics, open management ports when Bastion/JIT exists). Alert for anything that could break an app or destroy data. Publish the list of auto-remediated controls so teams aren't surprised.
23. **Q:** Agentless scanning vs agent-based?
**A.** Agentless (P2) gives snapshot-based vulnerability/secret scanning without touching the VM workload — good coverage with no performance impact, but no runtime protection or FIM. Agent-based gives runtime detections (Defender for Endpoint) and deep signals but requires install/health management. Mature estates use both: agentless for breadth/assessment, agent for runtime.
24. **Q:** Should every recommendation be remediated?
**A.** No — prioritise by exposure and business impact, accept documented exceptions, and question recommendations that don't fit your architecture. Blindly driving secure score to 100% wastes effort on low-value controls while real exposures (internet-facing + vulnerable + privileged identity paths) sit unaddressed.
25. **Q:** Defender for Servers P1 vs P2?
**A.** P2 adds agentless vulnerability scanning, file integrity monitoring, and just-in-time access plus deeper licensing integration (Defender for Endpoint). If you need MDE integration and agentless scanning, P2; otherwise P1 covers basic threat detection. Choose by coverage requirement, not price alone.

**🎯 Senior**
26. **Q:** How would you report cloud risk to an executive in one page?
**A.** Top 5 attack paths that reach sensitive data (with business impact), coverage percentage (what % of assets are measured), time-to-remediate by severity vs SLA, the 3 uncontrolled exceptions with owners and dates, and the trend (score/alert volume/MTTR). Not a list of 500 recommendations — exposure and progress against commitments.

**🎯 Senior signal:** "secure score ≠ security", prioritising by attack paths/exposure, and fixing *coverage* before discussing posture. That's a security leader's framing.

---

## 6. Key Vault — `key-vault.md`

**⚡ Rapid**
1. **Q:** What can Key Vault store?
**A.** Secrets (strings/passwords/connection strings), keys (RSA/EC for encryption/signing, HSM-backed in Premium/managed HSM), and certificates (with optional auto-renewal against supported CAs). Standard tier is software-protected; Premium gives HSM-backed keys.
2. **Q:** Access model: access policies vs RBAC?
**A.** RBAC (Azure roles like Key Vault Secrets User/Administrator) is the modern, recommended model — enable `enableRbacAuthorization` on the vault. Access policies are the legacy per-vault model (all-or-nothing per principal across secret/key/cert) and should be migrated off for new vaults.
3. **Q:** How does an app read a secret without credentials?
**A.** Managed identity (system/user-assigned) + RBAC role on the vault (or a specific secret), fetched via SDK/Key Vault references — no credentials anywhere. This is the pattern auditors expect.
4. **Q:** What is a Key Vault reference?
**A.** A pointer in app configuration like `@Microsoft.KeyVault(SecretUri=...)` that Azure resolves at runtime using the app's identity — so values never sit in config. Cache/refresh behaviour varies by service; keep it in mind.
5. **Q:** Soft delete and purge protection?
**A.** Soft delete keeps deleted vaults/objects recoverable (7–90 days); purge protection prevents permanent deletion during that window — required for production/compliance (and required to use CMK for some services).
6. **Q:** How do you rotate secrets?
**A.** Automate where possible (Event Grid + Function/Automation on near-expiry events, or native rotation for supported services), dual-credential pattern so both old and new work during the transition, and version references so consumers pick up the new version. Rotation without consumer refresh is a ticket, not a control.
7. **Q:** Why multiple vaults?
**A.** Segmentation: per environment, per application/region, and to stay under per-vault limits (transactions, objects, RBAC assignments). One giant vault is both a scaling and a blast-radius problem; too many vauleves fragment management — balance with naming/Policy standards.

**🔍 Deep dive**
8. **Q:** Design a secrets-management standard for a 200-app estate.
**A.** One vault per app+environment (region-aligned for data residency), RBAC-only with least-privilege roles (Secrets User for apps, Secrets Officer for the pipeline identity), private endpoints + no public access, purge protection + soft delete, CMK for higher tiers, diagnostic settings/logging to a central workspace with alerts on secret delete/permission changes, rotation policy per secret class (90 days secrets, 12 months certs), and a managed-identity-by-default rule enforced by Policy. Reference the "three names" convention: vault naming, secret naming, and tag/owner.
**↳ Follow-up:** "How do you prove no human read a production secret?"
**A.** Key Vault diagnostic logs (data-plane, `SecretGet`/`SecretList` events) exported to an immutable store, queried by principal — with RBAC designed so only the app's managed identity holds `Secrets User` on that secret. If access is not logged/retained, say that's the gap and fix it, because the honest answer is "we can't prove it yet".
9. **Q:** How do you handle multi-region secrets and certificates?
**A.** Key Vault is regional with automatic intra-region replication; for multi-region apps either use paired-region vaults with the same secrets (managed by pipeline), or a vault per region per app. Certificates with auto-renewal via Key Vault + App Gateway/Front Door Key Vault references are the cleanest — make sure the app's config references the vault URI in its region.
10. **Q:** How do you rotate a certificate with zero downtime?
**A.** Issue the new certificate alongside the old (both valid), configure the endpoint (App Gateway/App Service/Front Door) to trust both during the transition, switch the binding to the new one, verify with TLS checks, then retire the old. Automate via Key Vault auto-renewal and monitor `NotAfter` with alerts — never rely on a calendar reminder.
11. **Q:** What is Managed HSM and when do you need it?
**A.** A single-tenant, FIPS 140-2 Level 3 HSM-backed key store with full key control — required by some regulations (or when you need key operations unavailable in Key Vault Premium). Higher cost and operational overhead; use it for signing/root keys where control matters, not for all secrets.
12. **Q:** How do you secure Key Vault's own access paths?
**A.** Private endpoints + public network access disabled or restricted, firewall rules if public access is unavoidable, RBAC with PIM for admin roles, resource locks on the vault, diagnostic logs (both management and data plane), alerts on permission changes/secret deletions/vault deletion, and careful use of "trusted Azure services" bypass (document who needs it).
13. **Q:** How do you handle secrets for CI/CD and pipelines?
**A.** Workload identity federation from the pipeline to Azure, then read from Key Vault at deploy time (or use Key Vault references in the target service) — no secrets stored in Azure DevOps/GitHub variable groups where avoidable, and no long-lived PATs. Where variable groups are used, store them as Key Vault-backed with restricted project access.
14. **Q:** What are the Key Vault transaction limits and how do you avoid throttling?
**A.** Per-vault transaction/QPS limits (varied by vault and operation) — apps that fetch a secret on every request will hit them. Mitigate with SDK caching (in-memory with TTL), Key Vault references resolved once at app start, and sharding across vaults for very high-volume apps. Monitor throttling (`429`s) and add backoff.

**🚨 War room**
15. **Q:** The vault is unreachable and every service that reads a secret is failing at start-up.
**A.** Check the vault's resource health, whether a firewall/private-endpoint/DNS change cut access, whether the RBAC assignment was removed, and whether the vault was deleted (soft delete → recover). Short-term: if the app caches secrets, it may be running fine — the failure is at restart. Permanent fix: cache secrets with sensible TTL + graceful degradation, DNS/endpoint monitoring, and alerts on vault access failures.
16. **Q:** A secret was read by an unexpected principal. Investigate.
**A.** Query Key Vault diagnostic logs for the principal/IP/time, check the identity's sign-in logs and role assignments to see when access was granted, determine whether the identity was compromised or the role assignment was a mistake, then revoke and rotate the secret (assume exposure) and audit what it protected (DB/API) for abuse. Add an alert on unexpected principals reading production secrets.
17. **Q:** Purge protection blocked deleting a vault in a sandbox. Annoying or correct?
**A.** Correct behaviour — purge protection is doing its job; the sandbox vault should have been created without purge protection or in a non-production policy. Don't disable protections to work around process; find and fix the creation template so environments are provisioned with the right settings.
18. **Q:** You must rotate 300 secrets across 60 vaults this quarter.
**A.** Centralise the inventory (Resource Graph/Key Vault API) with owners and expiry, automate rotation for classes of secrets (Event Grid + Function for near-expiry, native rotation for supported services, pipeline-driven for others), track completion with a dashboard and per-team reporting, and use the dual-secret pattern so consumers don't break. Manual ticketing doesn't scale past a handful.
19. **Q:** An application's certificate expired and App Gateway lost TLS.
**A.** Restore service (upload/reference a valid cert, update the listener), then fix the root cause: Key Vault auto-renewal enabled and correctly scoped (the CA/issuer may need re-authentication), plus expiry alerts at 45/30/7 days and a synthetic TLS check from multiple regions. Also verify that the App Gateway references the *version-less* secret ID so renewals are picked up.
20. **Q:** A developer pasted a production secret into a ticket/chat.
**A.** Rotate immediately (treat as public), check logs for use of the credential since exposure, remove the message where possible but assume it's copied, and address the process gap: Key Vault-backed access with managed identity, training on not transporting secrets, and if it's a recurring pattern, block secrets at the chat/ticket integration level.

**⚖️ Trade-off**
21. **Q:** Key Vault vs Managed HSM vs Key Vault (Premium) for keys?
**A.** Key Vault Premium gives HSM-backed keys with shared infrastructure and simpler ops; Managed HSM gives single-tenant dedicated HSMs with full control and higher throughput/assurance, at higher cost and operational complexity. Choose Managed HSM when regulation or risk demands dedicated control; otherwise Premium.
22. **Q:** Access policies vs RBAC?
**A.** RBAC: fine-grained per secret/key/cert scope, consistent with the rest of Azure RBAC, auditable, and supports PIM. Access policies: legacy, vault-wide, but still needed for some service integration scenarios and older SDK flows. New vaults: RBAC.
23. **Q:** One vault per app vs per environment vs per subscription?
**A.** Per app+environment is the sweet spot (clean ownership, least privilege, manageable limits); per subscription creates a shared blast radius and permission sprawl; per-secret isolation isn't practical. Add region alignment for residency.
24. **Q:** Managed identity vs service principal with certificate for accessing Key Vault?
**A.** Managed identity is credential-free and lifecycle-bound — always preferred for Azure-hosted workloads. Service principals (certificate, not secret) only for non-Azure hosts, with rotation automation. Client secrets are the fallback you should be eliminating.
25. **Q:** Store config in Key Vault vs App Configuration?
**A.** App Configuration is for non-secret configuration with feature flags/labels and richer refresh semantics at lower cost; Key Vault is for secrets/keys/certs. Using Key Vault for all config is expensive and slow (transaction limits) — split by sensitivity.
26. **Q:** Should apps cache secrets?
**A.** Yes, with a bounded TTL and a refresh-on-failure path — otherwise you hammer the vault and create a hard dependency on every request. Design the cache so a rotation propagates within the app's tolerance (e.g. 5–15 min) and test the rotation path end to end.

**🎯 Senior**
27. **Q:** What does a mature secrets posture look like?
**A.** No long-lived secrets anywhere (workload identity/federated credentials), managed identity for all Azure-hosted apps, RBAC-only vaults with private endpoints and no public access, purge protection enforced by Policy, rotation automated per secret class with dual-credential transitions, data-plane logging to an immutable store with alerts on unexpected reads/deletes/permission changes, certificates auto-renewing with expiry alerts, and a documented, tested break-glass procedure.

**🎯 Senior signal:** "logging the data plane proves who read what", "reference the versionless secret ID so renewals work", and caching with TTL. That's the answer of someone who has operated a vault estate.

---

## 7. Logic Apps — `logic-apps.md`

**⚡ Rapid**
1. **Q:** Consumption vs Standard Logic Apps?
**A.** Consumption: per-execution pricing, fully managed, 5-minute default timeout (up to 90 days for async patterns), simpler connectors. Standard: single-tenant, runs on App Service/Functions infrastructure, VNet integration, predictable pricing, better for high volume and enterprise networking. Standard is the go-forward for most new enterprise workflows.
2. **Q:** What are the main building blocks?
**A.** Triggers (HTTP request, recurrence, Service Bus, Event Grid, connectors), actions, control flow (conditions/switch/foreach/until/scope), parallel branches, managed connectors (SaaS), custom connectors, and the workflow definition (JSON) + parameters.
3. **Q:** Why is a Logic App the wrong place for business logic?
**A.** It's an integration/orchestration tool: complex business rules become unmaintainable JSON, hard to unit test, and hard to version-compare. Keep logic in a service (Function/API) and use Logic Apps for orchestration, connectors, and retries.
4. **Q:** How do you handle errors and retries?
**A.** Configure per-action retry policies (fixed/exponential, count), use Scopes with "run after" configuration for catch/finally patterns, terminate/compensate on failure, and route failures to a notification/ticket. Also enable run history retention and log to Log Analytics.
5. **Q:** How do you secure a Logic App?
**A.** Managed identity for connector access, Key Vault for secrets, IP restrictions/private endpoints (Standard), access control for the workflow (RBAC on the resource + trigger auth via SAS/Entra for HTTP triggers), and parameterise connections rather than embedding credentials. Secure the run history — it contains payload data.
6. **Q:** How do you version and deploy Logic Apps?
**A.** Consumption: ARM/Bicep templates or export-from-portal then parameterise (never hand-edit in prod). Standard: code-based project (VS Code, workflow.json) deployed through pipelines with parameters per environment — much cleaner. Use separate resources per environment, not stages within one workflow.
7. **Q:** What's the run-history/retention story?
**A.** Run history stores input/output of each run (payloads!) and is retained per plan/configuration — it's both an audit asset and a data-leak risk. Set retention appropriately and restrict access; for sensitive payloads, avoid logging full bodies and store data in a service rather than passing it through the workflow.

**🔍 Deep dive**
8. **Q:** Design an integration that must reliably process 100k messages/day from Service Bus with enrichment and downstream APIs.
**A.** Standard Logic Apps (or Functions) for throughput/cost, Service Bus trigger with sessions for ordering where needed, enrichment via managed connectors/API calls with retry policies, idempotency via a state store (or Service Bus dedup), dead-letter handling, and observability into Log Analytics with alerts on failure rate and backlog. For that volume, verify whether Functions would be cheaper and simpler — Logic Apps per-execution pricing gets expensive at scale.
9. **Q:** How do you do "long-running workflow" (human approval, hours/days)?
**A.** Async pattern with HTTP webhook actions (approval requests), delays/until loops, and persisted state in the workflow run — or Durable Functions for finer control. Track SLAs/timeouts explicitly and notify/expire stale approvals; don't let a workflow sit forever silently.
10. **Q:** How do you make a Logic App idempotent and safe on retries?
**A.** Store processed message IDs in a durable store with a TTL, check before doing work, and make the downstream operations idempotent (idempotency keys). Also configure retries knowing the platform may redeliver — "exactly once" doesn't exist here.
11. **Q:** How do you monitor and troubleshoot a failing workflow?
**A.** Run history gives the exact failed action with inputs/outputs (the killer feature of Logic Apps), plus Application Insights/Log Analytics for trends. For intermittent issues, add a correlation ID through the workflow, alert on failed runs/backlog, and check connector throttling (SaaS API limits are a common hidden cause).
12. **Q:** How do you control cost at high volume?
**A.** Move high-volume flows to Standard (predictable, cheaper at scale) or Functions, reduce action count per run (fewer connector calls, batching), avoid polling triggers where possible (use Event Grid/webhooks), minimise run history retention, and monitor per-workflow execution counts to find the chattiest flows.
13. **Q:** When is Logic Apps the wrong choice?
**A.** Complex algorithmic logic, very high throughput/low latency, heavy data transformations (use Data Factory/Functions/Synapse), or anything requiring unit-testable business logic. Logic Apps shines at connector-heavy orchestration and low-code integration.

**🚨 War room**
14. **Q:** A critical workflow stopped running; no one noticed for a day.
**A.** Check trigger configuration/expiry (SAS-signed HTTP triggers expire!), connector authentication (tokens expire when a user's credentials change — very common), throttling, and whether the workflow was disabled. Then fix monitoring: alerts on no-runs-in-X and on failed runs, plus an ops dashboard. "Silent stop" is always a monitoring gap.
15. **Q:** Thousands of runs failed after a SaaS API change.
**A.** Inspect run history for the connector's error, adapt the mapping/API version, and add a resilience layer: retry with backoff, fallback path/queue, and schema validation. Then reduce the coupling (queue messages and process with a service you control, or version the integration contract) so a vendor change degrades rather than breaks.
16. **Q:** A workflow processed the same payment twice.
**A.** Missing idempotency: the trigger redelivered (or the workflow retried an action) and the downstream was not idempotent. Fix by storing processed IDs transactionally with the payment record, and use idempotency keys on the payment API. Then audit for other flows with side effects and no dedup — this is a class of bug, not a single incident.
17. **Q:** Sensitive data showed up in the run history accessible to a wide group.
**A.** Restrict access to the Logic App resource (RBAC) and run history, purge/limit history where possible, and reduce what's logged (don't pass PII through workflow actions — fetch/store in a controlled service). Then assess whether it constitutes a data incident per policy, and add DLP policies for the connectors involved.
18. **Q:** The workflow is running but taking hours instead of minutes.
**A.** Look for sequential connector calls that could be parallel, retries/backoff on a failing dependency, throttling from a SaaS connector (check its limits), large payload transformations, and long-polling triggers. Also verify the workflow isn't waiting on approvals/delays by design. Run history timing per action shows exactly where the time goes.
19. **Q:** A connector's authentication broke after a password/credential change.
**A.** The connection uses a user's credentials or a secret that rotated — replace with a managed-identity/service-principal-based connection (where the connector supports it), or centralise the credential in Key Vault and update the connection. Monitor connector health so this surfaces as an alert, not a business complaint.

**⚖️ Trade-off**
20. **Q:** Logic Apps vs Functions vs Power Automate?
**A.** Logic Apps for enterprise integration with connectors, retries, and run history; Functions for code-centric, high-throughput, cheap-at-scale event processing; Power Automate for citizen-developer/personal productivity flows (with governance concerns in enterprise). Choose by who owns the workflow and the throughput requirement.
21. **Q:** Consumption vs Standard?
**A.** Consumption for low/medium volume, no VNet needs, fastest start; Standard for high volume (cost), VNet/private networking, predictable performance, and code-based deployment. New enterprise integrations should generally start Standard.
22. **Q:** Logic Apps vs Service Bus + consumers?
**A.** Logic Apps orchestrates and connects but isn't a queue; for reliable high-volume processing with retries/backpressure, put Service Bus in front and let Functions/containers consume — then optionally orchestrate with Logic Apps where connector value is high. Avoid using Logic Apps as the queue/worker layer at scale.
23. **Q:** One workflow doing everything vs many small workflows?
**A.** Small, focused workflows are testable, independently deployable, and easier to monitor; a mega-workflow becomes unmaintainable JSON with an opaque failure surface. Split by business capability and chain via HTTP/Service Bus/child workflows.
24. **Q:** Should Logic Apps call your internal APIs directly or go through API Management?
**A.** Through API Management when you need throttling, auth policies, versioning, and observability — it also decouples the workflow from backend changes. Direct calls are fine for internal, low-risk flows but you lose the governance layer.
25. **Q:** Managed connectors vs custom HTTP calls?
**A.** Managed connectors give auth handling, retries, and familiar shapes but add per-action cost and vendor-specific behaviour; raw HTTP is cheaper and more flexible but you own auth/retry/schema. Use connectors where they save real work (OAuth-heavy SaaS) and HTTP where the API is simple and volume is high.

**🎯 Senior**
26. **Q:** What's your standard for production Logic Apps?
**A.** Standard plan where volume/networking matter, managed identity for all connections, parameters per environment with Key Vault references, idempotent processing with a dedup store, retry policies + scopes for error handling, Log Analytics/App Insights with alerts on failures and no-run conditions, restricted run history (no PII), deployment via pipeline with environment parameters, and a documented owner/on-call for every workflow.

**🎯 Senior signal:** "run history is payload data — treat it as a data store", "HTTP triggers with SAS expire and silently stop", and "don't use Logic Apps as your worker layer at scale". Those are operational truths.

---

## 8. Service Bus — `service-bus.md`

**⚡ Rapid**
1. **Q:** Queue vs Topic/Subscription?
**A.** Queue: point-to-point, one logical consumer (competing consumers for scale). Topic with subscriptions: publish/subscribe with independent copies per subscription, filters/rules on each, and per-subscription DLQs. Choose by fan-out, not by familiarity.
2. **Q:** Tiers?
**A.** Basic (queues only, no topics/duplicates/DLQ-size limits), Standard (topics, DLQs, duplicate detection, transactions, 256 KB), Premium (isolated resources, VNet integration, 1 MB messages, predictable performance). Production with VNet/private endpoints needs Premium.
3. **Q:** How do messages get delivered exactly once?
**A.** They don't — Service Bus is at-least-once with duplicate detection (by MessageId within a window). You must design idempotent consumers and use `Complete/Abandon/DeadLetter` correctly with `PeekLock` receive mode.
4. **Q:** What is a dead-letter queue and how do you use it?
**A.** Messages that exceed `MaxDeliveryCount`, expire, or fail a filter go to the entity's DLQ (per subscription/queue). You monitor its depth, inspect why via `DeadLetterReason`, fix the handler, then resubmit or resubmit-repaired. An unmonitored DLQ is silent data loss.
5. **Q:** Sessions — what are they for?
**A.** Ordered, exclusive processing of related messages: you set a `SessionId` (e.g. per customer/order), and a single consumer handles each session sequentially, enabling FIFO-with-parallelism and state storage per session. The standard answer for ordered processing at scale.
6. **Q:** How do you route/filter messages?
**A.** Subscription rules with SQL-like filters or correlation filters on message properties (not body) — routing at the broker saves consumers from receiving and discarding everything (which cuts costs and noise). Use separate subscriptions for materially different consumers.
7. **Q:** How do you authenticate?
**A.** Entra ID managed identity with the `Azure Service Bus Data Owner/Sender/Receiver` RBAC roles — the modern answer. Shared access policies (SAS keys) are legacy, harder to rotate, and a common audit finding.

**🔍 Deep dive**
8. **Q:** Design an order-processing system with strict per-order ordering, retries, and DLQ handling.
**A.** Orders → Service Bus Premium queue with sessions (SessionId = orderId) → consumers with `maxConcurrentSessions` tuned for parallelism, processing in order per session, idempotent handlers (dedup store in Cosmos/SQL), `MaxDeliveryCount` set from the retry budget, DLQ monitoring with alerts and a resubmission tool, and dead-letter analysis dashboards. Add Application Insights with correlation IDs propagated into message properties, plus a backlog-age alert (not just depth).
**↳ Follow-up:** "One consumer is stuck on a poison message; how do you keep others moving?"
**A.** Sessions isolate the damage (only that session stalls); set a short lock duration with auto-renewal, `MaxDeliveryCount` so poison messages move to the DLQ promptly, and use a circuit-breaker/exception classifier so unrecoverable errors dead-letter immediately rather than retrying blindly. Also alert on sessions with a high delivery count.
9. **Q:** How do you handle the lock/processing-timeout mismatch?
**A.** The `PeekLock` lock duration (default 1 min, max 5 min) must exceed expected processing time, and long handlers must auto-renew the lock (`AutoComplete`/renewLock with the SDK) or the message becomes visible to another consumer → duplicate processing. Also set `MaxAutoLockRenewDuration` sensibly (it's capped, and very long processing should be redesigned).
10. **Q:** How do you scale consumers correctly?
**A.** Competing consumers across instances with `PrefetchCount` and `MaxConcurrentCalls` bounded to protect downstreams; scale on backlog per consumer (message count / instance count) and on age-of-oldest-message for SLA. Scaling more consumers than partitions/sessions allow gives no benefit and can hurt ordering — that trade is the interesting part of the question.
11. **Q:** How do you migrate from Standard to Premium with no downtime?
**A.** Plan the namespace migration: deploy the Premium namespace with the same entities (queues/topics/subscriptions), configure both senders and consumers (dual-read/Dual-write or cutover window), migrate in-flight messages or drain the old namespace, then switch DNS/connection strings (use the fully qualified namespace in config so it's a config change, not a code change). Include a rollback window while the old namespace still has traffic.
12. **Q:** What's the difference between Service Bus, Event Grid, and Event Hubs?
**A.** Service Bus: enterprise messaging with ordering, transactions, sessions, DLQs (commands/tasks). Event Grid: push-based reactive event routing with retries/filters (events). Event Hubs: high-throughput streaming/telemetry with partitions, retention, and replay (data streams). Pick by semantics: command vs event vs stream.
13. **Q:** How do you monitor and alert on messaging health?
**A.** Metrics: active/ scheduled/dead-lettered message counts, incoming/outgoing rates, throttled requests, server latency, and namespace-level throttling; plus age-of-oldest-message for SLA. Alert on DLQ growth, backlog beyond threshold, throttling, and no-consumer-activity. Dashboards per entity, not just per namespace.
14. **Q:** How do you secure Service Bus end-to-end?
**A.** Premium with private endpoints (no public access) + private DNS, managed identity/RBAC (no SAS keys), resource-level least privilege (send-only vs receive-only), encryption with CMK optional, and diagnostic logs to a central workspace with alerts on permission changes and anonymous/legacy-auth attempts. Also disable local auth where the SDKs support it.

**🚨 War room**
15. **Q:** The queue is growing fast and no one is processing. First moves?
**A.** Check the consumer's health (deployments, crashes, connectivity), whether the entity is disabled, throttling (Standard tier has throughput limits — Premium has messaging units), whether the lock/lease is stuck, and whether the consumer's identity still has permissions. Then scale consumers and, if the backlog is hours long, decide on a catch-up strategy (temporary higher concurrency, batching) with a communicated ETA.
16. **Q:** Duplicate order confirmations were sent to customers.
**A.** At-least-once delivery with a non-idempotent consumer, or a lock expiry/retry after a successful side effect; or duplicate sends by a producer retrying without dedup. Fix with idempotency keys stored transactionally with the side effect, `MessageId`-based duplicate detection at the broker (as a second layer), and a reconciliation report. Treat customer-visible duplicates as a sev-level issue with comms.
17. **Q:** DLQ has grown to 300k messages. How do you recover?
**A.** Quantify by `DeadLetterReason` and time, determine whether the cause is fixed, then replay in a controlled way: write a resubmission tool (or Service Bus Explorer/Logic App) with throttling and idempotent consumers, replay into a dedicated queue first if you need to validate, and track progress with metrics. Do not bulk-move into production without rate control — you'll DDoS your own system.
18. **Q:** Throttling errors (`ServerBusy`/`ServiceBusyException`) under load on Standard tier.
**A.** You've hit the tier's throughput/connection limits — mitigate with batching, prefetch tuning, fewer connections (reuse `ServiceBusClient`/`ServiceBusSender` across calls; creating a client per message is a classic bug), and move to Premium with messaging units for isolation and scale. Also check for retry storms amplifying the load.
19. **Q:** Messages expire before being processed during a long outage. Prevention?
**A.** Set TTL and `MaxDeliveryCount` deliberately (TTL should exceed your longest plausible outage), enable dead-lettering on expiry, and alert on expiry events. For business-critical flows, mirror messages to storage/archive as you send, so nothing is lost when TTL expires — that's the "durable log" trade Service Bus doesn't give you.
20. **Q:** A subscription's filter was changed and a whole consumer stopped receiving messages.
**A.** Messages matching no rule are dropped silently unless `EnableDeadLetteringOnFilterEvaluationExceptions`/a catch-all rule exists — check the rules and the subscription's message counters, restore the rule, and add a catch-all/default rule for unmatched messages where you want visibility. Then alert on "subscription has zero receives while the topic has publishes" (a great detection for this exact failure).

**⚖️ Trade-off**
21. **Q:** Service Bus vs Storage Queues?
**A.** Storage Queues: cheapest, massive scale, at-least-once, no ordering/sessions/transactions, 64 KB messages. Service Bus: ordering (sessions), transactions, duplicate detection, scheduled delivery, larger messages, filters, DLQ semantics, RBAC/VNet on Premium — at higher cost. Use Storage Queues for simple decoupling; Service Bus when messaging semantics matter.
22. **Q:** Service Bus vs Event Hubs vs Kafka?
**A.** Service Bus for commands/tasks with enterprise semantics; Event Hubs for high-throughput streaming with retention/replay and consumer groups; Kafka (or Event Hubs' Kafka surface) when the ecosystem/stream-processing model is required. "Do consumers need to replay?" is the deciding question.
23. **Q:** Standard vs Premium tier?
**A.** Premium gives isolation, predictable performance, VNet/private endpoints, 1 MB messages, and geo-disaster recovery at a fixed cost; Standard is shared and cheap but can throttle and lacks VNet support. Production enterprise workloads with security requirements: Premium.
24. **Q:** Topics with many subscriptions vs multiple queues?
**A.** Topics give publisher-side simplicity and broker-side filtering, at the cost of duplicate storage/throughput per subscription; queues are simpler and cheaper when there's one consumer. If consumers need materially different data, publish to separate queues/topics from the source rather than filtering in the broker.
25. **Q:** Should you use sessions everywhere for ordering?
**A.** No — sessions add per-session serialisation, and a hot session can throttle throughput. Use them only where ordering per key is a business requirement; otherwise rely on idempotency and accept out-of-order processing.
26. **Q:** PeekLock vs ReceiveAndDelete?
**A.** `ReceiveAndDelete` loses messages on failure (no redelivery) — only for fire-and-forget telemetry. `PeekLock` is the default for real work: complete on success, abandon on transient failure, dead-letter on unrecoverable. Any production answer is PeekLock with explicit completion.

**🎯 Senior**
27. **Q:** What does production-ready Service Bus look like?
**A.** Premium tier with private endpoints and managed identity (no SAS keys), sessions only where ordering is required, explicit `MaxDeliveryCount`/TTL and dead-lettering policy, idempotent consumers with dedup storage, bounded concurrency (`MaxConcurrentCalls`/prefetch) to protect downstreams, DLQ alerts with a tested replay tool, correlation IDs propagated through message properties, backlog-age alerting, diagnostic logs to a central workspace, and a documented catch-up strategy for backlog incidents.

**🎯 Senior signal:** "at-least-once, so idempotency is mandatory", "lock duration vs processing time causes duplicates", and alerting on *age* of the oldest message rather than depth. Those three are the marks of a messaging practitioner.
