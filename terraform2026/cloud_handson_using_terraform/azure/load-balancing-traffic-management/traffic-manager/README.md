# Traffic Manager — Terraform how-to

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

**What:** a global **DNS-based** traffic manager profile + endpoints — the "route users to the best region" service.

**Interview angle (SDE3):**
- Traffic Manager is **DNS-based** (it returns an IP via DNS, not a proxy) — it's **L7-ish but at the DNS layer**: routing by **performance (latency)**, **weighted**, **priority (failover)**, or **geographic**.
- It's **not** a load balancer for a single region — it balances **across regions/endpoints** (global failover).
- The **profile** + **endpoints** model: a profile defines the routing method + a **monitor**, endpoints are the targets (Azure resources or external).
- Interview: "When would you use Traffic Manager vs Application Gateway?" → TM = global/regional failover; App GW = per-region L7 + WAF.

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ profile + endpoints cost — destroy when done
# verify: az network dns traffic-manager profile list -g rg-lab-tm
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Traffic not shifting to the healthy endpoint | the **endpoint monitor** is still `Enabled` but the unhealthy endpoint isn't being probed/removed — check the profile's monitor interval + the endpoint's `weight`/status |
| "It's not load balancing" | Traffic Manager is **DNS** — clients cache the answer (TTL); it won't rebalance faster than DNS TTL |
| Wrong method | pick the method for the goal: **Performance** (lowest latency), **Priority** (active/passive failover), **Weighted** (percent), **Geographic** (region) |
