# RTIQ — AWS Monitoring & Governance (Real-Time Interview Questions)

> **Cloud:** AWS · **Domain:** CloudWatch, CloudTrail, AWS Config · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~15 min

**How this file is used live:** for SRE and platform roles this topic *is* the interview. They will ask what you instrument, how you page, how you investigate a 3 a.m. incident, and how you prove compliance afterwards. Vague answers ("we have dashboards") end the round; numbers, alarm design, and postmortem fixes carry it.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. CloudWatch — `cloudwatch.md`

**⚡ Rapid**
1. **Q:** What do you alarm on, minimum?
**A.** The four golden signals: latency (p99 `TargetResponseTime`), traffic (requests), errors (`HTTPCode_Target_5xx`), saturation (CPU/queue depth/connections). Plus availability (`UnHealthyHostCount`) and a business KPI (checkout success rate) — because infra-green + business-red is the worst outage type.
2. **Q:** Metric alarm vs composite alarm — when do you use composite?
**A.** Composite when a single metric is too noisy alone but a combination means real trouble (e.g. CPU high **AND** latency high **AND** healthy-host count dropping) — it's how you cut alert fatigue without lowering sensitivity.
3. **Q:** What's the difference between detailed and standard monitoring?
**A.** Standard = 5-minute metrics (free); detailed = 1-minute (paid per metric). 1-minute granularity matters for fast-changing autoscaling and short-lived spikes; most production alarms should use 1-minute metrics with 2–3 datapoints to alarm.
4. **Q:** Where do your logs live and for how long?
**A.** CloudWatch Logs with explicit retention per log group (never "never expire" by default) and a tiering/export decision: hot in CloudWatch for querying, archived to S3/Glacier for compliance. Name the numbers you actually use.
5. **Q:** What is EMF (Embedded Metric Format)?
**A.** Emitting structured JSON logs that CloudWatch turns into metrics at no per-metric cost — the standard way to get custom business/queue metrics without a metric-per-dimension bill blow-up.

**🔍 Deep dive**
6. **Q:** Design monitoring for a payments API. What pages, and at what thresholds?
**A.** Symptoms page, causes dashboard. Page on: p99 latency > SLA (e.g. 800 ms for 3 × 1 min), 5xx rate > 1% for 5 min, availability < 99.9% (synthetic canary), payment success rate drop, and error-budget burn (fast/slow burn windows). CPU/memory/queue → dashboards + Slack, not pages.
**↳ Follow-up:** "How do you decide a threshold?"
**A.** From the SLA and real traffic: pick the value that predicts user harm (from load tests and past incidents), set the datapoints-to-alarm so a single blip doesn't page, then review after every false page and tune. Thresholds are living config in Terraform, not tribal knowledge.
7. **Q:** How do you handle noisy alerts? Give a concrete example.
**A.** Replace a bare CPU>80% alarm with a composite (CPU high for 15 min AND request count above baseline AND p99 rising), or convert it to an auto-scaling trigger and keep only the symptom alarm. Track a "pages per on-call shift" metric and treat >2 actionable pages/night as a bug to fix.
8. **Q:** How do you correlate logs across microservices during an incident?
**A.** Structured JSON logs with a request/trace ID propagated through every hop (`X-Amzn-Trace-Id` from X-Ray/OTel), one log group per service with a consistent schema, CloudWatch Logs Insights queries joining by trace ID, and X-Ray/OpenTelemetry service map for the topology. Without correlation IDs, you're grepping.
9. **Q:** Logs Insights query to find the slowest requests in the last hour — roughly what do you write?
**A.** `fields @timestamp, requestId, path, duration | filter duration > 1000 | sort duration desc | limit 50` — the point is filtering on structured fields, not regex-scanning free text. Mention you'd index/parse once and query many times.
10. **Q:** How do you monitor something that only happens rarely (e.g. a nightly job that fails silently)?
**A.** Heartbeat/synthetic: a metric that must appear (cloudwatch `IF`-style missing-data treatment, or a canary Lambda that publishes on success and alarms on absence), plus a log-based metric alarm on error patterns. Missing-data treatment (`breaching` vs `notBreaching` vs `missing`) is the classic silent-outage trap — say it explicitly.

**🚨 War room**
11. **Q:** 3 a.m. page: "p99 latency high" on a service you've never touched. First 10 minutes?
**A.** Acknowledge, check the dashboard's blast radius (one AZ? one endpoint? one customer?), check recent deploys/Config changes in the blast window, check downstream dependencies' latencies, look at saturation metrics (connections, threads, queue depth), then correlate with a trace sample of a slow request. Communicate status to stakeholders before you're sure of the root cause.
12. **Q:** Metrics say healthy, customers say broken. What's missing?
**A.** Your monitoring is on infrastructure, not user journeys: add synthetic canaries (CloudWatch Synthetics), real user monitoring, and business KPIs. This is the answer that separates SRE-minded candidates — "we were green because we were measuring the wrong thing".
13. **Q:** A metric you depend on stops reporting. What happens and how do you design against it?
**A.** Default `missing` → alarm may stay OK, leaving a blind spot. Fix: treat missing data as `breaching` for availability metrics, add an alarm on metric age/heartbeat, and alert on `InsufficientData` transitions for critical alarms.
14. **Q:** CloudWatch costs doubled last month. Investigate and reduce.
**A.** Look at custom metrics × dimensions (the #1 driver — high-cardinality dimensions), logs ingestion (chatty debug logs in production), stored logs without retention, and `GetMetricData` API calls from dashboards. Fix: EMF + fewer dimensions, log level discipline, retention policies, S3 export/archival, and dashboards that query less often.

**⚖️ Trade-off**
15. **Q:** Alarm on causes (CPU) or symptoms (latency/errors)?
**A.** Page on symptoms, diagnose with causes. Cause-based alarms are noisy and don't map to user impact; keep them as dashboard/autoscaling signals.
16. **Q:** CloudWatch Logs vs S3+Athena vs a third-party (Datadog/Splunk)?
**A.** CloudWatch is cheapest to start and integrates natively, but expensive at volume with weaker query language. S3 + Athena/OpenSearch is cheap for audit/long-term. Third-party gives better UX/correlation at higher cost. Many shops: CloudWatch for alarms and short-term, export to S3/third-party for the rest.
17. **Q:** One central monitoring account vs per-team stacks?
**A.** Central account for cross-account dashboards, alarms and aggregation (with cross-account observability); teams own their resources and alarm definitions via IaC. Centralisation without ownership = nobody's alarm.

**🎯 Senior**
18. **Q:** How do you measure and improve your own on-call health?
**A.** Track pages per shift, % actionable, MTTA/MTTD/MTTR, and error-budget burn; review every page in a weekly ops review; kill or automate anything that pages twice for the same cause; and hold blameless postmortems with tracked action items. Show a before/after (e.g. 12 pages/night → 2).

**🎯 Senior signal:** golden signals + error budgets + "alert on symptoms" + missing-data treatment. Say "we were green because we measured the wrong thing" and you sound like someone who's been on call for real.

---

## 2. CloudTrail — `cloudtrail.md`

**⚡ Rapid**
1. **Q:** What is CloudTrail, in one line, and what does it *not* capture?
**A.** An audit log of AWS API activity (who did what, when, from where) across management events by default. It does not capture data-plane reads inside a service (S3 object reads unless you enable data events, DynamoDB item reads) or OS-level activity (that's SSM/agents).
2. **Q:** Management vs data events — and the cost implication?
**A.** Management events (create/delete/modify resources) are on by default; data events (S3 GetObject, Lambda Invoke, DynamoDB item ops) are high-volume and charged — enable selectively for sensitive buckets/tables only.
3. **Q:** Where must the trail deliver, and why an org trail?
**A.** S3 (with SSE-KMS + versioning + lock), optionally CloudWatch Logs for alerting, and an organisation trail so every account and new account is covered automatically. An org trail is table stakes for governance.
4. **Q:** How do you make the trail tamper-evident?
**A.** Log file validation (digest files) + S3 Object Lock (WORM) + restricted delete permissions + lifecycle to Glacier for retention. Then you can prove no one edited history.
5. **Q:** Default retention?
**A.** Event history in the console covers 90 days; anything longer requires the S3 delivery. Compliance windows (1 year, 7 years) are why the S3 bucket and lifecycle policy exist.

**🔍 Deep dive**
6. **Q:** Someone deleted a production RDS instance. Reconstruct what happened.
**A.** CloudTrail event `DeleteDBInstance` → principal (role/user, source IP, user agent), whether it was console/CLI/Terraform (user agent + `requestParameters`), whether MFA was used, the CloudTrail events immediately before (who granted that permission, was the role just assumed?). Correlate with SSO/session logs and CI logs. Then Config for the before-state and backup/PITR for recovery.
**↳ Follow-up:** "It was a Terraform apply — how do you find *why*?"
**A.** CI logs from the apply run, the PR that changed the config, the plan output, and the pipeline actor. This is why pipeline logs need the same retention and immutability as CloudTrail.
7. **Q:** How do you alert on the top 10 risky events in near-real time?
**A.** EventBridge rules over CloudTrail for: root login, `ConsoleLogin` failures, IAM changes (`CreateUser`, `AttachUserPolicy`, `CreateAccessKey`, `PutRolePolicy`, `UpdateAssumeRolePolicy`), S3 bucket policy/public-access changes, security group 0.0.0.0/0 ingress, KMS key deletion/schedule, `StopLogging`/`DeleteTrail`, GuardDuty disabling, and Config rule deletion. Route to Security Hub + a security channel, with GuardDuty for threat detection.
8. **Q:** How do you detect unusual API activity, not just known-bad events?
**A.** GuardDuty (baseline ML on CloudTrail/VPC/DNS), plus behaviour baselining in a SIEM: new principals doing familiar actions, familiar principals doing new actions, spikes in `AccessDenied` (recon), API calls from new geographies, off-hours activity. Alert on the combination, tune with allow-lists.
9. **Q:** What does "CloudTrail gaps" mean during an investigation, and how do you plug them?
**A.** Missing data events (S3 object reads), missing regions (legacy single-region trails), no OS-level events, and short retention. Fix by multi-region org trail, targeted data events, SSM/Session Manager logging for instance access, and shipping to an immutable lake with long retention.
10. **Q:** How do you give auditors what they want without giving away the farm?
**A.** A read-only security/audit role scoped to the log archive account, cross-account access to an Athena table over the S3 trail, and pre-built saved queries per control. Auditors get evidence on demand; they never get write or delete access.

**🚨 War room**
11. **Q:** An engineer with no prod permissions appears in CloudTrail deleting an Auto Scaling group. Hypothesis tree?
**A.** (1) They assumed a role they shouldn't be able to (trust policy too broad). (2) They went via a CI identity (check user agent). (3) Credentials shared/leaked. (4) Console session hijack (check source IP/device). (5) A runaway automation acting on their behalf. Then contain: revoke sessions, rotate, tighten trust policy.
12. **Q:** CloudTrail stops recording for 20 minutes. Now what?
**A.** This is a sev-1. Check who called `StopLogging`/`DeleteTrail` (EventBridge should have alerted), check S3 bucket policy/KMS key changes that broke delivery, check service health, then re-enable and backfill if possible. Treat any gap during that window as suspicious by default and review all activity.
13. **Q:** Root account was used. What do you do?
**A.** Alert is already the goal — root should be locked with MFA, no access keys, and used only for the handful of root-only tasks. Immediately: verify it was authorised, rotate root credentials + password, review all root activity in the window, remove any access keys, and confirm org SCPs prevent API use by root.

**⚖️ Trade-off**
14. **Q:** CloudTrail + S3 + Athena vs a full SIEM?
**A.** CloudTrail+Athena is cheap and great for forensics/compliance queries; a SIEM gives correlation, threat intel, and real-time detections — at a real cost and with an owner required. Start with CloudTrail + GuardDuty + EventBridge alerts, graduate to a SIEM when you have the team to run it.
15. **Q:** Data events everywhere vs selectively?
**A.** Selectively — high-volume data events can multiply your bill for little detection value. Enable for sensitive buckets (PII, secrets, backups) and specific tables; use S3 access logging + GuardDuty for breadth if needed.
16. **Q:** Central log archive account — worth the friction?
**A.** Yes for any regulated environment: separation of duties, immutable retention, one place to query. The friction is access approvals; solve with a scoped read role, not by keeping logs local.

**🎯 Senior**
17. **Q:** Design a governance and forensics baseline for a 60-account org.
**A.** Org CloudTrail → dedicated log archive account (S3 + Object Lock + KMS + Athena), Config recording all resource types with conformance packs, GuardDuty + Security Hub org-wide with delegated admin, EventBridge-based alerting for the risky-event list, SSO with permission sets and MFA, SCP guardrails (regions, no root API, no public S3), and a documented, rehearsed incident-response runbook with an evidence-retention policy.

**🎯 Senior signal:** knowing CloudTrail's blind spots (data events, OS layer) and treating the trail as an immutable evidence store is the difference between "I turned it on" and "I can defend an audit".

---

## 3. AWS Config — `aws-config.md`

**⚡ Rapid**
1. **Q:** What does AWS Config do that CloudTrail doesn't?
**A.** CloudTrail tells you *what happened*; Config tells you *what the resource looks like now and how it changed over time* — configuration items, relationships, and compliance state against rules.
2. **Q:** Managed rule vs custom rule?
**A.** Managed (e.g. `s3-bucket-public-read-prohibited`, `encrypted-volumes`, `required-tags`) cover common controls with no code; custom Lambda rules handle org-specific logic. Most compliance packs are a mix.
3. **Q:** Conformance pack — what is it?
**A.** A bundle of Config rules + remediation as YAML, deployable org-wide. Use AWS's operational-best-practices pack, CIS, PCI-DSS packs as a starting point and trim to what you can actually enforce.
4. **Q:** What is remediation in Config?
**A.** Automatic or manual fixes attached to a rule (SSM Automation documents, e.g. re-enable S3 encryption, remove public access). Automatic remediation only for safe, deterministic fixes; otherwise alert + ticket.
5. **Q:** Does Config record everything by default?
**A.** No — recording is opt-in per resource type; recording *all* supported types is the common baseline in production (with cost consideration), plus recording of global resources like IAM.

**🔍 Deep dive**
6. **Q:** A resource drifts from your Terraform-defined state. How do you detect and fix it?
**A.** Detection: Config rules + `terraform plan` running on a schedule in CI (plan-as-monitor) + Config's timeline on the resource. Fix: either import into Terraform (if the change is desired), revert via apply, or block it structurally — no console write access in prod, SCPs denying the action, and Change Manager for exceptions.
**↳ Follow-up:** "How do you stop the console cowboy in the first place?"
**A.** Read-only console in production, all writes through pipelines, and alarms on Config noncompliance/CloudTrail console-based mutations. Culture plus guardrails, not trust.
7. **Q:** How do you enforce tagging at scale?
**A.** `required-tags` Config rule + SCP denying creation of untagged resources (`aws:RequestedTags`) + tag policies in Organizations + auto-remediation that tags or stops resources. Report on untagged spend weekly; hit the budget owners, not the engineers.
8. **Q:** Which Config rules would you consider mandatory in a security baseline?
**A.** Encrypted volumes/EBS, RDS encryption, S3 public access blocked + SSL-only, security groups without 0.0.0.0/0 on 22/3389, IAM password/root-access-key rules, MFA on root, CloudTrail enabled + validated, GuardDuty enabled, KMS key rotation, no unused credentials, VPC flow logs enabled, and required tags.
9. **Q:** How do you handle a rule that's "noncompliant" but intentionally so (a documented exception)?
**A.** Use rule-level exemptions where supported, or a separate rule set for the exception scope with a documented, time-boxed approval and an owner; silence nothing globally. Auditors want the exception register, not a green dashboard.
10. **Q:** How do you use Config for incident response?
**A.** Config's timeline gives the resource's configuration before/during/after the event — e.g. "the SG was opened at 02:13 and closed at 02:41, exposing X" — which is exactly the blast-radius question. It also proves the remediation happened.

**🚨 War room**
11. **Q:** An S3 bucket was made public in production. Detection and response?
**A.** Detection: Config rule/EventBridge on `PutBucketPolicy`/`PutBucketAcl` + GuardDuty S3 findings + Security Hub. Response: immediately re-apply Block Public Access, review sensitive-object access logs in the exposure window, rotate any exposed credentials found in the bucket, notify per policy, then remediate structurally (SCP deny + auto-remediation).
12. **Q:** 400 resources flip to noncompliant overnight after a rule update. What's your move?
**A.** Confirm it's a rule/pack change rather than 400 real changes (check the rule's version/timestamp and whether the same resources were compliant before), assess whether it's a false positive or a genuine gap, and split into "fix now" (real security exposure) vs "fix by date" with owners. Never mass-exempt to make the dashboard green.
13. **Q:** Your compliance score is 99% but an auditor finds a public bucket. What went wrong?
**A.** Coverage gap — the rule wasn't scoped to that account/region or that resource type wasn't recorded. Fix the blind spots (org-level conformance packs, all-types recording, new accounts auto-enrolled), and add a detective control that's independent of your own rules (GuardDuty/Security Hub + external scan).

**⚖️ Trade-off**
14. **Q:** Config rules vs AWS Security Hub vs custom scripts?
**A.** Config = resource-level compliance and history; Security Hub = aggregated findings, standards (CIS/PCI) and cross-account view; Security Hub consumes Config/GuardDuty/Inspector findings. Custom scripts are for gaps and CI-time checks — never as the primary control plane.
15. **Q:** Auto-remediate everything vs alert-only?
**A.** Auto-remediate safe, reversible, deterministic fixes (public access block, missing encryption, unencrypted volumes where snapshots allow, tag enforcement). Alert on anything that could destroy data or break an app; humans own those decisions with a runbook.
16. **Q:** Config cost vs value with 10k resources?
**A.** Configuration items + rule evaluations scale with resources and changes; use all-types recording only where needed, eval frequency to daily where real-time isn't required, and aggregation across accounts rather than duplicated rules.

**🎯 Senior**
17. **Q:** You're asked to prove "continuous compliance" for PCI in AWS. What's your architecture?
**A.** Org-level CloudTrail + Config with PCI conformance pack, Security Hub PCI standard, GuardDuty + Inspector for detection, centralised log archive with Object Lock, automated remediation for the deterministic controls, exception register with expiry dates, weekly evidence export (Athena/report) and quarterly control testing with the QSA. Compliance is a pipeline output, not a project.

**🎯 Senior signal:** the "99% compliant but a public bucket exists" answer — i.e. thinking about control *coverage* and independence of controls — is what senior cloud/DevSecOps interviewers are fishing for.
