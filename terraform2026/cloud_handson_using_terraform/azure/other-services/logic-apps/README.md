# Logic Apps — Terraform how-to

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

**What:** a **Logic App** with a **workflow** (Request → Respond) — the visual serverless workflow (as-code).

**Interview angle (SDE3):**
- **Logic Apps** = **serverless workflow** (a visual, event-driven automation: "when X, do Y") — great for **integrations** (connectors to hundreds of SaaS).
- The **workflow** is a **JSON** document (`workflow_schema`) — it's "as code", so it's versionable + Terraform-able (as here).
- **Standard** vs **Consumption** Logic Apps: Standard = more connectors, VNet, scale; Consumption = cheaper, fewer connectors.
- The interview: "When would you use a Logic App vs a Function?" → **Logic App** = multi-step, connector-based, low-code; **Function** = custom code, more control.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az logic workflow list -g rg-lab-logic
#   az logic workflow show -g rg-lab-logic -n workflow-lab
# invoke the workflow: curl -X POST -H "Content-Type: application/json" https://<workflow-endpoint>/runtime/api/... 
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Workflow "404" when invoked | the **trigger** path is wrong (a `Request` trigger exposes a specific URL) — use the workflow's **access endpoint** |
| "Workflow schema invalid" | the `workflow_schema` JSON must be a **valid** Logic Apps schema (the `contentVersion`, `parameters`, `triggers`, `actions` blocks) |
| Connector "not found" | the **connector** isn't available in the region/sku (Standard vs Consumption) — check the connector's **plan** |
