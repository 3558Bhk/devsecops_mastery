# Route 53 — Terraform how-to

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

**What:** a hosted zone + an A record + a health check — the DNS layer with routing and monitoring.

**Interview angle (SDE3):**
- Routing policies: simple (default) → weighted (canary) → latency → failover (active/passive) — know the canary story for weighted.
- **Alias** records (to ALB/CloudFront) are free + follow the target's DNS; **A** records cost + you manage the value.
- Route 53 is also the health-check backbone for failover (the record flips when the check goes red).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws route53 list-resource-record-sets --hosted-zone-id $(terraform output -raw zone_id)
# dig lab-2026.example.com   (after you make the zone point at Route 53's NS — a real domain is needed for it to resolve publicly)
```

> ⚠️ The zone name here is a dummy domain. For a real test, use a domain you own (or accept that the zone exists but doesn't resolve publicly).

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Record "exists" but doesn't resolve | the domain's **NS delegation** isn't pointed at Route 53's nameservers (or the zone is a private zone without an association) |
| Alias + TTL both set | alias records have no TTL (it follows the target) — Terraform rejects the combination |
