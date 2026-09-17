# Azure RSV Restore — Terraform how-to

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

**What:** the **restore** side: a vault + a **fresh target VM** (the restore target) — and the exact commands to restore a recovery point into it.

**Interview angle (SDE3):**
- Restore is an **action**, not a resource — Terraform builds the *target* (vault + replacement VM); the actual restore is a one-off (Portal/CLI/`az`).
- Two restore modes: **original location** (overwrite the VM) vs **new location** (a new VM in a different resource group/VNet — the DR play).
- The DR story: primary region fails → pick the **latest recovery point** in the (geo) RSV → restore to a new VM in the DR region → flip DNS.

## Run it
```bash
terraform init && terraform plan && terraform apply
# RESTORE (the action) — list recovery points, then restore:
#   az recovery-services backup-protected-item show -g rg-lab-rsv -v rsv-lab
#   az recovery-services backup-protected-item list -g rg-lab-rsv -v rsv-lab
#   az recovery-services backup-vault list -g rg-lab-rsv
# Then in the Portal (or `az` equivalent): pick the recovery point → "Restore" →
#   target = the new VM / a new VM name, in the (DR) resource group.
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "No recovery points" | the source VM's **first backup hasn't run yet** (wait for the schedule) or the **policy** isn't attached |
| Restore to the same name fails | the original VM still exists — restore to a **new name** (or delete the original first) |
| Restored VM can't reach the Internet | it's in a **private subnet** — it needs a public IP/NAT, and the **NSG** must allow its traffic |
