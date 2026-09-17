# Amazon CloudWatch — Interview Questions

> **Cloud:** AWS · **Category:** Monitoring & Governance · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

CloudWatch alarms, dashboards, and metric data are JSON (e.g. `put-metric-alarm`, `AWS::CloudWatch::Alarm`, and the metric-data format for custom metrics).

```json
{
  "AlarmName": "high-cpu",
  "MetricName": "CPUUtilization",
  "Namespace": "AWS/EC2",
  "Statistic": "Average",
  "Period": 300,
  "EvaluationPeriods": 2,
  "Threshold": 85,
  "ComparisonOperator": "GreaterThanThreshold",
  "AlarmActions": ["arn:aws:sns:us-east-1:111122223333:oncall"]
}
```

**Key fields:** `MetricName` / `Namespace` / `Dimensions` · `Statistic` (Average/Sum/Maximum/p99…) · `Period` × `EvaluationPeriods` (datapoints to alarm) · `ComparisonOperator` + `Threshold` · `AlarmActions` (SNS/ASG targets).


## Case A — Basic

**A1. What is Amazon CloudWatch?**
**Answer:** AWS's monitoring and observability service that collects metrics, logs, and events, sets alarms, and visualizes dashboards — giving you visibility into AWS resources and applications.

**A2. What are the core CloudWatch components?**
**Answer:** **Metrics** (time-series data), **Alarms** (threshold/action triggers), **Logs** (application/system logs), **Events/EventBridge** (rules reacting to events), **Dashboards** (visualization), and **Synthetics/Contributor Insights** (canaries/top-talkers).

**A3. What is a metric and what is a namespace?**
**Answer:** A metric is a time-ordered set of data points (a variable like CPUUtilization). A **namespace** is a container grouping related metrics (e.g., `AWS/EC2`).

**A4. What is a CloudWatch Alarm and what can it do?**
**Answer:** An alarm watches a metric against a threshold and changes state (OK/ALARM/INSUFFICIENT_DATA), triggering actions like SNS notifications, EC2 actions (stop/terminate/reboot), or Auto Scaling policies.

**A5. What is the difference between basic and detailed monitoring?**
**Answer:** Basic monitoring = metrics every **5 minutes** (free, default). Detailed monitoring = every **1 minute** (paid), enabling faster alarm response and finer Auto Scaling.

**A6. What is the CloudWatch Agent?**
**Answer:** An agent installed on EC2/on-prem servers that collects **system-level metrics** (memory, disk usage, processes) and logs not available by default (EC2 hypervisor metrics don't include guest-OS memory/disk).

**A7. What is a log group and a log stream?**
**Answer:** A **log group** is a container for related logs (e.g., `/aws/lambda/myfunc`); a **log stream** is a sequence of log events from one source (one instance/container/Lambda invocation set).

**A8. What are the three alarm states?**
**Answer:** **OK** (metric within threshold), **ALARM** (threshold breached), **INSUFFICIENT_DATA** (not enough data to evaluate).

**A9. What is CloudWatch Logs Insights?**
**Answer:** A query language and console for interactively searching and analyzing log data (e.g., "count errors by hour") without exporting logs.

**A10. What is a CloudWatch dashboard?**
**Answer:** A customizable view of graphs/metrics/alarms across resources and regions — used for operational overviews and NOC screens.

**A11. What is CloudWatch Synthetics (Canaries)?**
**Answer:** Scripted tests (Node/Python) that run on schedules to monitor endpoints/APIs/UX — detecting issues before users do (e.g., a login-flow canary).

**A12. What is the difference between CloudWatch and CloudTrail?**
**Answer:** CloudWatch = performance/operational monitoring (metrics, logs, alarms). CloudTrail = **audit/API activity** (who did what API call). CloudTrail events can be sent to CloudWatch Logs for alerting.

**A13. How does CloudWatch help Auto Scaling?**
**Answer:** Alarms on metrics (e.g., CPUUtilization, ALB RequestCountPerTarget) drive scaling policies — the control loop that adds/removes instances.

**A14. What are metric dimensions?**
**Answer:** Name/value pairs that identify a unique instance of a metric (e.g., `InstanceId=i-1234`). A metric is uniquely identified by namespace + name + dimensions.

**A15. What is CloudWatch Contributor Insights?**
**Answer:** Analyzes logs to identify the "top-N" contributors (e.g., which IP/API key generates the most traffic/errors) — useful for finding noisy neighbors and hot keys.

---

## Case B — Advanced (Senior)

**B1. Explain CloudWatch's metrics model: namespaces, dimensions, aggregation, and resolution.**
**Answer:** Metrics live in namespaces, are uniquely identified by dimensions, and support **standard resolution (60s)** or **high resolution (1s)** for custom metrics. You aggregate across dimensions (e.g., sum CPU across an ASG) via Metric Math/SEARCH. Understanding the model is key to building correct alarms (e.g., using `Average` vs `Sum` vs `p99`).

**B2. How do you monitor things EC2 doesn't report by default (memory, disk, processes)?**
**Answer:** Install the **CloudWatch Agent**, configure it to collect memory/disk/swap/process metrics (and optionally logs) into the `CWAgent` namespace, then alarm on those. This is essential because the hypervisor can't see guest-OS memory/disk usage.

**B3. What is Metric Math and how do you use it (e.g., latency p99, error rate %)?**
**Answer:** Metric Math lets you compute derived metrics from existing ones using expressions (`e1`, `m1`, `SUM`, `RATE`, `PERCENTILE`). E.g., error rate = `(errors / requests) * 100`, or p99 latency via `PERCENTILE(m1, 99)`. Useful for ratio-based alarms and dashboards without emitting new metrics.

**B4. How do you design a robust alarm strategy (thresholds, missing data, alarm actions, composite alarms)?**
**Answer:** Set thresholds with hysteresis (different high/low to avoid flapping), choose datapoints-to-alarm (e.g., 3 of 5), define `treatMissingData` (e.g., `breaching` for critical "no data = bad" cases), use **composite alarms** to combine conditions and reduce noise, and route through SNS → PagerDuty/Opsgenie with runbooks linked.

**B5. Explain CloudWatch Logs architecture: log groups, streams, retention, and subscription filters.**
**Answer:** Logs are organized into groups (retention per group) and streams (per source). **Subscription filters** deliver matching log events in real time to destinations (Kinesis, Lambda, OpenSearch, S3, or cross-account) — the mechanism for log-based alerting and centralizing logs.

**B6. How do you centralize logs and metrics across many accounts (observability at org scale)?**
**Answer:** Use **CloudWatch cross-account observability** (link accounts, view logs/metrics/alarms centrally), or forward logs via subscription filters/Kinesis Firehose to a central S3/OpenSearch, and send CloudTrail to a central account. Standardize namespaces, tagging, and dashboards via IaC; use CloudWatch cross-account dashboards for a unified view.

**B7. What is the difference between CloudWatch Events and EventBridge, and how do they drive automation?**
**Answer:** CloudWatch Events is the older name; **EventBridge** is its evolution (richer: schema registry, cross-account buses, SaaS partners). Both match event patterns and route to targets (Lambda, Step Functions, SNS, etc.). Use them for operational automation — e.g., an EC2 state-change event triggers a Lambda that tags/remediates.

**B8. How do you monitor Lambda with CloudWatch (metrics, logs, tracing)?**
**Answer:** Lambda emits Invocations, Errors, Duration, Throttles, IteratorAge (for streams), and custom metrics. Use structured JSON logs + **Logs Insights** for queries, **X-Ray** (via CloudWatch) for traces, and **embedded metric format (EMF)** to emit high-cardinality metrics from within functions. Alarms on Errors/Throttles/Duration.

**B9. What is the Embedded Metric Format (EMF) and why use it?**
**Answer:** EMF lets apps write metrics as structured log lines; CloudWatch automatically extracts them as metrics. Benefits: no extra API calls (lower cost/latency), high-cardinality dimensions supported, and metrics+logs captured together — ideal for Lambda/serverless.

**B10. How does CloudWatch Anomaly Detection work and when is it better than static thresholds?**
**Answer:** It applies ML to a metric's history to model a normal band, then alarms when values deviate (with configurable band width). Use it for metrics with seasonal/variable baselines (latency, custom app metrics) where static thresholds produce false alarms.

**B11. What are CloudWatch's cost drivers and how do you optimize?**
**Answer:** Costs come from custom metrics ($ per metric), detailed monitoring, log ingestion/storage, alarms, canaries, and dashboards. Optimize: use standard resolution, EMF instead of PutMetricData at scale, set log retention and filter noise (no debug in prod), use basic monitoring where 5-min is enough, and review dashboards/alarms for orphans.

**B12. How do you build an SLO/error-budget dashboard in CloudWatch?**
**Answer:** Use Metric Math to compute success rate and latency percentiles over a rolling window, compare against SLO targets, show error-budget burn rate with composite alarms (fast burn vs slow burn), and display via a dashboard. Pair with synthetic canaries for external availability and X-Ray for latency distribution.

---

## Case C — Scenario

**C1. Scenario:** Prod goes down at 2 AM; you get paged because an EC2 CPU alarm fired, but you have no idea what was running or why.
**Question:** What should have been in place, and how do you improve?
**Expected answer:** Before: alarms on memory/disk via CloudWatch Agent (CPU alone misses OOM), logs centralized with Insights, X-Ray traces, and a runbook with links. After the event: enable detailed monitoring + agent, create composite alarms + anomaly detection, add canaries for user-path checks, and build a dashboard so on-call can triage in minutes. Postmortem: find the root cause in logs/metrics and add a specific alarm.

**C2. Scenario:** A Lambda-based API returns intermittent 5xx, but the default Error alarm didn't fire.
**Question:** Diagnose why and build better observability.
**Expected answer:** The alarm may be on the wrong metric/statistic (e.g., average error count vs errors per invocation), or thresholds too coarse, or 5xx from an external dependency (not Lambda errors). Improve: alarm on `Errors` rate (Metric Math errors/invocations) and `Duration`/p99, enable X-Ray for downstream tracing, use structured logs + Insights to find the failing path, and add canaries.

**C3. Scenario:** You must alert when any instance in a fleet exceeds 90% memory for 10 minutes, and capture logs at that moment.
**Question:** Implement end-to-end.
**Expected answer:** Install the **CloudWatch Agent** (via SSM) to emit `mem_used_percent` to the CWAgent namespace and ship logs. Create an alarm on `mem_used_percent > 90` for 2 datapoints of 5 minutes, action = SNS topic (page the on-call). Use a **composite alarm** or EventBridge to also trigger a Lambda that grabs recent logs/`/var/log` snippets and posts them to the incident channel.

**C4. Scenario:** A customer reports slowness, but your CPU/memory/disk metrics all look normal.
**Question:** What else do you check in CloudWatch, and what metrics matter for "slow but healthy"?**
**Expected answer:** Check latency metrics (ALB TargetResponseTime, Latency), error rates, EBS VolumeQueueLength/BurstBalance, RDS DBLoad via Performance Insights (or CloudWatch), network throughput/packet drops, and queue depths (SQS AgeOfOldestMessage). Add X-Ray to find the slow service, and canaries to confirm end-user latency. "Healthy" system metrics often miss app-level and dependency bottlenecks.

**C5. Scenario:** Log storage costs are exploding; teams keep everything forever at DEBUG.
**Question:** Design a log governance strategy.
**Expected answer:** Set **retention policies** per log group (e.g., 30 days hot, then archive to S3 Glacier via subscription/Kinesis Firehose), enforce INFO+ in prod (no DEBUG), drop noisy sources, use Logs Insights for on-demand queries instead of exporting everything, standardize structured JSON (cheaper to parse, filterable), and set a budget alarm on log ingestion (CloudWatch + Cost Explorer).

**C6. Scenario:** You need a single dashboard showing CPU, latency, and error rate across three linked accounts, with alarms in one place.
**Question:** How do you build it with CloudWatch?
**Expected answer:** Use **CloudWatch cross-account observability**: designate a monitoring account, link the other accounts, then create a **cross-account dashboard** aggregating their metrics (and cross-account alarms). Set up IAM via CloudFormation StackSets to enable the links, and standardize tags/namespaces so metrics are consistent and queryable with SEARCH expressions.
