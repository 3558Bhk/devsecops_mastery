# Key Vault — Terraform how-to

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

**What:** a **Key Vault** (RBAC-authorized) + a **secret** + a **user-assigned identity** granted the **Key Vault Secrets Officer** role.

**Interview angle (SDE3):**
- **Key Vault** = a managed store for **secrets** (strings), **keys** (crypto), and **certificates** — with **access control** + **audit**.
- **RBAC vs access policy**: in `azurerm` v5, Key Vault uses **RBAC** (`rbac_authorization_enabled = true`) — you grant roles (e.g. **Key Vault Secrets Officer**) instead of the old **access policies**. The interview: "how do you give an app access to a secret?" → **RBAC role** (or a **managed identity** + role).
- The **managed identity** pattern: the app has an identity → the identity gets the **Secrets Officer** role on the vault → the app reads the secret (no stored key).
- **Soft delete** (vault keeps deleted items for 90 days) + **purge protection** = the "I deleted a secret by mistake" safety net.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az keyvault list -g rg-lab-kv
#   az keyvault secret list -g rg-lab-kv --vault-name kv-lab
# read the secret: az keyvault secret show -g rg-lab-kv --vault-name kv-lab --name app-secret
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "Authorization failed" | the identity doesn't have the **Key Vault Secrets Officer** role (or the **scope** is wrong) — check `az role assignment list` |
| RBAC vs access-policy confusion | v5 uses **RBAC** (`rbac_authorization_enabled = true`) — the old **access policies** are deprecated; grant a **role** instead |
| "Soft-deleted secret" can't be recreated | the vault **soft-deletes** for 90 days — `az keyvault secret restore` (or **purge protection** is on, so you can't purge it) |
