# Security Groups — Terraform how-to

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

**What:** the stateful firewall at the **ENI (instance)** level — ingress/egress rules per workload tier.

**Interview angle (SDE3):**
- SGs are **stateful** (reply traffic auto-allowed) and **allow-only** (no deny rules — that's NACL's job).
- A security group **can reference another SG** (rule: "5432 from app-sg") → tier-based access without IP lists.
- Default behavior: allow all egress; a new SG has **no** ingress.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws ec2 describe-security-groups --filters Name=group-name,Values=app-sg,database-sg
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "Security group is too large" | an SG has ~60 rule slots + 500 references per ENI; split into fewer, well-named SGs |
| Instance can't reach the DB | the **egress** of the app SG or the **ingress** of the DB SG is missing — check both sides |
| Rules that "should" work don't | SG rules attach to a NIC, not a subnet/VM — the NIC must be in the subnet you think it's in |
