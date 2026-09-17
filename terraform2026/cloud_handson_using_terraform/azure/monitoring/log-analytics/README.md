# Log Analytics — Terraform how-to

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

**What:** a **Log Analytics workspace** + a **solution** (Activity) + a **Log Profile** (which Azure logs flow into a storage account).

**Interview angle (SDE3):**
- A **Log Analytics workspace** = a store for **logs** (diagnostic, audit, activity) + **metrics**; queried with **KQL**.
- A **solution** = a pre-built set of tables + views (e.g. **Activity**, **Security**, **VM Insights**) — it "installs" a schema into the workspace.
- **Log profile** = a subscription-level setting: "send these **first-party** log categories to this storage account" — the modern replacement is a **Diagnostic Setting** on each resource.
- The interview: "How do you centralize logs from all resources?" → **Diagnostic Settings** (per resource or via a policy) → **Log Analytics** (for analysis) + **Storage** (for retention/archive).

## Run it
```bash
terraform init && terraform plan && terraform apply
# query (KQL): in the workspace → Logs →  AzureActivity | take 10
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Workspace is empty (no logs) | no **Diagnostic Setting** / **Log Profile** is sending data to it — add a diagnostic setting on the resource |
| "Activity logs not in the workspace" | install the **Activity** solution (this file does) + make sure the **Log Profile** includes the `Activity` category |
| KQL "table not found" | the **solution** for that table isn't installed (e.g. `Heartbeat` needs the right solution) — solutions add the tables |
