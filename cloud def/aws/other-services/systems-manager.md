# AWS Systems Manager (SSM) — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Operations / Management · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

SSM **documents** (Run Command, Automation, State Manager) are JSON (or YAML) files that define actions and parameters.

```json
{
  "schemaVersion": "0.3",
  "description": "Restart an unhealthy instance",
  "parameters": { "InstanceId": { "type": "String" } },
  "mainSteps": [{
    "name": "restart",
    "action": "aws:changeInstanceState",
    "inputs": { "InstanceIds": ["{{ InstanceId }}"], "DesiredState": "running" }
  }]
}
```

**Key fields:** `schemaVersion` (0.3) · `parameters` (typed, e.g. String/StringList/AWS::EC2::Instance::Id) · `mainSteps[]` with `action` (aws:runCommand, aws:invokeLambda, aws:approve…) + `inputs`. Parameter Store values also support JSON strings.


## Case A — Basic

**A1. What is AWS Systems Manager (SSM)?**
**Answer:** An operations hub for managing AWS (and on-prem) resources: patching, running commands, managing parameters/secrets, inventory, and automation — without SSH/RDP or bastion hosts.

**A2. What are the main SSM capabilities?**
**Answer:** **Run Command** (execute scripts remotely), **Session Manager** (secure shell without SSH), **Patch Manager** (OS patching), **Parameter Store** (config/secrets), **Inventory** (software/OS inventory), **State Manager** (enforce desired state), **Automation** (runbooks), **Documents** (SSM documents/scripts).

**A3. What is the SSM Agent?**
**Answer:** The software installed on instances that communicates with the SSM service to execute commands and report state. It's pre-installed on Amazon Linux and many AMIs.

**A4. What does an instance need to be "managed" by SSM?**
**Answer:** The SSM Agent installed, an **IAM instance profile** with the `AmazonSSMManagedInstanceCore` policy, and (for private subnets) connectivity to SSM via **VPC endpoints** or NAT.

**A5. What is Session Manager and why is it better than SSH?**
**Answer:** A secure, browser/CLI-based shell to instances **without opening port 22**, without a bastion, and without SSH keys — with full audit (CloudTrail + session logs).

**A6. What is Parameter Store?**
**Answer:** A hierarchical, encrypted store for configuration and secrets (String/StringList/SecureString), with versioning — used to inject config without hardcoding.

**A7. What is a SecureString parameter?**
**Answer:** A parameter encrypted with **KMS**, used for secrets (passwords, API keys) with optional KMS-key selection.

**A8. What is a Systems Manager document?**
**Answer:** A JSON/YAML definition of an action (run a script, apply a patch, run an automation) — the building block for Run Command, Automation, and State Manager.

**A9. What is Patch Manager?**
**Answer:** Automates OS/software patching using **patch baselines** (approved patches + schedule), with compliance reporting per instance.

**A10. What is State Manager?**
**Answer:** Ensures a defined state (e.g., "this agent installed, this config applied") by running associations on a schedule and re-applying on drift.

**A11. What is Automation?**
**Answer:** Runbooks (`AWS-*` or custom) that execute multi-step operational tasks — e.g., restart instances, create AMIs, remediate Config findings — with parameters, branching, and approvals.

**A12. What is Inventory?**
**Answer:** Collects software/OS/config metadata from instances (e.g., installed applications, AWS components) for querying and compliance.

**A13. How does SSM work with on-premises servers?**
**Answer:** Register on-prem servers as **managed instances** (install the agent + activation code/ID) to run commands/patch them like EC2.

**A14. What are maintenance windows?**
**Answer:** Scheduled windows for running patching/administrative tasks on instances — avoiding changes outside approved times.

**A15. What is the difference between SSM and CloudWatch?**
**Answer:** SSM = **operations/action** (run commands, patch, manage state). CloudWatch = **observability** (metrics, logs, alarms). They complement: SSM acts; CloudWatch watches.

---

## Case B — Advanced (Senior)

**B1. Explain how SSM Agent securely communicates, and why VPC endpoints matter.**
**Answer:** The agent polls the SSM service over HTTPS using **instance-profile credentials** (temporary, rotated). For private subnets without internet, create **VPC endpoints** for `ssm`, `ssmmessages`, and `ec2messages` (plus S3 for patching) so traffic stays private. This enables fully private, audited operations at scale.

**B2. How does Session Manager secure sessions (no SSH), and how do you enable logging/audit?**
**Answer:** Session Manager brokers the connection through the SSM service (port 443) — no inbound SSH port, no bastion, no keys. Auth via IAM. Enable **session logs** to S3/CloudWatch and **session encryption with a KMS key**; record every session in CloudTrail. Use IAM conditions to restrict who can start sessions on which instances.

**B3. How do you use Parameter Store for hierarchical config and secrets at scale (paths, policies, encryption)?**
**Answer:** Organize parameters as paths (e.g., `/prod/app/db-url`), apply **parameter policies** (expiration/notification), use `SecureString` with a KMS key for secrets, and grant least-privilege IAM by path prefix (`ssm:GetParametersByPath`). Combine with **AppConfig** for dynamic, validated config rollout.

**B4. What is the difference between Parameter Store (SecureString) and Secrets Manager?**
**Answer:** Parameter Store = free (standard), hierarchical, good for config + secrets, no built-in rotation. Secrets Manager = per-secret cost, **automatic rotation**, cross-account resource policies, replication. Use SSM for config/simple secrets; Secrets Manager for rotating DB/API credentials.

**B5. How does Patch Manager work (baselines, compliance, and the patching flow)?**
**Answer:** Define a **patch baseline** (approved/rejected patches, auto-approval rules, product/family). Instances report compliance against the baseline; **maintenance windows** schedule patching (Run Command `AWS-RunPatchBaseline`). SSM shows per-instance patch compliance; integrate with Config/Security Hub for reporting.

**B6. What is the role of SSM in EC2 Image Builder and golden-image pipelines?**
**Answer:** SSM documents/automation drive build steps and post-build config; the SSM **agent** must be present in the AMI (required for later management). SSM Automation is also used to **distribute and run** actions across fleets (e.g., apply config, remediate) — commonly orchestrated from Config remediations or EventBridge.

**B7. How do you automate operational runbooks with SSM Automation (parameters, approvals, output)?**
**Answer:** Automation documents define steps (aws:runCommand, aws:invokeLambda, aws:approve, aws:branch), take **parameters**, support **approval steps** for human gating, and return outputs for chaining. Trigger via EventBridge (alarms), Config remediation, or console — e.g., "restart unhealthy instance" or "create AMI before change."

**B8. How do you manage state drift with State Manager (associations)?**
**Answer:** An **association** binds a document + schedule + targets (e.g., "run `AWS-RunPatchBaseline` every Sunday on tag=prod"). State Manager re-applies on schedule, and you can set `apply-only-at-cron-interval` vs. always. It detects/remediates drift from the desired configuration — the declarative configuration manager.

**B9. What is AppConfig and how does it enable safe dynamic configuration?**
**Answer:** AppConfig (part of SSM) deploys **configuration** with **validators** (syntactic/semantic checks), **deployment strategies** (linear/canary with bake time + rollback), and environment separation — so apps get validated, gradual config changes instead of risky flag flips.

**B10. How do you use SSM at org scale (Fleet Manager, resource data sync, OpsCenter)?**
**Answer:** **Fleet Manager** gives a unified UI for managed nodes. **Resource Data Sync** aggregates inventory into S3 for org-wide querying (Athena). **OpsCenter** aggregates operational issues (OpsItems) from events/alarms. Combined with **Explorer** and Change Calendar, you get enterprise-scale operational governance.

**B11. How do you secure SSM end-to-end (IAM, endpoints, encryption, audit)?**
**Answer:** Least-privilege IAM (`AmazonSSMManagedInstanceCore` for agents; scoped `ssm:SendCommand`/`ssm:StartSession` for operators with resource/tag conditions), **VPC endpoints** for private connectivity, **KMS** for session logs/parameters, **CloudTrail** for API audit, session logging to S3/CloudWatch, and SCPs to restrict risky actions.

**B12. What are common SSM troubleshooting scenarios (agent not online, command not executing)?**
**Answer:** Check (1) the **SSM Agent** is installed/running and up-to-date, (2) the instance **IAM role** has the right policy, (3) **connectivity** to SSM (endpoints/NAT for private subnets), (4) instance appears in Fleet Manager (managed), (5) the command targets match (tags/instance IDs), and (6) SSM agent logs/CloudTrail. Agent heartbeats + `ping status` are the first signals.

---

## Case C — Scenario

**C1. Scenario:** The security team wants to eliminate SSH bastions and port 22 while still giving devs shell access, with full audit.
**Question:** Implement it.
**Answer:** Use **Session Manager**: grant devs IAM permission `ssm:StartSession` (scoped to their instances), keep port 22 closed (no SSH keys, no bastion), and enable **session logging to S3/CloudWatch + KMS encryption** with CloudTrail audit. For private instances, add the SSM **VPC endpoints**. Optionally restrict sessions to specific users/hours via IAM conditions.

**C2. Scenario:** Hundreds of instances need monthly OS patching with zero changes outside a maintenance window, plus a compliance report.
**Question:** Design the patching solution.
**Answer:** Create a **patch baseline** (auto-approve security patches), define a **maintenance window** (e.g., first Sunday 2–4 AM) targeting instances by tag, run `AWS-RunPatchBaseline` via the window, and use **Patch Manager compliance** reports + Config/Security Hub for audit. Exclude critical instances or use staggered windows for HA.

**C3. Scenario:** An app reads a DB password from a hardcoded config file across 50 instances; the password must change and be updated everywhere.
**Question:** Refactor with SSM Parameter Store.
**Answer:** Store the password as a **SecureString parameter** (KMS-encrypted) at e.g. `/prod/app/db-password`. Update the app to fetch it at startup (via SDK with the instance's IAM role, or inject via user data/`ssm:GetParameter`), and grant the instance role `ssm:GetParameter` for that path. Changing the parameter + a rolling restart (or app refresh) updates all 50 instances — no file edits.

**C4. Scenario:** A Config rule found an S3 bucket non-compliant, and you must fix it automatically and be notified.
**Question:** Wire up SSM automation remediation.
**Answer:** Attach an **SSM Automation** runbook (e.g., `AWSConfigRemediation-EnableS3BucketEncryption` or custom) to the Config rule as its **remediation action**, configure parameters (bucket name), enable **remediation retries**, and route completion/failure notifications via SNS. Config executes the automation on non-compliance and re-evaluates.

**C5. Scenario:** You need to run a one-off diagnostic script on 200 instances (tagged `env=prod`) and collect results, without SSH.
**Question:** How?
**Answer:** Use **Run Command** with a custom SSM document (or `AWS-RunShellScript`), target the `env=prod` tag, set output to S3/CloudWatch, and monitor per-instance status (Success/Failed) in the console. Use concurrency/error thresholds to control blast radius and review CloudTrail for the action.

**C6. Scenario:** Instances in a private subnet aren't showing up in Fleet Manager / can't run commands.
**Question:** Diagnose.
**Answer:** Likely missing **connectivity** or **IAM**. Check: (1) instance role has `AmazonSSMManagedInstanceCore`, (2) SSM Agent installed/running, (3) **VPC endpoints** for `ssm`, `ec2messages`, `ssmmessages` exist and route correctly (or NAT gateway for private subnets), (4) the endpoints' security groups allow 443 from the instances, and (5) the agent's logs for errors. Then verify the instance appears as managed.
