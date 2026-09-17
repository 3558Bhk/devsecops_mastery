# Project 06 — Remote Backend, State Surgery & Import (Azure)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0

Same lesson as AWS project 06, with the Azure backend: state in a **storage account blob**,
plus a **SAS token** (Azure's way of handing a scoped credential to the backend).

## Concepts practiced
- `azurerm` backend (blob + SAS token) → `../terraform-mastery/02-azure-provider/10-advanced-state-diagnostics-interop.md`
- `terraform state list / show / mv / rm`
- `terraform import`

## Structure

```
project-06-remote-backend-state/
├── 00-bootstrap/        ← step 1: creates the storage account + state container
│   └── main.tf
├── backend.tf           ← tells the MAIN project to store state in the blob
├── main.tf              ← the main project: 2 storage accounts (one for import)
└── outputs.tf
```

## Run it — step by step

**Step 1 — bootstrap (run once):**

```bash
cd project-06-remote-backend-state/00-bootstrap
terraform init && terraform apply
cd ..
```

**Step 2 — get a SAS token for the state container:**

```bash
az storage container generate-sas \
  --name tfstate \
  --account-name tflabstate2026 \
  --permissions rwdl \
  --expiry 2027-01-01T00:00Z \
  --full-uri false
```

This prints something like `?sv=2024-...&sp=rwdl&se=...` — **copy it, including the leading `?`**.

**Step 3 — put it in `backend.tf`:** set `sas_token = "<paste-it>"`.

**Step 4 — run the main project:**

```bash
terraform init          # asks to copy/move state → yes
terraform plan && terraform apply
```

**Step 5 — prove it's remote + state surgery:**

```bash
ls terraform.tfstate            # → No such file (nothing local)
az storage blob list -c tfstate --account-name tflabstate2026 -o table   # your state blob is there

terraform state list
terraform state mv azurerm_storage_account.main azurerm_storage_account.main_v2
# then rename the resource in main.tf to match → terraform plan shows ZERO changes (the magic moment)
terraform state rm azurerm_storage_account.main_v2
```

**Step 6 — import:**

1. Portal → Storage accounts → create `tflablegacy2026` with **Standard / LRS**, in the region `eastus`.
   (It doesn't matter where it lives yet — `terraform import` doesn't care about the RG; the
   `main.tf` slot declares the values Terraform expects, so the plan after import shows no drift.)
2. Adopt it:

```bash
terraform import azurerm_storage_account.legacy tflablegacy2026
terraform plan        # 0 changes: Terraform now manages the existing account
```

## Clean up

```bash
terraform destroy
az storage account delete --name tflablegacy2026 --yes   # the imported one is destroyed by TF, but double-check
az storage account delete --name tflabstate2026 --yes
cd 00-bootstrap && terraform destroy && cd ..
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `Authentication to the storage account failed` | the SAS token expired or was pasted without the leading `?` |
| `init` asks about migrating state and you said no | the backend is configured but local state stays local — re-run `terraform init -migrate-state` |
| After `state mv`, plan wants to create+destroy | rename the resource in `main.tf` to match the new state address |
| SAS token in git | never commit it — keep `backend.tf` with a placeholder and fill it locally (or use a managed identity setup for teams) |
