# Azure API Services (API Management) — Terraform how-to

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

**What:** an **API Management** service (Consumption) + a **product** + an **API** — the managed API gateway.

**Interview angle (SDE3):**
- **API Management** = a **managed gateway**: **throttling**, **caching**, **authentication** (API key, OAuth, OpenID), **versioning**, **analytics**, **WAF** — all policy-driven (no code).
- The 3-object model: a **service** (the gateway) → a **product** (a bundle of APIs + a pricing tier) → an **API** (a specific endpoint). A **subscription** (an API key) is issued per product.
- The interview: "How do you secure an API?" → **API key** (per consumer), **OAuth2/OpenID Connect** (for users), **WAF** (for attacks) — all in the gateway, not in the app.
- **Consumption** sku = pay-per-call (no always-on gateway); **Developer/Standard** = dedicated gateway.

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ APM costs — destroy when done
# verify: az apim list -g rg-lab-apim
#   az apim api list -g rg-lab-apim -s apim-lab
#   az apim product list -g rg-lab-apim -s apim-lab
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| API "401 Unauthorized" | the consumer didn't pass a **subscription key** (API key) — issue a subscription and add the key to the `Ocp-Apim-Subscription-Key` header |
| "Product not found" | an API must be **assigned to a product** (`product_id`) and the product **published** (`published = true`) |
| Consumption "no gateway" | the **Consumption** sku has **no always-on** gateway — for a dedicated, always-on gateway use a **Dedicated** sku |
