# AWS Config — Interview Questions

> **Cloud:** AWS · **Category:** Monitoring & Governance · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

AWS Config stores **configuration items** and rule results as JSON (the S3 delivery and `get-resource-config-history` output are JSON).

```json
{
  "configurationItemVersion": "1.3",
  "resourceType": "AWS::EC2::SecurityGroup",
  "resourceId": "sg-0abc123",
  "configurationItemCaptureTime": "2026-09-13T10:00:00Z",
  "configurationState": "OK",
  "configuration": { "groupName": "web-sg" },
  "relationships": [],
  "tags": { "env": "prod" }
}
```

**Key fields:** `resourceType` / `resourceId` · `configuration` (the actual snapshot) · `relationships` (linked resources) · `configurationItemCaptureTime` (timeline). Config **rules** (custom Lambda) report via `PutEvaluations` JSON.


## Case A — Basic

**A1. What is AWS Config?**
**Answer:** A service that continuously records and evaluates the **configuration of your AWS resources** — what they look like now, how they changed over time, and whether they comply with your rules.

**A2. What problems does AWS Config solve?**
**Answer:** Configuration drift detection, compliance auditing, change tracking ("what changed on this security group and when?"), and security forensics — answering both "what is the current state?" and "what was the state at time X?"

**A3. What are the core components of AWS Config?**
**Answer:** **Configuration recorder** (captures changes), **delivery channel** (S3 + optional SNS), **Config items** (resource snapshots), **timeline** (change history), and **Config rules** (compliance checks).

**A4. What is a configuration item (CI)?**
**Answer:** A point-in-time snapshot of a resource's configuration, including its relationships to other resources — recorded whenever a resource is created, changed, or deleted.

**A5. What is a Config rule?**
**Answer:** A compliance check (AWS-managed like `s3-bucket-public-read-prohibited`, or custom Lambda-based) that evaluates resources against a desired state and reports COMPLIANT / NON_COMPLIANT.

**A6. What are the two evaluation trigger types for Config rules?**
**Answer:** **Configuration changes** (evaluated when a resource changes) and **periodic** (evaluated on a schedule, e.g., every 24 hours).

**A7. How is AWS Config different from CloudTrail?**
**Answer:** CloudTrail = **who did what API call** (activity). Config = **what is the resource state** and is it compliant (inventory + compliance). Config often uses CloudTrail-like change events internally but focuses on state, not just actions.

**A8. How is AWS Config different from CloudWatch?**
**Answer:** CloudWatch = performance metrics/alarms/logs. Config = resource configuration inventory and compliance. They're complementary: Config tells you state; CloudWatch tells you health/performance.

**A9. What is a Config "timeline"?**
**Answer:** The chronological view of all configuration changes for a resource — letting you pinpoint exactly when a change happened and what the configuration was before/after.

**A10. Can AWS Config work across multiple accounts and regions?**
**Answer:** Yes — via **Config Aggregator** (central account collects data from member accounts/regions) and **organization-wide** rules deployed via the delegated administrator.

**A11. What is a conformance pack?**
**Answer:** A collection of Config rules + remediations packaged as a template (YAML) that you deploy at scale — e.g., an "Operational Best Practices" or custom CIS pack across accounts.

**A12. What is the difference between AWS-managed and custom Config rules?**
**Answer:** AWS-managed = pre-built rules (e.g., `ec2-managedinstance-patch-compliance`). Custom = your own **Lambda function** implementing the evaluation logic for bespoke requirements.

**A13. What are Config's pricing components?**
**Answer:** Charged per **configuration item recorded** and per **rule evaluation** (and per conformance pack). Cost grows with the number of resources and rules — scope recording appropriately.

**A14. What is the configuration recorder's "recording scope"?**
**Answer:** You can record **all supported resource types** or restrict to specific types/regions — scoping controls cost and noise.

**A15. Where is Config data delivered?**
**Answer:** To an **S3 bucket** (config snapshots + history) and optionally an **SNS topic** for change notifications, plus the Config console for visualization.

---

## Case B — Advanced (Senior)

**B1. Explain how Config detects drift and builds a compliance view (recorder → items → rules → remediation).**
**Answer:** The recorder emits configuration items on every change (and periodically). Rules evaluate those items (triggered by change or schedule) against expected state, producing compliance results. **Remediations** (SSM Automation) can auto-fix non-compliant resources, and **remediation retries** handle transient issues. Together they form a closed loop: detect → assess → fix.

**B2. How does AWS Config achieve cross-account/region governance (aggregator + delegated admin)?**
**Answer:** Designate a **delegated administrator** account; enable Config in all accounts; create an **aggregator** in the admin account to pull compliance + inventory from member accounts/regions into one dashboard. Use **organization conformance packs** (via CloudFormation StackSets) to deploy identical rules everywhere.

**B3. What is the difference between a Config rule's evaluation modes, and how do you choose?**
**Answer:** **Detective** rules evaluate continuously and report compliance. **Proactive** rules run **before** provisioning (e.g., via CloudFormation hooks) to block non-compliant changes. Choose proactive for hard "never allow" policies and detective for monitoring existing resources.

**B4. How do you write a custom Config rule (Lambda) — evaluation flow, permissions, and best practices?**
**Answer:** The rule invokes a Lambda with an event (configuration change or scheduled). The Lambda fetches the resource configuration (via the event or `getResourceConfigHistory`), evaluates, and calls `PutEvaluations` with COMPLIANT/NON_COMPLIANT. Grant the Lambda the `AWSLambdaBasicExecutionRole` + `config:PutEvaluations`. Best practices: idempotent logic, handle deleted resources, map findings by resource, and test with the rule development kit (RDK).

**B5. How do Config rules and Security Hub / AWS Organizations fit together for compliance at scale?**
**Answer:** Config is the evaluation engine; **Security Hub** aggregates findings (including Config non-compliance) into a unified security score with standards (CIS, PCI, NIST). Organizations provides the multi-account structure; Config aggregators + org rules give centralized compliance. Use them together: Config rules detect, Security Hub reports/prioritizes.

**B6. Explain automatic remediation with SSM Automation documents and remediation retries.**
**Answer:** Attach a **remediation action** (an SSM Automation runbook, e.g., `AWSConfigRemediation-EnableS3BucketEncryption`) to a rule with parameters (e.g., the bucket name). When a resource is NON_COMPLIANT, Config executes the runbook. **Retries** handle failures (e.g., eventual-consistency), and you can scope remediation to specific resource IDs for safety.

**B7. How do you control Config costs at large scale (recording scope, rule scoping, CI costs)?**
**Answer:** (1) Scope the recorder to required resource types/regions (not "all supported"). (2) Use periodic rules instead of change-triggered where real-time isn't needed. (3) Limit rules to relevant resources (rule `scope` filters). (4) Use conformance packs (efficient bulk delivery). (5) Monitor CI/rule-evaluation counts via Cost Explorer and prune orphaned rules.

**B8. What is the Config timeline + query capabilities, and how do advanced queries help forensics?**
**Answer:** The timeline shows every CI version of a resource over time. **Advanced queries** (SQL over the Config database) answer questions like "show all SGs with 0.0.0.0/0 on port 22" or "resources changed in the last hour" across accounts — powerful for audits and incident scoping without custom tooling.

**B9. How do proactive rules work with CloudFormation hooks and Terraform?**
**Answer:** Proactive rules run during resource provisioning: CloudFormation uses a **hook** that calls the Config rule before CREATE/UPDATE; if NON_COMPLIANT, the deployment fails with a message. Terraform integrates via a similar hook mechanism. This shifts compliance left — blocking bad changes instead of detecting them after.

**B10. What are the limitations/gotchas of AWS Config?**
**Answer:** Not all resource types are supported (check the supported-types list), CIs have a finite retention (default 7 years, configurable), rule evaluation has latency (change-triggered is near-real-time but not instant), cost scales with coverage, and custom rules require Lambda maintenance. Also, Config records configuration, not *who* made the change (pair with CloudTrail).

**B11. How do you combine Config + CloudTrail for a complete change-intelligence picture?**
**Answer:** CloudTrail gives the **API call** (who/when/how); Config gives the **resulting state** (before/after configuration) and compliance. Correlate via timestamps/resource ARNs — e.g., CloudTrail shows `AuthorizeSecurityGroupIngress` by user X; Config's timeline shows the SG went from compliant → non-compliant. Together they answer the full "who changed what and is it still compliant" question.

**B12. How do you build a self-healing compliance pipeline (detect → remediate → verify → notify)?**
**Answer:** Config rule (detect) → SSM Automation remediation (fix) → the rule re-evaluates (verify COMPLIANT) → SNS/EventBridge notify + log in Security Hub (report). Add retry + escalation for persistent non-compliance, and exclude/allowlist resources intentionally non-compliant via rule scoping or tags (avoid remediation loops).

---

## Case C — Scenario

**C1. Scenario:** An auditor asks: "Prove no S3 bucket in the org is publicly readable, and show the change history of any that became public."
**Question:** How do you answer with AWS Config?
**Expected answer:** Deploy the `s3-bucket-public-read-prohibited` rule org-wide (conformance pack); show the aggregated compliance dashboard (0 non-compliant). For history: use the **timeline**/advanced queries to show every CI change for the flagged buckets (when `PublicAccessBlock`/policy changed) and correlate with CloudTrail for who made the change.

**C2. Scenario:** A security group on a production instance was silently changed to allow 0.0.0.0/0 on port 22, and no one knows when.
**Question:** How do you find what happened and auto-fix it?
**Expected answer:** Use Config's **timeline** for the SG to see exactly when the rule changed and the before/after state; correlate the timestamp with CloudTrail (`AuthorizeSecurityGroupIngress`) to find the actor. Auto-fix: attach the `restricted-ssh` rule with an **SSM remediation** that removes the offending ingress rule, and alert via SNS/Security Hub.

**C3. Scenario:** You must enforce "all EBS volumes encrypted" and "all RDS instances private" across 25 accounts, blocking new violations at deploy time.
**Question:** Design the governance.
**Expected answer:** Deploy **proactive rules** (`ec2-volume-encryption`-style custom rule, `rds-instance-public-access-check`) via organization conformance packs with CloudFormation **hooks** so non-compliant provisioning fails. Keep **detective** versions running to catch existing/imported resources, with remediation for encryption (enable encryption / re-create volume). Aggregate compliance in a delegated admin via Config aggregator.

**C4. Scenario:** Config costs tripled after a team enabled recording of "all supported resource types" in all regions plus 200 rules.
**Question:** Right-size the Config setup.
**Expected answer:** Scope the recorder to only the resource types/regions actually governed (exclude noisy types), convert unnecessary change-triggered rules to **periodic**, remove duplicate/overlapping rules (one rule can check many resources), consolidate into **conformance packs**, and use rule scoping (resource filters/tags) to skip irrelevant resources. Report savings via Cost Explorer CI/rule metrics.

**C5. Scenario:** During an incident, you need to know every AWS resource changed in the last 2 hours, across accounts, to scope the blast radius.
**Question:** How do you get this fast?
**Expected answer:** Use **Config advanced queries** (via the aggregator across accounts) with a query filtering resources by last-change timestamp, and/or the Config dashboard's "recently changed" view. Cross-reference with CloudTrail for the API calls in the same window to identify the actor and the sequence of changes.

**C6. Scenario:** A custom compliance requirement: "every EC2 instance must have a 'cost-center' tag, or it should be stopped."
**Question:** Implement detection + remediation.
**Expected answer:** Create a **custom Config rule** (Lambda) using the `required-tags` pattern (or the managed rule with `requiredTagKey`), triggered on configuration changes + periodic. Attach an **SSM Automation remediation** (e.g., stop the instance, or better: apply the tag via a lookup) — with proper scoping and an allowlist for exceptions. Alert owners via SNS and track compliance trend in Security Hub/dashboard.
