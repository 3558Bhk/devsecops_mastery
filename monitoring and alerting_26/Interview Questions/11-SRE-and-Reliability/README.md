# 11 · SRE & Reliability Engineering

The defining topic for SRE roles and increasingly asked of senior DevOps/Platform candidates. Expect **SLOs/error budgets, incident management, post-mortems, toil, capacity planning, and resilience patterns** — plus at least one long incident scenario.

---

## 🟢 Basic

### 1. What is SRE, and how is it different from DevOps / Ops?
**Google's definition:** "SRE is what happens when you ask a software engineer to design an operations function." SRE treats **operations as a software problem**: reliability is engineered, measured, and automated rather than staffed.

| | Traditional Ops | DevOps | SRE |
|---|---|---|---|
| Ownership | Ops team operates what devs build | Shared; "you build it, you run it" | SREs *own* reliability for services they take on |
| Success metric | Uptime, tickets closed | Delivery speed + stability | **SLO attainment, error budget, toil reduction** |
| Method | Runbooks, manual work, heroics | Culture + tooling + collaboration | **Engineering**: automation, SLOs, capacity models, post-incident analysis |
| Relationship to features | Ops says no to risky changes | Collaboration | **Error budget is the negotiation mechanism** — a policy, not an opinion |
| Scaling | Headcount scales with systems | Tooling | **Toil must be < 50% of time; the rest is engineering** |

**The most-cited SRE tenets:**
- **Embrace risk** — 100% reliability is the wrong target (users can't tell the difference between 99.99% and 99.999% if their own last mile is 99%). **So: set an SLO slightly below perfection and spend the difference on velocity.**
- **Error budgets** — the formal mechanism for trading reliability against speed.
- **Eliminate toil** — manual, repetitive, automatable, tactical, no enduring value, scaling linearly with service growth. **Cap at 50% of an SRE's time**; the rest goes to engineering that reduces future toil.
- **Monitoring, automation, release engineering, simplicity.**
- **Blameless post-mortems.**
- **SRE owns the pagers; if a service's ops load exceeds the team's capacity, SRE can hand it back** (the "SRE engagement/exit" model — a real governance lever).

**Honest framing for interviews:** "DevOps is a culture and a set of practices for collaboration between dev and ops; SRE is a *role and a discipline* that implements much of DevOps with specific mechanisms — SLOs, error budgets, toil budgets, engagement criteria. Google's line is 'class SRE implements DevOps'. In practice, many companies use the titles interchangeably, and the useful distinction is whether the team has **quantified reliability targets and a policy for trading them against feature velocity**. If they don't, it's ops with a new name."

### 2. Toil — define it precisely and give examples
**Toil is work that is:** manual, repetitive, automatable, tactical (interrupt-driven), **without enduring value**, and that **scales linearly with service growth**.

| Toil (eliminate) | Not toil (real work) |
|---|---|
| Restarting a service that OOMs every Tuesday | Fixing the memory leak |
| Manually rotating a certificate | Automating cert issuance (cert-manager) |
| Granting access by editing an IAM policy per request | Self-service access with policy-as-code |
| Hand-running a deploy | Building the pipeline |
| Answering "what's the status?" in Slack | A status page + dashboards |
| Manually resizing a disk when it fills | Auto-expansion + capacity forecasting |
| Reading a paging alert and doing the same 3 commands | Automating the remediation, then the detection |
| Copying a config value between environments | GitOps |

**The 50% rule and why it exists:** if ops work exceeds ~50% of an SRE's time, the team becomes reactive, morale collapses, people leave, and reliability *decreases* — because nobody is doing the engineering that reduces the load. **It's a self-reinforcing death spiral.** The cap is the guardrail.

**How to actually reduce it (the senior answer):**
1. **Measure it first.** You can't reduce what you don't count: tag tickets/pages by toil category, track page volume per service per week, and time-box a two-week self-audit.
2. **Rank by frequency × time × risk.** Automate the top 5, not all 50.
3. **Fix the cause, not the symptom.** A page that requires a restart is a bug: the fix isn't a better restart script, it's making the service not need restarting.
4. **Delete work.** Some toil exists because of a process nobody questions. Ask "what happens if we stop doing this?" — surprisingly often, nothing.
5. **Push it to self-service.** The best automation isn't a script the SRE runs; it's a portal where the requesting team runs it themselves within guardrails.
6. **Make the remaining toil visible and bounded**: a weekly toil report, a toil budget per quarter, and a rule that new services must not add unautomated toil (enforced at the engagement review).

### 3. Incident management — roles, severities, and command structure
**Severity scale (define it, don't improvise):**
| Sev | Definition | Response |
|---|---|---|
| **SEV1** | Full outage or major data loss; significant revenue/customer impact | Page immediately, all hands, exec comms, 24/7 until resolved |
| **SEV2** | Major degradation; a subset of users/features broken; workaround exists | Page the on-call, assemble a small team, business-hours+ |
| **SEV3** | Minor degradation; internal impact; no customer effect | Ticket, next business day |
| **SEV4** | Cosmetic / non-urgent | Backlog |
**Criteria must be objective** (error rate > X%, N customers affected, revenue impact > $Y/min) so declaring a SEV1 isn't a negotiation.

**Incident Command System (ICS) roles — the thing that separates mature teams:**
| Role | Responsibility | Why it matters |
|---|---|---|
| **Incident Commander (IC)** | Owns the incident: sets strategy, delegates, does **not** debug. Decides mitigation vs root cause, escalations, and when to declare resolved | Prevents the "everyone debugs, nobody coordinates" failure |
| **Operations / Tech Lead** | Executes the mitigation plan, runs the debugging | Separates thinking from doing |
| **Communications Lead** | Status page, stakeholder updates, exec comms, timeline | Prevents the IC being interrupted every 5 minutes with "what's the status?" |
| **Scribe / Note-taker** | Maintains the timeline: what was observed, what was tried, when | The post-mortem writes itself; memory is worthless after 6 hours |
| **Subject Matter Experts** | Pulled in on demand | |

**The critical rules:**
- **The IC does not debug.** An IC who is also in the terminal has stopped coordinating, and the incident lasts longer. This is the single most common failure in small-team incidents.
- **One IC at a time**, explicitly handed over with a briefing ("here's what we know, what we've tried, what's next").
- **Declare, and declare severity.** Undeclared incidents get under-resourced.
- **Mitigate before root-causing.** Restore service first; investigate afterwards with preserved evidence. **"We don't know why yet, but we've rolled back and the error rate is normal" is a perfectly good status at minute 20.**
- **Communicate on a cadence** (every 15–30 min) even when there's nothing new. Silence generates more escalations than bad news.
- **Timebox hypotheses.** If a theory hasn't produced evidence in 15 minutes, drop it and re-scope. **Sunk-cost debugging is how 45-minute incidents become 6-hour ones.**
- **Escalate early and without shame.** Waking a colleague is cheaper than a prolonged outage.
- **Blameless language in the channel.** "The deploy broke it", not "Alice broke it". People who fear blame hide information, and hidden information prolongs incidents.

### 4. Post-mortems / post-incident reviews — how to do them so they work
**Blameless is a technique, not a kindness.** The reasoning: humans act on the information available to them at the time; if you punish the person, you get *less information* next time, and you never learn the systemic cause. **A blameless review asks "how did the system make this the reasonable action?" not "who did it?"**

**Structure:**
1. **Timeline** (from the scribe): detection → each observation → each action → mitigation → resolution. Include *when the incident actually started* (usually earlier than detection — that gap is MTTD and it's a finding).
2. **Impact**, quantified: duration, requests failed, users affected, revenue, SLO budget consumed, data loss, support tickets.
3. **What went well.** (Always include this — it's how you learn what to keep, and it balances the tone.)
4. **What went badly.** Contributing factors, not a single root cause.
5. **Where we got lucky.** (The near-miss that didn't bite this time — often the most valuable section.)
6. **Root cause analysis** — properly done (see below).
7. **Action items** with owners and due dates.
8. **Detection and response metrics**: MTTD, MTTA (acknowledge), MTTM (mitigate), MTTR (resolve), and whether a human or a customer found it.

**Root cause analysis techniques:**
- **5 Whys** — simple, but **tends to converge on "human error" or one linear chain**, which is exactly the wrong answer for complex systems. Use it as a starting point, not the method.
- **Fault tree / fishbone (Ishikawa)** — enumerate contributing factors across categories (people, process, technology, environment). Better for multi-causal incidents.
- **Contributing-factor analysis** — the mature approach: list every factor that made the incident possible or worse, and treat each as an actionable finding. **Real incidents have 5–15 contributing factors, not one root cause.**
- **The "root cause is a person" test:** if your root cause is "engineer made a mistake", you haven't finished. Ask: why was the mistake possible? Why wasn't it caught by validation, review, canary, or automated rollback? Why wasn't it detected faster? **Every one of those is a system property you can change.**

**Action items that actually get done:**
- **Specific, owned, dated, and small.** "Improve monitoring" is not an action item; "add a burn-rate alert for the checkout SLO with a runbook, @sam, by Sept 30" is.
- **Classify them**: prevent / detect faster / mitigate faster / process / documentation. A post-mortem with only "prevent" items is under-thinking.
- **Track completion** in the normal backlog with the same priority discipline as product work — **the #1 failure mode of post-mortems is that action items are written and never done**, so the same incident recurs. Report completion rate monthly.
- **The one action item that must always be there:** "add the CI/admission policy that would have caught this specific mistake."
- **Review past post-mortems** for repeat incidents. A recurring incident class means the fixes were superficial.

### 5. Availability arithmetic — the numbers you must be able to do live
**Serial composition (all must work):** multiply.
```
Availability = A₁ × A₂ × … × Aₙ
```
A request through LB (99.99%) → API (99.9%) → auth (99.9%) → DB (99.95%):
`0.9999 × 0.999 × 0.999 × 0.9995 ≈ 0.9973` → **99.73%**, even though every component is "three nines or better". **You cannot build a 99.9% service out of serial 99.9% dependencies.**

**Parallel composition (any one suffices):** multiply the *unavailability*.
```
A = 1 − ((1−A₁) × (1−A₂))
```
Two independent nodes at 99.9%: `1 − (0.001 × 0.001) = 0.999999` → **99.9999%**. Redundancy is enormously powerful — *if the failures are independent*.

**The catch (say it):** failures are **not independent**. A shared AZ, a shared config, a common library version, one deployment pipeline, one DNS provider, one cloud region, or a correlated load pattern couples them. **Real-world availability after redundancy is far below the arithmetic** because of common-cause failures. That's why you diversify: multi-AZ, multi-region, multiple DNS providers, staged rollouts, and independent failure domains.

**The retry trap:**
```
Effective load with retries = original × (1 + retries) × callers
```
A client retrying 3× on failure, with 5 services in a chain, can amplify load **exponentially** during an incident — **retry storms are how a partial failure becomes a total outage.** Mitigations: **exponential backoff with jitter**, a **retry budget** (e.g. retries ≤ 10% of requests), retry only on idempotent operations, **circuit breakers**, and don't retry at every layer (retry at one layer only, ideally the outermost).

**Other numbers to have ready:**
- Downtime per nines (see [`10-Observability`](../10-Observability/README.md#12-sli--slo--sla--get-the-definitions-exact)): 99.9% = 43.2 min/30 days; 99.99% = 4.32 min.
- **MTBF / MTTF / MTTR**: `Availability = MTBF / (MTBF + MTTR)`. **Improving MTTR usually beats improving MTBF** — you can't stop failures, but you can get faster at recovering. This reframing is a strong SRE signal.
- **RTO** (how long you can be down) and **RPO** (how much data you can lose) — set by the business, and they determine your backup/failover architecture. A 5-minute RPO requires continuous replication, not nightly backups.

---

## 🔵 Advanced

### 6. Error budgets in practice — the policy, not just the math
**Definition:** `error budget = 1 − SLO`, over a window (usually a rolling 30 days or a calendar month).

At 99.9% over 30 days, you may spend **43.2 minutes** of unavailability (or 0.1% of requests failing).

**The policy — this is the part most teams skip:**
| Budget state | Policy |
|---|---|
| **> 50% remaining** | Ship freely. Take risks. Run game days and chaos experiments **against production**. Do the risky migration now |
| **25–50%** | Normal velocity; extra scrutiny on risky changes; canary windows lengthened |
| **< 25%** | Only reliability work and low-risk changes; increased review; no risky migrations |
| **Exhausted (0%)** | **Feature freeze.** All engineering capacity goes to reliability until the budget recovers. Launches blocked |
| **Repeatedly exhausted** | The SLO is wrong (too tight for the architecture) **or** the architecture is wrong (under-invested). Escalate to leadership with data — this is a funding conversation, not an engineering one |

**Why it works (the insight to articulate):**
> "The reliability-vs-velocity conflict is unresolvable as a values debate — the product team wants speed, the SRE team wants stability, and whoever shouts loudest wins. An error budget converts it into a **shared, quantified resource with a pre-agreed spending policy**. When the budget is gone, the freeze isn't the SRE team blocking product; it's the policy both teams agreed to when the numbers were calm. That's why it has to be agreed *in advance* and owned by leadership, not invented during an argument."

**Practical details that show experience:**
- **Rolling vs calendar window**: rolling 30d smooths out month-boundary games (a team burning the whole budget on the 1st then freezing); calendar months align with business reporting. Rolling is technically better; calendar is easier to communicate. Many use rolling with a monthly review.
- **Multiple SLOs per service** (availability + latency) → multiple budgets; the binding constraint is the min.
- **Planned vs unplanned**: decide whether maintenance windows count. My answer: **user-visible unavailability counts, regardless of intent** — otherwise you game it by labelling outages "planned". But *scheduled, notified, off-peak* maintenance can be excluded by pre-agreement.
- **Budget burn rate alerting** is what makes it real-time (see [`10-Observability`](../10-Observability/README.md#9-alerting-philosophy--what-makes-alerting-good-or-bad)).
- **Error budget reporting to leadership** monthly, with the trend and the policy state. This is how reliability gets funded.
- **The failure mode:** an error budget nobody enforces is a dashboard. You need a written policy, leadership backing, and the willingness to actually freeze — **once**. After the first real freeze, the policy is credible.

### 7. Resilience patterns — the full toolbox with when to use each
| Pattern | Problem it solves | Key parameters | Failure mode if misconfigured |
|---|---|---|---|
| **Timeouts** | A hung dependency consumes your resources forever | Must be **shorter than the caller's timeout** (nested budgets shrink inward); connect vs read vs total | Too short → false failures + retries; too long → thread exhaustion |
| **Retries + backoff + jitter** | Transient failures | Exponential backoff, **equal or decorrelated jitter**, **retry budget**, max attempts, idempotency required | **Retry storms** amplify load; retrying non-idempotent ops duplicates side effects |
| **Circuit breaker** | Repeatedly calling a known-dead dependency | Failure-rate threshold, window size, half-open probe count, open duration | Tripping on a partial failure and cutting off healthy traffic; not resetting |
| **Bulkheads** | One slow dependency consumes all resources | Separate thread/connection pools per dependency or tenant | Over-partitioning wastes capacity |
| **Rate limiting** | Overload from clients (or yourself) | Token bucket / sliding window; per-tenant + global; fail-open vs fail-closed | Limiting legitimate traffic; IP-based limits hurting NAT users |
| **Load shedding** | Survival under overload | Priority classes; shed cheapest/least-important first; **shed early, at the edge** | Shedding your most valuable traffic; shedding too late (resources already exhausted) |
| **Backpressure** | Propagate congestion upstream instead of buffering to death | Bounded queues; reject when full (429/503 + `Retry-After`) | Unbounded queues → OOM instead of a clean rejection |
| **Graceful degradation** | Serve something useful when a dependency is down | Cached/stale data, defaults, reduced functionality | Serving stale data that's *wrong* rather than merely old |
| **Fallbacks** | Alternate path when primary fails | Secondary provider, read replica, cache, static content | Fallback untested → fails when needed (**test it**) |
| **Isolation / cell architecture** | Contain blast radius | Sharded "cells" each serving N users; failure affects one cell | Routing complexity; cross-cell operations |
| **Idempotency keys** | Safe retries for mutations | Client-generated key, server-side dedupe store with TTL | Not enforcing them → duplicate charges |
| **Chaos engineering** | Verify resilience claims | Steady-state hypothesis, blast radius control, production-first | Running it without a hypothesis = just breaking things |
| **Health checks + auto-restart** | Self-healing from stuck states | Liveness vs readiness distinction | Restart loops masking a real bug; restarting away the evidence |

**Retry + jitter, precisely:**
```
sleep = min(cap, base * 2**attempt)          # exponential
sleep = sleep/2 + random(0, sleep/2)         # "equal jitter" — AWS-recommended
# or decorrelated jitter: sleep = min(cap, random(base, prev_sleep * 3))
```
**Why jitter is non-negotiable:** without it, N clients that failed at the same instant all retry at the same instant → a **synchronised thundering herd** that re-kills the recovering service. Jitter decorrelates them. **This is a very common interview probe — name "thundering herd" explicitly.**

**Circuit breaker states:** `CLOSED` (normal) → failure rate exceeds threshold → `OPEN` (fail fast, no calls) → after `reset_timeout` → `HALF_OPEN` (allow N probe requests) → success → `CLOSED`, failure → `OPEN`. **The subtle point:** in `HALF_OPEN` you must limit concurrency to the probe count, or the whole flood hits the recovering service at once and it dies again.

### 8. Disaster recovery — tiers, testing, and the honest gaps
**Recovery objectives drive architecture:**
| RTO / RPO | Architecture required | Cost |
|---|---|---|
| RTO hours, RPO 24h | Backups to object storage, rebuild from IaC | Low |
| RTO ~1h, RPO ~5min | Standby environment, continuous DB replication, IaC-tested rebuild | Medium |
| RTO minutes, RPO ~0 | **Multi-AZ active-active**, synchronous replication, automated failover | High |
| RTO seconds, RPO 0 | **Multi-region active-active**, global load balancing, conflict resolution | Very high |

**DR strategies (AWS terminology, generalises):**
1. **Backup & restore** — cheapest, slowest.
2. **Pilot light** — core data tier replicated and running small; compute scaled up on failover.
3. **Warm standby** — a scaled-down full stack always running; scale up on failover.
4. **Hot standby / active-active** — full capacity in both; traffic split or instant shift.
5. **Multi-site active-active** — both serving real traffic. **The hardest part isn't the infra, it's data consistency** (conflict resolution, latency between regions, write ownership — single-writer-per-region vs CRDTs vs last-write-wins).

**The senior points:**
- **Untested DR is a hypothesis, not a capability.** Failover that has never been exercised fails during the real disaster — usually because of hardcoded endpoints, DNS TTLs, secrets that don't exist in region B, an IAM role that wasn't replicated, a database extension not installed, or a dependency that only exists in one region. **Schedule game days; make failover routine.**
- **DNS TTL matters**: a 1-hour TTL means an hour of users pinned to the dead region. Use low TTLs (30–60s) for failover records — but understand the trade-off (more DNS queries, and resolvers ignore TTLs anyway).
- **Failover itself can cause an outage** — the standby has been cold, its caches are empty, its connection pools are unwarmed, and it takes 100% of traffic instantly → **it collapses under load it has never seen**. Mitigate: keep the standby warm with real (or synthetic) traffic, capacity-test it, and ramp traffic gradually on failover.
- **Failback is harder than failover** and is usually the untested part: data written in region B during the incident must be reconciled back.
- **Dependencies are the real constraint.** Your multi-region app is only as available as its single-region database, its one DNS provider, its single SaaS auth vendor. **Map the dependency graph and find the single-region/single-vendor components — that's your actual DR posture.**
- **Backup integrity**: encryption keys must be recoverable independently of the primary account (a compromised/deleted account shouldn't take the backups with it), cross-account/cross-org backup vaults, **immutable/object-locked backups** (ransomware protection), and **restore drills with measured RTO**.

### 9. Capacity planning
**The question it answers:** "Will we have enough resources, at the right time, at acceptable cost?"

**Method:**
1. **Establish the demand model.** Historical traffic with seasonality (daily, weekly, holiday), growth trend, and **known upcoming events** (launches, marketing campaigns, migrations). Use p95–p99 of demand, not the average.
2. **Establish the capacity model.** What's the actual limit of one unit? **Load test to find it** (the theoretical answer is always wrong): requests/second per pod at the SLO latency, not at saturation. **Capacity is defined by the SLO, not by the point of failure** — a service that serves 1,000 rps at 5s latency has a capacity of whatever it serves at 300 ms.
3. **Find the binding constraint.** It's rarely the app: usually the database (connections, IOPS, lock contention), a downstream API's rate limit, a cloud quota (ENIs, IPs per instance type, Lambda concurrency), network bandwidth, or a connection pool. **Model the whole chain and take the minimum.**
4. **Apply headroom.** Typical: **N+1 or N+2 for AZ failure**, plus 30–50% for spikes and autoscaler lag, plus growth over the lead time to add capacity (hardware has weeks-to-months lead time; cloud has minutes but quotas don't).
5. **Set thresholds and automate.** Scale at 60–70% utilisation, not 90% (autoscaling has lag; by 90% you've already lost latency). Alert on **trend**, not just level (`predict_linear`).
6. **Re-validate quarterly** and after every major change. Capacity models rot.

**The insights that separate seniors:**
- **Utilisation vs latency is non-linear.** Queueing theory (M/M/1: wait ∝ ρ/(1−ρ)) means latency explodes as utilisation approaches 100%. At 70% you're fine; at 90% you're already degraded; at 95% you're in a death spiral. **This is the mathematical justification for headroom**, and citing it is a strong signal.
- **Autoscaling has a reaction time** — HPA + cluster autoscaler can be 5–10 minutes (metrics window → new pods → Pending → new node → boot → CNI → image pull). For spiky traffic you need over-provisioning (pause pods with low priority that get preempted), predictive scaling, Karpenter, or scale-from-zero warm pools.
- **Scale-up must be tested at the real rate.** A system that can scale from 10 to 100 pods but takes 20 minutes doesn't survive a viral spike.
- **The database doesn't autoscale.** Compute is elastic; state isn't. Capacity planning is mostly database planning.
- **Cost is a capacity constraint** — the answer isn't always "add nodes".
- **Quotas are silent capacity limits.** AWS service quotas, Kubernetes `ResourceQuota`, connection limits, port ranges, conntrack table size. **Audit quotas proactively; hitting one during an incident is a horrible way to discover it.**

### 10. Chaos engineering — done properly
**Definition (Principles of Chaos):** "a disciplined approach to identifying failure conditions in steady-state systems by experimenting on a distributed system to build confidence in its capability to withstand turbulent conditions in production."

**The method:**
1. **Define steady state** with measurable indicators (SLO metrics: success rate, latency, throughput). **Without a hypothesis, chaos engineering is just breaking things.**
2. **Hypothesise** that steady state will hold in both control and experimental groups.
3. **Introduce real-world variables**: node kill, AZ failure, latency injection, packet loss, DNS failure, dependency 500s, clock skew, disk full, CPU saturation, certificate expiry, quota exhaustion, region failover.
4. **Minimise blast radius** — run in production (that's the point; staging doesn't have production's topology or data) but on a small slice, with an abort switch and a defined stop condition.
5. **Measure, learn, fix, and re-run** until the hypothesis holds.
6. **Automate and schedule** — a one-off experiment is a story; a continuous programme is a capability.

**Tools:** **LitmusChaos** (CNCF, Kubernetes-native, ChaosHub), **Chaos Mesh** (CNCF, Kubernetes-native, rich fault types incl. JVM/kernel/IO/network), **Gremlin** (commercial, safest onboarding), **AWS Fault Injection Service**, **toxiproxy** (application-level latency/fault injection), **Pumba** (Docker).

**The maturity framing that scores:**
> "Chaos engineering is the *verification* step of reliability work, not a substitute for it. You design for failure with redundancy, timeouts, circuit breakers and graceful degradation; then you *test* those claims, because untested resilience claims are wrong about half the time. The order matters: teams that start with chaos before they have SLOs and dashboards just generate incidents without learning anything, because they can't measure steady state. And I'd start with game days — a scheduled, facilitated, human-in-the-loop experiment — before automated continuous chaos, because the value early on is in the conversation it forces, not the automation."

**Game days specifically:** scheduled events where a team practices responding to a simulated failure. Value: validates runbooks, finds undocumented dependencies, trains new on-call engineers, tests communication paths and escalation, and surfaces the gaps that no design review finds. **Run them quarterly; write up findings as tracked action items.**

### 11. On-call — designing a rotation that doesn't burn people out
**Principles:**
- **Enough people**: a minimum of 6–8 in a rotation for a 24/7 primary+secondary (Google's guidance: ≥ 8 for a comfortable 25% on-call load; fewer than 6 is unsustainable). Below that, use follow-the-sun across regions or a managed service.
- **Compensate**: pay for on-call time (not just pages), and give **time off in lieu** after a rough night. If the organisation won't pay, it should reduce the load.
- **Bounded load**: target **≤ 2 pages per 12-hour shift**, and **≤ 25% of time on-call** for a single team member. Track it; act when breached.
- **Actionable pages only.** Every page requires intelligent action; everything else is a ticket or a dashboard. **This is the single biggest lever on on-call quality.**
- **Runbooks for every alert**, tested, with the diagnostic commands and the mitigation steps. An alert without a runbook should be deleted or demoted.
- **Escalation path** with a clear secondary and a manager; escalation must be free of stigma.
- **Handover ritual**: a written and verbal handoff at rotation change — active issues, recent changes, known flakiness, things to watch.
- **Shift quality metrics**: pages per shift, % actionable, % pages caused by a recent deploy, MTTR, interrupt count, and **a self-reported quality survey** (people leave over bad on-call long before the metrics show it).
- **Feedback loop into engineering**: every page gets triaged in a weekly review — fix the cause, tune the alert, or delete it. **The on-call engineer's job is to make themselves unnecessary**, and the team's job is to fund that.
- **Shadowing and training** before solo rotation; a "on-call for the first time" pairing week.
- **Tools that reduce pain**: reliable paging (PagerDuty/Opsgenie with phone/SMS fallback), mobile access to dashboards, the ability to roll back from a phone, and **an incident channel template** so the process starts automatically.

**Burnout signals to name:** rising page counts tolerated as normal, people swapping shifts constantly, cynicism about alerts ("just restart it"), attrition in the team, and action items from post-mortems not being completed. **All of these are management failures, not individual failures** — and framing them that way is the mature answer.

---

## 🔴 Scenario

### 12. "You're paged at 3am: the checkout service is returning 500s for 40% of requests. Walk me through it."
**Minute 0–2 — Orient before acting.**
- **Acknowledge the page** (so escalation doesn't fire), open the incident channel, declare **SEV1** (40% failure on a revenue path is unambiguous).
- **Assign roles even in a small incident**: "I'm IC; Sam, take ops; Priya, comms and scribe." **If you're alone, say so in the channel and pull someone in** — an IC who is also debugging and also doing comms will run a longer incident.
- **Open the dashboard and answer three questions**: since when? which percentile/what proportion? what changed?

**Minute 2–5 — Correlate with change.**
```bash
# What deployed? What changed?
kubectl rollout history deploy/checkout -n prod
git log --since="3 hours ago" --oneline -- config/ infra/
# Check: deploys, config/ConfigMap changes, feature flags, migrations,
# infra applies, cert rotations, dependency releases, traffic anomalies
```
**If a deploy happened near the start of the incident → roll back first, investigate second.** "Rollback is the fastest mitigation available and it costs 2 minutes. I'd take it even if I suspect something else, because if I'm wrong I've learned that in 2 minutes, and if I'm right the outage is over."

**Minute 3–8 — Scope and localise (in parallel with mitigation).**
- **Which pods/nodes/AZs/regions?** `kubectl get pods -o wide`, per-instance error rate.
  - **One pod** → kill it (`kubectl delete pod`), then examine the corpse (logs `--previous`, profile, thread dump).
  - **One AZ** → AZ-level problem (network, cloud provider event). Check the cloud status page and node health; consider failing over.
  - **All of them** → shared dependency, shared config, or a code regression.
- **Which errors?** Read the actual error, don't guess:
  ```bash
  kubectl logs deploy/checkout -n prod --tail=200 --prefix
  kubectl logs deploy/checkout -n prod --previous | grep -i -E 'error|panic|exception' | tail -50
  ```
  Classify: `5xx` from the app (exception, panic), `502/504` from the proxy (app not responding / timed out), `503` (circuit open, pool exhausted, shedding), DB errors (connection refused, timeout, deadlock, pool exhausted), dependency errors (downstream 5xx), TLS/cert errors, DNS timeouts.
- **Which dependency?** Check per-downstream latency/error metrics and traces. Open one failing trace — it usually shows the failing span directly.
- **Is it saturation?** CPU throttling, memory/OOMKills, connection pool utilisation + wait time, thread/goroutine count, DB connections vs `max_connections`, disk IOPS, conntrack, fd count.

**Minute 8–15 — Mitigate with the highest-leverage lever available.** Ranked by speed and safety:
1. **Roll back the deploy** (`kubectl rollout undo`) or **disable the feature flag** (seconds, no deploy).
2. **Restart/replace the bad pod(s)** — after capturing evidence.
3. **Scale out** — if saturation is the cause and the bottleneck is compute (not the DB).
4. **Shed load / rate-limit** — if overload is the cause; protect the 60% that works rather than losing 100%.
5. **Fail over** the database or the AZ — highest impact, highest risk; only with confidence.
6. **Increase a limit** (pool size, timeout) — a band-aid that buys time; note it as tech debt.
7. **Roll forward with a fix** — last resort, only if rollback is impossible (e.g. an irreversible migration).

**Verify mitigation with evidence, not hope:** define the success condition *before* acting ("error rate < 0.5% for 5 consecutive minutes") and watch it.

**Minute 15+ — Stabilise, communicate, preserve.**
- Comms every 15–30 min: what's happening, what's the impact, what's been done, what's next, ETA for the next update. **Update the status page** if customer-facing.
- **Preserve evidence for root cause**: the failing pod's logs, a profile/heap/thread dump, the trace samples, the metrics screenshots, the timeline. **Then** restart/replace.
- **Don't declare resolved prematurely** — watch for 15–30 minutes of stability, check the downstream effects (retry backlog draining, cache rebuild, queue catch-up).
- Schedule the post-incident review within 48 hours while memory is fresh.

**Then the systemic work:**
- Was detection fast enough? (MTTD — if a customer reported it before the page, that's a finding.)
- Would an automated rollback have caught this? (Canary + metric analysis.)
- Was there a guardrail missing? (A CI check, an admission policy, a test.)
- Was the runbook accurate? (If the on-call had to improvise, update it.)

**The framing that scores:** "I follow **orient → correlate → localise → mitigate → verify → learn**, and I keep mitigation and root-causing separate. In the first 15 minutes I am not trying to understand the bug; I'm trying to restore service using the cheapest reversible lever, while someone captures the evidence needed to understand it later. Teams that debug before mitigating turn a 20-minute incident into a 4-hour one."

### 13. "Our MTTR is 90 minutes. How would you halve it?"
**Decompose MTTR first** — you can't fix a number you can't break down:
```
MTTR = MTTD (detect) + MTTA (acknowledge/assemble) + MTTI (identify/localise) + MTTM (mitigate) + MTTV (verify)
```
Measure each for the last 20 incidents. **In most organisations MTTD and MTTI dominate** — the incident was live for 25 minutes before anyone knew, and 40 minutes before anyone knew *where*.

**Attack each component:**

**MTTD (detection) — usually the biggest win:**
- **SLO burn-rate alerting** on user-facing symptoms with a fast-burn window (2% budget in 1 hour → page within ~2–5 minutes). Threshold alerts on CPU/latency are slower and noisier.
- **Alert on absence** (`absent()`, "no successful requests in 5m") — a service that stops doing anything is often not detected by error-rate alerts (no requests = no errors).
- **Synthetic probes** from outside, on the real user path — catches DNS, TLS, CDN, LB and regional failures that server-side metrics can't see.
- **Track "% of incidents found by monitoring vs by a customer".** Target > 90% monitoring-first. **This single metric is the clearest signal of detection maturity** and it's easy to report to leadership.
- **Deploy annotations + a change feed** so "what changed" is answered instantly.

**MTTA (acknowledge/assemble):**
- Reliable paging (phone/SMS fallback), a clear primary/secondary, an **auto-created incident channel** with the alert, dashboard links, runbook link and recent changes pre-posted (PagerDuty/Opsgenie/Rootly/incident.io automation).
- **Reduce time-to-context**: the page itself should contain the current value, the threshold, the affected scope, the runbook link and a one-click dashboard link. **A page that just says "HighErrorRate firing" costs 5 minutes of orientation.**

**MTTI (identify/localise) — the second-biggest win:**
- **Traces with tail sampling** so any slow/erroring request can be localised to a span in one click.
- **Log↔trace correlation** via `trace_id` — the pivot from "which service" to "which error" is what takes 20 minutes without it and 30 seconds with it.
- **Standard dashboards per service** (same layout, same variables) so anyone can navigate any service. On-call shouldn't require service-specific knowledge.
- **Runbooks that are diagnostic trees**, not prose: "if X, check Y; if Y is Z, do W." Include the exact commands.
- **Access**: on-call must have read access to logs, metrics, traces, cloud consoles and the cluster **without requesting it at 3am**. Just-in-time access with a fast approval path for write.
- **Topology documentation**: what depends on what. Half of localisation is knowing what *could* be involved.

**MTTM (mitigate):**
- **Make rollback one command and tested.** `kubectl rollout undo`, `git revert` + auto-sync, feature-flag off. **If rollback takes 20 minutes, that's your MTTR floor.**
- **Prefer reversible levers**: flags > rollback > restart > scale > failover > roll-forward.
- **Automated remediation** for known, well-understood failure modes (a controller that restarts a wedged pod, drains a node, fails over a replica) — but only after the manual procedure is proven and documented. **Automate the second time, not the first.**
- **Automated rollback on canary analysis failure** (Argo Rollouts) — removes the human from the fastest part of the loop.
- **Break-glass procedures**, documented and drilled.

**MTTV (verify):**
- Pre-agreed **resolution criteria** per alert (error rate < X for N minutes) so "is it fixed?" isn't a debate.
- Watch for second-order effects: retry backlogs draining, cache rebuilds, queue catch-up, connection storms.

**The structural changes beyond tooling:**
- **Game days** quarterly — practise the whole loop, including comms and escalation. **MTTR improves most from rehearsal, not from dashboards.**
- **Reduce the number of things that can break**: fewer moving parts, fewer dependencies, standardised stacks. Complexity is the root cause of long incidents.
- **Post-mortem action item completion rate** — if fixes never land, MTTR never improves. Track it as a team metric.
- **Follow-the-sun on-call** if MTTR is dominated by "waiting for someone to wake up".
- **Blast radius reduction** (cells, progressive delivery, feature flags) so incidents are smaller, which makes them faster to resolve.

**The closing framing:** "I'd measure the decomposition for 20 incidents, then fix the largest component — which is usually detection or localisation, not mitigation. The two highest-leverage single changes are typically: **SLO burn-rate alerting with synthetic probes** (kills MTTD) and **trace-to-log correlation with standard dashboards and diagnostic-tree runbooks** (kills MTTI). And I'd rehearse it, because the difference between a team that has the tools and a team that has *practised* the tools is 30 minutes at 3am."

### 14. "Design a reliability programme for a company that has never had one."
**Sequence by value; don't try to do everything.**

**Phase 1 — Make the current state visible (weeks 1–4)**
- **Inventory**: services, owners, dependencies, criticality tiers (Tier 0 = revenue/safety, Tier 1 = important, Tier 2 = internal). **You cannot apply SRE uniformly; tiering is what makes it affordable.**
- **Baseline metrics**: current availability per Tier 0 service (measured, not asserted), incident count, MTTR, on-call load, deploy frequency, change failure rate.
- **Instrument the basics** if missing (see [`10-Observability`](../10-Observability/README.md#18-we-have-no-observability-build-a-strategy-from-zero-for-a-30-service-platform)).
- **Establish the incident process**: severity definitions, IC/comms/scribe roles, a channel template, an escalation path, a status page. **Write it on one page.**
- **Start the on-call rotation properly** — with runbooks, compensation, and a page-quality target.

**Phase 2 — Set targets and get agreement (weeks 4–8)**
- **Define SLIs and SLOs for Tier 0 services only** (5–10 services). Involve product and leadership: the SLO is a business decision, not an engineering one.
- **Agree the error budget policy in writing, with leadership sign-off.** This is the pivotal moment — without it, SLOs are decoration. Get the freeze policy agreed while everyone is calm.
- **Switch alerting to symptom-based / burn-rate** for those services; delete the noisy cause-based pages.
- **Start blameless post-incident reviews** for every SEV1/SEV2, with tracked action items.

**Phase 3 — Reduce the load (months 2–4)**
- **Measure toil**, rank it, and fund the top 5 automations. Target < 50% ops time.
- **Resilience pass on Tier 0**: timeouts everywhere, retries with jitter and budgets, circuit breakers on external dependencies, bulkheads/pool isolation, graceful degradation for non-critical dependencies, idempotency keys on mutations. **This is a finite, high-value project — not a permanent state.**
- **Fix the top 3 recurring incident causes** from the post-mortem data.
- **DR: define RTO/RPO with the business**, implement the matching tier, and **run the first failover test**.
- **Capacity model** for Tier 0 with headroom policy and quota audit.

**Phase 4 — Verify and harden (months 4–8)**
- **Game days** quarterly: AZ failure, dependency outage, DB failover, region failover, cert expiry, on-call handover with a surprise.
- **Chaos experiments** in production with blast radius control, once steady state is measurable.
- **Progressive delivery** everywhere (canary + automated analysis + auto-rollback) — this is the single biggest change-failure-rate reducer.
- **Extend SLOs to Tier 1**; standardise the service template so new services arrive with observability, SLOs, alerts, runbooks and resilience defaults baked in.
- **Reliability review as a gate** for new services and major changes (an engagement checklist: SLO defined? runbook exists? on-call trained? dependencies mapped? failure modes analysed? rollback tested?).

**Phase 5 — Sustain (ongoing)**
- **Monthly reliability review** with leadership: SLO attainment, error budget state, incident trends, MTTR decomposition, toil %, action item completion, on-call quality.
- **Quarterly SLO recalibration** — SLOs that are never revisited become fiction.
- **Report the outcome metrics, not the activity metrics**: "customer-visible downtime down 70%, MTTR from 90 to 35 minutes, 85% of incidents detected before customer report, on-call pages down 60%" — that's what keeps the programme funded.

**The organisational realities to name (this is what makes the answer senior):**
- **You need executive sponsorship before you need tooling.** An error budget policy without a VP backing it will be overridden the first time it blocks a launch, and then it's dead.
- **Start with one or two services, prove the value, then expand.** A big-bang SRE transformation across 200 services fails.
- **SRE is a negotiating position, not a police force.** If the team is perceived as blocking, it will be routed around.
- **Hire/build for software engineers who like operations**, not operators who tolerate code. The discipline is engineering.
- **The measure of success is that reliability decisions become data-driven and boring** — nobody argues about whether to freeze, because the budget says so.

### 15. "A third-party API you depend on is down and there's no ETA. What do you do?"
**Immediate (minutes):**
1. **Confirm it's them, not you.** Check their status page *and* verify independently (your client-side error metrics, a direct curl, a different network path, another region). **Assuming it's the vendor wastes time; assuming it's you wastes more.**
2. **Quantify the blast radius**: which user journeys are affected, what % of requests fail, is it degrading or fully down, are we retrying (amplifying their problem and ours)?
3. **Stop making it worse**: **reduce retries immediately** (or disable them) — a retry storm consumes your threads/connections and slows your recovery when they come back. Enable the **circuit breaker** so you fail fast instead of timing out (timeouts hold resources far longer than immediate failures).
4. **Mitigate by dependency criticality:**
   - **Non-critical path** (recommendations, analytics, personalisation) → **degrade gracefully**: serve defaults, cached results, or hide the feature entirely behind a flag. Users rarely notice.
   - **Critical path with a fallback** (secondary provider, cached data) → **fail over**. If you have a multi-vendor strategy, use it — and note that the fallback must have been tested, or you're about to discover it doesn't work.
   - **Critical path, no fallback** → **shed load deliberately**: queue the work for later (if it's deferrable — e.g. async enrichment), return a clear "temporarily unavailable" with a retry hint, or take the affected feature offline with an honest message. **A clean, honest degradation beats a hung, spinning page.**
5. **Protect your own system from cascading failure**: thread/connection pool isolation (bulkheads) so the dead dependency can't exhaust your capacity; request deadlines shorter than the vendor's timeout; queue bounded with backpressure; and **watch your own saturation metrics** — the second-order failure (your pool exhausting) is often worse than the first.
6. **Communicate**: status page, customer comms if the impact is user-visible, internal updates on a cadence. **Contact the vendor through the escalation path** (TAM, support contract, exec channel) — and log the incident with them, since you'll want the RCA and possibly a credit.

**During the outage (hours):**
- **Monitor for partial recovery** and be ready to ramp back gradually — a vendor coming back often gets crushed by accumulated retries from all their customers (**thundering herd**), so re-enable traffic progressively rather than flipping the circuit breaker to full.
- **Backfill**: if you queued or skipped work, plan the catch-up (rate-limited, so you don't re-overload them or yourself).
- **Keep the mitigation in place** until they've been stable for a meaningful period.

**Afterwards (the part that determines whether it happens again):**
- **Post-incident review** with the vendor's RCA as an input, not an answer.
- **Architectural fixes, in order of leverage:**
  1. **Timeouts + circuit breakers + retry budgets** on every external call (should already exist; if not, this is finding #1).
  2. **Cache aggressively** — even a 60-second cache absorbs a short outage; **stale-while-revalidate** serves old data during an outage, which for many use cases is fine.
  3. **Multi-vendor / multi-provider** for anything business-critical (two SMS providers, two payment processors, two DNS providers). **Cost: integration work, consistency between providers, split-brain concerns.** Worth it only above a criticality threshold.
  4. **Async decoupling** — turn synchronous dependency calls into a queue-backed workflow so a vendor outage delays work rather than failing requests.
  5. **Contract/SLA review** — a vendor with no SLA and no support contract is a business risk, not just a technical one. Escalate it with the incident data.
- **Add the vendor to your dependency risk register** with: criticality, SLA, historical availability (measured by *you*, not by them), fallback status, and blast radius. **Review it quarterly.**
- **Test the fallback.** Add "vendor X is down for 30 minutes" to your game-day rotation. **An untested fallback is a hypothesis.**

**The framing that scores:** "The technical answer is timeouts, circuit breakers, retry budgets, caching and fallbacks. The senior answer is that **every external dependency is a reliability decision you made when you chose it**, and it needs an entry in a risk register with a criticality tier, a measured availability, and a documented fallback — because the moment you find out you don't have one is during the outage, and that's the most expensive possible time to discover it."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "Our target is 100% uptime" | Signals you don't understand error budgets or cost curves |
| SLA tighter than SLO | Contractually promising more than you target |
| Root cause = "human error" | You stopped one layer too early |
| The IC debugging in a terminal | Nobody is coordinating; the incident runs longer |
| Mitigating only after understanding the bug | 45-minute incident becomes 4 hours |
| No scribe / no timeline | The post-mortem is fiction |
| Action items with no owner or date | They will not happen |
| Retries without jitter or a budget | You built a retry storm amplifier |
| Timeouts longer than the caller's | Nested budgets broken; the caller gives up first |
| Never testing DR or fallbacks | Untested resilience is a hypothesis |
| Chaos experiments without a steady-state hypothesis | Just breaking things |
| On-call with > 2 pages/shift tolerated as normal | Burnout, attrition, and a reliability death spiral |
| Alerts without runbooks | 3am improvisation |
| Capacity planned on averages | p99 demand and queueing theory say otherwise |
| Scaling at 90% utilisation | Autoscaler lag means you're already degraded |
| Ignoring cloud/service quotas in capacity planning | A silent limit discovered during the incident |
| Error budget policy agreed *during* an argument | It won't hold |

## Rapid recall

1. SRE = treating ops as a software problem; DevOps is the culture, SRE is the discipline with mechanisms (SLOs, error budgets, toil caps, engagement criteria).
2. Toil: manual, repetitive, automatable, tactical, no enduring value, scales with growth. **Cap at 50%**; measure, rank, fix causes, delete, self-service.
3. Incident roles: **IC (does not debug)**, ops lead, comms lead, scribe. Declare severity; hand over explicitly.
4. **Mitigate before root-causing**; preserve evidence before restarting; timebox hypotheses; communicate on a cadence.
5. Post-mortem: timeline, quantified impact, what went well/badly/lucky, contributing factors (not one root cause), owned+dated action items, MTTD/MTTA/MTTM/MTTR. **"Human error" is not a root cause.**
6. Availability math: serial = multiply, parallel = 1 − Π(1−A). **Correlated failures break the arithmetic.** Retries multiply load; budget them and jitter them.
7. `Availability = MTBF/(MTBF+MTTR)` → **improving MTTR usually beats MTBF**.
8. Error budget = 1 − SLO; the **policy** (freeze when exhausted, take risks when full) is the point; leadership must sign it in advance.
9. Resilience toolbox: timeouts (nested budgets shrink), retries+backoff+**jitter**+budget, circuit breaker (limit half-open concurrency), bulkheads, rate limiting, **load shedding early**, backpressure with bounded queues, degradation, fallbacks (**tested**), cells, idempotency.
10. Queueing theory: latency ∝ ρ/(1−ρ) → **that's why you keep headroom** and scale at 60–70%.
11. DR: RTO/RPO set by the business determine the tier (backup/pilot light/warm standby/active-active). **Untested DR is a hypothesis**; failover can itself cause an outage (cold caches); failback is harder; **dependencies define your real posture**.
12. Chaos: steady-state hypothesis → real-world fault → minimise blast radius → measure → fix → automate. Game days first.
13. On-call: ≥ 6–8 people, ≤ 2 pages/shift, ≤ 25% time, compensated, runbooks, escalation without stigma, handover ritual, weekly alert triage, quality survey.
14. MTTR = MTTD + MTTA + MTTI + MTTM + MTTV. Fix the largest component — usually **detection** (SLO burn-rate + synthetics + absent alerts) or **localisation** (traces + trace↔log correlation + diagnostic-tree runbooks).
15. Vendor outage: confirm it's them, kill retries, open the breaker, degrade by criticality, bulkhead to prevent cascade, ramp back gradually, then cache/multi-vendor/async-decouple and **test the fallback**.
16. New programme: tier services → baseline → incident process → SLOs on Tier 0 → **written error-budget policy with exec sign-off** → toil reduction → resilience pass → DR test → game days → progressive delivery → template it into new services → monthly leadership review with outcome metrics.

→ Next: [`12-Cloud-AWS`](../12-Cloud-AWS/README.md)
