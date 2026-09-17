# Project 02 — Storage with Variables, Outputs & locals (Azure)

**Difficulty:** ⭐ · **️ ~40 min** · **Cost:** ~$0

Same idea as AWS project 02, plus **`locals`** — computed values that aren't user input.
This is where Azure's naming rules (global uniqueness, character sets) bite you for the first time.

## Concepts practiced
- `variable`, `output`, `terraform.tfvars`, validation → `../terraform-mastery/00-terraform-core/03-variables-outputs-locals-functions.md`
- `locals` — derived values (naming conventions)
- Azure-specific: storage account names are **globally unique, lowercase, no hyphens**

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, environment, location, replication |
| `main.tf` | RG + storage account + two blob containers |
| `outputs.tf` | endpoint, account name, containers |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-02-variables-outputs
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it

```bash
terraform output
az storage container list --account-name $(terraform output -raw storage_account_name) -o table
```

## Break it (this is the learning)

1. `environment = "staging"` in tfvars → `plan` → the account is **replaced** (the name embeds the env). Apply, then revert.
2. `replication = "RA-GRS"` → `plan` → in-place update of the account (replication type *can* change). Apply.
3. Add a container to `var.containers` (e.g. `"audit"`) → `plan` → one new resource, nothing else touched. Apply.

## Clean up

```bash
terraform destroy
rm terraform.tfvars
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `InvalidStorageAccountName` | you allowed uppercase or hyphens — `local.account_name` in main.tf strips them; keep it that way |
| `AccountAlreadyExists` | pick a longer `project` name so the derived name is more unique |
| Container names with uppercase fail | containers *do* allow hyphens, and 3–63 chars; no uppercase |
