# Project 01 — Your First Storage Account (Azure)

**Difficulty:** ⭐ (complete beginner) · **⏱️ ~30 min** · **Cost:** ~$0 (free tier: 5 GB LRS for 12 months)

Your very first Terraform run on Azure: a resource group + a storage account.

## Concepts practiced
- The `terraform`, `provider`, and the required **`features {}`** block → `../terraform-mastery/02-azure-provider/01-provider-setup-and-authentication.md`
- The `init` → `plan` → `apply` → `destroy` loop
- The state file

## Files in this folder

| File | What it is |
|---|---|
| `main.tf` | provider + resource group + storage account |
| `outputs.tf` | names, location, and the blob endpoint |

## Run it

```bash
cd project-01-first-storage

az login                          # one-time: make sure you're logged in
terraform init                    # downloads the azurerm provider
terraform plan                    # "will CREATE 2 resources" — read it
terraform apply                   # type yes
```

## Verify it

```bash
az resource group list --query "[].name" -o table      # your RG appears
az storage account list --query "[].name" -o table     # your storage account appears
terraform output blob_endpoint                          # the URL that ends in blob.core.windows.net
```

**Look at the state file** (`cat terraform.tfstate | head -30`) — same idea as AWS: it's the memory of your infrastructure.

## Break it (this is the learning)

1. Change `account_tier` from `Standard` to `Premium` → `plan` → it wants to **replace** the account
   (tier is immutable). Read the plan, don't apply, revert.
2. Add a `tags` block with `team = "lab"` → `plan` → in-place **update**. Apply.

## Clean up

```bash
terraform destroy     # destroys the storage account, then the resource group (dependency order)
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `Authentication failed` on `init`/`plan` | `az login` first; check `az account show` |
| `The storage account name is invalid` | 3–24 chars, **lowercase letters and numbers only**, no hyphens |
| `AccountAlreadyExists` | the name is taken globally — add more characters |
| Plan shows the resource group being replaced | you changed `location` — location is immutable on an RG |
