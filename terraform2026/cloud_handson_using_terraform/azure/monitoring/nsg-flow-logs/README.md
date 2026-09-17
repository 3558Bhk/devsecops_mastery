# NSG Flow Logs — Terraform how-to

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

**What:** **NSG flow logs** (every allow/deny decision) → a **storage account** (raw logs) + **Log Analytics** (queryable, with traffic analytics).

**Interview angle (SDE3):**
- **Flow logs** = a record of **every NSG decision** (allow/deny, 5-tuple) — the "why was that traffic blocked?" tool.
- They're **expensive** at scale (every packet tuple) — enable per **NSG**, not per subnet, and set a **retention** + **traffic analytics** (aggregates in Log Analytics).
- Flow logs vs **VNet diagnostic settings**: flow logs = NSG-level decisions; VNet diagnostic = the VNet's counters (packets, bytes).
- The interview: "A user says 'my app can't reach the DB'. How do you find out?" → **NSG flow logs** (was it a deny?) + **NSG effective rules** + the **effective routing table**.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az network watcher flow-log list -g rg-lab-flowlog
#   the raw logs land in the storage account (NetworkWatcher/*) and in the Log Analytics workspace
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Flow logs "not showing" | the **NSG** must be the **target** (`target_resource_id` = the NSG id) — flow logs follow the NSG, not the subnet |
| Logs are huge / expensive | set a **retention** (days) and turn on **traffic analytics** (aggregates) instead of raw per-packet logs |
| "Blocked traffic" but no flow log entry | the traffic was dropped by a **route** (or a **different NSG**) — flow logs only capture **NSG** decisions |
