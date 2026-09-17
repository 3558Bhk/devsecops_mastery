# Front Door — Terraform how-to

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

**What:** a global **Layer 7** CDN + load-balancer + WAF: profile + origin group + 2 origins + endpoint + a route.

**Interview angle (SDE3):**
- Front Door = **global** (any-pop) **L7** routing + **CDN** + **WAF** in one — the modern replacement for "Traffic Manager + Application Gateway + CDN" combos.
- The model: **profile → origin group → origins**, then **endpoint → route** (the route points at an origin group).
- It's **global anycast** (single VIP), works with **standard + premium** skus (Premium adds **WAF**, **caching rules**, **re-routing**).
- Front Door vs Application Gateway: FD = **global** + CDN + anycast; App GW = **per-region** L7 (closer to the VNet, can load-balance inside one region's VNets).

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ profile costs — destroy when done
# verify: az network frontdoor profile list -g rg-lab-fd
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Origin "403 / AccessDenied" | the origin (e.g. a storage account) blocks the Front Door IP ranges — allow `Microsoft.Cdn` / the Front Door service in the origin's firewall |
| Route not matching | the route's `patterns_to_match` must match the path (e.g. `/*` or `/api*`) — an unmatched path 404s |
| No TLS | enable **HTTPS** on the route/endpoint + a **certificate** — the Standard sku needs a cert on the endpoint for HTTPS |
