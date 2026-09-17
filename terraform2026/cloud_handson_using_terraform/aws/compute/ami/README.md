# AMI — Terraform how-to

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

**What:** the two halves of the AMI story — **look one up** (data source) and **create one** (from a stopped instance).

**Interview angle (SDE3):**
- Hardcoding an AMI id = broken in 3 months. Always `data "aws_ami"` (or SSM parameter `aws:ssm:/ssm/documents/...`, or an AMI built by your pipeline).
- Creating an AMI = build an instance (with your packages/config) → stop → create image. That's the "golden image" pipeline in its simplest form.
- AMIs are per-region — copy them with `aws ec2 copy-image`.

## Run it
```bash
terraform init && terraform plan && terraform apply   # builds the instance, waits, then the AMI
# verify: aws ec2 describe-images --owners self --filters Name=name,Values=lab-ami-*
```

## Clean up
```bash
terraform destroy   # (the AMI resource deletes the image; the instance too)
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `aws_ami` lookup returns an old image | pin `most_recent = true` **and** the name filter; or pin an exact id deliberately |
| AMI build fails | the instance must reach `stopped` before the AMI — Terraform's depends_on handles ordering, but a failing user_data breaks the instance |
