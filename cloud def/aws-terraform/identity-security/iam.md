# Terraform IAM (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What are the main IAM resources in Terraform?**
**Answer:** `aws_iam_user`, `aws_iam_group`, `aws_iam_role`, `aws_iam_policy`, `aws_iam_role_policy_attachment`, `aws_iam_instance_profile`, and inline policies.

**A2. What is an IAM role and its trust policy?**
**Answer:** `aws_iam_role` with an `assume_role_policy` defining who can assume it (e.g. an EC2 service or another account). The role then holds permission policies.

**A3. What is the difference between a managed policy and an inline policy?**
**Answer:** Managed policies are standalone, reusable, and versionable; inline policies are embedded in a single role/user and can't be reused. Prefer managed (or customer-managed) policies.

**A4. How do you attach a managed policy to a role?**
**Answer:** `aws_iam_role_policy_attachment` linking the role to a policy ARN (AWS-managed like `arn:aws:iam::aws:policy/AdministratorAccess` or custom).

**A5. What is `aws_iam_policy`?**
**Answer:** A customer-managed policy resource with a `policy` JSON document defining permissions.

**A6. What is `data "aws_iam_policy_document"`?**
**Answer:** A way to build IAM policy JSON in HCL with `statement` blocks, converted with `json = data.aws_iam_policy_document.x.json`.

**A7. What is an instance profile?**
**Answer:** `aws_iam_instance_profile` wraps a role so EC2 instances (and other services) can assume it — `iam_instance_profile` on an instance references it.

**A8. What is an IAM user and access key?**
**Answer:** `aws_iam_user` (a person/system identity) and `aws_iam_access_key` (long-lived credentials). Prefer roles/OIDC over users and keys.

**A9. What is an IAM group and membership?**
**Answer:** `aws_iam_group` plus `aws_iam_group_membership` (or `aws_iam_user_group_membership`) to attach policies to many users at once.

**A10. What is `aws_iam_role_policy` (inline)?**
**Answer:** An inline policy attached directly to a role — use sparingly when a policy is truly role-specific.

**A11. What does a typical EC2 role trust policy look like?**
**Answer:** A statement with `Action = "sts:AssumeRole"`, `Effect = "Allow"`, and `Principal = { Service = "ec2.amazonaws.com" }`.

**A12. What is `aws_iam_account_password_policy`?**
**Answer:** Enforces password complexity/rotation for IAM users at the account level.

**A13. How do you create a user's login profile?**
**Answer:** `aws_iam_user_login_profile` (console password), with `password_reset_required`.

**A14. What is `aws_iam_server_certificate`?**
**Answer:** Uploads an SSL/TLS certificate for legacy services (ELB/CloudFront) that don't use ACM.

**A15. What is `aws_iam_policy_attachment` and why is it discouraged?**
**Answer:** It attaches a policy to many principals in one go, but can detach policies other code attached (exclusive control). Prefer per-principal `role_policy_attachment`.

## Case B — Advanced / Senior

**B1. How do you write least-privilege policies in Terraform?**
**Answer:** Start with empty allow, add only needed actions/resources via `aws_iam_policy_document`, use conditions (tags, VPC, MFA), test with IAM Access Analyzer/Policy Simulator, and iterate via CI linting (checkov/tfsec).

**B2. What is `aws_iam_policy_document` vs raw JSON strings?**
**Answer:** The data source gives structured HCL, validation, and interpolation (e.g. referencing ARNs), reducing syntax errors versus pasting JSON. Raw JSON is fine for exotic statements.

**B3. Explain IAM conditions and give a Terraform example.**
**Answer:** Conditions restrict when a statement applies, e.g. `condition { test = "StringEquals" ; variable = "aws:SourceVpce" ; values = ["vpce-123"] }` to limit S3 access to a VPC endpoint.

**B4. How do you grant cross-account access with Terraform?**
**Answer:** In account A, create a role whose trust policy allows account B's principal; in account B, a role/user assumes it. Terraform uses `assume_role` providers or `aws_iam_role` + `aws_iam_role_policy_attachment`.

**B5. What is the risk of `aws_iam_policy_attachment` and what should you use instead?**
**Answer:** It takes exclusive control and can detach attachments it didn't create. Use `aws_iam_role_policy_attachment` (or `_user_`/`_group_`) so each principal's attachments are independent.

**B6. How do you manage IAM for Lambda vs EC2 vs EKS differently?**
**Answer:** Lambda: execution role (trust `lambda.amazonaws.com`). EC2: instance profile role (trust `ec2.amazonaws.com`). EKS: node role + IRSA roles (OIDC trust) per service account.

**B7. What is OIDC federation for CI and how do you set it up?**
**Answer:** Create an OIDC provider (`aws_iam_openid_connect_provider`) for GitHub Actions, then a role whose trust policy allows `sts:AssumeRoleWithWebIdentity` from the repo/branch — removing long-lived keys from CI.

**B8. How do you structure IAM code across environments?**
**Answer:** Keep baseline IAM (roles/policies) in a separate "security" stack/module shared across accounts, and environment-specific roles in each env's config. Centralize policy docs as reusable modules.

**B9. What is an IAM policy size limit and how does Terraform help?**
**Answer:** Policies have character/size limits (6,144 chars managed; inline ~10,240). If policies bloat, split into multiple managed policies or use conditions to consolidate.

**B10. How do you avoid breaking permissions during a Terraform IAM refactor?**
**Answer:** Add the new role/policy first, attach, verify services work, then remove the old one. Never delete and recreate a role an instance is currently using — swap instance profiles carefully.

**B11. What is the `iam` module pattern for per-team roles?**
**Answer:** A module parameterized by team (name, allowed actions, resources, conditions) generating role + policy + attachments, instantiated via `for_each` over teams — consistent, auditable roles.

**B12. How do you audit IAM drift and permissions with Terraform?**
**Answer:** `terraform plan` detects config drift; combine with IAM Access Analyzer (unused access/external access findings) and CloudTrail for actual API usage to right-size policies over time.

## Case C — Scenario

**C1. An audit flags a role with `AdministratorAccess` attached. What do you do?**
**Answer:** Identify what the role actually uses (Access Analyzer/CloudTrail), write a scoped policy with only those actions/resources, attach it, verify, then remove the admin policy. Add a CI rule blocking wildcard `*:*` in new policies.

**C2. CI uses long-lived access keys that keep leaking. How do you fix it?**
**Answer:** Move to OIDC federation: create the OIDC provider + role, update the pipeline to assume the role, deactivate and delete the access keys, and enforce no-new-keys via SCP/IAM policy.

**C3. A service in account B needs to read a bucket in account A.**
**Answer:** In A, create a role with an S3 read policy and a trust policy allowing account B's role/user to assume it; in B, the service assumes that role (provider `assume_role` or `sts:AssumeRole`). Ensure the bucket policy/KMS key also allow the role.

**C4. Terraform plan wants to detach a policy that another team attached manually.**
**Answer:** Because you used `aws_iam_policy_attachment` (exclusive). Switch to `aws_iam_role_policy_attachment` per role so each principal manages its own attachments without stepping on others.

**C5. You need to give a contractor temporary, minimal access.**
**Answer:** Create a dedicated IAM user/role with least-privilege policies + an expiration (or better, federate via SSO/OIDC with time-bound sessions). Use conditions like `aws:RequestedRegion`/IP and set password/keys to rotate.

**C6. An EC2 app suddenly lost permissions after a Terraform change.**
**Answer:** Roll back/stop at the IAM change, check the instance profile attachment (a role rename/recreate breaks it), and restore the prior role. Verify with the Policy Simulator before reapplying, and prefer attaching new policies over recreating roles.
