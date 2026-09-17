# Defender for Cloud — Terraform how-to

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

**What:** **Defender for Cloud** enabled at the subscription level + **Defender for Storage** on a storage account (wired to a Log Analytics workspace).

**Interview angle (SDE3):**
- **Defender for Cloud** (formerly **Azure Security Center**) = a **CSPM + CWPP** (security posture + workload protection) with **continuous monitoring** + **recommendations** + **threat protection**.
- The **pricing tier**: **Free** (basic posture) vs **Standard/P1** (full Defender) — the interview: "what's the difference between Free and Standard?"
- **Defender plans** are **per-workload** (Storage, SQL, AKS, Key Vault, etc.) — you enable the plan for each workload you want to protect.
- The interview: "How do you get a security baseline?" → **Defender**'s **recommendations** (a list of misconfigurations) + **policy** (to enforce) + **Blueprints** (a set of policies).

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ Defender costs — destroy when done
# verify: az security center subscription-pricing
#   az security center defender-plan list
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "No recommendations" | the **subscription pricing tier** is **Free** (basic) — enable **Standard** to get the full Defender recommendations |
| A workload "not protected" | the **Defender plan** for that workload (e.g. **Storage**) isn't enabled — enable the plan per workload |
| "Alerts not showing" | the **Log Analytics workspace** isn't wired (Defender needs a workspace for some features) — set the **workspace** on the Defender plan |
