# Inline Policies — Terraform how-to

## 📁 File structure (the standard Terraform layout)

| File | What it does |
|---|---|
| `providers.tf` | the `terraform` block (required_providers) + provider config — "which cloud, which provider version, how to log in" |
| `variables.tf` | input variables — the knobs (e.g. `region`) you change without touching the resources |
| `main.tf` | the resources — the actual infrastructure Terraform creates (and any `data` lookups) |
| `outputs.tf` | output values — the endpoints/ids/URLs Terraform prints after `apply` |

> Why four files? Terraform reads **every** `.tf` file in the folder as one program. Splitting by
> concern is the industry convention: reviewers find the resources in `main.tf`, you change
> settings in `variables.tf`, and you read results in `outputs.tf` — instead of one 500-line file.

**What:** the same least-privilege idea, but the policy lives **inside** the role (`aws_iam_role_policy`) — perfect for a role that only ever needs exactly these permissions.

**Interview angle (SDE3):**
- Inline vs managed: inline can't be shared; managed (a separate `aws_iam_policy`) can be attached to many principals.
- For **roles** (services), inline is usually right — the policy is as unique as the service is.
- Always show the `assume_role_policy` (who may become the role) AND the permissions (what it can do) — two separate documents.

## Run it
```bash
terraform init && terraform plan &&terraform apply
# verify: aws iam get-role-policy --role-name lab-inline-role --policy-name bucket-writer
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `AccessDenied` from the service | the **assume** policy is right but the **permissions** are wrong (or missing an action) — check both documents |
| Role works but "sometimes" fails | a cross-account or `sts:AssumeRole` path is involved — check the trust document's `Condition` |
