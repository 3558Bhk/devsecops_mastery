# EBS Volumes — Terraform how-to

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

**What:** block storage volumes (gp3), snapshots (the backup story), and a volume **restored from a snapshot**.

**Interview angle (SDE3):**
- EBS is **single-AZ** block storage (copy cross-AZ = new volume from snapshot); S3 is cross-AZ by design.
- Volume types: gp3 (default, cheap) → io2 (high IOPS/low latency) → st1 (throughput, data lake).
- Snapshot = incremental, shared across the account/region; a volume from a snapshot = restore/clone.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws ec2 describe-volumes
#         aws ec2 describe-snapshots --owner-ids self
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `IncorrectState` on attach | the volume must be in the **same AZ** as the instance and in `available` state |
| Restored volume is "full of garbage" | it contains exactly what the snapshot had — snapshots are point-in-time, not live |
| Volume outlives the instance | `delete_on_termination` is an **attachment** property — set it where the attachment is declared |
