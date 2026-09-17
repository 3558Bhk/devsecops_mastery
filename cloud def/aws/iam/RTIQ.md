# RTIQ — AWS IAM (Real-Time Interview Questions)

> **Cloud:** AWS · **Domain:** IAM (Policies, Inline Policies, Permissions Boundaries) · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~10 min

**How this file is used live:** IAM questions are the fastest way for an interviewer to separate "has used AWS" from "has been accountable for AWS". They will ask you to read a policy out loud, explain why an access is denied, and then hand you an audit finding. DevSecOps rounds go straight to "least privilege at scale" and "how do you prove it".

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. IAM Policies — `iam-policies.md`

**⚡ Rapid**
1. **Q:** What is the default decision in IAM?
**A.** Implicit deny. Nothing is allowed unless something grants it. Evaluation order: explicit deny > SCP > permissions boundary > identity policy / resource policy > session policy. If nothing allows it, it's denied.
2. **Q:** Identity-based vs resource-based policy?
**A.** Identity-based attaches to a user/role/group (what can *this principal* do). Resource-based attaches to a resource (who can touch *this S3 bucket / KMS key / SQS queue*) and can grant cross-account access directly — the trust-policy direction people forget.
3. **Q:** What's the difference between a role and a user?
**A.** Roles are assumed and issue temporary credentials (STS) with no long-lived secrets; users have permanent credentials. For anything in 2026, roles only — users exist for break-glass/legacy.
4. **Q:** What does `"Action": "s3:*"` do to your security review?
**A.** Fails it. Wildcard actions plus `Resource: "*"` is the archetypal over-privilege finding; replace with enumerated actions and ARNs, and use Access Analyzer to prove it.

**🔍 Deep dive**
5. **Q:** How do you actually build a least-privilege policy for a new service?
**A.** Start from the task, enumerate the exact API calls from docs/logs, scope resources by ARN, add condition keys (`aws:SourceVpc`, `aws:PrincipalTag/team`, `aws:RequestedRegion`), deploy, then use CloudTrail + IAM Access Analyzer's policy generation and `last-accessed` data to prune. Least privilege is a loop, not a one-time document.
**↳ Follow-up:** "How do you scope permissions you can't enumerate up front?"
**A.** Permissions boundary with a maximum-allowed set + a broader working policy inside it. The boundary caps blast radius while the team iterates.
6. **Q:** Explain `AssumeRole` with MFA and where the trust policy lives.
**A.** The trust policy is a resource-based policy on the role itself (`sts:AssumeRole` principal), and the caller also needs `sts:AssumeRole` in their identity policy. MFA enforcement goes in the trust policy via `aws:MultiFactorAuthPresent` — both halves are required or it silently fails.
7. **Q:** Service control policies vs permissions boundaries — where do you use each?
**A.** SCPs cap what's possible in an entire account/OU (guardrails like "no region outside eu-*", "no IAM user creation"). Boundaries cap a single principal inside an account. SCP for organisational blast radius, boundary for team/app scoping.
8. **Q:** What are the condition keys you use most, and what do they buy you?
**A.** `aws:SourceVpce` (only via a VPC endpoint), `aws:SourceIp`, `aws:PrincipalOrgID` (only your org), `aws:ResourceTag/*` and `aws:PrincipalTag/*` (tag-based ABAC), `aws:RequestedRegion`. They convert static policies into context-aware and scalable ones — ABAC means new resources inherit access via tags instead of new policies.
9. **Q:** `NotAction` with an `Allow` — what's the risk?
**A.** It allows *everything* except the listed actions, including future actions and services you didn't consider. Read it as a deny-list that will be wrong within a year. Prefer an explicit allow-list.
10. **Q:** A user has an identity policy allowing `s3:GetObject` and a bucket policy denying it. What happens?
**A.** Denied. Explicit deny wins over any allow. This is also how you implement "deny access to unencrypted uploads" (`s3:PutObject` with `s3:x-amz-server-side-encryption` condition) in a bucket policy.

**🚨 War room**
11. **Q:** A developer says "AccessDenied" and you can't see why. Debug it in 5 minutes.
**A.** Use the IAM Policy Simulator / `aws sts get-caller-identity` to confirm the *actual* principal (assumed role vs user — this is often the answer), then check in order: SCPs on the account/OU, permissions boundary, identity policy, resource policy, KMS key policy, VPC endpoint policy, session policy (if SSO/permission set), and finally the service's own resource-level support (not all actions support resource ARNs).
12. **Q:** CloudTrail shows the role did something it shouldn't be able to do. What happened?
**A.** Likely a confused-deputy problem or an overly broad trust policy — check if the role is assumable by an external account or by a service principal (`ec2.amazonaws.com`) without an `sts:ExternalId` condition. Also check for a role-chaining path: role A can assume role B, which has the permissions.
13. **Q:** A leaked long-lived access key was found in a public repo. Walk me through your first hour.
**A.** Deactivate the key immediately (don't delete yet — you need it for forensics), confirm via CloudTrail what it did and from where, rotate any downstream secrets it could read, revoke sessions, notify security/legal per policy, then kill the root cause: move the workload to OIDC roles and add secret scanning + push protection to the pipeline.
14. **Q:** An S3 bucket with sensitive data starts returning 403s to a legitimate service. Nothing "changed". Where do you look?
**A.** KMS key policy vs bucket policy vs service role. Common causes: a key rotation/policy change removing the service principal, `aws:SourceVpce`/`SourceIp` condition now failing because traffic moved egress paths, S3 Block Public Access being enabled, or the service switching to a new role without the KMS grant.

**⚖️ Trade-off**
15. **Q:** Many small roles vs few shared roles?
**A.** One role per workload, per environment. Shared roles create cross-team blast radius and make CloudTrail useless for attribution. The management overhead is solved with IaC templates and tagging, not by sharing.
16. **Q:** ABAC (tags) vs RBAC (roles) at scale?
**A.** ABAC scales sub-linearly — new resources are governed by tags and policies don't multiply. But it demands disciplined tagging and can be hard to audit. Many orgs run RBAC for platform/infra and ABAC for multi-tenant data access.
17. **Q:** Block Public Access at bucket vs organisational level?
**A.** Both. Account/org-level S3 Block Public Access makes it structurally impossible; bucket-level is defence in depth and needed for exceptions you deliberately approve. Org-level plus SCP is what auditors want to see.

**🎯 Senior**
18. **Q:** How do you run an access review for 200 roles without it being theatre?
**A.** Automate evidence: IAM credential report, `GetRolePolicy`/last-accessed, Access Analyzer findings, and unused-permission reports into the ticket; owners must justify each elevated action; anything unused for 90 days is proposed for removal via PR. Time-box it quarterly and track "privilege removed" as the KPI.

**🎯 Senior signal:** saying "evaluation order" and "explicit deny wins" unprompted, and treating IAM as a continuous loop with evidence, is exactly the L5/SRE-platform bar.

---

## 2. Inline Policies & Advanced Permission Patterns — `inline-policies.md`

**⚡ Rapid**
1. **Q:** Managed vs inline policy — which do you use?
**A.** Managed (customer-managed) almost always: reusable, versioned, auditable, and countable in a review. Inline policies are 1:1 with one principal, hard to audit, and can't be attached elsewhere — use only for a genuinely unique, single-principal trust edge.
2. **Q:** AWS-managed vs customer-managed?
**A.** AWS-managed (e.g. `ReadOnlyAccess`) is convenient but broad and changes under you. Customer-managed gives exact scope and versioning; that's what a senior fleet should ship.
3. **Q:** How many policies per role and how do you stay under the limits?
**A.** Attach up to 10 managed policies (and size limits per policy); the discipline is composition — small reusable building blocks and permission sets rather than one giant policy per service.
4. **Q:** What happens to an inline policy when you delete the role?
**A.** It's deleted with it — so it disappears from your audit trail. Another reason to avoid inline in production.

**🔍 Deep dive**
5. **Q:** Describe a real least-privilege rollout you did, with numbers.
**A.** Example shape: inventory 300 roles, 40% had `*:*`-style policies → generate narrowed policies from CloudTrail, ship behind a permissions boundary so nothing breaks, run for 30 days in monitor mode, remove unused grants, then enforce. Result: N% reduction in granted-but-unused actions and zero sev-2s.
6. **Q:** How do you implement break-glass admin access?
**A.** A dedicated `BreakGlass` role with broad permissions, protected by MFA, a distinct IAM identity or federated user, alarm on any assume (CloudWatch/EventBridge → PagerDuty + Slack), and mandatory review of the session's CloudTrail activity. It must be loud and rare.
7. **Q:** How do you give a CI/CD pipeline AWS access without static keys?
**A.** GitHub Actions OIDC or GitLab OIDC → `sts:AssumeRoleWithWebIdentity`, with the trust policy scoped by `sub` claim (`repo:org/repo:ref:refs/heads/main`) and environment. ECS/EKS use task roles and IRSA/IRSA-equivalent. No long-lived keys anywhere.
**↳ Follow-up:** "Why scope by `sub` and not just repo?"
**A.** So a pull-request workflow from a fork or a feature branch can't assume the production role — the condition pins branch/environment, which is where the real trust boundary lives.
8. **Q:** What's wrong with this policy? *(interviewer pastes a policy with `Resource: "*"`, `Action: "iam:PassRole"`, and no conditions)*
**A.** `iam:PassRole` + wildcard resource + no `iam:PassedToService` condition is a privilege-escalation path: the principal can create a Lambda/EC2 resource with a *more privileged* role attached and execute as it. Always constrain `PassRole` with `Resource` = specific role ARNs and a `iam:PassedToService` condition.
9. **Q:** What are the other classic escalation paths to know?
**A.** `iam:CreatePolicyVersion` (silently replace policies), `iam:AttachUserPolicy`/`PutUserPolicy` (grant yourself admin), `sts:AssumeRole` on a role that can do more, `iam:UpdateAssumeRolePolicy`, `lambda:CreateFunction` + `PassRole`, `ec2:RunInstances` + `PassRole`, and `sso:CreatePermissionSet`-style federation abuse. Know them — interviewers love "how would you escalate from this policy?"

**🚨 War room**
10. **Q:** Your CI role suddenly needs `s3:PutObject` on a new bucket. Fastest safe answer?
**A.** Add the ARN to the existing scoped policy via PR (IaC), not a wildcard "just to unblock". If you're under time pressure, use a temporary, time-boxed inline policy with an expiry note and a ticket — but never `s3:*`.
11. **Q:** A terminated employee's credentials still work. What do you check and fix?
**A.** Federation/SSO group membership (the usual miss — IAM user deleted but SSO assignment remained), IAM users/groups they were in, any access keys, and any roles with a trust policy referencing them. Fix by making SSO the only path, automating deprovisioning from the HR system, and alerting on any activity by deprovisioned principals.
12. **Q:** Access Analyzer flags an S3 bucket shared with an unknown account. Response?
**A.** Identify the account (internal org unit? third party?), check CloudTrail/access logs for actual cross-account reads, and if it's not required, remove the grant immediately. If it is required, add conditions (`aws:PrincipalOrgID`, `s3:prefix`) and document the exception.

**⚖️ Trade-off**
13. **Q:** Broad role that makes incidents fixable fast, or narrow roles that make incidents slower?
**A.** Narrow by default plus a monitored break-glass path. You keep the speed of a broad role exactly when you need it, with an audit trail — the worst option is a permanently broad role nobody notices is being used.
14. **Q:** Permission boundaries always on, or only for risky teams?
**A.** Modern practice: boundaries on anything that can create/modify IAM or compute (platform, CI, Lambda invoker roles). They cost a little velocity and buy a very large safety net.
15. **Q:** Policy as code with Terraform/CFN — how do you prevent a bad policy PR?
**A.** CI checks: policy linting (e.g. cfn_nag/checkov/Parliament), diff-based review requiring a security approver on IAM paths, `terraform plan` output posted to the PR, and an auto-rollback if an apply triggers elevated-privilege alarms.

**🎯 Senior**
16. **Q:** How would you detect privilege escalation attempts in real time?
**A.** EventBridge rules over CloudTrail management events for the escalation API list (`AttachUserPolicy`, `CreatePolicyVersion`, `UpdateAssumeRolePolicy`, `PutRolePolicy`, `CreateAccessKey`, first-time `AssumeRole` to admin roles), routed to Security Hub/GuardDuty and an alert channel. Baseline normal behaviour so you're alerting on anomalies, not noise.

**🎯 Senior signal:** the `iam:PassRole` escalation path is the single best discriminator in this topic. Knowing it, plus OIDC-over-keys, plus break-glass discipline, reads as DevSecOps-credible.
