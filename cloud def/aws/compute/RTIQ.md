# RTIQ — AWS Compute (Real-Time Interview Questions)

> **Cloud:** AWS · **Domain:** Compute (AMI, Auto Scaling) · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~9 min

**How this file is used live:** these are the questions actually asked out loud in a 45–60 min senior technical round — not textbook definitions. Interviewers open with a nervous-easy rapid question, then push with "why did you choose that", then drop you into a production incident ("your nodes keep dying, what do you do, walk me through it"). Every answer below is written the way a senior candidate should say it out loud.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room (production incident) · ⚖️ Trade-off debate · 🎯 Senior signal

**Roles this round filters for:** SDE-3 / L5+ ownership, SRE on-call maturity, Platform/Cloud engineer depth on compute lifecycle.

---

## 1. AMI — `ami.md`

**⚡ Rapid**
1. **Q:** What is an AMI, in one sentence, and what makes up its ID?
**A.** A region-scoped snapshot-based template (root volume + launch permissions + block-device mapping). The `ami-xxxx` ID is region-specific, so the same logical image has different IDs per region — hardcoding one ID across regions is an immediate red flag.
2. **Q:** EBS-backed vs instance-store-backed AMI — which do you use in production and why?
**A.** EBS-backed: persistent root volume, stop/start keeps data, can be resized, supports snapshots. Instance-store is ephemeral and mostly legacy/graphics workloads. Production defaults to EBS-backed.
3. **Q:** Where should the AMI ID live in your pipeline?
**A.** Not in code. In SSM Parameter Store / Terraform data source / launch template variable, resolved at deploy time so a new golden AMI doesn't mean a code change.

**🔍 Deep dive**
4. **Q:** Walk me through your golden-AMI pipeline.
**A.** Base image (CIS-hardened) → Packer/EC2 Image Builder builds with patching + agents + app runtime → CIS/Trivy scan gates → AMI tagged with `version`, `build-date`, `source-commit` → published to Parameter Store → launch template/ASG points at the parameter → roll out via instance refresh, canary first.
**↳ Follow-up:** "What if the scan fails after publish?"
**A.** The pipeline fails the build and never publishes the parameter; the previous AMI stays live. That's why publication is the last step, not the first.
5. **Q:** How do you stop AMIs multiplying and blowing up your snapshot bill?
**A.** Retention policy: keep last N per family (`DescribeImages` + owner filter + `CreationDate`), deregister older ones, delete their snapshots (AMI deregistration does *not* delete snapshots), and tag every build. Automate it — manual cleanup always stops happening.
6. **Q:** You share a KMS-encrypted AMI with another account; they can't launch it. Why?
**A.** Two permissions are needed: AMI launch permission *and* KMS key policy/grant allowing the target account `kms:DescribeKey`, `CreateGrant`, `Decrypt`, `ReEncrypt`. Missing the KMS half is the classic answer.
**↳ Follow-up:** "Instance profile role also failing — why?"
**A.** The app's instance profile/role belongs to your account; a cross-account launch needs the instance role to exist and be trusted in *their* account, or you pass a role ARN they own.

**🚨 War room**
7. **Q:** Monday morning: the ASG is launching and terminating instances every 3 minutes. Where do you look first?
**A.** Check ASG activity history and instance lifecycle state. Most common causes: instance failing ELB health check (app not up in time → health-check grace period too short), user-data script exiting non-zero, or a health check path returning 500. Confirm by pulling the instance's console log / SSM session.
8. **Q:** An instance launched from your new AMI won't boot after a kernel change. Immediate mitigation and permanent fix?
**A.** Mitigation: roll the launch template back to the previous AMI version (versioned launch templates make this one parameter), then instance refresh. Fix: reproduce the boot in a lab with console output (`GetConsoleOutput`), fix the driver/kernel module, and add a smoke-test step to the AMI pipeline that boots the image and checks SSM registration.
9. **Q:** Someone deregistered the production AMI 3 months ago; audit wants proof it was patched. How do you answer?
**A.** Tag-based evidence: AMI tags (build date, patch level, CVE scan report in S3/Security Hub), Image Builder/Packer build logs, and CloudTrail `DeregisterImage` event. Pin retention to compliance (e.g. 1 year), never delete evidence AMIs.

**⚖️ Trade-off**
10. **Q:** Rebuild from base vs patch running instances — which and why?
**A.** Rebuild (immutable). Patching live drifts, isn't reproducible, and can't be tested. Rebuild + instance refresh gives you rollback and identical environments.
11. **Q:** Always use the "latest" AMI tag so you're always patched — good idea?
**A.** No. It's unpredictable (deploy today ≠ deploy tomorrow), breaks reproducibility, and can silently pull an unvalidated image. Pin a specific version, promote deliberately.

**🎯 Senior**
12. **Q:** Tell me about an image-related production failure you owned end to end.
**A.** (Structure) Symptom → blast radius → what I checked in the first 5 min → root cause → temporary mitigation (rollback) → permanent fix (pipeline gate) → what I changed in runbooks/monitoring so it couldn't repeat. Mention a number: MTTR, instances affected, cost saved.

**🎯 Senior signal:** they're listening for *immutability thinking* — do you treat servers as cattle, pin versions, and prove rollback. Say "roll back via launch template version" and you sound like an operator, not a candidate.

---

## 2. Auto Scaling — `auto-scaling.md`

**⚡ Rapid**
1. **Q:** Which scaling policy do you use by default and why?
**A.** Target tracking (e.g. keep average CPU at 50%, or ALB request-count-per-target at 1000). It's self-adjusting, needs no threshold math, and handles both scale-out and scale-in.
2. **Q:** Simple vs step vs target tracking — one line each.
**A.** Simple: breach a threshold → one adjustment, has cooldown. Step: graduated adjustments based on breach size. Target tracking: ASG continuously chases a metric value. Target tracking for steady services, step for bursty/graduated patterns.
3. **Q:** What is the `health_check_grace_period` actually for?
**A.** It tells the ASG to ignore health-check failures for N seconds after launch so the app can boot — without it, a healthy-but-slow-booting app gets killed on loop.

**🔍 Deep dive**
4. **Q:** Your service scales on CPU, but CPU is flat and latency is bad. What do you scale on?
**A.** The saturated resource — usually concurrency/queue depth. For workers: SQS `ApproximateNumberOfMessagesVisible` ÷ instances, or `backlog-per-instance` target tracking (custom metric via CloudWatch). For web: ALB `RequestCountPerTarget` or `TargetResponseTime`. Scaling on a symptom metric = scaling too late.
**↳ Follow-up:** "How would you build backlog-per-instance?"
**A.** A Lambda/CloudWatch math metric publishing visible+in-flight messages divided by `GroupInServiceInstances`, then a target-tracking policy on that metric.
5. **Q:** Instance refresh vs blue/green across two ASGs?
**A.** Instance refresh is cheaper and in-place with a min-healthy percentage and can skip matching instances — good for AMI/config updates. Blue/green gives instant rollback and no mixed-version traffic, at 2× cost and more moving parts. Regulated/latency-sensitive → blue/green; standard web fleet → refresh.
6. **Q:** Explain mixed instances policy and when you'd use Spot.
**A.** Several instance families/AZs with on-demand base + Spot allocation strategy for burst capacity — the ASG rebalances on interruption. Use for stateless, fault-tolerant, checkpointed work (batch, CI runners, queue consumers). Never for stateful primary DBs or single-instance services.

**🚨 War room**
7. **Q:** Peak traffic, ASG at max capacity, users see 504s. What do you do *right now*?
**A.** Raise `max_size` immediately (or temporarily remove the cap) to relieve, then diagnose: is it instance count, a downstream bottleneck (DB connections/thread pool), or the ALB itself? Also check whether scale-out even worked — pending instances with capacity errors (Spot) or IAM/limit errors count.
8. **Q:** Scale-out is fast but scale-in keeps killing in-flight requests. Fix?
**A.** Deregistration delay (connection draining) on the target group — 30–60 s for web; enable `scale_in_protected_instances` for long-running jobs; for queue consumers, use lifecycle hooks so the job finishes before termination. Also check that the app handles SIGTERM.
9. **Q:** AZ-a goes down; half the fleet is unhealthy and the ASG isn't rebalancing. What's wrong?
**A.** AZ Rebalance can't exceed desired capacity unless you can grow — so either you're at `max_size` (raise it) or the ASG can't launch in another AZ (subnet/AMI/instance-type unavailability). Also verify ELB health checks are enabled so instances are marked unhealthy at all.
**↳ Follow-up:** "How do you prevent a repeat?"
**A.** Capacity spread across 3 AZs, `max_size` ≥ desired × 1.5–2, capacity-optimized Spot allocation, and an alarm on `GroupInServiceInstances < desired`.

**⚖️ Trade-off**
10. **Q:** Predictive vs dynamic scaling — do you bother?
**A.** Predictive for known diurnal patterns (morning login ramp) so instances exist *before* traffic; dynamic (target tracking) as the safety net. Predictive alone fails on unexpected spikes; dynamic alone always lags.
11. **Q:** Scaling policy or scheduled scaling for a nightly batch?
**A.** Scheduled — you know exactly when the batch runs; waiting for a metric to breach wastes minutes of SLA. Scheduled capacity + target tracking as backstop is the pragmatic answer.

**🎯 Senior**
12. **Q:** Describe a capacity incident where you made the call under pressure.
**A.** Name the metric, the cap that was hit, the customer impact, the immediate lever (raise max, scale manually, shed load), and the permanent fix (capacity headroom policy, load testing, alerts at 70% of max).

**🎯 Senior signal:** seniors never say "we scaled out and it was fine". They name the *binding constraint* — connection limits, AZ capacity, max_size, launch throttling — and how they found it.

---

## Killer cross-topic questions (SDE-3+ filter)

1. **Design a zero-downtime deployment for a 300-instance ASG that must roll out a new AMI and app version.** *(Expect: launch template versioning, instance refresh batch %, warm-up, health checks, rollback plan, observability during rollout.)*
2. **Your ASG scales on CPU and the platform is 40% cheaper if it scales on the right metric. How do you find that metric?** *(Expect: queue depth, concurrency, request-per-target; measure before/after; cost-per-request review.)*
3. **Spot instances power 60% of your fleet. A capacity pool disappears in one AZ. Walk me through the next 10 minutes.** *(Expect: graceful shutdown/SIGTERM handling, checkpointing, diversity across families/AZs, capacity-optimized allocation, alerting.)*
4. **How do you prove to an auditor that every production instance was launched from an approved, patched image?** *(Expect: IaC-only launches, no key pairs/manual SSH, AMI tags + build provenance, SSM, Config rules.)*
5. **You inherit a fleet with no launch template versioning and drifting images. What's your 30-60-90 day plan?** *(Expect: containerize/immutable first, codify, then automate patching with a pipeline and refresh.)*
