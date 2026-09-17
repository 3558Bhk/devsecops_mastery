# RTIQ — Terraform Monitoring & Messaging on AWS (Real-Time Interview Questions)

> **Cloud:** AWS · **Tool:** Terraform · **Domain:** SQS/SNS/EventBridge, CloudWatch alarms/dashboards/logs · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~18 min

**How this file is used live:** SRE/platform interviewers use these topics to check whether you build observability *into* infrastructure as code, and whether your messaging design survives failure. Expect "what alerts would you create by default?", "how do you alert on a dead-letter queue?", and "what happens when the consumer is down for an hour?"

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. Messaging (SQS, SNS, EventBridge) — `messaging.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for SQS?
**A.** `aws_sqs_queue` (with `visibility_timeout_seconds`, `message_retention_seconds`, `redrive_policy`, `kms_master_key_id`), `aws_sqs_queue_policy` (who can send/receive), `aws_sqs_queue_redrive_allow_policy` (on the DLQ), and `aws_lambda_event_source_mapping` for consumers.
2. **Q:** How do you wire a DLQ in Terraform?
**A.** Create the DLQ, then set `redrive_policy { deadLetterTargetArn = aws_sqs_queue.dlq.arn, maxReceiveCount = N }` on the main queue and `redrive_allow_policy` on the DLQ allowing the source queue. Two resources, and the second is the one people forget (causing a policy error or a non-interactive redrive).
3. **Q:** SNS topic + subscriptions in Terraform?
**A.** `aws_sns_topic` (+ `kms_master_key_id` for encryption), `aws_sns_topic_subscription` per protocol/target (SQS with `raw_message_delivery = true`, Lambda, HTTPS), and `aws_sqs_queue_policy` on each subscribing queue allowing `sns.amazonaws.com` with `aws:SourceArn` conditions.
4. **Q:** EventBridge in Terraform?
**A.** `aws_cloudwatch_event_bus` (custom bus), `aws_cloudwatch_event_rule` (event pattern), `aws_cloudwatch_event_target` (Lambda/SQS/Step Functions), plus `aws_lambda_permission` for the target, and `aws_cloudwatch_event_archive`/`aws_cloudwatch_event_permission` for replay and cross-account publishing.
5. **Q:** How do you scale consumers from Terraform?
**A.** For Lambda: event source mapping settings (`batch_size`, `maximum_batching_window_in_seconds`, `function_response_types = ["ReportBatchItemFailures"]`, `scaling_config.maximum_concurrency`). For ECS/EC2: autoscaling policies on a custom backlog-per-consumer metric (`ApproximateNumberOfMessagesVisible / running tasks`).
6. **Q:** Where does the FIFO decision happen?
**A.** On the resource: `fifo_queue = true` + `content_based_deduplication` (or explicit `MessageDeduplicationId`), plus `message_group_id` for ordering. It's a design decision with throughput implications — not a config detail you flip later (queue type can't be changed in place).
7. **Q:** How do you encrypt queues/topics?
**A.** `kms_master_key_id` with a CMK you control (or `alias/aws/sqs`), and grant the producers/consumers `kms:Decrypt`/`GenerateDataKey` in their policies. SSE is not just a flag — the permissions must follow.
8. **Q:** How do you grant cross-account publish/consume?
**A.** Resource policy on the queue/topic (`aws_sqs_queue_policy`/`aws_sns_topic_policy`) allowing the specific account/role with `aws:SourceArn`/`aws:PrincipalOrgID` conditions, plus the caller's identity policy allowing the send/receive action. Both sides, always.

**🔍 Deep dive**
9. **Q:** Design an event-driven order pipeline and the Terraform for it.
**A.** API → SQS (buffer, encrypted, DLQ after N receives) → Lambda with partial batch failures and reserved concurrency → DynamoDB (idempotency + state) → EventBridge bus for domain events → SNS topics or per-consumer SQS queues for fan-out (bucket-per-consumer with DLQs) → downstream services consuming their own queues. Terraform: a messaging module creating queue+DLQ+policy+alarms as a unit (so no queue lands without a DLQ), EventBridge rules with explicit targets and permissions, alarms on backlog age/DLQ depth/consumer errors, and idempotency storage as part of the module. Every async hop gets a DLQ and an alarm — that rule alone prevents most silent data loss.
**↳ Follow-up:** "How do you choose between SQS-fan-out and EventBridge?"
**A.** EventBridge for content-based routing (many event types, filtering with patterns, SaaS/AWS sources, archive/replay) and for cross-service contracts; SNS+SQS when you need massive fan-out with per-consumer buffers and independent retries. Both are often used together: EventBridge routes domain events, SNS/SQS scales delivery to consumers.
10. **Q:** How do you make messaging resilient to consumer outages?
**A.** Buffering (queues absorb spikes/outages), retention long enough for the worst plausible outage (`message_retention_seconds`, up to 14 days), visibility timeouts > processing time with heartbeats for long jobs, DLQ + alarms, and idempotent consumers so replays are safe. Also alarm on `ApproximateAgeOfOldestMessage` — depth alone doesn't tell you the SLA impact.
11. **Q:** How do you avoid the classic visibility-timeout duplicate?
**A.** Set `visibility_timeout_seconds` ≥ 6× the function's timeout (AWS's own recommendation for Lambda+SQS) or at least greater than p99 processing time, use heartbeats (`ChangeMessageVisibility`) for long-running consumers, and make handlers idempotent with a dedup store. Terraform owns the timeout; the app owns idempotency — say both.
12. **Q:** How do you do ordered processing at scale?
**A.** FIFO queue with `message_group_id` per entity (order per customer/order, parallel across groups), `content_based_deduplication` where appropriate, and consumer concurrency aligned so groups aren't processed concurrently. Watch throughput limits (FIFO is lower than standard) and avoid using one group for everything.
13. **Q:** How do you alert on messaging health in Terraform?
**A.** Alarms on DLQ `ApproximateNumberOfMessagesVisible` > 0 (page), main-queue `ApproximateAgeOfOldestMessage` beyond SLA, `ApproximateNumberOfMessagesVisible` trend for capacity, Lambda `Errors`/`Throttles` for the consumer, and EventBridge `FailedInvocations`/DLQ for rules. Add a dashboard per domain (message flow, backlog, age, error rate) so the on-call sees the whole pipeline.
14. **Q:** How do you handle schema evolution in events?
**A.** Register schemas (`aws_schemas_registry`/`aws_schemas_schema`) and validate, version events explicitly in the payload or via separate detail-types, and keep consumers tolerant (ignore unknown fields) so producers can add fields safely. Removing/renaming fields is a breaking change requiring a new event version and a migration window.
15. **Q:** How do you structure messaging modules in a repo?
**A.** A `queue` module (queue + DLQ + policy + alarms + optional Lambda mapping) and a `topic`/`event_rule` module, with name conventions and encryption on by default; consumers call the module rather than hand-rolling resources. This is how you guarantee "no queue without a DLQ and an alarm" across 40 teams.

**🚨 War room**
16. **Q:** A DLQ is filling but nobody was paged. What do you fix?
**A.** Add the missing alarm (DLQ depth > 0 pages; consider a threshold > 1 to avoid noise on transient blips), then triage the messages: reason codes, error signatures, and whether the cause is fixed. Replay deliberately (idempotent, rate-limited). Then make it systemic: the queue module should create the alarm so a queue can't exist without one.
17. **Q:** Messages expired before processing during a long outage.
**A.** Retention (`message_retention_seconds`) was shorter than the outage — increase it (up to 14 days) and alarm on age approaching retention. For business-critical flows, also archive messages to S3/DynamoDB at send time so an outage can't erase the backlog. TTL/retention is a business decision about how long you can be down, not a default.
18. **Q:** The same order was processed twice. Diagnose and fix.
**A.** At-least-once delivery plus a non-idempotent handler (or a re-visible message due to a visibility timeout shorter than processing). Fix with idempotency keys stored transactionally with the side effect (DynamoDB conditional writes), align the visibility timeout with the function timeout, and add monitoring on duplicate-processing attempts. Terraform sets the timeouts; the app enforces idempotency.
19. **Q:** An EventBridge rule stopped delivering.
**A.** Check the rule's target (deleted/renamed Lambda, changed queue), the target's resource policy/permissions, the DLQ configuration (EventBridge retries then drops without a DLQ), and whether the event pattern changed. Also verify the producer is publishing to the same bus. Configure a DLQ on every rule target — this is exactly the failure it protects against.
20. **Q:** Queue depth is growing linearly and the consumer is healthy but slow.
**A.** Compare arrival rate vs processing rate, check whether the consumer is scaling at all (concurrency caps, reserved concurrency, autoscaling metric wrong), whether downstream is the bottleneck (DB latency), and whether one poison message is blocking a batch. Levers: raise consumer concurrency/batch size, temporarily increase capacity, and move poison messages aside; then fix the arithmetic (either capacity or throughput) — backlog management is arithmetic, not instinct.
21. **Q:** Costs spiked on messaging with stable traffic.
**A.** Check for polling inefficiency (short polling instead of long polling `WaitTimeSeconds = 20` — Terraform sets this on the event source mapping), excessive `SQS API calls` from consumers, encryption requests (KMS), Lambda invocations from batch size being too small, and EventBridge/HTTP endpoint deliveries. Long polling and batching are the two cheapest wins.
22. **Q:** A queue's `redrive_policy` was removed in an apply.
**A.** Restore it immediately (the DLQ relationship is a safety net, not a nice-to-have) and check whether any messages were already lost/never dead-lettered during the window. Then add a CI policy check that fails plans removing a `redrive_policy` or a DLQ alarm — these are the kinds of guardrails that belong in code review.

**⚖️ Trade-off**
23. **Q:** SQS vs SNS vs EventBridge vs Kinesis?
**A.** SQS: work queues with per-message ack and independent consumer scaling. SNS: pub/sub fan-out to many protocols with no replay. EventBridge: event routing/filtering with SaaS sources, schema registry, and archive/replay. Kinesis: ordered streams with replay for multiple consumers and analytics. Choose by consumer count, ordering/replay needs, and routing complexity — and be able to name the failure model of each.
24. **Q:** Standard vs FIFO queues?
**A.** Standard: unlimited throughput, at-least-once, best-effort ordering. FIFO: ordering per message group with dedup, at lower throughput and higher cost. Only use FIFO where ordering is a real requirement; use message groups to preserve parallelism, since a single group serialises everything.
25. **Q:** Fan-out to N consumers: SNS with N SQS subscriptions vs N queues published directly?
**A.** SNS decouples the producer from subscriber count (publish once, add consumers without touching the producer) with per-subscription filters; direct publishing means the producer knows its consumers (tighter coupling, but simpler permissions and no SNS hop). For a growing consumer set, SNS/EventBridge; for a fixed small set with strong coupling, direct.
26. **Q:** Alarms from the module vs alarms written by each team?
**A.** Module-created defaults guarantee coverage (DLQ, age, error rate) with consistent thresholds; teams can add domain-specific ones. Hand-rolled alarms mean gaps discovered during incidents — and "we didn't alarm on that" is the most common postmortem finding.
27. **Q:** Encryption with a CMK vs the AWS-managed key for queues?
**A.** A CMK gives you control (key policy, cross-account grants, audit of key use) and is usually required for sensitive data, at the cost of KMS request charges and permission plumbing on every producer/consumer. AWS-managed keys are simpler but you can't scope or audit usage the same way.
28. **Q:** Synchronous HTTP calls vs async messaging between services?
**A.** Sync is simpler to reason about and gives immediate responses but couples availability (the caller fails when the callee does) and amplifies load; async decouples and buffers at the cost of eventual consistency, ordering/idempotency work, and harder debugging. Commands that need answers stay sync; state changes/notifications become events.
29. **Q:** Event archive/replay: worth the complexity?
**A.** Yes when you need to rebuild projections, recover consumers that missed events, or add a new consumer and backfill it — EventBridge archive + replay gives that without re-emitting from producers. The cost is storage and the discipline of idempotent consumers (replays deliver duplicates).

**🎯 Senior**
30. **Q:** What does production-ready messaging infrastructure include in Terraform?
**A.** Every queue/topic with encryption (CMK where sensitive), a DLQ with a redrive policy and an alarm on depth, retention aligned with the maximum tolerable outage, visibility/batch settings matched to consumer behaviour, idempotency support (dedup store) and reserved concurrency/scaling config on consumers, correlation IDs propagated through message attributes, alarms on backlog age and consumer errors, a dashboard per domain, event schemas registered with versioning, and EventBridge targets with DLQs. All of it created by a module so it's consistent, not per-team craft.

**🎯 Senior signal:** "no queue without a DLQ and an alarm", alerting on age of oldest message rather than depth, and retention as a business decision. Those three come from having been paged.

---

## 2. Monitoring & Alerts — `monitoring-alerts.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for CloudWatch?
**A.** `aws_cloudwatch_metric_alarm`, `aws_cloudwatch_composite_alarm`, `aws_cloudwatch_log_group` (with `retention_in_days`), `aws_cloudwatch_log_metric_filter` + `aws_cloudwatch_metric_alarm` for log-based alerts, `aws_cloudwatch_dashboard`, `aws_sns_topic` for the alarm action, and `aws_cloudwatch_event_rule` for event-driven alerting.
2. **Q:** How do you create an alarm properly?
**A.** `aws_cloudwatch_metric_alarm` with namespace/name/dimensions, `statistic`/`extended_statistic` (use p95/p99 for latency, not Average), `period`, `evaluation_periods`, `datapoints_to_alarm`, `treat_missing_data` (explicitly — `breaching` for availability-critical metrics), and `alarm_actions` pointing at an SNS topic.
3. **Q:** Why `treat_missing_data`?
**A.** The default (`missing`) can leave an alarm in OK when data stops arriving — a silent failure. Set `breaching` for metrics that must always report (heartbeats, availability) and `notBreaching` only where gaps are genuinely fine. This is a favourite SRE question.
4. **Q:** How do you alert on log patterns?
**A.** `aws_cloudwatch_log_metric_filter` (pattern + metric transformation) → `aws_cloudwatch_metric_alarm`. Good for error keywords/HTTP 5xx counts/exceptions; prefix with structured logs so the pattern is precise rather than regex soup.
5. **Q:** How do you alert on infrastructure events (deletions, state changes)?
**A.** `aws_cloudwatch_event_rule` with an event pattern (e.g. CloudTrail `DeleteDBInstance`, EC2 state changes, Config compliance changes) → SNS/Lambda target with appropriate resource policy. Activity-style alerting for "someone changed production" belongs here.
6. **Q:** How do you set log retention?
**A.** Always create `aws_cloudwatch_log_group` with `retention_in_days` and let other resources reference it; otherwise services create groups with "never expire" and the bill grows forever. Also tag groups for attribution.
7. **Q:** What goes in a dashboard vs an alarm?
**A.** Alarms are for actionable, paging conditions; dashboards are for diagnosis and context (golden signals, capacity, dependency health, deploy markers). Building an alarm per metric is how alert fatigue starts.
8. **Q:** How do you reference alarms for auto-scaling/deployments?
**A.** `aws_autoscaling_policy`/CodeDeploy deployment groups can reference alarm ARNs (`alarm_specification`/`alarms`), so a breaching alarm pauses scaling or rolls back a deployment. Wiring the alarm into the deployment is where monitoring becomes control.

**🔍 Deep dive**
9. **Q:** Design the default observability package your platform module adds to every service in Terraform.
**A.** Alarms: 5xx rate (ALB target-level), p95 latency (TargetResponseTime), unhealthy host count, ASG/task capacity headroom, DLQ depth, oldest-message age, Lambda errors/throttles, RDS connections/CPU/free storage, and a synthetic canary for availability. Dashboards: golden signals per service plus dependency latency and deploy markers. Log groups with retention and a metric filter for error rate. SNS topics for page/ticket channels with subscriptions managed centrally. All parameterised (thresholds as inputs with sane defaults) so a new service inherits the whole package with one module call.
**↳ Follow-up:** "How do you avoid 200 alarms firing for one incident?"
**A.** Use composite alarms (`aws_cloudwatch_composite_alarm`) that fire only on a combination (e.g. 5xx high AND healthy hosts low), route alerts by severity (page vs ticket) through separate SNS topics, and add EventBridge suppression for planned maintenance. The dashboards show everything; the pager shows only user-impacting conditions.
10. **Q:** How do you alert on a business KPI rather than infrastructure?
**A.** Custom metrics (or log metric filters/EMF) for domain events (orders/min, sign-ins, payment success rate), with alarms on deviation from a band (static or `ANOMALY_DETECTION_BAND`), and a clear owner. Infra-green + business-red is the worst outage class, so at least one KPI must be alarmed per critical journey.
11. **Q:** How do you parameterise thresholds across environments?
**A.** Module inputs with environment-specific tfvars (prod pages at tighter thresholds with longer evaluation, dev uses looser/ticket-only or disabled), plus variables for paging vs non-paging SNS topics. This keeps one module and avoids copy-pasted alarms per environment.
12. **Q:** How do you monitor the infrastructure that Terraform manages (meta-monitoring)?
**A.** Alarms on state backend access failures, on pipeline failures (CodeBuild/CodePipeline/CI events → SNS), on `terraform plan` drift jobs reporting changes, and on Config compliance. If nobody knows your infrastructure is drifting or your pipeline is broken, the observability of the services themselves doesn't help.
13. **Q:** How do you handle alarm ownership and routing in a multi-team setup?
**A.** One SNS topic per team/on-call rotation (or per severity channel), alarms reference the owning team's topic, and tags record the owner. Add a periodic report listing alarms with no subscriptions/no recent activity so orphans get cleaned up — unowned alarms get ignored, and then nobody trusts the pager.
14. **Q:** How do you do alerting as code across many services without duplication hell?
**A.** A `service-observability` module that takes the resource identifiers (ALB ARN, target group, ASG/Lambda name, queue) and creates the full standard set with naming conventions; services call it once. Changes to thresholds/standards then propagate via a module version bump, which is the leverage you want as a platform team.
15. **Q:** How do you test alarms?
**A.** Deliberately trigger them in non-prod (force a 5xx, publish to the DLQ, stop a consumer), confirm the page reaches the right channel within the expected time, and record it as part of the service onboarding/drill checklist. An untested alarm is a hypothesis.

**🚨 War room**
16. **Q:** An incident happened but no alarm fired. What do you do?
**A.** Establish the symptom that should have alerted (user impact, error rate, latency, availability), then check whether the metric existed, whether the alarm was created/attached to the right dimension, whether `treat_missing_data` masked it, and whether thresholds/evaluation periods were too lenient. Fix, add the missing signal, and add a test to the onboarding checklist — postmortem action items should include monitoring, not just code.
17. **Q:** The pager went off 14 times overnight for the same non-issue.
**A.** Silence/tune the specific alarm (thresholds, evaluation periods, composite conditions), convert it to a ticket/dashboard if it's not actionable, and if it's an autoscaling trigger rather than an incident, remove it from paging. Track pages-per-shift as a metric and treat high volume as a defect to fix — otherwise people start ignoring the pager, which is the real risk.
18. **Q:** Alarms are firing in dev/staging and drowning real alerts.
**A.** Route non-prod alarms to a different (non-paging) SNS topic by default via the module, and only escalate specific ones deliberately. Environment-separated routing should be a default of the observability module, not something each team configures.
19. **Q:** After a region/AZ event, dozens of alarms fired and nobody could tell what the root cause was.
**A.** Use composite alarms and dependency-aware dashboards so the top-level symptom is clear, add region/AZ dimensions to metrics where available, and publish an "incident dashboard" (service map + dependency health) that the on-call opens first. Also make sure Service Health events are routed to the same channel so platform events are visible alongside service alarms.
20. **Q:** Log ingestion costs exploded.
**A.** Find the top log groups by volume (CloudWatch Logs Insights/usage), reduce verbosity in production (log levels), set retention per group, exclude noisy categories at the source (or use metric filters instead of storing everything), and consider exporting high-volume logs to S3 for cheap retention. Terraform-side: retention and log-group configuration are code — make the standard the default.
21. **Q:** An alarm exists but has no subscribers (nobody gets paged).
**A.** Attach the correct SNS topic (and verify subscriptions with confirmed endpoints), then add a check — a scheduled query/report identifying alarms whose actions have no subscribers or whose topics have no confirmed endpoints. Silent alarms are worse than no alarms because they build false confidence.
22. **Q:** Two teams are creating alarms that overwrite each other's dashboards/log groups.
**A.** Naming collisions (same metric filter/log group names) — enforce naming conventions in the module (`<service>-<env>-<purpose>`) and give each service its own log group/dashboard. Shared names are a sign the resource ownership boundary is wrong.

**⚖️ Trade-off**
23. **Q:** Metric alarms vs log-based alarms vs composite alarms?
**A.** Metric alarms are fast, cheap, and reliable for thresholds (use for paging); log-based alarms detect patterns/errors in text but cost per GB scanned/ingested and add latency; composite alarms combine signals to reduce noise. Default: metric alarms for paging, log filters for specific error classes, composites where a single metric is too noisy.
24. **Q:** One shared observability module vs per-service alarms?
**A.** Shared module with per-service parameters gives standard coverage, consistent naming, and easy propagation of improvements; per-service hand-written alarms drift and leave gaps. The module should be opinionated with escape hatches for genuine exceptions.
25. **Q:** Static thresholds vs anomaly detection?
**A.** Static thresholds are predictable and explainable (good for hard SLOs like 5xx > 1%); anomaly detection adapts to diurnal patterns (good for traffic/latency where "normal" varies) but can hide slow degradation and is harder to justify in a postmortem. Use both: static for SLO-critical, anomaly bands for busy metrics.
26. **Q:** CloudWatch-only vs a third-party observability stack?
**A.** CloudWatch integrates natively, is cheap to start, and works with IaC cleanly; third parties offer better correlation/UX and cross-cloud views at a real cost. Many teams keep alarms in CloudWatch (closest to the resource) and ship metrics/logs to a third party for exploration — Terraform can manage the CloudWatch side plus the exporter/firehose.
27. **Q:** Alert on causes (CPU) or symptoms (latency/errors)?
**A.** Symptoms page; causes live on dashboards and drive autoscaling. Cause-based paging produces noise (CPU high but serving fine) and misses failures that don't show in the cause metric. Say it directly — it's a classic senior-vs-junior separator.
28. **Q:** Should Terraform own dashboards?
**A.** Yes for standard, templated per-service dashboards (consistent golden signals, easy to propagate); ad-hoc exploration dashboards can live outside Terraform. Managing them as code prevents the classic "dashboard nobody updated since the redesign".

**🎯 Senior**
29. **Q:** What's your monitoring-as-code standard for a new service?
**A.** A single module call that creates the standard alarms (availability/synthetic, 5xx rate, p95 latency, capacity headroom, backlog age/DLQ depth, error/throttle metrics), routes them to the team's paging topic with correct severity, creates the golden-signal dashboard with deploy markers, creates log groups with retention and error metric filters, and sets `treat_missing_data` deliberately for each alarm. Thresholds come from SLOs and are reviewed after every incident; pages-per-shift is tracked as a quality metric; and every alarm is tested at least once before the service goes live.

**🎯 Senior signal:** "alert on symptoms, dashboard on causes", `treat_missing_data = breaching` for heartbeats, and "an untested alarm is a hypothesis". Those three are what SRE panels listen for.
