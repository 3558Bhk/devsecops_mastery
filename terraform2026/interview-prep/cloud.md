# Cloud Engineering (AWS + Azure) — Real Interview Questions

> ~65 questions across 5 parts. Cloud interviews grade: breadth (you know where everything lives) + depth on 2–3 services + judgment (cost, security, "why not the other cloud").
> You have the full Terraform AWS+Azure course in this workspace — you can say "I've deployed this with Terraform" for most of Part 2.

---

## Part 1 — Basic Level (phone screen / fundamentals)

**Q1. What is the shared responsibility model?**
→ The cloud secures *of* the cloud (hardware, region, AZ, hypervisor); you secure *in* the cloud (OS, data, IAM, app, network rules). IaaS: you own more (patch the OS). PaaS/SaaS: they own more. Say it with an example: "with RDS, Amazon patches PostgreSQL; I still own the DB user permissions and encryption of *my* data."

**Q2. What is an IAM role? Difference from a user? Why do roles exist?**
→ User = a permanent identity (a human or a script) with credentials. Role = an identity you *assume* (temp credentials, no long-lived keys) that an entity is trusted to take on. EC2 instance role: the instance assumes it, no keys on disk. Cross-account role: account B trusts account A's role. "Roles exist so credentials are temporary and trust is declared."

**Q3. Explain VPC (AWS) / VNet (Azure): subnets, route tables, internet access.**
→ Private IP space you control. Subnets = CIDR slices in an AZ. Public subnet: route table has 0.0.0.0/0 → Internet Gateway. Private subnet: no IGW route (resources use NAT to egress, or VPC endpoints). Security groups (stateful, per-resource) vs NACLs (stateless, per-subnet). Say both clouds: "AZs are the isolation domain — spread subnets across 2+ for any HA."

**Q4. Security group vs NACL (AWS) / NSG (Azure)?**
→ SG = stateful allow-list on instances/ENIs (return traffic automatic). NACL = stateless rule set on subnets (must allow both directions), evaluated by rule number, supports DENY. NSG (Azure) = SG equivalent (stateful, on NIC/subnet). Classic probe: "traffic denied in SG but allowed in NACL" → NACL wins (it's checked first, per subnet).

**Q5. S3 storage classes — name 4 and when you'd use each.**
→ Standard (hot), Standard-IA (infrequent, > 30 days), Glacier IR (archive, min 30 days, minutes access), Glacier Deep Archive (cheapest, hours). Plus One Zone (single AZ, cheaper, no cross-AZ DR). Probe: "object smaller than 128KB in IA" → per-request fee + min storage duration make IA *more* expensive for small hot objects.

**Q6. EBS vs EFS (AWS)? Azure equivalent?**
→ EBS = block volume, single-attach (one AZ), attach to EC2 — like a raw disk. EFS = shared filesystem (NFS), multi-AZ, multi-attach — for shared home dirs / app data. Azure: Managed Disks (EBS) vs Azure Files (EFS). "Block for one VM's disk, file for many VMs' shared data."

**Q7. RDS vs Aurora? When is each right?**
→ RDS = classic managed DB (MySQL/Postgres/SQL Server), single writer + read replicas. Aurora = AWS's cloud-native Postgres/MySQL: storage auto-scales (up to 128TB), 6-way replication across 3 AZs, 15 min PITR, faster failover (minutes→~10s class). Right: Aurora when you want the durability + scale without tuning; RDS when cost/compatibility matters and a single AZ's replication model suffices. Azure equivalents: Azure SQL Database (PaaS) vs Flexible Server (IaaS-ish) vs Cosmos (NoSQL).

**Q8. What is a Lambda function? Limits you should know?**
→ Event-driven compute (no servers). Key limits: 15 min timeout (the one people always hit), 10GB temp disk, memory 128MB–10GB (CPU scales with memory). Cold starts (ms–s) — why you keep layers small, provision concurrency for latency-sensitive, and don't put 2-min initializations in the handler.

**Q9. SQS vs SNS vs EventBridge (AWS)? Azure equivalents?**
→ SQS = queue (1 consumer group at a time, decouples + buffers). SNS = pub/sub fan-out (topic → many subscriptions). EventBridge = event *router* (rules: "when S3 object created in this prefix → call this Lambda"). Azure: Service Bus (queues + topics, richer), Event Grid (EventBridge). "Queue for work, pub/sub for notification, router for glue."

**Q10. What is API Gateway? Difference between REST and HTTP APIs (AWS)?**
→ Managed front door for APIs (auth, throttling, mapping, caching). REST API = full-featured (WAF, canary, request validation, more integrations) but more expensive per call; HTTP API = thinner + cheaper (Lambda proxy mode, per-request pricing). Pick HTTP API for high-volume simple routes; REST when you need the extras.

**Q11. What are CloudFront / Azure CDN? Where does the origin fit?**
→ Edge network: caches content at PoPs near users; origin = S3/ALB/your servers. You configure cache behaviors (paths, TTL, headers to cache), and the CDN handles TLS at the edge + origin shield (reduce origin load). Say why: latency (distance), origin offload, and DDoS absorption at the edge.

**Q12. Explain a DNS record: A, CNAME, Alias, TXT, MX. When is CNAME not enough?**
→ A = IP. CNAME = alias to another name. Alias (AWS Route53) = CNAME-like but *can point at an AWS resource* and works at the zone apex. TXT = verification/metadata (SPF, DKIM, domain ownership). MX = mail. "CNAME can't sit at the zone root (example.com) — that's what Alias (or a bare A) is for."

**Q13. What is a load balancer? Health checks' job?**
→ Distributes traffic across targets (instances/containers/IPs) and *removes unhealthy ones* via health checks — the health check is the LB's immune system. Say: target group = the pool + the check config (path, port, thresholds); a target fails N checks → out of rotation; recovers → back in.

**Q14. What's an AMI / Azure image? What's in it?**
→ A machine image: OS + drivers + (often) your app baseline + boot config. You boot instances from it. Custom AMI = your golden build (snapshot of a configured instance, or Packer-built). "The AMI is how 'the server we tested' becomes 'the server in prod' — if your AMI is a hand-configured snowflake, your prod is a snowflake."

**Q15. What is an Auto Scaling Group? Min/max/desired — what do they actually do?**
→ Keeps N healthy instances. Min = floor (scale-in never below), max = ceiling (scale-out never above), desired = target after launch. Scaling policies (target tracking: keep CPU 50%; or scheduled: 10am traffic). Say: "ASG scales on *metrics you trust* — if your alarm is wrong, your fleet is wrong."

**Q16. What is a KMS key? Envelope encryption in one sentence?**
→ KMS = managed key service (you control the key; the cloud controls the HSM). Envelope: a *data key* (generated per object/file) encrypts your data; the data key itself is encrypted by the KMS key and stored with the data. "KMS never sees your data; it only wraps/unwrap keys."

**Q17. What is a WAF? What does it actually protect against?**
→ Web Application Firewall: inspects HTTP(S) for app-layer attacks (SQLi, XSS, path traversal, bad bots) using rule sets (managed + custom), in front of your web tier (CloudFront/WAF or App Gateway WAF). It's *not* a DDoS layer (that's Shield/AF), and it's not a replacement for fixing the app — it's a guardrail while you do.

**Q18. What's the difference between us-east-1 and us-east-2?**
→ Same *region* family, different physical locations; within a region are AZs. Multi-AZ = fault isolation inside a region. Cross-region = disaster recovery (an AZ loss doesn't take the region). "AZs are for outages; regions are for catastrophes."

**Q19. What is CloudTrail / Azure Activity Log? What do they NOT tell you?**
→ Audit log: *who did what to your AWS/Azure API* (every API call, who, when, source IP). They do NOT tell you *application-level* events (what your app did to data inside a service) — that's your own logging / DB audit. "Trail = the security camera of the control plane."

**Q20. What is a VPC peering / VNet peering? Limits?**
→ Private network link between two VPCs/VNets (no internet transit). Not transitive (A↔B, B↔C does NOT give A↔C) → for many networks you need a hub (Transit Gateway / hub VNet). CIDRs must not overlap (the classic migration blocker). "Peering is for pairs; Transit is for constellations."

---

## Part 2 — Real Job-Specific Questions (architecture + day job)

**Q21. Design the networking for a production web app (AWS or Azure — your pick).**
→ VPC/VNet, 2–3 AZs: public subnet (ALB/AppGW), private subnets (compute), private (DB). IGW for the LB; no public IPs on instances. DB in its own subnets + security group that only allows the app tier. Egress for packages: NAT (AWS) or outbound rule (Azure) — or VPC endpoints/ExpressRoute for internal S3/Storage. Private DNS for internal services. Say the security groups per tier *and* why stateful return traffic makes it simpler than NACLs.

**Q22. How do you give a Lambda all the access it needs and nothing more?**
→ Role (assumed by lambda.amazonaws.com) with *only* the resources it touches, scoped: `Resource` = the specific bucket ARN (not `*`), condition where useful (`aws:SourceArn`), a KMS key grant if it touches encrypted data, and no `*` actions. Test it: run the function, watch CloudTrail for the exact API calls, trim the policy to match. "Least privilege is a measurement, not a vibe."

**Q23. Your S3 bucket has to be read by 4 services and a CDN, but never public. Design it.**
→ Private bucket (public access block on, always). Services: IAM (role ARNs in the bucket policy — principal-based, no keys), or better: service roles + `s3:GetObject` grants scoped to the prefix each service owns. CDN: Origin Access Control (S3→CloudFront) so the CDN's *identity* (not a key) reads it. Cross-account: a role the other account assumes. No presigned URLs unless a specific short-lived share is needed — and if so, < 15 min TTL.

**Q24. Design identity for 50 engineers: no standing prod access.**
→ SSO (AWS) / Entra ID (Azure) as the IdP, per-environment roles (dev/staging/prod), groups map to roles. Just-in-time elevation: a ticket + approval grants prod access for 8h, auto-revokes, and every session is recorded/audited. Break-glass: one emergency role, using it *pages everyone*. No personal IAM users in prod (the interview tells you: standing personal prod access = a failed interview).

**Q25. How do you observe a cloud service end-to-end?**
→ Three pillars + the glue: metrics (CloudWatch/monitor — latency, errors, saturation), logs (aggregated, queryable — CloudWatch Logs/Log Analytics), traces (X-Ray/App Insights — one request across 6 services). The glue: correlation IDs that flow from API → queue → worker → DB, and *business* metrics (signups, checkout) not just infra ones. Alert on SLOs, not on "CPU > 80" vibes.

**Q26. Cost: a service costs $40k/mo. You find 60% is data transfer. Why, and fix?**
→ Why: cross-AZ traffic (each request crossing AZs = charged), public internet egress, or a mis-routed architecture (app in one AZ talking to DB in another every request). Fix: co-locate app+DB in the same AZ *pair* (per-AZ deployment, route within AZ), VPC endpoints (S3/ECR traffic stays private + cheaper), CDN for static egress, and check for chatty APIs (N+1 calls multiplying transfer). "Data transfer cost is usually an *architecture* smell, not a rate problem."

**Q27. Multi-account (AWS) / multi-subscription (Azure) — how do you deploy across them?**
→ A platform pipeline in a central account with **cross-account roles** (each target account has a role the platform account assumes — trust policy by account ID, not `*`). The pipeline never holds target-account credentials; it *assumes* per deploy. State per target in that target's own backend bucket. Say why not shared root keys: "a shared key is a shared incident."

**Q28. How do you migrate a 500GB on-prem database to the cloud with < 1h downtime?**
→ AWS DMS / Azure DMS: initial full load, then *continuous replication* (CDC) until cutover. Cutover: freeze writes (maintenance window), let the replica catch up (lag → 0), switch the connection string (DNS or config), verify (row counts + spot checks), then cut the reverse flow off. The <1h is the *freeze-to-switch* window, not the whole migration. Fallback: if the replica lags, you extend the freeze (say the risk out loud).

**Q29. Design logging at scale (10k log lines/sec, 30 services).**
→ Ship: agents (Fluent Bit/Data Collection) → aggregated store (CloudWatch Logs/Log Analytics), structured JSON (never free text — you'll pay in query time), with service + request-ID + env fields. Retention tiers (hot 7 days, cold 90 in archive), sampled full logs + always-on errors/alerts, and *derived metrics* (log-based alerts for "ERROR rate in service X"). Cost control: don't store debug in prod; sample the verbose paths.

**Q30. What is a landing zone? What goes in it first?**
→ A pre-built, secure multi-account/subscription foundation: identity (SSO), networking (hub + spokes), security (centralized logging, guardrails), and a deploy path (IaC pipeline). First: **identity + logging + network** — because everything else needs to log in, be audited, and talk to each other. Then: guardrails (prevent public S3, required tags, allowed regions), then golden paths for services. "A landing zone is the *rails* the business runs on — build rails before trains."

**Q31. How do you keep a cloud environment compliant (SOC 2 / GDPR) operationally?**
→ Controls = code: IAM (no standing admin, JIT), encryption (at rest + in transit, enforced by policy), audit (Trail/Activity Log → SIEM, immutable), data (GDPR: where does PII live, right-to-erasure → a delete API that actually deletes, incl. backups — the hard part), and evidence (the pipeline *is* the evidence: change history, approvals, reviews). Say the GDPR trap: "backups and DR replicas are copies — erasure must reach them or you failed the requirement."

**Q32. A provider region is degraded (status page: "investigating"). Your app is in that region. What do you do?**
→ Confirm scope (is it the whole region or one AZ? which service?). If single AZ: traffic should already be failing over (multi-AZ LB/DB) — verify it is, and don't *add* changes to a degraded region (changes + degradation = chaos). If regional and you have a DR region: execute the failover runbook (DNS cut, DB failover, verify). If no DR: communicate (status page, ETA unknown), shed non-critical load, and *don't* try to "fix" the provider's issue from inside. "You can't fix AWS; you can only fail over or wait — decide which, and say it."

**Q33. How do you secure container workloads on a cloud (ECS/ACI/EKS)?**
→ Layers: IAM roles for tasks/ pods (no keys in env), network policies (default-deny between namespaces), image scanning (block unscanned/vulnerable at deploy), runtime (read-only rootfs, non-root, seccomp, drop caps), secrets from the vault (not env), and the registry itself (private, signed images, only signed images deploy). "Each layer catches what the others miss; one layer is a bet."

**Q34. Design an API for a mobile app: auth, rate limiting, versioning, offline.**
→ Auth: short-lived JWTs from an OAuth flow (or Cognito/Entra app), refresh token rotation, per-device. Rate limit per user + per token (not per IP — mobile NATs break IP limits), 429 with `Retry-After`. Versioning: URL version + additive-only policy (mobile can't hot-fix fast). Offline: the app caches + queues writes; your API must be *idempotent* (client-generated IDs) so queued replays don't duplicate. Say the mobile constraint explicitly: "you can't ship a fix in 10 minutes — the API's contract is the release mechanism."

**Q35. How do you do CI/CD for infra-as-code in a regulated company?**
→ Plan in PR (bot posts the diff — humans read what changes), policy gates (no public resources, required tags, region allow-list), a *reviewed plan file* gets applied (`plan -out` → approval → `apply -auto-approve planfile` — what was reviewed is what runs), audit trail of every apply (who, which commit, which plan), and change windows for prod network. "The plan IS the change order."

**Q36. Explain the difference between availability and durability. RDS numbers?**
→ Availability = "can I reach it now" (uptime %). Durability = "will my *data* survive" (replication). RDS: multi-AZ = high availability (synchronous standby, auto failover ~minutes) + 10 nines durability *for the data* (storage replicated across AZs). Say them separately: "a DB can be available and still lose data (single copy), or be briefly unavailable and lose nothing (multi-AZ failover gap = seconds)."

**Q37. What is a NAT gateway? Why do people forget it's expensive?**
→ Private subnets → internet (outbound only; no inbound). It's per-AZ, single-AZ (no cross-AZ), and costs: hourly + per-GB processed. Forgotten because: left running in dev (idle cost), oversized, or *cross-AZ NAT traffic* (a whole other fee) when the wrong subnet routes through it. "NAT is the most-common 'why is the bill high' line item."

**Q38. How do you test that a cloud architecture actually fails over?**
→ Don't trust the docs — test it: kill an AZ's worth of instances (or the whole app tier in a scratch account), fail the primary DB over on purpose (measure the *actual* failover time = your real RTO), cut DNS to the DR region, and load-test the DR region at full traffic (it's usually undersized — find out *now*, not at 3am). Game day twice a year, results in the postmortem, RTO/RPO re-measured. "A failover you haven't run is a hope, not a plan."

**Q39. Azure: how is networking fundamentally different from AWS (as a cloud engineer)?**
→ VNet vs VPC (similar), but: Azure's NSG (SG equivalent) + NSG rules + **NAT Gateway** (no NAT *instance* per se), **Application Gateway** (L7, the ALB equivalent) vs **Load Balancer** (L4), **ExpressRoute** (private cross-cloud/on-prem) vs Direct Connect, and **Peering is not transitive** (like AWS) → hub VNet or VWAN. Say it as "same concepts, different names + a couple of structural choices (AppGW does WAF in-product; AWS is CloudFront+WAF)."

**Q40. AWS: what's the difference between a CloudFormation stack and a Terraform state?**
→ CloudFormation: AWS-native IaC, a *stack* is the unit (create/update/rollback built-in, ChangeSets = plans). Terraform: multi-cloud, *state file* is the unit (remote backend + locking, import, modules). Both are declarative + diff-based. The real answer: "same job; Terraform is cloud-agnostic and has a stronger module ecosystem, CloudFormation is natively integrated (stack policies, drift detection, native rollback). I'd pick per org: all-AWS shop → CFN is fine; multi-cloud → Terraform." (You can say this from both sides — pick one and defend it.)

---

## Part 3 — Advanced Level (senior / design)

**Q41. Design a global SaaS: 3 regions, multi-tenant, payments + content.**
→ Data gravity decides placement: payments in the region closest to the *processor* + compliance (data residency — EU data stays EU), content/CDN global. Multi-region model: active-active for stateless web (any region serves), **active-passive per tenant** for data (each tenant pinned to one region — say why not active-active: sync complexity + consistency); failover per tenant (not global cutover). DNS: geo + latency routing, with health checks. Replication: cross-region read replicas for analytics, not for serving (say the consistency trade-off). Cost: egress between regions is the hidden tax — design the *queries* to not cross regions.

**Q42. Design identity + authorization for a multi-tenant B2B SaaS (SSO for enterprise customers).**
→ Tenant = customer org. Auth: SAML/OIDC SSO per tenant (their IdP → your SP), plus magic link/password for non-enterprise. Authorization: **RBAC per tenant** (roles scoped by tenant ID — every query carries the tenant; enforce in DB, not just app), SCIM for user provisioning/deprovisioning (the off-boarding path is where leaks happen). Say the two classic bugs: a query missing the tenant filter (cross-tenant read — catastrophic) and an admin role that's global instead of per-tenant. "Tenant isolation is a *database* problem first, an app problem second."

**Q43. Your app needs to process 1TB of files/day (upload → process → deliver). Design.**
→ Ingest: S3/Storage (multipart for big files, presigned URLs — never proxy bytes through your app). Event per object (S3 → SQS/Kafka) → processing workers (autoscaled; stateless; idempotent per object-ID) with per-stage queues (upload → process → deliver) so each stage scales independently. Durability: at-least-once + idempotent handlers + DLQ for poison objects (quarantine + alert, don't block the queue). Delivery: back to S3 (customer bucket via cross-account role) + a record in a "jobs" table (status, latency, retries) you can query. Cost: storage classes per stage (hot while processing, IA after 7 days), and *spot* for the stateless workers.

**Q44. Design a zero-trust network for a 200-engineer company.**
→ No implicit trust by location: (1) Identity: every engineer + every workload has an identity (SSO + workload identities/SPFs). (2) Workload-to-workload: service mesh (mTLS, per-service authorization — "payments can't read HR"), not just VPC rules. (3) Human-to-app: per-app access policies (attribute-based: role + time + MFA), just-in-time, session recorded. (4) Network: default-deny, least-privilege segments, and **egress control** (the data-exfil path) — DNS + proxy allow-lists. (5) Continuous verification (device posture, cert validity). "Zero trust = assume breach; the perimeter moves from the network to the identity."

**Q45. A legacy monolith (10 yrs, 2M LOC, COBOL-adjacent) must move to cloud. Strategy?**
→ Don't re-architect to migrate — **strangler fig**: (1) Lift-and-shift the monolith to cloud VMs/containers *as-is* (fast, low-risk, buys time). (2) Identify seams via traffic analysis (which endpoints are independent?). (3) Build new services *around* the monolith (API facade in front; carve one bounded context at a time — the most-changed one first), DB last (shared DB = the chain; extract per service). (4) The facade is the contract — old and new clients don't notice the surgery. Say the failure mode: "teams that re-architect *during* migration ship nothing for 2 years and lose the business's trust."

**Q46. Design a cost-governance system (not a one-time cleanup).**
→ (1) Attribution: tags enforced at creation (policy-as-code: no tag = no resource — a guardrail, not a request), per-service cost dashboards. (2) Baselines + anomaly alerts (per service, per env — "dev jumped 3x" pages the team, not finance). (3) Lifecycle: automated (dev stops at night, storage tiers, unattached volume reaper, orphaned snapshot reaper). (4) Committed use: RIs/savings plans on the *stable* baseline only (measured over a quarter), never on spiky. (5) Unit economics: cost per 1k requests / per user — the number engineering actually responds to. "Finance sees the bill; I want each team to see *its* bill and *its* unit cost."

**Q47. How would you design the network for a Kubernetes platform on AWS (EKS)?**
→ Two common models: (a) VPC CNI — pods take VPC IPs (simple, but pod density limited by subnet size — /23 minimum-ish per AZ for 1k pods; plan subnets *big*). (b) Overlay (Cilium/GKE-style) — pods get overlay IPs (dense, but egress/NAT + security differ). Say: node subnets sized for pod density + headroom, NAT per AZ (and the cross-AZ NAT cost when a pod in AZ1 talks NAT in AZ2 — keep pod→NAT in-AZ), security groups per node group (or network policies if overlay), and **the cluster is an endpoint**: private subnets, access via a bastion/SSM/LoadBalancer, never public node IPs. "K8s networking is VPC networking with a *pod density* tax — size for it or the cluster grows into its own subnets."

**Q48. A security finding: "your S3 bucket has public read." It's actually *meant* to be public (static site). How do you respond + prevent the class of finding?**
→ Respond: verify (is it *intended*? what's in it? any PII that shouldn't be?), document the *exception* (a ticket: "this bucket is intentionally public, reviewed by X on date, contains only static web content"), and add the compensating controls (versioning for accidental-overwrite recovery, a bucket policy that denies *write* to everyone, and a WAF/CloudFront in front if it serves app content). Prevent: the scanner finding is *correct* — the fix is not "make it private" (breaks the site) but **policy that knows the difference**: a tag `public-intended=true` that the guardrail exempts *and* that requires the review ticket, plus the scanner whitelisting *by tag with expiry*. "The best security answer is a *process* that makes 'intended' auditable."

**Q49. Design a data pipeline: on-prem → cloud → analytics, with < 24h RPO.**
→ Ingest: replicate the on-prem DB (DMS CDC) to the cloud in near-real-time (RPO ~minutes, not 24h — beat the requirement). Landing: raw zone (immutable, as-landed) → curated (transformed, validated) → serving (marts for BI/models). Each zone: separate storage, separate permissions, schema registry + contract tests (a bad transform is caught at the zone boundary, not in the dashboard). Lineage + data quality checks (freshness, volume, nulls — alert on "the number stopped moving" — the classic silent failure). "The 24h RPO is the *floor*; the CDC gives you minutes — spend the headroom on data quality."

**Q50. You must choose: AWS or Azure for a new product. Walk the decision.**
→ Framework, not a cheerlead: (1) Existing: where are the team's skills, the data, the customers (a Microsoft-embedded B2B → Azure; an AWS-native startup → AWS)? (2) Services that matter: the 3–5 services the product lives on — compare *those* (not all 400): e.g., "our DB is Postgres → Aurora vs Flexible Server/SQL DB — both fine, but the PaaS depth differs." (3) Ecosystem: the SaaS you're already buying (M365/Entra → Azure identity; existing AWS credits). (4) Cost model: run *your* workload in both (a 2-week PoC with real traffic — "I'd price it on our actual request pattern, not the calculator"). (5) Escape: abstract the cloud-dependent bits (IaC, secrets, LB) so the choice is reversible for 18 months. "The answer is the 3 services + the 2 constraints, not the logo."

**Q51. How do you design for a 10x traffic event (a product launch) on cloud?**
→ (1) Load-test at 10x *now* (find the ceiling before the crowd does). (2) Autoscaling with headroom (pre-scale before the launch, not just on metric — cold start + scale lag = the first 10 minutes are the risk). (3) Cache everything cacheable (CDN, app cache — the origin should see a fraction). (4) Rate limit + queue the non-critical (recommendations, analytics — shed load deliberately). (5) Circuit breakers on every external dependency (the payment processor's limit is *their* problem to absorb, not yours to crash on). (6) A runbook for "we're at 90% of the ceiling" (who turns what off, in what order). "The launch plan is the *shedding* plan — what dies first, and who decides."

**Q52. Design an event-driven architecture for order processing (order → payment → inventory → shipping).**
→ Events, not calls: `OrderCreated` → payment service (→ `PaymentCaptured` | `PaymentFailed`) → inventory (`InventoryReserved`) → shipping. Each step: consume (at-least-once) → process (idempotent by event ID) → publish next event → acknowledge. State: an order state machine (pending → paid → reserved → shipped) in a DB (the *source of truth*; events are the *trigger*). The hard parts, said out loud: **out-of-order events** (version the order state; ignore stale), **partial failure** (a saga: compensating events — `PaymentCaptured` then `InventoryFailed` → `PaymentRefunded`), and **replay** (events are append-only — you can re-drive the state). "The queue is the backbone; the state machine is the brain; idempotency is the immune system."

**Q53. A compliance requirement: "all PII must be encrypted and deletable within 72h." Design the delete path.**
→ The trap is *where copies live*: live DB, backups, DR replicas, search indexes, analytics, and *logs* (a log line containing an email is PII). Design: (1) PII tagged at the schema level (column-level, so "delete user X" = a defined query set). (2) A **deletion job** that sweeps all known stores (DB, replica, index, log redaction) and *verifies* (a re-query returns nothing) — with a receipt. (3) Backups: you can't delete inside a backup → the 72h is met by *not keeping PII in long backups* (or accepting the risk in writing — say it). (4) Logs: structured so PII is in a field you can redact, or a separate PII log with a short retention. "Deletion is a *multi-system transaction* — the 72h is only real if the slowest store is in the sweep."

**Q54. How do you observe an event-driven system (it has no obvious "request")?**
→ The unit of observation is the *event*, not the request: (1) Per-topic lag/depth (queue depth is the #1 signal — "the pipe is clogging"). (2) Per-consumer processing rate + error rate + DLQ depth (DLQ non-empty = a page, always). (3) Event *throughput* trends (a drop = upstream broke, even if consumers are healthy). (4) End-to-end: a synthetic event that must traverse the whole chain (OrderCreated → Shipped) with a latency SLO — the only thing that catches a *silent* break in the middle. (5) Idempotency/duplicate rate (a spike = a producer retrying = something upstream is sick). "In event systems, *absence* is the symptom: no events = no error logs = no alerts unless you alert on the absence."

**Q55. Design a hybrid architecture: on-prem datacenter + cloud, with a private link.**
→ ExpressRoute (Azure) / Direct Connect (AWS) = the private backbone (no internet for east-west). On-prem: the systems that *must* stay (regulated data, low-latency to a factory floor, legacy mainframe). Cloud: the elastic web tier + new services. The seam: a DMZ/VPC with a VPN or Direct Connect gateway, and **the decision matrix**: which data crosses (and it's encrypted + logged), which services call across (and the latency budget — a 5ms cross-link changes your call design), and the failure mode (the link dies → does on-prem fail over to cloud or stand alone? Say it). "Hybrid isn't 'both' — it's a *contract* between two networks, and the contract is the design."

---

## Part 4 — Scenario-Based (real-time)

**S1. The cloud bill is 3x this month and finance is paging. 4pm, you have 1 hour. Go.**
→ (1) **Stop the bleeding, don't cut yet**: is it *new* (a new service/env someone spun up) or *grown* (traffic 3x)? Cost Explorer → top line items *this month vs last* — the delta, not the total. (2) The 3x is usually *one* thing: a dev left a 16-vCPU cluster running, a cross-AZ NAT storm, an S3 lifecycle that expired, or a spot→on-demand flip. Find the delta line item (10 min). (3) If it's a runaway *compute*: stop it (with the team's OK if it's theirs) — that's a reversible 1-click. If it's *structural* (data transfer): document it, don't yank it out at 5pm. (4) Tell finance a number + a cause + a fix ETA in the first 30 min (not at the end). (5) Next day: the tag/guardrail that would have caught it (cost anomaly alert per env). "3x is almost never 30 small things — it's one big thing. Find the one."

**S2. A customer reports "your API is down" at 9am. Your dashboards say healthy. What's going on?**
→ Dashboards healthy + customer down = **you're not measuring what the customer experiences**. Check: (1) *their* path — are they a specific region/tenant/device? (a regional DNS issue, a CDN edge, a specific auth provider being slow). (2) The *edge* — the LB/CDN/API gateway (your "service" is up but the *door* is jammed: TLS handshake, a WAF rule that started blocking their traffic, a cert that expired at the edge). (3) A *specific* integration they depend on (their IdP, their webhook). (4) Synthetic monitors from *their* geography (your monitors are all in one region). (5) Recent change *at the edge* (a WAF rule, a CDN config) that "healthy" dashboards don't cover. Say it: "the gap between 'service up' and 'customer up' is where the monitoring debt lives — I'd add a customer-path synthetic the same week."

**S3. You're asked to stand up a new production environment in 3 days (not 3 weeks). How?**
→ (1) Day 1: reuse, don't build — the existing IaC modules + landing zone + a copy of the prod config *parameterized* for the new env (the whole point of IaC is this is a morning). (2) Day 1: the non-negotiables only — identity (SSO + least-priv roles), networking (2 AZs, private subnets), logging (Trail/Activity → central), and the data store. (3) Day 2: deploy the app via the *standard pipeline* (not a hand-rolled script — a hand-rolled prod env is a future incident), with the canary/health gates. (4) Day 2: the 3 things that make it *prod* not *staging*: the SLO + on-call (who gets paged?), the backup + a restore test, and the rollback path. (5) Day 3: a go/no-go checklist with the app owner (not just infra: "does the business flow actually work end-to-end?"). Say the trade-off: "3 days means I'm borrowing from the *standard* — anything I hand-roll is a named debt with a paydown date."

**S4. Your prod RDS is at 90% storage and growing 5GB/day. It'll be full in 6 days. Plan.**
→ (1) **Today**: what's filling it — `pg_stat`/`sys.dm` space (table growth? bloat? a runaway log table? a `TEMP` that's not temp?). The fix differs: table growth (archive/partition it), bloat (VACUUM/`OPTIMIZE`), a log table (add a retention job). (2) Buy time *now*: RDS storage is expandable online (grow it 2x today — it's the cheapest 30-min action and removes the 6-day clock). (3) Fix the growth: lifecycle (move old partitions to S3/IA), and a *storage SLO* (alert at 70%, page at 85% — you found it at 90% because there was no 70% alert). (4) The real question: is this *expected* growth (then the design is "grow storage + archive," a recurring cost) or a *bug* (a table that should be bounded isn't)? Answer that and you've solved the next 5 years, not the next 6 days.

**S5. A junior deleted the wrong resource in prod (an S3 bucket with 2 years of user uploads) via console. They're scared and silent. What do you do when they finally tell you (2h later)?**
→ (1) **First, de-escalate the person**: "good that you told me — now let's fix it." (2) **Is it really gone?** S3 has *versioning* — if it was on (it should have been), the objects are in previous versions / the bucket's deletion may be recoverable via support if within the window. Check the bucket policy + versioning state *before* assuming loss. (3) **Scope it**: what's actually missing, is anything still writing to the (now-gone) bucket, are backups (another bucket, a replica) intact? (4) **Communicate up** with the scope + the recovery path (not the blame) — the manager needs to know the data impact, and the junior telling you 2h late is *less* bad than 2 days late; don't punish the 2h. (5) **Prevent the class**: console write-access in prod is the root cause → move to read-only + IaC-only writes + a break-glass; and versioning + cross-region replication on all user-data buckets (a policy, not a request). "The 2-hour delay is a symptom of *fear*, not malice — I fix the fear (psychological safety) and the access (the real hole) together."

**S6. You must migrate from CloudFormation to Terraform (or vice versa) for a service that can't have downtime. Plan.**
→ (1) **Adopt, don't recreate**: `terraform import` (or CFN's `template` from existing) to put the *live* resources under the new tool — zero downtime, and the first diff should be *near-empty* (if it's not, you've found drift — fix that first, it's the gift). (2) **The seam**: both tools point at the same resources for a window? No — *one* owns the state at a time. Do it per-service: import the service's resources, verify a `plan` is empty, then flip ownership (delete the CFN stack *after* TF's plan is empty, never before). (3) **The contract**: a "state handoff" doc — what TF now owns, what's still CFN, and the rule "the tool that imported it owns it." (4) **Rollback**: during the window, the old tool's state is still there (don't destroy it until the new one has *deployed* at least one change successfully). (5) Order by risk: migrate a stateless service first (prove the process), the data tier last. "The migration's risk isn't the new tool — it's the *state handoff*. An empty plan on both sides is the only safe moment to switch."

**S7. A dependency you rely on (a 3rd-party API) is degrading (p99 up 4x) and it's degrading *your* SLO. You can't fix their service. What do you do?**
→ (1) **Contain**: circuit breaker on the dependency (stop sending it traffic when it's sick — fail fast, don't let its latency pile up your thread pool/queues). (2) **Degrade gracefully**: what does the *product* do without that dependency? (show cached/stale data, disable the feature that needs it, queue the work for later) — the feature flag to turn it off is your emergency valve. (3) **Protect the rest**: rate-limit *your* calls to them (their degradation shouldn't consume all your capacity — a token bucket on the egress). (4) **Communicate**: to the users (degraded mode, not "down") and to the vendor (the SLA, the incident, your data). (5) **After**: is this dependency *critical-path*? If so, it needs a fallback (a second provider, or an async/offload path) — "a single 3rd-party in the critical path is a 4th AZ that you don't control."

**S8. Your IaC says "12 resources to replace" after a provider upgrade. Nothing changed in your code. What happened?**
→ (1) **Don't apply.** A provider upgrade changing the plan = the provider's *behavior or naming* shifted (a default it now sets, a property it now returns, a deprecation that forces a new arg). (2) Read the *why* in the plan (the "because" lines) — is it a true change (a property that genuinely differs → a real, maybe-needed, replace) or a *representation* change (TF now sees a value it didn't before → often a no-op in reality, and the fix is `ignore_changes` or a pinned version, *not* a 12-resource replace)? (3) **Pin and bisect**: revert the provider to the last-good version (it's in the lock file) to confirm, then upgrade in a staging state and read the diff *there*. (4) The 12 replaces are the red flag: a provider upgrade that replaces 12 prod resources without a code change is a **stop-the-world** — page the platform team, hold the upgrade, and treat it as a provider-release incident. (5) Prevent: upgrade providers *in staging first*, with a "plan must be ≤ N changes" gate, and read the provider's changelog for the specific version. "A provider is a dependency — and a dependency that can replace your prod is the scariest kind."

**S9. You inherit a cloud account with 400 resources, no tags, 3 unknown buckets, and a $15k/mo bill with no owner. First 2 weeks.**
→ (1) Week 1: **attribute before you optimize** — CloudWatch/Cost Explorer → map the top 20 cost items to *something* (the instance name, the subnet, the bucket). The 3 unknown buckets: peek (what's in them? owner? last access? — `s3 ls` + last-access logs), don't delete yet. (2) **Freeze the unknown**: the 3 buckets → a "quarantine" tag + a 30-day lifecycle (move to Glacier, don't delete — deletion is irreversible, quarantine is not). (3) **Baseline the bill**: this month's $15k is the *before* — tag everything you can (a tagging campaign, enforced going forward by policy: no tag = no create). (4) **Find the owner**: the top 5 line items → the team that created them (CloudTrail: who/when) → a 15-min "here's your cost" conversation (this is where you find the forgotten experiment costing $6k/mo). (5) Week 2: the 2 quick wins (stop the forgotten thing, rightsize the top item) + the guardrails (tag policy, cost alert per tag, a "new resource > $X/mo" alert). "400 untagged resources means *nobody owns this account* — my first deliverable isn't savings, it's *attribution*, because savings without ownership just regrows."

**S10. The CTO asks: "are we cloud-native or just 'in the cloud'?" Give an honest 2-minute answer with an example from a real system.**
→ "In the cloud" = running VMs you could have run on-prem (lift-and-shift, same architecture, same ops). "Cloud-native" = using the cloud's *different* capabilities to change the *design*: stateless + autoscale (you can't do that on a fixed server farm), managed datastores (you stop being a DBA), event-driven (queues decouple what used to be synchronous calls), and **infra-as-code** (the environment is a deployable, reviewable artifact). The honest test: *"could we have built this on 10 racks in a basement?"* If yes → in the cloud. If the design *requires* the cloud (elastic scale, managed PaaS, global edge) → cloud-native. The honest example: "our web tier is cloud-native (stateless, autoscaled, managed LB) but our data tier is 'in the cloud' (a fixed-size RDS we treat like a server) — and that's the honest gap: the next cloud-native move is making the data tier elastic too." (The senior answer *names the gap*; the junior answer says "we're very cloud-native.")

---

## Part 5 — Questions to ask the interviewers

- "What's the most-surprising cost line item you've had to explain to finance?" (reveals cost maturity)
- "When the last regional degradation happened, what did your failover actually do — and what was the measured RTO?"
- "What's the one resource in prod that's still not in code, and why?"
- "How do you handle a customer whose data must stay in a specific country — how does that shape your architecture?"
- "What's the biggest 'we just lift-and-shifted this' decision you'd reverse if you could?"
