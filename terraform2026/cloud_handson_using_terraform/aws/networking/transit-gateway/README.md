# Transit Gateway — Terraform how-to

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

**What:** a hub that connects many VPCs (star topology) — the scalable replacement for N×(N-1)/2 peering connections.

**Interview angle (SDE3):**
- Peering = point-to-point, non-transitive. TGW = central hub, **transitive by design** (A→hub→B→C works).
- TGW route tables can isolate spokes (blackhole routes / route table associations) — a common "security boundary" question.
- Cost: TGW ~$0.05/hr + $0.02/GB processed — you pay for the hub.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws ec2 describe-transit-gateway-attachments --filters Name=state,Values=available
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Subnets unreachable | the TGW attachment needs subnets in **≥2 AZs**, and each VPC needs a route to the peer CIDR → the TGW |
| `InvalidAttachment` | the VPC CIDRs of attached VPCs must not overlap |
