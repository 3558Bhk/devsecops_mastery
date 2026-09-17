# ALB (Application Load Balancer) — Terraform how-to

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

**What:** Layer-7 (HTTP/HTTPS) load balancer: routes by **path/host**, health-checks, terminates SSL, sits in front of targets.

**Interview angle (SDE3):**
- ALB = L7 (content-aware: /api → service A, /static → S3). NLB = L4 (fast, TCP/UDP, static IP, preserve client IP).
- ALB DNS name is stable; **IPs behind it change** — never hardcode ALB IPs.
- Target group = the "who am I load-balancing to" object; the **health check** defines what "healthy" means.

## Run it
```bash
terraform init && terraform plan && terraform apply   # takes ~5 min (2 tiny instances boot)
# verify: curl http://$(aws elbv2 describe-load-balancers --query 'LoadBalancers[0].DNSName' --output text)
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| 503 from the ALB | all targets are `unused` — the health check is failing (wrong port/path/protocol on the target group) |
| ALB in a private subnet | ALB subnets must be **public** (need a path to the internet) |
| Health check "works" but app errors | the check hits the LB's port, but the app listens elsewhere — check the target's **port** vs the check's **port** |
