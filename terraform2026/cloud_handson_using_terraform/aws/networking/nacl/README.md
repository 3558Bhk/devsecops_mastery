# NACL — Terraform how-to

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

**What:** the **stateless** firewall at the **subnet** level — the perimeter layer under security groups.

**Interview angle (SDE3):**
- NACL = **stateless**: allow inbound, and you MUST allow the return traffic outbound too (that's why the lab allows ephemeral ports both ways).
- NACL rules are **numbered** (1–32766) and evaluated by priority; **no number = implicit deny**.
- Use NACLs for coarse perimeter denials (e.g. "no inbound to private subnets at all"); use SGs for fine-grained allow.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws ec2 describe-network-acls
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Instances "suddenly" can't browse | you allowed inbound but forgot the **outbound return range** (1024–65535) — stateless! |
| Rule order surprises | NACLs are evaluated by number; a higher-numbered allow after a lower-numbered deny is dead code |
