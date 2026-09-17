# AWS Inline Policies — Interview Questions

> **Cloud:** AWS · **Category:** Identity & Access Management · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

An inline policy uses the **same JSON document structure** as a managed policy, but it is embedded in exactly one principal (via `put-user-policy` / `put-role-policy` / `put-group-policy`) and deleted with it.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": ["arn:aws:s3:::my-bucket/*"]
  }]
}
```

**Key fields:** identical to a managed policy (`Version`, `Statement`, `Effect`, `Action`, `Resource`, `Condition`). Differences are **behavioural, not structural**: no versioning, no reuse, and it counts toward the principal's total policy-size quota.


## Case A — Basic

**A1. What is an inline policy?**
**Answer:** A policy that is **embedded directly in a single IAM identity** (user, group, or role) or resource — it exists as part of that entity rather than as a standalone object.

**A2. How is an inline policy different from a managed policy?**
**Answer:** An inline policy is embedded in exactly one principal and is **deleted when the principal is deleted**. A managed policy is a standalone object that can be attached to many principals and versioned.

**A3. When is an inline policy deleted?**
**Answer:** When the user, group, or role it's embedded in is deleted — inline policies do not survive the principal. (On a resource like a bucket policy, it's removed when you edit the resource policy.)

**A4. Can an inline policy be attached to multiple users?**
**Answer:** No. It's bound to one principal. To share the same permissions, copy it or (better) use a **managed policy**.

**A5. Can a user have both inline and managed policies?**
**Answer:** Yes — a principal's effective permissions are the union of all its inline and attached managed policies (subject to denies, boundaries, and SCPs).

**A6. Where do you see/edit inline policies?**
**Answer:** On the IAM console under the user/group/role's **Permissions → Add inline policy**, or via CLI `put-user-policy` / `put-role-policy`, or in CloudFormation/JSON.

**A7. Are inline policies versioned?**
**Answer:** No. Inline policies have **no versioning** or history — edits overwrite the previous version. Managed policies keep up to 5 versions.

**A8. What is a typical use case for an inline policy?**
**Answer:** A permission that applies to **only one** principal and should never be reused — e.g., a one-off grant to a specific role, or a tightly-scoped exception you don't want available for attachment elsewhere.

**A9. What is the size/quota consideration for inline policies?**
**Answer:** Inline policies count toward the principal's total policy size (a principal's inline + managed policies are limited in total characters). Too many large inline policies can hit IAM quotas.

**A10. How does an inline policy's JSON differ from a managed policy's?**
**Answer:** The JSON structure is identical (Effect/Action/Resource/Condition). The only difference is **where it's stored** — embedded vs. standalone.

**A11. Can a group have an inline policy?**
**Answer:** Yes — you can embed an inline policy in a group; it applies to all group members.

**A12. What is a role trust policy — is it inline or managed?**
**Answer:** A trust policy is a special **resource-based** policy on the role (always embedded on the role itself, i.e., inline in nature) that controls who can assume the role.

**A13. How do inline and managed policies combine for a single user?**
**Answer:** They are evaluated together: an explicit Deny in either overrides any Allow, and the user gets the union of all Allow statements (within boundaries/SCPs).

**A14. Why might a security reviewer prefer managed policies over inline?**
**Answer:** Managed policies are reusable, versionable, centrally auditable, and easier to review at scale. Inline policies are scattered, harder to inventory, and easy to lose track of.

**A15. Can an inline policy be attached to an S3 bucket?**
**Answer:** Buckets use **resource-based (bucket) policies**, which are embedded on the resource — conceptually "inline" to the bucket, though IAM typically calls them resource policies. The term "inline policy" usually refers to identity-embedded policies.

---

## Case B — Advanced (Senior)

**B1. Explain the tradeoffs: when is an inline policy actually the right choice?**
**Answer:** Choose inline when a permission must **live and die with one principal** — e.g., a unique exception on a single role, a tightly-scoped grant that must not be accidentally reused, or when you need to guarantee the policy can't outlive the principal. Otherwise, prefer customer-managed policies for reuse, versioning, and auditability.

**B2. How do inline policies interact with permissions boundaries and SCPs?**
**Answer:** They compose identically to managed policies: inline Allow + managed Allow = union; any explicit Deny (inline or managed) wins; the **permissions boundary** and **SCP** then cap the result. An inline policy cannot grant more than the boundary/SCP allows.

**B3. Why does AWS warn against using inline policies at scale, and how do you refactor them?**
**Answer:** They fragment permissions across principals, make audits slow (no central list of "what grants this"), can't be versioned/rolled back, and multiply review effort. Refactor: inventory inline policies, group identical ones into **customer-managed policies**, attach them, and delete the inline copies — keeping only true one-offs inline.

**B4. How does the principal's total policy size quota affect heavy inline-policy use?**
**Answer:** A principal's combined policy (inline + attached) has a total character limit (default 2,048 chars per managed policy; ~10,240 total for a user; 10,240 for a role). Many inline policies consume this budget and cause `LimitExceeded` errors. Consolidating into managed policies avoids this.

**B5. Compare inline policies vs permissions boundaries — why is a boundary *not* just a big inline policy?**
**Answer:** A boundary sets the **maximum** a principal can ever have (a ceiling, evaluated as intersection); an inline policy **grants** permissions. Semantically different and evaluated at different stages. You often combine them: an inline policy grants specific actions; a boundary prevents the principal from exceeding a scope (e.g., can't touch IAM).

**B6. How do you manage one-off exceptions in a "managed policies only" shop?**
**Answer:** Establish an exception process: document the need, use a **customer-managed policy** with a descriptive name (even if attached to one principal), and track it for review — or use a narrowly-scoped inline policy with a review/expiry tag. The key is governance: any exception must be visible, justified, and time-boxed.

**B7. What happens to a resource-based (inline-on-resource) policy when the resource is deleted?**
**Answer:** It's deleted with the resource — e.g., delete a bucket and its bucket policy is gone; delete a role and its trust policy is gone. This contrasts with managed policies, which persist independently and must be detached/deleted separately.

**B8. How do you detect who has inline policies and what they grant (audit)?**
**Answer:** Enumerate via `iam:ListUserPolicies` / `ListRolePolicies` / `ListGroupPolicies` + `GetUserPolicy` etc. (or SDK/Steampipe/Prowler), then review each. AWS Config and Access Analyzer can flag principals; combine with last-used data to prune unused inline grants.

**B9. Explain the "union + explicit deny" evaluation when a principal has conflicting inline and managed policies.**
**Answer:** If an inline policy Allows `s3:*` and a managed policy Denies `s3:DeleteBucket`, the user cannot delete buckets (explicit deny wins). If one Allows `s3:GetObject` and another Denies nothing about it, the union grants GetObject. Denies always dominate; allows accumulate.

**B10. In a least-privilege review, how would you decide to convert an inline policy to a managed policy vs. delete it?**
**Answer:** Check usage (CloudTrail + last-used) — if unused, delete. If used by multiple principals, convert to customer-managed. If used by one principal but stable and auditable, convert to managed for versioning; keep inline only for true single-principal, short-lived exceptions.

**B11. How do inline policies affect CloudFormation/Terraform drift and IaC best practices?**
**Answer:** Inline policies defined in IaC are managed with the principal resource, so they're fine if declared there — but hand-made inline policies create **configuration drift** (console changes invisible to IaC). Best practice: manage all policies (inline or managed) in IaC, and prefer managed policy resources (`AWS::IAM::ManagedPolicy`) for reuse and drift detection.

**B12. What are IAM quotas relevant to inline policies (counts and sizes), and how do you plan around them?**
**Answer:** Limits include: inline policies per principal, total policy size per principal, managed policies per principal, and policy versions. Plan: consolidate policies, keep inline count low, monitor with Service Quotas, and treat policy size budget as a real constraint for large organizations.

---

## Case C — Scenario

**C1. Scenario:** An auditor asks: "Show me every permission granted by inline policies across the account."
**Question:** How do you produce that inventory?
**Expected answer:** Script a scan: list all users/roles/groups, call `ListUserPolicies`/`ListRolePolicies`/`ListGroupPolicies`, then `GetUserPolicy` etc. to fetch each inline JSON, and output a report (principal → inline policy → actions/resources). Use tools (Steampipe, Prowler, AWS Config advanced queries) for speed. Then review and rationalize into managed policies.

**C2. Scenario:** A role's inline policy was accidentally edited in the console (a stray `*` was added). No one can reconstruct the original.
**Question:** How could this have been prevented, and how do you recover?
**Expected answer:** Inline policies have **no version history**, so recovery depends on backups: IaC (CloudFormation/Terraform) with version control, or AWS Config recording the policy JSON, or CloudTrail showing the change event. Prevent recurrence by converting to **managed policies (versioned)** or managing everything in IaC with code review.

**C3. Scenario:** You must grant a single IAM role permission to read one S3 prefix, and this permission must **not** exist anywhere else or outlive the role.
**Question:** Inline or managed? Justify.
**Expected answer:** **Inline** — it's bound to that one role, deleted with it, and can't be accidentally attached elsewhere. (Alternative: a customer-managed policy attached only to the role also works if you want versioning, but inline best matches the "die with the role" requirement.)

**C4. Scenario:** A developer hit "LimitExceeded" when adding another inline policy to a long-lived role with 30 inline policies.
**Question:** Diagnose and redesign.
**Expected answer:** The role exceeded policy count/size quotas from accumulated inline policies. Redesign: consolidate overlapping inline policies into **customer-managed policies** (fewer attachments, versioned), remove unused ones (verify with last-used/CloudTrail), and use tags/ABAC to reduce policy count. Then attach managed policies and delete the inline clutter.

**C5. Scenario:** Two teams need identical read-only access to their respective S3 prefixes, each via an inline policy on their own role.
**Question:** How do you reduce duplication safely?
**Expected answer:** Create one **customer-managed policy** using policy variables — e.g., `"Resource": "arn:aws:s3:::bucket/${aws:PrincipalTag/team}/*"` (or `${aws:username}`) — so one reusable policy serves both teams based on their tags. Attach it to both roles and remove the inline duplicates. This keeps least-privilege while eliminating copy-paste drift.

**C6. Scenario:** Security policy mandates no inline policies except documented exceptions. You find 40 rogue inline policies.
**Question:** Build the remediation + prevention plan.
**Expected answer:** (1) Inventory and classify each inline policy (used/unused via last-used data). (2) Delete unused; convert used ones to customer-managed policies. (3) Create documented exceptions with justification and expiry. (4) Enforce with **SCP** (e.g., deny `iam:PutUserPolicy`/`PutRolePolicy` except for an exception role) and **AWS Config** custom/managed rules + Security Hub to alert on new inline policies. (5) Require IaC for all future policy changes.
