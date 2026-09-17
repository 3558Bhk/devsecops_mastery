# Project 08 — Capstone: 3-Tier Web App (Azure)

**Difficulty:** ⭐⭐⭐⭐ · **⏱️ ~2.5 hrs** · **Cost:** ~$0.05–0.15/hr while running (App Gateway bills a monthly minimum) — TEST, THEN DESTROY

Everything combined, in one realistic architecture:

```
internet ──► Application Gateway (WAF v2)
                 └──► web VM (B1s, static private IP, NSG: 80)
internet ──► Azure SQL (Basic)
Key Vault (DB password as a secret) + Log Analytics (WAF logs)
```

The network reuses **the VNet module you built in project 05** — the module payoff.
The App Gateway needs a subnet with a *delegation*, which the generic module doesn't
do, so that subnet is created inline in the root (a real-world pattern: module for the
standard parts, inline for the special parts).

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, location, SQL password, admin password |
| `network.tf` | RG + VNet module + the special App Gateway subnet |
| `web.tf` | NSG + NIC + VM + public IP + Application Gateway (WAF v2) |
| `db.tf` | Azure SQL server + database |
| `vault.tf` | Key Vault + the DB password stored as a secret |
| `observability.tf` | Log Analytics + WAF log streaming |
| `outputs.tf` | App Gateway IP, SQL FQDN, vault URI |

## Run it

```bash
cd project-08-capstone-3-tier-app
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan        # ~12 resources — this is your exam; read every line
terraform apply       # ~10 min (the VM + SQL server take the longest)
```

## Verify it (all four must work)

```bash
# 1. the web tier behind the WAF
sleep 60   # App Gateway needs a moment to become ready
curl -s http://$(terraform output -raw appgw_ip)          # → "Hello from the Azure capstone!"

# 2. the database is up
az sql server list -g $(terraform output -raw rg_name) -o table
# connect:  az sql db tsql query -s $(terraform output -raw sql_server) -d appdb -q "SELECT 1 AS ok"

# 3. the secret is in the vault
az keyvault secret show --name db-password \
  --vault-name $(terraform output -raw vault_name) --query value -o tsv

# 4. WAF logs flow to Log Analytics (do this in the portal)
#    Log Analytics workspace → Log Analytics queries:
#    AzureActivity and AppGateway logs will appear after you hit the site a few times
```

## Break it (this is the learning)

1. In the `sku` block, change `name = "WAF_v2"` → `"WAF_v1"` (and `tier = "WAF_v1"`) → `plan` →
   **replacement** of the whole gateway. Read it, revert.
2. Add a second `enabled_log` category (`"AuditLogs"`) to the diagnostic setting → `plan` → in-place update. Apply.
3. In the portal, open Application Gateway → WAF settings: mode is **Prevention** —
   then flip it to **Detection** and re-attack: `curl "http://<ip>/<script>alert(1)</script>"`.
   In Prevention the WAF blocks it (403); in Detection it logs but allows.

## Clean up (MONEY IS BURNING — App Gateway bills a monthly minimum)

```bash
terraform destroy     # ~8 min
```

## Common mistakes

| Mistake | Fix |
|---|---|
| App Gateway `Operation returned an error: ... subnet` | the App GW subnet must have the delegation (check `network.tf`) and be in the same VNet |
| `curl` to the App Gateway IP hangs | wait 2–3 min after apply; check the gateway status in the portal |
| SQL connection refused | the SQL server has a firewall by default — the lab only uses it via `az sql`, which doesn't need a public firewall rule |
| `server name is already taken` | SQL server names are **globally unique** — change `project` |
