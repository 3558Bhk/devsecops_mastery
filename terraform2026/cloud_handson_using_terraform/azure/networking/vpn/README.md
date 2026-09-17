# Azure VPN (site-to-site) — Terraform how-to

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

**What:** a traditional site-to-site VPN: VNet gateway + local network gateway (your on-prem) + the IPsec connection.

**Interview angle (SDE3):**
- Site-to-site = VNet Gateway (cloud) ↔ **Local Network Gateway** (a record for your on-prem public IP) + an **IPsec connection** with a shared key.
- `sku = "Basic"` is the cheap lab option; **HighPerformance** for >100 Mbps.
- The **vNet gateway subnet** must be named `GatewaySubnet` (or `vnet-gateway-subnet`) and be a certain size — the gateway lives in it.
- ExpressRoute = private, dedicated circuit (no Internet); VPN = over the Internet (cheaper, less predictable).

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ gateway costs — destroy when done
# verify: az network vnet-gateway list -g rg-lab-vpn
# connect on-prem: the connection needs the SAME shared key both ends
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "Gateway failed to create" | the subnet isn't the **GatewaySubnet** (name + size requirements) |
| Connection `Connected` flapping | the **shared key** differs between the VNG connection and the on-prem device — they must match |
| On-prem can't reach the VNet | the local network gateway's `local_network_address_space` must be your on-prem CIDR (e.g. `192.168.0.0/16`) |
