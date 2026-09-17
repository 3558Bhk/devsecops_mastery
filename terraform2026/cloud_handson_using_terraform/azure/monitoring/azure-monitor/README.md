# Azure Monitor — Terraform how-to

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

**What:** an **action group** (who gets paged) + a **metric alert** (CPU > 80% for 5 min) + a **Log Analytics workspace** + a log profile.

**Interview angle (SDE3):**
- The 3 alert types: **Metric** (a number crosses a threshold), **Log** (a KQL query), and **Activity/Resource health** (an operation/SMC).
- An **alert rule** (the condition) is separate from an **action group** (the destination: email, SMS, webhook, Function, Logic App, ITSM).
- **Log profile** = which Azure diagnostic logs go to a storage account (the legacy way); the modern way is **Diagnostic Settings** on each resource.
- Azure Monitor = **metrics** (time-series) + **logs** (telemetry) + **workbooks** (dashboards) + **Application Insights** (APM, for code-level tracing).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az monitor metric-alarm list -g rg-lab-monitor
#   az monitor action-group list -g rg-lab-monitor
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Alert fires but nobody is notified | the **action group** has no receiver (or the email is wrong) — the alert rule and the action group are separate resources |
| Alert doesn't fire | the **scope** is wrong (point it at the VM/metric, not the RG), or the **threshold/period** is off — check the metric's actual values in Metrics Explorer |
| "Activity" vs "Metric" confusion | a **Metric alert** watches a number; an **Activity log alert** watches an operation (e.g. "a VM was deleted") — different resources |
