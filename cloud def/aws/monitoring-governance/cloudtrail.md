# AWS CloudTrail — Interview Questions

> **Cloud:** AWS · **Category:** Monitoring & Governance · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

CloudTrail **events** are JSON records (the raw log files in S3 and the EventBridge payload are both JSON).

```json
{
  "eventVersion": "1.08",
  "eventTime": "2026-09-13T10:30:00Z",
  "eventSource": "ec2.amazonaws.com",
  "eventName": "RunInstances",
  "userIdentity": { "type": "AssumedRole", "arn": "arn:aws:sts::111122223333:assumed-role/admin/jdoe" },
  "sourceIPAddress": "203.0.113.10",
  "requestParameters": { "instanceType": "t3.micro" },
  "responseElements": { "instancesSet": { "items": [{ "instanceId": "i-0abc123" }] } }
}
```

**Key fields:** `eventName` + `eventSource` (what happened) · `userIdentity` (who — includes assumed-role chains) · `sourceIPAddress` / `userAgent` · `requestParameters` / `responseElements` · `errorCode` (failures). Management vs **data events** (S3/Lambda/DynamoDB) are both JSON.


## Case A — Basic

**A1. What is AWS CloudTrail?**
**Answer:** A service that records **API activity** in your AWS account — who did what, when, from where — as events for auditing, security analysis, and compliance. It's the "audit log" of your account.

**A2. What are the three main event types?**
**Answer:** **Management events** (control-plane: creating EC2, IAM changes), **Data events** (data-plane: S3 object reads/writes, Lambda invocations, DynamoDB item access), and **Insights events** (anomalous API activity).

**A3. Where can CloudTrail deliver events?**
**Answer:** To an **S3 bucket** (the default for trails) and optionally to **CloudWatch Logs** and **EventBridge** for real-time alerting/automation.

**A4. What is a "trail" and what is a multi-region trail?**
**Answer:** A trail is a configuration that captures and delivers events. A **multi-region trail** records events from **all regions** into one S3 bucket — the recommended setup for complete coverage.

**A5. What is the difference between CloudTrail and CloudWatch?**
**Answer:** CloudTrail = **audit** (API calls, who did what). CloudWatch = **operational monitoring** (metrics/logs/alarms). CloudTrail events can feed CloudWatch Logs/alarms.

**A6. Is CloudTrail enabled by default?**
**Answer:** Yes — the account has an always-on **Event history** (90 days of management events viewable in the console), but a **trail** (persisted to S3) must be created for longer retention and data events.

**A7. What is the default retention of CloudTrail Event history?**
**Answer:** **90 days** in the console. For longer retention, create a trail to S3 (with lifecycle to Glacier for archiving).

**A8. What are Data events and why are they off by default?**
**Answer:** Data events capture resource-level activity (S3 GetObject, Lambda Invoke, DynamoDB reads) — they're high-volume and incur extra cost, so they're **disabled by default** and enabled per-resource when needed.

**A9. What information does a CloudTrail event contain?**
**Answer:** Event time, user/role identity (and ARN), source IP, user agent, region, requested action/service, resources affected, request parameters, response elements, and error codes.

**A10. What is CloudTrail's role in security forensics?**
**Answer:** It answers "who deleted this bucket?" or "who changed this security group?" by providing an immutable, timestamped record of the API calls that caused changes.

**A11. What is a CloudTrail Insights event?**
**Answer:** ML-detected **unusual API activity** (e.g., a spike in `CreateInstance` or unusual IAM calls) — helps spot potential compromise or misconfiguration.

**A12. How does CloudTrail help compliance (e.g., HIPAA/SOC2)?**
**Answer:** It provides the audit trail required by frameworks: complete API activity logs, retained immutably, with integrity validation — evidence for auditors.

**A13. What is an organization trail?**
**Answer:** A trail created in the **management account** that captures events for **all accounts** in AWS Organizations — centralized auditing.

**A14. Can CloudTrail logs be tampered with?**
**Answer:** CloudTrail offers **log file integrity validation** (SHA-256 hashes + digital signatures) to detect modification or deletion of delivered log files.

**A15. How do you query CloudTrail logs in S3?**
**Answer:** Use **Athena** (SQL over the JSON/Parquet logs in S3), or send logs to CloudWatch Logs and use Logs Insights, or use Amazon S3 Select/OpenSearch.

---

## Case B — Advanced (Senior)

**B1. Explain the difference between management events, data events, and Insights events, with examples and cost implications.**
**Answer:** Management = control-plane API calls (RunInstances, CreateBucket, IAM changes) — free for the first copy, low volume. Data = data-plane (S3 object ops, Lambda invoke, DynamoDB) — high volume, charged per 100k events. Insights = ML anomaly detection on management events (extra cost). Design: always capture management events org-wide; enable data events only on sensitive resources (prod S3 buckets).

**B2. How do you build a centralized, multi-account audit architecture with CloudTrail?**
**Answer:** Create an **organization trail** in the management account (or delegate to an audit account via CloudTrail delegation) capturing all accounts/regions into a central S3 bucket with SSE-KMS + bucket policy, S3 Object Lock for immutability, lifecycle to Glacier, and CloudWatch Logs/EventBridge routing for near-real-time alerting. Restrict write access to the bucket to CloudTrail only.

**B3. How do you use CloudTrail with EventBridge for real-time security automation?**
**Answer:** Configure the trail to send events to **EventBridge**, then create rules matching risky patterns (e.g., `DeleteBucket`, `StopLogging`, `CreateUser`, `AuthorizeSecurityGroupIngress` with 0.0.0.0/0) and route to targets: Lambda (auto-remediate), SNS (alert), or Step Functions (runbook). This turns audit logs into an active detection/response pipeline.

**B4. How do you secure the CloudTrail trail itself (defense against tampering)?**
**Answer:** Enable **log file validation**, store in a bucket with restrictive policy (only CloudTrail can write), SSE-KMS encryption with restricted key policy, **S3 Object Lock** (governance/compliance mode) for immutability, MFA Delete on the bucket, separate audit account ownership, and alarm on `StopLogging`/`DeleteTrail`/`UpdateTrail` events.

**B5. What is the difference between CloudTrail, AWS Config, and GuardDuty?**
**Answer:** CloudTrail = **who did what API call** (activity log). AWS Config = **what is the current/past configuration** and is it compliant (resource state). GuardDuty = **threat detection** (finds malicious/anomalous behavior using VPC flow logs, DNS, CloudTrail). They complement: Config for compliance drift, CloudTrail for audit, GuardDuty for attacks.

**B6. How do you query CloudTrail at scale with Athena, and what are the schema/partitioning best practices?**
**Answer:** Create an Athena table over the trail's S3 prefix (partitioned by region/year/month/day via partition projection). Query for specific users, actions, error codes, or IPs (e.g., `SELECT * FROM cloudtrail WHERE useridentity.arn LIKE '%admin%' AND eventname='DeleteBucket'`). Use Parquet conversion (via Glue) for cost/speed at very large scale.

**B7. Explain CloudTrail log file integrity validation — how does it work?**
**Answer:** For each log file, CloudTrail computes a SHA-256 hash and delivers a signed digest file (hourly). You can validate that delivered files match the digest and that the digest chain is unbroken (using the public key), proving no file was modified or deleted after delivery.

**B8. What are the typical use cases for enabling Data events, and how do you control their cost?**
**Answer:** Enable on prod S3 buckets (track object access/exfiltration), DynamoDB tables (sensitive data), and Lambda (function invocation tracing). Control cost by scoping to specific resources (not all), using advanced event selectors (e.g., only Put/Delete), and filtering noise. Monitor via Cost Explorer + trail configuration review.

**B9. How does CloudTrail handle cross-account / assumed-role attribution in a shared model?**
**Answer:** When a principal assumes a role, CloudTrail logs both the **role session** (role ARN + `principalId` of the original caller) and the original identity in `userIdentity` fields — enabling you to trace actions back through role chains to the actual user, crucial in multi-account investigations.

**B10. How do you detect "CloudTrail was disabled" or other anti-forensics activities?**
**Answer:** Create alarms/rules on **StopLogging, DeleteTrail, UpdateTrail, PutEventSelectors** (reducing coverage), and `console sign-in` failures. Because the actor must call these via API, CloudTrail records the attempt — alert immediately and auto-re-enable via a Lambda remediation. Use a separate account (or org trail) so the attacker can't suppress the audit trail from within the same account.

**B11. What are CloudTrail's limits you should design around?**
**Answer:** Event size limits (trail captures up to 256 KB per event), data-event cost at scale, one trail per region unless multi-region, delivery latency (typically ~15 min to S3, near-real-time to EventBridge), and the need for Athena/Glue for efficient querying. Design for immutability + near-real-time routing for detection rather than S3-only.

**B12. How do you produce compliance reports (e.g., who has admin, unused keys) from CloudTrail?**
**Answer:** Combine CloudTrail (activity) with IAM credential reports and Access Analyzer: e.g., find `CreateAccessKey`/`LoginProfile` events, correlate with last-used timestamps to flag inactive admin users, and generate periodic reports via Athena queries + QuickSight. Automate with Config rules and Security Hub for continuous compliance.

---

## Case C — Scenario

**C1. Scenario:** A production S3 bucket was deleted at 3 PM yesterday. Management wants to know exactly who, when, and from where.
**Question:** Walk through your investigation.
**Expected answer:** Query CloudTrail (Athena or console) for `eventName = DeleteBucket` (and prior `DeleteObject`s) on that bucket: extract `userIdentity.arn`, `sourceIPAddress`, `userAgent`, `eventTime`. Cross-check whether it was a role (trace the original principal), and review surrounding events for other actions by the same principal. Corroborate with S3 server access logs if data events were enabled.

**C2. Scenario:** A security alert fires: an IAM user made unusual API calls from a foreign IP.
**Question:** What CloudTrail features help, and how do you respond?
**Expected answer:** **CloudTrail Insights** flags unusual activity (API anomaly). Investigate the user's events (Athena query by IP/userAgent), check `sourceIPAddress`/geolocation, review created keys/roles (persistence), disable the user/rotate keys, revoke sessions, and check for lateral movement (other calls). Long-term: add EventBridge rules for impossible-travel/foreign-IP patterns and enable GuardDuty.

**C3. Scenario:** Compliance (SOC 2) requires immutable, encrypted API logs retained 7 years for all accounts.
**Question:** Design the CloudTrail setup.
**Expected answer:** **Organization trail** (all accounts, all regions) → central audit-account S3 bucket with **SSE-KMS**, **log file integrity validation**, **S3 Object Lock (compliance mode)** for immutability, **MFA Delete**, lifecycle rule → Glacier Deep Archive after 90 days (7-year total retention), and a restrictive bucket policy. Optionally replicate to a second region. Document + test access for auditors.

**C4. Scenario:** You suspect data exfiltration from an S3 bucket but have no object-level logs.
**Question:** Why can't you see it, and how do you enable visibility going forward?
**Expected answer:** **Data events are off by default**, so object-level GetObject/PutObject weren't logged — only bucket management events were. Going forward: enable **S3 data events** for the bucket (via advanced event selector, optionally only Put/Delete to limit cost), route to CloudWatch Logs/EventBridge for alerting on large/anomalous reads, and correlate with S3 server access logs, VPC Flow Logs, and GuardDuty S3 protection.

**C5. Scenario:** An attacker disabled CloudTrail to hide their actions, but you still need to know what happened.
**Question:** How do you (a) detect this and (b) recover visibility?
**Expected answer:** Detect: alert on **StopLogging/DeleteTrail** events via EventBridge → SNS/Lambda, and use GuardDuty (which can flag CloudTrail disabling). Recover: re-enable the trail immediately via automation; since the disable call itself was logged, examine events **before** the stop. Use an **organization trail in a separate account** so a single-account compromise can't disable the audit source — this is the key architectural defense.

**C6. Scenario:** A quarterly audit asks: "Show every action taken by third-party vendor roles in the last quarter, including in which account."
**Question:** How do you produce this report efficiently?
**Expected answer:** Use the **organization trail** data in the central S3 bucket + **Athena** (partitioned by account/region/date) to query: `WHERE useridentity.arn LIKE '%vendor-role%' AND eventtime BETWEEN ...`. Export results to CSV/QuickSight for the auditors. For ongoing control, add an EventBridge rule on the vendor role's assumed sessions to alert on out-of-policy actions.
