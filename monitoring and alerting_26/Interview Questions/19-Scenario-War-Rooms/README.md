# 19 · Scenario War Rooms

Long-form, multi-domain scenarios — the "here's a live situation, talk me through it" round that decides senior offers. Each one is written as **the situation → what they're scoring → the model answer → the follow-ups they'll ask**.

**How to run any of these live:**
1. **Clarify before you solve** (30–60 seconds). Ask 2–4 questions that would change your answer. *Never* start designing on assumptions you could have checked.
2. **State your method** in one sentence: "I'll scope it, correlate with change, localise, then mitigate and root-cause."
3. **Think in layers, out loud.** Name what you'd check and what each result would tell you.
4. **Mitigate before you understand.** In an incident scenario, restoring service is the job.
5. **Quantify and bound.** "About 40 minutes of budget at 99.9%", "~1 GB/s, so ~86 TB/day".
6. **Trade-offs, always.** Every decision costs something; say what.
7. **End with the systemic fix.** What changes so this can't recur — and how you'd verify it.

---

## War Room 1 — "Production is down and nobody knows why"

### The situation
> "It's 14:07. Monitoring shows the checkout API error rate jumped from 0.1% to 34% at 14:02. Latency p99 went from 300 ms to 8 s. Everything else looks normal — CPU, memory, and node health are all green. There was a deploy at 13:40, but the error rate didn't move until 14:02. You're the senior engineer on the incident. Go."

### What they're scoring
Whether you **mitigate fast**, whether you notice the **22-minute gap** (the most important clue in the scenario), whether you use **structured diagnosis** instead of guessing, and whether you **run the incident** (roles, comms) rather than just debugging.

### Model answer

**Minute 0–1: Take command and scope.**
> "First I declare SEV1 and assign roles out loud — I'm IC, I'm not debugging; one person on ops with me, one on comms and the timeline. If I'm alone I say so and pull someone in, because an IC who's also debugging and also answering Slack runs a longer incident.
> Then three scoping questions, answered in under a minute: **which percentile and what proportion?** 34% of all requests, or 100% of one region/tenant/client version? **Which endpoints?** All of checkout, or one path? **Since exactly when?** 14:02, sharp, not gradual."

**The clue that matters most:**
> "The 22-minute gap between the deploy at 13:40 and the failure at 14:02 is the single most important fact here, and it argues **against** the deploy being the direct cause — or at least against it being a straightforward bad-code regression, which fails within seconds of the rollout. A delayed failure usually means one of:
> - something **exhausted or expired** at 14:02 (a connection pool, a cache, a token/certificate, a rate-limit quota, a lease, disk space, a queue backfill catching up),
> - a **threshold crossed** (traffic ramped past a limit, a table grew past a tipping point, an autoscaler hit its max),
> - a **delayed effect of the deploy** (a cache that was populated at 13:40 with a 22-minute TTL; a migration that ran async; a new code path that only triggers on a rare condition; a connection leak that takes 20 minutes to exhaust the pool),
> - or **something entirely unrelated** that coincided (a downstream dependency, a cloud event, a batch job, a traffic source).
> So my first action is not 'roll back' — it's 'what else happened at 14:02?', because rolling back the deploy won't fix a dependency that died, and I'll have wasted 10 minutes."

**Minute 1–4: Correlate with change, broadly.**
```bash
# What changed at ~14:02, across every system, not just the app?
kubectl get events -A --sort-by=.lastTimestamp | tail -40
kubectl rollout history deploy/checkout -n prod        # deploy timeline per replica
# Config, flags, migrations, IaC applies, cert rotations, DNS changes,
# dependency releases, batch jobs, autoscaling events, cloud provider events
```
Plus: **is the error rate the same on old and new pods?** If the pods from the 13:40 deploy are failing and the older ones aren't, it *is* the deploy. If both are failing, it's shared — a dependency, config, or infrastructure. **This one check resolves the deploy question in 30 seconds and it's the thing most people forget.**

**Minute 2–6: Localise with the data that's already there.**
> "CPU, memory and nodes are green, which is genuinely informative: it says this is **not saturation**. So I look for **waiting**, not working. Four checks in parallel:
> 1. **Read the actual error.** `kubectl logs deploy/checkout --tail=200 | grep -i error` — is it a timeout, a connection refused, a pool-exhausted error, a 5xx from a downstream, a TLS error, a DNS failure? **The error text usually names the cause.**
> 2. **Open one slow trace.** p99 at 8 s means something is waiting 8 s. A trace shows which span. **8 seconds is a suspiciously round number** — it smells like a timeout (two 4-second retries, or a 5-second DNS timeout plus a 3-second connect), and timeouts point at a dependency, not at our code.
> 3. **Check every dependency's latency and error rate** — database, cache, the payment provider, auth, inventory. A slow database presents as slow checkout with green CPU everywhere.
> 4. **Check pool saturation**: DB connection pool utilisation and wait time, HTTP client pool, thread/goroutine count, open file descriptors. **A leak that exhausted the pool at 14:02 fits every symptom perfectly** — green CPU/memory, rising latency, rising errors, and a delay after the deploy."

**Minute 6–10: Mitigate with the cheapest reversible lever.**
> "Once I have a hypothesis I mitigate, and I keep mitigation separate from understanding:
> - **If it's the deploy**: `kubectl rollout undo` — two minutes, fully reversible, and if I'm wrong I've learned that cheaply.
> - **If it's a connection/thread leak**: roll the pods one batch at a time (which restores service while preserving one pod for evidence — **capture a goroutine/thread dump and a heap profile first**), then fix the leak.
> - **If it's a downstream dependency**: circuit-break it, degrade gracefully (serve cached/default), or shed the affected feature behind a flag. **Protect the 66% of requests that still work.**
> - **If it's saturation of a shared resource**: raise the limit as a band-aid, scale out, and note the debt.
> - **If it's a traffic event**: rate-limit the offending source.
> I define the success criterion *before* I act — 'error rate below 0.5% for five consecutive minutes' — so 'is it fixed?' isn't a debate."

**Minute 10+: Verify, communicate, preserve.**
> "Verify with evidence, not hope. Communicate every 15–20 minutes including when there's nothing new — silence generates more escalations than bad news. Preserve the evidence: logs from the failing pods, dumps, trace samples, metric screenshots, the timeline from the scribe. **Then** restart or roll back, because a restart destroys the crime scene and if I don't capture it I'll be back here next week.
> And I don't declare resolved at the first green metric — I watch for the second-order effects: the retry backlog draining (which can cause a second spike), caches rebuilding, queues catching up, connection storms."

**Then the systemic work:**
> "In the post-incident review I'd focus on three things: **why detection took until 14:07** (five minutes is fine, but was it monitoring or a customer?); **why localisation took N minutes** (was there a trace? was the dependency's latency on the dashboard? was the deploy annotated?); and **what guardrail would have prevented it** — a canary with automated analysis would have caught a deploy-caused regression at 5% traffic instead of 100%, a pool-saturation alert would have caught a leak before it became an outage, and a connection-pool metric on the service dashboard would have made localisation instant. **The 22-minute gap is also a finding: our deploy verification window is too short. A canary that only watches for five minutes will never catch a slow leak.**"

### Follow-ups they'll ask
- **"What if the traces show the app itself is slow, with no slow dependency?"** → GC pauses (check pause histograms and frequency), lock contention (mutex/block profile), a synchronous call added in the hot path, a logging statement in a loop, allocation churn, CPU throttling despite "green" average CPU (**check `container_cpu_cfs_throttled_periods_total` — averages hide throttling**), or a single hot partition/key.
- **"What if rolling back doesn't fix it?"** → Then it's not the deploy: a shared dependency, a config change, a migration that already ran (**and now rollback may not be safe — check schema compatibility before undoing**), or an external event. Also consider: the rollback itself may be failing (an image pull issue, a resource constraint).
- **"What if it's only one region/AZ?"** → AZ-level: a cloud provider event (check the status page early), a network partition, a node pool exhausted in that AZ, a zonal database replica, or a regional dependency. Consider failing traffic over while you investigate.
- **"How do you decide between mitigating and investigating?"** → By blast radius and reversibility. If customers are affected and a reversible mitigation exists, mitigate now and investigate the preserved evidence after. If mitigation is risky (a database failover, a full-region shift) I need enough confidence first — which is when the 10-minute investigation is worth it.
- **"What's your communication plan?"** → Internal channel with a pinned summary, updates on a 15–20 minute cadence, a status page if customer-facing, an exec summary at 30 minutes and hourly, and a named comms lead so the IC isn't interrupted.

---

## War Room 2 — "Design the platform" (greenfield)

### The situation
> "We're a 60-person startup, 25 engineers, 6 product teams. Everything runs on three EC2 instances with a bash deploy script. We deploy twice a week, it takes an hour, and it breaks about a third of the time. We just raised a Series B and expect 5× traffic and 3× headcount in 18 months. You're our first platform hire. What do you do?"

### What they're scoring
Whether you **sequence by value**, whether you resist **over-building**, whether you understand that a platform is a **product with users**, and whether you can justify each choice with a cost/benefit rather than a fashion.

### Model answer

**First, clarify (and say why each question matters):**
> "Before I propose anything, four questions:
> 1. **What breaks when it breaks?** Is the deploy failure a broken build, a broken runtime, or no rollback? That tells me whether the problem is CI, packaging, or process — and they have very different fixes.
> 2. **What's the compliance picture?** SOC 2, PCI, HIPAA? If SOC 2 is on the roadmap for sales, that changes the priority order completely — access control, audit logging and change management move up.
> 3. **What's the workload shape?** A stateful monolith, 6 services, or 40? Monolith or microservices? Which languages?
> 4. **How many platform engineers will there be — me, or a team?** Everything I recommend scales with that answer. **One person cannot run Kubernetes, a service mesh, a CI system, an observability stack, and an infra module library.**"

**Assume:** one stateful-ish monolith plus 5 services, mostly Python/TypeScript, no compliance deadline yet but SOC 2 in 12 months, and **me alone for the first 6 months**.

**The operating principle I'd state up front:**
> "With one platform engineer, my job for the first six months is **not** to build a platform — it's to remove the three things that cost the most engineering time, using managed services and open source, and to establish the conventions that will make the platform buildable later. **The thinnest viable platform here is: a CI pipeline, containers, a managed orchestrator, GitOps, and observability defaults.** Everything else is a distraction until we have more people or more pain."

**Phase 1 (weeks 1–4): Make deploying safe and boring.**
- **Containerise everything** (multi-stage Dockerfiles, a hardened base image, `--init`, exec-form entrypoint, non-root, resource limits). This is the prerequisite for everything else and it also fixes "works on my machine".
- **CI**: GitHub Actions with lint → unit tests → build → scan (Trivy + gitleaks + Semgrep) → push by digest → sign. **Cache aggressively; target under 10 minutes.**
- **Managed Kubernetes (EKS/GKE)** — not because we need it, but because **self-managed control planes and self-managed EC2 fleets are the two things a one-person platform team cannot operate reliably**. Managed costs more and saves a hire.
- **GitOps (Argo CD)** from day one: manifests in Git, an agent in the cluster pulling, drift detection on, **`git revert` as the rollback**. This is the single change that fixes "deploys break a third of the time and we can't undo them".
- **Rolling updates done properly**: readiness/startup/liveness probes (three different endpoints), `maxUnavailable: 0`, `preStop` sleep, PDB, and a `terminationGracePeriodSeconds` that covers the drain.
- **The result I'd target**: deploy from an hour to under 10 minutes, failure rate from 33% to under 10%, and rollback in one command. **That's the credibility that makes everything after it possible.**

**Phase 2 (weeks 5–10): See everything.**
- **Observability defaults**: Prometheus + Grafana + Loki + Tempo (or a vendor if we'd rather pay than operate — with one platform engineer, **I'd genuinely consider Grafana Cloud or Datadog for the first year**, and I'd say that out loud rather than defaulting to self-hosting on principle).
- **A shared instrumentation library** per language so every service gets RED metrics, trace propagation, structured logging with `trace_id`, and health endpoints by importing one package. **This is the highest-leverage thing I can build** — it turns six efforts into one.
- **One standard service dashboard** (templated, variable-driven) + **deploy annotations** in Grafana.
- **~10 alerts to start**, all symptom-based with runbooks: target down, error rate, latency, CrashLoop, node NotReady, cert expiry, disk will fill. **Fewer, better alerts beat 200 noisy ones; I can always add.**
- **An on-call rotation that's humane**: two people minimum with a secondary, compensated, ≤ 2 pages per shift as a target, weekly triage where we delete anything that produced no action.

**Phase 3 (weeks 10–16): Make the cloud safe and cheap.**
- **IaC everything** (Terraform/OpenTofu) with remote encrypted state, locking, per-environment states, and CI that fails on `-/+ destroy and then create replacement` for tagged-critical resources.
- **A landing zone**: separate accounts/projects per environment, SSO (no IAM users), **OIDC federation for CI instead of stored keys**, SCPs/Org Policy denying the destructive and public-exposure actions, a central log-archive account with immutable CloudTrail/audit logs.
- **Secrets**: no static keys anywhere — workload identity (IRSA/Pod Identity), External Secrets Operator, and **no secrets in Git or in Terraform state**.
- **Kubernetes hardening**: Pod Security Admission `restricted`, Kyverno policies (approved registries, no `latest`, requests required, no privileged, signature verification), default-deny NetworkPolicy, no SA token automount by default.
- **Cost**: tagging enforced, budgets with forecast alerts, Cost Anomaly Detection, gp3, S3 gateway endpoints, non-prod shutdown at night. **At 5× traffic this is a real line item, and setting it up now is cheap.**

**Phase 4 (months 4–6): The golden path and self-service.**
- **A service template** that generates: repo, CI, Dockerfile, Helm chart, IaC for baseline resources, dashboards, SLO, alerts, runbook stub, on-call registration, docs. **Target: a new service in production in under a day.** With 3× headcount coming, this is the difference between onboarding taking a week and taking an afternoon.
- **A Terraform module library** for the 6 things teams actually need, with secure defaults baked in.
- **Ephemeral preview environments** for PRs — but only if the cost and the data problem are solved; otherwise a shared, resettable staging environment. **I'd be honest that this is the first thing I'd cut if time ran short.**
- **A service catalogue** (`catalog-info.yaml` in every repo: owner, tier, runbook, on-call, dependencies). With 25 engineers it feels like bureaucracy; with 75 it's the only way anyone knows what exists. **Backstage only once the capabilities exist to put in it** — a portal over nothing is a demo, not a platform.
- **Progressive delivery**: Argo Rollouts canary with automated Prometheus analysis and auto-rollback, for the services that matter.

**Phase 5 (months 6–18): Scale the team, not just the tech.**
- **Hire**: a second platform engineer around month 6 (argue for it with the ticket volume and the delivery numbers), and an SRE/security-minded engineer when SOC 2 work starts.
- **SOC 2 preparation** starting around month 9 — evidence generated automatically from GitOps history and policy checks, access reviews from cloud audit logs, and the controls encoded as code so the audit is a review of a live system.
- **Reliability maturity**: SLOs on the critical journeys with error-budget policy, quarterly game days, a tested backup/restore and a tested rebuild-from-Git procedure, capacity planning for the 5× traffic (**including the database, which doesn't autoscale**), and quota audits (a silent quota limit discovered during a traffic spike is a horrible way to find out).
- **Deprecate and prune**: kill what isn't used, consolidate duplicates, document the escape hatches.

**What I would explicitly not do (and why):**
- **No service mesh in year one.** With 6 services and one platform engineer, Gateway API + a shared client library + NetworkPolicy + cert-manager gets 80% of the value at 10% of the operational cost. **A mesh without an owning team is a mystery layer everyone blames.**
- **No bespoke internal tooling.** No custom deploy system, no custom CI, no custom portal. Assemble open source and managed services; the *integration* is the platform.
- **No microservices mandate.** Splitting further with 25 engineers creates a distributed monolith. I'd make the existing boundaries clean rather than creating new ones.
- **No big-bang migration.** Every phase runs alongside the old way until it's proven, and teams move when it's faster — not when I say so.
- **No mandate without a benefit.** The rule I'd enforce from day one is only that **new** services start on the platform; existing ones migrate when the path is demonstrably better and I've helped them.

**How I'd measure myself:** deploy lead time and frequency, change failure rate, time-to-first-deploy for a new service, on-call pages per shift and % actionable, incident MTTR, % of services with an owner/dashboard/SLO/runbook, self-service success rate, cost per service, and a **quarterly anonymous developer survey**. **And the meta-metric: are 25 engineers shipping faster than they were? If not, none of the architecture matters.**

### Follow-ups they'll ask
- **"What if the CTO insists on Kubernetes from day one?"** → Fine, it's what I'd choose anyway — but I'd insist on *managed* Kubernetes and I'd push back on anything beyond that (a mesh, custom operators, multi-cluster) until there's a measured need and someone to own it.
- **"What if you had three engineers instead of one?"** → Then I'd parallelise: one on CI/CD and GitOps, one on observability and reliability, one on cloud foundation and security — and I'd bring the golden path forward to month 3 and add the mesh/security depth earlier. **The sequencing is driven by headcount, not by preference.**
- **"What's the first thing you'd cut if you ran out of time?"** → Preview environments and progressive delivery. They're high-value but they're refinements; safe deploys, observability, and a secure cloud foundation are not negotiable.
- **"How do you handle a team that refuses to containerise?"** → Find out why — usually a real blocker (a stateful workload, a native dependency, a licensing constraint). Then either solve the blocker, provide a supported alternative path (a managed service, a VM with configuration management), or accept the deviation with documented extra responsibility. **Forcing it costs more than it saves.**
- **"Build vs buy the observability stack?"** → With one engineer: **buy** (Grafana Cloud or Datadog) for year one, with OpenTelemetry instrumentation so the *data* is portable and we can self-host later if cost demands it. **Instrument with OTel, store wherever — that's the reversible part.**

---

## War Room 3 — "The migration"

### The situation
> "We need to move 40 services from a hand-managed EC2 fleet with Capistrano deploys onto Kubernetes, without stopping feature delivery, in 9 months, with 3 platform engineers and no budget for contractors. Plan it."

### What they're scoring
Whether you understand that migration is **change management**, whether you can **sequence and fund** it realistically, whether you know the **hard 20%** (state, data, hidden dependencies), and whether you'd push back on the constraints.

### Model answer

**First, negotiate the constraints — respectfully and with numbers:**
> "Three things I'd want to establish before committing to a plan, because they change it fundamentally:
> 1. **What's the actual goal?** Is it 'Kubernetes' (a means) or 'faster, safer delivery and lower cost' (the end)? If it's the latter, some of the 40 services might be better served by a managed service (ECS/Fargate, Cloud Run, a SaaS) than by Kubernetes, and I'd rather migrate 25 well than 40 badly.
> 2. **Is 9 months a deadline or a target?** If it's contractual or tied to a datacenter exit, I plan for it. If it's aspirational, I'd propose a phased target: 30 services in 9 months, the hard 10 in the following quarter.
> 3. **What capacity do the product teams have?** 'No budget for contractors' is fine, but if the platform team does all the work, 3 engineers × 9 months = 27 engineer-months for 40 services ≈ 2.5 weeks each **with zero time for building the platform itself**. That arithmetic doesn't work, so either the teams contribute capacity, or the platform team builds tooling that makes migration nearly automatic, or the scope shrinks. **I'd rather have that conversation now than in month 7.**"

**The strategy — four decisions that shape everything:**
1. **Make migration cheap, not mandatory.** The only way 40 services move with 3 platform engineers is if each migration costs the *product team* hours, not weeks. So the first two months are spent building the machine: a standard Helm/Kustomize chart, a CI template, a GitOps app template, an observability bundle, an infra module, a migration guide, and a **migration tool** that generates 80% of the manifests from the existing service's config. **Platform effort front-loaded; migration effort distributed.**
2. **New services on Kubernetes from day one.** This stops the backlog growing and it's free. **A migration without this rule is a treadmill.**
3. **Migrate by value and risk, not by count.** Order: (a) the services with the worst deploy pain and the most enthusiastic owners — they'll be the pilot and the advocates; (b) high-churn services, which benefit most; (c) stateless services, which are easy; (d) the complex/stateful ones last, when the process is proven and the tooling is mature. **Never start with the riskiest service — you'll learn the hard lessons on something that matters most.**
4. **Strangler-fig per service, with dual-running.** Old and new paths run in parallel, traffic shifts progressively (5% → 25% → 50% → 100%) with automated rollback on SLO breach, then the old path is decommissioned. **Budget for 2–4 weeks of dual-running per service — that's real cost (double infra) and it's non-negotiable for safety.**

**The plan:**

| Phase | Months | Work | Exit criteria |
|---|---|---|---|
| **0. Foundation** | 1–2 | Build the platform *for one service*: cluster(s), CI template, GitOps, observability defaults, secrets, hardening policies, the golden-path chart, and the migration tooling. Migrate **2 pilot services** end-to-end with the platform team doing most of the work | 2 services in prod on K8s; deploy lead time and incident count measured; **the migration guide is written from what we actually learned** |
| **1. Prove and publish** | 3 | Iterate the tooling on the pilots; publish before/after numbers; run a migration workshop; recruit 3 volunteer teams | 5 services migrated; volunteers signed up; **a documented effort estimate per service type** |
| **2. Wave migration** | 4–7 | 4 waves of ~6 services. Each team owns its migration with platform pairing for the first one. Platform team runs weekly office hours and unblocks | 29 services migrated; **migration is now a team activity, not a platform activity** |
| **3. The hard tail** | 7–9 | The stateful, high-risk, and complex services — with dedicated design per service, extended dual-running, and a rollback plan for each | 40 services migrated, or a documented, agreed list of services staying behind with reasons |
| **4. Decommission** | 9+ | Turn off EC2 fleet, Capistrano, old CI, old monitoring. **Verify the cost actually dropped** | Old infra gone; savings realised; retro published |

**The per-service process (what each team actually does):**
```
1. Assess (30 min with a checklist): language, dependencies, state, config, ports, cron jobs,
   background workers, file storage, external DNS, DB connections, special OS packages,
   startup time, memory profile → produces an effort estimate and a risk list
2. Make it 12-factor (usually the real work): externalise config to env/ConfigMap,
   stateless sessions, log to stdout, graceful SIGTERM handling, health endpoints (livez/readyz),
   no local filesystem writes (or an explicit volume)
3. Containerise: multi-stage Dockerfile, hardened base, non-root, resource requests/limits
4. Generate manifests with the migration tool → chart + GitOps app + dashboards + alerts
5. Validate in a non-prod environment: functional tests, a load test at production shape,
   a failure test (kill a pod, kill a node, exhaust the pool) to verify probes/PDB/rollout behaviour
6. Discover hidden dependencies: traces, DNS query logs, VPC flow logs, and the existing
   load balancer config — NOT a survey of what people remember
7. Dual-run in prod, mirror or split traffic, compare error rate/latency/cost for a soak period
8. Shift traffic progressively with automated rollback
9. Decommission the old path, update DNS/docs/on-call, verify cost dropped
10. Retro: what was hard? → feeds the tooling and the guide before the next wave
```

**The hard 20% — where migrations actually fail (name these):**
- **State and data**: local file storage → S3/EFS; local caches → Redis; **database connection counts** (40 services × 20 connections against a Postgres with `max_connections=100` is an outage — so **RDS Proxy or PgBouncer is part of the platform, not an afterthought**); sticky sessions → externalised state.
- **Long-running and scheduled work**: cron jobs on the EC2 host → Kubernetes CronJobs (with concurrency policy, timezone handling, and monitoring — **a silent CronJob that stopped running is a nasty failure**); background workers → Deployments with their own scaling.
- **Batch/long-lived processes**: a 6-hour job doesn't fit a rolling-update model; needs a Job with backoff, checkpointing, and a grace period longer than the runtime.
- **Networking and identity**: hardcoded IPs and hostnames, `localhost` dependencies between co-located processes (now separate pods — **needs a sidecar or a refactor**), firewall rules that assumed the EC2 security group, service discovery via DNS or Consul, and **client IP preservation** (X-Forwarded-For chains, proxy protocol).
- **Performance surprises**: sidecar/mesh overhead, different instance types, container CPU throttling from a mis-set limit (**set requests, be careful with CPU limits**), DNS `ndots` amplification, image pull time on cold nodes, and JVM/Go runtimes that read the *node's* resources instead of the container's (**`GOMEMLIMIT`/`GOMAXPROCS`/`MaxRAMPercentage`** — a migration-specific class of bug).
- **Operational knowledge**: the on-call team must be able to debug the new path *before* cutover — updated runbooks, a game day, and a shadowed on-call shift. **Migrating the service without migrating the on-call knowledge just moves the incident.**
- **Secrets and config drift**: compare the *rendered* config old vs new, not the source. A missing env var is the most common "it works on EC2 but not on Kubernetes" bug.

**Risk management:**
| Risk | Mitigation |
|---|---|
| Platform capacity (40 services land on a cluster sized for 5) | Migrate in waves with capacity planning per wave; node autoscaling with quota headroom checked in advance; **load-test the cluster, not just the service** |
| Team capacity evaporates under feature pressure | Written commitment from engineering leadership; migration as a tracked OKR with per-team dates; platform pairing to reduce the cost; **and a hard rule that a migration in progress isn't abandoned halfway** — half-migrated is the worst state |
| A bad migration causes a SEV1 and kills momentum | Pilots first, dual-running always, automated rollback, a documented abort procedure per service, and **a blameless retro published with the fix** — one well-handled failure builds more trust than ten silent successes |
| Hidden dependency discovered in prod | Discovery from telemetry (flow logs, DNS, traces, LB config) before the migration, plus dual-running with traffic comparison |
| Data migration | CDC/dual-write with a reconciliation job to prove parity before switching reads; a rollback plan; **never cut over on faith** |
| Cost goes up instead of down | Measure before and after per service; the usual causes are over-set resource requests, dual-running left on too long, and always-on non-prod. **Report the savings monthly — it's what keeps the programme funded** |
| Scope creep ("while we're migrating, let's also…") | Explicit rule: **migration is a lift-and-shift plus 12-factor compliance. Refactoring is a separate project.** Mixing them doubles the risk and the timeline |

**How I'd report it:** a public dashboard — services migrated / in progress / planned / blocked, with owners, dates, and the measured before/after per service (deploy lead time, change failure rate, on-call pages, cost). A weekly update. Celebrated wins with numbers. **And honest reporting of the ones that went badly**, which builds far more credibility than a highlight reel and prevents the same mistake 20 times.

### Follow-ups
- **"What if a team says their service can't be containerised?"** → Find out why. Usually it's a real constraint (a licensed binary tied to a host, a hardware dependency, a mainframe-adjacent integration, a performance requirement). Then: solve it (a sidecar, a VM-based node pool, a managed service), or leave it behind with a documented reason and a supported alternative path. **Leaving 3 of 40 services behind with a plan is a success; forcing them is a failure.**
- **"Would you use a service mesh?"** → Not as part of the migration. Migrate first, get the basics right, and add a mesh later if we hit a problem it solves (uniform mTLS, per-request L7 balancing for gRPC, traffic splitting across many teams). **Adding a mesh to a migration doubles the number of things that can go wrong.**
- **"One cluster or many?"** → Start with one production cluster plus one non-prod, with namespaces per team, RBAC, quotas and NetworkPolicy. Split when we have a real reason: a compliance boundary, a blast-radius requirement, a scale limit, or a team that needs independent upgrades. **Multi-cluster is a tax you should only pay when the benefit is measured.**
- **"How do you know when to stop?"** → When the marginal service costs more to migrate than the remaining benefit — and I'd say that explicitly rather than finishing the list for its own sake. A documented "these 4 stay on EC2/managed services because X" is a better outcome than a forced migration that breaks something.

---

## War Room 4 — "The cost crisis"

### The situation
> "Your cloud bill is $180k/month and the CFO wants it at $110k within two quarters, without degrading reliability. Traffic is growing 15% quarter over quarter. What do you do?"

### What they're scoring
Whether you **attribute before you optimise**, whether you know the **high-yield levers**, whether you understand that **cost and reliability interact**, and whether you can build a **durable** model rather than a one-off cleanup.

### Model answer

**First, reframe the target honestly:**
> "A 39% reduction while traffic grows 15% per quarter means reducing **cost per unit of work** by roughly half over two quarters. That's achievable, but it's not achievable by cancelling a few idle instances — it requires structural changes plus a durable operating model. So I'd commit to a number **with a stated composition**: what comes from waste removal, what from commitment and pricing, what from architecture, and what from demand management. And I'd flag the two things I won't trade: reliability headroom and the ability to grow. **Cutting 40% by removing headroom saves money this quarter and costs an outage next quarter.**"

**Phase 1 (weeks 1–3): Attribute and find the top 10.**
- **Turn on tagging enforcement and cost allocation.** Mandatory tags (`team`, `env`, `service`, `cost-centre`) enforced by SCP/policy and by IaC. **Untagged spend is unmanageable spend** — and usually 30–40% of the bill initially.
- **Get the CUR (or the equivalent) into Athena/BigQuery** and slice it: by service, by account, by region, by **usage type**, by team, by tag, month over month.
- **Produce the top-10 line items.** Pareto always holds — typically: compute (EC2/EKS nodes), databases, **data transfer**, object storage + requests, **NAT Gateway**, load balancers, snapshots/backups, observability (CloudWatch/Datadog/log ingestion), CI runners, and one surprise.
- **Set up detection so this never happens again**: budgets with **forecasted** alerts at 50/80/100% per account and per team, and **Cost Anomaly Detection** wired to a real notification path. **"We noticed on the invoice" means the detection failed regardless of the cause.**

**Phase 2 (weeks 3–8): Remove waste — the fast 15–20%.**
| Waste | How to find | Typical saving |
|---|---|---|
| **Zombies**: unattached EBS volumes, orphaned snapshots, unused Elastic IPs, idle load balancers, empty clusters, forgotten dev environments, unreferenced AMIs | Automated sweeps + `aws config`/inventory queries | 3–8% |
| **Non-prod running 24/7** | Schedule shutdown nights/weekends (with an override for anyone who needs it) | **~65% of non-prod compute** |
| **Over-provisioned instances** | Compute Optimizer / observed p95 utilisation | 10–30% of compute — **but right-size against the SLO, not the peak** |
| **Data transfer via NAT instead of endpoints** | VPC flow logs + NAT Gateway line item | **S3/DynamoDB gateway endpoints are free** — often a 5-figure monthly saving |
| **Log and metric volume** | Ingestion reports; top-N noisy services; **retention set to forever** | 20–60% of observability cost — filter at the edge, tier retention, drop health-check access logs |
| **Storage tiering** | Access-pattern analysis; lifecycle policies absent | S3 Intelligent-Tiering/lifecycle, **non-current version expiry**, **abort incomplete multipart uploads**, snapshot retention limits, EBS **gp2 → gp3** (cheaper *and* faster) |
| **Over-set Kubernetes requests** | Utilisation vs requests per workload (kubecost/OpenCost) | Requests drive scheduling and node count — **halving over-set requests can halve the node fleet** |
| **Duplicate telemetry** | Two agents collecting the same thing | 5–15% of observability |

**Phase 3 (weeks 6–14): Pricing and purchasing — another 15–25%.**
- **Compute Savings Plans** covering the **stable baseline** (target 70–80% coverage), on-demand for the elastic top. **Buy *after* right-sizing, or you commit to the waste.**
- **Spot** for stateless, interruptible work: CI runners, batch, EKS managed node groups with mixed-instances policies, EMR, stateless web tiers. **Typically the largest single lever available — 60–90% off** — and it's an architecture decision (graceful interruption handling, diversified pools, capacity-rebalance signals), not a switch.
- **Reserved capacity** for steady databases (RDS/DynamoDB/OpenSearch) and for the observability vendor.
- **Graviton/Arm** migration for JVM, Go, Node, Python and container workloads — 20–40% better price-performance; the blocker is multi-arch images and native deps.
- **Vendor renegotiation** — but only after the waste is out, otherwise you lock in the waste. **Committed spend is leverage; committed waste is a tragedy.**
- **Region selection** where data residency allows (prices vary 10–30% by region).

**Phase 4 (months 3–6): Architecture — the durable 20–30%.**
- **Autoscaling that actually scales in**: verify HPA/Karpenter/ASG behaviour, remove CPU limits that block efficient packing, **consolidate node pools** (Karpenter bin-packing is often a 20–30% node-count win), and fix the "scaled up in a spike, never scaled down" pattern.
- **Scale-to-zero for spiky workloads**: Cloud Run / Knative / KEDA / Lambda for low-traffic services and internal tools. **A service that serves 100 requests a day doesn't need three always-on pods.**
- **Right-size the data tier** — usually the second-biggest line: Aurora Serverless v2 with `min_capacity=0` for spiky workloads, DynamoDB provisioned vs on-demand modelling, **removing unused GSIs** (each multiplies write cost), read-replica count review, and **cache hit-rate improvement** (a 10% hit-rate gain can remove a whole replica).
- **Storage architecture**: open table formats + object storage instead of an always-on warehouse cluster; **partitioning and clustering so queries scan less**; query cost limits and per-team attribution.
- **Async and queue-based smoothing** so peak capacity isn't provisioned for a 20-minute daily spike.
- **Consolidation**: how many Postgres instances do we actually need? How many Redis clusters? How many CI systems? **Duplication across teams is a large, invisible cost.**
- **Data lifecycle**: delete what has no value. Retention policies for logs, traces, metrics, snapshots, backups, event streams. **The cheapest byte is the one you never stored.**

**Phase 5 (ongoing): The operating model — so the savings don't decay.**
- **Showback per team**, published monthly, with the trend. **Visibility alone typically cuts 10–20%** — teams that see their own spend behave differently. (Chargeback later, if at all — it can distort engineering decisions.)
- **Cost in code review**: Infracost on every IaC PR; a "what does this cost at 10× traffic?" question in design reviews; cost as a non-functional requirement alongside latency and availability.
- **Cheap-by-default standards**: Graviton, gp3, endpoints, spot-friendly design, log filtering at the edge, sane retention defaults, resource requests reviewed by policy.
- **A monthly cost review** with engineering and finance, top-N drivers, anomaly review, and a burn-down against the target.
- **Per-team budgets with forecast alerts**, and **anomalies routed to a human within a day**.
- **Unit economics, not just totals**: cost per request, per user, per job, per GB processed. **A total that grows with traffic is fine; a unit cost that grows is not.** This is the metric that lets you say "we're 15% more expensive but 40% more efficient".

**The reliability guardrails I'd state explicitly:**
- **Don't remove headroom**: keep N+1 AZ capacity, keep autoscaling headroom, keep the SLO-motivated slack. **Right-size against the p99 demand plus the autoscaler's reaction time, not against the average.**
- **Don't spot-ify the stateful or the latency-critical without interruption handling.**
- **Don't cut observability to the point where you can't diagnose an incident** — that's a false saving with an incident-shaped bill attached.
- **Don't defer patching or upgrades to save money** — that's borrowing at a terrible rate.
- **Measure reliability alongside cost** and report both. If change failure rate or MTTR degrades, the saving wasn't real.

**The composition I'd commit to (example):**
| Source | Saving | Confidence |
|---|---|---|
| Waste removal (zombies, non-prod scheduling, endpoints, log/metric volume, storage lifecycle) | 18% | High, weeks |
| Commitments (Savings Plans, reserved DBs, vendor renegotiation) | 15% | High, but only after right-sizing |
| Spot + Graviton + autoscaling consolidation | 15% | Medium-high, needs engineering |
| Right-sizing + data-tier architecture + scale-to-zero | 12% | Medium, needs measurement |
| **Total** | **~60%** | — |
> "That overshoots the target, deliberately — because some levers won't deliver as modelled, and because traffic is growing 15% a quarter underneath me. **I'd commit to the CFO's number as the floor and report against unit cost as the real measure.**"

### Follow-ups
- **"What if the team says a service can't be spot-ified?"** → Ask what breaks on a 2-minute notice. Usually the answer is "we don't handle interruption", which is a fixable engineering problem (graceful draining, checkpointing, diversified pools), not a fundamental one. For genuinely stateful or long-transaction work, keep it on-demand and find the saving elsewhere.
- **"How do you prevent this recurring?"** → The operating model: attribution, forecast budgets, anomaly detection with a real notification path, cost in PR reviews, cheap-by-default standards, and a monthly review with owners. **A cleanup without a model decays in two quarters — I've seen it happen every time.**
- **"What's the riskiest lever?"** → Reducing resource requests and headroom, because the failure shows up as an incident rather than a bill. That's why I right-size against p99 plus autoscaler reaction time, keep N+1 AZ capacity, and measure reliability metrics alongside cost throughout.
- **"Would you move workloads to another cloud for cost?"** → Almost never for cost alone — egress, duplicated engineering, and the migration cost swamp the savings. I'd use the *threat* of portability as negotiating leverage, and I'd invest in portability (open formats, Kubernetes, Terraform) so the option stays real.

---

## War Room 5 — "The security incident"

### The situation
> "GuardDuty reports `UnauthorizedAccess:EC2/InstanceCredentialNotfromAWS` on three production instances, and you find two IAM users you don't recognise. It's Friday 17:00. Go."

*(The full cloud-credential compromise playbook is in [`12-Cloud-AWS`](../12-Cloud-AWS/README.md#19-an-engineers-aws-access-keys-were-committed-to-a-public-github-repo-respond) and the Kubernetes version in [`14-DevSecOps-and-Security`](../14-DevSecOps-and-Security/README.md#14-you-suspect-an-active-compromise-of-your-kubernetes-cluster-respond). This war room is about **running it** — the decisions, the sequencing, and the judgement.)*

### What they're scoring
Whether you **contain before investigating**, whether you know **where attackers persist**, whether you protect **evidence and people**, whether you understand the **notification obligations**, and whether you can stay organised under pressure at 5pm on a Friday.

### Model answer

**Minute 0–5: Declare, staff, and stop the bleeding.**
> "This is a SEV1 security incident with an active adversary, so the first three things are: **declare it and pull in security leadership and legal now** — not after I've confirmed everything, because notification clocks (GDPR's 72 hours, contractual customer notice) start at awareness, and because I want the decision-makers awake at 5pm Friday rather than at 9am Monday. **Assign roles**: I'm IC, someone on forensics, someone on comms/legal, someone as scribe building the timeline. **And I make one rule explicit: nobody deletes or terminates anything yet** — because the instinct to clean up destroys the evidence and often triggers the attacker's persistence."

**Minute 5–20: Contain — credentials first, network second, workloads third.**
> "The order matters, and credentials come first because everything else the attacker has flows from them.
> 1. **Deactivate, don't delete**, the two unknown IAM users — and capture their policies, access keys, creation time and the CloudTrail record of who created them first. **Deactivating preserves attribution; deleting destroys it.**
> 2. **Revoke active sessions.** For the compromised instance roles, the credentials are temporary, so I need a **deny policy with a `aws:TokenIssueTime` condition** set to now — that invalidates every session issued before it. Without that, the attacker keeps working for up to 12 hours.
> 3. **Rotate the instance profiles'** underlying assumptions: check what roles those three instances had, and treat **everything those roles could read as compromised** — S3 buckets, Secrets Manager secrets, DynamoDB tables, the database. Rotate the database passwords and any secret in scope.
> 4. **Network containment**: security-group changes to restrict the three instances' egress, block the attacker IPs at the perimeter (while knowing they'll rotate), and **cut the instances off from lateral paths** — but keep them running for forensics if it's safe to do so.
> 5. **Freeze change**: pause CI/CD and GitOps auto-sync so the attacker can't ride our pipeline back in, and lock the image registry."

**Minute 20–60: Find the persistence — because removing the entry point without removing persistence is not remediation.**
> "I work through the places attackers actually persist, in this order:
> - **IAM**: new users, roles, access keys, **role trust policies modified to allow an external account or a wildcard principal**, new instance profiles attached, `iam:PassRole` grants, and **new federation/SSO configurations**. Also: **were any existing roles' policies widened?**
> - **Compute**: unexpected running instances (especially GPU or large types in unusual regions — **mining**), modified user data / launch templates, new Lambda functions, new ECS tasks, **new AMIs or snapshots shared externally** (`ModifySnapshotAttribute` with `createVolumePermission` is a classic exfiltration path).
> - **Data**: S3 access logs and CloudTrail data events for anomalous `GetObject` volume, new bucket policies granting public or cross-account access, **disabled bucket logging or versioning**, lifecycle rules added to delete data.
> - **Detection tampering**: **CloudTrail stopped or its trail deleted**, GuardDuty disabled, log delivery broken, Security Hub standards turned off, **CloudWatch log retention reduced**. Attackers do this early — if it happened, my visibility window is shorter than I think, and that's a finding.
> - **Kubernetes** (if the instances are nodes): new RBAC bindings, unexpected workloads, **mutating/validating webhooks** (a superb persistence mechanism), DaemonSets, SA tokens, and the `aws-auth`/Pod Identity mappings.
> - **GitOps repos and CI**: commits I don't recognise, workflow changes, new secrets, a modified OIDC trust policy.
> - **Backdoors in the application**: a new admin account, a modified auth config, a webshell in a writable path.
> Meanwhile I'm building the **timeline**: when were the users created, when were the keys first used, from which IPs, and what did they touch? That establishes **dwell time** — which is the number leadership and legal will ask for, and which determines the notification analysis."

**The entry point question (answer it, don't skip it):**
> "The GuardDuty finding `InstanceCredentialNotfromAWS` means the **instance's own temporary credentials were used from outside AWS** — so they were extracted. The three usual paths: an **SSRF** in one of our applications reaching the metadata endpoint (IMDSv1 or a hop limit > 1 makes this easy), a **compromised container or host** that read the credential file, or **credentials leaked into logs/user data/a public artifact**. So I check: is IMDSv2 enforced with hop limit 1 on those instances? Which application on those instances fetches URLs? Are there any logs containing `ASIA`-prefixed keys? **Finding the entry point isn't academic — until I close it, everything I clean up gets re-compromised.**"

**Hour 1–4: Eradicate and preserve.**
> "**Preserve before eradicating**: snapshot the volumes of the three instances, export the relevant CloudTrail/GuardDuty/VPC flow log windows to a **separate account the attacker can't reach**, capture memory if we have the tooling, and record the IOCs (IPs, key IDs, user ARNs, file hashes) for detection.
> Then **eradicate by rebuilding, not cleaning**: delete the rogue identities, terminate and **replace the three instances from a known-good AMI** rather than trying to clean them, remove any attacker-created resources, and revoke/rotate everything in scope. **A cleaned host is an uncertain host, and uncertainty is worse than the rebuild cost.**
> And I keep asking: **is data leaving?** Egress volume, DNS queries to unusual domains, snapshot sharing, new public buckets. If I can't rule out exfiltration, I say so explicitly rather than reassuring people — because that determination drives the legal obligation."

**Hour 4–24: Assess, notify, recover.**
> "**Legal and notification**: with security counsel, determine whether customer data was accessed or exfiltrated, which regulations and contracts apply, and the deadlines. **GDPR is 72 hours from awareness**; customer contracts often have their own notice periods; some regimes require regulator notification even without confirmed data loss. I provide the facts and the timeline, not the conclusion — that call isn't mine.
> **Recovery**: restore services progressively, verifying integrity at each step (image digests match, IAM matches policy-as-code, no unexpected resources, RBAC matches Git). Re-enable CI/CD **only after** the pipeline and repos are verified clean — otherwise I reintroduce the attacker.
> **Heightened monitoring** for 2–4 weeks with the specific IOCs, because the same actor often returns.
> **Communications**: internal all-hands when appropriate, customer notification per legal's guidance, and a single source of truth for the facts so people don't speculate."

**Then: the systemic fix.**
> "The post-incident review will produce the same list every time, and I'd rather do it now than after the next one:
> - **IMDSv2 required with hop limit 1** on every instance, enforced by SCP/policy and by the launch template defaults — this closes the SSRF-to-credential path that causes most of these.
> - **No long-lived credentials anywhere**: OIDC federation for CI, instance profiles/task roles/Pod Identity for workloads, IAM Identity Center for humans. **The credential that doesn't exist can't be stolen.**
> - **Least privilege with permission boundaries**, so a stolen instance role can't create IAM users or share snapshots. **The attacker created two IAM users — that means our instance roles had `iam:CreateUser`, which is the actual root cause of the escalation.**
> - **SCPs denying the crown-jewel actions**: disabling CloudTrail/GuardDuty, sharing snapshots externally, creating IAM users from a workload role, leaving approved regions, deleting backups.
> - **Egress filtering** — default-deny outbound with an allowlisting proxy, so exfiltration and C2 are hard and noisy.
> - **Alerting on identity creation**: an alert on `CreateUser`/`CreateAccessKey`/`AttachRolePolicy` from unexpected principals catches persistence attempts in minutes rather than weeks. **That one alert would have shortened this incident dramatically.**
> - **Runtime detection** (Falco/Tetragon/GuardDuty with EKS protection) and **CSPM** running continuously.
> - **Immutable, cross-account, object-locked logs** so the audit trail survives the attacker.
> - **A tested incident response runbook** and a game day for exactly this scenario — because the reason this took four hours instead of one is that we were improvising."

**The framing that closes it:** "The technical steps are well-known; the judgement is in the sequencing — **contain credentials before cleaning hosts, preserve before eradicating, rebuild rather than clean, and involve legal at minute five rather than hour five.** And the honest conclusion is that this incident wasn't caused by a clever attacker; it was caused by an instance role that could create IAM users and a metadata service that handed credentials to anything that asked. **Those are configuration decisions we made, and they're the thing I'd fix first.**"

---

## War Room 6 — "The impossible deadline"

### The situation
> "Sales signed a contract that requires a feature in 6 weeks. Your honest estimate is 12. The CEO wants it done. You're the tech lead. What do you do?"

### What they're scoring
Whether you **negotiate rather than absorb**, whether you can **decompose scope**, whether you **protect quality where it's non-negotiable**, whether you communicate risk early and without drama, and whether you'd say no.

### Model answer

**Step 1: Understand the real requirement before arguing about the date.**
> "My first move isn't 'we can't' — it's 'what exactly does the contract require?' Because 'a feature in 6 weeks' is usually a proxy for something narrower: a customer demo, a pilot with 3 users, a compliance checkbox, a renewal deadline, a launch event. **I'd read the contract language with sales and legal, and talk to the customer if possible.** Half the time the real requirement is 30% of what everyone assumed, or the date is soft, or there's a manual workaround that satisfies it temporarily.
> Concretely I'd ask: what happens if it's two weeks late? Is there a penalty, or just disappointment? Which *part* is contractually required on that date? Can a subset plus a documented roadmap satisfy it? **These are questions nobody asked before the estimate became a fight.**"

**Step 2: Re-estimate honestly, and show the work.**
> "I'd produce a decomposed estimate — not a number, a breakdown: what each piece costs, what's uncertain, and where the risk is. And I'd separate the three things people conflate:
> - **The minimum viable version** that satisfies the contract: maybe 5 weeks.
> - **The version we'd be proud of**: 12 weeks.
> - **The version that's actually being asked for**: probably somewhere between, and nobody has written it down.
> I'd also be explicit about what makes the 12 weeks 12: the schema migration on a large table, the integration with a third party whose API we haven't used, the auth model, the multi-tenant isolation, the observability, the migration of existing data, and the testing. **Naming them turns 'you're slow' into 'here are the six things, choose which three we skip.'**"

**Step 3: Present options, not a refusal.**
> "I'd bring the CEO three or four options with honest trade-offs, because 'can we do it?' is the wrong question — 'which of these do you want?' is the right one:
> 1. **Reduced scope, 6 weeks**: the contractual minimum, hand-built where possible, with the automation and generalisation deferred. Ships on time; we owe ~6 weeks of follow-up work.
> 2. **Full scope, 12 weeks**: what we estimated, with the quality we'd want.
> 3. **Full scope, 8 weeks, with 2 more engineers**: borrowed from another team — which means *their* commitments slip, so that's a business decision, not an engineering one. (And Brooks's Law applies: adding people to a late project can make it later, so this only works if the work is genuinely parallelisable.)
> 4. **A phased delivery**: the contractual minimum at week 6, the rest at week 12, with the customer informed — often acceptable, and the honest version of option 1.
> For each, I'd state what we'd be **deferring and what it costs later**, in writing. **The point is to make the trade-off explicit and owned at the top, rather than absorbing it silently in the team.**"

**Step 4: If the answer is still "all of it, in 6 weeks" — protect the non-negotiables.**
> "Then I'd negotiate the *quality* dimension explicitly, because that's where silent compromises happen. I'd say: we can cut scope, we can cut polish, we can cut generality, and we can defer automation. **What I won't cut is the things that create unbounded risk:** security (auth, authorisation, secrets, input validation), data integrity (the migration is reversible, backups are tested, no data loss), the ability to roll back, and observability (if we can't see it fail, we can't fix it at 3am). Cutting those doesn't save 6 weeks — it converts a schedule problem into an incident problem with a much larger cost.
> Everything else is negotiable, and I'd write down exactly what we deferred, with a date to revisit. **Deferred work that isn't written down becomes a mystery outage in three months.**"

**Step 5: Run it as a risk-managed sprint, not a death march.**
> "Practically: cut scope to the smallest thing that satisfies the contract; freeze it (no additions — the biggest killer of a compressed timeline is scope arriving mid-sprint); reduce WIP to one or two things per person; protect the team from meetings and context-switching; ship continuously behind a feature flag so we're integrating from week 1 rather than week 6 (**a big-bang integration at week 6 is how you discover in week 7 that it doesn't work**); test the risky unknowns in week 1 with a spike; and give a weekly honest status with a confidence level, not a percentage complete.
> And I'd **not** rely on sustained overtime. A week of extra hours is a lever; six weeks is a quality problem — defect rates rise, judgement degrades, and people leave. I'd use the extra hours deliberately, on the critical path, with time off after, and I'd say so."

**Step 6: Communicate early, often, and without drama.**
> "The failure mode I most want to avoid is the optimistic status report that becomes a surprise in week 6. So: the risk is stated in week 1, in writing, with the options; the weekly status includes a confidence level and the top three risks; and if we're going to miss, leadership hears it the moment I know — not the day before. **Bad news early is a manageable problem; bad news late is a crisis, and it also destroys the trust I'll need next time.**"

**Step 7: Afterwards.**
> "Whether we made it or not, I'd run a review on the *process*, not the outcome: how did a 6-week commitment get made against a 12-week feature? Was engineering consulted before the contract was signed? Do we have a way to give a confidence-weighted estimate to sales quickly? **The durable fix is usually a process one** — a lightweight pre-sales technical review, a published 'we can commit to X in N weeks' catalogue, or a rule that contracts include a technical feasibility check. Otherwise this happens every quarter, and each time it costs the team's trust a little more."

**Would I ever just say no?**
> "Yes — in two specific cases. If delivering would create an unacceptable safety, security, or data-loss risk, I'd refuse and escalate, because that's a decision above my pay grade but the information is mine and I'm obliged to give it clearly. And if the ask is impossible rather than merely hard — no scope reduction makes it feasible — then saying 'this isn't achievable, here's what is' is more useful than committing and failing. **But I'd only say no after I'd genuinely looked for the third option, and I'd say it with alternatives attached, because 'no' without options is just obstruction.**"

---

## War Room 7 — "The architecture review"

### The situation
> "A team proposes replacing their Postgres monolith database with 12 microservices, each with its own database. They've written a 40-page design doc. You're the reviewing architect. What do you look at, and what do you say?"

### What they're scoring
Whether you can **evaluate a design**, whether you know **the real costs of distributed systems**, whether you push back **with reasoning rather than authority**, and whether you can find the **actual problem** behind the proposal.

### Model answer

**First, find out what problem they're solving — because the architecture is an answer, and I want the question.**
> "A 40-page design doc for a database decomposition usually means one of four real problems, and each has a different best answer:
> - **'We can't deploy independently'** → the fix might be module boundaries, a monorepo with clear interfaces, or feature flags — not 12 databases.
> - **'The database is a bottleneck'** → then I want the measurement: which queries, which tables, what's the contention? Often it's 3 hot tables and an indexing problem, and the answer is read replicas, partitioning, caching, or extracting *one* service — not 12.
> - **'The team has grown and we're stepping on each other'** → that's a Conway's Law problem; the fix is team boundaries and interfaces, which may justify *some* decomposition, but the number of services should follow the number of teams, not the number of tables.
> - **'We want to modernise / the CTO asked for microservices'** → then the honest conversation is about cost and risk, because there's no problem to solve.
> So my first question in the review is: **'what specifically is broken today, and how would you measure whether this fixed it?'** If they can't answer, the design isn't ready — and saying so kindly is the most valuable thing I can do."

**Then, the specific things I'd examine in the doc:**

**1. Service boundaries — the hardest part, and the part most often drawn wrong.**
- Are the boundaries drawn around **business capabilities with independent change rates**, or around **database tables**? Table-per-service is the classic mistake: it produces a distributed monolith where every feature change touches five services and five schemas.
- **The test I'd apply:** can two teams change their services independently, without coordinating a deploy? If not, the boundary is in the wrong place.
- Do the boundaries match the **team structure** (Conway's Law)? A 6-person team owning 12 services will produce 12 poorly-maintained services.
- Are there **shared/circular dependencies**? I'd ask for the dependency graph and look for cycles — a cycle means those two "services" are one service.

**2. Data consistency — where these designs most often fail.**
- Which operations currently happen in **one transaction** that would now span services? Every one of those needs a **saga with compensating actions**, an **outbox pattern**, or an acceptance of eventual consistency. **I'd ask them to list the cross-service transactions and show me the design for each.** If the doc doesn't have that section, it isn't finished — this is the single biggest omission in decomposition proposals.
- **Read-your-writes**: a user updates their profile and the next page load shows stale data. Which reads must be consistent, and how is that achieved?
- **Joins and reporting**: how do you answer "show me all orders for customers in region X with product Y" when orders, customers and products are in three databases? The usual answers — API composition (slow, N+1), CQRS read models (correct but a lot of machinery), or a data lake/warehouse with CDC (the pragmatic one). **The doc must pick one.**
- **Uniqueness constraints** that spanned tables (a globally unique email across users and pending_registrations) — now impossible to enforce with a constraint. How is it enforced, and what's the race window?
- **Referential integrity**: no foreign keys across services, so orphaned records become a runtime condition. What detects and repairs them?

**3. Operational cost — the part that isn't in the doc.**
- 12 services = 12 deploy pipelines, 12 sets of dashboards, 12 SLOs, 12 runbooks, 12 on-call knowledge areas, 12 databases to back up, patch, upgrade, monitor, and size. **I'd ask: who operates these, and what's the estimate in engineer-hours per quarter?**
- **Distributed-systems failure modes** they now own: partial failure, network partitions, retries and idempotency, timeouts and deadline propagation, message ordering, duplicate delivery, clock skew, cascading failure, and the fact that **a request now has 5 hops and each adds latency and a failure probability**.
- **Debuggability**: a bug that was one stack trace is now a distributed trace across 5 services. Do they have tracing? Correlated logs? A local environment where all 12 run?
- **Testing**: integration testing across service boundaries is an order of magnitude harder. Contract tests? Consumer-driven? Ephemeral environments? What's the plan?
- **Local development**: can a developer run and debug the system on a laptop? If not, velocity will drop and nobody will notice until it's too late.

**4. The migration plan — because this is where projects die.**
- Is it a **strangler-fig** (extract one service at a time, dual-write, verify, cut over, decommission) or a **big bang** (rewrite everything, switch over)? Big bang migrations of this kind have a very poor record. **I'd require strangler-fig with a working system at every step.**
- **Data migration**: how do you split a 500 GB database with live traffic? Dual-write with reconciliation? CDC? A freeze window? Each has a cost and a risk, and the doc must pick and justify.
- **Rollback**: at each step, can we go back? After the data has diverged, "rollback" may not exist.
- **Sequencing**: which service first? (Answer: the one with the clearest boundary, the least coupling, and the most to gain — not the most important one.)
- **Time and cost**: a decomposition like this is typically 9–18 months of a team's capacity, during which feature delivery slows. **Is that trade-off approved by the business, explicitly?**

**5. What I'd want to see that's probably missing**
- **Non-goals** (what this design deliberately doesn't solve).
- **Alternatives considered** with reasons for rejection — including **"do nothing" and "improve the monolith"**. A doc with one option isn't a design, it's a proposal.
- **Success metrics**: how will we know it worked? Deploy frequency? Lead time? Incident count? Team autonomy? Without them, we'll never know whether the cost was worth it.
- **A reversible/exit story**: if this goes badly at service 4, what do we do?

**What I'd actually say (and how I'd say it):**
> "I'd start with what's good — and there's usually a lot: the analysis, the ambition, the desire for independent deployability. Then I'd frame my feedback as **questions and risks, not verdicts**, because a reviewing architect who says 'no' loses the team and gets the design anyway, just without the review.
> My central challenge would be: **'this design distributes the data before it distributes the teams, and it doesn't yet have an answer for cross-service transactions, joins, or the operational cost of 12 databases. I'd like to see three things before I can support it: (1) the problem statement with measurements — what's broken today and how we'll know it's fixed; (2) a section on data consistency that lists every operation currently in one transaction and shows how it works when split; and (3) a strangler-fig plan where the first service extracted is the least coupled one, with dual-write and reconciliation, so we learn the hard lessons on something small.'**
> And I'd offer the **incremental alternative** explicitly: keep one database, but introduce **module boundaries with enforced interfaces** (a modular monolith — separate schemas or logical schemas, no cross-module queries, an API between modules). That gets 70% of the deployability and team-autonomy benefit at 10% of the risk, and **it's the right preparation for decomposition anyway** — because if you can't define clean module boundaries inside the monolith, you certainly can't define clean service boundaries across a network. **Then, when the modules are stable and the team structure justifies it, extracting a service is a mechanical step rather than an archaeological project.**
> If after all that they still want 12 services, and the business has accepted the cost, I'd support it — with the consistency design and the strangler-fig plan as conditions. **My job isn't to impose my preference; it's to make sure the trade-offs were seen by the people paying for them.**"

### Follow-ups
- **"When IS microservices the right answer?"** → When you have **multiple teams** (roughly one service per team, per Conway), genuinely **independent change rates**, **different scaling profiles** (one component needs 50× the compute), **different technology requirements**, or a **fault-isolation** requirement (one component's failure must not take down the rest). And when you have the platform maturity to operate them: CI/CD, observability, tracing, service discovery, resilience patterns, and on-call.
- **"What about the modular monolith — isn't that just delaying?"** → No, it's often the destination. A well-modularised monolith with enforced boundaries gives most of the benefits at a fraction of the cost, and it's the best possible *preparation* for decomposition. **Premature distribution is a much more common and more expensive mistake than premature monolithism.**
- **"How do you handle a team that ignores your review?"** → Escalate the *risk*, not the *person*: write down the specific risks and the conditions, share them with the team's leadership, and let the decision be made by whoever owns the outcome. Then, if it proceeds, I help make it succeed — because being right and being useless are compatible, and I'd rather not be.

---

## Red flags (across all war rooms)

| Doing this | Costs you |
|---|---|
| Diving into a solution before clarifying | You solve the wrong problem, visibly |
| Never asking a question | Signals overconfidence or an inability to scope |
| "I'd roll back the deploy" as the first action when the timeline says otherwise | You didn't read the scenario |
| Mitigating only after fully understanding the bug | The incident lasts 4× longer |
| No mention of roles/comms in an incident scenario | You can't run an incident, only debug one |
| Restarting before capturing evidence | The crime scene is gone |
| Only one option presented in a design/negotiation scenario | No trade-off thinking |
| No numbers — no estimate of scale, cost, time or impact | Untestable claims |
| Ignoring the second-order effects (retry storms, recovery floods, connection counts) | You fixed it and broke it again |
| "We'd just add more nodes" for a database bottleneck | Compute is elastic; state isn't |
| Proposing 12 microservices without a consistency design | The classic distributed-monolith proposal |
| Absorbing an impossible deadline silently | A surprise in week 6, and lost trust |
| Cutting security/data-integrity to hit a date | Converting a schedule problem into an incident |
| Deleting attacker artifacts before preserving evidence | No forensics, no attribution, no lessons |
| Cleaning a compromised host instead of rebuilding | Uncertainty, and probably still compromised |
| Involving legal/comms at hour 20 instead of minute 5 | Missed notification deadlines |
| No systemic fix at the end | You'll be back |
| Blaming a person or a team in any scenario | You're the risk |

## Rapid recall

**Method for every war room:** clarify (2–4 questions) → state your method → mitigate before you understand → quantify → trade-offs → **end with the systemic fix and how you'd verify it.**

**War Room 1 (production down):** declare SEV1 + roles (IC doesn't debug) → scope (which percentile, what proportion, since when) → **the 22-minute gap means exhaustion/expiry/threshold/delayed-deploy-effect, not a plain bad deploy** → **check old vs new pods** (settles the deploy question in 30s) → read the actual error → open one slow trace (8s smells like a timeout) → dependency latency + **pool saturation** (green CPU means *waiting*, not working) → mitigate with the cheapest reversible lever → define the success criterion before acting → verify, communicate on a cadence, **preserve evidence before restarting** → watch second-order effects (retry backlog, cache rebuild) → systemic: canary with a **long enough verification window**, pool-saturation alerts, dependency latency on the dashboard, deploy annotations.

**War Room 2 (greenfield platform):** clarify the real problem, compliance, workload shape, and **headcount** → **thinnest viable platform**: containers + CI + managed K8s + GitOps + observability defaults → safe boring deploys first (hour → 10 min, failure 33% → <10%, rollback = `git revert`) → see everything (shared instrumentation library, one templated dashboard, ~10 symptom-based alerts with runbooks, humane on-call) → safe cheap cloud (IaC, landing zone, OIDC not keys, SCPs, PSA restricted, secrets via workload identity) → golden path + service template + module library + catalogue → **buy observability in year one with OTel so the data is portable** → **no mesh, no bespoke tooling, no microservices mandate, no big-bang, no mandate without benefit** → measure: DORA, time-to-first-deploy, pages/shift, MTTR, survey.

**War Room 3 (migration):** negotiate the goal/deadline/**team capacity** with arithmetic → make migration **cheap, not mandatory** (build the machine first: chart, CI template, GitOps app, observability bundle, migration tool) → **new services on-platform from day one** → migrate by value/risk, easiest+enthusiastic first, hardest last → strangler-fig with **dual-running budgeted** → phases: foundation+pilots (mo 1–2), prove+publish (3), waves (4–7), hard tail (7–9), decommission (9+) → **the hard 20%**: state/files, **DB connection counts (RDS Proxy/PgBouncer)**, cron/workers/batch, hardcoded hosts and `localhost` co-location, client IP, sidecar/throttling/**runtime container-awareness**, DNS ndots, image pull, **and migrating on-call knowledge not just the service** → discovery from **telemetry, not memory** → never mix migration with refactoring → report publicly with per-service before/after and honest failures.

**War Room 4 (cost):** reframe as **cost per unit of work** and commit with a stated composition → **attribute first** (tags enforced, CUR sliced, top-10 line items, **forecast** budgets + anomaly detection) → waste (zombies, **non-prod scheduling ~65%**, right-size against **p99 not average**, **S3/DynamoDB gateway endpoints are free**, log/metric volume filtered at the edge + retention tiers, storage lifecycle incl. **non-current versions and incomplete multipart uploads**, gp2→gp3, **over-set K8s requests**) → pricing (**Savings Plans after right-sizing**, **Spot for stateless/interruptible**, reserved DBs, Graviton, renegotiate only after waste is out) → architecture (autoscaling that scales in, Karpenter consolidation, **scale-to-zero**, data tier, cache hit rate, open table formats + partitioning, async smoothing, consolidation, retention) → **operating model** (showback, Infracost on PRs, cheap-by-default standards, monthly review, unit economics) → **guardrails: don't remove headroom, don't cut observability below diagnosability, don't defer patching, measure reliability alongside cost.**

**War Room 5 (security incident):** declare + **legal/security at minute 5** (notification clocks start at awareness) + roles + **"nobody deletes anything yet"** → contain **credentials first** (**deactivate don't delete**; **`aws:TokenIssueTime` deny to revoke STS sessions**; rotate everything the role could read), then network, then freeze CI/GitOps → hunt persistence in order: **IAM (incl. widened trust policies)**, compute (**mining instances, externally-shared snapshots**), data (anomalous `GetObject`, new public bucket policies), **detection tampering (CloudTrail/GuardDuty disabled → your visibility window is shorter than you think)**, Kubernetes (**webhooks**, RBAC, SA tokens), CI/GitOps repos, app backdoors → **find the entry point** (`InstanceCredentialNotfromAWS` = extracted → **SSRF/IMDSv1/hop-limit**, a compromised host, or a leak) because otherwise you get re-compromised → **preserve to a separate account, then rebuild not clean** → assess exfiltration honestly → notify per legal → recover progressively and re-enable CI only when verified → heightened monitoring 2–4 weeks → systemic: **IMDSv2 + hop limit 1**, **no long-lived credentials**, least privilege + permission boundaries (**an instance role that can `iam:CreateUser` is the root cause**), **SCPs denying crown-jewel actions**, egress filtering, **alert on identity creation**, immutable cross-account logs, **a rehearsed runbook**.

**War Room 6 (impossible deadline):** find the **real** requirement (the date is usually a proxy) → re-estimate as a **breakdown** separating minimum-viable / proud-version / actually-asked-for → present **3–4 options with explicit deferrals and later costs** (scope cut, full scope later, more people from elsewhere = their commitments slip, phased delivery with the customer informed) → if forced: cut scope/polish/generality/automation but **never security, data integrity, rollback ability, or observability** → **write down what was deferred with a date** → run it as a risk-managed sprint (frozen scope, low WIP, protected focus, **ship continuously behind a flag from week 1**, spike the unknowns in week 1, weekly honest status with a confidence level) → **don't rely on sustained overtime** → communicate risk in week 1 in writing → review the *process* afterwards (how did a 6-week commitment get made against a 12-week feature?) → say no only for unacceptable risk or genuine impossibility, **always with alternatives attached**.

**War Room 7 (architecture review):** find the **problem behind the proposal** (independent deploys? a DB bottleneck? team growth? fashion?) and demand a measurable success criterion → examine **boundaries** (capabilities vs tables; can two teams deploy independently; Conway alignment; cycles = one service) → **data consistency** (list every cross-service transaction and its saga/outbox/eventual design; read-your-writes; joins and reporting; cross-service uniqueness; orphaned references) → **operational cost** (12 pipelines/dashboards/SLOs/runbooks/databases; distributed failure modes; debuggability; contract testing; **can a developer run it locally?**) → **migration plan** (strangler-fig with a working system at every step, dual-write + reconciliation, rollback story, sequencing, business-approved cost) → what's missing: **non-goals, alternatives including "do nothing", success metrics, exit story** → deliver feedback as **questions and conditions**, not verdicts → offer the **modular monolith** as the incremental path that also *prepares* decomposition → support their decision if the business accepts the cost, **with the consistency design and strangler-fig as conditions**.

→ Next: [`20-Rapid-Fire-One-Liners`](../20-Rapid-Fire-One-Liners/README.md)
