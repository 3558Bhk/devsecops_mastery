# AWS IAM Policies — Interview Questions

> **Cloud:** AWS · **Category:** Identity & Access Management · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

IAM policies are the canonical **JSON policy document** — the format every other AWS policy (bucket, endpoint, key) reuses.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowS3Read",
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
    "Condition": { "StringEquals": { "aws:PrincipalTag/team": "data" } }
  }]
}
```

**Key fields:** `Version` (2012-10-17) · `Statement[]` · `Sid` · `Effect` (Allow/Deny — **explicit Deny always wins**) · `Action`/`NotAction` · `Resource`/`NotResource` · `Condition` (operators like `StringEquals`, `IpAddress`, `ArnLike`).


## Case A — Basic

**A1. What is an IAM policy?**
**Answer:** A JSON document that defines permissions: which actions are allowed/denied on which resources under which conditions. Policies are attached to users, groups, and roles (identity-based) or to resources (resource-based).

**A2. What are the types of IAM policies?**
**Answer:** **Managed policies** (AWS-managed or customer-managed, standalone, reusable) and **inline policies** (embedded in a single principal, deleted with it). Plus resource-based policies (bucket policies, role trust policies) and session/permissions-boundary/SCP policies.

**A3. What are the core elements of a policy statement?**
**Answer:** `Effect` (Allow/Deny), `Action` (or NotAction), `Resource` (or NotResource), and optional `Condition`. A policy can contain multiple statements.

**A4. What is the difference between Allow and Deny?**
**Answer:** Allow grants permission; Deny explicitly forbids it. An explicit **Deny always overrides any Allow** — the most important IAM rule.

**A5. What is the difference between an identity-based and a resource-based policy?**
**Answer:** Identity-based = attached to a user/group/role (defines what the principal can do). Resource-based = attached to a resource (e.g., S3 bucket policy) defining who can access it. Both can grant cross-account access.

**A6. What is the implicit deny?**
**Answer:** By default, everything is denied unless explicitly allowed. A request is allowed only if an applicable policy explicitly allows it and nothing denies it.

**A7. What is an AWS-managed vs customer-managed policy?**
**Answer:** AWS-managed policies are created/maintained by AWS (e.g., `AdministratorAccess`, `ReadOnlyAccess`). Customer-managed policies are created by you for precise, reusable permissions you control and version.

**A8. What is a wildcard and why is it dangerous?**
**Answer:** `*` matches any action/resource (e.g., `"Action": "*"` grants everything). Overly broad wildcards (especially with `"Resource": "*"`) are a top security risk — always least privilege.

**A9. What is the difference between a user, group, and role?**
**Answer:** A **user** is a person/system with long-term credentials. A **group** is a collection of users sharing policies. A **role** is an identity with temporary credentials that a principal (user, service, or federated identity) can assume.

**A10. What is a role's trust policy?**
**Answer:** The resource-based policy on a role that defines **who can assume it** (the `sts:AssumeRole` permission and principal, e.g., `ec2.amazonaws.com` or another account ID).

**A11. How is an IAM policy evaluated?**
**Answer:** AWS aggregates all applicable policies (identity, resource, permissions boundary, SCP, session), checks for an explicit Deny (wins), then requires an Allow; otherwise implicit deny. The effective permission is the intersection.

**A12. What is ARN and its format?**
**Answer:** Amazon Resource Name — a unique identifier: `arn:partition:service:region:account:resource`. E.g., `arn:aws:s3:::my-bucket/*`.

**A13. What are condition keys used for?**
**Answer:** To make permissions conditional — e.g., `aws:SourceIp` (IP allowlist), `aws:RequestedRegion`, `s3:prefix`, `aws:MultiFactorAuthPresent`, `aws:PrincipalTag`. Conditions restrict when an Allow applies.

**A14. What is least privilege?**
**Answer:** Granting only the minimum permissions required for a task, reviewed regularly. Reduces blast radius of compromised credentials.

**A15. How do you check whether a policy allows a specific action?**
**Answer:** Use the **IAM Policy Simulator**, `Access Analyzer` policy validation/generation, or the `iam:SimulatePrincipalPolicy` API — without actually making the request.

---

## Case B — Advanced (Senior)

**B1. Walk through the full IAM evaluation logic (identity, resource, boundary, SCP, session).**
**Answer:** (1) **Explicit Deny** anywhere → deny. (2) **SCP** (org) sets the account's max — if not allowed there, deny. (3) **Permissions boundary** caps a principal. (4) **Session policies** (STS) further restrict. (5) For the request to be allowed, at least one applicable identity **or** resource policy must Allow, and all boundaries must not deny. Net effect = intersection of all layers.

**B2. What is a permissions boundary and when would you use it?**
**Answer:** A managed policy that sets the **maximum** permissions an identity can have — the effective permissions are the intersection of the identity policy and the boundary. Use it to delegate IAM administration safely (let a team create roles without granting themselves admin beyond the boundary).

**B3. How do SCPs differ from IAM policies?**
**Answer:** SCPs (Service Control Policies) apply to **accounts/OU** in AWS Organizations and cap what any principal in the account can do — they don't grant permissions themselves, they only restrict. IAM policies grant permissions to principals. SCP is an outer guardrail; IAM is the inner permission.

**B4. Explain how cross-account access works with roles vs resource-based policies.**
**Answer:** **Role-based**: Account A creates a role with a trust policy allowing Account B to assume it; Account B's principal calls `sts:AssumeRole` and uses the role's permissions. **Resource-based**: Account A attaches a policy directly to the resource (e.g., S3 bucket) granting Account B's principal access — no role assumption needed. For most services, role assumption is required; S3/SQS/KMS/SNS etc. support resource-based grants.

**B5. What is the difference between `aws:SourceIp` vs `aws:VpcSourceIp`, and `aws:SourceVpc`/`aws:SourceVpce` conditions?**
**Answer:** `aws:SourceIp` = the requester's public IP (as seen by AWS). `aws:VpcSourceIp` = the private IP within the VPC. `aws:SourceVpc` / `aws:SourceVpce` restrict access to requests originating from a specific VPC or VPC endpoint — powerful for "only from our network" controls.

**B6. How do you use IAM roles for EC2/Lambda instead of hardcoded credentials, and how does credential rotation work?**
**Answer:** Attach an **instance role** (EC2) or execution role (Lambda). AWS injects **temporary credentials** via the instance metadata service / Lambda environment, rotated automatically by STS (default 1-hour, configurable for roles). No long-term keys on the instance — this eliminates secret management and rotation burden.

**B7. What is the difference between `sts:AssumeRole` vs `sts:AssumeRoleWithWebIdentity` vs `sts:GetFederationToken`?**
**Answer:** AssumeRole = standard role assumption (AWS principals). AssumeRoleWithWebIdentity = for OIDC/IdP federation (e.g., Cognito, GitHub OIDC). GetFederationToken = issues temp creds for an IAM user with scoped policies. Choose based on who the caller is (AWS principal, web identity, or user needing scoped delegation).

**B8. How do you design a scalable IAM strategy across many accounts and teams (guardrails + delegation)?**
**Answer:** Use **AWS Organizations** with OUs and **SCPs** for hard guardrails (deny risky actions), **permission sets** via IAM Identity Center (SSO) for human access, **permissions boundaries** to delegate role creation to teams, **AWS-managed + customer-managed** policies for standard roles, and **Access Analyzer/Config** for continuous review. Centralize identity; decentralize least-privilege role creation.

**B9. What is IAM Access Analyzer and what does it do?**
**Answer:** It analyzes resource-based policies (S3, IAM roles, KMS, SQS, etc.) to find **external access** (access granted to principals outside your account) and can generate least-privilege policies based on CloudTrail activity. It's a core tool for finding unintended public/cross-account exposure.

**B10. How do policy conditions, tags (attribute-based access control), and variables work?**
**Answer:** Conditions evaluate request context (e.g., `aws:PrincipalTag/team == aws:ResourceTag/team`) enabling **ABAC** — one policy serving many principals via matching tags instead of per-user policies. Policy variables like `${aws:username}` personalize policies (e.g., each user can only access their own S3 prefix).

**B11. What are the dangers of `NotAction` and `NotResource`, and when are they useful?**
**Answer:** They invert the match (everything except the listed actions/resources) and are easy to get wrong, accidentally granting broad access. Use sparingly — e.g., "Allow everything except IAM delete" is risky; prefer explicit allow-lists. Deny + NotAction is also dangerous (denies almost everything).

**B12. How do you audit IAM at scale?**
**Answer:** **IAM Access Analyzer** (external access + unused access findings), **CloudTrail** (who did what), **AWS Config** (policy/role compliance), **Security Hub + IAM Access Analyzer policies**, credential reports, last-used timestamps to prune unused users/roles/keys, and periodic privilege reviews (remove `*`, rotate keys, enforce MFA).

---

## Case C — Scenario

**C1. Scenario:** A developer accidentally has `"Action": "*", "Resource": "*"` in an attached policy, and security flags it.
**Question:** How do you remediate with least privilege?
**Expected answer:** Analyze actual usage via **CloudTrail** + **IAM Access Analyzer policy generation** to see which actions/resources are actually used. Replace the wildcard policy with a generated least-privilege policy, add MFA, move the user to SSO/permission sets, and set up Config/Security Hub rules to alert on future `*` policies.

**C2. Scenario:** Account A needs to read from Account B's S3 bucket without sharing long-term credentials.
**Question:** Design both possible approaches and pick the best.
**Expected answer:** (1) **Resource-based**: Account B adds a bucket policy granting Account A's **role ARN** `s3:GetObject`/`ListBucket`; Account A's role gets a matching IAM policy. (2) **Role assumption**: Account B creates a cross-account role trusting Account A; Account A's role assumes it. Choose (1) for simple S3 access (no assume-role hop); choose (2) for broader service access. Ensure KMS key policy shared if SSE-KMS is used.

**C3. Scenario:** A third-party vendor needs limited, temporary access to a single DynamoDB table in your account.
**Question:** Design the secure access mechanism.
**Expected answer:** Create a **role** with an inline/managed policy limited to that table (e.g., `dynamodb:GetItem`/`Query` on the table ARN), a trust policy allowing only the vendor's **account ID + external ID** (to prevent the confused-deputy problem), and let them assume it for STS temporary credentials. Add conditions (time/IP) if needed; revoke by editing the trust policy.

**C4. Scenario:** A developer can attach any policy to their role and has escalated themselves to admin within a team's sandbox account.
**Question:** How do you prevent this while still letting the team self-serve IAM?
**Expected answer:** Attach a **permissions boundary** to the developer role (and require it via SCP) that caps their maximum permissions (e.g., no IAM admin, no `*`). Combine with an SCP denying `iam:CreatePolicyVersion`/`AttachUserPolicy` beyond limits and IAM policies that allow role creation but only with the boundary. This is the canonical delegated-administration pattern.

**C5. Scenario:** A policy allows `s3:GetObject` on a bucket, but a user can't download a file encrypted with SSE-KMS.
**Question:** Why, and how do you fix it?
**Expected answer:** S3 permission alone isn't enough — the user also needs **KMS permissions** (`kms:Decrypt` on the key) because the object is encrypted with a KMS key. Fix: add `kms:Decrypt` (and `kms:GenerateDataKey` for writes) to the user's policy **and** grant them in the **KMS key policy**. Both the S3 and KMS layers must allow.

**C6. Scenario:** You must allow a role to use a KMS key only when requests come from a specific VPC endpoint.
**Question:** Write the condition and explain.
**Expected answer:** In the key policy (or IAM policy), add: `"Condition": { "StringEquals": { "aws:SourceVpce": "vpce-0abc123..." } }`. This restricts `kms:Decrypt` (or the encrypt/decrypt actions) to requests arriving through that interface endpoint, preventing usage of the key from outside the trusted network path. (Also restrict the endpoint policy side for defense in depth.)
