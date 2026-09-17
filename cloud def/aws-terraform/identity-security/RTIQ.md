# RTIQ — Terraform IAM on AWS (Real-Time Interview Questions)

> **Cloud:** AWS · **Tool:** Terraform · **Domain:** IAM roles, policies, federation, OIDC, least privilege · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~11 min

**How this file is used live:** DevSecOps and platform rounds spend the most time here, because IAM is Terraform's highest-leverage and highest-risk surface. Interviewers ask how you avoid wildcards, how pipelines get credentials, how you write policies without making them unmaintainable, and what you'd do if the pipeline role were compromised.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

**⚡ Rapid**
1. **Q:** Core IAM resources in Terraform?
**A.** `aws_iam_role` (with `assume_role_policy`), `aws_iam_policy` (JSON via `data "aws_iam_policy_document"`), `aws_iam_role_policy_attachment` (managed policies), `aws_iam_role_policy` (inline), `aws_iam_policy_document` for composing statements, `aws_iam_openid_connect_provider` for OIDC, plus `aws_iam_instance_profile` for EC2.
2. **Q:** Why use `data "aws_iam_policy_document"` instead of a heredoc JSON?
**A.** It's composable (statements can be built from variables/loops), validated by Terraform, and diff-friendly — and it can reference resource ARNs directly (so policies track the resources they describe). Heredocs break formatting/review and can't be composed safely.
3. **Q:** Managed policy vs inline policy in Terraform?
**A.** Managed (`aws_iam_policy` + attachment): reusable, versioned, visible in the console, auditable, capacity-limited per role (10 attachments). Inline (`aws_iam_role_policy`): fine for a role-unique, small statement but harder to audit and deleted with the role. Prefer managed customer-managed policies (AWS-managed ones are broad and can change under you).
4. **Q:** How do you avoid wildcards?
**A.** Enumerate actions, scope `Resource` to specific ARNs built from Terraform references, add conditions (`aws:RequestedRegion`, `aws:PrincipalOrgID`, `aws:SourceVpc`, tag-based `aws:ResourceTag/*`), and use IAM Access Analyzer's policy generation from CloudTrail activity to derive what's actually needed. Wildcards in `Resource` with `iam:PassRole` are the classic escalation path.
5. **Q:** How do you do GitHub Actions → AWS without keys?
**A.** `aws_iam_openid_connect_provider` for `token.actions.githubusercontent.com`, a role with a trust policy conditioned on the repo/branch/environment (`sub` claim), and `aws_iam_role` permissions scoped to what the pipeline deploys. Short-lived credentials, no static keys — the expected modern answer.
6. **Q:** How do EC2 instances get permissions?
**A.** `aws_iam_role` + `aws_iam_instance_profile` attached via the launch template, with a scoped policy. Apps on the instance should use the instance role (or better, per-pod/per-task roles in containers) — never long-lived keys in config.
7. **Q:** How do you grant a service permissions to call another service (e.g. Lambda → DynamoDB)?
**A.** A dedicated role per function with a policy scoped to the table ARN (`aws_dynamodb_table.x.arn` plus `/index/*` for GSIs) and specific actions (`Query`, `PutItem`) — not `dynamodb:*`, and not a shared "app" role.
8. **Q:** What is a permissions boundary and when do you use it?
**A.** `permissions_boundary` on a role/user caps the maximum permissions (intersection with identity policies) — used for self-service/IAM-creating roles so a team can create roles without exceeding the boundary. Great control for platform teams, and cheap to apply.
9. **Q:** How do you manage IAM users in Terraform (if at all)?
**A.** Generally you don't — use SSO/Identity Center and federation. Legacy service accounts should be migrated to roles. If a user must exist (break-glass), manage it in Terraform with MFA enforcement, no access keys, and alarms on usage.
10. **Q:** What's the difference between a trust policy and a permissions policy?
**A.** Trust policy (`assume_role_policy`) answers *who can assume this role*; the permissions policy answers *what the role can do*. Getting the trust policy wrong is how cross-account escalation happens (e.g. a wildcard principal or no external ID).

**🔍 Deep dive**
11. **Q:** Design IAM for a 40-team AWS organisation in Terraform.
**A.** Structure: per-account baseline roles (read-only for humans via SSO, pipeline roles per environment/repo, break-glass), per-service roles with scoped policies generated from Terraform references, SCPs for guardrails (regions, no root API, deny public S3/IAM user creation), permission boundaries for any role that can create IAM resources, and OIDC federation for all CI. Policy documents composed with `aws_iam_policy_document` (no raw JSON), every change reviewed in PR with `terraform plan` output, and Access Analyzer + CloudTrail last-accessed data feeding a quarterly pruning loop. Name roles by purpose and tag ownership.
**↳ Follow-up:** "How do you stop a team from giving themselves more permissions?"
**A.** Their pipeline role can't modify IAM outside a boundary (boundary + denied `iam:CreatePolicyVersion`/`AttachRolePolicy`/`PutRolePolicy` on privileged roles), SCPs prevent IAM user creation and disabling CloudTrail, and any IAM change is alerted (EventBridge on IAM mutations). Also: separate accounts mean escalation in one account doesn't reach production data.
12. **Q:** How do you make least privilege practical rather than aspirational?
**A.** Start from real usage: generate policies from CloudTrail with Access Analyzer, ship them behind a permissions boundary so nothing breaks, monitor, then remove unused actions after a soak period. Track a metric (e.g. % of roles with wildcard resources) and review quarterly with evidence — least privilege is a loop with telemetry, not a one-time document.
13. **Q:** How do you handle cross-account access in Terraform?
**A.** Target-account roles with trust policies naming the source account/role ARN (plus `sts:ExternalId` for third parties), the source role granted `sts:AssumeRole` on that specific ARN, and resources (KMS keys, buckets, SQS) with resource policies allowing the target principal. All four pieces must line up — build them as a module so they're consistent.
14. **Q:** How do you handle the Terraform pipeline's own role permissions?
**A.** Scope it per environment and state key: state bucket read/write (that key only), ability to manage the resource types in that root, and nothing else. Don't give the pipeline `AdministratorAccess` "because it's easier" — a compromised pipeline is then total account takeover. Also deny the pipeline `iam:*` on privileged roles, and keep the bootstrap (state bucket, CI roles) in a manually-applied, documented root.
15. **Q:** How do you structure IAM in the repo so it's reviewable?
**A.** A `iam` module (role + policy document inputs + attachments + boundary) and per-service IAM in the service's root, with policy documents near the resources they reference. Avoid a single monolithic `iam.tf` with 200 roles — reviewers can't reason about it, and the blast radius of a change is unclear.
16. **Q:** How do you test IAM changes?
**A.** `terraform plan` review of the policy JSON diff (visible in the PR), policy linting in CI (Parliament/checkov/OPA: no wildcards, no `iam:PassRole` unconstrained, no public assume-role policies), and integration tests in a sandbox account that assert an action succeeds/fails as expected. For critical roles, a dedicated "negative test" (the role must NOT be able to delete the table) is worth automating.
17. **Q:** How do you handle role chaining and its limits?
**A.** Role chaining (assuming a role from a role session) works but the session is limited (max 1 hour for chained sessions, versus up to 12 hours for the initial role) and CloudTrail attribution gets one level deeper. Prefer direct federation to the target role instead of chains two or three levels deep; document the chain when unavoidable because debugging access requires walking it.
18. **Q:** How do you manage IAM Access Analyzer and last-accessed data?
**A.** `aws_accessanalyzer_analyzer` (account or org level) for external-access findings, plus `aws_iam_access_analyzer_archive_rule` for accepted findings; for pruning, use IAM's last-accessed data (via CLI/Config, not directly in Terraform) as evidence in the review. Feed both into a quarterly access-review report — that's the audit artifact.

**🚨 War room**
19. **Q:** The pipeline role was compromised. What's your blast radius and response?
**A.** Blast radius = everything that role can do (hence scoping per root/environment): assess with CloudTrail what it did, disable the OIDC trust (or the role) immediately to stop further use, revoke sessions, rotate any secrets it could read (Secrets Manager/SSM), and check for persistence (new roles, new OIDC providers, added policy versions, new access keys, changed trust policies). Then fix the scoping and add alerts on IAM mutations from pipeline roles.
20. **Q:** An apply created a role with `Action: "*"` on `Resource: "*"`.
**A.** Remove it immediately (corrected apply), check whether the role was ever used/exploited (CloudTrail), then add CI policy checks that fail plans containing wildcard action+resource (except for documented, justified cases like specific read-only reporting roles). This shouldn't be catchable only by human review.
21. **Q:** A team's Terraform keeps changing an AWS-managed policy attachment and plans flip-flop.
**A.** Attaching/detaching AWS-managed policies that AWS updates can cause diff noise if the policy document is read into config; attach by ARN only (`aws_iam_role_policy_attachment` with a literal ARN) rather than comparing documents, or pin versions where supported. For stability, prefer customer-managed policies you control.
22. **Q:** `terraform destroy` on an IAM root would delete roles used by running services.
**A.** Mark critical roles with `prevent_destroy` (or at least the role resources that services depend on), and remove destroy capability for the pipeline role in production (`iam:DeleteRole` denied for roles tagged `critical`). Also separate IAM roots by lifecycle so an app teardown can't delete platform roles.
23. **Q:** Access Analyzer flags a bucket/role shared with an unknown account.
**A.** Identify the account (org unit? partner? an old test?), check whether access is actually used (CloudTrail/S3 access logs), and either remove the grant or constrain it with conditions (`aws:PrincipalOrgID`, external ID, prefix) and document it in the exception register. Then investigate how it was granted — usually an unmanaged console change that should be imported or reverted.
24. **Q:** The app is failing with AccessDenied after an IAM refactor.
**A.** Diff the effective permissions: the new policy may be missing a specific action that the old wildcard covered (e.g. `dynamodb:DescribeTable` alongside `Query`), a KMS grant, or a resource ARN mismatch (index ARNs `table/index/*` are a classic omission). Use CloudTrail's `AccessDenied` events + the simulator to find the exact action, then fix the policy narrowly — and add the case to your integration tests.
25. **Q:** A developer added an access key to a "temporary" Terraform-managed user for a script.
**A.** Rotate/delete the key, migrate the script to a role (or SSO short-lived credentials), and remove the user (avoid IAM users entirely). Then check whether that key was used from unexpected locations (CloudTrail) and add a guardrail (SCP denying `iam:CreateAccessKey` for non-break-glass principals) plus a Config rule/alarm on access key creation.

**⚖️ Trade-off**
26. **Q:** AWS-managed vs customer-managed policies?
**A.** AWS-managed are convenient (maintained, broad) but change under you and are usually too permissive for least privilege; customer-managed give exact scope, version control, and reviewability. Default to customer-managed for anything touching production data, and use AWS-managed only where the breadth is genuinely acceptable (e.g. `ReadOnlyAccess` for auditors, narrow service roles).
27. **Q:** One role per service vs one role per environment?
**A.** One role per service per environment. Shared roles create cross-service blast radius and make CloudTrail attribution impossible ("which service did this?"). The management overhead is solved with modules and `for_each`, not by sharing.
28. **Q:** Tag-based (ABAC) policies vs enumerated resource ARNs?
**A.** ABAC scales (new resources inherit access via tags, fewer policies) and suits multi-tenant/platform scenarios, but requires disciplined tagging and can be harder to audit; ARN enumeration is explicit and reviewable but grows with the estate. Many shops use ARNs for platform roles and ABAC for tenant/workload data access.
29. **Q:** Permissions boundaries vs SCPs?
**A.** Boundaries cap a single principal inside an account (good for self-service role creation); SCPs cap entire accounts/OUs (guardrails like no regions outside EU, no IAM users). They're complementary — boundaries for delegated administration, SCPs for organisational policy.
30. **Q:** Terraform-managed IAM vs manual (console/CLI) IAM?
**A.** Terraform for anything durable: reviewable, versioned, and consistent. Manual IAM should be break-glass only, followed by an import or revert. Unmanaged IAM is where auditors always find surprises — say that.
31. **Q:** Long-lived roles vs short session durations for humans?
**A.** Short sessions (8–12 h max, and shorter for privileged roles via Identity Center) force re-authentication and reduce the window of a stolen token; long-lived roles are convenient but weaken the control. Pair with MFA and PIM-style elevation for privileged access.

**🎯 Senior**
32. **Q:** What does your IAM standard in Terraform look like?
**A.** All roles/policies as code with `aws_iam_policy_document` (no raw JSON), least privilege with ARNs from references and conditions (region/org/tags), no wildcard action+resource in production roles (CI-enforced), permissions boundaries on any IAM-mutating role, OIDC federation for all pipelines (no static keys, no IAM users), one role per service per environment, `prevent_destroy` on platform roles, Access Analyzer + last-accessed data driving quarterly pruning with evidence, alerts on IAM mutations (new policies/trust changes/access keys), and a documented break-glass role excluded from normal pipelines.

**🎯 Senior signal:** "the pipeline role is the biggest credential — scope it per root and environment", the `iam:PassRole`/`CreatePolicyVersion` escalation paths, and the generate-from-CloudTrail least-privilege loop. Those three are DevSecOps-grade answers.
