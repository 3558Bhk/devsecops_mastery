# Azure Identity (Entra ID) — Terraform how-to

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

**What:** the **identity** side of "identity mgmt in storage": a **User-Assigned Managed Identity** + RBAC grant, plus the `az` CLI to create **Entra users/groups** (which `azurerm` v5 does NOT manage).

**Interview angle (SDE3):**
- **Entra ID** (the new name for Azure AD) = the **identity provider** for Azure: users, groups, **service principals** (app identities), and **managed identities** all live in it.
- **Managed identity** = an identity the **platform** assigns to a resource (no secrets). Two kinds: **System-assigned** (lives with the resource) and **User-assigned** (standalone, shareable).
- The **RBAC grant** is the key: a **role assignment** (role + scope + principal) is what actually gives the identity access — the identity alone does nothing.
- `azurerm` v5 **removed** the AD-object resources (users/groups/service principals are now Microsoft Graph territory) — so **users/groups via `az ad` CLI / Graph**, and **managed identities + role assignments via Terraform** (as shown).

## Run it
```bash
terraform init && terraform plan && terraform apply
# create an Entra user:
#   az ad user create --user-principal-name dev@contoso.com --display-name "Dev User" --password <pw>
# create a group + add the user:
#   az ad group create --display-name "Storage-Admins" --mail-nick-name storage-admins
#   az ad group member add --group storage-admins --member-id <dev-object-id>
# grant the GROUP a role on the storage account:
#   az role assignment create --assignee <group-object-id> --role "Storage Blob Data Owner" --scope <storage-account-id>
```

## Clean up
```bash
terraform destroy
#   az ad group delete --group storage-admins ; az ad user delete --id <dev-object-id>
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "User not found" in a role assignment | the `--assignee` must be the user's **object id** (not the UPN) — get it from `az ad user show` |
| Managed identity "has no access" | the **role assignment** is missing, or its **scope** is wrong (must be the storage account or a parent) |
| Trying `azurerm_user` / `azurerm_group` | those resources are **gone in azurerm v5** — use **`az ad` CLI** or the **Microsoft Graph** (a separate provider) for Entra objects |
