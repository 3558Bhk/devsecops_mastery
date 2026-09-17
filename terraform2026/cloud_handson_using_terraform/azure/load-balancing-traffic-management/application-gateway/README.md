# Application Gateway — Terraform how-to

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

**What:** a **Layer 7** load balancer (WAF v2) with an HTTP listener + a basic path-based routing rule to a backend.

**Interview angle (SDE3):**
- App Gateway = **Layer 7** (understands HTTP) — path-based routing, TLS **termination**, **WAF**, cookie-based affinity. (Classic LB = Layer 4 only.)
- It **must** have a public IP (unlike the classic LB which can be internal) and runs on its **own subnet** (not with the backend VMs).
- **WAF v2** supports **Managed Rule Sets** (Microsoft/OWASP) — the interview favourite: "enable OWASP CRS 3.x, put it in Detection first, then Prevention after you fix false positives".
- Capacity is **units** (1–10); each unit ≈ a size (v2 uses instance count, not vCPU).

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ capacity 2 costs — destroy when done
# verify: az network application-gateway show -g rg-lab-appgw -n appgw-lab
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| WAF "not blocking" | the rule set is in **Detection** mode — switch to **Prevention** (after tuning false positives) |
| TLS not offloading | you need a **certificate** in the App Gateway + an HTTPS listener — an HTTP listener doesn't terminate TLS |
| Backend 502 | the App Gateway must be able to reach the backend (NSG/ASG on the backend NIC must allow from the App GW's subnet) |
