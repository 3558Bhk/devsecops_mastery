# Hub & Spoke — Terraform how-to

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

**What:** the enterprise topology: a hub VNet (with a gateway subnet) + two spoke VNets, all peer-armed both ways.

**Interview angle (SDE3):**
- Hub & spoke = all spokes peer to the **hub** (which holds the VPN/ExpressRoute gateway) instead of meshing to each other → **N peering links instead of N×(N-1)/2**.
- Peering is **not transitive by default**: spoke-A ↔ spoke-B traffic still goes A → hub → B (that's the point — the hub is the controlled choke point).
- You peer **both directions** (each VNet peering is one-way until the other side is created).
- The hub's `10.0.0.0/24` is the **vNet gateway subnet** (special name/size for VPN/ER gateways).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az network vnet peer list -g rg-lab-hubspoke
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Spokes can't reach each other | the **remote** peering is missing — peering is two one-way links (create both `azurerm_virtual_network_peering`s) |
| "Should I use route tables or peering?" | use **peering** for same-region VNets (private, fast, no NAT); use **User Defined Routes** only for specific prefix steering |
| Address space overlap | peered VNets must have **non-overlapping** prefixes (10.1/10.2/10.3 in this file) |
