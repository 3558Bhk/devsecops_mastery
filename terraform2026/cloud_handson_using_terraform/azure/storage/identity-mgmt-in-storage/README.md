# Identity Mgmt in Storage — Terraform how-to

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

**What:** a storage account + a **User-Assigned Managed Identity** granted the **Storage Blob Data Owner** role, wired to a VM — the "no secrets" access pattern.

**Interview angle (SDE3):**
- **Managed identities** let a resource (VM, App Service, Function) get an **Azure AD identity** with **no stored credentials** — the platform injects a token.
- The 3 access models, in order of preference: **Managed Identity** (best) > **RBAC role** > **shared key** (worst, account-level secret).
- The grant here is a **role assignment** (RBAC): `Storage Blob Data Owner` on the storage account, scoped to the identity's **principal_id**.
- **System-assigned** (1 per resource, created/deleted with it) vs **User-assigned** (standalone, can be shared across resources) — this one is **User-assigned**.

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ VM costs — destroy when done
# from the VM: az storage blob list --account-name <acct> (uses the VM's identity automatically)
#   or curl -X GET -H "Metadata:sas-token=..." with a token minted by the identity
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "AuthorizationFailure" even with the identity | the **role assignment** is missing or scoped to the wrong **scope** (the storage account) — check `az role assignment list` |
| Role assignment "not found" right after apply | **RBAC propagation** can take a few seconds — wait, then retry |
| VM identity is "SystemAssigned" but the role is on the User-assigned identity | the VM must use the **UserAssigned** identity (set `identity.type = "UserAssigned"` + `user_assigned_identity_id`) |
