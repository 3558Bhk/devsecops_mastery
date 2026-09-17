# NAT Gateway — Terraform how-to

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

**What:** lets **private** subnets initiate outbound internet (patching, pulling images) while never exposing instances inbound.

**Interview angle (SDE3):**
- Private subnets route `0.0.0.0/0 → NAT GW`; public subnets route it to the **IGW** — that one-line difference is the whole design.
- NAT GW = per-AZ, one IP; for HA put one NAT GW in each AZ (or a shared subnet).
- Alternatives: **NAT Instance** (cheaper, DIY, single AZ) and **VPC Endpoint** (for AWS APIs — no internet needed at all).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws ec2 describe-nat-gateways
# real test: run an instance in the private subnet → `curl http://checkip.amazonaws.com`
```

## Clean up
```bash
terraform destroy   # NAT GW + EIP cost money while they exist — destroy first
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Private instance can't reach internet | the private subnet's route table is missing `0.0.0.0/0 → nat-gw` |
| `curl` works but is slow/flaky | NAT GW is per-AZ — an instance in AZ-b talking through an AZ-a NAT pays for cross-AZ |
| Port exhaustion under load | each connection uses an ephemeral port on the NAT's public IP (~10k max) — add NAT GWs / EIPs |
