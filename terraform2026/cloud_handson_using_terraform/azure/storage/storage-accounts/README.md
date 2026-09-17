# Azure Storage Accounts — Terraform how-to

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

**What:** a storage account (Standard LRS) + a blob container + a sample blob — the Azure "everything" storage.

**Interview angle (SDE3):**
- An **account** is the container; inside it are **blob** (object), **file** (SMB), **queue**, and **table** services.
- **Replication tiers**: LRS (local), ZRS (zone-redundant), GRS (geo-redundant), RA-GRS (read-access geo). The interview asks "which for a disaster-recovery scenario?" → **RA-GRS**.
- **Access**: SAS tokens (time-limited, scoped), **shared keys** (account-level), and **managed identity** (the modern, no-secret way — see the `identity-mgmt-in-storage` folder).
- **Blob tiers**: Hot / Cool / Cold / Archive (by access frequency) — the "tiering" interview question.

## Run it
```bash
terraform init && terraform plan && terraform apply
# list: az storage container list --account-name $(az storage account list -o tsv --query "[0].name")
# upload: az storage blob upload -f ./file.txt --container-name lab-blobs --name new-blob.txt
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "AuthorizationFailure" from the portal | the account requires a **firewall** rule for your IP, or you need the right **key/SAS/identity** — check the `network_rules` + the access method |
| Account name collision | storage account names are **globally unique** — use a random suffix (as here) |
| "The account was blocked by a firewall rule" | the storage account's firewall blocks the portal/IP — allow your IP or the `VirtualNetwork` rule |
