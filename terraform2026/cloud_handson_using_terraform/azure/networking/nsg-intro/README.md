# NSG Intro — Terraform how-to

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

**What:** a VNet + subnet + an **empty** NSG attached to it — the baseline to learn rule priority on.

**Interview angle (SDE3):**
- An NSG starts with **default rules** (priority 100–400, e.g. AllowVNetInbound, DenyAllInbound) — an "empty" NSG still has them.
- Rules evaluate in **ascending priority** (100 first); first match **wins** (allow or deny) — that's why a `deny 443 @ 200` beats an `allow 443 @ 300`.
- NSG = **stateless**: an inbound allow does NOT auto-allow the response — you need an outbound rule too (ASG is stateful, NSG is not).

## Run it
```bash
terraform init && terraform plan && terraform apply
# see the default rules: az network nsg list-rule -g rg-lab-nsg -n nsg-intro
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "My rule doesn't apply" | a **lower-priority (smaller number) rule matched first** — priorities must be unique per direction |
| Outbound is blocked | NSG is **stateless** — add the matching outbound rule (or use an ASG for stateful) |
| Confused about defaults | an NSG auto-attaches to a new subnet with **DenyAllInbound** (but allows within-VNet) — that's why new subnets are quiet by default |
