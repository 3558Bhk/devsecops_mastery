# VPC Peering — Terraform how-to

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

**What:** two VPCs in different regions, connected so private IPs can talk directly (no internet, no NAT).

**Interview angle (SDE3):**
- Peering is **transitive = NO** (A↔B, B↔C, but A↛C) → that's why Transit Gateway exists.
- CIDRs of peered VPCs must not overlap; DNS resolution is opt-in per side.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws ec2 describe-vpc-peering-connections --filters Name=status-code,Values=accepted
```

## Clean up
```bash
terraform destroy   # routes and peering go first, then the VPCs
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `Rejected` status forever | someone's account must accept it — `auto_accept = true` (same account) or `aws ec2 accept-vpc-peering-connection` |
| No connectivity after apply | peering only creates the **link** — you must add **routes** in BOTH VPCs (that's what this file does) |
| Overlapping CIDRs | peering is rejected at creation; pick non-overlapping /16s |
