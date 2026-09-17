# VPC Endpoints — Terraform how-to

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

**What:** a private in-VPC route to an **AWS API** (S3, DynamoDB, …) — no internet gateway, no NAT, no public IP needed.

**Interview angle (SDE3):**
- **Gateway** endpoints (S3, DynamoDB) = free, just a route-table entry. **Interface** endpoints (everything else) = ENI per subnet, charged hourly.
- "How do I let my private RDS reach S3 without a NAT GW?" → gateway endpoint. A favorite SDE-3 question.
- Endpoints pair with **endpoint policies** (allow/deny by bucket, by principal) — a common least-privilege story.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws ec2 describe-vpc-endpoints
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| S3 still going via internet/NAT | the **route table** association is missing — gateway endpoints only work on subnets whose table has the endpoint |
| `AccessDenied` after adding the endpoint | the endpoint **policy** or bucket policy now applies — check both allow the principal |
