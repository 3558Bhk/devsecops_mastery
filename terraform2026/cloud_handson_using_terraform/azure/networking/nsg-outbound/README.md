# NSG Outbound Rules — Terraform how-to

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

**What:** outbound NSG rules: allow the app to reach a specific API (443) and block a known-bad prefix — plus why stateless means you need BOTH directions.

**Interview angle (SDE3):**
- Outbound rules control **what resources inside the VNet may call out to** — the classic use: "VMs may only talk to our upstream API, not the open Internet".
- NSG is **stateless** → an inbound Allow does NOT auto-permit the response packets; you must allow the outbound too (ASG is stateful and does this for you).
- "Egress filtering" is the modern security ask: block C2/exfil by restricting outbound prefixes and ports.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az network nsg list-rule -g rg-lab-nsgout -n nsg-outbound
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| App can reach IN but responses don't come back | NSG is **stateless** — the outbound direction was denied (or there was no matching allow); add the outbound rule |
| "Block the Internet" broke the VM | the VM still needs outbound to **update endpoints, DNS (53/udp), and its storage** — don't deny-all blindly, or use `source = VirtualNetwork` carve-outs |
| Rule order confusion | same as inbound: **lower number = evaluated first**, first match wins, priorities must be unique |
