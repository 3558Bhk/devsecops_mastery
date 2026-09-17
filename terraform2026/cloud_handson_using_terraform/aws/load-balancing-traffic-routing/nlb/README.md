# NLB (Network Load Balancer) — Terraform how-to

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

**What:** Layer-4 (TCP/UDP) load balancer — raw speed, **static IP per AZ**, preserves client source IP.

**Interview angle (SDE3):**
- ALB vs NLB: L7 content routing vs L4 throughput (millions of new connections/sec). NLB for gRPC/UDP/games/DB-ish workloads, or when you need a **static IP** (firewall rules, cert CN).
- NLB can target by **IP** (any fleet on the network, even on-prem via Direct Connect).
- Cross-zone load balancing is ON by default for NLB (you pay cross-AZ data transfer).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws elbv2 describe-load-balancers --query 'LoadBalancers[0].DNSName'
# test: nc <nlb-dns> 80  (or curl — the backend is httpd)
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| NLB with no health check "passing" | NLB's default check is a **TCP connect** — anything that accepts a connection counts as healthy (even a broken app!) |
| "Static IP" surprises you | the NLB DNS is stable, but it has a **different IP per AZ** — publish the DNS name |
| High latency to backends in other AZs | cross-AZ is enabled by default and costs per-GB — put targets in the same AZ when you can |
