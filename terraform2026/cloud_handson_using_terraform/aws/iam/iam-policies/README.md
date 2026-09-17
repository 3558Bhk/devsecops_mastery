# IAM Policies (managed) — Terraform how-to

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

**What:** a customer **user** + a **managed policy** built from `aws_iam_policy_document` + the attachment.

**Interview angle (SDE3):**
- **Managed** policy (reusable, attach to many) vs **inline** policy (lives on the principal, dies with it).
- Least privilege in practice: name the exact ARNs, add `Condition`s (e.g. `aws:SourceIp`), scope actions to what's used.
- Users = humans/CI; for services prefer **roles** (no long-lived keys) — this file is the "human" side.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws iam list-attached-user-policies --user-name lab-user
#         aws iam get-policy-policy-document \
#           --policy-arn $(aws iam list-attached-user-policies --user-name lab-user \
#             --query 'AttachedPolicies[0].Arn' --output text)
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Policy works for "everything" | you wrote `Resource: "*"` — scope to exact ARNs (that's the whole point of Terraform-managed policy) |
| User can't do what the policy says | check the **action spelling** (`s3:GetObject` ≠ `s3:GetObject*`) and that no other policy `Deny`s it (explicit deny wins) |
