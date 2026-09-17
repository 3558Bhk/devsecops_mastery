# Project 07 — Key Vault + App Service (Azure)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0 (F1 web app is free; Key Vault Standard is ~$0.30/mo)

You will create a **Key Vault** (Azure's secrets manager), store a secret in it, give your
own user access to it, and deploy a **web app** on the free plan.

## Concepts practiced
- Key Vault + access policies → `../terraform-mastery/02-azure-provider/02-azure-foundations-and-identity.md`
- `data.azurerm_client_config` — "who am I?" (your Azure AD identity)
- App Service plan (F1 = free) + Linux web app → `../terraform-mastery/02-azure-provider/08-serverless-functions-and-app-service.md`

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, location, the secret value |
| `main.tf` | RG + Key Vault + access policy + secret + plan + web app |
| `outputs.tf` | vault URI, secret, web app URL |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-07-key-vault-serverless
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it

```bash
# the vault + secret
az keyvault show --name $(terraform output -raw vault_name) -o table
az keyvault secret show --name app-secret --vault-name $(terraform output -raw vault_name) --query value -o tsv

# the web app (F1 apps take ~1 min to become ready)
sleep 60
curl -sI https://$(terraform output -raw app_url) | head -3     # expect HTTP/2 200
```

## Break it (this is the learning)

1. Change `secret_value` in tfvars → `plan` → only the secret **updates** (Key Vault keeps old versions). Apply.
2. Add `secret_permissions = ["Get", "Set", "List", "Delete"]` to the access policy → `plan` → in-place update.
3. In `main.tf`, add another key to the web app's `app_settings` map (e.g. `"Env" = var.environment`)
   → `plan` → only the web app updates.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `az keyvault secret show` → AccessDenied | the access policy only covers the user from `az login`; log in as that user |
| Vault name "must be between 3 and 24 characters" | shorten `project` — the name is `<project>kv<env>` |
| Web app 503s for a while | F1 free apps spin up on first hit — curl again in 30s |
| `app_secret` shows in plan output | it's marked `sensitive = true` in variables.tf — check you didn't remove it |
