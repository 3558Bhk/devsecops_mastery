# Azure RSV Backup — Terraform how-to

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

**What:** a **Recovery Services Vault** + a backup **policy** + a **protected VM** — scheduled backups of an Azure VM.

**Interview angle (SDE3):**
- **RSV** (Recovery Services Vault) = where backup **recovery points** are stored; you register a VM, pick a **policy**, and it backs up on schedule.
- A **policy** = schedule (daily/hourly/weekly) + **retention** (daily/weekly/monthly/yearly counts) + optional **instant restore**.
- Backup vs **Snapshot**: backup = scheduled, off-site, recovery-oriented; snapshot = point-in-time, in-region, for quick rollback.
- The DR story: **Regional RSV** (same region) vs **Geo-redundant RSV** (a copy in a paired region) — the interview asks "where does the backup actually live?"

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ VM + vault costs — destroy when done
# verify: az recovery-services protected-vault list -g rg-lab-rsv
#   az recovery-services backup-vault show -g rg-lab-rsv -n rsv-lab
#   az recovery-services backup-policy show -g rg-lab-rsv -n bpol-lab
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Backup "not running" | the **policy** isn't attached to the protected VM (the `backup_policy_id` link) — or the vault is in a **different region** than the VM |
| Retention shorter than you think | the **daily retention count** caps how many daily recovery points you keep — set `retention_daily.count` |
| "Can't restore to the same name" | if the original VM still exists, restore to a **new name** or the **original** with the old one deleted |
