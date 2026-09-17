# KMS — Terraform how-to

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

**What:** a customer-managed key + an alias + grant + an encrypted S3 bucket using it.

**Interview angle (SDE3):**
- Customer-Managed Keys (CMKs) vs AWS-managed keys: you control rotation, policy, deletion window (7–30 days), and **which service can use it** (via key policy or grants).
- Two permission layers: **key policy** (can the key be used/managed) + **resource policy** (can I read the data) — data-encryption vs metadata-access are different.
- The **key deletion window**: deleting schedules deletion with a 7–30 day wait so encrypted data can be decrypted first.

## Run it
```bash
terraform init && terraform plan && terraform apply
# encrypt: aws kms encrypt --key-id $(terraform output -raw alias_name) --plaintext "secret" --grant-token ...
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Service "AccessDenied" on the key | the key policy must allow the **service** (e.g. S3) `kms:GenerateDataKey` — or add a grant |
| "Key is scheduled for deletion" | deletion is async with a 7–30 day window — `aws kms cancel-key-deletion` to undo |
| Aliasing the wrong ARN | always reference the **alias** (`arn:alias/...`), not the key ARN — keys rotate, aliases don't change |
