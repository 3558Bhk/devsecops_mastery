# Azure SQL — Terraform how-to

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

**What:** an **Azure SQL logical server** + a **database** (General Purpose) + a firewall rule + TDE + short-term retention.

**Interview angle (SDE3):**
- **Azure SQL DB** = a **PaaS** single database (fully managed). Don't confuse with **SQL MI** (a managed *instance*) or **SQL on VM** (IaaS).
- **Tiers**: **General Purpose** (balanced), **Business Critical** (high perf), **Hyperscale** (huge), and **Serverless** (auto pause). The interview asks "which tier for a spiky, low-traffic API?" → **Serverless** or **DTU/Gen5 GP**.
- The server has a **public endpoint** → you must add **firewall rules** (or a VNet service endpoint / private endpoint) — a new server is locked down by default.
- **TDE** (Transparent Data Encryption) = encryption at rest, on by default; **short-term retention** = point-in-time restore for N days.

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ DB costs — destroy when done
# verify: az sql server list -g rg-lab-sql
#   az sql db list -g rg-lab-sql -s sql-srv-lab
# connect: sqlcmd -S sql-srv-lab.database.windows.net -U sqladmin -P <pw>
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "Login failed" / connection refused | the client IP isn't in the **firewall rule** — add it (or use a **private endpoint**) |
| `sku_name` "not valid" | the SKU must match the tier and have a valid **size** (e.g. `GP_S_G5`) — and the DB must be the right size for that SKU |
| TDE "already enabled" | TDE is **on by default**; to use a **customer-managed key** you point it at a **Key Vault** key (the `transparent_data_encryption_key_vault_key_id`) |
