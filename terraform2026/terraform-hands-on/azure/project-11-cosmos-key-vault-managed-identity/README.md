# Project 11 — Cosmos DB + Key Vault + Managed Identity (Azure)

**Difficulty:** ⭐⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0.30/mo (Cosmos 400 RU) — destroy after

The "no secrets in code" architecture: a web app that reads its DB password from Key Vault
using a **managed identity** (no client secrets anywhere), and a Cosmos DB NoSQL store.

## Concepts practiced
- Cosmos DB (SQL API: account → database → container, RU/s) → `../terraform-mastery/02-azure-provider/06-databases.md`
- Key Vault + access policies + **managed identity** → `../terraform-mastery/02-azure-provider/02-azure-foundations-and-identity.md`
- The identity chain: app identity → vault access policy → secret reference

## The flow

```
web app (SystemAssigned identity)
   │  identity (no secret!)
   ▼
Key Vault access policy allows THIS identity's principal_id
   ▼
app_settings references the vault secret  →  password lives ONLY in the vault
```

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, location, the db password value |
| `main.tf` | RG + Cosmos + Key Vault + policy + web app (identity + vault reference) |
| `outputs.tf` | vault URI, app URL, cosmos endpoint |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-11-cosmos-key-vault-managed-identity
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it

```bash
# 1. cosmos: put + read a document (via portal: Data Explorer → orders → New Item
#    { "id": "1", "status": "new" } — or az cosmosdb sql query)
az cosmosdb sql query \
  --resource-group $(terraform output -raw rg_name) \
  --account-name $(terraform output -raw cosmos_name) \
  --database-name appdb --container-name orders \
  --sql "SELECT * FROM c" -o table

# 2. the secret is in the vault (readable by YOU via the access policy)
az keyvault secret show --name db-password \
  --vault-name $(terraform output -raw vault_name) --query value -o tsv

# 3. the web app's identity is the one the vault policy allows
az webapp identity show -g $(terraform output -raw rg_name) -n $(terraform output -raw app_name) -o table
az keyvault show --name $(terraform output -raw vault_name) -o table

# 4. (concept check) grep the deployed app config — the password is NOT in it:
az webapp config appsettings list -g $(terraform output -raw rg_name) -n $(terraform output -raw app_name) -o table
# you'll see the vault REFERENCE, not the value — that's the whole point
```

## Break it (this is the learning)

1. Change `sku_name = "standard"` → `"premium"` on the vault → `plan` → in-place. (Premium adds
   HSM-backed keys.) Revert.
2. Remove `Get` from the access policy's `secret_permissions` → `plan` → in-place. Now the app's
   identity can't read the secret (apply, then put it back).
3. Add a second container (`products`) to Cosmos → `plan` → one new resource.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Vault name invalid | 3–24 chars, letters/digits/hyphens, must start with a letter — shorten `project` |
| App can't read the secret at runtime | the access policy must allow the app's **principal_id** — check `az keyvault show` → enabled for template deployment / the policy's object id matches the identity |
| Cosmos `az cosmosdb sql query` permission error | your `az login` user needs CosmosDB Data Reader on the vault-less resource — use the portal Data Explorer instead |
