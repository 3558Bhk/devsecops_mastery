# Terraform Monitoring & Alerts (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is CloudWatch in Terraform?**
**Answer:** AWS's monitoring service, managed via resources like `aws_cloudwatch_metric_alarm`, `aws_cloudwatch_log_group`, and `aws_cloudwatch_dashboard`.

**A2. What is an `aws_cloudwatch_metric_alarm`?**
**Answer:** An alarm that evaluates a metric against a threshold and triggers actions (SNS, EC2, ASG) when breached.

**A3. How do you declare a CPU alarm for an EC2 instance?**
**Answer:** `metric_name = "CPUUtilization"`, `namespace = "AWS/EC2"`, `dimensions = { InstanceId = ... }`, `comparison_operator = "GreaterThanThreshold"`, `threshold = 80`, `evaluation_periods = 2`, and `alarm_actions = [sns.arn]`.

**A4. What is a composite alarm?**
**Answer:** `aws_cloudwatch_composite_alarm` combines multiple alarms with a rule (e.g. "alarm only if both A and B are ALARM") to reduce noise.

**A5. What is `aws_cloudwatch_log_group` and retention?**
**Answer:** A log group storing logs; set `retention_in_days` to control cost/compliance (e.g. 30 days).

**A6. How do you ship EC2 logs to CloudWatch?**
**Answer:** Install the CloudWatch agent (via SSM/user data) and configure it to push logs/metrics to the log group.

**A7. What is `aws_cloudwatch_dashboard`?**
**Answer:** A JSON-defined dashboard of widgets (graphs, alarms) rendered in the console.

**A8. What is an SNS topic's role in alerts?**
**Answer:** Alarms publish to an SNS topic, which fans out to email/Slack/Lambda/PagerDuty via subscriptions.

**A9. What is CloudTrail in Terraform?**
**Answer:** `aws_cloudtrail` records API activity in your account, delivered to S3/CloudWatch Logs — the audit log.

**A10. How do you enable a multi-region trail?**
**Answer:** `is_multi_region_trail = true` on `aws_cloudtrail`, with a destination S3 bucket and optional log group.

**A11. What is `aws_cloudwatch_log_metric_filter`?**
**Answer:** Turns log patterns into metrics (e.g. count "ERROR" lines), which alarms can then watch.

**A12. What is `aws_cloudwatch_event_rule` for health/state events?**
**Answer:** Rules that match AWS state changes (e.g. EC2 instance state-change) and route them to targets.

**A13. What is `aws_sns_topic_subscription` with protocol `email`?**
**Answer:** Sends alarm notifications to an email address (requires manual confirmation).

**A14. What is the `period` and `evaluation_periods` on an alarm?**
**Answer:** `period` is the metric granularity (seconds); `evaluation_periods` is how many consecutive periods must breach before ALARM state.

**A15. What is `treat_missing_data`?**
**Answer:** How the alarm treats gaps in data (e.g. `notBreaching`, `breaching`, `missing`) — important for flapping avoidance.

## Case B — Advanced / Senior

**B1. How do you build a monitoring module that every service reuses?**
**Answer:** A module taking inputs (service name, thresholds, SNS topic, log group) that emits standard alarms (CPU, 5xx, latency, error rate, DLQ depth) and a dashboard — instantiated per service for consistency.

**B2. What is the difference between standard, high-resolution, and anomaly detection alarms?**
**Answer:** Standard = 60s granularity; high-res = 10/30s (`period` under 60); anomaly detection (`aws_cloudwatch_metric_alarm` with `metrics` + `anomaly_detection_configuration`) learns baselines and alarms on deviation.

**B3. How do you alarm on log patterns (e.g. too many 500s)?**
**Answer:** `aws_cloudwatch_log_metric_filter` with a pattern, then an alarm on that custom metric — e.g. `[timestamp, level=ERROR, ...]` counting matches per minute.

**B4. How do you use metric math in alarms?**
**Answer:** In the alarm's `metrics` block, define expressions like `m1/m2*100` to compute error rate from two metrics instead of alarming on raw counts.

**B5. How do you wire alerts into Slack/PagerDuty with Terraform?**
**Answer:** SNS topic → `aws_sns_topic_subscription` for HTTPS (Slack webhook via Lambda) or a PagerDuty integration/Lambda that maps SNS → PagerDuty API. Keep the mapping in the monitoring module.

**B6. What is the purpose of a "page vs warn" alerting strategy?**
**Answer:** Separate severity: pages (composite/urgent, immediate) vs warnings (email/ticket, next business day). Encode both in the module so services only pick severity, not plumbing.

**B7. How do you avoid alarm flapping and alert fatigue?**
**Answer:** Use `evaluation_periods` > 1, `datapoints_to_alarm` (M of N), `treat_missing_data` policy, and dedupe via SNS → Slack with throttling. Prefer SLO-based thresholds over static ones.

**B8. How do you configure CloudTrail to feed detection pipelines?**
**Answer:** Trail to CloudWatch Logs + `aws_cloudwatch_log_metric_filter`/subscription filters, or trail to S3 + EventBridge/Athena for queries. Terraform manages the trail, bucket, and IAM roles.

**B9. How do you monitor Terraform itself (drift) with CloudWatch?**
**Answer:** Nightly CI runs `terraform plan -detailed-exitcode`; on exit 2, publish a custom metric (or EventBridge event) that alarms — so infrastructure drift is caught like any other incident.

**B10. What is `aws_cloudwatch_metric_stream`?**
**Answer:** Streams CloudWatch metrics to a third-party destination (e.g. Datadog, Splunk, or Firehose→S3) in near real-time.

**B11. How do you set up a "healthcheck" endpoint alarm for an ALB?**
**Answer:** Alarm on `AWS/ApplicationELB` metrics like `TargetResponseTime`, `HTTPCode_Target_5XX_Count`, or `HealthyHostCount < 1` per target group, routed to the ops topic.

**B12. How do you handle monitoring resources living in a separate "observability" account?**
**Answer:** Use CloudWatch cross-account observability (or metric streams/EventBridge) to centralize metrics/alarms in one account, with Terraform using aliased providers per account.

## Case C — Scenario

**C1. Your app returned 500s for 10 minutes but nobody got paged.**
**Answer:** The alarm on 5xx didn't exist or wasn't wired to the right SNS topic. Add the 5xx/custom metric alarm, verify the subscription, and test it end-to-end. Then add a synthetic canary (`aws_synthetics_canary`) as a user-facing check.

**C2. A noisy alarm wakes engineers every night during a known batch job.**
**Answer:** Suppress during the batch window (alarm `actions_enabled` toggled, or a composite alarm with a schedule gate), or raise `evaluation_periods`/use anomaly detection so only real deviations page.

**C3. You need to know if any of 50 services' error rates spike, with one page.**
**Answer:** Per-service metric filters feeding one composite alarm (or a single metric-math expression summing error rates), so a threshold on the aggregate pages once instead of 50 individual alarms.

**C4. A compliance audit requires 1 year of API activity and 90 days of logs.**
**Answer:** CloudTrail to S3 with lifecycle/retention for 1 year (and optionally logs to CloudWatch with 90-day retention); set log group `retention_in_days = 90` and encrypt the buckets.

**C5. A DB is about to run out of storage; you want proactive warning.**
**Answer:** Alarm on `FreeStorageSpace` (RDS) below a threshold with `datapoints_to_alarm` to avoid flapping, routed to the ops topic, plus storage autoscaling (`max_allocated_storage`) as the automatic mitigation.

**C6. Monitoring config is drifting because teams edit alarms in the console.**
**Answer:** Move all alarms/dashboards into the Terraform monitoring module, adopt console changes with `-refresh-only` or import, restrict console edit permissions, and enforce "changes only via code" in the runbook.
